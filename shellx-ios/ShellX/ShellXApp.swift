import SwiftUI

@main
struct ShellXApp: App {
    @State private var coordinator = AppComposition.makeCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator)
                .task { await coordinator.launch() }
                // A locked Keychain keeps the launch screen up; try again whenever the app comes to
                // the front or protected data opens, so it can never stay there.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await coordinator.protectedDataBecameAvailable() } }
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
                ) { _ in
                    Task { await coordinator.protectedDataBecameAvailable() }
                }
        }
    }
}
