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
//
//  **B.8 (D113/D114/D116/D117):** a third path -- joining -- alongside single-process and
//  hosting. `tcpSession`/`udpSession` are already-`TCPSession.join`-established, live
//  connections handed in from `JoinGameView`; this class owns their whole post-handshake
//  lifecycle from here. Three independent event sources (this class's own tick timer,
//  `tcpSession`'s `SR*` stream, `udpSession`'s relayed `CLUpdate` stream) all need to mutate
//  `state` -- exactly `HostGameEngine`'s own situation (D95/D96), so this path reuses that same
//  merged-event-stream/single-consumer shape rather than `@MainActor` isolation alone, which a
//  first attempt at this (self-caught, nothing committed from it) proved insufficient: isolation
//  only serializes *synchronous* code, not an `inout state` mutation spanning a long network-wait
//  `await`, which is exactly what three independently-awaiting sources sharing one `state` need
//  guarding against. `TCPSession.receiveOneRawMessage`/`UDPSession.receiveOneRawDatagram` (D117)
//  are the I/O-only producers; `startJoinConsumer`'s own drain loop is the one and only consumer.

import AppKit
import BoloKit
import BoloNet

/// See `GameSession`'s own B.8 header above.
private enum JoinEvent: Sendable {
    case tick
    case tcpMessage(TCPSession.RawMessage)
    case tcpEnded
    case udpDatagram(Data)
    case udpEnded
}

@MainActor
public final class GameSession {
    public private(set) var state: GameState
    public let renderView: GameRenderView

    private let ticksSinceLastUpdate: [UInt64]
    private var timer: DispatchSourceTimer?
    private let hostEngine: HostGameEngine?
    private let tcpSession: TCPSession?
    private let udpSession: UDPSession?
    private var joinContinuation: AsyncStream<JoinEvent>.Continuation?
    private var joinConsumerTask: Task<Void, Never>?
    /// Mirrors `HostGameEngine.localSeq`'s identical role -- this client's own outgoing per-tick
    /// counter, `assembleClUpdate`'s own broadcast cadence gate (`% 5 == 0`, ~10Hz).
    private var localSeq: Int32 = 0

    /// Measured tick-to-tick interval, most recent first, capped to a rolling window -- surfaced
    /// so the completion report can state real jitter instead of asserting the nominal 20ms holds
    /// (D41: "worth measuring, not assumed," same standard as Wave 7.2's rendering benchmark).
    /// Only ever populated on the single-process path -- the host path's cadence is `HostGameEngine`'s
    /// own tick timer, not this class's, so there is nothing of this class's own to measure there.
    public private(set) var recentTickIntervals: [TimeInterval] = []
    private var lastTickTime: DispatchTime?

    /// **1.1 backlog C.4:** the messages panel's own scrollback -- kept here, not on `GameState`,
    /// matching the reference's own design: `printmessage`/`messagesTextView` is a pure display
    /// sink with no simulation effect (`recvclsendmesg`/`recvsrsendmesg`'s own zero-`GameState`-
    /// effect finding, restated in `ChatMessage.swift`'s header). Populated on all three paths --
    /// the host path via `HostGameEngine.onMessageReceived` below, the join path via
    /// `SRDispatchCallbacks.onSendMesg` in `handleJoinEvent`, and the single-process path directly
    /// inside `sendMessage` itself (no relay exists to receive it back through).
    public private(set) var messages: [ChatMessage] = []
    private var nextMessageID: UInt64 = 0

    public init(initialState: GameState, tilesImage: CGImage, spritesImage: CGImage) {
        self.state = initialState
        self.ticksSinceLastUpdate = Array(repeating: 0, count: initialState.players.count)
        self.hostEngine = nil
        self.tcpSession = nil
        self.udpSession = nil
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
        // D137: single-process path -- no other real players to inform, mutate `state` directly,
        // same reasoning as `sendMessage`'s single-process branch.
        view.onBuilderCommand = { [weak self] command, target in
            guard let self else { return }
            queueBuilderCommand(command: command, target: target, player: self.state.localPlayer, state: &self.state)
        }
    }

