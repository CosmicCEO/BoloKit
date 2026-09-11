import BoloKit

// Procedural glyph drawing (D67): nothing in the 290-cell image set is
// actual text, so this draws everything with pixel-level primitives rather
// than vendoring an OFL font. `GlyphRole` is the seam a font-backed source
// could plug into later without reworking `ImageIndex`/`SheetBuilder`.

public enum GlyphRole: Sendable {
    case connective(family: TileFamily, ortho: UInt8, diag: UInt8)
    case flatFill(r: UInt8, g: UInt8, b: UInt8)
    case mine
    case pill(armor: Int, friendly: Bool)
    /// `ownership`: 0 = player, 1 = friendly, 2 = enemy.
    case tank(heading: Int, ownership: Int, destroyed: Bool)
    case shell(frame: Int)
    case explosion(frame: Int)
    case builder(frame: Int)
    case crosshair
    case selectReticle
    /// **D152 item 2:** replaces the three flat-color base tiles with a house/fort silhouette
    /// so ownership reads at a glance instead of only via color.
    case base(ownership: BaseOwnership)
}

/// **D152 item 2:** who currently controls a refuelling base -- `NBAS00IMAGE`/`FBAS00IMAGE`/
/// `HBAS00IMAGE`'s three cases (`ImageIndex.swift`), same partition `mapimage()` already uses.
public enum BaseOwnership: Sendable {
    case neutral
    case friendly
    case hostile
}

public func renderGlyph(_ role: GlyphRole) -> Canvas16 {
    var c = Canvas16()
    switch role {
    case .connective(let family, let ortho, let diag):
        drawConnective(&c, family: family, ortho: ortho, diag: diag)
    case .flatFill(let r, let g, let b):
        c.fillRect(0, 0, 16, 16, r, g, b)
    case .mine:
        c.fillRect(0, 0, 16, 16, 40, 40, 40)
        c.fillCircle(cx: 8, cy: 8, radius: 3, 200, 30, 30)
    case .pill(let armor, let friendly):
        drawPill(&c, armor: armor, friendly: friendly)
    case .tank(let heading, let ownership, let destroyed):
        drawTank(&c, heading: heading, ownership: ownership, destroyed: destroyed)
    case .shell(let frame):
        c.fillCircle(cx: 8, cy: 8, radius: 1.5 + Double(frame) * 0.3, 255, 220, 120)
    case .explosion(let frame):
        let radius = 2.0 + Double(frame) * 1.3
        c.fillRing(cx: 8, cy: 8, inner: max(0, radius - 2), outer: radius, 255, 140, 30)
    case .builder(let frame):
        let s = 3 + frame
        c.fillRect(8 - s, 8 - s, 8 + s, 8 + s, 160, 160, 60)
    case .crosshair:
        c.fillRect(7, 0, 9, 16, 255, 255, 255)
        c.fillRect(0, 7, 16, 9, 255, 255, 255)
        c.fillCircle(cx: 8, cy: 8, radius: 1.2, 0, 0, 0)
    case .selectReticle:
        for i in stride(from: 0, to: 16, by: 2) {
            c.set(i, 0, 255, 255, 0)
            c.set(i, 15, 255, 255, 0)
            c.set(0, i, 255, 255, 0)
            c.set(15, i, 255, 255, 0)
        }
    case .base(let ownership):
        drawBase(&c, ownership: ownership)
    }
    return c
}

private func familyColor(_ family: TileFamily) -> (UInt8, UInt8, UInt8) {
    switch family {
    case .wall: return (140, 140, 140)
    case .river: return (60, 110, 220)
    case .forest: return (30, 100, 40)
    case .crater: return (70, 60, 55)
    // D154 Wave 1: dark asphalt tone, shifted off the prior flat tan/dirt look.
    case .road: return (52, 52, 58)
    case .boat: return (40, 160, 170)
    case .sea: return (20, 70, 160)
    }
}

