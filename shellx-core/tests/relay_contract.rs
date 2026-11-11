//! Holds the fake relay (`shellx-fake-api`) to `relay/contract/desktop-api.json`, the file
//! `relay/test/desktop-contract.test.ts` holds the real relay to: the same answers (keys, types, null) and
//! the same refusals. The file is read at run time; nothing compiles it in.
//!
//! Shapes: an object has exactly these keys (a key ending in `?` may be absent); a one-element array is a
//! non-empty array whose every element matches; a string is type tokens (`string`, `integer`, `number`,
//! `boolean`, `null`) joined by `|`; `null` is an empty body.

use base64::Engine;
use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use serde_json::{Value, json};
use shellx_fake_api::{FakeApi, FakeOptions, fetch};
use std::collections::HashSet;
use std::sync::atomic::{AtomicU64, Ordering};

fn contract() -> Value {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../relay/contract/desktop-api.json");
    let text = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{path}: {e}"));
    serde_json::from_str(&text).unwrap_or_else(|e| panic!("{path}: {e}"))
}

fn type_matches(v: &Value, token: &str) -> bool {
    match token {
        "string" => v.is_string(),
        "integer" => v.is_i64() || v.is_u64(),
        "number" => v.is_number(),
        "boolean" => v.is_boolean(),
        "null" => v.is_null(),
        other => panic!("unknown type token {other}"),
    }
}

/// Every way `v` differs from `shape` (empty when it matches).
fn check_shape(v: &Value, shape: &Value, path: &str) -> Vec<String> {
    match shape {
        Value::Null => vec![format!("{path}: null is only a whole (empty) body")],
        Value::String(s) => {
            if s.split('|').any(|t| type_matches(v, t)) {
                vec![]
            } else {
                vec![format!("{path}: {v} is not {s}")]
            }
        }
        Value::Array(items) => {
            let [item] = items.as_slice() else { return vec![format!("{path}: an array shape has exactly one element")] };
            match v.as_array() {
                Some(a) if !a.is_empty() => {
                    a.iter().enumerate().flat_map(|(i, x)| check_shape(x, item, &format!("{path}[{i}]"))).collect()
                }
                _ => vec![format!("{path}: {v} is not a non-empty array")],
            }
        }
        Value::Object(fields) => {
            let Some(obj) = v.as_object() else { return vec![format!("{path}: {v} is not an object")] };
            let mut problems = Vec::new();
            let mut names = HashSet::new();
            for (key, sub) in fields {
                let (name, optional) = key.strip_suffix('?').map_or((key.as_str(), false), |n| (n, true));
                names.insert(name);
                match obj.get(name) {
                    None if optional => {}
                    None => problems.push(format!("{path}.{name}: missing")),
                    Some(x) => problems.extend(check_shape(x, sub, &format!("{path}.{name}"))),
                }
            }
            problems.extend(obj.keys().filter(|k| !names.contains(k.as_str())).map(|k| format!("{path}.{k}: not in the contract")));
            problems
        }
        other => vec![format!("{path}: {other} is not a shape")],
    }
}

fn body_problems(text: &str, shape: &Value) -> Vec<String> {
    if shape.is_null() {
        return if text.is_empty() { vec![] } else { vec![format!("body: expected none, got {text}")] };
    }
    match serde_json::from_str::<Value>(text) {
        Ok(v) => check_shape(&v, shape, "body"),
        Err(_) => vec![format!("body: not JSON: {text}")],
    }
}

static SEQ: AtomicU64 = AtomicU64::new(1);

fn next() -> u64 {
    SEQ.fetch_add(1, Ordering::Relaxed)
}

/// A fresh 32-byte key, base64url without padding.
fn fresh_key() -> String {
    let mut b = [0x5au8; 32];
    b[..8].copy_from_slice(&next().to_le_bytes());
    URL_SAFE_NO_PAD.encode(b)
}

fn fresh_email() -> String {
    format!("contract-{}@shellx.test", next())
}

struct Relay {
    fake: FakeApi,
}

impl Relay {
    fn new() -> Relay {
        Relay { fake: FakeApi::start(FakeOptions::default()) }
    }

    fn call(&self, method: &str, path: &str, bearer: Option<&str>, body: Option<&Value>) -> (u16, String) {
        fetch(method, &format!("{}{path}", self.fake.base_url), bearer, body).unwrap_or_else(|e| panic!("{method} {path}: {e}"))
    }

    fn json(&self, method: &str, path: &str, bearer: Option<&str>, body: Option<&Value>, want: u16) -> Value {
        let (status, text) = self.call(method, path, bearer, body);
        assert_eq!(status, want, "{method} {path}: {text}");
        serde_json::from_str(&text).unwrap_or_else(|_| panic!("{method} {path}: not JSON: {text}"))
    }

    /// A desktop of `email`'s account (`POST /v1/auth/login`, a new device key); its token.
    fn desktop(&self, email: &str) -> String {
        let device = json!({"kind":"desktop","name":"PC","platform":"windows","public_key": fresh_key()});
        let v = self.json("POST", "/v1/auth/login", None, Some(&json!({"email": email, "password": "pw", "device": device})), 200);
        v["token"].as_str().expect("token").to_string()
    }

