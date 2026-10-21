## Rulings (L7, 2026-10-21) — record in the ledger in Task B0

- **R1 No Rust sidecar.** The plan's `shellx-share` bridge would attach to the cmux-tui daemon, which only sees Mac terminals projected into it (D7 bind targets the focused terminal, needs the `remoteMachines` gate and a running daemon). The Mac app already owns every pane, its VT tail (`readBoundedScreenTailVT`), its output tee and its input path, and CryptoKit/URLSession cover AES-GCM, HKDF and WebSocket. So the host side is Swift in the app; no new binary to build, sign or bundle. Shares do **not** need `ShellXFeatures.remoteMachines`; they need a signed-in account.
- **R2 Browser admission.** `cmux-relay` answers 403 to any `Origin` (`relay.rs:285`). Add `CMUX_RELAY_ALLOWED_ORIGINS` (comma list, exact match, default empty = today's behaviour) and set it to `https://shellx.pro` in `deploy/docker-compose.yml`. Same `wss://relay.shellx.pro/v2/relay` path; no nginx change on the relay host.
- **R3 Own slot per share.** A second `register` on a slot replaces the first (`relay.rs:677-724`), so each share gets its own random slot (`newSlot()`); the host never touches the machine's slot.
- **R4 Access token.** The viewer proves knowledge of the fragment without sending it: `access = HKDF(secret, salt=share_id, info="shellx-share/1 access")`; the API stores only `sha256(access)` hex. The API rejects any body containing a `secret` field (400 `bad_request`).
- **R5 Lifetimes.** `15m` and `1h` set `expires_at`. `until_quit` sets `expires_at = created + 24 h` (hard cap) and the app revokes it on quit. The QR share is `type` permission, `claim_until = created + 2 min`, stream lifetime `until_quit`, one-time: the first viewer ticket binds `sha256(viewer)` (a random id the page keeps in `sessionStorage`); later tickets must present the same `viewer` (reconnects after a phone sleeps) or get 410 `share_used`.
- **R6 Host online.** `host_seen_at` is refreshed by every host-ticket mint (the host re-registers every 90 s); a viewer ticket answers 503 `host_offline` when `host_seen_at` is older than 150 s.
- **R7 Viewer scope.** One pane at a time with a pane bar on desktop and phone (desktop split layout deferred, parent plan summary). Browser and Agent Chat panes show a placeholder. The viewer never resizes the host: xterm runs at the host grid; the page scrolls horizontally when narrower.

## Controller rulings (preflight, bind every task)

1. `enum SharePermission: String { case view, type }` and `enum ShareLifetime: String { case fifteenMinutes = "15m", oneHour = "1h", untilQuit = "until_quit" }` live in Task B3's `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/Share/ShareMessage.swift` (public).
2. API share ids are 8 chars without dash; the dash (`xxxx-xxxx`) is display/URL only. Swift and the viewer strip it before API calls and before the HKDF salt; the API route accepts both forms.
3. The viewer's API base comes from `web/src/site.config.json` key `shareApiBase` (default `https://relay.shellx.pro`), rendered into the page.

## Wire format v1 and Global Constraints (from the plan)
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


## Wire format v1 amendment A1 (controller ruling 4, binds B3, B4, B7) — per-connection binding against relay replay

- `hello` gains `"nonce": <16 random bytes, standard base64>` generated fresh by the viewer per connection (key order: t, seq, nonce, label). `welcome` gains `"nonce": <16 random bytes, standard base64>` generated fresh by the host per connection (key order: t, seq, nonce, perm, expires_at_unix, panes, active).
- AAD is staged per connection: the viewer's `hello` frame uses `shellx-share/1|<circuit>`; the host's `welcome` frame uses `shellx-share/1|<circuit>|<viewer nonce b64>`; every later frame in both directions uses `shellx-share/1|<circuit>|<viewer nonce b64>|<host nonce b64>`. A frame that fails under the current stage's AAD is dropped and counted.
- Host: before receiving a valid `hello`, accept only `hello`; anything else is dropped. Viewer: before a valid `welcome`, accept only `welcome` (or `bye`, sealed with the welcome-stage AAD).
- Hostile-input caps on open (both sides): a frame > 64 KiB is dropped before decryption. Host additionally drops `in` with data > 4 KiB and truncates `label` to 40 chars.
- Vectors file: add `viewer_nonce_b64`, `host_nonce_b64` and per frame an `aad` string; frames: one `hello` (stage 1), one `welcome` (stage 2), one `out` and one `in` (stage 3).

## Wire format v1 amendment A2 (controller ruling 5, binds B4, B7) — keepalive

- cmux-relay closes a circuit after 300 s without traffic. The host sends `{"t":"ka","seq"}` (stage-3 AAD) on every live circuit that has sent nothing for 60 s. The viewer accepts `ka` as a valid frame (advances seq, does nothing else). `ka` is never sent before `welcome`.
