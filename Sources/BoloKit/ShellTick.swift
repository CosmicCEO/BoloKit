import Darwin

// MARK: - Wave 5.3a — shelllogic / shellcollisiontest / recvcldamage / recvcltouch / killtank
//
// Ported from `shelllogic()` (client.c:5373), `shellcollisiontest()`
// (client.c:5126), the local-effect-free `recvcldamage()` (server.c:2804)
// and `recvcltouch()` (server.c:2236), and `killtank()` (client.c, ~2650).
//
// **Generalization from C's network-authority model:** every collision-
// resolution, damage-application, and builder-kill call in the C source is
// additionally gated on `player == client.player` — a network-authority
// artifact (only the client that owns a shell list submits its results to
// the server; every other connected client would independently compute the
// identical result and does not need to, since it trusts the server's
// broadcast instead). BoloKit has one authoritative simulation, not N
// independently-computing clients, so this port drops that specific gate
// everywhere it appears. Per-player explosion attribution
// (`client.players[client.player].explosions`) becomes
// `state.players[shell.owner].explosions` — the gate's `client.player`
// always equals the shell's owner at every call site that reaches it. This
// mirrors the precedent already established for `pillTick`'s "closest
// hostile" check and `tankLocalTick`'s tank-tank push (Wave 5.1/5.2 reports).
//
// The tank-hit loop's armour decrement and `killTank()` call stay gated to
// `player == state.localPlayer`, however: `LocalPlayerState.armour` only
// exists once, for the local player — exactly like `tankMoveTick`'s
// dead-tumble/respawn sequence (Wave 5.2a). A hit on a remote player's tank
// still applies the kick and spawns the explosion (both live in
// `PlayerState`, modeled per-player), but has no armour pool to decrement
// against in this port.
//
// `sendcldamage`/`sendsrdamage`/`sendcltouch`/`sendcldroppills` are network
// sends with no simulation state of their own — omitted, matching the
// treatment already given to `settankstatus`/`playsound` elsewhere.

// MARK: - shellAdvance

/// Per-tick shell position/range advance, with a final partial step when
/// the remaining range is less than one tick's travel. Ported from the move
/// loop in `shelllogic()` (client.c:5382-5392).
///
/// C: `SHELLVEL/TICKSPERSEC` — `SHELLVEL` is a double literal (`7.0`);
/// `TICKSPERSEC` is a bare int literal (`50`) that promotes to double in
/// this division. The comparison `shell->range < SHELLVEL/TICKSPERSEC`
/// therefore happens at double precision with `shell->range` promoted UP
/// (not the step narrowed down first) — the same double-promotion pattern
/// already established for `collisionDetect`/`kickSpeed` decay (Wave 5.0/
/// 5.2a), not the plain `Float / Float` this would otherwise read as.
public func shellAdvance(_ shell: inout Shell) {
    let step = Double(shellVelocity) / Double(ticksPerSec)
    if Double(shell.range) < step {
        shell.point = shell.point + dir2vec(shell.dir) * shell.range
        shell.range = 0.0
    } else {
        shell.point = shell.point + dir2vec(shell.dir) * Float(step)
        shell.range = Float(Double(shell.range) - step)
    }
}

// MARK: - heatPill

