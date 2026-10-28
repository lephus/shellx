import SwiftUI

/// Settings › Appearance: "Match iPhone", "Light" or "Dark". `ShellXApp` applies the choice.
struct AppearanceSection: View {
    @AppStorage(AppAppearance.storageKey) private var stored = AppAppearance.system.rawValue

    var body: some View {
        Section {
            Picker(selection: Binding(get: { AppAppearance(stored: stored) }, set: { stored = $0.rawValue })) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            } label: {
                Text(LocalizedStringResource("settings.appearance.mode"))
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.appearance")
        } header: {
            Text(LocalizedStringResource("settings.appearance.title"))
        }
    }
}
