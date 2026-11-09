package com.shellx.core.text

import java.text.Normalizer

// The unit Swift's `String` counts in: what a person sees as one character. JDK 17's BreakIterator splits emoji ZWJ
// sequences, so this is a simplified grapheme rule of its own:
// - a cluster is one code point followed by any number of extenders: combining marks, variation selectors, emoji
//   modifiers (skin tones), tag characters, and U+200D ZWJ together with the code point after it (and its extenders);
// - two regional indicators in a row are one cluster (a flag);
// - "\r\n" is one cluster, and a CR or LF never takes extenders.

/** The clusters of this string, in order. */
fun String.graphemes(): List<String> {
    val out = ArrayList<String>()
    var start = 0
    while (start < length) {
        val end = graphemeEnd(start)
        out += substring(start, end)
        start = end
    }
    return out
}

fun String.graphemeCount(): Int {
    var count = 0
    var start = 0
    while (start < length) {
        start = graphemeEnd(start)
        count += 1
    }
    return count
}

/** The first [count] clusters. */
fun String.takeGraphemes(count: Int): String {
    var end = 0
    var taken = 0
    while (end < length && taken < count) {
        end = graphemeEnd(end)
        taken += 1
    }
    return substring(0, end)
}

/** This string without its last cluster; "" stays "". */
fun String.dropLastGrapheme(): String {
    var last = 0
    var start = 0
    while (start < length) {
        last = start
        start = graphemeEnd(start)
    }
    return substring(0, last)
}

/** The longest prefix of whole clusters with at most [maxBytes] UTF-8 bytes. */
fun String.cutToUtf8(maxBytes: Int): String {
    var end = 0
    var bytes = 0
    while (end < length) {
        val next = graphemeEnd(end)
        val size = substring(end, next).utf8Size
        if (bytes + size > maxBytes) break
        bytes += size
        end = next
    }
    return substring(0, end)
}

/** The number of bytes of this string's UTF-8 form, as it goes on the wire. */
val String.utf8Size: Int get() = encodeToByteArray().size

/** The composed form (java.text.Normalizer NFC). */
fun String.nfc(): String = Normalizer.normalize(this, Normalizer.Form.NFC)

/** Swift's `split(whereSeparator: \.isNewline)`: the lines between "\r\n", "\r", "\n", U+000B, U+000C, U+0085,
 *  U+2028 and U+2029, without the empty ones. */
internal fun String.nonEmptyLines(): List<String> = split(LINE_BREAK).filter { it.isNotEmpty() }

/** Swift's `split(whereSeparator: \.isWhitespace)`: the runs of characters between whitespace. */
internal fun String.words(): List<String> {
    val out = ArrayList<String>()
    val word = StringBuilder()
    for (c in this) {
        if (c.isWhitespace()) {
            if (word.isNotEmpty()) {
                out += word.toString()
                word.setLength(0)
            }
        } else {
            word.append(c)
        }
    }
    if (word.isNotEmpty()) out += word.toString()
    return out
}

private val LINE_BREAK = Regex("\r\n|[\n\r\u000B\u000C\u0085\u2028\u2029]")

private const val CR = 0x0D
private const val LF = 0x0A
private const val ZWJ = 0x200D

/** The index just past the cluster that starts at [start]. */
private fun String.graphemeEnd(start: Int): Int {
    val first = codePointAt(start)
    var i = start + Character.charCount(first)
    if (first == CR) return if (i < length && this[i].code == LF) i + 1 else i
    if (first == LF) return i
    if (isRegionalIndicator(first) && i < length) {
        val next = codePointAt(i)
        if (isRegionalIndicator(next)) i += Character.charCount(next)
    }
    while (i < length) {
        val cp = codePointAt(i)
        when {
            isExtender(cp) -> i += Character.charCount(cp)
            cp == ZWJ -> {
                i += 1
                if (i < length) {
                    val joined = codePointAt(i)
                    if (joined == CR || joined == LF) return i
                    i += Character.charCount(joined)
                }
            }
            else -> return i
        }
    }
    return i
}

private fun isRegionalIndicator(cp: Int): Boolean = cp in 0x1F1E6..0x1F1FF

private fun isExtender(cp: Int): Boolean {
    when (Character.getType(cp).toByte()) {
        Character.NON_SPACING_MARK, Character.ENCLOSING_MARK, Character.COMBINING_SPACING_MARK -> return true
    }
    return cp in 0xFE00..0xFE0F || cp in 0xE0100..0xE01EF || cp in 0x1F3FB..0x1F3FF || cp in 0xE0020..0xE007F
}
