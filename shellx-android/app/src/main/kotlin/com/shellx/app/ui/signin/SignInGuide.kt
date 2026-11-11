package com.shellx.app.ui.signin

/**
 * The three numbered steps on the sign-in screen. They come in one after another when the logo's chevrons are in
 * place, each fading in while it rises, then stay.
 */
object SignInGuide {
    /** The first row starts when the logo's chevrons are in place; each next one [STEP_MS] later. */
    const val START_MS = SignInLogo.SLIDE_MS
    const val STEP_MS = 80L
    const val ROW_MS = 250L

    /** How far a row rises while it comes in, in dp. */
    const val RISE_DP = 8

    const val ROWS = 3

    /** When the last row is in. */
    const val END_MS = 0L

    /** How far row [row] (from 0) has come in at [ms]: 0 unseen and [RISE_DP] low, 1 in place. Null: no motion. */
    fun reveal(row: Int, ms: Long?): Float = 1f
}
