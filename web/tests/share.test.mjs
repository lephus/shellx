// Share viewer logic (/s/): wire format v1 + amendment A1, the session state machine and the
// keyboard/composition → bytes mapping. Pure modules, so these run in node with WebCrypto and fake
// fetch / WebSocket / timers. Run: node --test tests/share.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  aadFor, b64Decode, b64Encode, b64urlDecode, deriveKeyBytes, deriveKeys, encodeMessage, MAX_FRAME_BYTES,
  normalizeShareId, openFrame, sealFrame,
} from '../src/share/wire.mjs';
import { createSession } from '../src/share/session.mjs';
import { createInput } from '../src/share/input.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const vectors = JSON.parse(readFileSync(join(root, 'tests/fixtures/share-vectors.json'), 'utf8'));

const hex = (bytes) => Buffer.from(bytes).toString('hex');
const fromHex = (s) => new Uint8Array(Buffer.from(s, 'hex'));
const utf8 = (s) => new TextEncoder().encode(s);
const text = (b) => new TextDecoder().decode(b);

// ---------------------------------------------------------------------------------------------
// Wire format

test('keys and frames match share-vectors.json', async () => {
  const secret = b64urlDecode(vectors.secret);
  assert.deepEqual([...secret], [...Array(32).keys()], 'vector secret is bytes 0..31');
  const raw = await deriveKeyBytes(secret, vectors.share_id);
  assert.equal(hex(raw.hostToViewer), vectors.keys.host_to_viewer_hex);
  assert.equal(hex(raw.viewerToHost), vectors.keys.viewer_to_host_hex);
  assert.equal(raw.access, vectors.keys.access);
  // The display dash is stripped before the HKDF salt.
  const dashed = await deriveKeyBytes(secret, `${vectors.share_id.slice(0, 4)}-${vectors.share_id.slice(4)}`);
  assert.equal(dashed.access, vectors.keys.access);

  const keys = await deriveKeys(secret, vectors.share_id);
  const vn = vectors.viewer_nonce_b64;
  const hn = vectors.host_nonce_b64;
  for (const frame of vectors.frames) {
    const message = JSON.parse(frame.plaintext);
    // Amendment A1: AAD is staged per connection (hello, welcome, everything after).
    const expectedAad = frame.aad ?? `shellx-share/1|${frame.circuit}`;
    if (vn !== undefined) {
      const stage = message.t === 'hello' ? [] : message.t === 'welcome' ? [vn] : [vn, hn];
      assert.equal(aadFor(frame.circuit, ...stage), expectedAad, `AAD stage of ${message.t}`);
    }
    // The codec writes the exact plaintext bytes (key order t, seq, then the v1 fields).
    const { seq, ...fields } = message;
    assert.equal(encodeMessage(fields, seq), frame.plaintext, `codec of ${message.t}`);

    const key = frame.key === 'host_to_viewer' ? keys.hostToViewer : keys.viewerToHost;
    const sealed = await sealFrame(key, expectedAad, utf8(frame.plaintext), fromHex(frame.nonce_hex));
    assert.equal(hex(sealed), frame.frame_hex, `seal of ${message.t}`);
    const opened = await openFrame(key, expectedAad, fromHex(frame.frame_hex));
    assert.equal(text(opened), frame.plaintext);
    // Wrong AAD (another circuit or stage) and the other direction's key both fail to open.
    assert.equal(await openFrame(key, `${expectedAad}x`, fromHex(frame.frame_hex)), null);
    const other = frame.key === 'host_to_viewer' ? keys.viewerToHost : keys.hostToViewer;
    assert.equal(await openFrame(other, expectedAad, fromHex(frame.frame_hex)), null);
  }
});

test('ids: dash stripped, 8 chars of the share alphabet', () => {
  assert.equal(normalizeShareId('k7f2-9qd1'), 'k7f29qd1');
  assert.equal(normalizeShareId('k7f29qd1'), 'k7f29qd1');
  for (const bad of ['', 'k7f2', 'K7F2-9QD1', 'k7f2-9qdi', 'k7f2-9qd1-', 'k7f2/9qd1']) {
    assert.equal(normalizeShareId(bad), null, bad);
  }
});

test('frames over 64 KiB are dropped before decryption', async () => {
  const keys = await deriveKeys(new Uint8Array(32), 'k7f29qd1');
  const aad = aadFor('c');
  const big = await sealFrame(keys.hostToViewer, aad, new Uint8Array(MAX_FRAME_BYTES));
  assert.ok(big.length > MAX_FRAME_BYTES);
  assert.equal(await openFrame(keys.hostToViewer, aad, big), null);
  assert.equal(await openFrame(keys.hostToViewer, aad, new Uint8Array(27)), null, 'shorter than nonce + tag');
  const ok = await sealFrame(keys.hostToViewer, aad, utf8('{}'));
  assert.equal(text(await openFrame(keys.hostToViewer, aad, ok)), '{}');
});

