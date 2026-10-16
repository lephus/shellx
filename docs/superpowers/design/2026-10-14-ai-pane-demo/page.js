/* ShellX · Pane AI — page behaviour: theme, nav, architecture details,
 * the decision form and links that start a demo scenario. */
(function () {
  'use strict';

  const store = {
    get(k) {
      try {
        return localStorage.getItem('shellx-ai-pane:' + k);
      } catch (e) {
        return null;
      }
    },
    set(k, v) {
      try {
        localStorage.setItem('shellx-ai-pane:' + k, v);
      } catch (e) {
        /* private window: nothing to remember */
      }
    },
  };

  /* ------------------------------------------------------------ theme -- */

  function applyTheme(t) {
    if (t === 'light' || t === 'dark') document.documentElement.dataset.theme = t;
    else delete document.documentElement.dataset.theme;
    for (const b of document.querySelectorAll('[data-theme-set]')) {
      b.setAttribute('aria-pressed', String(b.dataset.themeSet === (t || 'system')));
    }
  }
  applyTheme(store.get('theme') || 'system');
  for (const b of document.querySelectorAll('[data-theme-set]')) {
    b.addEventListener('click', () => {
      store.set('theme', b.dataset.themeSet);
      applyTheme(b.dataset.themeSet);
    });
  }

  /* -------------------------------------------------------------- nav -- */

  const links = [...document.querySelectorAll('.nav a')];
  const secs = links.map((a) => document.querySelector(a.getAttribute('href'))).filter(Boolean);
  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver(
      (es) => {
        for (const e of es) {
          if (!e.isIntersecting) continue;
          for (const a of links) a.classList.toggle('is-on', a.getAttribute('href') === '#' + e.target.id);
        }
      },
      { rootMargin: '-45% 0px -50% 0px' },
    );
    secs.forEach((s) => io.observe(s));
  }

  /* --------------------------------------------- run a scenario link -- */

  document.addEventListener('click', (ev) => {
    const a = ev.target.closest('[data-run]');
    if (!a || !window.ShellXDemo) return;
    ev.preventDefault();
    // Land on the toolbar so the coach line and the window are both in view.
    (document.querySelector('#demo .dm') || document.getElementById('demo')).scrollIntoView({ behavior: 'smooth' });
    window.ShellXDemo.start(a.dataset.run);
  });

  const params = new URLSearchParams(location.search);
  const kb = params.get('kb');
  if (kb && window.ShellXDemo) {
    const id = /^\d+$/.test(kb) ? 's' + kb : kb;
    if (window.ShellXDemo.scenarios.includes(id)) window.ShellXDemo.start(id);
  }
  const speed = Number(params.get('tocdo'));
  if (speed > 0 && window.ShellXDemo) window.ShellXDemo.speed(speed);

  /* ----------------------------------------------- architecture boxes -- */

  const ARCH = {
    ui: {
      t: 'Tab AI',
      d: 'Giao diện thuần Flutter (K2), không kèm terminal (K3): dòng hội thoại, thẻ cho từng việc agent làm, thanh xin quyền, ô nhập có @tệp, /lệnh, ảnh; chế độ, model, mức suy nghĩ từ configOptions của agent. Đăng nhập và cài đặt chạy trong một khung nhỏ trên pane.',
      f: ['apps/desktop/lib/src/ui/ai/'],
    },
    panel: {
      t: 'Thay đổi · Tệp',
      d: 'Panel bên phải của pane AI. “Thay đổi” so ổ đĩa với điểm khôi phục (đầu phiên hoặc đầu lượt): diff thật, Đã xem, hoàn tác tệp hoặc cả lượt, cảnh báo khi tệp bị sửa sau lượt. “Tệp”: cây thư mục, xem chỉ đọc có tô màu.',
      f: ['apps/desktop/lib/src/ui/ai/', 're_editor + re_highlight (chỉ đọc)', 'diff_match_patch'],
    },
    session: {
      t: 'Phiên AI',
      d: 'Trạng thái của một phiên: biến chuỗi session/update thành dòng hội thoại (gộp chunk, cập nhật thẻ theo toolCallId), hàng đợi tin khi agent đang chạy, lượt hiện tại và stopReason.',
      f: ['apps/desktop/lib/src/ai/'],
    },
    ckpt: {
      t: 'Điểm khôi phục',
      d: 'Trước mỗi lượt: git add -A + commit vào repo git ẩn (GIT_DIR riêng, GIT_WORK_TREE = dự án), theo .gitignore. So sánh và hoàn tác từ đó. Không đụng .git, index hay nhánh của bạn. Ngưỡng cho dự án lớn; kiểm Command Line Tools trên macOS; tự dọn sau 14 ngày (K4).',
      f: ['<app support>/ai/checkpoints/<dự án>'],
    },
    acp: {
      t: 'shellx_acp',
      d: 'Gói Dart thuần, mới: các kiểu ACP v1 cần dùng và kết nối JSON-RPC 2.0 theo dòng (mỗi thông điệp một dòng, chấp nhận dòng nhiều MB, bỏ dòng hỏng). Test đối chiếu schema chính thức. ACP chưa có SDK Dart chính thức (K1).',
      f: ['packages/shellx_acp'],
    },
    launch: {
      t: 'Chạy agent',
      d: 'Lấy PATH và env của login shell bằng ký tự đánh dấu (như LoginPathCheck), rồi chạy agent trực tiếp, không qua shell — profile in chữ ra stdout là hỏng giao thức. Adapter npm cài một lần vào thư mục riêng (bản ghim), chạy bằng node, không npx. Dừng bằng killProcessTree.',
      f: ['apps/desktop/lib/src/cli/cli_install.dart (LoginPathCheck)', 'apps/desktop/lib/src/platform/process_tree.dart (killProcessTree)'],
    },
    tree: {
      t: 'Tab, cây pane, layout.json',
      d: 'Tab AI là loại tab mới, không bắt kèm terminal (K3): id từ dải tổng hợp (≥ 2 000 000 000); pane AI và pane tool là lá id âm với bản đồ riêng (mẫu A6); nhãn và thư mục lấy từ pane AI. layout.json ghi tab AI trong mảng mới "aiTabs" ở cấp trên cùng để bản cũ bỏ qua mà không hỏng.',
      f: ['apps/desktop/lib/src/terminal/terminal_tabs.dart', 'apps/desktop/lib/src/terminal/pane_layout.dart', 'apps/desktop/lib/src/restore/restore_snapshot.dart'],
    },
    a12: {
      t: 'Trạng thái A12 · relay',
      d: 'Pane AI báo trạng thái thẳng vào AgentStatusNotifier (tra theo pane chung thay vì chỉ pane terminal): sidebar, viền chú ý, thông báo hệ thống qua một lối mới của TabAttention. Điện thoại nhận phiên AI qua loại tin ai.* (đề xuất) trong kênh mã hoá đầu cuối.',
      f: ['apps/desktop/lib/src/terminal/agent_status_notifier.dart', 'packages/shellx_core/lib/src/protocol/messages.dart'],
    },
    agent: {
      t: 'Tiến trình agent',
      d: 'Mỗi tab AI một tiến trình. Claude: adapter @agentclientprotocol/claude-agent-acp bọc Agent SDK nên chạy chính CLI chính thức (Node ≥ 22). Codex: @agentclientprotocol/codex-acp (đã kèm Codex). Gemini CLI: gemini --acp. OpenCode: opencode acp. Hoặc bất kỳ agent nói ACP.',
      f: [],
    },
    disk: {
      t: 'Thư mục dự án',
      d: 'Agent tự đọc, ghi tệp và chạy lệnh ở đây — ShellX không ghi hộ (không cung cấp fs/* của ACP, và ACP v2 bỏ phần này). Vì thế hoàn tác phải dựa vào điểm khôi phục, không dựa vào diff agent báo.',
      f: [],
    },
    auth: {
      t: 'Đăng nhập',
      d: 'Kiểu “terminal” của ACP: ShellX chạy lại chính lệnh của agent kèm args của cách đăng nhập trong một khung nhỏ trên pane AI (không phải pane terminal); mã thoát 0 = thành công; không gọi authenticate. ShellX không đọc, lưu hay chuyển credential và không bỏ cách đăng nhập nào (K5).',
      f: [],
    },
    tool: {
      t: 'Tool của bạn',
      d: 'Một web app bạn tự viết bằng bất kỳ công nghệ gì, chạy ở một URL (thường là localhost). ShellX chỉ hiển thị: engine trình duyệt A6 trên desktop, webview của app trên điện thoại (qua đường hầm). Không manifest, không SDK (K6).',
      f: [],
    },
    phone: {
      t: 'App ShellX trên điện thoại',
      d: 'Xem và điều khiển phiên AI (danh sách, hội thoại trực tiếp, prompt, trả lời xin quyền, dừng) và mở tool đã bật — qua relay mã hoá đầu cuối sẵn có, bằng loại tin ai.* và tool.* (đề xuất). Agent và tool vẫn chạy trên desktop (K7).',
      f: ['apps/mobile/', 'packages/shellx_client/'],
    },
  };
  const detail = document.getElementById('arch-detail');
  function showArch(key) {
    const a = ARCH[key];
    if (!a || !detail) return;
    for (const b of document.querySelectorAll('[data-arch]')) b.classList.toggle('is-on', b.dataset.arch === key);
    detail.innerHTML = `<h3>${a.t}</h3><p>${a.d}</p>${a.f.length ? `<ul>${a.f.map((x) => `<li><code>${x.replace(/</g, '&lt;')}</code></li>`).join('')}</ul>` : ''}`;
  }
  for (const b of document.querySelectorAll('[data-arch]')) b.addEventListener('click', () => showArch(b.dataset.arch));
  showArch('ui');

  /* ------------------------------------------------------ decisions -- */

  const form = document.getElementById('qa');
  const outEl = document.getElementById('qa-out');
  const msg = document.getElementById('qa-msg');
  if (form) {
    for (const el of form.elements) {
      if (!el.name) continue;
      const saved = store.get('qa:' + el.name);
      if (saved == null) continue;
      if (el.type === 'radio') el.checked = el.value === saved;
      else el.value = saved;
    }
    const render = () => {
      const v = (n) => {
        const el = form.elements[n];
        return el ? el.value : '';
      };
      const note = v('note').trim();
      outEl.textContent = [
        'Trả lời đề xuất pane AI:',
        `1. ${v('q1')}`,
        `2. ${v('q2')}`,
        `3. ${v('q3')}`,
        `4. ${v('q4')}`,
        note ? `Ghi chú: ${note}` : '',
      ]
        .filter(Boolean)
        .join('\n');
    };
    form.addEventListener('input', (ev) => {
      const el = ev.target;
      if (el.name) store.set('qa:' + el.name, el.value);
      render();
    });
    render();
    document.getElementById('qa-copy').addEventListener('click', async () => {
      const text = outEl.textContent;
      let ok = false;
      try {
        await navigator.clipboard.writeText(text);
        ok = true;
      } catch (e) {
        const ta = document.createElement('textarea');
        ta.value = text;
        document.body.append(ta);
        ta.select();
        try {
          ok = document.execCommand('copy');
        } catch (e2) {
          ok = false;
        }
        ta.remove();
      }
      msg.textContent = ok ? 'Đã sao chép — dán vào Claude Code.' : 'Không sao chép được; hãy chọn đoạn chữ ở trên và sao chép tay.';
    });
  }
})();
