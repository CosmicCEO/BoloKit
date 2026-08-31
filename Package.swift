// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XBolo",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .target(name: "BoloCore"),
        .target(name: "BoloNet", dependencies: ["BoloCore"]),
        .executableTarget(name: "BoloGlyphs"),
        .testTarget(name: "BoloCoreTests", dependencies: ["BoloCore"]),
        .testTarget(name: "DifferentialTests", dependencies: ["BoloCore"]),
    ]
)
