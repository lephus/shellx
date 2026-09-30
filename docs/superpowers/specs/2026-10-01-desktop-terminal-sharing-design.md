# Chia sẻ terminal máy tính với điện thoại — Đặc tả thiết kế

- **Ngày:** 2026-10-01
- **Trạng thái:** Đã duyệt qua brainstorming từng phần (6/6); chờ người dùng đọc lại spec trước khi lập kế hoạch
- **Phạm vi:** chương trình mới `shellx-term` (Rust), agent desktop (macOS/Windows), giao thức điện thoại ↔ agent, app mobile, bộ cài và quy trình phát hành desktop. Relay **không đổi**.
- **Sửa đổi spec v1 (`2026-09-25-shellx-v1-design.md`):** D2 nói "Mọi phiên terminal do điện thoại mở". Tính năng này bổ sung một loại phiên thứ hai: terminal do người dùng tự mở trên máy tính, được chia sẻ sang điện thoại. Mục §3.2 "Hiển thị/mirror terminal trên desktop" (chiều ngược lại: xem phiên của điện thoại trên máy tính) vẫn ngoài phạm vi.

---

## 1. Mục tiêu

Khi rời máy tính, người dùng mở điện thoại và **xem tiếp, gõ tiếp** vào các cửa sổ terminal đang chạy sẵn trên máy (build, dev server, script dài) — không chỉ các phiên do ShellX mở từ điện thoại. Áp dụng cho **mọi ứng dụng terminal**, tự động cho **mọi cửa sổ terminal mới** sau khi bật một lần, trên **cả macOS và Windows**.

### Tiêu chí thành công

1. Sau khi bật, mở một cửa sổ mới trong Terminal.app, iTerm2 hoặc terminal của Cursor/VS Code (macOS): trong vòng 2 giây nó hiện trong danh sách phiên trên điện thoại, kèm tên ứng dụng và tiêu đề.
2. Gắn vào từ điện thoại: thấy output gần nhất (tối đa 256 KiB), **kể cả phần chạy trước khi agent khởi động hoặc trước khi gắn vào**.
3. Gõ lệnh từ điện thoại thì lệnh chạy trong đúng cửa sổ đó. Gõ phím trên máy tính thì terminal trở về kích thước cửa sổ.
4. Thoát, treo, cập nhật ShellX, hoặc xóa `shellx-term`: **không một cửa sổ terminal nào bị đóng, treo hay chậm đi** (có test cho từng trường hợp).
5. Mỗi cửa sổ terminal mở chậm thêm **dưới 50 ms** (trung vị, đo trên macOS).
6. App mobile cũ với agent mới, và app mobile mới với agent cũ, đều chạy như trước. Bên cũ chỉ không thấy terminal máy tính; app mobile mới gặp agent cũ thì hiện gợi ý cập nhật.
7. Windows: toàn bộ test tự động pass trên máy `windows-latest`. Kiểm tra tương tác trên Windows thật là việc chờ, và **chặn việc phát hành tính năng trên Windows** (§12).

---

## 2. Nhật ký quyết định

| # | Chủ đề | Quyết định |
|---|---|---|
| T1 | Đối tượng quan sát | Terminal người dùng tự mở trên máy tính, mọi ứng dụng terminal. Không phải lịch sử phiên ShellX đã kết thúc, không phải cửa sổ ứng dụng khác |
| T2 | Tương tác | Xem **và** gõ. Máy tính và điện thoại cùng điều khiển một terminal |
| T3 | Chia sẻ những terminal nào | Tự động mọi terminal mới sau khi bật công tắc (khối tích hợp trong file cấu hình shell), mặc định tắt |
| T4 | Nền tảng | macOS và Windows trong cùng một bản thiết kế. Chạy thử tương tác trên Windows để sau, và chặn phát hành trên Windows tới khi xong (§12) |
| T5 | Hướng kỹ thuật | **Hướng A:** mỗi terminal chạy shell bên trong chương trình bọc `shellx-term`. Loại bỏ hướng B (agent giữ shell, kiểu tmux: thoát ShellX là mất mọi terminal) và hướng C (tích hợp từng ứng dụng: không phủ được mọi terminal, không có đường cho Windows) |
| T6 | Ngôn ngữ của `shellx-term` | Rust + thư viện `portable-pty` (lấy từ WezTerm): khởi động vài ms, khoảng 2–3 MB RAM mỗi cửa sổ, một API PTY cho cả Unix lẫn ConPTY |
| T7 | Nguyên tắc số 1 | ShellX hỏng thì terminal vẫn chạy (§5.4) |
| T8 | Kết nối nội bộ | TCP chỉ trên `127.0.0.1` + khóa bí mật trong thư mục người dùng + xác thực hai chiều HMAC-SHA256. Cùng một cơ chế cho macOS và Windows |
| T9 | Kích thước terminal | Theo bên hoạt động gần nhất (như tmux) |
| T10 | Quyền của điện thoại | Không bao giờ tắt terminal máy tính. "Đóng" từ điện thoại chỉ là rời |
| T11 | Windows PowerShell 5.1 bị chặn script | ShellX phát hiện, giải thích, có nút đổi chính sách `CurrentUser` sang `RemoteSigned`; chỉ đổi khi người dùng bấm xác nhận |
| T12 | Kiểm chứng Windows | Workflow GitHub Actions chạy khi bấm tay trên `windows-latest` (không chạy theo push). Kiểm tra tương tác là việc chờ. Công tắc trên Windows chỉ hiện qua cờ ẩn |

---

## 3. Phạm vi

### 3.1 Trong phạm vi