// ---------------------------------------------------------------------------------------------
// Fakes: fetch, WebSocket, timers and a scripted host that speaks the wire format.

const SHARE_ID = 'k7f2-9qd1';
const SECRET = vectors.secret;
const RELAY = 'wss://relay.example.test/v2/relay';

function fakeClock() {
  let now = 1_000_000;
  let timers = [];
  let nextId = 1;
  return {
    now: () => now,
    setTimeout: (fn, ms) => {
      const id = nextId++;
      timers.push({ id, at: now + ms, fn });
      return id;
    },
    clearTimeout: (id) => {
      timers = timers.filter((t) => t.id !== id);
    },
    advance(ms) {
      now += ms;
      const due = timers.filter((t) => t.at <= now);
      timers = timers.filter((t) => t.at > now);
      for (const t of due) t.fn();
    },
    pending: () => timers.length,
  };
}

function memoryStorage() {
  const map = new Map();
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
    removeItem: (k) => map.delete(k),
  };
}

function fakeFetch(respond) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url, init, body: JSON.parse(init.body) });
    const { status, body } = respond(calls.length);
    return {
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
    };
  };
  fn.calls = calls;
  return fn;
}

const okTicket = () => ({
  status: 200,
  body: { ticket: 'tkt.viewer', expires_at_unix: 2_000_000, relay_url: RELAY, slot: 'slot-share-1' },
});

function fakeWebSocketClass() {
  const sockets = [];
  class FakeWebSocket {
    static OPEN = 1;
    constructor(url) {
      this.url = url;
      this.readyState = 0;
      this.sent = [];
      this.closed = false;
      this.binaryType = 'blob';
      sockets.push(this);
    }
    send(data) {
      if (this.readyState !== 1) throw new Error('send before open');
      this.sent.push(data);
    }
    close() {
      if (this.closed) return;
      this.closed = true;
      this.readyState = 3;
      this.onclose?.({ code: 1000 });
    }
    // test side
    serverOpen() {
      this.readyState = 1;
      this.onopen?.({});
    }
    serverText(obj) {
      this.onmessage?.({ data: JSON.stringify(obj) });
    }
    serverBinary(bytes) {
      const copy = bytes.slice();
      this.onmessage?.({ data: copy.buffer });
    }
    serverClose(code = 1006) {
      if (this.closed) return;
      this.closed = true;
      this.readyState = 3;
      this.onclose?.({ code });
    }
    textSent() {
      return this.sent.filter((d) => typeof d === 'string').map((d) => JSON.parse(d));
    }
    binarySent() {
      return this.sent.filter((d) => typeof d !== 'string').map((d) => new Uint8Array(d.buffer ?? d));
    }
  }
  FakeWebSocket.sockets = sockets;
  return FakeWebSocket;
}

async function settle(cond, label = 'condition') {
  for (let i = 0; i < 500; i++) {
    if (cond()) return;
    await new Promise((r) => setImmediate(r));
  }
  assert.fail(`timed out waiting for ${label}`);
}

function states(session) {
  const seen = [session.state];
  session.on('state', (s) => seen.push(s.state));
  return seen;
}

function setup({ respond = okTicket, storage = memoryStorage() } = {}) {
  const clock = fakeClock();
  const fetch = fakeFetch(respond);
  const WebSocket = fakeWebSocketClass();
  const session = createSession({
    id: SHARE_ID, secret: SECRET, fetch, WebSocket, storage,
    now: clock.now, setTimeout: clock.setTimeout, clearTimeout: clock.clearTimeout,
    label: 'Safari · iPhone',
  });
  return { clock, fetch, WebSocket, session, storage };
}

// Drives the relay handshake up to `ready` on the circuit socket.
async function relayToReady(ctx) {
  const { WebSocket } = ctx;
  await settle(() => WebSocket.sockets.length >= 1, 'control socket');
  const control = WebSocket.sockets[0];
  assert.equal(control.url, RELAY);
  control.serverOpen();
  await settle(() => control.textSent().length === 1, 'connect');
  const connect = control.textSent()[0];
  control.serverText({
    type: 'allocated', circuit: 'circuit-1', lane: connect.lane, generation: connect.generation, join_ticket: 'jt',
  });
  await settle(() => WebSocket.sockets.length >= 2, 'circuit socket');
  const circuit = WebSocket.sockets[1];
  circuit.serverOpen();
  await settle(() => circuit.textSent().length === 1, 'join');
  const join = circuit.textSent()[0];
  circuit.serverText({ type: 'ready', circuit: 'circuit-1', lane: join.lane, generation: join.generation });
  return { control, circuit, connect, join };
}

