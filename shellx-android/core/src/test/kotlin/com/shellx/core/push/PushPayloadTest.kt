package com.shellx.core.push

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Reading what an FCM data message from a paired Mac says (contracts §8). */
class PushPayloadTest {
    @Test fun readsANeedsYouPush() {
        val data = mapOf(
            "kind" to "needs_you", "machine_id" to "m1", "request_id" to "r1", "agent" to "Claude Code",
            "workspace_title" to "shellx",
        )
        assertEquals(PushPayload.NeedsYou("m1", "r1", "Claude Code", "shellx"), PushPayload.parse(data))
    }

    @Test fun readsAResolvedPush() {
        val data = mapOf("kind" to "resolved", "machine_id" to "m1", "request_id" to "r1")
        assertEquals(PushPayload.Resolved("m1", "r1"), PushPayload.parse(data))
    }

    @Test fun anythingElseIsNotOurs() {
        assertNull(PushPayload.parse(emptyMap()))
        assertNull(PushPayload.parse(mapOf("kind" to "done", "machine_id" to "m1", "request_id" to "r1")))
        assertNull(PushPayload.parse(mapOf("kind" to "needs_you", "request_id" to "r1", "agent" to "Codex")))
        // FCM data values are always strings: an empty request id stands for the iPhone's non-string one.
        assertNull(PushPayload.parse(mapOf("kind" to "needs_you", "machine_id" to "m1", "request_id" to "", "agent" to "Codex")))
        assertNull(PushPayload.parse(mapOf("machine_id" to "m1", "request_id" to "r1", "agent" to "Codex")))
    }

    @Test fun dataWithExtraKeysOrNoTitleStillParses() {
        assertEquals(PushPayload.NeedsYou("m1", "r1", "Claude Code", ""), PushPayload.parse(mapOf("kind" to "needs_you",
            "machine_id" to "m1", "request_id" to "r1", "agent" to "Claude Code", "google.message_id" to "x", "from" to "y")))
        assertFalse(PushPayload.NeedsYou("m1", "r1", "Codex", "   ").showsWorkspace)
        assertTrue(PushPayload.NeedsYou("m1", "r1", "Codex", "Dự án 🚀").showsWorkspace)
        assertNull(PushPayload.parse(mapOf("kind" to "needs_you", "machine_id" to "m1", "request_id" to "r1")))
        assertNull(PushPayload.parse(mapOf("kind" to "needs_you", "machine_id" to "", "request_id" to "r1", "agent" to "Codex")))
        assertEquals(PushPayload.Resolved("m1", "r1"), PushPayload.parse(mapOf("kind" to "resolved", "machine_id" to "m1",
            "request_id" to "r1", "agent" to "Claude Code", "workspace_title" to "shellx")))
    }
}
