# ShellX v1 — Checklist go-live

Một file duy nhất để quyết định phát hành v1. Gộp và loại trùng từ `HANDOFF.md` §3–§22, `release/README.md` và các ledger. Chi tiết từng bước gốc vẫn nằm ở `HANDOFF.md` (số § ghi trong ngoặc). Ghi kết quả (đạt/không, ngày, máy) vào `ledgers/a1-desktop-terminal.md`.

Quy ước: `[M]` macOS desktop, `[W]` Windows desktop, `[iOS]` iPhone, `[AND]` Android, `[S]` relay/web/cửa hàng. Mỗi dòng: **việc làm** → *kết quả mong đợi*. Sắp theo rủi ro: mất dữ liệu, bảo mật, crash, rồi luồng lõi.

Tình trạng chung: mọi mục dưới đây **chưa ai chạy trên máy thật** (Windows chưa từng chạy cả app, chỉ biên dịch chéo). Phiên bản v1 chỉ phát hành khi toàn bộ P0 đạt.

---

## A. P0 — bắt buộc đạt trước khi phát hành

### A1. macOS desktop (26 mục)

Dữ liệu và an toàn thoát (§11, §15, §20)
1. **M-01** Mở 4 tab, `kill -9` ShellX, mở lại; rồi `kill -9` ngay khi cửa sổ vừa hiện, mở lại → đủ 4 tab, có dải "đóng bất thường". Đóng hết tab rồi ⌘Q → mở lại màn hình rỗng.
2. **M-02** ⌘Q (menu) với tab đang chạy `sleep 1000` → một hộp xác nhận; đồng ý thì mọi shell và cây tiến trình biến mất (`ps`), Hủy thì còn nguyên. ⌘Q lần hai khi hộp mở → vẫn một hộp.
3. **M-03** Đăng xuất / Khởi động lại / Tắt máy macOS khi có tab đang chạy lệnh → ShellX không chặn, không hiện "ShellX đã ngăn tắt máy". Mở lại: khôi phục đủ, không dải.
4. **M-04** Khôi phục: workspace, tab, tên, cây pane, tỉ lệ; `seq 1 5000` giữ 3001…5000 + vạch "Phiên được khôi phục"; vim đang mở lúc thoát → lưu nội dung trước vim.
5. **M-05** Quyền thư mục `restore/`: `ls -l` là 700/600, `tmutil isexcluded` → Excluded. Tray → Terminal → tắt lưu → `restore/scrollback` rỗng ngay.
6. **M-06** Dán lớn (A10 T3): chạy `integration_test/pty_test.dart`; dán 800 KB vào `cat > /tmp/x` và vim, `wc -c` khớp; 5 MB hỏi trước; 20 MB bị từ chối.
7. **M-07** Đổi cỡ cửa sổ/đường chia chậm rồi nhanh trong `vim`, `htop`, `claude` → thả chuột xong không còn màn hình vẽ dở; đổi cỡ rồi gõ ngay một phím vẫn đúng.

Bảo mật (§16, §18, §20)
8. **M-08** CLI: `ls -l ~/Library/Application\ Support/pro.shellx.desktop/mux/` → `mux.sock` `srw-------`, `endpoint` `-rw-------`, thư mục `drwx------`; `echo ${#SHELLX_CLI_TOKEN}` trong tab ShellX = 64.
9. **M-09** Terminal.app (không phải shell ShellX): `shellx ls` → thoát 6 cho tới khi tick "Cho phép terminal khác"; bỏ tick → bị từ chối ngay (cả `events --follow` đang chạy). Tài khoản macOS khác → thoát 3.
10. **M-10** SSH: mật khẩu/passphrase đã gõ không xuất hiện ở đâu (`grep -r` thư mục app support + plist); thư mục `/tmp/shellx-ssh-$(id -u)` là `drwx------`; thư mục tạo sẵn bởi user khác → log `ssh: control dir unsafe` và SSH vẫn chạy.
11. **M-11** Thả/dán đường dẫn: kéo tệp (tên có dấu cách, tiếng Việt, emoji, ngoặc) vào zsh/bash/fish → đường dẫn đã escape + một dấu cách, **không Enter**. Pane SSH từ chối thả/dán ảnh (toast), dán chữ vẫn chạy.

