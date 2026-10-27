import Foundation

/// What a released dictation becomes (`VoiceInputModel.outcome(for:)`).
public enum DictationOutcome: Equatable, Sendable {
    /// Everything said: the composer sends it, a sheet takes it; the mic plays the success haptic.
    case complete(String)
    /// Stopped at the byte limit, so the last sentence may be cut: the composer puts it in its field
    /// to be read before sending; no success haptic.
    case cutAtLimit(String)

    public var words: String {
        switch self {
        case let .complete(words), let .cutAtLimit(words): return words
        }
    }
}
