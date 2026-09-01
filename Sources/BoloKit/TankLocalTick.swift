import Darwin

// MARK: - Wave 5.2b — tanklocallogic / enter()
//
// Ported from `tanklocallogic()` (client.c:4226) and `enter()` (client.c:5785),
// plus the local-effect halves of `drown()` (5574), `smallboom()` (5614),
// `superboom()` (5647), `killsquarebuilder()` (6999), `killpointbuilder()`
// (7023), and `killbuilder()` (7047) — all of which these two entry points
// reach directly.
//
// Everything here is scoped to the LOCAL player only, matching C exactly:
// `tanklocallogic`/`enter` read and write `client.player`'s own state
// throughout (`client.players[client.player]`, `client.armour`, etc.) — this
// is not a simplification, it is what the original code does.
//
// Three subsystems this wave deliberately does NOT implement, because each
// is a genuinely separate, not-yet-designed piece of the simulation (server.c
// mine-chain/flood propagation and the pill-scatter placement search) rather
// than something that shrinks the current wave:
//   - `explosionAt`/`superboomAt`/`chain`/`flood` (server.c) — turns a mined
//     tile into a crater, floods neighbouring sea cells, and registers a
//     chain-reaction list consumed by a per-tick `chain()`/`flood()` pass.
//     Surfaced here as `onMineExplosion` (single tile) and
//     `onSuperboomTerrain` (2×2 area, from ramming a wall).
//   - `droppills` (server.c:1984) — an outward-spiral search for free squares
//     to scatter a dead tank's/builder's onboard pills onto the map.
//     Surfaced here as `onDropPills`.
// All three default to no-ops so this wave is fully testable in isolation,
// exactly like `tankMoveTick`'s `onExplosion`/`onSuperboom`/`onSmallboom`/
// `onSpawn` (Wave 5.2a) — a future wave wires real implementations in.
//
// Also omitted, but for a different reason (no simulation state involved at
// all): C's `testhiddenmine` (only calls `refresh()`, a fog-of-war tile-cache
// invalidation) and the `increasevis`/`decreasevis` calls after a tank moves
// (visibility-radius bookkeeping for rendering). BoloKit's simulation core
// has no fog-of-war or rendering state, so there is nothing to port.

// MARK: - killPointBuilder / killSquareBuilder / killBuilder

/// Kills the local player's builder if it is within `explosionRadius` of
/// `point` and in an active state (goto/work/wait/return — not ready or
/// mid-parachute). Ported from `killpointbuilder()` (client.c:7023).
public func killPointBuilder(
    at point: Vec2f,
    state: inout GameState,
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    let player = state.localPlayer
    switch state.players[player].builderStatus {
    case .goto, .work, .wait, .return:
        if mag2f(state.players[player].builder - point) < explosionRadius {
            killBuilder(state: &state, onDropPills: onDropPills)
        }
    case .ready, .parachute:
        break
    }
}

/// Kills the local player's builder if its tile matches `point` and it is in
/// an active state. Ported from `killsquarebuilder()` (client.c:6999).
public func killSquareBuilder(
    at point: Pointi,
    state: inout GameState,
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    let player = state.localPlayer
    switch state.players[player].builderStatus {
    case .goto, .work, .wait, .return:
        let builderTile = Pointi(
            x: Int32(state.players[player].builder.x), y: Int32(state.players[player].builder.y)
        )
        if builderTile == point {
            killBuilder(state: &state, onDropPills: onDropPills)
        }
    case .ready, .parachute:
        break
    }
}

/// Kills the local player's builder outright: drops its reserved pill (if
/// any) and respawns it as a parachute at a uniformly random start.
///
/// Ported from `killbuilder()` (client.c:7047). C's `client.nextbuildercommand`/
/// `client.nextbuildertarget` are queued-UI-input fields with no simulation
/// state to port; `playsound`/`printmessage` are UI hooks. All omitted,
/// matching the treatment already given to `settankstatus` elsewhere.
public func killBuilder(
    state: inout GameState,
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    let player = state.localPlayer

    if state.local.builderPill != noPill {
        onDropPills(
            UInt16(truncatingIfNeeded: 1 << Int(state.local.builderPill)), state.players[player].builder
        )
        state.local.builderPill = noPill
    }

    // C: `start = random() % client.nstarts;` — no C oracle can be
    // differentially compared against an independent PRNG stream, so this
    // port uses `arc4random_uniform` uniformly for such choices (matches the
    // Wave 5.6 `spawn()` pre-brief's rationale).
    let start = Int(arc4random_uniform(UInt32(state.starts.count)))
    state.players[player].builderStatus = .parachute
    state.players[player].builder = Vec2f(
        x: Float(state.starts[start].x) + 0.5, y: Float(state.starts[start].y) + 0.5
    )
    state.local.builderTask = .doNothing
    state.local.builderMines = 0
    state.local.builderTrees = 0
    state.players[player].builderTarget = Pointi(
        x: Int32(state.players[player].tank.x), y: Int32(state.players[player].tank.y)
    )
}

