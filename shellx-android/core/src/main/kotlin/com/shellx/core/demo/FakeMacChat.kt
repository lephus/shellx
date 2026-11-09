package com.shellx.core.demo

import com.shellx.link.core.ChatAttachment
import com.shellx.link.core.ChatEntry
import com.shellx.link.core.ChatHistoryPage
import com.shellx.link.core.ChatInterruptOutcome
import com.shellx.link.core.ChatPush
import com.shellx.link.core.ChatSendOutcome

/**
 * [FakeMac]'s chat (FakeMacChat.swift). A session has a transcript once [setHistory], [push] or [reset] named it;
 * others answer `not_found`. Every member takes the Mac's lock. A Mac that serves no chat ([pushes] false) pushes
 * nothing.
 */
internal class FakeMacChat(private val live: FakeMacLive, private val pushes: Boolean) {
    private val lock = live.lock

    /** Entries by session, then by [ChatEntry.id] (upserts). */
    private val transcripts = HashMap<String, LinkedHashMap<String, ChatEntry>>()
    private var sendOutcome: ChatSendOutcome? = null
    private var interruptOutcome: ChatInterruptOutcome? = null
    private val sends = ArrayList<FakeMac.SentText>()
    private val attachments = ArrayList<ChatAttachment>()
    private val interruptCalls = ArrayList<FakeMac.Interrupt>()
    private val historyCalls = ArrayList<FakeMac.HistoryRequest>()

    /** Chat calls (history, send, interrupt) are recorded, then wait while it holds. */
    val hold = FakeMacHold(lock)

    val sentTexts: List<FakeMac.SentText> get() = synchronized(lock) { sends.toList() }
    val receivedAttachments: List<ChatAttachment> get() = synchronized(lock) { attachments.toList() }
    val interrupts: List<FakeMac.Interrupt> get() = synchronized(lock) { interruptCalls.toList() }
    val historyRequests: List<FakeMac.HistoryRequest> get() = synchronized(lock) { historyCalls.toList() }

    fun setHistory(sessionId: String, entries: List<ChatEntry>) {
        synchronized(lock) { transcripts[sessionId] = byId(entries) }
    }

    /** Upserts [entries] into the transcript and pushes them to every live session. */
    fun push(sessionId: String, entries: List<ChatEntry>) {
        synchronized(lock) {
            val transcript = transcripts.getOrPut(sessionId) { LinkedHashMap() }
            for (entry in entries) transcript[entry.id] = entry
            broadcastLocked(ChatPush.Upsert(sessionId, entries))
        }
    }

    /** Replaces the transcript, as when the Mac reloads it, and pushes `chat.reset`, in order with the other pushes. */
    fun reset(sessionId: String, entries: List<ChatEntry>) {
        synchronized(lock) {
            transcripts[sessionId] = byId(entries)
            broadcastLocked(ChatPush.Reset(sessionId))
        }
    }

    fun setSendOutcome(outcome: ChatSendOutcome?) {
        synchronized(lock) { sendOutcome = outcome }
    }

    fun setInterruptOutcome(outcome: ChatInterruptOutcome?) {
        synchronized(lock) { interruptOutcome = outcome }
    }

    /**
     * Answers from the transcript as it is when the call arrives, like a Mac reading its file; a held call delivers
     * that answer later (after a reset, the old transcript's page). Null for a session without a transcript.
     */
    suspend fun history(sessionId: String, beforeSeq: Long?, limit: Int): ChatHistoryPage? {
        val page = synchronized(lock) {
            historyCalls += FakeMac.HistoryRequest(sessionId, beforeSeq, limit)
            transcripts[sessionId]?.values?.sortedBy { it.seq }?.let { all ->
                val older = if (beforeSeq == null) all else all.filter { it.seq < beforeSeq }
                ChatHistoryPage(older.takeLast(limit), older.size > limit)
            }
        }
        hold.pass()
        return page
    }

    /** A message, with the attachments it carries (recorded in order, its text in [sentTexts]). */
    suspend fun send(sessionId: String, text: String, carried: List<ChatAttachment>): ChatSendOutcome {
        synchronized(lock) {
            attachments += carried
            sends += FakeMac.SentText(sessionId, text)
        }
        hold.pass()
        return synchronized(lock) {
            sendOutcome ?: if (transcripts.containsKey(sessionId)) ChatSendOutcome.SUBMITTED else ChatSendOutcome.NOT_FOUND
        }
    }

    suspend fun interrupt(sessionId: String, hard: Boolean): ChatInterruptOutcome {
        synchronized(lock) { interruptCalls += FakeMac.Interrupt(sessionId, hard) }
        hold.pass()
        return synchronized(lock) {
            interruptOutcome
                ?: if (transcripts.containsKey(sessionId)) ChatInterruptOutcome.SENT else ChatInterruptOutcome.NOT_FOUND
        }
    }

    private fun broadcastLocked(push: ChatPush) {
        if (!pushes) return
        live.broadcastLocked { it.chatQueue.trySend(push) }
    }

    private fun byId(entries: List<ChatEntry>): LinkedHashMap<String, ChatEntry> =
        LinkedHashMap<String, ChatEntry>().also { map -> for (entry in entries) map[entry.id] = entry }
}
