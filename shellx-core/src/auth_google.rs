//! Google sign-in for the desktop: loopback OAuth with PKCE (S256), driven by the core.
//!
//! `begin` asks the relay for a nonce, opens a `127.0.0.1` listener and returns the Google URL;
//! the app opens it in the system browser. Secrets (state, verifier, nonce) live in the `Flow`,
//! never in a result, an error message or a `Debug`.

use crate::api::{
    GoogleAuthResponse, GoogleLinkRequest, GoogleSignInRequest, GoogleTokenResponse, LoginDevice, NonceResponse, SessionFile,
};
use crate::fingerprint::fingerprint;
use crate::config::Config;
use crate::envelope::CoreError;
use crate::http::{self, Method};
use crate::store::StateStore;
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::io::{Read, Write};
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

pub const DONE_PAGE: &str = "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>ShellX</title></head><body style=\"font-family:-apple-system,'Segoe UI',sans-serif;text-align:center;margin-top:20vh\"><p>You can close this tab and return to ShellX.</p><p lang=\"vi\">Bạn có thể đóng tab này và quay lại ShellX.</p></body></html>";
pub const FAILED_PAGE: &str = "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>ShellX</title></head><body style=\"font-family:-apple-system,'Segoe UI',sans-serif;text-align:center;margin-top:20vh\"><p>Sign-in did not finish. Return to ShellX and try again.</p><p lang=\"vi\">Đăng nhập chưa hoàn tất. Hãy quay lại ShellX và thử lại.</p></body></html>";

fn respond(stream: &mut std::net::TcpStream, status: &str, body: &str) {
    let msg = format!(
        "HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    let _ = stream.write_all(msg.as_bytes());
    let _ = stream.flush();
}

/// Read one request head (at most 8 KiB, 2 s); `(method, target)` of its request line.
fn read_request(stream: &mut std::net::TcpStream) -> Option<(String, String)> {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(2)));
    let mut buf = Vec::with_capacity(1024);
    let mut chunk = [0u8; 1024];
    while buf.len() < 8192 && !buf.windows(4).any(|w| w == b"\r\n\r\n") {
        match stream.read(&mut chunk) {
            Ok(0) => break,
            Ok(n) => buf.extend_from_slice(&chunk[..n]),
            Err(_) => return None,
        }
    }
    let head = String::from_utf8_lossy(&buf).into_owned();
    let line = head.lines().next()?;
    let mut parts = line.split_whitespace();
    Some((parts.next()?.to_string(), parts.next()?.to_string()))
}

/// Accepts on `listener` (non-blocking, polled every 50 ms) until a GET of `CALLBACK_PATH` arrives,
/// the deadline passes (`google_timeout`) or `cancelled` is set (`google_cancelled`). Returns `code`.
pub fn wait_for_callback(
    listener: &TcpListener,
    expected_state: &str,
    deadline: Instant,
    cancelled: &AtomicBool,
) -> Result<Zeroizing<String>, CoreError> {
    loop {
        if cancelled.load(Ordering::SeqCst) {
            return Err(CoreError::new("google_cancelled", "Google sign-in was cancelled"));
        }
        if Instant::now() >= deadline {
            return Err(CoreError::new("google_timeout", "Google sign-in timed out"));
        }
        let mut stream = match listener.accept() {
            Ok((s, _)) => s,
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(50));
                continue;
            }
            Err(_) => {
                std::thread::sleep(Duration::from_millis(50));
                continue;
            }
        };
        // macOS hands accepted sockets the listener's non-blocking flag.
        let _ = stream.set_nonblocking(false);
        let Some((method, target)) = read_request(&mut stream) else { continue };
        if method != "GET" {
            respond(&mut stream, "405 Method Not Allowed", "");
            continue;
        }
        let (path, query) = target.split_once('?').unwrap_or((target.as_str(), ""));
        if path != CALLBACK_PATH {
            respond(&mut stream, "404 Not Found", "");
            continue;
        }
        let q = parse_query(query);
        let get = |k: &str| q.iter().find(|(n, _)| n == k).map(|(_, v)| v.as_str());
        let fail = |stream: &mut std::net::TcpStream, code: &str, msg: &str| {
            respond(stream, "200 OK", FAILED_PAGE);
            Err(CoreError::new(code, msg))
        };
        if get("state") != Some(expected_state) {
            return fail(&mut stream, "google_state_mismatch", "the sign-in response did not match this request");
        }
        if get("error").is_some() {
            return fail(&mut stream, "google_cancelled", "Google sign-in was cancelled");
        }
        let Some(code) = get("code").filter(|c| !c.is_empty()) else {
            return fail(&mut stream, "google_state_mismatch", "the sign-in response had no code");
        };
        let code = Zeroizing::new(code.to_string());
        respond(&mut stream, "200 OK", DONE_PAGE);
        return Ok(code);
    }
}

/// `auth.google.cancel {flow_id}` → `{}` (also for an unknown flow).
pub fn cancel(flows: &Flows, params: &Value) -> Result<Value, CoreError> {
    let id = params
        .get("flow_id")
        .and_then(Value::as_str)
        .ok_or_else(|| CoreError::invalid_params("flow_id is required and must be a string"))?;
    if let Some(f) = flows.lock().unwrap_or_else(|p| p.into_inner()).get(id) {
        f.cancelled.store(true, Ordering::SeqCst);
        *f.listener.lock().unwrap_or_else(|p| p.into_inner()) = None;
    }
    Ok(json!({}))
}

