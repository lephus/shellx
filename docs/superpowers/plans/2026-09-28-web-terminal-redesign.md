# Web Terminal Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the shellx.pro marketing site as a full-page terminal experience (modern dark + cyan) with a complete technical-SEO package, without breaking any published promise or deploy contract.

**Architecture:** The whole home page is one semantic-HTML "terminal session" — six command→output blocks inside a terminal window chrome — styled by CSS and progressively enhanced by ~3 KB of vanilla JS (typing effect). Legal pages keep readable prose and inherit the dark theme through CSS variables. SEO is static: meta/OG in `Base.astro`, a hand-rolled `sitemap.xml` endpoint, static `robots.txt`, committed OG images, JSON-LD on home pages.

**Tech Stack:** Astro 7 (already present), zero new npm dependencies, self-hosted JetBrains Mono (OFL), vanilla JS + CSS.

**Spec:** `docs/superpowers/specs/2026-09-28-web-terminal-redesign-design.md`

## Global Constraints

- Zero new entries in `web/package.json` `dependencies`/`devDependencies`.
- No `<script src>`, `<link href>`, `src=` or `url()` pointing to any origin other than the page's own (`https://shellx.pro` or relative). Anchors (`<a href>`) to `download.shellx.pro`, `mailto:` and stores are allowed. Enforced by a test (Task 1).
- URL structure frozen: `/`, `/en/`, `/privacy/`, `/terms/`, `/en/privacy/`, `/en/terms/`, `404.html`. No new pages except `/sitemap.xml` and static assets.
- Contracts old tests rely on stay intact: installer hrefs from `site.config.json`, `data-platform="macos|windows"`, `data-store="app-store|google-play"` with `aria-disabled="true"` when the URL is null.
- `web/scripts/check-placeholders.mjs` and the `[quốc gia]` guard: untouched.
- Every new user-facing string exists in BOTH `vi` and `en` in `web/src/i18n/ui.ts` (the `Strings` type enforces parity at build).
- Dark theme only (`color-scheme: dark`); pricing statement: "ShellX hiện miễn phí" / "ShellX is currently free"; JSON-LD `offers` price `"0"`.
- All commands below run from `web/` unless stated; build must stay green after every task: `npm run build` (runs placeholder check + astro build + node tests).
- Node >= 22.12 (`web/.node-version`); run `npm ci` once before Task 1.

## Review Focus

1. A crawler or no-JS browser must see the complete marketing content — pinned by the static-content test in Task 3.
2. `#delete-account` on both privacy pages (linked from the mobile app flow and policy text) must survive the re-skin — pinned by the anchor test in Task 1.
3. `prefers-reduced-motion: reduce` must fully disable the typing animation — guarded first-line in the script (Task 4), verified in the browser in Task 6.
4. A 320 px viewport must not horizontally scroll the terminal frame — verified in the browser in Task 6.
5. Vietnamese diacritics must render in JetBrains Mono itself (no fallback-font mixing mid-word) — verified visually in Task 6 (JetBrains Mono ships Vietnamese glyphs since v2.0).

---

### Task 1: Fonts + dark terminal theme in Base, Legal re-skin, external-origin guard

**Files:**
- Create: `web/public/fonts/JetBrainsMono-Regular.woff2`, `web/public/fonts/JetBrainsMono-Bold.woff2`
- Create: `third_party/jetbrains-mono/OFL.txt`
- Modify: `web/src/layouts/Base.astro` (global styles, header/footer, font-face, preload)
- Modify: `web/src/layouts/Legal.astro` (prose stays sans)
- Test: `web/tests/site.test.mjs`

**Interfaces:**
- Produces CSS variables every later task uses: `--bg #0b1120`, `--fg #e2e8f0`, `--muted #94a3b8`, `--accent #22d3ee`, `--ok #4ade80`, `--card #0f172a`, `--border #1e293b`, `--mono` (JetBrains Mono stack), `--sans` (system-ui stack).
- Produces helper class `.wrap` (unchanged max-width 52rem) that Task 2 wraps the terminal in.

- [ ] **Step 1: Fetch the fonts and license**

```bash
cd web
curl -L -o /tmp/jbmono.zip https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip
unzip -l /tmp/jbmono.zip | grep -E 'woff2|OFL'   # confirm paths before extracting
unzip -j /tmp/jbmono.zip 'fonts/webfonts/JetBrainsMono-Regular.woff2' 'fonts/webfonts/JetBrainsMono-Bold.woff2' -d public/fonts
mkdir -p ../third_party/jetbrains-mono
unzip -j /tmp/jbmono.zip 'OFL.txt' -d ../third_party/jetbrains-mono
```

If a path differs in the listing, use the listed path; the two woff2 weights and the OFL license are what matter.

