//! `phones.pending` / `phones.approve` / `phones.deny` / `phones.grants` / `phones.revoke`:
//! the Mac side of phone pairing (`/v2/phone-pairings`, `/v2/phone-grants`).
//!
//! A phone of the same account asks one of this account's machines for access; the
//! person on the Mac compares what the phone shows and approves, which grants the
//! phone's key on the machine's ShellX Link lane. These commands only list and
//! decide: the server owns every check (target machine, expiry, status).
//!
//! * Every command needs a registered machine (`not_registered`) and a session
//!   (`not_logged_in`, checked by `Core::call`); server error codes pass through.
//! * Ids go into URL paths, so they must match `^[A-Za-z0-9_-]{1,128}$`.
//! * `client_key_b64` / `proof_b64` are returned as the server sent them (standard
//!   base64 of 32 bytes); the Swift wrapper validates the lengths. `proof_b64` is
//!   never logged: `Debug` of the typed items shows lengths only.

use crate::auth;
use crate::config::Config;
use crate::envelope::CoreError;
use crate::http::{self, Method};
use crate::machines::require_machine;
use crate::pairing::pairing_id_ok;
use crate::store::StateStore;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::fmt;
use zeroize::Zeroizing;

const PENDING_PATH: &str = "/v2/phone-pairings?role=target";
const GRANTS_PATH: &str = "/v2/phone-grants";

/// One item of `GET /v2/phone-pairings?role=target`. `Debug` hides key and proof.
#[derive(Deserialize, Serialize)]
struct PendingItem {
    pairing_id: String,
    #[serde(default)]
    device_name: String,
    #[serde(default)]
    platform: String,
    client_key_b64: String,
    proof_b64: String,
    created_at_unix: u64,
}

impl fmt::Debug for PendingItem {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PendingItem")
            .field("pairing_id", &self.pairing_id)
            .field("device_name", &self.device_name)
            .field("platform", &self.platform)
            .field("client_key_len", &self.client_key_b64.len())
            .field("proof_len", &self.proof_b64.len())
            .finish_non_exhaustive()
    }
}

#[derive(Debug, Deserialize)]
struct PendingList {
    pairings: Vec<PendingItem>,
}

/// One item of `GET /v2/phone-grants` (desktop side).
#[derive(Debug, Deserialize, Serialize)]
struct GrantItem {
    grant_id: String,
    device_id: String,
    #[serde(default)]
    device_name: String,
    #[serde(default)]
    platform: String,
    client_key_b64: String,
    created_at_unix: u64,
    #[serde(default)]
    last_seen_unix: Option<u64>,
}

#[derive(Debug, Deserialize)]
struct GrantList {
    grants: Vec<GrantItem>,
}

fn token(store: &StateStore) -> Result<Zeroizing<String>, CoreError> {
    let s = auth::load_session(store)?.ok_or_else(|| CoreError::new("not_logged_in", "auth.login has not been called"))?;
    Ok(Zeroizing::new(s.token.clone()))
}

/// A path-safe id param (`key` is `pairing_id` or `grant_id`).
fn id_param<'a>(params: &'a Value, key: &str) -> Result<&'a str, CoreError> {
    if !params.is_object() {
        return Err(CoreError::invalid_params("params must be an object"));
    }
    params
        .get(key)
        .and_then(Value::as_str)
        .filter(|id| pairing_id_ok(id))
        .ok_or_else(|| CoreError::invalid_params(format!("{key} is required and must match [A-Za-z0-9_-]{{1,128}}")))
}

pub fn pending(agent: &ureq::Agent, cfg: &Config, store: &StateStore) -> Result<Value, CoreError> {
    require_machine(store)?;
    let tok = token(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Get, PENDING_PATH, None, None)?;
    let list: PendingList = http::parse_json("/v2/phone-pairings", &reply)?;
    let pairings = list.pairings.iter().filter(|p| pairing_id_ok(&p.pairing_id)).collect::<Vec<_>>();
    Ok(json!({"pairings": pairings}))
}

/// `POST /v2/phone-pairings/<id>/<verb>`; the id is checked before anything is sent.
fn decide(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value, verb: &str) -> Result<Value, CoreError> {
    let id = id_param(params, "pairing_id")?;
    require_machine(store)?;
    let path = format!("/v2/phone-pairings/{id}/{verb}");
    let tok = token(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Post, &path, None, None)?;
    http::check_status(&path, &reply)?;
    Ok(json!({}))
}

pub fn approve(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError> {
    decide(agent, cfg, store, params, "approve")
}

pub fn deny(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError> {
    decide(agent, cfg, store, params, "deny")
}

pub fn grants(agent: &ureq::Agent, cfg: &Config, store: &StateStore) -> Result<Value, CoreError> {
    require_machine(store)?;
    let tok = token(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Get, GRANTS_PATH, None, None)?;
    let list: GrantList = http::parse_json(GRANTS_PATH, &reply)?;
    let grants = list.grants.iter().filter(|g| pairing_id_ok(&g.grant_id)).collect::<Vec<_>>();
    Ok(json!({"grants": grants}))
}

pub fn revoke(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError> {
    let id = id_param(params, "grant_id")?;
    require_machine(store)?;
    let path = format!("{GRANTS_PATH}/{id}");
    let tok = token(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Delete, &path, None, None)?;
    http::check_status(&path, &reply)?;
    Ok(json!({}))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debug_hides_key_and_proof() {
        let item: PendingItem = serde_json::from_value(json!({
            "pairing_id": "p1", "device_name": "iPhone", "platform": "ios",
            "client_key_b64": "KEY-SECRET", "proof_b64": "PROOF-SECRET", "created_at_unix": 1
        }))
        .unwrap();
        let d = format!("{item:?}");
        assert!(!d.contains("KEY-SECRET") && !d.contains("PROOF-SECRET"), "{d}");
    }
}
