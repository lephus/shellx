//! `pair.request` / `pair.pending` / `pair.approve` / `pair.deny` / `pair.poll` (D5, D9).
//!
//! A requester Mac asks a target Mac for access. The target's user compares the
//! code and the fingerprint on both screens and approves; the target then seals
//! a cmux enrollment invite to the requester's device key (D4, AAD = pairing id),
//! the server stores only ciphertext, and the requester opens it here.
//!
//! * Every fingerprint shown is computed locally from the key bytes (D1); the
//!   server's `requester_fingerprint` is only compared, never trusted.
//! * `pair.approve` re-fetches the target list and refuses (`not_found`,
//!   `pairing_not_pending`, `contract_missing_requester_key`,
//!   `fingerprint_mismatch`) **before** any POST; it seals to the exact key bytes
//!   whose fingerprint it checked.
//! * The invite URI is a secret (it carries the enrollment PSK and a relay
//!   ticket): it is never logged, never put in an error, and returned by
//!   `pair.poll` only when `write_invite_to` is absent. With `write_invite_to` it
//!   is written owner-only to `<state_dir>/tickets/<name>` (the caller deletes it
//!   after use).
//! * `pairing_id` goes into URL paths, so it must match `^[A-Za-z0-9_-]{1,128}$`.

use crate::auth;
use crate::config::Config;
use crate::envelope::CoreError;
use crate::fingerprint::fingerprint;
use crate::http::{self, Method};
use crate::machines::require_machine;
use crate::seal::{self, URI_PREFIX};
use crate::store::{self, StateStore};
use base64::Engine;
use base64::engine::general_purpose::{STANDARD, STANDARD_NO_PAD, URL_SAFE, URL_SAFE_NO_PAD};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::fmt;
use zeroize::Zeroizing;

const PATH: &str = "/v2/pairings";
const PAIRING_ID_MAX: usize = 128;
const STATUSES: &[&str] = &["pending", "approved", "denied", "expired"];
/// cmux `MAX_RELAY_SLOT_BYTES` (`cmux-remote/src/identity.rs:35`).
const SLOT_MAX_BYTES: usize = 256;
/// cmux `STATE_VERSION` (`cmux-remote/src/identity.rs:22`).
const INVITE_VERSION: u32 = 1;

/// `POST /v2/pairings` body.
#[derive(Debug, Serialize)]
struct CreateRequest<'a> {
    from_machine_id: &'a str,
    to_machine_id: &'a str,
    requester_x25519_b64: &'a str,
}

/// `POST /v2/pairings` 201 response.
#[derive(Debug, Deserialize)]
struct CreateResponse {
    pairing_id: String,
    code: String,
}

/// One item of `GET /v2/pairings?role=…`.
#[derive(Deserialize)]
struct PairingItem {
    pairing_id: String,
    #[serde(default)]
    from_machine_id: String,
    #[serde(default)]
    to_machine_id: String,
    #[serde(default)]
    requester_fingerprint: String,
    #[serde(default)]
    requester_x25519_b64: Option<String>,
    #[serde(default)]
    code: String,
    #[serde(default)]
    status: String,
    #[serde(default)]
    sealed_invite_b64: Option<String>,
}

/// Shows the sealed invite's length only.
impl fmt::Debug for PairingItem {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PairingItem")
            .field("pairing_id", &self.pairing_id)
            .field("from_machine_id", &self.from_machine_id)
            .field("to_machine_id", &self.to_machine_id)
            .field("status", &self.status)
            .field("sealed_invite_len", &self.sealed_invite_b64.as_ref().map(String::len))
            .finish_non_exhaustive()
    }
}

#[derive(Debug, Deserialize)]
struct PairingList {
    pairings: Vec<PairingItem>,
}

/// The non-secret part of a cmux `EnrollmentInvitation`
/// (`cmux-remote/src/identity.rs:67-79`). `secret` and `relay_access[].ticket`
/// are deliberately not deserialized.
#[derive(Debug, Deserialize)]
struct InviteView {
    version: u32,
    daemon_public_key: String,
    daemon_fingerprint: String,
    #[serde(default)]
    relay_access: Vec<RelayAccessView>,
}

/// `EnrollmentRelayAccess` without its `ticket` (`identity.rs:48-53`).
#[derive(Debug, Deserialize)]
struct RelayAccessView {
    route: String,
    slot: String,
}

/// What the requester learns from an invite (all non-secret).
#[derive(Debug, PartialEq, Eq)]
struct InviteSummary {
    relay_route: String,
    relay_slot: String,
    daemon_fingerprint: String,
}

