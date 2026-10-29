import Foundation
import XCTest

@testable import ShellXLinkAccount

final class RelayAPILogoutTests: XCTestCase {
    private let base = URL(string: "https://api.example.test")!

    private func api() throws -> RelayAPI {
        try RelayAPI(baseURL: base, session: StubURLProtocol.session(), clientVersion: "9.9.9")
    }

    func testLogoutPostsBearer() async throws {
        StubURLProtocol.install { _ in StubResponse(204) }
        try await api().logout(token: "tok-secret")

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/auth/logout")
        XCTAssertEqual(request.headers["Authorization"], "Bearer tok-secret")
        XCTAssertEqual(request.headers["X-ShellX-Version"], "9.9.9")
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testLogoutErrorSurfaced() async throws {
        StubURLProtocol.install { _ in StubResponse(401, ["error": ["code": "unauthorized"]]) }
        do {
            try await api().logout(token: "t")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? RelayAPIError, .http(status: 401, code: "unauthorized"))
        }
    }
}
