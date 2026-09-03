import Darwin

// MARK: - Wave 6.2 — recvsr* broadcast handlers
//
// Ported from the ~33 `recvsr*` functions in `Reference/c/client.c`
// (all 34 `SR*` opcodes except `SRHANGUP`, which has no handler — "not
// used" per `bolo.h:210`). See the Wave 6.2 pre-brief (`docs/AGENT_NOTES.md`)
// for the central finding this file is built on: in real distributed
// Bolo, `recvsr*` exists to let a remote client's own copy of state stay
// in sync with authoritative decisions it didn't compute itself. Wave 5's
// tick functions (`growTrees`, `explosionAt`/`superboomAt`, etc.) ARE that
// authoritative computation — they make the randomized decisions. These
// functions must never re-invoke them; they apply an already-decided
// value directly (e.g. `recvSrGrow` sets terrain straight from the given
// coordinates — re-running `growTrees` would pick a *different* random
// winner locally and desync from the server's actual choice).
//
// **Consistently out of scope, matching every prior wave's precedent:**
// `printmessage`/`playsound`/`refresh` (UI, never modeled in `BoloKit`)
// and `increasevis`/`decreasevis` (fog-of-war, likewise never modeled).
// Player `name`/`host` are never stored either — every use across all 33
// handlers is UI text generation, and `GameState.PlayerState` has never
// carried them. `seq`/`lastUpdate` are never touched — they live in a
// `BoloNet`-side table, not `BoloKit`, per Wave 6.0's design call.
//
// **Finding: `sendmesg`/`timelimit`/`basecontrol` have no `GameState`
// mutation at all, contrary to the pre-brief's assumption.** The
// pre-brief expected simple flag/counter updates for `timelimit`/
// `basecontrol`; reading the actual bodies (`client.c:3030-3086`,
// `3088-3135`) shows they are pure UI text formatting ("N Minutes and M
// Seconds Remaining!") with no state effect BoloKit could apply — the
// one exception, `client.timelimitreached`/`basecontrolreached`, has no
// analog by design (Wave 6.1's `runTick` already derives the equivalent
// condition from `ticks` vs. `timeLimit`/`baseControlThreshold` directly,
// every tick, with no separate flag to set from a broadcast). These two,
// plus `sendmesg` (already flagged in the pre-brief, confirmed the same
// way), are intentionally **not implemented** here — nothing to
// differentially test, nothing to port. 30 functions below, not 33.
//
// **Finding: `recvSrCapturePill`'s `sendclgrabtile()` calls are network
// sends in the real C, not direct state mutations.** Two of its terrain
// branches (`.boat`, and the mined-terrain cases) call `sendclgrabtile()`
// — the local client *asking the server* to process a grab, not a direct
// call to the already-ported `grabTile()`. Applying it directly here
// would re-trigger a state change the real client never makes on its
// own, the same class of mistake Wave 6.1/PLANNER explicitly ruled
// against for the mine-cascade case (Wave 5.9). Surfaced instead as
// `onRequestGrabTile`, a plain pass-through callback.
//
// **Finding, flagged for PLANNER, not fixed here (out of this wave's
// scope):** `recvSrDamage`'s pill/base heat logic (`client.c:1540-1577`)
// resets neither `Pill.counter` nor `Pill.coolCounter`. Its server-side
// sibling `recvcldamage()` (`server.c:2804-2846`, already ported as
// `applyDamage`/`heatPill` in `ShellTick.swift`, Wave 5.3a) resets
// `server.pills[pill].counter = 0` — and `Pill.coolCounter`'s own doc
// comment identifies `server.pills[i].counter` as *its* C analog, not
// `Pill.counter`'s. `heatPill` resets `Pill.counter` instead. If that
// doc-comment mapping is right, `heatPill` has been resetting the wrong
// field since Wave 5.3a — a pre-existing question, not introduced or
// fixed here; `recvSrDamage` below does not call `heatPill` and matches
// `client.c` exactly (no counter reset of either field), so this file is
// correct regardless of how that question resolves.

