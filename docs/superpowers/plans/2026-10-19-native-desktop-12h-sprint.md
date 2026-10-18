# ShellX native desktop — 12-hour sprint (master plan)

> **For agentic workers:** this is the orchestration plan. It does not hold code steps itself: each lane runs a wave plan task by task with superpowers:subagent-driven-development (lanes in parallel, one worktree each). Read this file first, then your lane's plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Tóm tắt (cho người dùng):** 12 giờ đồng hồ, 7 lane chạy song song, build trên GitHub Actions (fork công khai → miễn phí) thay vì máy Mac. Kết quả sau 12h: **ShellX Mac dùng hằng ngày** (đợt 1 xong), **Mac xem và điều khiển Mac khác qua relay v2** có ghép cặp và chấp thuận tại chỗ (lõi đợt 2), **ShellX Windows bản MVP** (terminal, tab, chia khung, sidebar, tiếng Việt, đăng nhập, xem máy Mac từ xa, bộ cài chưa ký). **Không nằm trong 12h:** Windows làm máy chủ phiên (port daemon + rà soát bảo mật ACL), phát hành công khai 2.0.0, link chia sẻ trên trình duyệt (lane L7 chỉ làm nếu dư sức). Bạn cần có mặt ở 4 cổng (G0–G3), mỗi cổng 5–20 phút.

**Goal:** In 12 wall-clock hours, take the W0 results to: ShellX for Mac usable daily (Wave 1 done), Mac↔Mac remote sessions over a self-hosted relay v2 with on-site approval (Wave 2 core), and a Windows MVP that runs a local terminal and views a Mac remotely (Wave 4 subset), all pushed, built by CI, and recorded in the ledger.

**Architecture:** Seven lanes in separate git worktrees, joined by contracts frozen in this file (§Contracts) so no lane waits on another's code. Compile and test on GitHub Actions (`lephus/shellx` is public: macOS and Windows runners are free); the dev Mac only does fast package-level tests and two integration builds (T+6, T+10). Integration branch `shellx/sprint` in the fork, `feat/relay-v2` in the shellx repo; `main` in both is updated only at the T+12 close.

**Tech Stack:** fork = Swift 6 / SwiftUI + AppKit (Xcode 26.2), Rust (cmux-tui workspace, GPUI 0.2.2 on Windows), Zig 0.16.0 for libghostty; shellx repo = Node 22 + Hono + better-sqlite3 (relay/API), Astro (web), Docker on the VPS behind `nginx-proxy`.

**Repo move (2026-10-19, T+0:25):** the cmux fork now lives on `main` of `lephus/shellx` (ledger "Repo move"). Everywhere below, "fork" and "shellx repo" are the same repository; fork branches `shellx/<lane>` are branches of `lephus/shellx`. Pushing any branch except `main` is allowed; `main` pushes of `relay/`, `web/`, `deploy/` deploy production.

**Spec:** `docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md` (D-W0-1 amendments of 2026-10-19 included). Ledger: `docs/superpowers/ledgers/native-desktop.md` (binding for spike facts: ticket format, PSK out of band, bridge hook points, Windows CI).

**Lane plans:**

| Lane | Plan | Repo / branch |
| --- | --- | --- |
| L0 lead | this file | both |
| L1 Mac identity | `2026-10-18-native-desktop-w1-mac-local.md` Tasks 1–5, 5B | fork `shellx/l1-identity` |
| L2 Mac look | W1 plan Tasks 6, 7, 8, 9 (verify only), 11, 12 | fork `shellx/l2-look` |
| L3 Mac sidebar | W1 plan Task 10, then W2 plan "Mac remote UI" tasks | fork `shellx/l3-sidebar` |
| L4 server | `2026-10-19-native-desktop-w2-server.md` | shellx `feat/relay-v2` |
| L5 Mac remote core | `2026-10-19-native-desktop-w2-mac-remote.md` (shellx-core + bridge) | fork `shellx/l5-remote` |
| L6 Windows | `2026-10-19-native-desktop-w4-windows-mvp.md` | fork `shellx/l6-windows` |
| L7 share (stretch) | `2026-10-19-native-desktop-w3-release-share.md` Part B | shellx `feat/share-viewer` |
| after 12h | `2026-10-19-native-desktop-w3-release-share.md` Part A (public release) | both |

## Global Constraints

