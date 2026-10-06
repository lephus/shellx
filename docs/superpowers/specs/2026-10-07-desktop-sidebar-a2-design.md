# A2 — Sidebar giàu thông tin trên desktop — Đặc tả thiết kế

- **Ngày:** 2026-10-07
- **Trạng thái:** Người dùng giao toàn quyền cho controller (như A1). Quyết định C1–C8 do controller chốt; D1–D19 do người viết spec chốt trong phạm vi C1–C8. Tất cả ghi ở bảng §2 kèm cái giá nếu sai.
- **Lộ trình:** A1 (cửa sổ terminal, đã trên `main`) → **A2 (tài liệu này)** → A4 thông báo kiểu cmux → A3 split pane → A5 khôi phục session + daemon → A6 trình duyệt nhúng → A7 CLI/socket → A8 SSH/tmux → A9 skills, phím tắt tuỳ biến, file cấu hình.
- **Tài liệu đi kèm:** UI addendum `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a2.md` (đo đạc, token, wireframe, chuỗi; ràng buộc cho phần nhìn); plan `docs/superpowers/plans/2026-10-07-desktop-sidebar-a2.md`.
- **Giữ nguyên A1:** spec `2026-10-06-desktop-terminal-a1-design.md` (D1–D16) và UI doc A1 vẫn có hiệu lực; tài liệu này chỉ **thêm** và ghi rõ chỗ nào sửa A1.

---

## 1. Mục tiêu

Sidebar trở thành nơi nhìn một lần là biết mỗi tab đang ở đâu và đang làm gì, như cmux: mỗi dòng tab có thêm **một dòng ngữ cảnh** "nhánh git · thư mục · cổng đang nghe"; các tab được gom vào **workspace** (nhóm có tên, thu gọn được, kéo thả tab giữa các nhóm); tab **đổi tên** được.

### Tiêu chí thành công (đo được)

1. **Thư mục:** trong một tab zsh, bash hoặc PowerShell (có hook ShellX), `cd ~/work/shellx` → dòng ngữ cảnh hiện `~/work/shellx` **trong vòng 300 ms** sau khi prompt hiện. Tab không có hook (shell khác, hook không ghi được) → không hiện thư mục, không lỗi.
2. **Nhánh git:** `cd` vào một repo → nhánh hiện trong cùng lần cập nhật (≤ 300 ms); `git switch other` → nhánh mới hiện ≤ 300 ms sau khi lệnh xong (OSC 133;D). HEAD tách rời → 7 ký tự đầu của SHA. Worktree (`.git` là file `gitdir:`) và submodule đúng nhánh của chính nó. Agent **không bao giờ** chạy tiến trình `git`.
3. **Cổng:** trong một tab, `python3 -m http.server 8000` → `:8000` hiện trên dòng tab đó **≤ 4 s** (chu kỳ 3 s + thời gian quét); Ctrl+C → biến mất ≤ 4 s. Bấm `:8000` mở `http://localhost:8000/` trong trình duyệt mặc định. Hơn 3 cổng → 3 cổng nhỏ nhất + "+N".
4. **Không quét khi không ai xem:** cửa sổ ẩn, hoặc không còn phiên nào → **không** sinh tiến trình `lsof`/`ps`/`netstat`/`powershell` nào (kiểm bằng test với runner giả; thử tay bằng `sudo fs_usage -f exec | grep lsof` hoặc Activity Monitor).
5. **Chi phí:** một lần quét trên macOS với 32 phiên ≤ 150 ms thời gian thực (đo bằng log debug, không ghi nội dung); ShellX rảnh với 10 tab, cửa sổ hiện → CPU trung bình ≤ 2 % trong 1 phút (Activity Monitor, Apple M-series).
6. **Workspace:** ⌘⇧N / Ctrl+Shift+N tạo workspace mới (kèm một tab mới, ô đổi tên mở sẵn); đổi tên (double-click tiêu đề, F2, menu); xoá (tab chuyển về "Mặc định"); thu gọn/mở rộng; kéo thả tab giữa các workspace và trong cùng workspace; menu "Chuyển tới workspace…". Danh sách workspace, tên, trạng thái thu gọn **còn nguyên sau khi thoát và mở lại app**. ⌘1–⌘9 (Windows Ctrl+Alt+1…9) chọn theo **thứ tự đang nhìn thấy**.
7. **Đổi tên tab:** double-click dòng tab / F2 / menu → ô sửa tại chỗ; tên người dùng thắng tiêu đề OSC; để trống → về tên tự động. Tiêu đề cửa sổ theo tên mới.
8. **Điện thoại:** điện thoại đã `session.list {desktop: true}` nhận thêm `cwd`, `branch` trong mỗi `SessionInfo` (khi có); điện thoại cũ (`desktop: false`) nhận danh sách **giống từng byte** A1 (test so sánh). App mobile không đổi trong A2.
9. **Không hồi quy A1:** mọi test A1 vẫn xanh (trừ các fake phải bổ sung thành viên interface mới); mọi hành vi D1–D16 (driver, quy tắc thoát, phím tắt, Ctrl+F6) không đổi. Khi chỉ có workspace "Mặc định", sidebar trông **như A1** (không có tiêu đề nhóm).
10. **Trợ năng:** mọi phần mới có nhãn Semantics vi/en; tương phản chữ ≥ 4,5:1, thành phần không phải chữ ≥ 3:1; mọi thao tác kéo có lựa chọn thay thế bằng một cú bấm (WCAG 2.5.7) và bằng bàn phím; chuyển động tắt khi hệ thống giảm chuyển động.

