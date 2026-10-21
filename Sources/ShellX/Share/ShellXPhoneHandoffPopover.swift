import AppKit
import Combine
import ShellXBrand
import ShellXRemoteCore
import SwiftUI

// MARK: - "Tiếp tục trên điện thoại" (§7.2)

/// The QR popover's state: a one-time "Được gõ" share, replaced by a fresh one when its 2-minute claim
/// window passes unclaimed while the popover is open. Closing the popover revokes an unclaimed one; a
/// claimed one keeps streaming until quit. No native app yet (C14), so "Gửi tới máy đã ghép cặp" is
/// not offered.
@MainActor
final class ShellXPhoneHandoffModel: ObservableObject {
    let workspaceID: UUID
    private let controller: ShellXShareController
    private let sleeper: any ShareSleeper
    @Published private(set) var shareID: String?
    @Published private(set) var qrImage: CGImage?
    @Published private(set) var errorText: String?
    @Published private(set) var isWorking = false
    private var renewal: Task<Void, Never>?
    private var isOpen = false

    init(workspaceID: UUID, controller: ShellXShareController, sleeper: any ShareSleeper = ShareSystemSleeper()) {
        self.workspaceID = workspaceID
        self.controller = controller
        self.sleeper = sleeper
    }

    var share: ActiveShare? { shareID.flatMap { id in controller.active.first { $0.id == id } } }
    var isClaimed: Bool { !(share?.viewers.isEmpty ?? true) }
    var needsSignIn: Bool { !controller.isSignedIn }

    func signIn() { controller.presentSignIn() }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        guard !needsSignIn else { return }
        Task { await refresh() }
    }

    func close() {
        isOpen = false
        renewal?.cancel()
        renewal = nil
        if let id = shareID, !isClaimed { Task { await controller.revoke(id) } }
        shareID = nil
        qrImage = nil
    }

    /// Replaces an unclaimed code with a new one.
    func refresh() async {
        guard isOpen, !isWorking else { return }
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        if let old = shareID, !isClaimed {
            shareID = nil
            qrImage = nil
            await controller.revoke(old)
        }
        do {
            let share = try await controller.startPhoneHandoff(workspaceID: workspaceID)
            guard isOpen else { await controller.revoke(share.id); return }
            shareID = share.id
            qrImage = ShellXQRCode.makeImage(payload: share.url.absoluteString)
            scheduleRenewal(at: share.claimUntil)
        } catch {
            errorText = ShellXShareError.from(error).errorDescription
        }
    }

    private func scheduleRenewal(at deadline: Date?) {
        renewal?.cancel()
        guard let deadline else { return }
        let sleeper = self.sleeper
        renewal = Task { @MainActor [weak self] in
            do { try await sleeper.sleep(until: deadline) } catch { return }
            guard !Task.isCancelled, let self, self.isOpen, !self.isClaimed else { return }
            await self.refresh()
        }
    }
}

struct ShellXPhoneHandoffPopoverView: View {
    @ObservedObject var model: ShellXPhoneHandoffModel
    @ObservedObject var controller: ShellXShareController

    var body: some View {
        VStack(spacing: 12) {
            Text(String(localized: "share.menu.phone", defaultValue: "Continue on Phone"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShellXPalette.textHi.color)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.needsSignIn {
                ShellXShareSignInRow { model.signIn() }
            } else if model.isClaimed {
                Text(String(localized: "share.phone.connected", defaultValue: "Phone connected"))
                    .font(.system(size: 12))
                    .foregroundColor(ShellXPalette.done.color)
            } else if let image = model.qrImage {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 184, height: 184)
                    .accessibilityIdentifier("shellxShare.qr")
                Text(String(localized: "share.phone.scan", defaultValue: "Scan with your phone camera"))
                    .font(.system(size: 12))
                    .foregroundColor(ShellXPalette.text.color)
                Text(String(localized: "share.phone.oneTime", defaultValue: "One-time code, renewed every 2 minutes"))
                    .font(.system(size: 11))
                    .foregroundColor(ShellXPalette.muted.color)
            } else if model.isWorking {
                ProgressView().controlSize(.small).frame(height: 184)
            }
            if let error = model.errorText {
                ShellXShareErrorText(text: error)
                Button(String(localized: "share.retry", defaultValue: "Try Again")) {
                    Task { await model.refresh() }
                }
                .buttonStyle(ShellXSheetButtonStyle(kind: .secondary))
            }
        }
        .padding(16)
        .frame(width: 240)
        .background(ShellXPalette.raise.color)
        .environment(\.colorScheme, .dark)
    }
}