/// Halves a pill's reload interval (`speed` — lower is faster fire),
/// clamped to `minTicksPerShot`, and resets its cooldown-degradation
/// tally. A direct hit also decrements armour; the base-splash case
/// (`applyDamage`'s base branch) does not. Ported from the pill-heating
/// logic duplicated at `recvcldamage()`'s two call sites (server.c:2815,
/// 2833), a SERVER-side function — `server.pills[pill].counter` there is
/// the cooldown tally `coolPills` (Wave 5.7) owns, which this port calls
/// `Pill.coolCounter`, not `Pill.counter` (the CLIENT-side fire-cadence
/// tally, a different C variable — see `Pill.counter`'s own doc comment).
///
/// **Fix, Wave 6.2 PARITY audit / Q21 (D37):** this line reset
/// `Pill.counter` from Wave 5.3a until now. Real effect, not just a
/// mislabeled field: pill damage was spuriously resetting the
/// in-progress fire-cadence tally `PillTick.swift` owns (interrupting an
/// already-charging shot) while never resetting the cooldown-degradation
/// tally `coolPills` expects to own exclusively — letting an
/// already-halved `speed` degrade again sooner than the real game
/// allows. `recvSrDamage` (`RecvSR.swift`, Wave 6.2) never called this
/// function and was unaffected.
private func heatPill(_ index: Int, state: inout GameState, decrementArmour: Bool = true) {
    if decrementArmour {
        state.pills[index].armour -= 1
    }
    state.pills[index].speed /= 2
    state.pills[index].speed = max(state.pills[index].speed, UInt8(minTicksPerShot))
    state.pills[index].coolCounter = 0
}

// MARK: - applyDamage