---

## 2. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| C1 | Thư mục hiện tại (controller) | Hook shell zsh/bash/pwsh **thêm OSC 7** (`ESC ] 7 ; file://<host>/<path> BEL`, path percent-encode theo byte UTF-8) ở **mỗi prompt**. Agent đọc OSC 7 theo từng phiên. Phiên không có hook → không có cwd. Hiển thị: `~` thay home, cắt giữa (middle-ellipsis) | Shell không hook (fish, nu, cmd) không có thư mục cho tới khi có hook riêng |
| C2 | Nhánh git (controller) | Agent tìm nhánh bằng **Dart thuần** từ cwd: đi ngược lên tìm `.git`; `.git` là file `gitdir:` (worktree, submodule) thì theo; đọc `HEAD`: tên nhánh, hoặc SHA rút gọn khi tách rời. Cache theo thư mục, làm mới khi cwd đổi và ở mỗi OSC 133;D. **Không bao giờ chạy `git`**; IO giới hạn, bất đồng bộ | Trạng thái lạ (rebase dở, `GIT_DIR` tuỳ chỉnh, repo reftable) hiện SHA/nhánh có thể khác `git status` |
| C3 | Cổng đang nghe (controller) | Cổng TCP LISTEN của cây tiến trình mỗi phiên. Cần PID shell. macOS: `lsof -nP -iTCP -sTCP:LISTEN -Fpn` + `ps -axo pid=,ppid=`; Windows: `netstat -ano` + cây tiến trình qua CIM (D7). Chu kỳ 3 s **chỉ khi cửa sổ hiện và có ít nhất một phiên**. Hiện tối đa 3 + "+N"; bấm → `http://localhost:PORT` trong trình duyệt mặc định | Tiến trình đã tách khỏi cây (`nohup … &`, `disown`, daemon tự fork kép) không được gán cho tab |
| C4 | Dữ liệu và protocol (controller) | `SessionSummary` thêm `cwd`, `gitBranch`, `ports` (tuỳ chọn). Protocol: `SessionInfo` thêm khoá **tuỳ chọn** `cwd`, `branch`, chỉ gửi cho điện thoại đã `session.list {desktop: true}`. Quy tắc: bộ giải mã của mọi phiên bản app đã phát hành **bỏ qua khoá lạ** (`SessionInfo._fromMap` chỉ đọc khoá nó biết), nên thêm khoá tuỳ chọn không bao giờ làm hỏng app cũ; việc chỉ gửi cho điện thoại opt-in là để danh sách của app cũ giống hệt A1. `ports` **không** gửi. UI mobile: ngoài phạm vi (follow-up) | Nếu sau này có app nghiêm ngặt với khoá lạ thì phải giữ quy tắc opt-in |
| C5 | Workspace (controller) | Nhóm có tên trong sidebar, tiêu đề thu gọn được kèm số tab; workspace mặc định "Mặc định"/"Default". Tạo (⌘⇧N / Ctrl+Shift+N), đổi tên (double-click tiêu đề / menu), xoá (tab về Mặc định); chuyển tab bằng menu và kéo thả; tab mới mở trong workspace hiện tại; tab do điện thoại mở vào Mặc định. Thành viên = trạng thái UI desktop theo session id (trong bộ nhớ); danh sách + tên + thu gọn lưu trong settings. ⌘1–9 theo thứ tự nhìn thấy | Thoát app mất thành viên (phiên cũng chết khi thoát — tới A5 mới khôi phục) |
| C6 | Đổi tên tab (controller) | Double-click dòng hoặc menu → sửa tại chỗ; tên người dùng thắng OSC; rỗng → tên tự động; chỉ trên desktop (không gửi điện thoại trong A2) | Điện thoại vẫn thấy tên cũ |
| C7 | Bố cục dòng (controller) | Dòng tiêu đề + **một** dòng ngữ cảnh "branch · ~/path · :3000 :5173" chữ nhỏ/phụ; dòng cao lên cho vừa; Semantics vi/en; tương phản ≥ 4,5:1; tôn trọng giảm chuyển động | Sidebar 220 px chật: đường dẫn hay bị cắt (xem D12) |
| C8 | Giữ A1 (controller) | Driver, quy tắc thoát, phím tắt (kể cả Ctrl+F6) không đổi | — |
| D1 | Chỗ đặt mã phát OSC 7 | Trong **thân hook dùng chung** (`zshHookBody`, `bashHookBody`, `powerShellHookBody`), và cập nhật **cùng commit** bản sao trong `term/shell/block.{zsh,bash,ps1}` (test `shell_hook_sync_test.dart` bắt buộc hai nơi giống nhau). Lý do: bash không có chỗ móc an toàn nào khác ngoài `PROMPT_COMMAND` mà thân hook đã quản lý; hai bản lệch nhau là lỗi đã được test chặn. Terminal thật (Terminal.app, iTerm2) cũng hiểu OSC 7 và vô hại với terminal khác | Block terminal-sharing đã cài trong rc của người dùng chỉ có OSC 7 sau khi bật lại chia sẻ; không ảnh hưởng A2 |
| D2 | OSC 7 từ máy khác | Host rỗng, `localhost`, hoặc trùng nhãn đầu của hostname máy (không phân biệt hoa thường) → nhận. Host khác (shell trong `ssh` có tích hợp riêng) → **xoá** cwd và nhánh của tab (không hiện thư mục cũ sai) cho tới OSC 7 cục bộ tiếp theo | Ssh vào máy có cùng tên ngắn bị coi là cục bộ (hiếm) |
| D3 | PID của shell | **Không** thêm thành viên vào `Pty` (sẽ phá mọi fake). Thêm interface tuỳ chọn `PtyProcessId { int? get processId; }`; `FlutterPtyAdapter` và `ProcessPty` hiện thực nó; `SessionManager` kiểm `pty is PtyProcessId`. Không có PID → phiên không có cổng | — |
| D4 | Gán PID nghe vào phiên | Đi ngược chuỗi `ppid` từ PID nghe (tối đa 64 bước, chống vòng) tới PID shell của một phiên. Cache kết quả theo PID nghe; **chỉ chụp bảng tiến trình khi có PID nghe chưa phân loại** (hoặc danh sách phiên đổi); PID biến khỏi danh sách nghe thì bỏ khỏi cache | PID tái sử dụng trong < 3 s và lại nghe cổng → gán nhầm một chu kỳ |
| D5 | Lịch quét | Một lần quét tại một thời điểm; lần sau hẹn **3 s sau khi lần trước xong**. Lần quét > 1,5 s → khoảng cách nhân đôi, tối đa 15 s; quét nhanh lại → về 3 s. Mỗi lệnh con có timeout 2 s (riêng truy vấn CIM trên Windows: 5 s), quá thì bị kill. Cửa sổ hiện lại → quét ngay | Máy rất chậm thấy cổng trễ tới 15 s |
| D6 | Lỗi quét | `lsof` thoát mã 1 với stdout rỗng = "không có cổng nào" (không phải lỗi). Lỗi thật (không chạy được, timeout, mã khác) → giữ cổng cũ một lần, lỗi lần hai liên tiếp → xoá cổng và lùi về 15 s. Log chỉ `runtimeType`/mã thoát | Một lần lỗi thoáng qua hiện cổng cũ thêm ≤ 3 s |
| D7 | Windows | Cổng: `netstat -ano` (nhanh, có sẵn); dòng nghe nhận ra bằng **địa chỉ đích kết thúc `:0`** (`0.0.0.0:0`, `[::]:0`), không dựa vào chữ `LISTENING` (bị bản địa hoá). Cây tiến trình: `powershell -NoProfile -NonInteractive -Command "Get-CimInstance Win32_Process …"` — chậm (~1 s) nên chỉ chạy theo D4. Không dùng `wmic` (đã bị gỡ ở Windows 11 24H2). Cả hai chạy bằng **đường dẫn tuyệt đối** `%SystemRoot%\System32\netstat.exe` và `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe` (thiếu biến thì `C:\Windows`), không bao giờ tìm theo `PATH` hay thư mục làm việc | Windows chưa thử máy thật; cha đã chết thì chuỗi `ppid` đứt → cổng không gán được |
| D8 | "Cửa sổ hiện" | = cửa sổ terminal đang được hiện (`WindowState.visible`: terminal hoặc hộp thoại trên nó), kể cả khi thu nhỏ hoặc bị che. Desktop gọi `LocalSessions.watchPorts(bool)` | Quét cả khi cửa sổ thu nhỏ (chi phí nhỏ, D5) |
| D9 | Mở cổng trong trình duyệt | `UrlOpener.openLocalPort(int port)` mới: chỉ mở đúng `http://localhost:<1–65535>/`; mọi URL khác vẫn bị chặn như A1 (chỉ `https`) | — |
| D10 | Workspace khi chỉ có Mặc định | **Ẩn** tiêu đề nhóm: sidebar giống A1. Tiêu đề hiện khi có từ hai workspace | Người dùng mới ít thấy tính năng (bù bằng ⌘⇧N trong tooltip `+` và menu tab) |
| D11 | Mặc định | Không xoá được (mục menu mờ); đổi tên và thu gọn được. Tên lưu `null` → dùng chuỗi bản địa hoá "Mặc định"/"Default" | — |
| D12 | Chiều cao dòng | Dòng có ngữ cảnh cao 46 px; dòng không có ngữ cảnh giữ 30 px của A1 (cỡ chữ lớn: công thức ở UI addendum). Dòng cao lên một lần khi prompt đầu tiên báo thư mục. Sidebar giữ 220 px (kéo rộng: milestone sau). Thứ tự ưu tiên khi chật: cổng (không cắt) > nhánh (≤ 45 %, cắt cuối) > thư mục (cắt giữa, bỏ nếu < 24 px) | Một lần dịch dòng sidebar khi tab mới hiện prompt (không đổi cỡ PTY) |
| D13 | Từ "workspace" | Giữ tiếng Anh trong câu tiếng Việt, như "tab", "terminal", "shell" (quy tắc copy A1). Viết "Xóa" (kiểu cũ, khớp "Hủy" của A1) | — |
| D14 | Bàn phím trong sidebar | Khi có tiêu đề nhóm, danh sách thành cây (WAI-ARIA tree): ↑/↓ đi qua tiêu đề và dòng; trên dòng thì **chọn tab** như A1; trên tiêu đề chỉ hiện vòng focus (tab đang chọn không đổi). ←/→ thu gọn/mở rộng, Enter/Space trên tiêu đề = bật/tắt thu gọn, F2 đổi tên, Shift+F10 menu, ⌥↑/⌥↓ (Windows Alt+↑/↓) chuyển tab lên/xuống (qua ranh giới nhóm) | Khác A1 ở chỗ có "con trỏ" đứng trên tiêu đề (A1 không có tiêu đề) |
| D15 | Workspace mới | ⌘⇧N tạo "Workspace N" (N nhỏ nhất ≥ 2 chưa dùng) ở cuối, đặt làm hiện tại, mở một tab trong đó và mở sẵn ô đổi tên tiêu đề (chọn hết chữ). Enter/Esc/bấm ra ngoài → bàn phím về terminal của tab mới | — |
| D16 | Xoá workspace | Không hỏi (không mất dữ liệu: tab chuyển về cuối Mặc định, Mặc định tự mở rộng); hiện toast trung tính "Đã xóa workspace …" | Lỡ tay xoá phải tạo lại tên |
| D17 | Lưu workspace | Khoá settings mới `terminal_workspaces` (danh sách chuỗi JSON `{"id","name","collapsed"}`, theo thứ tự) — thêm vào `SettingKeys.all`. Thứ tự tab và thành viên không lưu | — |
| D18 | Kéo thả trong cùng nhóm | Kéo thả cũng **sắp xếp lại** trong một workspace (vị trí thả quyết định chỗ đứng). Lựa chọn không kéo: menu "Chuyển lên"/"Chuyển xuống"/"Chuyển tới workspace…" và ⌥↑/⌥↓ | — |
| D19 | Tên tab tuỳ chỉnh | Tối đa 64 ký tự, cắt khoảng trắng hai đầu; lưu trong `TerminalTabs` theo session id (trong bộ nhớ). Tiêu đề cửa sổ, nhãn Semantics, hộp xác nhận đóng tab dùng tên này | Mở lại app (phiên mới) mất tên — đúng vì phiên cũng mất |

