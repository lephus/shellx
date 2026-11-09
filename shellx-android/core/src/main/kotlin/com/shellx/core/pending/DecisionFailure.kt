package com.shellx.core.pending

/** Why a decision was not taken. */
enum class DecisionFailure {
    /** The Mac had no live, synced session: nothing was sent, and nothing will be sent by itself when it is back
     *  (no queue). */
    OFFLINE,

    /** The Mac did not answer, even after one resend. Trying again is safe. */
    NO_ANSWER,

    /** The Mac answered that it cannot take this decision (`unknown`, or an error). */
    REJECTED,
}
