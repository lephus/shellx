package com.shellx.app.ui.pending

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.performFirstLinkClick
import androidx.compose.ui.text.LinkAnnotation
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.ui.theme.ShellXTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Review A I-2: a plan comes from an agent, so a tap opens only a web link, and a phone that cannot open it never
 *  crashes the app. */
@RunWith(AndroidJUnit4::class)
class PlanMarkdownLinkTest {
    @get:Rule val compose = createComposeRule()

    private val opened = mutableListOf<String>()

    private fun show(markdown: String, fails: Boolean = false) = compose.setContent {
        val handler = object : UriHandler {
            override fun openUri(uri: String) {
                opened += uri
                // What AndroidUriHandler lets through: a file: URI throws FileUriExposedException, a provider can refuse.
                if (fails) throw SecurityException("refused")
            }
        }
        ShellXTheme {
            CompositionLocalProvider(LocalUriHandler provides handler) { PlanMarkdownText(markdown) }
        }
    }

    private fun tap(url: String) {
        compose.onNode(hasText("open", substring = true)).performFirstLinkClick { (it.item as LinkAnnotation.Url).url == url }
        compose.waitForIdle()
    }

    @Test
    fun onlyWebLinksOpen() {
        val others = listOf("file:///Users/me/app.log", "intent://scan#Intent;scheme=zxing;end", "javascript:void0", "tel:+84900000000", "content://x/y")
        val web = listOf("https://shellx.pro/docs", "HTTP://example.com/a")
        show("open " + (others + web).mapIndexed { i, url -> "[link$i]($url)" }.joinToString(" "))
        for (url in others + web) tap(url)
        assertEquals(web, opened)
    }

    @Test
    fun aWebLinkThePhoneCannotOpenDoesNothing() {
        show("open [the docs](https://shellx.pro/docs)", fails = true)
        tap("https://shellx.pro/docs")
        assertEquals(listOf("https://shellx.pro/docs"), opened)
    }
}