- `shellx-term` cho macOS 12+ (universal: arm64 + x86_64) và Windows 10 1809+ (x64).
- Shell: zsh và bash trên macOS; PowerShell 7 và Windows PowerShell 5.1 trên Windows.
- Công tắc bật/tắt, cài/gỡ khối tích hợp, cài/cập nhật/gỡ `shellx-term`.
- Phiên loại `desktop` trong agent, mục menu và thông báo trên máy tính.
- Mở rộng giao thức điện thoại ↔ agent, tương thích hai chiều.
- Giao diện mobile: bảng chọn phiên, tab terminal máy tính, băng "Máy tính đang dùng", các trạng thái kết thúc.
- Kiểm thử tự động, workflow Windows bấm tay, danh sách kiểm tra tay theo ứng dụng terminal.

### 3.2 Ngoài phạm vi

- Terminal đã mở **trước** khi bật tính năng (chỉ terminal mở sau mới được bọc).
- cmd.exe, Git Bash, WSL, fish, nushell và các shell khác.
- Linux.
- Xem lại terminal sau khi cửa sổ đã đóng (lịch sử lâu dài).
- Nhiều điện thoại cùng xem một terminal cùng lúc (giữ quy tắc hiện có: một điện thoại mỗi phiên, điện thoại sau chiếm quyền).
- Chế độ chỉ xem (không cho gõ).
- Cửa sổ của ứng dụng không phải terminal.
- Tắt terminal máy tính từ điện thoại hoặc từ menu ShellX.

---

## 4. Kiến trúc

```
 Cửa sổ terminal (Terminal.app, iTerm2, Cursor, Windows Terminal…)
        │  bàn phím / màn hình (TTY hoặc console của cửa sổ)
        ▼
   shellx-term ──── PTY bên trong ────  zsh / bash / PowerShell
        │
        │  TCP 127.0.0.1, xác thực hai chiều (§6)
        ▼
   Agent ShellX (app desktop) ──── relay (E2E, không đổi) ──── điện thoại
```

| Thành phần | Nơi ở | Việc |
|---|---|---|
| `shellx-term` | `term/` (crate Cargo mới ở gốc repo) | Bọc một shell trong PTY, chuyển tiếp giữa cửa sổ và shell, giữ bộ đệm 256 KiB, nối với agent |
| Khối tích hợp shell | chèn vào file cấu hình shell | Chuyển shell tương tác mới sang chạy trong `shellx-term` |
| Bộ cài đặt tích hợp | `apps/desktop` | Bật/tắt: chép `shellx-term`, sửa file cấu hình, kiểm chính sách PowerShell |
| Máy chủ nội bộ | `packages/shellx_agent` | Nhận kết nối của các `shellx-term`, biến mỗi terminal thành phiên `desktop` |
| Giao thức | `packages/shellx_core`, `packages/shellx_client` | Trường/tin nhắn mới (§8) |
| Giao diện | `apps/mobile`, `apps/desktop` | §9, §7.6 |

Build: `flutter build macos` và `flutter build windows` tự build `shellx-term` (Xcode Run Script build phase / CMake custom command gọi `cargo build --release`) và đặt nó vào bản build. Máy build chỉ cần có Rust (máy GitHub đã cài sẵn; thêm target `aarch64-apple-darwin` và `x86_64-apple-darwin`).

---

## 5. `shellx-term`

### 5.1 Cách gọi

```
shellx-term wrap [--login] -- <đường dẫn tuyệt đối của shell> [đối số…]
shellx-term uninstall        # gỡ khối tích hợp khỏi mọi file cấu hình, xóa thư mục bin
shellx-term --version
```

`wrap` mở một PTY cỡ bằng cửa sổ hiện tại, chạy shell trong đó với biến môi trường `SHELLX_TERM=1`, chuyển tiếp dữ liệu hai chiều, và thoát với **đúng mã thoát của shell**.

### 5.2 Khối tích hợp trên macOS (zsh, bash)

Khối nằm ở **đầu** file, chỉ gồm ký tự ASCII, có dấu `# >>> ShellX >>>` và `# <<< ShellX <<<`. Nó `exec` sang `shellx-term` khi **mọi** điều kiện sau đều đúng:

- shell đang ở chế độ tương tác (`$-` chứa `i`);
- stdin và stdout đều là terminal (`[ -t 0 ] && [ -t 1 ]`);
- chưa ở trong `shellx-term` (`SHELLX_TERM` rỗng) và không phải phiên do ShellX mở từ điện thoại (`SHELLX` rỗng);
- không ở trong tmux hoặc screen (`TMUX`, `STY` rỗng) — cửa sổ đang chạy tmux đã được bọc ở tầng ngoài;
- ứng dụng terminal không nằm trong danh sách loại trừ (theo `TERM_PROGRAM`, lập từ kết quả kiểm tra ở §13; Warp là nghi vấn đầu tiên);
- file `~/Library/Application Support/ShellX/bin/shellx-term` tồn tại và chạy được.

Khối truyền cho `shellx-term` đường dẫn tuyệt đối của **chính shell đang chạy** (bash: `$BASH`; zsh: `${${ZSH_ARGZERO#-}:c}`) và cờ `--login` nếu shell là login shell (bash: `shopt -q login_shell`; zsh: `[[ -o login ]]`). Nhờ `exec`, `shellx-term` giữ đúng PID của shell ban đầu.

### 5.3 Khối tích hợp trên Windows (PowerShell 7 và 5.1)

Khối nằm ở đầu profile `CurrentUserAllHosts` của từng bản PowerShell, chỉ gồm ký tự ASCII (Windows PowerShell 5.1 đọc file không BOM theo bảng mã hệ thống). Nó chạy khi:

