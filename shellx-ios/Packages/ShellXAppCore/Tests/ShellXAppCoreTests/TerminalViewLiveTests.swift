import Foundation
import ShellXAppTestSupport
import ShellXLinkCore
import ShellXLinkSession
import XCTest

@testable import ShellXAppCore

/// `TerminalViewModel` through a real `MachineHub` and a `FakeMac` (a real `LinkHost`) whose `ws-a` holds `t1` and `t2`.
@MainActor
final class TerminalViewLiveTests: XCTestCase {
    private func makeMac() async -> FakeMac {
        let mac = FakeMac(name: "Mac")
        await mac.setWorkspaces([
            linkWorkspace("a", terminals: [linkTerminal("t1", selected: true), linkTerminal("t2", order: 1)])
        ])
        return mac
    }

    /// A model of `mac` through `rig.hub`, running until the test ends.
    private func makeModel(_ mac: FakeMac, _ rig: HubRig) -> TerminalViewModel {
        let model = TerminalViewModel(machineID: mac.machine.machineID, link: rig.hub)
        let run = Task { await model.run() }
        addTeardownBlock { run.cancel() }
        return model
    }

    func testOpensSwitchesAndClosesThroughAFakeMac() async throws {
        let mac = await makeMac()
        let rig = try await HubRig.make([mac], in: self)
        let up = await rig.online(sessions: 0); XCTAssertTrue(up)
        let model = makeModel(mac, rig)
        model.setPhoneGrid(cols: 30, rows: 6); model.show("t1")
        let shown = await eventually { model.phase == .live && model.screen.screenText().first == "$" }
        XCTAssertTrue(shown, "\(model.phase) \(model.screen.screenText())")
        let opens = await mac.terminalViewOpens
        XCTAssertEqual(opens, [FakeMac.TerminalViewSize(terminalId: "t1", cols: 30, rows: 6)])
        model.show("t2")
        let switched = await eventually {
            let closes = await mac.terminalViewCloses, opens = await mac.terminalViewOpens
            return model.phase == .live && closes == ["t1"] && opens.map(\.terminalId) == ["t1", "t2"]
        }
        XCTAssertTrue(switched, "closed before the next open: no busy, no retry")
        model.show(nil)
        let closed = await eventually { await mac.terminalViewCloses == ["t1", "t2"] }
        XCTAssertTrue(closed)
    }

    func testAReconnectReopensTheView() async throws {   // Review Focus 4
        let mac = await makeMac()
        let rig = try await HubRig.make([mac], in: self)
        let up = await rig.online(sessions: 0); XCTAssertTrue(up)
        let model = makeModel(mac, rig)
        model.setPhoneGrid(cols: 30, rows: 6); model.show("t1")
        let shown = await eventually { model.phase == .live && model.screen.screenText().first == "$" }
        XCTAssertTrue(shown)
        await mac.dropLiveSessions()
        let back = await eventually {
            rig.backoff.release()
            let opens = await mac.terminalViewOpens
            return model.phase == .live && opens.count == 2
        }
        XCTAssertTrue(back, "\(model.phase)")
    }

    func testATerminalTheMacCannotViewFailsLikeAnyFailure() async throws {   // contracts §17
        let mac = await makeMac()
        await mac.refuseTerminalView("t1", with: .failed)
        let rig = try await HubRig.make([mac], in: self)
        let up = await rig.online(sessions: 0); XCTAssertTrue(up)
        let model = makeModel(mac, rig)
        model.setPhoneGrid(cols: 30, rows: 6); model.show("t1")
        let failed = await eventually {
            let opens = await mac.terminalViewOpens
            return model.phase == .unavailable(.failed) && opens.count == 2
        }
        XCTAssertTrue(failed, "one retry after 1 s, then Try Again")
    }

    func testTypingEchoesThroughAFakeMac() async throws {
        let mac = await makeMac()
        let rig = try await HubRig.make([mac], in: self)
        let up = await rig.online(sessions: 0); XCTAssertTrue(up)
        let model = makeModel(mac, rig)
        model.setPhoneGrid(cols: 30, rows: 6); model.show("t1")
        let shown = await eventually { model.phase == .live && model.screen.screenText().first == "$" }
        XCTAssertTrue(shown)
        model.insertText("ls"); model.press(.enter)
        let echoed = await eventually { Array(model.screen.screenText().prefix(2)) == ["$ ls", "$"] }
        XCTAssertTrue(echoed, "\(model.screen.screenText())")
        let inputs = await mac.terminalViewInputs("t1")
        XCTAssertEqual(inputs, [[.text("ls")], [.key(.enter, mods: [])]])
    }

    /// Review Focus 1, A → B → A through a real hub and Link host: the keys typed after the last swipe reach A only
    /// (final review, core M8).
    func testSwipingBackAndForthTypesIntoTheTerminalShown() async throws {
        let mac = await makeMac()
        let rig = try await HubRig.make([mac], in: self)
        let up = await rig.online(sessions: 0); XCTAssertTrue(up)
        let model = makeModel(mac, rig)
        model.setPhoneGrid(cols: 30, rows: 6)
        model.show("t1"); model.show("t2"); model.show("t1")
        let shown = await eventually { model.phase == .live && model.terminalId == "t1" }
        XCTAssertTrue(shown, "\(model.phase)")
        model.insertText("ab")
        let typed = await eventually { await mac.terminalViewInputs("t1") == [[.text("ab")]] }
        XCTAssertTrue(typed)
        let other = await mac.terminalViewInputs("t2")
        XCTAssertEqual(other, [])
    }
}
