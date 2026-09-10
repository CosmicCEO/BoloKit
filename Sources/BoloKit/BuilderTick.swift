import Darwin

// MARK: - Wave 5.3b — builderlogic / buildercollision / server build handlers
//
// Ported from `builderlogic()` (client.c:4531), `buildercollision()`
// (client.c:6831), `circlesquare()` (client.c:6891), `builderspeed()`
// (client.c:3722), `buildertargetspeed()` (client.c:3792), `tanktest()`
// (client.c:4501), `tankonaboattest()` (client.c:4515), and the
// local-effect-free server handlers `recvclgrabtrees`, `recvclbuildroad`,
// `recvclbuildwall`, `recvclbuildboat`, `recvclbuildpill`,
// `recvclrepairpill`, `recvclplacemine` (server.c:2347-2802).
//
// **Collapsed network round trip:** C's `kBuilderGoto` arrival sends
// `sendcl<action>` and moves to `kBuilderWork` (a pure placeholder —
// `case kBuilderWork: break;`, client.c:4924); the SERVER's `recvcl<action>`
// does the actual terrain/resource mutation and replies with
// `sendsrbuilderack`, whose CLIENT-side handler (`recvsrbuilderack`,
// client.c:2570) is what actually advances `kBuilderWork` to `kBuilderWait`.
// BoloKit has no client/server split, so `arriveAtTarget` below performs
// the `recvcl<action>` mutation and the `recvsrbuilderack` consequence
// (updated trees/mines/pill) synchronously, going straight to `.wait`.
// `.work` is kept as a switch case for structural fidelity but is
// unreachable in this port.
//
// **`getbuildertaskforcommand()`/`client.nextbuildercommand`/
// `client.nextbuildertarget` are OUT OF SCOPE — a fog-of-war/UI input-layer
// concern, not core simulation.** That function resolves a raw UI command
// (BUILDERTREE/BUILDERROAD/…) plus `client.seentiles` (the fog-of-war tile
// cache) into a `BuilderTask`, exactly analogous to how some future input
// layer would resolve a click into `InputFlags` for `tankMoveTick` — it is
// not itself simulation state, and BoloKit's simulation core has no
// fog-of-war (same category of omission as Wave 5.2b's `testhiddenmine`/
// `increasevis`/`decreasevis`). `builderTick`'s `.ready` case instead reads
// `state.players[player].builderTask` + `state.players[player].builderTarget`
// directly as an already-resolved, one-shot order — exactly the same
// contract `InputFlags` already has with `tankMoveTick`. On failure (not
// enough resources, no free pill), C discards the *queued command*
// (`nextbuildercommand`/`nextbuildertarget`, reset to nil); since those
// don't exist here, this port discards the *resolved* one-shot order
// instead (`state.players[player].builderTask = .doNothing`), leaving
// `builderTarget` untouched — the closest faithful equivalent.
//
// **`repairPill`'s "trees needed" is derived from ground-truth
// `Pill.armour` instead of the fog-of-war tile cache.** C computes it from
// `client.seentiles[target]`, a `kFriendlyPillNN`/`kHostilePillNN` tile
// index that `bmap_client.c:169` keeps permanently in sync with
// `pills[i].armour` (`kFriendlyPill00Tile + armour`) whenever the pill is
// in view — i.e. the tile cache is just ground truth armour, indirected
// through a rendering enum. Reading `pill.armour` directly is strictly
// more accurate (no fog-of-war staleness) and needs no rendering-tile
// model at all.
//
// **D24 (ruled by PLANNER): `recvclbuildroad`'s `if (trees >= trees)` is a
// tautology (comparing a value to itself) — replicated verbatim, not
// corrected.** Same discipline as the dead-tank terrain-enum mismatch
// (Wave 5.2a) and `growtrees`' outer-guard bug (Wave 5.7 pre-brief): Phase
// 3 is behaviour-preserving; fidelity fixes belong to Phase 5. See
// `buildRoad(at:trees:state:onMineExplosion:)` below.

// MARK: - tankTest / tankOnABoatTest

/// True if any connected, alive tank occupies (x, y). Ported from
/// `tanktest()` (client.c:4501) — gates `buildWall`/`buildBoat`/
/// `buildPill`/`repairPill` from starting work under an occupied tile.
public func tankTest(x: Int, y: Int, state: GameState) -> Bool {
    state.players.contains {
        $0.connected && !$0.dead && Int($0.tank.x) == x && Int($0.tank.y) == y
    }
}

/// True if any connected, alive, *boated* tank occupies (x, y). Ported
/// from `tankonaboattest()` (client.c:4515) — the `buildRoad`-specific
/// variant of `tankTest` (a road can be built under a tank that isn't
/// currently boating; boating specifically blocks it).
public func tankOnABoatTest(x: Int, y: Int, state: GameState) -> Bool {
    state.players.contains {
        $0.connected && !$0.dead && $0.boat && Int($0.tank.x) == x && Int($0.tank.y) == y
    }
}

// MARK: - circleSquare

