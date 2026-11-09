//! Google sign-in through the loopback flow against the fake relay and fake Google.
mod support;

use serde_json::{Value, json};
use shellx_core::auth_google::FAILED_PAGE;

const REG: fn() -> Value = || json!({"name":"Mac A","platform":"macos","os_version":"15","app_version":"2.0.0"});

fn session_json(dir: &std::path::Path) -> Value {
    serde_json::from_slice(&std::fs::read(dir.join("session.json")).unwrap()).unwrap()
}

fn redirect_of(auth_url: &str) -> String {
    support::query(auth_url)["redirect_uri"].clone()
}

fn port_of(redirect: &str) -> u16 {
    redirect.strip_prefix("http://127.0.0.1:").unwrap().strip_suffix("/oauth2/callback").unwrap().parse().unwrap()
}

#[test]
fn begin_returns_a_google_url_with_pkce_state_and_the_relay_nonce() {
    let (core, fake, _dir) = support::google_logged_out();
    let r = core.call("auth.google.begin", json!({"purpose": "sign_in"})).unwrap();
    assert_eq!(r["flow_id"].as_str().unwrap().len(), 22);
    let url = r["auth_url"].as_str().unwrap();
    assert!(url.starts_with(&format!("{}/fake-google/auth?client_id=fake-desktop-client&redirect_uri=", fake.base_url)));
    let q = support::query(url);
    assert_eq!((q["response_type"].as_str(), q["scope"].as_str()), ("code", "openid email profile"));
    assert_eq!((q["code_challenge_method"].as_str(), q["prompt"].as_str()), ("S256", "select_account"));
    assert_eq!((q["code_challenge"].len(), q["state"].len()), (43, 43));
    assert_eq!(q["nonce"], fake.issued_nonces()[0]);
    let port = q["redirect_uri"].strip_prefix("http://127.0.0.1:").unwrap().strip_suffix("/oauth2/callback").unwrap();
    assert!(port.parse::<u16>().unwrap() > 0);
    let nonce = &support::requests_to(&fake, "/v1/auth/nonce")[0];
    assert_eq!((nonce.method.as_str(), support::header(nonce, "Authorization")), ("POST", None));
}

#[test]
fn default_google_endpoints_are_googles() {
    let cfg = shellx_core::Config::from_params(&json!({"api_base":"https://a.b","state_dir":"/tmp/sx"})).unwrap();
    assert_eq!(cfg.google_auth_url, "https://accounts.google.com/o/oauth2/v2/auth");
    assert_eq!(cfg.google_token_url, "https://oauth2.googleapis.com/token");
}

#[test]
fn begin_requires_a_known_purpose_and_a_client_id() {
    let (core, fake, _dir) = support::google_logged_out();
    for p in [json!({"purpose": "x"}), json!({}), json!("sign_in")] {
        assert_eq!(core.call("auth.google.begin", p).unwrap_err().code, "invalid_params");
    }
    assert!(fake.requests().is_empty());
    let fake = support::fake();
    let dir = support::state_dir();
    let core = shellx_core::Core::new();
    let mut extra = support::google(&fake);
    extra["google_client_id"] = json!("");
    support::configure(&core, &fake.base_url, &dir, extra);
    assert_eq!(core.call("auth.google.begin", json!({"purpose": "sign_in"})).unwrap_err().code, "not_configured");
    assert!(fake.requests().is_empty());
}

#[test]
fn link_needs_a_session() {
    let (core, fake, _dir) = support::google_logged_out();
    assert_eq!(core.call("auth.google.begin", json!({"purpose": "link"})).unwrap_err().code, "not_logged_in");
    assert!(fake.requests().is_empty());
}

#[test]
fn google_urls_must_be_https_off_loopback() {
    let (core, _fake, dir) = support::google_logged_out();
    let p = json!({"api_base": "https://a.b", "state_dir": dir.to_str().unwrap(), "google_token_url": "http://evil.example/token"});
    assert_eq!(core.call("config.set", p).unwrap_err().code, "invalid_params");
}

#[test]
fn config_debug_hides_the_google_client_secret() {
    let cfg = shellx_core::Config::from_params(&json!({
        "api_base": "https://a.b", "state_dir": "/tmp/sx", "google_client_secret": "fake-desktop-secret"
    }))
    .unwrap();
    assert!(!format!("{cfg:?}").contains("fake-desktop-secret"));
    assert_eq!(cfg.google_client_secret, "fake-desktop-secret");
}


