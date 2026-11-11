package com.shellx.app.ui.signin

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString

/**
 * The line under the sign-in title, typed like a terminal's: each tagline is typed, held, erased, and the next one
 * follows after a pause, for as long as the screen shows. Without motion the first tagline is there at once.
 */
object TypedTagline {
    /** Typing starts when the logo's chevrons are in place. */
    const val START_MS = SignInLogo.SLIDE_MS
    const val TYPE_MS = 28L
    const val HOLD_MS = 2_400L
    const val ERASE_MS = 12L
    const val PAUSE_MS = 300L

    enum class Phase { TYPING, HOLDING, ERASING, PAUSING }

    /** What shows at one moment: the first [shown] letters of tagline [line]. */
    data class Frame(val line: Int, val shown: Int, val phase: Phase)

    /** When each letter of each tagline shows; [letters] is how many letters each tagline has. */
    class Schedule(private val letters: List<Int>) {
        /** One round through every tagline. */
        val cycleMs: Long = 0

        /** Without motion: the first tagline, whole. */
        val still: Frame = Frame(0, 0, Phase.PAUSING)

        /** The frame at [ms] since the screen appeared. */
        fun at(ms: Long): Frame = still
    }

    /** Whether the cursor after the typed letters is lit at [ms]: steady while letters change, blinking at rest. */
    fun cursorOn(phase: Phase, ms: Long): Boolean = false

    /** Where each letter of [text] ends, so a letter and its accents are typed as one. */
    fun letters(text: String): IntArray = IntArray(0)

    /** [text] with its first [shown] characters in the text's colour and the rest [hidden]. */
    fun styled(text: String, shown: Int, hidden: Color = Color.Transparent): AnnotatedString = AnnotatedString("")
}
