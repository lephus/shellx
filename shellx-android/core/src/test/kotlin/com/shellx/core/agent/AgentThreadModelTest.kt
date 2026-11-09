package com.shellx.core.agent

import com.shellx.core.demo.FakeMac
import com.shellx.core.link.ChatUpdate
import com.shellx.core.link.MachineLinkConnecting
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.SessionRef
import com.shellx.core.storage.ChatCopySweeper
import com.shellx.core.storage.ConversationStore
import com.shellx.core.storage.StoreDocument
import com.shellx.core.testing.HubRig
import com.shellx.core.testing.ManualSleeper
import com.shellx.core.testing.agentSession
import com.shellx.core.testing.eventually
import com.shellx.core.testing.hubRig
import com.shellx.core.testing.pendingItem
import com.shellx.link.core.AgentState
import com.shellx.link.core.ChatEntry
import com.shellx.link.core.ChatEntryKind
import com.shellx.link.core.ChatEntryRole
import com.shellx.link.core.ChatHistoryPage
import com.shellx.link.core.LinkClientException
import com.shellx.link.core.LinkSession
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest

/**
 * One agent's detail screen: the chat copy shown from the phone at once, then the Mac's newest page, older pages on
 * demand, live entries, and the pending items of the session's workspace (AgentThreadModelTests.swift; sending and
 * stopping are AgentThreadSendTest).
 */
class AgentThreadModelTest {
    private fun ref(mac: FakeMac, sessionId: String = "s1", workspace: String = "shellx") =
        SessionRef(mac.machine.machineId, sessionId, "claude", workspace)

    /** A Mac with one working session `s1` whose transcript holds [history]. */
    private fun TestScope.mac(history: List<ChatEntry>, name: String = "MacBook Pro"): FakeMac {
        val mac = FakeMac(name, backgroundScope)
        mac.upsertSession(agentSession("s1"))
        mac.setHistory("s1", history)
        return mac
    }

    private fun entries(seqs: LongRange, text: String? = null, rev: Long = 1): List<ChatEntry> = seqs.map { seq ->
        ChatEntry(
            id = "e-$seq", rev = rev, seq = seq, role = ChatEntryRole.AGENT, kind = ChatEntryKind.PROSE,
            text = "${text ?: "entry"} $seq", tsMs = 1_700_000_000_000 + seq,
        )
    }

    /** The model's waits (the 0.5 s save) wait on the returned sleeper. */
    private fun TestScope.model(ref: SessionRef, rig: HubRig): Pair<AgentThreadModel, ManualSleeper> {
        val timers = ManualSleeper()
        return AgentThreadModel(ref, rig.hub, rig.store, backgroundScope, timers.sleep) to timers
    }

    /** Runs model.run() until the test ends; returns once it follows the hub. */
    private suspend fun TestScope.startRunning(model: AgentThreadModel): Boolean {
        backgroundScope.launch { model.run() }
        return eventually { model.isObserving }
    }

    private suspend fun stored(ref: SessionRef, rig: HubRig): ChatThread? =
        rig.store.load(StoreDocument.Thread(ref), ChatThread.CODEC)

    private fun seedCopy(vararg copies: Pair<SessionRef, ChatThread>): suspend (ConversationStore) -> Unit = { store ->
        for ((ref, thread) in copies) store.writer().save(thread, ChatThread.CODEC, StoreDocument.Thread(ref))
    }

    // Seen

