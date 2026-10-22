// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "shellx-link",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ShellXLinkCore", targets: ["ShellXLinkCore"]),
        .library(name: "ShellXLinkRelay", targets: ["ShellXLinkRelay"]),
        .library(name: "ShellXLinkSession", targets: ["ShellXLinkSession"]),
    ],
    targets: [
        .target(name: "ShellXLinkCore"),
        .testTarget(name: "ShellXLinkCoreTests", dependencies: ["ShellXLinkCore"]),
        .target(name: "ShellXLinkRelay"),
        .testTarget(name: "ShellXLinkRelayTests", dependencies: ["ShellXLinkRelay"]),
        .target(name: "ShellXLinkSession", dependencies: ["ShellXLinkCore", "ShellXLinkRelay"]),
        .testTarget(
            name: "ShellXLinkSessionTests",
            dependencies: ["ShellXLinkSession", "ShellXLinkCore", "ShellXLinkRelay"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
