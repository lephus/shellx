//! `notify.phones`: `POST /v2/notifications`, the Mac's push to the phones granted to it.
//!
//! `needs_you` says an agent waits for the user (the relay's alert names the agent and the
//! workspace, never what it asks); `resolved` says the request was handled, so the phones take the
//! alert away. Nothing about the request is logged.

use crate::auth;
use crate::config::Config;
use crate::envelope::CoreError;
use crate::http::{self, Method};
use crate::machines::require_machine;
use crate::store::StateStore;
use serde::Deserialize;
use serde_json::{Map, Value, json};
use zeroize::Zeroizing;

const PATH: &str = "/v2/notifications";
/// The relay uses the request id as `apns-collapse-id`, which takes at most 64 bytes.
const REQUEST_ID_MAX_BYTES: usize = 64;
const AGENT_MAX_CHARS: usize = 64;
const WORKSPACE_TITLE_MAX_CHARS: usize = 200;

#[derive(Deserialize)]
struct Sent {
    sent: u64,
}

pub fn phones(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError> {
    if !params.is_object() {
        return Err(CoreError::invalid_params("params must be an object"));
    }
    let kind = match params.get("kind").and_then(Value::as_str) {
        Some(k @ ("needs_you" | "resolved")) => k,
        _ => return Err(CoreError::invalid_params("kind must be \"needs_you\" or \"resolved\"")),
    };
    let request_id = params
        .get("request_id")
        .and_then(Value::as_str)
        .filter(|id| !id.is_empty() && id.len() <= REQUEST_ID_MAX_BYTES)
        .ok_or_else(|| CoreError::invalid_params("request_id must be 1 to 64 bytes"))?;
    let mut body = Map::new();
    body.insert("kind".into(), json!(kind));
    body.insert("request_id".into(), json!(request_id));
    if kind == "needs_you" {
        let agent_name = params
            .get("agent")
            .and_then(Value::as_str)
            .filter(|a| !a.trim().is_empty() && a.chars().count() <= AGENT_MAX_CHARS)
            .ok_or_else(|| CoreError::invalid_params("agent must be 1 to 64 characters"))?;
        let workspace = match params.get("workspace_title") {
            None | Some(Value::Null) => "",
            Some(Value::String(w)) if w.chars().count() <= WORKSPACE_TITLE_MAX_CHARS => w.as_str(),
            Some(_) => return Err(CoreError::invalid_params("workspace_title must be a string of at most 200 characters")),
        };
        body.insert("agent".into(), json!(agent_name));
        body.insert("workspace_title".into(), json!(workspace));
    }
    require_machine(store)?;
    let bytes = serde_json::to_vec(&Value::Object(body)).map_err(|_| CoreError::invalid_params("body is not serializable"))?;
    let session = auth::load_session(store)?
        .ok_or_else(|| CoreError::new("not_logged_in", "auth.login has not been called"))?;
    let tok = Zeroizing::new(session.token.clone());
    drop(session);
    let reply = http::send(agent, cfg, Some(&tok), Method::Post, PATH, Some(&bytes), None)?;
    let sent: Sent = http::parse_json(PATH, &reply)?;
    Ok(json!({"sent": sent.sent}))
}
