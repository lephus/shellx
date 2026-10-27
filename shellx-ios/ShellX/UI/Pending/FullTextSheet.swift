import ShellXAppCore
import ShellXLinkCore
import SwiftUI

/// Everything a request's preview holds, in a scrolling sheet ("Show more" on a card): each field
/// of a tool's input, or the text as it came. Display only; selectable for copying.
struct FullTextSheet: View {
    let item: PendingItem
    let close: () -> Void

    private var title: String {
        if let tool = item.toolName, !tool.isEmpty { return tool }
        return String(localized: "pending.fullText.title")
    }

    private var raw: String {
        item.toolInputPreview ?? item.previewText ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let fields = item.previewFields {
                        ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: field.key)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                monospaced(field.value)
                            }
                        }
                    } else {
                        monospaced(raw)
                    }
                    if PendingItem.previewMayBeCut(raw) {
                        CutNotice()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close"), action: close)
                        .accessibilityIdentifier("pending.close")
                }
            }
        }
    }

    private func monospaced(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
