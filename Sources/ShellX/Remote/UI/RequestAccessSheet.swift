import AppKit
import Combine
import ShellXBrand
import ShellXRemoteCore
import ShellXRemoteUI
import SwiftUI

extension RequestAccessLabels {
    static var localized: RequestAccessLabels {
        RequestAccessLabels(
            title: String(localized: "remote.request.title", defaultValue: "Request access to %@"),
            instructions: String(
                localized: "remote.request.instructions",
                defaultValue: "On %@, approve only if the code and fingerprint match this screen."
            ),
            approved: String(localized: "remote.request.approved", defaultValue: "Approved"),
            denied: String(localized: "remote.request.denied", defaultValue: "Denied"),
            expired: String(localized: "remote.request.expired", defaultValue: "Expired"),
            network: String(localized: "remote.signin.error.network", defaultValue: "Can't reach relay.shellx.pro")
        )
    }
}

/// Follows one machine's outgoing pairing in the service and turns it into
/// a `RequestAccessModel`. A retry asks the service for a new pairing, which
/// then replaces the old one on screen.
@MainActor
final class RequestAccessSheetModel: ObservableObject {
    let machineID: RemoteMachine.ID
    @Published private(set) var model: RequestAccessModel?
    @Published private(set) var machineName: String
    @Published private(set) var isRetrying = false

    /// Cancel: dismiss only; the pairing expires server-side.
    var onCancel: (() -> Void)?
    /// Fired once, `RequestAccessModel.autoCloseDelay` after approval.
    var onApproved: (() -> Void)?

    private let service: any ShellXRemoteServicing
    private var expectedCode: String?
    private var supersededPairingIDs: Set<OutgoingPairing.ID> = []
    private var changeCancellable: AnyCancellable?
    private var autoCloseTask: Task<Void, Never>?
    private var autoClosePairingID: OutgoingPairing.ID?

    init(machineID: RemoteMachine.ID, expectedCode: String?, service: any ShellXRemoteServicing) {
        self.machineID = machineID
        self.expectedCode = expectedCode
        self.service = service
        machineName = service.machines.first { $0.id == machineID }?.name ?? machineID
        refresh()
        // `changePublisher` fires before the change lands; read on the next turn.
        changeCancellable = service.changePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
    }

    /// The header's "waiting · code" was clicked while this sheet is up.
    func follow(expectedCode code: String?) {
        if let code { expectedCode = code }
        refresh()
    }

    /// Title for the moment before the service publishes the pairing.
    var pendingTitle: String {
        String(format: RequestAccessLabels.localized.title, machineName)
    }

    func refresh() {
        let name = service.machines.first { $0.id == machineID }?.name ?? machineID
        if name != machineName { machineName = name }
        let pairing = RequestAccessModel.currentPairing(
            in: service.outgoing,
            for: machineID,
            expectedCode: expectedCode,
            excluding: supersededPairingIDs
        )
        let next = pairing.map { RequestAccessModel(pairing: $0, machineName: name, labels: .localized) }
        if next != model { model = next }
        if let next, next.closesAutomatically { scheduleAutoClose(for: next.pairingID) }
    }

    func retry() {
        guard !isRetrying, model?.primaryAction == .retry else { return }
        let previous = model?.pairingID
        if let previous { supersededPairingIDs.insert(previous) }
        isRetrying = true
        model = nil
        let service = service
        let machineID = machineID
        Task { @MainActor in
            do {
                let code = try await service.requestAccess(to: machineID)
                self.expectedCode = code
            } catch {
                // Nothing new to show; let the old pairing back so "Try again" stays.
                if let previous { self.supersededPairingIDs.remove(previous) }
                NSSound.beep()
            }
            self.isRetrying = false
            self.refresh()
        }
    }

    func cancel() {
        stop()
        onCancel?()
    }

    func stop() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
        changeCancellable = nil
    }

    private func scheduleAutoClose(for pairingID: OutgoingPairing.ID) {
        guard autoClosePairingID != pairingID else { return }
        autoClosePairingID = pairingID
        autoCloseTask?.cancel()
        let delay = UInt64(RequestAccessModel.autoCloseDelay * 1_000_000_000)
        autoCloseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }
            self.stop()
            self.onApproved?()
        }
    }
}

/// The requester's half of pairing: the code and this Mac's own
/// fingerprint, always side by side, for the target machine to compare.
/// Nothing here approves anything; there is no default button.
struct RequestAccessSheet: View {
    @ObservedObject var model: RequestAccessSheetModel

