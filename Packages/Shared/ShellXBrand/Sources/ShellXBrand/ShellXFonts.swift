import AppKit
import SwiftUI

/// ShellX display type (spec §7.4, "Chữ"): Space Grotesk for large titles
/// and the wordmark, like shellx.pro. Interface text stays on the system
/// font.
///
/// The app bundles `Resources/Fonts/SpaceGrotesk[wght].ttf` (SIL OFL 1.1,
/// `OFL.txt` beside it) and registers it through `ATSApplicationFontsPath`.
public enum ShellXFonts {
    /// Family name of the bundled variable font.
    public static let familyName = "Space Grotesk"

    /// Space Grotesk at `size` and `weight`, or the system font at the same
    /// size and weight when the family is not installed.
    public static func display(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        display(size: size, weight: weight, isFamilyAvailable: isFamilyAvailable)
    }

    static func display(
        size: CGFloat,
        weight: Font.Weight,
        isFamilyAvailable: (String) -> Bool
    ) -> Font {
        guard isFamilyAvailable(familyName) else {
            return .system(size: size, weight: weight)
        }
        return .custom(familyName, size: size).weight(weight)
    }

    /// Whether `family` is registered with the font manager.
    static func isFamilyAvailable(_ family: String) -> Bool {
        NSFontManager.shared.availableMembers(ofFontFamily: family) != nil
    }
}
