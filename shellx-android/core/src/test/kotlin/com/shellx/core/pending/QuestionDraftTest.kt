package com.shellx.core.pending

import com.shellx.core.text.utf8Size
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.PendingQuestion
import com.shellx.link.core.PendingQuestionOption
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Answers to an agent's questions, built up on the phone and sent as positional `selections` (PROTOCOL.md
 *  section 4, Decision). */
class QuestionDraftTest {
    private val color = PendingQuestion(
        id = "color", header = "Colour", prompt = "Which colour?", multiSelect = false,
        options = listOf(PendingQuestionOption("blue", "Blue"), PendingQuestionOption("gray", "Gray")),
    )
    private val checks = PendingQuestion(
        id = "checks", prompt = "Which checks?", multiSelect = true,
        options = listOf(PendingQuestionOption("lint", "Lint"), PendingQuestionOption("unit", "Unit"), PendingQuestionOption("ui", "UI")),
    )

    @Test fun singleSelectReplaces() {
        var draft = QuestionDraft(listOf(color))
        draft = draft.toggle("color", "Blue")
        draft = draft.toggle("color", "Gray")
        assertFalse(draft.isSelected("color", "Blue"))
        assertTrue(draft.isSelected("color", "Gray"))
        draft = draft.toggle("color", "Gray")
        assertTrue(draft.isSelected("color", "Gray"), "a single choice stays chosen")
        assertEquals(LinkDecision.Question(listOf("Gray")), draft.decision)
    }

    @Test fun multiSelectToggles() {
        var draft = QuestionDraft(listOf(checks))
        draft = draft.toggle("checks", "UI")
        draft = draft.toggle("checks", "Lint")
        draft = draft.toggle("checks", "Unit")
        draft = draft.toggle("checks", "Unit")
        assertEquals(LinkDecision.Question(listOf("Lint, UI")), draft.decision)
        draft = draft.toggle("checks", "Lint")
        draft = draft.toggle("checks", "UI")
        assertFalse(draft.isComplete, "nothing chosen any more")
        assertNull(draft.decision)
    }

    @Test fun multiSelectJoinsLabels() {
        var draft = QuestionDraft(listOf(checks))
        for (label in listOf("UI", "Unit", "Lint")) draft = draft.toggle("checks", label)
        assertEquals(LinkDecision.Question(listOf("Lint, Unit, UI")), draft.decision, "in the options' order")
    }

    @Test fun completeNeedsEveryQuestion() {
        var draft = QuestionDraft(listOf(color, checks))
        assertFalse(draft.isComplete)
        draft = draft.toggle("color", "Blue")
        assertFalse(draft.isComplete)
        assertTrue(draft.isAnswered("color"))
        assertFalse(draft.isAnswered("checks"))
        draft = draft.setFreeText("checks", "   ")
        assertFalse(draft.isComplete, "blank text answers nothing")
        draft = draft.setFreeText("checks", "Only the fast ones")
        assertTrue(draft.isComplete)
        assertFalse(QuestionDraft(emptyList()).isComplete, "no question, nothing to send")
        assertNull(QuestionDraft(emptyList()).decision)
    }

    @Test fun decisionKeepsQuestionOrder() {
        var draft = QuestionDraft(listOf(color, checks))
        draft = draft.toggle("checks", "Unit")
        draft = draft.toggle("color", "Gray")
        assertEquals(LinkDecision.Question(listOf("Gray", "Unit")), draft.decision)
    }

    @Test fun freeTextAnswerIsPositional() {
        var draft = QuestionDraft(listOf(color, checks))
        draft = draft.setFreeText("color", "  Teal, like the logo \n")
        draft = draft.toggle("checks", "Lint")
        assertEquals(LinkDecision.Question(listOf("Teal, like the logo", "Lint")), draft.decision)
        assertEquals("  Teal, like the logo \n", draft.freeText("color"), "the field keeps what was typed")
    }

    @Test fun choosingOptionClearsFreeText() {
        var draft = QuestionDraft(listOf(checks))
        draft = draft.toggle("checks", "Lint")
        draft = draft.setFreeText("checks", "None of these")
        assertFalse(draft.isSelected("checks", "Lint"), "typed text replaces the choices")
        assertEquals(LinkDecision.Question(listOf("None of these")), draft.decision)

        draft = draft.toggle("checks", "UI")
        assertEquals("", draft.freeText("checks"))
        assertEquals(LinkDecision.Question(listOf("UI")), draft.decision)
    }

    @Test fun joinedLabelsOverLimitSayWhy() {
        val long = PendingQuestion(
            id = "long", prompt = "Pick", multiSelect = true,
            options = (0 until 3).map { PendingQuestionOption("o$it", "$it".repeat(400)) },
        )
        var draft = QuestionDraft(listOf(long))
        draft = draft.toggle("long", "0".repeat(400))
        draft = draft.toggle("long", "1".repeat(400))
        assertEquals(802, draft.answerBytes("long"))
        assertFalse(draft.isTooLong("long"))
        assertTrue(draft.isComplete)

        draft = draft.toggle("long", "2".repeat(400))

        assertEquals(1204, draft.answerBytes("long"), "three labels and two separators")
        assertTrue(draft.isTooLong("long"), "the sheet can say why Send is off")
        assertTrue(draft.isAnswered("long"))
        assertFalse(draft.isComplete)
        assertNull(draft.decision)
        assertEquals(0, draft.answerBytes("missing"))
    }

    @Test fun freeTextBytesCountWhatIsSent() {
        assertEquals(3, QuestionDraft.freeTextBytes("  ệ \n"), "trimmed, as the decision sends it")
        assertEquals(2000, QuestionDraft.freeTextBytes("a".repeat(2000)), "never cut")
        assertEquals(0, QuestionDraft.freeTextBytes(""))
    }

    @Test fun freeTextCutAt1024Bytes() {
        var draft = QuestionDraft(listOf(color))
        // "ệ" is 3 UTF-8 bytes: 341 of them make 1023 bytes, so a 342nd cannot fit whole.
        draft = draft.setFreeText("color", "ệ".repeat(400))
        val kept = draft.freeText("color")
        assertEquals(1023, kept.utf8Size)
        assertEquals("ệ".repeat(341), kept)

        // A flag is one character of two scalars (8 bytes): it is kept whole or not at all.
        draft = draft.setFreeText("color", "a".repeat(1020) + "🇻🇳")
        assertEquals("a".repeat(1020), draft.freeText("color"))

        draft = draft.setFreeText("color", "b".repeat(1024))
        assertEquals(1024, draft.freeText("color").utf8Size)
        assertEquals(1024, QuestionDraft.MAX_ANSWER_BYTES)
    }
}
