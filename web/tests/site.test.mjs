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

const guideSlugs = ['claude-code-on-phone', 'ssh-from-phone', 'remote-terminal-without-vpn', 'shellx-vs-termius', 'shellx-vs-tailscale'];
const guidePages = ['/guides/', '/en/guides/', ...guideSlugs.flatMap((s) => [`/guides/${s}/`, `/en/guides/${s}/`])];
const indexablePages = ['/', '/en/', '/privacy/', '/terms/', '/en/privacy/', '/en/terms/', ...guidePages];
const everyPage = [...indexablePages, '/404.html'];

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
  assert.match(config.supportEmail, /^[^@\s]+@[^@\s]+\.[^@\s]+$/);
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
  const allPages = everyPage;
  for (const p of allPages) {
    const count = (readPage(p).match(/<h1[\s>]/g) ?? []).length;
    assert.equal(count, 1, `${p} has ${count} h1`);
  }
});

test('self-hosted font files exist and are preloaded', () => {
  for (const f of ['JetBrainsMono-Regular', 'JetBrainsMono-Bold', 'SpaceGrotesk-Latin', 'SpaceGrotesk-Vietnamese']) {
    assert.ok(existsSync(join(dist, `fonts/${f}.woff2`)), `missing fonts/${f}.woff2`);
  }
  const html = readPage('/');
  assert.match(html, /rel="preload" as="font"[^>]*SpaceGrotesk-Latin\.woff2/);
  assert.match(html, /rel="preload" as="font"[^>]*SpaceGrotesk-Vietnamese\.woff2/);
  assert.match(html, /rel="preload" as="font"[^>]*JetBrainsMono-Regular\.woff2/);
});