// MARK: - drown / smallboom / superboom

/// Computes the local player's currently-onboard, non-builder-reserved pill
/// bitmask — the shared precondition for `drown`/`smallboom`/`superboom`'s
/// pill-scatter call. Ported from the identical loop duplicated at each of
/// their three call sites (client.c:5590, 5624, 5762).
private func onboardPillMask(state: GameState) -> UInt16 {
    let player = state.localPlayer
    var pills: UInt16 = 0
    for j in state.pills.indices where state.pills[j].owner == UInt8(player)
        && j != Int(state.local.builderPill) && state.pills[j].armour == pillOnboard {
        pills |= UInt16(truncatingIfNeeded: 1 << j)
    }
    return pills
}

/// Kills the local player by drowning: no explosion, no kick. Ported from
/// `drown()` (client.c:5574). `playsound(kSinkSound)` is a UI hook, omitted.
public func drown(
    state: inout GameState,
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    let player = state.localPlayer

    if !state.players[player].dead || state.local.respawnCounter <= explodeTicks {
        state.players[player].boat = false
        state.players[player].kickSpeed = 0.0
        state.local.respawnCounter = explodeTicks + 1
    }

    if !state.players[player].dead {
        onDropPills(onboardPillMask(state: state), state.players[player].tank)
        state.local.deaths += 1
        state.players[player].dead = true
    }
}

/// Kills the local player by single-tile mine detonation under its own tank.
/// Ported from `smallboom()` (client.c:5614). The terrain-mutation half of
/// the C function's `sendclsmallboom` → `recvclsmallboom` → `explosionat`
/// round trip is out of scope here (see file header); surfaced as
/// `onMineExplosion`.
public func smallboom(
    state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    let player = state.localPlayer

    if !state.players[player].dead || state.local.respawnCounter <= explodeTicks {
        state.players[player].boat = false
        state.players[player].kickSpeed = 0.0
        state.local.respawnCounter = explodeTicks + 1
        let tank = state.players[player].tank
        onMineExplosion(Pointi(x: Int32(tank.x), y: Int32(tank.y)))
    }

    if !state.players[player].dead {
        onDropPills(onboardPillMask(state: state), state.players[player].tank)
        state.local.deaths += 1
        state.players[player].dead = true
    }
}

/// Kills the local player with a 2×2-tile superboom centred on its tank,
/// spawning 9 explosion particles (4 corners + 4 edge midpoints + centre)
/// and testing each against the local builder. Ported from `superboom()`
/// (client.c:5647). The 2×2 crater/chain/flood terrain effect
/// (`sendclsuperboom` → `recvclsuperboom` → `superboomat`) is out of scope
/// here (see file header); surfaced as `onSuperboomTerrain`.
/// `playsound` (near/far superboom by fog visibility) is a UI hook, omitted.
public func superboom(
    state: inout GameState,
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    let player = state.localPlayer

    if !state.players[player].dead || state.local.respawnCounter <= explodeTicks {
        state.players[player].boat = false
        state.players[player].kickSpeed = 0.0
        state.local.respawnCounter = explodeTicks + 1

        let tank = state.players[player].tank
        var x = Int(tank.x)
        if tank.x - Float(Int(tank.x)) < 0.5 {
            x -= 1
        }
        var y = Int(tank.y)
        if tank.y - Float(Int(tank.y)) < 0.5 {
            y = Int(tank.y) - 1
        }

        onSuperboomTerrain(Pointi(x: Int32(x), y: Int32(y)))

        let fx = Float(x)
        let fy = Float(y)

        let corners: [(Vec2f, Pointi)] = [
            (Vec2f(x: fx + 0.5, y: fy + 0.5), Pointi(x: Int32(x), y: Int32(y))),
            (Vec2f(x: fx + 1.5, y: fy + 0.5), Pointi(x: Int32(x + 1), y: Int32(y))),
            (Vec2f(x: fx + 0.5, y: fy + 1.5), Pointi(x: Int32(x), y: Int32(y + 1))),
            (Vec2f(x: fx + 1.5, y: fy + 1.5), Pointi(x: Int32(x + 1), y: Int32(y + 1))),
        ]
        for (point, square) in corners {
            state.players[player].explosions.append(Explosion(point: point, counter: 0))
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
            state.players[player].explosions.append(Explosion(point: point, counter: 0))
            killPointBuilder(at: point, state: &state, onDropPills: onDropPills)
        }
    }

    if !state.players[player].dead {
        onDropPills(onboardPillMask(state: state), state.players[player].tank)
        state.local.deaths += 1
        state.players[player].dead = true
    }
}

