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
        .testTarget(
            name: "BezelbubKitTests",
            dependencies: ["BezelbubKit"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
