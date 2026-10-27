import Foundation
import ShellXAppTestSupport
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// One agent's detail screen: the chat copy shown from the phone at once, then the Mac's newest
/// page, older pages on demand, live entries, sending, Stop and Force stop, and the pending items of
/// the session's workspace.
@MainActor
final class AgentThreadModelTests: XCTestCase {
    private func ref(_ mac: FakeMac, _ sessionId: String = "s1", workspace: String = "shellx") -> SessionRef {
        SessionRef(machineID: mac.machine.machineID, sessionId: sessionId, agent: "claude", workspaceTitle: workspace)
    }

    /// A Mac with one working session `s1` whose transcript holds `history`.
    private func mac(history: [ChatEntry], name: String = "MacBook Pro") async -> FakeMac {
        let mac = FakeMac(name: name)
        await mac.upsertSession(agentSession("s1"))
        await mac.setHistory(sessionId: "s1", entries: history)
        return mac
    }

    private func entries(_ seqs: ClosedRange<Int>, text: String? = nil, rev: Int = 1) -> [ChatEntry] {
        seqs.map { seq in
            ChatEntry(
                id: "e-\(seq)", rev: rev, seq: seq, role: .agent, kind: .prose, text: "\(text ?? "entry") \(seq)",
                tsMs: 1_700_000_000_000 + Int64(seq))
        }
    }

    /// The model's waits (the 0.5 s save) wait on the returned sleeper.
    private func model(_ ref: SessionRef, _ rig: HomeRig) -> (AgentThreadModel, ManualSleeper) {
        let timers = ManualSleeper()
        let model = AgentThreadModel(ref: ref, hub: rig.hub, store: rig.store, sleep: timers.sleep)
        addTeardownBlock { @MainActor in await model.close() }
        return (model, timers)
    }

    /// Runs `model.run()` until the test ends; returns once it follows the hub.
    private func startRunning(_ model: AgentThreadModel) async -> Bool {
        let task = Task { await model.run() }
        addTeardownBlock { task.cancel() }
        return await eventually { model.isObserving }
    }

    private func stored(_ ref: SessionRef, _ rig: HomeRig) async -> ChatThread? {
        await rig.store.load(.thread(ref), as: ChatThread.self)
    }

    // MARK: - History

    func testOpenShowsCacheThenLatest() async throws {
        let mac = await mac(history: entries(1...30, rev: 2))
        let s1 = ref(mac)
        let cached = ChatThread(entries: entries(1...5, text: "cached"), hasMore: false)
        let rig = try await HomeRig.make(
            [mac], in: self, seed: { await $0.writer().save(cached, to: .thread(s1)) }, loads: false)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let (model, timers) = model(s1, rig)
        XCTAssertEqual(model.thread, ChatThread(), "nothing before open()")

        await mac.holdChat()
        let opening = Task { await model.open() }
        let showsCache = await eventually { model.thread == cached && model.loading }
        XCTAssertTrue(showsCache, "the copy on the phone shows while the Mac's page is on its way")
        let asked = await eventually { await mac.historyRequests.count == 1 }
        XCTAssertTrue(asked)
        await mac.releaseChat()
        await opening.value

        XCTAssertFalse(model.loading)
        XCTAssertEqual(model.thread.entries.map(\.seq), Array(1...30))
        XCTAssertEqual(model.thread.entries.map(\.rev), Array(repeating: 2, count: 30), "the Mac's newer revisions win")
        XCTAssertFalse(model.thread.hasMore)
        let requests = await mac.historyRequests
        XCTAssertEqual(requests, [FakeMac.HistoryRequest(sessionId: "s1", beforeSeq: nil, limit: 50)])

        // The new copy is written at most `saveDelay` after the change.
        let waiting = await eventually { timers.waiting.contains(AgentThreadModel.saveDelay) }
        XCTAssertTrue(waiting)
        XCTAssertEqual(AgentThreadModel.saveDelay, .milliseconds(500))
        let before = await stored(s1, rig)
        XCTAssertEqual(before, cached)
        timers.release { $0 == AgentThreadModel.saveDelay }
        let saved = await eventually { await self.stored(s1, rig) == model.thread }
        XCTAssertTrue(saved)

        // Opening again does not ask twice.
        await model.open()
        let after = await mac.historyRequests
        XCTAssertEqual(after.count, 1)
    }