Crash/độ ổn định và terminal lõi (§11, §20)
12. **M-12** Mở app: một tab zsh `-l` ở `~`, prompt đầu tiên hiện đúng một lần; Dock + ⌘Tab + menu "Quit ShellX"; nút đỏ ẩn cửa sổ (Dock biến mất), mở lại từ Dock/tray còn nguyên tab; ⌘M rồi bấm Dock/tray → cửa sổ bung ra.
13. **M-13** `vim`, `htop`, `less`, Claude Code; truecolor `printf '\e[38;2;255;100;0mTRUECOLOR\e[0m\n'`; kéo đổi cỡ → vẽ lại đúng; F6 thường tới được `htop`.
14. **M-14** `yes` 10 s rồi Ctrl+C, và `cat` file 50 MB → UI không treo quá 1 s; ẩn rồi mở lại thấy output mới nhất.
15. **M-15** 32 tab × `seq 1 20000` → bộ nhớ ổn định, UI mượt; ghi số Activity Monitor.
16. **M-16** Rút màn hình ngoài (cửa sổ đang ở màn ngoài) rồi mở lại → cửa sổ hiện giữa màn còn lại.

Gõ tiếng Việt (§11, §12, §17, §20)
17. **M-17** Telex/Unikey/macOS VN: gõ "Tiếng Việt" trong zsh, vim và **trong Claude Code**, không mất/lặp ký tự; lặp lại sau khi đổi tab (⌘1/⌘2, bấm sidebar) và sau khi chia pane.
18. **M-18** Telex trong ô tên tab/workspace, thanh tìm ⌘F, bảng lệnh ⌘⇧P (`tieesng`, `ddoongj`): Enter chỉ chốt khi hết soạn, khớp không phân biệt dấu.
19. **M-19** Phím soạn dòng (A11): Ctrl-A/E, Option+←/→, Option+Backspace, ⌘+Backspace sửa đúng dòng trong zsh/bash/fish; không chặn phím trong `vim`; gõ Telex có dùng Option vẫn ra dấu.

SSH (§18)
20. **M-20** SSH tới máy Linux (khoá trong agent): pane mở ≤ 500 ms, không hỏi mật khẩu lần hai khi chia pane; host key lần đầu hỏi `yes/no` trong pane; khoá đổi → pane `failed`, `known_hosts` không bị đụng.
21. **M-21** Tắt Wi-Fi 60 s rồi bật → dải đếm ngược, tự kết nối lại cùng chỗ, cwd khôi phục; sai mật khẩu không bao giờ tự thử lại. tmux: đóng tab rồi `tmux ls` vẫn thấy; rớt Wi-Fi → gắn lại, `top` còn chạy.

CLI và thông báo (§13, §16)
22. **M-22** `shellx ls`/`ls --json`, `split --right --cmd "python3 -m http.server 8000"` + `wait --match` + `read`, `send --text` nhiều dòng, `events --follow`, `help`; `time shellx --version` ≤ 50 ms. "Cài lệnh cho mọi terminal": không ghi được `/usr/local/bin` → hộp mật khẩu, Hủy không đổi gì.
23. **M-23** Thông báo: tab không chọn `printf '\e]9;Build xong\a'` → badge + dòng + Dock 1 ≤ 200 ms; `shellx notify`, OSC 777, OSC 99; `sleep 11; false` → "✗ … mã 1 · 11 giây"; BEL liên tục 10 s ≤ 2 chuông.
24. **M-24** Cửa sổ ở sau/thu nhỏ/Space khác: thông báo hệ thống tới; bấm trong Notification Center → cửa sổ lên trước, đúng tab, badge mất, gõ được ngay. Claude Code `preferredNotifChannel` = kitty/iterm2/terminal_bell → tab có badge khi chờ trả lời.