**Sửa A1:** UI doc A1 §2.2 ghi "A2 sẽ làm dòng cao 46 và dòng tiêu đề `bodyStrong`" — A2 **giữ** kiểu chữ tiêu đề của A1 (`body`, đang chọn `bodyStrong`) để dòng đang chọn vẫn khác các dòng khác. A1 §7 "đổi tên tab: ngoài phạm vi" — nay trong phạm vi.

---

## 3. Kiến trúc

```
packages/shellx_agent
 ├─ notify/osc_event_parser.dart   + OSC 7 → CwdReported(url)
 ├─ pty/shell_hook_scripts.dart    + phát OSC 7 mỗi prompt (zsh/bash/pwsh)   (+ term/shell/block.*)
 ├─ pty/pty.dart                   + PtyProcessId { int? processId }
 ├─ context/ (mới)
 │   ├─ cwd_url.dart          parseCwdUrl: file://host/path → LocalCwd / RemoteCwd (D2), Windows `C:\…`
 │   ├─ git_head.dart         GitHeadReader: tìm .git, gitdir:, HEAD; cache; timeout
 │   └─ listening_ports.dart  parser lsof/ps/netstat/CIM, PortProbe (mac/win), PortWatcher (D4–D6)
 └─ session/session_manager.dart   mỗi phiên: cwd, gitBranch, ports; watchPorts(bool);
                                   sessionInfosWithContext cho SessionRouter (C4)
packages/shellx_core   SessionInfo + cwd, branch (khoá tuỳ chọn)
apps/desktop
 ├─ agent/session_core.dart        tạo GitHeadReader + PortProbe theo nền tảng
 ├─ platform/url_opener.dart       + openLocalPort (D9)
 ├─ terminal/terminal_tabs.dart    TerminalTab + cwd/gitBranch/ports/customTitle; rename()
 ├─ terminal/sidebar_workspaces.dart (mới)  workspace, thành viên, thứ tự nhìn thấy, lưu settings
 ├─ terminal/context_line.dart (mới)        `~`, cắt giữa, bố trí dòng ngữ cảnh (hàm thuần)
 └─ ui/terminal/  session_tab_row (dòng ngữ cảnh, sửa tên), workspace_header (mới),
                  session_sidebar (cây, kéo thả), terminal_shortcuts (+ ⌘⇧N), shellx_menu (+ vạch ngăn)
```

