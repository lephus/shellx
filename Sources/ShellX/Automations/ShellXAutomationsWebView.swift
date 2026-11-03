import AppKit
import SwiftUI
import WebKit

/// Shows the Automations page that ``ShellXAutomationsWebHost`` keeps for its panel.
///
/// SwiftUI dismantles this view whenever its tab is hidden; the page lives in the host,
/// so the creator's chat and draft survive switching tabs.
struct ShellXAutomationsWebView: NSViewRepresentable {
    let host: ShellXAutomationsWebHost

    func makeNSView(context: Context) -> WKWebView {
        host.attachWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: ()) {
        // The panel owns the page; closing the panel tears it down.
    }
}

/// Owns one panel's Automations web view and connects its `shellxAutomations` bridge to
/// the panel's ``ShellXAutomationsController``.
@MainActor
final class ShellXAutomationsWebHost: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    private static let page = WebviewsAppPage.automations
    let controller: ShellXAutomationsController
    private var webView: WKWebView?
    private var reloadBudget = GitGraphReloadBudget()

    init(controller: ShellXAutomationsController) {
        self.controller = controller
    }

    /// The panel's web view, made and loaded on first use and reused afterwards.
    /// It is detached from any old view tree first, since SwiftUI attaches it again.
    func attachWebView() -> WKWebView {
        if let webView {
            webView.removeFromSuperview()
            return webView
        }
        let configuration = WKWebViewConfiguration()
        // The page and its module scripts come from the bundle through this
        // scheme, which also inflates the scripts the build deflated.
        configuration.setURLSchemeHandler(
            GitGraphURLSchemeHandler(assets: .bundled(page: Self.page)),
            forURLScheme: Self.page.scheme
        )
        configuration.userContentController.addScriptMessageHandler(
            self,
            contentWorld: .page,
            name: ShellXAutomationsBridgeContract.handlerName
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.navigationDelegate = self
#if DEBUG
        webView.isInspectable = true
#endif
        self.webView = webView
        connect()
        loadShell()
        return webView
    }

    /// Stops the page and drops the bridge; the panel is closing.
    func tearDown() {
        guard let webView else { return }
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: ShellXAutomationsBridgeContract.handlerName,
            contentWorld: .page
        )
        webView.navigationDelegate = nil
        webView.removeFromSuperview()
        self.webView = nil
        controller.emit = nil
    }

    // MARK: Bridge

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        let controller = controller
        guard message.frameInfo.isMainFrame,
              Self.page.isShellDocument(message.frameInfo.request.url) else {
            let failure = ShellXAutomationsBridgeFailure.untrustedFrame
            replyHandler(controller.errorReply(code: failure.code, message: failure.message), nil)
            return
        }
        guard let body = message.body as? [String: Any], let method = body["method"] as? String else {
            let failure = ShellXAutomationsBridgeFailure.malformedRequest
            replyHandler(controller.errorReply(code: failure.code, message: failure.message), nil)
            return
        }
        let params = body["params"] as? [String: Any] ?? [:]
        Task { @MainActor in
            replyHandler(await controller.handle(method: method, params: params), nil)
        }
    }

    // MARK: Navigation

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Only the page itself and its in-page fragments; everything else is cancelled.
        decisionHandler(Self.page.isShellDocument(navigationAction.request.url) ? .allow : .cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard reloadBudget.allowsReload(at: .now) else {
#if DEBUG
            cmuxDebugLog("automations.web.processTerminated reloadBudgetSpent")
#endif
            return
        }
        loadShell()
    }

    // MARK: Private

    private func connect() {
        controller.emit = { [weak self] event in
            self?.send(event)
        }
        controller.effectiveAppearance = { [weak self] in
            self?.webView?.effectiveAppearance ?? NSApplication.shared.effectiveAppearance
        }
    }

    private func loadShell() {
        webView?.load(URLRequest(url: Self.page.shellURL))
    }

    private func send(_ event: [String: Any]) {
        guard let webView,
              let data = try? JSONSerialization.data(withJSONObject: event),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        webView.evaluateJavaScript("window.shellxAutomations?.receive(\(json));") { _, error in
#if DEBUG
            if let error {
                cmuxDebugLog("automations.bridge.event.failed error=\(error.localizedDescription)")
            }
#else
            _ = error
#endif
        }
    }
}
