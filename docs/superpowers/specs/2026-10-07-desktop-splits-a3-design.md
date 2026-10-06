# A3 — Chia pane (split) trên desktop — Đặc tả thiết kế

- **Ngày:** 2026-10-07
- **Trạng thái:** Người dùng giao toàn quyền cho controller (như A1, A2, A4). Quyết định P1–P9 do controller chốt (ràng buộc); D1–D30 do người viết spec chốt trong phạm vi P1–P9. Tất cả ghi ở bảng §2 kèm cái giá nếu sai.
- **Lộ trình:** A1 (cửa sổ terminal) → A2 (sidebar giàu thông tin) → A4 (thông báo kiểu cmux) → **A3 (tài liệu này)** → A5 khôi phục session + daemon → A6 trình duyệt nhúng → A7 CLI/socket → A8 SSH/tmux → A9 skills, phím tắt tuỳ biến, file cấu hình.
- **Thứ tự thực thi:** A3 **chạy sau khi A4 đã merge vào `main`**. Phần gộp thông báo theo pane (§3.4, D18) sửa trực tiếp `TabAttention` của A4; các phần khác cũng chạm những file A4 sửa (`terminal_tabs.dart`, `terminal_pane.dart`, `terminal_shortcuts.dart`, `session_tab_row.dart`, `session_sidebar.dart`), nên không làm song song với A4.
- **Tài liệu đi kèm:** UI addendum `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a3.md` (đo đạc, token, wireframe, chuỗi; ràng buộc cho phần nhìn); plan `docs/superpowers/plans/2026-10-07-desktop-splits-a3.md`.
- **Giữ nguyên:** spec A1 (D1–D16), A2 (C1–C8, D1–D19), A4 (N1–N9, D1–D27). Tài liệu này chỉ **thêm** và ghi rõ chỗ nào sửa.
- **Ký hiệu:** "A1 D6" = quyết định D6 của spec A1; "A4 D10" = của spec A4; "P1"/"D1" không tiền tố = của tài liệu này.

---

## 1. Mục tiêu

Một tab trong sidebar chứa **nhiều terminal cạnh nhau**, như cmux/iTerm2/Windows Terminal: chia phải (⌘D), chia xuống (⌘⇧D), di chuyển focus giữa các pane bằng phím mũi tên, kéo đường chia để đổi tỉ lệ, phóng to một pane, đóng từng pane. Mỗi pane là **một phiên shell** của agent như mọi tab A1, nên điện thoại vẫn thấy từng pane là một phiên riêng. Tab chỉ có một pane trông và hoạt động **giống hệt A2/A4**.

### Tiêu chí thành công (đo được)

