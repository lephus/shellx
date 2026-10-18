//! UI strings: Vietnamese by default, English via `SHELLX_LANG=en`.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Lang {
    Vi,
    En,
}

impl Lang {
    /// `en`, `EN`, `en-US` (any value starting with "en", case-insensitive) select English;
    /// everything else, including no value, selects Vietnamese.
    pub fn from_env_value(v: Option<&str>) -> Lang {
        match v {
            Some(s) if s.trim().to_ascii_lowercase().starts_with("en") => Lang::En,
            _ => Lang::Vi,
        }
    }

    /// Reads `SHELLX_LANG`.
    pub fn from_env() -> Lang {
        Lang::from_env_value(std::env::var("SHELLX_LANG").ok().as_deref())
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Str {
    AppName,
    MachinesHeader,
    ThisMachine,
    Offline,
    Online,
    Connecting,
    Reconnecting,
    E2eFooter,
    SearchPlaceholder,
    Login,
    Logout,
    Email,
    Password,
    LoginFailed,
    NotLoggedIn,
    SigningIn,
    RequestAccess,
    PairingCodeHint,
    WaitingApproval,
    Approved,
    Denied,
    Expired,
    Open,
    Cancel,
    Retry,
    UpdateAvailable,
    UpdateRequired,
    UpToDate,
    Download,
    Settings,
    About,
    Version,
    IconCredits,
    CmuxCredits,
    NewTab,
    ClosePane,
    SplitRight,
    SplitDown,
    Copy,
    Paste,
    ToggleSidebar,
    StatusWaiting,
    StatusRunning,
    StatusDone,
    StatusError,
    LocalShell,
    RemoteEnded,
    InputPaused,
    NoTerminalOnMachine,
    Error,
    Account,
    Updates,
    Language,
    LanguageHint,
    LanguageName,
    CheckUpdate,
    Checking,
    SignedIn,
    Close,
    FontCredits,
    CheckFailed,
}

impl Str {
    pub const ALL: &'static [Str] = &[
        Str::AppName,
        Str::MachinesHeader,
        Str::ThisMachine,
        Str::Offline,
        Str::Online,
        Str::Connecting,
        Str::Reconnecting,
        Str::E2eFooter,
        Str::SearchPlaceholder,
        Str::Login,
        Str::Logout,
        Str::Email,
        Str::Password,
        Str::LoginFailed,
        Str::NotLoggedIn,
        Str::SigningIn,
        Str::RequestAccess,
        Str::PairingCodeHint,
        Str::WaitingApproval,
        Str::Approved,
        Str::Denied,
        Str::Expired,
        Str::Open,
        Str::Cancel,
        Str::Retry,
        Str::UpdateAvailable,
        Str::UpdateRequired,
        Str::UpToDate,
        Str::Download,
        Str::Settings,
        Str::About,
        Str::Version,
        Str::IconCredits,
        Str::CmuxCredits,
        Str::NewTab,
        Str::ClosePane,
        Str::SplitRight,
        Str::SplitDown,
        Str::Copy,
        Str::Paste,
        Str::ToggleSidebar,
        Str::StatusWaiting,
        Str::StatusRunning,
        Str::StatusDone,
        Str::StatusError,
        Str::LocalShell,
        Str::RemoteEnded,
        Str::InputPaused,
        Str::NoTerminalOnMachine,
        Str::Error,
        Str::Account,
        Str::Updates,
        Str::Language,
        Str::LanguageHint,
        Str::LanguageName,
        Str::CheckUpdate,
        Str::Checking,
        Str::SignedIn,
        Str::Close,
        Str::FontCredits,
        Str::CheckFailed,
    ];
}

/// Looks up a UI string. One exhaustive `match` per language: a missing key fails to compile.
pub fn t(lang: Lang, key: Str) -> &'static str {
    match lang {
        Lang::Vi => match key {
            Str::AppName => "ShellX",
            Str::MachinesHeader => "MÁY CỦA BẠN",
            Str::ThisMachine => "máy này",
            Str::Offline => "ngoại tuyến",
            Str::Online => "trực tuyến",
            Str::Connecting => "đang kết nối…",
            Str::Reconnecting => "đang kết nối lại…",
            Str::E2eFooter => "Mã hoá đầu cuối · relay.shellx.pro",
            Str::SearchPlaceholder => "Tìm phiên, máy, lệnh… Ctrl+K",
            Str::Login => "Đăng nhập",
            Str::Logout => "Đăng xuất",
            Str::Email => "Email",
            Str::Password => "Mật khẩu",
            Str::LoginFailed => "Đăng nhập không thành công",
            Str::NotLoggedIn => "Chưa đăng nhập",
            Str::SigningIn => "Đang đăng nhập…",
            Str::RequestAccess => "Xin quyền truy cập",
            Str::PairingCodeHint => "Kiểm tra mã này trên máy kia rồi bấm Chấp thuận",
            Str::WaitingApproval => "Đang chờ máy kia chấp thuận…",
            Str::Approved => "Đã được chấp thuận",
            Str::Denied => "Máy kia đã từ chối",
            Str::Expired => "Yêu cầu đã hết hạn",
            Str::Open => "Mở",
            Str::Cancel => "Huỷ",
            Str::Retry => "Thử lại",
            Str::UpdateAvailable => "Có bản cập nhật",
            Str::UpdateRequired => "Cần cập nhật",
            Str::UpToDate => "Đã là bản mới nhất",
            Str::Download => "Tải về",
            Str::Settings => "Cài đặt",
            Str::About => "Giới thiệu",
            Str::Version => "Phiên bản",
            Str::IconCredits => "coolicons by Kryston Schwarze (CC BY 4.0)",
            Str::CmuxCredits => "Dựa trên cmux (GPL-3.0)",
            Str::NewTab => "Tab mới",
            Str::ClosePane => "Đóng khung",
            Str::SplitRight => "Chia sang phải",
            Str::SplitDown => "Chia xuống dưới",
            Str::Copy => "Sao chép",
            Str::Paste => "Dán",
            Str::ToggleSidebar => "Ẩn/hiện thanh bên",
            Str::StatusWaiting => "chờ bạn",
            Str::StatusRunning => "chạy",
            Str::StatusDone => "xong",
            Str::StatusError => "lỗi",
            Str::LocalShell => "PowerShell",
            Str::RemoteEnded => "Phiên ở xa đã kết thúc",
            Str::InputPaused => "Mất kết nối, tạm ngừng nhập",
            Str::NoTerminalOnMachine => "Máy này chưa có phiên nào",
            Str::Error => "Lỗi",
            Str::Account => "Tài khoản",
            Str::Updates => "Cập nhật",
            Str::Language => "Ngôn ngữ",
            Str::LanguageHint => "đặt SHELLX_LANG=en để dùng tiếng Anh",
            Str::LanguageName => "Tiếng Việt",
            Str::CheckUpdate => "Kiểm tra cập nhật",
            Str::Checking => "Đang kiểm tra…",
            Str::SignedIn => "Đã đăng nhập",
            Str::Close => "Đóng",
            Str::FontCredits => "JetBrains Mono, Space Grotesk — SIL OFL 1.1",
            Str::CheckFailed => "Không kiểm tra được cập nhật",
        },
        Lang::En => match key {
            Str::AppName => "ShellX",
            Str::MachinesHeader => "YOUR MACHINES",
            Str::ThisMachine => "this machine",
            Str::Offline => "offline",
            Str::Online => "online",
            Str::Connecting => "connecting…",
            Str::Reconnecting => "reconnecting…",
            Str::E2eFooter => "End-to-end encrypted · relay.shellx.pro",
            Str::SearchPlaceholder => "Search sessions, machines, commands… Ctrl+K",
            Str::Login => "Sign in",
            Str::Logout => "Sign out",
            Str::Email => "Email",
            Str::Password => "Password",
            Str::LoginFailed => "Sign-in failed",
            Str::NotLoggedIn => "Not signed in",
            Str::SigningIn => "Signing in…",
            Str::RequestAccess => "Request access",
            Str::PairingCodeHint => "Check this code on the other machine, then approve",
            Str::WaitingApproval => "Waiting for the other machine to approve…",
            Str::Approved => "Approved",
            Str::Denied => "The other machine declined",
            Str::Expired => "The request expired",
            Str::Open => "Open",
            Str::Cancel => "Cancel",
            Str::Retry => "Retry",
            Str::UpdateAvailable => "Update available",
            Str::UpdateRequired => "Update required",
            Str::UpToDate => "Up to date",
            Str::Download => "Download",
            Str::Settings => "Settings",
            Str::About => "About",
            Str::Version => "Version",
            Str::IconCredits => "coolicons by Kryston Schwarze (CC BY 4.0)",
            Str::CmuxCredits => "Based on cmux (GPL-3.0)",
            Str::NewTab => "New tab",
            Str::ClosePane => "Close pane",
            Str::SplitRight => "Split right",
            Str::SplitDown => "Split down",
            Str::Copy => "Copy",
            Str::Paste => "Paste",
            Str::ToggleSidebar => "Toggle sidebar",
            Str::StatusWaiting => "waiting",
            Str::StatusRunning => "running",
            Str::StatusDone => "done",
            Str::StatusError => "error",
            Str::LocalShell => "PowerShell",
            Str::RemoteEnded => "The remote session ended",
            Str::InputPaused => "Disconnected, input paused",
            Str::NoTerminalOnMachine => "No sessions on this machine",
            Str::Error => "Error",
            Str::Account => "Account",
            Str::Updates => "Updates",
            Str::Language => "Language",
            Str::LanguageHint => "set SHELLX_LANG=vi for Vietnamese",
            Str::LanguageName => "English",
            Str::CheckUpdate => "Check for updates",
            Str::Checking => "Checking…",
            Str::SignedIn => "Signed in",
            Str::Close => "Close",
            Str::FontCredits => "JetBrains Mono, Space Grotesk — SIL OFL 1.1",
            Str::CheckFailed => "Could not check for updates",
        },
    }
}

