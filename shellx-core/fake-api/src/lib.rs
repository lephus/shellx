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
//! `POST|GET /v2/machines`, `POST /v2/machines/<id>/heartbeat`, `POST /v2/relay/tickets`,
//! `POST|GET /v2/pairings`, `POST /v2/pairings/<id>/approve|deny`.
//!
//! Machines: registering again with the same (user, key) updates the same machine.
//! `online` = heartbeat within 90 s. Tickets follow the ledger "Ticket format"
//! (cmux-relay v2) and are signed with `FakeOptions::hmac_secret`; `connect` is
//! allowed for the caller's own machine (D3) or a granted target, else 403
//! `not_granted`.
//!
//! Pairings follow the L4 rules (w2-server plan Task 4): `from_machine_id` must be
//! the caller's own machine (the one registered by its device), code = 6 random
//! digits unique among the target's live pending requests, `requester_fingerprint`
//! copied from the requester machine row, pending expires after 300 s (reported
//! lazily as `expired`), a new (from, to) request supersedes the old pending one,
//! items of both roles carry `requester_x25519_b64` (standard base64, D2/R13), a
//! request whose key is not the requester machine's registered one is 400 (D1/R17),
//! `sealed_invite_b64` is returned verbatim to the requester only once approved,
//! approve is target-only, refuses plaintext `cmux://` and grants `connect`.

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
/// Pending pairings expire after 5 minutes (L4 `PAIRING_TTL_MS`).
pub const PAIRING_TTL_SECS: u64 = 300;
/// L4 `SEALED_INVITE_MAX_BYTES` (decoded).
const SEALED_INVITE_MAX_BYTES: usize = 8192;

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
    /// pairing_id → pairing
    pairings: HashMap<String, Pairing>,
    /// Creation counter (newest first ordering).
    pairing_seq: u64,
    /// Test hook: `GET /v2/pairings` returns every pairing of the account, ignoring `role`.
    list_all_pairings: bool,
}

#[derive(Clone)]
struct Pairing {
    user_id: String,
    from_machine_id: String,
    to_machine_id: String,
    /// Raw 32 bytes; `None` after `drop_requester_key` (a server without D2).
    requester_x25519: Option<Vec<u8>>,
    requester_fingerprint: String,
    code: String,
    status: String,
    sealed_invite: Option<String>,
    created_at: u64,
    seq: u64,
}

impl Pairing {
    /// Stored status with lazy expiry of an old pending request.
    fn current_status(&self, now: u64) -> &str {
        if self.status == "pending" && now.saturating_sub(self.created_at) > PAIRING_TTL_SECS {
            "expired"
        } else {
            &self.status
        }
    }
}

#[derive(Debug, Clone)]
struct Machine {
    user_id: String,
    /// The device that registered it ("own machine" of that device's token).
    device_id: String,
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

    /// Overwrite the stored `requester_fingerprint` of a pairing. Test hook (a
    /// server lying about who is asking).
    pub fn tamper_requester_fingerprint(&self, pairing_id: &str, fingerprint: &str) {
        if let Some(p) = self.shared.lock().pairings.get_mut(pairing_id) {
            p.requester_fingerprint = fingerprint.to_string();
        }
    }

    /// Replace a pairing's requester key and keep `requester_fingerprint`
    /// consistent with it (a server swapping in an attacker key). Test hook.
    pub fn swap_requester_key(&self, pairing_id: &str, public: [u8; 32]) {
        if let Some(p) = self.shared.lock().pairings.get_mut(pairing_id) {
            p.requester_fingerprint = key_fingerprint(&URL_SAFE_NO_PAD.encode(public));
            p.requester_x25519 = Some(public.to_vec());
        }
    }

    /// Forget a pairing's requester key, so `role=target` items lack
    /// `requester_x25519_b64` (a server without D2). Test hook.
    pub fn drop_requester_key(&self, pairing_id: &str) {
        if let Some(p) = self.shared.lock().pairings.get_mut(pairing_id) {
            p.requester_x25519 = None;
        }
    }

    /// Move the sealed invite of `from_id` onto `to_id` and mark `to_id` approved
    /// (a server replaying ciphertext on another pairing). Test hook.
    pub fn move_sealed_invite(&self, from_id: &str, to_id: &str) {
        let mut st = self.shared.lock();
        let sealed = st.pairings.get_mut(from_id).and_then(|p| p.sealed_invite.take());
        if let Some(p) = st.pairings.get_mut(to_id) {
            p.sealed_invite = sealed;
            p.status = "approved".to_string();
        }
    }

    /// Age a pairing past its 5-minute expiry. Test hook.
    pub fn expire(&self, pairing_id: &str) {
        if let Some(p) = self.shared.lock().pairings.get_mut(pairing_id) {
            p.created_at = p.created_at.saturating_sub(PAIRING_TTL_SECS + 1);
        }
    }

