import Foundation
import Speech

/// What the app knows about `SpeechAnalyzer` per locale, shared by the transcriber and the probe:
/// - which module has the language (`module(for:lookup:)`), asked of iOS once per locale: the two
///   `supportedLocale` questions are not repeated on every press, on the way to the first word;
/// - its language assets download in the background, once per locale at a time; until they are
///   installed, the mic uses `SFSpeechRecognizer` (`FallbackTranscriber`);
/// - a locale whose analyzer itself failed to start (not a passing audio problem) is not offered again
///   in this run of the app, so the probe (and Settings) name the `SFSpeechRecognizer` path presses
///   really take; its module answer is forgotten too.
actor AnalyzerAssets {
    /// The analyzer module that has a language, and the locale it supports it as.
    enum ModuleChoice: Equatable, Sendable {
        case speech(Locale)
        case dictation(Locale)
        case unsupported
    }

    private var installing: Set<String> = []
    private var failed: Set<String> = []
    private var modules: [String: ModuleChoice] = [:]

    /// The module for `locale`: the answer kept from an earlier press, or `lookup`'s.
    func module(for locale: Locale, lookup: @Sendable (Locale) async -> ModuleChoice) async -> ModuleChoice {
        if let known = modules[locale.identifier] { return known }
        let found = await lookup(locale)
        modules[locale.identifier] = found
        return found
    }

    /// Starts installing the assets `module` needs for `locale`, unless that already runs.
    @available(iOS 26, *)
    func install(_ module: any SpeechModule, locale: Locale) {
        guard installing.insert(locale.identifier).inserted else { return }
        Task {
            _ = try? await AssetInventory.reserve(locale: locale)
            if let request = try? await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try? await request.downloadAndInstall()
            }
            self.finished(locale)
        }
    }

    /// The analyzer could not start for `locale`; presses use `SFSpeechRecognizer` from now on, and
    /// the module answer is forgotten.
    func markFailed(_ locale: Locale) {
        failed.insert(locale.identifier)
        modules[locale.identifier] = nil
    }

    func hasFailed(_ locale: Locale) -> Bool {
        failed.contains(locale.identifier)
    }

    private func finished(_ locale: Locale) {
        installing.remove(locale.identifier)
    }
}
