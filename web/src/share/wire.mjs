// Share wire format v1 + amendment A1 (see the Swift twin in
// Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/Share/ and web/tests/fixtures/share-vectors.json).
//
// Keys: HKDF-SHA256(ikm = 32-byte secret, salt = UTF-8 share id without dash) for the infos below.
// Frame: nonce(12) || AES-256-GCM ciphertext || tag(16). AAD is staged per connection:
//   hello  `shellx-share/1|<circuit>`
//   welcome `shellx-share/1|<circuit>|<viewer nonce b64>`
//   later  `shellx-share/1|<circuit>|<viewer nonce b64>|<host nonce b64>`
// Plaintext: UTF-8 JSON, keys in a fixed order (t, seq, then the v1 fields).

export const MAX_FRAME_BYTES = 64 * 1024;
export const MAX_INPUT_BYTES = 4096;
const NONCE_BYTES = 12;
const TAG_BYTES = 16;

const ID_ALPHABET = /^[0123456789abcdefghjkmnpqrstvwxyz]{8}$/;
const encoder = new TextEncoder();

function subtle() {
  return globalThis.crypto.subtle;
}

/** `k7f2-9qd1` or `k7f29qd1` → `k7f29qd1`; null unless 8 chars of the share alphabet. */
export function normalizeShareId(id) {
  if (typeof id !== 'string') return null;
  const m = /^([0-9a-z]{4})-?([0-9a-z]{4})$/.exec(id);
  if (!m) return null;
  const plain = m[1] + m[2];
  return ID_ALPHABET.test(plain) ? plain : null;
}

export function b64Encode(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) {
    s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  }
  return btoa(s);
}