- `$Host.Name -eq 'ConsoleHost'` (loại trừ ISE và PowerShell Extension của VS Code);
- stdin và stdout không bị chuyển hướng (`[Console]::IsInputRedirected`, `IsOutputRedirected`);
- PowerShell không được gọi với `-Command`, `-File`, `-EncodedCommand`, `-NonInteractive` (kể cả dạng viết tắt, không phân biệt hoa thường);
- `SHELLX_TERM` và `SHELLX` rỗng;
- file `%LOCALAPPDATA%\ShellX\bin\shellx-term.exe` tồn tại.

Windows không thay tiến trình tại chỗ được, nên PowerShell ngoài chạy `shellx-term wrap -- <(Get-Process -Id $PID).Path> -NoLogo`, chờ, rồi `exit` với mã thoát của nó. **Ngoại lệ:** mã **222** nghĩa là "không bọc được"; khi đó profile chạy tiếp như bình thường và người dùng dùng PowerShell ngoài. (Nếu chính shell bên trong thoát với mã 222, người dùng rơi về PowerShell ngoài thay vì cửa sổ đóng. Trường hợp hiếm và vô hại, ghi nhận.)

**Cái giá trên Windows:** mỗi cửa sổ PowerShell có thêm một tiến trình PowerShell đứng chờ (mở chậm hơn khoảng 0,3–1 giây, tốn thêm khoảng 60–80 MB RAM). Con số thật đo trong lần kiểm tra Windows.

`shellx-term` trên Windows:
- đưa console ngoài vào chế độ VT thô (`ENABLE_VIRTUAL_TERMINAL_INPUT`, tắt `ENABLE_PROCESSED_INPUT`/`LINE_INPUT`/`ECHO_INPUT` ở stdin; `ENABLE_VIRTUAL_TERMINAL_PROCESSING` ở stdout), để Ctrl+C đi vào shell bên trong như một ký tự thay vì tín hiệu;
- đọc input bằng `ReadConsoleInputW` để nhận cả phím (kể cả ký tự tiếng Việt từ IME, gồm cặp surrogate UTF-16) lẫn sự kiện đổi kích thước;
- tạo ConPTY bên trong qua `portable-pty`.

### 5.4 Cam kết an toàn

1. **Terminal không bao giờ chờ ShellX.** Luồng chính chỉ chuyển dữ liệu giữa cửa sổ và PTY. Bản sao gửi agent đi qua hàng chờ giới hạn **1 MiB**. Hàng chờ đầy thì cắt kết nối với agent, kết nối lại sau và gửi lại bộ đệm (§6.5). Ghi input từ điện thoại vào PTY chạy trên luồng riêng.
2. **Không mở được PTY hay không chạy được shell trong PTY:** macOS `exec` thẳng shell gốc với đối số gốc; Windows thoát với mã 222 (§5.3). Người dùng vẫn có shell, chỉ không chia sẻ.
3. **Agent không chạy:** `shellx-term` chạy bình thường và thử kết nối lại theo lịch 1, 2, 4, 8, tối đa 10 giây. Mỗi lần thử chỉ đọc file `endpoint` rồi kết nối tới localhost.
4. **`shellx-term` bị xóa:** khối tích hợp kiểm tra file tồn tại trước khi dùng.
5. **Shell thoát:** `shellx-term` khôi phục chế độ cửa sổ rồi thoát với mã thoát của shell.
6. **Chế độ cửa sổ luôn được khôi phục** (termios / console mode ban đầu) khi thoát bình thường, khi nhận tín hiệu kết thúc, và khi panic (panic hook).
7. **Bàn phím và kích thước:** Ctrl+C, Ctrl+Z, Ctrl+D đi thẳng vào shell bên trong. Đổi kích thước cửa sổ được chuyển tiếp: macOS qua `SIGWINCH`, Windows qua `WINDOW_BUFFER_SIZE_EVENT`. Tiêu đề do shell hoặc chương trình đặt (OSC 0/2) đi qua nguyên vẹn ra cửa sổ.
8. **Bộ đệm 256 KiB** output gần nhất, giữ từ lúc mở cửa sổ.

### 5.5 Kích thước khi cả hai cùng dùng

`shellx-term` giữ trạng thái "bên điều khiển": `desktop` (mặc định) hoặc `phone`.

- Agent gửi `resize` (điện thoại gắn vào, gõ, hoặc đổi kích thước) → PTY lấy kích thước điện thoại, bên điều khiển là `phone`.
- Có phím gõ trên máy tính, hoặc cửa sổ đổi kích thước, khi bên điều khiển là `phone` → `shellx-term` **tự** đưa PTY về kích thước cửa sổ ngay (không chờ agent), đặt bên điều khiển là `desktop` và báo agent (`local`).
- Agent gửi `local_size` (điện thoại rời) → về kích thước cửa sổ.
- Mỗi lần đổi bên điều khiển mà kích thước không đổi, dùng mẹo "giảm một dòng rồi trả lại" (như `SessionManager._attach`) để chương trình toàn màn hình vẽ lại.

---

## 6. Kết nối nội bộ `shellx-term` ↔ agent

### 6.1 Điểm kết nối

- Agent mở `ServerSocket` trên `127.0.0.1`, cổng do hệ điều hành chọn, **chỉ khi tính năng đang bật**.
- Mỗi lần agent khởi động (và mỗi lần bật tính năng), agent sinh **khóa bí mật 32 byte mới** và ghi file `endpoint` (ghi file tạm rồi đổi tên) gồm phiên bản, số cổng và khóa:
  - macOS: `~/Library/Application Support/ShellX/term/endpoint`; thư mục 0700, file 0600.
  - Windows: `%LOCALAPPDATA%\ShellX\term\endpoint` (quyền thừa kế của `%LOCALAPPDATA%`: chỉ người dùng, SYSTEM, Administrators).