    /// The sealed invite text the server stores for a pairing (empty if none). Test helper.
    pub fn stored_sealed(&self, pairing_id: &str) -> String {
        self.shared.lock().pairings.get(pairing_id).and_then(|p| p.sealed_invite.clone()).unwrap_or_default()
    }

    /// Whether `from_machine` may mint connect tickets for `target_machine`. Test helper.
    pub fn has_grant(&self, from_machine: &str, target_machine: &str) -> bool {
        self.shared.lock().grants.contains(&(from_machine.to_string(), target_machine.to_string()))
    }

    /// Make `GET /v2/pairings` return every pairing of the account whatever the
    /// role (a misbehaving server). Test hook.
    pub fn set_list_all_pairings(&self, on: bool) {
        self.shared.lock().list_all_pairings = on;
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
        ("POST", "/v2/pairings") => create_pairing(rec, st),
        ("GET", "/v2/pairings") => list_pairings(rec, st),
        ("POST", p) if p.starts_with("/v2/pairings/") && p.ends_with("/approve") => {
            let id = &p["/v2/pairings/".len()..p.len() - "/approve".len()];
            approve_pairing(rec, id, st)
        }
        ("POST", p) if p.starts_with("/v2/pairings/") && p.ends_with("/deny") => {
            let id = &p["/v2/pairings/".len()..p.len() - "/deny".len()];
            deny_pairing(rec, id, st)
        }
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
            device_id: who.device_id,
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

/// Standard or URL alphabet, padded or not (K1 `*_b64` inputs).
fn decode_any_b64(s: &str) -> Option<Vec<u8>> {
    use base64::engine::general_purpose::{STANDARD, STANDARD_NO_PAD, URL_SAFE};
    [&URL_SAFE_NO_PAD, &URL_SAFE, &STANDARD, &STANDARD_NO_PAD].iter().find_map(|e| e.decode(s).ok())
}

/// The caller's own machine id (registered by the caller's device).
fn own_machine_id(who: &TokenInfo, st: &State) -> Option<String> {
    st.machines
        .iter()
        .find(|(_, m)| m.user_id == who.user_id && m.device_id == who.device_id)
        .map(|(id, _)| id.clone())
}

fn random_code() -> String {
    let mut b = [0u8; 4];
    getrandom::fill(&mut b).expect("random source");
    format!("{:06}", u32::from_le_bytes(b) % 1_000_000)
}

fn create_pairing(rec: &Recorded, st: &mut State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let b = &rec.body;
    let (Some(from), Some(to)) = (b["from_machine_id"].as_str(), b["to_machine_id"].as_str()) else {
        return Reply::error(400, "bad_request", "from_machine_id and to_machine_id are required");
    };
    match st.machines.get(from) {
        Some(m) if m.user_id == who.user_id && m.device_id == who.device_id => {}
        Some(m) if m.user_id == who.user_id => return Reply::error(403, "forbidden", "Not your machine"),
        _ => return Reply::error(404, "machine_not_found", "Machine not found"),
    }
    if !st.machines.get(to).is_some_and(|m| m.user_id == who.user_id) {
        return Reply::error(404, "machine_not_found", "Machine not found");
    }
    if from == to {
        return Reply::error(400, "bad_request", "A machine cannot pair with itself");
    }
    let Some(key) = b["requester_x25519_b64"].as_str().and_then(decode_any_b64).filter(|k| k.len() == 32) else {
        return Reply::error(400, "bad_request", "requester_x25519_b64 must be a 32-byte key");
    };
    // D1, enforced as the real server does (relay/src/v2/pairings.ts:103): the
    // key must be the requester machine's registered one.
    if URL_SAFE_NO_PAD.decode(&st.machines[from].noise_public_key_b64).ok().as_deref() != Some(key.as_slice()) {
        return Reply::error(400, "bad_request", "Malformed request body");
    }
    let now = now_unix();
    // Supersede an older pending request with the same (from, to).
    for p in st.pairings.values_mut() {
        if p.from_machine_id == from && p.to_machine_id == to && p.current_status(now) == "pending" {
            p.status = "expired".to_string();
        }
    }
    let live_codes: HashSet<String> = st
        .pairings
        .values()
        .filter(|p| p.to_machine_id == to && p.current_status(now) == "pending")
        .map(|p| p.code.clone())
        .collect();
    let Some(code) = (0..10).map(|_| random_code()).find(|c| !live_codes.contains(c)) else {
        return Reply::error(500, "internal", "Could not draw a pairing code");
    };
    let fingerprint = key_fingerprint(&st.machines[from].noise_public_key_b64);
    let id = random_id();
    st.pairing_seq += 1;
    let seq = st.pairing_seq;
    st.pairings.insert(
        id.clone(),
        Pairing {
            user_id: who.user_id,
            from_machine_id: from.to_string(),
            to_machine_id: to.to_string(),
            requester_x25519: Some(key),
            requester_fingerprint: fingerprint,
            code: code.clone(),
            status: "pending".to_string(),
            sealed_invite: None,
            created_at: now,
            seq,
        },
    );
    Reply::json(201, json!({"pairing_id": id, "code": code}))
}

fn list_pairings(rec: &Recorded, st: &State) -> Reply {
    use base64::engine::general_purpose::STANDARD;
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let role = match rec.query.split('&').find_map(|kv| kv.strip_prefix("role=")) {
        Some(r @ ("target" | "requester")) => r,
        _ => return Reply::error(400, "bad_request", "role must be target or requester"),
    };
    let Some(own) = own_machine_id(&who, st) else { return Reply::json(200, json!({"pairings": []})) };
    let now = now_unix();
    let mut items: Vec<(&String, &Pairing)> = st
        .pairings
        .iter()
        .filter(|(_, p)| p.user_id == who.user_id)
        .filter(|(_, p)| {
            st.list_all_pairings || if role == "target" { p.to_machine_id == own } else { p.from_machine_id == own }
        })
        .collect();
    items.sort_by(|a, b| b.1.seq.cmp(&a.1.seq));
    let pairings: Vec<Value> = items
        .into_iter()
        .map(|(id, p)| {
            let status = p.current_status(now);
            let mut v = json!({
                "pairing_id": id,
                "from_machine_id": p.from_machine_id,
                "to_machine_id": p.to_machine_id,
                "requester_fingerprint": p.requester_fingerprint,
                "code": p.code,
                "status": status,
            });
            if let Some(k) = &p.requester_x25519 {
                v["requester_x25519_b64"] = json!(STANDARD.encode(k));
            }
            if (role == "requester" || st.list_all_pairings)
                && status == "approved"
                && let Some(s) = &p.sealed_invite
            {
                v["sealed_invite_b64"] = json!(s);
            }
            v
        })
        .collect();
    Reply::json(200, json!({"pairings": pairings}))
}

/// The pairing `id` of the caller's account, or the L4 error reply.
fn account_pairing<'a>(who: &TokenInfo, id: &str, st: &'a State) -> Result<&'a Pairing, Reply> {
    st.pairings
        .get(id)
        .filter(|p| p.user_id == who.user_id)
        .ok_or_else(|| Reply::error(404, "pairing_not_found", "Pairing not found"))
}

