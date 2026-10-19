// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CmuxMobileHost",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxMobileHost",
            targets: ["CmuxMobileHost"]
        ),
    ],
    dependencies: [
        .package(path: "../CmuxFoundation"),
        .package(path: "../../Shared/CMUXMobileCore"),
        .package(path: "../../Shared/CmuxAgentChat"),
        // coolicons behind ShellXIcon (spec §7.4); the CLI never links this package.
        .package(path: "../../Shared/ShellXBrand"),
    ],
    targets: [
        .target(
            name: "CmuxMobileHost",
            dependencies: [
                .product(name: "CmuxFoundation", package: "CmuxFoundation"),
                .product(name: "CMUXMobileCore", package: "CMUXMobileCore"),
                .product(name: "CmuxAgentChat", package: "CmuxAgentChat"),
                .product(name: "ShellXIcons", package: "ShellXBrand"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxMobileHostTests",
            dependencies: ["CmuxMobileHost"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
