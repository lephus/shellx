import Observation

/// How loud the microphone is while the user talks, from 0 (silence) to 1, for the level bar over
/// the composer. `AudioCapture` sets it about twenty times a second and back to 0 when it stops.
@MainActor @Observable
final class AudioLevelMeter {
    private(set) var level: Double = 0

    init(level: Double = 0) {
        self.level = min(max(level, 0), 1)
    }

    func update(_ level: Double) {
        self.level = min(max(level, 0), 1)
    }
}
