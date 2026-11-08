import Foundation
import XCTest
@testable import ShellXAppCore

@MainActor
final class GoogleOAuthTests: XCTestCase {
    private let id = "123456789012-abcdef123.apps.googleusercontent.com"
    private var client: GoogleOAuthClient { GoogleOAuthClient(clientID: id)! }
    private func query(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
    private func form(_ request: URLRequest) -> [String: String] {
        var parts = URLComponents()
        parts.percentEncodedQuery = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        return Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    func testOnlyGoogleIOSClientIDsAreAccepted() {
        XCTAssertEqual(client.callbackScheme, "com.googleusercontent.apps.123456789012-abcdef123")
        XCTAssertEqual(client.redirectURI, "com.googleusercontent.apps.123456789012-abcdef123:/oauth2redirect")
        for bad in ["", "0-shellx-placeholder.apps.googleusercontent.com", "abc.apps.googleusercontent.com",
                    "123-abc.example.com", "123-ABC.apps.googleusercontent.com"] {
            XCTAssertNil(GoogleOAuthClient(clientID: bad), bad)
        }
    }

    func testAuthorizationURLCarriesPKCEStateAndNonce() throws {
        let url = client.authorizationURL(nonce: "n-1", state: "s-1", codeChallenge: "c-1")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "accounts.google.com")
        XCTAssertEqual(url.path, "/o/oauth2/v2/auth")
        XCTAssertEqual(query(url), [
            "client_id": id, "redirect_uri": client.redirectURI, "response_type": "code", "scope": "openid email",
            "code_challenge": "c-1", "code_challenge_method": "S256", "state": "s-1", "nonce": "n-1",
            "prompt": "select_account",
        ])
    }

    func testCallbackGivesTheCodeOfThisState() throws {
        let url = URL(string: "com.googleusercontent.apps.123456789012-abcdef123:/oauth2redirect?state=s-1&code=4/0Abc-_x")!
        XCTAssertEqual(try client.code(fromCallback: url, state: "s-1"), "4/0Abc-_x")
    }

    func testCallbackFailures() {
        let base = "com.googleusercontent.apps.123456789012-abcdef123:/oauth2redirect"
        let cases: [(String, IdentityProviderError)] = [
            ("\(base)?error=access_denied&state=s-1", .cancelled),
            ("\(base)?error=server_error&state=s-1", .failed),
            ("\(base)?state=other&code=c", .failed),
            ("\(base)?state=s-1", .failed),
            ("com.example.other:/oauth2redirect?state=s-1&code=c", .failed),
        ]
        for (text, expected) in cases {
            XCTAssertThrowsError(try client.code(fromCallback: URL(string: text)!, state: "s-1"), text) {
                XCTAssertEqual($0 as? IdentityProviderError, expected, text)
            }
        }
    }

    func testTokenRequestIsAFormPostWithoutSecret() {
        let request = client.tokenRequest(code: "4/0Abc", codeVerifier: "v-1")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, GoogleOAuthClient.tokenEndpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("code=4%2F0Abc"), body)
        XCTAssertFalse(body.contains("client_secret"))
        XCTAssertEqual(form(request), [
            "client_id": id, "code": "4/0Abc", "code_verifier": "v-1", "grant_type": "authorization_code",
            "redirect_uri": client.redirectURI,
        ])
    }

    func testIDTokenComesOnlyFromASuccessfulTokenResponse() throws {
        XCTAssertEqual(
            try GoogleOAuthClient.idToken(fromTokenResponse: Data(#"{"id_token":"eyJ.a.b","access_token":"x"}"#.utf8), status: 200),
            "eyJ.a.b")
        for (json, status) in [(#"{"error":"invalid_grant"}"#, 400), (#"{"access_token":"x"}"#, 200), ("not json", 200)] {
            XCTAssertThrowsError(try GoogleOAuthClient.idToken(fromTokenResponse: Data(json.utf8), status: status)) {
                XCTAssertEqual($0 as? IdentityProviderError, .failed)
            }
        }
    }

    func testSignInOpensTheSheetThenExchangesTheCodeWithTheVerifier() async throws {
        let web = FakeWebAuthenticator()
        let sent = RequestBox()
        let flow = GoogleSignIn(client: client, web: web, exchange: { request in
            sent.set(request)
            return (Data(#"{"id_token":"google-id"}"#.utf8), 200)
        })
        let token = try await flow.idToken(nonce: "relay-nonce")
        XCTAssertEqual(token, "google-id")
        let opened = try XCTUnwrap(web.opened.first)
        XCTAssertEqual(opened.callbackScheme, client.callbackScheme)
        let asked = query(opened.url)
        XCTAssertEqual(asked["nonce"], "relay-nonce")
        let exchanged = form(try XCTUnwrap(sent.request))
        XCTAssertEqual(exchanged["code"], "code-1")
        XCTAssertEqual(AuthCrypto.pkceChallenge(verifier: try XCTUnwrap(exchanged["code_verifier"])), asked["code_challenge"])
    }

    func testCancelledSheetStopsBeforeTheExchange() async {
        let web = FakeWebAuthenticator()
        web.error = IdentityProviderError.cancelled
        let sent = RequestBox()
        let flow = GoogleSignIn(client: client, web: web, exchange: { sent.set($0); return (Data(), 200) })
        do { _ = try await flow.idToken(nonce: "n"); XCTFail() } catch {
            XCTAssertEqual(error as? IdentityProviderError, .cancelled)
        }
        XCTAssertNil(sent.request)
    }
}

/// Answers like Google: back to the callback scheme with the request's `state` and code "code-1".
@MainActor
private final class FakeWebAuthenticator: WebAuthenticating {
    var opened: [(url: URL, callbackScheme: String)] = []
    var error: (any Error)?
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        opened.append((url, callbackScheme))
        if let error { throw error }
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value ?? ""
        return URL(string: "\(callbackScheme):/oauth2redirect?state=\(state)&code=code-1")!
    }
}

private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?
    var request: URLRequest? { lock.withLock { stored } }
    func set(_ request: URLRequest) { lock.withLock { stored = request } }
}