Deviation from the spec noted on purpose: the spec aimed for a ~60 KB subset, but subsetting needs an extra tool (fonttools). We commit the full woff2 files (~95 KB each) instead — cached after first visit, and Task 6's Performance ≥ 95 gate is the real arbiter. If Lighthouse misses the target because of fonts, subset then.

- [ ] **Step 2: Write the failing tests** — append to `web/tests/site.test.mjs`:

```js
const allPages = ['/', '/en/', '/privacy/', '/terms/', '/en/privacy/', '/en/terms/', '/404.html'];

test('no external scripts, styles, fonts or media on any page', () => {
  for (const p of allPages) {
    const html = readPage(p);
    for (const m of html.matchAll(/<(script|link|img|source|iframe)\b[^>]*\b(?:src|href)="(https?:)?\/\/(?!shellx\.pro)/g)) {
      assert.fail(`${p}: external resource in ${m[0].slice(0, 120)}`);
    }
  }
});

test('every page has exactly one h1', () => {
  for (const p of allPages) {
    const count = (readPage(p).match(/<h1[\s>]/g) ?? []).length;
    assert.equal(count, 1, `${p} has ${count} h1`);
  }
});

test('privacy pages keep the #delete-account anchor', () => {
  for (const p of ['/privacy/', '/en/privacy/']) {
    assert.match(readPage(p), /id="delete-account"/);
  }
});

test('self-hosted font files exist and are preloaded', () => {
  assert.ok(existsSync(join(dist, 'fonts/JetBrainsMono-Regular.woff2')));
  assert.ok(existsSync(join(dist, 'fonts/JetBrainsMono-Bold.woff2')));
  assert.match(readPage('/'), /rel="preload" as="font"[^>]*JetBrainsMono-Regular\.woff2/);
});
```

Note: `404.html` currently has TWO h1-like headings (h1 vi + h2 en) — it already passes; do not "fix" it into two h1s.

- [ ] **Step 3: Run tests, verify the new ones fail** — `npm run build` → font/preload tests FAIL (fonts not wired), external-origin and h1 tests PASS already (baseline is self-contained). That is expected: this task's red is the font wiring.

- [ ] **Step 4: Rewrite Base.astro theme** — replace the whole `<style is:global>` and the header/footer markup; head gains preload + font-face. Keep the existing head meta (canonical/hreflang) untouched.

```astro
<head> additions (inside existing <head>):
    <link rel="preload" as="font" type="font/woff2" href="/fonts/JetBrainsMono-Regular.woff2" crossorigin />
```

```astro
<body markup replacement:
  <header class="wrap top">
    <a class="brand" href={pathFor(lang, 'home')}><span aria-hidden="true">~/</span>shellx</a>
    <a class="lang-switch" href={switchHref} hreflang={other} lang={other}
      ><span aria-hidden="true">--lang=</span>{other}</a>
  </header>
  (main/footer structure unchanged; footer keeps the same three links + ©)
```

```css
<style is:global> replacement:
  @font-face {
    font-family: 'JetBrains Mono';
    src: url('/fonts/JetBrainsMono-Regular.woff2') format('woff2');
    font-weight: 400; font-style: normal; font-display: swap;
  }
  @font-face {
    font-family: 'JetBrains Mono';
    src: url('/fonts/JetBrainsMono-Bold.woff2') format('woff2');
    font-weight: 700; font-style: normal; font-display: swap;
  }
  :root {
    color-scheme: dark;
    --bg: #0b1120; --fg: #e2e8f0; --muted: #94a3b8;
    --accent: #22d3ee; --ok: #4ade80; --card: #0f172a; --border: #1e293b;
    --mono: 'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    --sans: system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: var(--bg); color: var(--fg);
    font-family: var(--mono); line-height: 1.7; font-size: 0.95rem;
  }
  a { color: var(--accent); }
  a:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
  .wrap { max-width: 52rem; margin: 0 auto; padding: 0 1rem; }
  .top { display: flex; justify-content: space-between; align-items: center;
         padding-top: 1rem; padding-bottom: 1rem; }
  .brand { font-weight: 700; font-size: 1.1rem; color: var(--fg); text-decoration: none; }
  .brand span, .lang-switch span { color: var(--muted); }
  .lang-switch { text-decoration: none; }
  .bottom { margin-top: 3rem; padding-top: 1rem; padding-bottom: 2rem;
            border-top: 1px solid var(--border); color: var(--muted); font-size: 0.85rem; }
  .bottom nav { display: flex; flex-wrap: wrap; gap: 0.5rem 1.5rem; }
  code { font-family: var(--mono); font-size: 0.9em; }
```

- [ ] **Step 5: Legal prose stays sans** — in `web/src/layouts/Legal.astro` style block add:

