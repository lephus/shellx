# V2-5b — Trợ lý AI giống Claude desktop, có bộ chọn dự án — Đặc tả thiết kế

- **Ngày:** 2026-10-16
- **Branch:** `shellx-v2`. V2-5 không lên `main` khi người dùng chưa nói (đẩy `main` là phát hành app desktop).
- **Trạng thái:** Người dùng đã duyệt đề xuất V2-5 ngày 16/10: "làm theo khuyến nghị, Nhưng tên app nên để tên đầy đủ". Tài liệu này là phần **B** của đề xuất, viết thành thiết kế làm được.
  - Điều đã duyệt ghi "(đã duyệt)" và không mở lại.
  - Chỗ đề xuất chưa nói, người viết spec chốt ở T1–T49, mỗi quyết định ghi cái giá nếu sai.
  - Không còn việc chờ người dùng (§17): 🎙 trên desktop (T41) và tab AI ở chế độ Terminal (T2) đã chốt theo khuyến nghị.
- **Phụ thuộc:**
  - V2-2b, V2-3, V2-4 đã gộp vào `shellx-v2`. Spec viết trên trạng thái gộp đó.
  - **V2-5a** (`2026-10-16-v2-5a-name-and-design-system-design.md`): tên app, token, kiểu chữ, component, bảng vai trò biểu tượng `ShellxIcons`. B gọi component của A theo vai trò: "nút chính gradient của A", "chip / segmented của A", "thẻ của A", "sheet của A", "menu của A", "thanh dưới của A", "nêm / kính của A". B không định nghĩa token, cỡ chữ hay font. Làm sau A.
  - **Cập nhật 16/10 11:25 của A (bắt buộc):** font của cả hai app là **SF Mono**: SF Mono của hệ thống trên iOS, macOS, nạp lúc chạy, không bao giờ đóng gói; **JetBrains Mono** trên Android, Windows. Trên iOS, macOS mà không nạp được SF Mono thì dự phòng là JetBrains Mono, không phải Menlo (Menlo chỉ có 88/134 chữ tiếng Việt; A31–A33, đã chốt). Biểu tượng là **`CupertinoIcons`** (`cupertino_icons` ghim 1.0.9) qua bảng vai trò `ShellxIcons` của A; A quyết tên vai trò và glyph. B tuân theo ở T48 (biểu tượng) và T49 (bố cục với chữ đơn cách).
  - **V2-5c** (giọng nói) định nghĩa việc của nút 🎙 mà B đặt chỗ (T41).
- **Hướng đã được duyệt (phần B):**
  1. "Giao diện AI" / "AI interface" thành **"Trợ lý AI" / "AI Assistant"**. "Phiên AI" / "AI session" giữ cho một phiên. Gọi "Claude", không bao giờ "Claude Code".
  2. Desktop: sidebar có công tắc **Terminal | Trợ lý AI**. Chế độ AI có "+ Phiên mới", **Dự án** (workspace có thư mục; mở ra thấy phiên đang mở và phiên cũ từ `session/list {cwd}` của agent), "Gần đây", lọc trạng thái (đang chạy / cần bạn / xong). Tab terminal ở chế độ Terminal.
  3. **Màn bắt đầu** (chưa chọn phiên): lời chào, nêm hoặc kính của tham chiếu, **thẻ ô nhập ở giữa**, chip **📁 Dự án ▾ · agent (Claude ▾) · Chế độ ▾ · Model ▾ · 🎙**. Tin đầu tạo phiên với dự án, agent, chế độ, model đã chọn, thay cho "mở tab ngay với agent mặc định".
  4. **Bộ chọn dự án:** tìm; dự án (tên, đường dẫn, nhánh git); **thư mục gần đây** (danh sách mới, có lưu); **"Mở thư mục…"** bằng hộp chọn của hệ điều hành qua `file_selector` ghim (đảo V2-1 B7); "Lưu thành dự án".
  5. **Bộ chọn agent theo phiên.**
  6. **Trang phiên:** header có dự án, nhánh, agent, trạng thái; tin người dùng là bong bóng, chữ agent rộng hết; thẻ tool gọn; suy nghĩ gập; panel Thay đổi / Tệp / Terminal giữ; thẻ ô nhập giống màn bắt đầu.
  7. Điện thoại: **thanh dưới Máy tính / Trợ lý AI / Cài đặt**, mục đang chọn là ô nổi gradient. Trang Trợ lý AI làm việc trên máy đang chọn (chip máy): dự án (workspace có thư mục, cộng thư mục AI gần đây), phiên của dự án (đang mở và cũ), phiên mới kiểu gõ trước (dự án và agent là chip). Hội thoại kiểu desktop. **Điện thoại không bao giờ duyệt thư mục** (V2-2 D9 giữ).
  8. Giao thức thêm (thư mục gần đây, liệt kê theo dự án) theo luật V2-2: cờ khả năng; bản cũ vẫn chạy; giải mã không làm rơi kênh; `toString()` là `Tên(…)`; không log nội dung.
  9. Cập nhật 16/10 11:25, lời người dùng: "tôi muốn bạn sử dụng font chữ SF Mono cho mobile và desktop app ; icon trong app thì dùng cupertino". Phần font và biểu tượng là của A; B gọi biểu tượng theo vai trò và giữ bố cục chạy được với chữ đơn cách rộng hơn.
- **Tài liệu này thay** (lý do ở quyết định tương ứng):
  - V2-1 D4, D5: `new-tab-kind` quyết định ⌘T và "Phiên AI mới" mở tab ngay → T6, T7;
  - V2-1 B7 (không có hộp chọn thư mục) → T26;
  - V2-1 "tab AI không hiện nhánh" → T28;
  - V2-1 D15: nút Lịch sử trên header → T30;
  - V2-1 §4.2 "lệnh xong thì thẻ tự mở" → T32;
  - V2-2 §5.1: sheet "Phiên AI mới" hai danh sách radio → T38;
  - V2-2b B11: chạm dòng phụ để mở "Chế độ và model" → T39;
  - V2-2b B21: chạm dòng AI của máy mở bộ chọn → T34.
- **Nền:** `shellx-v2` sau khi gộp `v2-2b` (`fd48288`), `v2-3` (`bfff4c0`), `v2-4` (`e3ca11f`), là HEAD của ba worktree lúc đọc. Đường dẫn mã: mã desktop tính từ `apps/desktop/lib/src/`, mã mobile tính từ `apps/mobile/lib/`, gói (`packages/…`) và chỗ viết đủ tính từ gốc repo. Số dòng lấy ở worktree có bản mới nhất của tệp, có thể lệch vài dòng sau khi gộp.
- **Nguồn đã kiểm ngày 16/10/2026:**
  - mã của ba worktree;
  - spec V2-1, V2-2, V2-2b, V2-3, V2-4;
  - nghiên cứu `ai-ui-current.md` và `references.md` §1. Claude desktop: tab Code chọn thư mục, model, chế độ trước tin đầu; sidebar lọc theo trạng thái, nhóm theo dự án; thẻ ô nhập có hàng điều khiển;
  - pub.dev: `file_selector` 1.1.0 cần Flutter 3.32 / Dart 3.8; `file_selector_macos` 0.9.5+1 và `file_selector_windows` 0.9.3+6 cần Flutter 3.38 / Dart 3.10. Cả ba hợp với Flutter 3.41.4 / Dart 3.11.1 của repo. README của `file_selector`: entitlement `files.user-selected.*` dành cho app sandbox;
  - lớp `CupertinoIcons` của Flutter 3.41.4 (`packages/flutter/lib/src/cupertino/icons.dart` trong SDK đã cài): mọi glyph `CupertinoIcons` nêu ở §4.0 có tên trong lớp này; **không có** glyph terminal (A dùng glyph Material dự phòng cho `terminal`) hay mảnh ghép (A dùng `square_grid_2x2` cho `tool`).
- **Ký hiệu:**
  - "T1" là quyết định của tài liệu này; "V2-1 D5", "V2-2 D9", "V2-2b B17", "V2-3 D4", "V2-4 E4" là của spec khác.
  - "A1", "A2", "A4", "A9", "A12" viết liền số là các spec desktop ngày 06–07/10 (`2026-10-06-desktop-terminal-a1-design.md`, `2026-10-07-desktop-*-aN-design.md`, `2026-10-07-agents-a12-design.md`), không phải quyết định của V2-5a; "A" đứng riêng ("của A") là spec V2-5a.
  - **ĐT** = điện thoại, **DT** = desktop.
  - **Chế độ AI** = chế độ Trợ lý AI của sidebar desktop.
  - **Màn bắt đầu** = vùng nội dung của chế độ AI khi chưa chọn phiên.
  - **Nhóm** = một thư mục trong sidebar AI.
- **V2-5b được phép sửa:**
  - app desktop, app mobile;
  - `packages/shellx_core/lib/src/protocol/` (chỉ thêm);
  - `packages/shellx_ai`: listing, `AiRuntime.listSessions` theo thư mục, trình liệt kê lịch sử, bộ đệm tuỳ chọn;
  - `packages/shellx_agent`: hub, `AiSessionSource`;
  - `packages/shellx_client`;
  - `packages/shellx_design`: chỉ thêm các vai trò mới của §4.0 (nguồn B) vào `ShellxIcons` và vào `icons_test.dart` (T48).

  **Không sửa:** relay; mô hình phiên (`AiSessionState`, `Timeline`); token, component và vai trò biểu tượng đã có của A.

---

## 1. Mục tiêu

Người dùng làm việc với agent như trong Claude desktop:
- chọn dự án trước;
- gõ câu đầu ở màn bắt đầu;
- thấy phiên của từng dự án ở một chỗ: đang chạy, cần mình, đã xong, phiên cũ.

Người dùng terminal giữ chế độ Terminal như hôm nay. Trên điện thoại, Trợ lý AI là một mục riêng của thanh dưới, đi từ dự án tới phiên, mở phiên mới bằng cách gõ trước.

### Tiêu chí thành công (đo được)

1. **Công tắc.** ⌘⇧J đổi chế độ trong một khung hình. Chế độ Terminal không có hàng AI; chế độ AI không có hàng terminal. Lần mở sau ở đúng chế độ lúc thoát.
2. **Bắt đầu như Claude.**
   - ⌘⇧E: màn bắt đầu hiện, ô nhập có focus, chip dự án đặt sẵn.
   - Gõ "sửa nút đăng xuất", Enter: trong cùng khung hình có hàng phiên dưới đúng dự án ở sidebar và trang phiên hiện.
   - Tin đầu tới agent **đúng một lần**, ngay khi agent sẵn sàng.
   - Chế độ và model chọn trên màn bắt đầu có hiệu lực từ lượt đầu.
3. **Chọn dự án.**
   - Gõ "shop" trong bộ chọn: lọc xong trong một khung hình.
   - "Mở thư mục…" mở hộp chọn của hệ điều hành.
   - Thư mục vừa dùng nằm đầu "Gần đây", còn sau khi mở lại ShellX (tối đa 20).
   - "Lưu thành dự án" tạo workspace có thư mục đó.
4. **Phiên theo dự án.**
   - Mở một dự án: thấy phiên đang mở.
   - "Phiên trước" hiện trang đầu trong ≤ 3 s khi agent đó đang chạy, ≤ 10 s khi phải chạy agent.
   - Mở một phiên trước: tab mới phát lại lịch sử (V2-1 D14).
5. **Header.** Thấy dự án, nhánh, agent, trạng thái. Nhánh đổi trong ≤ 2 s sau `git switch`, khi cửa sổ được focus hoặc lượt kết thúc.
6. **Hội thoại.** Bong bóng, thẻ gọn, suy nghĩ gập. Mọi test V2-1 và V2-2b của xin quyền, hàng đợi, dừng, `@`, `/`, ảnh vẫn xanh.
7. **Điện thoại.**
   - Thanh dưới ba mục.
   - Trang Trợ lý AI của một máy online hiện dự án và thư mục gần đây trong ≤ 2 s.
   - Mở một dự án: thấy phiên đang mở và phiên trước.
   - Gõ một câu, Gửi: trang phiên mở và câu đã gửi trong ≤ 3 s trên mạng thường.
8. **Bản cũ.** Các tổ hợp ở §6.4 có test. V1 và V2.0 đọc `layout.json` có `mode` mà không đổi tệp thành `.bak`.
9. **An toàn.** Không đường nào mới (màn bắt đầu, bộ đệm tuỳ chọn, điện thoại) bật hay nhớ chế độ không cần duyệt. Mọi test hiện có vẫn xanh.

---

## 2. Kiểm tra hiện trạng (đọc mã ngày 2026-10-16)

| Mảng | Hiện có | Hệ quả |
|---|---|---|
| Mở phiên AI (DT) | `AiOpener.newSession` mở tab **ngay** với agent mặc định. Thư mục: `Workspace.root`, rồi thư mục tab trước mặt, rồi thẻ gõ đường dẫn (`apps/desktop/lib/src/ai/ai_open.dart:27-63`). ⌘T / `+` mở tab AI khi `new-tab-kind = ai` (`ai_open.dart:69-91`, `config/settings_schema.dart:474-489`) | T6, T7, T22 |
| Sidebar (DT) | Một danh sách 220 px; tab AI lẫn tab terminal trong workspace. Dải đầu 38 / 36 px có ⚙ 🔔 +; trên macOS đèn giao thông chiếm 80 px trái. Chân sidebar: "Phiên AI mới" và 🧩 (`ui/terminal/session_sidebar.dart:1441-2030`; `ui/theme/shellx_desktop_theme.dart:71,92-93,157`) | T2, T3, T10 |
| Chọn tab | Một `selectedId`; `_sync` tự điền tab đầu khi nó null (`terminal/terminal_tabs.dart:998-1003`). Chỗ đọc "đang hiện": A12 `paneVisible` (`terminal/agent_status_notifier.dart:194`), dwell A4, `seenOnDesktop` (`ai/ai_phone.dart:284`), `IndexedStack` giữ mọi tab sống (`ui/terminal/terminal_pane.dart:421-433`), tiêu đề cửa sổ (`ui/window_host.dart:18`), `ui.ls` (`cli/ui_command_handler.dart:214,238`), dock (`ui/tools/tool_area.dart:41-44`) | T5 |
| Agent | Chỉ chọn được trong Cài đặt › Agents (`ai/ai_agents.dart:259-266`). Lựa chọn nhớ theo agent chỉ có id và giá trị, không có tên (`ai_agents.dart:273-310`, khoá `ai_agent_config`). Áp sau `session/new`, trước tin đầu (`packages/shellx_ai/lib/src/host/ai_runtime.dart:265-290`) | T20, T21 |
| Thư mục | Thẻ gõ đường dẫn (B7), không có `file_selector` trong pubspec. App macOS không sandbox (`apps/desktop/macos/Runner/*.entitlements`). Không có danh sách gần đây (chỉ `ssh_recent_targets`) | T24–T26, T29 |
| Lịch sử | `AiRuntime.listSessions` cần runtime đang chạy và luôn hỏi thư mục của phiên (`ai_runtime.dart:740-750`). Hộp thoại desktop chỉ trang 1 (`ui/ai/ai_history.dart`). Điện thoại `ai.history {sid}` cần một phiên (`packages/shellx_client/lib/src/machine_ai.dart`, `history`) | T13, T14, T43 |
| Nhánh | `GitHeadReader` cho pane terminal (`packages/shellx_agent/lib/src/context/git_head.dart`). Tab AI không có nhánh (`TerminalTab.gitBranch` trả null) | T28 |
| Hội thoại (DT) | Tin người dùng là hộp viền có nhãn "Bạn" (`ui/ai/ai_timeline.dart:181-260`). Thẻ tự mở khi lệnh sửa chờ quyền và khi lệnh chạy xong (`ui/ai/ai_tool_card.dart:406-411`). Suy nghĩ gập (`ai_timeline.dart:271-324`). Header 34 px (`ui/ai/ai_header.dart`, `ui/ai/ai_theme.dart`) | T30, T32 |
| Ô nhập (DT) | Gắn với runtime qua `AiPaneScope` (`ui/ai/ai_composer.dart:70-125`). `_Unchecked` giữ ảnh gửi trước khi biết agent nhận ảnh (`ai_composer.dart:45-58`). `send` trả false khi agent cần đăng nhập hoặc lỗi khởi động (`ai_runtime.dart:449-467`) | T19, T22 |
| Dock tool | Workspace của dock: `loose`, rồi tab đang chọn, rồi workspace hiện tại (`ui/tools/tool_area.dart:41-44`) | T8 |
| Khôi phục | `layout.json` v1 có `selectedTab`, `aiTabs`, `toolDock` ở cấp trên cùng; bản cũ bỏ qua khoá lạ cấp trên cùng (`restore/restore_snapshot.dart:326-352,463-472`) | T6 |
| Cài đặt (DT) | Khoá UI phải có trong `SettingKeys.all` và `UiSettingKeys` (`platform/settings_store.dart`) | T21, T25 |
| App mobile | Một chồng phẳng `auto_route` 11.1.0, `MachineListRoute` là trang đầu (`core/router/app_router.dart:7-32`). Cài đặt đẩy từ nút ⚙ của trang máy. `session_enforcer` gọi `replaceAll([MachineListRoute()])`. Thông báo gọi `popUntilRouteWithName(MachineListRoute.name)` (`features/notifications/presentation/notification_opener.dart`). B21 giữ kênh khi `ModalRoute.isCurrent` (`machine_list_page.dart`, `didChangeDependencies`). `AppSettings` lưu trong kho bảo mật (`core/settings/app_settings.dart`) | T34, T35 |
| AI trên ĐT | Lối vào là bộ chọn phiên và nút ✦ ở trang máy. Sheet "Phiên AI mới" có hai danh sách radio (`features/ai/presentation/widgets/ai_new_session_sheet.dart`), dùng ở `terminal_page.dart` và `ai_chooser.dart` | T36–T38 |
| Listing | `folders` = gốc workspace (`ws:<id>`) cộng `cwd` của tab AI đang mở (`path:<dir>`) (`ai/ai_phone.dart:160-184`). Listing quá cỡ thì cắt (`packages/shellx_agent/lib/src/ai/ai_phone_hub.dart:1062-1090`). Khoá `f` liệt kê các từ tính năng (`packages/shellx_ai/lib/src/remote/listing.dart`, `AiFeature`) | T42 |
| Dịch vụ nền | Chuyển `ai.*` nguyên văn; loại lạ thành `AiRaw` (V2-2b B2). Không có cửa sổ thì `AiRaw` có `rid` nhận `unavailable` (`packages/shellx_agent/lib/src/ai/ai_endpoint.dart:36-60`) | T45 |