Ghép nối điện thoại (§11)
25. **M-25** Tray "Ghép nối điện thoại…" → quét QR (cả khi cửa sổ 640×400) → ghép xong, hộp tự đóng. Đăng xuất tray → điện thoại bị ngắt, shell còn chạy; tắt "Cho phép truy cập từ xa" khi có điện thoại → hỏi, shell còn chạy.
26. **M-26** Điện thoại + desktop cùng gõ vào một tab: không ai bị đẩy ra, dải vàng "Điện thoại đang dùng…" đúng, desktop gõ 1 s lấy lại; điện thoại "Đóng" tab desktop → chỉ tách, shell còn chạy.

### A2. Windows desktop (14 mục) — chặn phát hành

Windows chưa từng chạy; mỗi mục dưới đây cũng là lần chạy đầu tiên của đường code đó.

1. **W-01** `flutter build windows` thành công (`/W4 /WX`); bản cài (Inno) chạy trên **Windows Sandbox** sạch (không thiếu `vcruntime`), ký xong hiện đúng publisher. Windows 10 1809 và Windows 11.
2. **W-02** Mở từ Start: tab PowerShell ở `%USERPROFILE%`, nút taskbar khi hiện/mất khi ẩn, title bar tối từ khung hình đầu; Alt+F4/X → ẩn vào khay, chạy ShellX.exe lần hai → hiện lại, không có tab thứ hai.
3. **W-03** Tray "Thoát" với tab đang mở → hỏi; đồng ý → `Get-Process pwsh,powershell` không còn tiến trình con. Đăng xuất / tắt máy Windows không bị ShellX chặn.
4. **W-04** Khôi phục: `seq`, màu, vim, `End task` → dải "đóng bất thường"; Start → Restart → khôi phục đủ, không dải; huỷ tắt máy rồi `End task` → lần sau có dải; thư mục `%LOCALAPPDATA%\ShellX\restore` chỉ có quyền tài khoản của bạn (`icacls`).
5. **W-05** Phím: Ctrl+Shift+T/W/C/V, Ctrl+Alt+1…9, Ctrl+Tab, Ctrl+=/−/0; Ctrl+C vẫn ngắt lệnh trong PowerShell.
6. **W-06** **AltGr** (bàn phím Đức/Ba Lan/Pháp): AltGr+Q → `@`, AltGr+7/8 → `{`/`[` trong PowerShell và vim; AltGr+Shift+D, AltGr+mũi tên không chia/chuyển pane; kể cả khi `keybind` tuỳ biến dùng Alt.
7. **W-07** Tiếng Việt Unikey/EVKey: gõ "Tiếng Việt" trong PowerShell, vim và Claude Code, sau khi đổi tab, trong ô tên tab, thanh tìm, bảng lệnh.
8. **W-08** Dán 800 KB / 5 MB / 20 MB, `yes`/`cat` 50 MB không treo UI; thả tệp từ Explorer (tên có dấu cách, tiếng Việt) vào PowerShell và cmd → escape đúng, không Enter.
9. **W-09** CLI: `where shellx` trong tab ShellX; pipe `\\.\pipe\shellx-mux-…` chỉ DACL tài khoản của bạn; `windows_pipe_transport_test.dart` xanh; `shellx ls/split/send/read/events --follow` chạy; Setup đè lên ShellX đang chạy thay được `shellx.exe`; gỡ cài đặt xoá `cli\` và mục Path.
10. **W-10** Thông báo: OSC 9/777, `shellx notify`, `sleep 11; false`; toast Action Center bấm → cửa sổ lên trước, đúng tab; chấm accent + nháy taskbar; Explorer restart → chấm trở lại.
11. **W-11** SSH (ssh.exe 8.x+, ssh-agent): đăng nhập trong pane, mật khẩu hiện dấu nhắc ConPTY, Ctrl+C, `~.`, đổi cỡ vim; không có OpenSSH Client → toast gợi ý Settings.
12. **W-12** Hook PowerShell phát OSC 7 trên cả PowerShell 5.1 và pwsh 7: `cd` vào `C:\tmp\a b`, `C:\tmp\Tài liệu`, `C:\tmp\c#1`, `C:\tmp\100%` → thư mục hiện đúng; cổng `:8000` đúng trên Windows bản địa hoá (Đức/Pháp/Việt), không có cửa sổ console nháy mỗi 3 s.
13. **W-13** Cửa sổ: kéo đổi cỡ (tối thiểu 640×400), Snap layouts, nhớ vị trí; rút màn ngoài rồi mở lại → hiện giữa màn còn lại; màn hình 125 %/150 % đường chia pane 1 px sắc nét.
14. **W-14** Ghép nối điện thoại bằng QR từ tray, điện thoại gõ vào tab desktop và ngược lại; gỡ cài đặt xoá `restore\` và không còn tiến trình ShellX.

### A3. iPhone (9 mục)

1. **I-01** Đăng nhập, quét QR ghép nối với desktop, mở lại app có Face ID; đăng xuất → không còn nhận gì (§3).
2. **I-02** Terminal I/O: duyệt danh sách máy → mở phiên, gõ lệnh, xem output, đổi cỡ/xoay ngang; mở tab của desktop; gõ cùng lúc với desktop không bị đẩy ra.
3. **I-03** Bàn phím mềm tiếng Việt (Telex, VNI) gõ thẳng vào terminal, **kể cả trong Claude Code**: mỗi ký tự đúng một lần; bàn phím Bluetooth có dấu không gửi trùng.
4. **I-04** Giọng nói: chạm mic → hai hộp thoại quyền (micro, nhận dạng) bằng tiếng Việt; nói "chạy git status gửi" → `git status` chạy; từ chối quyền → dòng lỗi + "Mở Cài đặt" đúng trang.
5. **I-05** Giọng nói trong Claude Code: một câu dài rồi "gửi" → tới đúng một lần, không tách dòng. Ô soạn gõ `--help` (không thành `—help`), `'x'` (không nháy cong).
6. **I-06** Giọng nói bị gián đoạn: có cuộc gọi/khoá màn hình lúc đang nghe → dừng nghe, chữ còn nguyên, không tự gửi. Chế độ máy bay → hiện "Cần kết nối mạng…" hoặc vẫn chạy nếu Apple nhận dạng trên máy.
7. **I-07** Thông báo đẩy: đã cấp APNs key; hỏi quyền một lần sau khi ghép nối; `sleep 40; false` trên desktop → nhận "✗ sleep 40; false · mã 1 · 40 giây" khi app foreground, nền và **đã đóng hẳn**; chạm → mở đúng máy/tab (kể cả khi tắt mạng rồi bật lại); tắt thông báo trong cài đặt máy → Settings app hiện "Đang tắt — Mở Cài đặt hệ thống". Bản TestFlight/App Store phải có `aps-environment = production`.
8. **I-08** Xem dạng văn bản trong `claude` (câu trả lời dài): chọn, sao chép, "Sao chép tất cả", VoiceOver, 2 000 dòng cuộn mượt; chạm URL (`gh pr create`) → bảng Mở/Sao chép.
9. **I-09** Hiệu năng: desktop `yes | head -c 50M` ở tab A, sang tab B trên điện thoại gõ → echo tức thì, không giật; 4 tab bận trong 1 phút không nóng/hao pin bất thường.

### A4. Android (7 mục)

1. **A-01** Đăng nhập, quét QR (cả "Quét lại" cùng một mã; cấp quyền camera từ Cài đặt), mở lại app có khoá sinh trắc (§3).
2. **A-02** Terminal I/O, mở tab của desktop, gõ cùng lúc không đẩy nhau; bàn phím mũi tên trong `vim`/`claude`.
3. **A-03** Gboard/Samsung Keyboard Telex/VNI gõ vào terminal và ô soạn giọng nói (kể cả Claude Code): ghép dấu đúng, mỗi ký tự một lần, không gạch đỏ chính tả; bàn phím cứng không gửi trùng; dán từ gợi ý clipboard của bàn phím.
4. **A-04** Giọng nói (máy có Google app): lần chạm mic đầu trên Android 13+ không treo (≤ 2 s); VI chạy qua cloud khi chưa có gói on-device; chip VI chỉ mờ khi bộ nhận dạng báo lỗi ngôn ngữ; nói một câu dài trong Claude Code → đúng một lần.
5. **A-05** Từ chối quyền micro → dòng lỗi + "Mở Cài đặt" mở đúng trang ShellX; cuộc gọi đến khi đang nghe → dừng, không tự gửi.
6. **A-06** Thông báo đẩy FCM: foreground, nền, **đã đóng hẳn**; chạm mở đúng máy/tab; Android 13+ hỏi quyền một lần; trạng thái Settings đúng khi tắt thông báo.
7. **A-07** `flutter build appbundle` thành công, bản release (không chỉ debug) cài được và đăng nhập/ghép nối/push chạy; Xem dạng văn bản và chạm URL như iPhone.

### A5. Relay, web và cửa hàng (4 mục)

1. **S-01** Relay thật: `curl https://relay.shellx.pro/v1/version` đúng phiên bản; `docker compose logs relay | grep push_` thấy `push_enabled {"project":"shellxpro"}`; e2e trên relay thật: `cd packages/shellx_e2e && SHELLX_E2E_RELAY=https://relay.shellx.pro dart test test/desktop_terminal_e2e_test.dart` xanh.
2. **S-02** Quy trình phát hành theo đúng thứ tự (`release/README.md`): dry run → tag `desktop-v1.0.0` → URL tải về công khai → `LATEST_AGENT_VERSION/MAC_URL/WIN_URL` → `CHECK_DOWNLOADS=1 npm run build` web. DMG tải bằng trình duyệt trên Mac sạch chỉ hiện hộp "tải từ Internet"; trang web mới có nút tải chạy.
3. **S-03** Trang privacy/terms vi + en lên **trước** khi phát hành app có push; đã có mục thông báo đẩy, SSH, agent, khôi phục phiên; tên pháp nhân/địa chỉ đã điền và có người chuyên môn xem; câu về log ≤ 30 ngày khớp thực tế (Docker xoay log 10 MB × 3).
4. **S-04** Nhãn quyền riêng tư cửa hàng: App Store Connect (FCM token = Device ID, Audio data cho giọng nói) và Play Data safety khớp privacy; điền `apps/desktop/assets/whats_new.json` cho đúng số phiên bản v1 (khoá hiện là `1.1.0`, thiếu thì thẻ "Có gì mới" không hiện).

