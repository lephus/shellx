package com.shellx.app.ui.signin

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect

/**
 * The ShellX mark drawn in code, so the sign-in screen can move it: at rest it is `res/drawable/shellx_logo.xml`
 * (`design/shellx-logo.svg`, the launcher icon). Everything that moves is a function of the time since the screen
 * appeared, in milliseconds.
 */
object SignInLogo {
    /** The mark's own units: the SVG's 512 × 512 box. */
    const val VIEWPORT = 512f

    /** The rounded square's corner radius. */
    const val CORNER = 114f

    /** The square's fill, top to bottom, ARGB. */
    val SQUARE: List<Long> = listOf(0xFF1C1438, 0xFF0B0716)

    /** The glow inside the square: its colour (22 % in the middle, none at the rim), middle and radius. */
    const val INNER_GLOW = 0xFF4AF2A1
    const val INNER_GLOW_ALPHA = 0x38 / 255f
    val INNER_GLOW_CENTER = Offset(215.04f, 235.52f)
    const val INNER_GLOW_RADIUS = 215.04f

    /** The square's hairline: white at 9 %, 3 units wide, 2 units inside the edge. */
    const val BORDER = 0x17FFFFFF
    const val BORDER_WIDTH = 3f
    const val BORDER_INSET = 2f

    /** ">", the computer's side and the prompt: mint, from the left. */
    val PROMPT: List<Offset> = listOf(Offset(128f, 122f), Offset(222f, 234f), Offset(128f, 346f))
    val MINT: List<Long> = listOf(0xFF7DF7BE, 0xFF2FD98A)

    /** "<", the phone's side: white to lilac, from the right. */
    val PHONE: List<Offset> = listOf(Offset(384f, 122f), Offset(290f, 234f), Offset(384f, 346f))
    val LILAC: List<Long> = listOf(0xFFFFFFFF, 0xFFCFC8EE)

    /** Both chevrons' stroke, with round caps and joins. */
    const val STROKE = 54f

    /** The prompt's underscore (the cursor), mint, with corners of [UNDERSCORE_CORNER]. */
    val UNDERSCORE = Rect(300f, 398f, 384f, 424f)
    const val UNDERSCORE_CORNER = 8f

    /** The logo's side on a phone, and in a window less than 600 dp tall or in landscape. */
    const val SIZE_DP = 96
    const val COMPACT_SIZE_DP = 72

    /** How far each chevron starts from its place: half the square, which leaves it wholly outside. */
    const val TRAVEL = 256f

    /** The chevrons' slide, and the whole intro: the underscore comes in between the two. */
    const val SLIDE_MS = 650L
    const val INTRO_MS = 900L

    /** The furthest the chevrons pass their place before settling, as a part of [TRAVEL]. */
    const val MAX_OVERSHOOT = 0.04f

    /** The underscore blinks like a terminal's cursor once the intro is over. */
    const val BLINK_ON_MS = 530L
    const val BLINK_OFF_MS = 530L

    /** The glow around the square after the intro: its opacity breathes between the two, once every [GLOW_PERIOD_MS]. */
    const val GLOW_MIN = 0.25f
    const val GLOW_MAX = 0.45f
    const val GLOW_PERIOD_MS = 4_000L

    /** The glow comes up from nothing over this long, then breathes. */
    const val GLOW_FADE_IN_MS = 400L

    /** The logo at one moment: [slide] 0 (chevrons at the edges) to 1 (in place), [underscore] and [glow] opacities. */
    data class Pose(val slide: Float, val underscore: Float, val glow: Float)

    /** The logo as the launcher shows it: what a screen without motion draws. */
    val REST = Pose(slide = 1f, underscore = 1f, glow = 0f)

    /** The slide's easing over 0…1: out fast, a little past 1 (at most [MAX_OVERSHOOT]), back to 1. */
    fun settle(t: Float): Float = t

    /** How far the chevrons have come at [ms]: 0 at the edges, 1 in place. */
    fun slide(ms: Long): Float = 1f

    /** Whether a cursor that blinks with the logo's is lit at [ms]. */
    fun cursorOn(ms: Long): Boolean = true

    /** The underscore's opacity at [ms]. */
    fun underscore(ms: Long): Float = 1f

    /** The opacity of the glow around the square at [ms]. */
    fun glow(ms: Long): Float = 0f

    /** The logo at [ms] since the screen appeared. */
    fun pose(ms: Long): Pose = REST
}
