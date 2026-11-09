package com.shellx.core.voice

import com.shellx.core.text.graphemeCount
import com.shellx.link.core.PendingQuestion
import com.shellx.link.core.PendingQuestionOption
import java.text.Normalizer
import java.util.Locale

/**
 * The option a spoken answer picks, or null when it picks none or more than one. Null leaves the words to the
 * question's typed answer (`QuestionDraft.setFreeText`), shown for review; a spoken answer is never sent by itself.
 *
 * Both sides are compared without Vietnamese diacritics (đ is d), case or punctuation:
 * 1. an option whose words are exactly the words said wins when it is the only one;
 * 2. otherwise an option matches when its label (two characters or more) is said as whole words within the sentence,
 *    or when the sentence names its position: "1", "một", "thứ nhất", "đầu tiên", "first", "số hai", "cái thứ hai",
 *    "number two"…; exactly one must match.
 */
fun PendingQuestion.optionMatching(transcript: String): PendingQuestionOption? {
    val said = SpokenWords(transcript)
    if (said.words.isEmpty() || options.isEmpty()) return null
    val labels = options.map { SpokenWords(it.label) }

    val exact = labels.indices.filter { labels[it].words == said.words }
    if (exact.size == 1) return options[exact[0]]

    val matched = HashSet<Int>()
    for (index in labels.indices) {
        if (labels[index].letterCount >= 2 && said.contains(labels[index])) matched += index
    }
    for (position in said.positions()) {
        if (position - 1 in options.indices) matched += position - 1
    }
    return if (matched.size == 1) options[matched.first()] else null
}

/**
 * Text reduced to lower-case words without diacritics or punctuation, for comparing what was said with an option.
 * Folding: đ/Đ become d/D, then NFKD, then every combining mark (\p{M}) is dropped, then lower case (Locale.ROOT);
 * every code point that is not a letter or digit becomes a space.
 */
private class SpokenWords(text: String) {
    val words: List<String>

    init {
        val decomposed = Normalizer.normalize(text.replace("đ", "d").replace("Đ", "D"), Normalizer.Form.NFKD)
        val folded = MARKS.replace(decomposed, "").lowercase(Locale.ROOT)
        val spaced = StringBuilder(folded.length)
        var i = 0
        while (i < folded.length) {
            val cp = folded.codePointAt(i)
            if (Character.isLetterOrDigit(cp)) spaced.appendCodePoint(cp) else spaced.append(' ')
            i += Character.charCount(cp)
        }
        words = spaced.split(' ').filter { it.isNotEmpty() }
    }

    val letterCount: Int get() = words.sumOf { it.graphemeCount() }

    /** Whether [other]'s words appear here in a row. */
    fun contains(other: SpokenWords): Boolean {
        val needle = other.words
        if (needle.isEmpty() || needle.size > words.size) return false
        return (0..(words.size - needle.size)).any { start -> words.subList(start, start + needle.size) == needle }
    }

    /**
     * The 1-based positions named: an ordinal phrase anywhere ("thứ hai", "số 2", "đầu tiên", "second", "number two"),
     * or a bare number when it is all that was said besides filler words ("2", "một", "đáp án hai"). A number inside
     * other words ("chạy hai lần") is not a position.
     */
    fun positions(): Set<Int> {
        val found = HashSet<Int>()
        for ((index, word) in words.withIndex()) {
            val next = words.getOrNull(index + 1)
            val ordinal = ENGLISH_ORDINALS[word]
            if (ordinal != null) {
                found += ordinal
                continue
            }
            if (word == "dau" && next == "tien") {
                found += 1
                continue
            }
            if (word == "thu" && next != null) {
                val value = AFTER_THU[next] ?: number(next)
                if (value != null) {
                    found += value
                    continue
                }
            }
            if (word in NUMBER_MARKERS && next != null) {
                val value = number(next)
                if (value != null) {
                    found += value
                    continue
                }
            }
            if (index + 2 < words.size && listOf(word, words[index + 1]) in NUMBER_MARKER_PAIRS) {
                val value = number(words[index + 2])
                if (value != null) found += value
            }
        }
        val rest = words.filter { it !in FILLERS }
        if (rest.size == 1) number(rest[0])?.let { found += it }
        return found
    }

    private companion object {
        val MARKS = Regex("\\p{M}+")

        /** 1 to 99 in ASCII digits (Swift's `Int(_:)` takes no other digits), or a cardinal word. */
        fun number(word: String): Int? {
            if (word.isNotEmpty() && word.length <= 9 && word.all { it in '0'..'9' }) {
                val value = word.toInt()
                if (value in 1..99) return value
            }
            return CARDINALS[word]
        }

        /** Cardinal numbers, folded: Vietnamese, then English. */
        val CARDINALS: Map<String, Int> = mapOf(
            "mot" to 1, "hai" to 2, "ba" to 3, "bon" to 4, "nam" to 5, "sau" to 6, "bay" to 7, "tam" to 8, "chin" to 9,
            "muoi" to 10,
            "one" to 1, "two" to 2, "three" to 3, "four" to 4, "five" to 5, "six" to 6, "seven" to 7, "eight" to 8,
            "nine" to 9, "ten" to 10,
        )

        /** Words that only follow "thứ": "thứ nhất", "thứ tư". */
        val AFTER_THU: Map<String, Int> = mapOf("nhat" to 1, "tu" to 4)

        val ENGLISH_ORDINALS: Map<String, Int> = mapOf(
            "first" to 1, "second" to 2, "third" to 3, "fourth" to 4, "fifth" to 5, "sixth" to 6, "seventh" to 7,
            "eighth" to 8, "ninth" to 9, "tenth" to 10, "1st" to 1, "2nd" to 2, "3rd" to 3, "4th" to 4, "5th" to 5,
            "6th" to 6, "7th" to 7, "8th" to 8, "9th" to 9, "10th" to 10,
        )

        /** A word that makes the number after it a position: "số 2", "number two", "option 3". */
        val NUMBER_MARKERS: Set<String> = setOf("so", "number", "option", "choice", "answer")

        /** Two words that do the same: "đáp án hai", "phương án 2", "lựa chọn ba". */
        val NUMBER_MARKER_PAIRS: Set<List<String>> = setOf(listOf("dap", "an"), listOf("phuong", "an"), listOf("lua", "chon"))

        /** Words said around a bare position: "cái", "số", "chọn", "nhé", "the", "pick"… */
        val FILLERS: Set<String> = setOf(
            "cai", "so", "thu", "dap", "an", "phuong", "lua", "chon", "nhe", "nha", "di", "a", "ah", "oi", "la",
            "the", "number", "option", "choice", "answer", "pick", "select", "please",
        )
    }
}
