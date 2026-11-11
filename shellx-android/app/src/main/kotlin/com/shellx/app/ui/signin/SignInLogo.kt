package com.shellx.app.ui.signin

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.CacheDrawScope
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.center
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Canvas
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import com.shellx.app.R
import kotlin.math.PI
import kotlin.math.ceil
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

    /**
     * The glow around the square after the intro: a ring of these colours round the square's middle, clockwise in
     * this order and evenly spaced. The last is the first again, so the ring has no seam.
     */
    val GLOW_COLORS: List<Long> = listOf(0xFF4AF2A1, 0xFF60A5FA, 0xFFA78BFA, 0xFFF472B6, 0xFFFBBF24, 0xFF4AF2A1)

    /** The ring of colours turns clockwise, once round every [GLOW_TURN_MS]. */
    const val GLOW_TURN_MS = 6_000L

    /**
     * The glow's opacity breathes from the first to the second and back, once every [GLOW_PERIOD_MS]: on a dark page,
     * and on a light one, where the same colours need less to show.
     */
    val GLOW_DARK: ClosedFloatingPointRange<Float> = 0.35f..0.60f
    val GLOW_LIGHT: ClosedFloatingPointRange<Float> = 0.25f..0.45f
    const val GLOW_PERIOD_MS = 4_000L

    /** The glow comes up from nothing over this long, then breathes. */
    const val GLOW_FADE_IN_MS = 400L

    /**
     * The glow reaches a quarter of the square's side past the middle of each edge: a disc of [GLOW_RADIUS] round the
     * square's middle, at full strength as far as the edge ([GLOW_FULL]) and fading to nothing at its rim.
     */
    const val GLOW_REACH = VIEWPORT / 4
    const val GLOW_FULL = VIEWPORT / 2
    const val GLOW_RADIUS = GLOW_FULL + GLOW_REACH

    /**
     * How hard the slide springs back: the overshoot is 4/27 · b³ / (b + 1)², 2.7 % here, which brings the chevrons'
     * tips within half a unit of each other and no closer.
     */
    private const val BACK = 0.85f

    /**
     * The logo at one moment: [slide] 0 (chevrons at the edges) to 1 (in place), the [underscore]'s opacity, and the
     * glow: how much of it is there ([glow], 0 none to 1 all of it), where its breath stands ([breath], 0 its faintest
     * to 1 its strongest) and how far its colours have turned ([turn], degrees clockwise).
     */
    data class Pose(val slide: Float, val underscore: Float, val glow: Float, val breath: Float, val turn: Float) {
        /** The glow's opacity on a [dark] page or a light one. */
        fun glowOpacity(dark: Boolean): Float {
            val range = glowRange(dark)
            return glow * (range.start + (range.endInclusive - range.start) * breath)
        }
    }

    /** The logo as the launcher shows it: what a screen without motion draws. No glow. */
    val REST = Pose(slide = 1f, underscore = 1f, glow = 0f, breath = 0f, turn = 0f)

    /** Between which opacities the glow breathes on a [dark] page or a light one. */
    fun glowRange(dark: Boolean): ClosedFloatingPointRange<Float> = if (dark) GLOW_DARK else GLOW_LIGHT

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

    /** How much of the glow around the square is there at [ms]: none during the intro, all [GLOW_FADE_IN_MS] later. */
    fun glow(ms: Long): Float = ((ms - INTRO_MS).toFloat() / GLOW_FADE_IN_MS).coerceIn(0f, 1f)

    /** Where the glow's breath stands at [ms]: 0 (its faintest) as the intro ends, 1 half a loop later, and back. */
    fun breath(ms: Long): Float {
        if (ms <= INTRO_MS) return 0f
        val loop = ((ms - INTRO_MS) % GLOW_PERIOD_MS).toDouble() / GLOW_PERIOD_MS
        return ((1 - cos(2 * PI * loop)) / 2).toFloat()
    }

    /** How far the glow's colours have turned at [ms], in degrees clockwise: 0 as the intro ends, under 360 always. */
    fun turn(ms: Long): Float = if (ms <= INTRO_MS) 0f else (ms - INTRO_MS) % GLOW_TURN_MS * 360f / GLOW_TURN_MS

    /** The logo at [ms] since the screen appeared. */
    fun pose(ms: Long): Pose = Pose(slide(ms), underscore(ms), glow(ms), breath(ms), turn(ms))
}

