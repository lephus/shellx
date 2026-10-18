//! Tickets must be byte-exact per the ledger "Ticket format" (cmux-relay v2).
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use hmac::{Hmac, Mac};
use serde_json::{Value, json};
use sha2::Sha256;
use shellx_fake_api::{FakeApi, FakeOptions};
use std::io::{Read, Write};

fn post(addr: &str, path: &str, bearer: Option<&str>, body: &Value) -> (u16, Value) {
    let addr = addr.strip_prefix("http://").unwrap();
    let body = body.to_string();
    let auth = bearer.map(|t| format!("Authorization: Bearer {t}\r\n")).unwrap_or_default();
    let mut s = std::net::TcpStream::connect(addr).unwrap();
    write!(
        s,
        "POST {path} HTTP/1.1\r\nHost: x\r\nConnection: close\r\nContent-Type: application/json\r\n{auth}Content-Length: {}\r\n\r\n{body}",
        body.len()
    )
    .unwrap();
    let mut resp = String::new();
    s.read_to_string(&mut resp).unwrap();
    let status = resp[9..12].parse().unwrap();
    let json = resp.split_once("\r\n\r\n").map(|(_, b)| b).and_then(|b| serde_json::from_str(b).ok()).unwrap_or(Value::Null);
    (status, json)
}

fn setup(fake: &FakeApi) -> (String, String, String) {
    let key = URL_SAFE_NO_PAD.encode([9u8; 32]);
    let (_, l) = post(
        &fake.base_url,
        "/v1/auth/login",
        None,
        &json!({"email":"a@b.c","password":"pw","device":{"kind":"desktop","name":"d","platform":"macos","public_key":key}}),
    );
    let token = l["token"].as_str().unwrap().to_string();
    let (st, m) = post(
        &fake.base_url,
        "/v2/machines",
        Some(&token),
        &json!({"name":"m","platform":"macos","os_version":"1","app_version":"1","noise_public_key_b64":key}),
    );
    assert_eq!(st, 200, "{m}");
    (token, m["machine_id"].as_str().unwrap().to_string(), m["slot"].as_str().unwrap().to_string())
}

fn sign(secret: &[u8], payload: &str) -> String {
    let mut mac = Hmac::<Sha256>::new_from_slice(secret).unwrap();
    mac.update(payload.as_bytes());
    URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes())
}

fn check(opts: &FakeOptions, ticket: &str, permission: &str, role: &str, slot: &str) {
    let parts: Vec<&str> = ticket.split('.').collect();
    assert_eq!(parts.len(), 3);
    assert_eq!(parts[0], "v2");
    assert!(ticket.len() <= 4096);
    let claims: Value = serde_json::from_slice(&URL_SAFE_NO_PAD.decode(parts[1]).unwrap()).unwrap();
    assert_eq!(claims["version"], 2);
    assert_eq!(claims["issuer"], "shellx-relay");
    assert_eq!(claims["permission"], permission);
    assert_eq!(claims["role"], role);
    assert_eq!(claims["slot"], slot);
    assert!(claims["circuit"].is_null() && claims["lane"].is_null() && claims["generation"].is_null());
    let (iat, exp) = (claims["issued_at_unix"].as_u64().unwrap(), claims["expires_at_unix"].as_u64().unwrap());
    assert_eq!(exp - iat, opts.ticket_ttl_secs);
    assert!(exp - iat > 0 && exp - iat <= 300);
    let payload = format!("cmux-relay-ticket-v2\n2\nshellx-relay\n{permission}\n{role}\n{slot}\n\n\n\n{iat}\n{exp}");
    assert_eq!(parts[2], sign(&opts.hmac_secret, &payload), "signature mismatch");
}

#[test]
fn register_and_connect_tickets_are_byte_exact() {
    let opts = FakeOptions::default();
    let fake = FakeApi::start(opts.clone());
    let (token, id, slot) = setup(&fake);
    let (st, r) = post(&fake.base_url, "/v2/relay/tickets", Some(&token), &json!({"machine_id":id,"permission":"register"}));
    assert_eq!(st, 200, "{r}");
    assert_eq!(r["relay_url"], opts.relay_url.as_str());
    check(&opts, r["ticket"].as_str().unwrap(), "register", "daemon", &slot);
    let (st, r) = post(
        &fake.base_url,
        "/v2/relay/tickets",
        Some(&token),
        &json!({"machine_id":id,"permission":"connect","target_machine_id":id}),
    );
    assert_eq!(st, 200, "{r}");
    check(&opts, r["ticket"].as_str().unwrap(), "connect", "client", &slot);
}

#[test]
fn ticket_rules() {
    let fake = FakeApi::start(FakeOptions::default());
    let (token, id, _slot) = setup(&fake);
    let url = &fake.base_url;
    let t = |tok: Option<&str>, b: Value| post(url, "/v2/relay/tickets", tok, &b).0;
    assert_eq!(t(None, json!({"machine_id":id,"permission":"register"})), 401);
    assert_eq!(t(Some(&token), json!({"machine_id":id,"permission":"bogus"})), 400);
    assert_eq!(t(Some(&token), json!({"machine_id":id,"permission":"connect"})), 400);
    assert_eq!(t(Some(&token), json!({"machine_id":"nope","permission":"register"})), 404);
    // register is only ever for the caller's own machine
    assert_eq!(t(Some(&token), json!({"machine_id":id,"permission":"register","target_machine_id":"other"})), 400);
}