- Tắt tính năng hoặc thoát agent: đóng cổng và xóa file `endpoint`.
- `shellx-term` đọc lại file ở mỗi lần kết nối.

### 6.2 Khung

Mỗi khung là độ dài 4 byte big-endian + một map CBOR có khóa `t` (cùng quy ước với tin nhắn ứng dụng hiện có). Khung tối đa 64 KiB; output lớn được chia nhỏ. Nhận khung sai định dạng hoặc quá lớn thì đóng kết nối.

### 6.3 Xác thực hai chiều

1. `shellx-term` → agent: `{t: "hello", v: 1, nonce: 32 byte}`.
2. agent → `shellx-term`: `{t: "challenge", nonce: 32 byte, mac: HMAC-SHA256(khóa, "shellx-term/agent" ‖ nonce_term ‖ nonce_agent)}`.
3. `shellx-term` kiểm `mac` (so sánh thời gian hằng). Sai thì đóng và **chưa gửi byte terminal nào**.
4. `shellx-term` → agent: `{t: "auth", mac: HMAC-SHA256(khóa, "shellx-term/term" ‖ nonce_agent ‖ nonce_term), term_id: 16 byte, app, shell, pid, cols, rows, started_at}`.
5. Agent kiểm `mac`, rồi trả `{t: "ready"}`, hoặc `{t: "reject", reason: "limit" | "version"}` và đóng.

- `v` là phiên bản giao thức nội bộ. Agent chấp nhận mọi phiên bản nó biết, để terminal mở từ trước khi cập nhật ShellX vẫn nối được. Bị `reject` với `version` thì `shellx-term` ngừng thử cho tới khi file `endpoint` đổi. Bị `limit` thì thử lại sau 30 giây.
- Xác thực không qua trong 5 giây thì đóng.
- `app`: tên ứng dụng terminal lấy từ biến môi trường (`TERM_PROGRAM` trên macOS; `WT_SESSION` có mặt thì là Windows Terminal; `TERM_PROGRAM=vscode` cho VS Code/Cursor), rỗng nếu không biết.

### 6.4 Tin nhắn sau `ready`

| Hướng | `t` | Trường | Ý nghĩa |
|---|---|---|---|
| term → agent | `snapshot` | `data` | Toàn bộ bộ đệm 256 KiB. Luôn là khung đầu tiên sau `ready` |
| term → agent | `out` | `data` | Output mới |
| term → agent | `size` | `cols`, `rows` | Kích thước cửa sổ đổi |
| term → agent | `local` | — | Bên điều khiển chuyển về `desktop` (§5.5) |
| term → agent | `exit` | `code` | Shell đã thoát |
| agent → term | `in` | `data` | Input từ điện thoại |
| agent → term | `resize` | `cols`, `rows` | Kích thước điện thoại, bên điều khiển thành `phone` |
| agent → term | `local_size` | — | Về kích thước cửa sổ |

### 6.5 Mất kết nối và nối lại

- `shellx-term` nối lại với **cùng `term_id`**, gửi `snapshot` mới.
- Agent giữ phiên `desktop` **30 giây** sau khi mất kết nối. Nối lại kịp thì dùng lại đúng phiên (cùng `id` phiên): agent đặt bộ đệm của phiên theo `snapshot` (số thứ tự tiếp tục tăng) và gửi `session.reset` rồi dữ liệu cho điện thoại đang gắn.
- Quá 30 giây: phiên bị xóa; điện thoại đang gắn nhận `session.detached {reason: "terminal_gone"}`.

### 6.6 Giới hạn và mô hình đe dọa

- Tối đa **32** phiên `desktop` mỗi agent (tối đa khoảng 8 MiB bộ đệm), tách khỏi giới hạn 10 phiên `shellx`.
- Không mã hóa trên `127.0.0.1`: tài khoản thường khác không nghe lén được loopback; người có quyền admin vốn đọc được mọi thứ trên máy.
- **Ranh giới được bảo vệ là giữa các tài khoản trên cùng máy.** Tài khoản khác không đọc được file `endpoint`, nên không giả làm agent được (kể cả khi chiếm cổng cũ lúc ShellX đang tắt) và không giả làm `shellx-term` được. Chương trình chạy dưới **chính tài khoản người dùng** thì đọc được khóa; đây không phải lỗ hổng mới vì chương trình đó vốn đã làm được mọi thứ với terminal của người dùng.

---

## 7. Agent

### 7.1 Phiên `desktop`

Mỗi `shellx-term` đã xác thực trở thành một phiên loại `desktop` trong `SessionManager`, dùng chung:
- bộ đệm vòng theo `seq`;
- gắn lại và phát lại;
- quy tắc một điện thoại mỗi phiên (`taken_over`);
- cửa sổ gửi/ack.

Agent **luôn đọc** socket của `shellx-term` vào bộ đệm (bộ đệm vòng ghi đè dữ liệu cũ), không bao giờ ngừng đọc để dồn áp lực ngược về terminal.

| | Phiên `shellx` (như hiện nay) | Phiên `desktop` |
|---|---|---|
| Xuất hiện | `session.open` từ điện thoại | `shellx-term` kết nối và xác thực |
| `session.close` từ điện thoại | tắt shell | coi như `session.detach` |
| Thu hồi điện thoại, tắt "Allow remote access", đăng xuất, `closeAll`, thoát ShellX | tắt shell | chỉ ngắt điện thoại (gửi `session.detached {closed_by_host}` nếu kênh còn) |
| Kết thúc | shell thoát → `session.exited` | `exit` từ `shellx-term` → `session.exited`; mất kết nối quá 30 giây → `terminal_gone` |
| Giới hạn | 10 | 32 |
| `index` | số thứ tự phiên `shellx` | dãy số riêng cho phiên `desktop` |
| Kích thước | theo điện thoại | theo bên điều khiển (§5.5) |