---

## 3. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| T1 | Tên | "Giao diện AI" / "AI interface" thành "Trợ lý AI" / "AI Assistant" ở mọi chuỗi (§8.1), ở từ khoá tìm của Cài đặt (`new-tab-kind`: thêm `trợ lý ai`, `assistant`, `chế độ`, `mode`) và ở chú thích của tệp cấu hình mẫu (`config_template.dart`). "Phiên AI" / "AI session" giữ cho một phiên. Agent gọi là "Claude", không bao giờ "Claude Code" trong tên tính năng hay chuỗi giao diện. (đã duyệt) Vì vậy mô tả `aiSettingClaudeDesc` "Chạy Claude Code qua adapter Claude Agent…" bỏ chữ "Claude Code" (§8.1): luật đặt tên của V2-5 chặt hơn V2-1 D21, vốn cho phép chữ đó trong phần mô tả. Test "feature names say Claude" (`test/l10n/ai_strings_test.dart`) thêm `aiSettingClaudeDesc` và các chuỗi của §8.1. | Đổi tên lại chỉ là sửa ARB. |
| T2 | Hai chế độ | Sidebar desktop có hai chế độ, **Terminal** và **Trợ lý AI**. Mỗi loại tab chỉ hiện ở chế độ của nó. **Chế độ Terminal:** liệt kê tab terminal theo workspace và nhóm Tool (V2-3 D21) như cũ, **không** liệt kê tab AI; số tab trên tiêu đề workspace và gợi ý "không có tab" chỉ tính tab terminal; vùng nội dung hiện tab terminal đang chọn, không có thì trạng thái trống A1. **Chế độ AI:** liệt kê phiên AI (T10), không liệt kê tab terminal; vùng nội dung hiện phiên AI đang chọn (gồm pane terminal bên dưới nếu có, V2-1 D3) hoặc màn bắt đầu (T18). Tab AI vẫn là thành viên của một workspace (đặt tab, dock tool, khôi phục không đổi). **Loại bỏ:** chế độ Terminal vẫn liệt kê tab AI như V2-1 — hai nơi xem cùng một phiên, hai luật chọn tab, khó giữ bất biến T5. **Đã chốt theo khuyến nghị:** tab AI không được liệt kê ở chế độ Terminal. | Ai quen thấy tab AI lẫn trong workspace phải chuyển chế độ (một phím, T4). V2 chưa phát hành nên chưa ai quen. Muốn liệt kê lại tab AI ở chế độ Terminal: sửa T2, T5, T9 và thêm luật chọn tab cho hai nơi. |
| T3 | Công tắc chế độ | **Segmented của A** với hai ô "Terminal" và "Trợ lý AI". Rộng hết sidebar (lề 8 px), cao 28 px, nằm **ngay dưới dải đầu sidebar**: dải đầu giữ ⚙ 🔔 + và trên macOS đèn giao thông chiếm 80 px trái, nên không đủ chỗ trong dải. Ô của chế độ không đang xem mang dấu khi chế độ đó cần bạn: ô "Trợ lý AI" có số phiên AI cần bạn; ô "Terminal" có chấm khi một tab terminal có thông báo chưa đọc (A4). Thứ tự Tab: ⚙ → 🔔 → + → công tắc → danh sách; mũi tên trái / phải đổi ô. Đọc màn hình: "Chế độ: Trợ lý AI, đã chọn, 1 phiên AI cần bạn". Chỉ có chữ, không biểu tượng. Nhãn của ô cắt bằng dấu ba chấm khi không vừa (T49); số đếm và chấm không bao giờ bị cắt. | Sidebar mất 36 px chiều cao. |
| T4 | Phím | Hành động mới `toggle_ai_mode` (nhóm `window`), mặc định **⌘⇧J / Ctrl+Shift+J**. Chord này trống ở cả hai nền tảng (Ctrl+Shift+A trên Windows đã là `select_all`). Có trong bảng phím A9 (đặt lại được) và bảng lệnh ("Chuyển Terminal / Trợ lý AI"). | Phím không gợi nhớ; người dùng đặt lại trong tệp cấu hình. |
| T5 | Chọn tab theo chế độ | `TerminalTabsState.selectedId` vẫn là nguồn duy nhất của "tab đang hiện". Thêm hằng **`kNoTabShown = 0`** và hàm `TerminalTabs.showNone()`. Số 0 không bao giờ là id tab: id phiên đếm từ 1, id tổng hợp ≥ 2·10⁹. `select(id)` không bao giờ nhận số 0. **Bất biến I-mode:** `selected == null \|\| selected.kind == chế độ đang xem`. Giữ bằng bốn luật: **(a)** đường chọn có chủ ý đổi chế độ theo loại tab **trước** khi đặt `selectedId`. Các đường đó: `TerminalTabs.select` (hàng sidebar, ⌘1–9, Ctrl+Tab, thông báo A4, ⌘⇧U, `ui.*` của CLI, khôi phục), `openAiTab(select: true)`, tab terminal mới do người dùng mở. **(b)** Đổi chế độ thì chọn tab đã nhớ của chế độ kia trong lần chạy này (`lastTerminal`, `lastAi`) nếu tab còn. Không còn: chế độ Terminal chọn tab terminal đầu theo thứ tự sidebar, không có thì `showNone()`; chế độ AI thì `showNone()` (màn bắt đầu). **(c)** `selectedId` đổi mà không qua (a) (kế vị khi đóng, `_sync`) và vi phạm I-mode thì chuẩn hoá ngay theo luật (b). **(d)** `_sync` giữ nguyên: `selectedId ?? first` không đụng tới số 0 vì nó khác null. **Chỗ đọc phải biết `kNoTabShown`:** `TerminalPane` (mọi `PaneTreeView` nhận `selected: false`; `IndexedStack` giữ tab sống nhưng không vẽ; chồng màn bắt đầu hoặc trạng thái trống lên trên), `ToolArea` (T8), ghi khôi phục (`selectedTab: null`), `ui.ls` (`selectedTab: null`, thêm khoá `mode`), `TerminalTabs._step` và `selectIndex`. Chỗ đọc qua `state.selected` tự đúng vì `selected` trả null: A12 `paneVisible`, dwell A4, `seenOnDesktop` của điện thoại, tiêu đề cửa sổ, mọi lệnh đóng / chia / chép / đổi tên. **Loại bỏ:** (1) `selectedId = null` khi còn tab: `_sync` tự điền tab đầu; (2) cờ "đang ở màn bắt đầu" tách khỏi `selectedId`: ⌘W, chia, đổi tên… sẽ tác động lên tab bị che. | Sót một chỗ đọc thẳng `selectedId` thì chỗ đó thấy số 0. Test từng chỗ (§11), Review Focus 1. |
| T6 | Chế độ lúc mở app | `layout.json` thêm khoá cấp trên cùng **`"mode": "ai"`**, chỉ ghi khi đang ở chế độ AI. Layout ở chế độ Terminal vì vậy giống hệt từng byte như trước. V1 và V2.0 bỏ qua khoá lạ cấp trên cùng. **Khi mở:** có `mode == "ai"` → chế độ AI; không có `mode` mà `selectedTab` là tab AI (layout của V2 trước V2-5b) → chế độ AI; còn lại → chế độ Terminal. Khôi phục xong mà chế độ AI không có tab AI nào được chọn → `showNone()`. Không có gì để khôi phục (lần đầu, khôi phục tắt, layout hỏng) → theo `new-tab-kind`. **`new-tab-kind`** giữ khoá và giá trị `terminal` / `ai` (bản cũ đọc vẫn đúng) nhưng đổi nghĩa: không còn quyết định ⌘T (T7), chỉ là "Mở ShellX ở chế độ" (Cài đặt › Chung, §8.1). Bước onboarding "Bạn muốn làm việc theo kiểu nào?" và thẻ chào một lần (V2-1 D4) ghi `new-tab-kind` **và** đổi chế độ ngay. | Ai chọn "Terminal" lúc onboarding vẫn mở lại ở chế độ AI nếu đã thoát khi ở đó (layout thắng): đúng nghĩa "mở lại như lúc thoát". |
| T7 | Lối vào | **Theo chế độ đang xem:** ⌘T (`new_tab`), nút `+` của dải đầu, nút của trạng thái trống. Chế độ Terminal mở tab terminal (B8 giữ: workspace SSH mở server); chế độ AI hiện màn bắt đầu. **Sang chế độ AI, hiện màn bắt đầu, focus ở ô nhập, không mở tab nào** (tab sinh ra khi gửi tin đầu, T22): ⌘⇧E (`new_ai_session`), bảng lệnh "Phiên AI mới", nút "Phiên AI mới" ở chân sidebar chế độ Terminal, mục "Phiên AI mới" của menu `+`. **"Tab terminal mới"** (bảng lệnh, menu `+`): sang chế độ Terminal và mở tab terminal. Nút `+` và mục "Tab mới trong workspace này" của tiêu đề workspace luôn mở tab terminal. **Cửa sổ trống lúc mở app** (`ensureTab`): chế độ Terminal không có tab terminal thì mở một tab như A1; chế độ AI thì hiện màn bắt đầu, không mở gì. **Mở lại phiên cũ** (hàng "Phiên trước" ở sidebar, mục "Lịch sử phiên" trong ⋯): mở tab AI mới ngay với `sessionId` (`session/load`, V2-1 D15), chọn nó, không qua màn bắt đầu. **Điện thoại** `ai.open`: như V2-2 D9 (tab không được chọn, agent chạy ngay), cộng `text` (T44). **Menu `+`:** chế độ Terminal bỏ mục "Tab terminal mới" (chỉ có khi `new-tab-kind = ai`, nay thừa); chế độ AI có "Phiên mới" (⌘T), "Mở thư mục…", "Tab terminal mới", "Kết nối SSH…", "Gắn tmux…". `AiOpener.newSession` thay bằng `showHome({folder, agent})` (chỉ hiện màn bắt đầu) và `start(AiStart)` (mở tab kèm tin đầu). | Ai quen ⌘⇧E mở tab ngay giờ phải gõ câu đầu trước. Đó là thay đổi đã duyệt. |
| T8 | Dock tool (V2-3) | **Chế độ Terminal:** như V2-3. **Chế độ AI, có phiên:** dock của workspace chứa tab AI, như hôm nay; nút 🧩 trên header phiên giữ. **Màn bắt đầu:** dock của workspace có `root` bằng thư mục ở chip dự án, với trạng thái mở / đóng / rộng V2-3 lưu cho workspace đó. Chip không phải dự án → không có dock; ⌘⇧B mờ. **Mở một tool khi đang ở chế độ AI** (bảng lệnh, Cài đặt › Dự án): workspace của tool có tab AI → chọn tab AI mới nhất của nó rồi mở dock; không có tab AI mà có `root` → màn bắt đầu với chip = `root` rồi mở dock; không có `root` → sang chế độ Terminal và làm như V2-3 D4 (tab gần nhất hoặc bảng "loose"). Sang chế độ AI thì bỏ `loose`. Sidebar AI không có nhóm Tool. | Thư mục chưa là dự án thì màn bắt đầu không có dock: một lần "Lưu thành dự án" (T27). |
| T9 | Điều hướng | ⌘1–9, Ctrl+Tab / Ctrl+Shift+Tab, ↑ / ↓ của sidebar và kế vị khi đóng đi theo **danh sách đang hiện của chế độ đang xem**. Chế độ Terminal: hàng tab terminal đang hiện (`visibleTabIds` của sidebar Terminal không còn tab AI). Chế độ AI: hàng phiên AI **đang mở** đang hiện của sidebar AI, trên xuống; bỏ hàng phiên trước và tiêu đề nhóm; từ màn bắt đầu, Ctrl+Tab chọn phiên đầu tiên. Khi chế độ AI đang xem, sidebar AI đăng ký bộ chọn kế vị của nó vào `closeSuccessorProvider`. | — |
| T10 | Sidebar chế độ AI | Từ trên xuống: (1) hàng **"+ Phiên mới"** (`newSession`), ⌘⇧E ở bên phải (ẩn nhãn phím khi hàng không đủ chỗ, T49), sáng khi màn bắt đầu đang hiện; (2) **bộ lọc** (T15); (3) **DỰ ÁN**; (4) **GẦN ĐÂY**; (5) nhóm **"Chưa có thư mục"** khi có tab AI chưa có thư mục (phiên cũ, V2-1 D5). Không có chân sidebar: thẻ chào V2-1 và hàng "Phiên AI mới · 🧩" chỉ ở chế độ Terminal. Danh sách ảo hoá, dựng lười; hàng cao như hàng sidebar A2. | — |
| T11 | Dự án, Gần đây và nhóm | Một **nhóm** là một thư mục. So đường dẫn sau `p.normalize`; Windows không phân biệt hoa thường. Nhóm là **dự án** khi một workspace **cục bộ** (không SSH, B8) có `root` bằng thư mục đó; tên nhóm là tên workspace. Mọi nhóm khác nằm ở **Gần đây**, tên là tên thư mục cuối. Phiên AI thuộc nhóm của `cwd` của nó, không theo thành viên workspace. Dự án hiện kể cả khi chưa có phiên. **Gần đây** = thư mục của tab AI đang mở mà không là dự án, cộng mục của `ai_recent_folders` (T25) không là dự án. Thứ tự là thứ tự của `ai_recent_folders` (mới nhất trên); thư mục của tab đang mở mà không có trong danh sách đó xếp cuối. **Đầu nhóm:** `chevronRight` (gập) / `expand` (mở), `folder`, tên, nhánh git (`branch`, T28) ở bên phải, chấm cảnh báo khi nhóm đang gập mà có phiên cần bạn (vai trò biểu tượng ở §4.0). Tên lấy phần bề rộng còn lại và cắt cuối; nhánh tối đa 40 % bề rộng hàng, cắt cuối (T49). Rê chuột: `newSession` ("+") thay chỗ nhánh, nghĩa là "Phiên mới trong {project}" (màn bắt đầu với chip là thư mục này). Bấm đầu nhóm để gập / mở. Mặc định mở khi nhóm có phiên đang mở hoặc chứa phiên đang chọn; gập / mở chỉ nhớ trong lần chạy. **Vì sao Gần đây là thư mục, không là danh sách phiên:** phiên đang mở đã nằm dưới thư mục của nó và có bộ lọc; thư mục chưa là dự án cần một chỗ, và điện thoại cũng hiện "dự án + thư mục AI gần đây" (đã duyệt). | Phiên chạy trong thư mục con của một dự án nằm ở Gần đây, không nằm dưới dự án đó. |
| T12 | Thứ tự và giới hạn | Dự án theo thứ tự workspace (sắp ở chế độ Terminal hoặc Cài đặt › Dự án). Trong nhóm: **phiên đang mở** trước, mới tạo nhất ở trên. Thứ tự là id tab tổng hợp giảm dần, nên tab khôi phục giữ thứ tự cũ và hàng không nhảy khi trạng thái đổi. Sau đó là hàng **"Phiên trước · {agent}"** (T13). Mỗi nhóm hiện tối đa 8 phiên đang mở rồi "Xem thêm {count}". Gần đây hiện tối đa 8 nhóm rồi "Xem thêm {count}". | Ai có hàng chục phiên đang mở phải bấm "Xem thêm". |
| T13 | Phiên trước trong sidebar | Hàng "Phiên trước · {agent}" (`history`, `chevronRight` / `expand`) nằm cuối mỗi nhóm đang mở. **Chỉ tải khi người dùng mở hàng này**, không tải khi chỉ mở nhóm: duyệt danh sách không chạy agent nào. **Agent:** agent của phiên mới nhất đang mở trong nhóm, không có thì agent mặc định. "▾" đổi sang agent khác của Cài đặt › Agents; lựa chọn nhớ theo nhóm trong lần chạy. **Nguồn:** `session/list {cwd}` qua trình liệt kê (T14). Hiện 5 hàng đầu (tiêu đề hoặc "Phiên chưa đặt tên", ngày giờ ngắn); "Xem thêm" mở thêm 20, lấy trang kế bằng `nextCursor` khi cần. Bỏ phiên trùng `sessionId` với một tab đang mở cùng agent. Bấm một hàng: mở tab AI mới tiếp phiên đó (T7). Kết quả giữ 60 s theo (agent, thư mục); mở lại hàng sau 60 s thì tải lại. **Trạng thái:** đang tải → "Đang tải…"; agent chưa cài, thiếu Node hoặc cần đăng nhập → "Phiên trước hiện khi {agent} đã sẵn sàng."; agent không có `session/list` → "{agent} không liệt kê phiên."; lỗi → "Chưa tải được phiên trước. Thử lại". | Lần mở đầu chậm 2–8 s khi phải chạy agent (T14). |
| T14 | Trình liệt kê lịch sử | `AiHistoryLister` (thuần Dart, `shellx_ai/host`), hàm `list(agent, cwd, {cursor})`. **(1)** Có runtime **sẵn sàng hoặc đang chạy** của cùng agent → dùng client của nó; `AiRuntime.listSessions` nhận thêm `cwd` (mặc định là thư mục của phiên). **(2)** Không có → **một tiến trình riêng** cho agent đó: resolve như runtime (cùng `AgentLauncher`, cùng env login shell, không có biến `SHELLX_*`), chạy trong thư mục đang hỏi, `initialize` (30 s). Tiến trình này **không bao giờ** gọi `session/new`, `session/load`, `authenticate` hay gửi prompt. Agent không khai `sessionCapabilities.list` → "không liệt kê". **Giới hạn:** tối đa 1 tiến trình mỗi agent, 2 cho cả app; yêu cầu của một agent chạy lần lượt; mỗi `session/list` ≤ 15 s. **Dừng** sau **60 s** không có yêu cầu, khi agent bị tắt hoặc xoá trong Cài đặt, và khi thoát app, theo đường dừng của runtime (đóng stdin, chờ 2 s, `killProcessTree`). Ghi vào `ai/running.json` như runtime, để dọn sau crash (V2-1 §6). `-32000` (cần đăng nhập) → "chưa sẵn sàng", không mở thẻ đăng nhập. **Task 1** ghi lại adapter Claude có theo `cwd` của `session/list` khi tiến trình chạy ở thư mục khác hay không. Không theo thì trình liệt kê khởi động lại tiến trình trong thư mục được hỏi (vẫn tối đa 1 mỗi agent). Dùng chung cho sidebar desktop và `ai.folder.history` của điện thoại (T43). **Loại bỏ:** (1) đọc thẳng tệp phiên của agent: ShellX không đọc dữ liệu của agent, và mỗi agent lưu một kiểu; (2) chỉ cho xem lịch sử khi thư mục đã có phiên đang mở. | Một tiến trình Node (khoảng 100–200 MB) sống tối đa 60 s sau lần xem lịch sử. |
| T15 | Bộ lọc trạng thái | Một hàng ba nút **biểu tượng + số**, vì sidebar 220 px không đủ chỗ cho ba nhãn chữ tiếng Việt, nhất là với chữ đơn cách (T49): Đang chạy = `filterRunning` (`CupertinoIcons.play_fill`), Cần bạn = `filterNeedsYou` (`CupertinoIcons.hand_raised_fill`), Xong = `filterDone` (`CupertinoIcons.checkmark`). Ba hình khác nhau, nên không chỉ dựa vào màu. Mỗi nút có tooltip, nhãn đọc màn hình "Lọc: {nhãn}, {n} phiên", trạng thái chọn tô gradient (chip của A). Chọn một; bấm lại để bỏ. Nút có số 0 thì mờ, trừ khi đang chọn. **Trạng thái** lấy từ runtime (`aiRemoteStateOf`, gồm cả agent tuỳ chỉnh): Đang chạy = `running`; Cần bạn = `needs_input`; Xong = `idle` và `aiLastEndedTurn` khác null. **Đang lọc:** dưới hàng là tiêu đề "{nhãn} · {n}" và "Bỏ lọc"; danh sách thành **một danh sách phẳng** các phiên khớp, dòng hai của mỗi hàng thêm tên dự án hoặc thư mục; không có nhóm, không có phiên trước. Không phiên nào khớp: câu riêng cho từng nút (§8.2). Bộ lọc chỉ nhớ trong lần chạy. | Phiên chưa chạy (khôi phục mà chưa mở) không thuộc nút nào. |
| T16 | Trống, thư mục mất (sidebar) | Không có dự án, không có Gần đây: "Chưa có dự án. Chọn một thư mục để bắt đầu." và nút "Mở thư mục…" (`folderOpen`, T26). Nhóm không có phiên đang mở: "Chưa có phiên nào ở đây." trên hàng phiên trước. Dự án có `root` không còn: đầu nhóm mờ, `warning` thay `folder`, ghi "Không thấy thư mục", không có "+"; phiên trong đó vẫn hiện, pane của chúng có thẻ "Thư mục dự án không còn" (T29). Mục Gần đây không còn: bị bỏ khỏi danh sách (T25). | — |
| T17 | Hàng phiên | Dòng 1: chấm trạng thái (chấm vẽ, không phải biểu tượng; cần bạn: màu cảnh báo; đang chạy: accent; xong: ok; còn lại: mờ) và tiêu đề tab (V2-1 D2). Dòng 2: "{trạng thái} · {agent}" như hàng AI hôm nay (`ui/terminal/session_tab_row.dart:1066-1121`). Hai dòng cắt cuối, tooltip đủ chữ (T49). Dấu chưa đọc A4 như hàng terminal. Bấm: chọn (T5a). **Menu chuột phải:** "Đổi tên…" (`edit`, A2), "Đóng phiên" (`remove`; hỏi lại khi lượt đang chạy, V2-1), "Hiện trong Finder" / "Hiện trong File Explorer" (`folder`), "Chép đường dẫn" (`copyPath`). F2 đổi tên; ⌘W đóng phiên đang xem. Không kéo thả trong chế độ AI. Đọc màn hình: "{title}, {agent}, {state}, {project}". | — |
| T18 | Màn bắt đầu | Cột giữa vùng nội dung, từ trên xuống: lời chào theo giờ của máy ("Chào buổi sáng" 05:00–11:59, "Chào buổi chiều" 12:00–17:59, "Chào buổi tối" giờ còn lại; kiểu `display` của A); dòng phụ "Hôm nay {agent} làm gì trong {project}?" (chưa chọn dự án: "Chọn một dự án rồi nói {agent} cần làm gì."); **thẻ ô nhập** (T19), rộng tối đa 720 px. Nền dùng **nêm / kính của A** sau lời chào (A cho phép ở màn trống và ở thẻ ô nhập AI). Dưới thẻ có một dòng ghi chú khi cần: thư mục quá rộng (T23), thư mục không còn, không có agent. Không có gợi ý soạn sẵn, không có danh sách phiên (sidebar đã có). Bản nháp (chữ, ảnh, `@`, chip) giữ trong bộ nhớ khi rời màn và quay lại trong cùng lần chạy; xoá khi gửi. | Không chào bằng tên: desktop không biết tên người dùng. |
| T19 | Thẻ ô nhập dùng chung | Một widget `AiComposerCard` (thẻ của A, góc 16, được dùng kính theo luật của A, A29: trên bản ghi của trang phiên thì `blur: false`; chữ nằm thẳng trên kính chỉ từ `textPrimary` trở lên) cho cả màn bắt đầu lẫn phiên. Từ trên xuống: hàng ảnh (nếu có); ô chữ (2 dòng, giãn tới 140 px); **hàng điều khiển trong thẻ**: nút `@` (`mention`), nút `/` (`commands`), các chip, phần trăm ngữ cảnh (chỉ trong phiên), nút Gửi / Xếp hàng / Dừng / Dừng hẳn (nút chính gradient của A; `send`, `queue`, `stop`). Hàng điều khiển xuống dòng thay vì tràn; nút Gửi luôn ở cuối hàng cuối (T49). **Chip trên màn bắt đầu:** Dự án (`folder`) ▾ · agent (`ai`) ▾ · Chế độ ▾ · Model ▾ (· `mic`: T41); ▾ là `expand`. **Chip trong phiên:** chip cấu hình sống như V2-1 D11 (Chế độ, Model, Suy nghĩ, tuỳ chọn khác); dự án và agent nằm ở header (T30). Mọi phím và luật của ô nhập theo V2-1 D16 và §1.4 giữ nguyên: Enter, Shift+Enter, IME, Esc dừng, hàng đợi 5, `_Unchecked` cho ảnh. | — |
| T20 | Chip dự án và agent | **Dự án:** mở bộ chọn (T24). Chip hiện `folder`, tên và nhánh (T28); khi hàng chật, nhánh ẩn trước rồi tên cắt cuối (T49). **Đặt sẵn** khi màn bắt đầu hiện, lấy cái đầu tiên có được: (1) thư mục của nhóm, khi mở từ "+" của nhóm hoặc "Phiên mới trong dự án này"; (2) thư mục của phiên, khi mở từ "Phiên mới với…" trên header; (3) thư mục của phiên AI hiện gần nhất trong lần chạy; (4) mục đầu của `ai_recent_folders`; (5) dự án đầu tiên theo thứ tự workspace. Bỏ qua thư mục quá rộng (T23) và thư mục không còn. Không có gì: chip ghi "Chọn dự án" và Gửi mờ. **Agent** ("Claude ▾") là **bộ chọn agent theo phiên**: mọi agent của Cài đặt › Agents (V2-1 D23), mỗi agent kèm trạng thái (Sẵn sàng / Chưa cài / Thiếu Node / Cần đăng nhập / Đang kiểm tra…). Chọn được cả agent chưa sẵn sàng: phiên sẽ hiện thẻ Cài đặt / Đăng nhập như V2-1. Mục cuối: "Cài đặt › Agents". Mặc định là agent mặc định (V2-1 D23), hoặc agent của phiên khi mở từ "Phiên mới với {agent}". Chọn ở chip **không** đổi agent mặc định. | Ai hay dùng một agent không phải mặc định phải đổi mặc định trong Cài đặt. |
| T21 | Chế độ, model trước khi có agent | **Bộ đệm:** khoá UI mới **`ai_agent_options`** (cửa sổ sở hữu, thêm vào `SettingKeys.all` và `UiSettingKeys` như T25), mỗi agent một JSON `{"agent", "options": [{"id", "name", "cat", "kind", "value"?, "choices": [{"v", "n"}]}]}`. Chỉ giữ tuỳ chọn nhóm `mode` (`category == "mode"` hoặc `id == "mode"`) và `model`; ≤ 40 lựa chọn mỗi tuỳ chọn; tên ≤ 60 ký tự. Ghi khi một runtime của agent đó báo `configOptions` (sau `session/new`, `session/load`, `config_option_update`) mà khác bản đang lưu. **Không bao giờ lưu** lựa chọn bật chế độ không cần duyệt (`aiTurnsOnNoApproval`, `aiIsNoApprovalMode`), và bỏ `value` khi nó là chế độ đó. **Chip Chế độ / Model** trên màn bắt đầu dựng từ bộ đệm. Giá trị hiện là giá trị đã nhớ của agent (`rememberedConfig`, V2-1 D11) nếu nó có trong danh sách, không thì `value` của bộ đệm. Chọn → `rememberConfig` như chip phiên hôm nay; phiên mới áp nó qua `preferredConfig` sau `session/new` và trước tin đầu (`_applyPreferred`). Chưa có bộ đệm (agent chưa chạy lần nào), hoặc agent chỉ có `modes` kiểu cũ → chip **mờ** "Chế độ" / "Model", gợi ý "Có sau lần đầu chạy {agent}"; chip thật hiện khi phiên chạy. Màn bắt đầu **không bao giờ** liệt kê chế độ không cần duyệt. "Bỏ qua mọi quyền" chỉ bật được ở chip của phiên, qua hộp xác nhận (V2-1 D11, R6). **Loại bỏ:** chạy trước agent khi màn bắt đầu hiện để lấy tuỳ chọn thật — tốn một tiến trình mỗi lần mở màn, và `session/new` để lại phiên rỗng trong lịch sử của agent. | Model mới của agent chỉ hiện trên màn bắt đầu sau một phiên. |
| T22 | Tin đầu tạo phiên (DT) | Bấm Gửi trên màn bắt đầu: **(1)** kiểm: thư mục còn, agent có, có chữ hoặc ảnh. **(2)** Ghi thư mục vào Gần đây (T25). **(3)** `openAiTab(agent, cwd, select: true, workspace: aiWorkspaceForFolder(cwd))`. `aiWorkspaceForFolder`: workspace có `root` = `cwd`, không có thì workspace của tab AI cùng `cwd`, không có thì Default. **(4)** Bản nháp thành **`AiFirstMessage`** (chữ, ảnh, `@`), giữ theo id pane. **(5)** Pane hiện, runtime chạy (V2-1 B11). Ô nhập của pane **lấy và xoá** tin đầu ở lần dựng đầu, rồi gửi qua đường `_send` thường: xếp hàng tới khi agent sẵn sàng; ảnh gửi trước khi biết agent nhận ảnh đi qua `_Unchecked`, và quay lại ô nhập nếu agent không nhận. Tin đầu gửi **đúng một lần**. Pane đóng trước khi gửi thì tin bỏ theo. `send` trả false (agent đã lỗi hoặc cần đăng nhập trước khi ô nhập dựng) → tin quay về ô nhập của phiên, kèm ghi chú "Agent chưa nhận tin lúc này." (V2-1). `@` trên màn bắt đầu dùng chỉ mục của thư mục ở chip (`aiProjectFilesProvider`, không cần agent). `/` mờ, gợi ý "Lệnh của agent có sau khi phiên bắt đầu"; gõ `/…` vẫn gửi như chữ. | — |
| T23 | Thư mục quá rộng | Luật `aiFolderIsBroad` (home, thư mục trên home, gốc ổ đĩa; I-1) giữ. Thư mục quá rộng không bao giờ được đặt sẵn (T20) và không bao giờ được ghi vào Gần đây (T25). Người dùng vẫn chọn được (bộ chọn, "Mở thư mục…", gõ đường dẫn): chip có `warning`, dưới thẻ có dòng "{folder} là thư mục home hoặc gốc ổ đĩa: hoàn tác và @ tắt ở đây." và "Chọn thư mục khác". Gửi vẫn được: người dùng tự chọn thì làm theo, như I-1. Hộp chọn của hệ điều hành mở ở home, bấm "Chọn" ngay là ra home: dòng này chặn nhầm lẫn đó mà không thêm bước. | Ai thật sự làm việc ở `~` phải chọn lại mỗi lần. |
| T24 | Bộ chọn dự án | Popover (menu của A, rộng 380 px, cao tối đa 460 px) neo ở chip; cũng dùng trong thẻ "Chọn thư mục dự án" (T29). Từ trên xuống: **ô tìm** (`search`; có focus sẵn; khớp tên và đường dẫn, không phân biệt dấu nhờ `foldForSearch` của bảng lệnh); **"Dự án"**: `folder`, tên, đường dẫn (home viết `~`, cắt ở giữa), nhánh; **"Thư mục gần đây"**: `folder`, tên thư mục, đường dẫn, nhánh, khi rê chuột có nút "Lưu thành dự án" (`saveProject`) và "Bỏ khỏi gần đây" (`remove`); cuối cùng **"Mở thư mục…"** (`folderOpen`, T26). Trong mỗi hàng: tên cắt cuối, đường dẫn cắt ở giữa, nhánh cắt cuối và ẩn trước tiên khi hàng chật (T49). Chữ gõ là đường dẫn tuyệt đối (hoặc `~/…`) của một thư mục có thật → hàng đầu "Dùng thư mục {path}" (thay ô gõ của B7). Phím: ↑ / ↓, Enter chọn, Esc đóng, ⌘O / Ctrl+O là "Mở thư mục…" (chỉ trong popover). Dự án có `root` không còn: mờ, ghi "Không thấy", có "Sửa trong Cài đặt › Dự án". Trống: "Chưa có dự án hay thư mục gần đây." | — |
| T25 | Thư mục gần đây | Khoá UI mới **`ai_recent_folders`**, cửa sổ sở hữu, thêm vào `SettingKeys.all` và `UiSettingKeys`. Danh sách chuỗi, mới nhất trước; mỗi phần tử là JSON `{"p": "<đường dẫn tuyệt đối đã chuẩn hoá>", "at": <ms>}`. **Tối đa 20.** Trùng (so như T11) thì đưa lên đầu. **Ghi khi một phiên bắt đầu trong thư mục đó:** gửi từ màn bắt đầu; `ai.open` của điện thoại; mở lại phiên cũ; chọn thư mục cho tab đã có (thẻ thư mục T29, `ai.folder` của B18). Không ghi khi chỉ chọn ở chip mà không gửi; không ghi thư mục quá rộng hay đường dẫn dài hơn 1 024 byte UTF-8. **Lần đầu V2-5b** (khoá chưa có): gieo từ thư mục của các tab AI khôi phục, nếu còn và không quá rộng. **Thư mục mất:** kiểm `Directory.exists` khi bộ chọn mở, khi sidebar AI hiện (tối đa 1 lần mỗi 60 s), và lúc khởi động (sau khung hình đầu); ≤ 50 lần kiểm mỗi vòng, mỗi lần ≤ 2 s. Kết quả `false` → **xoá khỏi danh sách**; hết giờ hay lỗi → giữ (ổ mạng chậm). "Lưu thành dự án" giữ mục: nó ẩn khi đã là dự án, và hiện lại nếu dự án bị xoá. "×" bỏ tay. | Thư mục trên ổ rời biến khỏi danh sách khi ổ chưa cắm; mở lại bằng "Mở thư mục…". |
| T26 | "Mở thư mục…" (đảo V2-1 B7) | Hộp chọn thư mục của hệ điều hành qua **`file_selector` 1.1.0**, ghim đúng bản, cùng `file_selector_macos` 0.9.5+1 và `file_selector_windows` 0.9.3+6 (ghim như `webview_flutter`). Task 1 kiểm `pub get` và build trên Flutter 3.41.4. Gọi `getDirectoryPath(initialDirectory: thư mục cha của mục Gần đây đầu tiên, không có thì home; confirmButtonText: "Chọn"; canCreateDirectories: true)`. Huỷ thì không đổi gì. **macOS:** app không sandbox (`com.apple.security.app-sandbox = false` ở cả Debug và Release), nên **không thêm** entitlement `files.user-selected.*`, vì nó chỉ có nghĩa khi có sandbox. Hardened runtime không cần entitlement nào cho `NSOpenPanel`. Thư mục trong Desktop, Documents, Downloads: lần đầu agent đọc, macOS hỏi quyền cho ShellX như hôm nay (§13). **Windows:** `IFileDialog` (COM), Windows 10 trở lên, không đổi manifest. Lỗi mở hộp: toast "Không mở được hộp chọn thư mục."; log chỉ `runtimeType`. Seam `aiPickFolderProvider` để test không mở hộp thật. **Lý do đảo B7:** chính B7 ghi giá nếu sai là "thêm `file_selector` sau". Nay mỗi phiên mới cần một thư mục ngay từ màn bắt đầu, và gõ đường dẫn là rào cản lớn nhất với người không dùng terminal. | Thêm một plugin native ghim; nâng Flutter thì nâng cùng. |
| T27 | Lưu thành dự án | Có ở: hàng Gần đây của bộ chọn, menu đầu nhóm Gần đây, menu chip dự án trên header (T30). Việc làm: `createFor(name: tên thư mục)` rồi `setRoot(id, path)`; chuyển mọi tab AI có `cwd` này vào workspace mới (để dock theo dự án); toast "Đã lưu “{name}” thành dự án.". Workspace mới cũng hiện ở chế độ Terminal: "dự án" của Cài đặt › Dự án và workspace là một khái niệm. Thư mục quá rộng cũng lưu được (workspace terminal ở `~` là hợp lý); phần AI vẫn theo T23. | Tên trùng workspace khác: người dùng đổi tên trong Cài đặt. |
| T28 | Nhánh git | Đọc bằng `GitHeadReader` của `shellx_agent`: đi lên tới `.git`, theo `gitdir:` của worktree, ≤ 500 ms, LRU 64; trả nhánh, hoặc SHA 7 ký tự khi detached. **Không bao giờ chạy git** trên dự án. Provider của cửa sổ `aiFolderBranchProvider(path)` giữ kết quả; hỏi lại khi cần hiện mà kết quả cũ hơn 10 s, khi cửa sổ được focus, và khi một lượt kết thúc trong thư mục đó. Hết giờ → giữ giá trị cũ. Không phải repo → không hiện gì. **Hiện ở:** đầu nhóm sidebar AI, hàng bộ chọn, chip dự án, header phiên, listing cho điện thoại (`branch`, T42). `TerminalTab.gitBranch` của tab AI vẫn null, nên chỗ đọc của chế độ Terminal không đổi. | — |
| T29 | Thẻ "Chọn thư mục dự án" | `AiFolderCard` (ô gõ đường dẫn của B7) thay bằng thẻ chứa **bộ chọn dự án** (T24) dạng danh sách, giữ tiêu đề "Chọn thư mục dự án" và dòng "Agent làm việc trong thư mục này.". Dùng ở: tab AI chưa có thư mục (phiên cũ); nút "Chọn thư mục" của thẻ "Thư mục dự án không còn" (V2-1 §4.5). Chọn một thư mục: như `_useFolder` hôm nay (thư mục khác → phiên mới; cùng thư mục → mở lại phiên của nó), rồi ghi Gần đây. Huỷ / Esc như hôm nay. **Cài đặt › Dự án:** ô "Thư mục dự án" của dự án cục bộ có thêm nút "Chọn…" mở cùng hộp chọn (T26); ô gõ giữ. | — |
| T30 | Header phiên | Cao 40 px (từ 34), hoặc cao hơn nếu dòng chữ của A cần. Trái sang phải: **tiêu đề phiên** (cắt cuối, tooltip đủ chữ); **chip dự án** (`folder` + tên; tooltip là đường dẫn; menu: "Phiên mới trong dự án này" (`newSession`), "Hiện trong Finder" / "Hiện trong File Explorer" (`folder`), "Chép đường dẫn" (`copyPath`), "Lưu thành dự án" (`saveProject`) khi chưa là dự án); **nhánh** (`branch` + tên, T28); **chip agent** (`ai` + "Claude" + `expand`; menu: "Phiên mới với {agent}" cho mọi agent, mở màn bắt đầu với thư mục này và agent đó; "Cài đặt › Agents"); **trạng thái** (A12 kèm đồng hồ, `aiStatusOf`, vùng sống như hôm nay). Bên phải: Panel Thay đổi · Tệp (`sidePanel`), Terminal (`terminal`), Tool (`tool`, V2-3), Phóng to (`maximize`, khi tab có hơn một pane), ⋯ (`more`); cả năm là vai trò của A. **"Lịch sử phiên" (`history`) chuyển từ nút riêng vào ⋯**, cạnh Cài đặt › Agents, Khởi động lại agent, Xem log. **Khi thiếu chỗ** (đo bằng bề rộng thật của chữ, không có ngưỡng px cố định): trạng thái và các nút bên phải không bao giờ bị bỏ; bỏ nhánh trước, rồi chip dự án, khi tiêu đề sẽ hẹp hơn bề rộng 12 ký tự của font đang dùng; tooltip của tiêu đề vẫn ghi dự án và nhánh (T49). | Header cao thêm 6 px. |
| T31 | Bộ chọn agent theo phiên | Một phiên giữ agent của nó: một tiến trình ACP (V2-1 D3). "Theo phiên" nghĩa là chọn agent cho **mỗi phiên mới**: ở chip của màn bắt đầu (T20) và "Phiên mới với {agent}" trên header (T30). Cài đặt › Agents vẫn giữ agent mặc định. | Muốn đổi agent giữa phiên: mở phiên mới, như hôm nay. |
| T32 | Hội thoại | **Tin người dùng:** bong bóng canh phải, rộng tối đa 80 % cột (cột 760 px giữ), nền nổi của A (`navy700`), không đổ bóng (A44: dòng thời gian không có `BoxShadow`), góc 16. Bỏ nhãn "Bạn" ở trên. Tin từ điện thoại có dòng nhỏ "Bạn · từ điện thoại" phía trên bong bóng (B24 giữ, cả ở hàng xếp hàng). Chip `@` và ảnh nằm trong bong bóng như hôm nay. **Chữ agent:** rộng hết cột, không nhãn, markdown như V2-1 D17. **Thẻ tool:** một dòng gọn (biểu tượng theo kind là vai trò của A, động từ và đối tượng cắt ở giữa, +/− của lệnh sửa, trạng thái bên phải không bao giờ bị cắt: "chờ", "chờ bạn", "đang chạy · 2,1 s", `check` của A cho xong (như hôm nay), "lỗi · mã 1"…), **gập mặc định**. Luật tự mở đổi: chỉ mở khi **đang chờ quyền** (mọi kind mở được); không còn tự mở lệnh chạy xong (đổi V2-1 §4.2). Bấm thẻ để mở diff hoặc đầu ra như cũ. **Suy nghĩ:** một dòng mờ gập sẵn "Suy nghĩ ›", "Đang suy nghĩ…" khi đang chạy. Dòng hết lượt, thẻ thông báo, câu hỏi: giữ, theo kiểu của A. **Không** gộp nhiều thẻ tool thành nhóm (việc sau). | Muốn đọc đầu ra lệnh phải bấm một lần. |
| T33 | Giữ nguyên | Mọi hành vi V2-1 và V2-2b của trang phiên: thanh xin quyền (phím 1–9, Esc, không bao giờ tự cho phép, hỏi trước khi bật chế độ không cần duyệt); hàng đợi 5 tin; Dừng / Dừng hẳn (Esc, 10 s); `@` (chỉ mục theo `.gitignore` của ShellX); `/` (lệnh của agent); ảnh (dán, kéo thả, ≤ 5, ≤ 10 MiB, `_Unchecked`); kế hoạch; câu hỏi elicitation; panel Thay đổi / Tệp (268 px); pane Terminal 72 / 28; thẻ khôi phục; "Bạn · từ điện thoại"; hoàn tác từ điện thoại; mọi thứ điện thoại thấy. Test V2-1 và V2-2b hiện có phải xanh; chỉ sửa test ở chỗ T30 và T32 cố ý đổi. | — |
| T34 | Thanh dưới và route (ĐT) | **Thanh dưới của A**, mục đang chọn là ô nổi gradient, ba mục: **Máy tính** (`computer`) · **Trợ lý AI** (`ai`) · **Cài đặt** (`settings`). Nhãn một dòng, không xuống dòng; khi chữ hệ thống lớn thì co theo luật của A (T49). **Route:** `HomeRoute` mới ở gốc: `AutoTabsRouter`, `homeIndex: 0`, dựng lười, là route `initial`, guard `updateGuard` và `authGuard`; con là `MachineListRoute`, `AiHomeRoute` (mới), `SettingsRoute`. `AutoTabsRouter` không tạo navigator lồng: trang con vẫn dưới navigator gốc, nên luật "một chồng phẳng" của `app_router.dart` giữ cho mọi trang đẩy lên và mọi hộp thoại. Đẩy **đè lên thanh dưới** (toàn màn) bằng `context.router.root.push`: `TerminalRoute`, `AiSessionRoute`, `ToolRoute`, `QrScannerRoute`, `DeleteAccountRoute` và hai route mới `AiProjectRoute`, `AiNewSessionRoute`. `session_enforcer`: đăng nhập xong thì `replaceAll([HomeRoute()])`. **Trang máy** bỏ nút ⚙ (Cài đặt là một mục); trở về mục Máy tính thì làm mới danh sách, như lúc đóng Cài đặt hôm nay. Back Android ở mục 2, 3 → về mục 1; ở mục 1 → thoát như cũ. Mở app: luôn ở mục Máy tính. **Thông báo:** `popUntilRouteWithName(HomeRoute.name)`; thông báo AI thì chọn mục Trợ lý AI và máy của thông báo trước khi đẩy trang phiên. **B21:** dòng AI trên thẻ máy chỉ giữ kênh khi trang máy **đang hiện**, tức là route trên cùng **và** mục Máy tính đang chọn (`IndexedStack` giữ trang sống khi ở mục khác). Chạm dòng: đúng một phiên cần bạn → mở phiên đó như cũ; không thì → mục Trợ lý AI với máy đó (thay bộ chọn). **Huy hiệu** trên mục Trợ lý AI: tổng số phiên cần bạn trong các listing app đang giữ, hiện "9+" khi quá 9; không mở kênh mới chỉ vì huy hiệu. | Đổi route là thay đổi lớn nhất của app mobile: test điều hướng (§11). |
| T35 | Trang Trợ lý AI: máy | Đầu trang: tiêu đề "Trợ lý AI" và **chip máy** (`computer`, chấm online, tên cắt cuối, `expand`). Bấm chip → sheet các máy đã ghép đôi; máy offline mờ, không chọn được; nhãn "Dùng gần nhất". Chỉ một máy thì chip không bấm được. Máy đã chọn lưu trong `AppSettings`, khoá mới `settings_ai_machine`. Mặc định: máy dùng gần nhất (`lastMachineId`) nếu đang online, không thì máy online đầu tiên. **Dữ liệu:** workspace của máy đó (`WorkspaceRegistry`): kết nối, `session.list {desktop: true}` khi chưa biết `ai`, rồi `holdAiListing()` **chỉ khi** mục đang hiện và app ở trước, như B21. Nhả khi rời mục, khi app vào nền, khi đổi máy. Kéo xuống: hỏi lại listing. **Trạng thái:** chưa ghép máy nào → "Ghép đôi một máy tính để dùng Trợ lý AI." và nút "Quét mã QR" (`scanQr`); máy offline → "{name} đang offline. Mở ShellX trên máy đó rồi thử lại."; desktop cũ → `aiUpdateDesktop`; không có cửa sổ phục vụ → `aiUnavailable`; đang kết nối → vòng xoay. | — |
| T36 | Trang Trợ lý AI: danh sách | Từ trên xuống: **Phiên đang mở**: mọi phiên của listing, phiên cần bạn trước, rồi theo thứ tự listing (desktop gửi theo thứ tự sidebar AI, T12); 5 hàng rồi "Xem tất cả ({count})"; hàng như nhóm AI của bộ chọn phiên (`ai`, tiêu đề, "{agent} · {state}" kèm tên dự án, việc đang chờ; mọi dòng cắt cuối). **Dự án:** khoá `ws:`. **Gần đây:** khoá `path:` và mọi khoá khác. **Chưa có thư mục:** phiên không có `cwd`. Hàng thư mục: `folder`, tên (cắt cuối), đường dẫn (mờ, một dòng, cắt ở giữa), nhánh (`branch`, T42; ẩn trước khi hàng chật); bên phải "{n} phiên" (không bao giờ bị cắt), chấm cảnh báo khi có phiên cần bạn, `chevronRight`. Ghép phiên với thư mục bằng `session.cwd == folder.path` (khoá nối mà V2-2b B17 đã dùng). Chạm thư mục → `AiProjectRoute`. Cuối trang, ngay trên thanh dưới: **ô nhập mở phiên** (T38). Không có thư mục nào: `aiNewNoFolders` (chữ mới, §8.1). | — |
| T37 | Trang dự án (ĐT) | `AiProjectRoute(agentId, machineName, folderKey)`; `agentId` là id máy như ở mọi route của app mobile. Header: quay lại (`back` của A), tên, đường dẫn (cắt ở giữa), nhánh (`branch`). **Đang mở:** phiên có `cwd` này. **"Phiên trước · {agent} ▾":** `ai.folder.history` (T43) khi listing có `folder_history`; trang 50 (B17), "Tải thêm". Agent: agent của phiên mới nhất đang mở ở đây, không có thì `default_agent`; "▾" đổi sang agent khác của listing. Bỏ mục trùng `acp` với phiên đang mở. Chạm một mục: `ai.open {resume}` như B17 (desktop mở tab mới, không chọn) rồi đẩy trang phiên. Listing không có `folder_history` (desktop V2-2b trở về trước) → "Cập nhật ShellX trên máy tính để xem phiên trước ở đây."; `not_ready` → "Thiết lập {agent} trên máy tính để xem phiên trước."; `no_list` → "{agent} không liệt kê phiên.". Cuối trang: ô nhập mở phiên, chip dự án cố định là thư mục này. Khoá thư mục biến khỏi listing khi đang ở trang → "Máy tính không còn đưa thư mục này.", ô nhập mờ. | — |
| T38 | Ô nhập mở phiên (ĐT) | Một widget dùng ở trang Trợ lý AI, trang dự án và `AiNewSessionRoute`. Route này thay sheet "Phiên AI mới" của V2-2 ở hai chỗ: bộ chọn phiên của trang máy và bảng chọn AI. Hình: thẻ của A; ô chữ 1–6 dòng ("Nhắn cho {agent}…"); hàng chip: **dự án** (`folder` + tên + `expand`; sheet "Dự án" / "Gần đây", chỉ có khoá listing đưa ra), **agent** (`ai` + tên + `expand`; sheet các agent của listing; agent chưa sẵn sàng thì mờ, ghi "cài trên máy tính"), **`mic`** (T41), nút Gửi gradient (`send`). Biểu tượng và nút Gửi không co; chip dự án và chip agent chia phần còn lại và cắt cuối (T49). Không có ảnh, `@`, chế độ, model trước khi có phiên: thêm sau trong trang phiên (B11, B12, B13). **Đặt sẵn:** dự án = khoá đã dùng lần trước trên máy đó (`settings_ai_last_folder`: JSON máy → khoá, ≤ 20 máy) nếu listing còn khoá đó, không thì khoá `ws:` đầu tiên, không thì khoá đầu tiên; agent = `default_agent` nếu sẵn sàng, không thì agent sẵn sàng đầu tiên. **Gửi khi listing có `open_prompt`:** **một** `ai.open {agent, folder, text}` (T44); có `sid` → đẩy trang phiên (khoá `ai:{máy}/{sid}`), xoá ô. **Gửi khi không có `open_prompt`:** `ai.open` không kèm chữ; có `sid` → ghi chữ vào `AiDrafts` của phiên đó → đẩy trang phiên; ô nhập có sẵn chữ và dải "Tin của bạn đang ở ô nhập. Chạm Gửi khi phiên sẵn sàng."; không tự gửi. **Thất bại:** chữ giữ, câu theo mã (`AiWords.failure`); mất kênh → `aiOpenOutcomeUnknown`; không bao giờ tự gửi lại (V2-2 D13). | Với desktop cũ phải chạm Gửi thêm một lần. |
| T39 | Trang phiên (ĐT) | **Header:** nút quay lại (`back` của A); tiêu đề; dòng phụ "● {agent} · {trạng thái}[ · đồng hồ] · {dự án} · {nhánh}" (chấm vẽ; dự án kèm `folder`, nhánh kèm `branch`), cắt cuối. Trạng thái đứng trước để không bị cắt. Tên dự án lấy từ thư mục của listing có `path` trùng `cwd`, không có thì tên thư mục cuối. Menu ⋯ như B17, B20. **Chế độ, model, ngữ cảnh chuyển xuống thẻ ô nhập:** chip "Hỏi trước ▾" và "Opus ▾" mở sheet B11 (thay dòng phụ bấm được của B11); vòng ngữ cảnh "16%". **Thẻ ô nhập:** thẻ của A; hàng ảnh; gợi ý `@`; ô chữ; hàng chip: chế độ, model (cắt cuối), ảnh (`image`, khi có `blob`), `mic`, Gửi / Xếp hàng / Dừng (`send`, `queue`, `stop`; luật V2-2, V2-2b giữ). **Hội thoại** theo kiểu desktop (T32): bong bóng người dùng canh phải (nền `raised` của A, không đổ bóng), chữ agent rộng hết, thẻ tool một dòng gập (tự mở khi chờ quyền, như hôm nay), suy nghĩ gập. Bảng xin quyền, câu hỏi, hàng đợi, chống chạm 400 ms, "Xem đủ", Thay đổi / Hoàn tác: giữ. | — |
| T40 | V2-2 D9 giữ | Điện thoại không bao giờ duyệt hay gõ đường dẫn: chỉ gửi khoá desktop đưa trong listing, và desktop kiểm lại khoá lúc làm. Điện thoại không tạo, đổi tên hay lưu dự án. | Thư mục chưa từng dùng trên desktop thì điện thoại không mở được. |
| T41 | 🎙 và chỗ cho giọng nói | B đặt chỗ 🎙 (`mic` → `CupertinoIcons.mic`, khi đang nghe `micOn` → `CupertinoIcons.mic_fill`) trong hàng chip của mọi thẻ ô nhập. **Điện thoại:** 🎙 là đọc chính tả B14 hiện có và giữ nguyên (dừng nghe khi rời mục hoặc trang, khi app vào nền; V2-5c C2 giữ từ khoá "gửi"). Chỗ ngay bên phải 🎙 dành cho nút chế độ giọng nói của C (vai trò `voiceMode` → `CupertinoIcons.waveform`, V2-5c C2). **Chỗ móc của C ở trang phiên (T39):** khi chế độ giọng nói bật, thanh giọng nói của C thay chỗ thẻ ô nhập ở đáy trang (các bảng của dock — kế hoạch, xin quyền, câu hỏi, hàng đợi — vẫn ở trên nó) và lớp phủ toàn màn hình của C nằm trong trang phiên; nháp và ảnh của thẻ ô nhập giữ nguyên trong lúc đó (V2-5c C3–C5). C thêm tham số `startVoice` (mặc định false) cho `AiSessionRoute`; ô nhập mở phiên (T38) truyền nó khi mở phiên bằng nút giọng nói, hoặc bằng Gửi khi cài đặt "Mở phiên AI mới bằng giọng nói" bật (V2-5c C2, C31). **Desktop:** chưa có giọng nói (C: desktop làm sau), nên trong V2-5 **không hiện** 🎙; `AiComposerCard` giữ chỗ. **Đã chốt theo khuyến nghị.** | Bản phác đã duyệt có 🎙 trên desktop: thiếu nút đó cho tới khi có giọng nói desktop. Muốn có sớm hơn: hiện 🎙 kèm gợi ý dùng đọc chính tả của hệ điều hành (macOS: 🌐 / Fn hai lần; Windows: Win+H), sau khi kiểm tay xem chữ có vào ô nhập Flutter không. |
| T42 | Listing | Thân `ai.list.result` (JSON, đọc lỏng). **`folders` theo thứ tự:** dự án (`ws:<id>`, theo thứ tự workspace; bỏ workspace SSH; bỏ dự án mà lần kiểm gần nhất thấy `root` không còn), rồi Gần đây theo thứ tự T11. Gần đây dùng khoá **`path:<thư mục>`**, định dạng V2-2 D9 sẵn có. Mỗi mục thêm **`branch?`** (≤ 200 byte). `sessions` theo thứ tự sidebar AI (T12). `f` thêm **`folder_history`** và **`open_prompt`**. Listing quá cỡ cắt theo luật V2-2b hiện có (danh sách dài nhất mất mục cuối), nên thư mục gần đây cũ nhất mất trước. Trên điện thoại: `ws:` là Dự án; mọi khoá khác là Gần đây. | — |
| T43 | `ai.folder.history` | Tin mới ĐT → DT `{t: "ai.folder.history", rid, folder, agent, cursor?}`. Trả lời `ai.result {body: {"sessions": [{"acp", "title", "at"}], "next"?}}`, như B17: ≤ 50 phiên mỗi trang, tiêu đề ≤ 120 ký tự, con trỏ của hub khi trang của agent dài hơn. Desktop kiểm: khoá phải đang có trong listing (D9), agent phải có trong Cài đặt › Agents; rồi gọi trình liệt kê (T14) với đường dẫn của khoá. **Mã:** `refused` (khoá hoặc agent lạ, con trỏ sai); `not_ready` (agent chưa cài, thiếu Node, cần đăng nhập); **`no_list`** (mới: agent không có `session/list`); `busy` (ngân sách 60 dồn, 30 mỗi giây); `unavailable` (không có cửa sổ: `aiUnavailableReply`). | — |
| T44 | `ai.open {text}` | `ai.open` thêm `text?` (UTF-8 ≤ 32 KiB, như `ai.prompt`). Desktop kiểm trước và **không mở tab** khi sai: rỗng sau khi bỏ khoảng trắng → `refused`; quá cỡ → `too_large`. Rồi làm như V2-2 D9 (tab không được chọn, agent chạy ngay; workspace theo `aiWorkspaceForFolder` của T22), rồi `send([TextBlock(text)], source: phone)` (xếp hàng tới khi agent sẵn sàng; hiện "Bạn · từ điện thoại", B24), ghi Gần đây, trả `ai.result {sid}`. Điện thoại chỉ gửi `text` khi `MachineAi.can("open_prompt")`: `ai` ≥ 2 và `f` có từ đó (B1). | — |
| T45 | Tương thích | Bảng §6.4. `kAiProtocol` giữ 2. Daemon V2-2b đọc `ai.folder.history` thành `AiRaw` và chuyển nguyên văn (B2); không có cửa sổ thì trả `unavailable`. Daemon V2-5b biết loại mới: `_towardsPhone` false, có trong `aiUnavailableReply` và `_ridOf`. `ai.open` có `text` đi qua daemon V2-2b: map gốc được chuyển nguyên văn. **Giải mã không bao giờ làm rơi kênh:** tin sai trường thành `null`; thân JSON đọc lỏng. Test với bộ giải mã đóng băng của V2-2b (commit gộp V2-2b, plan ghi hash) và của V2-2a (`d8ad686`). | — |
| T46 | Riêng tư, log | Không nội dung mới nào rời kênh mã hoá đầu cuối: đường dẫn thư mục gần đây và nhánh đi trong listing như đường dẫn thư mục hôm nay, chỉ tới điện thoại đã ghép đôi. `ai_recent_folders` và `ai_agent_options` chỉ ở trên máy, cùng quyền với mọi cài đặt, không chứa bí mật (tên model, tên chế độ). Không log đường dẫn, tiêu đề, chữ tin, con trỏ; lỗi của trình liệt kê và của hộp chọn thư mục chỉ log `runtimeType`. `toString()` của tin và bản ghi mới là `Tên(…)`, có test ghim: `AiFolderHistory(…)`, `AiRecentFolder(…)`, `AiAgentOptions(…)`, `AiFirstMessage(…)`, `AiStart(…)`, `AiHomeDraft(…)` (desktop); `AiFolderGroup(…)` (ĐT). Trang Quyền riêng tư không cần đổi: không có loại dữ liệu mới rời máy. | — |
| T47 | Thứ tự làm | §14. | — |
| T48 | Biểu tượng (cập nhật A 11:25) | Mọi biểu tượng của B gọi qua **vai trò** trong `ShellxIcons` của A (`packages/shellx_design`). Mã của B không bao giờ dùng `Icons.*` của Material; grep ở bước rà soát cuối. Bảng vai trò và glyph `CupertinoIcons` ở §4.0. Vai trò **mới** của B: B thêm vào `ShellxIcons` với glyph ghi ở đó. Vai trò **đã có** trong bảng của A (A §7.4): B dùng đúng tên và glyph của A; §4.0 chép lại, lệch thì theo A. `CupertinoIcons` không có glyph terminal: nút Terminal dùng vai trò `terminal` của A với glyph Material dự phòng A ghi (`Icons.terminal_rounded`, chỉ nằm trong `ShellxIcons`). Nút Tool dùng vai trò `tool` của A (`CupertinoIcons.square_grid_2x2`). B không tự chọn glyph cho vai trò của A. Mọi glyph phải có trong `cupertino_icons` 1.0.9 mà A ghim. Chấm trạng thái, chấm online và số đếm là hình vẽ, không phải biểu tượng. Emoji trong các bản phác của §4, §5 chỉ là chỗ đứng cho vai trò, app không vẽ emoji. | Glyph mong đợi lệch với bảng của A: theo A, sửa một dòng ở §4.0. |
| T49 | Bố cục với chữ đơn cách (cập nhật A 11:25) | Font của app là SF Mono (iOS, macOS) hoặc JetBrains Mono (Android, Windows, và dự phòng trên iOS, macOS): rộng hơn chữ thường. Cỡ chữ theo kiểu chữ của A; B không đặt cỡ chữ và **không đặt bề rộng cố định cho chữ** ở đâu cả (chỉ đặt bề rộng tối đa cho khung: thẻ ô nhập 720 px, popover 380 px, bong bóng 80 % cột, sidebar 220 px giữ). **Luật cắt:** (1) mọi nhãn một dòng cắt bằng dấu ba chấm và có tooltip hoặc nhãn đọc màn hình đủ chữ; đường dẫn cắt ở giữa, tên, tiêu đề, nhánh cắt ở cuối. (2) Mỗi hàng có phần không bao giờ bị cắt: số đếm, chấm trạng thái, biểu tượng, nút; phần chữ chia phần còn lại. (3) Sidebar AI: tên nhóm lấy phần còn lại, nhánh tối đa 40 % bề rộng hàng; hàng phiên hai dòng cắt cuối; hàng "+ Phiên mới" ẩn nhãn phím khi không vừa; ô công tắc chế độ cắt nhãn, giữ số đếm; nút lọc chỉ có biểu tượng và số (T15). (4) Hàng chip của thẻ ô nhập desktop **xuống dòng thay vì tràn**, nút Gửi luôn ở cuối hàng cuối. Trên điện thoại hàng chip là một dòng: biểu tượng và nút Gửi giữ nguyên cỡ, các chip có chữ chia phần còn lại và cắt cuối. Trong một chip, nhánh ẩn trước rồi tên cắt. (5) Header phiên (DT) bỏ phần theo thứ tự ở T30, đo bằng chữ thật. (6) Điện thoại: nhãn thanh dưới một dòng, không xuống dòng; dòng phụ header cắt cuối, trạng thái đứng trước. (7) Test widget: mỗi màn của B ở bề rộng nhỏ nhất (sidebar 220 px; cửa sổ desktop nhỏ nhất; điện thoại 320 pt) và chữ hệ thống 200 % (điện thoại) không có lỗi tràn (`RenderFlex overflowed`). | Chữ hiện ít ký tự hơn trước trong sidebar; tooltip bù. |

