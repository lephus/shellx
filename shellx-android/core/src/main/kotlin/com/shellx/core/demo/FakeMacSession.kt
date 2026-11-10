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
import com.shellx.link.core.TerminalCreated
import com.shellx.link.core.TerminalInputCheck
import com.shellx.link.core.TerminalInputUnit
import com.shellx.link.core.TerminalPushQueue
import com.shellx.link.core.TerminalViewOpenOutcome
import com.shellx.link.core.TerminalViewPush
import com.shellx.link.core.WorkspaceChange
import com.shellx.link.core.WorkspaceControlOutcome
import com.shellx.link.core.WorkspaceCreated
import com.shellx.link.core.WorkspaceList
import kotlin.coroutines.cancellation.CancellationException
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
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
 *
 * Terminal views (plan 3G Task 5): there is no `LinkHost` on Android, so this session is the host the phone talks to,
 * with LinkHost.swift's checks (the feature first, then sizes of at least 1, clamped into `TERMINAL_COLUMNS` and
 * `TERMINAL_ROWS`) before [FakeMacTerminals] acts. The phone's side is 3B's client's (review B1 m4):
 * - Each terminal message goes into the session's host inbox, which the Mac takes in order, one at a time, as LinkHost
 *   handles each message inline: a held open holds the messages sent after it, on the Mac's side.
 * - Input, resize, resync and close return once sent; an input `TerminalInputCheck` refuses throws first: nothing was
 *   sent. Open waits for its answer or the session's end.
 * - An open the phone stopped waiting for (cancelled, or the session ended) still opens the view on the Mac, but its
 *   `Opened` is not announced, as 3B's client announces none for a waiter that is gone.
 * - The terminal pushes go through a [TerminalPushQueue], as 3B's client's do, so a terminal flood is bounded the same
 *   way; the queue closes when the session ends.
 */
internal class FakeMacSession(private val mac: FakeMac, override val hostFeatures: Set<String>) : LinkSession {
    val pendingQueue = Channel<PendingChange>(Channel.UNLIMITED)
    val sessionQueue = Channel<SessionChange>(Channel.UNLIMITED)
    val workspaceQueue = Channel<WorkspaceChange>(Channel.UNLIMITED)
    val chatQueue = Channel<ChatPush>(Channel.UNLIMITED)
    private val ended = CompletableDeferred<Unit>()
    private val terminalQueue = TerminalPushQueue()

    /** The terminal messages the phone sent, which the Mac takes in order ([hostLoop]); closed when the session ends. */
    private val hostInbox = Channel<suspend () -> Unit>(Channel.UNLIMITED)

    /** Takes [hostInbox] in the Mac's scope; started by the first terminal message. Guarded by [hostInbox]. */
    private var hostLoop: Job? = null

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
    override val terminalPushes: Flow<TerminalViewPush> = terminalQueue.pushes

    /** True once the session ended (either side). */
    val hasEnded: Boolean get() = ended.isCompleted

    /** The Mac's side: a push for this session's phone. */
    fun offerTerminal(push: TerminalViewPush) = terminalQueue.offer(push)

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

    override suspend fun openTerminalView(terminalId: String, cols: Int, rows: Int): TerminalViewOpenOutcome {
        currentCoroutineContext().ensureActive()
        mac.notePhoneCall()
        if (ended.isCompleted) throw LinkClientException.SessionClosed()
        val waiter = OpenWaiter()
        val answer = CompletableDeferred<Result<TerminalViewOpenOutcome>>()
        toHost {
            val result = try {
                Result.success(openOnHost(terminalId, cols, rows, waiter))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Result.failure(e)
            }
            answer.complete(result)
        }
        val result = try {
            select<Result<TerminalViewOpenOutcome>?> {
                answer.onAwait { it }
                ended.onAwait { null }
            }
        } catch (e: CancellationException) {
            waiter.leave()
            throw e
        }
        if (result == null) {
            waiter.leave()
            throw LinkClientException.SessionClosed()
        }
        return result.getOrThrow()
    }

    override suspend fun closeTerminalView(terminalId: String) = post {
        if (viewsTerminals()) mac.terminals.close(this, terminalId)
    }

