# V2-1 — Giao diện AI trên desktop (tab AI) — Đặc tả thiết kế

- **Ngày:** 2026-10-14
- **Branch:** `shellx-v2`. Toàn bộ V2 nằm trên branch này; `main` giữ V1.
- **Trạng thái:** Người dùng đã duyệt hướng trong chat ngày 14/10/2026:
  - giao diện AI cho người không muốn dùng terminal;
  - tool riêng nhúng bằng URL;
  - điện thoại xem và điều khiển được;
  - sau V2-1 làm điện thoại và tool song song; tool trên điện thoại làm ngay trong lộ trình.

  D1–D23 do người viết spec chốt, có ghi cái giá nếu sai. Spec chờ người dùng xem.
- **Lộ trình V2:** **V2-1 (tài liệu này)**, sau đó làm song song V2-2 (điện thoại: phiên AI), V2-3 (tool qua URL trên desktop) và V2-4 (tool trên điện thoại). Mỗi phần có spec riêng (§11).
- **Nền:** `main` tại `164bba6`.
  - V2-1 **được phép** thêm:
    - các gói `packages/shellx_acp` và `packages/shellx_ai`;
    - các thư mục `apps/desktop/lib/src/ai/` và `apps/desktop/lib/src/ui/ai/`;
    - một loại tab;
    - khoá cài đặt, hành động phím tắt, chuỗi ARB;
    - khoá `aiTabs` trong `layout.json`.
  - V2-1 **không** sửa:
    - relay;
    - giao thức điện thoại (`packages/shellx_core/lib/src/protocol/`);
    - daemon (`daemon_main.dart`, `src/mux/*`);
    - app mobile.
- **Giữ nguyên:** spec A1–A13 và spec "agent quick reply", đặc biệt:
  - A3: cây pane;
  - A5a: `layout.json` v1;
  - A9: phím tắt và cài đặt;
  - A12: mô hình trạng thái agent và §5 về riêng tư.

  Tài liệu này chỉ **thêm** và ghi rõ chỗ nào sửa.
- **Tài liệu đi kèm:** trang đề xuất và demo `docs/superpowers/design/2026-10-14-ai-pane-demo/`. Demo ràng buộc phần bố cục; màu và cỡ lấy theo `ShellxDesktopColors`.
- **Nguồn đã kiểm ngày 14/10/2026:**
  - schema ACP v1 bản 1.25.0 (`schema/v1/schema.json`, CHANGELOG);
  - mã nguồn `@agentclientprotocol/claude-agent-acp` 0.90.0 (gói npm);
  - tài liệu Claude Code: "Legal and compliance" và "Agent SDK overview";
  - mã nguồn ShellX (§2).
- **Ký hiệu:**
  - "D1" không tiền tố là quyết định của tài liệu này; "A12 D9" là quyết định D9 của spec A12.
  - **Tab AI:** tab có nội dung chính là pane AI.
  - **Agent:** chương trình nói ACP. Gồm Claude (qua adapter), Codex (qua adapter), Gemini CLI, OpenCode và agent tuỳ chỉnh.
  - **Lượt:** từ một `session/prompt` tới khi có `stopReason`.

---

## 1. Mục tiêu

Người không muốn dùng terminal làm việc với agent CLI qua một tab AI:
- trò chuyện với agent;
- thấy mỗi việc agent làm thành một thẻ;
- trả lời xin quyền bằng một phím;
- duyệt diff và hoàn tác;
- mở lại phiên sau khi thoát ShellX.

Tất cả không lần nào phải mở terminal. Người dùng terminal giữ nguyên trải nghiệm hôm nay.

### Tiêu chí thành công (đo được)

1. **Màn chào.**
   - Lần đầu mở bản V2, màn chào hỏi "Giao diện AI | Terminal". Chọn AI thì `new-tab-kind = ai`, và ⌘T / Ctrl+Shift+T mở tab AI.
   - Đổi lại được trong Cài đặt › Chung.
   - Người dùng đã qua onboarding của V1 thấy câu hỏi một lần, ở dạng thẻ chào (D4).
2. **Gửi câu đầu nhanh.** Điều kiện: máy đã đăng nhập Claude, có Node ≥ 22 và adapter đã cài. Từ "Phiên AI mới" tới lúc gửi câu đầu ≤ 30 s, và không pane terminal nào được tạo.
3. **Thẻ và xin quyền.**
   - Mỗi `tool_call` thành một thẻ theo `kind` (§4.2).
   - `session/request_permission` hiện thanh xin quyền.
   - Phím 1–4 chọn đúng `optionId` theo thứ tự agent gửi. Esc chọn lựa chọn `reject_*` đầu tiên.
   - Khi ô nhập đang có chữ, phím số đi vào ô nhập.
4. **Dừng lượt.**
   - Esc khi không có xin quyền nào: gửi `session/cancel`; xin quyền đang chờ trả `cancelled`.
   - Lượt phải kết thúc với `stopReason: cancelled` trong ≤ 10 s. Quá thời gian thì hiện nút "Dừng hẳn".
5. **Hoàn tác.**
   - Agent sửa bằng `sed -i` (không có diff ACP) thì panel Thay đổi vẫn liệt kê đúng tệp. "Hoàn tác lượt" khôi phục đúng nội dung.
   - Tệp bị sửa sau lượt thì hiện hộp thoại cảnh báo trước khi ghi đè.
   - `git status` của dự án giống hệt trước và sau.
6. **Khôi phục.**
   - Có tab AI → ⌘Q → mở lại: tab AI hiện đúng vị trí và tiêu đề, agent chưa chạy.
   - Chọn tab thì agent chạy và `session/load` phát lại lịch sử, ≤ 5 s với phiên khoảng 50 lượt.
   - Bản V1 đọc `layout.json` mới vẫn mở đủ tab terminal, bỏ qua tab AI, và không đổi tên tệp thành `.bak`.
7. **Trạng thái.**
   - Hàng sidebar của tab AI hiện huy hiệu A12: Đang chạy / Cần bạn trả lời / Đang chờ / Xong.
   - "Cần bạn" khi tab không được nhìn → thông báo hệ thống ghi đúng tab; bấm vào thì về tab đó.
8. **Đăng nhập.**
   - Agent trả `-32000` → hiện thẻ đăng nhập với các `authMethods`.
   - Chọn một cách → khung chạy lệnh mở với đúng lệnh. Mã thoát 0 → khung đóng và `session/new` tự thử lại.
   - ShellX không đọc nội dung khung, không lưu credential.
