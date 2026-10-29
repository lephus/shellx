import Foundation

/// Reuses what iOS answered about a language's recognizers. Every press asks, so an answer with a
/// recognizer is kept for `reuse`, keeping the question off the way to the first word. An answer
/// without one is never kept: the next press asks again (the network may be back).
public actor VoiceCapabilityCache {
    public static let defaultReuse: Duration = .seconds(30)

    private let reuse: Duration
    private let ask: @Sendable (VoiceLanguage) async -> VoiceCapabilities
    private let startStopwatch: @Sendable () -> @Sendable () -> Duration
    private var kept: [VoiceLanguage: (capabilities: VoiceCapabilities, age: @Sendable () -> Duration)] = [:]

    public init(
        reuse: Duration = defaultReuse, clock: any Clock<Duration> = ContinuousClock(),
        ask: @escaping @Sendable (VoiceLanguage) async -> VoiceCapabilities
    ) {
        self.reuse = reuse
        self.ask = ask
        startStopwatch = Self.stopwatch(clock)
    }

    public func capabilities(for language: VoiceLanguage) async -> VoiceCapabilities {
        if let entry = kept[language], entry.age() < reuse { return entry.capabilities }
        let found = await ask(language)
        if found.engine != nil {
            kept[language] = (found, startStopwatch())
        } else {
            kept[language] = nil
        }
        return found
    }

    /// Drops the kept answer for `language`: the next question goes to iOS (the path changed, for
    /// example the analyzer failed to start and a press fell back to `SFSpeechRecognizer`).
    public func forget(_ language: VoiceLanguage) {
        kept[language] = nil
    }

    /// Returns a function that starts a stopwatch on `clock`: calling what it returns gives the time
    /// since it started.
    private static func stopwatch<C: Clock<Duration>>(_ clock: C) -> @Sendable () -> @Sendable () -> Duration {
        {
            let start = clock.now
            return { start.duration(to: clock.now) }
        }
    }
}
