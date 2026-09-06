import BoloSoundsCore
import Foundation

// BoloSounds [<dir>] - write all 24 named .aiff sound effects (the build-time path, D122/C.3)
let args = Array(CommandLine.arguments.dropFirst())
let outputDir = args.first ?? "Resources/Generated"

try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let sounds = buildSounds()
for name in allSoundNames {
    guard let buffer = sounds[name] else {
        throw NSError(domain: "BoloSounds", code: 1, userInfo: [NSLocalizedDescriptionKey: "buildSounds() has no buffer for \(name)"])
    }
    let url = URL(fileURLWithPath: outputDir + "/\(name).aiff")
    try AIFFCodec.write(buffer, to: url)
}
print("Wrote \(allSoundNames.count) .aiff files to \(outputDir)")