/// True if a circle of `radius` centered at `point` overlaps the unit
/// square at `square`. Ported from `circlesquare()` (client.c:6891); used
/// by `returnTick` to decide whether the builder has drifted off its
/// target square, which cancels the pending build task.
public func circleSquare(point: Vec2f, radius: Float, square: Pointi) -> Bool {
    let sx = Float(square.x)
    let sy = Float(square.y)

    if point.x < sx {
        if point.y < sy {
            return mag2f(Vec2f(x: sx, y: sy) - point) < radius
        } else if point.y > sy + 1 {
            return mag2f(Vec2f(x: sx, y: sy + 1) - point) < radius
        } else {
            return point.x + radius > sx
        }
    } else if point.x > sx + 1 {
        if point.y < sy {
            return mag2f(Vec2f(x: sx + 1, y: sy) - point) < radius
        } else if point.y > sy + 1 {
            return mag2f(Vec2f(x: sx + 1, y: sy + 1) - point) < radius
        } else {
            return point.x - radius < sx + 1
        }
    } else {
        if point.y < sy {
            return point.y + radius > sy
        } else if point.y > sy + 1 {
            return point.y - radius < sy + 1
        } else {
            return true
        }
    }
}

// MARK: - builderSpeed / builderTargetSpeed

/// LGM movement speed at (x, y), including pill/base overrides. Ported
/// from `builderspeed()` (client.c:3722): an armed pill blocks movement
/// (0.0); a dead pill allows full speed; a base allows full speed unless
/// hostile and resourced (mirrors `maxSpeed`'s override shape, Wave 5.0,
/// but the base branch also accepts a *dead* base, `armour == 0`, as
/// passable — tanks don't get that exception). Falls through to
/// `terrainBuilderSpeed` (shipped Wave 3.1) otherwise.
public func builderSpeed(
    x: Int, y: Int, player: Int, terrain: Terrain, pills: [Pill], bases: [Base], players: [PlayerState]
) -> Float {
    if let i = findPill(x: x, y: y, pills: pills) {
        return pills[i].armour > 0 ? 0.0 : builderMaxSpeed
    }
    if let i = findBase(x: x, y: y, bases: bases) {
        let base = bases[i]
        return (base.owner == playerNeutral || base.armour == 0 || testAlliance(Int(base.owner), player, players: players))
            ? builderMaxSpeed : 0.0
    }
    return terrainBuilderSpeed(terrain)
}

/// LGM movement speed while standing exactly on its own target square.
/// Ported from `buildertargetspeed()` (client.c:3792): pill/base always
/// full speed regardless of ownership/armament (you've arrived, that's the
/// point); river/wall/damagedWall also full speed here (unlike
/// `terrainBuilderSpeed`, where they're impassable/half-speed) since
/// standing on the exact target square being built/repaired is itself
/// solid ground for the builder. Only sea/mined-sea stay impassable.
public func builderTargetSpeed(x: Int, y: Int, terrain: Terrain, pills: [Pill], bases: [Base]) -> Float {
    if findPill(x: x, y: y, pills: pills) != nil { return builderMaxSpeed }
    if findBase(x: x, y: y, bases: bases) != nil { return builderMaxSpeed }
    switch terrain {
    case .swamp0, .swamp1, .swamp2, .swamp3, .crater,
        .rubble0, .rubble1, .rubble2, .rubble3,
        .minedSwamp, .minedCrater, .minedRubble:
        return builderMaxSpeed * 0.25
    case .forest, .minedForest:
        return builderMaxSpeed * 0.5
    case .sea, .minedSea:
        return 0.0
    default:
        // grass0-3/minedGrass/road/boat/minedRoad/wall/damagedWall0-3/river.
        return builderMaxSpeed
    }
}

// MARK: - builderLaunchPosition

/// The builder's initial position when starting a new goto — the repeated
/// formula from every `kBuilderReady` task branch (client.c, e.g.
/// 4550-4553): snap to the target's center if already within
/// `tankRadius - builderRadius`, otherwise step out from the tank toward
/// the target by exactly that distance.
private func builderLaunchPosition(target: Pointi, tank: Vec2f) -> Vec2f {
    let center = Vec2f(x: Float(target.x) + 0.5, y: Float(target.y) + 0.5)
    let diff = center - tank
    let mag = mag2f(diff)
    return mag <= (tankRadius - builderRadius) ? center : tank + diff * ((tankRadius - builderRadius) / mag)
}

// MARK: - buildercollision

