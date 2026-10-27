import SwiftUI

/// The app version and the open-source licence note.
struct AboutSection: View {
    private var version: String {
        let info = Bundle.main
        let short = info.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = info.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: version).foregroundStyle(.secondary)
            } label: {
                Text(LocalizedStringResource("settings.about.version"))
            }
            .accessibilityElement(children: .combine)

            LabeledContent {
                Text(LocalizedStringResource("settings.about.license.value")).foregroundStyle(.secondary)
            } label: {
                Text(LocalizedStringResource("settings.about.license"))
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text(LocalizedStringResource("settings.about.title"))
        }
    }
}