### 7.2 Không bao giờ tắt terminal máy tính

Mọi đường code hiện có dẫn tới `kill()` (`closeSessionsAttachedTo`, `closeSession`, `closeAll`, `SessionClose`) phải bỏ qua phiên `desktop` và chỉ ngắt điện thoại. **Mỗi đường có một test riêng.** Phiên `desktop` không có `kill`; `Pty` của nó (adapter trên kết nối nội bộ) cài `kill()` là no-op.

### 7.3 Kích thước

- `session.attach` / `resize` / `input` từ điện thoại đang gắn → nếu kích thước khác kích thước hiện tại hoặc bên điều khiển đang là `desktop`, agent gửi `resize` cho `shellx-term`.
- Nhận `local` từ `shellx-term` → agent gửi `session.driver {by: "desktop"}` cho điện thoại đang gắn.
- Agent gửi `resize` thì cũng gửi `session.driver {by: "phone"}`.
- Điện thoại rời hoặc bị ngắt → agent gửi `local_size`.

### 7.4 Tiêu đề

Agent đọc chuỗi OSC 0/2 trong output của phiên `desktop` và giữ tiêu đề mới nhất (tối đa 200 ký tự) để đưa vào `session.list.result` và menu.

### 7.5 Quyền truy cập

Giữ quy tắc hiện có: chỉ điện thoại đã ghép nối, qua kênh mã hóa đầu cuối, chỉ khi "Allow remote access" bật. Tắt "Allow remote access" thì mọi điện thoại đang gắn vào phiên `desktop` bị ngắt, còn terminal không bị đụng tới.

### 7.6 Giao diện desktop

- Menu: công tắc **"Chia sẻ terminal với điện thoại (thử nghiệm)"**.
  - macOS: luôn hiện.
  - Windows: chỉ hiện khi ShellX khởi động với biến môi trường `SHELLX_EXPERIMENTAL=terminal-sharing` (§12).
- Menu con **"Terminal trên máy tính (N)"**: mỗi dòng "ứng dụng — tiêu đề", thêm "📱" khi có điện thoại gắn. Chọn một dòng → **"Ngắt điện thoại"**. Không có mục tắt terminal.
- Dòng cảnh báo **"Chia sẻ terminal cần thiết lập lại…"** khi công tắc bật mà khối tích hợp không còn trong file cấu hình, hoặc `shellx-term` trong thư mục `bin` bị thiếu.
- **Thông báo trên máy tính** khi một điện thoại gắn vào phiên `desktop`: "{thiết bị} đang xem terminal {ứng dụng — tiêu đề}". Tối đa một thông báo cho mỗi cặp (điện thoại, terminal) trong 10 phút, để việc gắn lại sau khi rớt mạng không làm phiền.

---

## 8. Giao thức điện thoại ↔ agent

Mọi thay đổi nằm trong tin nhắn ứng dụng (spec v1 §6.4), đi trong kênh mã hóa. `proto` của handshake **không đổi**.

| Tin nhắn | Thay đổi |
|---|---|
| `session.list` | Trường tùy chọn `desktop: true`. App mobile mới luôn gửi |
| `session.list.result` | Khi yêu cầu có `desktop: true`: thêm `desktop_sharing: bool` (công tắc đang bật hay không) và đưa phiên `desktop` vào `sessions` |
| `SessionInfo` | Trường tùy chọn `kind` (`"desktop"`; vắng mặt = `shellx`), `app` (chuỗi, có thể rỗng), `title` (chuỗi, có thể rỗng). Chỉ có trên phiên `desktop` |
| `session.detach {id}` | **Mới**, điện thoại → agent. Rời phiên `desktop`. Không có trả lời |
| `session.driver {id, by}` | **Mới**, agent → điện thoại. `by` ∈ `desktop`, `phone` |
| `session.detached` | Lý do mới `terminal_gone` |

**Tương thích:**
- App mobile cũ không gửi `desktop: true`, nên không bao giờ nhận phiên `desktop`, trường mới, `session.driver` hay `terminal_gone` (những thứ bộ giải mã enum cũ sẽ từ chối).
- Agent cũ bỏ qua trường lạ (bộ giải mã hiện tại chỉ đọc khóa nó biết) và trả danh sách như cũ, không có `desktop_sharing`.
- App mobile mới thấy thiếu `desktop_sharing` thì hiểu là agent cũ và hiện gợi ý cập nhật.
- Agent cũ nhận `session.detach` (loại `t` lạ) thì bỏ qua. Điện thoại chỉ gửi nó cho phiên `desktop`, vốn không tồn tại trên agent cũ.

---

## 9. App mobile

### 9.1 Bảng chọn phiên

- Hai nhóm: **"Terminal trên máy tính"** (biểu tượng máy tính; dòng chính "ứng dụng — tiêu đề", nếu thiếu thì dùng tên ứng dụng hoặc tên shell; dòng phụ "mở {khi nào}" và "đang mở trên thiết bị khác" nếu có) và **"Phiên ShellX"** (như hiện nay), cuối bảng là nút **"Phiên mới"**.
- **Khi hiện:** lần đầu vào một máy (như hiện nay), và **khi bấm `+`** nếu có phiên `desktop` hoặc phiên `shellx` chưa mở thành tab. Không có gì để chọn thì `+` mở phiên mới ngay như bây giờ.
- **Không có phiên `desktop`**, một dòng gợi ý:
  - `desktop_sharing: false`: "Bật 'Chia sẻ terminal' trong menu ShellX trên máy tính để xem các terminal đang mở ở đây."
  - Thiếu `desktop_sharing`: "Cập nhật ShellX trên máy tính để xem các terminal đang mở."
  - `desktop_sharing: true`: "Chỉ các cửa sổ terminal mở sau khi bật chia sẻ mới hiện ở đây. Mở một cửa sổ terminal mới trên máy tính."

