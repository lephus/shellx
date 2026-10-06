# A8 — Workspace SSH và gắn tmux trên desktop — Đặc tả thiết kế

- **Ngày:** 2026-10-07
- **Trạng thái:** Người dùng giao toàn quyền cho người viết spec (như A1–A7). Yêu cầu phạm vi S1–S7 do người dùng nêu (ràng buộc); D1–D44 do người viết spec chốt trong phạm vi S1–S7. Tất cả ghi ở bảng §2 kèm cái giá nếu sai.
- **Lộ trình:** A1 → A2 → A4 → A3 → A5a → A5b → A6 → A7 → **A8 (tài liệu này)** → A9 phím tắt tuỳ biến, file cấu hình.
- **Thứ tự thực thi:** A8 chạy **sau khi A3, A4, A5a, A6 và A7 đã merge vào `main`** (D1). **A5b tuỳ chọn**: plan rẽ nhánh ở các bước codec mux (D31). Plan: `docs/superpowers/plans/2026-10-07-desktop-ssh-a8.md`. UI addendum: `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a8.md`.
- **Giữ nguyên:** spec A1 (D1–D16), A2 (C1–C8, D1–D19), A4 (N1–N9, D1–D27), A3 (P1–P9, D1–D30), A5a (R0–R8, D1–D26), A5b (B1–B9, D1–D30), A6 (W1–W7, D1–D38), A7 (C1–C7, D1–D40 + sửa đổi "chỉ shell của ShellX"), spec chia sẻ terminal (`2026-10-01`), spec push (`2026-10-05`). Protocol điện thoại (`shellx_core` `AppMessage`), app mobile, relay **không đổi**. Tài liệu này chỉ **thêm** và ghi rõ chỗ nào sửa (cuối §2).
- **Ký hiệu:** "A7 D16" = quyết định D16 của spec A7; "S1"/"D1" không tiền tố = của tài liệu này. "Máy chủ" = máy ở xa mà người dùng SSH tới. "Đích" = chuỗi người dùng gõ để chỉ máy chủ (alias trong `~/.ssh/config` hoặc `user@host:port`). "Pane SSH" = pane có phiên chạy `ssh`; "pane tmux" = pane có phiên chạy một client tmux (cục bộ hoặc qua SSH).

---

## 1. Mục tiêu

Như cmux (`cmux ssh`, `cmux ssh-tmux`): **làm việc trên máy chủ như làm việc trên máy mình** — một workspace cho mỗi máy chủ trong sidebar, tab và pane mở thẳng vào máy chủ (⌘T, ⌘D không hỏi lại mật khẩu), sidebar hiện thư mục, nhánh git và cổng đang nghe **trên máy chủ**, bấm cổng là mở được trong trình duyệt của máy mình (chuyển tiếp qua chính kết nối SSH), mất mạng thì pane chờ và **tự kết nối lại**, và gắn được một phiên tmux (trên máy này hay trên máy chủ) thành một tab. ShellX dùng **binary `ssh` của hệ điều hành và agent SSH của người dùng**; ShellX không bao giờ hỏi, giữ hay lưu mật khẩu.

Khác cmux có chủ đích: không triển khai daemon riêng lên máy chủ (chỉ một hook shell nhỏ trong thư mục cache, D10), không proxy SOCKS cho pane trình duyệt (chuyển tiếp từng cổng, D18), không ánh xạ cửa sổ/pane tmux thành tab/pane ShellX (D27 — follow-up A8.1).

### Tiêu chí thành công (đo được)

1. **Kết nối:** ⌘⇧K (Windows Ctrl+Shift+K) → hộp "Kết nối tới máy chủ" → gõ `dev` → gợi ý `devbox` (từ `~/.ssh/config`) → Enter → hộp đóng ngay; sidebar có workspace **"devbox"** (biểu tượng máy chủ) với một tab, chấm nhỏ "đang kết nối"; xác thực bằng khoá trong agent → trong ≤ 2 s (LAN) prompt của máy chủ hiện, chấm thành trạng thái thường, dòng ngữ cảnh hiện `~` (home **từ xa**).
2. **Mật khẩu và host key:** máy chủ chỉ cho mật khẩu → lời nhắc `password:` hiện **trong terminal của pane**, người dùng gõ; lần đầu gặp host → câu hỏi `yes/no` của ssh hiện trong pane. Không có hộp mật khẩu của ShellX; không file/khoá settings nào của ShellX chứa mật khẩu (`grep -r` thư mục app support không thấy chuỗi đã gõ).
3. **Ngữ cảnh từ xa:** trong pane SSH `cd ~/work/api` (repo git nhánh `feat/x`), `python3 -m http.server 8000 &` → trong ≤ 6 s dòng sidebar hiện `feat/x · ~/work/api · :8000`. Bấm `:8000` → trình duyệt hệ thống mở `http://localhost:8000/` hiển thị danh sách thư mục **của máy chủ** (chuyển tiếp qua SSH; nếu 8000 trên máy đang bận thì một cổng khác, tooltip "localhost:53012 → devbox:8000"). ⌥-click → pane trình duyệt A6.
4. **Chia và tab mới:** trong pane SSH đang ở `~/work/api`, ⌘D → pane mới bên phải **trên máy chủ**, ở `~/work/api`, **không hỏi mật khẩu** (macOS: ghép kết nối D7) trong ≤ 500 ms (LAN); ⌘T trong workspace "devbox" → tab SSH mới tới devbox ở home từ xa; ⌘T trong workspace Mặc định → shell cục bộ như A1.
5. **Mất kết nối và kết nối lại:** đang ở pane SSH, tắt Wi-Fi 60 s → trong ≤ 50 s (keepalive 15 s × 3) pane hiện dòng mờ "[Mất kết nối tới devbox] — Enter để kết nối lại" và dải "Mất kết nối tới devbox · Thử lại sau 3 giây" với nút "Kết nối lại"; bật Wi-Fi → pane tự kết nối lại (lùi dần 3, 6, 12, … ≤ 60 s), **cùng chỗ trong cây pane**, nội dung cũ vẫn ở trên vạch "— Đã kết nối lại · 14:32 —", shell mới ở `~/work/api`. Máy ngủ rồi thức → thử lại ngay. Xác thực sai ngay lần đầu (pane "Không kết nối được tới devbox") → **không** tự thử lại.
6. **tmux:** ⌘⇧K → thẻ "tmux" → "Trên: Máy này" liệt kê `tmux ls` (tên, số cửa sổ, "đang gắn ở nơi khác"); chọn `main` → Enter → tab mới "tmux: main" hiện thanh trạng thái tmux; đóng tab → `tmux ls` vẫn có `main` (chỉ tách client). "Trên: devbox" liệt kê phiên tmux của máy chủ (qua kết nối đã có); gắn → tab trong workspace "devbox"; mất mạng → kết nối lại **gắn lại đúng phiên tmux** (chương trình trong tmux vẫn chạy). Ô "Tên phiên mới" + "Tạo và gắn" tạo phiên.
7. **Khôi phục (A5a):** có workspace devbox với tab chia 2 pane SSH (một ở `~/work/api`) và một tab tmux → ⌘Q → mở lại: workspace, cây pane, nội dung cũ + vạch A5a trở lại; mỗi pane SSH **kết nối lại** (đúng thư mục từ xa), tab tmux gắn lại `main`. Máy chủ không vào được → pane "Không kết nối được" với nút "Thử lại", bố cục không mất.
8. **Daemon (A5b, nếu đã merge):** ⌘Q với pane SSH đang chạy `top` → mở lại ShellX → `top` vẫn chạy (phiên SSH sống trong daemon).
9. **CLI (A7):** `p=$(shellx ssh devbox --cwd /srv/app --cmd 'git status')` in id tab; `shellx ls --json` có `remote: {kind: "ssh", host: "devbox", state: "connected"}` trên pane; `shellx tmux ls --host devbox --json`; `shellx tmux attach main` mở tab tmux cục bộ; sau khi pane kết nối lại, `shellx send p<id cũ> --text ls` vẫn tới pane đó.
10. **Điện thoại:** điện thoại thấy pane SSH như một phiên desktop (xem, gõ, driver A1); thư mục hiện dạng `devbox:/home/me/work/api`. Protocol không đổi.
11. **Riêng tư:** chạy toàn bộ tiêu chí 1–10 với log debug bật → log không chứa tên máy, user, cổng, đường dẫn từ xa, tên phiên tmux, lệnh (`grep` chuỗi `devbox`, `work/api`, `main` trên log trả rỗng).
12. **Không hồi quy:** mọi test A1–A7 xanh; shell cục bộ không đổi hành vi (hook cục bộ giữ nguyên byte, A2 D2 cho phiên cục bộ giữ nguyên).

