import ShellXAppCore
import SwiftUI

/// One agent's screen, from plain values so render tests can show any state; `AgentView` feeds it
/// from `AgentThreadModel`, the hub and the decision center.
///
/// - Navigation bar: the workspace, "Stop" while the session works or waits for the user, and `•••` with
///   "Close Agent" (red; it asks first) while the agent can be closed (`closeAgentName`), and "Remove from
///   This Phone" (red; nothing is asked) while the session is gone from its Mac (`canRemoveFromPhone`).
///   Embedded as a workspace screen's pane (`embedded`) it has no navigation bar of its own: the screen
///   around it has one, with "Close Tab…" for the agent's tab in its `•••`, and "Stop" sits at the end of
///   the header.
/// - Top, pinned: the header ("Claude Code · Mac", state), "Remove from This Phone" under the gone line
///   while `canRemoveFromPhone` (standalone only) and, while this workspace has pending requests, the
///   "Needs you · N" bar that opens them on their own page.
/// - Middle: the chat, newest at the bottom; scrolling to the top loads older entries. It follows
///   new entries only while its bottom shows; otherwise "New messages ↓" offers to jump down. A tap
///   on it closes the keyboard.
/// - Bottom: what became of the last send or stop, then the composer (its target is this session).
struct AgentScreen: View {
    struct Actions {
        /// The composer's trimmed, valid text (empty with attachments only) and its attachments.
        var send: (String, [OutgoingAttachment]) -> Void = { _, _ in }
        /// What the user said into the mic (trimmed, not empty).
        var sendVoice: (String) -> Void = { _ in }
        var stop: () -> Void = {}
        /// Force Stop, once confirmed.
        var forceStop: () -> Void = {}
        /// Asks for older entries (also the retry after a failure).
        var loadOlder: () -> Void = {}
        /// Asks for the newest page again after it failed.
        var retry: () -> Void = {}
        /// The "Needs you" bar: this workspace's pending cards.
        var seeAllPending: () -> Void = {}
        /// Close Agent, once confirmed: closes the terminal tab the agent runs in on its Mac.
        var closeAgent: () -> Void = {}
        /// Remove from This Phone: hides the session gone from its Mac on this phone, then goes back.
        var removeFromPhone: () -> Void = {}
    }

    /// Where the chat's bottom sentinel sits, to scroll to.
    private static let bottomID = "agent.chat.bottom"

    /// A short line over the composer: what became of the last send or stop.
    struct Notice: Equatable {
        var id = UUID()
        var text: String
    }

    let ref: SessionRef
    /// A pane of the workspace screen: no navigation title or toolbar of its own.
    var embedded = false
    /// "Claude Code · MacBook Pro".
    let place: String
    /// The header's state as of now; read again every second for the "Running for" time.
    let row: () -> AgentStatusRow?
    let gone: Bool
    let offline: Bool
    let pending: [MachinePendingItem]
    let showsMachineName: Bool
    let entries: [ChatEntry]
    /// What the chat says while it has no entries.
    let emptyState: AgentThreadModel.EmptyState?
    /// The Mac's name, for "<Mac> is offline".
    let machineName: String
    /// What the top of the chat shows about older entries.
    let older: AgentThreadModel.Older
    let loadingOlder: Bool
    let canStop: Bool
    let notice: Notice?
    @Binding var draft: String
    /// The composer's photos and files; nil when the session's Mac takes none.
    var attachments: Binding<[OutgoingAttachment]>? = nil
    /// How far the attachments of the message being sent got; not nil locks the composer.
    var sending: Double? = nil
    /// The agent's name, for "Close <name>?", while `•••` offers "Close Agent": the session has not ended, a
    /// listed tab names it and its Mac takes `agent.close` (`WorkspaceListActions.canClose`). Nil shows no
    /// `•••`; standalone only.
    var closeAgentName: String? = nil
    /// The Mac answered `not_found` for this session, which it still lists (`AgentThreadModel.ghost`): the
    /// screen offers "Remove from This Phone" under the gone line and in `•••`. Standalone only; never for a
    /// live session.
    var canRemoveFromPhone = false
    var actions = Actions()

