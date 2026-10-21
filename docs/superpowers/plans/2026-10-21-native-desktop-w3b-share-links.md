# ShellX native desktop — Wave 3 Part B: share links and "Tiếp tục trên điện thoại" (lane L7) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Tóm tắt (cho người dùng):** Chủ phiên trên ShellX Mac bấm "Chia sẻ phiên" → nhận link `shellx.pro/s/k7f2-9qd1#<khoá>`; hoặc bấm "Tiếp tục trên điện thoại" → mã QR. Người nhận mở bằng trình duyệt, không cần app hay tài khoản, xem (và nếu được phép thì gõ) **từng khung một** với thanh chuyển khung. Khoá nằm sau dấu `#`, không máy chủ nào thấy; relay chỉ chuyển bản mã. Khác plan cũ: **không làm sidecar Rust** — app Mac tự mã hoá và nói chuyện với relay (CryptoKit + URLSession), vì app đã giữ sẵn mọi khung terminal; ít thứ phải build, ký và bọc vào app hơn. Lên production cần bạn "đi" ở cổng **G-L7** (sau G2).

**Goal:** A ShellX Mac shares one workspace as a browser link (view-only or typing, 15 min / 1 h / until quit, revocable, "Đang xem" list) and hands it to a phone by a one-time 2-minute QR, end-to-end encrypted with the key in the URL fragment.

**Architecture:** The ShellX API (`relay/`) stores shares and mints relay2 tickets: a `register` ticket for the host on the share's own slot, and an anonymous `connect` ticket for a viewer who proves knowledge of a fragment-derived access token; it refuses with share codes (expired, revoked, used, host offline). The Mac app (`ShareHost`, Swift) registers on the slot through `cmux-relay`, accepts one circuit per viewer and speaks a small JSON protocol inside AES-256-GCM frames keyed by HKDF from the fragment secret; it reads the workspace's terminal panes directly (VT snapshot, PTY output tee, `ghostty_surface_text_input`) and enforces permission and expiry. The viewer is a static Astro page with self-hosted xterm.js that speaks the same protocol with WebSocket + WebCrypto; `cmux-relay` gains an exact-match `Origin` allowlist so browsers from `https://shellx.pro` are admitted.

**Tech Stack:** Node 22 + Hono + better-sqlite3 + vitest (`relay/`); Rust 1.95 (`shellx-core/` client methods, `cmux-tui/crates/cmux-relay` Origin allowlist); Swift 6 / SwiftUI / CryptoKit / `URLSessionWebSocketTask` (macOS 14+); Astro 7.3.5 + `@xterm/xterm` 5.5.0 (MIT, bundled by Vite into `dist/_astro`), plain ES modules (`.mjs`) + `node:test` for viewer logic.

**Spec:** `docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md` §7.2, §7.3, §7.4, §8.5 (principle 3), §8.7; C8, C12, C14, C17. Parent plan: `docs/superpowers/plans/2026-10-19-native-desktop-w3-release-share.md` (Global Constraints and Review Focus 1–4 apply; this file replaces its missing Part B tasks). Relay2 facts: `docs/superpowers/sprint-state/lead/l4-server-report.md`, ledger "Relay spike".

## Rulings (L7, 2026-10-21) — record in the ledger in Task B0

