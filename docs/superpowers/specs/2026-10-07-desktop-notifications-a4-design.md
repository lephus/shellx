# A4 — Thông báo kiểu cmux trên desktop — Đặc tả thiết kế

- **Ngày:** 2026-10-07
- **Trạng thái:** Người dùng giao toàn quyền cho controller (như A1, A2). Quyết định N1–N9 do controller chốt (ràng buộc); D1–D27 do người viết spec chốt trong phạm vi N1–N9. Tất cả ghi ở bảng §2 kèm cái giá nếu sai.
- **Lộ trình:** A1 (cửa sổ terminal) → A2 (sidebar giàu thông tin) → **A4 (tài liệu này)** → A3 split pane → A5 khôi phục session + daemon → A6 trình duyệt nhúng → A7 CLI/socket → A8 SSH/tmux → A9 skills, phím tắt tuỳ biến, file cấu hình.
- **Tài liệu đi kèm:** UI addendum `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a4.md` (đo đạc, token, wireframe, chuỗi; ràng buộc cho phần nhìn); plan `docs/superpowers/plans/2026-10-07-desktop-notifications-a4.md`.
- **Giữ nguyên:** spec A1 (D1–D16), spec A2 (C1–C8, D1–D19), spec thông báo đẩy `2026-10-05-push-notifications-design.md` (N1–N12) vẫn có hiệu lực. Tài liệu này chỉ **thêm** và ghi rõ chỗ nào sửa.
- **Ký hiệu:** "push N6" = quyết định N6 của spec thông báo đẩy; "N1" không tiền tố = quyết định của tài liệu này.

---

## 1. Mục tiêu

Khi một chương trình trong một tab cần người dùng (Claude Code chờ trả lời, build xong, test hỏng, lệnh chạy lâu kết thúc, chuông), người dùng **thấy ngay tab nào** mà không phải lật từng tab — như cmux: dòng tab có **badge số chưa đọc** và **dòng thông báo cuối**, terminal có **vòng sáng** khi tab đang xem có thông báo chưa đọc, có **bảng thông báo** (⌘⇧I) và **nhảy tới thông báo chưa đọc tiếp theo** (⌘⇧U), có **thông báo hệ thống** khi người dùng đang ở app khác, và **badge trên Dock/taskbar**.

### Tiêu chí thành công (đo được)

1. **OSC 9:** trong tab B (không chọn), `printf '\e]9;Build xong\a'` → trong ≤ 200 ms dòng tab B hiện badge `1` và dòng thông báo "Build xong"; Dock (macOS, khi icon Dock hiện) hiện `1`.
2. **OSC 777 / `shellx notify`:** `printf '\e]777;notify;CI;Đã xanh\a'` → dòng thông báo "CI: Đã xanh"; `shellx notify "xong"` → "xong".
3. **OSC 99 (kitty):** `printf '\e]99;;Xin chào\e\\'` → "Xin chào"; `printf '\e]99;i=1:d=0;Tiêu đề\e\\'; printf '\e]99;i=1:p=body;Nội dung\e\\'` → **một** thông báo "Tiêu đề: Nội dung"; `e=1` (base64) giải mã đúng tiếng Việt; khoá lạ (`u=2`, `o=unfocused`, `a=focus`) bị bỏ qua, thông báo vẫn hiện. Claude Code với `preferredNotifChannel: kitty` hoặc `iterm2` hiện thông báo trên tab của nó.
4. **Chuông (BEL):** `printf '\a'` trong tab không chọn → badge + dòng "Chuông"; 100 BEL liên tiếp → tối đa **một** thông báo chuông mỗi 5 giây mỗi tab. BEL kết thúc một OSC **không** tính là chuông.
5. **Lệnh chạy lâu:** với ngưỡng 10 s (cài đặt sẵn của push N6), `sleep 11; false` trong tab không chọn → dòng "✗ sleep 11; false · mã 1 · 11 giây" (cùng câu chữ với push). Ngưỡng "Tắt" → không có thông báo lệnh trên desktop.
6. **Đọc:** chọn tab B khi cửa sổ đang được focus → sau **1 giây** ở lại, badge, dòng thông báo và vòng sáng biến mất; chọn rồi rời đi trước 1 giây → vẫn chưa đọc. Menu dòng "Đánh dấu đã đọc", "Đánh dấu tất cả đã đọc" hoạt động.
7. **Vòng sáng:** cửa sổ không focus, tab đang chọn nhận thông báo → vòng `accent` 2 px quanh vùng terminal; focus lại cửa sổ → 1 s sau vòng tắt. Giảm chuyển động → vòng tĩnh, hiện/tắt tức thì. Vòng **không** đổi cỡ terminal (không resize PTY, không đổi driver).
8. **Workspace thu gọn** chứa tab chưa đọc → tiêu đề nhóm có chấm `accent` tổng hợp.
9. **Bảng thông báo:** ⌘⇧I / Ctrl+Shift+I mở bảng 50 thông báo gần nhất (tab, workspace, nội dung, thời gian tương đối), ↑/↓/Home/End, Enter nhảy tới tab (chọn tab, mở rộng workspace, focus terminal), Esc đóng. ⌘⇧U / Ctrl+Shift+U nhảy tới tab chưa đọc tiếp theo theo thứ tự sidebar.
10. **Thông báo hệ thống:** cửa sổ ở sau app khác, `printf '\e]9;xong\a'` → một thông báo macOS (Notification Center) / toast Windows, tiêu đề = tên tab, nội dung "xong". Bấm vào → cửa sổ ShellX lên trước, đúng tab được chọn, gõ được ngay. `for i in $(seq 20); do printf '\e]9;%s\a' $i; done` → tối đa 2 thông báo hệ thống cho tab đó trong 3 giây đầu (một ngay, một gộp "19 thông báo mới · 20"), không bao giờ quá 6/phút/tab.
11. **Cài đặt:** tray → "Thông báo" → "Thông báo trên máy tính" (mặc định bật) và "Chỉ khi cửa sổ không ở phía trước" (mặc định bật) có hiệu lực ngay, còn sau khi khởi động lại; dùng được cả khi **chưa đăng nhập**.
12. **Điện thoại không đổi (N8):** cùng một phiên, OSC 9/777 và lệnh chạy lâu gửi push **đúng như trước** (số lần gọi `NotificationSender.send` không đổi); OSC 99 và BEL **không** gửi push. Test so sánh.
13. **Riêng tư (N9):** không log nào chứa nội dung thông báo, tiêu đề chương trình hay dòng lệnh; danh sách thông báo chỉ ở bộ nhớ, không ghi settings/đĩa.
14. **Không hồi quy A1/A2:** mọi test A1/A2 vẫn xanh (trừ fake phải bổ sung thành viên interface mới); khi không có thông báo nào, sidebar và terminal trông **giống hệt A2**.

