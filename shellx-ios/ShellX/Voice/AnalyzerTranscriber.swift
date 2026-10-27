import AVFoundation
import Foundation
import ShellXAppCore
import Speech

/// Dictation with `SpeechAnalyzer` (iOS 26 and later), on the iPhone: `SpeechTranscriber` with
/// volatile (tentative) results, or `DictationTranscriber` when only it has the language. The
/// workspace names and terms go in as the analysis context; the microphone's audio is converted to
/// the analyzer's best format. While the language's assets are not installed yet (they download in
/// the background), when the analyzer has no such language, or when it fails to start (then it is
/// not tried again for that language, and `onFallback` lets Settings name the path really used), a
/// press uses `LegacyTranscriber`.
///
/// One run at a time: starting a run tears down any other; `finish` and `cancel` act on the run they
/// name only. A run whose results end by itself (an error, the analyzer stopping) gives the
/// microphone back at once.
@available(iOS 26, *)
final class AnalyzerTranscriber: SpeechTranscribing, @unchecked Sendable {
    /// Whether the analyzer can transcribe a language now.
    enum Readiness: Equatable {
        case unsupported
        /// Supported, but its assets are not installed yet (the download was started).
        case needsAssets
        case ready
    }

    /// How long `finish` waits for the analyzer to finalize before it stops it.
    static let finalizeTimeout: Duration = .seconds(2)

    /// The module that has the language.
    private enum Module: Sendable {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)

