import type { APIRoute } from 'astro';
import { pathFor, type Lang, type Page } from '../i18n/ui';
import { guides, siteUrl as site } from '../lib/seo';

const lang: Lang = 'en';

// lastmod: legal pages use their front-matter `updated`, guides theirs; home, the videos and the guide
// index use the build date (they change with every content or design update).
const legal = import.meta.glob<{ frontmatter: { page: Page; updated: string } }>(
  ['./privacy.md', './terms.md'],
  { eager: true },
);
const buildDate = new Date().toISOString().slice(0, 10);

function legalDate(page: Page): string {
  return Object.values(legal).find((m) => m.frontmatter.page === page)?.frontmatter.updated ?? buildDate;
}

const pageEntries = (['home', 'videos', 'guides', 'privacy', 'terms'] as Page[]).map((page) => ({
  path: pathFor(lang, page),
  lastmod: page === 'privacy' || page === 'terms' ? legalDate(page) : buildDate,
}));

const guideEntries = guides(lang).map((g) => ({ path: g.path, lastmod: g.updated }));

export const GET: APIRoute = () => {
  const urls = [...pageEntries, ...guideEntries].map(
    (e) => `<url><loc>${site}${e.path}</loc><lastmod>${e.lastmod}</lastmod></url>`,
  );
  const xml =
    `<?xml version="1.0" encoding="UTF-8"?>` +
    `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">` +
    urls.join('') +
    `</urlset>`;
  return new Response(xml, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
};
