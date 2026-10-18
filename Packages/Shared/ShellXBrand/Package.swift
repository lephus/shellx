// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShellXBrand",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShellXBrand", targets: ["ShellXBrand"]),
        .library(name: "ShellXRemoteCore", targets: ["ShellXRemoteCore"])
    ],
    targets: [
        .target(name: "ShellXBrand"),
        .testTarget(name: "ShellXBrandTests", dependencies: ["ShellXBrand"]),
        .target(name: "ShellXRemoteAtomicsC", publicHeadersPath: "include"),
        .target(name: "ShellXRemoteCore", dependencies: ["ShellXRemoteAtomicsC"]),
        .testTarget(name: "ShellXRemoteCoreTests", dependencies: ["ShellXRemoteCore"])
    ],
    swiftLanguageModes: [.v6]
)
