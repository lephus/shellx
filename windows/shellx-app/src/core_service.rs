//! GPUI-free half of the account service (the window drives it from
//! `ui/account.rs`; `--smoke` and the Mac tests drive it directly):
//!
//! - `ConfiguredCore`: a `CoreCall` that sends `config.set` (this PC's
//!   values) before its first call, and again after a failed attempt, so a
//!   missing `%LOCALAPPDATA%` or a bad state dir shows up as a readable error
//!   on the call that needed it instead of stopping the app.
//! - `run_account_action`: one `AccountFlow` action -> its core call -> the
//!   result event. Calls block (ureq); the caller runs them off the UI thread,
//!   one at a time, in order.
//!
//! The account token never leaves shellx-core; the password is moved into
//! the login call and dropped with the action.
// The window (cfg(windows)) is the main user; the Mac build only tests it.
#![cfg_attr(not(windows), allow(dead_code))]

use std::sync::Mutex;

use shellx_model::account::{AccountAction, AccountEvent};
use shellx_model::core_api::{
    CoreCall, CoreConfig, CoreErr, config_set, heartbeat, list_machines, login, logout,
    register_machine,
};

/// The ShellX API (K2). The relay URL is never set here: it comes from
/// `tickets.mint` / `pair.poll`.
pub const API_BASE: &str = "https://relay.shellx.pro";

/// API base for `config.set`. Debug builds may point at a local fake API with
/// `SHELLX_API_BASE`; release builds always use `API_BASE`.
pub fn api_base() -> String {
    api_base_from(std::env::var("SHELLX_API_BASE").ok())
}

fn api_base_from(env: Option<String>) -> String {
    #[cfg(debug_assertions)]
    if let Some(v) = env.map(|v| v.trim().to_string()).filter(|v| !v.is_empty()) {
        return v;
    }
    #[cfg(not(debug_assertions))]
    let _ = env;
    API_BASE.to_string()
}

/// Facts about this PC sent with `config.set` and `machines.register`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MachineFacts {
    pub os_version: String,
    pub device_name: String,
}

impl MachineFacts {
    pub fn this_pc() -> MachineFacts {
        MachineFacts {
            os_version: crate::os_info::os_version(),
            device_name: crate::os_info::device_name(),
        }
    }
}

/// `config.set` values for this PC: state dir `%LOCALAPPDATA%\ShellX\native\core`.
pub fn this_pc_config(facts: &MachineFacts) -> Result<CoreConfig, CoreErr> {
    let dir = crate::paths::core_dir()
        .map_err(|e| CoreErr::new("state_dir", &format!("ShellX state folder: {e}")))?;
    Ok(CoreConfig {
        api_base: api_base(),
        state_dir: dir.to_string_lossy().into_owned(),
        app_version: shellx_model::VERSION.to_string(),
        os_version: facts.os_version.clone(),
        device_name: facts.device_name.clone(),
    })
}

type MakeConfig = Box<dyn Fn() -> Result<CoreConfig, CoreErr> + Send + Sync>;

/// A `CoreCall` that is configured before its first call.
pub struct ConfiguredCore {
    inner: Box<dyn CoreCall>,
    make_config: MakeConfig,
    configured: Mutex<bool>,
}

impl ConfiguredCore {
    pub fn new(
        inner: Box<dyn CoreCall>,
        make_config: impl Fn() -> Result<CoreConfig, CoreErr> + Send + Sync + 'static,
    ) -> ConfiguredCore {
        ConfiguredCore {
            inner,
            make_config: Box::new(make_config),
            configured: Mutex::new(false),
        }
    }

    /// The real shellx-core with this PC's config.
    pub fn this_pc(facts: MachineFacts) -> ConfiguredCore {
        ConfiguredCore::new(Box::new(crate::core_bridge::CoreBridge::new()), move || {
            this_pc_config(&facts)
        })
    }

    fn ensure_configured(&self) -> Result<(), CoreErr> {
        let mut configured = self.configured.lock().unwrap_or_else(|p| p.into_inner());
        if !*configured {
            let cfg = (self.make_config)()?;
            config_set(self.inner.as_ref(), &cfg)?;
            *configured = true;
        }
        Ok(())
    }
}

impl CoreCall for ConfiguredCore {
    fn call(&self, method: &str, params: serde_json::Value) -> Result<serde_json::Value, CoreErr> {
        if method != "config.set" {
            self.ensure_configured()?;
        }
        self.inner.call(method, params)
    }
}

