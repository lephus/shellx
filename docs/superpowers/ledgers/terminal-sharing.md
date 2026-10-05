# Ledger — chia sẻ terminal máy tính

Spec: `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md`
Plan P1: `docs/superpowers/plans/2026-10-01-terminal-sharing-p1-shellx-term-spike.md`
Plan P2a: `docs/superpowers/plans/2026-10-01-terminal-sharing-p2a-agent-link.md`
Plan P2b: `docs/superpowers/plans/2026-10-01-terminal-sharing-p2b-windows.md`

## P1 — bản thử shellx-term trên macOS (2026-10-01)

Máy: MacBook (arm64), macOS 26, zsh 5.9, bash 3.2. `.zprofile` chạy `brew shellenv`, `.zshrc` nạp nvm.
Người dùng đồng ý cho chèn tạm khối vào `~/.zshrc`. Sau khi thử, đã gỡ và so `cmp` với hai bản sao lưu: giống hệt từng byte. `shellx-term` và thư mục `~/Library/Application Support/ShellX` đã xóa.
Người dùng không cài thêm iTerm2, VS Code, Warp.

### Đo thời gian mở cửa sổ (R3)

`cargo run --release --example startup_bench`: 20 lần cho mỗi biến thể, thêm 2 vòng làm nóng, mở `zsh -l` với cấu hình thật của người dùng.

```
baseline                   median   703.7 ms   p90   761.9 ms   overhead    +0.0 ms
wrapped, login inner       median   739.6 ms   p90   758.0 ms   overhead   +35.9 ms
wrapped, non-login inner   median   716.9 ms   p90   742.3 ms   overhead   +13.2 ms
```

Ba dòng số đo trên lấy từ **bản bench đầu tiên** (nhãn và thứ tự biến thể như trên; chạy trước khi khối có bước kiểm tra `--version`). Bước kiểm tra này thêm khoảng 2,4 ms, đo riêng; chưa chạy lại bench với khối cuối cùng.

So PATH với cùng cấu hình thật, qua ZDOTDIR tạm:
- **Shell bên trong là login:** đủ 45 mục nhưng **đổi thứ tự**. `/opt/local/bin`, `/opt/homebrew/bin`… nhảy lên trước vì `/etc/zprofile` (path_helper) và `.zprofile` chạy lại. Thứ tự đổi thì lệnh trùng tên có thể chạy bản khác.
- **Shell bên trong không phải login:** PATH **giống hệt** cửa sổ thường.
- Cửa sổ Terminal.app thật (khối dùng `--login`): PATH có thêm 5 mục lặp ở cuối.

### Kiểm tra theo ứng dụng

**Khối đã dùng khi thử trên Terminal.app thật là bản ĐẦU TIÊN**: shell bên trong chạy với `--login`, chưa có bước kiểm tra `--version`, chưa có xử lý `ZDOTDIR`. Khối cuối cùng (shell bên trong không phải login, kiểm tra `--version`, `ZDOTDIR`, điều kiện `ZSH_SCRIPT`/`ZSH_EVAL_CONTEXT`) mới chỉ chạy trong test PTY và giả lập, **chưa** thử trên cửa sổ Terminal.app thật. Lần kiểm trên cửa sổ thật với khối cuối đã làm sau đó; xem mục ngay dưới.

**Thử lại trên cửa sổ thật với khối cuối (2026-10-01, người dùng đồng ý lần hai):**
- Cửa sổ mới được bọc (`SHELLX_TERM=1`). Tiêu đề là `shellx-term wrap -- /bin/zsh ▸ zsh`, và `▸ vim` khi chạy vim.
- **PATH giống hệt cửa sổ thường** (31 mục).
- `[[ -o login ]]` sai và `logout` báo "not login shell", đúng như cái giá đã ghi.
- vim và Ctrl+C chạy đúng.
- `source ~/.zshrc` bằng tay trong một zsh không được bọc **không thay shell**: biến vẫn còn.
- Đóng cửa sổ đang chạy `sleep` thì không hỏi; đây là R2, người dùng đã chấp nhận.
- **Thay `shellx-term` đã cài bằng file hỏng thì cửa sổ mới vẫn mở bình thường:** tiêu đề `-zsh`, không bị bọc, không có thông báo lỗi.
- Sau đó `~/.zshrc` được gỡ khối và so `cmp` giống hệt hai bản sao; `shellx-term` và thư mục `ShellX` đã xóa.

Các kiểm tra trên Terminal.app được làm tự động: AppleScript `do script` gõ lệnh vào đúng tab thử theo tty; nút đóng được bấm bằng System Events trên đúng cửa sổ thử. Không gửi phím nào vào cửa sổ khác của người dùng.

Cột Terminal.app trong bảng dưới là kết quả của khối đầu tiên (xem trên).

| Ứng dụng | Tiêu đề (R2) | Hỏi khi đóng (R2) | Integration (R1) | PATH giống trước | Checklist 1–8 | Ghi chú |
|---|---|---|---|---|---|---|
| Terminal.app | Trước: `lehuuphu — -zsh — 80×24`. Có khối: `lehuuphu — shellx-term wrap --login -- /bin/zsh ▸ zsh` (lúc chạy vim thì `▸ vim`). Danh sách tiến trình của tab: `login, shellx-term` | Shell rảnh: không hỏi (như trước). **Đang chạy lệnh (`sleep`): không hỏi, lệnh bị giết.** Trước khi có khối: hỏi "Do you want to terminate running processes in this window?" | — | Không (login: lặp 5 mục) | 2 `SHELLX_TERM=1` ✓; 3 vim/less/top mở và thoát ✓; 4 Ctrl+C ✓, Ctrl+Z dừng tiến trình ✓; 5 đổi cỡ → `stty size` = `30 100` ✓; 6 dán 200 dòng (có tiếng Việt) → `pasted=200` ✓; 7 chữ tiếng Việt gõ qua AppleScript ✓ (**chưa thử bộ gõ IME**); 8 `exit 3` → mã 3 ✓ | Với `exec -a -zsh`, tiêu đề thành `-zsh wrap -- /bin/zsh ▸ zsh` và tiến trình thành `login, -zsh`: Terminal lấy tên từ argv |
| Cursor | chưa kiểm bằng tay | chưa kiểm | **Mất** (giả lập bằng script integration thật của Cursor: không còn `__vsc_precmd`, không có OSC 633). Đặt `export ZDOTDIR=$VSCODE_ZDOTDIR` trước `exec` thì **có lại** (`INTEGRATION=on`, có OSC 633) | — | chưa kiểm bằng tay | Lệnh dò môi trường `-ilc` đã có test riêng: không bị bọc |
| Android Studio | chưa kiểm bằng tay | chưa kiểm | **Mất phần thiết lập của IDE** (giả lập bằng `plugins/terminal/zsh/.zshenv`: phím `^[^[[C` từ `forward-word` thành `undefined-key`). Đặt `export ZDOTDIR=$_INTELLIJ_ZDOTDIR` trước `exec` thì **có lại** | — | chưa kiểm bằng tay | |
| iTerm2 | chưa kiểm (chưa cài) | | | | | |
| VS Code | chưa kiểm (chưa cài) | | Dùng cùng script với Cursor, nên dự đoán giống Cursor | | | |
| Warp | chưa kiểm (chưa cài; đang loại trừ trước) | | | | | |

