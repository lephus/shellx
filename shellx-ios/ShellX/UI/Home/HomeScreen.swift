import ShellXAppCore
import SwiftUI

/// The home's layout, from plain values so render tests can show any state; `HomeView` feeds it from
/// the hub, the decision center and the home model.
///
/// - Top, pinned with `safeAreaInset` so it never scrolls away and never takes more than two lines:
///   the "Needs you · N" bar (it opens the "Needs You" page, where the cards are) and the agent
///   chips. The chips step aside while the keyboard is up.
/// - Middle: the conversation, newest at the bottom, scrolled down when an entry arrives. A tap on
///   it closes the keyboard.
/// - Bottom: the composer (the field and the mic) with its "Send to:" chip.
/// - Toolbar: the default Mac (opens "Your Macs") on the left, Settings on the right.
struct HomeScreen: View {
    struct Actions {
        var openMachines: () -> Void = {}
        var openSettings: () -> Void = {}
        var seeAllPending: () -> Void = {}
        /// The user picked a session in the "Send to:" menu (nil: automatic).
        var choose: (SessionRef?) -> Void = { _ in }
        /// A message began (the mic pressed, the field focused): it goes where the chip points now.
        var beginMessage: () -> Void = {}
        /// The message was dropped (released with nothing said, the keyboard closed empty).
        var endMessage: () -> Void = {}
        /// The composer's trimmed, valid text.
        var send: (String) -> Void = { _ in }
        /// What the user said into the mic (trimmed, not empty).
        var sendVoice: (String) -> Void = { _ in }
    }

    /// The default Mac, for the toolbar.
    let machine: (name: String, state: MachineLinkState)?
    let pending: [MachinePendingItem]
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
    var actions = Actions()

    @State private var keyboardUp = false

    var body: some View {
        conversation
            .safeAreaInset(edge: .top, spacing: 0) { top }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .tracksKeyboard($keyboardUp)
        .background(Color.appBackground)
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

    /// The bar while something is pending, the chips while an agent is live and the keyboard is down;
    /// nothing at all (not even the divider) otherwise.
    @ViewBuilder private var top: some View {
        let showsChips = !keyboardUp && !rows().isEmpty
        VStack(alignment: .leading, spacing: 2) {
            if !pending.isEmpty {
                NeedsYouBar(items: pending, showsMachineName: showsMachineName, open: actions.seeAllPending)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if showsChips {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    AgentChips(rows: rows())
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, pending.isEmpty && !showsChips ? 0 : 2)
        .background(Color.appBackground)
        .overlay(alignment: .bottom) {
            if !pending.isEmpty || showsChips { Divider() }
        }
        .dismissesKeyboardOnTap()
        .animation(.snappy(duration: 0.25), value: pending.isEmpty)
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
            .dismissesKeyboardOnTap()
            .onChange(of: entries.last?.id) { _, last in
                guard let last else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder private func row(_ entry: HomeEntry) -> some View {
        switch entry.content {
        case let .userSaid(text, target, viaVoice, _):
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
        ComposerBar(
            text: $draft, send: actions.send, sendVoice: actions.sendVoice, onBegin: actions.beginMessage,
            onEnd: actions.endMessage
        ) {
            TargetPicker(current: target, picked: pickedTarget, sessions: sessions, choose: actions.choose)
        }
    }
}