/// Builds a `collisionDetect` callback for a builder pursuing `task`
/// toward `target`, owned by `owner`. An armed pill blocks unless it's the
/// exact repair target; a hostile, over-`minBaseArmour` base blocks
/// (`>`, exclusive — distinct from `tankCollision`'s inclusive `>=`); a
/// wall/damaged-wall blocks unless it's the exact build-wall target; river
/// blocks unless it's the exact build-boat/build-road target; sea/mined-sea
/// always blocks; everything else is passable.
///
/// Ported from `buildercollision()` (client.c:6831), which reads three C
/// globals (`target`, `buildertask`, `collisionowner`) set immediately
/// before each `collisiondetect` call — captured here as closure
/// parameters instead.
public func builderCollision(target: Pointi, task: BuilderTask, owner: Int, state: GameState) -> (Pointi) -> Bool {
    { square in
        guard square.x >= 0, square.x < 256, square.y >= 0, square.y < 256 else { return true }
        let x = Int(square.x)
        let y = Int(square.y)

        if let i = findPill(x: x, y: y, pills: state.pills) {
            let isRepairTarget = square == target && task == .repairPill
            return !(isRepairTarget || state.pills[i].armour == 0)
        }
        if let i = findBase(x: x, y: y, bases: state.bases) {
            let base = state.bases[i]
            return base.owner != playerNeutral
                && !testAlliance(Int(base.owner), owner, players: state.players)
                && Int(base.armour) > minBaseArmour
        }
        guard let terrain = state.terrain[x, y] else { return true }
        switch terrain {
        case .wall, .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
            return !(square == target && task == .buildWall)
        case .river:
            return !(square == target && (task == .buildBoat || task == .buildRoad))
        case .sea, .minedSea:
            return true
        default:
            return false
        }
    }
}

// MARK: - Work handlers
//
// Each collapses a `sendcl<action>()` → `recvcl<action>()` → `sendsrbuilderack()`
// round trip into one synchronous call, returning the updated `builderTrees`
// (or, for `placeMineWork`, mutating terrain only — the caller always
// resets `builderMines` to 0 afterward, matching C exactly: a placed mine
// is never refunded, success or not).

/// Ported from `recvclgrabtrees()` (server.c:2347).
private func grabTrees(
    at point: Pointi, state: inout GameState, onMineExplosion: (Pointi) -> Void,
    // D148(A): fires only on an actual completed harvest (the two success cases below), not on
    // the mine-explosion failure cases or the no-op default — mirrors how `onMineExplosion`
    // itself only fires in the mined-terrain branches of this same function.
    onTreeHarvest: (Pointi) -> Void = { _ in }
) -> Int {
    let x = Int(point.x)
    let y = Int(point.y)
    guard let terrain = state.terrain[x, y] else { return 0 }
    switch terrain {
    case .forest:
        state.terrain[x, y] = .grass3
        onTreeHarvest(point)
        return forestTreeYield
    case .minedForest:
        state.terrain[x, y] = .minedGrass
        onTreeHarvest(point)
        return forestTreeYield
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedRubble, .minedGrass:
        onMineExplosion(point)
        return 0
    default:
        return 0
    }
}

/// Ported from `recvclbuildroad()` (server.c:2390).
private func buildRoad(at point: Pointi, trees: Int, state: inout GameState, onMineExplosion: (Pointi) -> Void) -> Int {
    let x = Int(point.x)
    let y = Int(point.y)
    guard let terrain = state.terrain[x, y] else { return trees }
    switch terrain {
    case .river, .swamp0, .swamp1, .swamp2, .swamp3, .crater,
        .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3:
        // D24: `if (trees >= trees)` in the C source compares a value to
        // itself — always true. Not a real sufficiency check (the READY-
        // state check, `state.players[player].trees >= roadTrees`, is what actually
        // gates entry here); replicated verbatim per PLANNER's ruling.
        if trees >= trees {
            state.terrain[x, y] = .road
            return trees - roadTrees
        }
        return trees
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        onMineExplosion(point)
        return trees
    default:
        return trees
    }
}

/// Ported from `recvclbuildwall()` (server.c:2439). Unlike `buildRoad`,
/// this sufficiency check is real (`trees >= wallTrees`, not a tautology).
private func buildWall(at point: Pointi, trees: Int, state: inout GameState, onMineExplosion: (Pointi) -> Void) -> Int {
    let x = Int(point.x)
    let y = Int(point.y)
    guard let terrain = state.terrain[x, y] else { return trees }
    switch terrain {
    case .swamp0, .swamp1, .swamp2, .swamp3, .crater, .road,
        .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3,
        .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
        if trees >= wallTrees {
            state.terrain[x, y] = .wall
            return trees - wallTrees
        }
        return trees
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        onMineExplosion(point)
        return trees
    default:
        return trees
    }
}

/// Ported from `recvclbuildboat()` (server.c:2483). No sufficiency check
/// at all in C — the READY-state gate (`trees >= boatTrees`) already
/// guarantees enough trees by the time this runs, so `trees - boatTrees`
/// is always safe.
private func buildBoat(at point: Pointi, trees: Int, state: inout GameState, onMineExplosion: (Pointi) -> Void) -> Int {
    let x = Int(point.x)
    let y = Int(point.y)
    guard let terrain = state.terrain[x, y] else { return trees }
    switch terrain {
    case .river:
        state.terrain[x, y] = .boat
        return trees - boatTrees
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        onMineExplosion(point)
        return trees
    default:
        return trees
    }
}

