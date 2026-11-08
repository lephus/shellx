//! Google sign-in through the loopback flow against the fake relay and fake Google.
mod support;

use serde_json::{Value, json};

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

#[allow(dead_code)]
fn _unused(_: Value) {}
