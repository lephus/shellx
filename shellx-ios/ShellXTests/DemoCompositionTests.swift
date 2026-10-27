import ShellXAppCore
import SwiftUI
import UIKit
import XCTest
@testable import ShellX

/// The Debug demo's wiring (`SHELLX_DEMO=1`) and the paste path of the pairing sheet.
@MainActor
final class DemoCompositionTests: XCTestCase {
    private func makePasteboard() -> UIPasteboard {
        let pasteboard = UIPasteboard.withUniqueName()
        let name = pasteboard.name
        addTeardownBlock { @MainActor in UIPasteboard.remove(withName: name) }
        return pasteboard
    }

    /// Polls `condition` until it holds; only a wait for an asynchronous effect.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    func testPastedCodeIsReadOnceAndCleared() {
        let pasteboard = makePasteboard()
        pasteboard.string = "shellx-link://pair?v=1&m=m1&s=s1&k=k&c=c&n=Mac\n"

        let text = PairingPaste.take(from: pasteboard)

        XCTAssertEqual(text, "shellx-link://pair?v=1&m=m1&s=s1&k=k&c=c&n=Mac\n")
        XCTAssertFalse(pasteboard.hasStrings, "the one-time code does not stay on the pasteboard")
    }

    func testOtherPastedTextIsLeftAlone() {
        let pasteboard = makePasteboard()
        pasteboard.string = "a note"

        XCTAssertEqual(PairingPaste.take(from: pasteboard), "a note")
        XCTAssertEqual(pasteboard.string, "a note")
    }

    private func makeHistoryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("demo-history-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testDemoIsSignedInWithFakeMacOnlineAndPairsSecondMacFromPastedCode() async throws {
        let pasteboard = makePasteboard()
        let graph = DemoComposition.make(
            approvalDelay: .zero, pasteboard: pasteboard, runsScript: false, history: makeHistoryDirectory())
        let coordinator = graph.coordinator
        addTeardownBlock { @MainActor in await coordinator.hub?.stopAll() }

        await graph.prepare()
        await graph.coordinator.launch()

        XCTAssertEqual(graph.coordinator.phase, .signedIn(email: "demo@shellx.pro"))
        let hub = try XCTUnwrap(graph.coordinator.hub)
        let online = await eventually { hub.machines.first?.state == .online }
        XCTAssertTrue(online, "\(hub.machines.map(\.state))")
        XCTAssertEqual(hub.machines.map(\.name), [DemoComposition.firstName])

        let scope = try XCTUnwrap(graph.scopes.scope(for: hub), "the sign-in made the account's scope with its hub")
        let pairing = scope.pairing
        pairing.begin(uri: PairingPaste.take(from: pasteboard))
        XCTAssertEqual(pairing.step, .confirm(machineName: DemoComposition.secondName))
        XCTAssertFalse(pasteboard.hasStrings)
        await pairing.confirm()

        XCTAssertEqual(pairing.step, .paired(machineName: DemoComposition.secondName))
        let both = await eventually { hub.machines.count == 2 && hub.machines.allSatisfy { $0.state == .online } }
        XCTAssertTrue(both, "\(hub.machines.map(\.state))")

        // The fake relay lists the new Mac, so a refresh keeps both.
        await hub.refreshGrants()
        XCTAssertEqual(hub.machines.map(\.state), [.online, .online])
    }

    func testDemoHomeKeepsItsConversationAcrossRelaunch() async throws {
        let history = makeHistoryDirectory()

        let first = DemoComposition.make(
            approvalDelay: .zero, pasteboard: makePasteboard(), runsScript: false, history: history)
        await first.prepare()
        await first.coordinator.launch()
        let firstHub = try XCTUnwrap(first.coordinator.hub)
        let home = try XCTUnwrap(first.scopes.scope(for: firstHub)?.home)
        await home.load()
        _ = await home.submit("Xin chào", viaVoice: false)
        await home.flush()
        await firstHub.stopAll()
        XCTAssertEqual(home.entries.count, 2)

        let second = DemoComposition.make(
            approvalDelay: .zero, pasteboard: makePasteboard(), runsScript: false, history: history)
        await second.prepare()
        await second.coordinator.launch()
        let secondHub = try XCTUnwrap(second.coordinator.hub)
        addTeardownBlock { @MainActor in await secondHub.stopAll() }
        let reopened = try XCTUnwrap(second.scopes.scope(for: secondHub)?.home)
        await reopened.load()

        XCTAssertEqual(reopened.entries, home.entries)
        XCTAssertEqual(secondHub.machines.map(\.id), firstHub.machines.map(\.id), "the fake Mac keeps its id")
    }

    func testDemoAgentScreenShowsTheScriptedChatAndStops() async throws {
        let graph = DemoComposition.make(
            approvalDelay: .zero, pasteboard: makePasteboard(), runsScript: true, history: makeHistoryDirectory())
        await graph.prepare()
        await graph.coordinator.launch()
        let hub = try XCTUnwrap(graph.coordinator.hub)
        addTeardownBlock { @MainActor in await hub.stopAll() }
        let scope = try XCTUnwrap(graph.scopes.scope(for: hub))
        let listed = await eventually { hub.liveSessions.count == 2 }
        XCTAssertTrue(listed, "\(hub.machines.map(\.state))")
        let session = try XCTUnwrap(hub.liveSessions.first { $0.session.workspaceTitle == "shellx" })

        // What tapping its row opens.
        let model = scope.agentThread(session.ref)
        addTeardownBlock { @MainActor in await model.close() }
        await model.open()

        let kinds = Set(model.thread.entries.map(\.kind.wire))
        XCTAssertTrue(kinds.isSuperset(of: ["prose", "thought", "tool_use", "status"]), "\(kinds)")
        XCTAssertTrue(model.thread.entries.contains { $0.truncated == true }, "one entry is cut")
        XCTAssertEqual(model.thread.entries.first?.role, .user)
        let sent = await model.send("Chạy lại test giúp mình", viaVoice: false)
        XCTAssertEqual(sent, .sent(.submitted))
        // The script leaves shellx working (its third step switched it back on).
        XCTAssertTrue(model.canStop)
        let stopped = await model.stop(hard: false)
        XCTAssertEqual(stopped, .sent)
    }
}
