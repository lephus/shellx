//! `auth.login` / `auth.logout`, the device key (D1) and `session.json`.
//!
//! * `device.key` = raw 32-byte X25519 secret, generated once per `state_dir`
//!   (0600 via `StateStore`), kept across logout so the device identity (and the
//!   server's `device_id`) stays stable.
//! * `session.json` = `{token, user_id, device_id}`; the token never leaves the
//!   state dir: it is not returned, logged or shown by any `Debug`.

use crate::api::{LoginDevice, LoginRequest, LoginResponse, SessionFile};
use crate::config::Config;
use crate::envelope::CoreError;
use crate::fingerprint::fingerprint;
use crate::http::{self, Method};
use crate::store::StateStore;
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde_json::{Value, json};
use std::time::Duration;
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::{Zeroize, Zeroizing};

pub const SESSION_FILE: &str = "session.json";
pub const DEVICE_KEY_FILE: &str = "device.key";
pub const MACHINE_FILE: &str = "machine.json";
/// Best-effort server logout must not hold up a local sign-out.
pub const LOGOUT_TIMEOUT: Duration = Duration::from_secs(2);
const DEVICE_NAME_MAX_CHARS: usize = 100;

impl Drop for SessionFile {
    fn drop(&mut self) {
        self.token.zeroize();
    }
}

impl Drop for crate::api::MintResponse {
    fn drop(&mut self) {
        self.ticket.zeroize();
    }
}

impl Drop for LoginResponse {
    fn drop(&mut self) {
        self.token.zeroize();
    }
}

/// `session.json`, `None` when logged out. A file that does not parse is an `io` error.
pub fn load_session(store: &StateStore) -> Result<Option<SessionFile>, CoreError> {
    let Some(bytes) = store.read_secret(SESSION_FILE)? else { return Ok(None) };
    let s: SessionFile = serde_json::from_slice(&bytes)
        .map_err(|_| CoreError::new("io", format!("{SESSION_FILE}: not a valid session ({} bytes)", bytes.len())))?;
    if s.token.is_empty() {
        return Err(CoreError::new("io", format!("{SESSION_FILE}: empty token")));
    }
    Ok(Some(s))
}

/// The device X25519 secret, generated and stored on first use.
pub fn device_secret(store: &StateStore) -> Result<StaticSecret, CoreError> {
    if let Some(bytes) = store.read_secret(DEVICE_KEY_FILE)? {
        let mut raw: [u8; 32] = bytes[..].try_into().map_err(|_| {
            CoreError::new("io", format!("{DEVICE_KEY_FILE}: expected 32 bytes, found {}", bytes.len()))
        })?;
        let secret = StaticSecret::from(raw);
        raw.zeroize();
        return Ok(secret);
    }
    let mut raw = Zeroizing::new([0u8; 32]);
    getrandom::fill(&mut raw[..]).map_err(|_| CoreError::new("crypto", "random source unavailable"))?;
    store.write_secret(DEVICE_KEY_FILE, &raw[..])?;
    Ok(StaticSecret::from(*raw))
}

pub fn device_public(store: &StateStore) -> Result<[u8; 32], CoreError> {
    Ok(PublicKey::from(&device_secret(store)?).to_bytes())
}

#[cfg(unix)]
fn hostname() -> Option<String> {
    let mut buf = [0u8; 256];
    // SAFETY: buf is valid for buf.len() bytes.
    if unsafe { libc::gethostname(buf.as_mut_ptr().cast(), buf.len()) } != 0 {
        return None;
    }
    let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
    let name = String::from_utf8_lossy(&buf[..end]).into_owned();
    Some(name.strip_suffix(".local").unwrap_or(&name).to_string())
}

#[cfg(not(unix))]
fn hostname() -> Option<String> {
    std::env::var("COMPUTERNAME").ok()
}

/// `device_name` from `config.set`, else the host name, trimmed to the server's 100 chars.
pub fn device_name(cfg: &Config) -> String {
    let pick = |s: &str| {
        let t = s.trim();
        (!t.is_empty()).then(|| t.chars().take(DEVICE_NAME_MAX_CHARS).collect::<String>())
    };
    pick(&cfg.device_name)
        .or_else(|| hostname().as_deref().and_then(pick))
        .unwrap_or_else(|| "ShellX".to_string())
}

fn required_str<'a>(params: &'a Value, key: &str) -> Result<&'a str, CoreError> {
    params
        .get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| CoreError::invalid_params(format!("{key} is required and must be a string")))
}

pub fn login(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError> {
    const PATH: &str = "/v1/auth/login";
    if !params.is_object() {
        return Err(CoreError::invalid_params("params must be an object"));
    }
    let email = required_str(params, "email")?;
    let password = required_str(params, "password")?;
    let public = device_public(store)?;
    let public_b64 = URL_SAFE_NO_PAD.encode(public);
    let name = device_name(cfg);
    let body = LoginRequest {
        email,
        password,
        device: LoginDevice { kind: "desktop", name: &name, platform: &cfg.platform, public_key: &public_b64 },
    };
    let body = Zeroizing::new(
        serde_json::to_vec(&body).map_err(|_| CoreError::invalid_params("login body is not serializable"))?,
    );
    // A stale session (re-login) still authenticates the request, per "every request".
    let old = load_session(store).ok().flatten();
    let reply = http::send(agent, cfg, old.as_ref().map(|s| s.token.as_str()), Method::Post, PATH, Some(&body), None)?;
    let previous_user = old.as_ref().map(|s| s.user_id.clone());
    drop(old);
    let resp: LoginResponse = http::parse_json(PATH, &reply)?;
    if resp.token.is_empty() || resp.user_id.is_empty() || resp.device_id.is_empty() {
        return Err(CoreError::new("server", format!("{PATH}: response is missing token, user_id or device_id")));
    }
    let session = SessionFile {
        token: resp.token.clone(),
        user_id: resp.user_id.clone(),
        device_id: resp.device_id.clone(),
    };
    let bytes = Zeroizing::new(
        serde_json::to_vec(&session).map_err(|_| CoreError::new("io", "session is not serializable"))?,
    );
    store.write_secret(SESSION_FILE, &bytes)?;
    // A machine registered under another account must not be reused.
    if previous_user.as_deref().is_some_and(|u| u != resp.user_id) {
        store.remove(MACHINE_FILE)?;
    }
    Ok(json!({
        "user_id": resp.user_id,
        "device_id": resp.device_id,
        "device_public_key_b64": public_b64,
        "fingerprint": fingerprint(&public),
    }))
}

/// Best-effort server logout (2 s), then forget the session and machine locally.
/// The device key stays. Succeeds even when the server is unreachable.
pub fn logout(agent: &ureq::Agent, cfg: &Config, store: &StateStore) -> Result<Value, CoreError> {
    // A session file that does not parse cannot be sent; it is removed below anyway.
    if let Some(s) = load_session(store).ok().flatten() {
        let _ = http::send(agent, cfg, Some(&s.token), Method::Post, "/v1/auth/logout", None, Some(LOGOUT_TIMEOUT));
    }
    store.remove(SESSION_FILE)?;
    store.remove(MACHINE_FILE)?;
    Ok(json!({}))
}
