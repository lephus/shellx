//! Fake relay Google routes, the fake Google and the account routes of plan 1B.
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use shellx_fake_api::{FakeApi, FakeOptions};
use std::io::{Read, Write};

/// Raw-socket request; returns status, lowercased headers text and the body.
fn raw(addr: &str, method: &str, path: &str, bearer: Option<&str>, ctype: &str, body: &str) -> (u16, String, String) {
    let addr = addr.strip_prefix("http://").unwrap();
    let auth = bearer.map(|t| format!("Authorization: Bearer {t}\r\n")).unwrap_or_default();
    let mut s = std::net::TcpStream::connect(addr).unwrap();
    write!(
        s,
        "{method} {path} HTTP/1.1\r\nHost: x\r\nConnection: close\r\nContent-Type: {ctype}\r\n{auth}Content-Length: {}\r\n\r\n{body}",
        body.len()
    )
    .unwrap();
    let mut resp = String::new();
    s.read_to_string(&mut resp).unwrap();
    let status = resp[9..12].parse().unwrap();
    let (head, body) = resp.split_once("\r\n\r\n").unwrap_or((&resp, ""));
    (status, head.to_string(), body.to_string())
}

fn request(addr: &str, method: &str, path: &str, bearer: Option<&str>, body: Option<&Value>) -> (u16, Value) {
    let body = body.map(Value::to_string).unwrap_or_default();
    let (st, _, b) = raw(addr, method, path, bearer, "application/json", &body);
    (st, serde_json::from_str(&b).unwrap_or(Value::Null))
}

fn code(v: &Value) -> &str {
    v["error"]["code"].as_str().unwrap_or("")
}

fn challenge(verifier: &str) -> String {
    URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()))
}

fn auth_path(challenge: &str, state: &str, nonce: &str) -> String {
    format!(
        "/fake-google/auth?client_id=fake-desktop-client&redirect_uri=http%3A%2F%2F127.0.0.1%3A9%2Foauth2%2Fcallback&response_type=code&scope=openid%20email%20profile&state={state}&nonce={nonce}&code_challenge={challenge}&code_challenge_method=S256&prompt=select_account"
    )
}

fn token_form(code: &str, verifier: &str) -> String {
    format!(
        "grant_type=authorization_code&code={}&redirect_uri=http%3A%2F%2F127.0.0.1%3A9%2Foauth2%2Fcallback&client_id=fake-desktop-client&client_secret=fake-desktop-secret&code_verifier={verifier}",
        code.replace('/', "%2F")
    )
}

fn auth_code(fake: &FakeApi, verifier: &str, nonce: &str) -> String {
    let (st, head, _) = raw(&fake.base_url, "GET", &auth_path(&challenge(verifier), "st", nonce), None, "", "");
    assert_eq!(st, 302, "{head}");
    let loc = head.lines().find(|l| l.to_ascii_lowercase().starts_with("location:")).unwrap();
    let q = loc.split_once('?').unwrap().1;
    let code = q.split('&').find_map(|kv| kv.strip_prefix("code=")).unwrap();
    code.replace("%2F", "/")
}

fn new_nonce(fake: &FakeApi) -> String {
    let (st, v) = request(&fake.base_url, "POST", "/v1/auth/nonce", None, Some(&json!({})));
    assert_eq!(st, 201, "{v}");
    v["nonce"].as_str().unwrap().to_string()
}

/// A full fake-Google round trip; returns the id_token.
fn id_token(fake: &FakeApi, nonce: &str) -> String {
    let verifier = "v".repeat(43);
    let c = auth_code(fake, &verifier, nonce);
    let (st, _, body) = raw(&fake.base_url, "POST", "/fake-google/token", None, "application/x-www-form-urlencoded", &token_form(&c, &verifier));
    assert_eq!(st, 200, "{body}");
    serde_json::from_str::<Value>(&body).unwrap()["id_token"].as_str().unwrap().to_string()
}

fn device(seed: u8) -> Value {
    json!({"kind":"desktop","name":"d","platform":"macos","public_key": URL_SAFE_NO_PAD.encode([seed; 32])})
}

fn google_sign_in(fake: &FakeApi, seed: u8) -> (u16, Value) {
    let nonce = new_nonce(fake);
    let idt = id_token(fake, &nonce);
    request(&fake.base_url, "POST", "/v1/auth/google", None, Some(&json!({"id_token": idt, "nonce": nonce, "device": device(seed)})))
}

fn password_login(fake: &FakeApi, email: &str, seed: u8) -> Value {
    let (st, l) = request(&fake.base_url, "POST", "/v1/auth/login", None, Some(&json!({"email": email, "password":"pw","device": device(seed)})));
    assert_eq!(st, 200, "{l}");
    l
}

