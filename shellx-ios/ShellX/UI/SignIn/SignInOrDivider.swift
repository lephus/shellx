import SwiftUI

/// A hairline, "or" in footnote grey, a hairline: between Send code and the Google and Apple buttons. Only the word
/// is read out.
struct SignInOrDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 12) {
            hairline
            Text(LocalizedStringResource("signin.email.or"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            hairline
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("signin.email.or")
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(maxWidth: .infinity)
            .frame(height: 1 / max(1, displayScale))
            .accessibilityHidden(true)
    }
}