// A host that answers hello with welcome and speaks stage-3 frames afterwards.
async function hostFor(circuit, circuitId = 'circuit-1') {
  const keys = await deriveKeys(b64urlDecode(SECRET), SHARE_ID);
  await settle(() => circuit.binarySent().length === 1, 'hello frame');
  const helloFrame = circuit.binarySent()[0];
  const helloPlain = await openFrame(keys.viewerToHost, aadFor(circuitId), helloFrame);
  assert.ok(helloPlain, 'hello opens with the stage-1 AAD');
  const hello = JSON.parse(text(helloPlain));
  const hostNonce = b64Encode(new Uint8Array(16).fill(7));
  let seq = 0;
  let lastIn = 0;
  const host = {
    hello,
    hostNonce,
    keys,
    async send(fields, stage = 'late') {
      seq += 1;
      const aad = stage === 'welcome' ? aadFor(circuitId, hello.nonce) : aadFor(circuitId, hello.nonce, hostNonce);
      circuit.serverBinary(await sealFrame(keys.hostToViewer, aad, utf8(encodeMessage(fields, seq))));
    },
    async sendRaw(fields, seqValue, aad) {
      circuit.serverBinary(await sealFrame(keys.hostToViewer, aad, utf8(encodeMessage(fields, seqValue))));
    },
    welcome(perm = 'type', extra = {}) {
      return host.send({
        t: 'welcome', nonce: hostNonce, perm, expires_at_unix: 2_000_000,
        panes: [
          { id: 'p1', title: 'zsh', kind: 'terminal', cols: 80, rows: 24 },
          { id: 'p2', title: 'Docs', kind: 'browser', cols: 0, rows: 0 },
        ],
        active: 'p1',
        ...extra,
      }, 'welcome');
    },
    // Viewer → host frames after hello, opened with the stage-3 AAD.
    async received() {
      const out = [];
      for (const frame of circuit.binarySent().slice(1)) {
        const plain = await openFrame(keys.viewerToHost, aadFor(circuitId, hello.nonce, hostNonce), frame);
        assert.ok(plain, 'viewer frame opens with the stage-3 AAD');
        const msg = JSON.parse(text(plain));
        assert.ok(msg.seq > lastIn, 'viewer seq increases');
        lastIn = msg.seq;
        out.push(msg);
      }
      lastIn = 0;
      return out;
    },
  };
  return host;
}

async function goLive(ctx, perm = 'type') {
  ctx.session.start();
  const relay = await relayToReady(ctx);
  const host = await hostFor(relay.circuit);
  await host.welcome(perm);
  await settle(() => ctx.session.state === 'live', 'live');
  return { ...relay, host };
}

// ---------------------------------------------------------------------------------------------
// Session

test('ticket request carries no secret', async () => {
  const ctx = setup();
  ctx.session.start();
  await settle(() => ctx.fetch.calls.length === 1, 'ticket fetch');
  const call = ctx.fetch.calls[0];
  assert.equal(call.url, 'https://relay.shellx.pro/v2/shares/k7f29qd1/ticket');
  assert.ok(!call.url.includes('#') && !call.url.includes('?'));
  assert.equal(call.init.method, 'POST');
  assert.deepEqual(Object.keys(call.body).sort(), ['access', 'viewer']);
  assert.equal(call.body.access, vectors.keys.access);
  assert.match(call.body.viewer, /^[A-Za-z0-9_-]{16,64}$/);
  assert.ok(!call.init.body.includes(SECRET), 'secret never leaves the page');
  assert.equal(call.init.credentials, 'omit');
  assert.equal(call.init.referrerPolicy, 'no-referrer');
});

test('viewer id persists in storage', async () => {
  const storage = memoryStorage();
  const a = setup({ storage });
  a.session.start();
  await settle(() => a.fetch.calls.length === 1);
  const b = setup({ storage });
  b.session.start();
  await settle(() => b.fetch.calls.length === 1);
  assert.equal(a.fetch.calls[0].body.viewer, b.fetch.calls[0].body.viewer);
  const c = setup({ storage: memoryStorage() });
  c.session.start();
  await settle(() => c.fetch.calls.length === 1);
  assert.notEqual(c.fetch.calls[0].body.viewer, a.fetch.calls[0].body.viewer);
});

test('a broken storage still yields a viewer id', async () => {
  const broken = { getItem() { throw new Error('denied'); }, setItem() { throw new Error('denied'); } };
  const ctx = setup({ storage: broken });
  ctx.session.start();
  await settle(() => ctx.fetch.calls.length === 1);
  assert.match(ctx.fetch.calls[0].body.viewer, /^[A-Za-z0-9_-]{16,64}$/);
});

