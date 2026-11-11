import Foundation
import Testing
import ShellXRemoteCore
@testable import ShellXRemoteUI

/// Keeps an injected call pending until the test resolves it, and records the arguments of every call.
/// (The plan's `Gate<Value>`; named apart from `GoogleSignInModelTests`'s private `Gate`.)
@MainActor final class CallGate<Value: Sendable> {
    private(set) var calls: [[String]] = []
    /// `Task.isCancelled` of each call, read right after its gate opened.
    private(set) var cancelledAfterOpening: [Bool] = []
    private var continuation: CheckedContinuation<Value, any Error>?

    var isPending: Bool { continuation != nil }

    func wait(_ args: [String]) async throws -> Value {
        calls.append(args)
        defer { cancelledAfterOpening.append(Task.isCancelled) }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    /// True once a call waits here (a bounded wait, so a missing call fails the test instead of hanging it).
    func pending() async -> Bool {
        var rounds = 0
        while continuation == nil && rounds < 10_000 {
            rounds += 1
            await Task.yield()
        }
        return continuation != nil
    }

    func resolve(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
    func fail(_ error: any Error) { continuation?.resume(throwing: error); continuation = nil }
    func fail(_ code: String) { fail(ShellXCoreError(code: code, message: "")) }
}

/// The injected clock (the plan's `Clock`; named apart from the standard library's `Clock` protocol).
@MainActor final class SignInClock {
    static let t0 = Date(timeIntervalSince1970: 1_000)
    var now = SignInClock.t0
}

/// What `onFinished` reported, in order.
@MainActor final class FinishReports { var values: [Bool] = [] }

/// An `EmailSignInModel` over two gates and a manual clock.
@MainActor final class EmailSignInRig {
    let send: CallGate<EmailCodeChallenge>
    let verify: CallGate<String>
    let clock: SignInClock
    let reports: FinishReports
    let model: EmailSignInModel

    init() {
        let send = CallGate<EmailCodeChallenge>(), verify = CallGate<String>(), clock = SignInClock(), reports = FinishReports()
        self.send = send
        self.verify = verify
        self.clock = clock
        self.reports = reports
        model = EmailSignInModel(
            labels: .english,
            requestCode: { try await send.wait([$0]) },
            verify: { try await verify.wait([$0, $1]) },
            now: { clock.now }
        )
        model.onFinished = { reports.values.append($0) }
    }

    static func challenge(_ id: String) -> EmailCodeChallenge {
        EmailCodeChallenge(challengeID: id, email: "foo@bar.com", expiresIn: 600, resendIn: 60)
    }

    /// `setEmail("Foo@Bar.com")` and `sendCode()`, then the relay answers `challenge("ch-1")`.
    func toCodeStep() async {
        model.setEmail("Foo@Bar.com")
        let task = model.sendCode()
        #expect(task != nil)
        #expect(await send.pending())
        send.resolve(Self.challenge("ch-1"))
        await task?.value
        #expect(model.step == .code)
    }
}
