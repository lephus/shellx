#!/usr/bin/env node
// Share links end to end on loopback: the real cmux-relay, the Node API (relay/src) in process, the
// Swift `ShareHost` (test executable `share-e2e-host`, scripted panes that echo typed input) and the
// web viewer's session module (web/src/share/session.mjs) driven from Node with Origin https://shellx.pro.
//
// Usage: node scripts/shellx/share-e2e.mjs [--no-build]
//   CMUX_RELAY_BIN       cmux-relay binary (default cmux-tui/target/debug/cmux-relay, built when missing)
//   SHARE_E2E_HOST_BIN   share-e2e-host binary (default: `swift build --product share-e2e-host`)
// Needs `npm ci` in relay/ (tsx, ws). Exits 1 on the first failed check.
import { spawn, spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const RELAY_DIR = join(ROOT, 'relay');
const PKG_DIR = join(ROOT, 'Packages/Shared/ShellXBrand');
const ORIGIN = 'https://shellx.pro';
const ISSUER = 'shellx-relay';
const BUILD = !process.argv.includes('--no-build');

const requireRelay = createRequire(join(RELAY_DIR, 'package.json'));
const fileUrl = (p) => pathToFileURL(p).href;
const { register: registerTsx } = await import(fileUrl(requireRelay.resolve('tsx/esm/api')));
registerTsx();
const WS = (await import(fileUrl(requireRelay.resolve('ws')))).default;
const { startRelay } = await import(fileUrl(join(RELAY_DIR, 'src/relay.ts')));
const { Db } = await import(fileUrl(join(RELAY_DIR, 'src/db/db.ts')));
const { migrate } = await import(fileUrl(join(RELAY_DIR, 'src/db/migrate.ts')));
const { HubRegistry } = await import(fileUrl(join(RELAY_DIR, 'src/hub/registry.ts')));
const { randomShareId } = await import(fileUrl(join(RELAY_DIR, 'src/v2/shares.ts')));
const { createSession } = await import(fileUrl(join(ROOT, 'web/src/share/session.mjs')));
const wire = await import(fileUrl(join(ROOT, 'web/src/share/wire.mjs')));

const log = (...a) => console.log(...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const cleanups = [];
/** Every spawned process; killed synchronously on `exit`, whatever ended the run. */
const children = new Set();
const relayLog = [];
let tempDirPath = null;

/** Redacts relay and join tickets from debug output. */
const redact = (text) => text.replace(/(\\?"(?:join_)?ticket\\?":\\?")[^"\\]+/g, '$1<redacted>');
const debug = (...a) => { if (process.env.SHARE_E2E_DEBUG) console.log(...a.map((x) => (typeof x === 'string' ? redact(x) : x))); };

function track(child) {
  children.add(child);
  child.once('exit', () => children.delete(child));
  return child;
}

process.on('exit', () => {
  for (const child of children) {
    try { child.kill('SIGKILL'); } catch { /* already gone */ }
  }
  if (tempDirPath) rmSync(tempDirPath, { recursive: true, force: true });
});
let passed = 0;

function check(name, ok, detail = '') {
  if (!ok) throw new Error(`FAIL ${name}${detail ? `: ${detail}` : ''}`);
  passed += 1;
  log(`PASS ${name}${detail ? ` (${detail})` : ''}`);
}

async function waitUntil(what, fn, timeoutMs = 10_000) {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const v = fn();
    if (v) return v;
    if (Date.now() > deadline) {
      throw new Error(`FAIL timed out after ${timeoutMs} ms waiting for ${typeof what === 'function' ? what() : what}`);
    }
    await sleep(10);
  }
}

async function freePort() {
  return new Promise((res, rej) => {
    const s = createServer();
    s.once('error', rej);
    s.listen(0, '127.0.0.1', () => {
      const { port } = s.address();
      s.close(() => res(port));
    });
  });
}

function run(cmd, args, cwd) {
  log(`$ ${[cmd, ...args].join(' ')}`);
  const r = spawnSync(cmd, args, { cwd, stdio: ['ignore', 'inherit', 'inherit'] });
  if (r.status !== 0) throw new Error(`${cmd} exited with ${r.status}`);
}

// ---- binaries -----------------------------------------------------------------------------------

/** `cargo` from PATH, else rustup's default location. */
function cargoBinary() {
  if (spawnSync('cargo', ['--version'], { stdio: 'ignore' }).status === 0) return 'cargo';
  return join(process.env.HOME, '.cargo/bin/cargo');
}

function relayBinary() {
  const bin = process.env.CMUX_RELAY_BIN ?? join(ROOT, 'cmux-tui/target/debug/cmux-relay');
  if (!existsSync(bin)) {
    if (!BUILD || process.env.CMUX_RELAY_BIN) throw new Error(`cmux-relay not found at ${bin}`);
    run(cargoBinary(), ['build', '-p', 'cmux-relay'], join(ROOT, 'cmux-tui'));
  }
  return bin;
}

function hostBinary() {
  if (process.env.SHARE_E2E_HOST_BIN) return process.env.SHARE_E2E_HOST_BIN;
  if (BUILD) run('swift', ['build', '--product', 'share-e2e-host'], PKG_DIR);
  const r = spawnSync('swift', ['build', '--show-bin-path'], { cwd: PKG_DIR, encoding: 'utf8' });
  const bin = join(r.stdout.trim(), 'share-e2e-host');
  if (!existsSync(bin)) throw new Error(`share-e2e-host not found at ${bin}`);
  return bin;
}

// ---- cmux-relay and the API ---------------------------------------------------------------------

async function startCmuxRelay(bin, secretFile, dir) {
  const port = await freePort();
  const errLog = relayLog;
  const child = track(spawn(bin, ['serve'], {
    env: {
      CMUX_RELAY_HMAC_SECRET: readFileSync(secretFile, 'utf8').trim(),
      CMUX_RELAY_ISSUER: ISSUER,
      CMUX_RELAY_BIND: `127.0.0.1:${port}`,
      CMUX_RELAY_ALLOWED_ORIGINS: ORIGIN,
    },
    stdio: ['ignore', 'ignore', 'pipe'],
  }));
  child.stderr.on('data', (d) => errLog.push(d.toString()));
  let exited = false;
  child.once('exit', () => { exited = true; });
  cleanups.push(() => {
    if (!exited) child.kill('SIGKILL');
    writeFileSync(join(dir, 'cmux-relay.log'), errLog.join(''));
  });
  const deadline = Date.now() + 15_000;
  for (;;) {
    if (exited) throw new Error(`cmux-relay exited: ${errLog.join('')}`);
    try {
      if ((await fetch(`http://127.0.0.1:${port}/healthz`)).ok) return port;
    } catch { /* not listening yet */ }
    if (Date.now() > deadline) throw new Error('cmux-relay did not become healthy');
    await sleep(50);
  }
}

const clock = { offsetMs: 0 };
let nextShareId = null;

async function startApi(secretFile, relayPort, dir) {
  const db = Db.open(join(dir, 'api.db'));
  migrate(db);
  const hubs = new HubRegistry({ db });
  const allow = { limit: async () => true };
  const config = {
    host: '127.0.0.1', port: 0, dbPath: join(dir, 'api.db'),
    minAgent: '1.0.0', minMobile: '1.0.0', latestAgentVersion: '1.0.0',
    macUrl: 'https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg',
    winUrl: 'https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe',
    minMacos: '2.0.0', minWindows: '2.0.0', nativeManifestDir: join(dir, 'desktop'),
    rateLimitsEnabled: false, adminHost: 'admin.shellx.pro', adminPassword: null,
    relayHmacSecret: new TextEncoder().encode(readFileSync(secretFile, 'utf8').trim()),
    relayV2DisabledReason: null, relayIssuer: ISSUER,
    relayV2Url: `ws://127.0.0.1:${relayPort}/v1/relay`,
    shareAllowedOrigin: ORIGIN,
  };
  const limiters = Object.fromEntries(
    ['loginIp', 'loginEmail', 'registerIp', 'upgradeIp', 'notifyAgent', 'ticketMint', 'pairingCreate', 'shareCreate', 'shareTicket']
      .map((k) => [k, allow]));
  const relay = await startRelay(
    {
      config, db, hubs, limiters,
      // Test hooks the API already offers: a shiftable clock (expiry) and the next share id.
      now: () => Date.now() + clock.offsetMs,
      shareId: () => { const id = nextShareId ?? randomShareId(); nextShareId = null; return id; },
    },
    { host: '127.0.0.1', port: 0 },
  );
  cleanups.push(async () => {
    relay.server.closeAllConnections();
    await new Promise((r) => relay.server.close(() => r()));
    db.close();
  });
  return `http://127.0.0.1:${relay.port}`;
}

async function api(base, method, path, { token, body } = {}) {
  const headers = { 'X-Real-IP': '203.0.113.7' };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(base + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

const device = (kind) => ({
  kind, name: kind === 'desktop' ? 'Mac-Studio' : 'MacBook-Pro', platform: 'macos',
  public_key: randomBytes(32).toString('base64url'),
});

async function desktopAccount(base) {
  const email = `share-e2e-${randomBytes(6).toString('hex')}@example.com`;
  const password = 'correct horse battery';
  const reg = await api(base, 'POST', '/v1/auth/register', { body: { email, password, device: device('agent') } });
  if (reg.status !== 201) throw new Error(`register: ${reg.status} ${JSON.stringify(reg.body)}`);
  const login = await api(base, 'POST', '/v1/auth/login', { body: { email, password, device: device('desktop') } });
  if (login.status !== 200) throw new Error(`login: ${login.status} ${JSON.stringify(login.body)}`);
  return login.body.token;
}

/**
 * Creates a share like the app does, except that the id is chosen before the POST: `access` is salted
 * with the id, so it cannot be computed from the API's answer (see e2e.md, interop finding 1).
 */
async function createShare(base, token, body, shiftMs = 0) {
  const id = randomShareId();
  const secret = randomBytes(32).toString('base64url');
  const { access } = await wire.deriveKeyBytes(new Uint8Array(Buffer.from(secret, 'base64url')), id);
  nextShareId = id;
  clock.offsetMs = shiftMs;
  const res = await api(base, 'POST', '/v2/shares', { token, body: { ...body, access } }).finally(() => { clock.offsetMs = 0; });
  if (res.status !== 201 || res.body.id !== id) throw new Error(`create share: ${res.status} ${JSON.stringify(res.body)}`);
  return { ...res.body, secret, dashed: `${id.slice(0, 4)}-${id.slice(4)}` };
}

// ---- the Swift host -------------------------------------------------------------------------------

function startHost(bin, base, token, share, perm) {
  const args = ['--api', base, '--token', token, '--id', share.dashed, '--slot', share.slot,
    '--secret', share.secret, '--perm', perm];
  if (share.expires_at_unix != null) args.push('--expires-at', String(share.expires_at_unix));
  const child = track(spawn(bin, args, { stdio: ['pipe', 'pipe', 'pipe'] }));
  child.stdin.on('error', () => {}); // EPIPE once the host has exited
  const events = [];
  const stderr = [];
  createInterface({ input: child.stdout }).on('line', (line) => {
    debug('DBG host', line.slice(0, 300));
    try { events.push({ at: Date.now(), ...JSON.parse(line) }); } catch { stderr.push(line); }
  });
  child.stderr.on('data', (d) => stderr.push(d.toString()));
  let exited = false;
  child.once('exit', () => { exited = true; });
  cleanups.push(() => { if (!exited) child.kill('SIGKILL'); });
  const host = {
    events,
    send: (line) => child.stdin.write(`${line}\n`),
    wait: (what, pred, ms = 10_000) => waitUntil(() => `host ${what} (${stderr.join('').trim()})`, () => events.find(pred), ms),
    async stats() {
      const n = events.length;
      host.send('stats');
      return waitUntil('host stats', () => events.slice(n).find((e) => e.event === 'stats'));
    },
    get exited() { return exited; },
  };
  return host;
}

// ---- the Node viewer ----------------------------------------------------------------------------

/** The page's fetch, with the Origin a browser on shellx.pro would send. */
const corsSeen = [];
const originFetch = async (url, init = {}) => {
  const res = await fetch(url, { ...init, headers: { ...init.headers, Origin: ORIGIN } });
  corsSeen.push(res.headers.get('access-control-allow-origin'));
  return res;
};

function memoryStorage() {
  const m = new Map();
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)) };
}

