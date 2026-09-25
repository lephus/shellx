# ShellX v1.0 — Kế hoạch 06: Website `shellx.pro`, CI và phát hành desktop

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dựng website tĩnh song ngữ `shellx.pro` (trang chủ có link tải, chính sách quyền riêng tư, điều khoản sử dụng), workflow CI chạy toàn bộ bộ test của dự án, và pipeline phát hành desktop (dmg đã ký + notarize, bộ cài Windows đã ký) tải lên R2 tại `download.shellx.pro`.

**Architecture:** `web/` là site Astro 7 xuất HTML tĩnh; mọi link tải và link cửa hàng đọc từ một file `web/src/site.config.json`; `npm run build` chạy `astro build` rồi bộ kiểm tra `node:test` trên `dist/`. `.github/workflows/ci.yml` dùng `dorny/paths-filter` để chỉ chạy các job liên quan tới phần thay đổi; mỗi job gọi đúng lệnh test chuẩn của overview §3. `release/` chứa các script phát hành nhỏ có test; `.github/workflows/release-desktop.yml` điều phối chúng: `prepare` (chọn phiên bản) → `macos` + `windows` song song → `publish` (Wrangler → R2), job cuối chỉ chạy khi cả hai job build thành công và không phải dry run.

**Tech Stack:** Astro 7.3.5 (Node ≥ 22.12), `node:test`; GitHub Actions (`actions/checkout@v7`, `actions/setup-node@v7`, `subosito/flutter-action@v2`, `dorny/paths-filter@v4`, `actions/upload-artifact@v7`, `actions/download-artifact@v8`, `azure/artifact-signing-action@v2`); Flutter 3.41.7; `codesign`/`notarytool`/`stapler`/`hdiutil` của Xcode; Inno Setup 6; Wrangler 4.139.0; actionlint 1.7.12; shellcheck 0.11.0.

**Spec:** `docs/superpowers/specs/2026-09-25-shellx-v1-design.md` (§3, §4.2, §5, §6.3, §8.5, §10, §11, §13, §14)

**Overview:** `docs/superpowers/plans/2026-09-25-shellx-v1-00-overview.md` (§2 Global Constraints, §3 lệnh test chuẩn, §4.3 JSON của `/v1/version`)

---

## Global Constraints

Mọi mục ở **overview §2** áp dụng nguyên văn. Các giá trị riêng của plan này (trích từ spec/overview):

- Landing: "Astro, xuất trang tĩnh, triển khai trên Cloudflare Pages tại `shellx.pro`"; "trang chủ đơn giản có link tải (macOS, Windows, App Store, Google Play), `/privacy`, `/terms`, song ngữ Việt/Anh" (spec §11). Tiếng Việt mặc định tại `/`, tiếng Anh dưới `/en/`.
- Mobile trên App Store và Google Play "trỏ tới `https://shellx.pro/privacy`" (spec §14) → URL này phải mở được chính sách (Cloudflare Pages chuyển hướng `/privacy` → `/privacy/`).
- Bản cài desktop: "tải lên R2 theo đường dẫn `desktop/<version>/…`, phục vụ qua `download.shellx.pro`" (spec §14); tên file đúng như overview §4.3: `desktop/<v>/ShellX-<v>.dmg` và `desktop/<v>/ShellX-Setup-<v>.exe`.
- macOS: "`.dmg`, ký Developer ID, notarize bằng `notarytool`" (spec §14); "Phát hành ngoài Mac App Store (sandbox không cho spawn shell), ký Developer ID, notarize, bật hardened runtime, không bật App Sandbox" (spec §8.5).
- Windows: "bộ cài Inno Setup `.exe`, ký code (chứng chỉ OV hoặc Azure Trusted Signing)" (spec §14) — plan này dùng Azure Trusted Signing, nay Microsoft gọi là *Artifact Signing*. Windows 10 bản 1809+ (spec §3.1). "shell chạy với quyền người dùng thường. Không hỗ trợ lệnh cần UAC" (spec §8.5) → bộ cài per-user, không đòi quyền admin.
- CI: "test Dart packages, test relay, test tích hợp desktop trên `macos-latest` và `windows-latest`, test widget mobile, test end-to-end" (spec §14), dùng đúng lệnh test chuẩn ở overview §3.
- Phiên bản đã xác minh ngày 2026-09-25: Flutter **3.41.7** (stable, Dart 3.11.5, trùng máy dev; bản vá 3.41 mới nhất là 3.41.9); Node **22** trong CI (Astro 7.3.5 yêu cầu `node >=22.12.0`); Wrangler **4.139.0**; actionlint **1.7.12**; shellcheck **0.11.0**. Action: `actions/checkout@v7` (v7.0.1), `actions/setup-node@v7` (v7.0.0), `subosito/flutter-action@v2` (v2.23.0), `dorny/paths-filter@v4` (v4.0.3), `actions/upload-artifact@v7` (v7.0.1), `actions/download-artifact@v8` (v8.0.1), `azure/artifact-signing-action@v2` (v2.0.0; repo cũ `azure/trusted-signing-action` đã đổi tên thành repo này). `windows-latest` = Windows Server 2025 + Visual Studio 2026 (Flutter 3.41.7 hỗ trợ generator "Visual Studio 18 2026"), có sẵn Inno Setup 6.7.1; `macos-latest` = macOS 26 arm64.
- Dữ liệu mà chính sách quyền riêng tư phải mô tả đúng (spec §3.2, §5.1–5.3, §6.3, §10.3, §10.5): email (đã chuyển chữ thường); mật khẩu chỉ lưu dạng băm argon2id; `created_at`, `password_changed_at`; thiết bị `{kind, name, platform, public_key (X25519), created_at, last_seen_at}`; token chỉ lưu SHA-256, hết hạn sau 90 ngày không dùng, đổi mật khẩu thu hồi token của mọi thiết bị khác; bản ghi ghép nối `{agent_id, mobile_id, created_at}` chỉ để hiển thị; IP dùng tạm cho rate limit chu kỳ 60 s; log chỉ siêu dữ liệu, "Không bao giờ ghi payload, token hay mật khẩu"; nội dung terminal mã hóa đầu cuối bằng Noise, relay không đọc được, không biết cả số tab; bộ đệm 256 KiB mỗi phiên chỉ nằm trên máy tính; không push notification, không analytics; xóa tài khoản ngay trong app mobile (spec §5.2 đã sửa: Cài đặt → "Xóa tài khoản"/"Delete account", nhập lại mật khẩu, relay `DELETE /v1/account` xóa người dùng cùng thiết bị, token, ghép nối và đóng WebSocket mọi thiết bị với 4002; agent xử lý như đăng xuất), dự phòng qua email `support@shellx.pro`.
- Website không dùng cookie, không tải script/stylesheet/iframe của bên thứ ba (chính sách quyền riêng tư cam kết điều này).
- Không làm nội dung marketing: "Nội dung marketing của landing page (spec riêng)" nằm ngoài phạm vi (spec §3.2).

**Hợp đồng lấy từ plan khác.** Plan 06 chỉ *gọi* những thứ sau; nếu plan chủ sở hữu làm khác, sửa plan đó hoặc sửa đúng dòng tương ứng ở plan này.

| Plan | Điều plan 06 dựa vào |
|---|---|
| 01 relay | Theo overview §4.3 ("Relay dev server"): `relay/package.json` có script `test` (Vitest) và `dev`; `npm run dev -- --ip 127.0.0.1 --port 8787` áp dụng migration D1 cục bộ rồi phục vụ tại `http://127.0.0.1:8787`, với `RATE_LIMITS_ENABLED = "false"` ở môi trường dev (E2E tạo nhiều tài khoản từ cùng IP, nên CI không cần xử lý gì thêm); `GET /v1/version` trả 200 khi chạy dev; cấu hình ở `relay/wrangler.jsonc`, các biến phiên bản `MIN_AGENT`, `MIN_MOBILE`, `LATEST_AGENT_VERSION`, `MAC_URL`, `WIN_URL` nằm trong `vars` của môi trường production; `relay/package-lock.json` được commit |
| 02, 03 | `dart test` chạy được trong `packages/shellx_core`, `packages/shellx_agent`, `packages/shellx_client`, `packages/shellx_e2e` sau `flutter pub get` ở gốc workspace; `shellx_e2e` đọc `SHELLX_E2E_RELAY` |
| 04 desktop | `apps/desktop/pubspec.yaml` có dòng `version: X.Y.Z+N`; `flutter build macos --release` sinh `build/macos/Build/Products/Release/ShellX.app` với bundle id `pro.shellx.desktop`; `flutter build windows --release` sinh `build/windows/x64/runner/Release/ShellX.exe`; `apps/desktop/macos/Runner/Release.entitlements` **không** bật `com.apple.security.app-sandbox`; `apps/desktop/windows/runner/resources/app_icon.ico` tồn tại; `launch_at_startup` đăng ký giá trị Run tên `ShellX`; có `test/` và `integration_test/` |
| 05 mobile | `apps/mobile` có `test/` chạy bằng `flutter test`; app id `pro.shellx.mobile` (link Google Play `https://play.google.com/store/apps/details?id=pro.shellx.mobile`); màn Cài đặt có "Xóa tài khoản" / "Delete account" mà chính sách quyền riêng tư mô tả |

## Review Focus

Năm tình huống spec ngụ ý nhưng dễ bị bỏ sót, xếp theo khả năng làm hại người dùng. Mỗi dòng có kiểm tra ở task sở hữu.

1. **Nút "Tải cho macOS/Windows" trả 404** — tên file trên web lệch với tên file mà release tải lên, hoặc `desktopVersion` được tăng trước khi bản cài có trên R2. Người dùng mong bấm là tải được. Kiểm tra: Task 1 (test dựng URL từ config theo đúng mẫu `ShellX-<v>.dmg` / `ShellX-Setup-<v>.exe`; test `CHECK_DOWNLOADS=1` gửi HEAD thật), Task 6 (`publish` kiểm tra URL công khai và kích thước file sau khi tải lên; README bắt chạy `CHECK_DOWNLOADS=1` trước khi bump web).
2. **Bản cài mang phiên bản khác `apps/desktop/pubspec.yaml`** — agent tự báo phiên bản cũ nên thông báo "có bản mới" (spec §14) không bao giờ tắt dù người dùng đã cập nhật. Kiểm tra: Task 3 (tag khác pubspec → dừng; tag sai định dạng → dừng; phát hành thật từ nhánh → dừng).
3. **Cài bản mới hoặc gỡ cài đặt khi agent đang chạy ở tray** — exe/DLL bị khóa làm cài hỏng, hoặc gỡ xong vẫn còn mục "khởi động cùng Windows" trỏ tới exe đã xóa. Kiểm tra: Task 5 (test cho `taskkill` trong `PrepareToInstall` và `[UninstallRun]`, `RegDeleteValue` cho `HKCU\…\Run\ShellX`); Task 7 (job CI biên dịch `.iss` thật trên Windows).
4. **Gatekeeper chặn app macOS, hoặc agent không mở được shell** — dylib/framework lồng bên trong thiếu hardened runtime + timestamp làm notarization từ chối; entitlements bật App Sandbox làm agent không spawn được shell. Kiểm tra: Task 4 (test ký ad-hoc kiểm cờ `runtime` trên code lồng; test từ chối entitlements bật sandbox).
5. **Người duyệt store hoặc người dùng mở `https://shellx.pro/privacy` (không có `/` cuối) hay gõ sai đường dẫn** — phải tới đúng chính sách, và đường dẫn sai phải là 404 thật chứ không phải trang chủ với mã 200 (Cloudflare Pages coi site không có `404.html` là SPA). Kiểm tra: Task 2 (test `dist/404.html`; test mọi link nội bộ trỏ tới file có thật; README có lệnh `curl` xác minh sau khi deploy).

Plan còn kiểm thêm: chính sách quyền riêng tư không thành sai sự thật khi ai đó thêm script bên thứ ba (Task 2); Wrangler 4 lặng lẽ ghi vào bucket giả lập cục bộ nếu thiếu `--remote` (Task 6 kiểm URL công khai sau khi tải lên); 404 bị Cloudflare cache làm bước kiểm tra sau upload thất bại (Task 6 dùng query string riêng cho mỗi lần chạy).

---

## Cấu trúc file

```
web/
  package.json, package-lock.json, .gitignore, .node-version, astro.config.mjs, tsconfig.json
  README.md                       # lệnh, cấu hình link, deploy Cloudflare Pages, URL cho store
  public/favicon.svg
  src/site.config.json            # NGUỒN DUY NHẤT: desktopVersion, link store, email hỗ trợ
  src/lib/site.ts                 # dựng URL bản cài từ config
  src/i18n/ui.ts                  # chuỗi vi/en, đường dẫn từng trang theo ngôn ngữ
  src/layouts/Base.astro          # khung HTML, header (đổi ngôn ngữ), footer (privacy/terms/email)
  src/layouts/Legal.astro         # layout cho các trang pháp lý viết bằng Markdown
  src/components/Home.astro, src/components/Downloads.astro
  src/pages/index.astro, src/pages/en/index.astro, src/pages/404.astro
  src/pages/privacy.md, src/pages/terms.md, src/pages/en/privacy.md, src/pages/en/terms.md
  tests/site.test.mjs             # kiểm tra dist/ sau khi build
release/
  README.md                       # secrets, thiết lập thủ công, quy trình phát hành
  scripts/version.mjs, scripts/resolve-version.mjs
  macos/import-certificate.sh, macos/sign-app.sh, macos/notarize.sh, macos/make-dmg.sh
  windows/shellx.iss, windows/build-installer.ps1
  tests/version.test.mjs, tests/macos-scripts.test.mjs, tests/inno.test.mjs
.github/workflows/
  ci.yml
  release-desktop.yml
```

Task 1–2 (web) độc lập với Task 3–7. Task 6 dùng file của Task 3–5. Task 7 chạy test của Task 3–5 và `build-installer.ps1`. Task 4 phải chạy trên macOS.

**Công cụ lint dùng ở Task 4, 6, 7** — tải vào thư mục tạm, không cài vào hệ thống, chạy lại nhiều lần được (macOS hoặc Linux):

```bash
TOOLS="${TMPDIR:-/tmp}/shellx-tools"; mkdir -p "$TOOLS"
test -x "$TOOLS/shellcheck" || curl -sSfL "https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.$(uname -s | tr '[:upper:]' '[:lower:]').$(uname -m | sed 's/arm64/aarch64/').tar.xz" | tar -xJ --strip-components=1 -C "$TOOLS" shellcheck-v0.11.0/shellcheck
test -x "$TOOLS/actionlint" || bash <(curl -sSfL https://raw.githubusercontent.com/rhysd/actionlint/v1.7.12/scripts/download-actionlint.bash) 1.7.12 "$TOOLS"
```

---

### Task 1: Website — khung Astro, trang chủ song ngữ và link tải

**Files:**
- Create: `web/package.json`, `web/package-lock.json` (npm sinh ra), `web/.gitignore`, `web/.node-version`, `web/astro.config.mjs`, `web/tsconfig.json`, `web/public/favicon.svg`
- Create: `web/src/site.config.json`, `web/src/lib/site.ts`, `web/src/i18n/ui.ts`
- Create: `web/src/layouts/Base.astro`, `web/src/components/Downloads.astro`, `web/src/components/Home.astro`, `web/src/pages/index.astro`, `web/src/pages/en/index.astro`
- Test: `web/tests/site.test.mjs`

**Interfaces:**
- Consumes: không có.
- Produces:
  - `web/src/site.config.json` = `{desktopVersion: "x.y.z", downloadBaseUrl: "https://download.shellx.pro/desktop", appStoreUrl: string | null, googlePlayUrl: string | null, supportEmail: "support@shellx.pro"}`. `null` ở link store hiển thị "Sắp ra mắt" / "Coming soon". README của Task 6 hướng dẫn bump `desktopVersion`.
  - Mẫu URL bản cài (phải khớp Task 6): `${downloadBaseUrl}/${v}/ShellX-${v}.dmg`, `${downloadBaseUrl}/${v}/ShellX-Setup-${v}.exe`.
  - `src/i18n/ui.ts`: `type Lang = 'vi' | 'en'`, `type Page = 'home' | 'privacy' | 'terms'`, `pathFor(lang: Lang, page: Page): string` (`/`, `/privacy/`, `/terms/`, `/en/`, `/en/privacy/`, `/en/terms/`), `otherLang(lang: Lang): Lang`, `ui: Record<Lang, Strings>` (có các khóa `privacy`, `terms`, `lastUpdated`, `notFoundTitle`, `notFoundBody`, `backHome` dùng ở Task 2).
  - `src/layouts/Base.astro` props `{lang: Lang; page: Page | null; title: string; description: string}`; footer luôn có link `pathFor(lang, 'privacy')`, `pathFor(lang, 'terms')`, `mailto:<supportEmail>`; header có link sang trang tương ứng ở ngôn ngữ kia.
  - `web/tests/site.test.mjs` có các helper cấp module (không export) mà Task 2 dùng lại khi nối thêm test vào cuối cùng file: `root`, `dist`, `config`, `fileFor(pathname)`, `readPage(pathname)`, `hrefs(html)`; đã import sẵn `readdirSync`.

- [ ] **Step 1: Tạo cấu hình dự án**

Run: `mkdir -p web/public web/src/lib web/src/i18n web/src/layouts web/src/components web/src/pages/en web/tests`

`web/package.json` (`build` chạy luôn bộ kiểm tra, nên Cloudflare Pages và CI đều không deploy/pass được một bản build thiếu trang):

```json
{
  "name": "shellx-web",
  "type": "module",
  "version": "1.0.0",
  "private": true,
  "engines": {
    "node": ">=22.12.0"
  },
  "scripts": {
    "dev": "astro dev",
    "build": "astro build && node --test tests/site.test.mjs",
    "preview": "astro preview",
    "test": "node --test tests/site.test.mjs",
    "astro": "astro"
  },
  "dependencies": {
    "astro": "^7.3.5"
  },
  "allowScripts": {
    "esbuild": true
  }
}
```

`web/.gitignore`:

```gitignore
# build output
dist/
# generated types
.astro/

# dependencies
node_modules/

# logs
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*


# environment variables
.env
.env.production

# macOS-specific files
.DS_Store

# jetbrains setting folder
.idea/
```

`web/.node-version`:

```
22
```

`web/astro.config.mjs`:

```js
// @ts-check
import { defineConfig } from 'astro/config';

// Static site for Cloudflare Pages. Every page is emitted as <path>/index.html, so internal
// links use a trailing slash (/privacy/, /en/terms/); Pages redirects /privacy to /privacy/.
export default defineConfig({
  site: 'https://shellx.pro',
  build: { format: 'directory' },
});
```

`web/tsconfig.json`:

```json
{
  "extends": "astro/tsconfigs/strict",
  "include": [".astro/types.d.ts", "**/*"],
  "exclude": ["dist"]
}
```

- [ ] **Step 2: Cài dependency và kiểm tra phiên bản**

Run: `cd web && npm install && npx astro --version && (grep -q 'linux-x64-gnu' package-lock.json && echo linux-bindings-ok)`

Expected: in `astro  v7.3.5` (hoặc 7.x mới hơn) rồi `linux-bindings-ok`. Dòng cuối chứng tỏ lockfile có binding native cho Linux, để `npm ci` chạy được trên CI Ubuntu và Cloudflare Pages. Nếu thiếu: `rm -rf node_modules package-lock.json && npm install` (lockfile phải sinh khi chưa có `node_modules`).

