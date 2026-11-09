import CoreText
import SwiftUI
import UIKit

/// "Continue with Google" drawn to Google's branding guidelines (https://developers.google.com/identity/branding-guidelines):
/// the Light theme in both appearances (fill #FFFFFF, 1 pt inside stroke #747775, text #1F1F1F), a 44 pt pill, 16 pt before
/// the G, 12 pt between the G and the text, 16 pt after, Google Sans Medium 14/20. Without the `GoogleG` asset the G and
/// its gap are left out (the text-only fallback).
struct GoogleSignInButton: View {
    var busy = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    private static let ink = Color(red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255)
    private static let stroke = Color(red: 0x74 / 255, green: 0x77 / 255, blue: 0x75 / 255)

    /// Google's official "G" (asset `GoogleG`, 20 × 20 pt); nil until the asset is bundled.
    static var mark: UIImage? { UIImage(named: "GoogleG") }

    /// Google Sans Medium 14 pt. `Fonts/GoogleSans.ttf` is Google Fonts' variable Google Sans, whose one PostScript name
    /// is `GoogleSans-Regular`; its named instance "Medium" is `wght` (tag 0x77676874) 500 at `opsz` (tag 0x6F70737A) 18.
    /// Both are set: CoreText would otherwise size `opsz` to the point size (17 at 14 pt, the "Text Medium" style).
    /// The system's medium weight while the font is not bundled.
    static func labelFont() -> UIFont {
        guard let base = UIFont(name: "GoogleSans-Regular", size: 14) else {
            return UIFont.systemFont(ofSize: 14, weight: .medium)
        }
        let variation = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = base.fontDescriptor.addingAttributes([variation: [0x7767_6874: 500, 0x6F70_737A: 18]])
        return UIFont(descriptor: descriptor, size: 14)
    }

    var body: some View {
        Button(action: action) {
            Group {
                if busy {
                    ProgressView().tint(Self.ink)
                } else {
                    HStack(spacing: 0) {
                        if let mark = Self.mark {
                            Image(uiImage: mark)
                                .resizable()
                                .frame(width: 20, height: 20)
                                .accessibilityHidden(true)
                            Spacer().frame(width: 12)
                        }
                        Text(LocalizedStringResource("signin.google"))
                            .font(Font(Self.labelFont()))
                            .foregroundStyle(Self.ink)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().strokeBorder(Self.stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityIdentifier("signin.google")
    }
}