#[test]
fn google_sign_in_through_the_browser_writes_a_google_session() {
    let (core, fake, dir) = support::google_logged_out();
    let r = support::google_sign_in(&core, "sign_in").unwrap();
    assert_eq!((r["email"].as_str(), r["auth_method"].as_str()), (Some("google-user@shellx.test"), Some("google")));
    for k in ["user_id", "device_id", "device_public_key_b64", "fingerprint"] {
        assert!(r[k].as_str().is_some_and(|s| !s.is_empty()), "{k}");
    }
    assert!(r.get("token").is_none());
    let s = session_json(&dir);
    assert_eq!((s["auth_method"].as_str(), s["email"].as_str()), (Some("google"), Some("google-user@shellx.test")));
    assert_eq!(fake.token_auth_method(&fake.issued_token()).as_deref(), Some("google"));
    let t = &support::requests_to(&fake, "/fake-google/token")[0];
    assert_eq!(t.form["grant_type"], "authorization_code");
    assert_eq!(t.form["client_secret"], "fake-desktop-secret");
    assert_eq!(t.form["code_verifier"].len(), 43);
    assert!(t.form["code"].starts_with("4/"));
    assert_eq!(support::header(t, "Authorization"), None);
    let g = &support::requests_to(&fake, "/v1/auth/google")[0];
    assert_eq!(g.body["device"]["kind"], "desktop");
    assert_eq!(g.body["nonce"], json!(fake.issued_nonces()[0]));
    assert_eq!(support::header(g, "Authorization"), None);
    assert_eq!(core.call("machines.list", json!({})).unwrap()["machines"], json!([]));
}

#[test]
fn the_loopback_closes_after_the_callback() {
    let (core, _fake, _dir) = support::google_logged_out();
    let begun = core.call("auth.google.begin", json!({"purpose": "sign_in"})).unwrap();
    let url = begun["auth_url"].as_str().unwrap().to_string();
    let port = port_of(&redirect_of(&url));
    let browser = std::thread::spawn(move || shellx_fake_api::browse(&url));
    core.call("auth.google.finish", json!({"flow_id": begun["flow_id"]})).unwrap();
    let _ = browser.join();
    assert!(std::net::TcpStream::connect(("127.0.0.1", port)).is_err());
}

#[test]
fn a_wrong_state_is_google_state_mismatch() {
    let (core, fake, dir) = support::google_logged_out();
    let begun = core.call("auth.google.begin", json!({"purpose": "sign_in"})).unwrap();
    let redirect = redirect_of(begun["auth_url"].as_str().unwrap());
    let url = format!("{redirect}?code=4%2Fx&state=wrong");
    let browser = std::thread::spawn(move || shellx_fake_api::browse(&url));
    let e = core.call("auth.google.finish", json!({"flow_id": begun["flow_id"]})).unwrap_err();
    assert_eq!(e.code, "google_state_mismatch");
    let (status, body) = browser.join().unwrap().unwrap();
    assert_eq!(status, 200);
    assert_eq!(body, FAILED_PAGE);
    assert!(support::requests_to(&fake, "/fake-google/token").is_empty());
    assert!(!dir.join("session.json").exists());
}

#[test]
fn the_browser_error_is_google_cancelled() {
    let (core, _fake, _dir) = support::google_logged_out();
    let begun = core.call("auth.google.begin", json!({"purpose": "sign_in"})).unwrap();
    let q = support::query(begun["auth_url"].as_str().unwrap());
    let url = format!("{}?error=access_denied&state={}", q["redirect_uri"], q["state"]);
    let browser = std::thread::spawn(move || shellx_fake_api::browse(&url));
    let e = core.call("auth.google.finish", json!({"flow_id": begun["flow_id"]})).unwrap_err();
    assert_eq!(e.code, "google_cancelled");
    let _ = browser.join();
}

#[test]
fn cancel_ends_a_waiting_finish() {
    let (core, _fake, _dir) = support::google_logged_out();
    let begun = core.call("auth.google.begin", json!({"purpose": "sign_in"})).unwrap();
    let id = begun["flow_id"].clone();
    std::thread::scope(|s| {
        let waiter = s.spawn(|| {
            let t = std::time::Instant::now();
            (core.call("auth.google.finish", json!({"flow_id": id})), t)
        });
        std::thread::sleep(std::time::Duration::from_millis(200));
        assert_eq!(core.call("auth.google.cancel", json!({"flow_id": id})).unwrap(), json!({}));
        let (res, t) = waiter.join().unwrap();
        assert_eq!(res.unwrap_err().code, "google_cancelled");
        assert!(t.elapsed() < std::time::Duration::from_secs(2));
    });
}

