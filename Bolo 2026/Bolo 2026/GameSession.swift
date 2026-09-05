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

import AppKit
import BoloKit

@MainActor
public final class GameSession {
    public private(set) var state: GameState
    public let renderView: GameRenderView

    private let ticksSinceLastUpdate: [UInt64]
    private var timer: DispatchSourceTimer?

    /// Measured tick-to-tick interval, most recent first, capped to a rolling window -- surfaced
    /// so the completion report can state real jitter instead of asserting the nominal 20ms holds
    /// (D41: "worth measuring, not assumed," same standard as Wave 7.2's rendering benchmark).
    public private(set) var recentTickIntervals: [TimeInterval] = []
    private var lastTickTime: DispatchTime?

    public init(initialState: GameState, tilesImage: CGImage, spritesImage: CGImage) {
        self.state = initialState
        self.ticksSinceLastUpdate = Array(repeating: 0, count: initialState.players.count)
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

    public func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: 1.0 / Double(ticksPerSec), leeway: .milliseconds(0))
        source.setEventHandler { [weak self] in self?.tick() }
        source.resume()
        timer = source
    }

    public func stop() {
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
