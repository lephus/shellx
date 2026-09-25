// @ts-check
import { defineConfig } from 'astro/config';

// Static site for Cloudflare Pages. Every page is emitted as <path>/index.html, so internal
// links use a trailing slash (/privacy/, /en/terms/); Pages redirects /privacy to /privacy/.
export default defineConfig({
  site: 'https://shellx.pro',
  build: { format: 'directory' },
});
