# A1 — Cửa sổ terminal trên desktop — Đặc tả thiết kế

- **Ngày:** 2026-10-06
- **Trạng thái:** Người dùng chọn Q1–Q3 trong brainstorming 2026-10-06 rồi giao toàn quyền (chạy qua đêm, merge thẳng `main`, được push). Các quyết định còn lại do controller chốt, ghi ở bảng §2 kèm cái giá nếu sai.
- **Lộ trình:** desktop phải đạt **đầy đủ tính năng cmux** (cmux.com). Thứ tự: A1 (tài liệu này) → A2 sidebar giàu thông tin (git branch, cwd, port, workspace) → A4 thông báo kiểu cmux (vòng sáng, badge, OSC 9/99/777) → A3 split pane → A5 khôi phục session + tách daemon → A6 trình duyệt nhúng → A7 CLI/socket API → A8 SSH/tmux → A9 skills, phím tắt tuỳ biến, file cấu hình.
- **Sửa spec v1 (`2026-09-25-shellx-v1-design.md`):** quyết định D2 ("máy tính không hiển thị terminal") và §3.2 "Hiển thị/mirror terminal trên desktop" ngoài phạm vi — **thay bằng tài liệu này**. §8.3 "tắt truy cập từ xa đóng mọi phiên" — **đổi**: chỉ ngắt điện thoại, phiên vẫn chạy (D7).

---

## 1. Mục tiêu

ShellX desktop trở thành terminal chính trên máy tính: một cửa sổ có **sidebar tab dọc** bên trái và terminal bên phải. Mỗi tab là một phiên shell do agent giữ; **cùng phiên đó hiện trên điện thoại** (mở từ desktop hay từ điện thoại đều thấy ở cả hai nơi). Đóng cửa sổ không giết shell.

### Tiêu chí thành công

1. Mở ShellX (Dock/Finder/Start menu, hoặc lần chạy thứ hai) → cửa sổ terminal hiện với ít nhất một tab shell đăng nhập (zsh `-l` trên macOS) ở thư mục home, gõ được ngay; `vim`, `htop`, Claude Code chạy đúng (phím, màu 256/truecolor, resize).
2. ⌘T mở tab mới; ⌘W đóng tab; ⌘1…⌘9 chọn tab; ⌃Tab/⌃⇧Tab chuyển tab; ⌘C/⌘V sao chép/dán; ⌘+/⌘−/⌘0 cỡ chữ. (Windows: Ctrl+Shift+T/W, Ctrl+Shift+C/V, Ctrl+Tab.)
3. Tab mở trên desktop xuất hiện trong danh sách phiên của điện thoại trong vòng 2 giây; gõ trên điện thoại hiện trên desktop và ngược lại, cùng lúc, không ai bị "đá" ra.
4. Phiên điện thoại mở cũng hiện thành tab trên desktop (biểu tượng 📱).
5. Đóng cửa sổ (nút đỏ / Ctrl+W cửa sổ) → shell vẫn chạy, điện thoại vẫn dùng được; mở lại cửa sổ → các tab còn nguyên, nội dung gần nhất (≤ 256 KiB mỗi phiên) hiện lại.
6. Đăng xuất hoặc tắt "Cho phép truy cập từ xa" → điện thoại bị ngắt, **shell vẫn chạy** trong cửa sổ. Cửa sổ terminal dùng được cả khi chưa đăng nhập.
7. ⌘Q / "Thoát" ở tray → hỏi xác nhận nếu còn phiên → đóng mọi shell (cây tiến trình) rồi thoát, như hiện nay.
8. Output nặng (`cat` file 50 MB, `yes | head -n 2000000`) không làm treo UI quá 1 giây và không làm agent dùng quá 256 KiB bộ đệm mỗi phiên.

---

