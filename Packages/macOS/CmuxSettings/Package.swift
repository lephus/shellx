// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CmuxSettings",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxSettings",
            targets: ["CmuxSettings"]
        ),
    ],
    dependencies: [
        .package(path: "../CmuxFoundation"),
        .package(path: "../CmuxCore"),
        // ShellX look tokens (sidebar tint default).
        .package(path: "../../Shared/ShellXBrand"),
    ],
    targets: [
        .target(
            name: "CmuxSettings",
            dependencies: [
                .product(name: "CmuxFoundation", package: "CmuxFoundation"),
                .product(name: "CmuxCore", package: "CmuxCore"),
                .product(name: "ShellXBrand", package: "ShellXBrand"),
            ],
            resources: [
                .copy("Resources/CustomSidebarTemplates"),
            ]
        ),
        .testTarget(
            name: "CmuxSettingsTests",
            dependencies: ["CmuxSettings"]
        ),
    ]
)
