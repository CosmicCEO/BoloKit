import Darwin

// MARK: - roundDir

/// Quantizes a continuous heading to the nearest of 16 discrete directions
/// (π/8 radian steps). Tank position stored continuously (for smooth
/// turning) but movement is quantized to these 16 headings each tick.
///
/// Ported from `rounddir()` in Reference/c/client.c:6765. Uses `kPif`
/// (Vector.swift) rather than `Float.pi` — the same constant already used
/// for this identical `kPif/8.0` idiom elsewhere in the codebase
/// (dir2vec/vec2dir). The two are bit-identical as Float in practice; this
/// is a consistency choice, not a correctness fix.
public func roundDir(_ dir: Float) -> Float {
    let step = kPif / 8.0
    return step * floor(dir / step + 0.5)
}

// MARK: - maxSpeed / maxTurnSpeed

/// Maximum tank forward speed at (x, y), including pill/base overrides.
///
/// Ported from `maxspeed()` in Reference/c/client.c:3594. Override order:
/// an armed pill blocks movement (0.0); a dead pill or any base allows full
/// road speed (matches the C literal `3.125`, equal to `roadMaxSpeed`);
/// otherwise falls through to the pure terrain tier (`terrainMaxSpeed`,
/// shipped Wave 3.1 — its switch is an exact match for `maxspeed`'s own
/// terrain switch, verified against the C reference).
public func maxSpeed(x: Int, y: Int, terrain: Terrain, pills: [Pill], bases: [Base]) -> Float {
    if let i = findPill(x: x, y: y, pills: pills) {
        return pills[i].armour > 0 ? 0.0 : roadMaxSpeed
    }
    if findBase(x: x, y: y, bases: bases) != nil {
        return roadMaxSpeed
    }
    return terrainMaxSpeed(terrain)
}

/// Maximum tank turn rate at (x, y), including pill/base overrides.
///
/// Ported from `maxturnspeed()` in Reference/c/client.c:3659. Same override
/// structure as `maxSpeed`; the pill/base override value is the literal
/// `2.5`, matching `terrainMaxTurnSpeed`'s own bare-literal style rather
/// than introducing a new named constant for it.
public func maxTurnSpeed(x: Int, y: Int, terrain: Terrain, pills: [Pill], bases: [Base]) -> Float {
    if let i = findPill(x: x, y: y, pills: pills) {
        return pills[i].armour > 0 ? 0.0 : 2.5
    }
    if findBase(x: x, y: y, bases: bases) != nil {
        return 2.5
    }
    return terrainMaxTurnSpeed(terrain)
}

// MARK: - collisionDetect

/// Resolves a circular collider of `radius` centered at `p` against up to
/// 8 neighboring grid cells (4 cardinal, 4 diagonal), pushing `p` out of
/// any solid cell it overlaps.
///
/// Ported verbatim from `collisiondetect()` in Reference/c/client.c:6927,
/// **including a source bug**: in the `lyc && hyc` branch (squeezed
/// between solid cells above and below), the C source assigns `p.x = fy +
/// 0.5` where the surrounding pattern makes clear `p.y` was intended. This
/// must NOT be fixed — differential testing against the C oracle requires
/// bit-identical behavior, bug included.
///
/// Finding: this branch only fires when `radius > 0.5` (both `lyc` and
/// `hyc` require the fractional y-offset to be `< radius` from both edges
/// simultaneously, i.e. `ly < radius` and `1 - ly < radius`). No radius
/// constant in this codebase exceeds 0.5 (`tankRadius = 0.375`,
/// `builderRadius = 0.125`), so this bug is currently dormant in real
/// gameplay — reachable only via a synthetic test radius.
public func collisionDetect(_ p: Vec2f, radius: Float, isSolid: (Pointi) -> Bool) -> Vec2f {
    var p = p

    let ix = Int32(p.x)
    let iy = Int32(p.y)
    let fx = Float(ix)
    let fy = Float(iy)
    let lx = p.x - fx
    // C: `hx = 1.0 - lx;` — 1.0 is a double literal, so this promotes lx to
    // double, subtracts, and truncates to float only at assignment. Swift
    // infers a bare `1.0` as Float when the target type is Float, which
    // would skip that intermediate double rounding and diverge from the C
    // oracle on some inputs — every "1.0 - x" / "x + 0.5" site below is
    // written with explicit Double(...) promotion to match C exactly.
    let hx: Float = Float(1.0 - Double(lx))
    let ly = p.y - fy
    let hy: Float = Float(1.0 - Double(ly))
    let r2 = radius * radius

    let lxc = lx < radius && isSolid(makepoint(ix - 1, iy))
    let hxc = hx < radius && isSolid(makepoint(ix + 1, iy))
    let lyc = ly < radius && isSolid(makepoint(ix, iy - 1))
    let hyc = hy < radius && isSolid(makepoint(ix, iy + 1))

    if lxc {
        if hxc {
            p.x = Float(Double(fx) + 0.5)
        } else {
            p.x = fx + radius
        }
    } else if hxc {
        p.x = Float(Double(fx) + (1.0 - Double(radius)))
    }

    if lyc {
        if hyc {
            // BUG: replicates C source p.x/p.y swap for behavioral parity — do not fix.
            p.x = Float(Double(fy) + 0.5)
        } else {
            p.y = fy + radius
        }
    } else if hyc {
        p.y = Float(Double(fy) + (1.0 - Double(radius)))
    }

    if !lxc && !lyc {
        let sqr = lx * lx + ly * ly
        if sqr < r2 && isSolid(makepoint(ix - 1, iy - 1)) {
            let sca = radius / sqrtf(sqr)
            p.x = fx + sca * lx
            p.y = fy + sca * ly
        }
    }

    if !hxc && !lyc {
        let sqr = hx * hx + ly * ly
        if sqr < r2 && isSolid(makepoint(ix + 1, iy - 1)) {
            let sca = radius / sqrtf(sqr)
            p.x = Float(Double(fx) + (1.0 - Double(sca * hx)))
            p.y = fy + sca * ly
        }
    }

    if !lxc && !hyc {
        let sqr = lx * lx + hy * hy
        if sqr < r2 && isSolid(makepoint(ix - 1, iy + 1)) {
            let sca = radius / sqrtf(sqr)
            p.x = fx + sca * lx
            p.y = Float(Double(fy) + (1.0 - Double(sca * hy)))
        }
    }

    if !hxc && !hyc {
        let sqr = hx * hx + hy * hy
        if sqr < r2 && isSolid(makepoint(ix + 1, iy + 1)) {
            let sca = radius / sqrtf(sqr)
            p.x = Float(Double(fx) + (1.0 - Double(sca * hx)))
            p.y = Float(Double(fy) + (1.0 - Double(sca * hy)))
        }
    }

    return p
}