- **R1 No Rust sidecar.** The plan's `shellx-share` bridge would attach to the cmux-tui daemon, which only sees Mac terminals projected into it (D7 bind targets the focused terminal, needs the `remoteMachines` gate and a running daemon). The Mac app already owns every pane, its VT tail (`readBoundedScreenTailVT`), its output tee and its input path, and CryptoKit/URLSession cover AES-GCM, HKDF and WebSocket. So the host side is Swift in the app; no new binary to build, sign or bundle. Shares do **not** need `ShellXFeatures.remoteMachines`; they need a signed-in account.
- **R2 Browser admission.** `cmux-relay` answers 403 to any `Origin` (`relay.rs:285`). Add `CMUX_RELAY_ALLOWED_ORIGINS` (comma list, exact match, default empty = today's behaviour) and set it to `https://shellx.pro` in `deploy/docker-compose.yml`. Same `wss://relay.shellx.pro/v2/relay` path; no nginx change on the relay host.
- **R3 Own slot per share.** A second `register` on a slot replaces the first (`relay.rs:677-724`), so each share gets its own random slot (`newSlot()`); the host never touches the machine's slot.
- **R4 Access token.** The viewer proves knowledge of the fragment without sending it: `access = HKDF(secret, salt=share_id, info="shellx-share/1 access")`; the API stores only `sha256(access)` hex. The API rejects any body containing a `secret` field (400 `bad_request`).
- **R5 Lifetimes.** `15m` and `1h` set `expires_at`. `until_quit` sets `expires_at = created + 24 h` (hard cap) and the app revokes it on quit. The QR share is `type` permission, `claim_until = created + 2 min`, stream lifetime `until_quit`, one-time: the first viewer ticket binds `sha256(viewer)` (a random id the page keeps in `sessionStorage`); later tickets must present the same `viewer` (reconnects after a phone sleeps) or get 410 `share_used`.
- **R6 Host online.** `host_seen_at` is refreshed by every host-ticket mint (the host re-registers every 90 s); a viewer ticket answers 503 `host_offline` when `host_seen_at` is older than 150 s.
- **R7 Viewer scope.** One pane at a time with a pane bar on desktop and phone (desktop split layout deferred, parent plan summary). Browser and Agent Chat panes show a placeholder. The viewer never resizes the host: xterm runs at the host grid; the page scrolls horizontally when narrower.

## Global Constraints

- Parent plan's Global Constraints hold: never push `main` with non-doc changes without the user's go (it deploys), never ask for or print a secret, no third-party requests or telemetry, palette §7.4 only (primary `#60a5fa`, no gradients), GPL-compatible deps only, Vietnamese strings per `scripts/shellx/l10n/vi-glossary.md` ("workspace" = "phiên", "pane" = "khung").
- URL: `https://shellx.pro/s/<id>#<secret>`. `id` = 8 chars of `0123456789abcdefghjkmnpqrstvwxyz` shown as `xxxx-xxxx` (example `k7f2-9qd1`); `secret` = 32 random bytes, base64url without padding (43 chars).
- Defaults: share link "Chỉ xem" + 1 giờ; QR "Được gõ", 2 phút, dùng một lần. Lifetimes exactly `15m` / `1h` / `until_quit`.
- Relay protocol `REMOTE_PROTOCOL_VERSION = 5`; tickets 120 s, issuer `shellx-relay`; binary frames ≤ 64 KiB, so plaintext chunks ≤ 48 KiB.
- Branch `shellx/l7-share` (worktree `../shellx-wt-l7`, = `main` + `--no-ff` merge of `feat/relay-v2` at `cf6f5371e1`). Push the branch freely; merging into `main` deploys API v2 too, so it waits for G2 **and** G-L7.
- Swift app code stays Swift 6.0 compatible; new `cmuxTests/` files → `scripts/sync-test-wiring`; new app `.swift` files registered in `cmux.xcodeproj/project.pbxproj`.

### Wire format v1 (shared by Tasks B3 and B7; vectors in `web/tests/fixtures/share-vectors.json`)

- Keys: HKDF-SHA256, `ikm` = secret (32 bytes), `salt` = UTF-8 of the id without dash (8 bytes), 32-byte outputs for info `shellx-share/1 host->viewer`, `shellx-share/1 viewer->host`, `shellx-share/1 access` (access is sent base64url).
- Frame (one binary WebSocket message): `nonce (12 random bytes) || AES-256-GCM ciphertext||tag`, AAD = UTF-8 `shellx-share/1|<circuit id>`. Plaintext = UTF-8 JSON with an integer `seq` starting at 1 per direction; the receiver drops a frame whose `seq` is not greater than the last one, or that fails to open, and counts it.
- Host → viewer: `{"t":"welcome","seq","perm":"view"|"type","expires_at_unix":int|null,"panes":[{"id","title","kind":"terminal"|"browser"|"agent","cols","rows"}],"active":id}`; `{"t":"panes",…same panes/active}`; `{"t":"replay","pane","cols","rows","data":b64}` (clear + VT); `{"t":"out","pane","data":b64}`; `{"t":"size","pane","cols","rows"}`; `{"t":"bye","reason":"revoked"|"expired"|"host_quit"}`.
- Viewer → host: `{"t":"hello","seq","label"}` (label ≤ 40 chars, e.g. "Safari · iPhone"); `{"t":"select","pane"}`; `{"t":"in","pane","data":b64}` (UTF-8 text or key bytes, ≤ 4 KiB).

## Review Focus

1. **Link opened after expiry/revoke or while the Mac app is closed** — viewer shows "Link đã hết hạn" / "Link đã bị thu hồi" / "Máy chủ phiên đang tắt" and never spins: Task B1 refusal codes, Task B7 `state machine` tests (refused ticket, relay timeout 15 s).
2. **"Chỉ xem" viewer sends input anyway** (devtools) — host drops and counts it, never reaches the PTY: Task B4 `testViewOnlyDropsInput`.
3. **Fragment secret leaking** — no request carries it; `Referrer-Policy: no-referrer`, `history.replaceState` strips the hash before any request, API refuses a `secret` field: Tasks B1, B7, B8.
4. **Vietnamese typing on a phone** (Gboard/iOS Telex composition) — composed text arrives once as UTF-8: Task B7 `input` tests feeding `compositionstart`/`compositionend`/`input`.
5. **Revoke while a viewer is mid-stream, and app quit** — every open circuit gets `bye` and closes within 1 s, the API share is revoked, a reopened link answers `share_revoked`: Task B4 `testRevokeClosesAllCircuits`, Task B6 `testQuitRevokesUntilQuitShares`.

---

### Task B0: Record rulings

**Files:** Modify `docs/superpowers/ledgers/native-desktop.md` (new section `## L7 share rulings (2026-10-21)` with R1–R7, one line each, pointing to this plan); modify `docs/superpowers/plans/2026-10-19-native-desktop-w3-release-share.md` line 9 (append "Part B superseded by `2026-10-21-native-desktop-w3b-share-links.md` (R1: no sidecar)").

- [ ] **Step 1:** Write both edits. **Step 2:** Commit `docs(l7): share-link rulings R1-R7 and the Part B plan`.

### Task B1: API — shares table and routes

**Files:**
- Create: `relay/migrations/0006_shares.sql`, `relay/src/v2/shares.ts`, `relay/test/v2-shares.test.ts`
- Modify: `relay/src/app.ts` (route `/v2/shares`; no injectable `shareId` (the client proposes the id)), `relay/src/http/errors.ts` (codes below), `relay/src/auth/rate-limit.ts` + `relay/test/helpers.ts` (`shareCreate` 10/min per device, `shareTicket` 30/min per IP), `relay/test/db.test.ts:104` (migration list), `relay/src/config.ts` (`SHARE_ALLOWED_ORIGIN`, default `https://shellx.pro`)

**Interfaces:**
- Table `shares(id TEXT PK, user_id, device_id, slot TEXT UNIQUE, permission CHECK(view|type), lifetime CHECK(15m|1h|until_quit), one_time INT, access_hash TEXT, created_at, expires_at, claim_until NULL, viewer_hash NULL, revoked_at NULL, host_seen_at)` (ms timestamps, FKs to users/devices with `ON DELETE CASCADE`).
- `POST /v2/shares` (requireAuth, requireDesktop, body `{id, permission, lifetime, one_time?, access}`; `id` = client-proposed 8 chars (dash and case normalised), a duplicate gives 409 `share_id_taken`; `access` = 43-char base64url) → 201 `{id, slot, expires_at_unix, claim_until_unix|null}`. `one_time: true` forces R5 values. Max 20 unrevoked unexpired shares per device (409 `share_limit`).
- `GET /v2/shares` (owner) → `{shares:[{id, permission, lifetime, expires_at_unix, revoked}]}` of the caller's device.
- `DELETE /v2/shares/:id` (owner) → 204; idempotent; another device's share → 404.
- `POST /v2/shares/:id/host-ticket` (owner) → `{ticket, expires_at_unix, relay_url}`, `register` claims on `shares.slot` (reuse `ticketClaims`/`mintTicket`), sets `host_seen_at`; revoked/expired → 410 code.
- `POST /v2/shares/:id/ticket` (**no auth**, CORS only for `SHARE_ALLOWED_ORIGIN`, body `{access, viewer}`; `viewer` 16–64 chars base64url) → `{ticket, expires_at_unix, relay_url, slot}`, `connect` claims. Refusal order: 404 `share_not_found` (also wrong `access` — never reveal existence), 410 `share_revoked`, 410 `share_expired`, 410 `share_used`, 503 `host_offline`, 429.

- [ ] **Step 1: Write the failing tests** in `v2-shares.test.ts` (use `makeApp({now})`, `registerAccount`, `loginDesktop`, `call`, `errorCode`):
  - `creates a share with its own slot` — slot ≠ any `machines.slot`, id matches `/^[0-9a-hjkmnp-tv-z]{8}$/`, `expires_at_unix - now = 3600` for `1h`, `86400` for `until_quit`.
  - `refuses a body carrying secret` — `{…, secret: "x"}` → 400 `bad_request`; the row count stays 0.
  - `viewer ticket needs the access token` — wrong access → 404 `share_not_found`; right access → 200 with claims `permission:"connect"`, `role:"client"`, `slot` = share slot.
  - `refusal codes` — after `DELETE` → 410 `share_revoked`; clock past expiry → 410 `share_expired`; no host ticket for 151 s → 503 `host_offline`; host ticket at 149 s → 200.
  - `one-time share binds the first viewer` — QR share: viewer A 200, viewer A again at +10 min 200, viewer B 410 `share_used`, viewer A first claim at +121 s → 410 `share_expired`.
  - `another account cannot revoke or host` — 404 for both.
  - `CORS` — preflight `OPTIONS` from `https://shellx.pro` gets `access-control-allow-origin: https://shellx.pro`; from `https://evil.example` gets none; `/v2/shares` (create) never sends CORS headers.
  - `never logs access or tickets` — same spy pattern as `v2-relay-tickets.test.ts:154`.
- [ ] **Step 2: Run** `cd relay && npx vitest run test/v2-shares.test.ts` → FAIL (route missing).
- [ ] **Step 3: Implement** migration, routes, errors, limiters (share id from `crypto.randomBytes` mapped to the alphabet; `claim_until` checked only before the first claim).
- [ ] **Step 4: Run** `cd relay && npm run typecheck && npm test` → PASS (whole suite, incl. `db.test.ts`).
- [ ] **Step 5: Commit** `feat(relay): share links API — shares table, host and anonymous viewer tickets, refusal codes`.

### Task B2: cmux-relay Origin allowlist

**Files:** Modify `cmux-tui/crates/cmux-relay/src/config.rs` (`allowed_origins: Vec<String>` from `CMUX_RELAY_ALLOWED_ORIGINS` / `--allowed-origin` repeatable), `cmux-tui/crates/cmux-relay/src/relay.rs:285` (403 only when `Origin` is present and not in the list), `deploy/docker-compose.yml` (relay2 env `CMUX_RELAY_ALLOWED_ORIGINS: https://shellx.pro`), `deploy/tests/compose.test.mjs` (assert that env value).

- [ ] **Step 1: Write the failing tests** next to `browser_origin_is_rejected_before_relay_admission` (relay.rs:2257): `allowed_origin_is_admitted` (Origin `https://shellx.pro` with the list set → upgrade succeeds and a `register` gets `registered`), `other_origin_still_rejected` (list set, Origin `https://shellx.pro.evil.example` → 403), and keep the existing test (empty list → 403).
- [ ] **Step 2: Run** `cd cmux-tui && ~/.cargo/bin/cargo test -p cmux-relay origin` → FAIL.
- [ ] **Step 3: Implement**; compare the header bytes exactly, no case folding, no trailing-slash tolerance.
- [ ] **Step 4: Run** the same command → PASS; `cd deploy && node --test tests/compose.test.mjs` → PASS.
- [ ] **Step 5: Commit** `feat(cmux-relay): exact-match Origin allowlist so the shellx.pro share viewer can connect`.

### Task B3: Swift wire format and crypto (pure)

**Files:**
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/Share/ShareSecret.swift`, `ShareCipher.swift`, `ShareMessage.swift`; `web/tests/fixtures/share-vectors.json`; `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/ShareWireTests.swift`

**Interfaces (Produces):**
- `struct ShareSecret { static func random() -> ShareSecret; init?(base64url: String); var base64url: String; func keys(shareID: String) -> ShareKeys }` (`shareID` with or without dash).
- `struct ShareKeys { let hostToViewer: SymmetricKey; let viewerToHost: SymmetricKey; let access: String /* base64url */ }`
- `struct ShareCipher { init(sendKey:, receiveKey:, circuit: String); mutating func seal(_ m: ShareMessage) throws -> Data; mutating func open(_ frame: Data) -> ShareMessage? /* nil = dropped */; private(set) var dropped: Int }` — owns both `seq` counters.
- `enum ShareMessage: Equatable, Codable { case welcome(perm:, expiresAt: Int?, panes: [SharePane], active: String), panes([SharePane], active: String), replay(pane:, cols:, rows:, data: Data), out(pane:, data: Data), size(pane:, cols:, rows:), bye(ShareByeReason), hello(label: String), select(pane: String), input(pane: String, data: Data) }`; `struct SharePane { id, title, kind: SharePaneKind, cols, rows }`; `enum ShareByeReason: String { revoked, expired, hostQuit = "host_quit" }`. JSON keys exactly as "Wire format v1".
- `share-vectors.json`: `{secret, share_id, keys:{host_to_viewer_hex, viewer_to_host_hex, access}, frames:[{circuit, key:"host_to_viewer", nonce_hex, plaintext, frame_hex}]}` — generated once by this task's test helper with fixed nonces (`ShareCipher` gets an internal `nonce` injection for tests only).

- [ ] **Step 1: Write the failing tests:** `testKeysMatchVectors`, `testSealWithFixedNonceMatchesVectorFrame`, `testOpenRejectsReplayedSeq` (same frame twice → second `nil`, `dropped == 1`), `testOpenRejectsOtherCircuit` (AAD mismatch → `nil`), `testMessageJSONKeys` (encode `.input` → `{"t":"in","seq":1,"pane":"p","data":"aGk="}`), `testSecretRoundTripIs43Chars`.
- [ ] **Step 2: Run** `cd Packages/Shared/ShellXBrand && swift test --filter ShareWireTests` → FAIL.
- [ ] **Step 3: Implement** with CryptoKit `HKDF<SHA256>.deriveKey` and `AES.GCM.seal(_, using:, nonce:, authenticating:)`; write the vectors file from the test helper once, then the test only reads it.
- [ ] **Step 4: Run** the same → PASS.
- [ ] **Step 5: Commit** `feat(shellx): share wire format v1 — fragment keys, AES-GCM frames, message codec and vectors`.

### Task B4: Swift ShareHost — relay session and viewer enforcement (pure)

**Files:**
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/Share/ShareSocket.swift` (protocol + `URLSessionShareSocket`), `ShareRelayControl.swift` (relay JSON control messages), `ShareHost.swift`, `ShareSource.swift` (protocol); `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/ShareHostTests.swift` (with an in-memory fake relay and fake source)

**Interfaces:**
- Consumes: Task B3 types.
- `protocol ShareSocket: Sendable { func send(text: String) async throws; func send(data: Data) async throws; func receive() async throws -> ShareSocketMessage /* .text/.data */; func close() }`; `protocol ShareSocketFactory: Sendable { func open(_ url: URL) async throws -> ShareSocket }`.
- `@MainActor protocol ShareSource: AnyObject { var panes: [SharePane] { get }; var activePane: String? { get }; func snapshot(pane: String) -> (cols: Int, rows: Int, vt: Data)?; func subscribe(pane: String, _ sink: @escaping @Sendable (Data) -> Void) -> AnyObject /* token; drop to unsubscribe */; func input(pane: String, _ bytes: Data); var onPanesChanged: (() -> Void)? { get set } }`
- `protocol ShareTicketProvider: Sendable { func hostTicket(shareID: String) async throws -> (ticket: String, relayURL: URL, expiresAt: Date) }`
- `actor ShareHost { init(shareID:, slot:, secret: ShareSecret, permission: SharePermission /* .view/.type */, expiresAt: Date?, source: ShareSource, tickets: ShareTicketProvider, sockets: ShareSocketFactory, clock: @Sendable () -> Date); func start() async; func stop(reason: ShareByeReason) async; var viewers: [ShareViewer] { get }; nonisolated var viewerStream: AsyncStream<[ShareViewer]> }` — `ShareViewer { id: String /* circuit */, label: String, connectedAt: Date }`, `droppedInputCount: Int`.
- Behaviour: register (`{"type":"register","protocol":5,"slot","ticket"}`), ping every 10 s, re-register on a fresh control socket every 90 s and close the old one after `registered`; on `incoming` open a circuit socket and `join` with the join ticket, role `daemon`; after `ready` wait ≤ 10 s for `hello`, then send `welcome` + `replay` of the active pane, then stream `out`/`size` for the viewer's selected pane only; `select` → `replay` of that pane; `input` written only when `permission == .type` and the pane is a terminal; at `expiresAt` send `bye(expired)` to all and stop; relay errors back off 1/2/4/8/16/30 s.

- [ ] **Step 1: Write the failing tests:** `testRegistersOnShareSlot`, `testReRegistersBeforeTicketExpiry` (fake clock +90 s → second `register`, first socket closed), `testViewerGetsWelcomeAndReplay`, `testViewOnlyDropsInput` (`.view` share, viewer sends `in` → source never called, `droppedInputCount == 1`), `testTypeShareWritesInputByteExact` (`"chào\r"` UTF-8 arrives once), `testSelectSwitchesStream`, `testExpiryEndsEveryViewer` (bye `expired`), `testRevokeClosesAllCircuits` (`stop(.revoked)` → each fake circuit gets `bye` then close within 1 s), `testOutputChunksStayUnder48KiB` (200 KiB output → frames ≤ 64 KiB), `testViewerListUpdates`.
- [ ] **Step 2: Run** `swift test --filter ShareHostTests` → FAIL.
- [ ] **Step 3: Implement**; output from `subscribe` is coalesced per 16 ms and sealed off the main actor.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(shellx): ShareHost — registers a share slot on relay2, one encrypted circuit per viewer, permission and expiry enforced`.

### Task B5: shellx-core share methods

**Files:** Create `shellx-core/src/shares.rs`, `shellx-core/tests/shares.rs`; modify `shellx-core/src/lib.rs` (`KNOWN_METHODS` + dispatch), `shellx-core/fake-api/src/*` (the four owner routes of Task B1, same JSON), `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/ShellXCoreClient.swift` (typed wrappers).

**Interfaces:** core methods `shares.create {permission, lifetime, one_time, access}` → `{id, slot, expires_at_unix, claim_until_unix}`; `shares.list {}`; `shares.revoke {id}`; `shares.host_ticket {id}` → `{ticket, expires_at_unix, relay_url}`. Errors keep the API `code` (`share_revoked` …). Swift: `ShellXCoreClient.createShare(...)`, `listShares()`, `revokeShare(id:)`, `hostShareTicket(id:)`; `ShellXCoreShareTickets: ShareTicketProvider`.

- [ ] **Step 1: Write the failing tests** in `tests/shares.rs` against fake-api: `create_then_host_ticket`, `revoke_is_idempotent`, `revoked_share_host_ticket_maps_code`, `create_never_sends_secret` (fake-api records the body; assert keys == `{permission,lifetime,one_time,access}`).
- [ ] **Step 2: Run** `cd shellx-core && ~/.cargo/bin/cargo test --workspace --locked shares` → FAIL.
- [ ] **Step 3: Implement** like `tickets.rs`.
- [ ] **Step 4: Run** `cargo test --workspace --locked && python3 scripts/check_deps.py` → PASS; `swift test` in ShellXBrand → PASS.
- [ ] **Step 5: Commit** `feat(shellx-core): shares.create/list/revoke/host_ticket`.

### Task B6: Mac app — workspace source, share controller and popovers

**Files:**
- Create: `Sources/ShellX/Share/WorkspaceShareSource.swift` (`ShareSource` over one `Workspace`), `Sources/ShellX/Share/ShellXShareController.swift`, `Sources/ShellX/Share/ShellXSharePopover.swift`, `Sources/ShellX/Share/ShellXPhoneHandoffPopover.swift`, `Sources/ShellX/Share/ShellXQRCode.swift` (CIQRCodeGenerator, ECC M, quiet zone 4 — copy of `CmxPairingQRBitmap`); `cmuxTests/ShellXShareTests.swift`
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/Bridge/ShellXBridgeTee.swift` (registry holds `ShellXTeeSink` — `protocol ShellXTeeSink: AnyObject, Sendable { func teeOutput(_ bytes: Data) }`; `BridgeConnection` conforms; add `public static func register(_ sink: ShellXTeeSink, surfaceID:)`/`unregister`), `ShellXFeatures.swift` (`shareLinks = false`; DEBUG `SHELLX_SHARE_LINKS=1` via a `ShellXShareGate` like `ShellXRemoteGate`), `Sources/ShellX/Titlebar/ShellXTitlebarAccessory.swift` (share button left of settings, `titlebarControl.shellxShare`), `Sources/Sidebar/AppKitList/Cells/SidebarWorkspaceRowCommands.swift` + `Sources/TabItemView+WorkspaceContextMenu.swift` ("Chia sẻ phiên…", "Tiếp tục trên điện thoại"), `Sources/AppDelegate.swift` (quit → `ShellXShareController.shared.stopAll()`), `Resources/Localizable.xcstrings`, `cmux.xcodeproj/project.pbxproj`

**Interfaces:**
- `WorkspaceShareSource(workspace:)`: panes in bonsplit order; terminal kind for terminal panels, `browser`/`agent` placeholders; `snapshot` = `"\e[H\e[2J" + readBoundedScreenTailVT(maxRows: 200, maxBytes: 1 << 20)` and `ghostty_surface_size`; `input` → `ghostty_surface_text_input`; `subscribe` registers a `ShellXTeeSink` for the surface id.
- `@MainActor final class ShellXShareController: ObservableObject { static let shared; @Published private(set) var active: [ActiveShare] /* id, url, permission, lifetime, workspaceID, viewers */; func share(workspaceID: UUID, permission: SharePermission, lifetime: ShareLifetime) async throws -> URL; func phoneHandoff(workspaceID: UUID) async throws -> URL; func revoke(_ id: String) async; func stopAll() async /* bye host_quit, revoke until_quit and one-time shares */ }`. `phoneHandoff` regenerates its QR on expiry while the popover is open.
- Share popover per §7.3: link + "Sao chép", permission "Chỉ xem"/"Được gõ" (default view), lifetime "15 phút"/"1 giờ"/"Khi tôi tắt" (default 1 h), "Đang xem" list, "Thu hồi link". Phone popover per §7.2: QR + "Quét bằng camera điện thoại" (no app yet, C14; "Gửi tới máy đã ghép cặp" hidden). Not signed in → "Đăng nhập để chia sẻ" opening the existing sign-in sheet. Errors in Vietnamese and English.

- [ ] **Step 1: Write the failing tests** in `cmuxTests/ShellXShareTests.swift` (fake core client + fake socket factory): `testSourceListsTerminalAndPlaceholderPanes`, `testSourceInputReachesSurface`, `testTeeSinkReceivesOutputOnlyWhileSubscribed`, `testShareDefaultsAreViewAndOneHour`, `testShareURLHasIdPathAndSecretFragment` (`https://shellx.pro/s/xxxx-xxxx#` + 43 chars; the secret never appears in the recorded core-call params), `testQuitRevokesUntilQuitShares`, `testGateOffHidesEntrypoints`.
- [ ] **Step 2: Run** `scripts/sync-test-wiring && scripts/shellx/test-app.sh ShellXShareTests` → FAIL.
- [ ] **Step 3: Implement**; route the titlebar button and both context-menu items through `ShellXShareController` (cmux-shared-behavior: one action path). Run the localization audit (`python3 scripts/localization_catalog.py check`).
- [ ] **Step 4: Run** the same tests → PASS; `swift test` in ShellXBrand → PASS; `python3 scripts/verify-local.py` → PASS.
- [ ] **Step 5: Commit** `feat(shellx): share a workspace as a link or a phone QR from the titlebar and workspace menu`.

