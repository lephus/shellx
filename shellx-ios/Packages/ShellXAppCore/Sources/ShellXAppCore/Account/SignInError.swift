import Foundation
import ShellXLinkAccount

public enum SignInError: Error, Equatable, Sendable {
    case invalidCredentials
    case rateLimited
    case network
    case server(code: String)
    /// The previous account's data could not be removed from this iPhone yet; nobody can sign in
    /// until it is.
    case localWipePending

    /// Maps what `RelayAPI.login` threw.
    init(_ error: Error) {
        switch error {
        case let RelayAPIError.http(status, code):
            if status == 401 && code == "invalid_credentials" {
                self = .invalidCredentials
            } else if status == 429 {
                self = .rateLimited
            } else {
                self = .server(code: code)
            }
        case RelayAPIError.badResponse:
            self = .server(code: "bad_response")
        case is URLError:
            self = .network
        default:
            self = .server(code: "unknown")
        }
    }
}
