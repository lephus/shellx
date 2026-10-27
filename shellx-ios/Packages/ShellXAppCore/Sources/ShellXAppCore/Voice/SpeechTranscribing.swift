import Foundation

/// Names one dictation of a `SpeechTranscribing`. `finish` and `cancel` act on that run only, so a
/// late cancel of a press that was already released can never stop the next press's run.
public struct SpeechRunID: Hashable, Sendable {
    public let raw: UUID

    public init(raw: UUID = UUID()) {
        self.raw = raw
    }
}

/// Turns the microphone into text while the user holds the mic (plan decision D8). The app's
/// implementations use Apple's speech recognition only: `SpeechAnalyzer` on iOS 26 and later,
/// otherwise `SFSpeechRecognizer`, on the device when it can, else on Apple's servers. Audio never
/// goes to ShellX or anyone else. Transcripts are never logged.
///
/// A run holds the microphone from `start` until `finish` or `cancel` for it. One that ends by
/// itself (an error, a time limit) gives the microphone back too; the model still cancels it then.
/// Starting a run stops any other run first.
public protocol SpeechTranscribing: Sendable {
    /// Starts listening as `run`. Each element is the whole text heard so far, the tentative part
    /// included, so the newest element replaces the one before. The stream ends after `finish` or
    /// `cancel`, or by itself, with an error when recognition fails.
    func start(run: SpeechRunID, locale: Locale, contextualStrings: [String]) async throws
        -> AsyncThrowingStream<String, any Error>

    /// Stops listening as `run` and returns its final text ("" when nothing was recognised, or when
    /// `run` is not the one listening).
    func finish(run: SpeechRunID) async -> String

    /// Stops listening as `run` and drops what was heard. Does nothing for any other run.
    func cancel(run: SpeechRunID) async
}