    override suspend fun sendTerminalInput(terminalId: String, units: List<TerminalInputUnit>) {
        TerminalInputCheck.check(units)
        post { if (viewsTerminals()) mac.terminals.input(this, terminalId, units) }
    }

    override suspend fun resizeTerminalView(terminalId: String, cols: Int, rows: Int) = post {
        // The host answers sizes below 1 with an error frame that names no call: the phone sees nothing.
        if (viewsTerminals() && cols >= 1 && rows >= 1) {
            mac.terminals.resize(this, terminalId, cols.coerceIn(ShellXLink.TERMINAL_COLUMNS), rows.coerceIn(ShellXLink.TERMINAL_ROWS))
        }
    }

    override suspend fun resyncTerminalView(terminalId: String) = post {
        if (viewsTerminals()) mac.terminals.resync(this, terminalId)
    }

    override suspend fun createTerminal(workspaceId: String): TerminalCreated = ask {
        if (!(mac.servesWorkspaces && mac.acceptsTerminalCreate)) {
            throw LinkClientException.Remote("unsupported", "this host takes no terminal creation")
        }
        val (outcome, terminalId) = mac.terminals.create(workspaceId)
        // The new id goes out only with OK.
        TerminalCreated(outcome, terminalId.takeIf { outcome == WorkspaceControlOutcome.OK })
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
        // The view goes with its session; its pushes complete once taken. The Mac reads no more of its messages.
        hostInbox.close()
        mac.terminals.sessionEnded(this)
        terminalQueue.close()
    }

    override fun toString(): String = "FakeMacSession(features=$hostFeatures)"

    private fun takesWorkspaceControl() = mac.servesWorkspaces && mac.acceptsWorkspaceControl

    private fun viewsTerminals() = mac.servesWorkspaces && mac.servesTerminalViews

    /** `terminal.view.open` on the Mac's side, in the inbox's order. */
    private suspend fun openOnHost(terminalId: String, cols: Int, rows: Int, waiter: OpenWaiter): TerminalViewOpenOutcome {
        if (!viewsTerminals()) throw LinkClientException.Remote("unsupported", "this host offers no terminal views")
        if (cols < 1 || rows < 1) throw LinkClientException.Remote("bad_request", "cols and rows must be at least 1")
        return mac.terminals.open(
            this, terminalId, cols.coerceIn(ShellXLink.TERMINAL_COLUMNS), rows.coerceIn(ShellXLink.TERMINAL_ROWS),
            announce = waiter::answer,
        )
    }

    /** A terminal message without an answer: counted, sent to the Mac's inbox, and back at once (3B's `post`). */
    private suspend fun post(onHost: suspend () -> Unit) {
        currentCoroutineContext().ensureActive()
        mac.notePhoneCall()
        if (ended.isCompleted) throw LinkClientException.SessionClosed()
        toHost(onHost)
    }

    /** Puts [onHost] in the Mac's inbox; the first message starts the Mac's loop over it. */
    private fun toHost(onHost: suspend () -> Unit) {
        synchronized(hostInbox) {
            if (hostLoop == null) hostLoop = mac.scope.launch { takeInbox() }
        }
        hostInbox.trySend(onHost)
    }

    /** The Mac's read loop for terminal messages: one at a time, in order, until the session ends. */
    private suspend fun takeInbox() {
        for (onHost in hostInbox) {
            if (ended.isCompleted) return
            try {
                onHost()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // The Mac's side of one message failed; the session goes on, as the host's loop does.
            }
        }
    }

    /** Whether the phone still waits for an open's answer, decided once: the Mac answers, or the phone leaves. */
    private class OpenWaiter {
        private val state = AtomicInteger(WAITING)

        /** The Mac answers `ok`: true when the phone still waits, so its `Opened` is announced. */
        fun answer(): Boolean = state.compareAndSet(WAITING, ANSWERED)

        /** The phone stopped waiting (cancelled, or the session ended). */
        fun leave() {
            state.compareAndSet(WAITING, LEFT)
        }

        private companion object {
            const val WAITING = 0
            const val ANSWERED = 1
            const val LEFT = 2
        }
    }

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
