import type { APIRoute } from 'astro';
import { pathFor, type Lang, type Page } from '../i18n/ui';

const site = 'https://shellx.pro';
const pages: Page[] = ['home', 'privacy', 'terms'];
const langs: Lang[] = ['vi', 'en'];

// lastmod: legal pages use their front-matter `updated`; the home page uses the build date.
const legal = import.meta.glob<{ frontmatter: { lang: Lang; page: Page; updated: string } }>(
  ['./privacy.md', './terms.md', './en/privacy.md', './en/terms.md'],
  { eager: true },
);
const buildDate = new Date().toISOString().slice(0, 10);

function lastmod(lang: Lang, page: Page): string {
  const doc = Object.values(legal).find((m) => m.frontmatter.lang === lang && m.frontmatter.page === page);
  return doc?.frontmatter.updated ?? buildDate;
}

export const GET: APIRoute = () => {
  const entries = pages.flatMap((page) =>
    langs.map((lang) => {
      const alts = langs
        .map((l) => `<xhtml:link rel="alternate" hreflang="${l}" href="${site}${pathFor(l, page)}"/>`)
        .join('');
      const xDefault = `<xhtml:link rel="alternate" hreflang="x-default" href="${site}${pathFor('vi', page)}"/>`;
      return `<url><loc>${site}${pathFor(lang, page)}</loc><lastmod>${lastmod(lang, page)}</lastmod>${alts}${xDefault}</url>`;
    }),
  );
  const xml =
    `<?xml version="1.0" encoding="UTF-8"?>` +
    `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">` +
    entries.join('') +
    `</urlset>`;
  return new Response(xml, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
};
