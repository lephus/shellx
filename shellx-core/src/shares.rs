//! `shares.*`: owner side of share links (`/v2/shares`).
//!
//! `shares.create` sends only `{permission, lifetime, one_time, access}`. The
//! link secret never reaches the core; `access` is the HKDF-derived token and
//! any other param (a stray `secret` included) is dropped, not forwarded.
//! Ids are 8 chars; a display dash (`xxxx-xxxx`) is stripped before any call.

use crate::auth;
use crate::config::Config;
use crate::envelope::CoreError;
use crate::http::{self, Method};
use crate::store::StateStore;
use serde::Serialize;
use serde_json::{Value, json};
use zeroize::Zeroizing;

const TICKET_MAX_BYTES: usize = 4096;
const ACCESS_LEN: usize = 43;

#[derive(Serialize)]
struct CreateBody<'a> {
    permission: &'a str,
    lifetime: &'a str,
    one_time: bool,
    access: &'a str,
}

fn bearer(store: &StateStore) -> Result<Zeroizing<String>, CoreError> {
    let session = auth::load_session(store)?
        .ok_or_else(|| CoreError::new("not_logged_in", "auth.login has not been called"))?;
    Ok(Zeroizing::new(session.token.clone()))
}

/// Normalize a share id: strip one display dash, require 8 lowercase alphanumerics.
fn share_id(params: &Value) -> Result<String, CoreError> {
    let raw = params
        .get("id")
        .and_then(Value::as_str)
        .ok_or_else(|| CoreError::invalid_params("id must be a string"))?;
    let id: String = raw.chars().filter(|c| *c != '-').collect();
    if id.len() != 8 || !id.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit()) {
        return Err(CoreError::invalid_params("id must be 8 characters like k7f29qd1"));
    }
    Ok(id)
}

pub fn create(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError> {
    const PATH: &str = "/v2/shares";
    if !params.is_object() {
        return Err(CoreError::invalid_params("params must be an object"));
    }
    let permission = match params.get("permission").and_then(Value::as_str) {
        Some(p @ ("view" | "type")) => p,
        _ => return Err(CoreError::invalid_params("permission must be \"view\" or \"type\"")),
    };
    let lifetime = match params.get("lifetime").and_then(Value::as_str) {
        Some(l @ ("15m" | "1h" | "until_quit")) => l,
        _ => return Err(CoreError::invalid_params("lifetime must be \"15m\", \"1h\" or \"until_quit\"")),
    };
    let one_time = match params.get("one_time") {
        None | Some(Value::Null) => false,
        Some(Value::Bool(b)) => *b,
        Some(_) => return Err(CoreError::invalid_params("one_time must be a boolean")),
    };
    let access = params.get("access").and_then(Value::as_str).filter(|a| {
        a.len() == ACCESS_LEN && a.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-' || c == b'_')
    });
    let Some(access) = access else {
        return Err(CoreError::invalid_params("access must be a 43-character base64url token"));
    };
    let body = Zeroizing::new(
        serde_json::to_vec(&CreateBody { permission, lifetime, one_time, access })
            .map_err(|_| CoreError::invalid_params("share body is not serializable"))?,
    );
    let tok = bearer(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Post, PATH, Some(&body), None)?;
    let v: Value = http::parse_json(PATH, &reply)?;
    let id = v.get("id").and_then(Value::as_str).filter(|s| !s.is_empty());
    let slot = v.get("slot").and_then(Value::as_str).filter(|s| !s.is_empty());
    let (Some(id), Some(slot), Some(exp)) = (id, slot, v.get("expires_at_unix").and_then(Value::as_u64)) else {
        return Err(CoreError::new("server", format!("{PATH}: response has no id, slot or expires_at_unix")));
    };
    Ok(json!({
        "id": id,
        "slot": slot,
        "expires_at_unix": exp,
        "claim_until_unix": v.get("claim_until_unix").and_then(Value::as_u64),
    }))
}

pub fn list(agent: &ureq::Agent, cfg: &Config, store: &StateStore) -> Result<Value, CoreError> {
    const PATH: &str = "/v2/shares";
    let tok = bearer(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Get, PATH, None, None)?;
    let v: Value = http::parse_json(PATH, &reply)?;
    match v.get("shares") {
        Some(s) if s.is_array() => Ok(json!({ "shares": s })),
        _ => Err(CoreError::new("server", format!("{PATH}: response has no shares array"))),
    }
}

pub fn revoke(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError> {
    let path = format!("/v2/shares/{}", share_id(params)?);
    let tok = bearer(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Delete, &path, None, None)?;
    http::check_status(&path, &reply)?;
    Ok(json!({}))
}

pub fn host_ticket(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError> {
    let path = format!("/v2/shares/{}/host-ticket", share_id(params)?);
    let tok = bearer(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Post, &path, None, None)?;
    let resp: crate::api::MintResponse = http::parse_json(&path, &reply)?;
    if resp.ticket.is_empty() || resp.ticket.len() > TICKET_MAX_BYTES || resp.relay_url.is_empty() {
        return Err(CoreError::new("server", format!("{path}: response has no usable ticket or relay_url")));
    }
    Ok(json!({
        "ticket": resp.ticket,
        "expires_at_unix": resp.expires_at_unix,
        "relay_url": resp.relay_url,
    }))
}
