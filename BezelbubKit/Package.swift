// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BezelbubKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "BezelbubKit", targets: ["BezelbubKit"]),
        // Video framing lives in its own product so consumers that only frame
        // stills (e.g. the share extension) don't pull in AVFoundation code.
        .library(name: "BezelbubVideoKit", targets: ["BezelbubVideoKit"]),
        .executable(name: "bezelbub", targets: ["bezelbub"]),
    ],
    dependencies: [
        // Only the `bezelbub` CLI uses this; it is not linked into the
        // library, so the apps never pull ArgumentParser into their binary.
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "BezelbubKit",
            // Bezel/mask PNGs and the precomputed regions map are served to every
            // consumer (macOS app, iOS app, share extension, and the future CLI)
            // through Bundle.module. .copy preserves the Bezels/ and Masks/ folder
            // structure that ScreenRegionDetector looks up by directory name.
            resources: [
                .copy("Resources/Bezels"),
                .copy("Resources/Masks"),
                .copy("Resources/screen-regions.json"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .target(
            name: "BezelbubVideoKit",
            dependencies: ["BezelbubKit"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .executableTarget(
            name: "bezelbub",
            dependencies: [
                "BezelbubKit",
                "BezelbubVideoKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "BezelbubKitTests",
            dependencies: ["BezelbubKit", "BezelbubVideoKit"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
