// Checks on deploy/docker-compose.yml itself (no Docker needed):
//   node --test deploy/tests/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const compose = readFileSync(join(dirname(fileURLToPath(import.meta.url)), '..', 'docker-compose.yml'), 'utf8');

/** The lines of one service under `services:`, from its `  <name>:` line to the next top-level or service key. */
function service(name) {
  const lines = compose.split('\n');
  const start = lines.indexOf(`  ${name}:`);
  assert.notEqual(start, -1, `service ${name} not found`);
  let end = start + 1;
  while (end < lines.length && !/^ {0,2}\S/.test(lines[end])) end++;
  return lines.slice(start, end).join('\n');
}

test('the relay has a hard memory ceiling of 512 MB, swap included (mem_limit + memswap_limit, Compose v2), and still restarts on its own', () => {
  const relay = service('relay');
  assert.match(relay, /^ {4}mem_limit: 512m$/m);
  // Without it, a host with swap lets the container use up to twice mem_limit (swap included).
  assert.match(relay, /^ {4}memswap_limit: 512m$/m);
  // An OOM kill then restarts only the relay, and clients reconnect with backoff.
  assert.match(relay, /^ {4}restart: unless-stopped$/m);
  // deploy.resources.limits is ignored by `docker compose up` without swarm: it would look like a limit and be none.
  assert.doesNotMatch(compose, /^\s+deploy:/m);
});
