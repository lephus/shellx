# A7 — Dòng lệnh `shellx` và socket API: điều khiển ShellX từ script và agent — Đặc tả thiết kế

- **Ngày:** 2026-10-07
- **Trạng thái:** Người dùng giao toàn quyền cho controller (như A1–A6). Quyết định C1–C7 do controller chốt (ràng buộc); D1–D40 do người viết spec chốt trong phạm vi C1–C7. Tất cả ghi ở bảng §2 kèm cái giá nếu sai.
- **Lộ trình:** A1 → A2 → A4 → A3 → A5a → A5b → A6 → **A7 (tài liệu này)** → A8 SSH/tmux → A9 phím tắt tuỳ biến, file cấu hình.
- **Thứ tự thực thi:** A7 chạy **sau khi A3, A4, A5a, A6 đã merge vào `main`** (D1). **Không cần A5b**: A7 chạy được trước hoặc sau A5b (C1, D2, D34). Plan: `docs/superpowers/plans/2026-10-07-desktop-cli-a7.md`.
- **Giữ nguyên:** spec A1 (D1–D16), A2 (C1–C8, D1–D19), A4 (N1–N9, D1–D27), A3 (P1–P9, D1–D30), A5a (R0–R8, D1–D26), A5b (B1–B9, D1–D30), A6 (W1–W7, D1–D38), spec chia sẻ terminal (`2026-10-01`), spec push (`2026-10-05`). Protocol điện thoại (`shellx_core` `AppMessage`), app mobile, relay **không đổi**. Tài liệu này chỉ **thêm** và ghi rõ chỗ nào sửa (§2 cuối).
- **Ký hiệu:** "A5b D9" = quyết định D9 của spec A5b; "C1"/"D1" không tiền tố = của tài liệu này. "Host" = tiến trình phục vụ API: tiến trình UI ShellX (trước A5b) hoặc daemon `shellx-mux` (sau A5b). "CLI" = lệnh `shellx`. "Agent" (chữ hoa, trong UI) = chương trình điều khiển ShellX qua CLI (Claude Code, Codex, script).

---

## 1. Mục tiêu

Như cmux: **mọi thứ người dùng làm bằng chuột/phím trong ShellX, một script hay một AI agent làm được bằng dòng lệnh** — tạo tab và workspace, chia pane, gửi chữ vào pane, đọc màn hình và scrollback, chờ một lệnh xong hay một dòng chữ xuất hiện, gửi thông báo, điều khiển pane trình duyệt (A6), theo dõi sự kiện. Kênh là socket cục bộ có xác thực của A5b (vai trò `cli` đã dành sẵn), chỉ cùng tài khoản hệ điều hành, không bao giờ ra mạng hay tới điện thoại. Kèm bộ **skill** cho Claude Code/Codex để agent biết dùng ShellX: chạy dev server ở pane bên cạnh, đọc log, mở pane trình duyệt, báo khi xong.

### Tiêu chí thành công (đo được)

1. **Có lệnh ngay:** sau khi mở ShellX, trong một tab mới `command -v shellx` in `…/ShellX/cli/shellx` (Windows `where shellx`); `echo $SHELLX_PANE_ID $SHELLX_TAB_ID` in hai số; `shellx --version` in `shellx <app> (api 1)` trong ≤ 50 ms.
2. **ls:** `shellx ls` liệt kê workspace → tab → pane với id `t…`/`p…`, tiêu đề, cwd, nhánh, cổng, số chưa đọc; `shellx ls --json` là một object JSON hợp lệ (`jq .` chạy được) đúng lược đồ §3.4.
3. **Chạy dev server bên cạnh:** trong pane A, `p=$(shellx split --right --cmd "python3 -m http.server 8000")` (chữ đầu ra của `split` chỉ là id pane mới, D11) → trong ≤ 1 s tab có hai pane, pane mới **không** lấy focus (bàn phím vẫn ở pane A), server chạy; `shellx wait $p --match 'Serving HTTP' --timeout 10` thoát 0; `shellx read $p --lines 20` in log; `shellx browser open http://localhost:8000 --pane $p` mở pane trình duyệt; `shellx browser eval <pane> --script 'return document.title'` in `"Directory listing for /"`.
4. **Gửi chữ an toàn:** `shellx send $p --text $'echo a\necho b' --enter` chạy như dán (bracketed paste khi shell bật); chữ chứa `ESC[201~` không thoát khỏi chế độ dán (bị lọc như clipboard A1).
5. **Chờ:** `shellx wait $p --idle` trả về khi lệnh trong pane xong và prompt hiện (shell có hook); `shellx wait $p --exit` in mã thoát khi shell thoát; hết giờ → mã thoát 5.
6. **Thông báo:** `shellx notify "Build xong"` trong pane ShellX → badge/dòng thông báo của tab đó (A4) **và** push điện thoại (như OSC 777); trong Terminal.app (không chia sẻ) → thông báo hệ thống ShellX + mục "Dòng lệnh" trong bảng thông báo.
7. **Sự kiện:** `shellx events --follow --json` in một dòng JSON cho mỗi lần mở/đóng tab, chia/đóng pane, đổi tiêu đề/cwd, thông báo; Ctrl+C dừng sạch.
8. **Bảo mật:** tài khoản khác không kết nối được (A5b tiêu chí 6); tiến trình không có token bị đóng sau bắt tay; vai trò `cli` gửi `sessions.open`/`agent.call`/`daemon.quit` → `forbidden`; tắt "Cho phép điều khiển ShellX bằng dòng lệnh" → `shellx send` thoát 6 với thông điệp rõ, `shellx notify` vẫn chạy; mỗi lệnh điều khiển làm dấu **"Agent"** hiện trên dòng tab đích 10 s.
9. **Skill:** `shellx skills install --claude` tạo `~/.claude/skills/shellx/SKILL.md`; chạy lại khi file đã bị sửa → hỏi trước khi ghi đè; Claude Code thấy skill `shellx`.
10. **Mã thoát và trợ giúp:** `shellx help`, `shellx help <lệnh>` đầy đủ; `shellx completions zsh|bash|pwsh` sinh script chạy được; mã thoát đúng bảng D10.
11. **Hai host, một hợp đồng:** bộ test hợp đồng API chạy xanh với host trong UI; sau A5b chạy xanh cả với daemon + UI chuyển tiếp (C7).
12. **Không hồi quy:** mọi test A1–A6, `cargo test` của `term/` (kể cả link chia sẻ terminal) xanh; `shellx-term` gọi từ khối shell vẫn chạy y như cũ.

---

