package com.shellx.core.agent

import com.shellx.core.text.utf8Size
import com.shellx.link.core.ChatEntry
import com.shellx.link.core.ChatEntryKind
import com.shellx.link.core.ChatEntryRole
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * One session's chat copy on the phone: entries merged by `id` (the higher `rev` wins), ordered by `seq`, history
 * pages joined or replacing a stale copy, and the newest 500 kept (PROTOCOL.md sections 4 and 6).
 */
class ChatThreadTest {
    private fun entry(seq: Long, id: String? = null, rev: Long = 1, text: String? = null): ChatEntry = ChatEntry(
        id = id ?: "e-$seq", rev = rev, seq = seq, role = ChatEntryRole.AGENT, kind = ChatEntryKind.PROSE,
        text = text ?: "entry $seq", tsMs = 1_700_000_000_000 + seq,
    )

    private fun entries(seqs: LongRange, text: String? = null): List<ChatEntry> = seqs.map { entry(it, text = text) }

    @Test fun upsertKeepsHigherRevAndSortsBySeq() {
        var thread = ChatThread()
        thread = thread.upsert(listOf(entry(3), entry(1), entry(2)))
        assertEquals(listOf(1L, 2, 3), thread.entries.map { it.seq })

        thread = thread.upsert(listOf(entry(2, rev = 2, text = "edited"), entry(5), entry(4)))

        assertEquals(listOf(1L, 2, 3, 4, 5), thread.entries.map { it.seq })
        assertEquals(listOf("e-1", "e-2", "e-3", "e-4", "e-5"), thread.entries.map { it.id }, "one entry per id")
        assertEquals("edited", thread.entries.first { it.seq == 2L }.text)
        assertEquals(2, thread.entries.first { it.seq == 2L }.rev)

        // Entries of one transcript line share a `seq` and keep the order they came in, also when one of them is
        // edited later.
        thread = thread.upsert(listOf(entry(6, id = "6a"), entry(6, id = "6b")))
        thread = thread.upsert(listOf(entry(6, id = "6a", rev = 2, text = "6a edited")))
        assertEquals(listOf("6a", "6b"), thread.entries.takeLast(2).map { it.id })
        assertEquals("6a edited", thread.entries.takeLast(2).first().text)
        assertFalse(thread.hasMore, "a live update says nothing about older entries")
    }

    @Test fun lowerRevNeverOverwrites() {
        var thread = ChatThread()
        thread = thread.applyLatestPage(listOf(entry(1), entry(2, rev = 1, text = "draft")), hasMore = false)
        // A live update edits entry 2 ...
        thread = thread.upsert(listOf(entry(2, rev = 3, text = "final")))
        // ... then a history page the Mac sent before that edit arrives late.
        thread = thread.applyLatestPage(listOf(entry(1), entry(2, rev = 2, text = "stale")), hasMore = false)
        assertEquals(listOf("entry 1", "final"), thread.entries.map { it.text })

        // An older page and a live push that repeat it change nothing either.
        thread = thread.applyOlderPage(listOf(entry(2, rev = 1, text = "older page")), hasMore = false)
        thread = thread.upsert(listOf(entry(2, rev = 3, text = "same rev, other text")))
        assertEquals(listOf("entry 1", "final"), thread.entries.map { it.text }, "equal rev keeps what is there")
        assertEquals(listOf(1L, 3), thread.entries.map { it.rev })
    }

    @Test fun latestPageWithGapReplacesStaleCache() {
        // Last week's copy holds the first ten entries; the Mac's newest page starts at 100.
        var stale = ChatThread()
        stale = stale.applyLatestPage(entries(1L..10, text = "old"), hasMore = false)
        stale = stale.applyLatestPage(entries(100L..149), hasMore = true)
        assertEquals((100L..149).toList(), stale.entries.map { it.seq }, "no hole between 10 and 100 is kept")
        assertTrue(stale.hasMore)

        // An entry pushed live while the page was on its way is newer than the page: it stays.
        var live = ChatThread()
        live = live.applyLatestPage(entries(1L..10), hasMore = false)
        live = live.upsert(listOf(entry(150)))
        live = live.applyLatestPage(entries(100L..149), hasMore = true)
        assertEquals((100L..150).toList(), live.entries.map { it.seq })
        assertTrue(live.hasMore)

        // A page that joins the copy (it starts right after it) is merged, and the copy still starts at the first
        // entry.
        var joined = ChatThread()
        joined = joined.applyLatestPage(entries(1L..60), hasMore = false)
        joined = joined.applyLatestPage(entries(61L..110), hasMore = true)
        assertEquals((1L..110).toList(), joined.entries.map { it.seq })
        assertFalse(joined.hasMore)

        // An overlapping page is merged too.
        var overlap = ChatThread()
        overlap = overlap.applyLatestPage(entries(1L..60), hasMore = true)
        overlap = overlap.applyLatestPage(entries(41L..90), hasMore = true)
        assertEquals((1L..90).toList(), overlap.entries.map { it.seq })
        assertTrue(overlap.hasMore)
    }

    @Test fun olderPagePrepends() {
        var thread = ChatThread()
        thread = thread.applyLatestPage(entries(51L..100), hasMore = true)
        assertTrue(thread.hasMore)

        thread = thread.applyOlderPage(entries(21L..50), hasMore = true)
        assertEquals((21L..100).toList(), thread.entries.map { it.seq })
        assertTrue(thread.hasMore)

        // The first page of the transcript: a line of two entries, then the rest.
        thread = thread.applyOlderPage(listOf(entry(1, id = "1a"), entry(1, id = "1b")) + entries(2L..20), hasMore = false)
        assertEquals(listOf("1a", "1b", "e-2"), thread.entries.take(3).map { it.id })
        assertEquals(101, thread.entries.size)
        assertFalse(thread.hasMore)
    }

    @Test fun threadCapKeepsNewest() {
        // 600 entries of 4 KB each (the host's cap per entry).
        val text = "ệ".repeat(1_365) + "a"
        assertEquals(ChatEntry.MAX_TEXT_BYTES, text.utf8Size)
        var thread = ChatThread()
        thread = thread.applyLatestPage(entries(1L..600, text = text), hasMore = false)

        assertEquals(500, ChatThread.MAX_ENTRIES)
        assertEquals(500, thread.entries.size)
        assertEquals(101, thread.entries.first().seq)
        assertEquals(600, thread.entries.last().seq)
        assertTrue(thread.hasMore, "the dropped entries are still on the Mac")
        assertEquals(text, thread.entries.first().text, "the phone never cuts text itself")

        // A live entry past the cap pushes the oldest out.
        thread = thread.upsert(listOf(entry(601, text = text)))
        assertEquals(500, thread.entries.size)
        assertEquals(102, thread.entries.first().seq)
        assertEquals(601, thread.entries.last().seq)

        // The copy survives a round trip through the store's JSON.
        val decoded = ChatThread.CODEC.decode(ChatThread.CODEC.encode(thread))
        assertEquals(thread, decoded)

        // A cut never splits a transcript line: paging back from its `seq` would skip its rest.
        var grouped = ChatThread()
        grouped = grouped.upsert(listOf(entry(1, id = "1a"), entry(1, id = "1b")) + entries(2L..500))
        assertEquals(499, grouped.entries.size)
        assertEquals(2, grouped.entries.first().seq)
        assertTrue(grouped.hasMore)
    }
}
