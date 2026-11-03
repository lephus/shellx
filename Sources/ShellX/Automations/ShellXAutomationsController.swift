import AppKit
import Foundation
import Observation
import ShellXAutomations

/// Answers the Automations page's bridge requests and forwards creator events to it.
///
/// One controller backs one Automations panel. It reads and writes through the store,
/// installs and removes launchd jobs through the scheduler, and owns at most one creator
/// session (a headless Claude Code chat) at a time. Replies are
/// `{ok: true, result}` or `{ok: false, error: {code, message}}`.
@MainActor
final class ShellXAutomationsController {
    private typealias Contract = ShellXAutomationsBridgeContract
    private typealias Failure = ShellXAutomationsBridgeFailure

    let library: ShellXAutomationsLibrary
    /// Delivers `automations.changed`, `creator.event` and `focus` to the page.
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
    private let encoder = ShellXAutomationsDTOEncoder()

    private var pendingFocusId: String?
    private var session: ShellXCreatorSession?
    private var sessionEvents: Task<Void, Never>?
    /// The automation the creator edits, or nil for a new one.
    private var editing: ShellXAutomation?
    /// The last valid draft the assistant proposed.
    private var latestDraft: ShellXAutomationDraft?
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
        makeValidator: @escaping (_ replacingName: String?) async -> ShellXAutomationValidator
    ) {
        self.library = library
        self.store = store
        self.scheduler = scheduler
        self.creatorFactory = creatorFactory
        self.runLauncher = runLauncher
        self.terminalOpener = terminalOpener
        self.fileOpener = fileOpener
        self.makeValidator = makeValidator
        observeLibrary()
    }

    /// Shows `id`'s card, or the list for nil. The page reads it from `app.context` when it
    /// is still loading, and from the `focus` event when it is already up.
    func focus(id: String?) {
        pendingFocusId = id
        if let id { send(["type": Contract.Event.focus.rawValue, "id": id]) }
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
        case .creatorStart:
            try await startCreator(editId: try optionalString(params, "editId"))
            return [:]
        case .creatorSend:
            let text = try string(params, "text")
            guard let session else { throw Failure.assistantNotRunning }
            try await session.send(text)
            return [:]
        case .creatorCancel:
            endSession()
            return [:]
        case .creatorSave:
            return try await saveDraft()
        }
    }

    private func appContext() -> [String: Any] {
        let isDark = effectiveAppearance().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        var context: [String: Any] = [
            "labels": ShellXAutomationsLabels().localized(),
            "reduceMotion": reduceMotion(),
            "appearance": isDark ? "dark" : "light",
        ]
        if let pendingFocusId { context["focusId"] = pendingFocusId }
        pendingFocusId = nil
        return context
    }

    // MARK: Creator

    private func startCreator(editId: String?) async throws {
        endSession()
        let generation = creatorGeneration
        var seed: ShellXCreatorSeed?
        var editedAutomation: ShellXAutomation?
        var seededDraft: ShellXAutomationDraft?
        if let editId {
            guard let automation = try await store.automation(id: editId) else {
                throw Failure.notFound
            }
            let markdown = await Self.readText(automation.directory.appending(path: "SKILL.md")) ?? ""
            seed = ShellXCreatorSeed(automation: automation, skillMarkdown: markdown)
            editedAutomation = automation
            seededDraft = encoder.draft(from: automation, skillMarkdown: markdown)
        }
        // A later `creator.start` or `creator.cancel` ran while this one read the files.
        guard generation == creatorGeneration else { return }
        editing = editedAutomation
        latestDraft = seededDraft
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
        if case .draft(let draft) = event { latestDraft = draft }
        send(creatorEvent(encoder.creatorEvent(event)))
    }

    private func saveDraft() async throws -> [String: Any] {
        guard let draft = latestDraft else {
            throw Failure.noDraft
        }
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
                let fix = "Fix: " + issues.map { "\($0.field.rawValue): \($0.message)" }.joined(separator: " ")
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
        endSession()
        await library.reload()
        return ["automation": encoder.automation(saved)]
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