1. **Chia phải:** tab có một pane ở `~/work/shellx` (OSC 7 của A2) → ⌘D (Windows Ctrl+Shift+D) → trong ≤ 1 s tab có hai pane cạnh nhau, tỉ lệ 50/50, pane mới bên phải có focus, prompt ở `~/work/shellx` (`pwd` in đúng). Pane không có cwd (shell không hook) → pane mới ở home.
2. **Chia xuống:** ⌘⇧D (Windows Ctrl+Shift+Alt+D) → pane mới bên dưới pane đang focus, cùng quy tắc cwd.
3. **Kích thước từng pane:** sau khi chia, `tput cols; tput lines` trong mỗi pane in đúng lưới của chính pane đó (không phải của cả vùng); kéo đường chia → hai pane đổi cỡ, mỗi phiên nhận cỡ mới của mình trong ≤ 1 khung hình sau khi thả (trong lúc kéo: mỗi khung hình tối đa một `resize` mỗi phiên). `vim`, `htop` vẽ lại đúng.
4. **Focus:** bấm vào một pane → pane đó nhận bàn phím, viền focus `accent` chuyển sang nó; ⌘⌥←/→/↑/↓ (Windows Ctrl+Alt+mũi tên) chuyển focus theo hình học; không có pane theo hướng đó → không gì xảy ra. Tiêu đề dòng sidebar và tiêu đề cửa sổ theo pane đang focus.
5. **Đóng pane:** ⌘W (Windows Ctrl+Shift+W) đóng pane đang focus; pane anh em chiếm chỗ; focus về pane được dùng gần nhất. Pane đang chạy lệnh (OSC 133;C chưa D) → hỏi xác nhận như A1 D15. Pane cuối → đóng tab như A1. `exit` trong một pane (mã 0) → pane biến mất; mã ≠ 0 → pane giữ dòng "[Tiến trình đã thoát, mã N] — Enter để đóng", Enter đóng **pane đó**.
6. **Phóng to:** ⌘⇧↩ (Windows Ctrl+Shift+Enter) → pane đang focus chiếm cả vùng terminal, các pane khác ẩn nhưng **vẫn chạy** (output vẫn ghi vào buffer); đầu pane hiện "Phóng to · 2/3"; ⌘⇧↩ lần nữa → về bố cục cũ, đúng tỉ lệ cũ.
7. **Cân bằng và đổi cỡ bằng phím:** ⌘⌃= (Windows Ctrl+Shift+Alt+=) → mọi pane cùng hướng chia đều nhau (ba cột → 1/3 mỗi cột); ⌘⌃←/→/↑/↓ (Windows Ctrl+Shift+Alt+mũi tên) dời đường chia gần nhất 5 % theo hướng mũi tên; không pane nào nhỏ hơn 20 cột × 5 dòng.
8. **Menu:** chuột phải trong terminal có "Chia sang phải", "Chia xuống dưới", "Phóng to pane"/"Bỏ phóng to", "Cân bằng pane", "Đóng pane" (ba mục cuối chỉ khi có > 1 pane); menu dòng sidebar có "Chia sang phải", "Chia xuống dưới", "Cân bằng pane".
9. **Sidebar:** dòng của tab có ≥ 2 pane hiện dấu số pane (biểu tượng + chữ số); tiêu đề, dòng ngữ cảnh A2, chấm trạng thái theo pane đang focus. ⌘1–9, ⌃Tab, kéo thả workspace không đổi (tab là đơn vị).
10. **Thông báo (A4) gộp theo pane:** pane không focus của tab đang chọn phát `printf '\e]9;xong\a'` → badge dòng `1`, **vòng sáng chỉ quanh pane đó**; bấm vào pane đó và ở lại 1 s (cửa sổ focus) → badge và vòng tắt. Hai pane cùng có chưa đọc → badge = tổng. ⌘⇧U nhảy tới tab và focus đúng pane có thông báo mới nhất.
11. **Điện thoại không đổi:** mỗi pane là một phiên trong `session.list` (không đổi protocol, không đổi app mobile); điện thoại gõ vào một pane → chỉ pane đó có dải driver; phiên điện thoại mở → **tab mới** (không bao giờ thành pane).
12. **Trợ năng:** mỗi pane là vùng có nhãn "Pane 2 trên 3 — vim"; chia/đóng/chuyển focus được đọc lên; mọi thao tác (chia, focus, đổi cỡ, phóng to, cân bằng, đóng) làm được chỉ bằng bàn phím và bằng menu (WCAG 2.1.1, 2.5.7).
13. **Không hồi quy:** mọi test A1/A2/A4 vẫn xanh (trừ fake bổ sung tham số mới); tab một pane trông giống hệt A4 (test so sánh: không pane header, không viền focus, cùng nhãn "Terminal {title}", vòng sáng A4 cùng chỗ).

---

