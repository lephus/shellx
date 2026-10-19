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
    ComingSoon,
    YourDeviceCode,
    SaveLinkFailed,
    SendingRequest,
    NoOtherMachines,
    AddMachine,
    FingerprintMismatch,
    NeedsPairing,
    RemoteAttachFailed,
    /// A held pane (`tabs::RespawnGuard`): the shell exits as it starts.
    ShellExitsAtStart,
    /// Under `ShellExitsAtStart`.
    PressAnyKeyToRetry,
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
        Str::ComingSoon,
        Str::YourDeviceCode,
        Str::SaveLinkFailed,
        Str::SendingRequest,
        Str::NoOtherMachines,
        Str::AddMachine,
        Str::FingerprintMismatch,
        Str::NeedsPairing,
        Str::RemoteAttachFailed,
        Str::ShellExitsAtStart,
        Str::PressAnyKeyToRetry,
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
            Str::ComingSoon => "sắp có",
            Str::YourDeviceCode => "Mã thiết bị của bạn",
            Str::SaveLinkFailed => "Không lưu được quyền truy cập",
            Str::SendingRequest => "Đang gửi yêu cầu…",
            Str::NoOtherMachines => "Không còn máy nào để xin quyền",
            Str::AddMachine => "Xin quyền truy cập máy khác",
            Str::FingerprintMismatch => "Khóa của máy không khớp, không kết nối",
            Str::NeedsPairing => "Cần xin quyền truy cập lại",
            Str::RemoteAttachFailed => "Không mở được phiên trên máy kia, đang thử lại…",
            Str::ShellExitsAtStart => "Shell thoát ngay khi khởi động. Kiểm tra SHELLX_SHELL.",
            Str::PressAnyKeyToRetry => "Nhấn phím bất kỳ hoặc Thử lại.",
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
            Str::ComingSoon => "coming soon",
            Str::YourDeviceCode => "Your device code",
            Str::SaveLinkFailed => "Could not save the access",
            Str::SendingRequest => "Sending the request…",
            Str::NoOtherMachines => "No other machines to request",
            Str::AddMachine => "Request access to another machine",
            Str::FingerprintMismatch => "The machine's key does not match; not connecting",
            Str::NeedsPairing => "Request access again",
            Str::RemoteAttachFailed => "Could not open the session on the other machine, retrying…",
            Str::ShellExitsAtStart => "The shell exits as soon as it starts. Check SHELLX_SHELL.",
            Str::PressAnyKeyToRetry => "Press any key or Retry.",
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

/// Pairing panel title: "Xin quyền truy cập <máy>" / "Request access to <machine>".
pub fn request_access_to(lang: Lang, machine: &str) -> String {
    match lang {
        Lang::Vi => format!("{} {machine}", t(lang, Str::RequestAccess)),
        Lang::En => format!("Request access to {machine}"),
    }
}

/// The 6-digit pairing code as shown: "123 456" (other lengths unchanged).
pub fn pairing_code_display(code: &str) -> String {
    let code = code.trim();
    if code.chars().count() == 6 {
        let (a, b) = code.split_at(code.char_indices().nth(3).map_or(code.len(), |(i, _)| i));
        format!("{a} {b}")
    } else {
        code.to_string()
    }
}

/// A device fingerprint (16 hex chars) in groups of 4: "0123 4567 89ab cdef".
pub fn fingerprint_groups(fingerprint: &str) -> String {
    let chars: Vec<char> = fingerprint.trim().chars().collect();
    chars
        .chunks(4)
        .map(|c| c.iter().collect::<String>())
        .collect::<Vec<_>>()
        .join(" ")
}

/// "Mã thiết bị của bạn: 0123 4567 89ab cdef".
pub fn your_device_code(lang: Lang, fingerprint: &str) -> String {
    format!(
        "{}: {}",
        t(lang, Str::YourDeviceCode),
        fingerprint_groups(fingerprint)
    )
}

/// "Không lưu được quyền truy cập: <error>" (just the label without one).
pub fn save_link_failed(lang: Lang, message: &str) -> String {
    let message = message.trim();
    if message.is_empty() {
        t(lang, Str::SaveLinkFailed).to_string()
    } else {
        format!("{}: {message}", t(lang, Str::SaveLinkFailed))
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
        assert_eq!(Str::ALL.len(), 72);
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
        assert_eq!(
            t(Lang::Vi, Str::ShellExitsAtStart),
            "Shell thoát ngay khi khởi động. Kiểm tra SHELLX_SHELL."
        );
        assert_eq!(t(Lang::Vi, Str::Retry), "Thử lại");
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

    #[test]
    fn pairing_helpers() {
        assert_eq!(
            request_access_to(Lang::Vi, "Mac của Phú"),
            "Xin quyền truy cập Mac của Phú"
        );
        assert_eq!(request_access_to(Lang::En, "Mac"), "Request access to Mac");
        assert_eq!(pairing_code_display("482913"), "482 913");
        assert_eq!(pairing_code_display(" 12345 "), "12345");
        assert_eq!(
            fingerprint_groups("0123456789abcdef"),
            "0123 4567 89ab cdef"
        );
        assert_eq!(fingerprint_groups("abcdef"), "abcd ef");
        assert_eq!(
            your_device_code(Lang::Vi, "0123456789abcdef"),
            "Mã thiết bị của bạn: 0123 4567 89ab cdef"
        );
        assert_eq!(t(Lang::Vi, Str::ComingSoon), "sắp có");
        assert_eq!(
            save_link_failed(Lang::Vi, "denied"),
            "Không lưu được quyền truy cập: denied"
        );
        assert_eq!(save_link_failed(Lang::En, ""), "Could not save the access");
    }

    #[test]
    fn remote_pane_strings() {
        assert_eq!(
            t(Lang::Vi, Str::FingerprintMismatch),
            "Khóa của máy không khớp, không kết nối"
        );
        assert_eq!(t(Lang::Vi, Str::NeedsPairing), "Cần xin quyền truy cập lại");
        assert_eq!(t(Lang::Vi, Str::Connecting), "đang kết nối…");
        assert_eq!(t(Lang::Vi, Str::Offline), "ngoại tuyến");
        assert_eq!(t(Lang::Vi, Str::InputPaused), "Mất kết nối, tạm ngừng nhập");
        assert_eq!(t(Lang::En, Str::NeedsPairing), "Request access again");
    }
}
