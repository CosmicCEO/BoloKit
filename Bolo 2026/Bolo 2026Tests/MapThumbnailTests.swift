import CoreGraphics
import Foundation
import Testing
import BoloKit
@testable import Bolo_2026

struct MapThumbnailTests {
    @Test func garbageBytesYieldNoImage() {
        let tiles = MapThumbnail.loadTiles()
        guard let tiles else {
            Issue.record("Tiles.png missing from test host")
            return
        }
        #expect(MapThumbnail.makeImage(from: [0, 1, 2, 3], tiles: tiles) == nil)
    }

    @Test func defaultMapThumbnailIs256AndNotFlat() throws {
        let tiles = try #require(MapThumbnail.loadTiles())
        let image = try #require(MapThumbnail.makeImage(from: defaultMapFileBytes, tiles: tiles))
        #expect(image.width == 256)
        #expect(image.height == 256)

        let bytesPerPixel = 4
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: 256 * 256 * bytesPerPixel)
        defer { data.deallocate() }
        guard let ctx = CGContext(
            data: data, width: 256, height: 256,
            bitsPerComponent: 8, bytesPerRow: 256 * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("could not create readback context")
            return
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256))
        let first = (data[0], data[1], data[2])
        var sawOther = false
        for i in stride(from: 0, to: 256 * 256, by: 17) {
            let o = i * bytesPerPixel
            if (data[o], data[o + 1], data[o + 2]) != first {
                sawOther = true
                break
            }
        }
        #expect(sawOther, "thumbnail should show land against sea, not a flat fill")
    }

    @Test func usaMapThumbnailIs256AndNotFlat() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/U.S.A.map")
        let bytes = Array(try Data(contentsOf: url))
        let tiles = try #require(MapThumbnail.loadTiles())
        let image = try #require(MapThumbnail.makeImage(from: bytes, tiles: tiles))
        #expect(image.width == 256)
        #expect(image.height == 256)
    }
}