// MARK: - Player lifecycle (join / rejoin / exit / disc / kick / ban)
//
// **Finding: the pre-brief's flagged exit-vs-disc/kick/ban asymmetry
// (`recvsrplayerexit` omits the `player != client.player` self-check the
// other three have) turns out to affect only the fog-of-war `decreasevis`
// call — never modeled in `BoloKit`. There is no state-level difference
// between the four to preserve.** Kept as four separate functions anyway,
// one per wire opcode, for traceability back to `client.c`.

/// Ported from `recvsrplayerjoin()` (`client.c:1957-1994`). Sets the new
/// player's alliance to just their own bit, matching every other
/// initial-alliance call site in this port (`spawn()`, `requestalliance()`).
public func recvSrPlayerJoin(
    player: Int,
    state: inout GameState,
    onPlayerStatusChanged: (Int) -> Void = { _ in }
) {
    state.players[player].used = true
    state.players[player].connected = true
    state.players[player].alliance = UInt16(1 << player)
    onPlayerStatusChanged(player)
}

/// Ported from `recvsrplayerrejoin()` (`client.c:1996-2043`). The
/// pill-status refresh loop only fires when the rejoin is about the local
/// player itself (`client.player == srplayerrejoin->player`).
public func recvSrPlayerRejoin(
    player: Int,
    state: inout GameState,
    onPlayerStatusChanged: (Int) -> Void = { _ in },
    onPillStatusChanged: (Int) -> Void = { _ in }
) {
    state.players[player].connected = true

    if player == state.localPlayer {
        for i in state.pills.indices
            where testAlliance(state.localPlayer, Int(state.pills[i].owner), players: state.players) {
            onPillStatusChanged(i)
        }
    }

    onPlayerStatusChanged(player)
}

/// Ported from `recvsrplayerexit()` (`client.c:2045-2080`).
public func recvSrPlayerExit(player: Int, state: inout GameState, onPlayerStatusChanged: (Int) -> Void = { _ in }) {
    state.players[player].connected = false
    onPlayerStatusChanged(player)
}

/// Ported from `recvsrplayerdisc()` (`client.c:2082-2117`).
public func recvSrPlayerDisc(player: Int, state: inout GameState, onPlayerStatusChanged: (Int) -> Void = { _ in }) {
    state.players[player].connected = false
    onPlayerStatusChanged(player)
}

/// Ported from `recvsrplayerkick()` (`client.c:2119-2154`).
public func recvSrPlayerKick(player: Int, state: inout GameState, onPlayerStatusChanged: (Int) -> Void = { _ in }) {
    state.players[player].connected = false
    onPlayerStatusChanged(player)
}

/// Ported from `recvsrplayerban()` (`client.c:2156-2191`).
public func recvSrPlayerBan(player: Int, state: inout GameState, onPlayerStatusChanged: (Int) -> Void = { _ in }) {
    state.players[player].connected = false
    onPlayerStatusChanged(player)
}

// MARK: - Terrain broadcasts (damage / grabTrees / build / grow / flood / placeMine / dropMine / dropBoat)

/// Ported from `recvsrdamage()` (`client.c:1531-1626`). Pill/base heat
/// logic deliberately does **not** reset either `Pill.counter` or
/// `Pill.coolCounter` — matching `client.c` exactly. See the file header
/// finding re: this vs. `heatPill`'s server-side behavior.
public func recvSrDamage(
    player: UInt8,
    x: Int,
    y: Int,
    terrain: Terrain,
    state: inout GameState,
    onPillStatusChanged: (Int) -> Void = { _ in },
    onBaseStatusChanged: (Int) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    if let pill = findPill(x: x, y: y, pills: state.pills) {
        if state.pills[pill].armour > 0 {
            state.pills[pill].armour -= 1
            if state.pills[pill].armour == 0 {
                onPillStatusChanged(pill)
            }
            state.pills[pill].speed /= 2
            state.pills[pill].speed = max(state.pills[pill].speed, UInt8(minTicksPerShot))
        }
    } else if let base = findBase(x: x, y: y, bases: state.bases) {
        if state.bases[base].armour >= UInt8(minBaseArmour) {
            state.bases[base].armour -= UInt8(minBaseArmour)

            let baseCenter = Vec2f(x: Float(state.bases[base].x) + 0.5, y: Float(state.bases[base].y) + 0.5)
            for i in state.pills.indices {
                let pillCenter = Vec2f(x: Float(state.pills[i].x) + 0.5, y: Float(state.pills[i].y) + 0.5)
                if mag2f(pillCenter - baseCenter) <= 8.0,
                    state.pills[i].owner != playerNeutral, state.bases[base].owner != playerNeutral,
                    testAlliance(Int(state.pills[i].owner), Int(state.bases[base].owner), players: state.players) {
                    state.pills[i].speed /= 2
                    state.pills[i].speed = max(state.pills[i].speed, UInt8(minTicksPerShot))
                }
            }

            onBaseStatusChanged(base)
        }
    }

    state.terrain[x, y] = terrain

    if player != UInt8(state.localPlayer) {
        state.explosions.append(Explosion(point: Vec2f(x: Float(x) + 0.5, y: Float(y) + 0.5)))
        killSquareBuilder(at: Pointi(x: Int32(x), y: Int32(y)), state: &state, onDropPills: onDropPills)
    }
}