9. **Hỏi người dùng.** Agent hỏi bằng elicitation dạng form (ví dụ câu hỏi nhiều lựa chọn của Claude) → hiện thẻ trả lời được ngay trong hội thoại.
10. **Gõ và đọc màn hình.** Telex/IME trong ô nhập; Enter khi đang ghép chữ không gửi. VoiceOver và Narrator đọc được thẻ, thanh xin quyền và trạng thái.
11. **Không hồi quy.**
    - Mọi test hiện có vẫn xanh; tab terminal hoạt động như trước.
    - `ui.ls` của CLI đúng cho tab terminal, và liệt kê tab AI với `kind: "ai"` (D19).

---

## 2. Kiểm tra hiện trạng (đọc mã ngày 2026-10-14, đường dẫn tính từ `apps/desktop/lib/`)

| Mảng | Hiện có | Hệ quả cho V2-1 |
|---|---|---|
| Tab | `TerminalTab` (`src/terminal/terminal_tabs.dart` L343–460). Ô `focused => panes[focusedPaneId]!` (L386). Mọi getter nhãn và ngữ cảnh đi qua `focused`: index, shell, title, runningCommand, terminal, selection, cwd, gitBranch, ports, exitCode, `label`, `noticeLabel`, `hasContext`, `driver` (L396–429). Factory duy nhất là `TerminalTab.single(PaneSession)` (L357); id tab = id phiên tạo ra nó. | D2 |
| Chỗ đọc `focused`/`label` ngoài tệp | Sidebar: `session_tab_row.dart`, `session_sidebar.dart`, `sidebar_drag.dart`. Tiêu đề cửa sổ: `ui/window_host.dart:19`, `terminal_pane.dart:316`. Khung pane: `pane_tree_view.dart:288`. Tìm tất cả: `search_all_overlay.dart:34`. Bảng lệnh: `terminal_workspace_notices.dart:158`. Chép, dán, chọn hết: `terminal_workspace_page.dart` (L260, 446, 495, 563–613). Đóng tab: `close_tab.dart:33, 36`. CLI: `cli/ui_command_handler.dart:209`, `cli_event_bus.dart:184`, `cli_targets.dart:79`. Khôi phục: `restore_capture.dart:80–97`. Thông báo: `tab_attention.dart:436, 507`, `desktop_notifications.dart:261`, `notifications_panel.dart:274`, `main.dart:602, 621`, `closed_items.dart:398`. Khác: `terminal_tabs_config.dart:77–79`, `user_commands.dart:16`, `remote_marks.dart:136`, `sidebar_remote.dart:110`. | §4.7 |
| Id tổng hợp | `kSyntheticTabIdBase = 2000000000` (`terminal_tabs_panes.dart:33`). Khôi phục dùng `keyOf(-tab.id)` cho tab bị dời (`restore_capture.dart:33–36`, `restore_persistence.dart:533–537`). | D2: tab AI không dùng id âm |
| Cây pane | `PaneLeaf(int sessionId)`; mọi phép toán theo int (`pane_layout.dart` L24–359). Mẫu A6 (nhánh `feat/desktop-a6`, chưa merge) dùng lá id âm, bản đồ riêng và `activeTerminalPane`, với quy tắc A6 D5 "mỗi tab giữ ít nhất một pane terminal". | D3 |
| `layout.json` | `v: 1`. Khoá lạ ở cấp trên cùng bị bỏ qua (`restore_snapshot.dart` L227–228). Một nút lạ trong cây gây TypeError hoặc ArgumentError; `tryParse` trả null và `loadLayout` đổi tên tệp thành `layout.json.bak` (`restore_store.dart:229–243`). Workspace nhắc tới key không có trong `tabs` thì bị bỏ (L295). | D14 |
| Trạng thái agent | `ingest` cần `tabOfSession(e.pane)?.panes[e.pane]` (`agent_status_notifier.dart` L207–213). Các chỗ khác cũng chỉ nhận pane terminal: `paneVisible` L195, `_store` L369, `_updateLive` L411/423, `seedRestored` L319. `_review` (L510–527) bỏ bản ghi nào không phải pane terminal. Huy hiệu tab đi theo `tab.paneOrder` (L55–75). Thông báo gọi `localSessionsProvider.notify` → `SessionManager.notify`, mà hàm này cần một phiên đang sống. | D13 |
| Mở tab | `SshActions.newTab()` (`remote/ssh_actions.dart:84`) → `openTabIn` (`sidebar_workspaces.dart:480–495`, cwd = `Workspace.root`) → `TerminalTabs.openTab` (L660) → `openTabFor` (L686). `ensureTab()` (L764) chạy lúc khởi động. Sidebar tự đặt tab mới vào workspace (`_reconcile`, `sidebar_workspaces.dart:340, 804–812`). | D4, D5 |
| Cài đặt và onboarding | Khoá do UI giữ: `SettingsStore`/`UiSettingKeys` (`src/platform/settings_store.dart`). Khoá trong tệp cấu hình: `SettingDef` trong `config/settings_schema.dart` (mẫu `agent-resume` L533–550). Onboarding: `ui/pages/onboarding_page.dart:15`, mở ở `window_coordinator.dart:20` khi `onboardingDone` là false. | D4 |
| Cài đặt › Agents | `ui/settings/pages/agents_page.dart:27–53`. Nút Set up / Remove của tích hợp A12 mở một tab terminal (`runInTerminal`). | D7 |
| Phím tắt | `config/keybindings.dart:107–354`. ⌘⇧I đã là `toggle_notifications` (L136). ⌘⇧E / Ctrl+Shift+E còn trống. | D5 |
| Chạy tiến trình | `LoginPathCheck` (`src/cli/cli_install.dart:471`), `killProcessTree` (`src/platform/process_tree.dart:11`). | D6 |
| Điện thoại | `session.list` lấy từ phiên terminal của daemon (`packages/shellx_agent/lib/src/session/session_router.dart:70–74`). Pane không có phiên terminal thì điện thoại không thấy. | V2-2 |

---

