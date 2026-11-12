package com.shellx.app.ui.settings

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme
import java.io.FileNotFoundException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The Licenses screen shows the generated notices from the real asset, lazily, and survives a missing asset. */
@RunWith(AndroidJUnit4::class)
class LicencesScreenTest {
    @get:Rule val compose = createAndroidComposeRule<LicencesActivity>()

    @Test
    fun theScreenShowsTheFirstLibraryOfTheBundledNotices() {
        val asset = compose.activity.assets.open(LICENCES_ASSET).bufferedReader().use { it.readText() }
        val first = Regex("""^(.+) \([^()\s]+:[^()\s]+:[^()\s]+\)$""", RegexOption.MULTILINE).find(asset)!!.groupValues[1]
        compose.onNodeWithText(first, substring = true).assertExists()
    }

    @Test
    fun aMissingAssetShowsOneLineInsteadOfCrashing() {
        assertNull(readLicenceNotices { throw FileNotFoundException("licenses/third_party_licenses.txt") })
        val message = compose.activity.getString(R.string.licences_unavailable)
        compose.activity.setContent { ShellXTheme { LicencesScreen(null) } }
        compose.onNodeWithText(message).assertExists()
    }

    @Test
    fun longTextsAreCutIntoBlocksSoTheListStaysLazy() {
        val licence = (1..100).joinToString("\n") { "line $it" }
        val blocks = licenceBlocks("Name (a:b:1)\nLicense: MIT\n\n$licence\n\n\nlast")
        assertEquals("Name (a:b:1)\nLicense: MIT", blocks.first())
        assertEquals("last", blocks.last())
        assertTrue(blocks.all { it.lines().size <= MAX_BLOCK_LINES })
        assertEquals(licence, blocks.drop(1).dropLast(1).joinToString("\n"))
    }
}