/// Ported from `recvsrgrabtrees()` (`client.c:1628-1658`).
public func recvSrGrabTrees(x: Int, y: Int, state: inout GameState) {
    state.terrain[x, y] = (state.terrain[x, y] == .minedForest) ? .minedGrass : .grass0
}

/// Ported from `recvsrbuild()` (`client.c:1660-1684`) — the given terrain
/// value is applied directly, no recompute.
public func recvSrBuild(x: Int, y: Int, terrain: Terrain, state: inout GameState) {
    state.terrain[x, y] = terrain
}

/// Ported from `recvsrgrow()` (`client.c:1686-1730`).
public func recvSrGrow(x: Int, y: Int, state: inout GameState) {
    switch state.terrain[x, y] {
    case .grass0, .grass1, .grass2, .grass3, .rubble0, .rubble1, .rubble2, .rubble3,
        .crater, .swamp0, .swamp1, .swamp2, .swamp3, .road:
        state.terrain[x, y] = .forest
    case .minedGrass, .minedRubble, .minedCrater, .minedSwamp, .minedRoad:
        state.terrain[x, y] = .minedForest
    default:
        break
    }
}

/// Ported from `recvsrflood()` (`client.c:1732-1747`) — unconditional,
/// unlike `floodAt`'s fuller mined-tile-detonation switch: the server
/// already decided this was the plain crater-to-river case (a mine
/// detonation would have come as `SRSMALLBOOM`/`SRSUPERBOOM` instead).
public func recvSrFlood(x: Int, y: Int, state: inout GameState) {
    state.terrain[x, y] = .river
}

private func mineify(_ terrain: Terrain) -> Terrain {
    switch terrain {
    case .swamp0, .swamp1, .swamp2, .swamp3: return .minedSwamp
    case .crater: return .minedCrater
    case .road: return .minedRoad
    case .forest: return .minedForest
    case .rubble0, .rubble1, .rubble2, .rubble3: return .minedRubble
    case .grass0, .grass1, .grass2, .grass3: return .minedGrass
    default: return terrain
    }
}

/// Ported from `recvsrplacemine()` (`client.c:1749-1824`). The
/// `hiddenmines`/`testalliance` gate in C only affects `refresh()`
/// (fog-of-war), never modeled here — so `player` has no state effect
/// and isn't a parameter.
public func recvSrPlaceMine(x: Int, y: Int, state: inout GameState) {
    if let terrain = state.terrain[x, y] {
        state.terrain[x, y] = mineify(terrain)
    }
}

/// Ported from `recvsrdropmine()` (`client.c:1826-1899`) — identical
/// terrain transition to `recvSrPlaceMine`, no fog-of-war gate at all.
/// Kept separate: two distinct wire opcodes, even though the state effect
/// happens to be the same table.
public func recvSrDropMine(x: Int, y: Int, state: inout GameState) {
    if let terrain = state.terrain[x, y] {
        state.terrain[x, y] = mineify(terrain)
    }
}

/// Ported from `recvsrdropboat()` (`client.c:1901-1955`).
public func recvSrDropBoat(x: Int, y: Int, state: inout GameState) {
    if state.terrain[x, y] == .river {
        state.terrain[x, y] = .boat
    }
}

// MARK: - Pill broadcasts (repairPill / coolPill / capturePill / buildPill / dropPill)

