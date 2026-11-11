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
//!
//! Email code sign-in (D2, D3) is a run beside the state: `EmailCodeRequested` mails a code,
//! `EmailCodeSubmitted` checks it and, when right, signs in like Google does. The address, the code and the
//! challenge id live only in the run and in the events and actions that carry them; `Debug` redacts them.
//! One sign-in flow runs at a time: no email call starts while a Google flow runs, and Google is refused
//! while a code is on its way, shown or being checked.

use std::fmt;

use crate::core_api::{
    CoreErr, EmailChallenge, GoogleBegin, GooglePurpose, GoogleSignIn, LoginInfo, Registered,
    SessionInfo, SignInMethod,
};
use crate::email_sign_in::{EmailStep, code_digits, email_looks_valid};
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
    /// "Send code": the typed address and the mail's language (`"vi"` | `"en"`); starts an email run.
    EmailCodeRequested {
        email: String,
        locale: String,
    },
    /// The email field's text changed (an edit, not a click or a cursor move).
    EmailEdited,
    /// "Resend code": the run's address and language again.
    EmailResendRequested,
    /// Result of `CallEmailBegin`.
    EmailBegun(Result<EmailChallenge, CoreErr>),
    /// Verify, Enter or six digits typed: the code field's text.
    EmailCodeSubmitted(String),
    /// Result of `CallEmailFinish`.
    EmailFinished {
        challenge_id: String,
        result: Result<GoogleSignIn, CoreErr>,
    },
    /// "Use a different email".
    EmailChangeRequested,
    /// The dialog closed (Cancel, Escape) while an email run exists.
    EmailCancelled,
}

#[derive(Clone, PartialEq, Eq)]
pub enum AccountAction {
    CallList,
    CallLogin {
        email: String,
        password: String,
    },
    CallRegister,
    CallHeartbeat,
    CallLogout,
    ScheduleTick {
        at_ms: u64,
    },
    CallGoogleBegin(GooglePurpose),
    /// The window opens this URL in the system browser.
    OpenBrowser(String),
    /// Blocks until the browser answers (up to 300 s): the app runs it on its own task.
    CallGoogleFinish(String),
    CallGoogleCancel(String),
    CallSession,
    CallListSignInMethods,
    CallRemoveSignInMethod(String),
    /// `auth.email.begin`: the trimmed address and the mail's language.
    CallEmailBegin {
        email: String,
        locale: String,
    },
    /// `auth.email.finish`: the challenge and the six ASCII digits.
    CallEmailFinish {
        challenge_id: String,
        code: String,
    },
}

impl fmt::Debug for AccountEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AccountEvent::Started => write!(f, "Started"),
            AccountEvent::ListResult(r) => f.debug_tuple("ListResult").field(r).finish(),
            AccountEvent::LoginSubmitted { .. } => f
                .debug_struct("LoginSubmitted")
                .field("email", &"<redacted>")
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
            AccountEvent::SignInMethodsResult(r) => f
                .debug_tuple("SignInMethodsResult")
                .field(&r.as_ref().map(Vec::len))
                .finish(),
            AccountEvent::RemoveSignInMethodRequested(id) => f
                .debug_tuple("RemoveSignInMethodRequested")
                .field(id)
                .finish(),
            AccountEvent::SignInMethodRemoved {
                identity_id,
                result,
            } => f
                .debug_struct("SignInMethodRemoved")
                .field("identity_id", identity_id)
                .field("result", result)
                .finish(),
            AccountEvent::EmailCodeRequested { locale, .. } => f
                .debug_struct("EmailCodeRequested")
                .field("email", &"<redacted>")
                .field("locale", locale)
                .finish(),
            AccountEvent::EmailEdited => write!(f, "EmailEdited"),
            AccountEvent::EmailResendRequested => write!(f, "EmailResendRequested"),
            AccountEvent::EmailBegun(r) => f.debug_tuple("EmailBegun").field(r).finish(),
            AccountEvent::EmailCodeSubmitted(_) => f
                .debug_tuple("EmailCodeSubmitted")
                .field(&"<redacted>")
                .finish(),
            AccountEvent::EmailFinished { result, .. } => f
                .debug_struct("EmailFinished")
                .field("challenge_id", &"<redacted>")
                .field("result", result)
                .finish(),
            AccountEvent::EmailChangeRequested => write!(f, "EmailChangeRequested"),
            AccountEvent::EmailCancelled => write!(f, "EmailCancelled"),
        }
    }
}

impl fmt::Debug for AccountAction {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AccountAction::CallList => write!(f, "CallList"),
            AccountAction::CallLogin { .. } => f
                .debug_struct("CallLogin")
                .field("email", &"<redacted>")
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
            AccountAction::OpenBrowser(_) => {
                f.debug_tuple("OpenBrowser").field(&"<auth url>").finish()
            }
            AccountAction::CallGoogleFinish(id) => {
                f.debug_tuple("CallGoogleFinish").field(id).finish()
            }
            AccountAction::CallGoogleCancel(id) => {
                f.debug_tuple("CallGoogleCancel").field(id).finish()
            }
            AccountAction::CallSession => write!(f, "CallSession"),
            AccountAction::CallListSignInMethods => write!(f, "CallListSignInMethods"),
            AccountAction::CallRemoveSignInMethod(id) => {
                f.debug_tuple("CallRemoveSignInMethod").field(id).finish()
            }
            AccountAction::CallEmailBegin { locale, .. } => f
                .debug_struct("CallEmailBegin")
                .field("email", &"<redacted>")
                .field("locale", locale)
                .finish(),
            AccountAction::CallEmailFinish { .. } => f
                .debug_struct("CallEmailFinish")
                .field("challenge_id", &"<redacted>")
                .field("code", &"<redacted>")
                .finish(),
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

/// An email code sign-in the person started. `Debug` (hand-written) shows the step only.
struct EmailRun {
    step: EmailStep,
    /// False once the dialog closed a run that is verifying: hidden, but its answer still applies.
    shown: bool,
    /// The typed address (trimmed) and the mail's language, sent again by "Resend code".
    email: String,
    locale: String,
    /// The relay's address for the code sent in this run.
    sent_to: Option<String>,
    /// The challenge a code can be verified against; `None` once the relay lost it.
    challenge: Option<String>,
    error: Option<CoreErr>,
    /// "Resend code" stays locked until this time.
    resend_at_ms: u64,
    /// While verifying: what the verify interrupted, restored when the code is refused.
    resume: Option<Resume>,
}

/// The account state a verify started from, and whether its list retries were running.
struct Resume {
    state: AccountState,
    retry_list: bool,
}

impl fmt::Debug for EmailRun {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("EmailRun")
            .field("step", &self.step)
            .field("shown", &self.shown)
            .finish_non_exhaustive()
    }
}

/// `Debug` (hand-written) shows the state, counts and flags, never the email or the machines' names.
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
    /// `notice` is a failed sign-in-methods list or removal (Settings words it differently).
    notice_is_methods: bool,
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
    /// The server ended a session this flow had; cleared by the next entry to LoggedIn.
    session_ended_by_server: bool,
    methods: Option<Vec<SignInMethod>>,
    removing: Option<String>,
    /// The core has shown that it holds a session: a login or Google sign-in succeeded, a list answered
    /// anything but `not_logged_in` / `unauthorized` / `http_401`, or a register answered. Cleared with
    /// the session (`reset_session`) and by a list that says there is none.
    has_session: bool,
    /// The email code sign-in, if one runs. `reset_session` leaves it; entering LoggedIn drops it.
    email_run: Option<EmailRun>,
    /// `auth.email.begin` calls dropped by a close whose answers have not arrived yet.
    stale_email_begins: u32,
    /// Moves whenever the dialog must empty its code field (`email_code_epoch`).
    email_epoch: u64,
}

impl Default for AccountFlow {
    fn default() -> Self {
        AccountFlow::new()
    }
}

