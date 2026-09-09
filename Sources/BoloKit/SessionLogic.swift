// MARK: - Server session logic (Wave 6.3)
//
// Pure decision logic ported from `joinplayerserver()`/`kickplayer()`/
// `banplayer()`/`removeplayer()` (server.c) and `requestalliance()`/
// `leavealliance()`/`recvclsetalliance()` (client.c/server.c). Every
// socket, buffer, and mutex operation those C functions also perform is
// out of scope here — Wave 6.4 owns the transport mechanism (D31/D32);
// this file only owns the `GameState` mutations and pass/fail decisions
// that don't depend on how bytes actually move.
//
// `increasevis`/`decreasevis`/`refresh`/`client.printmessage` calls in
// `requestalliance`/`leavealliance` are skipped here, consistent with the
// project-wide precedent already established for these exact four C
// calls (see `TankLocalTick.swift`, `BuilderTick.swift`, `RecvSR.swift`'s
// file headers): fog-of-war visibility and screen invalidation are pure
// rendering-layer concerns with no effect on `GameState`, never modeled
// anywhere in this port.

// MARK: - Join

public enum JoinRejection: Sendable, Equatable {
    /// `kBadVersionJOIN`.
    case badVersion
    /// `kBadPasswordJOIN`.
    case badPassword
    /// `kDisallowJOIN`.
    case notAllowed
    /// `kBannedPlayerJOIN`.
    case banned
    /// `kServerFullJOIN`.
    case serverFull
}

public enum JoinOutcome: Sendable, Equatable {
    case rejected(JoinRejection)
    case accepted(player: Int, rejoin: Bool)
}

/// Ported from `joinplayerserver()`'s pure decision chain
/// (`server.c:714-834`, up through slot selection — everything before
/// "initialize player"). Rejection order matches the C exactly: version,
/// then password, then `allowjoin`, then the ban list, then slot search.
///
/// `ticksSinceLastUpdate` mirrors `RunTick.swift`'s own parameter of the
/// same name/shape (Wave 6.1) — this port has no stored per-player
/// `lastupdate` field, so the LRU-eviction age (`server.ticks -
/// server.players[p].lastupdate`) is supplied by the caller rather than
/// read from `GameState`, the same call Wave 6.1 already made for the
/// disconnect-detection path.
public func evaluateJoinRequest(
    name: String,
    password: String,
    version: UInt8,
    address: String,
    passwordRequired: Bool,
    serverPassword: String,
    allowJoin: Bool,
    bannedPlayers: [BannedPlayer],
    players: [PlayerState],
    ticksSinceLastUpdate: [UInt64]
) -> JoinOutcome {
    guard version == netGameVersionForJoin else { return .rejected(.badVersion) }
    guard !passwordRequired || password == serverPassword else { return .rejected(.badPassword) }
    guard allowJoin else { return .rejected(.notAllowed) }
    guard !bannedPlayers.contains(where: { $0.name == name && $0.address == address }) else {
        return .rejected(.banned)
    }

    // Rejoin: a previously-used, currently-disconnected slot with a
    // matching name (`server.c:772-777`).
    if let rejoinSlot = players.indices.first(where: { players[$0].used && !players[$0].connected && players[$0].name == name }) {
        return .accepted(player: rejoinSlot, rejoin: true)
    }

    // Brand-new slot: first never-used, never-connected index
    // (`server.c:782-786`).
    if let freshSlot = players.indices.first(where: { !players[$0].used && !players[$0].connected }) {
        return .accepted(player: freshSlot, rejoin: false)
    }

    // No fresh slot: evict the *oldest* disconnected slot, ties won by
    // the lowest index (`server.c:789-806`'s strict `<` comparison keeps
    // the first-found slot on a tie, not the last).
    let disconnected = players.indices.filter { !players[$0].connected }
    if let oldest = disconnected.max(by: { ticksSinceLastUpdate[$0] < ticksSinceLastUpdate[$1] }) {
        return .accepted(player: oldest, rejoin: false)
    }

    return .rejected(.serverFull)
}

/// `NET_GAME_VERSION` (`bolo.h:27`) restated here rather than imported
/// from `BoloNet` — `BoloKit` has no dependency on `BoloNet` (the
/// dependency runs the other way), and this pure decision logic belongs
/// in `BoloKit` alongside every other `GameState` mutation, not the wire
/// package. `BoloNet.netGameVersion` must stay equal to this by
/// construction; `NetCodecDifferentialTests` covers the wire encoding
/// side, this is the one place the bare version number is compared.
let netGameVersionForJoin: UInt8 = 1

