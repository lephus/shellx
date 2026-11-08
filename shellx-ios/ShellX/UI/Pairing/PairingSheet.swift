import ShellXAppCore
import SwiftUI
import UIKit

/// The "Pair a Mac" sheet: scan the Mac's QR code (or paste its code), confirm the Mac's name,
/// wait for Allow on the Mac, done. Closing the sheet at any step cancels the attempt.
struct PairingSheet<Flow: PairingFlow>: View {
    let model: Flow
    let close: () -> Void
    var title = String(localized: "pairing.title")
    var intro: String? = nil

    @State private var camera = CameraAccess.current()
    @Environment(\.openURL) private var openURL

    var body: some View {
        PairingSheetContent(
            step: model.step, camera: camera,
            title: title, intro: intro,
            actions: PairingSheetContent.Actions(
                scanned: { model.begin(uri: $0) },
                paste: { model.begin(uri: PairingPaste.take(from: .general)) },
                confirm: { Task { await model.confirm() } },
                retry: { model.cancel() },
                close: close,
                openSettings: {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }))
            // Ask for the camera when the scanner is about to show, not before (HIG: Privacy): a
            // sheet opened by a link starts at the confirmation and may never need it.
            .task(id: model.step == .idle) {
                if model.step == .idle, camera == .notDetermined { camera = await CameraAccess.request() }
            }
            // Back from Settings with the camera allowed (or taken away).
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                camera = CameraAccess.current()
            }
            .onChange(of: model.step) { _, step in
                if let announcement = PairingSheetContent.announcement(for: step) {
                    AccessibilityNotification.Announcement(announcement).post()
                }
            }
    }
}

/// What the pairing sheet shows for one step; no model, so render tests can show every step.
struct PairingSheetContent: View {
    struct Actions {
        var scanned: (String) -> Void = { _ in }
        var paste: () -> Void = {}
        var confirm: () -> Void = {}
        /// Back to scanning after a failure.
        var retry: () -> Void = {}
        /// Closes the sheet (and cancels whatever is under way).
        var close: () -> Void = {}
        var openSettings: () -> Void = {}
    }

