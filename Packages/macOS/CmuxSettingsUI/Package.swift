// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CmuxSettingsUI",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxSettingsUI",
            targets: ["CmuxSettingsUI"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/CMUXMobileCore"),
        .package(path: "../CmuxFoundation"),
        .package(path: "../CmuxSettings"),
        // coolicons behind ShellXIcon (spec §7.4); the CLI never links this package.
        .package(path: "../../Shared/ShellXBrand"),
    ],
    targets: [
        .target(
            name: "CmuxSettingsUI",
            dependencies: [
                "CMUXMobileCore",
                .product(name: "CmuxFoundation", package: "CmuxFoundation"),
                .product(name: "CmuxSettings", package: "CmuxSettings"),
                .product(name: "ShellXIcons", package: "ShellXBrand"),
            ],
            resources: [
                .process("Resources/Localizable.xcstrings"),
                .copy("Resources/CustomSidebars"),
                .copy("Resources/CustomSidebarTemplatePreviews"),
            ]
        ),
        .testTarget(
            name: "CmuxSettingsUITests",
            dependencies: [
                "CMUXMobileCore",
                "CmuxSettingsUI",
                "CmuxSettings",
                .product(name: "CmuxFoundation", package: "CmuxFoundation"),
                .product(name: "ShellXIcons", package: "ShellXBrand"),
            ]
        ),
    ]
)