### 3.1 Agent

- **OSC 7.** `OscEventParser` nhận thêm số `7` → `CwdReported(String url)` (payload ≤ 4 KiB như các OSC khác). `CommandTracker.handle` bỏ qua sự kiện mới. Mỗi `_Session` giữ `cwd`, `gitBranch`, `ports`.
- **`parseCwdUrl(url, {windows, localHostName})`** → `LocalCwd(path)`, `RemoteCwd()` (D2: xoá cwd và nhánh) hoặc `null` (sai định dạng: bỏ qua, giữ cwd cũ). Giải mã percent-encoding theo UTF-8 (byte lỗi → bỏ qua cả OSC). Windows: `file:///C:/x` → `C:\x`, `file://server/share/x` (UNC) → `\\server\share\x` (không tra nhánh trên UNC, xem §5).
- **`GitHeadReader.branchFor(dir, {refresh})`** (hiện thực interface `GitBranchLookup`, IO qua interface `GitFiles` để test được timeout) chỉ ném `TimeoutException` (xem dưới): tìm `.git` từ `dir` lên tối đa 64 cấp (`FileSystemEntity.type`), đọc file `gitdir:` (≤ 4 KiB, đường dẫn tương đối tính từ thư mục chứa), đọc `<gitdir>/HEAD` (≤ 4 KiB). Cache LRU 64 mục `thư mục → gitdir` (cả "không phải repo"); HEAD **luôn đọc lại** (một file nhỏ). `refresh: true` bỏ cache của thư mục đó. Toàn bộ một lần tra ≤ 500 ms; quá thì Future kết thúc bằng `TimeoutException` — nhánh **chưa biết**, khác với `null` = "không phải repo": `SessionManager` giữ nhánh đang hiện (M3). Các lần tra cùng thư mục đang chạy dùng chung một Future. Tên nhánh cắt 200 ký tự.
- **Khi nào tra nhánh:** cwd đổi → tra (cache); OSC 133;D → tra với `refresh: true`. Mỗi phiên có số thế hệ: kết quả về muộn của lần tra cũ bị bỏ.
- **Cổng.** `PortWatcher` (một cho cả manager) nhận `PortProbe` (`listening()`: pid → cổng; `parents()`: pid → ppid) và hàm cho biết PID shell của từng phiên. Bật khi `watchPorts(true)` **và** có phiên; tắt thì huỷ hẹn giờ, không sinh tiến trình. Kết quả: phiên → danh sách cổng tăng dần, không trùng (IPv4/IPv6 cùng cổng gộp một). Đổi → `changes`.
- **`LocalSessions`** thêm `void watchPorts(bool visible)`. `SessionSummary` thêm `String? cwd`, `String? gitBranch`, `List<int> ports` (mặc định `const []`).
- **Protocol (C4).** `SessionInfo` thêm `cwd`, `branch` (`String`, mặc định `''`); `toMap` chỉ ghi khoá khi khác rỗng; `_fromMap` đọc `optionalString`. `SessionManager.sessionInfos` (A1, không ngữ cảnh) giữ nguyên; `sessionInfosWithContext` mới; `SessionRouter` dùng bản có ngữ cảnh khi `desktop == true`. Không có message mới, không đẩy cập nhật — điện thoại thấy giá trị mới ở lần `session.list` sau.

