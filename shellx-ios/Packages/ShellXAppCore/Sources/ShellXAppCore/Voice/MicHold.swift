/// The mic's hold gesture as SwiftUI reports it, turned into what the mic does (`MicButton`). SwiftUI gives
/// two signals: the gesture's state (`@GestureState`), true while the finger is down and reset both when the
/// gesture ends and when it is cancelled, and `onEnded`, which comes only when the finger lifts.
///
/// Only a lift sends. A hold whose state is reset without `onEnded` was taken away (the workspace pager or a
/// scroll view claimed the touch): what was heard is dropped, as a drag to the left drops it, so half-spoken
/// words never reach the agent.
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

    private enum State: Equatable, Sendable {
        /// No hold, or one that was sent or dropped.
        case idle
        /// The finger is down.
        case holding
        /// The finger lifted; the state's reset is still to come.
        case lifted
        /// The state was reset and no lift came yet: `settle()` decides.
        case reset
    }

    private var state = State.idle

    public init() {}

    /// The gesture's state changed to `holding`.
    public mutating func holdingChanged(_ holding: Bool) -> Step {
        if holding {
            switch state {
            case .idle, .lifted:
                state = .holding
                return .press
            case .holding, .reset:
                return .none
            }
        }
        switch state {
        case .holding:
            state = .reset
        case .lifted:
            state = .idle
        case .idle, .reset:
            break
        }
        return .none
    }

    /// The gesture ended: the finger lifted.
    public mutating func ended() -> Step {
        switch state {
        case .holding:
            state = .lifted
            return .release
        case .reset:
            // The reset came first; the lift still sends.
            state = .idle
            return .release
        case .idle, .lifted:
            return .none
        }
    }

    /// The main actor's next turn after the gesture's state went false: a hold reset without a lift is
    /// cancelled.
    public mutating func settle() -> Step {
        guard state == .reset else { return .none }
        state = .idle
        return .cancel
    }
}
