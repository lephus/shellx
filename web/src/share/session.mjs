// Share viewer session: ticket from the ShellX API, relay2 control + circuit WebSockets, then the
// encrypted share protocol. Every dependency is injected so tests drive it with fakes.
//
// States: loading → connecting → live | expired | revoked | used | host_offline | not_found | ended | error.
// Everything after `live` (and every refusal) is terminal: sockets are closed and timers cleared.
import {
  aadFor, b64Encode, b64urlDecode, b64urlEncode, decodeHostMessage, deriveKeys, encodeMessage, MAX_INPUT_BYTES,
  normalizeShareId, openFrame, randomBytes, sealFrame,
} from './wire.mjs';

export const RELAY_PROTOCOL = 5;
export const CONNECT_TIMEOUT_MS = 15_000;
export const DEFAULT_API_BASE = 'https://relay.shellx.pro';

const MAX_LISTENER_FAILURES = 3;
const TERMINAL = new Set(['expired', 'revoked', 'used', 'host_offline', 'not_found', 'ended', 'error']);
const API_CODES = {
  share_not_found: 'not_found',
  share_revoked: 'revoked',
  share_expired: 'expired',
  share_used: 'used',
  host_offline: 'host_offline',
};
const BYE = { expired: 'expired', revoked: 'revoked', host_quit: 'host_offline' };
// Relay errors that mean "nobody is hosting this slot right now".
const RELAY_OFFLINE = new Set(['slot-offline', 'peer-detached', 'peer-disconnected', 'circuit-timeout', 'circuit-not-found']);

function viewerIdFrom(storage, shareId) {
  const key = `shellx.share.viewer.${shareId}`;
  try {
    const stored = storage?.getItem(key);
    if (typeof stored === 'string' && /^[A-Za-z0-9_-]{16,64}$/.test(stored)) return stored;
  } catch {
    // Private mode or blocked storage: a fresh id per page load still works for non one-time shares.
  }
  const id = b64urlEncode(randomBytes(16));
  try {
    storage?.setItem(key, id);
  } catch {
    // ignore
  }
  return id;
}

/** A circuit URL: legacy `/v1/slots/...` endpoints join on `/v1/circuits/<id>`, others on the same URL. */
function circuitUrl(relayUrl, circuit) {
  try {
    const url = new URL(relayUrl);
    if (!url.pathname.startsWith('/v1/slots/')) return relayUrl;
    url.pathname = `/v1/circuits/${encodeURIComponent(circuit)}`;
    return url.toString();
  } catch {
    return relayUrl;
  }
}

