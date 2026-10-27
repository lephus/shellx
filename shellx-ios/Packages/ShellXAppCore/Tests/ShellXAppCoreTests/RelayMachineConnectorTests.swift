import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import XCTest

@testable import ShellXAppCore

/// Answers every request like a relay that no longer grants the machine, and records what it saw.
private final class NotGrantedStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [(path: String, authorization: String?)] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append((request.url?.path ?? "", request.value(forHTTPHeaderField: "Authorization")))
        let http = HTTPURLResponse(
            url: request.url!, statusCode: 403, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error":{"code":"not_granted","message":"no"}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class RelayMachineConnectorTests: XCTestCase {
    private let machine = PairedMachine(
        machineID: "m1", name: "Mac", linkSlot: "s1", hostKey: Data(repeating: 1, count: 32))

    func testEachConnectReadsTheLatestTokenFromTheVault() async throws {
        NotGrantedStub.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NotGrantedStub.self]
        let vault = AccountVault(store: InMemorySecretStore())
        let connector = try RelayClientFactory.makeConnector(
            apiBase: URL(string: "https://relay.example.test")!, appVersion: "2.0.0", vault: vault,
            deviceName: "iPhone", session: URLSession(configuration: configuration))

        // Without a session it fails as a refused token would, before any request.
        do {
            _ = try await connector.connect(machine)
            XCTFail("connect without a session must fail")
        } catch {
            XCTAssertEqual(LinkFailure(error), .signedOut)
        }
        XCTAssertTrue(NotGrantedStub.requests.isEmpty)

        for token in ["tok-1", "tok-2"] {
            try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: token, email: "a@b.c"))
            do {
                _ = try await connector.connect(machine)
                XCTFail("the stub refuses every ticket")
            } catch {
                XCTAssertEqual(error as? RelayAPIError, .http(status: 403, code: "not_granted"))
                XCTAssertEqual(LinkFailure(error), .revoked)
            }
        }
        XCTAssertEqual(NotGrantedStub.requests.map(\.path), ["/v2/relay/tickets", "/v2/relay/tickets"])
        XCTAssertEqual(NotGrantedStub.requests.map(\.authorization), ["Bearer tok-1", "Bearer tok-2"])
    }
}
