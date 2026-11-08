import SwiftUI

/// The page of a shell chip on a Mac whose ShellX shows no terminals (no `terminal_view`): it asks for an
/// update of ShellX on the Mac, in the place the terminal would have.
struct ShellPanePlaceholder: View {
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(LocalizedStringResource("terminal.needsUpdate"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appSurface, in: shape)
        .overlay { shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1) }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workspace.shell.placeholder")
    }
}