#[test]
fn fake_google_checks_pkce_and_spends_codes() {
    let fake = FakeApi::start(FakeOptions::default());
    let verifier = "a".repeat(43);
    let (st, head, _) = raw(&fake.base_url, "GET", &auth_path(&challenge(&verifier), "stat-1", "n1"), None, "", "");
    assert_eq!(st, 302);
    assert!(head.contains("code=4%2F") && head.contains("state=stat-1"), "{head}");
    let c = auth_code(&fake, &verifier, "n1");
    let bad = token_form(&c, &"b".repeat(43));
    let (st, _, body) = raw(&fake.base_url, "POST", "/fake-google/token", None, "application/x-www-form-urlencoded", &bad);
    assert_eq!(st, 400);
    assert_eq!(serde_json::from_str::<Value>(&body).unwrap(), json!({"error":"invalid_grant"}));
    // a bad verifier attempt does not necessarily spend the code, but the right one works once
    let c = auth_code(&fake, &verifier, "n1");
    let ok = token_form(&c, &verifier);
    let (st, _, body) = raw(&fake.base_url, "POST", "/fake-google/token", None, "application/x-www-form-urlencoded", &ok);
    assert_eq!(st, 200, "{body}");
    let v: Value = serde_json::from_str(&body).unwrap();
    assert!(v["id_token"].as_str().unwrap().starts_with("fake-idt."));
    assert_eq!(v["token_type"], "Bearer");
    let (st, _, body) = raw(&fake.base_url, "POST", "/fake-google/token", None, "application/x-www-form-urlencoded", &ok);
    assert_eq!(st, 400);
    assert_eq!(serde_json::from_str::<Value>(&body).unwrap()["error"], "invalid_grant");
}

#[test]
fn nonces_are_single_use() {
    let fake = FakeApi::start(FakeOptions::default());
    let (st, v) = request(&fake.base_url, "POST", "/v1/auth/nonce", None, Some(&json!({})));
    assert_eq!(st, 201);
    assert_eq!(v["nonce"].as_str().unwrap().len(), 43);
    assert_eq!(v["expires_in"], 600);
    let nonce = v["nonce"].as_str().unwrap().to_string();
    assert_eq!(fake.issued_nonces(), vec![nonce.clone()]);
    let idt = id_token(&fake, &nonce);
    let body = json!({"id_token": idt, "nonce": nonce, "device": device(1)});
    assert_eq!(request(&fake.base_url, "POST", "/v1/auth/google", None, Some(&body)).0, 200);
    let idt2 = id_token(&fake, &nonce);
    let (st, v) = request(&fake.base_url, "POST", "/v1/auth/google", None, Some(&json!({"id_token": idt2, "nonce": nonce, "device": device(1)})));
    assert_eq!(st, 401);
    assert_eq!(code(&v), "invalid_credentials");
}

#[test]
fn google_sign_in_follows_the_account_rules() {
    let fake = FakeApi::start(FakeOptions::default());
    let (st, a) = google_sign_in(&fake, 1);
    assert_eq!(st, 200, "{a}");
    assert_eq!(a["email"], "google-user@shellx.test");
    assert_eq!(fake.token_auth_method(a["token"].as_str().unwrap()).as_deref(), Some("google"));
    let (st, a2) = google_sign_in(&fake, 1);
    assert_eq!(st, 200);
    assert_eq!((&a2["user_id"], &a2["device_id"]), (&a["user_id"], &a["device_id"]));
    password_login(&fake, "pw@shellx.test", 2);
    fake.set_google_account("pw@shellx.test", "s2");
    let (st, v) = google_sign_in(&fake, 3);
    assert_eq!(st, 409);
    assert_eq!(code(&v), "switch_from_signed_in_device");
    let l = password_login(&fake, "other@shellx.test", 4);
    assert_eq!(fake.token_auth_method(l["token"].as_str().unwrap()).as_deref(), Some("password"));
}

#[test]
fn link_rules_replace_the_token() {
    let fake = FakeApi::start(FakeOptions::default());
    // A owns the Google email through a Google sign-in.
    let (_, a) = google_sign_in(&fake, 1);
    let b = password_login(&fake, "b@shellx.test", 2);
    let b_tok = b["token"].as_str().unwrap().to_string();
    let link = |fake: &FakeApi, tok: Option<&str>| {
        let nonce = new_nonce(fake);
        let idt = id_token(fake, &nonce);
        request(&fake.base_url, "POST", "/v1/auth/google/link", tok, Some(&json!({"id_token": idt, "nonce": nonce})))
    };
    assert_eq!(link(&fake, None).0, 401);
    // The identity (google, sub) already belongs to A -> identity_in_use.
    let (st, v) = link(&fake, Some(&b_tok));
    assert_eq!((st, code(&v)), (409, "identity_in_use"));
    // A new Google subject whose email is owned by A -> email_in_use.
    fake.set_google_account("google-user@shellx.test", "other-sub");
    let (st, v) = link(&fake, Some(&b_tok));
    assert_eq!((st, code(&v)), (409, "email_in_use"));
    // A fresh email and subject -> success.
    fake.set_google_account("new@shellx.test", "sub-new");
    let (st, v) = link(&fake, Some(&b_tok));
    assert_eq!(st, 200, "{v}");
    assert!(!fake.token_is_live(&b_tok));
    let new = v["token"].as_str().unwrap();
    assert_eq!(fake.token_auth_method(new).as_deref(), Some("google"));
    assert_eq!(fake.user_email(b["user_id"].as_str().unwrap()).as_deref(), Some("new@shellx.test"));
    let _ = a;
}

