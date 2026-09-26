// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BoloKit",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        // Consumed by the `Bolo 2026` app target (Wave 7.1).
        .library(name: "BoloKit", targets: ["BoloKit"]),
        // Host/Join panels, Milestone B (D93/B.0) — exported now that the app target needs it.
        .library(name: "BoloNet", targets: ["BoloNet"]),
        // Build-time sheet generator, invoked from the app's Run Script phase (D72).
        .executable(name: "BoloGlyphs", targets: ["BoloGlyphs"]),
        // Build-time sound generator, invoked from the app's Run Script phase (C.3/D122).
        .executable(name: "BoloSounds", targets: ["BoloSounds"]),
    ],
    targets: [
        .target(name: "BoloKit"),
        .target(
            name: "CXBolo",
            path: "Sources/CXBolo",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-ffp-contract=off"])]
        ),
        .target(name: "BoloNet", dependencies: ["BoloKit"]),
        .target(name: "BoloGlyphsCore", dependencies: ["BoloKit"]),
        .executableTarget(name: "BoloGlyphs", dependencies: ["BoloGlyphsCore"]),
        .target(name: "BoloSoundsCore"),
        .executableTarget(name: "BoloSounds", dependencies: ["BoloSoundsCore"]),
        // Agent-vs-agent soak/anomaly-hunting tool (not shipped game functionality) --
        // `swift run BoloArena` starts a real host+guest game with two control ports two
        // independent Claude agents drive by hand, one seat each.
        .executableTarget(name: "BoloArena", dependencies: ["BoloKit", "BoloNet"]),
        .testTarget(name: "BoloKitTests", dependencies: ["BoloKit", "BoloGlyphsCore", "BoloSoundsCore"]),
        .testTarget(
            name: "DifferentialTests",
            dependencies: ["BoloKit", "BoloNet", "CXBolo"]
        ),
    ]
)