- Every rule in the spec §4 (anti-goals) and §5 (constraints) holds; the ones that bite in a sprint: no Manaflow servers, no third-party services or telemetry, no BUSL code (`web/`, `workers/*`, `services/iroh-relay-minter/`, `cmux-tui/relays/cloudflare-do/` in the fork), GPL-compatible deps only.
- Bundle id `pro.shellx.desktop`, team `W4RF3W4VTZ`, CLI name `shellx`, version `2.0.0`, macOS 14+.
- Palette §7.4 only, no gradients on UI elements, primary `#60a5fa`, running state = yellow.
- Relay sees only ciphertext; a device needs on-site approval by the target machine; the invitation PSK never reaches the ShellX server in clear (ledger "Spec implication (§8.5)").
- Never push `main` of the shellx repo with non-doc changes during the sprint (it releases the Flutter app, ~300 billed minutes). Fork pushes are free; push lane branches as often as CI needs.
- Never ask for secret values in chat; the user sets them by hand (`! ` commands or the VPS shell).
- Keep upstream files' edits to wiring; ShellX code lives in `Packages/Shared/ShellXBrand`, `Sources/ShellX/`, `shellx-core/`, `windows/` (fork) so `upstream` merges stay small.

## Review Focus

1. **Two ShellX builds on one Mac** (Release `pro.shellx.desktop` and a tagged dev build) — testers will run both for Mac↔Mac; each must use its own socket, daemon state dir and relay slot. Owner: L5 Task "daemon lifecycle" test that two instances get distinct paths.
2. **Relay or API down / ticket expired mid-session** — the sidebar must show the machine offline and reconnect with backoff, never hang the UI. Owner: L5 reconnect test with a 2 s ticket lifetime.
3. **Approval spoofing** — a request whose fingerprint or 6-digit code does not match what the target shows must be refused. Owner: L4 pairing API test + L5 approval test.
4. **Vietnamese input over remote** — Telex composition typed on Windows or Mac into a remote Mac terminal arrives as composed UTF-8, never as raw keystrokes. Owner: L6 remote input test and L5 bridge input test (`tiếng Việt` round trip).
5. **Flutter app still installed** — the native build exits while `/Applications/ShellX.app` (Flutter, same bundle id) runs; the first-run path must say so instead of silently quitting. Owner: L1 Task 3 (coexistence) test.

---

## Contracts (frozen at T+0; change only through L0 with a ledger note)

### K1 ShellX API v2 (shellx repo `relay/`, base `https://relay.shellx.pro`)

Auth = the existing v1 bearer token (`relay/src/auth/session.ts`, `requireAuth`); desktop devices log in with the v1 `/v1/auth` flow and `kind = "desktop"` (add the kind if missing). All bodies JSON, errors via `relay/src/http/errors.ts`.

| Method + path | Body | 2xx response |
| --- | --- | --- |
| `POST /v2/machines` | `{name, platform: "macos"\|"windows", os_version, app_version, noise_public_key_b64}` | `201 {machine_id, slot}` (`slot` = server-random 16 bytes b64url; one machine per device token) |
| `GET /v2/machines` | — | `{machines: [{machine_id, name, platform, online, last_seen_unix, fingerprint}]}` (account scope; `online` = heartbeat within 90 s; `fingerprint` = first 16 hex of SHA-256(noise public key)) |
| `POST /v2/machines/:id/heartbeat` | — | `204` (every 30 s while the app is open) |
| `DELETE /v2/machines/:id` | — | `204` (also deletes its grants) |
| `POST /v2/relay/tickets` | `{machine_id, permission: "register"\|"connect", target_machine_id?}` | `{ticket, expires_at_unix, relay_url}`; `register` only for the caller's own machine slot; `connect` only for a target with a granted pairing or the caller's own machine (D3); lifetime 120 s; format = ledger "Ticket format" (HMAC key env `CMUX_RELAY_HMAC_SECRET`, issuer `CMUX_RELAY_ISSUER=shellx-relay`) |
| `POST /v2/pairings` | `{from_machine_id, to_machine_id, requester_x25519_b64}` | `201 {pairing_id, code}` (`code` = 6 digits shown on both screens) |
| `GET /v2/pairings?role=target\|requester` | — | `{pairings: [{pairing_id, from_machine_id, to_machine_id, requester_fingerprint, requester_x25519_b64, code, status: "pending"\|"approved"\|"denied"\|"expired", sealed_invite_b64?}]}` (pending expire after 5 min; `requester_x25519_b64` on `role=target` items, D2) |
| `POST /v2/pairings/:id/approve` | `{sealed_invite_b64}` | `204` (target only; stores ciphertext, grants `connect`) |
| `POST /v2/pairings/:id/deny` | — | `204` |
| `GET /v1/version` | headers `X-ShellX-Version`, `X-ShellX-Platform` (`macos`/`windows`/`flutter-macos`/`flutter-windows`), `X-ShellX-OS-Version` | existing body + per-platform `min` (C15) |

