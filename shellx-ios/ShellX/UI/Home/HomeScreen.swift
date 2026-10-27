import ShellXAppCore
import SwiftUI

/// The home's layout (mockup layout C), from plain values so render tests can show any state;
/// `HomeView` feeds it from the hub, the decision center and the home model.
///
/// - Top, pinned with `safeAreaInset` so it never scrolls away: "Needs you · N" and the agent
///   strip. It leaves the conversation and the composer room (`conversationMinimum`) and scrolls
///   inside itself past that.
/// - Middle: the conversation, newest at the bottom, scrolled down when an entry arrives.
/// - Bottom: the composer with its "Send to:" chip.
/// - Toolbar: the default Mac (opens "Your Macs") on the left, Settings on the right.
struct HomeScreen: View {
    struct Actions {
        var openMachines: () -> Void = {}
        var openSettings: () -> Void = {}
        var seeAllPending: () -> Void = {}
        /// The user picked a session in the "Send to:" menu (nil: automatic).
        var choose: (SessionRef?) -> Void = { _ in }
        /// The composer's trimmed, valid text.
        var send: (String) -> Void = { _ in }
        var card: (MachinePendingItem) -> PendingCardView.Actions = { _ in PendingCardView.Actions() }
    }

    /// The default Mac, for the toolbar.
    let machine: (name: String, state: MachineLinkState)?
    let pending: [MachinePendingItem]
    let pendingStatus: [PendingKey: DecisionStatus]
    let showsMachineName: Bool
    /// The agent rows as of now; read again every second for the "Running for" times.
    let rows: () -> [AgentStatusRow]
    /// False until the stored conversation is read: nothing shows in it yet, not even the empty text.
    let isLoaded: Bool
    let entries: [HomeEntry]
    let target: SessionRef?
    let pickedTarget: SessionRef?
    let sessions: [MachineSession]
    @Binding var draft: String
    @Binding var agentsExpanded: Bool
    var actions = Actions()

    /// The conversation and the composer keep at least this much of the height, grown with the text
    /// size; the top panel always keeps 40 %.
    @ScaledMetric(relativeTo: .body) private var conversationMinimum: CGFloat = 260

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            conversation
                .safeAreaInset(edge: .top, spacing: 0) {
                    top(maxHeight: max(height * 0.4, min(height * 0.7, height - conversationMinimum)))
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(String(localized: "root.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let machine {
                ToolbarItem(placement: .topBarLeading) {
                    MacStatusPill(name: machine.name, state: machine.state, open: actions.openMachines)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: actions.openSettings) {
                    Label(String(localized: "settings.title"), systemImage: "gearshape")
                }
                .accessibilityIdentifier("root.settings")
            }
        }
    }

    // MARK: - Top

    /// The panel at its full height when it fits in `maxHeight`; otherwise `maxHeight` tall, and it
    /// scrolls inside itself (its scroll bar flashes, so that shows). Sized during layout, so the
    /// panel never jumps from a first guess to its real height.
    @ViewBuilder private func top(maxHeight: CGFloat) -> some View {
        let hasRows = !rows().isEmpty
        if !pending.isEmpty || hasRows {
            ContentHeightUpTo(maxHeight: maxHeight) {
                ScrollView { topPanel }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicatorsFlash(onAppear: true)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private var topPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !pending.isEmpty {
                PinnedSection(
                    items: pending, status: pendingStatus, showsMachineName: showsMachineName, actions: actions.card,
                    seeAll: actions.seeAllPending)
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let rows = rows()
                if !rows.isEmpty {
                    AgentStrip(rows: rows, expanded: $agentsExpanded)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if isLoaded, entries.isEmpty {
                        Text(LocalizedStringResource("home.empty"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                            .accessibilityIdentifier("home.empty")
                    }
                    ForEach(entries) { entry in
                        row(entry).id(entry.id)
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
        }
    }

    @ViewBuilder private func row(_ entry: HomeEntry) -> some View {
        switch entry.content {
        case let .userSaid(text, target, viaVoice):
            UserMessageBubble(text: text, target: target, viaVoice: viaVoice)
        case let .note(note):
            if case let .agentFinished(ref, _) = note {
                // A "done" note opens its agent.
                NavigationLink(value: ref) {
                    HomeNoteRow(note: note, showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(LocalizedStringResource("agent.open.hint")))
            } else {
                HomeNoteRow(note: note)
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        ComposerBar(text: $draft, send: actions.send) {
            TargetPicker(current: target, picked: pickedTarget, sessions: sessions, choose: actions.choose)
        }
    }
}