    /// B.7 (D108): the host path -- renders live off `hostEngine`'s own running state instead of
    /// driving a second, competing tick loop against a second copy of it.
    public init(hostEngine: HostGameEngine, tilesImage: CGImage, spritesImage: CGImage) {
        self.state = hostEngine.state
        self.ticksSinceLastUpdate = []
        self.hostEngine = hostEngine
        self.tcpSession = nil
        self.udpSession = nil
        let view = GameRenderView(tilesImage: tilesImage, spritesImage: spritesImage)
        self.renderView = view
        view.render(self.state)

        view.onInputFlagsChange = { change in
            hostEngine.submitLocalInputChange(set: change.set, clear: change.clear)
        }
        view.onLayMineKeyDown = {
            hostEngine.submitLocalLayMineKeyDown()
        }
        // D137: host path -- routed through `HostGameEngine`'s merged event stream, same
        // reasoning as `onLayMineKeyDown` above. Other connected players learn the host's
        // builder's new position/status through the existing periodic state broadcast (the same
        // mechanism that already keeps `remoteBuilderSmoothers` fed) -- no new broadcast message
        // needed for multiplayer visibility (D137 pre-brief finding).
        view.onBuilderCommand = { command, target in
            hostEngine.submitLocalBuilderCommand(command: command, target: target)
        }
        hostEngine.onTickRendered = { [weak view] renderedState in
            view?.render(renderedState)
        }
        hostEngine.onMessageReceived = { [weak self] message in
            self?.messages.append(message)
        }
    }

    /// **B.8 (D113/D114/D116):** the join path -- `tcpSession`/`udpSession` are already-live,
    /// already-past-the-handshake connections (`TCPSession.join`) handed in by the caller.
    ///
    /// Runs ONLY `tankMoveTick` for the local player's own tank each tick -- turning/
    /// acceleration/position/wall-and-terrain collision, matching what the host already trusts a
    /// client to self-report (D114: the host never validates a client's position at all, so
    /// there's nothing to defer to a round trip for). Deliberately NOT `tankLocalTick`/
    /// `shellTick`/`builderTick` -- touching a pill, building, mining, and shooting all need a
    /// real outbound CL*-message protocol this port doesn't have yet (D116, split to new B.10);
    /// calling those functions here would mutate this client's own *local* copy of shared state
    /// (pills/bases/mines) the host never learns about, an immediate, silent desync. `space`/
    /// `shift` (shoot/lay-mine) are left functionally dead for the same reason -- `inputFlags`
    /// still records them harmlessly (`onInputFlagsChange` below doesn't special-case any bit),
    /// nothing yet reads those two.
    ///
    /// **Known, disclosed, narrow gap even within `tankMoveTick`'s own scope:** it calls
    /// `superboom()`/`smallboom()` (`TankLocalTick.swift`) when the local player's own death
    /// timer crosses `explodeTicks` -- both drop the dying player's onboard pills onto the map,
    /// a `state.pills` mutation the host never learns about either. Narrow (fires once, only on
    /// this client's own death) and not fixable without B.10's same CL*-outbound protocol --
    /// flagged, not blocked on.
    public init(
        tcpSession: TCPSession, udpSession: UDPSession, initialState: GameState,
        tilesImage: CGImage, spritesImage: CGImage
    ) {
        self.state = initialState
        self.ticksSinceLastUpdate = []
        self.hostEngine = nil
        self.tcpSession = tcpSession
        self.udpSession = udpSession
        let view = GameRenderView(tilesImage: tilesImage, spritesImage: spritesImage)
        self.renderView = view
        view.render(initialState)

        view.onInputFlagsChange = { [weak self] change in
            guard let self else { return }
            let player = self.state.localPlayer
            self.state.players[player].inputFlags.formUnion(change.set)
            self.state.players[player].inputFlags.subtract(change.clear)
        }
        // B.10 (D127): the LMINE key's own separate down-edge path — read-only detection only
        // (`detectJoinLMineKeyDown`, TankLocalTick.swift), no local mutation (`state.pills`/
        // `state.bases`/mine count stay exactly as the host's own SR* broadcast last set them).
        view.onLayMineKeyDown = { [weak self] in
            guard let self, let tcpSession = self.tcpSession else { return }
            guard case .dropMine(let x, let y) = detectJoinLMineKeyDown(state: self.state) else { return }
            let message = CLDropMine(x: UInt8(x), y: UInt8(y))
            Task { try? await tcpSession.send(message.encode()) }
        }
        // D137: `onBuilderCommand` deliberately left unset on the join path -- there is no
        // outbound `CL*` builder-command message in the wire protocol yet, the identical B.10
        // gap already disclosed above for shoot/lay-mine ("space/shift ... left functionally
        // dead for the same reason"). Flagged for PLANNER as part of D137's own completion
        // report, not silently narrowed.
    }

