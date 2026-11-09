package com.shellx.app.ui.components

import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.ui.theme.AppAppearance
import com.shellx.app.ui.theme.ShellXAppTheme
import com.shellx.app.ui.theme.ShellXColors
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.platform.Clock
import kotlin.time.TestTimeSource
import kotlin.time.TimeSource
import kotlinx.coroutines.flow.MutableSharedFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The row, dialog, ticker and theme helpers every screen shares. */
@RunWith(AndroidJUnit4::class)
class ComponentsTest {
    @get:Rule val rule = createComposeRule()

    private class Counter(val label: String) {
        var count = 0
        fun action(destructive: Boolean = true) = RowAction(label, Icons.Filled.Close, destructive) { count++ }
    }

    private fun row(swipe: RowAction?, menu: List<RowAction>, enabled: Boolean = true, onClick: (() -> Unit)? = null) {
        rule.setContent {
            ShellXTheme {
                ActionRow(
                    swipe = swipe,
                    menu = menu,
                    onClick = onClick,
                    onClickLabel = null,
                    modifier = Modifier.fillMaxWidth().height(64.dp).testTag("row"),
                    enabled = enabled,
                ) { Text("row") }
            }
        }
    }

    @Test
    fun aSwipeRunsTheSwipeActionOnceAndTheRowStays() {
        val close = Counter("Close")
        row(swipe = close.action(), menu = listOf(close.action()))

        rule.onNodeWithTag("row").performTouchInput { swipeLeft() }
        rule.waitForIdle()
        assertEquals(1, close.count)
        rule.onNodeWithTag("row").assertIsDisplayed()
        rule.onNodeWithText("row").assertIsDisplayed()

        rule.onNodeWithTag("row").performTouchInput { swipeLeft() }
        rule.waitForIdle()
        assertEquals(2, close.count)
    }

    @Test
    fun aLongPressOpensTheMenuAndRunsTheChosenAction() {
        val rename = Counter("Rename")
        val close = Counter("Close")
        row(swipe = close.action(), menu = listOf(RowAction("Rename", Icons.Outlined.Edit, false) { rename.count++ }, close.action()))

        rule.onNodeWithTag("row").performTouchInput { longClick() }
        rule.onNodeWithText("Rename").assertIsDisplayed()
        rule.onNodeWithText("Close").assertIsDisplayed()
        val renameTop = rule.onNodeWithText("Rename").fetchSemanticsNode().boundsInRoot.top
        val closeTop = rule.onNodeWithText("Close").fetchSemanticsNode().boundsInRoot.top
        assert(renameTop < closeTop) { "the menu keeps its order" }

        rule.onNodeWithText("Close").performClick()
        rule.waitForIdle()
        assertEquals(1, close.count)
        assertEquals(0, rename.count)
        rule.onNodeWithText("Rename").assertDoesNotExist()
    }

    /**
     * A screen recomposes during a press (a hub update, the 30 s tick) and hands the row a fresh menu list; the press
     * still opens the menu (review B I-1: Your Macs rows have no click, and the menu is their only touch route).
     */
    private fun holdWhileTheScreenRecomposes(withClick: Boolean) {
        var tick by mutableIntStateOf(0)
        var clicks = 0
        var unpaired = -1
        rule.setContent {
            ShellXTheme {
                val t = tick
                ActionRow(
                    swipe = null,
                    // The action reads what the screen read, as RowActionKind.menuAction { … } does: a new lambda.
                    menu = listOf(RowAction("Unpair", Icons.Filled.Close, true) { unpaired = t }),
                    onClick = if (withClick) ({ clicks++ }) else null,
                    onClickLabel = null,
                    modifier = Modifier.fillMaxWidth().height(64.dp).testTag("row"),
                ) { Text("row $t") }
            }
        }
        rule.mainClock.autoAdvance = false
        rule.onNodeWithTag("row").performTouchInput { down(center) }
        rule.mainClock.advanceTimeBy(200)
        rule.runOnUiThread {
            tick++
            Snapshot.sendApplyNotifications()
        }
        rule.mainClock.advanceTimeBy(100)
        rule.onNodeWithText("row 1", useUnmergedTree = true).assertExists()
        rule.onNodeWithText("Unpair").assertDoesNotExist()

        rule.mainClock.advanceTimeBy(600)
        rule.onNodeWithTag("row").performTouchInput { up() }
        rule.mainClock.autoAdvance = true
        rule.waitForIdle()
        rule.onNodeWithText("Unpair").assertIsDisplayed()
        assertEquals("a long press is not a click", 0, clicks)
        rule.onNodeWithText("Unpair").performClick()
        rule.waitForIdle()
        assertEquals("the menu runs the latest action", 1, unpaired)
    }

    @Test
    fun aLongPressHeldWhileTheScreenRecomposesOpensTheMenuOfARowWithoutAClick() =
        holdWhileTheScreenRecomposes(withClick = false)

