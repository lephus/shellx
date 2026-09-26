// @ts-check
import { defineConfig } from 'astro/config';

// Static site served by nginx in the `web` container (deploy/web/nginx.conf). Every page is emitted
// as <path>/index.html, so internal links use a trailing slash (/privacy/, /en/terms/); nginx
// redirects /privacy to /privacy/.
export default defineConfig({
  site: 'https://shellx.pro',
  build: { format: 'directory' },
});
