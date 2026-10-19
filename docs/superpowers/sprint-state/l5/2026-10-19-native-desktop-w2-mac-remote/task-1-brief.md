### Task 1: `shellx-core` workspace, C ABI, envelope, `config.set`

**Files:**
- Create: `shellx-core/Cargo.toml`, `shellx-core/Cargo.lock`, `shellx-core/include/shellx_core.h`, `shellx-core/src/{lib.rs,ffi.rs,envelope.rs,config.rs}`, `shellx-core/src/bin/shellx-core-cli.rs`, `shellx-core/tests/ffi.rs`, `shellx-core/tests/c/smoke.c`, `shellx-core/scripts/c-smoke.sh`, `shellx-core/scripts/check_deps.py`
- Modify: `.gitignore` (`shellx-core/target/`)

**Interfaces:**
- Produces (C, K3 verbatim): `char *shellx_core_call(const char *method, const char *json_in);` `void shellx_core_free(char *ptr);` — output is never NULL; caller frees with `shellx_core_free`; thread-safe.
- Produces (Rust): `pub struct Core` with `pub fn new() -> Core`, `pub fn call(&self, method: &str, params: serde_json::Value) -> Result<serde_json::Value, CoreError>`, `pub fn call_json(&self, method: &str, json_in: &str) -> String` (envelope). `pub struct CoreError { pub code: String, pub message: String }`. FFI uses one process-wide `static CORE: OnceLock<Core>`.
- Envelope: success `{"ok": <value>}`; failure `{"error": {"code": "<code>", "message": "<text>"}}`. Core-local codes: `invalid_json`, `invalid_params`, `unknown_method`, `not_configured`, `not_logged_in`, `not_registered`, `network`, `server`, `state_dir_insecure`, `state_file_insecure`, `io`, `crypto`, `invite_invalid`, `pairing_not_pending`, `fingerprint_mismatch`, `contract_missing_requester_key`, `panic`. Server `{"error":{"code"}}` bodies pass their code through verbatim (e.g. `invalid_credentials`, `forbidden`, `rate_limited`); other non-2xx → `http_<status>`.
- `config.set {api_base, state_dir, app_version?, os_version?, platform?, device_name?}` → `{}`. `api_base` must be `https://…`, or `http://` only for host `127.0.0.1`/`localhost`; `state_dir` absolute; `platform` ∈ `macos|windows` (default from `cfg!(target_os)`); `app_version` default `"2.0.0"`. Re-callable (replaces config).
- `shellx-core-cli <method> '<json>'` prints the envelope; reads `SHELLX_CORE_CONFIG` (JSON for `config.set`) first if set.

- [ ] **Step 1: Write the failing tests** (`tests/ffi.rs`)

```rust
fn env(out: &str) -> serde_json::Value { serde_json::from_str(out).unwrap() }
#[test] fn unknown_method_is_error_envelope() {
    assert_eq!(env(&Core::new().call_json("nope", "{}"))["error"]["code"], "unknown_method");
}
#[test] fn invalid_json_is_error_envelope() {
    assert_eq!(env(&Core::new().call_json("config.set", "{"))["error"]["code"], "invalid_json");
}
#[test] fn config_rejects_plain_http_off_loopback() {
    let r = Core::new().call("config.set", json!({"api_base":"http://relay.shellx.pro","state_dir":"/tmp/x"}));
    assert_eq!(r.unwrap_err().code, "invalid_params");
}
#[test] fn config_accepts_loopback_http_and_requires_absolute_state_dir() { /* http://127.0.0.1:9 ok; "rel/dir" → invalid_params */ }
#[test] fn calls_before_config_fail_not_configured() {
    assert_eq!(Core::new().call("machines.list", json!({})).unwrap_err().code, "not_configured");
}
#[test] fn ffi_handles_null_and_frees() { unsafe {
    let p = shellx_core_call(std::ptr::null(), std::ptr::null());
    assert_eq!(env(CStr::from_ptr(p).to_str().unwrap())["error"]["code"], "invalid_params");
    shellx_core_free(p); shellx_core_free(std::ptr::null_mut());
} }
#[test] fn ffi_is_safe_under_concurrency() { /* 8 threads × 200 shellx_core_call("nope","{}"), every result is an unknown_method envelope */ }
```

`tests/c/smoke.c` calls `shellx_core_call("nope", "{}")`, prints the result, frees it, exits 0 iff it starts with `{"error":{"code":"unknown_method"`. `scripts/c-smoke.sh` builds the staticlib, reads the native libs from `cargo rustc --lib --crate-type staticlib -- --print native-static-libs`, compiles with `clang -I include tests/c/smoke.c target/debug/libshellx_core.a <native libs>`, runs it. `scripts/check_deps.py` runs `cargo metadata --format-version 1 --locked` and exits 1 if any package is in the forbidden list or has a license outside Global Constraints' allowlist (prints offenders).

- [ ] **Step 2: Run** `(cd shellx-core && cargo test -p shellx-core)` — Expected: FAIL (crate missing).
- [ ] **Step 3: Implement** the files above. `ffi.rs` wraps every call in `std::panic::catch_unwind` (`panic` code), rejects NULL (`invalid_params`) and non-UTF-8 (`invalid_json`), returns `CString::into_raw`. Dispatch is a `match` on method names (later tasks add arms). The header has `#pragma once`, `extern "C"` guards and a comment that the output must be freed. `[profile.release] panic = "unwind"` (catch_unwind needs it), `lto = "thin"`.
- [ ] **Step 4: Run** `(cd shellx-core && cargo test -p shellx-core && scripts/c-smoke.sh && python3 scripts/check_deps.py)` — Expected: PASS, smoke prints the `unknown_method` envelope, deps check prints `ok`.
- [ ] **Step 5: Commit** `git add shellx-core .gitignore && git commit -m "feat(shellx-core): workspace, K3 C entry point, JSON envelope, config.set"`