- [ ] **Step 3: Viết test (thất bại) cho trang chủ**

`web/tests/site.test.mjs`:

```js
// Checks the built site in dist/. Run `npm run build` (which runs these tests after `astro build`).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');
const config = JSON.parse(readFileSync(join(root, 'src/site.config.json'), 'utf8'));

const macUrl = `${config.downloadBaseUrl}/${config.desktopVersion}/ShellX-${config.desktopVersion}.dmg`;
const winUrl = `${config.downloadBaseUrl}/${config.desktopVersion}/ShellX-Setup-${config.desktopVersion}.exe`;

const homePages = [
  { path: '/', lang: 'vi', other: '/en/', privacy: '/privacy/', terms: '/terms/' },
  { path: '/en/', lang: 'en', other: '/', privacy: '/en/privacy/', terms: '/en/terms/' },
];

function fileFor(pathname) {
  return pathname.endsWith('/') ? join(dist, pathname, 'index.html') : join(dist, pathname);
}

function readPage(pathname) {
  const file = fileFor(pathname);
  assert.ok(existsSync(file), `missing ${relative(root, file)} (run: npm run build)`);
  return readFileSync(file, 'utf8');
}

function hrefs(html) {
  return [...html.matchAll(/href="([^"]*)"/g)].map((m) => m[1]);
}

test('site config is valid', () => {
  assert.match(config.desktopVersion, /^\d+\.\d+\.\d+$/);
  assert.equal(config.downloadBaseUrl, 'https://download.shellx.pro/desktop');
  assert.match(config.supportEmail, /^[^@\s]+@shellx\.pro$/);
  assert.ok(config.appStoreUrl === null || config.appStoreUrl.startsWith('https://apps.apple.com/'));
  assert.ok(config.googlePlayUrl === null || config.googlePlayUrl.startsWith('https://play.google.com/'));
});

for (const page of homePages) {
  test(`home ${page.path} links to the ${config.desktopVersion} installers`, () => {
    const html = readPage(page.path);
    assert.match(html, new RegExp(`<html lang="${page.lang}"`));
    const links = hrefs(html);
    assert.ok(links.includes(macUrl), `missing ${macUrl}`);
    assert.ok(links.includes(winUrl), `missing ${winUrl}`);
  });

  test(`home ${page.path} shows store links from config or a coming-soon placeholder`, () => {
    const html = readPage(page.path);
    for (const [store, url] of [
      ['app-store', config.appStoreUrl],
      ['google-play', config.googlePlayUrl],
    ]) {
      if (url) {
        assert.ok(hrefs(html).includes(url), `missing ${store} link ${url}`);
      } else {
        assert.match(html, new RegExp(`data-store="${store}" aria-disabled="true"`));
      }
    }
  });

  test(`home ${page.path} links to the other language and to the legal pages`, () => {
    const links = hrefs(readPage(page.path));
    for (const target of [page.other, page.privacy, page.terms, `mailto:${config.supportEmail}`]) {
      assert.ok(links.includes(target), `missing link to ${target}`);
    }
  });
}

test('installer URLs are live (only with CHECK_DOWNLOADS=1)', { skip: process.env.CHECK_DOWNLOADS !== '1' }, async () => {
  for (const url of [macUrl, winUrl]) {
    const response = await fetch(url, { method: 'HEAD' });
    assert.equal(response.status, 200, `${url} returned ${response.status}`);
  }
});
```

- [ ] **Step 4: Chạy test, xác nhận thất bại**

Run: `cd web && npm test`

Expected: FAIL ở mức file với `ENOENT: no such file or directory, open '…/web/src/site.config.json'` (config chưa có).

- [ ] **Step 5: Config link và hàm dựng URL**

`web/src/site.config.json`:

```json
{
  "desktopVersion": "1.0.0",
  "downloadBaseUrl": "https://download.shellx.pro/desktop",
  "appStoreUrl": null,
  "googlePlayUrl": null,
  "supportEmail": "support@shellx.pro"
}
```

`web/src/lib/site.ts`:

```ts
import config from '../site.config.json';

// The single source of truth for download and store links is src/site.config.json.
// Installer file names must match what release/ uploads to R2:
//   desktop/<version>/ShellX-<version>.dmg
//   desktop/<version>/ShellX-Setup-<version>.exe
export const desktopVersion: string = config.desktopVersion;
export const supportEmail: string = config.supportEmail;
export const appStoreUrl: string | null = config.appStoreUrl;
export const googlePlayUrl: string | null = config.googlePlayUrl;

export function macDownloadUrl(version: string = desktopVersion): string {
  return `${config.downloadBaseUrl}/${version}/ShellX-${version}.dmg`;
}

export function windowsDownloadUrl(version: string = desktopVersion): string {
  return `${config.downloadBaseUrl}/${version}/ShellX-Setup-${version}.exe`;
}
```

- [ ] **Step 6: Chuỗi giao diện song ngữ**

`web/src/i18n/ui.ts` (bước ghép nối tiếng Việt dùng đúng nhãn menu tray của spec §5.3 "Ghép nối điện thoại…"; bản tiếng Anh không trích nhãn vì plan 04 quyết định chuỗi đó):

```ts
export type Lang = 'vi' | 'en';
export type Page = 'home' | 'privacy' | 'terms';

const paths: Record<Lang, Record<Page, string>> = {
  vi: { home: '/', privacy: '/privacy/', terms: '/terms/' },
  en: { home: '/en/', privacy: '/en/privacy/', terms: '/en/terms/' },
};

export function pathFor(lang: Lang, page: Page): string {
  return paths[lang][page];
}

export function otherLang(lang: Lang): Lang {
  return lang === 'vi' ? 'en' : 'vi';
}

const vi = {
  languageName: 'Tiếng Việt',
  homeTitle: 'ShellX — Terminal máy tính ngay trên điện thoại',
  homeDescription:
    'Điều khiển terminal trên máy Mac hoặc PC từ điện thoại, ở bất kỳ đâu có Internet, qua kết nối mã hóa đầu cuối.',
  tagline: 'Terminal máy tính của bạn, ngay trên điện thoại.',
  intro:
    'Cài agent ShellX trên máy Mac hoặc PC, rồi mở và điều khiển các phiên terminal từ điện thoại ở bất kỳ đâu có Internet. Không cần mở port trên router, không cần mang laptop theo.',
  e2e: 'Kết nối được mã hóa đầu cuối: máy chủ trung gian không đọc được nội dung terminal của bạn.',
  stepsHeading: 'Bắt đầu trong ba bước',
  step1: 'Cài agent trên máy tính và đăng ký tài khoản.',
  step2: 'Cài app trên điện thoại và đăng nhập cùng tài khoản.',
  step3: 'Chọn "Ghép nối điện thoại…" ở menu khay trên máy tính và quét mã QR bằng điện thoại.',
  desktopHeading: 'Agent cho máy tính',
  mobileHeading: 'App cho điện thoại',
  version: 'Phiên bản',
  macos: 'Tải cho macOS',
  macosRequirement: 'macOS 12 trở lên · tệp .dmg',
  windows: 'Tải cho Windows',
  windowsRequirement: 'Windows 10 (bản 1809) trở lên · tệp .exe',
  appStore: 'App Store',
  appStoreRequirement: 'iOS 15 trở lên',
  googlePlay: 'Google Play',
  googlePlayRequirement: 'Android 8.0 trở lên',
  comingSoon: 'Sắp ra mắt',
  privacy: 'Chính sách quyền riêng tư',
  terms: 'Điều khoản sử dụng',
  contact: 'Hỗ trợ',
  lastUpdated: 'Cập nhật lần cuối',
  notFoundTitle: 'Không tìm thấy trang',
  notFoundBody: 'Trang bạn tìm không tồn tại hoặc đã được chuyển đi.',
  backHome: 'Về trang chủ',
};

type Strings = typeof vi;

const en: Strings = {
  languageName: 'English',
  homeTitle: 'ShellX — Your computer’s terminal on your phone',
  homeDescription:
    'Control the terminal on your Mac or PC from your phone, from anywhere with an Internet connection, over an end-to-end encrypted connection.',
  tagline: 'Your computer’s terminal, right on your phone.',
  intro:
    'Install the ShellX agent on your Mac or PC, then open and control terminal sessions from your phone wherever you have an Internet connection. No router ports to open, no laptop to carry.',
  e2e: 'End-to-end encrypted: the relay server in the middle cannot read your terminal content.',
  stepsHeading: 'Get started in three steps',
  step1: 'Install the agent on your computer and create an account.',
  step2: 'Install the phone app and sign in with the same account.',
  step3: 'Open the tray menu on your computer, choose to pair a phone, and scan the QR code with your phone.',
  desktopHeading: 'Agent for your computer',
  mobileHeading: 'App for your phone',
  version: 'Version',
  macos: 'Download for macOS',
  macosRequirement: 'macOS 12 or later · .dmg file',
  windows: 'Download for Windows',
  windowsRequirement: 'Windows 10 (version 1809) or later · .exe file',
  appStore: 'App Store',
  appStoreRequirement: 'iOS 15 or later',
  googlePlay: 'Google Play',
  googlePlayRequirement: 'Android 8.0 or later',
  comingSoon: 'Coming soon',
  privacy: 'Privacy Policy',
  terms: 'Terms of Use',
  contact: 'Support',
  lastUpdated: 'Last updated',
  notFoundTitle: 'Page not found',
  notFoundBody: 'The page you are looking for does not exist or has moved.',
  backHome: 'Back to home',
};

export const ui: Record<Lang, Strings> = { vi, en };
```

- [ ] **Step 7: Layout, component, trang chủ và favicon**

`web/src/layouts/Base.astro`:

```astro
---
import { otherLang, pathFor, ui, type Lang, type Page } from '../i18n/ui';
import { supportEmail } from '../lib/site';

interface Props {
  lang: Lang;
  /** null for pages without a translated counterpart (404). */
  page: Page | null;
  title: string;
  description: string;
}

const { lang, page, title, description } = Astro.props;
const t = ui[lang];
const other = otherLang(lang);
const switchHref = pathFor(other, page ?? 'home');
const site = Astro.site ?? new URL('https://shellx.pro');
const year = new Date().getFullYear();
---

<!doctype html>
<html lang={lang}>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{title}</title>
    <meta name="description" content={description} />
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
    {page && <link rel="canonical" href={new URL(pathFor(lang, page), site).href} />}
    {page && <link rel="alternate" hreflang="vi" href={new URL(pathFor('vi', page), site).href} />}
    {page && <link rel="alternate" hreflang="en" href={new URL(pathFor('en', page), site).href} />}
    {page && <link rel="alternate" hreflang="x-default" href={new URL(pathFor('vi', page), site).href} />}
  </head>
  <body>
    <header class="wrap top">
      <a class="brand" href={pathFor(lang, 'home')}>ShellX</a>
      <a class="lang-switch" href={switchHref} hreflang={other} lang={other}>{ui[other].languageName}</a>
    </header>
    <main class="wrap">
      <slot />
    </main>
    <footer class="wrap bottom">
      <nav>
        <a href={pathFor(lang, 'privacy')}>{t.privacy}</a>
        <a href={pathFor(lang, 'terms')}>{t.terms}</a>
        <a href={`mailto:${supportEmail}`}>{t.contact}: {supportEmail}</a>
      </nav>
      <p>© {year} ShellX</p>
    </footer>
  </body>
</html>

<style is:global>
  :root {
    color-scheme: light dark;
    --bg: #ffffff;
    --fg: #0f172a;
    --muted: #475569;
    --accent: #0e7490;
    --card: #f1f5f9;
    --border: #cbd5e1;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0b1120;
      --fg: #e2e8f0;
      --muted: #94a3b8;
      --accent: #22d3ee;
      --card: #111827;
      --border: #334155;
    }
  }
  * {
    box-sizing: border-box;
  }
  body {
    margin: 0;
    background: var(--bg);
    color: var(--fg);
    font-family: system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
    line-height: 1.6;
  }
  a {
    color: var(--accent);
  }
  .wrap {
    max-width: 52rem;
    margin: 0 auto;
    padding: 0 1rem;
  }
  .top {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding-top: 1rem;
    padding-bottom: 1rem;
  }
  .brand {
    font-weight: 700;
    font-size: 1.25rem;
    color: var(--fg);
    text-decoration: none;
  }
  .bottom {
    margin-top: 3rem;
    padding-top: 1rem;
    padding-bottom: 2rem;
    border-top: 1px solid var(--border);
    color: var(--muted);
    font-size: 0.9rem;
  }
  .bottom nav {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem 1.5rem;
  }
  code {
    font-family: ui-monospace, 'JetBrains Mono', Menlo, Consolas, monospace;
    font-size: 0.9em;
  }
</style>
```

`web/src/components/Downloads.astro`:

```astro
---
import { ui, type Lang } from '../i18n/ui';
import { appStoreUrl, desktopVersion, googlePlayUrl, macDownloadUrl, windowsDownloadUrl } from '../lib/site';

interface Props {
  lang: Lang;
}

const { lang } = Astro.props;
const t = ui[lang];
const stores = [
  { id: 'app-store', label: t.appStore, requirement: t.appStoreRequirement, url: appStoreUrl },
  { id: 'google-play', label: t.googlePlay, requirement: t.googlePlayRequirement, url: googlePlayUrl },
];
---

<section class="downloads">
  <div class="group">
    <h2>{t.desktopHeading}</h2>
    <p class="muted">{t.version} {desktopVersion}</p>
    <a class="button" data-platform="macos" href={macDownloadUrl()}>
      <strong>{t.macos}</strong><span>{t.macosRequirement}</span>
    </a>
    <a class="button" data-platform="windows" href={windowsDownloadUrl()}>
      <strong>{t.windows}</strong><span>{t.windowsRequirement}</span>
    </a>
  </div>
  <div class="group">
    <h2>{t.mobileHeading}</h2>
    {
      stores.map((store) =>
        store.url ? (
          <a class="button" data-store={store.id} href={store.url} rel="noopener">
            <strong>{store.label}</strong>
            <span>{store.requirement}</span>
          </a>
        ) : (
          <span class="button disabled" data-store={store.id} aria-disabled="true">
            <strong>{store.label}</strong>
            <span>
              {store.requirement} · {t.comingSoon}
            </span>
          </span>
        ),
      )
    }
  </div>
</section>

<style>
  .downloads {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
    gap: 1.5rem;
    margin-top: 2rem;
  }
  .group h2 {
    margin-bottom: 0.25rem;
  }
  .muted {
    color: var(--muted);
    margin-top: 0;
  }
  .button {
    display: flex;
    flex-direction: column;
    padding: 0.75rem 1rem;
    margin-bottom: 0.75rem;
    border: 1px solid var(--border);
    border-radius: 0.75rem;
    background: var(--card);
    color: var(--fg);
    text-decoration: none;
  }
  .button span {
    color: var(--muted);
    font-size: 0.9rem;
  }
  a.button:hover {
    border-color: var(--accent);
  }
  .disabled {
    opacity: 0.6;
  }
</style>
```

`web/src/components/Home.astro`:

```astro
---
import Base from '../layouts/Base.astro';
import Downloads from './Downloads.astro';
import { ui, type Lang } from '../i18n/ui';

interface Props {
  lang: Lang;
}

const { lang } = Astro.props;
const t = ui[lang];
---

<Base lang={lang} page="home" title={t.homeTitle} description={t.homeDescription}>
  <section class="hero">
    <h1>{t.tagline}</h1>
    <p>{t.intro}</p>
    <p class="e2e">{t.e2e}</p>
  </section>
  <Downloads lang={lang} />
  <section>
    <h2>{t.stepsHeading}</h2>
    <ol>
      <li>{t.step1}</li>
      <li>{t.step2}</li>
      <li>{t.step3}</li>
    </ol>
  </section>
</Base>

<style>
  .hero h1 {
    font-size: 2rem;
    line-height: 1.25;
    margin-top: 2rem;
  }
  .e2e {
    padding: 0.75rem 1rem;
    border-left: 4px solid var(--accent);
    background: var(--card);
  }
</style>
```

`web/src/pages/index.astro`:

```astro
---
import Home from '../components/Home.astro';
---

<Home lang="vi" />
```

`web/src/pages/en/index.astro`:

```astro
---
import Home from '../../components/Home.astro';
---

<Home lang="en" />
```

`web/public/favicon.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="14" fill="#0f172a"/>
  <path d="M16 22l12 10-12 10" fill="none" stroke="#22d3ee" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M32 44h16" stroke="#e2e8f0" stroke-width="5" stroke-linecap="round"/>
</svg>
```

- [ ] **Step 8: Build và chạy kiểm tra**

Run: `cd web && npm run build`

Expected: Astro sinh `/index.html` và `/en/index.html`, sau đó `ℹ tests 8`, `ℹ pass 7`, `ℹ fail 0`, `ℹ skipped 1` (test "installer URLs are live" chỉ chạy khi `CHECK_DOWNLOADS=1`). Link tải trong `dist/index.html` là `https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg` và `https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe`. Link privacy/terms trong footer chưa có trang đích; Task 2 thêm chúng và test link nội bộ.

- [ ] **Step 9: Commit**

```bash
git add web/package.json web/package-lock.json web/.gitignore web/.node-version web/astro.config.mjs web/tsconfig.json web/public web/src web/tests
git commit -m "feat(web): add Astro site with bilingual home page and download links"
```

---

### Task 2: Website — chính sách quyền riêng tư, điều khoản, trang 404 và hướng dẫn deploy

**Files:**
- Create: `web/src/layouts/Legal.astro`, `web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`, `web/src/pages/terms.md`, `web/src/pages/en/terms.md`, `web/src/pages/404.astro`, `web/README.md`
- Modify: `web/tests/site.test.mjs` (nối thêm test vào cuối file)

**Interfaces:**
- Consumes (Task 1): `Base.astro` props `{lang, page, title, description}`; `ui[lang].lastUpdated`, `notFoundTitle`, `notFoundBody`, `backHome`; `type Lang`, `type Page`; helper test `dist`, `config`, `fileFor`, `readPage`, `hrefs`, `readdirSync`.
- Produces: trang `/privacy/`, `/en/privacy/`, `/terms/`, `/en/terms/`; mục `id="delete-account"` trên cả hai trang privacy mô tả đường chính trong app (**Cài đặt → Xóa tài khoản** / **Settings → Delete account**, nhập lại mật khẩu, xóa ngay) và đường dự phòng qua email `support@shellx.pro`; anchor này là URL xóa tài khoản trên web cho Google Play: `https://shellx.pro/en/privacy/#delete-account`; `dist/404.html`. Front matter của trang pháp lý: `{layout, lang, page, title, description, updated: "YYYY-MM-DD"}` (ngày phải để trong ngoặc kép, nếu không YAML đọc thành `Date`).

Nội dung pháp lý dưới đây mô tả đúng hệ thống trong spec (xem Global Constraints). Khi sửa, sửa cả hai ngôn ngữ và ngày `updated`. Đây là bản nháp kỹ thuật chính xác; nên nhờ người có chuyên môn pháp lý đọc lại trước khi nộp store.

- [ ] **Step 1: Nối thêm test (thất bại) vào cuối `web/tests/site.test.mjs`**

