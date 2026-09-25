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
