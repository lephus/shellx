import ShellXAppCore
import SwiftUI

/// One agent's screen, from plain values so render tests can show any state; `AgentView` feeds it
/// from `AgentThreadModel`, the hub and the decision center.
///
/// - Navigation bar: the workspace, and "Stop" while the session works or waits for the user.
/// - Top, pinned: the header ("Claude Code · Mac", state) and the pending cards of this workspace.
///   It keeps at most 40 % of the height and scrolls inside itself past that.
/// - Middle: the chat, newest at the bottom; scrolling to the top loads older entries.
/// - Bottom: what became of the last send or stop, then the composer (its target is this session).
struct AgentScreen: View {
    struct Actions {
        /// The composer's trimmed, valid text.
        var send: (String) -> Void = { _ in }
        var stop: () -> Void = {}
        /// Force Stop, once confirmed.
        var forceStop: () -> Void = {}
        var loadOlder: () -> Void = {}
        var seeAllPending: () -> Void = {}
        var card: (MachinePendingItem) -> PendingCardView.Actions = { _ in PendingCardView.Actions() }
    }

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
    let pendingStatus: [PendingKey: DecisionStatus]
    let showsMachineName: Bool
    let entries: [ChatEntry]
    /// The newest page is on its way.
    let loading: Bool
    let canLoadOlder: Bool
    let loadingOlder: Bool
    /// Older entries exist, but the phone keeps no more.
    let olderOnlyOnMac: Bool
    let canStop: Bool
    let notice: Notice?
    @Binding var draft: String
    var actions = Actions()

    @State private var confirmsForceStop = false
    /// The first entry when older ones were asked for: the chat stays on it when they arrive.
    @State private var olderAnchor: String?
    @ScaledMetric(relativeTo: .body) private var conversationMinimum: CGFloat = 260

    private var agent: String { AgentLabel(agent: ref.agent).text }

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            conversation
                .safeAreaInset(edge: .top, spacing: 0) {
                    top(maxHeight: max(height * 0.4, min(height * 0.7, height - conversationMinimum)))
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
        }
        .background(Color(uiColor: .systemGroupedBackground))
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

    private func top(maxHeight: CGFloat) -> some View {
        ContentHeightUpTo(maxHeight: maxHeight) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        AgentHeader(place: place, row: row(), gone: gone, offline: offline)
                    }
                    if !pending.isEmpty {
                        PinnedSection(
                            items: pending, status: pendingStatus, showsMachineName: showsMachineName,
                            actions: actions.card, seeAll: actions.seeAllPending)
                            .padding(.bottom, 6)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicatorsFlash(onAppear: true)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay(alignment: .bottom) { Divider() }
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: entries.last?.id) { _, last in
                guard let last else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
            }
            .onChange(of: loadingOlder) { was, now in
                // Older entries came in above: stay on the entry that was first.
                guard was, !now, let anchor = olderAnchor else { return }
                olderAnchor = nil
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
    }

    /// At the top: a spinner that asks for older entries when it scrolls into view, or a line saying
    /// the older ones are only on the Mac.
    @ViewBuilder private var olderRow: some View {
        if !entries.isEmpty, canLoadOlder {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44)
                .onAppear {
                    olderAnchor = entries.first?.id
                    actions.loadOlder()
                }
                .accessibilityIdentifier("agent.loadOlder")
        } else if !entries.isEmpty, olderOnlyOnMac {
            Text(LocalizedStringResource("agent.olderOnMac"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("agent.olderOnMac")
        }
    }

    @ViewBuilder private var emptyRow: some View {
        if loading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else {
            Text(LocalizedStringResource("agent.empty"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .accessibilityIdentifier("agent.empty")
        }
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
            ComposerBar(text: $draft, send: actions.send)
        }
        .animation(.easeInOut(duration: 0.2), value: notice)
    }
}