```js
const legalPages = [
  { path: '/privacy/', lang: 'vi', other: '/en/privacy/' },
  { path: '/terms/', lang: 'vi', other: '/en/terms/' },
  { path: '/en/privacy/', lang: 'en', other: '/privacy/' },
  { path: '/en/terms/', lang: 'en', other: '/terms/' },
];

function allHtmlFiles(dir = dist) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) return allHtmlFiles(full);
    return entry.name.endsWith('.html') ? [full] : [];
  });
}

for (const page of legalPages) {
  test(`legal page ${page.path} is built in ${page.lang} and links to its translation`, () => {
    const html = readPage(page.path);
    assert.match(html, new RegExp(`<html lang="${page.lang}"`));
    assert.ok(hrefs(html).includes(page.other), `missing link to ${page.other}`);
    assert.ok(hrefs(html).includes(`mailto:${config.supportEmail}`), 'missing support email link');
  });
}

for (const [path, inApp] of [
  ['/privacy/', 'Cài đặt → Xóa tài khoản'],
  ['/en/privacy/', 'Settings → Delete account'],
]) {
  test(`privacy page ${path} documents account deletion and what is stored`, () => {
    const html = readPage(path);
    assert.match(html, /id="delete-account"/);
    assert.ok(html.includes(inApp), `privacy page ${path} must describe in-app deletion (${inApp})`);
    for (const fact of ['argon2id', 'SHA-256', 'X25519', '90', '256 KiB', 'Noise']) {
      assert.ok(html.includes(fact), `privacy page ${path} no longer mentions "${fact}"`);
    }
  });
}

test('404 page exists so Cloudflare Pages does not fall back to SPA mode', () => {
  assert.ok(existsSync(join(dist, '404.html')), 'missing dist/404.html');
});

test('every internal link resolves to a built file', () => {
  const files = allHtmlFiles();
  assert.ok(files.length >= 7, `expected at least 7 HTML files, found ${files.length}`);
  for (const file of files) {
    for (const href of hrefs(readFileSync(file, 'utf8'))) {
      if (!href.startsWith('/') || href.startsWith('//')) continue;
      const pathname = href.split('#')[0].split('?')[0];
      assert.ok(existsSync(fileFor(pathname)), `${relative(dist, file)} links to missing ${href}`);
    }
  }
});

test('no third-party scripts, stylesheets or frames (the privacy policy promises no trackers)', () => {
  for (const file of allHtmlFiles()) {
    const html = readFileSync(file, 'utf8');
    const where = relative(dist, file);
    assert.doesNotMatch(html, /<iframe/i, `${where} embeds an iframe`);
    for (const m of html.matchAll(/<script[^>]*\ssrc="([^"]*)"/gi)) {
      assert.ok(m[1].startsWith('/') && !m[1].startsWith('//'), `${where} loads external script ${m[1]}`);
    }
    for (const m of html.matchAll(/<link[^>]*rel="stylesheet"[^>]*>/gi)) {
      assert.doesNotMatch(m[0], /href="(https?:)?\/\//, `${where} loads external stylesheet`);
    }
  }
});
```

- [ ] **Step 2: Chạy, xác nhận thất bại**

Run: `cd web && npm run build`

Expected: `ℹ tests 17`, `ℹ pass 8`, `ℹ fail 8`, `ℹ skipped 1`. Tám test lỗi: 4 test "legal page …" (`missing dist/privacy/index.html …`), 2 test "privacy page …", "404 page exists …", "every internal link resolves …" (`expected at least 7 HTML files, found 2`).

- [ ] **Step 3: Layout cho trang pháp lý**

`web/src/layouts/Legal.astro`:

```astro
---
import Base from './Base.astro';
import { ui, type Lang, type Page } from '../i18n/ui';

interface Props {
  frontmatter: {
    lang: Lang;
    page: Page;
    title: string;
    description: string;
    updated: string;
  };
}

const { lang, page, title, description, updated } = Astro.props.frontmatter;
const updatedLabel = new Date(`${updated}T00:00:00Z`).toLocaleDateString(lang === 'vi' ? 'vi-VN' : 'en-US', {
  year: 'numeric',
  month: 'long',
  day: 'numeric',
  timeZone: 'UTC',
});
---

<Base lang={lang} page={page} title={`${title} — ShellX`} description={description}>
  <article class="legal">
    <h1>{title}</h1>
    <p class="updated">{ui[lang].lastUpdated}: <time datetime={updated}>{updatedLabel}</time></p>
    <slot />
  </article>
</Base>

<style>
  .legal h1 {
    margin-bottom: 0.25rem;
  }
  .updated {
    color: var(--muted);
    margin-top: 0;
  }
  .legal :global(h2) {
    margin-top: 2rem;
  }
</style>
```

- [ ] **Step 4: Chính sách quyền riêng tư (tiếng Việt)**

`web/src/pages/privacy.md`:

```markdown
---
layout: ../layouts/Legal.astro
lang: vi
page: privacy
title: Chính sách quyền riêng tư
description: ShellX thu thập dữ liệu gì, dùng để làm gì, lưu bao lâu và quyền của bạn.
updated: "2026-09-25"
---

ShellX ("chúng tôi") cung cấp agent cho máy tính (macOS, Windows), ứng dụng di động (iOS, Android), máy chủ chuyển tiếp (relay) tại `relay.shellx.pro` và trang web `shellx.pro` (gọi chung là "Dịch vụ"). Chính sách này mô tả dữ liệu nào được thu thập, dùng để làm gì, lưu bao lâu và bạn có những quyền gì.

## Tóm tắt

- Nội dung terminal (lệnh bạn gõ và kết quả hiển thị) được **mã hóa đầu cuối** giữa điện thoại và máy tính của bạn. Máy chủ chuyển tiếp chỉ chuyển dữ liệu đã mã hóa và **không thể đọc** nội dung đó.
- Chúng tôi chỉ lưu những gì cần để vận hành tài khoản: email, mật khẩu ở dạng băm, thông tin thiết bị và bản ghi ghép nối.
- Không quảng cáo, không công cụ phân tích hay theo dõi, không thông báo đẩy (push notification), không bán dữ liệu.

## 1. Dữ liệu lưu trên máy chủ của chúng tôi

**Tài khoản**

- **Email** — dùng làm tên đăng nhập, lưu ở dạng chữ thường. Chúng tôi không gửi email xác thực hay email quảng cáo.
- **Mật khẩu** — không bao giờ được lưu ở dạng gốc. Máy chủ chỉ lưu kết quả băm bằng thuật toán **argon2id**; từ kết quả băm không thể khôi phục mật khẩu.
- Thời điểm tạo tài khoản và thời điểm đổi mật khẩu gần nhất.

**Thiết bị** — mỗi khi bạn đăng ký hoặc đăng nhập trên một thiết bị, chúng tôi lưu:

- **tên thiết bị**: tên máy (hostname) với máy tính, tên model với điện thoại;
- **loại thiết bị** (agent trên máy tính hoặc ứng dụng di động) và **nền tảng** (macOS, Windows, iOS hoặc Android);
- **khóa công khai** của thiết bị (X25519). Khóa bí mật tương ứng không bao giờ rời khỏi thiết bị;
- thời điểm thêm thiết bị và **thời điểm online gần nhất**, dùng để hiển thị "Lần cuối online" trong ứng dụng.

**Mã truy cập (token)** — mỗi thiết bị đăng nhập nhận một mã truy cập ngẫu nhiên. Máy chủ chỉ lưu giá trị băm SHA-256 của mã, thời điểm tạo và thời điểm dùng gần nhất.

**Bản ghi ghép nối** — khi bạn ghép nối một điện thoại với một máy tính bằng mã QR, máy chủ lưu cặp (máy tính, điện thoại) và thời điểm ghép nối, chỉ để hiển thị trong ứng dụng. Việc tin cậy một điện thoại được quyết định và lưu trên chính máy tính của bạn, không phải trên máy chủ.

**Địa chỉ IP** — địa chỉ IP của bạn được dùng tạm thời để giới hạn số lần đăng nhập và đăng ký trong mỗi khoảng 60 giây (chống dò mật khẩu và lạm dụng). Chúng tôi không lưu địa chỉ IP vào cơ sở dữ liệu tài khoản.

**Nhật ký vận hành** — máy chủ ghi nhật ký kỹ thuật tối thiểu để vận hành và xử lý sự cố: thời điểm, mã thiết bị, mã lỗi và kích thước gói dữ liệu. Nhật ký **không bao giờ** chứa nội dung terminal, mật khẩu hay mã truy cập.

## 2. Nội dung terminal được mã hóa đầu cuối

Điện thoại và máy tính thiết lập một kênh mã hóa bằng giao thức Noise, với khóa mà chỉ hai thiết bị đó nắm giữ. Máy chủ chuyển tiếp chỉ thấy các gói dữ liệu đã mã hóa, mã thiết bị gửi và nhận, kích thước và thời điểm của gói; nó không đọc được lệnh bạn gõ, kết quả hiển thị, và cũng không biết bạn đang mở bao nhiêu phiên terminal. Chúng tôi không lưu nội dung terminal.

Để bù phần output phát sinh khi điện thoại tạm mất kết nối, agent giữ tối đa 256 KiB output gần nhất của mỗi phiên **trong bộ nhớ của máy tính của bạn**. Dữ liệu này không được gửi cho chúng tôi và mất đi khi phiên kết thúc hoặc agent thoát.

## 3. Dữ liệu chỉ nằm trên thiết bị của bạn

Khóa bí mật của thiết bị, mã truy cập, danh sách điện thoại được tin cậy (trên máy tính), danh sách máy đã ghép nối (trên điện thoại) và các cài đặt được lưu trong kho bảo mật của hệ điều hành (Keychain, Windows Credential Manager, Android Keystore) hoặc vùng cài đặt của ứng dụng. Những dữ liệu này không được gửi lên máy chủ, trừ mã truy cập được gửi kèm mỗi yêu cầu để xác thực.

- **Camera:** ứng dụng di động chỉ dùng camera để quét mã QR ghép nối. Hình ảnh không được lưu hay gửi đi.
- **Sinh trắc học:** khóa ứng dụng bằng Face ID, vân tay hoặc mã máy do hệ điều hành xử lý. Ứng dụng chỉ nhận kết quả thành công hoặc thất bại, không bao giờ nhận dữ liệu sinh trắc học.
- **Full Disk Access (macOS):** quyền này không bắt buộc và chỉ để các lệnh bạn chạy trong terminal truy cập được thư mục của bạn. Agent không tự đọc hay tải lên tệp nào của bạn.

## 4. Những gì chúng tôi không làm

- Không dùng công cụ phân tích, quảng cáo, pixel theo dõi hay SDK bên thứ ba để theo dõi hành vi.
- Không gửi thông báo đẩy.
- Không bán, cho thuê hay chia sẻ dữ liệu cá nhân cho mục đích quảng cáo.
- Trang web `shellx.pro` không dùng cookie và không nhúng script của bên thứ ba.

## 5. Mục đích sử dụng dữ liệu

Chúng tôi chỉ dùng dữ liệu nêu ở mục 1 để: tạo và xác thực tài khoản; hiển thị danh sách thiết bị, trạng thái online và ghép nối; chuyển tiếp dữ liệu đã mã hóa giữa các thiết bị trong cùng một tài khoản; và bảo vệ Dịch vụ khỏi lạm dụng.

## 6. Bên cung cấp hạ tầng và nơi xử lý dữ liệu

Dịch vụ chạy trên hạ tầng của Cloudflare, Inc. (Workers, Durable Objects, D1, R2, Pages). Dữ liệu có thể được xử lý tại các trung tâm dữ liệu của Cloudflare bên ngoài Việt Nam. Cloudflare xử lý dữ liệu thay mặt chúng tôi và cũng xử lý địa chỉ IP cùng thông tin kỹ thuật của kết nối để vận chuyển dữ liệu và chống tấn công, theo chính sách của Cloudflare.

Khi bạn tải ứng dụng từ App Store hoặc Google Play, Apple và Google xử lý dữ liệu theo chính sách riêng của họ.

Chúng tôi chỉ cung cấp dữ liệu cho cơ quan nhà nước khi pháp luật bắt buộc. Vì nội dung terminal được mã hóa đầu cuối, chúng tôi không có nội dung đó để cung cấp.

## 7. Thời gian lưu trữ

- **Tài khoản và thiết bị:** cho tới khi tài khoản bị xóa.
- **Mã truy cập:** bị xóa khi bạn đăng xuất trên thiết bị đó hoặc khi bị thu hồi (đổi mật khẩu thu hồi mã của mọi thiết bị khác); mã hết hiệu lực sau 90 ngày không dùng.
- **Bản ghi ghép nối:** bị xóa khi bạn thu hồi hoặc bỏ ghép nối, hoặc khi bạn đăng xuất khỏi agent trên máy tính đó.
- **Nhật ký vận hành:** không quá 30 ngày.

<h2 id="delete-account">8. Xóa tài khoản</h2>

Bạn có thể tự xóa tài khoản ngay trong ứng dụng di động: mở **Cài đặt → Xóa tài khoản** và nhập lại mật khẩu để xác nhận. Việc xóa có hiệu lực ngay và không thể hoàn tác: máy chủ xóa vĩnh viễn tài khoản cùng toàn bộ thiết bị, mã truy cập và bản ghi ghép nối; mọi thiết bị đang kết nối bị đăng xuất, và agent trên máy tính xử lý như khi bạn đăng xuất (xóa danh sách điện thoại được tin cậy và đóng mọi phiên terminal).

Nếu bạn không còn dùng được ứng dụng di động, hãy gửi email tới [support@shellx.pro](mailto:support@shellx.pro) **từ chính địa chỉ email của tài khoản**, tiêu đề "Xóa tài khoản ShellX". Chúng tôi có thể hỏi thêm thông tin để xác minh bạn là chủ tài khoản, xóa tài khoản trong vòng 30 ngày kể từ khi xác minh, rồi gửi email xác nhận.

Nhật ký vận hành (không chứa nội dung terminal, mật khẩu hay mã truy cập) tự hết hạn trong vòng 30 ngày. Dữ liệu nằm trên thiết bị của bạn (mục 3) được xóa khi bạn gỡ cài đặt ứng dụng.

## 9. Quyền của bạn

Bạn có quyền yêu cầu truy cập, chỉnh sửa hoặc xóa dữ liệu cá nhân của mình, rút lại sự đồng ý và phản đối việc xử lý dữ liệu, theo pháp luật về bảo vệ dữ liệu cá nhân nơi bạn sinh sống. Gửi yêu cầu tới [support@shellx.pro](mailto:support@shellx.pro); chúng tôi phản hồi trong vòng 30 ngày.

Ngay trong ứng dụng, bạn có thể xem danh sách thiết bị, thu hồi hoặc bỏ ghép nối, đăng xuất, đổi mật khẩu (từ máy tính đang đăng nhập) và xóa tài khoản (từ ứng dụng di động).

## 10. Bảo mật

Mọi kết nối tới máy chủ dùng TLS; nội dung terminal được mã hóa đầu cuối; mật khẩu được băm bằng argon2id; mã truy cập chỉ được lưu ở dạng băm SHA-256; khóa bí mật nằm trong kho bảo mật của hệ điều hành; ứng dụng di động mặc định khóa bằng sinh trắc học. Không hệ thống nào an toàn tuyệt đối; nếu xảy ra sự cố ảnh hưởng tới dữ liệu của bạn, chúng tôi sẽ thông báo theo quy định của pháp luật.

## 11. Trẻ em

Dịch vụ không dành cho người dưới 16 tuổi và chúng tôi không cố ý thu thập dữ liệu của họ. Nếu bạn biết một người dưới 16 tuổi đã tạo tài khoản, hãy liên hệ để chúng tôi xóa tài khoản đó.

## 12. Thay đổi chính sách

Khi chính sách thay đổi, chúng tôi cập nhật trang này và ngày "Cập nhật lần cuối" ở đầu trang. Với thay đổi quan trọng, chúng tôi đăng thông báo trên `shellx.pro` trước khi thay đổi có hiệu lực.

## 13. Liên hệ

Mọi câu hỏi về quyền riêng tư: [support@shellx.pro](mailto:support@shellx.pro).
```

- [ ] **Step 5: Privacy Policy (tiếng Anh)**

`web/src/pages/en/privacy.md`:

```markdown
---
layout: ../../layouts/Legal.astro
lang: en
page: privacy
title: Privacy Policy
description: What data ShellX collects, why, how long it is kept, and your rights.
updated: "2026-09-25"
---

ShellX ("we") provides a desktop agent (macOS, Windows), a mobile app (iOS, Android), a relay server at `relay.shellx.pro` and the website `shellx.pro` (together, the "Service"). This policy explains what data is collected, what it is used for, how long it is kept, and what rights you have.

## Summary

- Terminal content (the commands you type and the output you see) is **end-to-end encrypted** between your phone and your computer. The relay only forwards encrypted data and **cannot read** it.
- We store only what is needed to run your account: your email, a hash of your password, device information and pairing records.
- No ads, no analytics or tracking tools, no push notifications, and we never sell data.

## 1. Data stored on our servers

**Account**

- **Email** — your sign-in name, stored in lowercase. We do not send verification or marketing emails.
- **Password** — never stored as entered. The server stores only an **argon2id** hash, from which the password cannot be recovered.
- When the account was created and when the password was last changed.

**Devices** — each time you register or sign in on a device, we store:

- the **device name**: the hostname for a computer, the model name for a phone;
- the **device kind** (desktop agent or mobile app) and **platform** (macOS, Windows, iOS or Android);
- the device's **public key** (X25519). The matching private key never leaves the device;
- when the device was added and when it was **last online**, used to show "Last online" in the app.

**Access tokens** — each signed-in device receives a random access token. The server stores only its SHA-256 hash, when it was created and when it was last used.

**Pairing records** — when you pair a phone with a computer by scanning a QR code, the server stores the (computer, phone) pair and when it was paired, for display in the apps only. Whether a phone is trusted is decided and stored on your computer, not on the server.

**IP addresses** — your IP address is used transiently to limit sign-in and registration attempts per 60-second window (to stop password guessing and abuse). We do not store IP addresses in the account database.

**Operational logs** — the server keeps minimal technical logs to run the Service and fix problems: timestamps, device IDs, error codes and frame sizes. Logs **never** contain terminal content, passwords or access tokens.

## 2. Terminal content is end-to-end encrypted

Your phone and your computer set up an encrypted channel using the Noise protocol, with keys that only those two devices hold. The relay sees only encrypted frames, the sending and receiving device IDs, and the size and timing of frames; it cannot read what you type or what is displayed, and it does not even know how many terminal sessions you have open. We do not store terminal content.

To replay output produced while your phone is briefly disconnected, the agent keeps up to 256 KiB of the most recent output of each session **in your computer's memory**. It is never sent to us and is gone when the session ends or the agent quits.

## 3. Data that stays on your devices

The device private key, access token, the list of trusted phones (on the computer), the list of paired computers (on the phone) and your settings are stored in the operating system's secure storage (Keychain, Windows Credential Manager, Android Keystore) or in the app's settings storage. They are not sent to our servers, except for the access token, which accompanies each request to authenticate it.

- **Camera:** the mobile app uses the camera only to scan pairing QR codes. Images are neither stored nor sent anywhere.
- **Biometrics:** the app lock uses Face ID, fingerprint or the device passcode through the operating system. The app only receives a success or failure result, never biometric data.
- **Full Disk Access (macOS):** this optional permission only lets the commands you run in the terminal reach your folders. The agent itself never reads or uploads your files.

## 4. What we do not do

- No analytics, advertising, tracking pixels or third-party tracking SDKs.
- No push notifications.
- We do not sell, rent or share personal data for advertising.
- The `shellx.pro` website sets no cookies and embeds no third-party scripts.

## 5. How we use data

We use the data listed in section 1 only to: create and authenticate your account; show your devices, their online status and pairings; relay encrypted data between devices of the same account; and protect the Service from abuse.

## 6. Infrastructure provider and where data is processed

The Service runs on Cloudflare, Inc. infrastructure (Workers, Durable Objects, D1, R2, Pages). Data may be processed in Cloudflare data centers outside Vietnam. Cloudflare processes data on our behalf, and also processes IP addresses and connection metadata to deliver traffic and block attacks, under Cloudflare's own policies.

When you download the mobile app from the App Store or Google Play, Apple and Google process data under their own policies.

We disclose data to authorities only when the law requires it. Because terminal content is end-to-end encrypted, we do not have it to disclose.

## 7. Retention

- **Account and devices:** until the account is deleted.
- **Access tokens:** deleted when you sign out on that device or when revoked (changing your password revokes the tokens of all other devices); a token expires after 90 days without use.
- **Pairing records:** deleted when you revoke or unpair, or when you sign out of the agent on that computer.
- **Operational logs:** no longer than 30 days.

<h2 id="delete-account">8. Deleting your account</h2>

You can delete your account yourself in the mobile app: open **Settings → Delete account** and enter your password again to confirm. Deletion takes effect immediately and cannot be undone: the server permanently deletes the account with all of its devices, access tokens and pairing records; every connected device is signed out, and the desktop agent handles it like a sign-out (it clears its list of trusted phones and closes all terminal sessions).

If you can no longer use the mobile app, email [support@shellx.pro](mailto:support@shellx.pro) **from the email address of the account** with the subject "Delete my ShellX account". We may ask for more information to confirm that you own the account, delete it within 30 days of verification, and confirm by email.

Operational logs (which never contain terminal content, passwords or access tokens) expire within 30 days. Data stored on your devices (section 3) is removed when you uninstall the apps.

## 9. Your rights

You have the right to request access to, correction of, or deletion of your personal data, to withdraw consent and to object to processing, under the data protection laws where you live. Send requests to [support@shellx.pro](mailto:support@shellx.pro); we reply within 30 days.

In the apps you can view your devices, revoke or remove pairings, sign out, change your password (from a signed-in computer) and delete your account (from the mobile app).

## 10. Security

All connections to our servers use TLS; terminal content is end-to-end encrypted; passwords are hashed with argon2id; access tokens are stored only as SHA-256 hashes; private keys live in the operating system's secure storage; and the mobile app is locked with biometrics by default. No system is perfectly secure; if an incident affects your data, we will notify you as required by law.

## 11. Children

The Service is not intended for anyone under 16, and we do not knowingly collect their data. If you know that someone under 16 has created an account, contact us and we will delete it.

## 12. Changes to this policy

When this policy changes, we update this page and the "Last updated" date at the top. For significant changes, we post a notice on `shellx.pro` before the change takes effect.

## 13. Contact

Privacy questions: [support@shellx.pro](mailto:support@shellx.pro).
```

