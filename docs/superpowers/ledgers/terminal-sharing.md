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

So PATH với cùng cấu hình thật, qua ZDOTDIR tạm:
- **Shell bên trong là login:** đủ 45 mục nhưng **đổi thứ tự**. `/opt/local/bin`, `/opt/homebrew/bin`… nhảy lên trước vì `/etc/zprofile` (path_helper) và `.zprofile` chạy lại. Thứ tự đổi thì lệnh trùng tên có thể chạy bản khác.
- **Shell bên trong không phải login:** PATH **giống hệt** cửa sổ thường.
- Cửa sổ Terminal.app thật (khối dùng `--login`): PATH có thêm 5 mục lặp ở cuối.

### Kiểm tra theo ứng dụng

Các kiểm tra trên Terminal.app được làm tự động: AppleScript `do script` gõ lệnh vào đúng tab thử theo tty; nút đóng được bấm bằng System Events trên đúng cửa sổ thử. Không gửi phím nào vào cửa sổ khác của người dùng.

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
  - Cách sửa: trước khi `exec`, khối zsh đặt `export ZDOTDIR=$VSCODE_ZDOTDIR` (hoặc `$_INTELLIJ_ZDOTDIR`). Shell bên trong khi đó chạy lại integration. Nếu `exec` thất bại, `ZDOTDIR` được trả về như cũ.
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
     - **Cần người dùng chọn:**
       - (a) chấp nhận và ghi rõ trong cửa sổ xác nhận khi bật tính năng;
       - (b) khi bật, đề nghị đổi Terminal.app → Settings → Profiles → Shell → "Ask before closing" thành **Always** (lúc nào cũng hỏi, kể cả khi shell rảnh);
       - (c) cả hai.
- **R3 — shell zsh bên trong chạy không phải login.**
  - +13,2 ms so với +35,9 ms (ngưỡng 50 ms). PATH giống hệt cửa sổ thường; dạng login làm đổi thứ tự PATH.
  - Cái giá: `~/.zlogin` và các thiết lập không phải biến môi trường (alias, hàm, option) trong `~/.zprofile` không áp dụng cho cửa sổ được bọc.
  - bash giữ `--login`. Khối bash nằm đầu `.bash_profile` nên có thể bị cùng vấn đề đổi thứ tự PATH (chưa đo; bash hiếm trên macOS). Ghi cho P2.
- **Cho P4:** file cấu hình có thể là symlink (dotfile manager), nên bộ cài thật phải ghi xuyên qua link như `dev-block.sh`. Phải từ chối sửa khi khối hỏng (chỉ có dấu mở, hoặc dấu sai thứ tự), và gỡ khối phải trả file về đúng từng byte (file không có xuống dòng cuối, CRLF).
- **Khoảng trống đã biết:** `zsh -i script` và `bash -i script` vẫn bị bọc (script không chạy). Hiếm gặp; ghi trong spec §5.2.
- **Đã kiểm bằng tự động:** Ctrl+C, Ctrl+Z, đổi cỡ, dán 200 dòng, UTF-8, mã thoát, vim/less/top. **Chưa có người thử:** bộ gõ tiếng Việt (IME), Cmd+W, giao diện Cursor và Android Studio. Cả bốn thuộc danh sách §11.6 khi làm P5.
- **Đề xuất: GO cho P2**, sau khi người dùng chọn cách xử lý R2.
