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

// The site is English only since 2026-10-29: the English pages moved from /en/ to / (nginx answers
// /en/… with 301) and the Vietnamese pages were removed.
const homePages = [{ path: '/', lang: 'en', privacy: '/privacy/', terms: '/terms/' }];

const guideSlugs = [
  'claude-code-on-phone',
  'ssh-from-phone',
  'remote-terminal-without-vpn',
  'shellx-vs-termius',
  'shellx-vs-tailscale',
  'ai-coding-agent-on-phone',
  'claude-code-remote-control-vs-shellx',
  'best-ssh-app-iphone-android',
  'schedule-claude-code-mac',
];
const guidePages = ['/guides/', ...guideSlugs.map((s) => `/guides/${s}/`)];
const videoPages = [{ path: '/videos/', lang: 'en', home: '/' }];
const indexablePages = ['/', '/privacy/', '/terms/', ...videoPages.map((v) => v.path), ...guidePages];
const everyPage = [...indexablePages, '/404.html', '/s/'];

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

test('windowsSha256 is empty or 64 hex characters', () => {
  const sha = config.windowsSha256;
  assert.ok(sha === null || sha === undefined || /^[0-9a-fA-F]{64}$/.test(sha), 'windowsSha256 must be null or 64 hex characters');
});

test('the Windows download explains SmartScreen and Smart App Control, and shows the SHA-256 only when set', () => {
  const html = readPage('/');
  assert.ok(html.includes('id="windows-help"'), 'home: no Windows install help');
  for (const needle of ['More info', 'Run anyway', 'Smart App Control']) {
    assert.ok(html.includes(needle), `home: Windows help lacks "${needle}"`);
  }
  const sha = config.windowsSha256;
  if (sha) {
    assert.ok(html.includes(sha.toLowerCase()), 'home: the SHA-256 from site.config.json is not shown');
  } else {
    assert.ok(!html.includes('data-windows-sha256'), 'home: a SHA-256 block is shown without a value');
  }
});

test('site config is valid', () => {
  assert.match(config.desktopVersion, /^\d+\.\d+\.\d+$/);
  assert.equal(config.downloadBaseUrl, 'https://download.shellx.pro/desktop');
  assert.match(config.supportEmail, /^[^@\s]+@[^@\s]+\.[^@\s]+$/);
  assert.match(config.discordUrl, /^https:\/\/discord\.gg\/[A-Za-z0-9]+$/);
  assert.match(config.shareApiBase, /^https:\/\/[a-z0-9.-]+$/, 'shareApiBase is an https origin without a path');
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

  test(`home ${page.path} has a contact section with the Discord invite, linked from the menu`, () => {
    const html = readPage(page.path);
    const section = html.match(/<section[^>]*id="contact"[\s\S]*?<\/section>/);
    assert.ok(section, 'missing <section id="contact">');
    assert.ok(hrefs(section[0]).includes(config.discordUrl), 'contact section lacks the Discord invite');
    assert.ok(!section[0].includes(config.supportEmail), 'contact section still shows the email address');
    const nav = html.match(/<nav class="top-nav"[\s\S]*?<\/nav>/);
    assert.ok(nav && hrefs(nav[0]).includes(`${page.path}#contact`), `menu lacks a link to ${page.path}#contact`);
  });

  test(`home ${page.path} links to the legal pages`, () => {
    const links = hrefs(readPage(page.path));
    for (const target of [page.privacy, page.terms, config.discordUrl]) {
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
  { path: '/privacy/', lang: 'en' },
  { path: '/terms/', lang: 'en' },
];

function allHtmlFiles(dir = dist) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) return allHtmlFiles(full);
    return entry.name.endsWith('.html') ? [full] : [];
  });
}

for (const page of legalPages) {
  test(`legal page ${page.path} is built in ${page.lang}`, () => {
    const html = readPage(page.path);
    assert.match(html, new RegExp(`<html lang="${page.lang}"`));
    assert.ok(hrefs(html).includes(`mailto:${config.supportEmail}`), 'missing support email link');
  });
}

