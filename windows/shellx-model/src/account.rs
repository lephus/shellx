//! Account session state machine: sign-in state, this machine's registration,
//! heartbeat and machine-list refresh. Pure and event driven like
//! `remote_state`: the app runs the returned actions off the UI thread and
//! feeds results back as events. Time is passed in (`now_ms`).
//!
//! The password lives only in `LoginSubmitted` and the `CallLogin` action it
//! produces; the flow never stores it, and `Debug` output redacts it.
//!
//! The app runs the core calls one at a time, in the order the actions were
//! returned, so results arrive in call order. A list result that arrives
//! while the login call is in flight belongs to a list started before the
//! login and is dropped.

use std::fmt;

use crate::core_api::{
    CoreErr, GoogleBegin, GooglePurpose, GoogleSignIn, LoginInfo, Registered, SessionInfo, SignInMethod,
};
use crate::sidebar::MachineInfo;

pub const HEARTBEAT_INTERVAL_MS: u64 = 30_000;
pub const LIST_INTERVAL_MS: u64 = 15_000;
/// Desktop account deletion is a link only.
pub const DELETE_ACCOUNT_URL: &str = "https://shellx.pro/privacy#delete-account";

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum AccountState {
    Unknown,
    LoggedOut,
    LoggingIn,
    LoggedIn { machine_id: String },
    Error(CoreErr),
}

#[derive(Clone, PartialEq)]
pub enum AccountEvent {
    Started,
    ListResult(Result<Vec<MachineInfo>, CoreErr>),
    LoginSubmitted {
        email: String,
        password: String,
    },
    LoginResult(Result<LoginInfo, CoreErr>),
    Registered(Result<Registered, CoreErr>),
    Tick(u64),
    /// Result of `CallHeartbeat`. `machine_not_found` / `not_registered`
    /// (this machine was removed or revoked elsewhere) lists at once and
    /// allows one more `machines.register`; other errors are ignored (a lost
    /// session shows on the next list).
    HeartbeatResult(Result<(), CoreErr>),
    LogoutRequested,
    /// Result of `CallLogout`. A failure keeps the session (LoggedIn) and
    /// sets `notice`; `not_logged_in` counts as signed out.
    LogoutResult(Result<(), CoreErr>),
    /// The logout call succeeded (same as `LogoutResult(Ok(()))`).
    LoggedOut,
    /// "Continue with Google": `SignIn` from signed out, `Link` switches a password session in place.
    GoogleRequested(GooglePurpose),
    /// Result of `CallGoogleBegin`.
    GoogleBegun {
        purpose: GooglePurpose,
        result: Result<GoogleBegin, CoreErr>,
    },
    /// Result of `CallGoogleFinish` (the browser answered, the flow was cancelled or it timed out).
    GoogleFinished {
        flow_id: String,
        result: Result<GoogleSignIn, CoreErr>,
    },
    /// The person closed the dialog while a Google flow runs.
    GoogleCancelRequested,
    /// Result of `CallSession` (`auth.session`, local).
    SessionResult(Result<SessionInfo, CoreErr>),
    SignInMethodsRequested,
    SignInMethodsResult(Result<Vec<SignInMethod>, CoreErr>),
    RemoveSignInMethodRequested(String),
    SignInMethodRemoved {
        identity_id: String,
        result: Result<(), CoreErr>,
    },
}

#[derive(Clone, PartialEq, Eq)]
pub enum AccountAction {
    CallList,
    CallLogin { email: String, password: String },
    CallRegister,
    CallHeartbeat,
    CallLogout,
    ScheduleTick { at_ms: u64 },
    CallGoogleBegin(GooglePurpose),
    /// The window opens this URL in the system browser.
    OpenBrowser(String),
    /// Blocks until the browser answers (up to 300 s): the app runs it on its own task.
    CallGoogleFinish(String),
    CallGoogleCancel(String),
    CallSession,
    CallListSignInMethods,
    CallRemoveSignInMethod(String),
}

impl fmt::Debug for AccountEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AccountEvent::Started => write!(f, "Started"),
            AccountEvent::ListResult(r) => f.debug_tuple("ListResult").field(r).finish(),
            AccountEvent::LoginSubmitted { email, .. } => f
                .debug_struct("LoginSubmitted")
                .field("email", email)
                .field("password", &"<redacted>")
                .finish(),
            AccountEvent::LoginResult(r) => f.debug_tuple("LoginResult").field(r).finish(),
            AccountEvent::Registered(r) => f.debug_tuple("Registered").field(r).finish(),
            AccountEvent::Tick(t) => f.debug_tuple("Tick").field(t).finish(),
            AccountEvent::HeartbeatResult(r) => f.debug_tuple("HeartbeatResult").field(r).finish(),
            AccountEvent::LogoutRequested => write!(f, "LogoutRequested"),
            AccountEvent::LogoutResult(r) => f.debug_tuple("LogoutResult").field(r).finish(),
            AccountEvent::LoggedOut => write!(f, "LoggedOut"),
            AccountEvent::GoogleRequested(p) => f.debug_tuple("GoogleRequested").field(p).finish(),
            AccountEvent::GoogleBegun { purpose, result } => f
                .debug_struct("GoogleBegun")
                .field("purpose", purpose)
                .field("result", result)
                .finish(),
            AccountEvent::GoogleFinished { flow_id, result } => f
                .debug_struct("GoogleFinished")
                .field("flow_id", flow_id)
                .field("result", result)
                .finish(),
            AccountEvent::GoogleCancelRequested => write!(f, "GoogleCancelRequested"),
            AccountEvent::SessionResult(r) => f.debug_tuple("SessionResult").field(r).finish(),
            AccountEvent::SignInMethodsRequested => write!(f, "SignInMethodsRequested"),
            AccountEvent::SignInMethodsResult(r) => {
                f.debug_tuple("SignInMethodsResult").field(&r.as_ref().map(Vec::len)).finish()
            }
            AccountEvent::RemoveSignInMethodRequested(id) => {
                f.debug_tuple("RemoveSignInMethodRequested").field(id).finish()
            }
            AccountEvent::SignInMethodRemoved { identity_id, result } => f
                .debug_struct("SignInMethodRemoved")
                .field("identity_id", identity_id)
                .field("result", result)
                .finish(),
        }
    }
}

