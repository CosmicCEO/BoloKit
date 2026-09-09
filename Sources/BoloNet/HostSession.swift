import Network
import Foundation
import BoloKit

// MARK: - Wave 6.4b — host-side session table, broadcast fan-out, CL* dispatch
//
// `HostSessionTable` carries exactly the transport session state
// `GameState` deliberately lacks (Wave 6.4b pre-brief §1): one TCP
// `NWConnection` and one UDP peer address/seq per player slot. The
// fan-out primitives (`sendToAll`/`sendToAllExcept`/`sendToOne`/
// `sendToMask`) are this port's replacement for `sendtoall`/
// `sendtoallex`/`sendtoone` (`server.c:3818-3870`) -- G-2, confirmed
// in-scope by D47.
//
// `receiveAndDispatchOneHostMessage` mirrors `TCPSession.swift`'s own
// `receiveAndDispatchOne` (Wave 6.4a, client-side `SR*` dispatch) for the
// reverse direction: decode one `CL*` opcode, call the matching already-
// shipped `recvCl*` (Wave 6.6), and forward its `onShouldBroadcast*`
// callbacks to the right fan-out primitive with the right `SR*` struct.
// Every `sendsr*` function's own choice of `sendtoall`/`sendtoallex(player)`/
// `sendtoone(player)` was read directly from `server.c` and is cited
// per-case below, not assumed from the shape of the callback.
//
// **Wave 6.4c (D50):** `dropPills` (`MineChain.swift`, Wave 5.5a) now has
// an `onShouldBroadcastDropPill` callback (`dropPillSearch`'s own
// post-mutation fire, mirroring `dr()`'s `sendsrdroppill(i)` call exactly
// -- `server.c:1965-1976`), wired here (`.dropPills` below) and in
// `handlePlayerDisconnect`/`hostKickPlayer`/`hostBanPlayer`. `RunTick.
// swift`'s own `dropPills` call site (the stale-player-disconnect path)
// still has no live wiring to a `HostSessionTable` -- disclosed there,
// not here, since no top-level tick-orchestration driver exists yet to
// own that connection.
//
// **Six `RecvCL.swift` (Wave 6.6) callback signatures were extended, not
// just wired, while writing this dispatcher** -- `onShouldBroadcastBuild`,
// `onShouldBroadcastDamage`, `onShouldBroadcastCapturePill`,
// `onShouldBroadcastCaptureBase`, `onShouldBroadcastBuildPill`, and
// `onShouldBroadcastRepairPill` didn't carry enough data to build their
// `SR*` struct -- the real `sendsrbuild()`/`sendsrdamage()`/etc. each read
// one more field (`terrain`/`owner`/`armour`/`x`/`y`) directly off the
// `server` global at send time (`server.c:3232`, `:3190`, `:3528`,
// `:3604`, `:3547-3549`, `:3491`). A caller-side closure can't do the same
// read here: it would need to read `state` while `state: &state` is still
// formally exclusive-locked by the very call passing the closure in --
// this file's own header already documents the identical constraint for
// `applyDamage`. Fixed by having each `recvCl*` function read the extra
// field itself (always immediately after its own mutation, matching the
// C's own post-mutation read order) and pass it as a new trailing
// parameter -- same shape of "found a real gap in already-shipped,
// PARITY-passed code while wiring a later wave, fix it now" this project
// has applied repeatedly (D35/D37/D39/D45/D46).

public enum HostSessionError: Error {
    case connectionClosed
    case malformedMessage
}

// MARK: - Low-level NWConnection primitives
//
// Free functions, not a class -- `HostSessionTable` already owns
// connection lifecycle (set at accept time, torn down at disconnect); this
// dispatcher only ever needs to read/write bytes on a connection it's
// handed, mirroring `TCPSession.swift`'s private methods exactly for the
// reverse direction.

private func receiveExactly(_ count: Int, from connection: NWConnection) async throws -> [UInt8] {
    guard count > 0 else { return [] }
    return try await withCheckedThrowingContinuation { continuation in
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let data, data.count == count {
                continuation.resume(returning: Array(data))
            } else {
                continuation.resume(throwing: HostSessionError.connectionClosed)
            }
        }
    }
}

private func receiveOneByte(from connection: NWConnection) async throws -> UInt8 {
    try await receiveExactly(1, from: connection)[0]
}

private func sendBytes(_ bytes: [UInt8], over connection: NWConnection) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        connection.send(
            content: Data(bytes),
            completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        )
    }
}

// MARK: - HostSessionTable