/// Ported from `recvclbuildpill()` (server.c:2528). `pillIndex` is the pill
/// slot reserved at READY time (`state.players[player].builderPill`); on success this
/// places it at `point` for `owner`, with armour = `trees * 4` clamped to
/// `maxPillArmour` (excess trees refunded). `speed`/`counter` are
/// deliberately left untouched — C only ever sets `x`/`y`/`owner`/`armour`
/// here, leaving the pill's map-authored reload rate as-is.
private func buildPill(
    at point: Pointi, trees: Int, pillIndex: Int, owner: Int,
    state: inout GameState, onMineExplosion: (Pointi) -> Void
) -> Int {
    let x = Int(point.x)
    let y = Int(point.y)
    guard findPill(x: x, y: y, pills: state.pills) == nil, findBase(x: x, y: y, bases: state.bases) == nil else {
        return trees
    }
    guard let terrain = state.terrain[x, y] else { return trees }
    switch terrain {
    case .swamp0, .swamp1, .swamp2, .swamp3, .crater, .road,
        .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3,
        .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
        state.pills[pillIndex].x = UInt8(x)
        state.pills[pillIndex].y = UInt8(y)
        state.pills[pillIndex].owner = UInt8(owner)
        let armour = trees * 4
        if armour > maxPillArmour {
            state.pills[pillIndex].armour = UInt8(maxPillArmour)
            return (armour - maxPillArmour) / 4
        } else {
            state.pills[pillIndex].armour = UInt8(armour)
            return 0
        }
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        onMineExplosion(point)
        return trees
    default:
        return trees
    }
}

/// Ported from `recvclrepairpill()` (server.c:2620). Adds `trees * 4`
/// armour to the pill at `point`, clamped to `maxPillArmour` (excess trees
/// refunded).
private func repairPill(at point: Pointi, trees: Int, state: inout GameState, onMineExplosion: (Pointi) -> Void) -> Int {
    let x = Int(point.x)
    let y = Int(point.y)
    guard let pillIndex = findPill(x: x, y: y, pills: state.pills), findBase(x: x, y: y, bases: state.bases) == nil else {
        return trees
    }
    guard let terrain = state.terrain[x, y] else { return trees }
    switch terrain {
    case .swamp0, .swamp1, .swamp2, .swamp3, .crater, .road,
        .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3,
        .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
        let armour = Int(state.pills[pillIndex].armour) + trees * 4
        if armour > maxPillArmour {
            state.pills[pillIndex].armour = UInt8(maxPillArmour)
            return (armour - maxPillArmour) / 4
        } else {
            state.pills[pillIndex].armour = UInt8(armour)
            return 0
        }
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        onMineExplosion(point)
        return trees
    default:
        return trees
    }
}

/// Ported from `recvclplacemine()` (server.c:2705). Mines the target
/// terrain if it's a valid mineable variant; the caller (`arriveAtTarget`)
/// always zeroes `builderMines` afterward regardless of outcome — this
/// function only mutates terrain, matching the duplicated (not shared —
/// see file header) terrain-to-mined-variant mapping already ported for
/// the tank's own mine-plant path in `TankLocalTick.swift`'s `plantMine`.
private func placeMineWork(at point: Pointi, state: inout GameState, onMineExplosion: (Pointi) -> Void) {
    let x = Int(point.x)
    let y = Int(point.y)
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
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        onMineExplosion(point)
    default:
        break
    }
}

// MARK: - readyTick

