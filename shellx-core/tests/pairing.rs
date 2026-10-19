//! `pair.request` / `pair.pending` / `pair.approve` / `pair.deny` / `pair.poll`
//! between two cores on one account: A = requester, B = target.
mod support;

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use shellx_core::Core;
use shellx_fake_api::FakeApi;
use support::{Dir, requests_to};

const ROUTE: &str = "relay+wss://relay.test/v2/relay";
const SECRET_B64: &str = "U0VDUkVULVBTSy1ET05PVExFQUstMDEyMzQ1Njc4OWE";
const TICKET: &str = "v2.connect-ticket-SECRET.sig";

/// The daemon key in every test invite, and its cmux fingerprint
/// (`cmux-remote/src/crypto.rs:72`: b64url-nopad of SHA-256(key)[..16]).
fn daemon_key() -> [u8; 32] {
    [5u8; 32]
}
fn daemon_fp() -> String {
    URL_SAFE_NO_PAD.encode(&Sha256::digest(daemon_key())[..16])
}

/// A `cmux://enroll/` URI shaped exactly like `EnrollmentInvitation::to_uri`
/// (`cmux-remote/src/identity.rs:67-79,106-110`): URL-safe base64 without padding
/// of the invitation JSON, `relay_access` = `[{route, slot, ticket}]`.
fn invite(route: &str, slot: &str) -> String {
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs();
    let inv = json!({
        "version": 1,
        "id": "inv_test_0001",
        "secret": SECRET_B64,
        "daemon_public_key": URL_SAFE_NO_PAD.encode(daemon_key()),
        "daemon_fingerprint": daemon_fp(),
        "daemon_name": "Mac B",
        "expires_at_unix": now + 300,
        "route_hints": [route],
        "relay_access": [{"route": route, "slot": slot, "ticket": TICKET}],
        "approval_required": true,
    });
    format!("cmux://enroll/{}", URL_SAFE_NO_PAD.encode(inv.to_string()))
}

fn uri() -> String {
    invite(ROUTE, "slotB")
}

struct Pair {
    fake: FakeApi,
    a: Core,
    b: Core,
    a_dir: Dir,
    _b_dir: Dir,
    a_login: Value,
    a_id: String,
    b_id: String,
}

fn machine(fake: &FakeApi, email: &str, name: &str) -> (Core, Dir, Value, String) {
    let core = Core::new();
    let dir = support::state_dir();
    support::configure(&core, &fake.base_url, &dir, json!({}));
    let login = core.call("auth.login", json!({"email": email, "password": "pw"})).unwrap();
    let m = core
        .call("machines.register", json!({"name": name, "platform": "macos", "os_version": "15", "app_version": "2.0.0"}))
        .unwrap();
    (core, dir, login, m["machine_id"].as_str().unwrap().to_string())
}

fn pair() -> Pair {
    let fake = support::fake();
    let (a, a_dir, a_login, a_id) = machine(&fake, "a@b.c", "Mac A");
    let (b, b_dir, _, b_id) = machine(&fake, "a@b.c", "Mac B");
    Pair { fake, a, b, a_dir, _b_dir: b_dir, a_login, a_id, b_id }
}

impl Pair {
    fn request(&self) -> String {
        let r = self.a.call("pair.request", json!({"to_machine_id": self.b_id})).unwrap();
        r["pairing_id"].as_str().unwrap().to_string()
    }
    /// B lists its pending requests (what the person sees before approving).
    fn show(&self) -> Value {
        self.b.call("pair.pending", json!({})).unwrap()
    }
    fn approve_posts(&self) -> usize {
        self.fake.requests().iter().filter(|r| r.path.ends_with("/approve")).count()
    }
}

#[test]
fn request_returns_code_and_local_fingerprint() {
    let p = pair();
    // A caller-supplied from_machine_id is ignored: the stored own id is always sent.
    let r = p.a.call("pair.request", json!({"to_machine_id": p.b_id, "from_machine_id": "evil"})).unwrap();
    let code = r["code"].as_str().unwrap();
    assert!(code.len() == 6 && code.bytes().all(|c| c.is_ascii_digit()), "{code}");
    assert_eq!(r["fingerprint"], p.a_login["fingerprint"]);
    assert!(r["pairing_id"].as_str().is_some_and(|s| !s.is_empty()));
    let req = &requests_to(&p.fake, "/v2/pairings")[0];
    assert_eq!(req.method, "POST");
    assert_eq!(req.body["from_machine_id"], json!(p.a_id));
    assert_eq!(req.body["to_machine_id"], json!(p.b_id));
    assert_eq!(req.body["requester_x25519_b64"], p.a_login["device_public_key_b64"]);
}

