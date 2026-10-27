import Foundation

/// The analyzer first, `SFSpeechRecognizer` otherwise (plan decision D8): a run starts on `primary`
/// when `usePrimary` says it can run the locale now, else on `fallback`.
///
/// - A `SpeechStartError.recognizer` from `primary` makes this press fall back, and `primaryFailed`
///   is told, so the app stops offering the analyzer for the language and Settings names the path
///   really used.
/// - Any other error (`SpeechStartError.audio`: a passing audio problem) fails the press and keeps
///   the analyzer for the next one.
/// - `finish` goes to the transcriber that started the run; `cancel` to both (each acts on its own
///   run only), so a run still starting is cancelled wherever it is.
///
/// Both transcribers share one `SpeechRunSlot`, so one run holds the microphone across them.
public final class FallbackTranscriber: SpeechTranscribing, @unchecked Sendable {
    private let primary: any SpeechTranscribing
    private let fallback: any SpeechTranscribing
    private let usePrimary: @Sendable (Locale) async -> Bool
    private let primaryFailed: @Sendable (Locale) async -> Void
    private let lock = NSLock()
    /// Which transcriber started each run still known (bounded: the newest few).
    private var startedOnPrimary: [(run: SpeechRunID, primary: Bool)] = []

    public init(
        primary: any SpeechTranscribing, fallback: any SpeechTranscribing,
        usePrimary: @escaping @Sendable (Locale) async -> Bool,
        primaryFailed: @escaping @Sendable (Locale) async -> Void
    ) {
        self.primary = primary
        self.fallback = fallback
        self.usePrimary = usePrimary
        self.primaryFailed = primaryFailed
    }

    public func start(run: SpeechRunID, locale: Locale, contextualStrings: [String]) async throws
        -> AsyncThrowingStream<String, any Error>
    {
        if await usePrimary(locale) {
            do {
                let stream = try await primary.start(run: run, locale: locale, contextualStrings: contextualStrings)
                remember(run, onPrimary: true)
                return stream
            } catch SpeechStartError.recognizer {
                await primaryFailed(locale)
            }
        }
        let stream = try await fallback.start(run: run, locale: locale, contextualStrings: contextualStrings)
        remember(run, onPrimary: false)
        return stream
    }

    public func finish(run: SpeechRunID) async -> String {
        let onPrimary = lock.withLock { startedOnPrimary.last(where: { $0.run == run })?.primary }
        switch onPrimary {
        case true?: return await primary.finish(run: run)
        case false?: return await fallback.finish(run: run)
        case nil: return ""
        }
    }

    public func cancel(run: SpeechRunID) async {
        await primary.cancel(run: run)
        await fallback.cancel(run: run)
    }

    private func remember(_ run: SpeechRunID, onPrimary: Bool) {
        lock.withLock {
            startedOnPrimary.append((run, onPrimary))
            if startedOnPrimary.count > 16 { startedOnPrimary.removeFirst(startedOnPrimary.count - 16) }
        }
    }
}