/// `.ready` case: reads `state.players[player].builderTask` as an already-resolved,
/// one-shot order (see file header — `getbuildertaskforcommand` is out of
/// scope). On success: computes the launch position, transitions to
/// `.goto`, and deducts/reserves resources exactly as C's per-task branch
/// does. On failure (insufficient resources, no free pill): discards the
/// order (`builderTask = .doNothing`) and leaves everything else
/// untouched. Ported from the `kBuilderReady` case (client.c:4543-4787).
private func readyTick(player: Int, state: inout GameState) {
    // D137: resolve any pending mouse-issued builder command (C:
    // client.c:4544-4545 — `getbuildertaskforcommand` resolution, cleared
    // immediately regardless of outcome) before reading `builderTask`.
    if let command = state.players[player].pendingBuilderCommand {
        let target = state.players[player].pendingBuilderTarget
        state.players[player].builderTask = resolveBuilderTask(command: command, target: target, state: state)
        state.players[player].builderTarget = target
        state.players[player].pendingBuilderCommand = nil
    }

    let task = state.players[player].builderTask
    guard task != .doNothing else { return }

    let target = state.players[player].builderTarget
    let launch = builderLaunchPosition(target: target, tank: state.players[player].tank)

    switch task {
    case .doNothing:
        break

    case .getTree:
        state.players[player].builder = launch
        state.players[player].builderStatus = .goto
        state.players[player].builderMines = 0
        state.players[player].builderTrees = 0
        state.players[player].builderPill = noPill

    case .buildRoad:
        guard state.players[player].trees >= roadTrees else {
            state.players[player].builderTask = .doNothing
            return
        }
        state.players[player].builder = launch
        state.players[player].builderStatus = .goto
        state.players[player].builderMines = 0
        state.players[player].builderTrees = roadTrees
        state.players[player].trees -= roadTrees
        state.players[player].builderPill = noPill

    case .buildWall:
        guard state.players[player].trees >= wallTrees else {
            state.players[player].builderTask = .doNothing
            return
        }
        state.players[player].builder = launch
        state.players[player].builderStatus = .goto
        state.players[player].builderMines = 0
        state.players[player].builderTrees = wallTrees
        state.players[player].trees -= wallTrees
        state.players[player].builderPill = noPill

    case .buildBoat:
        guard state.players[player].trees >= boatTrees else {
            state.players[player].builderTask = .doNothing
            return
        }
        state.players[player].builder = launch
        state.players[player].builderStatus = .goto
        state.players[player].builderMines = 0
        state.players[player].builderTrees = boatTrees
        state.players[player].trees -= boatTrees
        state.players[player].builderPill = noPill

    case .buildPill:
        guard state.players[player].trees >= pillTrees else {
            state.players[player].builderTask = .doNothing
            return
        }
        guard let pillIndex = state.pills.indices.first(where: {
            state.pills[$0].owner == UInt8(player) && state.pills[$0].armour == pillOnboard
        }) else {
            state.players[player].builderTask = .doNothing
            return
        }
        state.players[player].builder = launch
        state.players[player].builderStatus = .goto
        state.players[player].builderMines = 0
        if state.players[player].trees >= pillTrees {
            state.players[player].builderTrees = pillTrees
            state.players[player].trees -= pillTrees
        } else {
            // Unreachable given the outer guard above already confirmed
            // `trees >= pillTrees` — kept for structural fidelity with
            // C's identically-shaped (and identically redundant) branch.
            state.players[player].builderTrees = state.players[player].trees
            state.players[player].trees = 0
        }
        state.players[player].builderPill = UInt8(pillIndex)

    case .repairPill:
        guard state.players[player].trees > 0 else {
            state.players[player].builderTask = .doNothing
            return
        }
        state.players[player].builder = launch
        state.players[player].builderStatus = .goto
        state.players[player].builderMines = 0

        let needed: Int
        if let pillIndex = findPill(x: Int(target.x), y: Int(target.y), pills: state.pills) {
            needed = max(0, (maxPillArmour - Int(state.pills[pillIndex].armour) + 3) / 4)
        } else {
            needed = 0
        }

        if state.players[player].trees > needed {
            state.players[player].builderTrees += needed
            state.players[player].trees -= needed
        } else {
            state.players[player].builderTrees += state.players[player].trees
            state.players[player].trees = 0
        }
        state.players[player].builderPill = noPill

    case .placeMine:
        guard state.players[player].mines > 0 else {
            state.players[player].builderTask = .doNothing
            return
        }
        state.players[player].builder = launch
        state.players[player].builderStatus = .goto
        state.players[player].builderMines = 1
        state.players[player].mines -= 1
        state.players[player].builderPill = noPill
    }
}

// MARK: - arriveAtTarget

/// Dispatches to the work handler for `state.players[player].builderTask` once the
/// builder has arrived at its target (`gotoTick`'s `mag2f(diff) < 0.00001`
/// branch), then transitions to `.wait` unconditionally — matching C
/// exactly: `kBuilderWork` always follows, whether the work succeeded, was
/// blocked by `tankTest`/`tankOnABoatTest`, or hit a mine.
///
/// **B.10 follow-on (D139):** `joinArrive`, when non-nil, replaces the mutation-applying
/// branches below with a read-only detect-and-send call (`detectJoinBuilderArrival`) — the join
/// path's own uncollapsed shape, matching C's real round trip (`kBuilderGoto` → sendcl* →
/// `kBuilderWork` → `recvsrbuilderack` → `kBuilderWait`), unlike host/single-process's collapsed
/// inline-mutation shortcut below. `nil` (every existing call site) preserves this function's
/// prior behavior exactly — zero change for host/single-process (D28).
private func arriveAtTarget(
    player: Int, state: inout GameState, onMineExplosion: (Pointi) -> Void,
    onTreeHarvest: (Pointi) -> Void = { _ in },
    joinArrive: ((Int, GameState) -> JoinOutboundBuilderCL?)? = nil
) -> JoinOutboundBuilderCL? {
    let target = state.players[player].builderTarget

    if let joinArrive {
        let outbound = joinArrive(player, state)
        if outbound != nil {
            state.players[player].builderStatus = .work
        } else {
            state.players[player].builderStatus = .wait
            state.players[player].builderWait = 0
        }
        return outbound
    }

    switch state.players[player].builderTask {
    case .getTree:
        state.players[player].builderTrees = grabTrees(
            at: target, state: &state, onMineExplosion: onMineExplosion, onTreeHarvest: onTreeHarvest
        )

    case .buildRoad:
        if !tankOnABoatTest(x: Int(target.x), y: Int(target.y), state: state) {
            state.players[player].builderTrees = buildRoad(
                at: target, trees: state.players[player].builderTrees, state: &state, onMineExplosion: onMineExplosion
            )
        }

    case .buildWall:
        if !tankTest(x: Int(target.x), y: Int(target.y), state: state) {
            state.players[player].builderTrees = buildWall(
                at: target, trees: state.players[player].builderTrees, state: &state, onMineExplosion: onMineExplosion
            )
        }

    case .buildBoat:
        if !tankTest(x: Int(target.x), y: Int(target.y), state: state) {
            state.players[player].builderTrees = buildBoat(
                at: target, trees: state.players[player].builderTrees, state: &state, onMineExplosion: onMineExplosion
            )
        }

    case .buildPill:
        if !tankTest(x: Int(target.x), y: Int(target.y), state: state) {
            state.players[player].builderTrees = buildPill(
                at: target, trees: state.players[player].builderTrees, pillIndex: Int(state.players[player].builderPill),
                owner: player, state: &state, onMineExplosion: onMineExplosion
            )
        }

    case .repairPill:
        if !tankTest(x: Int(target.x), y: Int(target.y), state: state) {
            state.players[player].builderTrees = repairPill(
                at: target, trees: state.players[player].builderTrees, state: &state, onMineExplosion: onMineExplosion
            )
        }

    case .placeMine:
        placeMineWork(at: target, state: &state, onMineExplosion: onMineExplosion)
        state.players[player].builderMines = 0

    case .doNothing:
        break
    }

    state.players[player].builderStatus = .wait
    state.players[player].builderWait = 0
    return nil
}

