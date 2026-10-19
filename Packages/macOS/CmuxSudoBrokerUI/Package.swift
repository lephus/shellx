// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CmuxSudoBrokerUI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "CmuxSudoBrokerUI", targets: ["CmuxSudoBrokerUI"]),
    ],
    dependencies: [
        .package(path: "../CmuxSudoBroker"),
        // coolicons behind ShellXIcon (spec §7.4); the CLI never links this package.
        .package(path: "../../Shared/ShellXBrand"),
    ],
    targets: [
        .target(
            name: "CmuxSudoBrokerUI",
            dependencies: [
                "CmuxSudoBroker",
                .product(name: "ShellXIcons", package: "ShellXBrand"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxSudoBrokerUITests",
            dependencies: ["CmuxSudoBrokerUI"]
        ),
    ]
)