- [ ] **Step 6: Điều khoản sử dụng (tiếng Việt)**

`web/src/pages/terms.md`:

```markdown
---
layout: ../layouts/Legal.astro
lang: vi
page: terms
title: Điều khoản sử dụng
description: Điều khoản áp dụng khi bạn sử dụng ShellX.
updated: "2026-09-25"
---

Điều khoản này là thỏa thuận giữa bạn và ShellX ("chúng tôi") khi bạn sử dụng agent trên máy tính, ứng dụng di động, máy chủ chuyển tiếp và trang web `shellx.pro` (gọi chung là "Dịch vụ"). Khi tạo tài khoản hoặc sử dụng Dịch vụ, bạn đồng ý với các điều khoản này và với [Chính sách quyền riêng tư](/privacy/).

## 1. Dịch vụ

ShellX cho phép bạn mở và điều khiển các phiên terminal trên máy tính macOS hoặc Windows của mình từ điện thoại qua Internet. Máy tính chạy agent kết nối tới máy chủ chuyển tiếp; nội dung terminal được mã hóa đầu cuối giữa điện thoại và máy tính.

## 2. Điều kiện sử dụng

- Bạn từ 16 tuổi trở lên.
- Bạn chỉ cài agent và điều khiển những máy tính mà bạn sở hữu hoặc được phép quản lý.
- Bạn đăng ký bằng địa chỉ email thật của mình. Địa chỉ email dùng một lần (email tạm) không được chấp nhận.

## 3. Tài khoản và bảo mật

- Bạn chịu trách nhiệm giữ bí mật mật khẩu và bảo vệ các thiết bị đang đăng nhập.
- Một điện thoại chỉ điều khiển được máy tính khi vừa đăng nhập cùng tài khoản, vừa được ghép nối bằng mã QR hiển thị trên chính máy tính đó. Chỉ quét mã QR khi bạn đang ở cạnh máy tính của mình.
- Nếu mất điện thoại: trên máy tính, mở menu khay → "Thiết bị đã ghép" → "Thu hồi" điện thoại đó, rồi đổi mật khẩu (việc đổi mật khẩu đăng xuất mọi thiết bị khác).
- Dịch vụ không có khôi phục mật khẩu qua email; mật khẩu chỉ đổi được từ một máy tính đang đăng nhập. Nếu bạn không còn truy cập được máy tính nào, hãy liên hệ [support@shellx.pro](mailto:support@shellx.pro); chúng tôi sẽ xác minh quyền sở hữu tài khoản trước khi đặt lại mật khẩu.
- Hãy báo ngay cho chúng tôi nếu bạn phát hiện tài khoản bị truy cập trái phép.

## 4. Trách nhiệm đối với lệnh được chạy

Các phiên terminal chạy với quyền của tài khoản người dùng trên máy tính. Mọi lệnh gửi từ điện thoại đã ghép nối có tác dụng như khi gõ trực tiếp trên máy, kể cả xóa dữ liệu, cài phần mềm hay thay đổi cấu hình hệ thống. Chúng tôi không xem được, không kiểm soát được và không thể hoàn tác các lệnh đó. Bạn tự chịu trách nhiệm về các lệnh chạy qua ShellX và nên sao lưu dữ liệu quan trọng.

Tính năng "Giữ máy không ngủ" (mặc định bật) ngăn máy tự ngủ khi để yên và có thể làm máy tiêu thụ thêm điện; bạn có thể tắt tính năng này trong menu khay.

## 5. Hành vi bị cấm

Bạn không được:

- truy cập hoặc điều khiển máy tính của người khác khi không được phép;
- dùng Dịch vụ cho hoạt động vi phạm pháp luật, phát tán mã độc hay tấn công hệ thống khác;
- dò mật khẩu, cố vượt qua các giới hạn kỹ thuật, làm quá tải hoặc gây gián đoạn máy chủ chuyển tiếp;
- truy cập tài khoản hoặc dữ liệu của người dùng khác;
- bán lại hoặc cung cấp Dịch vụ cho bên thứ ba như một dịch vụ thương mại khi chưa được chúng tôi đồng ý bằng văn bản.

## 6. Phí

ShellX hiện được cung cấp miễn phí. Nếu sau này có tính năng trả phí, chúng tôi sẽ thông báo trước và bạn có quyền không sử dụng các tính năng đó.

## 7. Tính sẵn sàng và giới hạn

- Dịch vụ được cung cấp theo khả năng tốt nhất, không cam kết thời gian hoạt động.
- Mỗi máy tính mở được tối đa 10 phiên terminal. Khi điện thoại mất kết nối, agent giữ tối đa 256 KiB output gần nhất của mỗi phiên để gửi bù; phần cũ hơn sẽ mất.
- Các phiên terminal kết thúc khi agent thoát hoặc máy tính khởi động lại. Gập nắp laptop thì máy vẫn ngủ và mất kết nối.
- Chúng tôi có thể yêu cầu bạn cập nhật ứng dụng; phiên bản quá cũ có thể không dùng được.
- Chúng tôi có thể thay đổi hoặc ngừng Dịch vụ. Nếu ngừng hẳn, chúng tôi sẽ thông báo trên `shellx.pro` ít nhất 30 ngày trước.

## 8. Quyền sở hữu trí tuệ và giấy phép

Chúng tôi cấp cho bạn quyền cá nhân, không độc quyền, không chuyển nhượng và có thể thu hồi để cài đặt và sử dụng các ứng dụng ShellX theo điều khoản này. Tên và biểu trưng ShellX thuộc về chúng tôi. Dữ liệu trên máy tính của bạn và nội dung terminal của bạn thuộc về bạn.

## 9. Dịch vụ của bên thứ ba

Dịch vụ chạy trên hạ tầng của Cloudflare. Ứng dụng di động được phân phối qua App Store và Google Play và cũng chịu điều khoản của Apple và Google. Với ứng dụng tải từ App Store, Thỏa thuận cấp phép người dùng cuối tiêu chuẩn của Apple (Standard EULA) cũng được áp dụng.

## 10. Chấm dứt

Bạn có thể ngừng sử dụng Dịch vụ bất cứ lúc nào và xóa tài khoản trong ứng dụng di động (**Cài đặt → Xóa tài khoản**) hoặc theo hướng dẫn trong [Chính sách quyền riêng tư](/privacy/#delete-account). Chúng tôi có thể tạm khóa hoặc chấm dứt tài khoản vi phạm điều khoản này, hoặc khi pháp luật yêu cầu.

## 11. Miễn trừ bảo đảm

Dịch vụ được cung cấp "nguyên trạng" và "theo khả năng sẵn có". Trong phạm vi pháp luật cho phép, chúng tôi không bảo đảm rằng Dịch vụ sẽ không bị gián đoạn, không có lỗi hoặc phù hợp với một mục đích cụ thể.

## 12. Giới hạn trách nhiệm

Trong phạm vi tối đa pháp luật cho phép, chúng tôi không chịu trách nhiệm về thiệt hại gián tiếp, mất dữ liệu hoặc mất lợi nhuận phát sinh từ việc sử dụng hoặc không thể sử dụng Dịch vụ, kể cả hậu quả của các lệnh chạy qua ShellX. Điều khoản này không loại trừ trách nhiệm mà pháp luật không cho phép loại trừ.

## 13. Luật áp dụng

Điều khoản này được điều chỉnh bởi pháp luật Việt Nam. Tranh chấp trước hết được giải quyết bằng thương lượng; nếu không thành, tranh chấp được giải quyết tại tòa án có thẩm quyền của Việt Nam. Điều khoản này không làm mất các quyền mà pháp luật bảo vệ người tiêu dùng nơi bạn sinh sống dành cho bạn.

## 14. Thay đổi điều khoản

Khi điều khoản thay đổi, chúng tôi cập nhật trang này và ngày "Cập nhật lần cuối". Với thay đổi quan trọng, chúng tôi đăng thông báo trên `shellx.pro` trước khi thay đổi có hiệu lực. Tiếp tục sử dụng Dịch vụ sau đó nghĩa là bạn chấp nhận điều khoản mới.

## 15. Ngôn ngữ

Điều khoản này có bản tiếng Việt và bản tiếng Anh. Nếu hai bản có khác biệt, bản tiếng Việt được ưu tiên.

## 16. Liên hệ

[support@shellx.pro](mailto:support@shellx.pro)
```

- [ ] **Step 7: Terms of Use (tiếng Anh)**

`web/src/pages/en/terms.md`:

```markdown
---
layout: ../../layouts/Legal.astro
lang: en
page: terms
title: Terms of Use
description: The terms that apply when you use ShellX.
updated: "2026-09-25"
---

These terms are an agreement between you and ShellX ("we") covering your use of the desktop agent, the mobile app, the relay server and the website `shellx.pro` (together, the "Service"). By creating an account or using the Service, you agree to these terms and to the [Privacy Policy](/en/privacy/).

## 1. The Service

ShellX lets you open and control terminal sessions on your own macOS or Windows computer from your phone over the Internet. The computer runs an agent that connects to the relay server; terminal content is end-to-end encrypted between your phone and your computer.

## 2. Eligibility

- You are at least 16 years old.
- You only install the agent on, and control, computers that you own or are authorized to administer.
- You register with your own real email address. Disposable (temporary) email addresses are not accepted.

## 3. Account and security

- You are responsible for keeping your password secret and for protecting the devices you are signed in on.
- A phone can control a computer only when it is signed in to the same account and has been paired by scanning the QR code shown on that computer. Only scan a QR code when you are next to your own computer.
- If you lose your phone: on your computer, open the tray menu, go to paired devices and revoke that phone, then change your password (which signs out every other device).
- There is no password recovery by email; the password can only be changed from a signed-in computer. If you no longer have access to any computer, contact [support@shellx.pro](mailto:support@shellx.pro); we will verify that you own the account before resetting the password.
- Tell us immediately if you notice unauthorized access to your account.

## 4. Responsibility for commands you run

Terminal sessions run with the permissions of your user account on the computer. Every command sent from a paired phone has the same effect as typing it on the computer, including deleting data, installing software or changing system settings. We cannot see, control or undo those commands. You are responsible for the commands you run through ShellX and should back up important data.

The "keep awake" feature (on by default) prevents the computer from sleeping when idle and may increase power use; you can turn it off in the tray menu.

## 5. Prohibited conduct

You must not:

- access or control anyone else's computer without permission;
- use the Service for unlawful activity, to spread malware, or to attack other systems;
- guess passwords, try to bypass technical limits, overload or disrupt the relay server;
- access other users' accounts or data;
- resell the Service or offer it to third parties as a commercial service without our written consent.

## 6. Fees

ShellX is currently free. If paid features are introduced later, we will announce them in advance and you may choose not to use them.

## 7. Availability and limits

- The Service is provided on a best-effort basis with no uptime commitment.
- Each computer can run at most 10 terminal sessions. While your phone is disconnected, the agent keeps up to 256 KiB of the most recent output of each session to replay; older output is lost.
- Terminal sessions end when the agent quits or the computer restarts. Closing a laptop lid still puts the computer to sleep and disconnects it.
- We may require you to update the apps; very old versions may stop working.
- We may change or discontinue the Service. If we shut it down permanently, we will post a notice on `shellx.pro` at least 30 days in advance.

## 8. Intellectual property and license

We grant you a personal, non-exclusive, non-transferable, revocable license to install and use the ShellX apps under these terms. The ShellX name and logo belong to us. The data on your computer and your terminal content belong to you.

## 9. Third-party services

The Service runs on Cloudflare infrastructure. The mobile app is distributed through the App Store and Google Play and is also subject to Apple's and Google's terms. For apps downloaded from the App Store, Apple's Standard End User License Agreement (Standard EULA) also applies.

## 10. Termination

You may stop using the Service at any time and delete your account in the mobile app (**Settings → Delete account**) or as described in the [Privacy Policy](/en/privacy/#delete-account). We may suspend or terminate accounts that violate these terms, or when required by law.

## 11. Disclaimer of warranties

The Service is provided "as is" and "as available". To the extent permitted by law, we do not warrant that the Service will be uninterrupted, error-free or fit for a particular purpose.

## 12. Limitation of liability

To the fullest extent permitted by law, we are not liable for indirect damages, loss of data or loss of profits arising from the use of, or inability to use, the Service, including the consequences of commands run through ShellX. Nothing in these terms excludes liability that cannot be excluded by law.

## 13. Governing law

These terms are governed by the laws of Vietnam. Disputes will first be resolved through negotiation; failing that, by the competent courts of Vietnam. These terms do not take away any rights you have under the consumer protection laws of the place where you live.

## 14. Changes to these terms

When these terms change, we update this page and the "Last updated" date. For significant changes, we post a notice on `shellx.pro` before the change takes effect. Continuing to use the Service afterwards means you accept the new terms.

## 15. Language

These terms are available in Vietnamese and English. If the two versions differ, the Vietnamese version prevails.

## 16. Contact

[support@shellx.pro](mailto:support@shellx.pro)
```

- [ ] **Step 8: Trang 404 song ngữ**

`web/src/pages/404.astro`:

```astro
---
import Base from '../layouts/Base.astro';
import { ui } from '../i18n/ui';

// Cloudflare Pages serves dist/404.html for unknown paths. Without it, Pages would treat the
// site as a single-page app and answer every unknown path with the home page and HTTP 200.
const vi = ui.vi;
const en = ui.en;
---

<Base lang="vi" page={null} title={`${vi.notFoundTitle} — ShellX`} description={vi.notFoundBody}>
  <h1>{vi.notFoundTitle}</h1>
  <p>{vi.notFoundBody} <a href="/">{vi.backHome}</a></p>
  <div lang="en">
    <h2>{en.notFoundTitle}</h2>
    <p>{en.notFoundBody} <a href="/en/">{en.backHome}</a></p>
  </div>
</Base>
```

- [ ] **Step 9: Build, xác nhận mọi kiểm tra qua**

Run: `cd web && npm run build`

Expected: Astro sinh 7 trang (`/404.html`, `/en/privacy/index.html`, `/en/terms/index.html`, `/en/index.html`, `/privacy/index.html`, `/terms/index.html`, `/index.html`), rồi `ℹ tests 17`, `ℹ pass 16`, `ℹ fail 0`, `ℹ skipped 1`. Trong `dist/privacy/index.html` có `<h2 id="delete-account">8. Xóa tài khoản</h2>` và `Cập nhật lần cuối: <time datetime="2026-09-25" …>25 tháng 9, 2026</time>`.

- [ ] **Step 10: Commit trang**

```bash
git add web/src/layouts/Legal.astro web/src/pages web/tests/site.test.mjs
git commit -m "feat(web): add bilingual privacy policy, terms of use and 404 page"
```

- [ ] **Step 11: Hướng dẫn và deploy Cloudflare Pages**

`web/README.md`:

````markdown
# shellx.pro website

