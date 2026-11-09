package com.shellx.app.ui.agent

import android.content.res.Resources
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shellx.app.R
import com.shellx.app.SignedInScope
import com.shellx.app.ui.composer.byteCount
import com.shellx.app.ui.nav.WorkRoutes
import com.shellx.app.ui.theme.AppLanguage
import com.shellx.app.ui.workspaces.WorkspaceAlert
import com.shellx.app.ui.workspaces.WorkspaceAlertDialog
import com.shellx.app.ui.workspaces.WorkspaceListActions
import com.shellx.core.agent.AgentSendResult
import com.shellx.core.agent.AgentThreadModel
import com.shellx.core.composer.ComposerDraft
import com.shellx.core.composer.OutgoingAttachment
import com.shellx.core.home.AgentStatusRow
import com.shellx.core.home.ComposerValidation
import com.shellx.core.home.SessionName
import com.shellx.core.link.MachineSession
import com.shellx.core.link.SessionRef
import com.shellx.core.pending.AgentLabel
import com.shellx.link.core.ChatSendOutcome
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * One agent screen's model and what it holds across configuration changes: the composer's draft, the notice, the last
 * Close Agent alert and whether a stop is on its way. Main-confined; 3C's model is closed when the screen's entry goes
 * ([onCleared]).
 */
class AgentScreenHolder(val model: AgentThreadModel) : ViewModel() {
    var draft: ComposerDraft by mutableStateOf(ComposerDraft())
    var notice: AgentNotice? by mutableStateOf(null)
    var alert: WorkspaceAlert? by mutableStateOf(null)

    /** A Stop or Force Stop is on its way: another tap sends nothing. */
    var stopping: Boolean = false

    override fun onCleared() {
        model.close()
    }
}

/**
 * One agent's screen (`AgentView.swift`), pushed from a list or shown as a pane of the workspace screen ([embedded]: no
 * top bar of its own): [AgentScreen] fed by the session's [AgentThreadModel] (its chat, sends and stops), the hub and
 * the decision center (the "Needs you" bar of the session's workspace).
 *
 * The model follows the hub while the screen is started, and writes its chat copy when the app leaves the foreground
 * and when the screen goes. Sends, stops and closes run in `hub.scope`, so they outlive the screen; their results land
 * in the [AgentScreenHolder]. Standalone, `⋮` offers Close Agent while the agent can be closed, and Remove from This
 * Phone once its Mac answered `not_found` for a session it still lists (that hides it here, then goes [back]).
 */
@Composable
fun AgentView(scope: SignedInScope, ref: SessionRef, open: (String) -> Unit, back: () -> Unit, embedded: Boolean = false) {
    val holder: AgentScreenHolder = viewModel(key = "agent/${ref.machineId}/${ref.sessionId}") { AgentScreenHolder(scope.agentThread(ref)) }
    val model = holder.model
    val hub = scope.hub
    val center = scope.decisions
    val res = LocalContext.current.resources
    // Read so that the model's, the hub's and the center's getters are read again when they change.
    model.state.collectAsStateWithLifecycle().value
    hub.state.collectAsStateWithLifecycle().value
    center.state.collectAsStateWithLifecycle().value

    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(model, lifecycle) { lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { model.run() } }
    DisposableEffect(model, lifecycle) {
        // Still the screen shown: write now, keep following.
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) model.save() }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            model.save()
        }
    }
    // Also when the Mac reports the ghost otherwise: the cards' swipe follows what the Mac reports now.
    val ghost = model.ghost
    LaunchedEffect(ghost) { ghost?.let { scope.goneRemovals.noteGone(it) } }
    val notice = holder.notice
    LaunchedEffect(notice?.id) {
        if (notice == null) return@LaunchedEffect
        delay(AgentView.NOTICE_DURATION)
        if (holder.notice?.id == notice.id) holder.notice = null
    }

    fun show(text: String?) {
        if (text != null) holder.notice = AgentNotice(text)
    }

    fun send(text: String, picked: List<OutgoingAttachment>, viaVoice: Boolean) {
        // A message with attachments is on its way: another tap sends nothing.
        if (picked.isNotEmpty() && holder.draft.isSending) return
        holder.draft = AgentView.beforeSend(holder.draft, picked)
        hub.scope.launch {
            val result = model.send(text, picked, viaVoice)
            holder.draft = AgentView.afterSend(holder.draft, text, picked, result)
            show(AgentView.text(result, model.ref, model.machineName, res))
        }
    }

    fun stop(hard: Boolean) {
        if (holder.stopping) return
        holder.stopping = true
        hub.scope.launch {
            try {
                val outcome = model.stop(hard)
                show(StopButton.text(outcome, model.offline, model.machineName, res))
            } finally {
                holder.stopping = false
            }
        }
    }

    val session = model.session
    val screenRef = session?.ref ?: model.ref
    val draft = holder.draft
    AgentScreen(
        ref = screenRef,
        place = "${AgentLabel.of(screenRef.agent).text} · ${session?.machineName ?: model.machineName}",
        row = { model.session?.let { AgentStatusRow.of(it, scope.clock.nowMs()) } },
        gone = model.sessionGone,
        offline = model.offline,
        pending = center.visibleItems(model.pendingHere),
        showsMachineName = hub.machines.size > 1,
        entries = model.thread.entries,
        emptyState = model.emptyState,
        machineName = model.machineName,
        older = model.older,
        loadingOlder = model.loadingOlder,
        canStop = model.canStop,
        notice = notice,
        draft = draft,
        onDraftChange = { holder.draft = it },
        embedded = embedded,
        attachmentsEnabled = hub.acceptsAttachments(ref.machineId) || draft.attachments.isNotEmpty(),
        sending = if (draft.isSending) model.uploadProgress ?: 0.0 else null,
        // Embedded, the workspace screen's `⋮` closes the agent's tab instead ("Close Tab…").
        closeAgentName = if (embedded) null else session?.takeIf { WorkspaceListActions.canClose(it, hub) }?.let { SessionName.base(it.session) },
        canRemoveFromPhone = AgentView.removable(model, embedded) != null,
        actions = AgentScreenActions(
            send = { text, picked -> send(text, picked, viaVoice = false) },
            sendVoice = { send(it, emptyList(), viaVoice = true) },
            stop = { stop(hard = false) },
            forceStop = { stop(hard = true) },
            loadOlder = { hub.scope.launch { model.loadOlder() } },
            retry = { hub.scope.launch { model.retry() } },
            seeAllPending = {
                // The page of this workspace's pending cards: the same ones the bar counts.
                model.session?.session?.workspaceId?.let { open(WorkRoutes.pendingIn(model.ref.machineId, it)) }
            },
            closeAgent = { WorkspaceListActions.closeAgent(model.ref, hub) { holder.alert = it } },
            removeFromPhone = {
                AgentView.removable(model, embedded)?.let {
                    scope.goneRemovals.remove(it)
                    back()
                }
            },
        ),
        back = back,
    )
    WorkspaceAlertDialog(holder.alert) { holder.alert = null }
}

