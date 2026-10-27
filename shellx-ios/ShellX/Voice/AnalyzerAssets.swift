import Foundation
import Speech

/// What the app knows about `SpeechAnalyzer` per locale, shared by the transcriber and the probe:
/// - its language assets download in the background, once per locale at a time; until they are
///   installed, the mic uses `SFSpeechRecognizer` (`AnalyzerTranscriber`);
/// - a locale whose analyzer failed to start is not offered again in this run of the app, so the
///   probe (and Settings) name the `SFSpeechRecognizer` path presses really take.
actor AnalyzerAssets {
    private var installing: Set<String> = []
    private var failed: Set<String> = []

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

    /// The analyzer could not start for `locale`; presses use `SFSpeechRecognizer` from now on.
    func markFailed(_ locale: Locale) {
        failed.insert(locale.identifier)
    }

    func hasFailed(_ locale: Locale) -> Bool {
        failed.contains(locale.identifier)
    }

    private func finished(_ locale: Locale) {
        installing.remove(locale.identifier)
    }
}