// MARK: - grabTile / dropBoat / plantMine

/// Captures whatever is at `point` for the local player: an unowned or
/// hostile pill (armed pills are handled by the caller before this is
/// reached — see `enterTile`), a neutral/hostile/allied base, a boat left by
/// another tank, or (surfaced as `onMineExplosion`) a mined tile.
///
/// Ported from the local-effect-free `recvclgrabtile()` (server.c:2271) —
/// in the original this runs on the SERVER after the client's `sendclgrabtile`
/// network round trip; BoloKit has no client/server split, so this runs
/// directly and synchronously from `enterTile`.
public func grabTile(
    at point: Pointi,
    state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in }
) {
    let player = state.localPlayer
    let x = Int(point.x)
    let y = Int(point.y)

    if let pill = findPill(x: x, y: y, pills: state.pills) {
        state.pills[pill].owner = UInt8(player)
        state.pills[pill].armour = pillOnboard
        state.pills[pill].speed = UInt8(maxTicksPerShot)
    }

    if let base = findBase(x: x, y: y, bases: state.bases) {
        let owner = state.bases[base].owner
        if owner == playerNeutral {
            state.bases[base].owner = UInt8(player)
            state.bases[base].armour = UInt8(maxBaseArmour)
            state.bases[base].shells = UInt8(maxBaseShells)
            state.bases[base].mines = UInt8(maxBaseMines)
        } else if testAlliance(Int(owner), player, players: state.players) {
            // Ally handoff: ownership transfers, resources are untouched.
            state.bases[base].owner = UInt8(player)
        } else {
            // Hostile takeover: ownership transfers, resources are zeroed.
            state.bases[base].owner = UInt8(player)
            state.bases[base].armour = 0
            state.bases[base].shells = 0
            state.bases[base].mines = 0
        }
    }

    guard let terrain = state.terrain[x, y] else { return }
    switch terrain {
    case .boat:
        state.terrain[x, y] = .river

    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        onMineExplosion(point)

    default:
        break
    }
}

/// Drops a boat at `point` if it is (still) river terrain. Ported from the
/// local-effect-free `recvcldropboat()` (server.c:2100).
private func dropBoat(at point: Pointi, state: inout GameState) {
    let x = Int(point.x)
    let y = Int(point.y)
    if state.terrain[x, y] == Terrain.river {
        state.terrain[x, y] = .boat
    }
}

/// Plants a mine at `point`, turning its terrain into the mined variant of
/// whatever it currently is (a no-op on terrain that has none, matching C's
/// silent `sendsrmineack(player, 0)` failure ack). Ported from the
/// local-effect-free `recvcldropmine()` (server.c:2164).
private func plantMine(at point: Pointi, state: inout GameState) {
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
    default:
        break
    }
}

// MARK: - enterTile

