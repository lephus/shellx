import Foundation

/// Turns the microphone into text while the user holds the mic (plan decision D8). The app's
/// implementations use Apple's speech recognition only: `SpeechAnalyzer` on iOS 26 and later,
/// otherwise `SFSpeechRecognizer`, on the device when it can, else on Apple's servers. Audio never
/// goes to ShellX or anyone else. Transcripts are never logged.
public protocol SpeechTranscribing: Sendable {
    /// Starts listening. Each element is the whole text heard so far, the tentative part included,
    /// so the newest element replaces the one before. The stream ends after `finish()` or `cancel()`,
    /// or with an error when recognition fails.
    func start(locale: Locale, contextualStrings: [String]) async throws -> AsyncThrowingStream<String, any Error>

    /// Stops listening and returns the final text ("" when nothing was recognised).
    func finish() async -> String

    /// Stops listening and drops what was heard.
    func cancel() async
}
