//! Email code sign-in (`auth.email.begin`, `auth.email.finish`) against the fake relay and its mailbox.
mod support;

use serde_json::{Value, json};
use shellx_core::Core;
use shellx_core::auth_email::{CODE_PATH, VERIFY_PATH};
use shellx_fake_api::{FakeApi, FakeOptions};

const REG: fn() -> Value = || json!({"name":"Mac A","platform":"macos","os_version":"15","app_version":"2.0.0"});

fn session_json(dir: &std::path::Path) -> Value {
    serde_json::from_slice(&std::fs::read(dir.join("session.json")).unwrap()).unwrap()
}

fn begin(core: &Core, email: &str) -> Result<Value, shellx_core::CoreError> {
    core.call("auth.email.begin", json!({"email": email, "locale": "en"}))
}

fn finish(core: &Core, challenge_id: &Value, code: &str) -> Result<Value, shellx_core::CoreError> {
    core.call("auth.email.finish", json!({"challenge_id": challenge_id, "code": code}))
}

/// A core against a fake built with `opts`.
fn with_options(opts: FakeOptions) -> (Core, FakeApi, support::Dir) {
    let fake = FakeApi::start(opts);
    let dir = support::state_dir();
    let core = Core::new();
    support::configure(&core, &fake.base_url, &dir, json!({}));
    (core, fake, dir)
}

#[test]
fn begin_asks_the_relay_for_a_code_and_returns_the_challenge() {
    let (core, fake, dir) = support::logged_out();
    let r = core.call("auth.email.begin", json!({"email": "  Foo@Bar.com ", "locale": "vi-VN"})).unwrap();
    assert_eq!(r["challenge_id"].as_str().unwrap().len(), 43);
    assert_eq!((&r["expires_in"], &r["resend_in"]), (&json!(600), &json!(60)));
    assert_eq!(r["email"], "foo@bar.com");
    let sent = support::requests_to(&fake, CODE_PATH);
    assert_eq!(sent.len(), 1);
    assert_eq!(sent[0].method, "POST");
    assert_eq!(sent[0].body, json!({"email": "Foo@Bar.com", "locale": "vi"}));
    assert_eq!(support::header(&sent[0], "Authorization"), None);
    assert_eq!(fake.requests().len(), 1);
    assert_eq!(fake.email_locale("foo@bar.com").as_deref(), Some("vi"));
    assert!(!dir.join("session.json").exists());
}

#[test]
fn locale_is_vi_or_en() {
    let (core, fake, _dir) = support::logged_out();
    let cases = [(json!("VI"), "vi"), (json!("ja"), "en"), (Value::Null, "en"), (json!(5), "en")];
    for (locale, want) in cases {
        let mut p = json!({"email": "foo@bar.com"});
        if !locale.is_null() {
            p["locale"] = locale.clone();
        }
        core.call("auth.email.begin", p).unwrap();
        let body = &support::requests_to(&fake, CODE_PATH).last().unwrap().body.clone();
        assert_eq!(body["locale"], want, "{locale}");
    }
}

#[test]
fn begin_refuses_an_address_the_relay_would_refuse_without_a_request() {
    let (core, fake, _dir) = support::logged_out();
    let long = format!("{}@bar.com", "a".repeat(255 - "@bar.com".len()));
    assert_eq!(long.len(), 255);
    for bad in ["phu@ẽample.com", "   ", long.as_str()] {
        assert_eq!(begin(&core, bad).unwrap_err().code, "invalid_email", "{bad:?}");
    }
    assert!(support::requests_to(&fake, CODE_PATH).is_empty());
}

#[test]
fn finish_signs_in_and_writes_an_email_session() {
    let (core, fake, dir) = support::logged_out();
    fake.set_next_email_code("246810");
    let r = support::email_sign_in(&core, &fake, "Foo@Bar.com").unwrap();
    assert_eq!((r["email"].as_str(), r["auth_method"].as_str()), (Some("foo@bar.com"), Some("email")));
    for k in ["user_id", "device_id", "device_public_key_b64", "fingerprint"] {
        assert!(r[k].as_str().is_some_and(|s| !s.is_empty()), "{k}");
    }
    assert!(r.get("token").is_none());
    let s = session_json(&dir);
    assert_eq!((s["auth_method"].as_str(), s["email"].as_str()), (Some("email"), Some("foo@bar.com")));
    #[cfg(unix)]
    assert_eq!(support::mode(dir.join("session.json")), 0o600);
    assert_eq!(fake.token_auth_method(&fake.issued_token()).as_deref(), Some("email"));
    let v = &support::requests_to(&fake, VERIFY_PATH)[0];
    assert_eq!((v.body["device"]["kind"].as_str(), v.body["device"]["platform"].as_str()), (Some("desktop"), Some("macos")));
    assert_eq!(v.body["device"]["public_key"], r["device_public_key_b64"]);
    assert_eq!(v.body["code"], json!("246810"));
    assert_eq!(support::header(v, "Authorization"), None);
    let session = core.call("auth.session", json!({})).unwrap();
    assert_eq!((session["auth_method"].as_str(), session["email"].as_str()), (Some("email"), Some("foo@bar.com")));
    assert_eq!(core.call("machines.list", json!({})).unwrap()["machines"], json!([]));
}

