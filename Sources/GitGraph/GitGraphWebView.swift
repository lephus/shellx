import AppKit
import SwiftUI
import WebKit

/// Hosts the bundled Git Graph page and connects its `shellxGitGraph` bridge to a
/// ``GitGraphController``.
struct GitGraphWebView: NSViewRepresentable {
    let controller: GitGraphController

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
        private(set) var controller: GitGraphController
        private weak var webView: WKWebView?
        private var trustedShellURL: URL?

        init(controller: GitGraphController) {
            self.controller = controller
        }

        func makeWebView() -> WKWebView {
            let configuration = WKWebViewConfiguration()
            configuration.userContentController.addScriptMessageHandler(
                self,
                contentWorld: .page,
                name: GitGraphBridgeContract.handlerName
            )
            // The bundled page is a module script loaded from a file URL. WebKit blocks
            // those as cross-origin unless file-to-file access is allowed. Navigation is
            // limited to the trusted shell, and the page renders repository text as text.
            configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
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
        func bind(_ controller: GitGraphController) {
            guard controller !== self.controller else { return }
            self.controller = controller
            connect(controller)
            loadShell()
        }

        func tearDown(_ webView: WKWebView) {
            webView.stopLoading()
            webView.configuration.userContentController.removeScriptMessageHandler(
                forName: GitGraphBridgeContract.handlerName,
                contentWorld: .page
            )
            webView.navigationDelegate = nil
            self.webView = nil
            trustedShellURL = nil
        }

        // MARK: Bridge

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage,
            replyHandler: @escaping (Any?, String?) -> Void
        ) {
            let controller = controller
            guard message.frameInfo.isMainFrame,
                  Self.isShellDocument(message.frameInfo.request.url, trustedShellURL: trustedShellURL) else {
                let message = "Requests are accepted only from the Git Graph page."
                replyHandler(controller.errorReply(code: .notAllowed, message: message), nil)
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
            let isShell = Self.isShellDocument(navigationAction.request.url, trustedShellURL: trustedShellURL)
            decisionHandler(isShell ? .allow : .cancel)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            loadShell()
        }

#if DEBUG
        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            cmuxDebugLog("gitGraph.web.didFailProvisional error=\(error.localizedDescription)")
        }
#endif

        /// True for the bundled page itself and for in-page fragments of it.
        nonisolated static func isShellDocument(_ url: URL?, trustedShellURL: URL?) -> Bool {
            if AgentSessionWebRendererCoordinator.isTrustedShellURL(url, expected: trustedShellURL) {
                return true
            }
            guard let url, url.fragment != nil,
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return false
            }
            components.fragment = nil
            return AgentSessionWebRendererCoordinator.isTrustedShellURL(components.url, expected: trustedShellURL)
        }

        // MARK: Private

        private func connect(_ controller: GitGraphController) {
            controller.eventSink = { [weak self, weak controller] event in
                // A controller this web view no longer shows must not reach its page.
                guard let self, let controller, self.controller === controller else { return }
                self.send(event)
            }
            controller.effectiveAppearance = { [weak self] in
                self?.webView?.effectiveAppearance ?? NSApplication.shared.effectiveAppearance
            }
        }

        private func loadShell() {
            guard let webView, let resourceURL = Bundle.main.resourceURL else { return }
            let shellURL = resourceURL.appendingPathComponent(
                "markdown-viewer/webviews-app/git-graph.html",
                isDirectory: false
            )
            trustedShellURL = shellURL
            webView.loadFileURL(shellURL, allowingReadAccessTo: resourceURL)
        }

        private func send(_ event: [String: Any]) {
            guard let webView,
                  let data = try? JSONSerialization.data(withJSONObject: event),
                  let json = String(data: data, encoding: .utf8) else {
                return
            }
            webView.evaluateJavaScript("window.shellxGitGraph?.receive(\(json));") { _, error in
#if DEBUG
                if let error {
                    cmuxDebugLog("gitGraph.bridge.event.failed error=\(error.localizedDescription)")
                }
#else
                _ = error
#endif
            }
        }
    }
}
