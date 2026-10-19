mod support;

use base64::Engine;
use serde_json::{Value, json};
use shellx_core::Core;
use shellx_core::store::StateStore;
use shellx_fake_api::FakeApi;
use support::{Dir, requests_to};

fn reg_params() -> Value {
    json!({"name":"Mac A","platform":"macos","os_version":"15.5","app_version":"2.0.0"})
}

fn now() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs()
}

fn login(core: &Core) -> Value {
    core.call("auth.login", json!({"email":"a@b.c","password":"pw"})).unwrap()
}

#[test]
fn register_then_heartbeat_uses_stored_id() {
    let (core, fake, dir) = support::logged_in();
    let r = core.call("machines.register", reg_params()).unwrap();
    assert!(r["machine_id"].as_str().is_some_and(|s| !s.is_empty()));
    assert!(r["slot"].as_str().is_some_and(|s| !s.is_empty()));
    assert!(dir.join("machine.json").exists());
    #[cfg(unix)]
    assert_eq!(support::mode(dir.join("machine.json")), 0o600);
    assert_eq!(core.call("machines.heartbeat", json!({})).unwrap(), json!({}));
    let last = fake.requests().last().unwrap().clone();
    assert_eq!(last.method, "POST");
    assert_eq!(last.path, format!("/v2/machines/{}/heartbeat", r["machine_id"].as_str().unwrap()));
    let want = format!("Bearer {}", fake.issued_token());
    assert_eq!(support::header(&last, "Authorization"), Some(want.as_str()));
}

#[test]
fn register_defaults_key_to_device_key() {
    let (core, fake, _dir) = support::logged_out();
    let l = login(&core);
    core.call("machines.register", reg_params()).unwrap();
    let body = &requests_to(&fake, "/v2/machines")[0].body;
    assert_eq!(body["noise_public_key_b64"], l["device_public_key_b64"]);
    assert_eq!(body["name"], "Mac A");
    assert_eq!(body["platform"], "macos");
    assert_eq!(body["os_version"], "15.5");
    assert_eq!(body["app_version"], "2.0.0");
}

#[test]
fn register_uses_explicit_key_when_given() {
    let (core, fake, _dir) = support::logged_in();
    let key = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode([7u8; 32]);
    let mut p = reg_params();
    p["noise_public_key_b64"] = json!(key);
    core.call("machines.register", p).unwrap();
    assert_eq!(requests_to(&fake, "/v2/machines")[0].body["noise_public_key_b64"], json!(key));
}

#[test]
fn register_validates_params() {
    let (core, fake, _dir) = support::logged_in();
    for p in [
        json!({}),
        json!({"name":"","platform":"macos","os_version":"1","app_version":"1"}),
        json!({"name":"x","platform":5,"os_version":"1","app_version":"1"}),
        json!({"name":"x","platform":"macos","os_version":"1"}),
        json!({"name":"x","platform":"macos","os_version":"1","app_version":"1","noise_public_key_b64":5}),
    ] {
        assert_eq!(core.call("machines.register", p.clone()).unwrap_err().code, "invalid_params", "{p}");
    }
    assert!(requests_to(&fake, "/v2/machines").is_empty());
}

#[test]
fn heartbeat_without_machine_is_not_registered_and_sends_nothing() {
    let (core, fake, _dir) = support::logged_in();
    assert_eq!(core.call("machines.heartbeat", json!({})).unwrap_err().code, "not_registered");
    assert!(fake.requests().iter().all(|r| !r.path.starts_with("/v2/")));
}