---

## 4. Desktop: bố cục

### 4.0 Biểu tượng (cả hai app, T48)

Cột "Nguồn": **B** = vai trò mới B thêm vào `ShellxIcons`; **A** = vai trò có trong bảng của A (A §7.4), kể cả tám vai trò `voice*` A khai cho V2-5c; tên và glyph chép từ bảng đó, lệch thì theo A. Emoji và ký hiệu trong bản phác của §4, §5 chỉ là chỗ đứng: 📁 `folder`, 📂 `folderOpen`, ⊕ `saveProject`, × `remove`, 🔍 `search`, ✦ `ai`, ⎇ `branch`, 🎙 `mic`, 🖼 `image`, 🧩 `tool`, >_ `terminal`, ▥ `sidePanel`, ⋯ `more`, ⚙ `settings`, 🔔 `notifications` (vai trò của A), 💻 `computer`, + `newSession`, ▸ và › `chevronRight`, ▾ (ở đầu hàng và trong chip) `expand`, ‹ `back`, ↑ `send`, ▶ ! ✓ ba nút lọc (T15), 📄 ✎ biểu tượng kind của thẻ tool (vai trò của A), ● chấm trạng thái (hình vẽ), ① số trên huy hiệu (hình vẽ).

| Vai trò | Glyph | Nguồn | Dùng ở |
|---|---|---|---|
| `newSession` | `CupertinoIcons.plus` | B | hàng "+ Phiên mới", "+" của nhóm, mục "Phiên mới…" |
| `filterRunning` | `CupertinoIcons.play_fill` | B | nút lọc Đang chạy |
| `filterNeedsYou` | `CupertinoIcons.hand_raised_fill` | B | nút lọc Cần bạn |
| `filterDone` | `CupertinoIcons.checkmark` | B | nút lọc Xong |
| `folder` | `CupertinoIcons.folder` | B | đầu nhóm, hàng bộ chọn, chip dự án, hàng thư mục (ĐT), "Hiện trong Finder / File Explorer" |
| `folderOpen` | `CupertinoIcons.folder_open` | B | "Mở thư mục…" |
| `saveProject` | `CupertinoIcons.folder_badge_plus` | B | "Lưu thành dự án" |
| `branch` | `CupertinoIcons.arrow_branch` | B | nhánh git ở mọi nơi |
| `copyPath` | `CupertinoIcons.doc_on_clipboard` | B | "Chép đường dẫn" |
| `remove` | `CupertinoIcons.xmark` | B | "Bỏ khỏi gần đây", "Bỏ lọc", "Đóng phiên" |
| `computer` | `CupertinoIcons.desktopcomputer` | B | mục Máy tính của thanh dưới, chip máy |
| `commands` | `CupertinoIcons.slash_circle` | B | nút `/` của thẻ ô nhập |
| `warning` | `CupertinoIcons.exclamationmark_triangle` | A | thư mục không còn; thư mục quá rộng (T23) |
| `scanQr` | `CupertinoIcons.qrcode_viewfinder` | A | "Quét mã QR" ở trang Trợ lý AI |
| `mention` | `CupertinoIcons.at` | A | nút `@` của thẻ ô nhập |
| `voiceMode` | `CupertinoIcons.waveform` | A (vai trò của V2-5c) | nút chế độ giọng nói của V2-5c (C2), ở chỗ B dành bên phải 🎙 (ĐT) |
| `ai` | `CupertinoIcons.sparkles` | A | chip agent, hàng phiên AI (ĐT), mục Trợ lý AI của thanh dưới |
| `history` | `CupertinoIcons.clock` | A | hàng "Phiên trước", mục "Lịch sử phiên" |
| `search` | `CupertinoIcons.search` | A | ô tìm của bộ chọn |
| `edit` | `CupertinoIcons.pencil` | A | "Đổi tên…" |
| `chevronRight` | `CupertinoIcons.chevron_right` | A | đầu nhóm và hàng phiên trước khi gập (DT); "Xem tất cả", hàng thư mục (ĐT) |
| `expand` | `CupertinoIcons.chevron_down` | A | đầu nhóm và hàng phiên trước khi mở (DT); ▾ của mọi chip |
| `check` | `CupertinoIcons.checkmark` | A | trạng thái xong của thẻ tool (như hôm nay) |
| `send` | `CupertinoIcons.arrow_up` | A | nút Gửi (trong nút gradient của A) |
| `queue` | `CupertinoIcons.text_badge_plus` | A | nút Xếp hàng |
| `stop` | `CupertinoIcons.stop_fill` | A | nút Dừng, Dừng hẳn |
| `image` | `CupertinoIcons.photo` | A | nút ảnh (ĐT) |
| `mic` / `micOn` | `CupertinoIcons.mic` / `CupertinoIcons.mic_fill` | A | 🎙 (ĐT) |
| `sidePanel` | `CupertinoIcons.sidebar_right` | A | nút Thay đổi · Tệp trên header |
| `maximize` | `CupertinoIcons.arrow_up_left_arrow_down_right` | A | nút Phóng to |
| `more` | `CupertinoIcons.ellipsis` | A | ⋯ |
| `settings` | `CupertinoIcons.gear_alt` | A | mục Cài đặt của thanh dưới |
| `back` | `CupertinoIcons.chevron_back` | A | quay lại ở trang dự án, trang phiên, `AiNewSessionRoute` |
| `terminal` | `Icons.terminal_rounded` (Material, dự phòng A ghi: `CupertinoIcons` không có glyph terminal) | A | nút Terminal trên header, mục "Tab terminal mới" |
| `tool` | `CupertinoIcons.square_grid_2x2` | A | nút Tool trên header (V2-3) |
| biểu tượng theo kind của thẻ tool | các vai trò A gán (đọc, sửa, tạo, xoá, đổi tên, tìm, chạy, tải, suy nghĩ, đổi chế độ, khác) | A | thẻ tool một dòng; B không đổi glyph |

