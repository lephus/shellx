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

// --- relay2 (cmux-relay), built on the VPS from a pinned commit, behind nginx-proxy at /v2/relay ---

const R = '57dd520ccf20b55c7eac662f1e09eae1c5069917';
const relayEnv = readFileSync(join(deployDir, 'relay.env'), 'utf8');

test('relay2: built locally from relay2-src/<R> (no registry image), only under the relay2 profile', () => {
  const relay2 = service('relay2');
  assert.match(relay2, /^ {4}profiles: \["relay2"\]$/m);
  assert.match(relay2, /^ {4}image: shellx-relay2:([0-9a-f]{40})$/m);
  assert.doesNotMatch(relay2, /ghcr\.io/);
  assert.match(relay2, /^ {4}pull_policy: never$/m);
  const sha = relay2.match(/^ {4}image: shellx-relay2:([0-9a-f]{40})$/m)[1];
  assert.equal(sha, R);
  assert.match(relay2, new RegExp(`^ {6}context: \\./relay2-src/${sha}$`, 'm'));
  assert.match(relay2, /^ {6}dockerfile: scripts\/shellx\/relay2\/Dockerfile$/m);
  assert.match(relay2, new RegExp(`^ {8}REVISION: ${sha}$`, 'm'));
});

test('relay2: restart, 256 MB ceiling without swap, read-only, no ports, no volumes, proxy network only', () => {
  const relay2 = service('relay2');
  assert.match(relay2, /^ {4}restart: unless-stopped$/m);
  assert.match(relay2, /^ {4}mem_limit: 256m$/m);
  assert.match(relay2, /^ {4}memswap_limit: 256m$/m);
  assert.match(relay2, /^ {4}read_only: true$/m);
  assert.doesNotMatch(relay2, /^ {4}ports:/m);
  assert.doesNotMatch(relay2, /^ {4}volumes:/m);
  assert.match(relay2, /^ {4}logging: \*logging$/m);
  assert.match(relay2, /^ {4}networks: \[proxy\]$/m);
});

test('relay2: routed by exact path /v2/relay (so /v2/relay/tickets stays on the Node relay), rewritten to /v1/relay, no certificate of its own', () => {
  const relay2 = service('relay2');
  assert.match(relay2, /^ {6}VIRTUAL_HOST: relay\.shellx\.pro$/m);
  assert.match(relay2, /^ {6}VIRTUAL_PATH: "= \/v2\/relay"$/m);
  assert.match(relay2, /^ {6}VIRTUAL_DEST: \/v1\/relay$/m);
  assert.match(relay2, /^ {6}VIRTUAL_PORT: "8787"$/m);
  assert.doesNotMatch(relay2, /LETSENCRYPT/);
  assert.match(relay2, /^ {6}CMUX_RELAY_BIND: 0\.0\.0\.0:8787$/m);
});

test('relay2 admits only the shellx.pro viewer origin (exact match)', () => {
  assert.match(service('relay2'), /^ {6}CMUX_RELAY_ALLOWED_ORIGINS: https:\/\/shellx\.pro$/m);
});

test('relay2 drops every capability and cannot gain privileges (uid 10001, port 8787)', () => {
  const relay2 = service('relay2');
  assert.match(relay2, /^ {4}cap_drop: \[ALL\]$/m);
  assert.match(relay2, /^ {4}security_opt: \["no-new-privileges:true"\]$/m);
});

test('relay2 healthcheck: bash /dev/tcp GET /healthz, 10 s interval, 3 retries, 10 s start period', () => {
  const relay2 = service('relay2');
  assert.ok(relay2.includes(
    String.raw`test: ["CMD", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8787 && printf 'GET /healthz HTTP/1.1\\r\\nHost: l\\r\\nConnection: close\\r\\n\\r\\n' >&3 && grep -q '\"status\":\"ok\"' <&3"]`,
  ));
  assert.match(relay2, /^ {6}interval: 10s$/m);
  assert.match(relay2, /^ {6}retries: 3$/m);
  assert.match(relay2, /^ {6}start_period: 10s$/m);
});

