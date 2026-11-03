import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class ShellXRoutineRunLauncherTests: XCTestCase {
    func testRunsTheSameCommandLaunchdCalls() async {
        let seen = ShellXAutomationsCallLog()
        let launcher = ShellXRoutineRunLauncher(cliPath: "/App/shellx", grace: .seconds(1)) { argv in
            seen.append(argv.joined(separator: " "))
            return 0
        }
        let problem = await launcher.start("abc")
        XCTAssertNil(problem)
        XCTAssertEqual(seen.all, ["/App/shellx routine run abc --trigger manual"])
    }

    func testEarlyNonZeroExitIsReported() async {
        let launcher = ShellXRoutineRunLauncher(cliPath: "/App/shellx", grace: .seconds(5)) { _ in 3 }
        let problem = await launcher.start("abc")
        XCTAssertTrue(problem?.contains("3") == true)
    }

    func testLaunchErrorIsReported() async {
        let launcher = ShellXRoutineRunLauncher(cliPath: "/App/shellx", grace: .seconds(5)) { _ in
            throw CocoaError(.fileNoSuchFile)
        }
        let problem = await launcher.start("abc")
        XCTAssertNotNil(problem)
        XCTAssertFalse(problem?.isEmpty ?? true)
    }

    func testLongRunCountsAsStartedAfterTheGrace() async {
        let launcher = ShellXRoutineRunLauncher(cliPath: "/App/shellx", grace: .milliseconds(50)) { _ in
            try await Task.sleep(for: .seconds(3))
            return 1
        }
        let clock = ContinuousClock()
        let started = clock.now
        let problem = await launcher.start("abc")
        XCTAssertNil(problem)
        XCTAssertLessThan(started.duration(to: clock.now), .seconds(2))
    }
}
