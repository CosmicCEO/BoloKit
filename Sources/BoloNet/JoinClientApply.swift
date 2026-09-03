import BoloKit

// MARK: - Wave 6.4a extension (D45) — client-side preamble application
//
// Ported from `joinclient()`'s state-modification block
// (`client.c:690-750`) -- the piece PARITY's Wave 6.4a audit found
// missing: `joinClient` (`JoinClient.swift`) returns a decoded
// `BoloPreamble` + map bytes, but nothing turned that into an
// initialized `GameState`. Lives in `BoloNet`, not `BoloKit`, for the
// same reason `assembleBoloPreamble` does -- it bridges a `BoloNet` wire
// type onto a `BoloKit` `GameState`.
//
// `increasevis`/fog and `lockclient`/`unlockclient` (mutex -- no
// concurrent access to guard against a single `inout GameState`) are
// skipped, matching this port's established precedents. No callback for
// `joinprogress(kJoinSUCCESS, ...)` -- this function's own successful
// return already communicates "join complete" to its caller.

/// Applies a joined `BoloPreamble` + its accompanying map bytes
/// (`joinClient`'s return value) onto `state`, fully initializing it:
/// assigns `state.localPlayer`, decodes the map (via `decodeBMap`,
/// itself a Wave 6.4a-extension port of `clientloadmap()`), initializes
/// every player slot, and spawns the local tank. Returns `false` if the
/// map bytes are malformed -- the same failure mode `clientloadmap()`
/// itself has, ported as a `Bool` rather than a thrown error to match
/// `decodeBMap`'s own convention.
@discardableResult
public func applyBoloPreamble(
    _ preamble: BoloPreamble, mapData: [UInt8], state: inout GameState,
    onPlayerStatusChanged: (Int) -> Void = { _ in },
    onPillStatusChanged: (Int) -> Void = { _ in },
    onBaseStatusChanged: (Int) -> Void = { _ in }
) -> Bool {
    state.localPlayer = Int(preamble.player)
    state.hiddenMines = preamble.hiddenMines != 0

    // Wire-domain, mirrors `client.pause` -- the same 255->-1 sentinel
    // translation `RecvSR.swift`'s `recvSrPause` already established for
    // this exact field (D39's split), not a new pattern.
    state.clientPauseDisplaySeconds = preamble.pause == 255 ? -1 : Int(preamble.pause)

    // Inverse of `assembleBoloPreamble`'s own 0/1/2 mapping
    // (`Preambles.swift`). C's `default: assert(0)` on an invalid byte --
    // guarded here (state.dominationType left at its prior value) rather
    // than trapped, since there's no oracle behavior to match past a
    // malformed byte.
    switch preamble.dominationType {
    case 0: state.dominationType = .open
    case 1: state.dominationType = .tournament
    case 2: state.dominationType = .strict
    default: break
    }

    // `preamble.players` is always exactly `maxPlayers` entries
    // (`BoloPreamble`'s own invariant); `state.players` may be shorter
    // (every existing fixture in this port) -- grow it to match rather
    // than silently dropping slots, since this function's whole job is
    // to fully initialize `state` from what the server sent.
    for i in 0..<preamble.players.count {
        if i >= state.players.count {
            state.players.append(PlayerState())
        }
        let entry = preamble.players[i]
        state.players[i].used = entry.used
        state.players[i].connected = entry.connected
        state.players[i].name = entry.name
        state.players[i].host = entry.host
        state.players[i].alliance = entry.alliance
        // Fixed value, not data-driven -- matches `client.c:727`'s
        // unconditional `kBuilderReady` assignment exactly.
        state.players[i].builderStatus = .ready
        onPlayerStatusChanged(i)
    }

    guard decodeBMap(mapData, into: &state) else { return false }

    spawn(state: &state)

    for i in state.pills.indices {
        onPillStatusChanged(i)
    }
    for i in state.bases.indices {
        onBaseStatusChanged(i)
    }

    return true
}