    func testLoadOlderUsesSmallestSeq() async throws {
        let mac = await mac(history: entries(1...120))
        let s1 = ref(mac)
        let rig = try await HomeRig.make([mac], in: self, loads: false)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let (model, _) = model(s1, rig)

        await model.open()
        XCTAssertEqual(model.thread.entries.map(\.seq), Array(71...120))
        XCTAssertTrue(model.thread.hasMore)

        await model.loadOlder()
        XCTAssertEqual(model.thread.entries.map(\.seq), Array(21...120))
        XCTAssertTrue(model.thread.hasMore)
        await model.loadOlder()
        XCTAssertEqual(model.thread.entries.map(\.seq), Array(1...120))
        XCTAssertFalse(model.thread.hasMore)
        XCTAssertFalse(model.loadingOlder)

        // Nothing older: no call.
        await model.loadOlder()
        let requests = await mac.historyRequests
        XCTAssertEqual(requests.map(\.beforeSeq), [nil, 71, 21])
        XCTAssertEqual(requests.map(\.limit), [50, 50, 50])
    }

    func testLoadOlderStopsAtThePhonesCap() async throws {
        let mac = await mac(history: entries(1...700))
        let s1 = ref(mac)
        let rig = try await HomeRig.make([mac], in: self, loads: false)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let (model, _) = model(s1, rig)
        await model.open()
        for _ in 0..<12 { await model.loadOlder() }

        XCTAssertEqual(model.thread.entries.count, ChatThread.maxEntries)
        XCTAssertEqual(model.thread.entries.last?.seq, 700, "the newest entries are the ones kept")
        XCTAssertTrue(model.thread.hasMore)
        XCTAssertTrue(model.olderOnlyOnMac)
        XCTAssertEqual(model.older, .onlyOnMac)
        let requests = await mac.historyRequests
        XCTAssertEqual(requests.count, 10, "the newest page, then nine older pages up to the cap, then no more calls")
    }

    func testLiveEntriesAppendWhileOpen() async throws {
        let mac = await mac(history: entries(1...3))
        await mac.upsertSession(agentSession("s2", workspace: "web"))
        await mac.setHistory(sessionId: "s2", entries: [])
        let s1 = ref(mac)
        let rig = try await HomeRig.make([mac], in: self, loads: false)
        let online = await rig.online(sessions: 2)
        XCTAssertTrue(online)
        let (model, timers) = model(s1, rig)

        let running = await startRunning(model)
        XCTAssertTrue(running)
        let opened = await eventually { model.thread.entries.map(\.seq) == [1, 2, 3] }
        XCTAssertTrue(opened, "run() opens the screen's history")

        await mac.pushChat(sessionId: "s1", entries: entries(4...4))
        let appended = await eventually { model.thread.entries.map(\.seq) == [1, 2, 3, 4] }
        XCTAssertTrue(appended)

        // The entry grows in place (a higher rev); another session's entries never show here.
        await mac.pushChat(
            sessionId: "s2",
            entries: [ChatEntry(id: "web-5", rev: 1, seq: 5, role: .agent, kind: .prose, text: "web", tsMs: 1)])
        await mac.pushChat(sessionId: "s1", entries: entries(4...4, text: "grown", rev: 2) + entries(5...5))
        let grown = await eventually { model.thread.entries.map(\.seq) == [1, 2, 3, 4, 5] }
        XCTAssertTrue(grown)
        XCTAssertEqual(model.thread.entries.first { $0.seq == 4 }?.text, "grown 4")
        XCTAssertFalse(model.thread.entries.contains { $0.id == "web-5" })

        // Saved once the changes settle; closing the screen writes what came after at once.
        let waiting = await eventually { timers.waiting.contains(AgentThreadModel.saveDelay) }
        XCTAssertTrue(waiting)
        timers.release { $0 == AgentThreadModel.saveDelay }
        let saved = await eventually { await self.stored(s1, rig)?.entries.count == 5 }
        XCTAssertTrue(saved)
        await mac.pushChat(sessionId: "s1", entries: entries(6...6))
        let six = await eventually { model.thread.entries.count == 6 }
        XCTAssertTrue(six)
        await model.close()
        let closed = await stored(s1, rig)
        XCTAssertEqual(closed?.entries.map(\.seq), Array(1...6))
    }

