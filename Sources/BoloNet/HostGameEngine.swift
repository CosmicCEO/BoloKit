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
// **Scope, per this sub-wave's own pre-brief (B.5c is the separate, harder half):** no TCP `CL*`
// message dispatch here -- a joined player's subsequent messages still go unread until B.5c
// lands, the same disclosed intermediate state B.5a already accepted. No app-target/UI wiring.
//
// **`runTick`'s environmental callbacks, wired to real `SR*` broadcasts where the mapping is a
// confident 1:1 (7 of them) -- the rest are deliberately left as their default no-op, not
// guessed at.** `onPause`/`onTimeLimitWarning`/`onBaseControlWarning`/`onCoolPill`/
// `onReplenishBase`/`onGrow`/`onShouldBroadcastDropPill` all have an exact, already-built `SR*`
// wire struct whose fields match the callback's own parameters verbatim (traced each one
// against `ServerMessages.swift`, not assumed from the struct's name alone). `onMineExplosion`/
// `onSuperboomTerrain`/`onDropPills`/`onExplosion`/`onSuperboom`/`onSmallboom`/`onSpawn`/
// `onPlayerLagStatusChanged`/`onPlayerDisconnected` do **not** have an equally obvious mapping --
// some may need no wire broadcast at all (e.g. `onSpawn`'s effect is already observable via the
// next `CLUpdate`), some may need to reuse whatever broadcast the CL*-dispatch path already sends
// for the player-triggered version of the same event, and at least one (`onPlayerDisconnected`)
// likely needs to call the already-built `handlePlayerDisconnect` rather than a fresh `SR*`
// struct. Left unwired rather than guessed -- flagged in this sub-wave's own completion report
// for Planner's call on whether that's its own targeted follow-up or folds into B.5c.
//
// Since `runTick`'s callbacks are synchronous (`(Int) -> Void`, not `async`) but broadcasting
// requires `await`ing into the `HostSessionTable` actor, this queues encoded bytes during the
// synchronous call and flushes them after `runTick` returns -- the same "queue during the
// synchronous call, flush after" shape `HostSession.swift`'s own `PendingBroadcast`/`flush`
// already established for the CL*-dispatch path, not a new pattern.

enum HostEngineEvent {
    case newConnection(NWConnection)
    case dgramPacket([UInt8], NWConnection)
    case tick
}

public final class HostGameEngine: @unchecked Sendable {
    public private(set) var state: GameState
    public let table: HostSessionTable

    private let listener: HostListener
    private let dgramListener: HostDgramListener
    private var timer: DispatchSourceTimer?
    private var consumerTask: Task<Void, Never>?
    /// Mirrors `client.players[client.player].seq` (`client.c:434`) -- the local player's own
    /// outgoing per-tick counter, incremented every tick regardless of pause/time-limit gating
    /// inside `runTick` itself. A different role from `HostSessionTable.seq`, which tracks what
    /// this host has last *received* from each other player (`decodeDgramServerRelay`'s
    /// `newSeq`) -- the two happen to share a C field name only because the reference's
    /// single-process-per-role model reuses one struct across roles; this port keeps them
    /// separate, matching D39's precedent for exactly this class of C-side conflation.
    private var localSeq: Int32 = 0

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
    }

    /// The single consumer -- the only place in this type that ever mutates `state`.
    private func handle(_ event: HostEngineEvent) async {
        switch event {
        case .newConnection(let connection):
            // Inlined from `runHostAcceptLoop` (B.5a) -- same call, just made from inside this
            // engine's single consumer instead of its own independent Task.
            _ = await processJoinAttempt(
                connection: connection, serializer: listener.serializer, state: &state, table: table
            )

        case .dgramPacket(let bytes, let connection):
            // Already fully built (`HostDgramListener.swift`) -- decode, apply, relay in one call.
            await processDgramPacket(bytes: bytes, from: connection, state: &state, table: table)

        case .tick:
            await tick()
        }
    }

    private func tick() async {
        var pending: [[UInt8]] = []
        let ticksSinceLastUpdate = await table.allTicksSinceLastUpdate(currentTick: state.ticks)

        runTick(
            state: &state,
            ticksSinceLastUpdate: ticksSinceLastUpdate,
            onPause: { seconds in pending.append(SRPause(pause: UInt8(seconds)).encode()) },
            onTimeLimitWarning: { seconds in pending.append(SRTimeLimit(timeRemaining: UInt16(seconds)).encode()) },
            onBaseControlWarning: { seconds in pending.append(SRBaseControl(timeLeft: UInt16(seconds)).encode()) },
            onCoolPill: { pill in pending.append(SRCoolPill(pill: UInt8(pill)).encode()) },
            onReplenishBase: { base in pending.append(SRReplenishBase(base: UInt8(base)).encode()) },
            onGrow: { x, y in pending.append(SRGrow(x: UInt8(x), y: UInt8(y)).encode()) },
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode())
            }
        )

        for bytes in pending {
            await table.sendToAll(bytes)
        }

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
