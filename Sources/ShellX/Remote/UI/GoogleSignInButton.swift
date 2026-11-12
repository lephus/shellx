import AppKit
import ShellXRemoteUI
import SwiftUI

/// The "Continue with Google" button, drawn exactly by `GoogleSignInButtonSpec` in Google's Light theme
/// whatever the appearance. The official "G" (image set `GoogleG`, downloaded by `fetch-google-branding.sh`)
/// is shown when it is in the bundle; without it the button is the same shape with the text only.
struct GoogleSignInButton: View {
    typealias Spec = GoogleSignInButtonSpec

    let title: String
    /// Return presses it. Off on the email-first sheet, where Return sends the code; on for the switch sheet.
    var isDefaultAction = true
    let action: () -> Void

    /// The official mark (image set `GoogleG`) is in the app bundle; without it the button is text-only.
    static var hasMark: Bool { NSImage(named: "GoogleG") != nil }

    private static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Spec.cornerRadius, style: .continuous)
        Button(action: action) {
            HStack(spacing: Spec.logoGap) {
                if Self.hasMark {
                    Image("GoogleG")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: Spec.logoSize, height: Spec.logoSize)
                }
                Text(title)
                    .font(Spec.font(isAvailable: { NSFont(name: $0, size: Spec.fontSize) != nil }))
                    .foregroundColor(Self.color(Spec.text))
                    .lineLimit(1)
            }
            .padding(.leading, Spec.leadingPadding)
            .padding(.trailing, Spec.trailingPadding)
            .frame(height: Spec.height)
            .background(shape.fill(Self.color(Spec.fill)))
            .overlay(shape.strokeBorder(Self.color(Spec.stroke), lineWidth: Spec.strokeWidth))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(isDefaultAction ? .defaultAction : nil)
        .accessibilityLabel(title)
    }
}