## 2. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| P1 | Mô hình (controller) | Dòng sidebar là **tab** giữ **cây pane nhị phân** (chia ngang/dọc có tỉ lệ); mỗi pane = một phiên agent. Điện thoại vẫn thấy từng phiên (không đổi protocol). Tab một pane = A2 | — |
| P2 | Dòng sidebar của tab chia (controller) | Tiêu đề/ngữ cảnh từ pane đang focus; dấu số pane nhỏ; chú ý gộp (badge = tổng chưa đọc các pane; vòng ở pane đã báo) | — |
| P3 | Hành động/phím tắt (controller) | Chia phải ⌘D / Ctrl+Shift+D; chia xuống ⌘⇧D / (chọn ở D20); focus ⌘⌥mũi tên / Ctrl+Alt+mũi tên; đóng pane ⌘W (pane cuối đóng tab; D15 A1 áp dụng từng pane); phóng to ⌘⇧↩ / Ctrl+Shift+Enter; cân bằng ⌘⌃=; kéo đường chia (vùng bấm 6 px, nét 1 px) và ⌘⌃mũi tên; menu terminal có Chia phải/xuống/Đóng pane/Phóng to; menu dòng có "Chia…" | — |
| P4 | Thư mục pane mới (controller) | Thư mục của pane đang focus (cwd A2) nếu biết, không thì home; thêm `LocalSessions.open(cwd:)` | — |
| P5 | Kích thước (controller) | Mỗi pane báo lưới của mình cho phiên của nó (quy tắc driver A1 theo từng phiên); pane bị ẩn (tab khác, D10) giữ quy tắc A1 "chỉ pane đang hiện báo cỡ" | — |
| P6 | Focus và đầu pane (controller: quyết ở D15, D16) | Bấm pane = focus; viền `accent` mảnh khi > 1 pane; có làm mờ pane không focus và đầu pane hay không: quyết ở D15–D16 | — |
| P7 | Kéo tab vào mép pane (controller) | **Ngoài phạm vi A3** (không rẻ: cần vùng thả trong terminal và chuyển cả cây phiên). Di chuyển pane giữa tab: ngoài phạm vi | Muốn gộp hai tab phải đóng một tab rồi chia lại |
| P8 | Lưu bố cục (controller) | Chỉ trong bộ nhớ; lưu qua khởi động lại là **A5** | Thoát app mất bố cục (phiên cũng mất tới A5) |
| P9 | Trợ năng (controller) | Mỗi pane là vùng có nhãn "Pane N trên M — <tiêu đề>"; đọc lên khi chia/đóng/đổi focus; bàn phím làm được mọi thứ | — |
| D1 | Id của tab | Id tab = id phiên **tạo ra tab** (pane đầu tiên); **giữ nguyên** khi pane đó đóng mà tab còn pane khác. Id phiên tăng dần và không bao giờ dùng lại (`sessionIdAllocator`), nên id tab không bao giờ trùng một phiên khác. Workspace (A2), tên tuỳ chỉnh, `CloseSuccessor`, `TabAttention` (A4) vẫn khoá theo id tab — không đổi | Mã nào ngầm coi "id tab == id phiên" (vd. `local.close(tab.id)`) phải đi qua `tab.paneIds`; test ở plan chặn |
| D2 | Mô hình dữ liệu | `PaneNode` sealed: `PaneLeaf(sessionId)` / `PaneSplit(axis, ratio, first, second)`. `axis: row` = cạnh nhau (chia phải), `column` = chồng nhau (chia xuống). `TerminalTab` (tab) giữ `layout`, `focusedPaneId`, `zoomedPaneId`, `panes: Map<int, PaneSession>` (bản ghi theo phiên — chính là các trường A1/A2 cũ của `TerminalTab`), `paneHistory` (MRU), `customTitle`. Các getter cũ của `TerminalTab` (`title`, `cwd`, `driver`, `terminal`, `selection`, `exitCode`, `label`…) **trỏ vào pane đang focus** → mã sidebar/A4 biên dịch không đổi | — |
| D3 | Chia | Pane mới chèn **ngay sau** pane đích (bên phải / bên dưới), tỉ lệ 0,5 của ô pane đích; pane mới nhận focus. Đang phóng to → bỏ phóng to rồi mới chia. Tab đang chọn là đích của phím tắt; menu dòng lấy tab đó (và chọn nó) | — |
| D4 | Cỡ tối thiểu | Pane ≥ **20 cột × 5 dòng** theo cỡ chữ hiện tại (cộng padding A1 và đầu pane). Chia khi pane đích không đủ chỗ cho hai pane tối thiểu + đường chia → **không chia**, toast trung tính "Không đủ chỗ để chia pane này". Kéo/phím đổi cỡ bị chặn ở mức tối thiểu. Cửa sổ thu nhỏ thì **giữ tỉ lệ**, pane có thể nhỏ hơn tối thiểu (không tự đóng) | Cửa sổ rất hẹp có pane vài cột (giống iTerm2) |
| D5 | Mở phiên cho pane — tranh chấp | Trong lúc `open()` của desktop đang chờ, phiên **gốc desktop chưa biết** không được nhận thành tab mới; khi `open()` trả về, người gọi quyết định (tab mới hay pane). Một lần mở tại một thời điểm (cờ `opening` A1 dùng chung cho tab và pane) | Một phiên desktop do nguồn khác mở đúng lúc đó (A7 sau này) hiện trễ tới lần `changes` sau |
| D6 | Đóng | ⌘W / "Đóng pane" / × trên đầu pane: đóng **pane đang focus** (hỏi theo A1 D15 nếu pane đó chạy lệnh). Pane cuối → đóng tab. × của dòng sidebar, "Đóng tab" trong menu dòng, bấm chuột giữa: đóng **cả tab** (mọi pane); hỏi nếu **ít nhất một** pane chạy lệnh ("2 pane đang chạy lệnh sẽ bị dừng"). Gợi ý phím ⌘W trên × dòng/menu dòng chỉ hiện khi tab có 1 pane | Không có phím tắt "đóng cả tab" khi có nhiều pane (dùng menu dòng); A9 cho tuỳ biến |
| D7 | Shell thoát trong pane | Mã 0 hoặc đóng theo yêu cầu → pane bị gỡ khỏi cây, pane anh em chiếm chỗ. Mã ≠ 0 → pane ở lại với dòng thoát A1 D14; Enter trong pane đó (hoặc ⌘W khi nó focus) đóng **pane đó**. Pane cuối thoát mã 0 → tab bị gỡ (A1) | — |
| D8 | Focus sau khi đóng | Pane dùng gần nhất còn lại trong tab (MRU); không có → lá đầu của nhánh anh em | — |
| D9 | Focus theo hướng | Hình học trên hình chữ nhật đơn vị của cây: ứng viên = pane có mép **chạm** mép pane đang focus theo hướng đó và **chồng lấn** theo trục vuông góc; chọn pane chứa đường tâm của pane đang focus, không có thì chồng lấn nhiều nhất, hoà thì dùng gần nhất (MRU). Không vòng. Đang phóng to → bỏ phóng to rồi chuyển | Bố cục lệch nhiều cho kết quả "gần nhất" khác iTerm2 một chút |
| D10 | Phóng to | Theo **tab** (`zoomedPaneId`). Pane phóng to vẽ đầy vùng; các pane khác vẫn được bố trí ở đúng ô của cây nhưng **không vẽ, không bấm được, không báo cỡ** (Offstage). Bỏ phóng to khi: ⌘⇧↩ lần nữa, chia, đóng pane phóng to, chuyển focus theo hướng. Đổi tab khác rồi quay lại → vẫn phóng to. Đầu pane phóng to hiện "Phóng to · 2/3" | — |
| D11 | Cân bằng | ⌘⌃= áp cho cả cây của tab: tỉ lệ mỗi nút = `nhịp(first) / (nhịp(first) + nhịp(second))`, nhịp theo trục của nút (lá = 1; nút cùng trục = tổng; khác trục = max). Ba cột chia liên tiếp → 1/3 mỗi cột. Nháy đúp đường chia → cân bằng **chỉ nút đó** | — |
| D12 | Đổi cỡ bằng phím | ⌘⌃→/← dời đường chia của **tổ tiên gần nhất trục `row`** của pane đang focus; ⌘⌃↓/↑ của tổ tiên gần nhất trục `column`; bước 5 % bề rộng/cao của nút đó; chặn theo D4. Không có tổ tiên trục đó → không gì xảy ra | Khác iTerm2 ("dời biên phía mũi tên của chính pane"): đơn giản và đoán được |
| D13 | Kích thước gửi phiên (P5) | Pane **hiện** = thuộc tab đang chọn **và** (không phóng to **hoặc** là pane phóng to) **và** chưa thoát. Chỉ pane hiện gọi `view.resize` khi xterm đổi lưới. Khi tập pane hiện đổi (chọn tab, bỏ phóng to) mỗi pane vừa hiện gửi lưới hiện tại một lần (mở rộng `_selectionChanged` A1). Pane mới mở với lưới **ước tính** = lưới pane đích chia đôi theo trục (trừ 1 cột/dòng cho đường chia và đầu pane), lưới thật tới ở lần bố trí kế | Một lần SIGWINCH thừa khi ước tính lệch |
| D14 | Đường chia | Nét 1 px `line`; vùng bấm 6 px canh giữa nét (đè lên mép pane, **không** chiếm chỗ bố trí ngoài 1 px); hover/kéo → nét `accent`; con trỏ `resizeColumn`/`resizeRow`. Kéo cập nhật tỉ lệ mỗi khung hình. Nháy đúp → D11. Không là điểm dừng Tab; trình đọc màn hình thấy nó là thanh trượt có tăng/giảm (5 %) | — |
| D15 | Đầu pane | Chỉ khi tab có **> 1 pane** (hoặc đang phóng to): dải **22 px** trên mỗi pane: chấm trạng thái, tiêu đề pane (một dòng, cắt), dấu 📱/👁, chấm chưa đọc A4, chỉ báo phóng to, nút × (hiện khi hover hoặc pane focus). Pane focus: nền `rowSelected`, chữ `textPrimary`; không focus: nền `bgSidebar`, chữ `textSecondary`. Đầu pane là một phần bố trí của pane (giảm 1 dòng lưới khi chia — chấp nhận vì là thao tác người dùng chủ động) | Mất ~1 dòng mỗi pane |
| D16 | Viền focus, không làm mờ | Pane đang focus có viền **1 px `accent`** vẽ đè (IgnorePointer) quanh cả pane (đầu + terminal), chỉ khi > 1 pane và không phóng to. **Không làm mờ** chữ pane không focus: làm mờ kéo chữ ANSI tối (vd. `brightBlack`) dưới 4,5:1 (WCAG 1.4.3); đầu pane + viền đã đủ phân biệt | Pane không focus trông "sống" như pane focus (giống Windows Terminal, khác iTerm2) |
| D17 | `open(cwd:)` ở agent | `LocalSessions.open({cols, rows, String? cwd})`. Agent dùng `cwd` khi: tuyệt đối, **không** phải UNC (`\\server\…`, cmd.exe không chạy được ở UNC), và là thư mục tồn tại — kiểm bằng `Directory.exists` có **timeout 300 ms**; sai/quá giờ → home, không lỗi. Log chỉ "cwd fallback" (không đường dẫn). ⌘T (tab mới) **vẫn ở home** như A1 | Ổ mạng chậm làm pane mới ở home; người quen ⌘T theo thư mục (cmux) phải dùng ⌘D |
| D18 | Gộp chú ý A4 (P2) | `TabUnread` thêm `panes: Map<int, int>` (id phiên → số chưa đọc); `count` = tổng (badge); `text` = thông báo mới nhất của tab. "Đã thấy" (A4 D7) = tab đang chọn **và** pane báo là pane đang focus **và** cửa sổ active; BEL từ pane **không** focus vẫn tính (không phải phản hồi gõ phím). Đồng hồ đọc 1 s (A4 D10) chạy cho **pane đang focus** có chưa đọc → đọc pane đó; tab hết chưa đọc khi mọi pane đã đọc. "Đánh dấu đã đọc" (menu dòng), bấm thông báo hệ thống, ⌘⇧U: đọc cả tab. Vòng sáng: quanh **từng pane** có chưa đọc của tab đang chọn (tab một pane: đúng vị trí A4). Pane ẩn do phóng to có chưa đọc → chấm `accent` trên chỉ báo phóng to. `jumpTo` focus pane có thông báo mới nhất. Mục lịch sử thêm `paneId`. `reads` vẫn phát **id tab**, chỉ khi tab hết chưa đọc. Pane đóng → chưa đọc của nó bị bỏ | Người muốn "nhìn tab là đọc hết" phải bấm vào từng pane (hoặc dùng menu "Đánh dấu đã đọc") |
| D19 | Dòng sidebar | Dấu số pane: `Icons.view_column_outlined` 12 + chữ số `caption`, `textSecondary`, **sau badge A4, trước 📱**; chỉ khi ≥ 2 pane; tooltip "3 pane". Chấm trạng thái, tiêu đề, dòng ngữ cảnh: pane focus. 👁 khi **bất kỳ** pane có điện thoại gắn; màu `warn` khi bất kỳ pane gắn đang do điện thoại lái. 📱 = gốc của phiên tạo tab | — |
| D20 | Phím Windows | Theo hướng Ctrl+Shift của A1; chord có Alt chỉ nhận **Alt trái** (AltGr = Ctrl+Alt trên Windows, như A1 với Ctrl+Alt+số): chia phải Ctrl+Shift+D; chia xuống **Ctrl+Shift+Alt+D**; focus Ctrl+Alt+mũi tên; phóng to Ctrl+Shift+Enter; cân bằng **Ctrl+Shift+Alt+=**; đổi cỡ **Ctrl+Shift+Alt+mũi tên**; đóng pane Ctrl+Shift+W. Chia/phóng to/cân bằng/đóng không lặp phím; focus và đổi cỡ lặp phím được | Driver đồ hoạ Intel cũ dùng Ctrl+Alt+mũi tên để xoay màn hình (nếu bật thì hệ thống nuốt phím); menu và ⌘⌃/Ctrl+Shift+Alt vẫn thay được |
| D21 | Menu | Menu terminal (A1 I6): sau Sao chép/Dán/Chọn tất cả, vạch, "Chia sang phải ⌘D", "Chia xuống dưới ⌘⇧D", (> 1 pane:) "Phóng to pane ⌘⇧↩"/"Bỏ phóng to", "Cân bằng pane ⌘⌃=", vạch, "Đóng pane ⌘W". Menu dòng (A2 §5.1 + A4): nhóm mới sau "Dùng tên tự động": "Chia sang phải", "Chia xuống dưới", "Cân bằng pane" (> 1 pane). Bấm chuột phải vào pane không focus → focus pane đó trước rồi mở menu | — |
| D22 | Trợ năng | Tab > 1 pane: mỗi pane `Semantics(container, label: "Pane {i} trên {n} — {title}")` (+ ", có thông báo chưa đọc" khi có vòng); tab 1 pane: nhãn A1/A4 "Terminal {title}". Đọc lên (lịch sự): chia → "Đã chia, pane {i} trên {n}"; đóng → "Đã đóng pane, còn {n}"; đổi focus bằng phím → "Pane {i} trên {n} — {title}"; phóng to/bỏ → "Đã phóng to pane"/"Đã bỏ phóng to"; không chia được → nội dung toast. Dòng sidebar thêm "{n} pane" vào nhãn | — |
| D23 | Thứ tự pane | Thứ tự đọc = duyệt sâu `first` trước `second` (trái→phải, trên→dưới). Dùng cho "Pane N trên M", lá đầu D8 | — |
| D24 | Điện thoại | Không đổi protocol. Phiên điện thoại mở → **tab mới** (A1). Điện thoại `session.close` phiên do desktop mở → tách (A1 D4), pane không đổi. Chia một tab gốc điện thoại được (pane mới gốc desktop). Dải driver A1 nằm **trong pane** của phiên đó | — |
| D25 | Tiêu đề | Tiêu đề cửa sổ, đầu pane macOS 28 px (A1 §2.1), hộp xác nhận: nhãn tab = tên tuỳ chỉnh hoặc tiêu đề tự động của **pane focus** | Đổi focus làm tiêu đề cửa sổ đổi (đúng ý P2) |
| D26 | Sao chép/dán/cỡ chữ | ⌘C/⌘V/⌘A, menu terminal tác động **pane focus**. Cỡ chữ (⌘+/−/0) chung cho mọi pane (như A1) | — |
| D27 | Giới hạn | Không giới hạn pane mỗi tab ngoài D4 và giới hạn 32 phiên/máy (A1 D8; vượt → toast A1) | — |
| D28 | Hộp xác nhận đóng | Đóng **tab** nhiều pane: tiêu đề A1 "Đóng “{tab}”?", nội dung mới `confirmCloseRunningPanesBody` "{n} pane đang chạy lệnh sẽ bị dừng.", nút A1. Đóng **pane** (tab > 1 pane): tiêu đề "Đóng “{tiêu đề pane}”?", nội dung `confirmCloseRunningPaneBody` "Lệnh đang chạy trong pane này sẽ bị dừng.", nút "Đóng pane". Tab một pane: hộp A1 nguyên văn | — |
| D29 | Font đổi cỡ | Đổi cỡ chữ giữ **tỉ lệ** (không giữ số cột); pane có thể dưới tối thiểu D4 (không tự đóng) | — |
| D30 | Pane mới khi tab đích không được chọn | Không xảy ra qua phím tắt; menu dòng chọn tab trước rồi chia | — |