Còn cần người thử tay: gõ bằng bộ gõ tiếng Việt (IME); Cmd+W trên Terminal.app; giao diện thật của Cursor và Android Studio (dấu lệnh, phím tắt, mở lại Cursor từ Dock).

## Quyết định sau P1 (2026-10-01)

- **R1 — integration của IDE: sửa được, không cần loại trừ.**
  - Cursor/VS Code chèn integration bằng `ZDOTDIR`; Android Studio/JetBrains cũng vậy. Khối `exec` trước khi IDE kịp cài hook, nên shell bên trong mất integration (giả lập bằng chính script của hai IDE đã xác nhận).
  - Cách sửa: trước khi `exec`, khối zsh đặt `export ZDOTDIR=$VSCODE_ZDOTDIR` (hoặc `$_INTELLIJ_ZDOTDIR`). Shell bên trong khi đó chạy lại integration. Khối không có đoạn "trả `ZDOTDIR` về như cũ" khi `exec` thất bại (đã bỏ): zsh thoát hẳn nếu `exec` thất bại, nên thay vào đó khối chạy `shellx-term --version` trước, và chỉ đổi `ZDOTDIR` rồi `exec` khi lệnh này thành công (xem mục kế tiếp).
  - Khối bash loại trừ `TERM_PROGRAM=vscode` và `TERMINAL_EMULATOR=JetBrains-JediTerm`, vì integration bash của hai IDE nạp qua `--init-file`, không chạy lại được.
  - Còn phải người thử trên giao diện thật của Cursor và Android Studio.
  - Warp vẫn loại trừ trước (chưa cài để kiểm).
- **Kiểm tra trước khi `exec` (thêm trong P1).** zsh 5.9 thoát hẳn khi `exec` thất bại (đã kiểm: "exec format error" rồi shell thoát).
  - Nếu không có bước này, một `shellx-term` hỏng hoặc sai kiến trúc CPU sẽ làm **mọi cửa sổ zsh mới đóng ngay khi mở**.
  - Khối nay chạy `shellx-term --version` trước, khoảng 2,4 ms. Chỉ khi lệnh này thành công thì khối mới đổi `ZDOTDIR` và `exec`; nếu không, cửa sổ chạy như terminal thường.
  - Chỉ còn một rủi ro rất nhỏ: file bị thay đổi đúng vào khoảng giữa bước kiểm tra và `exec`.
- **Khoảng trống đã biết (JetBrains):** nếu người dùng tự đặt `ZDOTDIR` riêng và mở terminal trong IDE JetBrains, shell bên trong rơi về `$HOME`, vì `.zshenv` của IDE đã xoá `_INTELLIJ_ORIGINAL_ZDOTDIR`. Hiếm gặp; ghi cho P2.
- **R2 — Terminal.app: chạy đúng, nhưng có hai khác biệt.**
  1. **Tiêu đề cửa sổ** thành `shellx-term wrap -- /bin/zsh ▸ …` thay vì `-zsh`. Terminal lấy tên từ argv (thử `exec -a -zsh` thì tiêu đề thành `-zsh wrap -- /bin/zsh ▸ zsh`). Hướng sửa cho P2: truyền tham số qua biến môi trường và đặt `argv[0]` giống shell gốc, khi đó tiêu đề gần như y cũ.
  2. **Mất cảnh báo khi đóng cửa sổ đang chạy lệnh.** Cửa sổ thường hỏi "Do you want to terminate running processes in this window?"; cửa sổ có `shellx-term` thì đóng luôn và lệnh bị dừng. Lý do: Terminal chỉ xét tiến trình trên tty của cửa sổ, còn lệnh chạy trên PTY bên trong. `shellx-term` không chặn được thao tác đóng (Terminal gửi SIGHUP). Đây là giới hạn của hướng A; iTerm2 nhiều khả năng cũng vậy (chưa kiểm).
     - **Người dùng chọn (a) (2026-10-01):** chấp nhận, và cửa sổ xác nhận khi bật tính năng phải nói rõ điều này (spec §10.1). Không đề nghị đổi cài đặt "Ask before closing".
- **R3 — shell zsh bên trong chạy không phải login.**
  - +13,2 ms so với +35,9 ms (ngưỡng 50 ms). PATH giống hệt cửa sổ thường; dạng login làm đổi thứ tự PATH.
  - Cái giá: `~/.zlogin` và các thiết lập không phải biến môi trường (alias, hàm, option) trong `~/.zprofile` không áp dụng cho cửa sổ được bọc. Ngoài ra `logout` báo lỗi ("not login shell") trong cửa sổ zsh được bọc, và `[[ -o login ]]` là sai đối với logic trong rc của người dùng.
  - Ý tưởng cho P2: export một biến đánh dấu để shell bên trong chạy `setopt login` (chưa kiểm xem khi đó `.zlogin` có được đọc không).
  - bash giữ `--login`. Khối bash nằm đầu `.bash_profile` nên có thể bị cùng vấn đề đổi thứ tự PATH (chưa đo; bash hiếm trên macOS). Ghi cho P2.
