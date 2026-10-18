use serde_json::json;
use shellx_core::ffi::{shellx_core_call, shellx_core_free};
use shellx_core::Core;
use std::ffi::{CStr, CString};

fn env(out: &str) -> serde_json::Value {
    serde_json::from_str(out).unwrap()
}

#[test]
fn unknown_method_is_error_envelope() {
    assert_eq!(env(&Core::new().call_json("nope", "{}"))["error"]["code"], "unknown_method");
}

#[test]
fn invalid_json_is_error_envelope() {
    assert_eq!(env(&Core::new().call_json("config.set", "{"))["error"]["code"], "invalid_json");
}

#[test]
fn config_rejects_plain_http_off_loopback() {
    let r = Core::new().call("config.set", json!({"api_base":"http://relay.shellx.pro","state_dir":"/tmp/x"}));
    assert_eq!(r.unwrap_err().code, "invalid_params");
}

#[test]
fn config_accepts_loopback_http_and_requires_absolute_state_dir() {
    let c = Core::new();
    assert_eq!(c.call("config.set", json!({"api_base":"http://127.0.0.1:9","state_dir":"/tmp/x"})).unwrap(), json!({}));
    assert_eq!(c.call("config.set", json!({"api_base":"http://localhost:9","state_dir":"/tmp/x"})).unwrap(), json!({}));
    assert_eq!(c.call("config.set", json!({"api_base":"https://relay.shellx.pro","state_dir":"/tmp/x"})).unwrap(), json!({}));
    let e = c.call("config.set", json!({"api_base":"http://127.0.0.1:9","state_dir":"rel/dir"})).unwrap_err();
    assert_eq!(e.code, "invalid_params");
}

#[test]
fn config_rejects_bad_optional_fields_and_lookalike_hosts() {
    let c = Core::new();
    for p in [
        json!({"api_base":"http://127.0.0.1.evil.com","state_dir":"/tmp/x"}),
        json!({"api_base":"http://localhost@evil.com","state_dir":"/tmp/x"}),
        json!({"api_base":"ftp://x","state_dir":"/tmp/x"}),
        json!({"api_base":"https://","state_dir":"/tmp/x"}),
        json!({"api_base":"https://a.b","state_dir":"/tmp/x","platform":"linux"}),
        json!({"api_base":"https://a.b","state_dir":"/tmp/x","app_version":5}),
        json!({"api_base":"https://a.b","state_dir":"/tmp/x/"}),
        json!({"api_base":"https://a.b","state_dir":"/tmp/x/."}),
        json!({"api_base":"https://a.b","state_dir":"/tmp/x/.."}),
        json!([]),
    ] {
        assert_eq!(c.call("config.set", p.clone()).unwrap_err().code, "invalid_params", "{p}");
    }
    assert!(c.call("config.set", json!({"api_base":"https://a.b","state_dir":"/tmp/x","platform":"windows"})).is_ok());
}

#[test]
fn calls_before_config_fail_not_configured() {
    assert_eq!(Core::new().call("machines.list", json!({})).unwrap_err().code, "not_configured");
}

#[test]
fn unknown_beats_not_configured_and_known_unimplemented_after_config_is_unknown() {
    let c = Core::new();
    assert_eq!(c.call("bogus.thing", json!({})).unwrap_err().code, "unknown_method");
    c.call("config.set", json!({"api_base":"https://a.b","state_dir":"/tmp/x"})).unwrap();
    assert_eq!(c.call("machines.list", json!({})).unwrap_err().code, "unknown_method");
}

#[test]
fn ok_envelope_shape() {
    let out = env(&Core::new().call_json("config.set", r#"{"api_base":"https://a.b","state_dir":"/tmp/x"}"#));
    assert_eq!(out, json!({"ok": {}}));
}

#[test]
fn ffi_handles_null_and_frees() {
    unsafe {
        let p = shellx_core_call(std::ptr::null(), std::ptr::null());
        assert_eq!(env(CStr::from_ptr(p).to_str().unwrap())["error"]["code"], "invalid_params");
        shellx_core_free(p);
        shellx_core_free(std::ptr::null_mut());
        let m = CString::new("nope").unwrap();
        let bad = [0xffu8, 0];
        let p = shellx_core_call(m.as_ptr(), bad.as_ptr() as *const _);
        assert_eq!(env(CStr::from_ptr(p).to_str().unwrap())["error"]["code"], "invalid_json");
        shellx_core_free(p);
    }
}

#[test]
fn ffi_is_safe_under_concurrency() {
    let hs: Vec<_> = (0..8)
        .map(|_| {
            std::thread::spawn(|| {
                let m = CString::new("nope").unwrap();
                let j = CString::new("{}").unwrap();
                for _ in 0..200 {
                    unsafe {
                        let p = shellx_core_call(m.as_ptr(), j.as_ptr());
                        let v = env(CStr::from_ptr(p).to_str().unwrap());
                        assert_eq!(v["error"]["code"], "unknown_method");
                        shellx_core_free(p);
                    }
                }
            })
        })
        .collect();
    for h in hs {
        h.join().unwrap();
    }
}