### 3.2 Desktop

- **`SessionCore`** tạo `GitHeadReader()` và `PortProbe` theo `Platform` (`MacPortProbe` / `WindowsPortProbe`), truyền vào `SessionManager` cùng `windowsPaths` và `Platform.localHostname`.
- **`main.dart`**: nghe `windowRouterProvider.select((s) => s.visible)` → `sessions.watchPorts(shown)` (gọi ngay một lần).
- **`TerminalTab`** thêm `cwd`, `gitBranch`, `ports`, `customTitle`; `label = customTitle ?? (title rỗng ? "<shell> <index>" : title)`. `TerminalTabs.rename(id, String? name)`.
- **`SidebarWorkspaces`** (Notifier mới): `workspaces` (thứ tự, tên, thu gọn), `members: Map<workspaceId, List<tabId>>`, `currentId`. Nghe `terminalTabsProvider`: tab mới gốc desktop → workspace hiện tại; gốc điện thoại → Mặc định; tab mất → bỏ. `visibleTabIds` = theo thứ tự workspace, bỏ tab trong nhóm thu gọn. Các hành động: `create()`, `rename`, `delete`, `toggleCollapsed`, `moveTab(tabId, toWorkspace, index)`, `moveUp/Down`, `selectVisible(position)`, `step(±1)`, `openTabIn(workspaceId)`. Lưu danh sách vào settings (D17) sau mỗi thay đổi danh sách/tên/thu gọn.
- **Phím tắt:** `SelectTabIntent`, `NextTabIntent`, `PreviousTabIntent` đi qua `SidebarWorkspaces` (thứ tự nhìn thấy); thêm `NewWorkspaceIntent` (⌘⇧N / Ctrl+Shift+N, không lặp phím). Phím A1 khác không đổi.
- **UI:** dòng ngữ cảnh, ô đổi tên, tiêu đề workspace, kéo thả, menu — xem UI addendum.