### 9.2 Tab của phiên `desktop`

- **Nhãn** là tiêu đề, không có thì tên ứng dụng, kèm biểu tượng máy tính nhỏ.
- **`×`** gửi `session.detach`, đóng tab, và hiện snackbar "Terminal vẫn chạy trên máy tính." Không hỏi xác nhận.
- **Băng "Máy tính đang dùng terminal này"** khi nhận `session.driver {by: desktop}`. Chạm vùng terminal hoặc gõ thì gửi `resize` với kích thước điện thoại; băng ẩn khi nhận `session.driver {by: phone}`.
- **Thẻ kết thúc** giữ nội dung tab (như hiện nay), chỉ có nút **"Đóng tab"** (terminal không còn, không gắn lại được):
  - `session.exited`: "Cửa sổ terminal trên máy tính đã đóng."
  - `terminal_gone`: "Mất kết nối với terminal này trên máy tính."
- **Bị ngắt, terminal vẫn chạy** (`closed_by_host`: người dùng bấm "Ngắt điện thoại" trên máy tính, hoặc tắt "Allow remote access"): thẻ "Máy tính đã ngắt điện thoại khỏi terminal này." với hai nút "Gắn lại" và "Đóng tab".

### 9.3 Không đổi

Thanh phím phụ, chụm đổi cỡ chữ, copy/paste, khóa app và danh sách máy giữ nguyên. Câu chữ có đủ tiếng Việt và tiếng Anh. File thiết kế `docs/superpowers/design/2026-09-25-shellx-mobile-ui.html` được bổ sung các trạng thái trên trước khi code giao diện.

---

## 10. Bật, tắt, cài đặt, cập nhật, gỡ

### 10.1 Bật

1. Người dùng bật công tắc → cửa sổ xác nhận liệt kê **chính xác các file sẽ sửa hoặc tạo**, giới hạn (chỉ terminal mở sau khi bật), và trên Windows là trạng thái chính sách script (§10.3).
2. Người dùng đồng ý → ShellX:
   1. chép `shellx-term` vào thư mục `bin` (§10.4);
   2. sao lưu từng file cấu hình **một lần** thành `<tên file>.shellx-backup`, không ghi đè bản sao lưu đã có;
   3. chèn khối vào đầu file;
   4. mở cổng nội bộ và ghi `endpoint`.
3. Lỗi ở bất kỳ bước nào thì hoàn tác các bước trước, và công tắc vẫn tắt kèm thông báo lỗi.

### 10.2 File cấu hình

| File | Quy tắc |
|---|---|
| `~/.zshrc` | Tạo nếu chưa có |
| `~/.bashrc`, `~/.bash_profile` | **Chỉ sửa file đã có.** Không bao giờ tạo `~/.bash_profile`: nếu có nó, bash login thôi đọc `~/.profile`. Không có file bash nào thì bỏ qua bash và nói rõ trong cửa sổ xác nhận |
| Profile PowerShell 7 và 5.1 | Đường dẫn lấy bằng cách hỏi chính từng bản PowerShell đã cài (`-NoProfile -Command $PROFILE.CurrentUserAllHosts`), vì Documents có thể nằm trong OneDrive. Tạo nếu chưa có |

- **Chèn và gỡ đều không lặp:** chèn lại vẫn chỉ có một khối; gỡ chỉ xóa phần giữa hai dấu.
- **Giữ nguyên** nội dung, bảng mã (UTF-8, UTF-8 BOM, UTF-16 LE/BE) và kiểu xuống dòng (LF/CRLF) sẵn có của file.
- **ShellX chỉ sửa file cấu hình khi người dùng bật hoặc tắt.** Khi khởi động, ShellX chỉ kiểm tra và báo "cần thiết lập lại" (§7.6), không tự chèn lại.

### 10.3 Chính sách script của PowerShell (Windows)

- Với từng bản PowerShell, ShellX đọc chính sách hiệu lực (`Get-ExecutionPolicy`) và chính sách theo từng phạm vi (`-List`).
- Nếu hiệu lực là `Restricted` hoặc `AllSigned` thì profile sẽ không chạy:
  - Cửa sổ xác nhận giải thích và có nút **"Cho phép script cục bộ cho tài khoản của tôi"**. Nút này chạy `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` **chỉ khi người dùng bấm**.
  - Nếu chính sách do Group Policy đặt (`MachinePolicy`/`UserPolicy`), ShellX không đổi được. Cửa sổ nói rõ rằng bản PowerShell đó sẽ không được chia sẻ.

### 10.4 Vị trí và cập nhật `shellx-term`

| | Trong bản cài | Thư mục `bin` (khối tích hợp trỏ tới) |
|---|---|---|
| macOS | `ShellX.app/Contents/Helpers/shellx-term` | `~/Library/Application Support/ShellX/bin/shellx-term` |
| Windows | `shellx-term.exe` cạnh `ShellX.exe` | `%LOCALAPPDATA%\ShellX\bin\shellx-term.exe` |

- Mỗi lần ShellX khởi động mà công tắc đang bật và bản trong `bin` khác bản trong bộ cài (so theo `--version` và hash), ShellX chép bản mới:
  - macOS: ghi file tạm rồi đổi tên đè lên; terminal đang mở vẫn dùng bản cũ.
  - Windows: đổi tên bản đang chạy thành `shellx-term.old-<n>.exe` rồi chép bản mới; lần khởi động sau xóa các bản `.old-*` không còn bị khóa.

### 10.5 Tắt

