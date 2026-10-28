/// The mic's hold gesture as SwiftUI reports it, turned into what the mic does (`MicButton`). SwiftUI gives
/// two signals: the gesture's state (`@GestureState`), true while the finger is down and reset both when the
/// gesture ends and when it is cancelled, and `onEnded`, which comes only when the finger lifts.
///
/// The mic calls `holdingChanged(_:)` when the state changes, `ended()` from `onEnded`, and `settle()` on the
/// main actor's next turn after the state went false, so a decision that needs both signals waits until
/// both have come, in whichever order SwiftUI delivers them.
public struct MicHold: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// Start listening.
        case press
        /// Finish and send what was heard.
        case release
        /// Drop what was heard.
        case cancel
        /// Nothing to do.
        case none
    }

    /// The finger is down: the gesture's state went true and has not been reset yet.
    private var down = false

    public init() {}

    /// The gesture's state changed to `holding`.
    public mutating func holdingChanged(_ holding: Bool) -> Step {
        if holding {
            guard !down else { return .none }
            down = true
            return .press
        }
        guard down else { return .none }
        down = false
        return .release
    }

    /// The gesture ended: the finger lifted.
    public mutating func ended() -> Step {
        .none
    }

    /// The main actor's next turn after the gesture's state went false.
    public mutating func settle() -> Step {
        .none
    }
}
