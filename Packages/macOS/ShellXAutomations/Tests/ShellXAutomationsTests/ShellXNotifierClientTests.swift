import Foundation
import Testing
@testable import ShellXAutomations

private actor RecordedArgv {
    private(set) var calls: [[String]] = []
    func record(_ argv: [String]) { calls.append(argv) }
}

@Suite struct ShellXNotifierClientTests {
    private let helper = "/Applications/ShellX.app/Contents/Library/ShellX Notifier.app"

    private func notification() -> ShellXAutomationNotification {
        ShellXAutomationNotification(
            title: "daily-digest",
            body: "All good",
            url: URL(string: "shellx://automations/abc")!,
            group: "abc"
        )
    }

    @Test func exactArgv() async throws {
        let recorded = RecordedArgv()
        let client = ShellXNotifierClient(helperAppPath: helper) { argv in
            await recorded.record(argv)
            return 0
        }
        try await client.post(notification())
        #expect(await recorded.calls == [[
            "/usr/bin/open", "-g", "-n", "-a", helper, "--args",
            "--title", "daily-digest",
            "--body", "All good",
            "--url", "shellx://automations/abc",
            "--group", "abc",
        ]])
    }

    @Test func nonZeroExitThrows() async {
        let client = ShellXNotifierClient(helperAppPath: helper) { _ in 1 }
        await #expect(throws: ShellXNotifierError.openFailed(status: 1)) {
            try await client.post(notification())
        }
    }

    @Test func manualNotificationLinksAKnownAutomation() {
        let known = ShellXAutomationNotification(name: "daily-digest", body: "hi", automationId: "abc")
        #expect(known == ShellXAutomationNotification(title: "daily-digest", body: "hi", url: URL(string: "shellx://automations/abc")!, group: "abc"))
        let unknown = ShellXAutomationNotification(name: "my-skill", body: "hi", automationId: nil)
        #expect(unknown.url == URL(string: "shellx://automations")!)
        #expect(unknown.group == "my-skill")
        let external = ShellXAutomationNotification(name: "x", body: "", automationId: "external:my skill/../x")
        #expect(external.url.absoluteString == "shellx://automations/external:my%20skill%2F..%2Fx")
    }

    @Test func manualNotificationBodyIsTruncated() {
        let long = String(repeating: "x", count: 200)
        let n = ShellXAutomationNotification(name: "a", body: long, automationId: nil)
        #expect(n.body == String(repeating: "x", count: 180) + "…")
        let exact = String(repeating: "y", count: 180)
        #expect(ShellXAutomationNotification(name: "a", body: exact, automationId: nil).body == exact)
    }

    @Test func bannerLinksUseTheAppScheme() {
        let dev = ShellXAutomationNotification(name: "a", body: "b", automationId: "abc", urlScheme: "shellx-dev")
        #expect(dev.url.absoluteString == "shellx-dev://automations/abc")
        let panel = ShellXAutomationNotification(name: "a", body: "b", automationId: nil, urlScheme: "shellx-dev")
        #expect(panel.url.absoluteString == "shellx-dev://automations")
    }

    @Test func appSchemeComesFromTheRegisteredURLTypes() {
        let info: [String: Any] = ["CFBundleURLTypes": [
            ["CFBundleURLSchemes": ["http", "https"]],
            ["CFBundleURLSchemes": ["shellx-dev"]],
            ["CFBundleURLSchemes": ["ssh"]],
        ]]
        #expect(ShellXAppURLScheme(infoDictionary: info).scheme == "shellx-dev")
        #expect(ShellXAppURLScheme(infoDictionary: nil).scheme == "shellx")
        #expect(ShellXAppURLScheme(infoDictionary: ["CFBundleURLTypes": [["CFBundleURLSchemes": ["https"]]]]).scheme == "shellx")
    }
}