#[test]
fn target_sees_pending_with_matching_fingerprint() {
    let p = pair();
    let r = p.a.call("pair.request", json!({"to_machine_id": p.b_id})).unwrap();
    let pending = p.b.call("pair.pending", json!({})).unwrap();
    let items = pending["pairings"].as_array().unwrap();
    assert_eq!(items.len(), 1);
    let it = &items[0];
    assert_eq!(it["pairing_id"], r["pairing_id"]);
    assert_eq!(it["from_machine_id"], json!(p.a_id));
    assert_eq!(it["code"], r["code"]);
    assert_eq!(it["fingerprint"], p.a_login["fingerprint"]);
    assert_eq!(it["server_fingerprint"], p.a_login["fingerprint"]);
    assert_eq!(it["suspicious"], json!(false));
    // The requester is not a target of its own request.
    assert_eq!(p.a.call("pair.pending", json!({})).unwrap(), json!({"pairings": []}));
    let get = requests_to(&p.fake, "/v2/pairings").into_iter().find(|r| r.method == "GET").unwrap();
    assert_eq!(get.query, "role=target");
}

#[test]
fn approve_seals_and_requester_opens() {
    let p = pair();
    let pid = p.request();
    assert_eq!(p.a.call("pair.poll", json!({"pairing_id": pid})).unwrap(), json!({"status": "pending"}));
    p.show();
    let out = p.b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": uri()})).unwrap();
    assert_eq!(out, json!({}));
    let poll = p.a.call("pair.poll", json!({"pairing_id": pid, "write_invite_to": "invite-b.uri"})).unwrap();
    assert_eq!(poll["status"], "approved");
    assert_eq!(poll["relay_route"], ROUTE);
    assert_eq!(poll["relay_slot"], "slotB");
    assert_eq!(poll["daemon_fingerprint"], json!(daemon_fp()));
    assert!(poll.get("invite_uri").is_none());
    let path = std::path::PathBuf::from(poll["invite_path"].as_str().unwrap());
    assert_eq!(path, p.a_dir.join("tickets").join("invite-b.uri"));
    #[cfg(unix)]
    assert_eq!(support::mode(&path), 0o600);
    assert_eq!(std::fs::read_to_string(&path).unwrap(), uri());
    // The secret and the relay ticket never appear in the response.
    let s = poll.to_string();
    assert!(!s.contains(SECRET_B64) && !s.contains(TICKET) && !s.contains("cmux://"));
    // The server holds ciphertext only.
    let stored = p.fake.stored_sealed(&pid);
    assert!(!stored.is_empty() && !stored.contains("cmux://"));
    let post = requests_to(&p.fake, &format!("/v2/pairings/{pid}/approve"));
    assert_eq!(post.len(), 1);
    assert_eq!(post[0].body["sealed_invite_b64"], json!(stored));
    assert!(!post[0].body.to_string().contains(&uri()));
    // Approval grants connect from requester to target (not the reverse).
    assert!(p.fake.has_grant(&p.a_id, &p.b_id) && !p.fake.has_grant(&p.b_id, &p.a_id));
    p.a.call("tickets.mint", json!({"permission": "connect", "target_machine_id": p.b_id})).unwrap();
}

#[test]
fn poll_returns_invite_uri_when_not_written() {
    let p = pair();
    let pid = p.request();
    p.show();
    p.b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": uri()})).unwrap();
    let poll = p.a.call("pair.poll", json!({"pairing_id": pid})).unwrap();
    assert_eq!(poll["invite_uri"], json!(uri()));
    assert!(poll.get("invite_path").is_none());
    assert_eq!(poll["relay_slot"], "slotB");
    assert!(std::fs::read_dir(p.a_dir.join("tickets")).unwrap().next().is_none());
}

#[test]
fn approve_refuses_fingerprint_mismatch() {
    let p = pair();
    let pid = p.request();
    p.fake.tamper_requester_fingerprint(&pid, "0000000000000000");
    let items = p.b.call("pair.pending", json!({})).unwrap()["pairings"].clone();
    assert_eq!(items[0]["suspicious"], json!(true));
    assert_eq!(items[0]["server_fingerprint"], "0000000000000000");
    assert_eq!(items[0]["fingerprint"], p.a_login["fingerprint"]);
    let e = p.b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": uri()})).unwrap_err();
    assert_eq!(e.code, "fingerprint_mismatch");
    assert!(!format!("{e:?}").contains("cmux://") && !e.message.contains(SECRET_B64));
    assert_eq!(p.approve_posts(), 0);
}

