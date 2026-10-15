// ShellX Admin — vanilla JS, no dependencies. Served under a strict CSP:
// no inline scripts/styles. Every node is built with createElement + textContent — API data never goes through an HTML parser.

const $ = (id) => document.getElementById(id);
const field = (box, name) => box.querySelector(`[data-f="${name}"]`);

const nf = new Intl.NumberFormat('vi-VN');
const pf = new Intl.NumberFormat('vi-VN', { style: 'percent', maximumFractionDigits: 1 });
const dtf = new Intl.DateTimeFormat('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', second: '2-digit' });

const KINDS = {
  agent: { key: 'min_agent', label: 'Desktop' },
  mobile: { key: 'min_mobile', label: 'Mobile' },
};
const VIEWS = ['loading', 'disabled', 'login', 'dash'];
const TITLES = { loading: 'ShellX Admin', disabled: 'Chưa bật · ShellX Admin', login: 'Đăng nhập · ShellX Admin', dash: 'Tổng quan · ShellX Admin' };
const VERSION_RE = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

const state = { stats: null, settings: null, pending: {}, loadSeq: 0 };

// ---------- API ----------

class ApiError extends Error {
  constructor(status, code, message) {
    super(message || code || `HTTP ${status}`);
    this.status = status;
    this.code = code;
    this.serverMessage = message;
  }
}

async function api(method, path, body) {
  const init = { method, credentials: 'same-origin', cache: 'no-store', headers: { Accept: 'application/json' } };
  if (method !== 'GET') {
    init.headers['Content-Type'] = 'application/json';
    init.body = JSON.stringify(body ?? {});
  }
  let res;
  try {
    res = await fetch(path, init);
  } catch {
    throw new ApiError(0, 'network', '');
  }
  let data = null;
  if (res.status !== 204) {
    try { data = await res.json(); } catch { data = null; }
  }
  if (!res.ok) throw new ApiError(res.status, data?.error?.code ?? '', data?.error?.message ?? '');
  return data;
}

function errText(e) {
  if (!(e instanceof ApiError)) return 'Có lỗi không mong muốn. Tải lại trang rồi thử lại.';
  if (e.status === 0) return 'Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.';
  if (e.status === 403) return 'Bị từ chối (403). Hãy mở trang qua đúng địa chỉ admin.';
  if (e.status === 429) return 'Thử quá nhiều lần — thử lại sau 15 phút.';
  if (e.status === 503 && e.code === 'admin_disabled') return 'Admin chưa được bật trên máy chủ.';
  if (e.status >= 500) return `Lỗi máy chủ (${e.status}). Thử lại sau.`;
  return e.serverMessage ? `Lỗi ${e.status}: ${e.serverMessage}` : `Lỗi ${e.status}.`;
}

// ---------- helpers ----------

function parseVer(v) {
  const m = typeof v === 'string' ? /^(\d+)\.(\d+)\.(\d+)$/.exec(v.trim()) : null;
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null;
}

/** -1 / 0 / 1, or NaN when either side is not x.y.z. */
function cmpVer(a, b) {
  const x = parseVer(a);
  const y = parseVer(b);
  if (!x || !y) return NaN;
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1;
  return 0;
}

const num = (n) => (typeof n === 'number' && Number.isFinite(n) ? nf.format(n) : '—');

function fmtTime(ms) {
  const d = new Date(ms);
  return Number.isNaN(d.getTime()) ? '—' : dtf.format(d);
}

/** "2026-09-16" → "16/09" (UTC day string, no timezone shift). */
function fmtDay(day) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(day));
  return m ? `${m[3]}/${m[2]}` : String(day ?? '');
}

function isHttps(url) {
  if (typeof url !== 'string') return false;
  try { return new URL(url).protocol === 'https:'; } catch { return false; }
}

function h(tag, opts = {}, ...children) {
  const el = document.createElement(tag);
  if (opts.className) el.className = opts.className;
  if (opts.text != null) el.textContent = opts.text;
  for (const c of children) if (c != null) el.append(c);
  return el;
}

const badge = (text, tone) => h('span', { className: `badge ${tone}`, text });

