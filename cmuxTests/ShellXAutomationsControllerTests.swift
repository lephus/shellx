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

    func testExternalSkillCannotBeEditedInTheCreator() async throws {
        try fixture.externalSkill("theirs")

        let reply = await controller.handle(method: "creator.start", params: ["editId": "external:theirs"])

        XCTAssertEqual(errorCode(reply), "notAllowed")
        let sends = await controller.handle(method: "creator.send", params: ["text": "hi"])
        XCTAssertEqual(errorCode(sends), "unavailable")
        let folder = fixture.environment.skillsRoot.appending(path: "theirs/SKILL.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
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

    // MARK: Helpers

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
