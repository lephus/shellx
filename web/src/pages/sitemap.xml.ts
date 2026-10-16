import type { APIRoute } from 'astro';
import { pathFor, type Lang, type Page } from '../i18n/ui';
import { guidePath, guides, siteUrl as site } from '../lib/seo';

const langs: Lang[] = ['vi', 'en'];

// lastmod: legal pages use their front-matter `updated`, guides theirs; home and the guide index use
// the build date (they change with every content or design update).
const legal = import.meta.glob<{ frontmatter: { lang: Lang; page: Page; updated: string } }>(
  ['./privacy.md', './terms.md', './en/privacy.md', './en/terms.md'],
  { eager: true },
);
const buildDate = new Date().toISOString().slice(0, 10);

function legalDate(lang: Lang, page: Page): string {
  const doc = Object.values(legal).find((m) => m.frontmatter.lang === lang && m.frontmatter.page === page);
  return doc?.frontmatter.updated ?? buildDate;
}

interface Entry { paths: Record<Lang, string>; lastmod: (lang: Lang) => string }

const pageEntries: Entry[] = (['home', 'guides', 'privacy', 'terms'] as Page[]).map((page) => ({
  paths: { vi: pathFor('vi', page), en: pathFor('en', page) },
  lastmod: (lang) => (page === 'privacy' || page === 'terms' ? legalDate(lang, page) : buildDate),
}));

const guideEntries: Entry[] = guides('vi').map((g) => ({
  paths: { vi: guidePath('vi', g.slug), en: guidePath('en', g.slug) },
  lastmod: (lang) => guides(lang).find((x) => x.slug === g.slug)?.updated ?? g.updated,
}));

export const GET: APIRoute = () => {
  const urls = [...pageEntries, ...guideEntries].flatMap((e) =>
    langs.map((lang) => {
      const alts = langs
        .map((l) => `<xhtml:link rel="alternate" hreflang="${l}" href="${site}${e.paths[l]}"/>`)
        .join('');
      const xDefault = `<xhtml:link rel="alternate" hreflang="x-default" href="${site}${e.paths.vi}"/>`;
      return `<url><loc>${site}${e.paths[lang]}</loc><lastmod>${e.lastmod(lang)}</lastmod>${alts}${xDefault}</url>`;
    }),
  );
  const xml =
    `<?xml version="1.0" encoding="UTF-8"?>` +
    `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">` +
    urls.join('') +
    `</urlset>`;
  return new Response(xml, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
};