- **Cho P4:** file cấu hình có thể là symlink (dotfile manager), nên bộ cài thật phải ghi xuyên qua link như `dev-block.sh`. Phải từ chối sửa khi khối hỏng (chỉ có dấu mở, hoặc dấu sai thứ tự), và gỡ khối phải trả file về đúng từng byte (file không có xuống dòng cuối, CRLF).
- **Sửa sau review cuối P1 (zsh):**
  - `source ~/.zshrc` gõ tay trong cửa sổ chưa bọc không còn `exec` thay shell đang chạy (mất job, hàm, biến). Khối zsh thêm điều kiện `$ZSH_EVAL_CONTEXT != toplevel*`: khi zsh đọc file khởi động, ngữ cảnh là `file` (hoặc `file:file` khi script của IDE `source` tiếp `.zshrc`), còn `source` gõ tay cho `toplevel:file`. Không dùng `== file` như đề xuất ban đầu vì sẽ làm hỏng tích hợp IDE (VS Code/JetBrains `source` file của người dùng, ngữ cảnh `file:file`; test `vscode_style_injection_repoints_zdotdir` bắt được).
  - `zsh -i /đường/dẫn/script` không còn bị bọc (điều kiện `-z "${ZSH_SCRIPT-}"`). `bash -i script` vẫn bị bọc (xem danh sách P2).
  - `shellx-term` nay tự treo (SIGHUP) phiên bên trong khi đọc cửa sổ gặp EOF/lỗi, kể cả khi ứng dụng terminal bị kill mà SIGHUP không tới `shellx-term`; trước đó cả `shellx-term` lẫn shell bên trong có thể sống mồ côi.
  - Chỉ cài panic hook cho lệnh `wrap`; đối số lạ in một dòng `shellx-term: unknown arguments; starting a plain shell` rồi vẫn mở shell thường.
- **Ghi cho P2 (không làm trong P1):**
  - bash: `. ~/.bashrc` / `. ~/.bash_profile` gõ tay vẫn `exec` thay shell (chưa có cách phát hiện sạch; ý tưởng `BASH_LINENO`/`BASH_SOURCE`); `bash -i script` vẫn bị bọc.
  - Biến đánh dấu để shell zsh bên trong chạy `setopt login` (xem R3).
  - SIGTERM: nếu `shellx-term` khởi động khi SIGTERM đang bị bỏ qua thì giữ nguyên việc bỏ qua (zsh tương tác bỏ qua SIGTERM; `pkill -f zsh` hiện đóng được cửa sổ đã bọc).
  - `SHELLX_TERM=1` được thừa kế bởi ứng dụng mở từ cửa sổ đã bọc (vd `code .`) nên terminal của chúng không bao giờ được bọc; ghi tty bên trong vào biến và so với `$TTY`.
  - Sai zsh khi `ZSH_ARGZERO` là đường dẫn tương đối và ứng dụng chạy zsh không phải login (lệnh tùy chỉnh của iTerm2): bước thăm dò `--version` có thể lấy đường dẫn file thực thi của tiến trình cha.
  - Terminal.app khôi phục phiên (`SHELL_SESSION_DID_INIT` không được export): kiểm tay.
- **Đã kiểm bằng tự động:** Ctrl+C, Ctrl+Z, đổi cỡ, dán 200 dòng, UTF-8, mã thoát, vim/less/top. **Chưa có người thử:** bộ gõ tiếng Việt (IME), Cmd+W, giao diện Cursor và Android Studio. Cả bốn thuộc danh sách §11.6 khi làm P5.
- **Người dùng quyết GO cho P2 (2026-10-01).**

## P2a — `shellx-term` nối agent, macOS (2026-10-01)

Nhánh `feat/terminal-sharing-p2a`. Phần phía `shellx-term` của kết nối nội bộ (spec §6) và khối tích hợp mới (§5.2). Agent (P3) và Windows (P2b) chưa làm.

**Test:** `cd term && cargo test --features test-hooks`: **146 test chạy, 2 bị `#[ignore]`** (bộ test đơn vị 59 + 9 bộ tích hợp; số này tính sau đợt sửa của review cuối; xanh 3 lần liên tiếp trước mỗi commit). `cargo fmt --check` và `cargo clippy --all-targets --features test-hooks -- -D warnings` sạch. Byte chuẩn của giao thức: `term/protocol/vectors.txt` (`vectors_match`, `proof_vectors_match`).

### Đo thời gian mở cửa sổ (sau Task 7)

`cargo run --release --example startup_bench`, khối zsh cuối cùng (có `probe`, `exec -a`, `SHELLX_TERM_LOGIN`):

```
baseline                   median   687.4 ms
wrapped (shipped block)    median   713.8 ms   overhead   +26.4 ms
```

**+26,4 ms, dưới ngưỡng 50 ms.** Số này thay cho số của P1 (+13,2 ms và +35,9 ms): shell bên trong nay chạy `setopt login` (đúng hành vi login) nên PATH vẫn giống hệt mà `.zlogin` và `logout` hoạt động.

### Những gì P2a làm (commit trong nhánh)

- `e17f4fa` thư viện + bộ mã CBOR, khung, tin nhắn, byte chuẩn.
- `51ec090`, `8d90168`, `b3cf57e` bắt tay HMAC hai chiều, file `endpoint`; hạn 5 giây tính trên từng byte; `reject` trước bằng chứng được chấp nhận (không lộ byte terminal).
- `15f8a4b` bộ đệm vòng 256 KiB và hàng chờ không bao giờ chặn 1 MiB; `dca127a` kích thước (bên cuối cùng thao tác điều khiển).
- `3aa211e` đường nối: snapshot rồi output trực tiếp, input/kích thước từ điện thoại, nối lại, không bao giờ chặn terminal.
- `070d92d` nối vào `wrap`, dấu theo tty, tên ứng dụng, giữ SIGTERM đang bị bỏ qua.
- `2af91d2` gọi bằng biến môi trường với `argv[0]` của shell gốc, `probe`, dấu theo tty trong khối, biến đánh dấu login của zsh, điều kiện `source` tay của bash.

### Các mục "Ghi cho P2" (P1)