### 4.1 Sidebar chế độ AI (T3, T10–T17)

```
┌ sidebar 220 px ───────────────┐
│ ● ● ●             ⚙  🔔  +    │  dải đầu 38 px (macOS), như hôm nay
│ [ Terminal │ Trợ lý AI  1 ]   │  công tắc 28 px (T3); "1" = phiên AI cần bạn (khi đang ở Terminal)
│ + Phiên mới            ⌘⇧E    │  sáng khi màn bắt đầu hiện
│ (▶ 1) (! 1) (✓ 2)             │  bộ lọc: đang chạy, cần bạn, xong (T15)
│ DỰ ÁN                         │
│ ▾ 📁 shop-web       ⎇ main  + │  "+" khi rê chuột
│   ● Sửa nút đăng xuất         │  chấm cảnh báo: cần bạn
│     Cần bạn · Claude          │
│   ● Refactor giỏ hàng         │
│     Đang chạy · 0:41 · Codex  │
│   ▸ Phiên trước · Claude ▾    │  chỉ tải khi mở (T13)
│ ▸ 📁 api            ⎇ dev     │
│ ▸ 📁 docs   Không thấy thư mục│  root không còn: mờ (T16)
│ GẦN ĐÂY                       │
│ ▾ 📁 scratch                  │
│   ○ Thử regex                 │
│     Xong · Claude             │
│   ▾ Phiên trước · Claude ▾    │
│     Đọc log nginx       13/10 │
│     Viết script backup  12/10 │
│     Xem thêm                  │
│ ▸ 📁 notes                    │
└───────────────────────────────┘
```

