package com.shellx.app.ui.signin

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import com.shellx.app.R
import kotlin.math.PI
import kotlin.math.cos

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
    const val BORDER = 0x17FFFFFFL
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

    /** The glow reaches a quarter of the square's side past its edge. */
    const val GLOW_REACH = VIEWPORT / 4

    /**
     * How hard the slide springs back: the overshoot is 4/27 · b³ / (b + 1)², 2.7 % here, which brings the chevrons'
     * tips within half a unit of each other and no closer.
     */
    private const val BACK = 0.85f

    /** The logo at one moment: [slide] 0 (chevrons at the edges) to 1 (in place), [underscore] and [glow] opacities. */
    data class Pose(val slide: Float, val underscore: Float, val glow: Float)

    /** The logo as the launcher shows it: what a screen without motion draws. */
    val REST = Pose(slide = 1f, underscore = 1f, glow = 0f)

    /** The slide's easing over 0…1: out fast, a little past 1 (at most [MAX_OVERSHOOT]), back to 1. */
    fun settle(t: Float): Float {
        val s = t.coerceIn(0f, 1f) - 1f
        return 1f + (BACK + 1f) * s * s * s + BACK * s * s
    }

    /** How far the chevrons have come at [ms]: 0 at the edges, 1 in place. */
    fun slide(ms: Long): Float = when {
        ms <= 0 -> 0f
        ms >= SLIDE_MS -> 1f
        else -> settle(ms.toFloat() / SLIDE_MS)
    }

    /** Whether a cursor that blinks with the logo's is lit at [ms]: all through the intro, then on and off. */
    fun cursorOn(ms: Long): Boolean = ms < INTRO_MS || (ms - INTRO_MS) % (BLINK_ON_MS + BLINK_OFF_MS) < BLINK_ON_MS

    /** The underscore's opacity at [ms]: it fades in once the chevrons are in place, then blinks. */
    fun underscore(ms: Long): Float = when {
        ms <= SLIDE_MS -> 0f
        ms < INTRO_MS -> (ms - SLIDE_MS).toFloat() / (INTRO_MS - SLIDE_MS)
        cursorOn(ms) -> 1f
        else -> 0f
    }

    /** The opacity of the glow around the square at [ms]: none during the intro, then [GLOW_MIN] to [GLOW_MAX] and back. */
    fun glow(ms: Long): Float {
        if (ms <= INTRO_MS) return 0f
        val since = ms - INTRO_MS
        val turn = (since % GLOW_PERIOD_MS).toDouble() / GLOW_PERIOD_MS
        val breath = (GLOW_MIN + GLOW_MAX) / 2 - (GLOW_MAX - GLOW_MIN) / 2 * cos(2 * PI * turn).toFloat()
        return breath * (since.toFloat() / GLOW_FADE_IN_MS).coerceAtMost(1f)
    }

    /** The logo at [ms] since the screen appeared. */
    fun pose(ms: Long): Pose = Pose(slide(ms), underscore(ms), glow(ms))
}

/**
 * The ShellX logo, [size] on a side, as [pose] says at each frame: the chevrons slide in from the square's edges, the
 * underscore blinks, a glow breathes around the square. [SignInLogo.REST] is the launcher's mark. A new pose redraws
 * the logo and recomposes nothing. TalkBack reads it as an image, "ShellX logo".
 */
@Composable
fun SignInLogo(size: Dp, pose: () -> SignInLogo.Pose, modifier: Modifier = Modifier) {
    val label = stringResource(R.string.signin_logo)
    Spacer(
        modifier
            .size(size)
            .testTag("signin.logo")
            .semantics {
                contentDescription = label
                role = Role.Image
            }
            .drawWithCache {
                val mark = LogoMark()
                val unit = this.size.minDimension / SignInLogo.VIEWPORT
                onDrawBehind { scale(unit, pivot = Offset.Zero) { mark.draw(this, pose()) } }
            },
    )
}

