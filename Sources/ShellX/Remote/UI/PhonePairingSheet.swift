import AppKit
import ShellXBrand
import ShellXIcons
import ShellXRemoteCore
import SwiftUI

/// "Pair iPhone": the QR a phone scans, then the phone's request for the person at this Mac to allow or
/// deny, and the phones paired so far, each with Remove. Allow is never the default button, so Return
/// cannot let a phone in. Dark only, flat fills, 1 px borders, like `RequestAccessSheet`.
struct PhonePairingSheet: View {
    @ObservedObject var coordinator: ShellXPhonePairingCoordinator
    let onClose: () -> Void
    @State private var qrCache = PhonePairingQRCache()

    static var title: String {
        String(localized: "remote.phonePairing.title", defaultValue: "Pair iPhone")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Self.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(ShellXPalette.textHi.color)
                .lineLimit(1)
                .truncationMode(.tail)
            if !coordinator.isReady {
                notReady
            } else if !coordinator.candidates.isEmpty {
                ForEach(coordinator.candidates) { candidate in
                    candidateCard(candidate)
                }
            } else {
                qrBlock
            }
            if coordinator.isReady {
                phonesSection
            }
            if let error = coordinator.errorText {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(ShellXPalette.error.color)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(String(localized: "common.close", defaultValue: "Close")) {
                    onClose()
                }
                .buttonStyle(ShellXSheetButtonStyle(kind: .secondary))
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
        .background(ShellXPalette.raise.color)
        .environment(\.colorScheme, .dark)
    }

    /// Why no QR shows: signed out, where to sign in; otherwise that the Mac is not serving yet.
    private var notReady: some View {
        Text(coordinator.needsSignIn
            ? String(localized: "remote.phonePairing.signInFirst",
                     defaultValue: "Sign in under Settings › Account to pair an iPhone with this Mac.")
            : String(localized: "remote.phonePairing.notReady", defaultValue: "This Mac is not ready to serve phones yet"))
            .font(.system(size: 12))
            .foregroundColor(ShellXPalette.text.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card)
    }

    /// The QR over its own white quiet zone, or a spinner while the offer is being made.
    private var qrBlock: some View {
        VStack(spacing: 10) {
            if let offer = coordinator.offer, let image = qrCache.image(for: offer.uri) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 184, height: 184)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityIdentifier("shellxPhonePairing.qr")
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 184, height: 184)
            }
            Text(String(localized: "remote.phonePairing.scan", defaultValue: "Scan this code with the ShellX app on your iPhone"))
                .font(.system(size: 12))
                .foregroundColor(ShellXPalette.text.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func candidateCard(_ candidate: ShellXPhonePairingCoordinator.Candidate) -> some View {
        let busy = coordinator.busy.contains(candidate.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ShellXIcon.image(coolicon: "Mobile")
                    .font(.system(size: 16))
                    .foregroundColor(ShellXPalette.primary.color)
                    .frame(width: 18, height: 18)
                Text(String(
                    format: String(localized: "remote.phonePairing.request", defaultValue: "%@ wants to control this Mac"),
                    ShellXPhonePairingCoordinator.displayName(candidate.deviceName)
                ))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShellXPalette.textHi.color)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if busy {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(String(localized: "remote.phonePairing.deny", defaultValue: "Deny")) {
                    Task { await coordinator.deny(candidate.id) }
                }
                .buttonStyle(ShellXSheetButtonStyle(kind: .secondary))
                .disabled(busy)
                // Deliberately not the default action: allowing a phone always takes a click. While any
                // phone is being allowed, every Allow waits: one QR pairs one phone.
                Button(String(localized: "remote.phonePairing.allow", defaultValue: "Allow")) {
                    Task { try? await coordinator.approve(candidate.id) }
                }
                .buttonStyle(ShellXSheetButtonStyle(kind: .primary))
                .disabled(coordinator.approvingID != nil)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private var phonesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "remote.phonePairing.paired", defaultValue: "Paired phones"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ShellXPalette.muted.color)
                .lineLimit(1)
            if coordinator.phones.isEmpty {
                if coordinator.phonesListed {
                    Text(String(localized: "remote.phonePairing.noPhones", defaultValue: "No phones yet"))
                        .font(.system(size: 12))
                        .foregroundColor(ShellXPalette.muted.color)
                        .lineLimit(1)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(coordinator.phones.enumerated()), id: \.element.grantID) { index, phone in
                        if index > 0 {
                            Rectangle()
                                .fill(ShellXPalette.line.color)
                                .frame(height: 1)
                        }
                        phoneRow(phone)
                    }
                }
                .background(card)
            }
        }
    }

    private func phoneRow(_ phone: PairedPhone) -> some View {
        HStack(spacing: 8) {
            ShellXIcon.image(coolicon: "Mobile")
                .font(.system(size: 13))
                .foregroundColor(ShellXPalette.muted.color)
                .frame(width: 16, height: 16)
            Text(ShellXPhonePairingCoordinator.displayName(phone.deviceName))
                .font(.system(size: 12))
                .foregroundColor(ShellXPalette.text.color)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Button(String(localized: "remote.phonePairing.remove", defaultValue: "Remove")) {
                Task { try? await coordinator.revoke(phone) }
            }
            .buttonStyle(ShellXSheetButtonStyle(kind: .secondary))
            .disabled(coordinator.busy.contains(phone.grantID))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(ShellXPalette.panel.color)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(ShellXPalette.border.color, lineWidth: 1)
            )
    }
}

