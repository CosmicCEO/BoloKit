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
    }
    return c
}

private func familyColor(_ family: TileFamily) -> (UInt8, UInt8, UInt8) {
    switch family {
    case .wall: return (140, 140, 140)
    case .river: return (60, 110, 220)
    case .forest: return (30, 100, 40)
    case .crater: return (70, 60, 55)
    case .road: return (150, 120, 80)
    case .boat: return (40, 160, 170)
    case .sea: return (20, 70, 160)
    }
}

/// Draws a plus-shaped blob: a fixed core, extended toward each orthogonal
/// direction with a connectivity bit set, with diagonal corners filled in
/// when their bit is set -- a generic autotile look, not a fidelity target
/// (D64: freshly-generated sheets carry no fidelity obligation).
private func drawConnective(_ c: inout Canvas16, family: TileFamily, ortho: UInt8, diag: UInt8) {
    let (r, g, b) = familyColor(family)
    c.fillRect(4, 4, 12, 12, r, g, b)
    if ortho & 1 != 0 { c.fillRect(0, 4, 4, 12, r, g, b) }
    if ortho & 2 != 0 { c.fillRect(4, 0, 12, 4, r, g, b) }
    if ortho & 4 != 0 { c.fillRect(12, 4, 16, 12, r, g, b) }
    if ortho & 8 != 0 { c.fillRect(4, 12, 12, 16, r, g, b) }
    if diag & 1 != 0 { c.fillRect(0, 0, 4, 4, r, g, b) }
    if diag & 2 != 0 { c.fillRect(12, 0, 16, 4, r, g, b) }
    if diag & 4 != 0 { c.fillRect(0, 12, 4, 16, r, g, b) }
    if diag & 8 != 0 { c.fillRect(12, 12, 16, 16, r, g, b) }
}

private func drawPill(_ c: inout Canvas16, armor: Int, friendly: Bool) {
    let (r, g, b): (UInt8, UInt8, UInt8) = friendly ? (60, 110, 220) : (200, 50, 50)
    let level = min(max(armor, 0), 15)
    let fillHeight = ((level + 1) * 12 + 8) / 16
    c.fillRect(2, 2, 14, 14, 50, 50, 50, 200)
    c.fillRect(3, 13 - fillHeight, 13, 13, r, g, b)
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
    let angle = Double(heading) * (2.0 * Double.pi / 16.0)
    c.fillRotatedTriangle(angle: angle, r, g, b)
}