/**
 * The ShellX logo, [size] on a side, as [pose] says at each frame: the chevrons slide in from the square's edges, the
 * underscore blinks, a glow of several colours turns and breathes around the square (stronger on a dark page).
 * [SignInLogo.REST] is the launcher's mark. A new pose redraws the logo and recomposes nothing. TalkBack reads it as
 * an image, "ShellX logo"; the glow is decoration and says nothing.
 */
@Composable
fun SignInLogo(size: Dp, pose: () -> SignInLogo.Pose, modifier: Modifier = Modifier) {
    val label = stringResource(R.string.signin_logo)
    // The glow is seen against the page: the theme's background says which opacity it takes.
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
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
                // The square and the glow never change: each is drawn once into an image. The square is then drawn
                // the way a vector drawable is, so its edge is the drawable's to the pixel, and a frame costs two
                // images (the glow, turned as far as it has come and at its opacity, and the square), the chevrons
                // and the underscore. The glow is a disc round the logo's middle: turning the image turns the colours.
                val reach = SignInLogo.GLOW_REACH * unit
                val square = image(this.size.minDimension) { scale(unit, pivot = Offset.Zero) { mark.square(this) } }
                val halo = image(this.size.minDimension + 2 * reach) { scale(unit, pivot = Offset.Zero) { mark.halo(this) } }
                onDrawBehind {
                    val now = pose()
                    val glow = now.glowOpacity(dark)
                    if (glow > 0f && halo != null) {
                        rotate(now.turn) { drawImage(halo, topLeft = Offset(-reach, -reach), alpha = glow) }
                    }
                    if (square != null) drawImage(square)
                    scale(unit, pivot = Offset.Zero) { mark.glyphs(this, now) }
                }
            },
    )
}

/** What [draw] draws in a square of [side] pixels, as an image; null while the logo has no size. */
private fun CacheDrawScope.image(side: Float, draw: DrawScope.() -> Unit): ImageBitmap? {
    val pixels = ceil(side).toInt()
    if (pixels <= 0) return null
    val image = ImageBitmap(pixels, pixels)
    CanvasDrawScope().draw(this, layoutDirection, Canvas(image), Size(side, side), draw)
    return image
}

/**
 * The mark's brushes and paths, in its own 512 units. The rounded shapes are built from path data, as the drawable
 * spells them, and not as round rectangles: their edges then fall on the same pixels as the drawable's.
 */
private class LogoMark {
    private val side = Size(SignInLogo.VIEWPORT, SignInLogo.VIEWPORT)
    private val outline = rounded(Rect(Offset.Zero, side), SignInLogo.CORNER)
    private val fill = Brush.verticalGradient(SignInLogo.SQUARE.map { Color(it) }, startY = 0f, endY = SignInLogo.VIEWPORT)
    private val glowColor = Color(SignInLogo.INNER_GLOW)
    private val innerGlow = Brush.radialGradient(
        listOf(glowColor.copy(alpha = SignInLogo.INNER_GLOW_ALPHA), glowColor.copy(alpha = 0f)),
        center = SignInLogo.INNER_GLOW_CENTER,
        radius = SignInLogo.INNER_GLOW_RADIUS,
    )
    private val haloBox = Size(2 * SignInLogo.GLOW_RADIUS, 2 * SignInLogo.GLOW_RADIUS)

    /**
     * The halo's box and some way past it on every side. The image the halo is drawn into is whole pixels, and the box
     * of a logo an odd number of pixels wide ends half way through one: the fade is drawn over this, so it covers
     * that pixel whole. Ending at the box, it would cover half of it and leave a line of the ring's colour there.
     */
    private val haloCover = Rect(Offset.Zero, haloBox).inflate(HALO_SPILL)
    private val haloRing = Brush.sweepGradient(SignInLogo.GLOW_COLORS.map { Color(it) }, center = haloBox.center)

