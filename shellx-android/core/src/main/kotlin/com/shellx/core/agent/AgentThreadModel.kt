package com.shellx.core.agent

import com.shellx.core.link.ChatUpdate
import com.shellx.core.link.LinkCallException
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.MachineModel
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.MachineSession
import com.shellx.core.link.MachineStateUpdate
import com.shellx.core.link.SessionRef
import com.shellx.core.platform.rethrowIfCancelled
import com.shellx.core.storage.ConversationStore
import com.shellx.core.storage.StoreDocument
import com.shellx.link.core.AgentState
import com.shellx.link.core.LinkClientException
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.job
import kotlinx.coroutines.launch

/** What an agent screen shows ([AgentThreadModel.state]). */
data class AgentThreadState(
    val thread: ChatThread = ChatThread(),
    /** The newest page is on its way. */
    val loading: Boolean = false,
    /** An older page is on its way. */
    val loadingOlder: Boolean = false,
    /** How far the attachments of the message being sent got; null while none go up (Task 21). */
    val uploadProgress: Double? = null,
    /** The Mac answered that it does not have this session (history, send or stop). */
    val answeredNotFound: Boolean = false,
    /** open() read the phone's copy. */
    val cacheRead: Boolean = false,
    /** A newest page came since open(). */
    val latestLoaded: Boolean = false,
    /** The last newest page failed with an error from the Mac. */
    val latestFailed: Boolean = false,
    /** The last older page failed. */
    val olderFailed: Boolean = false,
)

/**
 * One agent session's screen (AgentThreadModel.swift): its chat (the phone's copy at once, then the Mac's newest page,
 * older pages on demand, live entries while the screen is open), its pending items, sending and Stop / Force stop.
 *
 * The copy is written to the store at most [SAVE_DELAY] after its last change, and at once by [close] (the screen goes
 * away) or [save] (the app leaves the foreground). Writes use the store writer [open] takes, which claims the thread:
 * nothing is written after a sign-out wipe, nor after a later screen of the same session claimed it. Sending to an
 * offline Mac answers at once and queues nothing (spec section 7.5).
 *
 * Main-confined. [scope] runs its saves, its first load and its progress hops; pass hub.scope, not viewModelScope
 * (3E), so a save started when the screen leaves still finishes. Derived getters read [state] and hub.state.
 */