| Mục | Trạng thái |
|---|---|
| bash: `. ~/.bashrc` gõ tay vẫn `exec` thay shell | **Xong** (`2af91d2`, `BASH_LINENO[0] == 0`), còn hai giới hạn đã ghi ở spec §5.2 |
| bash: `bash -i script` vẫn bị bọc | **Còn mở** (zsh đã xử lý, bash chưa) |
| zsh login: biến đánh dấu + `setopt login` (R3) | **Xong** (`2af91d2`; có test PTY: `.zlogin` chạy một lần, `logout` thoát 0) |
| Tiêu đề cửa sổ: tham số qua biến môi trường, `argv[0]` giống shell gốc (R2) | **Xong** (`2af91d2`, `exec -a`) |
| SIGTERM đang bị bỏ qua thì giữ nguyên | **Xong, sửa ở review cuối:** `070d92d` chỉ giữ trạng thái "bỏ qua" có sẵn, nhưng zsh/bash đặt lại SIGTERM về mặc định trước `exec` nên đường khối không bao giờ thấy trạng thái đó. Nay `shellx-term` do khối gọi (không đối số + `SHELLX_TERM_WRAP`) luôn bỏ qua SIGTERM; `wrap …` tường minh vẫn giữ nguyên trạng thái lúc khởi động. Test PTY với bản thật cho zsh và bash (`kill -TERM $PPID`), spec §5.4 mục 6 |
| `SHELLX_TERM=1` bị thừa kế (`code .`): ghi tty bên trong, so với `$TTY` | **Xong** (`070d92d` đặt tty, `2af91d2` so trong khối); hệ quả: mọi PTY mở từ cửa sổ đã bọc cũng được bọc (spec §5.2) |
| Sai zsh khi `ZSH_ARGZERO` tương đối / zsh không login | **Xong** (`2af91d2`, `probe` thay cho đoán từ `$SHELL`/`--version`) |
| JetBrains với `ZDOTDIR` tùy chỉnh: shell bên trong rơi về `$HOME` | **Còn mở** (hiếm; chưa có cách sửa) |
| Terminal.app khôi phục phiên (`SHELL_SESSION_DID_INIT` không export) | **Còn mở**, chỉ kiểm tay được |

### Cần biết khi dùng

- Khối cần binary có `probe`: bộ cài (P4) cài binary vào `bin` **trước** khi ghi khối. Binary cũ gặp khối mới sẽ mở shell thường trong `$(…)` và trông như treo.
- Điều kiện bash `BASH_LINENO[0] == 0` không bắt được hàm bọc một dòng (`reload() { . ~/.bashrc; }`) và bỏ qua rc được `source` từ file khác: người dùng chỉ có `.profile` + `.bashrc` có cửa sổ login không bọc. P4 đặt khối vào cả `.bash_profile` và `.bashrc`.
- Mọi PTY mở từ cửa sổ đã bọc (`script`, `asciinema rec`, `:terminal` của nvim, `code .`) được bọc riêng và hiện là một terminal chia sẻ thêm (chủ ý của dấu theo tty).
- Nhánh `elif` (`setopt login`) cũng áp dụng cho shell thường do fallback mở: chủ ý.
- Thứ tự khóa CBOR là thứ tự byte (Rust `BTreeMap`), không phải thứ tự chuẩn "độ dài trước" của RFC 8949. P3 phải ghi cùng thứ tự để khớp từng byte `vectors.txt`.

### Việc nhỏ còn mở tại thời điểm viết

Từ review từng task. **Các mục đã gạch ở dưới được sửa trong đợt sửa của review cuối** (cùng nhánh); phần còn lại vẫn mở tại thời điểm viết:

- **Cho P3 (agent):** bộ giải mã nhận số nguyên không ở dạng ngắn nhất (chỉ bộ mã hóa ghi dạng ngắn nhất); không có test quét ngẫu nhiên "không panic" (cắt cụt/đổi byte) trên các vector.
- **Cho P2b/tiếp theo (độ bền của đường nối):**
  - ~~`output()`/`send()` chạy trong lúc `finish` đang xả có thể đẩy khung sau `exit`~~ **Xong** (`live` tắt cùng khối khóa với việc đẩy `exit`; test `no_frame_follows_exit`). Còn mở: một phiên có thể bắt đầu sau `finish`; mất đánh thức trong `nap`.
  - ~~Luồng đọc của agent chết mà output vẫn chảy thì không bị phát hiện~~ **Xong** (`read_agent` đóng socket khi kết thúc nên luồng ghi lỗi ngay; test `a_malformed_agent_frame_ends_the_session_even_while_output_flows`).
  - Thay đổi kích thước trong lúc bắt tay bị mất tới lần đổi sau (cần đẩy lại `Size` khi vào `live`).
  - Callback `LinkEvents` chạy trên luồng đọc và teardown join luồng này: `input()` bị chặn sẽ làm kẹt nối lại (cần ghi tài liệu hoặc tách).
  - `Timing::backoff` panic nếu vector rỗng; `output()` vẫn mã hóa sau khi hàng chờ tràn.
- **Cho `wrap`/`fallback`:**
  - ~~HOME không đặt → portable-pty gõ `\n^D`~~ **Xong** (luồng cửa sổ kết thúc bằng `std::mem::forget(writer)`; chưa có test riêng cho trường hợp HOME không đặt).
  - ~~Panic của luồng link làm exec shell thường~~ **Xong** (mọi luồng link tên `shellx-link…`, panic hook bỏ qua chúng, link dừng còn terminal tiếp tục; lỗi tạo luồng nghĩa là "không có phiên lần này"; test `a_panic_in_the_link_thread_does_not_cost_the_terminal_session` với `SHELLX_TERM_FAULT=link-panic`).
  - ~~Fallback `exec_shell` không gỡ `SHELLX_TERM_WRAP`/`SHELLX_TERM_WRAP_LOGIN`~~ **Xong** (test `the_fallback_shell_does_not_inherit_the_block_s_wrap_variables`).
  - ~~`SHELLX_TERM="1"` khi không lấy được tên tty~~ **Xong** (trả `WrapError::Pty`, đi đường fallback; không có test vì không giả lập được `tty_name() == None`).
  - ~~Khối nên gọi `probe </dev/null`~~ **Xong** (cả `block.zsh` lẫn `block.bash`).
  - Còn mở từ review cuối (ghi nhận, chưa sửa): `SIGTERM` thoát mà không gửi `exit` cho agent; một `sleep` 200 ms trong test kích thước; `Fields` clone; `start(None)` chưa có test; test bash cùng tty với bản thật; kiểm tra chỉ-tiền-tố ở `block.rs`; vài chi tiết nhỏ ở §5.4.2/§6.3.
  - Đã sửa thêm ở review cuối: cửa sổ test nay có HOME tạm riêng (`Harness::spawn`; trước đó luồng link của test có thể nối vào agent thật ở HOME thật; `startup_bench` cố ý dùng HOME thật, đã ghi trong tài liệu của nó); kích thước từ điện thoại bị kẹp trong 1..=1000; tên ứng dụng cắt ở 64 ký tự; test `finish` với khung không ghi được ngay mà chưa tràn hàng chờ (~950 KiB, vì 600 KiB lọt hết vào bộ đệm socket của macOS nên không thử được đường cần thử).
