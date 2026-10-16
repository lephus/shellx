# A5b — Daemon `shellx-mux`: shell sống sót khi giao diện thoát, crash, cập nhật — Đặc tả thiết kế

- **Ngày:** 2026-10-07
- **Trạng thái:** Người dùng đã chọn "daemon riêng `shellx-mux`" ở A1 Q2 (ledger A1: tạm để phiên trong tiến trình agent sau `LocalSessions`, tách daemon ở A5). Người dùng giao toàn quyền cho controller. Quyết định B1–B9 do controller chốt (ràng buộc); D1–D30 do người viết spec chốt trong phạm vi B1–B9. Tất cả ghi ở bảng §2 kèm cái giá nếu sai.
- **Thứ tự thực thi:** **sau khi A5a đã merge** (A5b dùng file bố cục A5a để gắn lại phiên, D18). Plan: `docs/superpowers/plans/2026-10-07-desktop-daemon-a5b.md`. UI addendum dùng chung: `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a5.md` (§6–§8).
- **Giữ nguyên:** spec A1–A4, A3, A5a. Protocol điện thoại (`shellx_core` `AppMessage`) và app mobile **không đổi**. Tài liệu này chỉ **thêm** và ghi rõ chỗ nào sửa.
- **Ký hiệu:** "A5a D8" = quyết định D8 của spec A5a; "B1"/"D1" không tiền tố = của tài liệu này. "UI" = tiến trình giao diện ShellX; "daemon" = tiến trình `shellx-mux`.

---

## 1. Mục tiêu

Shell **không chết** khi giao diện ShellX thoát (⌘Q), crash, bị kill hay được cập nhật: một tiến trình nền `shellx-mux` (chính binary ShellX chạy với `--daemon`, không cửa sổ) giữ `SessionManager`, các PTY và kết nối relay cho điện thoại. Mở lại ShellX → giao diện **gắn lại** vào đúng các shell đang chạy (vim vẫn mở, build vẫn chạy, nội dung gần nhất từ ring buffer), đúng bố cục A5a. "Thoát hoàn toàn" mới dừng daemon và mọi shell. Kênh nội bộ UI↔daemon là nền cho CLI/socket API của A7.

### Tiêu chí thành công (đo được)

1. **⌘Q giữ shell:** chạy `top` trong tab 1, `sleep 600; echo xong` trong pane 2 → ⌘Q (lần đầu: hộp giải thích, chọn "Thoát") → tiến trình UI biến mất (`pgrep -f 'ShellX$'`), `shellx-mux` còn (`pgrep -f -- '--daemon'`) → mở lại ShellX → trong ≤ 1,5 s cùng bố cục, tab 1 vẫn là `top` đang chạy, pane 2 vẫn đang `sleep`, gõ được ngay. Điện thoại đã ghép **không bị ngắt** trong suốt quá trình (relay ở daemon).
2. **Crash UI:** `kill -9 <pid UI>` → điện thoại không bị ngắt; mở lại ShellX → như tiêu chí 1, không có dải "đóng bất thường" của A5a (không mất gì).
3. **Daemon chết:** `kill -9 <pid daemon>` khi UI đang mở → trong ≤ 3 s dải "Phiên nền đã dừng bất ngờ và đã được khởi động lại…" hiện; các tab được mở lại theo A5a (shell mới ở cwd cũ, nội dung cũ phía trên vạch). Không có hộp thoại chặn.
4. **Thoát hoàn toàn:** tray → "Thoát hoàn toàn" (hoặc ⌘⌥Q trên macOS) → hỏi xác nhận nếu còn phiên (chữ A1) → mọi cây tiến trình shell bị kill, daemon thoát, UI thoát; `pgrep` không còn gì trong ≤ 4 s. Mở lại → khôi phục A5a (shell mới).
5. **Cập nhật:** cài bản mới khi đang có phiên (macOS: thay ShellX.app; Windows: chạy Setup) → shell vẫn sống; mở bản mới: daemon cũ cùng `protocol` → gắn lại bình thường; khác `protocol` → hộp "Phiên nền đang chạy bản cũ" với hai lựa chọn (UI-A5 §7.3), không bao giờ gắn vào daemon không tương thích.
6. **Bảo mật kênh:** một tài khoản khác trên cùng máy không mở được socket/pipe (macOS `ls -l` cho `srw-------`, thư mục `drwx------`; Windows ACL chỉ người dùng); một tiến trình cùng tài khoản không có token bị đóng kết nối sau bước `auth` sai (test); khung > 64 KiB hoặc CBOR lồng > 8 bị đóng kết nối (test).
7. **Hiệu năng:** `yes | head -n 2000000` trong một tab: UI không treo quá 1 s (như A1 tiêu chí 8); bộ nhớ daemon không tăng quá 4 MiB cho mỗi view khi UI bị treo (SIGSTOP UI 30 s trong lúc `yes` chạy) — kiểm bằng test cửa sổ ack D11 và thử tay.
8. **Đăng nhập máy:** "Khởi động cùng máy" bật → đăng nhập → daemon chạy (điện thoại thấy máy online) và cửa sổ hiện như A1 D11.
9. **Không hồi quy:** mọi test A1–A5a xanh; bộ test hợp đồng `LocalSessions` chạy **cùng một bộ** cho `SessionManager` (trong tiến trình) và `RemoteLocalSessions` (qua kênh) và đều xanh.

