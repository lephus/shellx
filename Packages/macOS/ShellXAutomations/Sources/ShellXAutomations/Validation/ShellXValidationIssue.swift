/// One problem found in a draft. The host localizes by `code`; `message` is plain English.
public struct ShellXValidationIssue: Sendable, Equatable {
    /// The draft field an issue refers to.
    public enum Field: String, Sendable, Equatable {
        case name, description, schedule, workingDirectory, skillMarkdown, claude, steps
    }

    /// Field with the problem.
    public let field: Field
    /// Short camelCase code such as `invalid`, `duplicate`, `tooLong`, `missing`, `mismatch`, `notFound`, `unavailable`.
    public let code: String
    /// English description.
    public let message: String

    /// Creates an issue.
    public init(field: Field, code: String, message: String) {
        self.field = field
        self.code = code
        self.message = message
    }
}
