# A9 — File cấu hình kiểu Ghostty, phím tắt tuỳ biến, bảng lệnh và skill cấu hình — Đặc tả thiết kế

- **Ngày:** 2026-10-07
- **Trạng thái:** Người dùng giao toàn quyền cho controller (như A1–A7). Controller giao người viết spec chốt toàn bộ phạm vi (đường dẫn, cú pháp, khoá, nạp lại, xung đột phím, trình sửa phím, di trú, CLI, ý nghĩa "skill"); D1–D46 ghi ở bảng §2 kèm cái giá nếu sai.
- **Lộ trình:** A1 → A2 → A4 → A3 → A5a → A5b → A6 → A7 → A8 SSH/tmux → **A9 (tài liệu này)**.
- **Thứ tự thực thi:** A9 chạy **sau khi A3, A4, A5a, A6, A7 đã merge vào `main`** (D1). **Không cần A5b, không cần A8.**
- **Tài liệu đi kèm:** UI addendum `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a9.md` (ràng buộc cho phần nhìn và chữ); plan `docs/superpowers/plans/2026-10-07-desktop-config-a9.md`.
- **Giữ nguyên:** spec A1 (D1–D16), A2 (C1–C8, D1–D19), A4 (N1–N9, D1–D27), A3 (P1–P9, D1–D30), A5a (R0–R8, D1–D26), A5b (B1–B9, D1–D30), A6 (W1–W7, D1–D38), A7 (C1–C7, D1–D40 + sửa đổi "chỉ shell của ShellX"), spec chia sẻ terminal (`2026-10-01`), spec push (`2026-10-05`). Protocol điện thoại, app mobile, relay **không đổi**. Tài liệu này chỉ **thêm** và ghi rõ chỗ nào sửa (cuối §2).
- **Ký hiệu:** "A3 D20" = quyết định D20 của spec A3; "D1" không tiền tố = của tài liệu này. "File ShellX" = `~/.config/shellx/config` (D3). "File Ghostty" = file cấu hình của Ghostty mà ShellX đọc (D4). "Phím tắt" = một **trigger** (tổ hợp phím, hoặc chuỗi hai tổ hợp) gắn với một **action**.

---

## 1. Mục tiêu

Như cmux (đọc cấu hình Ghostty cho font/màu, phím tắt tuỳ biến, bảng lệnh ⌘⇧P, lệnh tự định nghĩa, skill dạy agent sửa cấu hình) và như Ghostty (một file chữ `key = value`, nạp lại bằng ⌘⇧,): người dùng **viết một file chữ** để đổi font, cỡ chữ, bảng màu, con trỏ, lề, scrollback, Option-as-Alt, hỏi khi đóng, thư mục tab mới, **mọi phím tắt** của ShellX, và **lệnh/đoạn chữ của riêng họ**; sửa xong lưu file là ShellX áp ngay, dòng sai được chỉ rõ (file, dòng, lý do) mà **không bao giờ** làm ShellX hỏng hay mất phiên. Người dùng Ghostty mở ShellX là thấy đúng font và màu quen thuộc. Người không viết gì thấy ShellX **y như hôm nay**.

### Tiêu chí thành công (đo được)

1. **Không đổi gì khi không có file:** máy không có file ShellX và không có file Ghostty → font JetBrains Mono 13 (hoặc cỡ đã lưu bằng ⌘+/−), bảng màu A1, con trỏ khối, lề 10/6, scrollback 10 000 dòng, Option gõ ký tự, hỏi khi đóng tab đang chạy lệnh, ⌘T ở home, **mọi phím tắt A1–A6 giống hệt** (test vàng so bảng phím trước/sau A9, D24).
2. **Sửa là áp:** `echo 'font-size = 16' >> ~/.config/shellx/config` → trong ≤ 1,5 s mọi pane đổi cỡ chữ, mỗi phiên nhận lưới mới (A3 D13); `theme = /đường/dẫn/Dracula` → màu đổi ngay, không mở lại tab.
3. **Đọc Ghostty:** `~/.config/ghostty/config` có `font-family = Fira Code`, `theme = Dracula` (Ghostty đã cài) → mở ShellX lần đầu thấy Fira Code + Dracula và một toast trung tính một lần "Đang dùng font và màu từ cấu hình Ghostty". `ghostty-config = false` trong file ShellX → về mặc định ShellX.
4. **Dòng sai không làm hỏng:** file có `font-size = to` và `keybind = super+q=new_tab` → mọi dòng khác vẫn áp; toast "Cấu hình có 2 vấn đề — Xem" → bảng liệt kê "config, dòng 3 — font-size: “to” không hợp lệ (cần 9–28)" và "config, dòng 7 — Hệ điều hành giữ ⌘Q"; ShellX không crash, không mất phiên; sửa file → toast tự biến mất khi hết vấn đề.
5. **Phím tắt tuỳ biến:** `keybind = super+shift+t=new_split:down` → ⌘⇧T chia xuống; menu terminal hiện "Chia xuống dưới ⌘⇧T" (và ⌘⇧D vẫn chạy vì chưa bị bỏ); `keybind = super+d=unbind` → ⌘D tới shell; `keybind = ctrl+a>c=new_tab` → Ctrl+A rồi C mở tab, chỉ báo "Ctrl+A …" hiện trong lúc chờ.
6. **Windows AltGr:** bàn phím Đức, `keybind = ctrl+alt+q=new_tab` → Ctrl(trái)+Alt(trái)+Q mở tab; AltGr+Q vẫn gõ `@` vào shell (D26).
7. **Bảng lệnh:** ⌘⇧P (Windows Ctrl+Shift+P) mở ô tìm; gõ "chia" (hoặc "chia xuong", không dấu) → "Chia xuống dưới ⌘⇧D" lên đầu; Enter chạy; Esc đóng và trả bàn phím về pane cũ. File có `command = Lint = npm run lint` → gõ "lint" → Enter → `npm run lint` được dán + Enter vào pane đang focus.
8. **Trình sửa phím tắt:** bảng lệnh → "Phím tắt…" → hàng "Tab mới" → "Thêm phím" → bấm ⌃⌥N → file ShellX có thêm `keybind = ctrl+alt+n=new_tab` trong khối do ShellX quản lý, mọi dòng khác **giữ nguyên từng byte**; ⌃⌥N mở tab ngay; bấm ⌘D cho "Tab mới" → báo "⌘D đang dùng cho “Chia sang phải” — Thay thế?".
9. **Lệnh `shellx`:** `shellx config path` in đường dẫn file ShellX; `shellx config check` thoát 1 và in `…/config:3: error: font-size: “to” is not valid (expected 9–28)` khi có lỗi; `shellx config reload` nạp lại ngay; `shellx config show` in giá trị đang dùng kèm nguồn; `shellx skills install --claude` cài thêm skill `shellx-config` (A7 D35 mở rộng, không có lệnh cài thứ hai).
10. **Trợ năng:** bảng lệnh, bảng vấn đề, trình sửa phím dùng được chỉ bằng bàn phím, VoiceOver/Narrator đọc đúng (ô tìm có nhãn, số kết quả, mục đang chọn, phím đã ghi); chỉ báo chuỗi phím được đọc lên; F6/Shift+F6 không bao giờ bị gán lại (D25).
11. **Không hồi quy:** mọi test A1–A7 xanh; `cargo test` của `term/` xanh.

---

