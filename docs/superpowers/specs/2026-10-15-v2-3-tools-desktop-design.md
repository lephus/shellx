# V2-3 — Tool qua URL trên desktop — Đặc tả thiết kế

- **Ngày:** 2026-10-15
- **Branch:** `shellx-v2`. Toàn bộ V2 nằm trên branch này và được đẩy lên `main` sau mỗi phần đã test và review.
- **Trạng thái:** Người dùng giao: "soạn spec và làm tất cả V2-2b V2-3 V2-4" (15/10). Theo cách làm đã quen (spec ghi lại để lưu hồ sơ, không dừng chờ duyệt), các quyết định D1–D24 do người viết spec chốt, mỗi quyết định ghi cái giá nếu sai. Người dùng xem lại khi tiện; muốn đổi điều gì thì đổi.
- **Lộ trình V2:** V2-1 (tab AI, xong), V2-2 (điện thoại: phiên AI; V2-2a xong, V2-2b song song với tài liệu này), **V2-3 (tài liệu này)**, V2-4 (tool trên điện thoại, dùng danh sách tool của V2-3).
- **Nền:** `shellx-v2` tại `d8ad686`.
- **Hướng đã được duyệt (14/10, trang đề xuất `docs/superpowers/design/2026-10-14-ai-pane-demo/`):**
  - "Tool = một URL. Tool bạn tự viết bằng bất kỳ công nghệ gì, chạy ở localhost: ShellX hiện nó lên. Không manifest, không SDK."
  - "Bản đầu ShellX chỉ hiển thị, tool chưa nói chuyện với agent."
  - Kịch bản 6 của demo: thêm tool bằng tên và URL (gợi ý từ các cổng đang chạy, ô "Cho mở trên điện thoại"); tool mở cạnh pane AI; thanh của tool có chỉ báo "trang trên máy này", nút điện thoại, tải lại, đóng.
  - Rủi ro "Engine trình duyệt A6 trên máy thật" mức **Cao**: "Chạy bước thử sớm; không đạt thì cửa sổ con native."
- **Nguồn đã kiểm ngày 15/10/2026** (ghi chép đầy đủ ở ledger của plan):
  - mã nguồn ShellX tại `d8ad686` (§2);
  - nhánh để dành `origin/feat/desktop-a6` (8 commit trên `148c2db`), spec và plan A6, ledger `a1-desktop-terminal.md`;
  - thử trên worktree nháp (đã xoá): lấy riêng phần engine của A6 lên `main` thì `analyze` sạch, 107 test mới qua, cả bộ test desktop xanh (3 682), `flutter build macos --debug` thành công;
  - web: pub.dev (`webview_flutter` 4.14.1, `webview_flutter_wkwebview` 3.25.1 là bản mới nhất chạy được với Flutter 3.41.4, `webview_win_floating` 3.0.3, `webview_windows` 0.4.0 từ 02/2024), tài liệu Apple (ATS, `WKWebsiteDataStore`), tài liệu WebView2 (thư mục dữ liệu, profile), RFC 6265 §8.5, issue Flutter #41722 và #31713, issue `flutter-webview-windows` #230.
- **Ký hiệu:** "D1" không tiền tố là quyết định của tài liệu này; "A6 D10" là của spec A6; "V2-1 D3" là của spec V2-1.
- **V2-3 được phép sửa:** app desktop (`apps/desktop`), `packages/shellx_agent` (chỉ phần đọc cổng). **Không sửa:** giao thức điện thoại, relay, app mobile (V2-4 làm), mô hình phiên AI của V2-1a.

---

## 1. Mục tiêu

Người dùng có một web app của riêng mình (bảng việc, dashboard, trang quản trị, bản dev của sản phẩm…) chạy ở `http://localhost:…`. Họ muốn thấy và dùng nó **ngay trong ShellX**, cạnh cuộc trò chuyện với AI hoặc cạnh terminal, không phải chuyển qua trình duyệt:
- thêm tool bằng tên và URL, có gợi ý từ các cổng đang chạy;
- mở tool trong một vùng bên phải cửa sổ, đổi tab vẫn thấy nó;
- tool giữ đăng nhập qua các lần mở ShellX, tách khỏi trình duyệt của họ;
- bật "Cho mở trên điện thoại" cho tool nào muốn dùng từ điện thoại (V2-4 làm phần điện thoại).

### Tiêu chí thành công (đo được)

