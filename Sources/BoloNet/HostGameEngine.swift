import BoloKit
import Network
import os

// MARK: - Milestone B.5b (D96) — the real host-network engine's tick/dgram/accept half
//
// Generalizes D95's merged-event-stream architecture (approved for two branches at B.5's own
// pre-brief) to the three branches this sub-wave actually needs, corrected per D96 before any
// code was written: **one** merged `AsyncStream<HostEngineEvent>`, fed by three lightweight
// producer tasks that do I/O only and never touch `state`, drained by **exactly one** consumer
// `Task` that is the sole thing ever mutating `state`. `runHostAcceptLoop`'s own logic (B.5a) is
// inlined into that consumer's `.newConnection` case rather than run as its own independent Task
// alongside the other two branches -- reusing the logic, not the concurrency shape.
//
// **B.5c (D96 extended, Planner-approved 2026-09-05, `1b85dab`):** TCP `CL*` message dispatch is
// now wired -- a per-player producer `Task` is spawned dynamically from inside the consumer's own
// `.newConnection` handling once `processJoinAttempt` returns `.accepted`, generalizing D96's
// three-fixed-producers shape to "three fixed + N dynamic," approved with no reservation (producer
// *count* was never load-bearing to D96's safety, only "exactly one consumer mutates `state`" is,
// and that's unchanged -- every dynamic producer is still I/O-only, same as the three static ones).
// The producer loops `receiveOneHostMessageBytes` (I/O-only half of the Wave-6.4b
// `receiveAndDispatchOneHostMessage`, split out this sub-wave) and yields `.clMessage`/
// `.clConnectionEnded` into the same merged stream until the connection ends. No app-target/UI
// wiring still (that's Wave 7.2/7.3's own concern).
//
// **`runTick`'s environmental callbacks -- final disposition, all 16 now accounted for, not
// guessed at:**
// - **8 wired to real `SR*` broadcasts**, each traced against `ServerMessages.swift`'s actual
//   field names, not assumed from the callback's own name: `onPause`/`onTimeLimitWarning`/
//   `onBaseControlWarning`/`onCoolPill`/`onReplenishBase`/`onGrow`/`onShouldBroadcastDropPill`
//   (B.5b) plus `onPlayerDisconnected` (B.5c, below).
// - **5 confirmed correctly unwired, not merely undecided** (B.5c pre-brief, read every actual
//   call site rather than guessing from names): `onExplosion`/`onSuperboom`/`onSmallboom`/
//   `onSpawn` (`TankTick.swift:129,135,142,159`) only ever fire inside a block gated on `player ==
//   state.localPlayer` -- the local player's own death/respawn animation, mirroring how a real
//   distributed client animates its own tank's death independently with no wire message (other
//   players learn the new position from the next `CLUpdate`, already broadcast). `onPlayerLagStatusChanged`
//   (`RunTick.swift:203-211`) mirrors `client.c:437-447`'s `client.setplayerstatus` -- read
//   directly, that's a local UI callback, never a network send in the reference either.
// - **3 left unwired, a real pre-existing gap bigger than this sub-wave, split out to B.5d**
//   (Planner-approved 2026-09-05, `1b85dab`): `onMineExplosion`/`onSuperboomTerrain`/`onDropPills`
//   as `runTick`'s own top-level params. `MineChain.swift:43-51`'s own Wave 5.5a header already
//   disclosed this needs threading a causer parameter through `TankLocalTick`/`ShellTick`/
//   `BuilderTick`'s closure signatures, none of which currently have one -- a signature-changing
//   refactor across already-shipped files, not a callback-wiring task. `CLDispatchCallbacks`'s
//   own version of these three (`HostSession.swift:372`) has the identical gap today.
//
// Since `runTick`'s callbacks are synchronous (`(Int) -> Void`, not `async`) but broadcasting
// requires `await`ing into the `HostSessionTable` actor, this queues encoded bytes during the
// synchronous call and flushes them after `runTick` returns -- the same "queue during the
// synchronous call, flush after" shape `HostSession.swift`'s own `PendingBroadcast`/`flush`
// already established for the CL*-dispatch path, not a new pattern.

enum HostEngineEvent {
    case newConnection(NWConnection)
    case dgramPacket([UInt8], NWConnection)
    /// One fully-read (but undecoded) `CL*` message from an already-joined player's own dynamic
    /// producer `Task` (B.5c).
    case clMessage(player: Int, opcode: ClientOpcode, bytes: [UInt8])
    /// The connection for an already-joined player ended abnormally (read error/EOF) rather than
    /// via a clean `.hangUp` opcode -- T-13's "abnormal" disconnect path.
    case clConnectionEnded(player: Int)
    /// **B.7 (D108):** the host's own local keyboard input, submitted from the app's main-thread
    /// key handler via `submitLocalInputChange` -- routed through the merged stream rather than
    /// mutating `state` directly from that thread, since the consumer `Task` mutating `state`
    /// concurrently is exactly the race this type's whole architecture exists to avoid (see header).
    case localInputChanged(set: InputFlags, clear: InputFlags)
    /// Same reasoning as `localInputChanged` above, for `layMineOnKeyDown`'s separate call.
    case localLayMineKeyDown
    /// **D137:** the host's own local builder-mouse-click command, submitted from
    /// `GameRenderView.onBuilderCommand` via `submitLocalBuilderCommand` -- same reasoning as
    /// `localLayMineKeyDown` above: `queueBuilderCommand` takes `state: inout GameState`, so a
    /// UI mouse-click handler on the app's main thread must route through the merged stream
    /// rather than mutating `state` directly.
    case localBuilderCommand(command: BuilderCommandKind, target: Pointi)
    /// **C.0 (D119):** host-only kick/ban, same reasoning as `localInputChanged` above --
    /// `hostKickPlayer`/`hostBanPlayer` (`HostSession.swift:323,345`) take `state: inout GameState`,
    /// so a UI button must route through the merged stream rather than calling either directly.
    case kickPlayer(player: Int)
    case banPlayer(player: Int)
    /// **C.2 (D128):** host's own local alliance request/leave, same reasoning as
    /// `kickPlayer`/`banPlayer` above -- `requestAlliance`/`leaveAlliance` (`SessionLogic.swift`)
    /// take `state: inout GameState`, so a UI button must route through the merged stream rather
    /// than calling either directly.
    case requestAlliance(players: UInt16)
    case leaveAlliance(players: UInt16)
    /// **1.1 (D129):** host-admin pause/resume, allow-join toggle, unban -- same reasoning as
    /// `kickPlayer`/`banPlayer` above, routed through the merged stream since each takes
    /// `state: inout GameState`.
    case pauseResumeServer
    case setAllowJoin(Bool)
    case toggleAllowJoin
    case unbanPlayer(index: Int)
    /// **1.1 backlog C.4:** the host's own outbound chat message, submitted from the messages
    /// panel's send button via `submitLocalSendMessage` -- same "route through the merged stream"
    /// reasoning as `localInputChanged` above (`computeMessageMask` reads `state.players`, so this
    /// can't be computed off-thread against a copy that might already be stale by the time it's
    /// relayed).
    case sendMessage(text: String, target: MessageTarget)
    case tick
}

public final class HostGameEngine: @unchecked Sendable {
    public private(set) var state: GameState

