//! `/v2/shares` validation and list semantics of the fake API.
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde_json::{Value, json};
use shellx_fake_api::{FakeApi, FakeOptions};
use std::io::{Read, Write};

const ACCESS: &str = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"; // 43 chars

fn request(addr: &str, method: &str, path: &str, bearer: Option<&str>, body: Option<&Value>) -> (u16, Value) {
    let addr = addr.strip_prefix("http://").unwrap();
    let body = body.map(Value::to_string).unwrap_or_default();
    let auth = bearer.map(|t| format!("Authorization: Bearer {t}\r\n")).unwrap_or_default();
    let mut s = std::net::TcpStream::connect(addr).unwrap();
    write!(
        s,
        "{method} {path} HTTP/1.1\r\nHost: x\r\nConnection: close\r\nContent-Type: application/json\r\n{auth}Content-Length: {}\r\n\r\n{body}",
        body.len()
    )
    .unwrap();
    let mut resp = String::new();
    s.read_to_string(&mut resp).unwrap();
    let status = resp[9..12].parse().unwrap();
    let json = resp.split_once("\r\n\r\n").map(|(_, b)| b).and_then(|b| serde_json::from_str(b).ok()).unwrap_or(Value::Null);
    (status, json)
}

fn login(fake: &FakeApi) -> String {
    let key = URL_SAFE_NO_PAD.encode([9u8; 32]);
    let (st, l) = request(
        &fake.base_url,
        "POST",
        "/v1/auth/login",
        None,
        Some(&json!({"email":"a@b.c","password":"pw","device":{"kind":"desktop","name":"d","platform":"macos","public_key":key}})),
    );
    assert_eq!(st, 200, "{l}");
    l["token"].as_str().unwrap().to_string()
}

/// A fresh valid id per call (digits only, so always inside the alphabet).
fn fresh_id() -> String {
    static NEXT: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
    format!("{:08}", 20_000_000 + NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed))
}

fn create(fake: &FakeApi, token: &str) -> String {
    let (st, s) = request(
        &fake.base_url,
        "POST",
        "/v2/shares",
        Some(token),
        Some(&json!({"id": fresh_id(), "permission":"view","lifetime":"1h","access":ACCESS})),
    );
    assert_eq!(st, 201, "{s}");
    s["id"].as_str().unwrap().to_string()
}

#[test]
fn non_boolean_one_time_is_a_400() {
    let fake = FakeApi::start(FakeOptions::default());
    let token = login(&fake);
    for bad in [json!("yes"), json!(1), json!(0), json!([true]), json!({})] {
        let (st, body) = request(
            &fake.base_url,
            "POST",
            "/v2/shares",
            Some(&token),
            Some(&json!({"id": fresh_id(), "permission":"view","lifetime":"1h","access":ACCESS,"one_time":bad})),
        );
        assert_eq!(st, 400, "{bad}");
        assert_eq!(body["error"]["code"], "bad_request", "{bad}");
    }
    let (_, list) = request(&fake.base_url, "GET", "/v2/shares", Some(&token), None);
    assert!(list["shares"].as_array().unwrap().is_empty());
    // Absent, null and booleans are accepted.
    for ok in [json!({}), json!({"one_time": null}), json!({"one_time": false}), json!({"one_time": true})] {
        let mut body = json!({"id": fresh_id(), "permission":"view","lifetime":"1h","access":ACCESS});
        body.as_object_mut().unwrap().extend(ok.as_object().unwrap().clone());
        assert_eq!(request(&fake.base_url, "POST", "/v2/shares", Some(&token), Some(&body)).0, 201, "{ok}");
    }
}

#[test]
fn list_excludes_expired_shares_and_orders_by_created_at_then_id() {
    let fake = FakeApi::start(FakeOptions::default());
    let token = login(&fake);
    let ids: Vec<String> = (0..4).map(|_| create(&fake, &token)).collect();
    let far = u64::MAX / 2;
    // ids[0] expired; ids[1] and ids[2] created at the same instant; ids[3] created earliest.
    fake.set_share_times(&ids[0], 100, 1);
    fake.set_share_times(&ids[1], 200, far);
    fake.set_share_times(&ids[2], 200, far);
    fake.set_share_times(&ids[3], 150, far);
    let (st, list) = request(&fake.base_url, "GET", "/v2/shares", Some(&token), None);
    assert_eq!(st, 200);
    let got: Vec<String> = list["shares"].as_array().unwrap().iter().map(|s| s["id"].as_str().unwrap().to_string()).collect();
    let (lo, hi) = if ids[1] < ids[2] { (&ids[1], &ids[2]) } else { (&ids[2], &ids[1]) };
    assert_eq!(got, [ids[3].clone(), lo.clone(), hi.clone()]);
    assert!(!got.contains(&ids[0]));
}

#[test]
fn id_is_required_and_a_duplicate_is_409_share_id_taken() {
    let fake = FakeApi::start(FakeOptions::default());
    let token = login(&fake);
    for bad in [json!(null), json!("abc"), json!("ilou0000"), json!(12345678)] {
        let (st, body) = request(
            &fake.base_url, "POST", "/v2/shares", Some(&token),
            Some(&json!({"id": bad, "permission":"view","lifetime":"1h","access":ACCESS})),
        );
        assert_eq!((st, body["error"]["code"].as_str()), (400, Some("bad_request")), "{bad}");
    }
    let id = create(&fake, &token);
    let (st, body) = request(
        &fake.base_url, "POST", "/v2/shares", Some(&token),
        Some(&json!({"id": id, "permission":"view","lifetime":"1h","access":ACCESS})),
    );
    assert_eq!((st, body["error"]["code"].as_str()), (409, Some("share_id_taken")));
}