## 2. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| D1 | Tiền đề | A3 (bảng phím A3, intent pane), A4, A5a (scrollback lưu/khôi phục dùng `maxLines` của terminal), A6 (`browserPaneShortcuts`, `browserForwardedChords`), A7 (`UiCommandHandler`, `kCliCaps`, `term/src/api/skills.rs`) đã merge. A5b, A8 tuỳ chọn (cấu hình chỉ do tiến trình UI đọc, D41) | A6 trễ → plan Task 4/8 bỏ phần trình duyệt và ghi ledger; A7 trễ → Task 13 hoãn, phần còn lại vẫn merge được |
| D2 | Định dạng | **Một** cú pháp cho cả hai lớp: chữ thuần `key = value` của Ghostty (D5). **Không** JSON (cmux dùng `cmux.json` cho phím tắt + Ghostty cho phần vẽ). Lý do: một cú pháp để học, sao chép được dòng `keybind` từ Ghostty, sửa tay không vướng dấu phẩy/ngoặc, agent sửa bằng `echo >>` được | Người quen `cmux.json` không dán được file đó; không có biểu thức điều kiện `when` của cmux (ShellX dùng phạm vi cố định, D27) |
| D3 | Đường dẫn file ShellX | `$XDG_CONFIG_HOME/shellx/config` nếu biến có (cả hai hệ điều hành); không thì macOS `~/.config/shellx/config`, Windows `%APPDATA%\ShellX\config` (Roaming: cấu hình đi theo người dùng, khác binary ở `%LOCALAPPDATA%` của A7 D7). Không đuôi file (như Ghostty). Chủ đề riêng: thư mục `themes/` cạnh file | Người Windows quen `%USERPROFILE%\.config` phải đặt `XDG_CONFIG_HOME` |
| D4 | Đọc file Ghostty | Đọc **mọi** file tồn tại theo đúng thứ tự Ghostty: `$XDG_CONFIG_HOME/ghostty/config.ghostty` (mặc định `~/.config`), `…/ghostty/config`, rồi (macOS) `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`, `…/config`. Chỉ lấy khoá **vẽ và gõ**: `font-family`, `font-size`, `theme`, `background`, `foreground`, `palette`, `cursor-color`, `cursor-style`, `selection-background`, `macos-option-as-alt` (+ `config-file` để theo include). Mọi khoá khác của Ghostty (gồm `keybind` — tên action và mặc định của Ghostty khác ShellX, `window-padding-*`, `scrollback-limit` — đơn vị byte, `confirm-close-surface`, `working-directory`) bị **bỏ qua im lặng**: file Ghostty không viết cho ShellX nên không báo lỗi về nó, chỉ báo lỗi đọc file và lỗi giá trị của các khoá được lấy. Bật/tắt bằng `ghostty-config = true\|false` trong file ShellX, **mặc định `true`** (như cmux). Lần đầu thấy file Ghostty có khoá được lấy → toast trung tính một lần (cờ settings `config_ghostty_notice_shown`) | Người dùng Ghostty thấy font/màu đổi sau cập nhật (đúng ý cmux; tắt bằng một dòng); không theo phím Ghostty |
| D5 | Cú pháp | Mỗi dòng: bỏ khoảng trắng hai đầu; rỗng hoặc bắt đầu `#` → bỏ (chỉ chú thích **cả dòng**, `#` giữa dòng là chữ); còn lại phải có `=`: khoá = phần trước `=` đầu tiên (đã trim), giá trị = phần sau (đã trim). Khoá phân biệt hoa thường, chỉ `[a-z0-9-]`. Giá trị trong ngoặc kép `"…"` → bỏ hai ngoặc, không xử lý escape (trừ `text:` của keybind, D31). Giá trị **rỗng** → trả khoá về mặc định (khoá lặp: xoá danh sách). Dòng sau ghi đè dòng trước (khoá đơn); khoá lặp (`font-family`, `palette`, `keybind`, `command`, `snippet`, `config-file`) cộng dồn. Mã hoá UTF-8 (BOM được), UTF-16 có BOM được; byte UTF-8 sai → cả file lỗi `notUtf8` (coi như không đọc được). CRLF được. File > 256 KiB → lỗi `tooLarge`, coi như không đọc được | — |
| D6 | `config-file` | Như Ghostty: đường dẫn tương đối theo thư mục file chứa nó, `~/` mở rộng, tiền tố `?` = tuỳ chọn (thiếu → im lặng); include được đọc **sau** mọi dòng của file chứa nó (dòng sau `config-file` không ghi đè được include). Sâu tối đa 4; vòng lặp → lỗi `includeCycle`, bỏ include đó. Include của chuỗi Ghostty theo luật lấy khoá D4; include của chuỗi ShellX theo luật đầy đủ | — |
| D7 | Bảng khoá | §3.1: `font-family`, `font-size`, `theme`, `background`, `foreground`, `palette`, `cursor-color`, `cursor-style`, `cursor-style-blink`, `selection-background`, `scrollback-limit`, `window-padding-x`, `window-padding-y`, `macos-option-as-alt`, `confirm-close-surface`, `working-directory`, `keybind`, `command`, `snippet`, `ghostty-config`, `config-file`. **Mặc định = hành vi hôm nay** (cột "Mặc định" §3.1). Khoá lạ trong file ShellX → cảnh báo `unknownKey` | Thiếu khoá người dùng cần (vd. `copy-on-select`, `background-opacity`) → thêm sau, không đổi cú pháp |
| D8 | Lỗi và cấu hình hiệu lực | Mỗi vấn đề = `{file, dòng, mức (lỗi/cảnh báo/ghi chú), mã, khoá?, chi tiết?}`. **Cấu hình hiệu lực là hàm thuần của nội dung file**: dòng sai coi như không có (khoá giữ giá trị từ dòng hợp lệ trước đó hoặc mặc định), **không** giữ "giá trị tốt lần trước" theo từng khoá — cùng file luôn cho cùng kết quả. Ngoại lệ: file ShellX **không đọc được** (quyền, `notUtf8`, `tooLarge`, lỗi I/O) → giữ **nguyên** cấu hình hiệu lực trước đó và báo lỗi `unreadable`; file Ghostty không đọc được → coi như không có + cảnh báo. Giá trị ngoài khoảng → kẹp + cảnh báo `outOfRange` | Người sửa dở (lưu giữa chừng) thấy một khoá nhảy về mặc định trong lúc gõ |
| D9 | Nạp lại | (a) **Tự động:** mỗi 1 s so "dấu" `(tồn tại, cỡ, mtime)` của mọi file đã đọc lần trước (file ShellX, mọi file Ghostty ứng viên D4, include, file chủ đề); khác → chờ 250 ms yên rồi nạp. Thăm dò thay vì `File.watch`: chạy được khi thư mục chưa tồn tại, khi trình sửa ghi bằng đổi tên, trên ổ mạng, giống nhau trên macOS/Windows, test được bằng đồng hồ giả. (b) **Bằng tay:** ⌘⇧, / Ctrl+Shift+, (`reload_config`), bảng lệnh, khay, `shellx config reload`. Áp **ngay** (khung hình kế) cho mọi khoá, **trừ** `scrollback-limit` (chỉ pane mở sau đó, D17). Nạp tay thành công → toast trung tính "Đã tải lại cấu hình"; nạp tự động không vấn đề → im lặng | Sửa rồi lưu chờ tối đa ~1,25 s mới thấy; 4–8 lần `stat`/giây (không đáng kể) |
| D10 | Không bao giờ hỏng | Nạp, phân tích, dựng chủ đề, dò font, dựng bảng phím đều trong `try/catch`; lỗi bất ngờ → vấn đề `internal` + giữ cấu hình hiệu lực trước. Không `throw` nào từ cấu hình tới vòng sự kiện UI. Tải lần đầu lúc khởi động có hạn 1 s: quá hạn → chạy với mặc định, áp khi xong | — |
| D11 | Font | `font-family` lặp được: dòng đầu = font chính, các dòng sau = font dự phòng (theo thứ tự); dòng `font-family` đầu tiên của file ShellX **thay** danh sách lấy từ Ghostty (không nối thêm), sau cùng luôn có JetBrains Mono đóng gói (A1 D16) rồi danh sách dự phòng của xterm. Font chưa cài: Flutter tự rơi về dự phòng → ShellX **dò** (so bề rộng hai chuỗi mẫu với một họ chắc chắn không tồn tại) và cảnh báo `fontNotFound`; font không đơn cách (bề rộng `iiiiiiiiii` ≠ `MMMMMMMMMM`) → cảnh báo `fontNotMonospace` (vẫn dùng). Dò chạy ở UI, lỗi dò → không cảnh báo | Dò sai (hiếm: hai font cùng số đo) → thiếu một cảnh báo |
| D12 | Cỡ chữ | `font-size` 9–28 (số thập phân được; ngoài khoảng → kẹp + cảnh báo; giữ khoảng A1 UI §1.3 vì cỡ tối thiểu pane A3 D4 tính theo nó). **Có** `font-size` → cỡ lúc mở và mỗi khi **giá trị trong file đổi** = giá trị đó; ⌘+/−/0 chỉnh trong phiên, ⌘0 về `font-size`, **không lưu** vào settings. **Không có** → hành vi hôm nay (lưu `terminal_font_size`, mặc định 13). `increase_font_size:N` / `decrease_font_size:N` (N 0,5–8) | Người đã ⌘+ rồi sửa file khác (không đụng `font-size`) giữ cỡ ⌘+; sửa `font-size` thì mất cỡ ⌘+ (giống Ghostty) |
| D13 | Chủ đề | `theme = Tên` \| đường dẫn tuyệt đối (`~/` được) \| `light:A,dark:B` (ShellX luôn tối → lấy `dark`; chỉ có `light` → dùng nó + ghi chú). Tìm `Tên` theo thứ tự: `<thư mục file ShellX>/themes/`, `<XDG>/ghostty/themes/`, (macOS) `~/Library/Application Support/com.mitchellh.ghostty/themes/`, `/Applications/Ghostty.app/Contents/Resources/ghostty/themes/`. `ShellX` = bảng màu A1 (không cần file). File chủ đề là cú pháp D5, chỉ lấy khoá màu; khoá khác bỏ qua im lặng. Không tìm thấy → cảnh báo `themeNotFound`, giữ màu mặc định (và màu khai báo tường minh). **Không đóng gói** chủ đề bên thứ ba trong A9 | `theme = Dracula` trên máy không có Ghostty → cảnh báo + hướng dẫn tải về `themes/`; đóng gói bộ iTerm2-Color-Schemes là follow-up |
| D14 | Màu | Chỉ hex: `#RRGGBB`, `RRGGBB`, `#RGB`. Tên màu X11 → `badValue` ("chỉ hỗ trợ màu hex"). Thứ tự áp: mặc định A1 < chủ đề (giá trị `theme` cuối cùng) < khoá màu tường minh (giá trị cuối cùng, bất kể từ Ghostty hay ShellX). `palette = N=#hex`: N 0–15 áp; 16–255 → ghi chú `unsupportedValue` (xterm tự tính 256 màu). `selection-background` vẽ với độ mờ 40 % (xterm vẽ vùng chọn đè lên chữ). `cursor-text`, `selection-foreground` không có trong xterm 4 → bỏ qua im lặng từ Ghostty, ghi chú từ file ShellX. Ô tìm kiếm (xterm search hit) suy từ `palette` 3 và 6 như A1 | Người dùng có tên màu X11 phải đổi sang hex |
| D15 | Vùng terminal theo chủ đề; tương phản | Nền vùng terminal (gồm lề D18 và ô quanh pane) = `background` của chủ đề. Sidebar, đầu pane A3, thanh tiêu đề macOS 28 px, toast, dải driver, vòng sáng A4, viền focus giữ token ShellX. **Viền focus pane** (A3 D16) = `accent` nếu tương phản với nền chủ đề ≥ 3:1, không thì `bgTerminal` `#0B1215` (WCAG 1.4.11). `foreground`/`background` < 4,5:1 → cảnh báo `lowContrast` (vẫn áp: lựa chọn của người dùng) | Chủ đề sáng: vùng terminal sáng cạnh sidebar tối (giống cmux với chủ đề sáng) |
| D16 | Con trỏ | `cursor-style = block\|bar\|underline\|block_hollow` (`block_hollow` → khối + ghi chú: xterm 4 vẽ khối rỗng chỉ khi mất focus); mặc định `block`. `cursor-color` (mặc định = `foreground`). `cursor-style-blink` → ghi chú `unsupportedValue` (xterm 4 không nhấp nháy), từ Ghostty không đọc | Không có con trỏ nhấp nháy |
| D17 | Scrollback | `scrollback-limit` = **số dòng** (khác Ghostty: byte — vì vậy không đọc từ Ghostty), 1 000–100 000, mặc định 10 000 (A1). Chỉ áp cho pane **mở sau** lần nạp (bộ đệm xterm cố định cỡ lúc tạo); pane cũ giữ cỡ cũ. Khôi phục A5a dùng giá trị hiện tại | Đổi scrollback phải mở pane mới mới thấy |
| D18 | Lề | `window-padding-x = N` hoặc `L,R`; `window-padding-y = N` hoặc `T,B`; 0–64 px logic; mặc định 10 / 6 (A1). Áp ngay, mọi pane đo lại lưới; cỡ tối thiểu pane A3 D4 dùng lề hiện tại | — |
| D19 | Option as Alt (macOS) | `macos-option-as-alt = false\|true\|left\|right`, mặc định `false` (hôm nay: Option gõ ký tự đặc biệt, Option+←/→ nhảy từ ở shell — giữ ở mọi chế độ). `true`/`left`/`right` → Option (bên đó) + phím chữ/số/dấu gửi `ESC` + ký tự gốc (Shift → chữ hoa), không qua IME. Áp ngay (bộ xử lý phím đọc giá trị lúc gõ). Trên Windows khoá này không có tác dụng (Alt đã là Meta) → ghi chú `notOnThisPlatform` nếu đặt trong file ShellX | Bàn phím không phải US: ký tự gốc theo phím logic của layout (giống iTerm2 "Esc+") |
| D20 | Hỏi khi đóng | `confirm-close-surface = true\|false\|always` (tên Ghostty). `true` (mặc định) = A1 D15 / A3 D28 hôm nay; `false` = không bao giờ hỏi; `always` = luôn hỏi (chữ mới: "Shell trong tab này sẽ đóng."). Áp cho đóng tab và đóng pane từ UI (⌘W, ×, menu, chuột giữa). `shellx close` của CLI **giữ** luật A7 D18 (đang chạy lệnh và không `--force` → `running_command`; CLI không bao giờ mở hộp thoại). **Không** áp cho Thoát (A1/A5b giữ nguyên) | Người đặt `false` vẫn thấy hộp hỏi khi Thoát và vẫn cần `--force` ở CLI |
| D21 | Thư mục tab mới | `working-directory = home\|inherit\|<đường dẫn tuyệt đối>` (`~/` được), mặc định `home` (A3 D17: ⌘T ở home). `inherit` = cwd của pane đang focus (A2) nếu biết, không thì home. Áp cho ⌘T, `+`, "Mở tab mới" ở trạng thái trống, `new-tab` của CLI khi không `--cwd`. Chia pane giữ A3 P4. Kiểm tra thư mục theo A3 D17 (sai → home, không lỗi); đường dẫn tương đối → `badValue` | — |
| D22 | Cú pháp `keybind` | `keybind = <trigger>=<action>` của Ghostty. Trigger: các bộ phận nối bằng `+`: bổ trợ `shift`, `ctrl`/`control`, `alt`/`opt`/`option`, `super`/`cmd`/`command`; đúng **một** phím: chữ cái, chữ số, ký tự dấu (`=` `-` `[` `]` `;` `'` `,` `.` `/` `\` `` ` ``), hoặc tên (§3.2: `enter`/`return`, `tab`, `escape`, `space`, `backspace`, `delete`, `insert`, `home`, `end`, `page_up`, `page_down`, `arrow_left`…/`left`…, `f1`–`f24`, `equal`, `minus`, `plus`, `comma`, `period`, `slash`, `backslash`, `semicolon`, `quote`, `backquote`/`grave`, `bracket_left`, `bracket_right`, `kp_0`–`kp_9`, `kp_enter`, `kp_add`, `kp_subtract`, `digit_0`–`digit_9`). Chuỗi: `a>b` tối đa **2** bước (D28); dài hơn → lỗi `sequenceTooLong`. Tách trigger/action tại `=` đầu tiên **không** đứng ngay sau `+` hoặc đầu chuỗi (để `super+==…` hiểu là phím `=`). Tiền tố Ghostty `all:`, `unconsumed:`, `performable:` → ghi chú `unsupportedPrefix`, binding vẫn áp như không tiền tố; `global:` → lỗi (ShellX không bắt phím toàn hệ thống), bỏ dòng. Giá trị `keybind = clear` → bỏ **mọi** mặc định (trừ D25 cố định). Action `unbind` → bỏ trigger đó; `ignore` → nuốt phím (không tới shell) | Không có phím bắt toàn hệ thống (Quake mode) |
| D23 | Tên action | Dùng **tên Ghostty** khi Ghostty có (`new_tab`, `close_surface`, `close_tab`, `new_split:right\|down`, `goto_split:left\|right\|up\|down` (+ `top`/`bottom`), `resize_split:<hướng>[,N]` (N bỏ qua, bước A3 D12 5 % + ghi chú), `toggle_split_zoom`, `equalize_splits`, `goto_tab:1–9`, `next_tab`, `previous_tab`, `copy_to_clipboard`, `paste_from_clipboard`, `select_all`, `increase_font_size:N`, `decrease_font_size:N`, `reset_font_size`, `reload_config`, `open_config`, `toggle_command_palette`, `text:…`, `csi:…`, `esc:…`, `ignore`, `unbind`); tên **ShellX** cho cái Ghostty không có (`new_workspace`, `toggle_notifications`, `jump_to_unread`, `open_browser`, `browser_focus_address`, `browser_reload`, `browser_back`, `browser_forward`, `browser_stop`, `next_region`, `previous_region`, `show_shortcuts`, `show_config_problems`, `run_command:<tên>`). Bảng đầy đủ §3.3. `new_split:left\|up\|auto`, `goto_split:previous\|next`, `close_tab:other\|right` → lỗi `badActionParam` | Người dán nguyên khối keybind Ghostty thấy vài dòng lỗi (được chỉ rõ) |
| D24 | Bảng mặc định | Bảng mặc định = **đúng** bảng A1–A6 hôm nay theo từng nền tảng (kể cả bốn phím ⌘+ / ⌘⇧= / `add` / `numpadAdd`, ⌘⇧↩ trên cả `enter` và `numpadEnter`, cờ không lặp phím của A2 C5/A3 D20/A4 N5). `desktopShortcuts`/`terminalViewShortcuts`/`browserPaneShortcuts` dựng từ dữ liệu binding. Chứng minh bằng **fixture vàng** sinh từ mã **trước** khi đổi (plan Task 4). Mặc định mới của A9: `reload_config` ⌘⇧, / Ctrl+Shift+,; `open_config` ⌘, / Ctrl+,; `toggle_command_palette` ⌘⇧P / Ctrl+Shift+P; `close_tab`, `show_shortcuts`, `show_config_problems` **không gán** (vào qua bảng lệnh) | Mỗi phím mới lấy đi một tổ hợp khỏi shell: ⌘, ⌘⇧, ⌘⇧P trên macOS không tới shell (xterm không gửi gì cho ⌘); Ctrl+, / Ctrl+Shift+, / Ctrl+Shift+P trên Windows: xterm cũng không mã hoá Ctrl+dấu phẩy hay Ctrl+Shift+chữ → không mất gì |
| D25 | Luật trigger | **Lỗi (bỏ dòng):** (a) phím hệ điều hành giữ — macOS ⌘Q, ⌘H, ⌥⌘H, ⌘M, ⌘Tab, ⌘⇧Tab, ⌘Space, ⌃Space (đổi bộ gõ — quan trọng với người gõ tiếng Việt), ⌃⌘Space, ⌘`, ⌘⇧`, ⌥⌘Esc, ⌃⌘Q, ⌃⌘F, ⌘⇧3/4/5; Windows Alt+F4, Alt+Tab, Alt+Shift+Tab, Alt+Esc, Ctrl+Esc, Ctrl+Shift+Esc, Alt+Space, Ctrl+Alt+Delete, mọi tổ hợp có `super` (phím Win); (b) **F6 và Shift+F6 trơn** (vòng vùng A1 §3.6, WCAG 2.1.1/2.1.2 — luôn thoát được terminal); (c) phím **trơn hoặc chỉ Shift** (không ctrl/alt/super) trừ F1–F24 và — riêng `browser_stop` — Esc: phím đó dùng để gõ. **Ghi chú (vẫn áp):** Ctrl+chữ không Shift/Alt/Super trên Windows hoặc ⌃+chữ trên macOS (`shellKeyTrigger`: "phím này của shell, vd. Ctrl+C ngắt lệnh"); macOS ⌥+phím in được khi `macos-option-as-alt = false` (`optionKeyTrigger`: mất ký tự Option gõ ra); Windows Ctrl+Alt+phím in được (`altGrTrigger`: AltGr+phím vẫn gõ ký tự, D26); macOS ⌃+mũi tên (`missionControlTrigger`: Mission Control có thể giữ) | Người dùng nâng cao không gán được phím trơn (Ghostty cho phép) |
| D26 | AltGr (giữ A3 D20) | Windows: **mọi** phím tắt của ShellX không chạy khi **Alt phải** đang giữ (AltGr = Ctrl+Alt phải) — tổng quát hoá luật "chỉ Alt trái" của A1 (Ctrl+Alt+số) và A3 D20 cho cả binding tự định nghĩa. Phím được trả về shell như chưa gán | Không gán được phím tắt dùng AltGr (cố ý) |
| D27 | Xung đột | Cùng trigger được gán nhiều lần → **dòng sau thắng** (Ghostty), không báo; nhưng hai dòng **trong file của người dùng** gán cùng trigger cho hai action khác nhau → ghi chú `duplicate` (chỉ ra dòng trước). Một action nhiều trigger: được. Phạm vi cố định: action `browser_*` thuộc phạm vi **trình duyệt** (chỉ khi pane trình duyệt focus, A6 D15), còn lại phạm vi **cửa sổ**; cùng trigger ở hai phạm vi → không xung đột (pane trình duyệt focus: phạm vi trình duyệt thắng, như A6). Tiền tố chuỗi `a` trùng một binding một bước `a` → binding một bước bị bỏ + cảnh báo `sequencePrefixShadows` (giống tmux) | Không có biểu thức `when` như cmux |
| D28 | Chuỗi hai bước | Bấm tiền tố → nuốt phím, vào trạng thái chờ: **chỉ báo** "Ctrl+A …" (UI-A9 §5) + đọc lên lịch sự. Phím kế: khớp bước 2 → chạy action; Esc → huỷ im lặng; **cùng tiền tố lần nữa** → gửi tiền tố tới terminal (như `send-prefix` của tmux/screen) và thoát chờ; phím khác → huỷ chờ và phím đó đi tiếp **bình thường** (tới shell hay phím tắt khác). Không hết giờ (như Ghostty/tmux); đổi focus, bấm chuột, mở menu/hộp thoại → huỷ. Hoạt động khi terminal hoặc sidebar có focus; **không** trong nội dung web (A6: native chỉ chuyển phím trong danh sách) và **không** trong ô nhập chữ (đổi tên, bảng lệnh) | Người dùng kiểu tmux phải bấm vào terminal trước khi dùng chuỗi trong pane trình duyệt |
| D29 | Nhãn phím trong UI | Mọi gợi ý phím (menu terminal A3 D21, menu dòng, tooltip `+`, nút thông báo A4, nhãn trình duyệt A6) lấy **trigger đầu tiên** đang hiệu lực của action (thứ tự trong bảng mặc định, rồi thứ tự dòng); không có → **không hiện** gợi ý. Chuỗi hiện `⌃A C` / `Ctrl+A C`. Nhãn từ nền tảng, không dịch (A1 UI §5) | — |
| D30 | Pane trình duyệt (A6 D15) | Danh sách phím native chuyển về Flutter (`browserForwardedChords`) dựng từ bảng hiệu lực (phạm vi trình duyệt + cửa sổ, trừ copy/paste/chọn hết/cỡ chữ như A6) và **gửi lại** cho mọi pane trình duyệt sau mỗi lần nạp có đổi phím. Tiền tố chuỗi không chuyển (D28) | — |
| D31 | `text:` `csi:` `esc:` | Gửi thẳng vào pane terminal đang focus **như người dùng gõ** (thành driver, A1 D6), **không** qua lọc dán (file của chính người dùng, như Ghostty). `text:` theo escape chuỗi Zig: `\n` `\r` `\t` `\\` `\"` `\'` `\xHH` `\u{H…}`; `csi:X` = `ESC [ X`; `esc:X` = `ESC X`. ≤ 4 KiB sau giải mã; escape sai → `badActionParam`. Pane đã thoát hoặc pane trình duyệt focus → không làm gì | File cấu hình bị tiến trình khác của cùng người dùng sửa có thể gài phím gửi lệnh — ngang `.zshrc`, chấp nhận |
| D32 | Trình sửa phím tắt | **Có** (cmux có trong Settings). Hộp "Phím tắt" (UI-A9 §4): liệt kê mọi action theo nhóm với trigger hiện tại; "Thêm phím" → ghi tổ hợp kế tiếp (Esc huỷ; luật D25 kiểm tại chỗ; xung đột D27 hỏi "Thay thế?"); × trên một phím → bỏ; "Đặt lại" → về mặc định. Ghi vào **khối do ShellX quản lý** ở cuối file ShellX (`# >>> shellx-managed keybinds >>>` … `# <<< shellx-managed keybinds <<<`), **không bao giờ** sửa dòng khác; ghi nguyên tử (file tạm + đổi tên), giữ BOM và kiểu xuống dòng; thiếu file → tạo từ mẫu D37 + khối. Sau khi ghi → nạp lại ngay. Ghi chuỗi hai bước: không trong trình sửa (viết tay) | Khối quản lý ở cuối thắng mọi dòng trước — người sửa tay một phím đã chỉnh trong app phải xoá dòng trong khối (hộp hiện "Đặt trong file, dòng N" để biết) |
| D33 | Bảng lệnh | ⌘⇧P / Ctrl+Shift+P (`toggle_command_palette`, như cmux/VS Code/Windows Terminal). Một ô tìm + danh sách: mọi action phạm vi cửa sổ có nhãn (trừ `goto_tab`, `text`, `csi`, `esc`, `ignore`, `unbind`, `run_command` — chúng là binding; action `browser_*` thuộc trang web nên không có trong bảng lệnh), lệnh và đoạn chữ của người dùng (D35), mục cấu hình ("Mở file cấu hình", "Tải lại cấu hình", "Phím tắt…", "Xem vấn đề cấu hình" khi có). Lọc: không phân biệt hoa thường **và dấu tiếng Việt**, khớp tiền tố > đầu từ > dãy con; hoà → dùng gần đây (8 mục, trong bộ nhớ) → thứ tự gốc. Mục bị vô hiệu (vd. "Phóng to pane" khi tab một pane) **ẩn**. Enter chạy và đóng; Esc đóng, bàn phím về chỗ cũ (như bảng thông báo A4 UI §5.3) | — |
| D34 | "Skill" ở A9 nghĩa là gì | (a) **Skill cho agent**: thêm skill `shellx-config` (Markdown, nhúng trong binary) vào **đúng** bộ cài A7 D35 — `shellx skills install` cài cả `shellx` và `shellx-config` (cmux có skill "Settings"/"Customization" riêng); skill dạy agent tìm file (`shellx config path`), thêm dòng `keybind`/`command`, **không** sửa khối quản lý, chạy `shellx config check` rồi `reload`, đọc vấn đề. Không có lệnh cài thứ hai, không đường dẫn mới. (b) **Lệnh của người dùng** (`command`, `snippet`, D35) trong bảng lệnh và gán phím bằng `run_command:` — trong UI gọi là "Lệnh của bạn"/"Đoạn chữ", **không** gọi là "skill" để khỏi lẫn với skill agent. Ngoài phạm vi: bố cục workspace dựng sẵn (workspace command của cmux), file dự án `.shellx/config` (cần hỏi tin cậy) | Người tìm "skills" trong UI không thấy chữ đó (bảng lệnh có "Lệnh của bạn") |
| D35 | `command` / `snippet` | `command = <tên> = <chữ>`: tên = trước `=` đầu tiên của giá trị (trim, 1–64 ký tự, không chứa `=`), chữ = phần sau (trim; ngoặc kép → escape Zig như D31 để có `\n`). Chạy = **dán** chữ (qua `DesktopTerminal.paste`: lọc ký tự điều khiển, bracketed paste — như A7 `send`) **rồi Enter**. `snippet` cùng cú pháp, chỉ dán (người dùng sửa rồi tự Enter). Đích: pane terminal đang focus của tab đang chọn; pane trình duyệt focus → pane terminal dùng gần nhất của tab; không có / đã thoát → toast "Không có terminal để chạy lệnh này". Tên trùng → dòng sau thắng + ghi chú (thay **tại chỗ**, giữ vị trí trong file; `command` và `snippet` dùng chung một không gian tên). ≤ 200 mục; chữ ≤ 16 KiB tính theo byte UTF-8 (A7 D16). `command =` rỗng → xoá cả danh sách `command` (D5); `run_command:<tên>` trỏ tên không có → cảnh báo `unknownCommand`, bỏ binding | Không có "hỏi trước khi chạy" như `confirm` của cmux (dùng `snippet` khi cần xem lại) |
| D36 | Hiện vấn đề | Sau khi nạp (khởi động, tự động, bằng tay) mà **tập vấn đề khác lần trước** (hoặc nạp tay) và có ≥ 1 lỗi/cảnh báo → toast (UI-A9 §3): kiểu lỗi nếu có lỗi, trung tính nếu chỉ cảnh báo; chữ "Cấu hình có {n} vấn đề" + nút "Xem"; ghi chú (mức info) **không** gây toast, chỉ hiện trong bảng. "Xem" / bảng lệnh / khay → **bảng vấn đề**: từng dòng `file, dòng N`, mức, thông điệp, nút "Mở file cấu hình", "Tải lại". Hết vấn đề → bảng hiện "Cấu hình không có vấn đề" | Người bỏ qua toast chỉ thấy lại vấn đề qua bảng lệnh/khay |
| D37 | Mở file cấu hình | ⌘, / Ctrl+, (`open_config`, như Ghostty/Windows Terminal), bảng lệnh, khay. Thiếu file → tạo thư mục + file **mẫu** (mọi khoá §3.1 ở dạng chú thích với giá trị mặc định, đường dẫn file Ghostty đang đọc, ví dụ keybind/command), rồi mở bằng trình sửa chữ mặc định: macOS `/usr/bin/open -t <file>`, Windows `notepad.exe <file>` (file không đuôi → ShellExecute hỏi "mở bằng gì"). Không dùng `$EDITOR` (app GUI). Lỗi → toast `configOpenFailed` kèm đường dẫn | Người muốn VS Code phải mở tay |
| D38 | Di trú | **Không** tự ghi file khi nâng cấp. `terminal_font_size` vẫn dùng khi file không có `font-size` (D12). Các công tắc ứng dụng (thông báo, chia sẻ, CLI, trình duyệt, lưu phiên — tray A4–A7) **ở lại** settings/khay: file cấu hình là chuyện terminal + phím + lệnh. `shellx config show` cho thấy giá trị hiệu lực và nguồn | Không cấu hình được công tắc app bằng file (thêm khoá sau nếu cần) |
| D39 | CLI (A7) | Lệnh mới: `shellx config path [--ghostty]` (cục bộ trong Rust, cùng luật D3/D4, một test Dart ghim chuỗi để hai bên không lệch); `shellx config check` (`ui.config.check` — phân tích file **hiện tại** không áp), `shellx config reload` (`ui.config.reload`), `shellx config show [--defaults]` (`ui.config.show`). Kết quả `{problems:[{file,line,severity,code,key?,message}], generation}`; chữ tiếng Anh (A7 D11) `file:line: severity: message`; có lỗi → mã 1, chỉ cảnh báo → 0. Cap mới `ui.config`. Theo công tắc A7 D26 (`cli_disabled`); không dấu Agent (không nhắm tab). Không có `config set` (agent sửa file; khối quản lý dành cho trình sửa) | — |
| D40 | Riêng tư | Không bao giờ log nội dung file, giá trị, chữ của `command`/`snippet`/`text:`, đường dẫn người dùng — chỉ số dòng, mã vấn đề, `runtimeType` | — |
| D41 | Tiến trình | Chỉ tiến trình **UI** đọc và theo dõi cấu hình (daemon A5b không vẽ, không nhận phím). `scrollback-limit`, `working-directory` được UI dùng khi nó mở phiên | — |
| D42 | Hiệu năng | Nạp + phân tích + dựng bảng phím file 1 000 dòng ≤ 20 ms (macOS, debug ≤ 60 ms); áp lần nạp trong ≤ 1 khung hình sau khi xong; mỗi lần thăm dò ≤ 1 ms | — |
| D43 | Windows | `%APPDATA%\ShellX\config`; Notepad lưu UTF-8 (có hoặc không BOM) và CRLF → đọc được; khối quản lý ghi CRLF nếu file dùng CRLF. ⚠ MANUAL: Notepad, AltGr bàn phím Đức/Ba Lan, Ctrl+, / Ctrl+Shift+, | Chưa có máy Windows → "pending manual" trong ledger, không merge |
| D44 | Trợ năng | Bảng lệnh, bảng vấn đề, trình sửa phím: hộp thoại có nhãn, bẫy focus trong hộp, Esc đóng, focus trả về chỗ cũ; danh sách là listbox (mục đang chọn được đọc, số kết quả đọc lên ≤ 1 lần/500 ms); phím đã ghi đọc lên ("Đã gán ⌘⇧T cho Tab mới"); chế độ ghi luôn thoát được bằng Esc và không bao giờ ghi F6/Shift+F6/Esc/Tab trơn; toast vấn đề là live region lịch sự. Giảm chuyển động: không hoạt ảnh mới | — |
| D45 | Khay | Submenu mới **"Cấu hình"** ngay sau "Dòng lệnh" (A7 D26): "Mở file cấu hình", "Tải lại cấu hình", "Phím tắt…", và khi có lỗi/cảnh báo "⚠ {n} vấn đề cấu hình…" (mở bảng vấn đề). Có cả khi chưa đăng nhập | — |
| D46 | macOS menu ứng dụng | `MainMenu.xib` có "Preferences…" ⌘, không action. Flutter nhận phím trước menu (như ⌘C/⌘V hôm nay) nên ⌘, tới `open_config`; ⚠ MANUAL kiểm. Nếu menu nuốt ⌘, → bỏ `keyEquivalent` của mục đó (một dòng xib) | — |