/// Ported from `joinplayerserver()`'s "initialize player" block
/// (`server.c:808-836`, state-affecting lines only — `cntlsock`/`addr`/
/// `dgramaddr`/`recvbuf`/`lastupdate` are transport session state, Wave
/// 6.4's concern). Call only with an outcome from `evaluateJoinRequest`.
public func applyJoin(player: Int, name: String, address: String, rejoin: Bool, state: inout GameState) {
    if !rejoin {
        state.players[player].alliance = UInt16(1 << player)
        state.players[player].name = name
    }
    state.players[player].used = true
    state.players[player].connected = true
    state.players[player].address = address
}

// MARK: - Kick / ban / remove

/// Ported from `removeplayer()`'s pure core (`server.c:585-599`) —
/// closing the socket and draining buffers is Wave 6.4's concern; the
/// only state-affecting work is computing which onboard pills `player`
/// owns and scattering them via the already-shipped `dropPills`
/// (`MineChain.swift`, Wave 5.5a).
private func removePlayerPills(
    player: Int, state: inout GameState,
    onShouldBroadcastDropPill: (Int, Int, Int) -> Void = { _, _, _ in }
) {
    var pills: UInt16 = 0
    for i in state.pills.indices where Int(state.pills[i].owner) == player && state.pills[i].armour == pillOnboard {
        pills |= 1 << i
    }
    dropPills(
        player: player, x: state.players[player].tank.x, y: state.players[player].tank.y, pills: pills, state: &state,
        onShouldBroadcastDropPill: onShouldBroadcastDropPill
    )
}

/// Ported from `removeplayer()`'s `GameState`-affecting core
/// (`server.c:584-608`) — closing the socket and draining the byte-queue
/// buffers (`closesock`/`readbuf`) is Wave 6.4b's transport concern
/// (`HostSessionTable`), along with the `seq = 0` reset (`server.c:594`),
/// which has no `GameState` home (Wave 6.0's own design call — this port
/// never stores per-player network sequence bookkeeping there, same as
/// `evaluateJoinRequest`'s `ticksSinceLastUpdate` parameter). Public
/// because `servermainthread`'s socket-close disconnect path
/// (`server.c:1667-1740`, four call sites) calls `removeplayer()`
/// directly — not only via `kickplayer()`/`banplayer()`, which both call
/// it as their own tail (`server.c:487`, `:525`, confirmed) and so are
/// rewritten below to call this instead of duplicating its body.
public func removePlayer(
    player: Int, state: inout GameState,
    onShouldBroadcastDropPill: (Int, Int, Int) -> Void = { _, _, _ in }
) {
    state.players[player].connected = false
    removePlayerPills(player: player, state: &state, onShouldBroadcastDropPill: onShouldBroadcastDropPill)
}

/// Ported from `kickplayer()` (`server.c:475-501`). Unlike `banPlayer`
/// below, the real C has no `cntlsock != -1` guard here — calling this on
/// an already-disconnected player is the caller's contract to avoid
/// (`removeplayer()`'s own `assert`), matching this port's established
/// precedent of not adding defensive guards C itself doesn't have (see
/// `GameState.localPlayer`'s invariant, same rule).
public func kickPlayer(
    player: Int, state: inout GameState,
    onShouldBroadcastPlayerKick: (Int) -> Void = { _ in },
    onShouldBroadcastDropPill: (Int, Int, Int) -> Void = { _, _, _ in }
) {
    onShouldBroadcastPlayerKick(player)
    removePlayer(player: player, state: &state, onShouldBroadcastDropPill: onShouldBroadcastDropPill)
}

/// Ported from `banplayer()` (`server.c:503-535`). The `cntlsock != -1`
/// guard here IS real business logic (banning an already-disconnected
/// player is a silent no-op in the C, not an assertion precondition) —
/// replicated faithfully, not dropped as redundant with `kickPlayer`'s
/// lack of one.
public func banPlayer(
    player: Int, state: inout GameState,
    onShouldBroadcastPlayerBan: (Int) -> Void = { _ in },
    onShouldBroadcastDropPill: (Int, Int, Int) -> Void = { _, _, _ in }
) {
    guard state.players[player].connected else { return }
    state.bannedPlayers.append(BannedPlayer(name: state.players[player].name, address: state.players[player].address))
    onShouldBroadcastPlayerBan(player)
    removePlayer(player: player, state: &state, onShouldBroadcastDropPill: onShouldBroadcastDropPill)
}