export function createSession({
  id, secret, fetch, WebSocket, now = Date.now, setTimeout: setTimer = globalThis.setTimeout,
  clearTimeout: clearTimer = globalThis.clearTimeout, storage, apiBase = DEFAULT_API_BASE, label = 'Browser',
  timeoutMs = CONNECT_TIMEOUT_MS,
}) {
  const listeners = new Map();
  let state = 'loading';
  let detail = null;
  let control = null;
  let circuit = null;
  let timer = null;
  let keys = null;
  let circuitId = null;
  let viewerNonce = null;
  let hostNonce = null;
  let sendSeq = 0;
  let lastSeq = 0;
  let dropped = 0;
  let perm = null;
  let panes = [];
  let active = null;
  let expiresAt = null;
  // Frames are opened one at a time, in arrival order, so `seq` checks see them in order.
  let inbound = Promise.resolve();
  let outbound = Promise.resolve();

  function emit(type, value) {
    for (const fn of listeners.get(type) ?? []) fn(value);
  }

  function setState(next, info = null) {
    if (state === next || TERMINAL.has(state)) return;
    state = next;
    detail = info;
    if (TERMINAL.has(next)) teardown();
    emit('state', { state: next, detail: info });
  }

  function teardown() {
    if (timer !== null) clearTimer(timer);
    timer = null;
    for (const ws of [control, circuit]) {
      if (!ws) continue;
      ws.onopen = ws.onmessage = ws.onerror = ws.onclose = null;
      try {
        ws.close();
      } catch {
        // already closed
      }
    }
    control = circuit = null;
  }

  function sendText(ws, obj) {
    try {
      ws.send(JSON.stringify(obj));
      return true;
    } catch {
      return false;
    }
  }

  function parseControl(event) {
    if (typeof event.data !== 'string') return null;
    try {
      const msg = JSON.parse(event.data);
      return msg && typeof msg.type === 'string' ? msg : null;
    } catch {
      return null;
    }
  }

  // A page listener threw while handling a frame: count it, and give up after a few in a row.
  let listenerFailures = 0;
  function listenerFailed() {
    dropped += 1;
    listenerFailures += 1;
    if (listenerFailures >= MAX_LISTENER_FAILURES) setState('error', { listener: true });
  }

  function relayError(msg) {
    setState(RELAY_OFFLINE.has(msg.code) && state !== 'live' ? 'host_offline' : state === 'live' ? 'ended' : 'error',
      { relay: String(msg.code ?? '') });
  }

  // Seals one viewer → host message. hello uses the stage-1 AAD, everything else stage 3.
  function sendMessage(fields) {
    const seq = ++sendSeq;
    const aad = fields.t === 'hello' ? aadFor(circuitId) : aadFor(circuitId, viewerNonce, hostNonce);
    const plaintext = new TextEncoder().encode(encodeMessage(fields, seq));
    const ws = circuit;
    outbound = outbound.then(async () => {
      const frame = await sealFrame(keys.viewerToHost, aad, plaintext);
      if (ws && ws === circuit) ws.send(frame);
    }).catch(() => {
      dropped += 1; // seal or send failed; the frame is lost
    });
    return outbound;
  }

  async function receiveFrame(bytes) {
    // Before welcome the host speaks with the welcome-stage AAD; afterwards with both nonces.
    const aad = hostNonce === null ? aadFor(circuitId, viewerNonce) : aadFor(circuitId, viewerNonce, hostNonce);
    const plain = await openFrame(keys.hostToViewer, aad, bytes);
    const msg = plain && decodeHostMessage(plain);
    if (!msg || msg.seq <= lastSeq || TERMINAL.has(state)) {
      if (!TERMINAL.has(state)) dropped += 1;
      return;
    }
    // Before welcome only welcome or bye (A1); ka and everything else is dropped.
    if (hostNonce === null && msg.t !== 'welcome' && msg.t !== 'bye') {
      dropped += 1;
      return;
    }
    if (hostNonce !== null && msg.t === 'welcome') {
      dropped += 1;
      return;
    }
    lastSeq = msg.seq;
    dispatch(msg);
    listenerFailures = 0;
  }

  function dispatch(msg) {
    switch (msg.t) {
      case 'ka':
        // A2 keepalive: only advances seq.
        break;
      case 'welcome':
        hostNonce = msg.nonce;
        perm = msg.perm;
        panes = msg.panes;
        active = msg.active;
        expiresAt = msg.expiresAt;
        if (timer !== null) clearTimer(timer);
        timer = null;
        // The control socket is only needed to allocate; the circuit lives on its own.
        if (control) {
          control.onopen = control.onmessage = control.onerror = control.onclose = null;
          try {
            control.close();
          } catch {
            // ignore
          }
          control = null;
        }
        setState('live');
        emit('welcome', { perm, panes, active, expiresAt });
        break;
      case 'panes':
        // Only the list and titles: `msg.active` is the host's own focus, not the viewer's pane. If
        // the shown pane vanished, nothing is shown until the host's replay names what it streams.
        panes = msg.panes;
        if (!panes.some((p) => p.id === active)) active = null;
        emit('panes', { panes, active });
        break;
      case 'replay':
        // The host decides what is streamed; its replay sets the shown pane.
        active = msg.pane;
        emit('replay', { pane: msg.pane, cols: msg.cols, rows: msg.rows, data: msg.data });
        break;
      case 'out':
        if (msg.pane === active) emit('out', { pane: msg.pane, data: msg.data });
        break;
      case 'size':
        panes = panes.map((p) => (p.id === msg.pane ? { ...p, cols: msg.cols, rows: msg.rows } : p));
        if (msg.pane === active) emit('size', { pane: msg.pane, cols: msg.cols, rows: msg.rows });
        break;
      case 'bye':
        setState(BYE[msg.reason], { bye: msg.reason });
        break;
    }
  }

  function openCircuit(relayUrl, slot, alloc) {
    circuitId = alloc.circuit;
    const ws = new WebSocket(circuitUrl(relayUrl, alloc.circuit));
    circuit = ws;
    ws.binaryType = 'arraybuffer';
    let ready = false;
    ws.onopen = () => {
      sendText(ws, {
        type: 'join', protocol: RELAY_PROTOCOL, slot, circuit: alloc.circuit, lane: alloc.lane,
        generation: alloc.generation, ticket: alloc.join_ticket, role: 'client',
      });
    };
    ws.onmessage = (event) => {
      if (typeof event.data === 'string') {
        const msg = parseControl(event);
        if (!msg) return;
        if (msg.type === 'ready' && !ready && msg.circuit === alloc.circuit && msg.lane === alloc.lane
            && msg.generation === alloc.generation) {
          ready = true;
          viewerNonce = b64Encode(randomBytes(16));
          sendMessage({ t: 'hello', nonce: viewerNonce, label: String(label).slice(0, 40) });
        } else if (msg.type === 'ping') {
          sendText(ws, { type: 'pong', nonce: msg.nonce });
        } else if (msg.type === 'error') {
          inbound.then(() => relayError(msg)); // after queued frames (a bye just before the peer-disconnected error)
        }
        return;
      }
      if (!ready) return;
      const bytes = new Uint8Array(event.data);
      inbound = inbound.then(() => receiveFrame(bytes)).catch(listenerFailed);
    };
    ws.onclose = () => {
      if (circuit !== ws) return;
      circuit = null;
      // Let frames that already arrived (a bye just before close) land first.
      inbound.then(() => setState(state === 'live' ? 'ended' : 'error', { closed: true }));
    };
    ws.onerror = () => {};
  }

  function connectRelay(ticket) {
    const relayUrl = ticket.relay_url;
    const slot = ticket.slot;
    const lane = b64urlEncode(randomBytes(24));
    const generation = 1;
    let ws;
    try {
      ws = new WebSocket(relayUrl);
    } catch {
      setState('error', { relay: 'connect' });
      return;
    }
    control = ws;
    let allocated = false;
    ws.onopen = () => {
      sendText(ws, { type: 'connect', protocol: RELAY_PROTOCOL, slot, ticket: ticket.ticket, lane, generation });
    };
    ws.onmessage = (event) => {
      const msg = parseControl(event);
      if (!msg) return;
      if (msg.type === 'allocated' && !allocated && msg.lane === lane && msg.generation === generation
          && typeof msg.circuit === 'string' && typeof msg.join_ticket === 'string') {
        allocated = true;
        openCircuit(relayUrl, slot, msg);
      } else if (msg.type === 'ping') {
        sendText(ws, { type: 'pong', nonce: msg.nonce });
      } else if (msg.type === 'error') {
        relayError(msg);
      }
    };
    ws.onclose = () => {
      if (control !== ws) return;
      control = null;
      if (!allocated) setState('error', { closed: true });
    };
    ws.onerror = () => {};
  }

  async function requestTicket(shareId, access, viewer, signal) {
    let response;
    try {
      response = await fetch(`${apiBase.replace(/\/+$/, '')}/v2/shares/${shareId}/ticket`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ access, viewer }),
        credentials: 'omit',
        referrerPolicy: 'no-referrer',
        cache: 'no-store',
        signal,
      });
    } catch {
      return { state: 'error', detail: { api: 'network' } };
    }
    let body = null;
    try {
      body = await response.json();
    } catch {
      body = null;
    }
    if (response.ok) {
      const ok = body && typeof body.ticket === 'string' && typeof body.relay_url === 'string'
        && /^wss?:\/\//.test(body.relay_url) && typeof body.slot === 'string';
      return ok ? { ticket: body } : { state: 'error', detail: { api: 'bad_response' } };
    }
    const code = body?.error?.code;
    if (API_CODES[code]) return { state: API_CODES[code], detail: { api: code } };
    if (response.status === 404) return { state: 'not_found', detail: { api: 'share_not_found' } };
    return { state: 'error', detail: { api: typeof code === 'string' ? code : `http_${response.status}` } };
  }

  async function start() {
    if (state !== 'loading' || keys || timer !== null) return;
    const shareId = normalizeShareId(id);
    // Exactly 43 canonical base64url characters (32 bytes), as the Swift ShareSecret parser demands.
    const secretBytes = typeof secret === 'string' && secret.length === 43 ? b64urlDecode(secret) : null;
    if (!shareId || !secretBytes || secretBytes.length !== 32 || b64urlEncode(secretBytes) !== secret) {
      setState('not_found', { link: 'invalid' });
      return;
    }
    // One deadline covers the ticket request, its body and the relay handshake up to welcome.
    const abort = typeof AbortController === 'function' ? new AbortController() : null;
    timer = setTimer(() => {
      timer = null;
      abort?.abort();
      setState('host_offline', { timeout: true });
    }, timeoutMs);
    try {
      keys = await deriveKeys(secretBytes, shareId);
    } catch {
      setState('error', { crypto: true });
      return;
    } finally {
      secretBytes.fill(0);
    }
    if (TERMINAL.has(state)) return;
    const result = await requestTicket(shareId, keys.access, viewerIdFrom(storage, shareId), abort?.signal);
    if (TERMINAL.has(state)) return;
    if (result.state) {
      setState(result.state, result.detail);
      return;
    }
    setState('connecting');
    connectRelay(result.ticket);
  }

  return {
    start,
    on(type, fn) {
      if (!listeners.has(type)) listeners.set(type, new Set());
      listeners.get(type).add(fn);
      return () => listeners.get(type).delete(fn);
    },
    /** Asks the host to stream another pane. */
    select(pane) {
      if (state !== 'live' || !panes.some((p) => p.id === pane)) return;
      active = pane;
      sendMessage({ t: 'select', pane });
    },
    /** Sends typed bytes to the active pane; a no-op unless the share allows typing. */
    input(bytes) {
      if (state !== 'live' || perm !== 'type' || !active || !bytes?.length) return;
      for (let i = 0; i < bytes.length; i += MAX_INPUT_BYTES) {
        sendMessage({ t: 'in', pane: active, data: b64Encode(bytes.subarray(i, i + MAX_INPUT_BYTES)) });
      }
    },
    close() {
      setState('ended', { local: true });
    },
    get state() { return state; },
    get detail() { return detail; },
    get perm() { return perm; },
    get canType() { return state === 'live' && perm === 'type'; },
    get panes() { return panes; },
    get active() { return active; },
    get expiresAt() { return expiresAt; },
    get dropped() { return dropped; },
    /** Seconds until the share expires (null: no expiry announced), by the injected clock. */
    get secondsLeft() { return expiresAt === null ? null : Math.max(0, Math.floor(expiresAt - now() / 1000)); },
  };
}
