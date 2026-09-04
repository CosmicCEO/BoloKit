import BoloKit

// Wave 7.1 placeholder app icon.
//
// `Reference/c`'s `XBolo.icns` is Stuart Cheshire's original copyrighted art and is off-limits
// as a source, exactly like the sprite/tile sheets — so the placeholder is drawn here instead of
// copied. It deliberately reuses `renderGlyph` rather than opening a second, icon-only drawing
// path: the icon is literally two of the game's own 16x16 glyphs composited and scaled up, so it
// cannot drift from what the sheets render.
//
// Unlike `Tiles.png`/`Sprites.png` (regenerated at build time and never committed, D72), the icon
// output *is* committed: `actool` compiles the asset catalog during the Resources phase, so the
// PNGs have to exist before the build starts. Regenerate with `BoloGlyphs icon <dir>`.

public struct AppIconImage: Sendable {
    /// Width and height in pixels; always a whole multiple of `Canvas16.size`.
    public let size: Int
    /// Row-major RGBA8, `size * size * 4` bytes.
    public let pixels: [UInt8]
}

/// The 16x16 base the icon is scaled up from: the player's tank on grass.
///
/// Grass is taken from `tileGlyphRole(for: GRAS00IMAGE)` rather than a literal so the icon tracks
/// the sheet's own palette. Heading 0 matches `dir2vec`'s reference direction (D70).
public func buildAppIconBase() -> Canvas16 {
    var canvas: Canvas16
    if case .flatFill(let r, let g, let b)? = tileGlyphRole(for: GRAS00IMAGE, connectivity: [:]) {
        canvas = renderGlyph(.flatFill(r: r, g: g, b: b))
    } else {
        // GRAS00IMAGE is an unconditional `.flatFill` case in `tileGlyphRole`; this branch only
        // exists so a future change there fails loudly here rather than silently recolouring.
        preconditionFailure("GRAS00IMAGE no longer resolves to .flatFill in tileGlyphRole")
    }
    let tank = renderGlyph(.tank(heading: 0, ownership: 0, destroyed: false))
    composite(tank, over: &canvas)
    return canvas
}

/// Source-over alpha composite of one 16x16 glyph onto another.
private func composite(_ src: Canvas16, over dst: inout Canvas16) {
    for i in stride(from: 0, to: src.pixels.count, by: 4) {
        let alpha = Int(src.pixels[i + 3])
        if alpha == 0 { continue }
        for channel in 0..<3 {
            let s = Int(src.pixels[i + channel])
            let d = Int(dst.pixels[i + channel])
            // Rounded source-over; alpha 255 reproduces the source byte exactly.
            dst.pixels[i + channel] = UInt8((s * alpha + d * (255 - alpha) + 127) / 255)
        }
        dst.pixels[i + 3] = 255
    }
}

/// Nearest-neighbour upscale of the 16x16 base. Every macOS icon slot (16/32/64/128/256/512/1024)
/// is a whole multiple of 16, so this is an exact pixel replication with no resampling blur —
/// which is the point for pixel art.
public func buildAppIcon(size: Int) -> AppIconImage {
    precondition(size > 0 && size % Canvas16.size == 0, "icon size must be a positive multiple of \(Canvas16.size), got \(size)")
    let base = buildAppIconBase()
    let scale = size / Canvas16.size
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    for y in 0..<size {
        let srcRow = (y / scale) * Canvas16.size
        for x in 0..<size {
            let src = (srcRow + x / scale) * 4
            let dst = (y * size + x) * 4
            pixels[dst] = base.pixels[src]
            pixels[dst + 1] = base.pixels[src + 1]
            pixels[dst + 2] = base.pixels[src + 2]
            pixels[dst + 3] = base.pixels[src + 3]
        }
    }
    return AppIconImage(size: size, pixels: pixels)
}

/// The distinct pixel dimensions the macOS `AppIcon` slots resolve to (1x and 2x of 16/32/128/256/512).
public let appIconPixelSizes = [16, 32, 64, 128, 256, 512, 1024]
