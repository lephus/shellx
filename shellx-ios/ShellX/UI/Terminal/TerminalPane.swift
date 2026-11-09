import ShellXAppCore
import SwiftUI

/// A shell chip's page (and an agent chip's shown as its terminal).
///
/// The page of the terminal shown draws it (`TerminalSurface`), or says why it cannot: the Mac's ShellX shows no
/// terminals (`ShellPanePlaceholder`), the terminal is gone, refused or failed (with Try Again), it is opening, or the
/// Mac is offline before any screen came. Once a screen came it stays: dimmed under a line while the Mac is offline,
/// with a small spinner while it reopens. Any other page (a neighbour while swiping) is a plain card. The page shown
/// always holds the surface, under those cards too, because the surface's size is what the open asks for.
struct TerminalPane: View {
    let model: TerminalViewModel
    let terminalId: String
    /// The tab's name as its chip shows it (VoiceOver).
    let title: String
    /// Tests: the key bar shows without focus (Task 9).
    var showsKeyBar = false
    /// Says a line to VoiceOver; tests count the lines.
    var announce: @MainActor (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    /// The user took the keyboard on this page or sent it input (the workspace screen settles on its chip).
    var engaged: @MainActor () -> Void = {}

    @State private var focused = false
    @State private var notice: AgentScreen.Notice?

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        VStack(spacing: 0) {
            content
            if (focused || showsKeyBar) && model.terminalId == terminalId {
                TerminalKeyBar(ctrlLatched: model.typing.ctrlLatched) { item in
                    // A tap as the page stops being the one shown never reaches the terminal shown next.
                    guard model.terminalId == terminalId else { return }
                    Self.perform(item, on: model) { focused = false }
                }
            }
        }
        // A page that is not the one shown never keeps the keyboard.
        .onChange(of: model.terminalId) { _, shown in
            if shown != terminalId { focused = false }
        }
        .onChange(of: focused) { _, now in
            if now { engaged() }
        }
        .onChange(of: model.sentInputs) { _, _ in
            if model.terminalId == terminalId { engaged() }
        }
        .onChange(of: model.pasteTooLarge) { _, _ in
            // The model is every page's: only the page shown says it, once.
            guard model.terminalId == terminalId else { return }
            let text = String(localized: "terminal.paste.tooLarge")
            notice = AgentScreen.Notice(text: text)
            announce(text)
        }
        .task(id: notice?.id) {
            guard notice != nil else { return }
            do { try await Task.sleep(for: AgentView.noticeDuration) } catch { return }
            notice = nil
        }
    }

    @ViewBuilder private var content: some View {
        let phase = model.phase
        if model.terminalId != terminalId {
            if phase == .unsupported { ShellPanePlaceholder() } else { card { Color.appSurface } }
        } else {
            // The surface is there in every state of the page shown, under the card that says why it shows no terminal
            // (yet): its size is the grid every open asks for (R1, R11), so without it nothing would ever open. Covered,
            // it is not drawn, touched or read out; it stays the same view from the first card to the live screen.
            let covered = Self.covers(phase, snapshots: model.snapshots)
            surfacePage(phase)
                .opacity(covered ? 0 : 1)
                .allowsHitTesting(!covered)
                .accessibilityHidden(covered)
                .overlay {
                    if covered { cover(phase) }
                }
        }
    }

    /// Whether a card covers the surface of the page shown: the terminal cannot be shown, or no screen came yet.
    static func covers(_ phase: TerminalViewPhase, snapshots: Int) -> Bool {
        switch phase {
        case .live: false
        case .connecting, .offline: snapshots == 0
        case .unsupported, .unavailable: true
        }
    }

    /// The card over the surface (`covers(_:snapshots:)`).
    @ViewBuilder private func cover(_ phase: TerminalViewPhase) -> some View {
        switch phase {
        case .unsupported:
            ShellPanePlaceholder()
        case .unavailable(.gone):
            message(icon: "xmark.rectangle", text: LocalizedStringResource("terminal.gone"), id: "terminal.unavailable")
        case .unavailable(.refused):
            message(icon: "lock", text: LocalizedStringResource("workspaces.alert.refused.control"), id: "terminal.unavailable")
        case .unavailable(.failed):
            message(icon: "exclamationmark.triangle", text: LocalizedStringResource("terminal.failed"), id: "terminal.unavailable") {
                Button { model.retry() } label: { Text(LocalizedStringResource("terminal.retry")) }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("terminal.retry")
            }
        case .offline:
            message(icon: "wifi.slash", text: LocalizedStringResource("workspaces.alert.offline"), id: "terminal.offline")
        case .connecting, .live:
            connecting
        }
    }

    /// What a key bar button does: a key → `model.press(key)`; ctrl → `model.toggleCtrl()`; hide keyboard → `hideKeyboard()`.
    static func perform(_ item: TerminalKeyBarItem, on model: TerminalViewModel, hideKeyboard: () -> Void) {
        switch item {
        case let .key(barKey):
            if let key = barKey.key { model.press(key) } else { model.toggleCtrl() }
        case .hideKeyboard:
            hideKeyboard()
        }
    }

    // MARK: - The terminal

    private func surfacePage(_ phase: TerminalViewPhase) -> some View {
        card {
            TerminalSurface(
                model: model, terminalId: terminalId, revision: model.screenRevision, snapshots: model.snapshots, topShift: model.topShift,
                typing: model.typing, phase: phase, sentInputs: model.sentInputs, title: title, focused: $focused)
                .opacity(phase == .offline ? 0.5 : 1)
        }
        .overlay(alignment: .top) {
            Group {
                if let notice {
                    NoticeCapsule(text: notice.text)
                } else if phase == .offline {
                    NoticeCapsule(text: String(localized: "terminal.offline"))
                        .accessibilityIdentifier("terminal.offline")
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 6)
        }
        .overlay(alignment: .topTrailing) {
            if phase == .connecting {
                ProgressView()
                    .controlSize(.small)
                    .padding(18)
                    .accessibilityLabel(Text(LocalizedStringResource("terminal.connecting")))
            }
        }
        .animation(.default, value: notice?.id)
    }

    // MARK: - Messages

    private var connecting: some View {
        card {
            VStack(spacing: 12) {
                ProgressView()
                Text(LocalizedStringResource("terminal.connecting"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appSurface)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("terminal.connecting")
        }
    }

    private func message(icon: String, text: LocalizedStringResource, id: String) -> some View {
        message(icon: icon, text: text, id: id) { EmptyView() }
    }

    private func message(
        icon: String, text: LocalizedStringResource, id: String, @ViewBuilder action: () -> some View
    ) -> some View {
        card {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)
                action()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appSurface)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(id)
        }
    }

    /// The page's card, in the place and shape of `ShellPanePlaceholder`.
    private func card(@ViewBuilder _ inside: () -> some View) -> some View {
        inside()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1) }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
    }
}