function startViewer(base, share, storage = memoryStorage()) {
  const sockets = [];
  // `ws` with Origin (the global WebSocket cannot set it); records every socket the session opens.
  class OriginWebSocket extends WS {
    constructor(url) {
      super(url, { headers: { Origin: ORIGIN } });
      const tap = { ws: this, sentText: [], sentBinary: [], gotBinary: [] };
      sockets.push(tap);
      const send = this.send.bind(this);
      this.send = (data, ...rest) => {
        if (typeof data === 'string') tap.sentText.push(data); else tap.sentBinary.push(new Uint8Array(data));
        return send(data, ...rest);
      };
      this.on('message', (data, isBinary) => {
        if (isBinary) tap.gotBinary.push(new Uint8Array(data));
        debug('DBG ws <-', isBinary ? `binary ${data.length ?? data.byteLength}` : data.toString());
      });
      if (process.env.SHARE_E2E_DEBUG) {
        this.on('unexpected-response', (_req, res) => console.log('DBG ws unexpected-response', res.statusCode));
        this.on('close', (c, r) => console.log('DBG ws close', c, r.toString()));
      }
    }
  }
  const events = [];
  const session = createSession({
    id: share.dashed, secret: share.secret, fetch: originFetch, WebSocket: OriginWebSocket, storage,
    apiBase: base, label: 'Node · share-e2e',
  });
  for (const type of ['state', 'welcome', 'panes', 'replay', 'out', 'size']) {
    session.on(type, (value) => events.push({ type, at: Date.now(), ...value }));
  }
  cleanups.push(() => session.close());
  const text = (e) => Buffer.from(e.data).toString('utf8');
  const viewer = {
    session, events, sockets,
    state: (name) => events.find((e) => e.type === 'state' && e.state === name),
    waitState: (name, ms = 10_000) => waitUntil(() => `viewer state ${name} (now ${session.state} ${JSON.stringify(session.detail)})`,
      () => viewer.state(name), ms),
    output: () => events.filter((e) => e.type === 'out').map(text).join(''),
    replayText: () => events.filter((e) => e.type === 'replay').map(text).join(''),
  };
  session.start().catch((err) => events.push({ type: 'start_error', at: Date.now(), message: String(err) }));
  return viewer;
}

