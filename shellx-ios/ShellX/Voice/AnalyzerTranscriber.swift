import AVFoundation
import Foundation
import ShellXAppCore
import Speech

/// Dictation with `SpeechAnalyzer` (iOS 26 and later), on the iPhone: `SpeechTranscriber` with
/// volatile (tentative) results, or `DictationTranscriber` when only it has the language. The
/// workspace names and terms go in as the analysis context; the microphone's audio is converted to
/// the analyzer's best format.
///
/// It is the primary transcriber of a `FallbackTranscriber`: `readiness` says when it can run a
/// language now (its assets installed, and it never failed to start for it). Its start errors say
/// whose fault they were: `SpeechStartError.recognizer` (the analyzer's context, format, preparation
/// or start; the press falls back and the language stops being offered to the analyzer) or
/// `SpeechStartError.audio` (the microphone; that press fails, the analyzer stays).
///
/// Runs go through the `SpeechRunSlot` shared with `LegacyTranscriber`: the newest start takes the
/// microphone; a start that was overtaken or cancelled while it started never does. A run whose
/// results end by themselves gives the microphone back at once.
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
        private let lock = NSLock()
        private var resultsTask: Task<String, Never>?

        init(
            id: SpeechRunID, analyzer: SpeechAnalyzer, input: AsyncStream<AnalyzerInput>.Continuation,
            continuation: AsyncThrowingStream<String, any Error>.Continuation
        ) {
            self.id = id
            self.analyzer = analyzer
            self.input = input
            self.continuation = continuation
        }

        /// Reads the module's results into `continuation`; returns the final text.
        var results: Task<String, Never>? {
            get { lock.withLock { resultsTask } }
            set { lock.withLock { resultsTask = newValue } }
        }
    }

    private let audio: AudioCapture
    private let slot: SpeechRunSlot
    private let assets: AnalyzerAssets

    init(audio: AudioCapture, slot: SpeechRunSlot, assets: AnalyzerAssets) {
        self.audio = audio
        self.slot = slot
        self.assets = assets
    }

    /// Whether the analyzer can transcribe `locale` now. Starts downloading the assets when it could
    /// but they are missing. A locale it failed to start for counts as unsupported.
    static func readiness(for locale: Locale, assets: AnalyzerAssets) async -> Readiness {
        guard await !assets.hasFailed(locale), let module = await module(for: locale, assets: assets) else {
            return .unsupported
        }
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
        slot.begin(id)
        // The answer `readiness` just got: no second `supportedLocale` round on the first-word path.
        guard let module = await Self.module(for: locale, assets: assets) else {
            throw SpeechStartError.recognizer(LegacyTranscriber.Failure.unavailable)
        }
        // The analyzer's own steps: a failure here is the analyzer's.
        let analyzer: SpeechAnalyzer
        let format: AVAudioFormat
        let inputs: AsyncStream<AnalyzerInput>
        let input: AsyncStream<AnalyzerInput>.Continuation
        do {
            // Keep the model loaded between presses: the next first word comes sooner.
            analyzer = SpeechAnalyzer(
                modules: [module.base],
                options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering))
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualStrings
            try await analyzer.setContext(context)
            guard let best = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module.base]) else {
                throw LegacyTranscriber.Failure.unavailable
            }
            format = best
            try await analyzer.prepareToAnalyze(in: format)
            (inputs, input) = AsyncStream<AnalyzerInput>.makeStream()
            try await analyzer.start(inputSequence: inputs)
        } catch {
            throw SpeechStartError.recognizer(error)
        }

        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let run = Run(id: id, analyzer: analyzer, input: input, continuation: continuation)
        run.results = Task { [weak self] in
            let text = await Self.read(module, into: continuation)
            self?.resultsEnded(run)
            return text
        }
        let handlers = SpeechRunSlot.Handlers(
            finish: { [weak self] in await self?.finish(run) ?? "" },
            teardown: { [weak self] in await self?.tearDown(run) })
        switch slot.claim(id, handlers) {
        case .refused:
            // Overtaken or cancelled while starting: never takes the microphone.
            await tearDown(run)
            return stream
        case let .granted(replaced):
            await replaced?.teardown()
        }
        do {
            let slot = self.slot
            let converter = AudioBufferConverter(to: format)
            try audio.start(owner: id, stillWanted: { slot.isActive(id) }) { buffer in
                if let converted = converter.convert(buffer) { input.yield(AnalyzerInput(buffer: converted)) }
            }
        } catch {
            // The microphone's fault, not the analyzer's: this press fails, the analyzer stays.
            _ = slot.ended(id)
            await tearDown(run)
            throw SpeechStartError.audio(error)
        }
        return stream
    }

    func finish(run id: SpeechRunID) async -> String {
        await slot.takeForFinish(id)?.finish() ?? ""
    }

    func cancel(run id: SpeechRunID) async {
        await slot.cancel(id)?.teardown()
    }

    // MARK: - Private

    private func finish(_ run: Run) async -> String {
        audio.stop(owner: run.id)
        run.input.finish()
        let results = run.results
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
    }

    /// Stops a run's audio and analysis and ends its stream.
    private func tearDown(_ run: Run) async {
        audio.stop(owner: run.id)
        run.input.finish()
        await run.analyzer.cancelAndFinishNow()
        run.results?.cancel()
        run.continuation.finish()
    }

    /// The results ended by themselves (an error, the analyzer stopping): when `run` still holds the
    /// microphone, it gives it back now. (The model also cancels it.)
    private func resultsEnded(_ run: Run) {
        guard slot.ended(run.id) else { return }
        audio.stop(owner: run.id)
        run.input.finish()
        Task { await run.analyzer.cancelAndFinishNow() }
    }

    /// Asks iOS which module has `locale`: `SpeechTranscriber` when it has the language (and runs on
    /// this iPhone), else `DictationTranscriber` when it has it. `AnalyzerAssets` keeps the answer.
    private static func lookUpModule(_ locale: Locale) async -> AnalyzerAssets.ModuleChoice {
        if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return .speech(supported)
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return .dictation(supported)
        }
        return .unsupported
    }

    /// A new module for `locale` (one per press), from the answer kept in `assets`; nil when no module
    /// has the language.
    private static func module(for locale: Locale, assets: AnalyzerAssets) async -> Module? {
        switch await assets.module(for: locale, lookup: lookUpModule) {
        case let .speech(supported):
            return .speech(
                SpeechTranscriber(
                    locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults],
                    attributeOptions: []))
        case let .dictation(supported):
            return .dictation(
                DictationTranscriber(
                    locale: supported, contentHints: [.shortForm], transcriptionOptions: [.punctuation],
                    reportingOptions: [.volatileResults], attributeOptions: []))
        case .unsupported:
            return nil
        }
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
