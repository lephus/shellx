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
import java.util.concurrent.atomic.AtomicBoolean
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
 * `SessionClosed`). A message with attachments throws `MessageUploadException(SessionClosed)` instead while its
 * attachments go up, as 3B's client does.
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

    override suspend fun chatSend(sessionId: String, text: String, attachments: List<String>): ChatSendOutcome = ask {
        if (!mac.servesSessionsAndChat) throw noChat()
        if (attachments.isNotEmpty() && !takesAttachments) throw noAttachments()
        checkText(text, withAttachments = attachments.isNotEmpty())
        mac.chat.send(sessionId, text, take(attachments))
    }

    override suspend fun uploadAttachment(
        kind: AttachmentKind,
        name: String,
        data: ByteArray,
        progress: (Int) -> Unit,
    ): String = ask {
        uploadTurn.withLock {
            if (!takesAttachments) throw noAttachments()
            refusal(kind, data.size)?.let { throw it }
            goUp(data.size, progress)
            keep(ChatAttachment(kind, name, data.copyOf()))
        }
    }

    override suspend fun chatSend(
        sessionId: String,
        text: String,
        uploading: List<ChatAttachment>,
        progress: (Int) -> Unit,
    ): ChatSendOutcome {
        if (uploading.isEmpty()) return chatSend(sessionId, text, attachments = emptyList())
        val uploaded = AtomicBoolean(false)
        val endError = {
            if (uploaded.get()) LinkClientException.SessionClosed() else MessageUploadException(LinkClientException.SessionClosed())
        }
        return ask(endError) {
            uploadTurn.withLock {
                if (!takesAttachments) throw MessageUploadException(noAttachments())
                val carried = ArrayList<ChatAttachment>(uploading.size)
                var sent = 0
                for (attachment in uploading) {
                    refusal(attachment.kind, attachment.data.size)?.let { throw MessageUploadException(it) }
                    val before = sent
                    goUp(attachment.data.size) { progress(before + it) }
                    sent += attachment.data.size
                    carried += attachment.copy(data = attachment.data.copyOf())
                }
                uploaded.set(true)
                checkText(text, withAttachments = true)
                if (carried.size > ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE) {
                    throw LinkClientException.Remote(
                        "bad_request", "at most ${ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE} attachments per message",
                    )
                }
                mac.chat.send(sessionId, text, carried)
            }
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

    /** One upload's chunks: each is one round trip, so other work may run between them; [report] gets the bytes so far. */
    private suspend fun goUp(size: Int, report: (Int) -> Unit) {
        var offset = 0
        while (offset < size) {
            offset = minOf(offset + ShellXLink.MAX_ATTACHMENT_CHUNK_BYTES, size)
            yield()
            report(offset)
        }
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
     * Counts the call, then runs [macSide] in the Mac's scope and waits for its answer or the session's end ([endError]).
     * The Mac's side never fails its coroutine (its failure travels in a `Result`), so a reporting parent scope such as
     * runTest's backgroundScope never sees a refused call.
     */
    private suspend fun <T> ask(
        endError: () -> Exception = { LinkClientException.SessionClosed() },
        macSide: suspend () -> T,
    ): T {
        currentCoroutineContext().ensureActive()
        mac.notePhoneCall()
        if (ended.isCompleted) throw endError()
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
        return (result ?: throw endError()).getOrThrow()
    }

    private companion object {
        const val MAX_HISTORY_LIMIT = 50
        const val MAX_SEND_TEXT_BYTES = 16_384
    }
}