/**
 * Seals an `in` frame on a view share's circuit by hand (the session never sends one when perm is
 * view): circuit id from the `join`, viewer nonce from the `hello`, host nonce from the `welcome`.
 */
async function forgeInput(share, viewer, text, seq) {
  const keys = await wire.deriveKeys(new Uint8Array(Buffer.from(share.secret, 'base64url')), share.id);
  const tap = viewer.sockets.find((s) => s.sentText.some((t) => JSON.parse(t).type === 'join'));
  const circuit = JSON.parse(tap.sentText.find((t) => JSON.parse(t).type === 'join')).circuit;
  const hello = JSON.parse(new TextDecoder().decode(await wire.openFrame(keys.viewerToHost, wire.aadFor(circuit), tap.sentBinary[0])));
  const welcome = JSON.parse(new TextDecoder().decode(
    await wire.openFrame(keys.hostToViewer, wire.aadFor(circuit, hello.nonce), tap.gotBinary[0])));
  const plain = new TextEncoder().encode(
    wire.encodeMessage({ t: 'in', pane: 'p1', data: Buffer.from(text).toString('base64') }, seq));
  tap.ws.send(await wire.sealFrame(keys.viewerToHost, wire.aadFor(circuit, hello.nonce, welcome.nonce), plain));
  return { hello, welcome };
}

