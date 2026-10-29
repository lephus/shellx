import ShellXAppCore
import SwiftUI

extension View {
    /// The popup for a newer App Store version (`UpdatePrompt.offered`): Update opens the store page,
    /// Later closes it until the app opens again. Nil (Debug builds) shows nothing.
    func updateAlert(_ prompt: UpdatePrompt?) -> some View {
        modifier(UpdateAlert(prompt: prompt))
    }
}

private struct UpdateAlert: ViewModifier {
    let prompt: UpdatePrompt?

    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        let offered = prompt?.offered
        content.alert(
            offered.map { String(localized: "update.title \($0.version)") } ?? "",
            isPresented: Binding(get: { offered != nil }, set: { if !$0 { prompt?.later() } }),
            presenting: offered
        ) { release in
            Button(String(localized: "update.now")) {
                openURL(release.storeURL)
                prompt?.later()
            }
            Button(String(localized: "update.later"), role: .cancel) { prompt?.later() }
        } message: { _ in
            Text(LocalizedStringResource("update.message"))
        }
    }
}
