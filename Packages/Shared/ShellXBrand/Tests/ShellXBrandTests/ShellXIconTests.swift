import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ShellXIcons

@Suite struct ShellXIconTests {
    @Test func mappedSymbolUsesCoolicon() {
        #expect(ShellXIcon.cooliconName(for: "terminal") == "Terminal")
    }

    /// Xcode builds compile `Coolicons.xcassets` into the module bundle, so
    /// `nsImage(coolicon:)` loads straight from it. `swift test` on the
    /// command line copies the catalog uncompiled; then every mapped
    /// coolicon is loaded from the same catalog compiled with `actool`.
    @Test func everyMappedCooliconExists() throws {
        if ShellXIcon.isCatalogCompiled {
            for (_, name) in ShellXIcon.map {
                #expect(ShellXIcon.nsImage(coolicon: name) != nil, "\(name)")
            }
            return
        }
        let bundle = try CompiledCoolicons.bundle()
        for (_, name) in ShellXIcon.map {
            #expect(ShellXIcon.loadCoolicon(name, from: bundle) != nil, "\(name)")
        }
    }

    @Test func unmappedUserSymbolFallsBack() { // Review Focus 3
        #expect(ShellXIcon.cooliconName(for: "figure.surfing") == nil)
        #expect(ShellXIcon.nsImage("figure.surfing", accessibilityDescription: nil) != nil)
    }

    @Test func mappedSymbolIsNeverBlank() {
        // Mapped: the coolicon when the catalog is compiled, else the SF
        // Symbol of the same name. Either way an image, never nil.
        let image = ShellXIcon.nsImage("terminal", accessibilityDescription: "Terminal")
        #expect(image != nil)
        #expect(image?.accessibilityDescription == "Terminal")
        #expect(ShellXIcon.nsImage("not.a.symbol.anywhere", accessibilityDescription: nil) == nil)
    }

    @Test func returnedImagesAreIndependentCopies() throws {
        let first = try #require(ShellXIcon.nsImage("folder", accessibilityDescription: nil))
        first.size = NSSize(width: 99, height: 99)
        first.isTemplate = false
        let second = try #require(ShellXIcon.nsImage("folder", accessibilityDescription: nil))
        #expect(second.size != NSSize(width: 99, height: 99))
        #expect(second.isTemplate)
    }

    @Test func mapCoversCommonAppSymbols() {
        let required = [
            "terminal": "Terminal", "bell": "Bell", "gearshape": "Settings",
            "magnifyingglass": "Search_Magnifying_Glass", "plus": "Add_Plus",
            "sidebar.left": "Window_Sidebar", "ellipsis": "More_Horizontal",
            "laptopcomputer": "Laptop", "desktopcomputer": "Desktop", "iphone": "Mobile",
            "link": "Link", "qrcode": "Qr_Code",
        ]
        for (sf, cool) in required {
            #expect(ShellXIcon.cooliconName(for: sf) == cool, "\(sf)")
        }
    }

    /// Custom symbols size like the SF Symbols they replace: same point size
    /// configuration, height within a few points, and every image scale.
    @Test func cooliconsSizeLikeSFSymbols() throws {
        let bundle = ShellXIcon.isCatalogCompiled ? ShellXIcon.bundle : try CompiledCoolicons.bundle()
        for (sf, cool) in [("terminal", "Terminal"), ("circle", "Circle"), ("bell", "Bell"), ("folder", "Folder")] {
            for scale in [NSImage.SymbolScale.small, .medium, .large] {
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular, scale: scale)
                let sfImage = try #require(
                    NSImage(systemSymbolName: sf, accessibilityDescription: nil)?.withSymbolConfiguration(config)
                )
                let coolImage = try #require(
                    ShellXIcon.loadCoolicon(cool, from: bundle)?.withSymbolConfiguration(config), "\(cool)"
                )
                #expect(coolImage.isTemplate)
                #expect(abs(coolImage.size.height - sfImage.size.height) <= 4, "\(cool) \(scale.rawValue)")
                #expect(coolImage.size.width > 4 && coolImage.size.width <= sfImage.size.width + 4, "\(cool)")
            }
        }
    }

    @Test @MainActor func labelAcceptsTheSameTitleTypesAsLabel() {
        _ = ShellXLabel("Open", icon: "folder")
        _ = ShellXLabel(String("Open"), icon: "folder")
        _ = ShellXLabel(LocalizedStringResource("Open"), icon: "folder")
        _ = ShellXIcon.image("folder")
        _ = ShellXIcon.image(coolicon: "Folder")
    }
}

/// Compiles the module bundle's uncompiled `Coolicons.xcassets` with actool
/// once per test process (command-line SwiftPM copies catalogs verbatim).
enum CompiledCoolicons {
    private static let compiled: Result<Bundle, any Error> = Result { try compile() }

    static func bundle() throws -> Bundle { try compiled.get() }

    private static func compile() throws -> Bundle {
        guard let catalog = ShellXIcon.bundle.url(forResource: "Coolicons", withExtension: "xcassets") else {
            throw CompileError.catalogMissing
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("shellx-coolicons-\(ProcessInfo.processInfo.processIdentifier).bundle")
        let resources = root.appendingPathComponent("Contents/Resources")
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "pro.shellx.coolicons.tests", "CFBundlePackageType": "BNDL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Contents/Info.plist"))
        let actool = Process()
        actool.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        actool.arguments = [
            "actool", catalog.path, "--compile", resources.path, "--platform", "macosx",
            "--minimum-deployment-target", "14.0", "--errors", "--warnings",
            "--output-format", "human-readable-text",
        ]
        actool.standardOutput = FileHandle.nullDevice
        try actool.run()
        actool.waitUntilExit()
        guard actool.terminationStatus == 0,
              FileManager.default.fileExists(atPath: resources.appendingPathComponent("Assets.car").path),
              let bundle = Bundle(url: root) else {
            throw CompileError.actoolFailed(actool.terminationStatus)
        }
        return bundle
    }

    enum CompileError: Error { case catalogMissing, actoolFailed(Int32) }
}