**Sửa A1:** §2.3 "mỗi tab một `TerminalView` trong `IndexedStack`" → mỗi tab một **cây pane** trong `IndexedStack`; mỗi pane một `TerminalView`. A1 §3.6 vùng 1 "Terminal" = **pane đang focus** của tab đang chọn. Quy tắc `onResize` "chỉ tab đang chọn báo cỡ" → D13.
**Sửa A2:** không (workspace, thứ tự, kéo thả vẫn theo tab; dòng ngữ cảnh lấy pane focus).
**Sửa A4:** D7 ("thông báo của tab đang xem") và D10 (đồng hồ đọc) nay theo **pane focus** (D18); vòng sáng D21 vẽ theo **pane** thay vì cả vùng terminal (tab một pane: trùng khít).

---

## 3. Kiến trúc

```
packages/shellx_agent
 ├─ session/local_sessions.dart     open({cols, rows, String? cwd})                  (D17)
 └─ session/session_manager.dart    _spawn(workingDirectory) + kiểm thư mục 300 ms   (D17)
apps/desktop
 ├─ terminal/pane_layout.dart (mới)    PaneNode/PaneLeaf/PaneSplit, chia/gỡ/thứ tự/hình chữ nhật/
 │                                     hướng/cân bằng/đổi tỉ lệ — hàm thuần             (D2, D3, D9, D11, D12, D23)
 ├─ terminal/terminal_tabs.dart        PaneSession; TerminalTab giữ cây; split/closePane/focusPane/
 │                                     focusDirection/toggleZoom/equalize/setRatio/resizeFocused;
 │                                     tabOfSession; báo cỡ theo pane hiện                 (D1–D13)
 ├─ terminal/tab_attention.dart (A4)   gộp theo pane                                      (D18)
 └─ ui/terminal/
     ├─ pane_tree_view.dart (mới)      bố trí cây, đường chia, đầu pane, viền focus, phóng to, vòng theo pane
     ├─ terminal_pane.dart             IndexedStack của PaneTreeView; menu terminal          (D21)
     ├─ terminal_shortcuts.dart        7 intent mới                                        (P3, D20)
     ├─ terminal_workspace_page.dart   action, focus theo pane, đọc lên                     (D22)
     ├─ session_tab_row.dart           dấu số pane, nhãn                                    (D19)
     ├─ session_sidebar.dart           menu dòng                                            (D21)
     └─ close_tab.dart                 closePaneWithConfirm; đóng tab nhiều pane            (D6, D28)
```