Static [Astro](https://astro.build) site for `https://shellx.pro` (spec §11): a minimal home page with
download links, the privacy policy and the terms of use, in Vietnamese (default, at `/`) and English
(under `/en/`). Marketing content and design are out of scope for v1.0.

| Path | Page |
|---|---|
| `/` · `/en/` | Home page with download links |
| `/privacy/` · `/en/privacy/` | Privacy policy (`#delete-account` explains account deletion) |
| `/terms/` · `/en/terms/` | Terms of use |
| any other path | `404.html` |

## Commands (Node 22.12 or later)

| Command | What it does |
|---|---|
| `npm ci` | Install the locked dependencies |
| `npm run dev` | Dev server at http://localhost:4321 |
| `npm run build` | `astro build` into `dist/`, then `tests/site.test.mjs` checks pages and links |
| `npm test` | Re-run the checks against an existing `dist/` |
| `CHECK_DOWNLOADS=1 npm test` | Also sends HEAD requests to the installer URLs (needs network) |

## Links and version

`src/site.config.json` is the only file to edit for links:

- `desktopVersion` — the desktop version the home page links to:
  `https://download.shellx.pro/desktop/<v>/ShellX-<v>.dmg` and
  `https://download.shellx.pro/desktop/<v>/ShellX-Setup-<v>.exe`.
  Bump it only after `release-desktop.yml` has published that version (see `release/README.md`),
  and run `CHECK_DOWNLOADS=1 npm run build` before merging.
- `appStoreUrl`, `googlePlayUrl` — `null` shows "Sắp ra mắt" / "Coming soon". Once the listings
  are live, set `googlePlayUrl` to `https://play.google.com/store/apps/details?id=pro.shellx.mobile`
  and `appStoreUrl` to the App Store listing URL (`https://apps.apple.com/app/id` followed by the
  numeric Apple ID that App Store Connect assigns to `pro.shellx.mobile`).
- `supportEmail` — shown in the footer. The legal pages name `support@shellx.pro` in their text.

Legal text lives in `src/pages/privacy.md`, `src/pages/terms.md` and the English versions in
`src/pages/en/`. Change both languages together and update `updated:` in the front matter. The
privacy policy promises no analytics, cookies or third-party scripts; the build checks fail if a
page loads an external script, stylesheet or iframe.

## Cloudflare Pages (one-time setup)

1. Cloudflare dashboard → **Workers & Pages** → **Create application** → **Pages** →
   **Connect to Git** → repository `lephus/shellx`.
2. Project name `shellx-web`, production branch `main`.
3. Build settings:
   - Framework preset: **Astro**
   - Build command: `npm run build`
   - Build output directory: `dist`
   - Root directory (advanced): `web`
   - Environment variable: `NODE_VERSION` = `22` (the build image also reads `web/.node-version`)
4. **Save and Deploy**. The first build is published at `https://shellx-web.pages.dev`.
5. Project → **Settings** → **Build** → **Build watch paths** → include `web/*`, so commits that
   do not touch the site do not rebuild it.
6. Project → **Custom domains** → **Set up a custom domain** → `shellx.pro` → **Activate domain**.
   The `shellx.pro` zone is in the same Cloudflare account, so the DNS record is created
   automatically. Wait until the domain shows **Active**.
7. Keep **Web Analytics** for the project disabled, and do not turn on zone features that add
   cookies or scripts to `shellx.pro` pages (for example Bot Fight Mode's `__cf_bm` cookie or
   injected analytics). The privacy policy promises no cookies and no analytics, and the build
   checks cannot see anything Cloudflare injects at the edge.

Every non-production branch that changes `web/` gets a preview at
`https://<branch>.shellx-web.pages.dev`.

## Verify production

```bash
curl -sIL https://shellx.pro/privacy | grep -iE '^(HTTP|location)'
# Expected: a redirect to /privacy/, then a final "HTTP/2 200"
curl -s -o /dev/null -w '%{http_code}\n' https://shellx.pro/en/terms/
# Expected: 200
curl -s -o /dev/null -w '%{http_code}\n' https://shellx.pro/no-such-page
# Expected: 404 (dist/404.html; without it Pages would answer 200 with the home page)
```

## URLs for the store listings

- Privacy policy URL (App Store Connect, Google Play Console): `https://shellx.pro/privacy`
  (spec §14; redirects to `/privacy/`). English: `https://shellx.pro/en/privacy/`.
- Google Play "Delete account" URL: `https://shellx.pro/en/privacy/#delete-account`.
````

- [ ] **Step 12: Commit hướng dẫn**

```bash
git add web/README.md
git commit -m "docs(web): document site commands and Cloudflare Pages deployment"
```

Deploy thật (bước "Cloudflare Pages (one-time setup)" trong README) do người có quyền tài khoản Cloudflare làm sau khi nhánh được merge vào `main`; sau đó chạy ba lệnh `curl` ở mục "Verify production".

---

### Task 3: Release — chọn và kiểm tra phiên bản phát hành

**Files:**
- Create: `release/scripts/version.mjs`, `release/scripts/resolve-version.mjs`
- Test: `release/tests/version.test.mjs`

**Interfaces:**
- Consumes (plan 04): dòng `version: X.Y.Z+N` trong `apps/desktop/pubspec.yaml`.
- Produces:
  - `pubspecVersion(pubspecText: string): string` — `"1.2.3+7"` → `"1.2.3"`; ném `Error('apps/desktop/pubspec.yaml has no "version:" line')`.
  - `resolveRelease({eventName, refType, refName, inputVersion = '', inputDryRun = '', pubspecText}): {version: string, dryRun: boolean}` — tag push `desktop-vX.Y.Z` → `{version, dryRun: false}`; `workflow_dispatch` → `dryRun = inputDryRun !== 'false'`; phát hành thật chỉ từ tag; phiên bản phải là `x.y.z` và bằng phiên bản pubspec.
  - CLI `node release/scripts/resolve-version.mjs`: đọc env `GITHUB_EVENT_NAME`, `GITHUB_REF_TYPE`, `GITHUB_REF_NAME`, `INPUT_VERSION`, `INPUT_DRY_RUN` (`'true' | 'false' | ''`), `PUBSPEC_PATH` (mặc định `apps/desktop/pubspec.yaml`); ghi `version=<x.y.z>` và `dry_run=<true|false>` vào `$GITHUB_OUTPUT`; lỗi thì in `::error::<lý do>` và thoát 1. Task 6 dùng hai output này.

- [ ] **Step 1: Viết test (thất bại)**

Run: `mkdir -p release/scripts release/tests`

`release/tests/version.test.mjs`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pubspecVersion, resolveRelease } from '../scripts/version.mjs';

const pubspec = (version) => `name: shellx_desktop\nversion: ${version}\nenvironment:\n  sdk: ^3.11.0\n`;

test('pubspecVersion strips the +build suffix', () => {
  assert.equal(pubspecVersion(pubspec('1.2.3+7')), '1.2.3');
  assert.equal(pubspecVersion(pubspec('1.2.3')), '1.2.3');
});

test('pubspecVersion rejects a pubspec without a version line', () => {
  assert.throws(() => pubspecVersion('name: shellx_desktop\n'), /no "version:"/);
});

test('tag push publishes the tagged version', () => {
  const result = resolveRelease({
    eventName: 'push', refType: 'tag', refName: 'desktop-v1.2.3', pubspecText: pubspec('1.2.3+7'),
  });
  assert.deepEqual(result, { version: '1.2.3', dryRun: false });
});

test('tag push fails when the tag does not match apps/desktop/pubspec.yaml', () => {
  assert.throws(
    () => resolveRelease({ eventName: 'push', refType: 'tag', refName: 'desktop-v1.2.4', pubspecText: pubspec('1.2.3+7') }),
    /does not match apps\/desktop\/pubspec.yaml version 1.2.3/,
  );
});

for (const refName of ['desktop-v1.2', 'desktop-v1.2.3-rc.1', 'v1.2.3', 'desktop-v01.2.3']) {
  test(`tag ${refName} is rejected`, () => {
    assert.throws(
      () => resolveRelease({ eventName: 'push', refType: 'tag', refName, pubspecText: pubspec('1.2.3') }),
      /not a release tag/,
    );
  });
}

test('manual dry run from a branch uses the input version', () => {
  const result = resolveRelease({
    eventName: 'workflow_dispatch', refType: 'branch', refName: 'main',
    inputVersion: '1.2.3', inputDryRun: 'true', pubspecText: pubspec('1.2.3+1'),
  });
  assert.deepEqual(result, { version: '1.2.3', dryRun: true });
});

test('manual real release from a branch is refused', () => {
  assert.throws(
    () => resolveRelease({
      eventName: 'workflow_dispatch', refType: 'branch', refName: 'main',
      inputVersion: '1.2.3', inputDryRun: 'false', pubspecText: pubspec('1.2.3'),
    }),
    /must run from a desktop-v\* tag/,
  );
});

test('manual run on a tag must agree with the version input', () => {
  assert.throws(
    () => resolveRelease({
      eventName: 'workflow_dispatch', refType: 'tag', refName: 'desktop-v1.2.3',
      inputVersion: '1.2.4', inputDryRun: 'false', pubspecText: pubspec('1.2.3'),
    }),
    /input version 1.2.4 does not match tag desktop-v1.2.3/,
  );
});

test('manual real release from a tag is allowed', () => {
  const result = resolveRelease({
    eventName: 'workflow_dispatch', refType: 'tag', refName: 'desktop-v1.2.3',
    inputVersion: '', inputDryRun: 'false', pubspecText: pubspec('1.2.3+2'),
  });
  assert.deepEqual(result, { version: '1.2.3', dryRun: false });
});

test('manual run from a branch without a version is refused', () => {
  assert.throws(
    () => resolveRelease({
      eventName: 'workflow_dispatch', refType: 'branch', refName: 'main',
      inputVersion: '', inputDryRun: 'true', pubspecText: pubspec('1.2.3'),
    }),
    /version input is required/,
  );
});

test('an invalid version input is refused', () => {
  assert.throws(
    () => resolveRelease({
      eventName: 'workflow_dispatch', refType: 'branch', refName: 'main',
      inputVersion: '1.2', inputDryRun: 'true', pubspecText: pubspec('1.2.3'),
    }),
    /not a x\.y\.z version/,
  );
});
```

- [ ] **Step 2: Chạy, xác nhận thất bại**

Run: `node --test release/tests/version.test.mjs`

Expected: FAIL với `ERR_MODULE_NOT_FOUND` (không tìm thấy `release/scripts/version.mjs`).

- [ ] **Step 3: Cài đặt logic**

`release/scripts/version.mjs`:

```js
// Decides which desktop version a release-desktop.yml run builds, and whether it is a dry run.
// A real (signed + uploaded) release only ever comes from a `desktop-vX.Y.Z` tag whose version
// equals the `version:` in apps/desktop/pubspec.yaml (build suffix `+N` ignored).

const SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const TAG = /^desktop-v(.+)$/;