/// Applies shell damage at `point`: heats an armed pill directly hit, damages
/// a resourced base and heats every allied pill within 8 squares of it, or
/// steps terrain through its damage-progression ladder — detonating it via
/// `onMineExplosion` if it's a mined variant. Ported from the local-effect-
/// free `recvcldamage()` (server.c:2804): in the original this runs on the
/// SERVER after `shellcollisiontest`'s `sendcldamage` network round trip;
/// BoloKit has no client/server split, so `shellCollisionTest` calls this
/// directly and synchronously.
///
/// **Deviation, memory-safety-driven, not a "fix":** C's base-hit pill-
/// heating loop clamps with `server.pills[pill].speed`, where `pill` is the
/// OUTER scope's pill-lookup result — which is always `-1` here, since this
/// branch only runs when the earlier `findpill` call failed. `pills[-1]` is
/// an out-of-bounds C array access (undefined behavior, not a deterministic,
/// well-defined bug — unlike `collisionDetect`'s p.x/p.y swap or growtrees'
/// `(x, y)` vs `(growx, growy)` guard, both of which are replicated exactly
/// because they're well-defined). Swift arrays trap on invalid indices, so
/// this cannot be ported literally; the evidently-intended `pills[i]` (the
/// SAME pill just halved, two lines up in the C source) is used instead —
/// the same class of deviation already established for `writeRun`'s x<256
/// guard.
///
/// **Deviation, memory-safety-driven, not a "fix":** the boat-shell road
/// branch's water-adjacency check reads `terrain[y][x±1]`/`terrain[y±1][x]`
/// with no bounds guard in C — reachable only at the map's absolute edge
/// (x/y = 0 or 255), which the mined-sea border ring makes unreachable in
/// practice for a real road tile. `TerrainGrid`'s subscript already returns
/// `nil` out of bounds; this port treats an out-of-bounds neighbor as
/// non-water (`isWaterLikeTerrain` already returns 0 for an invalid raw
/// value), avoiding a trap without changing any reachable behavior.
public func applyDamage(
    at point: Pointi,
    boat: Bool,
    state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in }
) {
    let x = Int(point.x)
    let y = Int(point.y)

    if let pillIndex = findPill(x: x, y: y, pills: state.pills) {
        if state.pills[pillIndex].armour > 0 {
            heatPill(pillIndex, state: &state)
        }
        return
    }

    if let baseIndex = findBase(x: x, y: y, bases: state.bases) {
        if Int(state.bases[baseIndex].armour) >= minBaseArmour {
            state.bases[baseIndex].armour -= UInt8(minBaseArmour)
            state.bases[baseIndex].counter = 0

            let baseCenter = Vec2f(
                x: Float(state.bases[baseIndex].x) + 0.5, y: Float(state.bases[baseIndex].y) + 0.5
            )
            for i in state.pills.indices {
                let pillCenter = Vec2f(x: Float(state.pills[i].x) + 0.5, y: Float(state.pills[i].y) + 0.5)
                if mag2f(pillCenter - baseCenter) <= 8.0,
                    state.pills[i].owner != playerNeutral, state.bases[baseIndex].owner != playerNeutral,
                    testAlliance(Int(state.pills[i].owner), Int(state.bases[baseIndex].owner), players: state.players) {
                    heatPill(i, state: &state, decrementArmour: false)
                }
            }
        }
        return
    }

    guard let terrain = state.terrain[x, y] else { return }

    if boat {
        switch terrain {
        case .boat: state.terrain[x, y] = .river
        case .wall: state.terrain[x, y] = .damagedWall3
        case .swamp0: state.terrain[x, y] = .river
        case .swamp1: state.terrain[x, y] = .swamp0
        case .swamp2: state.terrain[x, y] = .swamp1
        case .swamp3: state.terrain[x, y] = .swamp2
        case .road:
            let waterX = isWaterLikeTerrain(state.terrain[x - 1, y] ?? .wall) != 0
                && isWaterLikeTerrain(state.terrain[x + 1, y] ?? .wall) != 0
            let waterY = isWaterLikeTerrain(state.terrain[x, y - 1] ?? .wall) != 0
                && isWaterLikeTerrain(state.terrain[x, y + 1] ?? .wall) != 0
            if waterX || waterY {
                state.terrain[x, y] = .river
            }
        case .forest: state.terrain[x, y] = .grass3
        case .rubble0: state.terrain[x, y] = .river
        case .rubble1: state.terrain[x, y] = .rubble0
        case .rubble2: state.terrain[x, y] = .rubble1
        case .rubble3: state.terrain[x, y] = .rubble2
        case .grass0: state.terrain[x, y] = .swamp3
        case .grass1: state.terrain[x, y] = .grass0
        case .grass2: state.terrain[x, y] = .grass1
        case .grass3: state.terrain[x, y] = .grass2
        case .damagedWall0: state.terrain[x, y] = .rubble3
        case .damagedWall1: state.terrain[x, y] = .damagedWall0
        case .damagedWall2: state.terrain[x, y] = .damagedWall1
        case .damagedWall3: state.terrain[x, y] = .damagedWall2
        case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
            onMineExplosion(point)
        default:
            break
        }
    } else {
        switch terrain {
        case .boat: state.terrain[x, y] = .river
        case .wall: state.terrain[x, y] = .damagedWall3
        case .forest: state.terrain[x, y] = .grass3
        case .damagedWall0: state.terrain[x, y] = .rubble3
        case .damagedWall1: state.terrain[x, y] = .damagedWall0
        case .damagedWall2: state.terrain[x, y] = .damagedWall1
        case .damagedWall3: state.terrain[x, y] = .damagedWall2
        case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
            onMineExplosion(point)
        default:
            break
        }
    }
}

// MARK: - touchTile

/// Detonates a mined tile a shell expired over (range reached zero without
/// hitting anything solid first). Ported from the local-effect-free
/// `recvcltouch()` (server.c:2236).
public func touchTile(
    at point: Pointi,
    state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in }
) {
    let x = Int(point.x)
    let y = Int(point.y)
    guard let terrain = state.terrain[x, y] else { return }
    switch terrain {
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        onMineExplosion(point)
    default:
        break
    }
}

// MARK: - shellCollisionTest

