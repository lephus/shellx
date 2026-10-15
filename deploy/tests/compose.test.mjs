// Checks on deploy/docker-compose.yml itself (no Docker needed):
//   node --test deploy/tests/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const deployDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const compose = readFileSync(join(deployDir, 'docker-compose.yml'), 'utf8');

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

test('push: the relay gets FCM_SERVICE_ACCOUNT from .env (empty by default) and ./secrets read-only', () => {
  const relay = service('relay');
  assert.match(relay, /^ {6}FCM_SERVICE_ACCOUNT: \$\{FCM_SERVICE_ACCOUNT:-\}$/m);
  assert.match(relay, /^ {6}- \.\/secrets:\/secrets:ro$/m);
  // The secret itself never goes through relay.env (synced from the repository on every deploy).
  assert.doesNotMatch(readFileSync(join(deployDir, 'relay.env'), 'utf8'), /FCM/);
});

test('admin: the relay also serves admin.shellx.pro, with its own certificate, and gets ADMIN_PASSWORD from .env only', () => {
  const relay = service('relay');
  assert.match(relay, /^ {6}VIRTUAL_HOST: relay\.shellx\.pro,admin\.shellx\.pro$/m);
  assert.match(relay, /^ {6}LETSENCRYPT_HOST: relay\.shellx\.pro,admin\.shellx\.pro$/m);
  // A certificate per name: a failure to issue admin's never touches the relay's (the apps' only way in).
  assert.match(relay, /^ {6}LETSENCRYPT_SINGLE_DOMAIN_CERTS: "true"$/m);
  // Empty by default (admin disabled); the value lives in the VPS's .env, never in synced files.
  assert.match(relay, /^ {6}ADMIN_PASSWORD: \$\{ADMIN_PASSWORD:-\}$/m);
  assert.doesNotMatch(readFileSync(join(deployDir, 'relay.env'), 'utf8'), /ADMIN/);
  // The web container must not claim the admin name too.
  assert.doesNotMatch(service('web'), /admin\.shellx\.pro/);
});

test('admin: nginx-proxy settings for admin.shellx.pro turn the access log off and keep request bodies small', () => {
  const vhost = readFileSync(join(deployDir, 'nginx-proxy', 'admin.shellx.pro'), 'utf8');
  // README step 5 copies a file only if it lacks this marker line, and the privacy policy promises no access logs.
  assert.match(vhost, /^access_log off;$/m);
  assert.match(vhost, /^client_max_body_size 16k;$/m);
  // Every name the compose file routes has its vhost.d original, and README step 5 copies each of them.
  const readme = readFileSync(join(deployDir, 'README.md'), 'utf8');
  for (const host of ['relay.shellx.pro', 'admin.shellx.pro', 'shellx.pro', 'www.shellx.pro', 'download.shellx.pro']) {
    assert.ok(readFileSync(join(deployDir, 'nginx-proxy', host), 'utf8').includes('access_log off;'), host);
    assert.match(readme, new RegExp(`^ {3}for f in .*(?<= )${host.replaceAll('.', '\\.')}(?= |;)`, 'm'), `README step 5 loop lacks ${host}`);
  }
});
