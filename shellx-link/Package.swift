// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "shellx-link",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ShellXLinkCore", targets: ["ShellXLinkCore"]),
        .library(name: "ShellXLinkRelay", targets: ["ShellXLinkRelay"]),
        .library(name: "ShellXLinkSession", targets: ["ShellXLinkSession"]),
        .library(name: "ShellXLinkAccount", targets: ["ShellXLinkAccount"]),
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
        // The phone side of the ShellX account: login, pairing and the relay connector.
        .target(
            name: "ShellXLinkAccount",
            dependencies: ["ShellXLinkCore", "ShellXLinkRelay", "ShellXLinkSession"]
        ),
        .testTarget(
            name: "ShellXLinkAccountTests",
            dependencies: ["ShellXLinkAccount", "ShellXLinkCore", "ShellXLinkRelay", "ShellXLinkSession"]
        ),
        // Plays the phone in the P1 spike; see Sources/shellx-link-probe/main.swift.
        .executableTarget(
            name: "shellx-link-probe",
            dependencies: ["ShellXLinkSession", "ShellXLinkCore", "ShellXLinkRelay", "ShellXLinkAccount"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
