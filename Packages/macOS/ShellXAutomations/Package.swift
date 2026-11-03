// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ShellXAutomations",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ShellXAutomations",
            targets: ["ShellXAutomations"]
        ),
    ],
    targets: [
        .target(
            name: "ShellXAutomations",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "ShellXAutomationsTests",
            dependencies: [
                "ShellXAutomations",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