---

## 2. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B1 | Daemon (controller) | Daemon = **chính binary app** chạy headless `--daemon`, giữ `SessionManager`/PTY/agent relay | — |
| B2 | Kênh (controller) | IPC cục bộ có xác thực: Unix domain socket trong app support quyền 0600 (macOS) / named pipe có ACL (Windows) + **file token ngẫu nhiên** | — |
| B3 | Protocol (controller) | `LocalSessions` qua giao thức khung (framed), message kiểu CBOR như `AppMessage` của `shellx_core` | — |
| B4 | Vòng đời (controller) | UI thoát/crash/cập nhật → shell vẫn chạy. "Thoát hoàn toàn" (tray, ⌘⌥Q) dừng daemon và shell | — |
| B5 | Đăng nhập máy (controller) | Khởi động cùng máy → daemon chạy (cách làm: D17) | — |
| B6 | Cập nhật (controller) | Cập nhật chỉ khởi động lại UI. Phiên bản: daemon chạy tới khi hết phiên hoặc người dùng thoát hoàn toàn; UI **từ chối** daemon không tương thích bằng hộp thoại rõ ràng (D7, D19) | — |
| B7 | Nền A7 (controller) | Thiết kế IPC để A7 (CLI/socket API) mở rộng được (D8, D9, D22) | — |
| B8 | Phạm vi daemon (controller) | Daemon sở hữu cả agent relay (điện thoại vẫn dùng được khi UI không chạy) | — |
| B9 | Thực hiện sau A5a (controller) | — | — |
| D1 | Chia vai | **Daemon:** `SessionCore` (`SessionManager`, thông báo đẩy), `AgentController` (đăng nhập, relay runtime, ghép nối, thiết bị tin cậy/Keychain, chia sẻ terminal `TermServer`, giữ máy thức, phát hiện thức dậy, kiểm tra cập nhật), khởi động cùng máy. **UI:** cửa sổ, tray, xterm, `TerminalTabs`, workspace, pane, `TabAttention` + thông báo hệ thống A4 + badge Dock/taskbar, khôi phục A5a, hộp thoại. UI **không** chạm Keychain/DPAPI, không mở relay | Một lỗi trong daemon (vd. relay) giờ là lỗi "phiên nền" — xử lý ở D15 |
| D2 | macOS: chạy headless | Cùng file `ShellX.app/Contents/MacOS/ShellX`. `AppDelegate` đọc `CommandLine.arguments` **trước mọi thứ**; `--daemon` → `NSApp.setActivationPolicy(.prohibited)` (không Dock, không menu, không ⌘Tab), `MainFlutterWindow.awakeFromNib` **không** tạo `FlutterViewController` (cửa sổ nib không bao giờ hiện), tạo `FlutterEngine(name: "shellx-mux", project: nil, allowHeadlessExecution: true)` chạy entrypoint Dart `daemonMain`, đăng ký **danh sách plugin tường minh** (secure storage, shared_preferences, path_provider, package_info, local_notifier, kênh `launch_at_startup`) — không `window_manager`, `tray_manager`, `screen_retriever`. `flutter_pty` là plugin FFI, không cần đăng ký. **Rủi ro:** LaunchServices có thể coi daemon là "ShellX đang chạy" và gửi sự kiện mở lại (Finder/Dock) cho daemon thay vì mở UI → daemon xử lý `applicationShouldHandleReopen`/`application(_:open:)` bằng cách mở UI (`NSWorkspace.openApplication(at: Bundle.main.bundleURL, configuration: createsNewApplicationInstance = true)`). Plan Task 1 là **spike có kiểm tay** chốt cách này | Nếu cả cách chuyển tiếp cũng không ổn, phương án dự phòng (ghi ở plan Task 1): bundle phụ `ShellX.app/Contents/Helpers/ShellX Mux.app` (`LSBackgroundOnly`, bundle id `pro.shellx.desktop.mux`) dùng chung `App.framework`/`FlutterMacOS.framework` qua rpath — tốn 1–2 ngày ký/notarize |
| D3 | Windows: chạy headless | UI chép bộ chạy (`ShellX.exe`, mọi `.dll`, thư mục `data\`) sang `%LOCALAPPDATA%\ShellX\mux\<version>\` (chép vào thư mục tạm rồi đổi tên, bỏ qua nếu đã có và cùng cỡ) và chạy **`shellx-mux.exe --daemon`** (bản chép đổi tên của chính `ShellX.exe`) từ đó, tách rời (`DETACHED_PROCESS \| CREATE_NEW_PROCESS_GROUP \| CREATE_BREAKAWAY_FROM_JOB`). Lý do: Windows khoá file exe/dll đang chạy — chạy từ bản chép thì trình cài đặt thay được `{app}` và `taskkill /IM ShellX.exe` chỉ trúng UI. `main.cpp` với `--daemon`: `flutter::FlutterEngine` headless chạy `daemonMain`, đăng ký plugin tường minh (không `window_manager`, `tray_manager`, `screen_retriever`), vòng lặp message, không cửa sổ, không taskbar. Daemon khi khởi động xoá thư mục phiên bản cũ không còn dùng (xoá lỗi vì đang dùng → bỏ qua) | ~40 MB mỗi phiên bản trong LOCALAPPDATA tới khi daemon cũ thoát; chưa thử Windows thật |
| D4 | Kênh vận chuyển | **macOS:** UDS `<app support>/mux/mux.sock`; thư mục `mux/` 0700, socket chmod 0600 ngay sau bind (thư mục 0700 che khoảng hở). Đường dẫn > 103 byte (giới hạn `sun_path` 104) → `$TMPDIR/shellx-mux-<uid>.sock` (TMPDIR là thư mục riêng 0700 của người dùng). **Windows:** named pipe `\\.\pipe\shellx-mux-<16 hex đầu của SHA-256(SID người dùng)>`, tạo bằng FFI (`package:win32`): DACL chỉ SID người dùng (SDDL `D:P(A;;GA;;;<SID>)`), `PIPE_REJECT_REMOTE_CLIENTS`, thể hiện đầu có `FILE_FLAG_FIRST_PIPE_INSTANCE` (tên đã bị chiếm → daemon từ chối chạy, log). I/O chặn trên **một isolate phụ mỗi kết nối**, chuyển byte về isolate chính qua `SendPort`. Cả hai sau interface `MuxTransport` (listen/connect → `MuxConnection` = `Stream<Uint8List>` + `add` + `close`) | Named pipe chưa thử máy thật. Dự phòng ghi sẵn: loopback TCP + bắt tay token y như link `shellx-term` (A1 term spec §6) — chỉ đổi lớp vận chuyển, ghi ledger |
| D5 | Endpoint + token | File `mux/endpoint` (ghi nguyên tử, 0700/0600 như `EndpointFile`): `v=1`, `address=<đường dẫn socket hoặc tên pipe>`, `secret=<64 hex>`, `pid=`, `instance=<32 hex>`, `protocol=<n>`, `app=<x.y.z>`. Secret và instance **mới mỗi lần daemon khởi động**. Daemon xoá file khi thoát (chỉ nếu còn là của nó, như `deleteIfOwned`). Windows: `%LOCALAPPDATA%\ShellX\mux\endpoint` | — |
| D6 | Khung + bắt tay | Khung = 4 byte độ dài big-endian + một map CBOR; tối đa **64 KiB** (dùng lại `termFrame`/`TermFrameReader`); CBOR qua `encodeCbor`/`decodeCbor` (giới hạn lồng 8). Bắt tay xác thực **hai chiều** như link term: client gửi `hello{nonce}` → daemon `hello{nonce, proof = HMAC(secret, "shellx-mux/daemon" ‖ nonceClient ‖ nonceDaemon), …}` → client kiểm proof (sai → đóng, không gửi gì thêm) → `auth{proof = HMAC(secret, "shellx-mux/client" ‖ nonceDaemon ‖ nonceClient)}` → daemon `ready` hoặc đóng. Hết 2 s chưa xong → đóng. Dùng lại `hmacSha256` | — |
| D7 | Phiên bản | Phần **đóng băng vĩnh viễn**: khung, `hello`, `auth`, `ready`, `daemon.status`, `daemon.quit`. `hello` hai chiều mang `protocol` (int, A5b = 1), `app`, `role`; daemon thêm `instance`, `pid`, `sessions` (số phiên), `caps` (danh sách chuỗi). **Tương thích ⇔ `protocol` bằng nhau.** Thay đổi thêm vào (message mới, khoá mới) **không** tăng `protocol`: bên nhận bỏ qua khoá lạ, event lạ; request lạ → `error{unknown_type}`; tính năng mới báo qua `caps`. Chỉ thay đổi phá vỡ mới tăng `protocol` | Một thay đổi phá vỡ quên tăng số → lỗi khó hiểu; test "khung vàng" (golden bytes) cho phần đóng băng chặn |
| D8 | Vai trò client | `role: "ui"` — **một** UI tại một thời điểm (UI thứ hai → `error{busy}` rồi đóng; khoá một thể hiện của UI làm việc này hiếm). `role: "cli"` dành cho A7: A5b trả `error{unsupported_role}` | — |
| D9 | Không gian tên | `sessions.*` (danh sách, mở, đóng, notice, watchPorts), `view.*` (một người xem), `agent.*` (trạng thái + lệnh agent), `daemon.*` (status, quit). **Dành sẵn cho A7:** `ui.*` (daemon chuyển tiếp tới UI đang gắn — vd. A7 `shellx new-split` → daemon → UI), `cli.*`. Message: `{"t": loại, "q": id yêu cầu (tuỳ chọn), …}`; trả lời `{"t": "result", "q", …}` hoặc `{"t": "error", "q", "code", "message"}`. Mã lỗi: `unknown_type`, `bad_request`, `not_found`, `busy`, `unsupported_role`, `session_limit`, `spawn_failed`, `internal` | — |
| D10 | `LocalSessions` từ xa | `RemoteLocalSessions implements LocalSessions`: daemon **không gửi gì trước request đầu tiên** của client (client chỉ nghe sau khi bắt tay xong); danh sách đầu lấy bằng request `sessions.list`, sau đó `sessions` là bản sao cập nhật bằng event `sessions.changed{sessions: […]}` (cả danh sách, gộp ≤ 1 lần / 16 ms); `open` → request (lỗi `session_limit`/`spawn_failed` thành `SessionLimitException`/`SpawnFailedException`); `close`, `watchPorts` gửi một chiều; `notices` ← `sessions.notice`. `view(id)` trả ngay `RemoteSessionView` và gửi `view.open{id}`; daemon trả `view.out` (backlog trước, chia ≤ 60 KiB) rồi output trực tiếp, `view.driver`, `view.exit{code, onRequest}`. **Sửa hợp đồng `LocalSessionView.backlog`:** "có thể rỗng; khi đó backlog đến **đầu tiên** trong `output`" — `TerminalTabs` vốn ghi `backlog` rồi `output` vào cùng `TerminalFeed` nên không đổi hành vi. `write`/`reply`/`resize`/`dispose` một chiều. `view(id)` của phiên không còn → `view.exit` ngay với `code: -1, onRequest: true` (thay cho `StateError` đồng bộ — `_attach` đã xử lý phiên kết thúc) | — |
| D11 | Kiểm soát luồng | Mỗi view: daemon đếm byte đã gửi − byte UI đã báo (`view.ack{id, bytes}`, UI gửi sau khi `TerminalFeed` nhận, gộp ≥ 64 KiB hoặc 100 ms). Đang treo > **2 MiB** → daemon **ngừng** gửi view đó; khi xuống < 512 KiB → `view.reset{data: ring buffer hiện tại}` rồi tiếp tục. UI nhận `reset`: ghi `\r\n` + xoá màn hình (không xoá scrollback) + dữ liệu. Ring buffer phiên (A1, 256 KiB) không đổi | UI treo lâu thấy một bước nhảy (màn hình vẽ lại từ 256 KiB cuối) — giống điện thoại `session.reset` |
| D12 | Agent tách đôi | `abstract class AgentControllerBase extends Notifier<AgentViewState>` khai báo mọi lệnh công khai hiện có. Daemon: `AgentController extends AgentControllerBase` (mã hiện tại, đổi chữ ký các hàm trả đồng bộ thành `Future`). UI: `RemoteAgentController extends AgentControllerBase` — `state` = lấy lần đầu bằng request `agent.get`, sau đó theo event `agent.state` (cả trạng thái, mã hoá CBOR, gửi mỗi lần đổi, gộp 16 ms), lệnh = request `agent.call{m: tên, a: map}`. `agentControllerProvider` có kiểu `NotifierProvider<AgentControllerBase, AgentViewState>`; UI override bằng `RemoteAgentController.new` | Thêm lệnh agent về sau phải thêm vào cả hai lớp + bảng mã hoá (test bao phủ: mỗi tên lệnh có một test khứ hồi) |
| D13 | Settings hai tiến trình | `shared_preferences` cache trong từng tiến trình → **mỗi khoá chỉ một tiến trình ghi và đọc**. Daemon: `remote_access_enabled`, `keep_awake_enabled`, `launch_at_startup_enabled`, `onboarding_done`, `terminal_sharing_*`, `command_notify_threshold_seconds`, `desktop_notifications_*` (UI đọc qua `AgentViewState`). UI: `terminal_font_size`, `window_*`, `terminal_workspaces`, `terminal_restore_scrollback`, `quit_keeps_sessions_explained` (mới). Test liệt kê `SettingKeys.all` = hợp rời của `DaemonSettingKeys` và `UiSettingKeys` | — |
| D14 | Hai kiểu thoát (B4) | **"Thoát" (⌘Q, tray "Thoát", menu app Quit):** chỉ thoát UI — A5a `flushAll(clean: true)`, ngắt kết nối, `exit(0)`; **không hỏi** xác nhận (không mất gì). Lần **đầu tiên** có phiên đang chạy: hộp giải thích một lần (UI-A5 §7.1, khoá `quit_keeps_sessions_explained`). **"Thoát hoàn toàn"** (tray, ⌘⌥Q trên macOS — mục menu app; Windows chỉ tray): hỏi xác nhận nếu còn phiên (chữ A1 `confirmQuit*`), A5a `flushAll(clean: true)`, `daemon.quit` (daemon: `AgentController.shutdown()` + `closeAll()` + chờ kill cây ≤ 3 s, trả lời, thoát), rồi UI `exit(0)`. Tắt máy/đăng xuất: cả hai tiến trình kết thúc; A5a lo phần khôi phục | Người quen A1 (⌘Q đóng mọi shell) thấy shell còn chạy — hộp giải thích lần đầu bù lại |
| D15 | Daemon chết khi UI đang mở | UI thấy kết nối đứt (không phải do `daemon.quit` của chính nó): **không** viết dòng thoát vào các tab, giữ nguyên màn hình, thử khởi động daemon mới (D16) **một lần ngay**, rồi khôi phục A5a ở chế độ mở lại (A5a D7) từ bản lưu cuối (UI vừa `flushAll(clean: false)` trước khi khởi động lại — nội dung xterm còn trong bộ nhớ UI nên **không mất** gì ngoài tiến trình). Dải UI-A5 §7.4. Thất bại → dải lỗi có nút "Thử lại" | Trong ≤ 3 s gõ phím bị bỏ (UI không có phiên để gửi) |
| D16 | Khởi động daemon | UI khi mở: đọc `endpoint` → kết nối + bắt tay (1 s). Thất bại (không file, không kết nối được, proof sai) → kiểm khoá `mux/mux.lock` (khoá tự do = không daemon) → chạy daemon tách rời → thử kết nối lại mỗi 100 ms tới **5 s**. Vẫn thất bại → hộp "Không khởi động được phiên nền" (Thử lại / Thoát). Daemon giữ khoá `mux.lock` suốt đời (hệ điều hành nhả khi crash); daemon thứ hai không lấy được khoá → thoát 0. Khoá một thể hiện của UI (`shellx.lock`, A1) giữ nguyên ý nghĩa cho UI | — |
| D17 | Khởi động cùng máy (B5) | Giữ cơ chế hiện tại (macOS `SMAppService.mainApp` / LaunchAgent macOS 12; Windows khoá `Run` "ShellX") mở **UI**; bước đầu tiên của UI là D16 nên daemon chạy ngay sau đăng nhập. **Không** thêm launchd agent/khoá Run riêng cho daemon (một mục "Login item" duy nhất người dùng thấy; không có launchd tự bật lại sau "Thoát hoàn toàn"). Công tắc do daemon ghi (D13) nhưng gọi API hệ điều hành ở daemon (kênh `launch_at_startup` được đăng ký trên engine headless) | UI hỏng lúc đăng nhập thì daemon không chạy tới khi mở app |
| D18 | Gắn lại (A5a) | Bố cục A5a ghi `daemon: <instance>` và `session` mỗi lá. Khi UI mở: `hello.instance == layout.daemon` → **chế độ gắn lại**: dựng tab/pane từ bố cục với **id phiên sống** (không `open`, không nội dung đã lưu, không vạch — backlog từ ring buffer); lá có phiên không còn → gỡ khỏi cây (A3 D7); phiên trong daemon không có trong bố cục (điện thoại mở lúc UI đóng, hay mở từ A7) → tab mới vào Mặc định (A1). Khác instance (khởi động lại máy, thoát hoàn toàn, daemon chết) → chế độ mở lại A5a. A5a D12 (`cleanExit`) chỉ xét ở chế độ mở lại | — |
| D19 | Daemon không tương thích | `protocol` khác: daemon có **0 phiên** → UI gửi `daemon.quit` không hỏi, chờ daemon thoát (≤ 4 s), khởi động daemon mới. Có phiên → hộp UI-A5 §7.3 "Phiên nền đang chạy bản cũ ({n} phiên)": **"Khởi động lại phiên nền"** (= `daemon.quit` + daemon mới + khôi phục A5a ở chế độ mở lại từ bản lưu cuối của UI cũ) hoặc **"Để sau"** (UI thoát; shell và điện thoại vẫn chạy với daemon cũ; lần mở sau hỏi lại). Không bao giờ gắn vào daemon khác `protocol` | Người chọn "Để sau" không dùng được cửa sổ tới khi khởi động lại phiên nền |
| D20 | Cập nhật macOS | Thay `ShellX.app` khi daemon cũ đang chạy: daemon giữ inode cũ (file đã mở/ánh xạ), tiếp tục chạy. Kiểm tay bắt buộc (Finder "Replace", DMG mới, `ditto`) | Nếu một tài nguyên được nạp lười sau khi thay, daemon cũ có thể crash → D15 trên UI mới |
| D21 | Cập nhật/gỡ Windows | `shellx.iss` `PrepareToInstall`: `taskkill /F /IM ShellX.exe` **bỏ `/T`** (cây của UI có thể chứa daemon theo `ppid`). Gỡ cài đặt: `taskkill /F /T /IM shellx-mux.exe` rồi `/IM ShellX.exe`; xoá `%LOCALAPPDATA%\ShellX\mux` và `\restore`. Test `release/tests/inno.test.mjs` cập nhật | — |
| D22 | Nền A7 (B7) | A7 thêm `role: "cli"`, các request `sessions.*` dùng lại nguyên, request `ui.*` daemon chuyển tới UI (UI trả lời; không có UI → `error{not_found}`), không cần tăng `protocol`. Endpoint + token là cách CLI tìm và xác thực (CLI cùng người dùng đọc được file 0600) | — |
| D23 | Bảo mật | Ranh giới tin cậy = **cùng tài khoản** (như cmux socket, tmux). Tài khoản khác: chặn bằng 0700/0600/ACL. Máy khác: UDS cục bộ; `PIPE_REJECT_REMOTE_CLIENTS`. Chiếm tên pipe trước: `FILE_FLAG_FIRST_PIPE_INSTANCE` + proof hai chiều (kẻ chiếm không có secret). Chống lạm dụng: khung ≤ 64 KiB, CBOR ≤ 8 lớp, ≤ 4 kết nối đang bắt tay, bắt tay ≤ 2 s, một UI. Không log nội dung message (chỉ loại, mã lỗi, `runtimeType`) | Mã độc cùng tài khoản điều khiển được shell (nó vốn đã làm được mọi thứ với tài khoản đó) |
| D24 | Thông báo của daemon | Thông báo của agent (đăng nhập lỗi, điện thoại bị thu hồi, chia sẻ terminal lỗi, kill cây tiến trình lỗi) do daemon hiện bằng `LocalSystemNotifier` (cùng bundle id / AppUserModelID "ShellX"). Thông báo tab A4 vẫn ở UI | Windows: toast từ tiến trình không cửa sổ cần AUMID đúng — kiểm tay |
| D25 | Tray khi không có UI | Không có biểu tượng tray khi UI đã thoát (tray thuộc UI). Mở ShellX để thấy lại | Người dùng không thấy daemon đang chạy — hộp giải thích D14 nói rõ |
| D26 | Lỗi trên kênh | Message sai dạng → `error{bad_request}` (request) hoặc bỏ qua (event); khung quá lớn/CBOR hỏng → đóng kết nối. UI mất kết nối → D15. Daemon mất UI → không làm gì (shell chạy tiếp) | — |
| D27 | Nghỉ của daemon | Daemon tự thoát khi **đồng thời**: không có UI ≥ 10 s, **không** phiên nào, và **không** phục vụ điện thoại (chưa đăng nhập hoặc tắt truy cập từ xa). Đăng nhập + bật truy cập từ xa → daemon chạy mãi như agent tray trước A5b | Máy có daemon chạy nền vô hình khi người dùng chỉ ⌘Q (đúng ý: điện thoại vẫn vào được) |
| D28 | Kiểm thử chung | Bộ test hợp đồng `local_sessions_contract.dart` (trong `packages/shellx_agent/test/support/`) chạy cho `SessionManager` và `RemoteLocalSessions` + `MuxServer` qua `MemoryMuxTransport` (cặp ống trong bộ nhớ) | — |
| D29 | Điện thoại | Không đổi gì: relay ở daemon, protocol điện thoại giữ nguyên, ring buffer giữ nguyên | — |
| D30 | Log | Daemon headless không có console: `debugPrint` vô hại; **không** thêm file log trong A5b (follow-up nếu cần chẩn đoán) | Khó chẩn đoán lỗi daemon ở máy người dùng |

**Sửa A1:** D2 (shell trong tiến trình agent) → trong daemon. D7 "chỉ Thoát mới đóng mọi phiên" → chỉ **Thoát hoàn toàn**. D10 "⌘Q đi qua luồng Thoát (xác nhận, đóng shell)" → ⌘Q chỉ thoát UI (D14). Tiêu chí 7 → "Thoát hoàn toàn".
**Sửa A5a:** D21 nay được dùng (D18). D12 chỉ xét ở chế độ mở lại.
**Sửa `LocalSessions`:** hợp đồng `backlog` (D10); `view()` của phiên không còn có thể trả view đã kết thúc thay vì ném `StateError` (cả hai hiện thực đều hợp lệ; `TerminalTabs` xử lý cả hai).

---

## 3. Kiến trúc

```
ShellX (UI)                                              shellx-mux (ShellX --daemon, headless)
 ├─ TerminalTabs / PaneTreeView / TabAttention            ├─ DaemonHost: khoá mux.lock, endpoint, nghỉ (D27)
 ├─ RestorePersistence (A5a)                               ├─ MuxServer ── SessionManager (LocalSessions)
 ├─ RemoteLocalSessions ─┐                                 │             └─ AgentController (relay, Keychain, push, TermServer)
 ├─ RemoteAgentController┤  MuxClient                      └─ MuxTransport.listen (UDS / named pipe)
 ├─ DaemonLauncher (D16, D19)                                         ▲
 └─ tray, cửa sổ, thông báo A4      └── MuxTransport.connect ─────────┘  khung 4B + CBOR, HMAC hai chiều
```

### 3.1 `packages/shellx_agent/lib/src/mux/` (mới, Dart thuần, test được)

- `mux_messages.dart` — `MuxMessage` (giá trị: `type`, `q` tuỳ chọn, `fields`), hằng tên loại `MuxType.*`, `encodeMux`/`decodeMux` (CBOR, khoá lạ bỏ qua), mã hoá `SessionSummary`, `SessionNotice` (kể cả `CompletedCommand`), `DriverSide`. Một map mở thay vì một lớp mỗi loại: đúng tinh thần "bỏ qua khoá lạ" của D7 và để A7 thêm loại mà không đổi lớp.
- `mux_handshake.dart` — `daemonProof`, `clientProof`, `MuxHello`, máy trạng thái bắt tay hai phía (timeout 2 s).
- `mux_endpoint.dart` — `MuxEndpoint` (đọc/ghi/xoá-nếu-của-mình) dùng lại logic `EndpointFile`.
- `mux_transport.dart` — `MuxTransport`, `MuxConnection`; `UnixMuxTransport` (dart:io `InternetAddressType.unix`); `MemoryMuxTransport` (test); `windows_pipe_transport.dart` (FFI, chỉ biên dịch/dùng trên Windows qua import có điều kiện).
- `mux_server.dart` — `MuxServer(LocalSessions sessions, {AgentBridge? agent, …})`: mỗi kết nối một `_ClientLink`: bắt tay → vai trò → phục vụ `sessions.*`/`view.*` (cửa sổ ack D11), chuyển tiếp `agent.*` cho `AgentBridge` (interface: `Stream<Map> states`, `Future<Object?> call(String m, Map a)`), `daemon.status`/`daemon.quit` (callback).
- `remote_local_sessions.dart` — `MuxClient` (kết nối + bắt tay + request/response theo `q` + event), `RemoteLocalSessions`, `RemoteSessionView`.

### 3.2 `apps/desktop`

- `lib/daemon_main.dart` — `@pragma('vm:entry-point') Future<void> daemonMain()`: khoá `mux.lock`, `SessionCore`, `DesktopServices` phía daemon, `ProviderContainer` chạy `AgentController`, `AgentBridge` từ container, `MuxServer`, `DaemonHost` (nghỉ, thoát).
- `lib/src/agent/agent_controller_base.dart` — `AgentControllerBase`; `agent_state_codec.dart` — `AgentViewState` ↔ map; `remote_agent_controller.dart`.
- `lib/src/mux/daemon_launcher.dart` — `DaemonLauncher.connect() → DaemonConnection` với kết quả `attached`, `started`, `incompatible(sessions)`, `failed`; `windows_runtime_copy.dart` (D3).
- `lib/main.dart` — UI: không còn tạo `SessionCore`/runtime; `DaemonLauncher` → override `localSessionsProvider`, `agentControllerProvider`; hai luồng thoát (D14); theo dõi mất kết nối (D15).
- Native: `macos/Runner/AppDelegate.swift`, `MainFlutterWindow.swift` (D2); `windows/runner/main.cpp` (+ `daemon_runner.cpp`) (D3).
- `release/windows/shellx.iss`, `release/tests/inno.test.mjs` (D21).

---

## 4. Luồng dữ liệu

```
Mở UI ─► DaemonLauncher: endpoint? ─► connect ─► hello/auth (HMAC 2 chiều) ─► protocol khớp?
            │ không có / lỗi ─► spawn --daemon ─► thử lại ≤ 5 s            │ không khớp ─► 0 phiên? quit+spawn : hộp §7.3
            └──────────────────────────────────────────────────────────────┴─► instance == layout.daemon ? gắn lại : mở lại (A5a)
Gõ phím ─► RemoteSessionView.write ─► view.write ─► MuxServer ─► LocalSessionView.write ─► PTY
PTY ─► ring buffer ─► (a) relay → điện thoại  (b) view.out ─► UI ─► TerminalFeed ─► view.ack
⌘Q ─► flushAll ─► đóng kết nối ─► exit(0)          (daemon: không UI ≥ 10 s ∧ 0 phiên ∧ không phục vụ điện thoại ─► thoát)
Thoát hoàn toàn ─► xác nhận ─► flushAll ─► daemon.quit ─► shutdown+closeAll ─► daemon exit ─► UI exit
```

---

## 5. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Daemon không khởi động được (thiếu quyền, binary hỏng) | Hộp "Không khởi động được phiên nền" — Thử lại / Thoát (D16) |
| Endpoint cũ (daemon đã chết, file còn) | Kết nối thất bại → khoá tự do → spawn (D16); daemon mới ghi đè file |
| Hai UI cùng mở (đua) | Khoá UI A1 chặn; nếu lọt, UI thứ hai nhận `busy` → kích hoạt UI kia rồi thoát |
| UI treo (debugger, SIGSTOP) | Cửa sổ ack D11 giới hạn bộ nhớ daemon; điện thoại không ảnh hưởng |
| Daemon crash | D15 |
| Socket path quá dài | `$TMPDIR` (D4) |
| Tên pipe bị chiếm (Windows) | Daemon từ chối chạy → UI hộp D16 (thông điệp chung, log ghi lý do) |
| Đổi giờ hệ thống, ngủ máy | Không ảnh hưởng kênh cục bộ; agent tự xử lý relay như trước |
| Đăng xuất macOS khi chỉ daemon chạy | Hệ điều hành kết thúc daemon; shell chết; lần sau A5a mở lại |
| `daemon.quit` khi đang có thao tác `open` dở | Daemon từ chối request mới sau `quit`, hoàn tất đóng, thoát |
| Điện thoại mở phiên khi không có UI | Phiên chạy trong daemon; UI mở sau thấy thành tab mới (D18) |
| Cập nhật macOS làm daemon cũ crash | UI mới thấy kết nối/endpoint hỏng → spawn daemon mới → A5a mở lại; dải D15 nếu UI đang mở |

---

## 6. Kiểm thử

- **`shellx_agent`:** `mux_messages_test` (khứ hồi mọi loại, khoá lạ, khung vàng cho phần đóng băng D7), `mux_handshake_test` (proof đúng/sai hai chiều, timeout, nonce lặp), `mux_endpoint_test` (quyền, nguyên tử, deleteIfOwned), `unix_mux_transport_test` (socket thật trong thư mục tạm, quyền 0600, đường dẫn dài → TMPDIR), `mux_server_test` (vai trò, busy, request lạ, ack/reset D11, view của phiên đã đóng), `local_sessions_contract_test` (D28 — chạy hai lần).
- **`apps/desktop`:** `agent_state_codec_test` (khứ hồi), `remote_agent_controller_test` (mỗi lệnh → `agent.call` đúng tên/tham số; lỗi → ném), `daemon_launcher_test` (các nhánh D16/D19 với transport + spawner giả), `daemon_host_test` (nghỉ D27, quit), `quit_flows_test` (D14: ⌘Q không hỏi, hộp lần đầu, Thoát hoàn toàn hỏi + `daemon.quit`), `daemon_lost_test` (D15: không viết dòng thoát, khôi phục), `settings_ownership_test` (D13), `windows_runtime_copy_test` (logic chép với file system giả).
- **Thử tay (HANDOFF §16, bắt buộc trước khi merge):** macOS và Windows thật — tiêu chí 1–8; Finder/Dock/Spotlight mở app khi chỉ daemon chạy (D2); thay app khi daemon chạy (D20); Setup Windows khi có phiên (D21); quyền socket/pipe (`ls -l`, PowerShell `Get-Acl \\.\pipe\…` qua `[System.IO.Directory]::GetAccessControl`); thông báo agent từ daemon (D24); điện thoại xuyên suốt.

---

## 7. Ngoài phạm vi A5b

CLI/socket API công khai (**A7** — A5b chỉ dành chỗ `cli`, `ui.*`); nhiều UI cùng gắn; daemon chuyển giao nóng sang bản mới (handoff PTY fd giữa tiến trình); daemon chạy dưới launchd/Service riêng; log file cho daemon; tray khi không có UI; Linux.
