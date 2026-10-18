import ShellXBrand

extension SidebarStatusPill {
    /// The pill for a row's compact status glyph; nil means no pill.
    static func from(_ kind: SidebarCompactStatusGlyph.Kind) -> SidebarStatusPill? {
        switch kind {
        case .needsInput:
            return .waiting
        case .running, .subagents, .pending:
            return .running
        case .unseen:
            return .done
        case .error:
            return .error
        case .waiting, .pullRequest, .idle, .branch, .terminal:
            return nil
        }
    }
}
