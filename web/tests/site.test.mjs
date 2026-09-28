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

test('404 page exists (nginx answers unknown paths with it and status 404)', () => {
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

test('no external scripts, styles, fonts or media on any page', () => {
  // Patterns for checking external resources
  // Negative lookahead with boundary ensures shellx.pro is only allowed with path/quote boundary, not shellx.pro.evil.com, etc
  const htmlOriginPattern = /<(?:script|link|img|source|iframe)\b[^>]*\b(?:src|href)="(?:https?:)?\/\/(?!shellx\.pro[/"])/gi;
  const cssUrlPattern = /url\(\s*["']?(?:https?:)?\/\/(?!shellx\.pro[/"'])/gi;

  // Validate that the patterns correctly identify evil domains but allow shellx.pro
  const evilSample = '<script src="https://shellx.pro.evil.com/x.js">';
  const goodSample = '<script src="https://shellx.pro/x.js">';

  htmlOriginPattern.lastIndex = 0;
  assert.ok(htmlOriginPattern.test(evilSample), 'Pattern should catch shellx.pro.evil.com domains');

  htmlOriginPattern.lastIndex = 0;
  assert.ok(!htmlOriginPattern.test(goodSample), 'Pattern should allow shellx.pro domains');

  const allPages = ['/', '/en/', '/privacy/', '/terms/', '/en/privacy/', '/en/terms/', '/404.html'];

  // Check HTML tags for external resources on all pages
  for (const p of allPages) {
    const html = readPage(p);
    htmlOriginPattern.lastIndex = 0;
    for (const m of html.matchAll(htmlOriginPattern)) {
      assert.fail(`${p}: external resource in ${m[0].slice(0, 120)}`);
    }

    // Check inline <style> contents for external URL references
    for (const styleMatch of html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi)) {
      const styleContent = styleMatch[1];
      cssUrlPattern.lastIndex = 0;
      for (const m of styleContent.matchAll(cssUrlPattern)) {
        assert.fail(`${p}: external CSS url() in <style>: ${m[0].slice(0, 120)}`);
      }
    }
  }

  // Check all .css files in dist/_astro/ for external URL references
  const astroDir = join(dist, '_astro');
  if (existsSync(astroDir)) {
    for (const file of readdirSync(astroDir)) {
      if (file.endsWith('.css')) {
        const css = readFileSync(join(astroDir, file), 'utf8');
        cssUrlPattern.lastIndex = 0;
        for (const m of css.matchAll(cssUrlPattern)) {
          assert.fail(`dist/_astro/${file}: external CSS url(): ${m[0].slice(0, 120)}`);
        }
      }
    }
  }
});

test('every page has exactly one h1', () => {
  const allPages = ['/', '/en/', '/privacy/', '/terms/', '/en/privacy/', '/en/terms/', '/404.html'];
  for (const p of allPages) {
    const count = (readPage(p).match(/<h1[\s>]/g) ?? []).length;
    assert.equal(count, 1, `${p} has ${count} h1`);
  }
});

test('self-hosted font files exist and are preloaded', () => {
  assert.ok(existsSync(join(dist, 'fonts/JetBrainsMono-Regular.woff2')));
  assert.ok(existsSync(join(dist, 'fonts/JetBrainsMono-Bold.woff2')));
  assert.match(readPage('/'), /rel="preload" as="font"[^>]*JetBrainsMono-Regular\.woff2/);
});

test('home is a terminal session: window chrome + command blocks', () => {
  for (const p of ['/', '/en/']) {
    const html = readPage(p);
    assert.match(html, /shellx@pro/);
    assert.ok((html.match(/data-term-block/g) ?? []).length >= 3, `${p}: too few term blocks`);
    assert.match(html, /data-cmd/);
  }
});

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
