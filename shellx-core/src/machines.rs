//! `machines.register` / `machines.list` / `machines.heartbeat` and `machine.json`.
//!
//! `machine.json` = `{machine_id, slot}` in the state dir. It is removed by
//! `auth.logout` and by an `auth.login` that changes the account.

use crate::api::{ListResponse, MachineFile, RegisterRequest, RegisterResponse};
use crate::auth::{self, MACHINE_FILE};
use crate::config::Config;
use crate::envelope::CoreError;
use crate::fingerprint::fingerprint;
use crate::http::{self, Method};
use crate::pairing::{decode_key, pairing_id_ok};
use crate::store::StateStore;
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde_json::{Value, json};

pub fn load_machine(store: &StateStore) -> Result<Option<MachineFile>, CoreError> {
    let Some(bytes) = store.read_secret(MACHINE_FILE)? else { return Ok(None) };
    let m: MachineFile = serde_json::from_slice(&bytes)
        .map_err(|_| CoreError::new("io", format!("{MACHINE_FILE}: not a valid machine record")))?;
    if m.machine_id.is_empty() || m.slot.is_empty() {
        return Err(CoreError::new("io", format!("{MACHINE_FILE}: empty machine_id or slot")));
    }
    Ok(Some(m))
}

/// The registered machine, or `not_registered`.
pub fn require_machine(store: &StateStore) -> Result<MachineFile, CoreError> {
    load_machine(store)?.ok_or_else(|| CoreError::new("not_registered", "machines.register has not been called"))
}

fn text_param<'a>(params: &'a Value, key: &str) -> Result<&'a str, CoreError> {
    params
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| CoreError::invalid_params(format!("{key} is required and must be a non-empty string")))
}

/// Bearer of the current session (callers have already checked a session exists).
fn token(store: &StateStore) -> Result<zeroize::Zeroizing<String>, CoreError> {
    let s = auth::load_session(store)?.ok_or_else(|| CoreError::new("not_logged_in", "auth.login has not been called"))?;
    Ok(zeroize::Zeroizing::new(s.token.clone()))
}

pub fn register(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError> {
    const PATH: &str = "/v2/machines";
    if !params.is_object() {
        return Err(CoreError::invalid_params("params must be an object"));
    }
    let name = text_param(params, "name")?;
    let platform = text_param(params, "platform")?;
    let os_version = text_param(params, "os_version")?;
    let app_version = text_param(params, "app_version")?;
    let key = match params.get("noise_public_key_b64") {
        None | Some(Value::Null) => URL_SAFE_NO_PAD.encode(auth::device_public(store)?),
        Some(Value::String(k)) if !k.is_empty() => k.clone(),
        Some(_) => return Err(CoreError::invalid_params("noise_public_key_b64 must be a non-empty string")),
    };
    let body = serde_json::to_vec(&RegisterRequest {
        name,
        platform,
        os_version,
        app_version,
        noise_public_key_b64: &key,
    })
    .map_err(|_| CoreError::invalid_params("register body is not serializable"))?;
    let tok = token(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Post, PATH, Some(&body), None)?;
    let resp: RegisterResponse = http::parse_json(PATH, &reply)?;
    if resp.machine_id.is_empty() || resp.slot.is_empty() {
        return Err(CoreError::new("server", format!("{PATH}: response is missing machine_id or slot")));
    }
    let file = MachineFile { machine_id: resp.machine_id.clone(), slot: resp.slot.clone() };
    let bytes = serde_json::to_vec(&file).map_err(|_| CoreError::new("io", "machine record is not serializable"))?;
    store.write_secret(MACHINE_FILE, &bytes)?;
    Ok(json!({"machine_id": resp.machine_id, "slot": resp.slot}))
}

pub fn list(agent: &ureq::Agent, cfg: &Config, store: &StateStore) -> Result<Value, CoreError> {
    const PATH: &str = "/v2/machines";
    let own = load_machine(store)?.map(|m| m.machine_id);
    let tok = token(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Get, PATH, None, None)?;
    let resp: ListResponse = http::parse_json(PATH, &reply)?;
    let machines: Vec<Value> = resp
        .machines
        .into_iter()
        .map(|m| {
            // D1: the fingerprint is computed here from the key the server holds (any
            // base64 alphabet). The server's own `fingerprint` field is never shown:
            // no decodable 32-byte key → `null` (Swift `MachineItem.fingerprint: String?`).
            let fp = m.noise_public_key_b64.as_deref().and_then(decode_key).map(|raw| fingerprint(&raw));
            json!({
                "is_this_machine": own.as_deref() == Some(m.machine_id.as_str()),
                "machine_id": m.machine_id,
                "name": m.name,
                "platform": m.platform,
                "online": m.online,
                "last_seen_unix": m.last_seen_unix.unwrap_or(0),
                "fingerprint": fp,
            })
        })
        .collect();
    Ok(json!({"machines": machines}))
}

pub fn heartbeat(agent: &ureq::Agent, cfg: &Config, store: &StateStore) -> Result<Value, CoreError> {
    let m = require_machine(store)?;
    if !pairing_id_ok(&m.machine_id) {
        return Err(CoreError::new("io", format!("{MACHINE_FILE}: machine_id is not path-safe")));
    }
    let path = format!("/v2/machines/{}/heartbeat", m.machine_id);
    let tok = token(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Post, &path, None, None)?;
    http::check_status(&path, &reply)?;
    Ok(json!({}))
}
