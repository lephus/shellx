/// The themes the Settings gallery lists when no search is typed: twelve per
/// appearance, by exact Ghostty theme name. "Search all themes" reaches the
/// rest of the catalog, and the themes in use always appear in their section.
enum TerminalThemeCuration {
    /// Dark themes, in display order.
    static let dark: [String] = [
        "One Half Dark", "Catppuccin Mocha", "iTerm2 Solarized Dark", "GitHub Dark Default", "TokyoNight", "Rose Pine",
        "Gruvbox Dark", "Everforest Dark Hard", "Atom One Dark", "Nord", "Ayu Mirage", "Kanagawa Wave",
    ]
    /// Light themes, in display order.
    static let light: [String] = [
        "Catppuccin Latte", "iTerm2 Solarized Light", "GitHub Light Default", "TokyoNight Day", "Rose Pine Dawn",
        "Gruvbox Light", "Everforest Light Med", "Atom One Light", "Nord Light", "Ayu Light", "Kanagawa Lotus", "One Half Light",
    ]
}