ShellX gỡ khối khỏi mọi file cấu hình, đóng cổng nội bộ, xóa `endpoint`, và xóa thư mục `bin` nếu được. Trên Windows, file đang chạy thì để lần khởi động sau xóa. Terminal đang mở vẫn chạy (không còn chia sẻ) tới khi người dùng đóng.

### 10.6 Gỡ cài đặt

- **Windows:** bộ gỡ cài đặt Inno Setup chạy `ShellX.exe --terminal-sharing-cleanup` (gỡ khối, xóa `bin` và `term`) trước khi xóa file.
- **macOS:** không có bước gỡ. Khối còn lại vô hại: `shellx-term` trong `bin` chạy một mình như terminal thường. Gỡ sạch bằng lệnh `shellx-term uninstall`. Trang FAQ của shellx.pro có thêm một mục hướng dẫn việc này.

### 10.7 Phát hành

- `release/macos/sign-app.sh` hiện chỉ ký dylib, framework và app lồng nhau; phải thêm bước ký `Contents/Helpers/shellx-term` với hardened runtime và timestamp **trước** khi ký app. Notarize như cũ.
- Windows: bước ký Azure hiện có (lọc `exe,dll`) ký luôn `shellx-term.exe`; bước kiểm Authenticode phải có file này.
- Relay và web không cần deploy. Riêng mục FAQ ở §10.6 là thay đổi web, deploy theo quy trình hiện có khi người dùng push.

---

## 11. Kiểm thử

### 11.1 `shellx-term` (Rust, `cargo test` trên macOS và Windows)

- **Đơn vị:**
  - khung CBOR (đúng, sai định dạng, quá 64 KiB);
  - xác thực HMAC hai chiều (đúng; sai `mac` của agent; sai `mac` của term; quá 5 giây);
  - bộ đệm vòng;
  - hàng chờ 1 MiB và hành vi khi đầy;
  - máy trạng thái bên điều khiển (§5.5);
  - lịch thử kết nối lại.
- **Tích hợp:** chạy `shellx-term wrap` bên trong một PTY giả làm cửa sổ, với shell thật:
  - gõ `echo` và thấy output;
  - truyền mã thoát;
  - chuyển tiếp đổi kích thước;
  - Ctrl+C dừng tiến trình con;
  - agent giả ngừng đọc mà terminal vẫn không nghẽn;
  - agent giả chết giữa chừng thì terminal vẫn chạy;
  - PTY không mở được thì dự phòng theo §5.4 mục 2;
  - chế độ cửa sổ được khôi phục sau khi thoát và sau panic.

### 11.2 Agent (Dart)

- **Phiên `desktop` không bao giờ bị tắt:** một test cho mỗi đường ở §7.2.
- **Gắn và bộ đệm:** gắn, gắn lại, phát lại; `snapshot` khi nối lại trong 30 giây; `terminal_gone` sau 30 giây.
- **Kích thước và bên điều khiển:** `resize`, `local`, `local_size`, `session.driver`.
- **Danh sách phiên:** giới hạn 32; chỉ liệt kê phiên `desktop` khi có `desktop: true`; `desktop_sharing`.
- **Máy chủ nội bộ:** xác thực (đúng, sai, chậm, giả lập kẻ chiếm cổng không có khóa), `reject` theo `limit`/`version`, nhiều phiên bản `v`.
- **Tiêu đề:** đọc OSC tiêu đề.
- **Thông báo:** thông báo gắn vào bị giới hạn tần suất.

### 11.3 Bộ sửa file cấu hình (Dart)

- Chèn hai lần vẫn chỉ một khối; gỡ khối; giữ nguyên nội dung còn lại.
- Giữ bảng mã (UTF-8, UTF-8 BOM, UTF-16) và kiểu xuống dòng (LF, CRLF).
- Quy tắc bash (không tạo `~/.bash_profile`).
- Sao lưu một lần.
- Hoàn tác khi một bước lỗi.
- Khối chỉ gồm ASCII.

### 11.4 End-to-end (`packages/shellx_e2e`)

- **Qua relay trong bộ nhớ:** điện thoại giả lập ↔ agent ↔ `shellx-term` thật đi trọn luồng: liệt kê, gắn, xem output có từ trước, gõ lệnh, rời, gắn lại, shell thoát.
- **Qua relay thật:** chạy một lần trỏ vào `relay.shellx.pro` (như lần kiểm tra 2026-09-30).

### 11.5 Mobile

Test widget và controller:
- bảng chọn hai nhóm và ba loại gợi ý;
- `+` mở bảng hoặc mở phiên mới ngay;
- `×` gửi `session.detach`;
- băng "Máy tính đang dùng";
- ba thẻ kết thúc.

### 11.6 Kiểm tra tay theo ứng dụng terminal

| Nền tảng | Ứng dụng |
|---|---|
| macOS | Terminal.app, iTerm2 (bật shell integration), Cursor, VS Code, Warp |
| Windows | Windows Terminal (PowerShell 7 và 5.1), cửa sổ console cũ (conhost), terminal của VS Code/Cursor |

Mỗi ứng dụng kiểm tra:
- chương trình toàn màn hình: `vim`, `htop` (Windows: một chương trình toàn màn hình tương đương), `less`;
- Ctrl+C với lệnh chạy lâu; Ctrl+Z (macOS);
- đổi kích thước cửa sổ;
- dán đoạn văn dài;
- **gõ tiếng Việt** (IME) cả ở máy tính lẫn điện thoại;
- mã thoát `exit 3`;
- tiêu đề cửa sổ;
- hỏi xác nhận khi đóng cửa sổ (§13, R2);
- thời gian mở cửa sổ (§1, tiêu chí 5).

---

