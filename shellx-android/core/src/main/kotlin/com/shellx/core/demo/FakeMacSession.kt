package com.shellx.core.demo

import com.shellx.core.text.utf8Size
import com.shellx.link.core.AttachmentKind
import com.shellx.link.core.ChatAttachment
import com.shellx.link.core.ChatHistoryPage
import com.shellx.link.core.ChatInterruptOutcome
import com.shellx.link.core.ChatPush
import com.shellx.link.core.ChatSendOutcome
import com.shellx.link.core.LinkClientException
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.LinkSession
import com.shellx.link.core.MessageUploadException
import com.shellx.link.core.PendingChange
import com.shellx.link.core.PendingSnapshot
import com.shellx.link.core.ReplyOutcome
import com.shellx.link.core.SessionChange
import com.shellx.link.core.SessionList
import com.shellx.link.core.ShellXLink
import com.shellx.link.core.WorkspaceChange
import com.shellx.link.core.WorkspaceControlOutcome
import com.shellx.link.core.WorkspaceCreated
import com.shellx.link.core.WorkspaceList
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.yield

/**
 * One phone's session with a [FakeMac], with the host rules of LinkHost.swift. Every call counts in
 * [FakeMac.phoneCallCount]; a call on an ended session throws `SessionClosed`. Otherwise the Mac's side runs in the
 * Mac's scope, and the phone waits for its answer or for the session's end, whichever comes first (the end throws
 * `SessionClosed`). No call times out.
 *
 * Uploads are the exception, as in 3B's client: the phone drives them chunk by chunk in the caller's coroutine, so a
 * cancelled caller or an ended session stops them, nothing is kept, and a message whose attachments did not all go up
 * is never sent (`MessageUploadException`).
 */
internal class FakeMacSession(private val mac: FakeMac, override val hostFeatures: Set<String>) : LinkSession {
    val pendingQueue = Channel<PendingChange>(Channel.UNLIMITED)
    val sessionQueue = Channel<SessionChange>(Channel.UNLIMITED)
    val workspaceQueue = Channel<WorkspaceChange>(Channel.UNLIMITED)
    val chatQueue = Channel<ChatPush>(Channel.UNLIMITED)
    private val ended = CompletableDeferred<Unit>()

    /** One upload at a time, a message's uploads and its send together (3B's upload turn). */
    private val uploadTurn = Mutex()

    /** Finished uploads no message has named yet, oldest first, by id. */
    private val uploads = LinkedHashMap<String, ChatAttachment>()
    private var uploadCount = 0

    private val takesAttachments: Boolean get() = mac.servesSessionsAndChat && mac.acceptsAttachments

    override val changes: Flow<PendingChange> = pendingQueue.receiveAsFlow()
    override val sessionChanges: Flow<SessionChange> = sessionQueue.receiveAsFlow()
    override val workspaceChanges: Flow<WorkspaceChange> = workspaceQueue.receiveAsFlow()
    override val chatEntries: Flow<ChatPush> = chatQueue.receiveAsFlow()

    override suspend fun snapshot(): PendingSnapshot = ask { mac.feed.snapshot() }

    override suspend fun reply(requestId: String, decision: LinkDecision): ReplyOutcome =
        ask { mac.feed.reply(requestId, decision) }

    override suspend fun sessions(): SessionList = ask {
        if (!mac.servesSessionsAndChat) throw LinkClientException.Remote("unsupported", "this host has no agent sessions")
        mac.sessionSource.list()
    }

    override suspend fun chatHistory(sessionId: String, beforeSeq: Long?, limit: Int): ChatHistoryPage = ask {
        if (!mac.servesSessionsAndChat) throw noChat()
        if (limit !in 1..MAX_HISTORY_LIMIT) {
            throw LinkClientException.Remote("bad_request", "limit must be 1 to $MAX_HISTORY_LIMIT")
        }
        mac.chat.history(sessionId, beforeSeq, limit) ?: throw LinkClientException.Remote("not_found", "no such session")
    }

    override suspend fun chatSend(sessionId: String, text: String, attachments: List<String>): ChatSendOutcome =
        send(sessionId, text, attachments, counted = true)

    /**
     * The phone drives the upload, as 3B's client does: each chunk is one round trip in the caller's coroutine, so a
     * cancelled caller stops it and an ended session fails the next chunk. Only a whole upload is kept.
     */
    override suspend fun uploadAttachment(
        kind: AttachmentKind,
        name: String,
        data: ByteArray,
        progress: (Int) -> Unit,
    ): String {
        currentCoroutineContext().ensureActive()
        mac.notePhoneCall()
        return withUploadTurn {
            if (ended.isCompleted) throw LinkClientException.SessionClosed()
            upload(kind, name, data, progress)
        }
    }

