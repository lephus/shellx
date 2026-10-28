import ShellXAppCore
import SwiftUI

/// One agent's screen, pushed from the list of other agent sessions: `AgentScreen` fed by the
/// session's `AgentThreadModel` (its chat, sends and stops), the hub and the decision center (the
/// "Needs you" bar of the session's workspace). The model follows the hub while the screen is shown
/// and writes its chat copy when the screen goes or the app leaves the foreground.
///
/// The composer offers attachments when the session's Mac takes them, or while some wait in it. A message with attachments stays in the composer, locked, until
/// the Mac answers; what went is cleared unless the result keeps it (`ComposerDraft`,
/// `AgentSendResult.keepsDraft`).
struct AgentView: View {
    let scope: SignedInScope
    /// Pushes a screen (the "Needs you" bar opens this workspace's pending cards).
    let open: (HomeRoute) -> Void

    @State private var model: AgentThreadModel
    @State private var composer = ComposerDraft()
    @State private var notice: AgentScreen.Notice?
    @Environment(\.scenePhase) private var scenePhase

    /// How long a notice over the composer stays.
    static let noticeDuration: Duration = .seconds(4)

    init(scope: SignedInScope, ref: SessionRef, open: @escaping (HomeRoute) -> Void) {
        self.scope = scope
        self.open = open
        _model = State(initialValue: scope.agentThread(ref))
    }

    var body: some View {
        let hub = scope.hub
        let center = scope.decisions
        let model = self.model
        let session = model.session
        AgentScreen(
            ref: session?.ref ?? model.ref,
            place: "\(AgentLabel(agent: model.ref.agent).text) · \(session?.machineName ?? model.machineName)",
            row: { model.session.map { AgentStatusRow(session: $0, now: Date()) } },
            gone: model.sessionGone,
            offline: model.offline,
            pending: center.visibleItems(model.pendingHere),
            showsMachineName: hub.machines.count > 1,
            entries: model.thread.entries,
            emptyState: model.emptyState,
            machineName: model.machineName,
            older: model.older,
            loadingOlder: model.loadingOlder,
            canStop: model.canStop,
            notice: notice,
            draft: $composer.text,
            attachments: hub.acceptsAttachments(model.ref.machineID) || !composer.attachments.isEmpty
                ? $composer.attachments : nil,
            sending: composer.isSending ? (model.uploadProgress ?? 0) : nil,
            actions: AgentScreen.Actions(
                send: { send($0, attachments: $1, viaVoice: false) },
                sendVoice: { send($0, attachments: [], viaVoice: true) },
                stop: { stop(hard: false) },
                forceStop: { stop(hard: true) },
                loadOlder: { Task { await model.loadOlder() } },
                retry: { Task { await model.retry() } },
                seeAllPending: { openPending() })
        )
        .task { await model.run() }
        .task(id: notice?.id) {
            guard notice != nil else { return }
            do { try await Task.sleep(for: Self.noticeDuration) } catch { return }
            notice = nil
        }
        .onChange(of: scenePhase) { _, phase in
            // Still the screen shown: write now, keep following.
            if phase != .active { Task { await model.save() } }
        }
        .onDisappear { Task { await model.close() } }
    }

    private func send(_ text: String, attachments picked: [OutgoingAttachment], viaVoice: Bool) {
        let model = self.model
        if !picked.isEmpty { composer.sendStarted() }
        Task {
            let result = await model.send(text, attachments: picked, viaVoice: viaVoice)
            if picked.isEmpty {
                // The Mac surely did not take it: give the text back, unless the user typed meanwhile.
                if result.keepsDraft, composer.text.isEmpty { composer.text = text }
            } else {
                // The composer held the message while it went up: clear what went once the Mac took it.
                composer.sendEnded(keepsDraft: result.keepsDraft)
            }
            show(Self.text(for: result, ref: model.ref, machineName: model.machineName))
        }
    }

    /// The page of this workspace's pending cards: the same ones the bar counts (`pendingHere`).
    private func openPending() {
        guard let workspaceId = model.session?.session.workspaceId else { return }
        open(.pendingIn(machineID: model.ref.machineID, workspaceId: workspaceId))
    }

    private func stop(hard: Bool) {
        let model = self.model
        Task {
            let outcome = await model.stop(hard: hard)
            show(StopButton.text(for: outcome, offline: model.offline, machineName: model.machineName))
        }
    }

    private func show(_ text: String?) {
        guard let text else { return }
        notice = AgentScreen.Notice(text: text)
        AccessibilityNotification.Announcement(text).post()
    }

    /// What the screen says after a send; nil for empty text (nothing happened).
    static func text(for result: AgentSendResult, ref: SessionRef, machineName: String) -> String? {
        let agent = AgentLabel(agent: ref.agent).text
        switch result {
        case .refused(.empty), .refused(.ok), .refused(.tooManyAttachments), .refused(.attachmentTooLarge):
            // Nothing happened, or the composer already says why under its field.
            return nil
        case let .refused(.tooLong(bytes)):
            let used = ComposerValidation.byteCount(bytes)
            let limit = ComposerValidation.byteCount(ComposerValidation.maxBytes)
            return String(localized: "composer.tooLong \(used) \(limit)")
        case .sent(.submitted):
            return String(localized: "agent.sent")
        case .sent(.busy):
            return String(localized: "agent.busy")
        case .sent(.notFound):
            return String(localized: "agent.gone")
        case .sent(.failed), .sent(.other), .notSent:
            return String(localized: "home.note.failed \(agent) \(ref.workspaceTitle)")
        case .attachmentsUnsupported:
            return String(localized: "home.note.attachmentsUnsupported \(agent) \(ref.workspaceTitle)")
        case .offline:
            return String(localized: "home.note.offline \(machineName)")
        case .noAnswer:
            return String(localized: "home.note.noAnswer \(agent) \(ref.workspaceTitle)")
        }
    }
}