    @State private var confirmsForceStop = false
    /// The name in the Close Agent confirmation while it is up.
    @State private var closing: String?
    @State private var follow = ChatFollow()
    /// The first entry when older ones were asked for: the chat stays on it when they arrive.
    @State private var olderAnchor: String?

    private var agent: String { AgentLabel(agent: ref.agent).text }
    /// A pane of the workspace screen offers no Remove from This Phone: it shows a tab of the Mac's.
    private var offersRemove: Bool { canRemoveFromPhone && !embedded }

    /// `•••` while it holds something: Close Agent while the agent can be closed, Remove from This Phone
    /// while it is offered.
    private var menu: AgentMenu? {
        guard closeAgentName != nil || offersRemove else { return nil }
        let close: (() -> Void)? = closeAgentName.map { name in { closing = name } }
        return AgentMenu(
            online: !offline, closeAgent: close, removeFromPhone: offersRemove ? actions.removeFromPhone : nil)
    }

    var body: some View {
        conversation
            .safeAreaInset(edge: .top, spacing: 0) { top }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
        .background(Color.appBackground)
        .modifier(
            NavigationChrome(
                enabled: !embedded, title: ref.workspaceTitle,
                stop: canStop ? StopButton(stop: actions.stop, forceStop: { confirmsForceStop = true }) : nil,
                menu: menu)
        )
        .confirmationDialog(
            Text(verbatim: String(localized: "agent.forceStop.title \(agent) \(ref.workspaceTitle)")),
            isPresented: $confirmsForceStop, titleVisibility: .visible
        ) {
            Button(String(localized: "agent.forceStop"), role: .destructive, action: actions.forceStop)
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringResource("agent.forceStop.message"))
        }
        .agentCloseConfirmation($closing, name: { $0 }) { _ in actions.closeAgent() }
    }

    // MARK: - Top

    private var top: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    AgentHeader(place: place, row: row(), gone: gone, offline: offline)
                }
                // Embedded, there is no toolbar to hold it.
                if embedded, canStop {
                    StopButton(stop: actions.stop, forceStop: { confirmsForceStop = true })
                }
            }
            if offersRemove {
                RemoveFromPhoneButton(remove: actions.removeFromPhone)
            }
            if !pending.isEmpty {
                NeedsYouBar(items: pending, showsMachineName: showsMachineName, open: actions.seeAllPending)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .background(Color.appBackground)
        .overlay(alignment: .bottom) { Divider() }
        .dismissesKeyboardOnTap()
        .animation(.snappy(duration: 0.25), value: pending.isEmpty)
    }

    // MARK: - Chat

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    olderRow
                    if entries.isEmpty {
                        emptyRow
                    }
                    ForEach(entries, id: \.id) { entry in
                        ChatEntryRow(entry: entry, agent: agent).id(entry.id)
                    }
                    // Shows while the bottom of the chat is on screen: new entries are followed
                    // only then.
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                        .onAppear { follow.bottomVisible(true) }
                        .onDisappear { follow.bottomVisible(false) }
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
            .overlay(alignment: .bottom) {
                if follow.hasUnseen {
                    NewMessagesButton {
                        follow.jumpedToBottom()
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                    }
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: follow.hasUnseen)
            .onChange(of: entries.last?.id) { _, last in
                // Never pulled down while the user reads older entries.
                guard follow.newest(last) else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onChange(of: loadingOlder) { was, now in
                // Older entries came in above: stay on the entry that was first.
                guard was, !now, let anchor = olderAnchor else { return }
                olderAnchor = nil
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
    }

    /// At the top: a spinner that asks for older entries when it scrolls into view, a row to try
    /// again after a failure, or a line saying the older ones are only on the Mac. Nothing while the
    /// Mac is offline.
    @ViewBuilder private var olderRow: some View {
        switch older {
        case .none:
            EmptyView()
        case .loadable:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44)
                .onAppear(perform: loadOlder)
                .accessibilityIdentifier("agent.loadOlder")
        case .failed:
            failedRow(LocalizedStringResource("agent.older.failed"), retry: loadOlder)
                .accessibilityIdentifier("agent.older.failed")
        case .onlyOnMac:
            Text(LocalizedStringResource("agent.olderOnMac"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("agent.olderOnMac")
        }
    }

    private func loadOlder() {
        olderAnchor = entries.first?.id
        actions.loadOlder()
    }

    @ViewBuilder private var emptyRow: some View {
        switch emptyState {
        case nil:
            EmptyView()
        case .loading?:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .accessibilityIdentifier("agent.loading")
        case .noMessages?:
            emptyText(LocalizedStringResource("agent.empty"))
                .accessibilityIdentifier("agent.empty")
        case .offline?:
            emptyText(LocalizedStringResource("agent.empty.offline \(machineName)"))
                .accessibilityIdentifier("agent.empty.offline")
        case .failed?:
            failedRow(LocalizedStringResource("agent.empty.failed"), retry: actions.retry)
                .padding(.vertical, 32)
                .accessibilityIdentifier("agent.empty.failed")
        case .gone?:
            emptyText(LocalizedStringResource("agent.gone"))
                .accessibilityIdentifier("agent.empty.gone")
        }
    }

    private func emptyText(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }

    /// What failed, and "Try again".
    private func failedRow(_ text: LocalizedStringResource, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text(LocalizedStringResource("pending.status.retry"))
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .tint(Color("AccentText"))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom

    private var bottom: some View {
        VStack(spacing: 0) {
            if let notice {
                Text(verbatim: notice.text)
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)
                    .transition(.opacity)
                    .accessibilityIdentifier("agent.notice")
            }
            ComposerBar(
                text: $draft, attachments: attachments, sending: sending, send: actions.send,
                sendVoice: actions.sendVoice)
        }
        .animation(.easeInOut(duration: 0.2), value: notice)
    }
}

/// The agent screen's navigation title and, while it can be stopped, "Stop" in the toolbar, then `•••`
/// while the agent can be closed: all of it off when the screen is a pane of the workspace screen, which
/// has its own bar.
private struct NavigationChrome: ViewModifier {
    let enabled: Bool
    let title: String
    let stop: StopButton?
    let menu: AgentMenu?

    func body(content: Content) -> some View {
        if enabled {
            content
                .navigationTitle(Text(verbatim: title))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let stop {
                        ToolbarItem(placement: .topBarTrailing) { stop }
                    }
                    if let menu {
                        ToolbarItem(placement: .topBarTrailing) { menu }
                    }
                }
        } else {
            content
        }
    }
}

extension AgentScreen {
    /// "Remove from This Phone" under the header's "This session is gone from the Mac": hides the session on
    /// this phone at once (nothing is asked: nothing stops on the Mac, and the session shows again when its
    /// Mac reports a change).
    struct RemoveFromPhoneButton: View {
        let remove: () -> Void

        var body: some View {
            Button(action: remove) {
                Label(String(localized: "agent.removeFromPhone"), systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .tint(Color("AccentText"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("agent.removeFromPhone")
        }
    }
}

/// `•••` in the agent screen's toolbar (HIG: Pull-down buttons): "Close Agent", red, which asks to confirm
/// first (the owner presents the confirmation) and is off while the Mac is not online; and "Remove from This
/// Phone", red, at once, also while the Mac is away (nothing reaches it). Off when nothing in it works.
private struct AgentMenu: View {
    /// The Mac is online: Close Agent reaches it.
    let online: Bool
    /// Close Agent; nil when the agent cannot be closed.
    let closeAgent: (() -> Void)?
    /// Remove from This Phone; nil unless the session is gone from its Mac.
    let removeFromPhone: (() -> Void)?

    var body: some View {
        Menu {
            if let closeAgent {
                Button(role: .destructive, action: closeAgent) {
                    Label(String(localized: "agent.close.menu"), systemImage: "xmark")
                }
                .disabled(!online)
            }
            if let removeFromPhone {
                Button(role: .destructive, action: removeFromPhone) {
                    Label(String(localized: "agent.removeFromPhone"), systemImage: "trash")
                }
            }
        } label: {
            Label(String(localized: "agent.menu"), systemImage: "ellipsis.circle")
        }
        .disabled(!online && removeFromPhone == nil)
        .accessibilityIdentifier("agent.menu")
    }
}
