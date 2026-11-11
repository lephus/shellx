//! UI strings: they follow the Windows display language (Vietnamese on a
//! Vietnamese Windows, English otherwise); `SHELLX_LANG=en|vi` overrides it.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Lang {
    Vi,
    En,
}

impl Lang {
    /// `env` is `SHELLX_LANG`, `ui_lang_id` the Windows display language
    /// (`os_info::ui_language_id`, a LANGID). A value starting with `vi` or
    /// `en` (trimmed, case-insensitive) wins; anything else leaves it to
    /// Windows, whose primary language 0x2A is Vietnamese and every other (or
    /// an unreadable one) English.
    pub fn from_system(env: Option<&str>, ui_lang_id: Option<u16>) -> Lang {
        if let Some(v) = env {
            let v = v.trim().to_ascii_lowercase();
            if v.starts_with("vi") {
                return Lang::Vi;
            }
            if v.starts_with("en") {
                return Lang::En;
            }
        }
        match ui_lang_id {
            Some(id) if id & 0x3ff == 0x2a => Lang::Vi,
            _ => Lang::En,
        }
    }

    /// The language the relay mails a sign-in code in (`auth.email.begin`'s `locale`).
    pub fn locale(self) -> &'static str {
        match self {
            Lang::Vi => "vi",
            Lang::En => "en",
        }
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
    /// The title bar "+" (and its menu's first item); the sidebar's "+".
    NewWorkspace,
    /// Tooltip of the title bar "+"'s chevron.
    NewWorkspaceOptions,
    /// The "+" menu's second item.
    NewTerminalTab,
    ClosePane,
    SplitRight,
    SplitDown,
    /// Tooltip of the tab bar's terminal button.
    NewTerminal,
    /// Tooltip of a tab's close button.
    CloseTab,
    /// Title bar arrows (`history::FocusHistory`).
    FocusBack,
    FocusForward,
    /// Title bar tooltips.
    ShowHideSidebar,
    ShowNotifications,
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
    PasteTooLarge,
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
    /// Title of the sign-in dialog.
    SignInTitle,
    /// Label over the dialog's email field.
    EmailAddress,
    /// Settings -> Account button that opens the dialog.
    SignInEllipsis,
    /// Under "not signed in" in Settings -> Account.
    SignInSubtitle,
    /// Tooltip of the sidebar footer's "?" button.
    Help,
    /// The help menu's items (the Mac's wording).
    SettingsEllipsis,
    CheckForUpdates,
    Docs,
    GitHub,
    ContinueWithGoogle,
    WaitingForGoogle,
    BrowserHint,
    SwitchToGoogle,
    SwitchToGoogleIntro,
    SwitchEllipsis,
    GoogleFailed,
    GoogleTimedOut,
    GoogleStateMismatch,
    SwitchFromSignedInDevice,
    EmailInUse,
    IdentityInUse,
    BrowserUnavailable,
    RelayUnreachable,
    SignInMethods,
    GoogleAccount,
    AppleId,
    HiddenEmail,
    RemoveMethod,
    DeleteAccount,
    /// The "+" picker and the empty machine list: why no Mac is offered (spec §4.5).
    MacCannotHostYet,
    /// Under `MacCannotHostYet` when the account has no Mac at all.
    SignInOnYourMac,
    /// `failure_sentence` for any code without a sentence of its own.
    ServerProblem,
    RateLimited,
    /// A sign-in route this relay does not have, or has turned off.
    SignInUnavailable,
    /// The sign-in dialog's line under its title: no separate sign-up (spec §4.1).
    FirstSignInCreatesAccount,
    /// Between "Send code" and "Continue with Google".
    OrDivider,
    SendCode,
    /// Placeholder of the dialog's code field.
    CodePlaceholder,
    VerifyCode,
    ResendCode,
    UseDifferentEmail,
    InvalidEmail,
    DisposableEmail,
    InvalidCode,
    CodeExpired,
    EmailSendFailed,
    /// Settings -> Account: the title of an `email` sign-in method.
    EmailCodeMethod,
    /// The sidebar's and Settings' notice after the server ended the session (catalog
    /// `signin.expired`, first sentence).
    SessionExpired,
    /// The notice's button (catalog `signin.expired`, second sentence).
    SignInAgain,
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
        Str::NewWorkspace,
        Str::NewWorkspaceOptions,
        Str::NewTerminalTab,
        Str::ClosePane,
        Str::SplitRight,
        Str::SplitDown,
        Str::NewTerminal,
        Str::CloseTab,
        Str::FocusBack,
        Str::FocusForward,
        Str::ShowHideSidebar,
        Str::ShowNotifications,
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
        Str::PasteTooLarge,
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
        Str::SignInTitle,
        Str::EmailAddress,
        Str::SignInEllipsis,
        Str::SignInSubtitle,
        Str::Help,
        Str::SettingsEllipsis,
        Str::CheckForUpdates,
        Str::Docs,
        Str::GitHub,
        Str::ContinueWithGoogle,
        Str::WaitingForGoogle,
        Str::BrowserHint,
        Str::SwitchToGoogle,
        Str::SwitchToGoogleIntro,
        Str::SwitchEllipsis,
        Str::GoogleFailed,
        Str::GoogleTimedOut,
        Str::GoogleStateMismatch,
        Str::SwitchFromSignedInDevice,
        Str::EmailInUse,
        Str::IdentityInUse,
        Str::BrowserUnavailable,
        Str::RelayUnreachable,
        Str::SignInMethods,
        Str::GoogleAccount,
        Str::AppleId,
        Str::HiddenEmail,
        Str::RemoveMethod,
        Str::DeleteAccount,
        Str::MacCannotHostYet,
        Str::SignInOnYourMac,
        Str::ServerProblem,
        Str::RateLimited,
        Str::SignInUnavailable,
        Str::FirstSignInCreatesAccount,
        Str::OrDivider,
        Str::SendCode,
        Str::CodePlaceholder,
        Str::VerifyCode,
        Str::ResendCode,
        Str::UseDifferentEmail,
        Str::InvalidEmail,
        Str::DisposableEmail,
        Str::InvalidCode,
        Str::CodeExpired,
        Str::EmailSendFailed,
        Str::EmailCodeMethod,
        Str::SessionExpired,
        Str::SignInAgain,
    ];
}