// MARK: - Alliance

/// Ported from `requestalliance()`'s state-affecting core
/// (`client.c:6314-6320`, plus the notification loop's callback-worthy
/// branches only — see the file header for why `printmessage`/
/// `increasevis`/`refresh` are skipped). `onPlayerStatusChanged` fires for
/// every player whose alliance-with-me just became mutual (the C's
/// "accepted" branch only — the "requested" branch has no `GameState`
/// effect, just a message, so no callback fires for it).
public func requestAlliance(
    withPlayers: UInt16, state: inout GameState,
    onSendSetAlliance: (UInt16) -> Void = { _ in },
    onPlayerStatusChanged: (Int) -> Void = { _ in },
    onBaseStatusChanged: (Int) -> Void = { _ in },
    onPillStatusChanged: (Int) -> Void = { _ in }
) {
    let localPlayer = state.localPlayer
    let xor = state.players[localPlayer].alliance ^ (state.players[localPlayer].alliance | withPlayers)
    state.players[localPlayer].alliance |= withPlayers
    onSendSetAlliance(state.players[localPlayer].alliance)

    for i in state.players.indices where state.players[i].connected && (xor & (1 << i)) != 0 {
        guard state.players[i].alliance & (1 << localPlayer) != 0 else { continue }
        onPlayerStatusChanged(i)
        for j in state.bases.indices where Int(state.bases[j].owner) == i {
            onBaseStatusChanged(j)
        }
        for j in state.pills.indices where Int(state.pills[j].owner) == i {
            onPillStatusChanged(j)
        }
    }
}

/// Ported from `leavealliance()`'s state-affecting core
/// (`client.c:6389-6396`, plus the notification loop). This is the real
/// implementation `RecvSR.swift`'s `recvSrSetAlliance` surfaced as
/// `onShouldLeaveAlliance` (Wave 6.2 Finding 3) rather than duplicating —
/// wire the two together at whatever call site owns both (Wave 6.4's
/// dispatch glue), not inside `RecvSR.swift` itself.
public func leaveAlliance(
    withPlayers: UInt16, state: inout GameState,
    onSendSetAlliance: (UInt16) -> Void = { _ in },
    onPlayerStatusChanged: (Int) -> Void = { _ in },
    onBaseStatusChanged: (Int) -> Void = { _ in },
    onPillStatusChanged: (Int) -> Void = { _ in }
) {
    let localPlayer = state.localPlayer
    let keepMask: UInt16 = ~withPlayers | UInt16(1 << localPlayer)
    let xor = state.players[localPlayer].alliance ^ (state.players[localPlayer].alliance & keepMask)
    state.players[localPlayer].alliance &= keepMask
    onSendSetAlliance(state.players[localPlayer].alliance)

    for i in state.players.indices where state.players[i].connected && (xor & (1 << i)) != 0 {
        guard state.players[i].alliance & (1 << localPlayer) != 0 else { continue }
        onPlayerStatusChanged(i)
        for j in state.bases.indices where Int(state.bases[j].owner) == i {
            onBaseStatusChanged(j)
        }
        for j in state.pills.indices where Int(state.pills[j].owner) == i {
            onPillStatusChanged(j)
        }
    }
}

/// Ported from `recvclsetalliance()` (`server.c:3123-3143`) — the
/// server's role in the alliance handshake is a trivial accept-and-
/// broadcast with **no** consent-checking of its own; the mutual-consent
/// negotiation lives entirely client-side in `requestAlliance`/
/// `leaveAlliance` above. Not a bug to "fix" — a real, deliberate
/// asymmetry in the original protocol (flagged in the Wave 6.3 pre-brief,
/// reconfirmed here).
public func recvClSetAlliance(player: Int, alliance: UInt16, state: inout GameState, onShouldBroadcastAlliance: (Int, UInt16) -> Void = { _, _ in }) {
    state.players[player].alliance = alliance
    onShouldBroadcastAlliance(player, alliance)
}

