# A12 — Agent và đợt trau chuốt (desktop + CLI + mobile) — Đặc tả thiết kế

- **Ngày:** 2026-10-07
- **Trạng thái:** Người dùng vắng mặt và giao toàn quyền quyết định sản phẩm cho người viết spec (như A1–A11). Phạm vi do người dùng nêu (ràng buộc): mục 23, 24, 33, 34, 36 của §5 gap analysis (`docs/superpowers/research/2026-10-07-cmux-gap-analysis.md`), phần "agent" của §1.3, PR status (mục 19, hoãn từ A11 D2), các mục A11 hoãn sang A12 (D36: T22 độ trong suốt/blur, chọn ngôn ngữ, nút kiểm cập nhật, đặt mô tả/trạng thái tab từ CLI/hook). D1–D27 do người viết spec chốt, ghi ở bảng §3 kèm cái giá nếu sai.
- **Lộ trình:** A1 → … → A11 → **A12 (tài liệu này)**.
- **Nền:** `main` sau A11 (đã gộp) và logo mới (`686375c`). A12 **được phép** thêm: một loại tin CLI (`ui.agent.event`, `ui.tab.meta`) vào `shellx_agent` (hằng số + cap), hai khoá tuỳ chọn trong `SessionInfo` của `shellx_core` (D22), mã Rust ở `term/`. A12 **không** sửa `src/mux/*` ngoài các hằng số trên, `daemon_main.dart`, relay, giao thức điện thoại ngoài D22.
- **Giữ nguyên:** spec A1–A11; đặc biệt A4 (thông báo theo pane, OSC 9/99/777 → `SessionNotice`), A5a/A5b (`layout.json`, `RestorePlan.reattach`), A7 (CLI, mọi thông điệp tiếng Anh, mã thoát), A9 D5/D8 (cú pháp và hàm thuần của cấu hình), A11 D4/D5 (một chủ cho mỗi khoá cài đặt; tệp của người dùng chỉ ghi khi có thao tác), A11 D18 (`TabMeta`).
- **Ký hiệu:** "A11 D5" = quyết định D5 của spec A11; "D1" không tiền tố = của tài liệu này. "Tab" = một hàng sidebar (cây pane); "workspace" = nhóm tab. "Agent" = chương trình lập trình AI chạy trong terminal (Claude Code, Codex, Gemini CLI, OpenCode). Plan: `docs/superpowers/plans/2026-10-07-agents-a12.md`.

---

## 1. Mục tiêu

Biến sidebar thành bảng theo dõi agent đáng tin cậy: nhìn một hàng biết agent trong tab đó **đang chạy, đang chờ bạn trả lời, nhàn rỗi hay vừa xong**; thông báo "cần bạn" đến đúng pane; sau khi máy khởi động lại, một cú bấm đưa agent về đúng phiên cũ; cài hook cho agent bằng một lệnh, có xem trước từng dòng thay đổi và không bao giờ đè lên cấu hình của người dùng. Thêm trạng thái pull request cạnh nhánh (tuỳ chọn, qua `gh`), và dọn nốt các mục A11 hoãn (ngôn ngữ app, nút kiểm cập nhật, độ trong suốt cửa sổ macOS nếu an toàn, mô tả/trạng thái tab từ CLI).

### Tiêu chí thành công (đo được)

1. **Cài hook:** `shellx integrations install claude` in diff đúng như sẽ ghi (chỉ các dòng thêm, ngữ cảnh 2 dòng, giá trị của khoá có tên giống `key|token|secret|password|auth` bị che trong **phần hiển thị**), hỏi `Apply these changes to ~/.claude/settings.json? [y/N]`; `n` hay Enter trần = không ghi byte nào. Sau `y`: file có thêm đúng 5 nhóm hook (D6), mọi byte còn lại **giữ nguyên** (kể cả hook, chú thích-không-có, thụt lề, CRLF của người dùng); có `settings.json.shellx-bak` là bản trước đó. Chạy lần hai: "already installed", file không đổi (so byte). `uninstall` xoá **chỉ** nhóm của ShellX; hook của người dùng còn nguyên; file do ShellX tạo mới mà giờ chỉ còn nội dung ShellX → xoá file.
2. **Trạng thái:** trong tab ShellX, `claude` nhận prompt → hàng tab hiện "Đang chạy" ≤ 500 ms sau `UserPromptSubmit`; Claude hỏi quyền → "Cần bạn trả lời" + vòng/dấu cảnh báo pane + thông báo hệ thống (pane không focus) ghi đúng pane đó, kể cả khi người dùng đang xem tab khác; trả lời xong → "Đang chạy"; `Stop` → "Đang chờ" (hoặc "Xong" nếu pane lúc đó không được xem), "Xong" tự về "Đang chờ" khi pane được focus. Nhấn Esc ngắt lượt (Claude không gọi `Stop`) → "Đang chạy" tự về "Đang chờ" sau 20 s pane im lặng. Tab có nhiều pane agent hiện trạng thái ưu tiên cao nhất (cần bạn > đang chạy > xong > chờ).
3. **Thông báo:** mỗi lượt "cần bạn" tạo **một** thông báo cho pane gốc; hook + OSC của cùng agent trong 3 s gộp thành một; subagent (`SubagentStop`) không tạo gì; ≤ 1 thông báo mỗi pane mỗi 5 s từ hook.
4. **Resume:** đang chạy `claude` trong pane có thư mục `~/proj`, thoát app (hoặc app crash), mở lại → pane có dải "Claude Code đang chạy ở đây trước khi ShellX khởi động lại. [Tiếp tục phiên] [Bỏ qua]"; bấm "Tiếp tục phiên" gõ `claude --resume <id>` + Enter **một lần**, chỉ khi shell sẵn sàng; không bấm thì **không có gì chạy**. Bật dịch vụ nền A5b (`reattach`) → không có dải (shell còn sống), trạng thái cũ "chưa rõ" cho tới sự kiện kế tiếp. Agent đã thoát bình thường (`SessionEnd`) → không có dải.
5. **PR status (tuỳ chọn):** bật trong Cài đặt, máy có `gh` đã đăng nhập: tab ở nhánh có PR hiện `#123` + trạng thái (mở/nháp/đã merge/đóng) + CI (đạt/lỗi/đang chạy) ≤ 10 s sau khi chọn tab; không có `gh`/chưa đăng nhập → không hiện gì, không báo lỗi lặp; ≤ 6 lần gọi `gh`/phút, không bao giờ chặn UI; ShellX không đọc token (chỉ chạy `gh`).
6. **Hook thông báo người dùng:** `agent-event-command = ~/bin/on-agent` chỉ chạy sau khi người dùng bấm "Cho phép" cho **đúng chuỗi lệnh đó**; chạy không qua shell, môi trường tối thiểu, timeout 10 s, ≤ 4 cùng lúc.
7. **Ngôn ngữ:** Cài đặt › Chung › Ngôn ngữ (Theo hệ thống / English / Tiếng Việt); chọn → có hiệu lực sau khởi động lại; thông báo, khay, menu theo ngôn ngữ đã chọn.
8. **Cập nhật:** nút "Kiểm tra cập nhật" cho một trong ba kết quả (mới nhất / có bản mới + Tải xuống / không kiểm tra được), dùng đúng kênh `/v1/version` và kiểm tra URL tin cậy có sẵn.
9. **CLI:** `shellx tab describe T3 "fix login"` và `shellx tab status T3 review` đặt mô tả/trạng thái (A11 D18) của tab; `shellx ls --json` có `agent`, `agent_status` mỗi pane.
10. **Mobile:** danh sách phiên trên điện thoại cho thấy "Claude · cần bạn trả lời" cạnh phiên của desktop khi desktop gửi (D22); điện thoại cũ vẫn hoạt động (khoá lạ bị bỏ qua).
11. **Riêng tư:** chạy tiêu chí 1–10 với log debug → log không chứa nội dung `message` của hook, id phiên, đường dẫn, lệnh hook của người dùng, đầu ra `gh`, tên nhánh (`grep` chuỗi thử nghiệm rỗng).
12. **Không hồi quy:** mọi test A1–A11 xanh; pane không có hook hoạt động giống hệt trước; file cấu hình agent của người dùng **không bao giờ** bị ghi nếu họ không trả lời `y`/`--yes`; `layout.json` cũ đọc được, bản cũ đọc `layout.json` mới được (khoá tuỳ chọn).

