import AppKit
import ShellXIcons

/// Resolves the coolicons names the sidebar models carry ("Laptop",
/// "Desktop", "Data", "Add_Plus", "User_Circle") to template images.
@MainActor
enum ShellXSidebarIcon {
    /// The bundled coolicon (`ShellXIcons`), sized as a template symbol image.
    static func image(named coolicon: String, pointSize: CGFloat) -> NSImage? {
        guard let symbol = ShellXIcon.nsImage(coolicon: coolicon) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let image = symbol.withSymbolConfiguration(configuration) ?? symbol
        image.isTemplate = true
        return image
    }
}
