import AppKit
import CmuxSettings
import Foundation
import SwiftUI
import Testing
@testable import CmuxSettingsUI

/// Settings › Mobile in a host that pairs phones through ShellX Link: one "Pair iPhone" row whose button opens
/// the pairing QR, and none of the cmux rows (iOS pairing host, port, display name, folder access, browser
/// tunnel, phone push), on screen or in search. A cmux host keeps its rows.
@MainActor
@Suite(.serialized)
struct MobileSectionShellXLinkTests {
    final class PairingHost: SettingsHostActions {
        let pairsPhonesThroughShellXLink: Bool
        var phonePairingOpens = 0
        var mobilePairingWindowOpens = 0

        init(shellXLink: Bool) { pairsPhonesThroughShellXLink = shellXLink }

        func openPhonePairing() { phonePairingOpens += 1 }
        func openMobilePairingWindow() { mobilePairingWindowOpens += 1 }

        func clearBrowserHistory() {}
        func openConfigInExternalEditor() {}
        func sendFeedback() {}
        func sendTestNotification() {}
        func openSystemNotificationSettings() {}
        func restartApp() {}
        func openBrowserImportFlow() {}
        func requestNotificationAuthorization() {}
        func openTerminalConfigWindow() {}
        func previewNotificationSound(value: String, customFilePath: String) {}
    }

    /// The section hosted the way the Settings window lays it out, laid out once.
    static func host(_ actions: PairingHost) -> NSWindow {
        let defaults = UserDefaults(suiteName: "MobileSectionShellXLinkTests.\(UUID().uuidString)")!
        let section = MobileSection(
            defaultsStore: UserDefaultsSettingsStore(defaults: defaults),
            catalog: SettingCatalog(),
            hostActions: actions
        )
        // In-process there is no assistive client to switch SwiftUI's accessibility output on, so the
        // hierarchy asks for it directly (as `MachinesListStatusToolbarRowTests` in the app tests does).
        let root = VStack(spacing: 0) { section }
            .frame(width: 760)
            .environment(\.accessibilityEnabled, true)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.setContentSize(NSSize(width: 760, height: 900))
        window.contentView?.layoutSubtreeIfNeeded()
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderBack(nil)
        return window
    }

    /// Reads an attribute the way an assistive client does: SwiftUI nodes answer either the modern getter or
    /// the legacy attribute API.
    static func attribute(_ attribute: NSAccessibility.Attribute, getter: String, of element: NSObject) -> Any? {
        let modern = NSSelectorFromString(getter)
        if element.responds(to: modern), let value = element.perform(modern)?.takeUnretainedValue() {
            return value
        }
        let names = NSSelectorFromString("accessibilityAttributeNames")
        let legacy = NSSelectorFromString("accessibilityAttributeValue:")
        guard element.responds(to: names), element.responds(to: legacy),
              let attributes = element.perform(names)?.takeUnretainedValue() as? [String],
              attributes.contains(attribute.rawValue) else { return nil }
        return element.perform(legacy, with: attribute.rawValue)?.takeUnretainedValue()
    }

    /// Every accessibility element under `root`, found through accessibility children (SwiftUI draws bordered
    /// buttons itself, with no AppKit view), breadth first.
    static func accessibilityElements(under root: NSView) -> [NSObject] {
        var found: [NSObject] = []
        var pending: [NSObject] = [root]
        var visited = Set<ObjectIdentifier>()
        while !pending.isEmpty {
            let element = pending.removeFirst()
            guard visited.insert(ObjectIdentifier(element)).inserted else { continue }
            if element !== root { found.append(element) }
            let children = attribute(.children, getter: "accessibilityChildren", of: element) as? [Any]
            pending += NSAccessibility.unignoredChildren(from: children ?? []).compactMap { $0 as? NSObject }
        }
        return found
    }

    static func identifier(_ element: NSObject) -> String? {
        attribute(.identifier, getter: "accessibilityIdentifier", of: element) as? String
    }

    /// The accessibility identifiers of the Mobile section's controls on screen.
    static func controlIdentifiers(in window: NSWindow) -> [String] {
        guard let view = window.contentView else { return [] }
        return accessibilityElements(under: view).compactMap(identifier).filter { $0.hasPrefix("SettingsMobile") }
    }

    /// Presses the control `id` the way VoiceOver does, through the modern method or the legacy action.
    static func press(_ id: String, in window: NSWindow) -> Bool {
        guard let view = window.contentView,
              let element = accessibilityElements(under: view).first(where: { identifier($0) == id }) else { return false }
        let modern = NSSelectorFromString("accessibilityPerformPress")
        if element.responds(to: modern) {
            _ = element.perform(modern)
            return true
        }
        let legacy = NSSelectorFromString("accessibilityPerformAction:")
        guard element.responds(to: legacy) else { return false }
        _ = element.perform(legacy, with: NSAccessibility.Action.press.rawValue)
        return true
    }

    /// The AppKit controls under `view`: SwiftUI hosts its toggles, text fields and menus in them.
    static func appKitControls(in view: NSView?) -> [NSControl] {
        guard let view else { return [] }
        if let control = view as? NSControl { return [control] }
        return view.subviews.flatMap { appKitControls(in: $0) }
    }