- **Test:** vài khoảng trống (kích thước ở mức bằng nhau, bash cùng tty, zsh sai bản với binary thật, test khởi động lại để lại agent cũ đang nghe); `read_endpoint` gộp mọi lỗi IO thành `Missing`.

### Còn mở sau review cuối P2a (chuyển sang P2b)

- **SIGTERM bị bỏ qua lọt sang shell dự phòng.** Với cửa sổ do khối mở, `shellx-term` bỏ qua SIGTERM trước một số bước có thể thất bại: tạo PTY, đăng ký tín hiệu, không có tên tty, spawn, panic. Nếu bọc thất bại, shell bash dự phòng và các chương trình con của nó thừa hưởng SIGTERM đang bị bỏ qua, nên `kill PID` không dừng được chúng (đã tái hiện). zsh tự đặt lại cho tiến trình con. Cách sửa: lưu trạng thái SIGTERM ban đầu và trả về trước `exec_shell` cũng như trong panic hook. — **đã sửa ở P2b Task 1.**
- **Panic trong `WrapEvents::input` hoặc `MasterResizer` làm khóa writer/master bị "poison".** Khi đó luồng cửa sổ lặng lẽ thôi nhận phím và đổi kích thước. Chỉ xảy ra nếu chính portable-pty panic khi ghi hoặc đổi kích thước, nên rất hiếm. Cách sửa: khóa tự phục hồi (`unwrap_or_else(|e| e.into_inner())`). — **đã sửa ở P2b Task 1.**
- **Luồng đọc của liên kết panic thì bỏ qua bước `shutdown` (M4).** Hệ quả: output vẫn chạy nhưng input từ điện thoại mất lặng lẽ cho tới hết phiên. Cách sửa: một drop guard tự gọi `shutdown`. — **đã sửa ở P2b Task 1.**
- Lặt vặt: một câu "test finish treo" trong mục **Test** ở trên đã lỗi thời (M5 đã thêm test này); chú thích của test M5 trong `tests/link.rs` bị thụt lề lạ. — **đã sửa ở P2b Task 1.**

## P2b — `shellx-term` trên Windows (2026-10-01)

Nhánh `feat/terminal-sharing-p2b`. Cổng Windows của `shellx-term` (spec §5.3) và workflow `windows-check`. Chưa chạy trên máy Windows thật.

**Test (macOS):** `cd term && cargo test --features test-hooks`: **157 chạy xanh, 2 `#[ignore]`**. `cargo fmt --check` và `cargo clippy --all-targets --features test-hooks -- -D warnings` sạch. Test Windows (`term/tests/windows.rs`) và mã `cfg(windows)` chưa biên dịch được trên macOS. **CI Windows: chờ Task 8 (lần chạy CI Windows đầu tiên).**

### Commit trong nhánh

- `996ccdf` SIGTERM trả về trạng thái ban đầu trước shell dự phòng; khóa chống poison; luồng đọc link tắt phiên cả khi panic.
- `803ea17` lõi phiên dùng chung; đường dẫn endpoint và tên ứng dụng theo nền tảng; test và harness sẵn cho Windows.
- `15b08cc` bộ mã hóa thuần UTF-16 (phím) và UTF-8 (luồng) cho console Windows.
- `c0bd03b` lớp console Windows: chế độ VT thô, kích thước, phím, đổi cỡ, output UTF-16, close handler.
- `e1337d1` wrapper Windows: shell ConPTY, relay console, đường nối agent, thoát 222 khi không bọc được.
- `8a67f9d` khối tích hợp PowerShell; test tích hợp Windows; kiểm tra văn bản khối trên mọi nền tảng.
- `7ae6b3b` test Windows chờ đường nối agent và ping trước khi gõ; khối chạy tiếp sau khi sập hoặc lỗi trình nạp.
- `b01d1a0` cửa sổ test Windows giữ lịch sử PSReadLine trong thư mục tạm của chính nó.
- Commit của Task 7: workflow `windows-check`, spec, ledger, HANDOFF.

### Khối PowerShell (`term/shell/block.ps1`)

- Danh sách cho phép đối số: `-NoLogo`, `-NoProfile`, `-NoProfileLoadTime`, `-NoExit`, `-Login`, `-l` (không phân biệt hoa thường); đối số khác thì không bọc. Thay cho danh sách cấm ở bản spec đầu.
- Điều kiện `Get-History -Count 1`: `. $PROFILE` gõ tay sau đó không bọc.
- `$global:LASTEXITCODE = 222` đặt trước lệnh gọi, `catch` rỗng. Thoát bằng `[Environment]::Exit($LASTEXITCODE)` chỉ khi mã khác 222 **và** không âm; mã âm (sập, thiếu `VCRUNTIME140.dll`) coi như 222. Sau đó `Remove-Variable LASTEXITCODE`.

### `shellx-term` trên Windows

- Chế độ console: stdin tắt PROCESSED/LINE/ECHO/MOUSE, bật VIRTUAL_TERMINAL_INPUT và WINDOW_INPUT; stdout bật PROCESSED_OUTPUT, VIRTUAL_TERMINAL_PROCESSING, DISABLE_NEWLINE_AUTO_RETURN.
- Input qua `ReadConsoleInputW`, ghép surrogate giữa các sự kiện; nhả phím Alt mang ký tự tính là một lần gõ (Alt+số).
- Output qua `WriteConsoleW` (UTF-16), xử lý UTF-8 bị cắt giữa hai lần đọc.
- Kích thước: `WINDOW_BUFFER_SIZE_EVENT` **và** kiểm mỗi 250 ms (conhost cổ điển chỉ báo đổi buffer).
- Close handler khôi phục console; mất console giết shell bên trong; panic ngoài luồng link khôi phục console và thoát 222.
- Thoát: bước xả output chờ đủ 500 ms (ống ConPTY chỉ đóng cùng pseudoconsole).
- Dấu shell bên trong `SHELLX_TERM=conpty:<pid>`; endpoint `%LOCALAPPDATA%\ShellX\term\endpoint`.

### Giới hạn đã biết

- Không có kiểm tra theo tty trên Windows: ứng dụng terminal mở từ cửa sổ đã bọc không bọc terminal của chính nó.
- Shell bên trong thoát với 222 hoặc mã âm thì rơi về shell ngoài.
- Tích hợp PowerShell của VS Code (`-NoExit -Command …`) không được bọc.
- Ctrl+Space / Ctrl+@ (NUL) chưa tới shell bên trong, nên `MenuComplete` của PSReadLine không dùng được.
- Mỗi lần thoát trên Windows chậm thêm khoảng 0,5 s.
- **Việc cho P4:** dựng `shellx-term.exe` với `+crt-static` để không phụ thuộc VCRUNTIME.

