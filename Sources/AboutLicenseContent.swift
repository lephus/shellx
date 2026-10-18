import Foundation
import ShellXBrand

struct AboutLicenseContent {
    /// A project or asset ShellX ships, credited in the About panel with its license.
    struct Attribution: Equatable {
        let name: String
        let license: String
        let url: URL?
    }

    /// Where the GPL corresponding source for ShellX lives.
    static let sourceCodeURL = ShellXBrand.sourceCodeURL

    /// The source URL as the About panel prints it: "github.com/lephus/shellx".
    static var sourceCodeDisplay: String {
        (sourceCodeURL.host ?? "") + sourceCodeURL.path
    }

    /// "GPL-3.0-or-later — source: github.com/lephus/shellx".
    static var licenseLine: String {
        String(
            format: String(localized: "about.shellx.licenseLine", defaultValue: "GPL-3.0-or-later — source: %@"),
            sourceCodeDisplay
        )
    }

    /// Upstream code, fonts and icons ShellX is built from (spec §12). The full
    /// third-party license texts stay behind the Licenses button.
    static let attributions: [Attribution] = [
        Attribution(name: "cmux (Manaflow, Inc.)", license: "GPL-3.0-or-later", url: nil),
        Attribution(name: "Ghostty", license: "MIT", url: URL(string: "https://github.com/ghostty-org/ghostty")),
        Attribution(name: "coolicons by Kryston Schwarze", license: "CC BY 4.0", url: URL(string: "https://github.com/krystonschwarze/coolicons")),
        Attribution(name: "Space Grotesk", license: "OFL-1.1", url: URL(string: "https://github.com/floriankarsten/space-grotesk")),
    ]

    let bundle: Bundle
    let repositoryURL: URL

    init(
        bundle: Bundle,
        repositoryURL: URL = AboutLicenseContent.sourceCodeURL
    ) {
        self.bundle = bundle
        self.repositoryURL = repositoryURL
    }

    func load() -> String {
        let missingMessage = String(
            localized: "about.licenses.notFound",
            defaultValue: "Licenses file not found.",
            bundle: bundle
        )
        let projectLicense = resourceText(
            named: "LICENSE",
            fileExtension: nil,
            in: bundle
        ) ?? missingMessage
        let thirdPartyLicenses = resourceText(
            named: "THIRD_PARTY_LICENSES",
            fileExtension: "md",
            in: bundle
        ) ?? missingMessage
        let projectHeading = String(
            localized: "about.licenses.projectHeading",
            defaultValue: "ShellX Project License",
            bundle: bundle
        )
        let projectSourceLabel = String(
            localized: "about.licenses.projectSource",
            defaultValue: "Project source",
            bundle: bundle
        )
        let correspondingSourceLabel = String(
            localized: "about.licenses.correspondingSource",
            defaultValue: "Corresponding source for this build",
            bundle: bundle
        )

        return """
        # \(projectHeading)

        \(projectSourceLabel): \(repositoryURL.absoluteString)
        \(correspondingSourceLabel): \(correspondingSourceURL().absoluteString)

        \(projectLicense)

        ---

        \(thirdPartyLicenses)
        """
    }

    func correspondingSourceURL() -> URL {
        correspondingSourceURL(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            bundleIdentifier: bundle.bundleIdentifier,
            commit: bundle.object(forInfoDictionaryKey: "CMUXCommit") as? String
        )
    }

    func correspondingSourceURL(
        version: String?,
        bundleIdentifier: String?,
        commit: String?
    ) -> URL {
        if bundleIdentifier == "com.cmuxterm.app", let version = normalized(version) {
            return repositoryURL
                .appendingPathComponent("tree", isDirectory: true)
                .appendingPathComponent("v\(version)")
        }
        if let commit = normalized(commit) {
            return repositoryURL
                .appendingPathComponent("tree", isDirectory: true)
                .appendingPathComponent(commit)
        }
        return repositoryURL
    }

    private func resourceText(
        named name: String,
        fileExtension: String?,
        in bundle: Bundle
    ) -> String? {
        guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
