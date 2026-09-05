// swift-tools-version: 6.4
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
        .testTarget(name: "BoloKitTests", dependencies: ["BoloKit", "BoloGlyphsCore"]),
        .testTarget(
            name: "DifferentialTests",
            dependencies: ["BoloKit", "BoloNet", "CXBolo"]
        ),
    ]
)