```css
  .legal { font-family: var(--sans); font-size: 1rem; }
  .legal :global(code) { font-family: var(--mono); }
```

- [ ] **Step 6: Run `npm run build`** — all tests PASS (old + new). Eyeball `npm run dev` once: dark pages, mono header, legal pages readable.

- [ ] **Step 7: Commit**

```bash
git add web/public/fonts third_party/jetbrains-mono web/src/layouts web/tests/site.test.mjs
git commit -m "feat(web): dark terminal theme, self-hosted JetBrains Mono, origin-guard tests"
```

---

### Task 2: Terminal window components + Home rebuilt with existing copy

**Files:**
- Create: `web/src/components/Terminal.astro`, `web/src/components/TermBlock.astro`
- Modify: `web/src/components/Home.astro`, `web/src/components/Downloads.astro` (re-skin only), `web/src/pages/404.astro`
- Test: `web/tests/site.test.mjs`

**Interfaces:**
- Consumes CSS vars from Task 1.
- Produces `<Terminal title?>` (window chrome, default title `shellx@pro — zsh`) and `<TermBlock command id?>` (renders `$ <command>` then the slot as output; root element carries `data-term-block`, the command text sits in `<span data-cmd>`, the output in `<div data-out>` — Task 4's script keys on exactly these three attributes).

- [ ] **Step 1: Write the failing test** — append:

```js
test('home is a terminal session: window chrome + command blocks', () => {
  for (const p of ['/', '/en/']) {
    const html = readPage(p);
    assert.match(html, /shellx@pro/);
    assert.ok((html.match(/data-term-block/g) ?? []).length >= 3, `${p}: too few term blocks`);
    assert.match(html, /data-cmd/);
  }
});
```

- [ ] **Step 2: Run `npm run build`** — new test FAILS (no terminal markup yet).

- [ ] **Step 3: Create the components**

`web/src/components/Terminal.astro`:

```astro
---
interface Props { title?: string }
const { title = 'shellx@pro — zsh' } = Astro.props;
---
<div class="term">
  <div class="term-bar">
    <span class="dots" aria-hidden="true"><i></i><i></i><i></i></span>
    <span class="term-title">{title}</span>
  </div>
  <div class="term-body"><slot /></div>
</div>
<style>
  .term { border: 1px solid var(--border); border-radius: 0.6rem; background: var(--card);
          margin-top: 1.5rem; overflow: hidden; }
  .term-bar { display: flex; align-items: center; gap: 0.75rem; padding: 0.5rem 0.9rem;
              border-bottom: 1px solid var(--border); color: var(--muted); font-size: 0.8rem; }
  .dots { display: inline-flex; gap: 0.4rem; }
  .dots i { width: 0.7rem; height: 0.7rem; border-radius: 50%; background: var(--border); }
  .dots i:first-child { background: #f87171; }
  .dots i:nth-child(2) { background: #fbbf24; }
  .dots i:last-child { background: var(--ok); }
  .term-body { padding: 0.5rem 1rem 1.5rem; overflow-wrap: break-word; }
</style>
```

`web/src/components/TermBlock.astro`:

```astro
---
interface Props { command: string; id?: string }
const { command, id } = Astro.props;
---
<section class="tb" id={id} data-term-block>
  <p class="tb-prompt"><span class="ps1" aria-hidden="true">$&nbsp;</span><span class="tb-cmd" data-cmd>{command}</span></p>
  <div class="tb-out" data-out><slot /></div>
</section>
<style>
  .tb { margin-top: 1.75rem; }
  .tb-prompt { margin: 0; color: var(--accent); font-weight: 700; }
  .ps1 { color: var(--muted); }
  .tb-out { margin-top: 0.4rem; }
  .tb-out :global(h1), .tb-out :global(h2) { font-size: 1.15rem; margin: 0.5rem 0; }
  .tb :global(h1) { font-size: 1.5rem; }
  .tb-out :global(ul), .tb-out :global(ol) { padding-left: 1.4rem; margin: 0.5rem 0; }
  .tb-out :global(li) { margin: 0.3rem 0; }
</style>
```

- [ ] **Step 4: Rebuild Home.astro with the EXISTING copy only** (new sections come in Task 3):

```astro
---
import Base from '../layouts/Base.astro';
import Terminal from './Terminal.astro';
import TermBlock from './TermBlock.astro';
import Downloads from './Downloads.astro';
import { ui, type Lang } from '../i18n/ui';

interface Props { lang: Lang }
const { lang } = Astro.props;
const t = ui[lang];
---
<Base lang={lang} page="home" title={t.homeTitle} description={t.homeDescription}>
  <Terminal>
    <TermBlock command="shellx connect">
      <p class="status"><span aria-hidden="true">✓ </span>{t.heroStatus}</p>
      <h1>{t.tagline}</h1>
      <p>{t.intro}</p>
      <p class="e2e">{t.e2e}</p>
    </TermBlock>
    <TermBlock command="shellx pair --qr">
      <h2>{t.stepsHeading}</h2>
      <ol>
        <li>{t.step1}</li>
        <li>{t.step2}</li>
        <li>{t.step3}</li>
      </ol>
    </TermBlock>
    <TermBlock command="shellx download" id="download">
      <Downloads lang={lang} />
    </TermBlock>
  </Terminal>
</Base>
<style>
  .status { color: var(--ok); margin: 0.25rem 0 0; }
  .e2e { padding: 0.6rem 0.9rem; border-left: 3px solid var(--accent); background: var(--bg); }
</style>
```

Add ONE new i18n key now (both languages) in `web/src/i18n/ui.ts`:

```ts
// vi:
heroStatus: 'đã ghép nối · mã hóa đầu cuối',
// en:
heroStatus: 'paired · end-to-end encrypted',
```

- [ ] **Step 5: Re-skin Downloads.astro** — markup and attributes stay byte-compatible with the old tests (`data-platform`, `data-store`, `aria-disabled`, same hrefs); only its `<style>` changes: `border-radius: 0.4rem`, `background: var(--bg)`, `border-color: var(--border)`, hover `border-color: var(--accent)`, `h2 { font-size: 1.15rem }`. Nothing else.

- [ ] **Step 6: Re-skin 404.astro** into command-not-found (keep the vi h1 + en h2 shape):

```astro
<Base lang="vi" page={null} title={`${vi.notFoundTitle} — ShellX`} description={vi.notFoundBody}>
  <Terminal title="shellx@pro — 404">
    <TermBlock command="open …">
      <p class="err" aria-hidden="true">zsh: command not found</p>
      <h1>{vi.notFoundTitle}</h1>
      <p>{vi.notFoundBody} <a href="/">{vi.backHome}</a></p>
      <div lang="en">
        <h2>{en.notFoundTitle}</h2>
        <p>{en.notFoundBody} <a href="/en/">{en.backHome}</a></p>
      </div>
    </TermBlock>
  </Terminal>
</Base>
<style> .err { color: #f87171; margin: 0.25rem 0 0; } </style>
```

(Imports: add `Terminal` and `TermBlock` to the existing import block.)

- [ ] **Step 7: Run `npm run build`** — ALL tests pass (old installer/store tests prove the contract survived).

- [ ] **Step 8: Commit**

```bash
git add web/src/components web/src/pages/404.astro web/src/i18n/ui.ts web/tests/site.test.mjs
git commit -m "feat(web): terminal window components; home and 404 rebuilt as a terminal session"
```

---

### Task 3: New marketing content — features, security, FAQ (vi + en)

**Files:**
- Modify: `web/src/i18n/ui.ts`, `web/src/components/Home.astro`
- Test: `web/tests/site.test.mjs`

**Interfaces:**
- Consumes `TermBlock` from Task 2.
- Produces i18n keys used only here: `featuresHeading`, `feature1..feature6`, `securityHeading`, `security1..security4`, `securityMore`, `faqHeading`, `faqQ1..faqQ5`, `faqA1..faqA5`.

- [ ] **Step 1: Write the failing test** — append:

```js
test('home carries the full marketing content statically (no JS needed)', () => {
  const checks = [
    ['/', ['Tính năng', 'Bảo mật', 'Câu hỏi thường gặp', 'argon2id', 'mã QR', 'miễn phí']],
    ['/en/', ['Features', 'Security', 'FAQ', 'argon2id', 'QR code', 'free']],
  ];
  for (const [p, needles] of checks) {
    const html = readPage(p);
    for (const n of needles) assert.ok(html.includes(n), `${p} missing "${n}"`);
    assert.ok((html.match(/<details[\s>]/g) ?? []).length >= 4, `${p}: FAQ needs >= 4 <details>`);
  }
});
```

- [ ] **Step 2: Run `npm run build`** — FAILS (content absent).

- [ ] **Step 3: Add the strings to `ui.ts`** — vi block (en mirrors it; the `Strings` type forces completeness):

```ts
  featuresHeading: 'Tính năng',
  feature1: 'Mở và điều khiển terminal của máy Mac hoặc PC từ điện thoại, ở bất kỳ đâu có Internet.',
  feature2: 'Mã hóa đầu cuối bằng giao thức Noise — máy chủ chuyển tiếp không đọc được nội dung.',
  feature3: 'Không cần mở port trên router, không cần IP tĩnh hay VPN.',
  feature4: 'Nhiều phiên terminal cùng lúc, chuyển qua lại như đang ngồi trước máy.',
  feature5: 'Ghép nối điện thoại với máy tính bằng mã QR; khóa bí mật không bao giờ rời thiết bị.',
  feature6: 'Agent cho macOS và Windows; app cho iOS và Android.',
  securityHeading: 'Bảo mật',
  security1: 'Nội dung terminal được mã hóa đầu cuối: chỉ điện thoại và máy tính của bạn giải mã được.',
  security2: 'Máy chủ chuyển tiếp chỉ thấy gói dữ liệu đã mã hóa — không bao giờ thấy lệnh hay kết quả.',
  security3: 'Mật khẩu được băm bằng argon2id; mã truy cập chỉ lưu ở dạng băm SHA-256.',
  security4: 'Không log nội dung terminal, không analytics, không cookie.',
  securityMore: 'Chi tiết trong Chính sách quyền riêng tư',
  faqHeading: 'Câu hỏi thường gặp',
  faqQ1: 'Tôi có cần mở port trên router hay IP tĩnh không?',
  faqA1: 'Không. Agent trên máy tính và app trên điện thoại đều tự kết nối ra máy chủ chuyển tiếp, nên không cần mở port, không cần IP tĩnh hay VPN.',
  faqQ2: 'Điện thoại mất mạng giữa chừng thì sao?',
  faqA2: 'Agent giữ tối đa 256 KiB output gần nhất của mỗi phiên trong bộ nhớ máy tính; khi điện thoại kết nối lại, phần output phát sinh trong lúc mất mạng được phát lại.',
  faqQ3: 'ShellX lưu những dữ liệu gì trên máy chủ?',
  faqA3: 'Chỉ email, mật khẩu đã băm, thông tin thiết bị và bản ghi ghép nối. Nội dung terminal được mã hóa đầu cuối nên máy chủ không đọc được và không lưu.',
  faqQ4: 'ShellX có mất phí không?',
  faqA4: 'ShellX hiện miễn phí.',
  faqQ5: 'ShellX chạy trên nền tảng nào?',
  faqA5: 'Agent: macOS 12 trở lên, Windows 10 (bản 1809) trở lên. App: iOS 15 trở lên, Android 8.0 trở lên.',
```

en equivalents (same keys): `'Features'`, `'Open and control your Mac or PC terminal from your phone, anywhere with an Internet connection.'`, `'End-to-end encrypted with the Noise protocol — the relay cannot read the content.'`, `'No router ports to open, no static IP, no VPN.'`, `'Multiple terminal sessions at once, switch as if you were at the machine.'`, `'Pair phone and computer with a QR code; private keys never leave the device.'`, `'Agent for macOS and Windows; app for iOS and Android.'`, `'Security'`, `'Terminal content is end-to-end encrypted: only your phone and your computer can decrypt it.'`, `'The relay only ever sees encrypted frames — never commands or output.'`, `'Passwords are hashed with argon2id; access tokens are stored only as SHA-256 hashes.'`, `'No terminal-content logs, no analytics, no cookies.'`, `'Details in the Privacy Policy'`, `'FAQ'`, `'Do I need to open router ports or have a static IP?'`, `'No. Both the desktop agent and the phone app dial out to the relay, so there are no ports to open, no static IP, no VPN.'`, `'What if my phone loses its connection?'`, `'The agent keeps up to 256 KiB of each session's most recent output in your computer's memory; when the phone reconnects, the output produced while it was away is replayed.'`, `'What does ShellX store on its servers?'`, `'Only your email, a password hash, device information and pairing records. Terminal content is end-to-end encrypted, so the server cannot read or store it.'`, `'Does ShellX cost anything?'`, `'ShellX is currently free.'`, `'Which platforms does ShellX run on?'`, `'Agent: macOS 12 or later, Windows 10 (1809) or later. App: iOS 15 or later, Android 8.0 or later.'`

- [ ] **Step 4: Insert three TermBlocks into Home.astro** between the hero block and the pair block (features), and after downloads (faq); security between pair and download:

```astro
    <TermBlock command="shellx --features" id="features">
      <h2>{t.featuresHeading}</h2>
      <ul class="arrows">
        <li>{t.feature1}</li><li>{t.feature2}</li><li>{t.feature3}</li>
        <li>{t.feature4}</li><li>{t.feature5}</li><li>{t.feature6}</li>
      </ul>
    </TermBlock>

    <TermBlock command="shellx security" id="security">
      <h2>{t.securityHeading}</h2>
      <ul class="arrows">
        <li>{t.security1}</li><li>{t.security2}</li><li>{t.security3}</li><li>{t.security4}</li>
      </ul>
      <p><a href={pathFor(lang, 'privacy')}>{t.securityMore}</a></p>
    </TermBlock>

    <TermBlock command="shellx faq" id="faq">
      <h2>{t.faqHeading}</h2>
      {[[t.faqQ1, t.faqA1], [t.faqQ2, t.faqA2], [t.faqQ3, t.faqA3], [t.faqQ4, t.faqA4], [t.faqQ5, t.faqA5]].map(([q, a]) => (
        <details><summary>{q}</summary><p>{a}</p></details>
      ))}
    </TermBlock>
```

Add to Home's `<style>` (and import `pathFor` from `../i18n/ui`):

```css
  .arrows { list-style: none; padding-left: 0; }
  .arrows :global(li)::before { content: '→ '; color: var(--accent); }
  details { border: 1px solid var(--border); border-radius: 0.4rem; padding: 0.5rem 0.9rem; margin: 0.5rem 0; }
  summary { cursor: pointer; font-weight: 700; }
```

Section order in the file ends up: connect (hero) → features → pair → security → download → faq.

- [ ] **Step 5: Run `npm run build`** — all tests pass. TypeScript fails the build if the en block misses any key.

- [ ] **Step 6: Commit**

```bash
git add web/src/i18n/ui.ts web/src/components/Home.astro web/tests/site.test.mjs
git commit -m "feat(web): features, security and FAQ sections in vi and en"
```

---

### Task 4: Typing effect (progressive enhancement)

**Files:**
- Modify: `web/src/components/Home.astro` (inline `<script>` at the end), `web/src/components/TermBlock.astro` (effect CSS)
- Test: `web/tests/site.test.mjs`

**Interfaces:**
- Consumes `data-term-block`, `[data-cmd]`, `[data-out]` from Task 2. No other task depends on this script.

- [ ] **Step 1: Write the failing test** — append:

```js
test('typing effect ships, is tiny, and respects reduced motion', () => {
  const html = readPage('/');
  assert.match(html, /prefers-reduced-motion/);
  const inline = [...html.matchAll(/<script(?![^>]*src)[^>]*>([\s\S]*?)<\/script>/g)]
    .map((m) => m[1]).join('');
  assert.ok(inline.length > 0, 'no inline script found');
  assert.ok(inline.length < 8192, `inline JS too big: ${inline.length} bytes`);
});
```

- [ ] **Step 2: Run `npm run build`** — FAILS (no script yet).

- [ ] **Step 3: Add the script to Home.astro** (Astro inlines module scripts this small):

```html
<script>
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (!reduce && 'IntersectionObserver' in window) {
    const blocks = [...document.querySelectorAll('[data-term-block]')];
    for (const b of blocks) {
      const cmd = b.querySelector('[data-cmd]');
      b.dataset.full = cmd.textContent;
      cmd.textContent = '';
      b.classList.add('tb-pending');
    }
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        io.unobserve(e.target);
        type(e.target);
      }
    }, { rootMargin: '0px 0px -10% 0px' });
    blocks.forEach((b) => io.observe(b));
    function type(b) {
      const cmd = b.querySelector('[data-cmd]');
      const full = b.dataset.full;
      let i = 0;
      cmd.classList.add('typing');
      const tick = () => {
        cmd.textContent = full.slice(0, ++i);
        if (i < full.length) setTimeout(tick, 24);
        else {
          cmd.classList.remove('typing');
          b.classList.remove('tb-pending');
        }
      };
      tick();
    }
  }
</script>
```

- [ ] **Step 4: Add the effect CSS to TermBlock.astro** — hidden state exists only when JS added it, and uses `visibility` (space stays reserved → no CLS):

```css
  .tb.tb-pending :global(.tb-out) { visibility: hidden; }
  .tb-cmd.typing::after, .tb-prompt .tb-cmd:empty::after {
    content: '█'; color: var(--accent);
    animation: blink 1s steps(1) infinite;
  }
  @keyframes blink { 50% { opacity: 0; } }
  @media (prefers-reduced-motion: reduce) {
    .tb-cmd.typing::after { animation: none; }
  }
```

- [ ] **Step 5: Run `npm run build`** — all pass. Then `npm run dev`, scroll the page: commands type themselves, outputs appear; with System Settings → Accessibility → Reduce Motion ON, everything is instantly visible.

- [ ] **Step 6: Commit**

```bash
git add web/src/components/Home.astro web/src/components/TermBlock.astro web/tests/site.test.mjs
git commit -m "feat(web): scroll-triggered typing effect, reduced-motion safe"
```

---

### Task 5: SEO package — OG/Twitter meta, JSON-LD, robots, sitemap, OG images

**Files:**
- Create: `web/public/robots.txt`, `web/src/pages/sitemap.xml.ts`, `web/og-src/og-vi.svg`, `web/og-src/og-en.svg`, `web/public/og/og-vi.png`, `web/public/og/og-en.png`
- Modify: `web/src/layouts/Base.astro` (meta + head slot), `web/src/components/Home.astro` (JSON-LD)
- Test: `web/tests/site.test.mjs`

**Interfaces:**
- Consumes `pathFor`/`ui` from `src/i18n/ui.ts`.
- Produces `<slot name="head" />` inside Base's `<head>` (any page can inject head tags).

- [ ] **Step 1: Write the failing tests** — append:

```js
test('robots.txt and sitemap.xml exist; sitemap lists exactly the 6 pages', () => {
  assert.match(readFileSync(join(dist, 'robots.txt'), 'utf8'), /Sitemap: https:\/\/shellx\.pro\/sitemap\.xml/);
  const xml = readFileSync(join(dist, 'sitemap.xml'), 'utf8');
  const locs = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]).sort();
  assert.deepEqual(locs, [
    'https://shellx.pro/', 'https://shellx.pro/en/', 'https://shellx.pro/en/privacy/',
    'https://shellx.pro/en/terms/', 'https://shellx.pro/privacy/', 'https://shellx.pro/terms/',
  ]);
});

test('OG/Twitter meta and per-language OG image on every page', () => {
  for (const p of ['/', '/en/', '/privacy/', '/en/privacy/']) {
    const html = readPage(p);
    const og = p.startsWith('/en') ? '/og/og-en.png' : '/og/og-vi.png';
    assert.match(html, /property="og:title"/);
    assert.match(html, /name="twitter:card" content="summary_large_image"/);
    assert.ok(html.includes(`https://shellx.pro${og}`), `${p} wrong og:image`);
    assert.ok(existsSync(join(dist, og.slice(1))), `${og} missing from dist`);
  }
});

