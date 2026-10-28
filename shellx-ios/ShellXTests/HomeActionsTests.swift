import ShellXAppCore
import ShellXAppTestSupport
import SwiftUI
import XCTest
@testable import ShellX

/// The home's controls as `HomeActions` wires them to the signed-in scope, run one by one against a
/// fake Mac: each reaches the model call it stands for (no UI automation is available, so this is
/// the executed coverage of the home's wiring).
@MainActor
final class HomeActionsTests: XCTestCase {
    /// Holds the sheet route the way `PendingListView`'s `@State` does.
    private final class RouteBox {
        var route: PendingRoute?
    }

    /// Polls `condition` until it holds; only a wait for an asynchronous effect.
    private func eventually(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    /// A signed-in scope, made as `AppComposition` makes it, over a hub connected to `mac`.
    private func makeScope(_ mac: FakeMac) async throws -> SignedInScope {
        let vault = AccountVault(store: InMemorySecretStore())
        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        try await vault.setMachines([mac.machine], owner: "u1")
        let suite = "HomeActionsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-actions-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let relay = FakeRelayAccount()
        let latency = LatencyLog()
        let hub = MachineHub(
            vault: vault, relay: relay, connector: FakeMacFleet([mac], phoneKey: { try await vault.phoneKey() }),
            latency: latency, defaults: defaults, sleep: { try await Task.sleep(for: $0) }, onUnauthorized: {})
        addTeardownBlock { @MainActor in await hub.stopAll() }
        let scope = AppComposition.makeScope(
            hub: hub, history: ConversationStore(directory: directory), latency: latency,
            launch: LaunchMark(latency: latency), pairing: PairingModel(hub: hub, relay: relay, vault: vault))
        await hub.start()
        await scope.home.load()
        return scope
    }

    private func session(_ id: String, lastActivityMs: Int64 = 1_700_000_000_000) -> AgentSession {
        AgentSession(
            sessionId: id, agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx", state: .working,
            stateSinceMs: 1_700_000_000_000, lastActivityMs: lastActivityMs)
    }

    func testToolbarSeeAllAndTargetActions() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.upsertSession(session("s1"))
        let scope = try await makeScope(mac)
        var opened: [HomeRoute] = []
        let actions = HomeActions.make(
            scope: scope, open: { opened.append($0) })

        actions.openMachines()
        actions.openSettings()
        actions.seeAllPending()
        XCTAssertEqual(opened, [.machines, .settings, .pending])

        let s1 = SessionRef(machineID: mac.machine.machineID, sessionId: "s1", agent: "claude", workspaceTitle: "shellx")
        actions.choose(s1)
        XCTAssertEqual(scope.home.target, s1)
        actions.choose(nil)
        XCTAssertNil(scope.home.target)
    }

    func testSendSubmitsToTheHomeModel() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.upsertSession(session("s1"))
        await mac.setHistory(sessionId: "s1", entries: [])
        let scope = try await makeScope(mac)
        let online = await eventually { scope.hub.liveSessions.first?.online == true }
        XCTAssertTrue(online)
        var sends: [Task<HomeSubmitResult, Never>] = []
        let actions = HomeActions.make(
            scope: scope, open: { _ in },
            sent: { sends.append($0) })

        actions.send("Chạy lại test")

