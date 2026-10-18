mod support;

use serde_json::json;
use shellx_core::Core;
use shellx_core::store::StateStore;
use support::{header, requests_to};

#[test]
fn login_stores_token_and_never_returns_it() {
    let (core, fake, dir) = support::logged_out(); // config.set pointing at FakeApi
    let r = core.call("auth.login", json!({"email":"a@b.c","password":"pw"})).unwrap();
    assert!(r.get("token").is_none());
    assert_eq!(r["fingerprint"].as_str().unwrap().len(), 16);
    assert!(r["fingerprint"].as_str().unwrap().bytes().all(|c| matches!(c, b'0'..=b'9' | b'a'..=b'f')));
    assert!(r["user_id"].as_str().is_some_and(|s| !s.is_empty()));
    assert!(r["device_id"].as_str().is_some_and(|s| !s.is_empty()));
    let req = &fake.requests()[0];
    assert_eq!(req.method, "POST");
    assert_eq!(req.path, "/v1/auth/login");
    assert_eq!(req.body["email"], "a@b.c");
    assert_eq!(req.body["device"]["kind"], "desktop");
    assert_eq!(req.body["device"]["platform"], "macos");
    assert!(req.body["device"]["name"].as_str().is_some_and(|s| !s.trim().is_empty()));
    assert_eq!(req.body["device"]["public_key"], r["device_public_key_b64"]);
    #[cfg(unix)]
    {
        assert_eq!(support::mode(dir.join("session.json")), 0o600);
        assert_eq!(support::mode(dir.join("device.key")), 0o600);
    }
    assert!(dir.join("session.json").exists());
    let token = fake.issued_token();
    assert!(!token.is_empty());
    assert!(!format!("{r:?}").contains(&token));
    assert!(!r.to_string().contains(&token));
}

#[test]
fn fingerprint_is_sha256_prefix_of_the_device_public_key() {
    use base64::Engine;
    let (core, _fake, _dir) = support::logged_out();
    let r = core.call("auth.login", json!({"email":"a@b.c","password":"pw"})).unwrap();
    let pk = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(r["device_public_key_b64"].as_str().unwrap())
        .unwrap();
    let pk: [u8; 32] = pk.try_into().unwrap();
    assert_eq!(r["fingerprint"].as_str().unwrap(), shellx_core::fingerprint::fingerprint(&pk));
    // Known answer: SHA-256 of 32 zero bytes starts 66687aadf862bd77.
    assert_eq!(shellx_core::fingerprint::fingerprint(&[0u8; 32]), "66687aadf862bd77");
}

#[test]
fn login_uses_device_name_when_configured() {
    let (core, fake, _dir) = support::logged_out_with(json!({"device_name": "Phu's Mac"}));
    core.call("auth.login", json!({"email":"a@b.c","password":"pw"})).unwrap();
    assert_eq!(fake.requests()[0].body["device"]["name"], "Phu's Mac");
}

#[test]
fn login_requires_email_and_password_strings() {
    let (core, fake, dir) = support::logged_out();
    for p in [json!({}), json!({"email":"a@b.c"}), json!({"email":1,"password":"pw"}), json!({"email":"a@b.c","password":null})] {
        assert_eq!(core.call("auth.login", p.clone()).unwrap_err().code, "invalid_params", "{p}");
    }
    assert!(fake.requests().is_empty());
    assert!(!dir.join("session.json").exists());
}

#[test]
fn wrong_password_passes_server_code() {
    let (core, _fake, dir) = support::logged_out();
    let e = core.call("auth.login", json!({"email":"a@b.c","password":"nope"})).unwrap_err();
    assert_eq!(e.code, "invalid_credentials");
    assert!(!e.message.contains("nope"));
    assert!(!dir.join("session.json").exists());
}

#[test]
fn every_request_sends_platform_headers() {
    let (core, fake, _dir) =
        support::logged_out_with(json!({"app_version":"2.0.0","os_version":"15.5","platform":"macos"}));
    core.call("version.check", json!({})).unwrap();
    core.call("auth.login", json!({"email":"a@b.c","password":"pw"})).unwrap();
    for path in ["/v1/version", "/v1/auth/login"] {
        let reqs = requests_to(&fake, path);
        assert_eq!(reqs.len(), 1, "{path}");
        let r = &reqs[0];
        assert_eq!(header(r, "X-ShellX-Version"), Some("2.0.0"), "{path}");
        assert_eq!(header(r, "X-ShellX-Platform"), Some("macos"), "{path}");
        assert_eq!(header(r, "X-ShellX-OS-Version"), Some("15.5"), "{path}");
        assert_eq!(header(r, "User-Agent"), Some("ShellX/2.0.0 (macos)"), "{path}");
    }
}

#[test]
fn os_version_header_is_omitted_when_unknown() {
    let (core, fake, _dir) = support::logged_out_with(json!({"app_version":"2.1.0","platform":"windows"}));
    core.call("version.check", json!({})).unwrap();
    let r = &fake.requests()[0];
    assert_eq!(header(r, "X-ShellX-OS-Version"), None);
    assert_eq!(header(r, "X-ShellX-Platform"), Some("windows"));
    assert_eq!(header(r, "User-Agent"), Some("ShellX/2.1.0 (windows)"));
}

