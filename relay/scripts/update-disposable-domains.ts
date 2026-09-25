// Refreshes src/auth/disposable-domains.json from the upstream blocklist.
// Usage: npm run domains:update   (then review the diff and commit it)
import { writeFile } from "node:fs/promises";
import { parseBlocklist, renderDomainsJson } from "./blocklist";

const SOURCE_URL =
  "https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/main/disposable_email_blocklist.conf";
const OUTPUT = new URL("../src/auth/disposable-domains.json", import.meta.url);
const MIN_EXPECTED = 1000;

const response = await fetch(SOURCE_URL);
if (!response.ok) throw new Error(`download failed: HTTP ${response.status}`);
const domains = parseBlocklist(await response.text());
if (domains.length < MIN_EXPECTED) throw new Error(`only ${domains.length} domains downloaded; refusing to write`);
await writeFile(OUTPUT, renderDomainsJson(domains), "utf8");
console.log(`wrote ${domains.length} domains to src/auth/disposable-domains.json`);