## 3. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| D1 | Giao thức | Dùng ACP v1 qua gói Dart thuần `packages/shellx_acp`: JSON-RPC 2.0, mỗi thông điệp một dòng UTF-8 trên stdin/stdout. **Initialize** gửi `{protocolVersion: 1, clientCapabilities: {fs: {readTextFile: false, writeTextFile: false}, terminal: false, auth: {terminal: true}, elicitation: {form: {}, url: {}}}, clientInfo: {name: "shellx", title: "ShellX", version}}`. **Phương thức dùng:** `initialize`, `authenticate` (chỉ cho phương thức kiểu agent), `session/new`, `session/load`, `session/list`, `session/prompt`, `session/cancel`, `session/set_config_option`, `session/set_mode` (agent cũ). **Agent gọi:** `session/request_permission`, `elicitation/create`, `elicitation/complete`. **Bỏ qua:** loại update lạ, khoá `_meta` lạ. Không làm ACP v2 (còn là bản nháp). Kiểu dữ liệu chỉ gồm phần cần dùng, có test đối chiếu `schema.json` 1.25.0 ghim trong fixture. | Agent đổi hành vi theo v2: ghim bản adapter và chạy test tuân thủ bằng agent giả. |
| D2 | Tab AI là một loại tab | `TerminalTab` thêm `kind` (`terminal` \| `ai`) và bản đồ `aiPanes: Map<int, AiPaneState>`. Id tab AI cấp từ dải tổng hợp (≥ `kSyntheticTabIdBase`, không trùng, không âm). `focused` đổi thành `PaneSession?`: null khi tab không có pane terminal. Getter có nhánh AI: `label` = tiêu đề phiên (từ `session_info_update`, nếu không có thì câu đầu cắt 40 ký tự, nếu không có thì "Phiên AI mới"); `cwd` = thư mục phiên; các getter terminal (runningCommand, exitCode, terminal, selection, gitBranch, ports) trả null hoặc rỗng. Mọi chỗ đọc ở §2 được sửa để chịu null (danh sách và hành vi ở §4.7). | Sót một chỗ thì crash null-check. Phòng: test "tab không có pane terminal" đi qua từng màn hình (§7). |
| D3 | Pane AI trong cây pane | Pane AI là lá id âm (đếm xuống, không dùng lại, như A6), trạng thái nằm trong `aiPanes`. Mỗi tab AI có đúng một pane AI. Tab AI **không** theo quy tắc A6 D5. Nút "Terminal" trên header thêm một pane terminal bên dưới qua `splitPaneFor` có sẵn: chia trên–dưới, pane AI ở trên chiếm 72 %. Đóng pane terminal đó không đóng tab; đóng pane AI thì đóng tab (hỏi lại nếu đang có lượt chạy). Pane AI không chia thêm pane AI. | Muốn nhiều phiên trong một tab: mỗi phiên một tab (đủ cho V2-1). |
| D4 | Kiểu tab mặc định và màn chào | Thêm `SettingDef` `new-tab-kind` (`terminal` \| `ai`, mặc định `terminal`, trang Chung) theo mẫu `agent-resume`. Onboarding thêm bước "Bạn muốn làm việc theo kiểu nào?" (Giao diện AI \| Terminal) để ghi khoá này. Người đã qua onboarding V1 thấy câu hỏi một lần dưới dạng thẻ chào khi mở bản V2 (khoá UI `ai_intro_shown`). | Người dùng cũ bị hỏi thêm: chỉ một lần, bỏ qua được. |
| D5 | Mở tab AI | Thêm hành động `new_ai_session`, mặc định ⌘⇧E / Ctrl+Shift+E, vào bảng phím A9 và bảng lệnh ("Phiên AI mới"). Cũng có nút "Phiên AI mới" cuối sidebar và mục trong menu chuột phải của nút `+`. **Khi `new-tab-kind = ai`:** `new_tab`, nút `+`, nút ở empty state và `ensureTab()` mở tab AI; "Tab terminal mới" vẫn có trong menu `+` và bảng lệnh. **Thư mục:** `Workspace.root`; không có thì thư mục của tab đang focus; vẫn không có thì pane AI hiện thẻ "Chọn thư mục dự án" trước khi chạy agent. **Agent:** agent mặc định (D7). | Người dùng AI cần terminal: dùng menu `+`, bảng lệnh hoặc nút Terminal. |
| D6 | Chạy agent | Mỗi tab AI một tiến trình agent. **Adapter npm:** Claude `@agentclientprotocol/claude-agent-acp`, Codex `@agentclientprotocol/codex-acp`. Cài một lần bằng `npm install --prefix <app support>/ai/agents <gói>@<bản ghim>` và chạy `node <entry>`; chỉ nâng bản ghim sau khi đã test. **Agent khác:** Gemini `gemini --acp`, OpenCode `opencode acp`; agent tuỳ chỉnh dùng lệnh, args và env người dùng nhập. **Môi trường:** PATH và env lấy từ login shell bằng kỹ thuật ký tự đánh dấu của `LoginPathCheck`, cache trong phiên app; chạy trực tiếp, không qua shell; cwd = thư mục phiên. **Không truyền** `SHELLX_CLI_TOKEN` hay `SHELLX_SOCKET` vào agent (V2-1 chưa cần). **Node:** Claude cần `node --version` ≥ 22, thiếu thì hiện thẻ hướng dẫn. **Dừng:** đóng stdin, chờ 2 s, rồi `killProcessTree`. | Profile shell in rác ra stdout: không ảnh hưởng vì không chạy qua shell. Env thiếu biến: người dùng thêm env cho agent trong Cài đặt. |
| D7 | Cài đặt › Agents | Thêm mục "Giao diện AI", gồm: (1) mỗi agent một hàng, với trạng thái Sẵn sàng / Thiếu Node 22 / Chưa cài / Cần đăng nhập / Lỗi; (2) nút Cài đặt và Đăng nhập, chạy trong khung chạy lệnh (D8), không mở tab terminal; (3) chọn agent mặc định; (4) thêm agent tuỳ chỉnh (tên, lệnh, args, env). "Cần đăng nhập" chỉ biết sau khi một phiên bị `-32000`; ShellX không tạo phiên chỉ để kiểm. Mục tích hợp hook của A12 giữ nguyên. | Trạng thái đăng nhập không có trước lần dùng đầu: chấp nhận được. |
| D8 | Đăng nhập và khung chạy lệnh | Khi `session/new` hoặc `session/load` trả `-32000`, hiện thẻ đăng nhập liệt kê `authMethods` bằng tên do agent đặt. **Kiểu `terminal`:** mở khung chạy lệnh trên pane AI. Đó là một terminal tạm (PTY + xterm như pane terminal), không thuộc cây pane, không có phiên daemon, chạy đúng lệnh của agent kèm `args` và `env` của phương thức. Mã thoát 0 thì đóng khung và thử lại; mã khác 0 thì giữ khung và báo lỗi. **Kiểu `agent`:** gọi `authenticate {methodId}`. ShellX không đọc nội dung khung và không lưu credential. Không dùng cờ `--hide-claude-auth`, không ẩn phương thức nào (điều kiện của Anthropic, D21). | Agent đổi cách đăng nhập: ShellX chỉ đọc `authMethods`, không giả định gì thêm. |
| D9 | Mô hình phiên dùng chung | Gói Dart thuần `packages/shellx_ai` (không phụ thuộc Flutter). Reducer biến `session/update`, prompt của người dùng, yêu cầu xin quyền và elicitation thành dòng thời gian gồm: `UserItem`, `AgentText` (gộp chunk), `Thought`, `ToolItem` (theo `toolCallId`; update thay `content`), `PlanState`, `AskItem`, `TurnSummary`, `Notice`. Gói cũng giữ trạng thái lượt và hàng đợi tin. Desktop dùng ở V2-1, app điện thoại dùng ở V2-2. | — |
| D10 | Xin quyền | **Nhãn chính theo `kind`:** `allow_once` "Cho phép", `allow_always` "Luôn cho phép", `reject_once` "Từ chối", `reject_always` "Luôn từ chối". **Nhãn phụ:** giữ nguyên `name` của agent, vì chỉ agent biết "luôn" bao gồm những gì. **Phím:** 1–9 theo thứ tự `options`; Esc chọn `reject_*` đầu tiên, không có thì trả `cancelled`. Thanh xin quyền không lấy focus; ô nhập có chữ thì phím số đi vào ô nhập. Lượt bị huỷ khi đang hỏi thì trả `{outcome: cancelled}`. Một lúc chỉ hiện một yêu cầu; yêu cầu sau xếp hàng. | — |
| D11 | Chế độ, model, mức suy nghĩ | Đọc `configOptions` từ `session/new` / `session/load` và từ `config_option_update`; khi người dùng chọn thì gửi `session/set_config_option {configId, value}`. Hiện tên do agent đặt; riêng id đã biết của Claude thì dịch: `default` "Hỏi trước", `acceptEdits` "Tự sửa tệp", `plan` "Lập kế hoạch", `auto` "Tự động", `bypassPermissions` "Bỏ qua mọi quyền". Chọn `bypassPermissions` phải qua hộp xác nhận. Agent chỉ có `modes` cũ thì dùng `session/set_mode`. Nhớ lựa chọn theo từng agent cho phiên mới. | — |
| D12 | Điểm khôi phục | **Repo:** mỗi dự án một repo git ẩn, `GIT_DIR=<app support>/ai/checkpoints/<sha1(realpath dự án) 12 ký tự>`, `GIT_WORK_TREE=<dự án>`. **Trước mỗi lượt:** `git add -A` rồi `git commit --allow-empty -q`. **Sau lượt:** `git add -A` rồi `git write-tree` (không commit), để biết tệp nào bị sửa sau lượt. **Diff:** `git diff --numstat`, `git diff <ckpt> -- <tệp>`. **Hoàn tác:** `git restore --source <ckpt> --worktree -- <tệp>`; tệp tạo mới trong lượt thì xoá. Thao tác git chạy tuần tự theo hàng đợi của từng dự án. **Git dùng:** git trên PATH của login shell. Trên macOS, nếu chỉ có `/usr/bin/git` thì kiểm `xcode-select -p` trước, để không bật hộp thoại cài đặt. **Ngưỡng:** lần chụp đầu chạy nền; dự án quá 200 000 tệp, hoặc lần chụp đầu quá 30 s, thì tắt hoàn tác cho dự án đó và báo rõ. **Phạm vi:** theo `.gitignore` (tệp bị bỏ qua không được theo dõi); thư mục có `.git` riêng (repo lồng nhau) được thêm vào `info/exclude` của repo ẩn và giao diện ghi rõ. **Dọn dẹp:** tự xoá điểm khôi phục cũ hơn `ai-checkpoint-days` ngày (mặc định 14); có nút xoá trong Cài đặt. Luôn đặt `GIT_DIR` và `GIT_WORK_TREE`; không bao giờ chạy git trên `.git` của dự án. | Dự án lớn bị chậm: có ngưỡng. Thư mục không có quyền ghi: tắt hoàn tác và báo. |
| D13 | Trạng thái và thông báo | Pane AI gọi `AgentStatusNotifier.ingest` trực tiếp với `AgentEvent(pane: <id pane AI>, agent, kind, at)` theo các mốc: bắt đầu lượt → `running`; xin quyền hoặc elicitation → `needs_input`; trả lời xong → `running`; hết lượt → `idle`; agent thoát → `end`. Mọi chỗ tra pane trong notifier (`ingest`, `paneVisible`, `_store`, `_updateLive`, `_review`, `seedRestored`) đổi sang `tabOfPane` kèm kiểm "pane còn sống", không chỉ nhận pane terminal. **Thông báo:** khi `notify` trả false (không có phiên terminal) thì dùng phương thức mới `TabAttention.addAiNotice(tabId, paneId, title, body)`, theo mẫu `addCommandLine` và cùng luật A4 (không báo khi pane đang focus và cửa sổ đang active; giới hạn tần suất như A4). Điện thoại: chưa có trong V2-1 (V2-2). | — |
| D14 | Khôi phục | `layout.json` giữ `v: 1` và thêm mảng `aiTabs` ở cấp trên cùng. Mỗi phần tử: `{key, title, focused, zoomed, agent, session, cwd, layout}`. `layout` là cây gồm lá `{"ai": key}` và lá `{"pane": key, …}` như A5a. Key của tab AI vẫn nằm trong `workspaces[].tabs` đúng thứ tự trên sidebar. Bản V1 bỏ qua `aiTabs` vì là khoá lạ ở cấp trên cùng, và bỏ các key không có trong `tabs`, nên giữ nguyên tab terminal. **Khi mở lại:** tab AI hiện tiêu đề và thẻ "Tiếp tục phiên"; agent chỉ chạy khi chọn tab (khởi chạy lười). Sau đó gọi `session/load` nếu agent khai `loadSession`; nếu không thì mở phiên mới kèm ghi chú "agent này không khôi phục được phiên cũ". **Không lưu** nội dung hội thoại. | Mở lại bằng bản V1 sau khi dùng V2: mất tab AI. Chấp nhận được vì V1 không có tab AI. |
| D15 | Lịch sử phiên | Nút "Lịch sử" trên header gọi `session/list {cwd}`, nếu agent khai `sessionCapabilities.list`. Chọn một phiên thì mở tab AI mới và `session/load` phiên đó. | — |
| D16 | Ô nhập | **Gửi:** Enter gửi, trừ khi IME đang ghép chữ; Shift+Enter xuống dòng. **`@`:** tìm tệp trong dự án theo `.gitignore`, gửi kèm dạng `resource_link`. **`/`:** liệt kê lệnh từ `available_commands_update`. **Ảnh:** dán hoặc kéo ảnh vào → `image`, nếu agent khai `promptCapabilities.image`. **Đang có lượt chạy:** tin xếp hàng (tối đa 5, bỏ được), tự gửi khi lượt xong. | — |
| D17 | Hiển thị | **Markdown:** `flutter_markdown_plus`, tự chia khối để khi stream chỉ khối cuối vẽ lại. **Xem code chỉ đọc:** `re_editor` + `re_highlight`. **Diff:** `diff_match_patch` ở chế độ dòng, khung xem tự viết. Ghim các bản chạy được trên Flutter 3.41.4 (chốt ở Task 1 bằng `pub get` và build). Không hoạt ảnh lặp (nguyên tắc A1). | Gói không chạy trên 3.41.4: hạ bản; không có bản nào thì tự viết phần tối thiểu. |
| D18 | Panel Thay đổi và Tệp | Như §4.4. Cây tệp tải dần, ẩn `.git`. Làm mới khi lượt xong và khi tab được focus; V2-1 không theo dõi tệp liên tục. | Tệp đổi bên ngoài giữa lượt: chỉ thấy ở lần làm mới kế tiếp. |
| D19 | CLI | `ui.ls` liệt kê tab AI với `kind: "ai"`, `title`, `cwd` và các pane terminal của tab (nếu có). Lệnh nhắm pane terminal (`send`, `read`…) gọi trên tab AI không có pane terminal thì trả `not_found`, như hiện tại khi không tìm thấy pane. Bản CLI cũ bỏ qua khoá lạ. | Script cũ giả định mọi tab có pane terminal: nhận `not_found`, không crash. |
| D20 | Riêng tư và log | ShellX không lưu nội dung hội thoại. Không log prompt, đầu ra tool, đường dẫn hay tên tệp (theo A12 §5). stderr của agent giữ trong bộ nhớ, vòng 256 KiB mỗi phiên, cho mục "Xem log". Chỉ log tên agent, loại sự kiện, số đếm và mã thoát. `toString()` của mọi kiểu phiên trả `'…'`. | — |
| D21 | Tên gọi và điều khoản | **Tên:** menu agent hiện "Claude" (và "Claude Agent" nếu cần phân biệt); không đưa "Claude Code" vào tên tính năng hay logo; phần mô tả được ghi "chạy Claude Code". **Công tắc:** `ai-agent-claude = on \| off` (mặc định `on`) để tắt hẳn tích hợp Claude. **Trước khi phát hành công khai (việc ngoài code):** chấp nhận Commercial Terms của Anthropic; gửi mô tả kiến trúc qua contact sales để có trả lời bằng văn bản. Việc này không chặn lộ trình. | Anthropic đổi điều khoản: tắt tích hợp bằng công tắc, kèm bản cập nhật. |
| D22 | Elicitation | **Dạng `form`:** thẻ trả lời trong hội thoại, hỗ trợ trường string, number, boolean, enum chọn một và enum chọn nhiều; trả `accept` kèm `content`, `decline` hoặc `cancel`. **Dạng `url`:** thẻ hiện đúng URL, nút "Mở trong trình duyệt" (chỉ http/https, phải bấm) và "Huỷ"; `elicitation/complete` thì đóng thẻ. Elicitation đang chờ cũng tính là `needs_input` (D13). | Schema có kiểu chưa hỗ trợ: thẻ hiện "Câu hỏi này dùng kiểu trả lời ShellX chưa hỗ trợ" và trả `decline`. |
| D23 | Agent mặc định và danh sách | Danh sách agent đã biết: Claude, Codex, Gemini CLI, OpenCode, cộng agent tuỳ chỉnh. Agent mặc định là agent đầu tiên đang "Sẵn sàng", theo thứ tự trên; người dùng đổi được. | — |

