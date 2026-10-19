//! GPUI-free data for the app shell (title bar + sidebar): the local machine
//! entry, session row titles, and the strings the shell draws. Kept out of
//! `ui/` so the Mac tests and `--smoke-ui-assets` cover it.

// The window (cfg(windows)) is the main user; the Mac build only tests it.
#![cfg_attr(not(windows), allow(dead_code))]

use shellx_model::sidebar::MachineInfo;
use shellx_model::strings::{Lang, Str, t};

/// Machine id of this PC in the sidebar while it has no server entry
/// (signed out, or not registered yet).
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
    Str::NotLoggedIn,
    Str::Login,
    Str::Email,
    Str::Password,
    Str::LoginFailed,
    Str::SigningIn,
    Str::Cancel,
    Str::RequestAccess,
    Str::Error,
    Str::Settings,
    Str::About,
    Str::Version,
    Str::IconCredits,
    Str::CmuxCredits,
    Str::FontCredits,
    Str::Account,
    Str::Updates,
    Str::Language,
    Str::LanguageHint,
    Str::LanguageName,
    Str::CheckUpdate,
    Str::Checking,
    Str::SignedIn,
    Str::Close,
    Str::CheckFailed,
    Str::Logout,
    Str::UpdateAvailable,
    Str::UpdateRequired,
    Str::UpToDate,
    Str::Download,
    Str::PairingCodeHint,
    Str::WaitingApproval,
    Str::Approved,
    Str::Denied,
    Str::Expired,
    Str::Open,
    Str::Retry,
    Str::ComingSoon,
    Str::YourDeviceCode,
    Str::SaveLinkFailed,
    Str::SendingRequest,
    Str::NoOtherMachines,
    Str::AddMachine,
    // remote panes (Task 13b): overlay pill and the input-paused flash
    Str::Connecting,
    Str::Reconnecting,
    Str::RemoteEnded,
    Str::InputPaused,
    Str::PasteTooLarge,
    Str::FingerprintMismatch,
    Str::NeedsPairing,
    Str::RemoteAttachFailed,
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

/// Machines for the sidebar: the server's list when there is one (this PC is
/// its `is_this_machine` entry), with this PC added first when the list
/// lacks it (signed out, or not registered yet).
pub fn sidebar_machines(server: &[MachineInfo], computer_name: Option<&str>) -> Vec<MachineInfo> {
    let mut list = server.to_vec();
    if !list.iter().any(|m| m.is_this_machine) {
        list.insert(0, this_machine(computer_name));
    }
    list
}

/// The group id of this PC in a `sidebar_machines` list.
pub fn this_machine_id(list: &[MachineInfo]) -> &str {
    list.iter()
        .find(|m| m.is_this_machine)
        .map_or(LOCAL_MACHINE_ID, |m| m.machine_id.as_str())
}

/// Session row title: the terminal's OSC title, else `Str::LocalShell`.
pub fn session_title(terminal_title: Option<&str>, lang: Lang) -> String {
    terminal_title
        .map(str::trim)
        .filter(|title| !title.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| t(lang, Str::LocalShell).to_string())
}

/// Session row title of a remote (Mac) tab: the terminal's OSC title, else
/// the machine's name.
pub fn remote_session_title(terminal_title: Option<&str>, machine_name: &str) -> String {
    terminal_title
        .map(str::trim)
        .filter(|title| !title.is_empty())
        .unwrap_or(machine_name)
        .to_string()
}

/// The window title's own name (also the whole title when nothing else fits).
pub const BASE_TITLE: &str = "ShellX";

/// Longest text (in chars) put before `" - ShellX"` in the window title.
pub const TITLE_MAX_CHARS: usize = 80;

/// Control chars removed, surrounding blanks trimmed, clipped to
/// `TITLE_MAX_CHARS` chars (never inside a char).
fn title_text(text: &str) -> String {
    let clean: String = text.chars().filter(|c| !c.is_control()).collect();
    clean.trim().chars().take(TITLE_MAX_CHARS).collect()
}