### Workflow `windows-check`

`.github/workflows/windows-check.yml`: `workflow_dispatch` và push lên `windows-check/**`; chạy `cargo fmt --check`, `clippy` và `test` (`--locked`) trên `windows-latest` và `macos-latest`. Bước đầu đặt `core.autocrlf=false` vì runner Windows mặc định là `true`. Rust ghim ở 1.95.0 (bản trên máy Mac) để lint/định dạng của bản stable mới hơn không làm đỏ CI. Phạm vi chỉ `term/`; P3/P4 thêm `dart test` và `flutter build windows`. `workflow_dispatch` chỉ dùng được khi file đã nằm trên nhánh mặc định.

### Kiểm tay Windows còn thiếu

- Windows Terminal thật (không chỉ conhost).
- Bộ gõ (IME): Telex/VNI qua Unikey hoặc IME của Windows.
- Đóng tab khi lệnh đang chạy.
- Mã hóa profile của PowerShell 5.1 (khối chỉ ASCII; kiểm profile có tiếng Việt và không BOM).
- Ctrl+Space (xem giới hạn).
- Đổi cỡ cửa sổ conhost cổ điển (đặc biệt chiều cao khi scrollback dài).
- Lối tắt PowerShell 7 ở Start menu có thể truyền `-WorkingDirectory ~`, đối số này không nằm trong danh sách cho phép nên cửa sổ đó sẽ không được bọc (chưa xác minh).
- Ctrl+Break cũng tới PowerShell bên ngoài trong lúc nó chờ.

### Review cuối P2b (2026-10-02)

Chạy sớm, song song với lần CI Windows đầu, để lỗi CI và lỗi review sửa chung một vòng đẩy. Kết luận: cần sửa 1 lỗi Important, không có Critical; 5 mục Review Focus đều đúng khi lần theo code; tên/chữ ký winapi 0.3.9 và lời gọi portable-pty 0.9.0 đã đối chiếu với source; `Cargo.lock` đủ cho Windows.

- **I1 — Xong:** trên Windows, `CommandBuilder::new` của portable-pty đè môi trường của tiến trình bằng giá trị registry (PATH, TEMP, PSModulePath…), nên shell bên trong mất PATH của venv/`conda activate`/`terminal.integrated.env` của VS Code. Nay `winwrap` xóa môi trường gốc của builder rồi chép nguyên môi trường của cửa sổ; test Windows `the_inner_shell_keeps_the_window_s_environment` (`OS` đặt khác registry).
- **M1 — Xong:** workflow ghim Rust 1.95.0.
- **M2 — Còn mở:** chưa có test Windows kiểm console được trả về chế độ cũ sau khi thoát hoặc panic (spec §11.1); hướng: thử phím Up sau khi carry-on và một test khối với lỗi `panic`.
- **M3 — Còn mở:** `appname.rs` xét `WT_SESSION` trước `TERM_PROGRAM`, mà `WT_SESSION` được thừa kế, nên VS Code mở bằng `code .` từ một tab Windows Terminal sẽ hiện là "Windows Terminal". Hẹp, spec không quy định thứ tự.

## P3 — agent + giao thức (2026-10-05)

Nhánh `feat/terminal-sharing-p3` (cắt từ `origin/windows-check/p2b` = `main` + `d6f778f`). Plan: `docs/superpowers/plans/2026-10-05-terminal-sharing-p3-agent-protocol.md`. Phía agent của đường nối nội bộ (spec §6), phiên `desktop` (§7.1–7.5, §7.7–7.9), giao thức điện thoại (§8), e2e (§11.4). Relay, web, `term/src/**` và giao diện mobile/desktop không đổi; thay đổi duy nhất ở `term/` là ví dụ chỉ dành cho test `term/examples/fake_window.rs`.

### Môi trường

- Flutter 3.41.7 cài qua `fvm install 3.41.7` (gọi bằng `PATH="$HOME/fvm/versions/3.41.7/bin:$PATH"`); fvm toàn cục vẫn là 3.38.2.
- Rust 1.95.0 cài qua rustup (`--no-modify-path`), gọi bằng `PATH="$HOME/.cargo/bin:$PATH"`, không đổi PATH của máy.
- e2e chạy với relay cục bộ (`npm run dev`, `SHELLX_E2E_RELAY=http://127.0.0.1:8787`). Không kết nối `relay.shellx.pro`.

### Test (lần chạy cổng cuối, 2026-10-05)

| Gói | Kết quả |
|---|---|
| `packages/shellx_core` | 280 xanh |
| `packages/shellx_agent` | 275 xanh (271 trước vòng sửa sau review cuối) |
| `packages/shellx_client` | 103 xanh |
| `packages/shellx_e2e` `test/term_link_test.dart` | 3 xanh (`shellx-term` thật) |
| `apps/desktop` | 269 xanh |
| `apps/mobile` | 501 xanh |
| `term/` (`cargo test --features test-hooks`) | 157 xanh, 2 `#[ignore]` (không đổi) |

`dart analyze` / `flutter analyze` sạch ở mọi gói; `cargo fmt --check` và `cargo clippy --all-targets --features test-hooks -- -D warnings` sạch. Đường cơ sở trước P3: core 261, agent 167, client 98, desktop 269.

e2e trên relay cục bộ (Task 12): toàn bộ `packages/shellx_e2e` **11 xanh** (7 e2e cũ + 3 `term_link` + 1 `desktop_terminal_e2e_test.dart`); file mới chạy thêm 3 lần liên tiếp đều xanh. Không chạy lại ở Task 13 (cổng cuối không khởi động relay).

### Commit trong nhánh (`git log --oneline main..HEAD`)

