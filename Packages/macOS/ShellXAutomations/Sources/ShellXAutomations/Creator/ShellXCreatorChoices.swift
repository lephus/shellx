/// Quick-reply options the assistant offers with a question.
public struct ShellXCreatorChoices: Codable, Sendable, Equatable {
    /// The question the options answer.
    public let question: String
    /// Whether several options may be picked.
    public let multi: Bool
    /// Option texts; the chosen text is sent back as the user's message.
    public let options: [String]

    /// Creates a choice set.
    public init(question: String, multi: Bool, options: [String]) {
        self.question = question
        self.multi = multi
        self.options = options
    }
}
