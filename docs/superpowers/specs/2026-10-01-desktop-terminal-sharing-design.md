# Chia sẻ terminal máy tính với điện thoại — Đặc tả thiết kế

- **Ngày:** 2026-10-01
- **Trạng thái:** Đã duyệt qua brainstorming từng phần (6/6). P1, P2a xong; P2b code xong. **Bổ sung P3 (2026-10-05): §7.7–§7.9, T13–T14, §11.2, §11.4, §14 — chờ người dùng đọc lại**
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
| T13 | Phiên `desktop` trong agent (2026-10-05) | Rút lõi chung `SessionStream`; phiên `desktop` có bộ quản lý riêng **không có hàm tắt** (§7.7). Loại bỏ: giả làm `Pty` có `kill()` rỗng, và một `SessionManager` chung có cờ `kind` — cả hai để an toàn của terminal phụ thuộc vào việc không quên một nhánh |
| T14 | e2e qua relay thật (2026-10-05) | Là bước cuối của P3, **người dùng tự chạy** theo lệnh ghi trong plan; agent không tự kết nối `relay.shellx.pro` |

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
shellx-term                  # không đối số: shell lấy từ biến môi trường (cách các khối tích hợp gọi)
shellx-term wrap [--login] -- <đường dẫn tuyệt đối của shell> [đối số…]
shellx-term probe            # in đường dẫn file thực thi của tiến trình cha
shellx-term uninstall        # gỡ khối tích hợp khỏi mọi file cấu hình, xóa thư mục bin
shellx-term --version
```

- **Không đối số + `SHELLX_TERM_WRAP`:** đây là cách các khối gọi, để tiêu đề cửa sổ hiện tên shell chứ không hiện đối số của `shellx-term` (R2). `SHELLX_TERM_WRAP` là đường dẫn tuyệt đối của shell cần bọc; `SHELLX_TERM_WRAP_LOGIN=1` (chỉ bash đặt) nghĩa là shell bên trong chạy với `-l`. Thiếu `SHELLX_TERM_WRAP` hoặc đường dẫn không tuyệt đối thì coi như đối số không hợp lệ: in một dòng cảnh báo và mở shell thường (§5.4). Cả hai biến bị gỡ khỏi môi trường của shell bên trong, và cả của shell thường do đường dự phòng mở (§5.4 mục 2; `SHELLX_TERM_LOGIN` thì giữ lại vì khối zsh đọc nó). Khi `shellx-term` được gọi theo cách này (từ khối, trong shell tương tác vừa bị thay thế) thì nó **luôn bỏ qua SIGTERM** như shell tương tác đó (§5.4 mục 6).
- **`wrap`:** mở một PTY cỡ bằng cửa sổ hiện tại, chạy shell trong đó, chuyển tiếp dữ liệu hai chiều, và thoát với **đúng mã thoát của shell**. Biến `SHELLX_TERM` của shell bên trong chứa **đường dẫn tty của PTY bên trong** (vd `/dev/ttys012`), không còn là `1`; khối so nó với tty của cửa sổ hiện tại để biết mình đang ở trong cửa sổ đã bọc hay chỉ thừa kế biến từ tiến trình cha (§5.2). Nếu không lấy được tên tty của PTY thì `wrap` coi như không mở được PTY (lỗi `no tty name for the PTY`) và đi đường dự phòng §5.4 mục 2: đặt `1` sẽ không chặn được việc bọc lại đệ quy, nên không có giá trị dự phòng đó.
- **`probe`:** in đường dẫn file thực thi của tiến trình cha (trên macOS bằng `proc_pidpath`), thoát với mã 1 nếu không lấy được. Khối gọi trong `$(…)`; vì `$(…)` là một bản fork của chính shell đang chạy khối nên đây đúng là file shell cần bọc.
- **Biến thử nghiệm:** `SHELLX_TERM_TIMING=fast` và `SHELLX_TERM_FAULT` chỉ có hiệu lực khi biên dịch với feature `test-hooks`; bản phát hành bỏ qua chúng.

### 5.2 Khối tích hợp trên macOS (zsh, bash)

Khối nằm ở **đầu** file, chỉ gồm ký tự ASCII, có dấu `# >>> ShellX >>>` và `# <<< ShellX <<<`. Nó `exec` sang `shellx-term` (không đối số, shell truyền qua `SHELLX_TERM_WRAP`, §5.1) khi **mọi** điều kiện sau đều đúng:

