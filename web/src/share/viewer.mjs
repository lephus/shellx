// DOM + xterm.js glue for the share viewer page (src/pages/s/index.astro). The protocol lives in
// session.mjs, the keyboard mapping in input.mjs. The link (id + secret) comes from the inline boot
// script, which already stripped the fragment from the address bar.
import { Terminal } from '@xterm/xterm';
import '@xterm/xterm/css/xterm.css';
import { createSession } from './session.mjs';
import { createInput } from './input.mjs';

const root = document.querySelector('[data-share]');
const link = window.__shellxShare ?? { id: '', secret: '' };
delete window.__shellxShare;

const all = JSON.parse(document.getElementById('share-strings').textContent);
const langs = [...(navigator.languages ?? []), navigator.language ?? ''].map((l) => String(l).toLowerCase());
const lang = (langs.find(Boolean) ?? 'vi').startsWith('vi') ? 'vi' : 'en';
const t = all[lang];

const $ = (sel) => root.querySelector(sel);
const el = {
  perm: $('[data-perm]'),
  expiry: $('[data-expiry]'),
  panes: $('[data-panes]'),
  statusTitle: $('[data-status-title]'),
  statusBody: $('[data-status-body]'),
  status: $('[data-status]'),
  retry: $('[data-retry]'),
  stage: $('[data-stage]'),
  termScroll: $('[data-term-scroll]'),
  term: $('[data-term]'),
  input: $('[data-input]'),
  placeholder: $('[data-placeholder]'),
  keys: $('[data-keys]'),
};

function applyLanguage() {
  document.documentElement.lang = lang;
  document.title = `${t.shareTitle} — ShellX`;
  for (const node of root.querySelectorAll('[data-t]')) node.textContent = t[node.dataset.t];
  for (const node of root.querySelectorAll('[data-t-label]')) node.setAttribute('aria-label', t[node.dataset.tLabel]);
}

const STATE_TEXT = {
  loading: ['shareLoading', null, 'wait'],
  connecting: ['shareConnecting', null, 'wait'],
  expired: ['shareExpired', 'shareExpiredBody', 'bad'],
  revoked: ['shareRevoked', 'shareRevokedBody', 'bad'],
  used: ['shareUsed', 'shareUsedBody', 'bad'],
  host_offline: ['shareHostOffline', 'shareHostOfflineBody', 'bad'],
  not_found: ['shareNotFound', 'shareNotFoundBody', 'bad'],
  ended: ['shareEnded', 'shareEndedBody', 'bad'],
  error: ['shareError', 'shareErrorBody', 'bad'],
};
const RETRYABLE = new Set(['host_offline', 'ended', 'error']);

function browserLabel() {
  const ua = navigator.userAgent;
  const browser = /Edg\//.test(ua) ? 'Edge' : /Firefox\//.test(ua) ? 'Firefox' : /CriOS|Chrome\//.test(ua) ? 'Chrome'
    : /Safari\//.test(ua) ? 'Safari' : 'Browser';
  const device = /iPhone/.test(ua) ? 'iPhone' : /iPad/.test(ua) ? 'iPad' : /Android/.test(ua) ? 'Android'
    : /Mac OS X/.test(ua) ? 'Mac' : /Windows/.test(ua) ? 'Windows' : /Linux/.test(ua) ? 'Linux' : '';
  return (device ? `${browser} · ${device}` : browser).slice(0, 40);
}

let term = null;
let session = null;
let shownPane = null;
const coarse = matchMedia('(pointer: coarse)').matches;

function ensureTerminal(cols, rows) {
  if (term) return term;
  term = new Terminal({
    cols: Math.max(2, cols || 80),
    rows: Math.max(1, rows || 24),
    disableStdin: true,
    cursorBlink: false,
    scrollback: 5000,
    fontFamily: '"JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
    fontSize: coarse ? 12 : 13,
    theme: {
      background: '#0b0716',
      foreground: '#cdc7e0',
      cursor: '#60a5fa',
      cursorAccent: '#0b0716',
      selectionBackground: 'rgba(96, 165, 250, 0.35)',
    },
  });
  // The page owns typing (input.mjs); xterm only renders.
  term.attachCustomKeyEventHandler(() => false);
  term.open(el.term);
  return term;
}

function resizeTo(cols, rows) {
  if (term && cols > 0 && rows > 0 && (term.cols !== cols || term.rows !== rows)) term.resize(cols, rows);
}

function showStatus(state) {
  const [titleKey, bodyKey, tone] = STATE_TEXT[state] ?? STATE_TEXT.error;
  root.dataset.state = state;
  root.dataset.tone = tone;
  el.statusTitle.textContent = t[titleKey];
  el.statusBody.textContent = bodyKey ? t[bodyKey] : '';
  el.retry.hidden = !RETRYABLE.has(state);
  el.status.hidden = state === 'live';
  if (state !== 'live') {
    el.keys.hidden = true;
    el.input.blur();
  }
  if (tone === 'bad') {
    el.stage.hidden = true;
    el.panes.hidden = true;
    el.perm.hidden = true;
    el.expiry.hidden = true;
  }
}

function renderPanes(panes, active) {
  el.panes.replaceChildren(...panes.map((p) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.dataset.pane = p.id;
    b.setAttribute('aria-pressed', String(p.id === active));
    const name = document.createElement('span');
    name.textContent = p.title || p.id;
    b.append(name);
    if (p.kind !== 'terminal') {
      const kind = document.createElement('span');
      kind.className = 'kind';
      kind.textContent = p.kind;
      b.append(kind);
    }
    return b;
  }));
  el.panes.hidden = panes.length < 2;
}