/// Parse a `cmux://enroll/<b64url-nopad JSON>` URI the way cmux's
/// `EnrollmentInvitation::from_uri` does (`identity.rs:118-145`): version 1, daemon
/// key matches its fingerprint (`crypto.rs:72`), first relay access uses a
/// `relay+` scheme (`identity.rs:2338`) with a usable slot. `None` on any failure;
/// nothing about the URI is reported.
fn parse_invite(uri: &str) -> Option<InviteSummary> {
    let encoded = uri.strip_prefix(URI_PREFIX)?;
    let json = Zeroizing::new(URL_SAFE_NO_PAD.decode(encoded).ok()?);
    let inv: InviteView = serde_json::from_slice(&json).ok()?;
    if inv.version != INVITE_VERSION {
        return None;
    }
    let key = URL_SAFE_NO_PAD.decode(&inv.daemon_public_key).ok().filter(|k| k.len() == 32)?;
    if URL_SAFE_NO_PAD.encode(&Sha256::digest(&key)[..16]) != inv.daemon_fingerprint {
        return None;
    }
    let first = inv.relay_access.into_iter().next()?;
    let scheme = first.route.split_once("://").map(|(s, _)| s)?;
    if !matches!(scheme, "relay+ws" | "relay+wss" | "relay+https" | "relay+do") {
        return None;
    }
    let slot_ok = !first.slot.is_empty()
        && first.slot.len() <= SLOT_MAX_BYTES
        && !first.slot.bytes().any(|b| b.is_ascii_whitespace() || b.is_ascii_control());
    if !slot_ok {
        return None;
    }
    Some(InviteSummary { relay_route: first.route, relay_slot: first.slot, daemon_fingerprint: inv.daemon_fingerprint })
}

/// A 32-byte public key in standard or URL-safe base64, padded or not (K1 `*_b64`;
/// L4 returns `requester_x25519_b64` in standard base64).
fn decode_key(b64: &str) -> Option<[u8; 32]> {
    [&URL_SAFE_NO_PAD, &URL_SAFE, &STANDARD, &STANDARD_NO_PAD]
        .iter()
        .find_map(|e| e.decode(b64).ok())
        .and_then(|raw| <[u8; 32]>::try_from(raw).ok())
}

fn pairing_id_ok(id: &str) -> bool {
    (1..=PAIRING_ID_MAX).contains(&id.len()) && id.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_' || c == b'-')
}

fn object(params: &Value) -> Result<(), CoreError> {
    if params.is_object() { Ok(()) } else { Err(CoreError::invalid_params("params must be an object")) }
}

fn pairing_id_param(params: &Value) -> Result<&str, CoreError> {
    params
        .get("pairing_id")
        .and_then(Value::as_str)
        .filter(|id| pairing_id_ok(id))
        .ok_or_else(|| CoreError::invalid_params("pairing_id is required and must match [A-Za-z0-9_-]{1,128}"))
}

fn token(store: &StateStore) -> Result<Zeroizing<String>, CoreError> {
    let s = auth::load_session(store)?.ok_or_else(|| CoreError::new("not_logged_in", "auth.login has not been called"))?;
    Ok(Zeroizing::new(s.token.clone()))
}

fn fetch(agent: &ureq::Agent, cfg: &Config, store: &StateStore, role: &str) -> Result<Vec<PairingItem>, CoreError> {
    let path = format!("{PATH}?role={role}");
    let tok = token(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Get, &path, None, None)?;
    Ok(http::parse_json::<PairingList>(PATH, &reply)?.pairings)
}

/// The locally computed fingerprint of an item's requester key, and the key.
fn requester_key(item: &PairingItem) -> Option<([u8; 32], String)> {
    let key = decode_key(item.requester_x25519_b64.as_deref()?)?;
    let fp = fingerprint(&key);
    Some((key, fp))
}

pub fn request(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError> {
    object(params)?;
    let to = params
        .get("to_machine_id")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| CoreError::invalid_params("to_machine_id is required and must be a non-empty string"))?;
    // `from_machine_id` is always the stored own id; any caller value is ignored.
    let own = require_machine(store)?;
    if to == own.machine_id {
        return Err(CoreError::invalid_params("to_machine_id is this machine"));
    }
    let public = auth::device_public(store)?;
    let public_b64 = URL_SAFE_NO_PAD.encode(public);
    let body = serde_json::to_vec(&CreateRequest {
        from_machine_id: &own.machine_id,
        to_machine_id: to,
        requester_x25519_b64: &public_b64,
    })
    .map_err(|_| CoreError::invalid_params("pairing body is not serializable"))?;
    let tok = token(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Post, PATH, Some(&body), None)?;
    let resp: CreateResponse = http::parse_json(PATH, &reply)?;
    if !pairing_id_ok(&resp.pairing_id) || resp.code.is_empty() {
        return Err(CoreError::new("server", format!("{PATH}: response has no usable pairing_id or code")));
    }
    Ok(json!({"pairing_id": resp.pairing_id, "code": resp.code, "fingerprint": fingerprint(&public)}))
}

