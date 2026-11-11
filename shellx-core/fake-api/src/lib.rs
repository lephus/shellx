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
//! Google sign-in (plan 1B): `POST /v1/auth/nonce`, `POST /v1/auth/google`, `POST /v1/auth/google/link`,
//! `GET /v1/account/identities`, `DELETE /v1/account/identities/<id>`, `DELETE /v1/account`, and a fake
//! Google (`GET /fake-google/auth`, `POST /fake-google/token`) that checks PKCE. Nonces and id_tokens are single use.
//!
//! Routes so far: `POST /v1/auth/login`, `POST /v1/auth/logout`, `GET /v1/version`,
//! `POST|GET /v2/machines`, `POST /v2/machines/<id>/heartbeat`, `POST /v2/relay/tickets`,
//! `POST|GET /v2/pairings`, `POST /v2/pairings/<id>/approve|deny`, and the desktop side of
//! ShellX Link phone pairing: `GET /v2/phone-pairings?role=target`,
//! `POST /v2/phone-pairings/<id>/approve|deny`, `GET /v2/phone-grants`, `DELETE /v2/phone-grants/<id>`.
//! Phone requests are created with `FakeApi::add_phone_pairing` (no phone-side routes here).
//!
//! Machines: registering again with the same (user, key) updates the same machine.
//! `online` = heartbeat within 90 s. Tickets follow the ledger "Ticket format"
//! (cmux-relay v2) and are signed with `FakeOptions::hmac_secret`; `connect` is
//! allowed for the caller's own machine (D3) or a granted target, else 403
//! `not_granted`.
//!
//! Email code sign-in (desktop plan A): `POST /v1/auth/email/code` and `POST /v1/auth/email/verify`, answered in the
//! relay's order and with its rules (`relay/src/routes/email-sign-in.ts`): one live code per address, five guesses, 600 s,
//! the relay's address check, a 409 that spends the code, a failed mail that drops the live code. There is no mail: the
//! code is read with `FakeApi::email_code`. Hooks: `set_next_email_code`, `expire_email_codes`, `fail_next_mail`,
//! `fail_next` (a scripted answer for one path that changes no state), `add_user`. `FakeOptions::email_sign_in = false`
//! is a relay without Resend (503) and `FakeOptions::email_routes = false` a relay from before the feature (404).
//! Rate limits are not counted.
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
/// A mailed code lives ten minutes (`EMAIL_CODE_TTL_MS` of the relay).
pub const EMAIL_CODE_TTL_SECS: u64 = 600;
/// `resend_in` of the 202: advice for the client's Resend button.
pub const EMAIL_RESEND_SECS: u64 = 60;
/// Guesses a challenge takes; the fifth wrong one kills it.
pub const EMAIL_CODE_MAX_ATTEMPTS: u32 = 5;
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
    /// Client id/secret the fake Google accepts.
    pub google_client_id: String,
    pub google_client_secret: String,
    /// The account the fake Google signs in (changeable with `set_google_account`).
    pub google_email: String,
    pub google_subject: String,
    /// false: `POST /v1/auth/email/code` answers 503 `email_sign_in_disabled` before reading the body (a relay
    /// without Resend). Fixed for the fake's life.
    pub email_sign_in: bool,
    /// false: neither email route exists; both answer 404 `not_found` (a relay from before the feature).
    pub email_routes: bool,
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
            .field("google_client_id", &self.google_client_id)
            .field("google_client_secret", &"<redacted>")
            .field("email_sign_in", &self.email_sign_in)
            .field("email_routes", &self.email_routes)
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
            google_client_id: "fake-desktop-client".to_string(),
            google_client_secret: "fake-desktop-secret".to_string(),
            google_email: "google-user@shellx.test".to_string(),
            google_subject: "fake-google-sub-1".to_string(),
            email_sign_in: true,
            email_routes: true,
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
    /// Decoded `application/x-www-form-urlencoded` body, else empty.
    pub form: BTreeMap<String, String>,
}

#[derive(Debug, Clone)]
struct TokenInfo {
    user_id: String,
    device_id: String,
    /// "password" | "google" | "email"
    auth_method: String,
    /// The sign-in (identity) this token came through: Google or email; None for a password login.
    /// Removing the identity revokes the token.
    identity_id: Option<String>,
}

#[derive(Clone)]
struct Identity {
    id: String,
    user_id: String,
    provider: String,
    subject: String,
    email: String,
    is_private_email: bool,
    linked_via_device_name: Option<String>,
    created_at: u64,
    seq: u64,
}

/// One pending email code (the relay's `email_codes` row).
struct EmailChallenge {
    email: String,
    code: String,
    /// "vi" or "en".
    locale: String,
    attempts: u32,
    expires_at: u64,
}

struct GoogleCode {
    challenge: String,
    redirect_uri: String,
    nonce: String,
    email: String,
    subject: String,
    used: bool,
}

struct IdToken {
    email: String,
    subject: String,
    nonce: String,
    used: bool,
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
    /// id → owner share (K1 owner routes of `/v2/shares`).
    shares: HashMap<String, Share>,
    /// Test hook: `GET /v2/pairings` returns every pairing of the account, ignoring `role`.
    list_all_pairings: bool,
    /// id → phone pairing request (`/v2/phone-pairings`, desktop side).
    phone_pairings: HashMap<String, PhonePairing>,
    /// id → phone grant (`/v2/phone-grants`).
    phone_grants: HashMap<String, PhoneGrant>,
    /// Creation counter for phone rows (oldest first ordering).
    phone_seq: u64,
    /// Users that signed in with a password (`/v1/auth/login`).
    password_users: HashSet<String>,
    /// Every nonce issued, oldest first; `spent_nonces` holds the used ones.
    nonces: Vec<String>,
    spent_nonces: HashSet<String>,
    google_account: Option<(String, String)>,
    google_codes: HashMap<String, GoogleCode>,
    id_tokens: HashMap<String, IdToken>,
    identities: Vec<Identity>,
    identity_seq: u64,
    /// challenge_id → pending email code.
    email_challenges: HashMap<String, EmailChallenge>,
    /// `set_next_email_code`: used once by the next challenge stored.
    next_email_code: Option<String>,
    /// `fail_next_mail`: the next `/code` that reaches the mail fails.
    fail_next_mail: bool,
    /// path → scripted answers `(status, error code or empty)`, oldest first.
    scripted: HashMap<String, std::collections::VecDeque<(u16, String)>>,
}