let statusTimer = 0;
function say(msg, kind = 'info') {
  const el = $('status');
  clearTimeout(statusTimer);
  el.dataset.kind = kind;
  el.textContent = msg;
  if (msg && kind !== 'error') statusTimer = setTimeout(() => { el.textContent = ''; }, 6000);
}

function show(name, { focus = true } = {}) {
  for (const v of VIEWS) $(`view-${v}`).hidden = v !== name;
  $('top-actions').hidden = name !== 'dash';
  document.title = TITLES[name];
  if (!focus) return;
  if (name === 'login') $('password').focus();
  else $(`h-${name}`).focus();
}

// ---------- flows ----------

async function boot() {
  state.loadSeq++;
  say('');
  show('loading', { focus: false });
  $('btn-retry').hidden = true;
  let s;
  try {
    s = await api('GET', '/api/session');
  } catch (e) {
    say(errText(e), 'error');
    $('btn-retry').hidden = false;
    return;
  }
  if (!s?.enabled) return show('disabled');
  if (!s.signed_in) return show('login');
  await enterDash();
}

async function enterDash() {
  show('loading', { focus: false });
  $('btn-retry').hidden = true;
  const ok = await loadDash();
  if (ok) show('dash');
  else if (!$('view-loading').hidden) $('btn-retry').hidden = false;
}

function toLogin(msg) {
  state.loadSeq++;
  state.stats = null;
  state.settings = null;
  for (const kind of Object.keys(KINDS)) hideConfirm(kind);
  show('login');
  say(msg || '');
}

function handleError(e) {
  if (e instanceof ApiError && e.status === 401) return toLogin('Phiên đăng nhập đã hết hạn — đăng nhập lại.');
  if (e instanceof ApiError && e.status === 503 && e.code === 'admin_disabled') {
    state.loadSeq++;
    show('disabled');
    return;
  }
  say(errText(e), 'error');
}

function setBusy(busy) {
  $('btn-refresh').disabled = busy;
  $('view-dash').setAttribute('aria-busy', String(busy));
}

/** Loads stats + settings in parallel and renders. Resolves true on success. */
async function loadDash({ announce = false } = {}) {
  const seq = ++state.loadSeq;
  setBusy(true);
  try {
    const [stats, settings] = await Promise.all([api('GET', '/api/stats'), api('GET', '/api/settings')]);
    if (seq !== state.loadSeq) return false;
    state.stats = stats ?? {};
    state.settings = settings ?? {};
    render();
    if (announce) say('Đã làm mới.', 'ok');
    else if ($('status').dataset.kind === 'error') say('');
    return true;
  } catch (e) {
    if (seq === state.loadSeq) handleError(e);
    return false;
  } finally {
    if (seq === state.loadSeq) setBusy(false);
  }
}

async function onLogin(ev) {
  ev.preventDefault();
  const input = $('password');
  const err = $('login-error');
  const btn = $('btn-login');
  if (btn.disabled) return;
  if (!input.value) {
    err.textContent = 'Nhập mật khẩu.';
    input.setAttribute('aria-invalid', 'true');
    input.focus();
    return;
  }
  err.textContent = '';
  input.removeAttribute('aria-invalid');
  btn.disabled = true;
  btn.textContent = 'Đang đăng nhập…';
  try {
    await api('POST', '/api/login', { password: input.value });
    input.value = '';
    say('');
    await enterDash();
    if (!$('view-login').hidden) {
      // Login answered 204 but the very next call was 401: the browser dropped the session cookie.
      say('');
      err.textContent = 'Đăng nhập được nhưng trình duyệt không giữ phiên (cookie). Hãy mở trang qua HTTPS.';
    }
  } catch (e) {
    if (e instanceof ApiError && e.status === 503 && e.code === 'admin_disabled') {
      show('disabled');
      return;
    }
    let msg;
    if (e instanceof ApiError && e.status === 401) msg = 'Sai mật khẩu.';
    else if (e instanceof ApiError && e.status === 429) msg = 'Sai quá nhiều lần — thử lại sau 15 phút.';
    else msg = errText(e);
    err.textContent = msg;
    if (e instanceof ApiError && e.status === 401) input.setAttribute('aria-invalid', 'true');
    input.focus();
    input.select();
  } finally {
    btn.disabled = false;
    btn.textContent = 'Đăng nhập';
  }
}

