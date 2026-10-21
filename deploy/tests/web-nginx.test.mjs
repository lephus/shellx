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

/**
 * The text from `start` to the `}` closing the block whose `{` is at `open`, found by counting braces.
 * `open` is passed in because a location header can contain braces of its own (the share regex's `{4}`).
 */
function braceBlock(text, start, open) {
  assert.equal(text[open], '{', 'the block opens at the expected brace');
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    if (text[i] === '{') depth++;
    if (text[i] === '}') {
      depth--;
      if (depth === 0) return text.slice(start, i + 1);
    }
  }
  assert.fail('the block has a closing brace');
}

/** The text of the `server { … }` block whose `server_name` is shellx.pro. */
function shellxServer() {
  for (const m of nginx.matchAll(/^server \{/gm)) {
    const block = braceBlock(nginx, m.index, m.index + 'server '.length);
    if (/^\s*server_name shellx\.pro;/m.test(block)) return block;
  }
  assert.fail('the shellx.pro server block exists');
}

/** The text of the `location <header> { … }` block inside the shellx.pro server. */
function locationBlock(header) {
  const server = shellxServer();
  const head = `location ${header} `;
  const start = server.indexOf(`${head}{`);
  assert.notEqual(start, -1, `location ${header} is inside the shellx.pro server block`);
  return braceBlock(server, start, start + head.length);
}

const shareLocation = () => locationBlock(`~ "${SHARE_PATTERN}"`);

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

test('/s/ without an id answers 404 instead of falling through to location /', () => {
  const loc = locationBlock('= /s/');
  assert.match(loc, /^location = \/s\/ \{\s*return 404;\s*\}$/);
});

test('/s/index.html is internal, so a direct request cannot serve the viewer without its headers', () => {
  const loc = locationBlock('= /s/index.html');
  assert.match(loc, /^location = \/s\/index\.html \{\s*internal;\s*\}$/);
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