Tổng P0: macOS 26 · Windows 14 · iPhone 9 · Android 7 · relay/web/cửa hàng 4 = **60**.

---

## B. P1 — có thể làm sau khi phát hành (không chặn)

Làm trong 2 tuần đầu, theo thứ tự này:

- **Trợ năng**: VoiceOver/Narrator cho sidebar, thông báo, bảng lệnh, Cài đặt, dải khôi phục, dải SSH; "Giảm chuyển động" (§12–§14, §17, §18).
- **Sidebar A2**: cwd/nhánh git, cổng nghe (`lsof`/`netstat`), CPU ≤ 2 % với 10 tab, kéo thả workspace/tab + tự cuộn, worktree/submodule, SMB/monorepo, `fs_usage` khi cửa sổ ẩn (§12).
- **Chia pane A3**: ⌘D/⌘⇧D theo cwd, cỡ PTY từng pane, phóng to, đóng pane, thông báo theo pane, 125 % DPI (§14).
- **Bộ gõ/phím A9, A11**: Option-as-Alt, `keybind` hai bước, trình sửa phím tắt với symlink/CRLF/BOM, theme Ghostty, Cài đặt (7 trang), copy mode, ba lần nhấp, mở lại tab ⌘⇧T, lịch sử focus, zoom workspace, ghim/mô tả tab, tour và "Có gì mới" (§17, §21).
- **Liên kết và tìm kiếm A10/A11**: ⌘/Ctrl-click URL và đường dẫn, OSC 8, ⌘F, ⌘⇧F, chuyển/tách pane, `shellx doctor` (§20, §21).
- **Phiên nền A5b** (mặc định TẮT nên chỉ cần kiểm khi định bật mặc định): 15 mục macOS + W1–W9 Windows (§19).
- **SSH nâng cao**: cổng forward, OTP/PAM, mật khẩu-only, hiệu năng D44 (`ssh -G` ≤ 80 ms, hộp mở ≤ 50 ms), Linux/Windows chi tiết (§18).
- **Agent A12**: cài hook cho Claude Code/Gemini/Codex/OpenCode (chưa kiểm với bản thật), trạng thái pane, "Tiếp tục phiên", PR qua `gh`, `agent-event-command`, đổi ngôn ngữ, "Kiểm tra cập nhật", chip agent trên mobile (§22).
- **Chia sẻ terminal máy tính** với iTerm2, VS Code, Warp, Cursor, Android Studio; Windows Terminal thật, conhost cổ điển, PowerShell 5.1 (§4, §9).
- **Hạ tầng VPS**: diễn tập rollback, backup, `X-Real-IP`/429 sau nginx-proxy, `pong` qua đường chậm, `docker inspect` giới hạn bộ nhớ relay (§4).
- **Mobile phụ**: danh sách máy "đầu ra mới", nháp theo terminal, giữ cỡ terminal khi bàn phím mở, TalkBack/VoiceOver cho bàn phím mũi tên (§21).
- **Hạn chế còn mở khác**: giới hạn khoá API Firebase; dọn Cloudflare; kiểm Linux (không phát hành Linux).