impl fmt::Debug for AccountFlow {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let email = if self.email.is_some() {
            "<set>"
        } else {
            "<none>"
        };
        f.debug_struct("AccountFlow")
            .field("state", &self.state)
            .field("machines", &self.machines.len())
            .field("register_requested", &self.register_requested)
            .field("list_in_flight", &self.list_in_flight)
            .field("login_in_flight", &self.login_in_flight)
            .field("logout_in_flight", &self.logout_in_flight)
            .field("retry_list", &self.retry_list)
            .field("has_session", &self.has_session)
            .field("session_requested", &self.session_requested)
            .field("session_ended_by_server", &self.session_ended_by_server)
            .field("last_list_ms", &self.last_list_ms)
            .field("last_heartbeat_ms", &self.last_heartbeat_ms)
            .field("tick_pending", &self.tick_pending)
            .field("google", &self.google)
            .field("stale_begins", &self.stale_begins)
            .field("notice", &self.notice)
            .field("notice_is_methods", &self.notice_is_methods)
            .field("email", &format_args!("{email}"))
            .field("auth_method", &self.auth_method)
            .field("methods", &self.methods.as_ref().map(Vec::len))
            .field("removing", &self.removing)
            .field("email_run", &self.email_run)
            .field("stale_email_begins", &self.stale_email_begins)
            .field("email_epoch", &self.email_epoch)
            .finish()
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
            notice_is_methods: false,
            last_list_ms: 0,
            last_heartbeat_ms: 0,
            retry_list: false,
            tick_pending: None,
            google: None,
            stale_begins: 0,
            email: None,
            auth_method: None,
            session_requested: false,
            session_ended_by_server: false,
            methods: None,
            removing: None,
            has_session: false,
            email_run: None,
            stale_email_begins: 0,
            email_epoch: 0,
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

    /// The notice is a failed sign-in-methods list or removal.
    pub fn notice_is_methods(&self) -> bool {
        self.notice.is_some() && self.notice_is_methods
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
        matches!(self.state, AccountState::LoggedIn { .. })
            && self.auth_method.as_deref() == Some("password")
    }

    pub fn sign_in_methods(&self) -> Option<&[SignInMethod]> {
        self.methods.as_deref()
    }

    pub fn removing_sign_in_method(&self) -> Option<&str> {
        self.removing.as_deref()
    }

    /// Whether "Sign out" is offered: always while signed in, and in the error state once the core has
    /// shown a session exists (R4 Major 6: a session whose list fails must still be able to sign out).
    pub fn can_sign_out(&self) -> bool {
        match self.state {
            AccountState::LoggedIn { .. } => true,
            AccountState::Error(_) => self.has_session,
            _ => false,
        }
    }

    /// The server ended this session while it was signed in (a 401, or `not_logged_in` while
    /// LoggedIn). Stays true until the flow next enters LoggedIn; reading it changes nothing: the
    /// sidebar and Settings show "Your session expired." with "Sign in again", and no dialog opens by
    /// itself (Ruling 29).
    pub fn session_ended_by_server(&self) -> bool {
        self.session_ended_by_server
    }

    /// The email run the dialog shows.
    fn shown_email_run(&self) -> Option<&EmailRun> {
        self.email_run.as_ref().filter(|r| r.shown)
    }

    /// The email run's step; `None` with no run, or once the dialog closed a run that is verifying.
    pub fn email_step(&self) -> Option<EmailStep> {
        self.shown_email_run().map(|r| r.step)
    }

    /// The relay's address for the code sent in this run.
    pub fn email_sent_to(&self) -> Option<&str> {
        self.shown_email_run().and_then(|r| r.sent_to.as_deref())
    }

    /// The run's last failure (worded by `strings::email_error`).
    pub fn email_error(&self) -> Option<&CoreErr> {
        self.shown_email_run().and_then(|r| r.error.as_ref())
    }

    /// On the code step with a challenge the relay still holds: Verify and the auto-submit may run.
    pub fn email_can_verify(&self) -> bool {
        self.shown_email_run()
            .is_some_and(|r| r.step == EmailStep::Code && r.challenge.is_some())
    }

    /// Seconds until "Resend code" can be pressed, rounded up; 0 = now.
    pub fn email_resend_wait_secs(&self, now_ms: u64) -> u64 {
        self.shown_email_run()
            .map_or(0, |r| r.resend_at_ms.saturating_sub(now_ms).div_ceil(1000))
    }

    /// Moves by one whenever the dialog must empty the code field: a new challenge, `invalid_code`, or a
    /// dropped challenge (`code_expired`, `switch_from_signed_in_device`, a Resend that lost it, "Use a
    /// different email").
    pub fn email_code_epoch(&self) -> u64 {
        self.email_epoch
    }

    /// A refused code leaves the account as the verify found it: signed out stays signed out; an error that
    /// holds a stored session stays, with its sign-out and its list retries; a state the first list had not
    /// settled yet asks again (that list's answer was dropped while the code was checked).
    fn resume_after_refused_code(
        &mut self,
        resume: Option<Resume>,
        now_ms: u64,
        out: &mut Vec<AccountAction>,
    ) {
        match resume {
            Some(Resume {
                state: AccountState::Error(e),
                retry_list,
            }) if self.has_session => {
                self.state = AccountState::Error(e);
                self.retry_list = retry_list;
                if retry_list {
                    self.arm(self.last_list_ms + LIST_INTERVAL_MS, now_ms, out);
                }
            }
            Some(Resume {
                state: AccountState::Unknown,
                ..
            }) => {
                self.state = AccountState::Unknown;
                if !self.list_in_flight {
                    self.list_in_flight = true;
                    self.last_list_ms = now_ms;
                    out.push(AccountAction::CallList);
                }
            }
            _ => self.state = AccountState::LoggedOut,
        }
    }

