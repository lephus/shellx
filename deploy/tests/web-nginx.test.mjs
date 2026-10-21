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

// --- every origin the share viewer connects to is allowed by the /s/ CSP connect-src ---

const repoDir = join(deployDir, '..');

/** The connect-src sources of the /s/<id> CSP, as written in nginx.conf. */
function shareConnectSrc() {
  const csp = shareLocation().match(/add_header Content-Security-Policy "([^"]*)" always;/)?.[1];
  assert.ok(csp, 'the /s/<id> location sets a CSP');
  const directive = csp.split(';').map((d) => d.trim()).find((d) => d.startsWith('connect-src '));
  assert.ok(directive, 'the /s/<id> CSP has connect-src');
  return directive.split(/\s+/).slice(1);
}

/** CSP host-source match for a scheme://host[:port] source (no wildcards or paths are used here). */
function allowedBy(sources, url) {
  const u = new URL(url);
  return sources.some((source) => {
    const m = source.match(/^([a-z][a-z0-9+.-]*):\/\/([^/:]+)(?::(\d+))?$/i);
    return m !== null && `${m[1].toLowerCase()}:` === u.protocol && m[2].toLowerCase() === u.hostname
      && (m[3] ?? '') === u.port;
  });
}

test('the share viewer API base (web/src/site.config.json) and its fallback are allowed by connect-src', () => {
  const sources = shareConnectSrc();
  const { shareApiBase } = JSON.parse(readFileSync(join(repoDir, 'web', 'src', 'site.config.json'), 'utf8'));
  assert.match(shareApiBase, /^https:\/\//);
  assert.ok(allowedBy(sources, shareApiBase), `${shareApiBase} is not in connect-src ${sources.join(' ')}`);
  const session = readFileSync(join(repoDir, 'web', 'src', 'share', 'session.mjs'), 'utf8');
  const fallback = session.match(/export const DEFAULT_API_BASE = '([^']+)';/)?.[1];
  assert.ok(fallback, 'session.mjs declares DEFAULT_API_BASE');
  assert.ok(allowedBy(sources, fallback), `${fallback} is not in connect-src ${sources.join(' ')}`);
});

test('the relay URL handed to viewers (RELAY_V2_URL default and relay.env) is allowed by connect-src', () => {
  const sources = shareConnectSrc();
  const config = readFileSync(join(repoDir, 'relay', 'src', 'config.ts'), 'utf8');
  const fallback = config.match(/export const DEFAULT_RELAY_V2_URL = "([^"]+)";/)?.[1];
  assert.ok(fallback, 'relay/src/config.ts declares DEFAULT_RELAY_V2_URL');
  const env = readFileSync(join(deployDir, 'relay.env'), 'utf8').match(/^RELAY_V2_URL=(\S+)$/m)?.[1];
  assert.ok(env, 'deploy/relay.env sets RELAY_V2_URL');
  for (const url of [fallback, env]) {
    assert.match(url, /^wss:\/\//);
    assert.ok(allowedBy(sources, url), `${url} is not in connect-src ${sources.join(' ')}`);
  }
});