---

## 2. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| N1 | Nguồn (controller) | OSC 9 (chữ), OSC 777;notify;title;body, OSC 99 (kitty, cơ bản: title/body, cờ `d=`, bỏ qua khoá không hỗ trợ), BEL (chú ý không chữ, giới hạn tần suất), lệnh xong vượt ngưỡng (dùng lại cài đặt ngưỡng push). Cùng đường parser với push; không cần đăng nhập | — |
| N2 | Trạng thái chú ý theo tab (controller: chọn chỗ) | **Chọn: desktop giữ** (`TabAttention` trong `apps/desktop`), agent chỉ **phát sự kiện** (`LocalSessions.notices`). Lý do ở D4 | Nếu sau này điện thoại cần số chưa đọc chung với desktop thì chuyển bộ đếm vào agent/daemon (A5); luồng sự kiện giữ nguyên |
| N3 | UI (controller) | Badge số + dòng thông báo cuối (một dòng, phụ) tới khi đọc; vòng sáng quanh terminal khi tab đang chọn có chưa đọc (tĩnh khi giảm chuyển động); chấm tổng hợp trên tiêu đề workspace thu gọn | — |
| N4 | Đọc (controller) | Chọn tab khi cửa sổ focus, ở lại 1 s → đọc; "Đánh dấu đã đọc" trong menu dòng; "Đánh dấu tất cả đã đọc" | — |
| N5 | Bảng thông báo (controller) | ⌘⇧I / Ctrl+Shift+I: popover 50 thông báo gần nhất mọi tab, điều khiển bằng bàn phím; Enter nhảy tới tab; ⌘⇧U / Ctrl+Shift+U nhảy tới chưa đọc tiếp theo | — |
| N6 | Thông báo hệ thống (controller) | Khi cửa sổ không focus HOẶC tab báo không được chọn; tiêu đề tab + nội dung; bấm → cửa sổ lên trước, nhảy tới tab. Cài đặt "Thông báo trên máy tính" (bật) và "Chỉ khi cửa sổ không ở phía trước" (bật). ≤ 6/phút/tab; gộp chùm | — |
| N7 | Badge Dock/taskbar (controller) | macOS `dockTile.badgeLabel` = tổng chưa đọc; Windows: overlay icon hoặc nháy — chọn ở D19 | — |
| N8 | Push điện thoại (controller) | Giữ nguyên; A4 không gửi trùng, không đổi hành vi push | — |
| N9 | Riêng tư (controller) | Nội dung thông báo không bao giờ ghi log; chỉ ở máy, trừ đường push sẵn có | — |
| D1 | OSC 99 và BEL chỉ cho desktop | Parser phát hai sự kiện **mới** `KittyNotifyRequested` và `BellRung`; `SessionNotifier` (push) chỉ xử lý `NotifyRequested` như cũ và **bỏ qua** hai sự kiện mới; `CommandTracker` bỏ qua chúng. Hệ quả: push không đổi (N8, tiêu chí 12) | Người dùng muốn nhận OSC 99/chuông trên điện thoại phải chờ một quyết định push riêng |
| D2 | Phạm vi OSC 99 | `ESC ] 99 ; <metadata> ; <payload> ST/BEL`. Metadata là các cặp `k=v` nối bằng `:`. Hỗ trợ: `i` (id, mặc định rỗng), `d` (`0` = còn mảnh sau, mặc định `1`), `p` (`title` mặc định, `body`), `e` (`1` = payload base64). `p` khác (`icon`, `buttons`, `close`, `alive`, `?`) → **bỏ qua mảnh đó** (không trả lời truy vấn `?`). Khoá khác (`a`, `o`, `u`, `c`, `f`, `t`, `s`, `w`, `n`…) bỏ qua. Mảnh cùng `i` được nối tới khi `d=1`. Chỉ có tiêu đề → nội dung = tiêu đề, tiêu đề chương trình = rỗng. Giới hạn: ≤ 4 bản nháp đang ghép (thêm cái thứ 5 thì bỏ cái cũ nhất), mỗi bản ≤ 4 KiB; base64 hỏng hoặc UTF-8 hỏng → bỏ cả mảnh; tiêu đề/nội dung cắt 200 ký tự như OSC 9/777 | Chương trình dựa vào `o=unfocused`/`a=focus`/nút bấm chỉ được hành vi mặc định của ShellX |
| D3 | Nhận ra BEL | Chỉ byte `0x07` ở **trạng thái nền** của parser (không nằm trong OSC/ESC). Agent giới hạn: một `bell` mỗi **5 giây** mỗi phiên (BEL thêm trong 5 s bị bỏ, không đếm) | Chuông trong chuỗi DCS lạ (hiếm) có thể bị tính; chuông thứ hai trong 5 s không làm tăng badge |
| D4 | Seam cho N2 | Agent: `SessionNotice {sessionId, kind (message/command/bell), at, title?, body?, command?}` qua `Stream<SessionNotice> LocalSessions.notices` (broadcast, bất đồng bộ). Desktop: `TabAttention` (Riverpod) giữ chưa đọc theo id tab, lịch sử 50, quy tắc đọc. **`SessionSummary` không đổi.** Lý do: (a) "đã đọc" phụ thuộc tab đang chọn, focus cửa sổ và 1 s dừng — chỉ desktop biết; đưa vào agent cần thêm API "đánh dấu đọc" đi ngược qua `LocalSessions` và sau A5 qua socket daemon; (b) điện thoại không đổi trong A4 nên không cần trạng thái chung; (c) `SessionSummary` thay đổi làm `changes` bắn và cả danh sách tab dựng lại cho mỗi thông báo, còn luồng sự kiện chỉ chạm `TabAttention` | Xem N2 |
| D5 | Lệnh chạy lâu trên desktop | `SessionManager` nhận `commandNoticeThreshold` (desktop truyền đúng hàm ngưỡng của push, đọc settings mỗi lần lệnh xong). `CommandTracker` sẵn có của mỗi phiên (đang dùng cho `runningCommand`) dùng ngưỡng này và đồng hồ của manager. Câu chữ: `NotificationText(<ngôn ngữ app>).commandBody(...)` — **cùng câu với push** | Đổi ngưỡng ảnh hưởng cả hai nơi (đúng ý N1) |
| D6 | Chống lũ ở agent | Mỗi phiên tối đa **30** thông báo `message`/`command` mỗi 60 giây; vượt thì bỏ và đếm (log chỉ số đếm). Riêng `bell` theo D3 | Chương trình nói nhiều mất các thông báo sau trong tối đa 1 phút |
| D7 | Thông báo của tab đang xem | Thông báo tới khi tab **đang chọn** và cửa sổ **hiện + focus** → coi như đã thấy: vào lịch sử với cờ đã đọc, không badge, không vòng, không thông báo hệ thống. **BEL** trong trường hợp này bị bỏ hẳn (chuông khi gõ là phản hồi bàn phím) | Người dùng đang nhìn chỗ khác trên màn hình vẫn không có tín hiệu |
| D8 | Số trên badge | Số thông báo kể từ lần đọc trước (cả chuông). Hiện `1`…`99`, trên 99 hiện `99+`. Dock dùng cùng quy tắc trên **tổng** | — |
| D9 | Dòng thông báo | Chữ của thông báo **cuối cùng** chưa đọc: message có tiêu đề chương trình → `"<tiêu đề>: <nội dung>"`, không có → nội dung; command → câu push; bell → "Chuông"/"Bell". Ký tự điều khiển/xuống dòng → một khoảng trắng. Một dòng, cắt cuối. Nằm **ngay dưới dòng tiêu đề, trên dòng ngữ cảnh A2**. Dòng cao lên (sửa A2 D12: 46 → 46/62, công thức ở UI addendum) | Sidebar dịch dòng khi thông báo tới/đọc (chỉ sidebar, không đổi cỡ terminal) |
| D10 | Đồng hồ đọc 1 s | Bắt đầu khi đồng thời: tab có chưa đọc **và** đang chọn **và** cửa sổ hiện **và** focus. Bất kỳ điều kiện nào đổi → huỷ, bắt đầu lại từ 0. Hộp thoại/menu/bảng thông báo trên cửa sổ vẫn tính là focus. Thông báo mới tới trong lúc đếm (với tab không thấy) không đặt lại đồng hồ | — |
| D11 | Lịch sử | Tối đa **50** mục, mới nhất trước, chỉ trong bộ nhớ (mất khi thoát app — phiên cũng mất tới A5). Mục của tab đã đóng **giữ lại**, hiện "Tab đã đóng", Enter không nhảy. Chuông liên tiếp của cùng tab gộp thành một mục "Chuông ×N". Đánh dấu tab đã đọc → mọi mục của tab đó đã đọc | Mở lại app mất lịch sử |
| D12 | Vị trí bảng | Popover neo dưới dải đầu sidebar (x 8, y = đáy dải đầu + 4), rộng 360, cao tối đa `min(480, cao cửa sổ − 64)`; đè lên sidebar và một phần terminal, **không** đổi bố cục. Mở bằng ⌘⇧I hoặc nút chuông mới ở dải đầu sidebar (trái nút `+`). Bấm ra ngoài / Esc / ⌘⇧I lần nữa → đóng, bàn phím về chỗ cũ | Che một phần terminal khi mở (chấp nhận: bảng tạm thời) |
| D13 | Chưa đọc tiếp theo | Thứ tự = thứ tự sidebar (`orderedTabIds`, **gồm** tab trong nhóm thu gọn), bắt đầu **sau** tab đang chọn, vòng lại. Tab ở nhóm thu gọn → nhóm tự mở rộng. Không còn → không đổi tab, thông báo cho trình đọc màn hình "Không còn thông báo chưa đọc" và toast trung tính | — |
| D14 | Khi nào gửi thông báo hệ thống | `bật` **và** thông báo không thuộc D7 **và** ( cửa sổ không focus hoặc ẩn **hoặc** (`Chỉ khi …` tắt **và** tab không được chọn) ). **Chuông** chỉ gửi khi cửa sổ không focus (bất kể công tắc thứ hai) | Người dùng tắt "Chỉ khi…" vẫn không nhận chuông khi cửa sổ đang trước |
| D15 | Gộp và giới hạn | Mỗi tab: thông báo đầu gửi **ngay**; các thông báo sau trong **3 giây** dồn lại, hết 3 s gửi **một** thông báo "N thông báo mới · <chữ mới nhất>" **thay** cái trước (cùng id `shellx.tab.<id>`). Mỗi tab ≤ **6** lần gửi trong 60 s trượt; toàn app ≤ **20** lần/60 s. Vượt → không gửi hệ thống (badge/lịch sử vẫn có). Tab được đọc → thông báo đã gửi của tab đó bị gỡ khỏi Notification Center/Action Center | Chùm dài hơn 3 s thành vài thông báo; vượt giới hạn mất thông báo hệ thống (vẫn thấy trong app) |
| D16 | Bấm thông báo hệ thống | Hiện + đưa cửa sổ lên trước (như kích hoạt A1 D11 nhưng **không** tự mở tab), chọn tab, mở rộng workspace của nó, focus terminal, đánh dấu tab đọc ngay (không chờ 1 s — người dùng chủ động). Tab đã đóng → chỉ đưa cửa sổ lên | — |
| D17 | Thư viện thông báo | Dùng lại `local_notifier` (macOS `NSUserNotification`, Windows WinToast) qua `SystemNotifier`, thêm `id` (thay thế) và `close(id)`. Không thêm phụ thuộc. Chuyển sang `UNUserNotificationCenter`: follow-up | `NSUserNotification` đã deprecated: nếu Apple gỡ, thông báo hệ thống macOS ngừng (badge/vòng vẫn chạy) |
| D18 | Badge macOS | `windowManager.setBadgeLabel` (đã có trong window_manager 0.5.2: `NSApp.dockTile.badgeLabel`, không cần quyền). Áp lại mỗi khi icon Dock hiện lại (A1 D10). Cửa sổ ẩn → không có icon Dock nên không thấy badge; thông báo hệ thống bù lại (D14: ẩn = không focus) | Cửa sổ ẩn không có tổng chưa đọc trên màn hình |
| D19 | Windows | **Overlay icon** trên nút taskbar: chấm tròn `accent` 16 px vẽ bằng GDI lúc chạy (không cần file .ico), mô tả trợ năng "N thông báo chưa đọc"; gỡ khi 0. **Nháy** (`FlashWindowEx`, `FLASHW_TRAY \| FLASHW_TIMERNOFG`) khi có thông báo mới lúc cửa sổ không focus. Làm trong runner C++ (`ITaskbarList3`) qua kênh `pro.shellx.desktop/taskbar` vì package `win32` 5.15 không có hai API này. Số không vẽ lên icon (follow-up) | Chưa thử máy Windows thật; người dùng Windows không thấy con số, chỉ thấy chấm |
| D20 | Chỗ đặt cài đặt | Tray: submenu mới **"Thông báo"** ở **cả** menu đã đăng nhập và chưa đăng nhập: ☑ "Thông báo trên máy tính", ☑ "Chỉ khi cửa sổ không ở phía trước" (mờ khi mục đầu tắt), vạch, submenu cũ "Thông báo khi lệnh chạy lâu xong" (chuyển vào đây, nay dùng được khi chưa đăng nhập — ngưỡng dùng chung, sửa push §7). Khoá settings `desktop_notifications_enabled`, `desktop_notifications_only_unfocused` (thêm `SettingKeys.all`) | Người đã quen vị trí cũ của ngưỡng phải tìm trong "Thông báo" |
| D21 | Vòng sáng | Chỉ cho tab **đang chọn** có chưa đọc. 2 px `accent` + 1 px `accent` 40 % bên trong (giả "glow"), vẽ đè (`IgnorePointer`) mép vùng terminal, nằm trong padding A1 (10/6) nên không che chữ. Hiện: fade `base` 150 ms; tắt: `exit` 120 ms; **không lặp/nhấp nháy** (giữ nguyên tắc A1 §1.5). Giảm chuyển động → tức thì | — |
| D22 | Workspace | Chấm tổng hợp 6 px `accent` trên tiêu đề nhóm **thu gọn** có ít nhất một tab chưa đọc; nhãn Semantics thêm "có thông báo chưa đọc". Nhóm mở rộng không có chấm (badge từng dòng đã đủ) | — |
| D23 | Menu | Menu dòng thêm "Đánh dấu đã đọc" (mờ khi tab không có chưa đọc) và "Đánh dấu tất cả đã đọc" (mờ khi tổng = 0) ở nhóm đầu. Bảng có nút "Đánh dấu tất cả đã đọc" | — |
| D24 | Trình đọc màn hình | Khi cửa sổ focus và thông báo tới tab **không** chọn: `SemanticsService.announce` (lịch sự) "Thông báo mới từ {tab}: {chữ}" — tối đa một lần mỗi 3 s mỗi tab (dùng cửa sổ gộp D15). Nhãn dòng thêm "{n} thông báo chưa đọc, mới nhất: {chữ}" | Thông báo dồn dập chỉ được đọc cái đầu |
| D25 | "Focus" cửa sổ | `window_manager` `onWindowFocus`/`onWindowBlur` (thêm vào `WindowManagerHost`) **và** `WindowState.visible`. Thu nhỏ/ẩn = không focus | — |
| D26 | Tab thoát / đóng | Tab bị gỡ (đóng, thoát mã 0) → chưa đọc của nó bị bỏ (badge, Dock giảm); lịch sử giữ (D11). Tab thoát mã ≠ 0 (còn trên sidebar) giữ chưa đọc như tab thường | — |
| D27 | Riêng tư chi tiết | Chữ thông báo chỉ ở bộ nhớ (`TabAttention`, `DesktopNotifications`) và trong Notification Center/Action Center của hệ điều hành (hệ điều hành tự lưu tới khi gỡ — D15 gỡ khi đọc). `SessionNotice.toString()` không in chữ. Log chỉ: loại, số đếm, `runtimeType` lỗi. Không có dữ liệu mới nào rời máy | Hệ điều hành giữ thông báo cũ ở Notification Center nếu người dùng không đọc trong app |