#[test]
fn a_code_with_leading_zeros_is_sent_as_the_same_six_characters() {
    let (core, fake, _dir) = support::logged_out();
    fake.set_next_email_code("004217");
    let b = begin(&core, "foo@bar.com").unwrap();
    finish(&core, &b["challenge_id"], "004217").unwrap();
    let v = &support::requests_to(&fake, VERIFY_PATH)[0];
    assert_eq!(v.body["code"], json!("004217"));
}

#[test]
fn a_pasted_code_with_spaces_or_wide_digits_is_sent_as_six_ascii_digits() {
    let (core, fake, _dir) = support::logged_out();
    fake.set_next_email_code("123456");
    let b = begin(&core, "foo@bar.com").unwrap();
    finish(&core, &b["challenge_id"], " \u{FF11}\u{FF12}\u{FF13} 456\n").unwrap();
    let v = &support::requests_to(&fake, VERIFY_PATH)[0];
    assert_eq!(v.body["code"], json!("123456"));
}

#[test]
fn a_code_that_is_not_six_digits_is_invalid_code_without_a_request() {
    let (core, fake, _dir) = support::logged_out();
    let b = begin(&core, "foo@bar.com").unwrap();
    for bad in ["12345", "1234567", "12a456", "123-456", "四五六七八九", ""] {
        assert_eq!(finish(&core, &b["challenge_id"], bad).unwrap_err().code, "invalid_code", "{bad:?}");
    }
    assert!(support::requests_to(&fake, VERIFY_PATH).is_empty());
    // No guess was burned: the mailbox code still signs in.
    let code = fake.email_code("foo@bar.com").unwrap();
    finish(&core, &b["challenge_id"], &code).unwrap();
}

#[test]
fn a_wrong_code_is_invalid_code_and_the_fifth_is_code_expired() {
    let (core, fake, dir) = support::logged_out();
    fake.set_next_email_code("004217");
    let b = begin(&core, "foo@bar.com").unwrap();
    for _ in 0..4 {
        assert_eq!(finish(&core, &b["challenge_id"], "000000").unwrap_err().code, "invalid_code");
    }
    assert_eq!(finish(&core, &b["challenge_id"], "000000").unwrap_err().code, "code_expired");
    assert_eq!(finish(&core, &b["challenge_id"], "004217").unwrap_err().code, "code_expired");
    assert!(!dir.join("session.json").exists());
}

#[test]
fn a_dead_code_is_code_expired() {
    let (core, fake, dir) = support::logged_out();
    let b = begin(&core, "foo@bar.com").unwrap();
    let code = fake.email_code("foo@bar.com").unwrap();
    fake.expire_email_codes();
    assert_eq!(finish(&core, &b["challenge_id"], &code).unwrap_err().code, "code_expired");
    // A challenge replaced by a second begin for the address.
    let c1 = begin(&core, "foo@bar.com").unwrap();
    let code1 = fake.email_code("foo@bar.com").unwrap();
    let c2 = begin(&core, "foo@bar.com").unwrap();
    assert_eq!(finish(&core, &c1["challenge_id"], &code1).unwrap_err().code, "code_expired");
    // Used once, then dead; the session file is left as the first sign-in wrote it.
    let code2 = fake.email_code("foo@bar.com").unwrap();
    finish(&core, &c2["challenge_id"], &code2).unwrap();
    let before = std::fs::read(dir.join("session.json")).unwrap();
    assert_eq!(finish(&core, &c2["challenge_id"], &code2).unwrap_err().code, "code_expired");
    assert_eq!(std::fs::read(dir.join("session.json")).unwrap(), before);
}

