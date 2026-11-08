// swift-tools-version: 6.0
import PackageDescription

// The ShellX iOS app's logic, tested with `swift test` on the Mac (no simulator needed).
// Depends only on the local MIT package shellx-link and Apple frameworks; see
// scripts/shellx/check-ios-license.sh for the licence boundary.
let package = Package(
    name: "ShellXAppCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ShellXAppCore", targets: ["ShellXAppCore"]),
        .library(name: "ShellXDemo", targets: ["ShellXDemo"]),
        .library(name: "ShellXAppTestSupport", targets: ["ShellXAppTestSupport"]),
    ],
    dependencies: [
        .package(path: "../../../shellx-link"),
    ],
    targets: [
        .target(
            name: "ShellXAppCore",
            dependencies: [
                .product(name: "ShellXLinkCore", package: "shellx-link"),
                .product(name: "ShellXLinkRelay", package: "shellx-link"),
                .product(name: "ShellXLinkSession", package: "shellx-link"),
                .product(name: "ShellXLinkAccount", package: "shellx-link"),
            ]
        ),
        // The in-app demo ("Try without an account", S1 §6.6): Macs running inside the app, a relay and a secret store
        // that never leave memory. Ships in Release.
        .target(
            name: "ShellXDemo",
            dependencies: [
                "ShellXAppCore",
                .product(name: "ShellXLinkCore", package: "shellx-link"),
                .product(name: "ShellXLinkRelay", package: "shellx-link"),
                .product(name: "ShellXLinkSession", package: "shellx-link"),
                .product(name: "ShellXLinkAccount", package: "shellx-link"),
            ]
        ),
        // Fakes for tests and previews; Release.xcconfig keeps it out of the App Store build.
        .target(
            name: "ShellXAppTestSupport",
            dependencies: [
                "ShellXAppCore",
                "ShellXDemo",
                .product(name: "ShellXLinkCore", package: "shellx-link"),
                .product(name: "ShellXLinkRelay", package: "shellx-link"),
                .product(name: "ShellXLinkSession", package: "shellx-link"),
                .product(name: "ShellXLinkAccount", package: "shellx-link"),
            ]
        ),
        .testTarget(name: "ShellXAppCoreTests", dependencies: ["ShellXAppCore", "ShellXAppTestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
