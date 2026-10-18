// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CmuxFeedback",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxFeedback",
            targets: ["CmuxFeedback"]
        ),
    ],
    dependencies: [
        .package(path: "../CmuxFoundation"),
        .package(path: "../../Shared/ShellXBrand"),
    ],
    targets: [
        .target(
            name: "CmuxFeedback",
            dependencies: [
                "CmuxFoundation",
                .product(name: "ShellXBrand", package: "ShellXBrand"),
            ],
            resources: [
                // Folded from CmuxFeedbackUI: the composer's localized strings.
                .process("ComposerUI/Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxFeedbackTests",
            dependencies: ["CmuxFeedback"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
