import ShellXAppCore
import SwiftUI

/// A ShellX note on the left: what became of a message, or a session that finished. Each note is
/// one fixed sentence with an icon whose colour follows the state colours.
struct HomeNoteRow: View {
    let note: HomeNote
    /// The note opens a screen (a "done" note opens its agent): a chevron at its end says so.
    var showsDisclosure = false

    var body: some View {
        let text = Self.text(for: note)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: UnevenRoundedRectangle(
                topLeadingRadius: 14, bottomLeadingRadius: 4, bottomTrailingRadius: 14, topTrailingRadius: 14))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(String(localized: "root.title")): \(text)"))
        .accessibilityIdentifier("home.note")
    }

    private var icon: String {
        switch note {
        case .sent: return "paperplane.fill"
        case .sendFailed: return "exclamationmark.triangle.fill"
        case .machineOffline: return "wifi.slash"
        case .machineNeedsPairing: return "iphone.slash"
        case .noLiveSession: return "info.circle.fill"
        case .agentFinished: return "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch note {
        case .sent: return Color("AccentText")
        case .sendFailed: return Color("StatusError")
        case .machineOffline, .machineNeedsPairing, .noLiveSession: return Color("StatusIdle")
        case .agentFinished: return Color("StatusDone")
        }
    }

    /// The note's sentence ("Sent to Claude Code in shellx.").
    static func text(for note: HomeNote) -> String {
        switch note {
        case let .sent(ref):
            return String(localized: "home.note.sent \(agent(ref)) \(ref.workspaceTitle)")
        case let .sendFailed(ref, failure):
            switch failure {
            case .notFound: return String(localized: "home.note.notFound \(agent(ref)) \(ref.workspaceTitle)")
            case .ended: return String(localized: "home.note.ended \(agent(ref)) \(ref.workspaceTitle)")
            case .busy: return String(localized: "home.note.busy \(agent(ref)) \(ref.workspaceTitle)")
            case .failed: return String(localized: "home.note.failed \(agent(ref)) \(ref.workspaceTitle)")
            case .noAnswer: return String(localized: "home.note.noAnswer \(agent(ref)) \(ref.workspaceTitle)")
            case .attachmentsUnsupported:
                return String(localized: "home.note.attachmentsUnsupported \(agent(ref)) \(ref.workspaceTitle)")
            }
        case let .machineOffline(machineName):
            return String(localized: "home.note.offline \(machineName)")
        case let .machineNeedsPairing(machineName):
            return String(localized: "home.note.needsPairing \(machineName)")
        case .noLiveSession:
            return String(localized: "home.note.noLiveSession")
        case let .agentFinished(ref, summary?):
            return String(localized: "home.note.finished \(agent(ref)) \(ref.workspaceTitle) \(summary)")
        case let .agentFinished(ref, nil):
            return String(localized: "home.note.finished.noSummary \(agent(ref)) \(ref.workspaceTitle)")
        }
    }

    private static func agent(_ ref: SessionRef) -> String { AgentLabel(agent: ref.agent).text }
}