---

## 2. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| S1 | Workspace SSH (yêu cầu) | Máy chủ từ `~/.ssh/config` hoặc `user@host:port`; dùng binary `ssh` và agent của hệ thống; ShellX không lưu mật khẩu | — |
| S2 | Ngữ cảnh từ xa (yêu cầu) | cwd/git/cổng của máy chủ trên sidebar khi khả thi, qua cùng kết nối hoặc hook shell nhỏ phía máy chủ | — |
| S3 | Kết nối lại (yêu cầu) | Có hành vi kết nối lại rõ ràng | — |
| S4 | tmux (yêu cầu) | Liệt kê phiên cục bộ/từ xa, gắn thành tab; ánh xạ cửa sổ/pane tmux chỉ khi sạch, không thì quyết và giải thích | — |
| S5 | Tương tác (yêu cầu) | Với pane A3, khôi phục A5, đích CLI A7, chia sẻ điện thoại | — |
| S6 | Riêng tư (yêu cầu) | Không bao giờ log hostname, lệnh, cwd | — |
| S7 | Tiền đề (yêu cầu) | Nói rõ A3/A5a/A5b/A7 nào phải merge trước | — |
| D1 | Tiền đề (S7) | **Phải merge trước:** A3 (cây pane, `open(cwd:)`), A4 (thông báo — hook từ xa dùng lại), A5a (bố cục lưu `launch`, D29), A6 (pane trình duyệt cho ⌥-click cổng; A7 cũng cần), A7 (`openTabFor`/`splitPane`, `UiCommandHandler`, lệnh `shellx ssh/tmux`, D33). **Tuỳ chọn:** A5b — có thì plan Task 13 cập nhật codec `sessions.open`/`sessions.changed`; không thì bỏ bước đó. A8 không cần A5b vì phiên SSH chỉ là một phiên PTY như mọi phiên | Nếu A7 trễ: A8 Task 1–12 vẫn làm được (không phụ thuộc CLI), Task 14 chờ A7; ghi ledger |
| D2 | Mô hình phiên | Một pane SSH = **một phiên `LocalSessions` có PTY chạy binary `ssh`** (thêm tham số `launch` cho `open`). Không thư viện SSH trong Dart, không kênh SSH tự cài. Vì vậy điện thoại, A4, A5b, A7 `send/read/wait` dùng được ngay; điều khác duy nhất là lệnh được spawn và cách hiểu OSC 7 (D14) | Không đọc được trạng thái kênh SSH chi tiết (chỉ mã thoát 255) |
| D3 | Binary `ssh` | macOS: **`/usr/bin/ssh`** (không theo PATH: app GUI có PATH tối giản; tránh ssh lạ). Windows: `%SystemRoot%\System32\OpenSSH\ssh.exe`, không có thì `ssh.exe` đầu tiên trong `Path`. Không có → không mở được (`SpawnFailedException('ssh_unavailable')`), toast `sshUnavailable` (Windows thêm hướng dẫn bật "OpenSSH Client"); mục menu vẫn hiện | Người dùng OpenSSH Homebrew (khoá FIDO mới…) dùng bản hệ thống — cấu hình vẫn đọc như nhau |
| D4 | Cú pháp đích | Nhận: `alias`, `host`, `user@host`, `host:port`, `user@host:port`, `[v6]:port`, IPv6 trần, `ssh://user@host[:port][/]`. Kiểm: host `^[A-Za-z0-9_][A-Za-z0-9._-]{0,252}$` hoặc IPv6 (hex, `:`, `.`, `%zone`); user `^[A-Za-z0-9_][A-Za-z0-9._-]{0,31}$`; cổng 1–65535; tổng ≤ 255; không khoảng trắng/ký tự điều khiển. Đối số ssh: `[-l user] [-p port] -- host` — **không bao giờ** đặt chuỗi người dùng trước `--` | User có `@`/khoảng trắng (domain Windows `DOMAIN\user`) phải dùng alias trong `~/.ssh/config` |
| D5 | Khoá đích | `SshTarget.key` = `[user@]host[:port]` theo thứ tự đó (IPv6 trong `[]` khi có cổng), là khoá của workspace SSH, danh sách gần đây, bố cục A5a, `--host` của CLI. Alias giữ nguyên chữ (ssh tự giải) | `devbox` và `me@devbox.lan` cùng một máy là hai workspace (đúng như người dùng gõ) |
| D6 | Danh sách máy | Đọc `~/.ssh/config` (Windows `%USERPROFILE%\.ssh\config`) + `Include` (đường tương đối theo `~/.ssh/`, `~` mở rộng, glob `*`/`?` ở thành phần cuối, sâu ≤ 4), lấy mọi tên `Host` không chứa `*`, `?`, `!` và hợp lệ theo D4; ≤ 256 tên, file > 1 MiB bỏ qua, lỗi đọc bỏ qua. Cộng **10 đích gần đây** (`ssh_recent_targets`, mới nhất trước). Không đọc `known_hosts` (băm, và là dữ liệu riêng tư). Đọc lại mỗi lần mở hộp | Khối `Match` và `Host *.corp` không thành gợi ý — người dùng gõ tay |
| D7 | Xác thực | Diễn ra **hoàn toàn trong terminal của pane**: mật khẩu, OTP, `yes/no` host key, PIN khoá cứng. ShellX không chặn, không đọc, không ghi nhớ — byte gõ đi thẳng vào PTY như mọi phím (A1). Agent/Keychain/1Password qua cấu hình ssh của người dùng; `SSH_AUTH_SOCK` kế thừa môi trường của app (launchd đặt cho app GUI macOS). Pane **không** thêm `BatchMode`, `StrictHostKeyChecking`, `-A` (không forward agent) | Người chỉ dùng mật khẩu trên Windows gõ mật khẩu cho mỗi pane (không ghép kết nối, D8) |
| D8 | Ghép kết nối (macOS) | Pane SSH chạy với `-o ControlMaster=auto -o ControlPath=<thư mục>/%C -o ControlPersist=60`: pane đầu xác thực, pane sau/probe/chuyển tiếp dùng chung. Thư mục = `/tmp/shellx-ssh-<uid>` (`ControlPath` + đuôi tạm 17 ký tự của ssh phải < 104 byte của `sun_path`; `$TMPDIR` macOS quá dài), tạo 0700; ShellX kiểm chủ sở hữu (`stat -f %u` = `id -u`) và quyền 0700 lúc khởi động — sai → **tắt ghép** (không bao giờ dùng thư mục người khác có thể thay socket). Tuỳ chọn dòng lệnh thắng `ControlMaster`/`ControlPath` của người dùng. **Windows:** Win32-OpenSSH không hỗ trợ ghép → không có tuỳ chọn Control; mỗi pane một kết nối | Người tự cấu hình ControlPath có thêm một master riêng của ShellX (vô hại); Windows hỏi mật khẩu mỗi pane |
| D9 | Chờ master | macOS: mở pane SSH tới đích đang có **phiên chưa kết nối xong** (spawn chưa hello, D16) → chờ tới khi phiên đó hello hoặc `ssh -O check` thấy master, **tối đa 3 s** (kiểm mỗi 100 ms), rồi spawn. Vì vậy chia ngay khi pane đầu còn ở lời nhắc mật khẩu: người dùng gõ kịp trong 3 s thì pane sau không hỏi; không kịp thì pane sau tự hỏi | Chia chậm tối đa 3 s trong lúc xác thực |
| D10 | Hook từ xa (S2) | Pane SSH chạy **một lệnh từ xa duy nhất**: `/bin/sh -c 'eval "$(b=<base64>; printf %s "$b" \| base64 -d 2>/dev/null \|\| printf %s "$b" \| base64 -D 2>/dev/null \|\| printf %s "$b" \| openssl base64 -d -A)"'` — chuỗi trong nháy đơn chỉ có ký tự ASCII an toàn nên đúng với mọi shell đăng nhập (sh, bash, zsh, fish, csh/tcsh: không `!`, không `'`). Script giải mã (sh POSIX, sinh trong Dart, mọi giá trị người dùng qua `shQuote`): (1) in `OSC 6973;hello=1`, `pid=$$`, `home=$HOME`; (2) đặt `SHELLX=1 SHELLX_REMOTE=1`; (3) nếu bật hook: ghi file hook vào `${XDG_CACHE_HOME:-$HOME/.cache}/shellx/remote-<12 hex>/` (umask 077, file tạm `.$$` + `mv`, bỏ qua khi `.ok` có — `<12 hex>` là FNV-1a của nội dung nên bản mới tự ghi lại) — **không bao giờ sửa file khởi động của người dùng**; (4) `cd -- <cwd>` nếu có (lỗi → home); (5) `exec` shell đăng nhập `$SHELL`: zsh → `ZDOTDIR` của hook (khôi phục `ZDOTDIR` người dùng như hook cục bộ), bash → `--rcfile` của hook, khác → `-l`; pane tmux → `exec tmux …` (D25). Nội dung hook = **đúng byte** `zshHookEnv`/`bashHookRc` cục bộ (OSC 7, 133, 633;E, hàm `shellx notify`) + phần thêm từ xa (D15) | Máy chủ không có `/bin/sh` POSIX (Windows OpenSSH server) không chạy được → người dùng tắt hook cho máy đó (D11); script ~14 KiB mỗi lần kết nối (không đáng kể) |
| D11 | Tắt hook | Toàn cục: tray "SSH" → ☑ "Cài hook ShellX trên máy chủ" (`ssh_remote_hook`, mặc định bật). Theo máy: hộp kết nối "Không cài hook trên máy này" và nút "Thử lại không dùng hook" trên pane `failed` (D17) → `ssh_plain_targets`. Không hook = `ssh -t … -- host` **không lệnh từ xa** (shell đăng nhập thuần): không cwd/nhánh/cổng; "đã kết nối" = sống ≥ 10 s. Pane tmux tới máy không hook dùng lệnh trần `tmux attach-session -t <tên>` (không tiền tố `=`: zsh của máy chủ sẽ mở rộng `=…`; tên chỉ `[A-Za-z0-9_-]`, khác → từ chối) | Máy chủ không hook mất ngữ cảnh sidebar |
| D12 | Lựa chọn tuỳ chọn ssh | Pane: `ssh -t [Control… D8] [keepalive D13] [-l -p] -- host [lệnh D10]`. `-t` buộc PTY từ xa khi có lệnh. Không đổi `TERM` (xterm-256color từ môi trường phiên, A1). Không `-q` (thông báo lỗi ssh hiện trong pane — người dùng cần đọc) | — |
| D13 | Keepalive | Trước khi spawn, `ssh -G <đích>` (cục bộ, không mạng, ≤ 2 s, nhớ 60 s theo khoá đích) đọc `serveraliveinterval`; = 0 → thêm `-o ServerAliveInterval=15 -o ServerAliveCountMax=3` (phát hiện mất mạng ≤ 45 s); người dùng đã đặt → giữ của họ; `ssh -G` lỗi → thêm | Ai cố ý tắt keepalive bằng 0 vẫn bị thêm (không phân biệt được "mặc định" và "đặt 0") |
| D14 | cwd từ xa (sửa A2 D2 cho phiên SSH) | Phiên SSH nhận OSC 7 với **mọi** host: lấy đường dẫn (giải mã %, UTF-8 hợp lệ, không NUL, bắt đầu `/`, ≤ 4096), **không** kiểm tồn tại, **không** tra git cục bộ. Hiển thị qua `displayPath` với `home` từ xa (OSC 6973 `home`). Phiên cục bộ giữ nguyên A2 D2 (OSC 7 host khác → quên). Pane tmux: OSC 7 bên trong tmux không tới được (tmux nuốt) → không cwd | — |
| D15 | Nhánh từ xa | Phần thêm của hook bọc `__shellx_osc7` (hàm có sẵn của hook, chạy mỗi prompt): sau OSC 7 gọi `__shellx_remote_meta` — đi ngược từ `$PWD` tới `/` bằng builtin (`[ -f ]`, `read`; **không fork, không chạy git**), đọc `.git/HEAD` hoặc file `.git` (`gitdir:` của worktree/submodule), `ref: refs/heads/X` → `X`, detached → 7 ký tự đầu; in `OSC 6973;branch=<X>` **chỉ khi đổi** (rỗng = không phải repo) | Repo dùng `GIT_DIR`, repo bare: không nhánh |
| D16 | OSC 6973 (riêng ShellX) | `ESC ] 6973 ; <khoá>=<giá trị> (BEL\|ST)`. Khoá: `hello` (=1), `pid` (số 1…2^31−1), `home` (bắt đầu `/`, ≤ 4096), `branch` (≤ 255). Giá trị chứa ký tự điều khiển C0/C1 → bỏ. **Chỉ phiên có `launch` từ xa** dùng; phiên cục bộ bỏ qua (nhánh cục bộ có từ git A2). `hello` = "đã kết nối" (đã qua xác thực, script đang chạy trên máy chủ). xterm.dart và điện thoại bỏ qua OSC lạ | Máy chủ độc hại giả được thư mục/nhánh/pid hiển thị — chỉ ảnh hưởng chữ trên sidebar và probe cổng của chính máy đó |
| D17 | Trạng thái kết nối | `connecting` (spawn → hello; không hook: 10 s), `connected`, `disconnected` (ssh thoát **255** sau khi pane **đã từng** kết nối — kể cả qua các lần kết nối lại), `failed` (thoát ≠ 0 khi **chưa từng** kết nối: xác thực sai, không phân giải được tên, máy chủ không chạy được hook), `exited` (thoát ≠ 0 và ≠ 255 sau khi đã kết nối: như A1 D14/A3 D7 — dòng thoát, Enter đóng). Thoát 0 → pane đóng (A3 D7). Đóng theo yêu cầu → như A1 | Lệnh từ xa tự thoát 255 bị coi là mất kết nối (hiếm; nút "Đóng pane" luôn có) |
| D18 | Cổng từ xa | Probe theo **máy chủ** (không theo pane): `ssh -o BatchMode=yes -o ControlMaster=no [ControlPath] -- host <lệnh D10 với script probe>` — dùng master nếu có (macOS), không thì kết nối riêng không bao giờ hỏi. Script: `ps -A -o pid= -o ppid=` + (`ss -ltnp` nếu có, không thì `lsof -nP -iTCP -sTCP:LISTEN -F pn`). Dart dựng cây tiến trình, mỗi phiên lấy cổng của **hậu duệ của `pid` của nó** (D16). Nhịp: 5 s (macOS) / 15 s (Windows) chỉ khi cửa sổ hiện (A2 D8) và máy chủ có ≥ 1 phiên đã hello; hết giờ 4 s; 3 lỗi liên tiếp → 60 s; thoát 255 (cần xác thực) → dừng probe máy đó tới lần hello kế. ≤ 16 máy chủ được probe | Máy chủ không có `ps`/`ss`/`lsof` (container tối giản) → không cổng; Windows mở một kết nối SSH mỗi 15 s khi cửa sổ hiện |
| D19 | Mở cổng từ xa | Bấm cổng của pane SSH → chuyển tiếp `127.0.0.1:L → localhost:R` trên máy chủ: macOS `ssh -S <ControlPath> -O forward -L 127.0.0.1:L:localhost:R -- host` (qua master); Windows/không master: tiến trình `ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes -L … -- host` giữ tới khi hết phiên của máy đó. **L = R nếu cổng R trên máy đang trống** (cookie, callback OAuth giữ đúng cổng), không thì cổng do hệ điều hành cấp. Dùng lại chuyển tiếp đã có cho (máy, R). Mở `http://localhost:L/` bằng trình duyệt hệ thống (A2) hoặc ⌥-click → pane trình duyệt A6. Tooltip cổng từ xa đổi thành "Mở cổng R trên devbox (chuyển tiếp qua SSH)", sau khi chuyển tiếp "localhost:L → devbox:R". Huỷ: phiên cuối của máy đóng, "Thoát hoàn toàn". Chuyển tiếp lỗi → toast `remotePortForwardFailed` | Không proxy SOCKS cho pane trình duyệt như cmux: gõ `localhost:3000` trong pane trình duyệt là máy mình — dùng cổng trên sidebar |
| D20 | Kết nối lại (S3) | Pane `disconnected`/`failed` **giữ chỗ** trong cây (như pane thoát ≠ 0 A3 D7): dòng mờ trong terminal + dải pane (UI §3) với "Kết nối lại" (= Enter trong pane) và "Đóng pane"; `failed` thêm "Thử lại không dùng hook" khi đã dùng hook và mã ≠ 255. **Tự kết nối lại chỉ cho `disconnected`**: chờ 3, 6, 12, 24, 48, 60, 60… s (như cmux), thử ngay khi máy thức (WakeDetector), ngừng sau **30 phút** kể từ lần mất đầu (dải đổi thành "Đã ngừng tự kết nối lại"). `failed` không bao giờ tự thử (tránh khoá tài khoản, fail2ban). Lần thử đang ở lời nhắc mật khẩu là phiên sống — chờ người dùng | Máy chủ tắt hẳn: ≤ 30 lần thử trong 30 phút |
| D21 | Phiên sau kết nối lại | Phiên **mới** cùng `launch`, cwd từ xa = cwd cuối của pane, lưới = lưới hiện tại của pane, **cùng `DesktopTerminal`** (nội dung cũ giữ), trước output mới ghi `ESC[?25h` + vạch mờ "— Đã kết nối lại · {giờ} —" (định dạng giờ A5a D23). Shell từ xa cũ đã chết cùng kết nối: chương trình đang chạy không sống lại (giống cmux không tmux); pane tmux gắn lại đúng phiên — chương trình sống. Dải `disconnected` có gợi ý "Chạy trong tmux để chương trình vẫn chạy khi mất kết nối" | Người không dùng tmux mất tiến trình từ xa khi mất mạng |
| D22 | Id khi kết nối lại | Phiên mới có id mới. `TerminalTabs.replacePaneSession(old, new)`: lá cây đổi id (`replaceLeaf`), tab giữ id (A3 D1), focus/phóng to/MRU chuyển sang id mới, `everConnected` mang theo, chưa đọc A4 của pane cũ bỏ; phát `paneReplacements` → A5a chuyển `paneKey` sang id mới; A7 giữ bảng chuyển tiếp `resolveReplaced(id)` (≤ 64 cặp, đi theo chuỗi) để `p<id cũ>` vẫn trỏ đúng pane, và phát sự kiện `pane.replaced{old, new}` | Script dùng `$SHELLX_PANE_ID`… chỉ cục bộ, không ảnh hưởng |
| D23 | Workspace SSH | `connect(đích)`: workspace đầu tiên có `ssh == key` nhận tab mới; không có → tạo workspace **tên = key**, `ssh = key`, không mở ô đổi tên, thành hiện tại, tab mới được chọn. Trong workspace SSH: ⌘T và `+` trên tiêu đề → tab SSH mới tới máy đó (home từ xa, hook theo D11); menu tiêu đề thêm "Tab cục bộ mới" và "Kết nối lại mọi pane". Kéo tab vào/ra workspace SSH không đổi bản chất tab. Đổi tên/xoá như A2 (xoá: tab về Mặc định, phiên giữ nguyên). Mặc định không bao giờ là SSH. Lưu: khoá `ssh` trong JSON workspace (A2 D17; bản cũ bỏ qua khoá lạ, `Workspace.decode` đã vậy) | Hai workspace cùng khoá (người dùng tạo tay rồi đổi tên): workspace đầu theo thứ tự sidebar nhận |
| D24 | Chia (sửa A3 D17 cho pane từ xa) | ⌘D/⌘⇧D/menu/A7 `split` trên pane SSH → pane SSH mới **cùng đích, cùng hook**, cwd từ xa = cwd của pane (qua `cd` trong script; A3 D17 kiểm thư mục cục bộ **không** áp dụng). Pane tmux → pane SSH thường tới cùng máy (tmux từ xa) hoặc shell cục bộ (tmux cục bộ), ở home — chia trong tmux dùng phím tmux. Pane `disconnected`/`failed` cũng chia được (kết nối mới). ⌘⇧B (A6) không đổi (pane trình duyệt là cục bộ) | Người muốn pane cục bộ cạnh pane SSH dùng menu "Chia cục bộ" (§UI 5.2) |
| D25 | tmux — liệt kê và gắn | Liệt kê: `tmux list-sessions -F '#{session_name}<TAB>#{session_windows}<TAB>#{session_attached}<TAB>#{session_activity}'`. **Cục bộ:** tmux dò ở `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`, `/usr/bin`, rồi `PATH`; Windows: không có mục "Máy này" (WSL ngoài phạm vi). **Từ xa:** cùng lệnh qua `runRemote` (BatchMode, D18), PATH của shell đăng nhập. "no server running"/"error connecting" → rỗng; không có tmux (127, "not found") → "tmux chưa được cài trên {nơi}"; thoát 255 → "cần đăng nhập không hỏi mật khẩu — kết nối SSH tới máy này một lần rồi thử lại"; hết giờ 5 s. **Gắn:** mỗi phiên tmux thành **một tab** (một pane ShellX chứa client tmux đầy đủ: thanh trạng thái, cửa sổ và pane của tmux). Cục bộ: PTY chạy `tmux attach-session -t =<tên>` (tạo: `new-session -A -s <tên>`); từ xa: script D10 kết thúc bằng `exec "$SHELL" -l -c 'exec tmux attach-session -t "=$SHELLX_TMUX"'` (shell bash/zsh/sh/dash/ksh/fish; khác → `/bin/sh` với PATH thêm `/usr/local/bin:/opt/homebrew/bin`), tên qua biến môi trường (không ghép chuỗi). Tên: 1–64 ký tự, không ký tự điều khiển, không `:`/`.` (tmux cấm) | tmux < 1.9 không hiểu `=` tiền tố (rất cũ) |
| D26 | tmux — tab | Tiêu đề tự động "tmux: {tên}" (tên tuỳ chỉnh A2 vẫn thắng; OSC 0/2 từ tmux `set-titles` bị bỏ cho pane tmux để tiêu đề ổn định); dấu tmux trên dòng (UI §2). Đóng tab/pane tmux = **tách client** (tmux server và phiên chạy tiếp) → **không hỏi xác nhận** dù có gì đang chạy (không mất gì). Tab tmux từ xa vào workspace SSH của máy đó (D23); tab tmux cục bộ vào workspace hiện tại | — |
| D27 | Không ánh xạ cửa sổ/pane tmux (S4) | **Không** dùng control mode (`tmux -CC`) để biến cửa sổ tmux thành tab và pane tmux thành pane ShellX (cmux `ssh-tmux` có làm). Lý do: (1) pane ShellX = một phiên PTY của agent; pane tmux ánh xạ sẽ là phiên ảo không PTY → phá hợp đồng `LocalSessions` (ring buffer, driver, điện thoại, A5b daemon, A7 `read`); (2) bố cục do tmux quyết (ô ký tự, `select-layout`), cây A3 do ShellX quyết (tỉ lệ thực, cỡ tối thiểu D4, phóng to) — hai nguồn sự thật cho cùng một màn hình; (3) A5a và A7 `split`/`close` phải có đường đi thứ hai; (4) control mode cần tmux ≥ 3.2, không bracketed paste nhiều dòng (chính cmux ghi là giới hạn). Thay vào đó: client tmux đầy đủ trong một pane (D25) — mọi phím tmux, chuột tmux, copy-mode chạy đúng. Follow-up **A8.1 "tmux mirror"** ghi trong §7 | Không có split/đóng/kéo native cho pane tmux; điện thoại thấy tmux như một phiên (vẫn dùng được) |
| D28 | tmux và điện thoại | Phiên tmux là phiên thường: điện thoại xem/gõ; cỡ PTY theo driver (A1 D6) nên tmux đổi cỡ client theo driver | — |
| D29 | Khôi phục (A5a, sửa A5a D7/D9) | Lá cây lưu `launch` (`{"kind":"ssh","target":key,"hook":bool}` hoặc `{"kind":"tmux","session":tên,"host":key?,"hook":bool}`) cạnh `cwd` (cwd từ xa với pane SSH). Mở lại: pane SSH/tmux **kết nối lại thật** (spawn ssh/tmux theo thứ tự A5a D7, D9 chờ master nên mỗi máy hỏi mật khẩu một lần nếu người dùng gõ kịp), nội dung đã lưu + vạch A5a ở trên. Kết nối không được → pane `failed` có nút thử lại, **không** bị gỡ khỏi cây (spawn ssh vẫn thành công — khác A5a D7 chỉ áp cho spawn lỗi). `launch` trong file là dữ liệu không tin cậy: kiểm lại bằng `SshTarget.parse`/`isValidTmuxName`; sai → cả file bị coi là hỏng theo A5a D11 (`.bak`, bắt đầu mới — chỉ file bị sửa tay mới tới đây). Workspace `ssh` theo settings A2 | Máy chủ cần mật khẩu: mở ShellX hỏi mật khẩu ngay (trong pane, khi người dùng nhìn tới) |
| D30 | Bố cục khi tab chưa hiện | Không trì hoãn: mọi pane SSH mở như A5a (đơn giản, nhất quán với A3 D13 lưới ước tính). Lời nhắc mật khẩu của tab không chọn chờ tới khi người dùng chọn tab | Nhiều máy cần mật khẩu → nhiều lời nhắc đang chờ |
| D31 | Daemon (A5b) | Phiên SSH/tmux sống trong daemon như mọi phiên: "Thoát" (⌘Q) không ngắt; mở lại UI gắn lại (A5b D18). Mux: `sessions.open` thêm khoá tuỳ chọn `launch` (map như D29), `sessions.changed` mang `remote{launch, connected, home}`. Master ControlPersist là tiến trình `ssh` riêng (sống tối đa 60 s sau phiên cuối). Probe cổng chạy ở tiến trình giữ `SessionManager` (daemon); chuyển tiếp cổng chạy ở UI (D19, tiện ích của cửa sổ). "Thoát hoàn toàn" → `ssh -O exit` cho mọi đích ShellX đã ghép (D40) | — |
| D32 | Ghép với `--cmd` (A7 D16) | Pane SSH "sẵn sàng" = OSC 7 đầu tiên (đã đến từ máy chủ vì hook gửi); không hook: quy tắc im lặng A7 D16 | — |
| D33 | CLI (A7) | Lệnh mới: `shellx ssh TARGET [--workspace W] [--cwd DIR] [--cmd C] [--no-hook] [--focus]` → `ui.ssh.open{target, workspace?, cwd?, cmd?, hook, focus}` → `{tab, pane}` (in `t<id>`); `shellx tmux ls [--host T]` → `ui.tmux.list{host?}` → `{sessions:[{name, windows, attached, activity}]}`; `shellx tmux attach NAME [--host T] [--create] [--focus]` → `ui.tmux.attach` → `{tab, pane}`. `ls` thêm mỗi pane `remote: {kind: "ssh"\|"tmux", host?, tmux?, state}`. `new-tab --workspace <workspace SSH>` mở SSH (D23); `split` kế thừa (D24). Caps `ui.ssh`, `ui.tmux`. Lỗi mới `ssh_unavailable`, `tmux_unavailable`, `tmux_failed` → mã thoát 1; đích/tên sai → `bad_request` (2); thiếu cap → 7. Tab do CLI mở không lấy focus (A7 D14). Dấu Agent A7 D27 như mọi lệnh | — |
| D34 | Không CLI trên máy chủ | Không reverse tunnel, không cài `shellx` lên máy chủ: một máy chủ bị chiếm không được điều khiển máy bàn (A7 "chỉ shell của ShellX"). Trên máy chủ, `shellx notify …` là **hàm** của hook (OSC 777, có sẵn trong `zshHookBody`/`bashHookBody`) → thông báo A4 + push điện thoại | Agent chạy trên máy chủ không mở được pane/tab (cmux làm được qua relay) — follow-up nếu cần |
| D35 | Thông báo từ xa | OSC 9/99/777/BEL và 133/633 từ máy chủ đi qua PTY cục bộ → A4 (vòng, badge, thông báo hệ thống, lệnh dài) và push hoạt động **không đổi**, cùng giới hạn A4 D6 | — |
| D36 | Điện thoại (S5) | Không đổi protocol. Phiên SSH/tmux là phiên desktop (A1 D4). `SessionInfo.cwd` gửi điện thoại `desktop: true` là `<key>:<đường dẫn từ xa>`, `branch` như thường. Điện thoại không mở được phiên SSH (protocol không có — ngoài phạm vi) | — |
| D37 | Riêng tư (S6) | **Không bao giờ log**: đích, host, user, cổng SSH, đường dẫn từ xa, `home`, nhánh, tên phiên tmux, script/lệnh, stdout/stderr của `ssh`/`tmux`, số cổng chuyển tiếp. Log chỉ: loại sự kiện, mã thoát, `runtimeType`, số đếm (`ssh: session exited 255`, `ssh probe: failed (timeout)`, `ssh: control dir unsafe`). Lưu trên máy: `ssh_recent_targets`, `ssh_plain_targets`, workspace `ssh`, `launch` trong `layout.json` — dữ liệu cục bộ như tên tab (A5a D22). Tooltip và nhãn trợ năng hiện host (giao diện, không phải log). Trang chính sách riêng tư thêm một gạch đầu dòng: ShellX chạy `ssh` của máy, ghi hook vào `~/.cache/shellx/` trên máy chủ, không gửi gì khác | — |
| D38 | Bảo mật | (a) Chèn đối số: D4 + `--`. (b) Script D10 sinh hoàn toàn trong Dart; chuỗi người dùng (cwd, tên tmux) chỉ vào qua `shQuote`/biến môi trường; vận chuyển base64. (c) OSC 6973 chỉ phiên từ xa, giá trị kiểm D16. (d) Không `-A`, không `-R`/reverse tunnel. (e) ControlPath chỉ trong thư mục đã kiểm chủ (D8). (f) Chuyển tiếp chỉ bind `127.0.0.1`. (g) Probe/liệt kê luôn `BatchMode=yes` (không bao giờ hiện lời nhắc vô hình) | — |
| D39 | Giới hạn | ≤ 32 phiên (A1 D8) gồm cả SSH/tmux; ≤ 16 máy probe đồng thời; gần đây ≤ 10; gợi ý config ≤ 256; script D10 ≤ 24 KiB (dòng lệnh Windows ≤ 32 767 ký tự); tên tmux ≤ 64; chuyển tiếp ≤ 32 mỗi máy | — |
| D40 | Thoát | A5b "Thoát": giữ phiên (D31). "Thoát hoàn toàn" (hoặc Thoát trước A5b, A1 D7): đóng phiên (kill `ssh`) → `ssh -O exit` mọi đích từng ghép trong thư mục ShellX (≤ 2 s tổng, song song) → kill tiến trình chuyển tiếp Windows | Master sống ≤ 60 s nếu "Thoát hoàn toàn" bị kill giữa chừng |
| D41 | Phím tắt và lối vào | "Kết nối SSH…" ⌘⇧K / Ctrl+Shift+K (không trùng A1–A7). Lối vào: phím; menu chuột phải của `+` đầu sidebar ("Tab mới", "Kết nối SSH…", "Gắn phiên tmux…"); menu tiêu đề workspace SSH; tray submenu **"SSH"** ngay sau "Dòng lệnh" (A7): "Kết nối SSH…", "Gắn phiên tmux…", ☑ "Cài hook ShellX trên máy chủ", "Xóa danh sách máy gần đây". "Gắn phiên tmux…" mở cùng hộp ở thẻ tmux | Ctrl+Shift+K trên Windows bị nuốt khỏi chương trình terminal (hiếm khi dùng) |
| D42 | Hộp kết nối | Một hộp, hai thẻ "SSH" \| "tmux" (UI §4). SSH: ô "Máy chủ" (gợi ý D6, lọc theo chữ con không phân biệt hoa thường, ↑/↓/Enter), ô tuỳ chọn "Thư mục trên máy chủ", ô kiểm "Không cài hook trên máy này" (nhớ theo máy). "Kết nối" đóng hộp **ngay** (xác thực diễn ra trong pane), lưu vào gần đây. tmux: "Phiên trên" (Máy này + máy chủ: cùng ô có gợi ý), danh sách phiên, "Gắn", ô "Tên phiên mới" + "Tạo và gắn". Đích sai → lỗi dưới ô (không đóng hộp) | — |
| D43 | Windows ⚠ | ConPTY + `ssh.exe` (Win32-OpenSSH ≥ 8.1, có sẵn Windows 10 1809+/11), không ghép, probe/liệt kê/chuyển tiếp là kết nối BatchMode riêng. Phải kiểm tay: ConPTY với lời nhắc mật khẩu, resize, Ctrl+C, `~.`, chuyển tiếp | Chưa có máy Windows → "pending manual" trong ledger, không merge |
| D44 | Hiệu năng | Mở pane SSH (tới lúc spawn `ssh`) ≤ 50 ms + `ssh -G` (≤ 30 ms, nhớ 60 s); chia trên master ≤ 300 ms tới prompt (LAN); probe ≤ 1 lần / 5 s / máy, phân tích ≤ 5 ms với 2000 tiến trình; mở hộp kết nối (đọc config) ≤ 50 ms | — |