- shell đang tương tác **và không chạy chuỗi lệnh hay script**: zsh `[[ -o interactive ]]`, `$ZSH_EXECUTION_STRING` rỗng và `$ZSH_SCRIPT` rỗng (`zsh -i script`; không dùng `-o shinstdin`: zsh chỉ bật nó sau khi đọc xong các file khởi động); bash `$-` chứa `i` và `$BASH_EXECUTION_STRING` rỗng. VS Code/Cursor chạy `$SHELL -i -l -c '…'` để đọc biến môi trường khi khởi động; bọc shell đó sẽ làm editor treo;
- **zsh: khối đang chạy trong lúc zsh đọc file khởi động, không phải do người dùng `source` tay:** `$ZSH_EVAL_CONTEXT` không bắt đầu bằng `toplevel` (khi đọc file khởi động giá trị là `file`, hoặc `file:file` khi script của IDE `source` tiếp `.zshrc`; `source ~/.zshrc` gõ tay cho `toplevel:file`). Nếu thiếu điều kiện này, `source ~/.zshrc` trong cửa sổ chưa bọc sẽ `exec` thay shell đang chạy và mất job, hàm, biến. **bash:** `BASH_LINENO[0]` bằng `0`: khi bash đọc file khởi động thì khối chạy ở mức trên cùng của file, còn `. ~/.bashrc` gõ tay thì `BASH_LINENO[0]` là số dòng của lệnh gọi (khác `0`), nên khối bỏ qua. Giới hạn của điều kiện này ở danh sách "Giới hạn đã biết" bên dưới;
- stdin và stdout đều là terminal (`[ -t 0 ] && [ -t 1 ]`);
- chưa ở trong đúng cửa sổ đã bọc này: biến `SHELLX_TERM` (tty của PTY bên trong, §5.1) **khác tty của cửa sổ hiện tại** (zsh so với `$TTY`; bash so với `$(tty)`, chỉ chạy khi mọi điều kiện rẻ hơn đã đạt, và `SHELLX_TERM` rỗng thì khỏi so). Một ứng dụng mở từ cửa sổ đã bọc (vd `code .`) thừa kế `SHELLX_TERM` nhưng có tty riêng, nên terminal của nó **vẫn được bọc**; shell bên trong thì có `SHELLX_TERM` bằng đúng tty của nó nên không bọc lại. Và không phải phiên do ShellX mở từ điện thoại (`SHELLX` rỗng);
- không ở trong tmux hoặc screen (`TMUX`, `STY` rỗng) — cửa sổ đang chạy tmux đã được bọc ở tầng ngoài;
- ứng dụng terminal không nằm trong danh sách loại trừ theo `TERM_PROGRAM`. Hiện có `WarpTerminal` (loại trừ trước vì Warp tự khởi tạo shell; chưa kiểm được vì máy phát triển chưa cài). Danh sách chốt sau kiểm tra ở §13;
- ứng dụng terminal không phải VS Code/Cursor hay JetBrains **khi shell là bash** (`TERM_PROGRAM` khác `vscode`, `TERMINAL_EMULATOR` khác `JetBrains-JediTerm`): integration bash của các IDE này được chèn bằng `--init-file`/rcfile nên không chạy lại được. Với zsh, xem mục "Tích hợp IDE" bên dưới;
- `~/Library/Application Support/ShellX/bin/shellx-term` là file thường (`-f`, vì `-x` đúng cả với thư mục), có quyền chạy (`-x`), và `shellx-term probe` chạy thành công **và in ra một đường dẫn tuyệt đối** (điều kiện cuối cùng, nên chỉ chạy khi mọi điều kiện khác đã cho phép bọc). Lý do: zsh **thoát** khi `exec` thất bại, nên một file hỏng hoặc sai kiến trúc sẽ đóng mọi cửa sổ mới; chạy thử trước loại trường hợp đó. Một lần chạy `probe` làm hai việc: chứng minh file chạy được **và** cho biết file thực thi của chính shell đang chạy khối.

Đường dẫn của shell cần bọc lấy từ `shellx-term probe` (file thực thi của tiến trình cha), không đoán từ `$SHELL`, `$0` hay `PATH`: cách đó đúng cả khi zsh được chạy bằng tên trần, bằng đường dẫn tương đối, hay do ứng dụng chạy zsh không phải login (lệnh tùy chỉnh của iTerm2). Khối `exec -a` với `argv[0]` **y nguyên của shell ban đầu** (zsh: `$ZSH_ARGZERO`, kể cả dạng `-zsh`; bash: `$0`), nên Terminal.app lấy tên từ argv vẫn thấy `-zsh`, và tiêu đề cửa sổ gần như y cũ (giải quyết hướng sửa R2). Nhờ `exec`, `shellx-term` giữ đúng PID của shell ban đầu. Nội dung chuẩn của khối nằm ở `term/shell/block.zsh` và `term/shell/block.bash`; bộ cài (P4) chèn đúng nội dung đó và **phải cài binary vào `bin` trước khi ghi khối** (khối cần một binary có lệnh `probe`).

- **Login shell:**
  - **zsh:** shell bên trong **luôn khởi động không phải login**, kể cả khi shell ngoài là login: login bên trong sẽ chạy lại `/etc/zprofile` (`path_helper`) và `~/.zprofile`, làm **đảo thứ tự `PATH`** và chậm hơn (đo trong P1: +35,9 ms so với +13,2 ms). Thay vào đó, nếu shell ngoài là login (`[[ -o login ]]`) khối `export SHELLX_TERM_LOGIN=1`. Trong shell bên trong, nhánh `elif` của khối (đang ở đúng cửa sổ đã bọc, `SHELLX_TERM` bằng `$TTY`, và có `SHELLX_TERM_LOGIN`) gỡ biến rồi chạy `setopt login`; zsh đọc `~/.zlogin` sau `.zshrc` và `logout` chạy được. Vì vậy PATH vẫn giống hệt cửa sổ thường, `[[ -o login ]]` đúng, `~/.zlogin` chạy đúng một lần và `logout` thoát bình thường (có test PTY). Không còn "cái giá login" đã ghi ở P1. Nhánh `elif` cũng áp dụng cho **shell thường do fallback mở** (§5.4), vì fallback cũng đặt `SHELLX_TERM` bằng tty của cửa sổ; đó là chủ ý (cùng hành vi `.zlogin`/`logout`).
  - **bash:** `SHELLX_TERM_WRAP_LOGIN=1` khi `shopt -q login_shell`; shell bên trong chạy với `-l` (khối nằm đầu `.bash_profile`, trước phần còn lại của file). Hai biến `SHELLX_TERM_WRAP*` được `shellx-term` gỡ trước khi chạy shell bên trong; nếu `exec` thất bại thì khối gỡ chúng khỏi shell hiện tại.
- **Tích hợp IDE:** VS Code/Cursor và JetBrains khởi động zsh với `ZDOTDIR` trỏ vào thư mục của họ. Ngay trước `exec`, khối zsh đặt lại `ZDOTDIR=$VSCODE_ZDOTDIR` (hoặc `$_INTELLIJ_ZDOTDIR` nếu không có) để shell bên trong chạy lại integration của IDE. Chỉ đổi `ZDOTDIR` sau khi mọi điều kiện (kể cả kiểm tra `probe`) đã đạt, nên khi không bọc thì `ZDOTDIR` và các biến của người dùng không bị đụng tới; khối không để lại biến phụ `__shellx_*` nào khi không bọc. bash loại trừ hai IDE này như trên.
- **Giới hạn đã biết:**
  - `bash -i script` vẫn bị bọc (zsh xử lý bằng `$ZSH_SCRIPT`); đây vẫn là chỗ hở. `source ~/.zshrc` / `. ~/.bashrc` gõ tay thì **đã xử lý cho cả hai shell**.
  - Điều kiện `BASH_LINENO[0] == 0` của bash có hai giới hạn: (1) hàm bọc một dòng, vd `reload() { . ~/.bashrc; }`, vẫn làm `BASH_LINENO[0]` bằng `0`, nên vẫn thay shell đang chạy; (2) file rc được `source` từ một file khởi động khác thì **không được bọc** (`BASH_LINENO[0]` khác `0`). Hệ quả: người dùng chỉ có `.profile` + `.bashrc` sẽ có cửa sổ login không được bọc; bộ cài P4 vì vậy đặt khối vào **cả `.bash_profile` và `.bashrc`**.
  - **Mọi PTY khởi động từ một cửa sổ đã bọc** (`script`, `asciinema rec`, `:terminal` của nvim, một ứng dụng terminal mở bằng `code .`) cho shell của nó một tty mới, khác `SHELLX_TERM`, nên shell đó **được bọc riêng và hiện thành một terminal chia sẻ thêm**. Đây là chủ ý của dấu theo tty.
  - Khối cần một binary có lệnh `probe`. Bản `shellx-term` cũ hơn (chỉ có `--version`) gặp khối mới thì `probe` rơi vào nhánh đối số lạ và mở shell thường bên trong `$(…)`, trông như treo; vì vậy bộ cài (P4) cài binary trước rồi mới ghi khối.