/// One player slot's transport session state -- exactly the fields
/// `GameState` deliberately doesn't store (Wave 6.4b pre-brief §1):
/// `used`/`connected` DO have a `GameState` home already
/// (`PlayerState.used`/`.connected`), so they are NOT duplicated here.
public actor HostSessionTable {
    public struct Slot: Sendable {
        public var connection: NWConnection?
        public var dgramAddress: DgramServerPeerAddress
        /// The live UDP flow (`NWConnection`) this slot's real datagrams
        /// have most recently arrived on -- Wave 6.4c, §2. Distinct from
        /// `dgramAddress` (a value snapshot for the pure decision
        /// function, `DgramServerRelay.swift`) and from `connection` (the
        /// TCP control socket): relaying needs an actual live object to
        /// send *through*, since Network.framework's UDP model requires an
        /// established inbound flow before sending outbound through a
        /// matching `NWConnection` -- there is no "send anywhere via one
        /// shared socket" primitive the way raw `sendto()` on the C's
        /// single `dgramsock` provides. D52: bounded to at most
        /// `maxPlayers` live connections at any time by `setDgramConnection`'s
        /// explicit cancel-and-replace below, not an arbitrary cap.
        public var dgramConnection: NWConnection?
        /// Mirrors `server.players[i].seq`. T-1: reset to 0 only at
        /// disconnect (`disconnect(_:)` below) -- the join-time reset is
        /// commented out in the real `joinplayerserver()`, so there is no
        /// equivalent reset at accept time either.
        public var seq: Int32
        public var lastUpdate: UInt64

        public init(
            connection: NWConnection? = nil,
            dgramAddress: DgramServerPeerAddress = DgramServerPeerAddress(family: 0, addr: 0, port: 0),
            dgramConnection: NWConnection? = nil,
            seq: Int32 = 0, lastUpdate: UInt64 = 0
        ) {
            self.connection = connection
            self.dgramAddress = dgramAddress
            self.dgramConnection = dgramConnection
            self.seq = seq
            self.lastUpdate = lastUpdate
        }
    }

    private var slots: [Slot]

    public init() {
        slots = Array(repeating: Slot(), count: maxPlayers)
    }

    public func connection(for player: Int) -> NWConnection? { slots[player].connection }
    public func setConnection(_ connection: NWConnection?, for player: Int) { slots[player].connection = connection }
    public func isConnected(_ player: Int) -> Bool { slots[player].connection != nil }
    public func dgramAddress(for player: Int) -> DgramServerPeerAddress { slots[player].dgramAddress }
    public func setDgramAddress(_ address: DgramServerPeerAddress, for player: Int) { slots[player].dgramAddress = address }
    public func dgramConnection(for player: Int) -> NWConnection? { slots[player].dgramConnection }
    /// D52: explicitly cancels the slot's previous UDP flow before storing
    /// the new one, rather than merely dropping the reference -- keeps
    /// live-tracked UDP connections bounded to at most `maxPlayers` at any
    /// time (T-15's real invariant), and ensures a stale flow (e.g. after
    /// a player rebinds their UDP source port) doesn't linger unreaped.
    public func setDgramConnection(_ connection: NWConnection?, for player: Int) {
        if let old = slots[player].dgramConnection, old !== connection {
            old.cancel()
        }
        slots[player].dgramConnection = connection
    }
    public func seq(for player: Int) -> Int32 { slots[player].seq }
    public func setSeq(_ seq: Int32, for player: Int) { slots[player].seq = seq }
    public func lastUpdate(for player: Int) -> UInt64 { slots[player].lastUpdate }
    public func setLastUpdate(_ tick: UInt64, for player: Int) { slots[player].lastUpdate = tick }

    /// `evaluateJoinRequest`'s own `ticksSinceLastUpdate` parameter --
    /// mirrors `server.ticks - server.players[p].lastupdate`
    /// (`SessionLogic.swift`'s doc comment on that parameter).
    public func allTicksSinceLastUpdate(currentTick: UInt64) -> [UInt64] {
        slots.map { currentTick - $0.lastUpdate }
    }

    /// `assembleBoloPreamble`'s own `seq` parameter, one entry per slot.
    public func allSeqsAsUInt32() -> [UInt32] {
        slots.map { UInt32(bitPattern: $0.seq) }
    }

    /// T-1's disconnect-side reset (`removeplayer()`, `server.c:594`) --
    /// cancels the TCP connection and wipes the whole slot, including
    /// `seq`, back to its never-joined default.
    public func disconnect(_ player: Int) {
        slots[player].connection?.cancel()
        slots[player].dgramConnection?.cancel()
        slots[player] = Slot()
    }

    /// Builds the per-packet snapshot `decodeDgramServerRelay` needs.
    /// `used` has no home in this table (it's `GameState.players[i].used`)
    /// -- callers holding `state` already supply it.
    public func dgramSessionSnapshot(usedFlags: [Bool]) -> [DgramServerPlayerSessionState] {
        (0..<maxPlayers).map { i in
            DgramServerPlayerSessionState(
                used: i < usedFlags.count ? usedFlags[i] : false,
                connected: slots[i].connection != nil,
                dgramAddress: slots[i].dgramAddress,
                seq: slots[i].seq
            )
        }
    }

    /// Best-effort -- a send failure (e.g. a peer that's already
    /// disconnecting) is not surfaced as an error, matching the C's own
    /// tolerance for `EPIPE` on exactly this kind of send
    /// (`sendsrplayerexit`, `server.c:3397-3404`).
    public func send(_ bytes: [UInt8], to player: Int) async {
        guard let connection = slots[player].connection else { return }
        try? await sendBytes(bytes, over: connection)
    }

    /// Milestone B.5b (D96) -- the UDP-side counterpart of `send(_:to:)`, over
    /// `slots[player].dgramConnection` instead of the TCP control socket. No equivalent existed
    /// before this: `decodeDgramServerRelay`'s `relayTo` result and the host's own outbound
    /// `CLUpdate` (`assembleClUpdate`, `CLUpdateCodec.swift`) both need to reach a player over
    /// their UDP flow, not TCP. Same best-effort tolerance as `send(_:to:)` -- a slot with no
    /// `dgramConnection` yet (a player who's joined but hasn't sent their first datagram) is a
    /// silent no-op, not an error.
    public func sendDgram(_ bytes: [UInt8], to player: Int) async {
        guard let connection = slots[player].dgramConnection else { return }
        try? await sendBytes(bytes, over: connection)
    }

    /// Mirrors `sendtoall()` (`server.c:3818-3834`) -- every connected slot.
    public func sendToAll(_ bytes: [UInt8]) async {
        for i in 0..<maxPlayers where slots[i].connection != nil {
            await send(bytes, to: i)
        }
    }

    /// Mirrors `sendtoallex()` (`server.c:3836-3854`) -- every connected
    /// slot except `player`.
    public func sendToAllExcept(_ player: Int, _ bytes: [UInt8]) async {
        for i in 0..<maxPlayers where i != player && slots[i].connection != nil {
            await send(bytes, to: i)
        }
    }

    /// Mirrors `sendsrsendmesg()`'s own inlined mask loop (`server.c:
    /// 3162-3168`) -- every connected slot whose bit is set in `mask`.
    public func sendToMask(_ mask: UInt16, _ bytes: [UInt8]) async {
        for i in 0..<maxPlayers where slots[i].connection != nil && (mask & (1 << i)) != 0 {
            await send(bytes, to: i)
        }
    }
}

