import AppKit
import Foundation
import Observation
import OSLog
import ShellXAutomations

/// Answers the Automations page's bridge requests and forwards creator events to it.
///
/// One controller backs one Automations panel. It reads and writes through the store,
/// installs and removes launchd jobs through the scheduler, and owns at most one creator
/// session (a headless Claude Code chat) at a time. It keeps the flowchart Claude sends with a
/// draft, and redraws a saved automation's flowchart on request. Replies are
/// `{ok: true, result}` or `{ok: false, error: {code, message}}`.
@MainActor
final class ShellXAutomationsController {
    private typealias Contract = ShellXAutomationsBridgeContract
    private typealias Failure = ShellXAutomationsBridgeFailure

    let library: ShellXAutomationsLibrary
    /// Delivers `automations.changed`, `creator.event`, `focus` and `appearance` to the page.
    var emit: (@MainActor ([String: Any]) -> Void)?
    /// The appearance `app.context` reports; the web view points it at itself.
    var effectiveAppearance: @MainActor () -> NSAppearance = { NSApplication.shared.effectiveAppearance }
    /// Whether the page should keep still.
    var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Shows a file or folder in Finder.
    var revealInFinder: @MainActor (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }

    private let store: ShellXAutomationStore
    private let scheduler: ShellXLaunchAgentScheduler
    private let creatorFactory: (ShellXCreatorSeed?) -> ShellXCreatorSession
    private let runLauncher: @Sendable (String) async -> String?
    private let terminalOpener: (ShellXAutomation) -> Void
    private let fileOpener: (URL) -> Void
    private let makeValidator: (_ replacingName: String?) async -> ShellXAutomationValidator
    private let flowDrawer: (_ skillMarkdown: String) async throws -> ShellXAutomationFlow
    private let encoder = ShellXAutomationsDTOEncoder()
    private let logger = Logger(subsystem: "pro.shellx.desktop", category: "automations")

    private var pendingFocusId: String?
    /// The appearance the page was last told about, in `app.context` or an `appearance` event.
    private var reportedAppearance: String?
    private var session: ShellXCreatorSession?
    private var sessionEvents: Task<Void, Never>?
    /// The automation the creator edits, or nil for a new one.
    private var editing: ShellXAutomation?
    /// The last valid draft the assistant proposed.
    private var latestDraft: ShellXAutomationDraft?
    /// Whether the user changed `latestDraft` on the card since Claude last heard about it.
    private var userEditedDraft = false
    /// Fingerprint of the `SKILL.md` the flow of `latestDraft` was drawn from, or nil when it has
    /// none. Card edits leave it as it is, so a flow saved after them is stale.
    private var latestFlowHash: String?
    /// Ids whose flowchart is being drawn.
    private var inFlightDraws: Set<String> = []
    /// Bumped by every `creator.start` and every end of a session, so a start that is still
    /// awaiting finds out it was replaced or cancelled.
    private var creatorGeneration: UInt64 = 0

    init(
        library: ShellXAutomationsLibrary,
        store: ShellXAutomationStore,
        scheduler: ShellXLaunchAgentScheduler,
        creatorFactory: @escaping (ShellXCreatorSeed?) -> ShellXCreatorSession,
        runLauncher: @escaping @Sendable (String) async -> String?,
        terminalOpener: @escaping (ShellXAutomation) -> Void,
        fileOpener: @escaping (URL) -> Void,
        makeValidator: @escaping (_ replacingName: String?) async -> ShellXAutomationValidator,
        flowDrawer: @escaping (_ skillMarkdown: String) async throws -> ShellXAutomationFlow
    ) {
        self.library = library
        self.store = store
        self.scheduler = scheduler
        self.creatorFactory = creatorFactory
        self.runLauncher = runLauncher
        self.terminalOpener = terminalOpener
        self.fileOpener = fileOpener
        self.makeValidator = makeValidator
        self.flowDrawer = flowDrawer
        observeLibrary()
    }

    /// Shows `id`'s card, or the list for nil. The page reads it from `app.context` when it
    /// is still loading, and from the `focus` event when it is already up.
    func focus(id: String?) {
        pendingFocusId = id
        if let id { send(["type": Contract.Event.focus.rawValue, "id": id]) }
    }

    /// Tells the page when the effective appearance differs from what it last heard.
    /// The web view calls it whenever its effective appearance changes.
    func appearanceDidChange() {
        let current = currentAppearance()
        guard current != reportedAppearance else { return }
        reportedAppearance = current
        send(["type": Contract.Event.appearance.rawValue, "appearance": current])
    }

    /// Stops the creator session, if any. Called when the panel closes.
    func shutDown() {
        endSession()
    }