**Sửa A2:** D12 ("dòng có ngữ cảnh cao 46") — nay dòng có thể có thêm dòng thông báo (46 hoặc 62, xem UI addendum §1.2). UI A1 §2.2 đặt chỗ badge "sau ×" — A4 đặt badge **ngay sau tiêu đề, trước các dấu** để cột dấu và × vẫn thẳng hàng giữa các dòng.

**Sửa push §7:** submenu ngưỡng chuyển vào submenu "Thông báo" và hiện cả khi chưa đăng nhập (D20). Hành vi push không đổi.

---

## 3. Kiến trúc

```
packages/shellx_agent
 ├─ notify/osc_event_parser.dart   + OSC 99 → KittyNotifyRequested (ghép mảnh, D2); BEL nền → BellRung (D3)
 ├─ notify/command_tracker.dart    bỏ qua 2 sự kiện mới
 ├─ notify/agent_notifications.dart (push) không đổi hành vi: chỉ NotifyRequested + lệnh (N8)
 ├─ session/session_notice.dart (mới)  SessionNotice, SessionNoticeKind, NoticeLimiter (D3, D6)
 ├─ session/local_sessions.dart    + Stream<SessionNotice> get notices
 └─ session/session_manager.dart   _track: phát notice; commandNoticeThreshold (D5)
apps/desktop
 ├─ agent/session_core.dart        truyền ngưỡng (D5)
 ├─ platform/notifier.dart         SystemNotifier + id/close (D17)
 ├─ platform/settings_store.dart   + 2 khoá (D20)
 ├─ platform/desktop_notifications.dart (mới)  chính sách gửi, gộp, giới hạn (D14, D15)
 ├─ platform/attention_badge.dart (mới)        Dock (D18) / taskbar (D19)
 ├─ windows/runner/flutter_window.cpp           kênh pro.shellx.desktop/taskbar (D19)
 ├─ terminal/tab_attention.dart (mới)           TabAttention: chưa đọc, lịch sử, đọc 1 s, nhảy (D7–D13)
 ├─ ui/window_focus.dart (mới)                  windowFocusProvider (D25), terminalFocusRequestProvider
 ├─ ui/window_host.dart            + onFocusChanged
 ├─ tray/*                         submenu "Thông báo" (D20)
 └─ ui/terminal/  session_tab_row (badge, dòng thông báo), workspace_header (chấm),
                  session_sidebar (menu, nút chuông), terminal_pane (vòng sáng),
                  notifications_panel (mới), terminal_shortcuts (+ ⌘⇧I, ⌘⇧U)
```

