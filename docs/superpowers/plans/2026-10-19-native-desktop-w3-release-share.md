# ShellX native desktop — Wave 3: public release (Part A) and share links (Part B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Part A and Part B are independent; run them as separate lanes.

**Tóm tắt (cho người dùng):** Kế hoạch có hai phần. **Phần B** (lane L7, chạy trong sprint từ khoảng T+3 nếu lane API v2 xong): link chia sẻ `shellx.pro/s/<id>#<khoá>` và nút "Tiếp tục trên điện thoại", mở bằng trình duyệt, không cần app hay tài khoản. Khoá nằm sau dấu `#` nên máy chủ không bao giờ thấy; relay chỉ thấy bản mã. Trong 7 giờ chỉ làm được bản tối thiểu trung thực: xem và gõ **từng pane một** (có thanh chuyển pane), chưa hiện bố cục chia khung trên trình duyệt desktop. **Phần A** (sau sprint, cần bạn bấm "đi" ở từng cổng): phát hành Flutter 1.0.1 (chỉ thêm gửi nền tảng + phiên bản hệ điều hành), relay đặt mức tối thiểu riêng cho từng nền tảng, pipeline phát hành ShellX Mac 2.0.0 trong repo fork công khai (ký, notarize, DMG, Sparkle appcast có chữ ký EdDSA, tải lên `download.shellx.pro`), rồi mới bắt người dùng Flutter trên macOS 14+ cập nhật. Có các bước quay lui.

**Goal:** Part A ships ShellX Mac 2.0.0 publicly (after Flutter 1.0.1 and per-platform minimums), with Sparkle updates from `download.shellx.pro`; Part B lets a ShellX Mac share a session as a browser link (view-only or typing, with expiry and revoke) and hand it to a phone by QR, end-to-end encrypted with the key in the URL fragment.

**Architecture:** Part A reuses the shellx repo's release pattern (version in a file, push `main` releases it unless `download.shellx.pro` already serves it; rsync over SSH; immutable installers) in a new fork workflow, and adds a mutable `desktop/appcast.xml` + `desktop/latest-macos.json` that the relay reads to answer `/v1/version` per platform. Part B adds a host-side **share bridge** (`shellx-share`, Rust, sidecar next to the `cmux-tui` daemon) that attaches to the session as a trusted local client and republishes it to browsers over the self-hosted `cmux-relay` (K2) as AES-256-GCM frames keyed from the URL fragment; the browser viewer (Astro page + vendored xterm.js) only needs WebSocket + WebCrypto. The ShellX API mints anonymous relay tickets per share and enforces expiry/revocation at ticket time; the bridge enforces permission and expiry on the live stream.

**Tech Stack:** shellx repo: Node 22 + Hono + better-sqlite3 + vitest (relay/API), Astro 7 + `@xterm/xterm` 5.5.0 + `@xterm/addon-fit` 0.10.0 (MIT, bundled, self-hosted), Flutter 3.41.7 / Dart (1.0.1 only), GitHub Actions. Fork: Rust (own crate in `shellx-core/` workspace; `aes-gcm` 0.10, `hkdf` 0.12, `sha2` 0.10, `tokio`, `tokio-tungstenite` with rustls), Swift 6 / SwiftUI (popovers), Sparkle 2 tools 2.8.1 (pinned by `scripts/sparkle_generate_appcast.sh`), Python 3 stdlib `unittest` for fork guard tests.

**Spec:** `docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md` (§2.2 item 5, §5, §7.2, §7.3, §8.5 principle 3, §8.7, §11, §12; C8, C12, C14, C15, C17). Master plan: `docs/superpowers/plans/2026-10-19-native-desktop-12h-sprint.md` (Contracts K1–K5, Global Constraints, gates). Ledger: `docs/superpowers/ledgers/native-desktop.md` (Signing, Relay spike, D-W0-1). Release pipeline reference: `release/README.md`, `.github/workflows/release-desktop.yml`.

## Global Constraints

