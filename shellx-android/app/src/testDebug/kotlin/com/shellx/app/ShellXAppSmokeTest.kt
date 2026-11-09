package com.shellx.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.TestComposition
import com.shellx.app.testing.mainComposition
import com.shellx.app.ui.ShellXApp
import com.shellx.app.ui.theme.AppAppearance
import com.shellx.app.ui.theme.ShellXAppTheme
import com.shellx.core.demo.FakeMac
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The whole window over fakes on the main thread: sign in, pair the first Mac, see its workspaces; and the demo. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h1600dp")
class ShellXAppSmokeTest {
    @get:Rule val rule = createComposeRule()
    @get:Rule val folder = TemporaryFolder()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    @After
    fun tearDown() {
        appScope.cancel()
    }

    private fun shown(text: String): Boolean = rule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    /** A real-time wait that runs the main looper meanwhile (Robolectric: the account's work is posted to it). */
    private fun waitUntil(condition: () -> Boolean) {
        rule.waitUntil(10_000) {
            rule.waitForIdle()
            condition()
        }
    }

    private fun waitForText(text: String) = waitUntil { shown(text) }

    private fun tap(text: String) {
        waitUntil { rule.onAllNodes(hasText(text) and hasClickAction()).fetchSemanticsNodes().isNotEmpty() }
        rule.onNode(hasText(text) and hasClickAction()).performClick()
    }

    private fun start(mac: FakeMac): TestComposition {
        val t = mainComposition(folder.root, macs = emptyList(), appScope = appScope, signedIn = false, pairable = listOf(mac))
        rule.setContent { ShellXAppTheme(AppAppearance.SYSTEM) { ShellXApp(t.composition) } }
        rule.runOnUiThread { t.composition.lifecycle.onStart() }
        return t
    }

    private fun macWithAWorkspace(): FakeMac = FakeMac("MacBook Pro", appScope).apply {
        setWorkspaces(
            listOf(LinkWorkspace("ws-shellx-ios", "shellx-ios", 0, terminals = listOf(LinkTerminal("t1", "zsh", 0, selected = true)))),
        )
    }

    @Test
    fun signInPairAndSeeTheHome() {
        val mac = macWithAWorkspace()
        val t = start(mac)

        tap("Continue with Google")
        waitForText("Pair a Mac")
        rule.runOnUiThread {
            context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("ShellX", mac.pairingCode()))
        }
        tap("Scan QR Code")
        tap("Paste Pairing Code")
        waitForText("Pair with MacBook Pro?")
        tap("Pair")
        waitForText("Paired with MacBook Pro.")
        tap("Done")

        waitForText("shellx-ios")
        assertEquals(1, t.relay.calls.count { it == "pair" })
    }

    @Test
    fun theDemoShowsItsBannerAndExits() {
        start(macWithAWorkspace())

        tap("Try without an account")
        waitForText("Exit")
        assertTrue(shown("Demo"))
        waitUntil { rule.onAllNodesWithText("MAC GIẢ", substring = true).fetchSemanticsNodes().isNotEmpty() }

        tap("Exit")

        waitForText("Continue with Google")
        waitUntil { !shown("Exit") }
        rule.onNodeWithText("Exit").assertDoesNotExist()
    }
}
