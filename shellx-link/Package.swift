// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "shellx-link",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ShellXLinkCore", targets: ["ShellXLinkCore"]),
    ],
    targets: [
        .target(name: "ShellXLinkCore"),
        .testTarget(name: "ShellXLinkCoreTests", dependencies: ["ShellXLinkCore"]),
    ],
    swiftLanguageModes: [.v6]
)