for (const [status, code, state] of [
  [410, 'share_expired', 'expired'],
  [410, 'share_revoked', 'revoked'],
  [410, 'share_used', 'used'],
  [503, 'host_offline', 'host_offline'],
  [404, 'share_not_found', 'not_found'],
  [404, undefined, 'not_found'],
  [429, 'rate_limited', 'error'],
  [500, 'internal', 'error'],
]) {
  test(`refused ticket maps to a state: ${status} ${code ?? '(no body)'} → ${state}`, async () => {
    const ctx = setup({
      respond: () => ({ status, body: code ? { error: { code, message: 'no' } } : null }),
    });
    const seen = states(ctx.session);
    await ctx.session.start();
    assert.equal(ctx.session.state, state);
    assert.deepEqual(seen, ['loading', state]);
    assert.equal(ctx.WebSocket.sockets.length, 0, 'no relay socket after a refusal');
  });
}

test('network failure on the ticket request ends in error, not a spinner', async () => {
  const clock = fakeClock();
  const session = createSession({
    id: SHARE_ID, secret: SECRET, storage: memoryStorage(), WebSocket: fakeWebSocketClass(),
    fetch: async () => { throw new TypeError('Failed to fetch'); },
    now: clock.now, setTimeout: clock.setTimeout, clearTimeout: clock.clearTimeout,
  });
  await session.start();
  assert.equal(session.state, 'error');
});

test('a bad link (no secret, wrong id) is not_found without any request', async () => {
  // The vector ends in '8' (111100); '9' (111101) decodes to the same 32 bytes but sets a padding bit.
  assert.equal(SECRET.at(-1), '8');
  const nonCanonical = `${SECRET.slice(0, 42)}9`;
  assert.deepEqual(b64urlDecode(nonCanonical), b64urlDecode(SECRET), 'lenient base64 accepts it');
  for (const [id, secret] of [[SHARE_ID, ''], [SHARE_ID, 'abc'], ['nope', SECRET], [SHARE_ID, `${SECRET}=`],
    [SHARE_ID, nonCanonical], [SHARE_ID, `${SECRET}A`]]) {
    const ctx = setup();
    const session = createSession({
      id, secret, fetch: ctx.fetch, WebSocket: ctx.WebSocket, storage: memoryStorage(),
      now: ctx.clock.now, setTimeout: ctx.clock.setTimeout, clearTimeout: ctx.clock.clearTimeout,
    });
    await session.start();
    assert.equal(session.state, 'not_found');
    assert.equal(ctx.fetch.calls.length, 0);
  }
});

test('relay handshake: connect, allocated, join, ready, then an encrypted hello', async () => {
  const ctx = setup();
  const seen = states(ctx.session);
  ctx.session.start();
  const { connect, join, circuit, control } = await relayToReady(ctx);
  assert.deepEqual(Object.keys(connect).sort(), ['generation', 'lane', 'protocol', 'slot', 'ticket', 'type']);
  assert.equal(connect.type, 'connect');
  assert.equal(connect.protocol, 5);
  assert.equal(connect.slot, 'slot-share-1');
  assert.equal(connect.ticket, 'tkt.viewer');
  assert.equal(connect.generation, 1);
  assert.match(connect.lane, /^[A-Za-z0-9_-]{16,}$/);
  assert.equal(circuit.url, RELAY, 'circuit joins on the same relay URL');
  assert.deepEqual(join, {
    type: 'join', protocol: 5, slot: 'slot-share-1', circuit: 'circuit-1', lane: connect.lane,
    generation: 1, ticket: 'jt', role: 'client',
  });
  assert.equal(circuit.binaryType, 'arraybuffer');
  const host = await hostFor(circuit);
  assert.equal(host.hello.t, 'hello');
  assert.equal(host.hello.seq, 1);
  assert.equal(host.hello.label, 'Safari · iPhone');
  assert.equal(b64Decode(host.hello.nonce).length, 16, 'hello carries a fresh 16-byte nonce');
  assert.deepEqual(Object.keys(host.hello), ['t', 'seq', 'nonce', 'label']);
  await host.welcome('view');
  await settle(() => ctx.session.state === 'live');
  assert.deepEqual(seen, ['loading', 'connecting', 'live']);
  assert.equal(ctx.session.perm, 'view');
  assert.equal(ctx.session.active, 'p1');
  assert.ok(control.closed, 'control socket is released once the circuit is live');
  assert.ok(!circuit.closed);
});

test('each connection draws a fresh hello nonce', async () => {
  const nonces = [];
  for (let i = 0; i < 2; i++) {
    const ctx = setup();
    ctx.session.start();
    const { circuit } = await relayToReady(ctx);
    nonces.push((await hostFor(circuit)).hello.nonce);
  }
  assert.notEqual(nonces[0], nonces[1]);
});

