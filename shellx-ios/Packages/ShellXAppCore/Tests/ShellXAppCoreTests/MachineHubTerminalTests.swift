import Foundation
import ShellXAppTestSupport
import ShellXLinkCore
import ShellXLinkSession
import XCTest

@testable import ShellXAppCore

/// The hub's terminal calls and events (`TerminalLink`, `createTerminal`), against a `FakeMac` (a real `LinkHost`).
@MainActor
final class MachineHubTerminalTests: XCTestCase {
    /// A Mac with `ws-a` holding `t1` and `t2`.
    private func makeMac(
        name: String = "Mac", servesTerminalViews: Bool = true, acceptsTerminalCreate: Bool = true
    ) async -> FakeMac {
        let mac = FakeMac(
            name: name, servesTerminalViews: servesTerminalViews, acceptsTerminalCreate: acceptsTerminalCreate)
        await mac.setWorkspaces([
            linkWorkspace("a", terminals: [linkTerminal("t1", selected: true), linkTerminal("t2", order: 1)])
        ])
        return mac
    }

    func testHubOffersTerminalsOnlyWhenTheMacDoes() async throws {
        let mac = await makeMac()
        let old = await makeMac(name: "Old", servesTerminalViews: false, acceptsTerminalCreate: false)
        let rig = try await HubRig.make([mac, old], in: self)
        let online = await rig.online(sessions: 0)
        XCTAssertTrue(online)
        let id = mac.machine.machineID, oldId = old.machine.machineID

        XCTAssertTrue(rig.hub.isOnline(id))
        XCTAssertTrue(rig.hub.supportsTerminalView(id))
        XCTAssertTrue(rig.hub.supportsTerminalCreate(id))
        XCTAssertTrue(rig.hub.isOnline(oldId))
        XCTAssertFalse(rig.hub.supportsTerminalView(oldId))
        XCTAssertFalse(rig.hub.supportsTerminalCreate(oldId))
    }

    func testPushesArriveInOrderAfterTheOpen() async throws {
        let mac = await makeMac()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 0)
        XCTAssertTrue(online)
        let id = mac.machine.machineID
        let events = Collector(rig.hub.terminalEvents())

        let answer = await rig.hub.openTerminalView(machineID: id, terminalId: "t1", cols: 50, rows: 20)