class AgentThreadModel(
    val ref: SessionRef,
    private val hub: MachineHub,
    private val store: ConversationStore,
    private val scope: CoroutineScope,
    private val sleep: suspend (Duration) -> Unit = { delay(it) },
) {
    enum class EmptyState {
        /** The phone's copy or the Mac's first page is on its way (or the Mac is still connecting). */
        LOADING,

        /** The Mac's first page came, and it was empty. Live entries fill it as the agent writes. */
        NO_MESSAGES,

        /** The Mac is offline and the phone has no copy. */
        OFFLINE,

        /** The first page did not come (the Mac answered an error): retry. */
        FAILED,

        /** The Mac no longer has this session. */
        GONE,
    }

    enum class Older {
        /** Nothing: no older entries, or none can be asked for now (the Mac is offline). */
        NONE,

        /** Scrolling to the top asks for them. */
        LOADABLE,

        /** The last try failed: a row to try again (never a spinner that asks by itself). */
        FAILED,

        /** The phone keeps no more; they are on the Mac. */
        ONLY_ON_MAC,
    }

    companion object {
        /** Entries asked for per `chat.history` call (the protocol's most). */
        const val PAGE_SIZE = 50

        val SAVE_DELAY: Duration = 500.milliseconds
    }

    private val _state = MutableStateFlow(AgentThreadState())
    val state: StateFlow<AgentThreadState> = _state.asStateFlow()

    private var writer: ConversationStore.Writer? = null
    private var opening: Deferred<Unit>? = null
    private var pendingSave: Job? = null
    private var writing: Job? = null
    private var changed = false
    private var latestInFlight = 0
    private var observers = 0

    /** run() ran before (and was cancelled when the screen was covered). */
    private var hasRun = false

    /** The screen went away (close()) and is not shown again yet: late answers change the copy in memory only,
     *  nothing is saved or asked for. */
    private var closed = false

    /** Counts the Mac's transcript resets (`chat.reset`): a history answer asked for under an older count belongs to
     *  the old transcript and is dropped. */
    private var transcript = 0

    /** A reset came before open() took the writer: the stored copy is the old transcript's. */
    private var storedCopyIsStale = false

    /**
     * The hub's count of this session's transcript resets that this model has dealt with: set when it starts
     * following, raised by each reset it reads. A higher count when it follows again is a reset it missed while
     * covered or closed. Resets before the screen existed: ChatCopySweeper already dropped their stored copy.
     */
    private var resetsSeen: Int = hub.transcriptResets(ref)

    // What the screen reads

    val thread: ChatThread get() = state.value.thread
    val loading: Boolean get() = state.value.loading
    val loadingOlder: Boolean get() = state.value.loadingOlder
    val uploadProgress: Double? get() = state.value.uploadProgress

    private val machine: MachineModel? get() = hub.state.value.machine(ref.machineId)

    /** The session's Mac has no live, synced link: calls answer at once without sending. */
    val offline: Boolean get() = machine?.state != MachineLinkState.Online

    /** The session as its Mac lists it (its last known state while the Mac is offline), or null when the Mac does not
     *  list it. */
    val session: MachineSession?
        get() {
            val machine = machine ?: return null
            val session = machine.sessions.session(ref.sessionId) ?: return null
            return MachineSession(machine.id, machine.name, machine.state == MachineLinkState.Online, session)
        }

    /** The Mac's name, for "<Mac> is offline"; empty when the Mac is no longer paired. */
    val machineName: String get() = machine?.name ?: ""

    /** The Mac no longer has this session: it said so, or its synced list leaves it out. */
    val sessionGone: Boolean
        get() {
            if (state.value.answeredNotFound) return true
            val machine = machine ?: return false
            if (machine.state != MachineLinkState.Online || !machine.sessionsSupported) return false
            return machine.sessions.session(ref.sessionId) == null
        }

    /** The session as its Mac still lists it, once the Mac answered `not_found` for it: a ghost the phone's lists would
     *  keep showing, which the user may remove from this phone (GoneRemovalStore). */
    val ghost: MachineSession? get() = if (state.value.answeredNotFound) session else null

    /** The pending requests of this session's workspace on its Mac, oldest first. */
    val pendingHere: List<MachinePendingItem>
        get() {
            val workspaceId = session?.session?.workspaceId ?: return emptyList()
            return hub.state.value.pendingItems.filter { it.isIn(ref.machineId, workspaceId) }
        }

    /** Stop applies: the Mac is online, the session works or waits for the user, and the Mac did not say the session
     *  is gone. */
    val canStop: Boolean
        get() {
            if (state.value.answeredNotFound) return false
            val session = session ?: return false
            if (!session.online) return false
            return session.session.state == AgentState.WORKING || session.session.state == AgentState.NEEDS_INPUT
        }

    /** The Mac has older entries, but another page would push the newest out of the phone's MAX_ENTRIES: they are only
     *  on the Mac. */
    val olderOnlyOnMac: Boolean get() = thread.hasMore && thread.entries.size + PAGE_SIZE > ChatThread.MAX_ENTRIES

    /** Scrolling to the top can ask the Mac for older entries: it has some, the phone has room for them, and the
     *  session is still on the Mac (`not_found` ends paging). */
    val canLoadOlder: Boolean get() = thread.hasMore && !olderOnlyOnMac && !sessionGone

    /** Null when the chat has entries. */
    val emptyState: EmptyState?
        get() {
            val s = state.value
            if (s.thread.entries.isNotEmpty()) return null
            if (sessionGone) return EmptyState.GONE
            if (s.latestLoaded) return EmptyState.NO_MESSAGES
            if (!s.cacheRead || s.loading) return EmptyState.LOADING
            if (offline) {
                return when (machine?.state) {
                    MachineLinkState.Connecting, MachineLinkState.Reconnecting -> EmptyState.LOADING
                    else -> EmptyState.OFFLINE
                }
            }
            return if (s.latestFailed) EmptyState.FAILED else EmptyState.LOADING
        }

    val older: Older
        get() {
            if (thread.entries.isEmpty() || !thread.hasMore || sessionGone) return Older.NONE
            if (olderOnlyOnMac) return Older.ONLY_ON_MAC
            if (offline) return Older.NONE
            return if (state.value.olderFailed) Older.FAILED else Older.LOADABLE
        }

    /** True while run() follows the hub (tests). */
    internal val isObserving: Boolean get() = observers > 0

    /** Asks the Mac for its newest page again (after EmptyState.FAILED). */
    suspend fun retry() {
        loadLatest()
    }

    // History

    /**
     * Shows the phone's copy, then asks the Mac for its newest page (none while it is offline: the page loads when it
     * comes back, if run() is following). An empty page is a session with no messages yet; `not_found` is a session
     * gone from the Mac. Takes the store writer for this screen. Runs once, in [scope]; later calls wait for it, and a
     * cancelled caller only stops waiting.
     */
    suspend fun open() {
        val existing = opening
        if (existing != null) return existing.await()
        val created = scope.async { load() }
        opening = created
        created.await()
    }

    /** Asks for the page before the oldest entry here (`before_seq` = its `seq`) when [canLoadOlder]. A failure shows as
     *  Older.FAILED; calling again retries. */
    suspend fun loadOlder() {
        if (loadingOlder || offline || !canLoadOlder) return
        val oldest = thread.entries.firstOrNull()?.seq ?: return
        _state.update { it.copy(loadingOlder = true, olderFailed = false) }
        try {
            val asked = transcript
            val page = try {
                hub.chatHistory(ref, oldest, PAGE_SIZE)
            } catch (e: Exception) {
                rethrowIfCancelled(e)
                if (asked != transcript) return
                if (!noteNotFound(e)) _state.update { it.copy(olderFailed = true) }
                return
            }
            // Asked before a transcript reset, or the copy changed meanwhile (a newest page replaced it): this page may
            // not join it.
            if (asked != transcript || thread.entries.firstOrNull()?.seq != oldest) return
            change { it.applyOlderPage(page.entries, page.hasMore) }
        } finally {
            _state.update { it.copy(loadingOlder = false) }
        }
    }

    /**
     * Opens the screen and follows the hub until cancelled (3E: while the screen is STARTED): this session's live
     * entries, and the newest page again each time its Mac's link comes back. Subscribes before asking for history, so
     * nothing falls between. Run again after a cancel (the screen was covered, then shown again), it reads the newest
     * page again, for what came while nobody followed; when the transcript was reset meanwhile, the copy is dropped
     * first, so the new transcript replaces it instead of merging into it. Cancelled before that, it asks for nothing.
     */
    suspend fun run() {
        closed = false
        // Every way of opening an agent runs this: it no longer counts as just finished.
        hub.markSeen(ref)
        try {
            // Subscribing and reading the hub's reset count happen in one step on the main thread: every reset is
            // either counted here or delivered to `chat`.
            val chat = hub.chatUpdates()
            val states = hub.stateUpdates()
            val resets = hub.transcriptResets(ref)
            if (resets != resetsSeen) {
                resetsSeen = resets
                voidCopy()
            }
            val again = hasRun
            hasRun = true
            observers += 1
            try {
                coroutineScope {
                    // Undispatched, so each subscription is collected (and ends with this run) from the start.
                    launch(start = CoroutineStart.UNDISPATCHED) { followChat(chat) }
                    launch(start = CoroutineStart.UNDISPATCHED) { followStates(states) }
                    open()
                    if (again && isActive && !closed) {
                        // Saves skipped while the screen was away are written now.
                        if (changed) scheduleSave()
                        loadLatest()
                    }
                }
            } finally {
                observers -= 1
            }
        } finally {
            // A turn that finished while the user watched is not news when the screen goes away.
            hub.markSeen(ref)
        }
    }

    /**
     * The screen goes away: writes the copy now if it changed, in [scope], and returns the write's Job (callable from
     * onCleared()). Until run() shows it again, answers still on their way change the copy in memory only: nothing is
     * saved. If the same session's screen was opened again meanwhile, its writer won and this write is dropped.
     */
    fun close(): Job {
        closed = true
        return flush()
    }

    /** Writes the copy now if it changed (the app left the foreground); returns the write's Job. */
    fun save(): Job = flush()

    // Private

    private fun flush(): Job {
        pendingSave?.cancel()
        pendingSave = null
        return startWrite()
    }

    /** One write at a time, in order, each with the copy as it is when it starts. */
    private fun startWrite(): Job {
        val previous = writing
        val next = scope.launch {
            previous?.join()
            write()
        }
        writing = next
        return next
    }

    private suspend fun load() {
        // This screen's writer claims the thread: a screen for the same session opened later wins.
        writer = store.writer(claiming = StoreDocument.Thread(ref))
        if (storedCopyIsStale) {
            // A reset came before there was a writer: the stored copy is the old transcript's.
            storedCopyIsStale = false
            removeStoredCopy()
        } else {
            val asked = transcript
            val cached = store.load(StoreDocument.Thread(ref), ChatThread.CODEC)
            // A reset while reading: the copy read is the old transcript's (its removal is queued).
            if (cached != null && asked == transcript) {
                // Entries pushed live before the copy was read are newer than it.
                _state.update { it.copy(thread = cached.upsert(it.thread.entries)) }
            }
        }
        _state.update { it.copy(cacheRead = true) }
        // Changes made before there was a writer were not saved yet.
        if (changed) scheduleSave()
        // Closed while reading the copy: the screen is gone, ask for nothing.
        if (closed) return
        loadLatest()
    }

    private suspend fun loadLatest() {
        if (offline) return
        latestInFlight += 1
        _state.update { it.copy(loading = true) }
        try {
            val asked = transcript
            val page = try {
                hub.chatHistory(ref, null, PAGE_SIZE)
            } catch (e: Exception) {
                rethrowIfCancelled(e)
                // The Mac went offline meanwhile (the page loads when it is back), or must be paired again.
                if (e is LinkCallException.Offline || e is LinkCallException.NeedsPairing) return
                if (asked != transcript) return
                if (!noteNotFound(e)) _state.update { it.copy(latestFailed = true) }
                return
            }
            // The answer to a call sent before a transcript reset is the old transcript's: drop it (PROTOCOL.md
            // section 4, `chat.reset`).
            if (asked != transcript) return
            _state.update { it.copy(latestLoaded = true, latestFailed = false) }
            change { it.applyLatestPage(page.entries, page.hasMore) }
        } finally {
            latestInFlight -= 1
            _state.update { it.copy(loading = latestInFlight > 0) }
        }
    }

    private suspend fun followChat(updates: Flow<ChatUpdate>) {
        updates.collect { update ->
            if (update.ref != ref) return@collect
            when (update) {
                is ChatUpdate.Upsert -> change { it.upsert(update.entries) }
                is ChatUpdate.Reset -> {
                    resetsSeen += 1
                    transcriptReset()
                }
            }
        }
    }

    private suspend fun followStates(updates: Flow<MachineStateUpdate>) {
        // Online comes once per new link, after its first sync.
        updates.collect { update ->
            if (update.machineId != ref.machineId || update.state != MachineLinkState.Online) return@collect
            // Before open() the first page is its job; a closed screen asks for nothing.
            if (opening == null || closed) return@collect
            loadLatest()
        }
    }

    /** The Mac replaced the session's transcript: drops the copy, then pages again from the newest; entries pushed
     *  after the reset upsert as usual. */
    private suspend fun transcriptReset() {
        voidCopy()
        // Before open() (or while it reads the copy), its own newest page comes after the reset.
        if (!state.value.cacheRead || closed) return
        loadLatest()
    }

    /** Every entry held for the session, its `seq` values and any history answer still on its way belong to a
     *  transcript the Mac replaced: drops the copy in memory and on disk. */
    private fun voidCopy() {
        transcript += 1
        _state.update {
            // The Mac reset this session's transcript: it has the session.
            it.copy(thread = ChatThread(), latestLoaded = false, latestFailed = false, olderFailed = false, answeredNotFound = false)
        }
        // At once, not after SAVE_DELAY: a relaunch must not show the old transcript.
        removeStoredCopy()
    }

    /** Drops the stored copy through this screen's writer, after any write already under way; a save still waiting is
     *  cancelled. */
    private fun removeStoredCopy() {
        pendingSave?.cancel()
        pendingSave = null
        changed = false
        val writer = writer
        if (writer == null) {
            storedCopyIsStale = true
            return
        }
        val previous = writing
        writing = scope.launch {
            previous?.join()
            writer.remove(StoreDocument.Thread(ref))
        }
    }

    /** Records a `not_found` answer (the session is gone); returns whether it was one. */
    private fun noteNotFound(error: Exception): Boolean {
        if (error !is LinkClientException.Remote || error.code != "not_found") return false
        _state.update { it.copy(answeredNotFound = true) }
        return true
    }

    /** Applies [body] to the copy; saves it when it changed (unless the screen is closed). */
    private fun change(body: (ChatThread) -> ChatThread) {
        val before = thread
        val after = body(before)
        if (after == before) return
        _state.update { it.copy(thread = after) }
        changed = true
        scheduleSave()
    }

    private fun scheduleSave() {
        if (closed) return
        pendingSave?.cancel()
        pendingSave = scope.launch {
            try {
                sleep(SAVE_DELAY)
            } catch (e: Exception) {
                rethrowIfCancelled(e)
                return@launch
            }
            currentCoroutineContext().ensureActive()
            // This save is due: it is no longer pending (flush would otherwise cancel it while it waits for the write).
            if (pendingSave === currentCoroutineContext().job) pendingSave = null
            startWrite().join()
        }
    }

    private suspend fun write() {
        val writer = writer ?: return
        if (!changed) return
        changed = false
        writer.save(thread, ChatThread.CODEC, StoreDocument.Thread(ref))
    }
}
