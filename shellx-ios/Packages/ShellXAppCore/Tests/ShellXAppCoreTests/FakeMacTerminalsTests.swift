import Foundation
import ShellXAppTestSupport
import ShellXLinkCore
import ShellXLinkSession
import XCTest

/// `FakeMac`'s terminals, reached through a real `LinkClient`: views, typing into the fake shell, creation.
@MainActor
final class FakeMacTerminalsTests: XCTestCase {
    private var clients: [LinkClient] = []

    override func tearDown() async throws {
        for client in clients { await client.close() }
        clients = []
        try await super.tearDown()
    }

    private func connect(_ mac: FakeMac) async throws -> LinkClient {
        let key = NoiseStaticKey()
        let client = try await mac.connector(phoneKey: { key }).connect(mac.machine)
        clients.append(client)
        return client
    }

    private func ws(_ ids: String...) -> LinkWorkspace {
        LinkWorkspace(
            workspaceId: "ws-a", title: "a", order: 0,
            terminals: ids.enumerated().map { index, id in
                LinkTerminal(terminalId: id, title: id, order: index, selected: index == 0)
            })
    }

    func testWelcomeOffersTerminalViewsAndCreation() async throws {
        let both: Set = [ShellXLink.terminalViewFeature, ShellXLink.terminalCreateFeature]
        let client = try await connect(FakeMac(name: "Mac"))
        XCTAssertTrue(client.hostFeatures.isSuperset(of: both))
        let old = try await connect(FakeMac(name: "Old", servesTerminalViews: false, acceptsTerminalCreate: false))
        XCTAssertTrue(old.hostFeatures.isDisjoint(with: both))
    }

    func testOpenServesTheFixturesScreen() async throws {
        let mac = FakeMac(name: "Mac")
        await mac.setWorkspaces([ws("t1")])
        await mac.setTerminalFixtures(["t1": DemoTerminalScreens.shell])
        let client = try await connect(mac)
        let reader = TerminalPushReader(client.terminalPushes, terminalId: "t1")
        let opened = try await client.openTerminalView(terminalId: "t1", cols: 50, rows: 40)
        XCTAssertEqual(opened, .ok)
        var expected = TerminalScreen()
        expected.apply(DemoTerminalScreens.shell.snapshot)
        let shown = await eventually {
            reader.screen.screenText() == expected.screenText() && reader.screen.historyText() == expected.historyText()
        }
        XCTAssertTrue(shown)
        let opens = await mac.terminalViewOpens
        XCTAssertEqual(opens, [FakeMac.TerminalViewSize(terminalId: "t1", cols: 50, rows: 40)])
    }

    func testAnUnlistedTerminalIsNotFound() async throws {
        let mac = FakeMac(name: "Mac")
        await mac.setWorkspaces([ws("t1")])
        let client = try await connect(mac)
        let answer = try await client.openTerminalView(terminalId: "nope", cols: 50, rows: 40)
        XCTAssertEqual(answer, .notFound)
    }

    func testTypingEchoesOnThePromptLine() async throws {
        let mac = FakeMac(name: "Mac")
        await mac.setWorkspaces([ws("t1")])
        let client = try await connect(mac)
        let reader = TerminalPushReader(client.terminalPushes, terminalId: "t1")
        _ = try await client.openTerminalView(terminalId: "t1", cols: 20, rows: 5)
        try await client.sendTerminalInput(terminalId: "t1", units: [.text("ls")])
        try await client.sendTerminalInput(terminalId: "t1", units: [.key(.enter, mods: [])])
        try await client.sendTerminalInput(terminalId: "t1", units: [.text("x"), .key(.backspace, mods: [])])
        try await client.sendTerminalInput(terminalId: "t1", units: [.key(.letter("c"), mods: [.ctrl])])
        let echoed = await eventually { Array(reader.screen.screenText().prefix(3)) == ["$ ls", "$ ^C", "$"] }
        XCTAssertTrue(echoed, "\(reader.screen.screenText())")
        let inputs = await mac.terminalViewInputs("t1")
        XCTAssertEqual(inputs.count, 4)
    }

    func testCloseResizeAndSnapshotRequestsAreRecorded() async throws {
        let mac = FakeMac(name: "Mac")
        await mac.setWorkspaces([ws("t1")])
        let client = try await connect(mac)
        let reader = TerminalPushReader(client.terminalPushes, terminalId: "t1")
        _ = try await client.openTerminalView(terminalId: "t1", cols: 20, rows: 5)
        let prompted = await eventually { reader.screen.screenText().first == "$" }
        XCTAssertTrue(prompted)
        try await client.resizeTerminalView(terminalId: "t1", cols: 30, rows: 10)
        try await client.resyncTerminalView(terminalId: "t1")
        try await client.closeTerminalView(terminalId: "t1")
        let recorded = await eventually {
            let resizes = await mac.terminalViewResizes, requests = await mac.terminalViewSnapshotRequests("t1")
            let closes = await mac.terminalViewCloses
            return resizes == [FakeMac.TerminalViewSize(terminalId: "t1", cols: 30, rows: 10)] && requests == 1
                && closes == ["t1"]
        }
        XCTAssertTrue(recorded)
    }