## 2. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| C1 | Kênh (controller) | IPC A5b (Unix socket 0600 / named pipe có ACL), vai trò `cli`, xác thực bằng file token per-user 0600. Trước A5b, **chính tiến trình UI** phục vụ cùng API trên cùng đường dẫn socket — A7 ra trước hay sau A5b đều được; task A7 không được cần A5b | — |
| C2 | Binary (controller) | Mở rộng `shellx-term` (Rust); lệnh người dùng tên `shellx` (bản chép/symlink) có lệnh con; `--json`; mặc định chữ cho người; mã thoát có tài liệu; `shellx help` đủ; completion zsh/bash/pwsh | — |
| C3 | Lệnh MVP (controller) | `ls`, `new-tab`, `split`, `focus`, `close`, `send`, `read`, `rename`, `workspace new\|rename\|move`, `notify`, `wait`, `browser open\|eval\|screenshot\|console\|network\|wait`, `events --follow` | — |
| C4 | Bảo mật (controller) | Chỉ cùng tài khoản; không listener mạng; công tắc "Cho phép điều khiển ShellX bằng dòng lệnh" mặc định BẬT; dấu "Agent" khi CLI hành động; không bao giờ lộ ra điện thoại/relay | — |
| C5 | Biến môi trường (controller) | `SHELLX=1`, `SHELLX_PANE_ID`, `SHELLX_TAB_ID`, `SHELLX_SOCKET` trong shell của ShellX | — |
| C6 | Skill (controller) | Thư mục `agent-skills/` (Markdown cho Claude Code/Codex); `shellx skills install [--claude\|--codex]` chép vào thư mục cấu hình, hỏi trước khi ghi đè | — |
| C7 | Phiên bản (controller) | `api.version`; chỉ thay đổi thêm vào; test hợp đồng chạy với cả host trong UI và daemon | — |
| D1 | Tiền đề | A3 (pane), A4 (thông báo), A5a (bộ mã hoá scrollback dùng cho `read --ansi`), A6 (`BrowserCommandHandler`) đã merge. A5b tuỳ chọn | Nếu A6 trễ, plan Task 8 bỏ phần `browser` và ghi ledger; CLI trả `unknown_type` → mã 7 cho `shellx browser` |
| D2 | Hai host, một dây | **Host trong UI** (`CliHost`, trước A5b): UI mở listener trên đúng địa chỉ A5b D4 (`<app support>/mux/mux.sock` / `\\.\pipe\shellx-mux-<hash SID>`), ghi `mux/endpoint` đúng định dạng A5b D5 (secret + instance mới mỗi lần chạy), bắt tay đúng A5b D6 (HMAC hai chiều, nhãn `shellx-mux/daemon`/`shellx-mux/client`), chỉ nhận `role: "cli"` (`ui` → `unsupported_role`). **Daemon** (sau A5b): `MuxServer` nhận thêm `cli` (A5b D22). Nếu A7 merge trước A5b, A7 tạo các file dây của A5b **đúng tên và nội dung plan A5b Task 2–3** (`mux_messages`, `mux_handshake`, `mux_endpoint`, `mux_transport`, `windows_pipe_transport`); A5b khi chạy sau thì dùng lại, không viết lại | Khoá một thể hiện UI (A1) bảo đảm không có hai host cùng lúc; nếu lọt, host thứ hai `listen` thất bại → log, CLI vẫn dùng host đầu |
| D3 | Không gian tên | `api.*` — host tự trả (`api.version`). `cli.*` — host tự xử lý (`cli.notify`, `cli.events.subscribe`). `ui.*` — do UI xử lý (trước A5b gọi thẳng; sau A5b daemon chuyển tiếp, A5b D9). Vai trò `cli` chỉ được gửi `api.*`, `cli.*`, `ui.*`, `daemon.status`; mọi loại khác (`sessions.*`, `view.*`, `agent.*`, `daemon.quit`) → `error{forbidden}` (không ngắt kết nối). Agent không bao giờ đăng nhập, ghép điện thoại, đổi cài đặt agent hay tắt phiên nền qua CLI | Muốn script hoá cài đặt agent phải chờ lệnh riêng (thêm vào `ui.*`/`cli.*` sau, không tăng phiên bản) |
| D4 | Phiên bản API (C7) | `kCliApi = 1`, tách khỏi `protocol` của A5b. `api.version` → `{api: 1, app: "x.y.z", host: "ui"\|"daemon", ui: bool, caps: [chuỗi]}`. Chỉ thêm: lệnh mới thêm vào `caps` (vd. `ui.pane.read`, `ui.browser`), khoá mới bị bên cũ bỏ qua. CLI gọi `api.version` ở mỗi lần chạy (cùng kết nối), lệnh cần cap không có → mã 7 "ShellX quá cũ cho lệnh này — cập nhật ShellX". `api` khác 1 → mã 7. Chỉ thay đổi phá vỡ mới tăng `api` | — |
| D5 | Thông điệp | Khung A5b: `{"t", "q", …}` → `{"t":"result","q",…}` / `{"t":"error","q","code","message"?}`; sự kiện `{"t":"event", "kind", …}`. Mã lỗi mới (thêm vào A5b D9): `forbidden`, `cli_disabled`, `no_ui`, `timeout`, `exited`, `running_command`, `no_room`, `ambiguous`; dùng lại `bad_request`, `not_found`, `unknown_type`, `busy`, `session_limit`, `spawn_failed`, `internal` và mã A6 §3.6 | — |
| D6 | Binary | Cùng file `shellx-term` (không binary thứ hai): `main` xem **tên gọi** (`argv[0]` bỏ đuôi `.exe`): `shellx` → chế độ CLI; ngoài ra `shellx-term cli <…>` cũng vào CLI (để test). Đường cũ (`wrap`, `probe`, `uninstall`, không đối số từ khối shell) **không đổi** — lỗi gõ ở chế độ CLI không bao giờ rơi vào nhánh "mở shell dự phòng". Mã API mới nằm ở mô-đun riêng `term/src/api/` với **codec CBOR đầy đủ riêng** (null, int âm, mảng, map lồng ≤ 8): `proto::cbor` của link chia sẻ terminal giữ nguyên byte cho byte | Binary to thêm ~150 KB |
| D7 | Cài lệnh | `CliBinaryInstaller` (cùng logic `TermBinaryInstaller`: chép qua file tạm + rename; Windows đổi tên bản đang chạy `.old-<n>`) chép binary của app thành `<support>/cli/shellx` (macOS: `~/Library/Application Support/ShellX/cli/shellx`; Windows `%LOCALAPPDATA%\ShellX\cli\shellx.exe`) **mỗi lần UI khởi động** nếu khác byte. Thư mục `cli/` tách khỏi `bin/` của chia sẻ terminal (sự có mặt của `bin/shellx-term` không bị hiểu nhầm là đã bật chia sẻ). Gỡ cài đặt (`shellx-term uninstall`, Inno) xoá `cli/` | — |
| D8 | PATH | **Shell của ShellX:** `PATH` = `<support>/cli` + `PATH` cũ (môi trường gốc của `SessionManager`). **Terminal khác:** tray "Dòng lệnh" → "Cài lệnh shellx cho mọi terminal…": macOS tạo symlink `/usr/local/bin/shellx` → `<support>/cli/shellx` (thư mục ghi được → không hỏi; không → `osascript … with administrator privileges`, hộp mật khẩu hệ thống); Windows thêm `%LOCALAPPDATA%\ShellX\cli` vào `Path` của người dùng (`HKCU\Environment`, không cần quyền admin) + phát `WM_SETTINGCHANGE`. Mục đổi thành "Gỡ lệnh shellx khỏi terminal khác" khi đã cài. Không bao giờ sửa file khởi động shell cho việc này | Người dùng Apple Silicon không có `/usr/local/bin` trong PATH (hiếm: macOS mặc định có) → thông báo đường dẫn để tự thêm |
| D9 | Bộ phân tích đối số | Viết tay, **một bảng** `COMMANDS` (tên, tóm tắt, cờ, đối số vị trí) sinh ra cả bộ phân tích, `help` và completion. Không thêm `clap` (giữ crate nhỏ, khởi động nhanh, không phụ thuộc mới). Cờ dạng `--name value` và `--name=value`; `--` kết thúc cờ | — |
| D10 | Mã thoát | `0` thành công · `1` lỗi khác (`eval_error`, `load_failed`, `spawn_failed`, `session_limit`, `no_room`, `internal`…) · `2` sai cú pháp · `3` ShellX không chạy / không kết nối / bắt tay sai · `4` không tìm thấy (`not_found`, `ambiguous`) · `5` hết giờ (`timeout`) · `6` bị từ chối (`cli_disabled`, `forbidden`, `forbidden_origin`, `running_command`, ghi đè skill không được phép) · `7` không tương thích (`api`, thiếu cap, `unknown_type`) · `8` không có cửa sổ ShellX (`no_ui`, chỉ sau A5b) | — |
| D11 | Đầu ra | Mặc định: chữ cho người, **tiếng Anh** (công cụ dev; agent đọc). `--json`: đúng **một** object JSON trên stdout (sự kiện: một object mỗi dòng); lỗi với `--json` cũng in `{"error":{"code","message"}}` ra **stdout** (agent chỉ cần đọc stdout) và thoát mã D10; không `--json` → lỗi ra stderr `shellx: <thông điệp> (<code>)`. Chữ của terminal (`read`) in nguyên, không trang trí. Lệnh tạo đối tượng in **chỉ id** mới để dùng trong `$(…)`: `split` → `p<id>`, `new-tab` → `t<id>`, `workspace new` → `w:<id>`, `browser open` → `p-<n>`; các lệnh còn lại thành công thì im lặng (trừ lệnh đọc). Không màu khi stdout không phải TTY hoặc có `NO_COLOR` | Người dùng Việt thấy CLI tiếng Anh (thêm `LANG` sau) |
| D12 | Địa chỉ đối tượng | Pane `p<id>` (id phiên; pane trình duyệt `p-<n>`), tab `t<id>` (A3 D1), workspace `w:<id>` hoặc tên (không phân biệt hoa thường; trùng tên → `ambiguous`). Số trần: hiểu theo lệnh (pane cho `send/read/wait/split`, tab cho `rename`/`workspace move`). Đặc biệt: `@self` = `$SHELLX_PANE_ID`, `@tab` = `$SHELLX_TAB_ID`, `@focused` = pane focus của tab đang chọn. `focus`/`close` nhận cả pane và tab nên **bắt buộc** tiền tố hoặc `@…` (số trần → hiểu là pane). CLI phân giải `@self`/`@tab` tại chỗ; `@focused` gửi nguyên cho UI | — |
| D13 | `ls` | `ui.ls` → `{workspaces:[{id,name,collapsed,current,tabs:[{id,title,custom,selected,unread,running,agent,panes:[{id,kind:"terminal"\|"browser",title,cwd?,branch?,ports,running,exited?,exitCode?,focused,zoomed,phone,driver,url?}]}]}], selectedTab, focusedPane}` (§3.4). Chữ: cây thụt lề, cột id/tiêu đề/`~/cwd`/nhánh/`:cổng`/`●n` chưa đọc. `--ids` in mỗi id một dòng (dùng cho completion) | — |
| D14 | `new-tab` | `ui.tab.new{workspace?, cwd?, cmd?, focus?}`. Workspace mặc định = workspace hiện tại (A2 C5). `cwd` tương đối được CLI đổi thành tuyệt đối theo thư mục của CLI; áp quy tắc A3 D17 (sai → home, không lỗi). **Không chọn tab mới** trừ khi `--focus` (agent không cướp bàn phím, như A6 D38 `focus` mặc định false). Trả `{tab, pane}` | Người dùng không thấy ngay tab agent mở (dấu Agent + sidebar có tab mới) |
| D15 | `split` | `ui.pane.split{pane, direction: right\|down, cwd?, cmd?, focus?}`. `pane` mặc định `@self`, không có thì `@focused`. Tab chứa pane **không cần** đang chọn (sửa A3 D30): kiểm chỗ A3 D4 theo vùng pane hiện tại của cửa sổ áp lên cây của tab đó. `cwd` mặc định = cwd của pane đích (A3 P4). Pane mới **không** nhận focus trừ `--focus` (sửa A3 D3 cho đường CLI). Không đủ chỗ → `no_room` (không toast) | — |
| D16 | `--cmd` | Shell mới khởi động bình thường (login, hook, biến môi trường); `cmd` (≤ 16 KiB) được **dán + Enter** như `send` khi shell sẵn sàng: lần đầu phiên báo cwd (OSC 7 ở prompt đầu, A2 C1) hoặc, với shell không hook, sau 1,5 s không có output kể từ output đầu, tối đa 5 s. Pane ở lại sau khi lệnh xong (giống tmux `send-keys`, cmux `--command`) | Shell có prompt chậm hơn 5 s (rc nặng) nhận lệnh trước prompt: shell vẫn đọc từ PTY nên thường vẫn chạy |
| D17 | `focus` | `ui.focus{target}`: tab → chọn tab (mở rộng workspace thu gọn); pane → chọn tab + `focusPane` (A3). **Không** đưa cửa sổ lên trước trừ `--raise` (hiện + kích hoạt như A1 D11) | — |
| D18 | `close` | `ui.close{target, force}`: pane → `closePane`; tab → `close` (mọi pane). Đang chạy lệnh (A1 D15 / A3 D28) và không `--force` → `running_command` (mã 6), **không** mở hộp xác nhận trên UI | — |
| D19 | `send` | `ui.pane.send{pane, text?, keys?: [tên], enter?}`. `text` đi qua **`DesktopTerminal.paste`** — cùng đường dán clipboard của A1: lọc ký tự điều khiển (kể cả ESC → không thể kết thúc bracketed paste sớm), xuống dòng → CR, bọc bracketed paste khi shell bật. `--enter` gửi phím Enter **sau** phần dán. `--key` (lặp được): `enter`, `tab`, `esc`, `backspace`, `up`, `down`, `left`, `right`, `home`, `end`, `pageup`, `pagedown`, `ctrl-a`…`ctrl-z`, `ctrl-\`, `ctrl-]` qua `keyInput`/`charInput` (đúng chế độ phím con trỏ của ứng dụng). `--stdin` đọc chữ từ stdin. Tổng ≤ 48 KiB. Ghi như người dùng gõ → desktop thành driver (A1 D6). Pane đã thoát → `exited`; pane trình duyệt → `bad_request` | Chữ nhiều dòng không có bracketed paste chạy từng dòng (y như dán tay) |
| D20 | `read` | `ui.pane.read{pane, lines?, ansi?, offset?}`. Không `lines` → **màn hình hiện tại** của buffer đang dùng (alt screen nếu đang vim/less). `lines: N` (1–10000) → N dòng logic cuối (dòng cuộn nối lại) của buffer đang dùng, gồm scrollback. Bỏ dòng trống cuối. `ansi` → mã hoá lại từ ô xterm chỉ chữ + SGR (bộ mã A5a D5, **không bao giờ** byte PTY thô: không tiêu đề, clipboard, chế độ chuột). Kết quả > 48 KiB → chia trang: `{text, next?}`, CLI tự lấy tiếp | Đọc lúc đang có output: các trang có thể lệch nhau một dòng (chấp nhận; agent đọc lại) |
| D21 | `wait` | `ui.pane.wait{pane, mode: idle\|exit\|match, pattern?, quietMs?, timeoutMs, fromNow?}`; mặc định hết giờ 30 s, tối đa 3600 s. **idle** = shell có hook (đã báo cwd): không chạy lệnh (A4 `runningCommand` false) **và** im ≥ `quietMs` (mặc định 500); shell không hook: im ≥ 2 s. **exit** = phiên kết thúc → `{exitCode}` (mã thoát của CLI vẫn là 0). **match** = `RegExp(pattern, multiLine: true)` (cú pháp ECMAScript/Dart, ≤ 1 KiB, sai → `bad_request`) chạy trên tối đa 2000 dòng logic cuối (≤ 256 KiB chữ) lúc bắt đầu và sau mỗi output (gộp 100 ms); `--from-now` chỉ xét dòng từ vị trí con trỏ lúc bắt đầu trở đi → `{match, line}`. CLI bị Ctrl+C → kết nối đóng → host huỷ chờ | Regex xấu (backtracking thảm hoạ) có thể làm UI khựng — cùng người dùng tự gây; giới hạn 256 KiB giảm nhẹ |
| D22 | `rename`, `workspace` | `ui.tab.rename{tab, name}` (A2 D19: cắt, ≤ 64, rỗng → tên tự động). `ui.workspace.new{name?, focus?}` → tạo "Workspace N" (A2 D15) hoặc tên cho sẵn, **mở một tab** trong đó (A2: workspace mới luôn có tab), không đổi workspace hiện tại / tab chọn trừ `--focus`, không mở ô đổi tên. `ui.workspace.rename{workspace, name}` (Mặc định đổi tên được, A2 D11). `ui.workspace.move{tab, workspace}` chuyển tab xuống cuối workspace đích | — |
| D23 | `notify` | Luật chọn đường (theo thứ tự): (1) có `--pane` hoặc `$SHELLX_PANE_ID` → `cli.notify{pane, title?, body}` → host gọi **`LocalSessions.notify(pane, …)`** mới: đi đúng đường của OSC 777 trong phiên đó (push điện thoại qua `SessionNotifier` + `SessionNotice` → A4), cùng giới hạn 30/phút/phiên (A4 D6); (2) không có pane nhưng `$SHELLX_TERM` khớp TTY hiện tại (cửa sổ đang chia sẻ, spec 2026-10-01) → ghi `OSC 777;notify;<title>;<body>` vào `/dev/tty` (y như hàm `shellx` cũ của khối shell — giữ hành vi push); (3) còn lại → `cli.notify{title?, body}` không pane → UI hiện **thông báo hệ thống** (theo công tắc A4 D20, giới hạn app 20/phút A4 D15) và thêm mục **"Dòng lệnh"** vào bảng thông báo (không tab, Enter chỉ đưa cửa sổ lên; không badge). Nếu (1)/(3) không kết nối được mà đang trong pane ShellX có `/dev/tty` → rơi về OSC 777 qua TTY. Chữ ≤ 1 KiB, tiêu đề ≤ 128 ký tự, ký tự điều khiển bị bỏ. Khi PATH có binary `shellx`, hook shell (push §4.5) **không** định nghĩa hàm `shellx` nữa — binary thay nó | Đường (3) không gửi push (không có phiên để gắn); người cần push từ cron dùng `--pane` |
| D24 | `events` | `cli.events.subscribe{kinds?}` → `result{}` rồi luồng `event`: `tab.opened`, `tab.closed`, `tab.renamed`, `tab.selected`, `tab.moved{workspace}`, `pane.opened{tab}`, `pane.closed`, `pane.exited{exitCode}`, `pane.focused`, `pane.changed{title,cwd,branch,ports,running}` (gộp 250 ms mỗi pane, chỉ khi khác), `workspace.created/renamed/deleted`, `notice{pane, tab, type, title?, body?}` (A4; `type` = loại thông báo vì `kind` là loại sự kiện; gồm chữ — cùng người dùng, cùng máy). Pane đầu của tab mới chỉ báo bằng `tab.opened` (id pane = id tab, A3 D1); `pane.opened` dành cho pane sinh ra do chia, sau A5b thêm `ui.attached`/`ui.detached`. Hàng đợi mỗi người nghe ≤ 1000 sự kiện; tràn → bỏ và gửi `{kind:"overflow", dropped:n}`. ≤ 4 người nghe đồng thời. `shellx events` không `--follow` = in sự kiện trong `--for` giây (mặc định 0: chỉ đăng ký rồi thoát — dùng để kiểm) | Agent chậm mất sự kiện (báo bằng `overflow`; gọi lại `ls` để đồng bộ) |
| D25 | `browser` | Lệnh con ánh xạ 1:1 A6 §3.6: `ls`, `open URL [--tab T\|--pane P] [--down] [--focus]`, `nav P URL [--no-wait]`, `back/forward/reload/stop/close P`, `wait P`, `eval P (--script S\|--file F\|-)`, `screenshot P [--out FILE]` (chép từ đường dẫn A6 D24 ra FILE), `console P [--since N] [--level L] [--limit N]`, `network P [--since N]`. Thêm ba lệnh tiện dụng (A6 §3.6 giao cho A7), **dựng trên `eval`** trong CLI, cùng cổng A6 D20: `query P SEL [--limit 50]` (text, value, href của tối đa 50 phần tử), `click P SEL`, `fill P SEL TEXT` (gán `value` + phát `input`/`change`). Selector/chữ được nhúng bằng `JSON.stringify` phía CLI (chuỗi JSON hợp lệ), không ghép chuỗi thô. UI chuyển `ui.browser.*` cho `BrowserCommandHandler` của A6 nguyên vẹn | `fill` không qua được framework theo dõi giá trị bằng setter riêng (React) — dùng `eval` |
| D26 | Công tắc (C4) | Khoá settings UI `cli_control_enabled` (bool, mặc định `true`; UI ghi theo A5b D13). Tắt → mọi `ui.*` và `cli.events.subscribe` trả `cli_disabled` (mã 6: "Điều khiển bằng dòng lệnh đang tắt trong ShellX (khay → Dòng lệnh)"); **vẫn cho** `api.version` và `cli.notify` (vô hại, tương đương `printf` OSC). Áp dụng ngay, không ngắt kết nối đang mở. Tray: submenu mới **"Dòng lệnh"** ngay sau "Trình duyệt" (A6 D27): ☑ "Cho phép điều khiển ShellX bằng dòng lệnh", "Cài lệnh shellx cho mọi terminal…" / "Gỡ lệnh shellx khỏi terminal khác", "Sao chép lệnh cài skill cho agent" (chép `shellx skills install` vào clipboard). Tắt không cần xác nhận; bật lại không cần xác nhận | Người dùng bật/tắt từ tray, không có trang cài đặt riêng (theo A4/A5a/A6) |
| D27 | Dấu "Agent" (C4) | Mỗi lệnh `ui.*` **nhắm một đối tượng** (mọi lệnh trừ `ui.ls`, `ui.browser.list`, `cli.events.*`, `api.*`) bật dấu **"Agent"** trên dòng sidebar của tab đích và trên đầu pane đích (A3 D15, khi có) trong **10 s** kể từ lệnh cuối — cùng hình A6 UI §2.1 (`Icons.smart_toy_outlined` 12 + "Agent", `warnBg`/`warnBorder`, `rPill`, cao 16 trên dòng, 20 trên đầu pane). Đọc lên lịch sự "Agent đang điều khiển {tab}" ≤ 1 lần/60 s. Pane trình duyệt: gọi thêm `agentCommand()` của A6 D25 (dấu trên thanh công cụ). Workspace mới/đổi tên: dấu trên tab mở kèm / không dấu | Dòng sidebar chật thêm một chip 10 s |
| D28 | Không ra điện thoại (C4) | Vai trò `cli` chỉ trên kênh cục bộ (A5b D23); relay và protocol điện thoại không đổi; không có lệnh nào của điện thoại tới `ui.*`/`cli.*`. Phiên do CLI mở là phiên desktop thường (điện thoại thấy như mọi tab desktop, A1) | — |
| D29 | Biến môi trường (C5) | `SessionManager` cấp id phiên **trước** khi spawn (id không dùng lại nên spawn lỗi chỉ bỏ phí một số) và đặt `SHELLX_PANE_ID=<id>`, `SHELLX_TAB_ID=<tabId ?? id>`; `LocalSessions.open({cols, rows, cwd, int? tabId})` (chia pane truyền id tab, tab mới để trống → bằng id của chính nó, A3 D1). `SHELLX_SOCKET=<địa chỉ host>` và `PATH` (D8) nằm trong môi trường gốc do desktop truyền cho `SessionManager`. Phiên điện thoại mở cũng có `SHELLX_PANE_ID`/`SHELLX_TAB_ID` (= id) — tab của nó mở ở desktop có cùng id. Biến cố định từ lúc spawn: id tab không đổi suốt đời tab (A3 D1) | Pane chuyển tab (chưa có, A3 P7) sẽ mang id tab cũ |
| D30 | Tìm host | CLI: địa chỉ = `--socket` › `$SHELLX_SOCKET` › trường `address` trong file endpoint; secret luôn từ file endpoint (mặc định = `MuxPaths.endpoint` của A5b: macOS `~/Library/Application Support/pro.shellx.desktop/mux/endpoint`, Windows `%LOCALAPPDATA%\ShellX\mux\endpoint` — A5b D5; một test Dart ghim chuỗi này để Rust và app không lệch; ghi đè bằng `$SHELLX_ENDPOINT` — chỉ cho test). File thiếu/hỏng/không kết nối được/bắt tay sai → mã 3 "ShellX is not running (open ShellX and try again)". Kết nối + bắt tay hết giờ 2 s | — |
| D31 | Vào/ra đồng bộ | CLI là client **đồng bộ, một yêu cầu tại một thời điểm**: ghi yêu cầu, đọc tới khi có `result`/`error` cùng `q` (bỏ qua sự kiện lạ); `events` chỉ đọc sau khi đăng ký. Không đọc và ghi đồng thời — tránh việc Windows tuần tự hoá I/O trên handle pipe đồng bộ. Windows: `ERROR_PIPE_BUSY` → thử lại mỗi 50 ms tới 2 s | — |
| D32 | Giới hạn host | ≤ 8 kết nối `cli` đã xác thực đồng thời (thêm → `busy` rồi đóng); ≤ 4 đang bắt tay (A5b D23); một kết nối xử lý yêu cầu **tuần tự** (cái sau chờ cái trước); `wait` chiếm kết nối tới khi xong. Khung ≤ 64 KiB; trường chữ trong yêu cầu ≤ 48 KiB | — |
| D33 | Đồng thời với người dùng | Lệnh mở phiên (`new-tab`, `split`, `workspace new`) dùng chung cờ `opening` của A3 D5: đang có lần mở khác → chờ (thử lại mỗi 50 ms) tối đa 10 s rồi `busy`. Hộp thoại xác nhận đang mở trên UI không chặn CLI | — |
| D34 | Sau A5b | Daemon: `cli` vào allowlist D3; `api.version` (host `daemon`, `ui` = có UI gắn), `cli.notify` có pane → `LocalSessions.notify` trong daemon (chạy cả khi không có UI). `ui.*` → chuyển tiếp nguyên văn cho UI qua kết nối `ui` với `q` mới của daemon, trả lời ánh xạ về `q` của CLI; không có UI → `no_ui` (mã 8). `cli.notify` không pane và `cli.events.subscribe` cũng cần UI (`no_ui`). Riêng **`ui.ls` khi không có UI**: daemon tự trả `{ui: false, sessions: [...]}` từ `sessions.list` (CLI in danh sách phẳng "ShellX window is closed"). Sự kiện: daemon đăng ký với UI (`ui.events.subscribe`) khi có ≥ 1 người nghe, phát lại cho từng người, thêm `ui.attached`/`ui.detached`. UI nhận yêu cầu từ daemon: `MuxClient` thêm bộ xử lý yêu cầu đến (A5b chỉ có chiều UI → daemon). Cùng `UiCommandHandler` phục vụ cả hai host | Không đọc/gửi được pane khi cửa sổ đã thoát (follow-up: `sessions.read` từ ring buffer ở daemon); Ctrl+C một `wait` đi qua daemon không huỷ phía UI — UI chờ tới hết giờ của nó (có giới hạn) |
| D35 | Skill (C6) | Thư mục gốc repo `agent-skills/shellx/` gồm `SKILL.md` (frontmatter `name: shellx`, `description` nói khi nào dùng; thân: kiểm `$SHELLX`, công thức dev server/đọc log/chờ/trình duyệt/thông báo, luật lịch sự: không cướp focus, không đóng pane của người dùng, luôn `--json` khi cần phân tích) và `reference.md` (mọi lệnh, mã thoát). File được **nhúng vào binary** (`include_str!`) — cài không cần đường dẫn trong app bundle, luôn khớp phiên bản CLI. `shellx skills install [--claude] [--codex] [--dir D] [--force]`: không cờ → mọi đích có thư mục gốc tồn tại (`~/.claude`, `~/.codex`); đích: `~/.claude/skills/shellx/`, `~/.codex/skills/shellx/` (Windows dưới `%USERPROFILE%`). File đích khác nội dung → TTY: hỏi "Overwrite …? [y/N]"; không TTY: từ chối (mã 6) trừ `--force`; giống hệt → "up to date". `shellx skills print [reference]` in nội dung | Đường dẫn skill của Codex đổi theo phiên bản Codex: plan Task 10 kiểm tài liệu Codex lúc làm; sai thì chỉ đổi một hằng |
| D36 | Completion | `shellx completions zsh\|bash\|pwsh` in script sinh từ bảng D9 (lệnh, lệnh con, cờ). Đối số pane/tab gợi ý động bằng `shellx ls --ids` (hết giờ 300 ms, lỗi → không gợi ý). Người dùng tự nạp (`shellx completions zsh > ~/.zfunc/_shellx`); `help completions` hướng dẫn. ShellX không tự sửa file khởi động | — |
| D37 | Test hợp đồng (C7) | (a) `cli_api_contract.dart` (`packages/shellx_agent/test/support/`): một bộ test chạy trên một `CliTestHost` trừu tượng; hiện thực 1 = `CliHost` trong UI qua `MemoryMuxTransport`; hiện thực 2 (thêm khi A5b đã merge) = `MuxServer` daemon + UI chuyển tiếp qua hai cặp ống bộ nhớ. (b) **Vector vàng chung Rust↔Dart** `term/protocol/mux_vectors.txt` (proof HMAC, khung `hello`/`auth`/`api.version`/`error`) — Rust `cargo test` và Dart `shellx_agent` cùng đọc. (c) `packages/shellx_e2e/test/cli_e2e_test.dart`: binary Rust thật ↔ `CliHost` thật qua Unix socket thật với `UiApi` giả (macOS/Linux) | — |
| D38 | Riêng tư/log | Không bao giờ log nội dung yêu cầu/kết quả (chữ gửi, chữ đọc, regex, script, URL, thông báo), token, đường dẫn người dùng — chỉ loại, mã lỗi, `runtimeType`. CLI không ghi file nào ngoài `--out` và skill | — |
| D39 | Windows | Named pipe A5b D4 cho host trong UI (FFI, isolate phụ mỗi kết nối); CLI mở pipe bằng `std::fs::OpenOptions` (`\\.\pipe\…`). `/dev/tty` của D23 → `CONOUT$`. Khối PowerShell không định nghĩa hàm `shellx` khi có `shellx.exe` trong PATH (đã đúng: `Get-Command shellx`). ⚠ MANUAL: pipe ACL, PATH người dùng + `WM_SETTINGCHANGE`, `shellx.exe` bị khoá khi cập nhật | Chưa có máy Windows → giữ "pending manual" trong ledger, không merge |
| D40 | Hiệu năng | CLI khởi động + kết nối + `api.version` + một yêu cầu đơn giản ≤ 50 ms (macOS, host rảnh). Host xử lý `ls` ≤ 5 ms với 32 phiên. `read` 10000 dòng ≤ 100 ms | — |

**Sửa A3:** D3 "pane mới nhận focus" — đường CLI mặc định không focus (D15). D30 "không xảy ra" — CLI chia được tab không được chọn (D15).
**Sửa A4:** bảng thông báo nhận mục không tab "Dòng lệnh" (D23); `SessionNotice` có thể đến từ `LocalSessions.notify` (cùng loại `message`).
**Sửa A5b:** D8 vai trò `cli` được nhận (D3 allowlist); D9 thêm mã lỗi D5; `sessions.open` thêm khoá tuỳ chọn `tab` (D29); `MuxClient` nhận yêu cầu từ daemon (D34). Nếu A7 merge trước, A5b Task 2–3 thành "đã có — chỉ kiểm".
**Sửa push §4.5:** hàm `shellx` của hook chỉ còn là dự phòng khi không có binary (vốn đã "chỉ khi chưa có lệnh `shellx`").
**Sửa `LocalSessions`:** `open(tabId:)` (D29), `notify(int id, {String? title, required String body})` (D23). Mọi hiện thực (`SessionManager`, `FakeLocalSessions`, `RemoteLocalSessions` nếu có) đổi cùng commit.

---

## 3. Kiến trúc

```
  shellx (Rust, = shellx-term gọi tên "shellx")             ShellX UI (trước A5b)
   ├─ api::args   bảng COMMANDS → parse/help/completion       ├─ CliHost ── MuxTransport.listen (UDS / pipe)
   ├─ api::value  CBOR đầy đủ + JSON                         │    ├─ bắt tay A5b D6, role cli, allowlist D3
   ├─ api::client endpoint → connect → bắt tay → request     │    ├─ api.version, cli.notify, cli.events
   ├─ api::run    mỗi lệnh → yêu cầu → in chữ/JSON, mã thoát │    └─ ui.* ─► UiCommandHandler (desktop) ─► TerminalTabs, SidebarWorkspaces,
   └─ api::skills nhúng agent-skills/                          │                                    TabAttention, BrowserCommandHandler (A6)
                                                               └─ CliEventBus ◄─ thay đổi tab/pane/workspace, notices
  Sau A5b:  shellx ─► daemon MuxServer (role cli) ─ api.*/cli.* tự trả ─ ui.* ─► (kết nối ui) ─► UiCommandHandler trong UI
