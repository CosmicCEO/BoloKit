import Darwin

// MARK: - isShore

/// True if (x, y) counts as "shore" for boat shore-push purposes: any base
/// (regardless of terrain underneath), or any terrain other than sea/
/// river/mined-sea. Out-of-bounds is never shore.
///
/// Ported from `isshore()` in Reference/c/client.c:3923.
public func isShore(x: Int, y: Int, terrain: TerrainGrid, bases: [Base]) -> Bool {
    guard x >= 0, x < 256, y >= 0, y < 256 else { return false }
    if findBase(x: x, y: y, bases: bases) != nil { return true }
    guard let t = terrain[x, y] else { return false }
    switch t {
    case .sea, .river, .minedSea:
        return false
    default:
        return true
    }
}

// MARK: - tankCollision

/// Builds a `collisionDetect` callback for a tank owned by `owner`.
/// Out-of-bounds is always solid; an armed (non-onboard, armour>0) pill is
/// solid; a base is solid only if hostile (not neutral, not allied with
/// `owner`) AND `armour >= minBaseArmour` (inclusive — contrast
/// `buildercollision`'s exclusive `>`, ported in Wave 5.4); otherwise
/// wall/damagedWall is solid, everything else passable.
///
/// Ported from `tankcollision()` in Reference/c/client.c:6769.
public func tankCollision(owner: Int, state: GameState) -> (Pointi) -> Bool {
    { square in
        guard square.x >= 0, square.x < 256, square.y >= 0, square.y < 256 else { return true }
        let x = Int(square.x)
        let y = Int(square.y)

        if let i = findPill(x: x, y: y, pills: state.pills) {
            return state.pills[i].armour > 0
        }
        if let i = findBase(x: x, y: y, bases: state.bases) {
            let base = state.bases[i]
            return base.owner != playerNeutral
                && !testAlliance(Int(base.owner), owner, players: state.players)
                && Int(base.armour) >= minBaseArmour
        }
        guard let t = state.terrain[x, y] else { return true }
        switch t {
        case .wall, .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
            return true
        default:
            return false
        }
    }
}

// MARK: - tankMoveTick

