import Foundation
import ShellXAppCore
import Speech

/// Asks iOS what can recognise a spoken language right now (plan decision D8):
/// - the analyzer counts only once its assets are installed (asking starts their download), so
///   Settings never says "on this iPhone" while a press still goes through `SFSpeechRecognizer`;
/// - `SFSpeechRecognizer` on the device when it supports the language there, and whether it is
///   available at all (on Apple's servers when not on the device).
///
/// Every press asks, so an answer with a recognizer is reused for `reuse`, keeping the question off
/// the way to the first word. An answer without one is never reused: the next press asks again.
struct VoiceCapabilityProbe: Sendable {
    static let reuse: Duration = .seconds(30)

    let assets: AnalyzerAssets
    private let recent = Recent()

    init(assets: AnalyzerAssets) {
        self.assets = assets
    }

    func capabilities(for language: VoiceLanguage) async -> VoiceCapabilities {
        if let known = await recent.answer(for: language, within: Self.reuse) { return known }
        let found = await ask(language)
        if found.engine != nil { await recent.keep(found, for: language) }
        return found
    }

    private func ask(_ language: VoiceLanguage) async -> VoiceCapabilities {
        let locale = language.locale
        var analyzer = false
        if #available(iOS 26, *) {
            analyzer = await AnalyzerTranscriber.readiness(for: locale, assets: assets) == .ready
        }
        let recognizer = SFSpeechRecognizer(locale: locale)
        return VoiceCapabilities(
            analyzerSupportsLocale: analyzer,
            legacyOnDevice: recognizer?.supportsOnDeviceRecognition ?? false,
            legacyAvailable: recognizer?.isAvailable ?? false)
    }

    /// The last answer with a recognizer, per language.
    private actor Recent {
        private var answers: [VoiceLanguage: (capabilities: VoiceCapabilities, at: ContinuousClock.Instant)] = [:]

        func answer(for language: VoiceLanguage, within age: Duration) -> VoiceCapabilities? {
            guard let entry = answers[language], entry.at.duration(to: .now) < age else { return nil }
            return entry.capabilities
        }

        func keep(_ capabilities: VoiceCapabilities, for language: VoiceLanguage) {
            answers[language] = (capabilities, .now)
        }
    }
}
