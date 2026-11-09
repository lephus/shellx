package com.shellx.core.agent

import com.shellx.core.composer.OutgoingAttachment
import com.shellx.core.demo.FakeMac
import com.shellx.core.home.ComposerValidation
import com.shellx.core.link.AttachmentSendException
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.SessionRef
import com.shellx.core.testing.HubRig
import com.shellx.core.testing.ManualSleeper
import com.shellx.core.testing.agentSession
import com.shellx.core.testing.assertSameCase
import com.shellx.core.testing.eventually
import com.shellx.core.testing.hubRig
import com.shellx.link.core.AgentState
import com.shellx.link.core.AttachmentKind
import com.shellx.link.core.ChatAttachment
import com.shellx.link.core.ChatInterruptOutcome
import com.shellx.link.core.ChatSendOutcome
import com.shellx.link.core.ShellXLink
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/**
 * Sending and stopping from an agent's screen (AgentThreadModelTests.swift), and photos and files sent with a message
 * through the hub to a FakeMac (AttachmentSendTests.swift): what reaches the Mac, what the phone refuses before any
 * call, and what the composer gets back when the Mac surely did not take the message.
 */
class AgentThreadSendTest {
    private fun ref(mac: FakeMac, sessionId: String = "s1") = SessionRef(mac.machine.machineId, sessionId, "claude", "shellx")

    /** A Mac with one running session `s1` whose chat accepts messages. */
    private fun TestScope.macWithSession(name: String = "MacBook Pro", acceptsAttachments: Boolean = true): FakeMac {
        val mac = FakeMac(name, backgroundScope, acceptsAttachments = acceptsAttachments)
        mac.upsertSession(agentSession("s1"))
        mac.setHistory("s1", emptyList())
        return mac
    }

    /** A screenshot bigger than one upload chunk, so it goes up in several. */
    private val shot = OutgoingAttachment(
        kind = AttachmentKind.IMAGE, name = "shot.jpg", data = ByteArray(100_000) { (it * 31).toByte() },
    )
    private val log = OutgoingAttachment(kind = AttachmentKind.FILE, name = "build.log", data = "error: missing import\n".encodeToByteArray())

    private fun TestScope.model(ref: SessionRef, rig: HubRig) =
        AgentThreadModel(ref, rig.hub, rig.store, backgroundScope, ManualSleeper().sleep)

    // AgentThreadModelTests.swift: send and stop

    @Test fun sendMapsOutcomes() { runTest {
        val mac = macWithSession()
        val s1 = ref(mac)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val model = model(s1, rig)

        // Refused on the phone: nothing leaves it.
        var result = model.send(" \n ", viaVoice = false)
        assertEquals(AgentSendResult.Refused(ComposerValidation.Empty), result)
        val long = "a".repeat(ComposerValidation.MAX_BYTES + 1)
        result = model.send(long, viaVoice = true)
        assertEquals(AgentSendResult.Refused(ComposerValidation.TooLong(16_385)), result)
        assertEquals(emptyList(), mac.sentTexts)

        result = model.send("  Chạy lại test giúp mình \n", viaVoice = false)
        assertEquals(AgentSendResult.Sent(ChatSendOutcome.SUBMITTED), result)
        assertEquals(listOf(FakeMac.SentText("s1", "Chạy lại test giúp mình")), mac.sentTexts)

        for (outcome in listOf(ChatSendOutcome.BUSY, ChatSendOutcome.FAILED, ChatSendOutcome("rate_limited"))) {
            mac.setSendOutcome(outcome)
            result = model.send("Thử lại", viaVoice = false)
            assertEquals(AgentSendResult.Sent(outcome), result)
        }
        assertFalse(model.sessionGone)
        mac.setSendOutcome(ChatSendOutcome.NOT_FOUND)
        result = model.send("Còn đó không?", viaVoice = false)
        assertEquals(AgentSendResult.Sent(ChatSendOutcome.NOT_FOUND), result)
        assertTrue(model.sessionGone, "the Mac said the session is gone")
        mac.setSendOutcome(null)

        // The link dies before the answer: it is unknown whether the text arrived.
        mac.holdChat()
        val pending = async { model.send("Đang gửi", viaVoice = false) }
        assertTrue(eventually { mac.sentTexts.size == 6 })
        mac.dropLiveSessions()
        result = pending.await()
        assertEquals(AgentSendResult.NoAnswer, result)
        mac.releaseChat()

        // Offline: answered at once, nothing sent or queued.
        assertTrue(eventually { model.offline })
        result = model.send("Có ai không?", viaVoice = false)
        assertEquals(AgentSendResult.Offline, result)
        assertEquals(6, mac.sentTexts.size)

        // Only a text the Mac surely did not take goes back into the composer.
        assertEquals(
            listOf(true, true, true, true, true, true),
            listOf(
                AgentSendResult.Offline, AgentSendResult.Refused(ComposerValidation.TooLong(16_385)),
                AgentSendResult.Sent(ChatSendOutcome.BUSY), AgentSendResult.Sent(ChatSendOutcome.FAILED),
                AgentSendResult.Sent(ChatSendOutcome.NOT_FOUND), AgentSendResult.Sent(ChatSendOutcome("x")),
            ).map { it.keepsDraft },
        )
        assertEquals(
            listOf(false, false, false),
            listOf(
                AgentSendResult.Sent(ChatSendOutcome.SUBMITTED), AgentSendResult.NoAnswer,
                AgentSendResult.Refused(ComposerValidation.Empty),
            ).map { it.keepsDraft },
        )
    } }

