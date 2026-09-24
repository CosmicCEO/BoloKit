import BoloKit

// Procedural glyph drawing (D67): nothing in the tile/sprite image set is
// actual text, so this draws everything with pixel-level primitives rather
// than vendoring an OFL font. `GlyphRole` is the seam a font-backed source
// could plug into later without reworking `ImageIndex`/`SheetBuilder`.

public enum GlyphRole: Sendable {
    case connective(family: TileFamily, ortho: UInt8, diag: UInt8)
    case flatFill(r: UInt8, g: UInt8, b: UInt8)
    /// D155 (#110): textured, not a `.flatFill` alias -- fine speckle to read as a distinct
    /// surface from `.swamp`'s blotches, not just a different hue.
    case grass
    /// D155 (#110): a handful of darker irregular blotches, structurally different from
    /// `.grass`'s fine speckle -- reads as "wet/mucky" rather than "textured but even."
    case swamp
    case mine
    case pill(armor: Int, ownership: BaseOwnership)
    /// `ownership`: 0 = player, 1 = friendly, 2 = enemy. `boat`: #147 -- the tank is currently
    /// boated (`PlayerState.boat`), matching the reference's separate `PTKB`/`FTKB`/`ETKB`
    /// sprite row (`ImageIndex.swift`'s `spriteGlyphRole`) with a distinct hull shape.
    case tank(heading: Int, ownership: Int, boat: Bool, destroyed: Bool)
    /// v1.5.1 #114: `heading` is one of the 16 `headingColumn` buckets (`PhysicsOps.swift`),
    /// matching the C reference's real `Sprites.png` asset -- not an animation frame index
    /// (the prior `frame` name/semantics only covered 6 of the 16 indices `headingColumn`
    /// can actually produce, so shells fired toward the other 10 headings rendered into a
    /// transparent gap for their entire flight; see `ImageIndex.swift`'s shell dispatch).
    case shell(heading: Int)
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
public enum BaseOwnership: Sendable, Equatable {
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
    case .grass:
        drawGrass(&c)
    case .swamp:
        drawSwamp(&c)
    case .mine:
        c.fillRect(0, 0, 16, 16, 40, 40, 40)
        c.fillCircle(cx: 8, cy: 8, radius: 3, 200, 30, 30)
    case .pill(let armor, let ownership):
        drawPill(&c, armor: armor, ownership: ownership)
    case .tank(let heading, let ownership, let boat, let destroyed):
        drawTank(&c, heading: heading, ownership: ownership, boat: boat, destroyed: destroyed)
    case .shell(let heading):
        // v1.5.1 #114: constant-size directional streak, not a growing circle -- size no
        // longer varies by index (that was mistaking a heading bucket for an animation
        // frame), and it's now oriented so all 16 headings render distinctly, same
        // `dir2vec`/`kPif/8` rotation convention `drawTank` uses (D70).
        let dir = Float(heading) * (kPif / 8.0)
        let v = dir2vec(dir)
        c.fillCircle(cx: 8, cy: 8, radius: 1.3, 255, 200, 100)
        c.fillRotatedBar(dx: Double(v.x), dy: Double(v.y), length: 4.0, halfWidth: 0.8, 255, 230, 150)
    case .explosion(let frame):
        let radius = 2.0 + Double(frame) * 1.3
        c.fillRing(cx: 8, cy: 8, inner: max(0, radius - 2), outer: radius, 255, 140, 30)
    case .builder(let frame):
        // #146: frames 0/1 are `GameRenderView.drawBuilder`'s BUILD0/BUILD1 walk-cycle
        // alternation, frame 2 is BUILD2 (parachute-in). A humanoid silhouette so the
        // "little green man" reads as a person, not a growing placeholder square.
        if frame == 2 {
            drawBuilderParachute(&c)
        } else {
            drawBuilderWalking(&c, strideFlip: frame == 1)
        }
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

    // D155 (#110): NW-half highlight plus scattered glints, so open sea reads as a lit
    // surface instead of a flat color block -- same "recolor only opaque pixels" rule the
    // wall bevel established, since sea's corners can still be transparent when inferred
    // from ortho (see the corner-fill comment above `drawConnective`).
    if family == .sea {
        applySeaShading(&c)
    }