/// `auth.google.finish {flow_id}`: wait for the browser, exchange the code, sign in or link.
pub fn finish(
    agent: &ureq::Agent,
    cfg: &Config,
    store: &StateStore,
    flows: &Flows,
    params: &Value,
    auth_lock: &Mutex<()>,
) -> Result<Value, CoreError> {
    let id = params
        .get("flow_id")
        .and_then(Value::as_str)
        .ok_or_else(|| CoreError::invalid_params("flow_id is required and must be a string"))?
        .to_string();
    let flow = flows
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .get(&id)
        .cloned()
        .ok_or_else(|| CoreError::invalid_params("unknown flow_id"))?;
    let result = run_flow(agent, cfg, store, &flow, auth_lock);
    flows.lock().unwrap_or_else(|p| p.into_inner()).remove(&id);
    result
}

fn run_flow(agent: &ureq::Agent, cfg: &Config, store: &StateStore, flow: &Flow, auth_lock: &Mutex<()>) -> Result<Value, CoreError> {
    if flow.cancelled.load(Ordering::SeqCst) {
        return Err(CoreError::new("google_cancelled", "Google sign-in was cancelled"));
    }
    let listener = flow.listener.lock().unwrap_or_else(|p| p.into_inner()).take();
    let Some(listener) = listener else {
        return Err(if flow.cancelled.load(Ordering::SeqCst) {
            CoreError::new("google_cancelled", "Google sign-in was cancelled")
        } else {
            CoreError::invalid_params("this flow is already finishing")
        });
    };
    let code = wait_for_callback(&listener, &flow.state, flow.deadline, &flow.cancelled)?;
    drop(listener);

    let reply = http::post_form(
        agent,
        cfg,
        &cfg.google_token_url,
        &[
            ("code", code.as_str()),
            ("client_id", cfg.google_client_id.as_str()),
            ("client_secret", cfg.google_client_secret.as_str()),
            ("redirect_uri", flow.redirect_uri.as_str()),
            ("grant_type", "authorization_code"),
            ("code_verifier", flow.verifier.as_str()),
        ],
        None,
    )?;
    if !(200..300).contains(&reply.status) {
        return Err(CoreError::new("invalid_credentials", format!("Google token exchange failed ({})", reply.status)));
    }
    let tok: GoogleTokenResponse = serde_json::from_slice(&reply.body)
        .map_err(|_| CoreError::new("server", "Google token endpoint: unexpected response"))?;
    if tok.id_token.is_empty() {
        return Err(CoreError::new("server", "Google token endpoint: no id_token"));
    }

    let old = crate::auth::load_session(store).ok().flatten();
    let previous_user = old.as_ref().map(|s| s.user_id.clone());
    let public = crate::auth::device_public(store)?;
    let public_b64 = URL_SAFE_NO_PAD.encode(public);
    let resp: GoogleAuthResponse = match flow.purpose {
        Purpose::SignIn => {
            drop(old);
            const PATH: &str = "/v1/auth/google";
            let name = crate::auth::device_name(cfg);
            let body = Zeroizing::new(
                serde_json::to_vec(&GoogleSignInRequest {
                    id_token: &tok.id_token,
                    nonce: &flow.nonce,
                    device: LoginDevice { kind: "desktop", name: &name, platform: &cfg.platform, public_key: &public_b64 },
                })
                .map_err(|_| CoreError::new("io", "sign-in body is not serializable"))?,
            );
            let reply = http::send(agent, cfg, None, Method::Post, PATH, Some(&body), None)?;
            http::parse_json(PATH, &reply)?
        }
        Purpose::Link => {
            const PATH: &str = "/v1/auth/google/link";
            let Some(session) = old else {
                return Err(CoreError::new("not_logged_in", "auth.login has not been called"));
            };
            let used = Zeroizing::new(session.token.clone());
            drop(session);
            let body = Zeroizing::new(
                serde_json::to_vec(&GoogleLinkRequest { id_token: &tok.id_token, nonce: &flow.nonce })
                    .map_err(|_| CoreError::new("io", "link body is not serializable"))?,
            );
            let outcome = http::send(agent, cfg, Some(&used), Method::Post, PATH, Some(&body), None)
                .and_then(|reply| http::parse_json::<GoogleAuthResponse>(PATH, &reply));
            match outcome {
                Ok(r) => r,
                Err(e) => {
                    if e.code == "unauthorized" || e.code == "http_401" {
                        crate::auth::forget_session_if(store, &used, auth_lock);
                    }
                    return Err(e);
                }
            }
        }
    };
    if resp.token.is_empty() || resp.user_id.is_empty() || resp.device_id.is_empty() || resp.email.is_empty() {
        return Err(CoreError::new("server", "Google sign-in response is missing token, user_id, device_id or email"));
    }
    {
        let _g = auth_lock.lock().unwrap_or_else(|p| p.into_inner());
        let session = SessionFile {
            token: resp.token.clone(),
            user_id: resp.user_id.clone(),
            device_id: resp.device_id.clone(),
            auth_method: Some("google".to_string()),
            email: Some(resp.email.clone()),
        };
        crate::auth::save_session(store, &session, previous_user.as_deref())?;
    }
    Ok(json!({
        "user_id": resp.user_id,
        "device_id": resp.device_id,
        "device_public_key_b64": public_b64,
        "fingerprint": fingerprint(&public),
        "email": resp.email,
        "auth_method": "google",
    }))
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