// MARK: - gotoTick

/// `.goto` case: on arrival, dispatches to `arriveAtTarget`; otherwise
/// picks a speed (target-square speed if already standing on the target
/// tile, boat-assist full speed near the tank, or plain `builderSpeed`
/// otherwise), advances one tick's distance through `builderCollision`,
/// and gives up to `.return` if collision reduced that to near-nothing.
/// Ported from the `kBuilderGoto` case (client.c:4880-4923).
///
/// `joinArrive` threads straight through to `arriveAtTarget` — see that function's own header
/// for the B.10 join-path split; `nil` (every existing call site) is unchanged.
@discardableResult
private func gotoTick(
    player: Int, state: inout GameState, onMineExplosion: (Pointi) -> Void,
    onTreeHarvest: (Pointi) -> Void = { _ in },
    joinArrive: ((Int, GameState) -> JoinOutboundBuilderCL?)? = nil
) -> JoinOutboundBuilderCL? {
    let target = state.players[player].builderTarget
    let center = Vec2f(x: Float(target.x) + 0.5, y: Float(target.y) + 0.5)
    var diff = center - state.players[player].builder

    if mag2f(diff) < 0.00001 {
        return arriveAtTarget(
            player: player, state: &state, onMineExplosion: onMineExplosion, onTreeHarvest: onTreeHarvest,
            joinArrive: joinArrive
        )
    }

    let builder = state.players[player].builder
    let bx = Int(builder.x)
    let by = Int(builder.y)
    let builderPoint = Pointi(x: Int32(bx), y: Int32(by))
    let terrain = state.terrain[bx, by] ?? .sea

    let speed: Float
    if builderPoint == target {
        speed = builderTargetSpeed(x: bx, y: by, terrain: terrain, pills: state.pills, bases: state.bases)
    } else if state.players[player].boat && mag2f(builder - state.players[player].tank) < tankRadius + builderRadius {
        speed = builderMaxSpeed
    } else {
        speed = builderSpeed(
            x: bx, y: by, player: player, terrain: terrain, pills: state.pills, bases: state.bases, players: state.players
        )
    }

    guard mag2f(diff) > speed / ticksPerSec else {
        state.players[player].builder = center
        return nil
    }

    diff = diff * (speed / (ticksPerSec * mag2f(diff)))

    let collision = builderCollision(target: target, task: state.players[player].builderTask, owner: player, state: state)
    let moved = collisionDetect(builder + diff, radius: builderRadius, isSolid: collision) - builder

    if mag2f(moved) <= 0.00128 * speed {
        state.players[player].builderStatus = .return
    } else {
        state.players[player].builder = collisionDetect(
            builder + moved * (speed / (ticksPerSec * mag2f(moved))), radius: builderRadius, isSolid: collision
        )
    }
    return nil
}

// MARK: - returnTick

