// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShellXBrand",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShellXBrand", targets: ["ShellXBrand"]),
        // coolicons behind `ShellXIcon` (asset catalog + map). A separate
        // product so resource-free clients (cmux-cli) never link the icons.
        .library(name: "ShellXIcons", targets: ["ShellXIcons"]),
        .library(name: "ShellXRemoteCore", targets: ["ShellXRemoteCore"]),
        .library(name: "ShellXRemoteUI", targets: ["ShellXRemoteUI"])
    ],
    targets: [
        .target(name: "ShellXBrand"),
        .target(name: "ShellXIcons", resources: [.process("Resources")]),
        .testTarget(name: "ShellXBrandTests", dependencies: ["ShellXBrand", "ShellXIcons"]),
        .target(name: "ShellXRemoteCore"),
        .testTarget(name: "ShellXRemoteCoreTests", dependencies: ["ShellXRemoteCore"]),
        .target(name: "ShellXRemoteUI", dependencies: ["ShellXBrand", "ShellXRemoteCore"]),
        .testTarget(name: "ShellXRemoteUITests", dependencies: ["ShellXRemoteUI", "ShellXBrand", "ShellXRemoteCore"])
    ],
    swiftLanguageModes: [.v6]
)
