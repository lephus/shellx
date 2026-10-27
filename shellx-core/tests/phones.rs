//! `phones.pending` / `phones.approve` / `phones.deny` / `phones.grants` / `phones.revoke`:
//! the Mac side of phone pairing (`/v2/phone-pairings`, `/v2/phone-grants`).
mod support;

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use serde_json::json;
use shellx_core::Core;
use support::requests_to;

const KEY: [u8; 32] = [7u8; 32];

fn registered() -> (Core, shellx_fake_api::FakeApi, support::Dir, String) {
    let (core, fake, dir) = support::logged_in();
    let m = core
        .call("machines.register", json!({"name": "Mac A", "platform": "macos", "os_version": "15", "app_version": "2.0.0"}))
        .unwrap();
    let id = m["machine_id"].as_str().unwrap().to_string();
    (core, fake, dir, id)
}

#[test]
fn phones_pending_lists_target_requests() {
    let (core, fake, _dir, machine) = registered();
    assert_eq!(core.call("phones.pending", json!({})).unwrap(), json!({"pairings": []}));
    let id = fake.add_phone_pairing(&machine, "Phu's iPhone", "ios", KEY);
    let out = core.call("phones.pending", json!({})).unwrap();
    let items = out["pairings"].as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["pairing_id"], json!(id));
    assert_eq!(items[0]["device_name"], "Phu's iPhone");
    assert_eq!(items[0]["platform"], "ios");
    assert_eq!(items[0]["client_key_b64"], STANDARD.encode(KEY));
    assert!(items[0]["proof_b64"].as_str().is_some_and(|p| !p.is_empty()));
    assert!(items[0]["created_at_unix"].as_u64().unwrap() > 0);
    let get = requests_to(&fake, "/v2/phone-pairings").into_iter().find(|r| r.method == "GET").unwrap();
    assert_eq!(get.query, "role=target");
}

#[test]
fn phones_approve_then_grants_lists_phone() {
    let (core, fake, _dir, machine) = registered();
    let id = fake.add_phone_pairing(&machine, "Phu's iPhone", "ios", KEY);
    assert_eq!(core.call("phones.grants", json!({})).unwrap(), json!({"grants": []}));
    assert_eq!(core.call("phones.approve", json!({"pairing_id": id})).unwrap(), json!({}));
    assert!(fake.has_phone_grant(&machine, KEY));
    assert_eq!(core.call("phones.pending", json!({})).unwrap(), json!({"pairings": []}));
    let out = core.call("phones.grants", json!({})).unwrap();
    let g = &out["grants"][0];
    assert!(g["grant_id"].as_str().is_some_and(|s| !s.is_empty()));
    assert!(g["device_id"].as_str().is_some_and(|s| !s.is_empty()));
    assert_eq!(g["device_name"], "Phu's iPhone");
    assert_eq!(g["platform"], "ios");
    assert_eq!(g["client_key_b64"], STANDARD.encode(KEY));
    assert!(g["created_at_unix"].as_u64().unwrap() > 0);
    assert!(g["last_seen_unix"].is_null());
}

#[test]
fn phones_deny_marks_request_denied() {
    let (core, fake, _dir, machine) = registered();
    let id = fake.add_phone_pairing(&machine, "Phone", "ios", KEY);
    assert_eq!(core.call("phones.deny", json!({"pairing_id": id})).unwrap(), json!({}));
    assert!(!fake.has_phone_grant(&machine, KEY));
    assert_eq!(core.call("phones.pending", json!({})).unwrap(), json!({"pairings": []}));
    assert_eq!(core.call("phones.approve", json!({"pairing_id": id})).unwrap_err().code, "pairing_not_pending");
}

#[test]
fn phones_revoke_removes_grant() {
    let (core, fake, _dir, machine) = registered();
    let id = fake.add_phone_pairing(&machine, "Phone", "ios", KEY);
    core.call("phones.approve", json!({"pairing_id": id})).unwrap();
    let grants = core.call("phones.grants", json!({})).unwrap();
    let gid = grants["grants"][0]["grant_id"].as_str().unwrap().to_string();
    assert_eq!(core.call("phones.revoke", json!({"grant_id": gid})).unwrap(), json!({}));
    assert!(!fake.has_phone_grant(&machine, KEY));
    assert_eq!(core.call("phones.grants", json!({})).unwrap(), json!({"grants": []}));
    // Unknown grant: the server's generic not_found passes through.
    assert_eq!(core.call("phones.revoke", json!({"grant_id": gid})).unwrap_err().code, "not_found");
}

#[test]
fn phones_require_login() {
    let (core, fake, _dir) = support::logged_out();
    for (m, p) in [
        ("phones.pending", json!({})),
        ("phones.approve", json!({"pairing_id": "p1"})),
        ("phones.deny", json!({"pairing_id": "p1"})),
        ("phones.grants", json!({})),
        ("phones.revoke", json!({"grant_id": "g1"})),
    ] {
        assert_eq!(core.call(m, p).unwrap_err().code, "not_logged_in", "{m}");
    }
    assert!(fake.requests().is_empty());
}

#[test]
fn phones_require_a_registered_machine() {
    let (core, _fake, _dir) = support::logged_in();
    for (m, p) in [
        ("phones.pending", json!({})),
        ("phones.approve", json!({"pairing_id": "p1"})),
        ("phones.deny", json!({"pairing_id": "p1"})),
        ("phones.grants", json!({})),
        ("phones.revoke", json!({"grant_id": "g1"})),
    ] {
        assert_eq!(core.call(m, p).unwrap_err().code, "not_registered", "{m}");
    }
}

#[test]
fn phones_approve_expired_passes_server_code() {
    let (core, fake, _dir, machine) = registered();
    let id = fake.add_phone_pairing(&machine, "Phone", "ios", KEY);
    fake.expire_phone_pairing(&id);
    assert_eq!(core.call("phones.approve", json!({"pairing_id": id})).unwrap_err().code, "pairing_expired");
    assert!(!fake.has_phone_grant(&machine, KEY));
}

#[test]
fn phones_ids_must_be_path_safe_and_never_reach_the_server() {
    let (core, fake, _dir, _machine) = registered();
    for bad in ["", "../x", "a/b", "a?b", &"a".repeat(129)] {
        assert_eq!(core.call("phones.approve", json!({"pairing_id": bad})).unwrap_err().code, "invalid_params");
        assert_eq!(core.call("phones.deny", json!({"pairing_id": bad})).unwrap_err().code, "invalid_params");
        assert_eq!(core.call("phones.revoke", json!({"grant_id": bad})).unwrap_err().code, "invalid_params");
    }
    assert_eq!(core.call("phones.approve", json!({})).unwrap_err().code, "invalid_params");
    assert!(requests_to(&fake, "/v2/phone-grants").is_empty());
    assert!(requests_to(&fake, "/v2/phone-pairings").is_empty());
}