    /// **C.0 (D119):** true only on the host path -- a join-side or single-process client has no
    /// authority to kick/ban anyone (matching the reference: only the server-role menu ever calls
    /// `kickplayer()`/`banplayer()`). `PlayerStatusView`'s kick/ban buttons are gated on this
    /// rather than on `hostEngine` itself, keeping `hostEngine`'s own visibility `private` --
    /// `GameSession` stays the one place that knows which of its three paths is active.
    public var canKickBan: Bool { hostEngine != nil }

    /// See `canKickBan` above -- routes through `HostGameEngine`'s own merged-event-stream submit
    /// methods rather than mutating `state` directly, same reasoning as `onInputFlagsChange`'s
    /// host-path branch in the `hostEngine:` initializer.
    public func kickPlayer(_ player: Int) {
        hostEngine?.submitKickPlayer(player)
    }

    /// Same reasoning as `kickPlayer` above, for `submitBanPlayer`.
    public func banPlayer(_ player: Int) {
        hostEngine?.submitBanPlayer(player)
    }

    /// **C.2 (D128):** alliance request, wired across all three of `GameSession`'s paths --
    /// unlike kick/ban this is every player's own right (not host-only), matching the reference's
    /// `requestAlliance:`/`leaveAlliance:` `IBAction`s (`GSXBoloController.m:1308,1350`), which any
    /// client can invoke on itself.
    ///
    /// - Host path: routes through `HostGameEngine`'s merged stream (`submitRequestAlliance`),
    ///   same reasoning as `kickPlayer` above.
    /// - Join path: mutates only a scratch copy of `state` to compute the outgoing mask, then
    ///   sends `CLSetAlliance` directly -- `self.state` is NOT mutated here; the host's own
    ///   eventual `SRSetAlliance` broadcast (`recvSrSetAlliance`, already wired in
    ///   `TCPSession.dispatch`) is what actually updates `state`, matching this path's existing
    ///   "local input is advisory, the host's broadcast is truth" discipline (see this class's
    ///   B.8 header).
    /// - Single-process path: no other real players to inform, so mutate `state` directly.
    public func requestAlliance(_ players: UInt16) {
        if let hostEngine {
            hostEngine.submitRequestAlliance(players: players)
            return
        }
        if let tcpSession {
            var scratch = state
            BoloKit.requestAlliance(withPlayers: players, state: &scratch, onSendSetAlliance: { alliance in
                let message = CLSetAlliance(alliance: alliance)
                Task { try? await tcpSession.send(message.encode()) }
            })
            return
        }
        BoloKit.requestAlliance(withPlayers: players, state: &state)
    }

    /// Same reasoning as `requestAlliance` above, for leaving an alliance.
    public func leaveAlliance(_ players: UInt16) {
        if let hostEngine {
            hostEngine.submitLeaveAlliance(players: players)
            return
        }
        if let tcpSession {
            var scratch = state
            BoloKit.leaveAlliance(withPlayers: players, state: &scratch, onSendSetAlliance: { alliance in
                let message = CLSetAlliance(alliance: alliance)
                Task { try? await tcpSession.send(message.encode()) }
            })
            return
        }
        BoloKit.leaveAlliance(withPlayers: players, state: &state)
    }

