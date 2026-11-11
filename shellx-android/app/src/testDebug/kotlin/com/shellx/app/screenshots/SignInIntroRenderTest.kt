package com.shellx.app.screenshots

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.ui.signin.SignInContent
import com.shellx.app.ui.signin.SignInGuide
import com.shellx.app.ui.signin.SignInLogo
import com.shellx.app.ui.signin.TypedTagline
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The sign-in intro, drawn at chosen moments: every piece is a function of the time since the screen appeared, so a
 * render at a fixed time is a still frame of the animation. The logo at rest is the launcher's mark, pixel for pixel.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class SignInIntroRenderTest {
    /** A plain page with [content] 24 dp (72 px) in from its top-left corner. */
    @Composable
    private fun Page(content: @Composable () -> Unit) {
        Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(24.dp)) { content() }
    }

    @Composable
    private fun taglines(): List<String> = listOf(
        stringResource(R.string.signin_tagline_1),
        stringResource(R.string.signin_tagline_2),
        stringResource(R.string.signin_tagline_3),
    )

    /** The pixels of the 96 dp (288 px) square whose top-left corner is at ([left], 72). */
    private fun square(shot: Snapshot, left: Int): List<Int> =
        (72 until 360).flatMap { y -> (left until left + 288).map { x -> shot.pixel(x, y) } }

    /** The same square without its four corners (66 px each way), where the page shows past the rounded edge. */
    private fun inside(shot: Snapshot, left: Int): List<Int> = (0 until 288).flatMap { y ->
        (0 until 288).filterNot { x -> (x < 66 || x >= 222) && (y < 66 || y >= 222) }.map { x -> shot.pixel(left + x, 72 + y) }
    }

    /** As bright as a chevron or the underscore: the square itself, its glow and its hairline are all dark. */
    private fun bright(argb: Int): Boolean = maxOf((argb shr 16) and 0xFF, (argb shr 8) and 0xFF, argb and 0xFF) > 150

    /** Green stands out over red and blue: the cursor's and the numbers' colour, in light and dark. */
    private fun green(argb: Int): Boolean {
        val r = (argb shr 16) and 0xFF
        val g = (argb shr 8) and 0xFF
        val b = argb and 0xFF
        return g - maxOf(r, b) > 60
    }

    @Test
    fun theLogoAtRestIsTheLaunchersMark() {
        val shots = assertRenders("signin-logo") {
            Page {
                Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                    Image(painterResource(R.drawable.shellx_logo), contentDescription = null, modifier = Modifier.size(96.dp))
                    SignInLogo(96.dp, pose = { SignInLogo.REST })
                }
            }
        }
        for (shot in shots) {
            // The drawable at x = 72, the drawn logo 96 + 24 dp (360 px) to its right.
            val drawable = square(shot, 72)
            val drawn = square(shot, 432)
            val distances = drawable.zip(drawn) { a, b -> colourDistance(a, b) }
            val worst = distances.max()
            val differing = distances.count { it > 0 }
            assertTrue("${shot.file.name}: the logo is drawn", inside(shot, 432).count(::bright) > 5_000)
            assertEquals(
                "${shot.file.name}: the drawn logo is the drawable, pixel for pixel (worst distance $worst)",
                0,
                differing,
            )
        }
    }

    @Test
    fun theChevronsComeFromOutsideTheSquare() {
        val start = assertRenders("signin-logo-start") { Page { SignInLogo(96.dp, pose = { SignInLogo.pose(0) }) } }
        val rest = assertRenders("signin-logo-rest") { Page { SignInLogo(96.dp, pose = { SignInLogo.REST }) } }
        for ((first, last) in start.zip(rest)) {
            val atStart = inside(first, 72).count(::bright)
            assertEquals("${first.file.name}: an empty square, no chevron and no underscore yet", 0, atStart)
            assertTrue("${last.file.name}: both chevrons and the underscore", inside(last, 72).count(::bright) > 5_000)
        }
    }

    /** The mean colour of the 5 × 5 px around ([x], [y]). */
    private fun mean(shot: Snapshot, x: Int, y: Int): Int {
        var r = 0
        var g = 0
        var b = 0
        for (dy in -2..2) {
            for (dx in -2..2) {
                val argb = shot.pixel(x + dx, y + dy)
                r += (argb shr 16) and 0xFF
                g += (argb shr 8) and 0xFF
                b += argb and 0xFF
            }
        }
        return (0xFF shl 24) or ((r / 25) shl 16) or ((g / 25) shl 8) or (b / 25)
    }

    /**
     * The glow 4 dp (12 px) outside the middle of each side of the 96 dp square at (72, 72): above it, right of it,
     * below it, left of it.
     */
    private fun ring(shot: Snapshot): List<Int> =
        listOf(216 to 60, 371 to 216, 216 to 371, 60 to 216).map { (x, y) -> mean(shot, x, y) }

    /** A colour's hue in degrees: 0 red, 120 green, 240 blue. */
    private fun hue(argb: Int): Float {
        val r = ((argb shr 16) and 0xFF).toFloat()
        val g = ((argb shr 8) and 0xFF).toFloat()
        val b = (argb and 0xFF).toFloat()
        val most = maxOf(r, g, b)
        val spread = most - minOf(r, g, b)
        if (spread == 0f) return 0f
        val sixth = when (most) {
            r -> (g - b) / spread
            g -> (b - r) / spread + 2
            else -> (r - g) / spread + 4
        }
        return (sixth * 60 + 360) % 360
    }

    /** How far apart two hues are round the colour wheel, in degrees. */
    private fun apart(a: Float, b: Float): Float = abs(a - b).let { minOf(it, 360 - it) }

    /** The hues among [colours] that are clearly their own: 40° or more from each one before. */
    private fun hues(colours: List<Int>): List<Float> =
        colours.map(::hue).fold(emptyList()) { seen, next -> if (seen.all { apart(it, next) >= 40f }) seen + next else seen }

    @Test
    fun theGlowIsARingOfColoursThatTurns() {
        // The glow at its strongest, half a breath after the intro, and a quarter turn (1.5 s) later.
        val first = SignInLogo.INTRO_MS + 2_000
        val second = first + 1_500
        val early = assertRenders("signin-logo-glow-${first}ms") { Page { SignInLogo(96.dp, pose = { SignInLogo.pose(first) }) } }
        val late = assertRenders("signin-logo-glow-${second}ms") { Page { SignInLogo(96.dp, pose = { SignInLogo.pose(second) }) } }
        val bare = assertRenders("signin-logo-glow-off") {
            Page { SignInLogo(96.dp, pose = { SignInLogo.pose(first).copy(glow = 0f) }) }
        }
        val still = assertRenders("signin-logo-still") { Page { SignInLogo(96.dp, pose = { SignInLogo.REST }) } }
        for (index in early.indices) {
            val name = early[index].file.name
            val before = ring(early[index])
            val after = ring(late[index])
            for (shot in listOf(early[index], late[index])) {
                val colours = ring(shot)
                assertTrue(
                    "${shot.file.name}: colour on every side of the square (chroma ${colours.map(::chroma)})",
                    colours.all { chroma(it) >= 24 },
                )
                assertTrue(
                    "${shot.file.name}: three or more hues round the square (${colours.map(::hue)})",
                    hues(colours).size >= 3,
                )
            }
            assertTrue(
                "$name: 1.5 s later the colours have moved on (above the square: ${hue(before[0])}° then ${hue(after[0])}°)",
                apart(hue(before[0]), hue(after[0])) >= 30f,
            )
            assertTrue(
                "$name: the glow is behind the square and never over it",
                inside(early[index], 72) == inside(bare[index], 72),
            )

            // Without motion (the pose at rest) there is no glow: nothing but the page around the square.
            val rest = still[index]
            val page = rest.pixel(rest.width - 1, rest.height - 1)
            val around = (0 until 432).sumOf { y ->
                (0 until 432).count { x -> (x !in 72 until 360 || y !in 72 until 360) && rest.pixel(x, y) != page }
            }
            assertEquals("${rest.file.name}: no glow around the square", 0, around)
            assertTrue("${rest.file.name}: the glow's place is the page", ring(rest).all { it == (page or (0xFF shl 24)) })
            val lit = (0 until 432).sumOf { y ->
                (0 until 432).count { x ->
                    (x !in 72 until 360 || y !in 72 until 360) && early[index].pixel(x, y) != early[index].pixel(1178, 0)
                }
            }
            assertTrue("$name: the glow is there, around the square ($lit px)", lit > 20_000)
        }
    }

    @Test
    fun theStepsAreUnseenUntilTheirTurnThenStay() {
        val before = assertRenders("signin-guide-before") {
            Page { SignInGuide(reveal = { SignInGuide.reveal(it, SignInGuide.START_MS) }) }
        }
        val after = assertRenders("signin-guide-after") {
            Page { SignInGuide(reveal = { SignInGuide.reveal(it, SignInGuide.END_MS) }) }
        }
        val still = assertRenders("signin-guide-still") { Page { SignInGuide(reveal = { SignInGuide.reveal(it, null) }) } }
        for (index in before.indices) {
            val blank = before[index]
            assertTrue("${blank.file.name}: nothing but the page", blank.argb.all { it == blank.pixel(0, 0) })
            assertTrue("${after[index].file.name}: three green numbers", after[index].argb.count(::green) > 300)
            assertTrue(
                "${still[index].file.name}: without motion the steps are as after the intro",
                still[index].argb.contentEquals(after[index].argb),
            )
        }
    }

    @Test
    fun theCursorFollowsTheTypedLettersAndIsGoneWithoutMotion() {
        val typing = TypedTagline.START_MS + 12 * TypedTagline.TYPE_MS
        val typed = assertRenders("signin-tagline-typing") { Page { TypedTagline(taglines(), introMs = { typing }) } }
        val still = assertRenders("signin-tagline-still") { Page { TypedTagline(taglines(), introMs = null) } }
        for (index in typed.indices) {
            assertTrue("${typed[index].file.name}: a green cursor", typed[index].argb.count(::green) > 50)
            assertEquals("${still[index].file.name}: no cursor", 0, still[index].argb.count(::green))
            val letters = { shot: Snapshot -> shot.argb.count { it != shot.pixel(0, 0) } }
            assertTrue(
                "${typed[index].file.name}: part of the line, where the still one has it whole",
                letters(typed[index]) < letters(still[index]),
            )
        }
    }

    /** For the eye: the chevrons' slide and overshoot, the underscore, the glow at its lowest and highest, the typed line. */
    @Test
    fun theIntroFrameByFrame() {
        assertRenders("signin-intro-frames") {
            Column(
                Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(28.dp),
            ) {
                for (moments in listOf(listOf(0L, 120L, 260L, 451L), listOf(650L, 775L, 900L, 1_500L))) {
                    Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                        for (ms in moments) SignInLogo(64.dp, pose = { SignInLogo.pose(ms) })
                    }
                }
                Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(48.dp)) {
                    for (ms in listOf(1_100L, 2_900L, 4_900L)) SignInLogo(72.dp, pose = { SignInLogo.pose(ms) })
                }
                val lines = taglines()
                for (ms in listOf(700L, 1_100L, 2_000L, 2_700L, 4_250L)) TypedTagline(lines, introMs = { ms })
                SignInGuide(reveal = { SignInGuide.reveal(it, 820L) })
            }
        }
    }

    /** The last two are 1.5 s apart: the glow near its strongest, then a quarter turn on and near its faintest. */
    @Test
    fun theScreenWhileTheIntroPlays() {
        for (ms in listOf(300L, 800L, 3_000L, 4_500L)) {
            assertRenders("signin-intro-${ms}ms") {
                SignInContent(
                    expired = false, error = null, busy = false, continueWithGoogle = {}, startDemo = {},
                    introMs = { ms },
                )
            }
        }
    }
}
