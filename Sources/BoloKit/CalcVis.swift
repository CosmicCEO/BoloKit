import Darwin

// MARK: - v1.5.0 (issue #1) — fogVis / calcVis
//
// Ported from `fogvis()`/`calcvis()` (`bolo.c:108-150,214-323`). Neither function is
// called anywhere in `Reference/c` — confirmed by exhaustive grep across every `.c` file
// — unlike the structurally-identical `forestVis` (`PillTick.swift:86`, ported from the
// sibling `forestvis()`, `bolo.c:174`), which *is* called, for pillbox target-acquisition
// line-of-sight, unrelated to fog. See `docs/CONSTRAINTS.md`'s "Fog-of-war (v1.5.0)"
// section: the working theory, confirmed with the repo owner, is that this is an
// unfinished Mac Bolo feature XBolo's own port left unwired, not a feature the real game
// lacked — this port's fidelity target is Mac Bolo 0.99.7bv, not XBolo specifically (D3).
// Ported bit-for-bit here and differentially tested against `Reference/c`'s own (unused)
// functions; wired into sprite rendering separately (`GameRenderView.swift`) as a
// reconstruction with no oracle-exercised behavior to verify the *wiring* against, only
// the math.

// MARK: - isFog

/// True if (x, y) is off-map or has no current vision source. Ported from the `ISFOG`
/// macro (`bolo.c:36`), which treats off-map coordinates as always fogged.
public func isFog(x: Int32, y: Int32, fogState: FogState) -> Bool {
    guard x >= 0, x < 256, y >= 0, y < 256 else { return true }
    return fogState.fog[Int(y) * 256 + Int(x)] == 0
}

// MARK: - fogVis

/// Fractional fog visibility at `v`, in `[0, 1]`: `0` deep inside fog with fog on every
/// side, `1` fully lit. Ported from `fogvis()` (`bolo.c:108`) — structurally identical to
/// `forestVis` (`PillTick.swift:86`) with `isForest` swapped for `isFog`, including the
/// same C double-precision-promotion behavior that function's own comment documents and
/// depends on (C's `1.0` literal promotes the whole `MAX`-of-ternary tree to double,
/// narrowing only once at return — verified empirically on `forestVis` to matter on ~48%
/// of random inputs; replicated here since `fogvis()`'s C body has the identical literal
/// structure).
public func fogVis(_ v: Vec2f, fogState: FogState) -> Float {
    guard v.x >= 0.0, v.x < 256.0, v.y >= 0.0, v.y < 256.0 else { return 0.0 }
    let x = Int32(v.x)
    let y = Int32(v.y)
    guard isFog(x: x, y: y, fogState: fogState) else { return 1.0 }

    let fx = v.x - floorf(v.x)
    let cx = Float(1.0 - Double(fx))
    let fy = v.y - floorf(v.y)
    let cy = Float(1.0 - Double(fy))

    let edgeX = max(
        isFog(x: x - 1, y: y, fogState: fogState) ? 0.0 : Double(cx),
        isFog(x: x + 1, y: y, fogState: fogState) ? 0.0 : Double(fx)
    )
    let edgeY = max(
        isFog(x: x, y: y - 1, fogState: fogState) ? 0.0 : Double(cy),
        isFog(x: x, y: y + 1, fogState: fogState) ? 0.0 : Double(fy)
    )

    let cornerNW: Double = isFog(x: x - 1, y: y - 1, fogState: fogState)
        ? 0.0 : 1.0 - Double(sqrtf(fx * fx + fy * fy))
    let cornerSW: Double = isFog(x: x - 1, y: y + 1, fogState: fogState)
        ? 0.0 : 1.0 - Double(sqrtf(fx * fx + cy * cy))
    let cornerNE: Double = isFog(x: x + 1, y: y - 1, fogState: fogState)
        ? 0.0 : 1.0 - Double(sqrtf(cx * cx + fy * fy))
    let cornerSE: Double = isFog(x: x + 1, y: y + 1, fogState: fogState)
        ? 0.0 : 1.0 - Double(sqrtf(cx * cx + cy * cy))

    let result = max(
        max(edgeX, edgeY), max(max(cornerNW, cornerSW), max(cornerNE, cornerSE))
    )
    return Float(result)
}

// MARK: - calcVis

/// Combined fog + forest + self-proximity visibility at `v`, in `[0, 1]`. Ported from
/// `calcvis()` (`bolo.c:214-323`). `observer`'s own tank and own live deployed pills
/// (armour neither `pillOnboard` nor `0`) get a hard 3.0-world-unit minimum-visibility
/// floor regardless of fog/forest, blended smoothly between 2.0 and 3.0 units rather than
/// snapping.
public func calcVis(_ v: Vec2f, state: GameState, fogState: FogState, observer: Int) -> Float {
    guard v.x >= 0.0, v.x < 256.0, v.y >= 0.0, v.y < 256.0 else { return 0.0 }

    let fog = fogVis(v, fogState: fogState)
    let forest = forestVis(v, state: state)

    var dist: Float = 3.0
    let ownTank = state.players[observer].tank
    let tankDist = mag2f(sub2f(ownTank, v))
    if tankDist < dist { dist = tankDist }

    let ownerID = UInt8(truncatingIfNeeded: observer)
    for pill in state.pills where pill.owner == ownerID && pill.armour != pillOnboard && pill.armour != 0 {
        let pillCenter = Vec2f(x: Float(pill.x) + 0.5, y: Float(pill.y) + 0.5)
        let pillDist = mag2f(sub2f(v, pillCenter))
        if pillDist < dist { dist = pillDist }
    }

    return calcVisBlend(forestVis: forest, fogVis: fog, dist: dist)
}

/// The final distance/blend step of `calcvis()` (`bolo.c:304-322`), factored out of
/// `calcVis` so it's independently fuzzable against the C oracle without needing a live
/// `GameState`/`FogState` (`calcvis_blend_oracle` in `Sources/CXBolo/fog.c`).
///
/// `forestvis*fogvis` is computed once as a `float*float` product, matching C's own
/// single narrower-precision multiplication (`forestvis`/`fogvis` are both `float`
/// locals in C) — only that already-rounded-to-`Float` result is promoted to `Double`
/// at each subsequent mixed-type operation against the `2.0`/`3.0`/`0.5` `double`
/// literals, never the original operands multiplied in `Double`. Getting this order
/// backwards (promoting `forestVis`/`fogVis` to `Double` before multiplying) measurably
/// diverges from the oracle in the low bits (verified empirically fuzzing this function).
public func calcVisBlend(forestVis: Float, fogVis: Float, dist: Float) -> Float {
    let combined = forestVis * fogVis
    if dist <= 2.0 {
        return combined < 0.5 ? 0.5 : combined
    } else if dist < 3.0 {
        if combined < 0.5 {
            return Float((3.0 - Double(dist)) * (0.5 - Double(combined)) + Double(combined))
        } else {
            return combined
        }
    } else {
        return combined
    }
}
