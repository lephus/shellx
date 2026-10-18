/// Session states and the palette color each one is drawn in
/// (spec §7.4 status table). Pills use the color at about 12% for the fill
/// and the full color for the text.
public enum ShellXStatus: CaseIterable, Sendable {
    /// "chờ bạn": the session needs your input.
    case needsYou
    /// "chạy": an agent or command is working.
    case running
    /// "xong": finished (and not yet seen).
    case done
    /// "lỗi": something failed.
    case error
    /// Idle: no pill, muted glyph.
    case idle

    public var color: ShellXColor {
        switch self {
        case .needsYou: return ShellXPalette.primary
        case .running: return ShellXPalette.running
        case .done: return ShellXPalette.done
        case .error: return ShellXPalette.error
        case .idle: return ShellXPalette.muted
        }
    }
}
