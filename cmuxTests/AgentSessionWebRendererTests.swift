import Foundation
import Testing
import AppKit
import WebKit

#if canImport(cmux_DEV)
    @testable import cmux_DEV
#elseif canImport(cmux)
    @testable import cmux
#endif

@Suite(.serialized)
struct AgentSessionWebRendererTests {
    @Test
    @MainActor
    func testRetainedWebViewHostReportsReattachmentAfterPaneMove() {
        let firstPane = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let secondPane = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let host = AgentSessionWebHostView(frame: firstPane.bounds)
        let webView = WKWebView(frame: host.bounds)
        var reattachmentCount = 0
        host.onDidReattach = {
            reattachmentCount += 1
        }

        firstPane.addSubview(host)
        host.attachWebView(webView)
        host.removeFromSuperview()
        secondPane.addSubview(host)

        #expect(reattachmentCount == 1)
    }

    @Test
    @MainActor
    func testRetainedCoordinatorReopensPaintGateForNewHost() {
        let coordinator = AgentSessionWebRendererCoordinator()
        var firstHost: AgentSessionWebHostView? = AgentSessionWebHostView()
        let secondHost = AgentSessionWebHostView()
        let initialGeneration = coordinator.visiblePaintGeneration

        coordinator.attach(to: firstHost!)
        #expect(coordinator.visiblePaintGeneration == initialGeneration)

        firstHost = nil
        coordinator.attach(to: secondHost)
        #expect(coordinator.visiblePaintGeneration == initialGeneration + 1)

        coordinator.attach(to: secondHost)
        #expect(coordinator.visiblePaintGeneration == initialGeneration + 1)
    }

    @Test
    @MainActor
    func testTerminalCommandQueuedBeforeCloseIsRejectedAfterClose() {
        let coordinator = AgentSessionWebRendererCoordinator()
        var invoked = false
        coordinator.onRunCommand = { _ in
            invoked = true
            return ["accepted": true]
        }

        coordinator.close()

        #expect(throws: AgentSessionBridgeError.self) {
            _ = try coordinator.runTerminalCommandRequest("pwd")
        }
        #expect(!invoked)
    }

    @Test
    func testTrustedShellURLAcceptsOnlyMatchingFileURL() {
        let resources = URL(fileURLWithPath: "/tmp/cmux DEV test.app/Contents/Resources", isDirectory: true)
        let expected = AgentSessionWebRendererCoordinator.shellURL(
            rendererKind: .solid,
            resourceDirectoryURL: resources
        )
        let equivalent = resources
            .appendingPathComponent("agent-session-solid", isDirectory: true)
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("agent-session-solid", isDirectory: true)
            .appendingPathComponent("index.html", isDirectory: false)
        let otherBundledFile = resources
            .appendingPathComponent("agent-session-solid", isDirectory: true)
            .appendingPathComponent("other.html", isDirectory: false)

        expectTrue(expected.isFileURL)
        expectTrue(AgentSessionWebRendererCoordinator.isTrustedShellURL(expected, expected: expected))
        expectTrue(AgentSessionWebRendererCoordinator.isTrustedShellURL(equivalent, expected: expected))
        expectFalse(AgentSessionWebRendererCoordinator.isTrustedShellURL(otherBundledFile, expected: expected))
        expectFalse(AgentSessionWebRendererCoordinator.isTrustedShellURL(URL(string: "https://example.com"), expected: expected))
    }

    /// The build deflates the React page's module scripts, which a file URL cannot
    /// load, so the page was blank in built apps. It loads on its own scheme,
    /// whose handler inflates them.
    @Test
    func testReactRendererLoadsThroughItsScheme() {
        let resources = URL(fileURLWithPath: "/tmp/cmux DEV test.app/Contents/Resources", isDirectory: true)
        let expected = AgentSessionWebRendererCoordinator.shellURL(
            rendererKind: .react,
            resourceDirectoryURL: resources
        )
        let oldFileURL = resources
            .appendingPathComponent("markdown-viewer/webviews-app/agent-session.html", isDirectory: false)

        #expect(expected.absoluteString == "shellx-agent-session://app/agent-session.html")
        expectTrue(AgentSessionWebRendererCoordinator.isTrustedShellURL(expected, expected: expected))
        expectFalse(AgentSessionWebRendererCoordinator.isTrustedShellURL(
            URL(string: "shellx-agent-session://app/git-graph.html"), expected: expected
        ))
        expectFalse(AgentSessionWebRendererCoordinator.isTrustedShellURL(WebviewsAppPage.gitGraph.shellURL, expected: expected))
        expectFalse(AgentSessionWebRendererCoordinator.isTrustedShellURL(oldFileURL, expected: expected))
        expectFalse(AgentSessionWebRendererCoordinator.isTrustedShellURL(URL(string: "https://example.com"), expected: expected))
    }
}