    let step: PairingModel.Step
    let camera: CameraAccess
    var title = String(localized: "pairing.title")
    /// Body text at the top of the `.idle` step, above the camera.
    var intro: String? = nil
    var actions = Actions()

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
            }
            .background(Color.appBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close"), action: actions.close)
                        .accessibilityIdentifier("pairing.close")
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .idle:
            PairingScanStep(camera: camera, intro: intro, actions: actions)
        case let .confirm(machineName):
            PairingMessage(
                symbol: "laptopcomputer.and.iphone", tint: Color("AccentText"),
                title: String(localized: "pairing.confirm.title \(machineName)"),
                detail: String(localized: "pairing.confirm.message")
            ) {
                Button(action: actions.confirm) {
                    Text(LocalizedStringResource("pairing.confirm.button"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("pairing.confirm")
                Button(action: actions.close) {
                    Text(LocalizedStringResource("common.cancel"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("pairing.cancel")
            }
        case let .waitingForMac(machineName):
            PairingMessage(
                progress: true, tint: Color("AccentText"),
                title: String(localized: "pairing.waiting \(machineName)"),
                detail: String(localized: "pairing.waiting.detail")
            ) {
                Button(action: actions.close) {
                    Text(LocalizedStringResource("common.cancel"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pairing.cancel")
            }
        case let .paired(machineName):
            PairingMessage(
                symbol: "checkmark.circle.fill", tint: Color("StatusDone"),
                title: String(localized: "pairing.paired \(machineName)"), detail: nil
            ) {
                Button(action: actions.close) {
                    Text(LocalizedStringResource("pairing.done"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("pairing.done")
            }
        case let .failed(failure):
            PairingMessage(
                symbol: "exclamationmark.triangle.fill", tint: Color("StatusError"),
                title: Self.message(for: failure), detail: nil
            ) {
                Button(action: actions.retry) {
                    Text(LocalizedStringResource("pairing.retry"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("pairing.retry")
            }
        }
    }

    static func message(for failure: PairingFailure) -> String {
        switch failure {
        case .notShellXCode: String(localized: "pairing.error.notShellXCode")
        case .needsUpdate: String(localized: "pairing.error.needsUpdate")
        case .damagedCode: String(localized: "pairing.error.damagedCode")
        case .denied: String(localized: "pairing.error.denied")
        case .expired: String(localized: "pairing.error.expired")
        case .otherAccount: String(localized: "pairing.error.otherAccount")
        case .network: String(localized: "pairing.error.network")
        case let .server(code): String(localized: "pairing.error.server \(code)")
        }
    }

    /// What VoiceOver says when the sheet moves to `step`.
    static func announcement(for step: PairingModel.Step) -> String? {
        switch step {
        case .idle, .confirm: nil
        case let .waitingForMac(machineName): String(localized: "pairing.waiting \(machineName)")
        case let .paired(machineName): String(localized: "pairing.paired \(machineName)")
        case let .failed(failure): message(for: failure)
        }
    }
}

/// The first step: the camera (or why there is none), the instructions, and the paste fallback.
private struct PairingScanStep: View {
    let camera: CameraAccess
    let intro: String?
    let actions: PairingSheetContent.Actions

    /// Fresh each time the scanner shows, so the code that was just cancelled can be scanned again.
    @State private var filter = PairingScanFilter()
    @State private var sawOtherCode = false
    @State private var scans = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let intro {
                Text(intro)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pairing.intro")
            }
            switch camera {
            case .authorized, .notDetermined:
                viewfinder
                if sawOtherCode {
                    Label(String(localized: "pairing.error.notShellXCode"), systemImage: "qrcode")
                        .font(.callout)
                        .foregroundStyle(Color("StatusNeedsYou"))
                        .accessibilityIdentifier("pairing.otherCode")
                }
            case .denied:
                notice(symbol: "video.slash", text: String(localized: "pairing.camera.denied"))
                Button(action: actions.openSettings) {
                    Text(LocalizedStringResource("pairing.camera.openSettings"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("pairing.openSettings")
            case .unavailable:
                notice(symbol: "camera", text: String(localized: "pairing.camera.unavailable"))
            }

            Text(LocalizedStringResource("pairing.instructions"))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: actions.paste) {
                Label(String(localized: "pairing.paste"), systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(Color("AccentText"))
            .accessibilityIdentifier("pairing.paste")
        }
        .sensoryFeedback(.selection, trigger: scans)
    }

    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Color.black)
            if camera == .authorized {
                QRScannerView(onCode: scanned)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                ProgressView().tint(.white)
            }
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 3)
                .padding(48)
                .accessibilityHidden(true)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringResource("pairing.camera.label")))
        .accessibilityIdentifier("pairing.scanner")
    }

    private func notice(symbol: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func scanned(_ payload: String) {
        switch filter.accept(payload) {
        case let .pairing(code):
            scans += 1
            actions.scanned(code)
        case .notShellX:
            sawOtherCode = true
        case .ignored:
            break
        }
    }
}

/// A centred step of the sheet: a symbol (or a spinner), a title, an optional detail, buttons.
private struct PairingMessage<Buttons: View>: View {
    var symbol: String?
    var progress = false
    let tint: Color
    let title: String
    let detail: String?
    @ViewBuilder let buttons: () -> Buttons
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 56

    init(
        symbol: String? = nil, progress: Bool = false, tint: Color, title: String, detail: String?,
        @ViewBuilder buttons: @escaping () -> Buttons
    ) {
        self.symbol = symbol
        self.progress = progress
        self.tint = tint
        self.title = title
        self.detail = detail
        self.buttons = buttons
    }

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if progress {
                    ProgressView().controlSize(.large)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: symbolSize))
                        .foregroundStyle(tint)
                }
            }
            .frame(minHeight: symbolSize)
            .accessibilityHidden(true)
            Text(verbatim: title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("pairing.message")
            if let detail {
                Text(verbatim: detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 8) { buttons() }
                .padding(.top, 8)
        }
        .padding(.top, 32)
        .frame(maxWidth: .infinity)
    }
}
