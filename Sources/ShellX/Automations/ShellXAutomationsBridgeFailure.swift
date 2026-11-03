import Foundation
import ShellXAutomations

/// A failed Automations bridge request: its wire code and a localized message the page shows.
///
/// Every message that can reach the page is built here, so none of them is a raw
/// `String(describing:)` of a Swift error.
struct ShellXAutomationsBridgeFailure: Error, Equatable {
    let code: ShellXAutomationsBridgeContract.ErrorCode
    let message: String

    init(_ code: ShellXAutomationsBridgeContract.ErrorCode, _ message: String) {
        self.code = code
        self.message = message
    }

    /// Maps any error thrown while answering a request.
    init(_ error: any Error) {
        if let failure = error as? ShellXAutomationsBridgeFailure {
            self = failure
            return
        }
        if let storeError = error as? ShellXAutomationStoreError {
            self = Self.store(storeError)
            return
        }
        if error is ShellXLaunchAgentError {
            self = Self.scheduleFailed
            return
        }
        if let cocoa = error as? CocoaError {
            // Foundation already localizes file errors.
            self.init(.failed, cocoa.localizedDescription)
            return
        }
        self = Self.generic
    }

    static func store(_ error: ShellXAutomationStoreError) -> Self {
        switch error {
        case .notFound:
            return notFound
        case .invalidID, .invalidName:
            return Self(.invalidArgument, String(
                localized: "automations.error.invalidName",
                defaultValue: "This name or id cannot be used."
            ))
        case .unsupported:
            return Self(.notAllowed, String(
                localized: "automations.error.unsupported",
                defaultValue: "This does not apply to this automation."
            ))
        case .alreadyExists(let name):
            return Self(.failed, String(
                localized: "automations.error.alreadyExists",
                defaultValue: "A folder named \(name) already exists."
            ))
        case .foreignRunDirectory:
            return generic
        }
    }

    static func invalidParameter(_ name: String) -> Self {
        Self(.invalidArgument, String(
            localized: "automations.error.invalidParameter",
            defaultValue: "The request is missing \(name)."
        ))
    }

    static func unknownMethod(_ name: String) -> Self {
        Self(.invalidArgument, String(
            localized: "automations.error.unknownMethod",
            defaultValue: "ShellX does not know the request \(name)."
        ))
    }

    static var notFound: Self {
        Self(.notFound, String(localized: "automations.error.notFound", defaultValue: "This automation no longer exists."))
    }

    static var generic: Self {
        Self(.failed, String(localized: "automations.error.generic", defaultValue: "Something went wrong."))
    }

    static var scheduleFailed: Self {
        Self(.failed, String(
            localized: "automations.error.scheduleFailed",
            defaultValue: "The schedule could not be set up on this Mac."
        ))
    }

    static var skillCannotRun: Self {
        Self(.notAllowed, String(
            localized: "automations.error.skillCannotRun",
            defaultValue: "Skills run inside Claude Code, not on their own."
        ))
    }

    static var externalDeleteNeedsConfirmation: Self {
        Self(.notAllowed, String(
            localized: "automations.error.externalDelete",
            defaultValue: "ShellX did not create this skill. Confirm before deleting it."
        ))
    }

    static var noLog: Self {
        Self(.notFound, String(localized: "automations.error.noLog", defaultValue: "This automation has no log yet."))
    }

    static var noSession: Self {
        Self(.notFound, String(
            localized: "automations.error.noSession",
            defaultValue: "The last run has no Claude Code session to continue."
        ))
    }

    static var assistantNotRunning: Self {
        Self(.unavailable, String(
            localized: "automations.error.assistantNotRunning",
            defaultValue: "The assistant is not running."
        ))
    }

    static var noDraft: Self {
        Self(.invalidArgument, String(
            localized: "automations.error.noDraft",
            defaultValue: "There is no draft to save yet."
        ))
    }

    static var untrustedFrame: Self {
        Self(.notAllowed, String(
            localized: "automations.error.untrustedFrame",
            defaultValue: "Requests are accepted only from the Automations page."
        ))
    }

    static var malformedRequest: Self {
        Self(.invalidArgument, String(localized: "automations.error.malformedRequest", defaultValue: "The request was malformed."))
    }

    /// The assistant could not start; `detail` is already readable (localized or Claude Code's own output).
    static func assistantFailedToStart(_ detail: String) -> Self {
        Self(.unavailable, String(
            localized: "automations.error.assistantFailedToStart",
            defaultValue: "The assistant could not start: \(detail)"
        ))
    }

    /// "Run now" could not start `shellx routine run`, or it stopped at once.
    static func runFailed(_ detail: String) -> Self {
        Self(.failed, String(
            localized: "automations.error.runFailed",
            defaultValue: "The run could not start: \(detail)"
        ))
    }
}
