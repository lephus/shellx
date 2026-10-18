//! In-memory fake of the ShellX K1 API subset that shellx-core talks to.
//!
//! Test infrastructure only (shellx-core integration tests and the remote e2e
//! harness through the `shellx-fake-api` binary). One `tiny_http` thread, state
//! in a `Mutex`. Every request is recorded (header names lowercased).
//!
//! Accounts: any email logs in with `FakeOptions::password`; the same email always
//! maps to the same user, and the same (user, device public key) to the same
//! device (like v1 `/v1/auth/login`). One live token per device; tokens are random
//! 32-byte b64url strings.
//!
//! Routes so far: `POST /v1/auth/login`, `POST /v1/auth/logout`, `GET /v1/version`.

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde_json::{Value, json};
use std::collections::{BTreeMap, HashMap};
use std::io::Read;
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread::JoinHandle;
use tiny_http::{Header, Request, Response, Server};

/// Device kinds `/v1/auth/login` accepts (v1 kinds + `desktop`, K1).
const DEVICE_KINDS: &[&str] = &["agent", "mobile", "desktop"];
const DEVICE_PLATFORMS: &[&str] = &["macos", "windows", "ios", "android"];
const MAX_BODY_BYTES: u64 = 64 * 1024;

#[derive(Debug, Clone)]
pub struct FakeOptions {
    pub password: String,
    /// HMAC key for relay tickets (later tasks). Never logged.
    pub hmac_secret: Vec<u8>,
    pub issuer: String,
    pub ticket_ttl_secs: u64,
    pub relay_url: String,
    /// Body served by `GET /v1/version`.
    pub version_body: Value,
}

impl FakeOptions {
    /// A `/v1/version` body shaped like the live server's.
    pub fn default_version_body() -> Value {
        json!({
            "min_agent": "2.0.0",
            "min_mobile": "1.0.0",
            "latest_agent": {
                "version": "2.0.0",
                "mac_url": "https://shellx.pro/download/ShellX.dmg",
                "win_url": "https://shellx.pro/download/ShellX-Setup.exe",
            },
        })
    }
}

impl Default for FakeOptions {
    fn default() -> Self {
        FakeOptions {
            password: "pw".to_string(),
            hmac_secret: b"shellx-fake-api-test-hmac-secret-32b".to_vec(),
            issuer: "shellx-relay".to_string(),
            ticket_ttl_secs: 120,
            relay_url: "ws://127.0.0.1:9/v2/relay".to_string(),
            version_body: FakeOptions::default_version_body(),
        }
    }
}

/// One request as the fake saw it.
#[derive(Debug, Clone)]
pub struct Recorded {
    pub method: String,
    /// URL path without the query string.
    pub path: String,
    /// Query string without `?` (empty when absent).
    pub query: String,
    /// Header names are lowercased.
    pub headers: BTreeMap<String, String>,
    /// JSON body, `Value::Null` when empty or not JSON.
    pub body: Value,
}

#[derive(Debug, Clone)]
struct TokenInfo {
    user_id: String,
    device_id: String,
}

#[derive(Default)]
struct State {
    requests: Vec<Recorded>,
    /// email → user_id
    users: HashMap<String, String>,
    /// (user_id, public key b64url) → device_id
    devices: HashMap<(String, String), String>,
    /// token → owner
    tokens: HashMap<String, TokenInfo>,
    last_token: Option<String>,
}

struct Shared {
    opts: FakeOptions,
    state: Mutex<State>,
}

impl Shared {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|p| p.into_inner())
    }
}

pub struct FakeApi {
    pub base_url: String,
    shared: Arc<Shared>,
    server: Arc<Server>,
    thread: Option<JoinHandle<()>>,
}

impl FakeApi {
    /// Bind `127.0.0.1:0` and serve on one thread.
    pub fn start(opts: FakeOptions) -> FakeApi {
        FakeApi::bind("127.0.0.1:0", opts).expect("bind fake api")
    }

    /// Bind `addr` (e.g. `127.0.0.1:8787`) and serve on one thread.
    pub fn bind(addr: &str, opts: FakeOptions) -> Result<FakeApi, String> {
        let server = Server::http(addr).map_err(|e| format!("bind {addr}: {e}"))?;
        let port = server
            .server_addr()
            .to_ip()
            .ok_or_else(|| "not an IP listener".to_string())?
            .port();
        let server = Arc::new(server);
        let shared = Arc::new(Shared { opts, state: Mutex::new(State::default()) });
        let (s, sh) = (server.clone(), shared.clone());
        let thread = std::thread::Builder::new()
            .name("shellx-fake-api".into())
            .spawn(move || serve(&s, &sh))
            .map_err(|e| format!("spawn: {e}"))?;
        Ok(FakeApi { base_url: format!("http://127.0.0.1:{port}"), shared, server, thread: Some(thread) })
    }

    /// Every request so far, oldest first.
    pub fn requests(&self) -> Vec<Recorded> {
        self.shared.lock().requests.clone()
    }

    /// The most recently issued login token (empty if none yet). Test helper.
    pub fn issued_token(&self) -> String {
        self.shared.lock().last_token.clone().unwrap_or_default()
    }

    /// Whether `token` is currently accepted. Test helper.
    pub fn token_is_live(&self, token: &str) -> bool {
        self.shared.lock().tokens.contains_key(token)
    }

    /// `(user_id, device_id)` that `token` belongs to, if live. Test helper.
    pub fn token_owner(&self, token: &str) -> Option<(String, String)> {
        self.shared.lock().tokens.get(token).map(|t| (t.user_id.clone(), t.device_id.clone()))
    }