    func testRunAgainCatchesUpOnWhatCameWhileCovered() async throws {
        let mac = await mac(history: entries(1...3))
        let s1 = ref(mac)
        let rig = try await HomeRig.make([mac], in: self, loads: false)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let (model, _) = model(s1, rig)

        // Shown, then covered by another screen: SwiftUI cancels the screen's task.
        let first = Task { await model.run() }
        let opened = await eventually { model.thread.entries.count == 3 }
        XCTAssertTrue(opened)
        first.cancel()
        await first.value
        XCTAssertFalse(model.isObserving)

        // Meanwhile the agent writes two entries; they reach the phone before the screen is back.
        var probe = rig.hub.chatUpdates().makeAsyncIterator()
        await mac.pushChat(sessionId: "s1", entries: entries(4...5))
        let arrived = await probe.next()
        XCTAssertEqual(arrived?.entries.map(\.seq), [4, 5])
        XCTAssertEqual(model.thread.entries.count, 3, "nobody follows the hub for the covered screen")

        // Shown again: the newest page brings them.
        let running = await startRunning(model)
        XCTAssertTrue(running)
        let caughtUp = await eventually { model.thread.entries.map(\.seq) == [1, 2, 3, 4, 5] }
        XCTAssertTrue(caughtUp)
        let requests = await mac.historyRequests
        XCTAssertEqual(requests.map(\.beforeSeq), [nil, nil])
    }

    func testEmptyFirstPageIsNoMessagesYetAndNotFoundIsGone() async throws {
        // A new session whose transcript does not exist yet: the Mac answers an empty page.
        let mac = await mac(history: [])
        // A session the Mac lists but has no chat for: it answers `not_found`.
        await mac.upsertSession(agentSession("s2", workspace: "web"))
        let s2 = ref(mac, "s2", workspace: "web")
        let cached = ChatThread(entries: entries(40...45), hasMore: true)
        let rig = try await HomeRig.make(
            [mac], in: self, seed: { await $0.writer().save(cached, to: .thread(s2)) }, loads: false)
        let online = await rig.online(sessions: 2)
        XCTAssertTrue(online)

        let (fresh, _) = model(ref(mac), rig)
        await fresh.open()
        XCTAssertEqual(fresh.thread, ChatThread(), "no messages yet")
        XCTAssertFalse(fresh.loading)
        XCTAssertFalse(fresh.sessionGone)
        // The agent writes its first entries: they arrive live.
        let running = await startRunning(fresh)
        XCTAssertTrue(running)
        await mac.pushChat(sessionId: "s1", entries: entries(1...2))
        let filled = await eventually { fresh.thread.entries.map(\.seq) == [1, 2] }
        XCTAssertTrue(filled)

        let (gone, _) = model(s2, rig)
        await gone.open()
        XCTAssertTrue(gone.sessionGone)
        XCTAssertEqual(gone.thread, cached, "the copy on the phone still shows")
        // Gone on the Mac: no paging back.
        await gone.loadOlder()
        let requests = await mac.historyRequests
        XCTAssertEqual(requests.map(\.sessionId), ["s1", "s2"])
    }

    func testEmptyStateSaysWhatIsKnown() async throws {
        let mac = await mac(history: [])
        // One transcript line of 20 entries of 4 KB: more than one frame holds, so the Mac answers
        // `too_large` while the link stays up.
        let big = String(repeating: "a", count: ChatEntry.maxTextBytes)
        await mac.upsertSession(agentSession("s2", workspace: "web"))
        await mac.setHistory(
            sessionId: "s2",
            entries: (1...20).map {
                ChatEntry(id: "big-\($0)", rev: 1, seq: 1, role: .agent, kind: .prose, text: big, tsMs: 1)
            })
        let rig = try await HomeRig.make([mac], in: self, loads: false)
        let online = await rig.online(sessions: 2)
        XCTAssertTrue(online)

        // Before the copy and the first page: loading, never "no messages yet".
        let (fresh, _) = model(ref(mac), rig)
        XCTAssertEqual(fresh.emptyState, .loading)
        await mac.holdChat()
        let opening = Task { await fresh.open() }
        let waiting = await eventually { fresh.loading }
        XCTAssertTrue(waiting)
        XCTAssertEqual(fresh.emptyState, .loading)
        await mac.releaseChat()
        await opening.value
        XCTAssertEqual(fresh.emptyState, .noMessages, "only after an empty first page")

        // The first page fails: say so, with a retry.
        let s2 = ref(mac, "s2", workspace: "web")
        let (failing, _) = model(s2, rig)
        await failing.open()
        XCTAssertEqual(failing.emptyState, .failed)
        XCTAssertFalse(failing.sessionGone)
        await mac.setHistory(sessionId: "s2", entries: entries(1...2))
        await failing.retry()
        XCTAssertNil(failing.emptyState)
        XCTAssertEqual(failing.thread.entries.map(\.seq), [1, 2])

        // Gone: a session the Mac has no chat for.
        await mac.upsertSession(agentSession("s3", workspace: "relay"))
        let (gone, _) = model(ref(mac, "s3", workspace: "relay"), rig)
        await gone.open()
        XCTAssertEqual(gone.emptyState, .gone)
    }