// MARK: - Disconnect / kick / ban (T-12, T-13)

public enum HostDisconnectReason: Sendable {
    /// `recvplayerserver()` returned success (`kHangupClientMessage`, or
    /// the buffer drained cleanly) -- `sendsrplayerexit`.
    case normal
    /// A socket error, or `recvplayerserver()` failed with something other
    /// than `EAGAIN` -- `sendsrplayerdisc`.
    case abnormal
}

/// Ported from `servermainthread()`'s four identical disconnect-handling
/// blocks (`server.c:1667-1740`) -- `removeplayer` (T-1's `GameState`
/// half already covered by `removePlayer`, `SessionLogic.swift`, G-4) +
/// the reason-dependent broadcast + T-12's `pauseonplayerexit` trigger.
/// **D53 (PARITY finding, Wave 6.4c post-commit audit):** an earlier
/// version of this function skipped the departing player's own exit
/// notice, reasoning that `sendsrplayerexit`'s `sendtoone(player)` half
/// (`server.c:3397`) was redundant since the connection is already being
/// torn down. That reasoning was wrong -- `sendtoone` there is
/// best-effort and EPIPE-tolerant precisely *because* C expects the
/// socket might already be half-closed, not because the send is
/// pointless; the real observable effect is that the departing player
/// DOES receive their own `SRPlayerExit` whenever the send succeeds.
/// Fixed to use `sendToAll` for `.normal`, matching that net effect
/// without replicating the two-syscall split itself (an artifact of C's
/// mechanism, not an observable protocol requirement).
public func handlePlayerDisconnect(
    player: Int, reason: HostDisconnectReason, state: inout GameState, table: HostSessionTable
) async {
    // C ordering (server.c:1667-1740): `removeplayer()` -- and so its own
    // `sendsrdroppill` calls -- runs BEFORE `sendsrplayerexit`/`sendsrplayerdisc`,
    // the opposite order from `kickplayer()`/`banplayer()` below.
    // `sendsrdroppill` is a plain `sendtoall` (server.c:3571) -- reaches
    // the disconnecting player's own still-registered slot too.
    var dropPillBroadcasts: [[UInt8]] = []
    removePlayer(player: player, state: &state, onShouldBroadcastDropPill: { pill, x, y in
        dropPillBroadcasts.append(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode())
    })
    for bytes in dropPillBroadcasts {
        await table.sendToAll(bytes)
    }

    // D53 (PARITY finding, Wave 6.4c audit): `sendsrplayerexit()`
    // (`server.c:3387-3409`) is NOT a single `sendtoallex` -- it does
    // `sendtoone(player)` (best-effort, EPIPE-tolerant) first, THEN
    // `sendtoallex` for everyone else, so the departing player receives
    // their own exit notice too. `sendsrplayerdisc()` (`server.c:
    // 3413-3426`), by contrast, really is a single unconditional
    // `sendtoallex` -- no self-send. `sendToAll` already includes the
    // departing player's still-registered slot (matching C's net effect
    // without needing to replicate the two-syscall EPIPE-tolerance
    // split, which is an artifact of C's mechanism, not an observable
    // protocol requirement) -- do NOT change the `.abnormal` branch.
    switch reason {
    case .normal:
        await table.sendToAll(SRPlayerExit(player: UInt8(player)).encode())
    case .abnormal:
        await table.sendToAllExcept(player, SRPlayerDisc(player: UInt8(player)).encode())
    }
    await table.disconnect(player)

    if state.pauseOnPlayerExit {
        state.serverPauseTicks = -1
        await table.sendToAll(SRPause(pause: 255).encode())
    }
}