/// `.return` case: fast, collision-free approach once within
/// `1.5 * (tankRadius + builderRadius)` of the tank; otherwise the same
/// speed selection and collision handling as `gotoTick`. Re-entering the
/// tank (`mag2f(tank - builder) <= tankRadius - builderRadius`) resets to
/// `.ready` and refunds `builderMines`/`builderTrees` into the main pools,
/// capped at `maxMines`/`maxTrees`. Drifting off the target square while
/// still returning cancels the task. Ported from the `kBuilderReturn` case
/// (client.c:4931-4998).
///
/// **B.5e (D105/D106):** both of these were previously gated to `player ==
/// state.localPlayer` -- `mines`/`trees`/`builderTask`/`builderMines`/
/// `builderTrees`/`builderPill` lived on singular `LocalPlayerState`, so
/// touching them for any other player would have clobbered the local
/// player's own in-progress state. Now that all 6 are `PlayerState` members
/// (migrated this sub-wave), the gate is gone -- it was never correct for
/// multiplayer in the first place: a non-local player's builder returning
/// to its tank never refunded resources or reset its task before this fix,
/// leaving it permanently stuck.
private func returnTick(player: Int, state: inout GameState) {
    guard !state.players[player].dead else { return }

    let builder = state.players[player].builder
    let tank = state.players[player].tank
    let target = state.players[player].builderTarget

    let nearTank = mag2f(builder - tank) <= 1.5 * (tankRadius + builderRadius)
    let speed: Float
    let collides: Bool
    if nearTank {
        speed = builderMaxSpeed
        collides = false
    } else {
        let bx = Int(builder.x)
        let by = Int(builder.y)
        let terrain = state.terrain[bx, by] ?? .sea
        if Pointi(x: Int32(bx), y: Int32(by)) == target {
            speed = builderTargetSpeed(x: bx, y: by, terrain: terrain, pills: state.pills, bases: state.bases)
        } else {
            speed = builderSpeed(
                x: bx, y: by, player: player, terrain: terrain, pills: state.pills, bases: state.bases, players: state.players
            )
        }
        collides = true
    }

    var diff = tank - builder

    if mag2f(diff) <= tankRadius - builderRadius {
        state.players[player].builderStatus = .ready
        state.players[player].builderTarget = Pointi(x: 0, y: 0)

        state.players[player].builderTask = .doNothing
        state.players[player].mines += state.players[player].builderMines
        state.players[player].trees += state.players[player].builderTrees
        state.players[player].builderMines = 0
        state.players[player].builderTrees = 0
        state.players[player].builderPill = noPill
        if state.players[player].mines > maxMines { state.players[player].mines = maxMines }
        if state.players[player].trees > maxTrees { state.players[player].trees = maxTrees }
        return
    }

    diff = diff * (speed / (ticksPerSec * mag2f(diff)))

    if collides {
        let collision = builderCollision(target: target, task: state.players[player].builderTask, owner: player, state: state)
        let moved = collisionDetect(builder + diff, radius: builderRadius, isSolid: collision) - builder
        if mag2f(moved) >= 0.00001 {
            state.players[player].builder = collisionDetect(
                builder + moved * (speed / (ticksPerSec * mag2f(moved))), radius: builderRadius, isSolid: collision
            )
        }
    } else {
        state.players[player].builder = builder + diff
    }

    if !circleSquare(point: state.players[player].builder, radius: builderRadius, square: target) {
        state.players[player].builderTask = .doNothing
    }
}

// MARK: - parachuteTick

/// `.parachute` case: straight-line descent toward the target at
/// `parachuteSpeed`, transitioning to `.return` on arrival. Ported from
/// the `kBuilderParachute` case (client.c:5010-5024).
private func parachuteTick(player: Int, state: inout GameState) {
    let target = state.players[player].builderTarget
    let center = Vec2f(x: Float(target.x) + 0.5, y: Float(target.y) + 0.5)
    var diff = center - state.players[player].builder

    if mag2f(diff) < 0.001 {
        state.players[player].builderTarget = Pointi(x: 0, y: 0)
        state.players[player].builderStatus = .return
        return
    }

    if mag2f(diff) > parachuteSpeed / ticksPerSec {
        diff = diff * (parachuteSpeed / (ticksPerSec * mag2f(diff)))
    }
    state.players[player].builder = state.players[player].builder + diff
}

// MARK: - builderTick

/// Per-tick builder (LGM) state machine, called once per connected player
/// per tick — matching `builderlogic(player)`'s call convention in
/// `runclient` (client.c:470). See the file header for the collapsed
/// network round trip and the `getbuildertaskforcommand` scope cut.
///
/// **B.10 follow-on (D139):** `joinArrive`, when non-nil, gives the join path the *uncollapsed*
/// round trip — see `arriveAtTarget`'s own header. `nil` (every pre-existing call site: `RunTick.
/// swift`'s host/single-process path) is unchanged, including the `.work` case staying genuinely
/// unreachable there. On the join path, `.work` becomes real: `recvSrBuilderAck` (already wired
/// into the join client's TCP receive loop) drives `.work` → `.wait`, matching `recvsrbuilderack`
/// (client.c:2572-2629)'s own outer `switch (builderstatus) { case kBuilderWork: ... }` gate —
/// this function's own `.work` case intentionally stays a no-op `break` either way, since the
/// transition happens over in `RecvSR.swift`, not here.
@discardableResult
public func builderTick(
    player: Int,
    state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in },
    onTreeHarvest: (Pointi) -> Void = { _ in },
    joinArrive: ((Int, GameState) -> JoinOutboundBuilderCL?)? = nil
) -> JoinOutboundBuilderCL? {
    guard state.players[player].connected else { return nil }

    switch state.players[player].builderStatus {
    case .ready:
        readyTick(player: player, state: &state)

    case .goto:
        return gotoTick(
            player: player, state: &state, onMineExplosion: onMineExplosion, onTreeHarvest: onTreeHarvest,
            joinArrive: joinArrive
        )

    case .work:
        // Unreachable in the host/single-process path (`joinArrive == nil`): gotoTick's arrival
        // branch collapses straight through to .wait via arriveAtTarget (see file header). Real,
        // but a no-op here, on the join path (`joinArrive != nil`): `recvSrBuilderAck` is what
        // drives `.work` → `.wait` there, not this function — see this function's own header.
        break

    case .wait:
        // C: `if (client.players[player].builderwait++ > BUILDERBUILDTIME)`
        // — post-increment: the OLD value is compared, then the field is
        // incremented. Comparing the already-incremented value here would
        // fire the transition one tick early.
        let old = state.players[player].builderWait
        state.players[player].builderWait = old + 1
        if old > builderBuildTime {
            state.players[player].builderStatus = .return
        }

    case .return:
        returnTick(player: player, state: &state)

    case .parachute:
        parachuteTick(player: player, state: &state)
    }
    return nil
}

