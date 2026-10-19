import AppKit
import SwiftUI

/// ShellX's icons: coolicons v4.1 (CC BY 4.0, "coolicons by Kryston
/// Schwarze") behind the SF Symbol names the app's call sites spell (spec
/// §7.4).
///
/// Call sites keep passing the SF Symbol name they used before ShellX. The
/// bundled `icon-map.json` turns it into the coolicon drawn instead; the
/// coolicons ship as SF Symbols custom symbols (`Coolicons.xcassets`), so they
/// scale with `.font`, `.imageScale` and `NSImage.SymbolConfiguration` and
/// render as templates exactly like the SF Symbols they replace.
///
/// A name the map does not know comes from user configuration (custom
/// commands, workspace group icons, `sidebar.compactStatusIcons`, custom
/// sidebars) and is drawn as the SF Symbol of that name, so a configured
/// symbol never disappears.
public enum ShellXIcon {
    /// `{ "<sf.symbol.name>": "<Coolicon_Name>" }` for every SF Symbol name
    /// the app spells, from the bundled `icon-map.json`.
    public static let map: [String: String] = loadMap()

    /// The coolicon drawn for `sfSymbol`, or nil when it is not mapped (a
    /// user-supplied name, drawn as that SF Symbol).
    public static func cooliconName(for sfSymbol: String) -> String? {
        map[sfSymbol]
    }

    /// `sfSymbol`'s coolicon as a symbol image, or `Image(systemName:)` when
    /// the name is not mapped.
    public static func image(_ sfSymbol: String) -> Image {
        if isCatalogCompiled, let name = map[sfSymbol] {
            return image(coolicon: name, in: bundle)
        }
        return Image(systemName: sfSymbol)
    }

    /// A coolicon by its own name (`Terminal`, `Bell_Ring`, ...).
    public static func image(coolicon name: String) -> Image {
        if !isCatalogCompiled, let sfSymbol = sfSymbolByCoolicon[name] {
            return Image(systemName: sfSymbol)
        }
        return image(coolicon: name, in: bundle)
    }

    /// `sfSymbol`'s coolicon as a template symbol image (a new instance on
    /// every call, safe to configure), or the SF Symbol of that name when it
    /// is not mapped; nil only when neither exists.
    public static func nsImage(_ sfSymbol: String, accessibilityDescription: String?) -> NSImage? {
        if let name = map[sfSymbol], let image = nsImage(coolicon: name) {
            image.accessibilityDescription = accessibilityDescription
            return image
        }
        return NSImage(systemSymbolName: sfSymbol, accessibilityDescription: accessibilityDescription)
    }

    /// A coolicon by its own name as a template symbol image (a new instance
    /// on every call).
    public static func nsImage(coolicon name: String) -> NSImage? {
        guard isCatalogCompiled else {
            return sfSymbolByCoolicon[name].flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        }
        return loadCoolicon(name, from: bundle)
    }

    // MARK: - Bundle

    /// The `ShellXIcons` resource bundle (asset catalog + map).
    static var bundle: Bundle { .module }

    /// Xcode compiles `Coolicons.xcassets` into `Assets.car`. Command-line
    /// SwiftPM (`swift build`, `swift test` of packages that link this one)
    /// copies the catalog uncompiled; then mapped names draw their SF Symbol
    /// so package tests and previews still show an icon.
    static let isCatalogCompiled: Bool = bundle.url(forResource: "Assets", withExtension: "car") != nil

    /// SwiftUI would read the asset name ("Bell_Ring") to VoiceOver; label it
    /// "Bell Ring" instead, as the SF Symbol it replaces had a spoken label.
    static func image(coolicon name: String, in bundle: Bundle) -> Image {
        Image(name, bundle: bundle, label: Text(verbatim: spokenNames[name] ?? spokenName(name)))
    }

    private static let spokenNames: [String: String] = Dictionary(
        uniqueKeysWithValues: Set(map.values).map { ($0, spokenName($0)) }
    )

    private static func spokenName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
    }

    static func loadCoolicon(_ name: String, from bundle: Bundle) -> NSImage? {
        guard let image = NSImage(symbolName: name, bundle: bundle, variableValue: 1) else { return nil }
        image.isTemplate = true
        return image
    }

    /// One SF Symbol per coolicon (the first by name), for command-line
    /// builds where the catalog is not compiled.
    private static let sfSymbolByCoolicon: [String: String] = map.keys.sorted().reduce(into: [:]) { result, sf in
        if let name = map[sf], result[name] == nil { result[name] = sf }
    }

    private static func loadMap() -> [String: String] {
        guard let url = bundle.url(forResource: "icon-map", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            assertionFailure("ShellXIcons: icon-map.json is missing or invalid")
            return [:]
        }
        return map
    }
}