#[test]
fn approve_refuses_fingerprint_other_than_the_one_shown() {
    let p = pair();
    let pid = p.request();
    let e = p
        .b
        .call("pair.approve", json!({"pairing_id": pid, "invite_uri": uri(), "fingerprint": "0123456789abcdef"}))
        .unwrap_err();
    assert_eq!(e.code, "fingerprint_mismatch");
    assert_eq!(p.approve_posts(), 0);
    let fp = p.a_login["fingerprint"].clone();
    p.b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": uri(), "fingerprint": fp})).unwrap();
    assert_eq!(p.approve_posts(), 1);
}

#[test]
fn suspicious_item_without_requester_key_cannot_be_approved() {
    let p = pair();
    let pid = p.request();
    p.fake.drop_requester_key(&pid);
    let items = p.b.call("pair.pending", json!({})).unwrap()["pairings"].clone();
    assert_eq!(items[0]["suspicious"], json!(true));
    assert_eq!(items[0]["fingerprint"], "");
    let e = p.b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": uri()})).unwrap_err();
    assert_eq!(e.code, "contract_missing_requester_key");
    assert_eq!(p.approve_posts(), 0);
}

#[test]
fn approve_refuses_non_pending() {
    let p = pair();
    let pid = p.request();
    assert_eq!(p.b.call("pair.deny", json!({"pairing_id": pid})).unwrap(), json!({}));
    let e = p.b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": uri()})).unwrap_err();
    assert_eq!(e.code, "pairing_not_pending");
    let pid2 = p.request();
    p.fake.expire(&pid2);
    let e = p.b.call("pair.approve", json!({"pairing_id": pid2, "invite_uri": uri()})).unwrap_err();
    assert_eq!(e.code, "pairing_not_pending");
    // A pairing the target cannot see (unknown id, or one where it is the requester).
    let e = p.b.call("pair.approve", json!({"pairing_id": "no-such-pairing", "invite_uri": uri()})).unwrap_err();
    assert_eq!(e.code, "not_found");
    let pid3 = p.request();
    let e = p.a.call("pair.approve", json!({"pairing_id": pid3, "invite_uri": uri()})).unwrap_err();
    assert_eq!(e.code, "not_found");
    assert_eq!(p.approve_posts(), 0);
}

#[test]
fn poll_rejects_invite_moved_to_another_pairing() {
    let p = pair();
    let pid1 = p.request();
    p.show();
    p.b.call("pair.approve", json!({"pairing_id": pid1, "invite_uri": uri()})).unwrap();
    let pid2 = p.request();
    p.fake.move_sealed_invite(&pid1, &pid2);
    let e = p.a.call("pair.poll", json!({"pairing_id": pid2, "write_invite_to": "invite.uri"})).unwrap_err();
    assert_eq!(e.code, "invite_invalid");
    // pid1 is approved but its invite is gone: also invite_invalid, nothing written.
    let e = p.a.call("pair.poll", json!({"pairing_id": pid1, "write_invite_to": "invite.uri"})).unwrap_err();
    assert_eq!(e.code, "invite_invalid");
    assert!(std::fs::read_dir(p.a_dir.join("tickets")).unwrap().next().is_none());
}

#[test]
fn denied_and_expired_pass_through() {
    let p = pair();
    let pid = p.request();
    p.b.call("pair.deny", json!({"pairing_id": pid})).unwrap();
    assert_eq!(requests_to(&p.fake, &format!("/v2/pairings/{pid}/deny"))[0].method, "POST");
    assert_eq!(p.a.call("pair.poll", json!({"pairing_id": pid})).unwrap(), json!({"status": "denied"}));
    let pid2 = p.request();
    p.fake.expire(&pid2);
    assert_eq!(p.a.call("pair.poll", json!({"pairing_id": pid2})).unwrap(), json!({"status": "expired"}));
    assert_eq!(p.b.call("pair.pending", json!({})).unwrap(), json!({"pairings": []}));
    // Deny of an already expired pairing passes the server code through.
    assert_eq!(p.b.call("pair.deny", json!({"pairing_id": pid2})).unwrap_err().code, "pairing_not_pending");
    // Polling a pairing this machine did not request.
    assert_eq!(p.b.call("pair.poll", json!({"pairing_id": pid})).unwrap_err().code, "not_found");
}