### Task B7: Web viewer `/s/`

**Files:**
- Create: `web/src/pages/s/index.astro`, `web/src/share/wire.mjs` (keys, seal/open, codec), `web/src/share/session.mjs` (state machine), `web/src/share/input.mjs` (keyboard/composition → bytes), `web/src/share/viewer.mjs` (DOM + xterm glue), `web/tests/share.test.mjs`
- Modify: `web/package.json` (`@xterm/xterm` 5.5.0 dependency; add `tests/share.test.mjs` to `test` and `build`), `web/tests/site.test.mjs` (viewer checks below), `web/src/i18n/ui.ts` (viewer strings vi + en; page shows vi or en from `navigator.language`)

**Interfaces:** Consumes the wire format (vectors) and Task B1 `POST /v2/shares/:id/ticket`. `session.mjs` exports `createSession({id, secret, fetch, WebSocket, now, setTimeout, storage})` returning an emitter with states `loading` → `connecting` → `live` | `expired` | `revoked` | `used` | `host_offline` | `not_found` | `ended` | `error`.

- [ ] **Step 1: Write the failing tests** in `share.test.mjs` (WebCrypto from `globalThis.crypto`, fake fetch/WebSocket):
  - `keys and frames match share-vectors.json`.
  - `refused ticket maps to a state` — 410 `share_expired` → `expired`, 410 `share_revoked` → `revoked`, 410 `share_used` → `used`, 503 `host_offline` → `host_offline`, 404 → `not_found`.
  - `relay timeout ends in host_offline after 15 s` — `ready` never arrives → state `host_offline`, sockets closed.
  - `bye reasons` — `bye expired` → `expired`, `revoked` → `revoked`, `host_quit` → `host_offline`.
  - `ticket request carries no secret` — the fetch body is exactly `{access, viewer}` and the URL has no `#` or `?`.
  - `viewer id persists in storage` — second session with the same storage sends the same `viewer`.
  - `composition sends text once` — `compositionstart`, `input` ×2 during composition, `compositionend("chào")` → one `in` frame with UTF-8 `chào`; Enter → `\r`; Backspace → `\x7f`.
  - `view-only page sends no input frames`.
