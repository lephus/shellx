import type { APIRoute } from 'astro';
import { pathFor, type Lang, type Page } from '../i18n/ui';

const site = 'https://shellx.pro';
const pages: Page[] = ['home', 'privacy', 'terms'];
const langs: Lang[] = ['vi', 'en'];

export const GET: APIRoute = () => {
  const entries = pages.flatMap((page) =>
    langs.map((lang) => {
      const alts = langs
        .map((l) => `<xhtml:link rel="alternate" hreflang="${l}" href="${site}${pathFor(l, page)}"/>`)
        .join('');
      return `<url><loc>${site}${pathFor(lang, page)}</loc>${alts}</url>`;
    }),
  );
  const xml =
    `<?xml version="1.0" encoding="UTF-8"?>` +
    `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">` +
    entries.join('') +
    `</urlset>`;
  return new Response(xml, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
};