### 5.3 Khối tích hợp trên Windows (PowerShell 7 và 5.1)

Khối nằm ở đầu profile `CurrentUserAllHosts` của từng bản PowerShell, chỉ gồm ký tự ASCII (Windows PowerShell 5.1 đọc file không BOM theo bảng mã hệ thống). Nó chạy khi:

- `$Host.Name -eq 'ConsoleHost'` (loại trừ ISE và PowerShell Extension của VS Code);
- stdin và stdout không bị chuyển hướng (`[Console]::IsInputRedirected`, `IsOutputRedirected`);
- mọi đối số của PowerShell nằm trong **danh sách cho phép** `-NoLogo`, `-NoProfile`, `-NoProfileLoadTime`, `-NoExit`, `-Login`, `-l` (không phân biệt hoa thường); đối số nào khác (`-Command`, `-File`, `-EncodedCommand`, `-NonInteractive`, tên script, kể cả dạng viết tắt…) thì không bọc. Danh sách cho phép thay cho danh sách cấm ban đầu: không cần đoán hết các dạng viết tắt;
- `Get-History -Count 1` rỗng: khối chỉ bọc ở lần khởi động đầu của phiên. `. $PROFILE` gõ tay sau đó (đã có lịch sử lệnh) không bọc, nên không lồng thêm một lớp `shellx-term`;
- `SHELLX_TERM` và `SHELLX` rỗng;
- file `%LOCALAPPDATA%\ShellX\bin\shellx-term.exe` tồn tại.

`SHELLX_TERM` của shell bên trong là `conpty:<pid>` (pid của `shellx-term`). **Giới hạn:** Windows không có kiểm tra theo tty như macOS (§5.2); biến này được thừa kế, nên một ứng dụng terminal mở từ cửa sổ PowerShell đã bọc (vd `code .`) không bọc terminal của chính nó.

Windows không thay tiến trình tại chỗ được, nên PowerShell ngoài đặt `$global:LASTEXITCODE = 222` trước, chạy `shellx-term wrap -- <(Get-Process -Id $PID).Path> -NoLogo` (`catch` rỗng), chờ, rồi gọi `[Environment]::Exit($LASTEXITCODE)` **chỉ khi mã khác 222 và không âm**. Mã **222** nghĩa là "không bọc được". Mã **âm** (tiến trình sập, hoặc trình nạp lỗi như thiếu `VCRUNTIME140.dll`) được coi như 222: profile chạy tiếp như bình thường và người dùng dùng PowerShell ngoài. Cuối cùng khối gỡ `LASTEXITCODE`. (Nếu chính shell bên trong thoát với mã 222 hoặc mã âm, người dùng rơi về PowerShell ngoài thay vì cửa sổ đóng. Hiếm và vô hại, ghi nhận.)

**Cái giá trên Windows:** mỗi cửa sổ PowerShell có thêm một tiến trình PowerShell đứng chờ (mở chậm hơn khoảng 0,3–1 giây, tốn thêm khoảng 60–80 MB RAM). Con số thật đo trong lần kiểm tra Windows.

`shellx-term` trên Windows (`term/src/wincon.rs`, `term/src/winwrap.rs`):
- **Chế độ console VT thô.** Stdin: tắt `ENABLE_PROCESSED_INPUT`/`LINE_INPUT`/`ECHO_INPUT`/`MOUSE_INPUT`, bật `ENABLE_VIRTUAL_TERMINAL_INPUT` và `ENABLE_WINDOW_INPUT`; Ctrl+C đi vào shell bên trong như một ký tự thay vì tín hiệu. Stdout: bật `ENABLE_PROCESSED_OUTPUT`, `ENABLE_VIRTUAL_TERMINAL_PROCESSING` và `DISABLE_NEWLINE_AUTO_RETURN`.
- **Input** đọc bằng `ReadConsoleInputW` (phím, kể cả ký tự tiếng Việt từ IME, lẫn sự kiện đổi kích thước). Cặp surrogate UTF-16 được ghép lại qua nhiều sự kiện. Nhả phím Alt mang theo một ký tự được tính là một lần gõ, vì ký tự gõ bằng Alt+bàn phím số đến theo cách đó.
- **Output** ghi bằng `WriteConsoleW` (UTF-16); UTF-8 bị cắt giữa hai lần đọc được xử lý.
- **Kích thước cửa sổ** lấy từ `WINDOW_BUFFER_SIZE_EVENT` **và** kiểm lại mỗi 250 ms: conhost cổ điển chỉ báo đổi cỡ buffer, nên đổi chiều cao khi scrollback dài không có sự kiện.
- **Bộ xử lý đóng** (close handler) khôi phục console. **Mất console** thì giết shell bên trong. **Panic** ngoài luồng link khôi phục console và thoát với mã 222.
- **Khi thoát**, bước xả output chờ đủ **500 ms**, vì ống ConPTY chỉ đóng cùng pseudoconsole (mỗi lần thoát trên Windows thêm khoảng 0,5 s).
- Tạo ConPTY bên trong qua `portable-pty`.

**Giới hạn đã biết (P2b):**
- Không có kiểm tra theo tty (xem trên).
- Shell bên trong thoát với 222 hoặc mã âm thì rơi về shell ngoài.
- Tích hợp PowerShell của VS Code (`-NoExit -Command …`) không được bọc.
- Ctrl+Space / Ctrl+@ (NUL) chưa tới shell bên trong, nên `MenuComplete` của PSReadLine chưa dùng được.
- Mỗi lần thoát chậm thêm khoảng 0,5 s (bước xả).
- Việc cho P4: dựng `shellx-term.exe` với `+crt-static` để không phụ thuộc VCRUNTIME.

