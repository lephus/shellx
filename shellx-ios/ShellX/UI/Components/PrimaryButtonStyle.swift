import SwiftUI

/// The primary button: a #60a5fa fill with a #0b1220 label (white on that blue is only about 2.5:1).
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    private static let fill = Color(red: 0x60 / 255, green: 0xA5 / 255, blue: 0xFA / 255)
    private static let label = Color(red: 0x0B / 255, green: 0x12 / 255, blue: 0x20 / 255)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Self.label)
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .background(Self.fill, in: RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}