---

## 4. Giao diện và chuỗi (EN + VI)

Màu, khoảng cách và cỡ chữ theo `ShellxDesktopColors`, `ShellxSpace` và `ShellxSizes`. Không có hoạt ảnh lặp. Bố cục theo demo.

### 4.1 Bố cục tab AI

- **Header của pane AI, 34 px.** Đây là header riêng của pane AI. Khi tab có thêm pane terminal, pane đó vẫn dùng header pane của A3 như cũ.
- **Nội dung header:**
  - chip agent (biểu tượng + tên);
  - tiêu đề phiên (`small`, `textSecondary`, cắt bằng dấu ba chấm);
  - huy hiệu trạng thái A12 cỡ lớn, có đồng hồ khi đang chạy ("Đang chạy · 0:12");
  - nút Lịch sử, Panel (Thay đổi · Tệp), Terminal, Phóng to và ⋯. Menu ⋯ gồm: Cài đặt › Agents, Khởi động lại agent, Xem log.
- **Cột hội thoại:** rộng tối đa 760 px. Dưới cùng là dock gồm, theo thứ tự từ trên xuống:
  1. thanh kế hoạch (gập được);
  2. thanh xin quyền;
  3. hàng đợi tin;
  4. ô nhập: textarea tự giãn (tối đa 140 px), dưới là hàng @, /, ảnh, chip cấu hình (`configOptions`), mức dùng ngữ cảnh ("Ngữ cảnh 16%", từ `usage_update`) và nút Gửi / Xếp hàng / Dừng.
