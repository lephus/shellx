# A10 — Đợt chất lượng P0 (desktop + mobile) — Đặc tả thiết kế

- **Ngày:** 2026-10-07
- **Trạng thái:** Người dùng vắng mặt và giao toàn quyền quyết định sản phẩm cho người viết spec (như A1–A9). Phạm vi do người dùng nêu (ràng buộc): mục 3–13 của §5 trong `docs/superpowers/research/2026-10-07-cmux-gap-analysis.md`. D1–D41 do người viết spec chốt, ghi ở bảng §3 kèm cái giá nếu sai.
- **Lộ trình:** A1 → A2 → A4 → A3 → A5a → A5b (đang làm, nhánh `feat/desktop-a5b`) → A6 → A7 → A8 → A9 → **A10 (tài liệu này)**. A10 **không phụ thuộc** A5b: không sửa `main.dart`, `agent_side.dart`, `daemon_main.dart`, `src/mux/*`, `src/agent/*`.
- **Loại trừ có chủ đích:** mục 1–2 của §5 (gõ tiếng Việt/IME và chữ quá đậm) đang được sửa riêng ở nhánh `fix/desktop-font-ime`. Điểm giao nhau ghi ở D38.
- **Giữ nguyên:** spec A1 (D1–D16), A2, A3 (D1–D30, đặc biệt D13 "kích thước gửi phiên" và D18 "gộp chú ý"), A4, A5a (D8, D11, D12, D15), A5b, A7, A8 (D22 `paneReplacements`), A9 (D24 bảng phím, D25, D29), spec chia sẻ terminal, spec push, protocol điện thoại (`shellx_core` `AppMessage`), relay. A10 **thêm** và ghi rõ chỗ sửa ở D20, D24.
- **Ký hiệu:** "A1 D6" = quyết định D6 của spec A1; "D1" không tiền tố = của tài liệu này. "Pane" = một phiên trong tab (A3). "Pane SSH" = pane có `PaneSession.remote?.launch.host != null` (A8). "Thanh tìm" = thanh Tìm trong terminal (D3). Plan: `docs/superpowers/plans/2026-10-07-quality-p0-a10.md`.

---

## 1. Mục tiêu

Làm cho terminal **đáng tin trong công việc hằng ngày** như cmux: tìm chữ trong cuộc ra dài, bấm vào URL/đường dẫn, kéo-thả tệp hay dán ảnh vào một cuộc trò chuyện với agent, dán đoạn lớn không mất chữ, bàn phím luôn về đúng pane, kéo cửa sổ không làm TUI vẽ hỏng, thông báo luôn trỏ đúng pane, hai lần crash liền không mất bố cục, và trên điện thoại: sao chép chữ dễ, cuộc ra dày đặc không làm giật máy và bộ gõ không biến `--` thành `—`.

### Tiêu chí thành công (đo được)

1. **Tìm:** ⌘F (Windows Ctrl+Shift+F) trong pane có 10 000 dòng scrollback → thanh tìm hiện ở góc trên phải pane **không đổi lưới** (không có tin nào gửi tới PTY); gõ `error` → trong ≤ 100 ms đếm "1/37", mọi kết quả được tô, kết quả hiện tại (accent) cuộn vào giữa pane; Enter/⌘G → kết quả sau, ⇧Enter/⌘⇧G → trước, vòng quanh; Esc đóng, xoá tô, bàn phím về terminal. Có chọn một đoạn chữ một dòng trước ⌘F → ô tìm điền sẵn đoạn đó.
2. **Liên kết:** `echo https://example.com/a?b=1.` → rê chuột giữ ⌘ (Windows Ctrl) lên URL → gạch chân + con trỏ bàn tay; ⌘-click mở trình duyệt mặc định tới `https://example.com/a?b=1` (**không** có dấu chấm cuối). URL bị xuống dòng do cuộc ra hẹp vẫn là **một** liên kết. `printf '\e]8;;https://example.com\e\\bấm vào đây\e]8;;\e\\\n'` → "bấm vào đây" là liên kết; vì chữ hiển thị khác địa chỉ nên ⌘-click hỏi xác nhận trước khi mở. `ls src/main.dart:42` → ⌘-click `src/main.dart` (tồn tại, thư mục hiện tại của pane) hiện tệp trong Finder; pane SSH: URL mở được, đường dẫn không phải liên kết. Điện thoại: chạm vào URL → khay "Mở liên kết?" với "Mở"/"Sao chép liên kết".
3. **Thả tệp và dán ảnh:** kéo 2 tệp từ Finder vào pane zsh → pane viền accent + dòng gợi ý; thả → dòng lệnh có `/Users/me/My\ Docs/a.png /Users/me/b.txt ` (thoát chuẩn shell, **không** Enter). Chụp màn hình vào clipboard (⌘⌃⇧4) rồi ⌘V → dòng lệnh có đường dẫn tệp PNG tạm (0600, trong thư mục 0700) — Claude Code đọc được. Pane SSH: thả/dán ảnh → toast giải thích, **không** chèn gì. Dán chữ thường không đổi (chữ luôn thắng ảnh).
4. **Dán lớn:** dán 800 KB chữ vào pane `cat > /tmp/x` → `wc -c /tmp/x` = đủ 800 KB (**trước đây** hàng đợi ghi PTY 1 MiB làm rơi chữ âm thầm); UI không đứng > 100 ms; dán > 1 MiB hỏi xác nhận; > 16 MiB từ chối kèm toast; đóng tab/pane hoặc phiên thay mới giữa lúc dán → dừng sạch, không gửi thêm gì vào phiên đã chết; huỷ chủ động trên pane còn sống thì đóng dấu bracketed bằng `ESC[201~`.
5. **Focus:** các bất biến F1–F7 của D23 đều có test widget; sau khi đóng bảng lệnh, thanh tìm, hộp xác nhận, bảng thông báo, hộp SSH → phím gõ vào đúng pane trong ≤ 1 khung hình; cửa sổ được kích hoạt lại → bàn phím về terminal.
6. **Không có kích thước tạm tới PTY:** kéo mép cửa sổ trong 2 s (120 lần đổi lưới) → `ioctl TIOCSWINSZ`/`pty.resize` của pane chỉ chạy **một** lần, ≤ 150 ms sau khi ngừng kéo; kéo đường chia pane tương tự; gõ phím ngay sau khi đổi cỡ thì PTY nhận cỡ mới **trước** phím. Bên không lái (điện thoại ↔ desktop) không bao giờ đổi cỡ PTY (giữ A1 D6; test hồi quy ở cả hai phía).
7. **Thông báo (đã có, ghim bằng test):** thông báo đến lúc người dùng đang ở pane khác của cùng tab → vòng và dòng sidebar ở đúng pane gửi, nhãn dùng tên pane gửi; thông báo của tab nền cập nhật chấm/tiêu đề tab nền; pane SSH kết nối lại thì chấm chưa đọc của pane cũ bị bỏ (A8 M5, giữ nguyên). Không có thay đổi hành vi.
8. **Khôi phục:** `layout.json` có 4 tab → app chết (kill -9) hai lần liên tiếp, lần chạy thứ hai chết **trước** khi khôi phục xong → lần thứ ba vẫn thấy cả 4 tab; `layout.json` hỏng hoặc rỗng-không-sạch → khôi phục từ thế hệ trước (`layout.json.1`/`.2`) kèm dải A5a; cửa sổ lưu ở màn hình đã rút / to hơn màn hình / nằm ngoài ≥ 75 % → mở trong màn hình, vừa khít, không ngoài màn hình.
9. **Điện thoại:** "Xem dạng văn bản" mở khay cuộn chọn được toàn bộ ≤ 2 000 dòng cuối (kể cả scrollback) + "Sao chép tất cả"; ô soạn giọng nói không tự sửa, không đổi `--` thành `—`, không viết hoa đầu câu; 1 MiB cuộc ra từ tab A trong lúc gõ ở tab B: echo của B hiện ≤ 100 ms, khung hình dựng ≤ 32 ms ở 95 % khung; gõ một chuỗi có dấu bằng bộ gõ ảo/bàn phím cứng tới terminal **đúng một lần**.
10. **Riêng tư:** chạy tiêu chí 1–9 với log debug → log không chứa chữ terminal, từ khoá tìm, URL, đường dẫn, tên tệp, nội dung clipboard, chuỗi OSC 8 (`grep` các chuỗi thử nghiệm trên log trả rỗng).
11. **Không hồi quy:** mọi test A1–A9 xanh; phím tắt có sẵn không đổi (fixture vàng chỉ **thêm** dòng); một pane không đổi hành vi khi không dùng tính năng mới.

