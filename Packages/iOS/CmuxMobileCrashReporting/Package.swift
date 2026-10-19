// swift-tools-version: 6.0

import PackageDescription

// `CmuxMobileCrashReporting` is the iOS crash telemetry leaf package. ShellX
// links no Sentry SDK (no phone-home), so it keeps the composition root's
// entry points as no-ops that only purge a stale crash cache.
let package = Package(
    name: "CmuxMobileCrashReporting",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxMobileCrashReporting",
            targets: ["CmuxMobileCrashReporting"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/CMUXMobileCore"),
    ],
    targets: [
        .target(
            name: "CmuxMobileCrashReporting",
            dependencies: [
                "CMUXMobileCore",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxMobileCrashReportingTests",
            dependencies: [
                "CMUXMobileCore",
                "CmuxMobileCrashReporting",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