---

## C. Blocker phát hành

| # | Blocker | Việc cần làm | Ai |
|---|---|---|---|
| 1 | **CI Windows đang đỏ** (`windows-check.yml`) | Cần log lỗi của lần chạy gần nhất (Actions → Windows check → job lỗi). Chưa có nên chưa kết luận được nguyên nhân; C++ của runner (`flutter_window.cpp`, `daemon_runner.cpp`), Inno Pascal và plugin hotkey chưa từng biên dịch. Phải xanh trước khi tag. | Bạn gửi log, rồi sửa |
| 2 | **Windows chưa từng chạy trên máy thật** | Hết mục A2 (14 mục). Không đạt = không phát hành bản Windows; có thể phát hành macOS + mobile trước. | Bạn |
| 3 | **Ký macOS + notarize** | Developer ID, 11 secret trong GitHub Environment `release`, dry run, tag; `notarize.sh` + `spctl` pass. | Bạn |
| 4 | **Ký Windows** | Azure Trusted Signing có thể không nhận nhà phát hành Việt Nam → dùng chứng chỉ OV và sửa hai bước ký trong workflow; nếu chưa ký, SmartScreen cảnh báo. | Bạn |
| 5 | **Cửa hàng** | iOS: APNs key vào Firebase, App ID bật Push, bản Archive build được (chưa từng build iOS) và `aps-environment = production`; Android: `appbundle` + SHA-1 Play App Signing; nhãn riêng tư; icon 1024×1024. | Bạn |
| 6 | **Pháp lý** | Tên pháp nhân/địa chỉ cho privacy/terms; người chuyên môn xem; thống nhất câu log ≤ 30 ngày. | Bạn |
| 7 | **Bản dịch** | Chữ tiếng Việt "Cần đăng nhập" (SSH) và "phiên nền" chờ người bản ngữ duyệt (không chặn, nên làm trước release). | Bạn |
| 8 | **Ghi chú phát hành** | Phải nêu đổi phím `⌘,` / `Ctrl+,` nay mở Cài đặt (mở tệp: `⌘⌥,` / `Ctrl+Shift+Alt+,`). Bản nháp ở mục F. | Đã có nháp |

