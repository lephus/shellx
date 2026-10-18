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
//! Routes so far: `POST /v1/auth/login`, `POST /v1/auth/logout`, `GET /v1/version`,
//! `POST|GET /v2/machines`, `POST /v2/machines/<id>/heartbeat`, `POST /v2/relay/tickets`.
//!
//! Machines: registering again with the same (user, key) updates the same machine.
//! `online` = heartbeat within 90 s. Tickets follow the ledger "Ticket format"
//! (cmux-relay v2) and are signed with `FakeOptions::hmac_secret`; `connect` is
//! allowed for the caller's own machine (D3) or a granted target, else 403
//! `not_granted`.

use base64::Engine;
use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde_json::{Value, json};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::io::Read;
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread::JoinHandle;
use tiny_http::{Header, Request, Response, Server};

/// Device kinds `/v1/auth/login` accepts (v1 kinds + `desktop`, K1).
const DEVICE_KINDS: &[&str] = &["agent", "mobile", "desktop"];
const DEVICE_PLATFORMS: &[&str] = &["macos", "windows", "ios", "android"];
const MAX_BODY_BYTES: u64 = 64 * 1024;

#[derive(Clone)]
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

/// Redacts the password and the HMAC secret.
impl std::fmt::Debug for FakeOptions {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("FakeOptions")
            .field("password", &"<redacted>")
            .field("hmac_secret", &format_args!("<{} bytes redacted>", self.hmac_secret.len()))
            .field("issuer", &self.issuer)
            .field("ticket_ttl_secs", &self.ticket_ttl_secs)
            .field("relay_url", &self.relay_url)
            .field("version_body", &self.version_body)
            .finish()
    }
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
    /// machine_id → machine
    machines: HashMap<String, Machine>,
    /// (from machine, target machine) pairs allowed to mint connect tickets.
    grants: HashSet<(String, String)>,
}

#[derive(Debug, Clone)]
struct Machine {
    user_id: String,
    name: String,
    platform: String,
    os_version: String,
    app_version: String,
    noise_public_key_b64: String,
    slot: String,
    last_heartbeat: Option<u64>,
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

    /// Forget `token` (the server no longer accepts it). Test helper.
    pub fn revoke_token(&self, token: &str) {
        self.shared.lock().tokens.remove(token);
    }

    /// Overwrite a machine's last heartbeat (unix seconds). Test hook.
    pub fn set_last_heartbeat(&self, machine_id: &str, unix: u64) {
        if let Some(m) = self.shared.lock().machines.get_mut(machine_id) {
            m.last_heartbeat = Some(unix);
        }
    }

    /// Allow `from_machine` to mint connect tickets for `target_machine` (what an
    /// approved pairing will do). Test hook; empty by default.
    pub fn grant_connect(&self, from_machine: &str, target_machine: &str) {
        self.shared.lock().grants.insert((from_machine.to_string(), target_machine.to_string()));
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
        ("POST", "/v2/machines") => register_machine(rec, raw, st),
        ("GET", "/v2/machines") => list_machines(rec, st),
        ("POST", "/v2/relay/tickets") => mint_ticket(rec, opts, st),
        ("POST", p) if p.starts_with("/v2/machines/") && p.ends_with("/heartbeat") => {
            let id = &p["/v2/machines/".len()..p.len() - "/heartbeat".len()];
            heartbeat(rec, id, st)
        }
        _ => Reply::error(404, "not_found", "Not found"),
    }
}

const ONLINE_WINDOW_SECS: u64 = 90;

fn now_unix() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// The user id behind the request's bearer token.
fn caller(rec: &Recorded, st: &State) -> Option<TokenInfo> {
    st.tokens.get(bearer(rec)?).cloned()
}

fn unauthorized() -> Reply {
    Reply::error(401, "unauthorized", "Missing, invalid or expired token")
}

/// First 16 hex of SHA-256 over the raw key (D1), as the real server reports it.
fn key_fingerprint(key_b64: &str) -> String {
    let raw = URL_SAFE_NO_PAD.decode(key_b64).unwrap_or_default();
    Sha256::digest(raw)[..8].iter().map(|b| format!("{b:02x}")).collect()
}