Amendments 2026-10-19 (L0, ledger "Sprint rulings"): **D1** one X25519 device key per `state_dir` is the v1 login device key, `noise_public_key_b64` and `requester_x25519_b64` (L6 too); **D2**, **D3** as marked in the table.

Sealed invite = X25519 ECDH(target ephemeral, requester public) → HKDF-SHA256(info `"shellx-invite-v1"`) → ChaCha20-Poly1305; payload = the `cmux://enroll/…` URI. The server stores and returns ciphertext only.

### K2 Relay v2 (VPS)

Container `relay2` = `cmux-relay` built from fork `cmux-tui/crates/cmux-relay` by fork CI, image `ghcr.io/lephus/shellx-relay2:<sha>`, env `CMUX_RELAY_HMAC_SECRET` (≥ 32 bytes, set by hand in `~/phu/shellx/.env`), `CMUX_RELAY_ISSUER=shellx-relay`; served at `wss://relay.shellx.pro/v2/relay` through `nginx-proxy` (path route on the existing host, so no DNS change; if `nginx-proxy` cannot route a path, fall back to `relay2.shellx.pro` and add DNS at gate G2).

### K3 `shellx-core` (fork `shellx-core/`, own Cargo workspace, MIT-or-GPL-compatible deps, rustls only)

Rust API used by Windows directly; the Mac links a staticlib through one C entry point:

```c
// shellx-core/include/shellx_core.h
char *shellx_core_call(const char *method, const char *json_in); // returns JSON {"ok":…} or {"error":{"code","message"}}
void  shellx_core_free(char *ptr);
```

Methods: `config.set {api_base, state_dir}`, `auth.login {email, password}`, `auth.logout`, `machines.register {name, platform, os_version, app_version, noise_public_key_b64}`, `machines.list`, `machines.heartbeat`, `tickets.mint {permission, target_machine_id?}`, `pair.request {to_machine_id}` → `{pairing_id, code}`, `pair.pending` (target side), `pair.approve {pairing_id, invite_uri}` (seals and posts), `pair.deny {pairing_id}`, `pair.poll {pairing_id}` → `{status, invite_uri?}` (opens the sealed invite), `version.check`. Token and keys live in `state_dir` with owner-only permissions (Keychain on Mac is a later upgrade).

### K4 Mac remote seam (fork)

- Feature switch `ShellXFeatures.remoteMachines` (`Packages/Shared/ShellXBrand`, created by W1 Task 1/5) — L5/L3 flip it to `true` only on `shellx/sprint` after checkpoint 1.
- Daemon = the bundled `Contents/Resources/bin/cmux-tui` run as a sidecar (`server start --relay <relay_url> --relay-slot <slot> --relay-ticket-file <file> --ephemeral`), proven by the bridge spike (`shellx/w0-bridge` `4e1ed7bc41`). C-ABI embedding is after the sprint.
- Swift service `ShellXRemoteService` (`Sources/ShellX/Remote/`) exposes to the UI: `@Published machines: [RemoteMachine]`, `@Published pendingApprovals: [PairingRequest]`, `func requestAccess(to: RemoteMachine.ID) async throws -> String /* code */`, `func approve(_: PairingRequest.ID) async throws`, `func deny(_:) async`, `func openSession(on: RemoteMachine.ID) async throws`.

### K5 Windows app (fork `windows/`)

`windows/shellx-app` (GPUI 0.2.2, from `spikes/windows-term`), uses `shellx-core` (K3) as a Rust crate and the `cmux-tui` remote client crates for viewing a Mac. CI workflow `.github/workflows/shellx-windows.yml` uploads `ShellX-Setup-2.0.0-sprint.exe` (Inno Setup, unsigned).

