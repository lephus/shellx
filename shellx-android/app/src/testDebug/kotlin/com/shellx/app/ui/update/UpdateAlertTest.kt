package com.shellx.app.ui.update

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.material3.Text
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.platform.PlayUpdateChecker
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.update.AvailableUpdate
import com.shellx.core.update.UpdateChecker
import com.shellx.core.update.UpdatePrompt
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The update prompt (`UpdateAlert.swift`): Play's own flexible-update dialog once per offer, then Restart. */
@RunWith(AndroidJUnit4::class)
class UpdateAlertTest {
    @get:Rule
    val rule = createComposeRule()

    private val res = ApplicationProvider.getApplicationContext<Context>().resources

    /** Answers [answer] and records each start. */
    private class TestChecker(var answer: AvailableUpdate?) : UpdateChecker {
        val started = mutableListOf<AvailableUpdate>()

        override suspend fun check(): AvailableUpdate? = answer

        override suspend fun startUpdate(update: AvailableUpdate) {
            started += update
        }
    }

    @Test
    fun anOfferStartsPlaysFlowOnce() {
        val checker = TestChecker(AvailableUpdate(101))
        val prompt = UpdatePrompt(100, checker)
        runBlocking { prompt.check() }
        var tick by mutableIntStateOf(0)
        rule.setContent {
            ShellXTheme {
                Text("tick $tick")
                UpdateAlert(prompt, null, restart = {})
            }
        }
        rule.waitForIdle()
        assertEquals(listOf(AvailableUpdate(101)), checker.started)
        assertNull(prompt.offered.value)

        tick++
        rule.waitForIdle()
        rule.onNodeWithText("tick 1").assertIsDisplayed()
        assertEquals("another recomposition starts nothing more", 1, checker.started.size)
    }

    @Test
    fun aDownloadedUpdateAsksToRestart() {
        val installs = MutableStateFlow(PlayUpdateChecker.InstallPhase.DOWNLOADED)
        var restarts = 0
        rule.setContent { ShellXTheme { UpdateAlert(null, installs, restart = { restarts++ }) } }
        rule.onNodeWithText(res.getString(R.string.update_downloaded)).assertIsDisplayed()
        rule.onNodeWithText(res.getString(R.string.update_restart)).performClick()
        rule.waitForIdle()
        assertEquals(1, restarts)
    }

    @Test
    fun nothingShowsWithoutAPrompt() {
        var restarts = 0
        rule.setContent { ShellXTheme { UpdateAlert(null, null) { restarts++ } } }
        rule.waitForIdle()
        rule.onAllNodesWithText(res.getString(R.string.update_downloaded)).assertCountEquals(0)
        rule.onAllNodesWithText(res.getString(R.string.update_restart)).assertCountEquals(0)
        assertTrue(restarts == 0)
    }
}
