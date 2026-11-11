//! Fake relay email code routes (`POST /v1/auth/email/code` and `/verify`), as `relay/src/routes/email-sign-in.ts` answers them.
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

#[test]
fn a_code_request_answers_202_with_the_normalized_email() {
    let fake = FakeApi::start(FakeOptions::default());
    let (st, v) = ask(&fake, "  Foo@Bar.com ", "vi");
    assert_eq!(st, 202, "{v}");
    assert_eq!(challenge_id(&v).len(), 43);
    assert_eq!((&v["expires_in"], &v["resend_in"]), (&json!(600), &json!(60)));
    assert_eq!(v["email"], "foo@bar.com");
    let code = fake.email_code("FOO@bar.com").unwrap();
    assert!(code.len() == 6 && code.bytes().all(|b| b.is_ascii_digit()), "{code}");
    assert_eq!(fake.email_locale("foo@bar.com").as_deref(), Some("vi"));
    assert_eq!(shellx_fake_api::EMAIL_CODE_TTL_SECS, 600);
    assert_eq!(shellx_fake_api::EMAIL_RESEND_SECS, 60);
    assert_eq!(shellx_fake_api::EMAIL_CODE_MAX_ATTEMPTS, 5);
}

#[test]
fn the_mail_is_vietnamese_only_for_exactly_vi() {
    let fake = FakeApi::start(FakeOptions::default());
    for (i, locale) in [json!("fr"), json!(7), Value::Null, json!("VI"), json!("vi-VN")].into_iter().enumerate() {
        let email = format!("a{i}@bar.com");
        let mut body = json!({"email": email});
        if !locale.is_null() {
            body["locale"] = locale.clone();
        }
        let (st, v) = ask_body(&fake, &body);
        assert_eq!(st, 202, "{locale}: {v}");
        assert_eq!(fake.email_locale(&email).as_deref(), Some("en"), "{locale}");
    }
    let (st, _) = ask(&fake, "vi@bar.com", "vi");
    assert_eq!(st, 202);
    assert_eq!(fake.email_locale("vi@bar.com").as_deref(), Some("vi"));
}

#[test]
fn bad_addresses_and_bodies_are_refused() {
    let fake = FakeApi::start(FakeOptions::default());
    let long = format!("{}@bar.com", "a".repeat(255 - "@bar.com".len()));
    assert_eq!(long.len(), 255);
    let at_65 = format!("{}@bar.com", "a".repeat(65));
    assert_eq!(at_65.rfind('@'), Some(65));
    let bad: Vec<Value> = ["nope", "a@b", "a b@c.de", "phu@ẽample.com", "a..b@c.de", "a@-b.cd", ".a@b.cd", long.as_str(), at_65.as_str()]
        .iter()
        .map(|s| json!(s))
        .chain([json!(5)])
        .collect();
    for email in bad {
        let (st, v) = ask_body(&fake, &json!({"email": email}));
        assert_eq!((st, code(&v)), (400, "invalid_email"), "{email}");
    }
    for email in ["a@mailinator.com", "a@x.mailinator.com"] {
        let (st, v) = ask(&fake, email, "en");
        assert_eq!((st, code(&v)), (400, "disposable_email"), "{email}");
    }
    for body in ["[]", "not json"] {
        let (st, v, _) = post_text(&fake, CODE, body);
        assert_eq!((st, code(&v)), (400, "bad_request"), "{body}");
    }
    for email in ["nope", "a@mailinator.com", "a@x.mailinator.com", "phu@ẽample.com"] {
        assert_eq!(fake.email_code(email), None, "{email}");
    }
}

#[test]
fn a_relay_without_resend_answers_503_before_reading_the_body() {
    let fake = FakeApi::start(FakeOptions { email_sign_in: false, ..FakeOptions::default() });
    let (st, v, _) = post_text(&fake, CODE, "[]");
    assert_eq!((st, code(&v)), (503, "email_sign_in_disabled"));
    let (st, v) = ask_body(&fake, &json!({"email": "nope"}));
    assert_eq!((st, code(&v)), (503, "email_sign_in_disabled"));
}

#[test]
fn an_old_relay_answers_404_on_both_routes() {
    let fake = FakeApi::start(FakeOptions { email_routes: false, ..FakeOptions::default() });
    let (st, v) = ask(&fake, "foo@bar.com", "en");
    assert_eq!((st, code(&v)), (404, "not_found"));
    let (st, v) = verify(&fake, &"A".repeat(43), json!("123456"), device(1));
    assert_eq!((st, code(&v)), (404, "not_found"));
}