**Sửa A1:** UI §1.3 cỡ chữ: có `font-size` thì ⌘+/− không lưu (D12). §3.6 / I6: phím tắt và nhãn đến từ bảng hiệu lực (D24, D29). D16 font: JetBrains Mono là mặc định và dự phòng cuối (D11). Vùng terminal lấy nền chủ đề (D15).
**Sửa A3:** D20 "chỉ Alt trái" → mọi phím tắt, mọi binding (D26). D6 "không có phím đóng cả tab" → action `close_tab` (không gán mặc định). D16 viền focus đổi màu khi nền chủ đề sáng (D15). D17 "⌘T vẫn ở home" → theo `working-directory` (D21, mặc định home).
**Sửa A4:** không (nhãn ⌘⇧I/⌘⇧U theo D29).
**Sửa A5a:** pane khôi phục dùng `scrollback-limit` hiện tại (D17).
**Sửa A6:** D15 danh sách phím chuyển dựng từ bảng hiệu lực, gửi lại sau nạp (D30); phím `browser_*` tuỳ biến được.
**Sửa A7:** D35 bộ cài cài **hai** skill (`shellx`, `shellx-config`), `skills print config`; caps thêm `ui.config`; lệnh `config` (D39); `new-tab` không `--cwd` theo `working-directory` (D21).

