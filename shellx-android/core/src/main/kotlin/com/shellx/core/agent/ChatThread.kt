package com.shellx.core.agent

import com.shellx.core.storage.JsonCodec
import com.shellx.core.storage.array
import com.shellx.core.storage.bool
import com.shellx.core.storage.field
import com.shellx.core.storage.long
import com.shellx.core.storage.obj
import com.shellx.core.storage.optBool
import com.shellx.core.storage.optString
import com.shellx.core.storage.string
import com.shellx.link.core.ChatEntry
import com.shellx.link.core.ChatEntryKind
import com.shellx.link.core.ChatEntryRole
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

/**
 * One session's chat as the phone keeps it: the entries it has, ordered by `seq`, and whether the Mac has older ones
 * (PROTOCOL.md sections 4 and 6). Immutable: every change returns a new thread.
 *
 * - Entries merge by `id`: of two emissions, the one with the higher `rev` stays (ChatEntry.newer), so an equal or
 *   lower `rev` arriving later, from a history page or a live push, is dropped.
 * - Entries sharing a `seq` form one transcript line and keep the order they arrived in.
 * - Only the newest [MAX_ENTRIES] are kept, cut between transcript lines (paging back with `before_seq` would skip
 *   the rest of a split line); a cut sets [hasMore].
 * - Text is kept as the Mac sent it: the host already cut each entry to 4096 bytes.
 *
 * Normalized on construction (sorted, one entry per id, capped). Equality is over (entries, hasMore).
 */
class ChatThread private constructor(normalized: Normalized) {
    constructor(entries: List<ChatEntry> = emptyList(), hasMore: Boolean = false) :
        this(Normalized(emptyList(), hasMore).upsert(entries))

    /** Oldest first. */
    val entries: List<ChatEntry> = normalized.entries

    /** The Mac has entries older than the first one here. */
    val hasMore: Boolean = normalized.hasMore

    /** Adds new entries and keeps the newer emission of known ones. Says nothing about older entries, so [hasMore]
     *  only changes when the cap drops some. */
    fun upsert(incoming: List<ChatEntry>): ChatThread =
        if (incoming.isEmpty()) this else ChatThread(Normalized(entries, hasMore).upsert(incoming))

    /**
     * The Mac's newest page (`chat.history` without `before_seq`). It replaces the copy when it does not reach it: the
     * Mac has older entries ([hasMore]) and no entry here lies within the page or right before it, so what came
     * between is unknown. Entries newer than the page (pushed live while it travelled) stay. Otherwise the page merges
     * into the copy.
     */
    fun applyLatestPage(page: List<ChatEntry>, hasMore: Boolean): ChatThread {
        if (page.isEmpty()) {
            // An empty page: the Mac has no entries (yet). What is here stays.
            return if (entries.isEmpty()) ChatThread(Normalized(entries, hasMore)) else this
        }
        val pageFirst = page.minOf { it.seq }
        val pageLast = page.maxOf { it.seq }
        val reaches = entries.any { it.seq in (pageFirst - 1)..pageLast }
        val olderHere = entries.any { it.seq < pageFirst }
        var kept = entries
        var more = this.hasMore
        if (hasMore && olderHere && !reaches) {
            kept = entries.filter { it.seq > pageLast }
            more = true
        } else if (!olderHere) {
            // The page holds the oldest entry known: it says whether older ones exist.
            more = hasMore
        }
        return ChatThread(Normalized(kept, more).upsert(page))
    }

    /** A page older than the first entry here (`before_seq` = its `seq`). */
    fun applyOlderPage(page: List<ChatEntry>, hasMore: Boolean): ChatThread =
        ChatThread(Normalized(entries, hasMore).upsert(page))

    override fun equals(other: Any?): Boolean = other is ChatThread && entries == other.entries && hasMore == other.hasMore

    override fun hashCode(): Int = entries.hashCode() * 31 + hasMore.hashCode()

    override fun toString(): String = "ChatThread(entries=${entries.size}, hasMore=$hasMore)"

    /** Entries already sorted, unique and capped (or about to be, through [upsert]). */
    private class Normalized(val entries: List<ChatEntry>, val hasMore: Boolean) {
        fun upsert(incoming: List<ChatEntry>): Normalized {
            if (incoming.isEmpty()) return this
            val index = HashMap<String, Int>()
            entries.forEachIndexed { i, entry -> index.putIfAbsent(entry.id, i) }
            val merged = entries.toMutableList()
            for (entry in incoming) {
                val at = index[entry.id]
                if (at != null) {
                    merged[at] = ChatEntry.newer(merged[at], entry)
                } else {
                    index[entry.id] = merged.size
                    merged += entry
                }
            }
            // Sorted by `seq`; within one `seq`, by arrival (an edited entry keeps its place).
            val sorted = merged.withIndex().sortedWith(compareBy({ it.value.seq }, { it.index })).map { it.value }
            return capped(sorted)
        }

        /** Keeps the newest MAX_ENTRIES, dropping whole transcript lines; only a single line longer than the cap is cut
         *  inside. */
        private fun capped(sorted: List<ChatEntry>): Normalized {
            if (sorted.size <= MAX_ENTRIES) return Normalized(sorted, hasMore)
            var start = sorted.size - MAX_ENTRIES
            val splitSeq = sorted[start - 1].seq
            while (start < sorted.size && sorted[start].seq == splitSeq) start += 1
            if (start == sorted.size) start = sorted.size - MAX_ENTRIES
            return Normalized(sorted.drop(start), true)
        }
    }

    companion object {
        /** The most entries kept on the phone; the oldest go first. */
        const val MAX_ENTRIES = 500

        /**
         * `{"entries":[{"id","rev","seq","role","kind","text","truncated"?,"tool_name"?,"ts_ms"}],"has_more"}`, with
         * role and kind as their wire strings; decode re-normalizes.
         */
        val CODEC: JsonCodec<ChatThread> = object : JsonCodec<ChatThread> {
            override fun encode(value: ChatThread): JsonElement = buildJsonObject {
                putJsonArray("entries") {
                    for (entry in value.entries) {
                        addJsonObject {
                            put("id", entry.id)
                            put("rev", entry.rev)
                            put("seq", entry.seq)
                            put("role", entry.role.wire)
                            put("kind", entry.kind.wire)
                            put("text", entry.text)
                            entry.truncated?.let { put("truncated", it) }
                            entry.toolName?.let { put("tool_name", it) }
                            put("ts_ms", entry.tsMs)
                        }
                    }
                }
                put("has_more", value.hasMore)
            }

            override fun decode(json: JsonElement): ChatThread {
                val root = json.obj("thread")
                val entries = root.field("entries").array("entries").map { element ->
                    val entry = element.obj("entry")
                    ChatEntry(
                        id = entry.string("id"),
                        rev = entry.long("rev"),
                        seq = entry.long("seq"),
                        role = ChatEntryRole(entry.string("role")),
                        kind = ChatEntryKind(entry.string("kind")),
                        text = entry.string("text"),
                        truncated = entry.optBool("truncated"),
                        toolName = entry.optString("tool_name"),
                        tsMs = entry.long("ts_ms"),
                    )
                }
                return ChatThread(entries, root.bool("has_more"))
            }
        }
    }
}