#[derive(Clone)]
struct PhonePairing {
    links_apple_id: bool,
    user_id: String,
    device_id: String,
    device_name: String,
    platform: String,
    machine_id: String,
    client_key: Vec<u8>,
    proof_b64: String,
    status: String,
    created_at: u64,
    seq: u64,
}

impl PhonePairing {
    fn current_status(&self, now: u64) -> &str {
        if self.status == "pending" && now.saturating_sub(self.created_at) > PAIRING_TTL_SECS {
            "expired"
        } else {
            &self.status
        }
    }
}

#[derive(Clone)]
struct PhoneGrant {
    user_id: String,
    device_id: String,
    device_name: String,
    platform: String,
    machine_id: String,
    client_key: Vec<u8>,
    created_at: u64,
    seq: u64,
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
struct Share {
    device_id: String,
    slot: String,
    permission: String,
    lifetime: String,
    created_at: u64,
    expires_at: u64,
    revoked: bool,
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
    link_slot: String,
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

    /// Change the account the fake Google signs in. Test hook.
    pub fn set_google_account(&self, email: &str, subject: &str) {
        self.shared.lock().google_account = Some((email.to_string(), subject.to_string()));
    }

    /// Every nonce ever issued, oldest first. Test helper.
    pub fn issued_nonces(&self) -> Vec<String> {
        self.shared.lock().nonces.clone()
    }

    /// Add an identity to a user; returns its id. Test hook.
    pub fn add_identity(&self, user_id: &str, provider: &str, subject: &str, email: &str, is_private_email: bool, linked_via_device_name: Option<&str>) -> String {
        let mut st = self.shared.lock();
        add_identity(&mut st, user_id, provider, subject, email, is_private_email, linked_via_device_name)
    }

    /// The account email of a user. Test helper.
    pub fn user_email(&self, user_id: &str) -> Option<String> {
        self.shared.lock().users.iter().find(|(_, u)| u.as_str() == user_id).map(|(e, _)| e.clone())
    }

    /// Whether the user still exists. Test helper.
    pub fn user_exists(&self, user_id: &str) -> bool {
        self.shared.lock().users.values().any(|u| u == user_id)
    }

    /// The live code mailed to `email` (trimmed and lowercased first); None when the address has no live challenge.
    /// Test helper (there is no mailbox).
    pub fn email_code(&self, email: &str) -> Option<String> {
        let (key, now) = (email.trim().to_lowercase(), now_unix());
        self.shared.lock().email_challenges.values().find(|c| c.email == key && c.expires_at > now).map(|c| c.code.clone())
    }

    /// That mail's language: "vi" when the request's `locale` was exactly "vi", else "en". Test helper.
    pub fn email_locale(&self, email: &str) -> Option<String> {
        let (key, now) = (email.trim().to_lowercase(), now_unix());
        self.shared.lock().email_challenges.values().find(|c| c.email == key && c.expires_at > now).map(|c| c.locale.clone())
    }

    /// The next challenge stored uses `code` (six ASCII digits) instead of a random one; once. Test hook.
    pub fn set_next_email_code(&self, code: &str) {
        assert!(code.len() == 6 && code.bytes().all(|b| b.is_ascii_digit()), "set_next_email_code: six ASCII digits");
        self.shared.lock().next_email_code = Some(code.to_string());
    }

    /// Every live email challenge answers 410 from now on, no guess counted: expiry, and the stand-in for a relay
    /// restart or deploy. Test hook.
    pub fn expire_email_codes(&self) {
        for c in self.shared.lock().email_challenges.values_mut() {
            c.expires_at = 0;
        }
    }

    /// The next `/code` that reaches the mail fails as the relay's does: the address's older challenge is gone, the
    /// new one is discarded, the answer is 502 `email_send_failed`. Test hook.
    pub fn fail_next_mail(&self) {
        self.shared.lock().fail_next_mail = true;
    }

    /// The next request to `path` is answered `status` with `{"error":{"code": code}}`, or with no body when `code`
    /// is empty; the route does not run, so no challenge changes (the relay's 429s change none). Calls for one path
    /// queue up. Test hook.
    pub fn fail_next(&self, path: &str, status: u16, code: &str) {
        self.shared.lock().scripted.entry(path.to_string()).or_default().push_back((status, code.to_string()));
    }

    /// A user with this address, no password and no sign-in (an account whose address nobody verified); its id.
    /// An address that already has a user answers that user's id. Test hook.
    pub fn add_user(&self, email: &str) -> String {
        self.shared.lock().users.entry(email.trim().to_lowercase()).or_insert_with(random_id).clone()
    }