---

## D. Tính năng TẮT mặc định trong v1 (và lý do)

| Tính năng | Bật ở đâu | Vì sao tắt |
|---|---|---|
| Phiên nền "Giữ shell chạy khi đóng cửa sổ" (A5b) | Tray → Terminal | Cổng bật mặc định là 15 mục macOS + W1–W9 Windows chưa chạy; tắt = đường trong tiến trình đã ổn định. Hệ quả: ⌘Q đóng mọi shell (có hộp xác nhận); khôi phục phiên mở shell mới ở cwd cũ. |
| Trạng thái PR + CI trong sidebar (`pr-status`) | Cài đặt › Agent | Cần `gh` đã đăng nhập; `gh` chạy trong thư mục pane nên với repo lạ nó đọc cấu hình git của repo đó. |
| `agent-event-command` | Tệp cấu hình | Chạy lệnh của người dùng; cổng cho phép theo SHA-256, đường dẫn tuyệt đối, không qua shell, Windows chỉ `.exe`. |
| Phím toàn cục hiện/ẩn cửa sổ (`global-hotkey`) | Cài đặt hoặc tệp cấu hình | Plugin luôn báo thành công nên không phát hiện được tổ hợp bị app khác chiếm (im lặng không chạy); C++ Windows chưa biên dịch. |
| "Cho phép terminal khác" điều khiển bằng `shellx` | Tray → Dòng lệnh | Mặc định chỉ shell do ShellX mở (có `SHELLX_CLI_TOKEN`) điều khiển được; là rào chặn nhầm lẫn, không phải ranh giới bảo mật với mã độc cùng tài khoản. |
| Cài hook agent (`shellx integrations install`) | Cài đặt › Agent hoặc terminal | Sửa tệp cấu hình của Claude Code/Gemini/Codex/OpenCode; luôn có diff + hỏi `y/N`; payload chưa kiểm với bản thật. |
| Chia sẻ terminal (Terminal.app, iTerm2…) | Tray | Phải bật tay (sửa file shell rc); trên Windows còn là thử nghiệm cho tới khi kiểm xong (`SHELLX_EXPERIMENTAL=terminal-sharing`, xem §9). |
| Giữ cỡ terminal khi bàn phím mở (mobile) | Cài đặt app | Tuỳ chọn; mặc định giữ hành vi cũ. |
| Đọc cấu hình Ghostty | Mặc định **bật** (có thông báo một lần) | Ghi để biết: `ghostty-config = false` tắt. |