/// Ported from `recvsrrepairpill()` (`client.c:2193-2232`).
public func recvSrRepairPill(pill: Int, armour: UInt8, state: inout GameState, onPillStatusChanged: (Int) -> Void = { _ in }) {
    state.pills[pill].armour = armour
    onPillStatusChanged(pill)
}

/// Ported from `recvsrcoolpill()` (`client.c:2234-2249`) — unclamped,
/// matching C exactly: the server already validated the value before
/// broadcasting it.
public func recvSrCoolPill(pill: Int, state: inout GameState) {
    state.pills[pill].speed += 1
}

/// Ported from `recvsrcapturepill()` (`client.c:2251-2354`). If the local
/// tank happens to be standing on the just-captured pill's square, the
/// real client reacts based on the terrain underneath: `drown()`/
/// `superboom()` are direct local calls, ported as such; the boat-grab
/// and mined-terrain cases call `sendclgrabtile()` — a network request
/// to the server, not a direct state mutation (see file header) —
/// surfaced as `onRequestGrabTile` instead of applied here.
public func recvSrCapturePill(
    pill: Int,
    owner: UInt8,
    state: inout GameState,
    onPillStatusChanged: (Int) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in },
    onRequestGrabTile: (Pointi) -> Void = { _ in }
) {
    state.pills[pill].owner = owner
    state.pills[pill].armour = pillOnboard
    state.pills[pill].speed = UInt8(maxTicksPerShot)

    let localPlayer = state.localPlayer
    let tank = state.players[localPlayer].tank
    let pillPoint = Pointi(x: Int32(state.pills[pill].x), y: Int32(state.pills[pill].y))

    if Int(state.pills[pill].x) == Int(tank.x) && Int(state.pills[pill].y) == Int(tank.y) {
        switch state.terrain[Int(tank.x), Int(tank.y)] {
        case .sea:
            if !state.players[localPlayer].boat {
                drown(state: &state, onDropPills: onDropPills)
            }
        case .boat:
            onRequestGrabTile(pillPoint)
        case .wall, .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
            superboom(state: &state, onDropPills: onDropPills)
        case .minedSea:
            drown(state: &state, onDropPills: onDropPills)
            onRequestGrabTile(pillPoint)
        case .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
            onRequestGrabTile(pillPoint)
        default:
            break
        }
    }

    onPillStatusChanged(pill)
}

/// Ported from `recvsrbuildpill()` (`client.c:2356-2396`).
public func recvSrBuildPill(
    pill: Int, x: UInt8, y: UInt8, armour: UInt8, state: inout GameState,
    onPillStatusChanged: (Int) -> Void = { _ in }
) {
    state.pills[pill].x = x
    state.pills[pill].y = y
    state.pills[pill].armour = armour
    state.pills[pill].speed = UInt8(maxTicksPerShot)
    onPillStatusChanged(pill)
}

/// Ported from `recvsrdroppill()` (`client.c:2398-2423`).
public func recvSrDropPill(pill: Int, x: UInt8, y: UInt8, state: inout GameState, onPillStatusChanged: (Int) -> Void = { _ in }) {
    state.pills[pill].x = x
    state.pills[pill].y = y
    state.pills[pill].armour = 0
    state.pills[pill].speed = UInt8(maxTicksPerShot)
    onPillStatusChanged(pill)
}

// MARK: - Base broadcasts (replenishBase / captureBase / refuel / grabBoat)

/// Ported from `recvsrreplenishbase()` (`client.c:2425-2453`).
public func recvSrReplenishBase(base: Int, state: inout GameState, onBaseStatusChanged: (Int) -> Void = { _ in }) {
    state.bases[base].armour = min(state.bases[base].armour + 1, UInt8(maxBaseArmour))
    state.bases[base].shells = min(state.bases[base].shells + 1, UInt8(maxBaseShells))
    state.bases[base].mines = min(state.bases[base].mines + 1, UInt8(maxBaseMines))
    onBaseStatusChanged(base)
}

