package com.shellx.core.workspaces

import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.MachineModel
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.MachineSession
import com.shellx.core.platform.rethrowIfCancelled
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** What a workspace screen shows ([WorkspaceScreenModel.state]). */
data class WorkspaceScreenState(
    val phase: WorkspaceScreenModel.Phase = WorkspaceScreenModel.Phase.WAITING,
    /** The terminal id of the chip shown; null while the workspace has no terminal. */
    val selectedTerminalId: String? = null,
    /**
     * How many times the chip shown left the Mac's list while the workspace stayed (it was closed on the Mac): the
     * screen moved to the next chip, and says so in a short line (spec section 6.2). A tab closed from this phone
     * ([WorkspaceScreenModel.closesHere]) does not count: the user knows why it went.
     */
    val shownPaneClosed: Int = 0,
    /** The workspace left the Mac's list (DISMISSED) after its last tabs were closed from this phone: the screen leaves
     *  without saying the workspace was closed on the Mac. */
    val lastTabClosedHere: Boolean = false,
)

/**
 * One workspace's screen (WorkspaceScreenModel.swift, without plan 2C's terminal page): the workspace as its Mac lists
 * it, the chip shown, and when the screen should give up (the workspace is gone, or never came).
 *
 * - The chip shown starts as [defaultTerminal] says and changes when the user swipes ([select]), or when the chip
 *   shown leaves the Mac's list: the next chip shows. The sessions and the requests can arrive after the list: until
 *   the user picks a chip, a chip that does not show an agent's chat gives way, once, to the pane waiting for the user.
 *   What the Mac selects later does not move it.
 * - The phase is DISMISSED only for a workspace the screen has seen and that then left the list of a Mac that is
 *   online and lists its workspaces ([absence]): only that Mac says the workspace was closed. A list emptied for
 *   another reason (the Mac is offline or no longer reachable from this phone, or its list could not be read) keeps
 *   the last chips; a Mac removed from this phone is MACHINE_REMOVED. A workspace the Mac has not listed yet (a
 *   create's answer can come before the push that lists the new workspace) is WAITING; after [PATIENCE] the model asks
 *   the Mac for its list once more, and when the workspace is still absent the phase is NOT_FOUND (it still shows if a
 *   push lists it later).
 * - A Mac that goes offline leaves the last known list in place, so the chips stay.
 * - A tab the user closes from this phone ([closesHere]) leaves without a word: the next chip shows without
 *   shownPaneClosed, and a workspace that goes with its last tabs sets lastTabClosedHere.
 *
 * Main-confined. Derived getters read [state] and hub.state. reconcile() runs once at construction, so the first frame
 * already shows the workspace and its chip; [run] follows the hub while the screen is shown.
 */
