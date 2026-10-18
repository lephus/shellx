# ShellX native desktop — Wave 2: Mac remote core (lane L5) and Mac remote UI (lane L3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Part A** (Tasks 1–14) is lane L5. **Part B** (Tasks U1–U4) is lane L3, after W1 Task 10. Read the master plan `2026-10-19-native-desktop-12h-sprint.md` first.

**Tóm tắt (cho người dùng):** Lane L5 làm phần lõi để một máy Mac xem và điều khiển máy Mac khác qua relay v2. Gồm ba khối. (1) `shellx-core`: thư viện Rust dùng chung cho Mac và Windows, lo đăng nhập, danh sách máy, ticket relay, ghép cặp, và **niêm phong lời mời** (khoá PSK được mã hoá cho riêng máy xin quyền, máy chủ ShellX chỉ thấy bản mã). (2) **Cầu nối** trong app Mac: daemon `cmux-tui` chạy kèm app, terminal libghostty của Mac được chiếu sang "PTY ảo" (đã chạy thật trong bước thử W0). (3) `ShellXRemoteService` trong Swift: tự khởi động daemon, làm mới ticket, tự kết nối lại khi relay hay mạng rớt, và chỉ cho vào khi **máy đích chấp thuận tại chỗ** (so mã 6 số + vân tay trên hai màn hình). Lane L3 làm giao diện: nhóm máy ở xa trong sidebar, hộp "Xin quyền" hiện mã và vân tay, hộp chấp thuận trên máy đích, trạng thái ngoại tuyến / đang kết nối lại. Có 3 điểm hợp đồng K1 cần lane L0 xác nhận ngay đầu sprint (mục "Quyết định"). Giới hạn đã biết: Ctrl-J từ máy xem tới Mac đến dưới dạng Enter (cần sửa ghostty sau sprint); máy xem thấy terminal đang mở trên Mac và tạo được tab mới, chưa thấy toàn bộ danh sách phiên.

**Goal:** By T+10, two ShellX Mac builds signed into one account pair through relay v2 with on-site approval, and each can open, view and type into a terminal of the other; the session survives relay/API outages by reconnecting with fresh tickets.

**Architecture:** `shellx-core/` (own Cargo workspace in the fork) is a Rust `staticlib` + `rlib` behind the one K3 C entry point; it owns every secret (account token, device X25519 key, tickets, invites) in an owner-only `state_dir`. The Mac serves its terminals through the bundled, fork-built `cmux-tui` run as a sidecar (`server start … --ephemeral`) whose default-shell terminals are virtual PTYs into the app (`virtual_pty.rs`, from the W0 bridge spike). A viewer Mac runs `cmux-tui remote connect` through `cmux-relay` and shows a remote terminal in a local pane running `cmux-tui attach`. Pure Swift logic (paths, backoff, link state machine, frame codec, approval gate, argv builders, core client) lives in a new `ShellXRemoteCore` target of the `ShellXBrand` package so it is tested in seconds; the app side (`Sources/ShellX/Remote/`) only wraps processes, sockets and `TerminalController`.

**Tech Stack:** Rust 2024 (`rust-version = "1.91"`, local 1.95): `ureq 3.3` (`rustls-no-provider` + `platform-verifier` + `json`), `rustls 0.23` with `ring`, `x25519-dalek 2` (`static_secrets`), `hkdf 0.12`, `sha2 0.10`, `chacha20poly1305 0.10`, `base64 0.22`, `zeroize 1`, `serde_json 1`, `libc 0.2`; test-only `tiny_http 0.12`, `hmac 0.12`. Swift 6 / Swift Testing, SwiftUI + AppKit, CryptoKit-free (crypto stays in Rust). cmux-tui workspace (`cmux-tui-core`, `cmux-remote`, `cmux-relay`) with Zig 0.16.0 for `ghostty-vt-sys`. Python 3 stdlib `unittest` for guards and the e2e harness. GitHub Actions `ubuntu-24.04`, `macos-26`.

**Spec:** `docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md` (§7.1 sidebar, §7.4 palette, §8.1, §8.4, §8.5 security principles 1–2, §8.6, U14, C12, C16, D-W0-1 amendments). Master plan (binding K1, K3, K4, Review Focus 1–4, Clock, checkpoint 2): `docs/superpowers/plans/2026-10-19-native-desktop-12h-sprint.md`. Ledger (binding facts): `docs/superpowers/ledgers/native-desktop.md` — D-W0-1 FINAL, "Mac bridge spike (M-B1)", "Ticket format", "Enroll → approve as observed", "Spec implication (§8.5)". W1 plan `2026-10-18-native-desktop-w1-mac-local.md` (Task 1 `ShellXBrand`/`ShellXFeatures`, Task 3 paths, Task 5 cloud-off, Task 10 sidebar grouping, Task 13 `audit_network.py`). Bridge spike: fork `shellx/w0-bridge` @ `4e1ed7bc41` (worktree `~/Documents/myProjects/shellx-pro-wt-bridge`): `spikes/protocol/mac-bridge-spike.md`, `cmux-tui/crates/cmux-tui-core/src/virtual_pty.rs`, `Sources/Mobile/ShellXBridgeSpike.swift`, `spikes/protocol/mac-bridge/{run.sh,fake_app.py}`. `docs/…` paths are in the shellx repo; every other path is in the fork worktree.

## Global Constraints

