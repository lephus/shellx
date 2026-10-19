# Task 3 report: HTTP client, auth.login/auth.logout, version.check, fake API

Status: DONE_WITH_CONCERNS
Branch `shellx/l5-remote`, worktree /Users/lehuuphu/Documents/myProjects/shellx-wt-l5, BASE e8dc4c8952.
Commit: `43ccaa017f feat(shellx-core): HTTP client with platform headers, desktop login/logout, version check, fake K1 API` (not pushed).
Step 0 skipped (Ruling: D1-D3 already accepted by L0).

## What was built

- `src/fingerprint.rs`: `fingerprint(&[u8;32]) -> String`, the first 16 lowercase hex chars of SHA-256(raw key). Checked against a known answer.
- `src/http.rs`: one `ureq` Agent, cached per `Core`. Settings:
  - TLS is rustls with `ring::default_provider()` passed in explicitly, plus `RootCerts::PlatformVerifier`.
  - Connect timeout 10 s, global timeout 20 s. A single request can set its own global timeout; logout uses 2 s.
  - `http_status_as_error(false)`, `max_redirects(0)` (a bearer token never follows a redirect), and the agent's own User-Agent turned off.
  - Headers on every request: `X-ShellX-Version`, `X-ShellX-Platform`, `X-ShellX-OS-Version` (left out when empty), `User-Agent: ShellX/<app_version> (<platform>)`, and `Authorization: Bearer <token>` when a session exists.
  - Error mapping:
    - transport failure → `network`
    - non-2xx with `{"error":{"code"}}` → that code, passed through only if it matches `[a-z0-9_]{1,64}`
    - any other non-2xx (3xx included) → `http_<status>`
    - 2xx body that does not parse → `server`
  - Error messages carry the path, status and body length, never body bytes. Response bodies are read into `Zeroizing` buffers capped at 1 MiB.
- `src/api.rs`: serde structs for the login request and response, `session.json`, and `/v1/version`.
  - `Debug` on `LoginResponse` and `SessionFile` redacts the token (`<n bytes>`).
  - Both structs zeroize the token on drop (impl in auth.rs).
- `src/auth.rs`:
  - `device.key` holds the raw 32-byte X25519 secret. It is made on the first login through `StateStore` (0600), kept across logout, and a wrong length is an `io` error (never silently regenerated).
  - Login sends `POST /v1/auth/login` with `{email, password, device:{kind:"desktop", name, platform, public_key:b64url-nopad}}`. `name` is `device_name`, or the hostname with `.local` removed, or `ShellX`, cut to 100 chars.
  - Login writes `session.json` `{token,user_id,device_id}` and returns `{user_id, device_id, device_public_key_b64, fingerprint}`.
  - Logout sends a best-effort `POST /v1/auth/logout` (2 s, result ignored), then removes `session.json` and `machine.json` and returns `{}`. With no session it sends nothing.
