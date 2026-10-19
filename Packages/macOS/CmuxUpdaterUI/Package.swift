// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CmuxUpdaterUI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxUpdaterUI",
            targets: ["CmuxUpdaterUI"]
        ),
    ],
    dependencies: [
        .package(path: "../CmuxFoundation"),
        .package(path: "../CmuxUpdater"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
        // coolicons behind ShellXIcon (spec §7.4); the CLI never links this package.
        .package(path: "../../Shared/ShellXBrand"),
    ],
    targets: [
        .target(
            name: "CmuxUpdaterUI",
            dependencies: [
                "CmuxFoundation",
                "CmuxUpdater",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "ShellXIcons", package: "ShellXBrand"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxUpdaterUITests",
            dependencies: ["CmuxUpdaterUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
