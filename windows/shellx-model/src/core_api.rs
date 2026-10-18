//! `shellx-core` (K3) call surface: the `CoreCall` trait, the C-ABI envelope
//! parser, typed wrappers and a scriptable `FakeCore`.

use std::collections::HashMap;
use std::fmt;
use std::sync::Mutex;

use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::{Value, json};

use crate::sidebar::MachineInfo;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CoreErr {
    pub code: String,
    pub message: String,
}

impl CoreErr {
    pub fn new(code: &str, message: &str) -> CoreErr {
        CoreErr {
            code: code.to_string(),
            message: message.to_string(),
        }
    }
}

impl fmt::Display for CoreErr {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.code, self.message)
    }
}

impl std::error::Error for CoreErr {}

/// Same shape as `shellx_core::Core::call`; the app bridges it.
pub trait CoreCall: Send + Sync {
    fn call(&self, method: &str, params: Value) -> Result<Value, CoreErr>;
}

/// Parse the C-ABI envelope `{"ok": v}` / `{"error": {"code", "message"}}`.
pub fn parse_envelope(s: &str) -> Result<Value, CoreErr> {
    let bad = || CoreErr::new("bad_envelope", "malformed core envelope");
    let v: Value = serde_json::from_str(s).map_err(|_| bad())?;
    let obj = v.as_object().ok_or_else(bad)?;
    if let Some(ok) = obj.get("ok") {
        return Ok(ok.clone());
    }
    if let Some(e) = obj.get("error") {
        let code = e.get("code").and_then(Value::as_str).ok_or_else(bad)?;
        let message = e.get("message").and_then(Value::as_str).unwrap_or("");
        return Err(CoreErr::new(code, message));
    }
    Err(bad())
}

