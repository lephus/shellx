# shellx.pro website

Static [Astro](https://astro.build) site for `https://shellx.pro` (spec §11): a landing page with
download links, the privacy policy and the terms of use, in Vietnamese (default, at `/`) and English
(under `/en/`). Design: `docs/superpowers/specs/2026-10-07-web-redesign-design.md`.

| Path | Page |
|---|---|
| `/` · `/en/` | Landing page: hero demo, how it works, features, security, steps, FAQ, downloads |
| `/privacy/` · `/en/privacy/` | Privacy policy (`#delete-account` explains account deletion) |
| `/terms/` · `/en/terms/` | Terms of use |
| any other path | `404.html` |

## Commands (Node 22.12 or later)

| Command | What it does |
|---|---|
| `npm ci` | Install the locked dependencies |
| `npm run dev` | Dev server at http://localhost:4321 |
| `npm run build` | Refuse the `[quốc gia]` placeholder, `astro build` into `dist/`, then check pages and links (`tests/`) |
| `npm test` | Re-run the checks against an existing `dist/` |
| `CHECK_DOWNLOADS=1 npm test` | Also sends HEAD requests to the installer URLs (needs network) |
| `npm run lighthouse` | Serve `dist/` locally and run Lighthouse (mobile) on the 6 pages; fails if SEO < 100 or Performance / Accessibility / Best Practices < 95. Needs Chrome and network (npx). `LH_PRESET=desktop` for desktop |
| `npm run images` | Render `og-src/*.svg` into `public/og/*.png`, `public/apple-touch-icon.png` and `public/icon-512.png` with headless Chrome; commit the PNGs |

Animations are CSS plus one small inline script in `src/components/Home.astro` (scroll reveals,
hero demo, OS-detected download button). With `prefers-reduced-motion: reduce` or without JS every
section shows its final, static state. Fonts are self-hosted: Space Grotesk (OFL, latin + vietnamese
subsets) for headings, JetBrains Mono for terminal text.

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

## Deployment

The site runs on the VPS as the `web` container (nginx:alpine with `dist/` and
`deploy/web/nginx.conf`), built by `web/Dockerfile` and deployed by `.github/workflows/deploy.yml`
on every push to `main` that changes `web/`, `relay/` or `deploy/`. See `deploy/README.md`.

- `npm run build` first runs `scripts/check-placeholders.mjs`, which refuses to build while any page
  still contains `[quốc gia]`: the privacy policy and terms must name the country where the VPS is
  hosted before the site is public (VPS spec §9). Replace every occurrence (vi and en), update
  `updated:` in their front matter, and commit.
- nginx answers `/privacy` with `301 /privacy/`, unknown paths with `dist/404.html` and status 404,
  `www.shellx.pro` with `301 https://shellx.pro…`, and serves `download.shellx.pro` from the VPS
  folder `downloads/` (files only, always as downloads). It writes no access log.
- Build the image locally from the repository root: `docker build -f web/Dockerfile -t shellx-web .`

## Verify production

```bash
curl -sIL https://shellx.pro/privacy | grep -iE '^(HTTP|location)'
# Expected: a redirect to /privacy/, then a final "HTTP/2 200"
curl -s -o /dev/null -w '%{http_code}\n' https://shellx.pro/en/terms/
# Expected: 200
curl -s -o /dev/null -w '%{http_code}\n' https://shellx.pro/no-such-page
# Expected: 404 (dist/404.html)
curl -sI https://www.shellx.pro/terms/ | grep -i '^location'
# Expected: location: https://shellx.pro/terms/
```

## URLs for the store listings

- Privacy policy URL (App Store Connect, Google Play Console): `https://shellx.pro/privacy`
  (spec §14; redirects to `/privacy/`). English: `https://shellx.pro/en/privacy/`.
- Google Play "Delete account" URL: `https://shellx.pro/en/privacy/#delete-account`.