#[test]
fn pending_ignores_pairings_for_other_machines() {
    let p = pair();
    let (_c, _c_dir, _, c_id) = machine(&p.fake, "a@b.c", "Mac C");
    p.a.call("pair.request", json!({"to_machine_id": c_id})).unwrap();
    let to_b = p.request();
    // Supersedes the first A -> C request (now expired); a second pending to C.
    p.a.call("pair.request", json!({"to_machine_id": c_id})).unwrap();
    // Even when the server returns every pairing of the account, B lists only
    // pending requests whose target is B.
    p.fake.set_list_all_pairings(true);
    let items = p.b.call("pair.pending", json!({})).unwrap()["pairings"].as_array().unwrap().clone();
    assert_eq!(items.len(), 1, "{items:?}");
    assert_eq!(items[0]["pairing_id"], json!(to_b));
    p.b.call("pair.deny", json!({"pairing_id": to_b})).unwrap();
    assert_eq!(p.b.call("pair.pending", json!({})).unwrap(), json!({"pairings": []}));
}

#[test]
fn invalid_params_never_reach_the_server() {
    let p = pair();
    let before = p.fake.requests().len();
    let bad = [
        ("pair.request", json!({})),
        ("pair.request", json!({"to_machine_id": 5})),
        ("pair.request", json!({"to_machine_id": p.b_id})),
        ("pair.approve", json!({"pairing_id": "../x", "invite_uri": uri()})),
        ("pair.approve", json!({"pairing_id": "a?b", "invite_uri": uri()})),
        ("pair.approve", json!({"pairing_id": "p1"})),
        ("pair.approve", json!({"pairing_id": "p1", "invite_uri": "https://example.com"})),
        ("pair.approve", json!({"pairing_id": "p1", "invite_uri": "cmux://enroll/not-json"})),
        ("pair.approve", json!({"pairing_id": "p1", "invite_uri": invite("wss://relay.test/v2/relay", "s")})),
        ("pair.approve", json!({"pairing_id": "p1", "invite_uri": invite(ROUTE, "")})),
        ("pair.approve", json!({"pairing_id": "p1", "invite_uri": uri(), "fingerprint": 5})),
        ("pair.deny", json!({"pairing_id": ""})),
        ("pair.deny", json!({"pairing_id": "a/b"})),
        ("pair.poll", json!({})),
        ("pair.poll", json!({"pairing_id": "p1", "write_invite_to": "../x"})),
        ("pair.poll", json!({"pairing_id": "p1", "write_invite_to": "device.key/x"})),
        ("pair.poll", json!({"pairing_id": "p1", "write_invite_to": 5})),
    ];
    for (m, params) in bad {
        let e = p.b.call(m, params.clone()).unwrap_err();
        assert_eq!(e.code, "invalid_params", "{m} {params}");
        assert!(!e.message.contains("cmux://") && !e.message.contains(SECRET_B64), "{m}: {}", e.message);
    }
    assert_eq!(p.fake.requests().len(), before, "invalid params must not reach the server");
}

#[test]
fn unregistered_machine_cannot_pair() {
    let (core, fake, _dir) = support::logged_in();
    for (m, params) in [
        ("pair.request", json!({"to_machine_id": "m1"})),
        ("pair.pending", json!({})),
        ("pair.approve", json!({"pairing_id": "p1", "invite_uri": uri()})),
        ("pair.poll", json!({"pairing_id": "p1"})),
    ] {
        assert_eq!(core.call(m, params).unwrap_err().code, "not_registered", "{m}");
    }
    assert!(requests_to(&fake, "/v2/pairings").is_empty());
}

/// The attacker key a lying server swaps in (a valid X25519 point).
fn attacker_key() -> [u8; 32] {
    x25519_dalek::PublicKey::from(&x25519_dalek::StaticSecret::from([9u8; 32])).to_bytes()
}

#[test]
fn approve_without_shown_fingerprint_fails_closed() {
    let p = pair();
    let pid = p.request();
    // No pair.pending on this Core and no fingerprint param: nothing was shown.
    let e = p.b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": uri()})).unwrap_err();
    assert_eq!(e.code, "fingerprint_mismatch");
    assert_eq!(p.approve_posts(), 0);
    // config.set forgets what was shown.
    p.show();
    support::configure(&p.b, &p.fake.base_url, &p._b_dir, json!({}));
    let e = p.b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": uri()})).unwrap_err();
    assert_eq!(e.code, "fingerprint_mismatch");
    assert_eq!(p.approve_posts(), 0);
}

