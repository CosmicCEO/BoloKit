// MARK: - Wave 6.6 — server TCP-receive handlers for `CL*` messages
//
// Ported from `server.c`'s ~19 `recvcl*` functions (server.c:2059-3123),
// covering every client→server opcode except `CLSetAlliance` (already
// shipped as `recvClSetAlliance`, `SessionLogic.swift`, Wave 6.3).
// `recvclsendmesg` is excluded here too — it has zero `GameState` effect,
// pure broadcast relay, matching Wave 6.2's prior finding for `sendmesg`/
// `timelimit`/`basecontrol`.
//
// Every socket/buffer read (`recvbuf`, `readbuf`) is out of scope — Wave
// 6.4's transport concern. Functions here take already-decoded plain
// values, matching every prior wave's convention (`RecvSR.swift` etc.).
//
// **D40 applies to `recvClBuildRoad`**: `clbuildroad->trees >=
// clbuildroad->trees` (server.c:2416) is a self-comparison, always true —
// replicated bug-for-bug per Planner's ruling, not corrected to
// `ROADTREES`.
//
// **Correction to this wave's own pre-brief:** `ShellTick.swift`'s
// `touchTile` (Wave 5.3a) does *not* already port `recvcltouch()` despite
// sharing a doc-comment citation — it's a shell-expiry helper with its own
// generic `onMineExplosion` passthrough, called from a different trigger
// entirely (`shellTick`, not the network layer). `recvClTouch` below calls
// `explosionAt` directly, in the same bucket as every other new
// mined-terrain trigger site, not delegated to `touchTile`.
//
// **New finding, worked around locally, not fixed at the source:**
// `explosionAt`/`superboomAt` (`MineChain.swift`, Wave 5.5a) have no
// broadcast-trigger callback of their own — the real `explosionat()`/
// `superboomat()` call `sendsrsmallboom`/`sendsrsuperboom` *internally*
// (server.c:4121-4249). Every function below that reaches a mined-terrain
// branch re-derives the same terrain-membership predicate those engine
// functions already use internally (rather than modifying their already-
// shipped, audited signatures) to know when to fire
// `onShouldBroadcastSmallBoom` itself. Two asymmetries worth flagging,
// both confirmed by direct read, not assumed: `explosionat()`'s broadcast
// always attributes to `playerNeutral`, never the real causer
// (server.c:4160); `superboomat()`'s broadcast uses the real causer and
// fires unconditionally, no terrain-membership gate at all
// (server.c:4243) — the two are not symmetric.

// MARK: - Boats and mines

/// Ported from `recvcldropboat()` (`server.c:2100-2126`).
public func recvClDropBoat(x: Int, y: Int, state: inout GameState, onShouldBroadcastDropBoat: (Int, Int) -> Void = { _, _ in }) {
    guard ispointinrect(seaRect, Pointi(x: Int32(x), y: Int32(y))) != 0 else { return }
    guard state.terrain[x, y] == .river else { return }
    state.terrain[x, y] = .boat
    onShouldBroadcastDropBoat(x, y)
}

/// Ported from `recvcldroppills()` (`server.c:2127-2163`) — a validation
/// wrapper around the already-shipped `dropPills` (`MineChain.swift`,
/// Wave 5.5a): every requested pill bit must actually be an onboard pill
/// owned by `player`, and the drop point must be strictly inside the map
/// (`0 < x/y < 256`), or the whole request is silently dropped. No
/// broadcast of any kind fires from this function itself — matches the
/// C exactly (`droppills()`/`dr()` handle their own `sendsrdroppill` per
/// pill, already the case in the shipped `dropPillSearch`).
public func recvClDropPills(player: Int, x: Float, y: Float, pills: UInt16, state: inout GameState) {
    for i in state.pills.indices where (pills & (1 << i)) != 0 {
        guard Int(state.pills[i].owner) == player, state.pills[i].armour == pillOnboard else { return }
    }
    guard x > 0.0, x < 256.0, y > 0.0, y < 256.0 else { return }
    dropPills(player: player, x: x, y: y, pills: pills, state: &state)
}