/// Looks up a UI string. One exhaustive `match` per language: a missing key fails to compile.
pub fn t(lang: Lang, key: Str) -> &'static str {
    match lang {
        Lang::Vi => match key {
            Str::AppName => "ShellX",
            Str::MachinesHeader => "Máy của bạn",
            Str::ThisMachine => "máy này",
            Str::Offline => "ngoại tuyến",
            Str::Online => "trực tuyến",
            Str::Connecting => "đang kết nối…",
            Str::Reconnecting => "đang kết nối lại…",
            Str::SearchPlaceholder => "Tìm phiên, máy, lệnh…",
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
            Str::Cancel => "Hủy",
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
            Str::NewWorkspace => "Phiên mới",
            Str::NewWorkspaceOptions => "Tùy chọn phiên mới",
            Str::NewTerminalTab => "Tab mới (terminal)",
            Str::ClosePane => "Đóng khung",
            Str::SplitRight => "Chia sang phải",
            Str::SplitDown => "Chia xuống dưới",
            Str::NewTerminal => "Terminal mới",
            Str::CloseTab => "Đóng tab",
            Str::FocusBack => "Tiêu điểm trước",
            Str::FocusForward => "Tiêu điểm sau",
            Str::ShowHideSidebar => "Hiện hoặc ẩn thanh bên",
            Str::ShowNotifications => "Hiện thông báo",
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
            Str::PasteTooLarge => "Nội dung dán quá lớn (tối đa 8 MB)",
            Str::NoTerminalOnMachine => "Máy này chưa có phiên nào",
            Str::Error => "Lỗi",
            Str::Account => "Tài khoản",
            Str::Updates => "Cập nhật",
            Str::Language => "Ngôn ngữ",
            Str::LanguageHint => "Theo ngôn ngữ hiển thị của Windows",
            Str::LanguageName => "Tiếng Việt",
            Str::CheckUpdate => "Kiểm tra cập nhật",
            Str::Checking => "Đang kiểm tra…",
            Str::SignedIn => "Đã đăng nhập",
            Str::Close => "Đóng",
            Str::FontCredits => "JetBrains Mono, Space Grotesk, Google Sans — SIL OFL 1.1",
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
            Str::SignInTitle => "Đăng nhập ShellX",
            Str::EmailAddress => "Địa chỉ email",
            Str::SignInEllipsis => "Đăng nhập…",
            Str::SignInSubtitle => "Đăng nhập bằng tài khoản ShellX của bạn.",
            Str::Help => "Trợ giúp",
            Str::SettingsEllipsis => "Cài đặt…",
            Str::CheckForUpdates => "Kiểm tra cập nhật",
            Str::Docs => "Tài liệu",
            Str::GitHub => "GitHub",
            Str::ContinueWithGoogle => "Tiếp tục với Google",
            Str::WaitingForGoogle => "Đang chờ Google…",
            Str::BrowserHint => "Hãy hoàn tất đăng nhập trong trình duyệt rồi quay lại đây.",
            Str::SwitchToGoogle => "Chuyển sang đăng nhập Google",
            Str::SwitchToGoogleIntro => {
                "ShellX giờ đăng nhập bằng Google. Chuyển sang Google vẫn giữ máy tính này, điện thoại và các liên kết chia sẻ của bạn."
            }
            Str::SwitchEllipsis => "Chuyển…",
            Str::GoogleFailed => "Đăng nhập Google không thành công. Hãy thử lại.",
            Str::GoogleTimedOut => "Đăng nhập Google đã hết thời gian chờ. Hãy thử lại.",
            Str::GoogleStateMismatch => "Đăng nhập chưa hoàn tất. Hãy thử lại.",
            Str::SwitchFromSignedInDevice => {
                "Email này đã có tài khoản ShellX. Mở ShellX trên một máy đang đăng nhập, vào Cài đặt › Tài khoản › Chuyển sang đăng nhập Google, rồi thử lại."
            }
            Str::EmailInUse => {
                "Email của tài khoản Google này đã thuộc một tài khoản ShellX khác. Hãy chọn tài khoản Google khác."
            }
            Str::IdentityInUse => {
                "Tài khoản Google này đã dùng để đăng nhập một tài khoản ShellX khác, hoặc tài khoản này đã dùng một tài khoản Google khác."
            }
            Str::BrowserUnavailable => "Không mở được trình duyệt.",
            Str::RelayUnreachable => "Không kết nối được relay.shellx.pro",
            Str::SignInMethods => "Cách đăng nhập",
            Str::GoogleAccount => "Tài khoản Google",
            Str::AppleId => "ID Apple",
            Str::HiddenEmail => "Email ẩn",
            Str::RemoveMethod => "Gỡ",
            Str::DeleteAccount => "Xóa tài khoản…",
            Str::MacCannotHostYet => {
                "ShellX cho Mac hiện chưa nhận kết nối từ máy tính Windows. Terminal trên máy này vẫn dùng bình thường."
            }
            Str::SignInOnYourMac => {
                "Đăng nhập ShellX trên Mac bằng cùng tài khoản để thấy Mac ở đây."
            }
            Str::ServerProblem => "ShellX đang gặp sự cố. Thử lại sau.",
            Str::RateLimited => "Thử lại sau ít phút.",
            Str::SignInUnavailable => "Bản này chưa dùng được cách đăng nhập này.",
            Str::FirstSignInCreatesAccount => {
                "Chưa có tài khoản? Lần đăng nhập đầu tiên sẽ tạo tài khoản cho bạn."
            }
            Str::OrDivider => "hoặc",
            Str::SendCode => "Gửi mã",
            Str::CodePlaceholder => "Mã 6 chữ số",
            Str::VerifyCode => "Xác nhận",
            Str::ResendCode => "Gửi lại mã",
            Str::UseDifferentEmail => "Dùng email khác",
            Str::InvalidEmail => "Địa chỉ email này chưa đúng.",
            Str::DisposableEmail => {
                "Không dùng được địa chỉ email tạm thời. Hãy dùng địa chỉ khác."
            }
            Str::InvalidCode => "Mã chưa đúng. Xem lại email rồi thử lại.",
            Str::CodeExpired => "Mã này không còn dùng được. Hãy gửi mã mới.",
            Str::EmailSendFailed => "Chưa gửi được email. Thử lại sau giây lát.",
            Str::EmailCodeMethod => "Mã qua email",
            Str::SessionExpired => "Phiên đăng nhập đã hết hạn.",
            Str::SignInAgain => "Đăng nhập lại",
        },
        Lang::En => match key {
            Str::AppName => "ShellX",
            Str::MachinesHeader => "YOUR MACHINES",
            Str::ThisMachine => "this PC",
            Str::Offline => "offline",
            Str::Online => "online",
            Str::Connecting => "connecting…",
            Str::Reconnecting => "reconnecting…",
            Str::SearchPlaceholder => "Search sessions, machines, commands…",
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
            Str::NewWorkspace => "New Workspace",
            Str::NewWorkspaceOptions => "New workspace options",
            Str::NewTerminalTab => "New Tab (Terminal)",
            Str::ClosePane => "Close pane",
            Str::SplitRight => "Split right",
            Str::SplitDown => "Split down",
            Str::NewTerminal => "New Terminal",
            Str::CloseTab => "Close Tab",
            Str::FocusBack => "Focus Back",
            Str::FocusForward => "Focus Forward",
            Str::ShowHideSidebar => "Show or hide the sidebar",
            Str::ShowNotifications => "Show notifications",
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
            Str::PasteTooLarge => "Paste too large (8 MB max)",
            Str::NoTerminalOnMachine => "No sessions on this machine",
            Str::Error => "Error",
            Str::Account => "Account",
            Str::Updates => "Updates",
            Str::Language => "Language",
            Str::LanguageHint => "Follows the Windows display language",
            Str::LanguageName => "English",
            Str::CheckUpdate => "Check for updates",
            Str::Checking => "Checking…",
            Str::SignedIn => "Signed in",
            Str::Close => "Close",
            Str::FontCredits => "JetBrains Mono, Space Grotesk, Google Sans — SIL OFL 1.1",
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
            Str::SignInTitle => "Sign in to ShellX",
            Str::EmailAddress => "Email address",
            Str::SignInEllipsis => "Sign In…",
            Str::SignInSubtitle => "Sign in with your ShellX account.",
            Str::Help => "Help",
            Str::SettingsEllipsis => "Settings…",
            Str::CheckForUpdates => "Check for Updates",
            Str::Docs => "Docs",
            Str::GitHub => "GitHub",
            Str::ContinueWithGoogle => "Continue with Google",
            Str::WaitingForGoogle => "Waiting for Google…",
            Str::BrowserHint => "Finish signing in in your browser, then come back here.",
            Str::SwitchToGoogle => "Switch to Google sign-in",
            Str::SwitchToGoogleIntro => {
                "ShellX now signs in with Google. Switching keeps this computer, your phones and your share links."
            }
            Str::SwitchEllipsis => "Switch…",
            Str::GoogleFailed => "Google sign-in didn't work. Try again.",
            Str::GoogleTimedOut => "Google sign-in timed out. Try again.",
            Str::GoogleStateMismatch => "Sign-in didn't finish. Try again.",
            Str::SwitchFromSignedInDevice => {
                "This email already has a ShellX account. Open ShellX on a device that is still signed in, go to Settings › Account › Switch to Google sign-in, then try again."
            }
            Str::EmailInUse => {
                "Another ShellX account already uses this Google account's email. Choose a different Google account."
            }
            Str::IdentityInUse => {
                "This Google account already signs in to another ShellX account, or this account already uses another Google account."
            }
            Str::BrowserUnavailable => "Couldn't open your browser.",
            Str::RelayUnreachable => "Can't reach relay.shellx.pro",
            Str::SignInMethods => "Sign-in methods",
            Str::GoogleAccount => "Google account",
            Str::AppleId => "Apple ID",
            Str::HiddenEmail => "Hidden email",
            Str::RemoveMethod => "Remove",
            Str::DeleteAccount => "Delete Account…",
            Str::MacCannotHostYet => {
                "ShellX for Mac doesn't accept connections from Windows PCs yet. Terminals on this PC work as usual."
            }
            Str::SignInOnYourMac => {
                "Sign in to ShellX on your Mac with the same account to see it here."
            }
            Str::ServerProblem => "ShellX is having a problem. Try again later.",
            Str::RateLimited => "Try again in a few minutes.",
            Str::SignInUnavailable => "This way of signing in isn't available in this build.",
            Str::FirstSignInCreatesAccount => "No account yet? Your first sign-in creates one.",
            Str::OrDivider => "or",
            Str::SendCode => "Send code",
            Str::CodePlaceholder => "6-digit code",
            Str::VerifyCode => "Verify",
            Str::ResendCode => "Resend code",
            Str::UseDifferentEmail => "Use a different email",
            Str::InvalidEmail => "That doesn't look like an email address.",
            Str::DisposableEmail => "Temporary email addresses can't be used. Try another address.",
            Str::InvalidCode => "That code isn't right. Check the email and try again.",
            Str::CodeExpired => "That code no longer works. Send a new one.",
            Str::EmailSendFailed => "Couldn't send the email. Try again in a moment.",
            Str::EmailCodeMethod => "Email code",
            Str::SessionExpired => "Your session expired.",
            Str::SignInAgain => "Sign in again",
        },
    }
}