#[test]
fn relay_refusals_keep_their_codes() {
    let (core, fake, _dir) = support::logged_out();
    assert_eq!(begin(&core, "nope").unwrap_err().code, "invalid_email");
    assert_eq!(begin(&core, "a@mailinator.com").unwrap_err().code, "disposable_email");
    fake.fail_next(CODE_PATH, 429, "rate_limited");
    assert_eq!(begin(&core, "foo@bar.com").unwrap_err().code, "rate_limited");
    fake.fail_next_mail();
    assert_eq!(begin(&core, "foo@bar.com").unwrap_err().code, "email_send_failed");
    let b = begin(&core, "foo@bar.com").unwrap();
    let code = fake.email_code("foo@bar.com").unwrap();
    fake.fail_next(VERIFY_PATH, 429, "rate_limited");
    assert_eq!(finish(&core, &b["challenge_id"], &code).unwrap_err().code, "rate_limited");
    fake.fail_next(VERIFY_PATH, 400, "invalid_device");
    assert_eq!(finish(&core, &b["challenge_id"], &code).unwrap_err().code, "invalid_device");
}

#[test]
fn a_failed_mail_leaves_no_live_code_and_a_429_keeps_it() {
    let (core, fake, _dir) = support::logged_out();
    let c1 = begin(&core, "foo@bar.com").unwrap();
    let code1 = fake.email_code("foo@bar.com").unwrap();
    fake.fail_next_mail();
    assert_eq!(begin(&core, "foo@bar.com").unwrap_err().code, "email_send_failed");
    assert_eq!(finish(&core, &c1["challenge_id"], &code1).unwrap_err().code, "code_expired");
    let c2 = begin(&core, "foo@bar.com").unwrap();
    let code2 = fake.email_code("foo@bar.com").unwrap();
    fake.fail_next(CODE_PATH, 429, "rate_limited");
    assert_eq!(begin(&core, "foo@bar.com").unwrap_err().code, "rate_limited");
    finish(&core, &c2["challenge_id"], &code2).unwrap();
}

#[test]
fn a_relay_without_email_sign_in_is_email_sign_in_disabled() {
    let (core, _fake, dir) = with_options(FakeOptions { email_sign_in: false, ..FakeOptions::default() });
    assert_eq!(begin(&core, "foo@bar.com").unwrap_err().code, "email_sign_in_disabled");
    let (core, _fake, dir2) = with_options(FakeOptions { email_routes: false, ..FakeOptions::default() });
    assert_eq!(begin(&core, "foo@bar.com").unwrap_err().code, "email_sign_in_disabled");
    assert_eq!(finish(&core, &json!("c"), "123456").unwrap_err().code, "email_sign_in_disabled");
    let (core, fake, dir3) = support::logged_out();
    fake.fail_next(CODE_PATH, 404, "");
    assert_eq!(begin(&core, "foo@bar.com").unwrap_err().code, "email_sign_in_disabled");
    for d in [dir.join("session.json"), dir2.join("session.json"), dir3.join("session.json")] {
        assert!(!d.exists());
    }
}

#[test]
fn a_proxy_answer_without_a_body_is_http_status() {
    let (core, fake, dir) = support::logged_out();
    fake.fail_next(CODE_PATH, 502, "");
    assert_eq!(begin(&core, "foo@bar.com").unwrap_err().code, "http_502");
    fake.fail_next(CODE_PATH, 503, "");
    assert_eq!(begin(&core, "foo@bar.com").unwrap_err().code, "http_503");
    let b = begin(&core, "foo@bar.com").unwrap();
    let code = fake.email_code("foo@bar.com").unwrap();
    fake.fail_next(VERIFY_PATH, 504, "");
    assert_eq!(finish(&core, &b["challenge_id"], &code).unwrap_err().code, "http_504");
    assert!(!dir.join("session.json").exists());
}

#[test]
fn offline_is_network() {
    let dir = support::state_dir();
    let core = Core::new();
    support::configure(&core, "http://127.0.0.1:1", &dir, json!({}));
    assert_eq!(begin(&core, "foo@bar.com").unwrap_err().code, "network");
    assert_eq!(finish(&core, &json!("c"), "123456").unwrap_err().code, "network");
    assert!(!dir.join("session.json").exists());
}

#[test]
fn a_password_account_email_answers_switch_and_spends_the_code() {
    let (core, fake, dir) = support::logged_out();
    core.call("auth.login", json!({"email": "a@b.cd", "password": "pw"})).unwrap();
    let b = begin(&core, "a@b.cd").unwrap();
    let code = fake.email_code("a@b.cd").unwrap();
    assert_eq!(finish(&core, &b["challenge_id"], &code).unwrap_err().code, "switch_from_signed_in_device");
    assert_eq!(finish(&core, &b["challenge_id"], &code).unwrap_err().code, "code_expired");
    assert_eq!(session_json(&dir)["auth_method"], "password");
    // A session exists, so a stored token is there to leak: neither call may send it.
    for path in [CODE_PATH, VERIFY_PATH] {
        let sent = support::requests_to(&fake, path);
        assert!(!sent.is_empty(), "{path}");
        for r in sent {
            assert_eq!(support::header(&r, "Authorization"), None, "{path}");
        }
    }
}