    /// Forgets the email run; the answer of a code request still on its way is owed and ignored.
    fn drop_email_run(&mut self) {
        if let Some(run) = self.email_run.take()
            && run.step == EmailStep::Sending
        {
            self.stale_email_begins += 1;
        }
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
                self.state = if cancelled {
                    AccountState::LoggedOut
                } else {
                    AccountState::Error(e)
                };
            }
            GooglePurpose::Link => {
                if !cancelled {
                    self.notice = Some(e);
                    self.notice_is_methods = false;
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
        self.notice_is_methods = false;
        self.google = None;
        self.email = None;
        self.auth_method = None;
        self.session_requested = false;
        self.methods = None;
        self.removing = None;
        self.has_session = false;
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
                self.has_session = match &result {
                    Ok(_) => true,
                    Err(e) => !matches!(
                        e.code.as_str(),
                        "not_logged_in" | "unauthorized" | "http_401"
                    ),
                };
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
                                    self.drop_email_run();
                                    self.session_ended_by_server = false;
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
                            || (self.logged_in()
                                && matches!(e.code.as_str(), "unauthorized" | "http_401")) =>
                    {
                        // The server (or a revoked token) ended the session while signed in: the notice
                        // asks for sign-in again.
                        if self.logged_in() {
                            self.session_ended_by_server = true;
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
                        self.has_session = true;
                        self.register_requested = false;
                        self.list_in_flight = true;
                        self.last_list_ms = now_ms;
                        out.push(AccountAction::CallList);
                    }
                    Err(e) => self.state = AccountState::Error(e),
                }
            }
            AccountEvent::Registered(result) => match result {
                // Either answer means the core sent the register with a session.
                Ok(_) => {
                    self.has_session = true;
                    self.list_in_flight = true;
                    self.last_list_ms = now_ms;
                    out.push(AccountAction::CallList);
                }
                Err(e) => {
                    self.has_session = true;
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
                self.notice_is_methods = false;
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
                    // An email run on the first screen gives way (with its failure); one with a code on its
                    // way, shown or being checked refuses Google (one sign-in flow at a time).
                    GooglePurpose::SignIn
                        if self.accepts_login()
                            && self
                                .email_run
                                .as_ref()
                                .is_none_or(|r| r.step == EmailStep::Email) =>
                    {
                        self.drop_email_run();
                        self.state = AccountState::LoggingIn;
                        self.retry_list = false;
                        self.login_in_flight = true;
                        self.notice = None;
                    }
                    GooglePurpose::Link if self.needs_google_switch() => self.notice = None,
                    _ => return out,
                }
                self.google = Some(GoogleRun {
                    purpose,
                    flow_id: None,
                });
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
                        self.has_session = true;
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
                let Some(run) = self.google.as_ref() else {
                    return out;
                };
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
                        Err(e) => {
                            self.notice = Some(e);
                            self.notice_is_methods = true;
                        }
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
            AccountEvent::SignInMethodRemoved {
                identity_id,
                result,
            } => {
                if self.removing.as_deref() != Some(identity_id.as_str()) {
                    return out;
                }
                self.removing = None;
                match result {
                    Ok(()) => out.push(AccountAction::CallListSignInMethods),
                    Err(e) => {
                        self.notice = Some(e);
                        self.notice_is_methods = true;
                    }
                }
            }
            AccountEvent::EmailCodeRequested { email, locale } => {
                let free = self
                    .email_run
                    .as_ref()
                    .is_none_or(|r| r.step == EmailStep::Email);
                if self.google.is_some()
                    || !self.accepts_login()
                    || self.logged_in()
                    || !free
                    || !email_looks_valid(&email)
                {
                    return out;
                }
                let email = email.trim().to_string();
                self.email_run = Some(EmailRun {
                    step: EmailStep::Sending,
                    shown: true,
                    email: email.clone(),
                    locale: locale.clone(),
                    sent_to: None,
                    challenge: None,
                    error: None,
                    resend_at_ms: 0,
                    resume: None,
                });
                out.push(AccountAction::CallEmailBegin { email, locale });
            }
            AccountEvent::EmailEdited => {
                if let Some(run) = self
                    .email_run
                    .as_mut()
                    .filter(|r| r.shown && r.step == EmailStep::Email)
                {
                    run.error = None;
                }
            }
            AccountEvent::EmailResendRequested => {
                if self.google.is_some() {
                    return out;
                }
                let Some(run) = self
                    .email_run
                    .as_mut()
                    .filter(|r| r.shown && r.step == EmailStep::Code)
                else {
                    return out;
                };
                if run.resend_at_ms > now_ms {
                    return out;
                }
                run.step = EmailStep::Sending;
                run.error = None;
                out.push(AccountAction::CallEmailBegin {
                    email: run.email.clone(),
                    locale: run.locale.clone(),
                });
            }
            AccountEvent::EmailBegun(result) => {
                if self.stale_email_begins > 0 {
                    self.stale_email_begins -= 1;
                    return out;
                }
                let Some(run) = self
                    .email_run
                    .as_mut()
                    .filter(|r| r.step == EmailStep::Sending)
                else {
                    return out;
                };
                match result {
                    Ok(c) => {
                        run.step = EmailStep::Code;
                        run.challenge = Some(c.challenge_id);
                        run.sent_to = Some(c.email);
                        run.error = None;
                        run.resend_at_ms = now_ms.saturating_add(c.resend_in.saturating_mul(1000));
                        self.email_epoch += 1;
                    }
                    // A Resend: the code step stays, Resend unlocks. A relay that lost the address's code
                    // (the mail failed, or the feature is off) leaves nothing to verify (D2).
                    Err(e) if run.sent_to.is_some() => {
                        run.step = EmailStep::Code;
                        run.resend_at_ms = 0;
                        if matches!(
                            e.code.as_str(),
                            "email_send_failed" | "email_sign_in_disabled"
                        ) {
                            run.challenge = None;
                            self.email_epoch += 1;
                        }
                        run.error = Some(e);
                    }
                    Err(e) => {
                        run.step = EmailStep::Email;
                        run.error = Some(e);
                    }
                }
            }
            AccountEvent::EmailCodeSubmitted(text) => {
                if self.google.is_some() || !self.accepts_login() {
                    return out;
                }
                let Some(run) = self
                    .email_run
                    .as_mut()
                    .filter(|r| r.shown && r.step == EmailStep::Code)
                else {
                    return out;
                };
                let (Some(challenge_id), Some(code)) = (run.challenge.clone(), code_digits(&text))
                else {
                    return out;
                };
                run.step = EmailStep::Verifying;
                run.error = None;
                run.resume = Some(Resume {
                    state: self.state.clone(),
                    retry_list: self.retry_list,
                });
                // As `GoogleRequested(SignIn)`: the sign-in is under way.
                self.state = AccountState::LoggingIn;
                self.retry_list = false;
                self.login_in_flight = true;
                self.notice = None;
                out.push(AccountAction::CallEmailFinish { challenge_id, code });
            }
            AccountEvent::EmailFinished {
                challenge_id,
                result,
            } => {
                let verifying = self.email_run.as_ref().is_some_and(|r| {
                    r.step == EmailStep::Verifying
                        && r.challenge.as_deref() == Some(challenge_id.as_str())
                });
                if !verifying {
                    return out; // a run that already ended, or another challenge
                }
                let e = match result {
                    Ok(info) => {
                        // As `GoogleFinished` for `SignIn`.
                        self.email_run = None;
                        self.has_session = true;
                        self.email = Some(info.email);
                        self.auth_method = Some(info.auth_method);
                        self.notice = None;
                        self.login_in_flight = false;
                        self.register_requested = false;
                        self.list_in_flight = true;
                        self.last_list_ms = now_ms;
                        out.push(AccountAction::CallList);
                        return out;
                    }
                    Err(e) => e,
                };
                self.login_in_flight = false;
                let resume = self.email_run.as_mut().and_then(|r| r.resume.take());
                self.resume_after_refused_code(resume, now_ms, &mut out);
                let Some(run) = self.email_run.as_mut().filter(|r| r.shown) else {
                    // The dialog closed meanwhile: nobody sees the failure.
                    self.email_run = None;
                    return out;
                };
                match e.code.as_str() {
                    "invalid_code" => {
                        run.step = EmailStep::Code;
                        self.email_epoch += 1;
                    }
                    "code_expired" => {
                        run.step = EmailStep::Code;
                        run.challenge = None;
                        run.resend_at_ms = 0;
                        self.email_epoch += 1;
                    }
                    "switch_from_signed_in_device" => {
                        run.step = EmailStep::Email;
                        run.challenge = None;
                        run.sent_to = None;
                        run.resend_at_ms = 0;
                        self.email_epoch += 1;
                    }
                    // Rate limit, network, a 5xx, a relay without the feature, …: the code and the
                    // challenge stay, so Verify can be pressed again (D2).
                    _ => run.step = EmailStep::Code,
                }
                run.error = Some(e);
            }
            AccountEvent::EmailChangeRequested => {
                if let Some(run) = self
                    .email_run
                    .as_mut()
                    .filter(|r| r.shown && r.step == EmailStep::Code)
                {
                    run.step = EmailStep::Email;
                    run.challenge = None;
                    run.sent_to = None;
                    run.error = None;
                    run.resend_at_ms = 0;
                    self.email_epoch += 1;
                }
            }
            AccountEvent::EmailCancelled => match self.email_run.as_ref().map(|r| r.step) {
                // A verify already sent cannot be cancelled: the run hides and its answer still applies.
                Some(EmailStep::Verifying) => {
                    if let Some(run) = self.email_run.as_mut() {
                        run.shown = false;
                    }
                }
                Some(_) => self.drop_email_run(),
                None => {}
            },
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core_api::{EmailChallenge, GoogleBegin, GoogleSignIn, SessionInfo, SignInMethod};
    use crate::email_sign_in::EmailStep;

    fn m(id: &str, this: bool) -> MachineInfo {
        MachineInfo {
            machine_id: id.into(),
            name: id.into(),
            platform: "windows".into(),
            online: true,
            last_seen_unix: 0,
            fingerprint: "f".into(),
            is_this_machine: this,
            can_host: false,
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
        assert!(
            f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 3)
                .is_empty()
        );
        assert!(
            f.on(AccountEvent::GoogleRequested(GooglePurpose::Link), 3)
                .is_empty()
        );
    }

    #[test]
    fn a_stale_google_finish_is_ignored() {
        let mut f = logged_out();
        f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 2);
        f.on(begun(GooglePurpose::SignIn, "f1"), 3);
        assert!(
            f.on(finished("f0", Ok(google_done("g@x", "google"))), 4)
                .is_empty()
        );
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
        assert!(
            f.on(AccountEvent::Tick(16_000), 16_000)
                .contains(&AccountAction::CallList)
        );
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
        f.on(
            finished("f1", Err(CoreErr::new("email_in_use", "x"))),
            1_400,
        );
        assert!(matches!(f.state(), AccountState::LoggedIn { .. }));
        assert_eq!(f.notice().map(|e| e.code.as_str()), Some("email_in_use"));
        assert!(f.needs_google_switch());
        // a cancelled link leaves no notice
        let mut g = logged_in();
        g.on(session(Some("old@x"), "password"), 1_100);
        g.on(AccountEvent::GoogleRequested(GooglePurpose::Link), 1_200);
        g.on(begun(GooglePurpose::Link, "f1"), 1_300);
        g.on(
            finished("f1", Err(CoreErr::new("google_cancelled", ""))),
            1_400,
        );
        assert!(g.notice().is_none());
    }

    #[test]
    fn link_is_refused_unless_signed_in_with_a_password() {
        let mut f = logged_out();
        assert!(
            f.on(AccountEvent::GoogleRequested(GooglePurpose::Link), 2)
                .is_empty()
        );
        let mut g = logged_in();
        g.on(session(Some("g@x"), "google"), 1_100);
        assert!(
            g.on(AccountEvent::GoogleRequested(GooglePurpose::Link), 1_200)
                .is_empty()
        );
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

    /// Ruling 29: no dialog opens by itself; the notice stays until the next sign-in.
    #[test]
    fn a_server_sign_out_shows_the_notice_until_the_next_sign_in() {
        for code in ["not_logged_in", "unauthorized", "http_401"] {
            let mut f = logged_in();
            f.on(AccountEvent::Tick(16_000), 16_000);
            f.on(
                AccountEvent::ListResult(Err(CoreErr::new(code, ""))),
                16_000,
            );
            assert_eq!(f.state(), &AccountState::LoggedOut, "{code}");
            assert!(f.session_ended_by_server(), "{code}");
            assert!(
                f.session_ended_by_server(),
                "{code}: reading it changes nothing"
            );
            f.on(AccountEvent::Tick(40_000), 40_000);
            f.on(AccountEvent::Started, 40_001);
            f.on(
                AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))),
                40_002,
            );
            assert!(
                f.session_ended_by_server(),
                "{code}: ticks and a restart keep it"
            );
            // Signing in again (an email code) clears it once the flow is LoggedIn.
            assert_eq!(f.on(send(), 41_000), vec![begin_call()]);
            f.on(AccountEvent::EmailBegun(Ok(challenge("c1"))), 41_000);
            f.on(submit("123456"), 41_100);
            f.on(email_finished("c1", Ok(done())), 41_200);
            assert!(f.session_ended_by_server(), "{code}: not before LoggedIn");
            f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), 41_300);
            assert!(matches!(f.state(), AccountState::LoggedIn { .. }), "{code}");
            assert!(!f.session_ended_by_server(), "{code}");
        }
        // No session at start: signed out, no notice.
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        f.on(
            AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))),
            1,
        );
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert!(!f.session_ended_by_server());
        // The person signed out: no notice.
        let mut f = logged_in();
        f.on(AccountEvent::LogoutRequested, 2_000);
        f.on(AccountEvent::LogoutResult(Ok(())), 2_100);
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert!(!f.session_ended_by_server());
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
            AccountEvent::SignInMethodsResult(Ok(vec![
                method("g1", "google"),
                method("a1", "apple"),
            ])),
            1_200,
        );
        assert_eq!(f.sign_in_methods().map(<[_]>::len), Some(2));
        assert_eq!(
            f.on(
                AccountEvent::RemoveSignInMethodRequested("a1".into()),
                1_300
            ),
            vec![AccountAction::CallRemoveSignInMethod("a1".into())]
        );
        assert_eq!(f.removing_sign_in_method(), Some("a1"));
        assert!(
            f.on(
                AccountEvent::RemoveSignInMethodRequested("a2".into()),
                1_310
            )
            .is_empty()
        );
        assert_eq!(
            f.on(
                AccountEvent::SignInMethodRemoved {
                    identity_id: "a1".into(),
                    result: Ok(())
                },
                1_400
            ),
            vec![AccountAction::CallListSignInMethods]
        );
        assert_eq!(f.removing_sign_in_method(), None);
        f.on(
            AccountEvent::RemoveSignInMethodRequested("a1".into()),
            1_500,
        );
        f.on(
            AccountEvent::SignInMethodRemoved {
                identity_id: "a1".into(),
                result: Err(net()),
            },
            1_600,
        );
        assert_eq!(f.notice(), Some(&net()));
    }

    #[test]
    fn logout_clears_email_method_and_methods() {
        let mut f = logged_in();
        f.on(session(Some("a@b.c"), "password"), 1_100);
        f.on(
            AccountEvent::SignInMethodsResult(Ok(vec![method("g1", "google")])),
            1_200,
        );
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

    // ----- sign-out in the error state (R4 Major 6) -----

    #[test]
    fn sign_out_is_offered_in_the_error_state_and_ends_the_retry_loop() {
        let mut f = logged_out();
        assert!(!f.can_sign_out());
        f.on(
            AccountEvent::LoginSubmitted {
                email: "a@b.c".into(),
                password: "pw".into(),
            },
            2,
        );
        assert!(!f.can_sign_out(), "signing in");
        assert_eq!(
            f.on(AccountEvent::LoginResult(Ok(login_info())), 3),
            vec![AccountAction::CallList]
        );
        let bad = CoreErr::new(
            "bad_response",
            "machines.list: invalid type: null, expected a string",
        );
        f.on(AccountEvent::ListResult(Err(bad.clone())), 4);
        assert_eq!(f.state(), &AccountState::Error(bad));
        assert!(f.can_sign_out());
        assert_eq!(
            f.on(AccountEvent::LogoutRequested, 5),
            vec![AccountAction::CallLogout]
        );
        f.on(AccountEvent::LogoutResult(Ok(())), 6);
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert!(!f.can_sign_out());
        assert!(f.on(AccountEvent::Tick(100_000), 100_000).is_empty());

        // the same after a Google sign-in
        let mut g = logged_out();
        g.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 2);
        g.on(begun(GooglePurpose::SignIn, "f1"), 3);
        g.on(finished("f1", Ok(google_done("g@x", "google"))), 4);
        g.on(AccountEvent::ListResult(Err(net())), 5);
        assert!(matches!(g.state(), AccountState::Error(_)));
        assert!(g.can_sign_out());
    }

    #[test]
    fn no_sign_out_after_a_first_sign_in_failed() {
        let mut f = logged_out();
        f.on(
            AccountEvent::LoginSubmitted {
                email: "a@b.c".into(),
                password: "x".into(),
            },
            2,
        );
        f.on(
            AccountEvent::LoginResult(Err(CoreErr::new("invalid_credentials", ""))),
            3,
        );
        assert!(matches!(f.state(), AccountState::Error(e) if e.code == "invalid_credentials"));
        assert!(!f.can_sign_out());
        assert!(!AccountFlow::new().can_sign_out(), "unknown");
    }

    #[test]
    fn startup_error_with_a_session_offers_sign_out() {
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        f.on(AccountEvent::ListResult(Err(net())), 10);
        assert!(matches!(f.state(), AccountState::Error(e) if e.code == "network"));
        assert!(f.can_sign_out());
        // a list the server refused: the core forgot the session
        f.on(AccountEvent::Tick(15_010), 15_010);
        f.on(
            AccountEvent::ListResult(Err(CoreErr::new("unauthorized", ""))),
            15_011,
        );
        assert!(matches!(f.state(), AccountState::Error(_)));
        assert!(!f.can_sign_out());
    }

    #[test]
    fn register_failure_offers_sign_out() {
        let mut f = logged_out();
        f.on(
            AccountEvent::LoginSubmitted {
                email: "a@b.c".into(),
                password: "pw".into(),
            },
            2,
        );
        f.on(AccountEvent::LoginResult(Ok(login_info())), 3);
        assert_eq!(
            f.on(AccountEvent::ListResult(Ok(vec![])), 4),
            vec![AccountAction::CallRegister]
        );
        f.on(
            AccountEvent::Registered(Err(CoreErr::new("invalid_machine", "x"))),
            5,
        );
        assert!(matches!(f.state(), AccountState::Error(e) if e.code == "invalid_machine"));
        assert!(f.can_sign_out());
        // signed in: always
        assert!(logged_in().can_sign_out());
    }

    /// Spec §4.7 layer (2): no email, machine name or device name in `Debug` output (logs, panics).
    #[test]
    fn account_debug_never_shows_emails_or_machine_names() {
        const SECRETS: [&str; 4] = ["secret.person", "Phú's MacBook", "Bếp-PC", "iPhone của Phú"];
        let check = |what: &str, text: String| {
            for s in SECRETS {
                assert!(!text.contains(s), "{what} shows {s:?}: {text}");
            }
        };
        let email = "secret.person@example.com";
        let mac = MachineInfo {
            name: "Phú's MacBook".into(),
            platform: "macos".into(),
            ..m("mac", false)
        };
        let pc = MachineInfo {
            name: "Bếp-PC".into(),
            ..m("me", true)
        };
        let method = SignInMethod {
            email: email.into(),
            linked_via_device_name: Some("iPhone của Phú".into()),
            ..method("a1", "apple")
        };

        let mut f = logged_out();
        f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 2);
        f.on(begun(GooglePurpose::SignIn, "f1"), 3);
        f.on(finished("f1", Ok(google_done(email, "google"))), 4);
        f.on(
            AccountEvent::ListResult(Ok(vec![mac.clone(), pc.clone()])),
            5,
        );
        f.on(
            AccountEvent::SignInMethodsResult(Ok(vec![method.clone()])),
            6,
        );
        assert_eq!(f.email(), Some(email));
        assert!(matches!(f.state(), AccountState::LoggedIn { .. }));
        check("flow", format!("{f:?}"));
        check("flow (pretty)", format!("{f:#?}"));

        let submitted = AccountEvent::LoginSubmitted {
            email: email.into(),
            password: "pw".into(),
        };
        check("LoginSubmitted", format!("{submitted:?}"));
        let mut g = logged_out();
        let actions = g.on(submitted, 7);
        assert!(matches!(actions[..], [AccountAction::CallLogin { .. }]));
        check("CallLogin", format!("{actions:?}"));
        check(
            "ListResult",
            format!("{:?}", AccountEvent::ListResult(Ok(vec![mac.clone()]))),
        );
        for m in [&mac, &pc] {
            check("MachineInfo", format!("{m:?} {m:#?}"));
        }
        check("SignInMethod", format!("{method:?} {method:#?}"));
    }

    #[test]
    fn delete_account_url_is_the_privacy_page() {
        assert_eq!(
            DELETE_ACCOUNT_URL,
            "https://shellx.pro/privacy#delete-account"
        );
    }

    // ----- email code sign-in (D2, D3, D4) -----

    fn challenge(id: &str) -> EmailChallenge {
        EmailChallenge {
            challenge_id: id.into(),
            email: "foo@bar.com".into(),
            expires_in: 600,
            resend_in: 60,
        }
    }

    fn done() -> GoogleSignIn {
        google_done("foo@bar.com", "email")
    }

    fn email_finished(id: &str, r: Result<GoogleSignIn, CoreErr>) -> AccountEvent {
        AccountEvent::EmailFinished {
            challenge_id: id.into(),
            result: r,
        }
    }

    fn err(code: &str) -> CoreErr {
        CoreErr::new(code, "x")
    }

    fn send() -> AccountEvent {
        AccountEvent::EmailCodeRequested {
            email: " Foo@Bar.com ".into(),
            locale: "vi".into(),
        }
    }

    fn begin_call() -> AccountAction {
        AccountAction::CallEmailBegin {
            email: "Foo@Bar.com".into(),
            locale: "vi".into(),
        }
    }

    fn submit(text: &str) -> AccountEvent {
        AccountEvent::EmailCodeSubmitted(text.into())
    }

    fn finish_call(id: &str, code: &str) -> AccountAction {
        AccountAction::CallEmailFinish {
            challenge_id: id.into(),
            code: code.into(),
        }
    }

    fn error_code(f: &AccountFlow) -> Option<&str> {
        f.email_error().map(|e| e.code.as_str())
    }

    /// `send()`, then the relay's challenge "c1", both at `now`: the code step.
    fn to_code(f: &mut AccountFlow, now: u64) {
        assert_eq!(f.on(send(), now), vec![begin_call()]);
        assert!(
            f.on(AccountEvent::EmailBegun(Ok(challenge("c1"))), now)
                .is_empty()
        );
        assert_eq!(f.email_step(), Some(EmailStep::Code));
    }

    #[test]
    fn email_sign_in_runs_email_code_verify_then_lists() {
        let mut f = logged_out();
        assert_eq!(f.email_code_epoch(), 0);
        assert_eq!(f.on(send(), 2), vec![begin_call()]);
        assert_eq!(f.email_step(), Some(EmailStep::Sending));
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert!(
            f.on(AccountEvent::EmailBegun(Ok(challenge("c1"))), 3)
                .is_empty()
        );
        assert_eq!(f.email_step(), Some(EmailStep::Code));
        assert_eq!(f.email_sent_to(), Some("foo@bar.com"));
        assert!(f.email_can_verify());
        assert_eq!(f.email_code_epoch(), 1);
        assert_eq!(
            f.on(submit(" 123 456\n"), 4),
            vec![finish_call("c1", "123456")]
        );
        assert_eq!(f.email_step(), Some(EmailStep::Verifying));
        assert_eq!(f.state(), &AccountState::LoggingIn);
        assert!(f.login_in_flight());
        assert_eq!(
            f.on(email_finished("c1", Ok(done())), 5),
            vec![AccountAction::CallList]
        );
        assert_eq!(f.email_step(), None);
        let acts = f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), 6);
        assert!(matches!(f.state(), AccountState::LoggedIn { .. }));
        assert!(!acts.contains(&AccountAction::CallSession), "{acts:?}");
        assert_eq!(f.email(), Some("foo@bar.com"));
        assert_eq!(f.auth_method(), Some("email"));
        assert!(!f.needs_google_switch());
    }

    #[test]
    fn send_code_needs_a_plausible_ascii_address_and_runs_once() {
        let mut f = logged_out();
        for bad in ["nope", "phu@ẽample.com"] {
            let ev = AccountEvent::EmailCodeRequested {
                email: bad.into(),
                locale: "en".into(),
            };
            assert!(f.on(ev, 2).is_empty(), "{bad}");
            assert_eq!(f.email_step(), None, "{bad}");
        }
        assert_eq!(f.on(send(), 3), vec![begin_call()]);
        assert!(f.on(send(), 4).is_empty());
        assert_eq!(f.email_step(), Some(EmailStep::Sending));
    }

    #[test]
    fn editing_the_address_clears_the_email_failure() {
        let mut f = logged_out();
        f.on(send(), 2);
        f.on(AccountEvent::EmailBegun(Err(err("rate_limited"))), 3);
        assert_eq!(f.email_step(), Some(EmailStep::Email));
        assert_eq!(error_code(&f), Some("rate_limited"));
        assert!(f.on(AccountEvent::EmailEdited, 4).is_empty());
        assert_eq!(f.email_error(), None);
        assert_eq!(f.email_step(), Some(EmailStep::Email));

        let mut g = logged_out();
        assert!(g.on(AccountEvent::EmailEdited, 2).is_empty());
        assert_eq!(g.email_step(), None);

        // On the code step an edit changes nothing (the email field is not drawn there).
        let mut h = logged_out();
        to_code(&mut h, 1_000);
        assert_eq!(
            h.on(AccountEvent::EmailResendRequested, 61_000),
            vec![begin_call()]
        );
        h.on(AccountEvent::EmailBegun(Err(err("rate_limited"))), 61_000);
        assert!(h.on(AccountEvent::EmailEdited, 61_000).is_empty());
        assert_eq!(error_code(&h), Some("rate_limited"));
        assert_eq!(h.email_step(), Some(EmailStep::Code));
    }

    #[test]
    fn a_failed_send_returns_to_the_first_screen_with_the_error() {
        for code in [
            "invalid_email",
            "disposable_email",
            "rate_limited",
            "email_send_failed",
            "network",
            "http_503",
        ] {
            let mut f = logged_out();
            f.on(send(), 2);
            assert!(f.on(AccountEvent::EmailBegun(Err(err(code))), 3).is_empty());
            assert_eq!(f.email_step(), Some(EmailStep::Email), "{code}");
            assert_eq!(error_code(&f), Some(code));
            assert_eq!(f.state(), &AccountState::LoggedOut, "{code}");
            assert!(!f.email_can_verify(), "{code}");
            assert_eq!(f.on(send(), 4), vec![begin_call()], "{code}");
            assert_eq!(f.email_error(), None, "{code}");
        }
    }

    #[test]
    fn a_relay_without_email_sign_in_keeps_the_app_signed_out() {
        let mut f = logged_out();
        f.on(send(), 2);
        f.on(
            AccountEvent::EmailBegun(Err(err("email_sign_in_disabled"))),
            3,
        );
        assert_eq!(f.email_step(), Some(EmailStep::Email));
        assert_eq!(error_code(&f), Some("email_sign_in_disabled"));
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert_eq!(f.notice(), None);
    }

    #[test]
    fn a_wrong_code_empties_the_field_and_stays_on_the_code_step() {
        let mut f = logged_out();
        to_code(&mut f, 1_000);
        let epoch = f.email_code_epoch();
        f.on(submit("123456"), 2_000);
        assert!(
            f.on(email_finished("c1", Err(err("invalid_code"))), 2_100)
                .is_empty()
        );
        assert_eq!(f.email_step(), Some(EmailStep::Code));
        assert_eq!(error_code(&f), Some("invalid_code"));
        assert!(f.email_can_verify());
        assert_eq!(f.email_code_epoch(), epoch + 1);
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert!(!f.login_in_flight());
        assert_eq!(
            f.on(submit("654321"), 2_200),
            vec![finish_call("c1", "654321")]
        );
    }

    #[test]
    fn an_expired_code_drops_the_challenge_and_unlocks_resend() {
        let mut f = logged_out();
        to_code(&mut f, 1_000);
        let epoch = f.email_code_epoch();
        f.on(submit("123456"), 2_000);
        f.on(email_finished("c1", Err(err("code_expired"))), 5_000);
        assert_eq!(f.email_step(), Some(EmailStep::Code));
        assert_eq!(error_code(&f), Some("code_expired"));
        assert!(!f.email_can_verify());
        assert_eq!(f.email_resend_wait_secs(5_000), 0);
        assert_eq!(f.email_code_epoch(), epoch + 1);
        assert!(f.on(submit("123456"), 5_000).is_empty());
        assert_eq!(
            f.on(AccountEvent::EmailResendRequested, 5_000),
            vec![begin_call()]
        );
    }

    #[test]
    fn a_switch_answer_returns_to_the_first_screen() {
        let mut f = logged_out();
        to_code(&mut f, 1_000);
        let epoch = f.email_code_epoch();
        f.on(submit("123456"), 2_000);
        f.on(
            email_finished("c1", Err(err("switch_from_signed_in_device"))),
            5_000,
        );
        assert_eq!(f.email_step(), Some(EmailStep::Email));
        assert_eq!(error_code(&f), Some("switch_from_signed_in_device"));
        assert_eq!(f.email_sent_to(), None);
        assert!(!f.email_can_verify());
        assert_eq!(f.email_resend_wait_secs(5_000), 0);
        assert_eq!(f.email_code_epoch(), epoch + 1);
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert_eq!(f.on(send(), 5_100), vec![begin_call()]);
    }

    #[test]
    fn a_disabled_relay_on_verify_keeps_the_code() {
        let mut f = logged_out();
        to_code(&mut f, 1_000);
        let epoch = f.email_code_epoch();
        f.on(submit("123456"), 2_000);
        f.on(
            email_finished("c1", Err(err("email_sign_in_disabled"))),
            2_000,
        );
        assert_eq!(f.email_step(), Some(EmailStep::Code));
        assert_eq!(error_code(&f), Some("email_sign_in_disabled"));
        assert!(f.email_can_verify());
        assert_eq!(f.email_resend_wait_secs(2_000), 59);
        assert_eq!(f.email_code_epoch(), epoch);
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert_eq!(
            f.on(submit("123456"), 2_100),
            vec![finish_call("c1", "123456")]
        );
    }

    #[test]
    fn a_verify_refused_for_rate_network_or_server_keeps_the_code() {
        for code in ["rate_limited", "network", "http_503", "invalid_device"] {
            let mut f = logged_out();
            to_code(&mut f, 1_000);
            let epoch = f.email_code_epoch();
            f.on(submit("123456"), 2_000);
            f.on(email_finished("c1", Err(err(code))), 2_000);
            assert_eq!(f.email_step(), Some(EmailStep::Code), "{code}");
            assert_eq!(error_code(&f), Some(code));
            assert!(f.email_can_verify(), "{code}");
            assert_eq!(f.email_resend_wait_secs(2_000), 59, "{code}");
            assert_eq!(f.email_code_epoch(), epoch, "{code}");
            assert_eq!(f.state(), &AccountState::LoggedOut, "{code}");
            assert!(!f.login_in_flight(), "{code}");
            assert_eq!(
                f.on(submit("123456"), 2_100),
                vec![finish_call("c1", "123456")],
                "{code}"
            );
        }
    }

    #[test]
    fn verify_runs_once_for_a_double_submit() {
        let mut f = logged_out();
        to_code(&mut f, 1_000);
        assert_eq!(
            f.on(submit("123456"), 2_000),
            vec![finish_call("c1", "123456")]
        );
        assert!(f.on(submit("123456"), 2_000).is_empty());
        let mut g = logged_out();
        to_code(&mut g, 1_000);
        for s in ["12345", "1234567"] {
            assert!(g.on(submit(s), 2_000).is_empty(), "{s}");
            assert_eq!(g.email_step(), Some(EmailStep::Code), "{s}");
        }
    }

    #[test]
    fn resend_is_locked_for_the_relays_resend_in() {
        let mut f = logged_out();
        to_code(&mut f, 1_000);
        assert_eq!(f.email_resend_wait_secs(1_000), 60);
        assert_eq!(f.email_resend_wait_secs(1_500), 60);
        assert_eq!(f.email_resend_wait_secs(60_200), 1);
        assert_eq!(f.email_resend_wait_secs(61_000), 0);
        assert!(f.on(AccountEvent::EmailResendRequested, 30_000).is_empty());
        assert_eq!(
            f.on(AccountEvent::EmailResendRequested, 61_000),
            vec![begin_call()]
        );
        assert_eq!(f.email_step(), Some(EmailStep::Sending));
        assert_eq!(f.email_sent_to(), Some("foo@bar.com"));
        let epoch = f.email_code_epoch();
        f.on(AccountEvent::EmailBegun(Ok(challenge("c2"))), 62_000);
        assert_eq!(f.email_resend_wait_secs(62_000), 60);
        assert_eq!(f.email_code_epoch(), epoch + 1);
        assert_eq!(
            f.on(submit("123456"), 62_100),
            vec![finish_call("c2", "123456")]
        );
    }

    #[test]
    fn a_failed_resend_keeps_the_challenge_for_rate_limited_and_network() {
        for code in ["rate_limited", "network", "http_503"] {
            let mut f = logged_out();
            to_code(&mut f, 1_000);
            let epoch = f.email_code_epoch();
            f.on(AccountEvent::EmailResendRequested, 61_000);
            f.on(AccountEvent::EmailBegun(Err(err(code))), 61_000);
            assert_eq!(f.email_step(), Some(EmailStep::Code), "{code}");
            assert_eq!(error_code(&f), Some(code));
            assert_eq!(f.email_resend_wait_secs(61_000), 0, "{code}");
            assert!(f.email_can_verify(), "{code}");
            assert_eq!(f.email_code_epoch(), epoch, "{code}");
            assert_eq!(
                f.on(AccountEvent::EmailResendRequested, 61_000),
                vec![AccountAction::CallEmailBegin {
                    email: "Foo@Bar.com".into(),
                    locale: "vi".into()
                }],
                "{code}"
            );
            f.on(AccountEvent::EmailBegun(Err(err(code))), 61_000);
            assert_eq!(f.email_step(), Some(EmailStep::Code), "{code}");
            assert!(f.email_can_verify(), "{code}");
            // last: a Resend at Verifying is refused
            assert_eq!(
                f.on(submit("123456"), 61_100),
                vec![finish_call("c1", "123456")],
                "{code}"
            );
        }
    }

    #[test]
    fn a_failed_resend_drops_the_challenge_the_relay_lost() {
        for code in ["email_send_failed", "email_sign_in_disabled"] {
            let mut f = logged_out();
            to_code(&mut f, 1_000);
            let epoch = f.email_code_epoch();
            f.on(AccountEvent::EmailResendRequested, 61_000);
            f.on(AccountEvent::EmailBegun(Err(err(code))), 61_000);
            assert_eq!(f.email_step(), Some(EmailStep::Code), "{code}");
            assert_eq!(error_code(&f), Some(code));
            assert!(!f.email_can_verify(), "{code}");
            assert_eq!(f.email_resend_wait_secs(61_000), 0, "{code}");
            assert_eq!(f.email_code_epoch(), epoch + 1, "{code}");
            assert_eq!(f.email_sent_to(), Some("foo@bar.com"), "{code}");
            assert!(f.on(submit("123456"), 61_100).is_empty(), "{code}");
            assert_eq!(
                f.on(AccountEvent::EmailResendRequested, 61_200),
                vec![begin_call()],
                "{code}"
            );
        }
    }

    #[test]
    fn use_a_different_email_returns_to_the_first_screen() {
        let mut f = logged_out();
        to_code(&mut f, 1_000);
        assert!(f.on(AccountEvent::EmailChangeRequested, 2_000).is_empty());
        assert_eq!(f.email_step(), Some(EmailStep::Email));
        assert_eq!(f.email_sent_to(), None);
        assert_eq!(f.email_error(), None);
        assert!(!f.email_can_verify());
        assert_eq!(f.on(send(), 2_100), vec![begin_call()]);

        let mut g = logged_out();
        to_code(&mut g, 1_000);
        g.on(submit("123456"), 2_000);
        assert!(g.on(AccountEvent::EmailChangeRequested, 2_100).is_empty());
        assert_eq!(g.email_step(), Some(EmailStep::Verifying));
    }

    #[test]
    fn closing_while_sending_ignores_the_late_challenge() {
        let mut f = logged_out();
        f.on(send(), 2);
        assert!(f.on(AccountEvent::EmailCancelled, 3).is_empty());
        assert_eq!(f.email_step(), None);
        assert_eq!(f.on(send(), 4), vec![begin_call()]);
        assert_eq!(f.email_step(), Some(EmailStep::Sending));
        assert!(
            f.on(AccountEvent::EmailBegun(Ok(challenge("c1"))), 5)
                .is_empty()
        );
        assert_eq!(f.email_step(), Some(EmailStep::Sending));
        f.on(AccountEvent::EmailBegun(Ok(challenge("c2"))), 6);
        assert_eq!(f.email_step(), Some(EmailStep::Code));
        assert_eq!(f.on(submit("123456"), 7), vec![finish_call("c2", "123456")]);
    }

    #[test]
    fn closing_while_verifying_still_signs_in_when_the_code_was_right() {
        let mut f = logged_out();
        to_code(&mut f, 1_000);
        f.on(submit("123456"), 2_000);
        assert!(f.on(AccountEvent::EmailCancelled, 2_100).is_empty());
        assert_eq!(f.email_step(), None);
        assert_eq!(f.state(), &AccountState::LoggingIn);
        assert!(f.on(send(), 2_200).is_empty());
        assert!(
            f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 2_300)
                .is_empty()
        );
        assert_eq!(
            f.on(email_finished("c1", Ok(done())), 2_400),
            vec![AccountAction::CallList]
        );
        assert_eq!(f.email(), Some("foo@bar.com"));
    }

    #[test]
    fn closing_while_verifying_a_wrong_code_ends_signed_out_without_an_error() {
        let mut f = logged_out();
        to_code(&mut f, 1_000);
        f.on(submit("123456"), 2_000);
        f.on(AccountEvent::EmailCancelled, 2_100);
        assert!(
            f.on(email_finished("c1", Err(err("invalid_code"))), 2_200)
                .is_empty()
        );
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert_eq!(f.email_step(), None);
        assert_eq!(f.email_error(), None);
        assert_eq!(f.on(send(), 2_300), vec![begin_call()]);
    }

    #[test]
    fn reopening_after_a_close_starts_clean() {
        let mut f = logged_out();
        to_code(&mut f, 1_000);
        assert!(f.on(AccountEvent::EmailCancelled, 2_000).is_empty());
        assert_eq!(f.email_step(), None);
        assert_eq!(f.email_sent_to(), None);
        assert_eq!(f.email_error(), None);
        assert!(!f.email_can_verify());
        f.on(send(), 2_100);
        assert_eq!(f.email_step(), Some(EmailStep::Sending));
    }

    #[test]
    fn a_late_list_result_does_not_reset_the_email_step() {
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        assert_eq!(f.state(), &AccountState::Unknown);
        to_code(&mut f, 1);
        f.on(
            AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))),
            2,
        );
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert_eq!(f.email_step(), Some(EmailStep::Code));
        assert!(f.email_can_verify());
    }

    #[test]
    fn email_and_google_share_the_first_screen() {
        let mut f = logged_out();
        f.on(send(), 2);
        assert!(
            f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 3)
                .is_empty()
        );
        f.on(AccountEvent::EmailBegun(Ok(challenge("c1"))), 4);
        assert!(
            f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 5)
                .is_empty()
        );
        assert_eq!(f.email_step(), Some(EmailStep::Code));

        let mut g = logged_out();
        g.on(send(), 2);
        g.on(AccountEvent::EmailBegun(Err(err("invalid_email"))), 3);
        assert_eq!(g.email_step(), Some(EmailStep::Email));
        assert_eq!(
            g.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 4),
            vec![AccountAction::CallGoogleBegin(GooglePurpose::SignIn)]
        );
        assert_eq!(g.email_step(), None);
        assert_eq!(g.email_error(), None);
        assert!(g.on(send(), 5).is_empty(), "a Google flow is waiting");
        assert_eq!(g.email_step(), None);

        let mut h = logged_in();
        assert!(h.on(send(), 2_000).is_empty());
        assert_eq!(h.email_step(), None);
    }

    #[test]
    fn a_stale_email_finish_is_ignored() {
        let mut f = logged_out();
        to_code(&mut f, 1_000);
        f.on(submit("123456"), 2_000);
        assert!(f.on(email_finished("c0", Ok(done())), 2_100).is_empty());
        assert_eq!(f.email_step(), Some(EmailStep::Verifying));
        assert_eq!(f.email(), None);

        let mut g = logged_out();
        to_code(&mut g, 1_000);
        assert!(g.on(email_finished("c1", Ok(done())), 2_000).is_empty());
        assert_eq!(g.email_step(), Some(EmailStep::Code));
        assert_eq!(g.email(), None);
    }

    /// Ruling 35: the core would run an email finish next to a waiting Google flow, so the flow keeps them apart.
    #[test]
    fn only_one_sign_in_flow_runs_at_a_time() {
        let mut f = logged_out();
        assert_eq!(
            f.on(AccountEvent::GoogleRequested(GooglePurpose::SignIn), 2),
            vec![AccountAction::CallGoogleBegin(GooglePurpose::SignIn)]
        );
        assert_eq!(
            f.on(begun(GooglePurpose::SignIn, "g1"), 3),
            vec![
                AccountAction::OpenBrowser("https://accounts.google.com/x".into()),
                AccountAction::CallGoogleFinish("g1".into())
            ]
        );
        assert!(f.on(send(), 4).is_empty());
        assert!(f.on(submit("123456"), 5).is_empty());
        assert!(f.on(AccountEvent::EmailResendRequested, 6).is_empty());
        assert_eq!(f.email_step(), None);
        assert_eq!(f.google_in_flight(), Some(GooglePurpose::SignIn));
        f.on(finished("g1", Err(err("google_cancelled"))), 7);
        assert_eq!(f.google_in_flight(), None);
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert_eq!(f.on(send(), 8), vec![begin_call()]);
    }

    #[test]
    fn an_email_session_ended_by_the_server_signs_out() {
        let mut f = logged_out();
        to_code(&mut f, 1_000);
        f.on(submit("123456"), 2_000);
        f.on(email_finished("c1", Ok(done())), 2_100);
        f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), 2_200);
        assert!(matches!(f.state(), AccountState::LoggedIn { .. }));
        assert_eq!(f.auth_method(), Some("email"));
        f.on(AccountEvent::Tick(17_200), 17_200);
        f.on(AccountEvent::ListResult(Err(err("unauthorized"))), 17_300);
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert!(f.session_ended_by_server());
        assert_eq!(f.auth_method(), None);
        assert_eq!(f.email(), None);
        assert_eq!(f.email_step(), None);
    }

    #[test]
    fn email_codes_addresses_and_challenges_never_in_debug() {
        const SECRETS: [&str; 4] = ["foo@bar.com", "Foo@Bar.com", "123456", "CH-SECRET"];
        let check = |what: &str, text: String| {
            for s in SECRETS {
                assert!(!text.contains(s), "{what} shows {s:?}: {text}");
            }
        };
        let ch = challenge("CH-SECRET");
        check("EmailCodeRequested", format!("{:?}", send()));
        check(
            "EmailBegun",
            format!("{:?}", AccountEvent::EmailBegun(Ok(ch.clone()))),
        );
        check("EmailCodeSubmitted", format!("{:?}", submit("123456")));
        check(
            "EmailFinished",
            format!("{:?}", email_finished("CH-SECRET", Ok(done()))),
        );
        check("CallEmailBegin", format!("{:?}", begin_call()));
        check(
            "CallEmailFinish",
            format!("{:?}", finish_call("CH-SECRET", "123456")),
        );
        assert_eq!(format!("{:?}", AccountEvent::EmailEdited), "EmailEdited");

        let mut f = logged_out();
        f.on(send(), 2);
        f.on(AccountEvent::EmailBegun(Ok(ch)), 3);
        assert!(f.email_can_verify());
        check("flow", format!("{f:?}"));
        check("flow (pretty)", format!("{f:#?}"));
    }

    // ----- a failed email attempt returns the flow to the state it started from -----

    /// R4 Blocker 1's path: a sign-in whose list the core refused, so `Error` holds a stored session (retry
    /// tick pending at 15_004).
    fn error_with_a_session() -> AccountFlow {
        let mut f = logged_out();
        f.on(
            AccountEvent::LoginSubmitted {
                email: "a@b.c".into(),
                password: "pw".into(),
            },
            2,
        );
        f.on(AccountEvent::LoginResult(Ok(login_info())), 3);
        f.on(AccountEvent::ListResult(Err(err("bad_response"))), 4);
        assert!(matches!(f.state(), AccountState::Error(e) if e.code == "bad_response"));
        assert!(f.can_sign_out());
        f
    }

    fn scheduled_tick(acts: &[AccountAction]) -> Option<u64> {
        acts.iter().find_map(|a| match a {
            AccountAction::ScheduleTick { at_ms } => Some(*at_ms),
            _ => None,
        })
    }

    fn in_the_list_error(f: &AccountFlow) -> bool {
        matches!(f.state(), AccountState::Error(e) if e.code == "bad_response")
    }

    #[test]
    fn a_failed_verify_returns_to_the_state_it_started_from() {
        // Signed out: back to LoggedOut, and a right code then signs in.
        let mut f = logged_out();
        to_code(&mut f, 1_000);
        f.on(submit("123456"), 2_000);
        f.on(email_finished("c1", Err(err("invalid_code"))), 2_100);
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert!(!f.can_sign_out());
        f.on(submit("654321"), 2_200);
        assert_eq!(
            f.on(email_finished("c1", Ok(done())), 2_300),
            vec![AccountAction::CallList]
        );
        f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), 2_400);
        assert!(matches!(f.state(), AccountState::LoggedIn { .. }));

        // An error that holds a session: that error stays, with "Sign out" and the list retries.
        let mut g = error_with_a_session();
        to_code(&mut g, 1_000);
        assert!(
            in_the_list_error(&g),
            "sending a code changes no account state"
        );
        g.on(submit("123456"), 2_000);
        assert_eq!(g.state(), &AccountState::LoggingIn);
        // The retry tick fires while the code is checked: nothing lists then.
        assert!(g.on(AccountEvent::Tick(15_004), 15_004).is_empty());
        let acts = g.on(email_finished("c1", Err(err("invalid_code"))), 15_100);
        assert!(in_the_list_error(&g), "{:?}", g.state());
        assert!(g.can_sign_out());
        assert!(!g.login_in_flight());
        assert_eq!(g.email_step(), Some(EmailStep::Code));
        assert_eq!(error_code(&g), Some("invalid_code"));
        let at = scheduled_tick(&acts).expect("the list retries go on");
        assert!(
            g.on(AccountEvent::Tick(at), at)
                .contains(&AccountAction::CallList)
        );
        g.on(AccountEvent::ListResult(Err(err("bad_response"))), at);
        assert!(in_the_list_error(&g) && g.can_sign_out());
        // A right code then signs in.
        assert_eq!(
            g.on(submit("654321"), at + 1),
            vec![finish_call("c1", "654321")]
        );
        assert_eq!(
            g.on(email_finished("c1", Ok(done())), at + 2),
            vec![AccountAction::CallList]
        );
        g.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), at + 3);
        assert!(matches!(g.state(), AccountState::LoggedIn { .. }));
        assert_eq!(g.auth_method(), Some("email"));

        // Any other refusal, and a verify the dialog no longer shows, keep that error too.
        for (code, close) in [("network", false), ("invalid_code", true)] {
            let mut h = error_with_a_session();
            to_code(&mut h, 1_000);
            h.on(submit("123456"), 2_000);
            if close {
                h.on(AccountEvent::EmailCancelled, 2_050);
            }
            h.on(email_finished("c1", Err(err(code))), 2_100);
            assert!(in_the_list_error(&h), "{code}: {:?}", h.state());
            assert!(h.can_sign_out(), "{code}");
            assert!(
                h.on(AccountEvent::Tick(15_004), 15_004)
                    .contains(&AccountAction::CallList),
                "{code}"
            );
        }
    }

    /// Checked while the first list was still out: its answer arrived meanwhile and was dropped, so the flow
    /// asks again instead of staying `Unknown`.
    #[test]
    fn a_failed_verify_before_the_first_list_answered_asks_again() {
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        to_code(&mut f, 1);
        f.on(submit("123456"), 2);
        f.on(
            AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))),
            3,
        );
        assert_eq!(f.state(), &AccountState::LoggingIn);
        assert_eq!(
            f.on(email_finished("c1", Err(err("invalid_code"))), 4),
            vec![AccountAction::CallList]
        );
        assert_eq!(f.state(), &AccountState::Unknown);
        f.on(
            AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))),
            5,
        );
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert_eq!(f.email_step(), Some(EmailStep::Code));
        assert!(f.email_can_verify());
    }

    /// The send path never changes the account state, so a failed send or Resend leaves an error that holds a
    /// session as it was.
    #[test]
    fn a_failed_send_leaves_the_account_state_alone() {
        let mut g = error_with_a_session();
        assert_eq!(g.on(send(), 5), vec![begin_call()]);
        assert!(in_the_list_error(&g));
        g.on(AccountEvent::EmailBegun(Err(err("rate_limited"))), 6);
        assert!(in_the_list_error(&g) && g.can_sign_out());
        g.on(send(), 7);
        g.on(AccountEvent::EmailBegun(Ok(challenge("c1"))), 7);
        g.on(AccountEvent::EmailResendRequested, 61_000);
        g.on(
            AccountEvent::EmailBegun(Err(err("email_send_failed"))),
            61_000,
        );
        assert!(in_the_list_error(&g) && g.can_sign_out());
        assert!(
            g.on(AccountEvent::Tick(61_000), 61_000)
                .contains(&AccountAction::CallList)
        );
    }
}
