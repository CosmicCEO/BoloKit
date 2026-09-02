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
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    for i in state.pills.indices {
        guard state.pills[i].armour != pillOnboard, state.pills[i].armour > 0 else {
            state.pills[i].counter = 0
            continue
        }

        let pillCenter = Vec2f(x: Float(state.pills[i].x) + 0.5, y: Float(state.pills[i].y) + 0.5)

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

        let eligible = aliveConnected.filter { player in
            state.pills[i].owner == playerNeutral
                || !testAlliance(Int(state.pills[i].owner), player, players: state.players)
        }

        guard !eligible.isEmpty else {
            state.pills[i].counter = 0
            continue
        }

        let inRange: [(player: Int, mag: Float)] = eligible.compactMap { player in
            let diff = state.players[player].tank - pillCenter
            let mag = mag2f(diff)
            guard (mag <= 2.0 || forestVis(state.players[player].tank, state: state) > 0.25) && mag <= 8.0 else {
                return nil
            }
            return (player, mag)
        }

        guard let minMag = inRange.map(\.mag).min() else {
            // No `else` branch in C here at this nesting level — everyone
            // eligible is simply out of range, so the counter freezes
            // (not resets), "remembering" partial charge. Not a bug to
            // smooth over.
            continue
        }
        // A player is disqualified in C iff someone else eligible has
        // strictly smaller mag — i.e. iff they're not in the argmin set.
        // Ties (equal minimum mag) all survive together.
        let closestSet = inRange.filter { $0.mag == minMag }.map(\.player)

        state.pills[i].counter += 1
        guard state.pills[i].counter >= state.pills[i].speed else { continue }

        for player in closestSet {
            let diff = state.players[player].tank - pillCenter
            let old = oldTankPositions[player]
            let vel = (state.players[player].tank - old) * ticksPerSec
            let compi = vel - prj2f(diff, vel)
            // C: `sqrtf(fabsf((SHELLVEL*SHELLVEL) - dot2f(compi, compi)))` —
            // SHELLVEL is a double literal, so the subtraction computes in
            // double, then narrows to Float when passed to `fabsf` (not
            // `fabs`) — before the absolute value, not after. See file header.
            let raw = Float(Double(shellVelocity) * Double(shellVelocity) - Double(dot2f(compi, compi)))
            let compj = unit2f(diff) * sqrtf(fabsf(raw))

            // C: `mul2f(diff, 0.70711219/mag)` — 0.70711219 is a double
            // literal, so the division computes in double and narrows to
            // Float once when passed as `mul2f`'s scalar argument.
            let offset = Float(0.70711219 / Double(minMag))
            let shell = Shell(
                point: pillCenter + diff * offset,
                dir: vec2dir(compi + compj),
                // C: `8.5 - 0.70711219` — both double literals, subtracted
                // in double, narrowed to Float once at assignment to `range`.
                range: Float((8.5 as Double) - 0.70711219),
                owner: state.pills[i].owner,
                boat: false,
                pill: true
            )

            if !shellCollisionTest(
                shell: shell, state: &state, onMineExplosion: onMineExplosion, onDropPills: onDropPills
            ) {
                state.players[player].shells.append(shell)
            }
        }

        state.pills[i].counter = 0
    }
}
