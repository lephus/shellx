//! Which terminal app hosts this window, for the phone's session list
//! (spec §6.3 `app`). macOS hands every app's processes its bundle id in
//! `__CFBundleIdentifier`; `TERM_PROGRAM` and JetBrains' variable are
//! fallbacks.

const BY_BUNDLE: &[(&str, &str)] = &[
    ("com.apple.Terminal", "Terminal"),
    ("com.googlecode.iterm2", "iTerm2"),
    ("com.microsoft.VSCode", "VS Code"),
    ("com.microsoft.VSCodeInsiders", "VS Code Insiders"),
    ("com.todesktop.230313mzl4w4u92", "Cursor"),
    ("com.google.android.studio", "Android Studio"),
    ("com.jetbrains.intellij", "IntelliJ IDEA"),
    ("com.jetbrains.intellij.ce", "IntelliJ IDEA CE"),
    ("dev.warp.Warp-Stable", "Warp"),
    ("com.mitchellh.ghostty", "Ghostty"),
    ("net.kovidgoyal.kitty", "kitty"),
    ("org.alacritty", "Alacritty"),
    ("com.github.wez.wezterm", "WezTerm"),
];

const BY_TERM_PROGRAM: &[(&str, &str)] = &[
    ("Apple_Terminal", "Terminal"),
    ("iTerm.app", "iTerm2"),
    ("vscode", "VS Code"),
    ("WarpTerminal", "Warp"),
    ("ghostty", "Ghostty"),
    ("WezTerm", "WezTerm"),
];

/// A display name, or "" when unknown. `get` reads an environment variable.
pub fn terminal_app(get: impl Fn(&str) -> Option<String>) -> String {
    if let Some(id) = get("__CFBundleIdentifier") {
        if let Some((_, name)) = BY_BUNDLE.iter().find(|(bundle, _)| *bundle == id) {
            return name.to_string();
        }
    }
    if let Some(program) = get("TERM_PROGRAM").filter(|p| !p.is_empty()) {
        return BY_TERM_PROGRAM
            .iter()
            .find(|(raw, _)| *raw == program)
            .map(|(_, name)| name.to_string())
            .unwrap_or(program);
    }
    if get("TERMINAL_EMULATOR").as_deref() == Some("JetBrains-JediTerm") {
        return "JetBrains".to_string();
    }
    String::new()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn app(vars: &[(&str, &str)]) -> String {
        terminal_app(|k| {
            vars.iter()
                .find(|(name, _)| *name == k)
                .map(|(_, v)| v.to_string())
        })
    }

    #[test]
    fn the_bundle_id_wins() {
        assert_eq!(
            app(&[
                ("__CFBundleIdentifier", "com.todesktop.230313mzl4w4u92"),
                ("TERM_PROGRAM", "vscode")
            ]),
            "Cursor"
        );
        assert_eq!(
            app(&[("__CFBundleIdentifier", "com.apple.Terminal")]),
            "Terminal"
        );
    }

    #[test]
    fn falls_back_to_term_program_then_jetbrains() {
        assert_eq!(
            app(&[
                ("__CFBundleIdentifier", "com.unknown"),
                ("TERM_PROGRAM", "iTerm.app")
            ]),
            "iTerm2"
        );
        assert_eq!(app(&[("TERM_PROGRAM", "Hyper")]), "Hyper");
        assert_eq!(
            app(&[("TERMINAL_EMULATOR", "JetBrains-JediTerm")]),
            "JetBrains"
        );
        assert_eq!(app(&[]), "");
    }
}