/** The mark's brushes and paths, in its own 512 units. */
private class LogoMark {
    private val side = Size(SignInLogo.VIEWPORT, SignInLogo.VIEWPORT)
    private val corner = CornerRadius(SignInLogo.CORNER)
    private val outline = Path().apply { addRoundRect(RoundRect(Rect(Offset.Zero, side), corner)) }
    private val square = Brush.verticalGradient(SignInLogo.SQUARE.map { Color(it) }, startY = 0f, endY = SignInLogo.VIEWPORT)
    private val glowColor = Color(SignInLogo.INNER_GLOW)
    private val innerGlow = Brush.radialGradient(
        listOf(glowColor.copy(alpha = SignInLogo.INNER_GLOW_ALPHA), glowColor.copy(alpha = 0f)),
        center = SignInLogo.INNER_GLOW_CENTER,
        radius = SignInLogo.INNER_GLOW_RADIUS,
    )
    private val border = Color(SignInLogo.BORDER)
    private val borderStroke = Stroke(SignInLogo.BORDER_WIDTH)
    private val prompt = chevron(SignInLogo.PROMPT)
    private val phone = chevron(SignInLogo.PHONE)
    private val mint = gradient(SignInLogo.MINT, SignInLogo.PROMPT)
    private val lilac = gradient(SignInLogo.LILAC, SignInLogo.PHONE)
    private val chevronStroke = Stroke(SignInLogo.STROKE, cap = StrokeCap.Round, join = StrokeJoin.Round)
    private val underscore = Brush.linearGradient(
        SignInLogo.MINT.map { Color(it) },
        start = SignInLogo.UNDERSCORE.topLeft,
        end = SignInLogo.UNDERSCORE.bottomRight,
    )

    private fun chevron(points: List<Offset>) = Path().apply {
        moveTo(points[0].x, points[0].y)
        for (point in points.drop(1)) lineTo(point.x, point.y)
    }

    /** The drawable's gradient: from the chevron's first point to its tip's x at its last point's y. */
    private fun gradient(colors: List<Long>, points: List<Offset>) =
        Brush.linearGradient(colors.map { Color(it) }, start = points.first(), end = Offset(points[1].x, points.last().y))

    fun draw(scope: DrawScope, pose: SignInLogo.Pose) = with(scope) {
        if (pose.glow > 0f) halo(pose.glow)
        drawRoundRect(square, size = side, cornerRadius = corner)
        drawRoundRect(innerGlow, size = side, cornerRadius = corner)
        val inset = SignInLogo.BORDER_INSET
        drawRoundRect(
            border,
            topLeft = Offset(inset, inset),
            size = Size(side.width - 2 * inset, side.height - 2 * inset),
            cornerRadius = CornerRadius(SignInLogo.CORNER - inset),
            style = borderStroke,
        )
        val away = (1f - pose.slide) * SignInLogo.TRAVEL
        if (away == 0f) {
            drawPath(phone, lilac, style = chevronStroke)
            drawPath(prompt, mint, style = chevronStroke)
        } else {
            // On their way the chevrons show only inside the square.
            clipPath(outline) {
                translate(left = away) { drawPath(phone, lilac, style = chevronStroke) }
                translate(left = -away) { drawPath(prompt, mint, style = chevronStroke) }
            }
        }
        if (pose.underscore > 0f) {
            drawRoundRect(
                underscore,
                topLeft = SignInLogo.UNDERSCORE.topLeft,
                size = SignInLogo.UNDERSCORE.size,
                cornerRadius = CornerRadius(SignInLogo.UNDERSCORE_CORNER),
                alpha = pose.underscore,
            )
        }
    }

    /**
     * The glow around the square, [opacity] at its edge and fading to nothing [SignInLogo.GLOW_REACH] out: rounded
     * squares one over another, each a little larger, so the glow keeps the square's shape. A blur would need API 31.
     */
    private fun DrawScope.halo(opacity: Float) {
        var under = 0f
        for (step in HALO_STEPS downTo 1) {
            val part = (HALO_STEPS - step + 1f) / HALO_STEPS
            val wanted = opacity * part * part
            val out = SignInLogo.GLOW_REACH * step / HALO_STEPS
            drawRoundRect(
                glowColor,
                topLeft = Offset(-out, -out),
                size = Size(side.width + 2 * out, side.height + 2 * out),
                cornerRadius = CornerRadius(SignInLogo.CORNER + out),
                // Over what the larger squares already laid down, this one brings the ring up to `wanted`.
                alpha = 1f - (1f - wanted) / (1f - under),
            )
            under = wanted
        }
    }

    private companion object {
        const val HALO_STEPS = 24
    }
}
