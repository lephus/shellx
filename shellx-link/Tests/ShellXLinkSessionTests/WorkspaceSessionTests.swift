import Foundation
import ShellXLinkCore
import ShellXLinkRelay
@testable import ShellXLinkSession
import XCTest

/// The workspace list and the workspace control calls of ShellX Link (PROTOCOL.md sections 4, 6 and 10).
final class WorkspaceSessionTests: XCTestCase {
    private var serveTasks: [Task<Void, Never>] = []
    private var clients: [LinkClient] = []

    override func tearDown() async throws {
        for client in clients { await client.close() }
        for task in serveTasks {
            task.cancel()
            await task.value
        }
        serveTasks = []
        clients = []
    }

    // MARK: - Features and unsupported

    func testWelcomeListsWorkspaceFeatures() async throws {
        let source = FakeWorkspaceSource()
        let control = FakeWorkspaceControl()
        let both = try await welcomeFeatures(makeHost(workspaces: source, control: control))
        XCTAssertEqual(both, [ShellXLink.workspacesFeature, ShellXLink.workspaceControlFeature])
        XCTAssertEqual(both, ["workspaces", "workspace_control"])

        let listOnly = try await welcomeFeatures(makeHost(workspaces: source))
        XCTAssertEqual(listOnly, ["workspaces"])
        let controlOnly = try await welcomeFeatures(makeHost(control: control))
        XCTAssertEqual(controlOnly, ["workspace_control"])
        let neither = try await welcomeFeatures(makeHost())
        XCTAssertEqual(neither, [], "a host without the sources offers neither feature")

        let withAttachments = try await welcomeFeatures(
            makeHost(chat: FakeChatSource(acceptsAttachments: true), workspaces: source, control: control))
        XCTAssertEqual(withAttachments, ["attachments", "workspaces", "workspace_control"])

        let client = try await connect(makeHost(workspaces: source, control: control))
        XCTAssertEqual(client.hostFeatures, ["workspaces", "workspace_control"])
    }

    func testWorkspacesUnsupportedWithoutSource() async throws {
        let client = try await connect(makeHost())
        await expectRemote("unsupported") { try await client.workspaces() }
        await expectRemote("unsupported") { try await client.createWorkspace() }
        await expectRemote("unsupported") { try await client.renameWorkspace(workspaceId: "w1", title: "docs") }
        await expectRemote("unsupported") { try await client.closeWorkspace(workspaceId: "w1") }
        // The session is still usable after the refusals.
        let snapshot = try await within { try await client.snapshot() }
        XCTAssertEqual(snapshot.pending, [])
    }

    func testEachSourceServesOnlyItsOwnCalls() async throws {
        let listOnly = try await connect(makeHost(workspaces: FakeWorkspaceSource([linkWorkspace("w1")])))
        let list = try await within { try await listOnly.workspaces() }
        XCTAssertEqual(list.workspaces.map(\.workspaceId), ["w1"])
        await expectRemote("unsupported") { try await listOnly.createWorkspace() }
        await expectRemote("unsupported") { try await listOnly.closeWorkspace(workspaceId: "w1") }

        let control = FakeWorkspaceControl()
        let controlOnly = try await connect(makeHost(control: control))
        await expectRemote("unsupported") { try await controlOnly.workspaces() }
        let created = try await within { try await controlOnly.createWorkspace() }
        XCTAssertEqual(created.outcome, .ok)
        XCTAssertEqual(control.calls, [.create])
    }

    // MARK: - List and changes

