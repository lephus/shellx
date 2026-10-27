import Foundation
import Speech

/// Downloads `SpeechAnalyzer`'s language assets in the background, once per locale at a time. Until
/// they are installed, the mic uses `SFSpeechRecognizer` (`AnalyzerTranscriber`), and Settings says
/// where the voice goes.
actor AnalyzerAssets {
    private var installing: Set<String> = []

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

    private func finished(_ locale: Locale) {
        installing.remove(locale.identifier)
    }
}
