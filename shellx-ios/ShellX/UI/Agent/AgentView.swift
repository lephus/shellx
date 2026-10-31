import ShellXAppCore
import SwiftUI

/// One agent's screen, pushed from the list of other agent sessions or shown as a pane of the
/// workspace screen (`embedded`: no navigation bar of its own): `AgentScreen` fed by the session's
/// `AgentThreadModel` (its chat, sends and stops), the hub and the decision center (the "Needs you"
/// bar of the session's workspace). The model follows the hub while the screen is shown and writes
/// its chat copy when the screen goes or the app leaves the foreground.
///
/// Standalone, its `•••` offers "Close Agent" while the session has not ended and its Mac takes
/// `agent.close`; the close goes through `WorkspaceListActions.closeAgent`, and an alert says why one did
/// not work. Once its Mac answered `not_found` for a session it still lists (`AgentThreadModel.ghost`), the
/// screen tells the scope (the session's cards then swipe to "Remove from This Phone"), and standalone it
/// offers "Remove from This Phone" under the gone line and in `•••`: that hides the session on this phone
/// (`GoneRemovalStore`), nothing goes to the Mac, and the screen goes back.
///
/// The composer offers attachments when the session's Mac takes them, or while some wait in it. A
/// message with attachments stays in the composer, locked, until the Mac answers; what went is
/// cleared unless the result keeps it (`ComposerDraft`, `AgentSendResult.keepsDraft`).
struct AgentView: View {
    let scope: SignedInScope
    /// A pane of the workspace screen, not a screen of its own.
    let embedded: Bool
    /// Pushes a screen (the "Needs you" bar opens this workspace's pending cards).
    let open: (HomeRoute) -> Void

    @State private var model: AgentThreadModel
    @State private var composer = ComposerDraft()
    @State private var notice: AgentScreen.Notice?
    /// Why the last Close Agent did not work.
    @State private var alert: WorkspaceAlert?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    /// How long a notice over the composer stays.
    static let noticeDuration: Duration = .seconds(4)

    init(scope: SignedInScope, ref: SessionRef, embedded: Bool = false, open: @escaping (HomeRoute) -> Void) {
        self.scope = scope
        self.embedded = embedded
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
            embedded: embedded,
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
            // Embedded, the workspace screen's `•••` closes the agent's tab instead ("Close Tab…").
            closeAgentName: embedded
                ? nil
                : session.flatMap { WorkspaceListActions.canClose($0, hub: hub) ? SessionName.base(of: $0.session) : nil },
            canRemoveFromPhone: Self.removable(model, embedded: embedded) != nil,
            actions: AgentScreen.Actions(
                send: { send($0, attachments: $1, viaVoice: false) },
                sendVoice: { send($0, attachments: [], viaVoice: true) },
                stop: { stop(hard: false) },
                forceStop: { stop(hard: true) },
                loadOlder: { Task { await model.loadOlder() } },
                retry: { Task { await model.retry() } },
                seeAllPending: { openPending() },
                closeAgent: { WorkspaceListActions.closeAgent(model.ref, hub: hub, alert: { alert = $0 }) },
                removeFromPhone: { removeFromPhone() })
        )
        .workspaceAlert($alert)
        .task { await model.run() }
        // Also when the Mac reports the ghost otherwise: the swipe follows what the Mac reports now.
        .onChange(of: model.ghost, initial: true) { Self.noteGone(model, in: scope) }
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

    /// The session "Remove from This Phone" takes off, while the screen offers it: standalone (a workspace's
    /// pane offers none) and its Mac answered `not_found` for a session it still lists
    /// (`AgentThreadModel.ghost`). Nil for a live session, always.
    static func removable(_ model: AgentThreadModel, embedded: Bool) -> MachineSession? {
        embedded ? nil : model.ghost
    }

    /// Tells the scope the screen's session is gone from its Mac, once its Mac answered `not_found` for a
    /// session it still lists: its cards on the home and the outside-workspace list swipe to "Remove from
    /// This Phone" while the Mac reports it so. A pane of the workspace screen tells it too.
    static func noteGone(_ model: AgentThreadModel, in scope: SignedInScope) {
        if let ghost = model.ghost { scope.goneRemovals.noteGone(ghost) }
    }

    /// Hides the gone session on this phone and goes back: the list the screen came from no longer has it.
    private func removeFromPhone() {
        guard let ghost = Self.removable(model, embedded: embedded) else { return }
        scope.goneRemovals.remove(ghost)
        dismiss()
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
