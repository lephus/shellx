// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "shellx-link",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ShellXLinkCore", targets: ["ShellXLinkCore"]),
        .library(name: "ShellXLinkRelay", targets: ["ShellXLinkRelay"]),
    ],
    targets: [
        .target(name: "ShellXLinkCore"),
        .testTarget(name: "ShellXLinkCoreTests", dependencies: ["ShellXLinkCore"]),
        .target(name: "ShellXLinkRelay"),
        .testTarget(name: "ShellXLinkRelayTests", dependencies: ["ShellXLinkRelay"]),
    ],
    swiftLanguageModes: [.v6]
)
