//! Fake relay account routes that know email sign-in: removal keeps one sign-in, a Google link to another address
//! drops the email sign-in, and `DELETE /v1/account` takes a code (`relay/src/routes/{identities,sign-in,account}.ts`).
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

const CODE: &str = "/v1/auth/email/code";
const VERIFY: &str = "/v1/auth/email/verify";

fn post_text(fake: &FakeApi, path: &str, body: &str) -> (u16, Value, String) {
    let (st, _, b) = raw(&fake.base_url, "POST", path, None, "application/json", body);
    (st, serde_json::from_str(&b).unwrap_or(Value::Null), b)
}

/// POST CODE with a JSON body.
fn ask_body(fake: &FakeApi, body: &Value) -> (u16, Value) {
    let (st, v, _) = post_text(fake, CODE, &body.to_string());
    (st, v)
}

fn ask(fake: &FakeApi, email: &str, locale: &str) -> (u16, Value) {
    ask_body(fake, &json!({"email": email, "locale": locale}))
}

fn verify(fake: &FakeApi, challenge_id: &str, code: Value, device: Value) -> (u16, Value) {
    let (st, v, _) = post_text(fake, VERIFY, &json!({"challenge_id": challenge_id, "code": code, "device": device}).to_string());
    (st, v)
}

fn challenge_id(v: &Value) -> String {
    v["challenge_id"].as_str().unwrap().to_string()
}

/// ask, read the mailbox, verify on device `seed`; `(user_id, token)`.
fn email_sign_in(fake: &FakeApi, email: &str, seed: u8) -> (String, String) {
    let (st, v) = ask(fake, email, "en");
    assert_eq!(st, 202, "{v}");
    let right = fake.email_code(email).unwrap();
    let (st, a) = verify(fake, &challenge_id(&v), json!(right), device(seed));
    assert_eq!(st, 200, "{a}");
    (a["user_id"].as_str().unwrap().to_string(), a["token"].as_str().unwrap().to_string())
}

fn identities(fake: &FakeApi, token: &str) -> Vec<Value> {
    let (st, v) = request(&fake.base_url, "GET", "/v1/account/identities", Some(token), None);
    assert_eq!(st, 200, "{v}");
    v["identities"].as_array().unwrap().clone()
}

fn providers(fake: &FakeApi, token: &str) -> Vec<String> {
    identities(fake, token).iter().map(|i| i["provider"].as_str().unwrap().to_string()).collect()
}

fn identity_id(fake: &FakeApi, token: &str, provider: &str) -> String {
    identities(fake, token).iter().find(|i| i["provider"] == provider).unwrap()["identity_id"].as_str().unwrap().to_string()
}

fn remove(fake: &FakeApi, token: &str, id: &str) -> (u16, Value) {
    request(&fake.base_url, "DELETE", &format!("/v1/account/identities/{id}"), Some(token), None)
}

#[test]
fn the_last_way_to_sign_in_cannot_be_removed() {
    let fake = FakeApi::start(FakeOptions::default());
    // An email-only account.
    let (_, tok) = email_sign_in(&fake, "foo@bar.com", 1);
    let (st, v) = remove(&fake, &tok, &identity_id(&fake, &tok, "email"));
    assert_eq!((st, code(&v)), (409, "last_google_identity"));
    // A Google account with the email sign-in added: device 1 by Google, device 2 by code.
    let (st, g) = google_sign_in(&fake, 1);
    assert_eq!(st, 200, "{g}");
    let g_tok = g["token"].as_str().unwrap().to_string();
    let (_, e_tok) = email_sign_in(&fake, "google-user@shellx.test", 2);
    assert_eq!(providers(&fake, &g_tok), ["google", "email"]);
    let (st, v) = remove(&fake, &g_tok, &identity_id(&fake, &g_tok, "email"));
    assert_eq!(st, 204, "{v}");
    assert!(!fake.token_is_live(&e_tok));
    assert!(fake.token_is_live(&g_tok));
    let (st, v) = remove(&fake, &g_tok, &identity_id(&fake, &g_tok, "google"));
    assert_eq!((st, code(&v)), (409, "last_google_identity"));
}

#[test]
fn linking_google_with_another_address_removes_the_email_sign_in() {
    let fake = FakeApi::start(FakeOptions::default());
    let (user, tok1) = email_sign_in(&fake, "foo@bar.com", 1);
    let (user2, tok2) = email_sign_in(&fake, "foo@bar.com", 2);
    assert_eq!(user, user2);
    fake.set_google_account("g@x.test", "sub-g");
    let nonce = new_nonce(&fake);
    let idt = id_token(&fake, &nonce);
    let (st, v) = request(&fake.base_url, "POST", "/v1/auth/google/link", Some(&tok1), Some(&json!({"id_token": idt, "nonce": nonce})));
    assert_eq!(st, 200, "{v}");
    assert_eq!(v["email"], "g@x.test");
    let new = v["token"].as_str().unwrap();
    assert_eq!(providers(&fake, new), ["google"]);
    assert!(!fake.token_is_live(&tok2));
    assert!(!fake.token_is_live(&tok1));
    assert_eq!(fake.token_auth_method(new).as_deref(), Some("google"));
}

#[test]
fn an_account_can_be_deleted_with_a_code_to_its_own_address() {
    let fake = FakeApi::start(FakeOptions::default());
    let (user, tok) = email_sign_in(&fake, "foo@bar.com", 1);
    fake.set_next_email_code("123456");
    let (_, v) = ask(&fake, "foo@bar.com", "en");
    let c = challenge_id(&v);
    let delete = |code_: &str| request(&fake.base_url, "DELETE", "/v1/account", Some(&tok), Some(&json!({"challenge_id": c, "code": code_})));
    let (st, v) = delete("000000");
    assert_eq!((st, code(&v)), (401, "invalid_code"));
    assert!(fake.user_exists(&user));
    let (st, v) = delete("123456");
    assert_eq!(st, 204, "{v}");
    assert!(!fake.user_exists(&user));
    assert!(!fake.token_is_live(&tok));
}

#[test]
fn a_code_to_another_address_cannot_delete_the_account() {
    let fake = FakeApi::start(FakeOptions::default());
    let (user, tok) = email_sign_in(&fake, "foo@bar.com", 1);
    let (_, v) = ask(&fake, "other@bar.com", "en");
    let c = challenge_id(&v);
    let right = fake.email_code("other@bar.com").unwrap();
    let body = json!({"challenge_id": c, "code": right});
    let (st, v) = request(&fake.base_url, "DELETE", "/v1/account", Some(&tok), Some(&body));
    assert_eq!((st, code(&v)), (401, "reauth_required"));
    // The code is spent: the same challenge is dead at /verify and at the delete.
    let (st, v) = verify(&fake, &c, json!(right), device(2));
    assert_eq!((st, code(&v)), (410, "code_expired"));
    let (st, v) = request(&fake.base_url, "DELETE", "/v1/account", Some(&tok), Some(&body));
    assert_eq!((st, code(&v)), (410, "code_expired"));
    assert!(fake.user_exists(&user));
    assert!(fake.token_is_live(&tok));
}
