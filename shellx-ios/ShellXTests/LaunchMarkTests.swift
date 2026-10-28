import ShellXAppCore
import XCTest
@testable import ShellX

/// The launch's two latencies: one sample each per launch, none for a launch that signed in or paired first.
@MainActor
final class LaunchMarkTests: XCTestCase {
    func testTheWorkspaceListIsMeasuredOncePerLaunch() {
        let latency = LatencyLog()
        let launch = LaunchMark(latency: latency)

        launch.homeShown()
        XCTAssertNil(latency.summary(.launchToWorkspaceList), "the home showed; no Mac has listed yet")
        launch.workspacesListed()
        launch.workspacesListed()

        XCTAssertEqual(latency.summary(.launchToHome)?.count, 1)
        XCTAssertEqual(latency.summary(.launchToWorkspaceList)?.count, 1, "a list after the first is not a launch")
    }

    func testALaunchThatSignedInFirstHasNoSample() {
        let latency = LatencyLog()
        let launch = LaunchMark(latency: latency)

        launch.skip()
        launch.homeShown()
        launch.workspacesListed()

        XCTAssertNil(latency.summary(.launchToHome))
        XCTAssertNil(latency.summary(.launchToWorkspaceList))
    }
}