/// Ported from `recvsrcapturebase()` (`client.c:2455-2505`).
public func recvSrCaptureBase(base: Int, owner: UInt8, state: inout GameState, onBaseStatusChanged: (Int) -> Void = { _ in }) {
    if state.bases[base].owner == playerNeutral {
        state.bases[base].shells = UInt8(maxBaseShells)
        state.bases[base].armour = UInt8(maxBaseArmour)
        state.bases[base].mines = UInt8(maxBaseMines)
    } else {
        state.bases[base].shells = 0
        state.bases[base].armour = 0
        state.bases[base].mines = 0
    }
    state.bases[base].owner = owner
    onBaseStatusChanged(base)
}

/// Ported from `recvsrrefuel()` (`client.c:2507-2525`) — unclamped,
/// matching C exactly (the server already validated the amounts).
public func recvSrRefuel(base: Int, armour: UInt8, shells: UInt8, mines: UInt8, state: inout GameState) {
    state.bases[base].armour -= armour
    state.bases[base].shells -= shells
    state.bases[base].mines -= mines
}

/// Ported from `recvsrgrabboat()` (`client.c:2527-2547`).
public func recvSrGrabBoat(player: Int, x: Int, y: Int, state: inout GameState) {
    if player == state.localPlayer {
        state.players[state.localPlayer].boat = true
    }
    if state.terrain[x, y] == .boat {
        state.terrain[x, y] = .river
    }
}

// MARK: - Local builder/mine acknowledgements

/// Ported from `recvsrmineack()` (`client.c:2550-2569`) — an ack for the
/// *local* player's own outstanding mine-placement request, not a
/// broadcast about another player.
public func recvSrMineAck(success: Bool, state: inout GameState, onTankStatusChanged: () -> Void = {}) {
    if !success {
        state.local.mines += 1
    }
    onTankStatusChanged()
}

/// Ported from `recvsrbuilderack()` (`client.c:2572-2629`) — an ack for
/// the local player's own outstanding builder command. Only fires while
/// `.work` (matching C's outer `switch`); every task transitions to
/// `.wait` with `builderWait` reset, differing only in which resource
/// field the ack's value lands in.
public func recvSrBuilderAck(mines: UInt8, trees: UInt8, pill: UInt8, state: inout GameState) {
    let player = state.localPlayer
    guard state.players[player].builderStatus == .work else { return }

    switch state.local.builderTask {
    case .getTree, .buildRoad, .buildWall, .buildBoat, .repairPill:
        state.local.builderTrees = Int(trees)
        state.players[player].builderStatus = .wait
        state.players[player].builderWait = 0
    case .buildPill:
        state.local.builderTrees = Int(trees)
        state.local.builderPill = pill
        state.players[player].builderStatus = .wait
        state.players[player].builderWait = 0
    case .placeMine:
        state.local.builderMines = Int(mines)
        state.players[player].builderStatus = .wait
        state.players[player].builderWait = 0
    case .doNothing:
        break
    }
}

// MARK: - Explosions (smallBoom / superBoom / hitTank)
//
// The tank-damage-cascade logic below (armour decrement, boat-drop,
// escalation to `superboom()`/`smallboom()`/`killTank()`) is the same
// shape `MineChain.swift`'s `explosionAt`/`superboomAt` already implement
// for the *authoritative* role — but calling those directly here would
// also re-schedule chain/flood ring-buffer entries, which only the
// authoritative side (server role) does; a receiving client never
// schedules anything (`client.c`'s `recvsrsmallboom`/`recvsrsuperboom`
// have no chain/flood scheduling at all). So these are independent,
// terminal implementations, not calls into `explosionAt`/`superboomAt`.

