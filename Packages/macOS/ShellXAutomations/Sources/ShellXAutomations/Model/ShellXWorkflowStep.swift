/// One step of a workflow, run as a prompt in order.
public struct ShellXWorkflowStep: Codable, Sendable, Equatable {
    /// Short step title.
    public var title: String
    /// Prompt sent to Claude for this step.
    public var prompt: String

    /// Creates a workflow step.
    public init(title: String, prompt: String) {
        self.title = title
        self.prompt = prompt
    }
}