    func testCreateAddsATerminalTabToTheWorkspace() async throws {
        let mac = FakeMac(name: "Mac")
        await mac.setWorkspaces([ws("t1")])
        let client = try await connect(mac)
        let created = try await client.createTerminal(workspaceId: "ws-a")
        XCTAssertEqual(created.outcome, .ok)
        let id = try XCTUnwrap(created.terminalId)
        XCTAssertEqual(id, "ws-a-new-1")
        let list = try await client.workspaces()
        XCTAssertTrue(list.workspaces.first?.terminals.contains { $0.terminalId == id } ?? false)
        let added = list.workspaces.first?.terminals.first { $0.terminalId == id }
        XCTAssertEqual(added?.order, 1)
        XCTAssertEqual(added?.selected, false)
        let missing = try await client.createTerminal(workspaceId: "nope")
        XCTAssertEqual(missing.outcome, .notFound)
        await mac.setNextTerminalCreateOutcome(.refused)
        let refused = try await client.createTerminal(workspaceId: "ws-a")
        XCTAssertEqual(refused.outcome, .refused)
        XCTAssertNil(refused.terminalId)
        let creates = await mac.terminalCreates
        XCTAssertEqual(creates, ["ws-a", "nope", "ws-a"])
    }

    func testEmittedFramesAndEndsReachThePhone() async throws {
        let mac = FakeMac(name: "Mac")
        await mac.setWorkspaces([ws("t1")])
        let client = try await connect(mac)
        let reader = TerminalPushReader(client.terminalPushes, terminalId: "t1")
        _ = try await client.openTerminalView(terminalId: "t1", cols: 20, rows: 5)
        let prompted = await eventually { reader.screen.screenText().first == "$" }
        XCTAssertTrue(prompted)
        await mac.emitTerminalFrame("t1", TerminalGridFrame(
            head: TerminalFrameHead(kind: .delta, cols: 20, rows: 5, cursor: TerminalCursor(x: 0, y: 0)),
            lines: [TerminalLine(y: 0, runs: [TerminalRun(text: "hi")])]))
        let drawn = await eventually { reader.screen.screenText().first == "hi" }
        XCTAssertTrue(drawn, "\(reader.screen.screenText())")
        await mac.endTerminalView("t1", reason: .gone)
        let ended = await eventually { reader.pushes.contains(.ended(terminalId: "t1", reason: .gone)) }
        XCTAssertTrue(ended)
    }

    func testRefusedAndHeldOpens() async throws {
        let mac = FakeMac(name: "Mac")
        await mac.setWorkspaces([ws("t1", "t2")])
        let client = try await connect(mac)
        await mac.refuseTerminalView("t1", with: .refused)
        let refused = try await client.openTerminalView(terminalId: "t1", cols: 20, rows: 5)
        XCTAssertEqual(refused, .refused)
        await mac.holdTerminalViewOpens()
        let pending = Task { try await client.openTerminalView(terminalId: "t2", cols: 20, rows: 5) }
        let asked = await eventually { await mac.terminalViewOpens.count == 2 }
        XCTAssertTrue(asked)
        await mac.releaseTerminalViewOpens()
        let opened = try await pending.value
        XCTAssertEqual(opened, .ok)
    }

    func testTicksAppendLinesWhileTheTerminalIsViewed() async throws {
        let mac = FakeMac(name: "Mac")
        await mac.setWorkspaces([ws("t1")])
        let ticking = DemoTerminalFixture(cols: 20, rows: 3, screen: [], cursor: TerminalCursor(x: 0, y: 0),
                                          ticks: [DemoTerminalScreens.runs("tick")], tickInterval: .milliseconds(20))
        await mac.setTerminalFixtures(["t1": ticking])
        let client = try await connect(mac)
        let reader = TerminalPushReader(client.terminalPushes, terminalId: "t1")
        _ = try await client.openTerminalView(terminalId: "t1", cols: 20, rows: 3)
        let ticked = await eventually { Array(reader.screen.screenText().prefix(2)) == ["tick", "tick"] }
        XCTAssertTrue(ticked, "\(reader.screen.screenText())")
    }
}
