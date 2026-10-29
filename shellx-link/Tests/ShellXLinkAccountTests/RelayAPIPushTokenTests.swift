import Foundation
import XCTest

@testable import ShellXLinkAccount

final class RelayAPIPushTokenTests: XCTestCase {
    private let base = URL(string: "https://api.example.test")!

    private func api() throws -> RelayAPI {
        try RelayAPI(baseURL: base, session: StubURLProtocol.session(), clientVersion: "9.9.9")
    }

    func testSetPushTokenPutsTheAPNsTokenWithTheAppAndHost() async throws {
        StubURLProtocol.install { _ in StubResponse(204) }

        try await api().setPushToken("ab12", topic: "com.shellx.dev", environment: .sandbox, token: "tok-secret")

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.path, "/v1/devices/me/push-token")
        XCTAssertEqual(request.headers["Authorization"], "Bearer tok-secret")
        let body = try XCTUnwrap(request.json)
        XCTAssertEqual(body as NSDictionary, [
            "token": "ab12", "platform": "ios", "apns_topic": "com.shellx.dev", "apns_env": "sandbox",
        ] as NSDictionary)
    }

    func testSetPushTokenErrorSurfaced() async throws {
        StubURLProtocol.install { _ in StubResponse(400, ["error": ["code": "bad_request"]]) }
        do {
            try await api().setPushToken("ab12", topic: "com.shellx.prod", environment: .production, token: "t")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? RelayAPIError, .http(status: 400, code: "bad_request"))
        }
    }
}