object AgentView {
    /** How long a notice over the composer stays (ledger 6.2-18). */
    val NOTICE_DURATION: Duration = 4.seconds

    /** What the screen says after a send; null when nothing happened, or the composer already says why. */
    fun text(result: AgentSendResult, ref: SessionRef, machineName: String, res: Resources): String? {
        val agent = AgentLabel.of(ref.agent).text
        return when (result) {
            is AgentSendResult.Refused -> when (val validation = result.validation) {
                is ComposerValidation.TooLong -> {
                    val locale = AppLanguage.of(res.configuration.locales[0])
                    res.getString(
                        R.string.composer_too_long, ComposerValidation.byteCount(validation.bytes, locale),
                        ComposerValidation.byteCount(ComposerValidation.MAX_BYTES, locale),
                    )
                }
                else -> null
            }
            is AgentSendResult.Sent -> when (result.outcome) {
                ChatSendOutcome.SUBMITTED -> res.getString(R.string.agent_sent)
                ChatSendOutcome.BUSY -> res.getString(R.string.agent_busy)
                ChatSendOutcome.NOT_FOUND -> res.getString(R.string.agent_gone)
                else -> res.getString(R.string.home_note_failed, agent, ref.workspaceTitle)
            }
            AgentSendResult.NotSent -> res.getString(R.string.home_note_failed, agent, ref.workspaceTitle)
            AgentSendResult.AttachmentsUnsupported -> res.getString(R.string.home_note_attachments_unsupported, agent, ref.workspaceTitle)
            AgentSendResult.Offline -> res.getString(R.string.home_note_offline, machineName)
            AgentSendResult.NoAnswer -> res.getString(R.string.home_note_no_answer, agent, ref.workspaceTitle)
        }
    }

    /** The session Remove from This Phone takes off, while the screen offers it: standalone, and its Mac answered
     *  `not_found` for a session it still lists. Null for a live session, always. */
    fun removable(model: AgentThreadModel, embedded: Boolean): MachineSession? = if (embedded) null else model.ghost

    /** With picks the composer holds the message while it goes up ([ComposerDraft.sendStarted]); without, unchanged. */
    fun beforeSend(draft: ComposerDraft, picked: List<OutgoingAttachment>): ComposerDraft =
        if (picked.isEmpty()) draft else draft.sendStarted()

    /** Without picks: the text back when the Mac surely did not take it and the field is still empty. With picks: what
     *  went is cleared unless the result keeps it. */
    fun afterSend(draft: ComposerDraft, text: String, picked: List<OutgoingAttachment>, result: AgentSendResult): ComposerDraft =
        if (picked.isEmpty()) {
            if (result.keepsDraft && draft.text.isEmpty()) draft.copy(text = text) else draft
        } else {
            draft.sendEnded(result.keepsDraft)
        }
}