/// "Thêm từ <thiết bị>" / "Added from <device>" (an Apple ID a phone linked).
pub fn added_from(lang: Lang, device: &str) -> String {
    match lang {
        Lang::Vi => format!("Thêm từ {device}"),
        Lang::En => format!("Added from {device}"),
    }
}

/// Settings -> Account, sign-in methods list or removal failed: "Sign-in methods: something went wrong (code)".
pub fn sign_in_methods_error(lang: Lang, code: &str) -> String {
    match lang {
        Lang::Vi => format!("{}: có lỗi xảy ra ({code})", t(lang, Str::SignInMethods)),
        Lang::En => format!(
            "{}: something went wrong ({code})",
            t(lang, Str::SignInMethods)
        ),
    }
}

/// The sentence for a failed account, sign-in or pairing call, never the code: a relay without the
/// route (or with it turned off) reads as "not available in this build", anything unknown as "ShellX is
/// having a problem" (spec §4.1).
pub fn failure_sentence(lang: Lang, code: &str) -> String {
    let key = match code {
        "network" => Str::RelayUnreachable,
        "rate_limited" => Str::RateLimited,
        "not_found"
        | "http_404"
        | "not_configured"
        | "email_sign_in_disabled"
        | "password_sign_in_removed" => Str::SignInUnavailable,
        "switch_from_signed_in_device" => Str::SwitchFromSignedInDevice,
        _ => Str::ServerProblem,
    };
    t(lang, key).to_string()
}

