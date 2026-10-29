import ShellXAppCore
import SwiftUI
import UIKit
import UserNotifications

@main
struct ShellXApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var appDelegate
    @State private var graph = AppComposition.make()
    @State private var inbox = PairingInbox()
    @State private var networkPath = NetworkPathWatcher()
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    private var coordinator: AppCoordinator { graph.coordinator }

    var body: some Scene {
        WindowGroup {
            RootView(graph: graph, inbox: inbox, pushTaps: appDelegate.taps)
                .task {
                    appDelegate.registration = graph.push
                    networkPath.start { [coordinator] in coordinator.hub?.networkChanged() }
                    await graph.prepare()
                    await coordinator.launch()
                    // Only a launch straight into the home counts towards launchToHome.
                    if coordinator.hub?.machines.isEmpty ?? true { graph.launch.skip() }
                }
                // A newer App Store version: asked at launch and each time the app comes to the front.
                .task { await graph.updatePrompt?.check() }
                .updateAlert(graph.updatePrompt)
                // A shellx-link:// link (the Camera app, Safari) only fills the pairing sheet's
                // confirmation step, after sign-in if needed; it never pairs by itself.
                .onOpenURL { url in
                    inbox.receive(url)
                }
                // Settings › Appearance, on the windows so sheets and alerts follow it.
                .onChange(of: appearance, initial: true) { _, stored in
                    AppAppearance(stored: stored).apply()
                }
                // A locked Keychain keeps the launch screen up; try again whenever the app comes to
                // the front or protected data opens, so it can never stay there.
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // A window made since the choice was set gets it too.
                        AppAppearance(stored: appearance).apply()
                        Task { await coordinator.protectedDataBecameAvailable() }
                        if let prompt = graph.updatePrompt { Task { await prompt.check() } }
                        // The user is in the app, which shows what waits: the alerts on the lock screen go.
                        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                        if let hub = coordinator.hub {
                            hub.appDidBecomeActive()
                            Task { await hub.refreshGrants() }
                        }
                    case .background:
                        if let hub = coordinator.hub {
                            Self.closeSessionsAfterGrace(hub)
                        }
                    default:
                        break
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
                ) { _ in
                    Task { await coordinator.protectedDataBecameAvailable() }
                }
        }
    }

    /// Keeps the app running through the hub's background grace, so sessions close cleanly when the
    /// app stays away, and stay open when it comes back within the grace. When iOS ends the time
    /// early, or grants none, the sessions close at once.
    private static func closeSessionsAfterGrace(_ hub: MachineHub) {
        let application = UIApplication.shared
        let task = BackgroundTask()
        task.id = application.beginBackgroundTask(withName: "ShellX Link grace") {
            hub.backgroundTimeExpired()
            task.end(in: application)
        }
        guard task.id != .invalid else {
            hub.backgroundTimeExpired()
            return
        }
        Task {
            await hub.appDidEnterBackground()
            task.end(in: application)
        }
    }
}

/// One `beginBackgroundTask` identifier, ended at most once.
@MainActor
private final class BackgroundTask {
    var id: UIBackgroundTaskIdentifier = .invalid

    func end(in application: UIApplication) {
        guard id != .invalid else { return }
        application.endBackgroundTask(id)
        id = .invalid
    }
}
