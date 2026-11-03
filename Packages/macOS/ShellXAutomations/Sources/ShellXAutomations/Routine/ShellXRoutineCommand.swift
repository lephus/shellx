/// One `shellx routine` invocation.
public enum ShellXRoutineCommand: Equatable, Sendable {
    /// `routine run <id> [--trigger schedule|manual]`.
    case run(id: String, trigger: ShellXRunTrigger)
    /// `routine notify --name <name> --status done|failed|needs-you --body <text>`.
    case notify(name: String, status: ShellXNotifyEvent, body: String)
    /// `routine list [--json]`.
    case list(json: Bool)
}
