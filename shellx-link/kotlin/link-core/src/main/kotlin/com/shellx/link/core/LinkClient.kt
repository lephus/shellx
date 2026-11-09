package com.shellx.link.core

import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
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
    /** Guards [nextCallNumber], [waiters] and [endError]. Never held across a suspension or a deferred completion. */
    private val lock = Any()
    private var nextCallNumber = 0L

    /** The calls waiting for their answer, by `call_id`. An answer whose id is not here is dropped. */
    private val waiters = HashMap<String, CompletableDeferred<LinkMessage>>()
    private var endError: LinkClientException? = null

    private val changeQueue = Channel<PendingChange>(Channel.UNLIMITED)
    private val sessionQueue = Channel<SessionChange>(Channel.UNLIMITED)
    private val workspaceQueue = Channel<WorkspaceChange>(Channel.UNLIMITED)
    private val chatQueue = Channel<ChatPush>(Channel.UNLIMITED)

    override val changes: Flow<PendingChange> = changeQueue.receiveAsFlow()
    override val sessionChanges: Flow<SessionChange> = sessionQueue.receiveAsFlow()
    override val workspaceChanges: Flow<WorkspaceChange> = workspaceQueue.receiveAsFlow()
    override val chatEntries: Flow<ChatPush> = chatQueue.receiveAsFlow()

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

    override fun close() = end(LinkClientException.SessionClosed())

    override fun toString(): String = "LinkClient(features=$hostFeatures)"

    /** [call], requiring an answer of type [T]. */
    private suspend inline fun <reified T : LinkMessage> ask(noinline make: (callId: String) -> LinkMessage): T =
        call(make) as? T ?: throw LinkClientException.UnexpectedAnswer()

    /** Sends `make(callId)` and returns the one answer that carries `callId`. */
    internal suspend fun call(make: (callId: String) -> LinkMessage): LinkMessage {
        val answer = CompletableDeferred<LinkMessage>()
        val callId = synchronized(lock) {
            endError?.let { throw it.fresh() }
            nextCallNumber += 1
            "c$nextCallNumber".also { waiters[it] = answer }
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
            return withTimeoutOrNull(timings.requestTimeout) { answer.await() } ?: throw LinkClientException.TimedOut()
        } finally {
            synchronized(lock) { if (waiters[callId] === answer) waiters.remove(callId) }
        }
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
            // A late answer (its call timed out or was cancelled) finds no waiter and is dropped.
            is LinkMessage.Answer -> takeWaiter(message.callId)?.complete(message)
            is LinkMessage.Changed -> changeQueue.trySend(PendingChange(message.revision, message.added, message.resolved))
            is LinkMessage.SessionsChanged ->
                sessionQueue.trySend(SessionChange(message.revision, message.upserted, message.removed))
            is LinkMessage.WorkspacesChanged ->
                workspaceQueue.trySend(WorkspaceChange(message.revision, message.upserted, message.removed))
            is LinkMessage.ChatEntries -> chatQueue.trySend(ChatPush.Upsert(message.sessionId, message.entries))
            is LinkMessage.ChatReset -> chatQueue.trySend(ChatPush.Reset(message.sessionId))
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
            // Pong, Unknown, Hello, Welcome and the client-only types are ignored (PROTOCOL.md section 7).
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