    @Test fun runMarksTheSessionSeen() { runTest {
        val mac = mac(entries(1L..3))
        mac.upsertSession(agentSession("s2", workspace = "web"))
        val s1 = ref(mac)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(2))
        val id = mac.machine.machineId
        mac.upsertSession(agentSession("s1", state = AgentState.IDLE, lastActivityMs = 2, stateSinceMs = 2))
        mac.upsertSession(agentSession("s2", state = AgentState.IDLE, lastActivityMs = 2, stateSinceMs = 2, workspace = "web"))
        assertTrue(eventually { rig.hub.finishedSessionIds(id) == setOf("s1", "s2") })

        val (model, _) = model(s1, rig)
        val task = launch { model.run() }
        val seen = eventually { rig.hub.finishedSessionIds(id) == setOf("s2") }
        task.cancel()
        assertTrue(seen, "opening an agent clears it from Just finished, and only it")
    } }

    @Test fun aTurnThatFinishesWhileWatchingDoesNotComeBackAsJustFinished() { runTest {
        val mac = mac(entries(1L..3))
        val s1 = ref(mac)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val id = mac.machine.machineId
        val (model, _) = model(s1, rig)
        val task = launch { model.run() }
        assertTrue(eventually { model.isObserving })

        mac.upsertSession(agentSession("s1", state = AgentState.WORKING, lastActivityMs = 2, stateSinceMs = 2))
        mac.upsertSession(agentSession("s1", state = AgentState.IDLE, lastActivityMs = 3, stateSinceMs = 3))
        assertTrue(eventually { rig.hub.finishedSessionIds(id) == setOf("s1") })
        task.cancelAndJoin()

        assertEquals(emptySet(), rig.hub.finishedSessionIds(id), "the user watched it finish")
    } }

    // History

    @Test fun openShowsCacheThenLatest() { runTest {
        val mac = mac(entries(1L..30, rev = 2))
        val s1 = ref(mac)
        val cached = ChatThread(entries(1L..5, text = "cached"), hasMore = false)
        val rig = hubRig(listOf(mac), seed = seedCopy(s1 to cached), start = true)
        assertTrue(rig.online(1))
        val (model, timers) = model(s1, rig)
        assertEquals(ChatThread(), model.thread, "nothing before open()")

        mac.holdChat()
        val opening = launch { model.open() }
        assertTrue(
            eventually { model.thread == cached && model.loading },
            "the copy on the phone shows while the Mac's page is on its way",
        )
        assertTrue(eventually { mac.historyRequests.size == 1 })
        mac.releaseChat()
        opening.join()

        assertFalse(model.loading)
        assertEquals((1L..30).toList(), model.thread.entries.map { it.seq })
        assertEquals(List(30) { 2L }, model.thread.entries.map { it.rev }, "the Mac's newer revisions win")
        assertFalse(model.thread.hasMore)
        assertEquals(listOf(FakeMac.HistoryRequest("s1", null, 50)), mac.historyRequests)

        // The new copy is written at most SAVE_DELAY after the change.
        assertTrue(eventually { AgentThreadModel.SAVE_DELAY in timers.waiting })
        assertEquals(500.milliseconds, AgentThreadModel.SAVE_DELAY)
        assertEquals(cached, stored(s1, rig))
        timers.release { it == AgentThreadModel.SAVE_DELAY }
        assertTrue(eventually { stored(s1, rig) == model.thread })

        // Opening again does not ask twice.
        model.open()
        assertEquals(1, mac.historyRequests.size)
    } }

    @Test fun loadOlderUsesSmallestSeq() { runTest {
        val mac = mac(entries(1L..120))
        val s1 = ref(mac)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val (model, _) = model(s1, rig)

        model.open()
        assertEquals((71L..120).toList(), model.thread.entries.map { it.seq })
        assertTrue(model.thread.hasMore)

        model.loadOlder()
        assertEquals((21L..120).toList(), model.thread.entries.map { it.seq })
        assertTrue(model.thread.hasMore)
        model.loadOlder()
        assertEquals((1L..120).toList(), model.thread.entries.map { it.seq })
        assertFalse(model.thread.hasMore)
        assertFalse(model.loadingOlder)

        // Nothing older: no call.
        model.loadOlder()
        val requests = mac.historyRequests
        assertEquals(listOf(null, 71L, 21L), requests.map { it.beforeSeq })
        assertEquals(listOf(50, 50, 50), requests.map { it.limit })
    } }

    @Test fun loadOlderStopsAtThePhonesCap() { runTest {
        val mac = mac(entries(1L..700))
        val s1 = ref(mac)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val (model, _) = model(s1, rig)
        model.open()
        repeat(12) { model.loadOlder() }

        assertEquals(ChatThread.MAX_ENTRIES, model.thread.entries.size)
        assertEquals(700, model.thread.entries.last().seq, "the newest entries are the ones kept")
        assertTrue(model.thread.hasMore)
        assertTrue(model.olderOnlyOnMac)
        assertEquals(AgentThreadModel.Older.ONLY_ON_MAC, model.older)
        assertEquals(10, mac.historyRequests.size, "the newest page, then nine older pages up to the cap, then no more calls")
    } }

    @Test fun liveEntriesAppendWhileOpen() { runTest {
        val mac = mac(entries(1L..3))
        mac.upsertSession(agentSession("s2", workspace = "web"))
        mac.setHistory("s2", emptyList())
        val s1 = ref(mac)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(2))
        val (model, timers) = model(s1, rig)

        assertTrue(startRunning(model))
        assertTrue(eventually { model.thread.entries.map { it.seq } == listOf(1L, 2, 3) }, "run() opens the screen's history")

        mac.pushChat("s1", entries(4L..4))
        assertTrue(eventually { model.thread.entries.map { it.seq } == listOf(1L, 2, 3, 4) })

        // The entry grows in place (a higher rev); another session's entries never show here.
        mac.pushChat(
            "s2",
            listOf(ChatEntry(id = "web-5", rev = 1, seq = 5, role = ChatEntryRole.AGENT, kind = ChatEntryKind.PROSE, text = "web", tsMs = 1)),
        )
        mac.pushChat("s1", entries(4L..4, text = "grown", rev = 2) + entries(5L..5))
        assertTrue(eventually { model.thread.entries.map { it.seq } == listOf(1L, 2, 3, 4, 5) })
        assertEquals("grown 4", model.thread.entries.first { it.seq == 4L }.text)
        assertFalse(model.thread.entries.any { it.id == "web-5" })

        // Saved once the changes settle; closing the screen writes what came after at once.
        assertTrue(eventually { AgentThreadModel.SAVE_DELAY in timers.waiting })
        timers.release { it == AgentThreadModel.SAVE_DELAY }
        assertTrue(eventually { stored(s1, rig)?.entries?.size == 5 })
        mac.pushChat("s1", entries(6L..6))
        assertTrue(eventually { model.thread.entries.size == 6 })
        model.close().join()
        assertEquals((1L..6).toList(), stored(s1, rig)?.entries?.map { it.seq })
    } }

    @Test fun runAgainCatchesUpOnWhatCameWhileCovered() { runTest {
        val mac = mac(entries(1L..3))
        val s1 = ref(mac)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val (model, _) = model(s1, rig)

        // Shown, then covered by another screen: the screen's coroutine is cancelled.
        val first = launch { model.run() }
        assertTrue(eventually { model.thread.entries.size == 3 })
        first.cancelAndJoin()
        assertFalse(model.isObserving)

        // Meanwhile the agent writes two entries; they reach the phone before the screen is back.
        val probe = rig.hub.chatUpdates()
        mac.pushChat("s1", entries(4L..5))
        assertEquals(listOf(4L, 5), probe.first().entries.map { it.seq })
        assertEquals(3, model.thread.entries.size, "nobody follows the hub for the covered screen")

        // Shown again: the newest page brings them.
        assertTrue(startRunning(model))
        assertTrue(eventually { model.thread.entries.map { it.seq } == listOf(1L, 2, 3, 4, 5) })
        assertEquals(listOf<Long?>(null, null), mac.historyRequests.map { it.beforeSeq })
    } }

    @Test fun emptyFirstPageIsNoMessagesYetAndNotFoundIsGone() { runTest {
        // A new session whose transcript does not exist yet: the Mac answers an empty page.
        val mac = mac(emptyList())
        // A session the Mac lists but has no chat for: it answers `not_found`.
        mac.upsertSession(agentSession("s2", workspace = "web"))
        val s2 = ref(mac, "s2", workspace = "web")
        val cached = ChatThread(entries(40L..45), hasMore = true)
        val rig = hubRig(listOf(mac), seed = seedCopy(s2 to cached), start = true)
        assertTrue(rig.online(2))

        val (fresh, _) = model(ref(mac), rig)
        fresh.open()
        assertEquals(ChatThread(), fresh.thread, "no messages yet")
        assertFalse(fresh.loading)
        assertFalse(fresh.sessionGone)
        // The agent writes its first entries: they arrive live.
        assertTrue(startRunning(fresh))
        mac.pushChat("s1", entries(1L..2))
        assertTrue(eventually { fresh.thread.entries.map { it.seq } == listOf(1L, 2) })

        val (gone, _) = model(s2, rig)
        gone.open()
        assertTrue(gone.sessionGone)
        assertEquals(cached, gone.thread, "the copy on the phone still shows")
        // Gone on the Mac: no paging back.
        gone.loadOlder()
        assertEquals(listOf("s1", "s2"), mac.historyRequests.map { it.sessionId })
    } }

    /** The session the phone may remove (spec 6.8) is one its Mac still lists but answered `not_found` for: a live one
     *  never is, nor one the Mac's list leaves out (no list shows it). */
    @Test fun onlyAListedSessionTheMacAnsweredNotFoundForIsAGhost() { runTest {
        val mac = mac(entries(1L..2))
        // `s2` is listed as working, but the Mac has no chat for it: it answers `not_found`.
        mac.upsertSession(agentSession("s2", workspace = "web"))
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(2))

        val (live, _) = model(ref(mac), rig)
        live.open()
        assertFalse(live.sessionGone)
        assertNull(live.ghost, "a live session never is one")

        val (gone, _) = model(ref(mac, "s2", workspace = "web"), rig)
        assertNull(gone.ghost, "not before the Mac answered")
        gone.open()
        assertTrue(gone.sessionGone)
        assertEquals(gone.session, gone.ghost)
        assertEquals(AgentState.WORKING, gone.ghost?.session?.state, "still listed as working")

        // Gone from the Mac's list: gone too, but nothing lists it.
        val (unlisted, _) = model(ref(mac, "s9"), rig)
        assertTrue(unlisted.sessionGone)
        assertNull(unlisted.ghost)
    } }

    @Test fun emptyStateSaysWhatIsKnown() { runTest {
        val mac = mac(emptyList())
        mac.upsertSession(agentSession("s2", workspace = "web"))
        mac.setHistory("s2", emptyList())
        // The Swift test gives s2 one transcript line of 20 entries of 4 KB, more than one frame holds, so its Mac
        // answers `too_large` while the link stays up. The fake Mac has no frame limit: the session answers that
        // error itself until the history fits.
        val refusing = RefusingHistory("s2")
        val rig = hubRig(listOf(mac), connector = { refusing.wrap(it) }, start = true)
        assertTrue(rig.online(2))

        // Before the copy and the first page: loading, never "no messages yet".
        val (fresh, _) = model(ref(mac), rig)
        assertEquals(AgentThreadModel.EmptyState.LOADING, fresh.emptyState)
        mac.holdChat()
        val opening = launch { fresh.open() }
        assertTrue(eventually { fresh.loading })
        assertEquals(AgentThreadModel.EmptyState.LOADING, fresh.emptyState)
        mac.releaseChat()
        opening.join()
        assertEquals(AgentThreadModel.EmptyState.NO_MESSAGES, fresh.emptyState, "only after an empty first page")

        // The first page fails: say so, with a retry.
        val s2 = ref(mac, "s2", workspace = "web")
        val (failing, _) = model(s2, rig)
        failing.open()
        assertEquals(AgentThreadModel.EmptyState.FAILED, failing.emptyState)
        assertFalse(failing.sessionGone)
        mac.setHistory("s2", entries(1L..2))
        refusing.refuses = false
        failing.retry()
        assertNull(failing.emptyState)
        assertEquals(listOf(1L, 2), failing.thread.entries.map { it.seq })

        // Gone: a session the Mac has no chat for.
        mac.upsertSession(agentSession("s3", workspace = "relay"))
        val (gone, _) = model(ref(mac, "s3", workspace = "relay"), rig)
        gone.open()
        assertEquals(AgentThreadModel.EmptyState.GONE, gone.emptyState)
    } }

    @Test fun emptyStateWhileTheMacIsOffline() { runTest {
        val mac = mac(emptyList())
        mac.failNextConnects(IOException("offline"), 1_000)
        val rig = hubRig(listOf(mac), start = true)
        val (model, _) = model(ref(mac), rig)
        model.open()
        if (rig.hub.machines.firstOrNull()?.state is MachineLinkState.Offline) {
            assertEquals(AgentThreadModel.EmptyState.OFFLINE, model.emptyState, "no copy and an unreachable Mac")
        } else {
            assertEquals(AgentThreadModel.EmptyState.LOADING, model.emptyState, "still connecting")
        }
        assertTrue(eventually { rig.hub.machines.firstOrNull()?.state is MachineLinkState.Offline })
        assertEquals(AgentThreadModel.EmptyState.OFFLINE, model.emptyState)
    } }

    @Test fun olderRowHidesOfflineAndOffersRetryAfterAFailure() { runTest {
        val mac = mac(entries(1L..120))
        val s1 = ref(mac)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val (model, _) = model(s1, rig)
        model.open()
        assertEquals(AgentThreadModel.Older.LOADABLE, model.older)

        // The link dies while an older page is on its way.
        mac.holdChat()
        val loading = launch { model.loadOlder() }
        assertTrue(eventually { mac.historyRequests.size == 2 })
        mac.dropLiveSessions()
        loading.join()
        mac.releaseChat()
        assertTrue(eventually { model.offline })
        assertEquals(AgentThreadModel.Older.NONE, model.older, "no spinner that cannot load while offline")

        // Back online: a retry row, not a spinner that would ask again by itself.
        assertTrue(eventually { rig.backoff.waiting.isNotEmpty() })
        rig.backoff.release()
        assertTrue(eventually { !model.offline })
        assertEquals(AgentThreadModel.Older.FAILED, model.older)
        model.loadOlder()
        assertEquals(AgentThreadModel.Older.LOADABLE, model.older)
        assertEquals(21, model.thread.entries.first().seq)
    } }

    @Test fun closedScreenStopsWorkAndANewerScreenWins() { runTest {
        val mac = mac(entries(1L..3))
        val s1 = ref(mac)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val (first, firstTimers) = model(s1, rig)

        // Shown, then closed: closing writes the copy.
        val shown = launch { first.run() }
        assertTrue(eventually { first.thread.entries.size == 3 })
        shown.cancelAndJoin()
        first.close().join()
        assertEquals(listOf(1L, 2, 3), stored(s1, rig)?.entries?.map { it.seq })

        // Shown again, then closed before its catch-up page comes back.
        mac.setHistory("s1", entries(1L..4))
        mac.holdChat()
        val again = launch { first.run() }
        assertTrue(eventually { mac.historyRequests.size == 2 })
        again.cancel()
        first.close().join()
        mac.releaseChat()
        again.join()
        assertFalse(AgentThreadModel.SAVE_DELAY in firstTimers.waiting, "a closed screen schedules no save")
        assertEquals(listOf(1L, 2, 3), stored(s1, rig)?.entries?.map { it.seq })
        assertEquals(2, mac.historyRequests.size, "a cancelled run asks for nothing more")

        // Shown once more, a save still pending, when it is closed and the session opened again at once: the new
        // screen's writer wins, and the old screen's late write is dropped.
        val third = launch { first.run() }
        assertTrue(eventually { first.thread.entries.size == 4 })
        assertTrue(eventually { AgentThreadModel.SAVE_DELAY in firstTimers.waiting })
        mac.setHistory("s1", entries(1L..5))
        val (second, secondTimers) = model(s1, rig)
        second.open()
        assertEquals(listOf(1L, 2, 3, 4, 5), second.thread.entries.map { it.seq })
        assertTrue(eventually { AgentThreadModel.SAVE_DELAY in secondTimers.waiting })
        secondTimers.release { it == AgentThreadModel.SAVE_DELAY }
        assertTrue(eventually { stored(s1, rig)?.entries?.size == 5 })
        third.cancelAndJoin()
        first.close().join()
        assertEquals(listOf(1L, 2, 3, 4, 5), stored(s1, rig)?.entries?.map { it.seq }, "the old screen's late write is dropped")
        assertEquals(4, mac.historyRequests.size)
    } }

    // Transcript reset (chat.reset)

    /** Entries of a reloaded transcript: other ids and text than [entries], the same `seq` range. */
    private fun reloaded(seqs: LongRange): List<ChatEntry> = seqs.map {
        ChatEntry(
            id = "new-$it", rev = 1, seq = it, role = ChatEntryRole.AGENT, kind = ChatEntryKind.PROSE, text = "new $it",
            tsMs = 1_800_000_000_000 + it,
        )
    }

    @Test fun resetReplacesTheChatAndIgnoresAnswersStartedBefore() { runTest {
        val mac = mac(entries(1L..60, text = "old"))
        val s1 = ref(mac)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val (model, _) = model(s1, rig)

        // The newest page of the old transcript is on its way when the Mac reloads the transcript.
        mac.holdChat()
        assertTrue(startRunning(model))
        assertTrue(eventually { mac.historyRequests.size == 1 })
        mac.resetChat("s1", reloaded(1L..80))
        // The screen pages again from the newest at once.
        assertTrue(eventually { mac.historyRequests.size == 2 })
        assertEquals(listOf<Long?>(null, null), mac.historyRequests.map { it.beforeSeq })
        mac.releaseChat()

        // The old transcript's page, asked for before the reset, is dropped whichever comes first.
        assertTrue(
            eventually { model.thread.entries.map { it.id } == (31..80).map { "new-$it" } },
            "${model.thread.entries.map { it.id }.take(5)}",
        )
        assertTrue(model.thread.hasMore)
        assertFalse(model.loading)
        assertNull(model.emptyState)

        // Entries after the reset upsert as usual; paging back goes through the new transcript.
        mac.pushChat("s1", reloaded(81L..81))
        assertTrue(eventually { model.thread.entries.lastOrNull()?.id == "new-81" })
        model.loadOlder()
        assertEquals("new-1", model.thread.entries.first().id)
        assertFalse(model.thread.entries.any { it.id.startsWith("e-") }, "nothing of the old transcript is left")
    } }

    @Test fun resetDropsTheStoredCopyAndOtherSessionsResetsChangeNothing() { runTest {
        val mac = mac(entries(1L..5, text = "old"))
        mac.upsertSession(agentSession("s2", workspace = "web"))
        mac.setHistory("s2", emptyList())
        val s1 = ref(mac)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(2))
        val (model, timers) = model(s1, rig)
        assertTrue(startRunning(model))
        assertTrue(eventually { model.thread.entries.size == 5 })
        assertTrue(eventually { AgentThreadModel.SAVE_DELAY in timers.waiting })
        timers.release { it == AgentThreadModel.SAVE_DELAY }
        assertTrue(eventually { stored(s1, rig)?.entries?.size == 5 })

        // Another session's reset changes nothing here.
        mac.resetChat("s2", emptyList())
        mac.pushChat("s1", entries(6L..6, text = "old"))
        assertTrue(eventually { model.thread.entries.size == 6 }, "the s2 reset, sent before this push, was ignored")
        assertEquals(1, mac.historyRequests.size)

        // This session's reset: the stored copy goes at once, before the new page is in.
        mac.holdChat()
        mac.resetChat("s1", reloaded(1L..2))
        assertTrue(eventually { stored(s1, rig) == null }, "a relaunch must not show the old transcript")
        assertEquals(emptyList(), model.thread.entries)
        assertEquals(AgentThreadModel.EmptyState.LOADING, model.emptyState)
        mac.releaseChat()
        assertTrue(eventually { model.thread.entries.map { it.id } == listOf("new-1", "new-2") })
        model.close().join()
        assertEquals(listOf("new-1", "new-2"), stored(s1, rig)?.entries?.map { it.id })
        assertEquals(2, mac.historyRequests.size)
    } }

    /** No agent screen follows the session when its transcript is reset: the stored copy still goes, so opening the
     *  screen later shows the new transcript only. */
    @Test fun resetWithNoScreenOpenDropsTheStoredCopy() { runTest {
        val mac = mac(entries(1L..300, text = "old"))
        val s1 = ref(mac)
        val cached = ChatThread(entries(1L..300, text = "old"), hasMore = false)
        val other = ref(mac, "s-other")
        val rig = hubRig(listOf(mac), seed = seedCopy(s1 to cached, other to cached), start = true)
        assertTrue(rig.online(1))
        // The sweeper follows the hub for the whole sign-in, as the signed-in screen runs it.
        val sweeper = ChatCopySweeper(rig.hub, rig.store)
        backgroundScope.launch { sweeper.run() }
        assertTrue(eventually { rig.hub.chatSubscriberCount == 1 })

        // The Mac reloads the transcript (a resume or /compact): its seq starts over.
        mac.resetChat("s1", reloaded(1L..20))
        assertTrue(eventually { stored(s1, rig) == null }, "the old transcript's copy goes although no screen follows the session")
        assertEquals(cached, stored(other, rig), "another session's copy stays")

        val (model, _) = model(s1, rig)
        assertTrue(startRunning(model))
        assertTrue(
            eventually { model.thread.entries.map { it.id } == (1..20).map { "new-$it" } },
            "${model.thread.entries.map { it.id }.takeLast(3)}, ${model.thread.entries.size} entries",
        )
        assertFalse(model.thread.entries.any { it.id.startsWith("e-") }, "nothing of the old transcript is left")
    } }

    /** The screen is covered (its coroutine cancelled, then closed) when the transcript is reset: shown again, it
     *  replaces its copy instead of merging the new transcript into the old one. */
    @Test fun resetWhileCoveredReplacesTheCopyWhenShownAgain() { runTest {
        val mac = mac(entries(1L..60, text = "old"))
        val s1 = ref(mac)
        val rig = hubRig(listOf(mac), start = true)
        assertTrue(rig.online(1))
        val (model, _) = model(s1, rig)
        val first = launch { model.run() }
        assertTrue(eventually { model.thread.entries.map { it.seq } == (11L..60).toList() })
        // Covered: the screen's coroutine is cancelled, and the screen closes the model.
        first.cancelAndJoin()
        model.close().join()

        val probe = rig.hub.chatUpdates()
        mac.resetChat("s1", reloaded(1L..20))
        assertEquals(ChatUpdate.Reset(s1), probe.first())
        assertEquals(50, model.thread.entries.size, "nobody follows the hub for the covered screen")

        // Shown again: only the new transcript.
        assertTrue(startRunning(model))
        assertTrue(
            eventually { model.thread.entries.map { it.id } == (1..20).map { "new-$it" } },
            "${model.thread.entries.map { it.id }.takeLast(3)}, ${model.thread.entries.size} entries",
        )
        model.close().join()
        assertEquals((1..20).map { "new-$it" }, stored(s1, rig)?.entries?.map { it.id }, "the stored copy is the new transcript's")
    } }

    // Offline and pending

    @Test fun offlineOpenShowsCacheAndOffline() { runTest {
        val mac = mac(entries(1L..3, text = "fresh", rev = 2))
        val s1 = ref(mac)
        val cached = ChatThread(entries(1L..2, text = "cached"), hasMore = false)
        mac.failNextConnects(IOException("offline"), 1_000)
        val rig = hubRig(listOf(mac), seed = seedCopy(s1 to cached), start = true)
        assertTrue(eventually { rig.hub.machines.firstOrNull()?.state is MachineLinkState.Offline })
        val (model, _) = model(s1, rig)

        model.open()

        assertTrue(model.offline)
        assertFalse(model.loading)
        assertEquals(cached, model.thread)
        assertNull(model.emptyState, "the copy shows")
        assertFalse(model.sessionGone, "an offline Mac's silence says nothing about the session")
        assertEquals(emptyList(), mac.historyRequests)

        // The Mac comes back while the screen is open: its newest page loads.
        assertTrue(startRunning(model))
        mac.failNextConnects(IOException("offline"), 0)
        assertTrue(eventually { rig.backoff.waiting.isNotEmpty() })
        rig.backoff.release()
        assertTrue(eventually { !model.offline && model.thread.entries.map { it.rev } == listOf(2L, 2, 2) })
        assertEquals(listOf(1L, 2, 3), model.thread.entries.map { it.seq })
        assertEquals(listOf<Long?>(null), mac.historyRequests.map { it.beforeSeq })

        // A drop and a return while open: the page is read again, for what was missed meanwhile.
        mac.dropLiveSessions()
        assertTrue(eventually { model.offline })
        mac.setHistory("s1", entries(1L..4, text = "fresh", rev = 2))
        assertTrue(eventually { rig.backoff.waiting.isNotEmpty() })
        rig.backoff.release()
        assertTrue(eventually { model.thread.entries.map { it.seq } == listOf(1L, 2, 3, 4) })
    } }

    @Test fun pendingHereFiltersByWorkspace() { runTest {
        val first = FakeMac("MacBook Pro", backgroundScope)
        first.upsertSession(agentSession("s1", workspace = "shellx"))
        first.upsertSession(agentSession("s2", workspace = "web"))
        first.addPending(pendingItem("p1", createdAtMs = 1, workspace = "shellx"))
        first.addPending(pendingItem("p2", createdAtMs = 2, workspace = "web"))
        first.addPending(pendingItem("p3", createdAtMs = 3, workspace = "shellx"))
        // Another Mac with a workspace of the same id.
        val second = FakeMac("Mac mini", backgroundScope)
        second.upsertSession(agentSession("s1", workspace = "shellx"))
        second.addPending(pendingItem("p4", createdAtMs = 0, workspace = "shellx"))
        val rig = hubRig(listOf(first, second), start = true)
        assertTrue(
            eventually {
                rig.hub.machines.all { it.state == MachineLinkState.Online } && rig.hub.liveSessions.size == 3 &&
                    rig.hub.pendingItems.size == 4
            },
        )

        val (shellx, _) = model(ref(first, "s1"), rig)
        val (web, _) = model(ref(first, "s2", workspace = "web"), rig)
        val (other, _) = model(ref(second, "s1"), rig)

        assertEquals(listOf("p1", "p3"), shellx.pendingHere.map { it.item.requestId })
        assertEquals(listOf("p2"), web.pendingHere.map { it.item.requestId })
        // The agent's "Needs You" page picks the same requests with isIn.
        val workspaceId = assertNotNull(shellx.session?.session?.workspaceId)
        val page = rig.hub.pendingItems.filter { it.isIn(first.machine.machineId, workspaceId) }
        assertEquals(listOf("p1", "p3"), page.map { it.item.requestId }.sorted())
        assertEquals(listOf("p4"), other.pendingHere.map { it.item.requestId })

        // Handled on the Mac: gone here too.
        first.resolvePending("p1")
        assertTrue(eventually { shellx.pendingHere.map { it.item.requestId } == listOf("p3") })
    } }
}

/**
 * A connector whose sessions answer `chat.history` for [sessionId] with the Mac's `too_large` error while [refuses]
 * holds: a Mac error that leaves the link up.
 */
private class RefusingHistory(private val sessionId: String) {
    @Volatile var refuses = true

    fun wrap(base: MachineLinkConnecting): MachineLinkConnecting = MachineLinkConnecting { machine ->
        val session = base.connect(machine)
        object : LinkSession by session {
            override suspend fun chatHistory(sessionId: String, beforeSeq: Long?, limit: Int): ChatHistoryPage {
                if (refuses && sessionId == this@RefusingHistory.sessionId) {
                    throw LinkClientException.Remote("too_large", "the page is larger than a frame")
                }
                return session.chatHistory(sessionId, beforeSeq, limit)
            }
        }
    }
}