    /// cmux rows whose controls carry an identifier in the accessibility tree. Its text fields and menus
    /// expose none there; they are AppKit controls, counted by ``appKitControls(in:)``.
    static let cmuxControlIdentifiers: Set<String> = [
        "SettingsMobileIOSPairingHostToggle",
        "SettingsMobilePhonePushForwardingToggle",
        "SettingsMobilePhonePushHideContentToggle",
        "SettingsMobilePairDeviceButton",
        "SettingsMobilePairingPortApplyButton",
        "SettingsMobileBrowserTunnelAllowOtherHostsToggle",
    ]

    @Test func shellXLinkHostShowsOnlyThePairingButton() {
        let window = Self.host(PairingHost(shellXLink: true))
        defer { window.orderOut(nil) }
        #expect(Self.controlIdentifiers(in: window) == ["SettingsMobilePairIPhoneButton"])
        // No toggle, port or name field, or menu of the cmux rows.
        #expect(Self.appKitControls(in: window.contentView).isEmpty)
    }

    @Test func pairingButtonOpensThePhonePairingSheet() {
        let host = PairingHost(shellXLink: true)
        let window = Self.host(host)
        defer { window.orderOut(nil) }
        #expect(Self.press("SettingsMobilePairIPhoneButton", in: window))
        #expect(host.phonePairingOpens == 1)
        #expect(host.mobilePairingWindowOpens == 0)
    }

    @Test func cmuxHostKeepsItsRows() {
        let host = PairingHost(shellXLink: false)
        let window = Self.host(host)
        defer { window.orderOut(nil) }
        let shown = Set(Self.controlIdentifiers(in: window))
        #expect(shown.isSuperset(of: Self.cmuxControlIdentifiers))
        #expect(!shown.contains("SettingsMobilePairIPhoneButton"))
        #expect(Self.appKitControls(in: window.contentView).count >= 8)
        #expect(Self.press("SettingsMobilePairDeviceButton", in: window))
        #expect(host.mobilePairingWindowOpens == 1)
        #expect(host.phonePairingOpens == 0)
    }

    // MARK: Search

    static let hiddenMobileEntryIDs = [
        "setting:mobile:iOSPairingHost",
        "setting:mobile:iOSPairingPort",
        "setting:mobile:iOSPairingDisplayName",
        "setting:mobile:artifactFolderAccess",
        "setting:mobile:browserTunnelAllowOtherHosts",
        "setting:mobile:phone-push-forwarding",
        "setting:mobile:phone-push-mode",
        "setting:mobile:phone-push-hide-content",
    ]

    static func runtime(_ host: PairingHost) -> SettingsRuntime {
        let suite = "MobileSectionShellXLinkTests.\(UUID().uuidString)"
        return SettingsRuntime(
            catalog: SettingCatalog(),
            userDefaultsStore: UserDefaultsSettingsStore(defaults: UserDefaults(suiteName: suite)!),
            jsonStore: JSONConfigStore(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
            ),
            secretStore: SecretFileStore(
                baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            ),
            errorLog: SettingsErrorLog(),
            hostActions: host
        )
    }

    @Test func shellXLinkSearchOffersOnlyThePairingRow() throws {
        let index = Self.runtime(PairingHost(shellXLink: true)).searchIndex
        let mobile = index.entries.filter { $0.id.hasPrefix("setting:mobile:") }.map(\.id)
        #expect(mobile == ["setting:mobile:pairDevice"])
        let pairing = try #require(index.entries.first { $0.id == "setting:mobile:pairDevice" })
        #expect(pairing.title == "Pair Phone")
        #expect(index.match("qr code").contains { $0.id == pairing.id })
        #expect(index.match("pair iphone").first?.id == pairing.id)
        #expect(!index.match("pairing port").contains { $0.id == "setting:mobile:iOSPairingPort" })
    }

    /// The Mobile section's own search words follow its rows: a ShellX Link host forwards no notifications to
    /// the phone, so searching for that never lands on Mobile.
    @Test func shellXLinkSearchHasNoPhonePushWords() {
        let index = Self.runtime(PairingHost(shellXLink: true)).searchIndex
        for query in ["push notifications", "forwarding"] {
            let mobile = index.match(query).map(\.id).filter { $0 == "section:mobile" || $0.hasPrefix("setting:mobile:") }
            #expect(mobile.isEmpty, "\"\(query)\" finds \(mobile)")
        }
        // The Pair iPhone row's long text still holds "alerts" as a scattered subsequence, the matcher's last
        // fallback for any row; the section itself no longer offers the word.
        #expect(!index.match("alerts").contains { $0.id == "section:mobile" })
        #expect(index.match("iphone").contains { $0.id == "section:mobile" })
    }

    @Test func cmuxSearchKeepsThePhonePushWords() {
        let index = Self.runtime(PairingHost(shellXLink: false)).searchIndex
        for query in ["push notifications", "forwarding", "alerts"] {
            #expect(index.match(query).contains { $0.id == "section:mobile" }, "\"\(query)\" left cmux Mobile")
        }
    }

    @Test func cmuxSearchKeepsTheMobileRows() {
        let index = Self.runtime(PairingHost(shellXLink: false)).searchIndex
        let ids = Set(index.entries.map(\.id))
        for id in Self.hiddenMobileEntryIDs { #expect(ids.contains(id), "\(id) left cmux search") }
        #expect(index.entries.first { $0.id == "setting:mobile:pairDevice" }?.title == "Mobile Pairing")
    }
}