### 3.1 Agent

- **Parser.** `_numbers` thêm `99`. `_finish` cho `99` gọi `_kitty(text)`: tách metadata/payload ở dấu `;` đầu tiên (không có → bỏ), đọc khoá theo D2, giải base64 nếu `e=1`, ghép theo `i`. Ở trạng thái `ground`, byte `0x07` → `BellRung()`. Hai lớp sự kiện mới:
  ```dart
  final class KittyNotifyRequested extends OscEvent { final String? title; final String body; }
  final class BellRung extends OscEvent { const BellRung(); }
  ```
- **Push không đổi (N8, D1).** `SessionNotifier._handle` chỉ khớp `is NotifyRequested` → hai sự kiện mới đi vào `_tracker.handle`, nơi `CommandTracker` bỏ qua chúng. Test khẳng định `NotificationSender` không được gọi cho OSC 99/BEL.
- **`SessionNotice`** (mới, `session/session_notice.dart`); `toString` không in chữ (N9). `NoticeLimiter` theo phiên: bell ≥ 5 s cách nhau, message/command ≤ 30/60 s.
- **`SessionManager`**: tham số mới `Duration? Function()? commandNoticeThreshold` (mặc định `null` = không thông báo lệnh); `_Session.commands = CommandTracker(threshold: commandNoticeThreshold ?? () => null, now: clock)`. Trong `_track`, với mỗi sự kiện: `commands.handle` trả `CompletedCommand` → notice `command`; `NotifyRequested` → `message`; `KittyNotifyRequested` → `message`; `BellRung` → `bell`. Phiên đang đóng không phát. `notices` là `StreamController.broadcast()` **không đồng bộ** (người nghe không gọi ngược vào manager trong callback).
- **`LocalSessions`** thêm `Stream<SessionNotice> get notices;` — mọi hiện thực cập nhật cùng commit (`SessionManager`, `FakeLocalSessions`).

