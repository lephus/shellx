import Observation
import ShellXAppCore
import UIKit
import UserNotifications

/// The UIKit side of push from paired Macs: the APNs token, a tap on an alert, and the quiet push that takes
/// a handled request's alert away. `ShellXApp` hands it the graph's `PushRegistration` at launch; a token
/// that came first is kept until then.
@MainActor
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Taps on a "needs you" alert, for the signed-in screens to open the waiting requests.
    let taps = PushTapInbox()

    var registration: PushRegistration? {
        didSet { if let registration, let token = earlyToken { Task { await registration.tokenArrived(token) } } }
    }
    private var earlyToken: Data?

    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Before launch returns, so a tap that launched the app reaches `didReceive`.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard let registration else {
            earlyToken = deviceToken
            return
        }
        Task { await registration.tokenArrived(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // No push this launch (simulator, no network, capability missing); the app works without it.
    }

    /// The quiet push the Mac sends once a request was handled: its alert goes away.
    func application(
        _ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard case let .resolved(_, requestID)? = PushPayload(userInfo: userInfo) else { return .noData }
        await Self.removeDelivered(requestID: requestID)
        return .noData
    }

    /// The app shows what waits for the user itself while it is open: no banner over it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard case .needsYou? = PushPayload(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run { taps.receive() }
    }

    /// Removes the alerts shown for `requestID`.
    nonisolated static func removeDelivered(requestID: String) async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.deliveredNotifications()
            .filter { PushPayload(userInfo: $0.request.content.userInfo)?.requestID == requestID }
            .map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Asks for permission to alert (iOS asks the user once and remembers) and, when allowed, registers with
    /// APNs, which answers with the token in `didRegisterForRemoteNotificationsWithDeviceToken`.
    static func registerIfAllowed() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }
}

/// A tap on a "needs you" alert, held until the signed-in screens take it (the tap may launch the app).
@MainActor @Observable
final class PushTapInbox {
    private(set) var hasTap = false

    func receive() {
        hasTap = true
    }

    /// True once per tap.
    func take() -> Bool {
        defer { hasTap = false }
        return hasTap
    }
}