    // D155 (#110): a handful of lighter/darker canopy clumps over the forest's own filled
    // shape, distinct in silhouette from both grass's fine speckle and swamp's blotches.
    if family == .forest {
        applyForestCanopy(&c)
    }

    // D156 (#110 remainder): three horizontal flow-streaks -- reads as "current," and
    // structurally distinct from sea's diagonal-plus-glint treatment despite the similar hue,
    // so the two water families don't read as the same texture in a different color.
    if family == .river {
        applyRiverFlow(&c)
    }

    // D156 (#110 remainder): short dashed ripple marks, distinct from river's continuous
    // flow-lines (river reads as "current," boat reads as "choppy/still water").
    if family == .boat {
        applyBoatRipple(&c)
    }

    // D156 (#110 remainder): a darker bowl toward the tile's center with a lighter rim --
    // reads as an impact crater's actual shape, not just a darker patch of ground.
    if family == .crater {
        applyCraterBowl(&c)
    }

    // D154 Wave 1: an isolated road tile (no road neighbor at all, ortho == 0 && diag == 0)
    // gets a dashed lone-segment marker, inspired by the reference's dashed-line marker for
    // single unconnected road cells, so it reads differently from a connected road segment.
    // D156 (#110 remainder): a connected segment gets a small centerline lane mark instead --
    // always inside the core 8x8 fill every connected road shape has, so no opacity check
    // is needed the way the other new textures above require.
    if family == .road {
        if ortho == 0 && diag == 0 {
            drawIsolatedRoadMarker(&c)
        } else {
            applyRoadLaneMark(&c)
        }
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

/// D155 (#110): NW-half highlight (a coarse two-band "lit from one side" gradient, the same
/// idea as the wall bevel but by diagonal position instead of edge-adjacency, since open water
/// has no shape edges to bevel) plus a sparse set of brighter glint pixels on top. Only ever
/// recolors already-opaque pixels, matching the wall bevel's invariant.
private func applySeaShading(_ c: inout Canvas16) {
    // #153 follow-up: halved both deltas from the base sea color (20, 70, 160) -- Jerod
    // reported the pattern reads too bold/high-contrast against the flat fill.
    let highlight: (UInt8, UInt8, UInt8) = (32, 82, 175)
    let glint: (UInt8, UInt8, UInt8) = (45, 100, 190)
    func isOpaque(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, x < Canvas16.size, y >= 0, y < Canvas16.size else { return false }
        return c.pixels[(y * Canvas16.size + x) * 4 + 3] != 0
    }
    for y in 0..<Canvas16.size {
        for x in 0..<Canvas16.size {
            guard isOpaque(x, y), x + y < Canvas16.size else { continue }
            c.set(x, y, highlight.0, highlight.1, highlight.2, 255)
        }
    }
    for y in 0..<Canvas16.size {
        for x in 0..<Canvas16.size {
            guard isOpaque(x, y), (x * 5 + y * 9) % 13 == 0 else { continue }
            c.set(x, y, glint.0, glint.1, glint.2, 255)
        }
    }
}

/// D155 (#110): a handful of lighter/darker circular clumps over the forest's own filled
/// shape, reading as clustered foliage -- a distinct *silhouette*, not just a color shift,
/// from `applyGrassSpeckle`'s fine scatter or `applySwampBlotches`' irregular puddles below.
/// Only ever recolors already-opaque pixels (forest's corners can be transparent when
/// inferred from ortho, same as sea above).
private func applyForestCanopy(_ c: inout Canvas16) {
    let lighter: (UInt8, UInt8, UInt8) = (55, 130, 55)
    let darker: (UInt8, UInt8, UInt8) = (15, 75, 25)
    func isOpaque(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, x < Canvas16.size, y >= 0, y < Canvas16.size else { return false }
        return c.pixels[(y * Canvas16.size + x) * 4 + 3] != 0
    }
    let clumps: [(cx: Double, cy: Double, r: Double, lighter: Bool)] = [
        (4, 3, 1.5, true), (11, 2, 1.3, false), (7, 6, 1.7, true),
        (2, 9, 1.4, false), (12, 9, 1.5, true), (6, 12, 1.6, false), (10, 13, 1.3, true),
    ]
    for (cx, cy, r, isLighter) in clumps {
        let color = isLighter ? lighter : darker
        for y in max(0, Int(cy - r))...min(Canvas16.size - 1, Int(cy + r)) {
            for x in max(0, Int(cx - r))...min(Canvas16.size - 1, Int(cx + r)) {
                guard isOpaque(x, y) else { continue }
                let dx = Double(x) + 0.5 - cx
                let dy = Double(y) + 0.5 - cy
                if dx * dx + dy * dy <= r * r {
                    c.set(x, y, color.0, color.1, color.2, 255)
                }
            }
        }
    }
}

/// D156 (#110 remainder): three full-width horizontal highlight rows -- "flow lines," distinct
/// in *shape* from `applySeaShading`'s diagonal split (river is a current, sea is open water).
/// Only ever recolors already-opaque pixels, same invariant as every texture above.
private func applyRiverFlow(_ c: inout Canvas16) {
    // #153 follow-up: halved the delta from the base river color (60, 110, 220) -- same
    // "too bold" softening as `applySeaShading` above, kept in sync since the two water
    // families share the complaint even though their patterns are shaped differently.
    let flow: (UInt8, UInt8, UInt8) = (75, 125, 227)
    func isOpaque(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, x < Canvas16.size, y >= 0, y < Canvas16.size else { return false }
        return c.pixels[(y * Canvas16.size + x) * 4 + 3] != 0
    }
    for y in [2, 7, 12] {
        for x in 0..<Canvas16.size {
            guard isOpaque(x, y) else { continue }
            c.set(x, y, flow.0, flow.1, flow.2, 255)
        }
    }
}

/// D156 (#110 remainder): short dashed highlight segments (not full-width rows, unlike
/// `applyRiverFlow` above) -- reads as choppy ripples rather than a directional current.
private func applyBoatRipple(_ c: inout Canvas16) {
    let ripple: (UInt8, UInt8, UInt8) = (90, 200, 210)
    func isOpaque(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, x < Canvas16.size, y >= 0, y < Canvas16.size else { return false }
        return c.pixels[(y * Canvas16.size + x) * 4 + 3] != 0
    }
    for y in stride(from: 3, to: Canvas16.size, by: 5) {
        for startX in stride(from: 1, to: Canvas16.size - 2, by: 4) {
            for x in startX..<(startX + 3) {
                guard isOpaque(x, y) else { continue }
                c.set(x, y, ripple.0, ripple.1, ripple.2, 255)
            }
        }
    }
}

/// D156 (#110 remainder): a darker bowl toward the tile's own center, a lighter ring at its
/// rim, and the flat base color in between -- reads as an actual crater's shape (concentric,
/// centered on the tile), not just a mottled patch like swamp's irregular off-center blotches.
private func applyCraterBowl(_ c: inout Canvas16) {
    let rim: (UInt8, UInt8, UInt8) = (95, 82, 74)
    let bowl: (UInt8, UInt8, UInt8) = (40, 32, 28)
    func isOpaque(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, x < Canvas16.size, y >= 0, y < Canvas16.size else { return false }
        return c.pixels[(y * Canvas16.size + x) * 4 + 3] != 0
    }
    for y in 0..<Canvas16.size {
        for x in 0..<Canvas16.size {
            guard isOpaque(x, y) else { continue }
            let dx = Double(x) - 8, dy = Double(y) - 8
            let dist = (dx * dx + dy * dy).squareRoot()
            if dist < 3 {
                c.set(x, y, bowl.0, bowl.1, bowl.2, 255)
            } else if dist > 6 {
                c.set(x, y, rim.0, rim.1, rim.2, 255)
            }
        }
    }
}

/// D156 (#110 remainder): a small centerline mark for a *connected* road segment, distinct from
/// `drawIsolatedRoadMarker`'s dashed-cross treatment for a lone tile. Always lands inside the
/// core 8x8 fill every connected road shape has (`fillRect(4,4,12,12,...)` above always runs),
/// so unlike every other texture in this file it needs no opacity check.
private func applyRoadLaneMark(_ c: inout Canvas16) {
    let mark: (UInt8, UInt8, UInt8) = (210, 205, 195)
    c.fillRect(7, 7, 9, 9, mark.0, mark.1, mark.2)
}

/// D155 (#110): unconditional flat green plus a fine, even speckle -- deliberately the
/// *quietest* of the three new textures (grass is the default ground cover, shouldn't compete
/// visually with anything placed on it), and structurally distinct from swamp's clustered
/// blotches below (scattered single pixels vs. a few solid blobs).
private func drawGrass(_ c: inout Canvas16) {
    c.fillRect(0, 0, 16, 16, 70, 140, 60)
    applyGrassSpeckle(&c)
}

private func applyGrassSpeckle(_ c: inout Canvas16) {
    let highlight: (UInt8, UInt8, UInt8) = (95, 165, 80)
    for y in 0..<Canvas16.size {
        for x in 0..<Canvas16.size {
            guard (x * 7 + y * 13) % 11 == 0 else { continue }
            c.set(x, y, highlight.0, highlight.1, highlight.2, 255)
        }
    }
}

/// D155 (#110): unconditional flat tan-brown plus a few darker irregular blotches -- reads as
/// "wet/mucky" via *shape* (clustered blobs), not just a browner grass.
private func drawSwamp(_ c: inout Canvas16) {
    c.fillRect(0, 0, 16, 16, 110, 100, 50)
    applySwampBlotches(&c)
}

private func applySwampBlotches(_ c: inout Canvas16) {
    let shadow: (UInt8, UInt8, UInt8) = (75, 68, 32)
    let blotches: [(cx: Double, cy: Double, r: Double)] = [
        (3, 4, 1.8), (12, 3, 1.4), (7, 9, 2.1), (13, 12, 1.5), (2, 13, 1.3),
    ]
    for (cx, cy, r) in blotches {
        for y in max(0, Int(cy - r))...min(Canvas16.size - 1, Int(cy + r)) {
            for x in max(0, Int(cx - r))...min(Canvas16.size - 1, Int(cx + r)) {
                let dx = Double(x) + 0.5 - cx
                let dy = Double(y) + 0.5 - cy
                if dx * dx + dy * dy <= r * r {
                    c.set(x, y, shadow.0, shadow.1, shadow.2, 255)
                }
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

/// D154 Wave 1 sunburst, plus v1.2.1 three-way ownership (yellow unowned, matching
/// `basePalette(.neutral)`) and a visible wreck mound at armor 0.
private func drawPill(_ c: inout Canvas16, armor: Int, ownership: BaseOwnership) {
    let (r, g, b) = pillPalette(ownership)
    let level = min(max(armor, 0), 15)
    c.fillRect(2, 2, 14, 14, 45, 45, 50, 220)
    if level == 0 {
        c.fillRect(4, 9, 12, 13, r, g, b)
        c.fillRect(5, 7, 11, 9, r, g, b)
        c.fillRect(6, 6, 10, 7, r, g, b)
    }
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

private func pillPalette(_ ownership: BaseOwnership) -> (UInt8, UInt8, UInt8) {
    switch ownership {
    case .neutral: return (200, 200, 60)
    case .friendly: return (60, 110, 220)
    case .hostile: return (200, 50, 50)
    }
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

/// #146: an upright walking figure -- round head, torso, arms, and two legs whose stride
/// offsets swap between the two frames `drawBuilder` alternates between (BUILD0/BUILD1),
/// giving the same "legs moving" read the reference's own alternation implies. No heading
/// input (unlike `drawTank`) -- the reference's builder sprite has no directional art either,
/// it always faces the same way regardless of travel direction.
private func drawBuilderWalking(_ c: inout Canvas16, strideFlip: Bool) {
    let skin: (UInt8, UInt8, UInt8) = (210, 190, 150)
    let suit: (UInt8, UInt8, UInt8) = (60, 150, 70)
    c.fillCircle(cx: 8, cy: 3.5, radius: 1.6, skin.0, skin.1, skin.2)
    c.fillRect(6, 5, 10, 11, suit.0, suit.1, suit.2)
    c.fillRect(4, 6, 6, 9, suit.0, suit.1, suit.2)
    c.fillRect(10, 6, 12, 9, suit.0, suit.1, suit.2)
    if strideFlip {
        c.fillRect(5, 11, 7, 16, suit.0, suit.1, suit.2)
        c.fillRect(9, 11, 11, 15, suit.0, suit.1, suit.2)
    } else {
        c.fillRect(5, 11, 7, 15, suit.0, suit.1, suit.2)
        c.fillRect(9, 11, 11, 16, suit.0, suit.1, suit.2)
    }
}

/// #146: a dome canopy over a smaller hanging figure with two suspension-cord pixels per
/// side -- distinct in silhouette from the walking pose, for BUILD2 (`.parachute` status).
private func drawBuilderParachute(_ c: inout Canvas16) {
    let canopy: (UInt8, UInt8, UInt8) = (200, 200, 60)
    let suit: (UInt8, UInt8, UInt8) = (60, 150, 70)
    let skin: (UInt8, UInt8, UInt8) = (210, 190, 150)
    let cord: (UInt8, UInt8, UInt8) = (230, 230, 230)
    let cx = 8.0, cy = 3.0, r = 7.0
    for y in 0..<5 {
        for x in 0..<16 {
            let dx = Double(x) + 0.5 - cx
            let dy = Double(y) + 0.5 - cy
            if dx * dx + dy * dy <= r * r {
                c.set(x, y, canopy.0, canopy.1, canopy.2)
            }
        }
    }
    c.set(3, 5, cord.0, cord.1, cord.2)
    c.set(4, 6, cord.0, cord.1, cord.2)
    c.set(12, 5, cord.0, cord.1, cord.2)
    c.set(11, 6, cord.0, cord.1, cord.2)
    c.fillCircle(cx: 8, cy: 9, radius: 1.3, skin.0, skin.1, skin.2)
    c.fillRect(7, 10, 9, 14, suit.0, suit.1, suit.2)
    c.fillRect(6, 14, 10, 16, suit.0, suit.1, suit.2)
}

private func tankPalette(_ ownership: Int) -> (UInt8, UInt8, UInt8) {
    switch ownership {
    case 0: return (220, 220, 220)
    case 1: return (60, 110, 220)
    default: return (200, 50, 50)
    }
}

private func drawTank(_ c: inout Canvas16, heading: Int, ownership: Int, boat: Bool, destroyed: Bool) {
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
    if boat {
        drawBoatHull(&c, dx: Double(v.x), dy: Double(v.y), r, g, b)
    } else {
        c.fillRotatedTriangle(dx: Double(v.x), dy: Double(v.y), r, g, b)
        // D148(C): a solid triangle alone reads as an ambiguous arrow at small
        // sizes -- add a dark barrel extending past the hull's tip (6px) toward
        // the same heading, using the same rotation convention as the hull, so
        // rotation can never drift from `dir2vec`/D70's reference frame.
        c.fillRotatedBar(dx: Double(v.x), dy: Double(v.y), length: 5.0, halfWidth: 0.8, 20, 20, 20)
    }
}

/// #147: the reference draws a distinct hull sprite for a boated tank (`PTKB`/`FTKB`/`ETKB`),
/// not the same triangle+barrel as a land tank -- this was previously indistinguishable since
/// `GlyphRole.tank` had no `boat` parameter at all. Reuses the same bow (`fillRotatedTriangle`)
/// as the land tank's hull, but adds a wide flat stern deck extending aft (negative-length
/// `fillRotatedBar`, matching drawTank's own rotation convention) instead of the thin forward
/// gun barrel, plus a thin waterline band -- an elongated boat-like silhouette, not an
/// ambiguous arrowhead.
private func drawBoatHull(_ c: inout Canvas16, dx: Double, dy: Double, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
    c.fillRotatedTriangle(dx: dx, dy: dy, r, g, b)
    c.fillRotatedBar(dx: dx, dy: dy, length: -4.0, halfWidth: 2.2, r, g, b)
    c.fillRotatedBar(dx: dx, dy: dy, length: 6.0, halfWidth: 0.5, 20, 40, 70)
}