    /// Answers one bridge request. The returned dictionary is the reply for the page.
    func handle(method name: String, params: [String: Any]) async -> [String: Any] {
        do {
            guard let method = Contract.Method(rawValue: name) else {
                throw Failure.unknownMethod(name)
            }
            return ["ok": true, "result": try await perform(method, params: params)]
        } catch {
            let failure = Failure(error)
            return errorReply(code: failure.code, message: failure.message)
        }
    }

    /// A failed reply.
    func errorReply(code: ShellXAutomationsBridgeContract.ErrorCode, message: String) -> [String: Any] {
        ["ok": false, "error": ["code": code.rawValue, "message": message]]
    }

    // MARK: Requests

    private func perform(_ method: Contract.Method, params: [String: Any]) async throws -> [String: Any] {
        switch method {
        case .appContext:
            return appContext()
        case .list:
            let all = try await store.list()
            return ["automations": all.map(encoder.automation)]
        case .runNow:
            let automation = try await existing(params)
            guard automation.kind != .skill else {
                throw Failure.skillCannotRun
            }
            if let problem = await runLauncher(automation.id) {
                throw Failure.runFailed(problem)
            }
            return [:]
        case .setEnabled:
            let id = try string(params, "id")
            guard let enabled = params["enabled"] as? Bool else { throw Failure.invalidParameter("enabled") }
            let updated = try await store.setEnabled(id: id, enabled)
            if updated.enabled, updated.schedule != nil {
                try await scheduler.install(updated)
            } else {
                try await scheduler.remove(id: updated.id)
            }
            await library.reload()
            return ["automation": encoder.automation(updated)]
        case .delete:
            let id = try string(params, "id")
            if id.hasPrefix(Self.externalPrefix), params["confirmedExternal"] as? Bool != true {
                throw Failure.externalDeleteNeedsConfirmation
            }
            let automation = try await existing(params)
            if automation.kind != .skill {
                try await scheduler.remove(id: automation.id)
            }
            try await store.delete(id: automation.id)
            await library.reload()
            return [:]
        case .reveal:
            let automation = try await existing(params)
            revealInFinder(automation.directory)
            return [:]
        case .editFile:
            let automation = try await existing(params)
            let file = automation.kind == .workflow ? "automation.json" : "SKILL.md"
            fileOpener(automation.directory.appending(path: file))
            return [:]
        case .openLog:
            let automation = try await existing(params)
            guard let log = await Self.newestLog(in: automation.directory) else {
                throw Failure.noLog
            }
            fileOpener(log)
            return [:]
        case .continueInTerminal:
            let automation = try await existing(params)
            guard automation.lastRun?.sessionId?.isEmpty == false else {
                throw Failure.noSession
            }
            terminalOpener(automation)
            return [:]
        case .markRead:
            let id = try string(params, "id")
            try await store.markRead(id: id)
            await library.reload()
            return [:]
        case .detail:
            return try await detail(of: try await existing(params))
        case .drawFlow:
            return try await drawFlow(for: try await existing(params))
        case .creatorStart:
            try await startCreator(editId: try optionalString(params, "editId"))
            return [:]
        case .creatorSend:
            let text = try string(params, "text")
            guard let session else { throw Failure.assistantNotRunning }
            try await session.send(outgoing(text))
            return [:]
        case .creatorCancel:
            endSession()
            return [:]
        case .creatorSave:
            return try await saveDraft()
        case .creatorEdit:
            try editDraft(params)
            return [:]
        }
    }

    private func appContext() -> [String: Any] {
        let appearance = currentAppearance()
        reportedAppearance = appearance
        var context: [String: Any] = [
            "labels": ShellXAutomationsLabels().localized(),
            "reduceMotion": reduceMotion(),
            "appearance": appearance,
        ]
        if let pendingFocusId { context["focusId"] = pendingFocusId }
        pendingFocusId = nil
        return context
    }

    private func currentAppearance() -> String {
        effectiveAppearance().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
    }

    // MARK: Creator