---

## Clock

T+0 is when the user says "chạy". Durations are agent wall-clock; CI round-trips (~25–50 min for a cold macOS app build) are already counted.

| Time | L0 lead | L1 | L2 | L3 | L4 | L5 | L6 | L7 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| before | gate G0 | | | | | | | |
| 0:00–0:45 | W1 Task 1 on `shellx/sprint`, CI workflow | — | — | — | API v2 tests first | shellx-core skeleton + K3 tests | app skeleton from spike | — |
| 0:45–3:00 | merge queue, CI watch | T2, T3 | T6, T7 | T10 | API v2, relay2 image | core done, bridge lifecycle | gate G1 at ~1:00, tabs/splits | — |
| 3:00–6:00 | gate G2 (~3:30 deploy) | T4, T5, T5B | T8, T11, T12 | T10 done, review | deploy, C15, Flutter 1.0.1 change (no release) | bridge projection, input, approvals | sidebar, palette, IME, login | starts if L4 done |
| 6:00 | **checkpoint 1** | merge | merge | merge | | | | |
| 6:00–10:00 | integration build, flip `remoteMachines` | L1 frees → helps L5 | L2 frees → helps L6 UI polish | remote group + approval UI | support, hardening | e2e Mac↔Mac | remote view of Mac, installer | viewer |
| 10:00 | **checkpoint 2** + gate G3 | | | | | | | |
| 10:00–12:00 | W1 Task 13 perf/network audit, signed build, push, ledger | fixes | fixes | fixes | fixes | fixes | fixes | stop |

## Gates (user, batched)

- **G0 before T+0 (15 min):** free ≥ 30 GB (delete old Flutter `~/Library/Developer/Xcode/DerivedData/Runner-*` and `Pods-*`; the lead lists sizes and asks before deleting); run Typometer on the perf-base app if not done; have the Windows 11 PC on; confirm Actions are enabled on `lephus/shellx`; `! gh auth refresh -s workflow` (lets agents push workflow files over https; SSH alias `phule9225.github.com` works meanwhile).
- **G1 ~T+1 (20 min, Windows PC):** run `shellx-term-spike.exe` checks from W0 Task 7 Step 3 (Telex/Unikey/EVKey, 150/200 %, Typometer vs Windows Terminal, Narrator). Pass → L6 stays on GPUI; fail on IME → L6 switches to the plan's fallback order (winit + wgpu, then Win32 + DirectWrite) and the Windows target shrinks to local terminal only.
- **G2 ~T+3:30 (10 min, VPS):** set `CMUX_RELAY_HMAC_SECRET` (`openssl rand -base64 48`) in `~/phu/shellx/.env` by hand; approve the deploy of `relay2` + API v2 (deploy.yml, `workflow_dispatch` on `feat/relay-v2` — the API change ships in the existing `relay` image, so it is a relay deploy too); DNS only if K2 falls back to a subdomain.
- **G3 ~T+10 (20 min):** hands-on acceptance: on the Mac, Release ShellX + tagged dev build pair and view each other; on Windows, the MVP installs, types Vietnamese, logs in, views the Mac. Also decides whether `main` gets the sprint merge tonight.

## Checkpoints and cut lines

- **Checkpoint 1 (T+6):** merge L1, L2, L3 into `shellx/sprint` in that order (L1 first: identity touches the most shared files), resolve, CI green, lead's local Release build + 10-minute smoke (launch, splits, SSH workspace, Vietnamese UI, no network to Manaflow per `nettop`). Cut if behind: W1 Task 11 (title bar) and Task 12 (Vietnamese strings beyond the main menus) move after the sprint; never cut Task 4 (no phone-home).
- **Checkpoint 2 (T+10):** e2e Mac↔Mac through the deployed relay v2. Cut if behind: Windows remote view (L6 ships local-only MVP), L7 entirely.
- **Never cut:** on-site approval, PSK out of band, no telemetry, signing.

## Lead (L0) tasks

### Task L0.1: Sprint branch and Mac CI (T+0:00–0:45)

**Files (fork):** Create `.github/workflows/shellx-mac.yml`; branch `shellx/sprint` from `main`.