    func testEmptyStateWhileTheMacIsOffline() async throws {
        let mac = await mac(history: [])
        await mac.failNextConnects(URLError(.notConnectedToInternet), count: 1_000)
        let rig = try await HomeRig.make([mac], in: self, loads: false)
        let (model, _) = model(ref(mac), rig)
        await model.open()
        if case .offline = rig.hub.machines.first?.state {
            XCTAssertEqual(model.emptyState, .offline, "no copy and an unreachable Mac")
        } else {
            XCTAssertEqual(model.emptyState, .loading, "still connecting")
        }
        let unreachable = await eventually {
            if case .offline = rig.hub.machines.first?.state { return true }
            return false
        }
        XCTAssertTrue(unreachable)
        XCTAssertEqual(model.emptyState, .offline)
    }

    func testOlderRowHidesOfflineAndOffersRetryAfterAFailure() async throws {
        let mac = await mac(history: entries(1...120))
        let s1 = ref(mac)
        let rig = try await HomeRig.make([mac], in: self, loads: false)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let (model, _) = model(s1, rig)
        await model.open()
        XCTAssertEqual(model.older, .loadable)

        // The link dies while an older page is on its way.
        await mac.holdChat()
        let loading = Task { await model.loadOlder() }
        let asked = await eventually { await mac.historyRequests.count == 2 }
        XCTAssertTrue(asked)
        let drop = Task { await mac.dropLiveSessions() }
        await loading.value
        await mac.releaseChat()
        await drop.value
        let down = await eventually { model.offline }
        XCTAssertTrue(down)
        XCTAssertEqual(model.older, .none, "no spinner that cannot load while offline")

        // Back online: a retry row, not a spinner that would ask again by itself.
        let retrying = await eventually { !rig.backoff.waiting.isEmpty }
        XCTAssertTrue(retrying)
        rig.backoff.release()
        let back = await eventually { !model.offline }
        XCTAssertTrue(back)
        XCTAssertEqual(model.older, .failed)
        await model.loadOlder()
        XCTAssertEqual(model.older, .loadable)
        XCTAssertEqual(model.thread.entries.first?.seq, 21)
    }

    func testClosedScreenStopsWorkAndANewerScreenWins() async throws {
        let mac = await mac(history: entries(1...3))
        let s1 = ref(mac)
        let rig = try await HomeRig.make([mac], in: self, loads: false)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let (first, firstTimers) = model(s1, rig)

        // Shown, then closed: closing writes the copy.
        let shown = Task { await first.run() }
        let opened = await eventually { first.thread.entries.count == 3 }
        XCTAssertTrue(opened)
        shown.cancel()
        await shown.value
        await first.close()
        var stored = await stored(s1, rig)
        XCTAssertEqual(stored?.entries.map(\.seq), [1, 2, 3])

        // Shown again, then closed before its catch-up page comes back.
        await mac.setHistory(sessionId: "s1", entries: entries(1...4))
        await mac.holdChat()
        let again = Task { await first.run() }
        let asked = await eventually { await mac.historyRequests.count == 2 }
        XCTAssertTrue(asked)
        again.cancel()
        await first.close()
        await mac.releaseChat()
        await again.value
        XCTAssertFalse(firstTimers.waiting.contains(AgentThreadModel.saveDelay), "a closed screen schedules no save")
        stored = await self.stored(s1, rig)
        XCTAssertEqual(stored?.entries.map(\.seq), [1, 2, 3])
        var requests = await mac.historyRequests
        XCTAssertEqual(requests.count, 2, "a cancelled run asks for nothing more")

        // Shown once more, a save still pending, when it is popped and the session pushed again at
        // once: the new screen's writer wins, and the old screen's late write is dropped.
        let third = Task { await first.run() }
        let caughtUp = await eventually { first.thread.entries.count == 4 }
        XCTAssertTrue(caughtUp)
        let unsaved = await eventually { firstTimers.waiting.contains(AgentThreadModel.saveDelay) }
        XCTAssertTrue(unsaved)
        await mac.setHistory(sessionId: "s1", entries: entries(1...5))
        let (second, secondTimers) = model(s1, rig)
        await second.open()
        XCTAssertEqual(second.thread.entries.map(\.seq), [1, 2, 3, 4, 5])
        let pending = await eventually { secondTimers.waiting.contains(AgentThreadModel.saveDelay) }
        XCTAssertTrue(pending)
        secondTimers.release { $0 == AgentThreadModel.saveDelay }
        let saved = await eventually { await self.stored(s1, rig)?.entries.count == 5 }
        XCTAssertTrue(saved)
        third.cancel()
        await third.value
        await first.close()
        stored = await self.stored(s1, rig)
        XCTAssertEqual(stored?.entries.map(\.seq), [1, 2, 3, 4, 5], "the old screen's late write is dropped")
        requests = await mac.historyRequests
        XCTAssertEqual(requests.count, 4)
    }