    /// `"password"`, `"google"` or `"email"` for a live token. Test helper.
    pub fn token_auth_method(&self, token: &str) -> Option<String> {
        self.shared.lock().tokens.get(token).map(|t| t.auth_method.clone())
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

    /// Overwrite a share's `created_at` and `expires_at` (unix seconds). Test hook (list
    /// ordering and expiry without waiting).
    pub fn set_share_times(&self, id: &str, created_at: u64, expires_at: u64) {
        if let Some(s) = self.shared.lock().shares.get_mut(id) {
            s.created_at = created_at;
            s.expires_at = expires_at;
        }
    }

    /// Overwrite a machine's stored `noise_public_key_b64` verbatim (e.g. padded
    /// standard base64 as the L4 server may hold it, or garbage). Test hook.
    pub fn set_machine_key_b64(&self, machine_id: &str, key_b64: &str) {
        if let Some(m) = self.shared.lock().machines.get_mut(machine_id) {
            m.noise_public_key_b64 = key_b64.to_string();
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

    /// A phone of the machine's account asks to pair with `machine_id`; returns the
    /// pairing id. Test hook (the phone side routes live in the real relay only).
    pub fn add_phone_pairing(&self, machine_id: &str, device_name: &str, platform: &str, client_key: [u8; 32]) -> String {
        self.add_phone_pairing_inner(machine_id, device_name, platform, client_key, false)
    }

    /// Like `add_phone_pairing` (platform ios) for a pairing that links an Apple ID. Test hook.
    pub fn add_apple_link_phone_pairing(&self, machine_id: &str, device_name: &str, client_key: [u8; 32]) -> String {
        self.add_phone_pairing_inner(machine_id, device_name, "ios", client_key, true)
    }

    fn add_phone_pairing_inner(&self, machine_id: &str, device_name: &str, platform: &str, client_key: [u8; 32], links_apple_id: bool) -> String {
        let mut st = self.shared.lock();
        let user_id = st.machines.get(machine_id).map(|m| m.user_id.clone()).expect("add_phone_pairing: unknown machine");
        st.phone_seq += 1;
        let seq = st.phone_seq;
        let id = random_id();
        let pairing = PhonePairing {
            links_apple_id,
            user_id,
            device_id: random_id(),
            device_name: device_name.to_string(),
            platform: platform.to_string(),
            machine_id: machine_id.to_string(),
            client_key: client_key.to_vec(),
            proof_b64: base64::engine::general_purpose::STANDARD.encode(Sha256::digest(client_key)),
            status: "pending".to_string(),
            created_at: now_unix(),
            seq,
        };
        st.phone_pairings.insert(id.clone(), pairing);
        id
    }

    /// Age a phone pairing past its 5-minute expiry. Test hook.
    pub fn expire_phone_pairing(&self, pairing_id: &str) {
        if let Some(p) = self.shared.lock().phone_pairings.get_mut(pairing_id) {
            p.created_at = p.created_at.saturating_sub(PAIRING_TTL_SECS + 1);
        }
    }

    /// Whether a phone with `client_key` holds a grant on `machine_id`. Test helper.
    pub fn has_phone_grant(&self, machine_id: &str, client_key: [u8; 32]) -> bool {
        self.shared
            .lock()
            .phone_grants
            .values()
            .any(|g| g.machine_id == machine_id && g.client_key == client_key)
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
    location: Option<String>,
}

impl Reply {
    fn json(status: u16, body: Value) -> Reply {
        Reply { status, body: Some(body), location: None }
    }
    fn empty(status: u16) -> Reply {
        Reply { status, body: None, location: None }
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
    let form = if headers.get("content-type").is_some_and(|c| c.starts_with("application/x-www-form-urlencoded")) {
        parse_form(&String::from_utf8_lossy(&raw)).into_iter().collect()
    } else {
        BTreeMap::new()
    };
    let rec = Recorded { method, path, query, headers, body, form };

    let reply = {
        let mut st = shared.lock();
        st.requests.push(rec.clone());
        route(&rec, &raw, &shared.opts, &mut st)
    };

    let content_type = Header::from_bytes("Content-Type", "application/json").expect("static header");
    let mut resp = match reply.body {
        Some(v) => Response::from_string(v.to_string()).with_status_code(reply.status).with_header(content_type),
        None => Response::from_string(String::new()).with_status_code(reply.status),
    };
    if let Some(loc) = reply.location {
        resp = resp.with_header(Header::from_bytes("Location", loc).expect("location header"));
    }
    let _ = req.respond(resp);
}

fn bearer(rec: &Recorded) -> Option<&str> {
    rec.headers.get("authorization")?.strip_prefix("Bearer ")
}

fn route(rec: &Recorded, raw: &[u8], opts: &FakeOptions, st: &mut State) -> Reply {
    if let Some(q) = st.scripted.get_mut(rec.path.as_str()) {
        if let Some((status, code)) = q.pop_front() {
            return if code.is_empty() { Reply::empty(status) } else { Reply::error(status, &code, "Scripted by the test") };
        }
    }
    match (rec.method.as_str(), rec.path.as_str()) {
        ("GET", "/v1/version") => Reply::json(200, opts.version_body.clone()),
        ("POST", "/v1/auth/login") => login(rec, raw, opts, st),
        ("POST", "/v1/auth/nonce") => issue_nonce(st),
        ("GET", "/fake-google/auth") => fake_google_auth(rec, opts, st),
        ("POST", "/fake-google/token") => fake_google_token(rec, opts, st),
        ("POST", "/v1/auth/google") => google_sign_in(rec, opts, st),
        ("POST", "/v1/auth/google/link") => google_link(rec, opts, st),
        ("POST", "/v1/auth/email/code") if opts.email_routes => email_code_request(rec, opts, st),
        ("POST", "/v1/auth/email/verify") if opts.email_routes => email_verify(rec, st),
        ("GET", "/v1/account/identities") => list_identities(rec, st),
        ("DELETE", p) if p.starts_with("/v1/account/identities/") => remove_identity(rec, &p["/v1/account/identities/".len()..], st),
        ("DELETE", "/v1/account") => delete_account(rec, st),
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
        ("POST", "/v2/shares") => create_share(rec, st),
        ("GET", "/v2/shares") => list_shares(rec, st),
        ("DELETE", p) if p.starts_with("/v2/shares/") => revoke_share(rec, &p["/v2/shares/".len()..], st),
        ("POST", p) if p.starts_with("/v2/shares/") && p.ends_with("/host-ticket") => {
            let id = &p["/v2/shares/".len()..p.len() - "/host-ticket".len()];
            share_host_ticket(rec, id, opts, st)
        }
        ("GET", "/v2/phone-pairings") => list_phone_pairings(rec, st),
        ("POST", p) if p.starts_with("/v2/phone-pairings/") && p.ends_with("/approve") => {
            let id = &p["/v2/phone-pairings/".len()..p.len() - "/approve".len()];
            approve_phone_pairing(rec, id, st)
        }
        ("POST", p) if p.starts_with("/v2/phone-pairings/") && p.ends_with("/deny") => {
            let id = &p["/v2/phone-pairings/".len()..p.len() - "/deny".len()];
            deny_phone_pairing(rec, id, st)
        }
        ("GET", "/v2/phone-grants") => list_phone_grants(rec, st),
        ("POST", "/v2/notifications") => notify_phones(rec, st),
        ("DELETE", p) if p.starts_with("/v2/phone-grants/") => delete_phone_grant(rec, &p["/v2/phone-grants/".len()..], st),
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
    let link_slot = st.machines.get(&id).map(|m| m.link_slot.clone()).unwrap_or_else(|| random_b64url(16));
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
            link_slot: link_slot.clone(),
            last_heartbeat: last,
        },
    );
    Reply::json(200, json!({"machine_id": id, "slot": slot, "link_slot": link_slot}))
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
    let link = match b.get("lane") {
        None => false,
        Some(l) if l == "link" => true,
        Some(_) => return Reply::error(400, "bad_request", "lane must be link"),
    };
    let (permission, role, slot) = match b["permission"].as_str() {
        Some("register") => {
            // Only ever for the caller's own machine.
            if target.is_some_and(|t| t != machine_id) {
                return Reply::error(400, "bad_request", "register tickets are for the caller's own machine");
            }
            ("register", "daemon", if link { own.link_slot.clone() } else { own.slot.clone() })
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
            ("connect", "client", if link { t.link_slot.clone() } else { t.slot.clone() })
        }
        _ => return Reply::error(400, "bad_request", "permission must be register or connect"),
    };
    signed_ticket(opts, permission, role, &slot)
}

fn signed_ticket(opts: &FakeOptions, permission: &str, role: &str, slot: &str) -> Reply {
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

const SHARE_ALPHABET: &[u8] = b"0123456789abcdefghjkmnpqrstvwxyz";

fn lifetime_secs(l: &str) -> Option<u64> {
    match l {
        "15m" => Some(900),
        "1h" => Some(3600),
        "until_quit" => Some(86400),
        _ => None,
    }
}

fn create_share(rec: &Recorded, st: &mut State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let Some(b) = rec.body.as_object() else { return Reply::error(400, "bad_request", "body must be an object") };
    if b.contains_key("secret") {
        return Reply::error(400, "bad_request", "secret must never be sent");
    }
    let id = b.get("id").and_then(Value::as_str).unwrap_or_default();
    if id.len() != 8 || !id.bytes().all(|c| SHARE_ALPHABET.contains(&c)) {
        return Reply::error(400, "bad_request", "id must be 8 characters of the share alphabet");
    }
    let (Some(permission), Some(lifetime)) = (b.get("permission").and_then(Value::as_str), b.get("lifetime").and_then(Value::as_str)) else {
        return Reply::error(400, "bad_request", "permission and lifetime are required");
    };
    if !matches!(permission, "view" | "type") {
        return Reply::error(400, "bad_request", "permission must be view or type");
    }
    if lifetime_secs(lifetime).is_none() {
        return Reply::error(400, "bad_request", "bad lifetime");
    }
    if b.get("access").and_then(Value::as_str).is_none_or(|a| a.len() != 43) {
        return Reply::error(400, "bad_request", "access must be 43 characters");
    }
    let one_time = match b.get("one_time") {
        None | Some(Value::Null) => false,
        Some(Value::Bool(v)) => *v,
        Some(_) => return Reply::error(400, "bad_request", "one_time must be a boolean"),
    };
    // R5: a one-time share is a typing share until quit with a 2-minute claim window.
    let (permission, lifetime) = if one_time { ("type", "until_quit") } else { (permission, lifetime) };
    let life = lifetime_secs(lifetime).expect("validated lifetime");
    let live = st.shares.values().filter(|s| s.device_id == who.device_id && !s.revoked && s.expires_at > now_unix()).count();
    if live >= 20 {
        return Reply::error(409, "share_limit", "Too many active shares");
    }
    if st.shares.contains_key(id) {
        return Reply::error(409, "share_id_taken", "That share id is already in use");
    }
    let now = now_unix();
    let (expires_at, claim_until) = (now + life, one_time.then_some(now + 120));
    let slot = random_b64url(16);
    let id = id.to_string();
    st.shares.insert(
        id.clone(),
        Share {
            device_id: who.device_id,
            slot: slot.clone(),
            permission: permission.to_string(),
            lifetime: lifetime.to_string(),
            created_at: now,
            expires_at,
            revoked: false,
        },
    );
    Reply::json(201, json!({"id": id, "slot": slot, "expires_at_unix": expires_at, "claim_until_unix": claim_until}))
}

fn list_shares(rec: &Recorded, st: &State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let now = now_unix();
    let mut items: Vec<(&String, &Share)> =
        st.shares.iter().filter(|(_, s)| s.device_id == who.device_id && s.expires_at > now).collect();
    items.sort_by(|a, b| (a.1.created_at, a.0).cmp(&(b.1.created_at, b.0)));
    let shares: Vec<Value> = items
        .into_iter()
        .map(|(id, s)| {
            json!({"id": id, "permission": s.permission, "lifetime": s.lifetime, "expires_at_unix": s.expires_at, "revoked": s.revoked})
        })
        .collect();
    Reply::json(200, json!({"shares": shares}))
}

fn owned_share<'a>(who: &TokenInfo, id: &str, st: &'a mut State) -> Option<&'a mut Share> {
    st.shares.get_mut(id).filter(|s| s.device_id == who.device_id)
}

fn revoke_share(rec: &Recorded, id: &str, st: &mut State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    match owned_share(&who, id, st) {
        Some(s) => {
            s.revoked = true;
            Reply::empty(204)
        }
        None => Reply::error(404, "share_not_found", "Share not found"),
    }
}

fn share_host_ticket(rec: &Recorded, id: &str, opts: &FakeOptions, st: &mut State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let Some(s) = owned_share(&who, id, st) else { return Reply::error(404, "share_not_found", "Share not found") };
    if s.revoked {
        return Reply::error(410, "share_revoked", "Share revoked");
    }
    if s.expires_at <= now_unix() {
        return Reply::error(410, "share_expired", "Share expired");
    }
    let slot = s.slot.clone();
    signed_ticket(opts, "register", "daemon", &slot)
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
    if st.machines.get(to).is_none_or(|m| m.user_id != who.user_id) {
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
    items.sort_by_key(|(_, p)| std::cmp::Reverse(p.seq));
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

/// Phone pairing of the caller's account targeting the caller's own machine (relay `phones.ts` rules).
fn target_phone_pairing<'a>(who: &TokenInfo, id: &str, st: &'a State) -> Result<&'a PhonePairing, Reply> {
    let p = st
        .phone_pairings
        .get(id)
        .filter(|p| p.user_id == who.user_id)
        .ok_or_else(|| Reply::error(404, "pairing_not_found", "Pairing not found"))?;
    if own_machine_id(who, st).as_deref() != Some(p.machine_id.as_str()) {
        return Err(Reply::error(403, "forbidden", "Forbidden"));
    }
    Ok(p)
}

fn list_phone_pairings(rec: &Recorded, st: &State) -> Reply {
    use base64::engine::general_purpose::STANDARD;
    let Some(who) = caller(rec, st) else { return unauthorized() };
    if !rec.query.split('&').any(|kv| kv == "role=target") {
        return Reply::error(400, "bad_request", "Malformed request");
    }
    let apple_links = rec.query.split('&').any(|kv| kv == "apple_links=1");
    let Some(own) = own_machine_id(&who, st) else { return Reply::json(200, json!({"pairings": []})) };
    let now = now_unix();
    let mut items: Vec<(&String, &PhonePairing)> = st
        .phone_pairings
        .iter()
        .filter(|(_, p)| p.machine_id == own && p.user_id == who.user_id && p.current_status(now) == "pending" && (apple_links || !p.links_apple_id))
        .collect();
    items.sort_by_key(|(_, p)| std::cmp::Reverse(p.seq));
    let pairings: Vec<Value> = items
        .into_iter()
        .map(|(id, p)| {
            json!({
                "pairing_id": id,
                "device_name": p.device_name,
                "platform": p.platform,
                "client_key_b64": STANDARD.encode(&p.client_key),
                "proof_b64": p.proof_b64,
                "created_at_unix": p.created_at,
                "links_apple_id": p.links_apple_id,
            })
        })
        .collect();
    Reply::json(200, json!({"pairings": pairings}))
}

fn approve_phone_pairing(rec: &Recorded, id: &str, st: &mut State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let p = match target_phone_pairing(&who, id, st) {
        Ok(p) => p.clone(),
        Err(r) => return r,
    };
    if p.current_status(now_unix()) != "pending" {
        return if p.status == "pending" {
            Reply::error(410, "pairing_expired", "Pairing expired")
        } else {
            Reply::error(409, "pairing_not_pending", "Pairing is not pending")
        };
    }
    st.phone_pairings.get_mut(id).expect("checked above").status = "approved".to_string();
    // One grant per (phone, machine): a re-approval replaces the old row.
    st.phone_grants.retain(|_, g| !(g.device_id == p.device_id && g.machine_id == p.machine_id));
    st.phone_seq += 1;
    let seq = st.phone_seq;
    st.phone_grants.insert(
        random_id(),
        PhoneGrant {
            user_id: p.user_id,
            device_id: p.device_id,
            device_name: p.device_name,
            platform: p.platform,
            machine_id: p.machine_id,
            client_key: p.client_key,
            created_at: now_unix(),
            seq,
        },
    );
    Reply::empty(204)
}

fn deny_phone_pairing(rec: &Recorded, id: &str, st: &mut State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let p = match target_phone_pairing(&who, id, st) {
        Ok(p) => p,
        Err(r) => return r,
    };
    match p.current_status(now_unix()) {
        "pending" => {
            st.phone_pairings.get_mut(id).expect("checked above").status = "denied".to_string();
            Reply::empty(204)
        }
        "denied" => Reply::empty(204),
        _ => Reply::error(409, "pairing_not_pending", "Pairing is not pending"),
    }
}

fn list_phone_grants(rec: &Recorded, st: &State) -> Reply {
    use base64::engine::general_purpose::STANDARD;
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let Some(own) = own_machine_id(&who, st) else { return Reply::json(200, json!({"grants": []})) };
    let mut items: Vec<(&String, &PhoneGrant)> =
        st.phone_grants.iter().filter(|(_, g)| g.machine_id == own && g.user_id == who.user_id).collect();
    items.sort_by_key(|(_, g)| g.seq);
    let grants: Vec<Value> = items
        .into_iter()
        .map(|(id, g)| {
            json!({
                "grant_id": id,
                "device_id": g.device_id,
                "device_name": g.device_name,
                "platform": g.platform,
                "client_key_b64": STANDARD.encode(&g.client_key),
                "created_at_unix": g.created_at,
                "last_seen_unix": Value::Null,
            })
        })
        .collect();
    Reply::json(200, json!({"grants": grants}))
}

/// `POST /v2/notifications`: answers how many phones are granted the caller's machine (no push is sent).
fn notify_phones(rec: &Recorded, st: &State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let Some(own) = own_machine_id(&who, st) else { return Reply::error(404, "not_found", "Not found") };
    let sent = st.phone_grants.values().filter(|g| g.machine_id == own && g.user_id == who.user_id).count();
    Reply::json(202, json!({"sent": sent}))
}

fn delete_phone_grant(rec: &Recorded, id: &str, st: &mut State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let Some(g) = st.phone_grants.get(id).filter(|g| g.user_id == who.user_id) else {
        return Reply::error(404, "not_found", "Not found");
    };
    if own_machine_id(&who, st).as_deref() != Some(g.machine_id.as_str()) {
        return Reply::error(403, "forbidden", "Forbidden");
    }
    st.phone_grants.remove(id);
    Reply::empty(204)
}

/// `{kind, name, platform, public_key}` per v1 `parseDevice` (+ kind `desktop`, which must be on `macos` or
/// `windows`: `relay/src/auth/device.ts:27`).
fn device_ok(d: &Value) -> bool {
    let kind_ok = d["kind"].as_str().is_some_and(|k| DEVICE_KINDS.contains(&k));
    let desktop_ok = d["kind"] != "desktop" || matches!(d["platform"].as_str(), Some("macos" | "windows"));
    let platform_ok = d["platform"].as_str().is_some_and(|p| DEVICE_PLATFORMS.contains(&p)) && desktop_ok;
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
    st.password_users.insert(user_id.clone());
    let token = issue_token(st, &user_id, &device_id, "password", None);
    Reply::json(200, json!({"user_id": user_id, "device_id": device_id, "token": token}))
}

/// One live token per device; the newest is `last_token`.
fn issue_token(st: &mut State, user_id: &str, device_id: &str, auth_method: &str, identity_id: Option<&str>) -> String {
    st.tokens.retain(|_, t| t.device_id != device_id);
    let token = random_b64url(32);
    st.tokens.insert(
        token.clone(),
        TokenInfo {
            user_id: user_id.to_string(),
            device_id: device_id.to_string(),
            auth_method: auth_method.to_string(),
            identity_id: identity_id.map(str::to_string),
        },
    );
    st.last_token = Some(token.clone());
    token
}

fn pct_decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        match b[i] {
            b'+' => out.push(b' '),
            b'%' if i + 2 < b.len() => {
                match u8::from_str_radix(&s[i + 1..i + 3], 16) {
                    Ok(v) => {
                        out.push(v);
                        i += 2;
                    }
                    Err(_) => out.push(b'%'),
                }
            }
            c => out.push(c),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn parse_form(s: &str) -> Vec<(String, String)> {
    s.split('&')
        .filter(|kv| !kv.is_empty())
        .map(|kv| {
            let (k, v) = kv.split_once('=').unwrap_or((kv, ""));
            (pct_decode(k), pct_decode(v))
        })
        .collect()
}

fn pct_encode(s: &str) -> String {
    let mut out = String::new();
    for c in s.bytes() {
        if c.is_ascii_alphanumeric() || matches!(c, b'-' | b'.' | b'_' | b'~') {
            out.push(c as char);
        } else {
            out.push_str(&format!("%{c:02X}"));
        }
    }
    out
}

fn issue_nonce(st: &mut State) -> Reply {
    let nonce = random_b64url(32);
    st.nonces.push(nonce.clone());
    Reply::json(201, json!({"nonce": nonce, "expires_in": 600}))
}

fn google_account(opts: &FakeOptions, st: &State) -> (String, String) {
    st.google_account.clone().unwrap_or_else(|| (opts.google_email.clone(), opts.google_subject.clone()))
}

fn google_error(status: u16, error: &str) -> Reply {
    Reply::json(status, json!({"error": error}))
}

/// `GET /fake-google/auth`: validates the request, then redirects back with a code.
fn fake_google_auth(rec: &Recorded, opts: &FakeOptions, st: &mut State) -> Reply {
    let q: HashMap<String, String> = parse_form(&rec.query).into_iter().collect();
    let get = |k: &str| q.get(k).map(String::as_str).unwrap_or("");
    let redirect = get("redirect_uri");
    let valid = get("client_id") == opts.google_client_id
        && get("response_type") == "code"
        && get("scope") == "openid email profile"
        && get("code_challenge_method") == "S256"
        && get("code_challenge").len() == 43
        && !get("state").is_empty()
        && !get("nonce").is_empty()
        && get("prompt") == "select_account"
        && redirect.starts_with("http://127.0.0.1:")
        && redirect.ends_with("/oauth2/callback");
    if !valid {
        return google_error(400, "invalid_request");
    }
    let code = format!("4/{}", random_b64url(24));
    let (email, subject) = google_account(opts, st);
    st.google_codes.insert(
        code.clone(),
        GoogleCode { challenge: get("code_challenge").to_string(), redirect_uri: redirect.to_string(), nonce: get("nonce").to_string(), email, subject, used: false },
    );
    let mut r = Reply::empty(302);
    r.location = Some(format!("{redirect}?code={}&state={}", pct_encode(&code), pct_encode(get("state"))));
    r
}

/// `POST /fake-google/token`: PKCE-checked code exchange.
fn fake_google_token(rec: &Recorded, opts: &FakeOptions, st: &mut State) -> Reply {
    let f = |k: &str| rec.form.get(k).map(String::as_str).unwrap_or("");
    if f("client_id") != opts.google_client_id || f("client_secret") != opts.google_client_secret {
        return google_error(400, "invalid_client");
    }
    let verifier_challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(f("code_verifier").as_bytes()));
    let ok = f("grant_type") == "authorization_code"
        && st.google_codes.get(f("code")).is_some_and(|c| !c.used && c.redirect_uri == f("redirect_uri") && c.challenge == verifier_challenge);
    if !ok {
        return google_error(400, "invalid_grant");
    }
    let c = st.google_codes.get_mut(f("code")).expect("checked above");
    c.used = true;
    let (email, subject, nonce) = (c.email.clone(), c.subject.clone(), c.nonce.clone());
    let idt = format!("fake-idt.{}", random_b64url(32));
    st.id_tokens.insert(idt.clone(), IdToken { email, subject, nonce, used: false });
    Reply::json(200, json!({"access_token": "fake-at", "expires_in": 3599, "id_token": idt, "scope": "openid email profile", "token_type": "Bearer"}))
}

/// Spend the relay nonce and the id_token; `(email, subject)` when both are valid for each other.
fn verify_google(rec: &Recorded, st: &mut State) -> Result<(String, String), Reply> {
    let invalid = || Reply::error(401, "invalid_credentials", "Google sign-in could not be verified");
    let nonce = rec.body["nonce"].as_str().unwrap_or("").to_string();
    let idt = rec.body["id_token"].as_str().unwrap_or("").to_string();
    let nonce_ok = st.nonces.contains(&nonce) && !st.spent_nonces.contains(&nonce);
    if nonce_ok {
        st.spent_nonces.insert(nonce.clone());
    }
    let token_ok = st.id_tokens.get(&idt).is_some_and(|t| !t.used && t.nonce == nonce);
    if let Some(t) = st.id_tokens.get_mut(&idt) {
        t.used = true;
    }
    if !(nonce_ok && token_ok) {
        return Err(invalid());
    }
    let t = &st.id_tokens[&idt];
    Ok((t.email.clone(), t.subject.clone()))
}

fn add_identity(st: &mut State, user_id: &str, provider: &str, subject: &str, email: &str, is_private_email: bool, via: Option<&str>) -> String {
    st.identity_seq += 1;
    let id = random_id();
    st.identities.push(Identity {
        id: id.clone(),
        user_id: user_id.to_string(),
        provider: provider.to_string(),
        subject: subject.to_string(),
        email: email.to_string(),
        is_private_email,
        linked_via_device_name: via.map(str::to_string),
        created_at: now_unix(),
        seq: st.identity_seq,
    });
    id
}

fn google_sign_in(rec: &Recorded, _opts: &FakeOptions, st: &mut State) -> Reply {
    if !rec.body.is_object() || !device_ok(&rec.body["device"]) {
        return Reply::error(400, "invalid_device", "Device information is not valid");
    }
    let (email, subject) = match verify_google(rec, st) {
        Ok(v) => v,
        Err(r) => return r,
    };
    let by_identity = st.identities.iter().find(|i| i.provider == "google" && i.subject == subject).map(|i| (i.user_id.clone(), i.id.clone()));
    let (user_id, identity_id) = if let Some(found) = by_identity {
        found
    } else if let Some(u) = st.users.get(&email).cloned() {
        if st.password_users.contains(&u) {
            return Reply::error(409, "switch_from_signed_in_device", "Switch to Google from a signed-in device");
        }
        let identity = add_identity(st, &u, "google", &subject, &email, false, None);
        (u, identity)
    } else {
        let u = random_id();
        st.users.insert(email.clone(), u.clone());
        let identity = add_identity(st, &u, "google", &subject, &email, false, None);
        (u, identity)
    };
    let key = rec.body["device"]["public_key"].as_str().unwrap_or_default().to_string();
    let device_id = st.devices.entry((user_id.clone(), key)).or_insert_with(random_id).clone();
    let token = issue_token(st, &user_id, &device_id, "google", Some(&identity_id));
    let account_email = st.users.iter().find(|(_, u)| **u == user_id).map(|(e, _)| e.clone()).unwrap_or(email);
    Reply::json(200, json!({"user_id": user_id, "device_id": device_id, "token": token, "email": account_email}))
}

fn google_link(rec: &Recorded, _opts: &FakeOptions, st: &mut State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let old = bearer(rec).unwrap_or_default().to_string();
    let (email, subject) = match verify_google(rec, st) {
        Ok(v) => v,
        Err(r) => return r,
    };
    let existing = st.identities.iter().find(|i| i.provider == "google" && i.subject == subject).map(|i| (i.user_id.clone(), i.id.clone()));
    let identity_id = match existing {
        Some((u, _)) if u != who.user_id => return Reply::error(409, "identity_in_use", "This Google account is linked to another ShellX account"),
        Some((_, id)) => id,
        None => {
            if st.identities.iter().any(|i| i.provider == "google" && i.user_id == who.user_id) {
                return Reply::error(409, "identity_in_use", "This account already uses another Google account");
            }
            if st.users.get(&email).is_some_and(|u| *u != who.user_id) {
                return Reply::error(409, "email_in_use", "Another account already uses this email");
            }
            let identity = add_identity(st, &who.user_id, "google", &subject, &email, false, None);
            let old_email = st.users.iter().find(|(_, u)| **u == who.user_id).map(|(e, _)| e.clone());
            if let Some(oe) = old_email {
                // A link to another address drops the account's email sign-ins, and their tokens with them.
                if oe != email {
                    let gone: Vec<String> = st.identities.iter().filter(|i| i.user_id == who.user_id && i.provider == "email").map(|i| i.id.clone()).collect();
                    st.identities.retain(|i| !gone.contains(&i.id));
                    st.tokens.retain(|_, t| t.identity_id.as_ref().is_none_or(|id| !gone.contains(id)));
                }
                st.users.remove(&oe);
            }
            st.users.insert(email.clone(), who.user_id.clone());
            identity
        }
    };
    st.tokens.remove(&old);
    let token = issue_token(st, &who.user_id, &who.device_id, "google", Some(&identity_id));
    let account_email = st.users.iter().find(|(_, u)| **u == who.user_id).map(|(e, _)| e.clone()).unwrap_or(email);
    Reply::json(200, json!({"user_id": who.user_id, "device_id": who.device_id, "token": token, "email": account_email}))
}

fn list_identities(rec: &Recorded, st: &State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let mut items: Vec<&Identity> = st.identities.iter().filter(|i| i.user_id == who.user_id).collect();
    items.sort_by_key(|i| i.seq);
    let list: Vec<Value> = items
        .into_iter()
        .map(|i| {
            json!({
                "identity_id": i.id,
                "provider": i.provider,
                "email": i.email,
                "is_private_email": i.is_private_email,
                "linked_via_device_name": i.linked_via_device_name,
                "created_at_unix": i.created_at,
            })
        })
        .collect();
    Reply::json(200, json!({"identities": list}))
}

fn remove_identity(rec: &Recorded, id: &str, st: &mut State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let Some(ident) = st.identities.iter().find(|i| i.id == id && i.user_id == who.user_id).cloned() else {
        return Reply::error(404, "identity_not_found", "Identity not found");
    };
    // The account keeps one of its Google (or test) and email sign-ins; Apple IDs never count and are always removable.
    let counts = |provider: &str| matches!(provider, "google" | "test" | "email");
    if counts(&ident.provider) && st.identities.iter().filter(|i| i.user_id == who.user_id && counts(&i.provider)).count() == 1 {
        return Reply::error(409, "last_google_identity", "A Google or email sign-in is required");
    }
    st.identities.retain(|i| i.id != id);
    st.tokens.retain(|_, t| t.identity_id.as_deref() != Some(id));
    Reply::empty(204)
}

fn delete_account(rec: &Recorded, st: &mut State) -> Reply {
    let Some(who) = caller(rec, st) else { return unauthorized() };
    let reauth = || Reply::error(401, "reauth_required", "Sign in again to delete the account");
    // Tried in the relay's order: a Google id_token, then a mailed code.
    if rec.body["id_token"].as_str().is_some() {
        let (_, subject) = match verify_google(rec, st) {
            Ok(v) => v,
            Err(r) => return r,
        };
        if !st.identities.iter().any(|i| i.provider == "google" && i.subject == subject && i.user_id == who.user_id) {
            return Reply::error(401, "invalid_credentials", "Google sign-in could not be verified");
        }
    } else if rec.body["challenge_id"].is_string() {
        // The challenge rules of /verify apply; a right code for another address is spent and refused.
        let email = match redeem_email_code(&rec.body["challenge_id"], &rec.body["code"], st) {
            Ok(e) => e,
            Err(r) => return r,
        };
        let own = st.users.iter().find(|(_, u)| **u == who.user_id).map(|(e, _)| e.clone());
        if own.as_deref() != Some(email.as_str()) {
            return reauth();
        }
    } else {
        return reauth();
    }
    let uid = who.user_id;
    st.users.retain(|_, u| *u != uid);
    st.identities.retain(|i| i.user_id != uid);
    st.tokens.retain(|_, t| t.user_id != uid);
    st.password_users.remove(&uid);
    Reply::empty(204)
}

/// The relay's address rule (`relay/src/auth/email.ts:5-19`) on an already trimmed, lowercased address: an ASCII
/// dot-atom local part, LDH labels, an alphabetic TLD of 2-63 letters, at most 254 characters, the last "@" at
/// index 1-64.
fn email_valid(e: &str) -> bool {
    if !e.is_ascii() || e.len() > 254 {
        return false;
    }
    let Some(at) = e.rfind('@') else { return false };
    if !(1..=64).contains(&at) || e.matches('@').count() != 1 {
        return false;
    }
    let (local, domain) = (&e[..at], &e[at + 1..]);
    let atom = |c: u8| c.is_ascii_lowercase() || c.is_ascii_digit() || b"!#$%&'*+/=?^_`{|}~-".contains(&c);
    if !local.split('.').all(|part| !part.is_empty() && part.bytes().all(atom)) {
        return false;
    }
    let labels: Vec<&str> = domain.split('.').collect();
    if labels.len() < 2 {
        return false;
    }
    let (tld, mids) = labels.split_last().expect("two labels");
    let ldh = |l: &str| {
        let b = l.as_bytes();
        (1..=63).contains(&b.len())
            && b.iter().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == b'-')
            && b[0] != b'-'
            && b[b.len() - 1] != b'-'
    };
    mids.iter().all(|l| ldh(l)) && (2..=63).contains(&tld.len()) && tld.bytes().all(|c| c.is_ascii_lowercase())
}

/// The fake's stand-in for the relay's disposable list: `mailinator.com` and its subdomains.
fn email_disposable(e: &str) -> bool {
    let domain = &e[e.rfind('@').map_or(0, |i| i + 1)..];
    domain == "mailinator.com" || domain.ends_with(".mailinator.com")
}

/// `POST /v1/auth/email/code`, in the relay's order (no rate limit is counted).
fn email_code_request(rec: &Recorded, opts: &FakeOptions, st: &mut State) -> Reply {
    if !opts.email_sign_in {
        return Reply::error(503, "email_sign_in_disabled", "Email sign-in is not available");
    }
    if !rec.body.is_object() {
        return Reply::error(400, "bad_request", "Malformed request body");
    }
    let email = rec.body["email"].as_str().map(|e| e.trim().to_lowercase()).filter(|e| email_valid(e));
    let Some(email) = email else { return Reply::error(400, "invalid_email", "Email address is not valid") };
    if email_disposable(&email) {
        return Reply::error(400, "disposable_email", "Temporary email addresses cannot be used");
    }
    let locale = if rec.body["locale"] == "vi" { "vi" } else { "en" };
    // The address's older challenge goes first, then the new one is stored (the relay's `issueEmailCode`).
    st.email_challenges.retain(|_, c| c.email != email);
    if std::mem::take(&mut st.fail_next_mail) {
        // The mail failed: the new challenge is discarded too, so the address has no live code at all.
        return Reply::error(502, "email_send_failed", "Could not send the email");
    }
    let code = st.next_email_code.take().unwrap_or_else(random_code);
    let challenge_id = random_b64url(32);
    st.email_challenges.insert(
        challenge_id.clone(),
        EmailChallenge { email: email.clone(), code, locale: locale.to_string(), attempts: 0, expires_at: now_unix() + EMAIL_CODE_TTL_SECS },
    );
    Reply::json(202, json!({"challenge_id": challenge_id, "expires_in": EMAIL_CODE_TTL_SECS, "resend_in": EMAIL_RESEND_SECS, "email": email}))
}

fn code_expired() -> Reply {
    Reply::error(410, "code_expired", "This code no longer works")
}

/// One guess at a challenge, as the relay's `redeemEmailCode`: `Ok(email)` for the right code (the challenge is
/// gone), `Err` with the answer otherwise.
fn redeem_email_code(challenge_id: &Value, code: &Value, st: &mut State) -> Result<String, Reply> {
    let id = challenge_id
        .as_str()
        .filter(|s| s.len() == 43 && s.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_'))
        .ok_or_else(code_expired)?;
    let live = st.email_challenges.get(id).map(|c| c.expires_at > now_unix());
    match live {
        None => return Err(code_expired()),
        Some(false) => {
            st.email_challenges.remove(id);
            return Err(code_expired());
        }
        Some(true) => {}
    }
    let c = st.email_challenges.get_mut(id).expect("checked above");
    c.attempts += 1;
    let right = code.as_str() == Some(c.code.as_str());
    let (attempts, email) = (c.attempts, c.email.clone());
    if right {
        st.email_challenges.remove(id);
        return Ok(email);
    }
    if attempts >= EMAIL_CODE_MAX_ATTEMPTS {
        st.email_challenges.remove(id);
        return Err(code_expired());
    }
    Err(Reply::error(401, "invalid_code", "That code is not right"))
}

/// `POST /v1/auth/email/verify`, in the relay's order.
fn email_verify(rec: &Recorded, st: &mut State) -> Reply {
    if !rec.body.is_object() {
        return Reply::error(400, "bad_request", "Malformed request body");
    }
    let device = &rec.body["device"];
    if !device_ok(device) || device["kind"] == "agent" {
        return Reply::error(400, "invalid_device", "Device information is not valid");
    }
    let email = match redeem_email_code(&rec.body["challenge_id"], &rec.body["code"], st) {
        Ok(e) => e,
        Err(r) => return r,
    };
    // The code is spent. Now the account (`matchAccount` and the branches of the handler).
    let switch = || Reply::error(409, "switch_from_signed_in_device", "Switch to email sign-in from a signed-in device");
    let by_identity = st.identities.iter().find(|i| i.provider == "email" && i.subject == email).map(|i| (i.user_id.clone(), i.id.clone()));
    let (user_id, identity_id) = if let Some(found) = by_identity {
        found
    } else if let Some(u) = st.users.get(&email).cloned() {
        if st.password_users.contains(&u) {
            return switch();
        }
        let has_primary = st.identities.iter().any(|i| i.user_id == u && (i.provider == "google" || i.provider == "test"));
        if !has_primary {
            if st.identities.iter().any(|i| i.user_id == u) {
                return switch();
            }
            // Nobody verified this address: the code claims the account and every earlier session goes.
            st.tokens.retain(|_, t| t.user_id != u);
        }
        let identity = add_identity(st, &u, "email", &email, &email, false, None);
        (u, identity)
    } else {
        let u = random_id();
        st.users.insert(email.clone(), u.clone());
        let identity = add_identity(st, &u, "email", &email, &email, false, None);
        (u, identity)
    };
    let key = device["public_key"].as_str().unwrap_or_default().to_string();
    let device_id = st.devices.entry((user_id.clone(), key)).or_insert_with(random_id).clone();
    let token = issue_token(st, &user_id, &device_id, "email", Some(&identity_id));
    let account_email = st.users.iter().find(|(_, u)| **u == user_id).map(|(e, _)| e.clone()).unwrap_or(email);
    Reply::json(200, json!({"user_id": user_id, "device_id": device_id, "token": token, "email": account_email}))
}

/// Test browser: GET `url` (loopback only), follow one 3xx `Location` (loopback only).
pub fn browse(url: &str) -> Result<(u16, String), String> {
    fn get(url: &str) -> Result<(u16, Option<String>, String), String> {
        let rest = url.strip_prefix("http://127.0.0.1:").ok_or_else(|| "browse: only http://127.0.0.1: URLs".to_string())?;
        let (port, path) = rest.split_once('/').map(|(p, r)| (p, format!("/{r}"))).unwrap_or((rest, "/".to_string()));
        let mut s = std::net::TcpStream::connect(format!("127.0.0.1:{port}")).map_err(|e| e.to_string())?;
        let _ = s.set_read_timeout(Some(std::time::Duration::from_secs(10)));
        use std::io::Write;
        write!(s, "GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\n\r\n").map_err(|e| e.to_string())?;
        let mut resp = String::new();
        s.read_to_string(&mut resp).map_err(|e| e.to_string())?;
        let status: u16 = resp.get(9..12).and_then(|c| c.parse().ok()).ok_or_else(|| "browse: bad status line".to_string())?;
        let (head, body) = resp.split_once("\r\n\r\n").unwrap_or((&resp, ""));
        let loc = head.lines().find_map(|l| {
            let (k, v) = l.split_once(':')?;
            k.eq_ignore_ascii_case("location").then(|| v.trim().to_string())
        });
        Ok((status, loc, body.to_string()))
    }
    let (status, loc, body) = get(url)?;
    if (300..400).contains(&status) {
        if let Some(l) = loc {
            let (s2, _, b2) = get(&l)?;
            return Ok((s2, b2));
        }
    }
    Ok((status, body))
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