/// Runs one account action. `ScheduleTick` is not a core call (the UI arms a
/// timer) and the heartbeat result has no event: both give `None`.
pub fn run_account_action(
    core: &dyn CoreCall,
    facts: &MachineFacts,
    action: AccountAction,
) -> Option<AccountEvent> {
    match action {
        AccountAction::CallList => Some(AccountEvent::ListResult(list_machines(core))),
        AccountAction::CallLogin { email, password } => {
            let result = login(core, &email, &password);
            drop(password);
            Some(AccountEvent::LoginResult(result))
        }
        // No device key from the app (L0 R17): shellx-core fills its own.
        AccountAction::CallRegister => Some(AccountEvent::Registered(register_machine(
            core,
            &facts.device_name,
            &facts.os_version,
            shellx_model::VERSION,
        ))),
        AccountAction::CallHeartbeat => {
            // A lost session shows on the next list (not_logged_in).
            let _ = heartbeat(core);
            None
        }
        AccountAction::CallLogout => Some(AccountEvent::LogoutResult(logout(core))),
        AccountAction::ScheduleTick { .. } => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use shellx_fake_api::{FakeApi, FakeOptions};
    use shellx_model::account::{AccountFlow, AccountState};
    use shellx_model::core_api::FakeCore;
    use std::collections::VecDeque;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};

    fn facts() -> MachineFacts {
        MachineFacts {
            os_version: "10.0.26100".into(),
            device_name: "TEST-PC".into(),
        }
    }

    fn cfg(api_base: &str, dir: &std::path::Path) -> CoreConfig {
        CoreConfig {
            api_base: api_base.into(),
            state_dir: dir.to_string_lossy().into_owned(),
            app_version: "2.0.0".into(),
            os_version: "10.0.26100".into(),
            device_name: "TEST-PC".into(),
        }
    }

    /// Feeds `ev`, runs every returned call (in order, like the UI's serial
    /// worker), and feeds the results back until no call is left. Returns
    /// the methods' actions in the order they ran and the scheduled ticks.
    fn drive(
        flow: &mut AccountFlow,
        core: &dyn CoreCall,
        ev: AccountEvent,
        now: u64,
    ) -> (Vec<String>, Vec<u64>) {
        let mut ran = Vec::new();
        let mut ticks = Vec::new();
        let mut queue: VecDeque<AccountAction> = flow.on(ev, now).into();
        while let Some(action) = queue.pop_front() {
            if let AccountAction::ScheduleTick { at_ms } = action {
                ticks.push(at_ms);
                continue;
            }
            ran.push(format!("{action:?}"));
            if let Some(result) = run_account_action(core, &facts(), action) {
                queue.extend(flow.on(result, now));
            }
        }
        (ran, ticks)
    }

    #[test]
    fn api_base_override_only_in_debug_builds() {
        assert_eq!(api_base_from(None), API_BASE);
        assert_eq!(api_base_from(Some("  ".into())), API_BASE);
        let local = api_base_from(Some("http://127.0.0.1:8787".into()));
        if cfg!(debug_assertions) {
            assert_eq!(local, "http://127.0.0.1:8787");
        } else {
            assert_eq!(local, API_BASE);
        }
    }

    #[test]
    fn config_set_once_before_the_first_call_and_retried_after_a_failure() {
        let fake = Arc::new(FakeCore::new());
        fake.on("config.set", Ok(json!({})));
        fake.on("machines.list", Err(CoreErr::new("not_logged_in", "")));
        let attempts = Arc::new(AtomicUsize::new(0));
        let a = attempts.clone();
        struct Shared(Arc<FakeCore>);
        impl CoreCall for Shared {
            fn call(&self, m: &str, p: serde_json::Value) -> Result<serde_json::Value, CoreErr> {
                self.0.call(m, p)
            }
        }
        let core = ConfiguredCore::new(Box::new(Shared(fake.clone())), move || {
            if a.fetch_add(1, Ordering::SeqCst) == 0 {
                Err(CoreErr::new(
                    "state_dir",
                    "ShellX state folder: LOCALAPPDATA is not set",
                ))
            } else {
                Ok(cfg(API_BASE, std::path::Path::new("/s")))
            }
        });
        // first: the config error is the call's error, core is not called
        let e = list_machines(&core).unwrap_err();
        assert_eq!(e.code, "state_dir");
        assert!(fake.calls().is_empty());
        // then: config.set, then the call; later calls do not re-send it
        assert_eq!(list_machines(&core).unwrap_err().code, "not_logged_in");
        assert_eq!(list_machines(&core).unwrap_err().code, "not_logged_in");
        let methods: Vec<String> = fake.calls().into_iter().map(|(m, _)| m).collect();
        assert_eq!(methods, ["config.set", "machines.list", "machines.list"]);
        assert_eq!(fake.calls()[0].1["platform"], "windows");
        assert_eq!(attempts.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn actions_map_to_calls_and_events() {
        let fake = FakeCore::new();
        fake.on("machines.heartbeat", Err(CoreErr::new("network", "down")));
        fake.on("auth.logout", Ok(json!({})));
        fake.on(
            "machines.register",
            Ok(json!({"machine_id":"m","slot":"s"})),
        );
        assert_eq!(
            run_account_action(&fake, &facts(), AccountAction::CallHeartbeat),
            None
        );
        assert_eq!(
            run_account_action(&fake, &facts(), AccountAction::ScheduleTick { at_ms: 5 }),
            None
        );
        assert_eq!(
            run_account_action(&fake, &facts(), AccountAction::CallLogout),
            Some(AccountEvent::LogoutResult(Ok(())))
        );
        assert!(matches!(
            run_account_action(&fake, &facts(), AccountAction::CallRegister),
            Some(AccountEvent::Registered(Ok(r))) if r.machine_id == "m"
        ));
        let (_, params) = &fake.calls()[2];
        assert_eq!(
            *params,
            json!({"name":"TEST-PC","platform":"windows","os_version":"10.0.26100","app_version":"2.0.0"})
        );
        // unknown_method (a method L5 has not implemented) is a readable error
        assert!(matches!(
            run_account_action(&fake, &facts(), AccountAction::CallList),
            Some(AccountEvent::ListResult(Err(e))) if e.code == "unknown_method"
        ));
    }

    #[test]
    fn smoke_account_flow() {
        crate::smoke::account_flow().unwrap();
    }

    /// The whole session through the real shellx-core against L5's fake API:
    /// start (no session) -> login card; login -> register once -> listed;
    /// heartbeat on the tick; logout -> login card.
    #[test]
    fn account_session_against_fake_api() {
        let api = FakeApi::start(FakeOptions::default());
        let password = FakeOptions::default().password;
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("core");
        let base = api.base_url.clone();
        let core =
            ConfiguredCore::new(Box::new(crate::core_bridge::CoreBridge::new()), move || {
                Ok(cfg(&base, &dir))
            });
        let mut flow = AccountFlow::new();

        let (ran, _) = drive(&mut flow, &core, AccountEvent::Started, 0);
        assert_eq!(ran, ["CallList"]);
        assert_eq!(flow.state(), &AccountState::LoggedOut);

        // wrong password: an error the panel can show, still resubmittable
        let (ran, _) = drive(
            &mut flow,
            &core,
            AccountEvent::LoginSubmitted {
                email: "a@b.c".into(),
                password: "wrong".into(),
            },
            1,
        );
        assert_eq!(ran.len(), 1);
        assert!(!ran[0].contains("wrong"), "password in {ran:?}");
        assert!(
            matches!(flow.state(), AccountState::Error(e) if !e.code.is_empty()),
            "{:?}",
            flow.state()
        );

        let (ran, ticks) = drive(
            &mut flow,
            &core,
            AccountEvent::LoginSubmitted {
                email: "a@b.c".into(),
                password,
            },
            2,
        );
        assert_eq!(
            ran,
            [
                "CallLogin { email: \"a@b.c\", password: \"<redacted>\" }",
                "CallList",
                "CallRegister",
                "CallList"
            ]
        );
        let AccountState::LoggedIn { machine_id } = flow.state().clone() else {
            panic!("not logged in: {:?}", flow.state());
        };
        let me: Vec<_> = flow
            .machines()
            .iter()
            .filter(|m| m.is_this_machine)
            .collect();
        assert_eq!(me.len(), 1);
        assert_eq!(me[0].machine_id, machine_id);
        assert_eq!(me[0].name, "TEST-PC");
        assert_eq!(ticks, [2 + shellx_model::account::LIST_INTERVAL_MS]);

        // the 30 s tick lists and heartbeats; no second register
        let (ran, _) = drive(&mut flow, &core, AccountEvent::Tick(30_002), 30_002);
        assert_eq!(ran, ["CallList", "CallHeartbeat"]);
        assert!(matches!(flow.state(), AccountState::LoggedIn { .. }));

        let (ran, _) = drive(&mut flow, &core, AccountEvent::LogoutRequested, 30_003);
        assert_eq!(ran, ["CallLogout"]);
        assert_eq!(flow.state(), &AccountState::LoggedOut);
        let (ran, _) = drive(&mut flow, &core, AccountEvent::Started, 30_004);
        assert_eq!(ran, ["CallList"]);
        assert_eq!(flow.state(), &AccountState::LoggedOut);
        api.stop();
    }
}