- **Phím trong danh sách:** ↑ / ↓ qua mọi hàng (đầu nhóm, phiên, hàng phiên trước, mục phiên trước, "Xem thêm"); ← / → gập, mở; Enter mở phiên hoặc gập / mở nhóm; F2 đổi tên; Shift+F10 hoặc phím Menu mở menu của hàng (như A2). Danh sách dùng chung focus node và vùng F6 với sidebar Terminal.
- **Khi lọc:** dưới hàng nút lọc là "Cần bạn · 1   Bỏ lọc", rồi một danh sách phẳng; dòng hai của mỗi hàng là "{trạng thái} · {agent} · {dự án}".

### 4.2 Màn bắt đầu (T18–T23)

```
┌ sidebar ──────────────────────┬───────────── vùng nội dung: chế độ AI, chưa chọn phiên ─────────────┐
│ ● ● ●             ⚙  🔔  +    │                                                   ░░▒▒▓ nêm của A    │
│ [ Terminal │ Trợ lý AI  1 ]   │                                                                      │
│ + Phiên mới            ⌘⇧E    │                      Chào buổi sáng                                  │
│ (▶ 1) (! 1) (✓ 2)             │            Hôm nay Claude làm gì trong shop-web?                     │
│ DỰ ÁN                         │   ╭────────────────────────────────────────────────────────────╮     │
│ ▾ 📁 shop-web       ⎇ main    │   │ [ảnh][ảnh]                                                 │     │
│   …                           │   │ Nhắn cho Claude… (@ nhắc tệp)                              │     │
│                               │   │                                                            │     │
│                               │   │ [@] [/]  [📁 shop-web ⎇ main ▾] [✦ Claude ▾]               │     │
│                               │   │          [Hỏi trước ▾] [Model: Opus ▾]              [ ↑ ]  │     │
│                               │   ╰────────────────────────────────────────────────────────────╯     │
│                               │      ⚠ dòng ghi chú khi cần: thư mục quá rộng / không còn / không agent │
└───────────────────────────────┴──────────────────────────────────────────────────────────────────────┘
```

