//! `account.identities.list` / `account.identities.remove`: the sign-in methods of the account
//! (`GET /v1/account/identities`, `DELETE /v1/account/identities/<id>`). Both need a session.
//! The relay owns every rule (`last_google_identity`, `identity_not_found`); codes pass through.

use crate::auth;
use crate::config::Config;
use crate::envelope::CoreError;
use crate::http::{self, Method};
use crate::pairing::pairing_id_ok;
use crate::store::StateStore;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use zeroize::Zeroizing;

const IDENTITIES_PATH: &str = "/v1/account/identities";

#[derive(Debug, Deserialize, Serialize)]
struct IdentityItem {
    identity_id: String,
    #[serde(default)]
    provider: String,
    #[serde(default)]
    email: String,
    #[serde(default)]
    is_private_email: bool,
    #[serde(default)]
    linked_via_device_name: Option<String>,
    #[serde(default)]
    created_at_unix: u64,
}

#[derive(Debug, Deserialize)]
struct IdentityList {
    identities: Vec<IdentityItem>,
}

fn token(store: &StateStore) -> Result<Zeroizing<String>, CoreError> {
    let s = auth::load_session(store)?.ok_or_else(|| CoreError::new("not_logged_in", "auth.login has not been called"))?;
    Ok(Zeroizing::new(s.token.clone()))
}

pub fn list_identities(agent: &ureq::Agent, cfg: &Config, store: &StateStore) -> Result<Value, CoreError> {
    let tok = token(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Get, IDENTITIES_PATH, None, None)?;
    let list: IdentityList = http::parse_json(IDENTITIES_PATH, &reply)?;
    let identities = list.identities.iter().filter(|i| pairing_id_ok(&i.identity_id)).collect::<Vec<_>>();
    Ok(json!({"identities": identities}))
}

pub fn remove_identity(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError> {
    let id = params
        .get("identity_id")
        .and_then(Value::as_str)
        .filter(|id| pairing_id_ok(id))
        .ok_or_else(|| CoreError::invalid_params("identity_id is required and must match [A-Za-z0-9_-]{1,128}"))?;
    let path = format!("{IDENTITIES_PATH}/{id}");
    let tok = token(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Delete, &path, None, None)?;
    http::check_status(&path, &reply)?;
    Ok(json!({}))
}
