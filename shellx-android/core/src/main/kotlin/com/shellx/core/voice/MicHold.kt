package com.shellx.core.voice

/**
 * The mic's hold gesture, turned into what the mic does. Compose's pointer input gives the same two signals as the
 * iPhone's gesture (3E): the hold state, true while the finger is down and reset both when the gesture ends and when
 * it is taken away, and the lift, which comes only when the finger goes up.
 *
 * Only a lift sends. A hold whose state is reset without a lift was taken away (the workspace pager or a scrolling
 * list claimed the touch): what was heard is dropped, as a drag to the left drops it, so half-spoken words never
 * reach the agent.
 *
 * The mic calls [holdingChanged] when the state changes, [ended] on the lift, and [settle] on the main thread's next
 * turn after the state went false, so a decision that needs both signals waits until both have come, in whichever
 * order they arrive. Mutable (Conventions): one owner, not thread-safe.
 */
class MicHold {
    enum class Step {
        /** Start listening. */
        PRESS,

        /** Finish and send what was heard. */
        RELEASE,

        /** Drop what was heard. */
        CANCEL,

        /** Nothing to do. */
        NONE,
    }

    private enum class State {
        /** No hold, or one that was sent or dropped. */
        IDLE,

        /** The finger is down. */
        HOLDING,

        /** The finger lifted; the state's reset is still to come. */
        LIFTED,

        /** The state was reset and no lift came yet: [settle] decides. */
        RESET,
    }

    private var state = State.IDLE

    /** The gesture's state changed to [holding]. */
    fun holdingChanged(holding: Boolean): Step {
        if (holding) {
            return when (state) {
                State.IDLE, State.LIFTED -> {
                    state = State.HOLDING
                    Step.PRESS
                }
                State.HOLDING, State.RESET -> Step.NONE
            }
        }
        state = when (state) {
            State.HOLDING -> State.RESET
            State.LIFTED -> State.IDLE
            State.IDLE, State.RESET -> state
        }
        return Step.NONE
    }

    /** The gesture ended: the finger lifted. */
    fun ended(): Step = when (state) {
        State.HOLDING -> {
            state = State.LIFTED
            Step.RELEASE
        }
        State.RESET -> {
            // The reset came first; the lift still sends.
            state = State.IDLE
            Step.RELEASE
        }
        State.IDLE, State.LIFTED -> Step.NONE
    }

    /** The main thread's next turn after the gesture's state went false: a hold reset without a lift is cancelled. */
    fun settle(): Step {
        if (state != State.RESET) return Step.NONE
        state = State.IDLE
        return Step.CANCEL
    }
}