// MARK: - Join client outbound CL* detection (B.10 follow-on, D139) — READ-ONLY SECTION
//
// Mirrors `TankLocalTick.swift`'s own "Join client outbound CL* detection" section (B.10, D127)
// exactly in spirit: a read-only analogue of C's real, uncollapsed builder round trip
// (`kBuilderGoto`'s arrival switch, client.c:4805-4877), for the join client's own local builder
// only. Never mutates `state` — `arriveAtTarget`'s `joinArrive` caller (above) is what applies the
// `.work`/`.wait` status transition based on this function's return value.

/// The small handful of outbound `CL*` message shapes reachable from the builder's arrival at its
/// target square, per `kBuilderGoto`'s arrival switch. Deliberately not the `CL*` wire structs
/// themselves (`BoloKit` doesn't depend on `BoloNet`) — the caller (`GameSession`, which imports
/// both) converts each case to its matching `CLGrabTrees`/`CLBuildRoad`/`CLBuildWall`/
/// `CLBuildBoat`/`CLBuildPill`/`CLRepairPill`/`CLPlaceMine` and sends it.
public enum JoinOutboundBuilderCL: Equatable, Sendable {
    case grabTrees(x: Int, y: Int)
    case buildRoad(x: Int, y: Int, trees: Int)
    case buildWall(x: Int, y: Int, trees: Int)
    case buildBoat(x: Int, y: Int, trees: Int)
    case buildPill(x: Int, y: Int, trees: Int, pill: Int)
    case repairPill(x: Int, y: Int, trees: Int)
    case placeMine(x: Int, y: Int)
}

/// Read-only analogue of `arriveAtTarget`'s mutation-applying switch, for the join client's own
/// builder arriving at `state.players[player].builderTarget`. Returns the message `kBuilderGoto`'s
/// arrival switch (client.c:4805-4877) would have sent for the player's current `builderTask`, or
/// `nil` if the reference's own guard (`tankonaboattest`/`tanktest`) would have blocked it (in
/// which case C skips straight to `kBuilderWait` with nothing sent — `arriveAtTarget`'s caller
/// reproduces that by transitioning to `.wait` whenever this returns `nil`).
///
/// `.getTree`/`.placeMine` have no such guard in C (`sendclgrabtrees`/`sendclplacemine` are
/// unconditional in the arrival switch) — matching `arriveAtTarget`'s own unconditional
/// `.getTree`/`.placeMine` branches, which never check `tankTest`/`tankOnABoatTest` either.
public func detectJoinBuilderArrival(player: Int, state: GameState) -> JoinOutboundBuilderCL? {
    let target = state.players[player].builderTarget
    let x = Int(target.x)
    let y = Int(target.y)
    let trees = state.players[player].builderTrees

    switch state.players[player].builderTask {
    case .getTree:
        return .grabTrees(x: x, y: y)

    case .buildRoad:
        guard !tankOnABoatTest(x: x, y: y, state: state) else { return nil }
        return .buildRoad(x: x, y: y, trees: trees)

    case .buildWall:
        guard !tankTest(x: x, y: y, state: state) else { return nil }
        return .buildWall(x: x, y: y, trees: trees)

    case .buildBoat:
        guard !tankTest(x: x, y: y, state: state) else { return nil }
        return .buildBoat(x: x, y: y, trees: trees)

    case .buildPill:
        guard !tankTest(x: x, y: y, state: state) else { return nil }
        return .buildPill(x: x, y: y, trees: trees, pill: Int(state.players[player].builderPill))

    case .repairPill:
        guard !tankTest(x: x, y: y, state: state) else { return nil }
        return .repairPill(x: x, y: y, trees: trees)

    case .placeMine:
        return .placeMine(x: x, y: y)

    case .doNothing:
        return nil
    }
}
