// Refuses to build the site while any page still contains the "[quốc gia]" placeholder: the country
// where the VPS is hosted must be written into the privacy policy before the public site is
// deployed (VPS spec §9). Usage: node scripts/check-placeholders.mjs [dir]   (default: src)
import { readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { pathToFileURL } from 'node:url';

export const MARKER = '[quốc gia]';

/** Every `file:line` under `dir` whose text (NFC-normalised) contains MARKER. */
export function findPlaceholders(dir) {
  const hits = [];
  const walk = (current) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const path = join(current, entry.name);
      if (entry.isDirectory()) {
        walk(path);
        continue;
      }
      const lines = readFileSync(path, 'utf8').normalize('NFC').split('\n');
      lines.forEach((line, index) => {
        if (line.includes(MARKER)) hits.push(`${relative(process.cwd(), path)}:${index + 1}`);
      });
    }
  };
  walk(dir);
  return hits;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const hits = findPlaceholders(process.argv[2] ?? 'src');
  if (hits.length > 0) {
    console.error(`Refusing to build: replace the ${MARKER} placeholder (the country where the VPS is hosted) in:`);
    for (const hit of hits) console.error(`  ${hit}`);
    process.exit(1);
  }
}
