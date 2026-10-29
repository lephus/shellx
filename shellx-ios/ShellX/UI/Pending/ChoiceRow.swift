import SwiftUI

/// A checklist row: its text, and a checkmark when chosen (the row's selected trait tells
/// VoiceOver; the mark is hidden from it). At least 44 pt tall, tappable across its width.
struct ChoiceRow<Content: View>: View {
    let selected: Bool
    let content: Content

    init(selected: Bool, @ViewBuilder content: () -> Content) {
        self.selected = selected
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color("AccentText"))
                .opacity(selected ? 1 : 0)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