---

## 3. Kiến trúc

```
apps/desktop/lib/src/config/ (mới, Dart thuần trừ ghi chú)
 ├─ config_problem.dart     ConfigProblem, mã, mức, thông điệp tiếng Anh cho CLI      (D8, D36, D39)
 ├─ config_syntax.dart      decode UTF-8/16, parseConfigText, chuỗi Zig               (D5, D31)
 ├─ config_files.dart       ConfigFs, loadConfigChain (include, sâu, vòng), dấu file  (D6, D9)
 ├─ config_paths.dart       ConfigPaths cho macOS/Windows/XDG                          (D3, D4, D13)
 ├─ config_color.dart       parseConfigColor, contrastRatio                            (D14, D15)
 ├─ shellx_config.dart      ShellxConfig + buildShellxConfig (lớp Ghostty → ShellX)    (D4, D7, D12–D21, D35)
 ├─ config_theme.dart       resolveTheme → TerminalTheme, nền, màu viền focus          (D13–D15)
 ├─ keybind_trigger.dart    KeyChord: parse, nhãn, activator, từ KeyEvent              (D22, D25, D29)
 ├─ keybind_actions.dart    bảng action (tên, phạm vi, lặp phím, intent, nhãn)         (D23)
 ├─ keybindings.dart        defaultKeyBindings, resolveKeyBindings, KeyBindings        (D24–D27)
 ├─ config_template.dart    file mẫu                                                    (D37)
 ├─ config_writer.dart      khối quản lý, ghi nguyên tử                                 (D32)
 ├─ config_watcher.dart     thăm dò dấu file 1 s + yên 250 ms                           (D9)
 └─ config_controller.dart  ConfigState, shellxConfigProvider (Notifier), nạp/kiểm      (D8–D10, D36)
apps/desktop/lib/src/terminal/
 ├─ terminal_appearance.dart (mới)  provider: TerminalTheme, nền, con trỏ, lề, font, viền (D11, D15, D16, D18)
 ├─ terminal_input.dart             OptionAsAltInputHandler                             (D19)
 ├─ desktop_terminal.dart           inputHandler, sendUserText                          (D19, D31)
 ├─ terminal_style.dart             họ font + dự phòng                                   (D11)
 ├─ terminal_font_size.dart         luật D12
 ├─ terminal_tabs.dart              maxLines theo cấu hình, cwd tab mới                  (D17, D21)
 └─ user_commands.dart (mới)        chạy command/snippet/text                            (D31, D35)
apps/desktop/lib/src/ui/
 ├─ terminal/terminal_shortcuts.dart   map dựng từ KeyBindings; intent mới               (D23, D24)
 ├─ terminal/shortcut_labels.dart      nhãn từ bảng hiệu lực                              (D29)
 ├─ terminal/key_sequence.dart (mới)   KeySequenceController + chỉ báo                    (D28)
 ├─ terminal/terminal_workspace_page.dart  action mới, AltGr toàn cục, overlay            (D26, D33)
 ├─ terminal/pane_tree_view.dart, terminal_pane.dart   theme/lề/con trỏ/font
 ├─ terminal/close_tab.dart            confirm-close-surface                              (D20)
 ├─ config/command_palette.dart (mới), config_problems_panel.dart (mới), shortcuts_sheet.dart (mới)
 └─ ../tray/*                          submenu "Cấu hình"                                  (D45)
apps/desktop/lib/src/cli/ui_command_handler.dart   ui.config.*                            (D39)
term/src/api/{args,run,skills,config_path}.rs; agent-skills/shellx-config/SKILL.md         (D34, D39)
```