test('relay ping is answered with pong on the control socket', async () => {
  const ctx = setup();
  ctx.session.start();
  await settle(() => ctx.WebSocket.sockets.length === 1);
  const control = ctx.WebSocket.sockets[0];
  control.serverOpen();
  await settle(() => control.textSent().length === 1);
  control.serverText({ type: 'ping', nonce: 42 });
  assert.deepEqual(control.textSent()[1], { type: 'pong', nonce: 42 });
});

test('relay timeout ends in host_offline after 15 s', async () => {
  const ctx = setup();
  ctx.session.start();
  await settle(() => ctx.WebSocket.sockets.length === 1);
  const control = ctx.WebSocket.sockets[0];
  control.serverOpen();
  ctx.clock.advance(14_999);
  assert.equal(ctx.session.state, 'connecting');
  ctx.clock.advance(1);
  assert.equal(ctx.session.state, 'host_offline');
  assert.ok(control.closed, 'control socket closed');
});

test('relay timeout also covers a ready circuit whose host never sends welcome', async () => {
  const ctx = setup();
  ctx.session.start();
  const { circuit, control } = await relayToReady(ctx);
  await hostFor(circuit);
  ctx.clock.advance(15_000);
  assert.equal(ctx.session.state, 'host_offline');
  assert.ok(circuit.closed && control.closed, 'sockets closed');
  assert.equal(ctx.clock.pending(), 0);
});

test('relay slot-offline error maps to host_offline; other relay errors to error', async () => {
  for (const [code, state] of [['slot-offline', 'host_offline'], ['invalid-ticket', 'error']]) {
    const ctx = setup();
    ctx.session.start();
    await settle(() => ctx.WebSocket.sockets.length === 1);
    const control = ctx.WebSocket.sockets[0];
    control.serverOpen();
    await settle(() => control.textSent().length === 1);
    control.serverText({ type: 'error', code, message: 'm', retryable: false });
    assert.equal(ctx.session.state, state, code);
    assert.ok(control.closed);
  }
});

test('before welcome the viewer accepts only welcome or bye', async () => {
  const ctx = setup();
  const events = [];
  ctx.session.on('out', (e) => events.push(e));
  ctx.session.start();
  const { circuit } = await relayToReady(ctx);
  const host = await hostFor(circuit);
  // `out` sealed with the welcome-stage AAD before any welcome: dropped.
  await host.send({ t: 'out', pane: 'p1', data: b64Encode(utf8('early')) }, 'welcome');
  await settle(() => ctx.session.dropped === 1, 'drop counted');
  assert.equal(ctx.session.state, 'connecting');
  // A welcome sealed with the stage-1 AAD (no viewer nonce) does not open: dropped.
  await host.sendRaw({ t: 'welcome', nonce: host.hostNonce, perm: 'type', expires_at_unix: null, panes: [], active: 'p1' },
    5, aadFor('circuit-1'));
  await settle(() => ctx.session.dropped === 2, 'drop counted');
  assert.equal(ctx.session.state, 'connecting');
  await host.welcome('type');
  await settle(() => ctx.session.state === 'live');
  assert.equal(events.length, 0);
});

test('bye before welcome (welcome-stage AAD) ends the session', async () => {
  const ctx = setup();
  ctx.session.start();
  const { circuit } = await relayToReady(ctx);
  const host = await hostFor(circuit);
  await host.send({ t: 'bye', reason: 'revoked' }, 'welcome');
  await settle(() => ctx.session.state === 'revoked');
  assert.ok(circuit.closed);
});

for (const [reason, state] of [['expired', 'expired'], ['revoked', 'revoked'], ['host_quit', 'host_offline']]) {
  test(`bye reasons: ${reason} → ${state}`, async () => {
    const ctx = setup();
    const live = await goLive(ctx);
    await live.host.send({ t: 'bye', reason });
    await settle(() => ctx.session.state === state);
    assert.ok(live.circuit.closed, 'circuit closed after bye');
  });
}

