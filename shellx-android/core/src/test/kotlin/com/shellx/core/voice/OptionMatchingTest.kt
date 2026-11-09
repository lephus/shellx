package com.shellx.core.voice

import com.shellx.core.pending.QuestionDraft
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.PendingQuestion
import com.shellx.link.core.PendingQuestionOption
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/** A spoken answer picks a question's option when exactly one option matches it: the same words (ignoring Vietnamese
 *  diacritics, case and punctuation), the label said within the sentence, or the option's position ("cái thứ hai",
 *  "first"). Anything else is the question's free text. */
class OptionMatchingTest {
    private fun question(labels: List<String>, multiSelect: Boolean = false): PendingQuestion = PendingQuestion(
        id = "q", prompt = "Pick one", multiSelect = multiSelect,
        options = labels.mapIndexed { index, label -> PendingQuestionOption(id = "o$index", label = label) },
    )

    private fun picked(labels: List<String>, transcript: String): String? =
        question(labels).optionMatching(transcript)?.label

    @Test fun matchesIgnoringDiacriticsAndCase() {
        assertEquals("Postgres", picked(listOf("Postgres", "SQLite"), "postgres"))
        assertEquals("Giữ route v1", picked(listOf("Giữ route v1", "Xoá route v1"), "giu route v1"))
        assertEquals("Xoá route v1", picked(listOf("Giữ route v1", "Xoá route v1"), "Xoá route V1."))
        // đ has no combining mark; it still folds to d.
        assertEquals("Đừng xoá", picked(listOf("Đừng xoá", "Xoá luôn"), "dung xoa"))
        // The label said inside a sentence.
        assertEquals("SQLite", picked(listOf("Postgres", "SQLite"), "Mình chọn SQLite nhé!"))
        // Whole words only: "postgresql" is not "postgres".
        assertNull(picked(listOf("Postgres", "SQLite"), "postgresql"))
        // A one-letter label is matched only when said alone.
        assertEquals("B", picked(listOf("A", "B"), "b."))
        assertNull(picked(listOf("A", "B"), "a bit of both"))
    }

    @Test fun ordinalPicksOption() {
        val labels = listOf("Postgres", "SQLite", "MySQL")
        assertEquals("SQLite", picked(labels, "cái thứ hai"))
        for (first in listOf("1", "một", "thứ nhất", "đầu tiên", "first", "số một", "the first one", "Cái đầu tiên nhé.")) {
            assertEquals("Postgres", picked(labels, first), first)
        }
        for (second in listOf("2", "số hai", "Thứ hai.", "second", "number two", "đáp án hai")) {
            assertEquals("SQLite", picked(labels, second), second)
        }
        assertEquals("MySQL", picked(labels, "thứ ba"))
        assertEquals("MySQL", picked(labels, "the third one"))
        // Past the last option: nothing.
        assertNull(picked(labels, "thứ năm"))
        assertNull(picked(labels, "0"))
        // A number inside other words is not a position.
        assertNull(picked(labels, "chạy hai lần"))
    }

    @Test fun ambiguousReturnsNil() {
        // Both labels said.
        assertNull(picked(listOf("Chạy lint", "Chạy test"), "chạy lint rồi chạy test"))
        // A position and another option's label.
        assertNull(picked(listOf("Postgres", "SQLite"), "Postgres, cái thứ hai"))
        // Two options with the same words.
        assertNull(picked(listOf("Giữ", "giữ"), "giữ"))
        // The words of exactly one option win over options that are only contained in them.
        assertEquals("Yes, and add tests", picked(listOf("Yes", "Yes, and add tests"), "yes and add tests"))
    }

    @Test fun noMatchReturnsNil() {
        assertNull(picked(listOf("Postgres", "SQLite"), "dùng MongoDB đi"))
        assertNull(picked(listOf("Postgres", "SQLite"), ""))
        assertNull(picked(listOf("Postgres", "SQLite"), "  ...  "))
        assertNull(question(emptyList()).optionMatching("postgres"))
    }

    @Test fun noMatchBecomesTheQuestionsFreeText() {
        // What the question sheet does with a spoken answer: a match picks the option, anything else is the typed
        // ("Other…") answer, shown for review; neither sends.
        val question = question(listOf("Postgres", "SQLite"))
        var draft = QuestionDraft(listOf(question))
        val spoken = "Dùng MongoDB đi"
        assertNull(question.optionMatching(spoken))
        draft = draft.setFreeText("q", spoken)
        assertEquals(spoken, draft.freeText("q"))
        assertEquals(LinkDecision.Question(listOf(spoken)), draft.decision)

        val match = assertNotNull(question.optionMatching("cái thứ hai"))
        draft = draft.toggle("q", match.label)
        assertEquals(LinkDecision.Question(listOf("SQLite")), draft.decision)
    }
}