/// The sign-in dialog's error line for a Google flow failure. `None` for `google_cancelled`
/// (the person closed it); any code without a Google sentence reads as `failure_sentence(code)`.
pub fn google_error(lang: Lang, code: &str) -> Option<String> {
    let key = match code {
        "google_cancelled" => return None,
        "invalid_credentials" => Str::GoogleFailed,
        "network" => Str::RelayUnreachable,
        "google_timeout" => Str::GoogleTimedOut,
        "google_state_mismatch" => Str::GoogleStateMismatch,
        "switch_from_signed_in_device" => Str::SwitchFromSignedInDevice,
        "email_in_use" => Str::EmailInUse,
        "identity_in_use" => Str::IdentityInUse,
        "browser_unavailable" => Str::BrowserUnavailable,
        other => return Some(failure_sentence(lang, other)),
    };
    Some(t(lang, key).to_string())
}

/// The sign-in dialog's line after a code was mailed (the phone catalog's `signin.email.sentTo`).
pub fn sent_code_to(lang: Lang, email: &str) -> String {
    match lang {
        Lang::Vi => format!(
            "Đã gửi mã 6 chữ số tới {email}. Nếu sau một phút chưa thấy, hãy xem cả thư rác."
        ),
        Lang::En => format!(
            "We sent a 6-digit code to {email}. If it isn't there in a minute, check your spam folder."
        ),
    }
}

/// The locked "Resend code" button: "Resend code in 42 s" / "Gửi lại mã sau 42 giây" (whole seconds).
pub fn resend_code_in(lang: Lang, secs: u64) -> String {
    match lang {
        Lang::Vi => format!("Gửi lại mã sau {secs} giây"),
        Lang::En => format!("Resend code in {secs} s"),
    }
}

/// The dialog's line for an email-path failure (D2): the eight email sentences, `network` as
/// `RelayUnreachable`, anything else (`http_<status>`, `server`, `invalid_device`, `not_configured`, …)
/// as `ServerProblem`. Never the code.
pub fn email_error(lang: Lang, code: &str) -> String {
    let key = match code {
        "invalid_email" => Str::InvalidEmail,
        "disposable_email" => Str::DisposableEmail,
        "invalid_code" => Str::InvalidCode,
        "code_expired" => Str::CodeExpired,
        "email_send_failed" => Str::EmailSendFailed,
        "email_sign_in_disabled" => Str::SignInUnavailable,
        "rate_limited" => Str::RateLimited,
        "switch_from_signed_in_device" => Str::SwitchFromSignedInDevice,
        "network" => Str::RelayUnreachable,
        _ => Str::ServerProblem,
    };
    t(lang, key).to_string()
}

