package com.shellx.core.voice

/**
 * Builds the whole text of a dictation from a recognizer's results: finalized segments in order, then the newest
 * tentative tail, which each new tentative result replaces.
 *
 * A recognizer may or may not carry a segment's leading space, so pieces are joined with one space only when neither
 * side already has whitespace there. Mutable (Conventions): one owner, not thread-safe. The text never prints.
 */
class TranscriptAccumulator {
    private var finalized = ""
    private var tentative = ""

    /** The text so far. */
    val text: String get() = join(finalized, tentative)

    /** Takes one result and returns the whole text so far. */
    fun take(piece: String, isFinal: Boolean): String {
        if (isFinal) {
            finalized = join(finalized, piece)
            tentative = ""
        } else {
            tentative = piece
        }
        return text
    }

    override fun toString(): String = "TranscriptAccumulator(<redacted>)"

    private companion object {
        fun join(left: String, right: String): String {
            if (left.isEmpty() || right.isEmpty()) return left + right
            return if (left.last().isWhitespace() || right.first().isWhitespace()) left + right else "$left $right"
        }
    }
}