### 3.1 Bảng khoá

| Khoá | Giá trị | Mặc định (= hôm nay) | Từ Ghostty | Áp |
|---|---|---|---|---|
| `font-family` (lặp) | tên họ font | JetBrains Mono | có | ngay |
| `font-size` | 9–28 | không đặt (cỡ đã lưu, 13) | có | ngay (D12) |
| `theme` | tên \| đường dẫn \| `light:A,dark:B` | `ShellX` | có | ngay |
| `background`, `foreground`, `cursor-color`, `selection-background` | hex | bảng A1 | có | ngay |
| `palette` (lặp) | `N=#hex`, N 0–15 | bảng A1 | có | ngay |
| `cursor-style` | `block\|bar\|underline\|block_hollow` | `block` | có | ngay |
| `cursor-style-blink` | bool | — | không | ghi chú |
| `scrollback-limit` | 1000–100000 dòng | 10000 | **không** | pane mới |
| `window-padding-x` / `-y` | `N` \| `A,B`, 0–64 | 10,10 / 6,6 | **không** | ngay |
| `macos-option-as-alt` | `false\|true\|left\|right` | `false` | có | ngay |
| `confirm-close-surface` | `true\|false\|always` | `true` | **không** | ngay |
| `working-directory` | `home\|inherit\|đường dẫn` | `home` | **không** | tab mới |
| `keybind` (lặp) | `trigger=action` \| `clear` | bảng A1–A6 + D24 | **không** | ngay |
| `command`, `snippet` (lặp) | `tên = chữ` | không có | không | ngay |
| `ghostty-config` | bool | `true` | — | lần nạp sau |
| `config-file` (lặp) | đường dẫn, `?` tuỳ chọn | — | có (theo include) | — |