---

## E. Giới hạn đã biết (đưa vào ghi chú phát hành)

- Windows: v1 là bản đầu tiên chạy thật; Linux chưa phát hành. Narrator không đọc nội dung web (không có trình duyệt trong v1).
- Terminal dựa trên xterm 4.0.0: **không có ligature** (`font-feature` chỉ ghi nhận), không có RIS (`ESC c`) nên vùng OSC 8 bị xoá khi đổi màn chính/phụ.
- Shell **không sống qua ⌘Q** khi phiên nền tắt (mặc định); khôi phục mở shell mới ở thư mục cũ và vẽ lại nội dung cũ.
- Khôi phục lưu nội dung terminal (có thể chứa bí mật) trong `restore/` (0700/0600, loại khỏi Time Machine, không rời máy); tắt được ở tray.
- Lịch sử tab vừa đóng (⌘⇧T) chỉ trong bộ nhớ (10 mục / 2 MiB). Tách/chuyển pane không có hoàn tác. Pane đã chuyển tab mất huy hiệu chưa đọc.
- ⌘⇧F chỉ tìm trong phần nhìn thấy khi TUI (vim, htop, tmux) dùng màn phụ. Alt-kéo khối không chạy khi chương trình bật báo chuột.
- Thả/dán đường dẫn được escape theo shell lúc khởi chạy pane (gõ shell khác bên trong dùng quy tắc ngoài); không bao giờ kèm Enter. Pane SSH không nhận ảnh dán/thả. Tệp thả > 16 MiB bị bỏ im lặng.
- SSH: cổng forward bị huỷ khi pane cuối của máy chủ đóng; hook agent không đi qua SSH; điện thoại không mở được phiên SSH; tên máy chủ/thư mục có thể hiện trong danh sách phiên điện thoại (qua kênh mã hoá).
- tmux mở như một tab chạy tmux client thật (không phản chiếu cửa sổ/pane tmux).
- Agent: Codex chỉ báo hết lượt; trạng thái "điện thoại đã trả lời" là heuristic; sự kiện hook mất khi chạy phiên nền không cửa sổ; ngôn ngữ cần khởi động lại.
- Mobile: bộ đếm "đầu ra mới" cũng đếm phần phát lại sau kết nối lại; không có trình duyệt ShellX; Android giữ gợi ý bàn phím bật để Telex hoạt động.
- Thông báo: OSC 99 và BEL chỉ ở máy tính, không push sang điện thoại.
- Tiếng Việt: chữ giao diện "phiên nền", "Cần đăng nhập" chờ duyệt bởi người bản ngữ.

