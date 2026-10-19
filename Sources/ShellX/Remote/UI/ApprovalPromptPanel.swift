import AppKit
import ShellXBrand
import ShellXRemoteCore
import ShellXRemoteUI
import SwiftUI

extension ApprovalPromptLabels {
    static var localized: ApprovalPromptLabels {
        ApprovalPromptLabels(
            title: String(
                localized: "remote.approve.title",
                defaultValue: "%@ wants to view and control this Mac"
            ),
            compare: String(
                localized: "remote.approve.compare",
                defaultValue: "Approve only if the code and fingerprint match the other screen."
            ),
            suspicious: String(
                localized: "remote.approve.suspicious",
                defaultValue: "The fingerprint does not match what the server reports. Do not approve."
            ),
            approve: String(localized: "remote.approve.approve", defaultValue: "Approve"),
            deny: String(localized: "remote.approve.deny", defaultValue: "Deny"),
            queue: String(localized: "remote.approve.queue", defaultValue: "%lld of %lld"),
            network: String(localized: "remote.signin.error.network", defaultValue: "Can't reach relay.shellx.pro"),
            codeLabel: String(localized: "remote.request.code", defaultValue: "Code"),
            fingerprintLabel: String(localized: "remote.approve.fingerprint", defaultValue: "Fingerprint")
        )
    }
}

/// What the approval panel shows and the two actions it reports. The panel's
/// controller owns it; the view only reads `state` and calls back with the id
/// of the request the buttons were drawn for.
@MainActor
final class ApprovalPromptViewModel: ObservableObject {
    @Published var state: ApprovalPromptModel
    var onApprove: ((PairingRequest.ID) -> Void)?
    var onDeny: ((PairingRequest.ID) -> Void)?

    init(state: ApprovalPromptModel = ApprovalPromptModel(queue: [], now: Date())) {
        self.state = state
    }
}

/// The target Mac's half of pairing: the code and the requester's
/// fingerprint, always side by side, for the person to compare with the other
/// screen. Approve is disabled for a suspicious request; Deny is always
/// there. There is no default action and no keyboard shortcut: only a click
/// decides.
struct ApprovalPromptView: View {
    static let width: CGFloat = 400

    @ObservedObject var model: ApprovalPromptViewModel
    let reportSize: (CGSize) -> Void

    var body: some View {
        let state = model.state
        // The id the buttons were drawn for; a click acts on this request only.
        let shownID = state.current?.id
        VStack(alignment: .leading, spacing: 12) {
            header(state)
            Text(state.compareText)
                .font(.system(size: 12))
                .foregroundColor(ShellXPalette.text.color)
                .fixedSize(horizontal: false, vertical: true)
            compareBox(state)
            if let warning = state.warning {
                Text(warning)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ShellXPalette.error.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(ShellXPalette.panel.color)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(ShellXPalette.error.color, lineWidth: 1)
                    )
            }
            if let errorText = state.errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundColor(ShellXPalette.error.color)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
                Button(state.denyTitle) {
                    if let shownID { model.onDeny?(shownID) }
                }
                .buttonStyle(ShellXSheetButtonStyle(kind: .secondary))
                .disabled(!state.canDeny)
                Button(state.approveTitle) {
                    if let shownID { model.onApprove?(shownID) }
                }
                .buttonStyle(ShellXSheetButtonStyle(kind: .primary))
                .disabled(!state.canApprove)
            }
        }
        .padding(20)
        .frame(width: Self.width, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .background(ShellXPalette.raise.color)
        .environment(\.colorScheme, .dark)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            reportSize(size)
        }
    }

    /// One line, tail truncation; the full name is in the tooltip.
    private func header(_ state: ApprovalPromptModel) -> some View {
        HStack(spacing: 8) {
            Text(state.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(ShellXPalette.textHi.color)
                .lineLimit(state.titleLineLimit)
                .truncationMode(.tail)
                .help(state.title)
            Spacer(minLength: 0)
            if let queueText = state.queueText {
                Text(queueText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ShellXPalette.muted.color)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: 20)
    }

    /// The code and the fingerprint in one box. Neither is ever truncated:
    /// a cut-off fingerprint could hide the characters that differ.
    private func compareBox(_ state: ApprovalPromptModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            field(
                label: state.codeLabel,
                value: state.codeText,
                font: .system(size: 28, weight: .semibold, design: .monospaced)
            )
            field(
                label: state.fingerprintLabel,
                value: state.fingerprintText,
                font: .system(size: 16, weight: .medium, design: .monospaced)
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(ShellXPalette.panel.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(ShellXPalette.border.color, lineWidth: 1)
        )
    }

    private func field(label: String, value: String, font: Font) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(ShellXPalette.muted.color)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(value)
                .font(font)
                .foregroundColor(ShellXPalette.textHi.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The floating, titled panel that holds the approval prompt. It becomes key
/// so its buttons take clicks. A stray keypress must never approve, so the
/// panel structurally has no default button, and Esc and the close command do
/// nothing while a request is shown: the panel leaves only through the
/// controller (decision, expiry, or the queue emptying).
@MainActor
final class ApprovalPromptPanel: NSPanel {
    private var pendingContentSize: NSSize?
    private var isResizeScheduled = false

    init(viewModel: ApprovalPromptViewModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: ApprovalPromptView.width, height: 260),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = ShellXPalette.raise.nsColor
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }

        let view = ApprovalPromptView(model: viewModel) { [weak self] size in
            self?.contentIdealSizeChanged(size)
        }
        // Sized like `CloudSheetWindow`: the hosting controller has no sizing
        // options, so AppKit's layout pass never resizes the window; the view
        // reports its ideal size and the panel takes it on a later turn.
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        contentViewController = controller
        let ideal = NSHostingView(rootView: view).fittingSize
        if ideal.width > 0, ideal.height > 0 {
            setContentSize(NSSize(width: ceil(ideal.width), height: ceil(ideal.height)))
        } else {
            setContentSize(NSSize(width: ApprovalPromptView.width, height: 260))
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Return and Enter find no default button to press.
    override var defaultButtonCell: NSButtonCell? {
        get { nil }
        set { }
    }

    /// Esc does not dismiss the prompt.
    override func cancelOperation(_ sender: Any?) {}

    /// The panel is not closable; the close command does nothing either.
    override func performClose(_ sender: Any?) {}

    private func contentIdealSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        pendingContentSize = NSSize(width: ceil(size.width), height: ceil(size.height))
        guard !isResizeScheduled else { return }
        isResizeScheduled = true
        // Leave the layout pass that reported the size; apply on the next turn.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isResizeScheduled = false
            self.applyPendingContentSize()
        }
    }

    private func applyPendingContentSize() {
        guard let size = pendingContentSize else { return }
        pendingContentSize = nil
        let current = contentRect(forFrameRect: frame).size
        guard size != current else { return }
        // Keep the top-left corner, where the title is read.
        let oldFrame = frame
        var newFrame = frameRect(forContentRect: NSRect(origin: .zero, size: size))
        newFrame.origin.x = oldFrame.minX
        newFrame.origin.y = oldFrame.maxY - newFrame.height
        setFrame(newFrame, display: isVisible, animate: false)
    }
}
