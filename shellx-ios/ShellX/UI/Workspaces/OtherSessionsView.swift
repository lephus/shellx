import ShellXAppCore
import SwiftUI

/// "Other agent sessions" of one Mac, from the workspace list's last row: the sessions no terminal of
/// the Mac's workspaces names (run over SSH, in a workspace since closed) and the ended ones whose chat
/// can still be read. A tap opens that session's `AgentView`.
struct OtherSessionsView: View {
    let hub: MachineHub
    let machineID: String

    var body: some View {
        let name = hub.machines.first { $0.id == machineID }?.name ?? ""
        let sessions = hub.otherSessions(machineID: machineID)
        TimelineView(.periodic(from: .now, by: 1)) { context in
            OtherSessionsList(machineName: name, sessions: sessions, now: context.date)
        }
    }
}

/// The list itself, from plain values so render tests can show it.
struct OtherSessionsList: View {
    let machineName: String
    let sessions: [MachineSession]
    let now: Date

    var body: some View {
        List {
            if sessions.isEmpty {
                Text(LocalizedStringResource("workspaces.other.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("workspace.otherSessions.empty")
            } else {
                Section {
                    ForEach(sessions) { session in
                        NavigationLink(value: session.ref) {
                            OtherSessionRow(session: session, now: now)
                        }
                        .listRowBackground(Color.appSurface)
                    }
                } header: {
                    Text(verbatim: machineName)
                }
            }
        }
        .themedList()
        .navigationTitle(String(localized: "workspaces.other.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One session: the workspace it ran in (or its title), the agent, and its state in words.
private struct OtherSessionRow: View {
    let session: MachineSession
    let now: Date

    private var style: AgentStateStyle { AgentStateStyle(AgentStatusRow(session: session, now: now)) }
    private var name: String {
        [session.session.workspaceTitle, session.session.title ?? ""].first { !$0.isEmpty } ?? session.session.sessionId
    }
    private var detail: String {
        var parts = [AgentLabel(agent: session.session.agent).text]
        if let title = session.session.title, !title.isEmpty, title != name { parts.append(title) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let color = style.color { StatusDot(color: color) }
                Text(verbatim: name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
            }
            Text(verbatim: detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let text = style.text {
                Text(verbatim: text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(LocalizedStringResource("agent.open.hint")))
        .accessibilityIdentifier("workspace.otherSession.\(session.session.sessionId)")
    }
}