**Sửa A2:** D2 (OSC 7 từ host khác → quên thư mục) chỉ còn áp cho phiên **cục bộ**; phiên SSH hiểu OSC 7 là thư mục từ xa (D14). Cổng của phiên SSH là cổng **trên máy chủ**, mở qua chuyển tiếp (D19).
**Sửa A3:** D17 (kiểm cwd cục bộ cho pane mới) không áp cho pane SSH (D24). D7 "pane thoát ≠ 0 giữ dòng thoát" — pane SSH `disconnected`/`failed` giữ dải kết nối lại thay vì dòng thoát A1 (D20).
**Sửa A5a:** lá thêm `launch` (D29); D7 "pane mở lỗi bị gỡ" không áp cho pane SSH không kết nối được (D29).
**Sửa A5b:** `sessions.open` thêm `launch`; `sessions.changed` mang `remote` (D31).
**Sửa A7:** lệnh `ssh`, `tmux ls`, `tmux attach`; `ls` thêm `remote`; caps `ui.ssh`, `ui.tmux`; mã lỗi mới; bảng chuyển tiếp id + sự kiện `pane.replaced` (D22, D33).
**Sửa `LocalSessions`:** `open({cols, rows, cwd, tabId, SessionLaunch? launch})`; `SessionSummary.remote`. Mọi hiện thực (`SessionManager`, `FakeLocalSessions`, `RemoteLocalSessions` nếu có) đổi cùng commit.