/// The window title (visible through GetWindowText, the taskbar, Alt+Tab and
/// screen sharing). Default: the terminal's OSC title, else nothing, before
/// " - ShellX", and NEVER any screen text. `screen_reader` (a screen reader
/// is running, or `SHELLX_A11Y_TITLE=1`): the accessibility stopgap, the
/// focused pane's cursor line instead (GPUI 0.2.2 has no UIA tree; Narrator
/// reads the title with Insert+T).
pub fn window_title(osc_title: Option<&str>, cursor_line: &str, screen_reader: bool) -> String {
    let line = if screen_reader {
        title_text(cursor_line)
    } else {
        String::new()
    };
    let text = if line.is_empty() {
        osc_title.map(title_text).unwrap_or_default()
    } else {
        line
    };
    if text.is_empty() {
        BASE_TITLE.to_string()
    } else {
        format!("{text} - {BASE_TITLE}")
    }
}

/// `SHELLX_A11Y_TITLE`: `1` forces the cursor-line title.
pub fn a11y_title_env(value: Option<&str>) -> bool {
    value.is_some_and(|v| v.trim() == "1")
}

/// Caches the "is a screen reader running" answer; asks again at most once
/// per second (the title is computed every frame).
#[derive(Debug, Default)]
pub struct ScreenReaderProbe {
    /// (asked at ms, answer)
    last: Option<(u64, bool)>,
}

impl ScreenReaderProbe {
    pub const RECHECK_MS: u64 = 1_000;

    pub const fn new() -> ScreenReaderProbe {
        ScreenReaderProbe { last: None }
    }

    pub fn running(&mut self, now_ms: u64, ask: impl FnOnce() -> bool) -> bool {
        match self.last {
            Some((at, answer)) if now_ms >= at && now_ms - at < Self::RECHECK_MS => answer,
            _ => {
                let answer = ask();
                self.last = Some((now_ms, answer));
                answer
            }
        }
    }
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
    fn sidebar_machines_this_pc_first_then_server_list() {
        // signed out: only this PC
        let list = sidebar_machines(&[], Some("PC-1"));
        assert_eq!(list.len(), 1);
        assert_eq!(this_machine_id(&list), LOCAL_MACHINE_ID);
        // signed in: the server entry is this PC (no duplicate), others follow
        let mac = MachineInfo {
            machine_id: "m-mac".into(),
            name: "MacBook".into(),
            platform: "macos".into(),
            online: false,
            last_seen_unix: 1_760_841_900,
            fingerprint: "f".into(),
            is_this_machine: false,
        };
        let me = MachineInfo {
            machine_id: "m-pc".into(),
            name: "PC-1".into(),
            platform: "windows".into(),
            online: true,
            last_seen_unix: 0,
            fingerprint: "g".into(),
            is_this_machine: true,
        };
        let list = sidebar_machines(&[mac.clone(), me.clone()], Some("PC-1"));
        assert_eq!(list.len(), 2);
        assert_eq!(this_machine_id(&list), "m-pc");
        let groups = build_groups(&list, &|_| Access::None, 7 * 3600, Lang::Vi);
        assert_eq!(groups[0].machine_id, "m-pc");
        assert_eq!(
            groups[1].subtitle.as_deref(),
            Some("ngoại tuyến · lần cuối 09:45")
        );
        assert!(groups[1].dimmed);
        // registered list without this PC yet: this PC is added first
        let list = sidebar_machines(&[mac], None);
        assert_eq!(list[0].machine_id, LOCAL_MACHINE_ID);
        assert_eq!(list.len(), 2);
        let mut online = me;
        online.is_this_machine = false;
        online.machine_id = "m-other".into();
        let groups = build_groups(&[online], &|_| Access::None, 0, Lang::Vi);
        assert_eq!(groups[0].action, RowAction::RequestAccess);
    }

