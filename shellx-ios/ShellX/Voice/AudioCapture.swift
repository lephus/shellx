import AVFoundation
import Foundation
import ShellXAppCore

/// The microphone while the user holds the mic: a tap on `AVAudioEngine`'s input node. The audio
/// session (category `.record`, mode `.measurement`, ducking other audio) is activated by `start`
/// and deactivated by `stop` with `.notifyOthersOnDeactivation`, so music the user paused comes
/// back. Buffers go to the transcriber in memory only; nothing is written or sent anywhere.
///
/// Each capture belongs to one dictation (`owner`): `stop(owner:)` stops only that one, so the late
/// teardown of an old run can never stop a newer capture, and `start` gives up when its run no longer
/// holds the microphone (`stillWanted`).
///
/// Engine work (`start`, `stop`) runs one at a time on `engineQueue`, which the audio thread never
/// touches: `removeTap` waits for a tap block still running, so the tap must never wait for
/// anything `stop` holds. The tap only takes `levelLock`, which nothing else holds while waiting.
///
/// An interruption (a call, Siri), or a route change that takes away the input in use, stops the
/// capture and calls `onLost`, so the dictation is cancelled rather than left listening to nothing.
/// An output-only device leaving (AirPods, a speaker) keeps the dictation (`AudioInputRoute`).
final class AudioCapture: @unchecked Sendable {
    enum Failure: Error {
        /// The input has no channels or no sample rate (no microphone, or the route is gone).
        case noInput
    }

    private let engineQueue = DispatchQueue(label: "com.shellx.audio-capture")
    private let engine = AVAudioEngine()
    private let meter: AudioLevelMeter
    /// The dictation the running capture belongs to. Read and written on `engineQueue` only.
    private var owner: SpeechRunID?
    private let levelLock = NSLock()
    private var throttle = AudioLevelThrottle()
    private let lostLock = NSLock()
    private var lostHandler: (@Sendable () -> Void)?
    private let notifications: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(meter: AudioLevelMeter, notifications: NotificationCenter = .default) {
        self.meter = meter
        self.notifications = notifications
        let session = AVAudioSession.sharedInstance()
        observers = [
            notifications.addObserver(
                forName: AVAudioSession.interruptionNotification, object: session, queue: nil
            ) { [weak self] note in
                let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
                if type == .began { self?.lose() }
            },
            notifications.addObserver(
                forName: AVAudioSession.routeChangeNotification, object: session, queue: nil
            ) { [weak self] note in
                if Self.inputLost(note) { self?.lose() }
            },
        ]
    }

    deinit {
        for observer in observers { notifications.removeObserver(observer) }
    }

    /// Called (on any thread) when a running capture was interrupted or lost its input.
    var onLost: (@Sendable () -> Void)? {
        get { lostLock.withLock { lostHandler } }
        set { lostLock.withLock { lostHandler = newValue } }
    }

    /// Activates the session and starts the tap for `owner`, replacing any other capture, unless
    /// `stillWanted` says the run no longer holds the microphone (then false, and nothing changes).
    /// `onBuffer` gets every buffer, in the input's format, on the audio thread.
    @discardableResult
    func start(
        owner run: SpeechRunID, stillWanted: @escaping @Sendable () -> Bool,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws -> Bool {
        try engineQueue.sync {
            guard stillWanted() else { return false }
            tearDown()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                throw Failure.noInput
            }
            levelLock.withLock { throttle = AudioLevelThrottle() }
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: makeTap(onBuffer))
            engine.prepare()
            do {
                try engine.start()
            } catch {
                input.removeTap(onBus: 0)
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                throw error
            }
            owner = run
            return true
        }
    }

    /// Stops `owner`'s capture and gives the audio back to other apps. Does nothing when another run
    /// owns the capture now, or when none runs.
    func stop(owner run: SpeechRunID) {
        engineQueue.sync {
            guard owner == run else { return }
            tearDown()
        }
    }

    // MARK: - Private

    /// On `engineQueue` only, holding no lock: the audio thread may still be inside the tap.
    private func tearDown() {
        guard owner != nil else { return }
        owner = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let meter = self.meter
        Task { @MainActor in meter.update(0) }
    }

    /// Stops a running capture and tells `onLost`. Asynchronous: the session may post the
    /// notification while `start` or `stop` runs on `engineQueue`.
    private func lose() {
        engineQueue.async { [weak self] in
            guard let self, self.owner != nil else { return }
            self.tearDown()
            self.onLost?()
        }
    }

    /// A route change that takes away the input in use (or every input); an output-only device
    /// leaving is not one.
    private static func inputLost(_ note: Notification) -> Bool {
        let session = AVAudioSession.sharedInstance()
        let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
            .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        guard reason == .oldDeviceUnavailable || !session.isInputAvailable else { return false }
        let previous = (note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)?
            .inputs.map(\.uid) ?? []
        return AudioInputRoute.inputLost(
            previousInputs: Set(previous), currentInputs: Set(session.currentRoute.inputs.map(\.uid)),
            inputAvailable: session.isInputAvailable)
    }

    /// The tap: hands the buffer on, then reports its level about 20 times a second of audio
    /// (`AudioLevelThrottle`, counted in frames). Built outside any actor: the audio thread calls it.
    private func makeTap(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) -> AVAudioNodeTapBlock {
        { [weak self] buffer, _ in
            onBuffer(buffer)
            self?.report(buffer)
        }
    }

    private func report(_ buffer: AVAudioPCMBuffer) {
        let due = levelLock.withLock {
            throttle.take(frames: Int(buffer.frameLength), sampleRate: buffer.format.sampleRate)
        }
        guard due else { return }
        let level = Self.level(of: buffer)
        let meter = self.meter
        Task { @MainActor in meter.update(level) }
    }

    /// The buffer's loudness from 0 to 1: its RMS in decibels, -50 dB and below being silence.
    private static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count { sum += channel[index] * channel[index] }
        let rms = (sum / Float(count)).squareRoot()
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(Double(rms))
        return min(max((decibels + 50) / 50, 0), 1)
    }
}