- Thẻ ô nhập rộng tối đa 720 px; hàng chip tự xuống dòng khi hẹp. Lời chào và thẻ nằm ở khoảng 40 % chiều cao vùng nội dung.
- Dock của chip dự án hiện bên phải như T8.
- **Phím:** focus vào ô nhập mỗi lần màn bắt đầu hiện. Enter gửi (Gửi đang mờ thì không làm gì); Shift+Enter xuống dòng. Esc đóng menu chip đang mở; không có menu thì không làm gì. Tab: ô nhập → chip → Gửi.

### 4.3 Bộ chọn dự án (T24–T27)

```
╭ bộ chọn dự án (380 × tối đa 460) ────────────╮
│ 🔍 Tìm dự án và thư mục                      │
│ DỰ ÁN                                        │
│ 📁 shop-web    ~/code/shop-web       ⎇ main  │
│ 📁 api         ~/code/api            ⎇ dev   │
│ 📁 docs        ~/code/docs      Không thấy   │  mờ; "Sửa trong Cài đặt › Dự án"
│ THƯ MỤC GẦN ĐÂY                              │
│ 📁 scratch     ~/tmp/scratch         ⊕   ×   │  khi rê chuột: Lưu thành dự án, bỏ khỏi gần đây
│ 📁 notes       ~/Documents/notes             │
│ ──────────────────────────────────────────── │
│ 📂 Mở thư mục…                          ⌘O   │
╰──────────────────────────────────────────────╯
```

Gõ `~/code/new-app` (đường dẫn của một thư mục có thật) → hàng đầu "Dùng thư mục ~/code/new-app".

### 4.4 Trang phiên (T30–T33)

```
┌ header 40 px ────────────────────────────────────────────────────────────────────────────────────┐
│ Sửa nút đăng xuất   📁 shop-web ▾  ⎇ main   ✦ Claude ▾   ● Cần bạn         [▥] [>_] [🧩] [⋯]    │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
                                         ╭─────────────────────────────────╮
                                         │ Nút đăng xuất không chạy trên   │   bong bóng, canh phải
                                         │ Safari, sửa giúp mình           │
                                         ╰─────────────────────────────────╯
  Mình xem `logout.ts` trước.                                                 chữ agent rộng hết cột
  › Suy nghĩ                                                                  gập sẵn
  [📄 Đọc src/logout.ts                                                ✓ ]    thẻ một dòng, gập
  [✎ Sửa src/logout.ts  +4 −1                                   chờ bạn ▾]    tự mở vì đang chờ quyền
     (diff)
  ── thanh kế hoạch · thanh xin quyền [1 Cho phép][2 Luôn cho phép][3 Từ chối Esc] · hàng đợi ──
  ╭────────────────────────────────────────────────────────────────────────╮
  │ Nhắn cho Claude… (@ nhắc tệp, / gọi lệnh)                              │
  │ [@] [/] [Hỏi trước ▾] [Model: Opus ▾] [Suy nghĩ: cao ▾]  Ngữ cảnh 16% [↑]│
  ╰────────────────────────────────────────────────────────────────────────╯
```

---

## 5. Điện thoại: bố cục

### 5.1 Thanh dưới và route (T34)

| Route | Hôm nay | V2-5b |
|---|---|---|
| `UpdateRequiredRoute`, `LoginRoute`, `RegisterRoute` | gốc | gốc, không đổi |
| `MachineListRoute` | gốc, `initial` | con thứ nhất của `HomeRoute` (mục Máy tính) |
| `AiHomeRoute` | — | **mới**, con thứ hai (mục Trợ lý AI) |
| `SettingsRoute` | gốc, đẩy từ ⚙ | con thứ ba (mục Cài đặt), không có nút back |
| `HomeRoute` | — | **mới**, gốc, `initial`, `AutoTabsRouter`, guard update + auth |
| `TerminalRoute`, `AiSessionRoute`, `ToolRoute`, `QrScannerRoute`, `DeleteAccountRoute` | gốc | gốc, đẩy đè thanh dưới bằng `context.router.root.push` |
| `AiProjectRoute`, `AiNewSessionRoute` | — | **mới**, gốc, đẩy đè thanh dưới |

### 5.2 Trang Trợ lý AI (T35, T36, T38)

```
┌──────────────────────────────────────┐
│ Trợ lý AI               [● MacBook ▾]│  chip máy (T35)
│ PHIÊN ĐANG MỞ                        │
│ ✦ Sửa nút đăng xuất                › │  cần bạn: lên đầu, màu cảnh báo
│   Claude · Cần bạn trả lời · shop-web│
│   Sửa src/logout.ts                  │
│ ✦ Refactor giỏ hàng                › │
│   Codex · Đang chạy · shop-web       │
│ DỰ ÁN                                │
│ 📁 shop-web    ⎇ main    2 phiên ● › │
│    ~/code/shop-web                   │
│ 📁 api         ⎇ dev               › │
│    ~/code/api                        │
│ GẦN ĐÂY                              │
│ 📁 scratch                         › │
│    ~/tmp/scratch                     │
│ ╭──────────────────────────────────╮ │
│ │ Nhắn cho Claude…                 │ │  ô nhập mở phiên (T38)
│ │ [📁 shop-web ▾][✦ Claude ▾] 🎙  ↑ │ │
│ ╰──────────────────────────────────╯ │
├──────────────────────────────────────┤
│ [💻 Máy tính] [✦ Trợ lý AI ①] [⚙ Cài đặt] │  thanh dưới của A; mục đang chọn là ô nổi gradient
└──────────────────────────────────────┘
```

### 5.3 Trang dự án (T37)

```
┌──────────────────────────────────────┐
│ ‹  shop-web                  ⎇ main  │
│    ~/code/shop-web                   │
│ ĐANG MỞ                              │
│ ✦ Sửa nút đăng xuất                › │
│   Claude · Cần bạn trả lời           │
│ PHIÊN TRƯỚC · Claude ▾               │
│   Thêm test đăng nhập   13/10 09:30  │
│   Sửa CSS trang chủ     12/10 17:02  │
│   [ Tải thêm ]                       │
│ ╭──────────────────────────────────╮ │
│ │ Nhắn cho Claude…                 │ │  chip dự án cố định: shop-web
│ │ [📁 shop-web][✦ Claude ▾] 🎙   ↑ │ │
│ ╰──────────────────────────────────╯ │
└──────────────────────────────────────┘
```

### 5.4 Trang phiên (T39)

```
┌──────────────────────────────────────┐
│ ‹ Sửa nút đăng xuất               ⋯  │
│   ● Claude · Đang chạy · 0:12 · 📁 s…│  dòng phụ cắt cuối, trạng thái đứng trước
├──────────────────────────────────────┤
│               từ điện thoại          │
│              ╭─────────────────────╮ │
│              │ Sửa giúp nút đăng   │ │  bong bóng canh phải
│              │ xuất trên Safari    │ │
│              ╰─────────────────────╯ │
│ Mình xem logout.ts trước.            │
│ › Suy nghĩ                           │
│ [✎ Sửa logout.ts +4 −1      chờ bạn] │
├──────────────────────────────────────┤
│ (bảng xin quyền / câu hỏi / hàng đợi)│
│ ╭──────────────────────────────────╮ │
│ │ Nhắn cho Claude…                 │ │
│ │ [Hỏi trước ▾][Opus ▾] 16% 🖼 🎙 ↑ │ │
│ ╰──────────────────────────────────╯ │
└──────────────────────────────────────┘
```

---

## 6. Giao thức (chỉ thêm)

### 6.1 Tin

| `t` | Chiều | Trường | Trả lời |
|---|---|---|---|
| `ai.folder.history` (mới) | ĐT → DT | `rid` (số), `folder` (khoá listing), `agent` (id agent), `cursor?` | `ai.result {body}` (§6.3), hoặc mã `refused`, `not_ready`, `no_list`, `busy`, `unavailable` (T43) |
| `ai.open` | ĐT → DT | thêm `text?` (UTF-8 ≤ 32 KiB) | như cũ; thêm `too_large` khi `text` quá cỡ (T44) |

- `shellx_core`: lớp `AiFolderHistory extends AiMessage` (`sid` null). Giải mã `'ai.folder.history' => AiFolderHistory(rid: f.integer('rid'), folder: f.string('folder'), agent: f.string('agent'), cursor: f.optionalString('cursor'))`. Thiếu hay sai trường thì `null`, như mọi tin `ai.*`.
- `AiOpen` thêm `text: f.optionalString('text')`; `toMap` ghi `'text': ?text`.
- Loại mới phải có mặt ở: `aiUnavailableReply` (`unavailable`), `_towardsPhone` (false), `_ridOf` (ngân sách `busy`), nhánh `switch` của hub.
- `AiFeature` thêm `folderHistory = 'folder_history'` và `openPrompt = 'open_prompt'`.
- `shellx_client`: `MachineAi.folderHistory(agent, folder, {cursor})` trả `AiHistoryPage` (`unsupported` ngay, không gửi gì, khi `!can('folder_history')`); `MachineAi.open(agent, folder, {resume, text})` chỉ đặt `text` khi `can('open_prompt')`, không thì ném `unsupported` để nơi gọi đi đường nháp (T38).
- Tin DT → ĐT: không có loại mới. Desktop chỉ trả lời yêu cầu, nên không bao giờ gửi điều gì mới cho điện thoại chưa hỏi.

### 6.2 Listing (`ai.list.result`, `body` JSON)

```json
{"v": 1,
 "sessions": [{"sid": "k3f9za.-12", "agent": "claude", "name": "Claude", "title": "Sửa nút đăng xuất",
               "state": "needs_input", "cwd": "/Users/me/code/shop-web", "waiting": "Sửa src/logout.ts",
               "acp": "sess_…"}],
 "agents": [{"id": "claude", "name": "Claude", "ready": true},
            {"id": "codex", "name": "Codex", "ready": false}],
 "folders": [{"key": "ws:abc", "name": "shop-web", "path": "/Users/me/code/shop-web", "branch": "main"},
             {"key": "path:/Users/me/tmp/scratch", "name": "scratch", "path": "/Users/me/tmp/scratch"}],
 "default_agent": "claude",
 "f": ["acp_head", "blob", "changes", "config", "files", "folder", "folder_history", "history",
       "item", "open_prompt", "push_answer", "revert"]}
```

`branch` đọc lỏng: thiếu, sai kiểu hay quá 200 byte thì bỏ. Không có khoá phân loại mới: điện thoại nhóm theo tiền tố khoá (`ws:` là dự án, khoá khác là Gần đây).

### 6.3 Thân trả lời của `ai.folder.history`

```json
{"sessions": [{"acp": "sess_…", "title": "Thêm test đăng nhập", "at": "2026-10-13T09:30:00Z"}],
 "next": "shellx-rest-3"}
```

Dùng lại `encodeHistoryPage` của B17 với `current: null`. Cùng giới hạn: 50 phiên mỗi trang, tiêu đề ≤ 120 ký tự, `acp` ≤ 200 byte, con trỏ ≤ 1 024 byte. Trang của agent dài hơn 50 thì hub chia bằng con trỏ của nó, như B17.

### 6.4 Tương thích

| Điện thoại | Desktop (cửa sổ) | Tiến trình giữ relay | Kết quả |
|---|---|---|---|
| cũ (V2-2b) | V2-5b | bất kỳ | Sheet "Phiên AI mới" cũ có thêm thư mục gần đây; khoá `branch` bị bỏ qua; không bao giờ nhận loại tin mới |
| V2-5b | V2-2b | V2-2b | Không có `folder_history` / `open_prompt`: trang dự án ghi "Cập nhật ShellX…", ô nhập đi đường nháp (T38); mọi thứ khác chạy |
| V2-5b | V2-2a | V2-2a (`ai: 1`) | Như hàng trên, và không có mọi tính năng B1 |
| V2-5b | không có AI | — | Trang Trợ lý AI ghi `aiUpdateDesktop` |
| V2-5b | V2-5b | daemon V2-2b | `ai.folder.history` thành `AiRaw`, chuyển nguyên văn (B2); `ai.open {text}` giữ map gốc; chạy |
| V2-5b | không có cửa sổ | daemon bất kỳ ≥ V2-2b | `ai.folder.history` nhận `unavailable` ngay; điện thoại không chờ |

---

## 7. Luồng dữ liệu

### 7.1 Desktop: tin đầu tạo phiên

```
Gửi trên màn bắt đầu (AiHomeDraft: thư mục, agent, chữ, ảnh, @)
  ├─ kiểm (thư mục còn? agent có? có nội dung?) — sai: dòng ghi chú, không mở tab
  ├─ AiRecentFolders.touch(thư mục)                                  T25
  ├─ TerminalTabs.openAiTab(agent, cwd, workspace, select: true)     chế độ AI, tab mới được chọn
  └─ AiFirstMessages.put(paneId, AiFirstMessage)                     chỉ trong bộ nhớ
PaneTreeView(selected) → AiPaneView → AiRuntimes.runtimeFor(pane)
  preferredConfig = rememberedConfig(agent)                          gồm chế độ / model của chip (T21)
AiComposer dựng lần đầu → AiFirstMessages.take(paneId) → _send() → runtime.send   (xếp hàng)
AiRuntime: initialize → session/new → _applyPreferred → ready → _drainQueue → session/prompt
```

### 7.2 Desktop: phiên trước của một nhóm

```
Mở hàng "Phiên trước · Claude" của nhóm /x
  bộ nhớ (claude, /x) còn dưới 60 s? → hiện
  không → AiHistoryLister.list(claude, /x)
            ├─ có runtime Claude sẵn sàng → client.listSessions(cwd: /x)
            └─ không → tiến trình liệt kê của Claude: initialize → session/list {cwd: /x}
                       (dừng sau 60 s rảnh; tối đa 1 mỗi agent, 2 cả app)
```

### 7.3 Điện thoại

```
Mục Trợ lý AI hiện, app ở trước
  AppSettings.aiMachine → WorkspaceRegistry.workspace(máy)
  → session.list {desktop: true} (khi chưa biết `ai`) → holdAiListing() → ai.list → ai.list.result
Chạm dự án → AiProjectRoute
  phiên có cwd này (listing) + ai.folder.history {folder, agent} → DT: AiHistoryLister
Gửi ở ô nhập mở phiên
  có open_prompt:   ai.open {agent, folder, text} → DT: openAiTab(select: false) + start + send(source: phone)
  không có:         ai.open {agent, folder} → AiDrafts.keep(phiên, chữ)
  → ai.result {sid} → AiSessionRoute(sid) → ai.attach → gương
```

---

## 8. Chuỗi (EN / VI)

Trong `apps/desktop/lib/l10n/app_*.arb` và `apps/mobile/lib/l10n/intl_*.arb`, cùng khoá ở hai ngôn ngữ.

### 8.1 Chuỗi đổi (khoá giữ, giá trị mới)