```
ecea0eb test(e2e): desktop terminal over the relay — list, earlier output, typing, detach, re-attach, exit code (spec §11.4)
ec4bdb6 feat(agent): TerminalSharing; test(e2e): real shellx-term through the agent — earlier output, phone typing and size, window takes the size back, exit code, agent restart (spec §11.4)
f6e9373 feat(client): desktop sessions — listSessions(includeDesktop), desktopSharing, tab kind/app/title, TabDriver, closeTab detaches desktop tabs
1456af4 feat(agent): SessionRouter — shared ids, merged session.list, desktop attach only for phones that listed with desktop: true, every close path spares desktop terminals (spec §7.2, §7.9)
8d9464a feat(agent): DesktopSessionManager — desktop sessions over TermLink: snapshot, 30 s reconnect, driver/size, titles, exit; no way to end a terminal (spec §7, T13)
38d28b2 feat(agent): OSC 0/2 window-title parser that survives chunk splits (spec §7.4)
baf969a feat(agent): TermServer — loopback port, endpoint, HMAC handshake with 5 s deadline, reject limit/version, links that close past 1 MiB queued
40abace feat(agent): endpoint file — per-platform path, 0700/0600 before the secret, atomic write, delete only our own (spec §6.1)
18203ff test(core): drop imports made redundant by the cbor_values export
3ac3991 feat(agent): local-link codec — messages, frames and HMAC proofs, byte-exact with term/protocol/vectors.txt
65a257e refactor(agent): SessionManager uses SessionStream and an injectable id allocator; AgentService takes AgentSessions (existing tests unchanged)
b6bd6ed feat(agent): SessionStream (phone-facing half of a session), RingBuffer.restartWith, shared session id allocator, AgentSessions interface
a5205de feat(core): terminal sharing messages — session.list desktop, desktop_sharing, desktop SessionInfo, session.detach, session.driver, terminal_gone (spec §8)
9f4a023 docs: implementation plan P3 — agent + protocol (terminal sharing)
fe7ea0a docs: P3 spec — the desktop-capable flag is kept per phone across channel losses (tabs re-attach without listing)
3688f0b docs: terminal sharing P3 design — agent structure (T13), data flow, errors and compatibility, tests; real-relay e2e run by the user (T14)
d6f778f fix(term): the Windows inner shell keeps the window's environment, not the registry's; ci: pin Rust 1.95.0; docs: P2b final review
```

Commit của Task 13: workflow `windows-check` (job `dart`), ledger này, HANDOFF, trạng thái spec.

### Quyết định của người điều phối (rulings)

- Ruling: dùng Flutter 3.41.7 cài bằng `fvm install 3.41.7` (người dùng đã duyệt), fvm toàn cục giữ 3.38.2 — workspace cần Dart ^3.11, 3.38.2 chỉ có Dart 3.10 (đã kiểm: `pub get` lỗi) — cái giá nếu sai: không có cho các dự án khác.
- Ruling: lúc đầu Rust chưa cài và người dùng chưa duyệt, nên Task 11–12 viết đúng như plan và mọi bước cần cargo/`shellx-term` ghi "chờ: cần Rust" — người dùng chưa cho cài thêm toolchain ngoài Flutter — cái giá nếu sai: `fake_window.rs` và test dùng binary thật hạ cánh chưa kiểm. **Đã thay thế** bằng ruling kế tiếp.
- Ruling: người dùng yêu cầu cài Rust 1.95.0 (2026-10-05): cài qua rustup `--no-modify-path --profile minimal` kèm clippy, rustfmt, gọi bằng `PATH="$HOME/.cargo/bin:$PATH"`; nền `cargo test` của `term/` 157 xanh / 2 `#[ignore]`; Task 11–13 chạy đủ cargo và test binary thật — lệnh của người dùng — cái giá nếu sai: không có.
- Ruling: `hello`/`auth` đến sau `ready` vẫn được chuyển ra `TermLink.messages` (plan quy định, review Task 6 Minor 2), giữ nguyên; `DesktopSessionManager` coi `TermHello() || TermAuth()` là lỗi giao thức và bỏ link — giữ hành vi đã định trong plan — cái giá nếu sai: người tiêu thụ `TermLink` sau này cũng phải tự xử lý hai tin nhắn này.
- Ruling: T13 — phiên `desktop` có bộ quản lý riêng (`DesktopSessionManager`) **không có hàm tắt**, phần chung rút ra `SessionStream`; không giả làm `Pty` có `kill()` rỗng, không dùng một `SessionManager` chung có cờ `kind` — an toàn của terminal không được phụ thuộc vào việc không quên một nhánh — cái giá nếu sai: thêm một lớp và `AgentSessions` để ghép, trùng một ít mã.
- Ruling: cờ "điện thoại đã `session.list {desktop: true}`" được giữ theo từng điện thoại qua các lần mất kênh (sửa spec §7.9, commit `fe7ea0a`) và chỉ xóa khi thu hồi — tab mở sẵn phải nối lại được mà không liệt kê lại — cái giá nếu sai: một điện thoại bị thu hồi rồi ghép lại phải liệt kê lại; nếu cờ bị xóa sớm, tab desktop không nối lại được sau khi mất kênh.
- Ruling: `listSessions(includeDesktop: false)` là mặc định cho đến P5 — `session.list` không có `desktop: true` và câu trả lời phải giống từng byte như hiện nay, app mobile hiện tại chưa biết phiên `desktop` — cái giá nếu sai: P5 phải nhớ bật `includeDesktop: true`, nếu quên người dùng không thấy phiên desktop.
- Ruling: `TermSize` từ `shellx-term` bị bỏ qua (kích thước do `driver` quyết định, bên cuối cùng thao tác điều khiển) — tránh hai nguồn kích thước giằng co — cái giá nếu sai: khi cửa sổ đổi cỡ mà điện thoại đang lái, kích thước phía điện thoại không theo cửa sổ.
- Ruling: `driver(phone)` được gửi cho `shellx-term` trên **mọi** lần điện thoại đổi cỡ (không chỉ lần đầu) — để cửa sổ biết điện thoại đang lái và lấy lại cỡ khi nó gõ — cái giá nếu sai: thêm một tin nhắn nhỏ mỗi lần đổi cỡ.
- Ruling: dùng ví dụ `term/examples/fake_window.rs` thay cho `script(1)` để giả cửa sổ terminal trong test — `script(1)` khác nhau giữa macOS/Linux/Windows và không điều khiển được cỡ/thoát — cái giá nếu sai: một chương trình test thêm cần biên dịch và (trên Windows) clippy qua `windows-check`.
- Ruling (lệch plan đã chấp nhận, Task 8): `_dropLink` đặt thêm `live=false` vì mã trong brief sập khi `input`/`resize` đến lúc `exit` đang xả; thêm test hồi quy — cái giá nếu sai: không có.
- Ruling (lệch plan đã chấp nhận, Task 11): `buildTermBinaries` đưa `$HOME/.cargo/bin` lên đầu PATH; `tearDown` chờ cửa sổ thoát rồi thử xóa HOME tạm (tối đa 5 giây) — cái giá nếu sai: thử lại có thể che việc bash ghi `.bash_history` (xem "Việc nhỏ còn mở").