#[test]
fn bearer_only_after_login() {
    let (core, fake, _dir) = support::logged_out();
    core.call("version.check", json!({})).unwrap();
    core.call("auth.login", json!({"email":"a@b.c","password":"pw"})).unwrap();
    core.call("version.check", json!({})).unwrap();
    let reqs = fake.requests();
    assert_eq!(reqs.len(), 3);
    assert_eq!(header(&reqs[0], "Authorization"), None);
    assert_eq!(header(&reqs[1], "Authorization"), None);
    let want = format!("Bearer {}", fake.issued_token());
    assert_eq!(header(&reqs[2], "Authorization"), Some(want.as_str()));
}

#[test]
fn device_key_is_stable_across_logins() {
    let (core, _fake, _dir) = support::logged_out();
    let a = core.call("auth.login", json!({"email":"a@b.c","password":"pw"})).unwrap();
    let b = core.call("auth.login", json!({"email":"a@b.c","password":"pw"})).unwrap();
    assert_eq!(a["device_public_key_b64"], b["device_public_key_b64"]);
    assert_eq!(a["fingerprint"], b["fingerprint"]);
    assert_eq!(a["device_id"], b["device_id"]);
    assert_eq!(a["device_public_key_b64"].as_str().unwrap().len(), 43);
}

#[test]
fn device_key_survives_logout_and_a_new_core() {
    let (core, fake, dir) = support::logged_out();
    let a = core.call("auth.login", json!({"email":"a@b.c","password":"pw"})).unwrap();
    core.call("auth.logout", json!({})).unwrap();
    let core2 = Core::new();
    support::configure(&core2, &fake.base_url, &dir, json!({}));
    let b = core2.call("auth.login", json!({"email":"a@b.c","password":"pw"})).unwrap();
    assert_eq!(a["device_public_key_b64"], b["device_public_key_b64"]);
}

#[test]
fn logout_online_revokes_token_and_forgets_session() {
    let (core, fake, dir) = support::logged_in();
    let token = fake.issued_token();
    StateStore::open(&dir).unwrap().write_secret("machine.json", br#"{"machine_id":"m","slot":"s"}"#).unwrap();
    assert_eq!(core.call("auth.logout", json!({})).unwrap(), json!({}));
    let reqs = requests_to(&fake, "/v1/auth/logout");
    assert_eq!(reqs.len(), 1);
    assert_eq!(reqs[0].method, "POST");
    let want = format!("Bearer {token}");
    assert_eq!(header(&reqs[0], "Authorization"), Some(want.as_str()));
    assert!(!fake.token_is_live(&token));
    assert!(!dir.join("session.json").exists());
    assert!(!dir.join("machine.json").exists());
    assert!(dir.join("device.key").exists());
    // Later requests carry no bearer.
    core.call("version.check", json!({})).unwrap();
    assert_eq!(header(fake.requests().last().unwrap(), "Authorization"), None);
}

#[test]
fn logout_works_offline_and_forgets_session() {
    let (core, fake, dir) = support::logged_in();
    StateStore::open(&dir).unwrap().write_secret("machine.json", br#"{"machine_id":"m","slot":"s"}"#).unwrap();
    // After stop() the listener is closed, but the client's pooled keep-alive socket
    // may still be held by a tiny_http connection thread that never answers: this
    // exercises the 2 s logout timeout as well as "connection refused".
    fake.stop();
    let t = std::time::Instant::now();
    assert_eq!(core.call("auth.logout", json!({})).unwrap(), json!({}));
    assert!(t.elapsed() < std::time::Duration::from_secs(5), "logout took {:?}", t.elapsed());
    assert!(!dir.join("session.json").exists());
    assert!(!dir.join("machine.json").exists());
    assert_eq!(core.call("machines.list", json!({})).unwrap_err().code, "not_logged_in");
}

#[test]
fn logout_without_session_is_ok_and_sends_nothing() {
    let (core, fake, _dir) = support::logged_out();
    assert_eq!(core.call("auth.logout", json!({})).unwrap(), json!({}));
    assert!(fake.requests().is_empty());
}

#[test]
fn unreachable_server_is_network_error() {
    let dir = support::state_dir();
    let core = Core::new();
    support::configure(&core, "http://127.0.0.1:1", &dir, json!({}));
    let e = core.call("auth.login", json!({"email":"a@b.c","password":"pw"})).unwrap_err();
    assert_eq!(e.code, "network");
    assert!(!e.message.contains("pw\""));
    assert_eq!(core.call("version.check", json!({})).unwrap_err().code, "network");
    assert!(!dir.join("session.json").exists());
}

#[test]
fn session_methods_need_login_then_reach_dispatch() {
    let (core, _fake, _dir) = support::logged_out();
    for m in ["machines.list", "machines.register", "tickets.mint", "pair.pending"] {
        assert_eq!(core.call(m, json!({})).unwrap_err().code, "not_logged_in", "{m}");
    }
}

#[test]
fn state_dir_change_reopens_the_store() {
    let (core, fake, dir_a) = support::logged_in();
    let dir_b = support::state_dir();
    support::configure(&core, &fake.base_url, &dir_b, json!({}));
    assert_eq!(core.call("machines.list", json!({})).unwrap_err().code, "not_logged_in");
    core.call("auth.login", json!({"email":"a@b.c","password":"pw"})).unwrap();
    assert!(dir_a.join("session.json").exists());
    assert!(dir_b.join("session.json").exists());
    assert_ne!(
        std::fs::read(dir_a.join("device.key")).unwrap(),
        std::fs::read(dir_b.join("device.key")).unwrap()
    );
}