- Every Global Constraint of the master plan holds; repeated here because they bite: never push shellx `main` with non-doc changes during the sprint (it starts `release-desktop.yml`); never ask for or print a secret value in chat (the user sets secrets by hand: `! gh secret set … < file` or the GitHub/VPS UI); no third-party services or telemetry; no BUSL code from the fork (`web/`, `workers/*`, `services/iroh-relay-minter/`, `cmux-tui/relays/cloudflare-do/`); GPL-compatible deps only.
- Identity: bundle id `pro.shellx.desktop`, team `W4RF3W4VTZ`, Apple account `phulealali@gmail.com`, version `2.0.0` (native), macOS 14+ (`MACOSX_DEPLOYMENT_TARGET = 14.0`), Windows installer unsigned.
- Release rule (spec §5/§11): push to `main` releases the version written in the version file; the user picks the number; no tag-triggered releases; installers are immutable (never overwrite a published version — release `X.Y.(Z+1)` instead).
- Download layout (frozen by W1 Task 2 `ShellXBrand.updateFeedURL`): appcast `https://download.shellx.pro/desktop/appcast.xml`; native installers `desktop/<v>/ShellX-<v>.dmg` and `desktop/<v>/ShellX-Setup-<v>.exe` (Flutter is frozen at 1.0.x, native starts at 2.0.0, so the shared folder never collides); native latest manifests `desktop/latest-macos.json`, `desktop/latest-windows.json`.
- `deploy/relay.env` `LATEST_AGENT_VERSION` / `MAC_URL` / `WIN_URL` keep naming the **Flutter** release (the Flutter pipeline's `bump.mjs` compares against it); native versions live only in the `latest-*.json` manifests.
- Share links (spec §7.3, §8.5 p.3, C8): URL `https://shellx.pro/s/<id>#<secret>`; the secret never reaches any server; defaults: "Chỉ xem" + 1 hour; "Tiếp tục trên điện thoại" QR = "Được gõ" + 2 minutes, one-time; lifetimes `15m` / `1h` / `until_quit`.
- Relay sees only ciphertext; the viewer page loads nothing from third parties (`web/tests/site.test.mjs` "no external scripts…"); palette §7.4 only, no gradients, primary `#60a5fa`.
- Branches: Part B = shellx `feat/share-viewer` (worktree `~/Documents/myProjects/shellx-wt-l7`) + fork `shellx/l7-share` (worktree `~/Documents/myProjects/shellx-pro-wt-l7`, branched from `shellx/sprint`); Part A = shellx `release/w3` and fork `shellx/w3-release`, merged to `main` only at the user gates below.
- Each task ≤ 60 min agent time (CI waits not counted).

## Review Focus

1. **Share link opened after expiry or revoke, or while the host app is closed** — the viewer must show a clear Vietnamese/English state ("Link đã hết hạn" / "Máy chủ phiên đang tắt") and never spin forever. Owner: Task B1 (ticket refusal codes) + Task B6 (viewer state machine test with a refused ticket and a relay timeout).
2. **"Chỉ xem" viewer sends input anyway** (crafted page, devtools) — the bridge must drop input frames from a view-only share and count them, never write them to the PTY. Owner: Task B4 test `view_only_drops_input`.
3. **Fragment secret leaking** — no request from the viewer may carry the secret (no `Referer` with fragment, no query string, no log line); `Referrer-Policy: no-referrer` and the secret is removed from `location.hash` after reading. Owner: Task B5 test (page header + `history.replaceState`) and Task B1 test (API never accepts a `secret` field).
4. **Vietnamese typing on a phone** (Gboard/iOS Telex, composition) — composed text must arrive as UTF-8 once, not as raw keys or doubled. Owner: Task B6 input test feeding `compositionend` + `input` events.
5. **Flutter on macOS 12–13 or Windows forced to the native dmg** — raising the macOS-14 minimum must not change the answer for `flutter-macos` 13.x, `flutter-windows`, or a 1.0.0 client that sends no platform. Owner: Task A1 test table.

---

# Part A — Public release: Flutter 1.0.1, per-platform minimum, ShellX Mac 2.0.0 (Wave 3, after the sprint)

**Order is binding:** A1 (relay per-platform) → A2/A3 (Flutter 1.0.1) → A4–A8 (fork pipeline + dry run) → A9 (2.0.0 live) → A10 (raise minimum) → A11 (website). A user gate (GA0–GA5) sits before every step that publishes, deploys, or spends billed minutes.

## User gates (Part A)

| Gate | When | What the user does (never paste values in chat) | Est. |
| --- | --- | --- | --- |
| **GA0** | before A6 | (1) Fork → Settings → Environments → `release`: deployment branches = `main` only, required reviewer = you; add secrets `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, and either `APPLE_API_KEY_P8_BASE64` + `APPLE_API_KEY_ID` + `APPLE_API_ISSUER_ID` or `APPLE_APP_SPECIFIC_PASSWORD` (same values as the shellx repo's `release` Environment, `release/README.md` §GitHub secrets). (2) Sparkle key: run `generate_keys` from the Sparkle 2.8.1 tools (the agent prints the exact download + sha256 check command), then `generate_keys -x ~/sparkle-private.key`, `! gh secret set SPARKLE_PRIVATE_KEY --env release --repo lephus/shellx-pro < ~/sparkle-private.key`, `rm ~/sparkle-private.key`; give the agent only the **public** key (`generate_keys -p`). (3) VPS upload key: on the VPS add a new key line to `~/.ssh/authorized_keys` restricted to `command="rrsync -wo ~/phu/shellx/downloads/desktop",restrict` (the agent prints the line template with the public key the user generated locally), then in fork → Environments → `production` (branch `main` only) set `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`, `VPS_KNOWN_HOSTS`. (4) Approve `gh workflow disable` of upstream workflows in the fork (`release.yml`, `nightly.yml`, `nightly-sign.yml`, `cmux-tui-release*.yml`, `coderouter-release.yml`, `sdk-release-cut.yml`; a repo setting, no file edit). | 30 min |
| **GA1** | after A1 merged on `release/w3` | "go" to push shellx `main` with the relay change (deploys the relay; `release-desktop.yml` sees 1.0.0 already published and exits in seconds). | 5 min |
| **GA2** | after A3 tests | "go" to push shellx `main` with Flutter 1.0.1 (builds + signs + publishes both Flutter installers, ~300 billed minutes). Optional same gate: raise `min_agent` to `1.0.1` on admin.shellx.pro once 1.0.1 is live (forces every Flutter user onto the build that reports its platform). | 5 min |
| **GA3** | after A8 dry run | Install the dry-run dmg (ad-hoc signed: right-click → Open) on your Mac, 10-minute smoke (launch, splits, Vietnamese UI, sign in, Mac↔Mac if the sprint shipped it). Then "go" to push fork `main` with `MARKETING_VERSION = 2.0.0`. Approve the `release` Environment review in the Actions UI. | 25 min |
| **GA4** | after A9 verified | On a clean Mac: download the public dmg in Safari, open (only the standard "downloaded from the Internet" prompt), ShellX → Check for Updates says up to date. Then on admin.shellx.pro set **"Flutter trên macOS 14+" = 2.0.0**. | 15 min |
| **GA5** | later, optional | Decide whether the Windows native installer is published (`SHELLX_WINDOWS_CHANNEL` = `upload`) and announced (`announce`); spec §10 puts the Windows public release in Wave 4. | 2 min |

## Contract added by Part A (K6, proposed to L0 for the master plan)

**K6 native latest manifest + per-platform `/v1/version`** (only if L4 did not already freeze a C15 shape; if it did, Task A1 adapts to L4's shape and keeps the test table).

- Files written by the fork release workflow, served by the `web` container, read by the relay through a read-only mount `./downloads/desktop:/srv/downloads/desktop:ro`:
  `desktop/latest-macos.json` = `{"version":"2.0.0","url":"https://download.shellx.pro/desktop/2.0.0/ShellX-2.0.0.dmg","sha256":"<hex>","min_os":"14.0","published_at_unix":<int>}` (same shape `latest-windows.json`, `url` ends `.exe`, `min_os` `"10.0.17763"`).
- `/v1/version` request headers: `X-ShellX-Version`, `X-ShellX-Platform` ∈ `macos|windows|flutter-macos|flutter-windows`, `X-ShellX-OS-Version` = `major.minor[.patch]`. Response keeps the v1 body (`min_agent`, `min_mobile`, `latest_agent{version,mac_url,win_url}`), computed per audience:

| Audience | Matches | `min_agent` | `latest_agent` |
| --- | --- | --- | --- |
| `native-macos` | platform `macos` | setting `min_macos` → env `MIN_MACOS` (default `2.0.0`) | manifest macos (`mac_url` = its url, `win_url` = env `WIN_URL`); legacy env if no manifest |
| `native-windows` | platform `windows` | `min_windows` → env `MIN_WINDOWS` (default `2.0.0`) | manifest windows (`win_url`), legacy if none |
| `flutter-macos-14` | `flutter-macos` and OS major ≥ 14 | `min_flutter_macos14` → `min_agent` | manifest macos when present, else legacy |
| `flutter-windows` | `flutter-windows` | `min_flutter_windows` → `min_agent` | legacy (until GA5 `announce`) |
| `legacy` | anything else (no header, `flutter-macos` < 14, unparsable OS) | `min_agent` (unchanged behaviour) | legacy env (`LATEST_AGENT_VERSION`, `MAC_URL`, `WIN_URL`) |

- Admin may not set `min_flutter_macos14` / `min_macos` above the macos manifest's `version` (nor `min_flutter_windows` / `min_windows` above the windows manifest's): forcing an update to a version nobody can download would lock users out.

## File structure (Part A)

shellx repo:
- `relay/src/versions.ts` — add `PLATFORM_HEADER`, `OS_VERSION_HEADER`, `type Audience`, `audienceOf(platform?: string, osVersion?: string): Audience`.
- `relay/src/native-latest.ts` (new) — `readNativeLatest(dir: string, platform: "macos" | "windows", now: number): NativeLatest | null` with a 60 s cache and strict validation.
- `relay/src/settings.ts` — `MIN_VERSION_KEYS` gains `min_macos`, `min_windows`, `min_flutter_macos14`, `min_flutter_windows`; `versionAnswer(db, config, audience, latest): VersionBody`.
- `relay/src/config.ts` — `minMacos`, `minWindows` (env `MIN_MACOS`, `MIN_WINDOWS`), `nativeManifestDir` (env `NATIVE_MANIFEST_DIR`, default `/srv/downloads/desktop`).
- `relay/src/app.ts:85-95` — `/v1/version` uses `audienceOf` + `versionAnswer`.
- `relay/src/admin/app.ts`, `relay/admin/admin.js`, `relay/admin/index.html` — four new minimum fields with labels "Mac (bản mới)", "Windows (bản mới)", "Flutter trên macOS 14+", "Flutter trên Windows".
- `deploy/docker-compose.yml` — relay volume `./downloads/desktop:/srv/downloads/desktop:ro`; `deploy/relay.env` — `MIN_MACOS=2.0.0`, `MIN_WINDOWS=2.0.0`.
- `deploy/web/nginx.conf` — exact locations for `desktop/appcast.xml` and `desktop/latest-*.json` (no-cache, no attachment).
- `packages/shellx_core/lib/src/api/shellx_api.dart`, `apps/desktop/lib/src/platform/system_info.dart`, `apps/desktop/lib/src/agent/agent_side.dart:68,104`, `apps/desktop/lib/src/agent/ui_services.dart:37-38`, `apps/desktop/pubspec.yaml` — Flutter 1.0.1.
- `web/src/site.config.json`, `web/src/pages/index.astro` (+ `en/`), `web/src/pages/privacy.md`, `web/src/pages/terms.md` (+ `en/`) — download split and §12 wording.

fork (`lephus/shellx-pro`):
- `scripts/shellx/release/version.py` — read/resolve/bump the version (pbxproj `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`).
- `scripts/shellx/release/macos/{import-certificate.sh,notarize.sh,check-team.sh,make-dmg.sh}` — copied from the shellx repo `release/macos/` (the user's own code, relicensed into the GPL fork; header comment says so).
- `scripts/shellx/release/inject-sparkle.sh`, `scripts/shellx/release/make-appcast.sh`, `scripts/shellx/release/sparkle-ed25519.pub`, `scripts/shellx/release/write-latest.py`.
- `scripts/shellx/sign-and-notarize.sh` — add CI mode (API-key notarization, `--universal`), keep local mode unchanged.
- `Resources/Info.plist` — `SUEnableAutomaticChecks` → `true`.
- `.github/workflows/shellx-release.yml` (new); `.github/workflows/shellx-windows.yml` (L6's) gains `workflow_call` with input `version`.
- Tests: `tests/test_shellx_release.py` (+ entry in `tests/test-execution.toml`, lane `linux-guard`).

---

### Task A1: Relay answers `/v1/version` per platform (C15) and reads the native manifest

Skip condition: `git -C ~/Documents/myProjects/shellx log main --oneline -- relay/src | head` shows L4's C15 commit **and** `relay/test/versions.test.ts` already covers every row of the table below → only add the missing rows as tests, then go to A2.

**Files:**
- Modify: `relay/src/versions.ts`, `relay/src/settings.ts`, `relay/src/config.ts`, `relay/src/app.ts:85-95`, `deploy/relay.env`, `deploy/docker-compose.yml`, `deploy/tests/compose.test.mjs`
- Create: `relay/src/native-latest.ts`
- Test: `relay/test/versions.test.ts`, `relay/test/native-latest.test.ts`, `relay/test/app.test.ts`

**Interfaces:**
- Produces: `audienceOf(platform: string | undefined, osVersion: string | undefined): "native-macos" | "native-windows" | "flutter-macos-14" | "flutter-windows" | "legacy"`; `readNativeLatest(dir, platform, now): {version: string, url: string, sha256: string, minOs: string} | null`; `versionAnswer(db, config, audience, latest: {macos: NativeLatest | null, windows: NativeLatest | null}): {min_agent, min_mobile, latest_agent: {version, mac_url, win_url}}`. A10 and the admin UI (A1b) rely on the setting keys `min_macos`, `min_windows`, `min_flutter_macos14`, `min_flutter_windows`.

- [ ] **Step 1: Write the failing tests** — `versions.test.ts` table for `audienceOf`: `("flutter-macos","14.0")→flutter-macos-14`, `("flutter-macos","15.1.2")→flutter-macos-14`, `("flutter-macos","13.6")→legacy`, `("flutter-macos","abc")→legacy`, `("flutter-windows","10.0.22631")→flutter-windows`, `("macos","14.5")→native-macos`, `("windows",undefined)→native-windows`, `(undefined,undefined)→legacy`, `("FLUTTER-MACOS","14.0")→legacy` (exact match only). `native-latest.test.ts`: valid file → object; missing file → `null`; `version` not semver, `url` not starting `https://download.shellx.pro/desktop/<version>/`, extra size > 4 KB, or invalid JSON → `null` (and one `logMeta("native_latest_invalid")`); second read within 60 s does not touch the disk (inject a reader spy). `app.test.ts` `/v1/version`: with env `MIN_AGENT=1.0.0`, setting `min_flutter_macos14=2.0.0`, macos manifest 2.0.0 → `flutter-macos`/`15.0` gets `{min_agent:"2.0.0", latest_agent:{version:"2.0.0", mac_url:".../2.0.0/ShellX-2.0.0.dmg"}}`; `flutter-macos`/`13.6`, `flutter-windows`, and no headers each get `{min_agent:"1.0.0", latest_agent:{version:<LATEST_AGENT_VERSION>}}`; no manifest → `flutter-macos`/`15.0` gets legacy `latest_agent` and `min_agent` = `min_flutter_macos14`. `compose.test.mjs`: relay service has volume `./downloads/desktop:/srv/downloads/desktop:ro`.
- [ ] **Step 2: Run** `cd relay && npx vitest run test/versions.test.ts test/native-latest.test.ts test/app.test.ts` and `node --test deploy/tests/compose.test.mjs` — Expected: FAIL (`audienceOf is not a function`, missing volume).
- [ ] **Step 3: Implement** the functions above; OS major = integer before the first `.`; manifest cache keyed by platform with the injected `now`; `settings.ts` `minVersions` keeps returning `min_agent`/`min_mobile` for the admin page and the new keys fall back as in the K6 table; add `MIN_MACOS=2.0.0`, `MIN_WINDOWS=2.0.0` to `deploy/relay.env` and the volume to compose.
- [ ] **Step 4: Run** the same commands plus `npm test` and `npm run typecheck` in `relay/` — Expected: all PASS.
- [ ] **Step 5: Commit** on shellx `release/w3`: `git add relay deploy && git commit -m "feat(relay): /v1/version per platform from X-ShellX-Platform and the native latest manifest (C15)"`

### Task A1b: Admin per-platform minimum fields with the "downloadable" guard

Skip condition: L4 shipped equivalent admin fields (check `relay/admin/admin.js` for `min_flutter_macos14` or L4's key names).

**Files:**
- Modify: `relay/src/admin/app.ts:190-210`, `relay/admin/admin.js:12-13`, `relay/admin/index.html`
- Test: `relay/test/admin.test.ts`

**Interfaces:**
- Consumes: `MIN_VERSION_KEYS`, `readNativeLatest` (A1).
- Produces: `PUT /api/settings` accepts the four new keys; error code `min_not_downloadable` (HTTP 409) when the value exceeds the matching manifest version or the manifest is missing.

- [ ] **Step 1: Write the failing tests** — `PUT {"min_flutter_macos14":"2.0.0"}` with macos manifest 2.0.0 → 200 and `GET /api/settings` shows it; same with no manifest → 409 `min_not_downloadable`; `"2.0.1"` with manifest 2.0.0 → 409; `{"min_flutter_macos14": null}` → 200 (back to fallback); `{"min_macos":"02.0.0"}` → 400 (existing `isSettableVersion`).
- [ ] **Step 2: Run** `npx vitest run test/admin.test.ts` — Expected: FAIL.
- [ ] **Step 3: Implement** the guard in the settings PUT and four rows in `admin.js` (labels in Global Constraints of this Part's file structure; Vietnamese first, same widget as `min_agent`).
- [ ] **Step 4: Run** `npm test` — Expected: PASS. Open `npm run dev` → `http://admin.localhost:<port>` and check the four fields render and save (screenshot in the task report).
- [ ] **Step 5: Commit** `git commit -am "feat(admin): per-platform minimum versions, refused above the downloadable native version"`. Then **gate GA1**: merge `release/w3` → `main`, push; watch `deploy.yml` green; `curl -s -H 'X-ShellX-Platform: flutter-macos' -H 'X-ShellX-OS-Version: 15.0' https://relay.shellx.pro/v1/version` → legacy body (no manifest yet).

### Task A2: Flutter 1.0.1 sends platform and OS version

Skip condition: L4 put this change on a branch (ledger `## Sprint 2026-10-19 summary`, "Flutter 1.0.1 change") → review it against the tests below, add any missing test, merge that branch into `release/w3` instead.

**Files:**
- Modify: `packages/shellx_core/lib/src/api/shellx_api.dart:10-30,272-276`, `apps/desktop/lib/src/platform/system_info.dart`, `apps/desktop/lib/src/agent/agent_side.dart:68,104`, `apps/desktop/lib/src/agent/ui_services.dart:37-38`
- Test: `packages/shellx_core/test/api/shellx_api_test.dart`, `apps/desktop/test/platform/system_info_test.dart`

**Interfaces:**
- Produces: `const String clientPlatformHeader = 'X-ShellX-Platform'`, `const String clientOsVersionHeader = 'X-ShellX-OS-Version'`; `ShellxApi({required Uri baseUri, http.Client? httpClient, String? clientVersion, String? clientPlatform, String? clientOsVersion})`; `String flutterPlatformName()` (`'flutter-macos'` / `'flutter-windows'`); `String? normalizedOsVersion(String operatingSystemVersion, {required bool isMacOS})`.

- [ ] **Step 1: Write the failing tests** — `shellx_api_test.dart`: with `clientPlatform: 'flutter-macos', clientOsVersion: '14.5'` a `version()` call's request has both headers; with both null neither header is present (mobile keeps sending nothing new). `system_info_test.dart`: `normalizedOsVersion('Version 14.5 (Build 23F79)', isMacOS: true) == '14.5'`, `('Version 15.1.1 (Build 24B91)', true) == '15.1.1'`, `('Version 12.7.6 (Build 21H1320)', true) == '12.7.6'`, `('"Windows 10 Pro" 10.0 (Build 22631)', false) == '10.0.22631'`, `('garbage', true) == null`.
- [ ] **Step 2: Run** `cd packages/shellx_core && flutter test test/api/shellx_api_test.dart` and `cd apps/desktop && flutter test test/platform/system_info_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement**; headers are added in `_send` next to `clientVersionHeader`; desktop passes `flutterPlatformName()` and `normalizedOsVersion(Platform.operatingSystemVersion, isMacOS: Platform.isMacOS)` at the three `ShellxApi(` call sites. No other behaviour change.
- [ ] **Step 4: Run** the full suites: `flutter test` in `packages/shellx_core`, `apps/desktop`, `apps/mobile` — Expected: PASS (mobile unchanged).
- [ ] **Step 5: Commit** `git commit -am "feat(desktop): send X-ShellX-Platform and X-ShellX-OS-Version (1.0.1, C15)"`

### Task A3: Release Flutter 1.0.1 through the existing pipeline

**Files:**
- Modify: `apps/desktop/pubspec.yaml` (via `bump.mjs`), `apps/desktop/assets/whats_new.json` (no entry: 1.0.1 shows no card; `bump.mjs` warns, expected)

- [ ] **Step 1:** `node release/scripts/bump.mjs 1.0.1` → pubspec `version: 1.0.1+2`; `node --test release/tests/*.test.mjs` → PASS.
- [ ] **Step 2:** Run the three Flutter suites again → PASS. Commit `chore(desktop): 1.0.1`.
- [ ] **Step 3: Gate GA2.** On "go": merge `release/w3` → `main`, push. Watch **Actions → Release desktop**: `prepare` resolves `version=1.0.1 build=true`; macOS + Windows jobs green; `publish` lists both URLs; `announce` commits `deploy/relay.env` (`LATEST_AGENT_VERSION=1.0.1`); `deploy` green. `git pull`.
- [ ] **Step 4: Verify** `curl -s https://relay.shellx.pro/v1/version` → `latest_agent.version == "1.0.1"`; on the user's Mac with Flutter 1.0.0 the update notice appears; after updating, admin dashboard device list shows `1.0.1`. Record run id in the ledger (`## W3 release`).
- [ ] **Step 5 (optional, GA2):** user sets `min_agent = 1.0.1` on admin.shellx.pro.

### Task A4: Fork version file, bump and resolve scripts

**Files:**
- Create: `scripts/shellx/release/version.py`, `tests/test_shellx_release.py`
- Modify: `tests/test-execution.toml` (lane `linux-guard`)

**Interfaces:**
- Produces (CLI, used by A6): `python3 scripts/shellx/release/version.py current` → prints `2.0.0 <build>`; `version.py bump X.Y.Z` → sets every `MARKETING_VERSION = X.Y.Z;` and `CURRENT_PROJECT_VERSION = <old+1>;` in `cmux.xcodeproj/project.pbxproj`, refuses `X.Y.Z` ≤ the version in `https://download.shellx.pro/desktop/latest-macos.json` (404 = nothing released) and refuses < 2.0.0; `version.py resolve --event <push|workflow_dispatch> --ref <name> --dry-run <true|false>` → writes `version=`, `build_number=`, `dry_run=`, `build=` (`false` when `desktop/<v>/ShellX-<v>.dmg` answers 200) to `$GITHUB_OUTPUT`; a real release off `main` is an error; a dmg answering anything other than 200/404 is an error.

- [ ] **Step 1: Write the failing tests** (`unittest`, network stubbed by injecting a `fetch_status(url) -> int` and `fetch_json(url)`): bump on a fixture pbxproj with three configurations changes all three `MARKETING_VERSION` and increments `CURRENT_PROJECT_VERSION`; bump `1.9.0` → error "native versions start at 2.0.0"; bump `2.0.0` when latest is `2.0.0` → error; resolve push on `main` + dmg 404 → `build=true dry_run=false`; dmg 200 → `build=false`; push on `shellx/x` → error; dispatch with dry-run true anywhere → `dry_run=true build=true`; dmg 503 → error.
- [ ] **Step 2: Run** `python3 tests/test_shellx_release.py` — Expected: FAIL (module missing).
- [ ] **Step 3: Implement** `version.py` (stdlib only: `argparse`, `re`, `urllib.request`, `json`).
- [ ] **Step 4: Run** the test and `python3 scripts/verify-local.py --all` — Expected: PASS.
- [ ] **Step 5: Commit** on fork `shellx/w3-release`: `feat(shellx): release version file, bump and resolve (pbxproj is the version source)`.

### Task A5: Sparkle feed, EdDSA public key, appcast and latest manifest

**Files:**
- Modify: `Resources/Info.plist` (`SUEnableAutomaticChecks` → `true`; `SUFeedURL` stays `https://download.shellx.pro/desktop/appcast.xml` from W1)
- Create: `scripts/shellx/release/sparkle-ed25519.pub` (the user's public key from GA0), `scripts/shellx/release/inject-sparkle.sh`, `scripts/shellx/release/make-appcast.sh`, `scripts/shellx/release/write-latest.py`
- Test: `tests/test_shellx_release.py`

**Interfaces:**
- Produces: `inject-sparkle.sh <app> <pubkey-file>` (PlistBuddy sets `SUPublicEDKey` and re-asserts `SUFeedURL`; if `SPARKLE_PRIVATE_KEY` is set, derives the public key with `scripts/derive_sparkle_public_key.swift` and fails on mismatch with the committed one — catches a wrong secret before anything is signed); `make-appcast.sh <dmg> <version>` → `dist/appcast.xml` via `scripts/sparkle_generate_appcast.sh` with `DOWNLOAD_URL_PREFIX=https://download.shellx.pro/desktop/<v>/`, `RELEASE_NOTES_URL=https://github.com/lephus/shellx-pro/releases/tag/shellx-v<v>`, then asserts `sparkle:edSignature`, `sparkle:minimumSystemVersion>14.0<` (adds it if absent) and the enclosure URL; `write-latest.py <dmg> <version> <platform>` → `dist/latest-<platform>.json` (K6 shape).

- [ ] **Step 1: Write the failing tests** — Info.plist: `SUFeedURL == "https://download.shellx.pro/desktop/appcast.xml"`, `SUEnableAutomaticChecks is True`, `SUSendProfileInfo is False`; `sparkle-ed25519.pub` is 44 base64 chars decoding to 32 bytes; `write-latest.py` on a fixture file gives the exact K6 keys, `url` = `https://download.shellx.pro/desktop/2.0.0/ShellX-2.0.0.dmg`, correct sha256; `make-appcast.sh` and `inject-sparkle.sh` exist, are executable, and contain no `manaflow` or `github.com/manaflow-ai` string.
- [ ] **Step 2: Run** `python3 tests/test_shellx_release.py` — Expected: FAIL.
- [ ] **Step 3: Implement.** Stop and ask the lead if GA0 has not delivered the public key (do not generate one yourself).
- [ ] **Step 4: Run** the test → PASS. On the Mac, smoke `make-appcast.sh` against any local dmg with a throwaway key generated in `$TMPDIR` (`SPARKLE_PRIVATE_KEY` from that throwaway, never the real one) → `dist/appcast.xml` has an `edSignature`.
- [ ] **Step 5: Commit** `feat(shellx): Sparkle feed on download.shellx.pro with EdDSA key, appcast and latest manifest scripts`.

### Task A6: `shellx-release.yml` — prepare, preflight, build and sign the Mac app

**Files:**
- Create: `.github/workflows/shellx-release.yml`, `scripts/shellx/release/macos/*` (copied, see File structure)
- Modify: `scripts/shellx/sign-and-notarize.sh` (CI mode)
- Test: `tests/test_shellx_release.py` (workflow lint)

**Interfaces:**
- Consumes: `version.py resolve` (A4), `inject-sparkle.sh`, `make-appcast.sh`, `write-latest.py` (A5).
- Produces: artifacts `shellx-macos` = `ShellX-<v>.dmg`, `appcast.xml`, `latest-macos.json`; job outputs `version`, `dry_run`, `build`.
- `sign-and-notarize.sh` additions: `--build --universal` (`ARCHS="arm64 x86_64"`, `ONLY_ACTIVE_ARCH=NO`; drop `SWIFT_OPTIMIZATION_LEVEL=-Onone` and `ENABLE_DEBUG_DYLIB=NO` now that fork `122037ee4d` fixed the SIL crash — keep them only behind `SHELLX_ONONE=1`); notarization uses `SHELLX_NOTARY_KEY_PATH` + `SHELLX_NOTARY_KEY_ID` + `SHELLX_NOTARY_ISSUER` when set, else `--keychain-profile`.

Workflow shape (decisions; the implementer writes the YAML):
- `on: push: branches: [main]` with `paths-ignore: ['docs/**','**/*.md','spikes/**']`, and `workflow_dispatch` input `dry_run` (default `true`). `permissions: contents: read`. Concurrency group `shellx-release` (dry runs: own group per run id), never cancel in progress.
- `prepare` (ubuntu-latest): `version.py resolve`.
- `preflight` (ubuntu-latest, `environment: release`, only when `build && !dry_run`): same "secret set / missing / is a variable" check as shellx `release-desktop.yml:66-123`, plus `SPARKLE_PRIVATE_KEY`.
- `macos` (`macos-26`, `environment: release`, timeout 120): checkout with submodules; Zig 0.16.0; GhosttyKit built locally (`CMUX_GHOSTTYKIT_NO_PREBUILT=1`, cache keyed on the ghostty submodule sha + `scripts/ghosttykit-checksums.txt`) — releases never download Manaflow's prebuilt; `sign-and-notarize.sh --build --universal` → app; check `CFBundleShortVersionString == version`, `CFBundleIdentifier == pro.shellx.desktop`, `LSMinimumSystemVersion == 14.0`, `lipo -archs` of the main executable has `arm64 x86_64`; `inject-sparkle.sh` **before** signing; real: `import-certificate.sh` → `sign-and-notarize.sh <app>` (inside-out signer + notarize + staple + spctl) → `check-team.sh`; dry run: `codesign --force --deep --sign -`; `make-dmg.sh` → real: sign + notarize + staple the dmg; real: `make-appcast.sh` + `write-latest.py`; upload artifact; always delete keychain and key files.
- If the universal build fails on x86_64 only, the fallback is `ARCHS=arm64` plus `sparkle:minimumSystemVersion` unchanged and a note in the ledger and on the download page ("Apple silicon"); the user decides at GA3.

- [ ] **Step 1: Write the failing workflow lint test** (parse YAML with a tiny stdlib-only indentation reader or `yaml` if present in the runner image; otherwise regex): jobs `prepare`, `preflight`, `macos`, `windows`, `publish` exist; `macos` and `preflight` declare `environment: release`, `publish` declares `environment: production`; `publish.if` contains `github.ref == 'refs/heads/main'` and `dry_run == 'false'`; no `secrets.` reference outside jobs that declare an environment; `actions/*` pinned by full sha; the string `inject-sparkle.sh` appears before `sign-and-notarize.sh <` in `macos` steps; no `manaflow` URL.
- [ ] **Step 2: Run** `python3 tests/test_shellx_release.py` — Expected: FAIL.
- [ ] **Step 3: Implement** the workflow (`windows`/`publish` as stubs that A7 fills) and the script CI mode; keep the local mode byte-identical in behaviour (`sign-and-notarize.sh --build` with no flags still builds arm64 like W0).
- [ ] **Step 4: Run** the test → PASS; push `shellx/w3-release`; **Actions → ShellX release → Run workflow** on `shellx/w3-release` with `dry_run` checked → `macos` green, artifact `shellx-macos` has a dmg that mounts and contains `ShellX.app` with `SUFeedURL` and `SUPublicEDKey` set.
- [ ] **Step 5: Commit** `ci(shellx): release workflow — build, Sparkle inject, sign, notarize, dmg, appcast`.

### Task A7: Publish to `download.shellx.pro`, Windows installer, GitHub release for GPL source

**Files:**
- Modify: `.github/workflows/shellx-release.yml` (`windows`, `publish`), `.github/workflows/shellx-windows.yml` (add `workflow_call` with input `version`, installer named `ShellX-Setup-<version>.exe`)
- Modify (shellx repo, `release/w3`): `deploy/web/nginx.conf`, `deploy/tests/` nginx test (or a new `deploy/tests/nginx.test.mjs`)
- Test: `tests/test_shellx_release.py`

**Interfaces:**
- Consumes: artifacts from A6; repo variable `SHELLX_WINDOWS_CHANNEL` ∈ `off` (default) | `upload` | `announce`.
- Produces: on the VPS `downloads/desktop/<v>/ShellX-<v>.dmg`, optional `ShellX-Setup-<v>.exe`, then `downloads/desktop/appcast.xml`, `downloads/desktop/latest-macos.json` (and `latest-windows.json` only with `announce`); fork tag `shellx-v<v>` + GitHub release whose notes link the source (`https://github.com/lephus/shellx-pro/tree/shellx-v<v>`), `LICENSE`, `THIRD_PARTY_LICENSES`, and the dmg URL.

Decisions:
- Upload with rsync only (the VPS key is `rrsync -wo` restricted: no shell commands): `rsync -t --mkpath --chmod=D755,F644 dist/ShellX-<v>.dmg vps:<v>/` (paths are relative to the rrsync root `~/phu/shellx/downloads/desktop`). Refuse to overwrite by HTTPS HEAD first, as shellx `release-desktop.yml:373-385`. Verify size over HTTPS. **Only then** rsync `appcast.xml` and `latest-macos.json` (rsync writes a temp name and renames: atomic). Sparkle and the relay therefore never point at a file that is not served yet.
- nginx (shellx repo): `location = /desktop/appcast.xml` and `location ~ ^/desktop/latest-(macos|windows)\.json$` with `Cache-Control: no-cache`, no `Content-Disposition`, `X-Content-Type-Options: nosniff`, types `application/xml` / `application/json`; everything else keeps the immutable rule.
- Tag + release with `GITHUB_TOKEN` (`permissions: contents: write` on that job only), best effort like shellx `announce`.

- [ ] **Step 1: Write the failing tests** — fork lint: `publish` rsyncs the dmg before `appcast.xml`/`latest-macos.json`; `publish` has the HEAD refusal; `windows` runs only when `vars.SHELLX_WINDOWS_CHANNEL` is `upload` or `announce`; `latest-windows.json` written only for `announce`. shellx repo nginx test: the config text has the two exact locations with `no-cache` and the `location /` block still has `immutable` and `attachment`.
- [ ] **Step 2: Run** both tests — Expected: FAIL.
- [ ] **Step 3: Implement** both sides.
- [ ] **Step 4: Run** tests → PASS; `docker run --rm -v $PWD/deploy/web/nginx.conf:/etc/nginx/conf.d/default.conf:ro nginx:alpine nginx -t` → `syntax is ok`. Dry run on the fork branch: `publish` is skipped (dry run), `windows` runs when the variable is set on a test run.
- [ ] **Step 5: Commit** fork `ci(shellx): publish installers then appcast and manifest to download.shellx.pro; GPL source release`; shellx `feat(web): no-cache appcast and native latest manifests on download.shellx.pro`. The nginx change rides the next shellx `main` push (GA1 or GA2 — whichever comes after it is ready; it must be live before GA3).

### Task A8: End-to-end dry run from fork `main` state

- [ ] **Step 1:** Merge `shellx/sprint` (or fork `main` after the sprint close) into `shellx/w3-release`; `version.py bump 2.0.0` if `MARKETING_VERSION` is not already `2.0.0`; `python3 scripts/verify-local.py --all` → PASS.
- [ ] **Step 2:** Dispatch `ShellX release` on `shellx/w3-release`, `dry_run` checked → green; download `shellx-macos`.
- [ ] **Step 3:** Local checks on the dmg's app: `codesign -dv` (ad-hoc), `PlistBuddy` `SUFeedURL`/`SUPublicEDKey`/`LSMinimumSystemVersion`, `lipo -archs`, launch from `/private/tmp` (TCC note in the ledger) with the Flutter app quit (bundle id collision, ledger Signing).
- [ ] **Step 4: Gate GA3** — hand the dmg to the user for the 10-minute smoke. Record result in the ledger.

### Task A9: Release ShellX Mac 2.0.0

- [ ] **Step 1:** On "go" (GA3): fast-forward fork `main` to `shellx/w3-release`, push. Approve the `release` Environment review.
- [ ] **Step 2:** Watch: `prepare` `version=2.0.0 build=true`; `macos` (notarization accepted, stapled); `publish` (dmg 200 with matching size, then appcast + manifest); tag `shellx-v2.0.0` + release.
- [ ] **Step 3: Verify** `curl -sI https://download.shellx.pro/desktop/appcast.xml` → `200`, `cache-control: no-cache`, no `content-disposition`; `curl -s https://download.shellx.pro/desktop/latest-macos.json` → version `2.0.0`; downloaded dmg: `spctl -a -vv -t open --context context:primary-signature ShellX-2.0.0.dmg` → `accepted`, `source=Notarized Developer ID`; `curl -s -H 'X-ShellX-Platform: flutter-macos' -H 'X-ShellX-OS-Version: 15.0' https://relay.shellx.pro/v1/version` → `latest_agent.version == "2.0.0"` with the native `mac_url`, `min_agent` still the legacy value; the same with `13.6` → legacy `latest_agent`.
- [ ] **Step 4: Gate GA4** (user clean-Mac install + Check for Updates).
- [ ] **Step 5:** Ledger `## W3 release`: run id, notarization ids, sha256, URLs.

### Task A10: Force Flutter-on-macOS-14+ users onto 2.0.0

- [ ] **Step 1:** User (GA4) sets "Flutter trên macOS 14+" = `2.0.0` on admin.shellx.pro (the A1b guard accepts it because the manifest says 2.0.0).
- [ ] **Step 2: Verify** with curl: `flutter-macos`/`15.0` → `min_agent "2.0.0"`; `flutter-macos`/`13.6`, `flutter-windows`, and no headers → unchanged `min_agent`; `macos`/`14.5` → `min_agent "2.0.0"` (no force for 2.0.0 itself).
- [ ] **Step 3:** On a Mac with Flutter 1.0.1 (macOS 14+): within one update check the "Cần cập nhật" screen opens the native dmg URL; after install the native app signs in with the old account and re-pairs (spec §11). Record in the ledger.

### Task A11: Website download split and §12 wording

**Files:**
- Modify: `web/src/site.config.json` (`nativeMacVersion: "2.0.0"`, `nativeMacUrl`), `web/src/pages/index.astro` and `web/src/pages/en/index.astro` (Mac button → native dmg, sub-line "macOS 14 trở lên · bản cho macOS 12–13: ShellX 1.0.1" linking the Flutter dmg; Windows unchanged), `web/src/pages/privacy.md`, `web/src/pages/terms.md` and `en/` twins (open source GPL-3.0 with source link, relay v2 sees only ciphertext, share links with the key in the `#` part, no telemetry)
- Test: `web/tests/site.test.mjs`

- [ ] **Step 1: Write the failing tests** — config has `nativeMacUrl` = `https://download.shellx.pro/desktop/2.0.0/ShellX-2.0.0.dmg`; both home pages link it and still link the Flutter `ShellX-1.0.1.dmg`; privacy pages (vi + en) mention `GPL-3.0`, `github.com/lephus/shellx-pro`, and `relay` + "không" telemetry wording (exact phrases fixed in the test from the page text you write).
- [ ] **Step 2: Run** `cd web && npm test` (after `npm run build`) — FAIL.
- [ ] **Step 3: Implement**; `announce.mjs` is untouched (it still manages the Flutter `desktopVersion`).
- [ ] **Step 4: Run** `npm run build` (includes tests) → PASS; `npm run lighthouse` stays 4×100 on the home page.
- [ ] **Step 5: Commit** `feat(web): ShellX 2.0.0 for macOS 14+, Flutter 1.0.1 for older Macs; privacy and terms for open source, relay v2 and share links`; ships with the next shellx `main` push (user "go").

## Rollback (Part A)

| Problem | Do this | Never |
| --- | --- | --- |
| Bad relay per-platform answer after GA1 | **Actions → Deploy → Run workflow** with the previous `main` sha (`deploy.yml` input `ref`); the admin overrides stay in SQLite and are ignored by the old code. | edit the DB by hand |
| Flutter 1.0.1 broken | Release `1.0.2` (`bump.mjs 1.0.2`, push). If `min_agent` was raised to 1.0.1, set it back to `1.0.0` on admin first. | overwrite the 1.0.1 files |
| Mac 2.0.0 broken, found before GA4 | On the VPS (user, or a one-off rsync from the fork with `--delete` disabled): replace `desktop/appcast.xml` with an empty-channel feed (agent prepares the file) and `rm desktop/latest-macos.json`. New installs stop being offered by the relay and by Sparkle; the dmg stays (immutable URL) but is no longer linked. Fix → `2.0.1`. | delete or replace `ShellX-2.0.0.dmg` |
| Mac 2.0.0 broken after GA4 (Flutter users already forced) | First: admin → "Flutter trên macOS 14+" → empty (back to fallback) — immediate on the next check. Then as above. Users already on 2.0.0 get `2.0.1` through Sparkle. | raise `min_macos` above a version that is not out |
| Sparkle key leaked or lost | Generate a new key; ship `2.0.x` signed with the **old** key whose Info.plist carries the new public key (Sparkle key rotation), then switch the secret. If the old private key is lost, existing installs cannot auto-update: announce a manual download on shellx.pro and raise `min_macos` so the force-update screen links the dmg. | publish an appcast signed with a key the installed apps do not trust |
| `publish` failed half-way | Same as shellx `release/README.md` "When something goes wrong": the next push (or **Re-run failed jobs**) retries because the dmg is still 404, or stops with "already published" if it went through; the appcast/manifest are written last, so a half run never announces. | — |
