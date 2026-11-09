import ShellXAppCore
import ShellXLinkAccount
import XCTest
@testable import ShellX

@MainActor
final class DemoSessionTests: XCTestCase {
    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
    private func makeSession(runsScript: Bool = false) -> DemoSession {
        let history = FileManager.default.temporaryDirectory.appendingPathComponent("demo-session-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: history) }
        return DemoSession(make: { DemoComposition.make(approvalDelay: .zero, pasteboard: nil, runsScript: runsScript, history: history) })
    }

    func testStartSignsInToTheDemoAccountWithTheSampleMac() async throws {
        let session = makeSession()
        addTeardownBlock { @MainActor in await session.exit() }
        await session.start()
        let graph = try XCTUnwrap(session.graph)
        XCTAssertEqual(graph.coordinator.phase, .signedIn(email: "demo@shellx.pro"))
        XCTAssertEqual(graph.coordinator.authMethod, .google, "no switch banner in the demo")
        XCTAssertNil(graph.push)
        XCTAssertNil(graph.updatePrompt)
        let hub = try XCTUnwrap(graph.coordinator.hub)
        let online = await eventually { hub.machines.first?.state == .online }
        XCTAssertTrue(online, "\(hub.machines.map(\.state))")
        XCTAssertEqual(hub.machines.map(\.name), [DemoComposition.firstName])
    }

    func testStartingTwiceKeepsOneDemo() async throws {
        let session = makeSession()
        addTeardownBlock { @MainActor in await session.exit() }
        await session.start()
        let first = try XCTUnwrap(session.graph?.coordinator)
        await session.start()
        XCTAssertTrue(session.graph?.coordinator === first)
    }

    func testExitStopsTheDemo() async throws {
        let session = makeSession(runsScript: true)
        await session.start()
        let hub = try XCTUnwrap(session.graph?.coordinator.hub)
        await session.exit()
        XCTAssertNil(session.graph)
        do {
            try await hub.add(PairedMachine(machineID: "x", name: "x", linkSlot: "x", hostKey: Data(repeating: 0, count: 32)))
            XCTFail("the demo's hub still runs")
        } catch { XCTAssertEqual(error as? MachineHub.AddError, .notSignedIn) }
    }

    /// Review finding I1: the demo must not retry (and so clear) the real app's "local wipe pending" marker.
    func testDemoLeavesTheRealWipePendingMarkerAlone() async throws {
        let key = "shellx.localWipePending"
        UserDefaults.standard.set(true, forKey: key)
        addTeardownBlock { UserDefaults.standard.removeObject(forKey: key) }
        let session = makeSession()
        await session.start()
        await session.exit()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key), "the demo cleared the real marker")
    }
}
