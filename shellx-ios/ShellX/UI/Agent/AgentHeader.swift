import ShellXAppCore
import SwiftUI

/// The top of an agent's screen, under the workspace in the navigation bar: "Claude Code · MacBook
/// Pro", then the state dot and its words ("Running for 4 minutes", "Needs you", "Mac offline").
/// A session the Mac no longer has says so.
struct AgentHeader: View {
    /// "Claude Code · MacBook Pro".
    let place: String
    /// The session's state as of now; nil when the Mac does not list it.
    let row: AgentStatusRow?
    let gone: Bool
    let offline: Bool

    var body: some View {
        let status = Self.status(row: row, gone: gone, offline: offline)
        // One line when both fit, otherwise the state under the place (never cut).
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                placeText.lineLimit(1)
                Spacer(minLength: 8)
                stateText(status).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 4) {
                placeText
                stateText(status)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [place, status.text].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityIdentifier("agent.header")
    }

    private var placeText: some View {
        Text(verbatim: place)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private func stateText(_ status: (text: String?, color: Color?)) -> some View {
        if let text = status.text {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                StatusDot(color: status.color ?? .clear)
                Text(verbatim: text)
                    .font(.subheadline)
                    .foregroundStyle(row?.online == true && row?.state == .needsInput ? Color("AccentText") : .secondary)
            }
        }
    }

    /// The words and dot colour: gone first, then the session's state (offline when its Mac is),
    /// then a Mac that is offline before it ever listed the session.
    static func status(row: AgentStatusRow?, gone: Bool, offline: Bool) -> (text: String?, color: Color?) {
        if gone { return (String(localized: "agent.gone"), Color("StatusIdle")) }
        if let row {
            let style = AgentStateStyle(row)
            return (style.text, style.color)
        }
        if offline { return (String(localized: "agent.state.offline"), Color("StatusIdle")) }
        return (nil, nil)
    }
}