- **Panel phải, 268 px:** hai tab "Thay đổi" và "Tệp".
- **Lớp phủ trên cột hội thoại:** khung xem diff hoặc tệp; khung chạy lệnh (D8); thẻ "Tiếp tục phiên" (D14).

### 4.2 Thẻ theo loại việc

| `kind` (ACP) | Hiển thị |
|---|---|
| `read` | "Đọc `<đường dẫn tương đối>`". Bấm vào mở khung xem tệp đúng dòng (`locations[0].line`). |
| `search` | "Tìm `<title>`". Mở thẻ ra thì thấy kết quả. |
| `fetch` | "Tải `<title>`". Mở thẻ ra thì thấy kết quả. |
| `edit` | Gồm 3 phần:<br>• "Sửa `<tệp>`", hoặc "Tạo `<tệp>`" khi diff có `oldText: null`;<br>• số dòng +/− tính từ diff;<br>• diff mở rộng được, có "Xem cả tệp" và "Mở trong editor".<br>Thẻ mở sẵn khi đang xin quyền. |
| `delete` | "Xoá `<tệp>`". |
| `move` | "Đổi tên `<tệp>`". |
| `execute` | "Chạy `<lệnh>`". Lệnh xong thì thẻ tự mở, hiện đầu ra (màu cơ bản), mã thoát và thời gian chạy. Không có đầu ra thì ghi "Không có đầu ra" và nhắc rằng panel Thay đổi vẫn thấy tệp đổi. |
| `think` | Gập sẵn. |
| `switch_mode` | Một dòng thông báo đổi chế độ. |
| `other` | `title`; tên dạng `mcp__a__b` hiện thành "a · b". Mở thẻ ra thì thấy `rawInput` và kết quả. |