## 12. Kiểm chứng và phát hành theo nền tảng

- **macOS:** kiểm chứng đầy đủ trên máy phát triển: test tự động, danh sách §11.6, và điện thoại thật (Pixel 3) qua `relay.shellx.pro`.
- **Windows:**
  - Workflow mới `.github/workflows/windows-check.yml`, **chỉ `workflow_dispatch`**, chạy trên `windows-latest`:
    - `cargo test` cho `term/` (gồm ConPTY thật);
    - `dart test` cho `packages/shellx_agent` và `packages/shellx_core`;
    - `flutter build windows` để xác nhận `shellx-term.exe` nằm trong bản build.
  - Không chạy theo push; giữ quyết định "không CI".
  - Kiểm tra tương tác (§11.6, phần Windows) là **việc chờ**, ghi vào HANDOFF §4.
  - Cho tới khi kiểm xong: công tắc không hiện trên Windows trừ khi có `SHELLX_EXPERIMENTAL=terminal-sharing`. Bản Windows vẫn chứa `shellx-term.exe` và mọi code, chỉ ẩn công tắc.
- **Mobile:** tính năng hiện khi agent hỗ trợ (§8), không cần cờ.

---

## 13. Rủi ro và việc cần xác minh sớm

Bước đầu tiên của kế hoạch triển khai là một **bản thử `shellx-term` trên macOS**. Bản thử chỉ bọc shell và chưa nối agent. Nó dùng để kiểm R1–R3 trước khi làm các phần còn lại; kết quả có thể thêm vào danh sách loại trừ ở §5.2.

| # | Rủi ro | Cách xử lý |
|---|---|---|
| R1 | **Shell integration của ứng dụng terminal** bị hỏng khi shell chạy lại bên trong `shellx-term`: VS Code/Cursor chèn integration cho zsh qua `ZDOTDIR`; iTerm2 shell integration; Warp tự khởi tạo shell theo cách riêng | Kiểm trong bản thử. Không sửa được thì đưa vào danh sách loại trừ theo `TERM_PROGRAM` |
| R2 | **Tên tiến trình trên tiêu đề và hỏi xác nhận khi đóng:** Terminal.app và iTerm2 xem tiến trình đang chạy trên TTY của cửa sổ, nay là `shellx-term`. Có thể tiêu đề hiện "shellx-term" và mỗi lần đóng cửa sổ đều bị hỏi "terminate running processes?" | Kiểm trong bản thử (`exec` giữ nguyên PID của login shell có thể giúp). Nếu bị hỏi: khi bật tính năng, đề nghị người dùng thêm `shellx-term` vào danh sách tiến trình bỏ qua của Terminal.app/iTerm2 (chỉ khi người dùng đồng ý), hoặc tìm cách khác trước khi làm tiếp |
| R3 | **Thời gian mở cửa sổ** vượt 50 ms | Đo trong bản thử; tối ưu khối tích hợp (không gọi tiến trình con) |
| R4 | **ConPTY lồng nhau trên Windows:** input VT, IME tiếng Việt qua `ReadConsoleInputW`, Ctrl+C, sự kiện đổi kích thước, chương trình toàn màn hình | Test tự động trên `windows-latest` + kiểm tra tay (việc chờ); công tắc ẩn tới khi xong |
| R5 | **Chi phí PowerShell đứng chờ** trên Windows (thời gian mở, RAM) | Đo khi kiểm tra Windows; ghi rõ trong cửa sổ xác nhận |
| R6 | Khối tích hợp tương tác với cấu hình sẵn có của người dùng (oh-my-zsh, powerlevel10k instant prompt, file có `exec tmux`) | Khối đứng đầu file nên `exec` trước mọi thứ; shell bên trong chạy cấu hình của người dùng như một cửa sổ mới. Kiểm với oh-my-zsh + powerlevel10k |
| R7 | `SHLVL` tăng thêm 1 trong shell bên trong | Chấp nhận (chỉ là biểu hiện) |
| R8 | Khối còn sót sau khi kéo ShellX.app vào Thùng rác | Vô hại theo §5.4; có `shellx-term uninstall` và mục FAQ |

---

## 14. Chia kế hoạch triển khai

Khối lượng lớn, chia thành các kế hoạch nối tiếp; mỗi kế hoạch kết thúc bằng review và merge vào nhánh tích hợp như các plan v1.

| # | Kế hoạch | Phụ thuộc | Kết quả kiểm được |
|---|---|---|---|
| P1 | Bản thử `shellx-term` trên macOS (chỉ bọc shell) + kiểm R1–R3 | — | Báo cáo tương thích, danh sách loại trừ, số đo thời gian mở; quyết định tiếp tục hoặc điều chỉnh thiết kế |
| P2 | `shellx-term` đầy đủ (macOS + Windows): §5, §6 phía term, test §11.1, workflow `windows-check.yml` | P1 | `cargo test` xanh trên macOS và `windows-latest` |
| P3 | Agent + giao thức: §6 phía agent, §7.1–7.5, §8, test §11.2, e2e §11.4 | P2 | e2e điện thoại giả lập ↔ agent ↔ `shellx-term` thật |
| P4 | Desktop: bật/tắt, bộ sửa file cấu hình, chính sách PowerShell, cập nhật/gỡ, menu và thông báo (§7.6, §10), tích hợp build và ký (§4, §10.7), test §11.3 | P3 | Bật trên macOS từ menu, mở cửa sổ mới thấy trên điện thoại giả lập |
| P5 | Mobile: §9, cập nhật file thiết kế giao diện, test §11.5 | P3 (chạy song song với P4 được) | Pixel 3 xem và gõ vào terminal Terminal.app qua `relay.shellx.pro`; danh sách §11.6 phần macOS |