/// Ported from `kickplayer()` (`server.c:475-501`) -- `sendsrplayerkick`
/// uses `sendtoall` (confirmed by direct read), unlike the exit/disc/ban
/// broadcasts, which all exclude the departing player.
public func hostKickPlayer(player: Int, state: inout GameState, table: HostSessionTable) async {
    // C ordering (server.c:486-487): `sendsrplayerkick` fires BEFORE
    // `removeplayer()` -- the opposite order from the disconnect path
    // above. Collecting both callbacks into one ordered array (rather
    // than a hardcoded `SRPlayerKick` send after the call returns)
    // preserves that firing order automatically.
    var broadcasts: [[UInt8]] = []
    kickPlayer(
        player: player, state: &state,
        onShouldBroadcastPlayerKick: { p in broadcasts.append(SRPlayerKick(player: UInt8(p)).encode()) },
        onShouldBroadcastDropPill: { pill, x, y in broadcasts.append(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode()) }
    )
    for bytes in broadcasts {
        await table.sendToAll(bytes)
    }
    await table.disconnect(player)
}

/// Ported from `banplayer()` (`server.c:503-535`) -- the `cntlsock != -1`
/// guard is real business logic (`SessionLogic.swift`'s `banPlayer`
/// already replicates it via `connected`), so the broadcast+disconnect
/// below only fire when that guard actually let the ban proceed.
public func hostBanPlayer(player: Int, state: inout GameState, table: HostSessionTable) async {
    // C ordering (server.c:524-525): `sendsrplayerban` fires BEFORE
    // `removeplayer()`, same shape as `hostKickPlayer` above.
    var broadcasts: [[UInt8]] = []
    var didBan = false
    banPlayer(
        player: player, state: &state,
        onShouldBroadcastPlayerBan: { p in
            didBan = true
            broadcasts.append(SRPlayerBan(player: UInt8(p)).encode())
        },
        onShouldBroadcastDropPill: { pill, x, y in broadcasts.append(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode()) }
    )
    guard didBan else { return }
    for bytes in broadcasts {
        await table.sendToAll(bytes)
    }
    await table.disconnect(player)
}

// MARK: - Host-admin: pause/resume, allow-join, unban (1.1, D129)

/// Async wrapper for `SessionLogic.pauseResumeServer` -- the only host-admin entry point here
/// that broadcasts (`SRPause`, reusing the existing wire message; `sendsrpause` is the same
/// message `handlePlayerDisconnect` above already sends for pause-on-player-exit, not a new one).
/// `setAllowJoin`/`toggleAllowJoin`/`unbanPlayer` have no async wrapper -- confirmed by direct
/// read of `server.c` that none of `setallowjoinserver`/`togglejoinserver`/`unbanplayer` ever
/// call `sendsr*`, so the pure `SessionLogic` function is the whole implementation; a caller
/// (`HostGameEngine`) can mutate `state` directly with no `table` involvement.
public func hostPauseResumeServer(state: inout GameState, table: HostSessionTable) async {
    var broadcast: [UInt8]?
    pauseResumeServer(state: &state, onShouldBroadcastPause: { seconds in broadcast = SRPause(pause: seconds).encode() })
    if let broadcast {
        await table.sendToAll(broadcast)
    }
}

// MARK: - CL* dispatch

/// Every `onMineExplosion`/`onSuperboomTerrain` a `recvCl*` call can fire, grouped the same way
/// `SRDispatchCallbacks` (`TCPSession.swift`, Wave 6.4a) groups the client-side equivalents -- a
/// headless host has no sound/vis layer of its own, but a future caller (logging, a hosting UI)
/// still needs these hooks.
///
/// **B.5d (D100/D103):** `onDropPills` used to live here too, as a bare `(UInt16, Vec2f) -> Void`
/// pass-through -- meaning a builder killed by an explosion during a CL-dispatched action (e.g.
/// `recvClTouch` detonating a mine under a builder) never actually broadcast its pill drop in
/// production, since nothing ever configured this struct with a real implementation. Removed:
/// every `recvCl*` call site below now passes an inline `onShouldBroadcastDropPill` closure
/// straight to `pending`, the same shape `.dropPills`'s own case already used -- a real broadcast
/// decision belongs there, not on a struct meant for local-only UI/logging hooks with no `table`
/// access.
public struct CLDispatchCallbacks {
    public var onMineExplosion: (Pointi) -> Void = { _ in }
    public var onSuperboomTerrain: (Pointi) -> Void = { _ in }

