import AVFoundation
import Foundation
import ShellXAppCore
import Speech

/// Dictation with `SpeechAnalyzer` (iOS 26 and later), on the iPhone: `SpeechTranscriber` with
/// volatile (tentative) results, or `DictationTranscriber` when only it has the language. The
/// workspace names and terms go in as the analysis context; the microphone's audio is converted to
/// the analyzer's best format. While the language's assets are not installed yet (they download in
/// the background), or when the analyzer has no such language, a press uses `LegacyTranscriber`.
@available(iOS 26, *)
final class AnalyzerTranscriber: SpeechTranscribing, @unchecked Sendable {
    /// Whether the analyzer can transcribe a language now.
    enum Readiness: Equatable {
        case unsupported
        /// Supported, but its assets are not installed yet (the download was started).
        case needsAssets
        case ready
    }

    /// How long `finish()` waits for the analyzer to finalize before it stops it.
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
        let analyzer: SpeechAnalyzer
        let input: AsyncStream<AnalyzerInput>.Continuation
        let continuation: AsyncThrowingStream<String, any Error>.Continuation
        /// Reads the module's results into `continuation`; returns the final text.
        let results: Task<String, Never>

        init(
            analyzer: SpeechAnalyzer, input: AsyncStream<AnalyzerInput>.Continuation,
            continuation: AsyncThrowingStream<String, any Error>.Continuation, results: Task<String, Never>
        ) {
            self.analyzer = analyzer
            self.input = input
            self.continuation = continuation
            self.results = results
        }
    }

    private enum Active {
        case fallback
        case analyzer(Run)
    }

    private let audio: AudioCapture
    private let fallback: LegacyTranscriber
    private let assets: AnalyzerAssets
    private let lock = NSLock()
    private var active: Active?

    init(audio: AudioCapture, fallback: LegacyTranscriber, assets: AnalyzerAssets) {
        self.audio = audio
        self.fallback = fallback
        self.assets = assets
    }

    /// Whether the analyzer can transcribe `locale` now. Starts downloading the assets when it could
    /// but they are missing.
    static func readiness(for locale: Locale, assets: AnalyzerAssets) async -> Readiness {
        guard let module = await module(for: locale) else { return .unsupported }
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

    func start(locale: Locale, contextualStrings: [String]) async throws -> AsyncThrowingStream<String, any Error> {
        await cancel()
        if let module = await Self.module(for: locale) {
            if await AssetInventory.status(forModules: [module.base]) == .installed {
                do {
                    return try await startAnalyzer(module, contextualStrings: contextualStrings)
                } catch {
                    // The analyzer could not start: this press goes through SFSpeechRecognizer.
                }
            } else {
                await assets.install(module.base, locale: locale)
            }
        }
        lock.withLock { active = .fallback }
        return try await fallback.start(locale: locale, contextualStrings: contextualStrings)
    }

    func finish() async -> String {
        switch take() {
        case .fallback:
            return await fallback.finish()
        case let .analyzer(run):
            audio.stop()
            run.input.finish()
            return await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    try? await run.analyzer.finalizeAndFinishThroughEndOfInput()
                    return await run.results.value
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
                return await run.results.value
            }
        case nil:
            return ""
        }
    }

    func cancel() async {
        switch take() {
        case .fallback:
            await fallback.cancel()
        case let .analyzer(run):
            audio.stop()
            run.input.finish()
            await run.analyzer.cancelAndFinishNow()
            run.results.cancel()
            run.continuation.finish()
        case nil:
            break
        }
    }

    // MARK: - Private

    private func take() -> Active? {
        lock.withLock {
            defer { active = nil }
            return active
        }
    }

    private func startAnalyzer(_ module: Module, contextualStrings: [String]) async throws -> AsyncThrowingStream<String, any Error> {
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
        let results = Task { await Self.read(module, into: continuation) }
        let run = Run(analyzer: analyzer, input: input, continuation: continuation, results: results)
        do {
            try await analyzer.start(inputSequence: inputs)
            let converter = AudioBufferConverter(to: format)
            _ = try audio.start { buffer in
                if let converted = converter.convert(buffer) { input.yield(AnalyzerInput(buffer: converted)) }
            }
        } catch {
            audio.stop()
            input.finish()
            await analyzer.cancelAndFinishNow()
            results.cancel()
            throw error
        }
        lock.withLock { active = .analyzer(run) }
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

    /// Sends the finalized text plus the newest volatile text after each result; returns the text
    /// at the end. Fails the stream only when nothing was heard.
    private static func collect<Results: AsyncSequence & Sendable>(
        _ results: Results, into continuation: AsyncThrowingStream<String, any Error>.Continuation,
        parts: @Sendable (Results.Element) -> (text: String, isFinal: Bool)
    ) async -> String {
        var finalized = ""
        var volatile = ""
        do {
            for try await result in results {
                let part = parts(result)
                if part.isFinal {
                    finalized += part.text
                    volatile = ""
                } else {
                    volatile = part.text
                }
                continuation.yield(finalized + volatile)
            }
            continuation.finish()
        } catch {
            if (finalized + volatile).isEmpty {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
        return finalized + volatile
    }
}
