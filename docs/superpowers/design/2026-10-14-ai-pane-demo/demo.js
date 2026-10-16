/* ShellX · Pane AI — demo engine.
 *
 * Plays ShellX's side of an AI pane: it renders the pane from the ACP v1
 * messages that the scripted agent in demo-data.js sends, keeps a fake
 * project "on disk", checkpoints it before every turn and logs every message.
 * No dependencies; a classic script so index.html also works from file://.
 */
(function () {
  'use strict';

  const DATA = window.SHELLX_DEMO;
  const root = document.getElementById('demo-root');
  if (!DATA || !root) return;

  /* ------------------------------------------------------------ helpers -- */

  const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ESC[c]);
  const clip = (s, n) => (s.length > n ? s.slice(0, n - 1) + '…' : s);
  const total = (xs) => xs.reduce((a, b) => a + b, 0);
  const two = (n) => String(n).padStart(2, '0');

  function h(tag, attrs, ...kids) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v == null || v === false) continue;
      if (k === 'class') el.className = v;
      else if (k === 'html') el.innerHTML = v;
      else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
      else el.setAttribute(k, v === true ? '' : v);
    }
    for (const kid of kids.flat()) if (kid != null && kid !== false) el.append(kid);
    return el;
  }

  const ICON = {
    spark: '<path class="f" d="M8 1.2l1.7 4.6 4.6 1.7-4.6 1.7L8 13.8l-1.7-4.6L1.7 7.5l4.6-1.7z"/>',
    file: '<path d="M4 1.5h5l3 3v10H4z"/><path d="M9 1.5v3h3"/>',
    search: '<circle cx="7" cy="7" r="4.5"/><path d="M10.4 10.4 14 14"/>',
    edit: '<path d="M10.8 2.7l2.5 2.5-7.6 7.6-3.2.7.7-3.2z"/>',
    term: '<rect x="1.5" y="2.5" width="13" height="11" rx="1.5"/><path d="M4.5 6l2 2-2 2M8.5 10.5h3"/>',
    think: '<path d="M4 12.5c-1.6-.9-2.5-2.5-2.5-4.3C1.5 5 4.4 2.5 8 2.5s6.5 2.5 6.5 5.7-2.9 5.8-6.5 5.8c-.7 0-1.4-.1-2-.3L3 14.5z"/>',
    globe: '<circle cx="8" cy="8" r="6.5"/><path d="M1.5 8h13M8 1.5c2.2 2.2 2.2 10.8 0 13M8 1.5c-2.2 2.2-2.2 10.8 0 13"/>',
    trash: '<path d="M2.5 4h11M6 4V2.5h4V4M3.8 4l.8 10h6.8l.8-10"/>',
    move: '<path d="M2 5.5h10.5l-2.5-2.5M14 10.5H3.5L6 13"/>',
    puzzle: '<path d="M3 4.5h2.6a1.6 1.6 0 1 1 3.2 0h2.7v2.7a1.6 1.6 0 1 1 0 3.2v2.6H3z"/>',
    check: '<path d="M3 8.5l3 3 7-7"/>',
    x: '<path d="M4 4l8 8M12 4l-8 8"/>',
    warn: '<path d="M8 1.8l6.6 11.7H1.4z"/><path d="M8 6.3v3.4M8 11.6v.1"/>',
    dot: '<circle class="f" cx="8" cy="8" r="4"/>',
    ring: '<circle cx="8" cy="8" r="3.8"/>',
    chev: '<path d="M4 6l4 4 4-4"/>',
    plus: '<path d="M8 3v10M3 8h10"/>',
    history: '<path d="M2.2 8a5.8 5.8 0 1 0 1.7-4.1"/><path d="M2 2.5v2.8h2.8M8 5v3.2l2.2 1.3"/>',
    panel: '<rect x="1.5" y="2.5" width="13" height="11" rx="1.5"/><path d="M10 2.5v11"/>',
    max: '<path d="M9.5 2.5h4v4M6.5 13.5h-4v-4M13.5 2.5 9.2 6.8M2.5 13.5l4.3-4.3"/>',
    more: '<circle class="f" cx="3.5" cy="8" r="1.1"/><circle class="f" cx="8" cy="8" r="1.1"/><circle class="f" cx="12.5" cy="8" r="1.1"/>',
    folder: '<path d="M1.5 4v8.5h13V5.5H7.8L6.3 4z"/>',
    undo: '<path d="M5.5 3.5 2.5 6.5l3 3"/><path d="M2.5 6.5H10a3.5 3.5 0 0 1 0 7H7"/>',
    at: '<circle cx="8" cy="8" r="2.6"/><path d="M10.6 8v1.1a1.9 1.9 0 0 0 3.8 0V8A6.4 6.4 0 1 0 12 13"/>',
    slash: '<path d="M10.5 2.5l-5 11"/>',
    image: '<rect x="1.5" y="2.5" width="13" height="11" rx="1.5"/><circle cx="5.5" cy="6.3" r="1.2"/><path d="M14.5 11 11 7.5 4 13.5"/>',
    ext: '<path d="M9 2.5h4.5V7M13.5 2.5 7.5 8.5M12 9.5v4H2.5V4h4"/>',
    send: '<path d="M8 13V3.5M4 7.5l4-4 4 4"/>',
    stop: '<rect class="f" x="4" y="4" width="8" height="8" rx="1.5"/>',
    restart: '<path d="M2.5 8a5.5 5.5 0 1 0 1.6-3.9"/><path d="M2.2 2.4v3.1h3.1"/>',
    pause: '<path d="M5.5 3.5v9M10.5 3.5v9"/>',
    play: '<path class="f" d="M5 3.2v9.6L12.5 8z"/>',
    step: '<path class="f" d="M3.5 3.5v9l6-4.5z"/><path d="M12 3.5v9"/>',
    bell: '<path d="M4 11.2V7.3a4 4 0 0 1 8 0v3.9l1.4 1.4H2.6zM6.5 14.3h3"/>',
    gear: '<path d="M2 4.5h7M12.5 4.5H14M2 11.5h1.5M7 11.5h7"/><circle cx="10.7" cy="4.5" r="1.7"/><circle cx="5.2" cy="11.5" r="1.7"/>',
    key: '<circle cx="5.5" cy="10.5" r="3"/><path d="M7.7 8.3 13.5 2.5M11 5l1.8 1.8"/>',
    phone: '<rect x="4.5" y="1.5" width="7" height="13" rx="1.6"/><path d="M7 12.3h2"/>',
    lock: '<rect x="3" y="7" width="10" height="7.5" rx="1.5"/><path d="M5.5 7V5a2.5 2.5 0 0 1 5 0v2"/>',
  };
  const svg = (name, cls) =>
    `<svg class="ic${cls ? ' ' + cls : ''}" viewBox="0 0 16 16" aria-hidden="true">${ICON[name] || ''}</svg>`;

  const fmtClock = (ms) => {
    const t = Math.max(0, ms) / 1000;
    return `${two(Math.floor(t / 60))}:${two(Math.floor(t % 60))}.${Math.floor((t * 10) % 10)}`;
  };
  const fmtDur = (ms) => {
    const s = Math.max(0, Math.round(ms / 1000));
    return `${Math.floor(s / 60)}:${two(s % 60)}`;
  };
  const fmtSec = (ms) => `${(Math.max(0, ms) / 1000).toFixed(1).replace('.', ',')} s`;

  const rel = (p) => (p && p.startsWith(DATA.cwd + '/') ? p.slice(DATA.cwd.length + 1) : p);
  const abs = (p) => `${DATA.cwd}/${p}`;
  const langOf = (p) =>
    /\.(ts|tsx|js|mjs)$/.test(p) ? 'ts' : /\.json$/.test(p) ? 'json' : /\.(sh|zsh)$/.test(p) ? 'sh' : 'txt';
  const mimeOf = (p) =>
    /\.tsx?$/.test(p) ? 'text/x-typescript' : /\.json$/.test(p) ? 'application/json' : 'text/plain';

  /* --------------------------------------------------------- text tools -- */

  function lines(s) {
    if (!s) return [];
    const out = s.split('\n');
    if (out[out.length - 1] === '') out.pop();
    return out;
  }

  /** Line diff (LCS); ops carry 1-based old (a) / new (b) line numbers. */
  function diffLines(oldText, newText) {
    const A = lines(oldText);
    const B = lines(newText);
    const n = A.length;
    const m = B.length;
    const dp = Array.from({ length: n + 1 }, () => new Int32Array(m + 1));
    for (let i = n - 1; i >= 0; i--) {
      for (let j = m - 1; j >= 0; j--) {
        dp[i][j] = A[i] === B[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
      }
    }
    const ops = [];
    let i = 0;
    let j = 0;
    while (i < n && j < m) {
      if (A[i] === B[j]) ops.push({ t: ' ', a: ++i, b: ++j, s: A[i - 1] });
      else if (dp[i + 1][j] >= dp[i][j + 1]) ops.push({ t: '-', a: ++i, s: A[i - 1] });
      else ops.push({ t: '+', b: ++j, s: B[j - 1] });
    }
    while (i < n) ops.push({ t: '-', a: ++i, s: A[i - 1] });
    while (j < m) ops.push({ t: '+', b: ++j, s: B[j - 1] });
    return ops;
  }

  function diffStat(oldText, newText) {
    const ops = diffLines(oldText || '', newText || '');
    return { add: ops.filter((o) => o.t === '+').length, del: ops.filter((o) => o.t === '-').length };
  }

  function hunks(ops, ctx) {
    const keep = ops.map(() => false);
    ops.forEach((o, i) => {
      if (o.t === ' ') return;
      for (let k = Math.max(0, i - ctx); k <= Math.min(ops.length - 1, i + ctx); k++) keep[k] = true;
    });
    const out = [];
    let cur = null;
    let skipped = 0;
    ops.forEach((o, i) => {
      if (!keep[i]) {
        cur = null;
        skipped++;
        return;
      }
      if (!cur) {
        cur = { skipped, lines: [] };
        out.push(cur);
        skipped = 0;
      }
      cur.lines.push(o);
    });
    return { list: out, tail: skipped };
  }

  function diffHtml(oldText, newText, lang) {
    const { list, tail } = hunks(diffLines(oldText || '', newText || ''), 3);
    let html = '<div class="df">';
    for (const hk of list) {
      if (hk.skipped) html += `<div class="df-gap">⋯ ${hk.skipped} dòng không đổi</div>`;
      for (const o of hk.lines) {
        const cls = o.t === '+' ? 'add' : o.t === '-' ? 'del' : 'ctx';
        const mark = o.t === '+' ? '+' : o.t === '-' ? '−' : '';
        html += `<div class="df-l df-${cls}"><span class="df-n">${o.a || ''}</span><span class="df-n">${o.b || ''}</span><span class="df-m">${mark}</span><code>${hl(o.s, lang) || ' '}</code></div>`;
      }
    }
    if (tail && list.length) html += `<div class="df-gap">⋯ ${tail} dòng không đổi</div>`;
    if (!list.length) html += '<div class="df-gap">Không có khác biệt</div>';
    return html + '</div>';
  }

  function tokenize(line, re, wrap) {
    let out = '';
    let last = 0;
    let m;
    re.lastIndex = 0;
    while ((m = re.exec(line))) {
      out += esc(line.slice(last, m.index)) + wrap(m);
      last = m.index + m[0].length;
      if (!m[0].length) re.lastIndex++;
    }
    return out + esc(line.slice(last));
  }
  const span = (cls, s) => `<span class="${cls}">${esc(s)}</span>`;
  const KW = new Set(
    'import from export default const let var function async await return if else try catch finally throw new type interface extends implements class for of in while switch case break continue typeof instanceof void null undefined true false this as'.split(' '),
  );
  const TESTFN = new Set('describe it test expect vi beforeEach afterEach'.split(' '));
  const RE_TS = /(\/\/.*$)|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`)|(\b\d[\d_]*(?:\.\d+)?\b)|([A-Za-z_$][\w$]*)/g;
  const RE_JSON = /("(?:[^"\\]|\\.)*")(\s*:)?|\b(true|false|null)\b|(-?\b\d+(?:\.\d+)?\b)/g;
  const RE_SH = /(#.*$)|("(?:[^"\\]|\\.)*"|'[^']*')|((?:^|\s)--?[\w-]+)/g;

  function hl(line, lang) {
    if (!line) return '';
    if (lang === 'ts') {
      return tokenize(line, RE_TS, (m) => {
        if (m[1]) return span('tk-c', m[1]);
        if (m[2]) return span('tk-s', m[2]);
        if (m[3]) return span('tk-n', m[3]);
        const w = m[4];
        if (KW.has(w)) return span('tk-k', w);
        if (TESTFN.has(w)) return span('tk-f', w);
        if (/^[A-Z]/.test(w)) return span('tk-t', w);
        return esc(w);
      });
    }
    if (lang === 'json') {
      return tokenize(line, RE_JSON, (m) => {
        if (m[1]) return m[2] ? span('tk-p', m[1]) + esc(m[2]) : span('tk-s', m[1]);
        if (m[3]) return span('tk-k', m[3]);
        return span('tk-n', m[4]);
      });
    }
    if (lang === 'sh') {
      return tokenize(line, RE_SH, (m) => {
        if (m[1]) return span('tk-c', m[1]);
        if (m[2]) return span('tk-s', m[2]);
        return span('tk-k', m[3]);
      });
    }
    return esc(line);
  }

  const inline = (s) =>
    esc(s)
      .replace(/`([^`]+)`/g, '<code>$1</code>')
      .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>');

  /** Small Markdown: paragraphs, "- " lists, ``` fences, `code`, **bold**. */
  function md(src) {
    let html = '';
    let para = [];
    let list = null;
    let code = null;
    let lang = '';
    const flushPara = () => {
      if (para.length) html += `<p>${inline(para.join(' '))}</p>`;
      para = [];
    };
    const flushList = () => {
      if (list) html += `<ul>${list.map((li) => `<li>${inline(li)}</li>`).join('')}</ul>`;
      list = null;
    };
    const flushCode = () => {
      html += `<pre class="md-code"><code>${code.map((l) => hl(l, lang)).join('\n')}</code></pre>`;
      code = null;
    };
    for (const ln of src.split('\n')) {
      if (ln.startsWith('```')) {
        if (code) flushCode();
        else {
          flushPara();
          flushList();
          code = [];
          lang = ln.slice(3).trim() || 'txt';
        }
        continue;
      }
      if (code) {
        code.push(ln);
        continue;
      }
      if (/^\s*[-*] /.test(ln)) {
        flushPara();
        (list = list || []).push(ln.replace(/^\s*[-*] /, ''));
        continue;
      }
      if (!ln.trim()) {
        flushPara();
        flushList();
        continue;
      }
      flushList();
      para.push(ln);
    }
    if (code) flushCode();
    flushPara();
    flushList();
    return html;
  }

  function trunc(v, n) {
    if (typeof v === 'string') return v.length > n ? v.slice(0, n) + '… (rút gọn)' : v;
    if (Array.isArray(v)) return v.map((x) => trunc(x, n));
    if (v && typeof v === 'object') {
      const o = {};
      for (const [k, x] of Object.entries(v)) o[k] = trunc(x, n);
      return o;
    }
    return v;
  }

  function jsonHtml(v) {
    return tokenize(JSON.stringify(trunc(v, 360), null, 2), RE_JSON, (m) => {
      if (m[1]) return m[2] ? span('j-k', m[1]) + esc(m[2]) : span('j-s', m[1]);
      if (m[3]) return span('j-l', m[3]);
      return span('j-n', m[4]);
    }).replace(/\n/g, '<br>');
  }

  /* -------------------------------------------------------------- state -- */

  class Stop extends Error {}
  class Cancelled extends Error {}
  class Crash extends Error {
    constructor(code, stderr) {
      super('agent exited');
      this.code = code;
      this.stderr = stderr;
    }
  }

  const MODE_VI = {
    default: ['Hỏi trước', 'Hỏi bạn trước mỗi lần sửa tệp hay chạy lệnh'],
    acceptEdits: ['Tự sửa tệp', 'Sửa tệp không hỏi; vẫn hỏi khi chạy lệnh'],
    plan: ['Lập kế hoạch', 'Chỉ đọc và lập kế hoạch, chưa sửa gì'],
    auto: ['Tự động', 'Claude tự quyết khi nào cần hỏi'],
    bypassPermissions: ['Bỏ qua mọi quyền', 'Không hỏi gì cả — chỉ dùng ở nơi chấp nhận rủi ro'],
  };
  const KIND_VI = {
    allow_once: 'Cho phép',
    allow_always: 'Luôn cho phép',
    reject_once: 'Từ chối',
    reject_always: 'Luôn từ chối',
  };
  const KIND_ICON = {
    read: 'file',
    edit: 'edit',
    delete: 'trash',
    move: 'move',
    search: 'search',
    execute: 'term',
    think: 'think',
    fetch: 'globe',
    switch_mode: 'gear',
    other: 'puzzle',
  };

  const R = { token: 0, paused: false, stepOnce: false, speed: 1, timers: [], waits: new Map() };
  const A = { granted: new Set() };
  let S = null;
  let W = {};
  let current = DATA.scenarios[0].id;
  let started = false;
  let visible = false;

  function freshState() {
    return {
      clock: 0,
      beat: 0,
      agentName: 'Claude',
      aiTab: true,
      selectedTab: 'ai',
      title: 'Phiên AI mới',
      // An AI tab has no terminal unless you ask for one (header button).
      layout: { tool: false, term: false, zoom: false, side: true },
      focus: 'ai',
      process: null,
      sessionId: null,
      ready: false,
      readyHint: 'Đang khởi động agent…',
      cfg: { mode: 'default', model: 'default', effort: 'medium' },
      configOptions: [],
      commands: [],
      usage: null,
      status: 'none',
      turn: null,
      turnCount: 0,
      plan: null,
      planOpen: true,
      perm: null,
      queue: [],
      tools: new Map(),
      block: null,
      history: [],
      fs: Object.assign({}, DATA.files),
      ckpts: [],
      reviewed: new Set(),
      sideTab: 'changes',
      scope: 'session',
      sheet: null,
      attachments: [],
      term: DATA.term.ai.slice(),
      // The sample tool's server state: desktop and phone views read the same.
      board: null,
      toolReg: [],
      toolOpen: null,
      runSheet: null,
      phone: { on: false, screen: 'list', attached: false, draft: '', tool: null },
      mirror: [],
      offline: false,
      empty: null,
      agents: JSON.parse(JSON.stringify(DATA.agents)),
      idOut: 0,
      idIn: 0,
      hashes: DATA.hashes.slice(),
      log: [],
      logFilter: { acp: true, hood: true, relay: true },
      stick: true,
      dialogDone: null,
      menu: null,
      pop: null,
    };
  }

  /* ------------------------------------------------------------ runner -- */

  function wait(ms) {
    const token = R.token;
    const turn = S.turn;
    return new Promise((resolve, reject) => {
      if (turn && turn.cancelled) return reject(new Cancelled());
      R.timers.push({ at: S.clock + ms, token, turn, resolve, reject });
    });
  }

  function waitUser(key) {
    const turn = S.turn;
    return new Promise((resolve, reject) => {
      const old = R.waits.get(key);
      if (old) old.reject(new Stop());
      R.waits.set(key, { resolve, reject, turn });
    });
  }

  function fire(key, value) {
    const w = R.waits.get(key);
    if (!w) return false;
    R.waits.delete(key);
    w.resolve(value);
    return true;
  }

  function runDetached(fn) {
    fn().catch((e) => {
      if (!(e instanceof Stop) && !(e instanceof Cancelled)) console.error(e);
    });
  }

  let lastTick = performance.now();
  setInterval(() => {
    const now = performance.now();
    const dt = Math.min(now - lastTick, 250);
    lastTick = now;
    if (!started || !S || R.paused) return;
    S.clock += dt * R.speed;
    const due = R.timers.filter((t) => t.at <= S.clock);
    if (due.length) {
      R.timers = R.timers.filter((t) => t.at > S.clock);
      for (const t of due) {
        if (t.token !== R.token) t.reject(new Stop());
        else if (t.turn && t.turn.cancelled) t.reject(new Cancelled());
        else t.resolve();
      }
    }
    tickUI();
  }, 40);

  function tickUI() {
    if (S.turn && S.status === 'running') renderStatus();
    for (const el of W.conv.querySelectorAll('[data-tt]')) {
      const t = S.tools.get(el.dataset.tt);
      if (t && t.status === 'in_progress') el.textContent = fmtSec(S.clock - t.started);
    }
  }

  function beat(text, actions) {
    S.beat++;
    coach(text, actions);
    if (R.stepOnce) {
      R.stepOnce = false;
      R.paused = true;
      renderControls();
    }
  }

  function coach(text, actions) {
    W.coachN.textContent = S.beat;
    W.coachT.innerHTML = inline(text);
    W.coachA.innerHTML = '';
    for (const a of actions || []) {
      W.coachA.append(
        h(
          'button',
          {
            class: 'dm-btn' + (a.primary ? ' pri' : ''),
            onclick: () => {
              unpause();
              fire(a.key, a.value);
            },
          },
          a.label,
        ),
      );
    }
  }

  function unpause() {
    if (R.paused) {
      R.paused = false;
      renderControls();
    }
  }

  /* --------------------------------------------------------------- log -- */

  const TAGS = {
    'tiến trình': 'proc',
    'điểm khôi phục': 'ckpt',
    'trạng thái': 'state',
    'thông báo': 'notif',
    'khôi phục': 'restore',
    plugin: 'plugin',
    tệp: 'file',
  };

  function logPush(e) {
    e.at = S.clock;
    e.i = S.log.length;
    const last = S.log[S.log.length - 1];
    if (e.chunk && last && last.chunk === e.chunk && last.dir === e.dir) {
      last.count++;
      last.text += e.text;
      renderLogRow(last, false);
      return;
    }
    e.count = 1;
    S.log.push(e);
    renderLogRow(e, true);
  }

  function renderLogRow(e, isNew) {
    if (!e.el) {
      e.el = h('div');
      W.logList.append(e.el);
    }
    e.el.className = `lg lg-${e.lane}${e.dir ? ' lg-' + e.dir : ''}${e.err ? ' lg-err' : ''}${e.open ? ' is-open' : ''}`;
    let head;
    if (e.lane === 'hood') {
      head = `<span class="lg-d">•</span><span class="lg-tag tag-${TAGS[e.tag] || 'file'}">${esc(e.tag)}</span>`;
    } else if (e.lane === 'relay') {
      head = `<span class="lg-d">${e.dir === 'down' ? '⇢' : '⇠'}</span><span class="lg-m">${esc(e.method)} <i>${e.dir === 'down' ? 'desktop → điện thoại' : 'điện thoại → desktop'}</i></span>`;
    } else {
      const id = e.id != null ? ` <i>#${e.id}</i>` : '';
      const kind = e.kind === 'res' ? ' <i>trả lời</i>' : e.kind === 'err' ? ' <i>lỗi</i>' : '';
      const n = e.count > 1 ? ` <i>×${e.count}</i>` : '';
      // While a phone is attached, every session/update also goes out as ai.update.
      const fwd = e.fwd ? ' <i class="lg-fwd" title="Desktop chuyển tiếp sang điện thoại (ai.update, đề xuất)">⇢ điện thoại</i>' : '';
      head = `<span class="lg-d">${e.dir === 'out' ? '→' : '←'}</span><span class="lg-m">${esc(e.method)}${id}${kind}${e.sub ? ` <em>${esc(e.sub)}</em>` : ''}${n}${fwd}</span>`;
    }
    const sum = e.count > 1 ? `“${clip(e.text.replace(/\s+/g, ' '), 80)}”` : e.sum || '';
    e.el.innerHTML =
      `<button class="lg-r" data-log="${e.i}"><span class="lg-t">${fmtClock(e.at)}</span>${head}<span class="lg-s">${inline(sum)}</span></button>` +
      (e.open ? `<div class="lg-x">${logDetail(e)}</div>` : '');
    if (isNew) {
      const L = W.logList;
      if (L.scrollHeight - L.scrollTop - L.clientHeight < 80 || e.i < 3) L.scrollTop = L.scrollHeight;
    }
  }

  function logDetail(e) {
    if (e.lane === 'hood') return e.detail ? `<pre class="hd">${esc(e.detail)}</pre>` : '<p class="lg-note">Không có chi tiết.</p>';
    let html = `<pre class="j">${jsonHtml(e.json)}</pre>`;
    if (e.count > 1) {
      html += `<p class="lg-note">+${e.count - 1} thông điệp cùng loại (mỗi thông điệp một đoạn). Ghép lại:</p><p class="lg-text">${esc(e.text)}</p>`;
    }
    if (e.note) html += `<p class="lg-note">${inline(e.note)}</p>`;
    return html;
  }

  function hood(tag, text, detail) {
    logPush({ lane: 'hood', tag, sum: text, detail });
  }

  function out(method, params, sum, note) {
    const id = ++S.idOut;
    logPush({ lane: 'acp', dir: 'out', kind: 'req', method, id, sum, note, json: { jsonrpc: '2.0', id, method, params } });
    return id;
  }
  function outNote(method, params, sum) {
    logPush({ lane: 'acp', dir: 'out', kind: 'note', method, sum, json: { jsonrpc: '2.0', method, params } });
  }
  function outRes(id, method, result, sum) {
    logPush({ lane: 'acp', dir: 'out', kind: 'res', method, id, sum, json: { jsonrpc: '2.0', id, result } });
  }
  function inReq(method, params, sum) {
    const id = S.idIn++;
    logPush({ lane: 'acp', dir: 'in', kind: 'req', method, id, sum, json: { jsonrpc: '2.0', id, method, params } });
    return id;
  }
  function inRes(id, method, result, sum, note) {
    logPush({ lane: 'acp', dir: 'in', kind: 'res', method, id, sum, note, json: { jsonrpc: '2.0', id, result } });
  }
  function inErr(id, method, error, sum) {
    logPush({ lane: 'acp', dir: 'in', kind: 'err', err: true, method, id, sum, json: { jsonrpc: '2.0', id, error } });
  }

  function updateSummary(u) {
    switch (u.sessionUpdate) {
      case 'agent_message_chunk':
      case 'agent_thought_chunk':
      case 'user_message_chunk':
        return `“${clip(u.content.text.replace(/\s+/g, ' '), 70)}”`;
      case 'tool_call':
        return `${u.kind || 'other'} · ${u.title} · ${u.status || 'pending'}`;
      case 'tool_call_update':
        return `…${u.toolCallId.slice(-4)} → ${u.status || 'cập nhật'}${u.content ? ' · ' + u.content.map((c) => c.type).join(', ') : ''}`;
      case 'plan':
        return `${u.entries.length} mục · ${u.entries.filter((x) => x.status === 'completed').length} xong`;
      case 'available_commands_update':
        return u.availableCommands.map((c) => '/' + c.name).join(' ');
      case 'config_option_update':
        return 'tuỳ chọn mới';
      case 'usage_update':
        return `${u.used.toLocaleString('vi-VN')} / ${u.size.toLocaleString('vi-VN')} token`;
      case 'session_info_update':
        return u.title ? `tiêu đề “${u.title}”` : 'thông tin phiên';
      default:
        return '';
    }
  }

  /** An agent → ShellX `session/update`: logged, then rendered. */
  function update(u, sum) {
    const chunk = /_chunk$/.test(u.sessionUpdate) ? u.sessionUpdate : null;
    logPush({
      lane: 'acp',
      dir: 'in',
      kind: 'note',
      method: 'session/update',
      sub: u.sessionUpdate,
      chunk,
      text: chunk ? u.content.text : '',
      sum: sum || updateSummary(u),
      fwd: S.phone.attached,
      json: { jsonrpc: '2.0', method: 'session/update', params: { sessionId: S.sessionId, update: u } },
    });
    applyUpdate(u, false);
    if (S.phone.on) renderPhone();
  }

  /* --------------------------------------------------------- build DOM -- */

  function build() {
    root.innerHTML = `
<div class="dm">
  <div class="dm-bar">
    <div class="dm-scens" role="tablist" aria-label="Kịch bản">${DATA.scenarios
      .map(
        (s, i) =>
          `<button role="tab" data-scen="${s.id}"><b>${i + 1}</b>${esc(s.name)}${s.phase ? `<span class="tag">${esc(s.phase)}</span>` : ''}</button>`,
      )
      .join('')}</div>
    <div class="dm-ctl">
      <button class="dm-btn" data-ctl="restart" title="Chạy lại kịch bản từ đầu">${svg('restart')}Làm lại</button>
      <button class="dm-btn" data-ctl="pause">${svg('pause')}<span>Tạm dừng</span></button>
      <button class="dm-btn" data-ctl="step" title="Chạy tới bước kế tiếp rồi dừng">${svg('step')}Bước tiếp</button>
      <div class="dm-seg" role="group" aria-label="Tốc độ">
        <button data-speed="1">1×</button><button data-speed="2">2×</button><button data-speed="4">4×</button>
      </div>
    </div>
  </div>
  <div class="dm-coach" aria-live="polite"><span class="dm-coach-n">0</span><div class="dm-coach-t">Demo tự chạy khi cửa sổ bên dưới hiện trên màn hình — hoặc chọn một kịch bản ở trên.</div><div class="dm-coach-a"></div></div>
  <div class="dm-stage">
    <div class="dm-winwrap">
      <div class="win" data-win>
        <div class="win-top">
          <div class="win-top-side"><i class="tl tl-r"></i><i class="tl tl-y"></i><i class="tl tl-g"></i></div>
          <div class="win-top-title"></div>
        </div>
        <div class="win-body">
          <nav class="sb" aria-label="Sidebar"></nav>
          <div class="panes">
            <div class="tab-ai">
              <div class="pane-row">
                <section class="pane ai" aria-label="Pane AI">
                  <header class="ai-h">
                    <span class="ai-agent"></span>
                    <span class="ai-title"></span>
                    <span class="ai-st"></span>
                    <span class="ai-tools">
                      <button class="ib" data-ai="history" title="Lịch sử phiên của dự án (session/list)">${svg('history')}</button>
                      <button class="ib" data-ai="side" title="Hiện/ẩn panel Thay đổi · Tệp">${svg('panel')}</button>
                      <button class="ib" data-ai="term" title="Hiện/ẩn terminal của tab (ẩn sẵn)">${svg('term')}</button>
                      <button class="ib" data-ai="zoom" title="Phóng to pane (toggle_split_zoom)">${svg('max')}</button>
                      <button class="ib" data-ai="more" title="Thêm">${svg('more')}</button>
                    </span>
                  </header>
                  <div class="ai-body">
                    <div class="ai-main">
                      <div class="ai-scroll"><div class="ai-conv"></div></div>
                      <div class="ai-dock">
                        <div class="ai-plan" hidden></div>
                        <div class="ai-perm" hidden></div>
                        <div class="ai-queue" hidden></div>
                        <div class="ai-comp">
                          <div class="ai-attach" hidden></div>
                          <textarea rows="2" spellcheck="false" aria-label="Tin nhắn cho agent"></textarea>
                          <div class="ai-pop" hidden></div>
                          <div class="ai-cf">
                            <button class="ib" data-cmp="at" title="Nhắc một tệp (@)">${svg('at')}</button>
                            <button class="ib" data-cmp="slash" title="Lệnh của agent (/)">${svg('slash')}</button>
                            <button class="ib" data-cmp="img" title="Đính ảnh (dán hoặc kéo thả)">${svg('image')}</button>
                            <span class="ai-cfg"></span>
                            <span class="ai-ctx"></span>
                            <button class="ai-send"></button>
                          </div>
                        </div>
                      </div>
                      <div class="ai-sheet" hidden></div>
                      <div class="ai-empty" hidden></div>
                      <div class="ai-run" hidden></div>
                    </div>
                    <aside class="ai-side" aria-label="Thay đổi và tệp">
                      <div class="side-tabs" role="tablist">
                        <button data-side="changes">Thay đổi <b class="cnt"></b></button>
                        <button data-side="files">Tệp</button>
                      </div>
                      <div class="side-body"></div>
                    </aside>
                  </div>
                </section>
                <section class="pane plg" aria-label="Pane tool" hidden></section>
              </div>
              <section class="pane term" aria-label="Terminal">
                <header class="pane-h">${svg('term')}<span class="term-title">zsh — ~/code/shop-web</span></header>
                <pre class="term-out"></pre>
              </section>
            </div>
            <div class="tab-other" hidden>
              <section class="pane term solo">
                <header class="pane-h">${svg('term')}<span class="other-title"></span></header>
                <pre class="term-out other-out"></pre>
              </section>
            </div>
          </div>
        </div>
        <div class="win-note" hidden></div>
        <div class="win-toast" hidden></div>
        <div class="win-menu" hidden></div>
        <div class="win-modal" hidden></div>
        <div class="win-off" hidden></div>
      </div>
    </div>
    <aside class="dm-phone" aria-label="Điện thoại" hidden></aside>
    <aside class="dm-log" aria-label="Nhật ký">
      <div class="dm-log-h">
        <strong>Nhật ký</strong>
        <span class="dm-log-f">
          <button data-lf="acp" aria-pressed="true"><i class="lg-dot acp"></i>ACP</button>
          <button data-lf="hood" aria-pressed="true"><i class="lg-dot hood"></i>ShellX</button>
          <button data-lf="relay" aria-pressed="true"><i class="lg-dot relay"></i>Điện thoại</button>
        </span>
      </div>
      <p class="dm-log-legend"><b>→</b> ShellX gửi agent · <b>←</b> agent gửi ShellX · <b>•</b> ShellX tự làm · <b>⇢ ⇠</b> desktop ↔ điện thoại (relay, mã hoá đầu cuối). Bấm một dòng để xem chi tiết.</p>
      <div class="dm-log-list"></div>
    </aside>
  </div>
</div>`;
    const q = (s) => root.querySelector(s);
    W = {
      coachN: q('.dm-coach-n'),
      coachT: q('.dm-coach-t'),
      coachA: q('.dm-coach-a'),
      win: q('[data-win]'),
      top: q('.win-top-title'),
      sb: q('.sb'),
      tabAi: q('.tab-ai'),
      tabOther: q('.tab-other'),
      otherTitle: q('.other-title'),
      otherOut: q('.other-out'),
      ai: q('.pane.ai'),
      aiAgent: q('.ai-agent'),
      aiTitle: q('.ai-title'),
      aiSt: q('.ai-st'),
      scroll: q('.ai-scroll'),
      conv: q('.ai-conv'),
      plan: q('.ai-plan'),
      perm: q('.ai-perm'),
      queue: q('.ai-queue'),
      attach: q('.ai-attach'),
      ta: q('.ai-comp textarea'),
      pop: q('.ai-pop'),
      cfg: q('.ai-cfg'),
      ctx: q('.ai-ctx'),
      send: q('.ai-send'),
      sheet: q('.ai-sheet'),
      empty: q('.ai-empty'),
      run: q('.ai-run'),
      side: q('.ai-side'),
      sideCnt: q('.side-tabs .cnt'),
      sideBody: q('.side-body'),
      plg: q('.pane.plg'),
      term: q('.pane.term:not(.solo)'),
      termOut: q('.pane.term:not(.solo) .term-out'),
      note: q('.win-note'),
      toast: q('.win-toast'),
      menu: q('.win-menu'),
      modal: q('.win-modal'),
      off: q('.win-off'),
      logList: q('.dm-log-list'),
      phone: q('.dm-phone'),
      stage: q('.dm-stage'),
    };
    bind();
  }

  /* ------------------------------------------------------------ render -- */

  function renderAll() {
    renderControls();
    renderTop();
    renderSidebar();
    renderPanes();
    renderHeader();
    renderPlan();
    renderPermBar();
    renderQueue();
    renderAttach();
    renderComposer();
    renderSide();
    renderSheet();
    renderTerm();
    renderToolView();
    renderRun();
    renderEmpty();
    renderOffline();
    renderPhone();
  }

  function renderControls() {
    for (const b of root.querySelectorAll('[data-scen]')) {
      b.setAttribute('aria-selected', String(b.dataset.scen === current));
    }
    const p = root.querySelector('[data-ctl="pause"]');
    p.innerHTML = R.paused ? `${svg('play')}<span>Chạy tiếp</span>` : `${svg('pause')}<span>Tạm dừng</span>`;
    for (const b of root.querySelectorAll('[data-speed]')) {
      b.setAttribute('aria-pressed', String(+b.dataset.speed === R.speed));
    }
    for (const b of root.querySelectorAll('[data-lf]')) {
      b.setAttribute('aria-pressed', String(S.logFilter[b.dataset.lf]));
    }
    W.logList.classList.toggle('no-acp', !S.logFilter.acp);
    W.logList.classList.toggle('no-hood', !S.logFilter.hood);
    W.logList.classList.toggle('no-relay', !S.logFilter.relay);
  }

  function renderTop() {
    const other = DATA.tabs[S.selectedTab];
    W.top.textContent = S.selectedTab === 'ai' ? S.title : other ? other.title : '';
  }

  function badge(state, agent) {
    const map = {
      running: ['dot', 'Đang chạy'],
      needsInput: ['warn', 'Cần bạn trả lời'],
      idle: ['ring', 'Đang chờ'],
      done: ['check', 'Xong'],
    };
    const b = map[state];
    if (!b) return '';
    return `<span class="bd bd-${state}">${svg(b[0])}${b[1]}<span class="bd-a"> · ${esc(agent)}</span></span>`;
  }

  function renderSidebar() {
    const row = (id, icon, title, line2, extra) =>
      `<button class="row${S.selectedTab === id ? ' sel' : ''}${extra || ''}" data-tab="${id}"><i class="row-bar"></i>${icon}<span class="row-tt"><span class="row-t">${esc(title)}</span>${line2 ? `<span class="row-2">${line2}</span>` : ''}</span></button>`;
    const aiRow = S.aiTab
      ? row('ai', `<span class="row-ic ai">${svg('spark')}</span>`, S.title, badge(S.status, S.agentName) || '<span class="muted">Pane AI</span>')
      : '';
    const tools = S.toolReg.length
      ? `<div class="ws-sub">Tool</div>` +
        S.toolReg
          .map(
            (t) =>
              `<button class="row row-tool${S.layout.tool && S.toolOpen === t.id ? ' on' : ''}" data-opentool="${t.id}" title="${esc(t.url)}"><i class="row-bar"></i><span class="row-ic tool">${svg('puzzle')}</span><span class="row-tt"><span class="row-t">${esc(t.name)}</span><span class="row-2">${esc(hostOf(t.url))}${t.phone ? ' · cả điện thoại' : ''}</span></span></button>`,
          )
          .join('')
      : '';
    W.sb.innerHTML = `
      <div class="sb-list">
        <div class="ws"><div class="ws-h"><span class="ws-n">shop-web</span><span class="ws-p">~/code/shop-web</span></div>
          ${aiRow}
          ${row('dev', '<i class="dot dot-run"></i>', DATA.tabs.dev.title, '<span class="muted">zsh · npm run dev</span>')}
          ${tools}
        </div>
        <div class="ws"><div class="ws-h"><span class="ws-n">shellx</span><span class="ws-p">~/code/shellx</span></div>
          ${row('cc', '<i class="dot"></i>', DATA.tabs.cc.title, badge('idle', 'Claude Code'))}
        </div>
      </div>
      <div class="sb-foot"><button class="sb-new" data-act="new-ai">${svg('plus')}Phiên AI mới</button><button class="sb-new" data-act="add-tool">${svg('puzzle')}Thêm tool</button></div>`;
  }

  const hostOf = (url) => url.replace(/^https?:\/\//, '').replace(/\/$/, '');

  function renderPanes() {
    const onAi = S.selectedTab === 'ai' && S.aiTab;
    W.tabAi.hidden = !onAi;
    W.tabOther.hidden = onAi;
    if (!onAi) {
      const tab = DATA.tabs[S.selectedTab] || DATA.tabs.dev;
      W.otherTitle.textContent = tab.header;
      W.otherOut.innerHTML = tab.lines.map(termLine).join('');
    }
    W.plg.hidden = !S.layout.tool || S.layout.zoom;
    W.term.hidden = !S.layout.term || S.layout.zoom;
    W.side.hidden = !S.layout.side;
    W.ai.classList.toggle('is-focus', S.focus === 'ai');
    W.term.classList.toggle('is-focus', S.focus === 'term');
    W.plg.classList.toggle('is-focus', S.focus === 'plugin');
    W.ai.classList.toggle('is-attn', S.status === 'needsInput');
  }

  function renderHeader() {
    W.aiAgent.innerHTML = `${svg('spark')}<b>${esc(S.agentName)}</b>`;
    W.aiTitle.textContent = S.title;
    renderStatus();
  }

  function renderStatus() {
    const st = S.status;
    let html = '';
    if (st === 'running') html = `${svg('dot')}Đang chạy${S.turn ? ' · ' + fmtDur(S.clock - S.turn.start) : ''}`;
    else if (st === 'needsInput') html = `${svg('warn')}Cần bạn trả lời`;
    else if (st === 'idle') html = `${svg('ring')}Đang chờ`;
    else if (st === 'done') html = `${svg('check')}Xong`;
    else if (!S.process) html = 'Agent chưa chạy';
    else if (S.authNeeded) html = `${svg('key')}Cần đăng nhập`;
    else html = 'Đang khởi động…';
    W.aiSt.className = 'ai-st st-' + st;
    W.aiSt.innerHTML = html;
  }

  function renderPlan() {
    const p = S.plan;
    W.plan.hidden = !p;
    if (!p) return;
    const done = p.filter((e) => e.status === 'completed').length;
    W.plan.innerHTML =
      `<button class="plan-h" data-act="plan">${svg('check')}<span>Kế hoạch · ${done}/${p.length} xong</span>${svg('chev', S.planOpen ? 'up' : '')}</button>` +
      (S.planOpen
        ? `<ol class="plan-l">${p.map((e) => `<li class="pe pe-${e.status}">${svg(e.status === 'completed' ? 'check' : e.status === 'in_progress' ? 'dot' : 'ring')}<span>${esc(e.content)}</span>${e.priority === 'high' ? '<i>ưu tiên</i>' : ''}</li>`).join('')}</ol>`
        : '');
  }

  function renderPermBar() {
    const p = S.perm;
    W.perm.hidden = !p;
    if (!p) {
      W.perm.innerHTML = '';
      return;
    }
    const firstReject = p.options.findIndex((o) => o.kind.startsWith('reject'));
    // Labels follow `kind`; only the agent knows what "always" covers, so
    // its own words for that option stay visible.
    const always = p.options.find((o) => o.kind === 'allow_always' || o.kind === 'reject_always');
    W.perm.innerHTML =
      `<div class="pb-h">${svg('warn')}<span>${esc(S.agentName)} xin quyền: <b>${esc(p.label)}</b></span></div>` +
      `<div class="pb-o">${p.options
        .map(
          (o, i) =>
            `<button class="pb-b k-${o.kind}" data-perm="${i}" title="Agent gửi: “${esc(o.name)}” (${o.kind})"><kbd>${i + 1}</kbd><b>${KIND_VI[o.kind] || esc(o.name)}</b>${i === firstReject ? '<kbd class="k-esc">Esc</kbd>' : ''}</button>`,
        )
        .join('')}</div>` +
      (always ? `<p class="pb-n">“${KIND_VI[always.kind]}” theo lời agent: <i>${esc(always.name)}</i></p>` : '');
  }

  function renderQueue() {
    W.queue.hidden = !S.queue.length;
    W.queue.innerHTML = S.queue
      .map(
        (m, i) =>
          `<div class="qm">${svg('history')}<span>Xếp hàng: <b>“${esc(clip(m.text, 60))}”</b> — gửi khi lượt này xong</span><button class="ib sm" data-unqueue="${i}" title="Bỏ">${svg('x')}</button></div>`,
      )
      .join('');
  }

  function renderAttach() {
    W.attach.hidden = !S.attachments.length;
    W.attach.innerHTML = S.attachments
      .map((a, i) => `<span class="chip">${svg('image')}${esc(a.name)}<button class="ib xs" data-unattach="${i}" title="Bỏ ảnh">${svg('x')}</button></span>`)
      .join('');
  }

  function cfgShort(o) {
    const opt = (o.options || []).find((x) => x.value === o.currentValue);
    const name = opt ? opt.name : o.currentValue;
    if (o.id === 'mode') return (MODE_VI[o.currentValue] || [name])[0];
    if (o.category === 'model') return `Model: ${name}`;
    if (o.category === 'thought_level') return `Suy nghĩ: ${name}`;
    return `${o.name}: ${name}`;
  }

  function renderComposer() {
    const ready = S.ready && !S.offline;
    W.ta.disabled = !ready;
    W.ta.placeholder = ready ? `Nhắn cho ${S.agentName}… (@ nhắc tệp, / gọi lệnh)` : S.readyHint;
    W.cfg.innerHTML = ready
      ? S.configOptions
          .map(
            (o) =>
              `<button class="cfg${o.id === 'mode' && o.currentValue !== 'default' ? ' is-on' : ''}${o.currentValue === 'bypassPermissions' ? ' is-danger' : ''}" data-cfg="${esc(o.id)}" title="${esc(o.name)}${o.description ? ' — ' + esc(o.description) : ''} (configOptions do agent gửi)">${esc(cfgShort(o))}${svg('chev')}</button>`,
          )
          .join('')
      : '';
    if (S.usage && ready) {
      const pct = Math.max(1, Math.round((S.usage.used / S.usage.size) * 100));
      W.ctx.textContent = `Ngữ cảnh ${pct}%`;
      W.ctx.title = `${S.usage.used.toLocaleString('vi-VN')} / ${S.usage.size.toLocaleString('vi-VN')} token (usage_update)`;
    } else {
      W.ctx.textContent = '';
      W.ctx.title = '';
    }
    renderSend();
  }

  function renderSend() {
    const running = !!S.turn;
    const has = W.ta.value.trim().length > 0;
    const stop = running && !has;
    W.send.className = 'ai-send' + (stop ? ' is-stop' : '');
    W.send.disabled = !S.ready || S.offline || (!running && !has);
    W.send.innerHTML = `${svg(stop ? 'stop' : 'send')}<span>${stop ? 'Dừng' : running ? 'Xếp hàng' : 'Gửi'}</span><kbd>${stop ? 'Esc' : '⏎'}</kbd>`;
  }

  function renderTerm() {
    W.termOut.innerHTML = S.term.map(termLine).join('');
    W.termOut.scrollTop = W.termOut.scrollHeight;
  }

  function termLine(l) {
    if (typeof l === 'string') return `<span class="tl-l">${esc(l) || ' '}</span>`;
    return `<span class="tl-l ${l.c || ''}">${l.h != null ? l.h : esc(l.t) || ' '}</span>`;
  }

  function renderEmpty() {
    W.empty.hidden = !S.empty;
    W.empty.innerHTML = S.empty || '';
  }

  function renderOffline() {
    W.off.hidden = !S.offline;
    W.off.innerHTML = S.offline
      ? `<div class="off-card"><b>ShellX đã thoát</b><p>Cửa sổ và tiến trình agent đã đóng. <code>layout.json</code> giữ lại pane AI (agent, id phiên, thư mục, tiêu đề) — không giữ nội dung hội thoại.</p><button class="btn pri" data-act="reopen">Mở lại ShellX</button></div>`
      : '';
  }

  /* -------------------------------------------------------- side panel -- */

  const isIgnored = (p) => p === '.env' || p.startsWith('node_modules/') || p.startsWith('dist/');

  function snapshot() {
    const o = {};
    for (const [p, c] of Object.entries(S.fs)) if (!isIgnored(p)) o[p] = c;
    return o;
  }

  function changesBetween(a, b) {
    const paths = [...new Set([...Object.keys(a), ...Object.keys(b)])].sort();
    const outList = [];
    for (const p of paths) {
      if (a[p] === b[p]) continue;
      const st = a[p] == null ? 'A' : b[p] == null ? 'D' : 'M';
      outList.push(Object.assign({ path: p, st }, diffStat(a[p] || '', b[p] || '')));
    }
    return outList;
  }

  function scopeBase() {
    if (!S.ckpts.length) return null;
    return S.scope === 'session' ? S.ckpts[0] : S.ckpts[S.ckpts.length - 1];
  }

  function changedAfterTurn(path) {
    const last = S.ckpts[S.ckpts.length - 1];
    if (!last || !last.after || S.turn) return false;
    return (last.after[path] ?? null) !== (S.fs[path] ?? null);
  }

  function reviewKey(p) {
    let x = 0;
    for (const ch of S.fs[p] || '') x = (x * 31 + ch.charCodeAt(0)) | 0;
    return `${p}:${x}`;
  }

  function renderSide() {
    const base = scopeBase();
    const ch = base ? changesBetween(base.files, snapshot()) : [];
    W.sideCnt.textContent = ch.length ? String(ch.length) : '';
    for (const b of root.querySelectorAll('[data-side]')) b.setAttribute('aria-selected', String(b.dataset.side === S.sideTab));
    W.sideBody.innerHTML = S.sideTab === 'changes' ? changesHtml(ch, base) : filesHtml(base);
  }

  function changesHtml(ch, base) {
    const scope = `<div class="dm-seg sm chg-scope" role="group" aria-label="So với"><button data-scope="turn" aria-pressed="${S.scope === 'turn'}">Lượt này</button><button data-scope="session" aria-pressed="${S.scope === 'session'}">Cả phiên</button></div>`;
    if (!base) {
      return `${scope}<p class="side-empty">Chưa có lượt nào. Trước mỗi lượt, ShellX chụp thư mục dự án vào một repo git ẩn; mọi thay đổi sau đó hiện ở đây — kể cả khi agent sửa bằng lệnh shell.</p>`;
    }
    const rows = ch
      .map((c) => {
        const after = changedAfterTurn(c.path);
        const dir = c.path.includes('/') ? c.path.slice(0, c.path.lastIndexOf('/') + 1) : '';
        const name = c.path.slice(dir.length);
        const seen = S.reviewed.has(reviewKey(c.path));
        return `<li class="chg${seen ? ' is-seen' : ''}">
          <button class="chg-p" data-chg="${esc(c.path)}" title="Xem diff"><span class="st st-${c.st}">${c.st}</span><span class="p"><span class="dir">${esc(dir)}</span>${esc(name)}</span><span class="n"><b class="add">+${c.add}</b><b class="del">−${c.del}</b></span></button>
          ${after ? '<span class="chg-warn" title="Tệp đã đổi sau khi lượt kết thúc">đã sửa sau lượt</span>' : ''}
          <span class="chg-a"><label class="rv" title="Đánh dấu đã xem"><input type="checkbox" data-rev="${esc(c.path)}"${seen ? ' checked' : ''}><span>Đã xem</span></label><button class="ib sm" data-revert-file="${esc(c.path)}" title="Hoàn tác tệp này">${svg('undo')}</button></span>
        </li>`;
      })
      .join('');
    const turnLabel = S.scope === 'session' ? 'Hoàn tác cả phiên' : `Hoàn tác lượt ${base.n}`;
    return `${scope}
      ${ch.length ? `<ul class="chg-list">${rows}</ul>` : `<p class="side-empty">Không có thay đổi nào so với ${S.scope === 'session' ? 'đầu phiên' : 'đầu lượt ' + base.n}.</p>`}
      <div class="chg-f">
        <p class="muted">Điểm khôi phục: trước lượt ${base.n} · <code>${base.id}</code></p>
        ${ch.length ? `<button class="btn sec sm" data-act="revert-scope"${S.turn ? ' disabled title="Đợi lượt đang chạy xong"' : ''}>${svg('undo')}${turnLabel}</button>` : ''}
        <p class="muted sm">Không theo dõi tệp bị <code>.gitignore</code> bỏ qua (vd <code>.env</code>): những tệp đó không hoàn tác được.</p>
      </div>`;
  }

  function filesHtml(base) {
    const tree = { dirs: {}, files: [] };
    for (const p of Object.keys(S.fs).sort()) {
      const parts = p.split('/');
      let node = tree;
      for (const d of parts.slice(0, -1)) node = node.dirs[d] = node.dirs[d] || { dirs: {}, files: [] };
      node.files.push(p);
    }
    const cur = snapshot();
    const changed = new Map((base ? changesBetween(base.files, cur) : []).map((c) => [c.path, c.st]));
    const walk = (node, depth) => {
      let html = '';
      for (const d of Object.keys(node.dirs).sort()) {
        html += `<div class="ft-d" style="padding-left:${8 + depth * 12}px">${svg('folder')}${esc(d)}</div>` + walk(node.dirs[d], depth + 1);
      }
      for (const p of node.files.sort()) {
        const st = changed.get(p);
        const ign = isIgnored(p);
        html += `<button class="ft-f${ign ? ' is-ign' : ''}" data-file="${esc(p)}" style="padding-left:${8 + depth * 12}px">${svg('file')}<span>${esc(p.split('/').pop())}</span>${st ? `<span class="st st-${st}">${st}</span>` : ''}${ign ? '<span class="ign">bỏ qua</span>' : ''}</button>`;
      }
      return html;
    };
    return `<div class="ft">${walk(tree, 0)}</div><p class="muted sm ft-n">Tệp do agent vừa sửa có nhãn <b>M</b>/<b>A</b>. Bấm một tệp để xem (chỉ đọc).</p>`;
  }

  function renderSheet() {
    const sh = S.sheet;
    W.sheet.hidden = !sh;
    if (!sh) {
      W.sheet.innerHTML = '';
      return;
    }
    const tools = `<button class="btn sm sec" data-sh="editor">${svg('ext')}Mở trong editor</button><button class="btn sm sec" data-sh="mention">${svg('at')}Nhắc trong chat</button><button class="ib" data-sh="close" title="Đóng (Esc)">${svg('x')}</button>`;
    if (sh.type === 'file') {
      const text = S.fs[sh.path];
      if (text == null) {
        S.sheet = null;
        renderSheet();
        return;
      }
      W.sheet.innerHTML = `<div class="sh-h">${svg('file')}<b class="mono">${esc(sh.path)}</b><span class="muted">chỉ đọc</span><span class="grow"></span>${tools}</div>
        <div class="sh-b"><div class="code">${lines(text)
          .map((l, i) => `<div class="cl${sh.line === i + 1 ? ' is-hit' : ''}"><span class="df-n">${i + 1}</span><code>${hl(l, langOf(sh.path)) || ' '}</code></div>`)
          .join('')}</div></div>`;
      const hit = W.sheet.querySelector('.is-hit');
      if (hit) hit.scrollIntoView({ block: 'center' });
      return;
    }
    const base = scopeBase();
    const old = base ? base.files[sh.path] : null;
    const cur = S.fs[sh.path] ?? null;
    const st = diffStat(old || '', cur || '');
    W.sheet.innerHTML = `<div class="sh-h">${svg('edit')}<b class="mono">${esc(sh.path)}</b><span class="n"><b class="add">+${st.add}</b><b class="del">−${st.del}</b></span><span class="muted">so với ${S.scope === 'session' ? 'đầu phiên' : 'đầu lượt'}</span><span class="grow"></span><button class="btn sm sec" data-revert-file="${esc(sh.path)}">${svg('undo')}Hoàn tác tệp</button>${tools}</div>
      <div class="sh-b">${diffHtml(old || '', cur || '', langOf(sh.path))}</div>`;
  }

  /* ----------------------------------------------------- conversation -- */

  function stickBottom(force) {
    if (force || S.stick) W.scroll.scrollTop = W.scroll.scrollHeight;
  }

  function newAgentBlock() {
    const el = h('div', { class: 'ab' }, h('div', { class: 'ab-h', html: `${svg('spark')}<b>${esc(S.agentName)}</b>` }), h('div', { class: 'ab-b' }));
    W.conv.append(el);
    return { el, body: el.lastChild, lastKind: null };
  }

  function ensureBlock() {
    if (!S.block) S.block = newAgentBlock();
    return S.block;
  }

  function endText(b) {
    if (b && b.textEl) b.textEl.classList.remove('is-streaming');
  }

  function appendText(text) {
    const b = ensureBlock();
    if (b.lastKind !== 'text') {
      b.textEl = h('div', { class: 'msg md is-streaming' });
      b.textBuf = '';
      b.body.append(b.textEl);
      b.lastKind = 'text';
    }
    b.textBuf += text;
    b.textEl.innerHTML = md(b.textBuf);
    stickBottom();
  }

  function appendThought(text) {
    const b = ensureBlock();
    if (b.lastKind !== 'thought') {
      endText(b);
      b.thought = h('details', { class: 'th' }, h('summary', { html: `${svg('think')}<span>Suy nghĩ</span><i>bấm để xem</i>` }), h('div', { class: 'th-b' }));
      b.thoughtBuf = '';
      b.body.append(b.thought);
      b.lastKind = 'thought';
    }
    b.thoughtBuf += text;
    b.thought.lastChild.textContent = b.thoughtBuf;
    stickBottom();
  }

  function userHtml(text) {
    return esc(text)
      .replace(/(^|\s)@([\w./-]+)/g, (m, sp, p) => (S.fs[p] != null ? `${sp}<button class="mention" data-file="${p}">${svg('file')}${p}</button>` : m))
      .replace(/\n/g, '<br>');
  }

  function addUser(msg) {
    endText(S.block);
    S.block = null;
    const el = h('div', { class: 'um' }, h('div', { class: 'um-h' }, msg.via === 'phone' ? 'Bạn · từ điện thoại' : 'Bạn'), h('div', { class: 'um-t', html: userHtml(msg.text) }));
    S.mirror.push({ k: 'user', text: msg.text, via: msg.via });
    if (msg.images && msg.images.length) {
      el.append(h('div', { class: 'um-att', html: msg.images.map((a) => `<span class="chip">${svg('image')}${esc(a.name)}</span>`).join('') }));
    }
    W.conv.append(el);
    stickBottom(true);
  }

  function notice(o) {
    endText(S.block);
    S.block = null;
    const icon = o.kind === 'err' ? 'warn' : o.kind === 'auth' ? 'key' : 'bell';
    const el = h(
      'div',
      { class: `nc nc-${o.kind || 'info'}` },
      h('div', { class: 'nc-h', html: `${svg(icon)}<b>${esc(o.title)}</b>` }),
      h('div', { class: 'nc-b', html: o.body || '' }),
    );
    if (o.actions && o.actions.length) {
      el.append(
        h(
          'div',
          { class: 'nc-a' },
          o.actions.map((a) =>
            h(
              'button',
              {
                class: `btn sm ${a.kind || 'sec'}`,
                onclick: () => {
                  unpause();
                  if (a.onClick) a.onClick();
                  else fire(a.key, a.value);
                },
              },
              a.label,
            ),
          ),
        ),
      );
    }
    W.conv.append(el);
    stickBottom(true);
    return el;
  }

  function diffOf(t) {
    return (t.content || []).find((c) => c.type === 'diff') || null;
  }

  function textOf(t) {
    return (t.content || [])
      .filter((c) => c.type === 'content' && c.content && c.content.type === 'text')
      .map((c) => c.content.text)
      .join('\n');
  }

  function toolLabel(t) {
    const loc = t.locations && t.locations[0] ? rel(t.locations[0].path) : null;
    const d = diffOf(t);
    switch (t.kind) {
      case 'read':
        return { verb: 'Đọc', target: loc || t.title, mono: true };
      case 'edit': {
        const verb = d ? (d.oldText == null ? 'Tạo' : 'Sửa') : /^Write /.test(t.title || '') ? 'Ghi' : 'Sửa';
        return { verb, target: loc || (d ? rel(d.path) : t.title), mono: true };
      }
      case 'delete':
        return { verb: 'Xoá', target: loc || t.title, mono: true };
      case 'move':
        return { verb: 'Đổi tên', target: loc || t.title, mono: true };
      case 'search':
        return { verb: 'Tìm', target: t.title, mono: true };
      case 'execute':
        return { verb: 'Chạy', target: t.title, mono: true };
      case 'fetch':
        return { verb: 'Tải', target: t.title, mono: false };
      case 'think':
        return { verb: 'Suy nghĩ', target: t.title, mono: false };
      default: {
        const m = /^mcp__(.+?)__(.+)$/.exec(t.title || '');
        if (m) return { verb: m[1], target: m[2], mono: true, mcp: true };
        return { verb: '', target: t.title, mono: false };
      }
    }
  }

  function toolStatus(t) {
    if (t.perm && !t.perm.answer) return '<span class="s-ask">chờ bạn</span>';
    if (t.status === 'pending') return '<span class="s-wait">chờ</span>';
    if (t.status === 'in_progress') return `<span class="s-run">${svg('dot')}đang chạy · <span data-tt="${esc(t.id)}">${fmtSec(S.clock - t.started)}</span></span>`;
    if (t.status === 'completed') {
      // A call that arrives already finished (replay) carries no timing.
      const live = t.kind === 'execute' && !t.noTiming;
      const dur = live && t.ended ? ` · ${fmtSec(t.ended - t.started)}` : '';
      return `<span class="s-ok">${svg('check')}${live ? 'mã 0' : ''}${dur}</span>`;
    }
    if (t.rejected) return `<span class="s-no">${svg('x')}bị từ chối</span>`;
    if (t.stopped) return `<span class="s-no">${svg('stop')}đã dừng</span>`;
    return `<span class="s-no">${svg('x')}lỗi</span>`;
  }

  function ansiLite(text) {
    return text
      .split('\n')
      .map((l) => {
        const c = /✓|passed/.test(l) ? 'ok' : /✗|FAIL|failed|Error/.test(l) ? 'err' : /^>/.test(l) ? 'dim' : '';
        return `<span class="${c}">${esc(l) || ' '}</span>`;
      })
      .join('\n');
  }

  function expandable(t) {
    return ['edit', 'execute', 'search', 'other', 'fetch', 'delete', 'move'].includes(t.kind);
  }

  function renderTool(t) {
    const L = toolLabel(t);
    const d = diffOf(t);
    const asking = t.perm && !t.perm.answer;
    const open = asking || t.open;
    t.el.className = `tc tc-${t.kind} tc-${t.status}${open ? ' is-open' : ''}${asking ? ' is-ask' : ''}`;
    let meta = '';
    if (d) {
      const s = diffStat(d.oldText || '', d.newText);
      meta += `<span class="n"><b class="add">+${s.add}</b><b class="del">−${s.del}</b></span>`;
    }
    meta += `<span class="tc-s">${toolStatus(t)}</span>`;
    const icon = L.mcp ? 'puzzle' : KIND_ICON[t.kind] || 'puzzle';
    const verb = L.mcp ? `<span class="tc-v mcp">${esc(L.verb)}</span><span class="tc-dot">·</span>` : L.verb ? `<span class="tc-v">${esc(L.verb)}</span>` : '';
    const head = `<button class="tc-h" data-tool="${esc(t.id)}" title="${esc(t.title)}">${svg(icon)}${verb}<span class="tc-t${L.mono ? ' mono' : ''}">${esc(L.target || '')}</span>${meta}${expandable(t) ? svg('chev', 'tc-chev') : ''}</button>`;
    let body = '';
    if (open) {
      if (d) {
        body += diffHtml(d.oldText || '', d.newText, langOf(d.path));
        body += `<div class="tc-act"><button class="lnk" data-file="${esc(rel(d.path))}">${svg('file')}Xem cả tệp</button><button class="lnk" data-editor="${esc(rel(d.path))}">${svg('ext')}Mở trong editor</button></div>`;
      }
      const txt = textOf(t);
      if (t.kind === 'execute') {
        if (t.status === 'completed' || t.status === 'failed') {
          body += txt
            ? `<pre class="tc-out">${ansiLite(txt)}</pre>`
            : '<p class="tc-empty">Không có đầu ra. Agent không gửi diff cho lệnh shell — panel Thay đổi vẫn thấy tệp đổi nhờ điểm khôi phục.</p>';
        } else {
          body += `<pre class="tc-out"><span class="dim">$</span> ${esc(t.title)}</pre>${txt ? `<p class="tc-empty">${esc(txt)}</p>` : ''}<p class="tc-empty">Adapter chỉ gửi đầu ra khi lệnh chạy xong.</p>`;
        }
      } else if (txt && !d) {
        body += `<pre class="tc-out">${esc(txt)}</pre>`;
      }
      if (t.kind === 'other' && t.rawInput) body += `<p class="tc-lbl">Tham số (rawInput)</p><pre class="tc-out j">${jsonHtml(t.rawInput)}</pre>`;
    }
    let ask = '';
    if (t.perm) {
      if (!t.perm.answer) {
        ask = `<div class="tc-ask">${svg('warn')}<span>Chờ bạn trả lời ở thanh xin quyền phía dưới — phím <kbd>1</kbd>–<kbd>${t.perm.options.length}</kbd>, <kbd>Esc</kbd> để từ chối.</span></div>`;
      } else if (t.perm.answer.cancelled) {
        ask = `<div class="tc-ans no">${svg('stop')}<span>Lượt bị dừng trước khi bạn trả lời (outcome: cancelled)</span></div>`;
      } else {
        const k = t.perm.answer.kind;
        ask = `<div class="tc-ans ${k.startsWith('allow') ? 'ok' : 'no'}">${svg(k.startsWith('allow') ? 'check' : 'x')}<span>Bạn chọn: <b>${KIND_VI[k]}</b> <span class="muted">(${esc(t.perm.answer.name)})</span></span></div>`;
      }
    }
    t.el.innerHTML = head + (body ? `<div class="tc-b">${body}</div>` : '') + ask;
  }

  function turnSummary(t, stop, ch) {
    const add = total(ch.map((c) => c.add));
    const del = total(ch.map((c) => c.del));
    const head = stop === 'cancelled' ? `Đã dừng lượt ${t.n}` : stop === 'crash' ? `Lượt ${t.n} bị gián đoạn` : `Lượt ${t.n}`;
    const el = h('div', { class: `turn-sum${stop !== 'end_turn' ? ' is-stop' : ''}` });
    el.innerHTML =
      `<span class="ts-h">${head} · ${fmtDur(t.end - t.start)}</span>` +
      (ch.length
        ? `<span>${ch.length} tệp đổi <b class="add">+${add}</b> <b class="del">−${del}</b></span><button class="lnk" data-act="see-turn">Xem</button><button class="lnk" data-act="revert-turn">${svg('undo')}Hoàn tác lượt</button>`
        : '<span class="muted">không đổi tệp nào</span>');
    return el;
  }

  /** Renders one `session/update` (live or replayed by session/load). */
  function applyUpdate(u, replay) {
    if (!replay && ['user_message_chunk', 'agent_message_chunk', 'tool_call', 'tool_call_update'].includes(u.sessionUpdate)) {
      S.history.push(JSON.parse(JSON.stringify(u)));
    }
    mirror(u);
    switch (u.sessionUpdate) {
      case 'user_message_chunk': {
        endText(S.block);
        S.block = null;
        const last = W.conv.lastElementChild;
        if (last && last.classList.contains('um') && last.dataset.replay === '1') {
          last.dataset.text += u.content.text;
          last.querySelector('.um-t').innerHTML = userHtml(last.dataset.text);
        } else {
          const el = h('div', { class: 'um', 'data-replay': '1', 'data-text': u.content.text }, h('div', { class: 'um-h' }, 'Bạn'), h('div', { class: 'um-t', html: userHtml(u.content.text) }));
          W.conv.append(el);
        }
        stickBottom();
        break;
      }
      case 'agent_message_chunk':
        appendText(u.content.text);
        break;
      case 'agent_thought_chunk':
        appendThought(u.content.text);
        break;
      case 'tool_call': {
        const b = ensureBlock();
        endText(b);
        b.lastKind = 'tool';
        const t = {
          id: u.toolCallId,
          kind: u.kind || 'other',
          title: u.title,
          status: u.status || 'pending',
          content: u.content || [],
          locations: u.locations || [],
          rawInput: u.rawInput,
          started: S.clock,
          ended: u.status === 'completed' ? S.clock : null,
          noTiming: u.status === 'completed' || u.status === 'failed',
          open: false,
          el: h('div'),
        };
        S.tools.set(t.id, t);
        if (S.turn) S.turn.tools.push(t.id);
        b.body.append(t.el);
        renderTool(t);
        stickBottom();
        break;
      }
      case 'tool_call_update': {
        const t = S.tools.get(u.toolCallId);
        if (!t) break;
        if (u.status && u.status !== t.status) {
          if (u.status === 'in_progress') t.started = S.clock;
          if (u.status === 'completed' || u.status === 'failed') t.ended = S.clock;
          t.status = u.status;
        }
        for (const k of ['title', 'kind', 'content', 'locations', 'rawInput']) if (u[k] != null) t[k] = u[k];
        // A finished command shows its output (or says there was none).
        if (t.kind === 'execute' && t.status === 'completed') t.open = true;
        renderTool(t);
        stickBottom();
        break;
      }
      case 'plan':
        S.plan = u.entries;
        S.planOpen = true;
        renderPlan();
        break;
      case 'available_commands_update':
        S.commands = u.availableCommands;
        break;
      case 'config_option_update':
        S.configOptions = u.configOptions;
        renderComposer();
        break;
      case 'usage_update':
        S.usage = { used: u.used, size: u.size };
        renderComposer();
        break;
      case 'session_info_update':
        if (u.title) setTitle(u.title);
        break;
      default:
        break;
    }
  }

  /* -------------------------------------------------- ShellX behaviour -- */

  function setStatus(st) {
    if (S.status === st) return;
    S.status = st;
    renderStatus();
    renderSidebar();
    renderPanes();
  }

  function setTitle(t) {
    S.title = t;
    renderTop();
    renderHeader();
    renderSidebar();
  }

  function selectTab(id) {
    if (id === 'ai' && !S.aiTab) return;
    S.selectedTab = id;
    if (id === 'ai' && S.status === 'done') {
      setStatus('idle');
      hood('trạng thái', 'A12: **Xong → Đang chờ** vì bạn vừa nhìn lại pane');
    }
    renderTop();
    renderSidebar();
    renderPanes();
    fire('tab', id);
  }

  function setLayout(o) {
    Object.assign(S.layout, o);
    renderPanes();
  }

  function focusPane(p) {
    S.focus = p;
    renderPanes();
  }

  function termPrint(items) {
    S.term.push(...items);
    renderTerm();
  }

  function toast(text) {
    W.toast.hidden = false;
    W.toast.innerHTML = inline(text);
    clearTimeout(toast.t);
    toast.t = setTimeout(() => {
      W.toast.hidden = true;
    }, 3600);
  }

  /** A mock macOS banner: what ShellX's A4 notification path would show. */
  function notify(title, body) {
    hood('thông báo', `Thông báo hệ thống: “${title}”`, 'Đi qua đường A4 sẵn có (localSessionsProvider.notify) — cũng đẩy sang điện thoại đã ghép đôi.');
    W.note.hidden = false;
    W.note.innerHTML = `<button class="nt" data-act="note">${svg('spark')}<span class="nt-app">ShellX · bây giờ</span><b>${esc(title)}</b><span>${esc(body)}</span><i>Bấm để mở pane</i></button>`;
    clearTimeout(notify.t);
    notify.t = setTimeout(() => {
      W.note.hidden = true;
    }, 7000);
  }

  function dialog(o) {
    closeMenu();
    return new Promise((resolve) => {
      W.modal.hidden = false;
      W.modal.innerHTML = `<div class="dlg${o.wide ? ' wide' : ''}" role="dialog" aria-modal="true" aria-label="${esc(o.title)}"><h3>${esc(o.title)}</h3><div class="dlg-b"></div><div class="dlg-a">${o.actions
        .map((a, i) => `<button class="btn ${a.kind || 'sec'}" data-dlg="${i}">${esc(a.label)}</button>`)
        .join('')}</div></div>`;
      const body = W.modal.querySelector('.dlg-b');
      if (typeof o.body === 'string') body.innerHTML = o.body;
      else if (o.body) body.append(o.body);
      const done = (v) => {
        if (S.dialogDone !== done) return;
        S.dialogDone = null;
        W.modal.hidden = true;
        W.modal.innerHTML = '';
        resolve(v);
      };
      S.dialogDone = done;
      W.modal.querySelectorAll('[data-dlg]').forEach((b) =>
        b.addEventListener('click', () => {
          unpause();
          done(o.actions[+b.dataset.dlg].value);
        }),
      );
      // ShellX UI §4: a destructive confirm starts on Cancel, never on the action.
      const first = W.modal.querySelector('.btn.pri') || W.modal.querySelector('.btn:not(.danger)');
      if (first && visible) first.focus({ preventScroll: true });
    });
  }

  function closeDialog() {
    if (S && S.dialogDone) S.dialogDone(null);
  }

  function openMenu(anchor, items, onPick, opts) {
    closeMenu();
    const wr = W.win.getBoundingClientRect();
    const ar = anchor.getBoundingClientRect();
    W.menu.hidden = false;
    W.menu.innerHTML =
      (opts && opts.title ? `<div class="mn-t">${esc(opts.title)}</div>` : '') +
      items
        .map((it, i) =>
          it.sep
            ? '<div class="mn-sep"></div>'
            : `<button class="mn-i${it.checked ? ' is-on' : ''}${it.danger ? ' is-danger' : ''}" data-mi="${i}"${it.disabled ? ' disabled' : ''}><span class="mn-c">${it.checked ? svg('check') : ''}</span><span class="mn-l"><b>${esc(it.label)}</b>${it.desc ? `<small>${esc(it.desc)}</small>` : ''}</span>${it.hint ? `<span class="mn-h">${esc(it.hint)}</span>` : ''}</button>`,
        )
        .join('');
    const mw = Math.min(330, wr.width - 16);
    W.menu.style.width = mw + 'px';
    let left = ar.left - wr.left;
    if (left + mw > wr.width - 8) left = wr.width - 8 - mw;
    W.menu.style.left = Math.max(8, left) + 'px';
    const below = ar.bottom - wr.top + 4;
    const mh = W.menu.offsetHeight;
    W.menu.style.top = (below + mh > wr.height - 8 ? Math.max(8, ar.top - wr.top - mh - 4) : below) + 'px';
    S.menu = { onPick, items };
    W.menu.querySelectorAll('[data-mi]').forEach((b) =>
      b.addEventListener('click', (e) => {
        e.stopPropagation();
        const it = items[+b.dataset.mi];
        closeMenu();
        onPick(it);
      }),
    );
  }

  function closeMenu() {
    if (!S || !S.menu) return;
    S.menu = null;
    W.menu.hidden = true;
    W.menu.innerHTML = '';
  }

  /* ----------------------------------------------- disk & checkpoints -- */

  function write(path, content) {
    if (content == null) delete S.fs[path];
    else S.fs[path] = content;
    renderSide();
    if (S.sheet && S.sheet.path === path) renderSheet();
  }

  function grep(pattern, dir) {
    const outLines = [];
    for (const p of Object.keys(S.fs).sort()) {
      if (dir && !p.startsWith(dir + '/')) continue;
      lines(S.fs[p]).forEach((l, i) => {
        if (l.includes(pattern)) outLines.push(`${p}:${i + 1}:${l}`);
      });
    }
    return outLines.join('\n');
  }

  function readNumbered(path) {
    return lines(S.fs[path] || '')
      .map((l, i) => `${i + 1}\t${l}`)
      .join('\n');
  }

  function checkpoint(n) {
    const id = S.hashes.shift() || Math.random().toString(16).slice(2, 9);
    const ck = { id, n, at: S.clock, files: snapshot(), after: null };
    S.ckpts.push(ck);
    hood(
      'điểm khôi phục',
      `Chụp thư mục trước lượt ${n} → commit \`${id}\` trong repo git ẩn`,
      `GIT_DIR="${DATA.ckptDir}"\nGIT_WORK_TREE=~/code/shop-web\ngit add -A                      # theo .gitignore của dự án\ngit commit -q --allow-empty -m "trước lượt ${n}"   → ${id}\n\nRepo .git của bạn không bị đụng tới (index, nhánh, stash giữ nguyên).`,
    );
    renderSide();
    return ck;
  }

  async function revertScope(single) {
    const base = scopeBase();
    if (!base) return;
    if (S.turn) {
      toast('Đợi lượt đang chạy xong rồi hoàn tác.');
      return;
    }
    let ch = changesBetween(base.files, snapshot());
    if (single) ch = ch.filter((c) => c.path === single);
    if (!ch.length) return;
    const dirty = ch.filter((c) => changedAfterTurn(c.path));
    let pick = 'all';
    if (dirty.length) {
      pick = await dialog({
        title: 'Có tệp đã đổi sau lượt này',
        body: `<p>${dirty.map((d) => `<code>${esc(d.path)}</code>`).join(', ')} đã bị sửa <b>sau khi lượt kết thúc</b> — có thể do bạn, hoặc một phiên khác.</p><p>Hoàn tác sẽ ghi đè cả thay đổi đó.</p>`,
        actions: [
          { label: 'Huỷ', value: 'cancel' },
          ...(ch.length > dirty.length ? [{ label: 'Chỉ hoàn tác tệp chưa sửa', value: 'clean' }] : []),
          { label: dirty.length === ch.length && ch.length === 1 ? 'Vẫn hoàn tác' : 'Hoàn tác tất cả', value: 'all', kind: 'danger' },
        ],
      });
      if (!pick || pick === 'cancel') return;
    }
    const targets = pick === 'clean' ? ch.filter((c) => !dirty.includes(c)) : ch;
    for (const c of targets) {
      if (base.files[c.path] == null) delete S.fs[c.path];
      else S.fs[c.path] = base.files[c.path];
    }
    const restored = targets.filter((c) => c.st !== 'A').map((c) => c.path);
    const created = targets.filter((c) => c.st === 'A').map((c) => c.path);
    hood(
      'điểm khôi phục',
      `Hoàn tác ${targets.length} tệp về \`${base.id}\` (trước lượt ${base.n})`,
      (restored.length ? `git checkout ${base.id} -- ${restored.join(' ')}\n` : '') + (created.length ? `rm ${created.join(' ')}   # tệp mới tạo sau điểm khôi phục\n` : '') + '(chạy với GIT_DIR của repo ẩn; .git của dự án không đổi)',
    );
    toast(`Đã hoàn tác ${targets.length} tệp.`);
    renderSide();
    renderSheet();
    fire('reverted', targets.map((c) => c.path));
  }

  /* ------------------------------------------------- agent & session -- */

  async function spawnAgent(opts) {
    const o = opts || {};
    hood('tiến trình', 'Lấy PATH và biến môi trường từ login shell', '$SHELL -lc với ký tự đánh dấu \\x1e trước và sau (như LoginPathCheck),\nnên chữ mà profile in ra không lẫn vào kết quả.');
    await wait(260);
    S.process = { pid: o.pid || 48211 };
    hood('tiến trình', `Chạy agent trực tiếp, không qua shell · pid ${S.process.pid}`, `node "${DATA.adapterPath}"${o.args ? ' ' + o.args : ''}\ncwd: ~/code/shop-web\n\nCài một lần vào thư mục riêng (bản ghim), chạy bằng node — không npx.`);
    renderStatus();
    await wait(240);
  }

  async function initialize() {
    const id = out('initialize', DATA.initParams, 'protocolVersion 1 · fs ✗ · terminal ✗ · auth.terminal ✓');
    await wait(520);
    inRes(id, 'initialize', DATA.initResult, 'Claude Agent 0.90.0 · loadSession ✓ · 2 cách đăng nhập', 'Đã rút gọn: bỏ các khoá `_meta` mở rộng của adapter.');
    await wait(140);
  }

  async function newSession(o) {
    const opts = o || {};
    const params = { cwd: DATA.cwd, mcpServers: opts.mcpServers || [] };
    const id = out('session/new', params, `cwd ~/code/shop-web · ${params.mcpServers.length} MCP server`);
    await wait(620);
    if (opts.authRequired) {
      inErr(id, 'session/new', { code: -32000, message: 'Authentication required' }, '-32000 Authentication required');
      S.authNeeded = true;
      renderStatus();
      return false;
    }
    S.sessionId = DATA.sessionId;
    S.configOptions = DATA.configOptions(S.cfg);
    inRes(id, 'session/new', { sessionId: S.sessionId, configOptions: S.configOptions }, `sessionId ${S.sessionId.slice(0, 8)}… · mode, model, effort`);
    await wait(120);
    update({ sessionUpdate: 'available_commands_update', availableCommands: DATA.commands });
    sessionReady();
    return true;
  }

  async function loadSession(o) {
    const opts = o || {};
    S.sessionId = S.sessionId || DATA.sessionId;
    const params = { sessionId: S.sessionId, cwd: DATA.cwd, mcpServers: opts.mcpServers || [] };
    const id = out('session/load', params, `phiên ${S.sessionId.slice(0, 8)}… · ${params.mcpServers.length} MCP server`);
    await wait(360);
    const hist = opts.history || [];
    if (hist.length) {
      W.conv.innerHTML = '';
      S.block = null;
      S.tools.clear();
      S.mirror = [];
    }
    for (const u of hist) {
      logPush({
        lane: 'acp',
        dir: 'in',
        kind: 'note',
        method: 'session/update',
        sub: u.sessionUpdate,
        sum: '(phát lại) ' + updateSummary(u),
        json: { jsonrpc: '2.0', method: 'session/update', params: { sessionId: S.sessionId, update: u } },
      });
      applyUpdate(u, true);
      await wait(90);
    }
    endText(S.block);
    S.block = null;
    S.configOptions = DATA.configOptions(S.cfg);
    inRes(id, 'session/load', { configOptions: S.configOptions }, hist.length ? `đã phát lại ${hist.length} cập nhật` : 'phiên sẵn sàng');
    await wait(100);
    update({ sessionUpdate: 'available_commands_update', availableCommands: DATA.commands });
    sessionReady();
  }

  function sessionReady() {
    S.ready = true;
    S.authNeeded = false;
    S.readyHint = '';
    S.empty = null;
    renderEmpty();
    setStatus('idle');
    renderComposer();
  }

  function stopAgent(reason) {
    if (S.process) hood('tiến trình', `Dừng agent (pid ${S.process.pid}) bằng killProcessTree`, reason || 'Đóng stdin, chờ tối đa 2 s, rồi diệt cả cây tiến trình (taskkill /T trên Windows).');
    S.process = null;
    S.ready = false;
    renderStatus();
    renderComposer();
  }

  function historyForReplay(src) {
    const outList = [];
    const tools = new Map();
    for (const u of src || S.history) {
      const k = u.sessionUpdate;
      if (k === 'user_message_chunk' || k === 'agent_message_chunk') {
        const last = outList[outList.length - 1];
        if (last && last.sessionUpdate === k) last.content = { type: 'text', text: last.content.text + u.content.text };
        else outList.push({ sessionUpdate: k, content: { type: 'text', text: u.content.text } });
      } else if (k === 'tool_call') {
        const c = JSON.parse(JSON.stringify(u));
        tools.set(u.toolCallId, c);
        outList.push(c);
      } else if (k === 'tool_call_update') {
        const c = tools.get(u.toolCallId);
        if (c) for (const [key, v] of Object.entries(u)) if (key !== 'sessionUpdate' && v != null) c[key] = JSON.parse(JSON.stringify(v));
      }
    }
    return outList;
  }

  async function setConfig(id, value) {
    if (id === 'mode' && value === 'bypassPermissions') {
      const ok = await dialog({
        title: 'Bật “Bỏ qua mọi quyền”?',
        body: '<p>Claude sẽ sửa tệp và chạy lệnh <b>không hỏi</b> bạn. Chỉ bật ở nơi bạn chấp nhận rủi ro (container, bản sao để thử).</p><p class="muted">Điểm khôi phục vẫn chạy trước mỗi lượt, nhưng không lấy lại được việc đã ra ngoài máy (git push, gọi API, gửi email…).</p>',
        actions: [
          { label: 'Huỷ', value: false },
          { label: 'Bật', value: true, kind: 'danger' },
        ],
      });
      if (!ok) return;
    }
    S.cfg[id] = value;
    const rid = out('session/set_config_option', { sessionId: S.sessionId, configId: id, value }, `${id} = ${value}`);
    S.configOptions = DATA.configOptions(S.cfg);
    inRes(rid, 'session/set_config_option', { configOptions: S.configOptions }, 'configOptions mới');
    renderComposer();
  }

  /* -------------------------------------------------------- the turn -- */

  function promptSummary(blocks) {
    const n = (t) => blocks.filter((b) => b.type === t).length;
    return ['text', n('resource_link') ? `${n('resource_link')} tệp` : '', n('image') ? `${n('image')} ảnh` : ''].filter(Boolean).join(' + ');
  }

  function buildPrompt(text) {
    const blocks = [{ type: 'text', text }];
    const mentions = [];
    for (const m of text.matchAll(/(?:^|\s)@([\w./-]+)/g)) {
      if (S.fs[m[1]] != null && !mentions.includes(m[1])) mentions.push(m[1]);
    }
    for (const p of mentions) blocks.push({ type: 'resource_link', uri: 'file://' + abs(p), name: p.split('/').pop(), mimeType: mimeOf(p) });
    for (let i = 0; i < S.attachments.length; i++) blocks.push({ type: 'image', mimeType: 'image/png', data: 'iVBORw0KGgoAAAANSUhEUgAAB4AAAAQ4CAYAAADo08FDAAAAAXNSR0IArs4c6QAAIABJREFUeF7s3Q…' });
    return { text, blocks, mentions, images: S.attachments.slice() };
  }

  function onSend() {
    const text = W.ta.value.trim();
    if (S.turn) {
      if (text) queueMsg(text);
      else cancelTurn();
      return;
    }
    if (!text || !S.ready || S.offline) return;
    const msg = buildPrompt(text);
    W.ta.value = '';
    autoGrow();
    S.attachments = [];
    renderAttach();
    closePop();
    addUser(msg);
    S.history.push({ sessionUpdate: 'user_message_chunk', content: { type: 'text', text } });
    unpause();
    if (!fire('send', msg)) runDetached(() => genericTurn(msg));
    renderSend();
  }

  function queueMsg(text) {
    S.queue.push(buildPrompt(text));
    W.ta.value = '';
    autoGrow();
    S.attachments = [];
    renderAttach();
    renderQueue();
    renderSend();
    hood('tiến trình', 'Xếp hàng tin nhắn — ShellX tự gửi khi lượt hiện tại xong', 'ACP v1 chưa có cách chuẩn để chen tin vào lượt đang chạy (adapter Claude có phần mở rộng riêng `_session/steering`; để sau).');
  }

  function pumpQueue() {
    if (S.turn || !S.queue.length || !S.ready) return;
    const msg = S.queue.shift();
    renderQueue();
    addUser(msg);
    S.history.push({ sessionUpdate: 'user_message_chunk', content: { type: 'text', text: msg.text } });
    runDetached(() => genericTurn(msg));
  }

  async function genericTurn(msg) {
    await turn(msg.blocks, async () => {
      await wait(500);
      await stream(DATA.genericReply(msg.text, S.cfg.mode));
      await wait(150);
      update({ sessionUpdate: 'usage_update', used: (S.usage ? S.usage.used : 18000) + 1400, size: 200000 });
    });
  }

  async function stream(text, kind) {
    const k = kind || 'agent_message_chunk';
    const parts = text.match(/\S+\s*|\s+/g) || [];
    for (let i = 0; i < parts.length; i += 3) {
      update({ sessionUpdate: k, content: { type: 'text', text: parts.slice(i, i + 3).join('') } });
      await wait(k === 'agent_thought_chunk' ? 45 : 60);
    }
  }

  async function turn(blocks, body) {
    const token = R.token;
    const n = ++S.turnCount;
    const ck = checkpoint(n);
    const t = { n, start: S.clock, cancelled: false, ck, tools: [], block: null, end: null };
    S.turn = t;
    S.block = newAgentBlock();
    t.block = S.block;
    t.promptId = out('session/prompt', { sessionId: S.sessionId, prompt: blocks }, promptSummary(blocks));
    setStatus('running');
    hood('trạng thái', `A12: **Đang chạy** (lượt ${n}) → sidebar, header pane; báo \`agent.state\` cho điện thoại`);
    renderComposer();
    renderSide();
    let stop = 'end_turn';
    try {
      stop = (await body()) || 'end_turn';
    } catch (e) {
      if (token !== R.token || e instanceof Stop) throw e;
      if (e instanceof Crash) {
        S.turn = null;
        crashed(t, e);
        return 'crash';
      }
      if (!(e instanceof Cancelled)) throw e;
      S.turn = null;
      stop = 'cancelled';
      for (const id of t.tools) {
        const tool = S.tools.get(id);
        if (tool && (tool.status === 'pending' || tool.status === 'in_progress')) {
          tool.stopped = true;
          update({ sessionUpdate: 'tool_call_update', toolCallId: id, status: 'failed' }, `…${id.slice(-4)} → failed (đã dừng)`);
        }
      }
    }
    if (token !== R.token) throw new Stop();
    inRes(t.promptId, 'session/prompt', { stopReason: stop }, `stopReason: ${stop}`);
    finishTurn(t, stop);
    pumpQueue();
    return stop;
  }

  function finishTurn(t, stop) {
    S.turn = null;
    t.end = S.clock;
    t.ck.after = snapshot();
    const ch = changesBetween(t.ck.files, t.ck.after);
    hood(
      'điểm khôi phục',
      ch.length ? `So với điểm khôi phục trước lượt ${t.n}: **${ch.length} tệp đổi**` : `Lượt ${t.n} không đổi tệp nào`,
      `git diff --numstat ${t.ck.id}\n` + (ch.map((c) => `${c.add}\t${c.del}\t${c.path}`).join('\n') || '(trống)'),
    );
    endText(t.block);
    t.block.el.append(turnSummary(t, stop, ch));
    S.mirror.push({
      k: 'sum',
      text: (stop === 'cancelled' ? 'Đã dừng lượt · ' : '') + (ch.length ? `${ch.length} tệp đổi +${total(ch.map((c) => c.add))} −${total(ch.map((c) => c.del))}` : 'không đổi tệp nào'),
    });
    if (S.plan) {
      S.planOpen = false;
      renderPlan();
    }
    const seen = S.selectedTab === 'ai';
    setStatus(seen ? 'idle' : 'done');
    if (seen) hood('trạng thái', 'A12: **Đang chờ** — bạn đang nhìn pane nên không cần thông báo “đã xong”');
    else {
      hood('trạng thái', 'A12: **Xong** — pane không được nhìn lúc lượt kết thúc');
      notify(`${S.agentName} đã xong`, S.title);
    }
    renderComposer();
    renderSide();
    stickBottom();
    renderPhone();
  }

  function cancelTurn() {
    const t = S.turn;
    if (!t || t.cancelled) return;
    t.cancelled = true;
    outNote('session/cancel', { sessionId: S.sessionId }, 'dừng lượt');
    hood('tiến trình', 'Bạn bấm Dừng (Esc) → `session/cancel`', 'Nếu sau 10 s agent chưa trả lời session/prompt, ShellX hiện nút “Dừng hẳn” (killProcessTree).');
    if (S.perm) {
      const p = S.perm;
      outRes(p.id, 'session/request_permission', { outcome: { outcome: 'cancelled' } }, 'outcome: cancelled');
      const tool = S.tools.get(p.toolCallId);
      if (tool && tool.perm) {
        tool.perm.answer = { cancelled: true };
        renderTool(tool);
      }
      S.perm = null;
      renderPermBar();
    }
    for (const tm of R.timers.filter((x) => x.turn === t)) tm.reject(new Cancelled());
    R.timers = R.timers.filter((x) => x.turn !== t);
    for (const [k, w] of [...R.waits]) {
      if (w.turn === t) {
        R.waits.delete(k);
        w.reject(new Cancelled());
      }
    }
    unpause();
  }

  function crashed(t, e) {
    for (const id of t.tools) {
      const tool = S.tools.get(id);
      if (tool && (tool.status === 'pending' || tool.status === 'in_progress')) {
        tool.status = 'failed';
        tool.stopped = true;
        renderTool(tool);
      }
    }
    t.end = S.clock;
    t.ck.after = snapshot();
    endText(t.block);
    t.block.el.append(turnSummary(t, 'crash', changesBetween(t.ck.files, t.ck.after)));
    S.process = null;
    S.ready = false;
    S.readyHint = 'Agent đã dừng — bấm “Khởi động lại”';
    S.perm = null;
    S.lastCrash = e;
    S.planOpen = false;
    renderPlan();
    renderPermBar();
    setStatus('none');
    hood('trạng thái', 'A12: bỏ trạng thái của pane — agent không còn chạy');
    renderComposer();
    renderSide();
  }

  /* -------------------------------------------------------- permission -- */

  async function ask(toolCall, options) {
    const t = S.tools.get(toolCall.toolCallId);
    const label = t ? `${toolLabel(t).verb} ${toolLabel(t).target}`.trim() : toolCall.title || '';
    const id = inReq('session/request_permission', { sessionId: S.sessionId, toolCall, options }, `${label} · ${options.length} lựa chọn`);
    S.perm = { id, options, toolCallId: toolCall.toolCallId, label };
    if (t) {
      t.perm = { options, answer: null };
      renderTool(t);
    }
    renderPermBar();
    setStatus('needsInput');
    hood('trạng thái', 'A12: **Cần bạn trả lời** → sidebar ▲, viền vàng quanh pane, báo cho điện thoại');
    if (S.selectedTab !== 'ai') notify(`${S.agentName} cần bạn trả lời`, `${S.title}: ${label}`);
    else hood('thông báo', 'Không bật thông báo hệ thống: bạn đang nhìn pane này (quy tắc A4)');
    if (S.phone.on) {
      if (S.phone.attached) relay('down', 'ai.update', { id: 1, kind: 'permission', request: id, options: options.map((o) => o.optionId) }, `xin quyền: ${label}`);
      hood('thông báo', 'Đẩy “cần bạn trả lời” tới điện thoại (đường A4/A12 sẵn có), kèm nút trả lời ngay trên thông báo', 'Mới: nút Cho phép / Từ chối trên thông báo đẩy; điện thoại gửi lại ai.answer.');
      renderPhone();
    }
    stickBottom(true);
    return waitUser('perm');
  }

  function answerPerm(i) {
    const p = S.perm;
    if (!p || !p.options[i]) return;
    const o = p.options[i];
    outRes(p.id, 'session/request_permission', { outcome: { outcome: 'selected', optionId: o.optionId } }, `selected · ${o.optionId}`);
    const t = S.tools.get(p.toolCallId);
    if (t && t.perm) {
      t.perm.answer = o;
      if (o.kind.startsWith('reject')) t.rejected = true;
      renderTool(t);
    }
    S.perm = null;
    renderPermBar();
    setStatus('running');
    hood('trạng thái', `Bạn chọn “${KIND_VI[o.kind]}” → A12: **Đang chạy**`);
    unpause();
    fire('perm', o);
    renderPhone();
  }

  function answerReject() {
    if (!S.perm) return;
    const i = S.perm.options.findIndex((o) => o.kind.startsWith('reject'));
    if (i >= 0) answerPerm(i);
  }

  function agentAllows(kind, key) {
    const mode = S.cfg.mode;
    if (mode === 'bypassPermissions' || mode === 'auto') return true;
    if (mode === 'acceptEdits' && kind === 'edit') return true;
    return A.granted.has(`${kind}:*`) || A.granted.has(`${kind}:${key || '*'}`);
  }

  /* ------------------------------------------------------------- tools -- */

  const BOARD_COLS = [
    ['todo', 'Cần làm'],
    ['doing', 'Đang làm'],
    ['done', 'Xong'],
  ];

  /** The sample tool's page; desktop and phone render the same server state. */
  function boardHtml(attr) {
    const B = S.board;
    if (!B) return '';
    return `<div class="board">${BOARD_COLS.map(([k, name]) => {
      const cards = B.cards.filter((c) => c.col === k);
      return `<div class="bcol"><div class="bcol-h">${name}<span>${cards.length}</span></div>${cards
        .map((c) => `<button class="bcard${c.id === B.flash ? ' is-new' : ''}" ${attr}="${c.id}" title="Bấm để chuyển cột">${esc(c.text)}</button>`)
        .join('')}</div>`;
    }).join('')}</div>`;
  }

  function renderToolView() {
    const t = S.toolReg.find((x) => x.id === S.toolOpen);
    if (!t) {
      W.plg.innerHTML = '';
      return;
    }
    const local = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:|\/|$)/.test(t.url);
    W.plg.innerHTML = `<header class="tv-h">${svg('puzzle')}<b>${esc(t.name)}</b>
        <span class="tv-url${local ? ' is-local' : ''}" title="${local ? 'Trang trên máy này' : 'Trang không nằm trên máy này'}">${esc(hostOf(t.url))}</span>
        <span class="grow"></span>
        <button class="tv-phone${t.phone ? ' on' : ''}" data-tv="phone" aria-pressed="${t.phone}" title="Mở tool này trên điện thoại: ${t.phone ? 'đang bật' : 'đang tắt'} (qua relay, mã hoá đầu cuối)">${svg('phone')}<i>${t.phone ? 'bật' : 'tắt'}</i></button>
        <button class="ib sm" data-tv="reload" title="Tải lại">${svg('restart')}</button>
        <button class="ib sm" data-tv="close" title="Đóng pane tool">${svg('x')}</button></header>
      ${boardHtml('data-card')}
      <p class="plg-f">Trang của bạn ở <code>${esc(t.url)}</code>. ShellX chỉ hiển thị: không manifest, không cầu nối.</p>`;
  }

  function addTool(t, opts) {
    const id = 't' + (S.toolReg.length + 1);
    const url = /^https?:\/\//.test(t.url) ? t.url : 'http://' + t.url;
    S.toolReg.push({ id, name: t.name, url, phone: !!t.phone });
    if (!S.board) S.board = JSON.parse(JSON.stringify(DATA.board));
    hood('tệp', `Lưu tool “${t.name}” vào workspace shop-web`, JSON.stringify({ name: t.name, url, phone: !!t.phone }, null, 2));
    if (!opts || opts.open !== false) openTool(id);
    renderSidebar();
    renderPhone();
    return id;
  }

  function openTool(id) {
    const t = S.toolReg.find((x) => x.id === id);
    if (!t) return;
    S.toolOpen = id;
    S.layout.tool = true;
    S.layout.side = false;
    if (S.selectedTab !== 'ai' && S.aiTab) selectTab('ai');
    hood(
      'tệp',
      `Mở pane tool cạnh pane AI · ${hostOf(t.url)}`,
      'Engine trình duyệt của A6: WKWebView (macOS), WebView2 (Windows).\nhttp://localhost → chỉ báo “trang trên máy này”; cookie cô lập khỏi trình duyệt của bạn.',
    );
    renderPanes();
    renderToolView();
    renderSidebar();
  }

  function onToolBar(act) {
    const t = S.toolReg.find((x) => x.id === S.toolOpen);
    if (!t) return;
    if (act === 'close') {
      S.layout.tool = false;
      renderPanes();
      renderSidebar();
    } else if (act === 'reload') {
      S.board.flash = null;
      hood('tệp', `Tải lại ${hostOf(t.url)}`);
      renderToolView();
    } else if (act === 'phone') {
      t.phone = !t.phone;
      hood('tệp', t.phone ? `Cho mở “${t.name}” trên điện thoại` : `Thôi cho mở “${t.name}” trên điện thoại`, t.phone ? `Desktop sẽ proxy đúng ${t.url} cho điện thoại đã ghép đôi, qua relay mã hoá đầu cuối.` : 'Phiên đang mở trên điện thoại (nếu có) bị đóng ngay.');
      if (!t.phone && S.phone.tool === t.id) S.phone.screen = 'tools';
      renderToolView();
      renderSidebar();
      renderPhone();
      fire('tool-phone', t.phone);
    }
  }

  function moveCard(c) {
    c.col = c.col === 'todo' ? 'doing' : c.col === 'doing' ? 'done' : 'todo';
    S.board.flash = c.id;
    renderToolView();
    renderPhone();
  }

  async function openAddTool(pre) {
    const p = pre || {};
    const body = h('div', { class: 'addtool' });
    body.innerHTML = `<label class="fld"><span>Tên</span><input name="name" value="${esc(p.name || '')}" placeholder="Bảng việc"></label>
      <label class="fld"><span>URL</span><input name="url" value="${esc(p.url || '')}" placeholder="http://localhost:4000"></label>
      <div class="sugg"><span class="muted">Cổng đang chạy mà ShellX thấy:</span>${DATA.ports
        .map((x) => `<button type="button" class="sg" data-sg="${esc(x.url)}" data-sn="${esc(x.name)}">${esc(x.label)}</button>`)
        .join('')}</div>
      <label class="chk"><input type="checkbox" name="phone"${p.phone ? ' checked' : ''}><span>Cho mở trên điện thoại<small>Đi qua relay, mã hoá đầu cuối. Điện thoại chỉ tới được đúng URL này.</small></span></label>`;
    body.addEventListener('click', (ev) => {
      const b = ev.target.closest('[data-sg]');
      if (!b) return;
      body.querySelector('[name=url]').value = b.dataset.sg;
      const n = body.querySelector('[name=name]');
      if (!n.value) n.value = b.dataset.sn;
    });
    const ok = await dialog({
      title: 'Thêm tool',
      body,
      actions: [
        { label: 'Huỷ', value: false },
        { label: 'Thêm', value: true, kind: 'pri' },
      ],
    });
    if (!ok) return null;
    const url = body.querySelector('[name=url]').value.trim();
    if (!url) return null;
    return { name: body.querySelector('[name=name]').value.trim() || hostOf(url), url, phone: body.querySelector('[name=phone]').checked };
  }

  /* --------------------------------------------- small run sheet -- */

  /** Login and install commands run in a small sheet over the AI pane: the
   *  user sees the exact command, without a terminal pane in the tab. */
  function renderRun() {
    const r = S.runSheet;
    W.run.hidden = !r;
    if (!r) {
      W.run.innerHTML = '';
      return;
    }
    W.run.innerHTML = `<div class="rs-h">${svg(r.icon || 'key')}<b>${esc(r.title)}</b><span class="muted">${esc(r.sub || '')}</span><span class="grow"></span><button class="ib sm" data-act="run-close" title="Đóng">${svg('x')}</button></div>
      <pre class="rs-out">${r.lines.map(termLine).join('')}</pre>${r.note ? `<p class="rs-n">${inline(r.note)}</p>` : ''}`;
  }

  /* ------------------------------------------------------------- phone -- */

  /** One message between desktop and phone over the E2E relay channel.
   *  `ai.*` and `tool.*` are proposals; today's protocol has session.*,
   *  output/input and agent.state. */
  function relay(dir, type, payload, sum) {
    logPush({
      lane: 'relay',
      dir,
      kind: 'relay',
      method: type,
      sum,
      json: Object.assign({ t: type }, payload || {}),
      note: 'Tin trong kênh mã hoá đầu cuối giữa desktop và điện thoại (CBOR, khoá "t"; hiển thị dạng JSON). Loại tin này là **đề xuất**.',
    });
  }

  function waitFree(ms) {
    const token = R.token;
    return new Promise((resolve, reject) => {
      R.timers.push({ at: S.clock + ms, token, turn: null, resolve, reject });
    });
  }

  /** What the phone shows of the conversation (built from the same updates). */
  function mirror(u) {
    const M = S.mirror;
    const last = M[M.length - 1];
    if (u.sessionUpdate === 'agent_message_chunk') {
      if (last && last.k === 'agent') last.text += u.content.text;
      else M.push({ k: 'agent', text: u.content.text });
    } else if (u.sessionUpdate === 'user_message_chunk') {
      if (last && last.k === 'user' && last.replay) last.text += u.content.text;
      else M.push({ k: 'user', text: u.content.text, replay: true });
    } else if (u.sessionUpdate === 'tool_call') {
      M.push({ k: 'tool', id: u.toolCallId });
    }
  }

  const PH_STATE = { running: 'đang chạy', needsInput: 'cần bạn trả lời', idle: 'đang chờ', done: 'xong' };

  function phonePermButtons() {
    return S.perm.options.map((o, i) => `<button class="ph-pb k-${o.kind}" data-ph-perm="${i}">${KIND_VI[o.kind] || esc(o.name)}</button>`).join('');
  }

  function phoneList() {
    const ai =
      S.aiTab && S.sessionId
        ? `<button class="ph-row" data-ph-open="ai"><span class="ph-ic ai">${svg('spark')}</span><span class="ph-rt"><b>${esc(S.title)}</b><small class="${S.status === 'needsInput' ? 'warn' : ''}">Claude · ${PH_STATE[S.status] || 'chưa chạy'}</small></span>${svg('chev', 'r')}</button>`
        : '<p class="ph-empty">Chưa có phiên AI.</p>';
    return `<div class="ph-hd"><b>Phiên</b><small>MacBook của bạn</small></div>
      <div class="ph-sec">Phiên AI</div>${ai}
      <div class="ph-sec">Terminal</div>
      <div class="ph-row dim"><span class="ph-ic">${svg('term')}</span><span class="ph-rt"><b>dev server</b><small>zsh · npm run dev</small></span></div>
      <div class="ph-row dim"><span class="ph-ic">${svg('term')}</span><span class="ph-rt"><b>claude</b><small>Claude Code · đang chờ</small></span></div>`;
  }

  function phoneToolList() {
    const shared = S.toolReg.filter((t) => t.phone);
    const off = S.toolReg.length - shared.length;
    return (
      `<div class="ph-hd"><b>Tool</b><small>tool bạn đã bật cho điện thoại</small></div>` +
      (shared.length
        ? shared
            .map(
              (t) =>
                `<button class="ph-row" data-ph-tool="${t.id}"><span class="ph-ic tool">${svg('puzzle')}</span><span class="ph-rt"><b>${esc(t.name)}</b><small>${esc(hostOf(t.url))} · qua desktop</small></span>${svg('chev', 'r')}</button>`,
            )
            .join('')
        : '<p class="ph-empty">Chưa có tool nào bật cho điện thoại. Trên desktop: thanh của tool › Điện thoại: bật.</p>') +
      (off ? `<p class="ph-note">${off} tool chưa bật cho điện thoại.</p>` : '')
    );
  }

  function phoneToolStatus(t) {
    if (t.perm && !t.perm.answer) return `<i class="warn">${svg('warn')}</i>`;
    if (t.status === 'completed') return `<i class="ok">${svg('check')}</i>`;
    if (t.status === 'in_progress') return `<i class="run">${svg('dot')}</i>`;
    if (t.status === 'failed') return `<i class="err">${svg('x')}</i>`;
    return '';
  }

  function phoneAi() {
    const items = S.mirror
      .map((m) => {
        if (m.k === 'user') return `<div class="ph-u">${esc(m.text)}${m.via === 'phone' ? '<small>từ điện thoại</small>' : ''}</div>`;
        if (m.k === 'agent') return `<div class="ph-a md">${md(m.text)}</div>`;
        if (m.k === 'sum') return `<div class="ph-sum">${esc(m.text)}</div>`;
        const t = S.tools.get(m.id);
        if (!t) return '';
        const L = toolLabel(t);
        return `<div class="ph-t">${svg(L.mcp ? 'puzzle' : KIND_ICON[t.kind] || 'puzzle')}<span>${esc(L.verb)} <code>${esc(L.target || '')}</code></span>${phoneToolStatus(t)}</div>`;
      })
      .join('');
    const perm = S.perm
      ? `<div class="ph-perm"><b>${esc(S.agentName)} xin quyền</b><span>${esc(S.perm.label)}</span><div class="ph-perm-a">${phonePermButtons()}</div></div>`
      : '';
    return `<div class="ph-hd"><button class="ph-back" data-ph="list">‹ Phiên</button><b>${esc(S.title)}</b><small class="${S.status === 'needsInput' ? 'warn' : ''}">Claude · ${PH_STATE[S.status] || 'chưa chạy'}${S.turn ? ' · ' + fmtDur(S.clock - S.turn.start) : ''}</small></div>
      <div class="ph-conv">${items || '<p class="ph-empty">Chưa có tin nhắn.</p>'}${perm}</div>
      <div class="ph-comp"><input class="ph-in" placeholder="Nhắn cho Claude…" aria-label="Tin nhắn từ điện thoại"${S.ready ? '' : ' disabled'}><button class="ph-send" data-ph-send="1" title="Gửi">${svg('send')}</button></div>`;
  }

  function phoneTool() {
    const t = S.toolReg.find((x) => x.id === S.phone.tool);
    if (!t || !t.phone) return phoneToolList();
    return `<div class="ph-hd"><button class="ph-back" data-ph="tools">‹ Tool</button><b>${esc(t.name)}</b><small>${esc(hostOf(t.url))} · qua desktop</small></div>
      <div class="ph-web">${S.phone.loading ? '<p class="ph-empty">Đang tải qua đường hầm…</p>' : boardHtml('data-pcard')}</div>`;
  }

  function renderPhone() {
    const P = S.phone;
    W.stage.classList.toggle('has-phone', P.on);
    W.phone.hidden = !P.on;
    if (!P.on) {
      W.phone.innerHTML = '';
      return;
    }
    // P.draft follows typing (input listener) and phoneDraft(); never read it back here.
    const old = W.phone.querySelector('.ph-in');
    const focused = old && document.activeElement === old;
    const screen = P.screen === 'ai' ? phoneAi() : P.screen === 'tool' ? phoneTool() : P.screen === 'tools' ? phoneToolList() : phoneList();
    const banner =
      S.perm && P.screen !== 'ai'
        ? `<div class="ph-banner"><button class="ph-bn" data-ph-open="ai"><small>ShellX · bây giờ</small><b>${esc(S.agentName)} cần bạn trả lời</b><span>${esc(S.perm.label)}</span></button><div class="ph-perm-a">${phonePermButtons()}</div></div>`
        : '';
    const tabOn = (s) => (P.screen === s || (s === 'list' && P.screen === 'ai') || (s === 'tools' && P.screen === 'tool') ? 'true' : 'false');
    W.phone.innerHTML = `<div class="ph"><div class="ph-island"></div><div class="ph-status"><span>9:41</span><span class="ph-e2e" title="Kênh mã hoá đầu cuối với desktop">${svg('lock')}E2E</span></div>${banner}<div class="ph-screen">${screen}</div><nav class="ph-tabs"><button data-ph="list" aria-pressed="${tabOn('list')}">Phiên</button><button data-ph="tools" aria-pressed="${tabOn('tools')}">Tool</button></nav></div><p class="ph-cap">App ShellX trên điện thoại (mô phỏng) — nói chuyện với desktop qua relay, mã hoá đầu cuối.</p>`;
    const inp = W.phone.querySelector('.ph-in');
    if (inp) {
      inp.value = P.draft;
      if (focused) inp.focus({ preventScroll: true });
    }
    const conv = W.phone.querySelector('.ph-conv');
    if (conv) conv.scrollTop = conv.scrollHeight;
  }

  function phoneOn() {
    S.phone.on = true;
    hood('tiến trình', 'Điện thoại đã ghép đôi: desktop và điện thoại nói chuyện qua relay, mã hoá đầu cuối (như hôm nay)');
    relay('up', 'ai.list', {}, 'xin danh sách phiên AI');
    relay('down', 'ai.list.result', { sessions: S.sessionId ? [{ id: 1, title: S.title, agent: 'claude', state: 'idle' }] : [] }, S.sessionId ? '1 phiên AI' : 'chưa có phiên');
    renderPhone();
  }

  function phoneOpenAi() {
    const P = S.phone;
    P.screen = 'ai';
    if (!P.attached && S.sessionId) {
      P.attached = true;
      relay('up', 'ai.attach', { id: 1 }, 'mở phiên AI');
      relay('down', 'ai.snapshot', { id: 1, items: S.mirror.length, state: S.status }, `bản chụp: ${S.mirror.length} mục + trạng thái; sau đó là cập nhật trực tiếp`);
    }
    renderPhone();
    fire('ph-open-ai');
  }

  function phoneSend() {
    const inp = W.phone.querySelector('.ph-in');
    const text = (inp ? inp.value : S.phone.draft).trim();
    if (!text || !S.ready) return;
    S.phone.draft = '';
    if (inp) inp.value = '';
    relay('up', 'ai.prompt', { id: 1, text }, `“${clip(text, 50)}”`);
    if (S.turn) {
      queueMsg(text);
      renderPhone();
      return;
    }
    const msg = buildPrompt(text);
    msg.via = 'phone';
    addUser(msg);
    S.history.push({ sessionUpdate: 'user_message_chunk', content: { type: 'text', text } });
    unpause();
    if (!fire('phone-send', msg)) runDetached(() => genericTurn(msg));
    renderPhone();
  }

  function phoneAnswer(i) {
    const p = S.perm;
    if (!p || !p.options[i]) return;
    const o = p.options[i];
    relay('up', 'ai.answer', { id: 1, request: p.id, option: o.optionId }, `${KIND_VI[o.kind]} · ${o.optionId}`);
    answerPerm(i);
  }

  function phoneOpenTool(id) {
    const t = S.toolReg.find((x) => x.id === id);
    if (!t || !t.phone) return;
    S.phone.screen = 'tool';
    S.phone.tool = id;
    S.phone.loading = true;
    renderPhone();
    runDetached(async () => {
      relay('up', 'tool.open', { tool: id }, t.name);
      hood('tiến trình', `Desktop mở proxy cho đúng ${hostOf(t.url)} — tool đã bật cho điện thoại`, 'Request tới URL khác bị từ chối. Điện thoại mở một cổng loopback cho webview; mọi byte đi qua kênh mã hoá đầu cuối, relay không đọc được.');
      relay('up', 'tool.http', { tool: id, stream: 1, method: 'GET', path: '/' }, 'GET /');
      await waitFree(350);
      relay('down', 'tool.http', { stream: 1, status: 200, bytes: 48213, frames: 1 }, '200 · 47 KB · 1 khung');
      relay('up', 'tool.http', { tool: id, stream: 2, method: 'GET', path: '/app.js' }, 'GET /app.js');
      await waitFree(300);
      relay('down', 'tool.http', { stream: 2, status: 200, bytes: 196608, frames: 4 }, '200 · 192 KB · 4 khung 64 KiB');
      S.phone.loading = false;
      renderPhone();
      fire('ph-open-tool');
    });
  }

  function phoneCard(id) {
    const c = S.board && S.board.cards.find((x) => x.id === id);
    if (!c) return;
    runDetached(async () => {
      relay('up', 'tool.http', { stream: 3, method: 'POST', path: `/api/cards/${id}/move` }, `POST /api/cards/${id}/move`);
      await waitFree(250);
      moveCard(c);
      relay('down', 'tool.http', { stream: 3, status: 200, bytes: 512, frames: 1 }, '200');
      hood('tệp', 'Pane tool trên desktop thấy ngay: cả hai cùng nói chuyện với một server của tool');
      fire('ph-card');
    });
  }

  /* --------------------------------------------------- popups & menus -- */

  function autoGrow() {
    W.ta.style.height = 'auto';
    W.ta.style.height = Math.min(W.ta.scrollHeight, 140) + 'px';
  }

  function closePop() {
    if (!S || !S.pop) return;
    S.pop = null;
    W.pop.hidden = true;
    W.pop.innerHTML = '';
  }

  function updatePop() {
    const v = W.ta.value;
    const caret = W.ta.selectionStart;
    const before = v.slice(0, caret);
    const at = /(^|\s)@([\w./-]*)$/.exec(before);
    const sl = /^\/([\w-]*)$/.exec(before);
    let items = null;
    let type = null;
    let q = '';
    if (at) {
      type = 'at';
      q = at[2].toLowerCase();
      items = Object.keys(S.fs)
        .filter((p) => !isIgnored(p) && p.toLowerCase().includes(q))
        .slice(0, 7)
        .map((p) => ({ label: p, desc: '' }));
    } else if (sl) {
      type = 'slash';
      q = sl[1].toLowerCase();
      items = S.commands.filter((c) => c.name.toLowerCase().startsWith(q)).map((c) => ({ label: '/' + c.name, desc: c.description, hint: c.input ? c.input.hint : '' }));
    }
    if (!items || !items.length) {
      closePop();
      return;
    }
    const sel = S.pop && S.pop.type === type ? Math.min(S.pop.sel, items.length - 1) : 0;
    S.pop = { type, items, sel, q };
    W.pop.hidden = false;
    W.pop.innerHTML =
      `<div class="pop-t">${type === 'at' ? 'Nhắc tệp — gửi kèm dưới dạng resource_link' : 'Lệnh do agent gửi (available_commands_update)'}</div>` +
      items
        .map((it, i) => `<button class="pop-i${i === sel ? ' is-sel' : ''}" data-pop="${i}">${type === 'at' ? svg('file') : svg('slash')}<b>${esc(it.label)}</b>${it.desc ? `<small>${esc(it.desc)}</small>` : ''}</button>`)
        .join('');
  }

  function pickPop(i) {
    const p = S.pop;
    if (!p) return;
    const it = p.items[i];
    const v = W.ta.value;
    const caret = W.ta.selectionStart;
    const before = v.slice(0, caret);
    const after = v.slice(caret);
    // "/cmd" only matches at the very start, so it replaces everything before the caret.
    const rep = p.type === 'at' ? before.replace(/@([\w./-]*)$/, '@' + it.label + ' ') : it.label + ' ';
    W.ta.value = rep + after;
    W.ta.setSelectionRange(rep.length, rep.length);
    closePop();
    autoGrow();
    renderSend();
    W.ta.focus({ preventScroll: true });
  }

  function openHistory(anchor) {
    if (!S.ready) {
      toast('Agent chưa chạy — không lấy được lịch sử phiên.');
      return;
    }
    const id = out('session/list', { cwd: DATA.cwd }, 'các phiên của ~/code/shop-web');
    const sessions = DATA.sessions(S.sessionId, S.title);
    inRes(id, 'session/list', { sessions }, `${sessions.length} phiên`);
    openMenu(
      anchor,
      sessions.map((s) => ({ label: s.title, desc: `${s.sessionId === S.sessionId ? 'phiên hiện tại · ' : ''}${new Date(s.updatedAt).toLocaleString('vi-VN')}`, checked: s.sessionId === S.sessionId, value: s.sessionId })),
      (it) => {
        if (it.value !== S.sessionId) toast('Mở phiên này = gọi `session/load` với id của nó. Demo không có nội dung phiên đó.');
      },
      { title: 'Lịch sử phiên (session/list) · do agent lưu' },
    );
    fire('history');
  }

  function openMore(anchor) {
    openMenu(
      anchor,
      [
        { label: 'Cài đặt › Agents…', desc: 'Trạng thái agent, cài đặt, đăng nhập', value: 'settings' },
        { label: 'Khởi động lại agent', desc: 'Dừng rồi chạy lại, nạp lại phiên bằng session/load', value: 'restart', disabled: !S.process },
        { label: 'Xem log agent', desc: 'stderr giữ trong bộ nhớ, không ghi ra đĩa', value: 'log' },
        { label: 'Hiện terminal của tab', desc: 'Tab AI ẩn sẵn terminal; bật khi bạn cần', value: 'term' },
        { sep: true },
        { label: 'Thêm tool…', desc: 'Tên + URL (vd http://localhost:4000)', value: 'tool' },
      ],
      (it) => {
        if (it.value === 'settings') openSettings();
        else if (it.value === 'log') showLog();
        else if (it.value === 'term') setLayout({ term: true, zoom: false });
        else if (it.value === 'tool') onAct('add-tool');
        else if (it.value === 'restart') {
          if (!fire('restart')) runDetached(restartAgent);
        }
      },
    );
  }

  async function restartAgent() {
    stopAgent('Khởi động lại theo yêu cầu.');
    await spawnAgent({ pid: 48377 });
    await initialize();
    await loadSession({ history: historyForReplay() });
  }

  function showLog() {
    const e = S.lastCrash;
    dialog({
      title: 'Log của agent (stderr)',
      body: `<p class="muted">Chỉ giữ trong bộ nhớ cho mục này; ShellX không ghi nội dung của agent vào log của mình.</p><pre class="hd">${esc(e ? e.stderr : '(trống)')}</pre>`,
      actions: [{ label: 'Đóng', value: true, kind: 'pri' }],
      wide: true,
    });
  }

  function agentRow(a) {
    const st = {
      ready: ['ok', 'Sẵn sàng'],
      login: ['warn', 'Chưa đăng nhập'],
      missing: ['warn', 'Chưa cài adapter'],
      notfound: ['muted', 'Chưa cài'],
      node: ['warn', 'Thiếu Node 22'],
    }[a.status] || ['muted', a.status];
    const btn =
      a.status === 'missing'
        ? `<button class="btn sm sec" data-ag="install" data-id="${a.id}">Cài đặt…</button>`
        : a.status === 'login'
          ? `<button class="btn sm sec" data-ag="login" data-id="${a.id}">Đăng nhập…</button>`
          : a.status === 'notfound'
            ? `<button class="btn sm sec" data-ag="guide" data-id="${a.id}">Hướng dẫn</button>`
            : '';
    return `<div class="ag"><div class="ag-n"><b>${esc(a.name)}</b><small>${esc(a.how)}</small><small>${esc(a.need)}</small></div><span class="ag-s s-${st[0]}">${st[1]}</span>${btn}</div>`;
  }

  async function openSettings() {
    const body = h('div', { class: 'ags' });
    const paint = () => {
      body.innerHTML = `<p class="muted">Mục mới trong <b>Cài đặt › Agents</b>. Lệnh cài đặt và đăng nhập luôn chạy trong một pane terminal để bạn thấy rõ nó làm gì.</p>
        ${S.agents.map(agentRow).join('')}
        <div class="ag ag-add"><div class="ag-n"><b>Agent tuỳ chỉnh</b><small>Bất kỳ agent nào nói ACP: nhập lệnh và tham số để chạy nó.</small></div><button class="btn sm sec" data-ag="custom">Thêm…</button></div>
        <p class="muted sm">Agent mặc định cho “Phiên AI mới”: <b>Claude Code</b></p>`;
    };
    paint();
    body.addEventListener('click', async (ev) => {
      const b = ev.target.closest('[data-ag]');
      if (!b) return;
      const a = S.agents.find((x) => x.id === b.dataset.id);
      if (b.dataset.ag === 'install' && a) {
        closeDialog();
        S.runSheet = {
          icon: 'term',
          title: `Cài adapter ${a.name}`,
          sub: 'bạn thấy đúng lệnh ShellX chạy',
          lines: [
            { t: `$ npm install --prefix "${DATA.agentsDir}" ${a.pkg}`, c: 'cmd' },
            { t: '✓ xong (mã thoát 0)', c: 'ok' },
          ],
          note: `**${a.name}: Sẵn sàng.** Bản ghim; ShellX chỉ nâng phiên bản sau khi đã test.`,
        };
        renderRun();
        a.status = 'ready';
        hood('tiến trình', `Cài ${a.pkg} (bản ghim) vào thư mục riêng của ShellX`, `npm install --prefix "${DATA.agentsDir}" ${a.pkg}\nChỉ nâng phiên bản sau khi đã test với ShellX.`);
      } else if (b.dataset.ag === 'login' && a) {
        closeDialog();
        S.runSheet = {
          icon: 'key',
          title: `Đăng nhập ${a.name}`,
          sub: 'màn đăng nhập của chính agent',
          lines: [
            { t: `$ ${a.loginCmd}`, c: 'cmd' },
            { t: '(màn đăng nhập của agent chạy ở đây — ShellX không đọc, không lưu gì)', c: 'dim' },
          ],
          note: '',
        };
        renderRun();
        a.status = 'ready';
      } else if (b.dataset.ag === 'guide') {
        toast('Mở trang hướng dẫn cài đặt của agent (trình duyệt).');
      } else if (b.dataset.ag === 'custom') {
        toast('Agent tuỳ chỉnh: tên + lệnh + tham số + biến môi trường. ShellX thử `initialize` để kiểm.');
      }
    });
    await dialog({ title: 'Cài đặt › Agents · Pane AI', body, actions: [{ label: 'Đóng', value: true, kind: 'pri' }], wide: true });
  }

  /** First run: how should a new tab open? Kept in Settings › General. */
  async function chooseStart() {
    const body = h('div', { class: 'ob' });
    body.innerHTML = `<p class="muted">Đổi lại được bất cứ lúc nào trong Cài đặt › Chung.</p>
      <button class="ob-c" data-ob="ai">${svg('spark')}<span><b>Giao diện AI</b><small>Tab mới là một phiên AI: trò chuyện, xem agent làm gì, duyệt thay đổi — không cần gõ lệnh.</small></span></button>
      <button class="ob-c" data-ob="terminal">${svg('term')}<span><b>Terminal</b><small>Như ShellX hiện nay: tab mới là một shell.</small></span></button>`;
    const p = dialog({ title: 'Bạn muốn làm việc theo kiểu nào?', body, actions: [{ label: 'Để sau', value: null }] });
    body.addEventListener('click', (ev) => {
      const b = ev.target.closest('[data-ob]');
      if (b && S.dialogDone) {
        unpause();
        S.dialogDone(b.dataset.ob);
      }
    });
    return p;
  }

  async function pickAgent() {
    const body = h('div', { class: 'ags pick' });
    body.innerHTML = S.agents
      .map((a) => `<button class="ag-pick" data-pick="${a.id}"${a.status === 'ready' || a.id === 'claude' ? '' : ' disabled'}>${svg('spark')}<span><b>${esc(a.name)}</b><small>${a.status === 'ready' || a.id === 'claude' ? 'Sẵn sàng để chạy' : 'Cần cài đặt — xem Cài đặt › Agents'}</small></span></button>`)
      .join('');
    const p = dialog({ title: 'Phiên AI mới — chọn agent', body, actions: [{ label: 'Huỷ', value: null }] });
    body.addEventListener('click', (ev) => {
      const b = ev.target.closest('[data-pick]');
      if (b && !b.disabled && S.dialogDone) S.dialogDone(b.dataset.pick);
    });
    return p;
  }

  /* ------------------------------------------------------------ events -- */

  function bind() {
    root.addEventListener('click', (ev) => {
      const el = ev.target.closest(
        '[data-scen],[data-ctl],[data-speed],[data-lf],[data-log],[data-tab],[data-act],[data-ai],[data-cmp],[data-cfg],[data-perm],[data-tool],[data-file],[data-editor],[data-chg],[data-revert-file],[data-side],[data-scope],[data-sh],[data-pop],[data-unqueue],[data-unattach],[data-card],[data-opentool],[data-tv],[data-ph],[data-ph-open],[data-ph-tool],[data-ph-perm],[data-ph-send],[data-pcard]',
      );
      if (S && S.menu && !ev.target.closest('.win-menu')) closeMenu();
      if (!el || !S) return;
      const d = el.dataset;
      if (d.scen) return start(d.scen);
      if (d.ctl === 'restart') return start(current);
      if (d.ctl === 'pause') {
        R.paused = !R.paused;
        return renderControls();
      }
      if (d.ctl === 'step') {
        R.stepOnce = true;
        R.paused = false;
        return renderControls();
      }
      if (d.speed) {
        R.speed = +d.speed;
        return renderControls();
      }
      if (d.lf) {
        S.logFilter[d.lf] = !S.logFilter[d.lf];
        return renderControls();
      }
      if (d.log != null) {
        const e = S.log[+d.log];
        if (e) {
          e.open = !e.open;
          renderLogRow(e, false);
        }
        return;
      }
      if (d.tab) return selectTab(d.tab);
      if (d.act) return onAct(d.act, el);
      if (d.ai === 'history') return openHistory(el);
      if (d.ai === 'side') return setLayout({ side: !S.layout.side });
      if (d.ai === 'zoom') {
        setLayout({ zoom: !S.layout.zoom });
        return hood('tệp', S.layout.zoom ? 'Phóng to pane AI (ẩn các pane khác của tab)' : 'Bỏ phóng to');
      }
      if (d.ai === 'term') {
        setLayout({ term: !S.layout.term, zoom: false });
        return hood('tệp', S.layout.term ? 'Hiện terminal của tab (tab AI ẩn sẵn terminal)' : 'Ẩn terminal của tab');
      }
      if (d.ai === 'more') return openMore(el);
      if (d.cmp === 'at' || d.cmp === 'slash') {
        if (W.ta.disabled) return;
        const ch = d.cmp === 'at' ? (W.ta.value && !/\s$/.test(W.ta.value) ? ' @' : '@') : '/';
        if (d.cmp === 'slash') W.ta.value = '/';
        else W.ta.value += ch;
        W.ta.focus({ preventScroll: true });
        W.ta.setSelectionRange(W.ta.value.length, W.ta.value.length);
        return updatePop();
      }
      if (d.cmp === 'img') {
        if (W.ta.disabled) return;
        S.attachments.push({ name: `anh-chup-${S.attachments.length + 1}.png` });
        return renderAttach();
      }
      if (d.cfg) {
        const o = S.configOptions.find((x) => x.id === d.cfg);
        if (!o) return;
        return openMenu(
          el,
          o.options.map((x) => ({
            label: o.id === 'mode' ? (MODE_VI[x.value] || [x.name])[0] : x.name,
            desc: o.id === 'mode' ? `${(MODE_VI[x.value] || ['', ''])[1]} · agent: ${x.name}${x.description ? ' — ' + x.description : ''}` : x.description || '',
            checked: x.value === o.currentValue,
            danger: x.value === 'bypassPermissions',
            value: x.value,
          })),
          (it) => runDetached(() => setConfig(o.id, it.value)),
          { title: `${o.name} · do agent gửi (configOptions)` },
        );
      }
      if (d.perm != null) return answerPerm(+d.perm);
      if (d.tool) {
        const t = S.tools.get(d.tool);
        if (!t) return;
        if (t.kind === 'read' && t.locations[0]) {
          S.sheet = { type: 'file', path: rel(t.locations[0].path), line: t.locations[0].line };
          return renderSheet();
        }
        if (!expandable(t)) return;
        t.open = !t.open;
        return renderTool(t);
      }
      if (d.file) {
        S.sheet = { type: 'file', path: d.file, line: null };
        return renderSheet();
      }
      if (d.editor) return openInEditor(d.editor);
      if (d.chg) {
        S.sheet = { type: 'diff', path: d.chg };
        return renderSheet();
      }
      if (d.revertFile) return runDetached(() => revertScope(d.revertFile));
      if (d.side) {
        S.sideTab = d.side;
        if (!S.layout.side) setLayout({ side: true });
        return renderSide();
      }
      if (d.scope) {
        S.scope = d.scope;
        renderSide();
        return renderSheet();
      }
      if (d.sh === 'close') {
        S.sheet = null;
        return renderSheet();
      }
      if (d.sh === 'editor') return openInEditor(S.sheet.path, S.sheet.line);
      if (d.sh === 'mention') {
        const p = S.sheet.path;
        S.sheet = null;
        renderSheet();
        if (!W.ta.disabled) {
          W.ta.value = (W.ta.value ? W.ta.value.replace(/\s*$/, ' ') : '') + '@' + p + ' ';
          autoGrow();
          renderSend();
          W.ta.focus({ preventScroll: true });
        }
        return;
      }
      if (d.pop != null) return pickPop(+d.pop);
      if (d.unqueue != null) {
        S.queue.splice(+d.unqueue, 1);
        return renderQueue();
      }
      if (d.unattach != null) {
        S.attachments.splice(+d.unattach, 1);
        return renderAttach();
      }
      if (d.card) {
        const c = S.board && S.board.cards.find((x) => x.id === d.card);
        if (!c) return;
        moveCard(c);
        return hood('tệp', 'Tool tự xử lý cú bấm (vd `POST /api/cards/…`) — ShellX không can thiệp');
      }
      if (d.opentool) return openTool(d.opentool);
      if (d.tv) return onToolBar(d.tv);
      if (d.ph) {
        S.phone.screen = d.ph;
        return renderPhone();
      }
      if (d.phOpen) return phoneOpenAi();
      if (d.phTool) return phoneOpenTool(d.phTool);
      if (d.phPerm != null) return phoneAnswer(+d.phPerm);
      if (d.phSend) return phoneSend();
      if (d.pcard) return phoneCard(d.pcard);
    });

    // The phone's message box: Enter sends (not while an IME is composing).
    root.addEventListener('keydown', (ev) => {
      if (ev.target.classList && ev.target.classList.contains('ph-in') && ev.key === 'Enter' && !ev.isComposing) {
        ev.preventDefault();
        phoneSend();
      }
    });
    root.addEventListener('input', (ev) => {
      if (ev.target.classList && ev.target.classList.contains('ph-in')) S.phone.draft = ev.target.value;
    });

    root.addEventListener('change', (ev) => {
      const cb = ev.target.closest('[data-rev]');
      if (!cb) return;
      const k = reviewKey(cb.dataset.rev);
      if (cb.checked) S.reviewed.add(k);
      else S.reviewed.delete(k);
      renderSide();
    });

    W.ta.addEventListener('input', () => {
      autoGrow();
      renderSend();
      updatePop();
    });
    W.ta.addEventListener('keydown', (ev) => {
      if (S.pop) {
        if (ev.key === 'ArrowDown' || ev.key === 'ArrowUp') {
          ev.preventDefault();
          S.pop.sel = (S.pop.sel + (ev.key === 'ArrowDown' ? 1 : -1) + S.pop.items.length) % S.pop.items.length;
          updatePop();
          return;
        }
        if ((ev.key === 'Enter' || ev.key === 'Tab') && !ev.isComposing) {
          ev.preventDefault();
          pickPop(S.pop.sel);
          return;
        }
        if (ev.key === 'Escape') {
          ev.preventDefault();
          ev.stopPropagation();
          closePop();
          return;
        }
      }
      // isComposing: Enter that ends a Telex/IME word must not send.
      if (ev.key === 'Enter' && !ev.shiftKey && !ev.isComposing) {
        ev.preventDefault();
        onSend();
      }
    });
    W.ta.addEventListener('blur', () => setTimeout(closePop, 150));
    // Keep the caret in the box while a suggestion is clicked.
    W.pop.addEventListener('mousedown', (ev) => ev.preventDefault());
    document.addEventListener('click', (ev) => {
      if (S && S.menu && !root.contains(ev.target)) closeMenu();
    });
    W.scroll.addEventListener('scroll', () => {
      S.stick = W.scroll.scrollHeight - W.scroll.scrollTop - W.scroll.clientHeight < 48;
    });
    W.send.addEventListener('click', onSend);

    document.addEventListener('keydown', (ev) => {
      if (!S || !(visible || root.contains(document.activeElement))) return;
      // The phone mock has its own controls; desktop shortcuts stay out of it.
      if (ev.target && ev.target.closest && ev.target.closest('.dm-phone')) return;
      const tag = ev.target && ev.target.tagName;
      const inTa = ev.target === W.ta;
      const elsewhere = !inTa && (/^(INPUT|TEXTAREA|SELECT)$/.test(tag) || (ev.target && ev.target.isContentEditable));
      if (ev.key === 'Escape') {
        if (S.dialogDone) {
          ev.preventDefault();
          return S.dialogDone(null);
        }
        if (S.menu) {
          ev.preventDefault();
          return closeMenu();
        }
        if (S.sheet) {
          ev.preventDefault();
          S.sheet = null;
          return renderSheet();
        }
        if (S.perm) {
          ev.preventDefault();
          return answerReject();
        }
        if (S.turn) {
          ev.preventDefault();
          return cancelTurn();
        }
        return;
      }
      if (S.perm && !S.dialogDone && /^[1-9]$/.test(ev.key) && !ev.metaKey && !ev.ctrlKey && !ev.altKey) {
        if (elsewhere || (inTa && W.ta.value.trim())) return;
        const i = +ev.key - 1;
        if (i < S.perm.options.length) {
          ev.preventDefault();
          answerPerm(i);
        }
      }
    });

    if ('IntersectionObserver' in window) {
      new IntersectionObserver(
        (es) => {
          for (const e of es) {
            visible = e.isIntersecting && e.intersectionRatio > 0.25;
            if (visible && !started) {
              started = true;
              start(current);
            }
          }
        },
        { threshold: [0, 0.25, 0.5] },
        // The frame, not the 940 px window inside it: on a narrow screen the
        // window overflows sideways and could never reach the threshold.
      ).observe(root.querySelector('.dm-winwrap'));
    } else {
      visible = true;
      started = true;
      start(current);
    }
  }

  function openInEditor(path, line) {
    hood('tệp', `Mở \`${path}${line ? ':' + line : ''}\` trong editor`, 'Dùng link-editor sẵn có (platform/editor_links.dart): VS Code, Cursor, Zed… theo cài đặt của bạn.');
    toast(`Mở \`${path}\` trong VS Code (mô phỏng)`);
  }

  function onAct(act) {
    if (act === 'plan') {
      S.planOpen = !S.planOpen;
      return renderPlan();
    }
    if (act === 'see-turn') {
      S.scope = 'turn';
      S.sideTab = 'changes';
      setLayout({ side: true });
      return renderSide();
    }
    if (act === 'revert-turn') {
      S.scope = 'turn';
      renderSide();
      return runDetached(() => revertScope(null));
    }
    if (act === 'revert-scope') return runDetached(() => revertScope(null));
    if (act === 'note') {
      W.note.hidden = true;
      return selectTab('ai');
    }
    if (act === 'reopen') return fire('reopen');
    if (act === 'new-ai') {
      if (fire('new-ai')) return;
      return toast('Demo có một tab AI. Kịch bản 3 cho thấy luồng tạo phiên mới từ đầu.');
    }
    if (act === 'resume') return fire('resume');
    if (act === 'add-tool') {
      if (fire('add-tool')) return;
      return runDetached(async () => {
        const t = await openAddTool({ name: 'Bảng việc', url: 'http://localhost:4000' });
        if (t) addTool(t);
      });
    }
    if (act === 'run-close') {
      S.runSheet = null;
      renderRun();
    }
  }

  /* --------------------------------------------------- scenario start -- */

  function start(id) {
    const sc = DATA.scenarios.find((s) => s.id === id) || DATA.scenarios[0];
    current = sc.id;
    R.token++;
    const old = R.timers;
    R.timers = [];
    for (const t of old) t.reject(new Stop());
    for (const w of R.waits.values()) w.reject(new Stop());
    R.waits.clear();
    R.paused = false;
    R.stepOnce = false;
    if (S && S.dialogDone) S.dialogDone(null);
    S = freshState();
    A.granted = new Set();
    W.conv.innerHTML = '';
    W.logList.innerHTML = '';
    W.ta.value = '';
    W.note.hidden = true;
    W.toast.hidden = true;
    W.menu.hidden = true;
    W.modal.hidden = true;
    closePop();
    autoGrow();
    renderAll();
    coach('');
    runDetached(() => sc.run(guard(R.token)));
  }

  /** The API for one run: once "Làm lại" or another scenario starts, every
   *  call from the old run throws Stop, so it can never touch the new state. */
  function guard(token) {
    const api = {};
    for (const [k, fn] of Object.entries(API)) {
      api[k] = (...args) => {
        if (token !== R.token) throw new Stop();
        return fn(...args);
      };
    }
    return api;
  }

  const API = {
    beat,
    wait,
    waitUser,
    hood,
    notice,
    toast,
    dialog,
    notify,
    setStatus,
    setTitle,
    setLayout,
    selectTab,
    focusPane,
    termPrint,
    spawnAgent,
    initialize,
    newSession,
    loadSession,
    stopAgent,
    historyForReplay,
    out,
    inRes,
    update,
    stream,
    ask,
    turn,
    write,
    grep,
    readNumbered,
    agentAllows,
    pickAgent,
    chooseStart,
    openSettings,
    showLog,
    openAddTool,
    addTool,
    openTool,
    relay,
    phoneOn,
    phoneDraft(text) {
      S.phone.draft = text;
      renderPhone();
    },
    runSheet(r) {
      S.runSheet = r;
      renderRun();
    },
    runPrint(lines) {
      if (!S.runSheet) return;
      S.runSheet.lines.push(...lines);
      renderRun();
    },
    grant: (kind, key) => A.granted.add(`${kind}:${key || '*'}`),
    crash: (code, stderr) => {
      hood('tiến trình', `Tiến trình agent thoát bất ngờ (mã ${code}) — stdout đóng giữa lượt`, 'session/prompt đang chờ sẽ không bao giờ có trả lời: ShellX tự kết thúc lượt.\nstderr được giữ trong bộ nhớ cho mục “Xem log”.');
      throw new Crash(code, stderr);
    },
    expectSend(prefill) {
      W.ta.value = prefill || '';
      autoGrow();
      renderSend();
      if (visible && (document.activeElement === document.body || !document.activeElement)) W.ta.focus({ preventScroll: true });
      return waitUser('send');
    },
    /** ShellX keeps no conversation text: after a restart the pane is empty. */
    clearConversation() {
      W.conv.innerHTML = '';
      S.block = null;
      S.tools.clear();
      S.mirror = [];
    },
    /** Shows a past turn at once (no log), as if it had happened earlier. */
    seedHistory(list) {
      for (const u of list) applyUpdate(u, false);
      endText(S.block);
      S.block = null;
    },
    state: () => S,
    set(fn) {
      fn(S);
      renderAll();
    },
    abs,
    rel,
  };

  build();
  window.ShellXDemo = {
    start(id) {
      started = true;
      start(id);
    },
    speed(n) {
      R.speed = n;
      if (S) renderControls();
    },
    scenarios: DATA.scenarios.map((s) => s.id),
  };
})();