/// Tests one shell against pills, bases, and terrain. Returns `true` if the
/// shell is consumed (collided or otherwise spent). Ported from
/// `shellcollisiontest()` (client.c:5126) — see the file header for the
/// network-authority-gate generalization applied throughout.
public func shellCollisionTest(
    shell: Shell,
    state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) -> Bool {
    let x = Int(shell.point.x)
    let y = Int(shell.point.y)
    let p = Pointi(x: Int32(x), y: Int32(y))

    if let pillIndex = findPill(x: x, y: y, pills: state.pills) {
        guard state.pills[pillIndex].armour > 0 else { return false }
        applyDamage(at: p, boat: shell.boat, state: &state, onMineExplosion: onMineExplosion)
        killSquareBuilder(at: p, state: &state, onDropPills: onDropPills)
        return true
    }

    if let baseIndex = findBase(x: x, y: y, bases: state.bases) {
        guard !shell.pill else { return false }

        let base = state.bases[baseIndex]
        let hostileAndResourced = base.owner != playerNeutral && shell.owner != playerNeutral
            && Int(base.armour) >= minBaseArmour
            && !testAlliance(Int(base.owner), Int(shell.owner), players: state.players)

        if shell.boat {
            if hostileAndResourced {
                applyDamage(at: p, boat: true, state: &state, onMineExplosion: onMineExplosion)
                killSquareBuilder(at: p, state: &state, onDropPills: onDropPills)
            } else {
                state.players[Int(shell.owner)].explosions.append(Explosion(point: shell.point))
                killPointBuilder(at: shell.point, state: &state, onDropPills: onDropPills)
            }
            return true
        } else if hostileAndResourced {
            applyDamage(at: p, boat: false, state: &state, onMineExplosion: onMineExplosion)
            killSquareBuilder(at: p, state: &state, onDropPills: onDropPills)
            return true
        } else {
            return false
        }
    }

    guard let terrain = state.terrain[x, y] else { return true }

    if shell.boat {
        switch terrain {
        case .sea, .river, .minedSea, .crater:
            return false
        case .road:
            let waterX = isWaterLikeTerrain(state.terrain[x - 1, y] ?? .wall) != 0
                && isWaterLikeTerrain(state.terrain[x + 1, y] ?? .wall) != 0
            let waterY = isWaterLikeTerrain(state.terrain[x, y - 1] ?? .wall) != 0
                && isWaterLikeTerrain(state.terrain[x, y + 1] ?? .wall) != 0
            if waterX || waterY {
                applyDamage(at: p, boat: true, state: &state, onMineExplosion: onMineExplosion)
                killSquareBuilder(at: p, state: &state, onDropPills: onDropPills)
            } else {
                state.players[Int(shell.owner)].explosions.append(Explosion(point: shell.point))
                killPointBuilder(at: shell.point, state: &state, onDropPills: onDropPills)
            }
            return true
        default:
            // Every remaining terrain case (wall/swamp/forest/rubble/grass/
            // damagedWall/boat/every mined variant except minedSea) damages
            // on a boat-shell hit. Verified exhaustive against the 30-case
            // Terrain enum: 4 handled above + this default's 26 = 30.
            applyDamage(at: p, boat: true, state: &state, onMineExplosion: onMineExplosion)
            killSquareBuilder(at: p, state: &state, onDropPills: onDropPills)
            return true
        }
    } else {
        switch terrain {
        case .wall, .forest, .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3, .boat, .minedForest:
            applyDamage(at: p, boat: false, state: &state, onMineExplosion: onMineExplosion)
            killSquareBuilder(at: p, state: &state, onDropPills: onDropPills)
            return true
        default:
            return false
        }
    }
}

// MARK: - killTank

/// Kills the local player outright (armour depleted by shell damage):
/// scatters onboard pills, marks dead, and resets the respawn counter to
/// `0` — an immediate tumble/kick-decay start, distinct from `drown`/
/// `smallboom`/`superboom` (Wave 5.2b), which jump straight to
/// `explodeTicks + 1`. Ported from `killtank()` (client.c, ~2650).
public func killTank(
    state: inout GameState,
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    let player = state.localPlayer
    guard !state.players[player].dead else { return }

    var pills: UInt16 = 0
    for j in state.pills.indices where state.pills[j].owner == UInt8(player)
        && j != Int(state.local.builderPill) && state.pills[j].armour == pillOnboard {
        pills |= UInt16(truncatingIfNeeded: 1 << j)
    }
    onDropPills(pills, state.players[player].tank)

    state.local.deaths += 1
    state.players[player].dead = true
    state.players[player].boat = false
    state.local.respawnCounter = 0
}