test('live stream: replay, out, size and panes reach the page; stage-3 AAD only', async () => {
  const ctx = setup();
  const got = [];
  for (const ev of ['replay', 'out', 'size', 'panes']) ctx.session.on(ev, (e) => got.push([ev, e]));
  const live = await goLive(ctx);
  await live.host.send({ t: 'replay', pane: 'p1', cols: 100, rows: 30, data: b64Encode(utf8('\x1b[2Jhello')) });
  await live.host.send({ t: 'out', pane: 'p1', data: b64Encode(utf8('chào')) });
  await live.host.send({ t: 'size', pane: 'p1', cols: 120, rows: 40 });
  await live.host.send({ t: 'panes', panes: [{ id: 'p3', title: 'logs', kind: 'terminal', cols: 80, rows: 24 }], active: 'p3' });
  await settle(() => got.length === 4, 'four events');
  assert.equal(got[0][0], 'replay');
  assert.equal(got[0][1].cols, 100);
  assert.equal(text(got[0][1].data), '\x1b[2Jhello');
  assert.equal(text(got[1][1].data), 'chào');
  assert.deepEqual([got[2][1].cols, got[2][1].rows], [120, 40]);
  assert.equal(got[3][1].active, 'p3');
  assert.equal(ctx.session.active, 'p3');
  // A frame sealed with the welcome-stage AAD after welcome no longer opens.
  await live.host.send({ t: 'out', pane: 'p3', data: b64Encode(utf8('x')) }, 'welcome');
  await settle(() => ctx.session.dropped === 1);
  assert.equal(got.length, 4);
});

test('replayed or reordered frames (non-increasing seq) are dropped and counted', async () => {
  const ctx = setup();
  const outs = [];
  ctx.session.on('out', (e) => outs.push(text(e.data)));
  const live = await goLive(ctx); // welcome used seq 1
  const aad = aadFor('circuit-1', live.host.hello.nonce, live.host.hostNonce);
  await live.host.sendRaw({ t: 'out', pane: 'p1', data: b64Encode(utf8('a')) }, 2, aad);
  await live.host.sendRaw({ t: 'out', pane: 'p1', data: b64Encode(utf8('again')) }, 2, aad);
  await live.host.sendRaw({ t: 'out', pane: 'p1', data: b64Encode(utf8('old')) }, 1, aad);
  await live.host.sendRaw({ t: 'out', pane: 'p1', data: b64Encode(utf8('b')) }, 7, aad);
  await settle(() => outs.length === 2 && ctx.session.dropped === 2);
  assert.deepEqual(outs, ['a', 'b']);
});

test('a bye queued just before a relay peer-disconnected error still decides the state', async () => {
  const ctx = setup();
  const seen = states(ctx.session);
  const live = await goLive(ctx);
  // cmux-relay forwards the host's last frame, then reports the peer gone, back to back: the
  // error text arrives while the bye is still being decrypted.
  await live.host.send({ t: 'bye', reason: 'revoked' });
  live.circuit.serverText({ type: 'error', code: 'peer-disconnected', message: 'gone', retryable: true });
  await settle(() => seen.includes('revoked') || seen.includes('ended'), 'a terminal state');
  assert.equal(ctx.session.state, 'revoked');
  assert.ok(!seen.includes('ended'), `states: ${seen.join(' → ')}`);
});

test('circuit closing while live ends the session', async () => {
  const ctx = setup();
  const live = await goLive(ctx);
  live.circuit.serverClose(1006);
  await settle(() => ctx.session.state === 'ended', 'ended');
});

test('select sends a select frame and switches the active pane', async () => {
  const ctx = setup();
  const live = await goLive(ctx, 'view');
  ctx.session.select('p2');
  await settle(() => live.circuit.binarySent().length === 2);
  const msgs = await live.host.received();
  assert.deepEqual(msgs, [{ t: 'select', seq: 2, pane: 'p2' }]);
  assert.equal(ctx.session.active, 'p2');
});

test('view-only page sends no input frames', async () => {
  const ctx = setup();
  const live = await goLive(ctx, 'view');
  assert.equal(ctx.session.canType, false);
  const input = createInput({ onData: (bytes) => ctx.session.input(bytes) });
  input.handle({ type: 'input', inputType: 'insertText', data: 'ls' });
  input.handle({ type: 'keydown', key: 'Enter' });
  ctx.session.input(utf8('rm -rf /\r'));
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(live.circuit.binarySent().length, 1, 'only the hello frame was sent');
});

test('typing sends in frames for the active pane, chunked to 4 KiB', async () => {
  const ctx = setup();
  const live = await goLive(ctx, 'type');
  assert.equal(ctx.session.canType, true);
  ctx.session.input(new Uint8Array(4096 + 10).fill(0x61));
  await settle(() => live.circuit.binarySent().length === 3);
  const msgs = await live.host.received();
  assert.deepEqual(msgs.map((m) => [m.t, m.seq, m.pane, b64Decode(m.data).length]), [['in', 2, 'p1', 4096], ['in', 3, 'p1', 10]]);
});