    // MARK: - Transcript reset (chat.reset)

    /// Entries of a reloaded transcript: other ids and text than `entries(_:)`, the same `seq` range.
    private func reloaded(_ seqs: ClosedRange<Int>) -> [ChatEntry] {
        seqs.map {
            ChatEntry(
                id: "new-\($0)", rev: 1, seq: $0, role: .agent, kind: .prose, text: "new \($0)",
                tsMs: 1_800_000_000_000 + Int64($0))
        }
    }

    func testResetReplacesTheChatAndIgnoresAnswersStartedBefore() async throws {
        let mac = await mac(history: entries(1...60, text: "old"))
        let s1 = ref(mac)
        let rig = try await HomeRig.make([mac], in: self, loads: false)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let (model, _) = model(s1, rig)

        // The newest page of the old transcript is on its way when the Mac reloads the transcript.
        await mac.holdChat()
        let running = await startRunning(model)
        XCTAssertTrue(running)
        let asked = await eventually { await mac.historyRequests.count == 1 }
        XCTAssertTrue(asked)
        await mac.resetChat(sessionId: "s1", entries: reloaded(1...80))
        // The screen pages again from the newest at once.
        let again = await eventually { await mac.historyRequests.count == 2 }
        XCTAssertTrue(again)
        let requests = await mac.historyRequests
        XCTAssertEqual(requests.map(\.beforeSeq), [nil, nil])
        await mac.releaseChat()

        // The old transcript's page, asked for before the reset, is dropped whichever comes first.
        let fresh = await eventually { model.thread.entries.map(\.id) == (31...80).map { "new-\($0)" } }
        XCTAssertTrue(fresh, "\(model.thread.entries.map(\.id).prefix(5))")
        XCTAssertTrue(model.thread.hasMore)
        XCTAssertFalse(model.loading)
        XCTAssertNil(model.emptyState)

        // Entries after the reset upsert as usual; paging back goes through the new transcript.
        await mac.pushChat(sessionId: "s1", entries: reloaded(81...81))
        let live = await eventually { model.thread.entries.last?.id == "new-81" }
        XCTAssertTrue(live)
        await model.loadOlder()
        XCTAssertEqual(model.thread.entries.first?.id, "new-1")
        XCTAssertFalse(model.thread.entries.contains { $0.id.hasPrefix("e-") }, "nothing of the old transcript is left")
    }

    func testResetDropsTheStoredCopyAndOtherSessionsResetsChangeNothing() async throws {
        let mac = await mac(history: entries(1...5, text: "old"))
        await mac.upsertSession(agentSession("s2", workspace: "web"))
        await mac.setHistory(sessionId: "s2", entries: [])
        let s1 = ref(mac)
        let rig = try await HomeRig.make([mac], in: self, loads: false)
        let online = await rig.online(sessions: 2)
        XCTAssertTrue(online)
        let (model, timers) = model(s1, rig)
        let running = await startRunning(model)
        XCTAssertTrue(running)
        let opened = await eventually { model.thread.entries.count == 5 }
        XCTAssertTrue(opened)
        let pending = await eventually { timers.waiting.contains(AgentThreadModel.saveDelay) }
        XCTAssertTrue(pending)
        timers.release { $0 == AgentThreadModel.saveDelay }
        let saved = await eventually { await self.stored(s1, rig)?.entries.count == 5 }
        XCTAssertTrue(saved)

        // Another session's reset changes nothing here.
        await mac.resetChat(sessionId: "s2", entries: [])
        await mac.pushChat(sessionId: "s1", entries: entries(6...6, text: "old"))
        let six = await eventually { model.thread.entries.count == 6 }
        XCTAssertTrue(six, "the s2 reset, sent before this push, was ignored")
        var requests = await mac.historyRequests
        XCTAssertEqual(requests.count, 1)

        // This session's reset: the stored copy goes at once, before the new page is in.
        await mac.holdChat()
        await mac.resetChat(sessionId: "s1", entries: reloaded(1...2))
        let dropped = await eventually { await self.stored(s1, rig) == nil }
        XCTAssertTrue(dropped, "a relaunch must not show the old transcript")
        XCTAssertEqual(model.thread.entries, [])
        XCTAssertEqual(model.emptyState, .loading)
        await mac.releaseChat()
        let fresh = await eventually { model.thread.entries.map(\.id) == ["new-1", "new-2"] }
        XCTAssertTrue(fresh)
        await model.close()
        let stored = await stored(s1, rig)
        XCTAssertEqual(stored?.entries.map(\.id), ["new-1", "new-2"])
        requests = await mac.historyRequests
        XCTAssertEqual(requests.count, 2)
    }