// MARK: - Host-admin: pause/resume, allow-join, unban (1.1, D129)
//
// `lockserver()`/`unlockserver()` (`server.c:454-476`) are NOT ported here or anywhere in this
// port: reading the actual bodies (confirmed directly, not assumed from the name) shows they are
// a bare `pthread_mutex_lock`/`pthread_mutex_unlock` pair on `server.mutex` -- every one of C's
// admin functions (`kickplayer`/`banplayer`/`pauseresumeserver`/`togglejoinserver`) calls
// `lockserver()` first purely to serialize concurrent access to the global `server` struct across
// threads (`server.h:374`: "lock server first before calling these"). There is no user-facing
// "lock the game" feature anywhere in the C reference. `HostGameEngine`'s single-consumer actor
// loop (`HostGameEngine.swift`'s own file header) already guarantees every `state` mutation is
// serialized by construction, making this mutex structurally redundant here -- the same class of
// skip this file's own header already documents for `increasevis`/`refresh`/`printmessage` (no
// `GameState` effect, a mechanism artifact of C's threading model, not an observable behavior).

/// Ported from `pauseserver()` (`server.c:373-378`). No-op when already paused
/// (`getpauseserver()`'s guard) -- real business logic, not a defensive addition: mid-countdown
/// (`serverPauseTicks > 0`), calling this re-pauses to `-1` instead of leaving the countdown
/// running, matching C's own `if (!getpauseserver())` guard exactly.
public func pauseServer(state: inout GameState, onShouldBroadcastPause: (UInt8) -> Void = { _ in }) {
    guard state.serverPauseTicks != -1 else { return }
    state.serverPauseTicks = -1
    onShouldBroadcastPause(255)
}

/// Ported from `resumeserver()` (`server.c:380-384`). No-op unless currently paused indefinitely
/// (`getpauseserver()`'s guard) -- calling this mid-countdown (`serverPauseTicks > 0`) does
/// nothing, matching C exactly. Resuming does NOT unfreeze the simulation immediately: it starts
/// a `TICKSPERSEC*5` countdown (`runTick`'s existing pause gate, `RunTick.swift:87-95`, already
/// ticks this down and fires `onPause` each second) -- the sim stays frozen for five more seconds.
public func resumeServer(state: inout GameState, onShouldBroadcastPause: (UInt8) -> Void = { _ in }) {
    guard state.serverPauseTicks == -1 else { return }
    state.serverPauseTicks = Int(ticksPerSec) * 5
    onShouldBroadcastPause(UInt8(state.serverPauseTicks / Int(ticksPerSec)))
}

/// Ported from `pauseresumeserver()` (`server.c:387-408`) -- the `lockserver()`/`unlockserver()`
/// calls bracketing its body are the mutex discussed above, not ported; its only real logic is
/// the toggle between `resumeServer`/`pauseServer` based on `getpauseserver()`.
public func pauseResumeServer(state: inout GameState, onShouldBroadcastPause: (UInt8) -> Void = { _ in }) {
    if state.serverPauseTicks == -1 {
        resumeServer(state: &state, onShouldBroadcastPause: onShouldBroadcastPause)
    } else {
        pauseServer(state: &state, onShouldBroadcastPause: onShouldBroadcastPause)
    }
}

/// Ported from `setallowjoinserver()` (`server.c:423-425`). Trivial flag flip -- no broadcast, no
/// other `GameState` effect (confirmed by direct read; unlike pause, nothing in `server.c` sends a
/// wire message when `allowjoin` changes).
public func setAllowJoin(_ allowJoin: Bool, state: inout GameState) {
    state.allowJoin = allowJoin
}

/// Ported from `togglejoinserver()` (`server.c:427-448`) -- again, the `lockserver()`/
/// `unlockserver()` bracket is the mutex, not ported; the only real logic is the flip itself.
public func toggleAllowJoin(state: inout GameState) {
    state.allowJoin.toggle()
}

/// Ported from `unbanplayer()` (`server.c:550-571`). **Positional index into the ban list**, not
/// a name/address match (confirmed by direct read -- the C walks `server.bannedplayers` with a
/// plain counter, unlike `evaluateJoinRequest`'s ban *check*, which does match on name+address).
/// An out-of-range index is a silent no-op in the C (`if (node != NULL) { removelist(...) }`),
/// replicated here as a bounds guard rather than a precondition.
public func unbanPlayer(index: Int, state: inout GameState) {
    guard state.bannedPlayers.indices.contains(index) else { return }
    state.bannedPlayers.remove(at: index)
}
