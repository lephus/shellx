# shellx.pro web redesign — design

Date: 2026-10-07 · Branch: `worktree-feat-web-redesign` · Scope: `web/` only

## Goal

Replace the v1.0 "terminal session" home page with a marketing landing page inspired by
overpassip.com (dark purple background, blue/purple/pink glows, bold sans headlines, one big CTA,
a three-column "how it works", illustrated feature cards, a closing CTA, a minimal footer), with
purposeful animations, and keep SEO at Lighthouse 100.

## Decisions (agreed in chat)

- Take both the visual style and the page structure from overpassip.
- "How it works" columns are product surfaces: **Desktop** (full terminal app: workspaces, split
  panes, session restore, command palette), **Phone** (remote control over E2E encryption),
  **Notifications** (command finished / agent needs you).
- Animations: CSS/SVG + a small vanilla script (IntersectionObserver). No animation library.
  `prefers-reduced-motion` shows the final static state.
- SEO: Lighthouse SEO = 100; Performance, Accessibility, Best Practices >= 95.

## Visual system

- Background `#0b0716`, surfaces `#151026`, border `#2a2145`, text `#ece9f6`, muted `#a69fc0`.
- Accents: purple `#7c3aed` / `#a78bfa`, blue `#3b82f6` / `#60a5fa`, pink `#ec4899` / `#f472b6`, ok `#4ade80`.
- Headings: Space Grotesk variable (self-hosted, latin + vietnamese subsets, OFL). Body: system sans.
  Terminal and code: JetBrains Mono (already self-hosted).
- Dark only. Illustrations are inline SVG/CSS, no bitmaps.

## Home page structure (vi `/`, en `/en/`, one shared component)

1. Nav: brand, Features · Security · FAQ, "Download" button, vi/en switch.
2. Hero: h1, sub-copy, primary CTA (OS-detected: macOS/Windows, falls back to `#download`),
   secondary CTA to `#how`. Right side: a desktop terminal window that types a command and prints
   output, mirrored on a phone frame with a short delay. Drifting glow blobs behind.
3. How it works (`#how`): three cards Desktop / Phone / Notifications, each with an animated
   mini illustration (panes split open; data flows through a lock; a notification slides in).
4. Features (`#features`): six-cell grid from the existing feature copy.
5. Security (`#security`): animated phone ⇄ relay ⇄ desktop diagram (packets turn into `▓▒░` at
   the relay), the four security points, link to the privacy policy.
6. Get started: three-step timeline that draws as it scrolls in.
7. FAQ (`#faq`): `<details>` accordion, existing content.
8. Closing CTA + downloads (`#download`): existing `Downloads` component restyled; store buttons
   stay "Coming soon" while `site.config.json` has `null` URLs.
9. Footer: brand, Privacy / Terms, support email, ©.

Unchanged: legal page content, `site.config.json`, download URL scheme, no external resources.
Legal pages and 404 pick up the new theme through `Base.astro`.

## SEO

- Keep canonical, hreflang (vi/en/x-default), OG/Twitter, robots.txt, sitemap with alternates.
- JSON-LD on home: `SoftwareApplication` (with `downloadUrl`, `operatingSystem`, free `offers`),
  `FAQPage` built from the same FAQ strings, `Organization`, `WebSite`.
- One h1 per page; semantic landmarks; title 30–65 chars, description 110–165 chars per language.
- New OG images matching the new look (`og-src/*.svg` → `public/og/*.png`).
- `apple-touch-icon`, `site.webmanifest`, `theme-color` updated; sitemap gains `lastmod`.

## Performance and accessibility

- Inline JS < 8 KB total, runs after paint; only `transform`/`opacity` animate; every animated box
  has a fixed size (CLS ≈ 0). LCP is hero text. Heading font preloaded, `font-display: swap`.
- WCAG AA contrast; decorative animations `aria-hidden` with a text equivalent; visible focus rings.
- All content is in the static HTML (no JS needed to read it).

## Testing

- `tests/site.test.mjs`: replace the "terminal session" check with checks for the new sections;
  add checks for title/description length, FAQPage/Organization JSON-LD, reciprocal hreflang,
  manifest + touch icon, `lastmod`, img alt, heading font preload.
- `npm run lighthouse`: builds nothing, serves `dist/` locally and runs Lighthouse (needs Chrome);
  fails if SEO < 100 or any other category < 95. Not part of `npm run build`.