/// Ported from `recvcldropmine()` (`server.c:2164-2235`) — a direct
/// tank-triggered mine placement, distinct from the builder-driven
/// `recvClPlaceMine` below (a different C function, `sendsrmineack`
/// vs. `sendsrbuilderack`, never merged).
public func recvClDropMine(
    player: Int, x: Int, y: Int, state: inout GameState,
    onShouldBroadcastDropMine: (Int, Int, Int) -> Void = { _, _, _ in },
    onShouldBroadcastMineAck: (Int, Bool) -> Void = { _, _ in }
) {
    guard ispointinrect(seaRect, Pointi(x: Int32(x), y: Int32(y))) != 0 else { return }
    guard let terrain = state.terrain[x, y] else { return }
    switch terrain {
    case .swamp0, .swamp1, .swamp2, .swamp3:
        state.terrain[x, y] = .minedSwamp
    case .crater:
        state.terrain[x, y] = .minedCrater
    case .road:
        state.terrain[x, y] = .minedRoad
    case .forest:
        state.terrain[x, y] = .minedForest
    case .rubble0, .rubble1, .rubble2, .rubble3:
        state.terrain[x, y] = .minedRubble
    case .grass0, .grass1, .grass2, .grass3:
        state.terrain[x, y] = .minedGrass
    default:
        onShouldBroadcastMineAck(player, false)
        return
    }
    onShouldBroadcastDropMine(player, x, y)
    onShouldBroadcastMineAck(player, true)
}

// MARK: - Touch / grab