    /**
     * How much of the ring shows at each distance from the middle: all of it under the square, then less and less,
     * gently at both ends (a smooth step), to none at the rim.
     */
    private val haloFade = Brush.radialGradient(
        colorStops = (
            listOf(0f to Color.Black) + (0..HALO_STEPS).map { step ->
                val out = step.toFloat() / HALO_STEPS
                val at = (SignInLogo.GLOW_FULL + SignInLogo.GLOW_REACH * out) / SignInLogo.GLOW_RADIUS
                at to Color.Black.copy(alpha = 1f - out * out * (3f - 2f * out))
            }
            ).toTypedArray(),
        center = haloBox.center,
        radius = SignInLogo.GLOW_RADIUS,
    )
    private val border = Color(SignInLogo.BORDER)
    private val borderLine = rounded(
        Rect(Offset.Zero, side).deflate(SignInLogo.BORDER_INSET),
        SignInLogo.CORNER - SignInLogo.BORDER_INSET,
    )
    private val borderStroke = Stroke(SignInLogo.BORDER_WIDTH, cap = StrokeCap.Round, join = StrokeJoin.Round)
    private val prompt = chevron(SignInLogo.PROMPT)
    private val phone = chevron(SignInLogo.PHONE)
    private val mint = gradient(SignInLogo.MINT, SignInLogo.PROMPT)
    private val lilac = gradient(SignInLogo.LILAC, SignInLogo.PHONE)
    private val chevronStroke = Stroke(SignInLogo.STROKE, cap = StrokeCap.Round, join = StrokeJoin.Round)
    private val underscore = rounded(SignInLogo.UNDERSCORE, SignInLogo.UNDERSCORE_CORNER)
    private val underscoreMint = Brush.linearGradient(
        SignInLogo.MINT.map { Color(it) },
        start = SignInLogo.UNDERSCORE.topLeft,
        end = SignInLogo.UNDERSCORE.bottomRight,
    )

    /** [rect] with corners of [radius], in the drawable's own commands: a line and an arc for each side. */
    private fun rounded(rect: Rect, radius: Float): Path {
        val (left, top, right, bottom) = rect
        val arc = "A$radius,$radius 0,0 1,"
        return PathParser().parsePathString(
            "M${left + radius},${top}H${right - radius}$arc$right ${top + radius}V${bottom - radius}" +
                "$arc${right - radius} ${bottom}H${left + radius}$arc$left ${bottom - radius}V${top + radius}" +
                "$arc${left + radius} ${top}Z",
        ).toPath()
    }

    private fun chevron(points: List<Offset>) = Path().apply {
        moveTo(points[0].x, points[0].y)
        for (point in points.drop(1)) lineTo(point.x, point.y)
    }

    /** The drawable's gradient: from the chevron's first point to its tip's x at its last point's y. */
    private fun gradient(colors: List<Long>, points: List<Offset>) =
        Brush.linearGradient(colors.map { Color(it) }, start = points.first(), end = Offset(points[1].x, points.last().y))

    /** The rounded square: its fill, the glow inside it and its hairline. */
    fun square(scope: DrawScope) = with(scope) {
        drawPath(outline, fill)
        drawPath(outline, innerGlow)
        drawPath(borderLine, border, style = borderStroke)
    }

    /** The two chevrons, as far in as [pose] says, and the underscore. */
    fun glyphs(scope: DrawScope, pose: SignInLogo.Pose) = with(scope) {
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
        if (pose.underscore > 0f) drawPath(underscore, underscoreMint, alpha = pose.underscore)
    }

    /**
     * The glow around the square at full strength, in a box of twice [SignInLogo.GLOW_RADIUS]: the ring of colours
     * round the box's middle, of which the fade keeps what its opacity says (a blur would need API 31). Drawn into an
     * image of its own: the fade takes away from what is under it, everywhere in the image and not only in the box.
     */
    fun halo(scope: DrawScope) = with(scope) {
        drawRect(haloRing, size = haloBox)
        drawRect(haloFade, topLeft = haloCover.topLeft, size = haloCover.size, blendMode = BlendMode.DstIn)
    }

    private companion object {
        /** The fade's curve is this many straight pieces. */
        const val HALO_STEPS = 16

        /** How far past the halo's box the fade is drawn, in the mark's units: more than a pixel at any size. */
        const val HALO_SPILL = 64f
    }
}