/// Draws a plus-shaped blob: a fixed core, extended toward each orthogonal direction with a
/// connectivity bit set -- a generic autotile look, not a fidelity target (D64: freshly-
/// generated sheets carry no fidelity obligation).
///
/// Corner fill: `.wall` and `.road` are the only families `Autotile.swift` tracks real
/// diagonal bits for (`needsDiag` for wall; `deriveRoadConnectivity()`'s own diagonal sweep
/// for road, since `mapimage()`'s road branch genuinely reads diagonal neighbors via
/// `isRoadLikeTile` to disambiguate several cases), so both use `diag` directly. Every other
/// family (sea/river/forest/crater/boat) always gets `diag == 0` -- corners inferred from
/// their two adjacent orthogonal bits instead, a discovered-by-Wave-7.2 fix: leaving those
/// corners permanently transparent meant any run of 2+ adjacent same-family tiles (open
/// water, forest, craters -- most of any real map) rendered with a permanent checkerboard of
/// transparent gaps at internal corners rather than a continuous fill, invisible to Wave
/// 7.0's own per-glyph-in-isolation tests since nothing tiled glyphs adjacently before this
/// wave existed to do it. D86: road was originally lumped into the inferred-corner bucket
/// alongside the five families with no real diagonal data, silently discarding its own real
/// diag bits -- fixed to match wall's treatment.
private func drawConnective(_ c: inout Canvas16, family: TileFamily, ortho: UInt8, diag: UInt8) {
    let (r, g, b) = familyColor(family)
    c.fillRect(4, 4, 12, 12, r, g, b)
    if ortho & 1 != 0 { c.fillRect(0, 4, 4, 12, r, g, b) }
    if ortho & 2 != 0 { c.fillRect(4, 0, 12, 4, r, g, b) }
    if ortho & 4 != 0 { c.fillRect(12, 4, 16, 12, r, g, b) }
    if ortho & 8 != 0 { c.fillRect(4, 12, 12, 16, r, g, b) }

    let tracksOwnDiag = family == .wall || family == .road
    let nw = tracksOwnDiag ? diag & 1 != 0 : (ortho & 1 != 0 && ortho & 2 != 0)
    let ne = tracksOwnDiag ? diag & 2 != 0 : (ortho & 4 != 0 && ortho & 2 != 0)
    let sw = tracksOwnDiag ? diag & 4 != 0 : (ortho & 1 != 0 && ortho & 8 != 0)
    let se = tracksOwnDiag ? diag & 8 != 0 : (ortho & 4 != 0 && ortho & 8 != 0)
    if nw { c.fillRect(0, 0, 4, 4, r, g, b) }
    if ne { c.fillRect(12, 0, 16, 4, r, g, b) }
    if sw { c.fillRect(0, 12, 4, 16, r, g, b) }
    if se { c.fillRect(12, 12, 16, 16, r, g, b) }

    // D154 Wave 1: wall bevel -- a lighter edge on the north/west side of the wall's own
    // filled shape, darker on south/east, for a blockier textured read closer to the
    // reference's brick-look walls. Only ever recolors already-opaque pixels (never writes
    // alpha), so it cannot turn a connectivity-driven transparent corner opaque.
    if family == .wall {
        applyWallBevel(&c)
    }

    // D154 Wave 1: an isolated road tile (no road neighbor at all, ortho == 0 && diag == 0)
    // gets a dashed lone-segment marker, inspired by the reference's dashed-line marker for
    // single unconnected road cells, so it reads differently from a connected road segment.
    if family == .road && ortho == 0 && diag == 0 {
        drawIsolatedRoadMarker(&c)
    }
}

/// D154 Wave 1: recolors every already-opaque pixel of the wall's own shape based on its
/// immediate neighbors' opacity -- north/west-open pixels lighten, south/east-open pixels
/// darken, interior pixels keep the flat base color. Neighbor-relative, not fixed-coordinate,
/// so it adapts to whatever `ortho`/`diag` shape was actually filled above.
private func applyWallBevel(_ c: inout Canvas16) {
    let highlight: (UInt8, UInt8, UInt8) = (190, 190, 195)
    let shadow: (UInt8, UInt8, UInt8) = (85, 85, 90)
    func isOpaque(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, x < Canvas16.size, y >= 0, y < Canvas16.size else { return false }
        return c.pixels[(y * Canvas16.size + x) * 4 + 3] != 0
    }
    for y in 0..<Canvas16.size {
        for x in 0..<Canvas16.size {
            guard isOpaque(x, y) else { continue }
            let northOpen = !isOpaque(x, y - 1)
            let westOpen = !isOpaque(x - 1, y)
            let southOpen = !isOpaque(x, y + 1)
            let eastOpen = !isOpaque(x + 1, y)
            if northOpen || westOpen {
                c.set(x, y, highlight.0, highlight.1, highlight.2, 255)
            } else if southOpen || eastOpen {
                c.set(x, y, shadow.0, shadow.1, shadow.2, 255)
            }
        }
    }
}

/// D154 Wave 1: dashed "+" inside the isolated road tile's own painted 8x8 center square
/// (`fillRect(4,4,12,12,...)` above) -- a lone-segment marker, not a copy of any reference
/// image's exact dash geometry.
private func drawIsolatedRoadMarker(_ c: inout Canvas16) {
    let (r, g, b): (UInt8, UInt8, UInt8) = (215, 210, 200)
    c.fillRect(4, 7, 7, 9, r, g, b)
    c.fillRect(9, 7, 12, 9, r, g, b)
    c.fillRect(7, 4, 9, 7, r, g, b)
    c.fillRect(7, 9, 9, 12, r, g, b)
}