async function onLogout() {
  const btn = $('btn-logout');
  btn.disabled = true;
  try {
    await api('POST', '/api/logout', {});
  } catch (e) {
    if (!(e instanceof ApiError && e.status === 401)) {
      say(errText(e), 'error');
      return;
    }
  } finally {
    btn.disabled = false;
  }
  toLogin('Đã đăng xuất.');
}

// ---------- render ----------

function render() {
  const st = state.stats;
  const se = state.settings;

  const t = $('generated-at');
  t.textContent = fmtTime(st.generated_at);
  if (Number.isFinite(st.generated_at)) t.dateTime = new Date(st.generated_at).toISOString();

  const u = st.users ?? {};
  $('k-users').textContent = num(u.total);
  $('k-users-new').textContent = `+${num(u.new_24h)} / 24 giờ · +${num(u.new_7d)} / 7 ngày · +${num(u.new_30d)} / 30 ngày`;
  $('k-active7').textContent = num(u.active_7d);
  $('k-active30').textContent = `30 ngày: ${num(u.active_30d)}`;

  renderDevices('agent', st.devices?.agent, [['macos', 'macOS'], ['windows', 'Windows']]);
  renderDevices('mobile', st.devices?.mobile, [['ios', 'iOS'], ['android', 'Android']]);
  renderChart(Array.isArray(st.signups_by_day) ? st.signups_by_day : []);

  for (const [kind, { key }] of Object.entries(KINDS)) {
    const rows = Array.isArray(st.versions?.[kind]) ? st.versions[kind] : [];
    renderVersions(kind, rows, se[key]?.value);
    renderSetting(kind);
  }
  renderLatest(se.latest_agent);
}

function renderDevices(kind, d, platforms) {
  $(`k-${kind}`).textContent = num(d?.total);
  const online = d?.online;
  $(`k-${kind}-online`).textContent = online == null ? '—' : num(online);
  $(`k-${kind}-dot`).classList.toggle('off', !(online > 0));
  const by = d?.by_platform;
  $(`k-${kind}-split`).textContent = platforms
    .map(([k, label]) => `${label} ${by ? num(by[k] ?? 0) : '—'}`)
    .join(' · ');
}

function renderChart(days) {
  const svg = $('signups-svg');
  const NS = svg.namespaceURI;
  const W = 300;
  const H = 100;
  const TOP = 4;
  const svgEl = (tag, attrs) => {
    const el = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, String(v));
    return el;
  };
  svg.replaceChildren();
  const tbody = $('signups-table').tBodies[0];
  tbody.replaceChildren();

  const counts = days.map((d) => Math.max(0, Number(d?.count) || 0));
  const max = counts.length ? Math.max(...counts) : 0;
  const total = counts.reduce((a, b) => a + b, 0);

  $('signups-total').textContent = `Tổng: ${nf.format(total)}`;
  $('signups-max').textContent = max ? `Cao nhất: ${nf.format(max)} / ngày` : 'Chưa có đăng ký nào trong 30 ngày.';
  $('signups-from').textContent = days.length ? fmtDay(days[0].day) : '';
  $('signups-to').textContent = days.length > 1 ? fmtDay(days[days.length - 1].day) : '';
  if (!days.length) return;

  if (max) svg.append(svgEl('line', { class: 'grid', x1: 0, x2: W, y1: TOP, y2: TOP, 'vector-effect': 'non-scaling-stroke' }));

  const slot = W / days.length;
  const bw = slot * 0.7;
  days.forEach((d, i) => {
    const c = counts[i];
    const bh = max ? Math.max(c ? 2 : 1, (c / max) * (H - TOP)) : 1;
    const cls = c === 0 ? 'day zero' : c === max ? 'day peak' : 'day';
    const g = svgEl('g', { class: cls });
    const title = svgEl('title', {});
    title.textContent = `${fmtDay(d.day)}: ${nf.format(c)} đăng ký`;
    g.append(
      title,
      svgEl('rect', { class: 'hit', x: i * slot, y: 0, width: slot, height: H }),
      svgEl('rect', { class: 'bar', x: i * slot + (slot - bw) / 2, y: H - bh, width: bw, height: bh, rx: 0.8 }),
    );
    svg.append(g);
    tbody.append(h('tr', {}, h('td', { text: fmtDay(d.day) }), h('td', { text: nf.format(c) })));
  });
}