    /// **1.1 backlog C.4:** the messages panel's send action, mirroring `sendmessage()`'s own
    /// three-way dispatch (`client.c:6705-6759`) across this port's three paths:
    /// - host: routed through `HostGameEngine`'s merged event stream (`submitLocalSendMessage`),
    ///   same reasoning as `kickPlayer`/`banPlayer` above.
    /// - join: mask computed here (client-side, matching `sendmessage`'s own `switch` -- the
    ///   server/host only ever relays the mask a `CLSendMesg` already carries, never recomputes
    ///   it; confirmed by reading `recvclsendmesg`, `server.c:2059-2087`, which does nothing but
    ///   `ntohs` the mask it was sent), then sent as a real `CLSendMesg` over `tcpSession`. Not
    ///   appended to `messages` here -- the host's own relay (`sendsrsendmesg`'s `sendToMask`)
    ///   includes the sender whenever the sender's own mask bit is set, so it comes back through
    ///   `handleJoinEvent`'s `.tcpMessage` case below, the same round trip a real two-instance
    ///   session has.
    /// - single-process (D73, no networking at all): appended directly -- there is no relay to
    ///   receive it back through, so this is the one path where "send" and "display" are the same
    ///   step rather than two ends of a wire round trip.
    public func sendMessage(text: String, target: MessageTarget) {
        if let hostEngine {
            hostEngine.submitLocalSendMessage(text: text, target: target)
            return
        }
        if let tcpSession {
            let localPlayer = state.localPlayer
            guard state.players.indices.contains(localPlayer) else { return }
            let mask = computeMessageMask(target: target, sender: localPlayer, players: state.players)
            let message = CLSendMesg(to: target.rawValue, mask: mask, text: text)
            Task { try? await tcpSession.send(message.encode()) }
            return
        }
        nextMessageID += 1
        let localPlayer = state.localPlayer
        let name = state.players.indices.contains(localPlayer) ? state.players[localPlayer].name : ""
        messages.append(ChatMessage(id: nextMessageID, player: localPlayer, senderName: name, text: text, to: target.rawValue))
    }