---

## 4. Luồng dữ liệu

```
shell prompt ─► OSC 7 + (133;D) ─► PTY output ─► SessionManager._track
                                     ├─ parseCwdUrl ─► session.cwd ─┐
                                     └─ GitHeadReader (async) ─► gitBranch ─┤
PortWatcher (3 s, chỉ khi watchPorts(true) & có phiên)                     ├─► changes ─► TerminalTabs._merge ─► sidebar
   lsof/netstat ─► pid nghe ─► (ps/CIM khi cần) ─► phiên ─► ports ─────────┘
session.list {desktop:true} ─► SessionRouter ─► sessionInfosWithContext (cwd, branch) ─► điện thoại
```

Nội dung terminal không đổi đường đi. Thư mục và nhánh tới điện thoại qua kênh mã hoá đầu cuối như mọi `SessionInfo`; relay không đọc được. Không thêm dữ liệu nào gửi lên relay dạng rõ.

---

## 5. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Shell không có hook (fish, cmd, hook không ghi được, `-NoProfile` tự gõ) | Không có cwd/nhánh; dòng chỉ có cổng (nếu có) hoặc là dòng 30 px của A1 |
| Người dùng tự phát OSC 7 (VTE `vte.sh`, oh-my-zsh, Starship) | Nhận như hook của ShellX (cùng định dạng); hai nguồn trùng nhau vô hại |
| OSC 7 sai định dạng / không phải `file:` / percent-encoding lỗi | Bỏ qua sự kiện, giữ cwd cũ |
| OSC 7 từ host khác (ssh) | D2: xoá cwd và nhánh |
| Repo cực lớn (monorepo, hàng triệu file) | Không ảnh hưởng: chỉ đọc `.git` (stat) và `HEAD` (một file), không quét cây |
| Thư mục sâu / ổ mạng chậm (`/Volumes/nas`, `\\server\share`, autofs) | Timeout 500 ms → giữ nhánh đang hiện (chưa biết ≠ không phải repo); một lần tra mỗi phiên tại một thời điểm, không chặn UI (IO bất đồng bộ). UNC trên Windows: không tra |
| Không có quyền đọc `.git`/`HEAD` | `FileSystemException` bị nuốt → không có nhánh; không log đường dẫn |
| `.git` file trỏ tới chỗ không tồn tại / vòng lặp symlink | Không có nhánh |
| HEAD là ref không phải nhánh (`refs/remotes/…`, `refs/tags/…`) | Hiện phần sau `refs/` |
| `lsof` chậm (máy tải nặng, nhiều socket) | Timeout 2 s → kill; D5 lùi tới 15 s; D6 xử lý lỗi |
| `lsof`/`ps` không có hoặc bị chặn (MDM) | D6: không có cổng, lùi 15 s; không hiện lỗi cho người dùng |
| `lsof` thoát 1, stdout rỗng | Không có cổng nào (bình thường) |
| Tiến trình nghe nhiều cổng / cả IPv4 và IPv6 | Gộp, sắp tăng dần; 3 + "+N" |
| Hai phiên lồng nhau (`zsh` trong `zsh`) | Mỗi PID nghe thuộc phiên có shell là tổ tiên gần nhất (đi ngược từ PID nghe, gặp shell nào trước thì là phiên đó) |
| Cổng của tiến trình chạy dưới người dùng khác (sudo) | `lsof` không thấy → không hiện (đúng: không mở được bằng localhost dễ dàng cũng không phải việc của tab) |
| Windows: `powershell` không chạy được / CIM chậm | D6 cho `parents()`; cổng không gán được → không hiện |
| Phiên kết thúc | Bỏ khỏi `PortWatcher`; tab đã thoát (mã ≠ 0) giữ giá trị cuối, mờ theo A1 |
| Cửa sổ ẩn | `watchPorts(false)`: huỷ hẹn giờ; giá trị cũ giữ nguyên; hiện lại → quét ngay |
| Mở `http://localhost:PORT` thất bại | Toast lỗi "Không mở được trình duyệt." |
| Xoá workspace đang chứa tab đang chọn | Tab về Mặc định, vẫn được chọn, Mặc định mở rộng |
| Thu gọn workspace chứa tab đang chọn | Terminal vẫn hiện tab đó; tiêu đề nhóm có dấu "đang chứa tab chọn"; ⌘1–9/Ctrl+Tab bỏ qua tab ẩn |
| Settings `terminal_workspaces` hỏng (JSON sai, id trùng, thiếu Mặc định) | Bỏ mục hỏng, thêm lại Mặc định ở đầu; không ném |
| Đổi tên thành chuỗi chỉ có khoảng trắng | Coi như rỗng: tab về tên tự động; workspace giữ tên cũ |
| Kéo tab rồi phiên kết thúc giữa chừng | Thả không làm gì |

