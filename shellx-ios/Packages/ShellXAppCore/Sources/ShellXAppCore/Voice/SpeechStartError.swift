import Foundation

/// Why a transcriber could not start a run. `FallbackTranscriber` gives up the analyzer for a
/// language only on `recognizer`.
public enum SpeechStartError: Error {
    /// The recognizer itself failed (its context, format, preparation or start).
    case recognizer(any Error)
    /// The audio could not start (the session cannot activate during a call, no input). Passing:
    /// it fails this press only.
    case audio(any Error)
}
