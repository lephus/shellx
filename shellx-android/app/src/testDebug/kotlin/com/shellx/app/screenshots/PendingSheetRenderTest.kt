package com.shellx.app.screenshots

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.VoiceRig
import com.shellx.app.ui.pending.PendingFixtures.mac
import com.shellx.app.ui.pending.PendingFixtures.plan
import com.shellx.app.ui.pending.PendingFixtures.question
import com.shellx.app.ui.pending.PendingFixtures.questions
import com.shellx.app.ui.pending.PendingSheetState
import com.shellx.app.ui.pending.PlanReviewSheet
import com.shellx.app.ui.pending.QuestionAnswerSheet
import com.shellx.app.voice.LocalVoice
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.pending.DecisionCenter
import com.shellx.core.pending.DecisionStatus
import com.shellx.core.pending.PendingSheetModel
import com.shellx.core.pending.QuestionDraft
import com.shellx.core.voice.VoiceInputModel
import com.shellx.core.voice.optionMatching
import com.shellx.link.core.PendingItem
import com.shellx.link.core.PendingKind
import com.shellx.link.core.PendingQuestion
import com.shellx.link.core.PendingQuestionOption
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The question and plan sheets of `PendingCardRenderTests.swift`, and their mics (`MicButtonRenderTests.swift`). Each
 *  sheet's content is drawn as it is, without the bottom sheet around it. */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class PendingSheetRenderTest {
    private val item = mac(question())

    private fun answered(): QuestionDraft =
        QuestionDraft(questions).toggle("db", "Postgres").setFreeText("checks", "Only lint, the UI tests are flaky today")

    @Test
    fun pendingQuestion() {
        assertRenders("pending-question") { QuestionAnswerSheet(item, PendingSheetState(), send = {}, close = {}) }
    }

    @Test
    fun pendingQuestionOther() {
        assertRenders("pending-question-other") {
            QuestionAnswerSheet(item, PendingSheetState(), send = {}, close = {}, draft = answered(), page = 1, typing = setOf("checks"))
        }
    }

    @Test
    fun pendingQuestionHandled() {
        assertRenders("pending-question-handled") {
            QuestionAnswerSheet(item, PendingSheetState(handledElsewhere = true, canSend = false), send = {}, close = {}, draft = answered())
        }
    }

    @Test
    fun pendingQuestionReconnecting() {
        assertRenders("pending-question-reconnecting") {
            QuestionAnswerSheet(
                mac(question(), actionable = false), PendingSheetState(canSend = false, actionable = false), send = {}, close = {},
                draft = answered(), page = 1,
            )
        }
    }

    /** The Mac went offline with the answer typed: the answer stays, Send is off, the line says why. */
    @Test
    fun pendingQuestionOffline() {
        assertRenders("pending-question-offline") {
            QuestionAnswerSheet(
                mac(question(), actionable = false),
                PendingSheetState(canSend = false, actionable = false, linkNote = PendingSheetModel.LinkNote.OFFLINE), send = {},
                close = {}, draft = answered(), page = 1,
            )
        }
    }

    @Test
    fun pendingQuestionTooLong() {
        assertRenders("pending-question-too-long") {
            QuestionAnswerSheet(
                item, PendingSheetState(), send = {}, close = {}, page = 1, typing = setOf("checks"),
                freeText = mapOf("checks" to "Chỉ chạy lint thôi. ".repeat(60)),
            )
        }
    }

    @Test
    fun pendingQuestionChoicesTooLong() {
        val wide = PendingItem(
            requestId = "w1", kind = PendingKind.QUESTION, agent = "claude", workspaceId = "ws", workspaceTitle = "shellx",
            createdAtMs = 6,
            questions = listOf(
                PendingQuestion(
                    id = "wide", prompt = "Which notes go in the release?", multiSelect = true,
                    options = (1..3).map { PendingQuestionOption("o$it", "Note $it: " + "x".repeat(400)) },
                ),
            ),
        )
        var picks = QuestionDraft(wide.questions.orEmpty())
        for (option in wide.questions.orEmpty().first().options) picks = picks.toggle("wide", option.label)
        assertRenders("pending-question-choices-too-long") {
            QuestionAnswerSheet(mac(wide), PendingSheetState(), send = {}, close = {}, draft = picks)
        }
    }

    @Test
    fun pendingPlan() {
        assertRenders("pending-plan") { PlanReviewSheet(mac(plan()), PendingSheetState(), send = {}, close = {}) }
    }

    @Test
    fun pendingPlanReviseTooLong() {
        assertRenders("pending-plan-revise-too-long") {
            PlanReviewSheet(mac(plan()), PendingSheetState(), send = {}, close = {}, revising = true, feedback = "Tách bước 2 ra. ".repeat(260))
        }
    }

    @Test
    fun pendingPlanHandled() {
        assertRenders("pending-plan-handled") {
            PlanReviewSheet(mac(plan()), PendingSheetState(status = DecisionStatus.HandledElsewhere, canSend = false), send = {}, close = {})
        }
    }

    @Test
    fun pendingPlanNeedsPairing() {
        assertRenders("pending-plan-needs-pairing") {
            PlanReviewSheet(
                mac(plan(), actionable = false),
                PendingSheetState(canSend = false, actionable = false, linkNote = PendingSheetModel.LinkNote.NEEDS_PAIRING), send = {},
                close = {},
            )
        }
    }

    @Test
    fun pendingPlanMissing() {
        assertRenders("pending-plan-missing") {
            PlanReviewSheet(
                mac(plan(null, modes = listOf("manual", "deny"))), PendingSheetState(status = DecisionStatus.Sending, canSend = false),
                send = {}, close = {},
            )
        }
    }

    // MicButtonRenderTests' sheets: one question, the mic in the bottom bar.

    private val voiceQuestion = MachinePendingItem(
        "m1", "MacBook Pro",
        PendingItem(
            requestId = "q1", kind = PendingKind.QUESTION, agent = "claude", workspaceId = "ws", workspaceTitle = "shellx",
            createdAtMs = 1,
            questions = listOf(
                PendingQuestion(
                    id = "db", header = "Database", prompt = "Which database should the relay use?", multiSelect = false,
                    options = listOf(PendingQuestionOption("pg", "Postgres"), PendingQuestionOption("lite", "SQLite")),
                ),
            ),
        ),
        true,
    )

    /** A rig and its model made once per capture (each capture composes anew), [prepare]d by an effect: nothing blocks
     *  the composition. */
    @Composable
    private fun WithMic(
        maxBytes: Int,
        prepare: suspend (VoiceRig, VoiceInputModel) -> Unit = { _, _ -> },
        content: @Composable (VoiceInputModel) -> Unit,
    ) {
        val (rig, model) = remember {
            val rig = VoiceRig.make()
            rig to rig.model(maxBytes)
        }
        LaunchedEffect(model) { prepare(rig, model) }
        CompositionLocalProvider(LocalVoice provides rig.env) { content(model) }
    }

    private fun listen(words: String): suspend (VoiceRig, VoiceInputModel) -> Unit = { rig, model ->
        model.press()
        rig.engine.say(words)
    }

    @Test
    fun pendingQuestionVoiceNoMatch() {
        val words = "Dùng MongoDB đi"
        assertNull(voiceQuestion.item.questions!!.first().optionMatching(words))
        assertRenders("pending-question-voice-no-match") {
            WithMic(QuestionDraft.MAX_ANSWER_BYTES) { model ->
                QuestionAnswerSheet(
                    voiceQuestion, PendingSheetState(), send = {}, close = {}, typing = setOf("db"), freeText = mapOf("db" to words),
                    voice = model, unmatched = setOf("db"),
                )
            }
        }
    }

    /** The mic and its words sit in the bottom bar, outside the list. */
    @Test
    fun pendingQuestionVoiceListening() {
        assertRenders("pending-question-voice-listening") {
            WithMic(QuestionDraft.MAX_ANSWER_BYTES, listen("cái thứ hai")) { model ->
                QuestionAnswerSheet(voiceQuestion, PendingSheetState(), send = {}, close = {}, voice = model)
            }
        }
    }

    @Test
    fun pendingPlanVoice() {
        val relayPlan = MachinePendingItem(
            "m1", "MacBook Pro",
            PendingItem(
                requestId = "x1", kind = PendingKind.EXIT_PLAN, agent = "claude", workspaceId = "ws", workspaceTitle = "relay",
                createdAtMs = 2, modes = listOf("manual", "deny"), planPreview = "1. Remove route v1.\n2. Ship.",
            ),
            true,
        )
        assertRenders("pending-plan-voice") {
            WithMic(DecisionCenter.MAX_FEEDBACK_BYTES, listen("Giữ route v1, đừng xoá")) { model ->
                PlanReviewSheet(relayPlan, PendingSheetState(), send = {}, close = {}, revising = true, voice = model)
            }
        }
    }
}
