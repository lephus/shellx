import AppKit
import SwiftUI
import WebKit

/// Hosts the bundled Automations page and connects its `shellxAutomations` bridge to a
/// ``ShellXAutomationsController``.
struct ShellXAutomationsWebView: NSViewRepresentable {
    let controller: ShellXAutomationsController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.bind(controller)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.tearDown(webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
        private static let page = WebviewsAppPage.automations
        private(set) var controller: ShellXAutomationsController
        private weak var webView: WKWebView?
        private var reloadBudget = GitGraphReloadBudget()

        init(controller: ShellXAutomationsController) {
            self.controller = controller
        }

        func makeWebView() -> WKWebView {
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
            connect(controller)
            loadShell()
            return webView
        }

        /// Switches to another controller. The page's state belongs to the previous one, so it reloads.
        func bind(_ controller: ShellXAutomationsController) {
            guard controller !== self.controller else { return }
            self.controller = controller
            connect(controller)
            loadShell()
        }

        func tearDown(_ webView: WKWebView) {
            webView.stopLoading()
            webView.configuration.userContentController.removeScriptMessageHandler(
                forName: ShellXAutomationsBridgeContract.handlerName,
                contentWorld: .page
            )
            webView.navigationDelegate = nil
            self.webView = nil
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
                let text = "Requests are accepted only from the Automations page."
                replyHandler(controller.errorReply(code: .notAllowed, message: text), nil)
                return
            }
            guard let body = message.body as? [String: Any], let method = body["method"] as? String else {
                replyHandler(controller.errorReply(code: .invalidArgument, message: "Malformed request."), nil)
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

        private func connect(_ controller: ShellXAutomationsController) {
            controller.emit = { [weak self, weak controller] event in
                // A controller this web view no longer shows must not reach its page.
                guard let self, let controller, self.controller === controller else { return }
                self.send(event)
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
}