        XCTAssertEqual(answer, .outcome(.ok))
        let pushes = {
            events.items.compactMap { event -> TerminalViewPush? in
                if case let .push(machine, push) = event, machine == id { return push }
                return nil
            }
        }
        let framed = await eventually {
            pushes().contains {
                if case .frame(terminalId: "t1", _) = $0 { return true }
                return false
            }
        }
        XCTAssertTrue(framed)
        XCTAssertEqual(pushes().first, .opened(terminalId: "t1"))
        let opens = await mac.terminalViewOpens
        XCTAssertEqual(opens, [FakeMac.TerminalViewSize(terminalId: "t1", cols: 50, rows: 20)])
    }

    func testInputResizeResyncAndCloseReachTheMac() async throws {
        let mac = await makeMac()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 0)
        XCTAssertTrue(online)
        let id = mac.machine.machineID

        _ = await rig.hub.openTerminalView(machineID: id, terminalId: "t1", cols: 50, rows: 20)
        await rig.hub.sendTerminalInput(machineID: id, terminalId: "t1", units: [.text("ls")])
        await rig.hub.resizeTerminalView(machineID: id, terminalId: "t1", cols: 60, rows: 30)
        await rig.hub.resyncTerminalView(machineID: id, terminalId: "t1")
        await rig.hub.closeTerminalView(machineID: id, terminalId: "t1")

        let reached = await eventually {
            let inputs = await mac.terminalViewInputs("t1"), closes = await mac.terminalViewCloses
            let requests = await mac.terminalViewSnapshotRequests("t1"), resizes = await mac.terminalViewResizes
            return inputs == [[.text("ls")]] && closes == ["t1"] && requests == 1
                && resizes == [FakeMac.TerminalViewSize(terminalId: "t1", cols: 60, rows: 30)]
        }
        XCTAssertTrue(reached)
    }

    func testNothingIsSentWithoutTheFeature() async throws {
        let mac = await makeMac(servesTerminalViews: false, acceptsTerminalCreate: false)
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 0)
        XCTAssertTrue(online)
        let id = mac.machine.machineID
        let before = mac.phoneFrameCount

        let answer = await rig.hub.openTerminalView(machineID: id, terminalId: "t1", cols: 50, rows: 20)
        XCTAssertEqual(answer, .notSent)
        await rig.hub.sendTerminalInput(machineID: id, terminalId: "t1", units: [.text("x")])
        await rig.hub.resizeTerminalView(machineID: id, terminalId: "t1", cols: 60, rows: 30)
        await rig.hub.resyncTerminalView(machineID: id, terminalId: "t1")
        await rig.hub.closeTerminalView(machineID: id, terminalId: "t1")
        let made = await rig.hub.createTerminal(WorkspaceRef(machineID: id, workspaceId: "ws-a"))

        XCTAssertEqual(made.result, .failed)
        XCTAssertNil(made.terminalId)
        XCTAssertEqual(mac.phoneFrameCount, before)
    }

    func testNothingIsSentToAMacThatIsNotOnline() async throws {
        let mac = await makeMac()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 0)
        XCTAssertTrue(online)

        XCTAssertFalse(rig.hub.isOnline("mac-nope"))
        XCTAssertFalse(rig.hub.supportsTerminalView("mac-nope"))
        let answer = await rig.hub.openTerminalView(machineID: "mac-nope", terminalId: "t1", cols: 50, rows: 20)
        XCTAssertEqual(answer, .notSent)
        let made = await rig.hub.createTerminal(WorkspaceRef(machineID: "mac-nope", workspaceId: "ws-a"))
        XCTAssertEqual(made.result, .offline)
        XCTAssertNil(made.terminalId)
    }

    func testStateChangesReachTerminalSubscribers() async throws {
        let mac = await makeMac()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 0)
        XCTAssertTrue(online)
        let id = mac.machine.machineID
        let events = Collector(rig.hub.terminalEvents())

        await mac.dropLiveSessions()

        let back = await eventually {
            rig.backoff.release()
            let states = events.items.compactMap { event -> MachineLinkState? in
                if case let .state(machine, state) = event, machine == id { return state }
                return nil
            }
            return states.contains(.reconnecting) && states.last == .online
        }
        XCTAssertTrue(back)
    }

    func testCreateTerminalOutcomes() async throws {
        let mac = await makeMac()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 0)
        XCTAssertTrue(online)
        let id = mac.machine.machineID

        let made = await rig.hub.createTerminal(WorkspaceRef(machineID: id, workspaceId: "ws-a"))
        XCTAssertEqual(made.result, .ok(workspaceId: nil))
        let newId = try XCTUnwrap(made.terminalId)
        let listed = await eventually {
            rig.hub.machines.first?.workspaces.workspace("ws-a")?.terminals.contains { $0.terminalId == newId } ?? false
        }
        XCTAssertTrue(listed)

        let missing = await rig.hub.createTerminal(WorkspaceRef(machineID: id, workspaceId: "nope"))
        XCTAssertEqual(missing.result, .notFound)
        XCTAssertNil(missing.terminalId)

        await mac.setNextTerminalCreateOutcome(.refused)
        let refused = await rig.hub.createTerminal(WorkspaceRef(machineID: id, workspaceId: "ws-a"))
        XCTAssertEqual(refused.result, .refused)
        XCTAssertNil(refused.terminalId)

        let creates = await mac.terminalCreates
        XCTAssertEqual(creates, ["ws-a", "nope", "ws-a"])
    }

    func testStopAllFinishesTheTerminalStream() async throws {
        let mac = await makeMac()
        let rig = try await HubRig.make([mac], in: self)
        let online = await rig.online(sessions: 0)
        XCTAssertTrue(online)
        let stream = rig.hub.terminalEvents()
        let finished = Task { for await _ in stream {}; return true }

        await rig.hub.stopAll()

        let done = await finished.value
        XCTAssertTrue(done)
    }
}