### 5.4 Cam kết an toàn

1. **Terminal không bao giờ chờ ShellX.** Luồng chính chỉ chuyển dữ liệu giữa cửa sổ và PTY. Bản sao gửi agent đi qua hàng chờ giới hạn **1 MiB**. Hàng chờ đầy thì cắt kết nối với agent, kết nối lại sau và gửi lại bộ đệm (§6.5). Ghi input từ điện thoại vào PTY chạy trên luồng riêng.
2. **Không mở được PTY hay không chạy được shell trong PTY** (và cả khi đối số không hợp lệ, hoặc panic): macOS `exec` thẳng một shell thường, thử lần lượt shell được yêu cầu, `$SHELL`, `/bin/zsh`, `/bin/sh` (chỉ đường dẫn tuyệt đối), với `argv[0]` như login(1) (`-zsh` nếu là login); Windows thoát với mã 222 (§5.3). Shell thường này nhận `SHELLX_TERM` = **tty của chính cửa sổ** (`0` nếu không có tty), để khối trong file khởi động của nó thấy mình đã ở đúng cửa sổ và không gửi ngược về `shellx-term`. Người dùng vẫn có shell, chỉ không chia sẻ.
3. **Agent không chạy:** `shellx-term` chạy bình thường và thử kết nối lại theo lịch 1, 2, 4, 8, rồi mỗi 10 giây (§6.5). Mỗi lần thử chỉ đọc file `endpoint` rồi kết nối tới localhost.
4. **`shellx-term` bị xóa:** khối tích hợp kiểm tra file tồn tại trước khi dùng.
5. **Shell thoát:** `shellx-term` khôi phục chế độ cửa sổ rồi thoát với mã thoát của shell. **Cửa sổ biến mất** (đọc cửa sổ gặp EOF hoặc lỗi, vd ứng dụng terminal bị kill mà SIGHUP không tới `shellx-term`): `shellx-term` gửi SIGHUP cho nhóm tiến trình của shell bên trong rồi cho chính shell, sau đó đi theo đường thoát bình thường; không để lại tiến trình mồ côi.
6. **Chế độ cửa sổ luôn được khôi phục** (termios / console mode ban đầu) khi thoát bình thường, khi nhận tín hiệu kết thúc, và khi panic (panic hook, chỉ cài cho chế độ `wrap`; trên Windows panic ngoài luồng link cũng khôi phục console rồi thoát 222, §5.3). **SIGTERM:** shell tương tác thường bỏ qua SIGTERM, nhưng zsh/bash đặt lại SIGTERM về mặc định trước khi `exec` (đã đo trên macOS), nên `shellx-term` do khối gọi sẽ thấy SIGTERM ở trạng thái mặc định. Vì vậy: khi `shellx-term` được gọi theo cách của khối (không đối số + `SHELLX_TERM_WRAP`, §5.1) thì nó **luôn bỏ qua SIGTERM**, giống shell tương tác mà nó thay; nhờ đó `pkill -f zsh` không đóng cửa sổ đã bọc (có test PTY với `kill -TERM` từ shell bên trong, cho cả zsh và bash). Khi gọi tường minh bằng `wrap …` thì **giữ nguyên trạng thái lúc khởi động**: đang bị bỏ qua thì tiếp tục bỏ qua; ngược lại SIGTERM khôi phục cửa sổ rồi thoát với mã `128+SIGTERM`. **Trước khi `exec` shell dự phòng**, SIGTERM được trả về đúng trạng thái lúc tiến trình khởi động (P2b Task 1), để shell dự phòng và các tiến trình con không thừa hưởng SIGTERM đang bị bỏ qua.
7. **Bàn phím và kích thước:** Ctrl+C, Ctrl+Z, Ctrl+D đi thẳng vào shell bên trong. Đổi kích thước cửa sổ được chuyển tiếp: macOS qua `SIGWINCH`, Windows qua `WINDOW_BUFFER_SIZE_EVENT` và kiểm lại mỗi 250 ms (§5.3). Tiêu đề do shell hoặc chương trình đặt (OSC 0/2) đi qua nguyên vẹn ra cửa sổ.
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
  - macOS: `$HOME/Library/Application Support/ShellX/term/endpoint`; thư mục 0700, file 0600.
  - Windows: `%LOCALAPPDATA%\ShellX\term\endpoint` (quyền thừa kế của `%LOCALAPPDATA%`: chỉ người dùng, SYSTEM, Administrators).
- Tắt tính năng hoặc thoát agent: đóng cổng và xóa file `endpoint`.
- **Định dạng file:** văn bản UTF-8, đúng ba dòng, cho phép một dấu xuống dòng ở cuối:
  ```
  v=1
  port=<số thập phân 1..65535>
  secret=<64 ký tự hex thường>
  ```
  `port` viết thập phân thuần, không số 0 đứng đầu. Dòng đầu `v=` khác `v=1` là phiên bản không hỗ trợ; dòng sai, thừa hoặc thiếu, `port` ngoài khoảng, `secret` không phải 64 hex thường, hay file không phải UTF-8 là sai định dạng. Cả ba trường hợp (và file không tồn tại) đều làm lần kết nối đó thất bại và `shellx-term` thử lại theo lịch §6.5.
- `shellx-term` đọc lại file ở mỗi lần kết nối.

### 6.2 Khung

Mỗi khung là độ dài 4 byte big-endian + một map CBOR có khóa `t` (cùng quy ước với tin nhắn ứng dụng hiện có). Khung tối đa 64 KiB (`65536` byte payload); `snapshot` và `out` được chia thành các phần `data` **tối đa 60 KiB** (`61440` byte) mỗi khung. Nhận khung sai định dạng hoặc quá lớn thì đóng kết nối.

- **Thứ tự khóa CBOR:** `shellx-term` ghi khóa map theo **thứ tự byte tăng dần** (bên Rust dùng `BTreeMap`). Đây **không phải** thứ tự chuẩn "độ dài trước" của RFC 8949 §4.2.1: vd `hello` ghi `nonce`, `t`, `v` (theo byte), trong khi thứ tự chuẩn sẽ là `t`, `v`, `nonce`. Bộ giải mã **chấp nhận mọi thứ tự khóa**; chỉ khi muốn khớp **từng byte** với `term/protocol/vectors.txt` thì bên ghi (agent, P3) mới phải dùng đúng thứ tự khóa này. Số nguyên và độ dài được ghi ở dạng ngắn nhất; bộ giải mã không bắt buộc dạng ngắn nhất.