- [ ] **Step 2: Add to `site.test.mjs`:** `/s/index.html` has `<meta name="referrer" content="no-referrer">`, `robots noindex`, no external `src`/`href` (extend the no-external test to also scan `dist/_astro/*.js` for `https?://` other than `shellx.pro` and `relay.shellx.pro`), not in sitemap, one `<h1>`; the inline boot script calls `history.replaceState` before any `fetch`.
- [ ] **Step 3: Run** `cd web && npm ci && npm run build` → FAIL.
- [ ] **Step 4: Implement**: page `page={null}` in `Base`; the hash is read and stripped first; xterm at host grid, read-only when `perm == "view"`, pane bar from `panes`, placeholders for non-terminal panes, an on-screen key row (Esc, Tab, Ctrl, ←↑↓→) on touch devices when typing is allowed; palette §7.4.
- [ ] **Step 5: Run** `npm run build` → PASS (tests run inside build).
- [ ] **Step 6: Commit** `feat(web): /s/ share viewer — fragment keys, encrypted relay2 stream, pane bar, phone typing`.

### Task B8: Serving headers

**Files:** Modify `deploy/web/nginx.conf` (shellx.pro server):

```
location ~ "^/s/[0-9a-z]{4}-[0-9a-z]{4}/?$" {
    add_header Referrer-Policy "no-referrer" always;
    add_header Content-Security-Policy "default-src 'self'; connect-src https://relay.shellx.pro wss://relay.shellx.pro; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; frame-ancestors 'none'" always;
    add_header Cache-Control "no-store" always;
    try_files /s/index.html =404;
}
```