fn two_machines() -> (Core, FakeApi, Dir, Value, String) {
    let (core, fake, dir) = support::logged_in();
    let mine = core.call("machines.register", reg_params()).unwrap();
    // A second device of the same account (own state dir) registers another machine.
    let other = Core::new();
    let dir_b = support::state_dir();
    support::configure(&other, &fake.base_url, &dir_b, json!({}));
    other.call("auth.login", json!({"email":"a@b.c","password":"pw"})).unwrap();
    let o = other
        .call("machines.register", json!({"name":"Win B","platform":"windows","os_version":"11","app_version":"2.0.0"}))
        .unwrap();
    std::mem::forget(dir_b); // keep the other state dir alive for the test's duration
    (core, fake, dir, mine, o["machine_id"].as_str().unwrap().to_string())
}

#[test]
fn list_marks_this_machine_and_offline_after_90s() {
    let (core, fake, _dir, mine, other_id) = two_machines();
    let mine_id = mine["machine_id"].as_str().unwrap().to_string();
    core.call("machines.heartbeat", json!({})).unwrap();
    fake.set_last_heartbeat(&other_id, now() - 100);
    let r = core.call("machines.list", json!({})).unwrap();
    let list = r["machines"].as_array().unwrap();
    assert_eq!(list.len(), 2);
    let m = list.iter().find(|m| m["machine_id"] == json!(mine_id)).unwrap();
    let o = list.iter().find(|m| m["machine_id"] == json!(other_id)).unwrap();
    assert_eq!(m["is_this_machine"], true);
    assert_eq!(o["is_this_machine"], false);
    assert_eq!(m["online"], true);
    assert_eq!(o["online"], false);
    assert_eq!(m["name"], "Mac A");
    assert_eq!(o["platform"], "windows");
    assert!(m["last_seen_unix"].as_u64().unwrap() >= now() - 5);
    assert_eq!(o["last_seen_unix"].as_u64().unwrap(), now() - 100);
    assert_eq!(m["fingerprint"].as_str().unwrap().len(), 16);
    fake.set_last_heartbeat(&other_id, now() - 80);
    let r = core.call("machines.list", json!({})).unwrap();
    let o = r["machines"].as_array().unwrap().iter().find(|m| m["machine_id"] == json!(other_id)).unwrap().clone();
    assert_eq!(o["online"], true);
}

#[test]
fn list_fingerprint_of_this_machine_matches_login_fingerprint() {
    let (core, _fake, _dir) = support::logged_out();
    let l = login(&core);
    core.call("machines.register", reg_params()).unwrap();
    let r = core.call("machines.list", json!({})).unwrap();
    assert_eq!(r["machines"][0]["fingerprint"], l["fingerprint"]);
}

#[test]
fn list_without_a_registered_machine_has_no_this_machine() {
    let (core, fake, _dir, _mine, _o) = two_machines();
    let fresh = Core::new();
    let d = support::state_dir();
    support::configure(&fresh, &fake.base_url, &d, json!({}));
    fresh.call("auth.login", json!({"email":"a@b.c","password":"pw"})).unwrap();
    let r = fresh.call("machines.list", json!({})).unwrap();
    assert!(r["machines"].as_array().unwrap().iter().all(|m| m["is_this_machine"] == false));
    let _ = core;
}

#[test]
fn list_requires_valid_session_on_server() {
    let (core, fake, dir) = support::logged_in();
    // Server forgets the token: the server's code passes through.
    let token = fake.issued_token();
    fake.revoke_token(&token);
    let e = core.call("machines.list", json!({})).unwrap_err();
    assert_eq!(e.code, "unauthorized");
    assert!(!e.message.contains(&token));
    let _ = dir;
}

#[test]
fn login_as_another_user_drops_machine_json() {
    let (core, _fake, dir) = support::logged_in();
    core.call("machines.register", reg_params()).unwrap();
    assert!(dir.join("machine.json").exists());
    // Same user again: the machine stays.
    login(&core);
    assert!(dir.join("machine.json").exists());
    core.call("auth.login", json!({"email":"other@b.c","password":"pw"})).unwrap();
    assert!(!dir.join("machine.json").exists());
    assert_eq!(core.call("machines.heartbeat", json!({})).unwrap_err().code, "not_registered");
    let _ = StateStore::open(&dir);
}