class WorkspaceScreenModel(
    val ref: WorkspaceRef,
    private val hub: MachineHub,
    private val sleep: suspend (Duration) -> Unit = { delay(it) },
) {
    enum class Phase {
        /** The Mac's list does not have the workspace yet. */
        WAITING,
        SHOWING,

        /** The workspace was listed, and left: it was closed (on the Mac, or by this screen). */
        DISMISSED,

        /** The workspace's Mac was removed from this phone: the screen leaves without a word. */
        MACHINE_REMOVED,

        /** The workspace did not come within PATIENCE, even after asking the Mac again. */
        NOT_FOUND,
    }

    /** Why the Mac's list, as the hub has it, lacks a workspace the screen saw. */
    internal enum class Absence {
        /** The Mac is online and lists its workspaces: it closed the workspace. */
        CLOSED,

        /** The Mac is no longer paired with this phone. */
        MACHINE_REMOVED,

        /** The hub emptied the list without the Mac saying anything (it is offline, no longer reachable from this
         *  phone, or its list could not be read): the last chips stay. */
        UNKNOWN,
    }

    companion object {
        /** How long a workspace the Mac has not listed is waited for before the Mac is asked again. */
        val PATIENCE: Duration = 5.seconds

        /**
         * The chip to show first, as its terminal id:
         * - an agent whose session needs input waits for the user: among those, one whose agent is the agent of a
         *   request of the workspace, then the one the Mac has selected, then the first;
         * - while a request of the workspace waits for the user and no session says it needs input yet, the agent the
         *   Mac has selected, else the first chip that runs an agent;
         * - otherwise the chip the Mac has selected;
         * - otherwise the first chip.
         *
         * [pending] are the requests of the workspace's Mac (those of another workspace are ignored). [sessions] are
         * the sessions the hub lists for that Mac: a terminal naming any other is not an agent (null takes every
         * `sessionId` as a live session, in no known state).
         */
        fun defaultTerminal(workspace: LinkWorkspace, pending: List<MachinePendingItem>, sessions: List<AgentSession>? = null): String? =
            defaultChoice(workspace, pending, sessions).first

        /** [defaultTerminal], and whether that chip is there because it waits for the user. */
        internal fun defaultChoice(
            workspace: LinkWorkspace,
            pending: List<MachinePendingItem>,
            sessions: List<AgentSession>?,
        ): Pair<String?, Boolean> {
            val terminals = WorkspacePane.ordered(workspace.terminals)
            val live = sessions?.let { list ->
                LinkedHashMap<String, AgentSession>().also { map -> for (session in list) map.putIfAbsent(session.sessionId, session) }
            }

            fun session(terminal: LinkTerminal): AgentSession? = terminal.sessionId?.let { live?.get(it) }

            fun preferred(chips: List<LinkTerminal>): String? = (chips.firstOrNull { it.selected } ?: chips.firstOrNull())?.terminalId

            val agents = terminals.filter { terminal ->
                val sessionId = terminal.sessionId ?: return@filter false
                live?.containsKey(sessionId) ?: true
            }
            val asking = pending.filter { it.item.workspaceId == workspace.workspaceId }
            val waiting = agents.filter { session(it)?.state == AgentState.NEEDS_INPUT }
            if (waiting.isNotEmpty()) {
                val askingAgents = asking.map { it.item.agent }.toSet()
                val matching = waiting.filter { terminal -> session(terminal)?.let { it.agent in askingAgents } ?: false }
                return preferred(matching.ifEmpty { waiting }) to true
            }
            if (asking.isNotEmpty()) preferred(agents)?.let { return it to true }
            return preferred(terminals) to false
        }

        /** The chip that takes the place of [gone]: the next one that is still there, else the one before. [before] are
         *  the chips' ids as they were, [now] as they are. */
        internal fun successor(gone: String, before: List<String>, now: List<String>): String? {
            val index = before.indexOf(gone)
            if (index < 0) return now.firstOrNull()
            before.subList(index + 1, before.size).firstOrNull { it in now }?.let { return it }
            before.subList(0, index).lastOrNull { it in now }?.let { return it }
            return now.firstOrNull()
        }

        internal fun absence(machine: MachineModel?): Absence {
            machine ?: return Absence.MACHINE_REMOVED
            return if (machine.state == MachineLinkState.Online && machine.workspacesSupported) Absence.CLOSED else Absence.UNKNOWN
        }
    }

    private val _state = MutableStateFlow(WorkspaceScreenState())
    val state: StateFlow<WorkspaceScreenState> = _state.asStateFlow()

    /** The workspace was in the Mac's list at some point. */
    private var seen = false

    /** The terminal ids as reconcile() last saw them, in chip order. */
    private var knownTerminalIds: List<String> = emptyList()

    /** The workspace as the Mac last listed it: shown while the list does not have it for a reason other than a close. */
    private var kept: LinkWorkspace? = null

    /** The chip shown was chosen for good: the user picked it, the screen moved to the pane waiting for the user, or the
     *  chip shown left and the next one took its place. Until then the screen may still move to the pane waiting for
     *  the user. */
    private var settled = false

    /** The tabs this phone asked the Mac to close ([closesHere]), less those the Mac kept ([keeps]). */
    private val closingHere = HashSet<String>()

    /** The terminal ids, in chip order, the workspace had when it last had any: a Mac may list the workspace with no tab
     *  for a moment before it goes. */
    private var lastTerminalIds: List<String> = emptyList()

    init {
        // The first frame already shows the workspace and its chip, when the list has it.
        reconcile()
    }

    // What the screen reads

    val phase: Phase get() = state.value.phase
    val selectedTerminalId: String? get() = state.value.selectedTerminalId
    val shownPaneClosed: Int get() = state.value.shownPaneClosed
    val lastTabClosedHere: Boolean get() = state.value.lastTabClosedHere

    private val machine: MachineModel? get() = hub.state.value.machine(ref.machineId)

    /** The workspace in the Mac's list as the hub has it now. */
    private val listed: LinkWorkspace? get() = machine?.workspaces?.workspace(ref.workspaceId)

    /** The workspace as its Mac last listed it (also while the Mac is offline, or after the hub emptied the list of a
     *  Mac that did not close it), or null while the screen has not seen it. */
    val workspace: LinkWorkspace? get() = listed ?: kept

    /** The workspace's chips, in the Mac's order. Empty while there is no workspace. */
    val panes: List<WorkspacePane>
        get() {
            val machine = machine ?: return emptyList()
            val workspace = workspace ?: return emptyList()
            return WorkspacePane.panes(workspace) { sessionId ->
                machine.sessions.session(sessionId)?.let {
                    MachineSession(machine.id, machine.name, machine.state == MachineLinkState.Online, it)
                }
            }
        }

    /** Rename and close reach the Mac: it is online and takes workspace commands. */
    val canControl: Boolean
        get() = machine?.state == MachineLinkState.Online && hub.state.value.supportsWorkspaceControl(ref.machineId)

    // Choosing a chip

    /** Shows the chip [terminalId] (the user swiped to it). An id the workspace does not have is ignored. */
    fun select(terminalId: String) {
        // The pager may write back the chip it already shows: only a change is the user's pick.
        if (terminalId == selectedTerminalId) return
        if (workspace?.terminals?.any { it.terminalId == terminalId } != true) return
        _state.update { it.copy(selectedTerminalId = terminalId) }
        settled = true
    }

    /** The user closed the tab [terminalId] from this phone, and the close is on its way to the Mac: when the Mac's
     *  list drops it, the next chip shows without a word (shownPaneClosed stays), and a workspace that goes with it
     *  sets lastTabClosedHere. */
    fun closesHere(terminalId: String) {
        closingHere += terminalId
    }

    /** The Mac did not close the tab [terminalId] after all ([closesHere]): if it goes later, the Mac closed it, and the
     *  screen says so. */
    fun keeps(terminalId: String) {
        closingHere -= terminalId
    }

    // Following the hub

    /**
     * Follows the hub until cancelled: takes each change of the hub's state into the phase and the chip shown
     * (reconcile() changes nothing when nothing relevant changed), and gives up waiting for a workspace the Mac does
     * not list ([PATIENCE]). Opening the screen counts as looking at the workspace (MachineHub.markSeen).
     */
    suspend fun run() {
        hub.markSeen(ref)
        reconcile()
        coroutineScope {
            launch { giveUpWaiting() }
            hub.state.collect { reconcile() }
        }
    }

    /** Brings the phase and the chip shown up to date with the hub's list. */
    internal fun reconcile() {
        var s = state.value
        if (s.phase == Phase.DISMISSED || s.phase == Phase.MACHINE_REMOVED) return
        val workspace = listed
        if (workspace == null) {
            // Never listed: still on its way (or NOT_FOUND).
            if (!seen) return
            when (absence(machine)) {
                Absence.CLOSED -> {
                    val closedHere = lastTerminalIds.isNotEmpty() && lastTerminalIds.all { it in closingHere }
                    _state.value = s.copy(lastTabClosedHere = closedHere, phase = Phase.DISMISSED)
                }
                Absence.MACHINE_REMOVED -> _state.value = s.copy(phase = Phase.MACHINE_REMOVED)
                Absence.UNKNOWN -> Unit
            }
            return
        }
        seen = true
        if (kept != workspace) kept = workspace
        s = s.copy(phase = Phase.SHOWING)
        val ids = WorkspacePane.ordered(workspace.terminals).map { it.terminalId }
        val selected = s.selectedTerminalId
        if (selected != null && selected !in ids) {
            s = s.copy(selectedTerminalId = successor(selected, knownTerminalIds, ids))
            settled = true
            if (selected !in closingHere) s = s.copy(shownPaneClosed = s.shownPaneClosed + 1)
        } else if (selected == null) {
            val (terminalId, waitsForUser) = defaultChoice(workspace, pendingHere, sessionsHere)
            s = s.copy(selectedTerminalId = terminalId)
            settled = waitsForUser
        } else if (!settled && !showsAgent(workspace, selected)) {
            // The sessions or the request came after the list: move to the pane waiting for the user. A chip that shows
            // an agent's chat stays, so a message being typed is never pulled away.
            val (terminalId, waitsForUser) = defaultChoice(workspace, pendingHere, sessionsHere)
            if (waitsForUser) {
                s = s.copy(selectedTerminalId = terminalId)
                settled = true
            }
        }
        knownTerminalIds = ids
        if (ids.isNotEmpty()) lastTerminalIds = ids
        _state.value = s
    }

    private val pendingHere: List<MachinePendingItem>
        get() = hub.state.value.pendingItems.filter { it.isIn(ref.machineId, ref.workspaceId) }

    private val sessionsHere: List<AgentSession> get() = machine?.sessions?.sessions ?: emptyList()

    /** The chip shown runs an agent the hub lists: its page is that agent's chat. */
    private fun showsAgent(workspace: LinkWorkspace, selected: String): Boolean {
        val sessionId = workspace.terminals.firstOrNull { it.terminalId == selected }?.sessionId ?: return false
        return machine?.sessions?.session(sessionId) != null
    }

    /** A workspace not listed yet: after PATIENCE asks the Mac for its list, once; then it either shows or is not
     *  found. */
    private suspend fun giveUpWaiting() {
        if (phase != Phase.WAITING) return
        try {
            sleep(PATIENCE)
        } catch (e: Exception) {
            rethrowIfCancelled(e)
            return
        }
        if (phase != Phase.WAITING) return
        hub.refreshWorkspaces(ref.machineId)
        reconcile()
        if (phase == Phase.WAITING) _state.update { it.copy(phase = Phase.NOT_FOUND) }
    }
}
