import Darwin

// MARK: - Wave 5.3c — pilllogic / forestvis
//
// Ported from `pilllogic()` (client.c:5034) and `forestvis()` (bolo.c:174),
// plus the local-effect-free `isforest()` (bolo.c:152).
//
// **Generalization from C's network-authority model:** `pilllogic(old)`
// takes no player parameter at all — it always operates on the single
// `client.player`, called once per tick (not in a per-connected-player
// loop like `shelllogic`/`builderlogic`). Its inner "am I the closest
// eligible target" loop (`for j in 0..<MAXPLAYERS where j != client.player`)
// only makes sense in C's real multiplayer model: every connected client
// runs this same code with its OWN identity as `client.player`, so summing
// every client's independent computation is "for every player P, check
// whether P is the closest eligible target for each hostile pill." This
// port generalizes exactly that way — `pillTick(player:old:...)` is called
// once per connected player, playing the `client.player` role for that
// call, with the inner loop's `j != client.player` becoming `j != player`.
// This mirrors the precedent already established for `shellTick`'s tank-hit
// loop and preserves the exact same tie-break quirk already flagged in the
// Wave 5.1 report: if two players are exactly equidistant from a pill,
// neither's check disqualifies the other (the inner test requires
// *strictly* closer), so both can independently satisfy "no one is closer
// than me" and the pill can fire at both in the same tick.
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

/// Per-tick pillbox AI, called once per connected player per tick — see
/// the file header for why `player` generalizes C's hardcoded
/// `client.player`. `old` is that player's tank position before this
/// tick's physics ran (needed for the shell's lead-targeting velocity
/// term). Ported from `pilllogic()` (client.c:5034).
public func pillTick(
    player: Int,
    old: Vec2f,
    state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard !state.players[player].dead else { return }

    for i in state.pills.indices {
        guard state.pills[i].armour != pillOnboard, state.pills[i].armour > 0,
            state.pills[i].owner == playerNeutral
                || !testAlliance(Int(state.pills[i].owner), player, players: state.players)
        else {
            state.pills[i].counter = 0
            continue
        }

        let pillCenter = Vec2f(x: Float(state.pills[i].x) + 0.5, y: Float(state.pills[i].y) + 0.5)
        let diff = state.players[player].tank - pillCenter
        let mag = mag2f(diff)

        guard (mag <= 2.0 || forestVis(state.players[player].tank, state: state) > 0.25) && mag <= 8.0 else {
            // No `else` branch in C here — an armed, hostile, but
            // out-of-range pill leaves `counter` untouched (not reset),
            // "remembering" partial charge. Not a bug to smooth over.
            continue
        }

        var closerHostileFound = false
        for j in state.players.indices
            where j != player && state.players[j].connected && !state.players[j].dead {
            let jDist = mag2f(state.players[j].tank - pillCenter)
            if jDist < mag,
                state.pills[i].owner == playerNeutral
                    || !testAlliance(Int(state.pills[i].owner), j, players: state.players),
                jDist <= 2.0 || forestVis(state.players[j].tank, state: state) > 0.25 {
                closerHostileFound = true
                break
            }
        }

        guard !closerHostileFound else {
            state.pills[i].counter = 0
            continue
        }

        state.pills[i].counter += 1
        guard state.pills[i].counter >= state.pills[i].speed else { continue }

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
        let offset = Float(0.70711219 / Double(mag))
        let shell = Shell(
            point: pillCenter + diff * offset,
            dir: vec2dir(compi + compj),
            // C: `8.5 - 0.70711219` — both double literals, subtracted in
            // double, narrowed to Float once at assignment to `range`.
            range: Float((8.5 as Double) - 0.70711219),
            owner: state.pills[i].owner,
            boat: false,
            pill: true
        )

        if !shellCollisionTest(shell: shell, state: &state, onMineExplosion: onMineExplosion, onDropPills: onDropPills) {
            state.players[player].shells.append(shell)
        }

        state.pills[i].counter = 0
    }
}