```

### 3.1 `term/src/api/` (Rust, mới)

- `value.rs` — `Value { Null, Bool, Int(i64), Bytes, Text, Array, Map(Vec<(String, Value)>) }`, `encode`, `decode` (độ sâu ≤ 8, không độ dài vô hạn, khoá map chỉ là chữ), `to_json` (chuỗi JSON escape đúng; `Bytes` → base64).
- `wire.rs` — khung 4 byte + CBOR ≤ 64 KiB (dùng lại `proto::frame::{read_frame, write_frame}`), `Message { t, q, fields }`.
- `endpoint.rs` — đọc file endpoint A5b D5 (`v=1`, `address`, `secret`, `pid`, `instance`, `protocol`, `app`), đường dẫn mặc định.
- `client.rs` — `Conn` trên `UnixStream` / file pipe Windows; `handshake` (nhãn `shellx-mux/*`, dùng `hmac`/`sha2` đã có); `request(t, fields) -> Result<Fields, ApiError>`; `next_event()`.
- `args.rs` — bảng `COMMANDS`, `parse`, `help_text`, `completion_script`.
- `run.rs` — thực thi từng lệnh, in kết quả, ánh xạ mã thoát D10; `notify` với ba đường D23; `browser query/click/fill` sinh script.
- `skills.rs` — nhúng `agent-skills/shellx/*.md`, cài đặt có hỏi.
- `main.rs` — rẽ nhánh theo tên gọi (D6).

### 3.2 `packages/shellx_agent`

- `LocalSessions.open(tabId:)`, `LocalSessions.notify(...)`; `SessionManager` cấp id trước spawn, đặt biến D29; `SessionNotifier.message(...)` công khai.
- `src/mux/cli_host.dart` — `CliHost({transport, endpointFile, address, ui, enabled, appVersion})` (Dart thuần, để daemon A5b và test e2e dùng lại): listen, ghi endpoint, bắt tay, allowlist, giới hạn D32, hàng đợi tuần tự mỗi kết nối, `api.version`, `cli.notify`, `cli.events.subscribe`, chuyển `ui.*`.
- `src/mux/ui_api.dart` — `abstract interface class UiApi { Future<Map<String, Object?>> handle(MuxMessage request, {Future<void>? cancelled}); Stream<Map<String, Object?>> events(); Future<void> notifyApp({String? title, required String body}); bool notifyPane(int pane, {String? title, required String body}); }`, `CliFailure(code, message)`.
- `src/mux/` (A5b Task 2–3 nếu chưa có) + hằng A7: `MuxType.apiVersion = 'api.version'`, `cliNotify`, `cliEventsSubscribe`, `event`; `MuxError.forbidden`, `cliDisabled`, `noUi`, `timeout`, `exited`, `runningCommand`, `noRoom`, `ambiguous`; `kCliApi = 1`.

### 3.3 `apps/desktop/lib/src/cli/` (mới)

- `cli_service.dart` — khởi động `CliHost` (từ `shellx_agent`) với đường dẫn A5b `MuxPaths`.
- `ui_command_handler.dart` — `UiCommandHandler implements UiApi` trên `Ref`: phân giải đích D12, gọi `TerminalTabs`/`SidebarWorkspaces`/`BrowserCommandHandler`, bật dấu Agent D27.
- `cli_targets.dart` — phân tích `p…`/`t…`/`w:…`/`@focused`.
- `pane_text.dart` — `readPaneText`, `paneTextForMatch` (D20, D21).
- `pane_waiter.dart` — chờ idle/exit/match (D21), `CommandInjector` cho `--cmd` (D16).
- `cli_event_bus.dart` — so trạng thái `TerminalTabsState`/`SidebarState` trước-sau → sự kiện D24; notices A4.
- `agent_marks.dart` — `AgentMarks` (Notifier: tab/pane → hết hạn, đọc lên ≤ 1/60 s).
- `cli_install.dart` — `CliBinaryInstaller`, `PathInstaller` (macOS symlink / Windows HKCU, D8).
- Sửa: `terminal_tabs.dart` (`openTabFor`, `splitPane`, `sessionFor`), `sidebar_workspaces.dart` (`createNamed`, `moveTab` đã có thì dùng), `tab_attention.dart` (mục không tab), `session_tab_row.dart` + `pane_tree_view.dart` (chip Agent), tray (submenu "Dòng lệnh"), `settings_store.dart` (`cli_control_enabled`, `cli_path_installed`), `main.dart` (khởi động host, môi trường gốc).

### 3.4 Lược đồ JSON của `ls` (ví dụ)

```json
{"workspaces":[{"id":"default","name":"Default","current":true,"collapsed":false,
  "tabs":[{"id":"t1712","title":"vim","custom":false,"selected":true,"unread":2,"running":true,"agent":false,
    "panes":[{"id":"p1712","kind":"terminal","title":"vim","cwd":"/Users/me/app","branch":"main","ports":[3000],
              "running":true,"focused":true,"zoomed":false,"phone":false,"driver":"desktop"},
             {"id":"p-1","kind":"browser","title":"App","url":"http://localhost:3000/","focused":false}]}]}],
 "selectedTab":"t1712","focusedPane":"p1712"}
```

Id trong JSON là **chuỗi có tiền tố** (đúng dạng người dùng gõ lại được); trên dây (CBOR) là số (`pane`, `tab`) — CLI chuyển đổi.

---

## 4. Luồng dữ liệu

```
shellx split --right --cmd "npm run dev"
  ├─ args::parse ─► endpoint (SHELLX_SOCKET / file) ─► connect ─► hello/auth (HMAC 2 chiều) ─► api.version (caps)
  └─ ui.pane.split{pane: $SHELLX_PANE_ID, direction: right, cmd}
        ─► CliHost: role cli ✓, cli_control_enabled ✓ ─► UiCommandHandler
        ─► TerminalTabs.splitPane(target, focus: false) ─► LocalSessions.open(cwd, tabId) ─► PTY (SHELLX_PANE_ID=new)
        ─► CommandInjector: chờ prompt đầu (OSC 7) ─► DesktopTerminal.paste(cmd) + Enter
        ─► AgentMarks.touch(tab, pane) ─► result{pane, tab} ─► CLI in "p1714" (hoặc JSON), thoát 0
shellx notify "xong" (trong pane)  ─► cli.notify{pane} ─► LocalSessions.notify ─► SessionNotifier.message (push) + SessionNotice (A4)
shellx events --follow ─► cli.events.subscribe ─► CliEventBus ─► event… (đến khi Ctrl+C đóng kết nối)
```

---

## 5. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| ShellX chưa mở | Mã 3, "ShellX is not running (open ShellX and try again)". CLI **không** tự mở app (agent không bất ngờ bật cửa sổ) |
| Endpoint cũ (app crash, file còn) | Kết nối thất bại → mã 3 |
| Tiến trình chiếm socket/pipe không có secret | Bắt tay sai proof → CLI đóng, không gửi gì thêm (A5b D6) → mã 3 |
| Pane id không tồn tại / đã đóng | `not_found` → mã 4 |
| `@self` ngoài ShellX | Mã 2 "@self needs SHELLX_PANE_ID (run inside a ShellX pane)" |
| Chia khi pane quá nhỏ | `no_room` → mã 1 (UI không toast) |
| 32 phiên | `session_limit` → mã 1 |
| `send` vào pane đã thoát | `exited` → mã 1 |
| `close` pane đang chạy lệnh | `running_command` → mã 6, gợi ý `--force` |
| `wait` khi pane đóng giữa chừng | `--exit`: trả mã thoát; chế độ khác: `exited` → mã 1 |
| CLI bị kill khi đang `wait`/`events` | Kết nối đóng → host huỷ, giải phóng |
| Tắt công tắc khi `events` đang chạy | Luồng tiếp tục tới khi người nghe ngắt (áp dụng cho yêu cầu mới) — ghi chú trong help |
| Hai agent cùng chia một pane | Tuần tự bởi cờ `opening` (D33) |
| Regex sai | `bad_request` → mã 2 |
| Kết quả `read` rất dài | Phân trang 48 KiB (D20) |
| UI đang có hộp thoại/menu | Lệnh vẫn chạy (không chặn bởi overlay) |
| Bản CLI mới gặp ShellX cũ | Thiếu cap → mã 7 với lời khuyên cập nhật |
| Bản CLI cũ gặp ShellX mới | Khoá lạ bị bỏ qua (D4) |
| Sau A5b, cửa sổ đã thoát | `ls` phẳng; `notify --pane` chạy; còn lại `no_ui` mã 8 |

---

## 6. Kiểm thử

- **Rust (`~/.cargo/bin/cargo test` trong `term/`):** `api::value` (khứ hồi mọi kiểu, độ sâu 9 bị từ chối, JSON escape, số âm), `api::wire`/`api::endpoint` (vector vàng, file hỏng), `api::client` (bắt tay với host giả Rust trong luồng: proof đúng/sai, hết giờ, `q` khớp, bỏ qua event lạ), `api::args` (mọi lệnh, cờ sai → mã 2, `help` có mọi lệnh, completion chứa mọi lệnh), `api::run` (mỗi lệnh dựng đúng yêu cầu và in đúng chữ/JSON với host giả; ánh xạ mã thoát D10; `notify` ba đường; `browser fill` escape), `api::skills` (thư mục tạm: cài mới, giống hệt, khác + không TTY → 6, `--force`). Test cũ của link chia sẻ terminal giữ nguyên.
- **Dart `shellx_agent`:** `open(tabId:)` + biến môi trường (`FakePtyFactory` ghi lại env), `notify` → `notices` + `SessionNotifier` (sender giả), vector vàng `mux_vectors.txt`.
- **Dart desktop:** `cli_targets_test`, `cli_host_test` (allowlist, công tắc, giới hạn, tuần tự, đóng khi bắt tay sai), `ui_command_handler_test` (mọi `ui.*` với `FakeLocalSessions` + container Riverpod), `pane_text_test`, `pane_waiter_test` (`fake_async`), `cli_event_bus_test`, `agent_marks_test`, `cli_install_test` (thư mục tạm, chmod giả, registry giả), widget test chip Agent + tray submenu, `cli_api_contract_test` (D37a).
- **E2E:** `packages/shellx_e2e/test/cli_e2e_test.dart` (D37c).
- **Thử tay (HANDOFF, ⚠ MANUAL):** macOS và Windows thật — tiêu chí 1–10; cài PATH macOS (có/không quyền ghi `/usr/local/bin`), Windows PATH + mở terminal mới thấy `shellx`; Claude Code thật dùng skill (chạy dev server, đọc log, mở trình duyệt, notify); VoiceOver/Narrator đọc "Agent đang điều khiển …"; completion zsh/bash/pwsh.

---

## 7. Ngoài phạm vi A7

Điều khiển qua mạng/SSH (chỉ cục bộ); điện thoại dùng CLI API; `read`/`send` khi cửa sổ đã thoát (sau A5b — cần đọc ring buffer ở daemon); ảnh chụp **terminal** (chỉ có ảnh pane trình duyệt của A6); quyền theo từng agent/token riêng; MCP server (agent dùng CLI qua skill); tự mở ShellX khi chưa chạy; i18n đầu ra CLI; phím tắt tuỳ biến và file cấu hình (**A9**).

## Sửa đổi (quyết định của controller, 2026-10-07)
Mặc định chỉ shell do ShellX mở mới điều khiển được: host chỉ nhận client CLI có token theo lần chạy, truyền qua biến môi trường `SHELLX_CLI_TOKEN` cho shell do ShellX mở. Đường HMAC qua endpoint file (mọi tiến trình cùng user) tắt cho đến khi bật "Cho phép terminal khác" trong menu khay "Dòng lệnh". `notify` và `api.version` vẫn theo luật cũ. Quyết định này thay mặc định bảo mật tương ứng ở trên.