1. **Thêm nhanh.** Từ nút "Thêm tool" ở chân sidebar: chọn một gợi ý cổng, bấm "Thêm". Sau ≤ 3 lần bấm, vùng tool mở và trang hiện lên.
2. **Gợi ý đúng.** Server do terminal của workspace chạy, và server do agent AI của workspace tự chạy (ví dụ Claude chạy `npm run dev`), đều có trong gợi ý trong ≤ 2 s sau khi mở hộp thoại.
3. **Cạnh nhau.** Trang hiện bên phải tab đang chọn (tab AI hay tab terminal). Đổi sang tab khác cùng workspace: trang vẫn ở đó, không tải lại, giữ chỗ cuộn và chữ đang gõ.
4. **Gõ được.** Gõ vào ô trong trang được, kể cả tiếng Việt Telex; ⌘C/⌘V/⌘A/⌘Z làm việc trong trang. Khi trang đang giữ bàn phím, phím tắt của ShellX (⌘T, ⌘1…9, ⌘⇧E, ⌘⇧P, ⌘⇧B…) vẫn chạy (macOS).
5. **Chưa chạy server.** Tool chưa có server thì vùng tool ghi "Chưa có gì chạy ở localhost:5173", tự thử lại, và trang hiện ra trong ≤ 3 s sau khi server lên, không phải bấm gì.
6. **Giữ đăng nhập.** Đăng nhập vào tool, thoát ShellX, mở lại: vẫn đăng nhập. Safari, Chrome, Edge không thấy cookie của tool và ngược lại.
7. **Khôi phục.** Mở lại ShellX: mỗi workspace có lại vùng tool như lúc thoát (mở hay đóng, tool nào, rộng bao nhiêu). Trang chỉ tải khi vùng tool của workspace đó hiện ra.
8. **Windows an toàn.** Trên Windows, khi chưa ai chạy bước kiểm trên máy thật, bấm mở tool thì tool mở bằng trình duyệt của hệ thống. Bật `tool-embed = on` thì tool hiện trong vùng tool.
9. **Không hồi quy.** Mọi test hiện có vẫn xanh. Mở ShellX bản cũ trên dữ liệu đã dùng V2-3 vẫn giữ nguyên terminal và tab AI.

---

## 2. Kiểm tra hiện trạng (đọc mã ngày 2026-10-15, đường dẫn tính từ `apps/desktop/lib/`)

| Mảng | Hiện có | Hệ quả cho V2-3 |
|---|---|---|
| Bố cục cửa sổ | `TerminalWorkspacePage._body()` là `Row(sidebar 220 px, VerticalDivider, Expanded(TerminalPane))` (`src/ui/terminal/terminal_workspace_page.dart:932`) | D3: vùng tool là một cột thứ ba, bên phải `TerminalPane`; không đụng cây pane |
| Cây pane | Lá dương là phiên terminal; lá âm là pane AI (`isAiPaneId(id) => id < 0`, `src/ai/ai_pane_state.dart:12`, 6 chỗ gọi). A6 cũng dùng id âm cho pane trình duyệt, đếm từ −1 | D3: tool không thành lá trong cây pane, nên không đụng không gian id |
| Khôi phục | `layout.json` v1; V2-1 thêm `aiTabs`. Khoá lạ ở cấp trên cùng bị bỏ qua. Một loại lá mới trong `tabs[].layout` làm bản cũ đổi cả tệp thành `.bak` (`src/restore/restore_snapshot.dart:482`) | D14: trạng thái vùng tool ở khoá mới `toolDock` cấp trên cùng |
| Workspace | `Workspace {id, name, collapsed, ssh, zoom, root}` lưu trong khoá `terminal_workspaces`; `encode()` chỉ ghi khoá đã biết, nên bản cũ sửa workspace là mất khoá lạ (`src/terminal/sidebar_workspaces.dart:84`) | D2: tool lưu ở khoá riêng `workspace_tools`, không nằm trong JSON workspace |
| Cài đặt | `SettingKeys` (`src/platform/settings_store.dart`); khoá do cửa sổ sở hữu (A5b, một người ghi). Tệp cấu hình A9 phẳng `key = value`, khoá kebab-case (`src/config/settings_schema.dart`) | D2 khoá app; D7 khoá tệp `tool-embed` |
| Cổng đang nghe (A2) | `PortWatcher` gán cổng cho phiên bằng cách đi ngược cha tới **pid của shell** (`packages/shellx_agent/lib/src/context/listening_ports.dart:125`), chạy ở nơi giữ phiên (cửa sổ, hoặc daemon khi bật dịch vụ nền); kết quả là `PaneSession.ports` | D12: server do agent AI chạy (con của adapter, không thuộc shell nào) **không bao giờ** được gợi ý; cần quét theo yêu cầu với gốc là pid agent |
| Engine A6 | Nhánh để dành có: `browser_url.dart`, `browser_engine.dart` (interface), `browser_controller.dart`, engine macOS `WkWebViewEngine` + `BrowserNative.swift` (viết xong, **chưa review**, chưa chạy thật), engine giả cho test. **Không có engine Windows.** `webview_windows` 0.4.0 vendored chưa có bản vá nào. `main` đã revert phần phụ thuộc của A6 Task 1 (`fd7d178`) | D6: chỉ lấy phần engine; D7: Windows dùng gói khác |
| Bước kiểm A6 | macOS: chỉ phần tự động qua (09/10); chưa kiểm overlay, Telex, cuộn, đổi cỡ, phím thật. Windows: chưa build lần nào | §11: kiểm tay là việc của người, trước khi bật mặc định trên Windows |
| ATS macOS | `macos/Runner/Info.plist` không có `NSAppTransportSecurity`. Từ macOS 14, ATS chặn kết nối tới địa chỉ IP (`http://127.0.0.1`) | D19 |
| Phím | `defaultKeyBindings` (`src/config/keybindings.dart:107`); ⌘⇧B / Ctrl+Shift+B còn trống; ⌘⇧P là bảng lệnh | D10 |
| Sidebar | Chân sidebar có nút "Phiên AI mới" (`src/ui/terminal/session_sidebar.dart:1901`); demo đặt "Thêm tool" cạnh nó | D21 |
| Cài đặt › Dự án | Mỗi workspace một thẻ tên và thư mục (`src/ui/settings/pages/projects_page.dart`) | D22: danh sách tool của từng dự án |

---

