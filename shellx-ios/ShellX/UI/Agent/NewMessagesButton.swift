import SwiftUI

/// "New messages ↓" over the bottom of an agent's chat: newer entries came while the user read older
/// ones. Tapping it scrolls to the newest.
struct NewMessagesButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(LocalizedStringResource("agent.newMessages"))
            } icon: {
                Image(systemName: "arrow.down")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PrimaryButtonStyle.label)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(PrimaryButtonStyle.fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(LocalizedStringResource("agent.newMessages.hint")))
        .accessibilityIdentifier("agent.newMessages")
    }
}
