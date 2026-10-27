import ShellXAppCore
import SwiftUI

/// What the user said or typed, on the right, with the session it went to under it (and a mic when
/// it was spoken).
struct UserMessageBubble: View {
    let text: String
    let target: SessionRef?
    let viaVoice: Bool

    private var targetLabel: String? {
        target.map { "\(AgentLabel(agent: $0.agent).text) · \($0.workspaceTitle)" }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(verbatim: text)
                .textSelection(.enabled)
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

    /// "You: <text>. Spoken. Claude Code · shellx"
    private var accessibilityText: String {
        var parts = ["\(String(localized: "home.sender.you")): \(text)"]
        if viaVoice { parts.append(String(localized: "home.voice")) }
        if let targetLabel { parts.append(targetLabel) }
        return parts.joined(separator: ". ")
    }
}