---

## 2. Kiểm tra hiện trạng (đọc mã ngày 2026-10-07, trước khi quyết)

Mục có HAVE bị **bỏ hoặc thu nhỏ**.

| Mục | Kết quả | Bằng chứng | Hệ quả cho A12 |
|---|---|---|---|
| 23 Cài hook agent | MISSING | `term/src/api/args.rs` không có `integrations`; chỉ `skills print` (`api/skills.rs`) | Làm (T3–T6) |
| 23 Nhận sự kiện hook | MISSING | không có lệnh nhận JSON hook; `shellx notify` (`api/run/notify.rs`) chỉ gửi chữ | Làm `agent-event` (T2) |
| 23 JSON/TOML trong CLI | Không có thư viện | `term/Cargo.toml` không có `serde`/`toml`; `api/value.rs` chỉ có CBOR + `to_json` | Tự viết bộ đọc JSON có vị trí byte, **không thêm crate** (D8) |
| 2 Chip "Agent" | Là cái khác | `ui/terminal/agent_chip.dart` + `cli/agent_marks.dart`: "lệnh CLI vừa tác động tab, 10 s" (A7 D27) — **không** phải trạng thái agent | Giữ nguyên; trạng thái agent là thành phần mới (T7–T8) |
| 2 Trạng thái Running/Needs input/Idle | MISSING | không có kiểu trạng thái agent trong `lib/src` (`grep AgentStatus` rỗng) | Làm (T7–T8) |
| 2 Trạng thái do người dùng đặt | HAVE (khác) | `terminal/tab_meta.dart` `TabStatus` (none/in_progress/review/blocked/done) tay đặt, lưu `layout.json` | Giữ tách biệt: trạng thái agent tự động, không ghi vào `TabMeta` (D9) |
| 2 Thông báo đúng pane | HAVE | `LocalSessions.notify(pane, …)` (`local_sessions_provider.dart`), A4 D18 vòng theo pane, `cli.notify`/`SHELLX_PANE_ID` | Hook dùng lại đường này (D10) |
| 3 Khôi phục | Một nửa | `restore_snapshot.dart` `SavedPane{key,cwd,session,launch}`; `RestorePlan.reattach` (A5b) | Thêm khoá tuỳ chọn `agent` + dải mời (T9) |
| 3 Gõ lệnh khi shell sẵn sàng | HAVE | `PaneIoCommands.typeCommand` → `CommandInjector` (A7 D16) | Dùng cho "Tiếp tục phiên" |
| 4 Nhánh git | HAVE | `TerminalTab.gitBranch` đọc `.git/HEAD` (`GitHeadReader`, A2), không chạy `git` | PR dùng nhánh sẵn có; chỉ chạy `gh` |
| 4 PR status | MISSING | không có `gh` trong `lib/src` | Làm, **tắt mặc định** (D16, T11) |
| 5 T22 trong suốt/blur | Hoãn từ A11 | HANDOFF §21 "Hoãn A12"; plan A11 Task 22 còn nguyên | Làm lại như tác vụ cuối, có cổng ⚠ (D21, T15) |
| 5 Chọn ngôn ngữ | MISSING | `src/l10n/locale.dart` chỉ `resolveAppLocale(system)`; `main.dart:95` | Làm nhỏ (D19, T13) |
| 5 Nút kiểm cập nhật | Kênh **có** | relay `GET /v1/version` → `latest_agent{version,mac_url,win_url}`; `agent/update_check.dart` `evaluateUpdate` + `isTrustedDownloadUrl`; `AgentController.checkForUpdate()` chỉ chạy tự động | Làm nút (D20, T14); không cần appcast |
| 5 Tự cài bản cập nhật | Không có kênh | `release/` không có appcast/latest.json; chỉ có link tải | **Hoãn lần nữa** (§10) |
| 6 Hook thông báo người dùng | MISSING | không có | Làm nhỏ, có cổng cho phép (D17, T12) |
| 11 `tab describe/status` CLI | MISSING | `args.rs` không có; A11 D2 hoãn | Làm (D18, T16) |
| cmux: ngủ đông agent, fork, Feed, inbox, Teams, sửa tên workspace bằng AI | — | `docs/agent-hooks.md` | **Bỏ** (sản phẩm riêng của cmux) |
| cmux: ~18 agent | — | `CLI/CMUXCLI+AgentHookCatalog.swift` | Làm 4: `claude`, `codex`, `gemini`, `opencode` (D6) |
| Điện thoại | Thêm nhỏ | `SessionInfo` (`shellx_core/…/messages.dart:124`) đã có khoá tuỳ chọn `cwd`,`branch` chỉ gửi khi `desktop:true` (A2 C4) | Thêm 2 khoá cùng mẫu (D22, T17) |

---