**Trạng thái thẻ:**

| Trạng thái | Hiển thị |
|---|---|
| `pending` | "chờ" |
| Đang xin quyền | "chờ bạn" (màu `warn`) |
| `in_progress` | chấm `accent` + "đang chạy · 2,1 s" (chữ, không hoạt ảnh) |
| `completed` | ✓ |
| `failed` | "bị từ chối", "đã dừng" hoặc "lỗi", tuỳ ngữ cảnh |

**Khác:**
- Suy nghĩ (`agent_thought_chunk`) dùng `details` gập sẵn.
- Cuối mỗi lượt có thẻ tóm tắt: "Lượt N · 0:41 · 2 tệp đổi +44 −5 · Xem · Hoàn tác lượt", hoặc "Đã dừng lượt N…".

### 4.3 Thanh xin quyền

- **Nền và viền:** `warnBg`, viền `warnBorder`.
- **Dòng đầu:** "{agent} xin quyền: **{nhãn thẻ}**".
- **Nút:** một hàng. Mỗi nút có `kbd` số thứ tự và nhãn theo `kind` (D10). Lựa chọn `reject_*` đầu tiên có thêm `kbd` "Esc".
- **Dòng phụ:** chữ gốc của agent cho lựa chọn `*_always`, ví dụ “Luôn cho phép” theo lời agent: *Yes, allow all edits during this session*.
- **Trên thẻ trong hội thoại:**
  - đang chờ: "Chờ bạn trả lời ở thanh xin quyền phía dưới — phím 1–n, Esc để từ chối";
  - đã trả lời: "Bạn chọn: Cho phép (Yes)".
- **Trợ năng:** `Semantics(liveRegion)` đọc dòng đầu một lần.

### 4.4 Panel Thay đổi và Tệp

- **Thay đổi:**
  - Công tắc "Lượt này | Cả phiên".
  - Mỗi tệp một hàng: trạng thái M/A/D, đường dẫn (phần thư mục màu `dim`), +/−, ô "Đã xem" (gắn với nội dung hiện tại của tệp) và nút hoàn tác tệp. Tệp bị sửa sau lượt có nhãn "đã sửa sau lượt" màu `warn`.
  - Chân panel: "Điểm khôi phục: trước lượt N · `<hash>`", nút "Hoàn tác lượt" hoặc "Hoàn tác cả phiên", và dòng "Không theo dõi tệp bị `.gitignore` bỏ qua".
  - Hoàn tác khi có tệp sửa sau lượt thì hiện hộp thoại "Có tệp đã đổi sau lượt này" với ba lựa chọn: Huỷ / Chỉ hoàn tác tệp chưa sửa / Hoàn tác tất cả. Lựa chọn thứ ba là nút phá huỷ; focus ban đầu ở Huỷ (UI §4).
- **Tệp:**
  - Cây thư mục, thư mục trước, tệp sau.
  - Tệp đổi trong phiên có nhãn M/A; tệp bị `.gitignore` bỏ qua có nhãn mờ "bỏ qua".
  - Bấm tệp thì mở khung xem chỉ đọc, có hai nút "Mở trong editor" (link-editor sẵn có) và "Nhắc trong chat" (chèn `@đường dẫn` vào ô nhập).

### 4.5 Thẻ thông báo trong hội thoại

| Tình huống | Thẻ |
|---|---|
| Cần đăng nhập | Thẻ đăng nhập, mỗi phương thức một nút (D8) |
| Thiếu Node 22 | Có nút "Hướng dẫn cài" |
| Agent chưa cài | Có nút "Cài đặt", chạy trong khung chạy lệnh |
| Agent dừng bất ngờ | Có nút "Khởi động lại" và "Xem log" |
| Không khôi phục được phiên | Ghi chú: "agent này không khôi phục được phiên cũ" |
| Thư mục không còn | Có nút "Chọn thư mục" |

### 4.6 Chuỗi chính

Trong `app_en.arb` và `app_vi.arb`; trạng thái agent dùng lại các khoá A12.

| Khoá | EN | VI |
|---|---|---|
| `aiNewSession` | New AI session | Phiên AI mới |
| `aiNewTabKindLabel` | New tabs open as | Tab mới mở dạng |
| `aiNewTabKindAi` / `…Terminal` | AI interface / Terminal | Giao diện AI / Terminal |
| `aiOnboardingTitle` | How do you want to work? | Bạn muốn làm việc theo kiểu nào? |
| `aiComposerHint` | Message {agent}… (@ file, / command) | Nhắn cho {agent}… (@ nhắc tệp, / gọi lệnh) |
| `aiPermTitle` | {agent} asks: {action} | {agent} xin quyền: {action} |
| `aiPermAllowOnce` / `AllowAlways` / `RejectOnce` / `RejectAlways` | Allow / Always allow / Reject / Always reject | Cho phép / Luôn cho phép / Từ chối / Luôn từ chối |
| `aiTurnSummary` | Turn {n} · {time} · {count} files changed | Lượt {n} · {time} · {count} tệp đổi |
| `aiRevertTurn` / `aiRevertSession` | Revert turn / Revert session | Hoàn tác lượt / Hoàn tác cả phiên |
| `aiChangedAfterTurn` | changed after the turn | đã sửa sau lượt |
| `aiLoginNeeded` | {agent} needs you to sign in | {agent} cần đăng nhập |
| `aiRunSheetLogin` / `aiRunSheetInstall` | Sign in to {agent} / Install {agent} | Đăng nhập {agent} / Cài {agent} |
| `aiNodeMissing` | {agent} needs Node.js 22 or newer | {agent} cần Node.js 22 trở lên |
| `aiAgentExited` | {agent} stopped unexpectedly (exit {code}) | {agent} dừng bất ngờ (mã thoát {code}) |
| `aiForceStop` | Force stop | Dừng hẳn |
| `aiResumeSession` | Resume session | Tiếp tục phiên |
| `aiHistory` | Session history | Lịch sử phiên |
| `aiNoUndo` | Undo is off for this project ({reason}) | Hoàn tác đang tắt cho dự án này ({reason}) |
| `aiBypassConfirm` | {agent} will edit files and run commands without asking. | {agent} sẽ sửa tệp và chạy lệnh mà không hỏi. |

### 4.7 Những chỗ đọc tab phải sửa (D2)