    @Test fun stopSoftAndHard() { runTest {
        val mac = macWithSession()
        val s1 = ref(mac)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val model = model(s1, rig)
        assertTrue(model.canStop, "a working session can be stopped")
        assertEquals(AgentState.WORKING, model.session?.session?.state)
        assertEquals("MacBook Pro", model.session?.machineName)

        var outcome = model.stop(hard = false)
        assertEquals(ChatInterruptOutcome.SENT, outcome)
        outcome = model.stop(hard = true)
        assertEquals(ChatInterruptOutcome.SENT, outcome)
        assertEquals(listOf(FakeMac.Interrupt("s1", false), FakeMac.Interrupt("s1", true)), mac.interrupts)

        mac.setInterruptOutcome(ChatInterruptOutcome.FAILED)
        outcome = model.stop(hard = false)
        assertEquals(ChatInterruptOutcome.FAILED, outcome)
        assertFalse(model.sessionGone)

        // Stop shows only while the session works or waits for the user.
        mac.upsertSession(agentSession("s1", state = AgentState.IDLE))
        assertTrue(eventually { !model.canStop })
        mac.upsertSession(agentSession("s1", state = AgentState.NEEDS_INPUT))
        assertTrue(eventually { model.canStop })

        mac.setInterruptOutcome(ChatInterruptOutcome.NOT_FOUND)
        outcome = model.stop(hard = true)
        assertEquals(ChatInterruptOutcome.NOT_FOUND, outcome)
        assertTrue(model.sessionGone)
        assertFalse(model.canStop, "the Mac said the session is gone, even if its list still shows it")
        mac.setInterruptOutcome(null)

        // Offline: nothing is sent, there is no answer, and Stop goes away.
        mac.dropLiveSessions()
        assertTrue(eventually { model.offline })
        assertFalse(model.canStop, "the state shown is only the last known one")
        outcome = model.stop(hard = false)
        assertNull(outcome)
        assertEquals(4, mac.interrupts.size)
    } }

    // AttachmentSendTests.swift: sent

    @Test fun photoAndTextReachTheMac() { runTest {
        val mac = macWithSession()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))

        val model = model(ref(mac), rig)
        val result = model.send("  sửa lỗi này \n", attachments = listOf(shot), viaVoice = false)

        assertEquals(AgentSendResult.Sent(ChatSendOutcome.SUBMITTED), result)
        assertFalse(result.keepsDraft)
        assertEquals(listOf(ChatAttachment(AttachmentKind.IMAGE, "shot.jpg", shot.data)), mac.receivedAttachments)
        assertEquals(listOf(FakeMac.SentText("s1", "sửa lỗi này")), mac.sentTexts)
        assertNull(model.uploadProgress, "no progress once the message is sent")