    /**
     * Uploads [uploading] in order on the phone's side, then sends `chat.send` with their ids, holding the upload turn
     * until that send is answered. An upload that fails, or a session that ends while the attachments go up, throws
     * MessageUploadException: the send never left, so nothing is typed. Once the attachments are up, the send goes to the
     * Mac like any call: an end while waiting throws SessionClosed, and a held send still acts once released.
     */
    override suspend fun chatSend(
        sessionId: String,
        text: String,
        uploading: List<ChatAttachment>,
        progress: (Int) -> Unit,
    ): ChatSendOutcome {
        if (uploading.isEmpty()) return chatSend(sessionId, text, attachments = emptyList())
        currentCoroutineContext().ensureActive()
        mac.notePhoneCall()
        return withUploadTurn {
            if (ended.isCompleted) throw MessageUploadException(LinkClientException.SessionClosed())
            val ids = ArrayList<String>(uploading.size)
            var sent = 0
            for (attachment in uploading) {
                val before = sent
                ids += try {
                    upload(attachment.kind, attachment.name, attachment.data) { progress(before + it) }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    throw MessageUploadException(e)
                }
                sent += attachment.data.size
            }
            send(sessionId, text, ids, counted = false)
        }
    }

    override suspend fun chatInterrupt(sessionId: String, hard: Boolean): ChatInterruptOutcome = ask {
        if (!mac.servesSessionsAndChat) throw noChat()
        mac.chat.interrupt(sessionId, hard)
    }

    override suspend fun workspaces(): WorkspaceList = ask {
        if (!mac.servesWorkspaces) throw LinkClientException.Remote("unsupported", "this host lists no workspaces")
        mac.workspaceSource.list()
    }

    override suspend fun createWorkspace(): WorkspaceCreated = ask {
        if (!takesWorkspaceControl()) throw noWorkspaceControl()
        mac.workspaceSource.create()
    }

    override suspend fun renameWorkspace(workspaceId: String, title: String): WorkspaceControlOutcome = ask {
        if (!takesWorkspaceControl()) throw noWorkspaceControl()
        if (title.utf8Size > ShellXLink.MAX_WORKSPACE_TITLE_BYTES) {
            throw LinkClientException.Remote(
                "bad_request", "title must be at most ${ShellXLink.MAX_WORKSPACE_TITLE_BYTES} bytes",
            )
        }
        mac.workspaceSource.rename(workspaceId, title)
    }

    override suspend fun closeWorkspace(workspaceId: String): WorkspaceControlOutcome = ask {
        if (!takesWorkspaceControl()) throw noWorkspaceControl()
        mac.workspaceSource.close(workspaceId)
    }

    override suspend fun closeAgent(sessionId: String): WorkspaceControlOutcome = ask {
        if (!(mac.servesSessionsAndChat && mac.acceptsAgentClose)) {
            throw LinkClientException.Remote("unsupported", "this host takes no agent control")
        }
        mac.workspaceSource.closeAgent(sessionId)
    }

    override suspend fun closeTerminal(workspaceId: String, terminalId: String): WorkspaceControlOutcome = ask {
        if (!(mac.servesWorkspaces && mac.acceptsTerminalClose)) {
            throw LinkClientException.Remote("unsupported", "this host takes no terminal control")
        }
        mac.workspaceSource.closeTerminal(workspaceId, terminalId)
    }

    /** Ends the session from the phone's side. Idempotent. */
    override fun close() {
        end()
    }

    /** Ends the session (either side): pending calls throw SessionClosed and every Flow completes. Idempotent. */
    fun end() {
        mac.ended(this)
        if (!ended.complete(Unit)) return
        // The Mac drops a session's unsent uploads with it.
        synchronized(uploads) { uploads.clear() }
        pendingQueue.close()
        sessionQueue.close()
        workspaceQueue.close()
        chatQueue.close()
    }

    override fun toString(): String = "FakeMacSession(features=$hostFeatures)"

    private fun takesWorkspaceControl() = mac.servesWorkspaces && mac.acceptsWorkspaceControl

    private fun noChat() = LinkClientException.Remote("unsupported", "this host has no chat")

    private fun noAttachments() = LinkClientException.Remote("unsupported", "this host takes no attachments")

    private fun noWorkspaceControl() = LinkClientException.Remote("unsupported", "this host takes no workspace control")

    /** A message of only attachments may have no text (PROTOCOL.md section 4). */
    private fun checkText(text: String, withAttachments: Boolean) {
        val least = if (withAttachments) 0 else 1
        if (text.utf8Size !in least..MAX_SEND_TEXT_BYTES) {
            throw LinkClientException.Remote("bad_request", "text must be $least to $MAX_SEND_TEXT_BYTES bytes")
        }
    }

