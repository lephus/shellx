// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CmuxAppKitSupportUI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxAppKitSupportUI",
            targets: ["CmuxAppKitSupportUI"]
        ),
    ],
    dependencies: [
        .package(path: "../CmuxFoundation"),
        .package(path: "../CmuxWorkspaces"),
        // ShellX look tokens (sidebar tint default).
        .package(path: "../../Shared/ShellXBrand"),
    ],
    targets: [
        .target(
            name: "CmuxAppKitSupportUI",
            dependencies: [
                "CmuxFoundation",
                "CmuxWorkspaces",
                .product(name: "ShellXBrand", package: "ShellXBrand"),
                .product(name: "ShellXIcons", package: "ShellXBrand"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxAppKitSupportUITests",
            dependencies: [
                "CmuxAppKitSupportUI",
                .product(name: "ShellXIcons", package: "ShellXBrand"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
