/// Why `shellx routine` arguments were rejected.
public enum ShellXRoutineArgumentsError: Error, Equatable, Sendable {
    /// No subcommand was given.
    case usage
    /// The subcommand is not `run`, `notify` or `list`.
    case unknownSubcommand(String)
    /// `run` was given no automation id.
    case missingID
    /// `flag` is required, or was given without a value.
    case missingValue(flag: String)
    /// `--trigger` is not `schedule` or `manual`.
    case invalidTrigger(String)
    /// `--status` is not `done`, `failed` or `needs-you`.
    case invalidStatus(String)
    /// An argument the subcommand does not take.
    case unexpectedArgument(String)
}