### Việc nhỏ còn mở (đánh dấu "FLAG FOR FINAL REVIEW")

Các mục đã sửa hoặc đã gỡ ở vòng sửa sau review cuối nằm trong mục kế tiếp. Còn mở:

- `input()` dùng `s.link!` sau khi `_drive` đã phát (nên lấy `link` trước) (`desktop_session_manager.dart`).
- `tearDown` của `term_link_test.dart` vẫn giữ vòng thử xóa HOME tạm có giới hạn (nay chỉ là lưới an toàn: `HISTFILE=''` đã chặn `.bash_history`); chưa cho cửa sổ của test 3 tự thoát.
- "Cửa sổ lấy lại cỡ" mới chỉ được chứng minh bằng tin nhắn `driver`; thêm `stty size` → `24 80` (`term_link_test.dart:110`).

### Sửa sau review cuối (2026-10-05)

Review cuối toàn nhánh: một mục Important và các mục nhỏ, sửa trong một lượt (báo cáo cục bộ `.superpowers/sdd/2026-10-05-terminal-sharing-p3-agent-protocol/final-fix-report.md`).

1. **Important — `TerminalSharing.start/stop` chạy đua:** `stop()` gọi lúc `start()` đang chờ bind/ghi `endpoint` trả về ngay và chia sẻ vẫn BẬT; hai `start()` cùng lúc bind hai server, rò server thứ nhất. Nay `TerminalSharing` xếp `start`/`stop` thành một hàng đợi theo thứ tự gọi (`start` lỗi chỉ ném cho người gọi, không chặn hàng); `TermServer` ghi rõ người gọi phải tuần tự hóa. Test: "stop while start is in flight leaves sharing off and no endpoint file", "two concurrent starts bind one server" (`terminal_sharing_test.dart`).
2. `@internal` đặt lại trên cả `handleDriver` lẫn `handleDetached` (`client_tab.dart`).
3. `dart format` cho `term_auth.dart`, `term_messages.dart`, `machine_client.dart`, `messages.dart` (và lint `curly_braces_in_flow_control_structures` lộ ra ở `term_messages.dart`).
4. Test mới: một `TermLink` sống quá 2× hạn bắt tay vẫn gửi được và không bị đóng (`term_server_test.dart`).
5. Test router `closeSession(desktopId)` và `closeAll` nay khẳng định điện thoại nhận `session.detached {closed_by_host}` và phiên không còn điện thoại gắn (`session_router_test.dart`).
6. `DesktopSessionManager.disconnectPhone` bỏ qua phiên đang xả sau `exit` (như `SessionManager.closeSession`): việc xả kết thúc và điện thoại nhận `session.exited` thay vì `closed_by_host` mà không có `session.exited`. Có test.
7. Chú thích cũ: `AgentService` (đóng phiên là việc của chủ `AgentSessions`, tức `SessionRouter.closeAll`); `DesktopSessionManager.outbound` mang cảnh báo gọi ngược đồng bộ như `SessionRouter`/`SessionManager`.
8. `TermWindow` đặt `HISTFILE=''` (bash không ghi `.bash_history` vào HOME tạm khi SIGHUP); giữ vòng thử lại có giới hạn trong `tearDown`.

Mục đánh dấu của Task 5 (`deleteIfOwned` để lọt `FormatException`) là **báo nhầm**: `File.readAsString` bọc lỗi giải mã thành `FileSystemException`, đã được bắt.

**Lệch §11.4 (đã chấp nhận):** spec muốn e2e qua relay chạy với relay trong bộ nhớ; thực tế `desktop_terminal_e2e_test.dart` chạy với relay Node cục bộ (`npm run dev`) và bị bỏ qua khi không có `SHELLX_E2E_RELAY`. Cổng mặc định phủ luồng này theo từng phần: `term_link_test.dart` (`shellx-term` thật qua agent) và harness của `shellx_client` với relay trong bộ nhớ.

Các việc nhỏ khác đã hoãn (không đánh dấu) nằm trong `.superpowers/sdd/2026-10-05-terminal-sharing-p3-agent-protocol/progress.md` (cục bộ, không vào git).

### Việc chờ người dùng

- **T14 — chạy e2e trên relay thật** (không chạy trong P3): `cd packages/shellx_e2e && SHELLX_E2E_RELAY=https://relay.shellx.pro dart test test/desktop_terminal_e2e_test.dart`
- **CI Windows của job `dart` mới** (`shellx_core` + `shellx_agent` trên `windows-latest` và `macos-latest`): chỉ đẩy nhánh `windows-check/p3` khi người dùng bảo. Các test `term_endpoint`/`term_server`/`terminal_sharing` là `@TestOn('mac-os || linux')`; bộ mã, tên cửa sổ, luồng, router và bộ quản lý phiên desktop chạy cả trên Windows. Lần chạy này cũng kiểm clippy cho `fake_window.rs` trên Windows.
- Spec §7.7–§7.9, T13–T14 đang "chờ người dùng đọc lại".

### Ghi cho P4

- `TerminalSharing` bật/tắt từ công tắc (start/stop theo `enabled`).
- `agent_runtime.dart`: `desktopSharing: () => sharing.enabled`.
- Menu khay liệt kê `DesktopSessionManager.sessions`.
- Thông báo từ `phoneAttached` (giới hạn 10 phút cho mỗi cặp (điện thoại, terminal)).
- Đường dẫn endpoint lấy từ `termEndpointPath(environment: Platform.environment, windows: Platform.isWindows)`.
- Chưa có test của `apps/desktop` cho việc phiên desktop sống sót qua `runtime.stop`/`closeSession`/`closeAllSessions`.

### Ghi cho P5

- Gọi `listSessions(includeDesktop: true)`.
- Gợi ý `desktopSharing` có ba giá trị null/false/true (agent cũ / tắt / bật).
- Banner của `TabDriver` (ai đang lái).
- Thẻ `TabDetached(terminalGone)`: hiện `terminal_tab_controller.dart:142` vẫn ánh xạ `terminal_gone` sang banner "đóng bởi máy chủ".
- Điện thoại giành phiên (`taken_over`) khi phiên đang do điện thoại lái và cùng kích thước thì **không** nhận `session.driver` (`desktop_session_manager.dart:439`, `_drive` thoát sớm khi `!changed && driver == phone`): banner của P5 phải coi bên lái là "phone" ngay sau khi gắn.