---

## F. Release notes v1 (bản nháp)

### English

**ShellX 1.0 — your computer's terminal, in your pocket and on your desktop.**

- Control the terminals on your Mac or Windows PC from your iPhone or Android phone, end-to-end encrypted. Pair with a QR code, open any session, type, paste, speak commands by voice (Vietnamese and English).
- A full terminal window on desktop: workspaces and tabs in a sidebar showing folder, git branch and listening ports; split panes; Vietnamese input (Telex/VNI) that just works.
- Never lose your place: sessions, layouts and scrollback are restored after a quit or crash.
- Notifications that matter: desktop badges and system notifications for commands that finish, `shellx notify`, and push notifications to your phone (even when the app is closed).
- Remote work: SSH and tmux connections with automatic reconnect; ports detected and forwarded with a click.
- `shellx` command line to script panes and tabs; works with Claude Code, Codex, Gemini CLI and OpenCode (status, "needs you" alerts, resume).
- Command palette (⌘⇧P), search in terminal (⌘F) and across all terminals (⌘⇧F), copy mode, reopen closed tab (⌘⇧T), drag and drop files and paste images.
- Settings window and a Ghostty-style config file with custom themes, fonts and key bindings.
- Off by default: background service, PR status, global hotkey, agent commands.
- **Changed shortcut:** `⌘,` / `Ctrl+,` now opens Settings. Open the config file with `⌘⌥,` / `Ctrl+Shift+Alt+,`.

### Tiếng Việt

**ShellX 1.0 — terminal của máy tính, ngay trong túi và trên màn hình.**

- Điều khiển terminal trên Mac hoặc Windows từ iPhone/Android, mã hoá đầu cuối. Ghép nối bằng QR, mở phiên bất kỳ, gõ, dán, hoặc nói lệnh bằng giọng nói (tiếng Việt và tiếng Anh).
- Cửa sổ terminal đầy đủ trên máy tính: workspace và tab ở thanh bên hiện thư mục, nhánh git, cổng đang nghe; chia pane; gõ tiếng Việt (Telex/VNI) mượt mà.
- Không mất chỗ làm việc: phiên, bố cục và nội dung cuộn được khôi phục sau khi thoát hoặc sập app.
- Thông báo đúng lúc: huy hiệu và thông báo hệ thống khi lệnh chạy xong, `shellx notify`, và thông báo đẩy sang điện thoại (kể cả khi đã đóng app).
- Làm việc từ xa: kết nối SSH và tmux tự nối lại; cổng được phát hiện và chuyển tiếp bằng một cú bấm.
- Dòng lệnh `shellx` để điều khiển pane/tab bằng script; dùng với Claude Code, Codex, Gemini CLI, OpenCode (trạng thái, báo "cần bạn", tiếp tục phiên).
- Bảng lệnh (⌘⇧P), tìm trong terminal (⌘F) và trong mọi terminal (⌘⇧F), chế độ copy, mở lại tab đã đóng (⌘⇧T), kéo thả tệp và dán ảnh.
- Cửa sổ Cài đặt và tệp cấu hình kiểu Ghostty: theme, font, phím tắt tuỳ chỉnh.
- Mặc định tắt: phiên nền, trạng thái PR, phím toàn cục, lệnh agent.
- **Đổi phím tắt:** `⌘,` / `Ctrl+,` nay mở Cài đặt. Mở tệp cấu hình bằng `⌘⌥,` / `Ctrl+Shift+Alt+,`.