    /// Registers the caller's machine (valid values, a fresh key); its id and key.
    fn machine(&self, token: &str) -> (String, String) {
        let key = fresh_key();
        let (status, text) = self.call("POST", "/v2/machines", Some(token), Some(&machine_body(&key)));
        assert!(status == 200 || status == 201, "register: {status} {text}");
        let v: Value = serde_json::from_str(&text).expect("register answer");
        (v["machine_id"].as_str().expect("machine_id").to_string(), key)
    }

    /// Two desktops of one account, each with its machine: (token, machine id, key) for each.
    fn two_desktops(&self) -> [(String, String, String); 2] {
        let email = fresh_email();
        [0, 1].map(|_| {
            let token = self.desktop(&email);
            let (id, key) = self.machine(&token);
            (token, id, key)
        })
    }

    /// Asks for a code for `email` and verifies it from a new desktop; the verify answer.
    fn email_sign_in(&self, email: &str) -> (u16, String) {
        let v = self.json("POST", "/v1/auth/email/code", None, Some(&json!({"email": email, "locale": "en"})), 202);
        let code = self.fake.email_code(email).expect("a mailed code");
        let device = json!({"kind":"desktop","name":"Mac-Studio","platform":"macos","public_key": fresh_key()});
        self.call("POST", "/v1/auth/email/verify", None, Some(&json!({"challenge_id": v["challenge_id"], "code": code, "device": device})))
    }
}

fn machine_body(key: &str) -> Value {
    json!({"name":"Mac","platform":"macos","os_version":"15.2","app_version":"1.0.0","noise_public_key_b64": key})
}

const RECIPES: &[&str] = &[
    "error|",
    "GET /v2/machines|",
    "POST /v2/machines|new",
    "POST /v2/machines|again",
    "POST /v2/machines/:id/heartbeat|",
    "POST /v2/pairings|",
    "GET /v2/pairings?role=requester|approved",
    "POST /v2/relay/tickets|register",
    "GET /v1/version|",
    "POST /v1/auth/email/code|",
    "POST /v1/auth/email/verify|",
    "GET /v1/account/identities|email sign-in",
];

/// How each answer of the contract is produced on the fake relay.
fn answer(r: &Relay, key: &str) -> (u16, String) {
    match key {
        "error|" => r.call("GET", "/v2/machines", None, None),
        "GET /v2/machines|" => {
            let [(one, _, _), (two, m2, _)] = r.two_desktops();
            // One machine has a heartbeat and one has none: last_seen_unix is an integer and null.
            let (beat, text) = r.call("POST", &format!("/v2/machines/{m2}/heartbeat"), Some(&two), None);
            assert!((200..300).contains(&beat), "heartbeat: {beat} {text}");
            let out = r.call("GET", "/v2/machines", Some(&one), None);
            let v: Value = serde_json::from_str(&out.1).unwrap_or(Value::Null);
            assert_eq!(v["machines"].as_array().map(Vec::len), Some(2), "{}", out.1);
            out
        }
        "POST /v2/machines|new" => {
            let token = r.desktop(&fresh_email());
            r.call("POST", "/v2/machines", Some(&token), Some(&machine_body(&fresh_key())))
        }
        "POST /v2/machines|again" => {
            let token = r.desktop(&fresh_email());
            let body = machine_body(&fresh_key());
            let (first, text) = r.call("POST", "/v2/machines", Some(&token), Some(&body));
            assert!(first == 200 || first == 201, "first register: {first} {text}");
            r.call("POST", "/v2/machines", Some(&token), Some(&body))
        }
        "POST /v2/machines/:id/heartbeat|" => {
            let token = r.desktop(&fresh_email());
            let (id, _) = r.machine(&token);
            r.call("POST", &format!("/v2/machines/{id}/heartbeat"), Some(&token), None)
        }
        "POST /v2/pairings|" => {
            let [(one, m1, k1), (_, m2, _)] = r.two_desktops();
            let body = json!({"from_machine_id": m1, "to_machine_id": m2, "requester_x25519_b64": k1});
            r.call("POST", "/v2/pairings", Some(&one), Some(&body))
        }
        "GET /v2/pairings?role=requester|approved" => {
            let [(one, m1, k1), (two, m2, _)] = r.two_desktops();
            let body = json!({"from_machine_id": m1, "to_machine_id": m2, "requester_x25519_b64": k1});
            let p = r.json("POST", "/v2/pairings", Some(&one), Some(&body), 201);
            let pid = p["pairing_id"].as_str().expect("pairing_id");
            let sealed = json!({"sealed_invite_b64": STANDARD.encode([0x42u8; 96])});
            let (st, text) = r.call("POST", &format!("/v2/pairings/{pid}/approve"), Some(&two), Some(&sealed));
            assert_eq!(st, 204, "approve: {text}");
            r.call("GET", "/v2/pairings?role=requester", Some(&one), None)
        }
        "POST /v2/relay/tickets|register" => {
            let token = r.desktop(&fresh_email());
            let (id, _) = r.machine(&token);
            r.call("POST", "/v2/relay/tickets", Some(&token), Some(&json!({"machine_id": id, "permission": "register"})))
        }
        "GET /v1/version|" => r.call("GET", "/v1/version", None, None),
        "POST /v1/auth/email/code|" => {
            r.call("POST", "/v1/auth/email/code", None, Some(&json!({"email": fresh_email(), "locale": "en"})))
        }
        "POST /v1/auth/email/verify|" => r.email_sign_in(&fresh_email()),
        "GET /v1/account/identities|email sign-in" => {
            let (st, text) = r.email_sign_in(&fresh_email());
            assert_eq!(st, 200, "verify: {text}");
            let v: Value = serde_json::from_str(&text).expect("verify answer");
            r.call("GET", "/v1/account/identities", v["token"].as_str(), None)
        }
        other => panic!("no recipe for {other}"),
    }
}