Create `deploy/tests/web-nginx.test.mjs`.

- [ ] **Step 1: Write the failing test** reading `nginx.conf`: the `/s/` location exists with those three headers and `try_files /s/index.html`; `/s/` without an id is not matched (404 page).
- [ ] **Step 2: Run** `cd deploy && node --test tests/web-nginx.test.mjs` → FAIL. **Step 3: Implement.** **Step 4:** → PASS; if Docker is available `docker build -f web/Dockerfile .` runs `nginx -t` → OK.
- [ ] **Step 5: Commit** `feat(deploy): serve the share viewer with no-referrer, CSP and no-store`.

### Task B9: End-to-end harness and dogfood

**Files:** Create `scripts/shellx/share-e2e.mjs`, `tests/test_shellx_share_e2e.py` (lane `manual` in `tests/test-execution.toml`), `docs/superpowers/sprint-state/l7/e2e.md` (results).

- [ ] **Step 1:** `share-e2e.mjs` starts `cmux-relay` (built by `cargo build -p cmux-relay`, HMAC secret from a temp file, `CMUX_RELAY_ALLOWED_ORIGINS=https://shellx.pro`) and the Node API on loopback, creates a share with a test desktop account, runs a Swift `ShareHost` test executable with a scripted `ShareSource` (`swift run` target `share-e2e-host` in ShellXBrand, test-only product), and a Node viewer from `web/src/share/session.mjs` with `Origin: https://shellx.pro`; asserts welcome → replay → typed `echo hi\r` arrives (type share), view share drops input, revoke → `revoked` within 1 s, expiry → `expired`.
- [ ] **Step 2: Run** `python3 tests/test_shellx_share_e2e.py` → PASS (record output in `e2e.md`).
- [ ] **Step 3: Dogfood** a tagged build (`skills/cmux-dev-workflow/references/tagged-builds.md`) with `SHELLX_SHARE_LINKS=1` and `SHELLX_API_BASE` pointing at a local API + relay reachable from the phone on the LAN (viewer served by `npm run preview` with a dev `connect-src`): Safari iOS and Chrome Android open the QR, Telex typing works, revoke cuts the phone. Record in `e2e.md`. Never touch `/Applications/cmux.app` or the Flutter ShellX.
- [ ] **Step 4: Commit** `test(shellx): share links end to end through cmux-relay and the API`; push `shellx/l7-share`.

### Gate G-L7 (user)

After G2 is done: merge `shellx/l7-share` into `main` `--no-ff` and push (deploys API v2 + shares, web `/s/`, relay2 with the Origin allowlist); rebuild relay2 from the source tarball including Task B2; flip `ShellXFeatures.shareLinks` in a follow-up Mac release. Rollback: `deploy.yml` "Run workflow" with the previous `main` sha; the `shares` table is additive.