### 3.2 Desktop

- **`TabAttention`** (`NotifierProvider<TabAttention, AttentionState>`): nghe `localSessions.notices`, `terminalTabsProvider` (tab đang chọn, tab mất), `windowFocusProvider`, `windowRouterProvider.visible`. Trạng thái: `Map<int, TabUnread> unread`, `List<AttentionEntry> history` (≤ 50). Hành động: `markRead(tabId)`, `markAllRead()`, `nextUnread()` → `int?`. Phát `Stream<AttentionArrival> arrivals` (thông báo **không** thuộc D7) cho `DesktopNotifications`, badge Windows (nháy) và thông báo trợ năng.
- **`DesktopNotifications`**: nhận `AttentionArrival` + trạng thái focus/chọn, đọc hai cài đặt mỗi lần (D14), gộp/giới hạn (D15), gọi `SystemNotifier.show(id: 'shellx.tab.<id>', …, onClick: …)`; `tabRead(id)` → `close`. Bấm → `jumpToTab` (D16).
- **Badge:** `listenForAttentionBadge` nghe `totalUnread` (khác giá trị mới gọi), và `visible` (áp lại khi hiện). `BadgeHost`: `MacDockBadge` (window_manager), `WindowsTaskbarBadge` (kênh), `NoBadge`.
- **Nhảy tới tab (`jumpToTab`)**: `TerminalTabs.select(id)`, `SidebarWorkspaces.reveal(id)` (mở rộng nhóm), `terminalFocusRequestProvider` tăng → `TerminalWorkspacePage` focus terminal; từ thông báo hệ thống thêm `router.showTerminal()` (raise) và `TabAttention.markRead(id)`.
- **Phím tắt:** `ToggleNotificationsPanelIntent` (⌘⇧I / Ctrl+Shift+I), `JumpToNextUnreadIntent` (⌘⇧U / Ctrl+Shift+U), không lặp phím, có trong cả `desktopShortcuts` và `terminalViewShortcuts`.
- **UI:** badge, dòng thông báo, chấm nhóm, vòng sáng, bảng, nút chuông — xem UI addendum.

