package com.shellx.app

import com.shellx.app.ui.workspaces.ListNotice
import com.shellx.core.agent.AgentThreadModel
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.home.EndedDismissalStore
import com.shellx.core.home.GoneRemovalStore
import com.shellx.core.link.MachineHub
import com.shellx.core.link.SessionRef
import com.shellx.core.pairing.PairingModel
import com.shellx.core.pairing.SheetPresence
import com.shellx.core.pending.DecisionCenter
import com.shellx.core.platform.Clock
import com.shellx.core.storage.ChatCopySweeper
import com.shellx.core.storage.ConversationStore
import com.shellx.core.voice.VoiceService
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * What one signed-in hub's screens share (`SignedInScope.swift`; plan 3E reads these names): its hub, the decision
 * center, the pairing model, the history store and its sweeper, the voice input, the open sheets, the list's notice,
 * and the ended and gone sessions the user removed. Made with each hub the coordinator makes, and dropped with it.
 * Main-confined.
 */
class SignedInScope(
    val hub: MachineHub,
    val decisions: DecisionCenter,
    val pairing: PairingModel,
    /** Where each agent's chat copy is kept (wiped on sign-out). */
    val history: ConversationStore,
    val launch: LaunchMark,
    val endedDismissals: EndedDismissalStore,
    val goneRemovals: GoneRemovalStore,
    val clock: Clock,
    val latency: LatencyLog,
    /** The mic's models and settings; null shows no mic and no Settings › Voice (until plan 3E's makeVoice). */
    val voice: VoiceService? = null,
    /** The pending sheets open now: a pairing link waits until none is. */
    val sheets: SheetPresence = SheetPresence(),
) {
    /** Drops a chat copy when its Mac resets the transcript, whether or not its screen is open. */
    val chatCopies: ChatCopySweeper = ChatCopySweeper(hub, history)

    /** What the workspace list says once more: a workspace screen that closed itself leaves a line here. */
    val listNotice: ListNotice = ListNotice()

    private var started = false

    /** The model of one agent's screen, over this account's hub and history. */
    fun agentThread(ref: SessionRef): AgentThreadModel = AgentThreadModel(ref, hub, history, hub.scope)

    /** The workspace list is shown: records `launchToHome` once per launch. */
    fun homeShown() = launch.homeShown()

    /** The default Mac's workspace list arrived: records `launchToWorkspaceList` once per launch. */
    fun workspacesListed() = launch.workspacesListed()

    /**
     * Once, in `hub.scope`: the chat-copy sweeper, and the decision center following the hub's whole pending list
     * (`SignedInView.swift`, the one place that calls `sync`). Both end with the hub.
     */
    fun start() {
        if (started) return
        started = true
        hub.scope.launch { chatCopies.run() }
        hub.scope.launch { hub.state.map { it.pendingItems }.distinctUntilChanged().collect { decisions.sync(it) } }
    }
}
