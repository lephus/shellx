### Task 3: HTTP client, `auth.login`/`auth.logout`, `version.check`, fake API

**Files:**
- Create: `shellx-core/src/{http.rs,api.rs,auth.rs,version.rs,fingerprint.rs}`, `shellx-core/fake-api/{Cargo.toml,src/lib.rs,src/main.rs}`, `shellx-core/tests/{auth.rs,version.rs}`, `shellx-core/tests/support/mod.rs`
- Modify: `shellx-core/Cargo.toml` (workspace members `[".", "fake-api"]`; `shellx-fake-api` as dev-dependency)

**Interfaces:**
- Consumes: `StateStore` (Task 2), `CoreConfig` (Task 1).
- Produces:
  - `fingerprint(public: &[u8; 32]) -> String` (16 lowercase hex of SHA-256).
  - Every request: `X-ShellX-Version: <app_version>`, `X-ShellX-Platform: <platform>`, `X-ShellX-OS-Version: <os_version>` (omitted if unknown), `User-Agent: ShellX/<app_version> (<platform>)`, `Authorization: Bearer <token>` when `session.json` exists; connect timeout 10 s, global timeout 20 s; `ureq` configured with the rustls `ring` provider and `RootCerts::PlatformVerifier`.
  - `auth.login {email, password}` → generates `device.key` if missing, POSTs `/v1/auth/login` `{email, password, device: {kind:"desktop", name:<device_name or hostname>, platform, public_key:<b64url 32 bytes>}}`, stores `session.json`, returns `{user_id, device_id, device_public_key_b64, fingerprint}`.
  - `auth.logout {}` → best-effort `POST /v1/auth/logout` (2 s timeout), then removes `session.json` and `machine.json`; returns `{}` even when the server is unreachable.
  - `version.check {}` → `GET /v1/version` → `{status: "ok"|"update_available"|"update_required", min_version, latest_version, download_url}`; semver compare of `app_version` with `min_agent` (required) and `latest_agent.version` (available); `download_url` = `latest_agent.mac_url` on macos, `win_url` on windows. L6 consumes this shape (W4 `update.rs`).
  - `shellx_fake_api::FakeApi::start(opts: FakeOptions) -> FakeApi` with `pub base_url: String`, `fn requests(&self) -> Vec<Recorded{method, path, headers: BTreeMap<String,String>, body: Value}>`, `fn stop(self)`; `FakeOptions { password: String, hmac_secret: Vec<u8>, issuer: String /* "shellx-relay" */, ticket_ttl_secs: u64, relay_url: String, version_body: Value }`. Binary `shellx-fake-api --bind 127.0.0.1:<port> --relay-url <url> --ticket-ttl <s> --issuer <s>` reading the secret from env `CMUX_RELAY_HMAC_SECRET`. Routes this task: `/v1/auth/login`, `/v1/auth/logout`, `/v1/version` (Task 4/6 add the rest).

- [ ] **Step 0: Send D1–D3 to L0** (one message: decisions table rows D1–D3 verbatim) and continue without waiting; the fake API implements D2/D3 as stated.
- [ ] **Step 1: Write the failing tests**

```rust
#[test] fn login_stores_token_and_never_returns_it() {
    let (core, fake, dir) = support::logged_out();               // config.set pointing at FakeApi
    let r = core.call("auth.login", json!({"email":"a@b.c","password":"pw"})).unwrap();
    assert!(r.get("token").is_none());
    assert_eq!(r["fingerprint"].as_str().unwrap().len(), 16);
    let req = &fake.requests()[0];
    assert_eq!(req.body["device"]["kind"], "desktop");
    assert_eq!(mode(dir.join("session.json")), 0o600);
    assert!(!format!("{r:?}").contains(&fake.issued_token()));
}
#[test] fn wrong_password_passes_server_code() { /* → "invalid_credentials" */ }
#[test] fn every_request_sends_platform_headers() {
    /* config.set app_version 2.0.0, os_version 15.5, platform macos → headers on /v1/version and /v1/auth/login:
       X-ShellX-Version == "2.0.0", X-ShellX-Platform == "macos", X-ShellX-OS-Version == "15.5" */
}
#[test] fn bearer_only_after_login() {}
#[test] fn device_key_is_stable_across_logins() { /* two logins → same device_public_key_b64 */ }
#[test] fn logout_works_offline_and_forgets_session() { /* fake.stop(); logout ok; machines.list → not_logged_in */ }
#[test] fn unreachable_server_is_network_error() { /* api_base http://127.0.0.1:1 → "network" */ }
#[test] fn version_check_statuses() {
    // (app, min_agent, latest) → status: ("1.9.9","2.0.0","2.0.0")→update_required; ("2.0.0","2.0.0","2.0.1")→update_available;
    // ("2.0.0","2.0.0","2.0.0")→ok; download_url == mac_url on macos
}
```

- [ ] **Step 2: Run** `(cd shellx-core && cargo test -p shellx-core --test auth --test version)` — Expected: FAIL.
- [ ] **Step 3: Implement** `http.rs`, `api.rs` (serde structs for K1 bodies), `auth.rs`, `version.rs`, `fingerprint.rs`, and the fake API (tiny_http, one thread, in-memory `Mutex<State>`, tokens = random 32-byte b64url).
- [ ] **Step 4: Run** the full suite plus `python3 scripts/check_deps.py` and `cargo tree -i aws-lc-rs` (Expected: "package ID specification `aws-lc-rs` did not match any packages") — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx-core): HTTP client with platform headers, desktop login/logout, version check, fake K1 API"`