---

## 3. Kiến trúc

```
packages/shellx_agent/lib/src/remote/ (mới, Dart thuần)
 ├─ ssh_target.dart        SshTarget.parse / key / destinationArgs                         (D4, D5)
 ├─ session_launch.dart    SessionLaunch (SshLaunch, TmuxLaunch): JSON, forSplit, forReconnect,
 │                         isValidTmuxName, SessionRemote                                   (D2, D24, D25, D29)
 ├─ ssh_config_hosts.dart  parseSshConfig, readSshConfigHosts                               (D6)
 ├─ tmux_sessions.dart     tmuxListFormat, parseTmuxSessions, classifyTmuxList              (D25)
 ├─ remote_probe.dart      remoteProbeScript, parseRemoteProbe                              (D18)
 ├─ remote_bootstrap.dart  RemoteBootstrap → script sh, remoteExecCommand, shQuote, phần thêm hook (D10, D15)
 ├─ ssh_command.dart       buildSshCommand, buildLocalTmuxCommand, sshPathFor, tmuxPathFor  (D3, D8, D12, D13, D25)
 ├─ ssh_control.dart       SshControl: thư mục ghép, ssh -G, -O check, runRemote, forward, exitMasters,
 │                         CommandRunner                                                    (D8, D9, D13, D18, D19, D40)
 └─ remote_port_watcher.dart  RemotePortWatcher (nhịp, lỗi, BatchMode)                      (D18)
packages/shellx_agent
 ├─ notify/osc_event_parser.dart   + RemoteMetaReported (OSC 6973)                          (D16)
 ├─ context/cwd_url.dart           + parseRemoteCwdPath                                     (D14)
 └─ session/session_manager.dart   open(launch:), spawn ssh/tmux, remote state, master wait,
                                   SessionSummary.remote, cwd/nhánh/cổng từ xa, SessionInfo cwd (D2, D9, D14–D18, D36)
apps/desktop/lib/src
 ├─ remote/ (mới)
 │   ├─ remote_tools.dart        đường dẫn ssh/tmux, SshControl của UI, provider               (D3, D8)
 │   ├─ ssh_actions.dart         connect, newTab (theo workspace), attachTmux, listTmux, gần đây, plain (D6, D11, D23, D25, D42)
 │   ├─ ssh_reconnector.dart     tự kết nối lại: lùi dần, thức máy, 30 phút                    (D20)
 │   └─ remote_port_forwards.dart  chuyển tiếp cổng, mở trình duyệt                           (D19)
 ├─ terminal/pane_layout.dart    + replaceLeaf                                                (D22)
 ├─ terminal/terminal_tabs.dart  PaneSession.remote/everConnected, remoteState; open/split với launch;
 │                               reconnect/replacePaneSession, paneReplacements, resolveReplaced; dòng mất kết nối (D17, D20–D24)
 ├─ terminal/sidebar_workspaces.dart  Workspace.ssh, workspaceForHost, createForHost          (D23)
 ├─ platform/settings_store.dart + ssh_recent_targets, ssh_plain_targets, ssh_remote_hook     (D6, D11)
 ├─ ui/terminal/ssh_connect_dialog.dart (mới), remote_strip.dart (mới), remote_marks.dart (mới)
 ├─ ui/terminal/{session_tab_row, pane_tree_view, workspace_header, session_sidebar, terminal_shortcuts,
 │               terminal_workspace_page}.dart       dấu, dải, menu, phím                   (UI addendum)
 ├─ tray/…                        submenu "SSH"                                               (D41)
 ├─ restore/…                     lá `launch`                                                 (D29)
 └─ cli/ui_command_handler.dart   ui.ssh.open, ui.tmux.list, ui.tmux.attach, ls remote         (D33)
term/src/api/{args,run}.rs        lệnh ssh / tmux ls / tmux attach                            (D33)
agent-skills/shellx/reference.md  mục SSH và tmux                                            (D33)
```