/// "ngoại tuyến · lần cuối 09:05" / "offline · last seen 09:05".
pub fn offline_last_seen(lang: Lang, hh: u8, mm: u8) -> String {
    match lang {
        Lang::Vi => format!("{} · lần cuối {hh:02}:{mm:02}", t(lang, Str::Offline)),
        Lang::En => format!("{} · last seen {hh:02}:{mm:02}", t(lang, Str::Offline)),
    }
}

/// "Yêu cầu phiên bản tối thiểu 2.0.1" / "Minimum version 2.0.1" (forced update).
pub fn minimum_version(lang: Lang, version: &str) -> String {
    match lang {
        Lang::Vi => format!("Cần phiên bản {version} trở lên"),
        Lang::En => format!("Version {version} or newer is required"),
    }
}

/// Login error line: "Đăng nhập không thành công: <core message>" (just the
/// label when the core gave no message).
pub fn login_failed(lang: Lang, message: &str) -> String {
    let message = message.trim();
    if message.is_empty() {
        t(lang, Str::LoginFailed).to_string()
    } else {
        format!("{}: {message}", t(lang, Str::LoginFailed))
    }
}

/// "Có bản cập nhật 2.0.1" / "Update available: 2.0.1".
pub fn update_available(lang: Lang, version: &str) -> String {
    match lang {
        Lang::Vi => format!("{} {version}", t(lang, Str::UpdateAvailable)),
        Lang::En => format!("{}: {version}", t(lang, Str::UpdateAvailable)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn every_key_non_empty_in_both_langs() {
        for &s in Str::ALL {
            assert!(!t(Lang::Vi, s).is_empty(), "{s:?} vi");
            assert!(!t(Lang::En, s).is_empty(), "{s:?} en");
        }
    }

    #[test]
    fn all_has_no_duplicates() {
        let set: HashSet<Str> = Str::ALL.iter().copied().collect();
        assert_eq!(set.len(), Str::ALL.len());
        assert_eq!(Str::ALL.len(), 61);
    }

    #[test]
    fn exact_vi_strings() {
        assert_eq!(t(Lang::Vi, Str::MachinesHeader), "MÁY CỦA BẠN");
        assert_eq!(t(Lang::Vi, Str::Reconnecting), "đang kết nối lại…");
        assert_eq!(
            t(Lang::Vi, Str::E2eFooter),
            "Mã hoá đầu cuối · relay.shellx.pro"
        );
        assert_eq!(t(Lang::Vi, Str::StatusWaiting), "chờ bạn");
        assert_eq!(t(Lang::Vi, Str::StatusRunning), "chạy");
        assert_eq!(t(Lang::Vi, Str::StatusDone), "xong");
        assert_eq!(t(Lang::Vi, Str::StatusError), "lỗi");
        assert_eq!(t(Lang::En, Str::MachinesHeader), "YOUR MACHINES");
        assert_eq!(t(Lang::En, Str::StatusWaiting), "waiting");
        assert_eq!(t(Lang::Vi, Str::IconCredits), t(Lang::En, Str::IconCredits));
    }

    #[test]
    fn env_parsing() {
        assert_eq!(Lang::from_env_value(Some("en")), Lang::En);
        assert_eq!(Lang::from_env_value(Some("EN")), Lang::En);
        assert_eq!(Lang::from_env_value(Some("en-US")), Lang::En);
        assert_eq!(Lang::from_env_value(Some("vi")), Lang::Vi);
        assert_eq!(Lang::from_env_value(Some("fr")), Lang::Vi);
        assert_eq!(Lang::from_env_value(Some("")), Lang::Vi);
        assert_eq!(Lang::from_env_value(None), Lang::Vi);
    }

    #[test]
    fn helpers_zero_pad() {
        assert_eq!(
            offline_last_seen(Lang::Vi, 9, 5),
            "ngoại tuyến · lần cuối 09:05"
        );
        assert_eq!(
            offline_last_seen(Lang::En, 9, 5),
            "offline · last seen 09:05"
        );
        assert_eq!(
            offline_last_seen(Lang::En, 23, 59),
            "offline · last seen 23:59"
        );
        assert_eq!(
            login_failed(Lang::Vi, "invalid credentials"),
            "Đăng nhập không thành công: invalid credentials"
        );
        assert_eq!(login_failed(Lang::En, "  "), "Sign-in failed");
        assert_eq!(update_available(Lang::Vi, "2.0.1"), "Có bản cập nhật 2.0.1");
        assert_eq!(
            update_available(Lang::En, "2.0.1"),
            "Update available: 2.0.1"
        );
    }
}