### 6.3 Xác thực hai chiều

1. `shellx-term` → agent: `{t: "hello", v: 1, nonce: 32 byte}`.
2. agent → `shellx-term`: `{t: "challenge", nonce: 32 byte, mac: HMAC-SHA256(khóa, "shellx-term/agent" ‖ nonce_term ‖ nonce_agent)}`. **Agent có thể trả `{t: "reject", reason}` thay cho `challenge`** (vd khi quá giới hạn hoặc không biết phiên bản); xem lưu ý về độ tin cậy bên dưới.
3. `shellx-term` kiểm `mac` (so sánh thời gian hằng). Sai thì đóng và **chưa gửi byte terminal nào**.
4. `shellx-term` → agent: `{t: "auth", mac: HMAC-SHA256(khóa, "shellx-term/term" ‖ nonce_agent ‖ nonce_term), term_id: 16 byte, app, shell, pid, cols, rows, started_at}`.
5. Agent kiểm `mac`, rồi trả `{t: "ready"}`, hoặc `{t: "reject", reason: "limit" | "version"}` và đóng.

- Byte chuẩn của từng tin nhắn và hai `mac` (với khóa và nonce cố định) nằm ở `term/protocol/vectors.txt`. **Plan P3 phải khớp từng byte** các vector này (thứ tự khóa: §6.2).
- `v` là phiên bản giao thức nội bộ. Agent chấp nhận mọi phiên bản nó biết, để terminal mở từ trước khi cập nhật ShellX vẫn nối được. Bị `reject` với `version` thì `shellx-term` ngừng thử cho tới khi **nội dung** file `endpoint` đổi (đọc lại mỗi 10 giây, §6.5). Bị `limit` thì thử lại sau 30 giây. Lý do khác (không biết) thì thử lại theo lịch 1, 2, 4, 8, 10 giây.
- **Hạn 5 giây** cho cả bắt tay tính trên **từng byte đọc hoặc ghi**, không chỉ từng lời gọi hệ thống: một bên nhỏ giọt từng byte cũng không giữ được quá 5 giây. Quá hạn thì đóng.
- **`reject` trước khi agent chứng minh khóa là chưa xác thực nhưng vẫn được chấp nhận:** kẻ chiếm cổng chỉ làm chậm việc chia sẻ (chiếm cổng vốn đã làm được vậy) và **không bao giờ nhận byte terminal nào**, vì lúc đó mới chỉ có `hello` rời đi.
- **Các trường của `auth`:**
  - `term_id`: 16 byte ngẫu nhiên, sinh một lần cho mỗi cửa sổ và giữ nguyên qua các lần nối lại.
  - `pid`: PID của **shell bên trong** (không phải của `shellx-term`).
  - `started_at`: Unix mili giây lúc `shellx-term` bắt đầu.
  - `shell`: tên shell (vd `zsh`); `cols`, `rows`: kích thước cửa sổ lúc đó.
  - `app`: tên ứng dụng terminal, rỗng nếu không biết. macOS lấy theo thứ tự: (1) `__CFBundleIdentifier` tra bảng dưới; (2) `TERM_PROGRAM`: `Apple_Terminal` → Terminal, `iTerm.app` → iTerm2, `vscode` → VS Code, `WarpTerminal` → Warp, `ghostty` → Ghostty, `WezTerm` → WezTerm, giá trị lạ khác được dùng nguyên văn; (3) `TERMINAL_EMULATOR=JetBrains-JediTerm` → JetBrains. Windows: `WT_SESSION` có mặt thì là Windows Terminal (làm ở P2b).

| `__CFBundleIdentifier` | `app` |
|---|---|
| `com.apple.Terminal` | Terminal |
| `com.googlecode.iterm2` | iTerm2 |
| `com.microsoft.VSCode` | VS Code |
| `com.microsoft.VSCodeInsiders` | VS Code Insiders |
| `com.todesktop.230313mzl4w4u92` | Cursor |
| `com.google.android.studio` | Android Studio |
| `com.jetbrains.intellij` | IntelliJ IDEA |
| `com.jetbrains.intellij.ce` | IntelliJ IDEA CE |
| `dev.warp.Warp-Stable` | Warp |
| `com.mitchellh.ghostty` | Ghostty |
| `net.kovidgoyal.kitty` | kitty |
| `org.alacritty` | Alacritty |
| `com.github.wez.wezterm` | WezTerm |

### 6.4 Tin nhắn sau `ready`

| Hướng | `t` | Trường | Ý nghĩa |
|---|---|---|---|
| term → agent | `snapshot` | `data`, `last` | Bộ đệm 256 KiB (hoặc ít hơn), gửi thành các phần `data` ≤ 60 KiB; `last: true` ở phần cuối. Luôn là khung đầu tiên sau `ready`. Chưa có output thì gửi **một** khung `data` rỗng với `last: true` |
| term → agent | `out` | `data` | Output mới, cũng chia thành các phần ≤ 60 KiB |
| term → agent | `size` | `cols`, `rows` | Kích thước cửa sổ đổi |
| term → agent | `local` | — | Bên điều khiển chuyển về `desktop` (§5.5) |
| term → agent | `exit` | `code` | Shell đã thoát |
| agent → term | `in` | `data` | Input từ điện thoại |
| agent → term | `resize` | `cols`, `rows` | Kích thước điện thoại, bên điều khiển thành `phone` |
| agent → term | `local_size` | — | Về kích thước cửa sổ |

### 6.5 Mất kết nối và nối lại

