import BoloKit

// MARK: - Wave 6.4b — dgramserver()'s pure per-packet decision core
//
// Ported from `dgramserver()` (`Reference/c/server.c:614-696`), minus the
// `recvfrom`/`sendto` socket calls and the outer `for (;;)` drain loop --
// those are `HostListener`'s transport mechanism (Wave 6.4b), this is
// only the decision made about one already-received datagram, given the
// server's already-known per-player session state.
//
// **T-2, load-bearing:** the real `dgramserver()` applies only
// `tank.x`/`tank.y` from the decoded header (`server.c:670-672`) --
// nothing else. Do NOT reuse `applyRemotePlayerUpdate`
// (`DgramClientApply.swift`, Wave 6.4a), which applies ~15 fields plus
// shells/explosions/dead-reckoning; that function ports the *client's*
// `dgramclient()`, a materially different, much richer role. The C
// server's own player record (`server.h:100-116`) doesn't even have most
// of those fields to apply to.

/// The three fields of a UDP peer's `sockaddr_in` the real comparison
/// actually reads (`sin_family`, `sin_addr.s_addr`, `sin_port`) --
/// `sin_family` is `uint8_t` on Darwin's `struct sockaddr_in`, matched
/// here rather than widened, since this exists to faithfully decompose
/// that comparison, not to be a general-purpose address type.
public struct DgramServerPeerAddress: Sendable, Equatable, Hashable {
    public var family: UInt8
    public var addr: UInt32
    public var port: UInt16
    public init(family: UInt8, addr: UInt32, port: UInt16) {
        self.family = family
        self.addr = addr
        self.port = port
    }
}

/// One player slot's dgram-relevant session state -- the subset of
/// `server.players[i]` that `GameState` deliberately doesn't store (Wave
/// 6.4b pre-brief §1: `used`/`connected` DO have a `GameState` home,
/// carried here too only because the decision below needs to read them
/// alongside the three fields that don't). `connected` mirrors `cntlsock
/// != -1`. Caller (`HostSessionTable`) must supply exactly `maxPlayers`
/// entries, indexed by wire player number, matching `server.players
/// [MAXPLAYERS]`'s own fixed-size array -- no defensive bounds guard here,
/// matching this port's established "trust the caller's contract" rule
/// for wire-indexed lookups (`DgramClientApply.swift`'s `state.players
/// [player]`, same precedent).
public struct DgramServerPlayerSessionState: Sendable {
    public var used: Bool
    public var connected: Bool
    public var dgramAddress: DgramServerPeerAddress
    /// Mirrors `server.players[i].seq` (`uint32_t` in the C, stored here
    /// as `Int32` to match `CLUpdateHeader.seq`'s element type and reuse
    /// `isNewerSeq` directly -- same bit pattern either way).
    public var seq: Int32

    public init(used: Bool, connected: Bool, dgramAddress: DgramServerPeerAddress, seq: Int32) {
        self.used = used
        self.connected = connected
        self.dgramAddress = dgramAddress
        self.seq = seq
    }
}

public enum DgramServerRelayDecision: Sendable, Equatable {
    /// `server.c:637-645` -- reply to the sender with the exact same
    /// bytes it sent (T-4: this echo, unlike `registerserver()`'s, is
    /// never zeroed).
    case trackerEcho
    /// Failed `CLUpdate.decode`'s own sanity check (T-6: reused directly
    /// rather than re-derived -- it's already `server.c:648-654`'s exact
    /// length/player-range guard). Drop silently, matching the C's own
    /// `continue`.
    case malformed
    /// Passed the sanity check but the sender isn't a currently-valid
    /// player for this address (T-3), or the update isn't newer than what
    /// this player's slot already has stored (T-7). Drop silently -- no
    /// state change, no relay.
    case dropped
    /// Apply and relay. `tank` is `header.tank`, unpacked for the caller
    /// to write into `GameState.players[player].tank` (T-2 -- nothing
    /// else from the header is applied). `newSeq` is what the caller's
    /// `DgramServerPlayerSessionState.seq` for `player` should advance to
    /// (T-1: the *reset-to-0* half of that field's lifecycle happens at
    /// disconnect, not here -- this path only ever advances it).
    /// `portUpdate`, if non-nil, is the new port the caller's session
    /// table should store for `player` (T-3). `relayTo` is exactly the
    /// slot indices to forward the ORIGINAL received bytes to, verbatim,
    /// unre-encoded (T-8).
    case applied(player: Int, tank: Vec2f, newSeq: Int32, portUpdate: UInt16?, relayTo: [Int])
}

/// `server.c:637-645`'s raw byte-level pattern, checked strictly before
/// any `CLUpdate.decode` attempt. **T-5, load-bearing:** `player == 255`
/// fails `decode`'s own `player < maxPlayers` guard, so this check cannot
/// be folded into a branch on `decode`'s result -- it has to run first,
/// on the raw bytes, exactly mirroring the C's `if`/`else if` ordering
/// (`server.c:635` vs. `:648`).
private func isTrackerEchoDatagram(_ bytes: [UInt8]) -> Bool {
    bytes.count == CLUpdateHeader.wireSize && bytes.first == 255
}

/// One call handles exactly one already-received datagram.
public func decodeDgramServerRelay(
    _ bytes: [UInt8], from address: DgramServerPeerAddress, players: [DgramServerPlayerSessionState]
) -> DgramServerRelayDecision {
    if isTrackerEchoDatagram(bytes) {
        return .trackerEcho
    }

    guard let update = CLUpdate.decode(bytes) else {
        return .malformed
    }

    let player = Int(update.header.player)
    let seq = update.header.seq[player]

    // Verify this is a valid player (server.c:663-667) -- family+addr
    // match; port is deliberately excluded from validity (T-3): the C
    // updates `dgramaddr.sin_port` from every accepted packet rather than
    // treating a port change as invalidating the sender.
    guard
        players[player].used,
        players[player].connected,
        players[player].dgramAddress.family == address.family,
        players[player].dgramAddress.addr == address.addr
    else {
        return .dropped
    }

    // Make sure this is not an old update (server.c:668). Everything
    // past this point -- seq store, tank apply, port update, relay -- sits
    // inside this one gate in the C (T-7); a stale packet does none of
    // them, not even the port refresh.
    guard isNewerSeq(seq, than: players[player].seq) else {
        return .dropped
    }

    let portUpdate: UInt16? = players[player].dgramAddress.port != address.port ? address.port : nil

    // Send update to all other players (server.c:678-684) -- deliberately
    // does NOT check `used`, only `connected` (T-8).
    let relayTo = players.indices.filter { $0 != player && players[$0].connected }

    return .applied(player: player, tank: update.header.tank, newSeq: seq, portUpdate: portUpdate, relayTo: relayTo)
}