    /// Stop serving and close the listener.
    pub fn stop(mut self) {
        self.shutdown();
    }

    /// Block until the server thread ends (binary use).
    pub fn wait(mut self) {
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }

    fn shutdown(&mut self) {
        self.server.unblock();
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}

impl Drop for FakeApi {
    fn drop(&mut self) {
        self.shutdown();
    }
}

fn serve(server: &Server, shared: &Shared) {
    // `recv` returns Err after `unblock`; that ends the thread.
    while let Ok(req) = server.recv() {
        handle(req, shared);
    }
}

fn random_b64url(n: usize) -> String {
    let mut b = vec![0u8; n];
    getrandom::fill(&mut b).expect("random source");
    URL_SAFE_NO_PAD.encode(b)
}

fn random_id() -> String {
    let mut b = [0u8; 16];
    getrandom::fill(&mut b).expect("random source");
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    let h: String = b.iter().map(|x| format!("{x:02x}")).collect();
    format!("{}-{}-{}-{}-{}", &h[0..8], &h[8..12], &h[12..16], &h[16..20], &h[20..32])
}

struct Reply {
    status: u16,
    body: Option<Value>,
}

impl Reply {
    fn json(status: u16, body: Value) -> Reply {
        Reply { status, body: Some(body) }
    }
    fn empty(status: u16) -> Reply {
        Reply { status, body: None }
    }
    fn error(status: u16, code: &str, message: &str) -> Reply {
        Reply::json(status, json!({"error": {"code": code, "message": message}}))
    }
}

fn handle(mut req: Request, shared: &Shared) {
    let method = req.method().as_str().to_ascii_uppercase();
    let url = req.url().to_string();
    let (path, query) = match url.split_once('?') {
        Some((p, q)) => (p.to_string(), q.to_string()),
        None => (url.clone(), String::new()),
    };
    let headers: BTreeMap<String, String> = req
        .headers()
        .iter()
        .map(|h| (h.field.as_str().as_str().to_ascii_lowercase(), h.value.as_str().to_string()))
        .collect();
    let mut raw = Vec::new();
    let _ = req.as_reader().take(MAX_BODY_BYTES).read_to_end(&mut raw);
    let body: Value = serde_json::from_slice(&raw).unwrap_or(Value::Null);
    let rec = Recorded { method, path, query, headers, body };

    let reply = {
        let mut st = shared.lock();
        st.requests.push(rec.clone());
        route(&rec, &raw, &shared.opts, &mut st)
    };

    let content_type = Header::from_bytes("Content-Type", "application/json").expect("static header");
    let resp = match reply.body {
        Some(v) => Response::from_string(v.to_string()).with_status_code(reply.status).with_header(content_type),
        None => Response::from_string(String::new()).with_status_code(reply.status),
    };
    let _ = req.respond(resp);
}

fn bearer(rec: &Recorded) -> Option<&str> {
    rec.headers.get("authorization")?.strip_prefix("Bearer ")
}

fn route(rec: &Recorded, raw: &[u8], opts: &FakeOptions, st: &mut State) -> Reply {
    match (rec.method.as_str(), rec.path.as_str()) {
        ("GET", "/v1/version") => Reply::json(200, opts.version_body.clone()),
        ("POST", "/v1/auth/login") => login(rec, raw, opts, st),
        ("POST", "/v1/auth/logout") => match bearer(rec) {
            Some(t) if st.tokens.contains_key(t) => {
                let t = t.to_string();
                st.tokens.remove(&t);
                Reply::empty(204)
            }
            _ => Reply::error(401, "unauthorized", "Missing, invalid or expired token"),
        },
        _ => Reply::error(404, "not_found", "Not found"),
    }
}

/// `{kind, name, platform, public_key}` per v1 `parseDevice` (+ kind `desktop`).
fn device_ok(d: &Value) -> bool {
    let kind_ok = d["kind"].as_str().is_some_and(|k| DEVICE_KINDS.contains(&k));
    let platform_ok = d["platform"].as_str().is_some_and(|p| DEVICE_PLATFORMS.contains(&p));
    let name_ok = d["name"].as_str().is_some_and(|n| (1..=100).contains(&n.trim().chars().count()));
    let key_ok = d["public_key"]
        .as_str()
        .and_then(|k| URL_SAFE_NO_PAD.decode(k).ok())
        .is_some_and(|k| k.len() == 32);
    kind_ok && platform_ok && name_ok && key_ok
}

fn login(rec: &Recorded, raw: &[u8], opts: &FakeOptions, st: &mut State) -> Reply {
    if !rec.body.is_object() || raw.is_empty() {
        return Reply::error(400, "bad_request", "Malformed request body");
    }
    let b = &rec.body;
    if !device_ok(&b["device"]) {
        return Reply::error(400, "invalid_device", "Device information is not valid");
    }
    let email = b["email"].as_str().unwrap_or("").trim().to_lowercase();
    if email.is_empty() || b["password"].as_str() != Some(opts.password.as_str()) {
        return Reply::error(401, "invalid_credentials", "Email or password is incorrect");
    }
    let user_id = st.users.entry(email).or_insert_with(random_id).clone();
    let key = b["device"]["public_key"].as_str().unwrap_or_default().to_string();
    let device_id = st.devices.entry((user_id.clone(), key)).or_insert_with(random_id).clone();
    // One live token per device.
    st.tokens.retain(|_, t| t.device_id != device_id);
    let token = random_b64url(32);
    st.tokens.insert(token.clone(), TokenInfo { user_id: user_id.clone(), device_id: device_id.clone() });
    st.last_token = Some(token.clone());
    Reply::json(200, json!({"user_id": user_id, "device_id": device_id, "token": token}))
}