Bool: `true`/`false` (Ghostty); khác → `badValue`.

### 3.2 Mô hình phím

```dart
final class KeyChord {                      // một tổ hợp
  final LogicalKeyboardKey key; final bool control, alt, shift, meta;   // meta = super/⌘/Win
}
final class KeyAction { final String name; final String? param; }      // 'new_split' + 'down'
final class KeyBinding { final List<KeyChord> sequence; final KeyAction action; final ConfigEntry? origin; }
final class KeyBindings {                   // bảng hiệu lực của một nền tảng
  List<KeyBinding> get all;
  Map<ShortcutActivator, Intent> windowMap({required bool includePlainF6});
  Map<ShortcutActivator, Intent> browserMap();
  List<KeyBinding> get sequences;           // 2 bước (D28)
  List<KeyChord> triggersOf(KeyAction a);   // nhãn D29
}
```

`desktopShortcuts(platform, {KeyBindings? bindings})`, `terminalViewShortcuts(…)`, `browserPaneShortcuts(…)` giữ tên và hành vi cũ khi `bindings == null` (mọi test A1–A6 chạy nguyên).

### 3.3 Bảng action (rút gọn; đầy đủ ở plan Task 4)

| Action | Intent | Lặp phím | Mặc định macOS | Mặc định Windows |
|---|---|---|---|---|
| `new_tab` | NewTab | không | ⌘T | Ctrl+Shift+T |
| `close_surface` | CloseTab (pane focus hoặc tab, A3 D6) | không | ⌘W | Ctrl+Shift+W |
| `close_tab` | CloseWholeTab (mới) | không | — | — |
| `new_workspace` | NewWorkspace | không | ⌘⇧N | Ctrl+Shift+N |
| `toggle_notifications` / `jump_to_unread` | A4 | không | ⌘⇧I / ⌘⇧U | Ctrl+Shift+I / U |
| `copy_to_clipboard` / `paste_from_clipboard` / `select_all` | A1 | có | ⌘C / ⌘V / ⌘A | Ctrl+Shift+C / V / A |
| `goto_tab:N` | SelectTab | có | ⌘1–9 | Ctrl+Alt+1–9 |
| `next_tab` / `previous_tab` | A1 | có | ⌃Tab / ⌃⇧Tab | như macOS |
| `new_split:right` / `:down` | SplitPane | không | ⌘D / ⌘⇧D | Ctrl+Shift+D / Ctrl+Shift+Alt+D |
| `goto_split:<hướng>` | FocusPane | có | ⌘⌥mũi tên | Ctrl+Alt+mũi tên |
| `resize_split:<hướng>` | ResizePane | có | ⌘⌃mũi tên | Ctrl+Shift+Alt+mũi tên |
| `toggle_split_zoom` | TogglePaneZoom | không | ⌘⇧↩ (+ keypad) | Ctrl+Shift+Enter (+ keypad) |
| `equalize_splits` | EqualizePanes | không | ⌘⌃= | Ctrl+Shift+Alt+= |
| `increase_font_size:N` | FontBigger(N) | có | ⌘=, ⌘⇧=, ⌘+, ⌘ keypad+ | Ctrl+= … |
| `decrease_font_size:N` / `reset_font_size` | A1 | có | ⌘−, ⌘ keypad− / ⌘0, ⌘ keypad0 | Ctrl+… |
| `next_region` / `previous_region` | A1 §3.6 | có | ⌃F6 / ⌃⇧F6 (+ F6/⇧F6 cố định ngoài terminal, D25) | như macOS |
| `open_browser` | OpenBrowserPane (A6) | không | ⌘⇧B | Ctrl+Shift+Alt+B |
| `browser_focus_address` / `browser_reload` / `browser_back` / `browser_forward` / `browser_stop` | A6 (phạm vi trình duyệt) | có | ⌘L / ⌘R / ⌘[ / ⌘] / Esc | Ctrl+L / Ctrl+R, F5 / Alt+← / Alt+→ / Esc |
| `reload_config` / `open_config` | mới | không | ⌘⇧, / ⌘, | Ctrl+Shift+, / Ctrl+, |
| `toggle_command_palette` | mới | không | ⌘⇧P | Ctrl+Shift+P |
| `show_shortcuts` / `show_config_problems` | mới | không | — | — |
| `run_command:<tên>` | RunUserCommand | không | — | — |
| `text:` / `csi:` / `esc:` | SendText | có | — | — |
| `ignore` | IgnoreKey | có | — | — |

