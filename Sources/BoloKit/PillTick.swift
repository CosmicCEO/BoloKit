import Darwin

// MARK: - Wave 5.3c — pilllogic / forestvis
//
// Ported from `pilllogic()` (client.c:5034) and `forestvis()` (bolo.c:174),
// plus the local-effect-free `isforest()` (bolo.c:152).
//
// **Fixed after a PARITY FAIL on the first cut of this file (see
// AGENT_NOTES.md, Wave 5.3c audit).** `pilllogic(old)` takes no player
// parameter at all in C — it hardcodes `client.player` and runs once per
// human's own client *process*. Every process mutates only its own
// private, unsynced replica of `pill.counter`; since every replica runs
// identical deterministic math over the same (eventually-synced) world
// state, only the replica belonging to whoever is genuinely the closest
// hostile target ever climbs toward the firing threshold, and every other
// replica resetting to 0 constantly is harmless, because those replicas
// are private and never influence the real game state.
//
// The first cut of this port called `pillTick` once per connected player,
// generalizing `client.player` → `player` — but all those calls mutated
// ONE shared `state.pills[i].counter`, not N independent replicas. That's
// not equivalent: a bystander (allied, or hostile-but-farther) processed
// *after* the genuine target in a tick's player-index order unconditionally
// resets the shared counter, erasing the real target's progress. The fix
// below computes each pill's closest-eligible-target *election* exactly
// once per tick, across the whole state, and applies exactly one
// increment/freeze/reset/fire decision per pill — not once per player.
//
// **Ties still fire at every tied player, not an arbitrary winner.** Two
// equidistant hostile players' *independent* private counters in the
// distributed model increment in perfect lockstep (identical inputs,
// identical outputs, every tick) and cross the firing threshold on the
// same tick — both get shot. Since tied targets move in lockstep, a
// single shared counter reaching threshold and firing at every member of
// the current tied-closest set reproduces that exactly, rather than
// approximating it away by picking one winner.
//
// **v1.2.2 Cheshire playability:** XBolo `pilllogic()` acquires tanks only.
// Hostile armed pills also acquire other hostile armed pills (same
// range/vis) so a placed turret can wear down an enemy pill for capture —
// a competition gap XBolo left vs Mac Bolo 0.99.7bv. Shells aimed at a
// pill enqueue on `localPlayer`'s list (no target client). Tank
// lead-targeting math is unchanged.
//
// **A real, C-source-acknowledged precision quirk, not a bug to fix:**
// `(SHELLVEL*SHELLVEL) - dot2f(compi, compi)` computes in double precision
// (`SHELLVEL` is the double literal `7.0`), but is then passed to `fabsf`
// (not `fabs`) — an implicit double-to-float narrowing *before* the
// absolute value, not after. The C source's own comment calls this out:
// `/* fabsf is a cludge */`. Replicated exactly: narrow to `Float` first,
// then take the magnitude, then `sqrt`.

// MARK: - isForest

/// True if (x, y) is unoccupied by any placed pill or base and its terrain
/// is forest or mined-forest. Ported from `isforest()` (bolo.c:152).
public func isForest(x: Int, y: Int, state: GameState) -> Bool {
    guard x >= 0, x < 256, y >= 0, y < 256 else { return false }
    if state.pills.contains(where: { $0.armour != pillOnboard && Int($0.x) == x && Int($0.y) == y }) {
        return false
    }
    if state.bases.contains(where: { Int($0.x) == x && Int($0.y) == y }) {
        return false
    }
    switch state.terrain[x, y] {
    case .forest, .minedForest:
        return true
    default:
        return false
    }
}

// MARK: - forestVis

