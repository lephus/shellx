// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CmuxSwiftRenderUI",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxSwiftRenderUI",
            targets: ["CmuxSwiftRenderUI"]
        ),
    ],
    dependencies: [
        .package(path: "../CmuxSwiftRender"),
        .package(path: "../CmuxSettings"),
        .package(path: "../CmuxFoundation"),
        // coolicons behind ShellXIcon (spec §7.4); the CLI never links this package.
        .package(path: "../../Shared/ShellXBrand"),
    ],
    targets: [
        .target(
            name: "CmuxSwiftRenderUI",
            dependencies: [
                .product(name: "CmuxSwiftRender", package: "CmuxSwiftRender"),
                .product(name: "CmuxSettings", package: "CmuxSettings"),
                .product(name: "CmuxFoundation", package: "CmuxFoundation"),
                .product(name: "ShellXIcons", package: "ShellXBrand"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "CmuxSwiftRenderUITests",
            dependencies: ["CmuxSwiftRenderUI"]
        ),
        // Dev-only GUI lab for iterating on the reorderable drag interaction
        // without an app build. Run: swift run reorder-lab
        .executableTarget(
            name: "reorder-lab",
            dependencies: ["CmuxSwiftRenderUI"]
        ),
    ]
)
