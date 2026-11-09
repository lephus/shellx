package com.shellx.app.ui.signin

import android.content.Context
import android.graphics.BitmapFactory
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.screenshots.chroma
import com.shellx.app.ui.theme.ShellXTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Google's G and Google Sans on Continue with Google (contracts §11): official files only, the font with its OFL. */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "xxhdpi")
class GoogleBrandingTest {
    @get:Rule val rule = createComposeRule()
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun theGoogleMarkIsTheOfficialSizeOnceBundled() {
        val mark = GoogleBranding.mark(context)
        assumeTrue("Task 9 Step 8 adds the mark", mark != null)
        val bitmap = BitmapFactory.decodeResource(context.resources, mark!!)
        assertEquals("20 dp at xxhdpi", 60, bitmap.width)
        assertEquals(60, bitmap.height)
        for ((x, y) in listOf(0 to 0, 59 to 0, 0 to 59, 59 to 59)) {
            val pixel = bitmap.getPixel(x, y)
            val channels = listOf((pixel shr 16) and 0xFF, (pixel shr 8) and 0xFF, pixel and 0xFF)
            assertTrue("corner ($x, $y) is white", channels.all { it >= 0xF5 })
        }
        val pixels = IntArray(60 * 60).also { bitmap.getPixels(it, 0, 60, 0, 0, 60, 60) }
        val coloured = pixels.filter { chroma(it) > 80 }
        assertTrue("at least 20 % of the G is coloured", coloured.size * 5 >= pixels.size)
        val largest = coloured.map { pixel ->
            val channels = listOf((pixel shr 16) and 0xFF, (pixel shr 8) and 0xFF, pixel and 0xFF)
            channels.indexOf(channels.max())
        }.toSet()
        assertEquals("red, green and blue each lead some pixel: Google's colours", setOf(0, 1, 2), largest)
    }

    @Test
    fun googleSansIsUsedOnceBundled() {
        assumeTrue("Task 9 Step 8 bundles Google Sans", "GoogleSans.ttf" in context.assets.list("fonts").orEmpty())
        assertNotNull(GoogleBranding.font(context))
    }

    @Test
    fun aBundledFontCarriesItsOflLicence() {
        val files = context.assets.list("fonts").orEmpty().toSet()
        for (font in files.filter { it.endsWith(".ttf") || it.endsWith(".otf") }) {
            val licence = "${font.substringBeforeLast('.')}-OFL.txt"
            assertTrue("$font ships with $licence", licence in files)
            val text = context.assets.open("fonts/$licence").bufferedReader().use { it.readText() }
            assertTrue("$licence is the SIL OFL 1.1", text.contains("SIL OPEN FONT LICENSE Version 1.1"))
        }
    }

    @Test
    fun theMarkShowsOnlyWhenBundledAndTheNameStaysWhileBusy() {
        var mark by mutableStateOf<Int?>(R.drawable.shellx_logo)
        var busy by mutableStateOf(false)
        rule.setContent {
            ShellXTheme { GoogleSignInButton(onClick = {}, busy = busy, enabled = !busy, mark = mark, font = null) }
        }

        rule.onNodeWithTag("signin.google.mark", useUnmergedTree = true).assertExists()

        mark = null
        rule.waitForIdle()
        rule.onNodeWithTag("signin.google.mark", useUnmergedTree = true).assertDoesNotExist()
        rule.onNodeWithText("Continue with Google").assertIsDisplayed()

        busy = true
        rule.waitForIdle()
        rule.onNodeWithText("Continue with Google").assertDoesNotExist()
        rule.onNodeWithTag("signin.google").assertContentDescriptionEquals("Continue with Google")
    }
}