fn approve_pairing(rec: &Recorded, id: &str, st: &mut State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let own = own_machine_id(&who, st);
    let p = match account_pairing(&who, id, st) {
        Ok(p) => p,
        Err(r) => return r,
    };
    if own.as_deref() != Some(p.to_machine_id.as_str()) {
        return Reply::error(403, "forbidden", "Only the target machine can approve");
    }
    let Some(sealed) = rec.body["sealed_invite_b64"].as_str() else {
        return Reply::error(400, "bad_request", "sealed_invite_b64 is required");
    };
    let Some(raw) = decode_any_b64(sealed).filter(|r| (1..=SEALED_INVITE_MAX_BYTES).contains(&r.len())) else {
        return Reply::error(400, "bad_request", "sealed_invite_b64 is not a valid sealed invite");
    };
    if raw.starts_with(b"cmux://") {
        return Reply::error(400, "plaintext_invite", "Invites must be sealed");
    }
    let now = now_unix();
    let status = p.current_status(now).to_string();
    if status != "pending" {
        return if p.status == "pending" {
            Reply::error(410, "pairing_expired", "Pairing expired")
        } else {
            Reply::error(409, "pairing_not_pending", "Pairing is not pending")
        };
    }
    let (from, to) = (p.from_machine_id.clone(), p.to_machine_id.clone());
    let p = st.pairings.get_mut(id).expect("checked above");
    p.status = "approved".to_string();
    p.sealed_invite = Some(sealed.to_string());
    st.grants.insert((from, to));
    Reply::empty(204)
}

fn deny_pairing(rec: &Recorded, id: &str, st: &mut State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let own = own_machine_id(&who, st);
    let p = match account_pairing(&who, id, st) {
        Ok(p) => p,
        Err(r) => return r,
    };
    // Target denies, requester cancels.
    if own.as_deref() != Some(p.to_machine_id.as_str()) && own.as_deref() != Some(p.from_machine_id.as_str()) {
        return Reply::error(403, "forbidden", "Not a party to this pairing");
    }
    let status = p.current_status(now_unix()).to_string();
    match status.as_str() {
        "pending" => {
            st.pairings.get_mut(id).expect("checked above").status = "denied".to_string();
            Reply::empty(204)
        }
        "denied" => Reply::empty(204),
        _ => Reply::error(409, "pairing_not_pending", "Pairing is not pending"),
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
