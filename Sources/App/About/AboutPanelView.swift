import AppKit
import CmuxFoundation
import SwiftUI

struct AboutPanelView: View {
    let showLicenses: () -> Void

    @Environment(\.openURL) private var openURL

    private let githubURL = URL(string: "https://github.com/manaflow-ai/cmux")
    private let docsURL = URL(string: "https://cmux.com/docs")

    private var version: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }
    private var build: String? { Bundle.main.infoDictionary?["CFBundleVersion"] as? String }
    private var commit: String? {
        if let value = Bundle.main.infoDictionary?["CMUXCommit"] as? String, !value.isEmpty {
            return value
        }
        let env = ProcessInfo.processInfo.environment["CMUX_COMMIT"] ?? ""
        return env.isEmpty ? nil : env
    }
    private var copyright: String? { Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String }

    var body: some View {
        VStack(alignment: .center) {
            Image("ShellXLogo")
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(alignment: .center, spacing: 32) {
                VStack(alignment: .center, spacing: 8) {
                    Text(String(localized: "about.appName", defaultValue: "ShellX"))
                        .cmuxFont(.title)
                        .bold()
                    Text(String(localized: "about.description", defaultValue: "A Ghostty-based terminal with vertical tabs\nand a notification panel for macOS."))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .cmuxFont(.caption)
                        .tint(.secondary)
                        .opacity(0.8)
                }
                .textSelection(.enabled)

                VStack(spacing: 2) {
                    if let version {
                        AboutPropertyRow(label: String(localized: "about.version", defaultValue: "Version"), text: version)
                    }
                    if let build {
                        AboutPropertyRow(label: String(localized: "about.build", defaultValue: "Build"), text: build)
                    }
                    let commitText = commit ?? "—"
                    let commitURL = commit.flatMap { hash in
                        URL(string: "https://github.com/manaflow-ai/cmux/commit/\(hash)")
                    }
                    AboutPropertyRow(label: String(localized: "about.commit", defaultValue: "Commit"), text: commitText, url: commitURL)
                }
                .frame(maxWidth: .infinity)

                Link(AboutLicenseContent.licenseLine, destination: AboutLicenseContent.sourceCodeURL)
                    .cmuxFont(.caption)
                    .multilineTextAlignment(.center)

                VStack(spacing: 2) {
                    Text(String(localized: "about.shellx.credits", defaultValue: "Credits"))
                        .cmuxFont(.caption)
                        .bold()
                        .padding(.bottom, 2)
                    ForEach(AboutLicenseContent.attributions, id: \.name) { attribution in
                        AboutPropertyRow(label: attribution.name, text: attribution.license, url: attribution.url)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    if let url = docsURL {
                        Button(String(localized: "about.docs", defaultValue: "Docs")) {
                            openURL(url)
                        }
                    }
                    if let url = githubURL {
                        Button(String(localized: "about.github", defaultValue: "GitHub")) {
                            openURL(url)
                        }
                    }
                    Button(String(localized: "about.licenses", defaultValue: "Licenses")) {
                        showLicenses()
                    }
                }

                if let copy = copyright, !copy.isEmpty {
                    Text(copy)
                        .cmuxFont(.caption)
                        .textSelection(.enabled)
                        .tint(.secondary)
                        .opacity(0.8)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .padding(32)
        .frame(minWidth: 280)
        .background(AboutVisualEffectBackground(material: .underWindowBackground).ignoresSafeArea())
    }
}