function renderVersions(kind, rows, min) {
  const table = $(`ver-${kind}`);
  field(table, 'min').textContent = min ?? '—';
  const tbody = table.tBodies[0];
  tbody.replaceChildren();
  const total = rows.reduce((s, r) => s + (Number(r?.count) || 0), 0);

  if (!rows.length) {
    const td = h('td', { className: 'empty', text: 'Chưa có thiết bị nào.' });
    td.colSpan = 3;
    tbody.append(h('tr', {}, td));
  }
  for (const r of rows) {
    const count = Number(r?.count) || 0;
    const tr = h('tr');
    const cell = h('td');
    if (r?.version == null) {
      tr.className = 'unknown';
      cell.append('Không rõ (bản cũ) ', badge('có thể bị chặn', 'muted'));
    } else {
      cell.append(h('code', { text: String(r.version) }));
      if (min != null && cmpVer(r.version, min) < 0) {
        tr.className = 'blocked';
        cell.append(' ', badge('sẽ bị chặn', 'err'));
      }
    }
    tr.append(cell, h('td', { className: 'num', text: nf.format(count) }), h('td', { className: 'num', text: total ? pf.format(count / total) : '—' }));
    tbody.append(tr);
  }

  const sum = $(`ver-${kind}-sum`);
  if (!rows.length || min == null) {
    sum.textContent = '';
    return;
  }
  const { below, unknown } = blockedCount(kind, min);
  sum.textContent = `Dưới mức tối thiểu ${min}: ${nf.format(below)}/${nf.format(total)} thiết bị` +
    (unknown ? ` (+${nf.format(unknown)} không rõ phiên bản).` : '.');
}

function blockedCount(kind, target) {
  const rows = state.stats?.versions?.[kind];
  let below = 0;
  let unknown = 0;
  let total = 0;
  for (const r of Array.isArray(rows) ? rows : []) {
    const c = Number(r?.count) || 0;
    total += c;
    if (r?.version == null) unknown += c;
    else if (cmpVer(r.version, target) < 0) below += c;
  }
  return { below, unknown, total };
}

function renderSetting(kind) {
  const box = $(`set-${kind}`);
  const s = state.settings?.[KINDS[kind].key];
  field(box, 'value').textContent = s?.value ?? '—';
  field(box, 'env').textContent = s?.env ?? '—';
  field(box, 'badge').hidden = !s?.overridden;
  field(box, 'reset').hidden = !s?.overridden;
  hideConfirm(kind);
}

function renderLatest(l) {
  $('latest-version').textContent = l?.version || '—';
  const ul = $('latest-links');
  ul.replaceChildren();
  for (const [label, url] of [['macOS', l?.mac_url], ['Windows', l?.win_url]]) {
    const li = h('li');
    if (isHttps(url)) {
      const a = h('a', { text: `Tải cho ${label}` });
      a.href = url;
      a.rel = 'noopener noreferrer';
      li.append(a, h('span', { className: 'url', text: url }));
    } else {
      li.className = 'muted';
      li.textContent = `${label}: chưa có link https`;
    }
    ul.append(li);
  }
}

// ---------- force-update settings ----------

function setFieldError(kind, msg) {
  const box = $(`set-${kind}`);
  field(box, 'error').textContent = msg;
  const input = field(box, 'input');
  if (msg) input.setAttribute('aria-invalid', 'true');
  else input.removeAttribute('aria-invalid');
}

function hideConfirm(kind) {
  delete state.pending[kind];
  const box = $(`set-${kind}`);
  field(box, 'confirm').hidden = true;
  field(box, 'confirm-text').textContent = '';
}

