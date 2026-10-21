//! shellx-core: the ShellX account/relay client core.
//!
//! The Mac app links the staticlib through one C function (`ffi`); the Windows
//! app uses the rlib. Every method goes through [`Core::call`].

pub mod api;
pub mod auth;
pub mod config;
pub mod envelope;
pub mod ffi;
pub mod fingerprint;
pub mod http;
pub mod machines;
pub mod pairing;
pub mod seal;
pub mod shares;
pub mod store;
pub mod tickets;
pub mod version;

pub use config::Config;
pub use envelope::CoreError;

use serde_json::{Value, json};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};
use store::StateStore;

/// Every K3 method name. Names outside this list are `unknown_method`.
pub const KNOWN_METHODS: &[&str] = &[
    "config.set",
    "auth.login",
    "auth.logout",
    "machines.register",
    "machines.list",
    "machines.heartbeat",
    "tickets.mint",
    "shares.create",
    "shares.list",
    "shares.revoke",
    "shares.host_ticket",
    "pair.request",
    "pair.pending",
    "pair.approve",
    "pair.deny",
    "pair.poll",
    "version.check",
];

/// Methods that need `session.json` (Ruling R1: checked before dispatch).
fn needs_session(method: &str) -> bool {
    method.starts_with("machines.") || method.starts_with("tickets.") || method.starts_with("pair.") || method.starts_with("shares.")
}

#[derive(Default)]
pub struct Core {
    config: Mutex<Option<Config>>,
    /// Store opened for the configured `state_dir` (re-opened when it changes).
    store: Mutex<Option<(PathBuf, Arc<StateStore>)>>,
    agent: OnceLock<ureq::Agent>,
    /// Serializes calls that create or replace state files (device key, session).
    auth_lock: Mutex<()>,
    /// `pairing_id → fingerprint` shown by the most recent `pair.pending`
    /// (Ruling R14, see `pairing`). Public keys' fingerprints only, no secrets.
    /// Cleared by `config.set`, `auth.login` and `auth.logout`.
    shown_fingerprints: Mutex<HashMap<String, String>>,
}

impl Core {
    pub fn new() -> Core {
        Core::default()
    }

    /// Current config, if `config.set` succeeded. Later tasks use this.
    pub fn config(&self) -> Option<Config> {
        self.config.lock().unwrap_or_else(|p| p.into_inner()).clone()
    }

    pub fn call(&self, method: &str, params: Value) -> Result<Value, CoreError> {
        if !KNOWN_METHODS.contains(&method) {
            return Err(CoreError::new("unknown_method", format!("unknown method: {method}")));
        }
        if method == "config.set" {
            let cfg = Config::from_params(&params)?;
            *self.config.lock().unwrap_or_else(|p| p.into_inner()) = Some(cfg);
            self.forget_shown_fingerprints();
            return Ok(json!({}));
        }
        let cfg = self
            .config()
            .ok_or_else(|| CoreError::new("not_configured", "config.set has not been called"))?;
        if method == "version.check" {
            // Public endpoint: the bearer is sent only if a readable session exists;
            // a missing or broken state dir must not block update checks.
            let session = self.store(&cfg).ok().and_then(|s| auth::load_session(&s).ok().flatten());
            return version::check(self.agent(), &cfg, session.as_ref().map(|s| s.token.as_str()));
        }
        let store = self.store(&cfg)?;
        if needs_session(method) {
            let Some(session) = auth::load_session(&store)? else {
                return Err(CoreError::new("not_logged_in", "auth.login has not been called"));
            };
            let used = zeroize::Zeroizing::new(session.token.clone());
            drop(session);
            let result = self.dispatch(method, &params, &cfg, &store);
            if let Err(e) = &result
                && (e.code == "unauthorized" || e.code == "http_401")
            {
                self.forget_refused_session(&store, &used);
            }
            return result;
        }
        self.dispatch(method, &params, &cfg, &store)
    }

