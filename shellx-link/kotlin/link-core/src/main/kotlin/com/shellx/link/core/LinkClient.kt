package com.shellx.link.core

import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The phone side of ShellX Link: one established session with one host. Create it with [connect].
 *
 * Nothing closes a client that is dropped: callers must [close] it.
 */
class LinkClient private constructor(
    private val channel: SecureChannel,
    override val hostFeatures: Set<String>,
    private val timings: LinkTimings,
    private val scope: CoroutineScope,
    private val watchdog: Job,
) : LinkSession {
    /**
     * Guards [nextCallNumber], [waiters], [openingViews] and [endError]. Never held across a suspension or a deferred
     * completion.
     */
    private val lock = Any()
    private var nextCallNumber = 0L

    /** The calls waiting for their answer, by `call_id`. An answer whose id is not here is dropped. */
    private val waiters = HashMap<String, CompletableDeferred<LinkMessage>>()
    private var endError: LinkClientException? = null

    /** The `terminal_id` of each `terminal.view.open` still waiting for its answer, by `call_id`. */
    private val openingViews = HashMap<String, String>()

    private val changeQueue = Channel<PendingChange>(Channel.UNLIMITED)
    private val sessionQueue = Channel<SessionChange>(Channel.UNLIMITED)
    private val workspaceQueue = Channel<WorkspaceChange>(Channel.UNLIMITED)
    private val chatQueue = Channel<ChatPush>(Channel.UNLIMITED)
    private val terminalQueue = Channel<TerminalViewPush>(Channel.UNLIMITED)

    override val changes: Flow<PendingChange> = changeQueue.receiveAsFlow()
    override val sessionChanges: Flow<SessionChange> = sessionQueue.receiveAsFlow()
    override val workspaceChanges: Flow<WorkspaceChange> = workspaceQueue.receiveAsFlow()
    override val chatEntries: Flow<ChatPush> = chatQueue.receiveAsFlow()
    override val terminalPushes: Flow<TerminalViewPush> = terminalQueue.receiveAsFlow()

    /**
     * The upload turn, a fair (FIFO) lock. An upload holds it from `attach.begin` to its end, and a message from its
     * first upload until its `chat.send` is answered: the host drops an unfinished upload at every `attach.begin`, and
     * the oldest finished one when it holds five (PROTOCOL.md section 5).
     */
    private val uploadTurn = Mutex()
    private val waitingForTurn = AtomicInteger(0)

    private val pinger: Job = scope.launch { runPings(channel, timings.pingInterval) }

    init {
        // Last, so every property above is set when the reader starts.
        scope.launch {
            try {
                readLoop()
            } finally {
                // A reader that stops for any reason ends the session; a no-op when it already ended.
                end(LinkClientException.SessionClosed())
            }
        }
    }

    /** How many calls wait for their answer. For tests. */
    internal val pendingCalls: Int get() = synchronized(lock) { waiters.size }

    /** How many uploads and messages wait for the upload turn behind the one holding it. For tests. */
    internal val uploadsWaiting: Int get() = waitingForTurn.get()

    override suspend fun snapshot(): PendingSnapshot =
        ask<LinkMessage.Snapshot> { LinkMessage.SnapshotGet(it) }.let { PendingSnapshot(it.revision, it.pending) }

    override suspend fun reply(requestId: String, decision: LinkDecision): ReplyOutcome =
        ask<LinkMessage.ReplyResult> { LinkMessage.Reply(it, requestId, decision) }.outcome

    override suspend fun sessions(): SessionList =
        ask<LinkMessage.Sessions> { LinkMessage.SessionsGet(it) }.let { SessionList(it.revision, it.sessions) }

    override suspend fun chatHistory(sessionId: String, beforeSeq: Long?, limit: Int): ChatHistoryPage =
        ask<LinkMessage.ChatHistory> { LinkMessage.ChatHistoryGet(it, sessionId, beforeSeq, limit) }
            .let { ChatHistoryPage(it.entries, it.hasMore) }

    override suspend fun chatSend(sessionId: String, text: String, attachments: List<String>): ChatSendOutcome =
        ask<LinkMessage.ChatSendResult> { LinkMessage.ChatSend(it, sessionId, text, attachments) }.outcome

    override suspend fun uploadAttachment(
        kind: AttachmentKind,
        name: String,
        data: ByteArray,
        progress: (Int) -> Unit,
    ): String = withUploadTurn {
        endErrorOrNull()?.let { throw it }
        upload(kind, name, copyOffCaller(data), progress)
    }

    override suspend fun chatSend(
        sessionId: String,
        text: String,
        uploading: List<ChatAttachment>,
        progress: (Int) -> Unit,
    ): ChatSendOutcome = withUploadTurn {
        endErrorOrNull()?.let { throw MessageUploadException(it) }
        val ids = ArrayList<String>(uploading.size)
        var sent = 0
        for (attachment in uploading) {
            val before = sent
            val data = copyOffCaller(attachment.data)
            ids += try {
                upload(attachment.kind, attachment.name, data) { progress(before + it) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                throw MessageUploadException(e)
            }
            sent += data.size
        }
        chatSend(sessionId, text, ids)
    }

    override suspend fun chatInterrupt(sessionId: String, hard: Boolean): ChatInterruptOutcome =
        ask<LinkMessage.ChatInterruptResult> { LinkMessage.ChatInterrupt(it, sessionId, hard) }.outcome

    override suspend fun workspaces(): WorkspaceList =
        ask<LinkMessage.Workspaces> { LinkMessage.WorkspacesGet(it) }.let { WorkspaceList(it.revision, it.workspaces) }

    override suspend fun createWorkspace(): WorkspaceCreated =
        ask<LinkMessage.WorkspaceCreateResult> { LinkMessage.WorkspaceCreate(it) }
            .let { WorkspaceCreated(it.outcome, it.workspaceId) }

    override suspend fun renameWorkspace(workspaceId: String, title: String): WorkspaceControlOutcome =
        ask<LinkMessage.WorkspaceRenameResult> { LinkMessage.WorkspaceRename(it, workspaceId, title) }.outcome

    override suspend fun closeWorkspace(workspaceId: String): WorkspaceControlOutcome =
        ask<LinkMessage.WorkspaceCloseResult> { LinkMessage.WorkspaceClose(it, workspaceId) }.outcome

    override suspend fun closeAgent(sessionId: String): WorkspaceControlOutcome =
        ask<LinkMessage.AgentCloseResult> { LinkMessage.AgentClose(it, sessionId) }.outcome

    override suspend fun closeTerminal(workspaceId: String, terminalId: String): WorkspaceControlOutcome =
        ask<LinkMessage.TerminalCloseResult> { LinkMessage.TerminalClose(it, workspaceId, terminalId) }.outcome

    override suspend fun openTerminalView(terminalId: String, cols: Int, rows: Int): TerminalViewOpenOutcome =
        (call(openingView = terminalId) { LinkMessage.TerminalViewOpen(it, terminalId, cols, rows) } as? LinkMessage.TerminalViewOpenResult)
            ?.outcome ?: throw LinkClientException.UnexpectedAnswer()

    override suspend fun closeTerminalView(terminalId: String) = post(LinkMessage.TerminalViewClose(terminalId))

    override suspend fun sendTerminalInput(terminalId: String, units: List<TerminalInputUnit>) {
        TerminalInputCheck.check(units)
        post(LinkMessage.TerminalViewInput(terminalId, units))
    }

    override suspend fun resizeTerminalView(terminalId: String, cols: Int, rows: Int) =
        post(LinkMessage.TerminalViewResize(terminalId, cols, rows))

    override suspend fun resyncTerminalView(terminalId: String) = post(LinkMessage.TerminalViewResync(terminalId))

    override suspend fun createTerminal(workspaceId: String): TerminalCreated =
        ask<LinkMessage.TerminalCreateResult> { LinkMessage.TerminalCreate(it, workspaceId) }
            .let { TerminalCreated(it.outcome, it.terminalId) }

    override fun close() = end(LinkClientException.SessionClosed())

    override fun toString(): String = "LinkClient(features=$hostFeatures)"

    /** [call], requiring an answer of type [T]. */
    private suspend inline fun <reified T : LinkMessage> ask(noinline make: (callId: String) -> LinkMessage): T =
        call(make = make) as? T ?: throw LinkClientException.UnexpectedAnswer()

    /**
     * Sends `make(callId)` and returns the one answer that carries `callId`. [openingView] is the terminal of a
     * `terminal.view.open`: recorded with the waiter, and dropped with it, so only an `ok` this call still waits for
     * is announced as [TerminalViewPush.Opened].
     */
    internal suspend fun call(openingView: String? = null, make: (callId: String) -> LinkMessage): LinkMessage {
        // As Swift's checkOpen(): a caller that is already cancelled sends nothing. The send lock's free fast path
        // and the NonCancellable send would otherwise carry the request out.
        currentCoroutineContext().ensureActive()
        val answer = CompletableDeferred<LinkMessage>()
        val callId = synchronized(lock) {
            endError?.let { throw it.fresh() }
            nextCallNumber += 1
            "c$nextCallNumber".also {
                waiters[it] = answer
                if (openingView != null) openingViews[it] = openingView
            }
        }
        try {
            val request = make(callId)
            try {
                channel.send(request)
            } catch (e: CancellationException) {
                throw e
            } catch (e: LinkCodecException) {
                throw e
            } catch (_: Exception) {
                throw synchronized(lock) { endError?.fresh() } ?: LinkClientException.SessionClosed()
            }
            withTimeoutOrNull(timings.requestTimeout) { answer.await() }?.let { return it }
            // The reader (or the session's end) may have taken this call's waiter just as the timeout fired. Its
            // answer is then this call's result: an `ok` it already announced as Opened is never reported as a timeout.
            if (synchronized(lock) { waiters[callId] === answer }) throw LinkClientException.TimedOut()
            return answer.await()
        } finally {
            synchronized(lock) {
                if (waiters[callId] === answer) waiters.remove(callId)
                openingViews.remove(callId)
            }
        }
    }

    /**
     * Sends a message that expects no answer. Throws the session's end error when it has ended; a
     * [LinkCodecException] propagates (nothing was sent), and any other failure is [LinkClientException.SessionClosed].
     */
    internal suspend fun post(message: LinkMessage) {
        currentCoroutineContext().ensureActive()
        endErrorOrNull()?.let { throw it }
        try {
            channel.send(message)
        } catch (e: CancellationException) {
            throw e
        } catch (e: LinkCodecException) {
            throw e
        } catch (_: Exception) {
            throw LinkClientException.SessionClosed()
        }
    }

    /**
     * Runs [block] holding the upload turn. Cancellation while waiting for it or holding it propagates and gives the
     * turn up.
     */
    private suspend fun <T> withUploadTurn(block: suspend () -> T): T {
        waitingForTurn.incrementAndGet()
        try {
            uploadTurn.lock()
        } finally {
            waitingForTurn.decrementAndGet()
        }
        try {
            // Mutex.lock() takes a free lock without checking for cancellation.
            currentCoroutineContext().ensureActive()
            return block()
        } finally {
            uploadTurn.unlock()
        }
    }

    /**
     * The caller's bytes, copied on [Dispatchers.Default]: attachment-sized work (up to 10 MiB, as is the digest in
     * [upload]) never runs on the caller's dispatcher, which is often the main thread.
     */
    private suspend fun copyOffCaller(data: ByteArray): ByteArray = withContext(Dispatchers.Default) { data.copyOf() }

    /** One upload, `attach.begin` to `attach.end`. The caller holds the upload turn. */
    private suspend fun upload(kind: AttachmentKind, name: String, data: ByteArray, progress: (Int) -> Unit): String {
        val id = ask<LinkMessage.AttachReady> { LinkMessage.AttachBegin(it, kind, name, data.size) }.attachmentId
        var offset = 0
        while (offset < data.size) {
            val start = offset
            val end = minOf(start + ShellXLink.MAX_ATTACHMENT_CHUNK_BYTES, data.size)
            val chunk = data.copyOfRange(start, end)
            val answer = call { LinkMessage.AttachChunk(it, id, start, chunk) }
            if (answer !is LinkMessage.AttachChunkResult || answer.attachmentId != id || answer.received != end) {
                throw LinkClientException.UnexpectedAnswer()
            }
            offset = end
            progress(offset)
        }
        val digest = withContext(Dispatchers.Default) { sha256(data) }
        val finished = call { LinkMessage.AttachEnd(it, id, digest) }
        if (finished !is LinkMessage.AttachEndResult || finished.attachmentId != id) throw LinkClientException.UnexpectedAnswer()
        return id
    }

    /** The session's end error, or null while it runs. */
    internal fun endErrorOrNull(): LinkClientException? = synchronized(lock) { endError?.fresh() }

    private fun takeWaiter(callId: String): CompletableDeferred<LinkMessage>? = synchronized(lock) { waiters.remove(callId) }

    private suspend fun readLoop() {
        while (true) {
            val message = try {
                channel.receive()
            } catch (e: CancellationException) {
                throw e
            } catch (_: LinkCodecException.WrongVersion) {
                end(LinkClientException.ProtocolMismatch("the host sent another protocol version"))
                return
            } catch (_: LinkCodecException) {
                LinkLog.event("client dropped an undecodable frame")
                continue
            } catch (_: Exception) {
                end(LinkClientException.SessionClosed())
                return
            }
            if (!handle(message)) return
        }
    }

    /** Applies one received frame. False when the session is over. */
    private suspend fun handle(message: LinkMessage): Boolean {
        when (message) {
            is LinkMessage.TerminalViewOpenResult -> {
                val (waiter, terminalId) = synchronized(lock) { waiters.remove(message.callId) to openingViews[message.callId] }
                // The `ok` is announced first, so every frame of the new view comes after Opened (PROTOCOL.md 11.1).
                if (waiter != null && message.outcome == TerminalViewOpenOutcome.OK && terminalId != null) {
                    terminalQueue.trySend(TerminalViewPush.Opened(terminalId))
                }
                waiter?.complete(message)
            }
            // A late answer (its call timed out or was cancelled) finds no waiter and is dropped.
            is LinkMessage.Answer -> takeWaiter(message.callId)?.complete(message)
            is LinkMessage.Changed -> changeQueue.trySend(PendingChange(message.revision, message.added, message.resolved))
            is LinkMessage.SessionsChanged ->
                sessionQueue.trySend(SessionChange(message.revision, message.upserted, message.removed))
            is LinkMessage.WorkspacesChanged ->
                workspaceQueue.trySend(WorkspaceChange(message.revision, message.upserted, message.removed))
            is LinkMessage.ChatEntries -> chatQueue.trySend(ChatPush.Upsert(message.sessionId, message.entries))
            is LinkMessage.ChatReset -> chatQueue.trySend(ChatPush.Reset(message.sessionId))
            is LinkMessage.TerminalViewFrame -> terminalQueue.trySend(TerminalViewPush.Frame(message.terminalId, message.frame))
            is LinkMessage.TerminalViewEnded -> terminalQueue.trySend(TerminalViewPush.Ended(message.terminalId, message.reason))
            is LinkMessage.Ping -> try {
                channel.send(LinkMessage.Pong(message.nonce))
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // A failed send shows up as a failed receive next.
            }
            is LinkMessage.Error -> {
                if (message.code == "protocol_mismatch") {
                    end(LinkClientException.ProtocolMismatch(message.message))
                    return false
                }
                val waiter = message.callId?.let(::takeWaiter)
                if (waiter != null) {
                    waiter.completeExceptionally(LinkClientException.Remote(message.code, message.message))
                } else {
                    LinkLog.event("host reported error ${message.code}")
                }
            }
            // Pong, Unknown, Hello, Welcome and the client-only types (the terminal ones too) are ignored (PROTOCOL.md
            // section 7).
            else -> Unit
        }
        return true
    }

    /** Ends the session once: fails every waiter, completes every Flow, stops the timers and closes the circuit. */
    private fun end(error: LinkClientException) {
        val pending = synchronized(lock) {
            if (endError != null) return
            endError = error
            waiters.values.toList().also { waiters.clear() }
        }
        for (waiter in pending) waiter.completeExceptionally(error.fresh())
        changeQueue.close()
        sessionQueue.close()
        workspaceQueue.close()
        chatQueue.close()
        terminalQueue.close()
        pinger.cancel()
        watchdog.cancel()
        channel.close()
        scope.cancel()
    }

    companion object {
        /**
         * Runs the handshake (initiator, trusting only [hostKey]) and `hello` / `welcome`.
         *
         * Throws [NoiseException.UntrustedPeer] when the host is not [hostKey], [RelayException.Closed] when the host
         * drops the circuit (for example because it does not trust this phone, or the watchdog found it silent), and
         * [LinkClientException.ProtocolMismatch] or [LinkClientException.Rejected] when the host answers with an
         * error. The circuit is closed on failure.
         */
        suspend fun connect(
            circuit: RelayCircuit,
            key: NoiseStaticKey,
            hostKey: ByteArray,
            clientVersion: String,
            deviceName: String,
            timings: LinkTimings = LinkTimings.STANDARD,
        ): LinkClient {
            val pinned = hostKey.copyOf()
            val watched = WatchedCircuit(circuit)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default + CoroutineName("shellx-link-client"))
            // From before the handshake, so a host that goes silent at any point is found.
            val watchdog = scope.launch { watched.watch(timings.idleTimeout) }
            try {
                val channel = SecureChannel.open(watched, NoiseRole.INITIATOR, key) { it.contentEquals(pinned) }
                channel.send(LinkMessage.Hello(clientVersion, deviceName))
                val features = awaitWelcome(channel)
                return LinkClient(channel, features, timings, scope, watchdog)
            } catch (e: Throwable) {
                scope.cancel()
                watched.close()
                throw e
            }
        }

        /** Reads until `welcome` and returns its features; nothing else is allowed before it, and is ignored. */
        private suspend fun awaitWelcome(channel: SecureChannel): Set<String> {
            while (true) {
                val message = try {
                    channel.receive()
                } catch (_: LinkCodecException.WrongVersion) {
                    throw LinkClientException.ProtocolMismatch("the host sent another protocol version")
                } catch (_: LinkCodecException) {
                    LinkLog.event("client dropped an undecodable frame")
                    continue
                }
                when (message) {
                    is LinkMessage.Welcome -> {
                        if (message.protocolVersion != ShellXLink.PROTOCOL_VERSION) {
                            throw LinkClientException.ProtocolMismatch("the host speaks protocol ${message.protocolVersion}")
                        }
                        return message.features.toSet()
                    }
                    is LinkMessage.Error -> {
                        if (message.code == "protocol_mismatch") throw LinkClientException.ProtocolMismatch(message.message)
                        throw LinkClientException.Rejected(message.code, message.message)
                    }
                    else -> Unit
                }
            }
        }
    }
}
