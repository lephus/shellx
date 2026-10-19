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
    ],
    targets: [
        .target(name: "ShellXBrand"),
        .target(name: "ShellXIcons", resources: [.process("Resources")]),
        .testTarget(name: "ShellXBrandTests", dependencies: ["ShellXBrand", "ShellXIcons"])
    ],
    swiftLanguageModes: [.v6]
)