test('relay and relay2 take CMUX_RELAY_HMAC_SECRET from .env only; the issuer is exactly shellx-relay on both sides', () => {
  for (const name of ['relay', 'relay2']) {
    assert.match(service(name), /^ {6}CMUX_RELAY_HMAC_SECRET: \$\{CMUX_RELAY_HMAC_SECRET:-\}$/m, name);
  }
  assert.doesNotMatch(relayEnv, /SECRET/);
  // Node trims the issuer, cmux-relay reads it raw: no whitespace anywhere may differ between them.
  assert.match(relayEnv, /^CMUX_RELAY_ISSUER=shellx-relay$/m);
  assert.match(service('relay2'), /^ {6}CMUX_RELAY_ISSUER: shellx-relay$/m);
  assert.match(relayEnv, /^RELAY_V2_URL=wss:\/\/relay\.shellx\.pro\/v2\/relay$/m);
});

test('nginx-proxy relay.shellx.pro: 330 s timeouts (above cmux-relay 300 s idle) and still no access log', () => {
  const vhost = readFileSync(join(deployDir, 'nginx-proxy', 'relay.shellx.pro'), 'utf8');
  assert.match(vhost, /^proxy_read_timeout 330s;$/m);
  assert.match(vhost, /^proxy_send_timeout 330s;$/m);
  assert.match(vhost, /^access_log off;$/m);
});

test('deploy.yml: /v2/relay check only when RELAY2_ENABLED, /v2/relay/tickets always, relay2-src never synced', () => {
  const wf = readFileSync(join(deployDir, '..', '.github', 'workflows', 'deploy.yml'), 'utf8');
  assert.match(wf, /vars\.RELAY2_ENABLED/);
  assert.match(wf, /https:\/\/relay\.shellx\.pro\/v2\/relay\/tickets/);
  assert.match(wf, /"code":"unauthorized"/);
  assert.doesNotMatch(wf, /rsync[^\n]*relay2-src/);
});

test('README documents Relay v2 without any secret value', () => {
  const readme = readFileSync(join(deployDir, 'README.md'), 'utf8');
  assert.match(readme, /^## Relay v2/m);
  assert.match(readme, new RegExp(`relay2-src-${R}`));
  assert.match(readme, /COMPOSE_PROFILES=relay2/);
  assert.doesNotMatch(readme, /shellx-pro/);
});

test('README Relay v2 runbook has the G2 foreign_key_check pre-check on a copy of the database', () => {
  const readme = readFileSync(join(deployDir, 'README.md'), 'utf8');
  const section = readme.match(/^## Relay v2[\s\S]*?(?=\n## )/m)[0];
  assert.match(section, /PRAGMA foreign_key_check;/);
  assert.match(section, /COPY of\s+the production database, never on the live file/);
  assert.ok(section.indexOf('foreign_key_check') < section.indexOf('1. **VPS prerequisites**'), 'pre-check comes before the steps');
  assert.match(section, /before you push main with migration 0005/i);
  assert.match(section, /up to 24 h old/);
});

test('README Relay v2 runbook: merge with --no-ff, inline PROXY, pre-build, rollback note', () => {
  const readme = readFileSync(join(deployDir, 'README.md'), 'utf8');
  const section = readme.match(/^## Relay v2[\s\S]*?(?=\n## )/m)[0];
  assert.match(section, /git merge --no-ff/);
  assert.match(section, /never squash/i);
  assert.match(section, /PROXY=\$\(docker ps[^\n]*nginx-proxy\)/);
  assert.match(section, /docker compose --profile relay2 build relay2/);
  assert.ok(section.indexOf('build relay2') < section.indexOf("echo 'COMPOSE_PROFILES=relay2'"), 'pre-build comes before enabling the profile');
  assert.match(section, /workflow_dispatch[^\n]*\n?[^\n]*pre-v2/);
});

test('README switch-off removes the relay2 container (a deactivated profile makes no orphan) before dropping the profile', () => {
  const readme = readFileSync(join(deployDir, 'README.md'), 'utf8');
  const step = readme.match(/^7\. \*\*Roll back \/ switch off\.\*\*[\s\S]*?(?=\n## )/m)[0];
  assert.match(step, /docker compose --profile relay2 rm -sf relay2/);
  assert.doesNotMatch(step, /--remove-orphans/);
  assert.ok(step.indexOf('rm -sf relay2') < step.indexOf('COMPOSE_PROFILES'), 'remove the container first, then the profile');
});

test('native latest manifests: only the relay mounts ./downloads/desktop, read-only, and it needs no other volume change', () => {
  assert.match(service('relay'), /^ {6}- \.\/downloads\/desktop:\/srv\/downloads\/desktop:ro$/m);
  assert.doesNotMatch(service('relay2'), /downloads\/desktop/);
});