Không đổi: `shellx_core` protocol, `apps/mobile`, `relay/`, `term/src/proto`, `term/shell/*`, `zshHookEnv`/`bashHookRc`/`powerShellHook` (byte giữ nguyên — hook từ xa **thêm** phần riêng phía sau).

### 3.1 `SessionLaunch`

```dart
sealed class SessionLaunch {
  Map<String, Object?> toJson();
  static SessionLaunch? fromJson(Object? json);      // kiểm D4/D25, null nếu sai
  SessionLaunch? forSplit(String? cwd);             // D24: null = shell cục bộ
  SessionLaunch forReconnect(String? cwd);          // D21
  String get hostLabel;                             // key của đích, hoặc "" cho tmux cục bộ
}
final class SshLaunch extends SessionLaunch { SshTarget target; String? remoteCwd; bool hook; }
final class TmuxLaunch extends SessionLaunch { String session; SshTarget? host; bool create; bool hook; }
final class SessionRemote { SessionLaunch launch; bool connected; String? home; }
```

### 3.2 Luồng spawn trong `SessionManager`

`open(launch: SshLaunch)` → (`RemoteTools` null → `SpawnFailedException('ssh_unavailable')`) → D9 chờ master → `SshControl.keepaliveNeeded` (D13) → `buildSshCommand` → `_ptyFactory.spawn(command, workingDirectory: home, environment: buildSessionEnvironment(base))` **không** `ShellIntegration` → `_Session.remote = _RemoteState(launch)`; không hook → hẹn 10 s đặt `connected`. `_track`: `RemoteMetaReported` → hello/pid/home/branch; `CwdReported` của phiên từ xa → `parseRemoteCwdPath`. `RemotePortWatcher` nhận `{phiên → (đích, pid)}` từ `SessionManager`, trả cổng.

