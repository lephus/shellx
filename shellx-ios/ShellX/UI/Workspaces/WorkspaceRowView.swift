import ShellXAppCore
import SwiftUI

/// One workspace as a one-line card on the home: its name on the left and its git branch in monospace
/// on the right (the agents in it have their own cards above). The card is not a button itself: the
/// list wraps it in one.
struct WorkspaceRowView: View {
    let row: WorkspaceRow
    /// The Mac is not online: this is its last known list, so the card fades.
    var dimmed = false

    @Environment(\.dynamicTypeSize) private var typeSize

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        line
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.appSurface, in: shape)
            .overlay { shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1) }
            .contentShape(shape)
            .opacity(dimmed ? 0.55 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("workspace.row.\(row.id.workspaceId)")
    }

    /// The name and the branch side by side; under each other at the accessibility text sizes, so
    /// neither breaks inside a word.
    @ViewBuilder private var line: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                title
                branch(minWidth: nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title.layoutPriority(1)
                Spacer(minLength: 0)
                // The name comes first, but a long one still leaves the branch some room.
                branch(minWidth: 72)
            }
        }
    }

    private var title: some View {
        Text(verbatim: row.title)
            .font(.headline)
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .truncationMode(.tail)
    }

    /// The git branch, when the Mac gave one; `minWidth` keeps it from being squeezed out.
    @ViewBuilder private func branch(minWidth: CGFloat?) -> some View {
        if let branch = row.branch, !branch.isEmpty {
            Text(verbatim: branch)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .truncationMode(.middle)
                .frame(minWidth: minWidth, alignment: .trailing)
        }
    }
}
