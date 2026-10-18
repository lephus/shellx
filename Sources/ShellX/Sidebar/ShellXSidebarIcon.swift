import AppKit

/// Resolves the coolicons names the sidebar models carry ("Laptop",
/// "Desktop", "Data", "Add_Plus") to template images.
// ShellX: swap for ShellXIcon/ShellXFonts/ShellXLogo after W1 Tasks 7-9 merge
@MainActor
enum ShellXSidebarIcon {
    private static let symbolFallbacks: [String: String] = [
        "Laptop": "laptopcomputer",
        "Desktop": "desktopcomputer",
        "Data": "server.rack",
        "Add_Plus": "plus",
    ]

    /// The bundled coolicon when the asset exists, else an SF Symbol stand-in.
    static func image(named coolicon: String, pointSize: CGFloat) -> NSImage? {
        if let asset = NSImage(named: coolicon) {
            let image = (asset.copy() as? NSImage) ?? asset
            image.size = NSSize(width: pointSize, height: pointSize)
            image.isTemplate = true
            return image
        }
        guard let symbolName = symbolFallbacks[coolicon],
              let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let image = symbol.withSymbolConfiguration(configuration) ?? symbol
        image.isTemplate = true
        return image
    }
}