/// Per-tick tank physics for one player: dead-tumble/death-event/respawn
/// sequencing, or (if alive) turning, direction wrap, acceleration,
/// position update, kickspeed decay, boat shore-push, and terrain
/// collision.
///
/// Ported from `tankmovelogic()` in Reference/c/client.c:3977. In C this
/// is called once per connected player per tick (`runclient`,
/// client.c:449); the alive-branch physics below runs for whichever
/// `player` is passed in, matching that loop exactly.
///
/// The dead-tumble/boom/respawn sequence, however, is gated in C to
/// `player == client.player` — it reads `client.respawncounter`/`mines`/
/// `shells`, fields that exist once per LOCAL client instance (see
/// `LocalPlayerState`), not once per player. This port keeps that same
/// gate (`player == state.localPlayer`) because `GameState.local` is
/// currently modeled once, not per player — extending death/respawn
/// tracking to every player simultaneously would require per-player
/// resource state that hasn't been designed yet. This is a deliberate
/// scope boundary, not an oversight; see the Wave 5.2a report in
/// AGENT_NOTES for the full rationale.
///
/// `onExplosion`/`onSuperboom`/`onSmallboom`/`onSpawn` remain pure notify
/// hooks, fired alongside the real effects below (Wave 5.9): the periodic
/// corpse explosion now also kills a builder in range
/// (`killpointbuilder(explosion->point)`, client.c:4002), and the
/// `explodeTicks` boundary now also calls the real `superboom()`/
/// `smallboom()` (client.c:4008-4013's direct calls, no callback
/// indirection in the oracle at all here). `onMineExplosion`/
/// `onSuperboomTerrain`/`onDropPills` thread through to those calls.
public func tankMoveTick(
    player: Int,
    state: inout GameState,
    onExplosion: (Vec2f) -> Void = { _ in },
    onSuperboom: () -> Void = {},
    onSmallboom: () -> Void = {},
    onSpawn: () -> Void = {},
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard state.players[player].connected else { return }

    if state.players[player].dead {
        guard player == state.localPlayer else { return }

        state.local.respawnCounter += 1

        if state.local.respawnCounter < explodeTicks {
            state.players[player].tank =
                state.players[player].tank
                + dir2vec(state.players[player].kickDir) * (state.players[player].kickSpeed / ticksPerSec)

            state.players[player].tank = collisionDetect(
                state.players[player].tank, radius: tankRadius, isSolid: tankCollision(owner: player, state: state)
            )

            if state.local.respawnCounter % 5 == 0 {
                let point = state.players[player].tank
                let tx = Int(point.x)
                let ty = Int(point.y)
                // BUG (replicated, not fixed): C compares this lookup
                // against kSeaTile/kMinedSeaTile (tile-enum raw values 16,
                // 17), not the terrain-enum's sea/minedSea. In this port's
                // Terrain raw-value ordering (matched to C's terrain.h),
                // 16/17 are grass1/grass2 — so the explosion is skipped
                // only over those two grass variants, and always spawns
                // over real sea/mined-sea.
                let terrainValue = state.terrain[tx, ty]?.rawValue
                if terrainValue != 16 && terrainValue != 17 {
                    state.players[player].explosions.append(Explosion(point: point, counter: 0))
                    onExplosion(point)
                    killPointBuilder(at: point, state: &state, onDropPills: onDropPills)
                }
            }
        } else if state.local.respawnCounter == explodeTicks {
            if state.local.mines >= 32 {
                onSuperboom()
                superboom(
                    state: &state,
                    onSuperboomTerrain: onSuperboomTerrain, onMineExplosion: onMineExplosion,
                    onDropPills: onDropPills
                )
            } else if state.local.mines > 0 || state.local.shells > 0 {
                onSmallboom()
                smallboom(
                    state: &state,
                    onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain,
                    onDropPills: onDropPills
                )
            }
            // else: neither boom fires, matching C exactly.
        } else if state.local.respawnCounter >= respawnTicks {
            onSpawn()
        }
        // respawnCounter in [explodeTicks+1, respawnTicks-1]: no-op, matching
        // the real dead zone in C where nothing happens but the counter ticks.
        return
    }

    // MARK: Alive branch — runs for whichever player is being ticked.

    let flags = state.players[player].inputFlags
    let boat = state.players[player].boat

    // maxSpeed/maxTurnSpeed intentionally read the LOCAL player's tank
    // position for every player's speed cap, including remote players —
    // this is a real C bug (tankmovelogic reads client.players[client.player]
    // instead of client.players[player] for these two lookups specifically)
    // and must not be "fixed": every client in a real multiplayer session
    // would compute a different, locally-biased cap for every other tank.
    let localTank = state.players[state.localPlayer].tank
    let localX = Int(localTank.x)
    let localY = Int(localTank.y)
    let localTerrain = state.terrain[localX, localY] ?? .sea

    // 1. Turning
    if flags.contains(.turnL) && !flags.contains(.turnR) {
        if state.players[player].turnSpeed < 0 {
            state.players[player].turnSpeed = 0
        }
        let max: Float = boat
            ? maxAngularVelocity
            : maxTurnSpeed(x: localX, y: localY, terrain: localTerrain, pills: state.pills, bases: state.bases)
        if state.players[player].turnSpeed > max {
            state.players[player].turnSpeed -= angularAccel / ticksPerSec
            if state.players[player].turnSpeed < max {
                state.players[player].turnSpeed = max
            }
        } else {
            state.players[player].turnSpeed += angularAccel / ticksPerSec
            if state.players[player].turnSpeed > max {
                state.players[player].turnSpeed = max
            }
        }
    } else if flags.contains(.turnR) && !flags.contains(.turnL) {
        if state.players[player].turnSpeed > 0 {
            state.players[player].turnSpeed = 0
        }
        let max: Float = boat
            ? maxAngularVelocity
            : maxTurnSpeed(x: localX, y: localY, terrain: localTerrain, pills: state.pills, bases: state.bases)
        if state.players[player].turnSpeed < -max {
            state.players[player].turnSpeed += angularAccel / ticksPerSec
            if state.players[player].turnSpeed > -max {
                state.players[player].turnSpeed = -max
            }
        } else {
            state.players[player].turnSpeed -= angularAccel / ticksPerSec
            if state.players[player].turnSpeed < -max {
                state.players[player].turnSpeed = -max
            }
        }
    } else {
        // No input, or both pressed: instant reset, not gradual decay.
        state.players[player].turnSpeed = 0.0
    }

    // 2. Direction update + wrap. NOT fmod — this exact floor-based formula.
    state.players[player].dir += state.players[player].turnSpeed / ticksPerSec
    if state.players[player].dir > k2Pif {
        state.players[player].dir -= k2Pif * floor(state.players[player].dir / k2Pif)
    } else if state.players[player].dir < 0.0 {
        state.players[player].dir += k2Pif * floor(state.players[player].dir / -k2Pif + 1.0)
    }

    // 3. Acceleration / braking
    let speedMax: Float = boat
        ? boatMaxSpeed
        : maxSpeed(x: localX, y: localY, terrain: localTerrain, pills: state.pills, bases: state.bases)
    if flags.contains(.accel) && !flags.contains(.brake) {
        if state.players[player].speed < speedMax {
            state.players[player].speed += accel / ticksPerSec
            if state.players[player].speed > speedMax {
                state.players[player].speed = speedMax
            }
        } else {
            state.players[player].speed -= accel / ticksPerSec
            if state.players[player].speed < speedMax {
                state.players[player].speed = speedMax
            }
        }
    } else if !flags.contains(.accel) && flags.contains(.brake) {
        state.players[player].speed -= accel / ticksPerSec
        if state.players[player].speed < 0.0 {
            state.players[player].speed = 0.0
        }
    } else if state.players[player].speed > speedMax {
        state.players[player].speed -= accel / ticksPerSec
        if state.players[player].speed < speedMax {
            state.players[player].speed = speedMax
        }
    }
    // else (no input, speed <= max): unchanged — tanks coast, no friction below max.

    // 4. Position update. Velocity direction is quantized via roundDir;
    // `dir` itself stays continuous (used again below for shore-push).
    state.players[player].tank =
        state.players[player].tank
        + (
            dir2vec(roundDir(state.players[player].dir)) * state.players[player].speed
            + dir2vec(state.players[player].kickDir) * state.players[player].kickSpeed
        ) / ticksPerSec

    // 5. Kickspeed decay (alive branch only — the dead branch never decays it).
    // C: `kickspeed -= 12.0/TICKSPERSEC;` — 12.0 is a double literal, so
    // the division computes in double precision (0.24 is not exactly
    // representable in either Float or Double, so the precision used for
    // the division itself matters, unlike accel/ticksPerSec which happens
    // to land on an exact power-of-2 fraction). Matches the Double-
    // promotion treatment already established for collisionDetect.
    state.players[player].kickSpeed = Float(
        Double(state.players[player].kickSpeed) - Double(kickSpeedDecay) / Double(ticksPerSec)
    )
    if state.players[player].kickSpeed < 0.0 {
        state.players[player].kickSpeed = 0.0
    }

    // 6. Shore push (boat only)
    if boat {
        let tank = state.players[player].tank
        let ix = Int(tank.x)
        let iy = Int(tank.y)
        let fx = tank.x - Float(ix)
        let fy = tank.y - Float(iy)
        // C: `cx = 1.0 - fx;` — 1.0 is a double literal; matches the exact
        // promotion treatment already established for collisionDetect.
        let cx = Float(1.0 - Double(fx))
        let cy = Float(1.0 - Double(fy))
        var push = Vec2f(x: 0, y: 0)

        let fxc = fx < tankRadius && isShore(x: ix - 1, y: iy, terrain: state.terrain, bases: state.bases)
        let cxc = cx < tankRadius && isShore(x: ix + 1, y: iy, terrain: state.terrain, bases: state.bases)
        let fyc = fy < tankRadius && isShore(x: ix, y: iy - 1, terrain: state.terrain, bases: state.bases)
        let cyc = cy < tankRadius && isShore(x: ix, y: iy + 1, terrain: state.terrain, bases: state.bases)
        let r2 = tankRadius * tankRadius

        if !fxc && !fyc, (fx * fx + fy * fy) < r2,
            isShore(x: ix - 1, y: iy - 1, terrain: state.terrain, bases: state.bases) {
            push.x = fx
            push.y = fy
        } else if !cxc && !fyc, (cx * cx + fy * fy) < r2,
            isShore(x: ix + 1, y: iy - 1, terrain: state.terrain, bases: state.bases) {
            push.x -= cx
            push.y = fy
        } else if !fxc && !cyc, (fx * fx + cy * cy) < r2,
            isShore(x: ix - 1, y: iy + 1, terrain: state.terrain, bases: state.bases) {
            push.x = fx
            push.y -= cy
        } else if !cxc && !cyc, (cx * cx + cy * cy) < r2,
            isShore(x: ix + 1, y: iy + 1, terrain: state.terrain, bases: state.bases) {
            push.x -= cx
            push.y -= cy
        } else if fxc {
            if fyc {
                push.x = fy
                push.y = fx
            } else if cyc {
                push.x = cy
                push.y = -fx
            } else {
                push.x = fx
                push.y = 0.0
            }
        } else if cxc {
            if fyc {
                push.x = -fy
                push.y = cx
            } else if cyc {
                push.x = -cy
                push.y = -cx
            } else {
                push.x = -cx
                push.y = 0.0
            }
        } else if fyc {
            push.x = 0.0
            push.y = fy
        } else if cyc {
            push.x = 0.0
            push.y = -cy
        }

        if mag2f(push) > 0.00001 {
            let f = mag2f(prj2f(push, dir2vec(state.players[player].dir) * state.players[player].speed))
            if f < pushForce {
                state.players[player].tank = state.players[player].tank + unit2f(push) * (pushForce / ticksPerSec)
            }
            if !(flags.contains(.accel) && !flags.contains(.brake)) {
                state.players[player].speed -= accel / ticksPerSec
                if state.players[player].speed < 0.0 {
                    state.players[player].speed = 0.0
                }
            }
        }
    }

    // 7. Terrain collision
    state.players[player].tank = collisionDetect(
        state.players[player].tank, radius: tankRadius, isSolid: tankCollision(owner: player, state: state)
    )
}
