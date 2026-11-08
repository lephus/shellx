import Foundation

@MainActor public protocol WebAuthenticating {
    /// Shows `url` in the system's web sign-in sheet; returns the URL the page sent back to `callbackScheme`.
    /// Throws `IdentityProviderError.cancelled` when the user closes the sheet.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

/// Google's OAuth for an iOS client (no secret): authorization code with PKCE; the code exchange runs on the phone.
public struct GoogleOAuthClient: Equatable, Sendable {
    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    public let clientID: String
    private let prefix: String

    /// Nil unless `clientID` matches `^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$` (the build placeholder does not).
    public init?(clientID: String) {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let prefix = String(clientID.dropLast(suffix.count))
        let parts = prefix.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
            parts[0].utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
            parts[1].utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x7a) })
        else { return nil }
        self.clientID = clientID
        self.prefix = prefix
    }

    /// `com.googleusercontent.apps.<prefix>`
    public var callbackScheme: String { "com.googleusercontent.apps.\(prefix)" }
    public var redirectURI: String { callbackScheme + ":/oauth2redirect" }

    public func authorizationURL(nonce: String, state: String, codeChallenge: String) -> URL {
        var components = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return components.url!
    }

    /// `error=access_denied` → `.cancelled`; another `error`, another scheme, another `state`, no `code` → `.failed`.
    public func code(fromCallback url: URL, state: String) throws -> String {
        guard url.scheme?.lowercased() == callbackScheme,
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { throw IdentityProviderError.failed }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw error == "access_denied" ? IdentityProviderError.cancelled : IdentityProviderError.failed
        }
        guard value("state") == state, let code = value("code"), !code.isEmpty else {
            throw IdentityProviderError.failed
        }
        return code
    }

    /// POST, `application/x-www-form-urlencoded`, timeout 15 s. No client_secret.
    public func tokenRequest(code: String, codeVerifier: String) -> URLRequest {
        var request = URLRequest(url: Self.tokenEndpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let fields: [(String, String)] = [
            ("client_id", clientID), ("code", code), ("code_verifier", codeVerifier),
            ("grant_type", "authorization_code"), ("redirect_uri", redirectURI),
        ]
        let body = fields.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
        request.httpBody = Data(body.utf8)
        return request
    }

    /// The `id_token` of a status-200 JSON reply; anything else throws `IdentityProviderError.failed`.
    public static func idToken(fromTokenResponse data: Data, status: Int) throws -> String {
        struct Reply: Decodable { var idToken: String?
            private enum CodingKeys: String, CodingKey { case idToken = "id_token" }
        }
        guard status == 200, let reply = try? JSONDecoder().decode(Reply.self, from: data),
            let token = reply.idToken, !token.isEmpty
        else { throw IdentityProviderError.failed }
        return token
    }
}

/// Google sign-in: opens Google's page in the system sheet, then exchanges the code for an ID token.
@MainActor public struct GoogleSignIn {
    public typealias Exchange = @Sendable (URLRequest) async throws -> (Data, Int)

    private let client: GoogleOAuthClient
    private let web: any WebAuthenticating
    private let exchange: Exchange

    /// `exchange` nil: `URLSession.shared.data(for:)`, with the HTTP status (0 when there is none).
    public init(client: GoogleOAuthClient, web: any WebAuthenticating, exchange: Exchange? = nil) {
        self.client = client
        self.web = web
        self.exchange =
            exchange ?? { request in
                let (data, response) = try await URLSession.shared.data(for: request)
                return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
            }
    }

    /// verifier = randomToken(32), state = randomToken(16); opens the authorization URL; reads the code; exchanges it.
    public func idToken(nonce: String) async throws -> String {
        let verifier = AuthCrypto.randomToken(byteCount: 32)
        let state = AuthCrypto.randomToken(byteCount: 16)
        let url = client.authorizationURL(
            nonce: nonce, state: state, codeChallenge: AuthCrypto.pkceChallenge(verifier: verifier))
        let callback = try await web.authenticate(url: url, callbackScheme: client.callbackScheme)
        let code = try client.code(fromCallback: callback, state: state)
        let data: Data
        let status: Int
        do {
            (data, status) = try await exchange(client.tokenRequest(code: code, codeVerifier: verifier))
        } catch is URLError {
            throw IdentityProviderError.failed
        }
        return try GoogleOAuthClient.idToken(fromTokenResponse: data, status: status)
    }
}