test('composition sends text once', async () => {
  const ctx = setup();
  const live = await goLive(ctx, 'type');
  const input = createInput({ onData: (bytes) => ctx.session.input(bytes) });
  input.handle({ type: 'compositionstart', data: '' });
  input.handle({ type: 'input', isComposing: true, inputType: 'insertCompositionText', data: 'ch' });
  input.handle({ type: 'keydown', key: 'Process', isComposing: true, keyCode: 229 });
  input.handle({ type: 'input', isComposing: true, inputType: 'insertCompositionText', data: 'chà' });
  input.handle({ type: 'compositionend', data: 'chào' });
  // Safari fires the final input after compositionend; it must not repeat the text.
  input.handle({ type: 'input', isComposing: false, inputType: 'insertFromComposition', data: 'chào' });
  input.handle({ type: 'keydown', key: 'Enter' });
  input.handle({ type: 'keydown', key: 'Backspace' });
  await settle(() => live.circuit.binarySent().length === 4);
  await new Promise((r) => setTimeout(r, 10));
  const msgs = await live.host.received();
  assert.deepEqual(msgs.map((m) => text(b64Decode(m.data))), ['chào', '\r', '\x7f']);
  assert.deepEqual([...b64Decode(msgs[0].data)], [...utf8('chào')], 'UTF-8 bytes');
});

// ---------------------------------------------------------------------------------------------
// Input mapping (pure)

function collect() {
  const out = [];
  const input = createInput({ onData: (b) => out.push(text(b)) });
  return { input, out };
}

test('keys map to terminal bytes; printable keys wait for the input event', () => {
  const { input, out } = collect();
  const cases = [
    [{ key: 'Enter' }, '\r'], [{ key: 'Backspace' }, '\x7f'], [{ key: 'Tab' }, '\t'], [{ key: 'Escape' }, '\x1b'],
    [{ key: 'ArrowUp' }, '\x1b[A'], [{ key: 'ArrowDown' }, '\x1b[B'], [{ key: 'ArrowRight' }, '\x1b[C'],
    [{ key: 'ArrowLeft' }, '\x1b[D'], [{ key: 'Home' }, '\x1b[H'], [{ key: 'End' }, '\x1b[F'],
    [{ key: 'Delete' }, '\x1b[3~'], [{ key: 'PageUp' }, '\x1b[5~'], [{ key: 'PageDown' }, '\x1b[6~'],
    [{ key: 'c', ctrlKey: true }, '\x03'], [{ key: 'D', ctrlKey: true, shiftKey: true }, '\x04'],
    [{ key: '[', ctrlKey: true }, '\x1b'],
  ];
  for (const [ev, bytes] of cases) {
    out.length = 0;
    assert.equal(input.handle({ type: 'keydown', ...ev }), true, `${ev.key} is handled`);
    assert.deepEqual(out, [bytes], ev.key);
  }
  out.length = 0;
  assert.equal(input.handle({ type: 'keydown', key: 'a' }), false, 'printable keydown is left to the input event');
  assert.equal(input.handle({ type: 'keydown', key: 'c', metaKey: true }), false, 'Cmd+C stays a browser copy');
  assert.equal(input.handle({ type: 'keydown', key: 'Unidentified', keyCode: 229 }), false, 'Android IME keydown');
  input.handle({ type: 'input', inputType: 'insertText', data: 'a' });
  input.handle({ type: 'input', inputType: 'deleteContentBackward', data: null });
  input.handle({ type: 'input', inputType: 'insertLineBreak', data: null });
  input.handle({ type: 'paste', text: 'echo hi' });
  assert.deepEqual(out, ['a', '\x7f', '\r', 'echo hi']);
});

test('on-screen key row: Esc, Tab, arrows and a one-shot Ctrl', () => {
  const { input, out } = collect();
  input.press('Escape');
  input.press('Tab');
  input.press('ArrowLeft');
  input.toggleCtrl();
  assert.equal(input.ctrlArmed, true);
  input.handle({ type: 'input', inputType: 'insertText', data: 'c' });
  assert.equal(input.ctrlArmed, false, 'Ctrl applies to one key');
  input.handle({ type: 'input', inputType: 'insertText', data: 'c' });
  assert.deepEqual(out, ['\x1b', '\t', '\x1b[D', '\x03', 'c']);
});

test('viewer sources never log (the secret, tickets and keys must not reach a console)', () => {
  for (const f of ['wire.mjs', 'session.mjs', 'input.mjs', 'viewer.mjs']) {
    const src = readFileSync(join(root, 'src/share', f), 'utf8');
    assert.ok(!/\bconsole\./.test(src), `src/share/${f} uses console`);
  }
});

// ---------------------------------------------------------------------------------------------
// Fix round 1