#[test]
fn the_right_code_signs_in_once_with_an_email_session() {
    let fake = FakeApi::start(FakeOptions::default());
    let (_, v) = ask(&fake, "Foo@Bar.com", "en");
    let (c, code_) = (challenge_id(&v), fake.email_code("foo@bar.com").unwrap());
    let (st, a) = verify(&fake, &c, json!(code_), device(1));
    assert_eq!(st, 200, "{a}");
    for k in ["user_id", "device_id", "token"] {
        assert!(!a[k].as_str().unwrap_or("").is_empty(), "{k}");
    }
    assert_eq!(a["email"], "foo@bar.com");
    let token = a["token"].as_str().unwrap();
    assert_eq!(fake.token_auth_method(token).as_deref(), Some("email"));
    let (st, ids) = request(&fake.base_url, "GET", "/v1/account/identities", Some(token), None);
    assert_eq!(st, 200);
    let list = ids["identities"].as_array().unwrap();
    assert_eq!(list.len(), 1);
    assert_eq!((&list[0]["provider"], &list[0]["email"]), (&json!("email"), &json!("foo@bar.com")));
    let (st, v) = verify(&fake, &c, json!(code_), device(1));
    assert_eq!((st, code(&v)), (410, "code_expired"));
    assert_eq!(fake.email_code("foo@bar.com"), None);
}

#[test]
fn a_wrong_code_counts_and_the_fifth_kills_the_challenge() {
    let fake = FakeApi::start(FakeOptions::default());
    fake.set_next_email_code("004217");
    let (_, v) = ask(&fake, "foo@bar.com", "en");
    let c = challenge_id(&v);
    for guess in [json!(4217), json!(" 004217"), json!("4217"), json!("000000")] {
        let (st, v) = verify(&fake, &c, guess.clone(), device(1));
        assert_eq!((st, code(&v)), (401, "invalid_code"), "{guess}");
    }
    let (st, v) = verify(&fake, &c, json!("123456"), device(1));
    assert_eq!((st, code(&v)), (410, "code_expired"));
    let (st, v) = verify(&fake, &c, json!("004217"), device(1));
    assert_eq!((st, code(&v)), (410, "code_expired"));
}

#[test]
fn the_fifth_guess_can_still_be_right() {
    let fake = FakeApi::start(FakeOptions::default());
    fake.set_next_email_code("004217");
    let (_, v) = ask(&fake, "foo@bar.com", "en");
    let c = challenge_id(&v);
    for _ in 0..4 {
        let (st, v) = verify(&fake, &c, json!("000000"), device(1));
        assert_eq!((st, code(&v)), (401, "invalid_code"));
    }
    let (st, v) = verify(&fake, &c, json!("004217"), device(1));
    assert_eq!(st, 200, "{v}");
}

#[test]
fn a_new_code_replaces_the_old_one_for_that_address() {
    let fake = FakeApi::start(FakeOptions::default());
    fake.set_next_email_code("111111");
    let (_, v1) = ask(&fake, "foo@bar.com", "en");
    fake.set_next_email_code("222222");
    let (_, v2) = ask(&fake, "foo@bar.com", "en");
    let (c1, c2) = (challenge_id(&v1), challenge_id(&v2));
    let (st, v) = verify(&fake, &c1, json!("111111"), device(1));
    assert_eq!((st, code(&v)), (410, "code_expired"));
    let (st, v) = verify(&fake, &c2, json!("111111"), device(1));
    assert_eq!((st, code(&v)), (401, "invalid_code"));
    let (st, v) = verify(&fake, &c2, json!("222222"), device(1));
    assert_eq!(st, 200, "{v}");
}

#[test]
fn dead_challenges_answer_410() {
    let fake = FakeApi::start(FakeOptions::default());
    let (_, v) = ask(&fake, "foo@bar.com", "en");
    let c = challenge_id(&v);
    let right = fake.email_code("foo@bar.com").unwrap();
    fake.expire_email_codes();
    assert_eq!(fake.email_code("foo@bar.com"), None);
    let (st, v) = verify(&fake, &c, json!(right), device(1));
    assert_eq!((st, code(&v)), (410, "code_expired"));
    for id in [json!("nope"), json!("A".repeat(43)), json!(5)] {
        let (st, v, _) = post_text(&fake, VERIFY, &json!({"challenge_id": id, "code": "123456", "device": device(1)}).to_string());
        assert_eq!((st, code(&v)), (410, "code_expired"), "{id}");
    }
}

#[test]
fn a_password_account_answers_409_and_the_code_is_spent() {
    let fake = FakeApi::start(FakeOptions::default());
    password_login(&fake, "a@b.cd", 1);
    let (_, v) = ask(&fake, "a@b.cd", "en");
    let c = challenge_id(&v);
    let right = fake.email_code("a@b.cd").unwrap();
    let (st, v) = verify(&fake, &c, json!(right), device(2));
    assert_eq!((st, code(&v)), (409, "switch_from_signed_in_device"));
    let (st, v) = verify(&fake, &c, json!(right), device(2));
    assert_eq!((st, code(&v)), (410, "code_expired"));
    assert_eq!(fake.email_code("a@b.cd"), None);
}

