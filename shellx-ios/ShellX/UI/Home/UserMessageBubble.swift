import ShellXAppCore
import SwiftUI

/// What the user said or typed, on the right, with the session it went to under it (and a mic when
/// it was spoken). A message with attachments says how many under its text ("📎 2 files"); one of
/// attachments only shows just that line.
struct UserMessageBubble: View {
    let text: String
    let target: SessionRef?
    let viaVoice: Bool
    /// The names of the photos and files it carried; nil or empty when none.
    var attachments: [String]? = nil

    private var targetLabel: String? {
        target.map { "\(AgentLabel(agent: $0.agent).text) · \($0.workspaceTitle)" }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                if !text.isEmpty {
                    Text(verbatim: text)
                        .textSelection(.enabled)
                }
                if attachmentCount > 0 {
                    Text(verbatim: Self.attachmentLine(attachmentCount))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Color("BubbleMine"),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 14, bottomLeadingRadius: 14, bottomTrailingRadius: 4, topTrailingRadius: 14))
            if targetLabel != nil || viaVoice {
                HStack(spacing: 4) {
                    if viaVoice { Image(systemName: "mic.fill") }
                    if let targetLabel { Text(verbatim: targetLabel) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityIdentifier("home.userMessage")
    }

    private var attachmentCount: Int { attachments?.count ?? 0 }

    /// "📎 2 files", in the app's language.
    static func attachmentLine(_ count: Int) -> String {
        String(localized: "home.attachments \(count)")
    }

    /// "You: <text>. 📎 2 files. Spoken. Claude Code · shellx"
    private var accessibilityText: String {
        let you = String(localized: "home.sender.you")
        var parts = [text.isEmpty ? you : "\(you): \(text)"]
        if attachmentCount > 0 { parts.append(Self.attachmentLine(attachmentCount)) }
        if viaVoice { parts.append(String(localized: "home.voice")) }
        if let targetLabel { parts.append(targetLabel) }
        return parts.joined(separator: ". ")
    }
}