    @Test
    fun aLongPressHeldWhileTheScreenRecomposesOpensTheMenuOfARowWithAClick() =
        holdWhileTheScreenRecomposes(withClick = true)

    @Test
    fun talkBackListsTheMenuAsCustomActions() {
        val close = Counter("Close")
        row(swipe = close.action(), menu = listOf(RowAction("Rename", Icons.Outlined.Edit, false) {}, close.action()))

        val actions = rule.onNodeWithTag("row").fetchSemanticsNode().config[SemanticsActions.CustomActions]
        assertEquals(listOf("Rename", "Close"), actions.map { it.label })
        actions[1].action()
        assertEquals(1, close.count)
    }

    @Test
    fun aRowWithoutActionsNeitherSwipesNorHasAMenu() {
        row(swipe = null, menu = emptyList())

        rule.onNodeWithTag("row").performTouchInput { swipeLeft() }
        rule.onNodeWithTag("row").performTouchInput { longClick() }
        rule.waitForIdle()
        rule.onNodeWithText("row").assertIsDisplayed()
        assertFalse(SemanticsActions.CustomActions in rule.onNodeWithTag("row").fetchSemanticsNode().config)
        assertFalse(SemanticsActions.OnLongClick in rule.onNodeWithTag("row").fetchSemanticsNode().config)
    }

    @Test
    fun aDisabledRowIgnoresItsActions() {
        val close = Counter("Close")
        var clicks = 0
        row(swipe = close.action(), menu = listOf(close.action()), enabled = false, onClick = { clicks++ })

        rule.onNodeWithTag("row").performTouchInput { swipeLeft() }
        rule.onNodeWithTag("row").performClick()
        rule.onNodeWithTag("row").performTouchInput { longClick() }
        rule.waitForIdle()
        assertEquals(0, close.count)
        assertEquals(0, clicks)
        rule.onNodeWithText("Close").assertDoesNotExist()
        assertFalse(SemanticsActions.CustomActions in rule.onNodeWithTag("row").fetchSemanticsNode().config)
    }

    @Test
    fun confirmRunsOnceAndCloses() {
        var confirmed = 0
        rule.setContent {
            ShellXTheme {
                var shown by remember { mutableStateOf(true) }
                if (shown) {
                    ConfirmDialog(
                        title = "Close shellx-ios?",
                        text = "Its terminals close on the Mac.",
                        confirmLabel = "Close Workspace",
                        onConfirm = { confirmed++ },
                        onDismiss = { shown = false },
                    )
                }
            }
        }

        rule.onNodeWithText("Its terminals close on the Mac.").assertIsDisplayed()
        rule.onNodeWithText("Cancel").assertIsDisplayed()
        rule.onNodeWithText("Close Workspace").performClick()
        rule.waitForIdle()
        assertEquals(1, confirmed)
        rule.onNodeWithText("Its terminals close on the Mac.").assertDoesNotExist()
    }

    @Test
    fun nowFollowsTheTicks() {
        val clock = object : Clock {
            var wallMs = 1_700_000_000_000
            override fun nowMs(): Long = wallMs
            override val monotonic: TimeSource.WithComparableMarks = TestTimeSource()
        }
        val ticks = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
        rule.setContent { Text("now:${rememberNowMs(clock, ticks)}") }

        rule.onNodeWithText("now:1700000000000").assertIsDisplayed()
        clock.wallMs += 31_000
        rule.waitForIdle()
        rule.onNodeWithText("now:1700000000000").assertIsDisplayed()
        ticks.tryEmit(Unit)
        rule.waitForIdle()
        rule.onNodeWithText("now:1700000031000").assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "tr")
    fun aSectionTitleUpperCasesInTheAppsLanguage() {
        // A Turkish phone gets the English strings (there is no values-tr), so the title is English upper case, with
        // no dotted capital İ (review B m-2).
        val context = ApplicationProvider.getApplicationContext<Context>()
        assertEquals("tr", context.resources.configuration.locales[0].language)
        rule.setContent { ShellXTheme { SectionTitle("Notifications") } }

        rule.onNodeWithText("NOTIFICATIONS").assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "night")
    fun appearanceOverridesTheSystem() {
        var light = Color.Unspecified
        var dark = Color.Unspecified
        var system = Color.Unspecified
        rule.setContent {
            Column {
                ShellXAppTheme(AppAppearance.LIGHT) { light = MaterialTheme.colorScheme.background }
                ShellXAppTheme(AppAppearance.DARK) { dark = MaterialTheme.colorScheme.background }
                ShellXAppTheme(AppAppearance.SYSTEM) { system = MaterialTheme.colorScheme.background }
            }
        }
        rule.waitForIdle()
        assertEquals("Light wins over a dark phone", ShellXColors.Light.background, light)
        assertEquals(ShellXColors.Dark.background, dark)
        assertEquals("Match phone follows the phone", ShellXColors.Dark.background, system)
    }
}
