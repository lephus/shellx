package com.shellx.core.link

import com.shellx.core.testing.linkTerminal
import com.shellx.core.testing.linkWorkspace
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class WorkspaceSetTest {
    @Test fun applyNextRevision() {
        var set = WorkspaceSet()
        set = set.reset(3, listOf(linkWorkspace("a", order = 0)))

        val b = linkWorkspace("b", order = 1)
        var r = set.apply(4, listOf(b), emptyList()); set = r.value
        assertEquals(RevisionGate.Result.APPLIED, r.result)
        assertEquals(4, set.revision)
        assertEquals(listOf("ws-a", "ws-b"), set.workspaces.map { it.workspaceId })

        // An upsert replaces the workspace with the same id, with all its terminals.
        val withTerminals = linkWorkspace("a", order = 0, terminals = listOf(linkTerminal("t1"), linkTerminal("t2", order = 1)))
        r = set.apply(5, listOf(withTerminals), listOf("ws-b")); set = r.value
        assertEquals(RevisionGate.Result.APPLIED, r.result)
        assertEquals(listOf(withTerminals), set.workspaces)
        assertEquals(listOf("t1", "t2"), set.workspace("ws-a")?.terminals?.map { it.terminalId })
        assertNull(set.workspace("ws-b"))
    }

    @Test fun ignoreOldRevision() {
        var set = WorkspaceSet()
        set = set.reset(4, listOf(linkWorkspace("a")))

        var r = set.apply(4, listOf(linkWorkspace("b")), listOf("ws-a")); set = r.value
        assertEquals(RevisionGate.Result.IGNORED, r.result)
        r = set.apply(2, emptyList(), listOf("ws-a")); set = r.value
        assertEquals(RevisionGate.Result.IGNORED, r.result)
        assertEquals(4, set.revision)
        assertEquals(listOf("ws-a"), set.workspaces.map { it.workspaceId })
    }

    @Test fun gapReported() {
        var set = WorkspaceSet()
        set = set.reset(4, listOf(linkWorkspace("a")))

        var r = set.apply(6, listOf(linkWorkspace("b")), listOf("ws-a")); set = r.value
        assertEquals(RevisionGate.Result.GAP, r.result)
        assertEquals(4, set.revision)
        assertEquals(listOf("ws-a"), set.workspaces.map { it.workspaceId })
        // The change that was skipped is not mistaken for an old one afterwards.
        r = set.apply(5, listOf(linkWorkspace("b")), emptyList()); set = r.value
        assertEquals(RevisionGate.Result.APPLIED, r.result)
    }

    @Test fun sortedByOrder() {
        var set = WorkspaceSet()
        set = set.reset(1, listOf(linkWorkspace("c", order = 2), linkWorkspace("a", order = 0), linkWorkspace("b", order = 1)))
        assertEquals(listOf("ws-a", "ws-b", "ws-c"), set.workspaces.map { it.workspaceId })

        // The Mac moved "a" to the end: the upsert re-sorts the list.
        var r = set.apply(2, listOf(linkWorkspace("a", order = 5)), emptyList()); set = r.value
        assertEquals(RevisionGate.Result.APPLIED, r.result)
        assertEquals(listOf("ws-b", "ws-c", "ws-a"), set.workspaces.map { it.workspaceId })

        // The same position (two windows may each count from 0) falls back to the id.
        var tie = WorkspaceSet(1, listOf(linkWorkspace("z", order = 0), linkWorkspace("y", order = 0)))
        assertEquals(listOf("ws-y", "ws-z"), tie.workspaces.map { it.workspaceId })
        r = tie.apply(2, emptyList(), listOf("ws-y")); tie = r.value
        assertEquals(RevisionGate.Result.APPLIED, r.result)
        assertEquals(listOf("ws-z"), tie.workspaces.map { it.workspaceId })
    }

    @Test fun listAnswerReplacesRevisionAfterMacRestart() {
        var set = WorkspaceSet()
        set = set.reset(42, listOf(linkWorkspace("a")))

        // The Mac app restarted: its `workspace.list` revision starts again at 0.
        set = set.reset(0, listOf(linkWorkspace("b")))
        assertEquals(0, set.revision)
        val r = set.apply(1, listOf(linkWorkspace("c", order = 1)), emptyList()); set = r.value
        assertEquals(RevisionGate.Result.APPLIED, r.result)
        assertEquals(listOf("ws-b", "ws-c"), set.workspaces.map { it.workspaceId })
    }
}
