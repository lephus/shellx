package com.shellx.app.ui.pending

import android.content.Context
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.testing.VoiceRig
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.voice.LocalVoice
import com.shellx.core.pending.DecisionCenter
import com.shellx.core.pending.DecisionFailure
import com.shellx.core.pending.DecisionStatus
import com.shellx.core.voice.VoiceInputModel
import com.shellx.link.core.ExitPlanMode
import com.shellx.link.core.LinkDecision
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The plan sheet over a plan that offers `manual`, `auto_accept`, `ultraplan` and `deny`. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h1200dp")
class PlanReviewSheetTest {
    @get:Rule val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val sent = mutableListOf<LinkDecision>()
    private val item = PendingFixtures.mac(PendingFixtures.plan())

    private fun show(revising: Boolean = false, feedback: String = "", rig: VoiceRig? = null, voice: VoiceInputModel? = null) =
        compose.setContent {
            ShellXTheme {
                CompositionLocalProvider(LocalVoice provides rig?.env) {
                    PlanReviewSheet(item, PendingSheetState(), send = { sent += it }, close = {}, revising = revising, feedback = feedback, voice = voice)
                }
            }
        }

    private fun until(condition: () -> Boolean) = compose.waitUntil(10_000) {
        compose.waitForIdle()
        condition()
    }

    @Test
    fun approveSendsManual() {
        show()
        compose.onNodeWithTag("pending.approve").performClick()
        assertEquals(listOf(LinkDecision.ExitPlan(ExitPlanMode.MANUAL, null)), sent)
    }

    @Test
    fun otherModesSitInTheMenu() {
        show()
        compose.onNodeWithTag("pending.otherModes").performClick()
        compose.onNodeWithText(context.getString(R.string.pending_plan_auto_accept)).performClick()
        assertEquals(listOf(LinkDecision.ExitPlan(ExitPlanMode.AUTO_ACCEPT, null)), sent)
    }

    @Test
    fun reviseNeedsFeedbackWithinTheLimit() {
        show()
        compose.onNodeWithTag("pending.revise").performClick()
        compose.onNodeWithTag("pending.sendFeedback").assertIsNotEnabled()
        compose.onNodeWithTag("pending.feedback").performTextInput("Tách bước 2 ra.")
        compose.onNodeWithTag("pending.sendFeedback").assertIsEnabled().performClick()
        assertEquals(listOf(LinkDecision.ExitPlan(ExitPlanMode.DENY, "Tách bước 2 ra.")), sent)
        compose.onNodeWithTag("pending.feedback").performTextReplacement("x".repeat(4_097))
        compose.onNodeWithTag("pending.sendFeedback").assertIsNotEnabled()
        compose.onNodeWithText(context.getString(R.string.pending_too_long, 4_097, 4_096)).assertExists()
    }

    /** RF 3: the feedback being typed survives a recreated screen. */
    @Test
    fun feedbackSurvivesRecreation() {
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            ShellXTheme { PlanReviewSheet(item, PendingSheetState(), send = { sent += it }, close = {}) }
        }
        compose.onNodeWithTag("pending.revise").performClick()
        compose.onNodeWithTag("pending.feedback").performTextInput("Giữ route v1")
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("pending.feedback").assertTextEquals("Giữ route v1")
        compose.onNodeWithTag("pending.sendFeedback").assertExists()
    }

    @Test
    fun dictationAddsToTheFeedback() {
        val rig = VoiceRig.make()
        val model = rig.model(DecisionCenter.MAX_FEEDBACK_BYTES)
        show(revising = true, feedback = "Giữ route v1", rig = rig, voice = model)
        compose.onNodeWithTag("voice.mic").performTouchInput { down(center) }
        until { rig.engine.starts.size == 1 }
        rig.engine.say("đừng xoá")
        until { model.phase == VoiceInputModel.Phase.Listening("đừng xoá") }
        compose.onNodeWithTag("voice.mic").performTouchInput { up() }
        until { model.phase == VoiceInputModel.Phase.Idle }
        compose.onNodeWithTag("pending.feedback").assertTextEquals("Giữ route v1 đừng xoá")
        assertTrue(sent.isEmpty())
    }

    @Test
    fun rejectSendsDeny() {
        show()
        compose.onNodeWithTag("pending.reject").performClick()
        assertEquals(listOf(LinkDecision.ExitPlan(ExitPlanMode.DENY, null)), sent)
    }

    /** "Try again" resends what was sent from here, also once the screen was rebuilt in between. */
    @Test
    fun tryAgainResendsTheLastDecisionAfterRecreation() {
        var state by mutableStateOf(PendingSheetState())
        val restoration = StateRestorationTester(compose)
        restoration.setContent { ShellXTheme { PlanReviewSheet(item, state, send = { sent += it }, close = {}) } }
        compose.onNodeWithTag("pending.revise").performClick()
        compose.onNodeWithTag("pending.feedback").performTextInput("Tách bước 2 ra.")
        compose.onNodeWithTag("pending.sendFeedback").performClick()
        state = PendingSheetState(status = DecisionStatus.Failed(DecisionFailure.NO_ANSWER))
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("pending.retry").performClick()
        val feedback = LinkDecision.ExitPlan(ExitPlanMode.DENY, "Tách bước 2 ra.")
        assertEquals(listOf(feedback, feedback), sent)
    }

    /** A huge paste is too long to send; only its first 64 KB go into the saved screen state. */
    @Test
    fun aHugeFeedbackIsSavedCut() {
        val restoration = StateRestorationTester(compose)
        restoration.setContent { ShellXTheme { PlanReviewSheet(item, PendingSheetState(), send = { sent += it }, close = {}, revising = true) } }
        compose.onNodeWithTag("pending.feedback").performTextReplacement("x".repeat(70_000))
        restoration.emulateSavedInstanceStateRestore()
        val kept = compose.onNodeWithTag("pending.feedback").fetchSemanticsNode().config[SemanticsProperties.EditableText].text
        assertEquals(65_536, kept.length)
    }
}
