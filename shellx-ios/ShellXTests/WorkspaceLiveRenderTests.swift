import ShellXAppCore
import ShellXAppTestSupport
import ShellXLinkCore
import SwiftUI
import XCTest
@testable import ShellX

/// `WorkspaceView` itself, over a hub connected to a fake Mac, with the real agent screen as the pane
/// of the agent chip (`dev.sh screenshots` writes the images out in en and vi).
@MainActor
final class WorkspaceLiveRenderTests: XCTestCase {
    func testRendersTheScreenFromTheHub() async throws {
        let rig = try await WorkspaceRig.make(in: self)
        // A request waits on the agent: its chip is the one shown, and the bar says so.
        await rig.mac.addPending(
            PendingItem(
                requestId: "p1", kind: .permission, agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx-ios",
                toolName: "Bash", toolInputPreview: #"{"command":"xcodebuild test"}"#, createdAtMs: 1_700_000_000_000,
                modes: ["once", "always", "deny"]))
        let waiting = await WorkspaceRig.eventually { rig.hub.pendingItems.count == 1 }
        XCTAssertTrue(waiting)
        // The agent's chat is already on the phone, so the render shows it.
        let session = SessionRef(
            machineID: rig.model.ref.machineID, sessionId: "s1", agent: "claude", workspaceTitle: "shellx-ios")
        let thread = rig.scope.agentThread(session)
        let run = Task { await thread.run() }
        let chatted = await WorkspaceRig.eventually { !thread.thread.entries.isEmpty }
        XCTAssertTrue(chatted)
        run.cancel()
        await thread.close()

        let live = NavigationStack { WorkspaceView(scope: rig.scope, ref: rig.model.ref, open: { _ in }) }
        let images = try SnapshotWriter().write(live, name: "workspace-live", settle: 0.6)

        XCTAssertEqual(images.count, 2)
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
        XCTAssertEqual(rig.model.panes.map(\.isAgent), [true, false])
    }

    func testAWorkspaceTheMacHasNotListedYetRendersTheSpinner() async throws {
        let rig = try await WorkspaceRig.make(opening: "new", in: self)
        XCTAssertEqual(rig.model.phase, .waiting)

        let live = NavigationStack { WorkspaceView(scope: rig.scope, ref: rig.model.ref, open: { _ in }) }
        let images = try SnapshotWriter().write(live, name: "workspace-live-waiting")

        XCTAssertEqual(images.count, 2)
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }

    func testRendersATerminalFromTheHub() async throws {
        let rig = try await WorkspaceRig.make(in: self)
        await rig.mac.setTerminalFixtures(["t-zsh": DemoTerminalScreens.shell])
        XCTAssertEqual(rig.model.selectedTerminalId, "t-zsh", "the Mac's selection: a shell")

        let live = NavigationStack { WorkspaceView(scope: rig.scope, ref: rig.model.ref, open: { _ in }) }
        let images = try SnapshotWriter().write(live, name: "workspace-live-terminal", settle: 1.0)

        XCTAssertEqual(images.count, 2)
        let opened = await WorkspaceRig.eventually { await rig.mac.terminalViewOpens.first?.terminalId == "t-zsh" }
        XCTAssertTrue(opened, "the page shown opened its terminal")
        let cols = await rig.mac.terminalViewOpens.first?.cols ?? 0
        XCTAssertGreaterThanOrEqual(cols, 20)
    }
}
