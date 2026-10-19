mod support;

use serde_json::{Value, json};
use shellx_core::Core;
use shellx_fake_api::{FakeApi, FakeOptions};

const MAC: &str = "https://dl.shellx.pro/ShellX-2.0.1.dmg";
const WIN: &str = "https://dl.shellx.pro/ShellX-Setup-2.0.1.exe";

fn body(min_agent: &str, latest: &str) -> Value {
    json!({
        "min_agent": min_agent,
        "min_mobile": "1.0.0",
        "latest_agent": {"version": latest, "mac_url": MAC, "win_url": WIN},
    })
}

fn check(app: &str, platform: &str, version_body: Value) -> Value {
    let fake = FakeApi::start(FakeOptions { version_body, ..FakeOptions::default() });
    let dir = support::state_dir();
    let core = Core::new();
    support::configure(&core, &fake.base_url, &dir, json!({"app_version": app, "platform": platform}));
    let r = core.call("version.check", json!({})).unwrap();
    assert_eq!(fake.requests()[0].method, "GET");
    assert_eq!(fake.requests()[0].path, "/v1/version");
    r
}

#[test]
fn version_check_statuses() {
    for (app, min, latest, want) in [
        ("1.9.9", "2.0.0", "2.0.0", "update_required"),
        ("2.0.0", "2.0.0", "2.0.1", "update_available"),
        ("2.0.0", "2.0.0", "2.0.0", "ok"),
        ("2.0.1", "2.0.0", "2.0.0", "ok"),
        ("1.10.0", "1.9.0", "1.10.0", "ok"),
        ("1.9.0", "1.10.0", "1.10.0", "update_required"),
        ("2.0.0-beta.1", "2.0.0", "2.0.0", "update_required"),
        ("2.0.0", "1.0.0", "2.0.0-beta.1", "ok"),
        ("2.0.0+build.7", "2.0.0", "2.0.0", "ok"),
        ("1.0.0", "1.0.0", "3.0.0", "update_available"),
    ] {
        let r = check(app, "macos", body(min, latest));
        assert_eq!(r["status"], want, "app {app} min {min} latest {latest}");
        assert_eq!(r["min_version"], min);
        assert_eq!(r["latest_version"], latest);
    }
}

#[test]
fn download_url_follows_platform() {
    assert_eq!(check("2.0.0", "macos", body("2.0.0", "2.0.1"))["download_url"], MAC);
    assert_eq!(check("2.0.0", "windows", body("2.0.0", "2.0.1"))["download_url"], WIN);
}

#[test]
fn unparsable_versions_never_force_an_update() {
    // A version the strict parser rejects is "nothing to compare against".
    assert_eq!(check("2.0.0", "macos", body("02.0.0", "2.0.0"))["status"], "ok");
    assert_eq!(check("2.0.0", "macos", body("2.0", "2.0.0"))["status"], "ok");
    assert_eq!(check("dev", "macos", body("9.0.0", "9.0.0"))["status"], "ok");
    let r = check("2.0.0", "macos", json!({"min_mobile": "1.0.0"}));
    assert_eq!(r["status"], "ok");
    assert_eq!(r["min_version"], Value::Null);
    assert_eq!(r["latest_version"], Value::Null);
    assert_eq!(r["download_url"], Value::Null);
}

#[test]
fn version_check_server_error_passes_code() {
    let fake = FakeApi::start(FakeOptions { version_body: json!("not an object"), ..FakeOptions::default() });
    let dir = support::state_dir();
    let core = Core::new();
    support::configure(&core, &fake.base_url, &dir, json!({}));
    assert_eq!(core.call("version.check", json!({})).unwrap_err().code, "server");
}
