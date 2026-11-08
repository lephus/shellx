import Foundation

/// Why a Google sign-in flow runs: a new session, or switching the current session to Google in place.
public enum GoogleSignInPurpose: String, Sendable {
    case signIn = "sign_in"
    case link
}

/// A started Google flow: the page to open in the browser and the id to finish or cancel it with.
public struct GoogleSignInStart: Equatable, Sendable {
    public let flowID: String
    public let authURL: URL
    public init(flowID: String, authURL: URL) { self.flowID = flowID; self.authURL = authURL }
}

/// The account a finished Google flow signed in (never carries a token).
public struct GoogleSignInResult: Equatable, Sendable {
    public let userID: String
    public let deviceID: String
    public let email: String
    public let authMethod: String
    public init(userID: String, deviceID: String, email: String, authMethod: String) {
        self.userID = userID; self.deviceID = deviceID; self.email = email; self.authMethod = authMethod
    }
}

/// One way to sign in to the account (a Google or Apple identity).
public struct AccountSignInMethod: Equatable, Sendable, Identifiable {
    public let id: String
    public let provider: String
    public let email: String
    public let isPrivateEmail: Bool
    /// The phone that linked this Apple ID through pairing, if any.
    public let linkedViaDeviceName: String?
    public let createdAt: Date
    public var isApple: Bool { provider == "apple" }

    public init(id: String, provider: String, email: String, isPrivateEmail: Bool, linkedViaDeviceName: String?, createdAt: Date) {
        self.id = id; self.provider = provider; self.email = email; self.isPrivateEmail = isPrivateEmail
        self.linkedViaDeviceName = linkedViaDeviceName; self.createdAt = createdAt
    }
}

/// Typed Google sign-in and sign-in method calls. Every call blocks on the FFI: call from a background queue.
extension ShellXCoreClient {
    /// Starts a Google flow (loopback listener plus Google URL). Throws `bad_response` unless the URL is https.
    public func beginGoogleSignIn(purpose: GoogleSignInPurpose) throws -> GoogleSignInStart {
        struct Reply: Decodable { let flow_id: String, auth_url: String }
        let r = try call("auth.google.begin", ["purpose": .string(purpose.rawValue)], as: Reply.self)
        guard let url = URL(string: r.auth_url), url.scheme == "https", !r.flow_id.isEmpty else {
            throw ShellXCoreError(code: "bad_response", message: "core reply has an unusable auth_url")
        }
        return GoogleSignInStart(flowID: r.flow_id, authURL: url)
    }

    /// Waits for the browser, then signs in or links. Throws `google_cancelled`, `google_timeout`, `email_in_use`, ...
    public func finishGoogleSignIn(flowID: String) throws -> GoogleSignInResult {
        struct Reply: Decodable { let user_id: String, device_id: String, email: String, auth_method: String }
        let r = try call("auth.google.finish", ["flow_id": .string(flowID)], as: Reply.self)
        return GoogleSignInResult(userID: r.user_id, deviceID: r.device_id, email: r.email, authMethod: r.auth_method)
    }

    /// Ends a waiting flow; a `finishGoogleSignIn` blocked on it throws `google_cancelled`.
    public func cancelGoogleSignIn(flowID: String) throws {
        struct Empty: Decodable {}
        _ = try call("auth.google.cancel", ["flow_id": .string(flowID)], as: Empty.self)
    }

    /// The account's sign-in methods, oldest first.
    public func signInMethods() throws -> [AccountSignInMethod] {
        struct Item: Decodable {
            let identity_id: String, provider: String
            let email: String?, is_private_email: Bool?, linked_via_device_name: String?, created_at_unix: Double?
        }
        struct Reply: Decodable { let identities: [Item] }
        return try call("account.identities.list", as: Reply.self).identities.map {
            AccountSignInMethod(
                id: $0.identity_id, provider: $0.provider, email: $0.email ?? "", isPrivateEmail: $0.is_private_email ?? false,
                linkedViaDeviceName: $0.linked_via_device_name,
                createdAt: Date(timeIntervalSince1970: $0.created_at_unix ?? 0))
        }
    }

    /// Removes one sign-in method (an Apple ID). The relay refuses the last Google one (`last_google_identity`).
    public func removeSignInMethod(id: String) throws {
        struct Empty: Decodable {}
        _ = try call("account.identities.remove", ["identity_id": .string(id)], as: Empty.self)
    }
}
