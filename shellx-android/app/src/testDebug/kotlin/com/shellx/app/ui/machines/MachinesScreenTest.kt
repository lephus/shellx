package com.shellx.app.ui.machines

import android.content.Context
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.link.MachineLinkState
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Your Macs: unpair asks first and goes out once, a Mac that removed this phone goes without a question, a failure
 *  says so, the menu offers what each Mac allows. */
@RunWith(AndroidJUnit4::class)
class MachinesScreenTest {
    @get:Rule val rule = createComposeRule()
    private val context: Context = ApplicationProvider.getApplicationContext()

    private val items = listOf(
        MachineListItem("m1", "MacBook Pro", MachineLinkState.Online),
        MachineListItem("m3", "iMac", MachineLinkState.Online),
        MachineListItem("m5", "Mac của Lan", MachineLinkState.Revoked),
        MachineListItem("m6", "Mac Pro", MachineLinkState.HostKeyChanged),
    )

    private val unpaired = mutableListOf<String>()
    private val madeDefault = mutableListOf<String>()
    private var pairs = 0

    private fun show(unpair: suspend (String) -> Unit = { unpaired += it }) {
        rule.setContent {
            ShellXTheme {
                MachineList(
                    items = items,
                    defaultId = "m1",
                    makeDefault = { madeDefault += it },
                    unpair = unpair,
                    pair = { pairs++ },
                    back = {},
                )
            }
        }
    }

    private fun row(id: String): SemanticsNodeInteraction = rule.onNodeWithTag("machines.row.$id")

    private fun dialogButton(label: String) = rule.onNode(hasText(label) and hasClickAction())

    private fun menuLabels(id: String): List<String> =
        row(id).fetchSemanticsNode().config.getOrElse(SemanticsActions.CustomActions) { emptyList() }.map { it.label }

    @Test
    fun swipingAnOnlineMacAsksBeforeUnpairing() {
        show()

        row("m1").performTouchInput { swipeLeft() }
        rule.onNodeWithText("Unpair MacBook Pro?").assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.machines_unpair_message)).assertIsDisplayed()
        assertEquals(emptyList<String>(), unpaired)

        dialogButton("Unpair").performClick()
        rule.waitForIdle()
        assertEquals(listOf("m1"), unpaired)
        rule.onNodeWithText("Unpair MacBook Pro?").assertDoesNotExist()
    }

    @Test
    fun unpairTappedTwiceUnpairsOnce() {
        val gate = CompletableDeferred<Unit>()
        show(unpair = {
            unpaired += it
            gate.await()
        })

        row("m1").performTouchInput { swipeLeft() }
        dialogButton("Unpair").performClick()
        rule.waitForIdle()
        assertEquals(listOf("m1"), unpaired)

        row("m1").performTouchInput { swipeLeft() }
        rule.waitForIdle()
        rule.onNodeWithText("Unpair MacBook Pro?").assertDoesNotExist()
        row("m1").performTouchInput { longClick() }
        rule.waitForIdle()
        rule.onNodeWithText("Make Default").assertDoesNotExist()
        dialogButton("Unpair").assertDoesNotExist()

        gate.complete(Unit)
        rule.waitForIdle()
        assertEquals(listOf("m1"), unpaired)
    }

    @Test
    fun aMacThatRemovedThisPhoneIsRemovedWithoutAQuestion() {
        show()

        rule.onNodeWithTag("machine.remove").performClick()
        rule.waitForIdle()
        assertEquals(listOf("m5"), unpaired)
        rule.onNodeWithText("Unpair Mac của Lan?").assertDoesNotExist()

        row("m5").performTouchInput { swipeLeft() }
        rule.waitForIdle()
        assertEquals(listOf("m5", "m5"), unpaired)
        rule.onNodeWithText("Unpair Mac của Lan?").assertDoesNotExist()
    }

    @Test
    fun aFailedUnpairSaysSo() {
        show(unpair = { throw IOException("offline") })

        row("m1").performTouchInput { swipeLeft() }
        dialogButton("Unpair").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Couldn't Unpair").assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.machines_unpair_failed_message, "MacBook Pro")).assertIsDisplayed()

        dialogButton("OK").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Couldn't Unpair").assertDoesNotExist()
    }

    @Test
    fun theMenuOffersWhatTheMacAllows() {
        show()

        assertEquals(listOf("Make Default", "Unpair"), menuLabels("m3"))
        assertEquals(listOf("Unpair"), menuLabels("m1"))
        assertEquals(listOf("Pair Again", "Unpair"), menuLabels("m6"))
        assertEquals(listOf("Remove"), menuLabels("m5"))

        row("m3").performTouchInput { longClick() }
        rule.onNodeWithText("Make Default").assertIsDisplayed()
        dialogButton("Unpair").assertIsDisplayed()
        rule.onNodeWithText("Make Default").performClick()
        rule.waitForIdle()
        assertEquals(listOf("m3"), madeDefault)
    }

    @Test
    fun plusOpensPairing() {
        show()

        rule.onNodeWithTag("machines.pair").performClick()
        assertEquals(1, pairs)
    }
}
