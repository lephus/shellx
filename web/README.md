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
