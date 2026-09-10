import Darwin

// MARK: - Wave D137 — builder mouse control
//
// Ports `buildercommand()`/`getbuildertaskforcommand()` (client.c:6533-
// 6698), the raw-click-to-task resolution layer that `BuilderTick.swift`'s
// file header explicitly deferred as "out of scope" pending a real UI
// input path (see that file's header comment on `getbuildertaskforcommand`
// being a fog-of-war/UI concern). That deferral is resolved here.
//
// **Ground truth, not fog-of-war.** C resolves against
// `client.seentiles[at.y][at.x]` — the client's fog-of-war display cache.
// This port has never modeled `seentiles`/`fog` (D65, out of scope for the
// v1 vertical slice) and treats every tile as fully visible, so this
// resolves against `state.terrain` (ground truth) directly instead. For
// the BUILDERPILL case, C's `seentiles` folds "there's a pill here" into a
// synthetic `kFriendlyPillNNTile`/`kHostilePillNNTile` value that
// overrides the underlying terrain tile; here that's modeled directly as
// a `findPill` check ahead of the terrain switch, which is the ground-
// truth equivalent (same substitution `BuilderTick.swift`'s `repairPill`
// already made for the "trees needed" computation).
//
// **Unlimited range — no distance check, per Jerod's ruling (D137).**
// `buildercommand()` in C has none either (confirmed at client.c:6533-
// 6538): it just gates on builder availability and queues. Never add a
// distance cap here.
//
// **Dropped side effect:** C's `client.printmessage(MSGGAME, "Your
// builder cannot do that.  It would kill him.")` calls (mine-tile
// rejection branches) are not reproduced — no message-channel plumbing
// exists at this call site, and the return value (`kBuilderDoNothing`) is
// unaffected either way. Flagged, not silently dropped.

/// Builder-tool selection, matching C's `BUILDERTREE`..`BUILDERMINE`
/// (`bolo.h:150-155`; `BUILDERNILL = -1` has no case here — "no tool
/// selected" is modeled as `InputKeymap`/caller state, not this enum).
public enum BuilderCommandKind: Int, Hashable, Sendable {
    case tree = 0
    case road = 1
    case wall = 2
    case pill = 3
    case mine = 4
}

/// Ported from `getbuildertaskforcommand()` (client.c:6539-6698). See file
/// header for the `seentiles` → ground-truth-terrain/`findPill`
/// substitution.
public func resolveBuilderTask(command: BuilderCommandKind, target: Pointi, state: GameState) -> BuilderTask {
    let x = Int(target.x)
    let y = Int(target.y)

    if command == .pill, findPill(x: x, y: y, pills: state.pills) != nil {
        return .repairPill
    }

    guard let terrain = state.terrain[x, y] else { return .doNothing }

    switch command {
    case .tree:
        switch terrain {
        case .forest, .minedForest:
            return .getTree
        default:
            return .doNothing
        }

    case .road:
        switch terrain {
        case .forest, .minedForest:
            return .getTree
        case .river, .swamp0, .swamp1, .swamp2, .swamp3, .crater,
            .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3:
            return .buildRoad
        default:
            return .doNothing
        }

    case .wall:
        switch terrain {
        case .forest, .minedForest:
            return .getTree
        case .swamp0, .swamp1, .swamp2, .swamp3, .crater, .road,
            .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3,
            .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
            return .buildWall
        case .river:
            return .buildBoat
        default:
            return .doNothing
        }

    case .pill:
        switch terrain {
        case .forest, .minedForest:
            return .getTree
        case .swamp0, .swamp1, .swamp2, .swamp3, .crater, .road,
            .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3:
            return .buildPill
        default:
            return .doNothing
        }

    case .mine:
        switch terrain {
        case .swamp0, .swamp1, .swamp2, .swamp3, .crater, .road, .forest,
            .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3:
            return .placeMine
        default:
            return .doNothing
        }
    }
}

/// Ported from `buildercommand()` (client.c:6533-6538). Queues `(command,
/// target)` into the pending-command slot iff the builder isn't
/// parachuting, isn't dead, and no command is already pending — exactly
/// C's `nextbuildercommand == BUILDERNILL` gate. Resolution against
/// terrain (`getbuildertaskforcommand`) happens later, when
/// `builderTick`'s `.ready` case picks the pending command up (mirrors
/// C's `kBuilderReady` branch at client.c:4543-4545, which resolves and
/// immediately clears `nextbuildercommand` regardless of the outcome).
///
/// Unlimited range: no distance check against the target tile, matching
/// the C oracle exactly (D137).
public func queueBuilderCommand(command: BuilderCommandKind, target: Pointi, player: Int, state: inout GameState) {
    guard state.players[player].builderStatus != .parachute,
        state.players[player].pendingBuilderCommand == nil,
        !state.players[player].dead
    else { return }

    state.players[player].pendingBuilderCommand = command
    state.players[player].pendingBuilderTarget = target
}