// ---- scenarios --------------------------------------------------------------------------------------

async function scenarioTypeShare(ctx) {
  log('\n== type share: welcome, replay, echo, revoke (API DELETE, then the host\'s stop(.revoked), as the app\'s controller does)');
  const share = await createShare(ctx.base, ctx.token, { permission: 'type', lifetime: '1h' });
  const host = startHost(ctx.hostBin, ctx.base, ctx.token, share, 'type');
  await host.wait('registered', (e) => e.event === 'registered');
  const v = startViewer(ctx.base, share);
  await v.waitState('live').catch(async (e) => {
    if (process.env.SHARE_E2E_DEBUG) debug('DBG stats', JSON.stringify(await host.stats()));
    throw e;
  });
  const welcome = v.events.find((e) => e.type === 'welcome');
  check('type: welcome perm=type with the scripted panes', welcome?.perm === 'type'
    && welcome.panes.map((p) => `${p.id}:${p.kind}`).join(',') === 'p1:terminal,b1:browser' && welcome.active === 'p1',
  JSON.stringify(welcome?.panes));
  check('type: welcome expires_at_unix matches the API', welcome.expiresAt === share.expires_at_unix);
  await waitUntil('replay', () => v.events.find((e) => e.type === 'replay'));
  const replay = v.events.find((e) => e.type === 'replay');
  check('type: replay of p1 follows welcome', v.events.indexOf(replay) > v.events.indexOf(welcome)
    && replay.pane === 'p1' && replay.cols === 80 && replay.rows === 24 && v.replayText().includes('share-e2e scripted pane'));
  const listed = await host.wait('viewer label', (e) => e.event === 'viewers' && e.labels.length > 0);
  check('type: host lists exactly the viewer label', listed.labels.length === 1 && listed.labels[0] === 'Node · share-e2e',
    JSON.stringify(listed.labels));

  const t0 = Date.now();
  v.session.input(new TextEncoder().encode('echo hi\r'));
  await waitUntil('echo', () => v.output().includes('echo hi\r'));
  const typed = host.events.filter((e) => e.event === 'input');
  check('type: typed "echo hi\\r" reaches the host pane once and comes back as output',
    typed.length === 1 && typed[0].pane === 'p1' && typed[0].bytes === 8, `${Date.now() - t0} ms`);

  // Revoke is two steps, like ShellXShareController: the API DELETE, then ShareHost.stop(.revoked).
  // The API does not notify the host.
  const r0 = Date.now();
  const del = await api(ctx.base, 'DELETE', `/v2/shares/${share.dashed}`, { token: ctx.token });
  host.send('stop revoked');
  await v.waitState('revoked', 1000);
  check('type: revoke -> viewer state revoked (bye revoked) within 1 s',
    del.status === 204 && v.session.detail?.bye === 'revoked', `${v.state('revoked').at - r0} ms`);
  const again = startViewer(ctx.base, share);
  await again.waitState('revoked');
  check('type: a new viewer of the revoked link gets revoked from the API', again.session.detail?.api === 'share_revoked');
}