- `src/version.rs`: sends `GET /v1/version` and returns `{status, min_version, latest_version, download_url}`.
  - Uses a strict SemVer 2.0 parser: no leading zeros, `u64` parts, pre-release ordering per spec, build metadata ignored.
  - `update_required` if app < `min_agent`, else `update_available` if app < `latest_agent.version`, else `ok`.
  - A version that fails to parse (ours or the server's) never forces an update. This matches the server's `isSettableVersion` reasoning.
  - `download_url` is `mac_url` on macos and `win_url` on windows.
- `src/lib.rs` dispatch, in R1 order:
  1. unknown method → `unknown_method`
  2. `config.set`
  3. `not_configured`
  4. open the store (cached per state_dir, opened again when `config.set` changes the state_dir)
  5. session methods (`machines.`, `tickets.`, `pair.`) with no `session.json` → `not_logged_in`
  6. arms for `auth.login` and `auth.logout`, both behind an `auth_lock` so concurrent logins cannot race the device-key creation
  7. anything else → `unknown_method`

  `version.check` runs before the store step and is tolerant: if the store or session cannot be read, it sends no bearer instead of failing, so update checks still work.
- `fake-api/` (crate `shellx-fake-api`, GPL-3.0-or-later, workspace member, dev-dependency of shellx-core):
  - tiny_http on one thread, state in a `Mutex<State>`. Requests are recorded with lowercased header names.
  - `FakeApi::start(FakeOptions) / bind(addr, opts) / requests() / stop() / wait()`.
  - Additive helpers: `issued_token()`, `token_is_live()`, `token_owner()`, `Recorded.query` (the path is stored without the query), and `FakeOptions::default()` plus `default_version_body()`.
  - Login works like v1: kinds agent/mobile/desktop and the parseDevice checks. The same email gives the same user, the same (user, key) gives the same device, there is one live token per device, and tokens are 32 random bytes in b64url.
  - Login errors are `invalid_device`, `invalid_credentials` and `bad_request`. Logout returns 204, or 401 `unauthorized`. `/v1/version` serves `version_body`. Anything else is 404 `not_found`.
  - Binary: `shellx-fake-api --bind 127.0.0.1:<port> --relay-url --ticket-ttl --issuer`.
    - `CMUX_RELAY_HMAC_SECRET` comes from env only: required, at least 32 bytes, never printed.
    - The account password comes from env `SHELLX_FAKE_PASSWORD` (default `pw`), never from argv.
    - Only 127.0.0.1 binds are accepted. It prints `listening <url>`.
- `scripts/c-smoke.sh`, two required fixes:
  - (a) `rustls-platform-verifier` adds `-framework Security -framework CoreFoundation` to native-static-libs, and the old de-dup dropped the second `-framework`, so the link broke. Framework pairs are now kept together.
  - (b) ring builds its C code for the SDK version (26.2), while clang linked for 26.0, which gave a screen of ld warnings. The script now exports `MACOSX_DEPLOYMENT_TARGET` (default 14.0, the same as cmux.xcodeproj) on Darwin.

## Tests (TDD)

RED, after writing tests and the fake but before the core (`cargo test -p shellx-core --test auth --test version`):
```
error[E0433]: cannot find `fingerprint` in `shellx_core`   (tests/auth.rs:46, :48)
error: could not compile `shellx-core` (test "auth") due to 2 previous errors
--test version:
test download_url_follows_platform ... FAILED
test unparsable_versions_never_force_an_update ... FAILED
test version_check_server_error_passes_code ... FAILED   left: "unknown_method" right: "server"
test version_check_statuses ... FAILED
test result: FAILED. 0 passed; 4 failed
```
GREEN gate, `(cd shellx-core && cargo test --workspace --locked && python3 scripts/test_check_deps.py && scripts/c-smoke.sh && python3 scripts/check_deps.py)`:
- 56 passed, 0 failed, 0 warnings (lib unit 6, auth 16, ffi 10, store 17, version 4, fake-api bin 3).
- test_check_deps `OK`; c-smoke prints the `unknown_method` envelope with exit 0 and no ld warnings; check_deps `ok`.
- `cargo tree -i aws-lc-rs` gives "package ID specification `aws-lc-rs` did not match any packages".
- Cargo.lock has no aws-lc-*, openssl, openssl-sys, native-tls or iroh.

`openssl-probe 0.2.1` (MIT/Apache) is in the lock. It comes from rustls-native-certs (a Linux-only cert-path finder), links no OpenSSL, and is not on the forbidden list.

Test list:
- auth.rs:
  - `login_stores_token_and_never_returns_it` (brief), `fingerprint_is_sha256_prefix_of_the_device_public_key`, `login_uses_device_name_when_configured`, `login_requires_email_and_password_strings`
  - `wrong_password_passes_server_code`, `every_request_sends_platform_headers` (also checks User-Agent), `os_version_header_is_omitted_when_unknown`, `bearer_only_after_login`
  - `device_key_is_stable_across_logins`, `device_key_survives_logout_and_a_new_core`
  - `logout_online_revokes_token_and_forgets_session`, `logout_works_offline_and_forgets_session`, `logout_without_session_is_ok_and_sends_nothing`
  - `unreachable_server_is_network_error`, `session_methods_need_login_then_reach_dispatch`, `state_dir_change_reopens_the_store`
- version.rs: `version_check_statuses` (the brief's 3 cases plus 7 more: numeric ordering 1.10 > 1.9, pre-release, build metadata), `download_url_follows_platform`, `unparsable_versions_never_force_an_update`, `version_check_server_error_passes_code`.
- Unit tests:
  - semver: strict parse accept/reject lists, the spec ordering chain
  - http: code mapping, implausible codes, 3xx, no bodies in messages or Debug, User-Agent
  - api: Debug redaction
- fake-api/tests/bin.rs: refuses to start without the secret or with a short one (and does not print it), refuses a non-loopback bind, serves `/v1/version`.

Other checks:
- Real TLS check against ShellX's own server (no third party): `shellx-core-cli version.check` with api_base `https://relay.shellx.pro` returned `{"ok":{"status":"ok","min_version":"1.0.0","latest_version":"1.0.0","download_url":"https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg"}}`. So ring plus the platform verifier works on macOS.
- `cargo check --target x86_64-pc-windows-msvc --lib` (target installed) FAILED, but not in our code: ring's build script needs MSVC C headers (`'assert.h' file not found` under cc-rs), and this Mac has no Windows SDK. Our non-unix code (`hostname()` via `COMPUTERNAME`) is std-only. The Windows build has to be proven on Windows CI. I removed the partial `target/x86_64-pc-windows-msvc`.
- Disk: 25 GB free at start, 16-20 GB during the run because other lanes share the disk; never below 15 GB.

## Files changed (all under shellx-core/)
- New:
  - src/api.rs, src/auth.rs, src/fingerprint.rs, src/http.rs, src/version.rs
  - fake-api/{Cargo.toml, src/lib.rs, src/main.rs, tests/bin.rs}
  - tests/{auth.rs, version.rs, support/mod.rs}
- Modified:
  - Cargo.toml: deps, `members = [".", "fake-api"]`, dev-dep `shellx-fake-api`
  - Cargo.lock
  - src/lib.rs
  - tests/ffi.rs
  - scripts/c-smoke.sh

## Deps added (direct)
- shellx-core:
  - `ureq 3.3` (resolved 3.4.2, MIT OR Apache-2.0) with `default-features=false` and features `rustls-no-provider` + `platform-verifier`. `json` is not used; serde_json is called directly.
  - `rustls 0.23` (0.23.46, Apache-2.0 OR ISC OR MIT) with `default-features=false` and `ring, std, tls12`.
  - `x25519-dalek 2` (2.0.1, BSD-3-Clause) with `static_secrets`.
  - `sha2 0.10` (MIT OR Apache-2.0), `base64 0.22` (MIT OR Apache-2.0), `serde 1` with derive (MIT OR Apache-2.0).
- fake-api: `tiny_http 0.12` (MIT OR Apache-2.0), serde_json, getrandom 0.3, base64.
- Notable transitive deps:
  - ring 0.17.14 (Apache-2.0 AND ISC), rustls-webpki (ISC), untrusted (ISC), curve25519-dalek (BSD-3), subtle (BSD-3), fiat-crypto (MIT/Apache/BSD-1), security-framework (MIT/Apache)
  - webpki-root-certs (CDLA-Permissive-2.0), same-file/walkdir (Unlicense/MIT), jni* (Android verifier path, MIT/Apache)
- All are inside the allowlist (`check_deps.py` prints `ok`).

## Self-review
- Completeness against the brief: every interface item is in place. The fake's `issued_token()` was added as an additive helper, as the ruling allowed.
- Headers and timeouts: exactly as specified. The headers are covered by tests on both `/v1/version` and `/v1/auth/login`. The 2 s logout timeout is exercised by the offline test (see the 2 s note under Concerns).
- The token is never returned or logged:
  - Responses carry no token, and the test checks both `Debug` and the JSON string.
  - The core has no logging. Error messages hold paths, statuses and lengths only.
  - `Debug` is redacted on the login response and session file.
  - The bearer header string, request body and response body sit in `Zeroizing` buffers. Copies inside ureq/http are best effort.
  - The password is not in any message (tested).
- Semver edge cases: leading zeros, 2 or 4 parts, empty pre-release or build, `u64` overflow, pre-release against release, numeric against alphanumeric identifiers, and build metadata ignored.
- The fake binary reads secrets from env only: tested, including that a short secret is not echoed.

## Concerns
1. **tests/ffi.rs was changed.** The Task 1 test `unknown_beats_not_configured_and_known_unimplemented_after_config_is_unknown` expected `machines.list` → `unknown_method` right after `config.set` with `/tmp/x`. Under the full R1 (the session check is new in this task) that is now `not_logged_in`, and `/tmp/x` on this Mac is a regular file (`state_dir_insecure`). The test now uses a tempdir and checks both halves of R1: first `not_logged_in`, then `unknown_method` once `session.json` exists. The brief said R1 was "already implemented", but the session half was not; it is added here.
2. **The Windows cross-check cannot run on this Mac** because ring needs the MSVC headers. It must be confirmed on Windows CI (L6 / shellx-windows).
3. **The Xcode link (Task 9 / Task 13) must set `MACOSX_DEPLOYMENT_TARGET=14.0`** for the cargo build of the staticlib, or ld will warn about ring objects built for a newer OS. The app must also link `-framework Security -framework CoreFoundation` (needed by rustls-platform-verifier).
4. **ureq honours proxy environment variables by default** (`HTTP(S)_PROXY`/`ALL_PROXY`). GUI apps normally have none set, and TLS protects the token anyway; I left the default.
5. **The offline-logout test takes about 2 s.** After `stop()`, tiny_http keeps the client's pooled keep-alive socket open on a thread that never answers, so logout waits out its 2 s timeout. It still meets the "returns `{}`" contract, and the test asserts under 5 s.
6. **Not done (beyond the brief):** logging in again as a different account does not clear an old `machine.json`. Logout already clears it. Task 4 may want this.
7. **`version.check` sends no bearer when the state dir or session cannot be read**, instead of failing, so a broken state dir cannot block a forced update. This is a deliberate choice; the other methods do surface store errors.