    private func startCreator(editId: String?) async throws {
        endSession()
        let generation = creatorGeneration
        var seed: ShellXCreatorSeed?
        var editedAutomation: ShellXAutomation?
        var seededDraft: ShellXAutomationDraft?
        var seededFlowHash: String?
        if let editId {
            guard let automation = try await store.automation(id: editId) else {
                throw Failure.notFound
            }
            let markdown = await Self.readText(automation.directory.appending(path: "SKILL.md")) ?? ""
            seed = ShellXCreatorSeed(automation: automation, skillMarkdown: markdown)
            editedAutomation = automation
            // Only a flow drawn from this exact SKILL.md is shown; a stale one is left out.
            let record = try? await store.flowRecord(id: automation.id)
            let flow = ShellXAutomationStore.flowStatus(kind: automation.kind, record: record, skillMarkdown: markdown).flow
            seededDraft = encoder.draft(from: automation, skillMarkdown: markdown, flow: flow)
            seededFlowHash = flow.map { _ in ShellXFlowFingerprint.of(markdown) }
        }
        // A later `creator.start` or `creator.cancel` ran while this one read the files.
        guard generation == creatorGeneration else { return }
        editing = editedAutomation
        latestDraft = seededDraft
        latestFlowHash = seededFlowHash
        let session = creatorFactory(seed)
        self.session = session
        let events = session.events
        sessionEvents = Task { [weak self] in
            for await event in events {
                guard let self, self.session === session else { return }
                self.creatorDidEmit(event)
            }
        }
        if let seededDraft {
            send(creatorEvent(["type": "draft", "draft": encoder.draft(seededDraft)]))
        }
        do {
            try await session.start(seed: seed)
        } catch {
            guard self.session === session else { return }
            endSession()
            throw Failure.assistantFailedToStart(error.localizedDescription)
        }
        if self.session !== session {
            // Replaced while Claude Code started; the session stops its own process once cancelled.
            await session.cancel()
        }
    }

    private func creatorDidEmit(_ event: ShellXCreatorEvent) {
        if case .draft(let draft) = event {
            latestDraft = draft
            userEditedDraft = false
            latestFlowHash = draft.flow.map { _ in ShellXFlowFingerprint.of(draft.skillMarkdown) }
        }
        send(creatorEvent(encoder.creatorEvent(event)))
    }

    private func saveDraft() async throws -> [String: Any] {
        guard let draft = latestDraft else {
            throw Failure.noDraft
        }
        let flowHash = latestFlowHash
        let editingName = editing?.name
        let validator = await makeValidator(editingName)
        var issues = validator.validate(draft, replacingName: editingName)
        if editing?.origin == .external, draft.kind != .skill {
            // Skills ShellX did not create are saved in place, so they stay skills.
            issues.append(.init(
                field: .kind, code: "mustStaySkill",
                message: "ShellX did not create this skill, so it must stay a skill. Set kind to skill."
            ))
        }
        guard issues.isEmpty else {
            let payload = encoder.issues(issues, draft: draft)
            send(creatorEvent(["type": "validation", "issues": payload]))
            if let session {
                let fix = outgoing("Fix: " + issues.map { "\($0.field.rawValue): \($0.message)" }.joined(separator: " "))
                Task { try? await session.send(fix) }
            }
            return ["issues": payload]
        }

        let previous = editing
        let saved = try await store.save(draft, replacing: previous?.id)
        editing = saved
        do {
            if saved.kind != .skill {
                if saved.enabled, saved.schedule != nil {
                    try await scheduler.install(saved)
                } else {
                    try await scheduler.remove(id: saved.id)
                }
            } else if let previous, previous.kind != .skill {
                // A cronjob or workflow edited into a skill leaves no launchd job behind.
                try await scheduler.remove(id: previous.id)
            }
        } catch {
            throw Failure.scheduleFailed
        }
        await storeFlow(of: draft, hash: flowHash, saved: saved, previous: previous)
        endSession()
        await library.reload()
        return ["automation": encoder.automation(saved)]
    }

