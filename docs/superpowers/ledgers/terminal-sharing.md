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