/// How each request route of the contract is sent: a fresh account per case.
fn send(r: &Relay, route: &str, body: &Value) -> (u16, String) {
    match route {
        "POST /v2/machines" => {
            let token = r.desktop(&fresh_email());
            let mut full = json!({"noise_public_key_b64": fresh_key()});
            for (k, v) in body.as_object().expect("an object body") {
                full[k] = v.clone();
            }
            r.call("POST", "/v2/machines", Some(&token), Some(&full))
        }
        "POST /v1/auth/email/code" => r.call("POST", "/v1/auth/email/code", None, Some(body)),
        other => panic!("no sender for {other}"),
    }
}

fn entry_key(e: &Value) -> String {
    format!("{}|{}", e["route"].as_str().expect("route"), e["case"].as_str().unwrap_or(""))
}

#[test]
fn the_checker_finds_drift() {
    let shape = json!({"a": "string", "b?": "integer|null", "c": [{"d": "boolean"}]});
    let check = |v: Value| check_shape(&v, &shape, "v");
    assert!(check(json!({"a": "x", "c": [{"d": true}]})).is_empty());
    assert!(check(json!({"a": "x", "b": null, "c": [{"d": false}]})).is_empty());
    assert_eq!(check(json!({"c": [{"d": true}]})), ["v.a: missing"]);
    assert_eq!(check(json!({"a": "x", "c": [{"d": true}], "e": 1})), ["v.e: not in the contract"]);
    assert_eq!(check(json!({"a": "x", "b": 1.5, "c": [{"d": true}]})), ["v.b: 1.5 is not integer|null"]);
    assert_eq!(check(json!({"a": "x", "c": []})), ["v.c: [] is not a non-empty array"]);
    assert_eq!(body_problems("{}", &Value::Null), ["body: expected none, got {}"]);
}

#[test]
fn fake_answers_in_the_relays_shapes() {
    let c = contract();
    let entries = c["responses"].as_array().expect("responses");
    let mut keys: Vec<String> = entries.iter().map(entry_key).collect();
    keys.sort();
    let mut known: Vec<String> = RECIPES.iter().map(|k| k.to_string()).collect();
    known.sort();
    assert_eq!(keys, known, "one recipe per answer");

    let r = Relay::new();
    let mut problems = Vec::new();
    for e in entries {
        let key = entry_key(e);
        let (status, text) = answer(&r, &key);
        if let Some(want) = e["status"].as_u64()
            && u64::from(status) != want
        {
            problems.push(format!("{key}: status {status}, the relay answers {want} ({text})"));
        }
        problems.extend(body_problems(&text, &e["body"]).into_iter().map(|p| format!("{key}: {p}")));
    }
    assert!(problems.is_empty(), "the fake relay differs from the contract:\n{}", problems.join("\n"));
}

#[test]
fn fake_refuses_what_the_relay_refuses() {
    let c = contract();
    let error_shape = c["responses"].as_array().expect("responses").iter().find(|e| e["route"] == "error").expect("error entry")["body"].clone();
    let r = Relay::new();
    let mut problems = Vec::new();
    for route in c["requests"].as_array().expect("requests") {
        let name = route["route"].as_str().expect("route");
        for case in route["cases"].as_array().expect("cases") {
            let label = format!("{name} {}", case["label"].as_str().expect("label"));
            let mut body = route["base"].clone();
            for (k, v) in case["set"].as_object().expect("set") {
                body[k] = v.clone();
            }
            let (status, text) = send(&r, name, &body);
            let want = case["status"].as_u64().expect("status");
            if u64::from(status) != want {
                problems.push(format!("{label}: status {status}, the relay answers {want} ({text})"));
                continue;
            }
            if let Some(code) = case["error"].as_str() {
                problems.extend(body_problems(&text, &error_shape).into_iter().map(|p| format!("{label}: {p}")));
                let got: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
                if got["error"]["code"] != code {
                    problems.push(format!("{label}: error {}, the relay answers {code}", got["error"]["code"]));
                }
            }
        }
    }
    assert!(problems.is_empty(), "the fake relay differs from the contract:\n{}", problems.join("\n"));
}
