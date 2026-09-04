import BoloGlyphsCore
import Foundation

// Two modes:
//   BoloGlyphs [<dir>]        - write Tiles.png/Sprites.png (the build-time path, D72)
//   BoloGlyphs icon <dir>     - write the placeholder AppIcon PNGs (run by hand; committed)
let args = Array(CommandLine.arguments.dropFirst())
let iconMode = args.first == "icon"
let outputDir = (iconMode ? args.dropFirst().first : args.first) ?? "Resources/Generated"

try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func writePNG(_ pixels: [UInt8], size: Int, to path: String) throws {
    guard let data = encodePNGData(pixels, size: size) else {
        throw NSError(domain: "BoloGlyphs", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not encode PNG"])
    }
    try data.write(to: URL(fileURLWithPath: path))
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
