import SwiftUI

/// The app version and the "Licenses" row, which opens shellx.pro in the browser.
struct AboutSection: View {
    /// Where "Licenses" goes, and the host it shows as its value (a web address is never translated).
    static let website = URL(string: "https://shellx.pro")!
    static let websiteHost = "shellx.pro"

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

            // A link, so VoiceOver says so; the arrow only tells the eye that it leaves the app.
            Link(destination: Self.website) {
                LabeledContent {
                    HStack(spacing: 4) {
                        Text(verbatim: Self.websiteHost)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(.secondary)
                } label: {
                    Text(LocalizedStringResource("settings.about.license"))
                }
                .frame(minHeight: 44)
            }
            // A link is tinted; the row reads like the others, with only the arrow saying it leaves the app.
            .tint(.primary)
            .accessibilityIdentifier("settings.about.license")
        } header: {
            Text(LocalizedStringResource("settings.about.title"))
        }
    }
}
