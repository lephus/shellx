import SwiftUI

/// A secondary button next to a `PrimaryButtonStyle` one: the same shape and height, a soft tint of
/// `color` behind a label in that colour (no gradient, no border).
struct SecondaryButtonStyle: ButtonStyle {
    var color = Color("AccentText")

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