/// Settings -> Account: the title of a sign-in method by its provider.
pub fn sign_in_method_label(provider: &str) -> Str {
    match provider {
        "apple" => Str::AppleId,
        "email" => Str::EmailCodeMethod,
        _ => Str::GoogleAccount,
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

/// The sidebar footer's pill: "Có bản cập nhật: 1.5.4" / "Update Available: 1.5.4".
pub fn update_available_pill(lang: Lang, version: &str) -> String {
    match lang {
        Lang::Vi => format!("Có bản cập nhật: {version}"),
        Lang::En => format!("Update Available: {version}"),
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
        assert_eq!(Str::ALL.len(), 129);
    }

    #[test]
    fn sign_in_again_strings() {
        assert_eq!(t(Lang::En, Str::SessionExpired), "Your session expired.");
        assert_eq!(
            t(Lang::Vi, Str::SessionExpired),
            "Phiên đăng nhập đã hết hạn."
        );
        assert_eq!(t(Lang::En, Str::SignInAgain), "Sign in again");
        assert_eq!(t(Lang::Vi, Str::SignInAgain), "Đăng nhập lại");
    }

    #[test]
    fn the_first_sign_in_line() {
        assert_eq!(
            t(Lang::En, Str::FirstSignInCreatesAccount),
            "No account yet? Your first sign-in creates one."
        );
        assert_eq!(
            t(Lang::Vi, Str::FirstSignInCreatesAccount),
            "Chưa có tài khoản? Lần đăng nhập đầu tiên sẽ tạo tài khoản cho bạn."
        );
    }

    /// D5: every email string is the phone catalog's (`shellx-ios/ShellX/Localizable.xcstrings`).
    #[test]
    fn email_strings_match_the_phone_catalog() {
        let pairs = [
            (Str::OrDivider, "hoặc", "or"),
            (Str::SendCode, "Gửi mã", "Send code"),
            (Str::CodePlaceholder, "Mã 6 chữ số", "6-digit code"),
            (Str::VerifyCode, "Xác nhận", "Verify"),
            (Str::ResendCode, "Gửi lại mã", "Resend code"),
            (
                Str::UseDifferentEmail,
                "Dùng email khác",
                "Use a different email",
            ),
            (
                Str::InvalidEmail,
                "Địa chỉ email này chưa đúng.",
                "That doesn't look like an email address.",
            ),
            (
                Str::DisposableEmail,
                "Không dùng được địa chỉ email tạm thời. Hãy dùng địa chỉ khác.",
                "Temporary email addresses can't be used. Try another address.",
            ),
            (
                Str::InvalidCode,
                "Mã chưa đúng. Xem lại email rồi thử lại.",
                "That code isn't right. Check the email and try again.",
            ),
            (
                Str::CodeExpired,
                "Mã này không còn dùng được. Hãy gửi mã mới.",
                "That code no longer works. Send a new one.",
            ),
            (
                Str::EmailSendFailed,
                "Chưa gửi được email. Thử lại sau giây lát.",
                "Couldn't send the email. Try again in a moment.",
            ),
            (
                Str::SignInUnavailable,
                "Bản này chưa dùng được cách đăng nhập này.",
                "This way of signing in isn't available in this build.",
            ),
            (
                Str::RateLimited,
                "Thử lại sau ít phút.",
                "Try again in a few minutes.",
            ),
            (
                Str::ServerProblem,
                "ShellX đang gặp sự cố. Thử lại sau.",
                "ShellX is having a problem. Try again later.",
            ),
            (Str::EmailCodeMethod, "Mã qua email", "Email code"),
        ];
        assert_eq!(pairs.len(), 15);
        for (key, vi, en) in pairs {
            assert_eq!(t(Lang::Vi, key), vi, "{key:?}");
            assert_eq!(t(Lang::En, key), en, "{key:?}");
        }
        assert_eq!(
            sent_code_to(Lang::En, "foo@bar.com"),
            "We sent a 6-digit code to foo@bar.com. If it isn't there in a minute, check your spam folder."
        );
        assert_eq!(
            sent_code_to(Lang::Vi, "foo@bar.com"),
            "Đã gửi mã 6 chữ số tới foo@bar.com. Nếu sau một phút chưa thấy, hãy xem cả thư rác."
        );
        assert_eq!(resend_code_in(Lang::En, 42), "Resend code in 42 s");
        assert_eq!(resend_code_in(Lang::Vi, 60), "Gửi lại mã sau 60 giây");
        assert_eq!((Lang::Vi.locale(), Lang::En.locale()), ("vi", "en"));
    }

    #[test]
    fn email_error_maps_codes() {
        for lang in [Lang::Vi, Lang::En] {
            let own = [
                ("invalid_email", Str::InvalidEmail),
                ("disposable_email", Str::DisposableEmail),
                ("invalid_code", Str::InvalidCode),
                ("code_expired", Str::CodeExpired),
                ("email_send_failed", Str::EmailSendFailed),
                ("email_sign_in_disabled", Str::SignInUnavailable),
                ("rate_limited", Str::RateLimited),
                ("network", Str::RelayUnreachable),
                (
                    "switch_from_signed_in_device",
                    Str::SwitchFromSignedInDevice,
                ),
            ];
            for (code, key) in own {
                assert_eq!(email_error(lang, code), t(lang, key), "{lang:?} {code}");
            }
            for code in [
                "http_502",
                "http_503",
                "http_504",
                "server",
                "invalid_device",
                "invalid_params",
                "bad_request",
                "internal_error",
                "payload_too_large",
                "not_configured",
                "io",
                "crypto",
                "unknown_method",
                "",
            ] {
                assert_eq!(
                    email_error(lang, code),
                    t(lang, Str::ServerProblem),
                    "{lang:?} {code:?}"
                );
            }
            for code in own
                .iter()
                .map(|(c, _)| *c)
                .chain(["http_502", "invalid_device", "io"])
            {
                let out = email_error(lang, code);
                assert!(
                    !out.contains("http_") && !out.contains('_'),
                    "{code}: {out}"
                );
            }
        }
    }

    #[test]
    fn sign_in_method_labels_follow_the_provider() {
        assert_eq!(sign_in_method_label("apple"), Str::AppleId);
        assert_eq!(sign_in_method_label("email"), Str::EmailCodeMethod);
        assert_eq!(sign_in_method_label("google"), Str::GoogleAccount);
        assert_eq!(sign_in_method_label("test"), Str::GoogleAccount);
    }

    #[test]
    fn failure_sentence_wording() {
        let pairs = [
            (
                Str::ServerProblem,
                "ShellX đang gặp sự cố. Thử lại sau.",
                "ShellX is having a problem. Try again later.",
            ),
            (
                Str::RateLimited,
                "Thử lại sau ít phút.",
                "Try again in a few minutes.",
            ),
            (
                Str::SignInUnavailable,
                "Bản này chưa dùng được cách đăng nhập này.",
                "This way of signing in isn't available in this build.",
            ),
        ];
        for (key, vi, en) in pairs {
            assert_eq!(t(Lang::Vi, key), vi, "{key:?}");
            assert_eq!(t(Lang::En, key), en, "{key:?}");
        }
    }

    #[test]
    fn failure_sentences_never_show_codes() {
        for lang in [Lang::Vi, Lang::En] {
            let cases: &[(&[&str], Str)] = &[
                (&["network"], Str::RelayUnreachable),
                (&["rate_limited"], Str::RateLimited),
                (
                    &[
                        "not_found",
                        "http_404",
                        "not_configured",
                        "email_sign_in_disabled",
                        "password_sign_in_removed",
                    ],
                    Str::SignInUnavailable,
                ),
                (
                    &["switch_from_signed_in_device"],
                    Str::SwitchFromSignedInDevice,
                ),
                // Review M2: the server refused the session.
                (&["unauthorized", "http_401"], Str::SessionExpired),
                (
                    &[
                        "bad_response",
                        "server",
                        "http_502",
                        "io",
                        "invalid_machine",
                        "",
                    ],
                    Str::ServerProblem,
                ),
            ];
            for (codes, key) in cases {
                for code in *codes {
                    let out = failure_sentence(lang, code);
                    assert_eq!(out, t(lang, *key), "{lang:?} {code}");
                    assert!(!out.contains('_') && !out.contains("http"), "{code}: {out}");
                }
            }
        }
    }

    #[test]
    fn machine_list_sentences_say_why_no_mac_is_offered() {
        let pairs = [
            (
                Str::MacCannotHostYet,
                "ShellX cho Mac hiện chưa nhận kết nối từ máy tính Windows. Terminal trên máy này vẫn dùng bình thường.",
                "ShellX for Mac doesn't accept connections from Windows PCs yet. Terminals on this PC work as usual.",
            ),
            (
                Str::SignInOnYourMac,
                "Đăng nhập ShellX trên Mac bằng cùng tài khoản để thấy Mac ở đây.",
                "Sign in to ShellX on your Mac with the same account to see it here.",
            ),
        ];
        for (key, vi, en) in pairs {
            assert_eq!(t(Lang::Vi, key), vi, "{key:?}");
            assert_eq!(t(Lang::En, key), en, "{key:?}");
        }
    }

    #[test]
    fn exact_vi_strings() {
        assert_eq!(t(Lang::Vi, Str::MachinesHeader), "Máy của bạn");
        assert_eq!(t(Lang::Vi, Str::Reconnecting), "đang kết nối lại…");
        assert_eq!(t(Lang::Vi, Str::StatusWaiting), "chờ bạn");
        assert_eq!(t(Lang::Vi, Str::StatusRunning), "chạy");
        assert_eq!(t(Lang::Vi, Str::StatusDone), "xong");
        assert_eq!(t(Lang::Vi, Str::StatusError), "lỗi");
        assert_eq!(t(Lang::En, Str::MachinesHeader), "YOUR MACHINES");
        assert_eq!(t(Lang::En, Str::StatusWaiting), "waiting");
        assert_eq!(t(Lang::En, Str::ThisMachine), "this PC");
        assert_eq!(t(Lang::Vi, Str::ThisMachine), "máy này");
        assert_eq!(t(Lang::Vi, Str::SearchPlaceholder), "Tìm phiên, máy, lệnh…");
        assert_eq!(
            t(Lang::En, Str::SearchPlaceholder),
            "Search sessions, machines, commands…"
        );
        assert_eq!(
            t(Lang::Vi, Str::LanguageHint),
            "Theo ngôn ngữ hiển thị của Windows"
        );
        assert_eq!(
            t(Lang::En, Str::LanguageHint),
            "Follows the Windows display language"
        );
        assert_eq!(t(Lang::Vi, Str::IconCredits), t(Lang::En, Str::IconCredits));
        assert_eq!(
            t(Lang::Vi, Str::ShellExitsAtStart),
            "Shell thoát ngay khi khởi động. Kiểm tra SHELLX_SHELL."
        );
        assert_eq!(t(Lang::Vi, Str::Retry), "Thử lại");
    }

    #[test]
    fn tab_bar_strings_match_the_mac() {
        assert_eq!(t(Lang::Vi, Str::NewTerminal), "Terminal mới");
        assert_eq!(t(Lang::En, Str::NewTerminal), "New Terminal");
        assert_eq!(t(Lang::Vi, Str::CloseTab), "Đóng tab");
        assert_eq!(t(Lang::En, Str::CloseTab), "Close Tab");
    }

    #[test]
    fn title_bar_strings_match_the_mac() {
        let pairs = [
            (Str::NewWorkspace, "Phiên mới", "New Workspace"),
            (
                Str::NewWorkspaceOptions,
                "Tùy chọn phiên mới",
                "New workspace options",
            ),
            (
                Str::NewTerminalTab,
                "Tab mới (terminal)",
                "New Tab (Terminal)",
            ),
            (Str::FocusBack, "Tiêu điểm trước", "Focus Back"),
            (Str::FocusForward, "Tiêu điểm sau", "Focus Forward"),
            (
                Str::ShowHideSidebar,
                "Hiện hoặc ẩn thanh bên",
                "Show or hide the sidebar",
            ),
            (
                Str::ShowNotifications,
                "Hiện thông báo",
                "Show notifications",
            ),
        ];
        for (key, vi, en) in pairs {
            assert_eq!(t(Lang::Vi, key), vi, "{key:?}");
            assert_eq!(t(Lang::En, key), en, "{key:?}");
        }
    }

    #[test]
    fn sign_in_strings_match_the_mac() {
        assert_eq!(t(Lang::Vi, Str::SignInTitle), "Đăng nhập ShellX");
        assert_eq!(t(Lang::En, Str::SignInTitle), "Sign in to ShellX");
        assert_eq!(t(Lang::Vi, Str::EmailAddress), "Địa chỉ email");
        assert_eq!(t(Lang::En, Str::EmailAddress), "Email address");
        assert_eq!(t(Lang::Vi, Str::SignInEllipsis), "Đăng nhập…");
        assert_eq!(t(Lang::En, Str::SignInEllipsis), "Sign In…");
        assert_eq!(
            t(Lang::Vi, Str::SignInSubtitle),
            "Đăng nhập bằng tài khoản ShellX của bạn."
        );
        assert_eq!(
            t(Lang::En, Str::SignInSubtitle),
            "Sign in with your ShellX account."
        );
        assert_eq!(t(Lang::Vi, Str::Cancel), "Hủy");
        assert_eq!(t(Lang::En, Str::Cancel), "Cancel");
        let pairs = [
            (
                Str::ContinueWithGoogle,
                "Tiếp tục với Google",
                "Continue with Google",
            ),
            (
                Str::WaitingForGoogle,
                "Đang chờ Google…",
                "Waiting for Google…",
            ),
            (
                Str::BrowserHint,
                "Hãy hoàn tất đăng nhập trong trình duyệt rồi quay lại đây.",
                "Finish signing in in your browser, then come back here.",
            ),
            (
                Str::SwitchToGoogle,
                "Chuyển sang đăng nhập Google",
                "Switch to Google sign-in",
            ),
            (
                Str::SwitchToGoogleIntro,
                "ShellX giờ đăng nhập bằng Google. Chuyển sang Google vẫn giữ máy tính này, điện thoại và các liên kết chia sẻ của bạn.",
                "ShellX now signs in with Google. Switching keeps this computer, your phones and your share links.",
            ),
            (Str::SwitchEllipsis, "Chuyển…", "Switch…"),
            (
                Str::GoogleFailed,
                "Đăng nhập Google không thành công. Hãy thử lại.",
                "Google sign-in didn't work. Try again.",
            ),
            (
                Str::GoogleTimedOut,
                "Đăng nhập Google đã hết thời gian chờ. Hãy thử lại.",
                "Google sign-in timed out. Try again.",
            ),
            (
                Str::GoogleStateMismatch,
                "Đăng nhập chưa hoàn tất. Hãy thử lại.",
                "Sign-in didn't finish. Try again.",
            ),
            (
                Str::SwitchFromSignedInDevice,
                "Email này đã có tài khoản ShellX. Mở ShellX trên một máy đang đăng nhập, vào Cài đặt › Tài khoản › Chuyển sang đăng nhập Google, rồi thử lại.",
                "This email already has a ShellX account. Open ShellX on a device that is still signed in, go to Settings › Account › Switch to Google sign-in, then try again.",
            ),
            (
                Str::EmailInUse,
                "Email của tài khoản Google này đã thuộc một tài khoản ShellX khác. Hãy chọn tài khoản Google khác.",
                "Another ShellX account already uses this Google account's email. Choose a different Google account.",
            ),
            (
                Str::IdentityInUse,
                "Tài khoản Google này đã dùng để đăng nhập một tài khoản ShellX khác, hoặc tài khoản này đã dùng một tài khoản Google khác.",
                "This Google account already signs in to another ShellX account, or this account already uses another Google account.",
            ),
            (
                Str::BrowserUnavailable,
                "Không mở được trình duyệt.",
                "Couldn't open your browser.",
            ),
            (
                Str::RelayUnreachable,
                "Không kết nối được relay.shellx.pro",
                "Can't reach relay.shellx.pro",
            ),
            (Str::SignInMethods, "Cách đăng nhập", "Sign-in methods"),
            (Str::GoogleAccount, "Tài khoản Google", "Google account"),
            (Str::AppleId, "ID Apple", "Apple ID"),
            (Str::HiddenEmail, "Email ẩn", "Hidden email"),
            (Str::RemoveMethod, "Gỡ", "Remove"),
            (Str::DeleteAccount, "Xóa tài khoản…", "Delete Account…"),
        ];
        assert_eq!(pairs.len(), 20);
        for (key, vi, en) in pairs {
            assert_eq!(t(Lang::Vi, key), vi, "{key:?}");
            assert_eq!(t(Lang::En, key), en, "{key:?}");
        }
        assert_eq!(added_from(Lang::Vi, "Phu's iPhone"), "Thêm từ Phu's iPhone");
        assert_eq!(
            added_from(Lang::En, "Phu's iPhone"),
            "Added from Phu's iPhone"
        );
        assert_eq!(
            sign_in_methods_error(Lang::En, "network"),
            "Sign-in methods: something went wrong (network)"
        );
        assert_eq!(
            sign_in_methods_error(Lang::Vi, "network"),
            "Cách đăng nhập: có lỗi xảy ra (network)"
        );
    }

    #[test]
    fn google_error_maps_codes() {
        for lang in [Lang::Vi, Lang::En] {
            assert_eq!(google_error(lang, "google_cancelled"), None);
            assert_eq!(
                google_error(lang, "switch_from_signed_in_device").as_deref(),
                Some(t(lang, Str::SwitchFromSignedInDevice))
            );
            assert_eq!(
                google_error(lang, "network").as_deref(),
                Some(t(lang, Str::RelayUnreachable))
            );
            assert_eq!(
                google_error(lang, "google_timeout").as_deref(),
                Some(t(lang, Str::GoogleTimedOut))
            );
            assert_eq!(
                google_error(lang, "rate_limited"),
                Some(t(lang, Str::RateLimited).to_string())
            );
            assert_eq!(
                google_error(lang, "not_configured"),
                Some(t(lang, Str::SignInUnavailable).to_string())
            );
            assert_eq!(
                google_error(lang, "bad_response"),
                Some(t(lang, Str::ServerProblem).to_string())
            );
            assert_eq!(
                t(lang, Str::FontCredits),
                "JetBrains Mono, Space Grotesk, Google Sans — SIL OFL 1.1"
            );
        }
    }

    #[test]
    fn sidebar_footer_strings_match_the_mac() {
        let pairs = [
            (Str::Help, "Trợ giúp", "Help"),
            (Str::SettingsEllipsis, "Cài đặt…", "Settings…"),
            (
                Str::CheckForUpdates,
                "Kiểm tra cập nhật",
                "Check for Updates",
            ),
            (Str::Docs, "Tài liệu", "Docs"),
            (Str::GitHub, "GitHub", "GitHub"),
        ];
        for (key, vi, en) in pairs {
            assert_eq!(t(Lang::Vi, key), vi, "{key:?}");
            assert_eq!(t(Lang::En, key), en, "{key:?}");
        }
        assert_eq!(
            update_available_pill(Lang::Vi, "1.5.4"),
            "Có bản cập nhật: 1.5.4"
        );
        assert_eq!(
            update_available_pill(Lang::En, "1.5.4"),
            "Update Available: 1.5.4"
        );
    }

    #[test]
    fn language_follows_windows_unless_overridden() {
        // No override: the Windows display language decides (0x2A = Vietnamese).
        assert_eq!(Lang::from_system(None, Some(0x042A)), Lang::Vi);
        assert_eq!(Lang::from_system(None, Some(0x0409)), Lang::En);
        assert_eq!(Lang::from_system(None, None), Lang::En);
        // SHELLX_LANG starting with en or vi wins either way.
        assert_eq!(Lang::from_system(Some("en"), Some(0x042A)), Lang::En);
        assert_eq!(Lang::from_system(Some("EN-us"), Some(0x042A)), Lang::En);
        assert_eq!(Lang::from_system(Some(" vi "), Some(0x0409)), Lang::Vi);
        assert_eq!(Lang::from_system(Some("vi"), Some(0x0409)), Lang::Vi);
        assert_eq!(Lang::from_system(Some("vi"), None), Lang::Vi);
        // Anything else is ignored.
        assert_eq!(Lang::from_system(Some(""), Some(0x042A)), Lang::Vi);
        assert_eq!(Lang::from_system(Some("fr"), Some(0x0409)), Lang::En);
        assert_eq!(Lang::from_system(Some("fr"), Some(0x042A)), Lang::Vi);
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
        assert_eq!(
            t(Lang::Vi, Str::PasteTooLarge),
            "Nội dung dán quá lớn (tối đa 8 MB)"
        );
        assert_eq!(
            t(Lang::En, Str::PasteTooLarge),
            "Paste too large (8 MB max)"
        );
    }
}