#[test]
fn cancel_before_finish_is_google_cancelled() {
    let (core, _fake, _dir) = support::google_logged_out();
    let begun = core.call("auth.google.begin", json!({"purpose": "sign_in"})).unwrap();
    assert_eq!(core.call("auth.google.cancel", json!({"flow_id": begun["flow_id"]})).unwrap(), json!({}));
    assert_eq!(core.call("auth.google.finish", json!({"flow_id": begun["flow_id"]})).unwrap_err().code, "google_cancelled");
    assert_eq!(core.call("auth.google.cancel", json!({"flow_id": "unknown"})).unwrap(), json!({}));
    assert_eq!(core.call("auth.google.cancel", json!({})).unwrap_err().code, "invalid_params");
}

#[test]
fn waiting_past_the_deadline_is_google_timeout() {
    let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    l.set_nonblocking(true).unwrap();
    let t = std::time::Instant::now();
    let e = shellx_core::auth_google::wait_for_callback(
        &l,
        "s",
        t + std::time::Duration::from_millis(200),
        &std::sync::atomic::AtomicBool::new(false),
    )
    .unwrap_err();
    assert_eq!(e.code, "google_timeout");
    assert!(t.elapsed() >= std::time::Duration::from_millis(200) && t.elapsed() < std::time::Duration::from_secs(2));
}

#[test]
fn a_second_begin_cancels_the_first_flow() {
    let (core, _fake, _dir) = support::google_logged_out();
    let a = core.call("auth.google.begin", json!({"purpose": "sign_in"})).unwrap();
    let port_a = port_of(&redirect_of(a["auth_url"].as_str().unwrap()));
    let _b = core.call("auth.google.begin", json!({"purpose": "sign_in"})).unwrap();
    assert!(std::net::TcpStream::connect(("127.0.0.1", port_a)).is_err());
    assert_eq!(core.call("auth.google.finish", json!({"flow_id": a["flow_id"]})).unwrap_err().code, "google_cancelled");
    // the second flow still signs in
    let r = support::google_sign_in(&core, "sign_in").unwrap();
    assert_eq!(r["auth_method"], "google");
}

#[test]
fn a_failed_token_exchange_is_invalid_credentials() {
    let fake = support::fake();
    let dir = support::state_dir();
    let core = shellx_core::Core::new();
    let mut extra = support::google(&fake);
    extra["google_client_secret"] = json!("wrong");
    support::configure(&core, &fake.base_url, &dir, extra);
    let e = support::google_sign_in(&core, "sign_in").unwrap_err();
    assert_eq!(e.code, "invalid_credentials");
    assert!(!dir.join("session.json").exists());
}

#[test]
fn a_password_account_email_answers_switch_from_signed_in_device() {
    let (core, _fake, dir) = support::google_logged_out();
    core.call("auth.login", json!({"email": "google-user@shellx.test", "password": "pw"})).unwrap();
    let e = support::google_sign_in(&core, "sign_in").unwrap_err();
    assert_eq!(e.code, "switch_from_signed_in_device");
    assert_eq!(session_json(&dir)["auth_method"], "password");
}

#[test]
fn link_switches_the_password_session_to_google_and_keeps_the_machine() {
    let (core, fake, dir) = support::google_logged_out();
    let login = core.call("auth.login", json!({"email": "old@shellx.test", "password": "pw"})).unwrap();
    core.call("machines.register", REG()).unwrap();
    let old = fake.issued_token();
    let r = support::google_sign_in(&core, "link").unwrap();
    assert_eq!((&r["user_id"], &r["device_id"]), (&login["user_id"], &login["device_id"]));
    assert_eq!((r["email"].as_str(), r["auth_method"].as_str()), (Some("google-user@shellx.test"), Some("google")));
    assert!(!fake.token_is_live(&old));
    assert!(dir.join("machine.json").exists());
    let l = &support::requests_to(&fake, "/v1/auth/google/link")[0];
    assert_eq!(support::header(l, "Authorization"), Some(format!("Bearer {old}").as_str()));
    assert_eq!(core.call("machines.list", json!({})).unwrap()["machines"].as_array().unwrap().len(), 1);
}

