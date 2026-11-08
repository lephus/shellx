//! `shellx-core-cli`, including the e2e-only `auth.google.e2e`.
mod support;

use serde_json::{Value, json};
use std::process::Command;

fn run(cfg: &Value, method: &str, params: &str) -> (i32, Value) {
    let out = Command::new(env!("CARGO_BIN_EXE_shellx-core-cli"))
        .arg(method)
        .arg(params)
        .env("SHELLX_CORE_CONFIG", cfg.to_string())
        .output()
        .unwrap();
    let text = String::from_utf8_lossy(&out.stdout).to_string();
    let last = text.trim().lines().last().unwrap_or("null").to_string();
    (out.status.code().unwrap_or(-1), serde_json::from_str(&last).unwrap_or(Value::Null))
}

fn config(fake: &shellx_fake_api::FakeApi, dir: &std::path::Path) -> Value {
    let mut c = json!({"api_base": fake.base_url, "state_dir": dir.to_str().unwrap()});
    for (k, v) in support::google(fake).as_object().unwrap() {
        c[k] = v.clone();
    }
    c
}

#[test]
fn cli_google_e2e_signs_in_without_a_person() {
    let fake = support::fake();
    let dir = support::state_dir();
    let cfg = config(&fake, &dir);
    let (_, out) = run(&cfg, "auth.google.e2e", r#"{"purpose":"sign_in"}"#);
    assert_eq!(out["ok"]["email"], "google-user@shellx.test", "{out}");
    assert_eq!(out["ok"]["auth_method"], "google");
    let (_, out) = run(&cfg, "machines.list", "{}");
    assert_eq!(out, json!({"ok": {"machines": []}}));
}

#[test]
fn cli_google_e2e_refuses_a_real_google_url() {
    let fake = support::fake();
    let dir = support::state_dir();
    let cfg = json!({"api_base": fake.base_url, "state_dir": dir.to_str().unwrap(), "google_client_id": "x"});
    let (code, out) = run(&cfg, "auth.google.e2e", r#"{"purpose":"sign_in"}"#);
    assert_eq!(code, 1);
    assert_eq!(out["error"]["code"], "invalid_params");
}
