import ShellXAppCore
import SwiftUI

/// One agent's screen, from plain values so render tests can show any state; `AgentView` feeds it
/// from `AgentThreadModel`, the hub and the decision center.
///
/// - Navigation bar: the workspace, and "Stop" while the session works or waits for the user.
/// - Top, pinned: the header ("Claude Code · Mac", state) and, while this workspace has pending
///   requests, the "Needs you · N" bar that opens them on their own page.
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
    }

    /// Where the chat's bottom sentinel sits, to scroll to.
    private static let bottomID = "agent.chat.bottom"

    /// A short line over the composer: what became of the last send or stop.
    struct Notice: Equatable {
        var id = UUID()
        var text: String
    }

    let ref: SessionRef
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
    var actions = Actions()

    @State private var confirmsForceStop = false
    @State private var follow = ChatFollow()
    /// The first entry when older ones were asked for: the chat stays on it when they arrive.
    @State private var olderAnchor: String?

    private var agent: String { AgentLabel(agent: ref.agent).text }

    var body: some View {
        conversation
            .safeAreaInset(edge: .top, spacing: 0) { top }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
        .background(Color.appBackground)
        .navigationTitle(Text(verbatim: ref.workspaceTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canStop {
                ToolbarItem(placement: .topBarTrailing) {
                    StopButton(stop: actions.stop, forceStop: { confirmsForceStop = true })
                }
            }
        }
        .confirmationDialog(
            Text(verbatim: String(localized: "agent.forceStop.title \(agent) \(ref.workspaceTitle)")),
            isPresented: $confirmsForceStop, titleVisibility: .visible
        ) {
            Button(String(localized: "agent.forceStop"), role: .destructive, action: actions.forceStop)
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringResource("agent.forceStop.message"))
        }
    }

    // MARK: - Top

    private var top: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                AgentHeader(place: place, row: row(), gone: gone, offline: offline)
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