---

## 6. Kiểm thử

- **`shellx_agent`** (`dart test`):
  - `osc_event_parser_test`: OSC 7 với BEL/ST, cắt giữa chunk, payload > 4 KiB bị bỏ.
  - `cwd_url_test`: percent-decode UTF-8 (`%C3%A1`), khoảng trắng, host rỗng/localhost/tên máy/host lạ, Windows ổ đĩa và UNC, không phải `file:`.
  - `git_head_test` (thư mục tạm thật): repo thường, thư mục con sâu, HEAD tách rời, worktree (`gitdir:` tuyệt đối), submodule (`gitdir:` tương đối), không phải repo, không có quyền (POSIX `chmod 000`), cache + `refresh`, timeout với `FileSystem` chậm giả.
  - `listening_ports_test`: parser lsof (có dòng `f`, IPv6 `[::1]:8080`, `*:3000`), ps, netstat (IPv4/IPv6, bỏ ESTABLISHED, dòng tiêu đề bản địa hoá), CIM; gán PID theo cây (lồng nhau, vòng lặp, cha chết); `PortWatcher` với `fake_async`: không quét khi tắt/không phiên, 3 s sau khi xong, lùi khi chậm, D6, chỉ gọi `parents()` khi có PID mới.
  - `session_context_test` (`SessionRig` + `FakePty`): OSC 7 → `cwd` trong `SessionSummary` + `changes`; nhánh từ repo tạm; 133;D làm mới; kết quả cũ bị bỏ; `watchPorts`.
  - `session_router_test`: `desktop:true` có `cwd`/`branch`, `desktop:false` giống hệt A1.
  - `hook_cwd_test` (`@TestOn('mac-os || linux')`, zsh và bash thật như `hook_notifications_test`): `cd` sang thư mục có dấu cách và chữ có dấu → OSC 7 đúng.
  - `shell_hook_sync_test` (có sẵn) phải xanh sau khi sửa `term/shell/block.*`.