async function scenarioViewShare(ctx) {
  log('\n== view share: input dropped');
  const share = await createShare(ctx.base, ctx.token, { permission: 'view', lifetime: '1h' });
  const host = startHost(ctx.hostBin, ctx.base, ctx.token, share, 'view');
  await host.wait('registered', (e) => e.event === 'registered');
  const v = startViewer(ctx.base, share);
  await v.waitState('live');
  await waitUntil('replay', () => v.events.find((e) => e.type === 'replay'));
  check('view: welcome perm=view, canType false', v.session.perm === 'view' && v.session.canType === false);
  const sentBefore = v.sockets.reduce((n, s) => n + s.sentBinary.length, 0);
  v.session.input(new TextEncoder().encode('echo nope\r'));
  await sleep(100);
  check('view: the session sends no in frame', v.sockets.reduce((n, s) => n + s.sentBinary.length, 0) === sentBefore);
  await forgeInput(share, v, 'echo forged\r', 1000);
  await sleep(1000);
  const stats = await host.stats();
  check('view: a forged in frame is dropped by the host', !v.output().includes('forged')
    && !host.events.some((e) => e.event === 'input') && stats.dropped_input >= 1, `dropped_input=${stats.dropped_input}`);
  check('view: viewer still live after the forged frame', v.session.state === 'live');
  host.send('stop host_quit');
  await v.waitState('host_offline', 2000);
  check('view: host quit -> viewer host_offline (bye host_quit)', v.session.detail?.bye === 'host_quit');
}

async function scenarioExpiry(ctx) {
  log('\n== expiry: 15m share created on a shifted API clock so it expires in ~5 s');
  const share = await createShare(ctx.base, ctx.token, { permission: 'view', lifetime: '15m' }, -(15 * 60_000 - 5_000));
  const expiresMs = share.expires_at_unix * 1000;
  check('expiry: share expires in under 6 s', expiresMs - Date.now() < 6_000 && expiresMs > Date.now() + 2_000,
    `${expiresMs - Date.now()} ms left`);
  const host = startHost(ctx.hostBin, ctx.base, ctx.token, share, 'view');
  await host.wait('registered', (e) => e.event === 'registered');
  const v = startViewer(ctx.base, share);
  await v.waitState('live');
  await v.waitState('expired', expiresMs - Date.now() + 2_000);
  const late = v.state('expired').at - expiresMs;
  check('expiry: viewer state expired at expires_at', late >= -50 && late < 1000 && v.session.detail?.bye === 'expired',
    `${late} ms after expires_at`);
  // The API keeps milliseconds but announces floor(seconds): it may still mint for < 1 s after the host stopped.
  await sleep(Math.max(0, expiresMs + 1000 - Date.now()));
  const again = startViewer(ctx.base, share);
  await again.waitState('expired');
  check('expiry: a new viewer gets expired from the API', again.session.detail?.api === 'share_expired');
  const stopped = await host.wait('stopped', (e) => e.event === 'stopped');
  check('expiry: host stopped itself at expires_at', stopped.at - expiresMs >= -50 && stopped.at - expiresMs < 1500,
    `${stopped.at - expiresMs} ms after expires_at`);
}