    public func start() {
        if let hostEngine {
            hostEngine.start()
            return
        }
        if let tcpSession, let udpSession {
            startJoinConsumer(tcpSession: tcpSession, udpSession: udpSession)
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
    /// can't stay the synchronous call the single-process path alone would need. The join path's
    /// own teardown needs the same: cancelling `tcpSession`/`udpSession` makes each producer
    /// `Task`'s blocked receive throw into its own already-handled `.tcpEnded`/`.udpEnded` path,
    /// the identical "close the connection, let the producer's own catch end it" mechanism D102
    /// established for `HostGameEngine`.
    public func stop() async {
        if let hostEngine {
            await hostEngine.shutdown()
            return
        }
        timer?.cancel()
        timer = nil
        joinContinuation?.finish()
        joinContinuation = nil
        joinConsumerTask?.cancel()
        joinConsumerTask = nil
        tcpSession?.cancel()
        udpSession?.cancel()
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

        // D125: sound-effect triggers -- see SoundPlayer.swift's own header for exactly which
        // 5 of the 24 names are wired in this time-boxed pass, and why the rest (tankshot/
        // hittank/tree/build/etc., which need new BoloKit callback threading) aren't yet.
        runTick(
            state: &state, ticksSinceLastUpdate: ticksSinceLastUpdate,
            onMineExplosion: { _ in SoundPlayer.shared.play("explosion") },
            onSuperboomTerrain: { _ in SoundPlayer.shared.play("superboom") },
            onExplosion: { _ in SoundPlayer.shared.play("explosion") },
            onSuperboom: { SoundPlayer.shared.play("superboom") },
            onSmallboom: { SoundPlayer.shared.play("explosion") }
        )
        renderView.render(state)
    }

    // MARK: - Join path (B.8)

    /// Starts the tick timer (yielding `.tick` into the merged stream instead of calling `tick()`
    /// directly), the two I/O-only producer `Task`s, and the single consumer `Task` that drains
    /// all three -- see this class's own B.8 header for why a merged stream, not `@MainActor`
    /// isolation alone, is what keeps this safe.
    private func startJoinConsumer(tcpSession: TCPSession, udpSession: UDPSession) {
        guard joinConsumerTask == nil else { return }

        let (stream, continuation) = AsyncStream<JoinEvent>.makeStream()
        self.joinContinuation = continuation

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: 1.0 / Double(ticksPerSec), leeway: .milliseconds(0))
        source.setEventHandler { continuation.yield(.tick) }
        source.resume()
        timer = source

        Task {
            while true {
                do {
                    let message = try await tcpSession.receiveOneRawMessage()
                    continuation.yield(.tcpMessage(message))
                } catch {
                    continuation.yield(.tcpEnded)
                    break
                }
            }
        }

        Task {
            while true {
                do {
                    let data = try await udpSession.receiveOneRawDatagram()
                    continuation.yield(.udpDatagram(data))
                } catch {
                    continuation.yield(.udpEnded)
                    break
                }
            }
        }

        joinConsumerTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self else { return }
                self.handleJoinEvent(event, udpSession: udpSession)
            }
        }
    }

    /// The single consumer -- the only place that ever mutates `state` on the join path.
    private func handleJoinEvent(_ event: JoinEvent, udpSession: UDPSession) {
        switch event {
        case .tick:
            let now = DispatchTime.now()
            if let last = lastTickTime {
                recentTickIntervals.append(Double(now.uptimeNanoseconds - last.uptimeNanoseconds) / 1_000_000_000)
                if recentTickIntervals.count > 200 {
                    recentTickIntervals.removeFirst(recentTickIntervals.count - 200)
                }
            }
            lastTickTime = now

            let localPlayer = state.localPlayer
            let oldTank = state.players[localPlayer].tank
            let old = Pointi(x: Int32(oldTank.x), y: Int32(oldTank.y))

            tankMoveTick(player: localPlayer, state: &state)

            // B.10 (D127): read-only detect-and-send analogue of `enter()`'s pill/base/
            // mined-terrain branches (`detectJoinTileEntry`, TankLocalTick.swift) — never
            // mutates `state`; the eventual mutation arrives later via the host's own SR*
            // broadcast (`.tcpMessage` case below), same protocol latency the reference has.
            let newTank = state.players[localPlayer].tank
            let new = Pointi(x: Int32(newTank.x), y: Int32(newTank.y))
            let outbound = detectJoinTileEntry(new: new, old: old, state: state)
            if !outbound.isEmpty, let tcpSession {
                let bytes = outbound.map { message -> [UInt8] in
                    switch message {
                    case .grabTile(let x, let y):
                        return CLGrabTile(x: UInt8(x), y: UInt8(y)).encode()
                    case .dropBoat(let x, let y):
                        return CLDropBoat(x: UInt8(x), y: UInt8(y)).encode()
                    case .dropMine(let x, let y):
                        return CLDropMine(x: UInt8(x), y: UInt8(y)).encode()
                    }
                }
                Task {
                    for message in bytes {
                        try? await tcpSession.send(message)
                    }
                }
            }

            sendLocalUpdateIfDue(udpSession)
            renderView.render(state)

        case .tcpMessage(let message):
            // Snapshot player names before `dispatch` takes `&state` -- reading `self.state` from
            // inside `onSendMesg` below, while this same call already holds `state` as an
            // exclusive `inout` binding, would be a nested-access violation (same reasoning as
            // `HostGameEngine.swift`'s own `onSendMesg` wiring, `HostGameEngine.swift:264-281`).
            let playerNames = state.players.map(\.name)
            let callbacks = SRDispatchCallbacks(onSendMesg: { [weak self] player, to, text in
                guard let self else { return }
                self.nextMessageID += 1
                let senderIndex = Int(player)
                let name = playerNames.indices.contains(senderIndex) ? playerNames[senderIndex] : ""
                self.messages.append(
                    ChatMessage(id: self.nextMessageID, player: senderIndex, senderName: name, text: text, to: to)
                )
            })
            try? TCPSession.dispatch(message, state: &state, callbacks: callbacks)

        case .udpDatagram(let data):
            udpSession.apply(data, myOwnSeq: localSeq, state: &state)

        case .tcpEnded, .udpEnded:
            // Disconnection -- surfacing this to the user (a visible notice, not a silent
            // freeze, matching D109's own precedent) is the caller's job, not this consumer
            // loop's; no `state` mutation of its own is needed here either way.
            break
        }
    }

    /// Mirrors `HostGameEngine.tick()`'s own `localSeq % 5 == 0` broadcast cadence (~10Hz at this
    /// port's 50Hz tick rate) -- `sendclupdate()` only fires that often in the reference too
    /// (`client.c:485-487`), not every tick. Fire-and-forget (not awaited) since this consumer's
    /// own handling is synchronous -- a failed send is indistinguishable from a lost UDP packet,
    /// nothing this port doesn't already tolerate elsewhere.
    private func sendLocalUpdateIfDue(_ udpSession: UDPSession) {
        localSeq += 1
        guard localSeq % 5 == 0 else { return }
        guard state.players.indices.contains(state.localPlayer) else { return }
        var seq = udpSession.allRemoteSeqsAsUInt32()
        seq[state.localPlayer] = UInt32(bitPattern: localSeq)
        let update = assembleClUpdate(player: state.localPlayer, state: state, seq: seq)
        let bytes = update.encode()
        Task { try? await udpSession.sendLocalUpdate(bytes) }
    }
}
