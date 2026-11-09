package com.shellx.core.link

import com.shellx.core.testing.pendingItem
import kotlin.test.Test
import kotlin.test.assertEquals

class PendingSetTest {
    @Test fun oldRevisionIgnored() {
        var set = PendingSet()
        set = set.reset(5, listOf(pendingItem("a")))

        var r = set.apply(5, listOf(pendingItem("b")), listOf("a")); set = r.value
        assertEquals(RevisionGate.Result.IGNORED, r.result)
        r = set.apply(2, listOf(pendingItem("c")), emptyList()); set = r.value
        assertEquals(RevisionGate.Result.IGNORED, r.result)
        assertEquals(5, set.revision)
        assertEquals(listOf("a"), set.items.map { it.requestId })
    }

    @Test fun nextRevisionApplied() {
        var set = PendingSet()
        set = set.reset(5, listOf(pendingItem("a", createdAtMs = 1), pendingItem("b", createdAtMs = 2)))

        var r = set.apply(6, listOf(pendingItem("c", createdAtMs = 3)), listOf("a")); set = r.value
        assertEquals(RevisionGate.Result.APPLIED, r.result)
        assertEquals(6, set.revision)
        assertEquals(listOf("b", "c"), set.items.map { it.requestId })

        // An item added again under the same id replaces the old one.
        val changed = pendingItem("b", createdAtMs = 2).copy(toolInputPreview = "rm -rf build")
        r = set.apply(7, listOf(changed), emptyList()); set = r.value
        assertEquals(RevisionGate.Result.APPLIED, r.result)
        assertEquals(listOf("b", "c"), set.items.map { it.requestId })
        assertEquals("rm -rf build", set.items.firstOrNull()?.toolInputPreview)
    }

    @Test fun gapReported() {
        var set = PendingSet()
        set = set.reset(5, listOf(pendingItem("a")))

        val r = set.apply(7, listOf(pendingItem("b")), listOf("a")); set = r.value
        assertEquals(RevisionGate.Result.GAP, r.result)
        // A gap changes nothing: the caller resyncs from a snapshot.
        assertEquals(5, set.revision)
        assertEquals(listOf("a"), set.items.map { it.requestId })
    }

    @Test fun itemsSortedByCreation() {
        var set = PendingSet()
        set = set.reset(
            1,
            listOf(pendingItem("c", createdAtMs = 30), pendingItem("a", createdAtMs = 10), pendingItem("b", createdAtMs = 20)),
        )
        assertEquals(listOf("a", "b", "c"), set.items.map { it.requestId })

        val r = set.apply(2, listOf(pendingItem("d", createdAtMs = 15)), emptyList()); set = r.value
        assertEquals(RevisionGate.Result.APPLIED, r.result)
        assertEquals(listOf("a", "d", "b", "c"), set.items.map { it.requestId })
    }
}