## 3. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| D1 | Tool là gì | Một **tên** và một **URL** `http`/`https`, thuộc một workspace, kèm cờ **điện thoại**. Không manifest, không SDK, không cầu nối JS. **URL hợp lệ:** có host; không có `user:pass@`; không có `\`; cổng 1–65535; gõ thiếu scheme thì thêm `http://`; giữ path và query làm trang bắt đầu, bỏ `#…`. Tên trống thì lấy `host:port`. | — |
| D2 | Lưu tool | Khoá app mới `workspace_tools` (cửa sổ sở hữu), một chuỗi JSON cho mỗi tool `{id, ws, name, url, phone}`. `id` 10 ký tự `[a-z0-9]` ngẫu nhiên, không đổi suốt đời tool. Tối đa 50 tool mỗi workspace; tên ≤ 60 ký tự; URL ≤ 2 048 ký tự. Xoá workspace thì xoá tool của nó. **Không** để trong JSON của workspace, vì bản cũ ghi lại workspace sẽ làm mất khoá lạ. | Đọc thêm một khoá khi khởi động. |
| D3 | Tool hiện ở đâu | **Vùng tool:** một cột bên phải cửa sổ, cạnh pane của tab đang chọn (tab AI hay terminal), có thanh kéo để đổi rộng. Mỗi workspace có vùng tool riêng; đổi tab trong cùng workspace thì vùng tool đứng yên. Rộng mặc định 45 % vùng nội dung, tối thiểu 320 px; vùng pane còn lại tối thiểu 360 px. Nút **Mở rộng** cho vùng tool chiếm hết vùng nội dung (bấm lại hoặc Esc khi focus ở thanh của tool để thu về). **Loại bỏ:** (a) tool thành lá trong cây pane: đụng quy tắc tab AI, trùng id âm với pane AI, bản cũ mất `layout.json` khi gặp lá lạ; (b) loại tab mới: sidebar có hai danh sách cho cùng một tool, phải sửa mọi chỗ đọc tab; (c) trình duyệt hệ thống hoặc cửa sổ riêng: không "cạnh pane AI" như đã duyệt. | Một workspace chỉ thấy một tool một lúc (đổi qua lại bằng chip); không đặt hai tool cạnh nhau. |
| D4 | Mở tool | Từ: hàng tool trên sidebar; nút tool (🧩) trên thanh pane AI; bảng lệnh ("Mở tool: <tên>", "Thêm tool…"); thẻ dự án trong Cài đặt. Mở tool thì vùng tool của workspace đó mở và tool thành tool đang xem. Tool thuộc workspace khác workspace của tab đang chọn: chọn tab gần nhất của workspace đó trước (không có tab nào thì vùng nội dung để trống, vùng tool vẫn hiện). Tab AI đang mở panel Thay đổi/Tệp thì panel đóng lại khi vùng tool mở (như demo); người dùng mở lại được. | — |
| D5 | Nhiều tool | Đầu vùng tool có dải **chip**, mỗi tool đã mở một chip (bấm để xem, × để đóng); dải chỉ hiện khi có từ 2 tool. Mỗi tool đã mở giữ trang của nó khi đổi chip. Toàn app tối đa **8 trang sống** (A6 D28); mở trang thứ 9 thì trang lâu không xem nhất bị dỡ, chip của nó vẫn còn, bấm vào thì tải lại. Đóng vùng tool không dỡ trang: mở lại là thấy ngay. | ~100–200 MB mỗi trang sống. |
| D6 | Engine | Lấy **riêng phần engine** từ nhánh `feat/desktop-a6`: `browser_url.dart` (phân tích địa chỉ, lớp origin), `browser_engine.dart` (interface), engine macOS `WkWebViewEngine` (`webview_flutter` 4.14.1, `webview_flutter_wkwebview` 3.25.1) cùng `BrowserNative.swift`, và engine giả cho test. Review lại engine macOS (chưa review lần nào). **Không lấy:** pane trình duyệt chung, registry, sửa mô hình tab, tray, `ui.browser.*`, cầu nối JS và script khởi động. Thêm hai phụ thuộc bằng tay, **không** revert cả `fd7d178` (khỏi kéo theo `third_party/webview_windows`). Nhánh A6 vẫn để dành cho trình duyệt đầy đủ sau này. | Khi A6 làm tiếp phải dùng chung engine này. |
| D7 | Windows | Engine `webview_win_floating` 3.0.3: một cửa sổ WebView2 thật đặt trên cửa sổ Flutter, theo interface của `webview_flutter`, nên dùng chung mã engine với macOS. **Chưa ai chạy trên máy Windows thật**, nên khoá tệp `tool-embed = auto | on | off` (mặc định `auto`): `auto` là nhúng trên macOS, **mở bằng trình duyệt hệ thống trên Windows**. Khi nhúng trên Windows: Flutter không vẽ được lên trên WebView2, nên mỗi khi có lớp phủ (hộp thoại, menu, bảng lệnh, panel thông báo, tìm kiếm) ShellX ẩn trang và hiện một tấm thay thế mang tên tool; khi trang giữ bàn phím, phím tắt ShellX không tới (bấm ra ngoài trang để dùng). **Loại bỏ:** `webview_windows` 0.4.0 vendored (bản cuối 02/2024, lỗi #230 làm chết phím tắt khi bấm vào trang, năm bản vá C++ không kiểm được từ đây); bản fork `webview_flutter_windows` (cần Flutter ≥ 3.44). | Người dùng Windows mở tool bằng trình duyệt cho tới khi chạy bước kiểm §11.2 và đổi `auto`. |
| D8 | Dữ liệu web | **Một kho dữ liệu chung cho mọi tool**, tách khỏi Safari/Chrome/Edge, **giữ qua các lần mở ShellX** (giữ đăng nhập). macOS: kho mặc định của app (`WKWebsiteDataStore.default()`, `~/Library/WebKit/<bundle id>`). Windows: thư mục dữ liệu `%LOCALAPPDATA%\ShellX\tools`, profile `tools`. Cài đặt có "Xoá dữ liệu của tool" (xoá hết, hỏi lại trước). **Loại bỏ** mỗi tool một kho: macOS cần `WKWebsiteDataStore(forIdentifier:)` (macOS 14+, app hỗ trợ từ 12) và phải vá plugin. | Hai tool ở `localhost` dùng cùng tên cookie thì đè nhau, y như trong trình duyệt thường (cookie không tách theo cổng, RFC 6265 §8.5). |
| D9 | Điều hướng | Trang đầu là URL của tool. Mọi trang `http`/`https` được mở trong vùng tool (đăng nhập SSO đi qua trang khác rồi quay về vẫn chạy). Khi trang không còn ở origin của tool, thanh ghi "Đang ở <host>" và có nút "Về tool". **Cửa sổ mới** (`target=_blank`, `window.open`): mở bằng trình duyệt hệ thống. `mailto:`, `tel:`: giao cho hệ điều hành. Scheme khác (`file:`, `javascript:` cấp trên cùng, `data:` cấp trên cùng, scheme lạ): chặn, không báo. **Tải tệp:** chặn, vùng tool hiện "Tool muốn tải một tệp. Mở bằng trình duyệt để tải." kèm nút. **Quyền** (camera, micro, vị trí, thông báo): từ chối. **Hộp thoại JS** (`alert`, `confirm`, `prompt`): hiện bằng hộp thoại ShellX ghi tên tool. | Tool cần tải tệp phải mở bằng trình duyệt. |
| D10 | Bàn phím, focus | **macOS:** khi trang giữ bàn phím, ShellX bắt các phím trong bảng phím hiện hành (`KeyBindings.map(KeyScope.window)`, gồm cả phím đầu của chuỗi hai bước) và chạy lệnh của nó; riêng sao chép, dán, cắt, chọn hết, hoàn tác, làm lại để lại cho trang. Bấm chuột vào bất cứ đâu ngoài trang thì bàn phím về Flutter. Phím mới `toggle_tools` = **⌘⇧B / Ctrl+Shift+B**: mở hoặc đóng vùng tool của workspace (đang đóng thì mở tool xem gần nhất; chưa có tool thì mở hộp thoại Thêm tool). `close_surface` (⌘W) khi focus ở vùng tool: đóng chip đang xem, chip cuối thì đóng vùng tool. Lệnh chuyển focus sang phải từ pane ngoài cùng bên phải thì vào vùng tool, sang trái từ vùng tool thì về pane. **Windows (khi nhúng):** trang giữ mọi phím (D7). | Một phím tắt trùng với phím trang cần (ví dụ ⌘F) chạy lệnh ShellX thay vì trang. |
| D11 | Chỉ báo nơi chạy | Thanh của tool ghi `host:port` kèm dấu: **"Trên máy này"** cho `localhost`, `*.localhost`, `127.0.0.0/8`, `::1`, `0.0.0.0` (lớp `local` của A6 D11); **"Ngoài máy này"** cho host khác; `http` ngoài máy này thêm "không mã hoá". | — |
| D12 | Gợi ý cổng | Hộp thoại Thêm tool hiện "Cổng đang chạy mà ShellX thấy" cho workspace của nó: (1) `PaneSession.ports` của mọi pane terminal trong workspace (kể cả pane terminal mở trong tab AI); (2) **một lần quét theo yêu cầu** khi hộp thoại mở, lấy các cổng do **tiến trình con của agent AI** trong workspace nghe (gốc là pid tiến trình agent; dùng lại `PortProbe` và `ownerOf` của A2; quét trong cửa sổ, nơi agent chạy, ở cả hai chế độ). Mỗi gợi ý ghi `localhost:<cổng>` và tên tiến trình; tối đa 8; bỏ cổng tool trong workspace đã dùng. Bấm gợi ý thì điền URL, và điền tên khi ô tên còn trống (tên thư mục dự án, hoặc tên tiến trình). | Server chạy ngoài ShellX (ví dụ Docker) không được gợi ý; người dùng tự gõ URL. |
| D13 | Lỗi tải | **Bị từ chối kết nối:** "Chưa có gì chạy ở localhost:5173. Chạy server của tool rồi trang sẽ tự hiện." Tự thử lại sau 1, 2, 4, 8 s rồi 10 s một lần, chỉ khi vùng tool đang hiện; có nút "Tải lại". **Lỗi khác** (tên miền, TLS, hết giờ): câu ngắn đúng loại lỗi, "Tải lại", "Mở bằng trình duyệt". **ATS chặn** (macOS, `http` ở host có tên ngoài mạng nội bộ): "macOS không cho mở trang http này trong ShellX." và "Mở bằng trình duyệt". **Tiến trình trang bị dừng:** tự tải lại một lần; lần sau thì hiện "Trang đã dừng" và "Tải lại". | — |
| D14 | Khôi phục | Khoá mới `toolDock` ở cấp trên cùng của `layout.json` v1: `{"<id workspace>": {"open": true, "zoom": false, "width": 0.45, "active": "<id tool>", "tools": ["<id tool>", …]}}`. Bản V1 và V2.0 bỏ qua khoá lạ cấp trên cùng. Khi mở lại: vùng tool, chip và độ rộng như cũ; **trang chỉ tải khi vùng tool của workspace đó hiện ra lần đầu**. Tool đã bị xoá thì bỏ chip của nó. | Bản cũ ghi lại `layout.json` từ trạng thái của nó nên làm mất `toolDock`: mở lại bản mới thì vùng tool trống (tool vẫn còn trong cài đặt). |
| D15 | Cờ điện thoại | Mặc định tắt. Bật ở: hộp thoại Thêm tool, nút 📱 trên thanh của tool, menu chuột phải của hàng tool, thẻ dự án. **Chỉ tool `http` trên máy này** (`localhost`, `127.0.0.1`, `[::1]`) bật được (V2-4 E1); tool khác thấy nút mờ kèm lý do "Chỉ tool http trên máy này mở được trên điện thoại." Tắt cờ thì V2-4 đóng ngay mọi kết nối của điện thoại tới tool đó. | — |
| D16 | Không cầu nối | Không kênh JS, không `eval`, không chụp màn hình, không script khởi động. Agent không thấy và không điều khiển được tool (đúng như đề xuất đã duyệt). `ui.browser.*` vẫn trả `unknown_type`. | Agent chưa tự kiểm được giao diện của tool. |
| D17 | Thanh của tool | Trái sang phải: 🧩, tên, `host:port` + dấu D11, "Đang ở <host>" khi lạc origin; rồi: ◀ Quay lại (mờ khi không có trang trước), ↻ Tải lại (đang tải thì thành ✕ Dừng), 📱 Điện thoại (bật/tắt, D15), ⤢ Mở rộng, ↗ Mở bằng trình duyệt, ⋯ (Sửa tool…, Sao chép URL, Đóng vùng tool), × Đóng tool. Cao 32 px, cùng kiểu thanh pane AI. | — |
| D18 | Trợ năng | Mọi nút có nhãn đọc được; chip là nút có trạng thái chọn. VoiceOver đọc trong trang chỉ ở mức platform view của Flutter cho phép (issue #41722 còn mở); "Mở bằng trình duyệt" là lối thay thế. | Người dùng trình đọc màn hình nên dùng trình duyệt. |
| D19 | ATS macOS | Thêm `NSAppTransportSecurity › NSAllowsLocalNetworking = true` vào `macos/Runner/Info.plist`: mở được `http://localhost`, `http://127.0.0.1`, IP trong mạng nhà, `*.local`. **Không** thêm `NSAllowsArbitraryLoadsInWebContent`. | Tool `http` ở host có tên ngoài mạng nội bộ không nhúng được trên macOS (D13 báo rõ). |
| D20 | Khi nào không nhúng | `tool-embed = off`, hoặc `auto` trên Windows: mọi lối mở tool (D4) mở URL bằng trình duyệt hệ thống, vùng tool không hiện; hàng tool trên sidebar có ↗. Phím ⌘⇧B lúc đó mở hộp thoại Thêm tool khi workspace chưa có tool, còn không thì không làm gì. | — |
| D21 | Sidebar | Dưới mỗi workspace có tool: nhóm **"Tool"** (thu gọn được), mỗi tool một hàng: 🧩, tên, dòng phụ `host:port` (thêm "· cả điện thoại" khi bật cờ). Hàng sáng lên khi nó là tool đang xem của vùng tool đang mở. Chuột phải: Mở, Mở bằng trình duyệt, Sửa…, Cho mở trên điện thoại, Xoá… Chân sidebar: nút **"Thêm tool"** cạnh "Phiên AI mới"; thêm vào workspace của tab đang chọn. | — |
| D22 | Cài đặt | **Cài đặt › Dự án:** thẻ mỗi dự án có danh sách tool (tên, URL, cờ điện thoại, Sửa, Xoá) và "Thêm tool". Cuối trang: "Dữ liệu của tool: Xoá…" và "Hiện tool trong ShellX: Tự động / Luôn / Không, mở bằng trình duyệt" (chính là `tool-embed`). | — |
| D23 | Sửa, xoá | Sửa tên, URL, cờ điện thoại trong cùng hộp thoại. Đổi URL thì trang đang mở tải lại ở URL mới. Xoá hỏi lại ("Xoá tool "Bảng việc"? Trang của nó đóng lại. Dữ liệu web của nó không bị xoá."), đóng chip và trang. | — |
| D24 | Riêng tư | Không log URL, đường dẫn, tiêu đề trang, nội dung; chỉ log loại lỗi. `toString()` của tool trả `Tool(…)`. Không gửi gì ra ngoài máy: trang tải thẳng từ URL của tool. | — |

---

## 4. Giao diện và chuỗi (EN + VI)

### 4.1 Bố cục

```
┌ sidebar ─┬──── pane của tab đang chọn ────┬─┬────── vùng tool ──────┐
│ shop-web │  (tab AI hoặc terminal)        │║│ [Bảng việc][Grafana]+ │  ← chip (≥ 2 tool)
│  Tab AI  │                                │║│ 🧩 Bảng việc localhost:4000 · Trên máy này  ◀ ↻ 📱 ⤢ ↗ ⋯ × │
│  zsh     │                                │║│                       │
│  Tool    │                                │║│     (trang của tool)  │
│  🧩 Bảng │                                │║│                       │
│ [+ Phiên AI mới] [🧩 Thêm tool]           │║│                       │
└──────────┴────────────────────────────────┴─┴───────────────────────┘
```

### 4.2 Hộp thoại Thêm tool

- Tiêu đề "Thêm tool" / "Add a tool"; khi sửa: "Sửa tool" / "Edit tool".
- Ô **Tên** (gợi ý "Bảng việc" / "Task board"), ô **URL** (gợi ý `http://localhost:4000`).
- "Cổng đang chạy mà ShellX thấy:" / "Running ports ShellX can see:" rồi các nút gợi ý `localhost:5173 · node`. Không có gì: "Chưa thấy cổng nào. Chạy server của tool trong một terminal hoặc nhờ agent chạy." / "No running ports yet. Start your tool's server in a terminal or ask the agent to."
- Ô chọn **"Cho mở trên điện thoại"** / "Allow on phone", dòng nhỏ "Đi qua relay, mã hoá đầu cuối. Điện thoại chỉ tới được đúng URL này." / "Through the relay, end-to-end encrypted. The phone can reach this URL only."
- Nút "Huỷ" / "Cancel", "Thêm" / "Add" (sửa: "Lưu" / "Save"). URL sai: dòng đỏ dưới ô ("URL phải bắt đầu bằng http:// hoặc https://" / "The URL must start with http:// or https://"; "URL không được chứa tên đăng nhập hay mật khẩu" / "The URL can't contain a user name or password").

### 4.3 Chuỗi chính

| Khoá | EN | VI |
|---|---|---|
| `toolsGroup` | Tools | Tool |
| `toolAdd` | Add tool | Thêm tool |
| `toolOpenCommand` | Open tool: {name} | Mở tool: {name} |
| `toolLocal` | On this computer | Trên máy này |
| `toolRemote` | Not on this computer | Ngoài máy này |
| `toolUnencrypted` | not encrypted | không mã hoá |
| `toolAway` | On {host} | Đang ở {host} |
| `toolBackToTool` | Back to tool | Về tool |
| `toolPhoneOn` / `toolPhoneOff` | Phone: on / Phone: off | Điện thoại: bật / Điện thoại: tắt |
| `toolPhoneOnlyLocal` | Only http tools on this computer can open on a phone. | Chỉ tool http trên máy này mở được trên điện thoại. |
| `toolAlsoPhone` | · on phone too | · cả điện thoại |
| `toolExpand` / `toolCollapse` | Expand / Restore | Mở rộng / Thu về |
| `toolOpenInBrowser` | Open in browser | Mở bằng trình duyệt |
| `toolRefused` | Nothing is running at {hostPort}. Start your tool's server and the page will appear. | Chưa có gì chạy ở {hostPort}. Chạy server của tool rồi trang sẽ tự hiện. |
| `toolLoadFailed` | The page couldn't load: {reason} | Không tải được trang: {reason} |
| `toolAtsBlocked` | macOS doesn't allow this http page inside ShellX. | macOS không cho mở trang http này trong ShellX. |
| `toolCrashed` | The page stopped. | Trang đã dừng. |
| `toolDownloadBlocked` | This tool wants to download a file. Open it in your browser to download. | Tool muốn tải một tệp. Mở bằng trình duyệt để tải. |
| `toolDeleteConfirm` | Delete the tool "{name}"? Its page closes. Its web data stays. | Xoá tool "{name}"? Trang của nó đóng lại. Dữ liệu web của nó không bị xoá. |
| `toolClearData` | Clear tool data… | Xoá dữ liệu của tool… |
| `toolClearDataConfirm` | Sign every tool out and clear its cookies and storage? | Đăng xuất mọi tool và xoá cookie, bộ nhớ của chúng? |
| `toolEmbedSetting` | Show tools in ShellX | Hiện tool trong ShellX |
| `toolEmbedAuto` / `On` / `Off` | Automatic / Always / No, open in browser | Tự động / Luôn / Không, mở bằng trình duyệt |
| `toolCovered` | {name} — hidden while a menu is open | {name} — tạm ẩn khi đang mở menu |
| `toolTooMany` | Closed "{name}" to keep ShellX light. Click to load it again. | Đã dỡ "{name}" cho ShellX nhẹ. Bấm để tải lại. |
| `toolJsAlertTitle` | {name} says | {name} nhắn |

Hành động mới trong bảng phím và bảng lệnh: `toggle_tools` ("Show or hide tools" / "Hiện hoặc ẩn vùng tool"), "Add tool…" / "Thêm tool…".

---

## 5. Mô hình và lưu trữ

- `ToolEntry {id, ws, name, url, phone}` (thuần Dart, `src/tools/tool_entry.dart`): `fromJson` không bao giờ ném (mục hỏng bị bỏ, có test), `toJson`, `origin` (scheme+host+port), `isLocal` (D11), `phoneAllowed` (D15: `http` và host là `localhost` / `127.0.0.1` / `::1`).
- `ToolRegistry` (Riverpod notifier): đọc/ghi khoá `workspace_tools`; thêm, sửa, xoá; xoá theo workspace; luồng đổi để V2-4 nghe (`watchPhoneTools()`).
- `ToolDockState` theo workspace: `{open, zoom, width, active, tools}`; `ToolDockController` giữ trang sống (D5) và đếm LRU cho cả app.
- Khôi phục: `RestoreSnapshot` đọc/ghi `toolDock` (D14) cùng chỗ với `aiTabs`, theo cách lỏng: một mục hỏng chỉ bỏ mục đó.

---

## 6. Engine

- `BrowserEngine` (interface từ A6): `load`, `goBack`, `reload`, `stop`, sự kiện URL/tiêu đề/tải/lỗi/lịch sử/điều hướng bị chặn/tải tệp bị chặn/phím chuyển tiếp/bấm vào trang, `setForwardedChords`, `focusContent`, `releaseFocus`, `buildView`, `dispose`. Bỏ khỏi đường dùng cho tool: `runScript`, `capturePng`, cầu nối.
- `WkWebViewEngine` (macOS): `WebViewController` + `WebViewWidget`; `onNavigationRequest` thực thi D9; mã lỗi NSURLError đổi thành loại lỗi D13 (gồm ATS: `NSURLErrorAppTransportSecurityRequiresSecureConnection` −1022); `BrowserNative.swift` cho dừng tải, xoá dữ liệu, focus và chuyển phím (D10). Hộp thoại JS qua `setOnJavaScriptAlertDialog` / `ConfirmDialog` / `TextInputDialog`.
- `WinFloatingEngine` (Windows): `webview_win_floating` qua cùng interface `webview_flutter`; thư mục dữ liệu và profile D8; `setVisibility(false)` khi có lớp phủ (D7).
- `ToolPage` (widget): thanh D17, trang, các trạng thái lỗi D13, tấm thay thế khi bị phủ, và vòng thử lại.

---

## 7. Riêng tư, an ninh và log

- Trang chạy trong kho dữ liệu riêng của ShellX (D8), không có cầu nối vào app (D16), không quyền thiết bị (D9).
- Hộp thoại JS ghi rõ tên tool để không giả được hộp thoại của ShellX.
- Không log nội dung (D24). Test ghim `toString()`.
- URL lưu trên máy trong cài đặt của ShellX như mọi cài đặt khác; không gửi lên relay (V2-4 chỉ gửi qua kênh mã hoá đầu cuối tới điện thoại đã ghép đôi).

---

## 8. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Tool trỏ tới cổng chưa có server | D13: chờ, tự thử lại, tự hiện |
| Server tắt khi trang đang mở | Trang giữ nguyên; tải lại thì vào D13 |
| Trang chuyển hướng sang origin khác (SSO) | Cho đi; thanh ghi "Đang ở <host>", nút "Về tool" |
| Trang mở cửa sổ mới | Trình duyệt hệ thống |
| Tool bị xoá khi đang mở | Chip đóng, trang dỡ |
| Đổi URL tool | Trang đang mở tải lại ở URL mới; chip giữ chỗ |
| Đóng tab cuối của workspace | Vùng tool của workspace vẫn còn; nội dung trống |
| Xoá workspace | Xoá tool của nó và trạng thái vùng tool |
| 9 trang sống | Dỡ trang lâu không xem nhất (D5), báo bằng toast `toolTooMany` |
| Cửa sổ quá hẹp (< 360 + 320 px vùng nội dung) | Vùng tool tự thu: chỉ hiện khi Mở rộng |
| Bản cũ mở `layout.json` có `toolDock` | Bỏ qua khoá; giữ terminal và tab AI. Bản cũ ghi lại tệp thì `toolDock` mất (chấp nhận: vùng tool mở lại trống, tool vẫn còn trong cài đặt) |
| `workspace_tools` hỏng một mục | Bỏ mục đó, giữ mục khác |
| macOS 12–13 | Như macOS 14+ (không dùng API mới) |
| Windows thiếu WebView2 Runtime (khi `tool-embed = on`) | "Cần Microsoft Edge WebView2 Runtime." và nút "Mở bằng trình duyệt" |

---

## 9. Kiểm thử

- **Đơn vị (thuần Dart):** `ToolEntry` (URL hợp lệ/không hợp lệ: thiếu scheme, userinfo, `\`, cổng 0 và 65536, IPv6 `[::1]`, `javascript:`; `isLocal`; `phoneAllowed`); `ToolRegistry` (thêm, sửa, xoá, giới hạn 50, xoá theo workspace, mục hỏng); `toolDock` round-trip; gợi ý cổng (gán theo shell và theo pid agent, bỏ cổng đã dùng, tối đa 8); LRU 8 trang; vòng thử lại (1, 2, 4, 8, 10 s; dừng khi ẩn).
- **Widget (engine giả):** mở tool từ sidebar, thanh pane AI, bảng lệnh; đổi tab giữ trang (cùng một engine, không `load` lại); chip; đóng chip cuối đóng vùng; Mở rộng/Thu về; ⌘⇧B; ⌘W ở vùng tool; thanh D17 ở các trạng thái (đang tải, lỗi từ chối, ATS, đang ở host khác, dừng); hộp thoại Thêm tool (gợi ý, lỗi URL, cờ điện thoại mờ với tool không hợp lệ); D20 mở bằng trình duyệt (đường mở URL giả); tấm thay thế khi có lớp phủ (Windows giả); thẻ Cài đặt › Dự án.
- **Khôi phục:** lưu rồi đọc lại `toolDock`; **tương thích:** parser của V1 (`164bba6`) và V2.0 (`d8ad686`) đọc tệp có `toolDock` → giữ nguyên tab, không `.bak`.
- **Engine macOS:** test đơn vị với engine giả; integration test `flutter test -d macos` trong bản build cách ly (bundle id riêng, HOME tạm) với một server nhỏ trong test: tải trang, đổi tiêu đề, điều hướng bị chặn, cửa sổ mới chuyển ra ngoài, lỗi từ chối kết nối.
- **Tương thích phím:** chord chuyển tiếp lấy từ bảng phím hiện hành, kể cả phím người dùng đặt lại và phím đầu của chuỗi hai bước.
- **Không hồi quy:** toàn bộ test desktop, package; `flutter build macos`; build Windows trên nhánh `windows-check/v2-3` (người dùng xem kết quả CI).

---

## 10. Review Focus

1. **Trang bị tải lại ngoài ý muốn** khi đổi tab, đổi workspace, mở hộp thoại, đổi cỡ cửa sổ: người dùng mất chữ đang gõ. Test: cùng một engine sống qua các thao tác đó.
2. **Phím tắt khi trang giữ bàn phím** (macOS): ⌘T, ⌘W, ⌘1…9, ⌘⇧E, ⌘⇧P, ⌘⇧B phải chạy; ⌘C/⌘V phải ở lại trang. Test: danh sách chord chuyển tiếp từ bảng phím, có phím người dùng đặt lại.
3. **Server chưa chạy lúc mở tool** (trường hợp thường gặp nhất): trang phải tự hiện khi server lên. Test: engine giả trả từ chối rồi thành công.
4. **Bản cũ đọc dữ liệu mới:** `layout.json` có `toolDock`, cài đặt có `workspace_tools`. Test với parser đóng băng V1 và V2.0.
5. **URL lạ trong ô nhập** (`javascript:alert(1)`, `http://user:pass@host`, `localhost:5173` thiếu scheme, `[::1]:8080`, khoảng trắng ở đầu): hoặc chuẩn hoá đúng, hoặc báo lỗi rõ, không bao giờ nạp scheme lạ.

---

## 11. ⚠ Kiểm tay (cần người, máy thật)

### 11.1 macOS (Mac thật, macOS 14 trở lên và nếu có thể macOS 12)

1. Thêm tool `http://localhost:<cổng>` của một app Vite; trang hiện trong vùng tool; cửa sổ đổi cỡ không để lại khung cũ.
2. Bảng lệnh (⌘⇧P), menu chuột phải, toast và panel thông báo vẽ **trên** trang.
3. Gõ Telex `tieesng vieejt` vào ô trong trang ra "tiếng việt" có gạch chân lúc gõ; ⌘C/⌘V trong trang.
4. Bấm vào ô nhập của pane AI thì gõ vào đó; bấm lại vào trang thì trang nhận phím.
5. Trong trang đang giữ phím: ⌘T mở tab, ⌘⇧B đóng vùng tool, ⌘1 về tab 1.
6. Cuộn bằng trackpad, con trỏ đổi hình trên link.
7. `http://127.0.0.1:<cổng>` tải được (ATS, D19).
8. Đăng nhập một tool, thoát, mở lại: vẫn đăng nhập. Safari không thấy cookie đó.
9. VoiceOver: đọc được thanh của tool; ghi lại trang đọc được tới đâu.

### 11.2 Windows (Windows 10 1809+ hoặc 11, 100 % và 150 %)

Đặt `tool-embed = on` trong tệp cấu hình rồi kiểm:
1. Mục 1, 3 (UniKey/EVKey Telex và Telex có sẵn), 4, 6, 8 như macOS.
2. Mở bảng lệnh, menu, hộp thoại: trang tạm ẩn, tấm thay thế hiện, đóng lớp phủ thì trang về đúng chỗ.
3. 150 %: chữ nét, bấm trúng chỗ.
4. Kéo đổi rộng vùng tool, thu nhỏ/phóng to cửa sổ: trang theo đúng khung, không lòi ra ngoài.
5. Máy không có WebView2 Runtime: thông báo D8 §8.

**Đạt** cả 5 mục thì đổi `auto` thành nhúng trên Windows (một dòng mã, có test).

---

## 12. Phạm vi

**Trong V2-3:** mọi thứ ở §3–§9; engine macOS; engine Windows sau cờ `tool-embed`; gợi ý cổng gồm cả server do agent chạy.

**Ngoài V2-3:**
- Tool trên điện thoại (V2-4).
- Agent thấy hoặc điều khiển tool (`ui.browser.*`, chụp màn hình); trình duyệt A6 đầy đủ (thanh địa chỉ, ⌥-bấm vào cổng).
- Tải tệp trong tool; mỗi tool một kho cookie; tool ở workspace SSH qua port forward (người dùng tự gõ URL đã forward).
- Hai tool cạnh nhau trong một workspace.

---

## 13. Rủi ro

| Rủi ro | Mức | Xử lý |
|---|---|---|
| Platform view macOS lỗi ở máy thật (IME, overlay, cuộn) | Trung bình–Cao | §11.1; engine gói trong interface, nên đổi sang cửa sổ con native (A6 D3) chỉ đổi một lớp |
| Windows chưa chạy lần nào; build plugin mới có thể hỏng CI Windows | Trung bình | D7 mặc định mở bằng trình duyệt; nhánh `windows-check/v2-3`; người dùng xem CI |
| Trang tool nặng làm app chậm | Thấp–TB | Tối đa 8 trang sống (D5), trang ẩn vẫn chạy JS |
| Cookie tool trùng tên đè nhau | Thấp | D8, có "Xoá dữ liệu của tool" |
| Engine A6 macOS chưa review | Trung bình | Task review riêng trước khi dùng |
