//! GPUI-free data for the app shell (title bar + sidebar): the local machine
//! entry, session row titles, and the strings the shell draws. Kept out of
//! `ui/` so the Mac tests and `--smoke-ui-assets` cover it.

// The window (cfg(windows)) is the main user; the Mac build only tests it.
#![cfg_attr(not(windows), allow(dead_code))]

use shellx_model::sidebar::MachineInfo;
use shellx_model::strings::{Lang, Str, t};

/// Machine id of this PC in the sidebar (the only machine until Task 12).
pub const LOCAL_MACHINE_ID: &str = "local";

/// Name shown when `COMPUTERNAME` is missing or blank.
pub const FALLBACK_PC_NAME: &str = "PC Windows";

/// Every `Str` the title bar and sidebar draw. `--smoke-ui-assets` checks
/// each is non-empty in vi and en; add to it when the shell draws a new one.
pub const SHELL_STRINGS: &[Str] = &[
    Str::AppName,
    Str::SearchPlaceholder,
    Str::MachinesHeader,
    Str::ThisMachine,
    Str::Offline,
    Str::LocalShell,
    Str::E2eFooter,
    Str::NewTab,
];

/// This PC as a sidebar machine; `computer_name` is `%COMPUTERNAME%`.
pub fn this_machine(computer_name: Option<&str>) -> MachineInfo {
    let name = computer_name
        .map(str::trim)
        .filter(|n| !n.is_empty())
        .unwrap_or(FALLBACK_PC_NAME);
    MachineInfo {
        machine_id: LOCAL_MACHINE_ID.to_string(),
        name: name.to_string(),
        platform: "windows".to_string(),
        online: true,
        last_seen_unix: 0,
        fingerprint: String::new(),
        is_this_machine: true,
    }
}

/// Session row title: the terminal's OSC title, else `Str::LocalShell`.
pub fn session_title(terminal_title: Option<&str>, lang: Lang) -> String {
    terminal_title
        .map(str::trim)
        .filter(|title| !title.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| t(lang, Str::LocalShell).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use shellx_model::sidebar::{Access, MachineIcon, RowAction, build_groups};

    #[test]
    fn this_machine_uses_computer_name_or_fallback() {
        assert_eq!(this_machine(Some("DESKTOP-42")).name, "DESKTOP-42");
        assert_eq!(this_machine(Some("  ")).name, FALLBACK_PC_NAME);
        assert_eq!(this_machine(None).name, FALLBACK_PC_NAME);
        let m = this_machine(None);
        assert_eq!(m.machine_id, LOCAL_MACHINE_ID);
        assert_eq!(m.platform, "windows");
        assert!(m.online && m.is_this_machine);
        assert_eq!((m.last_seen_unix, m.fingerprint.as_str()), (0, ""));
    }

    #[test]
    fn local_group_is_desktop_with_note_and_sessions() {
        let groups = build_groups(
            &[this_machine(Some("PC-1"))],
            &|_| Access::None,
            0,
            Lang::Vi,
        );
        assert_eq!(groups.len(), 1);
        let g = &groups[0];
        assert_eq!(g.title, "PC-1");
        assert_eq!(g.note.as_deref(), Some("máy này"));
        assert_eq!(g.icon, MachineIcon::Desktop);
        assert!(g.online && !g.dimmed && g.sessions_visible);
        assert_eq!(g.action, RowAction::None);
    }

    #[test]
    fn session_title_falls_back_to_local_shell() {
        assert_eq!(
            session_title(Some("vim notes.txt"), Lang::Vi),
            "vim notes.txt"
        );
        assert_eq!(session_title(Some("   "), Lang::En), "PowerShell");
        assert_eq!(session_title(None, Lang::Vi), "PowerShell");
    }

    #[test]
    fn shell_strings_are_non_empty() {
        for lang in [Lang::Vi, Lang::En] {
            for s in SHELL_STRINGS {
                assert!(!t(lang, *s).trim().is_empty(), "{s:?} empty in {lang:?}");
            }
        }
    }
}
