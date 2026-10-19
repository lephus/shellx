// swift-tools-version: 6.0

import PackageDescription

// `CmuxSentryTelemetry` is the shared (macOS + iOS) privacy and
// transport-telemetry layer. `CmuxSentryScrubbing` is the pure-Foundation
// value scrubber. ShellX links no Sentry SDK (no phone-home), so
// `CmuxSentryReporting` keeps only a no-op `TransportSentryReporter` for the
// composition roots that construct one.
let package = Package(
    name: "CmuxSentryTelemetry",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxSentryScrubbing",
            targets: ["CmuxSentryScrubbing"]
        ),
        .library(
            name: "CmuxSentryReporting",
            targets: ["CmuxSentryReporting"]
        ),
    ],
    dependencies: [
        .package(path: "../CMUXMobileCore"),
    ],
    targets: [
        .target(
            name: "CmuxSentryScrubbing",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .target(
            name: "CmuxSentryReporting",
            dependencies: [
                "CmuxSentryScrubbing",
                "CMUXMobileCore",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxSentryScrubbingTests",
            dependencies: ["CmuxSentryScrubbing"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxSentryReportingTests",
            dependencies: ["CmuxSentryReporting", "CMUXMobileCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