/// Ported from `recvcltouch()` (`server.c:2236-2270`). See file header —
/// this does *not* delegate to `ShellTick.swift`'s `touchTile`, a
/// different helper for a different trigger.
public func recvClTouch(
    player: Int, x: Int, y: Int, state: inout GameState,
    onShouldBroadcastSmallBoom: (UInt8, Int, Int) -> Void = { _, _, _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard let terrain = state.terrain[x, y] else { return }
    switch terrain {
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        explosionAt(
            player: UInt8(player), x: x, y: y, state: &state,
            onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
        )
        onShouldBroadcastSmallBoom(playerNeutral, x, y)
    default:
        break
    }
}

/// Ported from `recvclgrabtile()` (`server.c:2271-2346`). Base capture's
/// three-way branch (neutral / mutually-allied hand-off / hostile
/// takeover) mirrors the same mutual-alliance shape `testAlliance`
/// already models elsewhere in this port (e.g. `RecvSR.swift`'s base
/// damage heating).
public func recvClGrabTile(
    player: Int, x: Int, y: Int, state: inout GameState,
    onShouldBroadcastCapturePill: (Int, UInt8) -> Void = { _, _ in },
    onShouldBroadcastCaptureBase: (Int, UInt8) -> Void = { _, _ in },
    onShouldBroadcastGrabBoat: (Int, Int, Int) -> Void = { _, _, _ in },
    onShouldBroadcastSmallBoom: (UInt8, Int, Int) -> Void = { _, _, _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    if let pill = findPill(x: x, y: y, pills: state.pills) {
        state.pills[pill].owner = UInt8(player)
        state.pills[pill].armour = pillOnboard
        state.pills[pill].speed = UInt8(maxTicksPerShot)
        // `sendsrcapturepill()` reads `server.pills[pill].owner` itself,
        // AFTER the assignment above (server.c:3528) -- passed here for
        // the same exclusivity reason `onShouldBroadcastBuild` documents.
        onShouldBroadcastCapturePill(pill, state.pills[pill].owner)
    }

    if let base = findBase(x: x, y: y, bases: state.bases) {
        if state.bases[base].owner == playerNeutral {
            state.bases[base].owner = UInt8(player)
            state.bases[base].armour = UInt8(maxBaseArmour)
            state.bases[base].shells = UInt8(maxBaseShells)
            state.bases[base].mines = UInt8(maxBaseMines)
        } else if testAlliance(Int(state.bases[base].owner), player, players: state.players) {
            state.bases[base].owner = UInt8(player)
        } else {
            state.bases[base].owner = UInt8(player)
            state.bases[base].armour = 0
            state.bases[base].shells = 0
            state.bases[base].mines = 0
        }
        // `sendsrcapturebase()` reads `server.bases[base].owner` itself
        // (server.c:3604), same reason as `onShouldBroadcastCapturePill`.
        onShouldBroadcastCaptureBase(base, state.bases[base].owner)
    }

    guard let terrain = state.terrain[x, y] else { return }
    switch terrain {
    case .boat:
        state.terrain[x, y] = .river
        onShouldBroadcastGrabBoat(player, x, y)
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        explosionAt(
            player: UInt8(player), x: x, y: y, state: &state,
            onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
        )
        onShouldBroadcastSmallBoom(playerNeutral, x, y)
    default:
        break
    }
}

/// Ported from `recvclgrabtrees()` (`server.c:2347-2392`). `.minedForest`
/// is deliberately excluded from the detonation case list below — it's
/// harvested safely into `.minedGrass` by the dedicated case above it,
/// unlike every other mined variant.
public func recvClGrabTrees(
    player: Int, x: Int, y: Int, state: inout GameState,
    onShouldBroadcastGrabTrees: (Int, Int) -> Void = { _, _ in },
    onShouldBroadcastBuilderAck: (Int, Int, Int, Int) -> Void = { _, _, _, _ in },
    onShouldBroadcastSmallBoom: (UInt8, Int, Int) -> Void = { _, _, _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard let terrain = state.terrain[x, y] else {
        onShouldBroadcastBuilderAck(player, 0, 0, Int(noPill))
        return
    }
    switch terrain {
    case .forest:
        state.terrain[x, y] = .grass3
        onShouldBroadcastGrabTrees(x, y)
        onShouldBroadcastBuilderAck(player, 0, forestTreeYield, Int(noPill))
    case .minedForest:
        state.terrain[x, y] = .minedGrass
        onShouldBroadcastGrabTrees(x, y)
        onShouldBroadcastBuilderAck(player, 0, forestTreeYield, Int(noPill))
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedRubble, .minedGrass:
        explosionAt(
            player: UInt8(player), x: x, y: y, state: &state,
            onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
        )
        onShouldBroadcastSmallBoom(playerNeutral, x, y)
        onShouldBroadcastBuilderAck(player, 0, 0, Int(noPill))
    default:
        onShouldBroadcastBuilderAck(player, 0, 0, Int(noPill))
    }
}

// MARK: - Construction

/// Ported from `recvclbuildroad()` (`server.c:2393-2444`). **D40:**
/// `clbuildroad->trees >= clbuildroad->trees` (server.c:2416) is a
/// self-comparison, always true in the real oracle — the tree-cost check
/// is dead code there, and this is replicated bug-for-bug rather than
/// corrected to `ROADTREES`, per Planner's ruling: a deterministic,
/// well-defined comparison (unlike `applyDamage`'s `pills[-1]` UB case),
/// so there's no memory-safety reason to deviate, and silently
/// correcting it would make this port's construction economy diverge
/// from the oracle it's supposed to match. A real second-order effect,
/// not just "the check is skipped": since the success branch is the only
/// reachable one, `trees - roadTrees` can go negative when `trees <
/// roadTrees` — passed through as-is (`Int`, not wire-truncated here);
/// whatever constructs the real `SRBuilderAck` from this callback's
/// arguments inherits the C's own `uint8_t` wraparound when it narrows.
public func recvClBuildRoad(
    player: Int, x: Int, y: Int, trees: Int, state: inout GameState,
    onShouldBroadcastBuild: (Int, Int, UInt8) -> Void = { _, _, _ in },
    onShouldBroadcastBuilderAck: (Int, Int, Int, Int) -> Void = { _, _, _, _ in },
    onShouldBroadcastSmallBoom: (UInt8, Int, Int) -> Void = { _, _, _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard let terrain = state.terrain[x, y] else {
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
        return
    }
    switch terrain {
    case .river, .swamp0, .swamp1, .swamp2, .swamp3, .crater,
        .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3:
        if trees >= trees {
            state.terrain[x, y] = .road
            // `sendsrbuild()` reads `server.terrain[y][x]` itself, AFTER
            // the mutation above (server.c:3232) -- passed here as the
            // raw wire byte (`Terrain.road.rawValue`) rather than
            // re-derived from a closure reading `state` mid-call, which
            // Swift's exclusivity rules don't allow across this same
            // `state: &state` formal access (same class of constraint
            // this file's own header already documents for `applyDamage`).
            onShouldBroadcastBuild(x, y, UInt8(Terrain.road.rawValue))
            onShouldBroadcastBuilderAck(player, 0, trees - roadTrees, Int(noPill))
        } else {
            onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
        }
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        explosionAt(
            player: UInt8(player), x: x, y: y, state: &state,
            onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
        )
        onShouldBroadcastSmallBoom(playerNeutral, x, y)
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
    default:
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
    }
}

/// Ported from `recvclbuildwall()` (`server.c:2452-2515`). Unlike
/// `recvClBuildRoad`, the `trees >= wallTrees` check here is real
/// (confirmed by direct read — the two functions are not the same shape
/// despite looking similar).
public func recvClBuildWall(
    player: Int, x: Int, y: Int, trees: Int, state: inout GameState,
    onShouldBroadcastBuild: (Int, Int, UInt8) -> Void = { _, _, _ in },
    onShouldBroadcastBuilderAck: (Int, Int, Int, Int) -> Void = { _, _, _, _ in },
    onShouldBroadcastSmallBoom: (UInt8, Int, Int) -> Void = { _, _, _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard let terrain = state.terrain[x, y] else {
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
        return
    }
    switch terrain {
    case .swamp0, .swamp1, .swamp2, .swamp3, .crater, .road,
        .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3,
        .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
        if trees >= wallTrees {
            state.terrain[x, y] = .wall
            onShouldBroadcastBuild(x, y, UInt8(Terrain.wall.rawValue))
            onShouldBroadcastBuilderAck(player, 0, trees - wallTrees, Int(noPill))
        } else {
            onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
        }
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        explosionAt(
            player: UInt8(player), x: x, y: y, state: &state,
            onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
        )
        onShouldBroadcastSmallBoom(playerNeutral, x, y)
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
    default:
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
    }
}

/// Ported from `recvclbuildboat()` (`server.c:2516-2557`). No tree-cost
/// gate at all here — confirmed by direct read, not an omission on this
/// port's part: unlike `buildwall`, the real C never compares `trees`
/// against `boatTrees` before converting the terrain, it only uses
/// `boatTrees` in the leftover-trees arithmetic. Building a boat on a
/// river always succeeds.
public func recvClBuildBoat(
    player: Int, x: Int, y: Int, trees: Int, state: inout GameState,
    onShouldBroadcastBuild: (Int, Int, UInt8) -> Void = { _, _, _ in },
    onShouldBroadcastBuilderAck: (Int, Int, Int, Int) -> Void = { _, _, _, _ in },
    onShouldBroadcastSmallBoom: (UInt8, Int, Int) -> Void = { _, _, _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard let terrain = state.terrain[x, y] else {
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
        return
    }
    switch terrain {
    case .river:
        state.terrain[x, y] = .boat
        onShouldBroadcastBuild(x, y, UInt8(Terrain.boat.rawValue))
        onShouldBroadcastBuilderAck(player, 0, trees - boatTrees, Int(noPill))
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        explosionAt(
            player: UInt8(player), x: x, y: y, state: &state,
            onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
        )
        onShouldBroadcastSmallBoom(playerNeutral, x, y)
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
    default:
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
    }
}

/// Ported from `recvclbuildpill()` (`server.c:2558-2632`). `pill` is the
/// client-specified slot index — the real C has no bounds check on it
/// before writing `server.pills[pill]`; guarded here (returning, doing
/// nothing) rather than trapping on an out-of-range Swift array access,
/// the same class of memory-safety deviation already established for
/// `applyDamage`'s `pills[-1]` case.
public func recvClBuildPill(
    player: Int, x: Int, y: Int, trees: Int, pill: Int, state: inout GameState,
    onShouldBroadcastBuildPill: (Int, Int, Int, UInt8) -> Void = { _, _, _, _ in },
    onShouldBroadcastBuilderAck: (Int, Int, Int, Int) -> Void = { _, _, _, _ in },
    onShouldBroadcastSmallBoom: (UInt8, Int, Int) -> Void = { _, _, _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard findPill(x: x, y: y, pills: state.pills) == nil, findBase(x: x, y: y, bases: state.bases) == nil else {
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
        return
    }
    guard let terrain = state.terrain[x, y] else {
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
        return
    }
    switch terrain {
    case .swamp0, .swamp1, .swamp2, .swamp3, .crater, .road,
        .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3,
        .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
        guard pill >= 0, pill < state.pills.count else { return }
        state.pills[pill].x = UInt8(x)
        state.pills[pill].y = UInt8(y)
        state.pills[pill].owner = UInt8(player)
        var armour = trees * pillTrees
        let leftoverTrees: Int
        if armour > maxPillArmour {
            leftoverTrees = (armour - maxPillArmour) / pillTrees
            armour = maxPillArmour
        } else {
            leftoverTrees = 0
        }
        state.pills[pill].armour = UInt8(armour)
        // `sendsrbuildpill()` reads `server.pills[pill].x/y/armour`
        // itself (server.c:3547-3549), same exclusivity-driven reason as
        // `onShouldBroadcastCapturePill` above -- `x`/`y` are passed from
        // this function's own already-known params rather than re-read
        // from `state.pills[pill]`, since they're the same values by
        // construction (`:373-374` set them from these exact params).
        onShouldBroadcastBuildPill(pill, x, y, state.pills[pill].armour)
        onShouldBroadcastBuilderAck(player, 0, leftoverTrees, Int(noPill))
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        explosionAt(
            player: UInt8(player), x: x, y: y, state: &state,
            onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
        )
        onShouldBroadcastSmallBoom(playerNeutral, x, y)
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
    default:
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
    }
}

/// Ported from `recvclrepairpill()` (`server.c:2633-2705`). `pill` here
/// always comes from `findPill`'s own return, so no separate bounds
/// guard is needed the way `recvClBuildPill` needs one.
public func recvClRepairPill(
    player: Int, x: Int, y: Int, trees: Int, state: inout GameState,
    onShouldBroadcastRepairPill: (Int, UInt8) -> Void = { _, _ in },
    onShouldBroadcastBuilderAck: (Int, Int, Int, Int) -> Void = { _, _, _, _ in },
    onShouldBroadcastSmallBoom: (UInt8, Int, Int) -> Void = { _, _, _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard let pill = findPill(x: x, y: y, pills: state.pills), findBase(x: x, y: y, bases: state.bases) == nil else {
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
        return
    }
    guard let terrain = state.terrain[x, y] else {
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
        return
    }
    switch terrain {
    case .swamp0, .swamp1, .swamp2, .swamp3, .crater, .road,
        .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3,
        .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
        var armour = Int(state.pills[pill].armour) + trees * pillTrees
        let leftoverTrees: Int
        if armour > maxPillArmour {
            leftoverTrees = (armour - maxPillArmour) / pillTrees
            armour = maxPillArmour
        } else {
            leftoverTrees = 0
        }
        state.pills[pill].armour = UInt8(armour)
        // `sendsrrepairpill()` reads `server.pills[pill].armour` itself
        // (server.c:3491), same exclusivity-driven reason as above.
        onShouldBroadcastRepairPill(pill, state.pills[pill].armour)
        onShouldBroadcastBuilderAck(player, 0, leftoverTrees, Int(noPill))
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        explosionAt(
            player: UInt8(player), x: x, y: y, state: &state,
            onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
        )
        onShouldBroadcastSmallBoom(playerNeutral, x, y)
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
    default:
        onShouldBroadcastBuilderAck(player, 0, trees, Int(noPill))
    }
}

/// Ported from `recvclplacemine()` (`server.c:2706-2803`) — the
/// builder-driven mine placement (`sendsrbuilderack`), distinct from the
/// direct tank-drop `recvClDropMine` above (`sendsrmineack`). Costs no
/// trees (always acks `0`), matching the C exactly.
public func recvClPlaceMine(
    player: Int, x: Int, y: Int, state: inout GameState,
    onShouldBroadcastPlaceMine: (Int, Int, Int) -> Void = { _, _, _ in },
    onShouldBroadcastBuilderAck: (Int, Int, Int, Int) -> Void = { _, _, _, _ in },
    onShouldBroadcastSmallBoom: (UInt8, Int, Int) -> Void = { _, _, _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard let terrain = state.terrain[x, y] else {
        onShouldBroadcastBuilderAck(player, 0, 0, Int(noPill))
        return
    }
    switch terrain {
    case .swamp0, .swamp1, .swamp2, .swamp3:
        state.terrain[x, y] = .minedSwamp
    case .crater:
        state.terrain[x, y] = .minedCrater
    case .road:
        state.terrain[x, y] = .minedRoad
    case .forest:
        state.terrain[x, y] = .minedForest
    case .rubble0, .rubble1, .rubble2, .rubble3:
        state.terrain[x, y] = .minedRubble
    case .grass0, .grass1, .grass2, .grass3:
        state.terrain[x, y] = .minedGrass
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        explosionAt(
            player: UInt8(player), x: x, y: y, state: &state,
            onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
        )
        onShouldBroadcastSmallBoom(playerNeutral, x, y)
        onShouldBroadcastBuilderAck(player, 0, 0, Int(noPill))
        return
    default:
        onShouldBroadcastBuilderAck(player, 0, 0, Int(noPill))
        return
    }
    onShouldBroadcastPlaceMine(player, x, y)
    onShouldBroadcastBuilderAck(player, 0, 0, Int(noPill))
}

// MARK: - Damage / combat

/// Ported from `recvcldamage()` (`server.c:2804-3035`) — the same
/// function `ShellTick.swift`'s `applyDamage` (Wave 5.3a) already ports
/// for its pill-heat and base-splash branches, including that function's
/// own documented `pills[-1]` UB deviation. The mined-terrain branch is
/// intercepted *before* calling `applyDamage` rather than routed through
/// its own `onMineExplosion` callback — capturing `&state` in a closure
/// passed to `applyDamage`, to call `explosionAt(..., state: &state, ...)`
/// from inside that closure, isn't expressible under Swift's exclusivity
/// rules (two simultaneous exclusive accesses to `state`). `applyDamage`
/// doesn't report which terrain-progression branch it took, so the
/// broadcast-firing predicate below re-derives the same boat/non-boat
/// case membership its own two switches use internally, rather than
/// modifying that already-shipped, audited function.
public func recvClDamage(
    player: Int, x: Int, y: Int, boat: Bool, state: inout GameState,
    onShouldBroadcastDamage: (Int, Int, Int, UInt8) -> Void = { _, _, _, _ in },
    onShouldBroadcastSmallBoom: (UInt8, Int, Int) -> Void = { _, _, _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    let point = Pointi(x: Int32(x), y: Int32(y))

    if findPill(x: x, y: y, pills: state.pills) != nil || findBase(x: x, y: y, bases: state.bases) != nil {
        applyDamage(at: point, boat: boat, state: &state, onMineExplosion: onMineExplosion)
        // `sendsrdamage()` reads `server.terrain[y][x]` itself
        // (server.c:3190), same exclusivity-driven reason as
        // `onShouldBroadcastBuild` -- the pill/base branch doesn't mutate
        // terrain, so this is just whatever it already was, matching the
        // C's own unconditional read.
        onShouldBroadcastDamage(player, x, y, UInt8((state.terrain[x, y] ?? .sea).rawValue))
        return
    }

    guard let terrain = state.terrain[x, y] else { return }

    switch terrain {
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        explosionAt(
            player: UInt8(player), x: x, y: y, state: &state,
            onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
        )
        onShouldBroadcastSmallBoom(playerNeutral, x, y)
        return
    default:
        break
    }

    let firesDamageBroadcast: Bool
    if boat {
        switch terrain {
        case .boat, .wall, .swamp0, .swamp1, .swamp2, .swamp3, .road, .forest,
            .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3,
            .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
            firesDamageBroadcast = true
        default:
            firesDamageBroadcast = false
        }
    } else {
        switch terrain {
        case .boat, .wall, .forest, .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
            firesDamageBroadcast = true
        default:
            firesDamageBroadcast = false
        }
    }

    applyDamage(at: point, boat: boat, state: &state, onMineExplosion: onMineExplosion)
    if firesDamageBroadcast {
        onShouldBroadcastDamage(player, x, y, UInt8((state.terrain[x, y] ?? .sea).rawValue))
    }
}

/// Ported from `recvclsmallboom()` (`server.c:3036-3055`) — a thin
/// wrapper around the already-shipped `explosionAt` (Wave 5.5a). See file
/// header for why the broadcast-firing predicate (`explosionAt`'s own
/// `detonated` case list, re-derived here rather than exposed via a new
/// parameter on that function) and the `playerNeutral` attribution are
/// both intentional, not simplifications.
public func recvClSmallBoom(
    player: Int, x: Int, y: Int, state: inout GameState,
    onShouldBroadcastSmallBoom: (UInt8, Int, Int) -> Void = { _, _, _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard let terrain = state.terrain[x, y] else { return }
    let detonated: Bool
    switch terrain {
    case .boat, .wall, .river, .swamp0, .swamp1, .swamp2, .swamp3, .crater, .road, .forest,
        .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3,
        .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3,
        .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass, .minedSea:
        detonated = true
    default:
        detonated = false
    }
    explosionAt(
        player: UInt8(player), x: x, y: y, state: &state,
        onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
    )
    if detonated {
        onShouldBroadcastSmallBoom(playerNeutral, x, y)
    }
}

/// Ported from `recvclsuperboom()` (`server.c:3056-3075`) — a thin
/// wrapper around the already-shipped `superboomAt` (Wave 5.5a). Unlike
/// `recvClSmallBoom`, `superboomat()`'s own broadcast has no
/// terrain-membership gate (fires unconditionally) and uses the real
/// causer `player`, not `playerNeutral` — confirmed by direct read
/// (server.c:4243), not assumed symmetric with `explosionat()`.
public func recvClSuperBoom(
    player: Int, x: Int, y: Int, state: inout GameState,
    onShouldBroadcastSuperBoom: (Int, Int, Int) -> Void = { _, _, _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    superboomAt(
        player: UInt8(player), x: x, y: y, state: &state,
        onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
    )
    onShouldBroadcastSuperBoom(player, x, y)
}

/// Ported from `recvclrefuel()` (`server.c:3076-3100`) — the
/// *authoritative* decision the already-shipped client mirror
/// `recvSrRefuel` (Wave 6.2) reflects, not another "apply-given-value"
/// function. Matches that mirror's unclamped-subtract arithmetic exactly
/// (no defensive clamp added here either — confirmed intentional
/// precedent, not an oversight, since `recvSrRefuel` already established
/// it). `base < server.nbases` is a real server-side bounds guard in the
/// C, replicated as a Swift array-bounds guard rather than an assertion.
public func recvClRefuel(
    player: Int, base: Int, armour: UInt8, shells: UInt8, mines: UInt8, state: inout GameState,
    onShouldBroadcastRefuel: (Int, Int, UInt8, UInt8, UInt8) -> Void = { _, _, _, _, _ in }
) {
    guard base >= 0, base < state.bases.count else { return }
    state.bases[base].armour -= armour
    state.bases[base].shells -= shells
    state.bases[base].mines -= mines
    onShouldBroadcastRefuel(player, base, armour, shells, mines)
}

/// Ported from `recvclhittank()` (`server.c:3101-3122`) — zero `GameState`
/// effect, a bounds-checked relay only. Kept as a minimal function for
/// parity with `recvSrHitTank`'s existing shape (unlike `recvclsendmesg`,
/// skipped entirely per Finding 4 of this wave's pre-brief).
public func recvClHitTank(player: Int, dir: Float, onShouldBroadcastHitTank: (Int, Float) -> Void = { _, _ in }) {
    guard player >= 0, player < maxPlayers else { return }
    onShouldBroadcastHitTank(player, dir)
}