/// Ported from `recvsrsmallboom()` (`client.c:2632-2707`).
public func recvSrSmallBoom(
    player: UInt8, x: Int, y: Int, state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in },
    onTankStatusChanged: () -> Void = {}
) {
    if state.terrain[x, y] != .sea && state.terrain[x, y] != .minedSea {
        state.terrain[x, y] = .crater
    }

    let point = Vec2f(x: Float(x) + 0.5, y: Float(y) + 0.5)

    if player != UInt8(state.localPlayer) {
        state.explosions.append(Explosion(point: point))
        killSquareBuilder(at: Pointi(x: Int32(x), y: Int32(y)), state: &state, onDropPills: onDropPills)
    }

    // Unconditional on `player` — deliberately NOT gated the way
    // `recvSrSuperBoom`'s equivalent block is. Brace-verified against
    // `client.c:2660-2686`: this `if` is a sibling of the explosion-
    // creation block above, not nested inside it (contrast
    // `recvsrsuperboom`, `client.c:2737-2851`, where it genuinely is
    // nested — see that function's doc comment). Do not add a gate here.
    let localPlayer = state.localPlayer
    if !state.players[localPlayer].dead, mag2f(state.players[localPlayer].tank - point) <= smallboomRadius {
        state.local.armour -= smallboomDamage
        state.players[localPlayer].boat = false

        if state.local.armour < 0 {
            state.local.armour = 0
            if state.local.mines > 32 {
                superboom(state: &state, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills)
            } else if state.local.mines > 0 || state.local.shells > 0 {
                smallboom(state: &state, onMineExplosion: onMineExplosion, onDropPills: onDropPills)
            } else {
                killTank(state: &state, onDropPills: onDropPills)
            }
        }

        onTankStatusChanged()
    }
}

/// Ported from `recvsrsuperboom()` (`client.c:2709-2868`) — a 2×2-tile
/// crater conversion, 9 explosion particles (4 corners + 4 edges +
/// center, the same layout `superboom()` already ships), and a
/// tank-damage cascade at `superboomRadius`/`superboomDamage`.
///
/// **Not the same shape as `recvSrSmallBoom` (Wave 6.2 PARITY audit,
/// Finding 1, D37):** brace-depth-verified against `client.c:2737-2851`
/// — the tank-damage check here is genuinely nested *inside*
/// `if (player != client.player)`, not a sibling `if` the way
/// `recvSrSmallBoom`'s equivalent check is. A broadcast superboom
/// attributed to the local player must skip local-tank damage entirely
/// (it was already applied optimistically when the local player
/// triggered it, Wave 5.2b's precedent) — matching the identical
/// nesting-differs-from-smallboom asymmetry `MineChain.swift`'s
/// `superboomAt` already documents for the authoritative-role twin of
/// this function.
public func recvSrSuperBoom(
    player: UInt8, x: Int, y: Int, state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in },
    onTankStatusChanged: () -> Void = {}
) {
    for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
        let tx = x + dx
        let ty = y + dy
        if state.terrain[tx, ty] != .sea && state.terrain[tx, ty] != .minedSea {
            state.terrain[tx, ty] = .crater
        }
    }

    if player != UInt8(state.localPlayer) {
        let fx = Float(x)
        let fy = Float(y)
        let corners: [(Vec2f, Pointi)] = [
            (Vec2f(x: fx + 0.5, y: fy + 0.5), Pointi(x: Int32(x), y: Int32(y))),
            (Vec2f(x: fx + 1.5, y: fy + 0.5), Pointi(x: Int32(x + 1), y: Int32(y))),
            (Vec2f(x: fx + 0.5, y: fy + 1.5), Pointi(x: Int32(x), y: Int32(y + 1))),
            (Vec2f(x: fx + 1.5, y: fy + 1.5), Pointi(x: Int32(x + 1), y: Int32(y + 1))),
        ]
        for (point, square) in corners {
            state.explosions.append(Explosion(point: point))
            killSquareBuilder(at: square, state: &state, onDropPills: onDropPills)
        }

        let edges: [Vec2f] = [
            Vec2f(x: fx + 0.25, y: fy + 1.0),
            Vec2f(x: fx + 1.0, y: fy + 0.25),
            Vec2f(x: fx + 1.75, y: fy + 1.0),
            Vec2f(x: fx + 1.0, y: fy + 1.75),
            Vec2f(x: fx + 1.0, y: fy + 1.0),
        ]
        for point in edges {
            state.explosions.append(Explosion(point: point))
            killPointBuilder(at: point, state: &state, onDropPills: onDropPills)
        }

        let localPlayer = state.localPlayer
        let center = Vec2f(x: Float(x) + 1.0, y: Float(y) + 1.0)
        if !state.players[localPlayer].dead, mag2f(state.players[localPlayer].tank - center) <= superboomRadius {
            state.local.armour -= superboomDamage
            state.players[localPlayer].boat = false

            if state.local.armour < 0 {
                state.local.armour = 0
                if state.local.mines > 32 {
                    superboom(state: &state, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills)
                } else if state.local.mines > 0 || state.local.shells > 0 {
                    smallboom(state: &state, onMineExplosion: onMineExplosion, onDropPills: onDropPills)
                } else {
                    killTank(state: &state, onDropPills: onDropPills)
                }
            }

            onTankStatusChanged()
        }
    }
}

