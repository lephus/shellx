package com.shellx.app.ui.pending

import android.content.Context
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isSelected
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.testing.VoiceRig
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.voice.LocalVoice
import com.shellx.core.pending.QuestionDraft
import com.shellx.core.voice.VoiceInputModel
import com.shellx.link.core.LinkDecision
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The question sheet over `PendingCardRenderTests.swift`'s two questions: `db` (Postgres / SQLite, one) and `checks`
 *  (Lint / Unit tests / UI tests, many). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h1200dp")
class QuestionAnswerSheetTest {
    @get:Rule val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val sent = mutableListOf<LinkDecision>()
    private val item = PendingFixtures.mac(PendingFixtures.question())

    private fun show(state: PendingSheetState = PendingSheetState(), rig: VoiceRig? = null, voice: VoiceInputModel? = null) =
        compose.setContent {
            ShellXTheme {
                CompositionLocalProvider(LocalVoice provides rig?.env) {
                    QuestionAnswerSheet(item, state, send = { sent += it }, close = {}, voice = voice)
                }
            }
        }

    private fun until(condition: () -> Boolean) = compose.waitUntil(10_000) {
        compose.waitForIdle()
        condition()
    }

    private fun tap(text: String) = compose.onNodeWithText(text).performClick()

    private fun selected(label: String): Boolean =
        compose.onAllNodes(hasText(label) and isSelected()).fetchSemanticsNodes().isNotEmpty()

    @Test
    fun picksGoOutAsTheirLabels() {
        show()
        tap("Postgres")
        compose.onNodeWithTag("pending.next").performClick()
        tap("Lint")
        tap("Unit tests")
        compose.onNodeWithTag("pending.send").performClick()
        assertEquals(listOf(LinkDecision.Question(listOf("Postgres", "Lint, Unit tests"))), sent)
    }

    @Test
    fun nextNeedsAnAnswer() {
        show()
        compose.onNodeWithTag("pending.next").assertIsNotEnabled()
        tap("Postgres")
        compose.onNodeWithTag("pending.next").assertIsEnabled()
    }

    @Test
    fun anOtherAnswerIsSentAsTyped() {
        show()
        tap("Postgres")
        compose.onNodeWithTag("pending.next").performClick()
        compose.onNodeWithTag("pending.other").performClick()
        compose.onNodeWithTag("pending.otherField").performTextInput("Chỉ chạy lint")
        compose.onNodeWithTag("pending.send").performClick()
        assertEquals(listOf(LinkDecision.Question(listOf("Postgres", "Chỉ chạy lint"))), sent)
    }

    private fun speak(rig: VoiceRig, model: VoiceInputModel, words: String) {
        compose.onNodeWithTag("voice.mic").performTouchInput { down(center) }
        until { rig.engine.starts.size == 1 }
        rig.engine.say(words)
        until { model.phase == VoiceInputModel.Phase.Listening(words) }
        compose.onNodeWithTag("voice.mic").performTouchInput { up() }
        until { model.phase == VoiceInputModel.Phase.Idle }
    }

    @Test
    fun aSpokenAnswerPicksTheOptionItNames() {
        val rig = VoiceRig.make()
        val model = rig.model(QuestionDraft.MAX_ANSWER_BYTES)
        show(rig = rig, voice = model)
        speak(rig, model, "postgres")
        until { selected("Postgres") }
        compose.onNode(hasText("Postgres")).assertIsSelected()
        assertTrue(sent.isEmpty())
    }

    @Test
    fun aSpokenAnswerWithoutAMatchBecomesTheOtherAnswer() {
        val rig = VoiceRig.make()
        val model = rig.model(QuestionDraft.MAX_ANSWER_BYTES)
        show(rig = rig, voice = model)
        speak(rig, model, "Dùng MongoDB đi")
        until { compose.onAllNodesWithTag("pending.otherField").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("pending.otherField").assertTextEquals("Dùng MongoDB đi")
        compose.onNodeWithTag("pending.voice.noMatch").assertExists()
        assertTrue(sent.isEmpty())
    }

    /** RF 3: rotation, dark mode or font size recreate the screen while the user types. */
    @Test
    fun typedAnswersSurviveRecreation() {
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            ShellXTheme { QuestionAnswerSheet(item, PendingSheetState(), send = { sent += it }, close = {}) }
        }
        tap("Postgres")
        compose.onNodeWithTag("pending.next").performClick()
        compose.onNodeWithTag("pending.other").performClick()
        compose.onNodeWithTag("pending.otherField").performTextInput("Chỉ lint")
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithText(context.getString(R.string.pending_question_page, 2, 2)).assertExists()
        compose.onNodeWithTag("pending.otherField").assertTextEquals("Chỉ lint")
        tap(context.getString(R.string.pending_question_back))
        compose.onNode(hasText("Postgres")).assertIsSelected()
    }

    @Test
    fun handledElsewhereOffersOnlyClose() {
        show(PendingSheetState(handledElsewhere = true, canSend = false))
        // The top bar's Close and the bottom bar's.
        assertEquals(2, compose.onAllNodesWithText(context.getString(R.string.common_close)).fetchSemanticsNodes().size)
        assertTrue(compose.onAllNodesWithTag("pending.send").fetchSemanticsNodes().isEmpty())
        compose.onNodeWithText(context.getString(R.string.pending_status_handled_elsewhere)).assertExists()
    }
}