impl fmt::Debug for AccountAction {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AccountAction::CallList => write!(f, "CallList"),
            AccountAction::CallLogin { email, .. } => f
                .debug_struct("CallLogin")
                .field("email", email)
                .field("password", &"<redacted>")
                .finish(),
            AccountAction::CallRegister => write!(f, "CallRegister"),
            AccountAction::CallHeartbeat => write!(f, "CallHeartbeat"),
            AccountAction::CallLogout => write!(f, "CallLogout"),
            AccountAction::ScheduleTick { at_ms } => f
                .debug_struct("ScheduleTick")
                .field("at_ms", at_ms)
                .finish(),
            AccountAction::CallGoogleBegin(p) => f.debug_tuple("CallGoogleBegin").field(p).finish(),
            AccountAction::OpenBrowser(_) => f.debug_tuple("OpenBrowser").field(&"<auth url>").finish(),
            AccountAction::CallGoogleFinish(id) => f.debug_tuple("CallGoogleFinish").field(id).finish(),
            AccountAction::CallGoogleCancel(id) => f.debug_tuple("CallGoogleCancel").field(id).finish(),
            AccountAction::CallSession => write!(f, "CallSession"),
            AccountAction::CallListSignInMethods => write!(f, "CallListSignInMethods"),
            AccountAction::CallRemoveSignInMethod(id) => {
                f.debug_tuple("CallRemoveSignInMethod").field(id).finish()
            }
        }
    }
}

/// A Google flow the person started and has not seen end yet.
#[derive(Debug)]
struct GoogleRun {
    purpose: GooglePurpose,
    /// Known once `auth.google.begin` answered.
    flow_id: Option<String>,
}

#[derive(Debug)]
pub struct AccountFlow {
    state: AccountState,
    /// Last good machine list; kept across network errors.
    machines: Vec<MachineInfo>,
    /// `machines.register` already requested since the last time this machine
    /// was in the list; reset when it fails, on every list that has this
    /// machine, on login/logout and when a heartbeat says the machine is gone.
    register_requested: bool,
    list_in_flight: bool,
    login_in_flight: bool,
    logout_in_flight: bool,
    /// Last error that did not change the state (a failed logout).
    notice: Option<CoreErr>,
    last_list_ms: u64,
    last_heartbeat_ms: u64,
    /// A failed list outside LoggedIn is retried on the next tick.
    retry_list: bool,
    /// Tick the app has been asked to deliver and has not delivered yet.
    tick_pending: Option<u64>,
    google: Option<GoogleRun>,
    /// `auth.google.begin` calls dropped by a cancel whose answers have not arrived yet.
    stale_begins: u32,
    email: Option<String>,
    auth_method: Option<String>,
    /// `auth.session` already asked for this session.
    session_requested: bool,
    signed_out_by_server: bool,
    methods: Option<Vec<SignInMethod>>,
    removing: Option<String>,
}

impl Default for AccountFlow {
    fn default() -> Self {
        AccountFlow::new()
    }
}

impl AccountFlow {
    pub fn new() -> AccountFlow {
        AccountFlow {
            state: AccountState::Unknown,
            machines: Vec::new(),
            register_requested: false,
            list_in_flight: false,
            login_in_flight: false,
            logout_in_flight: false,
            notice: None,
            last_list_ms: 0,
            last_heartbeat_ms: 0,
            retry_list: false,
            tick_pending: None,
            google: None,
            stale_begins: 0,
            email: None,
            auth_method: None,
            session_requested: false,
            signed_out_by_server: false,
            methods: None,
            removing: None,
        }
    }

    pub fn state(&self) -> &AccountState {
        &self.state
    }

    /// The last machine list the server returned (empty when logged out).
    pub fn machines(&self) -> &[MachineInfo] {
        &self.machines
    }

    /// An error that left the state as it was (a failed logout keeps the
    /// session). Cleared by the next login or logout attempt.
    pub fn notice(&self) -> Option<&CoreErr> {
        self.notice.as_ref()
    }

    /// Whether `LoginSubmitted` would start a login now. Not while a login
    /// runs or this machine is being registered (`LoggingIn`): the flow
    /// ignores the event then, and the panel keeps the typed password.
    pub fn accepts_login(&self) -> bool {
        self.state != AccountState::LoggingIn
    }

    /// The login call is running (the panel shows "signing in").
    pub fn login_in_flight(&self) -> bool {
        self.login_in_flight
    }

    /// The Google flow the person started and has not seen end, if any.
    pub fn google_in_flight(&self) -> Option<GooglePurpose> {
        self.google.as_ref().map(|g| g.purpose)
    }

    /// The account email (from Google sign-in or `auth.session`); `None` until known.
    pub fn email(&self) -> Option<&str> {
        self.email.as_deref()
    }

    /// `"google"`, `"password"`, ...; `None` until known.
    pub fn auth_method(&self) -> Option<&str> {
        self.auth_method.as_deref()
    }

    /// Signed in with a password: Settings offers the switch to Google.
    pub fn needs_google_switch(&self) -> bool {
        matches!(self.state, AccountState::LoggedIn { .. }) && self.auth_method.as_deref() == Some("password")
    }

    pub fn sign_in_methods(&self) -> Option<&[SignInMethod]> {
        self.methods.as_deref()
    }

    pub fn removing_sign_in_method(&self) -> Option<&str> {
        self.removing.as_deref()
    }

    /// True once after the server ended the session (the app shows sign-in).
    pub fn take_signed_out_by_server(&mut self) -> bool {
        std::mem::take(&mut self.signed_out_by_server)
    }

    fn logged_in(&self) -> bool {
        matches!(self.state, AccountState::LoggedIn { .. })
    }

    /// A Google flow ended without a session: `SignIn` shows the error (a cancel returns to signed
    /// out); `Link` keeps the session and sets the notice (a cancel sets nothing).
    fn end_google(&mut self, purpose: GooglePurpose, result: Result<(), CoreErr>) {
        self.google = None;
        let Err(e) = result else { return };
        let cancelled = e.code == "google_cancelled";
        match purpose {
            GooglePurpose::SignIn => {
                self.login_in_flight = false;
                self.state = if cancelled { AccountState::LoggedOut } else { AccountState::Error(e) };
            }
            GooglePurpose::Link => {
                if !cancelled {
                    self.notice = Some(e);
                }
            }
        }
    }

    fn arm(&mut self, at_ms: u64, now_ms: u64, out: &mut Vec<AccountAction>) {
        if self.tick_pending.is_some_and(|p| p > now_ms) {
            return;
        }
        self.tick_pending = Some(at_ms);
        out.push(AccountAction::ScheduleTick { at_ms });
    }

    fn reset_session(&mut self) {
        self.machines.clear();
        self.register_requested = false;
        self.list_in_flight = false;
        self.logout_in_flight = false;
        self.retry_list = false;
        self.notice = None;
        self.google = None;
        self.email = None;
        self.auth_method = None;
        self.session_requested = false;
        self.methods = None;
        self.removing = None;
    }

