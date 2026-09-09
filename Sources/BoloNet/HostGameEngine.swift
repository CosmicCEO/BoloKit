import BoloKit
import Network

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
    /// **C.0 (D119):** host-only kick/ban, same reasoning as `localInputChanged` above --
    /// `hostKickPlayer`/`hostBanPlayer` (`HostSession.swift:323,345`) take `state: inout GameState`,
    /// so a UI button must route through the merged stream rather than calling either directly.
    case kickPlayer(player: Int)
    case banPlayer(player: Int)
    case tick
}

public final class HostGameEngine: @unchecked Sendable {
    public private(set) var state: GameState
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

    /// **B.7 (D108):** fired at the end of every `tick()`, once `runTick` has already mutated
    /// `state` for that tick, with a value-type snapshot (never the live `state` itself, which
    /// only the consumer `Task` may ever touch). Hopped onto the main actor here, at the single
    /// call site, rather than leaving that to each caller -- the app's render target
    /// (`GameRenderView`, an `NSView`) must be touched from the main thread, and this is the one
    /// place that knows the callback fires from off-main (the consumer `Task` has no actor
    /// isolation of its own).
    public var onTickRendered: (@MainActor (GameState) -> Void)?

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

    public func stop() {
        timer?.cancel()
        timer = nil
        listener.cancel()
        dgramListener.cancel()
        consumerTask?.cancel()
        consumerTask = nil
        continuation = nil
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

    /// The single consumer -- the only place in this type that ever mutates `state`.
    private func handle(_ event: HostEngineEvent) async {
        switch event {
        case .newConnection(let connection):
            // Inlined from `runHostAcceptLoop` (B.5a) -- same call, just made from inside this
            // engine's single consumer instead of its own independent Task.
            let outcome = await processJoinAttempt(
                connection: connection, serializer: listener.serializer, state: &state, table: table
            )
            // B.5c: on a successful join, spawn this player's own dynamic producer `Task` --
            // I/O-only (just `receiveOneHostMessageBytes`, never touches `state`), matching the
            // three static producers' own discipline. Reads the same `connection`
            // `processJoinAttempt` already registered into `table` for this player.
            if case .accepted(let player, _) = outcome {
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
            do {
                try await dispatchHostMessage(opcode: opcode, bytes: bytes, player: player, state: &state, table: table)
            } catch {
                await handlePlayerDisconnect(player: player, reason: .abnormal, state: &state, table: table)
                return
            }
            if opcode == .hangUp {
                await handlePlayerDisconnect(player: player, reason: .normal, state: &state, table: table)
            }

        case .clConnectionEnded(let player):
            await handlePlayerDisconnect(player: player, reason: .abnormal, state: &state, table: table)

        case .localInputChanged(let set, let clear):
            state.players[state.localPlayer].inputFlags.formUnion(set)
            state.players[state.localPlayer].inputFlags.subtract(clear)

        case .localLayMineKeyDown:
            layMineOnKeyDown(state: &state)

        case .kickPlayer(let player):
            await hostKickPlayer(player: player, state: &state, table: table)

        case .banPlayer(let player):
            await hostBanPlayer(player: player, state: &state, table: table)

        case .tick:
            await tick()
        }
    }

    private func tick() async {
        var pending: [[UInt8]] = []
        // B.5c: `RunTick.swift`'s own step 4 already drops onboard pills (via `onShouldBroadcastDropPill`,
        // already wired above) and sets `connected = false` for a lag-timed-out player BEFORE
        // firing `onPlayerDisconnected` -- this callback's only remaining job is the network-side
        // half `handlePlayerDisconnect` would otherwise do, NOT that function itself (calling it
        // would re-run `removePlayer`'s own drop-pills logic a second time). Collected separately
        // from `pending` since it needs `table.disconnect`, not just a broadcast.
        var disconnectedPlayers: [Int] = []
        let ticksSinceLastUpdate = await table.allTicksSinceLastUpdate(currentTick: state.ticks)

        runTick(
            state: &state,
            ticksSinceLastUpdate: ticksSinceLastUpdate,
            onPlayerDisconnected: { player in disconnectedPlayers.append(player) },
            onPause: { seconds in pending.append(SRPause(pause: UInt8(seconds)).encode()) },
            onTimeLimitWarning: { seconds in pending.append(SRTimeLimit(timeRemaining: UInt16(seconds)).encode()) },
            onBaseControlWarning: { seconds in pending.append(SRBaseControl(timeLeft: UInt16(seconds)).encode()) },
            onCoolPill: { pill in pending.append(SRCoolPill(pill: UInt8(pill)).encode()) },
            onReplenishBase: { base in pending.append(SRReplenishBase(base: UInt8(base)).encode()) },
            onGrow: { x, y in pending.append(SRGrow(x: UInt8(x), y: UInt8(y)).encode()) },
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode())
            },
            onShouldBroadcastSmallBoom: { player, x, y in
                pending.append(SRSmallBoom(player: player, x: UInt8(x), y: UInt8(y)).encode())
            },
            onShouldBroadcastFlood: { x, y in pending.append(SRFlood(x: UInt8(x), y: UInt8(y)).encode()) }
        )

        for bytes in pending {
            await table.sendToAll(bytes)
        }

        for player in disconnectedPlayers {
            // Mirrors `handlePlayerDisconnect`'s own `.abnormal` broadcast + table cleanup
            // (`HostSession.swift:310,312`) -- NOT a call to that function itself, see above.
            await table.sendToAllExcept(player, SRPlayerDisc(player: UInt8(player)).encode())
            await table.disconnect(player)
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
        let seqSnapshot = await table.allSeqsAsUInt32()
        let update = assembleClUpdate(player: state.localPlayer, state: state, seq: seqSnapshot)
        let bytes = update.encode()
        for player in 0..<maxPlayers where player != state.localPlayer {
            await table.sendDgram(bytes, to: player)
        }
    }
}