| Chỗ | Hành vi với tab AI |
|---|---|
| Hàng sidebar (`session_tab_row.dart`, `session_sidebar.dart`) | Biểu tượng AI thay cho chấm trạng thái shell. Dòng 2 là huy hiệu A12 "{trạng thái} · {agent}". Ẩn cổng và nhánh git. |
| Tiêu đề cửa sổ, đầu pane | Dùng `label` (D2) |
| Kéo thả trong sidebar (`sidebar_drag.dart`) | Như tab terminal. Pane AI không chuyển sang tab khác. |
| Khung pane (`pane_tree_view.dart:288`) | Lá id âm vẽ pane AI |
| Tìm tất cả (`search_all_overlay.dart`) | Bỏ qua pane AI |
| Chép, dán, chọn hết, sửa dòng (`terminal_workspace_page.dart`) | Khi focus nằm trong pane AI, nhường cho ô nhập và khung xem; không gọi `terminal` |
| Bảng lệnh "Chuyển pane sang tab…" | Không áp dụng cho pane AI |
| Đóng tab (`close_tab.dart`) | Đang có lượt chạy thì hỏi "Dừng lượt và đóng?" |
| CLI (`ui_command_handler.dart`, `cli_targets.dart`, `cli_event_bus.dart`) | Theo D19. Không phát `pane.focused` cho id âm. |
| Khôi phục (`restore_capture.dart`) | Theo D14 |
| Thông báo (`tab_attention.dart`, `desktop_notifications.dart`, `notifications_panel.dart`, `closed_items.dart`, `main.dart`) | Nhãn lấy từ `label`; đường AI theo D13 |
| `terminal_tabs_config.dart` (working-directory `inherit`), `user_commands.dart` | Dùng `cwd` của phiên AI |
| `remote_marks.dart`, `sidebar_remote.dart` | Tab AI không có dấu remote |

---

## 5. Riêng tư, an ninh và log

- **Credential:** ShellX không bao giờ đọc, lưu hay chuyển. Đăng nhập chạy trong khung chạy lệnh bằng chính lệnh của agent, và ShellX không phân tích đầu ra của khung.
- **Tiến trình agent:**
  - Env lấy từ login shell; không thêm bí mật nào của ShellX (không `SHELLX_CLI_TOKEN`).
  - Agent tự quyết việc ghi tệp và chạy lệnh trong giới hạn quyền mà người dùng cấp qua xin quyền và chế độ.
- **"Bỏ qua mọi quyền":** chỉ bật được qua hộp xác nhận. Hộp này ghi rõ điểm khôi phục không lấy lại được việc đã ra ngoài máy (push, gọi API).
- **Điểm khôi phục:** chứa bản sao tệp dự án trong thư mục dữ liệu của ShellX, cùng quyền với người dùng. Tự dọn sau `ai-checkpoint-days` ngày và có nút xoá.
- **Log:** theo D20. `toString()` của `AiPaneState`, các mục dòng thời gian và thông điệp ACP trả `'…'`; có test ghim.
- **Elicitation URL:** chỉ mở http/https sau khi người dùng bấm, và hiện nguyên URL trước khi mở.

---

## 6. Lỗi và biên

| Tình huống | Xử lý |
|---|---|
| Không tìm thấy lệnh agent hoặc `node` | Thẻ "Chưa cài" hoặc "Thiếu Node 22" có nút làm ngay; agent không chạy |
| Cài adapter lỗi (npm) | Khung chạy lệnh giữ đầu ra lỗi; trạng thái "Lỗi"; có nút thử lại |
| `-32000` | D8 |
| Agent thoát giữa lượt | Lượt kết thúc "bị gián đoạn"; thẻ đang chạy thành "đã dừng"; thẻ lỗi có "Khởi động lại" (chạy lại agent rồi `session/load`) và "Xem log" |
| Dừng mà không xong sau 10 s | Nút "Dừng hẳn" gọi `killProcessTree`; lượt kết thúc phía ShellX |
| Dòng không phải JSON trên stdout | Bỏ qua. Quá 20 dòng hỏng liên tiếp thì coi là agent lỗi: dừng và báo |
| Dòng rất dài | Nhận tới 64 MiB một dòng; quá thì dừng agent và báo |
| Update đến sau `stopReason` (tác vụ nền) | Vẽ vào lượt vừa xong |
| Loại update lạ, `_meta` lạ | Bỏ qua |
| Xin quyền với `toolCallId` không có thẻ | Thanh xin quyền dùng `title` trong yêu cầu |
| Agent không khai `loadSession` | Mở lại thì tạo phiên mới kèm ghi chú (D14) |
| Thư mục phiên không còn khi khôi phục | Thẻ "Thư mục không còn", có nút chọn thư mục |
| Không có git, thiếu Command Line Tools, dự án vượt ngưỡng | Tắt hoàn tác cho dự án đó; thẻ `aiNoUndo` nói rõ lý do |
| Chụp điểm khôi phục lỗi giữa chừng | Lượt vẫn chạy; tắt hoàn tác cho lượt đó và báo |
| Hai tab AI cùng một dự án | Thao tác git tuần tự theo hàng đợi. Mỗi tab so với điểm khôi phục của chính nó; tệp do tab kia sửa sau lượt hiện "đã sửa sau lượt" |
| Agent ghi ra ngoài thư mục dự án | Không theo dõi; ghi trong mô tả panel Thay đổi |
| Windows | Diff so sánh sau khi chuẩn hoá CRLF để hiển thị (hoàn tác ghi lại đúng byte); đường dẫn không phân biệt hoa thường khi so `realpath` |
| Thoát app khi agent đang chạy | Đóng stdin, chờ 2 s, `killProcessTree`; không để lại tiến trình mồ côi |
| App crash khi agent đang chạy | Mỗi agent khi khởi chạy được ghi `{pid, lệnh, lúc chạy}` vào `<app support>/ai/running.json` và xoá khi dừng. Lần mở sau, tiến trình nào còn sống mà lệnh và thời điểm chạy khớp bản ghi thì bị dừng bằng `killProcessTree`; không khớp thì bỏ qua (pid đã bị dùng lại). |

---

## 7. Kiểm thử

- **`shellx_acp`:**
  - tách dòng, id và lỗi JSON-RPC (gồm `-32000`);
  - khoá lạ, dòng 64 MiB, dòng hỏng;
  - test tuân thủ: mọi kiểu dùng tới được kiểm với `schema.json` 1.25.0 (fixture ghim).
- **`shellx_ai`:**
  - gộp chunk, update thay `content`, kế hoạch;
  - hàng đợi xin quyền, huỷ khi đang hỏi;
  - elicitation form và url, phát lại `session/load`;
  - hàng đợi tin.