### 3.1 Agent

- `LocalSessions.open({required int cols, required int rows, String? cwd})`. `SessionManager.open` truyền `cwd` vào `_spawn(..., cwd:)`; `_spawn` gọi `_workingDirectoryFor(cwd)`: `null`/rỗng/không tuyệt đối/UNC → home; ngược lại `await _directoryExists(cwd).timeout(300 ms)` (tham số constructor mới `Future<bool> Function(String path)? directoryExists`, mặc định `Directory(path).exists()`); lỗi/false/timeout → home. Phiên điện thoại (`_open`) luôn home (không đổi).
- Không đổi `SessionSummary`, protocol, `SessionRouter`.

### 3.2 Mô hình pane (desktop, hàm thuần)

```dart
enum SplitAxis { row, column }           // row: cạnh nhau (chia phải); column: chồng (chia xuống)
enum PaneDirection { left, right, up, down }
sealed class PaneNode { const PaneNode(); }
final class PaneLeaf extends PaneNode { final int sessionId; }
final class PaneSplit extends PaneNode { final SplitAxis axis; final double ratio; final PaneNode first, second; }
typedef PanePath = String;               // '' gốc, '0'/'1' từng bước first/second
```

Các hàm: `paneIds(node)` (D23), `splitPane(node, target, newId, axis)`, `removePane(node, id) → PaneNode?`, `paneRects(node, Rect)` (đơn vị), `neighbourPane(node, from, dir, {mru})` (D9), `equalized(node)` (D11), `withRatio(node, path, ratio)`, `ancestorSplit(node, id, axis) → PanePath?` (D12). Tỉ lệ luôn kẹp `[0.05, 0.95]` trong mô hình; kẹp theo px (D4) ở `TerminalTabs` với số đo do giao diện báo (`reportPaneMetrics`).