fn typed<T: DeserializeOwned>(
    core: &dyn CoreCall,
    method: &str,
    params: Value,
) -> Result<T, CoreErr> {
    let v = core.call(method, params)?;
    serde_json::from_value(v).map_err(|e| CoreErr::new("bad_response", &format!("{method}: {e}")))
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CoreConfig {
    pub api_base: String,
    pub state_dir: String,
    pub app_version: String,
    pub os_version: String,
    pub device_name: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct LoginInfo {
    pub user_id: String,
    pub device_id: String,
    pub device_public_key_b64: String,
    pub fingerprint: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct Registered {
    pub machine_id: String,
    pub slot: i64,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct TicketFile {
    pub path: String,
    pub expires_at_unix: i64,
    pub relay_url: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct PairRequested {
    pub pairing_id: String,
    pub code: String,
    pub fingerprint: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PairStatus {
    Pending,
    Approved,
    Denied,
    Expired,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct PairPoll {
    pub status: PairStatus,
    pub invite_path: Option<String>,
    pub relay_route: Option<String>,
    pub relay_slot: Option<String>,
    pub daemon_fingerprint: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct VersionInfo {
    pub status: String,
    pub min_version: Option<String>,
    pub latest_version: Option<String>,
    pub download_url: Option<String>,
}

pub fn config_set(core: &dyn CoreCall, cfg: &CoreConfig) -> Result<(), CoreErr> {
    core.call(
        "config.set",
        json!({
            "api_base": cfg.api_base,
            "state_dir": cfg.state_dir,
            "app_version": cfg.app_version,
            "os_version": cfg.os_version,
            "platform": "windows",
            "device_name": cfg.device_name,
        }),
    )
    .map(|_| ())
}

pub fn login(core: &dyn CoreCall, email: &str, password: &str) -> Result<LoginInfo, CoreErr> {
    typed(
        core,
        "auth.login",
        json!({"email": email, "password": password}),
    )
}

pub fn logout(core: &dyn CoreCall) -> Result<(), CoreErr> {
    core.call("auth.logout", json!({})).map(|_| ())
}

pub fn register_machine(
    core: &dyn CoreCall,
    name: &str,
    os_version: &str,
    app_version: &str,
) -> Result<Registered, CoreErr> {
    typed(
        core,
        "machines.register",
        json!({"name": name, "platform": "windows", "os_version": os_version, "app_version": app_version}),
    )
}

pub fn list_machines(core: &dyn CoreCall) -> Result<Vec<MachineInfo>, CoreErr> {
    #[derive(Deserialize)]
    struct Resp {
        machines: Vec<MachineInfo>,
    }
    typed::<Resp>(core, "machines.list", json!({})).map(|r| r.machines)
}

pub fn heartbeat(core: &dyn CoreCall) -> Result<(), CoreErr> {
    core.call("machines.heartbeat", json!({})).map(|_| ())
}

pub fn mint_connect_ticket(
    core: &dyn CoreCall,
    target_machine_id: &str,
    write_to: &str,
) -> Result<TicketFile, CoreErr> {
    typed(
        core,
        "tickets.mint",
        json!({"permission": "connect", "target_machine_id": target_machine_id, "write_to": write_to}),
    )
}

pub fn pair_request(core: &dyn CoreCall, to_machine_id: &str) -> Result<PairRequested, CoreErr> {
    typed(
        core,
        "pair.request",
        json!({"to_machine_id": to_machine_id}),
    )
}

pub fn pair_poll(
    core: &dyn CoreCall,
    pairing_id: &str,
    write_invite_to: &str,
) -> Result<PairPoll, CoreErr> {
    typed(
        core,
        "pair.poll",
        json!({"pairing_id": pairing_id, "write_invite_to": write_invite_to}),
    )
}

pub fn version_check(core: &dyn CoreCall) -> Result<VersionInfo, CoreErr> {
    typed(core, "version.check", json!({}))
}

#[derive(Default)]
struct Script {
    results: Vec<Result<Value, CoreErr>>,
    next: usize,
}

#[derive(Default)]
struct FakeState {
    calls: Vec<(String, Value)>,
    scripts: HashMap<String, Script>,
}

/// Scriptable in-memory core for tests and `--smoke-ui`.
#[derive(Default)]
pub struct FakeCore {
    state: Mutex<FakeState>,
}

impl FakeCore {
    pub fn new() -> FakeCore {
        FakeCore::default()
    }

    /// Sticky result for `method`.
    pub fn on(&self, method: &str, result: Result<Value, CoreErr>) -> &FakeCore {
        self.on_seq(method, vec![result])
    }

    /// One result per call; the last repeats.
    pub fn on_seq(&self, method: &str, results: Vec<Result<Value, CoreErr>>) -> &FakeCore {
        let mut st = self.state.lock().unwrap();
        st.scripts
            .insert(method.to_string(), Script { results, next: 0 });
        self
    }

    pub fn calls(&self) -> Vec<(String, Value)> {
        self.state.lock().unwrap().calls.clone()
    }
}

impl CoreCall for FakeCore {
    fn call(&self, method: &str, params: Value) -> Result<Value, CoreErr> {
        let mut st = self.state.lock().unwrap();
        st.calls.push((method.to_string(), params));
        let Some(script) = st.scripts.get_mut(method) else {
            return Err(CoreErr::new("unknown_method", method));
        };
        if script.results.is_empty() {
            return Err(CoreErr::new("unknown_method", method));
        }
        let i = script.next.min(script.results.len() - 1);
        script.next += 1;
        script.results[i].clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fake_with(method: &str, v: Value) -> FakeCore {
        let f = FakeCore::new();
        f.on(method, Ok(v));
        f
    }

    #[test]
    fn envelope_ok_error_garbage() {
        assert_eq!(parse_envelope(r#"{"ok":{"a":1}}"#), Ok(json!({"a": 1})));
        assert_eq!(parse_envelope(r#"{"ok":null}"#), Ok(Value::Null));
        assert_eq!(
            parse_envelope(r#"{"error":{"code":"unauthorized","message":"nope"}}"#),
            Err(CoreErr::new("unauthorized", "nope"))
        );
        for bad in ["", "not json", "[]", "{}", r#"{"error":"x"}"#, r#"{"x":1}"#] {
            assert_eq!(
                parse_envelope(bad).unwrap_err().code,
                "bad_envelope",
                "{bad}"
            );
        }
    }

    #[test]
    fn fake_core_scripts_and_records() {
        let f = FakeCore::new();
        assert_eq!(f.call("x", json!({})).unwrap_err().code, "unknown_method");
        f.on("a", Ok(json!(1)));
        f.on_seq(
            "b",
            vec![Ok(json!(1)), Err(CoreErr::new("e", "m")), Ok(json!(3))],
        );
        assert_eq!(f.call("a", json!({})), Ok(json!(1)));
        assert_eq!(f.call("a", json!({})), Ok(json!(1)));
        assert_eq!(f.call("b", json!({})), Ok(json!(1)));
        assert_eq!(f.call("b", json!({})).unwrap_err().code, "e");
        assert_eq!(f.call("b", json!({})), Ok(json!(3)));
        assert_eq!(f.call("b", json!({})), Ok(json!(3)));
        let calls = f.calls();
        assert_eq!(calls.len(), 7);
        assert_eq!(calls[0].0, "x");
    }

    #[test]
    fn config_set_sends_all_keys() {
        let f = fake_with("config.set", json!({}));
        config_set(
            &f,
            &CoreConfig {
                api_base: "https://relay.shellx.pro".into(),
                state_dir: "C:\\s".into(),
                app_version: "2.0.0".into(),
                os_version: "10.0.26100".into(),
                device_name: "PC".into(),
            },
        )
        .unwrap();
        assert_eq!(
            f.calls(),
            vec![(
                "config.set".to_string(),
                json!({"api_base":"https://relay.shellx.pro","state_dir":"C:\\s","app_version":"2.0.0",
                       "os_version":"10.0.26100","platform":"windows","device_name":"PC"})
            )]
        );
    }

    #[test]
    fn login_logout_heartbeat() {
        let f = fake_with(
            "auth.login",
            json!({"user_id":"u1","device_id":"d1","device_public_key_b64":"AAA","fingerprint":"ab:cd","extra":1}),
        );
        let li = login(&f, "a@b.c", "pw").unwrap();
        assert_eq!(li.user_id, "u1");
        assert_eq!(li.device_id, "d1");
        assert_eq!(li.device_public_key_b64, "AAA");
        assert_eq!(li.fingerprint, "ab:cd");
        f.on("auth.logout", Ok(json!({})));
        f.on("machines.heartbeat", Ok(json!({})));
        logout(&f).unwrap();
        heartbeat(&f).unwrap();
        let c = f.calls();
        assert_eq!(
            c[0],
            (
                "auth.login".into(),
                json!({"email":"a@b.c","password":"pw"})
            )
        );
        assert_eq!(c[1], ("auth.logout".into(), json!({})));
        assert_eq!(c[2], ("machines.heartbeat".into(), json!({})));
    }

    #[test]
    fn register_machine_sends_no_key() {
        let f = fake_with("machines.register", json!({"machine_id":"m1","slot":2}));
        let r = register_machine(&f, "PC", "10.0", "2.0.0").unwrap();
        assert_eq!(
            r,
            Registered {
                machine_id: "m1".into(),
                slot: 2
            }
        );
        let (m, p) = &f.calls()[0];
        assert_eq!(m, "machines.register");
        assert_eq!(
            *p,
            json!({"name":"PC","platform":"windows","os_version":"10.0","app_version":"2.0.0"})
        );
        assert!(p.get("noise_public_key_b64").is_none());
    }

    #[test]
    fn list_machines_parses_and_defaults_self_flag() {
        let f = fake_with(
            "machines.list",
            json!({"machines":[
                {"machine_id":"m1","name":"Mac","platform":"macos","online":true,"last_seen_unix":5,"fingerprint":"f","is_this_machine":false},
                {"machine_id":"m2","name":"PC","platform":"windows","online":false,"last_seen_unix":0,"fingerprint":"g"}]}),
        );
        let ms = list_machines(&f).unwrap();
        assert_eq!(ms.len(), 2);
        assert!(!ms[1].is_this_machine);
        assert_eq!(f.calls()[0], ("machines.list".into(), json!({})));
    }

    #[test]
    fn tickets_and_pairing_calls() {
        let f = FakeCore::new();
        f.on(
            "tickets.mint",
            Ok(json!({"path":"C:\\t.json","expires_at_unix":99,"relay_url":"wss://relay.shellx.pro/v2/relay"})),
        );
        let t = mint_connect_ticket(&f, "m1", "C:\\t.json").unwrap();
        assert_eq!(t.path, "C:\\t.json");
        assert_eq!(t.expires_at_unix, 99);
        assert_eq!(t.relay_url, "wss://relay.shellx.pro/v2/relay");

        f.on(
            "pair.request",
            Ok(json!({"pairing_id":"p1","code":"482913","fingerprint":"ab"})),
        );
        let r = pair_request(&f, "m1").unwrap();
        assert_eq!((r.pairing_id.as_str(), r.code.as_str()), ("p1", "482913"));

        f.on_seq(
            "pair.poll",
            vec![
                Ok(json!({"status":"pending"})),
                Ok(json!({"status":"approved","invite_path":"C:\\i","relay_route":"r","relay_slot":"s","daemon_fingerprint":"df"})),
                Ok(json!({"status":"denied"})),
                Ok(json!({"status":"expired"})),
            ],
        );
        let p = pair_poll(&f, "p1", "C:\\i").unwrap();
        assert_eq!(p.status, PairStatus::Pending);
        assert_eq!(p.invite_path, None);
        let p = pair_poll(&f, "p1", "C:\\i").unwrap();
        assert_eq!(p.status, PairStatus::Approved);
        assert_eq!(p.invite_path.as_deref(), Some("C:\\i"));
        assert_eq!(p.relay_route.as_deref(), Some("r"));
        assert_eq!(p.relay_slot.as_deref(), Some("s"));
        assert_eq!(p.daemon_fingerprint.as_deref(), Some("df"));
        assert_eq!(pair_poll(&f, "p1", "x").unwrap().status, PairStatus::Denied);
        assert_eq!(
            pair_poll(&f, "p1", "x").unwrap().status,
            PairStatus::Expired
        );

        let c = f.calls();
        assert_eq!(
            c[0],
            (
                "tickets.mint".into(),
                json!({"permission":"connect","target_machine_id":"m1","write_to":"C:\\t.json"})
            )
        );
        assert_eq!(c[1], ("pair.request".into(), json!({"to_machine_id":"m1"})));
        assert_eq!(
            c[2],
            (
                "pair.poll".into(),
                json!({"pairing_id":"p1","write_invite_to":"C:\\i"})
            )
        );
    }

    #[test]
    fn version_check_parses() {
        let f = fake_with(
            "version.check",
            json!({"status":"update_available","latest_version":"2.0.1","download_url":"https://x"}),
        );
        let v = version_check(&f).unwrap();
        assert_eq!(v.status, "update_available");
        assert_eq!(v.latest_version.as_deref(), Some("2.0.1"));
        assert_eq!(v.min_version, None);
        assert_eq!(f.calls()[0], ("version.check".into(), json!({})));
    }

    #[test]
    fn bad_response_and_core_errors() {
        let f = FakeCore::new();
        f.on("auth.login", Ok(json!({"user_id": 5})));
        f.on("pair.poll", Ok(json!({"status":"weird"})));
        f.on("machines.list", Err(CoreErr::new("network", "down")));
        assert_eq!(login(&f, "a", "b").unwrap_err().code, "bad_response");
        assert_eq!(pair_poll(&f, "p", "x").unwrap_err().code, "bad_response");
        assert_eq!(
            list_machines(&f).unwrap_err(),
            CoreErr::new("network", "down")
        );
        assert_eq!(CoreErr::new("a", "b").to_string(), "a: b");
    }
}