/// The QR image for the offer on screen, rebuilt only when the offer changes. Never logged: the payload
/// holds the one-time pairing code.
@MainActor
final class PhonePairingQRCache {
    private var payload: String?
    private var image: CGImage?

    func image(for payload: String) -> CGImage? {
        if payload != self.payload {
            self.payload = payload
            image = ShellXQRCode.makeImage(payload: payload)
        }
        return image
    }
}

/// Shows one phone pairing sheet at a time on the main window, like `RequestAccessSheetPresenter`. The
/// sheet's coordinator is open exactly while the sheet is up.
@MainActor
final class PhonePairingSheetPresenter {
    static let shared = PhonePairingSheetPresenter()

    private var sheet: CloudSheetWindow?
    private var hostWindow: NSWindow?
    /// The open sheet's coordinator; the DEBUG pairing methods go through it.
    private(set) var coordinator: ShellXPhonePairingCoordinator?

    private init() {}

    /// Shows the sheet, or brings the open one back.
    ///
    /// - Parameters:
    ///   - bringToFront: False for the DEBUG socket path: an open sheet is left where it is, and a new
    ///     one is attached to the main window without activating the app.
    ///   - makeCoordinator: Builds the coordinator for a new sheet.
    /// - Returns: The open sheet's coordinator, or nil when none could be made.
    @discardableResult
    func present(bringToFront: Bool = true,
                 makeCoordinator: () -> ShellXPhonePairingCoordinator?) -> ShellXPhonePairingCoordinator? {
        if let coordinator, let window = sheet?.window {
            if bringToFront { (hostWindow ?? window).makeKeyAndOrderFront(nil) }
            return coordinator
        }
        guard let newCoordinator = makeCoordinator() else { return nil }
        let newSheet = CloudSheetWindow(rootView: PhonePairingSheet(coordinator: newCoordinator, onClose: { [weak self] in
            self?.dismiss()
        }))
        let window = newSheet.window
        window.styleMask = [.titled]
        window.title = PhonePairingSheet.title
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        coordinator = newCoordinator
        sheet = newSheet
        newCoordinator.open()

        let host = NSApp.cmuxMainWindowForModalPresentation(preferring: NSApp.keyWindow)
        if let host, host.attachedSheet == nil {
            hostWindow = host
            newSheet.beginSheet(on: host)
        } else {
            hostWindow = nil
            newSheet.orderFrontFloating()
        }
        return newCoordinator
    }

    func dismiss() {
        coordinator?.close()
        coordinator = nil
        guard let window = sheet?.window else { return }
        if let host = hostWindow, host.attachedSheet === window {
            host.endSheet(window)
        }
        window.orderOut(nil)
        sheet = nil
        hostWindow = nil
    }
}