- `shellx-term` nối lại với **cùng `term_id`**, gửi `snapshot` mới (luôn đứng đầu sau `ready`; phần output chưa gửi của phiên cũ bị bỏ, vì snapshot đã chứa nó).
- **Lịch thử lại:** sau mỗi lần thất bại (không đọc được `endpoint`, không nối được, bắt tay lỗi hoặc hết hạn 5 giây) chờ 1, 2, 4, 8 rồi 10 giây cho các lần sau; thành công thì lịch quay về đầu. Sau một phiên bị ngắt, chờ 1 giây trước lần nối kế tiếp. `reject limit`: thử lại sau **30 giây**. `reject version`: **không** thử cho tới khi nội dung `endpoint` đổi; đọc lại file **mỗi 10 giây**.
- **Không bao giờ làm chậm terminal:**
  - ghi vào socket có hạn **1 giây**;
  - hàng chờ gửi giới hạn **1 MiB** byte đã mã hóa;
  - agent treo (nhận kết nối nhưng ngừng đọc) làm phiên bị cắt khi một lần ghi quá hạn 1 giây **hoặc** hàng chờ tràn 1 MiB; phiên sau đó được nối lại và đồng bộ bằng `snapshot`;
  - đường cửa sổ ↔ PTY không bao giờ chờ socket.
- **Khi shell thoát:** gửi `exit` rồi chờ đẩy xong tối đa **200 ms** (cộng 500 ms xả output như trước); agent treo hoặc không có thì cửa sổ vẫn đóng ngay sau đó.
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

### 7.7 Cấu trúc trong agent (P3, chốt 2026-10-05)

Phiên `desktop` **không** đi qua `SessionManager` hiện có. Phần chung được rút ra một lớp riêng; mỗi loại phiên có bộ quản lý của mình (quyết định T13). Mọi thành phần nằm trong `packages/shellx_agent`.

| Thành phần | Việc | Phụ thuộc |
|---|---|---|
| `SessionStream` (rút từ `SessionManager`) | Bộ đệm vòng, `sent`/`acked`, đẩy dữ liệu theo cửa sổ gửi, gắn, gắn lại, phát lại, `session.reset`, `taken_over`. Không biết shell hay `shellx-term` | `RingBuffer` |
| `SessionManager` | Phiên `shellx`, hành vi **không đổi**: mở shell, tắt, giới hạn 10 | `SessionStream`, `PtyFactory` |
| `DesktopSessionManager` (mới) | Phiên `desktop`: nhận `TermLink` đã xác thực, giữ 30 giây chờ nối lại, bên điều khiển, tiêu đề, giới hạn 32. **Không có hàm tắt terminal nào** | `SessionStream` |
| `TermServer` (mới) | `ServerSocket` trên `127.0.0.1`, ghi/xóa `endpoint`, bắt tay §6.3, `reject`. Đưa ra `TermLink` đã xác thực. `start()` / `stop()`; `running` là giá trị `desktop_sharing` | codec, `cryptography` |
| Codec kết nối nội bộ (mới) | Khung §6.2, tin nhắn §6.3–§6.4; ghi khóa map theo thứ tự byte; khớp từng byte `term/protocol/vectors.txt` | CBOR của `shellx_core` |
| `SessionRouter` (mới) | Thay `SessionManager` trong `AgentService`: chuyển tin nhắn theo `id` phiên, gộp `session.list`, một bộ cấp `id` chung cho hai bộ quản lý (không bao giờ trùng `id`), gộp `outbound`/`changes` | hai bộ quản lý |

- `shellx_core`: trường và tin nhắn §8. `shellx_client`: API giao thức tương ứng (liệt kê có `desktop: true`, `session.detach`, `session.driver`, `terminal_gone`) để e2e đóng vai điện thoại; giao diện để P5.
- `apps/desktop`: chỉ đổi chỗ nối `AgentService` ↔ `SessionRouter`. Công tắc, menu, thông báo §7.6 thuộc P4; P3 đưa ra API cho chúng (danh sách phiên `desktop` kèm `app`/`title`/điện thoại đang gắn, "ngắt điện thoại" theo `id`, `TermServer.start/stop`).
- **Các đường "tắt" (§7.2) qua `SessionRouter`:** thu hồi điện thoại, `closeAll`, thoát app → phiên `shellx` bị tắt như cũ; phiên `desktop` chỉ bị ngắt điện thoại (`session.detached {closed_by_host}` nếu kênh còn). `session.close` gửi tới `id` của phiên `desktop` = `session.detach`.

### 7.8 Luồng dữ liệu phía agent (P3)

**Kết nối mới.**
1. `hello` có `v` lạ → `reject version` ngay (trước khi tính HMAC). Ngược lại → `challenge`.
2. `auth` → kiểm `mac` (so sánh thời gian hằng). Hạn 5 giây cho cả bắt tay, tính trên từng byte đọc/ghi (§6.3).
3. Giới hạn 32 được kiểm **ở bước `auth`**, khi đã biết `term_id`: terminal đang nối lại (cùng `term_id` với phiên đang chờ 30 giây) **không bao giờ bị `reject limit`**. Phiên đang chờ vẫn tính vào giới hạn.
4. `ready`, rồi giao `TermLink` cho `DesktopSessionManager`.

**Gắn kết nối vào phiên.** `term_id` mới → phiên mới (`id` từ bộ cấp chung, `index` theo dãy riêng). `term_id` trùng phiên đang chờ → dùng lại phiên (giữ `id`), hủy hẹn giờ. `term_id` trùng phiên **còn kết nối** (kết nối cũ treo nửa vời) → kết nối mới thắng, đóng kết nối cũ.

**Snapshot.** Agent gom các phần tới `last: true` rồi mới áp vào phiên, nên điện thoại không bao giờ thấy snapshot dở dang; tổng vượt 256 KiB là vi phạm giao thức (đóng kết nối). Lần đầu: bộ đệm bắt đầu từ 0 với nội dung snapshot. Nối lại: bộ đệm **thay bằng snapshot, số thứ tự đi tiếp** (`RingBuffer.restartWith(bytes)`: vùng hợp lệ thành `[end cũ, end cũ + độ dài snapshot)`); điện thoại đang gắn nhận `session.reset` rồi dữ liệu từ đầu vùng mới. Sau đó, nếu bên điều khiển là `phone`, agent **gửi lại `resize`**: `shellx-term` tự về kích thước cửa sổ khi mất kết nối (`term/src/size.rs`).

