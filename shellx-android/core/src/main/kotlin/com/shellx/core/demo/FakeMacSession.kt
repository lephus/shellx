package com.shellx.core.demo

import com.shellx.link.core.AttachmentKind
import com.shellx.link.core.ChatAttachment
import com.shellx.link.core.ChatHistoryPage
import com.shellx.link.core.ChatInterruptOutcome
import com.shellx.link.core.ChatPush
import com.shellx.link.core.ChatSendOutcome
import com.shellx.link.core.LinkClientException
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.LinkSession
import com.shellx.link.core.PendingChange
import com.shellx.link.core.PendingSnapshot
import com.shellx.link.core.ReplyOutcome
import com.shellx.link.core.SessionChange
import com.shellx.link.core.SessionList
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

/**
 * One phone's session with a [FakeMac]. Every call counts in [FakeMac.phoneCallCount]; a call on an ended session
 * throws `SessionClosed`. Otherwise the Mac's side runs in the Mac's scope, and the phone waits for its answer or for
 * the session's end, whichever comes first (the end throws `SessionClosed`).
 */
internal class FakeMacSession(private val mac: FakeMac, override val hostFeatures: Set<String>) : LinkSession {
    val pendingQueue = Channel<PendingChange>(Channel.UNLIMITED)
    val sessionQueue = Channel<SessionChange>(Channel.UNLIMITED)
    val workspaceQueue = Channel<WorkspaceChange>(Channel.UNLIMITED)
    val chatQueue = Channel<ChatPush>(Channel.UNLIMITED)
    private val ended = CompletableDeferred<Unit>()

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

    override suspend fun chatHistory(sessionId: String, beforeSeq: Long?, limit: Int): ChatHistoryPage =
        ask { throw noChat() }

    override suspend fun chatSend(sessionId: String, text: String, attachments: List<String>): ChatSendOutcome =
        ask { throw noChat() }

    override suspend fun uploadAttachment(
        kind: AttachmentKind,
        name: String,
        data: ByteArray,
        progress: (Int) -> Unit,
    ): String = ask { throw noChat() }

    override suspend fun chatSend(
        sessionId: String,
        text: String,
        uploading: List<ChatAttachment>,
        progress: (Int) -> Unit,
    ): ChatSendOutcome = ask { throw noChat() }

    override suspend fun chatInterrupt(sessionId: String, hard: Boolean): ChatInterruptOutcome = ask { throw noChat() }

    override suspend fun workspaces(): WorkspaceList = ask {
        if (!mac.servesWorkspaces) throw LinkClientException.Remote("unsupported", "this host lists no workspaces")
        mac.workspaceSource.list()
    }

    override suspend fun createWorkspace(): WorkspaceCreated = ask { throw noControl() }

    override suspend fun renameWorkspace(workspaceId: String, title: String): WorkspaceControlOutcome =
        ask { throw noControl() }

    override suspend fun closeWorkspace(workspaceId: String): WorkspaceControlOutcome = ask { throw noControl() }

    override suspend fun closeAgent(sessionId: String): WorkspaceControlOutcome = ask { throw noControl() }

    override suspend fun closeTerminal(workspaceId: String, terminalId: String): WorkspaceControlOutcome =
        ask { throw noControl() }

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

    private fun noChat() = LinkClientException.Remote("unsupported", "this host has no chat")

    private fun noControl() = LinkClientException.Remote("unsupported", "this host takes no workspace control")

    /**
     * Counts the call, then runs [macSide] in the Mac's scope and waits for its answer or the session's end. The Mac's
     * side never fails its coroutine (its failure travels in a `Result`), so a reporting parent scope such as runTest's
     * backgroundScope never sees a refused call.
     */
    private suspend fun <T> ask(macSide: suspend () -> T): T {
        currentCoroutineContext().ensureActive()
        mac.notePhoneCall()
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
}