        // A second message, with two attachments.
        val agentResult = model.send("còn file này", attachments = listOf(log, shot), viaVoice = false)
        assertEquals(AgentSendResult.Sent(ChatSendOutcome.SUBMITTED), agentResult)
        assertNull(model.uploadProgress)
        assertEquals(
            listOf(
                ChatAttachment(AttachmentKind.FILE, "build.log", log.data),
                ChatAttachment(AttachmentKind.IMAGE, "shot.jpg", shot.data),
            ),
            mac.receivedAttachments.takeLast(2),
        )
    } }

    @Test fun attachmentOnlyMessageIsSent() { runTest {
        val mac = macWithSession()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))

        val model = model(ref(mac), rig)
        val result = model.send(" \n ", attachments = listOf(log), viaVoice = false)

        assertEquals(AgentSendResult.Sent(ChatSendOutcome.SUBMITTED), result)
        assertEquals(listOf(FakeMac.SentText("s1", "")), mac.sentTexts)
        assertEquals(listOf(ChatAttachment(AttachmentKind.FILE, "build.log", log.data)), mac.receivedAttachments)

        val agentResult = model.send("", attachments = listOf(shot), viaVoice = false)
        assertEquals(AgentSendResult.Sent(ChatSendOutcome.SUBMITTED), agentResult)
        assertEquals(2, mac.sentTexts.size)
        // Still nothing to send without text or attachments.
        val empty = model.send("  ", attachments = emptyList(), viaVoice = false)
        assertEquals(AgentSendResult.Refused(ComposerValidation.Empty), empty)
    } }

    @Test fun uploadProgressShowsUntilTheMacAnswers() { runTest {
        val mac = macWithSession()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val model = model(ref(mac), rig)
        assertNull(model.uploadProgress)
        // The uploads finish; the Mac holds the message itself.
        mac.holdChat()

        val sending = async { model.send("xem ảnh", attachments = listOf(shot), viaVoice = false) }
        assertTrue(eventually { model.uploadProgress == 1.0 }, "every byte is up while the Mac has not answered")
        mac.releaseChat()
        val result = sending.await()

        assertEquals(AgentSendResult.Sent(ChatSendOutcome.SUBMITTED), result)
        assertNull(model.uploadProgress)
        // A late progress value of the finished send changes nothing.
        delay(50.milliseconds)
        runCurrent()
        assertNull(model.uploadProgress)
    } }

    /**
     * Two messages of five attachments sent at once to one Mac (two agent screens, say) both arrive whole. Each holds
     * the upload turn until its `chat.send` is answered, so the Mac never drops one of a message's uploads to make room
     * for the other's.
     */
    @Test fun twoMessagesOfFiveAttachmentsAtOnceBothArrive() { runTest {
        val mac = macWithSession()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        fun five(prefix: String): List<OutgoingAttachment> = (0 until ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE).map {
            OutgoingAttachment(kind = AttachmentKind.FILE, name = "$prefix$it.log", data = ByteArray(50_000))
        }
        val hub = rig.hub
        val target = ref(mac)

        val outcomes = coroutineScope {
            val first = async { hub.chatSend(target, "một", attachments = five("a")) {} }
            val second = async { hub.chatSend(target, "hai", attachments = five("b")) {} }
            listOf(first.await(), second.await())
        }

        assertEquals(listOf(ChatSendOutcome.SUBMITTED, ChatSendOutcome.SUBMITTED), outcomes)
        val received = mac.receivedAttachments.map { it.name }
        assertEquals((five("a").map { it.name } + five("b").map { it.name }).toSet(), received.toSet())
        assertEquals(10, received.size)
    } }

    // Refused on the phone

    @Test fun sixAttachmentsAreRefusedOnThePhone() { runTest {
        val mac = macWithSession()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val six = (1..6).map { OutgoingAttachment(kind = AttachmentKind.FILE, name = "f$it.txt", data = "$it".encodeToByteArray()) }

        assertEquals(ComposerValidation.TooManyAttachments, ComposerValidation.of("xem", attachmentCount = 6))
        assertEquals(ComposerValidation.Ok("xem"), ComposerValidation.of("xem", attachmentCount = 5))
        assertEquals(ComposerValidation.TooManyAttachments, ComposerValidation.check(six))
        assertNull(ComposerValidation.check(six.take(5)))

        val agentResult = model(ref(mac), rig).send("xem 6 file", attachments = six, viaVoice = false)
        assertEquals(AgentSendResult.Refused(ComposerValidation.TooManyAttachments), agentResult)
        assertTrue(agentResult.keepsDraft)

        assertEquals(emptyList(), mac.sentTexts)
        assertEquals(emptyList(), mac.receivedAttachments)
    } }

    @Test fun oversizeAttachmentIsRefusedOnThePhone() { runTest {
        val mac = macWithSession()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val big = OutgoingAttachment(kind = AttachmentKind.FILE, name = "video.mov", data = ByteArray(ShellXLink.MAX_ATTACHMENT_BYTES + 1))
        val atLimit = OutgoingAttachment(kind = AttachmentKind.FILE, name = "ok.bin", data = ByteArray(ShellXLink.MAX_ATTACHMENT_BYTES))

        assertEquals(ComposerValidation.AttachmentTooLarge("video.mov"), ComposerValidation.check(listOf(log, big)))
        assertNull(ComposerValidation.check(listOf(atLimit)), "10 MiB exactly is allowed")

        val agentResult = model(ref(mac), rig).send("xem video", attachments = listOf(log, big), viaVoice = false)
        assertEquals(AgentSendResult.Refused(ComposerValidation.AttachmentTooLarge("video.mov")), agentResult)
        assertTrue(agentResult.keepsDraft)

        assertEquals(emptyList(), mac.sentTexts)
        assertEquals(emptyList(), mac.receivedAttachments)
    } }

    // Not taken: the composer keeps the draft

    @Test fun failedSendGivesTheAttachmentsBack() { runTest {
        val mac = macWithSession()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val model = model(ref(mac), rig)

        // The link drops; the reconnect waits (its backoff is never released here).
        mac.dropLiveSessions()
        assertTrue(eventually { rig.hub.machines.firstOrNull()?.state == MachineLinkState.Reconnecting && model.offline })

        val agentResult = model.send("sửa lỗi này", attachments = listOf(shot), viaVoice = false)
        assertEquals(AgentSendResult.Offline, agentResult)
        assertTrue(agentResult.keepsDraft)
        assertNull(model.uploadProgress)

        assertEquals(emptyList(), mac.receivedAttachments)
    } }

    @Test fun messageTheMacDidNotTypeKeepsTheDraft() { runTest {
        val mac = macWithSession()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        mac.setSendOutcome(ChatSendOutcome.BUSY)

        val agentResult = model(ref(mac), rig).send("sửa lỗi này", attachments = listOf(shot), viaVoice = false)
        assertEquals(AgentSendResult.Sent(ChatSendOutcome.BUSY), agentResult)
        assertTrue(agentResult.keepsDraft)
    } }

    @Test fun macWithoutTheFeatureGetsNothing() { runTest {
        val mac = macWithSession(acceptsAttachments = false)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))

        // Said apart from a send that failed and can be tried again.
        val agentResult = model(ref(mac), rig).send("sửa lỗi này", attachments = listOf(shot), viaVoice = false)
        assertEquals(AgentSendResult.AttachmentsUnsupported, agentResult)
        assertTrue(agentResult.keepsDraft)
        assertSameCase(
            AttachmentSendException.Refused("unsupported"),
            assertFails { rig.hub.chatSend(ref(mac), "x", attachments = listOf(shot)) {} },
            "a Mac without the feature is never sent attachments",
        )
        assertEquals(emptyList(), mac.sentTexts)
    } }

    @Test fun refusedUploadKeepsTheDraft() { runTest {
        val mac = macWithSession()
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        // An empty file: the Mac takes 1 byte to 10 MiB, so it refuses the upload.
        val empty = OutgoingAttachment(kind = AttachmentKind.FILE, name = "empty.txt", data = ByteArray(0))

        val agentResult = model(ref(mac), rig).send("xem", attachments = listOf(empty), viaVoice = false)

        // A refusal other than `unsupported` is a plain failure, to try again.
        assertEquals(AgentSendResult.NotSent, agentResult)
        assertTrue(agentResult.keepsDraft)
        assertEquals(emptyList(), mac.sentTexts)
    } }

    // Gating

    @Test fun attachButtonOnlyForMacsThatAcceptThem() { runTest {
        val takes = macWithSession(name = "MacBook Pro")
        val refuses = FakeMac("Mac mini", backgroundScope, acceptsAttachments = false)
        val old = FakeMac("iMac", backgroundScope, servesSessionsAndChat = false)
        val rig = hubRig(listOf(takes, refuses, old), start = true)
        assertTrue(eventually { rig.hub.machines.all { it.state == MachineLinkState.Online } })

        assertTrue(rig.hub.acceptsAttachments(takes.machine.machineId))
        assertFalse(rig.hub.acceptsAttachments(refuses.machine.machineId))
        assertFalse(rig.hub.acceptsAttachments(old.machine.machineId), "no chat, no attachments")
        assertFalse(rig.hub.acceptsAttachments("mac-unknown"))

        // What the Mac said last stays known while it reconnects, so the button does not flicker.
        takes.dropLiveSessions()
        assertTrue(
            eventually { rig.hub.machines.firstOrNull { it.id == takes.machine.machineId }?.state == MachineLinkState.Reconnecting },
        )
        assertTrue(rig.hub.acceptsAttachments(takes.machine.machineId))
    } }
}
