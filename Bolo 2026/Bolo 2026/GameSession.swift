//
//  GameSession.swift
//  Bolo 2026
//
//  Wave 7.3 (D88) -- the port's equivalent of `runclient()`/`runserver()`'s driving loop plus
//  `GSXBoloController`'s keyboard-input wiring, unified since this port has no client/server
//  split (D82/RunTick.swift's own header). Owns the live `GameState`, drives `runTick` at the
//  real 50 Hz tick rate (`ticksPerSec`, `Physics.swift:11`), and calls `GameRenderView.render(_:)`
//  after each tick -- `GameRenderView` itself still owns no clock (D82 stands unchanged).
//
//  **Tick-driver mechanism, D41:** a `DispatchSourceTimer` on `.main`, not `Timer`/`RunLoop` --
//  `NSTimer`-family timers stop firing while the run loop is in a tracking mode (e.g. a window-
//  resize drag), a real hazard `GSXBoloController`'s C-era single-threaded model never had to
//  contend with. `DispatchSourceTimer` fires independent of run-loop mode while still executing
//  on the main queue, so touching `@MainActor`-isolated `GameRenderView`/AppKit state from its
//  handler stays concurrency-correct under D79's Swift 6 mode with no relaxed checking to lean on.
//
//  **Exclusivity, D88 §4:** `onSpawn`'s real consequence (`spawn(state:)`) is wired inside
//  `TankTick.swift`'s `tankMoveTick` itself, NOT here -- a closure passed into `runTick(state:
//  &state, ...)` that also captures and mutates that same `state` while the call is active would
//  be a nested exclusive-access violation (Swift's runtime exclusivity check traps). The
//  `onInputFlagsChange`/`onLayMineKeyDown` closures below are safe by contrast: AppKit key events
//  and this timer's fire both run serially on the main thread, but never nested inside each
//  other's call frame, so mutating `state` from either is a plain, non-overlapping access.
//
//  **Single-process, no networking (D73):** `ticksSinceLastUpdate` is `runTick`'s per-player
//  lag-detection input, meant to track elapsed ticks since a remote update -- with no network at
//  all in this slice, it stays a fixed all-zero array for the lone local player for the entire
//  session, which correctly means "never lagged," not a stubbed-out gap.
//
//  **B.7 (D108):** a second path -- hosting -- now exists alongside the single-process one above.
//  `HostGameEngine` (`BoloNet`) drives its *own* tick timer against the *one* `GameState` it owns;
//  running this class's timer too, against a second copy, would be two tickers racing to be the
//  truth for what's supposedly one game (PLANNER's own words at the D108 ruling) -- so on the host
//  path, `start()`/`stop()` delegate entirely to the engine and this class's own `timer` is never
//  created. `state` is set once at `init` from the engine's snapshot and never updated again on
//  this path -- nothing reads it afterward (rendering goes through `onTickRendered` below,
//  straight to `renderView`, not through `self.state`); if that stops being true, `state` needs
//  to become the engine's live copy, not a one-time snapshot. Local input can't touch `state`
//  directly on this path either, for the identical reason `HostGameEngine` itself never lets any
//  thread but its own consumer touch it -- `submitLocalInputChange`/`submitLocalLayMineKeyDown`
//  route it through the engine's merged event stream instead.

import AppKit
import BoloKit
import BoloNet

@MainActor
public final class GameSession {
    public private(set) var state: GameState
    public let renderView: GameRenderView

    private let ticksSinceLastUpdate: [UInt64]
    private var timer: DispatchSourceTimer?
    private let hostEngine: HostGameEngine?

    /// Measured tick-to-tick interval, most recent first, capped to a rolling window -- surfaced
    /// so the completion report can state real jitter instead of asserting the nominal 20ms holds
    /// (D41: "worth measuring, not assumed," same standard as Wave 7.2's rendering benchmark).
    /// Only ever populated on the single-process path -- the host path's cadence is `HostGameEngine`'s
    /// own tick timer, not this class's, so there is nothing of this class's own to measure there.
    public private(set) var recentTickIntervals: [TimeInterval] = []
    private var lastTickTime: DispatchTime?

    public init(initialState: GameState, tilesImage: CGImage, spritesImage: CGImage) {
        self.state = initialState
        self.ticksSinceLastUpdate = Array(repeating: 0, count: initialState.players.count)
        self.hostEngine = nil
        let view = GameRenderView(tilesImage: tilesImage, spritesImage: spritesImage)
        self.renderView = view
        view.render(initialState)

        view.onInputFlagsChange = { [weak self] change in
            guard let self else { return }
            let player = self.state.localPlayer
            self.state.players[player].inputFlags.formUnion(change.set)
            self.state.players[player].inputFlags.subtract(change.clear)
        }
        view.onLayMineKeyDown = { [weak self] in
            guard let self else { return }
            layMineOnKeyDown(state: &self.state)
        }
    }

    /// B.7 (D108): the host path -- renders live off `hostEngine`'s own running state instead of
    /// driving a second, competing tick loop against a second copy of it.
    public init(hostEngine: HostGameEngine, tilesImage: CGImage, spritesImage: CGImage) {
        self.state = hostEngine.state
        self.ticksSinceLastUpdate = []
        self.hostEngine = hostEngine
        let view = GameRenderView(tilesImage: tilesImage, spritesImage: spritesImage)
        self.renderView = view
        view.render(self.state)

        view.onInputFlagsChange = { change in
            hostEngine.submitLocalInputChange(set: change.set, clear: change.clear)
        }
        view.onLayMineKeyDown = {
            hostEngine.submitLocalLayMineKeyDown()
        }
        hostEngine.onTickRendered = { [weak view] renderedState in
            view?.render(renderedState)
        }
    }

    public func start() {
        if let hostEngine {
            hostEngine.start()
            return
        }
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: 1.0 / Double(ticksPerSec), leeway: .milliseconds(0))
        source.setEventHandler { [weak self] in self?.tick() }
        source.resume()
        timer = source
    }

    /// `async` (unlike `start()`) because the host path's real teardown, `HostGameEngine.shutdown()`,
    /// has to disconnect every already-joined player's connection (D102) -- an `await`, so this
    /// can't stay the synchronous call the single-process path alone would need.
    public func stop() async {
        if let hostEngine {
            await hostEngine.shutdown()
            return
        }
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let now = DispatchTime.now()
        if let last = lastTickTime {
            recentTickIntervals.append(Double(now.uptimeNanoseconds - last.uptimeNanoseconds) / 1_000_000_000)
            if recentTickIntervals.count > 200 {
                recentTickIntervals.removeFirst(recentTickIntervals.count - 200)
            }
        }
        lastTickTime = now

        runTick(state: &state, ticksSinceLastUpdate: ticksSinceLastUpdate)
        renderView.render(state)
    }
}