    public init(
        onMineExplosion: @escaping (Pointi) -> Void = { _ in },
        onSuperboomTerrain: @escaping (Pointi) -> Void = { _ in }
    ) {
        self.onMineExplosion = onMineExplosion
        self.onSuperboomTerrain = onSuperboomTerrain
    }
}

/// One broadcast a `recvCl*` callback decided to fire, queued during the
/// (synchronous) call and only actually sent -- via `table`'s `async`
/// primitives -- after the call returns. A callback can't `await` a send
/// directly (it runs synchronously, nested inside `recvCl*`'s own
/// `state: &state` formal access), so this defers the I/O the same way
/// every other exclusivity-driven callback boundary in this file does.
private enum PendingBroadcast {
    case all([UInt8])
    case allExcept(Int, [UInt8])
    case one(Int, [UInt8])
    case mask(UInt16, [UInt8])
}

private func flush(_ pending: [PendingBroadcast], table: HostSessionTable) async {
    for broadcast in pending {
        switch broadcast {
        case .all(let bytes): await table.sendToAll(bytes)
        case .allExcept(let player, let bytes): await table.sendToAllExcept(player, bytes)
        case .one(let player, let bytes): await table.send(bytes, to: player)
        case .mask(let mask, let bytes): await table.sendToMask(mask, bytes)
        }
    }
}

/// I/O-only half of `receiveAndDispatchOneHostMessage` (B.5c, D96): reads exactly one `CL*`
/// opcode's wire bytes off `connection` and returns them undecoded -- no `state` access, matching
/// the merged-event-stream architecture's producer-task discipline (`HostGameEngine.swift`'s own
/// header). Every opcode's wire size is static per-opcode (confirmed by reading every case below
/// before splitting this out -- none of them need a decoded value to know how many more bytes to
/// read), except `.sendMesg`'s null-terminated variable-length text, itself still a pure protocol
/// read with no `state` dependency either.
public func receiveOneHostMessageBytes(from connection: NWConnection) async throws -> (opcode: ClientOpcode, bytes: [UInt8]) {
    let opcodeByte = try await receiveOneByte(from: connection)
    guard let opcode = ClientOpcode(rawValue: opcodeByte) else {
        throw HostSessionError.malformedMessage
    }

    // `wireSize` includes the opcode byte already read above.
    func rest(_ wireSize: Int) async throws -> [UInt8] {
        [opcodeByte] + (try await receiveExactly(wireSize - 1, from: connection))
    }

    switch opcode {
    case .hangUp: return (opcode, try await rest(CLHangUp.wireSize))
    case .sendMesg:
        let fixed = try await rest(CLSendMesg.wireSize)
        var textBytes: [UInt8] = []
        while true {
            let b = try await receiveOneByte(from: connection)
            if b == 0 { break }
            textBytes.append(b)
        }
        return (opcode, fixed + textBytes + [0])
    case .dropBoat: return (opcode, try await rest(CLDropBoat.wireSize))
    case .dropPills: return (opcode, try await rest(CLDropPills.wireSize))
    case .dropMine: return (opcode, try await rest(CLDropMine.wireSize))
    case .touch: return (opcode, try await rest(CLTouch.wireSize))
    case .grabTile: return (opcode, try await rest(CLGrabTile.wireSize))
    case .grabTrees: return (opcode, try await rest(CLGrabTrees.wireSize))
    case .buildRoad: return (opcode, try await rest(CLBuildRoad.wireSize))
    case .buildWall: return (opcode, try await rest(CLBuildWall.wireSize))
    case .buildBoat: return (opcode, try await rest(CLBuildBoat.wireSize))
    case .buildPill: return (opcode, try await rest(CLBuildPill.wireSize))
    case .repairPill: return (opcode, try await rest(CLRepairPill.wireSize))
    case .placeMine: return (opcode, try await rest(CLPlaceMine.wireSize))
    case .damage: return (opcode, try await rest(CLDamage.wireSize))
    case .smallBoom: return (opcode, try await rest(CLSmallBoom.wireSize))
    case .superBoom: return (opcode, try await rest(CLSuperBoom.wireSize))
    case .refuel: return (opcode, try await rest(CLRefuel.wireSize))
    case .hitTank: return (opcode, try await rest(CLHitTank.wireSize))
    case .setAlliance: return (opcode, try await rest(CLSetAlliance.wireSize))
    }
}