### 3.3 `TerminalTabs`

- `PaneSession` = bản ghi theo phiên (các trường A1/A2 cũ). `TerminalTab {id, layout, focusedPaneId, zoomedPaneId, panes, paneHistory, customTitle}` + getter uỷ quyền (D2).
- `TerminalTabsState.tabOfSession(int sessionId) → TerminalTab?`.
- `_merge`: cập nhật `PaneSession` theo `SessionSummary` trong mọi tab; phiên mới chưa biết → tab mới, **trừ** phiên gốc desktop trong lúc một `open()` đang chờ (D5).
- `split(SplitAxis)`, `focusPane(int sessionId)` (chọn tab của nó nếu cần), `focusDirection(PaneDirection)`, `closePane(int sessionId)`, `needsPaneCloseConfirm(int)`, `runningPaneCount(int tabId)`, `toggleZoom()`, `equalize()`, `equalizeAt(int tabId, PanePath)`, `setRatio(int tabId, PanePath, double)`, `resizeFocused(PaneDirection)`, `reportPaneMetrics(PaneMetrics)`. `close(tabId)` đóng mọi phiên của tab.
- `onResize` của mỗi phiên: chỉ gửi khi `_reportsSize(sessionId)` (D13). `_visibleChanged()` thay `_selectionChanged()`.

