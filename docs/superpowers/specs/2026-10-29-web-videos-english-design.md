# shellx.pro: product videos, English only (2026-10-29)

## Why

Two videos were made for the site (`shellx-intro.mp4`, 1 min; `shellx-tutorial.mp4`, 3 min, both
narrated in English with English captions burned in). The user wanted visitors to watch the short
intro first and to have a place to watch the full tutorial when they want. While testing, they made
English the main language and then dropped Vietnamese from the website.

## Decisions

- **Self-hosted, not YouTube.** The privacy policy promises no third-party scripts or iframes, and the
  build checks refuse external media. Files live in `web/public/media/` (about 15 MB), served by the
  `web` nginx with `video/mp4` and `image/webp` types and a 7-day cache. `moov` is at the front, so
  playback starts before the download ends.
- **Intro first.** The home page has `#video` right under the hero, and the hero's second button
  ("Watch the 1-minute video") points there. Every `<video>` is `preload="none"` with a WebP poster,
  so the page weight does not change until someone presses play.
- **Full tutorial on `/videos/`.** Chapters (from the `.srt` cues), a transcript, then the intro.
  Chapters seek the player; `?t=<seconds>` opens the tutorial at that second, which is the `url` of each
  `Clip` in the `VideoObject` JSON-LD. Linked from the home page, the steps section, the menu and the
  footer.
- **One source for the words.** `web/src/videos/<name>.srt` feeds chapters, transcripts, the
  JSON-LD `transcript` and llms-full.txt (`web/src/lib/videos.ts`).
- **No caption track.** The captions are in the picture. The tutorial's embedded `mov_text` track
  was removed (stream copy, no re-encode) so Safari does not offer a duplicate.
- **English only.** English pages moved from `/en/` to `/`; nginx answers `/en` and `/en/…` with
  `301` to the same path without the prefix. The Vietnamese pages, strings, guides, legal texts,
  OG image and font preload were removed, and so were hreflang alternates. The terms' language
  clause now says they are published in English only (`updated: 2026-10-29`).
- **Share viewer stays bilingual.** `/s/` follows the viewer's browser language (Vietnamese or
  English), as before; its HTML defaults are English. It is app UI, not site content.

## Verification

`npm run build` (all page and link checks, including "no Vietnamese text on site pages" and "no link
to /en/"), `node --test deploy/tests/web-nginx.test.mjs`, headless-Chrome checks of layout from 390 to
1200 px, chapter seeking and the `?t=` deep link.
