import ShellXAppCore
import SwiftUI

/// A shell chip's page (and an agent chip's shown as its terminal).
///
/// The page of the terminal shown draws it (`TerminalSurface`), or says why it cannot: the Mac's ShellX shows no
/// terminals (`ShellPanePlaceholder`), the terminal is gone, refused or failed (with Try Again), it is opening, or the
/// Mac is offline before any screen came. Once a screen came it stays: dimmed under a line while the Mac is offline,
/// with a small spinner while it reopens. Any other page (a neighbour while swiping) is a plain card.
struct TerminalPane: View {
    let model: TerminalViewModel
    let terminalId: String
    /// The tab's name as its chip shows it (VoiceOver).
    let title: String
    /// Tests: the key bar shows without focus (Task 9).
    var showsKeyBar = false

    @State private var focused = false
    @State private var notice: AgentScreen.Notice?

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        content
            .onChange(of: model.pasteTooLarge) { _, _ in
                let text = String(localized: "terminal.paste.tooLarge")
                notice = AgentScreen.Notice(text: text)
                AccessibilityNotification.Announcement(text).post()
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
            case .connecting where model.snapshots == 0:
                connecting
            case .offline where model.snapshots == 0:
                message(icon: "wifi.slash", text: LocalizedStringResource("workspaces.alert.offline"), id: "terminal.offline")
            default:
                surfacePage(phase)
            }
        }
    }

    // MARK: - The terminal

    private func surfacePage(_ phase: TerminalViewPhase) -> some View {
        card {
            TerminalSurface(
                model: model, revision: model.screenRevision, snapshots: model.snapshots, topShift: model.topShift,
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