    /// No agent screen follows the session when its transcript is reset (final review, Important 2):
    /// the stored copy still goes, so opening the screen later shows the new transcript only.
    func testResetWithNoScreenOpenDropsTheStoredCopy() async throws {
        let mac = await mac(history: entries(1...300, text: "old"))
        let s1 = ref(mac)
        let cached = ChatThread(entries: entries(1...300, text: "old"), hasMore: false)
        let rig = try await HomeRig.make([mac], in: self, seed: { await $0.writer().save(cached, to: .thread(s1)) })
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        // The home follows the hub for the whole sign-in, as `SignedInView` runs it.
        let homeRunning = await rig.startRunning(in: self)
        XCTAssertTrue(homeRunning)

        // The Mac reloads the transcript (a resume or /compact): its seq starts over.
        await mac.resetChat(sessionId: "s1", entries: reloaded(1...20))
        let dropped = await eventually { await self.stored(s1, rig) == nil }
        XCTAssertTrue(dropped, "the old transcript's copy goes although no screen follows the session")

        let (model, _) = model(s1, rig)
        let running = await startRunning(model)
        XCTAssertTrue(running)
        let fresh = await eventually { model.thread.entries.map(\.id) == (1...20).map { "new-\($0)" } }
        XCTAssertTrue(fresh, "\(model.thread.entries.map(\.id).suffix(3)), \(model.thread.entries.count) entries")
        XCTAssertFalse(model.thread.entries.contains { $0.id.hasPrefix("e-") }, "nothing of the old transcript is left")
    }

    /// The screen is covered (its task cancelled, then closed) when the transcript is reset: shown
    /// again, it replaces its copy instead of merging the new transcript into the old one.
    func testResetWhileCoveredReplacesTheCopyWhenShownAgain() async throws {
        let mac = await mac(history: entries(1...60, text: "old"))
        let s1 = ref(mac)
        let rig = try await HomeRig.make([mac], in: self, loads: false)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let (model, _) = model(s1, rig)
        let first = Task { await model.run() }
        let opened = await eventually { model.thread.entries.map(\.seq) == Array(11...60) }
        XCTAssertTrue(opened)
        // Covered: SwiftUI cancels the screen's task, and its onDisappear closes the model.
        first.cancel()
        await first.value
        await model.close()

        var probe = rig.hub.chatUpdates().makeAsyncIterator()
        await mac.resetChat(sessionId: "s1", entries: reloaded(1...20))
        let arrived = await probe.next()
        XCTAssertEqual(arrived, .reset(s1))
        XCTAssertEqual(model.thread.entries.count, 50, "nobody follows the hub for the covered screen")

        // Shown again: only the new transcript.
        let running = await startRunning(model)
        XCTAssertTrue(running)
        let fresh = await eventually { model.thread.entries.map(\.id) == (1...20).map { "new-\($0)" } }
        XCTAssertTrue(fresh, "\(model.thread.entries.map(\.id).suffix(3)), \(model.thread.entries.count) entries")
        await model.close()
        let stored = await stored(s1, rig)
        XCTAssertEqual(stored?.entries.map(\.id), (1...20).map { "new-\($0)" }, "the stored copy is the new transcript's")
    }

    // MARK: - Send and stop