/// Terrain-transition dispatch for the local player moving from `old` to
/// `new` (which may be equal — this runs every tick, not just on tile
/// change; individual branches guard on `new != old` exactly where C does).
///
/// Ported from `enter()` (client.c:5785).
public func enterTile(
    new: Pointi,
    old: Pointi,
    state: inout GameState,
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    let player = state.localPlayer
    let x = Int(new.x)
    let y = Int(new.y)

    if let pill = findPill(x: x, y: y, pills: state.pills) {
        if state.pills[pill].armour > 0 {
            superboom(state: &state, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills)
        } else if !state.players[player].dead {
            if new != old {
                grabTile(at: new, state: &state, onMineExplosion: onMineExplosion)
            }
            if let terrain = state.terrain[x, y], isWalkableNonWater(terrain) {
                if state.players[player].boat && new != old {
                    state.players[player].boat = false
                    dropBoat(at: old, state: &state)
                }
            }
        }
        return
    }

    if let base = findBase(x: x, y: y, bases: state.bases) {
        if !state.players[player].dead, new != old {
            let owner = state.bases[base].owner
            if owner == playerNeutral || !testAlliance(Int(owner), player, players: state.players) {
                grabTile(at: new, state: &state, onMineExplosion: onMineExplosion)
            }
            if state.players[player].boat {
                state.players[player].boat = false
                dropBoat(at: old, state: &state)
            }
        }
        return
    }

    guard let terrain = state.terrain[x, y] else { return }

    switch terrain {
    case .wall, .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
        superboom(state: &state, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills)

    case .sea:
        if !state.players[player].boat {
            drown(state: &state, onDropPills: onDropPills)
        }

    case .river:
        break

    case .forest:
        if state.players[player].dead, state.local.respawnCounter < explodeTicks, new != old {
            state.players[player].explosions.append(
                Explosion(point: Vec2f(x: Float(new.x) + 0.5, y: Float(new.y) + 0.5), counter: 0)
            )
            killSquareBuilder(at: new, state: &state, onDropPills: onDropPills)
        }
        fallthrough

    case .swamp0, .swamp1, .swamp2, .swamp3, .crater, .road,
        .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3:
        if !state.players[player].dead, state.players[player].boat, new != old {
            state.players[player].boat = false
            dropBoat(at: old, state: &state)
        }
        if !state.players[player].dead, state.players[player].inputFlags.contains(.lmine),
            state.local.mines > 0, new != old {
            state.local.mines -= 1
            plantMine(at: new, state: &state)
        }

    case .boat:
        if new != old {
            if state.players[player].boat {
                state.players[player].explosions.append(
                    Explosion(point: Vec2f(x: Float(new.x) + 0.5, y: Float(new.y) + 0.5), counter: 0)
                )
                killSquareBuilder(at: new, state: &state, onDropPills: onDropPills)
            } else {
                grabTile(at: new, state: &state, onMineExplosion: onMineExplosion)
            }
        }

    case .minedSea:
        if new != old {
            grabTile(at: new, state: &state, onMineExplosion: onMineExplosion)
        }
        // Unconditional, unlike plain `.sea` above: a mined-sea tile drowns
        // a boated tank too. C: both `sendclgrabtile` and `drown()` fire
        // regardless of `client.players[client.player].boat`.
        drown(state: &state, onDropPills: onDropPills)

    case .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        if new != old {
            grabTile(at: new, state: &state, onMineExplosion: onMineExplosion)
        }
    }
}

/// True for the terrain set that triggers a boat-drop-on-entry in both the
/// pill branch of `enter()` and the plain-terrain switch's shared block.
private func isWalkableNonWater(_ terrain: Terrain) -> Bool {
    switch terrain {
    case .swamp0, .swamp1, .swamp2, .swamp3, .crater, .road, .forest,
        .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3:
        return true
    default:
        return false
    }
}

// MARK: - tankLocalTick

