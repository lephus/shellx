import Foundation
import Testing
@testable import CmuxBrowser

@Suite struct BrowserHistoryLocationTests {
    @Test func foldsDebugAndStagingNamespaces() {
        #expect(BrowserHistoryLocation.normalizedNamespace(bundleIdentifier: "pro.shellx.desktop.debug.my-tag") == "pro.shellx.desktop.debug")
        #expect(BrowserHistoryLocation.normalizedNamespace(bundleIdentifier: "pro.shellx.desktop.staging.rc") == "pro.shellx.desktop.staging")
        #expect(BrowserHistoryLocation.normalizedNamespace(bundleIdentifier: "pro.shellx.desktop") == "pro.shellx.desktop")
    }

    @Test func historyFileURLNestsUnderNamespace() {
        let root = URL(fileURLWithPath: "/tmp/appsupport", isDirectory: true)
        let location = BrowserHistoryLocation(applicationSupportDirectory: root, bundleIdentifier: "pro.shellx.desktop.debug.tag")
        #expect(location.namespace == "pro.shellx.desktop.debug")
        #expect(location.historyFileURL.path == "/tmp/appsupport/pro.shellx.desktop.debug/browser_history.json")
    }

    @Test func legacyURLPresentOnlyWhenNamespaceDiffers() {
        let root = URL(fileURLWithPath: "/tmp/appsupport", isDirectory: true)
        let tagged = BrowserHistoryLocation(applicationSupportDirectory: root, bundleIdentifier: "pro.shellx.desktop.debug.tag")
        #expect(tagged.legacyTaggedHistoryFileURL?.path == "/tmp/appsupport/pro.shellx.desktop.debug.tag/browser_history.json")

        let prod = BrowserHistoryLocation(applicationSupportDirectory: root, bundleIdentifier: "pro.shellx.desktop")
        #expect(prod.legacyTaggedHistoryFileURL == nil)
    }
}