## 2. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| D1 | Nền tảng (Q1, người dùng) | Flutter, macOS + Windows, một codebase | Hiệu năng render thua bản native; đo ở D12 |
| D2 | Nơi giữ shell (Q2 người dùng chọn daemon riêng) | **A1: shell nằm trong tiến trình agent hiện có** (luôn chạy ở tray, tự khởi động khi đăng nhập máy). Một API phiên cục bộ (`LocalSessions`) ngăn UI với quản lý phiên, để A5 tách thành daemon riêng mà không đổi UI. Lý do: `flutter_pty` là plugin Flutter, daemon Dart thuần chưa dùng được; không kịp trong một đêm | Crash native hoặc cập nhật app vẫn mất shell (như hiện nay) cho tới A5 |
| D3 | Hợp nhất phiên (Q3, người dùng) | Mọi phiên là `SessionKind.shellx` trong cùng `SessionManager`; hiện ở cả desktop lẫn điện thoại. Không đổi protocol bắt buộc; `proto` giữ nguyên | — |
| D4 | Ai được đóng phiên | Desktop đóng được mọi phiên. Điện thoại chỉ **kết thúc** được phiên do điện thoại mở; với phiên mở từ desktop, `session.close` của điện thoại = **tách** (detach), shell vẫn chạy (theo nguyên tắc "điện thoại không bao giờ tắt terminal của máy tính") | Người dùng muốn tắt từ điện thoại phải làm trên máy |
| D5 | Nhiều người xem | Cửa sổ desktop là **người xem cục bộ** tách khỏi "điện thoại đang gắn" (vẫn tối đa một điện thoại/phiên như v1). Điện thoại gắn vào không đá desktop ra và ngược lại. Cả hai đều gõ được | — |
| D6 | Kích thước (bên vừa dùng thắng) | Mỗi phiên có `driver` (desktop/phone) như terminal chia sẻ: phím hoặc resize cục bộ → desktop lái, PTY theo cỡ cửa sổ, gửi `session.driver{desktop}` cho điện thoại (chỉ điện thoại đã `session.list{desktop:true}`); điện thoại gắn/gõ/resize → điện thoại lái, desktop hiện dải "Điện thoại đang dùng terminal này — gõ để dùng lại". Điện thoại rời → PTY về cỡ cửa sổ | Dòng cuộn trên desktop có thể theo bề rộng điện thoại khi điện thoại lái |
| D7 | Vòng đời phiên tách khỏi relay | `SessionManager` được tạo **một lần khi app khởi động**, không còn nằm trong `CoreAgentRuntime`. Dừng runtime (đăng xuất, tắt truy cập từ xa, mất mạng) chỉ ngắt các điện thoại; chỉ **Thoát** mới đóng mọi phiên | Phiên bị bỏ quên chạy mãi tới khi thoát app (v1 cũng không tự đóng phiên bỏ rơi) |
| D8 | Giới hạn phiên | Tăng từ 10 lên **32** phiên mỗi máy (desktop mở nhiều tab). `session_limit` giữ nguyên ý nghĩa | Tốn RAM hơn (32 × 256 KiB bộ đệm) |
| D9 | Cửa sổ | Một cửa sổ chính, đổi cỡ được, nhớ vị trí/cỡ. Đóng = ẩn. Các trang cũ (đăng nhập, ghép nối, đổi mật khẩu, xác nhận) hiện thành **hộp thoại trên cửa sổ terminal** thay vì cửa sổ cỡ cố định. Nhiều cửa sổ: để sau | — |
| D10 | Dock/Taskbar | macOS: app vẫn `LSUIElement`, nhưng khi cửa sổ hiện thì chuyển `NSApp.activationPolicy = .regular` (icon Dock, ⌘Tab, menu ứng dụng có ⌘Q), khi ẩn về `.accessory`. ⌘Q đi qua luồng "Thoát" của Dart (xác nhận, đóng shell). Windows: `setSkipTaskbar(false)` khi hiện | Windows chưa thử trên máy thật |
| D11 | Mở app | Mỗi lần khởi động và mỗi lần kích hoạt lại (Dock, lần chạy thứ hai) đều mở cửa sổ terminal; chưa có tab nào thì tự mở một tab. Chưa đăng nhập thì cửa sổ có dải "Đăng nhập để dùng từ điện thoại" | Lúc đăng nhập máy cũng bật cửa sổ (chấp nhận được cho một app terminal chính) |
| D12 | Engine render | `xterm` 4.0.0 (cùng bản mobile, ghim chính xác). Có một bài đo (benchmark) trong plan; nếu không đạt tiêu chí 8 thì ghi lại số đo, A1 vẫn phát hành, việc thay renderer thành dự án riêng | Phải làm renderer riêng sau |
| D13 | Tiêu đề tab | OSC 0/2 nếu shell đặt, nếu không `"<shell> <index>"` (như mobile). Agent theo dõi tiêu đề cho cả phiên shellx (trước đây chỉ phiên desktop) | — |
| D14 | Tab khi shell thoát | Mã thoát 0 → tab tự đóng. Khác 0 → tab giữ, hiện "[Tiến trình đã thoát, mã N] — Enter để đóng" | — |
| D15 | ⌘W khi đang chạy lệnh | Hỏi xác nhận nếu hook shell báo đang có lệnh chạy (OSC 133;C chưa có 133;D); không có hook thì đóng ngay | Có thể mất một lệnh đang chạy ở shell không có hook |
| D16 | Font / màu | JetBrains Mono (đóng gói như mobile, SIL OFL), bảng màu tối giống mobile, nền cửa sổ tối kiểu cmux | — |

