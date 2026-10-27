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

    func testDemoIsSignedInWithFakeMacOnlineAndPairsSecondMacFromPastedCode() async throws {
        let pasteboard = makePasteboard()
        let graph = DemoComposition.make(approvalDelay: .zero, pasteboard: pasteboard, runsScript: false)
        let coordinator = graph.coordinator
        addTeardownBlock { @MainActor in await coordinator.hub?.stopAll() }

        await graph.prepare()
        await graph.coordinator.launch()

        XCTAssertEqual(graph.coordinator.phase, .signedIn(email: "demo@shellx.pro"))
        let hub = try XCTUnwrap(graph.coordinator.hub)
        let online = await eventually { hub.machines.first?.state == .online }
        XCTAssertTrue(online, "\(hub.machines.map(\.state))")
        XCTAssertEqual(hub.machines.map(\.name), [DemoComposition.firstName])

        let pairing = graph.makePairing(hub)
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
}