### 3.3 Desktop

`TerminalTabs` đọc `SessionSummary.remote` vào `PaneSession.remote`, giữ `everConnected`. `remoteState(PaneSession)` (thuần) cho UI. `_exited` của pane từ xa với trạng thái `disconnected`/`failed` ghi dòng mờ của A8 thay dòng A1 D14. `reconnect(id)` → `open(launch: forReconnect(cwd))` → `replacePaneSession`. `SshReconnector` nghe `terminalTabsProvider` (pane `disconnected` mới → hẹn giờ), `WakeDetector`, và trả lời "Kết nối lại" thủ công. `SshActions` là lối vào duy nhất cho phím/menu/hộp/CLI.

---

## 4. Luồng dữ liệu

```
⌘⇧K → hộp → "devbox" → SshActions.connect
  ├─ SidebarWorkspaces.workspaceForHost("devbox") ?? createForHost  → hiện tại
  └─ TerminalTabs.openTab(launch: SshLaunch(devbox, hook)) → LocalSessions.open(launch)
       → SessionManager: chờ master ≤3 s → ssh -G → /usr/bin/ssh -t -o Control… -- devbox '/bin/sh -c …'
       → PTY: [lời nhắc mật khẩu nếu có] → script: OSC 6973 hello/pid/home → ghi hook (lần đầu) → exec zsh -l
       → OSC 7 (cwd từ xa), OSC 6973 branch, 133 → SessionSummary.remote.connected, cwd, gitBranch
       → RemotePortWatcher (5 s, BatchMode qua master) → ports
mất mạng → ssh thoát 255 → TerminalTabs._exited: disconnected → dòng mờ + dải
  → SshReconnector: 3 s → TerminalTabs.reconnect → open(forReconnect(cwd)) → replacePaneSession(old,new)
  → cùng DesktopTerminal + vạch "Đã kết nối lại" → paneReplacements → A5a khoá, A7 bảng chuyển tiếp
bấm :8000 (pane SSH) → RemotePortForwards.open(devbox, 8000) → ssh -O forward -L 127.0.0.1:8000:localhost:8000 → UrlOpener
tmux: hộp thẻ tmux → SshActions.listTmux(host?) → tmux list-sessions (cục bộ / runRemote) → Gắn
  → openTab(launch: TmuxLaunch) → tmux attach-session -t =main (cục bộ) | ssh … script → exec tmux attach
```

