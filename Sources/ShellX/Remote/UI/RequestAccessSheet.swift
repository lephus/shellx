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
/// then replaces the old one on screen. Which pairing is followed, and what a
/// dismissed sheet may no longer do, is decided by the package's
/// `RequestAccessTracker`; this class only owns the Tasks.
@MainActor
final class RequestAccessSheetModel: ObservableObject {
    let machineID: RemoteMachine.ID
    /// Nil before the service publishes the pairing and while a retry is in flight.
    @Published private(set) var state: RequestAccessModel? = nil
    @Published private(set) var machineName: String

    /// Cancel: dismiss only; the pairing expires server-side.
    var onCancel: (() -> Void)?
    /// Fired once, `RequestAccessModel.autoCloseDelay` after approval.
    var onApproved: (() -> Void)?

    private let service: any ShellXRemoteServicing
    private var tracker: RequestAccessTracker
    private var changeCancellable: AnyCancellable?
    private var retryTask: Task<Void, Never>?
    private var autoCloseTask: Task<Void, Never>?

    init(machineID: RemoteMachine.ID, expectedCode: String?, service: any ShellXRemoteServicing) {
        self.machineID = machineID
        self.service = service
        tracker = RequestAccessTracker(machineID: machineID, expectedCode: expectedCode)
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
        tracker.follow(expectedCode: code)
        refresh()
    }

    /// Title for the moment before the service publishes the pairing.
    var pendingTitle: String {
        String(format: RequestAccessLabels.localized.title, machineName)
    }

    func refresh() {
        guard !tracker.isStopped else { return }
        let name = service.machines.first { $0.id == machineID }?.name ?? machineID
        if name != machineName { machineName = name }
        let next = tracker.current(in: service.outgoing)
            .map { RequestAccessModel(pairing: $0, machineName: name, labels: .localized) }
        if next != state { state = next }
        if let next, next.closesAutomatically, tracker.takeAutoClose(for: next.pairingID) {
            scheduleAutoClose()
        }
    }

    /// "Try again": ask for a new pairing and follow it instead of the old one.
    func retry() {
        guard tracker.beginRetry(from: state) else { return }
        refresh()
        let service = service
        let machineID = machineID
        retryTask = Task { @MainActor [weak self] in
            let code: String?
            do {
                code = try await service.requestAccess(to: machineID)
            } catch {
                code = nil
                if !Task.isCancelled { NSSound.beep() }
            }
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            self.tracker.finishRetry(code: code)
            self.refresh()
        }
    }

    func cancel() {
        stop()
        onCancel?()
    }

    /// The sheet is gone: no Task or subscription outlives this call, and a
    /// pending retry or auto-close can no longer open a session.
    func stop() {
        tracker.stop()
        retryTask?.cancel()
        retryTask = nil
        autoCloseTask?.cancel()
        autoCloseTask = nil
        changeCancellable = nil
    }

    private func scheduleAutoClose() {
        autoCloseTask?.cancel()
        let delay = UInt64(RequestAccessModel.autoCloseDelay * 1_000_000_000)
        autoCloseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self, !self.tracker.isStopped else { return }
            self.autoCloseTask = nil
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
        let state = model.state
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
        if let current = model, let window = sheet?.window {
            if current.machineID == machineID {
                current.follow(expectedCode: expectedCode)
                (hostWindow ?? window).makeKeyAndOrderFront(nil)
                return
            }
            dismiss()
        }
        let newModel = RequestAccessSheetModel(machineID: machineID, expectedCode: expectedCode, service: service)
        newModel.onCancel = { [weak self] in self?.dismiss() }
        newModel.onApproved = { [weak self] in
            self?.dismiss()
            ShellXRemoteUIActions.openSession(on: machineID)
        }
        let newSheet = CloudSheetWindow(rootView: RequestAccessSheet(model: newModel))
        let window = newSheet.window
        window.styleMask = [.titled]
        window.title = newModel.pendingTitle
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        model = newModel
        sheet = newSheet

        let host = NSApp.cmuxMainWindowForModalPresentation(preferring: NSApp.keyWindow)
        if let host, host.attachedSheet == nil {
            hostWindow = host
            newSheet.beginSheet(on: host)
        } else {
            hostWindow = nil
            newSheet.orderFrontFloating()
        }
    }

    private func dismiss() {
        model?.stop()
        model = nil
        guard let window = sheet?.window else { return }
        if let host = hostWindow, host.attachedSheet === window {
            host.endSheet(window)
        }
        window.orderOut(nil)
        sheet = nil
        hostWindow = nil
    }
}
