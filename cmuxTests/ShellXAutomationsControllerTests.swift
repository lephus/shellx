import Foundation
import ShellXAutomations
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class ShellXAutomationsControllerTests: XCTestCase {
    private var fixture: ShellXAutomationsFixture!
    private var launcher: ShellXAutomationsFakeCreatorLauncher!
    private var controller: ShellXAutomationsController!
    private var events: [[String: Any]] = []

    /// What "Run now" reports; nil means the run started.
    private var runFailure: String?
    /// What "Draw flowchart" answers; each call's `SKILL.md` is kept in `drawnMarkdown`.
    private var fakeDrawer: (String) async throws -> ShellXAutomationFlow = { _ in ShellXAutomationsControllerTests.sampleFlow }
    private var drawnMarkdown: [String] = []

    override func setUp() async throws {
        fixture = ShellXAutomationsFixture()
        let launcher = ShellXAutomationsFakeCreatorLauncher(log: fixture.log)
        self.launcher = launcher
        controller = makeController(launcher: launcher)
    }

    /// A controller over the fixture whose creator sessions start through `launcher`.
    private func makeController(launcher: any ShellXCreatorProcessLaunching) -> ShellXAutomationsController {
        let log = fixture.log
        let store = fixture.store
        let controller = ShellXAutomationsController(
            library: fixture.library,
            store: store,
            scheduler: fixture.scheduler,
            creatorFactory: { _ in
                ShellXCreatorSession(
                    launcher: launcher,
                    systemPrompt: "Prompt",
                    workingDirectory: URL(filePath: "/tmp"),
                    localeIdentifier: "en_US",
                    cliPath: "/cli"
                )
            },
            runLauncher: { [weak self] id in
                log.append("run " + id)
                return await self?.runFailure
            },
            terminalOpener: { automation in log.append("terminal " + automation.id) },
            fileOpener: { url in log.append("open " + url.lastPathComponent) },
            makeValidator: { _ in
                let names = Set(((try? await store.list()) ?? []).map(\.name))
                return ShellXAutomationValidator(existingNames: names, directoryExists: { _ in true }, claudeAvailable: true)
            },
            flowDrawer: { [weak self] markdown in
                guard let self else { throw CancellationError() }
                self.drawnMarkdown.append(markdown)
                return try await self.fakeDrawer(markdown)
            }
        )
        controller.emit = { [weak self] event in self?.events.append(event) }
        return controller
    }

    override func tearDown() async throws {
        controller.shutDown()
        fixture.remove()
        fixture = nil
        controller = nil
        launcher = nil
        events = []
        drawnMarkdown = []
    }

    // MARK: Tests

    func testListReturnsDTOs() async throws {
        let saved = try await fixture.store.save(fixture.cronDraft(), replacing: nil)
        try fixture.externalSkill("theirs")

        let reply = await controller.handle(method: "automations.list", params: [:])

        let list = try XCTUnwrap(result(reply)?["automations"] as? [[String: Any]])
        XCTAssertEqual(list.count, 2)
        let cron = try XCTUnwrap(list.first { $0["id"] as? String == saved.id })
        XCTAssertEqual(cron["kind"] as? String, "cronjob")
        XCTAssertEqual(cron["name"] as? String, "nightly")
        XCTAssertEqual(cron["origin"] as? String, "shellx")
        XCTAssertEqual(cron["enabled"] as? Bool, true)
        XCTAssertEqual(cron["iphonePending"] as? Bool, false)
        XCTAssertEqual((cron["schedule"] as? [String: Any])?["cron"] as? String, "0 9 * * *")
        XCTAssertNotNil(cron["nextRun"] as? String)
        XCTAssertEqual((cron["notify"] as? [String: Any])?["targets"] as? [String], ["mac"])
        XCTAssertNil(cron["lastRun"])
        let external = try XCTUnwrap(list.first { $0["id"] as? String == "external:theirs" })
        XCTAssertEqual(external["origin"] as? String, "external")
        XCTAssertEqual(external["kind"] as? String, "skill")
        // Every value must survive the trip to the page.
        XCTAssertTrue(JSONSerialization.isValidJSONObject(reply))
    }

    func testListCarriesStepProgressOfARunningWorkflow() async throws {
        let saved = try await fixture.store.save(fixture.cronDraft(), replacing: nil)
        let begun = try await fixture.store.beginRun(id: saved.id, trigger: .manual, pid: 1)
        let run = try XCTUnwrap(begun)
        let record = ShellXRunRecord(
            status: .done, trigger: .manual, startedAt: Date(), finishedAt: Date(),
            summary: "ok", currentStep: 2, totalSteps: 3
        )
        try await fixture.store.finishRun(id: saved.id, runDirectory: run, record: record, pid: 1)

        let reply = await controller.handle(method: "automations.list", params: [:])

        let list = try XCTUnwrap(result(reply)?["automations"] as? [[String: Any]])
        let lastRun = try XCTUnwrap(list.first?["lastRun"] as? [String: Any])
        XCTAssertEqual(lastRun["currentStep"] as? Int, 2)
        XCTAssertEqual(lastRun["totalSteps"] as? Int, 3)
        XCTAssertEqual(lastRun["status"] as? String, "done")
    }

    func testSaveRejectsInvalidDraftWithIssues() async throws {
        var draft = fixture.cronDraft("Not Valid")
        draft.skillMarkdown = "---\nname: Not Valid\ndescription: d\n---\n"
        try await startCreatorWithDraft(draft)

        let reply = await controller.handle(method: "creator.save", params: [:])

        let issues = try XCTUnwrap(result(reply)?["issues"] as? [[String: Any]])
        XCTAssertTrue(issues.contains { $0["field"] as? String == "name" && $0["code"] as? String == "invalid" })
        XCTAssertTrue(events.contains { creatorEventType($0) == "validation" })
        let list = try await fixture.store.list()
        XCTAssertTrue(list.isEmpty)
        await waitUntil { self.fixture.log.all.contains { $0.contains("creator.send") && $0.contains("Fix:") } }
        XCTAssertTrue(fixture.log.all.contains { $0.contains("creator.send") && $0.contains("Fix:") })
    }

    /// A workflow with no steps is not saved; its issue names the steps field so the page shows it there.
    func testSaveRejectsAWorkflowWithoutSteps() async throws {
        var draft = fixture.cronDraft("empty-flow")
        draft.kind = .workflow
        draft.schedule = nil
        draft.steps = []
        try await startCreatorWithDraft(draft)

        let reply = await controller.handle(method: "creator.save", params: [:])

        let issues = try XCTUnwrap(result(reply)?["issues"] as? [[String: Any]])
        let steps = try XCTUnwrap(issues.first { $0["field"] as? String == "steps" })
        XCTAssertEqual(steps["code"] as? String, "missing")
        XCTAssertEqual(steps["message"] as? String, "A workflow needs at least one step.")
        let list = try await fixture.store.list()
        XCTAssertTrue(list.isEmpty)
    }

    /// The user's own edits on the card are what gets saved.
    func testEditedDraftIsSaved() async throws {
        try await startCreatorWithDraft(fixture.cronDraft())

        let markdown = "---\nname: morning\ndescription: Morning job\n---\nDo it early\n"
        let edited = await controller.handle(
            method: "creator.edit",
            params: ["name": "morning", "description": "Morning job", "skillMarkdown": markdown]
        )
        XCTAssertEqual(edited["ok"] as? Bool, true)
        let reply = await controller.handle(method: "creator.save", params: [:])

        let automation = try XCTUnwrap(result(reply)?["automation"] as? [String: Any])
        XCTAssertEqual(automation["name"] as? String, "morning")
        XCTAssertEqual(automation["description"] as? String, "Morning job")
        let id = try XCTUnwrap(automation["id"] as? String)
        let found = try await fixture.store.automation(id: id)
        let saved = try XCTUnwrap(found)
        XCTAssertEqual(try String(contentsOf: saved.directory.appending(path: "SKILL.md"), encoding: .utf8), markdown)
    }

    /// Claude hears about the user's edits once, with the next message.
    func testEditedDraftIsToldToClaudeOnce() async throws {
        try await startCreatorWithDraft(fixture.cronDraft())

        _ = await controller.handle(method: "creator.edit", params: ["description": "Sharper words"])
        _ = await controller.handle(method: "creator.send", params: ["text": "first"])
        _ = await controller.handle(method: "creator.send", params: ["text": "second"])

        let sends = fixture.log.all.filter { $0.contains("creator.send") }
        let first = try XCTUnwrap(sends.first { $0.contains("first") })
        XCTAssertTrue(first.contains("I edited the draft myself"))
        XCTAssertTrue(first.contains("Sharper words"))
        let second = try XCTUnwrap(sends.first { $0.contains("second") })
        XCTAssertFalse(second.contains("I edited the draft myself"))
    }

    func testEditWithoutADraftIsRejected() async throws {
        _ = await controller.handle(method: "creator.start", params: [:])
        let reply = await controller.handle(method: "creator.edit", params: ["name": "x"])
        XCTAssertEqual(reply["ok"] as? Bool, false)
    }

    func testSaveInstallsSchedule() async throws {
        try await startCreatorWithDraft(fixture.cronDraft())

        let reply = await controller.handle(method: "creator.save", params: [:])

        let automation = try XCTUnwrap(result(reply)?["automation"] as? [String: Any])
        let id = try XCTUnwrap(automation["id"] as? String)
        XCTAssertEqual(automation["kind"] as? String, "cronjob")
        XCTAssertTrue(fixture.log.all.contains { $0.hasPrefix("launchctl bootstrap gui/501 ") && $0.hasSuffix(".\(id).plist") })
        let saved = try await fixture.store.automation(id: id)
        XCTAssertEqual(saved?.name, "nightly")
    }

    func testDeleteBootsOutBeforeTrash() async throws {
        let saved = try await fixture.store.save(fixture.cronDraft(), replacing: nil)

        let reply = await controller.handle(method: "automations.delete", params: ["id": saved.id])

        XCTAssertEqual(reply["ok"] as? Bool, true)
        let log = fixture.log.all
        let bootout = try XCTUnwrap(log.firstIndex { $0.hasPrefix("launchctl bootout") && $0.hasSuffix(saved.id) })
        let trash = try XCTUnwrap(log.firstIndex { $0 == "trash \(saved.id)" })
        XCTAssertLessThan(bootout, trash)
        let remaining = try await fixture.store.automation(id: saved.id)
        XCTAssertNil(remaining)
    }

    func testRunNowUsesRunLauncher() async throws {
        let saved = try await fixture.store.save(fixture.cronDraft(), replacing: nil)

        let reply = await controller.handle(method: "automations.runNow", params: ["id": saved.id])

        XCTAssertEqual(reply["ok"] as? Bool, true)
        XCTAssertEqual(fixture.log.all.filter { $0.hasPrefix("run ") }, ["run \(saved.id)"])
    }

    func testExternalSkillDeleteRequiresConfirmFlag() async throws {
        try fixture.externalSkill("theirs")

        let refused = await controller.handle(method: "automations.delete", params: ["id": "external:theirs"])

        XCTAssertEqual(errorCode(refused), "notAllowed")
        let stillThere = try await fixture.store.automation(id: "external:theirs")
        XCTAssertNotNil(stillThere)

        let confirmed = await controller.handle(
            method: "automations.delete",
            params: ["id": "external:theirs", "confirmedExternal": true]
        )
        XCTAssertEqual(confirmed["ok"] as? Bool, true)
        XCTAssertTrue(fixture.log.all.contains("trash theirs"))
        XCTAssertFalse(fixture.log.all.contains { $0.hasPrefix("launchctl") })
    }

    func testExternalSkillIsEditedInTheCreatorInPlace() async throws {
        try fixture.externalSkill("theirs")
        let edited = ShellXAutomationDraft(
            kind: .skill, name: "theirs", description: "Sharper",
            skillMarkdown: "---\nname: theirs\ndescription: Sharper\n---\nBetter\n"
        )

        try await startCreatorWithDraft(edited, editId: "external:theirs")
        let reply = await controller.handle(method: "creator.save", params: [:])

        let saved = try XCTUnwrap(result(reply)?["automation"] as? [String: Any])
        XCTAssertEqual(saved["id"] as? String, "external:theirs")
        XCTAssertEqual(saved["origin"] as? String, "external")
        let skill = fixture.environment.skillsRoot.appending(path: "theirs/SKILL.md")
        XCTAssertEqual(try String(contentsOf: skill, encoding: .utf8), edited.skillMarkdown)
    }

    func testExternalSkillCannotBeEditedIntoACronjob() async throws {
        try fixture.externalSkill("theirs")

        try await startCreatorWithDraft(fixture.cronDraft("theirs"), editId: "external:theirs")
        let reply = await controller.handle(method: "creator.save", params: [:])

        let issues = try XCTUnwrap(result(reply)?["issues"] as? [[String: Any]])
        XCTAssertTrue(issues.contains { $0["field"] as? String == "kind" && $0["code"] as? String == "mustStaySkill" })
        let skill = fixture.environment.skillsRoot.appending(path: "theirs/SKILL.md")
        XCTAssertEqual(try String(contentsOf: skill, encoding: .utf8), "---\nname: theirs\ndescription: Theirs\n---\nBody\n")
        XCTAssertFalse(fixture.log.all.contains { $0.hasPrefix("launchctl") })
    }

    func testCancelDuringStartLeavesNoRunningProcess() async throws {
        let gated = ShellXAutomationsGatedCreatorLauncher(log: fixture.log)
        controller = makeController(launcher: gated)
        let controller = controller!

        let starting = Task { await controller.handle(method: "creator.start", params: [:]) }
        await waitUntil { gated.startCount == 1 }
        _ = await controller.handle(method: "creator.cancel", params: [:])
        await gated.open()
        _ = await starting.value

        await waitUntil { self.fixture.log.all.contains("creator.stop#1") }
        XCTAssertTrue(fixture.log.all.contains("creator.stop#1"))
    }

    func testSecondStartKeepsOnlyTheLatestSession() async throws {
        let gated = ShellXAutomationsGatedCreatorLauncher(log: fixture.log)
        controller = makeController(launcher: gated)
        let controller = controller!

        let first = Task { await controller.handle(method: "creator.start", params: [:]) }
        await waitUntil { gated.startCount == 1 }
        let second = Task { await controller.handle(method: "creator.start", params: [:]) }
        await waitUntil { gated.startCount == 2 }
        await gated.open()
        _ = await first.value
        let secondReply = await second.value
        XCTAssertEqual(secondReply["ok"] as? Bool, true)

        await waitUntil { self.fixture.log.all.contains("creator.stop#1") }
        let sent = await controller.handle(method: "creator.send", params: ["text": "hello"])
        XCTAssertEqual(sent["ok"] as? Bool, true)
        let log = fixture.log.all
        XCTAssertTrue(log.contains("creator.stop#1"))
        XCTAssertFalse(log.contains("creator.stop#2"))
        XCTAssertTrue(log.contains { $0.hasPrefix("creator.send#2 ") && $0.contains("hello") })
        XCTAssertFalse(log.contains { $0.hasPrefix("creator.send#1 ") })
    }

    func testRunNowReportsALaunchFailure() async throws {
        let saved = try await fixture.store.save(fixture.cronDraft(), replacing: nil)
        runFailure = "shellx stopped with status 2."

        let reply = await controller.handle(method: "automations.runNow", params: ["id": saved.id])

        XCTAssertEqual(errorCode(reply), "failed")
        let message = (reply["error"] as? [String: Any])?["message"] as? String
        XCTAssertTrue(message?.contains("status 2") == true)
    }

    func testEditingACronjobIntoASkillRemovesItsLaunchAgent() async throws {
        let cron = try await fixture.store.save(fixture.cronDraft("nightly"), replacing: nil)
        try await fixture.scheduler.install(cron)
        let skill = ShellXAutomationDraft(
            kind: .skill, name: "nightly", description: "Nightly job",
            skillMarkdown: "---\nname: nightly\ndescription: Nightly job\n---\nDo it\n"
        )

        try await startCreatorWithDraft(skill, editId: cron.id)
        let mark = fixture.log.all.count
        let reply = await controller.handle(method: "creator.save", params: [:])

        XCTAssertEqual((result(reply)?["automation"] as? [String: Any])?["kind"] as? String, "skill")
        let after = fixture.log.all.dropFirst(mark)
        XCTAssertTrue(after.contains { $0.hasPrefix("launchctl bootout") && $0.hasSuffix(cron.id) })
        let plist = fixture.environment.launchAgentsDirectory
            .appending(path: fixture.scheduler.label(for: cron.id) + ".plist")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plist.path))
    }

    func testErrorsReachingThePageAreReadable() async {
        let missing = await controller.handle(method: "automations.reveal", params: ["id": "no-such-id"])
        XCTAssertEqual(errorCode(missing), "notFound")
        let message = (missing["error"] as? [String: Any])?["message"] as? String ?? ""
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(message.contains("ShellXAutomationStoreError"))
        let invalid = await controller.handle(method: "automations.reveal", params: ["id": "../x"])
        let invalidMessage = (invalid["error"] as? [String: Any])?["message"] as? String ?? ""
        XCTAssertFalse(invalidMessage.contains("invalidID"))
    }

    func testAppContextCarriesLabelsAndPendingFocus() async throws {
        controller.focus(id: "abc")

        let reply = await controller.handle(method: "app.context", params: [:])

        let context = try XCTUnwrap(result(reply))
        XCTAssertEqual(context["focusId"] as? String, "abc")
        XCTAssertNotNil((context["labels"] as? [String: String])?["title"])
        XCTAssertNotNil(context["reduceMotion"] as? Bool)
        XCTAssertTrue(events.contains { $0["type"] as? String == "focus" && $0["id"] as? String == "abc" })
    }

    func testUnknownMethodIsInvalidArgument() async {
        let reply = await controller.handle(method: "automations.explode", params: [:])
        XCTAssertEqual(errorCode(reply), "invalidArgument")
    }

    // MARK: Flowchart

    func testDraftEventCarriesFlow() async throws {
        try await startCreatorWithDraft(skillDraft(flow: Self.sampleFlow))

        let draftEvent = try XCTUnwrap(events.last { creatorEventType($0) == "draft" })
        let draft = try XCTUnwrap((draftEvent["event"] as? [String: Any])?["draft"] as? [String: Any])
        let flow = try XCTUnwrap(draft["flow"] as? [String: Any])
        let nodes = try XCTUnwrap(flow["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodes.map { $0["id"] as? String }, ["n1", "n2", "n3"])
        XCTAssertEqual(nodes.map { $0["type"] as? String }, ["step", "askUser", "end"])
        XCTAssertEqual(flow["trigger"] as? String, "when asked to tidy up")
        let edges = try XCTUnwrap(flow["edges"] as? [[String: Any]])
        XCTAssertEqual(edges.first { $0["from"] as? String == "n2" }?["label"] as? String, "approve")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(draftEvent))
    }

    func testSaveStoresFlowWithDraftHash() async throws {
        let draft = skillDraft(flow: Self.sampleFlow)
        try await startCreatorWithDraft(draft)

        let reply = await controller.handle(method: "creator.save", params: [:])

        let id = try XCTUnwrap((result(reply)?["automation"] as? [String: Any])?["id"] as? String)
        let stored = try await fixture.store.flowRecord(id: id)
        let record = try XCTUnwrap(stored)
        XCTAssertEqual(record.sourceHash, ShellXFlowFingerprint.of(draft.skillMarkdown))
        XCTAssertEqual(record.flow, Self.sampleFlow)
        // The page opened right after the save shows that chart as current.
        let detailReply = await controller.handle(method: "automations.detail", params: ["id": id])
        let detail = try XCTUnwrap(result(detailReply))
        XCTAssertEqual(detail["flowStatus"] as? String, "current")
        let nodes = try XCTUnwrap((detail["flow"] as? [String: Any])?["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodes.map { $0["id"] as? String }, ["n1", "n2", "n3"])
    }

    /// A flow Claude drew before the user changed `SKILL.md` on the card is kept, but shown as stale.
    func testSaveAfterCardEditStoresStaleFlow() async throws {
        let draft = skillDraft(flow: Self.sampleFlow)
        try await startCreatorWithDraft(draft)
        let edited = "---\nname: tidy\ndescription: Tidies up\n---\nDelete without asking\n"
        _ = await controller.handle(method: "creator.edit", params: ["skillMarkdown": edited])

        let reply = await controller.handle(method: "creator.save", params: [:])

        let id = try XCTUnwrap((result(reply)?["automation"] as? [String: Any])?["id"] as? String)
        let stored = try await fixture.store.flowRecord(id: id)
        XCTAssertEqual(stored?.sourceHash, ShellXFlowFingerprint.of(draft.skillMarkdown))
        let detailReply = await controller.handle(method: "automations.detail", params: ["id": id])
        let detail = try XCTUnwrap(result(detailReply))
        XCTAssertEqual(detail["flowStatus"] as? String, "stale")
        XCTAssertTrue(detail["flow"] is NSNull)
        XCTAssertEqual(detail["skillMarkdown"] as? String, edited)
    }

    func testSaveWithoutFlowSucceeds() async throws {
        try await startCreatorWithDraft(skillDraft(flow: nil))

        let reply = await controller.handle(method: "creator.save", params: [:])

        let id = try XCTUnwrap((result(reply)?["automation"] as? [String: Any])?["id"] as? String)
        let stored = try await fixture.store.flowRecord(id: id)
        XCTAssertNil(stored)
        let detailReply = await controller.handle(method: "automations.detail", params: ["id": id])
        let detail = try XCTUnwrap(result(detailReply))
        XCTAssertEqual(detail["flowStatus"] as? String, "missing")
        XCTAssertTrue(detail["flow"] is NSNull)
        XCTAssertEqual((detail["automation"] as? [String: Any])?["id"] as? String, id)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(detailReply))
    }

    /// A workflow's chart comes from its steps: even a flow Claude sent is not stored.
    func testWorkflowDetailIsDerived() async throws {
        try await startCreatorWithDraft(workflowDraft(flow: Self.sampleFlow))

        let reply = await controller.handle(method: "creator.save", params: [:])

        let id = try XCTUnwrap((result(reply)?["automation"] as? [String: Any])?["id"] as? String)
        let stored = try await fixture.store.flowRecord(id: id)
        XCTAssertNil(stored)
        let detailReply = await controller.handle(method: "automations.detail", params: ["id": id])
        let detail = try XCTUnwrap(result(detailReply))
        XCTAssertEqual(detail["flowStatus"] as? String, "derived")
        XCTAssertTrue(detail["flow"] is NSNull)
    }

    func testEditSeedsCurrentFlow() async throws {
        let saved = try await fixture.store.save(skillDraft(flow: nil), replacing: nil)
        let markdown = try String(contentsOf: saved.directory.appending(path: "SKILL.md"), encoding: .utf8)
        try await fixture.store.saveFlow(
            ShellXFlowRecord(flow: Self.sampleFlow, sourceHash: ShellXFlowFingerprint.of(markdown), drawnAt: Date()),
            id: saved.id
        )

        _ = await controller.handle(method: "creator.start", params: ["editId": saved.id])

        let current = try XCTUnwrap(seededDraft())
        let nodes = try XCTUnwrap((current["flow"] as? [String: Any])?["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodes.count, Self.sampleFlow.nodes.count)

        try await fixture.store.saveFlow(
            ShellXFlowRecord(flow: Self.sampleFlow, sourceHash: ShellXFlowFingerprint.of("older text"), drawnAt: Date()),
            id: saved.id
        )
        events = []
        _ = await controller.handle(method: "creator.start", params: ["editId": saved.id])

        let stale = try XCTUnwrap(seededDraft())
        XCTAssertTrue(stale["flow"] is NSNull)
    }

    func testDrawFlowSavesAndReturnsCurrent() async throws {
        try fixture.externalSkill("theirs")
        let folder = fixture.environment.skillsRoot.appending(path: "theirs", directoryHint: .isDirectory)
        let markdown = try String(contentsOf: folder.appending(path: "SKILL.md"), encoding: .utf8)
        let before = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()

        let reply = await controller.handle(method: "automations.drawFlow", params: ["id": "external:theirs"])

        XCTAssertEqual(drawnMarkdown, [markdown])
        let detail = try XCTUnwrap(result(reply))
        XCTAssertEqual(detail["flowStatus"] as? String, "current")
        XCTAssertEqual(((detail["flow"] as? [String: Any])?["nodes"] as? [[String: Any]])?.count, Self.sampleFlow.nodes.count)
        XCTAssertEqual(detail["skillMarkdown"] as? String, markdown)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(reply))
        let stored = try await fixture.store.flowRecord(id: "external:theirs")
        XCTAssertEqual(stored?.sourceHash, ShellXFlowFingerprint.of(markdown))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(), before)
    }

    func testDrawFlowRejectsWorkflowAndConcurrent() async throws {
        let workflow = try await fixture.store.save(workflowDraft(flow: nil), replacing: nil)
        let refused = await controller.handle(method: "automations.drawFlow", params: ["id": workflow.id])
        XCTAssertEqual(errorCode(refused), "failed")
        XCTAssertFalse(errorMessage(refused).isEmpty)
        XCTAssertTrue(drawnMarkdown.isEmpty)

        try fixture.externalSkill("theirs")
        let gate = ShellXFlowDrawGate()
        fakeDrawer = { _ in
            await gate.wait()
            return Self.sampleFlow
        }
        let controller = controller!
        let first = Task { await controller.handle(method: "automations.drawFlow", params: ["id": "external:theirs"]) }
        await waitUntil { gate.isWaiting }
        let second = await controller.handle(method: "automations.drawFlow", params: ["id": "external:theirs"])
        XCTAssertEqual(errorCode(second), "failed")
        XCTAssertFalse(errorMessage(second).isEmpty)
        gate.open()
        let firstReply = await first.value
        XCTAssertEqual(result(firstReply)?["flowStatus"] as? String, "current")
        XCTAssertEqual(drawnMarkdown.count, 1)
    }

    func testDrawFlowFailureIsReported() async throws {
        try fixture.externalSkill("theirs")
        fakeDrawer = { _ in throw ShellXFlowDrawError.failed("Claude hit its usage limit") }

        let reply = await controller.handle(method: "automations.drawFlow", params: ["id": "external:theirs"])

        XCTAssertEqual(reply["ok"] as? Bool, false)
        XCTAssertEqual(errorCode(reply), "failed")
        XCTAssertTrue(errorMessage(reply).contains("Claude hit its usage limit"))
        let stored = try await fixture.store.flowRecord(id: "external:theirs")
        XCTAssertNil(stored)

        // Without a detail from Claude the message still says why.
        for error in [ShellXFlowDrawError.failed(""), .invalidFlow] {
            fakeDrawer = { _ in throw error }
            let failed = await controller.handle(method: "automations.drawFlow", params: ["id": "external:theirs"])
            let empty = errorMessage(failed)
            let trimmed = empty.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(trimmed.isEmpty)
            XCTAssertFalse(trimmed.hasSuffix(":"), empty)
        }
    }

    /// A SKILL.md that is not UTF-8 text keeps the page open with a reason, not "no longer exists".
    func testDrawFlowWithUnreadableSkillFailsReadably() async throws {
        let saved = try await fixture.store.save(fixture.cronDraft("unreadable"), replacing: nil)
        try Data([0xFF, 0xFE, 0x00, 0xC3, 0x28]).write(to: saved.directory.appending(path: "SKILL.md"))

        let reply = await controller.handle(method: "automations.drawFlow", params: ["id": saved.id])

        XCTAssertEqual(errorCode(reply), "failed")
        XCTAssertTrue(errorMessage(reply).contains("SKILL.md"), errorMessage(reply))
        XCTAssertTrue(drawnMarkdown.isEmpty)
        let stored = try await fixture.store.flowRecord(id: saved.id)
        XCTAssertNil(stored)
    }

    func testCreatorPromptHasFlowRules() throws {
        let prompt = ShellXAutomationsRuntime.creatorSystemPrompt(bundle: .main)

        XCTAssertTrue(prompt.contains("Draw only what SKILL.md says. Do not invent steps, checks or outcomes."))
        XCTAssertTrue(prompt.contains("## Flowchart"))
        XCTAssertFalse(prompt.contains("{{SHELLX_FLOW_RULES}}"))
        // The rules sit inside "## Flowchart" without a top-level heading of their own.
        XCTAssertFalse(prompt.components(separatedBy: "\n").contains { $0.hasPrefix("# ") })
        // The closing rule about files belongs to the whole prompt, not to the flowchart section.
        let never = try XCTUnwrap(prompt.range(of: "Never write files"))
        let heading = prompt[..<never.lowerBound].components(separatedBy: "\n").last { $0.hasPrefix("## ") }
        XCTAssertNotEqual(heading, "## Flowchart")
        XCTAssertEqual(
            ShellXAutomationsRuntime.composeCreatorPrompt(template: "a {{SHELLX_FLOW_RULES}} b", flowRules: "rules"),
            "a rules b"
        )
    }

    // MARK: Helpers

    /// Measure, ask, then end; the ask has an approve and a decline outcome.
    static let sampleFlow = ShellXAutomationFlow(
        trigger: "when asked to tidy up",
        nodes: [
            .init(id: "n1", type: .step, label: "Measure disk usage"),
            .init(id: "n2", type: .askUser, label: "Delete these files?"),
            .init(id: "n3", type: .end, label: "Done", detail: "Nothing else to do"),
        ],
        edges: [
            .init(from: "n1", to: "n2"),
            .init(from: "n2", to: "n3", label: "approve"),
        ]
    )

    private func skillDraft(flow: ShellXAutomationFlow?) -> ShellXAutomationDraft {
        ShellXAutomationDraft(
            kind: .skill, name: "tidy", description: "Tidies up",
            skillMarkdown: "---\nname: tidy\ndescription: Tidies up\n---\nMeasure, then ask before deleting\n",
            flow: flow
        )
    }

    private func workflowDraft(flow: ShellXAutomationFlow?) -> ShellXAutomationDraft {
        var draft = fixture.cronDraft("steps")
        draft.kind = .workflow
        draft.schedule = nil
        draft.steps = [ShellXWorkflowStep(title: "Check", prompt: "Check the build")]
        draft.flow = flow
        return draft
    }

    /// The draft the creator showed first after `creator.start` with an edit id.
    private func seededDraft() -> [String: Any]? {
        let event = events.first { creatorEventType($0) == "draft" }
        return (event?["event"] as? [String: Any])?["draft"] as? [String: Any]
    }

    private func errorMessage(_ reply: [String: Any]) -> String {
        (reply["error"] as? [String: Any])?["message"] as? String ?? ""
    }

    /// Starts the creator and makes the fake assistant propose `draft`.
    private func startCreatorWithDraft(_ draft: ShellXAutomationDraft, editId: String? = nil) async throws {
        let params: [String: Any] = editId.map { ["editId": $0] } ?? [:]
        let started = await controller.handle(method: "creator.start", params: params)
        XCTAssertEqual(started["ok"] as? Bool, true)
        let draftObject = ShellXAutomationsDTOEncoder().draft(draft)
        let draftJSON = String(decoding: try JSONSerialization.data(withJSONObject: draftObject), as: UTF8.self)
        let text = "Here is the draft.\n```shellx-draft\n\(draftJSON)\n```\n"
        let line: [String: Any] = ["type": "assistant", "message": ["content": [["type": "text", "text": text]]]]
        launcher.continuation.yield(String(decoding: try JSONSerialization.data(withJSONObject: line), as: UTF8.self))
        let proposed = { (event: [String: Any]) -> Bool in
            guard self.creatorEventType(event) == "draft",
                  let draftEvent = (event["event"] as? [String: Any])?["draft"] as? [String: Any] else { return false }
            return draftEvent["kind"] as? String == draft.kind.rawValue && draftEvent["name"] as? String == draft.name
                && draftEvent["skillMarkdown"] as? String == draft.skillMarkdown
        }
        await waitUntil { self.events.contains(where: proposed) }
        XCTAssertTrue(events.contains(where: proposed))
    }

    private func creatorEventType(_ event: [String: Any]) -> String? {
        guard event["type"] as? String == "creator.event" else { return nil }
        return (event["event"] as? [String: Any])?["type"] as? String
    }

    private func result(_ reply: [String: Any]) -> [String: Any]? {
        guard reply["ok"] as? Bool == true else { return nil }
        return reply["result"] as? [String: Any]
    }

    private func errorCode(_ reply: [String: Any]) -> String? {
        (reply["error"] as? [String: Any])?["code"] as? String
    }

    /// Waits for a change another task makes; tests only.
    private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// Holds a fake flow draw until the test opens it.
private final class ShellXFlowDrawGate: @unchecked Sendable {
    // Test-only: touched from the drawing task and the test.
    private let lock = NSLock()
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    var isWaiting: Bool { lock.withLock { waiter != nil } }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiter = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let ready = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            isOpen = true
            defer { waiter = nil }
            return waiter
        }
        ready?.resume()
    }
}