/// D154 Wave 1: redesigned from a flat armor-level fill bar into a sunburst/spoked icon,
/// inspired by (not copied from) the reference's spoked pillbox icon. Armor level modulates
/// spoke length (2.5px at armor 0 .. 6.5px at armor 15) rather than a bar height; owner color
/// is unchanged from the prior design (friendly/hostile), including its already-disclosed,
/// out-of-scope collision with `tankPalette(1)` (D152) -- not touched by this wave.
private func drawPill(_ c: inout Canvas16, armor: Int, friendly: Bool) {
    let (r, g, b): (UInt8, UInt8, UInt8) = friendly ? (60, 110, 220) : (200, 50, 50)
    let level = min(max(armor, 0), 15)
    // Dark inset backing, distinct from `.mine`'s full-cell fill + small solid dot.
    c.fillRect(2, 2, 14, 14, 45, 45, 50, 220)
    let length = 2.5 + (Double(level) / 15.0) * 4.0
    let dirs: [(Double, Double)] = [
        (1, 0), (0.70711, 0.70711), (0, 1), (-0.70711, 0.70711),
        (-1, 0), (-0.70711, -0.70711), (0, -1), (0.70711, -0.70711),
    ]
    for (dx, dy) in dirs {
        c.fillRotatedBar(dx: dx, dy: dy, length: length, halfWidth: 0.7, r, g, b)
    }
    c.fillCircle(cx: 8, cy: 8, radius: 1.8, r, g, b)
}

/// **D152 item 2:** friendly shifted off `(60,110,220)` -- byte-identical to `familyColor(.river)`
/// above, the collision D152 orders fixed. Neutral/hostile match `ImageIndex.swift`'s prior
/// `.flatFill` values exactly (no reason to change those two).
private func basePalette(_ ownership: BaseOwnership) -> (UInt8, UInt8, UInt8) {
    switch ownership {
    case .neutral: return (200, 200, 60)
    case .friendly: return (35, 75, 175)
    case .hostile: return (200, 50, 50)
    }
}

/// **D152 item 2:** a house/fort silhouette -- dark backing square, a triangular roof widening
/// row-by-row, a rectangular wall body below it, and a dark door notch -- replacing the prior
/// undecorated flat-color fill so base ownership reads as a shape, not color alone.
private func drawBase(_ c: inout Canvas16, ownership: BaseOwnership) {
    let (r, g, b) = basePalette(ownership)
    // Dark backing, same alpha-fillRect pattern drawPill already uses.
    c.fillRect(1, 1, 15, 15, 30, 30, 30, 220)
    // Triangular roof: widens by one column per side per row, rows 3-7.
    for row in 3...7 {
        let half = row - 3
        c.fillRect(8 - half, row, 8 + half + 1, row + 1, r, g, b)
    }
    // Wall body, rows 8-13.
    c.fillRect(3, 8, 13, 14, r, g, b)
    // Door notch: a dark rectangle centered in the wall's bottom edge.
    c.fillRect(7, 10, 9, 14, 20, 20, 20)
}

private func tankPalette(_ ownership: Int) -> (UInt8, UInt8, UInt8) {
    switch ownership {
    case 0: return (220, 220, 220)
    case 1: return (60, 110, 220)
    default: return (200, 50, 50)
    }
}

private func drawTank(_ c: inout Canvas16, heading: Int, ownership: Int, destroyed: Bool) {
    let (r, g, b) = tankPalette(ownership)
    if destroyed {
        for i in 0..<16 {
            c.set(i, i, r / 2, g / 2, b / 2)
            c.set(15 - i, i, r / 2, g / 2, b / 2)
        }
        return
    }
    // D70: rotate by BoloKit's own `dir2vec` output directly, matching the
    // 16-heading quantization already established in `PhysicsOps.swift`
    // (`roundDir`, step `kPif/8`) -- not an independently-derived angle
    // that could silently drift from the simulation's own convention.
    let dir = Float(heading) * (kPif / 8.0)
    let v = dir2vec(dir)
    c.fillRotatedTriangle(dx: Double(v.x), dy: Double(v.y), r, g, b)
    // D148(C): a solid triangle alone reads as an ambiguous arrow at small
    // sizes -- add a dark barrel extending past the hull's tip (6px) toward
    // the same heading, using the same rotation convention as the hull, so
    // rotation can never drift from `dir2vec`/D70's reference frame.
    c.fillRotatedBar(dx: Double(v.x), dy: Double(v.y), length: 5.0, halfWidth: 0.8, 20, 20, 20)
}
