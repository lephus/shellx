import ShellXAppCore
import SwiftUI
import UIKit

@main
struct ShellXApp: App {
    @State private var coordinator = AppComposition.makeCoordinator()
    @State private var networkPath = NetworkPathWatcher()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator)
                .task {
                    networkPath.start { [coordinator] in coordinator.hub?.networkChanged() }
                    await coordinator.launch()
                }
                // A locked Keychain keeps the launch screen up; try again whenever the app comes to
                // the front or protected data opens, so it can never stay there.
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        Task { await coordinator.protectedDataBecameAvailable() }
                        if let hub = coordinator.hub {
                            hub.appDidBecomeActive()
                            Task { await hub.refreshGrants() }
                        }
                    case .background:
                        if let hub = coordinator.hub { Self.closeSessionsAfterGrace(hub) }
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
    /// app stays away, and stay open when it comes back within the grace.
    private static func closeSessionsAfterGrace(_ hub: MachineHub) {
        let application = UIApplication.shared
        let task = BackgroundTask()
        task.id = application.beginBackgroundTask(withName: "ShellX Link grace") {
            task.end(in: application)
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