    /// D150(3): the last `tick()`'s per-player connection-staleness snapshot, mirroring
    /// `state`'s own "plain stored property read cross-thread by `GameSession`" precedent
    /// immediately above -- lets the HUD's lag-color indicator read a synchronous value
    /// instead of `await`ing into `table` (a `HostSessionTable` actor) from SwiftUI's
    /// `TimelineView` render path. Set at the same point `tick()` already computes this
    /// array for `runTick`'s own disconnect-eviction consumer (`:443` below) -- no new
    /// computation, just retaining what was previously discarded after one use.
    public private(set) var lastKnownTicksSinceLastUpdate: [UInt64] = []
    public let table: HostSessionTable

    private let listener: HostListener
    private let dgramListener: HostDgramListener
    private var timer: DispatchSourceTimer?
    private var consumerTask: Task<Void, Never>?
    /// Stored so `.newConnection`'s dynamic per-player producer `Task` (B.5c) can yield into the
    /// same merged stream `start()` created -- the three static producers already close over it
    /// as a local; a dynamically-spawned one, created later from inside `handle(_:)`, needs it as
    /// an instance property instead.
    private var continuation: AsyncStream<HostEngineEvent>.Continuation?
    /// Mirrors `client.players[client.player].seq` (`client.c:434`) -- the local player's own
    /// outgoing per-tick counter, incremented every tick regardless of pause/time-limit gating
    /// inside `runTick` itself. A different role from `HostSessionTable.seq`, which tracks what
    /// this host has last *received* from each other player (`decodeDgramServerRelay`'s
    /// `newSeq`) -- the two happen to share a C field name only because the reference's
    /// single-process-per-role model reuses one struct across roles; this port keeps them
    /// separate, matching D39's precedent for exactly this class of C-side conflation.
    private var localSeq: Int32 = 0
    /// **1.1 backlog C.4:** monotonic id for `ChatMessage`s fired via `onMessageReceived`, the
    /// join-side/single-process equivalent of `SwiftUI`'s `Identifiable` needing a stable key --
    /// no wire-level counterpart exists (the reference's own `NSTextView` scrollback has no id at
    /// all, just appended text) so this is purely a display-layer concern invented for this port.
    private var nextMessageID: UInt64 = 0

    /// **v1.3.0 #24:** tracker registration/heartbeat and UPnP port mapping, both best-effort --
    /// see `startNetworkDiscovery`'s own doc comment.
    private var trackerSession: TrackerSession?
    private var trackerHeartbeatTask: Task<Void, Never>?
    private var portMapping: PortMapping?
    private var portMappingTask: Task<Void, Never>?
    private static let discoveryLogger = Logger(subsystem: BoloSignposts.subsystem, category: BoloSignposts.netCategory)

    /// **v1.5.0 #1:** one `FogState` per connected player slot -- see `docs/CONSTRAINTS.md`'s
    /// "Fog-of-war" section for why this lives per-slot on the host rather than per-running-
    /// process as in the C oracle. Empty (and untouched) whenever `state.hiddenMines` is
    /// false, matching the issue's "fully visible remains default" requirement at zero added
    /// cost. Keyed by player slot rather than a `[FogState]` sized `maxPlayers` so an
    /// unconnected slot never allocates a grid it doesn't need.
    private var fogStates: [Int: FogState] = [:]

    /// #62 S4: the last `SRTankStatus` sent to each remote slot, and whether that slot was dead
    /// when it was sent, so `tankStatusSends()` only sends on change and can attach a respawn
    /// teleport on the dead -> alive transition.
    private var lastTankStatus: [Int: SRTankStatus] = [:]
    private var lastTankDead: [Int: Bool] = [:]
    /// #62 S5: the last `SRTankShots` sent to each remote slot (its own shells and explosions),
    /// so `tankShotsSends()` sends only on change -- including one final empty list when the last
    /// shell lands or the last explosion ends, which is what clears the guest's copy.
    private var lastTankShots: [Int: SRTankShots] = [:]

    /// Read-only access to a connected player slot's current `FogState`, for rendering
    /// (Phase 3) and testing. `nil` when `state.hiddenMines` is false or the slot has no
    /// tracked fog state yet.
    public func fogState(for player: Int) -> FogState? {
        fogStates[player]
    }
    /// The vision rect `mover` is *currently* contributing to `observer`'s `FogState`, keyed
    /// `observer * maxPlayers + mover` -- present only while `mover` is both connected and
    /// mutually allied with `observer`. Diffed each tick (`updateFogVision`) against the
    /// current `shouldContribute` status to detect every kind of "started/stopped
    /// contributing vision" transition -- bootstrap, movement, alliance forming/breaking, and
    /// disconnect/kick/ban -- through one generic mechanism, rather than hooking each of
    /// those mutation call sites individually. See `updateFogVision`'s own header for why a
    /// cached *rect* (not just a bool) is required: it's what lets a mover who stops
    /// contributing (disconnected, alliance broken) be correctly `decreaseVis`'d using
    /// wherever they last actually revealed from, not a value re-derived after the fact.
    private var visionSourceRect: [Int: Recti] = [:]

    /// **B.7 (D108):** fired at the end of every `tick()`, once `runTick` has already mutated
    /// `state` for that tick, with a value-type snapshot (never the live `state` itself, which
    /// only the consumer `Task` may ever touch). Hopped onto the main actor here, at the single
    /// call site, rather than leaving that to each caller -- the app's render target
    /// (`GameRenderView`, an `NSView`) must be touched from the main thread, and this is the one
    /// place that knows the callback fires from off-main (the consumer `Task` has no actor
    /// isolation of its own).
    public var onTickRendered: (@MainActor (GameState) -> Void)?

    /// **1.1 backlog C.4 / D154 Wave 3:** fired for chat that includes the host's own slot
    /// *and* for `MSGGAME` system-event lines (roster/capture/alliance/clock/builder). The host
    /// has no socket to itself, so this is the in-process equivalent of receiving those `SR*`
    /// display events back over the wire.
    public var onMessageReceived: (@MainActor (ChatMessage) -> Void)?

    private func emitGameMessage(_ text: String) async {
        nextMessageID += 1
        let message = ChatMessage(
            id: nextMessageID, player: 0, senderName: "", text: text, to: EventLogText.gameTarget
        )
        if let onMessageReceived {
            await onMessageReceived(message)
        }
    }

    public init(initialState: GameState, listener: HostListener, dgramListener: HostDgramListener) {
        self.state = initialState
        self.table = HostSessionTable()
        self.listener = listener
        self.dgramListener = dgramListener
    }

    /// Starts all three producers and the single consumer. Safe to call once; a second call is
    /// a no-op (mirrors `GameSession.start()`'s own idempotence, Wave 7.3).
    public func start() {
        guard consumerTask == nil else { return }

        let (stream, continuation) = AsyncStream<HostEngineEvent>.makeStream()
        self.continuation = continuation

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: 1.0 / Double(ticksPerSec), leeway: .milliseconds(0))
        source.setEventHandler { continuation.yield(.tick) }
        source.resume()
        timer = source

        let acceptConnections = listener.connections
        Task {
            for await connection in acceptConnections {
                continuation.yield(.newConnection(connection))
            }
        }

