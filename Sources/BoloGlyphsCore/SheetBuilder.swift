import BoloKit

public struct GeneratedSheets: Sendable {
    public var tiles: RGBASheet
    public var sprites: RGBASheet
}

/// Builds both sheets deterministically from `BoloKit`'s existing image
/// constants (D63) -- pure function of the two dispatch tables in
/// `ImageIndex.swift`, no I/O.
public func buildSheets() -> GeneratedSheets {
    let connectivity = deriveAllConnectivity()

    var tiles = RGBASheet()
    for index in tileIndexRange {
        guard let role = tileGlyphRole(for: index, connectivity: connectivity) else { continue }
        tiles.blit(renderGlyph(role), atIndex: index)
    }

    var sprites = RGBASheet()
    for index: Int32 in 0...SELETRIMAGE {
        guard let role = spriteGlyphRole(for: index) else { continue }
        sprites.blit(renderGlyph(role), atIndex: index)
    }

    return GeneratedSheets(tiles: tiles, sprites: sprites)
}
