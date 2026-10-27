import Foundation

/// The analyzer first, `SFSpeechRecognizer` otherwise (plan decision D8): a run starts on `primary`
/// when `usePrimary` says it can run the locale now, else on `fallback`.
///
/// - The press begins in the shared `SpeechRunSlot` at entry, before any await, so which press is the
///   newest is decided by the order of the presses, never by which readiness check returns first.
/// - A `SpeechStartError.recognizer` from `primary` makes this press fall back, and `primaryFailed`
///   is told, so the app stops offering the analyzer for the language and Settings names the path
///   really used.
/// - Any other error (`SpeechStartError.audio`: a passing audio problem) fails the press and keeps
///   the analyzer for the next one.
/// - `finish` and `cancel` go through the slot, which holds the handlers of whichever transcriber
///   claimed the run, so a run can never be left holding the microphone.
///
/// Both transcribers share `slot`, so one run holds the microphone across them.
public final class FallbackTranscriber: SpeechTranscribing {
    private let slot: SpeechRunSlot
    private let primary: any SpeechTranscribing
    private let fallback: any SpeechTranscribing
    private let usePrimary: @Sendable (Locale) async -> Bool
    private let primaryFailed: @Sendable (Locale) async -> Void

    public init(
        slot: SpeechRunSlot, primary: any SpeechTranscribing, fallback: any SpeechTranscribing,
        usePrimary: @escaping @Sendable (Locale) async -> Bool,
        primaryFailed: @escaping @Sendable (Locale) async -> Void
    ) {
        self.slot = slot
        self.primary = primary
        self.fallback = fallback
        self.usePrimary = usePrimary
        self.primaryFailed = primaryFailed
    }

    public func start(run: SpeechRunID, locale: Locale, contextualStrings: [String]) async throws
        -> AsyncThrowingStream<String, any Error>
    {
        slot.begin(run)
        if await usePrimary(locale) {
            do {
                return try await primary.start(run: run, locale: locale, contextualStrings: contextualStrings)
            } catch SpeechStartError.recognizer {
                await primaryFailed(locale)
            }
        }
        return try await fallback.start(run: run, locale: locale, contextualStrings: contextualStrings)
    }

    public func finish(run: SpeechRunID) async -> String {
        await slot.takeForFinish(run)?.finish() ?? ""
    }

    public func cancel(run: SpeechRunID) async {
        await slot.cancel(run)?.teardown()
    }
}
