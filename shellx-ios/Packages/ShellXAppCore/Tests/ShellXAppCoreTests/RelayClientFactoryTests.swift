import Foundation
import XCTest

@testable import ShellXAppCore

private final class HeaderStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var seen: [String: String] = [:]
    nonisolated(unsafe) static var path = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.seen = request.allHTTPHeaderFields ?? [:]
        Self.path = request.url?.path ?? ""
        let http = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class RelayClientFactoryTests: XCTestCase {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeaderStub.self]
        return URLSession(configuration: configuration)
    }

    func testVersionHeaderIsTheBareVersion() async throws {
        let relay = try RelayClientFactory.make(
            apiBase: URL(string: "https://relay.example.test")!, appVersion: "2.0.0", session: session())
        try await relay.logout(token: "t")
        XCTAssertEqual(HeaderStub.path, "/v1/auth/logout")
        XCTAssertEqual(HeaderStub.seen["X-ShellX-Version"], "2.0.0")
    }

    func testHeaderVersionMatchesTheRelayPattern() {
        XCTAssertEqual(RelayClientFactory.headerVersion(for: "2.10.3"), "2.10.3")
        for bad in ["ios/2.0.0", "2.0", "2.0.0-beta", "1234567.0.0", "", "?"] {
            XCTAssertEqual(RelayClientFactory.headerVersion(for: bad), "0.0.0", bad)
        }
    }

    func testInsecureBaseIsRefused() {
        XCTAssertThrowsError(
            try RelayClientFactory.make(apiBase: URL(string: "http://relay.example.test")!, appVersion: "2.0.0"))
    }
}
