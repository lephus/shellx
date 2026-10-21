import AppKit
import Combine
import ShellXBrand
import ShellXIcons
import ShellXRemoteCore
import SwiftUI

/// ShellX: the one action path behind every share entrypoint (titlebar button, AppKit and SwiftUI
/// workspace context menus): gate check, then the popover over `ShellXShareController.shared`.
@MainActor
enum ShellXShareActions {
    enum Entry: Hashable { case share, phone }

    /// What a workspace menu shows: nothing with the gate off.
    static var menuEntries: [Entry] { ShellXShareGate.isEnabled ? [.share, .phone] : [] }

    static func title(_ entry: Entry) -> String {
        switch entry {
        case .share: return String(localized: "share.menu.share", defaultValue: "Share Workspace…")
        case .phone: return String(localized: "share.menu.phone", defaultValue: "Continue on Phone")
        }
    }

    static func icon(_ entry: Entry) -> String {
        entry == .share ? "link" : "iphone"
    }

    static func perform(_ entry: Entry, workspaceID: UUID, window: NSWindow? = nil) {
        guard ShellXShareGate.isEnabled else { return }
        ShellXSharePresenter.shared.present(entry, workspaceID: workspaceID, window: window ?? NSApp.keyWindow)
    }

    /// The titlebar button: the window's selected workspace.
    static func shareSelectedWorkspace(in window: NSWindow?) {
        guard let manager = AppDelegate.shared?.activeTabManagerForCommands(preferredWindow: window),
              let id = manager.selectedTabId else { NSSound.beep(); return }
        perform(.share, workspaceID: id, window: window)
    }

    static func workspace(id: UUID) -> Workspace? {
        AppDelegate.shared?.workspaceFor(tabId: id)
    }
}

/// Shows one share popover at a time, anchored to the window's titlebar share button (or the top of
/// the window when the titlebar has none).
@MainActor
final class ShellXSharePresenter: NSObject, NSPopoverDelegate {
    static let shared = ShellXSharePresenter()

    private let anchors = NSMapTable<NSWindow, NSView>(keyOptions: .weakMemory, valueOptions: .weakMemory)
    private var popover: NSPopover?
    private var phoneModel: ShellXPhoneHandoffModel?

    func registerAnchor(_ view: NSView) {
        guard let window = view.window else { return }
        anchors.setObject(view, forKey: window)
    }

    func present(_ entry: ShellXShareActions.Entry, workspaceID: UUID, window: NSWindow?) {
        popover?.performClose(nil)
        let controller = ShellXShareController.shared
        let content: NSViewController
        switch entry {
        case .share:
            let model = ShellXSharePopoverModel(workspaceID: workspaceID, controller: controller)
            content = NSHostingController(rootView: ShellXSharePopoverView(model: model, controller: controller))
        case .phone:
            let model = ShellXPhoneHandoffModel(workspaceID: workspaceID, controller: controller)
            phoneModel = model
            content = NSHostingController(rootView: ShellXPhoneHandoffPopoverView(model: model, controller: controller))
            model.open()
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = content
        popover.delegate = self
        self.popover = popover
        if let window, let anchor = anchors.object(forKey: window), !anchor.isHiddenOrHasHiddenAncestor {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        } else if let view = window?.contentView {
            let rect = NSRect(x: view.bounds.midX - 1, y: view.isFlipped ? 0 : view.bounds.maxY - 2, width: 2, height: 2)
            popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        } else {
            self.popover = nil
            phoneModel?.close()
            phoneModel = nil
        }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            // A popover closed by `present` replacing it must not tear down its successor.
            guard let closed = notification.object as? NSPopover, closed === popover else { return }
            phoneModel?.close()
            phoneModel = nil
            popover = nil
        }
    }
}

/// Registers its view as the window's share anchor.
struct ShellXShareAnchor: NSViewRepresentable {
    final class AnchorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            MainActor.assumeIsolated { ShellXSharePresenter.shared.registerAnchor(self) }
        }
    }

    func makeNSView(context: Context) -> NSView { AnchorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - "Chia sẻ phiên" (§7.3)

@MainActor
final class ShellXSharePopoverModel: ObservableObject {
    let workspaceID: UUID
    private let controller: ShellXShareController
    /// §7.3 defaults: "Chỉ xem", "1 giờ".
    @Published var permission: SharePermission = .view
    @Published var lifetime: ShareLifetime = .oneHour
    @Published private(set) var isWorking = false
    @Published private(set) var errorText: String?
    @Published private(set) var copied = false

    init(workspaceID: UUID, controller: ShellXShareController) {
        self.workspaceID = workspaceID
        self.controller = controller
    }

    /// The workspace's live link (QR shares are the phone popover's).
    var share: ActiveShare? {
        controller.shares(for: workspaceID).last { !$0.oneTime }
    }

    var needsSignIn: Bool { !controller.isSignedIn }

    func signIn() { controller.presentSignIn() }

    func create() async {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            _ = try await controller.share(workspaceID: workspaceID, permission: permission, lifetime: lifetime)
        } catch {
            errorText = ShellXShareError.from(error).errorDescription
        }
    }

    func copy(to pasteboard: NSPasteboard = .general) {
        guard let share else { return }
        pasteboard.clearContents()
        pasteboard.setString(share.url.absoluteString, forType: .string)
        copied = true
    }

    func revoke() async {
        guard let share else { return }
        copied = false
        errorText = nil
        if !(await controller.revoke(share.id)) {
            errorText = ShellXShareError.revokeFailed.errorDescription
        }
    }
}

