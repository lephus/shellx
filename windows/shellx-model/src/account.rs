//! Account session state machine: sign-in state, this machine's registration,
//! heartbeat and machine-list refresh. Pure and event driven like
//! `remote_state`: the app runs the returned actions off the UI thread and
//! feeds results back as events. Time is passed in (`now_ms`).
//!
//! The password lives only in `LoginSubmitted` and the `CallLogin` action it
//! produces; the flow never stores it, and `Debug` output redacts it.

use std::fmt;

use crate::core_api::{CoreErr, LoginInfo, Registered};
use crate::sidebar::MachineInfo;

pub const HEARTBEAT_INTERVAL_MS: u64 = 30_000;
pub const LIST_INTERVAL_MS: u64 = 15_000;

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
    LoginSubmitted { email: String, password: String },
    LoginResult(Result<LoginInfo, CoreErr>),
    Registered(Result<Registered, CoreErr>),
    Tick(u64),
    LogoutRequested,
    /// The logout call succeeded.
    LoggedOut,
}

#[derive(Clone, PartialEq, Eq)]
pub enum AccountAction {
    CallList,
    CallLogin { email: String, password: String },
    CallRegister,
    CallHeartbeat,
    CallLogout,
    ScheduleTick { at_ms: u64 },
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
            AccountEvent::LogoutRequested => write!(f, "LogoutRequested"),
            AccountEvent::LoggedOut => write!(f, "LoggedOut"),
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
            AccountAction::ScheduleTick { at_ms } => {
                f.debug_struct("ScheduleTick").field("at_ms", at_ms).finish()
            }
        }
    }
}