---

## 5. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Không có `ssh` | Toast `sshUnavailable` (Windows: hướng dẫn bật OpenSSH Client); không mở tab |
| Đích sai cú pháp | Lỗi dưới ô (`sshHostInvalid`); CLI `bad_request` mã 2 |
| Tên máy không phân giải / từ chối kết nối | ssh in lỗi trong pane, thoát 255 trước hello → `failed`, không tự thử |
| Sai mật khẩu 3 lần | ssh thoát 255 → `failed` |
| Host key đổi (cảnh báo MITM của ssh) | ssh in cảnh báo trong pane và thoát → `failed`; ShellX không bao giờ tự sửa `known_hosts` |
| Máy chủ không có `/bin/sh`/base64 (Windows server, busybox thiếu) | Script lỗi → thoát ≠ 0 trước hello → `failed` + nút "Thử lại không dùng hook" |
| Home từ xa chỉ đọc / không ghi được cache | Script bỏ qua hook, `exec $SHELL -l` → không cwd/nhánh, vẫn hello (vẫn có pid → cổng) |
| Shell từ xa là fish/csh | Không hook (chỉ zsh/bash); hello, pid → cổng vẫn có; không cwd/nhánh |
| Mất mạng | Keepalive → 255 sau ≤ 45 s → `disconnected` → tự kết nối lại (D20) |
| Máy ngủ | Thức → thử ngay mọi pane `disconnected`; pane còn sống nhưng TCP chết → keepalive phát hiện |
| Thư mục cwd từ xa không còn khi kết nối lại | `cd` lỗi → home từ xa, không lỗi |
| Phiên tmux không còn khi gắn lại | tmux in "can't find session", thoát 1 sau hello → `exited` (dòng thoát A1, Enter đóng) |
| tmux chưa cài | Hộp: "tmux chưa được cài trên {nơi}"; CLI `tmux_unavailable` |
| Liệt kê tmux từ xa cần mật khẩu | BatchMode thất bại 255 → thông điệp `tmuxListFailed` (kết nối SSH một lần trước) |
| Thư mục ghép không an toàn (chủ khác) | Tắt ghép; log `ssh: control dir unsafe` (không đường dẫn); mọi thứ khác chạy như Windows |
| Cổng chuyển tiếp bận / bị từ chối | Cổng khác do OS cấp; vẫn lỗi → toast `remotePortForwardFailed` |
| 32 phiên | `SessionLimitException` (A1) — toast A1 |
| Người dùng đóng pane trong lúc chờ kết nối lại | Huỷ hẹn giờ |
| Pane SSH đang ở lời nhắc mật khẩu khi ⌘Q (A5b có daemon) | Phiên sống trong daemon; mở lại vẫn ở lời nhắc |
| Điện thoại gõ vào pane SSH | Như mọi phiên (A1 D6) |
| Đóng tab tmux | Không hỏi; client tmux kết thúc, phiên tmux chạy tiếp |