## 3. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| D1 | Nền, độc lập | `main` sau A11. Mỗi task gộp độc lập (không có tính năng nửa vời nhìn thấy được). Ràng buộc cứng: T1 → T2 → T3; T3 → T4/T5/T6; T7 trước T8, T9, T10, T12; T2 cần T7 để có tác dụng nhìn thấy (T2 gộp trước vẫn vô hại: bộ xử lý trả `{}`); T15 cuối; T17 sau T7 | Xung đột nhỏ ở `args.rs`, `settings_schema.dart`, ARB — mỗi task chỉ **thêm** dòng |
| D2 | Phạm vi | **Làm:** hook cho 4 agent (T3–T6), nhận sự kiện (T2), trạng thái agent (T7–T8), resume (T9), Cài đặt › Agent (T10), PR (T11), hook người dùng (T12), ngôn ngữ (T13), nút cập nhật (T14), T22 (T15), `tab describe/status` (T16), mobile (T17). **Bỏ:** hibernation, fork, Feed/inbox, auto-naming bằng AI, cây subagent, Claude Teams. **Hoãn (§10):** hook cho agent chạy qua SSH/remote, hook Codex dạng `hooks.json`, bộ đệm sự kiện ở daemon khi không có cửa sổ, tự cài cập nhật, ~14 agent còn lại của cmux | — |
| D3 | Kiến trúc | `agent (hook) → shellx agent-event AGENT EVENT [stdin JSON] → ui.agent.event (một loại tin CLI) → UiCommandHandler → AgentStatusNotifier (bộ nhớ UI) → sidebar / header pane / thông báo / sự kiện CLI`. Chuẩn hoá **ở CLI Rust** (bảng D6, test bằng fixture), Dart kiểm tra lại mọi trường (không tin CLI). Trạng thái chỉ nằm bộ nhớ; chỉ `(agent, session)` được lưu (D13). Không thêm quy trình nền, không theo dõi tiến trình, không đọc transcript | Nếu hook không tới (tmux cũ, SSH): không có trạng thái, giống hôm nay |
| D4 | Dây `ui.agent.event` | Trường: `pane` (int, bắt buộc), `agent` (`claude`/`codex`/`gemini`/`opencode`), `event` (`start`/`running`/`needs_input`/`idle`/`end`/`notice`), `at` (ms epoch của CLI, để chống thứ tự đảo), `session?` (≤ 128 ký tự, `^[A-Za-z0-9][A-Za-z0-9._:-]*$`), `message?` (≤ 1024 ký tự, điều khiển → khoảng trắng), `ok?` (bool, `false` khi lượt thất bại). Khoá lạ bị bỏ qua; `agent`/`event` lạ → `bad_request`. Giới hạn 20 sự kiện/giây/pane (thừa bị bỏ, không lỗi). Thêm `CliType.uiAgentEvent` và cap `'ui.agent'` vào `kCliCaps`; `kCliApi` giữ 1 (chỉ thêm) | CLI mới + app cũ: cap thiếu → `agent-event` thoát 0 im lặng |
| D5 | Lệnh hook | `shellx agent-event AGENT EVENT [PAYLOAD] [--session ID] [--message TEXT]`. **Luôn thoát 0 và không in gì** (stdout không phải tty): hook không bao giờ làm hỏng hay chặn agent (Claude coi mã 2 là chặn!). Không làm gì nếu `SHELLX_PANE_ID` không đặt (agent chạy ở terminal khác — để hook cài toàn cục vô hại). Đọc stdin ≤ 64 KiB, chờ ≤ 1 s, chỉ khi stdin không phải tty; tổng thời gian ≤ 2 s (kết nối socket 1 s). Lệnh trong file agent **không chứa cú pháp shell** (không `\|\|`, không `2>`, không nháy): `shellx agent-event claude stop` — chạy giống nhau trên Windows | Đường dẫn: `shellx` phải nằm trong PATH của agent; installer cảnh báo khi không thấy, `shellx doctor` kiểm |
| D6 | Bảng tích hợp | **Claude Code:** `${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json`, khoá `hooks.<Sự kiện>[]` dạng lồng `{"hooks":[{"type":"command","command":"…","timeout":5}]}`; sự kiện `SessionStart→session-start`, `UserPromptSubmit→prompt-submit`, `Notification→notification`, `Stop→stop`, `SessionEnd→session-end`; resume `claude --resume <id>`. **Gemini CLI:** `~/.gemini/settings.json`, cùng dạng, `timeout` tính bằng ms (5000): `SessionStart`, `BeforeAgent→prompt-submit`, `AfterAgent→stop`, `Notification`, `SessionEnd`; resume `gemini --resume <id>`. **Codex:** `${CODEX_HOME:-~/.codex}/config.toml`, **một** khoá cấp đầu `notify = ["shellx","agent-event","codex","turn-complete"]` (Codex nối JSON vào cuối argv); chỉ cho `idle` + id phiên (không có Running/Needs input — hạn chế ghi rõ); resume `codex resume <id>`. **OpenCode:** tệp riêng của ShellX `${OPENCODE_CONFIG_DIR:-~/.config/opencode}/plugins/shellx-agent.js` (không gộp, ShellX sở hữu cả tệp; dòng đầu là dấu nhận diện); sự kiện bus `session.created`, `session.status(busy)`, `session.idle`, `permission.asked/updated`, `session.deleted`; resume `opencode --session <id>`. `PreToolUse/PostToolUse` **không** cài (một lần sinh tiến trình mỗi lệnh công cụ là quá nặng; "đang chạy lại sau khi trả lời quyền" do D9 xử lý). `StopFailure` không cài (tên sự kiện chưa ổn định giữa các bản; lượt chết vì lỗi API sẽ được quy tắc im lặng 20 s đưa về chờ) | Phiên bản agent đổi tên sự kiện: hook thành vô hại (không chạy); `integrations status` vẫn báo "đã cài"; ⚠ thử với bản thật |
| D7 | Installer — an toàn | `shellx integrations status [AGENT] [--json]`, `install AGENT [--yes] [--dry-run] [--print]`, `uninstall AGENT [--yes]`. (1) Đọc → tính nội dung mới (thuần) → in **diff thống nhất** (ngữ cảnh 2 dòng; dòng ngữ cảnh/xoá có khoá tên giống `(?i)key\|token\|secret\|password\|auth\|credential` thì thay giá trị bằng `"…"` **chỉ khi hiển thị**) → hỏi `[y/N]` đọc từ `/dev/tty` (Windows `CONIN$`); không có tty và không `--yes` → thoát 2 "cần --yes khi không tương tác". (2) Trước khi ghi: đọc lại tệp, so với bản đã tính diff, khác → huỷ ("tệp đã đổi trong lúc chờ"). (3) Sao lưu `<tệp>.shellx-bak` (một bản, ghi đè lần sau, quyền như tệp gốc, **chỉ khi tệp đã tồn tại**). (4) Ghi nguyên tử (tệp tạm cùng thư mục → đổi tên), giữ quyền; tệp là symlink → ghi vào đích của nó, giữ symlink. (5) Idempotent: đủ mục và giống hệt → "already installed", không ghi; có mục của ShellX cũ khác chuỗi lệnh → thay tại chỗ. (6) Nhận diện "của ShellX": phần tử có `command` bắt đầu bằng `shellx agent-event ` (Claude/Gemini), dòng `notify` có `"agent-event"` kèm dấu chú thích ShellX (Codex), dòng đầu `// shellx-agent-integration` (OpenCode). Không bao giờ sửa/xoá phần tử khác. (7) Từ chối an toàn: JSON có chú thích/không hợp lệ, kiểu sai (`hooks` không phải object…), tệp > 1 MiB, TOML đã có `notify` của người dùng → thoát 1 kèm lý do **cố định** và gợi ý `--print` (in đoạn cần thêm để dán tay). (8) `--dry-run` = in diff, không hỏi, không ghi. (9) `uninstall` bỏ đúng các mục của ShellX; nếu tệp do ShellX tạo (có tệp dấu rỗng `<tệp>.shellx-created`, §6) và sau khi gỡ chỉ còn `{}`/rỗng → xoá tệp và tệp dấu. (10) Không đọc biến môi trường nào ngoài đường dẫn cấu hình, không mạng, không in nội dung tệp ngoài diff đã che | Người dùng có tệp JSONC: phải dán tay (rủi ro thấp, cố ý) |
| D8 | Sửa JSON không thêm crate | Mô-đun `term/src/api/integrations/json.rs`: bộ đọc JSON nghiêm ngặt (RFC 8259, độ sâu ≤ 64, ≤ 1 MiB, từ chối chú thích/dấu phẩy thừa/khoá trùng trong đối tượng đang sửa) trả cây có **khoảng byte** từng nút; các phép sửa **chèn/xoá văn bản** tại khoảng đó (`insert_member`, `append_element`, `remove_element`) với thụt lề dò từ tệp (mặc định 2 khoảng trắng, giữ CRLF/LF, giữ đuôi dòng cuối). Không tuần tự hoá lại toàn tệp → mọi byte ngoài chỗ sửa giữ nguyên (test tính chất: xoá đoạn chèn ⇒ bằng tệp cũ). Bộ đọc cũng dùng ở `agent-event` để lấy trường chuỗi cấp đầu của JSON hook | Bộ đọc tự viết có lỗi: test tính chất + fuzz nhỏ (mọi tiền tố của vài tệp mẫu không panic) |
| D9 | Mô hình trạng thái | `AgentState`: `running`, `needsInput`, `idle`, `done`, `unknown`. Reducer thuần `reduceAgent(AgentPane?, AgentEvent, {now, paneVisible})`: `start`→`idle` (lưu id phiên); `running`→`running`; `needs_input`→`needsInput`; `idle`→`done` nếu pane **không được xem** (không focus hoặc tab không hiện) lúc đó, ngược lại `idle`; `end`→bỏ bản ghi; `notice`→không đổi trạng thái. **Chống đảo thứ tự:** bỏ sự kiện có `at` cũ hơn sự kiện đã áp dụng (mỗi pane). **Về lại:** `needsInput` → `running` khi người dùng gõ vào pane đó (byte ghi từ người dùng, không phải từ CLI `send`); `done` → `idle` khi pane được focus và tab hiện; `running` → `idle` khi pane im lặng ≥ 20 s (`kAgentQuietDecay`; spinner của agent luôn in nên im lặng = ngưng); `needsInput` **không** tự phân rã; shell thoát / pane đóng → bỏ bản ghi. Tab tổng hợp: `needsInput > running > done > idle`. Trạng thái **không** ghi vào `TabMeta` | Agent không in spinner (Codex cũ?): "đang chạy" kết thúc sớm 20 s — chỉ là hiển thị; hằng số chỉnh được |
| D10 | Quan hệ với OSC của A4 | Hook là nguồn duy nhất của trạng thái và của tên agent (không đoán tên từ tiêu đề). Thông báo từ hook đi qua `LocalSessions.notify(pane,…)` — **cùng** đường, cùng quy tắc A4 (tắt khi pane đang focus và cửa sổ active, ngưỡng, giới hạn 20/phút, đẩy sang điện thoại). Pane đã có sự kiện hook trong 3 s: thông báo OSC/chuông **cùng pane** đến sau bị gộp (không nhân đôi); pane không có hook: OSC chạy như cũ, không trạng thái. `needs_input` luôn thông báo (chữ = `message` đã làm sạch, nếu rỗng dùng "{agent} cần bạn trả lời"); `idle` thông báo "{agent} đã xong" chỉ khi lượt chạy ≥ ngưỡng lệnh dài của A4 (`SetNotifyThreshold`) và pane không được xem; `start`/`running`/`end`/`notice` không thông báo (`notice` chỉ khi `message` không rỗng, như `needs_input` nhưng không đổi trạng thái); ≤ 1 thông báo mỗi pane mỗi 5 s từ hook | Ngưỡng cao làm mất "xong": người dùng chỉnh được |
| D11 | Sự kiện CLI | `shellx events` thêm `agent.status {pane, tab, agent, status}` khi trạng thái hiển thị đổi; `shellx ls --json` thêm `agent`, `agent_status` cho pane có bản ghi (đầu ra người đọc không đổi). Tài liệu: `agent-skills/shellx/reference.md` | — |
| D12 | Giao diện sidebar/pane | Mỗi hàng tab hiện **huy hiệu trạng thái tổng hợp** trước tên agent: biểu tượng + chữ (không chỉ màu): `needsInput` (⚠ tam giác, `warn`), `running` (● đặc, `accent`), `done` (✓, `ok`), `idle` (○ rỗng, `textSecondary`); tên agent trong tooltip/semantics. Header của pane agent hiện cùng huy hiệu cỡ lớn. **Không hoạt hoạ** (không spinner; tiết kiệm GPU, cmux #14832) — `running` là chấm đặc tĩnh. Hàng tab hẹp (< 160 px): chỉ biểu tượng. `Semantics.liveRegion` chỉ cho `needsInput` (đọc "Claude Code cần bạn trả lời"), ≤ 1 lần/60 s/tab (A7 D27). Chip "Agent" của A7 giữ nguyên, khác nghĩa | Sidebar chật: ưu tiên biểu tượng, chữ rớt trước |
| D13 | Bản ghi phiên + resume | `SavedPane` thêm khoá tuỳ chọn `agent: {"k": "claude", "s": "<id>"}` (ghi khi pane có bản ghi với id hợp lệ; thiếu = như cũ; bản cũ bỏ qua khoá lạ). Khôi phục (không `reattach`): với mỗi pane có `agent` **và** cwd khôi phục được (`isRestorableCwd`), tạo **lời mời** trong bộ nhớ; dải trên đầu pane (D12 chuỗi §4.2); "Tiếp tục phiên" → `typeCommand(pane, "<lệnh>")` với lệnh dựng từ **hằng + id đã kiểm** (bảng D6; regex loại mọi ký tự đặc biệt của shell và không cho id bắt đầu bằng `-` nên không cần nháy, chạy giống nhau ở zsh/bash/fish/PowerShell/cmd; không bao giờ ghép chuỗi khác), một lần; "Bỏ qua"/đóng pane/gõ phím đầu tiên vào pane → xoá lời mời và bản ghi. Khoá cấu hình `agent-resume = ask`(mặc định) `\|off`. Không bao giờ tự chạy. `reattach` (A5b): bản ghi khôi phục với trạng thái `unknown`, **không** lời mời. Panes SSH/tmux (`launch != null`): không lời mời (lệnh sẽ chạy ở máy cục bộ, sai chỗ) | id hỏng/đã dọn: agent in lỗi "session not found", vô hại |
| D14 | Trạng thái `unknown` | Hiển thị: không huy hiệu; vẫn lưu bản ghi (id) để lần crash sau còn resume được; sự kiện kế tiếp đưa về trạng thái thật | — |
| D15 | Agent qua SSH | Ngoài phạm vi: hook chạy trên máy từ xa không với tới socket cục bộ (A8 chỉ cài hook shell, không phải CLI). Ghi vào §10 | Người dùng ssh + claude: như hôm nay (OSC) |
| D16 | PR status | Khoá tệp `pr-status = false` (mặc định **tắt**: mở kết nối ra GitHub bằng thông tin đăng nhập của người dùng là hành vi mới). Dịch vụ `PrStatusService`: `gh pr view --json number,state,isDraft,url,reviewDecision,statusCheckRollup` chạy với `cwd` = thư mục gốc git của pane **cục bộ**, môi trường kế thừa + `GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 NO_COLOR=1`, **không** truyền token, ShellX không đọc `GH_TOKEN`/`~/.config/gh`. Tìm `gh`: PATH + `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, (Windows) `%ProgramFiles%\GitHub CLI`. Giới hạn: 1 tiến trình cùng lúc, ≤ 6 lần/phút toàn app, timeout 8 s (giết cây), chỉ tab **đang hiện** hoặc vừa đổi nhánh, làm mới tối thiểu 120 s/(thư mục,nhánh) khi thành công, "không có PR" nhớ 10 phút, lỗi (chưa đăng nhập, mạng, không phải repo GitHub) lùi 5 → 10 → 20 → 30 phút; không `gh` → tắt im lặng. Không xin tiêu đề/nội dung PR (chỉ số, trạng thái, URL). URL chỉ mở khi bấm, phải `https`, không userinfo. Đầu ra `gh` không bao giờ log | Hộp cát: không có; người dùng tắt được |
| D17 | Hook thông báo người dùng | Khoá tệp `agent-event-command = <chuỗi>` (dòng lệnh tách theo quy tắc từ-có-nháy, **không qua shell**; ví dụ `~/bin/on-agent --fast`). Chỉ đọc từ **tệp chính của người dùng**, không từ `include`/tệp Ghostty (tệp có thể do một agent sửa qua kỹ năng `shellx-config`). **Cổng cho phép:** lần đầu (và mỗi khi chuỗi đổi), thông báo "Hook sự kiện agent chưa được cho phép" kèm nút → hộp thoại hiện đúng chuỗi lệnh + [Cho phép] [Huỷ]; `Cho phép` lưu SHA-256 của chuỗi vào `SettingsStore` (`agent_command_approved`). Chạy khi sự kiện trạng thái **đổi** (`running`,`needs_input`,`idle`,`done`,`end`): stdin = một dòng JSON `{"v":1,"event","agent","pane","tab","status","message?"}` (message đã làm sạch, có thể rỗng), môi trường **chỉ** `PATH HOME USER LOGNAME LANG TMPDIR SystemRoot` + `SHELLX_EVENT SHELLX_AGENT SHELLX_PANE SHELLX_TAB SHELLX_STATUS` (không `SHELLX_CLI_TOKEN`, không `SHELLX_SOCKET`), `cwd` = thư mục home, timeout 10 s (SIGKILL cây), ≤ 4 cùng lúc, hàng đợi 16 (bỏ cũ nhất), ≤ 1 lần/giây/(pane,sự kiện); stdout/stderr bỏ; mã thoát bỏ. Windows: chỉ `.exe` hoặc `powershell -File …` (không chạy `.cmd` — không qua shell). Không tên workspace, không đường dẫn, không tên nhánh trong JSON | Người dùng muốn shell (`\|`, `&&`): viết script rồi trỏ tới |
| D18 | `tab describe/status` | `shellx tab describe TAB [TEXT...]` (rỗng = xoá) và `shellx tab status TAB none\|in_progress\|review\|blocked\|done` → `ui.tab.meta {tab, description?, status?}` → `TerminalTabs.setMeta` sẵn có (A11 D18; `TabMeta.cleanDescription` làm sạch, 120 ký tự). Mô tả do agent đặt có thể là bí mật của người dùng: cùng quy tắc A11 §5 (không log, `ls` không in mô tả); lệnh **không** cướp focus; `TAB` theo `@self`/`@tab` như `rename` | Agent ghi đè mô tả người dùng: người dùng sửa lại được; không có khoá chống ghi |
| D19 | Ngôn ngữ app | `SettingsStore` khoá `app_language` (`getStrings`, một phần tử: `system`/`en`/`vi`; thiếu = `system`). `resolveAppLocale(preferred, {override})`; `main.dart` tính lại `locale`/`l10n` ngay sau khi mở `SharedPrefsSettingsStore` (hộp thoại lỗi khởi động trước đó dùng ngôn ngữ hệ thống). Có hiệu lực **sau khởi động lại** (l10n được truyền như giá trị cho khay, thông báo, dịch vụ — đổi nóng là chạm hàng chục chỗ). `TrayAction.setAppLanguage`; hàng ở Cài đặt › Chung. Daemon (`daemon_main.dart`) giữ ngôn ngữ hệ thống (chỉ chữ trong thông báo sự cố tiến trình) — ghi vào giới hạn | Người dùng muốn đổi nóng: chưa có |
| D20 | Nút kiểm cập nhật | Hàng Cài đặt › Chung: phiên bản hiện tại + [Kiểm tra cập nhật]. `AgentController.checkForUpdateNow()` trả `UpdateCheckResult` (`upToDate`/`available(UpdateNotice)`/`failed`) dùng `api.version()` + `evaluateUpdate` có sẵn (URL tin cậy bắt buộc); không thông báo hệ thống thêm (kết quả hiện ngay tại hàng, `liveRegion`); "Tải xuống" mở URL qua `UrlOpener`. Không tự cài | Relay không có bản mới hơn: luôn "mới nhất" — đúng |
| D21 | T22 độ trong suốt/blur | Làm lại **như tác vụ cuối, tuỳ chọn, chặn bởi ⚠**: khoá `background-opacity` (0,3–1, mặc định 1) và `background-blur` (bool hoặc bán kính >0) kiểu Ghostty, **chỉ macOS** (Windows: ghi chú `notOnThisPlatform`). Mặc định mờ = 1/không blur ⇒ **không dòng mã native nào chạy** với người dùng mặc định (`BackdropBinder` chỉ gọi khi `opacity < 1 \|\| blur`). Nguyên văn thiết kế và mã Swift ở plan A11 Task 22 (còn đúng); điều chỉnh: thử trên máy thật là **điều kiện gộp**; nếu cửa sổ nhấp nháy/chữ vỡ ⇒ bỏ task, ghi HANDOFF | Máy này không xác nhận bằng mắt được (A11): task chờ người có Mac |
| D22 | Mobile | `SessionInfo` thêm hai khoá tuỳ chọn `agent` (tên) và `agentState` (`running`/`needs_input`/`idle`/`done`), chỉ gửi cho điện thoại đã `session.list {desktop:true}` (mẫu A2 C4: `toMap` ghi khi khác rỗng; `_fromMap` đọc `optionalString`; điện thoại cũ bỏ khoá lạ). Không thêm thông điệp, không đẩy: điện thoại thấy giá trị ở lần `session.list` kế tiếp (mở bộ chọn phiên / kết nối lại) — thông báo đẩy "cần bạn" đã có đường riêng (D10). UI: chip một dòng trong bộ chọn phiên (`session_picker.dart`) "Claude · cần bạn trả lời". Không ghi `message` vào `SessionInfo` | Danh sách có thể cũ giữa hai lần tải; chấp nhận (thông báo đẩy mới là đường tức thời) |
| D23 | Chẩn đoán | `shellx doctor` thêm các dòng thông tin (không ✗): "Claude Code hooks: installed / not installed" (đọc tệp, chỉ tìm `shellx agent-event`) cho từng agent **tìm thấy trên PATH**; không agent nào trên PATH → không dòng. `✗` chỉ khi hook đã cài mà `shellx` không có trong PATH (hook sẽ lỗi) | — |
| D24 | Riêng tư và log | Mục §5. Bản ghi `AgentPane`, `AgentEvent`, `PrInfo`, lệnh hook người dùng: `toString()` trả `'…'` (test ghim) | — |
| D25 | Khoá cấu hình mới | `agent-resume` (`ask`\|`off`, mặc định `ask`), `pr-status` (bool, mặc định `false`), `agent-event-command` (chuỗi, mặc định rỗng; chỉ tệp chính), (T15) `background-opacity`, `background-blur`. Qua `buildShellxConfig`, `config_template.dart`, `config_show.dart`, `settings_schema.dart` (một chủ = tệp; A11 D4). Công tắc app: `app_language` (D19) và `agent_command_approved` (D17) ở `SettingsStore` | — |
| D26 | Giới hạn | Stdin hook 64 KiB; tổng thời gian `agent-event` 2 s; sự kiện 20/s/pane; `message` 1024; id 128; thông báo hook 1/5 s/pane; quiet-decay 20 s; gộp OSC 3 s; PR: 1 song song, 6/phút, 8 s, 120 s, 10 phút, lùi 5–30 phút; hook người dùng: 4 song song, hàng 16, 10 s, 1/s/(pane,sự kiện); tệp cấu hình agent ≤ 1 MiB; diff ≤ 5000 dòng (quá → không hiện diff, từ chối); nhóm hook của ShellX tối đa 6 mỗi tệp | — |
| D27 | Tài liệu và phát hành | HANDOFF §22; ledger; chính sách riêng tư thêm hai câu (hook ghi vào tệp cấu hình agent chỉ sau khi bạn đồng ý; trạng thái PR dùng `gh` của bạn); kỹ năng `agent-skills/shellx` nêu `agent-event`, `tab describe/status`, `integrations`; ghi chú phát hành điền `whats_new.json` (bắt buộc: "Cài hook agent: `shellx integrations install claude`") | — |

---

## 4. Giao diện và chuỗi (EN + VI)

Theme/token/khoảng cách: `ShellxDesktopColors`, `ShellxText`, `ShellxSpace`, `ShellxSizes` hiện có. "SSH", "tmux", "pane", "tab", "workspace", "hook", tên agent ("Claude Code", "Codex", "Gemini CLI", "OpenCode"), "gh", "GitHub" giữ nguyên trong bản VI; `⌘`/`Ctrl` lấy từ nền tảng. Mọi chuỗi vào `lib/l10n/app_en.arb` + `app_vi.arb` (desktop), `intl_en.arb` + `intl_vi.arb` (mobile).

### 4.1 Trạng thái agent (sidebar, header pane)

| Khoá ARB | EN | VI |
|---|---|---|
| `agentStateRunning` | Running | Đang chạy |
| `agentStateNeedsInput` | Needs input | Cần bạn trả lời |
| `agentStateIdle` | Idle | Đang chờ |
| `agentStateDone` | Done | Xong |
| `agentStatusTooltip` | {agent}: {state} | {agent}: {state} |
| `agentStatusAnnounce` | {agent} needs your input | {agent} cần bạn trả lời |
| `agentNotifyNeedsInput` | {agent} needs your input | {agent} cần bạn trả lời |
| `agentNotifyDone` | {agent} finished | {agent} đã xong |
| `agentNamesClaude`… | Claude Code · Codex · Gemini CLI · OpenCode | giữ nguyên |

### 4.2 Tiếp tục phiên (dải trên đầu pane)

Dải 36 px cao, `surface` 95 %, viền `accent`, nằm trên cùng pane, **không** chiếm focus bàn phím của terminal (nút `ExcludeFocus` trừ khi người dùng Tab tới); thứ tự Tab: [Tiếp tục] → [Bỏ qua]; Esc khi dải focus = Bỏ qua; `Semantics(container)` đọc cả câu.

| Khoá ARB | EN | VI |
|---|---|---|
| `resumeBannerText` | {agent} was running here before ShellX restarted. | {agent} đang chạy ở đây trước khi ShellX khởi động lại. |
| `resumeBannerResume` | Resume session | Tiếp tục phiên |
| `resumeBannerDismiss` | Dismiss | Bỏ qua |
| `resumeBannerTooltip` | Types “{command}” into this terminal and presses Enter. | Gõ “{command}” vào terminal này rồi nhấn Enter. |
| `resumeBannerBusy` | Wait for the shell to be ready | Chờ shell sẵn sàng |

### 4.3 Cài đặt › Agent (thêm hàng) và Chung

| Khoá ARB | EN | VI |
|---|---|---|
| `settingsAgentIntegrations` | Agent integrations | Tích hợp agent |
| `settingsAgentIntegrationsHint` | Hooks let ShellX show whether an agent is running or waiting for you. Setup shows every change and asks first. | Hook giúp ShellX biết agent đang chạy hay đang chờ bạn. Cài đặt luôn hiện từng thay đổi và hỏi trước. |
| `integrationInstalled` | Installed | Đã cài |
| `integrationNotInstalled` | Not installed | Chưa cài |
| `integrationNotFound` | {agent} not found on this computer | Không thấy {agent} trên máy này |
| `integrationSetUp` | Set up in a terminal | Cài đặt trong terminal |
| `integrationRemove` | Remove in a terminal | Gỡ trong terminal |
| `integrationLimit` | Codex reports when a turn ends; it does not report “running”. | Codex chỉ báo khi một lượt kết thúc, không báo “đang chạy”. |
| `settingAgentResume` | Offer to resume agent sessions | Đề nghị tiếp tục phiên agent |
| `settingAgentResumeDesc` | After a restart, show a button to continue the agent you were using. Nothing runs until you click. | Sau khi khởi động lại, hiện nút để tiếp tục agent bạn đang dùng. Không có gì chạy cho tới khi bạn bấm. |
| `settingPrStatus` | Show pull request status | Hiện trạng thái pull request |
| `settingPrStatusDesc` | Uses the GitHub CLI (gh) already signed in on this computer. ShellX never reads your token. | Dùng GitHub CLI (gh) đã đăng nhập sẵn trên máy. ShellX không bao giờ đọc token của bạn. |
| `settingPrStatusNoGh` | GitHub CLI (gh) was not found. | Không tìm thấy GitHub CLI (gh). |
| `settingAgentCommand` | Run a command on agent events | Chạy lệnh khi agent có sự kiện |
| `settingAgentCommandDesc` | Set agent-event-command in the config file. ShellX asks before running a new command. | Đặt agent-event-command trong tệp cấu hình. ShellX hỏi trước khi chạy một lệnh mới. |
| `agentCommandApproveTitle` | Allow this command? | Cho phép lệnh này? |
| `agentCommandApproveBody` | ShellX will run it when an agent starts, needs input or finishes. It gets no access to your ShellX session. | ShellX sẽ chạy lệnh này khi agent bắt đầu, cần nhập hoặc xong. Lệnh không có quyền gì với phiên ShellX của bạn. |
| `agentCommandApproveAllow` / `…Cancel` | Allow / Cancel | Cho phép / Huỷ |
| `agentCommandNotApproved` | An agent-event command is set but not allowed yet. | Đã đặt lệnh sự kiện agent nhưng chưa được cho phép. |
| `settingLanguage` | Language | Ngôn ngữ |
| `settingLanguageSystem` / `…En` / `…Vi` | System default / English / Tiếng Việt | Theo hệ thống / English / Tiếng Việt |
| `settingLanguageRestart` | Takes effect after you restart ShellX. | Có hiệu lực sau khi bạn khởi động lại ShellX. |
| `updateCheck` | Check for updates | Kiểm tra cập nhật |
| `updateChecking` | Checking… | Đang kiểm tra… |
| `updateUpToDate` | You’re up to date ({version}). | Bạn đang dùng bản mới nhất ({version}). |
| `updateAvailable` | Version {version} is available. | Đã có bản {version}. |
| `updateDownload` | Download | Tải xuống |
| `updateRequired` | This version is too old. Update to keep using phone access. | Bản này đã quá cũ. Hãy cập nhật để tiếp tục dùng truy cập từ điện thoại. |
| `updateFailed` | Couldn’t check right now. | Không kiểm tra được lúc này. |

### 4.4 PR trong sidebar

Phần tử nhỏ ngay sau tên nhánh trong dòng ngữ cảnh (A2 §2): `#123` + glyph CI; bị bỏ trước khi rút gọn cổng (ports) khi hẹp; bấm = mở URL; tooltip/semantics là câu đầy đủ.

| Khoá ARB | EN | VI |
|---|---|---|
| `prOpen` / `prDraft` / `prMerged` / `prClosed` | open / draft / merged / closed | đang mở / nháp / đã merge / đã đóng |
| `prChecksPassing` / `prChecksFailing` / `prChecksPending` | checks passing / checks failing / checks running | CI đạt / CI lỗi / CI đang chạy |
| `prReviewApproved` / `prReviewChanges` | approved / changes requested | đã duyệt / cần sửa |
| `prTooltip` | Pull request #{number}: {state}, {checks} | Pull request #{number}: {state}, {checks} |
| `prOpenInBrowser` | Open in browser | Mở trong trình duyệt |

### 4.5 CLI (tiếng Anh, như A7 D11)

```
$ shellx integrations status
✓ claude    installed   (~/.claude/settings.json)
✗ codex     not installed
- gemini    not found on PATH
✗ opencode  not installed

$ shellx integrations install claude
--- ~/.claude/settings.json
+++ ~/.claude/settings.json (after)
@@ -3,6 +3,16 @@
   "hooks": {
+    "SessionStart": [
+      {
+        "hooks": [
+          { "type": "command", "command": "shellx agent-event claude session-start", "timeout": 5 }
+        ]
+      }
+    ],
 …
Apply these changes to ~/.claude/settings.json? [y/N] y
Backed up the old file to ~/.claude/settings.json.shellx-bak
Installed. Restart running Claude Code sessions for the hooks to apply.
```
Thông điệp lỗi cố định: `refusing: the file has comments or is not valid JSON (use --print to see what to add)`, `refusing: "notify" is already set in config.toml (shellx will not replace it; see --print)`, `the file changed while waiting; nothing was written`, `needs --yes when not interactive`. Thoát: 0 thành công / đã cài sẵn / người dùng trả lời `n` (in "No changes made."), 1 từ chối an toàn hoặc ghi lỗi, 2 dùng sai (gồm thiếu `--yes` khi không tương tác).

`shellx tab describe T3 "fix login"`, `shellx tab status T3 review` — im lặng khi thành công (A7), `--json` `{}`.

### 4.6 Mobile

| Khoá ARB (`intl_*`) | EN | VI |
|---|---|---|
| `agentChipRunning` | {agent} · running | {agent} · đang chạy |
| `agentChipNeedsInput` | {agent} · needs your input | {agent} · cần bạn trả lời |
| `agentChipIdle` | {agent} · idle | {agent} · đang chờ |
| `agentChipDone` | {agent} · done | {agent} · xong |

---

## 5. Riêng tư, an ninh và log

- **Không bao giờ log** (kể cả `debugPrint`, kể cả `kDebugMode`): `message` của hook, id phiên, lệnh của hook người dùng, đầu ra/đường dẫn `gh`, tên nhánh, số PR, nội dung tệp cấu hình agent, đường dẫn thư mục, mô tả tab. Cho phép: loại sự kiện (`agent_event`, `agent_resume_offered`, `integration_installed`), tên agent (tập đóng), `runtimeType` của lỗi, **số** (số mục, ms), mã thoát.
- `toString()` của `AgentEvent`, `AgentPane`, `PrInfo`, `ResumeOffer`, `HookCommand` trả `'…'` (test ghim).
- **Installer sửa tệp của người dùng (D7):** diff đầy đủ trước khi ghi; che giá trị khoá giống bí mật trong **hiển thị**; `.shellx-bak` cùng quyền tệp gốc (0600 nếu gốc 0600) — tệp bak chứa nội dung gốc nên không nới quyền; chỉ ghi khi `y`/`--yes`; không đọc biến môi trường nào ngoài đường dẫn cấu hình; không mạng; không bao giờ đưa nội dung tệp vào log hoặc `--json` (JSON của `status` chỉ có `{agent, installed, path, found}`; `install --json` chỉ `{changed, backup}`).
- **Chuỗi lệnh hook không có dữ liệu người dùng** nên không có vấn đề trích dẫn/chèn lệnh; khoá `command` do ShellX sinh từ hằng (test so khớp từng byte). **Id phiên** vào lệnh resume chỉ sau regex nghiêm ngặt (D13; không cần nháy vì regex loại ký tự đặc biệt và cờ `-`) — id đến từ JSON của agent nên coi là không tin cậy.
- **`message` của hook là chữ do agent sinh** (có thể chứa nội dung từ web/tệp): làm sạch như `notify` (điều khiển, bidi), hiển thị như văn bản thuần, không bao giờ diễn giải (không markdown, không liên kết).
- **Hook người dùng (D17):** cổng cho phép theo SHA-256 của chuỗi; không qua shell nên dữ liệu sự kiện không thể chèn lệnh; môi trường tối thiểu (không token CLI); chỉ đọc từ tệp chính; thông báo khi chưa cho phép; `kill` cây khi hết giờ.
- **`gh` (D16):** ShellX chỉ chạy `gh` với đối số cố định; không `GH_TOKEN` từ ShellX; URL chỉ `https`; tắt mặc định; không gửi gì tới relay.
- **Dây `ui.agent.event`:** chỉ qua socket CLI (token/`cli_allow_external` như mọi `ui.*`); Dart kiểm lại kiểu/độ dài/regex; pane không tồn tại → bỏ im lặng (không lộ tồn tại).
- Chính sách riêng tư (`web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`): thêm hai câu ở T18 — "Khi bạn đồng ý, ShellX thêm hook vào tệp cấu hình của agent để biết agent đang chạy hay đang chờ; ShellX không gửi nội dung đó đi đâu." và "Trạng thái pull request (nếu bật) lấy bằng GitHub CLI đã đăng nhập trên máy bạn; ShellX không đọc hay lưu token."

## 6. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Hook chạy khi ShellX không mở / `ui` chưa gắn / CLI tắt | `agent-event` thoát 0 im lặng; không trạng thái |
| `SHELLX_PANE_ID` trỏ pane đã đóng (tmux giữ biến cũ) | App bỏ im lặng; không tạo bản ghi |
| Hai sự kiện đến đảo thứ tự | Bỏ sự kiện có `at` cũ hơn (D9) |
| `Stop` đến khi người dùng đang xem pane | `idle`, không `done` |
| Agent bị `kill -9` giữa lượt | Không có `SessionEnd`; `running` → `idle` sau 20 s; bản ghi/id còn tới khi shell thoát |
| Pane agent bị chuyển tab (A11 D20) | Bản ghi theo **id pane**, đi theo pane; huy hiệu tab tính lại |
| Nhiều agent trong một tab | Huy hiệu tab = ưu tiên cao nhất; mỗi pane giữ riêng |
| Tab đóng rồi mở lại (A11 D14) | Bản ghi `agent` có trong `SavedPane` của `ClosedTab` ⇒ dải mời hiện lại (chỉ trong phiên app) |
| Người dùng chạy `claude` rồi `cd` rồi `claude` mới | `SessionStart` mới thay id; `end` của phiên cũ đến sau (có `at` cũ) bị bỏ |
| `settings.json` không tồn tại | Installer tạo thư mục + tệp mới `{ "hooks": {…} }` (diff là toàn tệp); không có gốc nên không có `.shellx-bak`; ghi tệp dấu rỗng `<tệp>.shellx-created` để `uninstall` biết được xoá tệp (tệp dấu bị xoá cùng) |
| Tệp cấu hình agent không ghi được (quyền, đĩa đầy) | Thoát 1 "could not write … (permission denied)"; tệp gốc nguyên vẹn (ghi tệp tạm trước) |
| `shellx` không trong PATH khi cài | Cài vẫn được, cảnh báo một dòng: hook sẽ không chạy cho tới khi thêm vào PATH |
| `gh` treo | Giết cây sau 8 s, tính là lỗi, lùi |
| Repo không phải GitHub / chưa đăng nhập | Lỗi nhớ lâu (30 phút), không hiện gì |
| `agent-event-command` không tồn tại | Chạy lỗi → bỏ im lặng; không thử lại; một thông báo duy nhất mỗi phiên app "Lệnh sự kiện agent không chạy được" |
| `app_language` giá trị lạ | Coi như `system` |

## 7. Kiểm thử

- **Rust (`term/`, `cargo test`):** `json_test` (tính chất: chèn/xoá giữ nguyên mọi byte ngoài chỗ sửa; thụt lề/CRLF; từ chối chú thích/khoá trùng/độ sâu; mọi tiền tố không panic), `agent_event_test` (bảng chuẩn hoá D6 bằng fixture JSON thật của Claude/Gemini/Codex; id không hợp lệ bị bỏ; không `SHELLX_PANE_ID` ⇒ không kết nối; luôn mã 0; stdin lớn bị cắt), `integrations_plan_test` (từng agent: cài mới, cài lại, cài khi đã có hook người dùng ở cùng sự kiện, gỡ, gỡ khi có hook người dùng, tệp tự tạo, tệp symlink, từ chối từng trường hợp), `diff_test`, `integrations_cli_test` (tty giả: `y`/`n`/Enter; `--yes`; không tty; tệp đổi giữa chừng; quyền bak), `tab_meta_args_test`, `doctor_agents_test`.
- **Dart `shellx_agent`:** `cli_api_contract` thêm `ui.agent.event` + `ui.tab.meta` (cap), `cli_wire_test`.
- **Desktop thuần:** `agent_event_codec_test` (kiểm tra mọi trường, id regex, độ dài), `agent_reducer_test` (**quan trọng nhất**: bảng chuyển trạng thái D9, đảo thứ tự, done/idle theo `paneVisible`, quiet-decay với `fake_async`, needsInput→running khi gõ), `agent_status_test` (provider, pane đóng, tổng hợp tab, giới hạn 20/s), `resume_command_test` (bảng lệnh, id độc hại `a; rm -rf ~`, `$(x)`, xuống dòng ⇒ không có lệnh), `restore_snapshot_agent_test` (hai chiều, khoá lạ), `pr_status_parse_test` (JSON mẫu của `gh`, mọi tổ hợp CI), `pr_status_service_test` (`fake_async`: giới hạn tốc độ, lùi, không `gh`, timeout), `gh_locator_test`, `agent_command_runner_test` (tách từ, không qua shell, env tối thiểu, timeout, cổng cho phép theo hash, đổi chuỗi ⇒ hỏi lại), `app_language_test`, `update_check_now_test`, `shellx_config_a12_test` (khoá mới), `settings_schema_test` (mở rộng: mỗi khoá một chủ).
- **Desktop widget:** `agent_badge_ui_test` (4 trạng thái có chữ, hẹp chỉ biểu tượng, semantics), `agent_notify_ui_test` (đúng pane, gộp OSC 3 s, subagent không thông báo), `resume_banner_ui_test` (không tự chạy; bấm gõ đúng một lần; Bỏ qua; `reattach` không dải; cwd mất ⇒ không dải), `pr_chip_ui_test`, `settings_agents_a12_test`, `settings_general_a12_test` (ngôn ngữ, cập nhật), `shortcut_golden_test` (không phím mới ⇒ không đổi).
- **Mobile:** `session_info_agent_test` (khoá tuỳ chọn hai chiều), `session_picker_agent_test`.
- **Thử tay (⚠ MANUAL):** §9.

## 8. Review Focus

1. **Installer làm hỏng tệp của agent** — mất hook của người dùng, đổi định dạng, ghi khi chưa đồng ý, đè bản người dùng vừa sửa, symlink bị thay. Ghim: `json_test` (tính chất byte), `integrations_plan_test`, `integrations_cli_test` ("n ⇒ không ghi byte", "tệp đổi giữa chừng").
2. **Lộ bí mật qua diff** — khoá giống bí mật in ra terminal/scrollback. Ghim: `diff_test` (che), `integrations_cli_test` (`--json` không chứa nội dung).
3. **Hook làm hỏng agent** — thoát khác 0, in ra stdout, chờ vô hạn, chặn bằng mã 2. Ghim: `agent_event_test` ("luôn 0", "stdin lớn", "không socket").
4. **Trạng thái sai/kẹt** — `running` mãi sau Esc/kill; `needsInput` không về; `done` không tắt; đảo thứ tự. Ghim: `agent_reducer_test`, `agent_status_test`.
5. **Thông báo sai pane hoặc nhân đôi** — hook + OSC, subagent, tab khác đang xem. Ghim: `agent_notify_ui_test`.
6. **Resume tự chạy / chạy chuỗi độc / sai chỗ** — id từ JSON không tin cậy; pane SSH; `reattach`; cwd mất. Ghim: `resume_command_test`, `resume_banner_ui_test`.
7. **`layout.json` hỏng hai chiều** — khoá `agent` làm bản cũ lỗi. Ghim: `restore_snapshot_agent_test`.
8. **PR: chặn UI, spam GitHub, lộ token, mở URL lạ.** Ghim: `pr_status_service_test`, `gh_locator_test`, `pr_status_parse_test` (URL không `https`).
9. **Hook người dùng chạy lệnh chưa duyệt / qua shell / rò env.** Ghim: `agent_command_runner_test`.
10. **Cấu hình do agent sửa nâng quyền** — `agent-event-command` đọc từ `include`/Ghostty. Ghim: `shellx_config_a12_test` ("chỉ tệp chính").
11. **Riêng tư** — test bắt `debugPrint` qua toàn bộ luồng sự kiện/resume/PR/hook, khẳng định không chứa chuỗi thử nghiệm.
12. **Trợ năng** — huy hiệu có chữ, không chỉ màu; dải resume đọc được, Esc, không cướp focus; `liveRegion` chỉ `needsInput`.
13. **Mobile cũ** — điện thoại chưa cập nhật nhận `session.list` có khoá lạ vẫn chạy (`session_info_agent_test`).
14. **Ngôn ngữ** — `app_language` hỏng không làm app không khởi động (`app_language_test`).

## 9. ⚠ Kiểm tay (chỉ người ngồi trước Mac/Windows/điện thoại làm được)

Executor ghi từng mục "pending manual" vào ledger `## A12 — execution`; **task không gộp cho tới khi mục ⚠ của nó passed** (như A11 D35), riêng T15 là cổng bỏ/giữ.

**Mac (macOS 13+) — với Claude Code, Gemini CLI, Codex, OpenCode bản thật:**
- ⚠ T3: `shellx integrations install claude` trên `settings.json` thật có sẵn hook; diff đúng; `n` không ghi; `y` ghi; chạy `claude` — không báo lỗi hook; `uninstall` trả về nguyên trạng (`diff` với `.shellx-bak`); tệp là symlink (dotfiles).
- ⚠ T4–T6: tên sự kiện/định dạng đúng với **phiên bản đang cài** (ghi phiên bản vào ledger); Codex `notify` hoạt động và có id phiên; OpenCode nạp được plugin; Gemini nhận hook (có thể cần bật hooks trong cài đặt của nó).
- ⚠ T8: tiêu chí 2 từng dòng với Claude thật: hỏi quyền, trả lời, Stop, Esc giữa lượt, `/clear`, `/exit`, hai pane agent trong một tab, tab khác đang xem khi cần bạn, VoiceOver đọc huy hiệu và thông báo.
- ⚠ T9: `kill -9` ShellX giữa lúc `claude` chạy → mở lại → dải → bấm → đúng phiên (nội dung hội thoại cũ hiện); `Bỏ qua`; bật dịch vụ nền: không dải; tmux trong ShellX (biến `SHELLX_PANE_ID` cũ).
- ⚠ T10: nút "Cài đặt trong terminal" mở tab mới, gõ và chạy `shellx integrations install claude`; diff và câu hỏi `[y/N]` hiện **trong tab đó** (đồng ý luôn xảy ra ở CLI, không bao giờ ở nút).
- ⚠ T11: `gh` đã đăng nhập / chưa / không có; repo không phải GitHub; nhánh có PR nháp, đã merge; CI lỗi; mạng tắt; Activity Monitor: không tiến trình `gh` treo; tab ẩn không gọi.
- ⚠ T12: lệnh hook ghi một dòng vào tệp tạm; đổi chuỗi ⇒ hỏi lại; script treo ⇒ bị giết sau 10 s.
- ⚠ T13: đổi ngôn ngữ, khởi động lại: khay, menu, thông báo, Cài đặt, thông báo hook theo ngôn ngữ chọn.
- ⚠ T14: có/không có bản mới (đặt `latest_agent` trên relay thử); URL không tin cậy bị từ chối.
- ⚠ T15 (cổng): cửa sổ trong suốt + blur; kéo cửa sổ; Mission Control; sáng/tối; Stage Manager; toàn màn hình; **nhấp nháy hay chữ vỡ ⇒ bỏ task**.
- ⚠ T16: `shellx tab describe/status` từ một agent đang chạy trong tab khác workspace — không cướp focus.

**Windows 10 1809+/11:** T2/T3 (đường dẫn `%USERPROFILE%\.claude`, `shellx agent-event` từ hook của Claude trên Windows, tty `CONIN$`), T9, T11 (`gh.exe`), T12 (`.exe` / `powershell -File`), T13, T14. Windows chưa từng chạy cho A7–A11 (chỉ biên dịch): ghi "pending manual – Windows", **chặn phát hành**.

**iPhone / Android thật:** ⚠ T17: bộ chọn phiên hiện chip; desktop cũ (không gửi khoá) không lỗi; thông báo đẩy "cần bạn" tới đúng phiên (đường A4/push sẵn có).

## 10. Ngoài phạm vi A12

A13+: hook cho agent chạy qua SSH (cần CLI từ xa hoặc kênh OSC riêng), hook Codex dạng `hooks.json` (có trạng thái chạy/cần nhập; cần xử lý "trust" theo phiên bản), bộ đệm sự kiện ở daemon khi không có cửa sổ (A5b), cây subagent, ngủ đông agent, các agent còn lại (Cursor CLI, Amp, Pi, Kiro, Copilot, Droid…), nhóm workspace gập/ghim, mẫu bố cục, tự cài cập nhật (cần kênh appcast), đổi ngôn ngữ nóng, chọn ngôn ngữ cho daemon, vạch scrollbar theo prompt agent, "Open With", tìm regex, `shellx config set`. Hoãn không hẹn: những mục "bỏ" ở D2.
