// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "BoloKit",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        // Consumed by the `Bolo 2026` app target (Wave 7.1). `BoloNet` is deliberately not
        // exported — the v1 slice is single-process (D73); revisit at Milestone B.
        .library(name: "BoloKit", targets: ["BoloKit"]),
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
