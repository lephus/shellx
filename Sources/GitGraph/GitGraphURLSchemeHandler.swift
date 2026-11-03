import Foundation
import WebKit

/// A page in the bundle's `markdown-viewer/webviews-app` folder, served on its own
/// scheme by ``GitGraphURLSchemeHandler``.
struct WebviewsAppPage: Equatable, Sendable {
    let scheme: String
    let host = "app"
    /// The page's HTML file, such as `/git-graph.html`.
    let shellPath: String

    static let gitGraph = WebviewsAppPage(scheme: "shellx-git-graph", shellPath: "/git-graph.html")
    /// The Automations panel.
    static let automations = WebviewsAppPage(scheme: "shellx-automations", shellPath: "/automations.html")
    /// The React agent session renderer.
    static let agentSession = WebviewsAppPage(scheme: "shellx-agent-session", shellPath: "/agent-session.html")

    /// The page itself, such as `shellx-git-graph://app/git-graph.html`.
    var shellURL: URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = shellPath
        // A literal scheme, host and path always form a URL.
        return components.url!
    }

    /// True for the page itself and for in-page fragments of it: the scheme, the
    /// host and ``shellPath``, with no port, credentials or query.
    func isShellDocument(_ url: URL?) -> Bool {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme == scheme
            && components.host == host
            && components.port == nil
            && components.user == nil
            && components.password == nil
            && components.percentEncodedPath == shellPath
            && components.query == nil
    }
}

/// Serves a bundled webviews-app page on its own scheme: the Git Graph page on
/// `shellx-git-graph://app/` and the React agent session on `shellx-agent-session://app/`.
///
/// Neither page can load from a file URL: WebKit blocks its module scripts there
/// as cross-origin, and the build deflates them. Each web view gets its own
/// handler. WebKit calls it on the main actor and every ``WKURLSchemeTask``
/// call stays there; ``GitGraphPageAssets`` reads and inflates files on a
/// detached task, and a task WebKit stopped is never called again.
@MainActor
final class GitGraphURLSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = WebviewsAppPage.gitGraph.scheme
    nonisolated static let host = WebviewsAppPage.gitGraph.host
    nonisolated static let shellPath = WebviewsAppPage.gitGraph.shellPath
    /// The page itself: `shellx-git-graph://app/git-graph.html`.
    nonisolated static var shellURL: URL {
        WebviewsAppPage.gitGraph.shellURL
    }

    /// A task WebKit started and has not stopped. `serial` tells it apart from a
    /// later task that reuses the same object address.
    private struct Running {
        let serial: UInt64
        let task: any WKURLSchemeTask
        var operation: Task<Void, Never>?
    }

    private let assets: GitGraphPageAssets?
    private var running: [ObjectIdentifier: Running] = [:]
    private var nextSerial: UInt64 = 0

    /// - Parameter assets: The files to serve, for the page whose scheme it is
    ///   registered on. Nil fails every request.
    init(assets: GitGraphPageAssets? = .bundled()) {
        self.assets = assets
        super.init()
    }

    /// True for the Git Graph page itself and for in-page fragments of it.
    nonisolated static func isShellDocument(_ url: URL?) -> Bool {
        WebviewsAppPage.gitGraph.isShellDocument(url)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        nextSerial &+= 1
        let serial = nextSerial
        running[id] = Running(serial: serial, task: urlSchemeTask, operation: nil)
        let requestURL = urlSchemeTask.request.url
        let assets = assets
        let operation = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result<GitGraphPageAssets.Asset, any Error> {
                    guard let assets, let requestURL else { throw GitGraphPageAssets.Failure.badURL }
                    return try assets.asset(for: requestURL)
                }
            }.value
            self?.complete(id, serial: serial, requestURL: requestURL, result: result)
        }
        running[id]?.operation = operation
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        running.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.operation?.cancel()
    }

    /// Answers a task unless WebKit stopped it while its file was read.
    private func complete(
        _ id: ObjectIdentifier,
        serial: UInt64,
        requestURL: URL?,
        result: Result<GitGraphPageAssets.Asset, any Error>
    ) {
        guard running[id]?.serial == serial, let task = running.removeValue(forKey: id)?.task else { return }
        switch (result, requestURL) {
        case (.success(let asset), let requestURL?):
            let isText = asset.mimeType.hasPrefix("text/") || asset.mimeType == "application/json"
                || asset.mimeType == "image/svg+xml"
            let headers = [
                "Content-Type": isText ? "\(asset.mimeType); charset=utf-8" : asset.mimeType,
                "Content-Length": "\(asset.data.count)",
                "Cache-Control": "no-cache",
                "X-Content-Type-Options": "nosniff",
            ]
            let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) ?? URLResponse(
                url: requestURL,
                mimeType: asset.mimeType,
                expectedContentLength: asset.data.count,
                textEncodingName: isText ? "utf-8" : nil
            )
            task.didReceive(response)
            task.didReceive(asset.data)
            task.didFinish()
        case (.success, nil):
            task.didFailWithError(Self.urlError(for: GitGraphPageAssets.Failure.badURL))
        case (.failure(let error), _):
            task.didFailWithError(Self.urlError(for: error))
        }
    }

    private static func urlError(for error: any Error) -> NSError {
        let code = switch error as? GitGraphPageAssets.Failure {
        case .badURL: NSURLErrorBadURL
        case .unreadable: NSURLErrorCannotDecodeContentData
        case .notFound, nil: NSURLErrorFileDoesNotExist
        }
        return NSError(domain: NSURLErrorDomain, code: code)
    }
}