    func testSendMapsOutcomes() async throws {
        let mac = await mac(history: [])
        let s1 = ref(mac)
        let rig = try await HomeRig.make([mac], in: self, loads: false)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let (model, _) = model(s1, rig)

        // Refused on the phone: nothing leaves it.
        var result = await model.send(" \n ", viaVoice: false)
        XCTAssertEqual(result, .refused(.empty))
        let long = String(repeating: "a", count: ComposerValidation.maxBytes + 1)
        result = await model.send(long, viaVoice: true)
        XCTAssertEqual(result, .refused(.tooLong(bytes: 16_385)))
        var sent = await mac.sentTexts
        XCTAssertEqual(sent, [])

        result = await model.send("  Chạy lại test giúp mình \n", viaVoice: false)
        XCTAssertEqual(result, .sent(.submitted))
        sent = await mac.sentTexts
        XCTAssertEqual(sent, [FakeMac.SentText(sessionId: "s1", text: "Chạy lại test giúp mình")])

        for outcome in [ChatSendOutcome.busy, .failed, .other("rate_limited")] {
            await mac.setSendOutcome(outcome)
            result = await model.send("Thử lại", viaVoice: false)
            XCTAssertEqual(result, .sent(outcome))
        }
        XCTAssertFalse(model.sessionGone)
        await mac.setSendOutcome(.notFound)
        result = await model.send("Còn đó không?", viaVoice: false)
        XCTAssertEqual(result, .sent(.notFound))
        XCTAssertTrue(model.sessionGone, "the Mac said the session is gone")
        await mac.setSendOutcome(nil)

        // The link dies before the answer: it is unknown whether the text arrived.
        await mac.holdChat()
        let pending = Task { await model.send("Đang gửi", viaVoice: false) }
        let asked = await eventually { await mac.sentTexts.count == 6 }
        XCTAssertTrue(asked)
        let drop = Task { await mac.dropLiveSessions() }
        result = await pending.value
        XCTAssertEqual(result, .noAnswer)
        await mac.releaseChat()
        await drop.value

        // Offline: answered at once, nothing sent or queued.
        let down = await eventually { model.offline }
        XCTAssertTrue(down)
        result = await model.send("Có ai không?", viaVoice: false)
        XCTAssertEqual(result, .offline)
        sent = await mac.sentTexts
        XCTAssertEqual(sent.count, 6)

        // Only a text the Mac surely did not take goes back into the composer.
        XCTAssertEqual(
            [AgentSendResult.offline, .refused(.tooLong(bytes: 16_385)), .sent(.busy), .sent(.failed),
             .sent(.notFound), .sent(.other("x"))].map(\.keepsDraft),
            [true, true, true, true, true, true])
        XCTAssertEqual(
            [AgentSendResult.sent(.submitted), .noAnswer, .refused(.empty)].map(\.keepsDraft), [false, false, false])
    }

    func testStopSoftAndHard() async throws {
        let mac = await mac(history: [])
        let s1 = ref(mac)
        let rig = try await HomeRig.make([mac], in: self, loads: false)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let (model, _) = model(s1, rig)
        XCTAssertTrue(model.canStop, "a working session can be stopped")
        XCTAssertEqual(model.session?.session.state, .working)
        XCTAssertEqual(model.session?.machineName, "MacBook Pro")

        var outcome = await model.stop(hard: false)
        XCTAssertEqual(outcome, .sent)
        outcome = await model.stop(hard: true)
        XCTAssertEqual(outcome, .sent)
        var interrupts = await mac.interrupts
        XCTAssertEqual(interrupts, [
            FakeMac.Interrupt(sessionId: "s1", hard: false), FakeMac.Interrupt(sessionId: "s1", hard: true),
        ])

        await mac.setInterruptOutcome(.failed)
        outcome = await model.stop(hard: false)
        XCTAssertEqual(outcome, .failed)
        XCTAssertFalse(model.sessionGone)

        // Stop shows only while the session works or waits for the user.
        await mac.upsertSession(agentSession("s1", state: .idle))
        let idle = await eventually { !model.canStop }
        XCTAssertTrue(idle)
        await mac.upsertSession(agentSession("s1", state: .needsInput))
        let needsYou = await eventually { model.canStop }
        XCTAssertTrue(needsYou)

        await mac.setInterruptOutcome(.notFound)
        outcome = await model.stop(hard: true)
        XCTAssertEqual(outcome, .notFound)
        XCTAssertTrue(model.sessionGone)
        XCTAssertFalse(model.canStop, "the Mac said the session is gone, even if its list still shows it")
        await mac.setInterruptOutcome(nil)

        // Offline: nothing is sent, there is no answer, and Stop goes away.
        await mac.dropLiveSessions()
        let down = await eventually { model.offline }
        XCTAssertTrue(down)
        XCTAssertFalse(model.canStop, "the state shown is only the last known one")
        outcome = await model.stop(hard: false)
        XCTAssertNil(outcome)
        interrupts = await mac.interrupts
        XCTAssertEqual(interrupts.count, 4)
    }

