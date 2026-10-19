// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CmuxCanvasUI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxCanvasUI",
            targets: ["CmuxCanvasUI"]
        ),
    ],
    dependencies: [
        .package(path: "../CmuxCanvas"),
        .package(path: "../CmuxFoundation"),
        // coolicons behind ShellXIcon (spec §7.4); the CLI never links this package.
        .package(path: "../../Shared/ShellXBrand"),
    ],
    targets: [
        .target(
            name: "CmuxCanvasUI",
            dependencies: [
                "CmuxCanvas",
                "CmuxFoundation",
                .product(name: "ShellXIcons", package: "ShellXBrand"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxCanvasUITests",
            dependencies: [
                "CmuxCanvasUI",
            ]
        ),
    ]
)
