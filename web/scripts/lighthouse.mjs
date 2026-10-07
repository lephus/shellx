// Serves dist/ locally and runs Lighthouse on every page (needs Chrome and network for npx).
// Fails when SEO < 100 or Performance / Accessibility / Best Practices < 95.
// Usage: npm run build && npm run lighthouse   (LH_PRESET=desktop for the desktop profile)
import { spawn } from 'node:child_process';
import { createReadStream, existsSync, mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { dirname, extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');
if (!existsSync(dist)) throw new Error('dist/ missing — run npm run build first');

const minimum = { seo: 100, performance: 95, accessibility: 95, 'best-practices': 95 };
const pages = ['/', '/en/', '/privacy/', '/en/privacy/', '/terms/', '/en/terms/'];
const types = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml',
  '.png': 'image/png', '.woff2': 'font/woff2', '.xml': 'application/xml', '.txt': 'text/plain',
  '.webmanifest': 'application/manifest+json',
};

// Like deploy/web/nginx.conf: /x/ → /x/index.html, unknown → 404.html with status 404.
const server = createServer((req, res) => {
  const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname));
  let file = join(dist, path.endsWith('/') ? join(path, 'index.html') : path);
  let status = 200;
  if (!file.startsWith(dist) || !existsSync(file) || statSync(file).isDirectory()) {
    file = join(dist, '404.html');
    status = 404;
  }
  res.writeHead(status, { 'Content-Type': types[extname(file)] ?? 'application/octet-stream' });
  createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;

const out = mkdtempSync(join(tmpdir(), 'shellx-lh-'));
let failed = false;
try {
  for (const page of pages) {
    const report = join(out, 'report.json');
    const args = [
      '--yes', 'lighthouse@12', `${base}${page}`, '--quiet', '--output=json', `--output-path=${report}`,
      `--only-categories=${Object.keys(minimum).join(',')}`, '--chrome-flags=--headless=new',
    ];
    if (process.env.LH_PRESET === 'desktop') args.push('--preset=desktop');
    // Async on purpose: spawnSync would block this process, and with it the server Lighthouse loads.
    const status = await new Promise((resolve) => {
      const child = spawn('npx', args, { stdio: ['ignore', 'ignore', 'inherit'] });
      const timer = setTimeout(() => child.kill(), 180_000);
      child.on('exit', (code) => { clearTimeout(timer); resolve(code); });
    });
    if (status !== 0 || !existsSync(report)) {
      console.error(`${page}: lighthouse failed (status ${status})`);
      failed = true;
      continue;
    }
    const { categories, audits } = JSON.parse(readFileSync(report, 'utf8'));
    const scores = Object.keys(minimum).map((k) => [k, Math.round(categories[k].score * 100)]);
    const low = scores.filter(([k, s]) => s < minimum[k]);
    console.log(`${low.length ? '✖' : '✓'} ${page.padEnd(14)} ${scores.map(([k, s]) => `${k} ${s}`).join(' · ')}`);
    for (const [k] of low) {
      for (const ref of categories[k].auditRefs) {
        const a = audits[ref.id];
        if (ref.weight > 0 && a.score !== null && a.score < 1) console.log(`    ${k}: ${a.id} — ${a.title}`);
      }
    }
    if (low.length) failed = true;
    rmSync(report);
  }
} finally {
  server.close();
  rmSync(out, { recursive: true, force: true });
}
process.exit(failed ? 1 : 0);
