import Foundation

/// Wire names shared with the page side of the Automations bridge
/// (`webviews/src/automations/bridge.ts` and `types.ts`).
///
/// The page posts `{method, params}` to the `shellxAutomations` handler and gets back
/// `{ok: true, result}` or `{ok: false, error: {code, message}}`. The host pushes
/// events by calling `window.shellxAutomations.receive(event)`.
enum ShellXAutomationsBridgeContract {
    static let handlerName = "shellxAutomations"

    /// `AutomationsMethod` in `types.ts`.
    enum Method: String {
        case appContext = "app.context"
        case list = "automations.list"
        case runNow = "automations.runNow"
        case setEnabled = "automations.setEnabled"
        case delete = "automations.delete"
        case reveal = "automations.reveal"
        case editFile = "automations.editFile"
        case openLog = "automations.openLog"
        case continueInTerminal = "automations.continueInTerminal"
        case markRead = "automations.markRead"
        case creatorStart = "creator.start"
        case creatorSend = "creator.send"
        case creatorCancel = "creator.cancel"
        case creatorSave = "creator.save"
    }

    /// `AutomationsEvent.type` in `types.ts`.
    enum Event: String {
        case changed = "automations.changed"
        case creatorEvent = "creator.event"
        case focus
    }

    /// `error.code` of a failed reply. `notAllowed` marks a request from an untrusted
    /// frame, or a delete of a skill ShellX did not create without `confirmedExternal`.
    enum ErrorCode: String {
        case invalidArgument
        case notFound
        case notAllowed
        case unavailable
        case failed
    }
}