    /// Keeps the flow Claude drew for a saved skill or cronjob, under the fingerprint of the
    /// `SKILL.md` it was drawn from. Workflows keep none. A failure here never fails the save.
    private func storeFlow(
        of draft: ShellXAutomationDraft, hash: String?, saved: ShellXAutomation, previous: ShellXAutomation?
    ) async {
        do {
            if saved.kind == .workflow {
                try await store.removeFlow(id: saved.id)
            } else if let flow = draft.flow, let hash {
                try await store.saveFlow(ShellXFlowRecord(flow: flow, sourceHash: hash, drawnAt: Date()), id: saved.id)
            }
            if let previous, previous.id != saved.id {
                // A renamed skill ShellX did not create gets a new id; its old flow would be orphaned.
                try await store.removeFlow(id: previous.id)
            }
        } catch {
            logger.error("Could not store the flow of \(saved.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Applies the user's own changes to the draft's name, description and `SKILL.md`.
    /// Claude hears about them with the next message it gets.
    private func editDraft(_ params: [String: Any]) throws {
        guard var draft = latestDraft else { throw Failure.noDraft }
        for (key, path) in [
            ("name", \ShellXAutomationDraft.name),
            ("description", \ShellXAutomationDraft.description),
            ("skillMarkdown", \ShellXAutomationDraft.skillMarkdown),
        ] as [(String, WritableKeyPath<ShellXAutomationDraft, String>)] {
            guard let raw = params[key] else { continue }
            guard let value = raw as? String else { throw Failure.invalidParameter(key) }
            draft[keyPath: path] = value
        }
        guard draft != latestDraft else { return }
        latestDraft = draft
        userEditedDraft = true
    }

    /// `text` for Claude, led by the user's own edits to the draft when there are new ones.
    private func outgoing(_ text: String) -> String {
        guard userEditedDraft, let draft = latestDraft else { return text }
        userEditedDraft = false
        let fence = String(repeating: "`", count: max(3, Self.longestBacktickRun(in: draft.skillMarkdown) + 1))
        return """
        I edited the draft myself. Keep these values unless I ask you to change them.
        name: \(draft.name)
        description: \(draft.description)
        SKILL.md:
        \(fence)
        \(draft.skillMarkdown)
        \(fence)

        \(text)
        """
    }

    private static func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }

    private func endSession() {
        creatorGeneration &+= 1
        sessionEvents?.cancel()
        sessionEvents = nil
        if let session {
            Task { await session.cancel() }
        }
        session = nil
        editing = nil
        latestDraft = nil
        userEditedDraft = false
        latestFlowHash = nil
    }

    // MARK: Flowchart

    /// `{automation, skillMarkdown, flow, flowStatus}` for the detail page.
    private func detail(of automation: ShellXAutomation) async throws -> [String: Any] {
        let markdown = await Self.readText(automation.directory.appending(path: "SKILL.md")) ?? ""
        // Workflows are `derived` whatever is stored.
        let record = try await store.flowRecord(id: automation.id)
        let (status, flow) = ShellXAutomationStore.flowStatus(kind: automation.kind, record: record, skillMarkdown: markdown)
        return [
            "automation": encoder.automation(automation),
            "skillMarkdown": markdown,
            "flow": flow.map { encoder.flow($0) as Any } ?? NSNull(),
            "flowStatus": status.rawValue,
        ]
    }

    /// Asks Claude to draw `automation`'s `SKILL.md` again, stores the flow and returns the detail.
    private func drawFlow(for automation: ShellXAutomation) async throws -> [String: Any] {
        guard automation.kind != .workflow else { throw Failure.flowNotForWorkflow }
        guard inFlightDraws.insert(automation.id).inserted else { throw Failure.drawInProgress }
        defer { inFlightDraws.remove(automation.id) }
        // The automation exists (`existing` found it); its SKILL.md is not UTF-8 text or not there.
        guard let markdown = await Self.readText(automation.directory.appending(path: "SKILL.md")) else {
            throw Failure.skillUnreadable
        }
        let flow: ShellXAutomationFlow
        do {
            flow = try await flowDrawer(markdown)
        } catch {
            throw Failure.drawFailed(for: error)
        }
        let record = ShellXFlowRecord(flow: flow, sourceHash: ShellXFlowFingerprint.of(markdown), drawnAt: Date())
        try await store.saveFlow(record, id: automation.id)
        return try await detail(of: automation)
    }

    // MARK: Events

    private func observeLibrary() {
        withObservationTracking {
            _ = library.automations
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.send(["type": Contract.Event.changed.rawValue])
                self.observeLibrary()
            }
        }
    }

    private func creatorEvent(_ event: [String: Any]) -> [String: Any] {
        ["type": Contract.Event.creatorEvent.rawValue, "event": event]
    }

    private func send(_ event: [String: Any]) {
        emit?(event)
    }

    // MARK: Helpers

    private static let externalPrefix = "external:"

    private func existing(_ params: [String: Any]) async throws -> ShellXAutomation {
        let id = try string(params, "id")
        guard let automation = try await store.automation(id: id) else {
            throw Failure.notFound
        }
        return automation
    }

    private func string(_ params: [String: Any], _ key: String) throws -> String {
        guard let value = params[key] as? String, !value.isEmpty else { throw Failure.invalidParameter(key) }
        return value
    }

    private func optionalString(_ params: [String: Any], _ key: String) throws -> String? {
        guard let raw = params[key], !(raw is NSNull) else { return nil }
        guard let value = raw as? String else { throw Failure.invalidParameter(key) }
        return value.isEmpty ? nil : value
    }

    /// The newest run's transcript, else the launchd log. Reads the disk off the main actor.
    private static func newestLog(in directory: URL) async -> URL? {
        await Task.detached(priority: .userInitiated) { () -> URL? in
            let fileManager = FileManager.default
            let runs = directory.appending(path: "runs", directoryHint: .isDirectory)
            let names = ((try? fileManager.contentsOfDirectory(atPath: runs.path)) ?? [])
                .filter { !$0.hasPrefix(".") }
                .sorted(by: >)
            for name in names {
                let transcript = runs.appending(path: name).appending(path: "output.jsonl")
                if fileManager.fileExists(atPath: transcript.path) { return transcript }
            }
            let launchdLog = directory.appending(path: "launchd.log")
            return fileManager.fileExists(atPath: launchdLog.path) ? launchdLog : nil
        }.value
    }

    private static func readText(_ url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) { try? String(contentsOf: url, encoding: .utf8) }.value
    }
}