/// Ported from `recvsrhittank()` (`client.c:2870-2903`).
public func recvSrHitTank(
    dir: Float, state: inout GameState,
    onTankStatusChanged: () -> Void = {},
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    let player = state.localPlayer
    state.players[player].boat = false
    state.players[player].kickDir = dir
    state.players[player].kickSpeed = kickForce

    state.local.armour -= 5
    if state.local.armour < 0 {
        state.local.armour = 0
        killTank(state: &state, onDropPills: onDropPills)
    }

    onTankStatusChanged()
}

// MARK: - Alliance / pause

/// Ported from `recvsrsetalliance()` (`client.c:2905-3028`) — real
/// mutual-consent business logic, not a bitmask copy. Fires the
/// accepted/requested/left branches based on the XOR of the local
/// player's own bit before vs. after the broadcast's new value.
///
/// **The "left" branch's `leavealliance(1 << player)` call is *not*
/// reimplemented here.** `leavealliance()` (`client.c:6389-6454`) is a
/// full client-initiated command in its own right: it takes an arbitrary
/// bitmask of players (not just this one), sends its own `CLSetAlliance`
/// packet, and cascades a further status-refresh loop over every
/// currently-connected player — squarely Wave 6.3's `requestalliance`/
/// `leavealliance` scope (already flagged there), not a small fragment
/// safe to duplicate inline. A miniature reimplementation here would
/// both drift from the real function and duplicate work 6.3 owns.
/// Surfaced as `onShouldLeaveAlliance`, matching the `onRequestGrabTile`
/// pattern used above for the same shape of problem.
public func recvSrSetAlliance(
    player: Int, alliance: UInt16, state: inout GameState,
    onPlayerStatusChanged: (Int) -> Void = { _ in },
    onBaseStatusChanged: (Int) -> Void = { _ in },
    onPillStatusChanged: (Int) -> Void = { _ in },
    onShouldLeaveAlliance: (UInt16) -> Void = { _ in }
) {
    let localPlayer = state.localPlayer
    let xor = state.players[player].alliance ^ alliance
    state.players[player].alliance = alliance

    guard xor & (1 << localPlayer) != 0 else { return }

    if state.players[localPlayer].alliance & (1 << player) != 0 {
        if alliance & (1 << localPlayer) != 0 {
            // Accepted: their bit for us is now set too, alliance is live.
            onPlayerStatusChanged(player)
            for i in state.bases.indices where Int(state.bases[i].owner) == player {
                onBaseStatusChanged(i)
            }
            for i in state.pills.indices where Int(state.pills[i].owner) == player {
                onPillStatusChanged(i)
            }
        } else {
            // They left: our bit for them was set, theirs for us just cleared.
            onPlayerStatusChanged(player)
            for i in state.bases.indices where Int(state.bases[i].owner) == player {
                onBaseStatusChanged(i)
            }
            for i in state.pills.indices where Int(state.pills[i].owner) == player {
                onPillStatusChanged(i)
            }
            onShouldLeaveAlliance(UInt16(1 << player))
        }
    }
    // else: our bit for them is unset — a bare request notification, no
    // state mutation (the C body only prints a message in this branch).
}

/// Ported from `recvsrpause()` (`client.c:1474-1493`). `255` is the
/// wire's established indefinite-pause sentinel (confirmed for `runTick`
/// in Wave 6.1's D35 fix, from three independent C call sites). Writes
/// `clientPauseDisplaySeconds`, not `serverPauseTicks` — this mirrors
/// `client.pause` (wire-domain seconds, never counted down), a distinct
/// C variable from `server.pause` (tick-domain) that this port used to
/// conflate into one field before D39 split them.
public func recvSrPause(pause: UInt8, state: inout GameState) {
    state.clientPauseDisplaySeconds = (pause == 255) ? -1 : Int(pause)
}