    pub fn on(&mut self, ev: AccountEvent, now_ms: u64) -> Vec<AccountAction> {
        let mut out = Vec::new();
        match ev {
            AccountEvent::Started => {
                if self.list_in_flight {
                    return out;
                }
                self.list_in_flight = true;
                self.last_list_ms = now_ms;
                out.push(AccountAction::CallList);
            }
            AccountEvent::ListResult(result) => {
                self.list_in_flight = false;
                if self.state == AccountState::LoggedOut {
                    return out; // stale: the user signed out meanwhile
                }
                if self.login_in_flight {
                    return out; // stale: started before the login was submitted
                }
                match result {
                    Ok(list) => {
                        self.retry_list = false;
                        self.machines = list;
                        let this = self
                            .machines
                            .iter()
                            .find(|m| m.is_this_machine)
                            .map(|m| m.machine_id.clone());
                        match this {
                            Some(machine_id) => {
                                let entering = !matches!(self.state, AccountState::LoggedIn { .. });
                                self.state = AccountState::LoggedIn { machine_id };
                                if entering {
                                    self.last_heartbeat_ms = now_ms;
                                }
                                // A later list without this machine (revoked
                                // elsewhere) may register it once more.
                                self.register_requested = false;
                                self.last_list_ms = now_ms;
                                self.arm(
                                    (self.last_list_ms + LIST_INTERVAL_MS)
                                        .min(self.last_heartbeat_ms + HEARTBEAT_INTERVAL_MS),
                                    now_ms,
                                    &mut out,
                                );
                                if entering && self.email.is_none() && !self.session_requested {
                                    self.session_requested = true;
                                    out.push(AccountAction::CallSession);
                                }
                            }
                            None if !self.register_requested => {
                                self.register_requested = true;
                                self.state = AccountState::LoggingIn;
                                out.push(AccountAction::CallRegister);
                            }
                            None => {
                                // No second register (no loop); keep listing:
                                // the machine may show up on a later list.
                                self.state = AccountState::Error(CoreErr::new(
                                    "not_registered",
                                    "this machine is missing from the list after registering",
                                ));
                                self.retry_list = true;
                                self.last_list_ms = now_ms;
                                self.arm(now_ms + LIST_INTERVAL_MS, now_ms, &mut out);
                            }
                        }
                    }
                    Err(e)
                        if e.code == "not_logged_in"
                            || (self.logged_in() && matches!(e.code.as_str(), "unauthorized" | "http_401")) =>
                    {
                        // The server (or a revoked token) ended the session while signed in: ask for sign-in.
                        if self.logged_in() {
                            self.signed_out_by_server = true;
                        }
                        self.reset_session();
                        self.state = AccountState::LoggedOut;
                    }
                    Err(e) => {
                        if matches!(self.state, AccountState::LoggedIn { .. }) {
                            // offline: keep the session and the last list, retry on the tick
                            self.arm(now_ms + LIST_INTERVAL_MS, now_ms, &mut out);
                        } else {
                            self.state = AccountState::Error(e);
                            self.retry_list = true;
                            self.arm(now_ms + LIST_INTERVAL_MS, now_ms, &mut out);
                        }
                    }
                }
            }
            AccountEvent::LoginSubmitted { email, password } => {
                if !self.accepts_login() {
                    return out;
                }
                self.state = AccountState::LoggingIn;
                self.retry_list = false;
                self.login_in_flight = true;
                self.notice = None;
                out.push(AccountAction::CallLogin { email, password });
            }
            AccountEvent::LoginResult(result) => {
                if self.state != AccountState::LoggingIn || !self.login_in_flight {
                    return out;
                }
                self.login_in_flight = false;
                match result {
                    Ok(_) => {
                        self.register_requested = false;
                        self.list_in_flight = true;
                        self.last_list_ms = now_ms;
                        out.push(AccountAction::CallList);
                    }
                    Err(e) => self.state = AccountState::Error(e),
                }
            }
            AccountEvent::Registered(result) => match result {
                Ok(_) => {
                    self.list_in_flight = true;
                    self.last_list_ms = now_ms;
                    out.push(AccountAction::CallList);
                }
                Err(e) => {
                    self.register_requested = false;
                    self.state = AccountState::Error(e);
                    self.retry_list = true;
                    self.arm(now_ms + LIST_INTERVAL_MS, now_ms, &mut out);
                }
            },
            AccountEvent::Tick(now) => {
                if self.tick_pending.is_some_and(|p| now >= p) {
                    self.tick_pending = None;
                }
                match self.state {
                    AccountState::LoggedIn { .. } => {
                        if !self.list_in_flight && now >= self.last_list_ms + LIST_INTERVAL_MS {
                            self.list_in_flight = true;
                            self.last_list_ms = now;
                            out.push(AccountAction::CallList);
                        }
                        if now >= self.last_heartbeat_ms + HEARTBEAT_INTERVAL_MS {
                            self.last_heartbeat_ms = now;
                            out.push(AccountAction::CallHeartbeat);
                        }
                        let next = (self.last_list_ms + LIST_INTERVAL_MS)
                            .min(self.last_heartbeat_ms + HEARTBEAT_INTERVAL_MS);
                        self.arm(next, now, &mut out);
                    }
                    AccountState::Error(_) if self.retry_list => {
                        if !self.list_in_flight && now >= self.last_list_ms + LIST_INTERVAL_MS {
                            self.list_in_flight = true;
                            self.last_list_ms = now;
                            out.push(AccountAction::CallList);
                        }
                        self.arm(self.last_list_ms + LIST_INTERVAL_MS, now, &mut out);
                    }
                    _ => {}
                }
            }
            AccountEvent::HeartbeatResult(Err(e))
                if matches!(e.code.as_str(), "machine_not_found" | "not_registered")
                    && self.state != AccountState::LoggedOut =>
            {
                self.register_requested = false;
                if !self.list_in_flight && !self.login_in_flight {
                    self.list_in_flight = true;
                    self.last_list_ms = now_ms;
                    out.push(AccountAction::CallList);
                }
            }
            AccountEvent::HeartbeatResult(_) => {}
            AccountEvent::LogoutRequested => {
                if !self.logout_in_flight {
                    self.logout_in_flight = true;
                    self.notice = None;
                    out.push(AccountAction::CallLogout);
                }
            }
            AccountEvent::LogoutResult(Err(e)) if e.code != "not_logged_in" => {
                // The session stays (and keeps ticking); the UI shows the error.
                self.logout_in_flight = false;
                self.notice = Some(e);
            }
            AccountEvent::LogoutResult(_) | AccountEvent::LoggedOut => {
                self.reset_session();
                self.state = AccountState::LoggedOut;
            }
            AccountEvent::GoogleRequested(purpose) => {
                if self.google.is_some() {
                    return out;
                }
                match purpose {
                    GooglePurpose::SignIn if self.accepts_login() => {
                        self.state = AccountState::LoggingIn;
                        self.retry_list = false;
                        self.login_in_flight = true;
                        self.notice = None;
                    }
                    GooglePurpose::Link if self.needs_google_switch() => self.notice = None,
                    _ => return out,
                }
                self.google = Some(GoogleRun { purpose, flow_id: None });
                out.push(AccountAction::CallGoogleBegin(purpose));
            }
            AccountEvent::GoogleBegun { purpose, result } => {
                if self.stale_begins > 0 {
                    self.stale_begins -= 1;
                    if let Ok(b) = result {
                        out.push(AccountAction::CallGoogleCancel(b.flow_id));
                    }
                    return out;
                }
                let waiting = self
                    .google
                    .as_ref()
                    .is_some_and(|g| g.purpose == purpose && g.flow_id.is_none());
                if !waiting {
                    if let Ok(b) = result {
                        out.push(AccountAction::CallGoogleCancel(b.flow_id));
                    }
                    return out;
                }
                match result {
                    Ok(b) => {
                        if let Some(g) = self.google.as_mut() {
                            g.flow_id = Some(b.flow_id.clone());
                        }
                        out.push(AccountAction::OpenBrowser(b.auth_url));
                        out.push(AccountAction::CallGoogleFinish(b.flow_id));
                    }
                    Err(e) => self.end_google(purpose, Err(e)),
                }
            }
            AccountEvent::GoogleFinished { flow_id, result } => {
                let Some(purpose) = self
                    .google
                    .as_ref()
                    .filter(|g| g.flow_id.as_deref() == Some(flow_id.as_str()))
                    .map(|g| g.purpose)
                else {
                    return out; // a flow that already ended
                };
                match result {
                    Ok(info) => {
                        self.google = None;
                        self.email = Some(info.email);
                        self.auth_method = Some(info.auth_method);
                        self.notice = None;
                        match purpose {
                            GooglePurpose::SignIn => {
                                self.login_in_flight = false;
                                self.register_requested = false;
                                self.list_in_flight = true;
                                self.last_list_ms = now_ms;
                                out.push(AccountAction::CallList);
                            }
                            GooglePurpose::Link => out.push(AccountAction::CallListSignInMethods),
                        }
                    }
                    Err(e) => self.end_google(purpose, Err(e)),
                }
            }
            AccountEvent::GoogleCancelRequested => {
                let Some(run) = self.google.as_ref() else { return out };
                match run.flow_id.clone() {
                    Some(id) => out.push(AccountAction::CallGoogleCancel(id)),
                    None => {
                        // begin has not answered: forget the flow and cancel what it returns.
                        let purpose = run.purpose;
                        self.google = None;
                        self.stale_begins += 1;
                        if purpose == GooglePurpose::SignIn {
                            self.login_in_flight = false;
                            self.state = AccountState::LoggedOut;
                        }
                    }
                }
            }
            AccountEvent::SessionResult(result) => {
                if let (Ok(info), true) = (result, self.logged_in()) {
                    if info.email.is_some() {
                        self.email = info.email;
                    }
                    self.auth_method = Some(info.auth_method);
                }
            }
            AccountEvent::SignInMethodsRequested => {
                if self.logged_in() {
                    out.push(AccountAction::CallListSignInMethods);
                }
            }
            AccountEvent::SignInMethodsResult(result) => {
                if self.logged_in() {
                    match result {
                        Ok(list) => self.methods = Some(list),
                        Err(e) => self.notice = Some(e),
                    }
                }
            }
            AccountEvent::RemoveSignInMethodRequested(id) => {
                if self.logged_in() && self.removing.is_none() {
                    self.removing = Some(id.clone());
                    self.notice = None;
                    out.push(AccountAction::CallRemoveSignInMethod(id));
                }
            }
            AccountEvent::SignInMethodRemoved { identity_id, result } => {
                if self.removing.as_deref() != Some(identity_id.as_str()) {
                    return out;
                }
                self.removing = None;
                match result {
                    Ok(()) => out.push(AccountAction::CallListSignInMethods),
                    Err(e) => self.notice = Some(e),
                }
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core_api::{GoogleBegin, GoogleSignIn, SessionInfo, SignInMethod};

    fn m(id: &str, this: bool) -> MachineInfo {
        MachineInfo {
            machine_id: id.into(),
            name: id.into(),
            platform: "windows".into(),
            online: true,
            last_seen_unix: 0,
            fingerprint: "f".into(),
            is_this_machine: this,
        }
    }

    fn login_info() -> LoginInfo {
        LoginInfo {
            user_id: "u".into(),
            device_id: "d".into(),
            device_public_key_b64: "k".into(),
            fingerprint: "f".into(),
        }
    }

    fn net() -> CoreErr {
        CoreErr::new("network", "down")
    }

    /// Flow that is LoggedIn at t=1000 with list [this].
    fn logged_in() -> AccountFlow {
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 1_000);
        f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), 1_000);
        assert_eq!(
            f.state(),
            &AccountState::LoggedIn {
                machine_id: "me".into()
            }
        );
        f
    }