#[derive(Debug)]
pub struct AccountFlow {
    state: AccountState,
    /// Last good machine list; kept across network errors.
    machines: Vec<MachineInfo>,
    /// `machines.register` already requested in this sign-in; reset when it fails.
    register_requested: bool,
    list_in_flight: bool,
    last_list_ms: u64,
    last_heartbeat_ms: u64,
    /// A failed list outside LoggedIn is retried on the next tick.
    retry_list: bool,
    /// Tick the app has been asked to deliver and has not delivered yet.
    tick_pending: Option<u64>,
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
            last_list_ms: 0,
            last_heartbeat_ms: 0,
            retry_list: false,
            tick_pending: None,
        }
    }

    pub fn state(&self) -> &AccountState {
        &self.state
    }

    /// The last machine list the server returned (empty when logged out).
    pub fn machines(&self) -> &[MachineInfo] {
        &self.machines
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
        self.retry_list = false;
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
                                self.last_list_ms = now_ms;
                                self.arm(
                                    (self.last_list_ms + LIST_INTERVAL_MS)
                                        .min(self.last_heartbeat_ms + HEARTBEAT_INTERVAL_MS),
                                    now_ms,
                                    &mut out,
                                );
                            }
                            None if !self.register_requested => {
                                self.register_requested = true;
                                self.state = AccountState::LoggingIn;
                                out.push(AccountAction::CallRegister);
                            }
                            None => {
                                self.state = AccountState::Error(CoreErr::new(
                                    "not_registered",
                                    "this machine is missing from the list after registering",
                                ));
                            }
                        }
                    }
                    Err(e) if e.code == "not_logged_in" => {
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
                if self.state == AccountState::LoggingIn {
                    return out;
                }
                self.state = AccountState::LoggingIn;
                self.retry_list = false;
                out.push(AccountAction::CallLogin { email, password });
            }
            AccountEvent::LoginResult(result) => {
                if self.state != AccountState::LoggingIn {
                    return out;
                }
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
            AccountEvent::LogoutRequested => out.push(AccountAction::CallLogout),
            AccountEvent::LoggedOut => {
                self.reset_session();
                self.state = AccountState::LoggedOut;
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
        assert_eq!(f.state(), &AccountState::LoggedIn { machine_id: "me".into() });
        f
    }

    #[test]
    fn not_logged_in_shows_login() {
        let mut f = AccountFlow::new();
        assert_eq!(f.state(), &AccountState::Unknown);
        assert_eq!(f.on(AccountEvent::Started, 0), vec![AccountAction::CallList]);
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
        f.on(AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))), 1);
        let acts = f.on(
            AccountEvent::LoginSubmitted { email: "a@b.c".into(), password: "pw".into() },
            2,
        );
        assert_eq!(
            acts,
            vec![AccountAction::CallLogin { email: "a@b.c".into(), password: "pw".into() }]
        );
        assert_eq!(f.state(), &AccountState::LoggingIn);
        // a double submit while logging in is ignored
        assert!(f
            .on(AccountEvent::LoginSubmitted { email: "x".into(), password: "y".into() }, 3)
            .is_empty());
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
                AccountEvent::Registered(Ok(Registered { machine_id: "me".into(), slot: "s".into() })),
                6
            ),
            vec![AccountAction::CallList]
        );
        let acts = f.on(
            AccountEvent::ListResult(Ok(vec![m("mac", false), m("me", true)])),
            7,
        );
        assert_eq!(f.state(), &AccountState::LoggedIn { machine_id: "me".into() });
        assert!(!acts.contains(&AccountAction::CallRegister));
        assert_eq!(f.machines().len(), 2);
        // a later list that lacks this machine does not loop on register: LoggedIn stays Error-free
        // only when it has it; if the server forgets it after a fresh register request, we stop.
        let mut g = AccountFlow::new();
        g.on(AccountEvent::Started, 0);
        g.on(AccountEvent::ListResult(Ok(vec![])), 1);
        g.on(AccountEvent::Registered(Ok(Registered { machine_id: "x".into(), slot: "s".into() })), 2);
        let acts = g.on(AccountEvent::ListResult(Ok(vec![])), 3);
        assert!(!acts.contains(&AccountAction::CallRegister));
        assert!(matches!(g.state(), AccountState::Error(e) if e.code == "not_registered"));
    }

    #[test]
    fn login_failure_is_error_and_resubmittable() {
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        f.on(AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))), 1);
        f.on(AccountEvent::LoginSubmitted { email: "a".into(), password: "b".into() }, 2);
        f.on(AccountEvent::LoginResult(Err(CoreErr::new("unauthorized", "bad password"))), 3);
        assert!(matches!(f.state(), AccountState::Error(e) if e.code == "unauthorized"));
        // no automatic list retry after a login error
        assert!(f.on(AccountEvent::Tick(60_000), 60_000).is_empty());
        let acts = f.on(AccountEvent::LoginSubmitted { email: "a".into(), password: "c".into() }, 61_000);
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
            if calls.iter().any(|(ct, a)| *ct == t && *a == AccountAction::CallList) {
                f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), t);
            }
            next = sched.expect("a next tick is always scheduled while logged in");
            assert!(next > t);
        }
        let times = |want: AccountAction| -> Vec<u64> {
            calls.iter().filter(|(_, a)| *a == want).map(|(t, _)| *t).collect()
        };
        assert_eq!(times(AccountAction::CallList), vec![16_000, 31_000, 46_000, 61_000]);
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
        assert!(!acts.iter().any(|a| matches!(a, AccountAction::ScheduleTick { .. })));
    }

    #[test]
    fn network_error_keeps_session() {
        let mut f = logged_in();
        f.on(AccountEvent::ListResult(Ok(vec![m("mac", false), m("me", true)])), 1_000);
        let acts = f.on(AccountEvent::Tick(16_000), 16_000);
        assert!(acts.contains(&AccountAction::CallList));
        let acts = f.on(AccountEvent::ListResult(Err(net())), 16_100);
        assert_eq!(f.state(), &AccountState::LoggedIn { machine_id: "me".into() });
        assert_eq!(f.machines().len(), 2, "last list kept while offline");
        assert!(acts.iter().all(|a| !matches!(a, AccountAction::CallLogin { .. })));
        // retried on the next tick
        let acts = f.on(AccountEvent::Tick(31_000), 31_000);
        assert!(acts.contains(&AccountAction::CallList));
        assert!(acts.contains(&AccountAction::CallHeartbeat));
        // a heartbeat network error has no event, and a later not_logged_in does log out
        f.on(AccountEvent::ListResult(Err(CoreErr::new("not_logged_in", ""))), 31_100);
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert!(f.machines().is_empty());
    }

    #[test]
    fn startup_network_error_retries() {
        let mut f = AccountFlow::new();
        f.on(AccountEvent::Started, 0);
        let acts = f.on(AccountEvent::ListResult(Err(net())), 10);
        assert!(matches!(f.state(), AccountState::Error(e) if e.code == "network"));
        assert_eq!(acts, vec![AccountAction::ScheduleTick { at_ms: 10 + LIST_INTERVAL_MS }]);
        let acts = f.on(AccountEvent::Tick(15_010), 15_010);
        assert!(acts.contains(&AccountAction::CallList));
    }

    #[test]
    fn logout_flow() {
        let mut f = logged_in();
        assert_eq!(f.on(AccountEvent::LogoutRequested, 5_000), vec![AccountAction::CallLogout]);
        f.on(AccountEvent::LoggedOut, 5_001);
        assert_eq!(f.state(), &AccountState::LoggedOut);
        assert!(f.on(AccountEvent::Tick(40_000), 40_000).is_empty());
        // a stale list result after logout is ignored
        f.on(AccountEvent::ListResult(Ok(vec![m("me", true)])), 40_001);
        assert_eq!(f.state(), &AccountState::LoggedOut);
    }

    #[test]
    fn password_never_in_debug_or_state() {
        let ev = AccountEvent::LoginSubmitted { email: "a@b.c".into(), password: "hunter2".into() };
        assert!(!format!("{ev:?}").contains("hunter2"));
        let mut f = AccountFlow::new();
        let acts = f.on(ev, 0);
        assert!(!format!("{acts:?}").contains("hunter2"));
        assert!(!format!("{f:?}").contains("hunter2"));
    }
}