test('home JSON-LD parses and declares the free app', () => {
  for (const p of ['/', '/en/']) {
    const scripts = [...readPage(p).matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)];
    assert.ok(scripts.length >= 1, `${p}: JSON-LD missing`);
    const types = scripts.map((m) => JSON.parse(m[1])).map((d) => d['@type']);
    assert.ok(types.includes('SoftwareApplication'));
    const app = scripts.map((m) => JSON.parse(m[1])).find((d) => d['@type'] === 'SoftwareApplication');
    assert.equal(app.offers.price, '0');
  }
});
```

- [ ] **Step 2: Run `npm run build`** — the three new tests FAIL.

- [ ] **Step 3: `web/public/robots.txt`**

```
User-agent: *
Allow: /

Sitemap: https://shellx.pro/sitemap.xml
```

- [ ] **Step 4: `web/src/pages/sitemap.xml.ts`**

```ts
import type { APIRoute } from 'astro';
import { pathFor, type Lang, type Page } from '../i18n/ui';

const site = 'https://shellx.pro';
const pages: Page[] = ['home', 'privacy', 'terms'];
const langs: Lang[] = ['vi', 'en'];

export const GET: APIRoute = () => {
  const entries = pages.flatMap((page) =>
    langs.map((lang) => {
      const alts = langs
        .map((l) => `<xhtml:link rel="alternate" hreflang="${l}" href="${site}${pathFor(l, page)}"/>`)
        .join('');
      return `<url><loc>${site}${pathFor(lang, page)}</loc>${alts}</url>`;
    }),
  );
  const xml =
    `<?xml version="1.0" encoding="UTF-8"?>` +
    `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">` +
    entries.join('') +
    `</urlset>`;
  return new Response(xml, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
};
```

- [ ] **Step 5: Base.astro head additions** (below the existing hreflang links; `ogImage` derived from `lang`):

```astro
---
const ogImage = new URL(lang === 'en' ? '/og/og-en.png' : '/og/og-vi.png', site).href;
const pageUrl = page ? new URL(pathFor(lang, page), site).href : site.href;
---
    <meta name="theme-color" content="#0b1120" />
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="ShellX" />
    <meta property="og:title" content={title} />
    <meta property="og:description" content={description} />
    <meta property="og:url" content={pageUrl} />
    <meta property="og:image" content={ogImage} />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta property="og:locale" content={lang === 'vi' ? 'vi_VN' : 'en_US'} />
    <meta property="og:locale:alternate" content={lang === 'vi' ? 'en_US' : 'vi_VN'} />
    <meta name="twitter:card" content="summary_large_image" />
    <slot name="head" />
```

- [ ] **Step 6: JSON-LD in Home.astro** (frontmatter builds the objects; render into the head slot):

```astro
---
const site = 'https://shellx.pro';
const url = lang === 'vi' ? `${site}/` : `${site}/en/`;
const ld = [
  {
    '@context': 'https://schema.org', '@type': 'SoftwareApplication',
    name: 'ShellX', applicationCategory: 'DeveloperApplication',
    operatingSystem: 'macOS, Windows, iOS, Android',
    description: t.homeDescription, url, inLanguage: lang,
    offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
  },
  { '@context': 'https://schema.org', '@type': 'WebSite', name: 'ShellX', url: site, inLanguage: lang },
];
---
  <Fragment slot="head">
    {ld.map((d) => <script type="application/ld+json" set:html={JSON.stringify(d)} />)}
  </Fragment>
```

- [ ] **Step 7: OG images** — write `web/og-src/og-vi.svg` (en version: swap the two text lines for `ui.en.tagline` / `Your computer's terminal, right on your phone.` and `og-en`):

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630">
  <rect width="1200" height="630" fill="#0b1120"/>
  <rect x="80" y="90" width="1040" height="450" rx="16" fill="#0f172a" stroke="#1e293b" stroke-width="2"/>
  <circle cx="120" cy="130" r="8" fill="#f87171"/><circle cx="146" cy="130" r="8" fill="#fbbf24"/><circle cx="172" cy="130" r="8" fill="#4ade80"/>
  <text x="600" y="136" fill="#94a3b8" font-family="Menlo, monospace" font-size="20" text-anchor="middle">shellx@pro — zsh</text>
  <text x="130" y="230" fill="#22d3ee" font-family="Menlo, monospace" font-size="34" font-weight="bold">$ shellx connect</text>
  <text x="130" y="290" fill="#4ade80" font-family="Menlo, monospace" font-size="30">✓ đã ghép nối · mã hóa đầu cuối</text>
  <text x="130" y="380" fill="#e2e8f0" font-family="Menlo, monospace" font-size="44" font-weight="bold">Terminal máy tính của bạn,</text>
  <text x="130" y="440" fill="#e2e8f0" font-family="Menlo, monospace" font-size="44" font-weight="bold">ngay trên điện thoại.</text>
  <text x="130" y="510" fill="#94a3b8" font-family="Menlo, monospace" font-size="26">shellx.pro</text>
</svg>
```

Convert with headless Chrome (one-time, commit the PNGs):

```bash
for l in vi en; do
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
    --screenshot="$PWD/public/og/og-$l.png" --window-size=1200,630 --default-background-color=0b1120ff \
    "file://$PWD/og-src/og-$l.svg"
done
```

Check both PNGs by eye (open them) — text must not be clipped.

- [ ] **Step 8: Run `npm run build`** — all tests pass.

- [ ] **Step 9: Commit**

```bash
git add web/public/robots.txt web/public/og web/og-src web/src/pages/sitemap.xml.ts web/src/layouts/Base.astro web/src/components/Home.astro web/tests/site.test.mjs
git commit -m "feat(web): OG/Twitter meta, JSON-LD, robots.txt, sitemap.xml, OG images"
```

---

### Task 6: Lighthouse + browser verification

**Files:** none created; fixes land in the files above if scores miss targets.

- [ ] **Step 1: Build and serve** — `npm run build && npm run preview` (serves dist on http://localhost:4321).

- [ ] **Step 2: Lighthouse both languages**

```bash
npx --yes lighthouse http://localhost:4321/ --preset=desktop --quiet --chrome-flags="--headless=new" --output=json --output-path=/tmp/lh-vi.json
npx --yes lighthouse http://localhost:4321/en/ --preset=desktop --quiet --chrome-flags="--headless=new" --output=json --output-path=/tmp/lh-en.json
node -e "for (const f of ['/tmp/lh-vi.json','/tmp/lh-en.json']) { const r = JSON.parse(require('fs').readFileSync(f)); console.log(f, Object.fromEntries(Object.entries(r.categories).map(([k,v])=>[k, v.score*100]))); }"
```

Targets: SEO = 100, Accessibility = 100, Best Practices = 100, Performance ≥ 95. Fix and re-run until met (common fixes: contrast, missing aria, image dimensions).

- [ ] **Step 3: Browser checks (Review Focus 2-5)** — in a real browser on the preview URL:
  - 320 px viewport (responsive mode): no horizontal scroll on `/`, `/privacy/`.
  - Reduce Motion ON: no typing animation, everything visible instantly.
  - Vietnamese diacritics (`ậ`, `ế`, `ữ` on the page) render in JetBrains Mono — no mid-word font switch.
  - JS disabled: full content visible on `/`.
  - Keyboard-only: tab reaches lang switch, download links, FAQ summaries; focus visible.

- [ ] **Step 4: Record scores + close out**

```bash
git commit --allow-empty -m "chore(web): lighthouse verified — SEO 100 / A11y 100 / BP 100 / Perf >= 95 (vi+en)"
```

(If fixes were needed in Steps 2-3, commit them with the files they touch instead of an empty commit.)