function showPane(paneId) {
  const pane = session.panes.find((p) => p.id === paneId);
  const isTerminal = !pane || pane.kind === 'terminal';
  if (shownPane !== paneId && term) term.reset();
  shownPane = paneId;
  el.termScroll.hidden = !isTerminal;
  el.placeholder.hidden = isTerminal;
  if (!isTerminal) el.placeholder.textContent = pane.kind === 'browser' ? t.shareBrowserPane : t.shareAgentPane;
  if (isTerminal && pane) resizeTo(pane.cols, pane.rows);
  el.keys.hidden = !(session.canType && coarse && isTerminal);
  for (const b of el.panes.querySelectorAll('button')) b.setAttribute('aria-pressed', String(b.dataset.pane === paneId));
}

function showMeta(perm, expiresAt) {
  el.perm.hidden = false;
  el.perm.dataset.permKind = perm;
  el.perm.textContent = perm === 'type' ? t.sharePermType : t.sharePermView;
  if (expiresAt) {
    const time = new Date(expiresAt * 1000).toLocaleTimeString(lang, { hour: '2-digit', minute: '2-digit' });
    el.expiry.textContent = t.shareExpiresAt.replace('{time}', time);
    el.expiry.hidden = false;
  } else {
    el.expiry.hidden = true;
  }
}

// ----- typing -----
const input = createInput({ onData: (bytes) => session?.input(bytes) });

function forward(ev) {
  if (!session?.canType) return;
  const event = ev.type === 'paste' ? { type: 'paste', text: ev.clipboardData?.getData('text/plain') ?? '' } : ev;
  if (input.handle(event)) ev.preventDefault();
  if (ev.type === 'input' && !input.composing && !ev.isComposing) el.input.value = '';
  if (ev.type === 'compositionend') setTimeout(() => { if (!input.composing) el.input.value = ''; }, 0);
}
for (const type of ['keydown', 'input', 'compositionstart', 'compositionupdate', 'compositionend', 'paste']) {
  el.input.addEventListener(type, forward);
}
el.termScroll.addEventListener('click', () => {
  if (session?.canType && !window.getSelection()?.toString()) el.input.focus({ preventScroll: true });
});
el.keys.addEventListener('pointerdown', (ev) => {
  const button = ev.target.closest('button[data-key]');
  if (!button) return;
  ev.preventDefault(); // keep the phone keyboard open on the hidden textarea
  if (button.dataset.key === 'Ctrl') {
    button.setAttribute('aria-pressed', String(input.toggleCtrl()));
  } else {
    input.press(button.dataset.key);
    el.keys.querySelector('[data-key="Ctrl"]').setAttribute('aria-pressed', String(input.ctrlArmed));
  }
  el.input.focus({ preventScroll: true });
});
el.input.addEventListener('input', () => {
  el.keys.querySelector('[data-key="Ctrl"]').setAttribute('aria-pressed', String(input.ctrlArmed));
});

el.panes.addEventListener('click', (ev) => {
  const button = ev.target.closest('button[data-pane]');
  if (!button || !session) return;
  session.select(button.dataset.pane);
  showPane(button.dataset.pane);
});

// ----- session -----
async function fontsReady() {
  try {
    await Promise.race([document.fonts.load('13px "JetBrains Mono"'), new Promise((r) => setTimeout(r, 1500))]);
  } catch {
    // Fallback monospace metrics are fine.
  }
}

function connect() {
  session?.close();
  shownPane = null;
  const s = createSession({
    id: link.id,
    secret: link.secret,
    fetch: (...args) => fetch(...args),
    WebSocket,
    storage: (() => {
      try {
        return window.sessionStorage;
      } catch {
        return null;
      }
    })(),
    apiBase: root.dataset.apiBase,
    label: browserLabel(),
  });
  session = s;
  const mine = (fn) => (value) => { if (session === s) fn(value); };
  s.on('state', mine(({ state }) => showStatus(state)));
  s.on('welcome', mine(({ perm, panes, active, expiresAt }) => {
    const pane = panes.find((p) => p.id === active);
    ensureTerminal(pane?.cols, pane?.rows);
    el.stage.hidden = false;
    showMeta(perm, expiresAt);
    renderPanes(panes, active);
    showPane(active);
  }));
  s.on('panes', mine(({ panes, active }) => {
    renderPanes(panes, active);
    showPane(active);
  }));
  s.on('replay', mine(({ pane, cols, rows, data }) => {
    if (pane !== s.active || !term) return;
    term.reset();
    resizeTo(cols, rows);
    term.write(data);
  }));
  s.on('out', mine(({ pane, data }) => {
    if (pane === s.active && term) term.write(data);
  }));
  s.on('size', mine(({ pane, cols, rows }) => {
    if (pane === s.active) resizeTo(cols, rows);
  }));
  showStatus('loading');
  s.start();
}

el.retry.addEventListener('click', connect);
// A phone that slept dropped its sockets; reconnect once it is visible again (same viewer id).
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && session && ['ended', 'error'].includes(session.state)) connect();
});

applyLanguage();
// xterm measures the cell size when it opens; let the self-hosted mono font load first.
fontsReady().then(connect);
