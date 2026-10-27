import Foundation
import Observation
import ShellXAppCore

/// The signed-in account's voice input, put in the environment by `SignedInView`: it makes a
/// `VoiceInputModel` for each place with a mic (the composers, the question and plan sheets), keeps
/// the spoken language (Settings › Voice, saved in `UserDefaults`) and which recognizer runs for it,
/// and holds the level meter the mic's live text shows. Without one in the environment, no mic shows
/// and the keyboard is the only input (render tests, previews).
///
/// `cancelAll()` stops every mic at once: the audio was interrupted (a call), the input went away,
/// or the app left the foreground.
@MainActor @Observable
final class VoiceService {
    private(set) var language: VoiceLanguage
    /// The recognizer for `language`; nil when none can run. Read by `refreshEngine()`.
    private(set) var engine: VoiceEngine?
    /// True once `refreshEngine()` answered for the current language.
    private(set) var engineKnown = false
    let meter: AudioLevelMeter

    /// A model made here, held weakly so its language follows Settings.
    private struct Made {
        weak var model: VoiceInputModel?
    }

    @ObservationIgnored private let transcriber: any SpeechTranscribing
    @ObservationIgnored private let permissions: any VoicePermissionChecking
    @ObservationIgnored private let cache: VoiceCapabilityCache
    @ObservationIgnored private let contextualStrings: @MainActor () -> [String]
    @ObservationIgnored private let latency: LatencyLog
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var made: [Made] = []

    init(
        transcriber: any SpeechTranscribing, permissions: any VoicePermissionChecking, cache: VoiceCapabilityCache,
        meter: AudioLevelMeter, latency: LatencyLog, defaults: UserDefaults,
        contextualStrings: @escaping @MainActor () -> [String]
    ) {
        self.transcriber = transcriber
        self.permissions = permissions
        self.cache = cache
        self.meter = meter
        self.latency = latency
        self.defaults = defaults
        self.contextualStrings = contextualStrings
        language = VoiceLanguage.saved(in: defaults)
    }

    /// Apple's speech recognition on this iPhone, with the workspace names of `hub`'s live sessions
    /// as context: `SpeechAnalyzer` on iOS 26 and later (falling back to `SFSpeechRecognizer` while
    /// its assets download, or for good when it fails to start), `SFSpeechRecognizer` before.
    static func system(latency: LatencyLog, defaults: UserDefaults, hub: MachineHub) -> VoiceService {
        let owner = Owner()
        let meter = AudioLevelMeter()
        let audio = AudioCapture(meter: meter)
        audio.onLost = { Task { @MainActor in await owner.service?.cancelAll() } }
        let assets = AnalyzerAssets()
        let legacy = LegacyTranscriber(audio: audio)
        let transcriber: any SpeechTranscribing
        if #available(iOS 26, *) {
            transcriber = AnalyzerTranscriber(
                audio: audio, fallback: legacy, assets: assets,
                onFallback: { locale in Task { @MainActor in await owner.service?.analyzerFellBack(locale) } })
        } else {
            transcriber = legacy
        }
        let probe = VoiceCapabilityProbe.system(assets: assets)
        let service = VoiceService(
            transcriber: transcriber, permissions: SystemVoicePermissions(),
            cache: VoiceCapabilityCache { await probe.capabilities(for: $0) }, meter: meter, latency: latency,
            defaults: defaults,
            contextualStrings: { [weak hub] in
                VoiceInputModel.contextualStrings(workspaceTitles: hub?.liveSessions.map(\.session.workspaceTitle) ?? [])
            })
        owner.service = service
        return service
    }

    /// A dictation model for one mic; `maxBytes` is the most its text may take.
    func makeModel(maxBytes: Int = ComposerValidation.maxBytes) -> VoiceInputModel {
        let cache = self.cache
        let model = VoiceInputModel(
            transcriber: transcriber, permissions: permissions, capabilities: { await cache.capabilities(for: $0) },
            language: language, contextualStrings: contextualStrings, latency: latency, clock: ContinuousClock(),
            maxBytes: maxBytes)
        made = made.filter { $0.model != nil } + [Made(model: model)]
        return model
    }

    /// Saves the spoken language; every mic uses it from its next press.
    func setLanguage(_ language: VoiceLanguage) {
        guard language != self.language else { return }
        self.language = language
        language.save(in: defaults)
        engineKnown = false
        for entry in made { entry.model?.language = language }
    }

    /// Asks iOS which recognizer runs for the current language.
    func refreshEngine() async {
        let asked = language
        let engine = await cache.capabilities(for: asked).engine
        guard asked == language else { return }
        self.engine = engine
        engineKnown = true
    }

    /// Stops every mic that listens now and drops its words.
    func cancelAll() async {
        for entry in made {
            await entry.model?.cancel()
        }
    }

    /// The analyzer failed to start for `locale`, so presses go through `SFSpeechRecognizer`: ask
    /// again, so Settings names that path (Apple's servers when it cannot run on this iPhone).
    func analyzerFellBack(_ locale: Locale) async {
        guard let fallen = VoiceLanguage.allCases.first(where: { $0.locale.identifier == locale.identifier }) else {
            return
        }
        await cache.forget(fallen)
        if fallen == language { await refreshEngine() }
    }

    /// Lets the platform pieces made before the service reach it.
    @MainActor
    private final class Owner {
        weak var service: VoiceService?
    }
}