- **`shellx_core`**: `SessionInfo` round-trip có/không có `cwd`/`branch`; map không có khoá mới giống hệt A1.
- **`apps/desktop`** (`flutter test`): `context_line_test` (hàm thuần: `~`, Windows không phân biệt hoa thường, cắt giữa, bố trí ưu tiên); `sidebar_workspaces_test` (tạo/đổi tên/xoá/thu gọn, thành viên, thứ tự nhìn thấy, lưu/đọc settings hỏng); `terminal_tabs_test` (rename, ngữ cảnh theo `SessionSummary`); widget test sidebar (dòng ngữ cảnh, bấm cổng gọi `openLocalPort`, double-click đổi tên, menu, tiêu đề ẩn khi một nhóm, kéo thả giữa nhóm, bàn phím cây, ⌘⇧N); `url_opener_local_port_test` (`openLocalPort` chặn cổng 0/65536); `port_watch_test` (`watchPorts` theo cửa sổ).
- **Thử tay** (HANDOFF §12): macOS và Windows thật — cd/nhánh/cổng, worktree, `npm run dev` (Vite 5173), cửa sổ ẩn không quét, CPU 10 tab, workspace sau khi khởi động lại, kéo thả, VoiceOver/Narrator đọc dòng.

---

## 7. Ngoài phạm vi A2

UI mobile hiện cwd/nhánh (follow-up mobile; protocol đã sẵn); đẩy cập nhật cwd/nhánh cho điện thoại không cần `session.list`; gửi tên tab tuỳ chỉnh cho điện thoại; sidebar kéo rộng/hẹp; trạng thái git bẩn/ahead-behind; cổng UDP; cổng của tiến trình đã tách khỏi cây; split pane (**A3**); vòng sáng, badge, OSC 9/99/777 trên sidebar (**A4**); khôi phục tab, workspace và thành viên sau khởi động lại, daemon (**A5**); trình duyệt nhúng mở cổng ngay trong app (**A6**); CLI/socket API đặt tên/nhóm tab (**A7**); cwd/nhánh qua SSH (**A8**); phím tắt tuỳ biến (**A9**); nhiều cửa sổ.
