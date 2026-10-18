// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShellXBrand",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShellXBrand", targets: ["ShellXBrand"]),
        .library(name: "ShellXRemoteCore", targets: ["ShellXRemoteCore"]),
        .library(name: "ShellXRemoteUI", targets: ["ShellXRemoteUI"])
    ],
    targets: [
        .target(name: "ShellXBrand"),
        .testTarget(name: "ShellXBrandTests", dependencies: ["ShellXBrand"]),
        .target(name: "ShellXRemoteCore"),
        .testTarget(name: "ShellXRemoteCoreTests", dependencies: ["ShellXRemoteCore"]),
        .target(name: "ShellXRemoteUI", dependencies: ["ShellXBrand", "ShellXRemoteCore"]),
        .testTarget(name: "ShellXRemoteUITests", dependencies: ["ShellXRemoteUI", "ShellXBrand", "ShellXRemoteCore"])
    ],
    swiftLanguageModes: [.v6]
)