fn register_machine(rec: &Recorded, raw: &[u8], st: &mut State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    if !rec.body.is_object() || raw.is_empty() {
        return Reply::error(400, "bad_request", "Malformed request body");
    }
    let b = &rec.body;
    let text = |k: &str, max: usize| b[k].as_str().map(str::trim).filter(|v| (1..=max).contains(&v.chars().count()));
    let key = b["noise_public_key_b64"].as_str().filter(|k| URL_SAFE_NO_PAD.decode(k).is_ok_and(|r| r.len() == 32));
    let platform = b["platform"].as_str().filter(|p| DEVICE_PLATFORMS.contains(p));
    let (Some(name), Some(platform), Some(os), Some(app), Some(key)) =
        (text("name", 100), platform, text("os_version", 100), text("app_version", 100), key)
    else {
        return Reply::error(400, "invalid_machine", "Machine information is not valid");
    };
    let existing = st
        .machines
        .iter()
        .find(|(_, m)| m.user_id == who.user_id && m.noise_public_key_b64 == key)
        .map(|(id, _)| id.clone());
    let id = existing.unwrap_or_else(random_id);
    let slot = st.machines.get(&id).map(|m| m.slot.clone()).unwrap_or_else(|| random_b64url(16));
    let last = st.machines.get(&id).and_then(|m| m.last_heartbeat);
    st.machines.insert(
        id.clone(),
        Machine {
            user_id: who.user_id,
            name: name.to_string(),
            platform: platform.to_string(),
            os_version: os.to_string(),
            app_version: app.to_string(),
            noise_public_key_b64: key.to_string(),
            slot: slot.clone(),
            last_heartbeat: last,
        },
    );
    Reply::json(200, json!({"machine_id": id, "slot": slot}))
}

fn list_machines(rec: &Recorded, st: &State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let now = now_unix();
    let mut items: Vec<(&String, &Machine)> = st.machines.iter().filter(|(_, m)| m.user_id == who.user_id).collect();
    items.sort_by(|a, b| a.1.name.cmp(&b.1.name).then(a.0.cmp(b.0)));
    let machines: Vec<Value> = items
        .into_iter()
        .map(|(id, m)| {
            json!({
                "machine_id": id,
                "name": m.name,
                "platform": m.platform,
                "os_version": m.os_version,
                "app_version": m.app_version,
                "online": m.last_heartbeat.is_some_and(|t| now.saturating_sub(t) <= ONLINE_WINDOW_SECS),
                "last_seen_unix": m.last_heartbeat,
                "noise_public_key_b64": m.noise_public_key_b64,
                "fingerprint": key_fingerprint(&m.noise_public_key_b64),
            })
        })
        .collect();
    Reply::json(200, json!({"machines": machines}))
}

fn heartbeat(rec: &Recorded, id: &str, st: &mut State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    match st.machines.get_mut(id) {
        Some(m) if m.user_id == who.user_id => {
            m.last_heartbeat = Some(now_unix());
            Reply::json(200, json!({}))
        }
        _ => Reply::error(404, "machine_not_found", "Machine not found"),
    }
}

fn mint_ticket(rec: &Recorded, opts: &FakeOptions, st: &mut State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let b = &rec.body;
    let Some(machine_id) = b["machine_id"].as_str() else {
        return Reply::error(400, "bad_request", "machine_id is required");
    };
    let Some(own) = st.machines.get(machine_id).filter(|m| m.user_id == who.user_id) else {
        return Reply::error(404, "machine_not_found", "Machine not found");
    };
    let target = b["target_machine_id"].as_str();
    let (permission, role, slot) = match b["permission"].as_str() {
        Some("register") => {
            // Only ever for the caller's own machine.
            if target.is_some_and(|t| t != machine_id) {
                return Reply::error(400, "bad_request", "register tickets are for the caller's own machine");
            }
            ("register", "daemon", own.slot.clone())
        }
        Some("connect") => {
            let Some(target) = target else {
                return Reply::error(400, "bad_request", "target_machine_id is required for connect");
            };
            let Some(t) = st.machines.get(target) else {
                return Reply::error(404, "machine_not_found", "Machine not found");
            };
            // D3: the caller's own machine needs no grant.
            if target != machine_id && !st.grants.contains(&(machine_id.to_string(), target.to_string())) {
                return Reply::error(403, "not_granted", "No approved pairing for that machine");
            }
            ("connect", "client", t.slot.clone())
        }
        _ => return Reply::error(400, "bad_request", "permission must be register or connect"),
    };
    let iat = now_unix();
    let exp = iat + opts.ticket_ttl_secs;
    let claims = json!({
        "version": 2, "issuer": opts.issuer, "permission": permission, "role": role, "slot": slot,
        "circuit": null, "lane": null, "generation": null,
        "issued_at_unix": iat, "expires_at_unix": exp,
    });
    let payload = format!(
        "cmux-relay-ticket-v2\n2\n{}\n{permission}\n{role}\n{slot}\n\n\n\n{iat}\n{exp}",
        opts.issuer
    );
    let mut mac = Hmac::<Sha256>::new_from_slice(&opts.hmac_secret).expect("hmac accepts any key length");
    mac.update(payload.as_bytes());
    let ticket = format!(
        "v2.{}.{}",
        URL_SAFE_NO_PAD.encode(claims.to_string()),
        URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes())
    );
    Reply::json(200, json!({"ticket": ticket, "expires_at_unix": exp, "relay_url": opts.relay_url}))
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn options_debug_redacts_password_and_secret() {
        let o = FakeOptions { password: "hunter2-PW".into(), hmac_secret: b"HMAC-SECRET-VALUE-0123456789abcdef".to_vec(), ..FakeOptions::default() };
        let d = format!("{o:?}");
        assert!(!d.contains("hunter2-PW") && !d.contains("HMAC-SECRET-VALUE"));
    }
}