---

## 2. Kiểm tra hiện trạng (grep ngày 2026-10-07, trước khi quyết)

Bảng gap analysis có dòng đánh dấu (?) — dưới đây là kết quả kiểm lại bằng mã. Mục có HAVE bị **bỏ hoặc thu nhỏ**.

| Mục | Kết quả | Bằng chứng | Hệ quả cho A10 |
|---|---|---|---|
| 3 Tìm trong terminal | MISSING | không có `find`/`search` trong `lib/src/ui/terminal`; `kActionSpecs` không có `start_search` | Làm đủ (T4, T5) |
| 4 URL/đường dẫn desktop | MISSING | `url_opener.dart` chỉ mở https + `localhost:port`; `onPrivateOSC` không ai đặt | Làm (T1, T6, T7) |
| 4 OSC 8 | MISSING | xterm 4.0.0 chuyển OSC 8 vào `unknownOSC` → `onPrivateOSC`, không lưu theo ô | Tự theo dõi bằng neo ô (D11) |
| 4 chạm URL trên điện thoại | MISSING | `TerminalView` mobile không đặt `onTapUp` | Làm (T15) |
| 5 Thả tệp | MISSING | không có `desktop_drop`/`DropTarget` (kéo-thả chỉ ở sidebar) | Làm (T8, T9) |
| 5 Dán ảnh | MISSING | `_paste()` chỉ đọc `kTextPlain` | Làm (T8, T9) |
| 5 Tải lên pane SSH | MISSING, **không làm** | cần `scp` + thư mục từ xa + dọn dẹp | Tắt có thông báo (D17), follow-up A10.1 |
| 6 Dán bracketed | **HAVE** | `Terminal.paste` bọc `ESC[200~…ESC[201~` khi chương trình bật; `normalizePastedText` cắt mọi ESC/C0/C1 (cả hai chế độ) | **Bỏ** |
| 6 Dán chữ lớn | **BUG** | `PtyHandle.write` (flutter_pty đã vá) xếp hàng ≤ 1 MiB, **phần không vừa bị rơi**, chỉ log một lần; `_paste` gửi cả chuỗi một phát | Làm (T3) |
| 6 Đường nhanh HTML/RTF | N/A | Flutter chỉ đọc `text/plain`; không có đường chậm | **Bỏ** |
| 6 Cuộc đua huỷ/dán | PARTIAL | `_paste` bắt `selectedId` trước `await` nhưng lấy `tab.terminal` (pane focus) **sau** `await` | Làm (T3): bắt pane trước `await` |
| 7 Focus | PARTIAL | HAVE: pane ẩn không có `FocusNode` (`widget.selected && focused`), `_pointerDown` focus pane khi chia, `focusTerminal()` sau bảng thông báo. THIẾU: cửa sổ kích hoạt lại, test cho từng lớp phủ | Test + sửa nhỏ (T10) |
| 8 Kích thước tạm | **BUG** | `terminal.onResize` gọi `view.resize` ngay mỗi lần xterm đổi lưới (`terminal_tabs.dart` ~890) → mỗi khung hình kéo cửa sổ là một `pty.resize` | Làm (T2) |
| 8 Điện thoại/desktop | HAVE theo thiết kế | A1 D6 "bên vừa dùng thắng"; `_localResize` chỉ ghi nhận khi điện thoại lái; mobile debounce 150 ms | Giữ, thêm test hồi quy (T2, T13) |
| 9 Thông báo | **HAVE (bỏ)** | `tab_attention.dart` theo từng pane (`TabUnread.panes`, `AttentionEntry.paneId`, A3 D18), "đã thấy" = tab chọn + pane focus + cửa sổ hoạt động (A4 D7); tiêu đề tab nền cập nhật qua `SessionSummary`; ~45 test (`tab_attention_test`, `tab_attention_panes_test`). A8 M5 chủ ý bỏ chấm chưa đọc của pane cũ khi kết nối lại | **Bỏ**; chỉ thêm test N1 vào T10 để ghim |
| 10 Khôi phục | PARTIAL | HAVE: ghi nguyên tử (tạm + đổi tên), hỏng → `.bak`, dấu `cleanExit`, không ghi trước khi khôi phục xong (`_schedule` ở `finally`). THIẾU: thế hệ trước, bố cục rỗng-không-sạch, kẹp khung | Làm (T11, T12) |
| 11 Xem dạng văn bản | MISSING | chỉ có chọn bằng nhấn giữ + nút "Sao chép" | Làm (T14) |
| 12 Gom đầu ra | desktop **HAVE** (`TerminalFeed`), mobile MISSING | `TabOutput` → `terminal.write` ngay từng sự kiện | Làm cho mobile (T16) |
| 13 Ô soạn tự sửa | **BUG** | `voice_composer.dart` `TextField` không đặt `autocorrect`/`smartDashesType`… ; terminal view (xterm `CustomTextEdit`) **đã** tắt autocorrect/suggestions | Sửa ô soạn (T13) |
| 13 Gửi trùng | Chưa có test | HANDOFF: "IME VN / phím cứng gửi trùng" chưa kiểm | Test tự động (T13) + ⚠ tay |

---

