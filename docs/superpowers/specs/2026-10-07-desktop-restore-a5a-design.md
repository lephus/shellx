# A5a — Khôi phục phiên trên desktop (bố cục, thư mục, nội dung terminal) — Đặc tả thiết kế

- **Ngày:** 2026-10-07
- **Trạng thái:** Người dùng giao toàn quyền cho controller (như A1–A4). Quyết định R0–R8 do controller chốt (ràng buộc); D1–D26 do người viết spec chốt trong phạm vi R0–R8. Tất cả ghi ở bảng §2 kèm cái giá nếu sai.
- **Lộ trình:** A1 → A2 → A4 → A3 → **A5a (tài liệu này: khôi phục)** → A5b (daemon `shellx-mux`, `2026-10-07-desktop-daemon-a5b-design.md`) → A6 trình duyệt nhúng → A7 CLI/socket → A8 SSH/tmux → A9 skills, phím tắt tuỳ biến, file cấu hình.
- **Thứ tự thực thi:** A5a **chạy sau khi A3 đã merge vào `main`** (lưu cây pane của A3; dùng `LocalSessions.open(cwd:)` của A3 D17). A5b chạy sau A5a.
- **Tài liệu đi kèm:** UI addendum `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a5.md` (dùng chung A5a/A5b; ràng buộc cho phần nhìn và chữ); plan `docs/superpowers/plans/2026-10-07-desktop-restore-a5a.md`.
- **Giữ nguyên:** spec A1 (D1–D16), A2 (C1–C8, D1–D19), A4 (N1–N9, D1–D27), A3 (P1–P9, D1–D30). Tài liệu này chỉ **thêm** và ghi rõ chỗ nào sửa.
- **Ký hiệu:** "A3 D17" = quyết định D17 của spec A3; "R1"/"D1" không tiền tố = của tài liệu này.

---

## 1. Mục tiêu

Như cmux: **thoát rồi mở lại ShellX, kể cả sau khi khởi động lại máy hay app bị crash, mọi thứ trở lại như cũ** — cùng workspace, cùng tab (tên, thứ tự, nhóm), cùng cây pane (tỉ lệ, phóng to, pane focus), mỗi pane là một **shell đăng nhập mới ở đúng thư mục cũ**, phía trên là **nội dung terminal lần trước** (tối đa 2.000 dòng) ngăn bằng một vạch mờ "— Phiên được khôi phục · <thời gian> —", và đúng tab đang chọn.

Shell **không** sống sót qua thoát/khởi động lại trong A5a (tiến trình đã chết): A5a dựng lại "chỗ làm việc", không dựng lại tiến trình. Giữ shell sống khi giao diện thoát/crash/cập nhật là việc của **A5b**.

### Tiêu chí thành công (đo được)

