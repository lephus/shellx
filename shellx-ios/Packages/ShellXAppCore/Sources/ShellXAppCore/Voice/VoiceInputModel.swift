import Foundation
import Observation

/// Hold-to-talk (spec section 4, plan decision D8). `press()` checks the permissions and that some
/// recognizer can run, then listens; the words show in `phase` as they come; `release()` returns
/// them. A drag to the left arms cancel (`drag(dx:dy:)`); a swipe up before any word asks for the
/// keyboard instead. With VoiceOver the same calls make a tap-to-start, tap-to-finish button.
///
/// - The keyboard always stays usable: no recognizer (`unavailable`) also sets `wantsKeyboard`;
///   denied permissions only say so (`denied`) until the next press.
/// - Past `maxBytes` UTF-8 bytes, listening stops on its own; the words within the limit are kept
///   and `limitReached` is set, so nothing longer than the composer accepts is ever sent.
/// - `firstWordLatency` is the time from `press()` to the first update with a word, also recorded
///   in the `LatencyLog` (`firstWord`, target 300 ms). Transcripts are never logged.
@MainActor @Observable
public final class VoiceInputModel {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Listening (or starting to); `text` is everything heard so far.
        case listening(text: String)
        /// Still listening, but releasing now cancels.
        case cancelArmed(text: String)
        /// Released; waiting for the recognizer's final text.
        case finishing
        /// A permission is missing: the screen says so and offers Settings.
        case denied(VoicePermission)
        /// No recognizer can run now (no network and nothing on the device): the screen says so.
        case unavailable
    }

    /// How far left (points) a drag arms cancel.
    public static let cancelDistance: Double = 80
    /// How far up (points) a swipe asks for the keyboard, before any word.
    public static let keyboardDistance: Double = 60
    /// Terms added to every recognition, so Vietnamese mixed with these English words is heard right.
    public static let terms = ["PR", "CI", "push", "pull request", "branch", "merge", "deploy", "commit", "Claude"]

    public private(set) var phase: Phase = .idle
    /// Set when the user swiped up before any word, or when no recognizer can run: the screen opens
    /// the keyboard, then sets this back to false.
    public var wantsKeyboard = false
    /// From the last `press()` to its first update with a word; nil until then.
    public private(set) var firstWordLatency: Duration?
    /// The last dictation stopped at `maxBytes`.
    public private(set) var limitReached = false
    /// The language of the next press.
    public var language: VoiceLanguage
    /// The most UTF-8 bytes one dictation keeps.
    public let maxBytes: Int

    /// Where the recognizer of the current press stands.
    private enum Recognition {
        /// Checking permissions and capabilities, or starting the recognizer.
        case starting
        /// Running: updates are taken.
        case running
        /// Stopped by itself (the limit, an error, its own end): what was heard is kept.
        case stopped
    }

    @ObservationIgnored private let transcriber: any SpeechTranscribing
    @ObservationIgnored private let permissions: any VoicePermissionChecking
    @ObservationIgnored private let capabilities: @Sendable (VoiceLanguage) async -> VoiceCapabilities
    @ObservationIgnored private let contextualStrings: @MainActor () -> [String]
    @ObservationIgnored private let latency: LatencyLog
    @ObservationIgnored private let startStopwatch: @MainActor () -> @MainActor () -> Duration
    /// Counts presses; work of an older press is dropped.
    @ObservationIgnored private var attempt = 0
    /// The current press was released (or cancelled) while it was still starting.
    @ObservationIgnored private var released = false
    @ObservationIgnored private var recognition = Recognition.stopped
    @ObservationIgnored private var text = ""
    @ObservationIgnored private var elapsed: (@MainActor () -> Duration)?
    @ObservationIgnored private var reader: Task<Void, Never>?

    public init(
        transcriber: any SpeechTranscribing, permissions: any VoicePermissionChecking,
        capabilities: @escaping @Sendable (VoiceLanguage) async -> VoiceCapabilities, language: VoiceLanguage,
        contextualStrings: @escaping @MainActor () -> [String], latency: LatencyLog, clock: any Clock<Duration>,
        maxBytes: Int = ComposerValidation.maxBytes
    ) {
        self.transcriber = transcriber
        self.permissions = permissions
        self.capabilities = capabilities
        self.language = language
        self.contextualStrings = contextualStrings
        self.latency = latency
        self.maxBytes = maxBytes
        startStopwatch = Self.stopwatch(clock)
    }

    /// The workspace names of the live sessions, then `terms`, without blanks or repeats.
    public static func contextualStrings(workspaceTitles: [String]) -> [String] {
        var seen = Set<String>()
        var strings: [String] = []
        for string in workspaceTitles + terms {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            strings.append(trimmed)
        }
        return strings
    }

    /// Listening, cancel armed or finishing.
    public var isActive: Bool {
        switch phase {
        case .listening, .cancelArmed, .finishing: return true
        case .idle, .denied, .unavailable: return false
        }
    }

    // MARK: - Gestures

    /// The finger went down (or VoiceOver's first tap): checks the permissions and that a recognizer
    /// can run, then listens. Does nothing while a dictation is active.
    public func press() async {
        guard !isActive else { return }
        attempt += 1
        let current = attempt
        released = false
        recognition = .starting
        text = ""
        limitReached = false
        wantsKeyboard = false
        firstWordLatency = nil
        elapsed = startStopwatch()
        phase = .listening(text: "")

        guard await permissions.microphone() else { return refuse(current, .denied(.microphone)) }
        guard await permissions.speech() else { return refuse(current, .denied(.speech)) }
        guard await capabilities(language).engine != nil else { return refuse(current, .unavailable) }
        guard attempt == current, !released else { return }

        let stream: AsyncThrowingStream<String, any Error>
        do {
            stream = try await transcriber.start(locale: language.locale, contextualStrings: contextualStrings())
        } catch {
            return refuse(current, .unavailable)
        }
        guard attempt == current, !released else {
            // Released while the recognizer started: stop it again.
            await transcriber.cancel()
            return
        }
        recognition = .running
        reader = Task { [weak self] in await self?.read(stream, attempt: current) }
    }

    /// The finger moved by (`dx`, `dy`) points from where it went down.
    public func drag(dx: Double, dy: Double) {
        switch phase {
        case .listening, .cancelArmed: break
        default: return
        }
        if dy <= -Self.keyboardDistance, Self.isBlank(text) {
            wantsKeyboard = true
            if stop() {
                let transcriber = self.transcriber
                Task { await transcriber.cancel() }
            }
            return
        }
        phase = dx <= -Self.cancelDistance ? .cancelArmed(text: text) : .listening(text: text)
    }

    /// The finger went up (or VoiceOver's second tap): the final text, trimmed, unless cancel was
    /// armed or nothing was said. Nil also while nothing listens.
    public func release() async -> String? {
        switch phase {
        case .listening:
            break
        case .cancelArmed:
            if stop() { await transcriber.cancel() }
            return nil
        default:
            released = true
            return nil
        }
        switch recognition {
        case .starting:
            // The press stops the recognizer if it starts after all.
            _ = stop()
            return nil
        case .stopped:
            phase = .idle
            return Self.nonBlank(text)
        case .running:
            phase = .finishing
            let finalText = await transcriber.finish()
            recognition = .stopped
            reader?.cancel()
            reader = nil
            let words = Self.isBlank(finalText) ? text : finalText
            phase = .idle
            return Self.nonBlank(cut(words))
        }
    }

    /// Stops listening at once and drops the words: the mic's screen went away. Does nothing while
    /// nothing listens.
    public func cancel() async {
        switch phase {
        case .listening, .cancelArmed:
            if stop() { await transcriber.cancel() }
        default:
            break
        }
    }

    /// Clears a denied or unavailable message (the user typed instead, or closed it).
    public func dismiss() {
        switch phase {
        case .denied, .unavailable: phase = .idle
        default: break
        }
    }

    // MARK: - Private

    /// Ends a press that cannot listen. The reason shows even when the finger is already up (the
    /// permission prompt took it), unless a newer press started.
    private func refuse(_ current: Int, _ reason: Phase) {
        guard attempt == current else { return }
        recognition = .stopped
        if reason == .unavailable { wantsKeyboard = true }
        phase = reason
    }

    /// Stops listening now and drops the words. True when the recognizer was running: the caller
    /// cancels it.
    private func stop() -> Bool {
        released = true
        let wasRunning = recognition == .running
        recognition = .stopped
        reader?.cancel()
        reader = nil
        phase = .idle
        return wasRunning
    }

    private func read(_ stream: AsyncThrowingStream<String, any Error>, attempt current: Int) async {
        do {
            for try await update in stream {
                guard attempt == current, recognition == .running else { return }
                take(update)
            }
            guard attempt == current, recognition == .running else { return }
            recognition = .stopped
        } catch {
            guard attempt == current, recognition == .running else { return }
            recognition = .stopped
            // Nothing heard: no recognizer works right now. Otherwise the words stay to be sent.
            if Self.isBlank(text), case .listening = phase {
                wantsKeyboard = true
                phase = .unavailable
            }
        }
    }

    private func take(_ update: String) {
        let kept = cut(update)
        text = kept
        if firstWordLatency == nil, !Self.isBlank(kept), let elapsed {
            let duration = elapsed()
            firstWordLatency = duration
            latency.record(.firstWord, duration)
        }
        switch phase {
        case .listening: phase = .listening(text: kept)
        case .cancelArmed: phase = .cancelArmed(text: kept)
        default: break
        }
        if limitReached, recognition == .running {
            // Stop listening at the limit; the kept words stay until release.
            recognition = .stopped
            let transcriber = self.transcriber
            Task { await transcriber.cancel() }
        }
    }

    /// `text` cut to `maxBytes` UTF-8 bytes on a character boundary; sets `limitReached` when cut.
    private func cut(_ text: String) -> String {
        guard text.utf8.count > maxBytes else { return text }
        limitReached = true
        var kept = ""
        var used = 0
        for character in text {
            let size = character.utf8.count
            guard used + size <= maxBytes else { break }
            used += size
            kept.append(character)
        }
        return kept
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func nonBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Returns a function that starts a stopwatch on `clock`: calling what it returns gives the time
    /// since it started.
    private static func stopwatch<C: Clock<Duration>>(_ clock: C) -> @MainActor () -> @MainActor () -> Duration {
        {
            let start = clock.now
            return { start.duration(to: clock.now) }
        }
    }
}
