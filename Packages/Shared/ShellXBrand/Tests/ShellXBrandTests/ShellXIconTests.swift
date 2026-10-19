import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ShellXIcons

@Suite struct ShellXIconTests {
    @Test func mappedSymbolUsesCoolicon() {
        #expect(ShellXIcon.cooliconName(for: "terminal") == "Terminal")
    }

    @Test func mapIsLoadedFromTheBundledJSON() throws {
        let url = try #require(ShellXIcon.bundle.url(forResource: "icon-map", withExtension: "json"))
        let decoded = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        #expect(decoded.count > 200)
        #expect(ShellXIcon.map == decoded)
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

    /// Names later tasks draw directly (title bar, machine groups).
    @Test func cooliconsLaterTasksUseLoad() throws {
        let bundle = ShellXIcon.isCatalogCompiled ? ShellXIcon.bundle : try CompiledCoolicons.bundle()
        for name in [
            "Laptop", "Desktop", "Data", "Mobile", "Link", "Terminal", "Bell_Ring", "Add_Plus",
            "Search_Magnifying_Glass", "Settings", "Circle_Check", "Shield_Check", "Users",
            "Window_Sidebar", "More_Horizontal", "Qr_Code",
        ] {
            #expect(ShellXIcon.loadCoolicon(name, from: bundle) != nil, "\(name)")
        }
    }

    @Test func unmappedUserSymbolFallsBack() { // Review Focus 3
        #expect(ShellXIcon.cooliconName(for: "figure.surfing") == nil)
        #expect(ShellXIcon.nsImage("figure.surfing", accessibilityDescription: nil) != nil)
    }

    /// Review Focus 3: a user-configured SF Symbol the map does not know
    /// renders through SwiftUI as that SF Symbol, never blank.
    @Test @MainActor func unmappedUserSymbolRendersInSwiftUI() throws {
        let rendered = try #require(Rendered(ShellXIcon.image("figure.surfing").font(.system(size: 20))))
        #expect(rendered.visiblePixels > 20)
    }

    @Test func mappedSymbolIsNeverBlank() {
        // Mapped: the coolicon when the catalog is compiled, else the SF
        // Symbol of the same name. Either way an image, never nil.
        let image = ShellXIcon.nsImage("terminal", accessibilityDescription: "Terminal")
        #expect(image != nil)
        #expect(image?.accessibilityDescription == "Terminal")
        #expect(image?.isTemplate == true)
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
            var previousHeight: CGFloat = 0
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
                #expect(coolImage.size.height > previousHeight, "\(cool) grows with the image scale")
                previousHeight = coolImage.size.height
            }
        }
    }

    /// The configured coolicon draws real ink (strokes were outlined to
    /// fills, not dropped), centred in its frame like the SF Symbol.
    @Test @MainActor func cooliconDrawsVisibleCenteredInk() throws {
        let bundle = ShellXIcon.isCatalogCompiled ? ShellXIcon.bundle : try CompiledCoolicons.bundle()
        let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        for name in ["Terminal", "Circle", "Bell_Ring", "Window_Sidebar", "Close_MD"] {
            let image = try #require(ShellXIcon.loadCoolicon(name, from: bundle)?.withSymbolConfiguration(config))
            let rendered = try #require(Rendered(image))
            #expect(rendered.visiblePixels > 40, "\(name)")
            let center = try #require(rendered.inkCenter)
            #expect(abs(center.x - rendered.size.width / 2) < rendered.size.width * 0.2, "\(name)")
            #expect(abs(center.y - rendered.size.height / 2) < rendered.size.height * 0.2, "\(name)")
        }
    }

    /// SwiftUI draws the custom symbol from the compiled catalog and sizes it
    /// with `.font` the way it sizes an SF Symbol.
    @Test @MainActor func swiftUICooliconScalesWithFont() throws {
        let bundle = ShellXIcon.isCatalogCompiled ? ShellXIcon.bundle : try CompiledCoolicons.bundle()
        let small = try #require(Rendered(ShellXIcon.image(coolicon: "Terminal", in: bundle).font(.system(size: 11))))
        let large = try #require(Rendered(ShellXIcon.image(coolicon: "Terminal", in: bundle).font(.system(size: 22))))
        let sf = try #require(Rendered(Image(systemName: "terminal").font(.system(size: 22))))
        #expect(small.visiblePixels > 20)
        #expect(large.size.height > small.size.height * 1.5)
        #expect(abs(large.size.height - sf.size.height) <= 4)
    }

    @Test @MainActor func labelShowsTitleAndIconForEveryTitleType() throws {
        let key = try #require(Rendered(ShellXLabel("Open", icon: "folder").labelStyle(.titleAndIcon)))
        let text = try #require(Rendered(ShellXLabel(String("Open"), icon: "folder").labelStyle(.titleAndIcon)))
        let resource = try #require(Rendered(
            ShellXLabel(LocalizedStringResource("Open"), icon: "folder").labelStyle(.titleAndIcon)
        ))
        let iconOnly = try #require(Rendered(ShellXLabel("Open", icon: "folder").labelStyle(.iconOnly)))
        for label in [key, text, resource] {
            #expect(label.size.width > iconOnly.size.width + 10)
            #expect(label.visiblePixels > iconOnly.visiblePixels)
        }
        #expect(iconOnly.visiblePixels > 20)
    }
}

/// An offscreen render of a view or image, with the ink it drew.
@MainActor
struct Rendered {
    let size: CGSize
    let visiblePixels: Int
    let inkCenter: CGPoint?

    init?(_ view: some View) {
        let renderer = ImageRenderer(content: view.foregroundStyle(.black))
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { return nil }
        self.init(cgImage: cgImage)
    }

    init?(_ image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.init(cgImage: cgImage)
    }

    private init(cgImage: CGImage) {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        var count = 0
        var sumX = 0
        var sumY = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 {
                count += 1
                sumX += x
                sumY += y
            }
        }
        size = CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        visiblePixels = count
        inkCenter = count > 0 ? CGPoint(x: CGFloat(sumX) / CGFloat(count), y: CGFloat(sumY) / CGFloat(count)) : nil
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