        XCTAssertEqual(sends.count, 1)
        let result = await sends[0].value
        XCTAssertEqual(result, .added("Chạy lại test"))
        let s1 = SessionRef(machineID: mac.machine.machineID, sessionId: "s1", agent: "claude", workspaceTitle: "shellx")
        XCTAssertEqual(scope.home.entries.map(\.content), [
            .userSaid(text: "Chạy lại test", target: s1, viaVoice: false), .note(.sent(s1)),
        ])
        let sent = await mac.sentTexts
        XCTAssertEqual(sent, [FakeMac.SentText(sessionId: "s1", text: "Chạy lại test")])
    }

    func testSpokenTextIsSentAndMarkedAsSaid() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.upsertSession(session("s1"))
        await mac.setHistory(sessionId: "s1", entries: [])
        let scope = try await makeScope(mac)
        let online = await eventually { scope.hub.liveSessions.first?.online == true }
        XCTAssertTrue(online)
        var sends: [Task<HomeSubmitResult, Never>] = []
        let actions = HomeActions.make(
            scope: scope, open: { _ in },
            sent: { sends.append($0) })

        actions.sendVoice("Tạo PR cho branch develop")

        XCTAssertEqual(sends.count, 1)
        let result = await sends[0].value
        XCTAssertEqual(result, .added("Tạo PR cho branch develop"))
        let s1 = SessionRef(machineID: mac.machine.machineID, sessionId: "s1", agent: "claude", workspaceTitle: "shellx")
        XCTAssertEqual(scope.home.entries.map(\.content), [
            .userSaid(text: "Tạo PR cho branch develop", target: s1, viaVoice: true), .note(.sent(s1)),
        ])
        let sent = await mac.sentTexts
        XCTAssertEqual(sent, [FakeMac.SentText(sessionId: "s1", text: "Tạo PR cho branch develop")])
    }

    /// The mic is pressed while the chip shows s2; s1 becomes the newest session before the release.
    /// The words go to s2 (final review, Important 3).
    func testSpokenTextGoesWhereTheChipPointedAtThePress() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.upsertSession(session("s1"))
        await mac.upsertSession(session("s2", lastActivityMs: 1_700_000_000_001))
        await mac.setHistory(sessionId: "s1", entries: [])
        await mac.setHistory(sessionId: "s2", entries: [])
        let scope = try await makeScope(mac)
        let online = await eventually { scope.hub.liveSessions.count == 2 && scope.hub.liveSessions.allSatisfy(\.online) }
        XCTAssertTrue(online)
        let s1 = SessionRef(machineID: mac.machine.machineID, sessionId: "s1", agent: "claude", workspaceTitle: "shellx")
        let s2 = SessionRef(machineID: mac.machine.machineID, sessionId: "s2", agent: "claude", workspaceTitle: "shellx")
        var sends: [Task<HomeSubmitResult, Never>] = []
        let actions = HomeActions.make(
            scope: scope, open: { _ in },
            sent: { sends.append($0) })

        actions.beginMessage()
        await mac.upsertSession(session("s1", lastActivityMs: 1_800_000_000_000))
        let moved = await eventually { scope.home.effectiveTarget == s1 }
        XCTAssertTrue(moved)
        actions.sendVoice("merge it")

        XCTAssertEqual(sends.count, 1)
        _ = await sends[0].value
        let sent = await mac.sentTexts
        XCTAssertEqual(sent, [FakeMac.SentText(sessionId: "s2", text: "merge it")])
        XCTAssertEqual(scope.home.entries.map(\.content), [
            .userSaid(text: "merge it", target: s2, viaVoice: true), .note(.sent(s2)),
        ])
    }

    func testCardActionsReachTheDecisionCenterAndOpenSheets() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        await mac.addPending(
            PendingItem(
                requestId: "p1", kind: .permission, agent: "claude", workspaceId: "ws", workspaceTitle: "shellx",
                toolName: "Bash", toolInputPreview: #"{"command":"git push"}"#, createdAtMs: 1, modes: ["once", "deny"]))
        await mac.addPending(
            PendingItem(
                requestId: "q1", kind: .question, agent: "claude", workspaceId: "ws", workspaceTitle: "shellx",
                createdAtMs: 2,
                questions: [
                    PendingQuestion(
                        id: "q", prompt: "Which database?", multiSelect: false,
                        options: [PendingQuestionOption(id: "pg", label: "Postgres")])
                ]))
        let scope = try await makeScope(mac)
        let synced = await eventually { scope.hub.pendingItems.count == 2 && scope.hub.pendingItems.allSatisfy(\.actionable) }
        XCTAssertTrue(synced)
        // `SignedInView` keeps the center synced with the hub.
        scope.decisions.sync(scope.hub.pendingItems)
        let box = RouteBox()
        let route = Binding(get: { box.route }, set: { box.route = $0 })
        let card = { PendingCardsSection.actions(for: $0, hub: scope.hub, center: scope.decisions, route: route) }
        let permission = try XCTUnwrap(scope.hub.pendingItems.first { $0.item.requestId == "p1" })
        let question = try XCTUnwrap(scope.hub.pendingItems.first { $0.item.requestId == "q1" })

        // "Answer" and "Show more" open the item's sheet.
        card(question).openSheet()
        XCTAssertEqual(box.route?.kind, .question)
        XCTAssertEqual(box.route?.id, question.id)
        card(permission).showMore()
        XCTAssertEqual(box.route?.kind, .fullText)
        XCTAssertEqual(box.route?.id, permission.id)

        // A decision goes through the center to the Mac; "Try again" sends it once more.
        await mac.setReplyOutcome(.unknown)
        card(permission).decide(.permission(.once))
        let rejected = await eventually { scope.decisions.status[permission.id] == .failed(.rejected) }
        XCTAssertTrue(rejected)
        var decisions = await mac.decisions
        XCTAssertEqual(decisions, [FakeMac.Decision(requestId: "p1", decision: .permission(.once))])
        card(permission).retry()
        let resent = await eventually { await mac.decisions.count == 2 }
        XCTAssertTrue(resent)
        decisions = await mac.decisions
        XCTAssertEqual(decisions.last, FakeMac.Decision(requestId: "p1", decision: .permission(.once)))
    }
}
