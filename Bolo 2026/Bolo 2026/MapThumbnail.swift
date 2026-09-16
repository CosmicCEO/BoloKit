import CoreGraphics
import Foundation
import BoloKit

/// v1.3.0 #26 — 256×256 map thumbnail from `decodeBMap` + generated tile sheet.
/// One pixel per map cell, occupied region scaled to fill, matching the XBolo
/// Quick Look size. Uses BoloGlyphs `Tiles.png`, not Cheshire art.
nonisolated enum MapThumbnail {
    static let pixelSize = 256

    static func loadTiles(from bundle: Bundle = .main) -> CGImage? {
        guard let url = bundle.url(forResource: "Tiles", withExtension: "png"),
              let provider = CGDataProvider(url: url as CFURL)
        else { return nil }
        return CGImage(
            pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    static func makeImage(from bytes: [UInt8], tiles: CGImage) -> CGImage? {
        var state = GameState()
        guard decodeBMap(bytes, into: &state) else { return nil }
        let grid = displayTileGrid(for: state)
        let bounds = occupiedBounds(state)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let width = pixelSize
        let height = pixelSize
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setShouldAntialias(false)
        ctx.setFillColor(red: 0, green: 0, blue: 0.4, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let span = max(bounds.width, bounds.height)
        let scale = CGFloat(width) / CGFloat(span)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(
            x: CGFloat(-bounds.minX) + CGFloat(span - bounds.width) / 2,
            y: CGFloat(-bounds.minY) + CGFloat(span - bounds.height) / 2
        )

        for y in bounds.minY..<bounds.maxY {
            for x in bounds.minX..<bounds.maxX {
                let dst = CGRect(x: x, y: y, width: 1, height: 1)
                let index = mapimage(grid, Int32(x), Int32(y))
                if index >= 0, let cell = tiles.cropping(to: sheetRect(index)) {
                    ctx.interpolationQuality = .none
                    ctx.draw(cell, in: dst)
                }
                if isMinedTile(grid, Int32(x), Int32(y)) != 0,
                   let mine = tiles.cropping(to: sheetRect(MINE00IMAGE)) {
                    ctx.draw(mine, in: dst)
                }
            }
        }
        return ctx.makeImage()
    }

    private static func sheetRect(_ index: Int32) -> CGRect {
        let tile = 16
        let row = Int(index) >> 4
        let col = Int(index) & 0xF
        return CGRect(x: col * tile, y: row * tile, width: tile, height: tile)
    }

    private static func occupiedBounds(_ state: GameState) -> (minX: Int, minY: Int, maxX: Int, maxY: Int, width: Int, height: Int) {
        var minX = 256, minY = 256, maxX = 0, maxY = 0
        func include(_ x: Int, _ y: Int) {
            if x < minX { minX = x }
            if y < minY { minY = y }
            if x > maxX { maxX = x }
            if y > maxY { maxY = y }
        }
        for y in 0..<256 {
            for x in 0..<256 {
                if state.terrain[x, y] != .sea { include(x, y) }
            }
        }
        for pill in state.pills { include(Int(pill.x), Int(pill.y)) }
        for base in state.bases { include(Int(base.x), Int(base.y)) }
        for start in state.starts { include(Int(start.x), Int(start.y)) }
        minX = max(0, minX - 3)
        minY = max(0, minY - 3)
        maxX = min(256, maxX + 4)
        maxY = min(256, maxY + 4)
        return (minX, minY, maxX, maxY, maxX - minX, maxY - minY)
    }
}
