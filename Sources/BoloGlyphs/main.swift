import BoloGlyphsCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Two modes:
//   BoloGlyphs [<dir>]        - write Tiles.png/Sprites.png (the build-time path, D72)
//   BoloGlyphs icon <dir>     - write the placeholder AppIcon PNGs (run by hand; committed)
let args = Array(CommandLine.arguments.dropFirst())
let iconMode = args.first == "icon"
let outputDir = (iconMode ? args.dropFirst().first : args.first) ?? "Resources/Generated"

try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func writePNG(_ pixels: [UInt8], size: Int, to path: String) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "BoloGlyphs", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not create bitmap context"])
    }

    pixels.withUnsafeBytes { src in
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

if iconMode {
    for size in appIconPixelSizes {
        let icon = buildAppIcon(size: size)
        try writePNG(icon.pixels, size: icon.size, to: outputDir + "/icon_\(size).png")
    }
    print("Wrote \(appIconPixelSizes.count) AppIcon PNGs to \(outputDir)")
} else {
    let sheets = buildSheets()
    try writePNG(sheets.tiles.pixels, size: RGBASheet.size, to: outputDir + "/Tiles.png")
    try writePNG(sheets.sprites.pixels, size: RGBASheet.size, to: outputDir + "/Sprites.png")
    print("Wrote \(outputDir)/Tiles.png and \(outputDir)/Sprites.png")
}