        let dgramPackets = dgramListener.packets
        Task {
            for await (bytes, connection) in dgramPackets {
                continuation.yield(.dgramPacket(bytes, connection))
            }
        }

        consumerTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    /// **v1.3.0 #24:** wires the two "Announce on Tracker" / "UPnP Port Mapping" host-form toggles
    /// (`HostGameView.swift`) to the already-shipped `registerWithTracker`/`PortMapping` (Wave
    /// 6.5). Separate from `start()` -- which stays synchronous and non-throwing, matching its own
    /// "safe to call once" contract above -- because tracker registration is a real network
    /// handshake. Both halves are best-effort: a nil/empty `trackerHostname` skips tracker
    /// registration entirely (T-5's "no tracker configured is success" precedent,
    /// `TrackerRegistration.swift`), and either half failing (unreachable tracker, no UPnP
    /// gateway) never blocks or tears down hosting -- LAN-only play is still a first-class
    /// outcome.
    ///
    /// `heartbeatInterval` defaults to `TRACKERUPDATESECONDS` (`server.h:20`, 60s) but is
    /// overridable for tests, matching `registerWithTracker`'s own `trackerServerPort` parameter's
    /// existing test-injection precedent.
    public func startNetworkDiscovery(
        trackerHostname: String?, trackerServerPort: UInt16 = BoloNet.trackerPort, advertisedPort: UInt16,
        hostPlayerName: String, mapName: String, upnpEnabled: Bool,
        heartbeatInterval: Duration = .seconds(60)
    ) async {
        if let trackerHostname, !trackerHostname.isEmpty {
            do {
                let session = try await registerWithTracker(
                    hostname: trackerHostname, trackerServerPort: trackerServerPort, advertisedPort: advertisedPort,
                    hostPlayerName: hostPlayerName, mapName: mapName, state: state
                )
                trackerSession = session
                if let session {
                    trackerHeartbeatTask = Task { [weak self] in
                        while !Task.isCancelled {
                            try? await Task.sleep(for: heartbeatInterval)
                            guard !Task.isCancelled, let self else { return }
                            let host = trackerHost(
                                hostPlayerName: hostPlayerName, mapName: mapName, port: advertisedPort, state: self.state
                            )
                            try? await session.sendHeartbeat(host)
                        }
                    }
                }
            } catch {
                Self.discoveryLogger.error("tracker registration failed: \(String(describing: error), privacy: .public)")
            }
        }

        if upnpEnabled {
            do {
                let mapping = try PortMapping(internalPort: advertisedPort)
                portMapping = mapping
                portMappingTask = Task {
                    for await update in mapping.updates {
                        Self.discoveryLogger.debug("UPnP mapping updated: external port \(update.externalPort, privacy: .public)")
                    }
                }
            } catch {
                Self.discoveryLogger.error("UPnP port mapping failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        listener.cancel()
        dgramListener.cancel()
        consumerTask?.cancel()
        consumerTask = nil
        continuation = nil
        trackerHeartbeatTask?.cancel()
        trackerHeartbeatTask = nil
        trackerSession?.cancel()
        trackerSession = nil
        portMappingTask?.cancel()
        portMappingTask = nil
        portMapping?.cancel()
        portMapping = nil
    }

    /// **B.7 (D102/D108):** the fix for the teardown gap PARITY found -- `stop()` alone cancels
    /// `listener`/`dgramListener` (no more *new* connections accepted) and the consumer task, but
    /// never touched a player already registered in `table`, so their `NWConnection`s and the
    /// dynamic per-player producer `Task`s spawned in `handle(_:)`'s `.newConnection` case (above)
    /// kept running indefinitely after `stop()` returned. `table.disconnect(player)` closes the
    /// connection, which makes each producer's own blocked `receiveOneHostMessageBytes` throw --
    /// landing in the existing, already-tested `catch { ...; break }` path, not a new termination
    /// mechanism.
    ///
    /// A separate `async` method, not folded into `stop()` itself, because `table` is an actor and
    /// every existing test call site uses `defer { engine.stop() }` -- `defer` bodies can't
    /// `await`. This is the real, full-teardown entry point a live caller (B.7's "Stop Hosting")
    /// must use; `stop()` alone is only sufficient when leaked connections don't matter (e.g. a
    /// test process about to tear down its whole harness anyway).
    public func shutdown() async {
        for player in 0..<maxPlayers where await table.isConnected(player) {
            await table.disconnect(player)
        }
        stop()
    }

    /// **B.7 (D108):** the host's own local input, safely threaded onto the single consumer --
    /// see `HostEngineEvent.localInputChanged`'s own doc comment. Callable from any thread (the
    /// app's main-thread key handler); a plain `Continuation.yield`, not `async`, matching the
    /// three static producers' own non-blocking yield.
    public func submitLocalInputChange(set: InputFlags, clear: InputFlags) {
        continuation?.yield(.localInputChanged(set: set, clear: clear))
    }

    /// Same reasoning as `submitLocalInputChange` above, for `layMineOnKeyDown`'s separate call.
    public func submitLocalLayMineKeyDown() {
        continuation?.yield(.localLayMineKeyDown)
    }

    /// **D137:** same reasoning as `submitLocalLayMineKeyDown` above, for a builder-tool mouse
    /// click on the host's own local player.
    public func submitLocalBuilderCommand(command: BuilderCommandKind, target: Pointi) {
        continuation?.yield(.localBuilderCommand(command: command, target: target))
    }

    /// **C.0 (D119):** host-only kick, routed through the merged stream -- see
    /// `HostEngineEvent.kickPlayer`'s own doc comment for why this can't call `hostKickPlayer`
    /// directly.
    public func submitKickPlayer(_ player: Int) {
        continuation?.yield(.kickPlayer(player: player))
    }

    /// Same reasoning as `submitKickPlayer` above, for `hostBanPlayer`.
    public func submitBanPlayer(_ player: Int) {
        continuation?.yield(.banPlayer(player: player))
    }

    /// **C.2 (D128):** host-local alliance request, routed through the merged stream -- see
    /// `HostEngineEvent.requestAlliance`'s own doc comment.
    public func submitRequestAlliance(players: UInt16) {
        continuation?.yield(.requestAlliance(players: players))
    }

    /// Same reasoning as `submitRequestAlliance` above, for leaving an alliance.
    public func submitLeaveAlliance(players: UInt16) {
        continuation?.yield(.leaveAlliance(players: players))
    }

    /// **1.1 (D129):** host-only manual pause/resume toggle -- `pauseresumegame()`/
    /// `togglejoingame()` (`bolo.c`)'s Swift entry points, same reasoning as `submitKickPlayer`
    /// above.
    public func submitPauseResumeServer() {
        continuation?.yield(.pauseResumeServer)
    }

    /// Same reasoning as `submitPauseResumeServer` above, for `setallowjoinserver`.
    public func submitSetAllowJoin(_ allowJoin: Bool) {
        continuation?.yield(.setAllowJoin(allowJoin))
    }

    /// Same reasoning as `submitPauseResumeServer` above, for `togglejoinserver`.
    public func submitToggleAllowJoin() {
        continuation?.yield(.toggleAllowJoin)
    }

    /// Same reasoning as `submitPauseResumeServer` above, for `unbanplayer` -- `index` is
    /// positional into `state.bannedPlayers`, not a player slot (see `SessionLogic.unbanPlayer`'s
    /// own doc comment).
    public func submitUnbanPlayer(index: Int) {
        continuation?.yield(.unbanPlayer(index: index))
    }

    /// **1.1 backlog C.4:** the messages panel's own send action -- see `HostEngineEvent.sendMessage`'s
    /// doc comment for why this can't compute the mask/relay directly from the caller's thread.
    public func submitLocalSendMessage(text: String, target: MessageTarget) {
        continuation?.yield(.sendMessage(text: text, target: target))
    }

    /// The single consumer -- the only place in this type that ever mutates `state`.
    private func handle(_ event: HostEngineEvent) async {
        switch event {
        case .newConnection(let connection):
            // Inlined from `runHostAcceptLoop` (B.5a) -- same call, just made from inside this
            // engine's single consumer instead of its own independent Task.
            // v1.5.0 #1: `fogStates` is `inout` here -- `processJoinAttempt` seeds the
            // joining player's initial spawn-reveal `FogState` *before* it encodes and sends
            // the map (`HostListener.swift`'s own doc comment on that ordering), so the very
            // first map send is already redacted.
            let outcome = await processJoinAttempt(
                connection: connection, serializer: listener.serializer, state: &state, table: table,
                fogStates: &fogStates
            )
            // B.5c: on a successful join, spawn this player's own dynamic producer `Task` --
            // I/O-only (just `receiveOneHostMessageBytes`, never touches `state`), matching the
            // three static producers' own discipline. Reads the same `connection`
            // `processJoinAttempt` already registered into `table` for this player.
            if case .accepted(let player, let rejoin) = outcome {
                if state.players.indices.contains(player) {
                    let name = state.players[player].name
                    await emitGameMessage(rejoin ? EventLogText.rejoined(name) : EventLogText.joined(name))
                }
                let continuation = self.continuation
                Task {
                    while true {
                        do {
                            let (opcode, bytes) = try await receiveOneHostMessageBytes(from: connection)
                            continuation?.yield(.clMessage(player: player, opcode: opcode, bytes: bytes))
                            if opcode == .hangUp { break }
                        } catch {
                            continuation?.yield(.clConnectionEnded(player: player))
                            break
                        }
                    }
                }
            }

        case .dgramPacket(let bytes, let connection):
            // Already fully built (`HostDgramListener.swift`) -- decode, apply, relay in one call.
            await processDgramPacket(bytes: bytes, from: connection, state: &state, table: table)

        case .clMessage(let player, let opcode, let bytes):
            // A decode failure here means the bytes were framing-correct (the producer already
            // read the right length for this opcode) but logically invalid -- treat it the same
            // as a dead connection (abnormal disconnect) rather than silently ignoring a message
            // and leaving the connection's read position potentially desynced.
            // Snapshot the two fields `onSendMesg` below needs to read *before* `state` goes
            // into `dispatchHostMessage`'s own `&state` exclusive-access window -- the callback
            // fires synchronously from inside that call, so reading `self.state` from within it
            // (rather than a value captured beforehand) would be the identical nested-access
            // violation this file's own header already flags for `onSpawn` above.
            let localPlayerIndex = state.localPlayer
            let playerNames = state.players.map(\.name)
            do {
                try await dispatchHostMessage(
                    opcode: opcode, bytes: bytes, player: player, state: &state, table: table,
                    callbacks: CLDispatchCallbacks(onSendMesg: { [weak self] sender, to, mask, text in
                        guard let self, mask & (1 << localPlayerIndex) != 0 else { return }
                        self.nextMessageID += 1
                        let senderIndex = Int(sender)
                        let name = playerNames.indices.contains(senderIndex) ? playerNames[senderIndex] : ""
                        let message = ChatMessage(id: self.nextMessageID, player: senderIndex, senderName: name, text: text, to: to)
                        if let onMessageReceived = self.onMessageReceived {
                            Task { await onMessageReceived(message) }
                        }
                    }, onPrintMessage: { [weak self] text in
                        guard let self else { return }
                        self.nextMessageID += 1
                        let message = ChatMessage(
                            id: self.nextMessageID, player: 0, senderName: "", text: text, to: EventLogText.gameTarget
                        )
                        if let onMessageReceived = self.onMessageReceived {
                            Task { await onMessageReceived(message) }
                        }
                    }),
                    fogStates: fogStates
                )
            } catch {
                let name = player < playerNames.count ? playerNames[player] : ""
                await handlePlayerDisconnect(player: player, reason: .abnormal, state: &state, table: table)
                await emitGameMessage(EventLogText.disconnected(name))
                return
            }
            if opcode == .hangUp {
                let name = player < playerNames.count ? playerNames[player] : ""
                await handlePlayerDisconnect(player: player, reason: .normal, state: &state, table: table)
                await emitGameMessage(EventLogText.left(name))
            }

        case .clConnectionEnded(let player):
            // A lag eviction (`RunTick` step 4) already marked the player disconnected, reported
            // it, and closed their TCP itself; that close lands here as a second "connection
            // ended". Report a departure once.
            guard state.players.indices.contains(player), state.players[player].connected else {
                Self.discoveryLogger.notice("TCP ended for slot \(player), already disconnected")
                return
            }
            Self.discoveryLogger.notice("TCP ended for slot \(player): disconnecting")
            let name = state.players.indices.contains(player) ? state.players[player].name : ""
            await handlePlayerDisconnect(player: player, reason: .abnormal, state: &state, table: table)
            await emitGameMessage(EventLogText.disconnected(name))

        case .localInputChanged(let set, let clear):
            state.players[state.localPlayer].inputFlags.formUnion(set)
            state.players[state.localPlayer].inputFlags.subtract(clear)

        case .localLayMineKeyDown:
            var planted: Pointi?
            layMineOnKeyDown(state: &state, onMine: { planted = $0 })
            // A hidden mine is never announced: remote players learn of it by proximity reveal.
            if let planted, !state.hiddenMines {
                await table.sendToAll(SRDropMine(player: UInt8(state.localPlayer), x: UInt8(planted.x), y: UInt8(planted.y)).encode())
            }

        case .localBuilderCommand(let command, let target):
            queueBuilderCommand(command: command, target: target, player: state.localPlayer, state: &state)

        case .kickPlayer(let player):
            let name = state.players.indices.contains(player) ? state.players[player].name : ""
            await hostKickPlayer(player: player, state: &state, table: table)
            await emitGameMessage(EventLogText.kicked(name))

        case .banPlayer(let player):
            let name = state.players.indices.contains(player) ? state.players[player].name : ""
            let wasConnected = state.players.indices.contains(player) && state.players[player].connected
            await hostBanPlayer(player: player, state: &state, table: table)
            if wasConnected {
                await emitGameMessage(EventLogText.banned(name))
            }

        case .requestAlliance(let players):
            let localPlayer = state.localPlayer
            if state.players.indices.contains(localPlayer) {
                for line in EventLogText.localAllianceRequestMessages(
                    withPlayers: players, localPlayer: localPlayer,
                    previousAlliance: state.players[localPlayer].alliance, players: state.players
                ) {
                    await emitGameMessage(line)
                }
            }
            var broadcast: [UInt8]?
            requestAlliance(withPlayers: players, state: &state, onSendSetAlliance: { alliance in
                broadcast = SRSetAlliance(player: UInt8(localPlayer), alliance: alliance).encode()
            })
            if let broadcast {
                await table.sendToAllExcept(localPlayer, broadcast)
            }

        case .leaveAlliance(let players):
            let localPlayer = state.localPlayer
            if state.players.indices.contains(localPlayer) {
                for line in EventLogText.localAllianceLeaveMessages(
                    withPlayers: players, localPlayer: localPlayer,
                    previousAlliance: state.players[localPlayer].alliance, players: state.players
                ) {
                    await emitGameMessage(line)
                }
            }
            var broadcast: [UInt8]?
            leaveAlliance(withPlayers: players, state: &state, onSendSetAlliance: { alliance in
                broadcast = SRSetAlliance(player: UInt8(localPlayer), alliance: alliance).encode()
            })
            if let broadcast {
                await table.sendToAllExcept(localPlayer, broadcast)
            }

        case .pauseResumeServer:
            await hostPauseResumeServer(state: &state, table: table)

        case .setAllowJoin(let allowJoin):
            setAllowJoin(allowJoin, state: &state)

        case .toggleAllowJoin:
            toggleAllowJoin(state: &state)

        case .unbanPlayer(let index):
            unbanPlayer(index: index, state: &state)

        case .sendMessage(let text, let target):
            let sender = state.localPlayer
            guard state.players.indices.contains(sender) else { break }
            let mask = computeMessageMask(target: target, sender: sender, players: state.players)
            let bytes = SRSendMesg(player: UInt8(sender), to: target.rawValue, text: text).encode()
            await table.sendToMask(UInt16(bitPattern: mask), bytes)
            // The host has no socket to itself, so the "sender receives their own message back"
            // half of `sendToMask`'s real network round trip (see `onMessageReceived`'s own doc
            // comment) has to be done directly here instead.
            if (UInt16(bitPattern: mask) & (1 << sender)) != 0 {
                nextMessageID += 1
                let message = ChatMessage(
                    id: nextMessageID, player: sender, senderName: state.players[sender].name,
                    text: text, to: target.rawValue
                )
                if let onMessageReceived {
                    await onMessageReceived(message)
                }
            }

        case .tick:
            await tick()
        }
    }

    private func tick() async {
        var pending: [[UInt8]] = []
        // v1.5.0 #1: terrain-affecting tick-driven broadcasts (regrowth, flood, mine-chain
        // detonations) get masked instead of sent to everyone -- flushed separately below,
        // after `runTick` returns. Snapshotted before `runTick(state: &state, ...)` takes
        // exclusive access to `state`, since these callbacks fire *during* that call
        // (matches `dispatchHostMessage`'s own identical fix, `HostSession.swift`) --
        // `fogStates` itself is a different property, safe to read live.
        var maskedPending: [(mask: UInt16, bytes: [UInt8])] = []
        let hiddenMinesSnapshot = state.hiddenMines
        let localPlayerSnapshot = state.localPlayer
        // B.5c: `RunTick.swift`'s own step 4 already drops onboard pills (via `onShouldBroadcastDropPill`,
        // already wired above) and sets `connected = false` for a lag-timed-out player BEFORE
        // firing `onPlayerDisconnected` -- this callback's only remaining job is the network-side
        // half `handlePlayerDisconnect` would otherwise do, NOT that function itself (calling it
        // would re-run `removePlayer`'s own drop-pills logic a second time). Collected separately
        // from `pending` since it needs `table.disconnect`, not just a broadcast.
        var disconnectedPlayers: [Int] = []
        // D150 continuation (PARITY finding): without this, `table`'s slot for
        // `state.localPlayer` never advances and `RunTick.swift`'s 9-second lag-eviction loop
        // (below, via `ticksSinceLastUpdate`) self-evicts the host in every hosted game -- the
        // exact defect PARITY found in `5c3c605`. Refreshing here, unconditionally every tick, is
        // a deliberate divergence from the oracle's own cadence, not an attempt to claim exact
        // equivalence: `server.c:672` only refreshes `lastupdate` when a CLUpdate is actually
        // *received*, which for a real client (including the host's own loopback-socket
        // connection to its own server, per PLANNER's ruling) only happens at `client.c:485-487`'s
        // 10 Hz send cadence -- the same cadence this port's own outbound self-CLUpdate already
        // uses below (`localSeq % 5 == 0`, line ~531). That site was tried first and rejected: it
        // runs after this function's own `ticksSinceLastUpdate` snapshot (just below) within the
        // *same* tick, so a refresh placed there is invisible to that tick's own eviction check --
        // structurally too late, not just a cadence difference. Refreshing at 50 Hz (every tick)
        // instead of 10 Hz is strictly fresher than the oracle, never staler, so it can only ever
        // *prevent* an eviction the oracle itself would also not perform -- confirmed via the
        // negative-control test PARITY suggested (`HostGameEngineTests.swift`'s
        // `hostGameEngineDisconnectsALaggedPlayerViaTheTickTimer`, manual seed line removed).
        // `state.players.indices.contains` (not `table`'s own `maxPlayers`-sized `slots`, which is
        // always >= `state.players.count`) is the stricter of the two possible bounds checks.
        if state.players.indices.contains(state.localPlayer) {
            await table.setLastUpdate(state.ticks, for: state.localPlayer)
        }
        let ticksSinceLastUpdate = await table.allTicksSinceLastUpdate(currentTick: state.ticks)
        lastKnownTicksSinceLastUpdate = ticksSinceLastUpdate

        var pendingGameMessages: [String] = []
        let oldPillOwners = state.pills.map(\.owner)
        let oldBaseOwners = state.bases.map(\.owner)
        let oldBuilderStatus = state.players.map(\.builderStatus)
        let playerNames = state.players.map(\.name)

        let terrainBeforeTick = state.terrain.storage
        let tickSignpost = BoloSignposts.tick.beginInterval(BoloSignposts.runTickName)
        runTick(
            state: &state,
            ticksSinceLastUpdate: ticksSinceLastUpdate,
            onPlayerDisconnected: { player in disconnectedPlayers.append(player) },
            onPause: { seconds in pending.append(SRPause(pause: UInt8(seconds)).encode()) },
            onTimeLimitWarning: { seconds in
                pending.append(SRTimeLimit(timeRemaining: UInt16(seconds)).encode())
                pendingGameMessages.append(EventLogText.timeLimitRemaining(seconds))
            },
            onBaseControlWarning: { seconds in
                pending.append(SRBaseControl(timeLeft: UInt16(seconds)).encode())
                pendingGameMessages.append(EventLogText.baseControlRemaining(seconds))
            },
            onCoolPill: { pill in pending.append(SRCoolPill(pill: UInt8(pill)).encode()) },
            onReplenishBase: { base in pending.append(SRReplenishBase(base: UInt8(base)).encode()) },
            onGrow: { [weak self] x, y in
                let mask = terrainVisibilityMask(x: x, y: y, hiddenMines: hiddenMinesSnapshot, fogStates: self?.fogStates ?? [:])
                maskedPending.append((mask, SRGrow(x: UInt8(x), y: UInt8(y)).encode()))
            },
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode())
            },
            onShouldBroadcastSmallBoom: { [weak self] player, x, y in
                let mask = terrainVisibilityMask(x: x, y: y, hiddenMines: hiddenMinesSnapshot, fogStates: self?.fogStates ?? [:])
                maskedPending.append((mask, SRSmallBoom(player: player, x: UInt8(x), y: UInt8(y)).encode()))
            },
            onShouldBroadcastFlood: { [weak self] x, y in
                let mask = terrainVisibilityMask(x: x, y: y, hiddenMines: hiddenMinesSnapshot, fogStates: self?.fogStates ?? [:])
                maskedPending.append((mask, SRFlood(x: UInt8(x), y: UInt8(y)).encode()))
            },
            onPrintMessage: { pendingGameMessages.append($0) },
            onMine: { point in
                // Same rule as `.localLayMineKeyDown`: a hidden mine is never announced.
                guard !hiddenMinesSnapshot else { return }
                pending.append(SRDropMine(player: UInt8(localPlayerSnapshot), x: UInt8(point.x), y: UInt8(point.y)).encode())
            }
        )
        BoloSignposts.tick.endInterval(BoloSignposts.runTickName, tickSignpost)

        // Terrain the host's own simulation changed this tick (mine detonations, builder work,
        // shells): `runTick`'s terrain hooks are sound-only or unwired (the documented B.5d gap), so
        // remote players were never told. Send each changed tile as an absolute update to whoever can
        // see it, redacting mines when Hidden Mines is on. Only this tick's own changes appear here:
        // remote players' actions are applied by `dispatchHostMessage` outside this window and
        // broadcast themselves.
        if state.terrain.storage != terrainBeforeTick {
            for index in state.terrain.storage.indices where state.terrain.storage[index] != terrainBeforeTick[index] {
                let x = index % 256
                let y = index / 256
                let real = Terrain(rawValue: state.terrain.storage[index]) ?? .sea
                let sent = hiddenMinesSnapshot ? unminedTerrain(real) : real
                let mask = terrainVisibilityMask(x: x, y: y, hiddenMines: hiddenMinesSnapshot, fogStates: fogStates)
                maskedPending.append((mask, SRRevealTerrain(x: UInt8(x), y: UInt8(y), terrain: UInt8(sent.rawValue)).encode()))
            }
        }

        // Same B.5d gap as terrain above, for pill/base ownership: `grabTile` (the tile-entry
        // capture path host-simulated remote players now also run through `tankLocalTick`, per
        // #59/#62) mutates `state.pills`/`state.bases` directly with no broadcast hook -- unlike
        // `recvClGrabTile`, the message-driven twin (`HostSession.swift`), which does broadcast
        // `SRCapturePill`/`SRCaptureBase`. Diffs the same before-tick snapshots already captured
        // above for the chat-message diff (`EventLogText.captureMessages` below). Index+owner is
        // enough on the wire -- `recvSrCapturePill`/`recvSrCaptureBase` already reset armour/
        // shells/mines themselves on receipt, matching what `grabTile` just did locally. Not
        // visibility-masked: pills/bases are never fog-hidden (only mines are), matching
        // `recvClGrabTile`'s own unmasked `.all` broadcast.
        for pill in state.pills.indices where state.pills[pill].owner != oldPillOwners[pill] {
            pending.append(SRCapturePill(pill: UInt8(pill), owner: state.pills[pill].owner).encode())
        }
        for base in state.bases.indices where state.bases[base].owner != oldBaseOwners[base] {
            pending.append(SRCaptureBase(base: UInt8(base), owner: state.bases[base].owner).encode())
        }

        var statusSends: [(player: Int, bytes: [UInt8])] = []
        if state.hostSimulatesRemotePlayers {
            statusSends = tankStatusSends() + tankShotsSends()
        }

        var fogReveals: [(player: Int, bytes: [UInt8])] = []
        if state.hiddenMines {
            fogReveals = updateFogVision()
        }

        pendingGameMessages.append(contentsOf: EventLogText.captureMessages(
            previousPillOwners: oldPillOwners, pills: state.pills,
            previousBaseOwners: oldBaseOwners, bases: state.bases,
            players: state.players
        ))
        for i in state.players.indices {
            if oldBuilderStatus[i] != .parachute, state.players[i].builderStatus == .parachute {
                let name = i < playerNames.count ? playerNames[i] : state.players[i].name
                pendingGameMessages.append(EventLogText.lostBuilder(name))
            }
        }

        for bytes in pending {
            await table.sendToAll(bytes)
        }
        for (mask, bytes) in maskedPending {
            await table.sendToMask(mask, bytes)
        }
        for (player, bytes) in statusSends {
            await table.send(bytes, to: player)
        }
        for (player, bytes) in fogReveals {
            await table.send(bytes, to: player)
        }

        for player in disconnectedPlayers {
            // Mirrors `handlePlayerDisconnect`'s own `.abnormal` broadcast + table cleanup
            // (`HostSession.swift:310,312`) -- NOT a call to that function itself, see above.
            let name = player < playerNames.count ? playerNames[player] : ""
            let silentTicks = player < ticksSinceLastUpdate.count ? ticksSinceLastUpdate[player] : 0
            Self.discoveryLogger.error("lag eviction: slot \(player) sent no accepted UDP update for \(silentTicks) ticks")
            await table.sendToAllExcept(player, SRPlayerDisc(player: UInt8(player)).encode())
            await table.disconnect(player)
            pendingGameMessages.append(EventLogText.disconnected(name))
        }

        for text in pendingGameMessages {
            await emitGameMessage(text)
        }

        // B.7 (D108): fires every tick, including paused/time-limit-reached ticks (the guard
        // below returns *after* this) -- the app should keep rendering a paused game, not freeze
        // on its last pre-pause frame.
        if let onTickRendered {
            let snapshot = state
            await MainActor.run { onTickRendered(snapshot) }
        }

        // D98 (PARITY finding): `runclient()`'s early return (`client.c:430-434`,
        // `if (client.timelimitreached || client.basecontrolreached || client.pause)`) skips
        // `seq++`/`sendclupdate()` entirely while paused or once time-limit is reached --
        // `runTick` already gates its own gameplay simulation on pause (`RunTick.swift:76-84`)
        // but this `localSeq`/broadcast section, being this port's first real caller with its own
        // `seq`/cadence, never re-joined that gate. Pause and time-limit-reached are both safe to
        // re-derive here (pause is already an explicit `GameState` field per D39; time-limit-reached
        // is monotonic -- `ticks` only increases and `timeLimit` is static, so once reached it
        // stays reached, matching C's one-way latch exactly). **Base-control-reached is
        // deliberately NOT re-derived here** -- unlike time limit, `state.baseControlCounter` can
        // reset to 0 (`RunTick.swift`'s domination-counter logic, the "left untouched vs. reset to
        // 0" trap already documented there) if alliance/ownership changes after the threshold was
        // first crossed, so `counter >= threshold` would un-freeze broadcasting the moment that
        // happens -- but C's `client.basecontrolreached` is a one-way latch that, once set, never
        // clears. Reproducing that correctly needs an actual latch field in `GameState`, not a
        // one-line guard; flagged for Planner rather than guessed at silently.
        let paused = state.serverPauseTicks != 0 || state.clientPauseDisplaySeconds != 0
        // D99 (PARITY finding): `RunTick.swift:100-105` is a two-phase split, not one test --
        // `ticks == limitTicks` still runs a real simulated tick (fires `onTimeLimitWarning(0)`,
        // increments `ticks`, but does NOT skip this call's own gameplay/broadcast); only
        // `ticks > limitTicks` is actually frozen. `>=` here collapsed that split and suppressed
        // the last genuinely-simulated tick's broadcast one tick early. `>` matches
        // `RunTick.swift:104`'s own freeze condition exactly.
        let timeLimitReached = state.timeLimit > 0
            && Int(state.ticks) > Int(ticksPerSec) * state.timeLimit
        guard !paused, !timeLimitReached else { return }

        // The host's own outbound `CLUpdate` (`assembleClUpdate`, `CLUpdateCodec.swift`) --
        // `client.players[client.player].seq++` happens every tick (`client.c:434`), but
        // `sendclupdate()` itself only fires `if (seq % 5 == 0)` (`client.c:485-487`), confirmed
        // by reading the real source rather than assuming "every tick" -- roughly 10 Hz at this
        // port's 50 Hz tick rate, not 50 Hz.
        localSeq += 1
        guard localSeq % 5 == 0 else { return }
        guard state.players.indices.contains(state.localPlayer) else { return }
        let netSignpost = BoloSignposts.net.beginInterval(BoloSignposts.clUpdateName)
        // The host's own seq must ride in its own slot of the header: nothing else ever writes
        // it (`setSeq` is otherwise only called for guests that send), so it stayed 0 and every
        // guest dropped every host update as not newer (`isNewerSeq(0, than: 0)`).
        await table.setSeq(localSeq, for: state.localPlayer)
        let seqSnapshot = await table.allSeqsAsUInt32()
        let update = assembleClUpdate(player: state.localPlayer, state: state, seq: seqSnapshot)
        let bytes = update.encode()
        for player in 0..<maxPlayers where player != state.localPlayer {
            await table.sendDgram(bytes, to: player)
        }
        BoloSignposts.net.endInterval(BoloSignposts.clUpdateName, netSignpost)
    }


    /// #62 S4: each connected remote's own authoritative combat state, as `SRTankStatus`, sent
    /// only when it differs from the last one sent to that slot (so death, damage, firing, kick
    /// and refuel all go out immediately, and an idle tank costs nothing). A dead -> alive
    /// transition (host-side respawn) attaches the new position as a teleport, since the guest
    /// owns its own movement and would otherwise never learn where the host respawned it.
    private func tankStatusSends() -> [(player: Int, bytes: [UInt8])] {
        var sends: [(player: Int, bytes: [UInt8])] = []
        for player in state.players.indices where player != state.localPlayer {
            guard state.players[player].connected else {
                lastTankStatus[player] = nil
                lastTankDead[player] = nil
                continue
            }
            let p = state.players[player]
            let stats = state.localStats[player]
            let respawned = lastTankDead[player] == true && !p.dead
            let status = SRTankStatus(
                armour: UInt8(clamping: max(stats.armour, 0)), shells: UInt8(clamping: max(stats.shells, 0)),
                mines: UInt8(clamping: max(p.mines, 0)), trees: UInt8(clamping: max(p.trees, 0)),
                range: stats.range, dead: p.dead, boat: p.boat, kickDir: p.kickDir, kickSpeed: p.kickSpeed,
                teleport: respawned ? SRTankStatus.Teleport(x: p.tank.x, y: p.tank.y, dir: p.dir) : nil
            )
            lastTankDead[player] = p.dead
            if lastTankStatus[player] != status {
                lastTankStatus[player] = status
                sends.append((player, status.encode()))
            }
        }
        return sends
    }

    /// #62 S5: each connected remote's own in-flight shells and explosions as `SRTankShots`, sent
    /// only when they differ from the last list sent to that slot. The host is the only simulator
    /// of these, so the guest just applies what arrives (a shell moves every tick, so a flying
    /// shell means one small message per tick; nothing is sent while there are none).
    private func tankShotsSends() -> [(player: Int, bytes: [UInt8])] {
        var sends: [(player: Int, bytes: [UInt8])] = []
        for player in state.players.indices where player != state.localPlayer {
            guard state.players[player].connected else {
                lastTankShots[player] = nil
                continue
            }
            let p = state.players[player]
            let shots = SRTankShots(
                shells: p.shells.map {
                    SRTankShots.ShellEntry(x: $0.point.x, y: $0.point.y, dir: $0.dir, range: $0.range, boat: $0.boat, pill: $0.pill)
                },
                explosions: p.explosions.map {
                    SRTankShots.ExplosionEntry(x: $0.point.x, y: $0.point.y, counter: UInt8(clamping: max($0.counter, 0)))
                }
            )
            if (lastTankShots[player] ?? SRTankShots(shells: [], explosions: [])) != shots {
                lastTankShots[player] = shots
                sends.append((player, shots.encode()))
            }
        }
        return sends
    }

    /// v1.5.0 #1 (fix pass, `/code-review max` on PR #56): recomputes every connected player
    /// slot's `FogState` for this tick and returns the unicast `SRRevealTerrain` sends this
    /// tick's reveals require (`HostGameEngine.tick()` flushes them after `runTick` returns,
    /// same "queue synchronously, flush after" shape as `pending`/`maskedPending`). Called
    /// only when `state.hiddenMines` is true (zero-cost when off).
    ///
    /// **`visionSourceRect` replaces the original design's separate bootstrap/movement-diff
    /// branches and pre-tick `oldTankPositions` snapshot**, which a `/code-review max` review
    /// found could double-apply a reveal (a bootstrap tick where the tank also moves nets an
    /// extra `+1` on the new tile and an unmatched `-1` on the old tile's fringe -- an
    /// unclamped `Int16` going negative) and, separately, never decremented a mover who
    /// stopped contributing via disconnect/kick/ban (only alliance-breaking was even
    /// *attempted*, and a `guard isAllied else { continue }` placed before the only
    /// `decreaseVis` call made that unreachable too). This version tracks, per (observer,
    /// mover) pair, the exact rect currently contributing vision (`nil` when not
    /// contributing) and diffs `shouldContribute` against that cached presence every tick --
    /// one generic transition (`newly contributing` / `moved` / `stopped contributing`)
    /// covers bootstrap, alliance forming, alliance breaking, movement, and disconnect/kick/
    /// ban uniformly, with exactly one `increaseVis`/`decreaseVis` call per real transition.
    /// This also resolves the `isFog` (`fog == 0`)-vs-redaction-paths (`fog > 0`)
    /// inconsistency the same review flagged: `fog` can no longer go negative, so the two
    /// predicates can no longer disagree.
    ///
    /// Combines C's two separate mechanisms into one tick-driven pass, as before: C hooks
    /// `increasevis`/`decreasevis` both at (a) every tick, per-mover, gated on
    /// `testalliance(observer, mover)` (`client.c:458-460`), and (b) immediately at the exact
    /// moment an alliance forms/breaks (`recvsrsetalliance`, `client.c:2905-3013`) or a player
    /// disconnects/is kicked/banned (`client.c:2060-2061,2097-2098,2134-2135,2171-2172`) --
    /// four separate call sites in C, one generic diff here. Can lag a transition by up to one
    /// tick (20ms at 50Hz) versus C's same-event reveal/hide -- a deliberate, documented
    /// simplification, negligible in practice.
    private func updateFogVision() -> [(player: Int, bytes: [UInt8])] {
        var revealsToSend: [(player: Int, bytes: [UInt8])] = []

        // The host's own slot renders directly from `fogState(for:)` (Phase 3) -- no wire
        // round-trip needed, matching the existing "host has no socket to itself" precedent
        // this file already establishes for chat (`emitGameMessage`'s own doc comment).
        //
        // **Discovered-defect fix:** this previously always sent `unminedTerrain(real)`,
        // unconditionally hiding every mine regardless of what `fogState.seenTiles` had
        // just decided for this exact observer (sticky reveal, proximity reveal via
        // `revealNearbyHiddenMines`) -- a guest could never actually receive a mine as
        // mined over the wire. `fogState.seenTiles[index]` already carries the correct,
        // already-computed decision for this tick; this now forwards it (mined terrain
        // when the seen tile is the mined one, else the unmined substitute) instead of
        // re-deriving and force-hiding it a second time.
        func queueReveals(_ points: [Pointi], to observer: Int, fogState: FogState) {
            guard observer != state.localPlayer else { return }
            for point in points {
                let index = Int(point.y) * 256 + Int(point.x)
                let real = Terrain(rawValue: state.terrain.storage[index]) ?? .sea
                let revealed = fogState.seenTiles[index] == terrainToTile(real) ? real : unminedTerrain(real)
                let bytes = SRRevealTerrain(x: UInt8(point.x), y: UInt8(point.y), terrain: UInt8(revealed.rawValue)).encode()
                revealsToSend.append((observer, bytes))
            }
        }

        for observer in state.players.indices where state.players[observer].connected {
            var fogState = fogStates[observer] ?? FogState()

            for mover in state.players.indices {
                let shouldContribute = state.players[mover].connected
                    && testAlliance(observer, mover, players: state.players)
                let key = observer * maxPlayers + mover
                let previousRect = visionSourceRect[key]

                if shouldContribute {
                    let currentRect = tankVisionRect(around: state.players[mover].tank)
                    if let previousRect, previousRect.origin != currentRect.origin {
                        let before = fogState
                        increaseVis(
                            currentRect, state: &fogState, terrain: state.terrain, pills: state.pills,
                            bases: state.bases, hiddenMines: state.hiddenMines, observer: observer,
                            players: state.players
                        )
                        decreaseVis(previousRect, state: &fogState)
                        queueReveals(newlyVisibleTiles(in: currentRect, before: before, after: fogState), to: observer, fogState: fogState)
                        visionSourceRect[key] = currentRect
                    } else if previousRect == nil {
                        // Newly contributing -- covers bootstrap (never tracked before),
                        // alliance just forming, and a mover reconnecting, all uniformly.
                        let before = fogState
                        increaseVis(
                            currentRect, state: &fogState, terrain: state.terrain, pills: state.pills,
                            bases: state.bases, hiddenMines: state.hiddenMines, observer: observer,
                            players: state.players
                        )
                        queueReveals(newlyVisibleTiles(in: currentRect, before: before, after: fogState), to: observer, fogState: fogState)
                        visionSourceRect[key] = currentRect
                    }
                    // previousRect == currentRect (same tile): unchanged, no-op.
                } else if let previousRect {
                    // Stopped contributing -- alliance broke, or `mover` disconnected/was
                    // kicked/was banned. Decrements using the rect they last actually
                    // revealed from, not a value re-derived from their (possibly stale,
                    // possibly already-reset) current state.
                    decreaseVis(previousRect, state: &fogState)
                    visionSourceRect[key] = nil
                }
            }

            // Every connected slot gets its own proximity reveal around its own tank, not
            // just the host's `state.localPlayer` -- C only ever does this for "the local
            // player" because each C client is its own single-player process; this port's
            // per-slot `FogState` makes every connected player equally "local" from their
            // own observer's perspective. Diffed against `seenTiles`, not `fog` -- a
            // proximity reveal can sticky-reveal a mine on a tile that's already otherwise
            // visible (fog already > 0), which never touches the fog count at all.
            let beforeProximity = fogState
            revealNearbyHiddenMines(
                tankPos: state.players[observer].tank, state: &fogState, terrain: state.terrain,
                pills: state.pills, bases: state.bases, observer: observer, players: state.players
            )
            queueReveals(
                changedSeenTiles(around: state.players[observer].tank, before: beforeProximity, after: fogState),
                to: observer, fogState: fogState
            )

            fogStates[observer] = fogState
        }

        // v1.5.0 #1 known gap, deliberately deferred (not skipped, matching this file's own
        // `MineChain.swift`-precedent convention for flagging incomplete-but-tracked work):
        // pill/base state transitions (capture, build, deploy/onboard) do not yet act as
        // their own 15×15 vision sources the way C's own pill/base-related call sites do
        // (`client.c:1549,2013,2205,2383,2954,2993,6359,6436`). A pill/base a player has
        // never had a tank near still gets its own tile revealed via `fogTileFor`'s live
        // pill/base occupancy branch the moment ANY vision source (tank movement above)
        // crosses that tile, so this is a completeness gap on the *vision source* side
        // (structures projecting their own vision), not a correctness gap on the
        // *resolution* side (what a tile displays once seen).
        return revealsToSend
    }

    /// Tiles within `rect` whose `fog` count just crossed from "not visible" to "visible" --
    /// i.e. what `increaseVis` actually made newly visible this call, for reporting to
    /// `updateFogVision`'s reveal-sending caller without threading a return value through
    /// `FogState.swift`'s own (already-tested) algorithm layer.
    private func newlyVisibleTiles(in rect: Recti, before: FogState, after: FogState) -> [Pointi] {
        let clipped = intersectionrect(worldRect, rect)
        guard clipped.size.width > 0, clipped.size.height > 0 else { return [] }
        var points: [Pointi] = []
        let minX = clipped.origin.x, minY = clipped.origin.y
        let maxX = minX + clipped.size.width, maxY = minY + clipped.size.height
        for y in minY..<maxY {
            for x in minX..<maxX {
                let index = Int(y) * 256 + Int(x)
                if before.fog[index] <= 0, after.fog[index] > 0 {
                    points.append(Pointi(x: x, y: y))
                }
            }
        }
        return points
    }

    /// The 3×3 block `revealNearbyHiddenMines` scans, tiles whose `seenTiles` snapshot
    /// changed -- unlike `newlyVisibleTiles` above, a proximity reveal doesn't necessarily
    /// touch `fog` at all (the tile can already be otherwise visible), so this diffs the
    /// actual display value instead.
    private func changedSeenTiles(around tankPos: Vec2f, before: FogState, after: FogState) -> [Pointi] {
        let originX = Int32(tankPos.x) - 1
        let originY = Int32(tankPos.y) - 1
        var points: [Pointi] = []
        for dy in Int32(0)..<3 {
            for dx in Int32(0)..<3 {
                let x = originX + dx, y = originY + dy
                guard x >= 0, x < 256, y >= 0, y < 256 else { continue }
                let index = Int(y) * 256 + Int(x)
                if before.seenTiles[index] != after.seenTiles[index] {
                    points.append(Pointi(x: x, y: y))
                }
            }
        }
        return points
    }
}