## 3. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| D1 | Nền | `main` (A5b mới merge tới Task 6). A10 không đụng file A5b đang sửa (liệt kê ở đầu). Mỗi task gộp độc lập vào `main`; thứ tự trong plan chỉ là gợi ý (T1 trước T6/T15, T8 trước T9, T4 trước T5, T6 trước T7) | Xung đột nhỏ nếu A5b đổi `terminal_tabs.dart` — plan chỉ thêm, hạn chế sửa |
| D2 | Phạm vi | Mục 3–13 của §5; bảng §2 quyết **bỏ** (6 bracketed, 6 HTML/RTF, 9 phần "theo pane" đã có) và **thu nhỏ**. Không thêm phím/thiết lập mới nào ngoài D4 | — |
| D3 | Tìm — hành vi | Thanh tìm **theo pane** (pane đang focus), phủ lên góc trên phải pane (rộng 360, cao 36, `surface`, viền `border`), không đổi bố cục/lưới. Tìm **cả scrollback + màn hình** của pane (≤ 10 000 dòng). Không phân biệt hoa thường mặc định; nút "Aa" bật phân biệt. Không regex (tránh ReDoS, giá trị thấp). Kết quả không chồng nhau. Chữ chọn một dòng ≤ 200 ký tự điền sẵn khi mở (cmux). Đang mở mà có cuộc ra mới → tìm lại sau 150 ms (không cuộn lại trừ khi người dùng bấm tiếp). Đếm tối đa 1 000, hiện "1000+". Kết quả được chọn đầu tiên là kết quả **cuối cùng** (gần cuộc ra mới nhất); Enter đi xuống (vòng về đầu), ⇧Enter đi lên. Dòng bị xuống dòng (`isWrapped`) nối thành một dòng logic nên khớp qua mép | Regex/theo từ: A10.1 |
| D4 | Tìm — phím và lệnh | Hành động kiểu Ghostty: `start_search`, `navigate_search:next`, `navigate_search:previous`, `end_search` (không gán phím; Esc trong thanh đóng). Mặc định macOS: ⌘F, ⌘G, ⌘⇧G. Windows: Ctrl+Shift+F, Ctrl+Shift+G, Ctrl+Shift+Alt+G (Alt trái, A3 D20; **không** F3 trần — `mc`/`htop` dùng F3). Có trong bảng lệnh (A9 D26: `inPalette`), bảng phím tắt, menu chuột phải ("Tìm…"). Trong thanh: Enter/⇧Enter, ↑/↓ cũng chuyển kết quả | Windows người dùng quen F3: tự gán trong file cấu hình |
| D5 | Tìm — tô và cuộn | Tô bằng `TerminalController.highlight` của xterm (neo theo dòng nên bám khi cuộn): kết quả khác `accent` 25 % opacity, kết quả hiện tại `accent` 55 %. Cuộn bằng `RenderTerminal.getOffset` để đưa dòng khớp vào giữa khung nhìn (không giả định gì về `ScrollController`). Đóng thanh → `dispose` mọi tô và neo | Tô 1 000 đoạn mỗi khung hình: đo ở T4 (tiêu chí 8 ms) |
| D6 | Liên kết — URL | Phát hiện `https?://` (không phân biệt hoa thường) tới khoảng trắng/`<>"` ; cắt dấu câu cuối `.,;:!?'"` và `)`/`]`/`}` **không cân bằng** (URL Wikipedia có `)` trong tên vẫn đủ). Chỉ mở **http/https**. Không `file:`, `ssh:`, `mailto:`, `javascript:`, `x-apple…` (UrlOpener hiện chỉ cho https — thêm `openWebLink` riêng, **không nới** `open()`). Dài > 2 048 ký tự bỏ qua | `mailto:`/`ssh:` không bấm được (hiếm) |
| D7 | Liên kết — đường dẫn | Chỉ **pane cục bộ** (không SSH): tuyệt đối (`/…`, `~/…`, `C:\…`, `\\?\` bỏ), tương đối `./x`, `../x`, `dir/x.ext`; hậu tố `:dòng[:cột]` và `(dòng,cột)` được nhận ra rồi bỏ (không tích hợp trình soạn — A10.1). Tương đối giải theo `PaneSession.cwd` (OSC 7); không biết cwd → chỉ tuyệt đối. **Chỉ gạch chân khi tồn tại** (kiểm `FileSystemEntity.type` bất đồng bộ khi rê, nhớ 2 s, tối đa 1 lần/80 ms). Bấm = **hiện trong Finder** (`/usr/bin/open -R <tuyệt đối>`), Windows `explorer.exe /select,<đường>`; thư mục thì mở thư mục. **Không bao giờ thực thi** tệp; đường dẫn có ký tự điều khiển bị bỏ; sau khi giải luôn tuyệt đối (không bắt đầu bằng `-`) | Người dùng muốn mở trong VS Code: A10.1 |
| D8 | Liên kết — thao tác | ⌘-click (Windows Ctrl-click) mở; rê giữ phím đó → gạch chân + con trỏ `click` (không tooltip: terminal vẽ bằng canvas; mục menu chuột phải là chỗ nhắc). Bấm thường không đổi (chọn chữ). **Phát hiện khi thử:** `TerminalView.onTapUp` của xterm 4.0.0 **không bao giờ được gọi** (bộ nhận cử chỉ chỉ chuyển `onSingleTapUp`, `TerminalView` không đặt) nên click đọc từ một `Listener` ngoài đấu trường cử chỉ (chuột trái, nhả cách chỗ nhấn < `kTouchSlop`), cùng cách `_TapListener` của mobile Chương trình bật chế độ chuột vẫn nhận click; ⌘-click vừa gửi cho chương trình vừa mở liên kết (Listener không qua bộ lọc chuột của xterm) — chấp nhận. Chuột phải lên liên kết thêm hai mục đầu menu: "Mở liên kết", "Sao chép địa chỉ liên kết" | Mở nhầm khi dùng ⌘-click trong TUI chuột: hiếm |
| D9 | Liên kết — dòng logic | Lấy dòng logic quanh hàng được rê: lùi theo `isWrapped` tới đầu, tiến tới hết, tối đa 8 hàng vật lý (4 096 ký tự); lập bản đồ chỉ số → ô (ô rộng 2 chiếm một chỉ số, ô trống = khoảng trắng). Kết quả nhớ theo `(hàng đầu, phiên bản dòng)` — tính lại khi xterm đổi | URL > 8 hàng không bấm được |
| D10 | OSC 8 — an toàn | URI do chương trình (có thể từ máy chủ không tin cậy) → chỉ nhận **http/https**, ≤ 2 048 ký tự, không ký tự điều khiển. Khi **chữ hiển thị** của vùng liên kết không bằng/không bắt đầu bằng URI (so sánh host nếu chữ là URL) → hỏi xác nhận kèm URI đầy đủ (≤ 200 ký tự, rút gọn giữa) trước khi mở (chống đánh lừa). URL tự phát hiện (D6) mở thẳng | Xác nhận gây phiền cho `ls --hyperlink`: URI `file://` không thuộc phạm vi nên không hỏi, đơn giản không mở |
| D11 | OSC 8 — lưu | `DesktopTerminal` đặt `onPrivateOSC` chỉ cho mã `8`; mở (`params;uri` có uri) → neo ô tại con trỏ; đóng (uri rỗng) → neo cuối, ghi `HyperlinkRange`. Tối đa 2 000 vùng/pane, bỏ vùng có neo tách rời (dòng đã trôi khỏi scrollback). Mở mới khi chưa đóng → bỏ cái cũ. Chuỗi trên mạng/khôi phục: A5a đã cắt ESC nên văn bản khôi phục không tạo liên kết | Liên kết dài qua nhiều dòng bị cắt nếu xterm reflow đổi neo: chấp nhận |
| D12 | Liên kết — điện thoại | Chạm (không giữ, không kéo) vào URL → khay dưới "Mở liên kết?" (URL, "Mở", "Sao chép liên kết"); **không bao giờ** mở thẳng (chạm nhầm trong TUI là thường). Chỉ http/https. Dùng cùng bộ phát hiện `shellx_core` (T1); chạm đọc từ `_TapListener` (Listener) có sẵn vì `TerminalView.onTapUp` của xterm không bao giờ chạy (D8). Không đường dẫn, không OSC 8 ở A10 (xterm 4.0.0 không giữ theo ô; mobile chưa theo dõi) | OSC 8 trên điện thoại: A10.1 |
| D13 | Dán — đường ống | Một lớp `PasteSender` (desktop): ≤ 64 KiB → `terminal.paste` như cũ; 64 KiB–1 MiB → bọc bracketed một lần (nếu chương trình bật), gửi từng mảnh 32 KiB cách 8 ms (≈ 4 MB/s, hàng đợi PTY không bao giờ tràn); > 1 MiB → hỏi xác nhận rồi như trên; > 16 MiB → từ chối + toast. Hàng theo pane (dán thứ hai chờ). **Pane đích và id phiên bắt trước `await` clipboard**; mỗi mảnh kiểm pane còn sống/chưa thoát/cùng terminal (A8 thay phiên → dừng, không gửi gì thêm vào phiên đã chết); `PasteSender.cancel(key)` trên pane còn sống gửi `ESC[201~` nếu đã mở bracketed (chương trình không kẹt ở chế độ dán) — dùng khi thoát app Văn bản vẫn qua `normalizePastedText` (cắt ESC/C0/C1). Không cắt theo dòng (không đổi nội dung) | PTY chậm hơn 4 MB/s (shell bận): chữ vẫn xếp hàng ≤ 1 MiB; vượt thì rơi như cũ (log một lần) — nên xác nhận ở 1 MiB |
| D14 | Dán — cảnh báo nhiều dòng | **Không** làm (Ghostty `clipboard-paste-protection`): bracketed + cắt điều khiển đã chặn pastejacking; hộp hỏi mỗi lần dán nhiều dòng gây phiền hơn lợi. Ghi để người dùng đổi ý | Dán lệnh nhiều dòng vào shell không bracketed sẽ chạy ngay (như mọi terminal) |
| D15 | Ảnh/tệp trên clipboard | Thứ tự khi ⌘V: (1) **tệp** (Finder ⌘C) → đường dẫn thoát shell, cách nhau dấu cách + dấu cách cuối; (2) **chữ** không rỗng → như cũ; (3) **ảnh** → ghi `<tmp>/shellx-paste-<uid>/paste-<yyyyMMdd-HHmmss>-<8 hex>.<png|jpg|gif|bmp|tiff>` (đuôi theo byte đầu) rồi chèn đường dẫn thoát. Ảnh > 20 MiB → toast. Thư mục 0700, tệp 0600 (POSIX); mỗi lần lưu ảnh xoá tệp > 24 giờ và giữ ≤ 50 tệp (`PasteImageStore.deleteAll` có sẵn cho lần thoát, chưa nối). Không ghi log đường dẫn/kích thước chính xác. Gói `pasteboard` (macOS + Windows) | Ảnh vẫn nằm trên đĩa tới 24 giờ: ghi trong chính sách riêng tư (T17) |
| D16 | Kéo-thả | Gói `desktop_drop` bọc **mỗi pane**: thả = chèn đường dẫn thoát vào **pane đó** (focus pane đó), qua `PasteSender` (có bracketed → không chạy lệnh), không Enter. Khi rê: viền accent 2 px + nhãn "Thả để chèn đường dẫn" (`desktop_drop` không báo số tệp lúc rê nên không có dạng số nhiều); xoá khi rời, thả xong, cửa sổ mất focus, pane đóng (bài học cmux #14384). Pane đã thoát: không nhận. Thả lên sidebar/tab: không đổi (A2 kéo-sắp-xếp có sẵn; hai hệ thống không giao nhau) | `desktop_drop` ngừng bảo trì: bọc sau giao diện `DropSource` để thay |
| D17 | SSH | Pane SSH **không** nhận tệp/ảnh: nhãn khi rê "Không thể thả tệp vào phiên SSH", thả/dán ảnh → toast cùng ý. Lý do: tải lên cần `scp` qua ControlMaster (chỉ macOS), thư mục tạm trên máy chủ, dọn dẹp, mật khẩu không có master, rò rỉ dữ liệu sang máy khác ngoài ý người dùng. Dán **chữ** vào pane SSH không đổi. Pane tmux cục bộ: như pane cục bộ | Người dùng SSH vẫn phải scp tay: ghi rõ, A10.1 |
| D18 | Thoát tên tệp | Theo họ shell của pane (`PaneSession.shell` → posix/fish/powershell/cmd). posix & fish: thêm `\` trước mọi ký tự ASCII ngoài `[A-Za-z0-9_.,:/@%+=-]`; ký tự không-ASCII (chữ có dấu, CJK, emoji) **giữ nguyên** (UTF-8 an toàn): "Tệp ảnh.png" → `Tệp\ ảnh.png`; `~` chỉ thoát khi đứng ở đầu một tên không bắt đầu bằng `~/` (đường dẫn thả vào luôn tuyệt đối nên thực tế luôn thoát `~` ở đầu nếu có). powershell: tên chỉ gồm ký tự an toàn giữ nguyên, ngược lại bọc `'…'` (nhân đôi `'`); cmd: bọc `"…"`. Có ký tự điều khiển (< 0x20, 0x7F), NUL hay xuống dòng → từ chối cả lần thả + toast (không thoát nửa vời). Họ shell lạ trên Windows → powershell; trên macOS → posix | Shell lạ (nushell, xonsh) có thể hiểu `\` khác: rủi ro thấp |
| D19 | Phụ thuộc | Thêm vào `apps/desktop/pubspec.yaml`: `desktop_drop` và `pasteboard` (cả hai có plugin macOS + Windows, MIT/BSD). Ghim chính xác `desktop_drop: 0.8.4` và `pasteboard: 0.5.0` (đã đọc API trong `~/.pub-cache`: `DropTarget(onDragEntered/Exited/Done)`, `DropDoneDetails.files[].path`, `Pasteboard.files()`, `Pasteboard.image`); `flutter pub get` cập nhật `GeneratedPluginRegistrant.swift`, `generated_plugin_registrant.cc`, `generated_plugins.cmake` (commit) và `pod install` cập nhật `macos/Podfile.lock` (commit, cần Mac); không có gói nào cho Windows chạy được → T9 vẫn gộp, tính năng đó tắt trên Windows bằng cờ (⚠ tay). Quy tắc "không phụ thuộc mới" của A8 chỉ áp cho A8. Mobile: không thêm gì (đã có `url_launcher`) | Gói hỏng trên Windows: tắt từng tính năng |
| D20 | Kích thước tới PTY (sửa A3 D13) | Mỗi pane có **bộ ổn định kích thước**: xterm đổi lưới ngay (UI đúng), nhưng `view.resize` chỉ gọi sau **80 ms không đổi** (đuôi), hoặc ngay khi: (a) người dùng gõ vào pane (xả trước khi ghi phím), (b) pane đóng/thoát (huỷ), (c) tab/pane thành hiện (`_visibleChanged`: kích thước đã ổn, gửi ngay và huỷ hẹn). Lần mở pane (kích thước ban đầu) không qua bộ này. Không có "tối đa chờ" (kéo liên tục không gửi gì — đúng ý). `TerminalTabs.flushResizes()` công khai; thời gian chờ là `resizeSettleProvider` (mặc định 80 ms; harness test đặt 0 để các test bố cục cũ giữ nguyên) | TUI thấy đổi cỡ muộn 80 ms: không nhận ra |
| D21 | Điện thoại và desktop | **Giữ A1 D6** ("bên vừa dùng thắng", không "nhỏ nhất thắng" của tmux): người đang lái đặt cỡ PTY, bên kia chỉ ghi nhận; điện thoại gắn lại sau khi rớt kênh (`lastSeq > 0`) chỉ ghi nhận cỡ nếu desktop đang lái, như A1). Lý do: "nhỏ nhất thắng" làm cửa sổ desktop 200 cột bị kẹp 45 cột của điện thoại cả khi điện thoại chỉ xem; cmux iOS cũng không dùng. Bổ sung **test hồi quy**, không đổi hành vi | Điện thoại xem desktop đang lái thấy lưới lệch (đã có banner A1) |
| D22 | Điện thoại — kích thước | Không đổi mã: debounce 150 ms, `noteSizeIntent`, 1×1 và các quy tắc "máy tính đang lái" đã có đủ test trong `terminal_tab_controller_test.dart` (banner không gửi, một ý định một lần gửi, 1×1). Thêm **một** test: bàn phím trượt lên/xuống 5 lần trong 400 ms chỉ gửi một cỡ cuối | — |
| D23 | Bất biến focus | **F1** pane tab ẩn/Offstage dưới phóng to không bao giờ nhận `FocusNode` của terminal. **F2** đóng bất kỳ lớp phủ nào (bảng lệnh, thanh tìm, hộp xác nhận/SSH, bảng thông báo, bảng phím tắt, vấn đề cấu hình) → `primaryFocus` = terminal đang chọn (hoặc nút "Mở tab mới" khi rỗng). **F3** cửa sổ kích hoạt lại và `primaryFocus` null/ngoài trang → `focusTerminal()`. **F4** bấm pane không focus (tab chia) → pane đó focus **và** xterm vẫn nhận nhấn (bắt đầu chọn). **F5** bấm hàng sidebar → terminal focus ngay lần bấm đầu. **F6** lệnh CLI (`send`, `split` không `--focus`, `notify`) không đổi focus/chọn/cửa sổ — đã ghim bởi test A7 (`ui_command_handler_test` "split: … keeps focus and selection unless", "new tab: not selected by default", `ui_command_handler_ssh_test`). **F7** tab vừa mở lúc khởi động có focus không cần phím. Mỗi bất biến một test widget; chỗ nào đỏ thì sửa tối thiểu. Khi viết plan chạy thử: chỉ **F3** đỏ (cửa sổ kích hoạt lại, focus rơi về `FocusScopeNode` 'workspace') — sửa bằng một `ref.listen(windowFocusProvider)` trong trang; F1, F2, F4, F5, F7 đã đúng và được ghim | — |
| D24 | Thông báo (bỏ) | Không đổi A4/A3 D18/A8 M5. Mục 9 của gap analysis đã có đủ (bảng §2). Thêm đúng một test ghim (N1 trong `focus_invariants_test`): tiêu đề tab nền theo phiên, thông báo chưa đọc ghi đúng pane gửi khi tab khác đang chọn. Nhấp nháy vòng hai lần (cmux): **không** | — |
| D25 | Khôi phục — thế hệ | `layout.json` (hiện tại), `layout.json.1`, `layout.json.2` (thế hệ tốt trước). **Lúc nạp** (trước khi đánh dấu chưa sạch): nếu `layout.json` đọc được, có ≥ 1 tab và **khác** `.1` → xoay `.1 → .2`, chép `layout.json → .1` (tạm + đổi tên, 0600). Quy tắc chọn: (1) `layout.json` hợp lệ có ≥ 1 tab → dùng; (2) hợp lệ, **0 tab**, `cleanExit == false`, và `.1` có ≥ 1 tab → dùng `.1` (đóng hết tab rồi crash không xoá công việc; `cleanExit == true` rỗng thì **tôn trọng**); (3) hỏng/quá lớn → `.bak` như cũ rồi thử `.1`, `.2`. Dải A5a hiện như khi không sạch. `removeOrphans` giữ thêm khoá scrollback của các thế hệ (khôi phục từ thế hệ cũ có thể thiếu chữ cuộn — chấp nhận) | Dùng `.1` khi người dùng cố ý đóng hết rồi crash: khôi phục thừa, không mất dữ liệu |
| D26 | Khôi phục — hai crash liền | Đã an toàn nhờ `_schedule()` chỉ chạy ở `finally` sau khôi phục và nhờ D25: thêm test mô phỏng "chết giữa chừng" ở cả 3 điểm (sau nạp, giữa mở pane, sau ghi đầu) | — |
| D27 | Khung cửa sổ | `restorableBounds(saved, displays)`: màn hình chủ = màn hình chứa **tâm** khung, nếu không thì màn hình chứa **góc trên-trái + 24 px** (thanh tiêu đề vẫn với tới được), nếu không thì `null` (giữa màn hình mặc định, như A1 D9). Rồi **kẹp**: rộng/cao ≤ vùng hiển thị của màn hình chủ (`screen_retriever.visibleSize`, đã trừ thanh menu/Dock), và dời vào trong. Cửa sổ phóng to giữ cờ cũ. Không có danh sách màn hình → giữ `saved` | Màn hình ghép sai: cửa sổ giữa màn hình chính |
| D28 | Xem dạng văn bản | Nút `Icons.article_outlined` ("Xem dạng văn bản") cạnh "Aa" trên thanh chrome; mở **khay toàn chiều cao** (`DraggableScrollableSheet`, kéo xuống đóng) chứa `SelectableText` chữ JetBrains Mono 13, **ảnh chụp tĩnh** ≤ 2 000 dòng cuối của tab đang hoạt động (scrollback + màn hình; dòng xuống dòng nối lại; xoá khoảng trắng cuối dòng và dòng trống cuối; màn hình thay thế → chỉ màn hình), tối đa 200 000 ký tự (cắt đầu). Nút "Sao chép tất cả" (toast "Đã sao chép"), "Làm mới" (chụp lại), đóng. Rỗng → "Chưa có nội dung". Không đổi cỡ PTY (khay phủ lên, không đổi lưới thật: `MediaQuery` của terminal bị khay che nhưng terminal ở dưới giữ kích thước — kiểm bằng test `resize` không gọi) | Văn bản rất lớn làm `SelectableText` chậm: giới hạn ở trên |
| D29 | Gom đầu ra mobile | Port `TerminalFeed` desktop sang `features/terminal/domain/terminal_feed.dart` (sao chép có chủ đích, không gộp gói: hai app độc lập; ghi ở Review Focus) + thêm **ưu tiên**: tab hoạt động: ghi ngay chữ đầu sau lúc im lặng, rồi gộp ≤ 128 KiB/16 ms; **echo phím**: đầu ra tới trong 250 ms sau lần gõ của chính tab đó và ≤ 4 KiB → ghi ngay; tab không hoạt động: gộp theo tick 250 ms, ≤ 64 KiB/tick, giữ ≤ 2 MiB (cắt đầu ở đầu dòng khi vượt, như desktop), xả hết khi thành hoạt động. `session.reset` huỷ feed cũ. Không giảm fps theo mức bận (cmux 11 fps): ngân sách mỗi tick đã đủ; bỏ | Tab nền hiển thị trễ ≤ 250 ms khi chuyển tab: không nhận ra |
| D30 | Ô soạn và gõ | Ô `voice-text`: `autocorrect: false`, `enableSuggestions: false` **chỉ trên iOS** (trên Android giữ `true`: Gboard/Samsung có thể ngừng ghép Telex/VNI khi NO_SUGGESTIONS — rủi ro lớn hơn dải gợi ý), `enableIMEPersonalizedLearning: false`, `smartDashesType: disabled`, `smartQuotesType: disabled`, `textCapitalization: none`, `keyboardType: multiline`, `spellCheckConfiguration` bỏ. Test cấu hình `TextInputConfiguration` thực tế. Test "đúng một lần": `TestTextInput` đẩy chuỗi composing → commit (bộ gõ ảo) và phím cứng `KeyDownEvent` → `onOutput` nhận đúng một lần mỗi ký tự. **Phát hiện khi thử:** một bàn phím lặp lại trạng thái đặt lại (`'  '`) làm xterm gọi `textInput('')` → mobile gửi một tin nhập **rỗng**; `ShellxTerminal.textInput` nay bỏ qua văn bản rỗng Phần desktop của "gõ trùng" thuộc nhánh IME | Bộ gõ thật vẫn trùng: ⚠ tay (§9) |
| D31 | Riêng tư và log | §5. Tóm tắt: không bao giờ log chữ terminal, từ khoá tìm, URL, đường dẫn, tên tệp, clipboard, OSC 8, kích thước ảnh chính xác; log chỉ có loại sự kiện, `runtimeType`, đếm | — |
| D32 | Chuỗi | §4, EN + VI trong cả hai ARB desktop (`app_en.arb`, `app_vi.arb`, `flutter gen-l10n` đã commit) và mobile (`intl_en.arb`, `intl_vi.arb`, `intl_utils`) | — |
| D33 | Trợ năng | Thanh tìm: `Semantics(container, label: "Tìm trong terminal")`, ô có nhãn, bộ đếm là vùng sống (đọc "3 trên 17" khi đổi), nút có `tooltip`. Gợi ý thả: vùng sống `polite`. Liên kết: nội dung tooltip có sẵn nhưng terminal không là cây ngữ nghĩa — ghi rõ không hỗ trợ trình đọc màn hình cho liên kết (xterm vẽ canvas). Khay "Xem dạng văn bản": tiêu đề, nút, văn bản chọn được đọc bằng trình đọc màn hình (đây là **đường trợ năng** để đọc terminal) | — |
| D34 | Hiệu năng | Tìm 10 000 × 200 ký tự ≤ 50 ms (`indexOf` trên chuỗi nối, không tạo `String` mỗi ô quá một lần/dòng); phát hiện liên kết khi rê ≤ 1 ms nhờ nhớ theo dòng; bộ ổn định kích thước O(1). Mỗi mốc có test thời gian **lỏng** (≤ 5× ngân sách, để CI không chập chờn) | — |
| D35 | Thứ tự gộp | Mỗi task gộp riêng; không task nào để lại nửa tính năng: T4 (động cơ tìm) không hiện gì; T5 mới hiện thanh tìm + phím; T6 không hiện gì; T7 hiện liên kết; T8 không hiện gì; T9 hiện thả/dán ảnh. Chuỗi ARB thêm cùng task dùng nó | — |
| D36 | Bỏ/hoãn (ghi tên) | Tải lên SSH bằng scp (A10.1); regex/theo từ khi tìm; tích hợp trình soạn cho `path:line`; tìm trong mọi terminal (§5 #16); copy mode; cảnh báo dán nhiều dòng (D14); nhỏ-nhất-thắng (D21); giảm fps (D29); nhấp nháy vòng 2 lần (D24); OSC 8 trên mobile; ghi chú dòng/cột khi mở | — |
| D37 | Phụ thuộc giữa task | `shellx_core` (T1) thêm `terminal_links.dart` thuần Dart (không xterm) dùng cho desktop (T6) và mobile (T15). Phần lấy dòng logic từ `Buffer` của xterm được viết **hai lần** (desktop `terminal_buffer_text.dart`, mobile `buffer_text.dart`): hai app ghim cùng xterm 4.0.0 và không chia sẻ gói có xterm | Hai bản lệch nhau: test chung vector trong `shellx_core` kiểm phần thuần |
| D38 | Giao với nhánh `fix/desktop-font-ime` | (a) IME có thể vá `CustomTextEdit` (xterm vendor/lớp bọc): A10 chỉ dùng API công khai của `Terminal`/`TerminalController`/`TerminalView` (`highlight`, `onPrivateOSC`, `onTapUp`, `controller`), không đụng nội bộ nhập liệu. (b) Thanh tìm là một `TextField` Flutter **cùng cửa sổ** với terminal: khi nó focus, kết nối nhập của terminal đóng (đúng); khi đóng thanh phải `requestFocus` terminal — nếu nhánh IME thêm "mở lại kết nối khi `connectionClosed`" thì hợp, nếu không thì T10 F2 đã ép. (c) Cả hai nhánh có thể sửa `pane_tree_view.dart`/`terminal_pane.dart`: A10 chỉ **thêm** widget bọc quanh `PaneTerminal` và tham số mới, không đổi `TerminalView(...)` đang có (trừ thêm `onTapUp`, `mouseCursor`, `key`) nên xung đột là cơ học. (d) Font: A10 không đổi `terminal_style.dart`; số ô/hàng dùng `measureTerminalCell` nên đổi font không ảnh hưởng tìm/liên kết. (e) Test "gõ đúng một lần" desktop thuộc nhánh IME | Xung đột gộp: giải tay |
| D39 | Dữ liệu phiên bản | Không thay đổi định dạng `layout.json` (thế hệ chỉ là bản sao tệp), không thay đổi protocol, relay, `SettingKeys` (không thiết lập mới) | — |
| D40 | Trạng thái chặn | Ba chỗ cần máy thật (⚠ §9): `pasteboard` đọc ảnh/tệp trên Windows, `desktop_drop` thả từ Explorer/Finder, kiểm khung cửa sổ khi rút màn hình. Executor ghi "pending manual" vào ledger và tiếp tục; **nhánh không gộp cho tới khi các mục ⚠ của task đó ghi "passed"** (như A8) | — |
| D41 | Không có thiết kế UI riêng | A10 không có file `design/…-a10.md`; kích thước, màu, hành vi thanh tìm/gợi ý thả/khay nằm ở §4 và trong từng task (dùng token có sẵn `ShellxDesktopColors`, `ShellxSpace`, `ShellxText`) | — |

---

## 4. Giao diện và chuỗi (EN + VI)

### 4.1 Thanh tìm (desktop, góc trên phải của pane, trên đầu terminal, dưới vòng chú ý và nhãn driver)

`Row`: ô nhập (`ShellxText.body`, placeholder), bộ đếm (`caption`, `textSecondary`, tabular), nút `Aa` (bật = `primarySoft` nền + `accent` chữ), ▲, ▼, ✕ (mỗi nút 24×24, tooltip kèm phím). Nền `surface`, viền `border` 1 px, bo `r8`, bóng nhẹ như menu. Khi không có kết quả: bộ đếm `err`. Không tự đóng. Thu hẹp: pane < 400 px → ô nhập co, ẩn nhãn "Aa" thành biểu tượng.

| Khoá ARB | EN | VI |
|---|---|---|
| `findPlaceholder` | Find | Tìm |
| `findLabel` | Find in terminal | Tìm trong terminal |
| `findCount` | {current} of {total} | {current}/{total} |
| `findCountCapped` | {current} of {total}+ | {current}/{total}+ |
| `findNoMatches` | No matches | Không có kết quả |
| `findPrevious` | Previous match | Kết quả trước |
| `findNext` | Next match | Kết quả sau |
| `findMatchCase` | Match case | Phân biệt hoa thường |
| `findClose` | Close find | Đóng tìm kiếm |
| `findMenuItem` | Find… | Tìm… |
| `actionStartSearch` | Find in terminal | Tìm trong terminal |
| `actionSearchNext` | Find next | Tìm kết quả sau |
| `actionSearchPrevious` | Find previous | Tìm kết quả trước |
| `actionEndSearch` | Close find | Đóng tìm kiếm |

### 4.2 Liên kết

| Khoá | EN | VI |
|---|---|---|
| `linkOpenHintMac` | ⌘-click to open | Nhấn ⌘ và bấm để mở |
| `linkOpenHintWin` | Ctrl-click to open | Nhấn Ctrl và bấm để mở |
| `linkRevealHintMac` | ⌘-click to show in Finder | Nhấn ⌘ và bấm để hiện trong Finder |
| `linkRevealHintWin` | Ctrl-click to show in Explorer | Nhấn Ctrl và bấm để hiện trong Explorer |
| `linkConfirmTitle` | Open this link? | Mở liên kết này? |
| `linkConfirmBody` | The text shown is not this address:\n{url} | Chữ hiển thị không phải địa chỉ này:\n{url} |
| `linkConfirmAction` | Open | Mở |
| `linkOpenFailed` | Couldn’t open the link | Không mở được liên kết |
| `menuOpenLink` | Open link | Mở liên kết |
| `menuCopyLink` | Copy link address | Sao chép địa chỉ liên kết |
| `menuRevealFile` | Show in Finder | Hiện trong Finder |
| `menuRevealFileWin` | Show in Explorer | Hiện trong Explorer |

### 4.3 Dán, thả tệp, ảnh

| Khoá | EN | VI |
|---|---|---|
| `pasteLargeTitle` | Paste {size}? | Dán {size}? |
| `pasteLargeBody` | This is a lot of text. It is sent a piece at a time and can’t be undone. | Đây là lượng văn bản lớn. Chữ được gửi từng phần và không thể hoàn tác. |
| `pasteLargeAction` | Paste | Dán |
| `pasteTooLarge` | The clipboard is too large to paste (over 16 MB) | Nội dung clipboard quá lớn để dán (hơn 16 MB) |
| `pasteImageTooLarge` | The image is larger than 20 MB | Ảnh lớn hơn 20 MB |
| `pasteImageFailed` | Couldn’t read the image from the clipboard | Không đọc được ảnh từ clipboard |
| `pasteImageSsh` | Images can’t be pasted into an SSH session | Không thể dán ảnh vào phiên SSH |
| `dropHint` | Drop to insert the path | Thả để chèn đường dẫn |
| `dropHintSsh` | Files can’t be dropped into an SSH session | Không thể thả tệp vào phiên SSH |
| `dropRefused` | A file name has characters a shell can’t take safely | Tên tệp có ký tự mà shell không nhận an toàn |
| `dropSsh` | Files can’t be dropped into an SSH session. Use scp. | Không thể thả tệp vào phiên SSH. Hãy dùng scp. |

### 4.4 Mobile

| Khoá | EN | VI |
|---|---|---|
| `viewAsTextTooltip` | View as text | Xem dạng văn bản |
| `viewAsTextTitle` | Terminal text | Văn bản terminal |
| `viewAsTextCopyAll` | Copy all | Sao chép tất cả |
| `viewAsTextRefresh` | Refresh | Làm mới |
| `viewAsTextEmpty` | Nothing to show yet | Chưa có nội dung |
| `viewAsTextTruncated` | Showing the last {lines} lines | Hiển thị {lines} dòng cuối |
| `linkSheetTitle` | Open link? | Mở liên kết? |
| `linkSheetOpen` | Open | Mở |
| `linkSheetCopy` | Copy link | Sao chép liên kết |
| `linkOpenFailed` | Couldn’t open the link | Không mở được liên kết |

(`copied` / `actionClose` có sẵn được dùng lại.) Dung lượng hiển thị `{size}` do hàm `formatBytes` (KB/MB, một chữ số thập phân, dấu thập phân theo locale).

---

## 5. Riêng tư và log

- **Không bao giờ log** (kể cả `debugPrint`, kể cả khi `kDebugMode`): chữ trong buffer, từ khoá tìm, số kết quả của một từ khoá, URL, URI OSC 8, đường dẫn (kể cả tạm), tên tệp, nội dung/kích thước chính xác của clipboard hay ảnh, văn bản trong khay "Xem dạng văn bản", pane đích kèm đường dẫn. Cho phép: loại sự kiện (`paste_chunked`, `drop_refused`, `image_paste_failed`), `runtimeType` của lỗi, mã thoát, **số** (số mảnh, số tệp), kích thước làm tròn lên luỹ thừa 2 (`<=1MiB`).
- `toString()` của `SearchQuery`, `LinkMatch`, `HyperlinkRange`, `DroppedPaths`, `PasteJob` trả `'…'`.
- Tệp ảnh tạm: 0600 trong thư mục 0700 (POSIX); dọn > 24 giờ và > 50 tệp; không đưa vào backup (`/tmp`-kiểu thư mục hệ thống `Directory.systemTemp`); không đồng bộ lên điện thoại.
- Thế hệ `layout.json.1/.2`: cùng quyền và vị trí với `layout.json` (A5a §5), không thêm nội dung (là bản sao).
- Clipboard chỉ đọc khi người dùng thực hiện hành động dán (phím/menu); không đọc nền; mobile cũng vậy.
- Chính sách riêng tư (`web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`) thêm một câu ở T17: ảnh dán vào terminal được lưu tạm trên máy tính tối đa 24 giờ rồi xoá, không gửi đi đâu.

## 6. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Tìm khi buffer rỗng / từ khoá rỗng | 0 kết quả, không tô, bộ đếm trống (không "Không có kết quả") |
| Từ khoá chứa tab/xuống dòng | Dán vào ô: xuống dòng bỏ, tab giữ; dài > 200 ký tự cắt |
| Pane đóng khi thanh tìm mở | Huỷ tô, đóng thanh, focus về terminal đang chọn |
| Tab chuyển khi thanh tìm mở | Thanh theo pane: tab khác không thấy; quay lại vẫn mở. Tối đa một thanh mở/pane |
| Tìm trong màn hình thay thế (vim) | Chỉ màn hình thay thế (buffer đang dùng) |
| URL ngay mép trái/phải, ô rộng 2, emoji | Bản đồ chỉ số→ô đúng; test CJK/emoji |
| Rê chuột lên ô sau hàng cuối | Không liên kết |
| `open`/`explorer` lỗi | Toast `linkOpenFailed`; không log đường dẫn |
| Đường dẫn là liên kết tượng trưng | Kiểm bằng `FileSystemEntity.type(followLinks: true)`; hiện chính đường dẫn đã giải |
| OSC 8 URI giả mạo (`javascript:`, quá dài) | Bỏ, không tạo vùng |
| Dán khi pane thoát | Bỏ (A1 UI §2.6: Enter đóng pane — dán không được kích) |
| Thả tệp có tên chứa `\n` | Từ chối cả lần thả + toast `dropRefused` |
| Thả thư mục | Chèn đường dẫn thư mục |
| Thả nhiều tệp > 64 KiB tổng | Qua `PasteSender` như dán |
| Clipboard ảnh + chữ (trình duyệt "Sao chép ảnh") | Chữ không rỗng thắng; chỉ ảnh mới tạo tệp |
| Đĩa đầy khi ghi ảnh | Toast `pasteImageFailed`; dọn tệp lỗi |
| Hai lần crash liền | D25/D26 |
| `layout.json.1` hỏng | Bỏ qua, thử `.2`, rồi rỗng |
| Khung lưu có kích thước 0/âm | `read()` trả null (đã có) |
| Mobile: khay "Xem dạng văn bản" khi tab kết thúc | Vẫn mở (đọc buffer còn lại) |
| Mobile: đầu ra tràn 2 MiB ở tab nền | Cắt đầu ở đầu dòng; `dropped++` (không log) |

## 7. Kiểm thử

- **`shellx_core` (dart test):** `terminal_links_test` (URL: dấu câu cuối, ngoặc cân bằng, `?a=b&c`, IPv6 host, unicode, độ dài; đường dẫn: tuyệt đối/tương đối/`~`/Windows/`:12:3`/`(12,3)`/khoảng trắng không nhận; xác thực URI OSC 8: scheme, điều khiển, độ dài).
- **Desktop thuần:** `terminal_search_test`, `find_session_test` (tô, neo, đóng không để lại gì), `terminal_buffer_text`/`hyperlink_registry_test` (OSC 8 và dòng logic), `link_finder_test`, `link_resolver_test`, `shell_escape_test`, `paste_sender_test` (`fake_async`), `paste_image_store_test` (thư mục tạm thật), `resize_settler_test` (`fake_async`), `url_opener_web_link_test`, `window_bounds_test` mở rộng, `restore_store_rotation_test` (thư mục tạm thật).
- **Desktop widget:** `find_bar_test`, `pane_find_test`, `link_layer_test`, `paste_flow_test`, `drop_and_image_test`, `focus_invariants_test`, `focus_dialogs_test`, `shortcut_golden_test` (thêm `a10Additions`).
- **Desktop tích hợp thật:** `pty_paste_test` (`@TestOn('mac-os')`, `@Tags(['pty'])`): dán 800 KB vào `cat > tmp` qua `SessionManager` thật, so `wc -c`.
- **Agent:** không đổi mã. Hồi quy "bên không lái chỉ ghi nhận cỡ" đã có ở `local_sessions_test.dart` ("…a later resize does" quanh dòng 178) và mobile `terminal_tab_controller_test` (nhóm desktop terminal: banner, `noteSizeIntent`).
- **Mobile:** `terminal_output_feed_test` (`fake_async`), `buffer_text_test`, `terminal_links_test`, `terminal_input_once_test` (`TestTextInput`), và thêm vào `terminal_page_test` (composer, "A10 D12" chạm URL, "A10 D28" xem dạng văn bản) và `terminal_tab_controller_test` (D22, D29).
- **Thử tay (⚠ MANUAL):** §9.

## 8. Review Focus

1. **Một đường dẫn/URL độc đi vào `open`, `explorer` hay shell** — OSC 8 `javascript:`, URL có `\n`, tên tệp `$(rm -rf ~)`, `-rf`, `;` — phải bị từ chối hoặc thoát; `UrlOpener.open` **không** được nới (T7 thêm hàm riêng). Ghim: `terminal_links_test`, `link_resolver_test`, `shell_escape_test`, `url_opener_web_link_test`.
2. **Dán vẫn rơi chữ hoặc kẹt chế độ bracketed** — huỷ giữa chừng, pane thay id, shell không đọc, hai lần dán đồng thời, văn bản chứa `ESC[201~`. Ghim: `paste_sender_test`, `pty_paste_test`.
3. **Bộ ổn định kích thước làm lệch lưới** — PTY nhận cỡ cũ khi phím tới, TUI vẽ vào lưới sai sau khi tab đổi, pane thoát còn hẹn giờ. Ghim: `resize_settler_test`, `terminal_tabs_resize_test`, bộ `terminal_tabs_panes_test` hiện có (các `expect(resizes…)` thêm `flushResizes()`).
4. **Thanh tìm lấy focus rồi không trả** hoặc **làm đổi lưới** — Ghim: `pane_find_test` ("closing returns focus", "the grid never changes"), `focus_invariants_test`.
5. **Tô tìm kiếm rò rỉ** — neo/highlight không dispose khi đóng/đổi từ khoá/đóng pane (rò bộ nhớ và vẽ chậm dần). Ghim: `terminal_search_test` "dispose leaves no highlight and no anchor".
6. **Khôi phục từ thế hệ cũ ghi đè công việc mới** — chọn `.1` khi `layout.json` rỗng-**sạch** là sai. Ghim: `restore_store_rotation_test` hai nhánh sạch/không sạch; quy tắc chọn ở một hàm thuần.
7. **Mobile: gom đầu ra làm mất/đảo dòng, trễ echo, hoặc rò feed sau `session.reset`/đóng tab** — Ghim: `terminal_feed_test` (UTF-8 qua mảnh, cắt giữa cặp thay thế, tràn), `terminal_output_priority_test`, bộ `terminal_tab_controller_test` hiện có.
8. **Sao chép có chủ đích hai nơi** (`TerminalFeed`, lấy dòng logic) lệch nhau — mỗi nơi có test riêng; vector chung của phần thuần ở `shellx_core`.
9. **Riêng tư** — test log: chạy luồng tìm/liên kết/dán/thả với `debugPrint` bị bắt, khẳng định không chứa chuỗi thử nghiệm.
10. **Giao với nhánh IME** (D38) — sau khi nhánh đó gộp, chạy lại `pane_find_test` và `focus_invariants_test`.

## 9. ⚠ Kiểm tay (chỉ người ngồi trước Mac/điện thoại/Windows làm được)

Executor ghi từng mục "pending manual" vào ledger `## A10 — execution`; **nhánh không gộp cho tới khi mọi mục dưới đây của task liên quan đã passed** (D40).

**Mac (macOS 13+, màn hình Retina, thêm một màn hình ngoài nếu có):**
- ⚠ T5: ⌘F trong cuộc ra dài (`seq 1 20000`) mượt, ⌘G/⌘⇧G đúng, tô thấy rõ trên cả hai theme (tối/sáng A9), VoiceOver đọc bộ đếm. Gõ tiếng Việt (Telex) **vào ô tìm** ra đúng chữ có dấu (ô tìm là TextField Flutter, đi đường IME khác terminal; chạy sau khi nhánh IME gộp).
- ⚠ T7: ⌘-click URL/đường dẫn thật mở Safari/Chrome mặc định và Finder; rê giữ ⌘ gạch chân đúng vị trí ở cỡ chữ khác nhau (⌘+/⌘−), ở màn hình Retina và không-Retina; `ls --hyperlink=auto` (GNU coreutils) và `gh`/`cargo` cho OSC 8 thật; hộp xác nhận hiện khi chữ ≠ URI.
- ⚠ T9: kéo tệp/thư mục từ Finder, từ Desktop, từ Mail/Safari (kéo ảnh), tên có dấu cách/tiếng Việt/emoji vào pane zsh, bash, fish; chụp màn hình ⌘⌃⇧4 → ⌘V; ảnh "Copy Image" từ Safari; Finder ⌘C tệp → ⌘V; pane SSH hiện nhãn từ chối; `pasteboard` yêu cầu quyền? (macOS 15+ có thể hỏi quyền "Paste from Other Apps": ghi lại).
- ⚠ T3: dán 800 KB, 5 MB (hỏi xác nhận), 20 MB (từ chối) vào `cat > /tmp/x`, vào `vim` (bracketed), vào `claude`.
- ⚠ T2: kéo mép cửa sổ chậm/nhanh trong `vim`, `htop`, `claude` — không có dòng vẽ hỏng sau khi thả; kéo đường chia pane.
- ⚠ T10: chuyển Cmd-Tab ra vào app, Mission Control, khoá màn hình/mở: bàn phím luôn về terminal; Stage Manager.
- ⚠ T12: rút màn hình ngoài khi app đóng (cửa sổ lưu ở màn đó), mở lại; chạy với màn hình thu nhỏ độ phân giải; cửa sổ to hơn màn hình (kéo cửa sổ rồi đổi độ phân giải).
- ⚠ T11: `kill -9` app hai lần liền, lần hai ngay sau khi cửa sổ hiện; bố cục còn nguyên lần ba.

**Windows 10 1809+/11:**
- ⚠ T9: kéo tệp từ Explorer vào pane PowerShell/cmd (tên có dấu cách, tiếng Việt); ảnh từ Snipping Tool (Win+Shift+S) rồi Ctrl+Shift+V (đuôi BMP/PNG đúng; nếu `pasteboard` không đọc được → tính năng tắt, toast); Explorer ⌘C-tương-đương Ctrl+C tệp → dán.
- ⚠ T7: Ctrl-click URL/đường dẫn (`C:\Users\…`, `explorer /select`).
- ⚠ T5/T3/T2/T10 như trên với Ctrl+Shift.

**iPhone / Android thật (qua máy tính thật):**
- ⚠ T13: bàn phím ảo tiếng Việt (Telex/VNI) và Gboard gõ **thẳng vào terminal** — mỗi ký tự đúng một lần; bàn phím cứng Bluetooth gõ có dấu; ô soạn giọng nói gõ `--help` ra `--help` (iOS không đổi thành `—`), không viết hoa đầu câu, không gợi ý tự sửa; Android Gboard không gạch đỏ chính tả.
- ⚠ T14: khay "Xem dạng văn bản" chọn một đoạn bằng kéo tay cầm, VoiceOver/TalkBack đọc nội dung; xoay ngang; bàn phím mở; 2 000 dòng cuộn mượt.
- ⚠ T15: chạm URL trong `claude`/`git push` (ra URL PR) → khay → Mở trong trình duyệt.
- ⚠ T16: trên máy tính chạy `yes | head -c 50M` ở tab A rồi chuyển sang tab B gõ: echo B ngay; quay lại A không giật quá; đo bằng mắt + Flutter DevTools nếu có (≤ 32 ms/khung hình ở 95 %).
- ⚠ HANDOFF §3 mục "IME tiếng Việt / phím cứng gửi trùng" đóng bằng T13 + mục trên.

## 10. Ngoài phạm vi A10

A10.1 (follow-up): tải tệp/ảnh lên pane SSH bằng `scp` qua ControlMaster (macOS) kèm thư mục tạm từ xa và dọn dẹp; tìm regex/theo từ; mở `path:line` trong trình soạn; OSC 8 và đường dẫn trên mobile; copy mode; tìm trong mọi terminal. Còn lại của §5: mục 1–2 (nhánh `fix/desktop-font-ime`), 14–40 (P1/P2).
