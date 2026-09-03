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
private func removePlayerPills(player: Int, state: inout GameState) {
    var pills: UInt16 = 0
    for i in state.pills.indices where Int(state.pills[i].owner) == player && state.pills[i].armour == pillOnboard {
        pills |= 1 << i
    }
    dropPills(player: player, x: state.players[player].tank.x, y: state.players[player].tank.y, pills: pills, state: &state)
}

/// Ported from `kickplayer()` (`server.c:475-501`). Unlike `banPlayer`
/// below, the real C has no `cntlsock != -1` guard here — calling this on
/// an already-disconnected player is the caller's contract to avoid
/// (`removeplayer()`'s own `assert`), matching this port's established
/// precedent of not adding defensive guards C itself doesn't have (see
/// `GameState.localPlayer`'s invariant, same rule).
public func kickPlayer(player: Int, state: inout GameState, onShouldBroadcastPlayerKick: (Int) -> Void = { _ in }) {
    onShouldBroadcastPlayerKick(player)
    state.players[player].connected = false
    removePlayerPills(player: player, state: &state)
}

/// Ported from `banplayer()` (`server.c:503-535`). The `cntlsock != -1`
/// guard here IS real business logic (banning an already-disconnected
/// player is a silent no-op in the C, not an assertion precondition) —
/// replicated faithfully, not dropped as redundant with `kickPlayer`'s
/// lack of one.
public func banPlayer(player: Int, state: inout GameState, onShouldBroadcastPlayerBan: (Int) -> Void = { _ in }) {
    guard state.players[player].connected else { return }
    state.bannedPlayers.append(BannedPlayer(name: state.players[player].name, address: state.players[player].address))
    onShouldBroadcastPlayerBan(player)
    state.players[player].connected = false
    removePlayerPills(player: player, state: &state)
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