---

## 4. Luồng dữ liệu

```
chương trình ─► OSC 9/777/99, BEL, 133;C/D ─► PTY output ─► SessionManager._watch
   ├─ SessionNotifier.feed (push, KHÔNG đổi) ─► NotificationSender ─► relay ─► điện thoại
   └─ _track ─► OscEventParser ─► NoticeLimiter ─► notices (SessionNotice)
                                                       │
                     TabAttention ◄────────────────────┘
                       ├─ D7 thấy rồi? ─► lịch sử (đã đọc)
                       └─ chưa thấy ─► unread + lịch sử ─► sidebar (badge, dòng), vòng, Dock/taskbar
                                                       └─► arrivals ─► DesktopNotifications ─► SystemNotifier
                                                                     └─► announce (D24), nháy taskbar (D19)
chọn tab + focus + 1 s / menu / bấm thông báo ─► markRead ─► gỡ badge/vòng, close() thông báo hệ thống
```

Hai parser độc lập trên cùng byte (một của push, một của `_track`) — đã như vậy từ A1/A2; A4 không thêm lượt quét byte thứ ba.

---

## 5. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Chưa đăng nhập | Desktop vẫn đầy đủ (badge, vòng, bảng, hệ thống); push tự thất bại cục bộ như hiện nay |
| Hệ điều hành chặn thông báo (Focus/Không làm phiền, người dùng tắt quyền) | `show` thất bại hoặc bị hệ thống nuốt → không làm gì thêm, log `runtimeType`; badge/vòng/bảng vẫn chạy |
| `yes $'\e]9;x\a'` | Agent: ≤ 30/phút/phiên (D6); desktop: badge tăng tới 30, `99+` nếu cộng dồn; hệ thống ≤ 6/phút/tab (D15) |
| `yes $'\a'` | Một chuông mỗi 5 s (D3); không thông báo hệ thống khi cửa sổ focus |
| OSC 99 nhiều mảnh không bao giờ có `d=1` | Bản nháp nằm trong bộ đệm (≤ 4), bị đẩy ra khi có bản thứ 5; không rò bộ nhớ |
| OSC 99 `p=?` (truy vấn khả năng) | Bỏ qua, **không** trả lời (chương trình kitty sẽ dùng mặc định) |
| OSC 99 base64 hỏng | Bỏ mảnh |
| OSC 9;4 (thanh tiến trình ConEmu/Windows Terminal) | Vẫn bỏ (push §4.1) |
| Thông báo từ phiên do điện thoại mở | Như mọi tab (tab 📱 cũng có badge) |
| Tab đóng khi thông báo hệ thống của nó còn trong Notification Center | Bấm → chỉ đưa cửa sổ lên (D16); `close` gọi khi tab bị gỡ |
| Bấm thông báo khi cửa sổ có hộp thoại | Cửa sổ lên trước, tab được chọn phía sau hộp thoại; focus terminal sau khi hộp thoại đóng (quy tắc A1) |
| Tab đang chọn nằm trong nhóm thu gọn và có chưa đọc | Vòng vẫn hiện (terminal đang hiện tab đó); chấm nhóm hiện |
| Cửa sổ ẩn, tab đang chọn nhận thông báo | Không thuộc D7 (không focus): badge, Dock (nếu icon hiện), hệ thống |
| Đổi ngôn ngữ hệ thống khi đang chạy | Chữ đã tạo giữ nguyên; thông báo mới theo ngôn ngữ app |
| Đồng hồ máy nhảy (ngủ/dậy) | Thời gian tương đối tính từ `at` so với `now`; âm → "vừa xong" |
| Gộp đang chờ (3 s) thì tab bị đọc | Huỷ thông báo gộp |
| Windows: runner không có kênh (bản dựng cũ) / COM lỗi | `MissingPluginException`/lỗi bị nuốt, log `runtimeType` một lần |