#[test]
fn approve_refuses_key_swapped_after_pending() {
    let p = pair();
    let pid = p.request();
    let shown = p.show()["pairings"][0]["fingerprint"].clone();
    assert_eq!(shown, p.a_login["fingerprint"]);
    // The server swaps the key and keeps its fingerprint consistent with it.
    p.fake.swap_requester_key(&pid, attacker_key());
    // Remembered fingerprint (no param) ...
    let e = p.b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": uri()})).unwrap_err();
    assert_eq!(e.code, "fingerprint_mismatch");
    // ... and the shown fingerprint passed explicitly.
    let e = p.b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": uri(), "fingerprint": shown})).unwrap_err();
    assert_eq!(e.code, "fingerprint_mismatch");
    assert_eq!(p.approve_posts(), 0);
    // The param wins over the remembered value: a wrong param is refused even
    // though the last pending showed the (now current) attacker fingerprint.
    let now_shown = p.show()["pairings"][0]["fingerprint"].clone();
    assert_ne!(now_shown, shown);
    let e = p.b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": uri(), "fingerprint": shown})).unwrap_err();
    assert_eq!(e.code, "fingerprint_mismatch");
    assert_eq!(p.approve_posts(), 0);
}

/// L4 R17 (D1 enforced server-side): a pairing request whose key is not the
/// requester machine's registered key is refused, and nothing is created.
#[test]
fn request_with_key_other_than_registered_is_refused() {
    let fake = support::fake();
    let a = Core::new();
    let a_dir = support::state_dir();
    support::configure(&a, &fake.base_url, &a_dir, json!({}));
    a.call("auth.login", json!({"email": "a@b.c", "password": "pw"})).unwrap();
    // Registered under a key that is not this state_dir's device key.
    a.call(
        "machines.register",
        json!({"name": "Mac A", "platform": "macos", "os_version": "15", "app_version": "2.0.0",
               "noise_public_key_b64": URL_SAFE_NO_PAD.encode(attacker_key())}),
    )
    .unwrap();
    let (b, _b_dir, _, b_id) = machine(&fake, "a@b.c", "Mac B");
    let e = a.call("pair.request", json!({"to_machine_id": b_id})).unwrap_err();
    assert_eq!(e.code, "bad_request");
    assert!(b.call("pair.pending", json!({})).unwrap()["pairings"].as_array().unwrap().is_empty());
}

/// L4 R13: the requester's own items carry `requester_x25519_b64` too.
#[test]
fn requester_list_items_carry_the_requester_key() {
    let p = pair();
    p.request();
    let session: Value = serde_json::from_slice(&std::fs::read(p.a_dir.join("session.json")).unwrap()).unwrap();
    let token = session["token"].as_str().unwrap();
    let mut res = ureq::get(format!("{}/v2/pairings?role=requester", p.fake.base_url))
        .header("Authorization", format!("Bearer {token}"))
        .call()
        .unwrap();
    let body: Value = serde_json::from_str(&res.body_mut().read_to_string().unwrap()).unwrap();
    let item = &body["pairings"][0];
    let shown = base64::engine::general_purpose::STANDARD.decode(item["requester_x25519_b64"].as_str().expect("key present")).unwrap();
    let own = URL_SAFE_NO_PAD.decode(p.a_login["device_public_key_b64"].as_str().unwrap()).unwrap();
    assert_eq!(shown, own, "{item}");
}

#[test]
fn login_and_logout_forget_the_shown_fingerprints() {
    let p = pair();
    let pid = p.request();
    p.show();
    // Re-login (same account, machine kept) forgets what was shown.
    p.b.call("auth.login", json!({"email": "a@b.c", "password": "pw"})).unwrap();
    let e = p.b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": uri()})).unwrap_err();
    assert_eq!(e.code, "fingerprint_mismatch");
    // So does logout (then sign back in and re-register the same machine).
    p.show();
    p.b.call("auth.logout", json!({})).unwrap();
    p.b.call("auth.login", json!({"email": "a@b.c", "password": "pw"})).unwrap();
    let reg = json!({"name": "Mac B", "platform": "macos", "os_version": "15", "app_version": "2.0.0"});
    p.b.call("machines.register", reg).unwrap();
    let e = p.b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": uri()})).unwrap_err();
    assert_eq!(e.code, "fingerprint_mismatch");
    assert_eq!(p.approve_posts(), 0);
}
