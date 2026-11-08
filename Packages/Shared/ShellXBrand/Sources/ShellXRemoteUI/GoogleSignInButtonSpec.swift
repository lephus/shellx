import SwiftUI

/// Google's custom "Sign in with Google" button rules, Light theme in every appearance
/// (https://developers.google.com/identity/branding-guidelines): white fill, 1 px #747775 stroke inside,
/// #1F1F1F text, 40 pt tall, 4 pt corners, the 20 pt "G" 12 pt from the left edge, 10 pt before the text
/// and 12 pt after it. The "G" itself is Google's own file; this type only holds the numbers.
public struct GoogleSignInButtonSpec: Equatable, Sendable {
    public static let fill: UInt32 = 0xFFFFFF
    public static let stroke: UInt32 = 0x747775
    public static let text: UInt32 = 0x1F1F1F
    public static let height = 40.0
    public static let cornerRadius = 4.0
    public static let strokeWidth = 1.0
    public static let logoSize = 20.0
    public static let leadingPadding = 12.0
    public static let logoGap = 10.0
    public static let trailingPadding = 12.0
    public static let fontSize = 14.0
    public static let lineHeight = 20.0
    public static let fontPostScriptName = "GoogleSans-Medium"

    /// Google Sans Medium 14 when that face is registered, else the system font at 14 medium (licence gate).
    public static func font(isAvailable: (String) -> Bool) -> Font {
        isAvailable(fontPostScriptName)
            ? .custom(fontPostScriptName, size: fontSize)
            : .system(size: fontSize, weight: .medium)
    }
}
