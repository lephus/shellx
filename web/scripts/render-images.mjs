// Renders og-src/*.svg to the PNGs in public/ with headless Chrome (needs Chrome installed).
// Usage: node scripts/render-images.mjs   — run after editing og-src/, then commit public/.
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const chrome = [
  process.env.CHROME_PATH,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
].find((p) => p && existsSync(p));
if (!chrome) throw new Error('Chrome not found; set CHROME_PATH');

const jobs = [
  { src: 'og-src/og-en.svg', out: 'public/og/og-en.png', w: 1200, h: 630 },
  { src: 'og-src/og-vi.svg', out: 'public/og/og-vi.png', w: 1200, h: 630 },
  { src: 'og-src/icon.svg', out: 'public/apple-touch-icon.png', w: 180, h: 180 },
  { src: 'og-src/icon.svg', out: 'public/icon-512.png', w: 512, h: 512 },
];

for (const { src, out, w, h } of jobs) {
  // A fresh profile per shot: headless Chrome can linger on a reused one and never exit.
  const tmp = mkdtempSync(join(tmpdir(), 'shellx-og-'));
  const started = Date.now();
  try {
    // Wrap the SVG in a page so it scales to the window and its relative font URLs resolve.
    const page = join(root, 'og-src', `.render-${w}.html`);
    const svgUrl = pathToFileURL(join(root, src)).href;
    writeFileSync(page, `<!doctype html><style>html,body{margin:0;background:#0b0716}</style>` +
      `<object data="${svgUrl}" type="image/svg+xml" width="${w}" height="${h}"></object>`);
    const result = spawnSync(chrome, [
      '--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files',
      `--user-data-dir=${tmp}`, `--window-size=${w},${h}`, '--virtual-time-budget=3000',
      `--screenshot=${join(root, out)}`, pathToFileURL(page).href,
    ], { stdio: 'ignore', timeout: 30_000 });
    rmSync(page);
    // Chrome sometimes writes the screenshot and then hangs; a fresh file is what counts.
    const written = existsSync(join(root, out)) && statSync(join(root, out)).mtimeMs >= started;
    if (!written) throw new Error(`Chrome failed on ${src} (status ${result.status})`);
    console.log(`${src} → ${out}`);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}