---

## 6. Kiểm thử

- **Dart `shellx_agent` (thuần):** `ssh_target_test` (mọi dạng D4, chèn `-oProxyCommand`, IPv6, cổng biên, key), `session_launch_test` (JSON khứ hồi, fromJson từ chối dữ liệu xấu, forSplit/forReconnect), `ssh_config_hosts_test` (Host nhiều mẫu, `=`, nháy, wildcard bỏ, Include tương đối/glob/vòng lặp/độ sâu, giới hạn), `tmux_sessions_test` (parse, phân loại lỗi), `remote_probe_test` (ps + ss, ps + lsof, cây hậu duệ, IPv6, header ss), `remote_bootstrap_test` (không `'`/`!` trong lệnh ngoài, base64 khứ hồi, `shQuote`, `sh -n` hợp lệ, hook giữ byte `zshHookEnv`/`bashHookRc`), `ssh_command_test` (thứ tự đối số, `--`, Control chỉ macOS, keepalive), `ssh_control_test` (runner giả: `-G`, check, runRemote BatchMode, forward chọn cổng, exitMasters), `remote_port_watcher_test` (`fake_async`: nhịp, ẩn cửa sổ, 3 lỗi → 60 s, 255 → dừng), `osc_event_parser` (OSC 6973), `cwd_url` (`parseRemoteCwdPath`), `session_manager_remote_test` (spawn lệnh ssh/tmux, không ShellIntegration, hello/pid/home/branch/cwd, phiên cục bộ bỏ OSC 6973, không hook 10 s, chờ master, `SessionInfo.cwd` cho điện thoại, `ssh_unavailable`).
- **Dart thật (`@TestOn('mac-os || linux')`):** chạy script bootstrap bằng `/bin/sh` cục bộ với `HOME` tạm và `SHELL` = script giả ghi đối số → OSC hello/pid/home, file hook 0600/thư mục 0700, `.ok`, `cd`, exec đúng đối số; chạy `bash --rcfile <hook từ xa> -i` thật trong repo git tạm → OSC 6973 `branch` đúng, đổi khi `git switch`, không 133;C thừa.
- **Desktop:** `pane_layout_test` (`replaceLeaf`), `terminal_tabs_remote_test` (`FakeLocalSessions`: open/split kế thừa launch, dòng mất kết nối, Enter → reconnect, replacePaneSession giữ terminal/tab id/focus/zoom, `resolveReplaced`, `remoteState`), `sidebar_workspaces_ssh_test`, `ssh_actions_test`, `ssh_reconnector_test` (`fake_async`: lùi dần, thức máy, 30 phút, failed không tự thử, đóng pane huỷ), `remote_port_forwards_test`, widget: hộp kết nối (gợi ý, bàn phím, lỗi, thẻ tmux), dải pane, dấu SSH/tmux, tiêu đề workspace, tray submenu; restore khứ hồi `launch`; `ui_command_handler_ssh_test`.
- **Rust:** `args` có `ssh`, `tmux ls`, `tmux attach`; `run` dựng đúng yêu cầu và in đúng (host giả).
- **Thử tay (HANDOFF, ⚠ MANUAL):** macOS → máy chủ Linux thật (hoặc VM) và macOS "Remote Login": tiêu chí 1–11; khoá trong agent, mật khẩu, OTP, host key mới/đổi; zsh, bash, fish trên máy chủ; tắt Wi-Fi; ngủ máy; Windows 11 với `ssh.exe`: tiêu chí 1–7, 10 (không ghép), Ctrl+C, `~.`, resize vim; VoiceOver/Narrator đọc trạng thái kết nối.

---

## 7. Ngoài phạm vi A8

- **A8.1 "tmux mirror" (follow-up):** control mode `tmux -CC` → mỗi cửa sổ tmux một tab, mỗi pane tmux một pane ShellX. Phác thảo: `TmuxControlClient` (một PTY chạy `tmux -CC attach`, phân tích `%output`/`%layout-change`/`%window-add`), phiên ảo `TmuxPanePty implements Pty` trong `SessionManager` (input = `send-keys -H`, resize = `refresh-client -C`), bố cục **một chiều** tmux → cây A3 (đường chia ShellX chỉ đọc), A5a lưu chỉ tên phiên, A7 `split` → `split-window`. Điều kiện: tmux ≥ 3.2; quyết lại D27 với người dùng.
- Proxy SOCKS/HTTP qua máy chủ cho pane trình duyệt (cmux) — dùng chuyển tiếp từng cổng (D19).
- Mosh; daemon riêng trên máy chủ; kéo-thả file lên máy chủ bằng scp (cmux) — follow-up.
- CLI `shellx` chạy trên máy chủ điều khiển máy bàn (D34).
- Điện thoại mở phiên SSH; tmux trong WSL; PowerShell remoting; đồng bộ danh sách máy giữa các máy; lưu/quản lý khoá SSH; trình soạn `~/.ssh/config`.
- Phím tắt tuỳ biến, file cấu hình (**A9**).
