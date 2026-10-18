//! shellx-core: the ShellX account/relay client core.
//!
//! The Mac app links the staticlib through one C function (`ffi`); the Windows
//! app uses the rlib. Every method goes through [`Core::call`].

pub mod config;
pub mod envelope;
pub mod ffi;
pub mod store;

pub use config::Config;
pub use envelope::CoreError;

use serde_json::{Value, json};
use std::sync::Mutex;

/// Every K3 method name. Names outside this list are `unknown_method`.
pub const KNOWN_METHODS: &[&str] = &[
    "config.set",
    "auth.login",
    "auth.logout",
    "machines.register",
    "machines.list",
    "machines.heartbeat",
    "tickets.mint",
    "pair.request",
    "pair.pending",
    "pair.approve",
    "pair.deny",
    "pair.poll",
    "version.check",
];

#[derive(Default)]
pub struct Core {
    config: Mutex<Option<Config>>,
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
            return Ok(json!({}));
        }
        let _cfg = self
            .config()
            .ok_or_else(|| CoreError::new("not_configured", "config.set has not been called"))?;
        // Later tasks add arms here (session check `not_logged_in` for machines/tickets/pair).
        #[allow(clippy::match_single_binding)]
        match method {
            _ => Err(CoreError::new("unknown_method", format!("method not implemented: {method}"))),
        }
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