- **Agent giả** (script Dart trong test), nói ACP theo kịch bản:
  - stream, các loại tool, diff, xin quyền;
  - đòi đăng nhập, chết, treo sau `session/cancel`;
  - rác trên stdout, dòng 10 MiB, update sau `stopReason`.

  Kịch bản lấy từ bản ghi phiên thật của Claude và Codex ở Task 1, đã lọc nội dung riêng.
- **Điểm khôi phục:** chạy git thật trong thư mục tạm, cả macOS và Windows (CI `windows-check`):
  - chụp, diff, hoàn tác (gồm tệp mới và tệp bị xoá);
  - `.gitignore`, repo lồng nhau, ngưỡng;
  - "sửa sau lượt";
  - `.git` của dự án không đổi (so `git status --porcelain` và mtime của `.git/index`).
- **Widget desktop:**
  - tab AI không có pane terminal đi qua từng chỗ ở §4.7;
  - thẻ theo `kind`;
  - thanh xin quyền: phím số, Esc, phím số đi vào ô nhập khi có chữ;
  - bước màn chào, khung chạy lệnh (mở, đóng khi mã 0);
  - thẻ elicitation, hàng đợi tin.
- **Khôi phục:**
  - lưu rồi đọc lại `aiTabs`;
  - **tương thích V1:** parser V1 (bản tại `164bba6`) đọc tệp có `aiTabs` → giữ tab terminal, không đổi tên thành `.bak`.
- **Khác:**
  - phím `new_ai_session` (`keybindings_test.dart`);
  - khoá cài đặt mới (`settings_ownership_test.dart`);
  - `toString()` trả `'…'`.

---

## 8. Review Focus

1. Mọi chỗ đọc `focused`/`label` (§4.7) chịu được tab không có pane terminal. Kiểm bằng grep và test.
2. Không đọc, lưu hay chuyển credential. Khung chạy lệnh không bị phân tích.
3. Mọi lệnh git của điểm khôi phục đều đặt `GIT_DIR` và `GIT_WORK_TREE`; không có đường nào chạm `.git` của dự án.
4. `layout.json` vẫn tương thích V1.
5. Không để lại tiến trình agent mồ côi khi đóng tab hay thoát app. Nếu app crash, lần mở sau dọn theo `ai/running.json` (§6).
6. Không bao giờ tự cho phép: mặc định không có lựa chọn nào tự trả lời.

---

## 9. ⚠ Kiểm tay (cần người trước Mac và Windows)

- **Claude thật** (adapter 0.90.x ghim), trên macOS và Windows: cả luồng, gồm xin quyền, dừng, đăng nhập bằng Claude Subscription và Anthropic Console trong khung chạy lệnh, khôi phục, lịch sử, elicitation (câu hỏi nhiều lựa chọn).
- **Codex:** cài adapter, đăng nhập, một lượt sửa tệp.
- **Gemini CLI và OpenCode:** một lượt cơ bản.
- **Gõ và đọc màn hình:** Telex trong ô nhập (macOS, Windows); VoiceOver và Narrator trên thẻ, thanh xin quyền, trạng thái.
- **Dự án lớn** (khoảng 100 000 tệp): thời gian chụp lần đầu, ngưỡng.
- **Mạng và môi trường:** npm sau proxy; máy thiếu Node; không có Command Line Tools trên macOS.

---

## 10. Ngoài phạm vi V2-1

- Trình soạn thảo, LSP.
- `terminal/*` và `fs/*` của ACP: agent chạy lệnh trong terminal của ShellX, ShellX ghi tệp hộ agent.
- Worktree riêng cho từng phiên; nhiều pane AI trong một tab.
- Cài agent từ ACP Registry; tự tải kèm Node.
- Điện thoại (V2-2); tool qua URL (V2-3, V2-4).
- Truyền `SHELLX_CLI_TOKEN` cho agent.
- Chen tin vào lượt đang chạy (`_session/steering` là phần mở rộng riêng của adapter Claude).

---

## 11. Lộ trình V2 sau V2-1 (mỗi mục một spec)

| Phần | Phạm vi | Phụ thuộc |
|---|---|---|
| **V2-2 Điện thoại: phiên AI** | Loại tin `ai.*` trong kênh mã hoá đầu cuối: list, attach, snapshot, update, prompt, answer, cancel, open. Chia nhỏ theo khung 64 KiB. Màn phiên AI trên app (dùng `shellx_ai`). Trả lời xin quyền ngay trên thông báo đẩy. Bản cũ bỏ qua loại tin lạ. | V2-1 |
| **V2-3 Tool qua URL (desktop)** | Danh sách tool theo workspace (tên, URL, cờ điện thoại); gợi ý từ cổng A2. Pane tool dùng engine A6: chỉ báo localhost, cô lập cookie. Lưu tool trong `aiTabs` / `tabs`. | **Cổng engine A6 (Task 1)** trên Mac và Windows thật; không đạt thì dùng cửa sổ con native |
| **V2-4 Tool trên điện thoại** | Đường hầm `tool.*` (HTTP và WebSocket) qua kênh mã hoá đầu cuối. Desktop chỉ proxy tới đúng origin của tool đã bật. Điện thoại chạy server loopback và webview. Giới hạn: khung 64 KiB, 500 khung/giây, tồn đọng 4 MiB. | Danh sách tool của V2-3, nhưng **không** cần engine desktop |

---

## 12. Rủi ro và việc kiểm ở Task 1

| Rủi ro | Mức | Xử lý |
|---|---|---|
| Sửa mô hình tab: nhiều chỗ giả định có pane terminal | Trung bình | §4.7 và test ở §7 |
| Adapter đổi nhanh (đã đổi tên một lần; ACP v2 là bản nháp) | Trung bình | Ghim bản, chỉ làm v1, test tuân thủ |
| Điều khoản Anthropic về đăng nhập Claude | Trung bình | D8, D21 |
| Dự án lớn làm chậm điểm khôi phục | Trung bình | Ngưỡng D12 |
| Gói Flutter mới cần 3.44 | Thấp–TB | D17 |

**Task 1 kiểm trước khi viết code chính:**
1. Ghi lại phiên thật của Claude (adapter 0.90.x) và Codex, với `fs` và `terminal` đặt false, để làm fixture.
2. `codex-acp` bản hiện hành: yêu cầu Node và cách đăng nhập.
3. `pub get` cùng build với các gói D17 trên Flutter 3.41.4.
4. Gemini CLI chạy được khi không có `fs/*`.
5. Claude dùng elicitation form cho câu hỏi nhiều lựa chọn khi client khai `elicitation.form`.

Mỗi mục có kết quả ghi vào ledger. Kết quả trái với spec thì sửa spec trước khi làm tiếp.
