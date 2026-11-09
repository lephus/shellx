package com.shellx.core.home

import com.shellx.core.text.utf8Size
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * What the composer may send: trimmed, not empty, at most 16 384 UTF-8 bytes (the `chat.send` limit), checked on the
 * phone so the Mac never has to refuse it.
 */
class ComposerValidationTest {
    @Test fun whitespaceIsEmpty() {
        assertEquals(ComposerValidation.Empty, ComposerValidation.of(""))
        assertEquals(ComposerValidation.Empty, ComposerValidation.of("  \n\t 　"))
        assertEquals(ComposerValidation.Ok("chạy test đi"), ComposerValidation.of("  chạy test đi \n"))
    }

    @Test fun exactly16384BytesOk() {
        assertEquals(16_384, ComposerValidation.MAX_BYTES)
        val ascii = "a".repeat(16_384)
        assertEquals(ComposerValidation.Ok(ascii), ComposerValidation.of("\n $ascii  "), "counted after trimming")
        // "ệ" is 3 bytes: 5461 of them and one "a" make exactly 16 384.
        val vietnamese = "ệ".repeat(5_461) + "a"
        assertEquals(16_384, vietnamese.utf8Size)
        assertEquals(ComposerValidation.Ok(vietnamese), ComposerValidation.of(vietnamese))
    }

    /** The agent screen's half of the Swift test (nothing reaches the Mac) needs AgentThreadModel: Task 21 adds it. */
    @Test fun overlongTextRefusedBeforeSend() {
        val text = "ệ".repeat(5_461) + "ab"
        assertEquals(16_385, text.utf8Size)
        assertEquals(ComposerValidation.TooLong(16_385), ComposerValidation.of(text))
    }
}