/// Fractional forest visibility at `v`, in `[0, 1]`: `0` deep inside a
/// forest tile with forest on every side, `1` fully in the open. Ported
/// from `forestvis()` (bolo.c:174) — an interpolation across the 8
/// neighbors of the containing tile, favoring the nearest non-forest
/// direction.
public func forestVis(_ v: Vec2f, state: GameState) -> Float {
    guard v.x >= 0.0, v.x < 256.0, v.y >= 0.0, v.y < 256.0 else { return 0.0 }
    let x = Int(v.x)
    let y = Int(v.y)
    guard isForest(x: x, y: y, state: state) else { return 1.0 }

    let fx = v.x - floorf(v.x)
    // C: `cx = 1.0 - fx;` — 1.0 is a double literal, so this promotes fx to
    // double, subtracts, and narrows to float once at assignment. Same
    // treatment for cy and every `1.0 - sqrtf(...)` corner term below —
    // matches the pattern already established for collisionDetect/
    // isShore. Verified empirically: omitting this diverges from the C
    // oracle on ~48% of broadly-random (fx, fy, neighbor) inputs.
    let cx = Float(1.0 - Double(fx))
    let fy = v.y - floorf(v.y)
    let cy = Float(1.0 - Double(fy))

    // C's `MAX(x, y)` is `((x) > (y)) ? (x) : (y)`, and every call below
    // pits a `float` operand against the double literal `0.0` in a
    // ternary — C's conditional operator requires both branches to share
    // a common type, so mixing `double`/`float` promotes the WHOLE ternary
    // (including the float branch that's actually selected) to `double`.
    // This cascades through every level of MAX-of-MAX-of-MAX nesting, so
    // the entire tree below computes in double precision, narrowing to
    // Float only once, at this function's own return — not at each `max`.
    // Verified empirically: computing this tree in Float throughout (one
    // narrowing per level, matching Swift's plain `max`) diverges from the
    // C oracle on ~48% of broadly-random inputs.
    let edgeX = max(
        isForest(x: x - 1, y: y, state: state) ? 0.0 : Double(cx),
        isForest(x: x + 1, y: y, state: state) ? 0.0 : Double(fx)
    )
    let edgeY = max(
        isForest(x: x, y: y - 1, state: state) ? 0.0 : Double(cy),
        isForest(x: x, y: y + 1, state: state) ? 0.0 : Double(fy)
    )

    let cornerNW: Double = isForest(x: x - 1, y: y - 1, state: state)
        ? 0.0 : 1.0 - Double(sqrtf(fx * fx + fy * fy))
    let cornerSW: Double = isForest(x: x - 1, y: y + 1, state: state)
        ? 0.0 : 1.0 - Double(sqrtf(fx * fx + cy * cy))
    let cornerNE: Double = isForest(x: x + 1, y: y - 1, state: state)
        ? 0.0 : 1.0 - Double(sqrtf(cx * cx + fy * fy))
    let cornerSE: Double = isForest(x: x + 1, y: y + 1, state: state)
        ? 0.0 : 1.0 - Double(sqrtf(cx * cx + cy * cy))

    let result = max(
        max(edgeX, edgeY), max(max(cornerNW, cornerSW), max(cornerNE, cornerSE))
    )
    return Float(result)
}

// MARK: - pillTick