test('home has the landing sections: hero, how it works, features, security, steps, FAQ, download', () => {
  for (const p of ['/', '/en/']) {
    const html = readPage(p);
    for (const id of ['how', 'features', 'security', 'start', 'faq', 'download']) {
      assert.match(html, new RegExp(`<section[^>]*id="${id}"`), `${p}: missing section #${id}`);
    }
    assert.match(html, /data-demo/, `${p}: hero demo missing`);
    assert.equal((html.match(/class="pillar /g) ?? []).length, 3, `${p}: need 3 pillars`);
    assert.equal((html.match(/class="feature"/g) ?? []).length, 6, `${p}: need 6 feature cards`);
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
  for (const p of ['/', '/en/']) {
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

const seoPages = indexablePages.map((path) => {
  const lang = path.startsWith('/en/') ? 'en' : 'vi';
  return { path, lang, pair: lang === 'en' ? path.slice(3) : `/en${path}` };
});

function unescapeHtml(s) {
  return s.replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&amp;/g, '&');
}

for (const page of seoPages) {
  test(`SEO basics on ${page.path}: title, description, canonical, reciprocal hreflang, icons`, () => {
    const html = readPage(page.path);
    const title = unescapeHtml(html.match(/<title>([^<]*)<\/title>/)?.[1] ?? '');
    const description = unescapeHtml(html.match(/<meta name="description" content="([^"]*)"/)?.[1] ?? '');
    assert.ok(title.length >= 20 && title.length <= 65, `${page.path}: title is ${title.length} chars: ${title}`);
    assert.ok(description.length >= 70 && description.length <= 165,
      `${page.path}: description is ${description.length} chars`);
    assert.ok(html.includes(`<link rel="canonical" href="https://shellx.pro${page.path}">`), `${page.path}: canonical`);
    const otherLang = page.lang === 'vi' ? 'en' : 'vi';
    assert.ok(html.includes(`hreflang="${otherLang}" href="https://shellx.pro${page.pair}"`), `${page.path}: hreflang to ${page.pair}`);
    assert.ok(readPage(page.pair).includes(`hreflang="${page.lang}" href="https://shellx.pro${page.path}"`),
      `${page.pair} does not point back to ${page.path}`);
    assert.match(html, /hreflang="x-default"/);
    assert.match(html, /rel="apple-touch-icon" href="\/apple-touch-icon\.png"/);
    assert.match(html, /rel="manifest" href="\/site\.webmanifest"/);
    assert.ok(!/name="robots" content="[^"]*noindex/.test(html), `${page.path} is noindex`);
  });
}

test('home JSON-LD has FAQPage matching the visible FAQ, Organization and download URLs', () => {
  for (const p of ['/', '/en/']) {
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

test('manifest icons exist; sitemap carries lastmod and x-default for every page', () => {
  const manifest = JSON.parse(readFileSync(join(dist, 'site.webmanifest'), 'utf8'));
  for (const icon of manifest.icons) assert.ok(existsSync(join(dist, icon.src.slice(1))), `missing ${icon.src}`);
  const xml = readFileSync(join(dist, 'sitemap.xml'), 'utf8');
  assert.equal((xml.match(/<lastmod>\d{4}-\d{2}-\d{2}<\/lastmod>/g) ?? []).length, indexablePages.length);
  assert.equal((xml.match(/hreflang="x-default"/g) ?? []).length, indexablePages.length);
});

test('404 is noindex; every indexable page is index, follow', () => {
  assert.match(readPage('/404.html'), /<meta name="robots" content="noindex"/);
  for (const p of indexablePages) assert.match(readPage(p), /<meta name="robots" content="index, follow/, p);
});

test('home links to the guides; every guide links back to downloads and to other guides', () => {
  for (const [home, prefix] of [['/', '/guides/'], ['/en/', '/en/guides/']]) {
    const links = hrefs(readPage(home));
    assert.ok(links.includes(prefix), `${home}: no link to ${prefix}`);
    for (const s of ['claude-code-on-phone', 'ssh-from-phone', 'remote-terminal-without-vpn']) {
      assert.ok(links.includes(`${prefix}${s}/`), `${home}: no link to guide ${s}`);
    }
    const index = hrefs(readPage(prefix));
    for (const s of guideSlugs) assert.ok(index.includes(`${prefix}${s}/`), `${prefix}: missing ${s}`);
  }
  for (const s of guideSlugs) {
    for (const [p, home] of [[`/guides/${s}/`, '/'], [`/en/guides/${s}/`, '/en/']]) {
      const links = hrefs(readPage(p));
      assert.ok(links.includes(`${home}#download`), `${p}: no download link`);
      const others = new Set(links.filter((l) => /\/guides\/[a-z-]+\/$/.test(l) && l !== p));
      assert.ok(others.size >= 4, `${p}: only ${others.size} related guides`);
    }
  }
});

test('guides carry TechArticle and BreadcrumbList JSON-LD with author and dates', () => {
  for (const s of guideSlugs) {
    for (const p of [`/guides/${s}/`, `/en/guides/${s}/`]) {
      const html = readPage(p);
      const docs = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map((m) => JSON.parse(m[1]));
      const art = docs.find((d) => d['@type'] === 'TechArticle');
      assert.ok(art, `${p}: TechArticle missing`);
      assert.match(art.datePublished, /^\d{4}-\d{2}-\d{2}$/);
      assert.ok(art.author?.sameAs?.includes('https://github.com/lephus'), `${p}: author sameAs`);
      assert.equal(art.mainEntityOfPage, `https://shellx.pro${p}`);
      const crumbs = docs.find((d) => d['@type'] === 'BreadcrumbList');
      assert.equal(crumbs?.itemListElement.at(-1).item, `https://shellx.pro${p}`, `${p}: breadcrumb`);
      assert.match(html, /property="og:type" content="article"/);
      const article = html.match(/<article[\s\S]*?<\/article>/)[0].replace(/<[^>]+>/g, ' ');
      assert.ok(article.split(/\s+/).length > 450, `${p}: guide too short`);
    }
  }
});

test('home JSON-LD: app with features and keywords, HowTo, founder with sameAs', () => {
  for (const p of ['/', '/en/']) {
    const docs = [...readPage(p).matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map((m) => JSON.parse(m[1]));
    const app = docs.find((d) => d['@type'] === 'SoftwareApplication');
    assert.ok(app.featureList.length >= 5 && app.keywords && app.isAccessibleForFree === true);
    const howto = docs.find((d) => d['@type'] === 'HowTo');
    assert.equal(howto?.step.length, 3);
    const person = docs.find((d) => d['@type'] === 'Person');
    assert.deepEqual(person?.sameAs, [
      'https://huuphule.coregenaihub.com', 'https://www.linkedin.com/in/lehuuphu',
      'https://github.com/lephus', 'https://medium.com/@phule9225',
    ]);
    if (!config.appStoreUrl && !config.googlePlayUrl) assert.ok(!docs.some((d) => d['@type'] === 'MobileApplication'));
  }
});

test('llms.txt follows llmstxt.org and lists every guide; llms-full.txt carries FAQ and guide text', () => {
  const txt = readFileSync(join(dist, 'llms.txt'), 'utf8');
  assert.match(txt, /^# ShellX\n\n> /, 'llms.txt must start with an H1 and a blockquote summary');
  for (const s of guideSlugs) {
    assert.ok(txt.includes(`https://shellx.pro/en/guides/${s}/`), `llms.txt: missing en guide ${s}`);
    assert.ok(txt.includes(`https://shellx.pro/guides/${s}/`), `llms.txt: missing vi guide ${s}`);
  }
  assert.ok(txt.includes(macUrl) && txt.includes(winUrl), 'llms.txt: download links');
  if (!config.appStoreUrl) assert.match(txt, /App Store: coming soon/);
  const full = readFileSync(join(dist, 'llms-full.txt'), 'utf8');
  for (const needle of ['Is ShellX an SSH client?', 'ShellX có phải là SSH client không?', 'shellx skills install --claude', 'ShellX vs Termius']) {
    assert.ok(full.includes(needle), `llms-full.txt: missing "${needle}"`);
  }
  assert.ok(!full.includes('layout:'), 'llms-full.txt: front matter leaked');
  assert.match(readPage('/'), /rel="alternate" type="text\/plain"[^>]*href="\/llms\.txt"/);
});

test('IndexNow key file is served at /<key>.txt and holds exactly the key', () => {
  const file = readdirSync(dist).find((f) => /^[0-9a-f]{32}\.txt$/.test(f));
  assert.ok(file, 'IndexNow key file missing');
  assert.equal(readFileSync(join(dist, file), 'utf8'), file.slice(0, -4));
});
