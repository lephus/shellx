import Foundation
import ShellXLinkRelay
import ShellXLinkSession
import XCTest

/// `InMemoryCircuit` must behave like a relay circuit, or session tests prove nothing.
final class InMemoryCircuitTests: XCTestCase {
    func testFramesArriveInOrder() async throws {
        let (a, b) = makeInMemoryCircuitPair()
        try await a.send(Data([1]))
        try await a.send(Data([2]))
        let first = try await b.receive()
        let second = try await b.receive()
        XCTAssertEqual([first, second], [Data([1]), Data([2])])
    }

    func testCloseEndsPendingReceiveOnBothEnds() async throws {
        let (a, b) = makeInMemoryCircuitPair()
        let waitingA = Task { try await a.receive() }
        let waitingB = Task { try await b.receive() }
        try await Task.sleep(for: .milliseconds(20))
        await b.close()
        await assertClosed { try await waitingA.value }
        await assertClosed { try await waitingB.value }
        await assertClosed { try await a.receive() }
        await assertClosed { try await b.receive() }
    }

    func testSendAfterCloseThrows() async throws {
        let (a, b) = makeInMemoryCircuitPair()
        await a.close()
        await assertClosed { try await a.send(Data([1])) }
        await assertClosed { try await b.send(Data([1])) }
    }

    func testFramesSentBeforePeerClosedStillArrive() async throws {
        let (a, b) = makeInMemoryCircuitPair()
        try await a.send(Data([9]))
        await a.close()
        let frame = try await b.receive()
        XCTAssertEqual(frame, Data([9]))
        await assertClosed { try await b.receive() }
    }

    func testCancellingReceiveClosesCircuit() async throws {
        let (a, b) = makeInMemoryCircuitPair()
        let waiting = Task { try await a.receive() }
        try await Task.sleep(for: .milliseconds(20))
        waiting.cancel()
        _ = try? await waiting.value
        await assertClosed { try await b.send(Data([1])) }
        await assertClosed { try await b.receive() }
    }

    private func assertClosed<T>(
        _ body: () async throws -> T, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await body()
            XCTFail("expected RelayError.closed", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? RelayError, .closed, file: file, line: line)
        }
    }
}
