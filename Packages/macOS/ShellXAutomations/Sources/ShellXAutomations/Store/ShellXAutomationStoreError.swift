/// Why the store refused an operation.
public enum ShellXAutomationStoreError: Error, Sendable, Equatable {
    /// The name could not be used as a folder name inside the roots.
    case invalidName(String)
    /// The id is malformed.
    case invalidID(String)
    /// No automation has this id.
    case notFound(String)
    /// A folder with this name already exists.
    case alreadyExists(String)
    /// The operation does not apply to this automation (skills are always enabled and never run).
    case unsupported(String)
    /// The run directory does not belong to the automation.
    case foreignRunDirectory
}