/** Standard base64 → bytes; null when malformed. */
export function b64Decode(s) {
  if (typeof s !== 'string') return null;
  let bin;
  try {
    bin = atob(s);
  } catch {
    return null;
  }
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function b64urlEncode(bytes) {
  return b64Encode(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** base64url without padding → bytes; null when malformed or padded. */
export function b64urlDecode(s) {
  if (typeof s !== 'string' || !/^[A-Za-z0-9_-]*$/.test(s) || s.length % 4 === 1) return null;
  const std = s.replace(/-/g, '+').replace(/_/g, '/');
  return b64Decode(std + '='.repeat((4 - (std.length % 4)) % 4));
}

export function randomBytes(n) {
  return globalThis.crypto.getRandomValues(new Uint8Array(n));
}

async function hkdf(secret, salt, info) {
  const ikm = await subtle().importKey('raw', secret, 'HKDF', false, ['deriveBits']);
  const bits = await subtle().deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt: encoder.encode(salt), info: encoder.encode(info) }, ikm, 256);
  return new Uint8Array(bits);
}

/** Raw key bytes (tests compare them with the vectors) and the base64url access token. */
export async function deriveKeyBytes(secret, shareId) {
  const salt = String(shareId).replace(/-/g, '');
  const [hostToViewer, viewerToHost, access] = await Promise.all([
    hkdf(secret, salt, 'shellx-share/1 host->viewer'),
    hkdf(secret, salt, 'shellx-share/1 viewer->host'),
    hkdf(secret, salt, 'shellx-share/1 access'),
  ]);
  return { hostToViewer, viewerToHost, access: b64urlEncode(access) };
}

/** Non-extractable AES-GCM keys for both directions plus the access token. */
export async function deriveKeys(secret, shareId) {
  const raw = await deriveKeyBytes(secret, shareId);
  const importKey = (bytes) => subtle().importKey('raw', bytes, 'AES-GCM', false, ['encrypt', 'decrypt']);
  const [hostToViewer, viewerToHost] = await Promise.all([importKey(raw.hostToViewer), importKey(raw.viewerToHost)]);
  raw.hostToViewer.fill(0);
  raw.viewerToHost.fill(0);
  return { hostToViewer, viewerToHost, access: raw.access };
}

/** AAD for the current stage: no nonce (hello), viewer nonce (welcome), both (everything after). */
export function aadFor(circuit, viewerNonce, hostNonce) {
  let s = `shellx-share/1|${circuit}`;
  if (viewerNonce !== undefined) s += `|${viewerNonce}`;
  if (hostNonce !== undefined) s += `|${hostNonce}`;
  return s;
}

export async function sealFrame(key, aad, plaintext, nonce = randomBytes(NONCE_BYTES)) {
  const sealed = new Uint8Array(await subtle().encrypt(
    { name: 'AES-GCM', iv: nonce, additionalData: encoder.encode(aad), tagLength: 128 }, key, plaintext));
  const frame = new Uint8Array(NONCE_BYTES + sealed.length);
  frame.set(nonce, 0);
  frame.set(sealed, NONCE_BYTES);
  return frame;
}

/** Plaintext bytes, or null for an oversized, truncated or unauthentic frame. */
export async function openFrame(key, aad, frame) {
  if (!(frame instanceof Uint8Array) || frame.length > MAX_FRAME_BYTES || frame.length < NONCE_BYTES + TAG_BYTES) {
    return null;
  }
  try {
    const plain = await subtle().decrypt(
      { name: 'AES-GCM', iv: frame.subarray(0, NONCE_BYTES), additionalData: encoder.encode(aad), tagLength: 128 },
      key, frame.subarray(NONCE_BYTES));
    return new Uint8Array(plain);
  } catch {
    return null;
  }
}

// Field order after `t` and `seq`, per message type (v1 + A1).
const FIELDS = {
  hello: ['nonce', 'label'],
  select: ['pane'],
  in: ['pane', 'data'],
  welcome: ['nonce', 'perm', 'expires_at_unix', 'panes', 'active'],
  panes: ['panes', 'active'],
  replay: ['pane', 'cols', 'rows', 'data'],
  out: ['pane', 'data'],
  size: ['pane', 'cols', 'rows'],
  bye: ['reason'],
};
const PANE_FIELDS = ['id', 'title', 'kind', 'cols', 'rows'];

/** Deterministic JSON for a message: `t`, `seq`, then the type's fields in v1 order. */
export function encodeMessage(message, seq) {
  const fields = FIELDS[message.t];
  if (!fields) throw new Error('unknown message type');
  const out = { t: message.t, seq };
  for (const f of fields) {
    const v = message[f];
    if (f === 'panes') {
      out.panes = (v ?? []).map((p) => Object.fromEntries(PANE_FIELDS.map((k) => [k, p[k]])));
    } else if (f === 'expires_at_unix') {
      out[f] = v ?? null;
    } else {
      out[f] = v;
    }
  }
  return JSON.stringify(out);
}

const isInt = (v) => Number.isSafeInteger(v);
const isStr = (v) => typeof v === 'string';
const isPane = (p) => p && isStr(p.id) && isStr(p.title) && ['terminal', 'browser', 'agent'].includes(p.kind)
  && isInt(p.cols) && isInt(p.rows);

/**
 * Parses a host → viewer plaintext. Returns the message with `data` decoded to bytes, or null when the
 * JSON, the type or a field is invalid.
 */
export function decodeHostMessage(plaintext) {
  let m;
  try {
    m = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(plaintext));
  } catch {
    return null;
  }
  if (!m || typeof m !== 'object' || !isInt(m.seq) || m.seq < 1) return null;
  switch (m.t) {
    case 'welcome': {
      const nonce = b64Decode(m.nonce);
      if (!nonce || nonce.length !== 16) return null;
      if (!['view', 'type'].includes(m.perm)) return null;
      if (!(m.expires_at_unix === null || m.expires_at_unix === undefined || isInt(m.expires_at_unix))) return null;
      if (!Array.isArray(m.panes) || !m.panes.every(isPane) || !isStr(m.active)) return null;
      return { t: 'welcome', seq: m.seq, nonce: m.nonce, perm: m.perm, expiresAt: m.expires_at_unix ?? null,
        panes: m.panes, active: m.active };
    }
    case 'panes':
      if (!Array.isArray(m.panes) || !m.panes.every(isPane) || !isStr(m.active)) return null;
      return { t: 'panes', seq: m.seq, panes: m.panes, active: m.active };
    case 'replay': {
      const data = b64Decode(m.data);
      if (!data || !isStr(m.pane) || !isInt(m.cols) || !isInt(m.rows)) return null;
      return { t: 'replay', seq: m.seq, pane: m.pane, cols: m.cols, rows: m.rows, data };
    }
    case 'out': {
      const data = b64Decode(m.data);
      if (!data || !isStr(m.pane)) return null;
      return { t: 'out', seq: m.seq, pane: m.pane, data };
    }
    case 'size':
      if (!isStr(m.pane) || !isInt(m.cols) || !isInt(m.rows)) return null;
      return { t: 'size', seq: m.seq, pane: m.pane, cols: m.cols, rows: m.rows };
    case 'bye':
      if (!['revoked', 'expired', 'host_quit'].includes(m.reason)) return null;
      return { t: 'bye', seq: m.seq, reason: m.reason };
    default:
      return null;
  }
}
