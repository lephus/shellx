import Foundation
import ShellXLinkAccount
import XCTest
@testable import ShellXAppCore

final class SignInErrorTests: XCTestCase {
    func testRelayAndProviderErrorsMap() {
        let cases: [(any Error, SignInError)] = [
            (RelayAPIError.http(status: 401, code: "invalid_credentials"), .invalidCredentials),
            (RelayAPIError.http(status: 401, code: "reauth_required"), .reauthRequired),
            (RelayAPIError.http(status: 409, code: "switch_from_signed_in_device"), .switchFromSignedInDevice),
            (RelayAPIError.http(status: 409, code: "email_in_use"), .emailInUse),
            (RelayAPIError.http(status: 409, code: "identity_in_use"), .identityInUse),
            (RelayAPIError.http(status: 429, code: "rate_limited"), .rateLimited),
            (RelayAPIError.http(status: 400, code: "invalid_email"), .invalidEmail),
            (RelayAPIError.http(status: 400, code: "disposable_email"), .disposableEmail),
            (RelayAPIError.http(status: 401, code: "invalid_code"), .invalidCode),
            (RelayAPIError.http(status: 410, code: "code_expired"), .codeExpired),
            (RelayAPIError.http(status: 502, code: "email_send_failed"), .emailSendFailed),
            (RelayAPIError.http(status: 503, code: "email_sign_in_disabled"), .providerUnavailable),
            (RelayAPIError.http(status: 400, code: "invalid_device"), .server(code: "invalid_device")),
            // Only the email calls read a relay without the route as "not available" (the coordinator does that).
            (RelayAPIError.http(status: 404, code: "not_found"), .server(code: "not_found")),
            (RelayAPIError.http(status: 500, code: "boom"), .server(code: "boom")),
            (RelayAPIError.badResponse, .server(code: "bad_response")),
            (URLError(.notConnectedToInternet), .network),
            (IdentityProviderError.cancelled, .cancelled),
            (IdentityProviderError.notConfigured, .providerUnavailable),
            (IdentityProviderError.failed, .providerFailed),
            (CocoaError(.fileNoSuchFile), .server(code: "unknown")),
        ]
        for (error, expected) in cases { XCTAssertEqual(SignInError(error), expected, "\(error)") }
    }
}