| Khoá | EN mới | VI mới |
|---|---|---|
| `aiNewTabKindLabel` (DT; cũ "New tabs open as" / "Tab mới mở dạng") | Start in | Mở ShellX ở chế độ |
| `aiNewTabKindAi` (DT; cũ "AI interface" / "Giao diện AI") | AI Assistant | Trợ lý AI |
| `aiSettingNewTabKindDesc` (DT) | The mode ShellX opens in when there is no earlier window to restore. Switch modes any time at the top of the sidebar. | Chế độ ShellX mở ra khi không có cửa sổ cũ để khôi phục. Đổi chế độ bất cứ lúc nào ở đầu sidebar. |
| `aiOnboardingAiBody` (DT) | AI Assistant: chat with an agent in a project, see what it does and review its changes. No commands to type. | Trợ lý AI: trò chuyện với agent trong một dự án, xem agent làm gì, duyệt thay đổi. Không cần gõ lệnh. |
| `aiOnboardingTerminalBody` (DT) | Terminal: every tab is a shell, as in ShellX today. | Terminal: mỗi tab là một shell, như ShellX hiện nay. |
| `aiOnboardingNote` (DT) | Switch any time at the top of the sidebar. | Đổi bất cứ lúc nào ở đầu sidebar. |
| `aiIntroText` (DT) | New: AI Assistant. Which mode should ShellX open in? | Mới: Trợ lý AI. ShellX nên mở ở chế độ nào? |
| `aiSettingsSection` (DT) | AI Assistant | Trợ lý AI |
| `aiSettingClaude` (DT) | Claude in AI Assistant | Claude trong Trợ lý AI |
| `aiSettingClaudeDesc` (DT; cũ "Runs Claude Code through the Claude Agent adapter. Off hides Claude everywhere." / "Chạy Claude Code qua adapter Claude Agent. Tắt thì ẩn Claude ở mọi nơi.") | Runs Claude through the Claude Agent adapter. Off hides Claude everywhere. | Chạy Claude qua adapter Claude Agent. Tắt thì ẩn Claude ở mọi nơi. |
| `aiNewNoFolders` (ĐT) | No project yet. On the computer, start an AI session in a folder; it then shows here. | Chưa có dự án nào. Trên máy tính, mở một phiên AI trong một thư mục; thư mục đó sẽ hiện ở đây. |

Tệp cấu hình mẫu (`config_template.dart`, chỉ tiếng Anh):
- `# --- AI interface ---` → `# --- AI Assistant ---`
- `# new-tab-kind = terminal  (ai: new tabs are AI sessions)` → `# new-tab-kind = terminal  (ai: start in AI Assistant when there is no window to restore)`
- `# ai-agent-claude = on  (off: hide Claude from the AI interface)` → `# ai-agent-claude = on  (off: hide Claude from AI Assistant)`

### 8.2 Chuỗi mới (desktop)

| Khoá | EN | VI |
|---|---|---|
| `aiModeTerminal` | Terminal | Terminal |
| `aiModeAssistant` | AI Assistant | Trợ lý AI |
| `aiModeSwitchLabel` | Mode | Chế độ |
| `aiModeNeedsYou` | {count, plural, =1{1 AI session needs you} other{{count} AI sessions need you}} | {count} phiên AI cần bạn |
| `aiModeTerminalUnread` | Terminal tabs have new notices | Tab terminal có thông báo mới |
| `actionToggleAiMode` | Switch Terminal / AI Assistant | Chuyển Terminal / Trợ lý AI |
| `aiSidebarNew` | New session | Phiên mới |
| `aiFilterRunning` | Running | Đang chạy |
| `aiFilterNeedsYou` | Needs you | Cần bạn |
| `aiFilterDone` | Done | Xong |
| `aiFilterChipLabel` | Filter: {label}, {count, plural, =1{1 session} other{{count} sessions}} | Lọc: {label}, {count} phiên |
| `aiFilterHeader` | {label} · {count} | {label} · {count} |
| `aiFilterClear` | Clear filter | Bỏ lọc |
| `aiFilterNoneRunning` | No session is running. | Không có phiên nào đang chạy. |
| `aiFilterNoneNeedsYou` | No session needs you. | Không có phiên nào cần bạn. |
| `aiFilterNoneDone` | No session has finished a turn yet. | Chưa có phiên nào xong lượt. |
| `aiSidebarProjects` | Projects | Dự án |
| `aiSidebarRecent` | Recent | Gần đây |
| `aiSidebarNoFolder` | No folder yet | Chưa có thư mục |
| `aiSidebarEarlier` | Earlier sessions · {agent} | Phiên trước · {agent} |
| `aiSidebarLoading` | Loading… | Đang tải… |
| `aiSidebarShowMore` | Show {count} more | Xem thêm {count} |
| `aiSidebarMoreHistory` | Show more | Xem thêm |
| `aiSidebarEmpty` | No projects yet. Pick a folder to start. | Chưa có dự án. Chọn một thư mục để bắt đầu. |
| `aiSidebarGroupEmpty` | No sessions here yet. | Chưa có phiên nào ở đây. |
| `aiSidebarHistoryNeedsAgent` | Earlier sessions show once {agent} is ready. | Phiên trước hiện khi {agent} đã sẵn sàng. |
| `aiSidebarHistoryFailed` | Couldn't load earlier sessions. Try again | Chưa tải được phiên trước. Thử lại |
| `aiSidebarFolderGone` | Folder not found | Không thấy thư mục |
| `aiSidebarNewIn` | New session in {project} | Phiên mới trong {project} |
| `aiSidebarCloseSession` | Close session | Đóng phiên |
| `aiSidebarRemoveRecent` | Remove from Recent | Bỏ khỏi Gần đây |
| `aiSidebarRowLabel` | {title}, {agent}, {state}, {project} | {title}, {agent}, {state}, {project} |
| `aiRevealMac` | Show in Finder | Hiện trong Finder |
| `aiRevealWindows` | Show in File Explorer | Hiện trong File Explorer |
| `aiCopyPath` | Copy path | Chép đường dẫn |
| `aiHomeMorning` | Good morning | Chào buổi sáng |
| `aiHomeAfternoon` | Good afternoon | Chào buổi chiều |
| `aiHomeEvening` | Good evening | Chào buổi tối |
| `aiHomeSubtitle` | What should {agent} do in {project} today? | Hôm nay {agent} làm gì trong {project}? |
| `aiHomeSubtitleNoProject` | Pick a project, then tell {agent} what to do. | Chọn một dự án rồi nói {agent} cần làm gì. |
| `aiHomeHint` | Message {agent}… (@ file) | Nhắn cho {agent}… (@ nhắc tệp) |
| `aiChipChooseProject` | Choose a project | Chọn dự án |
| `aiChipMode` | Mode | Chế độ |
| `aiChipModel` | Model | Model |
| `aiChipLater` | Shown after {agent} has run once | Có sau lần đầu chạy {agent} |
| `aiHomeNeedsProject` | Choose a project to start. | Chọn một dự án để bắt đầu. |
| `aiHomeFolderGone` | This folder is not there any more. Choose another. | Thư mục này không còn. Chọn thư mục khác. |
| `aiHomeNoAgent` | No agent is offered. Turn one on in Settings › Agents. | Chưa có agent nào. Bật một agent trong Cài đặt › Agents. |
| `aiHomeBroad` | {folder} is your home folder or a disk root: undo and @ are off there. | {folder} là thư mục home hoặc gốc ổ đĩa: hoàn tác và @ tắt ở đây. |
| `aiHomeChooseOther` | Choose another folder | Chọn thư mục khác |
| `aiCommandsLater` | Agent commands show once the session starts | Lệnh của agent có sau khi phiên bắt đầu |
| `aiNewWith` | New session with {agent} | Phiên mới với {agent} |
| `aiNewInThisProject` | New session in this project | Phiên mới trong dự án này |
| `aiPickerSearch` | Search projects and folders | Tìm dự án và thư mục |
| `aiPickerProjects` | Projects | Dự án |
| `aiPickerRecent` | Recent folders | Thư mục gần đây |
| `aiPickerOpenFolder` | Open folder… | Mở thư mục… |
| `aiPickerChoose` | Choose | Chọn |
| `aiPickerUsePath` | Use folder {path} | Dùng thư mục {path} |
| `aiPickerSaveProject` | Save as project | Lưu thành dự án |
| `aiPickerSaved` | Saved “{name}” as a project. | Đã lưu “{name}” thành dự án. |
| `aiPickerEmpty` | No projects or recent folders yet. | Chưa có dự án hay thư mục gần đây. |
| `aiPickerGone` | Not found | Không thấy |
| `aiPickerEditProject` | Edit in Settings › Projects | Sửa trong Cài đặt › Dự án |
| `aiPickerDialogFailed` | The folder dialog didn't open. | Không mở được hộp chọn thư mục. |
| `aiHeaderBranch` | Branch {branch} | Nhánh {branch} |
| `aiHeaderProject` | Project {name}: {path} | Dự án {name}: {path} |
| `settingsProjectFolderPick` | Choose… | Chọn… |

Dùng lại không đổi: `aiNoMatches` (tìm không thấy), `aiHistory` (mục ⋯), `aiNewSessionTooltip` (tooltip của `+` ở chế độ AI, kèm phím ⌘T), `actionNewTerminalTab` ("Tab terminal mới"), `aiNewTabKindTerminal` / `aiNewTabKindAi` (hai lựa chọn của "Mở ShellX ở chế độ"), `aiHistoryUnavailable` ("{agent} không liệt kê phiên."), `aiHistoryUntitled`, `aiMenuAgentsSettings`, `aiCannotSend`, chữ trạng thái agent của Cài đặt › Agents (`aiAgentReady`…).

### 8.3 Chuỗi mới (điện thoại)

| Khoá | EN | VI |
|---|---|---|
| `navComputers` | Computers | Máy tính |
| `navAssistant` | AI Assistant | Trợ lý AI |
| `navSettings` | Settings | Cài đặt |
| `navAssistantBadge` | {count, plural, =1{1 AI session needs you} other{{count} AI sessions need you}} | {count} phiên AI cần bạn |
| `aiTabTitle` | AI Assistant | Trợ lý AI |
| `aiMachineChip` | Computer: {name} | Máy: {name} |
| `aiPickMachine` | Choose a computer | Chọn máy tính |
| `aiNoMachines` | Pair a computer to use AI Assistant. | Ghép đôi một máy tính để dùng Trợ lý AI. |
| `aiMachineOffline` | {name} is offline. Open ShellX on it, then try again. | {name} đang offline. Mở ShellX trên máy đó rồi thử lại. |
| `aiOpenSessions` | Open sessions | Phiên đang mở |
| `aiSeeAll` | See all ({count}) | Xem tất cả ({count}) |
| `aiProjects` | Projects | Dự án |
| `aiRecent` | Recent | Gần đây |
| `aiNoFolderGroup` | No folder yet | Chưa có thư mục |
| `aiFolderSessions` | {n, plural, =1{1 session} other{{n} sessions}} | {n} phiên |
| `aiProjectOpen` | Open | Đang mở |
| `aiProjectEarlier` | Earlier sessions · {agent} | Phiên trước · {agent} |
| `aiProjectEarlierUpdate` | Update ShellX on the computer to see earlier sessions here. | Cập nhật ShellX trên máy tính để xem phiên trước ở đây. |
| `aiProjectEarlierNotReady` | Set up {agent} on the computer to see its earlier sessions. | Thiết lập {agent} trên máy tính để xem phiên trước. |
| `aiProjectEarlierNoList` | {agent} does not list its sessions. | {agent} không liệt kê phiên. |
| `aiProjectEmpty` | No sessions in this project yet. | Dự án này chưa có phiên nào. |
| `aiProjectGone` | The computer no longer offers this folder. | Máy tính không còn đưa thư mục này. |
| `aiChooseProject` | Choose a project | Chọn dự án |
| `aiChooseAgent` | Choose an agent | Chọn agent |
| `aiNewTitle` | New AI session · {machine} | Phiên AI mới · {machine} |
| `aiStarting` | Starting the session… | Đang mở phiên… |
| `aiDraftWaiting` | Your message is in the box. Tap Send when the session is ready. | Tin của bạn đang ở ô nhập. Chạm Gửi khi phiên sẵn sàng. |

Dùng lại không đổi: `machineLastUsed` ("Dùng gần nhất"), `actionScanCode`, `aiContext` ("Ngữ cảnh {percent}%"), `aiAgentNotReady`, `aiUnavailable`, `aiUpdateDesktop`, `aiNewNoAgents`, `aiOpenOutcomeUnknown`, `aiHistoryMore` ("Tải thêm").

### 8.4 Chuỗi bỏ

- Desktop: `aiFolderField`, `aiFolderInvalid`, `aiFolderUse` (ô gõ đường dẫn của thẻ thư mục, T29).
- Điện thoại: `aiNewAgent`, `aiNewFolder`, `aiNewStart` (sheet cũ, T38); `settingsTooltip` (nút ⚙ trên trang máy, T34). Mỗi khoá chỉ bỏ khi grep không còn chỗ dùng.

---

## 9. Riêng tư, an ninh và log

- Luật đã có giữ nguyên:
  - ShellX không đọc, lưu hay chuyển credential;
  - không `--hide-claude-auth`;
  - không biến `SHELLX_*` trong env của agent; trình liệt kê dùng cùng đường env (T14);
  - không bao giờ tự cho phép;
  - không bao giờ áp lại một chế độ không cần duyệt đã nhớ;
  - không có đường nào điện thoại trả lời mà không có một lần chạm.
- **Đường mới không mở chế độ không cần duyệt:**
  - bộ đệm tuỳ chọn không lưu nó (T21);
  - màn bắt đầu không liệt kê nó (T21);
  - `_applyPreferred` vẫn chặn `bypassPermissions`;
  - điện thoại không chọn chế độ trước khi có phiên (T38).
- **Trình liệt kê không làm gì ngoài liệt kê:** không đăng nhập, không mở phiên, không prompt (T14).
- **Không log nội dung:** T46.

---

## 10. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Thư mục ở chip mất trước khi gửi | Kiểm lúc gửi; dòng "Thư mục này không còn…"; không mở tab |
| Agent chưa cài / cần đăng nhập khi gửi tin đầu | Tab mở; tin đầu vào hàng đợi lúc agent khởi động; pane hiện thẻ Cài đặt / Đăng nhập (V2-1); agent chạy được thì tin đi. `send` trả false → tin về ô nhập của phiên (T22) |
| Đóng tab trước khi tin đầu đi | Tin bỏ cùng tab; không gửi |
| Đổi chế độ khi đang gõ ở màn bắt đầu | Bản nháp giữ trong lần chạy (T18) |
| Trình liệt kê không khởi động được | "Chưa tải được phiên trước. Thử lại"; log `runtimeType` |
| Hai yêu cầu lịch sử cùng agent | Chạy lần lượt (T14) |
| Agent bị tắt khi trình liệt kê đang chạy | Tiến trình dừng; yêu cầu đang chờ nhận "chưa sẵn sàng" |
| Thoát app / crash khi trình liệt kê chạy | Dừng như runtime; crash thì dọn bằng `running.json` |
| Hộp chọn thư mục lỗi | Toast `aiPickerDialogFailed` |
| "Mở thư mục…" chọn đúng thư mục của một dự án | Chip là dự án đó; Gần đây không thêm mục trùng hiển thị |
| Ổ mạng chậm khi kiểm tồn tại | Hết 2 s → giữ mục (T25) |
| Workspace dự án bị xoá khi có phiên mở | A2 chuyển tab về Default; nhóm sang Gần đây |
| `root` dự án đổi trong Cài đặt | Phiên cũ theo `cwd` sang Gần đây; dự án mang `root` mới |
| Khôi phục `mode: "ai"` mà tab AI đã chọn không còn | Màn bắt đầu |
| Bản cũ ghi lại `layout.json` | `mode` mất; lần sau theo `selectedTab` (T6) |
| ĐT: máy đang chọn bị bỏ ghép đôi | Chọn lại theo mặc định T35 |
| ĐT: khoá thư mục ở chip biến khỏi listing | Chip về "Chọn dự án"; Gửi mờ |
| ĐT: `ai.open {text}` mất kênh | `aiOpenOutcomeUnknown`; chữ giữ; không gửi lại |
| ĐT: listing quá cỡ | Thư mục gần đây cũ nhất mất trước (T42); phiên vẫn ở "Phiên đang mở" |
| ĐT: phiên có `cwd` không trùng thư mục nào | Chỉ hiện ở "Phiên đang mở" |

---

## 11. Kiểm thử

- **`shellx_core`:**
  - `AiFolderHistory` round-trip; thiếu `rid`, `folder` hoặc `agent` → `null`, kênh không rơi;
  - `toString` là `AiFolderHistory(…)`; `AiOpen` có `text` round-trip, `toString` không lộ chữ;
  - tin lớn nhất (`text` 32 KiB) vừa một lô niêm phong;
  - bộ giải mã đóng băng V2-2b và V2-2a đọc lô có `ai.folder.history` và `ai.open {text}` mà không lỗi.
- **`shellx_ai`:**
  - listing: `branch` round-trip; `AiListing.fromJson` đóng băng của V2-2b bỏ qua khoá mới; hai từ `f` mới;
  - `AiHistoryLister` với agent giả (`FakeLauncher`):
    - có runtime đang chạy → dùng nó, không chạy tiến trình;
    - không có → chạy tiến trình riêng;
    - tối đa 1 tiến trình mỗi agent, 2 cả app; yêu cầu tuần tự; `session/list` quá 15 s là lỗi;
    - dừng sau 60 s rảnh (đồng hồ giả);
    - agent giả ghi lại phương thức nhận được: không bao giờ có `session/new`, `authenticate`, prompt;
    - `-32000` → chưa sẵn sàng; không có capability `list` → không liệt kê;
    - `stopAll` dừng hết; có ghi `running.json`;
  - `AiRuntime.listSessions(cwd:)`;
  - bộ đệm tuỳ chọn: mã hoá, giải mã; giới hạn 40 lựa chọn, 60 ký tự; bỏ chế độ không cần duyệt (cả `value`, cả id lạ có "bypass", "yolo").
- **`shellx_agent`:**
  - hub `ai.folder.history`: khoá lạ → `refused`; agent lạ → `refused`; `not_ready`; `no_list`; trang hơn 50 chia bằng con trỏ của hub; ngân sách `busy`;
  - loại mới có trong `aiUnavailableReply`, `_towardsPhone`, `_ridOf`; daemon V2-2b giả (đọc thành `AiRaw`) chuyển nguyên văn;
  - `ai.open {text}`: rỗng → `refused`, không mở tab; quá cỡ → `too_large`, không mở tab; hợp lệ → `open(…, text)` đúng một lần;
  - listing có `f` mới, `folders` đúng thứ tự, bỏ SSH và root không còn.
