/// Why a cron expression cannot be scheduled.
public enum ShellXCronError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Not five numeric fields, or a field is unparsable.
    case malformed
    /// Month/day names or `@` shortcuts.
    case unsupported
    /// Both day-of-month and day-of-week are restricted.
    case bothDayFields
    /// A value outside the field's range; carries the field name.
    case outOfRange(field: String)
    /// A `*/n` step that does not divide the minute or hour range evenly, so runs would not be evenly spaced.
    case unevenStep(field: String)
    /// Expands to more launchd entries than allowed.
    case tooManyEntries

    /// Short English explanation.
    public var description: String {
        switch self {
        case .malformed: "expected five numeric fields"
        case .unsupported: "names and @ shortcuts are not supported"
        case .bothDayFields: "day of month and day of week cannot both be set"
        case .outOfRange(let field): "\(field) is out of range"
        case .unevenStep(let field): "\(field) step does not divide evenly, so runs would be unevenly spaced"
        case .tooManyEntries: "it needs too many launch entries"
        }
    }
}