**Trong lúc chạy.**
- `out` → bộ đệm → điện thoại theo cửa sổ gửi/ack như phiên `shellx`. Agent luôn đọc socket; điện thoại chậm thì nhận `session.reset`.
- Điện thoại `session.attach` / `input` / `resize`: bên điều khiển là `desktop` hoặc kích thước khác → `resize` cho `shellx-term`, bên điều khiển = `phone`, `session.driver {phone}` cho điện thoại. Mẹo "giảm một dòng" do `shellx-term` làm (§5.5), agent không làm lại.
- `local` → bên điều khiển = `desktop`, `session.driver {desktop}` cho điện thoại đang gắn.
- Điện thoại rời, bị ngắt hoặc mất kênh → `local_size`, bên điều khiển = `desktop`.
- Ghi sang `shellx-term` (`in`, `resize`, `local_size`) không bao giờ chặn agent; hàng chờ ghi vượt 1 MiB → đóng kết nối (`shellx-term` tự nối lại và gửi snapshot).

**Tiêu đề.** Bộ đọc OSC 0/2 chạy liên tục trên `snapshot` và `out`, chịu chuỗi bị cắt giữa hai khung, giữ tiêu đề mới nhất ≤ 200 ký tự. Nối lại mà snapshot không có tiêu đề nào thì giữ tiêu đề cũ.

**Kết thúc.**
- `exit {code}` → phiên đang đóng, xả bộ đệm cho điện thoại rồi `session.exited` (logic drain hiện có của `SessionStream`).
- Mất kết nối không có `exit` → phiên vẫn hiện trong danh sách, điện thoại vẫn gắn, **input bị bỏ (không xếp hàng)**; hẹn giờ 30 giây. Hết giờ → xóa phiên, `session.detached {terminal_gone}` cho điện thoại đang gắn.

### 7.9 Lỗi và tương thích phía agent (P3)

**Máy chủ nội bộ.**
- `start()` không mở được cổng → ném lỗi, không ghi `endpoint` (P4 báo lỗi và để công tắc tắt).
- **`endpoint` (macOS):** tạo thư mục với quyền 0700; ghi file tạm, đặt quyền 0600 **trước khi ghi khóa** vào, rồi đổi tên. Windows: quyền thừa kế (§6.1).
- `stop()`: đóng cổng và mọi kết nối, xóa `endpoint` **chỉ khi nội dung vẫn là của lần `start()` này**. Mọi phiên `desktop` bị xóa ngay (không chờ 30 giây); điện thoại đang gắn nhận `session.detached {closed_by_host}`. Terminal không bị đụng tới; `shellx-term` tiếp tục thử nối lại theo §6.5.
- Khung sai định dạng hoặc quá lớn, sai `mac`, hết hạn bắt tay, khung sai thứ tự sau `ready` (vd `out` trước khi snapshot xong, hai snapshot) → đóng kết nối đó. Trước `ready` thì không có phiên nào; sau `ready` thì phiên vào trạng thái chờ 30 giây.
- Log của agent không bao giờ ghi khóa, `mac`, nonce hay byte terminal.
- **Agent khởi động lại** → khóa mới, `shellx-term` nối lại với khóa mới; agent không còn nhớ `term_id` nên tạo phiên mới (`id` mới). Điện thoại gắn lại `id` cũ nhận `session_not_found` như phiên `shellx` hiện nay. Chấp nhận.

**Tin nhắn từ điện thoại.**
- Agent ghi nhớ theo từng kênh việc điện thoại đã gửi `session.list {desktop: true}`. Điện thoại chưa gửi thì **không được gắn vào phiên `desktop`** (`session_not_found`), nên không bao giờ nhận `session.driver` hay `terminal_gone` mà bộ giải mã cũ từ chối. Cờ mất cùng kênh.
- `session.detach` cho `id` không tồn tại hoặc là phiên `shellx` → bỏ qua (tin nhắn này không có trả lời).
- `input`/`resize` cho phiên `desktop` đang mất kết nối → bỏ.

**Bộ giải mã mới (`shellx_core`).** `SessionInfo` có `kind` lạ (không phải `desktop`) thì **bỏ qua mục đó** thay vì ném lỗi cả danh sách, để agent sau này thêm loại phiên mà không làm hỏng app mobile mới. Mọi trường mới là tùy chọn.

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

1. Người dùng bật công tắc → cửa sổ xác nhận liệt kê **chính xác các file sẽ sửa hoặc tạo**, giới hạn (chỉ terminal mở sau khi bật), và trên Windows là trạng thái chính sách script (§10.3). Trên macOS, cửa sổ xác nhận còn nói rõ: **đóng một cửa sổ terminal đang chạy lệnh sẽ không còn được Terminal.app (và có thể iTerm2) hỏi xác nhận**, vì lệnh chạy bên trong `shellx-term` (§13 R2, người dùng chọn phương án (a) ngày 2026-10-01).
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
- **Thông báo:** thông báo gắn vào bị giới hạn tần suất (P4, cùng phần giao diện §7.6).
- **Bổ sung P3 (§7.7–§7.9):**
  - Refactor `SessionStream`: **mọi test agent hiện có chạy xanh mà không sửa nội dung test** (chỉ được đổi chỗ khởi tạo); đó là bằng chứng hành vi phiên `shellx` không đổi.
  - Codec: mã hóa từng tin nhắn khớp **từng byte** mỗi dòng `term.*`/`agent.*` của `vectors.txt`, giải mã ngược lại; hai `mac` khớp `auth.*_proof`.
  - `TermServer` với socket thật: quyền file `endpoint` (macOS), `stop()` không xóa `endpoint` của lần `start()` khác, nối lại không bị `reject limit`, kết nối cũ treo bị kết nối mới cùng `term_id` thay.
  - `DesktopSessionManager` với `TermLink` giả và `fake_async`: snapshot nhiều phần, `restartWith` + `session.reset`, gửi lại `resize` sau khi nối lại, input bị bỏ khi mất kết nối, `terminal_gone` đúng 30 giây, điện thoại chưa gửi `desktop: true` không gắn được.
  - `SessionRouter`: `id` không bao giờ trùng giữa hai bộ quản lý; `session.list` có/không có `desktop: true`.

### 11.3 Bộ sửa file cấu hình (Dart)

- Chèn hai lần vẫn chỉ một khối; gỡ khối; giữ nguyên nội dung còn lại.
- Giữ bảng mã (UTF-8, UTF-8 BOM, UTF-16) và kiểu xuống dòng (LF, CRLF).
- Quy tắc bash (không tạo `~/.bash_profile`).
- Sao lưu một lần.
- Hoàn tác khi một bước lỗi.
- Khối chỉ gồm ASCII.