#[test]
fn link_conflicts_pass_email_in_use_and_identity_in_use() {
    let (core, fake, dir) = support::google_logged_out();
    core.call("auth.login", json!({"email": "google-user@shellx.test", "password": "pw"})).unwrap();
    core.call("auth.login", json!({"email": "b@shellx.test", "password": "pw"})).unwrap();
    let e = support::google_sign_in(&core, "link").unwrap_err();
    assert_eq!(e.code, "email_in_use");
    assert_eq!(session_json(&dir)["auth_method"], "password");
    fake.set_google_account("x@shellx.test", "sub-x");
    core.call("auth.logout", json!({})).unwrap();
    support::google_sign_in(&core, "sign_in").unwrap();
    core.call("auth.logout", json!({})).unwrap();
    core.call("auth.login", json!({"email": "c@shellx.test", "password": "pw"})).unwrap();
    let e = support::google_sign_in(&core, "link").unwrap_err();
    assert_eq!(e.code, "identity_in_use");
}

#[test]
fn a_refused_link_forgets_the_session_but_keeps_machine_and_key() {
    let (core, fake, dir) = support::google_logged_out();
    core.call("auth.login", json!({"email": "old@shellx.test", "password": "pw"})).unwrap();
    core.call("machines.register", REG()).unwrap();
    fake.revoke_token(&fake.issued_token());
    let e = support::google_sign_in(&core, "link").unwrap_err();
    assert_eq!(e.code, "unauthorized");
    assert!(!dir.join("session.json").exists());
    assert!(dir.join("machine.json").exists() && dir.join("device.key").exists());
}

#[test]
fn google_sign_in_after_a_401_keeps_the_device_id_and_machine() {
    let (core, fake, dir) = support::google_logged_out();
    let first = support::google_sign_in(&core, "sign_in").unwrap();
    core.call("machines.register", REG()).unwrap();
    fake.revoke_token(&fake.issued_token());
    assert_eq!(core.call("machines.list", json!({})).unwrap_err().code, "unauthorized");
    assert!(dir.join("machine.json").exists() && dir.join("device.key").exists());
    let second = support::google_sign_in(&core, "sign_in").unwrap();
    assert_eq!((&second["user_id"], &second["device_id"]), (&first["user_id"], &first["device_id"]));
    let list = core.call("machines.list", json!({})).unwrap();
    assert_eq!(list["machines"][0]["is_this_machine"], true);
}

#[test]
fn google_secrets_never_reach_results_or_errors() {
    let (core, fake, _dir) = support::google_logged_out();
    let begun = core.call("auth.google.begin", json!({"purpose": "sign_in"})).unwrap();
    let state = support::query(begun["auth_url"].as_str().unwrap())["state"].clone();
    let url = begun["auth_url"].as_str().unwrap().to_string();
    let browser = std::thread::spawn(move || shellx_fake_api::browse(&url));
    let ok = core.call("auth.google.finish", json!({"flow_id": begun["flow_id"]})).unwrap();
    let _ = browser.join();
    let t = &support::requests_to(&fake, "/fake-google/token")[0];
    let blob = ok.to_string();
    for secret in [fake.issued_token(), "fake-desktop-secret".into(), t.form["code"].clone(), t.form["code_verifier"].clone(), state] {
        assert!(!blob.contains(&secret));
    }
    let begun = core.call("auth.google.begin", json!({"purpose": "sign_in"})).unwrap();
    let q = support::query(begun["auth_url"].as_str().unwrap());
    let url = format!("{}?code=4%2Fx&state=wrong", q["redirect_uri"]);
    let browser = std::thread::spawn(move || shellx_fake_api::browse(&url));
    let e = core.call("auth.google.finish", json!({"flow_id": begun["flow_id"]})).unwrap_err();
    let _ = browser.join();
    assert!(!e.message.contains(&q["state"]) && !e.message.contains("wrong") && !e.message.contains(&q["nonce"]));
}

#[test]
fn concurrent_begins_leave_one_live_listener() {
    for _ in 0..5 {
        let (core, _fake, _dir) = support::google_logged_out();
        let (a, b) = std::thread::scope(|s| {
            let x = s.spawn(|| core.call("auth.google.begin", json!({"purpose": "sign_in"})).unwrap());
            let y = s.spawn(|| core.call("auth.google.begin", json!({"purpose": "sign_in"})).unwrap());
            (x.join().unwrap(), y.join().unwrap())
        });
        let live = [a, b]
            .iter()
            .filter(|r| std::net::TcpStream::connect(("127.0.0.1", port_of(&redirect_of(r["auth_url"].as_str().unwrap())))).is_ok())
            .count();
        assert_eq!(live, 1);
    }
}