for (const [path, inApp] of [['/privacy/', 'Settings › Account › Delete Account…']]) {
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
  const htmlOriginPattern = /<(?:script|link|img|source|iframe|video|audio|track)\b[^>]*\b(?:src|href|poster)="(?:https?:)?\/\/(?!shellx\.pro[/"])/gi;
  const cssUrlPattern = /url\(\s*["']?(?:https?:)?\/\/(?!shellx\.pro[/"'])/gi;

  // Validate that the patterns correctly identify evil domains but allow shellx.pro
  const evilSample = '<script src="https://shellx.pro.evil.com/x.js">';
  const goodSample = '<script src="https://shellx.pro/x.js">';

  htmlOriginPattern.lastIndex = 0;
  assert.ok(htmlOriginPattern.test(evilSample), 'Pattern should catch shellx.pro.evil.com domains');

  htmlOriginPattern.lastIndex = 0;
  assert.ok(!htmlOriginPattern.test(goodSample), 'Pattern should allow shellx.pro domains');

  const allPages = everyPage;

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

  // Check all .css files in dist/_astro/ for external URL references, and every bundled script
  // (the /s/ viewer and xterm.js) for any URL other than shellx.pro and relay.shellx.pro.
  const astroDir = join(dist, '_astro');
  const jsUrlPattern = /https?:\/\/(?!(?:relay\.)?shellx\.pro(?![\w.-]))[^\s"'`)]*/gi;
  assert.ok(!jsUrlPattern.test('"https://relay.shellx.pro/v2"'), 'JS pattern allows relay.shellx.pro');
  jsUrlPattern.lastIndex = 0;
  assert.ok(jsUrlPattern.test('"https://shellx.pro.evil.com/"'), 'JS pattern catches shellx.pro.evil.com');
  if (existsSync(astroDir)) {
    for (const file of readdirSync(astroDir)) {
      if (file.endsWith('.js')) {
        const js = readFileSync(join(astroDir, file), 'utf8');
        jsUrlPattern.lastIndex = 0;
        for (const m of js.matchAll(jsUrlPattern)) {
          assert.fail(`dist/_astro/${file}: external URL in script: ${m[0].slice(0, 120)}`);
        }
      }
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
  const allPages = everyPage;
  for (const p of allPages) {
    const count = (readPage(p).match(/<h1[\s>]/g) ?? []).length;
    assert.equal(count, 1, `${p} has ${count} h1`);
  }
});

test('self-hosted font files exist and are preloaded', () => {
  // The Vietnamese subset stays for the share viewer's Vietnamese texts, loaded only when used.
  for (const f of ['JetBrainsMono-Regular', 'JetBrainsMono-Bold', 'SpaceGrotesk-Latin', 'SpaceGrotesk-Vietnamese']) {
    assert.ok(existsSync(join(dist, `fonts/${f}.woff2`)), `missing fonts/${f}.woff2`);
  }
  const html = readPage('/');
  assert.match(html, /rel="preload" as="font"[^>]*SpaceGrotesk-Latin\.woff2/);
  assert.doesNotMatch(html, /rel="preload" as="font"[^>]*SpaceGrotesk-Vietnamese\.woff2/);
  assert.match(html, /rel="preload" as="font"[^>]*JetBrainsMono-Regular\.woff2/);
});

test('gradient buttons paint their border box, so no sliver of the gradient repeats at the ends', () => {
  // .btn has a 1px transparent border. With the default background-origin (padding-box) the gradient
  // tile repeats under that border: a pink line at the left end and a purple one at the right.
  const css = readdirSync(join(dist, '_astro')).filter((f) => f.endsWith('.css'))
    .map((f) => readFileSync(join(dist, '_astro', f), 'utf8')).join('\n');
  const rule = css.match(/\.btn-primary\{([^}]*)\}/)?.[1];
  assert.ok(rule, 'no .btn-primary rule in dist/_astro/*.css');
  assert.match(rule, /linear-gradient/);
  assert.match(rule, /background-origin:border-box/, `.btn-primary: ${rule}`);
});

test('every page credits cmux, the open-source project ShellX is built on, at the bottom', () => {
  for (const p of everyPage) {
    const footer = readPage(p).match(/<footer class="bottom"[\s\S]*?<\/footer>/)?.[0];
    assert.ok(footer, `${p}: no footer`);
    assert.ok(hrefs(footer).includes('https://github.com/manaflow-ai/cmux'), `${p}: footer lacks the cmux link`);
    assert.ok(footer.indexOf('manaflow-ai/cmux') > footer.indexOf('©'), `${p}: the credit is not the last line`);
  }
});

test('home has the landing sections: hero, how it works, features, security, steps, FAQ, download', () => {
  for (const p of ['/']) {
    const html = readPage(p);
    for (const id of ['video', 'how', 'features', 'security', 'start', 'faq', 'download']) {
      assert.match(html, new RegExp(`<section[^>]*id="${id}"`), `${p}: missing section #${id}`);
    }
    assert.match(html, /data-demo/, `${p}: hero demo missing`);
    assert.equal((html.match(/class="pillar /g) ?? []).length, 3, `${p}: need 3 pillars`);
    assert.equal((html.match(/class="feature"/g) ?? []).length, 6, `${p}: need 6 feature cards`);
  }
});

test('home carries the full marketing content statically (no JS needed)', () => {
  const checks = [['/', ['Features', 'Security', 'FAQ', 'argon2id', 'QR code', 'free']]];
  for (const [p, needles] of checks) {
    const html = readPage(p);
    for (const n of needles) assert.ok(html.includes(n), `${p} missing "${n}"`);
    assert.ok((html.match(/<details[\s>]/g) ?? []).length >= 4, `${p}: FAQ needs >= 4 <details>`);
  }
});

test('animations ship as a small inline script and respect reduced motion', () => {
  const html = readPage('/');
  assert.match(html, /prefers-reduced-motion: reduce/);
  const inline = [...html.matchAll(/<script(?![^>]*src)(?![^>]*ld\+json)[^>]*>([\s\S]*?)<\/script>/g)]
    .map((m) => m[1]).join('');
  assert.ok(inline.length > 0, 'no inline script found');
  assert.ok(inline.length < 8192, `inline JS too big: ${inline.length} bytes`);
  assert.ok(inline.includes('IntersectionObserver'), 'reveals must be driven by IntersectionObserver');
  assert.ok(!/<script[^>]+src=/.test(html), 'no script files: animations stay inline');
});

test('decorative animations are hidden from screen readers and have a text equivalent', () => {
  for (const p of ['/']) {
    const html = readPage(p);
    assert.match(html, /class="desk"[^>]*aria-hidden="true"/, `${p}: hero desktop must be aria-hidden`);
    assert.match(html, /class="phone"[^>]*aria-hidden="true"/, `${p}: hero phone must be aria-hidden`);
    assert.match(html, /<figcaption class="sr-only"/, `${p}: security diagram needs a caption`);
    for (const img of html.match(/<img\b[^>]*>/g) ?? []) {
      assert.match(img, /\balt="/, `${p}: img without alt: ${img}`);
    }
  }
});

test('robots.txt welcomes search and AI crawlers; sitemap lists exactly the indexable pages', () => {
  const robots = readFileSync(join(dist, 'robots.txt'), 'utf8');
  assert.match(robots, /Sitemap: https:\/\/shellx\.pro\/sitemap\.xml/);
  assert.ok(!/Disallow:\s*\//.test(robots), 'robots.txt must not disallow anything');
  for (const bot of ['OAI-SearchBot', 'GPTBot', 'ClaudeBot', 'PerplexityBot', 'Google-Extended', 'Bingbot']) {
    assert.ok(robots.includes(`User-agent: ${bot}\nAllow: /`), `robots.txt: ${bot}`);
  }
  const xml = readFileSync(join(dist, 'sitemap.xml'), 'utf8');
  const locs = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]).sort();
  assert.deepEqual(locs, indexablePages.map((p) => `https://shellx.pro${p}`).sort());
});

test('OG/Twitter meta and the OG image on every page', () => {
  for (const p of ['/', '/privacy/', '/videos/']) {
    const html = readPage(p);
    const og = '/og/og-en.png';
    assert.match(html, /property="og:title"/);
    assert.match(html, /name="twitter:card" content="summary_large_image"/);
    assert.ok(html.includes(`https://shellx.pro${og}`), `${p} wrong og:image`);
    assert.ok(existsSync(join(dist, og.slice(1))), `${og} missing from dist`);
  }
});

test('home JSON-LD parses and declares the free app', () => {
  for (const p of ['/']) {
    const scripts = [...readPage(p).matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)];
    assert.ok(scripts.length >= 1, `${p}: JSON-LD missing`);
    const types = scripts.map((m) => JSON.parse(m[1])).map((d) => d['@type']);
    assert.ok(types.includes('SoftwareApplication'));
    const app = scripts.map((m) => JSON.parse(m[1])).find((d) => d['@type'] === 'SoftwareApplication');
    assert.equal(app.offers.price, '0');
  }
});

const seoPages = indexablePages.map((path) => ({ path, lang: 'en' }));

function unescapeHtml(s) {
  return s.replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&amp;/g, '&');
}

for (const page of seoPages) {
  test(`SEO basics on ${page.path}: title, description, canonical, one language, icons`, () => {
    const html = readPage(page.path);
    const title = unescapeHtml(html.match(/<title>([^<]*)<\/title>/)?.[1] ?? '');
    const description = unescapeHtml(html.match(/<meta name="description" content="([^"]*)"/)?.[1] ?? '');
    assert.ok(title.length >= 20 && title.length <= 65, `${page.path}: title is ${title.length} chars: ${title}`);
    assert.ok(description.length >= 70 && description.length <= 165,
      `${page.path}: description is ${description.length} chars`);
    assert.ok(html.includes(`<link rel="canonical" href="https://shellx.pro${page.path}">`), `${page.path}: canonical`);
    assert.match(html, new RegExp(`<html lang="${page.lang}"`));
    assert.ok(!html.includes('hreflang='), `${page.path}: hreflang on a one-language site`);
    assert.match(html, /rel="apple-touch-icon" href="\/apple-touch-icon\.png"/);
    assert.match(html, /rel="manifest" href="\/site\.webmanifest"/);
    assert.ok(!/name="robots" content="[^"]*noindex/.test(html), `${page.path} is noindex`);
  });
}

test('home JSON-LD has FAQPage matching the visible FAQ, Organization and download URLs', () => {
  for (const p of ['/']) {
    const html = readPage(p);
    const docs = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map((m) => JSON.parse(m[1]));
    const faq = docs.find((d) => d['@type'] === 'FAQPage');
    assert.ok(faq, `${p}: FAQPage missing`);
    assert.equal(faq.mainEntity.length, (html.match(/<details[\s>]/g) ?? []).length, `${p}: FAQPage and <details> differ`);
    for (const q of faq.mainEntity) assert.ok(q.name && q.acceptedAnswer.text, `${p}: empty FAQ entry`);
    const org = docs.find((d) => d['@type'] === 'Organization');
    assert.ok(org?.logo && existsSync(join(dist, new URL(org.logo).pathname.slice(1))), `${p}: Organization logo`);
    const app = docs.find((d) => d['@type'] === 'SoftwareApplication');
    assert.deepEqual(app.downloadUrl, [macUrl, winUrl]);
  }
});

test('manifest icons exist; sitemap carries lastmod for every page and no language alternates', () => {
  const manifest = JSON.parse(readFileSync(join(dist, 'site.webmanifest'), 'utf8'));
  for (const icon of manifest.icons) assert.ok(existsSync(join(dist, icon.src.slice(1))), `missing ${icon.src}`);
  const xml = readFileSync(join(dist, 'sitemap.xml'), 'utf8');
  assert.equal((xml.match(/<lastmod>\d{4}-\d{2}-\d{2}<\/lastmod>/g) ?? []).length, indexablePages.length);
  assert.ok(!xml.includes('hreflang'), 'sitemap lists language alternates');
});

test('404 and the share viewer are noindex; every indexable page is index, follow', () => {
  assert.match(readPage('/404.html'), /<meta name="robots" content="noindex"/);
  assert.match(readPage('/s/'), /<meta name="robots" content="noindex"/);
  for (const p of indexablePages) assert.match(readPage(p), /<meta name="robots" content="index, follow/, p);
});

test('home links to the guides; every guide links back to downloads and to other guides', () => {
  for (const [home, prefix] of [['/', '/guides/']]) {
    const links = hrefs(readPage(home));
    assert.ok(links.includes(prefix), `${home}: no link to ${prefix}`);
    for (const s of ['claude-code-on-phone', 'ssh-from-phone', 'remote-terminal-without-vpn']) {
      assert.ok(links.includes(`${prefix}${s}/`), `${home}: no link to guide ${s}`);
    }
    const index = hrefs(readPage(prefix));
    for (const s of guideSlugs) assert.ok(index.includes(`${prefix}${s}/`), `${prefix}: missing ${s}`);
  }
  for (const s of guideSlugs) {
    for (const [p, home] of [[`/guides/${s}/`, '/']]) {
      const links = hrefs(readPage(p));
      assert.ok(links.includes(`${home}#download`), `${p}: no download link`);
      const others = new Set(links.filter((l) => /\/guides\/[a-z-]+\/$/.test(l) && l !== p));
      assert.ok(others.size >= 4, `${p}: only ${others.size} related guides`);
    }
  }
});

test('guides carry TechArticle and BreadcrumbList JSON-LD with author and dates', () => {
  for (const s of guideSlugs) {
    for (const p of [`/guides/${s}/`]) {
      const html = readPage(p);
      const docs = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map((m) => JSON.parse(m[1]));
      const art = docs.find((d) => d['@type'] === 'TechArticle');
      assert.ok(art, `${p}: TechArticle missing`);
      assert.match(art.datePublished, /^\d{4}-\d{2}-\d{2}$/);
      assert.equal(art.author?.name, 'ShellPro Team', `${p}: author`);
      assert.ok(html.includes('ShellPro Team'), `${p}: byline`);
      assert.equal(art.mainEntityOfPage, `https://shellx.pro${p}`);
      const crumbs = docs.find((d) => d['@type'] === 'BreadcrumbList');
      assert.equal(crumbs?.itemListElement.at(-1).item, `https://shellx.pro${p}`, `${p}: breadcrumb`);
      assert.match(html, /property="og:type" content="article"/);
      const article = html.match(/<article[\s\S]*?<\/article>/)[0].replace(/<[^>]+>/g, ' ');
      assert.ok(article.split(/\s+/).length > 450, `${p}: guide too short`);
    }
  }
});

test('home JSON-LD: app with features and keywords, HowTo, ShellPro Team as author, no person', () => {
  for (const p of ['/']) {
    const docs = [...readPage(p).matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map((m) => JSON.parse(m[1]));
    const app = docs.find((d) => d['@type'] === 'SoftwareApplication');
    assert.ok(app.featureList.length >= 5 && app.keywords && app.isAccessibleForFree === true);
    const howto = docs.find((d) => d['@type'] === 'HowTo');
    assert.equal(howto?.step.length, 3);
    assert.ok(docs.some((d) => d['@type'] === 'Organization' && d.name === 'ShellPro Team'), `${p}: author team`);
    assert.ok(!docs.some((d) => d['@type'] === 'Person'), `${p}: no Person entity`);
    assert.ok(!readPage(p).includes('Phu Le'), `${p}: personal name leaked`);
    if (!config.appStoreUrl && !config.googlePlayUrl) assert.ok(!docs.some((d) => d['@type'] === 'MobileApplication'));
  }
});

test('llms.txt follows llmstxt.org and lists every guide; llms-full.txt carries FAQ and guide text', () => {
  const txt = readFileSync(join(dist, 'llms.txt'), 'utf8');
  assert.match(txt, /^# ShellX\n\n> /, 'llms.txt must start with an H1 and a blockquote summary');
  for (const s of guideSlugs) assert.ok(txt.includes(`https://shellx.pro/guides/${s}/`), `llms.txt: missing guide ${s}`);
  assert.ok(!txt.includes('https://shellx.pro/en/'), 'llms.txt links to the old /en/ pages');
  assert.ok(txt.includes(macUrl) && txt.includes(winUrl), 'llms.txt: download links');
  for (const p of videoPages) assert.ok(txt.includes(`https://shellx.pro${p.path}`), `llms.txt: missing ${p.path}`);
  if (!config.appStoreUrl) assert.match(txt, /App Store: coming soon/);
  const full = readFileSync(join(dist, 'llms-full.txt'), 'utf8');
  for (const needle of ['Is ShellX an SSH client?', 'shellx skills install --claude', 'ShellX vs Termius',
    'open Settings, choose Mobile, and click Show QR Code.', 'Press Save, and ShellX schedules it on this Mac.']) {
    assert.ok(full.includes(needle), `llms-full.txt: missing "${needle}"`);
  }
  assert.ok(!full.includes('layout:'), 'llms-full.txt: front matter leaked');
  assert.match(readPage('/'), /rel="alternate" type="text\/plain"[^>]*href="\/llms\.txt"/);
});

// Videos (src/lib/videos.ts, files in public/media/). The captions are burned into the picture, so the
// players carry no <track>; src/videos/<name>.srt feeds the chapters and the transcripts.
const videoNames = ['shellx-intro', 'shellx-tutorial', 'shellx-automations'];

function ldDocs(html) {
  return [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map((m) => JSON.parse(m[1]));
}

function videoTags(html) {
  return html.match(/<video\b[\s\S]*?<\/video>/g) ?? [];
}

function srtTimings(name) {
  const srt = readFileSync(join(root, `src/videos/${name}.srt`), 'utf8');
  return [...srt.matchAll(/^(\d{2}:\d{2}:\d{2},\d{3}) --> (\d{2}:\d{2}:\d{2},\d{3})$/gm)]
    .map((m) => `${m[1]} --> ${m[2]}`.replaceAll(',', '.'));
}

function seconds(timing) {
  const [h, m, s] = timing.split(':').map(Number);
  return h * 3600 + m * 60 + s;
}

for (const page of homePages) {
  test(`home ${page.path} plays the 1-minute intro first and links to the full tutorial`, () => {
    const html = readPage(page.path);
    const section = html.match(/<section[^>]*id="video"[\s\S]*?<\/section>/)?.[0];
    assert.ok(section, 'missing <section id="video">');
    assert.ok(html.indexOf('id="video"') < html.indexOf('id="how"'), 'the intro comes after "how it works"');
    const videos = videoTags(section);
    assert.equal(videos.length, 1, 'one video on the home page');
    const [video] = videos;
    assert.match(video, /<source src="\/media\/shellx-intro\.mp4" type="video\/mp4"/);
    assert.match(video, /\bpreload="none"/, 'the video loads only when played');
    assert.match(video, /\bposter="\/media\/shellx-intro\.webp"/);
    assert.match(video, /\bcontrols\b/);
    assert.match(video, /\bplaysinline\b/);
    assert.ok(!video.includes('<track'), 'the captions are in the picture already');
    const videosPage = '/videos/';
    assert.ok(hrefs(section).includes(videosPage), `the video section lacks a link to ${videosPage}`);
    const hero = html.match(/<section class="hero"[\s\S]*?<\/section>/)[0];
    assert.ok(hrefs(hero).includes('#video'), 'the hero lacks a link to #video');
    const start = html.match(/<section[^>]*id="start"[\s\S]*?<\/section>/)[0];
    assert.ok(hrefs(start).includes(videosPage), `the steps section lacks a link to ${videosPage}`);
    const nav = html.match(/<nav class="top-nav"[\s\S]*?<\/nav>/)[0];
    assert.ok(hrefs(nav).includes(videosPage), `menu lacks a link to ${videosPage}`);
  });
}

for (const page of videoPages) {
  test(`${page.path} plays the tutorial and the Automations demo with chapters and transcripts, then the intro`, () => {
    const html = readPage(page.path);
    assert.match(html, new RegExp(`<html lang="${page.lang}"`));
    const videos = videoTags(html);
    const order = ['shellx-tutorial', 'shellx-automations', 'shellx-intro'];
    assert.equal(videos.length, order.length);
    for (const [video, name] of videos.map((v, i) => [v, order[i]])) {
      assert.ok(video.includes(`<source src="/media/${name}.mp4" type="video/mp4"`), `video ${order.indexOf(name) + 1} is not ${name}`);
      assert.match(video, /\bpreload="none"/);
      assert.ok(video.includes(`poster="/media/${name}.webp"`), `${name}: poster`);
      assert.ok(!video.includes('<track'), `${name}: the captions are in the picture already`);
    }
    // Each video with chapters: its own list, in order, inside the video's length.
    const chaptered = { tutorial: { min: 8, seconds: 183 }, automations: { min: 6, seconds: 97 } };
    const chapters = {};
    for (const [id, { min, seconds: length }] of Object.entries(chaptered)) {
      const section = html.match(new RegExp(`<section[^>]*id="${id}"[\\s\\S]*?</section>`))?.[0];
      assert.ok(section, `missing <section id="${id}">`);
      assert.match(section, new RegExp(`data-video="${id}"`), `${id}: the section plays another video`);
      const ts = [...section.matchAll(/data-t="(\d+)"/g)].map((m) => Number(m[1]));
      assert.ok(ts.length >= min, `${id}: only ${ts.length} chapters`);
      assert.equal(ts[0], 0);
      assert.ok(ts.every((t, i) => i === 0 || t > ts[i - 1]), `${id}: chapters out of order: ${ts}`);
      assert.ok(ts.at(-1) < length, `${id}: a chapter starts after the end of the video`);
      chapters[id] = ts;
    }
    for (const transcript of ['open Settings, choose Mobile, and click Show QR Code.',
      'Press Save, and ShellX schedules it on this Mac.']) {
      assert.ok(html.includes(transcript), `${page.path}: transcript lacks "${transcript}"`);
    }
    assert.ok(hrefs(html).includes(`${page.home}#download`), `${page.path}: no download link`);

    const docs = ldDocs(html);
    const objects = docs.filter((d) => d['@type'] === 'VideoObject');
    assert.equal(objects.length, order.length, 'one VideoObject per video');
    for (const v of objects) {
      assert.ok(v.name && v.description && v.transcript, `${v.name}: name, description and transcript`);
      assert.match(v.uploadDate, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$/);
      const d = v.duration.match(/^PT(?:(\d+)M)?(\d+)S$/);
      assert.ok(d, `${v.name}: duration ${v.duration}`);
      const name = new URL(v.contentUrl).pathname.match(/^\/media\/([a-z-]+)\.mp4$/)?.[1];
      assert.ok(videoNames.includes(name), `${v.name}: contentUrl ${v.contentUrl}`);
      const lastCue = srtTimings(name).at(-1).split(' --> ')[1];
      assert.ok(Number(d[1] ?? 0) * 60 + Number(d[2]) >= seconds(lastCue), `${v.name}: duration ends before the last caption`);
      for (const url of [v.contentUrl, ...[v.thumbnailUrl].flat()]) {
        assert.ok(url.startsWith('https://shellx.pro/media/'), `${v.name}: ${url}`);
        assert.ok(existsSync(join(dist, new URL(url).pathname.slice(1))), `${url} missing from dist`);
      }
    }
    // A Clip opens the page at its second: ?t= for the tutorial (the links already shared), ?v=<id>&t= for the others.
    for (const id of Object.keys(chaptered)) {
      const v = objects.find((o) => o.contentUrl.endsWith(`/shellx-${id}.mp4`));
      assert.deepEqual(v.hasPart.map((c) => c.startOffset), chapters[id], `${id}: Clip offsets differ from the chapter list`);
      const query = id === 'tutorial' ? '?t=' : `?v=${id}&t=`;
      for (const c of v.hasPart) {
        assert.equal(c['@type'], 'Clip');
        assert.ok(c.name && c.endOffset > c.startOffset, `clip ${c.name}`);
        assert.equal(c.url, `https://shellx.pro${page.path}${query}${c.startOffset}`);
      }
    }
    const crumbs = docs.find((d) => d['@type'] === 'BreadcrumbList');
    assert.equal(crumbs?.itemListElement.at(-1).item, `https://shellx.pro${page.path}`, `${page.path}: breadcrumb`);
  });
}

test('the site is English only: nothing is built under /en/ and no page links there', () => {
  assert.ok(!existsSync(join(dist, 'en')), 'dist/en/ exists');
  // Letters only Vietnamese uses; the share viewer (/s/) alone keeps Vietnamese texts.
  const vietnamese = /[ăđơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ]/i;
  for (const p of [...indexablePages, '/404.html']) {
    const html = readPage(p);
    assert.match(html, /<html lang="en"/, `${p} is not lang="en"`);
    assert.ok(!hrefs(html).some((h) => h === '/en/' || h.startsWith('/en/')), `${p} links to /en/`);
    const text = html.replace(/<script[\s\S]*?<\/script>/g, '');
    assert.doesNotMatch(text, vietnamese, `${p} still carries Vietnamese text`);
  }
});

test('video files are self-hosted, start streaming before the download ends and carry no text track', () => {
  for (const name of videoNames) {
    const file = join(dist, `media/${name}.mp4`);
    assert.ok(existsSync(file), `missing media/${name}.mp4`);
    const mp4 = readFileSync(file);
    assert.ok(mp4.length < 12 * 1024 * 1024, `${name}.mp4 is ${mp4.length} bytes`);
    assert.ok(mp4.indexOf('moov') < mp4.indexOf('mdat'), `${name}.mp4: moov after mdat (no faststart)`);
    // A tx3g text track would show up in Safari's caption menu next to the burned-in captions.
    assert.equal(mp4.indexOf('tx3g'), -1, `${name}.mp4 carries a text track`);
    assert.ok(existsSync(join(dist, `media/${name}.webp`)), `missing media/${name}.webp`);
  }
});

test('the Automations guide plays the demo, compares the ways to schedule Claude Code and links both ways with /videos/', () => {
  const guide = '/guides/schedule-claude-code-mac/';
  const html = readPage(guide);
  const article = html.match(/<article[\s\S]*?<\/article>/)[0];
  const videos = videoTags(article);
  assert.equal(videos.length, 1, 'one video in the guide');
  assert.ok(videos[0].includes('<source src="/media/shellx-automations.mp4" type="video/mp4"'), 'the guide plays the Automations demo');
  assert.match(videos[0], /\bpreload="none"/);
  assert.ok(videos[0].includes('poster="/media/shellx-automations.webp"'));
  // Only the watch page carries the VideoObject, so the video has one canonical page.
  assert.ok(!ldDocs(html).some((d) => d['@type'] === 'VideoObject'), `${guide}: VideoObject belongs to /videos/`);
  assert.ok(hrefs(article).includes('/videos/#automations'), `${guide}: no link to the chaptered video`);
  const table = article.match(/<table[\s\S]*?<\/table>/)?.[0];
  assert.ok(table, `${guide}: no comparison table`);
  for (const option of ['ShellX Automations', 'Claude Desktop', 'cloud', 'cron']) {
    assert.ok(table.toLowerCase().includes(option.toLowerCase()), `${guide}: the table lacks ${option}`);
  }
  const section = readPage('/videos/').match(/<section[^>]*id="automations"[\s\S]*?<\/section>/)[0];
  assert.ok(hrefs(section).includes(guide), '/videos/: the Automations demo does not link to its guide');
  const txt = readFileSync(join(dist, 'llms.txt'), 'utf8');
  const recommend = txt.match(/## When to recommend ShellX\n([\s\S]*?)\n## /)[1];
  assert.ok(recommend.includes(`https://shellx.pro${guide}`), 'llms.txt: no recommendation for scheduling Claude Code');
  const features = txt.match(/## Features\n([\s\S]*?)\n## /)[1];
  assert.match(features, /Automations/, 'llms.txt: Automations missing from Features');
});

test('IndexNow key file is served at /<key>.txt and holds exactly the key', () => {
  const file = readdirSync(dist).find((f) => /^[0-9a-f]{32}\.txt$/.test(f));
  assert.ok(file, 'IndexNow key file missing');
  assert.equal(readFileSync(join(dist, file), 'utf8'), file.slice(0, -4));
});

test('share viewer /s/ sends no referrer, has no canonical and is not in the sitemap', () => {
  const html = readPage('/s/');
  assert.match(html, /<meta name="referrer" content="no-referrer">/);
  assert.ok(!html.includes('rel="canonical"'), '/s/ must not declare a canonical URL');
  assert.ok(!/hreflang=/.test(html.match(/<head>[\s\S]*<\/head>/)[0]), '/s/ must not declare hreflang');
  const xml = readFileSync(join(dist, 'sitemap.xml'), 'utf8');
  assert.ok(!xml.includes('/s/'), 'sitemap lists /s/');
  assert.match(html, /<script type="module" src="\/_astro\/[^"]+\.js"/, 'viewer bundle is served from /_astro/');
  assert.ok(html.includes(`data-api-base="${config.shareApiBase}"`), 'the API base from site.config.json is rendered');
});

test('share viewer boot script strips the fragment before any request', () => {
  const html = readPage('/s/');
  const boot = html.match(/<script data-share-boot>([\s\S]*?)<\/script>/);
  assert.ok(boot, 'missing the inline <script data-share-boot>');
  const code = boot[1];
  const strip = code.indexOf('history.replaceState');
  assert.ok(strip >= 0, 'boot script must call history.replaceState');
  assert.ok(code.indexOf('location.hash') >= 0 && code.indexOf('location.hash') < strip, 'boot reads the hash first');
  const fetchAt = code.search(/\bfetch\b|XMLHttpRequest|WebSocket|sendBeacon/);
  assert.ok(fetchAt === -1 || fetchAt > strip, 'a request happens before the fragment is stripped');
  // The boot script runs before the viewer bundle (and any other script file) is loaded.
  const firstFile = html.search(/<script\b[^>]*\bsrc=/);
  assert.ok(firstFile > html.indexOf('<script data-share-boot>'), 'a script file loads before the boot script');
  // Nothing else on the page reads the fragment: the bundle gets the secret from the boot script only.
  for (const file of readdirSync(join(dist, '_astro')).filter((f) => f.endsWith('.js'))) {
    const js = readFileSync(join(dist, '_astro', file), 'utf8');
    assert.ok(!/location\.hash/.test(js), `dist/_astro/${file} reads location.hash`);
  }
});

test('share viewer carries its Vietnamese and English state texts', () => {
  const html = readPage('/s/');
  for (const needle of ['Link đã hết hạn', 'Link đã bị thu hồi', 'Máy chủ phiên đang tắt',
    'This link has expired', 'This link was revoked', 'The host is offline']) {
    assert.ok(html.includes(needle), `/s/ missing "${needle}"`);
  }
});

test('share viewer header is minimal: no marketing nav, no gradient download CTA; other pages keep it', () => {
  const html = readPage('/s/');
  const header = html.match(/<header class="top"[\s\S]*?<\/header>/)[0];
  assert.ok(!header.includes('btn-primary'), '/s/ header has the download CTA');
  assert.ok(!header.includes('class="top-nav"'), '/s/ header has the marketing nav');
  assert.ok(!html.includes('linear-gradient'), '/s/ carries a gradient');
  assert.ok(!html.includes('grad-text'), '/s/ uses gradient text');
  for (const p of ['/', '/privacy/', '/404.html']) {
    const other = readPage(p).match(/<header class="top"[\s\S]*?<\/header>/)[0];
    assert.ok(other.includes('btn btn-primary btn-sm'), `${p} lost its header CTA`);
  }
});