#[test]
fn an_unverified_account_with_an_apple_id_answers_409() {
    let fake = FakeApi::start(FakeOptions::default());
    let u = fake.add_user("a@b.cd");
    fake.add_identity(&u, "apple", "apple-1", "apple-user@shellx.test", true, None);
    let (_, v) = ask(&fake, "a@b.cd", "en");
    let right = fake.email_code("a@b.cd").unwrap();
    let (st, v) = verify(&fake, &challenge_id(&v), json!(right), device(1));
    assert_eq!((st, code(&v)), (409, "switch_from_signed_in_device"));
}

#[test]
fn a_bare_account_is_claimed() {
    let fake = FakeApi::start(FakeOptions::default());
    let u = fake.add_user("a@b.cd");
    let (_, v) = ask(&fake, "a@b.cd", "en");
    let right = fake.email_code("a@b.cd").unwrap();
    let (st, a) = verify(&fake, &challenge_id(&v), json!(right), device(1));
    assert_eq!(st, 200, "{a}");
    assert_eq!(a["user_id"], u.as_str());
    let (_, ids) = request(&fake.base_url, "GET", "/v1/account/identities", Some(a["token"].as_str().unwrap()), None);
    let providers: Vec<&str> = ids["identities"].as_array().unwrap().iter().map(|i| i["provider"].as_str().unwrap()).collect();
    assert_eq!(providers, ["email"]);
}

#[test]
fn a_google_account_gets_the_email_sign_in_added() {
    let fake = FakeApi::start(FakeOptions::default());
    let (st, g) = google_sign_in(&fake, 1);
    assert_eq!(st, 200, "{g}");
    let (_, v) = ask(&fake, "google-user@shellx.test", "en");
    let right = fake.email_code("google-user@shellx.test").unwrap();
    let (st, a) = verify(&fake, &challenge_id(&v), json!(right), device(2));
    assert_eq!(st, 200, "{a}");
    assert_eq!(a["user_id"], g["user_id"]);
    let (_, ids) = request(&fake.base_url, "GET", "/v1/account/identities", Some(a["token"].as_str().unwrap()), None);
    let providers: Vec<&str> = ids["identities"].as_array().unwrap().iter().map(|i| i["provider"].as_str().unwrap()).collect();
    assert_eq!(providers, ["google", "email"]);
}

#[test]
fn a_bad_device_is_invalid_device_and_spends_no_guess() {
    let fake = FakeApi::start(FakeOptions::default());
    fake.set_next_email_code("004217");
    let (_, v) = ask(&fake, "foo@bar.com", "en");
    let c = challenge_id(&v);
    for _ in 0..4 {
        let (st, v) = verify(&fake, &c, json!("000000"), device(1));
        assert_eq!((st, code(&v)), (401, "invalid_code"));
    }
    let agent = json!({"kind":"agent","name":"d","platform":"macos","public_key": URL_SAFE_NO_PAD.encode([1u8; 32])});
    let phone_desktop = json!({"kind":"desktop","name":"d","platform":"ios","public_key": URL_SAFE_NO_PAD.encode([1u8; 32])});
    for d in [agent, Value::Null, phone_desktop] {
        let (st, v) = verify(&fake, &c, json!("004217"), d.clone());
        assert_eq!((st, code(&v)), (400, "invalid_device"), "{d}");
    }
    let (st, v) = verify(&fake, &c, json!("004217"), device(1));
    assert_eq!(st, 200, "{v}");
}

#[test]
fn fail_next_scripts_one_answer_and_changes_no_challenge() {
    let fake = FakeApi::start(FakeOptions::default());
    let (_, v) = ask(&fake, "foo@bar.com", "en");
    let c1 = challenge_id(&v);
    let right = fake.email_code("foo@bar.com").unwrap();
    fake.fail_next(CODE, 429, "rate_limited");
    let (st, v) = ask(&fake, "foo@bar.com", "en");
    assert_eq!((st, code(&v)), (429, "rate_limited"));
    fake.fail_next(CODE, 404, "");
    let (st, _, body) = post_text(&fake, CODE, &json!({"email": "foo@bar.com"}).to_string());
    assert_eq!((st, body.as_str()), (404, ""));
    let (st, v) = verify(&fake, &c1, json!(right), device(1));
    assert_eq!(st, 200, "{v}");
}

#[test]
fn fail_next_mail_drops_the_live_code_like_the_relay() {
    let fake = FakeApi::start(FakeOptions::default());
    let (_, v) = ask(&fake, "foo@bar.com", "en");
    let c1 = challenge_id(&v);
    let right = fake.email_code("foo@bar.com").unwrap();
    fake.fail_next_mail();
    let (st, v) = ask(&fake, "foo@bar.com", "en");
    assert_eq!((st, code(&v)), (502, "email_send_failed"));
    assert_eq!(fake.email_code("foo@bar.com"), None);
    let (st, v) = verify(&fake, &c1, json!(right), device(1));
    assert_eq!((st, code(&v)), (410, "code_expired"));
    let (st, _) = ask(&fake, "foo@bar.com", "en");
    assert_eq!(st, 202);
}
