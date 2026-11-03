/// An event the creator session publishes to the UI.
public enum ShellXCreatorEvent: Sendable, Equatable {
    /// Visible assistant text that just streamed in (structured blocks removed).
    case textDelta(String)
    /// A complete assistant message, with the quick-reply choices it offered.
    case assistantMessage(text: String, choices: ShellXCreatorChoices?)
    /// The latest valid draft the assistant proposed.
    case draft(ShellXAutomationDraft)
    /// Whether the assistant is working on a turn.
    case busy(Bool)
    /// The session failed; the message is readable by the user.
    case failed(String)
}
