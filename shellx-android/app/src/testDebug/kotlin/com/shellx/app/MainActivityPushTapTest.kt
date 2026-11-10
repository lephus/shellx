package com.shellx.app

import android.content.Intent
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.platform.PushNotifier
import com.shellx.app.testing.SignedInShellXApplication
import com.shellx.app.ui.pending.PendingFixtures
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The activity's window over a signed-in account of fakes. */
@RunWith(AndroidJUnit4::class)
@Config(application = SignedInShellXApplication::class, qualifiers = "w400dp-h1600dp")
class MainActivityPushTapTest {
    @get:Rule val rule = createEmptyComposeRule()

    private val app: SignedInShellXApplication = ApplicationProvider.getApplicationContext()

    /** A real-time wait that runs the main looper meanwhile. */
    private fun waitUntil(condition: () -> Boolean) {
        rule.waitUntil(10_000) {
            rule.waitForIdle()
            condition()
        }
    }

    /**
     * Review C item 2 (and I-1 end to end): MainActivity hands ShellXApp the real platform, so a tap that started the
     * app reaches the signed-in screens and opens Needs you once the home is in place. Without the platform the
     * wrapper is left out and nothing takes the tap.
     */
    @Test
    fun aTapThatStartsTheAppOpensNeedsYou() {
        app.mac.addPending(PendingFixtures.permission(workspaceId = "ws-1", workspaceTitle = "shellx-ios"))
        val tap = Intent(app, MainActivity::class.java).setAction(PushNotifier.ACTION_OPEN_PENDING)

        ActivityScenario.launch<MainActivity>(tap).use {
            waitUntil { app.composition.value != null }
            val composition = app.composition.value!!
            // Robolectric may not feed ProcessLifecycleOwner's ON_START: start the account as the app's first start does.
            if (!composition.lifecycle.isStarted) rule.runOnUiThread { composition.lifecycle.onStart() }

            val title = app.getString(R.string.pending_list_title)
            waitUntil { rule.onAllNodesWithText(title).fetchSemanticsNodes().isNotEmpty() }
            assertFalse("the signed-in screens took the tap", app.platform.pushTaps.hasTap.value)
        }
    }
}