/// Per-tick local-player-only logic: tank-vs-tank collision push, terrain
/// entry (`enterTile`), river resource drain, the refuel state machine,
/// shell-range adjustment, and shell firing.
///
/// Ported from `tanklocallogic()` (client.c:4226). `old` is the local
/// player's tank tile before this tick's physics update (`tankMoveTick`)
/// ran; `state.players[localPlayer].tank` already holds the post-physics
/// float position. C's `testhiddenmine` 3×3 loop and the
/// `increasevis`/`decreasevis` visibility bookkeeping are fog-of-war/
/// rendering concerns with no simulation state — omitted (see file header).
public func tankLocalTick(
    old: Pointi,
    state: inout GameState,
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard old.x >= 0, old.x < 256, old.y >= 0, old.y < 256 else { return }

    let player = state.localPlayer
    guard state.players[player].connected else { return }

    let new: Pointi

    if !state.players[player].dead {
        for i in state.players.indices
            where i != player && state.players[i].connected && !state.players[i].dead {
            let diff = state.players[player].tank - state.players[i].tank
            let mag = mag2f(diff)
            if mag < tankRadius * 2.0 {
                if mag < 0.00001 {
                    // C: `random()%16` — no oracle to compare an independent
                    // PRNG stream against; see killBuilder's identical note.
                    let dir = Float(arc4random_uniform(16)) * (kPif / 8.0)
                    state.players[player].tank = state.players[i].tank + tan2f(dir) * (tankRadius * 2.0)
                } else {
                    state.players[player].tank = state.players[i].tank + diff * ((tankRadius * 2.0) / mag)
                }
            }
        }
    }

    let tankNow = state.players[player].tank
    new = Pointi(x: Int32(tankNow.x), y: Int32(tankNow.y))

    enterTile(
        new: new, old: old, state: &state,
        onSuperboomTerrain: onSuperboomTerrain, onMineExplosion: onMineExplosion, onDropPills: onDropPills
    )

    let inBounds = new.x >= 0 && new.x < 256 && new.y >= 0 && new.y < 256
    let pill = inBounds ? findPill(x: Int(new.x), y: Int(new.y), pills: state.pills) : nil
    let base = inBounds ? findBase(x: Int(new.x), y: Int(new.y), bases: state.bases) : nil

    guard !state.players[player].dead else { return }

    // Drain resources on river terrain, off any pill/base, below boat speed.
    if !state.players[player].boat, pill == nil, base == nil, inBounds,
        state.terrain[Int(new.x), Int(new.y)] == Terrain.river,
        state.players[player].speed <= rubbleMaxSpeed {
        state.local.drainCounter += 1
        if state.local.drainCounter >= drainTicks {
            state.local.drainCounter = 0
            state.local.shells -= 1
            if state.local.shells < 0 { state.local.shells = 0 }
            state.local.mines -= 1
            if state.local.mines < 0 { state.local.mines = 0 }
        }
    } else {
        state.local.drainCounter = 0
    }

    // Refuel state machine.
    if !state.local.refueling {
        if let base {
            state.local.refueling = true
            state.local.refuelingBase = base
            state.local.refuelingCounter = 0
        }
    } else if new == old {
        state.local.refuelingCounter += 1
        let refuelingBase = state.local.refuelingBase

        let armourAmount = min(
            maxArmour - state.local.armour,
            min(Int(state.bases[refuelingBase].armour) - minBaseArmour, minBaseArmour)
        )

        if state.local.armour < maxArmour, Int(state.bases[refuelingBase].armour) > minBaseArmour,
            armourAmount > 0 {
            if state.local.refuelingCounter >= refuelArmourTicks {
                state.bases[refuelingBase].armour -= UInt8(armourAmount)
                state.local.armour += armourAmount
                state.local.refuelingCounter = 0
            }
        } else if state.local.shells < maxShells, Int(state.bases[refuelingBase].shells) >= minBaseShells {
            if state.local.refuelingCounter >= refuelShellsTicks {
                let transfer = state.local.shells > maxShells - minBaseShells
                    ? maxShells - state.local.shells : minBaseShells
                state.bases[refuelingBase].shells -= UInt8(transfer)
                state.local.shells += transfer
                state.local.refuelingCounter = 0
            }
        } else if state.local.mines < maxMines, Int(state.bases[refuelingBase].mines) >= minBaseMines {
            if state.local.refuelingCounter >= refuelMinesTicks {
                let transfer = state.local.mines > maxMines - minBaseMines
                    ? maxMines - state.local.mines : minBaseMines
                state.bases[refuelingBase].mines -= UInt8(transfer)
                state.local.mines += transfer
                state.local.refuelingCounter = 0
            }
        }
    } else {
        state.local.refueling = false
        state.local.refuelingBase = -1
        state.local.refuelingCounter = 0
    }

    // Shell-range adjustment. C: both `DRANGE` (=TICKSPERSEC/6.0) and the
    // increment `DRANGE/TICKSPERSEC` are double-precision (6.0 is a double
    // literal); narrowed to the float `range` field only once, at the final
    // assignment — same double-promotion treatment as `kickSpeed` decay.
    let flags = state.players[player].inputFlags
    if flags.contains(.incre), !flags.contains(.decre) {
        state.local.range = Float(Double(state.local.range) + Double(ticksPerSec) / 6.0 / Double(ticksPerSec))
        if state.local.range > maxShellRange { state.local.range = maxShellRange }
    } else if !flags.contains(.incre), flags.contains(.decre) {
        state.local.range = Float(Double(state.local.range) - Double(ticksPerSec) / 6.0 / Double(ticksPerSec))
        if state.local.range < minRange { state.local.range = minRange }
    }

    // Fire shell.
    if flags.contains(.shoot), state.local.shellCounter > shellFireThresholdTicks, state.local.shells > 0 {
        let shell = Shell(
            point: state.players[player].tank + dir2vec(state.players[player].dir) * 0.5,
            dir: state.players[player].dir,
            range: state.local.range - 0.5,
            owner: UInt8(player),
            boat: state.players[player].boat,
            pill: false
        )
        state.players[player].shells.append(shell)
        state.local.shells -= 1
        state.local.shellCounter = 0
    }

    state.local.shellCounter += 1
}
