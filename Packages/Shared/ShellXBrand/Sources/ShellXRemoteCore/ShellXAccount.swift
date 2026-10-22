import Foundation
import Observation

/// The ShellX account this Mac is signed in to, for Settings → Account. Works whether or not the
/// remote-machines gate is on:
///
/// * gate off: only `config.set` and `auth.login` / `auth.logout` through the core; no host, bridge or
///   remote session starts;
/// * gate on: the remote service signs in and out, and its session starts and stops with the account.
///
/// The core keeps the session token; `stateRoot/account.json` (owner-only) keeps the user id and the email
/// typed at sign-in, because the core never tells the email back. It is the signed-in state at launch.
@MainActor
@Observable
public final class ShellXAccount {
    public struct Identity: Codable, Equatable, Sendable {
        public let userID: String
        public let email: String
        /// When this Mac last signed in. Nil for records saved before it was kept.
        public let signedInAt: Date?

        public init(userID: String, email: String, signedInAt: Date? = nil) {
            self.userID = userID; self.email = email; self.signedInAt = signedInAt
        }
    }

    public private(set) var identity: Identity?
    /// True while a sign-out runs. The sign-in sheet shows its own progress.
    public private(set) var isWorking = false

    @ObservationIgnored private let service: ShellXRemoteService
    @ObservationIgnored private let file: URL

    public init(service: ShellXRemoteService) {
        self.service = service
        file = service.env.paths.stateRoot.appendingPathComponent("account.json")
        identity = (try? OwnerOnlyFile.read(file)).flatMap { $0 }.flatMap { try? JSONDecoder().decode(Identity.self, from: $0) }
    }

    /// Throws the core's error (`invalid_credentials`, `rate_limited`, `network`, …); the identity is
    /// kept only after the server accepted the password.
    public func signIn(email: String, password: String) async throws {
        let userID: String
        if service.env.gateEnabled() {
            try await service.signIn(email: email, password: password)
            userID = service.accountOwnerID ?? ""
        } else {
            try await service.ensureConfigured()
            let params: [String: JSONValue] = ["email": .string(email), "password": .string(password)]
            userID = try await service.call("auth.login", params, as: LoginReply.self).user_id
        }
        let signedIn = Identity(userID: userID, email: email, signedInAt: Date())
        let file = self.file
        do {
            let data = try JSONEncoder().encode(signedIn)
            try await ShellXRemoteService.offMain {
                try OwnerOnlyFile.ensurePrivateDirectory(file.deletingLastPathComponent())
                try OwnerOnlyFile.write(data, to: file)
            }
        } catch {
            // Signed in for this run anyway; the next launch shows signed out.
            RemoteLog.service.error("account record not saved: \(RemoteLog.code(error), privacy: .public)")
        }
        identity = signedIn
        RemoteLog.service.info("account signed in")
    }

    /// Best-effort server logout; the account is forgotten locally even when the server is unreachable.
    public func signOut() async {
        isWorking = true
        defer { isWorking = false }
        if service.env.gateEnabled() {
            await service.signOut()
        } else {
            do {
                try await service.ensureConfigured()
                _ = try await service.call("auth.logout", as: EmptyReply.self)
            } catch {
                RemoteLog.service.error("logout failed: \(RemoteLog.code(error), privacy: .public)")
            }
        }
        let file = self.file
        _ = try? await ShellXRemoteService.offMain { try FileManager.default.removeItem(at: file) }
        identity = nil
    }
}
