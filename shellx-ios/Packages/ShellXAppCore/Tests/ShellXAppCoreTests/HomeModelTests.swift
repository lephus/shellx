import Foundation
import ShellXAppTestSupport
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// The home conversation: what a message does, the ShellX notes it gets, finished sessions, and
/// the timeline kept on the phone.
@MainActor
final class HomeModelTests: XCTestCase {
    private func ref(_ mac: FakeMac, _ sessionId: String) -> SessionRef {
        SessionRef(machineID: mac.machine.machineID, sessionId: sessionId, agent: "claude", workspaceTitle: "shellx")
    }

    /// A Mac with running sessions whose chat accepts messages.
    private func macWithSessions(_ ids: [String], name: String = "MacBook Pro") async -> FakeMac {
        let mac = FakeMac(name: name)
        for (offset, id) in ids.enumerated() {
            await mac.upsertSession(agentSession(id, lastActivityMs: 1_700_000_000_000 + Int64(offset)))
            await mac.setHistory(sessionId: id, entries: [])
        }
        return mac
    }

    private func notes(_ home: HomeModel) -> [HomeNote] {
        home.entries.compactMap {
            if case let .note(note) = $0.content { return note }
            return nil
        }
    }

    private func agentProse(_ seq: Int, _ text: String, role: ChatEntryRole = .agent, kind: ChatEntryKind = .prose)
        -> ChatEntry
    {
        ChatEntry(id: "c\(seq)", rev: 1, seq: seq, role: role, kind: kind, text: text, tsMs: 1_700_000_000_000)
    }

    // MARK: - Sending

    func testSubmitSendsToTargetAndNotesSent() async throws {
        let mac = await macWithSessions(["s1"])
        let rig = try await HomeRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        XCTAssertEqual(rig.home.effectiveTarget, ref(mac, "s1"))

        let result = await rig.home.submit("  Chạy lại test giúp mình \n", viaVoice: true)

        XCTAssertEqual(result, .ok("Chạy lại test giúp mình"))
        XCTAssertEqual(rig.home.entries.map(\.content), [
            .userSaid(text: "Chạy lại test giúp mình", target: ref(mac, "s1"), viaVoice: true),
            .note(.sent(ref(mac, "s1"))),
        ])
        XCTAssertEqual(rig.home.entries.first?.at, HomeRig.now)
        var sent = await mac.sentTexts
        XCTAssertEqual(sent, [FakeMac.SentText(sessionId: "s1", text: "Chạy lại test giúp mình")])

        // A newer session starts: the composer keeps the session just messaged.
        await mac.upsertSession(agentSession("s2", lastActivityMs: 1_800_000_000_000))
        await mac.setHistory(sessionId: "s2", entries: [])
        let two = await rig.online(sessions: 2)
        XCTAssertTrue(two)
        XCTAssertEqual(rig.hub.liveSessions.first?.session.sessionId, "s2")
        XCTAssertEqual(rig.home.effectiveTarget, ref(mac, "s1"))

        // A session the user picks wins until they pick another.
        rig.home.target = ref(mac, "s2")
        XCTAssertEqual(rig.home.effectiveTarget, ref(mac, "s2"))
        _ = await rig.home.submit("Còn bên này?", viaVoice: false)
        sent = await mac.sentTexts
        XCTAssertEqual(sent.last, FakeMac.SentText(sessionId: "s2", text: "Còn bên này?"))
        XCTAssertEqual(notes(rig.home).last, .sent(ref(mac, "s2")))
    }

    func testSubmitToOfflineMacNotesOfflineImmediately() async throws {
        let mac = await macWithSessions(["s1"])
        let rig = try await HomeRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)

        // The link drops; the reconnect waits (its backoff is never released here).
        await mac.dropLiveSessions()
        let down = await eventually { rig.hub.machines.first?.state == .reconnecting }
        XCTAssertTrue(down)
        XCTAssertEqual(rig.hub.liveSessions.map(\.online), [false], "the last known session stays listed")