- Every master-plan Global Constraint holds (no Manaflow servers or telemetry, no BUSL dirs, GPL-compatible deps, palette §7.4, no secrets in chat, push lane branches only, never shellx `main`).
- Branches: L5 `shellx/l5-remote` (worktree `~/Documents/myProjects/shellx-pro-wt-l5`), L3 `shellx/l3-sidebar`, both from `shellx/sprint` after master Task L0.1 Step 4. Push with `git push git@phule9225.github.com:lephus/shellx-pro.git <branch>`. No PRs: report "ready <sha>" to L0 (master L0.2).
- **Disk: 7.6 GB free when this plan was written.** Build cmux-tui in the L5 worktree with `CARGO_TARGET_DIR=~/Documents/myProjects/shellx-pro/cmux-tui/target` (reuse W0's target dir). `cargo test -p cmux-tui-core` runs on CI only (fork workflow `cmux-tui.yml` focused mode or `shellx-remote.yml`), never locally. One local Xcode build at a time under `~/.shellx-build.lock` (master L0.2).
- `shellx-core`: own workspace at `shellx-core/`, `license = "GPL-3.0-or-later"`, `edition = "2024"`, `rust-version = "1.91"`, `crate-type = ["staticlib", "rlib"]`. TLS = rustls with the `ring` provider only: `Cargo.lock` must contain none of `aws-lc-rs`, `aws-lc-sys`, `openssl`, `openssl-sys`, `native-tls`, `iroh`. Allowed dependency licenses: MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, Zlib, Unicode-3.0, MPL-2.0, CDLA-Permissive-2.0 (any other → stop and ask L0).
- ShellX code lives in `shellx-core/`, `Sources/ShellX/`, `Packages/Shared/ShellXBrand/`, `scripts/shellx/`, `tests/test_shellx_*.py`, `.github/workflows/shellx-remote.yml`. Upstream edits are wiring only, each marked `// ShellX:` (Rust/Swift) or `# ShellX:`: `cmux-tui-core/src/lib.rs` (one `mod` line), `cmux-tui-core/src/surface.rs` (the spike seam), `Sources/TerminalOutputTeeCallback.swift` (one call), `Sources/AppDelegate.swift` (start/stop), `cmux-Bridging-Header.h` (one include), `cmux.xcodeproj/project.pbxproj` (build phase, link flags, files via `scripts/wire-app-sources.py` / `scripts/sync-test-wiring`), the three gate reads in Task 13. `cmux-tui-core/src/virtual_pty.rs` is a ShellX file inside an upstream crate (it implements crate-private seams); its header says so.
- The bundled `Contents/Resources/bin/cmux-tui` is built from this fork (`scripts/shellx/build-cmux-tui.sh`, default features, never `iroh-transport`) and installed with `CMUX_TUI_CLIENT_LOCAL`; nothing may download from `files.cmux.com` (upstream `reload.sh`'s default does — always set `CMUX_TUI_CLIENT_LOCAL`).
- Secrets: the account token, the device X25519 private key, relay tickets and enrollment invites exist only inside `shellx-core`'s `state_dir` (dir `0700`, files `0600`, owner = euid, no symlinks) and in cmux-tui's own owner-only state dirs. Swift never receives the token or the device private key; no secret value is ever logged (log lengths/ids only). Keychain is a post-sprint upgrade (K3).
- API base `https://relay.shellx.pro` (`ShellXBrand.apiBaseURL`, Task 13); `SHELLX_API_BASE` env override is honoured **only in DEBUG builds** (e2e against the fake API). Relay URL comes only from `tickets.mint`.
- New user-visible strings: `String(localized: "<key>", defaultValue: "<English>")` + Vietnamese in the catalog (W1 Global Constraints); glossary from W1 Task 12 (machine → "máy", session → "phiên").
- Tests: Swift Testing (`import Testing`). Package tests `swift test --package-path Packages/Shared/ShellXBrand`; app-hosted tests `scripts/shellx/test-app.sh <Suite>` (W1 Task 1); Python guards are stdlib `unittest`, run as `python3 tests/<file>.py`, registered in `tests/test-execution.toml`; Rust `(cd shellx-core && cargo test -p shellx-core)`.
- **Per-task security review** (master throughput rule 4) on Tasks 2, 5, 6, 11, 12: after the task's tests pass, dispatch one reviewer subagent with the task's checklist and the diff; fix findings before the commit.

## Review Focus

1. **Two ShellX builds on one Mac** (master RF1: Release `pro.shellx.desktop` + tagged `pro.shellx.desktop.debug.<tag>`): each must get its own core state, daemon session, mux/bridge/admin/link sockets, client state and relay slot, and each registers as its own machine. Tests: Task 10 `pathsAreDistinctPerBundleAndFitSunPath`, Task 12 `daemonArgumentsUseBundlePaths`, Task 14 Step 3.
2. **Relay or API down, or tickets expired mid-session** (master RF2): the sidebar shows offline/reconnecting, nothing blocks the main thread, and daemon + viewer come back with freshly minted tickets on a 1, 2, 4, 8, 16, 30 s backoff. Tests: Task 8 `test_reconnect_after_relay_restart_with_2s_tickets`, Task 10 `LinkStateMachine` tests, Task 12 `everyRespawnMintsAFreshTicket`, Task 13 `coreCallsNeverRunOnMainThread`.
3. **Approval spoofing** (master RF3): a pairing whose server fingerprint does not match the requester key the target would seal to is refused without posting anything; a sealed invite moved to another pairing does not open; a daemon enrollment whose invitation id the target did not issue for an approved pairing is denied. Tests: Task 6 `approve_refuses_fingerprint_mismatch`, `poll_rejects_invite_moved_to_another_pairing`; Task 10 `gateDeniesUnknownInvitation`; Task 13 `unknownPendingEnrollmentIsDenied`; Task U3 `suspiciousRequestCannotBeApproved`.
4. **Vietnamese over remote** (master RF4): Telex composed on the viewer arrives at the host PTY as composed UTF-8 bytes `74 69 e1 ba bf 6e 67 20 56 69 e1 bb 87 74`, even when a frame boundary splits a character. Tests: Task 7 `virtual_pty_forwards_vietnamese_utf8_unchanged`, Task 10 `decoderKeepsSplitUTF8ByteExact`, Task 11 `inputReachesHostByteExact`, Task 8 `test_vietnamese_round_trip`, Task 14 Step 4.
5. **ShellX crashes or is force-quit while serving:** `server start` has no `--exit-with-parent`, so the sidecar outlives the app. Next launch must stop the stale daemon of the same session before starting a new one; a normal quit stops it and the machine shows offline within 90 s (U14). Tests: Task 12 `staleDaemonIsStoppedBeforeStart`, Task 13 `terminateStopsDaemonAndHeartbeat`.

---

## Decisions this plan makes (L5 sends D1–D3 to L0 at T+0 for a ledger note)

| # | Decision | Why |
| --- | --- | --- |
| D1 | One X25519 **device key** per `state_dir` (generated by shellx-core, `device.key`, 0600) is: the v1 login `device.public_key` (`kind:"desktop"`), the `noise_public_key_b64` of `machines.register`, and the `requester_x25519_b64` of `pair.request`. Fingerprint everywhere = first 16 lowercase hex of SHA-256(raw 32-byte key), computed locally. It is **not** the cmux daemon's Noise key (that stays in cmux state). | No chicken-and-egg (the daemon needs the slot from `machines.register` before it starts); the server's `requester_fingerprint` and the machine fingerprint then equal the locally computed one whichever key L4 hashes. Invites are sealed to a long-lived key (no forward secrecy), acceptable: single-use, ≤ 300 s. |
| D2 | **K1 gap (additive):** `GET /v2/pairings?role=target` items must include `requester_x25519_b64`; the target cannot seal without it. Fake API (Task 3) includes it. | K1 response lists no requester key; the L4 plan (`2026-10-19-native-desktop-w2-server.md` Task 4) stores `requester_x25519` "for sealing only" but its `GET` does not return it. |
| D3 | **K1 gap (additive):** `POST /v2/relay/tickets {permission:"connect", target_machine_id:<caller's own machine>}` must be allowed. The L4 plan (Task 5 rules) currently answers 400 for `target_machine_id == machine_id`. `remote enroll create` requires `--relay-route/--relay-slot/--relay-ticket-file`, and the invite's `relay_access` is the only way a viewer learns the target's slot. | Fallback if L0 refuses: Task 8 Step 6 tries a non-secret placeholder ticket in the invite (viewer supplies its own ticket file) and records the result. Never put a `register` ticket in an invite (would let the viewer hijack the slot). |
| D4 | Sealed invite wire format (shellx-core owns both ends, Windows reuses it): `b64url_nopad(0x01 ‖ eph_pub[32] ‖ nonce[12] ‖ ChaCha20-Poly1305(ct‖tag))`, key = HKDF-SHA256(ikm = X25519(eph_secret, requester_pub), salt = eph_pub ‖ requester_pub, info = `"shellx-invite-v1"`, 32 bytes), AAD = UTF-8 `pairing_id`; refuse a non-contributory shared secret; plaintext must start with `cmux://enroll/` and be ≤ 8131 bytes so the sealed blob fits L4's `SEALED_INVITE_MAX_BYTES = 8192` (w2-server plan Task 4; 8192 − 1 − 32 − 12 − 16). | K1 fixes the primitives; this fixes the bytes. |
| D5 | Additive, optional K3 fields (no K3 field removed or renamed): `config.set` + `app_version`, `os_version`, `platform`, `device_name`; `auth.login` → `{user_id, device_id, device_public_key_b64, fingerprint}` (never the token); `machines.register` fills `noise_public_key_b64` from the device key when omitted, stores and returns `{machine_id, slot}`; `machines.list` items + `is_this_machine`; `tickets.mint` + `write_to` (bare file name → `<state_dir>/tickets/<name>`, response has `path` and no `ticket`); `pair.request` + `fingerprint`; `pair.pending` items `{pairing_id, from_machine_id, code, fingerprint, server_fingerprint, suspicious}`; `pair.poll` + `write_invite_to` → `{status, invite_path, relay_route, relay_slot, daemon_fingerprint}` (no `invite_uri` when written). | Keeps tickets, PSKs and the token out of Swift; one place (Rust) for owner-only file code. |
| D6 | cmux-tui gets relay routes as `relay+wss://host/path` (`wss://` → `relay+wss://`, `ws://` → `relay+ws://` for local tests); the path (`/v2/relay`) is kept as is (`cmux-remote/src/provider/relay.rs:1639-1675` only fills `/v1/relay` when the path is empty; invites require a `relay+` scheme, `identity.rs:2338`). | K2 serves `wss://relay.shellx.pro/v2/relay`. |
| D7 | Sprint projection rule (spike rule, made explicit): a daemon terminal created while no Mac terminal is bound projects the Mac's **focused** terminal (`mode=attach`); every later one opens a **new tab** in the focused workspace (`mode=create`). `K` from the daemon unbinds only (never closes a Mac tab); a closed Mac surface sends `E`. Input goes through `ghostty_surface_text_input`, so a remote `\n` arrives as `\r` (raw PTY-write export is post-sprint). | Full workspace/pane mapping (spike B4, ~4 d) is not in 12 h. |
| D8 | The viewer shows a remote terminal in a local ShellX workspace whose terminal runs a reconnect wrapper around `cmux-tui --socket <local> attach --terminal <id>` (upstream `CloudTuiCommandLine.attachArguments`). IME composition stays local; committed UTF-8 is what crosses. | Reuses upstream attach; no new renderer. |
| D9 | On-site approval has two layers: the person compares code + fingerprint on both screens and clicks Approve on the target (refused automatically when `suspicious`); then the target's `ApprovalGate` approves at the daemon **only** the invitation id it created for that pairing (single use, ≤ 300 s) and denies every other pending enrollment. | Ledger §8.5: show the device fingerprint, PSK out of band. |

## Clock (agent wall-clock, CI included)

| Task | Window | Notes |
| --- | --- | --- |
| 1 core skeleton, ABI, envelope, config | 0:00–0:20 | master row "shellx-core skeleton + K3 tests" |
| 2 owner-only state store | 0:20–0:45 | security review |
| 3 HTTP, auth, version, fake API | 0:45–1:20 | sends D1–D3 to L0 at start |
| 4 machines, tickets | 1:20–1:45 | |
| 5 sealed invite | 1:45–2:10 | security review |
| 6 pairing | 2:10–2:50 | security review; "core done" |
| 7 virtual PTY (second implementer) | 0:45–2:30 | disjoint files; CI focused run |
| 8 e2e harness + `shellx-remote.yml` | 2:50–3:40 | CI |
| 9 bundle cmux-tui + link core | 3:00–4:00 | local build under lock |
| 10 `ShellXRemoteCore` package | 3:00–3:45 | push early: L3 needs it |
| 11 bridge server | 4:00–5:00 | security review |
| 12 supervisors | 5:00–5:50 | security review |
| 13 service, gate, wiring | 5:50–6:40 | after checkpoint-1 merge |
| 14 Mac↔Mac acceptance | 6:40–10:00 | L1 helps from T+6; checkpoint 2 |
| L3: U1–U4 | 6:00–9:30 | binds to the real service once Task 13 is merged |

Cut order if behind at checkpoint 2 (master "never cut: on-site approval, PSK out of band"): U4 banner (keep sidebar states), then Task 14's second-app run (keep host-app + CLI viewer), then remote-initiated create (D7: attach-only).

---

## File Structure

```
shellx-core/                              own Cargo workspace: members ".", "fake-api"
  Cargo.toml, Cargo.lock                  crate shellx-core, lib shellx_core, staticlib+rlib
  include/shellx_core.h                   K3 header (frozen signatures)
  src/lib.rs                              Core, dispatch table
  src/ffi.rs                              shellx_core_call / shellx_core_free, catch_unwind
  src/envelope.rs                         CoreError, {"ok"}/{"error"} encoding
  src/config.rs                           config.set, CoreConfig
  src/store.rs                            StateStore: owner-only dir/files (Task 2)
  src/http.rs                             ureq agent (rustls+ring, platform verifier), headers, error mapping
  src/api.rs                              typed K1 requests/responses
  src/auth.rs, src/version.rs             auth.login/logout, version.check
  src/machines.rs, src/tickets.rs         machines.*, tickets.mint
  src/fingerprint.rs                      fingerprint(pub) -> 16 hex
  src/seal.rs                             D4 seal/open (Task 5)
  src/pairing.rs                          pair.* (Task 6)
  src/bin/shellx-core-cli.rs              `shellx-core-cli <method> '<json>'` (e2e + Windows debugging)
  fake-api/                               crate shellx-fake-api: in-memory K1 subset, HMAC tickets per ledger
    src/lib.rs, src/main.rs, tests/ticket_format.rs
  tests/{ffi,store,auth,version,machines,tickets,seal,pairing}.rs
  tests/c/smoke.c, scripts/c-smoke.sh, scripts/check_deps.py
cmux-tui/crates/cmux-tui-core/src/virtual_pty.rs   (Task 7; lib.rs + surface.rs wiring)
Packages/Shared/ShellXBrand/
  Package.swift                           + library ShellXRemoteCore, test target ShellXRemoteCoreTests
  Sources/ShellXBrand/ShellXBrand.swift   + apiBaseURL (Task 13)
  Sources/ShellXBrand/ShellXFeatures.swift + upstreamDeviceMirroring (Task 13)
  Sources/ShellXRemoteCore/*.swift        pure models and logic (Tasks 10, 12)
  Tests/ShellXRemoteCoreTests/*.swift
Sources/ShellX/Remote/
  ShellXCoreFFI.swift                     (Task 9)
  Bridge/ShellXBridgeServer.swift, Bridge/ShellXBridgeTee.swift, Bridge/TerminalControllerBridgeHost.swift (Task 11)
  ShellXSidecarProcess.swift, ShellXDaemonSupervisor.swift, ShellXClientLinkSupervisor.swift, ShellXTicketRefresher.swift (Task 12)
  ShellXRemoteService.swift, ShellXRemoteGate.swift (Task 13)
  UI/…                                    (Part B)
scripts/shellx/build-cmux-tui.sh, scripts/shellx/build-shellx-core.sh (Task 9)
scripts/shellx/remote-e2e/{harness.py,fake_app.py} (Task 8)
tests/test_shellx_remote.py (guards), tests/test_shellx_remote_e2e.py (e2e, lane manual)
cmuxTests/ShellXCoreFFITests.swift, ShellXBridgeServerTests.swift, ShellXSupervisorTests.swift, ShellXRemoteServiceTests.swift, ShellXRemoteUITests.swift
.github/workflows/shellx-remote.yml
```

---

# Part A — Mac remote core (lane L5)

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

### Task 2: Owner-only state store (security review)

**Files:**
- Create: `shellx-core/src/store.rs`, `shellx-core/tests/store.rs`

**Interfaces:**
- Produces: `pub struct StateStore`; `StateStore::open(root: &Path) -> Result<StateStore, CoreError>` — creates `root` and `root/tickets` with mode `0700` if missing; refuses (code `state_dir_insecure`) a root or `tickets` that is a symlink, not a directory, not owned by `geteuid()`, or has any `0o077` bit. `fn write_secret(&self, name: &str, bytes: &[u8]) -> Result<PathBuf, CoreError>`; `fn read_secret(&self, name: &str) -> Result<Option<Zeroizing<Vec<u8>>>, CoreError>`; `fn remove(&self, name: &str) -> Result<(), CoreError>`. `name` is either a bare file name or `tickets/<file>`; file part matches `^[a-z0-9][a-z0-9._-]{0,63}$` (else `invalid_params`).
- Files the core keeps (later tasks): `session.json` `{token, user_id, device_id}`, `device.key` (raw 32-byte X25519 secret), `machine.json` `{machine_id, slot}`, `tickets/*`.
- Write = open temp `name.tmp.<rand>` with `O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC`, mode `0600` (then `fchmod 0600` regardless of umask), write, `fsync`, `rename` over the target, `fsync` the dir. Read = `open(O_NOFOLLOW)` then `fstat`: owner == euid and no `0o077` bit, else `state_file_insecure`.
- Non-Unix (`cfg(not(unix))`, Windows client of L6): same API, plain create/rename under the per-user `%LOCALAPPDATA%` dir, no ACL hardening — documented in the module header as a post-sprint security item (master "after the sprint").

- [ ] **Step 1: Write the failing tests** (`#[cfg(unix)]`)

```rust
#[test] fn creates_root_0700_and_secrets_0600() {
    let d = tempdir(); let s = StateStore::open(&d.path().join("core")).unwrap();
    let p = s.write_secret("session.json", b"{}").unwrap();
    assert_eq!(mode(d.path().join("core")), 0o700); assert_eq!(mode(&p), 0o600);
    assert_eq!(mode(d.path().join("core/tickets")), 0o700);
}
#[test] fn refuses_group_readable_root() { /* chmod 0755 → open → state_dir_insecure */ }
#[test] fn refuses_symlinked_root_tickets_dir_and_file() { /* each → *_insecure, target untouched */ }
#[test] fn refuses_bad_names() { for n in ["", "../x", "a/b", "tickets/../x", "tickets/a/b", "UPPER", ".hidden"] { assert_eq!(s.write_secret(n, b"x").unwrap_err().code, "invalid_params") } }
#[test] fn write_replaces_atomically_and_leaves_no_temp() { /* write twice; content = second; dir listing has no *.tmp.* */ }
#[test] fn refuses_group_readable_secret_file() { /* chmod 0644 → read → state_file_insecure */ }
#[test] fn umask_zero_still_yields_0600() { /* serial test: libc::umask(0); write; restore */ }
#[test] fn insecure_error_messages_name_no_contents() { /* message contains the path, never file bytes */ }
```

- [ ] **Step 2: Run** `(cd shellx-core && cargo test -p shellx-core --test store)` — Expected: FAIL.
- [ ] **Step 3: Implement** `store.rs` with `libc` (`open`, `fstat`, `fchmod`, `geteuid`); check the directory with `symlink_metadata` before use and re-check through the opened fd (`fstat` on `open(dir, O_DIRECTORY|O_NOFOLLOW)`) to narrow TOCTOU.
- [ ] **Step 4: Run** the store tests and the full suite — Expected: PASS.
- [ ] **Step 5: Security review** — reviewer checklist: O_NOFOLLOW on every final component and dir; fd-based ownership/mode checks; temp names unpredictable and created with O_EXCL; `fchmod` after create; rename within the same dir; fsync file and dir; `Zeroizing` for read buffers; no secret bytes in errors or `Debug`; name regex blocks traversal; Windows gap documented. Fix findings.
- [ ] **Step 6: Commit** `git commit -m "feat(shellx-core): owner-only state store (0700/0600, no symlinks, atomic writes)"`

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

### Task 4: `machines.*` and `tickets.mint`

**Files:**
- Create: `shellx-core/src/{machines.rs,tickets.rs}`, `shellx-core/tests/{machines.rs,tickets.rs}`, `shellx-core/fake-api/tests/ticket_format.rs`
- Modify: `shellx-core/fake-api/src/lib.rs` (routes `/v2/machines*`, `/v2/relay/tickets`)

**Interfaces:**
- `machines.register {name, platform, os_version, app_version, noise_public_key_b64?}` → `POST /v2/machines` (key defaults to the device key, D1) → stores `machine.json` → `{machine_id, slot}`.
- `machines.list {}` → `{machines: [{machine_id, name, platform, online, last_seen_unix, fingerprint, is_this_machine}]}`.
- `machines.heartbeat {}` → `POST /v2/machines/<own id>/heartbeat` → `{}`; `not_registered` without `machine.json`.
- `tickets.mint {permission: "register"|"connect", target_machine_id?, write_to?}` → `POST /v2/relay/tickets {machine_id:<own>, permission, target_machine_id?}` → `{ticket, expires_at_unix, relay_url}`, or with `write_to` (bare file name): writes `tickets/<write_to>` via `StateStore` and returns `{path, expires_at_unix, relay_url}`. `connect` without `target_machine_id` → `invalid_params`.
- Fake API: tickets are minted exactly per ledger "Ticket format" (`v2.` + b64url(claims) + `.` + b64url(HMAC-SHA256(secret, signing payload))), lifetime `ticket_ttl_secs`; `register` only for the caller's machine; `connect` only for a granted pairing target **or the caller's own machine** (D3); `online` = heartbeat within 90 s; test hook `set_last_heartbeat(machine_id, unix)`.

- [ ] **Step 1: Write the failing tests**

```rust
#[test] fn register_then_heartbeat_uses_stored_id() {
    let r = core.call("machines.register", json!({"name":"Mac A","platform":"macos","os_version":"15.5","app_version":"2.0.0"})).unwrap();
    core.call("machines.heartbeat", json!({})).unwrap();
    assert_eq!(fake.requests().last().unwrap().path, format!("/v2/machines/{}/heartbeat", r["machine_id"].as_str().unwrap()));
}
#[test] fn register_defaults_key_to_device_key() { /* body.noise_public_key_b64 == login's device_public_key_b64 */ }
#[test] fn list_marks_this_machine_and_offline_after_90s() {}
#[test] fn mint_writes_owner_only_file_and_omits_ticket() {
    let r = core.call("tickets.mint", json!({"permission":"register","write_to":"register.ticket"})).unwrap();
    assert!(r.get("ticket").is_none());
    let p = PathBuf::from(r["path"].as_str().unwrap());
    assert!(p.ends_with("tickets/register.ticket")); assert_eq!(mode(&p), 0o600);
    assert!(std::fs::read_to_string(&p).unwrap().starts_with("v2."));
}
#[test] fn mint_rejects_bad_write_to_and_connect_without_target() {}
#[test] fn connect_without_grant_is_not_granted_but_own_machine_is_allowed() { /* 403 code "not_granted" (L4 plan Task 5); own machine allowed per D3 */ }
```

`fake-api/tests/ticket_format.rs`: decode a minted ticket → claims `version 2`, `issuer "shellx-relay"`, `permission "register"`, `role "daemon"`, `circuit/lane/generation null`, `expires_at_unix - issued_at_unix == ttl`; recompute HMAC over `"cmux-relay-ticket-v2\n2\nshellx-relay\nregister\ndaemon\n<slot>\n\n\n\n<iat>\n<exp>"` and compare.

- [ ] **Step 2: Run** `(cd shellx-core && cargo test --workspace)` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `(cd shellx-core && cargo test --workspace)` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx-core): machines register/list/heartbeat and relay tickets written owner-only"`

### Task 5: Sealed invite (security review)

**Files:**
- Create: `shellx-core/src/seal.rs`, `shellx-core/tests/seal.rs`

**Interfaces:**
- Produces: `pub fn seal_invite(requester_pub: &[u8; 32], pairing_id: &str, invite_uri: &str) -> Result<String, CoreError>`; `pub fn open_invite(device_secret: &x25519_dalek::StaticSecret, pairing_id: &str, sealed_b64: &str) -> Result<Zeroizing<String>, CoreError>`; test-only `pub(crate) fn seal_with(eph: StaticSecret, nonce: [u8; 12], …)` for the known-answer vector. Format: D4. Every open failure returns code `invite_invalid` with the fixed message "sealed invite could not be opened"; seal input errors return `invalid_params`.

- [ ] **Step 1: Write the failing tests**

```rust
const URI: &str = "cmux://enroll/eyJ2ZXJzaW9uIjoxfQ";
#[test] fn round_trip() { let (s, p) = keypair(); let c = seal_invite(&p, "pr_1", URI).unwrap(); assert_eq!(&*open_invite(&s, "pr_1", &c).unwrap(), URI); }
#[test] fn wrong_key_fails() {}
#[test] fn other_pairing_id_fails() { assert_eq!(open_invite(&s, "pr_2", &c).unwrap_err().code, "invite_invalid"); }
#[test] fn any_flipped_byte_fails() { /* flip one byte in each region: version, eph_pub, nonce, ciphertext, tag */ }
#[test] fn unknown_version_and_truncation_fail() {}
#[test] fn low_order_requester_key_is_refused() { assert_eq!(seal_invite(&[0u8; 32], "pr_1", URI).unwrap_err().code, "invalid_params"); }
#[test] fn only_cmux_enroll_uris_seal() { /* "https://x" → invalid_params; 8132-byte cmux URI → invalid_params; 8131 bytes → sealed blob decodes to exactly 8192 bytes */ }
#[test] fn same_input_seals_differently() {}
#[test] fn known_answer_vector() { /* fixed eph secret, requester secret, nonce → pinned b64; Windows/L6 and any reimplementation check this */ }
```

- [ ] **Step 2: Run** `(cd shellx-core && cargo test -p shellx-core --test seal)` — Expected: FAIL.
- [ ] **Step 3: Implement** with `x25519-dalek` (`was_contributory()`), `hkdf::Hkdf::<Sha256>::new(Some(&salt), shared)`, `chacha20poly1305::ChaCha20Poly1305` with `Payload { msg, aad }`, `OsRng` for the ephemeral secret and nonce, `Zeroizing` for shared secret, key and plaintext. Run once, paste the produced vector into `known_answer_vector`, rerun.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Security review** — checklist: D4 bytes exactly (salt order, info string, AAD = pairing id), contributory check on both seal and open, fresh ephemeral + random nonce per seal, no plaintext/shared secret in errors or logs, constant error message, length checks before decrypt, base64 variant (URL_SAFE_NO_PAD) consistent. Fix findings.
- [ ] **Step 6: Commit** `git commit -m "feat(shellx-core): sealed enrollment invite (X25519, HKDF-SHA256 shellx-invite-v1, ChaCha20-Poly1305, pairing-bound AAD)"`

### Task 6: Pairing methods (security review)

**Files:**
- Create: `shellx-core/src/pairing.rs`, `shellx-core/tests/pairing.rs`
- Modify: `shellx-core/fake-api/src/lib.rs` (`/v2/pairings*`, 6-digit codes, 5-minute expiry, test hooks `tamper_requester_fingerprint(id, fp)`, `move_sealed_invite(from_id, to_id)`, `expire(id)`)

**Interfaces:**
- Consumes: `seal_invite`/`open_invite` (Task 5), `fingerprint` (Task 3), own `machine.json` (Task 4).
- Produces (D5):
  - `pair.request {to_machine_id}` → `POST /v2/pairings {from_machine_id:<own>, to_machine_id, requester_x25519_b64:<device pub>}` → `{pairing_id, code, fingerprint}` (`fingerprint` = local, of the device key).
  - `pair.pending {}` → `GET /v2/pairings?role=target` → `{pairings: [{pairing_id, from_machine_id, code, fingerprint, server_fingerprint, suspicious}]}` for `status == "pending"` and `to_machine_id == own`; `fingerprint` = `fingerprint(requester_x25519_b64)` computed locally; `suspicious` = `server_fingerprint != fingerprint`; items without `requester_x25519_b64` are returned with `suspicious: true` (D2 not deployed).
  - `pair.approve {pairing_id, invite_uri}` → re-fetches the target list; refuses `not_found`, `pairing_not_pending`, `contract_missing_requester_key`, `fingerprint_mismatch` **before** any POST; seals (AAD `pairing_id`) → `POST /v2/pairings/<id>/approve {sealed_invite_b64}` → `{}`.
  - `pair.deny {pairing_id}` → `POST /v2/pairings/<id>/deny` → `{}`.
  - `pair.poll {pairing_id, write_invite_to?}` → `GET /v2/pairings?role=requester` → `{status}`; when `approved` with `sealed_invite_b64`: opens it with the device key, parses the invite JSON (base64url after `cmux://enroll/`) and returns `{status, relay_route: relay_access[0].route, relay_slot: relay_access[0].slot, daemon_fingerprint}` plus `invite_path` (file written 0600 via `write_invite_to`) or `invite_uri` (when not written). An approved item without an openable invite → `invite_invalid`.

- [ ] **Step 1: Write the failing tests** (two `Core`s, A = requester, B = target, both logged in and registered against one `FakeApi`)

```rust
#[test] fn request_returns_code_and_local_fingerprint() {
    let r = a.call("pair.request", json!({"to_machine_id": b_id})).unwrap();
    assert!(r["code"].as_str().unwrap().len() == 6 && r["code"].as_str().unwrap().bytes().all(|c| c.is_ascii_digit()));
    assert_eq!(r["fingerprint"], a_login["fingerprint"]);
}
#[test] fn target_sees_pending_with_matching_fingerprint() { /* b pair.pending: same code, fingerprint == a's, suspicious == false */ }
#[test] fn approve_seals_and_requester_opens() {
    b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": invite("relay+wss://relay.test/v2/relay", "slotB")})).unwrap();
    let p = a.call("pair.poll", json!({"pairing_id": pid, "write_invite_to": "invite-b.uri"})).unwrap();
    assert_eq!(p["status"], "approved"); assert_eq!(p["relay_slot"], "slotB");
    assert!(p.get("invite_uri").is_none()); assert_eq!(mode(p["invite_path"].as_str().unwrap()), 0o600);
    assert!(!fake.stored_sealed(&pid).contains("cmux://")); // server holds ciphertext only
}
#[test] fn approve_refuses_fingerprint_mismatch() {               // Review Focus 3
    fake.tamper_requester_fingerprint(&pid, "0000000000000000");
    assert_eq!(b.call("pair.approve", json!({"pairing_id": pid, "invite_uri": URI})).unwrap_err().code, "fingerprint_mismatch");
    assert!(!fake.requests().iter().any(|r| r.path.ends_with("/approve")));
}
#[test] fn approve_refuses_non_pending() { /* deny then approve → pairing_not_pending; expired → pairing_not_pending */ }
#[test] fn poll_rejects_invite_moved_to_another_pairing() {     // Review Focus 3
    fake.move_sealed_invite(&pid1, &pid2);
    assert_eq!(a.call("pair.poll", json!({"pairing_id": pid2})).unwrap_err().code, "invite_invalid");
}
#[test] fn denied_and_expired_pass_through() {}
#[test] fn pending_ignores_pairings_for_other_machines() {}
```

- [ ] **Step 2: Run** `(cd shellx-core && cargo test -p shellx-core --test pairing)` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `(cd shellx-core && cargo test --workspace && scripts/c-smoke.sh)` — Expected: PASS. Report "ready <sha>" (L6 can now link `shellx-core` as a path crate).
- [ ] **Step 5: Security review** — checklist: no POST before all refusals; fingerprint computed from the exact bytes sealed to; AAD = pairing id on both ends; invite parsing never logs the secret; invite file 0600 and removed by the caller after use (Task 12); `suspicious` items can never be approved; `from_machine_id` always the stored own id. Fix findings.
- [ ] **Step 6: Commit** `git commit -m "feat(shellx-core): pairing request/pending/approve/deny/poll with local fingerprints and sealed invites"`

### Task 7: Virtual PTY in `cmux-tui-core` (production port of the spike)

Runs in parallel with Tasks 3–6 (second implementer; disjoint files).

**Files:**
- Create: `cmux-tui/crates/cmux-tui-core/src/virtual_pty.rs` (from `shellx/w0-bridge` @ `4e1ed7bc41`, `git show 4e1ed7bc41:cmux-tui/crates/cmux-tui-core/src/virtual_pty.rs`)
- Modify: `cmux-tui/crates/cmux-tui-core/src/lib.rs` (`#[cfg(unix)] mod virtual_pty; // ShellX:`), `cmux-tui/crates/cmux-tui-core/src/surface.rs` (apply the spike's hunks at `:2437-2549`, `:2569-2579`, `:2699-2714` — `git show 4e1ed7bc41 -- cmux-tui/crates/cmux-tui-core/src/surface.rs`; re-anchor if lines moved; mark each hunk `// ShellX:`)

**Interfaces:**
- Consumes: frame protocol from the spike header (`[type u8][len u32 BE][payload]`; daemon→app `H` hello JSON, `I` input, `R` resize wish, `K` kill; app→daemon `A` ack JSON, `O` output, `S` real grid, `E` exit). Enabled by env `CMUX_SHELLX_BRIDGE_SOCKET`.
- Produces (for Task 11): hello JSON `{"protocol":1,"cols","rows","cwd"}`; ack JSON `{"surface_id","workspace_id","mode":"attach"|"create"}`; frame size cap 16 MiB; after `open`, an app `S` frame always resizes the mirror (the forced echo); `E` or EOF ends the child; `K` is sent by `ChildKiller::kill`.
- Changes vs spike: (a) before `connect`, refuse a socket whose parent dir is a symlink, not owned by euid, or has any `0o077` bit (error contains `"shellx bridge: insecure socket directory"`); (b) hello carries `"protocol":1`; (c) replace `eprintln!` traces with the logging used next to `surface.rs:2699` (or drop them); never log payload bytes; (d) header comment: "ShellX file in an upstream crate; see docs/superpowers/plans/2026-10-19-native-desktop-w2-mac-remote.md Task 7".

- [ ] **Step 1: Write the failing tests** (in `virtual_pty.rs` `mod tests`, using the spike's fake-app pattern; each test makes its socket dir `0700`)

```rust
#[test] fn virtual_pty_round_trips_output_input_and_sizes() { /* spike test, kept */ }
#[test] fn virtual_pty_forwards_vietnamese_utf8_unchanged() {        // Review Focus 4
    writer.write_all("tiếng Việt\r".as_bytes()).unwrap();
    assert_eq!(app_received_input(), vec![0x74,0x69,0xe1,0xba,0xbf,0x6e,0x67,0x20,0x56,0x69,0xe1,0xbb,0x87,0x74,0x0d]);
}
#[test] fn split_utf8_output_reaches_reader_in_order() { /* app sends O "Vi\xe1\xbb" then O "\x87t"; reader yields "Việt" bytes */ }
#[test] fn forced_host_size_reaches_handler_even_if_unchanged() { /* S 44x37 twice → handler called twice */ }
#[test] fn app_exit_frame_ends_child() { /* app sends E → child.wait() returns, try_wait Some */ }
#[test] fn refuses_socket_in_world_accessible_dir() { /* dir 0777 → open() Err contains "insecure socket directory" */ }
#[test] fn hello_carries_protocol_1() {}
#[test] fn oversize_frame_is_rejected() {}
```

- [ ] **Step 2: Push and run on CI (not locally — disk):** `git push … shellx/l5-remote && gh workflow run cmux-tui.yml -R lephus/shellx-pro -f commit=$(git rev-parse HEAD) -f mode=focused -f test_filter=virtual_pty -f request_id=l5-vpty-$(date +%s)` — Expected: FAIL (module missing).
- [ ] **Step 3: Implement** the port and the four changes.
- [ ] **Step 4: Rerun the CI command** — Expected: the focused job is green and its log lists the 8 `virtual_pty::tests::*` as `ok`. Locally only `cargo check -p cmux-tui-core` (with `CARGO_TARGET_DIR` shared) if `df -h ~` shows ≥ 15 GB free.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx): virtual PTY seam in cmux-tui-core for Mac-owned terminals (from W0 bridge spike)"`

### Task 8: Remote e2e harness and `shellx-remote.yml` (2 s tickets, Vietnamese, sealed-invite enrollment)

**Files:**
- Create: `scripts/shellx/remote-e2e/harness.py` (process control), `scripts/shellx/remote-e2e/fake_app.py` (spike `fake_app.py` + records every `I` payload to a log as hex), `tests/test_shellx_remote_e2e.py`, `.github/workflows/shellx-remote.yml`
- Modify: `tests/test-execution.toml` (`tests/test_shellx_remote_e2e.py`, `lane = "manual"`, `reason = "needs built cmux-tui, cmux-relay, shellx-core-cli and shellx-fake-api; run by .github/workflows/shellx-remote.yml"`)

**Interfaces:**
- Consumes: `shellx-core-cli` (Task 1), `shellx-fake-api` (Tasks 3–6), patched `cmux-tui` (Task 7), stock `cmux-relay` (same workspace).
- Produces: `harness.py` class `Harness(bin_dir, core_bin_dir, ticket_ttl)` with `start_relay()`, `stop_relay()`, `start_api()`, `machine(name) -> Machine` (own core state dir 0700 + `SHELLX_CORE_CONFIG`), `Machine.core(method, **params) -> dict`, `Machine.start_ticket_refresher(write_to, permission, target=None)` (thread: mint, then sleep `max(1, (exp-now)/2)`), `start_host_daemon(machine)` (fake app + `cmux-tui server start --session e2e-<name> --headless --ephemeral --socket … --remote-state-dir … --relay <route> --relay-slot <slot> --relay-ticket-file <core>/tickets/register.ticket`, env `CMUX_SHELLX_BRIDGE_SOCKET`), `pair(viewer, host) -> invitation_id` (viewer `pair.request` → host `pair.pending` → host `tickets.mint connect target=self write_to=invite-connect.ticket` → host `remote enroll create --session … --state-dir … --advertise <route> --relay-route <route> --relay-slot <slot> --relay-ticket-file … --ttl 300` → host `pair.approve` → viewer `pair.poll write_invite_to=invite.uri`), `connect_viewer(viewer, host)` (`remote connect <route> --invite-file … --relay-slot … --relay-ticket-file … --state-dir … --local-socket … --headless --device-name <name>`), `approve_pending(host, invitation_id)`, `viewer_cli(*args)`; every process runs under `env -i` with `HOME`/`TMPDIR` inside the harness dir; all temp secrets removed in `tearDown`.

- [ ] **Step 1: Write the failing tests**

```python
class RemoteE2E(unittest.TestCase):
    def test_enroll_via_sealed_invite_and_view(self):
        inv = self.h.pair(self.viewer, self.host); self.h.connect_viewer(self.viewer, self.host)
        pending = self.h.host_cli(self.host, "remote", "enroll", "pending", "--json")
        self.assertEqual([p["invitation_id"] for p in pending], [inv])        # only ours
        self.h.approve_pending(self.host, inv)
        ws = self.h.viewer_cli("workspace", "create", "--name", "e2e", "--json")
        term = self.h.first_terminal()
        self.assertIn("SHELLX-FAKE-APP", self.h.viewer_cli("terminal", term, "screen", "read"))
    def test_vietnamese_round_trip(self):                                    # Review Focus 4
        self.h.viewer_cli("terminal", self.term, "write", "--text", "tiếng Việt\r")
        self.assertTrue(self.h.fake_app_input().endswith(bytes.fromhex("7469e1babf6e672056 69e1bb8774 0d".replace(" ", ""))))
    def test_reconnect_after_relay_restart_with_2s_tickets(self):            # Review Focus 2 (ticket_ttl=2)
        self.h.stop_relay(); time.sleep(5)           # every ticket written before the outage has expired
        self.h.start_relay()                          # same port + secret
        self.assertTrue(wait_until(45, lambda: self.h.viewer_ok("terminal", "list", "--json")))
        for log in self.h.logs(): self.assertNotRegex(log, r"v2\.[A-Za-z0-9_-]{20,}\.")   # no ticket in any log
    def test_enrolled_device_reconnects_after_daemon_restart(self):
        self.h.restart_host_daemon(self.host)         # same --remote-state-dir, fresh --ephemeral mux
        self.assertTrue(wait_until(45, lambda: self.h.viewer_ok("workspace", "list", "--json")))
        self.assertEqual(self.h.host_cli(self.host, "remote", "enroll", "pending", "--json"), [])
```

`setUp` builds nothing; it reads `SHELLX_E2E_BIN` (cmux-tui target dir) and `SHELLX_E2E_CORE_BIN` (shellx-core target dir), `skipTest` with the exact build commands if missing.

- [ ] **Step 2: Run locally only if disk allows, else CI:** `SHELLX_E2E_BIN=… SHELLX_E2E_CORE_BIN=… python3 tests/test_shellx_remote_e2e.py` — Expected: FAIL (harness missing).
- [ ] **Step 3: Implement** `harness.py`, `fake_app.py`, and `shellx-remote.yml`: triggers `push` on `shellx/**` with `paths` (`shellx-core/**`, `cmux-tui/crates/cmux-tui-core/src/virtual_pty.rs`, `cmux-tui/crates/cmux-tui-core/src/surface.rs`, `scripts/shellx/remote-e2e/**`, `tests/test_shellx_remote*.py`, `Packages/Shared/ShellXBrand/**`, `.github/workflows/shellx-remote.yml`) + `workflow_dispatch`; `permissions: contents: read`; concurrency per ref, cancel in progress; actions pinned by full sha (copy pins from `cmux-tui.yml`). Jobs: `core` (matrix `ubuntu-24.04`, `macos-26`: `cargo test --workspace --locked` in `shellx-core`, `python3 scripts/check_deps.py`, `scripts/c-smoke.sh` on macOS); `swift-package` (`macos-26`: `swift test --package-path Packages/Shared/ShellXBrand`); `bridge-e2e` (`ubuntu-24.04`, timeout 60: `./scripts/install-zig-ci.sh`, `./.github/actions/setup-cmux-tui-rust`, env `CMUX_GHOSTTY_VT_ZIG_CPU=baseline`, `cargo test -p cmux-tui-core --lib virtual_pty --locked`, `cargo build -p cmux-tui -p cmux-relay --locked`, `cargo build --workspace --locked` in `shellx-core`, then the e2e test).
- [ ] **Step 4: Push and watch** `gh run watch -R lephus/shellx-pro $(gh run list -R lephus/shellx-pro -w shellx-remote -b shellx/l5-remote -L1 --json databaseId -q '.[0].databaseId')` — Expected: all three jobs green; the e2e log shows 4 tests `ok`.
- [ ] **Step 5: Commit** `git commit -m "test(shellx): remote e2e harness (fake API, cmux-relay, patched daemon) and shellx-remote CI"`
- [ ] **Step 6 (only if L0 refuses D3):** add `test_invite_with_placeholder_ticket` — host creates the invite with a ticket file containing `shellx-no-ticket` and the viewer connects with its own connect ticket; record pass/fail in the lane report; on fail, escalate to L0 (no other fallback is safe).

### Task 9: Build the bundled `cmux-tui` and link `shellx-core` into the app

**Files:**
- Create: `scripts/shellx/build-cmux-tui.sh`, `scripts/shellx/build-shellx-core.sh`, `Sources/ShellX/Remote/ShellXCoreFFI.swift`, `tests/test_shellx_remote.py`, `cmuxTests/ShellXCoreFFITests.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (target `cmux`: Run Script phase "ShellX core" placed before Compile Sources, `"${SRCROOT}/scripts/shellx/build-shellx-core.sh"`, inputs `$(SRCROOT)/shellx-core/Cargo.lock`, output `$(TARGET_BUILD_DIR)/shellx-core/libshellx_core.a`; `LIBRARY_SEARCH_PATHS += $(TARGET_BUILD_DIR)/shellx-core`; `HEADER_SEARCH_PATHS += $(SRCROOT)/shellx-core/include`; `OTHER_LDFLAGS += -lshellx_core` + the frameworks printed by `--print native-static-libs`), `cmux-Bridging-Header.h` (`#include "shellx_core.h" // ShellX:`), `scripts/shellx/sign-and-notarize.sh` (L0's file: before signing, `CMUX_TUI_CLIENT_LOCAL="$(scripts/shellx/build-cmux-tui.sh --release --arch universal)" scripts/install-cmux-tui-client.sh "$APP"` — flag it in the "ready" report), `tests/test-execution.toml` (`tests/test_shellx_remote.py`, lane `linux-guard`)

**Interfaces:**
- Produces: `scripts/shellx/build-cmux-tui.sh [--release] [--arch native|universal]` → prints the absolute path of the built `cmux-tui` (default features; `lipo` for universal); exits 2 if `CMUX_TUI_CLIENT_MANIFEST_URL` is set. Dev build recipe used by every later task: `CMUX_TUI_CLIENT_LOCAL="$(scripts/shellx/build-cmux-tui.sh)" CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag l5`.
- `scripts/shellx/build-shellx-core.sh` mirrors `scripts/build-command-palette-nucleo-ffi.sh` (targets from `ARCHS`/`TARGET_TRIPLE`, `rustup target add`, `cargo build --release --locked --target …`, `lipo` into `$(TARGET_BUILD_DIR)/shellx-core/libshellx_core.a`); fails (no skip) when cargo is missing.
- `ShellXCoreFFI` (app target): `final class ShellXCoreFFI: @unchecked Sendable { static let shared = ShellXCoreFFI(); func call(method: String, json: Data) throws -> Data }`; DEBUG-asserts `!Thread.isMainThread`. Task 13 adds `extension ShellXCoreFFI: ShellXCoreCalling {}` (the protocol comes from Task 10, which runs in parallel).

- [ ] **Step 1: Write the failing tests**

```python
class ShellXRemoteGuards(unittest.TestCase):
    def test_cmux_tui_is_built_from_this_fork(self):
        s = read("scripts/shellx/build-cmux-tui.sh")
        self.assertNotIn("files.cmux.com", s); self.assertNotIn("iroh-transport", s)
    def test_shellx_code_never_downloads_manaflow_artifacts(self):
        self.assertEqual(offenders(r"files\.cmux\.com|manaflow-ai/cmux/\.github", roots=["scripts/shellx", "shellx-core", "Sources/ShellX"], allow=[]), [])
    def test_core_lock_has_no_forbidden_crates(self):
        lock = read("shellx-core/Cargo.lock")
        for name in ["aws-lc-rs", "aws-lc-sys", "openssl-sys", "native-tls", "iroh"]:
            self.assertNotIn(f'name = "{name}"', lock)
    def test_core_is_linked_statically(self):
        pbx = read("cmux.xcodeproj/project.pbxproj")
        self.assertIn("build-shellx-core.sh", pbx); self.assertIn("-lshellx_core", pbx)
    def test_remote_sources_import_no_cloud_stack(self):
        self.assertEqual(offenders(r"^\s*import (CmuxCloud|CmuxIrohTransport|CmuxIrxTransport|CMUXAuthCore|CmuxAuthRuntime)\b", roots=["Sources/ShellX/Remote"], allow=[]), [])
```

`read`/`offenders` come from `tests/shellx_guard.py` (W1 Task 2); if L1 has not merged it yet, copy those two helpers into this file with a `# TODO(checkpoint 1): import from shellx_guard` and remove the copy after checkpoint 1.

```swift
@Test func coreAnswersThroughFFI() async throws {
  let out = try await Task.detached { try ShellXCoreFFI.shared.call(method: "nope", json: Data("{}".utf8)) }.value
  #expect(String(decoding: out, as: UTF8.self).contains("\"unknown_method\""))
}
```

- [ ] **Step 2: Run** `python3 tests/test_shellx_remote.py` — Expected: FAIL.
- [ ] **Step 3: Implement** the scripts, pbxproj wiring (`scripts/wire-app-sources.py Sources/ShellX/Remote/ShellXCoreFFI.swift`, `scripts/sync-test-wiring`), bridging-header line.
- [ ] **Step 4: Run** `python3 tests/test_shellx_remote.py` → PASS; take the build lock, `CMUX_TUI_CLIENT_LOCAL="$(scripts/shellx/build-cmux-tui.sh)" CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag l5 --build-only` → succeeds; `"<app>/Contents/Resources/bin/cmux-tui" --version` prints a version; `nm -gU "<app>/Contents/MacOS/cmux" | grep -c shellx_core_call` → `1`; `scripts/shellx/test-app.sh ShellXCoreFFITests` → PASS; `python3 scripts/verify-local.py --all` → PASS. Release the lock.
- [ ] **Step 5: Commit** `git commit -m "build(shellx): bundle fork-built cmux-tui and link shellx-core statically into the app"`

### Task 10: `ShellXRemoteCore` package target (pure Swift)

Push as soon as it is green and ask L0 to merge it into `shellx/sprint` early: Part B builds on these types.

**Files:**
- Modify: `Packages/Shared/ShellXBrand/Package.swift` (library product `ShellXRemoteCore`; target `ShellXRemoteCore` (Foundation only); test target `ShellXRemoteCoreTests`); link `ShellXRemoteCore` to the `cmux` app target in the pbxproj
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/{RemoteModels,RemotePaths,ReconnectBackoff,LinkStateMachine,TicketSchedule,BridgeFrame,InviteURI,ApprovalGate,RelayRoute,RemoteCommandLine,ShellXCoreClient,PairingDisplay}.swift`
- Test: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/*.swift`

**Interfaces (all `public`, `Sendable`):**

```swift
public struct RemoteMachine: Identifiable, Equatable, Sendable {
  public typealias ID = String                      // K1 machine_id
  public enum Platform: String, Sendable { case macos, windows }
  public enum Access: Equatable, Sendable { case none, requested(pairingID: String, code: String), granted }
  public let id: ID; public var name: String; public var platform: Platform
  public var online: Bool; public var lastSeen: Date?; public var fingerprint: String
  public var isThisMachine: Bool; public var access: Access; public var link: LinkState
}
public enum LinkState: Equatable, Sendable {
  case idle, connecting, connected(localSocket: String)
  case reconnecting(attempt: Int, retryAt: Date), offline(lastSeen: Date?), failed(code: String)
}
public struct PairingRequest: Identifiable, Equatable, Sendable {   // incoming, target side
  public typealias ID = String
  public let id: ID; public let fromMachineID: RemoteMachine.ID; public let requesterName: String
  public let code: String; public let fingerprint: String; public let suspicious: Bool; public let firstSeen: Date
  public var expiresAt: Date { firstSeen.addingTimeInterval(300) }
}
public struct OutgoingPairing: Identifiable, Equatable, Sendable {  // requester side
  public enum Status: Equatable, Sendable { case waiting, approved, denied, expired, failed(code: String) }
  public let id: String; public let toMachineID: RemoteMachine.ID; public let code: String
  public let ownFingerprint: String; public var status: Status; public let createdAt: Date
}
public struct RemotePaths: Equatable, Sendable {
  public init(bundleID: String, home: URL, temporaryDirectory: URL)
  public let stateRoot, coreStateDir, daemonStateDir, clientStateDir, socketDir, muxSocket, bridgeSocket, adminSocket, linkSocket: URL
  public let session: String
  public func clientSocket(for machine: RemoteMachine.ID) -> URL
  public func connectTicketName(for machine: RemoteMachine.ID) -> String   // "connect-<hash8>.ticket"
}
public struct ReconnectBackoff: Sendable { public static func delay(attempt: Int, jitter: Double = 1) -> TimeInterval }
public enum LinkEvent: Equatable, Sendable { case start, connected(localSocket: String), exited(status: Int32), mintFailed(code: String), machineOffline(lastSeen: Date?), machineOnline, retryDue, stop }
public enum LinkAction: Equatable, Sendable { case mintTicket, spawn, kill, scheduleRetry(at: Date), publish(LinkState) }
public struct LinkStateMachine: Sendable { public init(); public private(set) var state: LinkState; public mutating func handle(_ e: LinkEvent, now: Date) -> [LinkAction] }
public enum TicketSchedule { public static func nextRefresh(expiresAt: Date, now: Date) -> TimeInterval }
public enum BridgeFrameType: UInt8, Sendable { case hello = 0x48, input = 0x49, resize = 0x52, kill = 0x4B, ack = 0x41, output = 0x4F, size = 0x53, exit = 0x45 }
public struct BridgeFrame: Equatable, Sendable { public let type: BridgeFrameType; public let payload: Data
  public func encoded() -> Data; public static func size(cols: UInt16, rows: UInt16) -> BridgeFrame }
public struct BridgeFrameDecoder: Sendable { public static let maxPayload = 16 << 20
  public mutating func feed(_ bytes: Data) throws -> [BridgeFrame] }      // throws on oversize / unknown type
public struct InviteSummary: Equatable, Sendable { public let invitationID: String; public let relayRoute: String; public let relaySlot: String; public let daemonFingerprint: String }
public enum InviteURI { public static func summary(of uri: String) throws -> InviteSummary }   // never stores `secret`
public struct ApprovalGate: Sendable {
  public mutating func expect(invitationID: String, pairingID: String, now: Date)
  public mutating func decide(pendingInvitationID: String, now: Date) -> Decision   // .approve(pairingID) once, else .deny
  public enum Decision: Equatable, Sendable { case approve(pairingID: String), deny }
}
public enum RelayRoute { public static func cmuxRoute(from url: String) throws -> String }   // D6
public enum RemoteCommandLine {
  public static func serverStop(paths: RemotePaths) -> [String]
  public static func serverStart(paths: RemotePaths, route: String, slot: String, ticketFile: URL) -> [String]
  public static func enrollStatus(paths: RemotePaths) -> [String]
  public static func enrollCreate(paths: RemotePaths, route: String, slot: String, ticketFile: URL, ttlSeconds: Int) -> [String]
  public static func enrollPending(paths: RemotePaths) -> [String]
  public static func enrollApprove(paths: RemotePaths, invitationID: String) -> [String]
  public static func enrollDeny(paths: RemotePaths, invitationID: String) -> [String]
  public static func connect(paths: RemotePaths, machine: RemoteMachine.ID, route: String, slot: String, ticketFile: URL, inviteFile: URL?, deviceName: String) -> [String]
  public static func attachShellCommand(clientPath: String, socketPath: String, terminalID: String) -> String   // D8 wrapper
}
public protocol ShellXCoreCalling: Sendable { func call(method: String, json: Data) throws -> Data }
public struct ShellXCoreError: Error, Equatable, Sendable { public let code: String; public let message: String }
public struct ShellXCoreClient: Sendable {
  public init(_ core: ShellXCoreCalling)
  public func call<R: Decodable>(_ method: String, _ params: [String: JSONValue] = [:], as: R.Type) throws -> R   // throws ShellXCoreError
}
public enum PairingDisplay { public static func code(_ c: String) -> String; public static func fingerprint(_ f: String) -> String }
```

Exact values: `RemotePaths` — `hash8` = first 8 lowercase hex of SHA-256(UTF-8 bundleID) (use a small pure-Swift SHA-256 in the package; no CryptoKit dependency); `stateRoot = home/Library/Application Support/ShellX/remote/<bundleID>`; `coreStateDir = stateRoot/core`; `daemonStateDir = stateRoot/daemon`; `clientStateDir = stateRoot/client`; `socketDir = temporaryDirectory/sx-<hash8>` (per-user `NSTemporaryDirectory()`); sockets `mux.sock`, `bridge.sock`, `admin.sock`, `link.sock`, `c-<hash8(machineID)>.sock`; `session = "shellx-<hash8>"`. Backoff = `min(30, 2^attempt) * jitter` seconds (attempt 0 → 1). `TicketSchedule.nextRefresh = max(1, (expiresAt - now) / 2)`. `serverStart` argv = `["server", "start", "--session", session, "--socket", mux, "--headless", "--ephemeral", "--remote-state-dir", daemonStateDir, "--remote-admin-socket", admin, "--remote-link-socket", link, "--relay", route, "--relay-slot", slot, "--relay-ticket-file", ticket]`; `serverStop` = `["server", "stop", "--session", session, "--socket", mux, "--force"]`; enroll commands use `["remote", "enroll", <action>, …, "--session", session, "--state-dir", daemonStateDir, "--admin-socket", admin]` (+ `"--json"` for status/pending; create adds `"--advertise", route, "--relay-route", route, "--relay-slot", slot, "--relay-ticket-file", ticket, "--ttl", "300"`); `connect` = `["remote", "connect", route, "--relay-slot", slot, "--relay-ticket-file", ticket, "--state-dir", clientStateDir, "--local-socket", clientSocket, "--headless", "--json", "--exit-with-parent", "--device-name", name]` + `["--invite-file", path]` when given. `attachShellCommand` = `sh -c` loop: run `<client> --socket <sock> attach --terminal <id>`; on non-zero exit print `\r\n[ShellX] đang kết nối lại… / reconnecting…\r\n`, sleep 2, retry; after 10 consecutive failures print `[ShellX] phiên đã kết thúc / session ended` and exit 0; every argument shell-quoted like `CloudTuiCommandLine.shellQuote`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func pathsAreDistinctPerBundleAndFitSunPath() {                       // Review Focus 1
  let home = URL(fileURLWithPath: "/Users/phu"), tmp = URL(fileURLWithPath: "/var/folders/ab/cdefghijklmnop_qrstuvwx0000gn/T")
  let rel = RemotePaths(bundleID: "pro.shellx.desktop", home: home, temporaryDirectory: tmp)
  let dev = RemotePaths(bundleID: "pro.shellx.desktop.debug.l5", home: home, temporaryDirectory: tmp)
  let relAll = [rel.coreStateDir, rel.daemonStateDir, rel.clientStateDir, rel.muxSocket, rel.bridgeSocket, rel.adminSocket, rel.linkSocket]
  let devAll = [dev.coreStateDir, dev.daemonStateDir, dev.clientStateDir, dev.muxSocket, dev.bridgeSocket, dev.adminSocket, dev.linkSocket]
  #expect(Set(relAll).isDisjoint(with: devAll)); #expect(rel.session != dev.session)
  for s in [rel.muxSocket, rel.bridgeSocket, rel.adminSocket, rel.linkSocket, rel.clientSocket(for: "m_" + String(repeating: "x", count: 40))] { #expect(s.path.utf8.count < 104) }
}
@Test func backoffSchedule() { #expect((0...7).map { ReconnectBackoff.delay(attempt: $0) } == [1, 2, 4, 8, 16, 30, 30, 30]) }
@Test func linkExitSchedulesRetryAndMintsBeforeEachSpawn() {
  var m = LinkStateMachine(); let t0 = Date(timeIntervalSince1970: 1000)
  #expect(m.handle(.start, now: t0) == [.publish(.connecting), .mintTicket, .spawn])
  #expect(m.handle(.exited(status: 1), now: t0) == [.publish(.reconnecting(attempt: 1, retryAt: t0 + 1)), .scheduleRetry(at: t0 + 1)])
  #expect(m.handle(.retryDue, now: t0 + 1) == [.mintTicket, .spawn])
  _ = m.handle(.exited(status: 1), now: t0 + 1); #expect(m.state == .reconnecting(attempt: 2, retryAt: t0 + 3))
  _ = m.handle(.connected(localSocket: "/s"), now: t0 + 4); _ = m.handle(.exited(status: 1), now: t0 + 9)
  #expect(m.state == .reconnecting(attempt: 1, retryAt: t0 + 10))         // reset after a good connection
}
@Test func offlineMachineStopsRetriesUntilOnline() { /* .machineOffline → [.kill, .publish(.offline)], .retryDue ignored; .machineOnline → [.publish(.connecting), .mintTicket, .spawn] */ }
@Test func unauthorizedMintFailsWithoutRetry() { /* .mintFailed("unauthorized") → .failed("unauthorized"), no scheduleRetry; .mintFailed("network") → reconnecting */ }
@Test func ticketRefreshAtHalfLifeMinOneSecond() { #expect(TicketSchedule.nextRefresh(expiresAt: t0 + 120, now: t0) == 60); #expect(TicketSchedule.nextRefresh(expiresAt: t0 + 2, now: t0) == 1) }
@Test func decoderKeepsSplitUTF8ByteExact() {                                // Review Focus 4
  let bytes = Data("tiếng Việt\r".utf8); var d = BridgeFrameDecoder()
  let enc = BridgeFrame(type: .input, payload: bytes).encoded()
  var out: [BridgeFrame] = []; for b in enc { out += try! d.feed(Data([b])) }
  #expect(out == [BridgeFrame(type: .input, payload: bytes)])
  #expect(Array(bytes) == [0x74,0x69,0xe1,0xba,0xbf,0x6e,0x67,0x20,0x56,0x69,0xe1,0xbb,0x87,0x74,0x0d])
}
@Test func decoderRejectsOversizeAndUnknownType() {}
@Test func inviteSummaryNeverExposesSecret() { /* fixture invite JSON with secret "S3CRET…" → summary fields right; String(describing: summary) lacks "S3CRET" */ }
@Test func gateApprovesOnlyIssuedInvitationOnce() { var g = ApprovalGate(); g.expect(invitationID: "inv1", pairingID: "p1", now: t0)
  #expect(g.decide(pendingInvitationID: "inv1", now: t0 + 5) == .approve(pairingID: "p1")); #expect(g.decide(pendingInvitationID: "inv1", now: t0 + 6) == .deny) }
@Test func gateDeniesUnknownInvitation() { #expect(ApprovalGate().decide(pendingInvitationID: "x", now: t0) == .deny) }   // Review Focus 3
@Test func gateExpiresAfter300s() {}
@Test func relayRouteMapping() { #expect(try RelayRoute.cmuxRoute(from: "wss://relay.shellx.pro/v2/relay") == "relay+wss://relay.shellx.pro/v2/relay")
  #expect(throws: (any Error).self) { try RelayRoute.cmuxRoute(from: "https://x") } }
@Test func serverStartArgv() { /* exact array from Interfaces for a fixed RemotePaths */ }
@Test func attachWrapperQuotesAndLoops() { /* contains "attach" "--terminal" "'term_1'"; contains "reconnecting"; socket path with a space is quoted */ }
@Test func coreClientMapsErrorEnvelope() { /* FakeCore returns {"error":{"code":"fingerprint_mismatch","message":"m"}} → throws ShellXCoreError(code: "fingerprint_mismatch", message: "m") */ }
@Test func displayFormats() { #expect(PairingDisplay.code("123456") == "123 456"); #expect(PairingDisplay.fingerprint("a1b2c3d4e5f60718") == "a1b2 c3d4 e5f6 0718") }
```

- [ ] **Step 2: Run** `swift test --package-path Packages/Shared/ShellXBrand` — Expected: FAIL.
- [ ] **Step 3: Implement.** `LinkStateMachine` transition table (the tests above are its spec): `start`/`machineOnline`/`retryDue` → mint + spawn; `exited` → attempt += 1 (reset to 0 on `connected`), schedule `now + delay(attempt-1)`; `machineOffline` → kill, no retries; `mintFailed` with `unauthorized`/`forbidden`/`not_logged_in` → `failed`, else like `exited`; `stop` → kill, `idle`.
- [ ] **Step 4: Run** the same command — Expected: PASS. Push; post "ready (package) <sha>" to L0 and L3.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx): ShellXRemoteCore — models, per-bundle paths, backoff, link state machine, bridge frames, approval gate, argv builders"`

### Task 11: Bridge server in the app (security review)

**Files:**
- Create: `Sources/ShellX/Remote/Bridge/ShellXBridgeServer.swift`, `Sources/ShellX/Remote/Bridge/ShellXBridgeTee.swift`, `Sources/ShellX/Remote/Bridge/TerminalControllerBridgeHost.swift`
- Modify: `Sources/TerminalOutputTeeCallback.swift:14` (after `MobileTerminalByteTee.shared.append(…)`: `ShellXBridgeTee.consume(surfaceID: context.surfaceID, buffer: buffer) // ShellX:`), `scripts/shellx/remote-e2e/harness.py` (flag `--app-bridge <socket>`: skip `fake_app.py`, point the host daemon at a running app's bridge socket, start relay + fake API + daemon + stock viewer, print the viewer CLI env), `Sources/AppDelegate.swift` (temporary `#if DEBUG` bridge start when `SHELLX_REMOTE_MACHINES=1`, removed in Task 13)
- Test: `cmuxTests/ShellXBridgeServerTests.swift`

**Interfaces:**
- Consumes: `BridgeFrame`, `BridgeFrameDecoder`, `RemotePaths` (Task 10); spike `Sources/Mobile/ShellXBridgeSpike.swift` (`git show 4e1ed7bc41:Sources/Mobile/ShellXBridgeSpike.swift`) for bind/input/resize/size-poll/unbind logic.
- Produces:
  - `@MainActor protocol ShellXBridgeHost: AnyObject { func bind(hello: BridgeHello) -> BridgeBinding?; func input(_ bytes: Data, binding: BridgeBinding); func remoteResize(cols: UInt16, rows: UInt16, binding: BridgeBinding); func grid(binding: BridgeBinding) -> (cols: UInt16, rows: UInt16)?; func snapshot(binding: BridgeBinding) -> Data?; func unbind(_ binding: BridgeBinding) }` with `struct BridgeHello { cols, rows: UInt16; cwd: String?; protocolVersion: Int }`, `struct BridgeBinding: Hashable { connectionID: Int; surfaceID: UUID; workspaceID: UUID; mode: String }` (`grid == nil` means the surface is gone).
  - `TerminalControllerBridgeHost: ShellXBridgeHost` = the spike's `bind` (D7 rule: attach the focused terminal when no binding exists, else `Workspace.newTerminalSurface` in the focused workspace), `input` via `ghostty_surface_text_input` with the bytes as received, `remoteResize` via `TerminalController.v2MobileTerminalViewport` (`client_id "shellx-bridge-<id>"`, `device_kind "tui"`, `device_name "ShellX remote"`), `snapshot` = `"\u{1b}[H\u{1b}[2J" + readBoundedScreenTailVT(maxRows: 200, maxBytes: 1 << 20)` for attach only, `unbind` clears the viewport participant.
  - `final class ShellXBridgeServer { init(socket: URL, host: ShellXBridgeHost, uid: @escaping () -> uid_t = getuid); func start() throws; func stop() }` — creates the socket dir `0700` (refuses an existing dir that is a symlink, foreign-owned or has `0o077` bits), binds under `umask(0o077)`, `chmod 0600`; on accept checks `getpeereid` uid == `uid()` else closes; max 32 connections; per connection: read `H` → `bind` on main → send `A`, forced `S`, snapshot `O` (tee held until then, as in the spike); `I` → `input` byte-exact; `R` → `remoteResize` then forced `S`; `K`/EOF → `unbind` only (D7); 200 ms poll: grid changed → `S`; grid nil → send `E` and unbind. Logs only counts via `Logger(subsystem: "pro.shellx.desktop", category: "remote-bridge")`.
  - `enum ShellXBridgeTee { static func consume(surfaceID: UUID, buffer: UnsafeBufferPointer<UInt8>) }` — spike registry; no-op unless a connection is bound to that surface.

- [ ] **Step 1: Write the failing tests** (fake host, real Unix socket in a temp dir)

```swift
@Test func socketAndDirAreOwnerOnly() throws { let s = try startServer(); #expect(mode(s.socket) == 0o600); #expect(mode(s.socket.deletingLastPathComponent()) == 0o700) }
@Test func refusesForeignPeer() throws { /* uid closure returns getuid()+1 → client gets EOF without an A frame */ }
@Test func refusesInsecureExistingDir() { /* chmod 0755 dir → start() throws */ }
@Test func helloGetsAckSizeThenSnapshot() throws { /* frames in order: A{"mode":"attach"}, S(94x37), O(snapshot) */ }
@Test func inputReachesHostByteExact() throws {                             // Review Focus 4
  let bytes = Data("tiếng Việt\r".utf8); try client.send(.input, bytes.prefix(8)); try client.send(.input, bytes.dropFirst(8))
  #expect(await host.receivedInput == bytes)
}
@Test func remoteResizeAlwaysEchoesHostGrid() throws { /* R 120x40 while host grid 80x24 → host.remoteResize called, then S 80x24 even though unchanged */ }
@Test func surfaceGoneSendsExit() throws { /* host.grid returns nil → client receives E; host.unbind called */ }
@Test func killUnbindsWithoutClosingSurface() throws { /* K → host.unbind called; host.closedSurfaces is empty */ }
```

- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXBridgeServerTests` — Expected: FAIL.
- [ ] **Step 3: Implement**; wire files with `scripts/wire-app-sources.py` and `scripts/sync-test-wiring`.
- [ ] **Step 4: Run** the suite — Expected: PASS. Live check (bridge server started from a DEBUG-only call in `AppDelegate` guarded by `SHELLX_REMOTE_MACHINES=1`, replaced by the service in Task 13): launch the Task 9 dev build, run `python3 scripts/shellx/remote-e2e/harness.py --app-bridge "$TMPDIR/sx-<hash8>/bridge.sock"` from `/private/tmp` (TCC note in the ledger) → viewer `terminal <id> screen read` shows the focused ShellX terminal; `write --text $'echo $((6*7))\r'` prints `42` in the Mac pane.
- [ ] **Step 5: Security review** — checklist: dir/socket perms and refusal of pre-existing insecure dirs, peer uid check before any read, connection cap, frame cap enforced before allocation, no payload logging, input never converted to `String`, tee hot path allocation-free when unbound, main-thread hops only for TerminalController calls. Fix findings.
- [ ] **Step 6: Commit** `git commit -m "feat(shellx): bridge server serving Mac terminals to the cmux-tui virtual PTY"`

### Task 12: Supervisors — daemon, client link, ticket refresher (security review)

**Files:**
- Create: `Sources/ShellX/Remote/{ShellXSidecarProcess,ShellXDaemonSupervisor,ShellXClientLinkSupervisor,ShellXTicketRefresher}.swift`; package `Sources/ShellXRemoteCore/{OwnerOnlyFile,RemoteLinkStore}.swift` + tests
- Test: `cmuxTests/ShellXSupervisorTests.swift`

**Interfaces:**
- Consumes: `LinkStateMachine`, `ReconnectBackoff`, `TicketSchedule`, `RemoteCommandLine`, `RemotePaths`, `ShellXCoreClient` (Task 10).
- Produces:
  - `protocol SidecarLaunching: Sendable { func run(_ executable: URL, _ args: [String], env: [String: String]) async throws -> (status: Int32, stdout: Data); func launch(_ executable: URL, _ args: [String], env: [String: String], onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (Int32) -> Void) throws -> SidecarHandle }`, `protocol SidecarHandle: Sendable { func terminate() }`; `ShellXSidecarProcess: SidecarLaunching` (Foundation `Process`, env scrubbed to `HOME`, `PATH=/usr/bin:/bin`, `LANG`, `TMPDIR`, plus given keys).
  - `protocol RemoteClock: Sendable { var now: Date { get }; func sleep(until: Date) async throws }`.
  - `actor ShellXTicketRefresher { init(core: ShellXCoreClient, clock: RemoteClock); func keepFresh(name: String, permission: String, target: RemoteMachine.ID?) async throws -> URL /* first mint done */; func stop(name: String) }` — mints via `tickets.mint {permission, target_machine_id?, write_to: name}`, sleeps `TicketSchedule.nextRefresh`, on failure retries with `ReconnectBackoff`; returns the path from the first successful mint; also exposes `func mintNow(name:) async throws` used before every spawn.
  - `actor ShellXDaemonSupervisor { init(paths: RemotePaths, cmuxTui: URL, core: ShellXCoreClient, refresher: ShellXTicketRefresher, launcher: SidecarLaunching, clock: RemoteClock); func start(route: String, slot: String) async; func stop() async; var stateStream: AsyncStream<LinkState> }` — start: ensure `socketDir`/`daemonStateDir` (0700) → `run(serverStop)` (ignore status; Review Focus 5) → `refresher.keepFresh("register.ticket", "register")` → `launch(serverStart)` with env `CMUX_SHELLX_BRIDGE_SOCKET=<bridgeSocket>` → poll `run(enrollStatus)` every 250 ms up to 10 s → `.connected(localSocket: muxSocket)`; on exit feed `LinkStateMachine`; `mintNow` before each respawn; `stop` = terminate + `run(serverStop)`.
  - `actor ShellXClientLinkSupervisor { init(machine: RemoteMachine.ID, record: RemoteLinkRecord, deviceName: String, paths:, cmuxTui:, refresher:, launcher:, clock:); func start(inviteFile: URL?) async; func machineAvailability(online: Bool, lastSeen: Date?) async; func stop() async; var stateStream: AsyncStream<LinkState> }` — ticket name `paths.connectTicketName(for:)`, `permission "connect"`, `target = machine`; spawn `RemoteCommandLine.connect`; a stdout line whose JSON has `"event":"connection-snapshot"` → `.connected(localSocket: clientSocket)`; after the first `.connected` with an invite file, delete the invite file and set `record.enrolled = true`.
  - Package: `enum OwnerOnlyFile { static func write(_ data: Data, to url: URL) throws; static func read(_ url: URL) throws -> Data? }` (same rules as Task 2, Swift: `open(O_CREAT|O_EXCL|O_NOFOLLOW, 0o600)` temp + `fchmod` + `rename`; read refuses symlink / foreign owner / `0o077` bits; parent dir must be `0700`); `struct RemoteLinkRecord: Codable, Equatable, Sendable { machineID, route, slot, daemonFingerprint: String; enrolled: Bool }`; `struct RemoteLinkStore { init(file: URL); func load() throws -> [RemoteLinkRecord]; func save(_: [RemoteLinkRecord]) throws }` at `stateRoot/links.json`.

- [ ] **Step 1: Write the failing tests** (fake launcher records `(args, env)`; fake core; manual clock)

```swift
@Test func staleDaemonIsStoppedBeforeStart() async {                        // Review Focus 5
  await sup.start(route: "relay+wss://relay.test/v2/relay", slot: "S1")
  #expect(launcher.calls.prefix(2).map { Array($0.args.prefix(2)) } == [["server", "stop"], ["server", "start"]])
}
@Test func daemonArgumentsUseBundlePaths() async {                         // Review Focus 1
  let start = launcher.calls.first { $0.args.starts(with: ["server", "start"]) }!
  #expect(start.args == RemoteCommandLine.serverStart(paths: paths, route: route, slot: "S1", ticketFile: paths.coreStateDir.appending(path: "tickets/register.ticket")))
  #expect(start.env["CMUX_SHELLX_BRIDGE_SOCKET"] == paths.bridgeSocket.path)
}
@Test func daemonCrashRestartsWithBackoff() async { /* exit(1) → state reconnecting(1, t0+1); clock → t0+1 → second launch; exit → retryAt +2 */ }
@Test func everyRespawnMintsAFreshTicket() async {                          // Review Focus 2
  /* 3 crashes → core received tickets.mint(register) 4 times, each before the matching launch */ }
@Test func clientConnectsOnSnapshotLineAndDropsInviteFile() async {}
@Test func clientGoesOfflineWithoutRetrying() async { /* machineAvailability(online: false) → .offline, no launches for 120 s of fake time */ }
@Test func refresherUsesHalfLife() async { /* fake core returns expires now+2 → second mint at +1 s */ }
```

Package tests: `ownerOnlyWriteIs0600AndAtomic`, `refusesSymlinkTarget`, `refusesGroupReadableFile`, `linkStoreRoundTrip`.

- [ ] **Step 2: Run** `swift test --package-path Packages/Shared/ShellXBrand` and `scripts/shellx/test-app.sh ShellXSupervisorTests` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** both — Expected: PASS.
- [ ] **Step 5: Security review** — checklist: `OwnerOnlyFile` rules, invite file deleted on success and on every failure path, env scrubbing (no inherited `CMUX_*` except the bridge var), argv never contains a ticket or invite value (only file paths), processes never run via a shell, `serverStop` before start. Fix findings.
- [ ] **Step 6: Commit** `git commit -m "feat(shellx): daemon and client link supervisors with ticket refresh and backoff"`

### Task 13: `ShellXRemoteService` (K4), gate, upstream mirroring kept off, app wiring

Merge `shellx/sprint` (after checkpoint 1: L1's W1 Tasks 3 and 5 touch the same gate files) into `shellx/l5-remote` before Step 3.

**Files:**
- Create: `Sources/ShellX/Remote/ShellXRemoteService.swift`, `Sources/ShellX/Remote/ShellXRemoteGate.swift`
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXFeatures.swift` (+ `public static let upstreamDeviceMirroring = false`), `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXBrand.swift` (+ `public static let apiBaseURL = URL(string: "https://relay.shellx.pro")!`), `Sources/Devices/DevicesFeature.swift`, `Sources/Mobile/MobileHostService.swift`, `Sources/Cloud/PresenceSettings.swift` (each W1-Task-5 read of `ShellXFeatures.remoteMachines` becomes `ShellXFeatures.upstreamDeviceMirroring // ShellX: ShellX remote uses its own transport (W2 plan Task 13)`), `Sources/AppDelegate.swift` (after `BrowserAvailabilityMonitor.shared.activate()` ≈ `:1691`: `ShellXRemoteService.shared.startIfEnabled() // ShellX:`; in `applicationWillTerminate` ≈ `:2568`: `ShellXRemoteService.shared.stopForTermination() // ShellX:` — synchronous, ≤ 2 s)
- Test: `cmuxTests/ShellXRemoteServiceTests.swift`, `Packages/Shared/ShellXBrand/Tests/ShellXBrandTests/ShellXBrandTests.swift` (+1 expectation)

**Interfaces:**
- Consumes: everything above.
- Produces (K4 verbatim, plus additive members):

```swift
@MainActor final class ShellXRemoteService: ObservableObject {
  static let shared: ShellXRemoteService
  @Published private(set) var machines: [RemoteMachine]                 // K4 (excludes isThisMachine)
  @Published private(set) var pendingApprovals: [PairingRequest]        // K4
  @Published private(set) var outgoing: [OutgoingPairing]               // additive (Part B U2)
  @Published private(set) var hostState: LinkState                      // additive (this Mac serving)
  @Published private(set) var isSignedIn: Bool                          // additive (Part B U1)
  @Published private(set) var remoteWorkspaces: [UUID: RemoteMachine.ID] // additive (Part B U1/U4)
  func requestAccess(to: RemoteMachine.ID) async throws -> String        // K4: returns the 6-digit code
  func approve(_ id: PairingRequest.ID) async throws                      // K4
  func deny(_ id: PairingRequest.ID) async                                // K4
  func openSession(on: RemoteMachine.ID) async throws                     // K4
  func signIn(email: String, password: String) async throws              // additive
  func signOut() async                                                    // additive
  func startIfEnabled(); func stopForTermination()                        // app lifecycle
}
enum ShellXRemoteGate { static var isEnabled: Bool }   // ShellXFeatures.remoteMachines || (DEBUG && env SHELLX_REMOTE_MACHINES == "1")
```

Behaviour: all core calls and process work run off the main actor (`Task.detached` / the supervisors' actors); `@Published` updates hop to main. `startIfEnabled`: gate off → return (no process, no core call). Gate on: `config.set {api_base: ShellXBrand.apiBaseURL (DEBUG: SHELLX_API_BASE override), state_dir: paths.coreStateDir, app_version, os_version, platform: "macos", device_name}`; if signed in: `machines.register` (name = `LocalMachineInfo.current().name` + `" (DEV <tag>)"` when the bundle id contains `.debug.`), relay route via `RelayRoute.cmuxRoute` from the first `tickets.mint` response, start bridge server (Task 11) then daemon supervisor (Task 12); timers: heartbeat 30 s, `machines.list` 15 s (feeds `machineAvailability` of client links), `pair.pending` 5 s. `requestAccess` → `pair.request` → append `OutgoingPairing(.waiting)` → poll `pair.poll` every 2 s (`write_invite_to: "invite-<hash8>.uri"`) until a terminal status or 300 s → on approved: save `RemoteLinkRecord`, start the client supervisor with the invite file. `approve` → refuse when `suspicious` (throw `ShellXCoreError(code: "fingerprint_mismatch")`) → `tickets.mint {connect, target_machine_id: self, write_to: "invite-connect.ticket"}` (D3) → `run(enrollCreate)` → `InviteURI.summary` → `pair.approve {pairing_id, invite_uri}` → `gate.expect(invitationID:pairingID:)` → poll `run(enrollPending)` every 1 s while the gate holds expectations: `.approve` → `run(enrollApprove)`, `.deny` → `run(enrollDeny)`. `openSession(on:)` → start/await the client link `.connected` (≤ 20 s, else throw `ShellXCoreError(code: "offline")`) → `cmux-tui --socket <clientSocket> terminal list --json`; none → `workspace create --name "ShellX" --json` then list again → first terminal id → `TabManager.addWorkspace(title: "<machine name>", initialTerminalCommand: RemoteCommandLine.attachShellCommand(…))` → `remoteWorkspaces[ws.id] = machine`. `stopForTermination` → stop client links, daemon (`serverStop`), bridge, timers.

- [ ] **Step 1: Write the failing tests** (service built with injected fake core, fake launcher, manual clock, temp `RemotePaths`)

```swift
@Test func gateOffStartsNothing() { /* gate false → startIfEnabled → launcher.calls.isEmpty && core.calls.isEmpty */ }
@Test func upstreamMirroringStaysOffWhenRemoteMachinesOn() {
  #expect(ShellXFeatures.upstreamDeviceMirroring == false)
  #expect(DevicesFeature.isAvailable == false); #expect(PresenceSettings.isEnabled == false)   // real accessors per W1 Task 5
}
@Test func approveCreatesInvitationSealsAndExpectsIt() async throws {
  launcher.stub(["remote", "enroll", "create"], stdout: fixtureInviteURI(id: "inv1"))
  try await svc.approve("p1")
  #expect(core.calls.last == .init("pair.approve", ["pairing_id": "p1", "invite_uri": fixtureInviteURI(id: "inv1")]))
  launcher.stub(["remote", "enroll", "pending"], stdout: #"[{"invitation_id":"inv1"}]"#); await clock.advance(1)
  #expect(launcher.ran(RemoteCommandLine.enrollApprove(paths: paths, invitationID: "inv1")))
}
@Test func unknownPendingEnrollmentIsDenied() async {                       // Review Focus 3
  launcher.stub(["remote", "enroll", "pending"], stdout: #"[{"invitation_id":"evil"}]"#); /* after one approve cycle */
  #expect(launcher.ran(RemoteCommandLine.enrollDeny(paths: paths, invitationID: "evil")))
}
@Test func suspiciousRequestIsRefusedBeforeAnyProcess() async { /* pendingApprovals[0].suspicious → approve throws fingerprint_mismatch; no enroll create ran */ }
@Test func requestAccessReturnsCodeAndTracksOutgoing() async throws { /* returns "123456"; outgoing[0].status == .waiting; poll approved → .approved and a client launch with --invite-file */ }
@Test func coreCallsNeverRunOnMainThread() async { /* fake core records Thread.isMainThread == false for every call */ }   // Review Focus 2
@Test func terminateStopsDaemonAndHeartbeat() { /* stopForTermination → serverStop ran; no heartbeat after */ }   // Review Focus 5
```

- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXRemoteServiceTests` and `swift test --package-path Packages/Shared/ShellXBrand` — Expected: FAIL.
- [ ] **Step 3: Implement** and wire.
- [ ] **Step 4: Run** both, plus `python3 tests/test_shellx_remote.py` and `python3 scripts/verify-local.py --all` — Expected: PASS. Build the dev tag (lock), launch with `SHELLX_REMOTE_MACHINES=1 SHELLX_API_BASE=http://127.0.0.1:<fake port>` against `shellx-fake-api` + a local `cmux-relay`, sign in (temporary, DEBUG only: `startIfEnabled` calls `signIn` when `SHELLX_DEV_EMAIL`/`SHELLX_DEV_PASSWORD` are set — fake-API accounts only; Part B U1 is the real UI) → `hostState == .connected`. Also add `extension ShellXCoreFFI: ShellXCoreCalling {}` here and remove the Task 11 DEBUG bridge start from `AppDelegate`.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx): ShellXRemoteService (K4) — host daemon, pairing with on-site approval, remote sessions; upstream mirroring stays off"`

### Task 14: Mac↔Mac acceptance, checkpoint 2

**Files:** none new (fixes go to the owning task's files). Lane report to L0 (L0 writes the ledger).

- [ ] **Step 1: Preconditions.** G2 done (relay2 + API v2 live, `curl -s https://relay.shellx.pro/v1/version` → 200) and D2/D3 deployed; else run Steps 3–5 against `shellx-fake-api` + local `cmux-relay` (`SHELLX_API_BASE`, DEBUG) and say so in the report.
- [ ] **Step 2: Builds.** Dev tag `l5` (Task 9 recipe) and, at checkpoint 2, L0's integration Release build from `shellx/sprint` with `remoteMachines` flipped. Before L0's build exists: host = dev app, viewer = the e2e harness CLI (`shellx-core-cli` + stock `cmux-tui remote connect`) against the same API.
- [ ] **Step 3: Two builds, distinct paths (Review Focus 1).** Both apps running: `ps -o args= -p $(pgrep -f "cmux-tui server start")` shows two `--session shellx-<hash8>` values; `ls -ld $TMPDIR/sx-*` → two dirs `drwx------`; `ls -l ~/Library/Application\ Support/ShellX/remote/` → two bundle-id dirs; both machines listed on both apps.
- [ ] **Step 4: Pair, approve, view, type.** From the dev app request access to the Release app; codes and fingerprints match on both screens (photo for the report); approve on the Release app; open the session; in the viewer pane type `tieengs Vieetj` with macOS Vietnamese Telex and with EVKey → the host pane shows `tiếng Việt` (Review Focus 4); `vim` arrows and Ctrl-C work; remote split (`tab create terminal` from the viewer CLI or the pane's split) opens a new tab on the host (D7).
- [ ] **Step 5: Outages (Review Focus 2, 5).** Host Wi-Fi off 30 s → viewer sidebar `reconnecting…`, viewer UI stays responsive (drag the sidebar while waiting), back within 35 s after Wi-Fi on. Quit the host app → viewer shows `offline · last seen HH:MM` within 90 s; relaunch → viewer reconnects without a new pairing. Force-quit the host (`kill -9`), relaunch → `pgrep -fc "cmux-tui server start --session shellx-<hash8>"` → `1`.
- [ ] **Step 6: Spoofing (Review Focus 3).** Two requests at once from the two apps to a third session (or via harness CLI): the prompt shows two different codes; approving one never lets the other in (`remote enroll pending` on the host empties only for the approved invitation).
- [ ] **Step 7: Network audit.** `python3 scripts/shellx/audit_network.py --app "<ShellX DEV l5.app>" --seconds 120 --out /tmp/l5-audit.json` (W1 Task 13) with `SHELLX_REMOTE_MACHINES=1`: the only non-loopback endpoint is `relay.shellx.pro` (record in the report; the script's loopback-only rule needs an allowlist flag for this run — add `--allow-host relay.shellx.pro` if W1 did not).
- [ ] **Step 8: Report** "ready <sha>" with: CI run ids (`shellx-remote`, `shellx-mac`), Steps 3–7 results, known limitations (D7: `\n`→`\r`, focused-terminal projection, invites sealed to the device key), open questions still open.

---

# Part B — Mac remote UI (lane L3, after W1 Task 10)

Prerequisites: W1 Task 10 merged on `shellx/l3-sidebar`; L5 Task 10 merged into `shellx/sprint` (merge sprint into `shellx/l3-sidebar` when L5 posts "ready (package)"). Until L5 Task 13 lands, views read a `RemoteUISnapshot` built from fixtures; after it lands, `RemoteUISnapshot(service:)` reads `ShellXRemoteService.shared`. All views: palette §7.4 tokens from `ShellXPalette`, flat fills, 1 px borders, coolicons via `ShellXIcon`, labels truncate with `.byTruncatingTail`, fixed row/header heights (W1 RF5). Primary button = `primarySoft` fill + `primaryLine` border + `primaryText`; secondary = `raise` + `border` + `text`.

Strings (add to the catalog with Vietnamese):

| Key | English | Tiếng Việt |
| --- | --- | --- |
| `remote.signin.row` | Sign in to see your other machines | Đăng nhập để thấy các máy khác |
| `remote.signin.title` | Sign in to ShellX | Đăng nhập ShellX |
| `remote.signin.error.credentials` | Email or password is incorrect | Email hoặc mật khẩu không đúng |
| `remote.signin.error.network` | Can't reach relay.shellx.pro | Không kết nối được relay.shellx.pro |
| `remote.machine.offline` | offline · last seen %@ | ngoại tuyến · lần cuối %@ |
| `remote.machine.requestAccess` | Request access | Xin quyền |
| `remote.machine.waiting` | waiting · %@ | đang chờ · %@ |
| `remote.machine.reconnecting` | reconnecting… | đang kết nối lại… |
| `remote.machine.connecting` | connecting… | đang kết nối… |
| `remote.request.title` | Request access to %@ | Xin quyền vào %@ |
| `remote.request.instructions` | On %@, approve only if the code and fingerprint match this screen. | Trên %@, chỉ chấp thuận nếu mã và vân tay khớp với màn hình này. |
| `remote.request.code` | Code | Mã |
| `remote.request.fingerprint` | This Mac's fingerprint | Vân tay của máy này |
| `remote.request.approved` | Approved | Đã được chấp thuận |
| `remote.request.denied` | Denied | Bị từ chối |
| `remote.request.expired` | Expired | Đã hết hạn |
| `remote.request.retry` | Try again | Thử lại |
| `remote.approve.title` | %@ wants to view and control this Mac | %@ muốn xem và điều khiển máy này |
| `remote.approve.compare` | Approve only if the code and fingerprint match the other screen. | Chỉ chấp thuận nếu mã và vân tay khớp với màn hình máy kia. |
| `remote.approve.suspicious` | The fingerprint does not match what the server reports. Do not approve. | Vân tay không khớp với thông tin máy chủ. Đừng chấp thuận. |
| `remote.approve.approve` | Approve | Chấp thuận |
| `remote.approve.deny` | Deny | Từ chối |
| `remote.approve.queue` | %lld of %lld | %lld / %lld |
| `remote.banner.reconnecting` | Reconnecting to %@… | Đang kết nối lại tới %@… |
| `remote.banner.offline` | %@ is offline. The session resumes when ShellX opens there. | %@ đang ngoại tuyến. Phiên tiếp tục khi ShellX được mở trên máy đó. |
| `remote.banner.failed` | Can't connect to %@ (%@) | Không kết nối được tới %@ (%@) |
| `common.cancel` | Cancel | Huỷ |

### Task U1: Remote machine groups and sign-in in the sidebar

**Files:**
- Modify: `Sources/ShellX/Sidebar/SidebarMachineGrouping.swift`, `Sources/ShellX/Sidebar/SidebarMachineHeaderCellView.swift`, `Sources/ShellX/Sidebar/SidebarBrandHeaderView.swift` (W1 Task 10 files)
- Create: `Sources/ShellX/Remote/UI/RemoteUISnapshot.swift`, `Sources/ShellX/Remote/UI/SignInSheet.swift`
- Test: `cmuxTests/SidebarMachineGroupingTests.swift` (extend), `cmuxTests/ShellXRemoteUITests.swift`

**Interfaces:**
- Consumes: `RemoteMachine`, `LinkState` (L5 Task 10); `ShellXRemoteService` `machines`, `isSignedIn`, `remoteWorkspaces`, `requestAccess`, `openSession`, `signIn` (L5 Task 13).
- Produces: `SidebarMachineKey` gains `case remote(machineID: String)`; `SidebarMachineInput` gains `let remoteMachineID: String?` (default `nil`); `SidebarMachineGrouping.sections(for:local:remote: [RemoteMachine], now: Date)` (W1's `sections(for:local:)` stays as a wrapper passing `remote: []`, so W1 tests keep passing); `SidebarMachineHeaderModel` gains `let isDimmed: Bool` and `let action: SidebarMachineHeaderAction?` with `enum SidebarMachineHeaderAction: Equatable { case requestAccess, waiting(code: String), open, reconnecting, connecting }`; `struct RemoteUISnapshot { machines: [RemoteMachine]; isSignedIn: Bool; remoteWorkspaces: [UUID: String]; pendingApprovals: [PairingRequest]; outgoing: [OutgoingPairing] }`.
- Rules: order = local, then remote machines (online first, then offline; each by `name` localized-standard), then SSH (W1 order). `isThisMachine` is never a remote section. Remote header: coolicon `Laptop` (macos) / `Desktop` (windows); online → note `""`, dot `done`; offline → note `remote.machine.offline` with `lastSeen` as `HH:mm` (24 h, local time; `—` when nil), `isDimmed = true` (alpha 0.5), **no rows** (U14) even if workspaces are tagged; action: `access == .none` → `.requestAccess`; `.requested(_, code)` → `.waiting(code: PairingDisplay.code(code))`; granted + `.idle`/`.connected` → `.open`; `.connecting` → `.connecting`; `.reconnecting` → `.reconnecting`. Rows: workspaces whose id is in `remoteWorkspaces` go under that machine. Signed out (gate on) → one row `remote.signin.row` under "YOUR MACHINES" opening `SignInSheet` (email field, secure field, primary "Sign in", inline error from `ShellXCoreError.code`: `invalid_credentials` → `remote.signin.error.credentials`, `network` → `remote.signin.error.network`, else the code).

- [ ] **Step 1: Write the failing tests**

```swift
let mac = LocalMachineInfo(name: "MacBook Pro", isLaptop: true)
func rm(_ id: String, _ name: String, online: Bool, access: RemoteMachine.Access = .granted, link: LinkState = .idle, last: Date? = nil) -> RemoteMachine { … }
@Test func remoteMachinesSitBetweenLocalAndSSH() {
  let s = SidebarMachineGrouping.sections(for: [.init(workspaceID: 1, sshTarget: "u@vm", sshConnected: true, remoteMachineID: nil)], local: mac, remote: [rm("m1", "Mac mini", online: true)], now: t0)
  #expect(s.map(\.header.key) == [.local, .remote(machineID: "m1"), .ssh(target: "u@vm")])
}
@Test func onlineBeforeOfflineThenByName() {}
@Test func offlineRemoteIsDimmedWithLastSeenAndNoRows() {
  let s = SidebarMachineGrouping.sections(for: [.init(workspaceID: 9, sshTarget: nil, sshConnected: false, remoteMachineID: "m1")], local: mac,
    remote: [rm("m1", "Mac mini", online: false, last: date("14:05"))], now: t0)
  #expect(s[1].header.isDimmed && s[1].header.note == "offline · last seen 14:05" && s[1].workspaceIDs.isEmpty)
}
@Test func thisMachineIsNeverARemoteSection() {}
@Test func headerActionFollowsAccessAndLink() { /* .none → .requestAccess; .requested(code "123456") → .waiting("123 456"); granted+.reconnecting → .reconnecting */ }
@Test func remoteWorkspaceRowsGroupUnderTheirMachine() {}
@Test func longRemoteNameKeepsHeaderHeight() { /* W1 RF5 calculator, 6× "Máy tính văn phòng tầng 3 " */ }
@Test func signInErrorMapping() { /* invalid_credentials / network / other */ }
```

- [ ] **Step 2: Run** `scripts/shellx/test-app.sh SidebarMachineGroupingTests ShellXRemoteUITests` — Expected: FAIL.
- [ ] **Step 3: Implement**; header action button: `.requestAccess` → small primary button calling `requestAccess` then presenting U2's sheet; `.open` → clicking the header calls `openSession`; trailing dot colors per palette.
- [ ] **Step 4: Run** the tests — Expected: PASS. Dev build with fixtures (DEBUG env `SHELLX_REMOTE_UI_FIXTURES=1` injects a snapshot with one online, one offline, one requested machine): compare with the mockup's machine groups.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx): remote machine groups and sign-in in the sidebar"`

### Task U2: Request-access sheet (code + fingerprint)

**Files:**
- Create: `Sources/ShellX/Remote/UI/RequestAccessSheet.swift`, `Sources/ShellX/Remote/UI/RequestAccessModel.swift`
- Test: `cmuxTests/ShellXRemoteUITests.swift`

**Interfaces:**
- Consumes: `OutgoingPairing`, `PairingDisplay` (L5 Task 10); `ShellXRemoteService.outgoing`, `requestAccess(to:)`.
- Produces: `struct RequestAccessModel: Equatable { init(pairing: OutgoingPairing, machineName: String); let title: String; let codeText: String /* "123 456" */; let fingerprintText: String /* "a1b2 c3d4 e5f6 0718" */; let statusText: String?; let showsSpinner: Bool; let primaryAction: Action?; let closesAutomatically: Bool }` with `enum Action { case retry }`.
- Layout: `raise` panel, title (`remote.request.title`), code in 28 pt monospaced `textHi`, label `remote.request.code`; fingerprint 13 pt monospaced `muted` with label `remote.request.fingerprint`; instructions `remote.request.instructions`; footer secondary `common.cancel` (dismiss; the pairing expires server-side). `.waiting` → spinner; `.approved` → `remote.request.approved` in `done`, auto-close after 1 s and `openSession`; `.denied` → `error` text; `.expired`/`.failed` → text + primary `remote.request.retry` (calls `requestAccess` again).

- [ ] **Step 1: Write the failing tests** — `waitingShowsCodeFingerprintAndSpinner` (codeText `"123 456"`, fingerprintText `"a1b2 c3d4 e5f6 0718"`, showsSpinner, no action); `approvedClosesAutomatically`; `deniedShowsErrorWithoutRetry`; `expiredOffersRetry`; `vietnameseTitleTruncatesNotWraps` (model title for a 120-char name equals the full name; the view applies `.lineLimit(1)` — snapshot the view's `lineLimit` via the model's `titleLineLimit == 1`).
- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXRemoteUITests` — Expected: FAIL.
- [ ] **Step 3: Implement**; present as a sheet on the key window from U1's header action.
- [ ] **Step 4: Run** — Expected: PASS; check by eye with fixtures.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx): request-access sheet with code and fingerprint"`

### Task U3: On-site approval prompt on the target Mac

**Files:**
- Create: `Sources/ShellX/Remote/UI/ApprovalPromptPanel.swift`, `Sources/ShellX/Remote/UI/ApprovalPromptModel.swift`
- Modify: the notifications feed entry point used by the title-bar bell (W1 Task 11) — add one "approval needed" item per pending request
- Test: `cmuxTests/ShellXRemoteUITests.swift`

**Interfaces:**
- Consumes: `PairingRequest` (L5 Task 10); `ShellXRemoteService.pendingApprovals`, `approve(_:)`, `deny(_:)`.
- Produces: `struct ApprovalPromptModel: Equatable { init(queue: [PairingRequest], now: Date); let current: PairingRequest?; let title: String; let codeText: String; let fingerprintText: String; let warning: String?; let canApprove: Bool; let queueText: String? /* "1 / 2" */ }`; `final class ApprovalPromptPanel: NSPanel` (floating, titled, not closable by Esc while a request is shown; becomes key so the buttons take clicks).
- Rules: `current` = oldest non-expired request; requests with `now ≥ expiresAt` are dropped (the panel closes when the queue empties); `suspicious` → `warning = remote.approve.suspicious` in `error`, `canApprove = false`; buttons: primary `remote.approve.approve` (disabled when `!canApprove`), secondary `remote.approve.deny`; approve/deny errors shown inline (`fingerprint_mismatch` → the suspicious text). Never auto-approve; no default button (Return does nothing) so a stray keypress cannot approve.

- [ ] **Step 1: Write the failing tests** — `showsOldestRequestWithCodeAndFingerprint`; `suspiciousRequestCannotBeApproved` (Review Focus 3: `canApprove == false`, warning present); `expiredRequestsAreDropped` (`firstSeen + 301 s` → `current == nil`); `queueTextCountsPending` (`"1 / 2"`); `returnKeyHasNoDefaultAction` (panel `defaultButtonCell == nil`).
- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXRemoteUITests` — Expected: FAIL.
- [ ] **Step 3: Implement**; the service's `pendingApprovals` change shows/updates the panel; add the bell item.
- [ ] **Step 4: Run** — Expected: PASS; check by eye with a fixture request and a suspicious one.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx): on-site approval prompt comparing code and fingerprint"`

### Task U4: Offline and reconnecting states for remote sessions

**Files:**
- Create: `Sources/ShellX/Remote/UI/RemoteLinkBanner.swift`, `Sources/ShellX/Remote/UI/RemoteLinkBannerModel.swift`
- Modify: the workspace content container that hosts the presence strip (spec §7.1 "dải hiện diện"; find it next to the session bar view) — show the banner for workspaces in `remoteWorkspaces`
- Test: `cmuxTests/ShellXRemoteUITests.swift`

**Interfaces:**
- Consumes: `LinkState`, `RemoteMachine`; `ShellXRemoteService.remoteWorkspaces`, `machines`. The pane itself already prints `[ShellX] đang kết nối lại… / reconnecting…` from the attach wrapper (L5 Task 10, D8).
- Produces: `struct RemoteLinkBannerModel: Equatable { init(machine: RemoteMachine, now: Date); let text: String?; let tone: Tone; let showsSpinner: Bool }`, `enum Tone { case muted, error }`.
- Rules: `.connected`/`.idle` → `text == nil` (no banner); `.connecting`/`.reconnecting` → `remote.banner.reconnecting`, `muted`, spinner, plus "· retry in Ns" from `retryAt` (`max(0, ceil)`); `.offline` → `remote.banner.offline`, `muted`; `.failed(code)` → `remote.banner.failed` with the code, `error`. Banner height fixed 28 pt, flat `raise` fill, 1 px `line` bottom border; never covers the terminal (it pushes the pane down) and never blocks input.

- [ ] **Step 1: Write the failing tests** — `connectedShowsNoBanner`; `reconnectingShowsCountdown` (`retryAt = now + 3.2` → text ends with `"retry in 4s"`); `offlineExplainsResume`; `failedShowsCodeInErrorTone`; `bannerHeightIsFixed`.
- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXRemoteUITests` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — Expected: PASS. With L5's dev build: open a remote session, turn the host's Wi-Fi off → banner shows reconnecting with countdown and the pane prints the wrapper message; Wi-Fi on → banner disappears.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx): offline and reconnecting banner for remote sessions"`. Report "ready <sha>" to L0.

---

## Open questions and risks (unverified when this plan was written)

1. **D2 / D3 conflict with the L4 plan as written** (its target `GET` omits `requester_x25519_b64`; its ticket mint refuses `connect` to one's own machine with 400). Without D2 no pairing can be approved; without D3 Task 8 Step 6's placeholder path must pass. L0 must rule at T+0 and tell L4.
2. **`requester_fingerprint`**: the L4 plan copies the requester **machine's** noise-key fingerprint (`sha256(key).hex[0:16]`). D1 makes that key the same as `requester_x25519`, so local and server fingerprints match. This breaks if any client registers a different key than it pairs with (L6 must follow D1). L4 also revokes grants when a machine re-registers with a new key, so wiping `state_dir` means pairing again.
3. **`--remote-state-dir` durability with `--ephemeral`**: assumed enrolled devices persist across daemon restarts (Task 8 `test_enrolled_device_reconnects_after_daemon_restart` decides). If not, every host relaunch forces re-pairing.
4. **`server start` has no `--exit-with-parent`**: an app crash leaves an orphan daemon until next launch (mitigated by `serverStop` first). The orphan keeps the slot registered while heartbeats stop.
5. **Disk (7.6 GB free)**: cmux-tui-core tests run only on CI; the local cmux-tui release build plus two app builds may not fit — G0 must free ≥ 30 GB (master gate).
6. **Static link of `shellx-core` into the app**: native libs list (Security/CoreFoundation for the platform verifier) and Rust std alongside the nucleo cdylib are assumed fine; Task 9 Step 4 verifies.
7. **Sprint limitations** (D7): remote `\n` arrives as `\r` (raw PTY-write export in the ghostty fork is post-sprint); viewers see the host's focused terminal plus remote-created tabs, not the full session list; attach snapshot turns palette colors into fixed RGB.
8. **Windows ACLs** for `shellx-core`'s state dir are not hardened in the sprint (Task 2 note); L6 stores the token there.
9. **`requester_x25519` is the long-lived device key** (D1): invites have no forward secrecy; acceptable because single-use and ≤ 300 s, revisit with Keychain storage.
10. **Upstream gate files** (`DevicesFeature`, `MobileHostService`, `PresenceSettings`) are edited by both L1 (W1 Task 5) and L5 (Task 13): Task 13 waits for checkpoint 1 to avoid a conflict.
