package com.shellx.core.pending

import com.shellx.core.text.cutToUtf8
import com.shellx.core.text.utf8Size
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.PendingQuestion

/**
 * The user's answers to a `question` item while its sheet is open: options picked per question, or a typed answer
 * ("Other…") instead. Immutable: [toggle] and [setFreeText] return the changed draft. The answers never print.
 *
 * [decision] follows PROTOCOL.md section 4 (Decision): one element per question, in the questions' order; a typed
 * answer as typed (trimmed), otherwise the picked option's label, or for a multi-select question the picked labels in
 * the options' order joined with ", ".
 */
class QuestionDraft private constructor(
    val questions: List<PendingQuestion>,
    /** Picked labels, by question id. */
    private val picked: Map<String, Set<String>>,
    /** Typed answers, by question id, as typed (already cut to MAX_ANSWER_BYTES). */
    private val typed: Map<String, String>,
) {
    constructor(questions: List<PendingQuestion>) : this(questions, emptyMap(), emptyMap())

    /**
     * Picks [label], or for a multi-select question picks or unpicks it. A single-select question keeps one pick: the
     * new one replaces the old, and picking it again keeps it. Any pick clears the question's typed answer. Unknown
     * questions and labels are ignored.
     */
    fun toggle(questionId: String, label: String): QuestionDraft {
        val question = questions.firstOrNull { it.id == questionId } ?: return this
        if (question.options.none { it.label == label }) return this
        val typed = typed - questionId
        if (!question.multiSelect) return QuestionDraft(questions, picked + (questionId to setOf(label)), typed)
        val old = picked[questionId].orEmpty()
        val labels = if (label in old) old - label else old + label
        val picked = if (labels.isEmpty()) picked - questionId else picked + (questionId to labels)
        return QuestionDraft(questions, picked, typed)
    }

    /** The "Other…" answer of a question. Text that is not blank replaces the question's picks. Text over
     *  MAX_ANSWER_BYTES UTF-8 bytes is cut on a character boundary. */
    fun setFreeText(questionId: String, text: String): QuestionDraft {
        if (questions.none { it.id == questionId }) return this
        val kept = text.cutToUtf8(MAX_ANSWER_BYTES)
        val typed = if (kept.isEmpty()) typed - questionId else typed + (questionId to kept)
        val picked = if (kept.trim().isNotEmpty()) picked - questionId else picked
        return QuestionDraft(questions, picked, typed)
    }

    fun isSelected(questionId: String, label: String): Boolean = picked[questionId]?.contains(label) ?: false

    /** The typed answer as the field shows it ("" when none). */
    fun freeText(questionId: String): String = typed[questionId] ?: ""

    fun isAnswered(questionId: String): Boolean = questions.firstOrNull { it.id == questionId }?.let(::answer) != null

    /** UTF-8 bytes of the answer the decision would carry for the question (0 when none). */
    fun answerBytes(questionId: String): Int =
        questions.firstOrNull { it.id == questionId }?.let(::answer)?.utf8Size ?: 0

    /** The question has an answer, but too long for the wire: its picked labels joined pass MAX_ANSWER_BYTES.
     *  [decision] is null until fewer are picked; the sheet says why. */
    fun isTooLong(questionId: String): Boolean = answerBytes(questionId) > MAX_ANSWER_BYTES

    /** Every question has an answer that fits the wire: [decision] is not null. */
    val isComplete: Boolean get() = decision != null

    /** The decision to send; null until every question has an answer of 1 to MAX_ANSWER_BYTES bytes. */
    val decision: LinkDecision?
        get() {
            if (questions.isEmpty()) return null
            val selections = ArrayList<String>(questions.size)
            for (question in questions) {
                val answer = answer(question)
                if (answer == null || answer.utf8Size > MAX_ANSWER_BYTES) return null
                selections += answer
            }
            return LinkDecision.Question(selections)
        }

    private fun answer(question: PendingQuestion): String? {
        val text = typed[question.id].orEmpty().trim()
        if (text.isNotEmpty()) return text
        val chosen = picked[question.id].orEmpty()
        val joined = question.options.map { it.label }.filter { it in chosen }.distinct().joinToString(", ")
        return joined.ifEmpty { null }
    }

    override fun equals(other: Any?): Boolean = other is QuestionDraft && questions == other.questions &&
        picked == other.picked && typed == other.typed

    override fun hashCode(): Int = (questions.hashCode() * 31 + picked.hashCode()) * 31 + typed.hashCode()

    override fun toString(): String = "QuestionDraft(questions=${questions.size}, <redacted>)"

    companion object {
        /** The most UTF-8 bytes one answer may take on the wire. */
        const val MAX_ANSWER_BYTES = 1024

        /** UTF-8 bytes a typed answer takes once trimmed, as the decision would send it; never cut. The sheet counts
         *  with it while the field still holds more than [setFreeText] keeps. */
        fun freeTextBytes(text: String): Int = text.trim().utf8Size
    }
}
