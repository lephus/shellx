import Foundation
import ShellXAppCore
import Speech

/// Asks iOS what can recognise a spoken language right now (plan decision D8):
/// - whether `SpeechAnalyzer` can run it now (`analyzerReady`; in the app, only once its assets are
///   installed and it never failed to start for the language, so Settings never says "on this
///   iPhone" while a press goes through `SFSpeechRecognizer`);
/// - `SFSpeechRecognizer` on the device when it supports the language there, and whether it is
///   available at all (on Apple's servers when not on the device).
///
/// `VoiceCapabilityCache` (ShellXAppCore) decides how long an answer is reused.
struct VoiceCapabilityProbe: Sendable {
    /// Whether the analyzer can transcribe the locale now. Tests pass one that touches nothing.
    let analyzerReady: @Sendable (Locale) async -> Bool

    /// The app's: the analyzer counts once its assets are installed; asking starts their download.
    static func system(assets: AnalyzerAssets) -> VoiceCapabilityProbe {
        VoiceCapabilityProbe { locale in
            guard #available(iOS 26, *) else { return false }
            return await AnalyzerTranscriber.readiness(for: locale, assets: assets) == .ready
        }
    }

    func capabilities(for language: VoiceLanguage) async -> VoiceCapabilities {
        let locale = language.locale
        let analyzer = await analyzerReady(locale)
        let recognizer = SFSpeechRecognizer(locale: locale)
        return VoiceCapabilities(
            analyzerSupportsLocale: analyzer,
            legacyOnDevice: recognizer?.supportsOnDeviceRecognition ?? false,
            legacyAvailable: recognizer?.isAvailable ?? false)
    }
}