        // Nothing is chosen: the default Mac is offline.
        XCTAssertNil(rig.home.effectiveTarget)
        _ = await rig.home.submit("Có ai không?", viaVoice: false)
        XCTAssertEqual(rig.home.entries.map(\.content), [
            .userSaid(text: "Có ai không?", target: nil, viaVoice: false),
            .note(.machineOffline(machineName: "MacBook Pro")),
        ])

        // The user picked that session: still nothing is sent or queued.
        rig.home.target = ref(mac, "s1")
        XCTAssertEqual(rig.home.effectiveTarget, ref(mac, "s1"))
        _ = await rig.home.submit("Gửi lại", viaVoice: false)
        XCTAssertEqual(Array(rig.home.entries.suffix(2)).map(\.content), [
            .userSaid(text: "Gửi lại", target: ref(mac, "s1"), viaVoice: false),
            .note(.machineOffline(machineName: "MacBook Pro")),
        ])
        let sent = await mac.sentTexts
        XCTAssertEqual(sent, [])
    }

    func testSubmitWithoutLiveSessionNotesNoLiveSession() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.upsertSession(agentSession("gone", state: .ended))
        let rig = try await HomeRig.make([mac], in: self)
        let synced = await eventually { rig.hub.machines.first?.state == .online }
        XCTAssertTrue(synced)

        XCTAssertNil(rig.home.effectiveTarget)
        let result = await rig.home.submit("Làm issue 12 đi", viaVoice: false)

        XCTAssertEqual(result, .ok("Làm issue 12 đi"))
        XCTAssertEqual(rig.home.entries.map(\.content), [
            .userSaid(text: "Làm issue 12 đi", target: nil, viaVoice: false),
            .note(.noLiveSession),
        ])
        // Empty text does nothing at all.
        let empty = await rig.home.submit(" \n ", viaVoice: false)
        XCTAssertEqual(empty, .empty)
        XCTAssertEqual(rig.home.entries.count, 2)
    }

    func testBusyAndNotFoundNoted() async throws {
        let mac = await macWithSessions(["s1"])
        let rig = try await HomeRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let s1 = ref(mac, "s1")

        for (outcome, failure) in [
            (ChatSendOutcome.busy, SendFailure.busy), (.notFound, .notFound), (.failed, .failed),
            (.other("rate_limited"), .failed),
        ] {
            await mac.setSendOutcome(outcome)
            _ = await rig.home.submit("Thử lại", viaVoice: false)
            XCTAssertEqual(notes(rig.home).last, .sendFailed(s1, failure), "\(outcome)")
        }

        // Errors: an offline Mac names itself; anything else means no answer.
        XCTAssertEqual(HomeNote(sendError: LinkCallError.offline(machineName: "Mac mini"), to: s1), .machineOffline(machineName: "Mac mini"))
        XCTAssertEqual(HomeNote(sendError: CancellationError(), to: s1), .sendFailed(s1, .noAnswer))
        XCTAssertEqual(HomeNote(sendError: LinkCallError.unknownMachine, to: s1), .sendFailed(s1, .noAnswer))
    }

    // MARK: - Finished sessions

    func testFinishedNoteCarriesFirstLineOfLastAgentProse() async throws {
        let mac = await macWithSessions(["s1", "s2", "s3"])
        await mac.setHistory(sessionId: "s2", entries: [
            agentProse(1, "\n  Đã sửa lỗi build.  \nChi tiết: thiếu import."), agentProse(2, "ok", role: .user),
        ])
        // s3 has no transcript: its history answers not_found.
        let rig = try await HomeRig.make([mac], in: self)
        let online = await rig.online(sessions: 3)
        XCTAssertTrue(online)
        let running = await rig.startRunning(in: self)
        XCTAssertTrue(running)
        let s1 = ref(mac, "s1")

        // Seen live: the newest agent prose, not a later thought or user line.
        await mac.pushChat(sessionId: "s1", entries: [
            agentProse(3, "Cũ rồi"), agentProse(5, "Xong rồi, test xanh hết.\nChi tiết bên dưới."),
            agentProse(6, "Nghĩ thêm", kind: .thought), agentProse(7, "cảm ơn", role: .user),
        ])
        let seen = await eventually { rig.home.lastAgentLine(for: s1) == "Xong rồi, test xanh hết." }
        XCTAssertTrue(seen)
        await mac.upsertSession(agentSession("s1", state: .idle, stateSinceMs: 1_700_000_050_000))
        let first = await eventually { self.notes(rig.home).count == 1 }
        XCTAssertTrue(first)
        XCTAssertEqual(notes(rig.home), [.agentFinished(s1, summary: "Xong rồi, test xanh hết.")])

        // Not seen live: the last ten entries of its history.
        await mac.upsertSession(agentSession("s2", state: .idle, stateSinceMs: 1_700_000_060_000))
        let second = await eventually { self.notes(rig.home).count == 2 }
        XCTAssertTrue(second)
        XCTAssertEqual(notes(rig.home).last, .agentFinished(ref(mac, "s2"), summary: "Đã sửa lỗi build."))

        // History fails: no summary.
        await mac.upsertSession(agentSession("s3", state: .idle, stateSinceMs: 1_700_000_070_000))
        let third = await eventually { self.notes(rig.home).count == 3 }
        XCTAssertTrue(third)
        XCTAssertEqual(notes(rig.home).last, .agentFinished(ref(mac, "s3"), summary: nil))

        // A long first line is cut to 140 characters.
        await mac.upsertSession(agentSession("s1", state: .working, stateSinceMs: 1_700_000_080_000))
        await mac.pushChat(sessionId: "s1", entries: [agentProse(8, String(repeating: "ệ", count: 300))])
        let long = await eventually { rig.home.lastAgentLine(for: s1)?.count == 140 }
        XCTAssertTrue(long)
        await mac.upsertSession(agentSession("s1", state: .idle, stateSinceMs: 1_700_000_090_000))
        let fourth = await eventually { self.notes(rig.home).count == 4 }
        XCTAssertTrue(fourth)
        guard case let .agentFinished(_, summary?) = notes(rig.home).last else { return XCTFail("\(notes(rig.home))") }
        XCTAssertEqual(summary.count, 140)
        XCTAssertTrue(summary.hasSuffix("…"))

        // A reply seen live serves one finish only: the next turn, whose chat was not seen (the app
        // was away), reads the history instead of quoting the turn before.
        await mac.setHistory(sessionId: "s1", entries: [agentProse(20, "Lượt mới: đã deploy.")])
        await mac.upsertSession(agentSession("s1", state: .working, stateSinceMs: 1_700_000_100_000))
        await mac.upsertSession(agentSession("s1", state: .idle, stateSinceMs: 1_700_000_110_000))
        let fifth = await eventually { self.notes(rig.home).count == 5 }
        XCTAssertTrue(fifth)
        XCTAssertEqual(notes(rig.home).last, .agentFinished(s1, summary: "Lượt mới: đã deploy."))
    }

    func testFinishAfterReconnectQuotesTheNewestReplyFromHistory() async throws {
        let mac = await macWithSessions(["s1"])
        let rig = try await HomeRig.make([mac], in: self, settle: HomeModel.finishSettle)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let running = await rig.startRunning(in: self)
        XCTAssertTrue(running)
        let s1 = ref(mac, "s1")
        await mac.pushChat(sessionId: "s1", entries: [agentProse(3, "Đang xem log build.")])
        let seen = await eventually { rig.home.lastAgentLine(for: s1) == "Đang xem log build." }
        XCTAssertTrue(seen)

        // The link drops; meanwhile the turn ends on the Mac with a reply this phone never saw.
        await mac.dropLiveSessions()
        let down = await eventually { rig.hub.machines.first?.state == .reconnecting && !rig.backoff.waiting.isEmpty }
        XCTAssertTrue(down)
        await mac.pushChat(sessionId: "s1", entries: [agentProse(4, "Xong: build xanh lại.")])
        await mac.upsertSession(agentSession("s1", state: .idle, stateSinceMs: 1_700_000_050_000))
        rig.backoff.release()
        let back = await eventually { rig.hub.machines.first?.state == .online }
        XCTAssertTrue(back)

        // The note waits out the settle delay, then quotes the history's newest reply.
        let settling = await rig.release(HomeModel.finishSettle)
        XCTAssertTrue(settling)
        let noted = await eventually { self.notes(rig.home).count == 1 }
        XCTAssertTrue(noted)
        XCTAssertEqual(notes(rig.home), [.agentFinished(s1, summary: "Xong: build xanh lại.")])
    }

    func testFinishNoteFollowsTheFinalReplyArrivingLater() async throws {
        let mac = await macWithSessions(["s1"])
        await mac.setHistory(sessionId: "s1", entries: [agentProse(1, "Để mình xem log.")])
        let rig = try await HomeRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let running = await rig.startRunning(in: self)
        XCTAssertTrue(running)
        let s1 = ref(mac, "s1")

        // The Mac reports idle before its transcript has the final reply.
        await mac.upsertSession(agentSession("s1", state: .idle, stateSinceMs: 1_700_000_050_000))
        let noted = await eventually { self.notes(rig.home).count == 1 }
        XCTAssertTrue(noted)
        XCTAssertEqual(notes(rig.home), [.agentFinished(s1, summary: "Để mình xem log.")])

        // The final reply arrives while the session stays idle: the same note now quotes it.
        await mac.pushChat(sessionId: "s1", entries: [agentProse(2, "Xong, test xanh hết.")])
        let updated = await eventually {
            self.notes(rig.home) == [.agentFinished(s1, summary: "Xong, test xanh hết.")]
        }
        XCTAssertTrue(updated, "\(notes(rig.home))")
        XCTAssertEqual(rig.home.entries.count, 1, "updated in place, not a second note")

        // The session works again: the note stops following it.
        await mac.upsertSession(agentSession("s1", state: .working, stateSinceMs: 1_700_000_060_000))
        let stopped = await eventually { !rig.home.isFollowingFinish(of: s1) }
        XCTAssertTrue(stopped)
        await mac.pushChat(sessionId: "s1", entries: [agentProse(3, "Lượt tiếp theo.")])
        let seen = await eventually { rig.home.lastAgentLine(for: s1) == "Lượt tiếp theo." }
        XCTAssertTrue(seen)
        XCTAssertEqual(notes(rig.home), [.agentFinished(s1, summary: "Xong, test xanh hết.")])
    }

    func testFinishNoteStopsFollowingAfterTenSeconds() async throws {
        let mac = await macWithSessions(["s1"])
        await mac.setHistory(sessionId: "s1", entries: [agentProse(1, "Xong.")])
        let rig = try await HomeRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)
        let running = await rig.startRunning(in: self)
        XCTAssertTrue(running)
        let s1 = ref(mac, "s1")
        await mac.upsertSession(agentSession("s1", state: .idle, stateSinceMs: 1_700_000_050_000))
        let noted = await eventually { self.notes(rig.home).count == 1 }
        XCTAssertTrue(noted)
        XCTAssertTrue(rig.home.isFollowingFinish(of: s1))

        let ended = await rig.release(HomeModel.finishFollow)
        XCTAssertTrue(ended)
        let stopped = await eventually { !rig.home.isFollowingFinish(of: s1) }
        XCTAssertTrue(stopped)
        await mac.pushChat(sessionId: "s1", entries: [agentProse(2, "Một dòng muộn.")])
        let seen = await eventually { rig.home.lastAgentLine(for: s1) == "Một dòng muộn." }
        XCTAssertTrue(seen)
        XCTAssertEqual(notes(rig.home), [.agentFinished(s1, summary: "Xong.")])
    }

    func testFinishUsesALiveReplyNewerThanHistoryOrWhenHistoryFails() async throws {
        let mac = await macWithSessions(["s1", "s2"])
        let rig = try await HomeRig.make([mac], in: self, settle: HomeModel.finishSettle)
        let online = await rig.online(sessions: 2)
        XCTAssertTrue(online)
        let running = await rig.startRunning(in: self)
        XCTAssertTrue(running)
        let s1 = ref(mac, "s1")
        let s2 = ref(mac, "s2")

        // The history lags the live reply.
        await mac.pushChat(sessionId: "s1", entries: [agentProse(9, "Mới nhất.")])
        let seen = await eventually { rig.home.lastAgentLine(for: s1) == "Mới nhất." }
        XCTAssertTrue(seen)
        await mac.setHistory(sessionId: "s1", entries: [agentProse(5, "Cũ hơn.")])
        await mac.upsertSession(agentSession("s1", state: .idle, stateSinceMs: 1_700_000_050_000))
        let settled = await rig.release(HomeModel.finishSettle)
        XCTAssertTrue(settled)
        let first = await eventually { self.notes(rig.home).count == 1 }
        XCTAssertTrue(first)
        XCTAssertEqual(notes(rig.home).last, .agentFinished(s1, summary: "Mới nhất."))

        // The history cannot be read (the link dropped while settling): the live reply alone.
        await mac.pushChat(sessionId: "s2", entries: [agentProse(4, "Trả lời sống.")])
        let seenTwo = await eventually { rig.home.lastAgentLine(for: s2) == "Trả lời sống." }
        XCTAssertTrue(seenTwo)
        await mac.upsertSession(agentSession("s2", state: .idle, stateSinceMs: 1_700_000_060_000))
        let settling = await eventually { rig.timers.waiting.contains(HomeModel.finishSettle) }
        XCTAssertTrue(settling)
        await mac.dropLiveSessions()
        let down = await eventually { rig.hub.machines.first?.state == .reconnecting }
        XCTAssertTrue(down)
        rig.timers.release { $0 == HomeModel.finishSettle }
        let second = await eventually { self.notes(rig.home).count == 2 }
        XCTAssertTrue(second)
        XCTAssertEqual(notes(rig.home).last, .agentFinished(s2, summary: "Trả lời sống."))
    }

    func testFinishWhileAppClosedNotedOnRun() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.upsertSession(agentSession("s1", state: .idle, stateSinceMs: 1_700_000_050_000))
        await mac.setHistory(sessionId: "s1", entries: [agentProse(1, "Đã push nhánh.")])
        // Last launch saw s1 working.
        var saved = SessionFinishDetector()
        _ = saved.observe(machineID: mac.machine.machineID, sessions: [agentSession("s1", state: .working)])
        let rig = try await HomeRig.make([mac], in: self, seed: { await $0.writer().save(saved, to: .lastSessions) })
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)

        let running = await rig.startRunning(in: self)
        XCTAssertTrue(running)

        let noted = await eventually { self.notes(rig.home).count == 1 }
        XCTAssertTrue(noted)
        XCTAssertEqual(notes(rig.home), [.agentFinished(ref(mac, "s1"), summary: "Đã push nhánh.")])
    }

    // MARK: - Kept on the phone

    func testEntriesPersistAndReload() async throws {
        let mac = await macWithSessions(["s1"])
        let rig = try await HomeRig.make([mac], in: self)
        let online = await rig.online(sessions: 1)
        XCTAssertTrue(online)

        _ = await rig.home.submit("Lần một", viaVoice: false)
        // Written 0.5 s after the last change, not before.
        let waiting = await eventually { rig.timers.waiting == [HomeModel.saveDelay] }
        XCTAssertTrue(waiting, "\(rig.timers.waiting)")
        let early = await rig.stored()
        XCTAssertNil(early)
        rig.timers.release()
        let saved = await eventually { await rig.stored()?.entries.count == 2 }
        XCTAssertTrue(saved)

        // The app goes to the background: written at once.
        _ = await rig.home.submit("Lần hai", viaVoice: true)
        await rig.home.flush()
        let reopened = await rig.reopened()
        XCTAssertEqual(reopened.entries, rig.home.entries)
        XCTAssertEqual(reopened.entries.count, 4)
        XCTAssertEqual(reopened.effectiveTarget, ref(mac, "s1"), "the session last messaged is remembered")

        // After a sign-out wipe, this account's model can no longer write.
        try await rig.store.wipe()
        _ = await rig.home.submit("Sau khi đăng xuất", viaVoice: false)
        await rig.home.flush()
        let afterWipe = await rig.stored()
        XCTAssertNil(afterWipe)
    }

    func testEntriesAddedBeforeLoadAreSaved() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let stored = HomeDocument(entries: [homeEntry(0)], lastUsed: nil)
        let rig = try await HomeRig.make(
            [mac], in: self, seed: { await $0.writer().save(stored, to: .home) }, loads: false)

        // A message before the stored timeline is read: there is no writer yet, so nothing is saved.
        _ = await rig.home.submit("Trước khi tải xong", viaVoice: false)
        XCTAssertEqual(rig.home.entries.count, 2)
        await rig.home.flush()

        await rig.home.load()
        XCTAssertEqual(rig.home.entries.count, 3)
        XCTAssertEqual(rig.home.entries.first?.id, "e0")
        // Loading schedules the save it could not do before.
        let saved = await rig.release(HomeModel.saveDelay)
        XCTAssertTrue(saved)
        let written = await eventually { await rig.stored()?.entries.count == 3 }
        XCTAssertTrue(written)
    }

    func testUnreadableMacListKeepsTheSavedSessionStates() async throws {
        // The hub read no Macs (an empty or unreadable list): the saved states must survive.
        var saved = SessionFinishDetector()
        _ = saved.observe(machineID: "mac-x", sessions: [agentSession("s1", state: .working)])
        let rig = try await HomeRig.make([], in: self, seed: { await $0.writer().save(saved, to: .lastSessions) })

        let running = await rig.startRunning(in: self)
        XCTAssertTrue(running)
        await rig.home.flush()

        let stored = await rig.storedDetector()
        XCTAssertEqual(stored, saved)
    }

    func testEntriesCappedAt2000() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let stored = HomeDocument(entries: (0..<1_999).map { homeEntry($0) }, lastUsed: nil)
        let rig = try await HomeRig.make([mac], in: self, seed: { await $0.writer().save(stored, to: .home) })
        XCTAssertEqual(rig.home.entries.count, 1_999)
        let synced = await eventually { rig.hub.machines.first?.state == .online }
        XCTAssertTrue(synced)

        // A message and its note: 2001, so the oldest goes.
        _ = await rig.home.submit("Thêm một", viaVoice: false)

        XCTAssertEqual(rig.home.entries.count, HomeModel.maxEntries)
        XCTAssertEqual(rig.home.entries.first?.id, "e1")
        XCTAssertEqual(rig.home.entries.last?.content, .note(.noLiveSession))
        await rig.home.flush()
        let reopened = await rig.reopened()
        XCTAssertEqual(reopened.entries.count, 2_000)

        // A stored timeline longer than the cap (an older build) loads capped, newest kept.
        let oversized = HomeDocument(entries: (0..<2_500).map { homeEntry($0) }, lastUsed: nil)
        await rig.store.writer().save(oversized, to: .home)
        let capped = await rig.reopened()
        XCTAssertEqual(capped.entries.count, 2_000)
        XCTAssertEqual(capped.entries.first?.id, "e500")
    }
}