export function pubspecVersion(pubspecText) {
  const match = pubspecText.match(/^version:\s*([^\s#]+)/m);
  if (!match) throw new Error('apps/desktop/pubspec.yaml has no "version:" line');
  return match[1].split('+')[0];
}

function versionFromTag(refName) {
  const match = refName.match(TAG);
  if (!match || !SEMVER.test(match[1])) {
    throw new Error(`"${refName}" is not a release tag (expected desktop-vX.Y.Z)`);
  }
  return match[1];
}

/**
 * @param {{eventName: string, refType: string, refName: string, inputVersion?: string,
 *          inputDryRun?: string, pubspecText: string}} ctx
 * @returns {{version: string, dryRun: boolean}}
 */
export function resolveRelease({ eventName, refType, refName, inputVersion = '', inputDryRun = '', pubspecText }) {
  const onTag = refType === 'tag';
  const dryRun = eventName === 'workflow_dispatch' ? inputDryRun !== 'false' : false;
  let version;
  if (onTag) {
    version = versionFromTag(refName);
    if (inputVersion && inputVersion !== version) {
      throw new Error(`input version ${inputVersion} does not match tag ${refName}`);
    }
  } else {
    if (eventName !== 'workflow_dispatch') throw new Error(`unexpected event ${eventName} on ${refType} ${refName}`);
    if (!dryRun) throw new Error('a real release must run from a desktop-v* tag; use dry_run on branches');
    if (!inputVersion) throw new Error('the version input is required when running from a branch');
    version = inputVersion;
  }
  if (!SEMVER.test(version)) throw new Error(`"${version}" is not a x.y.z version`);
  const declared = pubspecVersion(pubspecText);
  if (declared !== version) {
    throw new Error(`release version ${version} does not match apps/desktop/pubspec.yaml version ${declared}`);
  }
  return { version, dryRun };
}
```

- [ ] **Step 4: Chạy test, xác nhận qua**

Run: `node --test release/tests/version.test.mjs`

Expected: `ℹ tests 14`, `ℹ pass 14`, `ℹ fail 0`.

- [ ] **Step 5: CLI cho workflow**

`release/scripts/resolve-version.mjs`:

```js
// CLI used by .github/workflows/release-desktop.yml. Reads the GitHub context from env,
// prints the result and appends `version=` / `dry_run=` to $GITHUB_OUTPUT when set.
import { appendFileSync, readFileSync } from 'node:fs';
import { resolveRelease } from './version.mjs';

try {
  const result = resolveRelease({
    eventName: process.env.GITHUB_EVENT_NAME ?? '',
    refType: process.env.GITHUB_REF_TYPE ?? '',
    refName: process.env.GITHUB_REF_NAME ?? '',
    inputVersion: (process.env.INPUT_VERSION ?? '').trim(),
    inputDryRun: process.env.INPUT_DRY_RUN ?? '',
    pubspecText: readFileSync(process.env.PUBSPEC_PATH ?? 'apps/desktop/pubspec.yaml', 'utf8'),
  });
  console.log(`version=${result.version} dry_run=${result.dryRun}`);
  if (process.env.GITHUB_OUTPUT) {
    appendFileSync(process.env.GITHUB_OUTPUT, `version=${result.version}\ndry_run=${result.dryRun}\n`);
  }
} catch (error) {
  console.error(`::error::${error.message}`);
  process.exit(1);
}
```

- [ ] **Step 6: Thử CLI**

Run:

```bash
D="$(mktemp -d)"; printf 'name: shellx_desktop\nversion: 1.0.0+3\n' > "$D/pubspec.yaml"
GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=tag GITHUB_REF_NAME=desktop-v1.0.0 PUBSPEC_PATH="$D/pubspec.yaml" GITHUB_OUTPUT="$D/out" node release/scripts/resolve-version.mjs && cat "$D/out"
GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=tag GITHUB_REF_NAME=desktop-v1.0.1 PUBSPEC_PATH="$D/pubspec.yaml" node release/scripts/resolve-version.mjs; echo "exit=$?"
```

Expected:

```
version=1.0.0 dry_run=false
version=1.0.0
dry_run=false
::error::release version 1.0.1 does not match apps/desktop/pubspec.yaml version 1.0.0
exit=1
```

- [ ] **Step 7: Commit**

```bash
git add release/scripts release/tests/version.test.mjs
git commit -m "feat(release): resolve and validate the desktop release version"
```

---

### Task 4: Release — ký, notarize và đóng gói dmg cho macOS

Thực hiện trên máy macOS (cần `codesign`, `hdiutil`, `PlistBuddy`). Trên Linux, các test của task này tự skip.

**Files:**
- Create: `release/macos/make-dmg.sh`, `release/macos/sign-app.sh`, `release/macos/import-certificate.sh`, `release/macos/notarize.sh` (đều `chmod +x`)
- Test: `release/tests/macos-scripts.test.mjs`

**Interfaces:**
- Consumes (plan 04): `apps/desktop/macos/Runner/Release.entitlements` (không bật App Sandbox); bản build `apps/desktop/build/macos/Build/Products/Release/ShellX.app` (bundle id `pro.shellx.desktop`, executable `ShellX`). App giả trong test dùng đúng các tên này.
- Produces (Task 6 gọi):
  - `release/macos/import-certificate.sh` — env `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `RUNNER_TEMP`, `GITHUB_ENV`; ghi `MACOS_SIGNING_IDENTITY=<SHA-1 của identity "Developer ID Application">` và `MACOS_KEYCHAIN=<đường dẫn keychain tạm>` vào `$GITHUB_ENV`.
  - `release/macos/sign-app.sh <App.app> <entitlements.plist>` — env `MACOS_SIGNING_IDENTITY` (`-` = chữ ký ad-hoc cho dry run/test); ký dylib, rồi bundle lồng (sâu trước), rồi app, luôn với `--options runtime --timestamp`; thoát 1 nếu entitlements bật `com.apple.security.app-sandbox`.
  - `release/macos/notarize.sh <App.app | file.dmg>` — env `APPLE_API_KEY_PATH`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`; `notarytool submit --wait`, in log khi bị từ chối, `stapler staple` + `validate`, `spctl --assess`.
  - `release/macos/make-dmg.sh <ShellX.app> <out.dmg>` — dmg UDZO, volume `ShellX`, gốc gồm `ShellX.app` và symlink `Applications` → `/Applications`.

- [ ] **Step 1: Viết test (thất bại)**

`release/tests/macos-scripts.test.mjs`:

```js
// Exercises release/macos/*.sh on a fake app bundle with an ad-hoc signature ("-").
// macOS only; skipped elsewhere. Real Developer ID signing only happens in release-desktop.yml.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readlinkSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const scripts = join(dirname(fileURLToPath(import.meta.url)), '..', 'macos');
const skip = process.platform !== 'darwin';

function plist(entries) {
  const body = Object.entries(entries)
    .map(([k, v]) => `<key>${k}</key>${typeof v === 'boolean' ? `<${v}/>` : `<string>${v}</string>`}`)
    .join('');
  return `<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>${body}</dict></plist>\n`;
}

function fakeApp(dir) {
  const app = join(dir, 'ShellX.app');
  mkdirSync(join(app, 'Contents/MacOS'), { recursive: true });
  mkdirSync(join(app, 'Contents/Frameworks'), { recursive: true });
  writeFileSync(
    join(app, 'Contents/Info.plist'),
    plist({ CFBundleExecutable: 'ShellX', CFBundleIdentifier: 'pro.shellx.desktop', CFBundlePackageType: 'APPL' }),
  );
  copyFileSync('/usr/bin/true', join(app, 'Contents/MacOS/ShellX'));
  // Any Mach-O file works for codesign; this stands in for a plugin dylib.
  copyFileSync('/usr/bin/true', join(app, 'Contents/Frameworks/libplugin.dylib'));
  return app;
}

function run(cmd, args, env = {}) {
  return spawnSync(cmd, args, { encoding: 'utf8', env: { ...process.env, ...env } });
}

test('sign-app.sh signs nested code and the app with hardened runtime', { skip }, () => {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-sign-'));
  try {
    const app = fakeApp(dir);
    const entitlements = join(dir, 'Release.entitlements');
    writeFileSync(entitlements, plist({ 'com.apple.security.network.client': true }));
    const result = run(join(scripts, 'sign-app.sh'), [app, entitlements], { MACOS_SIGNING_IDENTITY: '-' });
    assert.equal(result.status, 0, result.stderr);
    for (const target of [app, join(app, 'Contents/Frameworks/libplugin.dylib')]) {
      const info = run('codesign', ['-dv', '--verbose=4', target]);
      assert.match(info.stderr, /flags=0x\w+\([^)]*runtime[^)]*\)/, `${target} lacks hardened runtime`);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('sign-app.sh refuses entitlements that enable App Sandbox', { skip }, () => {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-sign-'));
  try {
    const app = fakeApp(dir);
    const entitlements = join(dir, 'Release.entitlements');
    writeFileSync(entitlements, plist({ 'com.apple.security.app-sandbox': true }));
    const result = run(join(scripts, 'sign-app.sh'), [app, entitlements], { MACOS_SIGNING_IDENTITY: '-' });
    assert.notEqual(result.status, 0);
    assert.match(result.stdout + result.stderr, /app-sandbox/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('make-dmg.sh packs the app as ShellX.app next to an /Applications link', { skip }, () => {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-dmg-'));
  const mount = join(dir, 'mnt');
  try {
    const app = fakeApp(dir);
    const dmg = join(dir, 'out', 'ShellX-9.9.9.dmg');
    const made = run(join(scripts, 'make-dmg.sh'), [app, dmg]);
    assert.equal(made.status, 0, made.stderr);
    assert.ok(existsSync(dmg));
    mkdirSync(mount);
    const attach = run('hdiutil', ['attach', '-nobrowse', '-readonly', '-mountpoint', mount, dmg]);
    assert.equal(attach.status, 0, attach.stderr);
    try {
      assert.ok(existsSync(join(mount, 'ShellX.app/Contents/Info.plist')), 'ShellX.app missing in dmg');
      assert.ok(lstatSync(join(mount, 'Applications')).isSymbolicLink());
      assert.equal(readlinkSync(join(mount, 'Applications')), '/Applications');
    } finally {
      run('hdiutil', ['detach', mount, '-force']);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
```

- [ ] **Step 2: Chạy, xác nhận thất bại**

Run: `node --test release/tests/macos-scripts.test.mjs`

Expected: `ℹ tests 3`, `ℹ fail 3` — script chưa tồn tại nên `spawnSync` trả `status: null` (`Expected values to be strictly equal: null !== 0`); test sandbox báo `The "string" argument must be of type string` vì không có output.

- [ ] **Step 3: Script đóng gói dmg**

Run: `mkdir -p release/macos`

`release/macos/make-dmg.sh`:

```bash
#!/usr/bin/env bash
# Builds a compressed, read-only DMG with ShellX.app and an /Applications shortcut.
# Usage: make-dmg.sh <path/to/ShellX.app> <out/ShellX-<version>.dmg>
set -euo pipefail

app="${1:?usage: make-dmg.sh <App.app> <out.dmg>}"
out="${2:?usage: make-dmg.sh <App.app> <out.dmg>}"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

ditto "$app" "$staging/ShellX.app"
ln -s /Applications "$staging/Applications"
mkdir -p "$(dirname "$out")"
rm -f "$out"
hdiutil create -volname ShellX -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$out"
hdiutil verify "$out"
```

- [ ] **Step 4: Script ký app**

`release/macos/sign-app.sh`:

```bash
#!/usr/bin/env bash
# Signs a Flutter macOS app bundle inside-out with hardened runtime and a secure timestamp.
# Usage: MACOS_SIGNING_IDENTITY=<sha1 or "-"> sign-app.sh <ShellX.app> <entitlements.plist>
set -euo pipefail

app="${1:?usage: sign-app.sh <ShellX.app> <entitlements.plist>}"
entitlements="${2:?usage: sign-app.sh <ShellX.app> <entitlements.plist>}"
: "${MACOS_SIGNING_IDENTITY:?set by import-certificate.sh (use - for an ad-hoc test signature)}"

# Spec §8.5: distributed outside the Mac App Store with App Sandbox OFF (the sandbox forbids
# spawning the user's shell). Refuse to ship a bundle whose entitlements turn it on.
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements" 2>/dev/null || true)" == "true" ]]; then
  echo "::error::$entitlements enables com.apple.security.app-sandbox; the agent must not be sandboxed"
  exit 1
fi

sign() {
  codesign --force --timestamp --options runtime --sign "$MACOS_SIGNING_IDENTITY" "$@"
}

# 1. Loose dylibs anywhere in the bundle.
while IFS= read -r -d '' item; do
  sign "$item"
done < <(find "$app/Contents" -type f -name '*.dylib' -print0)

# 2. Nested bundles, deepest first (frameworks, helper apps, XPC services).
while IFS= read -r -d '' item; do
  sign "$item"
done < <(find "$app/Contents" -depth -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' \) -print0)

# 3. The app itself, with its entitlements.
sign --entitlements "$entitlements" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
```

Run: `chmod +x release/macos/make-dmg.sh release/macos/sign-app.sh`

- [ ] **Step 5: Chạy test, xác nhận qua**

Run: `node --test release/tests/macos-scripts.test.mjs`

Expected: `ℹ tests 3`, `ℹ pass 3`, `ℹ fail 0` (test dmg mất khoảng 20–30 s vì `hdiutil`).

- [ ] **Step 6: Script nhập chứng chỉ và notarize**

Hai script này cần chứng chỉ Developer ID và API key thật nên chỉ chạy trong `release-desktop.yml` (Task 6); ở đây kiểm tra bằng shellcheck.

`release/macos/import-certificate.sh`:

```bash
#!/usr/bin/env bash
# Imports the Developer ID Application certificate (.p12, base64) into a temporary keychain.
# Exports MACOS_SIGNING_IDENTITY (SHA-1 of the identity) and MACOS_KEYCHAIN via $GITHUB_ENV.
set -euo pipefail

: "${MACOS_CERTIFICATE_P12_BASE64:?missing secret MACOS_CERTIFICATE_P12_BASE64}"
: "${MACOS_CERTIFICATE_PASSWORD:?missing secret MACOS_CERTIFICATE_PASSWORD}"
: "${RUNNER_TEMP:?RUNNER_TEMP must be set}"
: "${GITHUB_ENV:?GITHUB_ENV must be set}"

keychain="$RUNNER_TEMP/shellx-signing.keychain-db"
keychain_password="$(openssl rand -base64 24)"
certificate="$RUNNER_TEMP/developer-id.p12"

printf '%s' "$MACOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$certificate"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$certificate" -P "$MACOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$keychain"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" > /dev/null
security list-keychain -d user -s "$keychain"
rm -f "$certificate"

identity="$(security find-identity -v -p codesigning "$keychain" | awk '/"Developer ID Application: / { print $2; exit }')"
if [[ -z "$identity" ]]; then
  echo "::error::The certificate in MACOS_CERTIFICATE_P12_BASE64 has no 'Developer ID Application' identity"
  exit 1
fi
echo "Imported Developer ID Application identity $identity"
{
  echo "MACOS_SIGNING_IDENTITY=$identity"
  echo "MACOS_KEYCHAIN=$keychain"
} >> "$GITHUB_ENV"
```

`release/macos/notarize.sh`:

```bash
#!/usr/bin/env bash
# Notarizes a signed .app or .dmg with notarytool (App Store Connect API key), then staples it.
# Usage: notarize.sh <ShellX.app | ShellX-<version>.dmg>
set -euo pipefail

target="${1:?usage: notarize.sh <App.app|file.dmg>}"
: "${APPLE_API_KEY_PATH:?path to the decoded AuthKey_<id>.p8}"
: "${APPLE_API_KEY_ID:?missing secret APPLE_API_KEY_ID}"
: "${APPLE_API_ISSUER_ID:?missing secret APPLE_API_ISSUER_ID}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

submission="$target"
if [[ "$target" == *.app ]]; then
  submission="$work/$(basename "$target" .app).zip"
  ditto -c -k --keepParent "$target" "$submission"
fi

auth=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID")
xcrun notarytool submit "$submission" "${auth[@]}" --wait --timeout 30m --output-format json > "$work/result.json" || true
status="$(plutil -extract status raw "$work/result.json" 2>/dev/null || echo unknown)"
if [[ "$status" != "Accepted" ]]; then
  echo "::error::Notarization of $target finished with status '$status'"
  cat "$work/result.json" || true
  if id="$(plutil -extract id raw "$work/result.json" 2>/dev/null)"; then
    xcrun notarytool log "$id" "${auth[@]}" || true
  fi
  exit 1
fi

xcrun stapler staple "$target"
xcrun stapler validate "$target"
if [[ "$target" == *.app ]]; then
  spctl --assess --type execute --verbose=2 "$target"
else
  spctl --assess --type open --context context:primary-signature --verbose=2 "$target"
fi
```

Run: `chmod +x release/macos/import-certificate.sh release/macos/notarize.sh`

- [ ] **Step 7: shellcheck**

Run (đoạn "Công cụ lint" ở đầu plan, rồi):

```bash
"${TMPDIR:-/tmp}/shellx-tools/shellcheck" release/macos/*.sh && echo shellcheck-ok
```

Expected: `shellcheck-ok`, không có cảnh báo.

- [ ] **Step 8: Commit (giữ quyền thực thi)**

```bash
git add release/macos release/tests/macos-scripts.test.mjs
git ls-files -s release/macos
git commit -m "feat(release): add macOS signing, notarization and dmg scripts"
```

Expected của `git ls-files -s`: cả bốn file có mode `100755`.

---

### Task 5: Release — bộ cài Windows (Inno Setup)

**Files:**
- Create: `release/windows/shellx.iss`, `release/windows/build-installer.ps1`, `release/windows/Vietnamese.isl` (tải về, không sửa), `release/windows/.gitattributes`
- Test: `release/tests/inno.test.mjs`

**Interfaces:**
- Consumes (plan 04): `apps/desktop/build/windows/x64/runner/Release/ShellX.exe`; `apps/desktop/windows/runner/resources/app_icon.ico`; `launch_at_startup` dùng tên giá trị Run `ShellX`.
- Produces (Task 6, Task 7 gọi):
  - `release/windows/build-installer.ps1 -Version <x.y.z> -SourceDir <thư mục chứa ShellX.exe> -OutputDir <thư mục> [-AppIcon <app_icon.ico>]` → tạo `<OutputDir>\ShellX-Setup-<Version>.exe`; dừng nếu `SourceDir` thiếu `ShellX.exe`; chỉ dùng Inno Setup 6 (tự `choco install innosetup --version=6.7.1` nếu máy chưa có); ném lỗi nếu ISCC thất bại hoặc không sinh file.
  - `release/windows/shellx.iss` nhận `/DAppVersion`, `/DSourceDir`, `/DOutputDir`, `/DAppIcon` (tùy chọn); `AppExeName` cố định `ShellX.exe`. AppId cố định `{6A3A45BD-0A27-407A-A1FF-3C8D1BE226EE}`, không bao giờ đổi. Ngôn ngữ: English (`compiler:Default.isl`) và Vietnamese (`Vietnamese.isl`), `ShowLanguageDialog=auto` chọn theo ngôn ngữ giao diện Windows.

**Bản dịch tiếng Việt (đã xác minh 2026-09-25):** Inno Setup không có bản dịch tiếng Việt chính thức; dùng bản không chính thức `Files/Languages/Unofficial/Vietnamese.isl` ở tag `is-6_7_1` của `jrsoftware/issrc` (người dịch Memecoder, "cho Inno Setup phiên bản 6.5.0+"). File có đủ 296 khóa `[Messages]` và 12 khóa `[CustomMessages]`, trùng khớp tuyệt đối với `Default.isl` của 6.7.1 (không thiếu, không thừa); mã hóa UTF-8 không BOM, Inno Setup hỗ trợ từ 6.3.0; SHA-256 `826bc509b612d96ccfec89b81956640a3b56b547d194404e5ff95ae1a85babf0`. Vì file gắn với bộ tin nhắn của 6.7.1, script build chỉ dùng Inno Setup 6 (runner `windows-latest` có sẵn 6.7.1). `.gitattributes` giữ nguyên CRLF của file để hash không đổi.

Không chạy được ISCC trên macOS; biên dịch thật được kiểm ở job CI `installer` (Task 7) và ở dry run của `release-desktop.yml`.

- [ ] **Step 1: Viết test (thất bại)**

`release/tests/inno.test.mjs`:

```js
// Static checks on the Inno Setup script. The script is compiled for real on Windows by the
// "Installer compiles" CI job and by release-desktop.yml; these checks pin the spec values.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const iss = readFileSync(new URL('../windows/shellx.iss', import.meta.url), 'utf8');
const vietnamese = readFileSync(new URL('../windows/Vietnamese.isl', import.meta.url));

test('installer file name is ShellX-Setup-<version>.exe (what the website and relay link to)', () => {
  assert.match(iss, /^OutputBaseFilename=ShellX-Setup-\{#AppVersion\}$/m);
});

test('installer targets Windows 10 1809+ on x64 and installs per user without UAC', () => {
  assert.match(iss, /^MinVersion=10\.0\.17763$/m);
  assert.match(iss, /^PrivilegesRequired=lowest$/m);
  assert.match(iss, /^ArchitecturesAllowed=x64compatible$/m);
  assert.match(iss, /^ArchitecturesInstallIn64BitMode=x64compatible$/m);
});

test('installs ShellX.exe, the executable apps/desktop builds', () => {
  assert.match(iss, /^#define AppExeName "ShellX\.exe"$/m);
});

test('installer offers English and the pinned Vietnamese translation', () => {
  assert.match(iss, /^Name: "english"; MessagesFile: "compiler:Default\.isl"$/m);
  assert.match(iss, /^Name: "vietnamese"; MessagesFile: "Vietnamese\.isl"$/m);
  assert.equal(
    createHash('sha256').update(vietnamese).digest('hex'),
    '826bc509b612d96ccfec89b81956640a3b56b547d194404e5ff95ae1a85babf0',
    'Vietnamese.isl must be the file from jrsoftware/issrc tag is-6_7_1',
  );
});

test('AppId is fixed so upgrades replace the existing install', () => {
  assert.match(iss, /^AppId=\{\{6A3A45BD-0A27-407A-A1FF-3C8D1BE226EE\}$/m);
});

test('a running agent is stopped before files are replaced and before uninstall', () => {
  assert.match(iss, /function PrepareToInstall[\s\S]*?taskkill\.exe[\s\S]*?\/F \/IM/);
  assert.match(iss, /\[UninstallRun\][^[]*taskkill\.exe/);
});

test('uninstall removes the launch-at-login registry value', () => {
  assert.ok(
    iss.includes("RegDeleteValue(HKEY_CURRENT_USER, 'Software\\Microsoft\\Windows\\CurrentVersion\\Run', 'ShellX')"),
    'missing RegDeleteValue for HKCU Run\\ShellX',
  );
});
```

- [ ] **Step 2: Chạy, xác nhận thất bại**

Run: `node --test release/tests/inno.test.mjs`

Expected: FAIL ở mức file với `ENOENT` (chưa có `release/windows/shellx.iss`).

- [ ] **Step 3: Tải bản dịch tiếng Việt và khóa kiểu xuống dòng**

Run:

```bash
mkdir -p release/windows
curl -sSfL -o release/windows/Vietnamese.isl https://raw.githubusercontent.com/jrsoftware/issrc/is-6_7_1/Files/Languages/Unofficial/Vietnamese.isl
shasum -a 256 release/windows/Vietnamese.isl
```

Expected: `826bc509b612d96ccfec89b81956640a3b56b547d194404e5ff95ae1a85babf0  release/windows/Vietnamese.isl`. Không sửa file này.

`release/windows/.gitattributes`:

```gitattributes
*.isl -text
```

- [ ] **Step 4: Script Inno Setup**

`release/windows/shellx.iss`:

```ini
; ShellX desktop agent installer (Inno Setup 6).
; Compiled by release/windows/build-installer.ps1:
;   ISCC.exe /DAppVersion=1.0.0 /DSourceDir=<flutter Release folder>
;            /DOutputDir=<folder> [/DAppIcon=<app_icon.ico>] release\windows\shellx.iss
; Output: <OutputDir>\ShellX-Setup-<AppVersion>.exe

#ifndef AppVersion
  #error Define AppVersion, for example /DAppVersion=1.0.0
#endif
#ifndef SourceDir
  #error Define SourceDir (apps\desktop\build\windows\x64\runner\Release)
#endif
; apps/desktop (plan 04) builds ShellX.exe.
#define AppExeName "ShellX.exe"
#ifndef OutputDir
  #define OutputDir "dist"
#endif

[Setup]
; AppId identifies ShellX for upgrades and uninstall. Never change it.
AppId={{6A3A45BD-0A27-407A-A1FF-3C8D1BE226EE}
AppName=ShellX
AppVersion={#AppVersion}
AppVerName=ShellX {#AppVersion}
AppPublisher=ShellX
AppPublisherURL=https://shellx.pro/
AppSupportURL=https://shellx.pro/
AppUpdatesURL=https://shellx.pro/
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\ShellX
DefaultGroupName=ShellX
DisableProgramGroupPage=yes
; Per-user install, no UAC prompt: the agent runs as a normal user (spec 8.5).
PrivilegesRequired=lowest
; Windows 10 version 1809 (build 17763) is the first release with ConPTY (spec 3.1).
MinVersion=10.0.17763
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=ShellX-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName=ShellX
UninstallDisplayIcon={app}\{#AppExeName}
; The agent is stopped explicitly in PrepareToInstall; no Restart Manager prompt needed.
CloseApplications=no
; Pick the language from the Windows UI language; ask only when neither matches.
ShowLanguageDialog=auto
#ifdef AppIcon
SetupIconFile={#AppIcon}
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
; Unofficial translation from jrsoftware/issrc tag is-6_7_1 (Files/Languages/Unofficial/Vietnamese.isl),
; vendored next to this script; its SHA-256 is pinned in release/tests/inno.test.mjs.
Name: "vietnamese"; MessagesFile: "Vietnamese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\ShellX"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\ShellX"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,ShellX}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Stop the tray agent so its files can be deleted.
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM ""{#AppExeName}"""; Flags: runhidden; RunOnceId: "StopShellX"

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  { Stop a running agent: it keeps its exe and DLLs locked. Its terminal sessions end,
    exactly as when the agent quits (spec 7). }
  if not Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM "{#AppExeName}"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Log('taskkill could not be started');
  Result := '';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  { launch_at_startup (apps/desktop) registers the HKCU Run value "ShellX". }
  if CurUninstallStep = usPostUninstall then
    if not RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', 'ShellX') then
      Log('No ShellX Run value to remove');
end;
```

- [ ] **Step 5: Script biên dịch**

`release/windows/build-installer.ps1`:

```powershell
# Compiles release/windows/shellx.iss with Inno Setup 6 into <OutputDir>\ShellX-Setup-<Version>.exe.
# SourceDir must contain ShellX.exe. Used by .github/workflows/release-desktop.yml and by the
# "Installer compiles" CI job.
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$SourceDir,
  [Parameter(Mandatory = $true)][string]$OutputDir,
  [string]$AppIcon = ''
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path (Join-Path $SourceDir 'ShellX.exe'))) { throw "ShellX.exe not found in $SourceDir" }

# Inno Setup 6 only: Vietnamese.isl is pinned to the 6.7.1 message set.
function Find-Iscc {
  Get-ChildItem -Path "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe" -ErrorAction SilentlyContinue |
    Select-Object -First 1
}

$iscc = Find-Iscc
if (-not $iscc) {
  choco install innosetup --version=6.7.1 -y --no-progress
  if ($LASTEXITCODE -ne 0) { throw 'choco install innosetup failed' }
  $iscc = Find-Iscc
}
if (-not $iscc) { throw 'Inno Setup 6 ISCC.exe not found after installing it' }

$defines = @("/DAppVersion=$Version", "/DSourceDir=$SourceDir", "/DOutputDir=$OutputDir")
if ($AppIcon) { $defines += "/DAppIcon=$AppIcon" }
& $iscc.FullName @defines (Join-Path $PSScriptRoot 'shellx.iss')
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }

$setup = Join-Path $OutputDir "ShellX-Setup-$Version.exe"
if (-not (Test-Path $setup)) { throw "ISCC did not produce $setup" }
Write-Host "Built $setup"
```

- [ ] **Step 6: Chạy test, xác nhận qua**

Run: `node --test release/tests/inno.test.mjs`

Expected: `ℹ tests 7`, `ℹ pass 7`, `ℹ fail 0`.

- [ ] **Step 7: Commit**

```bash
git add release/windows release/tests/inno.test.mjs
git commit -m "feat(release): add Inno Setup installer for the Windows agent"
```

---

### Task 6: Workflow phát hành desktop và tài liệu secrets

**Files:**
- Create: `.github/workflows/release-desktop.yml`, `release/README.md`

**Interfaces:**
- Consumes: Task 3 (`resolve-version.mjs` → output `version`, `dry_run`), Task 4 (bốn script macOS và env của chúng), Task 5 (`build-installer.ps1`), plan 04 (`ShellX.app` với bundle id `pro.shellx.desktop`, `ShellX.exe`, entitlements, icon). Workflow kiểm các tên này ngay sau khi build và dừng với thông báo rõ ràng nếu sai; app được ký tại chỗ trong thư mục build.
- Produces:
  - Trigger: push tag `desktop-v*`; `workflow_dispatch` với input `version` (string) và `dry_run` (boolean, mặc định `true`).
  - Job `prepare` → `macos` + `windows` → `publish` (chỉ khi `dry_run == 'false'`). Artifact của run: `macos-dmg` (`ShellX-<v>.dmg`), `windows-installer` (`ShellX-Setup-<v>.exe`).
  - Object R2 (bucket `shellx-downloads`): `desktop/<v>/ShellX-<v>.dmg`, `desktop/<v>/ShellX-Setup-<v>.exe`, `Cache-Control: public, max-age=31536000, immutable`; không bao giờ ghi đè phiên bản đã có.
  - 13 secret: `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_P8_BASE64`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_SIGNING_ENDPOINT`, `AZURE_SIGNING_ACCOUNT_NAME`, `AZURE_CERTIFICATE_PROFILE_NAME`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.

Quyết định: tải lên R2 bằng `wrangler r2 object put --remote` (không dùng AWS CLI qua S3 API) — cùng công cụ với relay, chỉ cần một Cloudflare API token (không cần cặp S3 access key, endpoint hay cấu hình AWS CLI), đặt được `Content-Type`, `Content-Disposition`, `Cache-Control` trong một lệnh; giới hạn 300 MiB mỗi lần tải (đã xác minh trong mã nguồn Wrangler 4.139.0) vượt xa kích thước bản cài. Việc tải lên dồn vào một job Ubuntu chạy sau khi cả hai nền tảng thành công, nên không bao giờ có phiên bản chỉ có một nửa file, và chỉ job này thấy secret Cloudflare. Dry run vẫn chạy `sign-app.sh` với chữ ký ad-hoc để kiểm tra script ký và kiểm tra entitlements.

- [ ] **Step 1: Viết workflow**

Run: `mkdir -p .github/workflows`

`.github/workflows/release-desktop.yml`:

```yaml
name: Release desktop

on:
  push:
    tags: ['desktop-v*']
  workflow_dispatch:
    inputs:
      version:
        description: 'Version x.y.z (required on a branch; must equal the tag when run on a desktop-v* tag)'
        required: false
        type: string
      dry_run:
        description: 'Dry run: build and package only, skip signing, notarization and upload to R2'
        required: false
        type: boolean
        default: true

permissions:
  contents: read

concurrency:
  group: release-desktop-${{ github.ref }}
  cancel-in-progress: false

env:
  FLUTTER_VERSION: 3.41.7
  NODE_VERSION: 22
  WRANGLER_VERSION: 4.139.0
  R2_BUCKET: shellx-downloads
  DOWNLOAD_BASE_URL: https://download.shellx.pro

jobs:
  prepare:
    name: Resolve version
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.resolve.outputs.version }}
      dry_run: ${{ steps.resolve.outputs.dry_run }}
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: ${{ env.NODE_VERSION }}
      - id: resolve
        env:
          INPUT_VERSION: ${{ inputs.version }}
          INPUT_DRY_RUN: ${{ inputs.dry_run }}
        run: node release/scripts/resolve-version.mjs

  macos:
    name: macOS dmg
    needs: prepare
    runs-on: macos-latest
    timeout-minutes: 60
    env:
      VERSION: ${{ needs.prepare.outputs.version }}
      DRY_RUN: ${{ needs.prepare.outputs.dry_run }}
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: ${{ env.FLUTTER_VERSION }}
          cache: true
      - name: flutter build macos --release
        working-directory: apps/desktop
        run: flutter build macos --release
      - name: Check the built app (ShellX.app, bundle id pro.shellx.desktop)
        run: |
          app=apps/desktop/build/macos/Build/Products/Release/ShellX.app
          if [[ ! -d "$app" ]]; then
            echo "::error::$app not found (apps/desktop must build ShellX.app)"
            exit 1
          fi
          bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
          if [[ "$bundle_id" != "pro.shellx.desktop" ]]; then
            echo "::error::$app has bundle id '$bundle_id', expected pro.shellx.desktop"
            exit 1
          fi
          echo "APP=$app" >> "$GITHUB_ENV"
      - name: Import Developer ID certificate
        if: env.DRY_RUN == 'false'
        env:
          MACOS_CERTIFICATE_P12_BASE64: ${{ secrets.MACOS_CERTIFICATE_P12_BASE64 }}
          MACOS_CERTIFICATE_PASSWORD: ${{ secrets.MACOS_CERTIFICATE_PASSWORD }}
        run: release/macos/import-certificate.sh
      - name: Use an ad-hoc signature for the dry run
        if: env.DRY_RUN != 'false'
        run: echo "MACOS_SIGNING_IDENTITY=-" >> "$GITHUB_ENV"
      - name: Sign ShellX.app (hardened runtime)
        run: release/macos/sign-app.sh "$APP" apps/desktop/macos/Runner/Release.entitlements
      - name: Decode App Store Connect API key
        if: env.DRY_RUN == 'false'
        env:
          APPLE_API_KEY_P8_BASE64: ${{ secrets.APPLE_API_KEY_P8_BASE64 }}
        run: |
          printf '%s' "$APPLE_API_KEY_P8_BASE64" | base64 --decode > "$RUNNER_TEMP/AuthKey.p8"
          echo "APPLE_API_KEY_PATH=$RUNNER_TEMP/AuthKey.p8" >> "$GITHUB_ENV"
      - name: Notarize and staple ShellX.app
        if: env.DRY_RUN == 'false'
        env:
          APPLE_API_KEY_ID: ${{ secrets.APPLE_API_KEY_ID }}
          APPLE_API_ISSUER_ID: ${{ secrets.APPLE_API_ISSUER_ID }}
        run: release/macos/notarize.sh "$APP"
      - name: Build dmg
        run: release/macos/make-dmg.sh "$APP" "dist/ShellX-$VERSION.dmg"
      - name: Sign, notarize and staple the dmg
        if: env.DRY_RUN == 'false'
        env:
          APPLE_API_KEY_ID: ${{ secrets.APPLE_API_KEY_ID }}
          APPLE_API_ISSUER_ID: ${{ secrets.APPLE_API_ISSUER_ID }}
        run: |
          codesign --force --timestamp --sign "$MACOS_SIGNING_IDENTITY" "dist/ShellX-$VERSION.dmg"
          release/macos/notarize.sh "dist/ShellX-$VERSION.dmg"
      - uses: actions/upload-artifact@v7
        with:
          name: macos-dmg
          path: dist/ShellX-${{ env.VERSION }}.dmg
          if-no-files-found: error
      - name: Remove signing keychain and API key
        if: always()
        run: |
          if [[ -n "${MACOS_KEYCHAIN:-}" ]]; then security delete-keychain "$MACOS_KEYCHAIN" || true; fi
          rm -f "$RUNNER_TEMP/AuthKey.p8"

  windows:
    name: Windows installer
    needs: prepare
    runs-on: windows-latest
    timeout-minutes: 60
    env:
      VERSION: ${{ needs.prepare.outputs.version }}
      DRY_RUN: ${{ needs.prepare.outputs.dry_run }}
    defaults:
      run:
        shell: pwsh
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: ${{ env.FLUTTER_VERSION }}
          cache: true
      - name: flutter build windows --release
        working-directory: apps/desktop
        run: flutter build windows --release
      - name: Check the built app (ShellX.exe)
        run: |
          $release = Join-Path $env:GITHUB_WORKSPACE 'apps\desktop\build\windows\x64\runner\Release'
          if (-not (Test-Path (Join-Path $release 'ShellX.exe'))) { throw "ShellX.exe not found in $release (apps/desktop must build ShellX.exe)" }
          "RELEASE_DIR=$release" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
      - name: Sign app binaries (Azure Artifact Signing)
        if: env.DRY_RUN == 'false'
        uses: azure/artifact-signing-action@v2
        with:
          azure-tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          azure-client-id: ${{ secrets.AZURE_CLIENT_ID }}
          azure-client-secret: ${{ secrets.AZURE_CLIENT_SECRET }}
          endpoint: ${{ secrets.AZURE_SIGNING_ENDPOINT }}
          signing-account-name: ${{ secrets.AZURE_SIGNING_ACCOUNT_NAME }}
          certificate-profile-name: ${{ secrets.AZURE_CERTIFICATE_PROFILE_NAME }}
          files-folder: ${{ env.RELEASE_DIR }}
          files-folder-filter: exe,dll
          files-folder-recurse: true
      - name: Build installer with Inno Setup
        run: |
          $out = Join-Path $env:GITHUB_WORKSPACE 'dist'
          $icon = Join-Path $env:GITHUB_WORKSPACE 'apps\desktop\windows\runner\resources\app_icon.ico'
          ./release/windows/build-installer.ps1 -Version $env:VERSION -SourceDir $env:RELEASE_DIR -OutputDir $out -AppIcon $icon
          "SETUP_EXE=$(Join-Path $out "ShellX-Setup-$env:VERSION.exe")" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
      - name: Sign installer (Azure Artifact Signing)
        if: env.DRY_RUN == 'false'
        uses: azure/artifact-signing-action@v2
        with:
          azure-tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          azure-client-id: ${{ secrets.AZURE_CLIENT_ID }}
          azure-client-secret: ${{ secrets.AZURE_CLIENT_SECRET }}
          endpoint: ${{ secrets.AZURE_SIGNING_ENDPOINT }}
          signing-account-name: ${{ secrets.AZURE_SIGNING_ACCOUNT_NAME }}
          certificate-profile-name: ${{ secrets.AZURE_CERTIFICATE_PROFILE_NAME }}
          files: ${{ env.SETUP_EXE }}
      - name: Verify Authenticode signatures
        if: env.DRY_RUN == 'false'
        run: |
          foreach ($file in @($env:SETUP_EXE, (Join-Path $env:RELEASE_DIR 'ShellX.exe'))) {
            $signature = Get-AuthenticodeSignature -FilePath $file
            if ($signature.Status -ne 'Valid') { throw "$file signature status: $($signature.Status)" }
            Write-Host "$file signed by $($signature.SignerCertificate.Subject)"
          }
      - uses: actions/upload-artifact@v7
        with:
          name: windows-installer
          path: dist/ShellX-Setup-${{ env.VERSION }}.exe
          if-no-files-found: error

  publish:
    name: Upload to R2
    needs: [prepare, macos, windows]
    if: needs.prepare.outputs.dry_run == 'false'
    runs-on: ubuntu-latest
    timeout-minutes: 15
    env:
      VERSION: ${{ needs.prepare.outputs.version }}
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
      WRANGLER_SEND_METRICS: false
    steps:
      - uses: actions/setup-node@v7
        with:
          node-version: ${{ env.NODE_VERSION }}
      - uses: actions/download-artifact@v8
        with:
          path: dist
          merge-multiple: true
      - name: Refuse to overwrite a published version
        run: |
          for name in "ShellX-$VERSION.dmg" "ShellX-Setup-$VERSION.exe"; do
            test -f "dist/$name" || { echo "::error::missing artifact $name"; exit 1; }
            url="$DOWNLOAD_BASE_URL/desktop/$VERSION/$name"
            # Unique query string: never read (or seed) a cached 404 for the real URL.
            code="$(curl -s -o /dev/null -w '%{http_code}' "$url?precheck=$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT" || true)"
            case "$code" in
              404) echo "$url is free" ;;
              000) echo "::error::cannot reach $DOWNLOAD_BASE_URL (is the R2 custom domain set up?)"; exit 1 ;;
              *) echo "::error::$url already answers HTTP $code; bump the version instead of overwriting"; exit 1 ;;
            esac
          done
      - name: Upload installers
        run: |
          put() {
            npx --yes "wrangler@$WRANGLER_VERSION" r2 object put "$R2_BUCKET/desktop/$VERSION/$1" \
              --remote --file "dist/$1" --content-type "$2" \
              --content-disposition "attachment; filename=\"$1\"" \
              --cache-control "public, max-age=31536000, immutable"
          }
          put "ShellX-$VERSION.dmg" application/x-apple-diskimage
          put "ShellX-Setup-$VERSION.exe" application/vnd.microsoft.portable-executable
      - name: Verify public download URLs
        run: |
          {
            echo "## ShellX desktop $VERSION"
            echo
            echo "| File | URL | SHA-256 |"
            echo "|---|---|---|"
          } >> "$GITHUB_STEP_SUMMARY"
          for name in "ShellX-$VERSION.dmg" "ShellX-Setup-$VERSION.exe"; do
            url="$DOWNLOAD_BASE_URL/desktop/$VERSION/$name"
            remote_size="$(curl -sfIL "$url?verify=$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT" | tr -d '\r' | awk 'tolower($1) == "content-length:" { size = $2 } END { print size }')"
            local_size="$(stat -c %s "dist/$name")"
            if [[ "$remote_size" != "$local_size" ]]; then
              echo "::error::$url has size '$remote_size', expected $local_size"
              exit 1
            fi
            echo "| $name | $url | $(sha256sum "dist/$name" | cut -d' ' -f1) |" >> "$GITHUB_STEP_SUMMARY"
          done
```

- [ ] **Step 2: Lint workflow và kiểm các bất biến**

Run (đoạn "Công cụ lint" ở đầu plan, rồi):

```bash
PATH="${TMPDIR:-/tmp}/shellx-tools:$PATH" actionlint -color .github/workflows/release-desktop.yml && echo actionlint-ok
grep -q -- '--remote --file' .github/workflows/release-desktop.yml && grep -q "if: needs.prepare.outputs.dry_run == 'false'" .github/workflows/release-desktop.yml && echo invariants-ok
```

Expected: `actionlint-ok` (actionlint cũng chạy shellcheck trên các khối `run:` vì shellcheck nằm trong `PATH`) và `invariants-ok`.

- [ ] **Step 3: Commit workflow**

```bash
git add .github/workflows/release-desktop.yml
git commit -m "ci: add desktop release workflow (sign, notarize, upload to R2)"
```

- [ ] **Step 4: Tài liệu secrets và quy trình**

`release/README.md`:

````markdown
# Desktop release pipeline

`.github/workflows/release-desktop.yml` builds, signs and publishes the desktop agent (spec §8.5, §14).

| Platform | File | Signing | Public URL |
|---|---|---|---|
| macOS 12+ (universal) | `ShellX-<v>.dmg` | Developer ID, hardened runtime, no App Sandbox, notarized and stapled | `https://download.shellx.pro/desktop/<v>/ShellX-<v>.dmg` |
| Windows 10 1809+ (x64) | `ShellX-Setup-<v>.exe` (Inno Setup, per-user, no UAC, English + Vietnamese) | Azure Artifact Signing (formerly "Trusted Signing") | `https://download.shellx.pro/desktop/<v>/ShellX-Setup-<v>.exe` |

**Triggers**

- Pushing a tag `desktop-vX.Y.Z` runs a real release: build, sign, notarize, upload to R2.
- **Actions → Release desktop → Run workflow** with `dry_run` checked (the default) builds and
  packages only: the macOS app gets an ad-hoc signature, the installer is unsigned, nothing is
  uploaded, and the files are attached to the run as artifacts `macos-dmg` and
  `windows-installer`. An unchecked `dry_run` is accepted only when the workflow runs on a
  `desktop-v*` tag.
- The release version must equal `version:` in `apps/desktop/pubspec.yaml` (the `+build` suffix is
  ignored); otherwise the run stops in the `prepare` job.

**Files**

| File | Purpose |
|---|---|
| `scripts/version.mjs`, `scripts/resolve-version.mjs` | Pick the version and the dry-run flag from the GitHub context |
| `macos/import-certificate.sh` | Import the Developer ID certificate into a temporary keychain |
| `macos/sign-app.sh` | Sign nested code, then the app, with hardened runtime; refuse App Sandbox entitlements |
| `macos/notarize.sh` | `notarytool submit --wait`, staple, `spctl` check |
| `macos/make-dmg.sh` | Compressed dmg with `ShellX.app` and an `/Applications` link |
| `windows/shellx.iss` | Inno Setup script (per-user install, Windows 10 1809+, stops a running agent) |
| `windows/Vietnamese.isl` | Unofficial Vietnamese messages, copied unchanged from `jrsoftware/issrc` tag `is-6_7_1` (`Files/Languages/Unofficial/Vietnamese.isl`); SHA-256 pinned in `tests/inno.test.mjs` |
| `windows/build-installer.ps1` | Find (or install) Inno Setup 6.7.1 and compile `shellx.iss` |
| `tests/*.test.mjs` | `node --test release/tests/*.test.mjs` (the macOS script tests run only on macOS) |

**Why `wrangler r2 object put` for the upload:** it is the tool the relay already uses, it
authenticates with one Cloudflare API token (no separate S3 access key pair, endpoint URL or AWS
CLI configuration), and it sets `Content-Type`, `Content-Disposition` and `Cache-Control` in one
command. Its 300 MiB single-upload limit is far above the installer sizes. `--remote` is
mandatory: without it Wrangler 4 writes to a local simulated bucket and still reports success.

## GitHub secrets

Settings → Secrets and variables → Actions → **Repository secrets**. Dry runs need none of them.

| Secret | Job | Value |
|---|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | macos | Base64 of the `.p12` export of the "Developer ID Application" certificate **with its private key** (`base64 -i DeveloperID.p12 \| pbcopy`) |
| `MACOS_CERTIFICATE_PASSWORD` | macos | Password chosen when exporting the `.p12` |
| `APPLE_API_KEY_P8_BASE64` | macos | Base64 of the App Store Connect API key file `AuthKey_<KEYID>.p8` (`base64 -i AuthKey_<KEYID>.p8 \| pbcopy`) |
| `APPLE_API_KEY_ID` | macos | The key ID (10 characters) |
| `APPLE_API_ISSUER_ID` | macos | The issuer ID (UUID) shown above the keys list |
| `AZURE_TENANT_ID` | windows | Directory (tenant) ID of the app registration |
| `AZURE_CLIENT_ID` | windows | Application (client) ID of the app registration |
| `AZURE_CLIENT_SECRET` | windows | Client secret value of the app registration |
| `AZURE_SIGNING_ENDPOINT` | windows | Signing account endpoint for its region, e.g. `https://weu.codesigning.azure.net/` |
| `AZURE_SIGNING_ACCOUNT_NAME` | windows | Artifact Signing account name |
| `AZURE_CERTIFICATE_PROFILE_NAME` | windows | Certificate profile name (Public Trust) |
| `CLOUDFLARE_API_TOKEN` | publish | API token with **Account → Workers R2 Storage → Edit** |
| `CLOUDFLARE_ACCOUNT_ID` | publish | Cloudflare account ID that owns the R2 bucket and the `shellx.pro` zone |

The bucket name (`shellx-downloads`), the public base URL (`https://download.shellx.pro`), Flutter
3.41.7 and Wrangler 4.139.0 are pinned in the workflow's `env:` block. The workflow expects the
names fixed by `apps/desktop`: `ShellX.app` with bundle id `pro.shellx.desktop`, and `ShellX.exe`.

## One-time setup

### 1. Apple (macOS signing and notarization)

1. Enroll in the Apple Developer Program. Only the **Account Holder** can create Developer ID
   certificates.
2. Xcode → Settings → Accounts → Manage Certificates → **+** → **Developer ID Application**
   (or developer.apple.com → Certificates → **+** → Developer ID Application).
3. Keychain Access → My Certificates → right-click "Developer ID Application: …" → **Export** →
   `.p12` with a strong password → store as `MACOS_CERTIFICATE_P12_BASE64` and
   `MACOS_CERTIFICATE_PASSWORD`.
4. App Store Connect → Users and Access → Integrations → App Store Connect API → **Team Keys** →
   **+**, access **Developer** → download `AuthKey_<KEYID>.p8` (downloadable only once) → store as
   `APPLE_API_KEY_P8_BASE64`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`.
5. The certificate expires after 5 years; notarized builds keep working after expiry thanks to the
   secure timestamp, but new releases need a renewed certificate.

### 2. Azure Artifact Signing (Windows signing)

1. Check eligibility first: Public Trust identity validation is only offered to organizations and
   individual developers in the countries Microsoft lists for Artifact Signing. If the ShellX
   publisher is not eligible, use an OV code-signing certificate instead (spec §14 allows it) and
   replace the two "Sign … (Azure Artifact Signing)" steps in the workflow.
2. Azure portal → create an **Artifact Signing account** in a supported region. Its Overview page
   shows the **Account URI** → `AZURE_SIGNING_ENDPOINT`; the account name →
   `AZURE_SIGNING_ACCOUNT_NAME`.
3. Signing account → **Identity validations** → New → Public → complete the organization (or
   individual) validation.
4. Signing account → **Certificate profiles** → Create → **Public Trust** → select the validation →
   name → `AZURE_CERTIFICATE_PROFILE_NAME`.
5. Microsoft Entra ID → App registrations → **New registration** `shellx-release-signing` →
   copy Directory (tenant) ID → `AZURE_TENANT_ID`, Application (client) ID → `AZURE_CLIENT_ID`;
   Certificates & secrets → **New client secret** → `AZURE_CLIENT_SECRET` (note its expiry date).
6. Signing account → Access control (IAM) → Add role assignment → **Artifact Signing Certificate
   Profile Signer** (older portals: "Trusted Signing Certificate Profile Signer") → the app
   registration.

### 3. Cloudflare R2 and `download.shellx.pro`

1. R2 → **Create bucket** → name `shellx-downloads`.
2. Bucket → Settings → **Custom Domains** → Add → `download.shellx.pro` → Connect. Leave the
   `r2.dev` public URL disabled.
3. My Profile → API Tokens → **Create Token** → Custom token → Permissions: **Account → Workers R2
   Storage → Edit**, Account resources: the ShellX account → `CLOUDFLARE_API_TOKEN`.
4. Account ID (Workers & Pages overview, right column) → `CLOUDFLARE_ACCOUNT_ID`.
5. Check: `curl -s -o /dev/null -w '%{http_code}\n' https://download.shellx.pro/desktop/0.0.0/none`
   prints `404`.

### 4. GitHub

1. Add the 13 secrets above.
2. Recommended: Settings → Rules → Rulesets → **New tag ruleset** targeting `desktop-v*`,
   restricting creation and deletion to maintainers.
3. Run one dry run (next section, step 2) to validate the toolchain before the first real release.

## Releasing version X.Y.Z

1. Set `version: X.Y.Z+N` in `apps/desktop/pubspec.yaml` (increase `N` every release), merge to
   `main`, wait for CI.
2. **Dry run:** Actions → Release desktop → Run workflow → branch `main`, version `X.Y.Z`,
   `dry_run` checked. Download the `macos-dmg` and `windows-installer` artifacts and smoke-test them
   (macOS: right-click → Open, because the dry-run app is ad-hoc signed; Windows: SmartScreen →
   More info → Run anyway): the agent starts in the tray, you can sign in, pair a phone and open a
   session.
3. **Tag:** `git switch main && git pull && git tag desktop-vX.Y.Z && git push origin desktop-vX.Y.Z`.
4. Wait for the run to finish. Its summary lists both public URLs with SHA-256 hashes. On a clean
   Mac, download the dmg in a browser, drag ShellX to Applications and open it: macOS must show only
   the standard "downloaded from the Internet" prompt. On Windows, the installer's signature must
   show the publisher.
5. **Relay:** in `relay/wrangler.jsonc`, edit the `vars` of the production environment
   (`env.production.vars`), which feed `GET /v1/version`:
   - `LATEST_AGENT_VERSION` → `X.Y.Z`
   - `MAC_URL` → `https://download.shellx.pro/desktop/X.Y.Z/ShellX-X.Y.Z.dmg`
   - `WIN_URL` → `https://download.shellx.pro/desktop/X.Y.Z/ShellX-Setup-X.Y.Z.exe`
   - `MIN_AGENT` / `MIN_MOBILE` → raise only to force older agents / mobile apps to update.

   Deploy the relay to production (see `relay/README.md`), then check that
   `curl -s https://relay.shellx.pro/v1/version` shows `"version":"X.Y.Z"` and both URLs under
   `latest_agent`. Running agents show the update notice within 24 hours.
6. **Website:** set `"desktopVersion": "X.Y.Z"` in `web/src/site.config.json`, run
   `npm ci && CHECK_DOWNLOADS=1 npm run build` in `web/` (the "installer URLs are live" check must
   pass), merge to `main`. Cloudflare Pages deploys it.

Order matters: installers first, then the relay (which tells running agents to update), then the
website. The relay and the website must never link to files that are not on R2 yet.

## When something goes wrong

- **Build, signing or notarization failed:** nothing was uploaded (`publish` runs only after both
  platform jobs succeed). `notarize.sh` prints the notary log; the usual cause is nested code
  without hardened runtime or a secure timestamp. Fix it, then move the tag:
  `git push --delete origin desktop-vX.Y.Z && git tag -f desktop-vX.Y.Z && git push origin desktop-vX.Y.Z`.
- **`publish` failed after uploading one file:** delete it with
  `npx wrangler@4.139.0 r2 object delete shellx-downloads/desktop/X.Y.Z/<file> --remote`, then
  **Re-run failed jobs**.
- **A broken installer was published:** do not overwrite it. Objects are served with
  `Cache-Control: immutable` for a year and `publish` refuses existing versions. Release
  `X.Y.(Z+1)`.
````

- [ ] **Step 5: Kiểm README liệt kê đúng mọi secret mà workflow dùng**

Run:

```bash
diff <(grep -oE 'secrets\.[A-Z0-9_]+' .github/workflows/release-desktop.yml | sed 's/secrets\.//' | sort -u) \
     <(grep -oE '^\| `[A-Z0-9_]+` \|' release/README.md | tr -d '|` ' | sort -u) && echo secrets-documented
```

Expected: `secrets-documented` (không có dòng khác biệt nào).

- [ ] **Step 6: Commit tài liệu**

```bash
git add release/README.md
git commit -m "docs(release): list release secrets and the manual release procedure"
```

Kiểm thử chấp nhận sau khi merge vào `main` (cần GitHub, người thực hiện có quyền repo): Actions → Release desktop → Run workflow → `main`, version = phiên bản trong `apps/desktop/pubspec.yaml`, `dry_run` bật. Expected: `prepare`, `macos`, `windows` xanh; `publish` bị skip; run có hai artifact `macos-dmg` và `windows-installer`.

---

### Task 7: Workflow CI

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: lệnh test chuẩn của overview §3 (plan 01–05); `release/tests/*.test.mjs`, `release/macos/*.sh` (Task 3–5); `release/windows/build-installer.ps1` (Task 5); `web` `npm run build` (Task 1–2).
- Produces: workflow `CI` (push `main`, mọi pull request, `workflow_dispatch`) với job `changes`, `dart`, `relay`, `e2e`, `desktop` (matrix `macos-latest`/`windows-latest`), `mobile`, `web`, `release`, `installer`, và job tổng hợp `ci-ok` ("CI result") — đặt **một** status check bắt buộc này trong branch protection của `main`, vì các job bị path filter bỏ qua báo "skipped".

Path filter: thay đổi trong `packages/**`, `pubspec.yaml`, `analysis_options.yaml` hoặc chính `ci.yml` chạy mọi job Dart/Flutter (desktop và mobile phụ thuộc các package); `relay/**` chạy `relay` và `e2e`; `web/**` chạy `web`; `release/**` hoặc bất kỳ workflow nào chạy `release` và `installer`. `workflow_dispatch` chạy tất cả. Job `e2e` cần relay chạy thật nên khởi động `npm run dev` ở nền, đợi `GET /v1/version` trả 200 (tối đa 120 s, dừng sớm nếu tiến trình chết) rồi mới chạy `dart test` với `SHELLX_E2E_RELAY`.

- [ ] **Step 1: Viết workflow**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

env:
  FLUTTER_VERSION: 3.41.7
  NODE_VERSION: 22
  ASTRO_TELEMETRY_DISABLED: 1
  WRANGLER_SEND_METRICS: false

jobs:
  changes:
    name: Detect changed areas
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: read
    outputs:
      dart: ${{ github.event_name == 'workflow_dispatch' || steps.filter.outputs.dart }}
      relay: ${{ github.event_name == 'workflow_dispatch' || steps.filter.outputs.relay }}
      e2e: ${{ github.event_name == 'workflow_dispatch' || steps.filter.outputs.e2e }}
      desktop: ${{ github.event_name == 'workflow_dispatch' || steps.filter.outputs.desktop }}
      mobile: ${{ github.event_name == 'workflow_dispatch' || steps.filter.outputs.mobile }}
      web: ${{ github.event_name == 'workflow_dispatch' || steps.filter.outputs.web }}
      release: ${{ github.event_name == 'workflow_dispatch' || steps.filter.outputs.release }}
    steps:
      - uses: actions/checkout@v7
      - uses: dorny/paths-filter@v4
        id: filter
        with:
          filters: |
            dart_shared: &dart_shared
              - 'pubspec.yaml'
              - 'analysis_options.yaml'
              - 'packages/**'
              - '.github/workflows/ci.yml'
            dart:
              - *dart_shared
            relay:
              - 'relay/**'
              - '.github/workflows/ci.yml'
            e2e:
              - *dart_shared
              - 'relay/**'
            desktop:
              - *dart_shared
              - 'apps/desktop/**'
            mobile:
              - *dart_shared
              - 'apps/mobile/**'
            web:
              - 'web/**'
              - '.github/workflows/ci.yml'
            release:
              - 'release/**'
              - '.github/workflows/**'

  dart:
    name: Dart packages
    needs: changes
    if: needs.changes.outputs.dart == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: ${{ env.FLUTTER_VERSION }}
          cache: true
      - name: Resolve the pub workspace
        run: flutter pub get
      - name: shellx_core
        working-directory: packages/shellx_core
        run: dart test
      - name: shellx_agent
        working-directory: packages/shellx_agent
        run: dart test
      - name: shellx_client
        working-directory: packages/shellx_client
        run: dart test

  relay:
    name: Relay
    needs: changes
    if: needs.changes.outputs.relay == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 20
    defaults:
      run:
        working-directory: relay
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: npm
          cache-dependency-path: relay/package-lock.json
      - run: npm ci
      - run: npm test

  e2e:
    name: End-to-end (agent + client + local relay)
    needs: changes
    if: needs.changes.outputs.e2e == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 25
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: npm
          cache-dependency-path: relay/package-lock.json
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: ${{ env.FLUTTER_VERSION }}
          cache: true
      - name: Install relay dependencies
        working-directory: relay
        run: npm ci
      - name: Start relay on 127.0.0.1:8787
        working-directory: relay
        run: |
          nohup npm run dev -- --ip 127.0.0.1 --port 8787 > "$RUNNER_TEMP/relay.log" 2>&1 &
          echo "RELAY_PID=$!" >> "$GITHUB_ENV"
      - name: Wait until GET /v1/version answers 200
        run: |
          for second in $(seq 1 120); do
            if curl -sf -o /dev/null http://127.0.0.1:8787/v1/version; then
              echo "relay ready after ${second}s"
              exit 0
            fi
            if ! kill -0 "$RELAY_PID" 2> /dev/null; then
              echo "::error::npm run dev exited before the relay became ready"
              cat "$RUNNER_TEMP/relay.log"
              exit 1
            fi
            sleep 1
          done
          echo "::error::relay did not answer http://127.0.0.1:8787/v1/version within 120 s"
          cat "$RUNNER_TEMP/relay.log"
          exit 1
      - name: Resolve the pub workspace
        run: flutter pub get
      - name: shellx_e2e
        working-directory: packages/shellx_e2e
        env:
          SHELLX_E2E_RELAY: http://127.0.0.1:8787
        run: dart test
      - name: Relay log
        if: always()
        run: cat "$RUNNER_TEMP/relay.log" || true

  desktop:
    name: Desktop (${{ matrix.device }})
    needs: changes
    if: needs.changes.outputs.desktop == 'true'
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: macos-latest
            device: macos
          - os: windows-latest
            device: windows
    runs-on: ${{ matrix.os }}
    timeout-minutes: 45
    defaults:
      run:
        working-directory: apps/desktop
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: ${{ env.FLUTTER_VERSION }}
          cache: true
      - run: flutter pub get
      - name: Widget tests
        run: flutter test
      - name: Integration tests (real PTY)
        run: flutter test integration_test -d ${{ matrix.device }}

  mobile:
    name: Mobile widget tests
    needs: changes
    if: needs.changes.outputs.mobile == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 20
    defaults:
      run:
        working-directory: apps/mobile
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: ${{ env.FLUTTER_VERSION }}
          cache: true
      - run: flutter pub get
      - run: flutter test

  web:
    name: Website
    needs: changes
    if: needs.changes.outputs.web == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 10
    defaults:
      run:
        working-directory: web
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: npm
          cache-dependency-path: web/package-lock.json
      - run: npm ci
      - name: Build and check pages/links
        run: npm run build

  release:
    name: Release tooling
    needs: changes
    if: needs.changes.outputs.release == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: ${{ env.NODE_VERSION }}
      - name: Release script tests (macOS-only tests skip here)
        run: node --test release/tests/*.test.mjs
      - name: shellcheck
        run: shellcheck release/macos/*.sh
      - name: actionlint
        run: |
          bash <(curl -sSfL https://raw.githubusercontent.com/rhysd/actionlint/v1.7.12/scripts/download-actionlint.bash) 1.7.12 "$RUNNER_TEMP"
          "$RUNNER_TEMP/actionlint" -color

  installer:
    name: Installer compiles (Inno Setup)
    needs: changes
    if: needs.changes.outputs.release == 'true'
    runs-on: windows-latest
    timeout-minutes: 15
    defaults:
      run:
        shell: pwsh
    steps:
      - uses: actions/checkout@v7
      - name: Compile shellx.iss against a stand-in app folder
        run: |
          $source = Join-Path $env:RUNNER_TEMP 'fake-release'
          New-Item -ItemType Directory -Force -Path (Join-Path $source 'data') | Out-Null
          Copy-Item "$env:SystemRoot\System32\whoami.exe" (Join-Path $source 'ShellX.exe')
          Set-Content -Path (Join-Path $source 'data\placeholder.txt') -Value 'stand-in for flutter_assets'
          ./release/windows/build-installer.ps1 -Version 0.0.0 -SourceDir $source -OutputDir (Join-Path $env:RUNNER_TEMP 'installer')

  ci-ok:
    name: CI result
    needs: [changes, dart, relay, e2e, desktop, mobile, web, release, installer]
    if: always()
    runs-on: ubuntu-latest
    steps:
      - name: Fail if any job failed or was cancelled
        if: contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled')
        run: |
          echo "::error::At least one CI job failed or was cancelled"
          exit 1
      - run: echo "All required jobs passed or were skipped (no relevant changes)."
```

- [ ] **Step 2: Lint cả hai workflow**

Run (đoạn "Công cụ lint" ở đầu plan, rồi):

```bash
PATH="${TMPDIR:-/tmp}/shellx-tools:$PATH" actionlint -color .github/workflows/*.yml && echo actionlint-ok
```

Expected: `actionlint-ok`.

- [ ] **Step 3: Kiểm CI gọi đúng lệnh test chuẩn và phiên bản đã chốt**

Run:

```bash
for needle in 'working-directory: packages/shellx_core' 'working-directory: packages/shellx_agent' \
  'working-directory: packages/shellx_client' 'working-directory: packages/shellx_e2e' \
  'SHELLX_E2E_RELAY: http://127.0.0.1:8787' 'run: npm test' 'run: flutter test' \
  'flutter test integration_test -d ${{ matrix.device }}' 'run: npm run build' \
  'FLUTTER_VERSION: 3.41.7' 'NODE_VERSION: 22' 'os: macos-latest' 'os: windows-latest'; do
  grep -qF -- "$needle" .github/workflows/ci.yml || echo "MISSING: $needle"
done; echo checked
```

Expected: chỉ một dòng `checked`.

- [ ] **Step 4: Chạy cục bộ những job chạy được ngay**

Run:

```bash
(cd web && npm ci && npm run build) && node --test release/tests/*.test.mjs && "${TMPDIR:-/tmp}/shellx-tools/shellcheck" release/macos/*.sh && echo local-ci-ok
```

Expected: web `ℹ pass 16`, `ℹ skipped 1`; release `ℹ tests 24`, `ℹ pass 24` trên macOS (trên Linux: `ℹ pass 21`, `ℹ skipped 3`); cuối cùng `local-ci-ok`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add CI workflow for packages, relay, e2e, apps, website and release tooling"
```

Ghi chú: các job `dart`, `relay`, `e2e`, `desktop`, `mobile` chỉ xanh khi plan 01–05 đã được merge (thư mục của chúng tồn tại). Lần chạy CI đầy đủ đầu tiên là pull request `feat/shellx-v1` → `main`; sau khi xanh, bật branch protection với status check bắt buộc "CI result".

---

## Self-review (đã chạy khi viết plan)

- **Phủ spec:** §11 (Astro tĩnh, Pages, trang chủ + link tải 4 nền tảng, `/privacy`, `/terms`, song ngữ) → Task 1–2; §14 CI (5 nhóm test) → Task 7; §14 macOS dmg + Developer ID + notarytool, §8.5 hardened runtime/không sandbox → Task 4, 6; §14 Windows Inno Setup + ký → Task 5, 6; §14 R2 `desktop/<version>/…` qua `download.shellx.pro` → Task 6; §14 store trỏ `https://shellx.pro/privacy` → Task 2 README; §3.1 Windows 1809+ → `MinVersion=10.0.17763` (Task 5); §3.2 không push/analytics → nội dung + test "no third-party scripts" (Task 2).
- **Mọi file có nội dung đầy đủ** và đã được build/test thử trong thư mục nháp: web `npm run build` 16 pass + 1 skip; `node --test release/tests/*.test.mjs` 24 pass trên macOS; shellcheck sạch; actionlint sạch cho cả hai workflow. Riêng `shellx.iss`/`build-installer.ps1` chưa biên dịch được trên macOS — job `installer` ở Task 7 là nơi kiểm thật.
- **Tên khớp giữa các task:** `resolve-version.mjs` → `version`/`dry_run`; `MACOS_SIGNING_IDENTITY`, `MACOS_KEYCHAIN`, `APPLE_API_KEY_PATH`, `APP`; `RELEASE_DIR`, `SETUP_EXE`; tên cố định `ShellX.app` (`pro.shellx.desktop`), `ShellX.exe`, giá trị Run `ShellX`; artifact `macos-dmg`, `windows-installer`; mẫu tên file `ShellX-<v>.dmg`, `ShellX-Setup-<v>.exe` giống nhau ở web test, `.iss`, workflow và README.