    /// The server refused `used` (401): forget `session.json` so the next
    /// `auth.login` sends no stale bearer. `machine.json` is kept (same semantics
    /// as before: only logout or a login as another account drops it). A session
    /// replaced meanwhile by a concurrent `auth.login` is left alone.
    fn forget_refused_session(&self, store: &StateStore, used: &str) {
        let _g = self.auth_lock.lock().unwrap_or_else(|p| p.into_inner());
        if let Ok(Some(current)) = auth::load_session(store)
            && current.token == used
        {
            let _ = store.remove(auth::SESSION_FILE);
        }
    }

    fn forget_shown_fingerprints(&self) {
        self.shown_fingerprints.lock().unwrap_or_else(|p| p.into_inner()).clear();
    }

    fn dispatch(&self, method: &str, params: &Value, cfg: &Config, store: &StateStore) -> Result<Value, CoreError> {
        match method {
            "auth.login" => {
                let _g = self.auth_lock.lock().unwrap_or_else(|p| p.into_inner());
                self.forget_shown_fingerprints();
                auth::login(self.agent(), cfg, store, params)
            }
            "auth.logout" => {
                let _g = self.auth_lock.lock().unwrap_or_else(|p| p.into_inner());
                self.forget_shown_fingerprints();
                auth::logout(self.agent(), cfg, store)
            }
            "machines.register" => machines::register(self.agent(), cfg, store, params),
            "machines.list" => machines::list(self.agent(), cfg, store),
            "machines.heartbeat" => machines::heartbeat(self.agent(), cfg, store),
            "tickets.mint" => tickets::mint(self.agent(), cfg, store, params),
            "shares.create" => shares::create(self.agent(), cfg, store, params),
            "shares.list" => shares::list(self.agent(), cfg, store),
            "shares.revoke" => shares::revoke(self.agent(), cfg, store, params),
            "shares.host_ticket" => shares::host_ticket(self.agent(), cfg, store, params),
            "pair.request" => pairing::request(self.agent(), cfg, store, params),
            "pair.pending" => {
                let shown = pairing::pending(self.agent(), cfg, store)?;
                *self.shown_fingerprints.lock().unwrap_or_else(|p| p.into_inner()) =
                    pairing::shown_fingerprints(&shown);
                Ok(shown)
            }
            "pair.approve" => {
                let remembered = params
                    .get("pairing_id")
                    .and_then(Value::as_str)
                    .and_then(|id| self.shown_fingerprints.lock().unwrap_or_else(|p| p.into_inner()).get(id).cloned());
                pairing::approve(self.agent(), cfg, store, params, remembered.as_deref())
            }
            "pair.deny" => pairing::deny(self.agent(), cfg, store, params),
            "pair.poll" => pairing::poll(self.agent(), cfg, store, params),
            _ => Err(CoreError::new("unknown_method", format!("method not implemented: {method}"))),
        }
    }

    fn agent(&self) -> &ureq::Agent {
        self.agent.get_or_init(http::new_agent)
    }

    /// The `StateStore` for `cfg.state_dir`, opened on first use and re-opened
    /// when `config.set` moved the state dir.
    fn store(&self, cfg: &Config) -> Result<Arc<StateStore>, CoreError> {
        let mut slot = self.store.lock().unwrap_or_else(|p| p.into_inner());
        if let Some((root, s)) = slot.as_ref()
            && *root == cfg.state_dir
        {
            return Ok(s.clone());
        }
        let s = Arc::new(StateStore::open(&cfg.state_dir)?);
        *slot = Some((cfg.state_dir.clone(), s.clone()));
        Ok(s)
    }

    /// Parse `json_in`, dispatch, return the envelope string.
    pub fn call_json(&self, method: &str, json_in: &str) -> String {
        let params: Value = match serde_json::from_str(json_in) {
            Ok(v) => v,
            Err(_) => {
                return envelope::to_envelope(Err(CoreError::new("invalid_json", "params are not valid JSON")));
            }
        };
        envelope::to_envelope(self.call(method, params))
    }
}