---

## 4. Luồng dữ liệu

```
khởi động ─► ConfigController.load() (≤ 1 s) ─► đọc chuỗi Ghostty (D4) + chuỗi ShellX (D3, D6)
            ─► buildShellxConfig ─► resolveTheme ─► resolveKeyBindings ─► ConfigState{generation+1, problems}
            ─► terminalAppearanceProvider / terminalFontSizeProvider / bảng phím workspace / browserForwardedChords
            ─► problems khác lần trước? ─► toast D36
ConfigWatcher (1 s) ─► dấu file đổi ─► 250 ms yên ─► load() ─► …
⌘⇧, ─► ReloadConfigIntent ─► load(manual: true) ─► toast "Đã tải lại" / vấn đề
shellx config reload ─► ui.config.reload ─► UiCommandHandler ─► load(manual: true) ─► {problems} ─► CLI in, mã 0/1
Phím tắt sửa trong hộp ─► ConfigWriter (khối quản lý, ghi nguyên tử) ─► load(manual: false) ─► đọc lên D44
Ctrl+A (tiền tố) ─► KeySequenceController.pending ─► chỉ báo ─► C ─► NewTabIntent qua Actions của workspace
```

---

## 5. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Không có file nào | Mặc định; không toast; bảng lệnh có "Mở file cấu hình" (tạo mẫu) |
| Thư mục `~/.config/shellx` chưa có | Thăm dò vẫn chạy (dấu "không tồn tại"); tạo file sau đó → nạp trong ≤ 1,25 s |
| Lưu giữa chừng (file cụt) | Các dòng đủ vẫn áp; dòng cụt → `syntax`; lưu xong → nạp lại, hết vấn đề |
| File ShellX bị khoá/không có quyền đọc | Giữ cấu hình trước + lỗi `unreadable` |
| File là UTF-16 không BOM / byte sai | `notUtf8`, giữ cấu hình trước |
| `config-file` trỏ chính nó | `includeCycle`, bỏ |
| `theme` trỏ file có khoá lạ | Khoá lạ bỏ qua im lặng (D13) |
| Font không cài | `fontNotFound`; chữ vẽ bằng font dự phòng (JetBrains Mono) |
| `keybind = super+d=new_split:left` | `badActionParam`, bỏ dòng; ⌘D vẫn là mặc định |
| `keybind = super+q=…` (macOS) | `reservedTrigger`, bỏ |
| `keybind = a=new_tab` | `plainKeyTrigger`, bỏ |
| `keybind = clear` rồi không gán gì | Chỉ còn F6/⇧F6 và phím trong hộp thoại; bảng lệnh không có phím → vào qua khay "Cấu hình" hoặc `shellx` (ghi chú ở mẫu) |
| `run_command:Deploy` khi không có `command = Deploy …` | `unknownCommand`, bỏ binding |
| Hai pane trình duyệt mở lúc nạp | Cả hai nhận danh sách phím mới (D30) |
| Đang ở chế độ chờ chuỗi khi nạp lại | Huỷ chờ |
| Đang ghi phím trong hộp khi file đổi từ ngoài | Hộp làm mới danh sách; hàng đang ghi giữ chế độ ghi |
| Ghi khối quản lý khi file đổi giữa đọc và ghi | Đọc lại ngay trước khi ghi; đổi tên nguyên tử; nếu đổi tên lỗi → toast `configWriteFailed`, file không bị cắt |
| CLI `config reload` khi UI đã thoát (sau A5b) | `no_ui` (A7 D34) |
| Lỗi bất ngờ khi nạp | `internal`, giữ cấu hình trước (D10) |