pub fn pending(agent: &ureq::Agent, cfg: &Config, store: &StateStore) -> Result<Value, CoreError> {
    let own = require_machine(store)?;
    let items = fetch(agent, cfg, store, "target")?;
    let pairings: Vec<Value> = items
        .iter()
        .filter(|it| it.status == "pending" && it.to_machine_id == own.machine_id && pairing_id_ok(&it.pairing_id))
        .map(|it| {
            // No usable key (D2 not deployed) → suspicious, and approve refuses it.
            let fp = requester_key(it).map(|(_, fp)| fp);
            let suspicious = fp.as_deref() != Some(it.requester_fingerprint.as_str());
            json!({
                "pairing_id": it.pairing_id,
                "from_machine_id": it.from_machine_id,
                "code": it.code,
                "fingerprint": fp.unwrap_or_default(),
                "server_fingerprint": it.requester_fingerprint,
                "suspicious": suspicious,
            })
        })
        .collect();
    Ok(json!({"pairings": pairings}))
}

pub fn approve(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError> {
    object(params)?;
    let pairing_id = pairing_id_param(params)?;
    let invite_uri = params
        .get("invite_uri")
        .and_then(Value::as_str)
        .ok_or_else(|| CoreError::invalid_params("invite_uri is required and must be a string"))?;
    // Optional: the fingerprint the user compared on screen. When given, the key
    // sealed to must still have it (closes a key swap between pending and approve).
    let shown = match params.get("fingerprint") {
        None | Some(Value::Null) => None,
        Some(Value::String(f)) => Some(f.as_str()),
        Some(_) => return Err(CoreError::invalid_params("fingerprint must be a string")),
    };
    if invite_uri.len() > seal::URI_MAX_BYTES || parse_invite(invite_uri).is_none() {
        return Err(CoreError::invalid_params(
            "invite_uri is not a cmux enrollment invite with a relay+ route and slot",
        ));
    }
    let own = require_machine(store)?;
    // Every refusal happens before any POST.
    let items = fetch(agent, cfg, store, "target")?;
    let item = items
        .iter()
        .find(|it| it.pairing_id == pairing_id && it.to_machine_id == own.machine_id)
        .ok_or_else(|| CoreError::new("not_found", "no pairing with that id targets this machine"))?;
    if item.status != "pending" {
        return Err(CoreError::new("pairing_not_pending", format!("pairing is {}", status_label(&item.status))));
    }
    let (key, fp) = requester_key(item).ok_or_else(|| {
        CoreError::new("contract_missing_requester_key", "the server did not send a usable requester_x25519_b64")
    })?;
    if fp != item.requester_fingerprint {
        return Err(CoreError::new("fingerprint_mismatch", "requester key does not match the server fingerprint"));
    }
    if shown.is_some_and(|s| s != fp) {
        return Err(CoreError::new("fingerprint_mismatch", "requester key does not match the fingerprint shown"));
    }
    // Sealed to `key`, the exact bytes `fp` was computed from.
    let sealed = seal::seal_invite(&key, pairing_id, invite_uri)?;
    let body = serde_json::to_vec(&json!({"sealed_invite_b64": sealed}))
        .map_err(|_| CoreError::invalid_params("approve body is not serializable"))?;
    let path = format!("{PATH}/{pairing_id}/approve");
    let tok = token(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Post, &path, Some(&body), None)?;
    http::check_status(&path, &reply)?;
    Ok(json!({}))
}

pub fn deny(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError> {
    object(params)?;
    let pairing_id = pairing_id_param(params)?;
    let path = format!("{PATH}/{pairing_id}/deny");
    let tok = token(store)?;
    let reply = http::send(agent, cfg, Some(&tok), Method::Post, &path, None, None)?;
    http::check_status(&path, &reply)?;
    Ok(json!({}))
}

pub fn poll(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError> {
    object(params)?;
    let pairing_id = pairing_id_param(params)?;
    let write_to = match params.get("write_invite_to") {
        None | Some(Value::Null) => None,
        Some(Value::String(w)) if store::bare_file_name_ok(w) => Some(format!("tickets/{w}")),
        Some(_) => return Err(CoreError::invalid_params("write_invite_to must be a bare file name like invite.uri")),
    };
    let own = require_machine(store)?;
    let items = fetch(agent, cfg, store, "requester")?;
    let item = items
        .iter()
        .find(|it| it.pairing_id == pairing_id && it.from_machine_id == own.machine_id)
        .ok_or_else(|| CoreError::new("not_found", "no pairing with that id was requested by this machine"))?;
    if !STATUSES.contains(&item.status.as_str()) {
        return Err(CoreError::new("server", format!("{PATH}: unknown pairing status")));
    }
    if item.status != "approved" {
        return Ok(json!({"status": item.status}));
    }
    let sealed = item.sealed_invite_b64.as_deref().filter(|s| !s.is_empty()).ok_or_else(invite_invalid)?;
    let secret = auth::device_secret(store)?;
    // AAD = this pairing id: an invite sealed for another pairing does not open.
    let uri = seal::open_invite(&secret, pairing_id, sealed)?;
    drop(secret);
    let summary = parse_invite(&uri).ok_or_else(invite_invalid)?;
    let mut out = json!({
        "status": "approved",
        "relay_route": summary.relay_route,
        "relay_slot": summary.relay_slot,
        "daemon_fingerprint": summary.daemon_fingerprint,
    });
    match write_to {
        Some(name) => {
            let path = store.write_secret(&name, uri.as_bytes())?;
            out["invite_path"] = json!(path.to_string_lossy());
        }
        None => out["invite_uri"] = json!(uri.as_str()),
    }
    Ok(out)
}

/// Same code and fixed message as `seal::open_invite` failures.
fn invite_invalid() -> CoreError {
    CoreError::new("invite_invalid", "sealed invite could not be opened")
}

/// A server status for a message: known values verbatim, anything else generic.
fn status_label(status: &str) -> &str {
    if STATUSES.contains(&status) { status } else { "not pending" }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn uri_of(v: &Value) -> String {
        format!("{URI_PREFIX}{}", URL_SAFE_NO_PAD.encode(v.to_string()))
    }

    fn valid() -> Value {
        let key = [5u8; 32];
        json!({
            "version": 1, "id": "inv1", "secret": "c2VjcmV0", "daemon_public_key": URL_SAFE_NO_PAD.encode(key),
            "daemon_fingerprint": URL_SAFE_NO_PAD.encode(&Sha256::digest(key)[..16]), "daemon_name": "B",
            "expires_at_unix": 1, "route_hints": ["relay+wss://r/v2/relay"], "approval_required": true,
            "relay_access": [{"route": "relay+wss://r/v2/relay", "slot": "s1", "ticket": "t"}],
        })
    }

    #[test]
    fn parse_invite_reads_cmux_shape_and_refuses_the_rest() {
        let s = parse_invite(&uri_of(&valid())).unwrap();
        assert_eq!((s.relay_route.as_str(), s.relay_slot.as_str()), ("relay+wss://r/v2/relay", "s1"));
        let mut bad = Vec::new();
        for (k, v) in [
            ("version", json!(2)),
            ("daemon_fingerprint", json!("AAAA")),
            ("daemon_public_key", json!("short")),
            ("relay_access", json!([])),
            ("relay_access", json!([{"route": "wss://r/v2/relay", "slot": "s1", "ticket": "t"}])),
            ("relay_access", json!([{"route": "relay+wss://r", "slot": "a b", "ticket": "t"}])),
            ("relay_access", json!([{"route": "relay+wss://r", "slot": "x".repeat(257), "ticket": "t"}])),
        ] {
            let mut v2 = valid();
            v2[k] = v;
            bad.push(uri_of(&v2));
        }
        // Padded base64 (cmux uses URL_SAFE_NO_PAD), wrong prefix, not JSON.
        let padded = ["", " ", "  "]
            .iter()
            .map(|pad| URL_SAFE.encode(format!("{}{pad}", valid())))
            .find(|e| e.ends_with('='))
            .unwrap();
        let padded = format!("{URI_PREFIX}{padded}");
        bad.extend([padded, "cmux://pair/x".into(), format!("{URI_PREFIX}bm90LWpzb24")]);
        for u in bad {
            assert!(parse_invite(&u).is_none(), "{u}");
        }
    }

    #[test]
    fn decode_key_accepts_both_alphabets() {
        let k = [0xfbu8; 32];
        for s in [URL_SAFE_NO_PAD.encode(k), URL_SAFE.encode(k), STANDARD.encode(k), STANDARD_NO_PAD.encode(k)] {
            assert_eq!(decode_key(&s), Some(k), "{s}");
        }
        assert_eq!(decode_key(&STANDARD.encode([1u8; 31])), None);
    }

    #[test]
    fn pairing_ids_are_path_safe() {
        assert!(pairing_id_ok("3f2a9c1e-0b4d-4e8f-9a7b-1c2d3e4f5a6b"));
        for id in ["", "../x", "a/b", "a?b", "a b", "a%2f", &"a".repeat(129)] {
            assert!(!pairing_id_ok(id), "{id}");
        }
    }
}
