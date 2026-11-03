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

    override func setUp() async throws {
        fixture = ShellXAutomationsFixture()
        let log = fixture.log
        let launcher = ShellXAutomationsFakeCreatorLauncher(log: log)
        self.launcher = launcher
        let store = fixture.store
        controller = ShellXAutomationsController(
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
            runLauncher: { id in log.append("run " + id) },
            terminalOpener: { automation in log.append("terminal " + automation.id) },
            fileOpener: { url in log.append("open " + url.lastPathComponent) },
            makeValidator: { _ in
                let names = Set(((try? await store.list()) ?? []).map(\.name))
                return ShellXAutomationValidator(existingNames: names, directoryExists: { _ in true }, claudeAvailable: true)
            }
        )
        controller.emit = { [weak self] event in self?.events.append(event) }
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
    private func startCreatorWithDraft(_ draft: ShellXAutomationDraft) async throws {
        let started = await controller.handle(method: "creator.start", params: [:])
        XCTAssertEqual(started["ok"] as? Bool, true)
        let draftObject = ShellXAutomationsDTOEncoder().draft(draft)
        let draftJSON = String(decoding: try JSONSerialization.data(withJSONObject: draftObject), as: UTF8.self)
        let text = "Here is the draft.\n```shellx-draft\n\(draftJSON)\n```\n"
        let line: [String: Any] = ["type": "assistant", "message": ["content": [["type": "text", "text": text]]]]
        launcher.continuation.yield(String(decoding: try JSONSerialization.data(withJSONObject: line), as: UTF8.self))
        await waitUntil { self.events.contains { self.creatorEventType($0) == "draft" } }
        XCTAssertTrue(events.contains { creatorEventType($0) == "draft" })
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