for (const [label, fetchImpl] of [
  ['a ticket request that never answers', (calls) => (url, init) => { calls.push(init); return new Promise(() => {}); }],
  ['a ticket body that never arrives', (calls) => async (url, init) => {
    calls.push(init);
    return { ok: true, status: 200, json: () => new Promise(() => {}) };
  }],
]) {
  test(`one 15 s deadline covers ${label}: host_offline, request aborted`, async () => {
    const clock = fakeClock();
    const calls = [];
    const WebSocket = fakeWebSocketClass();
    const session = createSession({
      id: SHARE_ID, secret: SECRET, storage: memoryStorage(), WebSocket, fetch: fetchImpl(calls),
      now: clock.now, setTimeout: clock.setTimeout, clearTimeout: clock.clearTimeout,
    });
    const seen = states(session);
    session.start(); // never settles while the request hangs; the deadline ends the session anyway
    await settle(() => calls.length === 1, 'ticket fetch');
    assert.ok(calls[0].signal instanceof AbortSignal, 'fetch gets an abort signal');
    clock.advance(14_999);
    assert.equal(session.state, 'loading');
    clock.advance(1);
    assert.equal(session.state, 'host_offline');
    assert.deepEqual(seen, ['loading', 'host_offline']);
    assert.ok(calls[0].signal.aborted, 'the ticket request was aborted');
    assert.equal(WebSocket.sockets.length, 0);
    assert.equal(clock.pending(), 0);
  });
}

test('the deadline started at the ticket request still bounds the relay handshake', async () => {
  const ctx = setup();
  ctx.session.start();
  await settle(() => ctx.WebSocket.sockets.length === 1);
  ctx.clock.advance(15_000);
  assert.equal(ctx.session.state, 'host_offline');
  assert.equal(ctx.clock.pending(), 0);
});

test('keepalive (A2): a ka after welcome changes nothing and is not counted', async () => {
  const ctx = setup();
  const events = [];
  for (const ev of ['state', 'out', 'panes', 'replay', 'size', 'welcome']) ctx.session.on(ev, (e) => events.push([ev, e]));
  const live = await goLive(ctx);
  events.length = 0;
  await live.host.send({ t: 'ka' }); // seq 2
  await live.host.send({ t: 'ka' }); // seq 3
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(ctx.session.state, 'live');
  assert.equal(ctx.session.dropped, 0);
  assert.deepEqual(events, []);
  // ka advanced seq: a replay of seq 3 is now dropped, seq 4 is accepted.
  const aad = aadFor('circuit-1', live.host.hello.nonce, live.host.hostNonce);
  await live.host.sendRaw({ t: 'out', pane: 'p1', data: b64Encode(utf8('old')) }, 3, aad);
  await live.host.sendRaw({ t: 'out', pane: 'p1', data: b64Encode(utf8('new')) }, 4, aad);
  await settle(() => events.length === 1 && ctx.session.dropped === 1);
  assert.equal(text(events[0][1].data), 'new');
});

test('keepalive (A2): a ka before welcome is dropped and counted', async () => {
  const ctx = setup();
  ctx.session.start();
  const { circuit } = await relayToReady(ctx);
  const host = await hostFor(circuit);
  await host.send({ t: 'ka' }, 'welcome');
  await settle(() => ctx.session.dropped === 1);
  assert.equal(ctx.session.state, 'connecting');
  await host.welcome();
  await settle(() => ctx.session.state === 'live');
});

test('a throwing page listener is counted; three in a row end in error', async () => {
  const ctx = setup();
  ctx.session.on('out', () => { throw new Error('render failed'); });
  const live = await goLive(ctx);
  await live.host.send({ t: 'out', pane: 'p1', data: b64Encode(utf8('a')) });
  await settle(() => ctx.session.dropped === 1);
  assert.equal(ctx.session.state, 'live');
  await live.host.send({ t: 'out', pane: 'p1', data: b64Encode(utf8('b')) });
  await live.host.send({ t: 'out', pane: 'p1', data: b64Encode(utf8('c')) });
  await settle(() => ctx.session.state === 'error');
  assert.ok(live.circuit.closed);
});

test('Ctrl+V and Ctrl+Shift+V are left to the browser paste outside macOS', () => {
  const { input, out } = collect();
  assert.equal(input.handle({ type: 'keydown', key: 'v', ctrlKey: true }), false);
  assert.equal(input.handle({ type: 'keydown', key: 'V', ctrlKey: true, shiftKey: true }), false);
  assert.deepEqual(out, []);
  input.handle({ type: 'paste', text: 'pasted' });
  assert.deepEqual(out, ['pasted']);
  const mac = [];
  const macInput = createInput({ onData: (b) => mac.push(text(b)), isMac: true });
  assert.equal(macInput.handle({ type: 'keydown', key: 'v', ctrlKey: true }), true);
  assert.deepEqual(mac, ['\x16'], 'on a Mac Cmd+V pastes, so Ctrl+V is the terminal ^V');
});
