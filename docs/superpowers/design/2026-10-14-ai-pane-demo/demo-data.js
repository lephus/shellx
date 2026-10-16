/* ShellX · Pane AI — the scripted agent, the fake project and seven scenarios.
 *
 * Message shapes follow the ACP v1 schema (1.25.0, 2026-10-09) and what
 * @agentclientprotocol/claude-agent-acp 0.90.0 actually sends: its mode list,
 * permission options, terminal auth methods and tool-call titles were read
 * from the published package. The agent itself is fake: it plays a script.
 */
(function () {
  'use strict';

  const HOME = '/Users/dev';
  const CWD = HOME + '/code/shop-web';
  const APP = '~/Library/Application Support/pro.shellx.desktop';
  const ADAPTER = APP + '/ai/agents/node_modules/@agentclientprotocol/claude-agent-acp/dist/index.js';
  const SESSION = 'b6f1c2d4-7a8e-4f3b-9c21-5e0d8a7f4b13';
  const abs = (p) => `${CWD}/${p}`;

  /* ----------------------------------------------------- fake project -- */

  const SESSION_HEAD = `import { refreshToken } from './refresh';
import { clearSession, loadSession, saveSession } from './storage';

export type Session = {
  accessToken: string;
  refreshToken: string;
  /** Unix time in seconds, from the API. */
  expiresAt: number;
};

`;
  const SESSION_OLD = `export function isExpired(session: Session, now = Date.now()): boolean {
  return now >= session.expiresAt * 1000;
}

export async function getAccessToken(): Promise<string | null> {
  const session = loadSession();
  if (!session) return null;
  if (isExpired(session)) {
    clearSession();
    return null;
  }
  return session.accessToken;
}`;
  const SESSION_NEW = `/** Refresh this long before the token expires. */
const REFRESH_MARGIN_MS = 60_000;

export function isExpired(session: Session, now = Date.now()): boolean {
  return now >= session.expiresAt * 1000 - REFRESH_MARGIN_MS;
}

export async function getAccessToken(): Promise<string | null> {
  const session = loadSession();
  if (!session) return null;
  if (!isExpired(session)) return session.accessToken;
  try {
    const next = await refreshToken(session.refreshToken);
    saveSession(next);
    return next.accessToken;
  } catch {
    clearSession();
    return null;
  }
}`;
  const SESSION_TAIL = `

export function signIn(next: Session): void {
  saveSession(next);
}
`;
  const SESSION_TS = SESSION_HEAD + SESSION_OLD + SESSION_TAIL;
  const SESSION_FIXED = SESSION_HEAD + SESSION_NEW + SESSION_TAIL;

  const TEST_TS = `import { beforeEach, describe, expect, it, vi } from 'vitest';
import { getAccessToken } from '../../src/auth/session';
import { refreshToken } from '../../src/auth/refresh';
import { clearSession, loadSession } from '../../src/auth/storage';

vi.mock('../../src/auth/refresh');
vi.mock('../../src/auth/storage');

const inSeconds = (s: number) => Math.floor(Date.now() / 1000) + s;
const session = (expiresIn: number) => ({
  accessToken: 'old',
  refreshToken: 'r1',
  expiresAt: inSeconds(expiresIn),
});

describe('getAccessToken', () => {
  beforeEach(() => vi.resetAllMocks());

  it('returns the token while it is valid', async () => {
    vi.mocked(loadSession).mockReturnValue(session(3600));
    expect(await getAccessToken()).toBe('old');
  });

  it('refreshes a token that expires within a minute', async () => {
    vi.mocked(loadSession).mockReturnValue(session(30));
    vi.mocked(refreshToken).mockResolvedValue({ ...session(3600), accessToken: 'new' });
    expect(await getAccessToken()).toBe('new');
  });

  it('signs out only when the refresh fails', async () => {
    vi.mocked(loadSession).mockReturnValue(session(-10));
    vi.mocked(refreshToken).mockRejectedValue(new Error('401'));
    expect(await getAccessToken()).toBeNull();
    expect(clearSession).toHaveBeenCalledOnce();
  });
});
`;

  const PROD = `{
  "apiUrl": "http://api.example.com",
  "authUrl": "http://auth.example.com",
  "timeoutMs": 5000
}
`;
  const STAGING = `{
  "apiUrl": "http://staging-api.example.com",
  "authUrl": "http://staging-auth.example.com",
  "timeoutMs": 8000
}
`;
  const toHttps = (s) => s.replace(/http:\/\//g, 'https://');

  const FILES = {
    '.env': 'API_TOKEN=dev-local-123\n',
    '.gitignore': 'node_modules/\ndist/\n.env\n',
    'README.md': '# shop-web\n\nCửa hàng mẫu dùng trong demo pane AI của ShellX.\n\n```sh\nnpm run dev   # http://localhost:5173\nnpm test\n```\n',
    'package.json': `{
  "name": "shop-web",
  "version": "1.4.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "test": "vitest run"
  },
  "dependencies": {
    "axios": "^1.7.9"
  },
  "devDependencies": {
    "typescript": "^5.6.3",
    "vite": "^6.0.7",
    "vitest": "^2.1.8"
  }
}
`,
    'vite.config.ts': `import { defineConfig } from 'vite';

export default defineConfig({
  server: { port: 5173 },
});
`,
    'config/dev.json': `{
  "apiUrl": "http://localhost:8080/api",
  "authUrl": "http://localhost:8080/auth",
  "timeoutMs": 10000
}
`,
    'config/staging.json': STAGING,
    'config/prod.json': PROD,
    'src/main.ts': `import { getAccessToken } from './auth/session';

const token = await getAccessToken();
document.querySelector('#app')!.textContent = token ? 'Xin chào!' : 'Vui lòng đăng nhập';
`,
    'src/api/client.ts': `import axios from 'axios';
import config from '../../config/dev.json';

export const api = axios.create({ baseURL: config.apiUrl, timeout: config.timeoutMs });
`,
    'src/auth/refresh.ts': `import { api } from '../api/client';
import type { Session } from './session';

export async function refreshToken(token: string): Promise<Session> {
  const res = await api.post('/auth/refresh', { refreshToken: token });
  return res.data as Session;
}
`,
    'src/auth/session.ts': SESSION_TS,
    'src/auth/storage.ts': `import type { Session } from './session';

const KEY = 'shop.session';

export function loadSession(): Session | null {
  const raw = localStorage.getItem(KEY);
  return raw ? (JSON.parse(raw) as Session) : null;
}

export function saveSession(session: Session): void {
  localStorage.setItem(KEY, JSON.stringify(session));
}

export function clearSession(): void {
  localStorage.removeItem(KEY);
}
`,
    'test/auth/refresh.test.ts': `import { describe, expect, it, vi } from 'vitest';
import { api } from '../../src/api/client';
import { refreshToken } from '../../src/auth/refresh';

vi.mock('../../src/api/client');

describe('refreshToken', () => {
  it('posts the refresh token', async () => {
    vi.mocked(api.post).mockResolvedValue({ data: { accessToken: 'a', refreshToken: 'r', expiresAt: 1 } });
    await refreshToken('r0');
    expect(api.post).toHaveBeenCalledWith('/auth/refresh', { refreshToken: 'r0' });
  });
});
`,
  };

  const tracked = (files) => {
    const o = Object.assign({}, files);
    delete o['.env'];
    return o;
  };

  /* -------------------------------------------- ACP data (adapter 0.90.0) -- */

  const MODE_OPTIONS = [
    { value: 'default', name: 'Manual', description: 'Always ask before making changes' },
    { value: 'acceptEdits', name: 'Accept edits', description: 'Automatically accept all file edits' },
    { value: 'plan', name: 'Plan', description: 'Create a plan before making changes' },
    { value: 'auto', name: 'Auto', description: 'Claude handles permission decisions' },
    { value: 'bypassPermissions', name: 'Bypass permissions', description: 'Accepts all permissions' },
  ];

  function configOptions(cfg) {
    return [
      { id: 'mode', name: 'Mode', description: 'Session permission mode', category: 'mode', type: 'select', currentValue: cfg.mode, options: MODE_OPTIONS },
      {
        id: 'model',
        name: 'Model',
        category: 'model',
        type: 'select',
        currentValue: cfg.model,
        options: [
          { value: 'default', name: 'Default' },
          { value: 'opus', name: 'Opus' },
          { value: 'sonnet', name: 'Sonnet' },
          { value: 'haiku', name: 'Haiku' },
        ],
      },
      {
        id: 'effort',
        name: 'Effort',
        description: 'Available effort levels for this model',
        category: 'thought_level',
        type: 'select',
        currentValue: cfg.effort,
        options: [
          { value: 'low', name: 'Low' },
          { value: 'medium', name: 'Medium' },
          { value: 'high', name: 'High' },
        ],
      },
    ];
  }

  const COMMANDS = [
    { name: 'compact', description: 'Clear conversation history but keep a summary in context', input: { hint: 'optional summarization instructions' } },
    { name: 'init', description: 'Initialize a new CLAUDE.md file with codebase documentation' },
    { name: 'review', description: 'Review a pull request' },
    { name: 'security-review', description: 'Complete a security review of the pending changes on the current branch' },
  ];

  const INIT_PARAMS = {
    protocolVersion: 1,
    clientCapabilities: { fs: { readTextFile: false, writeTextFile: false }, terminal: false, auth: { terminal: true } },
    clientInfo: { name: 'shellx', title: 'ShellX', version: '1.0.0' },
  };

  const INIT_RESULT = {
    protocolVersion: 1,
    agentCapabilities: {
      loadSession: true,
      promptCapabilities: { image: true, embeddedContext: true },
      mcpCapabilities: { http: true, sse: true },
      sessionCapabilities: { additionalDirectories: {}, close: {}, delete: {}, fork: {}, list: {}, resume: {} },
      auth: { logout: {} },
    },
    agentInfo: { name: '@agentclientprotocol/claude-agent-acp', title: 'Claude Agent', version: '0.90.0' },
    authMethods: [
      { description: 'Use Claude subscription ', name: 'Claude Subscription', id: 'claude-ai-login', type: 'terminal', args: ['--cli', 'auth', 'login', '--claudeai'] },
      { description: 'Use Anthropic Console (API usage billing)', name: 'Anthropic Console', id: 'console-login', type: 'terminal', args: ['--cli', 'auth', 'login', '--console'] },
    ],
  };

  const EDIT_OPTIONS = [
    { optionId: 'allow-once', name: 'Yes', kind: 'allow_once' },
    { optionId: 'allow-with-updates', name: 'Yes, allow all edits during this session', kind: 'allow_always' },
    { optionId: 'reject', name: 'No', kind: 'reject_once' },
  ];
  const ruleOptions = (what) => [
    { optionId: 'allow-once', name: 'Yes', kind: 'allow_once' },
    { optionId: 'allow-with-updates', name: `Yes, and don't ask again for ${what} commands`, kind: 'allow_always' },
    { optionId: 'reject', name: 'No', kind: 'reject_once' },
  ];

  /* ------------------------------------------------- the fake agent -- */

  const plan = (entries, states) => entries.map((e, i) => ({ content: e[0], priority: e[1], status: states[i] }));
  const P1 = [
    ['Tìm chỗ xử lý token hết hạn', 'high'],
    ['Làm mới token thay vì đăng xuất', 'high'],
    ['Thêm test và chạy test auth', 'medium'],
  ];

  const PROMPT1 = 'Người dùng bị đăng xuất khi token hết hạn, thay vì được làm mới token. Sửa giúp mình nhé. @src/auth/session.ts';
  const THOUGHT1 = 'Người dùng bị đăng xuất khi token hết hạn. Cần xem getAccessToken() xử lý token hết hạn thế nào, và dự án đã có hàm làm mới token chưa.';
  const MSG1 = 'Mình thấy lỗi rồi: khi token hết hạn, `getAccessToken()` gọi `clearSession()` — tức là đăng xuất — thay vì `refreshToken()`. Hàm `refreshToken()` đã có trong `refresh.ts` và đã được import, nhưng chưa được gọi ở đâu.\n\nMình sẽ:\n- làm mới token khi còn dưới 60 giây,\n- chỉ đăng xuất khi làm mới thất bại.';
  const MSG_FINAL = 'Xong rồi:\n- `getAccessToken()` làm mới token khi còn dưới 60 giây và chỉ đăng xuất khi làm mới thất bại.\n- Thêm `test/auth/session.test.ts` với 3 trường hợp: còn hạn, sắp hết hạn, làm mới lỗi.\n- `npm test -- auth`: 4/4 test qua.';
  const TEST_OUT = `> shop-web@1.4.0 test
> vitest run auth

 ✓ test/auth/refresh.test.ts (1 test) 6ms
 ✓ test/auth/session.test.ts (3 tests) 11ms

 Test Files  2 passed (2)
      Tests  4 passed (4)
   Duration  812ms`;

  const ID = {
    read: 'toolu_01Read8KqX',
    grep: 'toolu_01Grep3ZpW',
    edit: 'toolu_01Edit7WdM',
    write: 'toolu_01Writ2LxT',
    test: 'toolu_01Bash5RtJ',
  };

  async function readTool(D, id, path) {
    const p = abs(path);
    D.update({ sessionUpdate: 'tool_call', toolCallId: id, title: `Read ${path}`, kind: 'read', status: 'pending', locations: [{ path: p, line: 1 }], rawInput: { file_path: p } });
    await D.wait(380);
    D.update({ sessionUpdate: 'tool_call_update', toolCallId: id, status: 'completed', content: [{ type: 'content', content: { type: 'text', text: D.readNumbered(path) } }] });
    await D.wait(260);
  }

  async function grepTool(D, id, pattern, dir) {
    D.update({ sessionUpdate: 'tool_call', toolCallId: id, title: `grep -n "${pattern}" ${dir}`, kind: 'search', status: 'pending', rawInput: { pattern, path: dir, '-n': true, output_mode: 'content' } });
    await D.wait(420);
    D.update({ sessionUpdate: 'tool_call_update', toolCallId: id, status: 'completed', content: [{ type: 'content', content: { type: 'text', text: D.grep(pattern, dir) } }] });
    await D.wait(260);
  }

  /** Edit or Write. The agent writes the file itself; ShellX only watches. */
  async function fileTool(D, o) {
    const p = abs(o.path);
    const isNew = o.oldText == null;
    const diff = { type: 'diff', path: p, oldText: isNew ? null : o.oldText, newText: o.newText };
    D.update({
      sessionUpdate: 'tool_call',
      toolCallId: o.id,
      title: `${isNew ? 'Write' : 'Edit'} ${o.path}`,
      kind: 'edit',
      status: 'pending',
      locations: [{ path: p }],
      // A Write's live call carries no diff (the input cannot tell a new file
      // from an overwrite); the diff arrives with the result.
      content: isNew ? [] : [diff],
      rawInput: isNew ? { file_path: p, content: o.newText } : { file_path: p, old_string: o.oldText, new_string: o.newText },
    });
    if (!D.agentAllows('edit')) {
      const choice = await D.ask({ toolCallId: o.id }, EDIT_OPTIONS);
      if (choice.kind.startsWith('reject')) {
        D.update({ sessionUpdate: 'tool_call_update', toolCallId: o.id, status: 'failed' });
        return false;
      }
      if (choice.kind === 'allow_always') D.grant('edit');
    }
    D.update({ sessionUpdate: 'tool_call_update', toolCallId: o.id, status: 'in_progress' });
    await D.wait(480);
    D.write(o.path, o.full);
    D.hood('tệp', `Agent tự ghi \`${o.path}\` lên đĩa — ShellX không ghi hộ, chỉ thấy qua điểm khôi phục`);
    D.update({ sessionUpdate: 'tool_call_update', toolCallId: o.id, status: 'completed', content: [diff] });
    return true;
  }

  async function shellTool(D, o) {
    D.update({
      sessionUpdate: 'tool_call',
      toolCallId: o.id,
      title: o.cmd,
      kind: 'execute',
      status: 'pending',
      content: [{ type: 'content', content: { type: 'text', text: o.desc } }],
      rawInput: { command: o.cmd, description: o.desc },
    });
    if (!D.agentAllows('execute', o.rule)) {
      const choice = await D.ask({ toolCallId: o.id }, ruleOptions(o.rule));
      if (choice.kind.startsWith('reject')) {
        D.update({ sessionUpdate: 'tool_call_update', toolCallId: o.id, status: 'failed' });
        return false;
      }
      if (choice.kind === 'allow_always') D.grant('execute', o.rule);
    }
    D.update({ sessionUpdate: 'tool_call_update', toolCallId: o.id, status: 'in_progress' });
    await D.wait(o.ms || 1300);
    if (o.crash) D.crash(1, o.crash);
    if (o.effect) o.effect();
    D.update({ sessionUpdate: 'tool_call_update', toolCallId: o.id, status: 'completed', content: o.output ? [{ type: 'content', content: { type: 'text', text: o.output } }] : [] });
    return true;
  }

  async function boot(D, first) {
    if (first) D.beat(first);
    await D.spawnAgent();
    await D.initialize();
    await D.newSession();
  }

  const S1_HISTORY = [
    { sessionUpdate: 'user_message_chunk', content: { type: 'text', text: PROMPT1 } },
    { sessionUpdate: 'tool_call', toolCallId: ID.read, title: 'Read src/auth/session.ts', kind: 'read', status: 'completed', locations: [{ path: abs('src/auth/session.ts'), line: 1 }] },
    { sessionUpdate: 'tool_call', toolCallId: ID.grep, title: 'grep -n "refreshToken" src', kind: 'search', status: 'completed' },
    { sessionUpdate: 'agent_message_chunk', content: { type: 'text', text: MSG1 } },
    { sessionUpdate: 'tool_call', toolCallId: ID.edit, title: 'Edit src/auth/session.ts', kind: 'edit', status: 'completed', locations: [{ path: abs('src/auth/session.ts') }], content: [{ type: 'diff', path: abs('src/auth/session.ts'), oldText: SESSION_OLD, newText: SESSION_NEW }] },
    { sessionUpdate: 'tool_call', toolCallId: ID.write, title: 'Write test/auth/session.test.ts', kind: 'edit', status: 'completed', locations: [{ path: abs('test/auth/session.test.ts') }], content: [{ type: 'diff', path: abs('test/auth/session.test.ts'), oldText: null, newText: TEST_TS }] },
    { sessionUpdate: 'tool_call', toolCallId: ID.test, title: 'npm test -- auth', kind: 'execute', status: 'completed', content: [{ type: 'content', content: { type: 'text', text: TEST_OUT } }] },
    { sessionUpdate: 'agent_message_chunk', content: { type: 'text', text: MSG_FINAL } },
  ];

  /* ---------------------------------------------------------- scenarios -- */

  const s1 = {
    id: 's1',
    name: 'Một lượt sửa lỗi',
    async run(D) {
      await boot(
        D,
        'Bạn vừa mở **Phiên AI mới** trong workspace `shop-web`: một tab AI, không kèm terminal (nút terminal trên header bật nó khi cần). ShellX chạy adapter Claude trong thư mục gốc dự án rồi bắt tay bằng `initialize` → `session/new` (xem nhật ký bên phải).',
      );
      D.beat('Pane sẵn sàng. Ô nhập đã điền sẵn một yêu cầu kèm `@src/auth/session.ts` — nhấn **Enter** hoặc bấm **Gửi**. Agent giả trả lời theo kịch bản, dù bạn gõ gì.');
      const msg = await D.expectSend(PROMPT1);
      const stop = await D.turn(msg.blocks, async () => {
        D.beat('ShellX vừa **chụp điểm khôi phục** rồi gửi `session/prompt` (chữ + `resource_link` cho tệp bạn nhắc). Từ giờ mọi thứ agent làm về qua `session/update`.');
        await D.wait(500);
        D.update({ sessionUpdate: 'session_info_update', title: 'Sửa lỗi token hết hạn' });
        await D.stream(THOUGHT1, 'agent_thought_chunk');
        D.update({ sessionUpdate: 'plan', entries: plan(P1, ['in_progress', 'pending', 'pending']) });
        D.beat('Agent gửi **kế hoạch** (`plan`): ShellX hiện thành danh sách dính trên ô nhập. Suy nghĩ (`agent_thought_chunk`) được gập lại. Mẹo: bấm tab **dev server** ở sidebar để rời pane — khi agent cần bạn, sẽ có thông báo.');
        await D.wait(900);
        await readTool(D, ID.read, 'src/auth/session.ts');
        await grepTool(D, ID.grep, 'refreshToken', 'src');
        await D.stream(MSG1);
        D.update({ sessionUpdate: 'plan', entries: plan(P1, ['completed', 'in_progress', 'pending']) });
        await D.wait(500);
        D.beat(
          D.agentAllows('edit')
            ? 'Chế độ hiện tại cho agent tự sửa tệp — không cần hỏi.'
            : 'Agent muốn **sửa tệp** → `session/request_permission`. Thẻ mở sẵn diff; sidebar chuyển **Cần bạn trả lời**. Nhấn **1** Cho phép · **2** Luôn cho phép sửa tệp trong phiên · **3**/**Esc** Từ chối.',
        );
        const edited = await fileTool(D, { id: ID.edit, path: 'src/auth/session.ts', oldText: SESSION_OLD, newText: SESSION_NEW, full: SESSION_FIXED });
        if (!edited) {
          D.beat('Bạn đã từ chối: ShellX trả `outcome: selected · reject` và agent bỏ thao tác đó.');
          await D.stream('Được, mình chưa sửa gì. Nếu muốn, mình có thể chỉ giải thích chỗ lỗi, hoặc làm theo hướng khác.');
          return 'end_turn';
        }
        await D.wait(450);
        D.beat(
          D.agentAllows('edit')
            ? 'Tệp test mới được ghi ngay: bạn đã chọn **Luôn cho phép** sửa tệp trong phiên này (hoặc chế độ cho phép).'
            : 'Agent lại xin quyền, lần này để **tạo tệp test**. (Nếu lần trước chọn 2 thì đã không phải hỏi.) Lệnh `Write` không kèm diff khi xin quyền — diff đến cùng kết quả.',
        );
        await fileTool(D, { id: ID.write, path: 'test/auth/session.test.ts', oldText: null, newText: TEST_TS, full: TEST_TS });
        D.update({ sessionUpdate: 'plan', entries: plan(P1, ['completed', 'completed', 'in_progress']) });
        D.beat(
          D.agentAllows('execute', 'npm test')
            ? 'Agent chạy test — lệnh này đã được cho phép.'
            : 'Agent muốn **chạy lệnh** `npm test -- auth`. Ở chế độ “Hỏi trước”, lệnh shell luôn phải hỏi. Thử giữ một chữ trong ô nhập rồi gõ số: số vào ô nhập, không trả lời nhầm.',
        );
        const ran = await shellTool(D, { id: ID.test, cmd: 'npm test -- auth', desc: 'Run the auth tests', rule: 'npm test', output: TEST_OUT, ms: 1500 });
        if (!ran) {
          await D.stream('Mình đã sửa xong nhưng chưa chạy test. Bạn chạy `npm test -- auth` ở terminal bên dưới khi tiện nhé.');
          return 'end_turn';
        }
        D.update({ sessionUpdate: 'plan', entries: plan(P1, ['completed', 'completed', 'completed']) });
        await D.stream(MSG_FINAL);
        D.update({ sessionUpdate: 'usage_update', used: 31840, size: 200000 });
        return 'end_turn';
      });
      if (stop === 'cancelled') {
        D.beat('Bạn đã dừng lượt: ShellX gửi `session/cancel`, agent trả `stopReason: cancelled`. Phần đã sửa (nếu có) vẫn nằm trong panel **Thay đổi** và hoàn tác được.');
        return;
      }
      D.beat(
        'Lượt xong (`stopReason: end_turn`). ShellX so với điểm khôi phục → panel **Thay đổi**. Thử: bấm một tệp để xem diff, đánh dấu **Đã xem**, hoặc **Hoàn tác lượt**. Gõ thêm tin nhắn để chạy một lượt nữa (khi agent đang chạy, tin sẽ được xếp hàng).',
      );
    },
  };

  const SED = "sed -i '' 's#http://#https://#g' config/prod.json config/staging.json";
  const s2 = {
    id: 's2',
    name: 'Hoàn tác lệnh shell',
    async run(D) {
      await boot(D, 'Lần này agent sửa tệp bằng **lệnh shell** (`sed`), không qua công cụ sửa tệp — nên agent sẽ không gửi diff nào.');
      D.beat('Nhấn **Enter** để gửi yêu cầu đã điền sẵn.');
      const msg = await D.expectSend('Đổi URL của môi trường prod và staging trong thư mục config sang https.');
      const stop = await D.turn(msg.blocks, async () => {
        await D.wait(450);
        D.update({ sessionUpdate: 'session_info_update', title: 'Đổi URL sang https' });
        await D.stream('Mình sẽ đổi `http://` thành `https://` trong hai tệp cấu hình bằng một lệnh `sed`.');
        D.beat('Agent xin chạy `sed -i` — nhấn **1** để cho phép.');
        const ran = await shellTool(D, {
          id: 'toolu_01Sed4HnQ',
          cmd: SED,
          desc: 'Switch the prod and staging URLs to https',
          rule: 'sed',
          ms: 700,
          effect() {
            D.write('config/prod.json', toHttps(PROD));
            D.write('config/staging.json', toHttps(STAGING));
          },
        });
        if (!ran) {
          await D.stream('Được, mình không chạy lệnh đó.');
          return 'end_turn';
        }
        await D.stream('Đã đổi 4 URL sang https trong `config/prod.json` và `config/staging.json`.');
        return 'end_turn';
      });
      if (stop !== 'end_turn' || D.state().fs['config/prod.json'] === PROD) {
        D.beat('Lượt kết thúc mà không đổi tệp. Bấm **Làm lại** để thử lại.');
        return;
      }
      D.set((s) => {
        s.scope = 'turn';
        s.sideTab = 'changes';
        s.layout.side = true;
      });
      D.beat('Agent **không gửi diff** cho lệnh shell — thẻ “Chạy” chỉ có kết quả lệnh. Nhưng panel **Thay đổi** vẫn thấy cả hai tệp nhờ điểm khôi phục chụp trước lượt. Giờ giả sử bạn sửa tiếp một tệp trong editor:', [
        { label: 'Mô phỏng: sửa tay config/staging.json', key: 'manual', primary: true },
      ]);
      await D.waitUser('manual');
      D.write('config/staging.json', toHttps(STAGING).replace('8000', '15000'));
      D.hood('tệp', '`config/staging.json` đổi trên đĩa sau khi lượt kết thúc — không phải do agent', 'ShellX so với ảnh chụp lúc lượt kết thúc để biết tệp nào bị sửa tiếp.');
      D.beat('Panel Thay đổi gắn nhãn **đã sửa sau lượt**. Bấm **Hoàn tác lượt** (cuối panel, hoặc trong thẻ tóm tắt lượt) để thấy ShellX hỏi lại trước khi ghi đè.');
      const reverted = await D.waitUser('reverted');
      D.beat(`Đã hoàn tác ${reverted.length} tệp từ repo git ẩn — \`.git\` của dự án không bị đụng tới. Tệp bị \`.gitignore\` bỏ qua (vd \`.env\`) không nằm trong điểm khôi phục nên không hoàn tác được; panel ghi rõ điều này.`);
    },
  };

  const s3 = {
    id: 's3',
    name: 'Lần đầu: chọn kiểu, đăng nhập',
    async run(D) {
      D.set((s) => {
        s.aiTab = false;
        s.selectedTab = 'dev';
        s.agents[0].status = 'login';
      });
      D.beat('Lần đầu mở ShellX bản mới, màn chào hỏi bạn muốn làm việc theo kiểu nào.');
      await D.wait(500);
      const kind = await D.chooseStart();
      if (kind === 'ai') {
        D.hood('tệp', 'Lưu cài đặt: tab mới mở dạng **AI** — ⌘T giờ mở một phiên AI');
        D.beat('Bạn chọn **Giao diện AI**: từ giờ tab mới là một phiên AI, không có terminal. Bấm **+ Phiên AI mới** để mở phiên đầu tiên.', [{ label: '+ Phiên AI mới', key: 'new-ai', primary: true }]);
      } else {
        D.hood('tệp', 'Giữ cài đặt: tab mới mở dạng **Terminal** (như hiện nay)');
        D.beat('ShellX giữ nguyên như hôm nay. Giao diện AI vẫn mở được bất cứ lúc nào bằng **+ Phiên AI mới**.', [{ label: '+ Phiên AI mới', key: 'new-ai', primary: true }]);
      }
      await D.waitUser('new-ai');
      D.beat('Chọn agent. Danh sách lấy từ **Cài đặt › Agents**; agent chưa cài sẽ dẫn tới phần cài đặt.');
      const pick = await D.pickAgent();
      if (!pick) {
        D.beat('Bạn đã huỷ. Bấm **Làm lại** để thử lại.');
        return;
      }
      D.set((s) => {
        s.aiTab = true;
      });
      D.selectTab('ai');
      D.hood('tệp', 'Mở tab AI trong workspace `shop-web` — không kèm pane terminal', 'Thư mục làm việc = gốc dự án của workspace (Workspace.root).');
      D.beat('ShellX chạy adapter và gửi `initialize` với `auth.terminal: true` — nghĩa là “tôi chạy được màn đăng nhập của agent”.');
      await D.spawnAgent();
      await D.initialize();
      await D.newSession({ authRequired: true });
      D.set((s) => {
        s.readyHint = 'Cần đăng nhập Claude trước khi gửi tin';
      });
      D.notice({
        kind: 'auth',
        title: 'Claude cần đăng nhập',
        body: '<p><code>session/new</code> trả lỗi <code>-32000 Authentication required</code>. Agent đưa sẵn hai cách đăng nhập trong <code>authMethods</code> của <code>initialize</code>.</p><p class="muted">ShellX chạy đúng màn đăng nhập của Claude trong một khung nhỏ; phần đăng nhập thật diễn ra trên trình duyệt. ShellX không thấy, không lưu mật khẩu hay token.</p>',
        actions: [
          { label: 'Claude Subscription', key: 'auth', value: 'claude-ai-login', kind: 'pri' },
          { label: 'Anthropic Console (API)', key: 'auth', value: 'console-login' },
        ],
      });
      D.beat('Agent báo cần đăng nhập. Chọn một cách trong thẻ (tên do agent đặt).');
      const method = await D.waitUser('auth');
      const args = method === 'console-login' ? '--cli auth login --console' : '--cli auth login --claudeai';
      D.runSheet({
        icon: 'key',
        title: 'Đăng nhập Claude',
        sub: method === 'console-login' ? 'Anthropic Console' : 'Claude Subscription',
        lines: [
          { t: `$ node …/claude-agent-acp/dist/index.js ${args}`, c: 'cmd' },
          { t: '[màn đăng nhập của chính Claude — trình duyệt mở để bạn xác nhận; demo không mô phỏng nội dung]', c: 'dim' },
        ],
        note: 'Khung nhỏ này chạy đúng lệnh agent đưa ra (kiểu đăng nhập “terminal” của ACP). Xong là tự đóng — không cần mở terminal.',
      });
      D.hood('tiến trình', 'Đăng nhập kiểu terminal: chạy lại chính lệnh của agent, thêm `args` của cách đăng nhập, trong một khung nhỏ', `node "${ADAPTER}" ${args}\n\nTheo schema ACP: mã thoát 0 = thành công; client KHÔNG gọi \`authenticate\` cho kiểu terminal.`);
      D.beat('Bạn đăng nhập trên trình duyệt. Khi xong:', [{ label: 'Mô phỏng: đăng nhập xong', key: 'logged', primary: true }]);
      await D.waitUser('logged');
      D.runPrint([{ t: '✓ tiến trình đăng nhập thoát, mã 0', c: 'ok' }]);
      D.set((s) => {
        s.agents[0].status = 'ready';
      });
      await D.wait(800);
      D.runSheet(null);
      D.hood('tiến trình', 'Đăng nhập xong (mã 0) → đóng khung, tự thử lại `session/new`');
      await D.newSession();
      D.beat('Xong — không lần nào phải mở terminal. Bạn gửi tin được ngay, hoặc xem trạng thái các agent khác:', [{ label: 'Mở Cài đặt › Agents', key: 'settings' }]);
      await D.waitUser('settings');
      await D.openSettings();
      D.beat('Cài đặt › Agents: cài adapter, đăng nhập (cũng trong khung nhỏ), chọn agent mặc định, thêm agent tuỳ chỉnh.');
    },
  };

  const LAYOUT_SNIPPET = `{
  "v": 1,
  "tabs": [ …các tab terminal, như hiện nay… ],
  "aiTabs": [{
    "key": "ai-1",
    "workspace": "shop-web",
    "agent": "claude",
    "session": "${SESSION}",
    "cwd": "~/code/shop-web",
    "title": "Sửa lỗi token hết hạn",
    "tools": ["t1"]
  }]
}

Tab AI nằm trong mảng mới "aiTabs" ở cấp trên cùng: bản ShellX cũ bỏ qua khoá lạ
ở cấp này nên vẫn mở được các tab terminal. (Một nút lạ trong cây pane thì làm
hỏng cả tệp — bản cũ đổi tên nó thành layout.json.bak.)`;

  const s4 = {
    id: 's4',
    name: 'Thoát rồi mở lại',
    async run(D) {
      D.set((s) => {
        s.title = 'Sửa lỗi token hết hạn';
        s.sessionId = SESSION;
        s.fs['src/auth/session.ts'] = SESSION_FIXED;
        s.fs['test/auth/session.test.ts'] = TEST_TS;
        s.ckpts = [{ id: s.hashes.shift(), n: 1, at: 0, files: tracked(FILES), after: tracked(s.fs) }];
        s.turnCount = 1;
        s.process = { pid: 48211 };
        s.ready = true;
        s.status = 'idle';
        s.configOptions = configOptions(s.cfg);
        s.commands = COMMANDS;
        s.usage = { used: 31840, size: 200000 };
      });
      D.seedHistory(S1_HISTORY);
      D.hood('khôi phục', 'Dựng sẵn: phiên đã có một lượt (giống kịch bản 1)');
      D.beat('Phiên này đã có một lượt sửa lỗi (giống kịch bản 1). Bấm **Thoát ShellX** để thử khôi phục.', [{ label: 'Thoát ShellX', key: 'quit', primary: true }]);
      await D.waitUser('quit');
      D.hood('khôi phục', 'Ghi `layout.json`: pane AI = {agent, id phiên, thư mục, tiêu đề}', LAYOUT_SNIPPET);
      D.stopAgent('Thoát ShellX: đóng stdin của agent, chờ ngắn, rồi diệt cả cây tiến trình.');
      D.set((s) => {
        s.offline = true;
        s.status = 'none';
      });
      D.beat('ShellX đã thoát. ShellX **không lưu nội dung hội thoại** — chỉ lưu id phiên; lịch sử nằm ở phía agent. Bấm **Mở lại ShellX**.', [{ label: 'Mở lại ShellX', key: 'reopen', primary: true }]);
      await D.waitUser('reopen');
      D.clearConversation();
      D.set((s) => {
        s.offline = false;
        s.ready = false;
        s.usage = null;
        s.plan = null;
        s.readyHint = 'Agent chưa chạy — bấm “Tiếp tục phiên”';
        s.empty = `<div class="empty-card"><span class="ec-ic">✦</span><b>Sửa lỗi token hết hạn</b><p>Claude · phiên ${SESSION.slice(0, 8)}… · ~/code/shop-web</p><p class="muted">Khôi phục từ layout.json. Agent chưa chạy — ShellX chỉ chạy khi bạn quay lại pane này.</p><button class="btn pri" data-act="resume">Tiếp tục phiên</button></div>`;
      });
      D.hood('khôi phục', 'Đọc `layout.json` → dựng lại tab, pane AI ở trạng thái chờ (khởi chạy lười)');
      D.beat('ShellX dựng lại tab với tiêu đề cũ nhưng **chưa chạy agent**. Bấm **Tiếp tục phiên**.', [{ label: 'Tiếp tục phiên', key: 'resume', primary: true }]);
      await D.waitUser('resume');
      D.set((s) => {
        s.empty = null;
      });
      await D.spawnAgent();
      await D.initialize();
      D.beat('Agent khai `loadSession: true` → ShellX gọi `session/load`; agent **phát lại lịch sử** bằng chuỗi `session/update`.');
      await D.loadSession({ history: D.historyForReplay() });
      D.set((s) => {
        s.usage = { used: 31840, size: 200000 };
      });
      D.beat('Hội thoại đã về. Panel **Thay đổi** vẫn đủ vì điểm khôi phục nằm trên đĩa. Bấm biểu tượng đồng hồ trên header pane để xem các phiên cũ (`session/list`).');
      await D.waitUser('history');
      D.beat('Danh sách phiên do agent lưu, trả qua `session/list`. Mở một phiên khác = `session/load` với id của phiên đó.');
    },
  };

  const STDERR = `[claude-agent-acp] prompt started (session ${SESSION.slice(0, 8)}…)
[claude-agent-acp] Bash: npm install axios@latest
Error: Claude Code process exited with code 1
    (dòng lỗi minh hoạ — nội dung thật tuỳ agent)`;

  const s5 = {
    id: 's5',
    name: 'Agent gặp sự cố',
    async run(D) {
      await boot(D, 'Lượt này agent sẽ **chết giữa chừng** để xem ShellX xử lý ra sao.');
      D.beat('Nhấn **Enter** để gửi.');
      const msg = await D.expectSend('Nâng axios lên bản mới nhất rồi chạy test.');
      const stop = await D.turn(msg.blocks, async () => {
        await D.wait(400);
        D.update({ sessionUpdate: 'session_info_update', title: 'Nâng axios' });
        D.update({
          sessionUpdate: 'plan',
          entries: plan(
            [
              ['Nâng axios lên bản mới nhất', 'high'],
              ['Chạy test', 'medium'],
            ],
            ['in_progress', 'pending'],
          ),
        });
        await readTool(D, 'toolu_01Pkg6VbN', 'package.json');
        await D.stream('Mình sẽ cài axios bản mới nhất rồi chạy test.');
        D.beat('Agent xin chạy `npm install axios@latest` — nhấn **1**.');
        await shellTool(D, { id: 'toolu_01Npm9KcD', cmd: 'npm install axios@latest', desc: 'Upgrade axios to the latest version', rule: 'npm install', ms: 1700, crash: STDERR });
        return 'end_turn';
      });
      if (stop !== 'crash') {
        D.beat('Lượt kết thúc trước khi kịp mô phỏng sự cố. Bấm **Làm lại** để thử lại.');
        return;
      }
      D.notice({
        kind: 'err',
        title: 'Claude dừng bất ngờ (mã thoát 1)',
        body: '<p>Lượt này bị gián đoạn. Những gì agent đã kịp ghi vẫn nằm trong điểm khôi phục — hoàn tác được.</p>',
        actions: [
          { label: 'Khởi động lại', key: 'restart', kind: 'pri' },
          { label: 'Xem log', onClick: () => D.showLog() },
        ],
      });
      D.beat('ShellX báo lỗi ngay trong hội thoại và bỏ trạng thái agent ở sidebar. Bấm **Khởi động lại**: ShellX chạy lại agent và nạp lại phiên bằng `session/load`.');
      await D.waitUser('restart');
      await D.spawnAgent({ pid: 48377 });
      await D.initialize();
      await D.loadSession({ history: D.historyForReplay() });
      D.beat('Phiên đã về (lịch sử phát lại từ phía agent). Gửi lại yêu cầu khi bạn muốn. Nếu agent **treo** thay vì chết: **Esc** gửi `session/cancel`; quá 10 giây chưa dừng thì ShellX hiện nút **Dừng hẳn**.');
    },
  };

  const s6 = {
    id: 's6',
    name: 'Tool qua URL',
    phase: 'GĐ2',
    async run(D) {
      await boot(D, '**Giai đoạn 2.** Bạn tự làm một tool — bất kỳ công nghệ gì — đang chạy ở `http://localhost:4000` (vd `node server.js`).');
      D.beat('Bấm **Thêm tool** ở cuối sidebar. Chỉ cần tên và URL: không manifest, không cài đặt, không SDK.', [{ label: 'Thêm tool', key: 'add-tool', primary: true }]);
      let tool = null;
      while (!tool) {
        await D.waitUser('add-tool');
        tool = await D.openAddTool({ name: 'Bảng việc', url: 'http://localhost:4000' });
        if (!tool) D.beat('Bạn đã huỷ. Bấm **Thêm tool** khi sẵn sàng.', [{ label: 'Thêm tool', key: 'add-tool', primary: true }]);
      }
      D.addTool(tool);
      D.beat('Tool mở cạnh pane AI và có tên trong sidebar. ShellX chỉ **hiển thị** trang của bạn (engine trình duyệt của A6) — tool tự lo giao diện và dữ liệu. Bấm một thẻ để chuyển cột, rồi bật **Điện thoại** trên thanh của tool.');
      const on = await D.waitUser('tool-phone');
      D.beat(on ? 'Tool này giờ mở được trên điện thoại đã ghép đôi (xem kịch bản 7). Desktop chỉ proxy đúng URL này, qua relay mã hoá đầu cuối.' : 'Đã tắt chia sẻ cho điện thoại. Bật lại bất cứ lúc nào trên thanh của tool.');
    },
  };

  const MAIN_OLD = FILES['src/main.ts'];
  const MAIN_NEW = `import { getAccessToken } from './auth/session';
import { clearSession } from './auth/storage';

const token = await getAccessToken();
const app = document.querySelector('#app')!;
app.textContent = token ? 'Xin chào!' : 'Vui lòng đăng nhập';

if (token) {
  const logout = document.createElement('button');
  logout.textContent = 'Đăng xuất';
  logout.onclick = () => {
    clearSession();
    location.reload();
  };
  app.append(logout);
}
`;

  const s7 = {
    id: 's7',
    name: 'Điện thoại',
    phase: 'GĐ2',
    async run(D) {
      await boot(D, '**Giai đoạn 2.** Phiên AI chạy trên desktop; điện thoại đã ghép đôi với ShellX như hôm nay (relay mã hoá đầu cuối).');
      D.addTool({ name: 'Bảng việc', url: 'http://localhost:4000', phone: true });
      D.phoneOn();
      D.beat('Bên phải là app ShellX trên điện thoại. Bấm vào phiên AI ở mục **Phiên AI** để mở.');
      await D.waitUser('ph-open-ai');
      D.beat('Điện thoại thấy cùng hội thoại với desktop: bản chụp ban đầu rồi cập nhật trực tiếp. Gõ yêu cầu ở ô dưới cùng của **điện thoại** (đã điền sẵn) rồi bấm gửi.');
      D.phoneDraft('Thêm nút đăng xuất ở trang chính.');
      const msg = await D.waitUser('phone-send');
      const stop = await D.turn(msg.blocks, async () => {
        await D.wait(400);
        D.update({ sessionUpdate: 'session_info_update', title: 'Nút đăng xuất' });
        await readTool(D, 'toolu_01Main4HkQ', 'src/main.ts');
        await D.stream('Mình sẽ thêm nút **Đăng xuất** gọi `clearSession()` rồi tải lại trang.');
        D.beat('Agent xin quyền sửa tệp. Điện thoại hiện yêu cầu ngay trong phiên (và trên thông báo đẩy nếu app đang ở nền) — bấm **Cho phép** trên **điện thoại**; desktop cập nhật theo.');
        const ok = await fileTool(D, { id: 'toolu_01Main7BtR', path: 'src/main.ts', oldText: MAIN_OLD, newText: MAIN_NEW, full: MAIN_NEW });
        if (!ok) {
          await D.stream('Được, mình chưa sửa gì.');
          return 'end_turn';
        }
        await D.stream('Xong: thêm nút **Đăng xuất** trong `src/main.ts` — bấm là xoá phiên rồi tải lại trang.');
        return 'end_turn';
      });
      if (stop !== 'end_turn') {
        D.beat('Lượt đã dừng. Bấm **Làm lại** để thử lại.');
        return;
      }
      D.beat('Lượt xong — điện thoại thấy tóm tắt. Giờ mở tool trên điện thoại: tab **Tool** → **Bảng việc**.');
      await D.waitUser('ph-open-tool');
      D.beat('Điện thoại mở tool qua đường hầm: desktop chỉ proxy đúng URL đã bật, qua relay mã hoá đầu cuối. Bấm một thẻ trên **điện thoại** — pane tool trên desktop đổi theo vì hai bên cùng nói chuyện với một server.');
      await D.waitUser('ph-card');
      D.beat('Giới hạn relay hiện tại: khung 64 KiB, 500 khung/giây mỗi thiết bị — đủ cho trang quản trị hay dashboard; video, tệp lớn sẽ chậm và tốn băng thông relay.');
    },
  };

  /* -------------------------------------------------------------- export -- */

  window.SHELLX_DEMO = {
    cwd: CWD,
    home: HOME,
    sessionId: SESSION,
    adapterPath: ADAPTER,
    agentsDir: APP + '/ai/agents',
    ckptDir: APP + '/ai/checkpoints/shop-web-5f3a9c',
    files: FILES,
    hashes: ['7c1e9a2', '3e8b1d4', 'a41f0c7', '9d2b6e8', '52f7c1a', 'e08a3d5', '1b9c4f0', 'c3d82e6', '6f0a2b9', 'd71e5c3'],
    initParams: INIT_PARAMS,
    initResult: INIT_RESULT,
    configOptions,
    commands: COMMANDS,
    sessions(currentId, currentTitle) {
      return [
        { sessionId: currentId || SESSION, cwd: CWD, title: currentTitle || 'Phiên AI mới', updatedAt: '2026-10-14T09:42:10Z' },
        { sessionId: '5d0e9b1a-3c4f-4e8a-b2d7-6a1f9c0e8b52', cwd: CWD, title: 'Thêm trang đăng ký', updatedAt: '2026-10-13T16:05:44Z' },
        { sessionId: '0c7a4e2f-9b1d-4f6a-8e3c-2d5b7a9f1c64', cwd: CWD, title: 'Viết test cho giỏ hàng', updatedAt: '2026-10-11T10:21:03Z' },
      ];
    },
    genericReply(text, mode) {
      if (mode === 'plan') {
        return '(Chế độ **Lập kế hoạch**) Mình sẽ chỉ đọc mã và đề xuất kế hoạch, chưa sửa gì. Kịch bản demo chưa soạn phần này — chuyển về **Hỏi trước** để xem luồng đầy đủ.';
      }
      const short = text.length > 80 ? text.slice(0, 79) + '…' : text;
      return `(Agent giả) Mình nhận được: “${short}”.\n\nDemo chỉ có vài kịch bản soạn sẵn — chọn kịch bản khác ở thanh trên để xem thêm. Lượt này vẫn đi đúng đường thật: điểm khôi phục → \`session/prompt\` → \`session/update\` → \`stopReason\`.`;
    },
    agents: [
      { id: 'claude', name: 'Claude Code', status: 'ready', how: 'Adapter @agentclientprotocol/claude-agent-acp 0.90.0 (bản ghim) · chạy CLI chính thức qua Agent SDK', need: 'Cần Node ≥ 22 · máy có 22.12.0', pkg: '@agentclientprotocol/claude-agent-acp@0.90.0', loginCmd: 'node …/claude-agent-acp/dist/index.js --cli auth login --claudeai' },
      { id: 'codex', name: 'Codex', status: 'missing', how: 'Adapter @agentclientprotocol/codex-acp (bản ghim, đã kèm Codex)', need: 'Cần Node', pkg: '@agentclientprotocol/codex-acp@<bản ghim>' },
      { id: 'gemini', name: 'Gemini CLI', status: 'notfound', how: 'gemini --acp', need: 'Không thấy lệnh gemini trong PATH của login shell' },
      { id: 'opencode', name: 'OpenCode', status: 'login', how: 'opencode acp', need: 'Đã cài', loginCmd: 'opencode auth login' },
    ],
    term: {
      ai: [{ t: '~/code/shop-web $ ', c: 'prompt' }],
    },
    tabs: {
      dev: {
        title: 'dev server',
        header: 'zsh — ~/code/shop-web',
        lines: [
          { t: '~/code/shop-web $ npm run dev', c: 'cmd' },
          '',
          { t: '> shop-web@1.4.0 dev', c: 'dim' },
          { t: '> vite', c: 'dim' },
          '',
          '  VITE v6.0.7  ready in 412 ms',
          '',
          '  ➜  Local:   http://localhost:5173/',
        ],
      },
      cc: {
        title: 'claude',
        header: 'claude — ~/code/shellx',
        lines: [
          { t: '~/code/shellx $ claude', c: 'cmd' },
          { t: '(giao diện chữ của Claude Code chạy trong terminal như hôm nay — trạng thái hiện ở sidebar nhờ hook A12)', c: 'dim' },
        ],
      },
    },
    // Ports the sidebar already shows for the workspace's terminals (A2).
    ports: [
      { url: 'http://localhost:4000', name: 'Bảng việc', label: ':4000 · node server.js' },
      { url: 'http://localhost:5173', name: 'shop-web', label: ':5173 · vite' },
    ],
    board: {
      flash: null,
      cards: [
        { id: 'c1', text: 'Trang đăng ký: kiểm tra email trùng', col: 'todo' },
        { id: 'c2', text: 'Thêm nút đăng xuất', col: 'todo' },
        { id: 'c3', text: 'Sửa lỗi token hết hạn', col: 'doing' },
        { id: 'c4', text: 'Nâng Vite lên 6', col: 'done' },
      ],
    },
    scenarios: [s1, s2, s3, s4, s5, s6, s7],
  };
})();