### 3.4 Gộp chú ý (A4, D18)

`TabAttention._onNotice` tìm tab bằng `tabOfSession`; `seen` dùng `focusedPaneId`; `TabUnread.panes`; `_armDwell` theo `(tabId, focusedPaneId)`; `markPaneRead(tabId, paneId)`; `markRead(tabId)` đọc mọi pane; `_dropGone` bỏ pane đã gỡ; `AttentionEntry.paneId`; `jumpTo` focus pane mới nhất. `AttentionState.paneHasUnread(tabId, paneId)` cho vòng theo pane.

### 3.5 Giao diện

`PaneTreeView(tab)`: tab một pane → **đúng** cây widget A4 (`_TabTerminal` + vòng A4); nhiều pane → `CustomMultiChildLayout`/`LayoutBuilder` đệ quy, mỗi lá là `KeyedSubtree(GlobalObjectKey('pane.$id'))` (giữ trạng thái `TerminalView` khi cây đổi), đường chia, đầu pane, viền focus, vòng theo pane, dải driver theo pane. Pane được focus nhận `terminalFocus` (vùng 1 A1); bấm/chạm vào pane khác → `Listener(onPointerDown)` gọi `focusPane` trước khi xterm xử lý.

---

## 4. Luồng dữ liệu

```
⌘D ─► SplitRightIntent ─► TerminalTabs.split(row)
        ├─ kiểm D4 (PaneMetrics) ─✗─► toast "Không đủ chỗ"
        └─ _local.open(cols, rows, cwd: pane focus.cwd) ─► agent: cwd hợp lệ? ─► PTY ở cwd / home
             └─ (D5) phiên mới ─► _attach ─► splitPane(layout) ─► focus pane mới ─► PaneTreeView bố trí
                                                                   └─ xterm.onResize ─► (pane hiện) view.resize
OSC 9 từ pane P ─► notices ─► TabAttention: tab = tabOfSession(P); seen = chọn ∧ P focus ∧ active
                                  └─ unread[tab].panes[P]++ ─► badge tổng, vòng quanh P, arrivals (A4)
```

---