    // MARK: - Offline and pending

    func testOfflineOpenShowsCacheAndOffline() async throws {
        let mac = await mac(history: entries(1...3, text: "fresh", rev: 2))
        let s1 = ref(mac)
        let cached = ChatThread(entries: entries(1...2, text: "cached"), hasMore: false)
        await mac.failNextConnects(URLError(.notConnectedToInternet), count: 1_000)
        let rig = try await HomeRig.make(
            [mac], in: self, seed: { await $0.writer().save(cached, to: .thread(s1)) }, loads: false)
        let unreachable = await eventually {
            if case .offline = rig.hub.machines.first?.state { return true }
            return false
        }
        XCTAssertTrue(unreachable)
        let (model, _) = model(s1, rig)

        await model.open()

        XCTAssertTrue(model.offline)
        XCTAssertFalse(model.loading)
        XCTAssertEqual(model.thread, cached)
        XCTAssertNil(model.emptyState, "the copy shows")
        XCTAssertFalse(model.sessionGone, "an offline Mac's silence says nothing about the session")
        var requests = await mac.historyRequests
        XCTAssertEqual(requests, [])

        // The Mac comes back while the screen is open: its newest page loads.
        let running = await startRunning(model)
        XCTAssertTrue(running)
        await mac.failNextConnects(URLError(.notConnectedToInternet), count: 0)
        let retrying = await eventually { !rig.backoff.waiting.isEmpty }
        XCTAssertTrue(retrying)
        rig.backoff.release()
        let fresh = await eventually { !model.offline && model.thread.entries.map(\.rev) == [2, 2, 2] }
        XCTAssertTrue(fresh)
        XCTAssertEqual(model.thread.entries.map(\.seq), [1, 2, 3])
        requests = await mac.historyRequests
        XCTAssertEqual(requests.map(\.beforeSeq), [nil])

        // A drop and a return while open: the page is read again, for what was missed meanwhile.
        await mac.dropLiveSessions()
        let dropped = await eventually { model.offline }
        XCTAssertTrue(dropped)
        await mac.setHistory(sessionId: "s1", entries: entries(1...4, text: "fresh", rev: 2))
        let again = await eventually { !rig.backoff.waiting.isEmpty }
        XCTAssertTrue(again)
        rig.backoff.release()
        let caughtUp = await eventually { model.thread.entries.map(\.seq) == [1, 2, 3, 4] }
        XCTAssertTrue(caughtUp)
    }

    func testPendingHereFiltersByWorkspace() async throws {
        let first = FakeMac(name: "MacBook Pro")
        await first.upsertSession(agentSession("s1", workspace: "shellx"))
        await first.upsertSession(agentSession("s2", workspace: "web"))
        await first.addPending(pendingItem("p1", createdAtMs: 1, workspace: "shellx"))
        await first.addPending(pendingItem("p2", createdAtMs: 2, workspace: "web"))
        await first.addPending(pendingItem("p3", createdAtMs: 3, workspace: "shellx"))
        // Another Mac with a workspace of the same id.
        let second = FakeMac(name: "Mac mini")
        await second.upsertSession(agentSession("s1", workspace: "shellx"))
        await second.addPending(pendingItem("p4", createdAtMs: 0, workspace: "shellx"))
        let rig = try await HomeRig.make([first, second], in: self, loads: false)
        let synced = await eventually {
            rig.hub.machines.allSatisfy { $0.state == .online } && rig.hub.liveSessions.count == 3
                && rig.hub.pendingItems.count == 4
        }
        XCTAssertTrue(synced)

        let (shellx, _) = model(ref(first, "s1"), rig)
        let (web, _) = model(ref(first, "s2", workspace: "web"), rig)
        let (other, _) = model(ref(second, "s1"), rig)

        XCTAssertEqual(shellx.pendingHere.map(\.item.requestId), ["p1", "p3"])
        XCTAssertEqual(web.pendingHere.map(\.item.requestId), ["p2"])
        XCTAssertEqual(other.pendingHere.map(\.item.requestId), ["p4"])

        // Handled on the Mac: gone here too.
        await first.resolvePending("p1")
        let resolved = await eventually { shellx.pendingHere.map(\.item.requestId) == ["p3"] }
        XCTAssertTrue(resolved)
    }
}