    #[test]
    fn session_title_falls_back_to_local_shell() {
        assert_eq!(
            session_title(Some("vim notes.txt"), Lang::Vi),
            "vim notes.txt"
        );
        assert_eq!(session_title(Some("   "), Lang::En), "PowerShell");
        assert_eq!(session_title(None, Lang::Vi), "PowerShell");
        assert_eq!(
            remote_session_title(Some("phu@mac: ~"), "MacBook"),
            "phu@mac: ~"
        );
        assert_eq!(remote_session_title(Some(" "), "MacBook"), "MacBook");
        assert_eq!(remote_session_title(None, "MacBook"), "MacBook");
    }

    #[test]
    fn default_title_never_carries_screen_text() {
        let line = "PS C:\\Users\\phu> mysql -p hunter2";
        assert_eq!(window_title(None, line, false), "ShellX");
        assert_eq!(
            window_title(Some("vim notes.txt"), line, false),
            "vim notes.txt - ShellX"
        );
        assert_eq!(window_title(Some("  "), line, false), "ShellX");
        for osc in [None, Some("t")] {
            let title = window_title(osc, line, false);
            assert!(!title.contains("hunter2"), "{title}");
            assert!(!title.contains("mysql"), "{title}");
        }
    }

    #[test]
    fn screen_reader_title_carries_the_cursor_line() {
        let line = "PS C:\\> dir   ";
        assert_eq!(window_title(None, line, true), "PS C:\\> dir - ShellX");
        assert_eq!(
            window_title(Some("vim"), line, true),
            "PS C:\\> dir - ShellX"
        );
        // an empty cursor line falls back to the short title
        assert_eq!(window_title(Some("vim"), "   ", true), "vim - ShellX");
        assert_eq!(window_title(None, "", true), "ShellX");
    }

    #[test]
    fn title_text_is_clipped_and_has_no_control_chars() {
        let osc = format!("a\x1b]0;evil\x07b\tc\r\nd{}", "x".repeat(500));
        let title = window_title(Some(&osc), "", false);
        assert!(!title.chars().any(char::is_control), "{title:?}");
        assert!(title.starts_with("a]0;evilbcd"), "{title:?}");
        assert!(title.ends_with(" - ShellX"), "{title:?}");
        let text = title.trim_end_matches(" - ShellX");
        assert_eq!(text.chars().count(), TITLE_MAX_CHARS);
        // char-based clipping never splits a multi-byte char
        let vi = "tiếng Việt ".repeat(40);
        let title = window_title(Some(&vi), "", false);
        assert_eq!(
            title.trim_end_matches(" - ShellX").chars().count(),
            TITLE_MAX_CHARS
        );
        // the screen-reader line is cleaned the same way
        let line = format!("ls\x07{}", "y".repeat(500));
        let title = window_title(None, &line, true);
        assert!(!title.chars().any(char::is_control));
        assert_eq!(
            title.trim_end_matches(" - ShellX").chars().count(),
            TITLE_MAX_CHARS
        );
    }

    #[test]
    fn a11y_title_env_needs_exactly_one() {
        assert!(a11y_title_env(Some("1")));
        assert!(a11y_title_env(Some(" 1 ")));
        for v in [None, Some(""), Some("0"), Some("true"), Some("yes")] {
            assert!(!a11y_title_env(v), "{v:?}");
        }
    }

    #[test]
    fn screen_reader_probe_asks_at_most_once_per_second() {
        let mut probe = ScreenReaderProbe::default();
        let mut asked = 0;
        let mut query = |now: u64, answer: bool, probe: &mut ScreenReaderProbe| {
            probe.running(now, || {
                asked += 1;
                answer
            })
        };
        assert!(!query(0, false, &mut probe));
        assert!(!query(999, true, &mut probe)); // cached
        assert!(query(1_000, true, &mut probe)); // re-asked
        assert!(query(1_500, false, &mut probe)); // cached
        assert!(!query(2_000, false, &mut probe));
        // a clock that went backwards asks again instead of caching forever
        assert!(query(10, true, &mut probe));
        drop(query);
        assert_eq!(asked, 4);
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