        var base: any SpeechModule {
            switch self {
            case let .speech(module): return module
            case let .dictation(module): return module
            }
        }
    }

    /// One dictation through the analyzer.
    private final class Run: @unchecked Sendable {
        let id: SpeechRunID
        let analyzer: SpeechAnalyzer
        let input: AsyncStream<AnalyzerInput>.Continuation
        let continuation: AsyncThrowingStream<String, any Error>.Continuation
        /// Reads the module's results into `continuation`; returns the final text. Set once, under
        /// `AnalyzerTranscriber.lock`, right after the run is made.
        var results: Task<String, Never>?

        init(
            id: SpeechRunID, analyzer: SpeechAnalyzer, input: AsyncStream<AnalyzerInput>.Continuation,
            continuation: AsyncThrowingStream<String, any Error>.Continuation
        ) {
            self.id = id
            self.analyzer = analyzer
            self.input = input
            self.continuation = continuation
        }
    }

    private enum Active {
        case fallback(SpeechRunID)
        case analyzer(Run)

        var id: SpeechRunID {
            switch self {
            case let .fallback(id): return id
            case let .analyzer(run): return run.id
            }
        }
    }

    private let audio: AudioCapture
    private let fallback: LegacyTranscriber
    private let assets: AnalyzerAssets
    private let onFallback: @Sendable (Locale) -> Void
    private let lock = NSLock()
    private var active: Active?

    /// `onFallback` is told when the analyzer failed to start for a locale (and will not be tried
    /// again for it).
    init(
        audio: AudioCapture, fallback: LegacyTranscriber, assets: AnalyzerAssets,
        onFallback: @escaping @Sendable (Locale) -> Void = { _ in }
    ) {
        self.audio = audio
        self.fallback = fallback
        self.assets = assets
        self.onFallback = onFallback
    }

    /// Whether the analyzer can transcribe `locale` now. Starts downloading the assets when it could
    /// but they are missing. A locale it failed to start for counts as unsupported.
    static func readiness(for locale: Locale, assets: AnalyzerAssets) async -> Readiness {
        guard await !assets.hasFailed(locale), let module = await module(for: locale) else { return .unsupported }
        switch await AssetInventory.status(forModules: [module.base]) {
        case .installed:
            return .ready
        case .unsupported:
            return .unsupported
        default:
            await assets.install(module.base, locale: locale)
            return .needsAssets
        }
    }

    /// Whether `SpeechTranscriber` and `DictationTranscriber` list `locale` (for the ledger).
    static func supports(_ locale: Locale) async -> (speech: Bool, dictation: Bool) {
        let speech = SpeechTranscriber.isAvailable ? await SpeechTranscriber.supportedLocale(equivalentTo: locale) : nil
        let dictation = await DictationTranscriber.supportedLocale(equivalentTo: locale)
        return (speech != nil, dictation != nil)
    }

    // MARK: - SpeechTranscribing

    func start(run id: SpeechRunID, locale: Locale, contextualStrings: [String]) async throws
        -> AsyncThrowingStream<String, any Error>
    {
        if let other = take(unless: id) { await tearDown(other) }
        if await !assets.hasFailed(locale), let module = await Self.module(for: locale) {
            if await AssetInventory.status(forModules: [module.base]) == .installed {
                do {
                    return try await startAnalyzer(id, module: module, contextualStrings: contextualStrings)
                } catch {
                    // The analyzer could not start: this press and the next ones go through
                    // SFSpeechRecognizer, and Settings is told which path that is.
                    await assets.markFailed(locale)
                    onFallback(locale)
                }
            } else {
                await assets.install(module.base, locale: locale)
            }
        }
        let previous = lock.withLock { () -> Active? in
            defer { active = .fallback(id) }
            return active
        }
        if let previous, previous.id != id { await tearDown(previous) }
        return try await fallback.start(run: id, locale: locale, contextualStrings: contextualStrings)
    }

    func finish(run id: SpeechRunID) async -> String {
        switch take(id) {
        case let .fallback(id):
            return await fallback.finish(run: id)
        case let .analyzer(run):
            audio.stop()
            run.input.finish()
            let results = lock.withLock { run.results }
            return await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    try? await run.analyzer.finalizeAndFinishThroughEndOfInput()
                    return await results?.value ?? ""
                }
                group.addTask {
                    try? await Task.sleep(for: Self.finalizeTimeout)
                    return nil
                }
                let first = await group.next() ?? nil
                if let first {
                    group.cancelAll()
                    return first
                }
                // Took too long: stop the analyzer, which ends the other child, and keep what came.
                await run.analyzer.cancelAndFinishNow()
                return await results?.value ?? ""
            }
        case nil:
            return ""
        }
    }

    func cancel(run id: SpeechRunID) async {
        if let run = take(id) { await tearDown(run) }
    }

    // MARK: - Private

    /// The active run when it is `id`, made inactive.
    private func take(_ id: SpeechRunID) -> Active? {
        lock.withLock {
            guard let current = active, current.id == id else { return nil }
            active = nil
            return current
        }
    }

    /// The active run when it is not `id`, made inactive.
    private func take(unless id: SpeechRunID) -> Active? {
        lock.withLock {
            guard let current = active, current.id != id else { return nil }
            active = nil
            return current
        }
    }

    /// Stops a run's audio and analysis and ends its stream.
    private func tearDown(_ run: Active) async {
        switch run {
        case let .fallback(id):
            await fallback.cancel(run: id)
        case let .analyzer(run):
            audio.stop()
            run.input.finish()
            await run.analyzer.cancelAndFinishNow()
            lock.withLock { run.results }?.cancel()
            run.continuation.finish()
        }
    }

    /// The results ended by themselves (an error, the analyzer stopping): when `run` is still the
    /// active one, it stops holding the microphone now. (The model also cancels it.)
    private func resultsEnded(_ run: Run) {
        let stillActive = lock.withLock { () -> Bool in
            guard case let .analyzer(current) = active, current === run else { return false }
            active = nil
            return true
        }
        guard stillActive else { return }
        audio.stop()
        run.input.finish()
        Task { await run.analyzer.cancelAndFinishNow() }
    }

    private func startAnalyzer(_ id: SpeechRunID, module: Module, contextualStrings: [String]) async throws
        -> AsyncThrowingStream<String, any Error>
    {
        // Keep the model loaded between presses: the next first word comes sooner.
        let analyzer = SpeechAnalyzer(
            modules: [module.base], options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering))
        let context = AnalysisContext()
        context.contextualStrings[.general] = contextualStrings
        try await analyzer.setContext(context)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module.base]) else {
            throw LegacyTranscriber.Failure.unavailable
        }
        try await analyzer.prepareToAnalyze(in: format)

        let (inputs, input) = AsyncStream<AnalyzerInput>.makeStream()
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let run = Run(id: id, analyzer: analyzer, input: input, continuation: continuation)
        let results = Task { [weak self] in
            let text = await Self.read(module, into: continuation)
            self?.resultsEnded(run)
            return text
        }
        lock.withLock { run.results = results }
        do {
            try await analyzer.start(inputSequence: inputs)
            // This run replaces any other: the other one is torn down, never left holding the mic.
            let previous = lock.withLock { () -> Active? in
                defer { active = .analyzer(run) }
                return active
            }
            if let previous { await tearDown(previous) }
            let converter = AudioBufferConverter(to: format)
            _ = try audio.start { buffer in
                if let converted = converter.convert(buffer) { input.yield(AnalyzerInput(buffer: converted)) }
            }
        } catch {
            _ = take(id)
            audio.stop()
            input.finish()
            await analyzer.cancelAndFinishNow()
            results.cancel()
            throw error
        }
        return stream
    }

    /// `SpeechTranscriber` when it has the language (and runs on this iPhone), else
    /// `DictationTranscriber` when it has it; nil when neither does.
    private static func module(for locale: Locale) async -> Module? {
        if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return .speech(
                SpeechTranscriber(
                    locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults],
                    attributeOptions: []))
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return .dictation(
                DictationTranscriber(
                    locale: supported, contentHints: [.shortForm], transcriptionOptions: [.punctuation],
                    reportingOptions: [.volatileResults], attributeOptions: []))
        }
        return nil
    }

    private static func read(_ module: Module, into continuation: AsyncThrowingStream<String, any Error>.Continuation) async -> String {
        switch module {
        case let .speech(transcriber):
            return await collect(transcriber.results, into: continuation) { (String($0.text.characters), $0.isFinal) }
        case let .dictation(transcriber):
            return await collect(transcriber.results, into: continuation) { (String($0.text.characters), $0.isFinal) }
        }
    }

    /// Sends the whole text after each result (`TranscriptAccumulator`: finalized segments plus the
    /// newest volatile tail); returns the text at the end. Fails the stream only when nothing was
    /// heard.
    private static func collect<Results: AsyncSequence & Sendable>(
        _ results: Results, into continuation: AsyncThrowingStream<String, any Error>.Continuation,
        parts: @Sendable (Results.Element) -> (text: String, isFinal: Bool)
    ) async -> String {
        var transcript = TranscriptAccumulator()
        do {
            for try await result in results {
                let part = parts(result)
                continuation.yield(transcript.take(part.text, isFinal: part.isFinal))
            }
            continuation.finish()
        } catch {
            if transcript.text.isEmpty {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
        return transcript.text
    }
}
