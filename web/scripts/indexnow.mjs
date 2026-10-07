// Tells IndexNow (Bing, Yandex, Seznam, Naver; Bing feeds ChatGPT search and DuckDuckGo) that every
// URL in the live sitemap changed. Run after a deploy: npm run indexnow
// The key is public by design: https://shellx.pro/<key>.txt must serve it (public/<key>.txt).
import { readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const host = 'shellx.pro';
const publicDir = join(dirname(fileURLToPath(import.meta.url)), '..', 'public');
const keyFile = readdirSync(publicDir).find((f) => /^[0-9a-f]{32}\.txt$/.test(f));
if (!keyFile) throw new Error('IndexNow key file public/<32 hex>.txt missing');
const key = keyFile.slice(0, -4);

const live = await fetch(`https://${host}/${keyFile}`);
if (!live.ok || (await live.text()).trim() !== key) {
  throw new Error(`https://${host}/${keyFile} does not serve the key yet — deploy first`);
}
const sitemap = await (await fetch(`https://${host}/sitemap.xml`)).text();
const urlList = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
if (urlList.length === 0) throw new Error('no <loc> in the live sitemap');

const res = await fetch('https://api.indexnow.org/indexnow', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json; charset=utf-8' },
  body: JSON.stringify({ host, key, keyLocation: `https://${host}/${keyFile}`, urlList }),
});
// 200 = accepted, 202 = accepted and key validation pending.
console.log(`IndexNow: ${res.status} for ${urlList.length} URLs`);
if (res.status !== 200 && res.status !== 202) process.exit(1);
