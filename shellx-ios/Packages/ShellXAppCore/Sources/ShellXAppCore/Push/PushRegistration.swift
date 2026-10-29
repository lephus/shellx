import Foundation
import ShellXLinkAccount

/// Keeps the relay holding this phone's APNs token while it is signed in, so a paired Mac can reach it
/// while the app is closed (`POST /v2/notifications`). The app hands over every token iOS gives it
/// (`tokenArrived`) and calls `signedIn()` once a session exists; a token is sent once per sign-in, and
/// again after a failure.
@MainActor
public final class PushRegistration {
    private let relay: any RelayAccountCalling
    private let vault: AccountVault
    private let topic: String
    private let environment: APNsEnvironment
    private var latest: String?
    /// The token and session token the relay last accepted.
    private var sent: (hex: String, session: String)?

    /// `topic` is the app's bundle id; `environment` the APNs host of this build (sandbox for Debug).
    public init(relay: any RelayAccountCalling, vault: AccountVault, topic: String, environment: APNsEnvironment) {
        self.relay = relay
        self.vault = vault
        self.topic = topic
        self.environment = environment
    }

    /// iOS registered the app for remote notifications (`didRegisterForRemoteNotificationsWithDeviceToken`).
    public func tokenArrived(_ deviceToken: Data) async {
        latest = deviceToken.map { String(format: "%02x", $0) }.joined()
        await sendIfNeeded()
    }

    /// A session exists now (launch, sign-in, or coming back to the front).
    public func signedIn() async {
        await sendIfNeeded()
    }

    private func sendIfNeeded() async {
        guard let hex = latest, let session = try? await vault.session() else { return }
        if let sent, sent.hex == hex, sent.session == session.token { return }
        do {
            try await relay.setPushToken(hex, topic: topic, environment: environment, token: session.token)
            sent = (hex, session.token)
        } catch {
            // Not sent: the next sign-in, launch or token tries again.
        }
    }
}
