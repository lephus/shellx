package com.shellx.app.ui.pending

import androidx.compose.runtime.saveable.SaverScope
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.core.pending.QuestionDraft
import com.shellx.link.core.ExitPlanMode
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.PendingQuestion
import com.shellx.link.core.PendingQuestionOption
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** The sheets' rules: answers over the wire's limit, a draft kept across recreation, and the approval titles. */
@RunWith(AndroidJUnit4::class)
class SheetRulesTest {
    @Test
    fun questionSheetBlocksAnswersOverTheLimit() {
        val questions = PendingFixtures.questions
        var draft = QuestionDraft(questions)
        draft = draft.toggle("db", "Postgres")
        val long = "ệ".repeat(400)
        draft = draft.setFreeText("checks", long)
        assertTrue("the draft holds the cut text", draft.isComplete)
        assertTrue("the field holds 1200 bytes: Send stays off", QuestionAnswerSheet.tooLong(draft, mapOf("checks" to long)))
        assertFalse(QuestionAnswerSheet.tooLong(draft, mapOf("checks" to "Only lint")))
        assertFalse(QuestionAnswerSheet.tooLong(draft, emptyMap()))

        val wide = PendingQuestion(
            id = "wide", prompt = "Pick", multiSelect = true,
            options = (0 until 3).map { PendingQuestionOption("o$it", "$it".repeat(400)) },
        )
        var picks = QuestionDraft(listOf(wide))
        for (option in wide.options) picks = picks.toggle("wide", option.label)
        assertTrue("joined labels past the limit", QuestionAnswerSheet.tooLong(picks, emptyMap()))
    }

    @Test
    fun aDraftSurvivesItsSaver() {
        val questions = PendingFixtures.questions
        val draft = QuestionDraft(questions).toggle("db", "Postgres").setFreeText("checks", "Chỉ lint")
        val saver = QuestionAnswerSheet.draftSaver(questions)
        val saved = with(saver) { SaverScope { true }.save(draft) }!!
        val restored = saver.restore(saved)!!
        assertEquals(LinkDecision.Question(listOf("Postgres", "Chỉ lint")), restored.decision)
        assertEquals(draft.decision, restored.decision)
        assertEquals(draft, restored)
    }

    @Test
    fun eachApprovalModeHasItsTitle() {
        assertEquals(R.string.pending_plan_auto_accept, PlanReviewSheet.title(ExitPlanMode.AUTO_ACCEPT))
        assertEquals(R.string.pending_plan_ultraplan, PlanReviewSheet.title(ExitPlanMode.ULTRAPLAN))
        assertEquals(R.string.pending_plan_approve, PlanReviewSheet.title(ExitPlanMode.MANUAL))
        assertEquals(R.string.pending_plan_approve, PlanReviewSheet.title(ExitPlanMode("x")))
    }
}
