package com.shellx.core.home

import com.shellx.core.agent.AgentSendResult
import com.shellx.core.agent.AgentThreadModel
import com.shellx.core.demo.FakeMac
import com.shellx.core.link.SessionRef
import com.shellx.core.testing.ManualSleeper
import com.shellx.core.testing.agentSession
import com.shellx.core.testing.hubRig
import com.shellx.core.text.utf8Size
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

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

    @Test fun overlongTextRefusedBeforeSend() { runTest {
        val text = "ệ".repeat(5_461) + "ab"
        assertEquals(16_385, text.utf8Size)
        assertEquals(ComposerValidation.TooLong(16_385), ComposerValidation.of(text))

        // With a live session to send to, an agent's screen still sends nothing.
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.upsertSession(agentSession("s1"))
        mac.setHistory("s1", emptyList())
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val ref = SessionRef(mac.machine.machineId, "s1", "claude", "shellx")
        val model = AgentThreadModel(ref, rig.hub, rig.store, backgroundScope, ManualSleeper().sleep)

        val result = model.send(text, viaVoice = true)

        assertEquals(AgentSendResult.Refused(ComposerValidation.TooLong(16_385)), result)
        assertEquals(emptyList(), mac.sentTexts)
    } }
}