#[test]
fn identities_remove_rules() {
    let fake = FakeApi::start(FakeOptions::default());
    let (_, a) = google_sign_in(&fake, 1);
    let tok = a["token"].as_str().unwrap();
    let user = a["user_id"].as_str().unwrap();
    let (st, v) = request(&fake.base_url, "GET", "/v1/account/identities", Some(tok), None);
    assert_eq!(st, 200);
    let list = v["identities"].as_array().unwrap();
    assert_eq!(list.len(), 1);
    let gid = list[0]["identity_id"].as_str().unwrap().to_string();
    let (st, v) = request(&fake.base_url, "DELETE", &format!("/v1/account/identities/{gid}"), Some(tok), None);
    assert_eq!((st, code(&v)), (409, "last_google_identity"));
    let aid = fake.add_identity(user, "apple", "apple-sub", "x@privaterelay.appleid.com", true, Some("Phu's iPhone"));
    let (_, v) = request(&fake.base_url, "GET", "/v1/account/identities", Some(tok), None);
    let apple = v["identities"].as_array().unwrap().iter().find(|i| i["identity_id"] == aid.as_str()).unwrap().clone();
    assert_eq!(apple["linked_via_device_name"], "Phu's iPhone");
    assert_eq!(apple["is_private_email"], true);
    assert_eq!(apple["provider"], "apple");
    let (st, _) = request(&fake.base_url, "DELETE", &format!("/v1/account/identities/{aid}"), Some(tok), None);
    assert_eq!(st, 204);
    let (st, v) = request(&fake.base_url, "DELETE", "/v1/account/identities/nope", Some(tok), None);
    assert_eq!((st, code(&v)), (404, "identity_not_found"));
}

#[test]
fn account_delete_needs_a_fresh_identity_token() {
    let fake = FakeApi::start(FakeOptions::default());
    let (_, a) = google_sign_in(&fake, 1);
    let tok = a["token"].as_str().unwrap();
    let user = a["user_id"].as_str().unwrap();
    let (st, v) = request(&fake.base_url, "DELETE", "/v1/account", Some(tok), Some(&json!({})));
    assert_eq!((st, code(&v)), (401, "reauth_required"));
    let nonce = new_nonce(&fake);
    let idt = id_token(&fake, &nonce);
    let (st, v) = request(&fake.base_url, "DELETE", "/v1/account", Some(tok), Some(&json!({"id_token": idt, "nonce": nonce})));
    assert_eq!(st, 204, "{v}");
    assert!(!fake.user_exists(user));
    assert!(!fake.token_is_live(tok));
}

#[test]
fn apple_link_pairings_are_marked() {
    let fake = FakeApi::start(FakeOptions::default());
    let l = password_login(&fake, "m@shellx.test", 1);
    let tok = l["token"].as_str().unwrap();
    let (st, m) = request(
        &fake.base_url,
        "POST",
        "/v2/machines",
        Some(tok),
        Some(&json!({"name":"Mac","platform":"macos","os_version":"15.5","app_version":"2.0.0","noise_public_key_b64": URL_SAFE_NO_PAD.encode([5u8; 32])})),
    );
    assert!(st == 200 || st == 201, "{m}");
    let mid = m["machine_id"].as_str().or(m["id"].as_str()).unwrap().to_string();
    let plain = fake.add_phone_pairing(&mid, "Plain", "ios", [1u8; 32]);
    let apple = fake.add_apple_link_phone_pairing(&mid, "Apple", [2u8; 32]);
    let (_, v) = request(&fake.base_url, "GET", "/v2/phone-pairings?role=target&apple_links=1", Some(tok), None);
    let items = v["pairings"].as_array().unwrap();
    let find = |id: &str| items.iter().find(|i| i["pairing_id"] == id).unwrap().clone();
    assert_eq!(find(&apple)["links_apple_id"], true);
    assert_eq!(find(&plain)["links_apple_id"], false);
    let (_, v) = request(&fake.base_url, "GET", "/v2/phone-pairings?role=target", Some(tok), None);
    let items = v["pairings"].as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["pairing_id"], plain.as_str());
}

#[test]
fn browse_refuses_non_loopback_urls() {
    assert!(shellx_fake_api::browse("https://accounts.google.com/o/oauth2/v2/auth").is_err());
}