    var body: some View {
        let state = model.model
        VStack(alignment: .leading, spacing: 14) {
            Text(state?.title ?? model.pendingTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(ShellXPalette.textHi.color)
                .lineLimit(state?.titleLineLimit ?? 1)
                .truncationMode(.tail)
            if let state {
                field(
                    label: String(localized: "remote.request.code", defaultValue: "Code"),
                    value: state.codeText,
                    font: .system(size: 28, weight: .semibold, design: .monospaced),
                    color: ShellXPalette.textHi
                )
                field(
                    label: String(localized: "remote.request.fingerprint", defaultValue: "This Mac's fingerprint"),
                    value: state.fingerprintText,
                    font: .system(size: 13, design: .monospaced),
                    color: ShellXPalette.muted
                )
                Text(state.instructions)
                    .font(.system(size: 12))
                    .foregroundColor(ShellXPalette.text.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            statusRow(state)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(String(localized: "common.cancel", defaultValue: "Cancel")) {
                    model.cancel()
                }
                .buttonStyle(ShellXSheetButtonStyle(kind: .secondary))
                .keyboardShortcut(.cancelAction)
                if state?.primaryAction == .retry {
                    // Deliberately not the default action: Return does nothing here.
                    Button(String(localized: "remote.request.retry", defaultValue: "Try again")) {
                        model.retry()
                    }
                    .buttonStyle(ShellXSheetButtonStyle(kind: .primary))
                    .disabled(model.isRetrying)
                }
            }
        }
        .padding(20)
        .frame(width: 380, alignment: .leading)
        .background(ShellXPalette.raise.color)
        .environment(\.colorScheme, .dark)
    }

    private func field(label: String, value: String, font: Font, color: ShellXColor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(ShellXPalette.muted.color)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(value)
                .font(font)
                .foregroundColor(color.color)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
        }
    }

    /// Fixed height so the sheet does not jump between states.
    private func statusRow(_ state: RequestAccessModel?) -> some View {
        HStack(spacing: 8) {
            if state?.showsSpinner ?? true {
                ProgressView()
                    .controlSize(.small)
            }
            if let text = state?.statusText {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Self.color(for: state?.statusTone).color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(height: 18, alignment: .leading)
    }

    private static func color(for tone: RequestAccessModel.Tone?) -> ShellXColor {
        switch tone {
        case .done: return ShellXPalette.done
        case .error: return ShellXPalette.error
        case .muted, nil: return ShellXPalette.muted
        }
    }
}

/// Shows one request-access sheet at a time on the key (or main) window,
/// like `SignInSheetPresenter`.
@MainActor
final class RequestAccessSheetPresenter {
    static let shared = RequestAccessSheetPresenter()

    private var sheet: CloudSheetWindow?
    private var hostWindow: NSWindow?
    private var model: RequestAccessSheetModel?

    private init() {}

    func present(machineID: RemoteMachine.ID, expectedCode: String?, service: any ShellXRemoteServicing) {
        if let model, let window = sheet?.window {
            if model.machineID == machineID {
                model.follow(expectedCode: expectedCode)
                (hostWindow ?? window).makeKeyAndOrderFront(nil)
                return
            }
            dismiss()
        }
        let model = RequestAccessSheetModel(machineID: machineID, expectedCode: expectedCode, service: service)
        model.onCancel = { [weak self] in self?.dismiss() }
        model.onApproved = { [weak self] in
            self?.dismiss()
            ShellXRemoteUIActions.openSession(on: machineID)
        }
        let sheet = CloudSheetWindow(rootView: RequestAccessSheet(model: model))
        let window = sheet.window
        window.styleMask = [.titled]
        window.title = model.pendingTitle
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        self.model = model
        self.sheet = sheet

        let host = NSApp.cmuxMainWindowForModalPresentation(preferring: NSApp.keyWindow)
        if let host, host.attachedSheet == nil {
            hostWindow = host
            sheet.beginSheet(on: host)
        } else {
            hostWindow = nil
            sheet.orderFrontFloating()
        }
    }

    private func dismiss() {
        model?.stop()
        guard let window = sheet?.window else { return }
        if let host = hostWindow, host.attachedSheet === window {
            host.endSheet(window)
        }
        window.orderOut(nil)
        sheet = nil
        hostWindow = nil
        model = nil
    }
}
