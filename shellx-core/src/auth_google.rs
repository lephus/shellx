//! Google sign-in for the desktop: loopback OAuth with PKCE (S256), driven by the core.
//!
//! `begin` asks the relay for a nonce, opens a `127.0.0.1` listener and returns the Google URL;
//! the app opens it in the system browser. Secrets (state, verifier, nonce) live in the `Flow`,
//! never in a result, an error message or a `Debug`.

use crate::api::NonceResponse;
use crate::config::Config;
use crate::envelope::CoreError;
use crate::http::{self, Method};
use crate::store::StateStore;
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::net::TcpListener;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use zeroize::Zeroizing;

pub const FLOW_TIMEOUT: Duration = Duration::from_secs(300);
pub const CALLBACK_PATH: &str = "/oauth2/callback";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Purpose {
    SignIn,
    Link,
}

pub struct Flow {
    pub purpose: Purpose,
    pub state: Zeroizing<String>,
    pub verifier: Zeroizing<String>,
    pub nonce: Zeroizing<String>,
    pub redirect_uri: String,
    pub listener: Mutex<Option<TcpListener>>,
    pub deadline: Instant,
    pub cancelled: AtomicBool,
}

pub type Flows = Mutex<HashMap<String, Arc<Flow>>>;

/// RFC 3986 unreserved characters are kept, everything else becomes `%XX` (uppercase).
pub fn percent_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_' | b'~') {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

fn percent_decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        match b[i] {
            b'+' => out.push(b' '),
            b'%' => match s.get(i + 1..i + 3).and_then(|h| u8::from_str_radix(h, 16).ok()) {
                Some(v) => {
                    out.push(v);
                    i += 2;
                }
                None => out.push(b'%'),
            },
            c => out.push(c),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// `a=b&c=d` → pairs, `+` is a space, `%XX` decoded, order kept.
pub fn parse_query(q: &str) -> Vec<(String, String)> {
    q.split('&')
        .filter(|kv| !kv.is_empty())
        .map(|kv| {
            let (k, v) = kv.split_once('=').unwrap_or((kv, ""));
            (percent_decode(k), percent_decode(v))
        })
        .collect()
}

/// `b64url(SHA-256(verifier))`, no padding.
pub fn pkce_challenge(verifier: &str) -> String {
    URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()))
}

fn random_b64url(n: usize) -> Result<Zeroizing<String>, CoreError> {
    let mut b = Zeroizing::new(vec![0u8; n]);
    getrandom::fill(&mut b[..]).map_err(|_| CoreError::new("crypto", "random source unavailable"))?;
    Ok(Zeroizing::new(URL_SAFE_NO_PAD.encode(&b[..])))
}

fn nonce_ok(n: &str) -> bool {
    n.len() == 43 && n.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-' || c == b'_')
}

fn purpose_of(params: &Value) -> Result<Purpose, CoreError> {
    match params.get("purpose").and_then(Value::as_str) {
        Some("sign_in") => Ok(Purpose::SignIn),
        Some("link") => Ok(Purpose::Link),
        _ => Err(CoreError::invalid_params("purpose must be \"sign_in\" or \"link\"")),
    }
}

/// `auth.google.begin {purpose}` → `{flow_id, auth_url}`.
pub fn begin(agent: &ureq::Agent, cfg: &Config, store: &StateStore, flows: &Flows, params: &Value) -> Result<Value, CoreError> {
    if !params.is_object() {
        return Err(CoreError::invalid_params("params must be an object"));
    }
    let purpose = purpose_of(params)?;
    if purpose == Purpose::Link && crate::auth::load_session(store)?.is_none() {
        return Err(CoreError::new("not_logged_in", "auth.login has not been called"));
    }
    if cfg.google_client_id.is_empty() {
        return Err(CoreError::new("not_configured", "this build has no Google desktop client id"));
    }
    // One flow at a time: an older one ends google_cancelled; expired ones are forgotten.
    {
        let mut map = flows.lock().unwrap_or_else(|p| p.into_inner());
        let now = Instant::now();
        map.retain(|_, f| f.deadline > now);
        for f in map.values() {
            f.cancelled.store(true, Ordering::SeqCst);
            *f.listener.lock().unwrap_or_else(|p| p.into_inner()) = None;
        }
    }
    const NONCE_PATH: &str = "/v1/auth/nonce";
    let reply = http::send(agent, cfg, None, Method::Post, NONCE_PATH, Some(b"{}"), None)?;
    let resp: NonceResponse = http::parse_json(NONCE_PATH, &reply)?;
    if !nonce_ok(&resp.nonce) {
        return Err(CoreError::new("server", format!("{NONCE_PATH}: unexpected nonce")));
    }
    let nonce = Zeroizing::new(resp.nonce.clone());
    let listener = TcpListener::bind("127.0.0.1:0").map_err(|e| CoreError::new("io", format!("loopback listener: {e}")))?;
    listener.set_nonblocking(true).map_err(|e| CoreError::new("io", format!("loopback listener: {e}")))?;
    let port = listener.local_addr().map_err(|e| CoreError::new("io", format!("loopback listener: {e}")))?.port();
    let redirect_uri = format!("http://127.0.0.1:{port}{CALLBACK_PATH}");
    let state = random_b64url(32)?;
    let verifier = random_b64url(32)?;
    let flow_id = random_b64url(16)?.to_string();
    let auth_url = format!(
        "{}?client_id={}&redirect_uri={}&response_type=code&scope=openid%20email%20profile&state={}&nonce={}&code_challenge={}&code_challenge_method=S256&prompt=select_account",
        cfg.google_auth_url,
        percent_encode(&cfg.google_client_id),
        percent_encode(&redirect_uri),
        percent_encode(&state),
        percent_encode(&nonce),
        pkce_challenge(&verifier),
    );
    let flow = Flow {
        purpose,
        state,
        verifier,
        nonce,
        redirect_uri,
        listener: Mutex::new(Some(listener)),
        deadline: Instant::now() + FLOW_TIMEOUT,
        cancelled: AtomicBool::new(false),
    };
    flows.lock().unwrap_or_else(|p| p.into_inner()).insert(flow_id.clone(), Arc::new(flow));
    Ok(json!({"flow_id": flow_id, "auth_url": auth_url}))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn percent_encode_keeps_only_unreserved() {
        assert_eq!(percent_encode("a b&c=d/é~-._"), "a%20b%26c%3Dd%2F%C3%A9~-._");
    }

    #[test]
    fn parse_query_decodes_percent_and_plus() {
        assert_eq!(
            parse_query("code=4%2F0Ab-x&state=s+t&e="),
            vec![("code".into(), "4/0Ab-x".into()), ("state".into(), "s t".into()), ("e".into(), String::new())]
        );
    }

    #[test]
    fn pkce_challenge_is_rfc7636_s256() {
        assert_eq!(pkce_challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
    }
}
