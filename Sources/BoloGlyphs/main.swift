import BoloGlyphsCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/Generated"

try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func writePNG(_ sheet: RGBASheet, to path: String) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: RGBASheet.size,
        height: RGBASheet.size,
        bitsPerComponent: 8,
        bytesPerRow: RGBASheet.size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "BoloGlyphs", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not create bitmap context"])
    }

    sheet.pixels.withUnsafeBytes { src in
        context.data!.copyMemory(from: src.baseAddress!, byteCount: src.count)
    }

    guard let image = context.makeImage() else {
        throw NSError(domain: "BoloGlyphs", code: 2, userInfo: [NSLocalizedDescriptionKey: "could not create image from context"])
    }

    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "BoloGlyphs", code: 3, userInfo: [NSLocalizedDescriptionKey: "could not create image destination at \(path)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "BoloGlyphs", code: 4, userInfo: [NSLocalizedDescriptionKey: "could not finalize PNG at \(path)"])
    }
}

let sheets = buildSheets()
try writePNG(sheets.tiles, to: outputDir + "/Tiles.png")
try writePNG(sheets.sprites, to: outputDir + "/Sprites.png")
print("Wrote \(outputDir)/Tiles.png and \(outputDir)/Sprites.png")