// MARK: - shellTick

/// Per-tick shell simulation, called once per connected player per tick
/// (matching `shelllogic(player)`'s call convention in `runclient`,
/// client.c:478): moves and resolves pill/base/terrain collisions for
/// `player`'s own shell list, tests every connected player's shells against
/// `player`'s tank (see below), and expires any of `player`'s shells whose
/// range has run out.
///
/// **`player` plays two different roles, exactly as in C:** for movement
/// and pill/base/terrain collision (steps 1, 2, 4) it is the shell-list
/// *owner*. For the tank-hit test (step 3) it is the *target* — C's
/// `shelllogic(player)` tests `client.players[client.player].shells`
/// (always the local list) against `client.players[player].tank`; the
/// generalization documented in this file's header widens "the local
/// list" to "every connected player's list," turning step 3 into a full
/// cross-product test run once per target.
///
/// **Processing order matters, exactly as in C:** the top-level driver must
/// call `shellTick(player:)` once per connected player in increasing index
/// order each tick (matching `runclient`'s `for (i = 0; i < MAXPLAYERS;
/// i++)`). A shell that hits a lower-indexed target this tick is removed
/// before a higher-indexed target's turn tests it — "first collision wins"
/// is order-dependent in the original and is not smoothed over here.
public func shellTick(
    player: Int,
    state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard state.players[player].connected else { return }

    // 1. Move this player's shells.
    for i in state.players[player].shells.indices {
        shellAdvance(&state.players[player].shells[i])
    }

    // 2. Pill/base/terrain collisions for this player's shells.
    var i = 0
    while i < state.players[player].shells.count {
        let shell = state.players[player].shells[i]
        if shellCollisionTest(
            shell: shell, state: &state, onMineExplosion: onMineExplosion, onDropPills: onDropPills
        ) {
            state.players[player].shells.remove(at: i)
        } else {
            i += 1
        }
    }

    // 3. Tank-hit test: every connected player's shells against THIS
    // player's tank (player is the TARGET here — see doc comment above).
    if !state.players[player].dead {
        for shooter in state.players.indices where state.players[shooter].connected {
            var j = 0
            while j < state.players[shooter].shells.count {
                let shell = state.players[shooter].shells[j]
                guard mag2f(shell.point - state.players[player].tank) <= tankRadius else {
                    j += 1
                    continue
                }

                state.players[Int(shell.owner)].explosions.append(Explosion(point: shell.point))
                killPointBuilder(at: shell.point, state: &state, onDropPills: onDropPills)
                state.players[player].kickDir = shell.dir
                state.players[player].kickSpeed = kickForce

                if player == state.localPlayer {
                    state.players[player].boat = false
                    state.local.armour -= shellDamage
                    if state.local.armour < 0 {
                        state.local.armour = 0
                        killTank(state: &state, onDropPills: onDropPills)
                    }
                }

                state.players[shooter].shells.remove(at: j)
            }
        }
    }

    // 4. Expire this player's remaining shells (range exhausted).
    var k = 0
    while k < state.players[player].shells.count {
        if state.players[player].shells[k].range <= 0.0 {
            let shell = state.players[player].shells[k]
            state.players[player].explosions.append(Explosion(point: shell.point))
            killPointBuilder(at: shell.point, state: &state, onDropPills: onDropPills)
            touchTile(
                at: Pointi(x: Int32(shell.point.x), y: Int32(shell.point.y)),
                state: &state, onMineExplosion: onMineExplosion
            )
            state.players[player].shells.remove(at: k)
        } else {
            k += 1
        }
    }
}