#[test]
fn an_email_code_signs_into_the_google_account_with_that_address() {
    let (core, fake, _dir) = support::google_logged_out();
    let g = support::google_sign_in(&core, "sign_in").unwrap();
    core.call("auth.logout", json!({})).unwrap();
    let e = support::email_sign_in(&core, &fake, "google-user@shellx.test").unwrap();
    assert_eq!(e["user_id"], g["user_id"]);
    let list = core.call("account.identities.list", json!({})).unwrap();
    let providers: Vec<&str> = list["identities"].as_array().unwrap().iter().map(|i| i["provider"].as_str().unwrap()).collect();
    assert_eq!(providers, ["google", "email"]);
}

#[test]
fn email_sign_in_after_a_401_keeps_the_device_id_and_machine() {
    let (core, fake, dir) = support::logged_out();
    let first = support::email_sign_in(&core, &fake, "foo@bar.com").unwrap();
    core.call("machines.register", REG()).unwrap();
    fake.revoke_token(&fake.issued_token());
    assert_eq!(core.call("machines.list", json!({})).unwrap_err().code, "unauthorized");
    assert!(dir.join("machine.json").exists() && dir.join("device.key").exists());
    let second = support::email_sign_in(&core, &fake, "foo@bar.com").unwrap();
    assert_eq!((&second["user_id"], &second["device_id"]), (&first["user_id"], &first["device_id"]));
    let list = core.call("machines.list", json!({})).unwrap();
    assert_eq!(list["machines"][0]["is_this_machine"], true);
}

#[test]
fn params_are_checked() {
    let (core, fake, _dir) = support::logged_out();
    for p in [json!("x"), json!({}), json!({"email": 5})] {
        assert_eq!(core.call("auth.email.begin", p).unwrap_err().code, "invalid_params");
    }
    for p in [
        json!({}),
        json!({"challenge_id": "c"}),
        json!({"challenge_id": "", "code": "123456"}),
        json!({"challenge_id": 5, "code": "123456"}),
    ] {
        assert_eq!(core.call("auth.email.finish", p).unwrap_err().code, "invalid_params");
    }
    assert!(fake.requests().is_empty());
}

#[test]
fn secrets_never_reach_results_or_errors() {
    let (core, fake, _dir) = support::logged_out();
    fake.set_next_email_code("004217");
    let b = begin(&core, "foo@bar.com").unwrap();
    let challenge = b["challenge_id"].as_str().unwrap().to_string();
    let wrong = finish(&core, &b["challenge_id"], "000000").unwrap_err();
    let local = finish(&core, &b["challenge_id"], "12a456").unwrap_err();
    let ok = finish(&core, &b["challenge_id"], "004217").unwrap();
    let blob = ok.to_string();
    for secret in [fake.issued_token(), "004217".to_string(), challenge.clone()] {
        assert!(!blob.contains(&secret), "{secret}");
    }
    let expired = finish(&core, &b["challenge_id"], "004217").unwrap_err();
    fake.fail_next(CODE_PATH, 429, "rate_limited");
    let limited = begin(&core, "foo@bar.com").unwrap_err();
    let (core2, _fake2, _d) = with_options(FakeOptions { email_routes: false, ..FakeOptions::default() });
    let disabled = begin(&core2, "foo@bar.com").unwrap_err();
    let long = format!("{}@bar.com", "a".repeat(255 - "@bar.com".len()));
    let bad1 = begin(&core, "phu@ẽample.com").unwrap_err();
    let bad2 = begin(&core, &long).unwrap_err();
    for e in [&wrong, &expired, &limited, &disabled] {
        for secret in [challenge.as_str(), "004217", "000000", "foo@bar.com", fake.issued_token().as_str()] {
            assert!(!e.message.contains(secret), "{}: {secret}", e.code);
        }
    }
    assert!(!bad1.message.contains("phu@") && !bad1.message.contains("ẽample"));
    assert!(!bad2.message.contains(&long) && !bad2.message.contains("aaaa"));
    assert!(!local.message.contains("12a456") && !local.message.contains(&challenge));
    let parsed: shellx_core::api::EmailCodeResponse =
        serde_json::from_value(json!({"challenge_id": "CH-SECRET", "email": "foo@bar.com"})).unwrap();
    let dbg = format!("{parsed:?}");
    assert!(!dbg.contains("CH-SECRET") && !dbg.contains("foo@bar.com"), "{dbg}");
    assert_eq!((parsed.expires_in, parsed.resend_in), (600, 60));
}