/// Pure half of `receiveAndDispatchOneHostMessage` (B.5c, D96): decodes `bytes` (already read by
/// `receiveOneHostMessageBytes`) and dispatches to the matching `recvCl*` function (Wave 6.6) --
/// or, for the two opcodes with no such function (`CLHangUp`/`CLSendMesg`, per `RecvCL.swift`'s
/// own header), the matching direct handling. No connection I/O -- only `await`s at the very end,
/// into `table`'s actor-isolated broadcast primitives, matching `HostGameEngine.tick()`'s own
/// "queue synchronously, flush after" shape for the identical reason (a `recvCl*` callback can't
/// itself `await` while holding `state: &state`).
///
/// `player` is this connection's own slot index -- the sender's identity for every opcode except
/// `CLHitTank`, whose wire struct carries an explicit, semantically different `player` field (the
/// tank being hit, not the sender -- `RecvCL.swift`'s own doc comment on `recvClHitTank`), used
/// instead.
public func dispatchHostMessage(
    opcode: ClientOpcode, bytes: [UInt8], player: Int, state: inout GameState, table: HostSessionTable,
    callbacks: CLDispatchCallbacks = CLDispatchCallbacks()
) async throws {
    var pending: [PendingBroadcast] = []

    switch opcode {
    case .hangUp:
        break
        // No `recvCl*` call -- `kHangupClientMessage` is a pure "normal
        // exit" signal (`RecvCL.swift`'s header, `server.c:1068-1069`).

    case .sendMesg:
        guard let msg = CLSendMesg.decode(bytes) else { throw HostSessionError.malformedMessage }
        // Pure masked relay (`sendsrsendmesg`, `server.c:3147-3173`) -- no
        // `GameState` effect, no `recvCl*` function (Wave 6.2/6.6's own
        // prior finding, restated in `RecvCL.swift`'s header).
        pending.append(.mask(UInt16(bitPattern: msg.mask), SRSendMesg(player: UInt8(player), to: msg.to, text: msg.text).encode()))

    case .dropBoat:
        guard let msg = CLDropBoat.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClDropBoat(x: Int(msg.x), y: Int(msg.y), state: &state, onShouldBroadcastDropBoat: { x, y in
            pending.append(.all(SRDropBoat(x: UInt8(x), y: UInt8(y)).encode()))
        })

    case .dropPills:
        guard let msg = CLDropPills.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClDropPills(
            player: player, x: msg.x, y: msg.y, pills: msg.pills, state: &state,
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(.all(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode()))
            }
        )

    case .dropMine:
        guard let msg = CLDropMine.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClDropMine(
            player: player, x: Int(msg.x), y: Int(msg.y), state: &state,
            onShouldBroadcastDropMine: { p, x, y in
                pending.append(.all(SRDropMine(player: UInt8(p), x: UInt8(x), y: UInt8(y)).encode()))
            },
            onShouldBroadcastMineAck: { p, success in
                pending.append(.one(p, SRMineAck(success: success ? 1 : 0).encode()))
            }
        )

    case .touch:
        guard let msg = CLTouch.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClTouch(
            player: player, x: Int(msg.x), y: Int(msg.y), state: &state,
            onShouldBroadcastSmallBoom: { p, x, y in
                pending.append(.all(SRSmallBoom(player: p, x: UInt8(x), y: UInt8(y)).encode()))
            },
            onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(.all(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode()))
            }
        )

    case .grabTile:
        guard let msg = CLGrabTile.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClGrabTile(
            player: player, x: Int(msg.x), y: Int(msg.y), state: &state,
            onShouldBroadcastCapturePill: { pill, owner in
                pending.append(.all(SRCapturePill(pill: UInt8(pill), owner: owner).encode()))
            },
            onShouldBroadcastCaptureBase: { base, owner in
                pending.append(.all(SRCaptureBase(base: UInt8(base), owner: owner).encode()))
            },
            onShouldBroadcastGrabBoat: { p, x, y in
                pending.append(.all(SRGrabBoat(player: UInt8(p), x: UInt8(x), y: UInt8(y)).encode()))
            },
            onShouldBroadcastSmallBoom: { p, x, y in
                pending.append(.all(SRSmallBoom(player: p, x: UInt8(x), y: UInt8(y)).encode()))
            },
            onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(.all(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode()))
            }
        )

    case .grabTrees:
        guard let msg = CLGrabTrees.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClGrabTrees(
            player: player, x: Int(msg.x), y: Int(msg.y), state: &state,
            onShouldBroadcastGrabTrees: { x, y in
                pending.append(.all(SRGrabTrees(x: UInt8(x), y: UInt8(y)).encode()))
            },
            onShouldBroadcastBuilderAck: { p, mines, trees, pill in
                pending.append(.one(p, SRBuilderAck(
                    mines: UInt8(truncatingIfNeeded: mines), trees: UInt8(truncatingIfNeeded: trees),
                    pill: UInt8(truncatingIfNeeded: pill)
                ).encode()))
            },
            onShouldBroadcastSmallBoom: { p, x, y in
                pending.append(.all(SRSmallBoom(player: p, x: UInt8(x), y: UInt8(y)).encode()))
            },
            onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(.all(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode()))
            }
        )

    case .buildRoad:
        guard let msg = CLBuildRoad.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClBuildRoad(
            player: player, x: Int(msg.x), y: Int(msg.y), trees: Int(msg.trees), state: &state,
            onShouldBroadcastBuild: { x, y, terrain in
                pending.append(.all(SRBuild(x: UInt8(x), y: UInt8(y), terrain: terrain).encode()))
            },
            onShouldBroadcastBuilderAck: { p, mines, trees, pill in
                pending.append(.one(p, SRBuilderAck(
                    mines: UInt8(truncatingIfNeeded: mines), trees: UInt8(truncatingIfNeeded: trees),
                    pill: UInt8(truncatingIfNeeded: pill)
                ).encode()))
            },
            onShouldBroadcastSmallBoom: { p, x, y in
                pending.append(.all(SRSmallBoom(player: p, x: UInt8(x), y: UInt8(y)).encode()))
            },
            onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(.all(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode()))
            }
        )

    case .buildWall:
        guard let msg = CLBuildWall.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClBuildWall(
            player: player, x: Int(msg.x), y: Int(msg.y), trees: Int(msg.trees), state: &state,
            onShouldBroadcastBuild: { x, y, terrain in
                pending.append(.all(SRBuild(x: UInt8(x), y: UInt8(y), terrain: terrain).encode()))
            },
            onShouldBroadcastBuilderAck: { p, mines, trees, pill in
                pending.append(.one(p, SRBuilderAck(
                    mines: UInt8(truncatingIfNeeded: mines), trees: UInt8(truncatingIfNeeded: trees),
                    pill: UInt8(truncatingIfNeeded: pill)
                ).encode()))
            },
            onShouldBroadcastSmallBoom: { p, x, y in
                pending.append(.all(SRSmallBoom(player: p, x: UInt8(x), y: UInt8(y)).encode()))
            },
            onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(.all(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode()))
            }
        )

    case .buildBoat:
        guard let msg = CLBuildBoat.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClBuildBoat(
            player: player, x: Int(msg.x), y: Int(msg.y), trees: Int(msg.trees), state: &state,
            onShouldBroadcastBuild: { x, y, terrain in
                pending.append(.all(SRBuild(x: UInt8(x), y: UInt8(y), terrain: terrain).encode()))
            },
            onShouldBroadcastBuilderAck: { p, mines, trees, pill in
                pending.append(.one(p, SRBuilderAck(
                    mines: UInt8(truncatingIfNeeded: mines), trees: UInt8(truncatingIfNeeded: trees),
                    pill: UInt8(truncatingIfNeeded: pill)
                ).encode()))
            },
            onShouldBroadcastSmallBoom: { p, x, y in
                pending.append(.all(SRSmallBoom(player: p, x: UInt8(x), y: UInt8(y)).encode()))
            },
            onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(.all(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode()))
            }
        )

    case .buildPill:
        guard let msg = CLBuildPill.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClBuildPill(
            player: player, x: Int(msg.x), y: Int(msg.y), trees: Int(msg.trees), pill: Int(msg.pill), state: &state,
            onShouldBroadcastBuildPill: { pill, x, y, armour in
                pending.append(.all(SRBuildPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y), armour: armour).encode()))
            },
            onShouldBroadcastBuilderAck: { p, mines, trees, pill in
                pending.append(.one(p, SRBuilderAck(
                    mines: UInt8(truncatingIfNeeded: mines), trees: UInt8(truncatingIfNeeded: trees),
                    pill: UInt8(truncatingIfNeeded: pill)
                ).encode()))
            },
            onShouldBroadcastSmallBoom: { p, x, y in
                pending.append(.all(SRSmallBoom(player: p, x: UInt8(x), y: UInt8(y)).encode()))
            },
            onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(.all(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode()))
            }
        )

    case .repairPill:
        guard let msg = CLRepairPill.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClRepairPill(
            player: player, x: Int(msg.x), y: Int(msg.y), trees: Int(msg.trees), state: &state,
            onShouldBroadcastRepairPill: { pill, armour in
                pending.append(.all(SRRepairPill(pill: UInt8(pill), armour: armour).encode()))
            },
            onShouldBroadcastBuilderAck: { p, mines, trees, pill in
                pending.append(.one(p, SRBuilderAck(
                    mines: UInt8(truncatingIfNeeded: mines), trees: UInt8(truncatingIfNeeded: trees),
                    pill: UInt8(truncatingIfNeeded: pill)
                ).encode()))
            },
            onShouldBroadcastSmallBoom: { p, x, y in
                pending.append(.all(SRSmallBoom(player: p, x: UInt8(x), y: UInt8(y)).encode()))
            },
            onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(.all(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode()))
            }
        )

    case .placeMine:
        // `msg.mines` is decoded but never forwarded -- `recvClPlaceMine`
        // takes no such parameter, matching the C exactly (`RecvCL.swift`'s
        // own doc comment: "costs no trees, always acks 0").
        guard let msg = CLPlaceMine.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClPlaceMine(
            player: player, x: Int(msg.x), y: Int(msg.y), state: &state,
            onShouldBroadcastPlaceMine: { p, x, y in
                pending.append(.all(SRPlaceMine(player: UInt8(p), x: UInt8(x), y: UInt8(y)).encode()))
            },
            onShouldBroadcastBuilderAck: { p, mines, trees, pill in
                pending.append(.one(p, SRBuilderAck(
                    mines: UInt8(truncatingIfNeeded: mines), trees: UInt8(truncatingIfNeeded: trees),
                    pill: UInt8(truncatingIfNeeded: pill)
                ).encode()))
            },
            onShouldBroadcastSmallBoom: { p, x, y in
                pending.append(.all(SRSmallBoom(player: p, x: UInt8(x), y: UInt8(y)).encode()))
            },
            onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(.all(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode()))
            }
        )

    case .damage:
        guard let msg = CLDamage.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClDamage(
            player: player, x: Int(msg.x), y: Int(msg.y), boat: msg.boat != 0, state: &state,
            onShouldBroadcastDamage: { p, x, y, terrain in
                pending.append(.all(SRDamage(player: UInt8(p), x: UInt8(x), y: UInt8(y), terrain: terrain).encode()))
            },
            onShouldBroadcastSmallBoom: { p, x, y in
                pending.append(.all(SRSmallBoom(player: p, x: UInt8(x), y: UInt8(y)).encode()))
            },
            onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(.all(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode()))
            }
        )

    case .smallBoom:
        guard let msg = CLSmallBoom.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClSmallBoom(
            player: player, x: Int(msg.x), y: Int(msg.y), state: &state,
            onShouldBroadcastSmallBoom: { p, x, y in
                pending.append(.all(SRSmallBoom(player: p, x: UInt8(x), y: UInt8(y)).encode()))
            },
            onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(.all(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode()))
            }
        )

    case .superBoom:
        guard let msg = CLSuperBoom.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClSuperBoom(
            player: player, x: Int(msg.x), y: Int(msg.y), state: &state,
            onShouldBroadcastSuperBoom: { p, x, y in
                pending.append(.all(SRSuperBoom(player: UInt8(p), x: UInt8(x), y: UInt8(y)).encode()))
            },
            onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
            onShouldBroadcastDropPill: { pill, x, y in
                pending.append(.all(SRDropPill(pill: UInt8(pill), x: UInt8(x), y: UInt8(y)).encode()))
            }
        )

    case .refuel:
        guard let msg = CLRefuel.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClRefuel(
            player: player, base: Int(msg.base), armour: msg.armour, shells: msg.shells, mines: msg.mines, state: &state,
            onShouldBroadcastRefuel: { p, base, armour, shells, mines in
                pending.append(.allExcept(p, SRRefuel(base: UInt8(base), armour: armour, shells: shells, mines: mines).encode()))
            }
        )

    case .hitTank:
        guard let msg = CLHitTank.decode(bytes) else { throw HostSessionError.malformedMessage }
        // `msg.player` -- the tank being hit -- not this connection's own
        // `player` (`RecvCL.swift`'s doc comment on `recvClHitTank`).
        recvClHitTank(player: Int(msg.player), dir: msg.dir, onShouldBroadcastHitTank: { p, dir in
            pending.append(.one(p, SRHitTank(player: UInt8(p), dir: dir).encode()))
        })

    case .setAlliance:
        guard let msg = CLSetAlliance.decode(bytes) else { throw HostSessionError.malformedMessage }
        recvClSetAlliance(player: player, alliance: msg.alliance, state: &state, onShouldBroadcastAlliance: { p, alliance in
            pending.append(.allExcept(p, SRSetAlliance(player: UInt8(p), alliance: alliance).encode()))
        })
    }

    await flush(pending, table: table)
}

/// Reads one full `CL*` opcode message off `connection`, decodes it, and dispatches it -- the
/// original Wave 6.4b combined shape, now a thin wrapper over the I/O/pure split above (B.5c).
/// Preserved so every existing caller (`HostSessionTests.swift`'s ~15 call sites) keeps working
/// unchanged. Returns the opcode that was dispatched; the caller (`HostListener`'s per-player
/// receive loop) treats `.hangUp` as T-13's "normal exit" signal.
@discardableResult
public func receiveAndDispatchOneHostMessage(
    connection: NWConnection, player: Int, state: inout GameState, table: HostSessionTable,
    callbacks: CLDispatchCallbacks = CLDispatchCallbacks()
) async throws -> ClientOpcode {
    let (opcode, bytes) = try await receiveOneHostMessageBytes(from: connection)
    try await dispatchHostMessage(opcode: opcode, bytes: bytes, player: player, state: &state, table: table, callbacks: callbacks)
    return opcode
}