1. **Bố cục:** có 2 workspace ("Mặc định" 2 tab, "API" 3 tab, một tab đổi tên "server", một tab chia 3 pane với một đường chia kéo về 30/70 và pane 2 phóng to), ⌘Q → mở lại ShellX → trong ≤ 2 s sau khi cửa sổ hiện: sidebar giống hệt (workspace, thứ tự, tên, trạng thái thu gọn), tab chia có 3 pane đúng tỉ lệ (±1 px), pane 2 vẫn phóng to, pane focus như cũ, tab đang chọn như cũ, **không** có tab thừa (A1 D11 không mở thêm tab).
2. **Thư mục:** pane đã `cd ~/work/shellx` (OSC 7, A2 C1) → sau khi mở lại `pwd` in `~/work/shellx`. Thư mục đã bị xoá / ổ mạng không phản hồi trong 300 ms / đường dẫn UNC → pane ở home (A3 D17), không lỗi, không chờ.
3. **Nội dung:** `seq 1 5000` trong một pane rồi thoát → mở lại: pane đó hiện các dòng `3001`…`5000` (2.000 dòng cuối), ngay dưới là vạch mờ "— Phiên được khôi phục · 14:32 —", dưới nữa là prompt mới. Màu (`ls --color`, prompt có màu, truecolor) giữ nguyên; dòng dài bị gói lại theo bề rộng mới (không cắt). Nội dung khôi phục **không** được gửi vào shell (gõ `history` không thấy gì lạ, không có ký tự rác ở prompt) và **không** có trên điện thoại.
4. **Giới hạn:** một pane có dòng 10 KB × 100 → nội dung lưu ≤ 256 KiB (bỏ dòng cũ nhất, không cắt giữa dòng, không cắt giữa ký tự UTF-8/chuỗi SGR).
5. **Khởi động lại máy:** làm việc bình thường rồi Apple menu → Khởi động lại (macOS) / Start → Restart (Windows) **không** thoát ShellX trước → sau khi đăng nhập và mở ShellX: bố cục đầy đủ; nội dung terminal tính tới **lần lưu cuối** (khi tắt máy nếu hệ điều hành cho kịp, nếu không thì ≤ 60 s trước).
6. **Crash:** `kill -9` tiến trình ShellX (Windows: Task Manager → End task) → mở lại: bố cục của lần thay đổi cấu trúc cuối (≤ 1 s trước khi kill), nội dung ≤ 60 s trước; dải "ShellX đã đóng bất thường lần trước…" hiện trên vùng terminal tới khi bấm "Đóng".
7. **File hỏng:** ghi rác vào `restore/layout.json` → mở lại: ShellX mở như lần đầu (một tab ở home), không crash, không thông báo lỗi chặn; file rác còn ở `layout.json.bak`.
8. **Cài đặt:** tray → "Terminal" → bỏ chọn "Lưu nội dung terminal khi thoát" → mọi file nội dung đã lưu bị xoá **ngay** (thư mục `restore/scrollback/` rỗng); thoát và mở lại: bố cục + thư mục vẫn khôi phục, không có nội dung cũ và không có vạch. "Xóa nội dung đã lưu" xoá file ngay mà không đổi công tắc.
9. **Quyền và chỗ lưu:** macOS `~/Library/Application Support/pro.shellx.desktop/restore/` (thư mục 0700, mọi file 0600, đã loại khỏi Time Machine); Windows `%LOCALAPPDATA%\ShellX\restore\` (kế thừa ACL chỉ chủ sở hữu, **không** nằm trong Roaming). Không file nào của A5a rời máy (không relay, không điện thoại, không đồng bộ).
10. **Hiệu năng:** lưu cuối khi thoát với 32 pane × 2.000 dòng ≤ 500 ms trên Apple M-series (test đo, không chặn); một lần lưu bố cục ≤ 20 ms; khôi phục: tab đang chọn gõ được ≤ 1 s sau khi cửa sổ hiện, các tab khác mở dần.
11. **Không hồi quy:** mọi test A1/A2/A4/A3 vẫn xanh; lần chạy đầu tiên (chưa có file) giống hệt A3.

---

## 2. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| R0 | Tách A5 (controller) | A5 = **A5a Khôi phục** (tài liệu này, chạy được ngay sau A3) + **A5b Daemon** (spec/plan riêng, chạy sau A5a) | — |
| R1 | Khi nào lưu (controller) | Mỗi thay đổi cấu trúc (debounce 1 s) và khi thoát. Ghi **nguyên tử** (file tạm + rename), JSON trong thư mục app support, quyền 0600 | — |
| R2 | Lưu gì (controller) | Bounds cửa sổ; workspace (tên, thứ tự, thu gọn); tab (tên tuỳ chỉnh, thứ tự, thành viên); cây pane A3 (tỉ lệ, phóng to); cwd mỗi pane; nội dung cuối mỗi pane ≤ 2.000 dòng / 256 KB (có giữ SGR hay không: D5) | — |
| R3 | Công tắc (controller) | "Lưu nội dung terminal khi thoát" (mặc định bật) tắt được việc lưu nội dung; nội dung không bao giờ đồng bộ đi đâu | — |
| R4 | Khi mở (controller) | Dựng lại workspace/tab/pane; mở shell đăng nhập **mới** ở cwd đã lưu (không được thì home); vẽ nội dung đã lưu phía trên vạch mờ "— Phiên được khôi phục · <thời gian> —"; chọn lại tab đã chọn | — |
| R5 | Vạch và ring buffer (controller: chọn ở D8) | Vạch không gửi vào shell; có vào ring buffer điện thoại hay không: D8 | — |
| R6 | An toàn khi crash (controller) | File tạm + rename; file hỏng → bắt đầu mới và giữ `.bak` | — |
| R7 | Riêng tư (controller) | Ghi chú ở trang chính sách riêng tư + HANDOFF | — |
| R8 | Nền tảng cho A5b | Bố cục ghi kèm id phiên và id thể hiện daemon để A5b gắn lại vào phiên còn sống (D21) | — |
| D1 | Nguồn dữ liệu | **Không chép đôi.** Bounds cửa sổ đã lưu trong settings từ A1 D9 (`window_*`); danh sách workspace + tên + thu gọn đã lưu trong settings từ A2 D17 (`terminal_workspaces`) — giữ nguyên ở đó. File bố cục A5a chỉ thêm cái chưa lưu ở đâu: thành viên/thứ tự tab theo **id workspace**, tên tuỳ chỉnh, cây pane, cwd, tab đang chọn, pane focus, phóng to. Workspace trong file không còn trong settings → tab về "Mặc định" | Hai nguồn có thể lệch nhau một nhịp (vd. crash giữa hai lần ghi): tab rơi về Mặc định |
| D2 | Chỗ lưu | macOS: `<app support>/restore/` = `~/Library/Application Support/pro.shellx.desktop/restore/`. Windows: `%LOCALAPPDATA%\ShellX\restore\` — **không** dùng `getApplicationSupportDirectory()` (trên Windows là `%APPDATA%` = Roaming, có thể bị đồng bộ theo roaming profile của domain). Thư mục 0700, file 0600 đặt **trước** khi ghi nội dung (như `EndpointFile` A1/term). macOS: `tmutil addexclusion <restore>` một lần, cố gắng hết sức (lỗi chỉ log loại lỗi) | Máy mất ổ thì mất nội dung đã lưu (chấp nhận: đây là bộ nhớ đệm, không phải dữ liệu người dùng) |
| D3 | Tách file | `restore/layout.json` (nhỏ, vài KB) + `restore/scrollback/<paneKey>.txt` mỗi pane một file. Lưu bố cục mỗi giây không phải ghi lại 8 MB nội dung | Nhiều file nhỏ hơn (≤ 32) |
| D4 | Lịch lưu | **Bố cục:** debounce 1 s sau mỗi thay đổi: mở/đóng/sắp xếp/đổi tên/chuyển workspace tab, chọn tab, chia/đóng pane, thả đường chia, cân bằng, đổi cỡ bằng phím, phóng to, đổi pane focus, cwd đổi, đổi workspace (A2 lưu riêng). **Nội dung:** (a) khi Thoát, (b) khi hệ điều hành báo tắt máy/đăng xuất (D18), (c) khi cửa sổ ẩn, (d) mỗi **60 s** cho pane có output mới kể từ lần ghi trước. Pane không có output mới không bị ghi lại | Crash mất ≤ 60 s nội dung cuối |
| D5 | Định dạng nội dung | **Giữ màu, nhưng tự mã hoá lại từ ô của xterm** — không bao giờ lưu byte PTY thô. Chỉ sinh: chữ in được, `\r\n`, và SGR `ESC [ … m` (màu 16/256/truecolor cho chữ và nền; đậm, mờ, nghiêng, gạch dưới, đảo màu, gạch ngang). Bỏ: nhấp nháy; ô `invisible` thành khoảng trắng; OSC 8 link, tiêu đề, chế độ chuột, alt screen. Chỉ **buffer chính** (màn hình `vim`/`htop` ở alt screen không lưu; buffer chính bên dưới thì lưu). Dòng gói (`isWrapped`) nối lại thành một dòng logic để gói lại theo bề rộng mới. Bỏ dòng trống cuối. Giới hạn: **2.000 dòng logic** cuối **và** ≤ **256 KiB** UTF-8 sau mã hoá (bỏ dòng cũ nhất, nguyên dòng). Mỗi dòng kết thúc bằng `ESC[0m` nếu có SGR | Mất link OSC 8 và gạch dưới kiểu (curly) trong nội dung cũ |
| D6 | Lọc khi nạp | File nội dung là dữ liệu không tin cậy (ai đó cùng tài khoản có thể sửa): khi nạp, **chỉ giữ** ký tự in được (≥ 0x20, khác 0x7F, kể cả Unicode), `\r`, `\n`, `\t` và chuỗi đúng dạng `ESC [ [0-9;:]{0,64} m`. Mọi ESC/C0/C1 khác bị xoá. File > 512 KiB hoặc UTF-8 hỏng → bỏ qua file đó | — |
| D7 | Mở lại shell | Mỗi pane đã lưu → `LocalSessions.open(cols, rows, cwd: cwdĐãLưu)` (quy tắc A3 D17: tuyệt đối, không UNC, tồn tại ≤ 300 ms; sai → home). Mở **tuần tự**, **tab đang chọn trước** (dùng được sớm nhất), rồi theo thứ tự sidebar. Tối đa 32 phiên (A1 D8): pane vượt giới hạn bị bỏ. Pane mở lỗi (spawn lỗi, giới hạn) bị gỡ khỏi cây (anh em chiếm chỗ, A3 D7); tab không còn pane bị bỏ. Có pane bị bỏ → **một** toast trung tính "Không mở lại được {n} pane" | Lưu hơn 32 pane là không thể (giới hạn đã chặn lúc tạo) — chỉ xảy ra nếu giới hạn giảm sau này |
| D8 | Vạch và ring buffer (R5) | Nội dung đã lưu + vạch **chỉ ghi vào `Terminal` của xterm trên desktop**: không vào PTY, không vào ring buffer của agent, **không tới điện thoại** (điện thoại thấy phiên mới tinh, như mọi phiên mới). Vạch: dòng riêng `ESC[0m` + `ESC[2m` + "— Phiên được khôi phục · {thời gian} —" + `ESC[0m` + `\r\n`, chỉ khi pane **có** nội dung đã lưu. Lý do: ring buffer là sự thật của PTY; chèn vào làm điện thoại phát lại hai lần và lệch trạng thái emulator (con trỏ, alt screen) | Điện thoại không xem được lịch sử của phiên được khôi phục |
| D9 | Không khôi phục | Chương trình đang chạy (không chạy lại lệnh — giống cmux), biến môi trường, gắn điện thoại, driver, vùng chọn, vị trí cuộn (luôn ở đáy), chưa đọc/lịch sử A4, pane **đã thoát** (mã ≠ 0) và nội dung của nó. Tab gốc điện thoại được khôi phục như tab desktop (phiên mới là phiên desktop) | Người muốn chạy lại lệnh phải gõ lại (↑ trong history của shell) |
| D10 | Chọn lại | Tab đang chọn, pane focus, pane phóng to, tỉ lệ từng nút; workspace hiện tại = workspace của tab đang chọn. Tab đang chọn không mở được → tab đầu tiên nhìn thấy | — |
| D11 | Hỏng file | `layout.json`: không đọc được / không phải JSON / `v` khác 1 / cấu trúc sai (cây pane sai, lá trùng `paneKey`, tỉ lệ ngoài [0,05; 0,95], tab không có pane, chuỗi quá dài) → **bỏ cả file**: đổi tên thành `layout.json.bak` (đè `.bak` cũ), bắt đầu như lần đầu. Khoá lạ bị bỏ qua (tương thích bản sau). Log chỉ `restore: layout unreadable (<loại>)` — không nội dung, không đường dẫn | Một lỗi nhỏ làm mất cả bố cục (có `.bak` để điều tra) |
| D12 | Đánh dấu thoát sạch | Lần ghi bố cục đầu tiên của một lần chạy ghi `cleanExit: false`; lần ghi cuối khi Thoát và khi tắt máy (D18) ghi `cleanExit: true`. Mở app gặp `cleanExit: false` **và** có ít nhất một tab được khôi phục → dải "đóng bất thường" (UI-A5 §4) | Tắt máy mà hệ điều hành không cho kịp ghi → lần sau báo "đóng bất thường" dù người dùng không làm gì sai (chữ trong dải trung tính, không đổ lỗi) |
| D13 | Công tắc (R3) | Khoá settings `terminal_restore_scrollback` (bool, mặc định `true`, thêm `SettingKeys.all`). Tray: submenu mới **"Terminal"** (cả menu đã/chưa đăng nhập, ngay trước "Thông báo"): ☑ "Lưu nội dung terminal khi thoát", "Xóa nội dung đã lưu" (mờ khi không có file nào). Tắt → xoá **ngay** mọi file nội dung và ngừng ghi; bố cục + cwd vẫn lưu. Bật lại → ghi từ lần lưu sau | Không có công tắc tắt hẳn khôi phục bố cục (ngoài phạm vi; bố cục không chứa nội dung terminal) |
| D14 | `paneKey` | Mỗi pane có khoá khôi phục ngẫu nhiên 128 bit (32 hex) cấp lúc pane xuất hiện, sống trong `RestorePersistence` (map id phiên → khoá), **không** trong `TerminalTab`. Pane được khôi phục **giữ khoá cũ** (file nội dung của nó được ghi đè lần sau). Tên file = khoá (không bao giờ từ dữ liệu người dùng) | — |
| D15 | Dọn file | Pane đóng → file nội dung của nó bị xoá ở lần lưu bố cục kế. Khi khởi động, sau khôi phục: xoá mọi file trong `scrollback/` không thuộc bố cục và mọi `*.tmp-*` còn sót | — |
| D16 | Thời điểm khôi phục | Sau `bootstrap()` và khung hình đầu (để lưới pane đã đo), **trước** `handleActivation` (A1 D11): khôi phục ra ≥ 1 tab thì D11 không mở thêm tab. Trong lúc khôi phục, `+`/⌘T vẫn dùng được (cờ `opening` của A1 chỉ giữ trong từng lần `open`). Phiên điện thoại mở trong lúc khôi phục → tab mới như A1 | Mất ≤ 1 khung hình trước khi tab đầu hiện |
| D17 | Lưới khi mở | Mỗi pane mở với lưới **ước tính** từ lưới vùng terminal hiện tại và tỉ lệ đã lưu (A3 D13); lưới thật tới ở lần bố trí kế (một SIGWINCH) | Một lần vẽ lại prompt ngay sau khi mở |
| D18 | Tắt máy / đăng xuất | **macOS:** khi `applicationShouldTerminate` thấy lý do tắt máy/đăng xuất (đã có từ A1), trả `.terminateLater`, gọi Dart `saveBeforeExit` qua kênh `pro.shellx.desktop/app`, trả lời `NSApp.reply(toApplicationShouldTerminate: true)` khi Dart xong hoặc sau **3 s**. **Windows:** `WM_QUERYENDSESSION` trong runner → gửi `saveBeforeExit` (không chờ), trả `TRUE`; `WM_ENDSESSION` không chặn. Dart lưu bố cục + nội dung với `cleanExit: true`, giới hạn 2 s | Windows có thể tắt trước khi lưu xong → lần sau dùng bản ≤ 60 s trước và báo "đóng bất thường" |
| D19 | Hiệu năng | Mã hoá nội dung chạy trên isolate UI (xterm `Terminal` không chuyển isolate được) nhưng **chỉ** cho pane bẩn; ghi file bất đồng bộ. Khi khôi phục, nội dung đi qua `TerminalFeed` (A1, 256 Ki ký tự/khung hình) nên 32 pane × 256 KiB không treo UI | Thoát với 32 pane đầy mất ~0,5 s |
| D20 | Cửa sổ | Bounds/phóng to cửa sổ dùng cơ chế A1 D9 (đã lưu mỗi lần di chuyển/đổi cỡ) — không đổi | — |
| D21 | Móc cho A5b (R8) | Bố cục ghi `daemon: null` (A5a) và mỗi lá có `session` = id phiên hiện tại. A5a **bỏ qua** hai trường này khi nạp; A5b dùng để gắn lại phiên còn sống | — |
| D22 | Riêng tư (R7) | Nội dung terminal có thể chứa bí mật (token in ra màn hình…): chỉ ở máy, 0600, loại khỏi Time Machine, không bao giờ log/gửi/đồng bộ; bị xoá khi tắt công tắc, "Xóa nội dung đã lưu", đóng pane, gỡ cài đặt (Windows: uninstaller xoá `%LOCALAPPDATA%\ShellX\restore`; macOS: theo thư mục app support như dữ liệu khác). Bố cục chứa đường dẫn thư mục và tên tab (không phải nội dung terminal). Trang chính sách riêng tư §4 (vi/en) thêm một gạch đầu dòng; HANDOFF §15 | — |
| D23 | Thời gian trên vạch | Giờ địa phương lúc **lưu nội dung lần cuối** của pane: hôm nay → "14:32"; hôm qua → "hôm qua 14:32"/"yesterday 14:32"; cũ hơn → "6/10 14:32" (vi, `d/M HH:mm`) / "Oct 6 14:32" (en, `MMM d HH:mm`), luôn 24 giờ | — |
| D24 | Thông báo đóng bất thường | Dải trung tính trên vùng terminal (UI-A5 §4), **không tự ẩn** (WCAG 2.2.1), đóng bằng nút "Đóng" hoặc Esc khi dải có focus. Đọc lên một lần (lịch sự) | — |
| D25 | Ghi đồng thời | Một bộ ghi tuần tự (hàng đợi) cho mọi file restore: không bao giờ hai lần ghi cùng file chồng nhau; lần ghi bố cục mới thay lần đang chờ | — |
| D26 | Đơn vị đo | "Dòng" = dòng logic (sau khi nối dòng gói). 256 KiB = 262 144 byte UTF-8 sau mã hoá D5 | — |

**Sửa A1:** D11 ("chưa có tab nào thì tự mở một tab") — nay chỉ khi khôi phục không ra tab nào (D16). §7 "khôi phục sau khởi động lại: ngoài phạm vi" — nay trong phạm vi (không gồm tiến trình).
**Sửa A2:** C5/D19 "thoát app mất thành viên / tên tab" — nay được khôi phục.
**Sửa A3:** P8 "lưu bố cục: A5" — nay làm ở đây.

---

## 3. Kiến trúc

```
apps/desktop
 ├─ restore/ (mới)
 │   ├─ scrollback_codec.dart   encodeScrollback(Terminal) → String (D5, D26); sanitizeRestored(String) (D6);
 │   │                          restoreDivider(...) (D8, D23)
 │   ├─ restore_snapshot.dart   RestoreSnapshot / SavedTab / SavedPaneNode — toJson / tryParse (D1, D11, D21)
 │   ├─ restore_store.dart      RestoreStore: thư mục, quyền, ghi nguyên tử, .bak, file nội dung, dọn (D2, D3, D11, D15, D25)
 │   ├─ restore_persistence.dart  Notifier: nghe tab/workspace → debounce 1 s; nội dung bẩn 60 s; ẩn/thoát/tắt máy (D4, D12, D13, D14)
 │   └─ restore_paths.dart      restoreDirectory(platform, env, appSupport) (D2)
 ├─ terminal/terminal_tabs.dart     restore(RestorePlan) — mở pane theo thứ tự D7, ghi nội dung + vạch trước backlog (D7–D10, D17)
 ├─ terminal/sidebar_workspaces.dart  adopt(Map<String, List<int>> members, currentId) (D1, D10)
 ├─ platform/settings_store.dart    + terminal_restore_scrollback (D13)
 ├─ platform/app_reopen.dart        + saveBeforeExit (D18)
 ├─ tray/…                          submenu "Terminal" (D13)
 ├─ ui/terminal/restore_strip.dart (mới)  dải đóng bất thường (D24)
 ├─ main.dart                       mở store, khôi phục trước handleActivation, lưu cuối khi Thoát (D16, D12)
 ├─ macos/Runner/AppDelegate.swift  .terminateLater + saveBeforeExit (D18)
 └─ windows/runner/flutter_window.cpp  WM_QUERYENDSESSION → saveBeforeExit (D18)
web/src/pages/privacy.md, en/privacy.md   §4 thêm một mục (D22)
release/windows/shellx.iss               [UninstallDelete] %LOCALAPPDATA%\ShellX\restore (D22)
```

Agent (`packages/shellx_agent`), protocol (`shellx_core`), mobile, relay, `term/`: **không đổi**.

### 3.1 File bố cục (`layout.json`, v1)

```json
{
  "v": 1,
  "savedAt": "2026-10-07T14:32:05.123Z",
  "cleanExit": false,
  "daemon": null,
  "selectedTab": "a1b2…(paneKey của pane tạo tab)",
  "workspaces": [
    {"id": "default", "tabs": ["k1", "k4"]},
    {"id": "w3x9", "tabs": ["k7"]}
  ],
  "tabs": [
    {
      "key": "k1",
      "name": "server",
      "focused": "k2",
      "zoomed": null,
      "layout": {"split": "row", "ratio": 0.3,
                 "first": {"pane": "k1", "cwd": "/Users/a/work/shellx", "session": 12},
                 "second": {"split": "column", "ratio": 0.5,
                            "first": {"pane": "k2", "cwd": null, "session": 15},
                            "second": {"pane": "k3", "cwd": "/tmp", "session": 16}}}
    }
  ]
}
```

- Khoá tab = `paneKey` của pane đã tạo tab (tương ứng A3 D1: id tab = id phiên tạo tab). `name` = tên tuỳ chỉnh (null = tự động). `workspaces[].tabs` liệt kê khoá tab theo thứ tự sidebar; tab không thuộc workspace nào → cuối Mặc định.
- Giới hạn khi đọc (D11): ≤ 32 lá tổng cộng, độ sâu cây ≤ 32, `name` ≤ 64 ký tự, `cwd` ≤ 4096 ký tự, khoá đúng 32 hex.
- `session`/`daemon`: A5a ghi, không đọc (D21).

### 3.2 `RestorePersistence` (Riverpod Notifier, desktop)

- Nghe `terminalTabsProvider` và `sidebarWorkspacesProvider`: dựng `RestoreSnapshot` (thuần, có test) → so với bản đã ghi gần nhất → khác thì hẹn ghi sau 1 s (huỷ hẹn trước).
- `_keys: Map<int sessionId, String paneKey>` (D14); `_dirty: Set<String paneKey>` — đánh dấu khi `TerminalFeed` của pane ghi chữ (hook nhẹ trong `TerminalTabs`: `onPaneOutput(sessionId)`).
- `Timer.periodic(60 s)` → ghi nội dung các pane bẩn (nếu công tắc bật).
- `flushAll({required bool clean})`: ghi bố cục (cờ `cleanExit`) + nội dung mọi pane bẩn; dùng khi Thoát, khi `saveBeforeExit`, khi cửa sổ ẩn (`clean: false`).
- `setScrollbackEnabled(bool)` / `clearScrollback()` (D13).

### 3.3 `TerminalTabs.restore`

`Future<RestoreOutcome> restore(RestorePlan plan)` — `RestorePlan` = snapshot đã kiểm + nội dung đã lọc theo `paneKey` + thời điểm lưu. Với từng tab theo D7: mở từng lá bằng `_local.open(cols, rows, cwd:)`; ngay khi có id phiên và **trước khi** gắn view, ghi nội dung + vạch vào `DesktopTerminal` mới (qua `TerminalFeed` + `drain`); sau đó backlog/output như A1. Cây được dựng lại bằng cách thay lá `paneKey` bằng `PaneLeaf(sessionId)`, lá lỗi bị `removePane`. Trả `RestoreOutcome {tabsRestored, panesFailed, keyBySession}` để `RestorePersistence` giữ khoá cũ và `SidebarWorkspaces.adopt(...)` đặt thành viên.

---

## 4. Luồng dữ liệu

```
khởi động ─► RestoreStore.load() ─► (hỏng → .bak, null) ─► RestorePlan
           ─► TerminalTabs.restore(plan) ─► open(cwd) tuần tự ─► xterm: nội dung đã lọc + vạch ─► backlog/output
           ─► SidebarWorkspaces.adopt ─► chọn tab/pane/zoom ─► (cleanExit=false & có tab) ─► dải đóng bất thường
           ─► handleActivation: có tab → không mở thêm
thay đổi cấu trúc ─► RestorePersistence ─► debounce 1 s ─► RestoreStore.writeLayout (tạm + rename, 0600)
output pane ─► dirty ─► (60 s | ẩn | Thoát | tắt máy) ─► encodeScrollback ─► RestoreStore.writeScrollback
Thoát (tray/⌘Q) ─► flushAll(clean: true) ─► closeAll (A1) ─► exit
```

---

## 5. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Chưa có file (lần đầu, sau khi xoá) | Như A3: một tab ở home |
| `layout.json` hỏng | `.bak`, bắt đầu mới (D11) |
| File nội dung thiếu/hỏng/quá lớn | Pane không có nội dung cũ, không vạch |
| cwd không còn / ổ mạng / UNC | Home (A3 D17) |
| Shell lỗi khi mở lại một pane | Gỡ pane khỏi cây; toast tổng hợp (D7) |
| Tất cả pane lỗi | Như lần đầu: A1 D11 mở một tab ở home + toast |
| Đĩa đầy / không ghi được | Giữ file cũ (rename không xảy ra); log loại lỗi; thử lại ở lần kế; không toast |
| Thư mục không đặt được 0700/0600 (macOS) | Không ghi nội dung terminal (bố cục vẫn ghi); log một lần |
| Cửa sổ thu nhỏ khi khôi phục | Như A3: tỉ lệ giữ, pane có thể dưới tối thiểu |
| Phiên điện thoại mở trong lúc khôi phục | Tab mới (A1); không lẫn vào cây đang dựng (A3 D5) |
| Người dùng đóng tab đang được khôi phục | Các pane còn lại của tab đó không mở nữa (huỷ theo tab) |
| Hai bản ShellX | Không thể (khoá một thể hiện A1) |
| Pane đang ở alt screen (vim) khi lưu | Lưu buffer chính bên dưới (D5) |
| Công tắc tắt khi đang lưu | Lần ghi đang chạy hoàn tất rồi xoá (D25 tuần tự) |

---

## 6. Kiểm thử

- **`restore/scrollback_codec_test.dart`** (thuần, `Terminal` xterm thật không UI): chữ thường; màu 16/256/truecolor chữ+nền; thuộc tính; nối dòng gói; ký tự rộng (CJK, emoji) không lặp; ô trống giữa dòng thành khoảng trắng; dòng trống cuối bị bỏ; alt screen → buffer chính; 2.000 dòng; 256 KiB không cắt giữa dòng; khứ hồi (mã hoá → ghi vào `Terminal` mới → mã hoá lại = như cũ); `sanitizeRestored` xoá OSC 52, OSC 0, CSI khác `m`, DCS, C1, BEL, giữ SGR hợp lệ và tiếng Việt; vạch D8 và thời gian D23 (vi/en, hôm nay/hôm qua/cũ hơn).
- **`restore/restore_snapshot_test.dart`:** khứ hồi JSON; mỗi loại hỏng của D11 → null; khoá lạ bỏ qua; `fromState` từ tab/workspace giả.
- **`restore/restore_store_test.dart`** (thư mục tạm): ghi nguyên tử (không còn `.tmp-*`), quyền 0600/0700 (macOS/Linux), file hỏng → `.bak`, nội dung > 512 KiB bị bỏ, dọn file mồ côi, hàng đợi tuần tự.
- **`restore/restore_persistence_test.dart`** (`fake_async`): debounce 1 s, chỉ ghi khi khác; 60 s chỉ pane bẩn; tắt công tắc xoá ngay; `flushAll(clean: true)`; đóng pane xoá file.
- **`terminal/terminal_tabs_restore_test.dart`** (`FakeLocalSessions`): thứ tự mở (tab chọn trước), `openCwds`, cây dựng lại đúng tỉ lệ/zoom/focus, nội dung + vạch đứng **trước** backlog trong buffer, không gì được `write` vào phiên (D8), pane lỗi bị gỡ + toast, tab rỗng bị bỏ, chọn lại tab, `SidebarWorkspaces.adopt`.
- **Widget:** dải đóng bất thường (hiện/đóng/đọc lên), submenu tray "Terminal".
- **Thử tay (HANDOFF §15):** macOS + Windows thật: ⌘Q/mở lại, khởi động lại máy không thoát app, `kill -9`, cwd ổ mạng, `ls --color`, vim đang mở lúc thoát, Time Machine exclusion (`tmutil isexcluded`), quyền file (`ls -l`), Windows `icacls`.

---

## 7. Ngoài phạm vi A5a

Giữ shell sống qua thoát/crash/cập nhật giao diện (**A5b**); chạy lại lệnh đang chạy; khôi phục lịch sử thông báo A4; nhiều cửa sổ; mã hoá file nội dung bằng khoá Keychain/DPAPI (follow-up nếu người dùng yêu cầu — hiện dựa vào quyền tệp như các app terminal khác); công tắc tắt hẳn khôi phục bố cục; đồng bộ bố cục giữa các máy; khôi phục trên điện thoại.


## Sửa đổi D18 (quyết định của controller, 2026-10-07)
Trên Windows, `WM_ENDSESSION` (wParam TRUE) **chờ tối đa 3 s** cho lần lưu `saveBeforeExit` trả lời (bơm thông điệp lồng nhau, có giới hạn), vì không chờ thì tiến trình có thể bị giết trước khi lưu xong. Với `ENDSESSION_CLOSEAPP` (Restart Manager), sau khi lưu xong ShellX tự thoát theo đường Thoát thường.