/// Per-tick pillbox AI for the whole game state — called **once per tick**,
/// not once per player (see the file header for why). `oldTankPositions`
/// gives each player's tank position before this tick's physics ran,
/// indexed like `state.players`; whichever player(s) win a given pill's
/// closest-target election need their own entry for the shell's
/// lead-targeting velocity term. Ported from `pilllogic()` (client.c:5034).
public func pillTick(
    state: inout GameState,
    oldTankPositions: [Vec2f],
    onMineExplosion: (Pointi) -> Void = { _ in },
    onShouldBroadcastDropPill: (Int, Int, Int) -> Void = { _, _, _ in }
) {
    for i in state.pills.indices {
        guard state.pills[i].armour != pillOnboard, state.pills[i].armour > 0 else {
            state.pills[i].counter = 0
            continue
        }

        let pillCenter = Vec2f(x: Float(state.pills[i].x) + 0.5, y: Float(state.pills[i].y) + 0.5)
        let shooterOwner = state.pills[i].owner

        func isHostileTarget(owner: UInt8) -> Bool {
            shooterOwner == playerNeutral || owner == playerNeutral
                || !testAlliance(Int(shooterOwner), Int(owner), players: state.players)
        }

        func inSight(_ target: Vec2f) -> (diff: Vec2f, mag: Float)? {
            let diff = target - pillCenter
            let mag = mag2f(diff)
            guard mag > 0, (mag <= 2.0 || forestVis(target, state: state) > 0.25), mag <= 8.0 else {
                return nil
            }
            return (diff, mag)
        }

        // Two distinct "nobody's a target" cases, with different C
        // outcomes: if there's no alive connected player *at all*, no
        // client is running any code this tick, so every private replica
        // is untouched (freeze) — not the same as every existing alive
        // player explicitly failing the alliance check on their own pill,
        // where each of THEIR clients does run and explicitly zeros their
        // own counter (reset).
        let aliveConnected = state.players.indices.filter {
            state.players[$0].connected && !state.players[$0].dead
        }
        guard !aliveConnected.isEmpty else { continue }

        let eligibleTanks = aliveConnected.filter { isHostileTarget(owner: UInt8($0)) }
        let eligiblePills = state.pills.indices.filter { j in
            j != i && state.pills[j].armour != pillOnboard && state.pills[j].armour > 0
                && isHostileTarget(owner: state.pills[j].owner)
        }

        guard !eligibleTanks.isEmpty || !eligiblePills.isEmpty else {
            state.pills[i].counter = 0
            continue
        }

        var inRange: [(target: PillAim, mag: Float, diff: Vec2f)] = []
        for player in eligibleTanks {
            if let seen = inSight(state.players[player].tank) {
                inRange.append((.tank(player), seen.mag, seen.diff))
            }
        }
        for j in eligiblePills {
            let center = Vec2f(x: Float(state.pills[j].x) + 0.5, y: Float(state.pills[j].y) + 0.5)
            if let seen = inSight(center) {
                inRange.append((.pill(j), seen.mag, seen.diff))
            }
        }

        guard let minMag = inRange.map(\.mag).min() else {
            // Eligible but all out of range: freeze (C has no else here).
            continue
        }
        let closestSet = inRange.filter { $0.mag == minMag }

        state.pills[i].counter += 1
        guard state.pills[i].counter >= state.pills[i].speed else { continue }

        let enqueuePillShot: Int = {
            if state.localPlayer >= 0, state.localPlayer < state.players.count {
                return state.localPlayer
            }
            return aliveConnected[0]
        }()

        for aim in closestSet {
            let vel: Vec2f
            let enqueue: Int
            switch aim.target {
            case .tank(let player):
                let old = player < oldTankPositions.count ? oldTankPositions[player] : state.players[player].tank
                vel = (state.players[player].tank - old) * ticksPerSec
                enqueue = player
            case .pill:
                vel = Vec2f(x: 0, y: 0)
                enqueue = enqueuePillShot
            }
            emitPillShell(
                from: pillCenter, diff: aim.diff, minMag: minMag, vel: vel, owner: shooterOwner,
                enqueuePlayer: enqueue, state: &state, onMineExplosion: onMineExplosion,
                onShouldBroadcastDropPill: onShouldBroadcastDropPill
            )
        }

        state.pills[i].counter = 0
    }
}

private enum PillAim {
    case tank(Int)
    case pill(Int)
}

/// Shared muzzle spawn + lead-targeting for tank and pill aims. Tank `vel`
/// is the C `pilllogic` term; pill aims pass zero. `enqueuePlayer` is the
/// shell-list owner (`shellTick` walks every connected list).
private func emitPillShell(
    from pillCenter: Vec2f,
    diff: Vec2f,
    minMag: Float,
    vel: Vec2f,
    owner: UInt8,
    enqueuePlayer: Int,
    state: inout GameState,
    onMineExplosion: (Pointi) -> Void,
    onShouldBroadcastDropPill: (Int, Int, Int) -> Void
) {
    let compi = vel - prj2f(diff, vel)
    // C: `sqrtf(fabsf((SHELLVEL*SHELLVEL) - dot2f(compi, compi)))` —
    // SHELLVEL is a double literal, so the subtraction computes in
    // double, then narrows to Float when passed to `fabsf` (not
    // `fabs`) — before the absolute value, not after. See file header.
    let raw = Float(Double(shellVelocity) * Double(shellVelocity) - Double(dot2f(compi, compi)))
    let compj = unit2f(diff) * sqrtf(fabsf(raw))
    let offset = Float(0.70711219 / Double(minMag))
    let shell = Shell(
        point: pillCenter + diff * offset,
        dir: vec2dir(compi + compj),
        range: Float((8.5 as Double) - 0.70711219),
        owner: owner,
        boat: false,
        pill: true
    )
    if !shellCollisionTest(
        shell: shell, player: enqueuePlayer, state: &state, onMineExplosion: onMineExplosion,
        onShouldBroadcastDropPill: onShouldBroadcastDropPill
    ) {
        state.players[enqueuePlayer].shells.append(shell)
    }
}
