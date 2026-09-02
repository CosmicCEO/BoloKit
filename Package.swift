// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "BoloKit",
    platforms: [
        .macOS(.v26)
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
        .executableTarget(name: "BoloGlyphs"),
        .testTarget(name: "BoloKitTests", dependencies: ["BoloKit"]),
        .testTarget(
            name: "DifferentialTests",
            dependencies: ["BoloKit", "BoloNet", "CXBolo"]
        ),
    ]
)