---

## 3. Kiến trúc

```
apps/desktop (một tiến trình, tray + cửa sổ)
 ├─ main.dart ── tạo một SessionManager (shellx_agent) lúc khởi động
 │                 ├─ LocalSessions (API cục bộ, mới)  ◄── UI terminal (Riverpod)
 │                 └─ SessionRouter → AgentService → relay ◄── điện thoại
 └─ CoreAgentRuntime: nhận SessionManager từ ngoài; start/stop chỉ nối/ngắt relay
```

### 3.1 `packages/shellx_agent` — thay đổi

- `SessionManager`:
  - `maxSessions` mặc định 32 (D8).
  - Mỗi phiên có `origin` (`desktop` | `phone`), `title` (OSC 0/2 qua `OscTitleParser`, như phiên desktop), `driver` (D6), `runningCommand` (từ `CommandTracker` sẵn có: true giữa 133;C và 133;D).
  - `SessionSummary` thêm `origin`, `title`, `driver`, `runningCommand`, `phoneAttached`.
  - `session.close` từ điện thoại với phiên `origin == desktop` → tách điện thoại (gửi `session.detached{closed_by_host}` cho điện thoại đó), không kill (D4).
  - `SessionDriver` gửi cho điện thoại đang gắn khi driver đổi, **chỉ** nếu điện thoại đó đã `session.list{desktop:true}` (SessionRouter biết tập này; truyền vào dưới dạng `bool Function(String mobileId)`).
  - `disconnectAllPhones()`: gửi `session.detached` thích hợp và bỏ gắn mọi điện thoại, không kill (dùng khi runtime dừng — D7).
- **`LocalSessions`** (mới, `session/local_sessions.dart`), API trong tiến trình cho cửa sổ desktop:
  ```dart
  abstract interface class LocalSessions {
    List<SessionSummary> get sessions;
    Stream<void> get changes;
    Future<int> open({required int cols, required int rows}); // ném SessionLimitException / SpawnFailedException
    LocalSessionView view(int id);                             // ném StateError nếu không có
    void close(int id);                                        // kill cây tiến trình (desktop được đóng mọi phiên)
  }
  abstract interface class LocalSessionView {
    int get id;
    Uint8List get backlog;            // nội dung ring buffer hiện có (≤ 256 KiB)
    Stream<Uint8List> get output;     // output trực tiếp sau backlog
    Stream<DriverSide> get driver;    // đổi driver
    Future<int> get exitCode;
    void write(Uint8List data);       // → driver = desktop
    void resize(int cols, int rows);  // → driver = desktop
  }
  ```
  `SessionManager implements LocalSessions`. `backlog` + `output` không đi qua `SessionStream`/ack (người xem cục bộ không có flow control mạng); `output` là broadcast, mỗi `view()` là một người nghe.

### 3.2 `apps/desktop` — thay đổi

- **Khởi tạo:** `main.dart` tạo `SessionManager` (với `FlutterPtyFactory`, shell resolver, hook tích hợp shell, thông báo đẩy) một lần; `CoreAgentRuntime` nhận nó qua constructor. `CoreAgentRuntime.stop()` gọi `disconnectAllPhones()` thay vì `closeAll()`. Thoát app vẫn `closeAll()` + chờ kill cây tiến trình.
- **Provider:** `localSessionsProvider` (Riverpod) trả `LocalSessions`.
- **`TerminalTabs`** (Notifier): danh sách tab theo `sessions` (thứ tự tạo), tab đang chọn, mỗi tab một `xterm.Terminal` (maxLines 10 000) nạp `backlog` rồi `output`; `Terminal.onOutput` → `view.write`; `onResize` → `view.resize`. Tab mới từ điện thoại tự thêm (không tự chọn). Phiên kết thúc theo D14.
- **UI** (`ui/terminal/`):
  - `TerminalWorkspacePage`: `Row(Sidebar 220 px, VerticalDivider, TerminalPane)`.
  - `SessionSidebar`: mỗi dòng: chấm trạng thái, tiêu đề (1 dòng, ellipsis), 📱 nếu `origin == phone`, biểu tượng "điện thoại đang xem" nếu `phoneAttached`; nút `+` ở đầu; menu chuột phải "Đóng tab".
  - `TerminalPane`: `TerminalView` (theme tối, JetBrains Mono, cỡ chữ 13 mặc định, lưu trong settings) + dải driver (D6) + trạng thái thoát (D14).
  - Dải đăng nhập (D11) ở đầu cửa sổ khi chưa đăng nhập; nút mở hộp thoại đăng nhập.
