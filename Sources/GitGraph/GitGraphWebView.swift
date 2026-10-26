import AppKit
import SwiftUI
import WebKit

/// How often the page may reload after its web content process dies: at most
/// ``maximumReloads`` within ``window``. A page that keeps crashing then stays as
/// it is instead of reloading forever.
struct GitGraphReloadBudget {
    var maximumReloads = 3
    var window: Duration = .seconds(60)
    private var reloads: [ContinuousClock.Instant] = []

    /// Records a reload at `now` and returns true, or returns false once the
    /// window already holds ``maximumReloads`` reloads.
    mutating func allowsReload(at now: ContinuousClock.Instant) -> Bool {
        reloads.removeAll { $0.duration(to: now) >= window }
        guard reloads.count < maximumReloads else { return false }
        reloads.append(now)
        return true
    }
}

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
        private var reloadBudget = GitGraphReloadBudget()

        init(controller: GitGraphController) {
            self.controller = controller
        }

        func makeWebView() -> WKWebView {
            let configuration = WKWebViewConfiguration()
            // The page and its module scripts come from the bundle through this
            // scheme, which also inflates the scripts the build deflated.
            configuration.setURLSchemeHandler(
                GitGraphURLSchemeHandler(),
                forURLScheme: GitGraphURLSchemeHandler.scheme
            )
            configuration.userContentController.addScriptMessageHandler(
                self,
                contentWorld: .page,
                name: GitGraphBridgeContract.handlerName
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
        }

        // MARK: Bridge

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage,
            replyHandler: @escaping (Any?, String?) -> Void
        ) {
            let controller = controller
            guard message.frameInfo.isMainFrame,
                  GitGraphURLSchemeHandler.isShellDocument(message.frameInfo.request.url) else {
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
            // Only the page itself and its in-page fragments; everything else is cancelled.
            let isShell = GitGraphURLSchemeHandler.isShellDocument(navigationAction.request.url)
            decisionHandler(isShell ? .allow : .cancel)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard reloadBudget.allowsReload(at: .now) else {
#if DEBUG
                cmuxDebugLog("gitGraph.web.processTerminated reloadBudgetSpent")
#endif
                return
            }
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
            webView?.load(URLRequest(url: GitGraphURLSchemeHandler.shellURL))
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