- **`shellx_client`:**
  - `folderHistory` gửi đúng tin khi `can`, ném `unsupported` ngay khi không;
  - `open(text:)` chỉ đặt `text` khi `can('open_prompt')`; mã `no_list` lên tới nơi gọi.
- **Desktop — chế độ (T2–T9):**
  - bất biến I-mode qua mọi đường: bấm hàng, ⌘1–9, Ctrl+Tab, đóng, kế vị khác loại, thông báo A4, CLI `ui.*`, khôi phục;
  - `kNoTabShown`: `TerminalPane` (mọi `selected` false, màn bắt đầu hiện);
  - **"nothing acts on a hidden tab"**: ⌘W, chia, đổi tên, chép không làm gì khi màn bắt đầu hiện;
  - A12 `paneVisible` false; dwell A4 không đánh dấu đã đọc; `seenOnDesktop` false; `ui.ls` `selectedTab: null` và `mode`; tiêu đề cửa sổ;
  - `layout.json` có `mode` round-trip; parser đóng băng V1 (`164bba6`) và V2.0 (`d8ad686`) đọc tệp có `mode` mà không `.bak`;
  - chế độ lúc mở: có `mode` → AI; không `mode` mà đã chọn tab AI → AI; không có gì → theo `new-tab-kind`;
  - ⌘⇧J (`keybindings_test`), bảng lệnh;
  - công tắc: dấu cần bạn, phím mũi tên, nhãn đọc màn hình;
  - sidebar Terminal không có tab AI; ⌘T theo chế độ; ⌘⇧E hiện màn bắt đầu mà không tạo tab; `ensureTab` theo chế độ;
  - bước onboarding và thẻ chào một lần ghi `new-tab-kind` và đổi chế độ ngay; hàng Cài đặt › Chung "Mở ShellX ở chế độ".
- **Desktop — sidebar AI (T10–T17):**
  - nhóm theo thư mục: dự án hay gần đây, bỏ SSH, so đường dẫn kiểu Windows;
  - thứ tự id tab giảm dần, không nhảy khi trạng thái đổi; 8 hàng rồi "Xem thêm";
  - bộ lọc: số đếm, danh sách phẳng, câu khi trống;
  - phiên trước: không tải khi chỉ mở nhóm; tải khi mở hàng; 5 hàng rồi "Xem thêm"; bỏ trùng tab đang mở; bộ nhớ 60 s; các trạng thái;
  - dự án có root không còn; danh sách trống.
- **Desktop — màn bắt đầu (T18–T23):**
  - lời chào theo giờ (đồng hồ giả); đặt sẵn chip theo năm bước;
  - chip agent: mọi agent kèm trạng thái, không đổi agent mặc định;
  - chip chế độ / model: từ bộ đệm, mờ khi chưa có, không có chế độ không cần duyệt; chọn → `rememberConfig`;
  - gửi: tab mới đúng workspace, chế độ AI, tin đầu gửi **đúng một lần** (dựng lại pane không gửi lần hai); ảnh qua `_Unchecked`; `send` false → tin về ô nhập; thư mục mất → không mở tab;
  - `@` từ chỉ mục của thư mục; `/` mờ;
  - thư mục quá rộng: có cảnh báo, không ghi Gần đây, không bao giờ đặt sẵn.
- **Desktop — bộ chọn (T24–T29):**
  - tìm không dấu; gõ đường dẫn; ↑ / ↓ / Enter / Esc / ⌘O;
  - `aiPickFolderProvider` giả: chọn, huỷ, lỗi → toast;
  - Gần đây: thêm, trùng lên đầu, tối đa 20, kiểm tồn tại (false thì xoá, hết giờ thì giữ), gieo lần đầu;
  - hai khoá UI mới `ai_recent_folders`, `ai_agent_options` có trong `SettingKeys.all` và `UiSettingKeys`; `settings_ownership_test` thêm hai khoá vào `_expectedUi` (chú thích V2-5b T21, T25) và đổi `hasLength(35)` thành `hasLength(37)` (35 là số khoá sau khi gộp V2-3; A và C không thêm khoá desktop);
  - lưu thành dự án: workspace, root, tab chuyển sang, toast;
  - nhánh: bộ nhớ 10 s, focus cửa sổ, hết lượt, hết giờ thì giữ giá trị cũ;
  - thẻ thư mục mới; nút "Chọn…" ở Cài đặt › Dự án.
- **Desktop — trang phiên (T30–T33):**
  - header: dự án, nhánh, menu agent "Phiên mới với…", trạng thái, thu hẹp;
  - bong bóng, "Bạn · từ điện thoại";
  - thẻ gọn: không tự mở lệnh chạy xong, tự mở khi chờ quyền; suy nghĩ gập;
  - test V2-1, V2-2b hiện có xanh.
- **Desktop — dock (T8):** màn bắt đầu theo chip; ⌘⇧B mờ khi chip không là dự án; mở tool khi ở chế độ AI.
- **Mobile:**
  - route: `HomeRoute` ba mục; back Android; `replaceAll`; guard; trang đẩy đè thanh dưới;
  - thông báo AI chọn đúng mục và máy;
  - B21 chỉ giữ kênh khi mục Máy tính hiện; huy hiệu;
  - trang Trợ lý AI: các trạng thái (không có máy, offline, desktop cũ, không cửa sổ); chip máy (lưu, mặc định); các nhóm (Phiên đang mở, Dự án, Gần đây, Chưa có thư mục); ghép phiên theo `cwd`;
  - trang dự án: phiên mở; phiên trước (trang, "Tải thêm", bỏ trùng `acp`, đổi agent, `not_ready`, `no_list`, desktop không có tính năng); mở một phiên trước = `ai.open {resume}`;
  - ô nhập mở phiên: chỉ khoá listing; đặt sẵn; có `open_prompt` → một `ai.open {text}`; không có → nháp và dải; thất bại giữ chữ; mất kênh không tự gửi lại; sheet cũ được thay ở trang máy và bảng chọn AI;
  - trang phiên: header mới; chip chế độ / model mở sheet B11; vòng ngữ cảnh;
  - chuỗi EN, VI cùng khoá.
- **Biểu tượng và chữ đơn cách (T48, T49):**
  - grep: mã mới hoặc sửa của B không có `Icons.`; mọi biểu tượng đi qua `ShellxIcons`;
  - vai trò mới của B có trong `ShellxIcons` với glyph ở §4.0 (B thêm dòng vào `icons_test.dart` của package); vai trò của A dùng đúng tên ở A §7.4;
  - test tràn chữ ở mỗi màn của B: sidebar AI 220 px với tên dự án, nhánh, tiêu đề phiên rất dài; thẻ ô nhập ở bề rộng nhỏ nhất của cửa sổ (hàng chip xuống dòng, nút Gửi ở cuối); header phiên hẹp (nhánh rồi chip dự án biến mất, trạng thái còn); điện thoại 320 pt với chữ hệ thống 200 % (thanh dưới, trang Trợ lý AI, trang dự án, ô nhập mở phiên, header trang phiên): không có lỗi tràn.
- **Đầu cuối** (desktop và điện thoại qua hub giả, như V2-2):
  - listing có thư mục gần đây và nhánh;
  - `ai.folder.history` qua trình liệt kê với agent giả;
  - `ai.open {text}` → tab mới, tin đầu hiện "Bạn · từ điện thoại".

---

## 12. Review Focus

1. **Tab bị che vẫn bị coi là đang hiện** (`kNoTabShown`, bất biến I-mode). Các dạng lỗi: ⌘W đóng tab terminal bị che khi đang ở màn bắt đầu; thông báo bị nuốt vì A12 tưởng người dùng đang xem; agent của tab AI bị che tự chạy; A4 đánh dấu đã đọc. Test từng chỗ đọc ở T5; grep `selectedId` ở bước rà soát cuối.
2. **Tin đầu mất hoặc gửi hai lần**: pane dựng lại; đổi chế độ giữa chừng; `send` từ chối; điện thoại mất kênh sau `ai.open {text}`; đường nháp với desktop cũ. Test: đúng một lần; không bao giờ tự gửi lại.
3. **Tiến trình agent thừa**: trình liệt kê không dừng; mở nhiều nhóm chạy nhiều tiến trình; tiến trình mồ côi khi thoát hoặc crash. Test: giới hạn, 60 s, `stopAll`, `running.json`.
4. **Bản cũ**: daemon V2-2b gặp loại tin mới; điện thoại cũ gặp listing nhiều thư mục (cắt khi quá cỡ); parser `layout.json` cũ gặp `mode`; bản cũ gặp khoá `ai_*` mới. Test với bộ giải mã đóng băng.
5. **Chế độ không cần duyệt lọt qua đường mới**: bộ đệm tuỳ chọn ghi `value` bypass; chip màn bắt đầu liệt kê nó; `rememberConfig` từ màn bắt đầu; `ai.open` của điện thoại. Test cả lúc liệt kê lẫn lúc áp (`_applyPreferred` vẫn chặn).

---

## 13. ⚠ Kiểm tay (cần người, máy thật)

1. **macOS, bản Release đã ký (hardened runtime):** "Mở thư mục…" mở `NSOpenPanel`; tạo được thư mục mới. Chọn `~/Documents/x` rồi gửi tin: macOS hỏi quyền Documents cho ShellX một lần, agent đọc được.
2. **Windows 10 và 11, 100 % và 150 %:** hộp chọn thư mục; đường dẫn `C:\Users\…` và ổ khác; Gần đây so trùng không phân biệt hoa thường.
3. **Claude thật:** trình liệt kê chạy ở thư mục A liệt kê đúng phiên của thư mục B (`session/list {cwd}`). Đo lần đầu (lạnh) và khi đã có phiên đang chạy. Tiến trình biến mất sau 60 s (Activity Monitor, Task Manager).
4. Telex trong ô nhập màn bắt đầu và trong ô tìm của bộ chọn; Enter khi đang ghép chữ không gửi.
5. VoiceOver và Narrator: công tắc chế độ, hàng sidebar AI, nút lọc, chip, bộ chọn.
6. 30 dự án, 100 phiên trước, 20 thư mục gần đây: sidebar cuộn mượt; listing tới điện thoại không làm rơi kênh.
7. iPhone (có home indicator) và Android (thanh cử chỉ, nút back): thanh dưới; back về mục Máy tính; bàn phím đè ô nhập ở trang Trợ lý AI.
8. Điện thoại mới với desktop V2-2b (bản `shellx-v2` trước V2-5b): trang dự án không có phiên trước; ô nhập đi đường nháp.
9. Thông báo AI khi app tắt và khi app ở nền: mở đúng mục Trợ lý AI, đúng máy, đúng phiên.
10. SF Mono (macOS, iOS) và JetBrains Mono (Windows, Android; cũng là dự phòng trên macOS, iOS) ở cỡ nhỏ nhất của A: sidebar AI (nút lọc, hàng hai dòng, đầu nhóm có nhánh dài), hàng chip của thẻ ô nhập, header phiên, thanh dưới. Chữ cắt gọn, không tràn, tiếng Việt đủ dấu. Cùng lượt kiểm tay của A.
11. Biểu tượng `CupertinoIcons` của §4.0 hiện đúng hình trên cả bốn nền tảng (không ô vuông rỗng); `terminal` hiện glyph Material dự phòng của A, `tool` hiện `square_grid_2x2`.

---

## 14. Phạm vi và chia plan

**Trong V2-5b:** mọi thứ ở §3–§11.

**Ngoài V2-5b:**
- Môi trường Cloud, SSH, WSL cho phiên AI; phiên AI trong workspace SSH (B8 giữ).
- Worktree riêng cho mỗi phiên; chip nhánh / worktree trên màn bắt đầu.
- Gộp thẻ tool thành nhóm; chế độ xem Normal / Verbose; side chat.
- Lưu trữ, ghim, xoá phiên; tìm trong mọi phiên; `session/delete`.
- Đổi tên, sắp xếp, xoá dự án ngay trong sidebar AI (làm ở chế độ Terminal hoặc Cài đặt › Dự án).
- Dự án nhiều thư mục (`additionalDirectories`); hướng dẫn và bộ nhớ theo dự án.
- Giọng nói trên desktop; việc của nút 🎙 (V2-5c).
- Điện thoại tạo hay lưu dự án, duyệt thư mục; ảnh, `@`, chế độ, model trước khi có phiên.
- Trang web và trang Quyền riêng tư (B không cần đổi gì ở đó).

**Chia plan:** một plan khoảng 26 task, cỡ V2-2b. Thứ tự:
1. **Task 1 — kiểm trước:** `file_selector` (`pub get`, build macOS và Windows); adapter Claude với `session/list {cwd}` từ một thư mục khác (ghi fixture).
2. **Giao thức và package:** T42–T46 trong `shellx_core`, `shellx_ai`, `shellx_agent`, `shellx_client`; `AiHistoryLister`; `AiRuntime.listSessions(cwd)`; bộ đệm tuỳ chọn.
3. **Mô hình chế độ:** T5, T6.
4. **Công tắc, phím, lối vào, đổi tên:** T1, T3, T4, T7, T9.
5. **Dữ liệu thư mục:** Gần đây, nhánh, kiểm tồn tại (T25, T28).
6. **Bộ chọn dự án:** bộ chọn, `file_selector`, lưu thành dự án, thẻ thư mục (T24, T26, T27, T29).
7. **Sidebar AI:** T10–T17.
8. **Thẻ ô nhập chung:** T19.
9. **Màn bắt đầu và tin đầu:** T18, T20–T23.
10. **Trang phiên:** header và hội thoại (T30–T33).
11. **Dock:** T8.
12. **Nguồn desktop cho điện thoại:** `folders`, `open` có chữ, lịch sử theo thư mục.
13. **Điện thoại — route và thanh dưới:** T34.
14. **Điện thoại — trang Trợ lý AI:** T35, T36.
15. **Điện thoại — trang dự án:** T37.
16. **Điện thoại — ô nhập mở phiên:** T38.
17. **Điện thoại — trang phiên:** T39.
18. **Chuỗi, test tương thích hai chiều, rà soát cuối.**

T48 và T49 không là bước riêng: mỗi bước giao diện dùng vai trò biểu tượng của §4.0 và luật cắt của T49, kèm test tràn của chính nó. Các bước giao diện cần `ShellxIcons`, kiểu chữ và component của A đã vào `shellx-v2`.

Muốn chạy song song thì chia hai nhánh **B-desktop** (bước 3–12) và **B-phone** (bước 13–17) sau khi bước 2 xong. V2-5c (giọng nói) sửa cùng trang phiên điện thoại, nên phần chồng lên T38, T39 của C chạy sau bước 16–17; phần không chồng chạy song song được.

---

## 15. Rủi ro

| Rủi ro | Mức | Xử lý |
|---|---|---|
| Đổi mô hình chọn tab (`kNoTabShown`) làm hỏng một chỗ đọc chưa biết | Trung bình | T5 liệt kê chỗ đọc; test từng chỗ; Review Focus 1 |
| Adapter Claude không theo `cwd` của `session/list` | Thấp–TB | Task 1 kiểm; dự phòng ở T14 (khởi động lại tiến trình trong thư mục được hỏi) |
| `file_selector` ghim không build được trên Flutter 3.41.4 hoặc CI Windows | Thấp | Task 1 kiểm cả hai; hạ bản nền tảng (0.9.4+x cần Dart 3.9) nếu cần |
| Đổi route điện thoại (shell) làm sai `popUntil`, B21, thông báo | Trung bình | T34; test điều hướng; kiểm tay 7, 9 |
| Chữ đơn cách (SF Mono, JetBrains Mono) làm sidebar 220 px, hàng chip, header chật hoặc tràn | Trung bình | T49 (không bề rộng chữ cố định, luật cắt, chip xuống dòng trên desktop và co trên điện thoại); bộ lọc dạng biểu tượng (T15); test tràn §11; kiểm tay 10 cùng A |
| Glyph `CupertinoIcons` thiếu trong bản `cupertino_icons` A ghim, hoặc lệch với bảng của A | Thấp | Tên glyph ở §4.0 đã kiểm trong lớp `CupertinoIcons` của Flutter 3.41.4; A thắng khi lệch (T48); kiểm tay 11 |
| Trình liệt kê tốn RAM, CPU | Thấp | Chỉ chạy khi mở "Phiên trước"; dừng sau 60 s; tối đa 2 |
| V2-5c cùng sửa trang phiên điện thoại | Trung bình | B làm T38, T39 trước; C dùng chỗ 🎙 (T41) |

---

## 16. Việc sau

- Gộp các thẻ tool liền nhau thành một nhóm; chế độ xem Normal / Verbose như Claude (Ctrl+O).
- Lưu trữ, ghim, tìm, xoá phiên.
- Worktree riêng cho mỗi phiên (V2-1 §10); chip nhánh / worktree trên màn bắt đầu.
- Giọng nói trên desktop (V2-5c pha sau) lấp chỗ 🎙.
- Đổi tên, sắp xếp dự án ngay trong sidebar AI; dự án nhiều thư mục.
- Điện thoại: ảnh và `@` trong ô nhập mở phiên; chọn chế độ, model trước khi có phiên.
- Desktop hiện "điện thoại đang xem phiên này".
- Phiên trước của mọi agent cùng lúc trong một nhóm.

---

## 17. Việc chờ người dùng

Không có. Hai việc trước đây để ngỏ đã chốt theo khuyến nghị, cách khác và giá của nó ghi ở cột "Giá nếu sai":
1. **🎙 trên desktop:** ẩn cho tới khi có giọng nói desktop (T41).
2. **Tab AI ở chế độ Terminal:** không liệt kê; phiên AI chỉ ở chế độ AI (T2).