### 11.4 End-to-end (`packages/shellx_e2e`)

- **Qua relay trong bộ nhớ:** điện thoại giả lập ↔ agent ↔ `shellx-term` thật đi trọn luồng: liệt kê, gắn, xem output có từ trước, gõ lệnh, rời, gắn lại, shell thoát.
- **Qua relay thật:** chạy một lần trỏ vào `relay.shellx.pro` (như lần kiểm tra 2026-09-30). **Người dùng tự chạy** bằng lệnh ghi trong plan P3 (T14).
- `shellx-term` thật được build bằng `cargo build` (feature `test-hooks`) ở đầu bộ test e2e; thiếu `cargo` thì bộ test **báo lỗi rõ**, không âm thầm bỏ qua. `HOME` tạm cho cả agent lẫn `shellx-term`, nên `endpoint` không đụng thư mục thật của người dùng.

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
  - Workflow `.github/workflows/windows-check.yml`, kích hoạt bằng `workflow_dispatch` **và** push lên nhánh `windows-check/**`. `workflow_dispatch` chỉ dùng được khi file đã nằm trên nhánh mặc định.
  - **Phạm vi trong P2b:** chỉ `term/` (`cargo fmt --check`, `clippy`, `test`, gồm ConPTY thật), trên `windows-latest` và `macos-latest`. P3 và P4 thêm các bước còn lại:
    - `dart test` cho `packages/shellx_agent` và `packages/shellx_core`;
    - `flutter build windows` để xác nhận `shellx-term.exe` nằm trong bản build.
  - Không chạy theo push thường; giữ quyết định "không CI".
  - Kiểm tra tương tác (§11.6, phần Windows) vẫn là **việc chờ**, ghi vào HANDOFF §4.
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

**Kết quả P1 (2026-10-01; chi tiết và số đo trong `docs/superpowers/ledgers/terminal-sharing.md`):**

- **R1 — đã xử lý.**
  - Cursor/VS Code và Android Studio mất integration khi bị bọc (giả lập bằng chính script của hai IDE).
  - Cách sửa: khối zsh trỏ `ZDOTDIR` về `$VSCODE_ZDOTDIR` hoặc `$_INTELLIJ_ZDOTDIR` trước khi `exec`; khối bash loại trừ hai IDE này (§5.2).
  - Còn chờ người thử trên giao diện thật.
- **R2 — một phần.**
  - Bọc chạy đúng trên Terminal.app thật, với cả khối đầu lẫn khối cuối. Với khối cuối: PATH giống hệt, `source` bằng tay không thay shell, file `shellx-term` hỏng thì cửa sổ vẫn mở bình thường.
  - Tiêu đề thành `shellx-term wrap -- … ▸ <lệnh>`. Đã cài ở P2a: tham số qua biến môi trường và `exec -a` với `argv[0]` y nguyên của shell gốc (§5.1, §5.2), nhưng **vẫn cần kiểm tra tay trong cửa sổ Terminal.app/iTerm2 thật** xem tiêu đề đã đúng chưa.
  - **Mất cảnh báo "terminate running processes?" khi đóng cửa sổ đang chạy lệnh.** Đây là giới hạn của hướng A: Terminal chỉ xét tiến trình trên tty của cửa sổ. **Người dùng chọn (a): chấp nhận và ghi rõ trong cửa sổ xác nhận (§10.1).**
  - Không có chuyện hỏi thừa khi shell đang rảnh.
- **R3 — đạt.** Shell bên trong không phải login: +13,2 ms và PATH giống hệt cửa sổ thường; dạng login: +35,9 ms và PATH đổi thứ tự (số đo từ bản bench đầu, trước bước kiểm tra `--version`). Bước kiểm tra `--version` thêm khoảng 2,4 ms. Cái giá của shell bên trong không phải login: `~/.zlogin` và thiết lập không phải biến môi trường trong `~/.zprofile` không áp dụng; `logout` báo "not login shell"; `[[ -o login ]]` là sai cho logic rc của người dùng. **Đã xử lý ở P2a:** biến `SHELLX_TERM_LOGIN` + `setopt login` trong shell bên trong, nên các cái giá này không còn (§5.2). Số đo cuối của P2a: xem ledger.
- **Phát hiện thêm:** zsh thoát khi `exec` thất bại, nên khối chạy `shellx-term probe` trước khi `exec` (§5.2).

---

## 14. Chia kế hoạch triển khai

Khối lượng lớn, chia thành các kế hoạch nối tiếp; mỗi kế hoạch kết thúc bằng review và merge vào nhánh tích hợp như các plan v1.

| # | Kế hoạch | Phụ thuộc | Kết quả kiểm được |
|---|---|---|---|
| P1 | Bản thử `shellx-term` trên macOS (chỉ bọc shell) + kiểm R1–R3 | — | Báo cáo tương thích, danh sách loại trừ, số đo thời gian mở; quyết định tiếp tục hoặc điều chỉnh thiết kế |
| P2a | `shellx-term` nối agent trên macOS: §5, §6 phía term, test §11.1 (**xong**, ledger `terminal-sharing.md`) | P1 | `cargo test --features test-hooks` xanh trên macOS |
| P2b | `shellx-term` trên Windows (§5.3) + workflow `windows-check.yml` (code xong, chờ CI Windows) | P2a | `cargo test` xanh trên `windows-latest` |
| P3 | Agent + giao thức: §6 phía agent, §7.1–7.5, §7.7–7.9, §8, test §11.2, e2e §11.4; thêm `dart test` của `shellx_agent` và `shellx_core` vào `windows-check.yml` (§12). Nhánh `feat/terminal-sharing-p3`, tách từ `origin/windows-check/p2b` | P2a | e2e điện thoại giả lập ↔ agent ↔ `shellx-term` thật |
| P4 | Desktop: bật/tắt, bộ sửa file cấu hình, chính sách PowerShell, cập nhật/gỡ, menu và thông báo (§7.6, §10), tích hợp build và ký (§4, §10.7), test §11.3 | P3 | Bật trên macOS từ menu, mở cửa sổ mới thấy trên điện thoại giả lập |
| P5 | Mobile: §9, cập nhật file thiết kế giao diện, test §11.5 | P3 (chạy song song với P4 được) | Pixel 3 xem và gõ vào terminal Terminal.app qua `relay.shellx.pro`; danh sách §11.6 phần macOS |