    func testWorkspaceListAndChangePushed() async throws {
        let source = FakeWorkspaceSource([linkWorkspace("w1", title: "shellx", order: 0, branch: "main")])
        let client = try await connect(makeHost(workspaces: source))
        let list = try await within { try await client.workspaces() }
        XCTAssertEqual(list.revision, 0)
        XCTAssertEqual(list.workspaces, [linkWorkspace("w1", title: "shellx", order: 0, branch: "main")])

        let seen = collect(client.workspaceChanges)
        let start = ContinuousClock.now
        source.upsert(linkWorkspace("w2", title: "docs", order: 1, directory: "~/docs", ports: [3000]))
        let arrived = await eventually(within: .seconds(1)) { !seen.items.isEmpty }
        XCTAssertTrue(arrived, "workspace.changed did not arrive within 1 s")
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1))
        XCTAssertEqual(seen.items.first?.revision, 1)
        XCTAssertEqual(
            seen.items.first?.upserted, [linkWorkspace("w2", title: "docs", order: 1, directory: "~/docs", ports: [3000])])
        XCTAssertEqual(seen.items.first?.removed, [])

        source.remove("w1")
        let removed = await eventually { seen.items.count == 2 }
        XCTAssertTrue(removed)
        XCTAssertEqual(seen.items.last?.revision, 2)
        XCTAssertEqual(seen.items.last?.removed, ["w1"])
        let after = try await within { try await client.workspaces() }
        XCTAssertEqual(after.revision, 2)
        XCTAssertEqual(after.workspaces.map(\.workspaceId), ["w2"])
    }

    func testSessionEndReleasesWorkspaceSubscription() async throws {
        let source = FakeWorkspaceSource()
        let rig = makeHost(workspaces: source)
        let (end, served) = startServe(rig.host)
        let client = try await connectClient(end, rig)
        _ = try await within { try await client.workspaces() }
        XCTAssertEqual(source.activeSubscribers, 1)
        XCTAssertEqual(source.changesCalls, 1)
        await client.close()
        let ended = await eventually { served.isSet }
        XCTAssertTrue(ended)
        let released = await eventually { source.activeSubscribers == 0 }
        XCTAssertTrue(released, "the host leaked its workspaceChanges() subscription")
    }

    // MARK: - Control

    func testCreateRenameCloseReachControl() async throws {
        let control = FakeWorkspaceControl()
        control.setCreate(.ok, workspaceId: "ws-9")
        let client = try await connect(makeHost(workspaces: FakeWorkspaceSource(), control: control))

        let created = try await within { try await client.createWorkspace() }
        XCTAssertEqual(created.outcome, .ok)
        XCTAssertEqual(created.workspaceId, "ws-9")
        let renamed = try await within { try await client.renameWorkspace(workspaceId: "w1", title: "Docs \u{1F4C4}") }
        XCTAssertEqual(renamed, .ok)
        let closed = try await within { try await client.closeWorkspace(workspaceId: "w1") }
        XCTAssertEqual(closed, .ok)
        XCTAssertEqual(
            control.calls, [.create, .rename(workspaceId: "w1", title: "Docs \u{1F4C4}"), .close(workspaceId: "w1")])

        // Every outcome comes back as the source gave it, an unknown one included.
        control.setRename(.notFound)
        control.setClose(.refused)
        control.setCreate(.failed, workspaceId: nil)
        let notFound = try await within { try await client.renameWorkspace(workspaceId: "gone", title: "x") }
        XCTAssertEqual(notFound, .notFound)
        let refused = try await within { try await client.closeWorkspace(workspaceId: "last") }
        XCTAssertEqual(refused, .refused)
        let failed = try await within { try await client.createWorkspace() }
        XCTAssertEqual(failed.outcome, .failed)
        XCTAssertNil(failed.workspaceId)
        control.setClose(.other("later_outcome"))
        let later = try await within { try await client.closeWorkspace(workspaceId: "w1") }
        XCTAssertEqual(later, .other("later_outcome"))
    }

    func testCreateResultWithoutOkCarriesNoWorkspaceId() async throws {
        let control = FakeWorkspaceControl()
        control.setCreate(.refused, workspaceId: "ws-leaked")
        let rig = makeHost(workspaces: FakeWorkspaceSource(), control: control)
        let (end, _) = startServe(rig.host)
        let raw = try await rawChannel(end, rig)
        try await raw.send(.hello(clientVersion: "raw", deviceName: "raw"))
        _ = try await raw.receive()

        try await raw.send(.workspaceCreate(callId: "c1"))
        let answer = try await within { try await raw.receive() }
        XCTAssertEqual(answer, .workspaceCreateResult(callId: "c1", outcome: .refused, workspaceId: nil))

        control.setCreate(.ok, workspaceId: "ws-new")
        try await raw.send(.workspaceCreate(callId: "c2"))
        let ok = try await within { try await raw.receive() }
        XCTAssertEqual(ok, .workspaceCreateResult(callId: "c2", outcome: .ok, workspaceId: "ws-new"))
    }

    func testRenameTitleTooLongIsBadRequest() async throws {
        let control = FakeWorkspaceControl()
        let rig = makeHost(workspaces: FakeWorkspaceSource(), control: control)
        let (end, _) = startServe(rig.host)
        let raw = try await rawChannel(end, rig)
        try await raw.send(.hello(clientVersion: "raw", deviceName: "raw"))
        _ = try await raw.receive()

        let tooLong = String(repeating: "t", count: ShellXLink.maxWorkspaceTitleBytes + 1)
        try await raw.send(.workspaceRename(callId: "c1", workspaceId: "w1", title: tooLong))
        let refused = try await within { try await raw.receive() }
        guard case let .error(code, _, callId) = refused else { return XCTFail("expected an error, got \(refused)") }
        XCTAssertEqual(code, "bad_request")
        XCTAssertEqual(callId, "c1")
        XCTAssertEqual(control.calls, [], "the source was called with a title that is too long")

        // Bytes, not characters: 257 two-byte characters are 514 bytes.
        let twoByte = String(repeating: "\u{E9}", count: 257)
        XCTAssertEqual(twoByte.utf8.count, 514)
        try await raw.send(.workspaceRename(callId: "c2", workspaceId: "w1", title: twoByte))
        let alsoRefused = try await within { try await raw.receive() }
        guard case let .error(code2, _, callId2) = alsoRefused else {
            return XCTFail("expected an error, got \(alsoRefused)")
        }
        XCTAssertEqual(code2, "bad_request")
        XCTAssertEqual(callId2, "c2")
        XCTAssertEqual(control.calls, [])

        // The longest title still goes through, and the session stays usable.
        let longest = String(repeating: "t", count: ShellXLink.maxWorkspaceTitleBytes)
        try await raw.send(.workspaceRename(callId: "c3", workspaceId: "w1", title: longest))
        let accepted = try await within { try await raw.receive() }
        XCTAssertEqual(accepted, .workspaceRenameResult(callId: "c3", outcome: .ok))
        XCTAssertEqual(control.calls, [.rename(workspaceId: "w1", title: longest)])
    }

    func testSlowControlDoesNotBlockTheSession() async throws {
        let source = FakeWorkspaceSource([linkWorkspace("w1")])
        let control = FakeWorkspaceControl()
        let gate = Gate()
        control.hold(until: gate)
        let client = try await connect(makeHost(workspaces: source, control: control))

        let closing = Task { try await client.closeWorkspace(workspaceId: "w1") }
        let reached = await eventually { control.calls == [.close(workspaceId: "w1")] }
        XCTAssertTrue(reached, "the close never reached the source")
        // The close is still waiting, and the host keeps answering other calls.
        let list = try await within { try await client.workspaces() }
        XCTAssertEqual(list.workspaces.map(\.workspaceId), ["w1"])
        let created = Task { try await client.createWorkspace() }
        let both = await eventually { control.calls.count == 2 }
        XCTAssertTrue(both, "a second control call waited behind the first")

        gate.open()
        let outcome = try await within { try await closing.value }
        XCTAssertEqual(outcome, .ok)
        let result = try await within { try await created.value }
        XCTAssertEqual(result.outcome, .ok)
    }

    // MARK: - Agent control

    func testWelcomeListsAgentCloseOnlyWithControl() async throws {
        let agents = FakeAgentControl()
        let alone = try await welcomeFeatures(makeHost(agentControl: agents))
        XCTAssertEqual(alone, [ShellXLink.agentCloseFeature])
        XCTAssertEqual(alone, ["agent_close"])

        let without = try await welcomeFeatures(makeHost(workspaces: FakeWorkspaceSource(), control: FakeWorkspaceControl()))
        XCTAssertEqual(without, ["workspaces", "workspace_control"], "a host without agent control does not offer it")

        let all = try await welcomeFeatures(
            makeHost(
                chat: FakeChatSource(acceptsAttachments: true), workspaces: FakeWorkspaceSource(),
                control: FakeWorkspaceControl(), agentControl: agents))
        XCTAssertEqual(all, ["attachments", "workspaces", "workspace_control", "agent_close"])

        let client = try await connect(makeHost(agentControl: agents))
        XCTAssertEqual(client.hostFeatures, ["agent_close"])
    }

    func testAgentCloseUnsupportedWithoutControl() async throws {
        // Workspace control alone does not take `agent.close`.
        let client = try await connect(makeHost(workspaces: FakeWorkspaceSource(), control: FakeWorkspaceControl()))
        await expectRemote("unsupported") { try await client.closeAgent(sessionId: "sess-1") }
        // The session is still usable after the refusal.
        let snapshot = try await within { try await client.snapshot() }
        XCTAssertEqual(snapshot.pending, [])

        // The refusal names the call, so a raw client sees `error` with its call_id.
        let rig = makeHost()
        let (end, _) = startServe(rig.host)
        let raw = try await rawChannel(end, rig)
        try await raw.send(.hello(clientVersion: "raw", deviceName: "raw"))
        _ = try await within { try await raw.receive() }
        try await raw.send(.agentClose(callId: "c1", sessionId: "sess-1"))
        let answer = try await within { try await raw.receive() }
        guard case let .error(code, _, callId) = answer else { return XCTFail("expected error, got \(answer)") }
        XCTAssertEqual(code, "unsupported")
        XCTAssertEqual(callId, "c1")
    }

    func testAgentCloseReachesControl() async throws {
        let agents = FakeAgentControl()
        let client = try await connect(makeHost(agentControl: agents))

        let closed = try await within { try await client.closeAgent(sessionId: "sess-1") }
        XCTAssertEqual(closed, .ok)
        XCTAssertEqual(agents.calls, ["sess-1"])

        // Every outcome comes back as the control gave it, an unknown one included.
        agents.setClose(.notFound)
        let notFound = try await within { try await client.closeAgent(sessionId: "sess-1") }
        XCTAssertEqual(notFound, .notFound)
        agents.setClose(.refused)
        let refused = try await within { try await client.closeAgent(sessionId: "sess-1") }
        XCTAssertEqual(refused, .refused)
        agents.setClose(.failed)
        let failed = try await within { try await client.closeAgent(sessionId: "sess-1") }
        XCTAssertEqual(failed, .failed)
        agents.setClose(.other("busy"))
        let busy = try await within { try await client.closeAgent(sessionId: "sess-1") }
        XCTAssertEqual(busy, .other("busy"))
        XCTAssertEqual(agents.calls, ["sess-1", "sess-1", "sess-1", "sess-1", "sess-1"])
    }

    func testAgentCloseResultFromAClientIsBadRequest() async throws {
        let agents = FakeAgentControl()
        let rig = makeHost(agentControl: agents)
        let (end, _) = startServe(rig.host)
        let raw = try await rawChannel(end, rig)
        try await raw.send(.hello(clientVersion: "raw", deviceName: "raw"))
        _ = try await within { try await raw.receive() }
        try await raw.send(.agentCloseResult(callId: "c1", outcome: .ok))
        let answer = try await within { try await raw.receive() }
        guard case let .error(code, _, callId) = answer else { return XCTFail("expected error, got \(answer)") }
        XCTAssertEqual(code, "bad_request")
        XCTAssertEqual(callId, "c1")
        XCTAssertEqual(agents.calls, [])
    }

    func testSlowAgentCloseDoesNotBlockTheSession() async throws {
        let source = FakeWorkspaceSource([linkWorkspace("w1")])
        let agents = FakeAgentControl()
        let gate = Gate()
        agents.hold(until: gate)
        let client = try await connect(makeHost(workspaces: source, agentControl: agents))

        let closing = Task { try await client.closeAgent(sessionId: "sess-1") }
        let reached = await eventually { agents.calls == ["sess-1"] }
        XCTAssertTrue(reached, "the close never reached the control")
        // The close is still waiting, and the host keeps answering other calls.
        let list = try await within { try await client.workspaces() }
        XCTAssertEqual(list.workspaces.map(\.workspaceId), ["w1"])
        let second = Task { try await client.closeAgent(sessionId: "sess-2") }
        let both = await eventually { agents.calls == ["sess-1", "sess-2"] }
        XCTAssertTrue(both, "a second close waited behind the first")

        gate.open()
        let outcome = try await within { try await closing.value }
        XCTAssertEqual(outcome, .ok)
        let result = try await within { try await second.value }
        XCTAssertEqual(result, .ok)
    }

    // MARK: - Terminal control

    func testWelcomeListsTerminalCloseOnlyWithControl() async throws {
        let terminals = FakeTerminalControl()
        let alone = try await welcomeFeatures(makeHost(terminalControl: terminals))
        XCTAssertEqual(alone, [ShellXLink.terminalCloseFeature])
        XCTAssertEqual(alone, ["terminal_close"])

        let without = try await welcomeFeatures(
            makeHost(workspaces: FakeWorkspaceSource(), control: FakeWorkspaceControl(), agentControl: FakeAgentControl()))
        XCTAssertEqual(
            without, ["workspaces", "workspace_control", "agent_close"],
            "a host without terminal control does not offer it")

        let all = try await welcomeFeatures(
            makeHost(
                chat: FakeChatSource(acceptsAttachments: true), workspaces: FakeWorkspaceSource(),
                control: FakeWorkspaceControl(), agentControl: FakeAgentControl(), terminalControl: terminals))
        XCTAssertEqual(all, ["attachments", "workspaces", "workspace_control", "agent_close", "terminal_close"])

        let client = try await connect(makeHost(terminalControl: terminals))
        XCTAssertEqual(client.hostFeatures, ["terminal_close"])
    }

    func testTerminalCloseUnsupportedWithoutControl() async throws {
        // Workspace and agent control do not take `terminal.close`.
        let client = try await connect(
            makeHost(workspaces: FakeWorkspaceSource(), control: FakeWorkspaceControl(), agentControl: FakeAgentControl()))
        await expectRemote("unsupported") { try await client.closeTerminal(workspaceId: "ws-1", terminalId: "t-1") }
        // The session is still usable after the refusal.
        let snapshot = try await within { try await client.snapshot() }
        XCTAssertEqual(snapshot.pending, [])

        // The refusal names the call, so a raw client sees `error` with its call_id.
        let rig = makeHost()
        let (end, _) = startServe(rig.host)
        let raw = try await rawChannel(end, rig)
        try await raw.send(.hello(clientVersion: "raw", deviceName: "raw"))
        _ = try await within { try await raw.receive() }
        try await raw.send(.terminalClose(callId: "c1", workspaceId: "ws-1", terminalId: "t-1"))
        let answer = try await within { try await raw.receive() }
        guard case let .error(code, _, callId) = answer else { return XCTFail("expected error, got \(answer)") }
        XCTAssertEqual(code, "unsupported")
        XCTAssertEqual(callId, "c1")
    }

    func testTerminalCloseReachesControl() async throws {
        let terminals = FakeTerminalControl()
        let client = try await connect(makeHost(terminalControl: terminals))

        let closed = try await within { try await client.closeTerminal(workspaceId: "ws-1", terminalId: "t-1") }
        XCTAssertEqual(closed, .ok)
        XCTAssertEqual(terminals.calls.map { [$0.workspaceId, $0.terminalId] }, [["ws-1", "t-1"]])

        // Every outcome comes back as the control gave it, an unknown one included.
        terminals.setClose(.notFound)
        let notFound = try await within { try await client.closeTerminal(workspaceId: "ws-1", terminalId: "t-1") }
        XCTAssertEqual(notFound, .notFound)
        terminals.setClose(.refused)
        let refused = try await within { try await client.closeTerminal(workspaceId: "ws-1", terminalId: "t-1") }
        XCTAssertEqual(refused, .refused)
        terminals.setClose(.other("busy"))
        let busy = try await within { try await client.closeTerminal(workspaceId: "ws-1", terminalId: "t-1") }
        XCTAssertEqual(busy, .other("busy"))
        XCTAssertEqual(terminals.calls.count, 4)
        XCTAssertTrue(terminals.calls.allSatisfy { $0.workspaceId == "ws-1" && $0.terminalId == "t-1" })
    }

    func testTerminalCloseResultFromAClientIsBadRequest() async throws {
        let terminals = FakeTerminalControl()
        let rig = makeHost(terminalControl: terminals)
        let (end, _) = startServe(rig.host)
        let raw = try await rawChannel(end, rig)
        try await raw.send(.hello(clientVersion: "raw", deviceName: "raw"))
        _ = try await within { try await raw.receive() }
        try await raw.send(.terminalCloseResult(callId: "c1", outcome: .ok))
        let answer = try await within { try await raw.receive() }
        guard case let .error(code, _, callId) = answer else { return XCTFail("expected error, got \(answer)") }
        XCTAssertEqual(code, "bad_request")
        XCTAssertEqual(callId, "c1")
        XCTAssertEqual(terminals.calls.count, 0)
    }

    func testSlowTerminalCloseDoesNotBlockTheSession() async throws {
        let source = FakeWorkspaceSource([linkWorkspace("w1")])
        let terminals = FakeTerminalControl()
        let gate = Gate()
        terminals.hold(until: gate)
        let client = try await connect(makeHost(workspaces: source, terminalControl: terminals))

        let closing = Task { try await client.closeTerminal(workspaceId: "w1", terminalId: "t-1") }
        let reached = await eventually { terminals.calls.map(\.terminalId) == ["t-1"] }
        XCTAssertTrue(reached, "the close never reached the control")
        // The close is still waiting, and the host keeps answering other calls.
        let list = try await within { try await client.workspaces() }
        XCTAssertEqual(list.workspaces.map(\.workspaceId), ["w1"])
        let second = Task { try await client.closeTerminal(workspaceId: "w1", terminalId: "t-2") }
        let both = await eventually { terminals.calls.map(\.terminalId) == ["t-1", "t-2"] }
        XCTAssertTrue(both, "a second close waited behind the first")

        gate.open()
        let outcome = try await within { try await closing.value }
        XCTAssertEqual(outcome, .ok)
        let result = try await within { try await second.value }
        XCTAssertEqual(result, .ok)
    }

    // MARK: - Oversize (PROTOCOL.md section 6)

    func testOversizedListIsShrunk() async throws {
        let many = (0..<60).map { index in
            linkWorkspace(
                String(format: "w%02d", index), order: index, directory: "~/" + String(repeating: "d", count: 1_200),
                branch: "main", ports: [3000, 3001])
        }
        // Pinned: the list needs step 2, step 1 (ports) is not enough.
        XCTAssertFalse(fits(many))
        XCTAssertFalse(fits(try shrunk(many, step: 1)))
        XCTAssertTrue(fits(try shrunk(many, step: 2)))

        let client = try await connect(makeHost(workspaces: FakeWorkspaceSource(many)))
        let list = try await within { try await client.workspaces() }
        XCTAssertEqual(list.workspaces.count, 60, "the host never sends a list with a workspace left out")
        XCTAssertEqual(list.workspaces.map(\.workspaceId), many.map(\.workspaceId))
        XCTAssertTrue(list.workspaces.allSatisfy { $0.ports == nil }, "ports are dropped first")
        XCTAssertTrue(list.workspaces.allSatisfy { $0.directory == nil }, "directories go when ports are not enough")
        XCTAssertTrue(list.workspaces.allSatisfy { $0.branch == "main" }, "the steps stop at the first that fits")
        XCTAssertEqual(list.workspaces.first?.terminals.first?.title, "zsh")
        XCTAssertEqual(list.workspaces.first?.title, "shellx")
    }

    func testShrinkStepsApplyInOrder() async throws {
        let long = String(repeating: "x", count: 1_200)
        // Each case needs exactly the step it names: the step before it is not enough.
        let cases: [(step: Int, make: (Int) -> LinkWorkspace)] = [
            (1, { linkWorkspace(String(format: "w%02d", $0), order: $0, directory: "~/code", branch: "main", ports: Array(3000..<3200)) }),
            (3, { linkWorkspace(String(format: "w%02d", $0), order: $0, directory: "~/code", branch: long, ports: [3000]) }),
            (4, {
                linkWorkspace(
                    String(format: "w%02d", $0), order: $0, directory: "~/code", branch: "main", ports: [3000],
                    terminals: [LinkTerminal(terminalId: "t\($0)", title: long, order: 0, selected: true, sessionId: "s\($0)")])
            }),
        ]
        for (step, make) in cases {
            let many = (0..<60).map(make)
            XCTAssertFalse(fits(many), "step \(step)")
            XCTAssertTrue(fits(try shrunk(many, step: step)), "step \(step)")
            if step > 1 { XCTAssertFalse(fits(try shrunk(many, step: step - 1)), "step \(step)") }
            let client = try await connect(makeHost(workspaces: FakeWorkspaceSource(many)))
            let list = try await within { try await client.workspaces() }
            XCTAssertEqual(list.workspaces, try shrunk(many, step: step), "step \(step)")
            await client.close()
        }
    }

    func testNothingFitsAnswersTooLarge() async throws {
        // A workspace's own title is never dropped, so this one fits at no step.
        let huge = linkWorkspace("huge", title: String(repeating: "w", count: 70_000), order: 1)
        let source = FakeWorkspaceSource([linkWorkspace("w1")])
        let client = try await connect(makeHost(workspaces: source))
        source.upsert(huge)
        await expectRemote("too_large") { try await client.workspaces() }
        // The session is still usable, and the list is served again once the workspace is gone.
        source.remove("huge")
        let list = try await within { try await client.workspaces() }
        XCTAssertEqual(list.workspaces.map(\.workspaceId), ["w1"])
    }

    func testOversizedChangeIsShrunk() async throws {
        let source = FakeWorkspaceSource()
        let client = try await connect(makeHost(workspaces: source))
        let seen = collect(client.workspaceChanges)
        let many = (0..<60).map { index in
            linkWorkspace(
                String(format: "w%02d", index), order: index, directory: "~/" + String(repeating: "d", count: 1_200),
                branch: "main", ports: [3000])
        }
        source.upsert(all: many)
        let arrived = await eventually { !seen.items.isEmpty }
        XCTAssertTrue(arrived, "an oversized workspace.changed was not shrunk to fit")
        let change = try XCTUnwrap(seen.items.first)
        XCTAssertEqual(change.revision, 1)
        XCTAssertEqual(change.upserted.map(\.workspaceId), many.map(\.workspaceId))
        XCTAssertEqual(change.upserted, try shrunk(many, step: 2))
    }

    func testChangeThatDoesNotFitIsDroppedAndTheGapShows() async throws {
        let source = FakeWorkspaceSource([linkWorkspace("w1")])
        let client = try await connect(makeHost(workspaces: source))
        let first = try await within { try await client.workspaces() }
        let seen = collect(client.workspaceChanges)

        source.upsert(linkWorkspace("huge", title: String(repeating: "w", count: 70_000), order: 1))   // revision 1: dropped
        source.upsert(linkWorkspace("w2", order: 2))                                                  // revision 2
        let arrived = await eventually { !seen.items.isEmpty }
        XCTAssertTrue(arrived)
        XCTAssertEqual(seen.items.map(\.revision), [2], "the dropped change must not reach the client")
        XCTAssertEqual(seen.items.first?.revision, first.revision + 2, "the client sees the gap")
        // The client's way out: ask for the list again. It does not fit while the huge workspace is there.
        await expectRemote("too_large") { try await client.workspaces() }
        source.remove("huge")
        let after = try await within { try await client.workspaces() }
        XCTAssertEqual(after.workspaces.map(\.workspaceId), ["w1", "w2"])
    }

    // MARK: - Helpers

    private struct Rig {
        let host: LinkHost
        let hostKey: NoiseStaticKey
        let clientKey: NoiseStaticKey
    }

    private func makeHost(
        chat: (any AgentChatSource)? = nil, workspaces: (any WorkspaceSource)? = nil,
        control: (any WorkspaceControl)? = nil, agentControl: (any AgentControl)? = nil,
        terminalControl: (any TerminalControl)? = nil
    ) -> Rig {
        let hostKey = NoiseStaticKey()
        let clientKey = NoiseStaticKey()
        let trusted: Set<Data> = [clientKey.publicKey]
        let host = LinkHost(
            key: hostKey, trustedClients: { trusted }, feed: FakeFeedSource(), sessions: nil, chat: chat,
            workspaces: workspaces, workspaceControl: control, agentControl: agentControl,
            terminalControl: terminalControl, hostVersion: "test-host", machineName: "Test Mac",
            timings: .standard)
        return Rig(host: host, hostKey: hostKey, clientKey: clientKey)
    }

    /// `list` with shrink steps 1 to `step` applied to every workspace.
    private func shrunk(_ list: [LinkWorkspace], step: Int) throws -> [LinkWorkspace] {
        try list.map { try XCTUnwrap($0.shrunk(step: step)) }
    }

    /// Whether `workspace.list` carrying `list` fits one frame.
    private func fits(_ list: [LinkWorkspace]) -> Bool {
        (try? LinkCodec.encode(.workspaces(callId: "c1", revision: 0, workspaces: list))) != nil
    }

    /// Serves one new circuit; returns the client end and a flag set when `serve` returns.
    private func startServe(_ host: LinkHost) -> (any RelayCircuit, Flag) {
        let (clientEnd, hostEnd) = makeInMemoryCircuitPair()
        let done = Flag()
        serveTasks.append(Task {
            await host.serve(hostEnd)
            done.set()
        })
        return (clientEnd, done)
    }

    private func connect(_ rig: Rig) async throws -> LinkClient {
        let (end, _) = startServe(rig.host)
        return try await connectClient(end, rig)
    }

    private func connectClient(_ end: any RelayCircuit, _ rig: Rig) async throws -> LinkClient {
        let client = try await LinkClient.connect(
            end, key: rig.clientKey, hostKey: rig.hostKey.publicKey, clientVersion: "test-client",
            deviceName: "Test Phone", timings: .standard)
        clients.append(client)
        return client
    }

    private func rawChannel(_ end: any RelayCircuit, _ rig: Rig) async throws -> SecureChannel {
        let hostPublic = rig.hostKey.publicKey
        return try await SecureChannel.open(end, role: .initiator, key: rig.clientKey, trusts: { $0 == hostPublic })
    }

    /// The `features` of the `welcome` the host sends to a raw client.
    private func welcomeFeatures(_ rig: Rig) async throws -> [String] {
        let (end, _) = startServe(rig.host)
        let raw = try await rawChannel(end, rig)
        try await raw.send(.hello(clientVersion: "raw", deviceName: "raw"))
        let welcome = try await within { try await raw.receive() }
        guard case let .welcome(_, _, _, features) = welcome else {
            XCTFail("expected welcome, got \(welcome)")
            return []
        }
        return features
    }

    /// Asserts that `operation` fails with the host's `error` `code`.
    private func expectRemote<T: Sendable>(
        _ code: String, file: StaticString = #filePath, line: UInt = #line,
        _ operation: @escaping @Sendable () async throws -> T
    ) async {
        do {
            _ = try await within { try await operation() }
            XCTFail("expected error \(code), got an answer", file: file, line: line)
        } catch {
            guard case let .remote(got, _)? = error as? LinkClientError else {
                return XCTFail("unexpected error \(error)", file: file, line: line)
            }
            XCTAssertEqual(got, code, file: file, line: line)
        }
    }
}