    /** Why the Mac refuses to begin an upload (AttachmentUploads.swift), or null. */
    private fun refusal(kind: AttachmentKind, size: Int): LinkClientException.Remote? = when {
        kind != AttachmentKind.IMAGE && kind != AttachmentKind.FILE ->
            LinkClientException.Remote("bad_request", "this host takes only image and file attachments")
        size < 1 -> LinkClientException.Remote("bad_request", "size must be at least 1")
        size > ShellXLink.MAX_ATTACHMENT_BYTES ->
            LinkClientException.Remote("too_large", "size is above ${ShellXLink.MAX_ATTACHMENT_BYTES} bytes")
        else -> null
    }

    /** `chat.send` with attachment ids, as the Mac checks and takes it. [counted] is false inside a message upload. */
    private suspend fun send(sessionId: String, text: String, ids: List<String>, counted: Boolean): ChatSendOutcome =
        ask(counted = counted) {
            if (!mac.servesSessionsAndChat) throw noChat()
            if (ids.isNotEmpty() && !takesAttachments) throw noAttachments()
            checkText(text, withAttachments = ids.isNotEmpty())
            mac.chat.send(sessionId, text, take(ids))
        }

    /** Runs [block] holding the upload turn; a caller cancelled while waiting for it, or holding it, gives it up. */
    private suspend fun <T> withUploadTurn(block: suspend () -> T): T = uploadTurn.withLock {
        // Mutex.lock() takes a free lock without checking for cancellation.
        currentCoroutineContext().ensureActive()
        block()
    }

    /**
     * One upload, on the phone's side: the Mac's refusal of its kind or size, then one round trip per chunk of at most
     * `ShellXLink.MAX_ATTACHMENT_CHUNK_BYTES`, then the Mac keeps it. [report] gets the bytes the Mac took after each
     * chunk. A session that ends before a chunk's answer fails the upload with SessionClosed; nothing is kept.
     */
    private suspend fun upload(kind: AttachmentKind, name: String, data: ByteArray, report: (Int) -> Unit): String {
        if (!takesAttachments) throw noAttachments()
        refusal(kind, data.size)?.let { throw it }
        val copy = data.copyOf()
        var offset = 0
        while (offset < copy.size) {
            if (ended.isCompleted) throw LinkClientException.SessionClosed()
            offset = minOf(offset + ShellXLink.MAX_ATTACHMENT_CHUNK_BYTES, copy.size)
            // The chunk's round trip: other work may run meanwhile, and a cancelled caller stops here.
            yield()
            if (ended.isCompleted) throw LinkClientException.SessionClosed()
            report(offset)
        }
        if (ended.isCompleted) throw LinkClientException.SessionClosed()
        return keep(ChatAttachment(kind, name, copy))
    }

    /** Holds a finished upload until a message names it; the oldest goes when [ShellXLink.MAX_PENDING_UPLOADS] are held. */
    private fun keep(attachment: ChatAttachment): String = synchronized(uploads) {
        while (uploads.size >= ShellXLink.MAX_PENDING_UPLOADS) uploads.remove(uploads.keys.first())
        uploadCount += 1
        "U$uploadCount".also { uploads[it] = attachment }
    }

    /** The uploads a message names, taken out (AttachmentUploads.take): all of them, or a `bad_request` and none. */
    private fun take(ids: List<String>): List<ChatAttachment> = synchronized(uploads) {
        if (ids.size > ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE) {
            throw LinkClientException.Remote(
                "bad_request", "at most ${ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE} attachments per message",
            )
        }
        if (ids.toSet().size != ids.size) throw LinkClientException.Remote("bad_request", "an attachment is named twice")
        val taken = ids.map {
            uploads[it] ?: throw LinkClientException.Remote("bad_request", "an attachment is not held, or not finished")
        }
        for (id in ids) uploads.remove(id)
        taken
    }

    /**
     * Counts the call (unless [counted] is false), then runs [macSide] in the Mac's scope and waits for its answer or the
     * session's end (SessionClosed).
     * The Mac's side never fails its coroutine (its failure travels in a `Result`), so a reporting parent scope such as
     * runTest's backgroundScope never sees a refused call.
     */
    private suspend fun <T> ask(counted: Boolean = true, macSide: suspend () -> T): T {
        currentCoroutineContext().ensureActive()
        if (counted) mac.notePhoneCall()
        if (ended.isCompleted) throw LinkClientException.SessionClosed()
        val answer = mac.scope.async {
            try {
                Result.success(macSide())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                Result.failure(e)
            }
        }
        val result = try {
            select<Result<T>?> {
                answer.onAwait { it }
                ended.onAwait { null }
            }
        } catch (e: CancellationException) {
            // The caller's own cancellation propagates; the Mac's scope ending is the session's end.
            currentCoroutineContext().ensureActive()
            null
        }
        return (result ?: throw LinkClientException.SessionClosed()).getOrThrow()
    }

    private companion object {
        const val MAX_HISTORY_LIMIT = 50
        const val MAX_SEND_TEXT_BYTES = 16_384
    }
}
