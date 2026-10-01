# Ledger — chia sẻ terminal máy tính

Spec: `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md`
Plan P1: `docs/superpowers/plans/2026-10-01-terminal-sharing-p1-shellx-term-spike.md`

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