    #[test]
    fn not_logged_in_shows_login() {
        let mut f = AccountFlow::new();
        assert_eq!(f.state(), &AccountState::Unknown);
        assert_eq!(
            f.on(AccountEvent::Started, 0),
            vec![AccountAction::CallList]
        );
        let acts = f.on(
            AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", "no"))),
            5,
        );
        assert!(acts.is_empty());
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert!(f.machines().is_empty());
        // ticks do nothing while logged out
        assert!(f.on(AccountEvent::Tick(100_000), 100_000).is_empty());
    }

    #[test]
    fn login_then_register_once() {
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        f.on(
            AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))),
            1,
        );
        let acts = f.on(
            AccountEvent::LoginSubmitted {
                email: "a@b.c".into(),
                password: "pw".into(),
            },
            2,
        );
        assert_eq!(
            acts,
            vec![AccountAction::CallLogin {
                email: "a@b.c".into(),
                password: "pw".into()
            }]
        );
        assert_eq!(f.state(), &AccountState::LoggingIn);
        // a double submit while logging in is ignored
        assert!(
            f.on(
                AccountEvent::LoginSubmitted {
                    email: "x".into(),
                    password: "y".into()
                },
                3
            )
            .is_empty()
        );
        assert_eq!(
            f.on(AccountEvent::LoginResult(Ok(login_info())), 4),
            vec![AccountAction::CallList]
        );
        // list without this machine: register exactly once
        assert_eq!(
            f.on(AccountEvent::ListResult(Ok(vec![m("mac", false)])), 5),
            vec![AccountAction::CallRegister]
        );
        assert_eq!(
            f.on(
                AccountEvent::Registered(Ok(Registered {
                    machine_id: "me".into(),
                    slot: "s".into()
                })),
                6
            ),
            vec![AccountAction::CallList]
        );
        let acts = f.on(
            AccountEvent::ListResult(Ok(vec![m("mac", false), m("me", true)])),
            7,
        );
        assert_eq!(
            f.state(),
            &AccountState::LoggedIn {
                machine_id: "me".into()
            }
        );
        assert!(!acts.contains(&AccountAction::CallRegister));
        assert_eq!(f.machines().len(), 2);
        // a later list that lacks this machine does not loop on register: LoggedIn stays Error-free
        // only when it has it; if the server forgets it after a fresh register request, we stop.
        let mut g = AccountFlow::new();
        g.on(AccountEvent::Started, 0);
        g.on(AccountEvent::ListResult(Ok(vec![])), 1);
        g.on(
            AccountEvent::Registered(Ok(Registered {
                machine_id: "x".into(),
                slot: "s".into(),
            })),
            2,
        );
        let acts = g.on(AccountEvent::ListResult(Ok(vec![])), 3);
        assert!(!acts.contains(&AccountAction::CallRegister));
        assert!(matches!(g.state(), AccountState::Error(e) if e.code == "not_registered"));
    }

    #[test]
    fn login_failure_is_error_and_resubmittable() {
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        f.on(
            AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))),
            1,
        );
        f.on(
            AccountEvent::LoginSubmitted {
                email: "a".into(),
                password: "b".into(),
            },
            2,
        );
        f.on(
            AccountEvent::LoginResult(Err(CoreErr::new("unauthorized", "bad password"))),
            3,
        );
        assert!(matches!(f.state(), AccountState::Error(e) if e.code == "unauthorized"));
        // no automatic list retry after a login error
        assert!(f.on(AccountEvent::Tick(60_000), 60_000).is_empty());
        let acts = f.on(
            AccountEvent::LoginSubmitted {
                email: "a".into(),
                password: "c".into(),
            },
            61_000,
        );
        assert_eq!(acts.len(), 1);
    }

    #[test]
    fn heartbeat_every_30s_list_every_15s() {
        let mut f = logged_in(); // t=1000
        let mut calls: Vec<(u64, AccountAction)> = Vec::new();
        let mut t = 1_000;
        // the first schedule was armed at login
        let mut next = 1_000 + LIST_INTERVAL_MS;
        while t < 61_000 {
            t = next;
            let acts = f.on(AccountEvent::Tick(t), t);
            let mut sched = None;
            for a in acts {
                match a {
                    AccountAction::ScheduleTick { at_ms } => sched = Some(at_ms),
                    AccountAction::CallList => {
                        calls.push((t, AccountAction::CallList));
                    }
                    AccountAction::CallHeartbeat => calls.push((t, AccountAction::CallHeartbeat)),
                    other => panic!("unexpected {other:?}"),
                }
            }
            if calls
                .iter()
                .any(|(ct, a)| *ct == t && *a == AccountAction::CallList)
            {
                f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), t);
            }
            next = sched.expect("a next tick is always scheduled while logged in");
            assert!(next > t);
        }
        let times = |want: AccountAction| -> Vec<u64> {
            calls
                .iter()
                .filter(|(_, a)| *a == want)
                .map(|(t, _)| *t)
                .collect()
        };
        assert_eq!(
            times(AccountAction::CallList),
            vec![16_000, 31_000, 46_000, 61_000]
        );
        assert_eq!(times(AccountAction::CallHeartbeat), vec![31_000, 61_000]);
    }

    #[test]
    fn ticks_do_not_duplicate_work_or_schedules() {
        let mut f = logged_in();
        // early ticks produce nothing
        assert!(f.on(AccountEvent::Tick(2_000), 2_000).is_empty());
        let acts = f.on(AccountEvent::Tick(16_000), 16_000);
        assert_eq!(acts[0], AccountAction::CallList);
        // list still in flight: a second tick does not call again
        let acts = f.on(AccountEvent::Tick(16_500), 16_500);
        assert!(!acts.contains(&AccountAction::CallList));
        assert!(
            !acts
                .iter()
                .any(|a| matches!(a, AccountAction::ScheduleTick { .. }))
        );
    }

    #[test]
    fn network_error_keeps_session() {
        let mut f = logged_in();
        f.on(
            AccountEvent::ListResult(Ok(vec![m("mac", false), m("me", true)])),
            1_000,
        );
        let acts = f.on(AccountEvent::Tick(16_000), 16_000);
        assert!(acts.contains(&AccountAction::CallList));
        let acts = f.on(AccountEvent::ListResult(Err(net())), 16_100);
        assert_eq!(
            f.state(),
            &AccountState::LoggedIn {
                machine_id: "me".into()
            }
        );
        assert_eq!(f.machines().len(), 2, "last list kept while offline");
        assert!(
            acts.iter()
                .all(|a| !matches!(a, AccountAction::CallLogin { .. }))
        );
        // retried on the next tick
        let acts = f.on(AccountEvent::Tick(31_000), 31_000);
        assert!(acts.contains(&AccountAction::CallList));
        assert!(acts.contains(&AccountAction::CallHeartbeat));
        // a heartbeat network error has no event, and a later not_logged_in does log out
        f.on(
            AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))),
            31_100,
        );
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert!(f.machines().is_empty());
    }

    #[test]
    fn startup_network_error_retries() {
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        let acts = f.on(AccountEvent::ListResult(Err(net())), 10);
        assert!(matches!(f.state(), AccountState::Error(e) if e.code == "network"));
        assert_eq!(
            acts,
            vec![AccountAction::ScheduleTick {
                at_ms: 10 + LIST_INTERVAL_MS
            }]
        );
        let acts = f.on(AccountEvent::Tick(15_010), 15_010);
        assert!(acts.contains(&AccountAction::CallList));
    }

    #[test]
    fn logout_flow() {
        let mut f = logged_in();
        assert_eq!(
            f.on(AccountEvent::LogoutRequested, 5_000),
            vec![AccountAction::CallLogout]
        );
        f.on(AccountEvent::LoggedOut, 5_001);
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert!(f.on(AccountEvent::Tick(40_000), 40_000).is_empty());
        // a stale list result after logout is ignored
        f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), 40_001);
        assert_eq!(f.state(), &AccountState::LoggedOut);
    }

    #[test]
    fn reregisters_once_after_this_machine_disappears() {
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        f.on(AccountEvent::ListResult(Ok(vec![])), 1);
        f.on(
            AccountEvent::Registered(Ok(Registered {
                machine_id: "me".into(),
                slot: "s".into(),
            })),
            2,
        );
        f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), 3);
        assert_eq!(
            f.state(),
            &AccountState::LoggedIn {
                machine_id: "me".into()
            }
        );
        // revoked elsewhere: the next list lacks this machine -> one register
        f.on(AccountEvent::Tick(15_003), 15_003);
        let acts = f.on(AccountEvent::ListResult(Ok(vec![m("mac", false)])), 15_004);
        assert_eq!(acts, vec![AccountAction::CallRegister]);
        f.on(
            AccountEvent::Registered(Ok(Registered {
                machine_id: "me2".into(),
                slot: "s".into(),
            })),
            15_005,
        );
        f.on(
            AccountEvent::ListResult(Ok(vec![m("mac", false), m("me2", true)])),
            15_006,
        );
        assert_eq!(
            f.state(),
            &AccountState::LoggedIn {
                machine_id: "me2".into()
            }
        );
    }

    #[test]
    fn heartbeat_machine_not_found_lists_and_registers_again() {
        for code in ["machine_not_found", "not_registered"] {
            let mut f = AccountFlow::new();
            f.on(AccountEvent::Started, 0);
            // register once; the machine still misses from the list (stuck)
            f.on(AccountEvent::ListResult(Ok(vec![])), 1);
            f.on(
                AccountEvent::Registered(Ok(Registered {
                    machine_id: "me".into(),
                    slot: "s".into(),
                })),
                2,
            );
            f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), 3);
            f.on(AccountEvent::Tick(30_003), 30_003); // list + heartbeat
            f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), 30_004);
            // removed on the server: the heartbeat answers machine_not_found
            let acts = f.on(
                AccountEvent::HeartbeatResult(Err(CoreErr::new(code, "gone"))),
                30_005,
            );
            assert_eq!(acts, vec![AccountAction::CallList], "{code}");
            let acts = f.on(AccountEvent::ListResult(Ok(vec![m("mac", false)])), 30_006);
            assert_eq!(acts, vec![AccountAction::CallRegister], "{code}");
        }
        // a heartbeat error that is not about the machine changes nothing
        let mut f = logged_in();
        assert!(
            f.on(AccountEvent::HeartbeatResult(Err(net())), 2_000)
                .is_empty()
        );
        assert!(
            f.on(AccountEvent::HeartbeatResult(Ok(())), 2_001)
                .is_empty()
        );
        // a revoked machine that failed to show up after its one register
        // may register again once a heartbeat says it is gone
        let mut g = AccountFlow::new();
        g.on(AccountEvent::Started, 0);
        g.on(AccountEvent::ListResult(Ok(vec![])), 1);
        g.on(
            AccountEvent::Registered(Ok(Registered {
                machine_id: "me".into(),
                slot: "s".into(),
            })),
            2,
        );
        g.on(AccountEvent::ListResult(Ok(vec![])), 3); // Error(not_registered)
        g.on(
            AccountEvent::HeartbeatResult(Err(CoreErr::new("machine_not_found", ""))),
            4,
        );
        let acts = g.on(AccountEvent::ListResult(Ok(vec![])), 5);
        assert!(acts.contains(&AccountAction::CallRegister), "{acts:?}");
    }

    #[test]
    fn not_registered_keeps_ticking_until_listed() {
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        f.on(AccountEvent::ListResult(Ok(vec![])), 1);
        f.on(
            AccountEvent::Registered(Ok(Registered {
                machine_id: "me".into(),
                slot: "s".into(),
            })),
            2,
        );
        let acts = f.on(AccountEvent::ListResult(Ok(vec![])), 3);
        assert!(matches!(f.state(), AccountState::Error(e) if e.code == "not_registered"));
        assert_eq!(
            acts,
            vec![AccountAction::ScheduleTick {
                at_ms: 3 + LIST_INTERVAL_MS
            }]
        );
        let acts = f.on(
            AccountEvent::Tick(3 + LIST_INTERVAL_MS),
            3 + LIST_INTERVAL_MS,
        );
        assert!(acts.contains(&AccountAction::CallList));
        assert!(!acts.contains(&AccountAction::CallRegister));
        // still missing: no register, another tick
        let acts = f.on(AccountEvent::ListResult(Ok(vec![])), 15_010);
        assert!(!acts.contains(&AccountAction::CallRegister));
        // the tick armed at 15_003 (for 30_003) is still pending: no new schedule
        assert!(
            !acts
                .iter()
                .any(|a| matches!(a, AccountAction::ScheduleTick { .. }))
        );
        let acts = f.on(AccountEvent::Tick(30_010), 30_010);
        assert!(acts.contains(&AccountAction::CallList));
        assert!(
            acts.iter()
                .any(|a| matches!(a, AccountAction::ScheduleTick { .. }))
        );
        f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), 30_011);
        assert_eq!(
            f.state(),
            &AccountState::LoggedIn {
                machine_id: "me".into()
            }
        );
    }

    #[test]
    fn list_result_ignored_while_login_in_flight() {
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        f.on(AccountEvent::ListResult(Err(net())), 1); // Error, retrying
        f.on(AccountEvent::Tick(15_001), 15_001); // a list is in flight
        f.on(
            AccountEvent::LoginSubmitted {
                email: "a".into(),
                password: "b".into(),
            },
            15_002,
        );
        assert!(f.login_in_flight());
        // the list started before the login answers not_logged_in: dropped
        let acts = f.on(
            AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))),
            15_003,
        );
        assert!(acts.is_empty());
        assert_eq!(f.state(), &AccountState::LoggingIn);
        assert_eq!(
            f.on(AccountEvent::LoginResult(Ok(login_info())), 15_004),
            vec![AccountAction::CallList]
        );
        assert!(!f.login_in_flight());
        // the list after the login is applied (LoggingIn, login done)
        f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), 15_005);
        assert_eq!(
            f.state(),
            &AccountState::LoggedIn {
                machine_id: "me".into()
            }
        );
    }

    #[test]
    fn logout_failure_stays_logged_in_with_notice() {
        let mut f = logged_in();
        assert_eq!(
            f.on(AccountEvent::LogoutRequested, 2_000),
            vec![AccountAction::CallLogout]
        );
        // a second request while the call runs is ignored
        assert!(f.on(AccountEvent::LogoutRequested, 2_001).is_empty());
        let acts = f.on(AccountEvent::LogoutResult(Err(net())), 2_002);
        assert!(acts.is_empty());
        assert_eq!(
            f.state(),
            &AccountState::LoggedIn {
                machine_id: "me".into()
            }
        );
        assert_eq!(f.notice(), Some(&net()));
        assert_eq!(f.machines().len(), 1);
        // still ticking
        assert!(
            f.on(AccountEvent::Tick(16_000), 16_000)
                .contains(&AccountAction::CallList)
        );
        // retry succeeds
        assert_eq!(
            f.on(AccountEvent::LogoutRequested, 16_001),
            vec![AccountAction::CallLogout]
        );
        assert_eq!(f.notice(), None);
        f.on(AccountEvent::LogoutResult(Ok(())), 16_002);
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert!(f.machines().is_empty());
        // core says there is no session: that is signed out too
        let mut g = logged_in();
        g.on(AccountEvent::LogoutRequested, 2_000);
        g.on(
            AccountEvent::LogoutResult(Err(CoreErr::new("not_logged_in", ""))),
            2_001,
        );
        assert_eq!(g.state(), &AccountState::LoggedOut);
    }

    #[test]
    fn login_accepted_only_outside_logging_in() {
        let submit = || AccountEvent::LoginSubmitted {
            email: "a".into(),
            password: "b".into(),
        };
        // register phase (LoggingIn, no login call): ignored, so the panel
        // must keep the typed password
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        f.on(AccountEvent::ListResult(Ok(vec![])), 1);
        assert_eq!(f.state(), &AccountState::LoggingIn);
        assert!(!f.accepts_login());
        assert!(f.on(submit(), 2).is_empty());
        // signed out: accepted
        let mut g = AccountFlow::new();
        g.on(AccountEvent::Started, 0);
        g.on(
            AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))),
            1,
        );
        assert!(g.accepts_login());
        assert!(matches!(
            g.on(submit(), 2)[..],
            [AccountAction::CallLogin { .. }]
        ));
        // while that login runs: not accepted
        assert!(!g.accepts_login());
        assert!(g.on(submit(), 3).is_empty());
        // after a failed login: accepted again
        g.on(AccountEvent::LoginResult(Err(net())), 4);
        assert!(g.accepts_login());
    }

    #[test]
    fn password_never_in_debug_or_state() {
        let ev = AccountEvent::LoginSubmitted {
            email: "a@b.c".into(),
            password: "hunter2".into(),
        };
        assert!(!format!("{ev:?}").contains("hunter2"));
        let mut f = AccountFlow::new();
        let acts = f.on(ev, 0);
        assert!(!format!("{acts:?}").contains("hunter2"));
        assert!(!format!("{f:?}").contains("hunter2"));
    }

    // ----- Google sign-in, switch, session, sign-in methods, server sign-out -----

    fn begun(purpose: GooglePurpose, id: &str) -> AccountEvent {
        AccountEvent::GoogleBegun {
            purpose,
            result: Ok(GoogleBegin {
                flow_id: id.into(),
                auth_url: "https://accounts.google.com/x".into(),
            }),
        }
    }

    fn google_done(email: &str, method: &str) -> GoogleSignIn {
        GoogleSignIn {
            user_id: "u".into(),
            device_id: "d".into(),
            device_public_key_b64: "k".into(),
            fingerprint: "f".into(),
            email: email.into(),
            auth_method: method.into(),
        }
    }

    fn finished(id: &str, r: Result<GoogleSignIn, CoreErr>) -> AccountEvent {
        AccountEvent::GoogleFinished {
            flow_id: id.into(),
            result: r,
        }
    }

    fn session(email: Option<&str>, method: &str) -> AccountEvent {
        AccountEvent::SessionResult(Ok(SessionInfo {
            user_id: "u".into(),
            device_id: "d".into(),
            email: email.map(String::from),
            auth_method: method.into(),
        }))
    }

    fn logged_out() -> AccountFlow {
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        f.on(
            AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))),
            1,
        );
        assert_eq!(f.state(), &AccountState::LoggedOut);
        f
    }

    #[test]
    fn google_sign_in_runs_begin_browser_finish_then_lists() {
        let mut f = logged_out();
        assert_eq!(
            f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 2),
            vec![AccountAction::CallGoogleBegin(GooglePurpose::SignIn)]
        );
        assert_eq!(f.state(), &AccountState::LoggingIn);
        assert!(f.login_in_flight());
        assert_eq!(f.google_in_flight(), Some(GooglePurpose::SignIn));
        assert_eq!(
            f.on(begun(GooglePurpose::SignIn, "f1"), 3),
            vec![
                AccountAction::OpenBrowser("https://accounts.google.com/x".into()),
                AccountAction::CallGoogleFinish("f1".into())
            ]
        );
        assert_eq!(
            f.on(finished("f1", Ok(google_done("g@x", "google"))), 4),
            vec![AccountAction::CallList]
        );
        let acts = f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), 5);
        assert!(!acts.contains(&AccountAction::CallSession), "{acts:?}");
        assert!(matches!(f.state(), AccountState::LoggedIn { .. }));
        assert_eq!(f.email(), Some("g@x"));
        assert_eq!(f.auth_method(), Some("google"));
        assert_eq!(f.google_in_flight(), None);
    }

    #[test]
    fn google_cancel_while_waiting_cancels_and_returns_to_signed_out() {
        let mut f = logged_out();
        f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 2);
        f.on(begun(GooglePurpose::SignIn, "f1"), 3);
        assert_eq!(
            f.on(AccountEvent::GoogleCancelRequested, 4),
            vec![AccountAction::CallGoogleCancel("f1".into())]
        );
        assert!(
            f.on(finished("f1", Err(CoreErr::new("google_cancelled", ""))), 5)
                .is_empty()
        );
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert_eq!(f.google_in_flight(), None);
    }

    #[test]
    fn google_cancel_before_begin_answers_cancels_the_returned_flow() {
        let mut f = logged_out();
        f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 2);
        assert!(f.on(AccountEvent::GoogleCancelRequested, 3).is_empty());
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert_eq!(
            f.on(begun(GooglePurpose::SignIn, "f1"), 4),
            vec![AccountAction::CallGoogleCancel("f1".into())]
        );
    }

    #[test]
    fn google_failure_is_an_error_and_can_be_retried() {
        let mut f = logged_out();
        f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 2);
        f.on(begun(GooglePurpose::SignIn, "f1"), 3);
        let e = CoreErr::new("switch_from_signed_in_device", "x");
        f.on(finished("f1", Err(e.clone())), 4);
        assert_eq!(f.state(), &AccountState::Error(e));
        assert_eq!(
            f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 5),
            vec![AccountAction::CallGoogleBegin(GooglePurpose::SignIn)]
        );
    }

    #[test]
    fn a_second_google_request_while_one_runs_is_ignored() {
        let mut f = logged_out();
        f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 2);
        assert!(f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 3).is_empty());
        assert!(f.on(AccountEvent::GoogleRequested(GooglePurpose::Link), 3).is_empty());
    }

    #[test]
    fn a_stale_google_finish_is_ignored() {
        let mut f = logged_out();
        f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 2);
        f.on(begun(GooglePurpose::SignIn, "f1"), 3);
        assert!(f.on(finished("f0", Ok(google_done("g@x", "google"))), 4).is_empty());
        assert_eq!(f.state(), &AccountState::LoggingIn);
        assert_eq!(f.email(), None);
    }

    #[test]
    fn switch_to_google_keeps_the_session_and_updates_the_method() {
        let mut f = logged_in();
        f.on(session(Some("old@x"), "password"), 1_100);
        assert!(f.needs_google_switch());
        assert_eq!(
            f.on(AccountEvent::GoogleRequested(GooglePurpose::Link), 1_200),
            vec![AccountAction::CallGoogleBegin(GooglePurpose::Link)]
        );
        assert!(matches!(f.state(), AccountState::LoggedIn { .. }));
        assert!(f.on(AccountEvent::Tick(16_000), 16_000).contains(&AccountAction::CallList));
        assert_eq!(
            f.on(begun(GooglePurpose::Link, "f1"), 16_100),
            vec![
                AccountAction::OpenBrowser("https://accounts.google.com/x".into()),
                AccountAction::CallGoogleFinish("f1".into())
            ]
        );
        assert_eq!(
            f.on(finished("f1", Ok(google_done("new@x", "google"))), 17_000),
            vec![AccountAction::CallListSignInMethods]
        );
        assert_eq!(f.email(), Some("new@x"));
        assert_eq!(f.auth_method(), Some("google"));
        assert!(!f.needs_google_switch());
        assert!(matches!(f.state(), AccountState::LoggedIn { .. }));
    }

    #[test]
    fn switch_failure_keeps_the_session_and_sets_the_notice() {
        let mut f = logged_in();
        f.on(session(Some("old@x"), "password"), 1_100);
        f.on(AccountEvent::GoogleRequested(GooglePurpose::Link), 1_200);
        f.on(begun(GooglePurpose::Link, "f1"), 1_300);
        f.on(finished("f1", Err(CoreErr::new("email_in_use", "x"))), 1_400);
        assert!(matches!(f.state(), AccountState::LoggedIn { .. }));
        assert_eq!(f.notice().map(|e| e.code.as_str()), Some("email_in_use"));
        assert!(f.needs_google_switch());
        // a cancelled link leaves no notice
        let mut g = logged_in();
        g.on(session(Some("old@x"), "password"), 1_100);
        g.on(AccountEvent::GoogleRequested(GooglePurpose::Link), 1_200);
        g.on(begun(GooglePurpose::Link, "f1"), 1_300);
        g.on(finished("f1", Err(CoreErr::new("google_cancelled", ""))), 1_400);
        assert!(g.notice().is_none());
    }

    #[test]
    fn link_is_refused_unless_signed_in_with_a_password() {
        let mut f = logged_out();
        assert!(f.on(AccountEvent::GoogleRequested(GooglePurpose::Link), 2).is_empty());
        let mut g = logged_in();
        g.on(session(Some("g@x"), "google"), 1_100);
        assert!(g.on(AccountEvent::GoogleRequested(GooglePurpose::Link), 1_200).is_empty());
    }

    #[test]
    fn entering_logged_in_asks_the_session_once() {
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        let acts = f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), 0);
        assert!(acts.contains(&AccountAction::CallSession), "{acts:?}");
        f.on(AccountEvent::Tick(16_000), 16_000);
        let acts = f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), 16_000);
        assert!(!acts.contains(&AccountAction::CallSession));
        f.on(AccountEvent::SessionResult(Err(net())), 16_100);
        assert_eq!(f.email(), None);
        assert!(matches!(f.state(), AccountState::LoggedIn { .. }));
        f.on(session(Some("a@b.c"), "password"), 16_200);
        assert_eq!(f.email(), Some("a@b.c"));
    }

    #[test]
    fn server_sign_out_shows_sign_in() {
        for code in ["unauthorized", "http_401", "not_logged_in"] {
            let mut f = logged_in();
            f.on(AccountEvent::Tick(16_000), 16_000);
            f.on(AccountEvent::ListResult(Err(CoreErr::new(code, ""))), 16_000);
            assert_eq!(f.state(), &AccountState::LoggedOut, "{code}");
            assert!(f.take_signed_out_by_server(), "{code}");
            assert!(!f.take_signed_out_by_server(), "{code}");
        }
        let mut f = logged_in();
        f.on(AccountEvent::LogoutRequested, 2_000);
        f.on(AccountEvent::LogoutResult(Ok(())), 2_100);
        assert!(!f.take_signed_out_by_server());
        // not_logged_in outside LoggedIn keeps today's behaviour: signed out, no flag
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        f.on(AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))), 1);
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert!(!f.take_signed_out_by_server());
    }

    fn method(id: &str, provider: &str) -> SignInMethod {
        SignInMethod {
            identity_id: id.into(),
            provider: provider.into(),
            email: "x@y".into(),
            is_private_email: false,
            linked_via_device_name: None,
            created_at_unix: 1,
        }
    }

    #[test]
    fn sign_in_methods_list_and_remove() {
        let mut out = logged_out();
        assert!(out.on(AccountEvent::SignInMethodsRequested, 2).is_empty());
        let mut f = logged_in();
        assert_eq!(
            f.on(AccountEvent::SignInMethodsRequested, 1_100),
            vec![AccountAction::CallListSignInMethods]
        );
        f.on(
            AccountEvent::SignInMethodsResult(Ok(vec![method("g1", "google"), method("a1", "apple")])),
            1_200,
        );
        assert_eq!(f.sign_in_methods().map(<[_]>::len), Some(2));
        assert_eq!(
            f.on(AccountEvent::RemoveSignInMethodRequested("a1".into()), 1_300),
            vec![AccountAction::CallRemoveSignInMethod("a1".into())]
        );
        assert_eq!(f.removing_sign_in_method(), Some("a1"));
        assert!(f.on(AccountEvent::RemoveSignInMethodRequested("a2".into()), 1_310).is_empty());
        assert_eq!(
            f.on(
                AccountEvent::SignInMethodRemoved { identity_id: "a1".into(), result: Ok(()) },
                1_400
            ),
            vec![AccountAction::CallListSignInMethods]
        );
        assert_eq!(f.removing_sign_in_method(), None);
        f.on(AccountEvent::RemoveSignInMethodRequested("a1".into()), 1_500);
        f.on(
            AccountEvent::SignInMethodRemoved { identity_id: "a1".into(), result: Err(net()) },
            1_600,
        );
        assert_eq!(f.notice(), Some(&net()));
    }

    #[test]
    fn logout_clears_email_method_and_methods() {
        let mut f = logged_in();
        f.on(session(Some("a@b.c"), "password"), 1_100);
        f.on(AccountEvent::SignInMethodsResult(Ok(vec![method("g1", "google")])), 1_200);
        f.on(AccountEvent::LogoutRequested, 1_300);
        f.on(AccountEvent::LogoutResult(Ok(())), 1_400);
        assert_eq!((f.email(), f.auth_method()), (None, None));
        assert!(f.sign_in_methods().is_none());
    }

    #[test]
    fn google_urls_and_emails_never_in_debug() {
        let a = AccountAction::OpenBrowser("https://accounts.google.com/x?state=S".into());
        assert!(!format!("{a:?}").contains("state=S"));
        let e = finished("f1", Ok(google_done("g@x", "google")));
        assert!(!format!("{e:?}").contains("g@x"));
        let s = session(Some("g@x"), "google");
        assert!(!format!("{s:?}").contains("g@x"));
    }

    #[test]
    fn delete_account_url_is_the_privacy_page() {
        assert_eq!(DELETE_ACCOUNT_URL, "https://shellx.pro/privacy#delete-account");
    }
}
