import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// The state and the one-line question of a workspace row, derived from the Mac's lists.
final class WorkspaceRowTests: XCTestCase {
    private let machine = "mac-1"

    private func rows(
        _ workspaces: [LinkWorkspace], sessions: [AgentSession] = [], pending: [MachinePendingItem] = [],
        finished: Set<String> = []
    ) -> [WorkspaceRow] {
        WorkspaceRow.rows(
            workspaces: WorkspaceSet(revision: 1, workspaces: workspaces), sessions: sessions, pending: pending,
            finished: finished, machineID: machine)
    }

    private func pending(
        _ id: String, workspace: String = "shellx", machineID: String? = nil, item: PendingItem? = nil
    ) -> MachinePendingItem {
        MachinePendingItem(
            machineID: machineID ?? machine, machineName: "Mac", item: item ?? pendingItem(id, workspace: workspace),
            actionable: true)
    }

    private func questionItem(_ id: String, prompts: [String], workspace: String = "shellx") -> PendingItem {
        PendingItem(
            requestId: id, kind: .question, agent: "claude", workspaceId: "ws-\(workspace)", workspaceTitle: workspace,
            createdAtMs: 1_700_000_000_000, modes: [],
            questions: prompts.enumerated().map { index, prompt in
                PendingQuestion(id: "q\(index)", header: "H", prompt: prompt, multiSelect: false, options: [])
            })
    }

    func testNeedsYouWinsOverRunning() {
        let result = rows(
            [linkWorkspace("shellx")], sessions: [agentSession("s1", state: .working)],
            pending: [pending("r1")], finished: ["s1"])

        XCTAssertEqual(result.map(\.state), [.needsYou])
    }

    func testRunningWinsOverDone() {
        let result = rows(
            [linkWorkspace("shellx")],
            sessions: [agentSession("s1", state: .working), agentSession("s2", state: .idle)], finished: ["s2"])

        XCTAssertEqual(result.map(\.state), [.running])
    }

    func testQuestionFromFirstPending() {
        let first = pending("r1", item: questionItem("r1", prompts: ["Nút chính nên dùng màu nào?", "Chạy test nào?"]))
        let second = pending("r2")
        let elsewhere = pending(
            "r3", workspace: "web", item: questionItem("r3", prompts: ["Không phải của shellx"], workspace: "web"))
        let otherMac = pending("r4", machineID: "mac-2", item: questionItem("r4", prompts: ["Mac khác"]))

        let result = rows(
            [linkWorkspace("shellx"), linkWorkspace("web", order: 1)],
            pending: [otherMac, first, second, elsewhere])

        XCTAssertEqual(result.map(\.state), [.needsYou, .needsYou])
        // The first pending of the workspace, on this Mac, and its first line.
        XCTAssertEqual(result[0].question, "Nút chính nên dùng màu nào?")
        XCTAssertEqual(result[1].question, "Không phải của shellx")
    }

    func testQuestionOfPermissionIsItsTellingValue() {
        let permission = pending(
            "r1",
            item: PendingItem(
                requestId: "r1", kind: .permission, agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx",
                toolName: "Bash", toolInputPreview: #"{"command":"git push origin main","description":"Push"}"#,
                createdAtMs: 1, modes: ["once", "deny"]))

        XCTAssertEqual(rows([linkWorkspace("shellx")], pending: [permission])[0].question, "git push origin main")
    }

    func testQuestionIsOneShortLine() {
        let long = String(repeating: "x", count: 500)
        let plan = pending(
            "r1",
            item: PendingItem(
                requestId: "r1", kind: .exitPlan, agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx",
                createdAtMs: 1, modes: ["manual", "deny"], planPreview: "\n  ## Ghép cặp Mac  \n\n1. Làm test"))
        XCTAssertEqual(rows([linkWorkspace("shellx")], pending: [plan])[0].question, "## Ghép cặp Mac")

        let cut = rows([linkWorkspace("shellx")], pending: [pending("r2", item: questionItem("r2", prompts: [long]))])[0]
        XCTAssertEqual(cut.question?.count, WorkspaceRow.questionLength)
        XCTAssertTrue(cut.question?.hasSuffix("…") ?? false)
    }

    func testDoneFromFinishedSession() {
        let result = rows(
            [linkWorkspace("shellx"), linkWorkspace("web", order: 1)],
            sessions: [agentSession("s1", state: .idle), agentSession("s2", state: .idle, workspace: "web")],
            finished: ["s1"])

        XCTAssertEqual(result.map(\.state), [.done, .idle])
        XCTAssertNil(result[0].question)
    }

    func testIdleWithoutAgent() {
        let result = rows(
            [linkWorkspace("shellx"), linkWorkspace("web", order: 1)],
            sessions: [agentSession("s2", state: .idle, workspace: "web")])

        XCTAssertEqual(result.map(\.state), [.idle, .idle])
        XCTAssertEqual(result.map(\.question), [nil, nil])
    }

    func testSessionNamedByATerminalBelongsToItsWorkspace() {
        // A session whose own `workspaceId` is empty is still the terminal's.
        let session = AgentSession(
            sessionId: "s1", agent: "claude", workspaceId: "", workspaceTitle: "", state: .working, stateSinceMs: 1,
            lastActivityMs: 1)
        let result = rows([linkWorkspace("shellx", terminals: [linkTerminal("t1", sessionId: "s1")])], sessions: [session])

        XCTAssertEqual(result.map(\.state), [.running])
    }

    func testRowCarriesTheWorkspaceInItsOrder() {
        let terminals = [linkTerminal("t1", sessionId: "s1"), linkTerminal("t2", order: 1, selected: true)]
        let result = rows([
            linkWorkspace("web", order: 1),
            linkWorkspace(
                "shellx", order: 0, terminals: terminals, directory: "~/code/shellx", branch: "main", ports: [3000]),
        ])

        XCTAssertEqual(result.map(\.id), [
            WorkspaceRef(machineID: machine, workspaceId: "ws-shellx"),
            WorkspaceRef(machineID: machine, workspaceId: "ws-web"),
        ])
        XCTAssertEqual(result[0].title, "shellx")
        XCTAssertEqual(result[0].directory, "~/code/shellx")
        XCTAssertEqual(result[0].branch, "main")
        XCTAssertEqual(result[0].ports, [3000])
        XCTAssertEqual(result[0].terminals, terminals)
        // No ports on the wire means none.
        XCTAssertEqual(result[1].ports, [])
        XCTAssertNil(result[1].directory)
        XCTAssertNil(result[1].branch)
    }
}