---

## 6. Kiểm thử

- **Dart thuần (`flutter test test/config/`):** `config_syntax_test` (chú thích, ngoặc kép, rỗng, CRLF, BOM, UTF-16, UTF-8 sai, `#` giữa dòng, khoá sai ký tự, escape Zig), `config_files_test` (include tương đối/tuyệt đối/`?`/thiếu/vòng/sâu 5, thứ tự "include sau file", 256 KiB), `config_paths_test` (XDG, macOS, Windows; chuỗi ghim cho Rust), `shellx_config_test` (mỗi khoá: hợp lệ, sai, ngoài khoảng, rỗng → mặc định; lớp Ghostty chỉ lấy khoá D4 và im lặng phần còn lại; ShellX ghi đè Ghostty; `ghostty-config = false`; command/snippet), `config_theme_test` (tìm theo thứ tự, `light:/dark:`, đường dẫn, màu tường minh thắng chủ đề, palette 16+, độ mờ vùng chọn, viền focus theo tương phản, `lowContrast`), `keybind_trigger_test` (mọi tên phím, bổ trợ, chuỗi, nhãn macOS/Windows, sinh lại chuỗi cấu hình), `keybindings_test` (**fixture vàng** mặc định macOS/Windows; unbind; clear; ignore; dòng sau thắng; `duplicateTrigger`; luật D25 từng nhóm; tiền tố chuỗi che binding; `run_command` không có), `config_writer_test` (thêm/bỏ/đặt lại, giữ byte ngoài khối, CRLF, BOM, file thiếu → mẫu), `config_controller_test` (`fake_async`: thăm dò, yên 250 ms, file không đọc được giữ cấu hình trước, `internal` khi bộ phân tích ném, toast chỉ khi tập vấn đề đổi).
- **Widget:** `terminal_appearance_test` (font/cỡ/màu/con trỏ/lề vào `TerminalView`; nền vùng terminal; viền focus), `terminal_font_size_config_test` (D12), `option_as_alt_test` (D19), `confirm_close_config_test` (D20), `config_behaviour_test` (D17, D21, D31, D35), `font_probe_test` (D11), `palette_match_test` (D33), `config_template_test`/`config_opener_test` (D37), `config_shortcuts_test` (phím tuỳ biến chạy, unbind tới shell, nhãn menu đổi, AltGr toàn cục, `text:`), `key_sequence_test` (D28), `command_palette_test` (lọc không dấu, Enter/Esc/focus, command/snippet), `config_problems_ui_test` (toast, bảng, nút), `shortcuts_sheet_test` (ghi, xung đột, bỏ, đặt lại, Esc, F6 bị từ chối), `tray_config_menu_test`.
- **CLI:** `ui_command_handler_config_test` (`ui.config.*`, `cli_disabled`); Rust `api::args` (lệnh `config`), `api::run` (in vấn đề, mã thoát), `api::config_path` (khớp chuỗi ghim), `api::skills` (cài hai skill, `print config`).
- **Thử tay (HANDOFF §18, ⚠ MANUAL):** macOS và Windows thật — tiêu chí 1–10; Ghostty đã cài (chủ đề trong app bundle); font chưa cài; Notepad (CRLF, BOM); AltGr Đức/Ba Lan; ⌘, qua menu xib; VoiceOver/Narrator với bảng lệnh và trình sửa phím; Option-as-Alt với `vim`/`emacs -nw` (M-x); chủ đề sáng (viền focus); Claude Code dùng skill `shellx-config` thêm một keybind.

---

## 7. Ngoài phạm vi A9

Cửa sổ Cài đặt đầy đủ (công tắc app vẫn ở khay, D38); biểu thức `when` của cmux; phím toàn hệ thống (`global:`); chuỗi > 2 bước; bố cục workspace dựng sẵn và lệnh tạo workspace (cmux workspace commands); file cấu hình theo dự án `.shellx/config` (cần hỏi tin cậy); đóng gói chủ đề bên thứ ba; tên màu X11; `copy-on-select`, `background-opacity`, `font-feature`, `adjust-cell-height`, ligature; con trỏ nhấp nháy; `config set` trong CLI; cấu hình cho app mobile; đồng bộ cấu hình giữa máy; nhập `cmux.json`.