- [ ] **Step 1:** `git -C ~/Documents/myProjects/shellx switch -c shellx/sprint main`; create worktrees for L1–L3, L5, L6 (`~/Documents/myProjects/shellx-wt-<lane>`) from `shellx/sprint` after Step 4, and L4/L7 in the shellx repo (`~/Documents/myProjects/shellx-wt-<lane>`).
- [ ] **Step 2:** write `shellx-mac.yml`: on push to `shellx/**`, `runs-on: macos-26`, steps = checkout with submodules, `./scripts/ensure-ghosttykit.sh` (prebuilt GhosttyKit, sha-pinned), cache DerivedData keyed on `Package.resolved` + GhosttyKit key, `xcodebuild -scheme cmux -configuration Debug build` with `CMUX_WIREGUARD_GO_REQUIRE=0`, `python3 scripts/verify-local.py --all`, `swift test --package-path Packages/Shared/ShellXBrand`, and the ShellX tests (`tests/test_shellx_*.py`). Concurrency group per branch, cancel in progress.
- [ ] **Step 3:** run W1 Task 1 (ShellXBrand package + test runner) on `shellx/sprint` yourself — every Mac lane depends on it.
- [ ] **Step 4:** push `shellx/sprint`; expected: `shellx-mac` green within ~50 min (cold); then branch L1–L3 off it.

### Task L0.2: Merge queue (continuous)

- [ ] Lanes open no PRs; they push their branch and post "ready <sha>" in their report. Lead merges `--no-ff` into `shellx/sprint` in arrival order, reruns CI, and on red bounces the merge back to the lane with the failing log. One local Xcode build at a time on the Mac: lock `~/.shellx-build.lock` (`shlock`-style; lanes check it).

### Task L0.3: Checkpoints (T+6, T+10)

- [ ] Per §Checkpoints. Record each in the ledger under `## Sprint 2026-10-19` (what merged, CI run ids, cuts taken).

### Task L0.4: Close-out (T+10–12)

- [ ] W1 Task 13 (perf compare vs `scripts/shellx/perf/baselines/cmux-122037ee4d.json`, network audit, upstream merge drill).
- [ ] Signed + notarized internal build: `scripts/shellx/sign-and-notarize.sh --build` from `shellx/sprint` (needs the keychain "Always Allow" once).
- [ ] After G3 yes: merge `shellx/sprint` → fork `main`, `feat/relay-v2` → shellx `main` only if its diff is server/docs (it deploys the relay; the Flutter 1.0.1 change stays on its own branch for W3 Part A). Push both.
- [ ] Ledger `## Sprint 2026-10-19 summary`: per lane done/cut, open risks, what W3 Part A needs.

## Throughput rules (why 12 h is possible)

1. **Contracts first:** K1–K5 above let L4/L5/L6 start at T+0 against tests and fakes, not each other's code.
2. **CI is the build farm:** each lane verifies on GitHub runners; local builds only at checkpoints (the Mac does one ~35 min cold build, warm rebuilds ~5–10 min).
3. **Fast inner loop:** SPM package tests (`swift test --package-path Packages/Shared/ShellXBrand`), `cargo test -p shellx-core`, `npm test` in `relay/`, and `python3 tests/test_shellx_*.py` run in seconds; push to CI only after those pass.
4. **Reviews sized to risk:** one reviewer per lane at its merge, plus a per-task security review for K1 tickets/pairings, K3 sealing, and any file-permission code. No per-task review elsewhere.
5. **No idle lanes:** a lane that finishes picks from the after-12h list in this order: L5 support (tests for reconnect), L6 UI polish, W3 Part A dry-run pipeline.
6. **User gates batched** at G0–G3; agents never wait on the user between gates (they stub and continue).

## After the sprint (not in 12 h)

- Windows as a session host: port `cmux-remote` daemon (security review of owner-only ACLs: `secure_directory.rs`, `secret_file.rs`, `identity.rs:2136-2143`, core `platform.rs:1527`), est. 15 d (ledger D-W0-1).
- Embed the daemon through the C ABI instead of the sidecar; durable daemon state; raw PTY-write export in the ghostty fork; Kitty graphics / OSC 8/52 over remote.
- Public release: W3 Part A (Flutter 1.0.1 → Mac 2.0.0 → per-platform `min`), Sparkle appcast on `download.shellx.pro`.
- Share link + "Tiếp tục trên điện thoại" if L7 did not finish (W3 Part B).
- Wave 5 (WebView2 browser, Agent Chat on Windows).
