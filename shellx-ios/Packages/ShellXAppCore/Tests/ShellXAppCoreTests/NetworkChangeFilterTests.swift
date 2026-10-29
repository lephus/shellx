import XCTest

@testable import ShellXAppCore

@MainActor
final class NetworkChangeFilterTests: XCTestCase {
    private let wifi = NetworkPath(status: "satisfied", interfaces: ["wifi:en0"], gateways: ["192.168.1.1:0"])

    private func filter(_ sleeper: ManualSleeper, _ calls: Collected<Void>) -> NetworkChangeFilter {
        NetworkChangeFilter(sleep: sleeper.sleep, onChange: { calls.items.append(()) })
    }

    func testFirstPathIsTheBaseline() async {
        let sleeper = ManualSleeper()
        let calls = Collected<Void>()
        let filter = filter(sleeper, calls)

        filter.receive(wifi)
        filter.receive(wifi)

        await Task.yield()
        XCTAssertEqual(sleeper.requested, [])
        XCTAssertEqual(calls.items.count, 0)
    }

    func testChangesWithin300msReportedOnce() async {
        let sleeper = ManualSleeper()
        let calls = Collected<Void>()
        let filter = filter(sleeper, calls)
        filter.receive(wifi)

        let cellular = NetworkPath(status: "satisfied", interfaces: ["cellular:pdp_ip0"], gateways: ["10.0.0.1:0"])
        let offline = NetworkPath(status: "unsatisfied", interfaces: [], gateways: [])
        filter.receive(offline)
        _ = await eventually { sleeper.waiting.count == 1 }
        filter.receive(cellular)
        let settled = await eventually { sleeper.waiting.count == 1 && sleeper.cancelled == 1 }
        XCTAssertTrue(settled, "the second change restarts the wait")
        XCTAssertEqual(sleeper.waiting, [NetworkChangeFilter.settle])
        XCTAssertEqual(NetworkChangeFilter.settle, .milliseconds(300))

        sleeper.release()
        let called = await eventually { calls.items.count == 1 }
        XCTAssertTrue(called)
        XCTAssertEqual(sleeper.requested.count, 2)
    }

    func testSecondaryInterfaceDoesNotCount() async {
        let sleeper = ManualSleeper()
        let calls = Collected<Void>()
        let filter = filter(sleeper, calls)
        filter.receive(wifi)

        // Cellular comes up behind Wi-Fi: the live sessions still use Wi-Fi.
        filter.receive(NetworkPath(status: "satisfied", interfaces: ["wifi:en0", "cellular:pdp_ip0"], gateways: ["192.168.1.1:0"]))
        await Task.yield()
        XCTAssertEqual(sleeper.requested, [])

        // Another Wi-Fi network: same interface, new gateway.
        filter.receive(NetworkPath(status: "satisfied", interfaces: ["wifi:en0"], gateways: ["10.1.1.1:0"]))
        _ = await eventually { sleeper.waiting.count == 1 }
        sleeper.release()
        let called = await eventually { calls.items.count == 1 }
        XCTAssertTrue(called)
    }

    func testGatewayOrderDoesNotCount() {
        XCTAssertEqual(
            NetworkPath(status: "satisfied", interfaces: ["wifi:en0"], gateways: ["a", "b"]),
            NetworkPath(status: "satisfied", interfaces: ["wifi:en0", "other:utun0"], gateways: ["b", "a"]))
    }
}