async function scenarioOneTime(ctx) {
  log('\n== one-time (QR) share: first viewer binds, a second is refused, reconnect allowed');
  const share = await createShare(ctx.base, ctx.token, { permission: 'type', lifetime: 'until_quit', one_time: true });
  const host = startHost(ctx.hostBin, ctx.base, ctx.token, share, 'type');
  await host.wait('registered', (e) => e.event === 'registered');
  const phone = memoryStorage();
  const a = startViewer(ctx.base, share, phone);
  await a.waitState('live');
  check('one-time: first viewer live with perm=type', a.session.perm === 'type');
  const b = startViewer(ctx.base, share);
  await b.waitState('used');
  check('one-time: a second browser gets used', b.session.detail?.api === 'share_used');
  a.session.close();
  const again = startViewer(ctx.base, share, phone);
  await again.waitState('live');
  again.session.input(new TextEncoder().encode('echo hi\r'));
  await waitUntil('echo after reconnect', () => again.output().includes('echo hi\r'));
  check('one-time: the same phone reconnects and types', again.session.perm === 'type'
    && host.events.filter((e) => e.event === 'input' && e.bytes === 8).length === 1);
  host.send('stop host_quit');
  await again.waitState('host_offline', 2000);
}

async function scenarioOrigins(ctx) {
  log('\n== origins');
  const status = (origin) => new Promise((res) => {
    const ws = new WS(`ws://127.0.0.1:${ctx.relayPort}/v1/relay`, origin ? { headers: { Origin: origin } } : {});
    ws.once('open', () => { ws.terminate(); res(101); });
    ws.once('unexpected-response', (_req, r) => { res(r.statusCode); ws.terminate(); });
    ws.once('error', () => {});
  });
  check('origins: cmux-relay admits https://shellx.pro', (await status(ORIGIN)) === 101);
  check('origins: cmux-relay refuses another Origin', (await status('https://evil.example')) === 403);
  check('origins: cmux-relay admits a host with no Origin', (await status(null)) === 101);
}

// ---- main -------------------------------------------------------------------------------------------

async function main() {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-share-e2e-'));
  tempDirPath = dir;
  cleanups.push(() => rmSync(dir, { recursive: true, force: true }));
  const secretFile = join(dir, 'hmac-secret');
  writeFileSync(secretFile, randomBytes(32).toString('hex'), { mode: 0o600 });
  chmodSync(secretFile, 0o600);

  const relayBin = relayBinary();
  const hostBin = hostBinary();
  const relayPort = await startCmuxRelay(relayBin, secretFile, dir);
  const base = await startApi(secretFile, relayPort, dir);
  log(`cmux-relay 127.0.0.1:${relayPort} (allowed origin ${ORIGIN}), API ${base}`);
  const token = await desktopAccount(base);
  const ctx = { base, token, hostBin, relayPort };

  await scenarioOrigins(ctx);
  await scenarioTypeShare(ctx);
  await scenarioViewShare(ctx);
  await scenarioExpiry(ctx);
  await scenarioOneTime(ctx);
  check('origins: every viewer ticket answered Access-Control-Allow-Origin https://shellx.pro',
    corsSeen.length > 0 && corsSeen.every((o) => o === ORIGIN), `${corsSeen.length} tickets`);
  log(`\nshare-e2e: ${passed} checks passed`);
}

let cleaning = null;
function runCleanups() {
  cleaning ??= (async () => {
    for (const fn of cleanups.splice(0).reverse()) {
      try { await fn(); } catch { /* best effort */ }
    }
  })();
  return cleaning;
}

function printRelayLog() {
  if (relayLog.length) console.error(`--- cmux-relay log ---\n${redact(relayLog.join('')).trimEnd()}\n---`);
}

/** Abnormal end (signal, uncaught error): clean up, then exit non-zero; `exit` kills what is left. */
async function abort(code, why) {
  console.error(`share-e2e: aborted (${why})`);
  printRelayLog();
  await Promise.race([runCleanups(), sleep(3000)]);
  process.exit(code);
}
process.once('SIGINT', () => abort(130, 'SIGINT'));
process.once('SIGTERM', () => abort(143, 'SIGTERM'));
process.on('uncaughtException', (err) => abort(1, `uncaught: ${err?.message ?? err}`));
process.on('unhandledRejection', (err) => abort(1, `unhandled rejection: ${err?.message ?? err}`));

let code = 0;
try {
  await main();
} catch (err) {
  console.error(err instanceof Error ? err.message : err);
  printRelayLog();
  code = 1;
} finally {
  await runCleanups();
}
process.exit(code);
