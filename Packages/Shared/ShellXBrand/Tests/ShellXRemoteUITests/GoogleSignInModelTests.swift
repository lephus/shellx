import Foundation
import Testing
import ShellXRemoteCore
@testable import ShellXRemoteUI

/// Keeps a `signIn` closure pending until the test resolves it.
@MainActor private final class Gate {
    var continuation: CheckedContinuation<String, any Error>?
    var runs = 0
    var cancels = 0
    func wait() async throws -> String {
        runs += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func resolve(_ email: String) { continuation?.resume(returning: email); continuation = nil }
    func fail(_ code: String) { continuation?.resume(throwing: ShellXCoreError(code: code, message: "")); continuation = nil }
}

@MainActor private final class Reports { var values: [Bool] = [] }

@MainActor private func model(_ gate: Gate, _ reports: Reports = Reports()) -> GoogleSignInModel {
    let m = GoogleSignInModel(purpose: .signIn, labels: .english,
                              signIn: { try await gate.wait() }, cancel: { gate.cancels += 1 })
    m.onFinished = { reports.values.append($0) }
    return m
}

@MainActor @Test func startShowsWaitingThenTheEmail() async {
    let gate = Gate(), reports = Reports()
    let m = model(gate, reports)
    let task = m.start()
    #expect(m.phase == .waiting)
    #expect(m.errorText == nil)
    while gate.continuation == nil { await Task.yield() }
    gate.resolve("g@shellx.test")
    await task?.value
    #expect(m.phase == .signedIn(email: "g@shellx.test"))
    #expect(reports.values.isEmpty)
    m.finish()
    #expect(reports.values == [true])
}

@MainActor @Test func startTwiceRunsOneFlow() async {
    let gate = Gate()
    let m = model(gate)
    let first = m.start()
    #expect(m.start() == nil)
    while gate.continuation == nil { await Task.yield() }
    gate.resolve("g@shellx.test")
    await first?.value
    #expect(gate.runs == 1)
}

@MainActor @Test func cancelWhileWaitingCancelsTheFlowAndCloses() async {
    let gate = Gate(), reports = Reports()
    let m = model(gate, reports)
    let task = m.start()
    while gate.continuation == nil { await Task.yield() }
    let cancelTask = m.cancel()
    #expect(reports.values == [false])
    gate.fail("google_cancelled")
    await task?.value
    await cancelTask?.value
    #expect(gate.cancels == 1)
    #expect(m.phase == .ready)
    #expect(m.errorText == nil)
    #expect(reports.values == [false])
}

@MainActor @Test func googleCancelledFromTheBrowserStaysOpenWithoutError() async {
    let gate = Gate(), reports = Reports()
    let m = model(gate, reports)
    let task = m.start()
    while gate.continuation == nil { await Task.yield() }
    gate.fail("google_cancelled")
    await task?.value
    #expect(m.phase == .ready)
    #expect(m.errorText == nil)
    #expect(reports.values.isEmpty)
}

@MainActor @Test func failureShowsTheMessageAndAllowsRetry() async {
    let gate = Gate()
    let m = model(gate)
    let task = m.start()
    while gate.continuation == nil { await Task.yield() }
    gate.fail("switch_from_signed_in_device")
    await task?.value
    #expect(m.phase == .ready)
    #expect(m.errorText == SignInErrorLabels.english.switchFromSignedInDevice)
    let again = m.start()
    #expect(again != nil)
    #expect(m.errorText == nil)
    while gate.continuation == nil { await Task.yield() }
    gate.resolve("g@shellx.test")
    await again?.value
    #expect(gate.runs == 2)
}

@MainActor @Test func aTimeoutShowsItsMessageAndAllowsRetry() async {
    let gate = Gate()
    let m = model(gate)
    let task = m.start()
    while gate.continuation == nil { await Task.yield() }
    gate.fail("google_timeout")
    await task?.value
    #expect(m.phase == .ready)
    #expect(m.errorText == SignInErrorLabels.english.timeout)
    #expect(m.start() != nil)
    while gate.continuation == nil { await Task.yield() }
    gate.resolve("g@shellx.test")
}
