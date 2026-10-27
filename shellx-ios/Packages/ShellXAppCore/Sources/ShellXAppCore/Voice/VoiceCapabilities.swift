import Foundation

/// The recognizer the mic uses for a language.
public enum VoiceEngine: Equatable, Sendable {
    /// `SpeechAnalyzer` (iOS 26 and later), on the iPhone.
    case analyzer
    /// `SFSpeechRecognizer` on the iPhone.
    case onDevice
    /// `SFSpeechRecognizer` on Apple's servers; Settings says so.
    case server
}

/// What iOS can do for one spoken language right now (plan decision D8).
public struct VoiceCapabilities: Equatable, Sendable {
    /// `SpeechAnalyzer` can transcribe the language on this iPhone now.
    public var analyzerSupportsLocale: Bool
    /// `SFSpeechRecognizer` can recognise the language on this iPhone.
    public var legacyOnDevice: Bool
    /// `SFSpeechRecognizer` is available for the language (on Apple's servers when not on device).
    public var legacyAvailable: Bool

    public init(analyzerSupportsLocale: Bool, legacyOnDevice: Bool, legacyAvailable: Bool) {
        self.analyzerSupportsLocale = analyzerSupportsLocale
        self.legacyOnDevice = legacyOnDevice
        self.legacyAvailable = legacyAvailable
    }

    /// Nothing can recognise the language.
    public static let none = VoiceCapabilities(analyzerSupportsLocale: false, legacyOnDevice: false, legacyAvailable: false)

    /// The analyzer first, then `SFSpeechRecognizer` on the device, then on Apple's servers. Nil only
    /// when no path is left: the mic is never off just because the language cannot run on device.
    public var engine: VoiceEngine? {
        if analyzerSupportsLocale { return .analyzer }
        if legacyOnDevice { return .onDevice }
        if legacyAvailable { return .server }
        return nil
    }
}
