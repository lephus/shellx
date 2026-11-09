package com.shellx.core.voice

import kotlin.test.Test
import kotlin.test.assertEquals

/** A recognizer reports finalized segments and a tentative tail. The whole text is the finalized segments plus the
 *  newest tail; a space goes between two pieces only when neither side already has whitespace there, so segments
 *  that carry their own spaces are not doubled. */
class TranscriptAccumulatorTest {
    @Test fun volatileTailIsReplacedAndFinalSegmentsKept() {
        val text = TranscriptAccumulator()
        assertEquals("chạy", text.take("chạy", isFinal = false))
        assertEquals("chạy test", text.take("chạy test", isFinal = false))
        assertEquals("chạy test", text.take("chạy test", isFinal = true))
        assertEquals("chạy test cho", text.take("cho", isFinal = false))
        assertEquals("chạy test cho shellx", text.take("cho shellx", isFinal = false))
        assertEquals("chạy test cho shellx.", text.take("cho shellx.", isFinal = true))
        assertEquals("chạy test cho shellx.", text.text)
    }

    @Test fun segmentsWithTheirOwnSpacesAreNotDoubled() {
        val text = TranscriptAccumulator()
        text.take("Merge main", isFinal = true)
        assertEquals("Merge main vào develop", text.take(" vào develop", isFinal = false))
        assertEquals("Merge main vào develop.", text.take(" vào develop.", isFinal = true))

        val trailing = TranscriptAccumulator()
        trailing.take("Tạo PR ", isFinal = true)
        assertEquals("Tạo PR cho branch develop", trailing.take("cho branch develop", isFinal = true))
    }

    @Test fun emptyPiecesAddNothing() {
        val text = TranscriptAccumulator()
        assertEquals("", text.take("", isFinal = false))
        assertEquals("push", text.take("push", isFinal = true))
        assertEquals("push", text.take("", isFinal = false))
        assertEquals("push", text.take("", isFinal = true))
    }
}
