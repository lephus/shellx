import Foundation
import WebKit
import XCTest
import zlib

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class GitGraphURLSchemeHandlerTests: XCTestCase {
    private var root: URL!
    private var outside: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGraphURLSchemeHandlerTests-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("webviews-app", isDirectory: true)
        outside = base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("chunks"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    // MARK: Request path to file

    func testRequestPathMapsToAFileUnderTheRoot() throws {
        let assets = GitGraphPageAssets(root: root)

        XCTAssertEqual(try assets.fileURL(forRequestPath: "/git-graph.html").path, root.standardizedFileURL.path + "/git-graph.html")
        XCTAssertEqual(try assets.fileURL(forRequestPath: "/chunks/git-graph-vendor.mjs").path, root.standardizedFileURL.path + "/chunks/git-graph-vendor.mjs")
        XCTAssertEqual(try assets.fileURL(forRequestPath: "/chunks/a%20b.mjs").lastPathComponent, "a b.mjs")
        XCTAssertEqual(
            try assets.fileURL(for: XCTUnwrap(URL(string: "shellx-git-graph://app/chunks/x.mjs?v=1#frag"))).path,
            root.standardizedFileURL.path + "/chunks/x.mjs"
        )
    }

    func testTraversalAbsoluteAndMalformedPathsAreRejected() throws {
        let assets = GitGraphPageAssets(root: root)
        let rejected = [
            "", "/", "git-graph.html", "//etc/passwd", "/chunks//x.mjs", "/chunks/",
            "/../outside/secret.mjs", "/chunks/../../outside/secret.mjs", "/./git-graph.html",
            "/%2e%2e/outside/secret.mjs", "/chunks%2F..%2F..%2Foutside%2Fsecret.mjs", "/%2Fetc%2Fpasswd",
            "/chunks/a%5Cb.mjs", "/a%00.mjs", "/%E0%A4%A",
        ]
        for path in rejected {
            XCTAssertThrowsError(try assets.fileURL(forRequestPath: path), path) { error in
                XCTAssertEqual(error as? GitGraphPageAssets.Failure, .badURL, path)
            }
        }
        let foreignURLs = [
            "https://app/git-graph.html", "file:///tmp/git-graph.html", "shellx-git-graph://other/git-graph.html",
            "shellx-git-graph://app:8080/git-graph.html", "shellx-git-graph://user@app/git-graph.html",
        ]
        for string in foreignURLs {
            XCTAssertThrowsError(try assets.fileURL(for: XCTUnwrap(URL(string: string))), string) { error in
                XCTAssertEqual(error as? GitGraphPageAssets.Failure, .badURL, string)
            }
        }
    }

    func testLinkThatLeavesTheRootIsRejected() throws {
        try write("secret", to: outside.appendingPathComponent("secret.mjs"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("chunks/link.mjs"),
            withDestinationURL: outside.appendingPathComponent("secret.mjs")
        )
        let assets = GitGraphPageAssets(root: root)

        XCTAssertThrowsError(try assets.asset(for: pageURL("/chunks/link.mjs"))) { error in
            XCTAssertEqual(error as? GitGraphPageAssets.Failure, .badURL)
        }
    }

    // MARK: Plain file, deflated fallback, missing

    func testPlainFileWinsOverItsDeflatedSibling() throws {
        try write("plain()", to: root.appendingPathComponent("main.mjs"))
        try deflate("deflated()", to: root.appendingPathComponent("main.mjs.deflate"))

        let asset = try GitGraphPageAssets(root: root).asset(for: pageURL("/main.mjs"))

        XCTAssertEqual(asset, GitGraphPageAssets.Asset(data: Data("plain()".utf8), mimeType: "text/javascript"))
    }

    func testMissingScriptIsInflatedFromItsDeflatedSibling() throws {
        let source = String(repeating: "export const lane = 1;\n", count: 400)
        try deflate(source, to: root.appendingPathComponent("chunks/gitGraphSurface.mjs.deflate"))
        try deflate("var x;", to: root.appendingPathComponent("legacy.js.deflate"))
        let assets = GitGraphPageAssets(root: root)

        XCTAssertEqual(
            try assets.asset(for: pageURL("/chunks/gitGraphSurface.mjs")),
            GitGraphPageAssets.Asset(data: Data(source.utf8), mimeType: "text/javascript")
        )
        XCTAssertEqual(try assets.asset(for: pageURL("/legacy.js")).data, Data("var x;".utf8))
    }

    /// The React agent session page shares the folder and its deflated scripts, but
    /// only on its own scheme: a built app has `main.mjs.deflate`, never `main.mjs`.
    func testAgentSessionPageInflatesItsScriptsOnItsOwnScheme() throws {
        try write("<script type=\"module\" src=\"./main.mjs\"></script>", to: root.appendingPathComponent("agent-session.html"))
        try deflate("boot()", to: root.appendingPathComponent("main.mjs.deflate"))
        let assets = GitGraphPageAssets(root: root, page: .agentSession)
        let page = try XCTUnwrap(URL(string: "shellx-agent-session://app/agent-session.html"))

        XCTAssertEqual(WebviewsAppPage.agentSession.shellURL, page)
        XCTAssertEqual(try assets.asset(for: page).mimeType, "text/html")
        XCTAssertEqual(
            try assets.asset(for: XCTUnwrap(URL(string: "shellx-agent-session://app/main.mjs"))),
            GitGraphPageAssets.Asset(data: Data("boot()".utf8), mimeType: "text/javascript")
        )
        XCTAssertThrowsError(try assets.asset(for: pageURL("/main.mjs"))) { error in
            XCTAssertEqual(error as? GitGraphPageAssets.Failure, .badURL, "the Git Graph scheme is not this page's")
        }
    }

    func testMissingFileUnknownTypeAndBadDeflateFail() throws {
        try deflate("body {}", to: root.appendingPathComponent("style.css.deflate"))
        try deflate("x()", to: root.appendingPathComponent("packed.mjs.deflate"))
        try write("not zlib", to: root.appendingPathComponent("broken.mjs.deflate"))
        try write("#!/bin/sh", to: root.appendingPathComponent("tool.sh"))
        let assets = GitGraphPageAssets(root: root)

        let expectations: [(String, GitGraphPageAssets.Failure)] = [
            ("/missing.mjs", .notFound),
            ("/style.css", .notFound),
            ("/packed.mjs.deflate", .notFound),
            ("/tool.sh", .notFound),
            ("/chunks", .notFound),
            ("/broken.mjs", .unreadable),
        ]
        for (path, failure) in expectations {
            XCTAssertThrowsError(try assets.asset(for: pageURL(path)), path) { error in
                XCTAssertEqual(error as? GitGraphPageAssets.Failure, failure, path)
            }
        }
    }

    // MARK: MIME types

    func testMIMETypes() throws {
        let expected = [
            "html": "text/html", "HTML": "text/html", "js": "text/javascript", "mjs": "text/javascript",
            "css": "text/css", "json": "application/json", "svg": "image/svg+xml", "woff2": "font/woff2",
            "png": "image/png",
        ]
        for (pathExtension, mimeType) in expected {
            XCTAssertEqual(GitGraphPageAssets.mimeType(forPathExtension: pathExtension), mimeType, pathExtension)
        }
        for pathExtension in ["", "deflate", "sh", "txt", "map", "wasm"] {
            XCTAssertNil(GitGraphPageAssets.mimeType(forPathExtension: pathExtension), pathExtension)
        }
        try write("<!doctype html>", to: root.appendingPathComponent("git-graph.html"))
        XCTAssertEqual(try GitGraphPageAssets(root: root).asset(for: pageURL("/git-graph.html")).mimeType, "text/html")
    }

    // MARK: Handler

    func testHandlerAnswersAScriptWithItsTypeAndInflatedBytes() async throws {
        try deflate("export {};", to: root.appendingPathComponent("main.mjs.deflate"))
        let handler = GitGraphURLSchemeHandler(assets: GitGraphPageAssets(root: root))
        let task = FakeSchemeTask(url: try pageURL("/main.mjs"), done: expectation(description: "answered"))

        handler.webView(WKWebView(), start: task)
        await fulfillment(of: [task.done], timeout: 10)

        XCTAssertEqual(task.events, ["response", "data", "finish"])
        XCTAssertEqual(task.response?.mimeType, "text/javascript")
        XCTAssertEqual((task.response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(task.data, Data("export {};".utf8))
    }

    func testHandlerNeverAnswersAStoppedTask() async throws {
        try write("export const a = 1;", to: root.appendingPathComponent("a.mjs"))
        try write("export const b = 2;", to: root.appendingPathComponent("b.mjs"))
        let handler = GitGraphURLSchemeHandler(assets: GitGraphPageAssets(root: root))
        let webView = WKWebView()
        let stoppedAnswered = expectation(description: "stopped task answered")
        stoppedAnswered.isInverted = true
        let stopped = FakeSchemeTask(url: try pageURL("/a.mjs"), done: stoppedAnswered)
        let later = FakeSchemeTask(url: try pageURL("/b.mjs"), done: expectation(description: "later task answered"))

        handler.webView(webView, start: stopped)
        handler.webView(webView, stop: stopped)
        handler.webView(webView, start: later)
        await fulfillment(of: [later.done], timeout: 10)
        await fulfillment(of: [stoppedAnswered], timeout: 0.5)

        XCTAssertEqual(stopped.events, [])
        XCTAssertEqual(later.events, ["response", "data", "finish"])
        XCTAssertEqual(later.data, Data("export const b = 2;".utf8))
    }

    func testHandlerFailsATraversalRequest() async throws {
        let handler = GitGraphURLSchemeHandler(assets: GitGraphPageAssets(root: root))
        let task = FakeSchemeTask(url: try pageURL("/%2e%2e/outside/secret.mjs"), done: expectation(description: "failed"))

        handler.webView(WKWebView(), start: task)
        await fulfillment(of: [task.done], timeout: 10)

        XCTAssertEqual(task.events, ["fail"])
        XCTAssertEqual((task.error as NSError?)?.code, NSURLErrorBadURL)
    }

    // MARK: Helpers

    private func pageURL(_ path: String) throws -> URL {
        try XCTUnwrap(URL(string: "shellx-git-graph://app" + path))
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    /// Writes `text` the way `scripts/compress-markdown-viewer-assets.sh` does:
    /// zlib format (`zlib.compress(raw, level=9)`).
    private func deflate(_ text: String, to url: URL) throws {
        let source = Data(text.utf8)
        var length = uLong(compressBound(uLong(source.count)))
        var buffer = [UInt8](repeating: 0, count: Int(length))
        let status = source.withUnsafeBytes { bytes -> Int32 in
            guard let base = bytes.bindMemory(to: Bytef.self).baseAddress else { return Z_BUF_ERROR }
            return compress2(&buffer, &length, base, uLong(source.count), 9)
        }
        XCTAssertEqual(status, Z_OK)
        try Data(buffer.prefix(Int(length))).write(to: url)
    }
}

/// Records what the handler tells WebKit about one request.
private final class FakeSchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    let done: XCTestExpectation
    private(set) var events: [String] = []
    private(set) var response: URLResponse?
    private(set) var data = Data()
    private(set) var error: (any Error)?

    init(url: URL, done: XCTestExpectation) {
        request = URLRequest(url: url)
        self.done = done
    }

    func didReceive(_ response: URLResponse) {
        events.append("response")
        self.response = response
    }

    func didReceive(_ data: Data) {
        events.append("data")
        self.data.append(data)
    }

    func didFinish() {
        events.append("finish")
        done.fulfill()
    }

    func didFailWithError(_ error: any Error) {
        events.append("fail")
        self.error = error
        done.fulfill()
    }
}
