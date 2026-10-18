// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShellXBrand",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ShellXBrand", targets: ["ShellXBrand"])],
    targets: [
        .target(name: "ShellXBrand"),
        .testTarget(name: "ShellXBrandTests", dependencies: ["ShellXBrand"])
    ],
    swiftLanguageModes: [.v6]
)