## 5. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Chia khi đã 32 phiên | Toast A1 "Đã đạt tối đa 32 phiên"; cây không đổi |
| Spawn lỗi khi chia | Toast A1 spawn; cây không đổi |
| cwd không còn (thư mục bị xoá), ổ mạng chậm, UNC | Home (D17) |
| Pane đích thoát trong lúc đang mở pane mới | Pane mới vẫn thêm vào tab nếu tab còn (chèn sau lá đầu nếu đích mất); tab mất → pane mới thành tab mới |
| Tab bị đóng trong lúc đang mở pane | Phiên mới thành tab mới (không mất phiên) |
| Đóng pane đang được điện thoại lái | Như đóng tab A1: desktop đóng được mọi phiên; điện thoại nhận `session.closed` |
| Pane thoát mã ≠ 0 khi đang phóng to pane khác | Pane đó giữ dòng thoát (ẩn); đầu pane có chấm `err` khi hiện lại |
| Kéo đường chia rồi cây đổi giữa chừng (pane thoát) | `setRatio` kiểm `PanePath` vẫn là nút cùng trục; sai → bỏ qua; kéo kết thúc |
| Cửa sổ hẹp tới mức pane < 1 cột | Lưới null → không gửi resize (A1 `measureTerminalGrid`) |
| Điện thoại mở phiên trong lúc desktop chia | Phiên gốc điện thoại không bị D5 giữ lại: thành tab mới ngay |
| Phím chia khi không có tab (trạng thái trống) | Không làm gì (⌘T mới mở tab) |
| Chuột giữa trên đầu pane | Đóng pane đó (như ×), theo D15 A1 |
| Kéo chọn chữ vượt mép pane | Vùng chọn kẹp trong pane (mỗi pane một `TerminalView` riêng) |

---

## 6. Kiểm thử

- **`shellx_agent`** (`dart test`): `local_sessions_test` thêm nhóm `open(cwd:)`: cwd tồn tại → `FakePty.workingDirectory == cwd`; null, tương đối, UNC, không tồn tại, probe ném, probe treo (timeout 300 ms với `fake_async`) → home; phiên điện thoại → home.
- **`apps/desktop`** (`flutter test`):
  - `pane_layout_test` (thuần): chia/gỡ, thứ tự đọc, hình chữ nhật, hướng (chữ T, lưới 2×2, không vòng, MRU hoà), cân bằng 3 cột và lồng, `withRatio` kẹp, `ancestorSplit`.
  - `terminal_tabs_panes_test`: tab một pane như A2 (id, nhãn); `split` dùng cwd và lưới ước tính, focus pane mới; D5 tranh chấp (`afterOpen` phát `changes` trước khi `open` trả về → không có tab thừa); `closePane` (MRU, pane cuối đóng tab, tab id giữ khi pane gốc đóng); thoát mã 0/≠0 theo pane; Enter đóng pane đã thoát; zoom (bỏ khi chia/đóng/hướng); `onResize` chỉ pane hiện; bỏ phóng to gửi lưới các pane vừa hiện; `close(tab)` đóng mọi phiên; `needsCloseConfirm` khi một pane chạy lệnh; D4 từ chối chia.
  - `pane_tree_view_test` (widget): tab một pane không có đầu pane/viền (giống A4); hai pane có hai `TerminalView`, đầu pane, viền focus ở pane focus; bấm pane khác → focus đổi và bàn phím vào đó; kéo đường chia đổi tỉ lệ và gọi `resize` cho cả hai phiên; nháy đúp cân bằng; phóng to ẩn pane khác; nhãn Semantics "Pane 1 of 2 — zsh".
  - `pane_shortcuts_test`: ⌘D/⌘⇧D/⌘⌥→/⌘W/⌘⇧↩/⌘⌃=/⌘⌃→ (macOS) và chord Windows; AltGr không kích hoạt; menu terminal và menu dòng.
  - `tab_attention_panes_test`: D18 — badge tổng, seen theo pane focus, BEL từ pane không focus tính, đọc 1 s chỉ pane focus, `markRead` đọc mọi pane, pane đóng bỏ chưa đọc, `jumpTo` focus pane mới nhất; vòng chỉ quanh pane có chưa đọc.
  - Toàn bộ test A1/A2/A4 vẫn xanh.
- **Thử tay** (HANDOFF §14): macOS và Windows thật — chia với `vim`/`htop`/Claude Code, kéo đường chia, phóng to, cwd trong repo/worktree/ổ mạng, điện thoại gõ vào một pane, VoiceOver/Narrator đọc pane, AltGr trên bàn phím Đức/Ba Lan, Ctrl+Alt+mũi tên trên máy có driver Intel.

---

## 7. Ngoài phạm vi A3

Kéo tab vào mép pane để gộp (P7); chuyển pane sang tab khác hoặc tách pane ra tab; hoán đổi/xoay pane; lưu bố cục qua khởi động lại (**A5**); nhiều "surface" trong một pane (tab trong pane kiểu cmux); pane trình duyệt (**A6**); điều khiển pane qua CLI/socket (**A7**); bố cục pane trên điện thoại; đồng bộ input tới nhiều pane (broadcast); phím tắt tuỳ biến (**A9**); làm mờ pane không focus (D16); ⌘T mở theo cwd (D17).
