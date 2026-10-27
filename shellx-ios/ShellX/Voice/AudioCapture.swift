import AVFoundation
import Foundation

/// The microphone while the user holds the mic: a tap on `AVAudioEngine`'s input node. The audio
/// session (category `.record`, mode `.measurement`, ducking other audio) is activated by `start`
/// and deactivated by `stop` with `.notifyOthersOnDeactivation`, so music the user paused comes
/// back. Buffers go to the transcriber in memory only; nothing is written or sent anywhere.
final class AudioCapture: @unchecked Sendable {
    enum Failure: Error {
        /// The input has no channels or no sample rate (no microphone, or the route is gone).
        case noInput
    }

    private let lock = NSLock()
    private let engine = AVAudioEngine()
    private let meter: AudioLevelMeter
    private var running = false
    private var lastLevelUpdate: TimeInterval = 0

    init(meter: AudioLevelMeter) {
        self.meter = meter
    }

    /// Activates the session and starts the tap. `onBuffer` gets every buffer, in the returned
    /// format, on the audio thread. A running capture is stopped first.
    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws -> AVAudioFormat {
        stop()
        return try lock.withLock {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                throw Failure.noInput
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: makeTap(onBuffer))
            engine.prepare()
            do {
                try engine.start()
            } catch {
                input.removeTap(onBus: 0)
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                throw error
            }
            running = true
            return format
        }
    }

    /// Stops the tap and the engine and gives the audio back to other apps. Safe to call twice.
    func stop() {
        let stopped = lock.withLock { () -> Bool in
            guard running else { return false }
            running = false
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return true
        }
        guard stopped else { return }
        let meter = self.meter
        Task { @MainActor in meter.update(0) }
    }

    /// The tap: hands the buffer on, then reports its level at most every 50 ms. Built outside any
    /// actor, because the audio thread calls it.
    private func makeTap(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) -> AVAudioNodeTapBlock {
        { [weak self] buffer, _ in
            onBuffer(buffer)
            self?.report(Self.level(of: buffer))
        }
    }

    private func report(_ level: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        let due = lock.withLock { () -> Bool in
            guard now - lastLevelUpdate >= 0.05 else { return false }
            lastLevelUpdate = now
            return true
        }
        guard due else { return }
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