---

## 6. Kiểm thử

- **`shellx_agent`** (`dart test`):
  - `osc99_bell_event_test`: OSC 99 một mảnh, nhiều mảnh (`d=0` rồi `p=body`), `e=1` tiếng Việt, khoá lạ bỏ qua, `p=?`/`p=icon` bỏ, base64 hỏng, > 4 bản nháp, BEL/ST, cắt giữa chunk; BEL nền → `BellRung`, BEL kết thúc OSC/OSC 133 → không; `ESC BEL` → không.
  - `command_tracker_test`: bỏ qua sự kiện mới.
  - `session_notifications_test` (push): OSC 99 và BEL không gọi sender; OSC 9/777/lệnh gọi đúng số lần như trước (N8).
  - `session_notice_test` (`SessionRig` + `FakePty`): `notices` cho OSC 9/777/99, BEL (≤ 1/5 s theo đồng hồ rig), lệnh vượt ngưỡng (rig `now`), ngưỡng null → không; 31 thông báo/60 s → 30; phiên đóng → không; `toString` không chứa chữ.
- **`apps/desktop`** (`flutter test`): `tab_attention_test` (D7, D8, D9, D10 với `fake_async`, D11, D13, D26, markRead/All), `desktop_notifications_test` (D14 ma trận, D15 gộp/giới hạn/close, click → jump, cài đặt đọc trực tiếp), `attention_badge_test` (nhãn `99+`, áp lại khi hiện, nháy chỉ khi không focus), `tray_notifications_test` (submenu, cả khi chưa đăng nhập), widget test sidebar (badge, dòng thông báo, chiều cao 46/62, menu, chấm nhóm, nhãn Semantics), `attention_ring_test` (hiện/tắt, giảm chuyển động tĩnh, không đổi cỡ terminal: `resizes` của view không đổi), `notifications_panel_test` (danh sách, bàn phím, Enter nhảy, Esc, tab đã đóng, trống, ⌘⇧I/⌘⇧U), `window_focus_test`.
- **Thử tay** (HANDOFF §13): macOS và Windows thật — Claude Code (`kitty`, `iterm2`, `terminal_bell`), `shellx notify`, Notification Center, bấm thông báo khi ở Space khác/thu nhỏ, Dock badge sau khi ẩn/hiện, Focus mode, VoiceOver/Narrator đọc dòng và thông báo, taskbar overlay + nháy trên Windows 10/11.

---

## 7. Ngoài phạm vi A4

Badge/số chưa đọc trên app điện thoại và đồng bộ "đã đọc" giữa máy và điện thoại; OSC 99 nâng cao (nút bấm, icon, `o=`, `a=`, trả lời truy vấn `?`, sự kiện đóng/kích hoạt gửi lại chương trình); âm thanh tuỳ chọn, tắt tiếng theo tab; quy tắc lọc thông báo; lưu lịch sử qua khởi động lại (**A5**); thông báo hệ thống có nút hành động; số trên overlay icon Windows; chuyển sang `UNUserNotificationCenter`; hook Claude Code chuyên dụng (`shellx notify` qua CLI/socket — **A7**); nhiều cửa sổ.
