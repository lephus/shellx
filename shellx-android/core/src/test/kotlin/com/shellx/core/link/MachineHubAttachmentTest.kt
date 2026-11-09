package com.shellx.core.link

import com.shellx.core.composer.OutgoingAttachment
import com.shellx.core.demo.FakeMac
import com.shellx.core.testing.agentSession
import com.shellx.core.testing.hubRig
import com.shellx.link.core.AttachmentKind
import com.shellx.link.core.ChatSendOutcome
import com.shellx.link.core.ShellXLink
import java.util.Collections
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

/** The hub's chatSend with attachments (AttachmentSendTests.swift). */
class MachineHubAttachmentTest {
    /** A screenshot bigger than one upload chunk, so it goes up in several. */
    private val shot = OutgoingAttachment(
        kind = AttachmentKind.IMAGE, name = "shot.jpg", data = ByteArray(100_000) { (it * 31).toByte() },
    )
    private val log = OutgoingAttachment(kind = AttachmentKind.FILE, name = "build.log", data = "error: missing import\n".encodeToByteArray())

    @Test fun progressCountsTheBytesOfEveryAttachment() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        mac.upsertSession(agentSession("s1"))
        mac.setHistory("s1", emptyList())
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val seen = Collections.synchronizedList(mutableListOf<Double>())
        val ref = SessionRef(mac.machine.machineId, "s1", "claude", "shellx")

        val outcome = rig.hub.chatSend(ref, "xem giúp", attachments = listOf(shot, log)) { seen += it }

        assertEquals(ChatSendOutcome.SUBMITTED, outcome)
        val fractions = seen.toList()
        assertEquals(fractions.sorted(), fractions, "progress only goes up")
        assertTrue(fractions.size > 2, "one value per chunk: the photo takes three")
        assertEquals(1.0, fractions.last(), 1e-9)
        val total = (shot.data.size + log.data.size).toDouble()
        assertEquals(ShellXLink.MAX_ATTACHMENT_CHUNK_BYTES / total, fractions.first(), 1e-9)
    } }
}
