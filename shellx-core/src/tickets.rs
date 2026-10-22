//! `tickets.mint`: relay tickets from `POST /v2/relay/tickets`.
//!
//! With `write_to` (a bare file name) the ticket is written owner-only to
//! `<state_dir>/tickets/<write_to>` and is never returned or logged.

use crate::api::{MintRequest, MintResponse};
use crate::auth;
use crate::config::Config;
use crate::envelope::CoreError;
use crate::http::{self, Method};
use crate::machines::require_machine;
use crate::store::StateStore;
use serde_json::{Value, json};
use zeroize::Zeroizing;

const TICKET_MAX_BYTES: usize = 4096;

pub fn mint(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError> {
    const PATH: &str = "/v2/relay/tickets";
    if !params.is_object() {
        return Err(CoreError::invalid_params("params must be an object"));
    }
    let permission = match params.get("permission").and_then(Value::as_str) {
        Some(p @ ("register" | "connect")) => p,
        _ => return Err(CoreError::invalid_params("permission must be \"register\" or \"connect\"")),
    };
    let target = match params.get("target_machine_id") {
        None | Some(Value::Null) => None,
        Some(Value::String(t)) if !t.is_empty() => Some(t.as_str()),
        Some(_) => return Err(CoreError::invalid_params("target_machine_id must be a non-empty string")),
    };
    if permission == "connect" && target.is_none() {
        return Err(CoreError::invalid_params("target_machine_id is required for connect"));
    }
    let lane = match params.get("lane") {
        None | Some(Value::Null) => None,
        Some(Value::String(l)) if l == "link" => Some("link"),
        Some(_) => return Err(CoreError::invalid_params("lane must be \"link\" or absent")),
    };
    let write_to = match params.get("write_to") {
        None | Some(Value::Null) => None,
        Some(Value::String(w)) => Some(w.as_str()),
        Some(_) => return Err(CoreError::invalid_params("write_to must be a string")),
    };
    // Validate the file name before any request (the store re-validates on write).
    if write_to.is_some_and(|w| !crate::store::bare_file_name_ok(w)) {
        return Err(CoreError::invalid_params("write_to must be a bare file name like register.ticket"));
    }
    let target_name = write_to.map(|w| format!("tickets/{w}"));
    let m = require_machine(store)?;
    // A relay that predates ShellX Link ignores `lane` and would mint a cmux-slot ticket: never ask it.
    if lane.is_some() && m.link_slot.is_none() {
        return Err(CoreError::new("not_registered", "machines.register must be called again to get a link_slot"));
    }
    let body = serde_json::to_vec(&MintRequest { machine_id: &m.machine_id, permission, target_machine_id: target, lane })
        .map_err(|_| CoreError::invalid_params("mint body is not serializable"))?;
    let session = auth::load_session(store)?
        .ok_or_else(|| CoreError::new("not_logged_in", "auth.login has not been called"))?;
    let tok = Zeroizing::new(session.token.clone());
    drop(session);
    let reply = http::send(agent, cfg, Some(&tok), Method::Post, PATH, Some(&body), None)?;
    let resp: MintResponse = http::parse_json(PATH, &reply)?;
    if resp.ticket.is_empty() || resp.ticket.len() > TICKET_MAX_BYTES || resp.relay_url.is_empty() {
        return Err(CoreError::new("server", format!("{PATH}: response has no usable ticket or relay_url")));
    }
    match target_name {
        Some(name) => {
            let path = store.write_secret(&name, resp.ticket.as_bytes())?;
            Ok(json!({
                "path": path.to_string_lossy(),
                "expires_at_unix": resp.expires_at_unix,
                "relay_url": resp.relay_url,
            }))
        }
        None => Ok(json!({
            "ticket": resp.ticket,
            "expires_at_unix": resp.expires_at_unix,
            "relay_url": resp.relay_url,
        })),
    }
}