enum ShellXShareStrings {
    static var title: String { String(localized: "share.title", defaultValue: "Share Workspace") }
    static var permission: String { String(localized: "share.permission.label", defaultValue: "Permission") }
    static var lifetime: String { String(localized: "share.lifetime.label", defaultValue: "Expires") }
    static var viewers: String { String(localized: "share.viewers", defaultValue: "Watching") }
    static var noViewers: String { String(localized: "share.viewers.none", defaultValue: "No one yet") }

    static func permission(_ value: SharePermission) -> String {
        switch value {
        case .view: return String(localized: "share.permission.view", defaultValue: "View only")
        case .type: return String(localized: "share.permission.type", defaultValue: "Can type")
        }
    }

    static func lifetime(_ value: ShareLifetime) -> String {
        switch value {
        case .fifteenMinutes: return String(localized: "share.lifetime.15m", defaultValue: "15 minutes")
        case .oneHour: return String(localized: "share.lifetime.1h", defaultValue: "1 hour")
        case .untilQuit: return String(localized: "share.lifetime.untilQuit", defaultValue: "Until I quit")
        }
    }
}

struct ShellXSharePopoverView: View {
    @ObservedObject var model: ShellXSharePopoverModel
    @ObservedObject var controller: ShellXShareController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ShellXShareStrings.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ShellXPalette.textHi.color)
            if model.needsSignIn {
                ShellXShareSignInRow { model.signIn() }
            } else if let share = model.share {
                linkRow(share)
                summary(share)
                viewerList(share.viewers)
                Button(String(localized: "share.revoke", defaultValue: "Revoke Link")) {
                    Task { await model.revoke() }
                }
                .buttonStyle(ShellXSheetButtonStyle(kind: .secondary))
                .accessibilityIdentifier("shellxShare.revoke")
            } else {
                options
                Button(String(localized: "share.create", defaultValue: "Create Link")) {
                    Task { await model.create() }
                }
                .buttonStyle(ShellXSheetButtonStyle(kind: .primary))
                .disabled(model.isWorking)
                .accessibilityIdentifier("shellxShare.create")
            }
            if let error = model.errorText {
                ShellXShareErrorText(text: error)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(ShellXPalette.raise.color)
        .environment(\.colorScheme, .dark)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(ShellXShareStrings.permission, selection: $model.permission) {
                ForEach([SharePermission.view, .type], id: \.self) { Text(ShellXShareStrings.permission($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker(ShellXShareStrings.lifetime, selection: $model.lifetime) {
                ForEach([ShareLifetime.fifteenMinutes, .oneHour, .untilQuit], id: \.self) {
                    Text(ShellXShareStrings.lifetime($0)).tag($0)
                }
            }
            .pickerStyle(.segmented)
        }
        .font(.system(size: 11))
        .foregroundColor(ShellXPalette.muted.color)
    }

    private func linkRow(_ share: ActiveShare) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: "shellx.pro/s/\(share.id)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(ShellXPalette.text.color)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(ShellXPalette.bg.color))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ShellXPalette.border.color, lineWidth: 1))
            Button(model.copied
                   ? String(localized: "share.copied", defaultValue: "Copied")
                   : String(localized: "share.copy", defaultValue: "Copy")) {
                model.copy()
            }
            .buttonStyle(ShellXSheetButtonStyle(kind: .primary))
            .accessibilityIdentifier("shellxShare.copy")
        }
    }

    private func summary(_ share: ActiveShare) -> some View {
        Text(verbatim: "\(ShellXShareStrings.permission(share.permission)) · \(ShellXShareStrings.lifetime(share.lifetime))")
            .font(.system(size: 11))
            .foregroundColor(ShellXPalette.muted.color)
    }

    private func viewerList(_ viewers: [ShareViewer]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ShellXShareStrings.viewers)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ShellXPalette.muted.color)
            if viewers.isEmpty {
                Text(ShellXShareStrings.noViewers)
                    .font(.system(size: 12))
                    .foregroundColor(ShellXPalette.muted.color)
            }
            ForEach(viewers, id: \.id) { viewer in
                HStack(spacing: 6) {
                    ShellXIcon.image("person.2")
                        .font(.system(size: 11))
                        .foregroundColor(ShellXPalette.primary.color)
                    Text(verbatim: viewer.label)
                        .font(.system(size: 12))
                        .foregroundColor(ShellXPalette.text.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }
}

struct ShellXShareSignInRow: View {
    let action: () -> Void

    var body: some View {
        Button(String(localized: "share.signIn", defaultValue: "Sign in to share"), action: action)
            .buttonStyle(ShellXSheetButtonStyle(kind: .primary))
            .accessibilityIdentifier("shellxShare.signIn")
    }
}

struct ShellXShareErrorText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(ShellXPalette.error.color)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
