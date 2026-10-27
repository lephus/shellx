import SwiftUI

@main
struct ShellXApp: App {
    @State private var coordinator = AppComposition.makeCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator)
                .task { await coordinator.launch() }
                .onReceive(
                    NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
                ) { _ in
                    Task { await coordinator.protectedDataBecameAvailable() }
                }
        }
    }
}