- **Phím tắt:** `Shortcuts`/`Actions` cấp cửa sổ theo tiêu chí 2 (macOS ⌘, Windows Ctrl+Shift). ⌘C chỉ sao chép khi có vùng chọn, nếu không thì để xterm xử lý.
- **Cửa sổ (D9–D11):** bỏ cỡ cố định theo route; cửa sổ đổi cỡ được (tối thiểu 640×400, mặc định 1100×720), nhớ bounds trong settings. Các route cũ hiện bằng `showDialog` trên trang terminal. Kênh `pro.shellx.desktop/app` thêm `setDockVisible(bool)` (macOS: activation policy) và `quitRequested` (AppDelegate `applicationShouldTerminate` → `.terminateCancel` + gọi Dart, Dart chạy luồng Thoát). Tray thêm "Mở cửa sổ terminal" ở đầu menu.

### 3.3 Điện thoại

Không bắt buộc đổi app mobile: phiên mở từ desktop là phiên `shellx` bình thường trong danh sách. (Hiện dải driver cho phiên shellx trên mobile: để A2+.)

---

## 4. Luồng dữ liệu

- Gõ trên desktop: `TerminalView` → `Terminal.onOutput` → `LocalSessionView.write` → PTY. Output PTY → ring buffer (256 KiB) → (a) `output` broadcast tới cửa sổ, (b) `SessionStream` → relay → điện thoại đang gắn.
- Điện thoại gõ: relay → `SessionRouter` → `SessionManager` → PTY (driver = phone). Output như trên đi tới cả hai.

---

## 5. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Vượt 32 phiên | Tab mới không mở; thông báo nổi "Đã đạt tối đa 32 phiên" |
| Không mở được shell | Thông báo nổi kèm lý do loại lỗi; không tạo tab |
| Đóng cửa sổ khi còn phiên | Ẩn, không hỏi |
| Thoát khi còn phiên | Hỏi xác nhận (như tray hiện nay) rồi đóng mọi cây tiến trình |
| Runtime dừng / mất relay | Điện thoại bị ngắt; cửa sổ không đổi |
| Output vượt ring buffer khi cửa sổ ẩn | Mở lại chỉ thấy 256 KiB cuối (như điện thoại) |
| `TerminalView` nhận output khi tab không chọn | Vẫn ghi vào `Terminal` của tab đó |

---

## 6. Kiểm thử

- `shellx_agent`: `LocalSessions` (mở, backlog+output, write/resize đổi driver, close, giới hạn 32, exitCode), điện thoại + cửa sổ cùng một phiên (không ai bị đá), `session.close` từ điện thoại với phiên desktop = detach, `SessionDriver` chỉ gửi cho điện thoại đã opt-in, `disconnectAllPhones` không kill, tiêu đề OSC cho phiên shellx, `runningCommand`. Dùng `SessionRig`/`FakePty` sẵn có.
- `apps/desktop`: runtime stop không kill phiên; `TerminalTabs` với `LocalSessions` giả (tab theo phiên, D14, tab từ điện thoại); widget test trang terminal (sidebar, chọn tab, phím tắt mở/đóng tab, dải driver, dải đăng nhập); luồng cửa sổ (đóng = ẩn, route cũ thành hộp thoại, Thoát qua `quitRequested`); bài đo xterm (in số đo, không chặn).
- Thử tay (HANDOFF): macOS thật (Dock, ⌘Q, ⌘Tab, vim/htop/Claude Code, bộ gõ tiếng Việt, đồng thời với điện thoại); Windows thật.

---

## 7. Ngoài phạm vi A1

Workspace, git branch/cwd/port trên sidebar (A2); vòng sáng/badge thông báo (A4); split pane (A3); khôi phục sau khởi động lại và daemon tách tiến trình (A5); trình duyệt nhúng (A6); CLI/socket API (A7); SSH/tmux (A8); phím tắt tuỳ biến, file cấu hình, skills (A9); nhiều cửa sổ; đổi tên tab; tìm kiếm trong scrollback.
