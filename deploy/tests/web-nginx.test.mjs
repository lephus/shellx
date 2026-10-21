// Checks on deploy/web/nginx.conf itself (no Docker needed):
//   cd deploy && node --test tests/web-nginx.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const deployDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const nginx = readFileSync(join(deployDir, 'web', 'nginx.conf'), 'utf8');

const SHARE_PATTERN = '^/s/[0-9a-z]{4}-[0-9a-z]{4}/?$';
const CSP =
  "default-src 'self'; connect-src https://relay.shellx.pro wss://relay.shellx.pro; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; frame-ancestors 'none'";

/** The text of the `server { … }` block whose `server_name` is shellx.pro. */
function shellxServer() {
  const blocks = nginx.split(/^server \{/m).slice(1);
  const block = blocks.find((b) => /^\s*server_name shellx\.pro;/m.test(b));
  assert.ok(block, 'the shellx.pro server block exists');
  return block;
}

/** The text of the `location ~ "<pattern>" { … }` block inside the shellx.pro server. */
function shareLocation() {
  const server = shellxServer();
  const start = server.indexOf(`location ~ "${SHARE_PATTERN}" {`);
  assert.notEqual(start, -1, 'the /s/<id> location is inside the shellx.pro server block');
  const end = server.indexOf('\n    }', start);
  return server.slice(start, end);
}

test('the /s/<id> location is inside the shellx.pro server block', () => {
  assert.match(shareLocation(), /location ~ "\^\/s\/\[0-9a-z\]\{4\}-\[0-9a-z\]\{4\}\/\?\$" \{/);
});

test('the /s/<id> location serves the share viewer with its three headers', () => {
  const loc = shareLocation();
  assert.ok(loc.includes('add_header Referrer-Policy "no-referrer" always;'), 'Referrer-Policy');
  assert.ok(loc.includes(`add_header Content-Security-Policy "${CSP}" always;`), 'CSP');
  assert.ok(loc.includes('add_header Cache-Control "no-store" always;'), 'Cache-Control');
  assert.ok(loc.includes('try_files /s/index.html =404;'), 'try_files');
});

test('the share pattern matches a share id with or without a trailing slash', () => {
  const re = new RegExp(SHARE_PATTERN);
  assert.ok(re.test('/s/k7f2-9qd1'));
  assert.ok(re.test('/s/k7f2-9qd1/'));
});

test('the share pattern rejects a missing id, a short id and upper-case ids', () => {
  const re = new RegExp(SHARE_PATTERN);
  assert.equal(re.test('/s/'), false);
  assert.equal(re.test('/s/k7f2'), false);
  assert.equal(re.test('/s/K7F2-9QD1'), false);
});