function onSettingSubmit(kind, ev) {
  ev.preventDefault();
  const input = field($(`set-${kind}`), 'input');
  const raw = input.value.trim().replace(/,/g, '.');
  input.value = raw;
  if (!VERSION_RE.test(raw)) {
    setFieldError(kind, raw ? 'Sai định dạng — nhập dạng x.y.z, ví dụ 1.2.0.' : 'Nhập phiên bản dạng x.y.z.');
    input.focus();
    return;
  }
  setFieldError(kind, '');
  propose(kind, raw);
}

/** target = "x.y.z" to override, or null to go back to the env default. */
function propose(kind, target) {
  const { key, label } = KINDS[kind];
  const s = state.settings?.[key];
  if (!s) return;
  const next = target ?? s.env;
  const diff = cmpVer(next, s.value);

  if (target !== null && diff === 0) {
    hideConfirm(kind);
    say(`${label}: mức tối thiểu đã là ${s.value} — không có gì thay đổi.`);
    return;
  }
  const body = { [key]: target };
  if (!(diff > 0)) {
    save(kind, body);
    return;
  }

  // Raising the minimum blocks devices: confirm in-page first.
  const { below, unknown, total } = blockedCount(kind, next);
  const box = $(`set-${kind}`);
  const text = field(box, 'confirm-text');
  const lead = target === null ? `Về mặc định sẽ nâng mức tối thiểu từ ${s.value} lên ${next}. ` : '';
  text.textContent = `${lead}Thiết bị dưới ${next} sẽ bị chặn cho tới khi cập nhật: ` +
    `${nf.format(below)}/${nf.format(total)} thiết bị ${label}` +
    (unknown ? ` (+${nf.format(unknown)} không rõ phiên bản)` : '') +
    '. Xác nhận?';
  state.pending[kind] = body;
  field(box, 'confirm').hidden = false;
  text.focus();
}

async function save(kind, body) {
  const { key, label } = KINDS[kind];
  const box = $(`set-${kind}`);
  const buttons = [...box.querySelectorAll('button')];
  for (const b of buttons) b.disabled = true;
  try {
    const res = await api('PUT', '/api/settings', body);
    hideConfirm(kind);
    field(box, 'input').value = '';
    setFieldError(kind, '');
    const s = res?.[key];
    say(`Đã lưu — ${label} tối thiểu: ${s?.value ?? '?'}${s && !s.overridden ? ' (mặc định)' : ''}.`, 'ok');
    await loadDash();
  } catch (e) {
    hideConfirm(kind);
    if (e instanceof ApiError && e.status === 400) {
      setFieldError(kind, e.code === 'invalid_version' ? 'Phiên bản không hợp lệ — dùng dạng x.y.z.' : 'Dữ liệu gửi lên không hợp lệ.');
      field(box, 'input').focus();
    } else {
      handleError(e);
    }
  } finally {
    for (const b of buttons) b.disabled = false;
  }
}

// ---------- wire up ----------

$('login-form').addEventListener('submit', onLogin);
$('btn-refresh').addEventListener('click', () => loadDash({ announce: true }));
$('btn-logout').addEventListener('click', onLogout);
$('btn-retry').addEventListener('click', boot);
$('btn-recheck').addEventListener('click', async () => {
  await boot();
  if (!$('view-disabled').hidden) say('Vẫn chưa bật — kiểm tra .env rồi chạy lại lệnh trên.', 'error');
});

for (const kind of Object.keys(KINDS)) {
  const box = $(`set-${kind}`);
  field(box, 'form').addEventListener('submit', (ev) => onSettingSubmit(kind, ev));
  field(box, 'reset').addEventListener('click', () => {
    setFieldError(kind, '');
    propose(kind, null);
  });
  field(box, 'yes').addEventListener('click', () => {
    const body = state.pending[kind];
    if (body) save(kind, body);
  });
  const cancel = () => {
    hideConfirm(kind);
    field(box, 'input').focus();
  };
  field(box, 'no').addEventListener('click', cancel);
  field(box, 'confirm').addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape') cancel();
  });
}

boot();
