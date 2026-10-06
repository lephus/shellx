# A6 — Pane trình duyệt nhúng trên desktop — Đặc tả thiết kế

- **Ngày:** 2026-10-07
- **Trạng thái:** Người dùng giao toàn quyền cho controller (như A1–A5). Quyết định W1–W7 do controller chốt (ràng buộc); D1–D38 do người viết spec chốt trong phạm vi W1–W7, sau khi đọc tài liệu pub.dev của `webview_flutter` 4.14.1, `webview_flutter_wkwebview` 3.27.0, `webview_windows` 0.4.0 và `desktop_webview_window` 0.3.0. Tất cả ghi ở bảng §2 kèm cái giá nếu sai.
- **Lộ trình:** A1 → A2 → A4 → A3 → A5a → A5b → **A6 (tài liệu này)** → A7 CLI/socket → A8 SSH/tmux → A9 skills, phím tắt tuỳ biến, file cấu hình.
- **Thứ tự thực thi:** A6 **chạy sau khi A3 đã merge vào `main`** (bắt buộc: pane trình duyệt là một loại lá trong cây pane A3). Phần khôi phục (§3.7, D29) cần A5a đã merge; phần gắn lại (D29) cần A5b. Theo lộ trình A5a/A5b merge trước A6; nếu chưa, plan bỏ qua bước khôi phục và ghi lại (plan Task 10).
- **Tài liệu đi kèm:** UI addendum `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a6.md` (đo đạc, token, wireframe, chuỗi; ràng buộc cho phần nhìn); plan `docs/superpowers/plans/2026-10-07-desktop-browser-a6.md`.
- **Giữ nguyên:** spec A1 (D1–D16), A2 (C1–C8, D1–D19), A4 (N1–N9, D1–D27), A3 (P1–P9, D1–D30), A5a (R0–R8, D1–D26), A5b (B1–B9, D1–D30). Tài liệu này chỉ **thêm** và ghi rõ chỗ nào sửa.
- **Ký hiệu:** "A3 D13" = quyết định D13 của spec A3; "W1"/"D1" không tiền tố = của tài liệu này.

---

## 1. Mục tiêu

Như cmux: **một pane trình duyệt nằm cạnh terminal trong cùng tab**, để xem ngay ứng dụng web đang chạy ở `localhost` (dev server, Storybook, Jupyter, tài liệu) mà không rời ShellX, và để **agent (Claude Code, script) điều khiển được** trình duyệt đó: mở URL, chạy JavaScript lấy kết quả JSON, chụp ảnh, đọc console và các request mạng, chờ trang tải xong. A6 dựng pane, thanh công cụ, engine trên từng nền tảng, chính sách an toàn và API nội bộ `BrowserController`; A7 mới mở API đó ra CLI/socket (A6 định nghĩa sẵn hình dạng lệnh, §3.6).

### Tiêu chí thành công (đo được)

1. **Mở từ phím tắt:** tab có một pane terminal đang chạy `python3 -m http.server 8000` (A2 thấy `:8000`) → ⌘⇧B (Windows Ctrl+Shift+Alt+B) → trong ≤ 1 s tab có hai pane: terminal bên trái, pane trình duyệt bên phải (50/50, A3 D3) đang tải `http://localhost:8000/`, pane mới có focus (nội dung web nhận bàn phím). Tab không có cổng → pane mở `about:blank` và ô địa chỉ có focus.
2. **Mở từ cổng A2:** ⌥-click (Windows Alt+click) `:8000` trên dòng sidebar → tab đó được chọn, pane trình duyệt mở bên phải pane focus với `http://localhost:8000/`. Bấm thường vẫn mở trình duyệt hệ thống (A2 D9). ⌥-click lần nữa khi tab đã có pane trình duyệt ở cổng 8000 → focus pane đó, không mở pane thứ hai.
3. **Thanh công cụ:** gõ `localhost:3000` + Enter → `http://localhost:3000/`; gõ `3000` → `http://localhost:3000/`; gõ `example.com` → `https://example.com/`; gõ `hello world` → không điều hướng, ô báo "Không phải địa chỉ web" (không bao giờ gửi chữ gõ tới công cụ tìm kiếm). Lùi/Tiến/Tải lại/Dừng chạy đúng và bị mờ đúng lúc; thanh tiến trình 2 px hiện khi đang tải; đầu pane (A3 D15) hiện tiêu đề trang. Nút "Mở trong trình duyệt hệ thống" mở URL hiện tại (chỉ http/https) bằng trình duyệt mặc định.
4. **Chỉ báo an toàn:** `http://localhost`, `http://127.0.0.1`, `http://[::1]`, `http://app.localhost` → biểu tượng "trang trên máy này", không cảnh báo; `https://…` → ổ khoá; `http://example.com` → biểu tượng cảnh báo `warn` + chữ "Không bảo mật". Lỗi chứng chỉ → trang lỗi của pane, không có cách bỏ qua.
5. **Phím tắt khi nội dung web có focus:** ⌘L (Windows Ctrl+L) chọn hết ô địa chỉ; ⌘R (F5 / Ctrl+R) tải lại; ⌘[ / ⌘] (Alt+← / Alt+→) lùi/tiến; Esc khi đang tải → dừng (khi không tải, Esc thuộc về trang); Ctrl+F6 chuyển vùng; ⌘W đóng pane; ⌘⌥mũi tên (A3) chuyển pane. Tất cả hoạt động **cả khi** focus nằm trong một ô nhập của trang.
6. **Focus:** bấm vào nội dung web → pane đó thành pane focus (viền A3); ⌘⌥← sang terminal → gõ vào shell được ngay, không ký tự nào lọt vào trang; Ctrl+F6 từ nội dung web → thanh công cụ trình duyệt → sidebar → (dải đăng nhập) → về nội dung web.
7. **Agent (qua `BrowserController`, test tự động; CLI ở A7):** `navigate("http://localhost:8000/")` + `waitForLoad()` trả `{url, title}`; `evalJs("return document.title")` trả `"Directory listing for /"`; `evalJs("return await fetch('/').then(r => r.status)")` trả `200`; `evalJs("return window")` trả lỗi `not_serializable`; `screenshot()` trả PNG có đúng kích thước khung nhìn × tỉ lệ điểm ảnh; `console()` thấy `console.log('xin chào')` của trang; `network()` liệt kê request `GET /` kèm mã 200 (khi engine cho biết).
8. **An toàn:** với cài đặt mặc định, `evalJs`/`screenshot`/`console`/`network` trên `https://example.com` trả lỗi `forbidden_origin`; bật "Cho phép agent điều khiển mọi trang" (tray → Trình duyệt, có hộp xác nhận) → chạy được. Trang **không** gọi được gì của ShellX ngoài việc gửi dữ liệu console/mạng/kết quả eval (dữ liệu, không phải lệnh).
9. **Cô lập:** đăng nhập một trang trong pane → thoát ShellX → mở lại → trang đó **chưa đăng nhập** (cookie đã xoá). Bật "Giữ dữ liệu trình duyệt" → lần sau còn đăng nhập. Không bao giờ thấy cookie/lịch sử của Safari/Chrome/Edge của người dùng.
10. **Khôi phục (A5a):** tab có terminal + pane trình duyệt ở `http://localhost:8000/docs` (tỉ lệ 40/60) → ⌘Q → mở lại → cùng cây pane, pane trình duyệt tải lại `http://localhost:8000/docs` (không giữ cuộn, form, phiên đăng nhập trừ khi giữ dữ liệu).
11. **Điện thoại không đổi:** `session.list` của điện thoại giống hệt trước A6 (pane trình duyệt không phải phiên); điện thoại không thấy, không điều khiển được pane trình duyệt.
12. **Trợ năng:** mọi nút thanh công cụ có nhãn vi/en và tooltip kèm phím tắt; VoiceOver đọc được nội dung trang trên macOS (engine); thanh tiến trình có giá trị; mọi thao tác làm được bằng bàn phím (WCAG 2.1.1). Windows: giới hạn Narrator ghi ở D2.
13. **Không hồi quy:** mọi test A1–A5 vẫn xanh; tab không có pane trình duyệt trông và hoạt động giống hệt A3; binary daemon A5b không nạp plugin webview.

---

## 2. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| W1 | Mô hình và lối mở (controller) | Pane trình duyệt là **loại pane mới** trong cây pane A3, cạnh pane terminal; mở bằng ⌘⇧B / Ctrl+Shift+Alt+B "Chia trình duyệt", menu terminal, menu dòng, hoặc ⌥-click cổng A2 (thay vì trình duyệt hệ thống) | — |
| W2 | Thanh công cụ (controller) | Ô URL (sửa được, Enter điều hướng, ⌘L focus), lùi/tiến/tải lại/dừng, "Mở trong trình duyệt hệ thống", tiến trình tải, tiêu đề trang ở đầu pane; ưu tiên localhost (http cho localhost/127.0.0.1/::1; http khác hiện "không bảo mật") | — |
| W3 | Engine (controller: chọn ở D1–D3) | macOS WKWebView qua `webview_flutter(_wkwebview)` nếu nhúng được trong cây view Flutter; Windows WebView2 qua `webview_windows`; không nhúng được → cửa sổ con native đặt đè lên pane | — |
| W4 | Lập trình được (controller) | `BrowserController` nội bộ: navigate, evalJs → JSON, screenshot PNG, console, network (nếu engine cho), chờ tải. Hình dạng lệnh định nghĩa ở A6, mở ra ở A7. Chỉ tiến trình của người dùng qua IPC có xác thực (A5b/A7). JS eval tắt với origin không cục bộ trừ khi bật "Cho phép agent điều khiển mọi trang" (mặc định tắt) | — |
| W5 | Cô lập (controller) | Hồ sơ riêng, không bền mỗi phiên app (xoá cookie khi thoát), có cài đặt giữ dữ liệu; không chạm hồ sơ trình duyệt hệ thống | — |
| W6 | Khôi phục, điện thoại (controller) | A5a khôi phục URL (không trạng thái trang). Điện thoại không thấy pane trình duyệt trong A6 | — |
| W7 | Trợ năng (controller) | Trợ năng nội dung web là của engine; nút thanh công cụ có nhãn vi/en; phím ⌘L, ⌘R, ⌘[, ⌘], Esc dừng; focus vào/ra web view đoán được (vòng Ctrl+F6 gồm nó) | — |
| D1 | Engine macOS | `webview_flutter` **^4.14.1** + `webview_flutter_wkwebview` **^3.27.0** (macOS hỗ trợ từ 3.15.0, tối thiểu macOS 10.15; app đặt 12.0). WKWebView là **platform view** trong cây Flutter: widget Flutter vẽ đè được (menu, toast, hộp thoại, bảng thông báo A4). Những gì Dart API không có (dừng tải, chụp ảnh, script đầu tài liệu, xoá dữ liệu, chuyển phím) làm bằng **trợ lý native** `BrowserNative.swift` trong Runner, lấy `WKWebView` qua API ngoài của plugin `webView(forIdentifier:withPluginRegistry:)` với `WebKitWebViewController.webViewIdentifier`. `setInspectable(true)` (Web Inspector của Safari dùng được) | Platform view macOS còn non (đồng bộ first responder ↔ focus Flutter, cuộn, con trỏ) — kiểm tay ở plan Task 1; nếu API ngoài không có trên macOS → tìm `WKWebView` bằng cách duyệt cây `NSView` của platform view (1 ngày) |
| D2 | Engine Windows | `webview_windows` **0.4.0** (WebView2), **vendored** vào `third_party/webview_windows` với `SHELLX_PATCHES.md` (tiền lệ `flutter_pty`), vì bản phát hành cuối đã ~2 năm và cần năm bản vá: (a) `capturePreview` → PNG (WebView2 `CapturePreview`), (b) chuyển phím tắt của ShellX khi WebView2 có focus (`AcceleratorKeyPressed`), (c) huỷ tải file (`DownloadStarting`), (d) chặn điều hướng khung trên cùng tới scheme khác http/https/about (`NavigationStarting`, D10) — plugin gốc không có móc điều hướng, (e) `moveFocus` (`ICoreWebView2Controller::MoveFocus`) để đưa bàn phím vào trang theo D16. Plugin vẽ **ngoài màn hình** qua `Windows.Graphics.Capture` vào texture Flutter → widget Flutter vẽ đè được. Yêu cầu Windows 10 1809+ và WebView2 Runtime (có sẵn trên Windows 11; thiếu → pane hiện hướng dẫn tải, D14) | **Narrator không đọc được nội dung trang** (nội dung vẽ ngoài màn hình, cây UIA của WebView2 không nối vào cửa sổ) — giới hạn ghi ở HANDOFF và UI; IME tiếng Việt (Telex qua UniKey/EVKey) và DPI phải kiểm tay; ta phải tự bảo trì bản vendored |
| D3 | Phương án dự phòng + cổng quyết định | Plan Task 1 là spike **⚠ MANUAL** trên máy thật: nhúng, vẽ đè, bàn phím, IME, focus, chụp ảnh, VoiceOver. **Không đạt** (bàn phím/IME/focus hỏng mà không vá được) → dừng và chuyển sang dự phòng: **cửa sổ con native** (macOS: `WKWebView` là subview của `FlutterView` đặt theo hình chữ nhật pane; Windows: WebView2 có cửa sổ — `CreateCoreWebView2Controller` với HWND con) đặt theo `PaneRects` mỗi khung hình; khi một lớp Flutter mở đè (menu, toast, hộp thoại, bảng thông báo) cửa sổ con bị **ẩn** và thay bằng ảnh chụp cuối; focus chuyển bằng `makeFirstResponder`/`SetFocus` và trả về Flutter khi có phím chuyển vùng. Ước tính thêm 3–4 ngày. `desktop_webview_window` bị loại: nó mở **cửa sổ riêng**, không phải pane | Dự phòng làm hiệu ứng đè xấu hơn (pane trình duyệt "trống" khi menu mở); nhưng có trợ năng đầy đủ trên Windows |
| D4 | Id pane trình duyệt | Pane trình duyệt có id **âm** (−1, −2, …) cấp bởi bộ đếm của desktop, không dùng lại trong một lần chạy app. `PaneLeaf(int)` của A3 **không đổi**; mọi hàm `pane_layout.dart` (chia, gỡ, hướng, cân bằng) dùng nguyên. `isBrowserPaneId(id) ⇔ id < 0`. Id phiên agent luôn dương nên không bao giờ trùng | Mã nào coi mọi lá là phiên (vd. `view(id)`) phải lọc `id > 0`; test chặn ở plan Task 5 |
| D5 | Tab và pane terminal | Tab luôn có **≥ 1 pane terminal** (bản ghi `PaneSession`): pane trình duyệt chỉ sinh ra bằng **chia** một tab sẵn có, không tạo tab. Pane terminal **cuối cùng** của một tab còn pane trình duyệt mà thoát mã 0 → **giữ lại** như mã ≠ 0 (A3 D7: dòng thoát, Enter đóng), để pane trình duyệt không biến mất vì shell thoát. Đóng pane terminal cuối (⌘W, ×, Enter trên dòng thoát) → đóng **cả tab** gồm pane trình duyệt (A3 D6), không hỏi thêm ngoài A1 D15 | Người dùng mất pane trình duyệt khi đóng terminal cuối; mở lại chỉ cần ⌘⇧B (URL nằm trong lịch sử cổng) |
| D6 | Getter của tab | Các getter A3 D2 (`title`, `cwd`, `driver`, `terminal`, …) trỏ vào **pane terminal hoạt động** = pane focus nếu là terminal, không thì pane terminal dùng gần nhất (MRU, A3 D8). Dòng sidebar, dòng ngữ cảnh A2, tiêu đề cửa sổ, hộp xác nhận theo pane đó. Dấu số pane A3 D19 **đếm cả** pane trình duyệt. Không thêm dấu mới trên dòng | Khi pane trình duyệt focus, tiêu đề cửa sổ vẫn là tên terminal (tiêu đề trang ở đầu pane) |
| D7 | Mở bằng lệnh | ⌘⇧B / Ctrl+Shift+Alt+B, mục "Mở pane trình duyệt" ở menu terminal (A3 D21) và menu dòng: chia **phải** pane focus của tab (menu dòng: tab đó, chọn nó trước). URL đầu: cổng nhỏ nhất của **pane terminal hoạt động** (A2 `ports`) → `http://localhost:<cổng>/`; không có cổng → `about:blank` và focus vào ô địa chỉ. Quy tắc chỗ (A3 D4) dùng cỡ tối thiểu của D31 cho pane mới; không đủ → toast A3 `paneSplitNoRoom`. Phím không lặp. Windows: chord có Alt chỉ nhận Alt trái (A3 D20) | — |
| D8 | ⌥-click cổng | Trên dòng sidebar, ⌥-click (Windows Alt+click) `:PORT` → chọn tab; nếu tab đã có pane trình duyệt mà URL hiện tại có host cục bộ (D11) **và** cùng cổng → focus pane đó (không tải lại); không thì chia phải pane focus với `http://localhost:PORT/`. Thay thế bàn phím/trình đọc màn hình (WCAG 2.1.1): menu dòng thêm "Mở :PORT trong pane trình duyệt" theo đúng quy tắc mục cổng A2 (một/hai cổng: một mục mỗi cổng; từ 3 cổng: menu con tối đa 5 cổng, UI-A6 §4.3). Tooltip cổng thêm dòng gợi ý ⌥-click | — |
| D9 | Ô địa chỉ | `parseAddressInput(text)`: cắt khoảng trắng hai đầu. (1) Chỉ chữ số 1–65535 → `http://localhost:<n>/`. (2) Có scheme `http`/`https` → URL đó (host phải có). (3) `about:blank` → nguyên. (4) Không scheme, không khoảng trắng, dạng `host[:port][/…]` với host là `localhost`, `*.localhost`, IPv4, `[IPv6]` → `http://…`; host có dấu chấm → `https://…`. (5) Còn lại (có khoảng trắng, scheme khác như `file:`, `javascript:`, `data:`, chữ không có dấu chấm) → **lỗi** "Không phải địa chỉ web", không điều hướng. Không bao giờ tìm kiếm web | Người quen gõ từ khoá vào ô địa chỉ phải mở trình duyệt hệ thống |
| D10 | Chính sách điều hướng | Điều hướng khung trên cùng chỉ cho `http`, `https`, `about:blank`; scheme khác (link `mailto:`, `file:`, app scheme) bị chặn → toast trung tính "Pane trình duyệt chỉ mở trang http và https". `window.open`/`target=_blank` → mở **trong cùng pane** (Windows `WebviewPopupWindowPolicy.sameWindow`; macOS script đầu tài liệu D21 chuyển thành `location.assign`). Tải file xuống bị huỷ → toast "Pane trình duyệt không tải file xuống — dùng “Mở trong trình duyệt hệ thống”". `<input type=file>`: theo engine (macOS có thể không mở hộp chọn file — ngoài phạm vi) | Luồng đăng nhập OAuth bằng cửa sổ bật lên có thể hỏng (dùng trình duyệt hệ thống) |
| D11 | Phân loại origin | `classifyOrigin(Uri)`: **local** = `http`/`https` với host `localhost`, `*.localhost`, `127.0.0.0/8`, `::1` (cả `[::1]`), `0.0.0.0`; **secure** = `https` còn lại; **insecure** = `http` còn lại; **none** = `about:blank`/khác. Dùng cho chỉ báo (W2) và cổng an toàn của agent (D20). Không tin DNS: `foo.localhost` không phân giải ra ngoài theo RFC 6761 trên cả hai engine | Một dịch vụ lạ nghe trên localhost được agent eval mà không cần bật cài đặt (cùng máy, cùng người dùng — chấp nhận) |
| D12 | Bố cục pane | Pane trình duyệt = đầu pane A3 (22, luôn hiện vì tab có ≥ 2 pane) + **thanh công cụ 32** + nội dung web. Đầu pane: biểu tượng địa cầu thay chấm trạng thái, tiêu đề trang (không có thì host, không có thì "Trình duyệt"), × và các hành vi A3 D15 (chuột giữa đóng, nháy đúp phóng to). Chi tiết đo đạc: UI-A6 §2 | — |
| D13 | Tiến trình tải | Thanh 2 px `accent` dính đáy thanh công cụ khi đang tải. macOS: theo `onProgress` 0–100. Windows: engine không báo phần trăm → thanh **tĩnh** 30 % khi bắt đầu, 100 % khi xong rồi ẩn. Không hoạt ảnh lặp (A1 nguyên tắc); giảm chuyển động → nhảy thẳng | Windows không thấy tiến độ thật |
| D14 | Trang lỗi | Lỗi tải (kết nối bị từ chối, DNS, hết giờ, chứng chỉ) → **giao diện lỗi Flutter** đè nội dung web: tiêu đề, mô tả theo loại, "Thử lại", "Mở trong trình duyệt hệ thống". `localhost` bị từ chối → "Chưa có gì chạy ở localhost:3000" + gợi ý chạy server. Windows không có WebView2 Runtime → "Cần Microsoft Edge WebView2 Runtime" + nút mở trang tải của Microsoft (https). Mã HTTP 4xx/5xx: trang của server hiện bình thường (không phải lỗi) | — |
| D15 | Phím tắt | Khi **pane trình duyệt** focus (thanh công cụ hoặc nội dung): ⌘L / Ctrl+L focus ô địa chỉ (chọn hết); ⌘R / Ctrl+R và F5 tải lại; ⌘[ / Alt+← lùi; ⌘] / Alt+→ tiến; Esc dừng **chỉ khi đang tải** (không tải → Esc tới trang). Khi nội dung web có focus, engine giữ bàn phím: phím của ShellX (bảng trên + ⌘⇧B, ⌘W, ⌘T, ⌘1–9, ⌃Tab, ⌘⌥mũi tên, ⌘⇧U, ⌘⇧I, Ctrl+F6, Ctrl+Shift+F6) được **chặn trước khi tới trang** và chuyển về Flutter: macOS bằng `NSEvent.addLocalMonitorForEvents(.keyDown)` của `BrowserNative.swift` khi first responder nằm trong một WKWebView của ShellX; Windows bằng bản vá `AcceleratorKeyPressed` (D2b). Danh sách chord do Dart gửi xuống (một nguồn: `browserForwardedChords`). ⌘C/⌘V/⌘A/⌘Z và ⌘+/− **không** chuyển: thuộc về trang | Trang không bắt được những chord đó (vd. ⌘L của một trình soạn thảo web) — giống cmux/VS Code |
| D16 | Focus và vùng | Vùng 1 A1 §3.6 = pane focus; với pane trình duyệt là **nội dung web**. Ctrl+F6 từ nội dung web → **vùng mới "thanh công cụ trình duyệt"** (vào ô địa chỉ) → sidebar → dải đăng nhập → nội dung web; Ctrl+Shift+F6 ngược lại. Trong thanh công cụ: Tab/Shift+Tab giữa các nút và ô địa chỉ. Enter trong ô → điều hướng, focus về nội dung web. Esc trong ô → trả chữ về URL hiện tại, focus về nội dung web. Bấm chuột vào nội dung web → `focusPane` (A3) trước khi engine xử lý. Chuyển tab/pane bằng phím → focus vào nội dung web của pane trình duyệt (như terminal). Pane trình duyệt bị ẩn (tab khác, phóng to pane khác) không bao giờ giữ first responder | Đồng bộ focus Flutter ↔ native là phần rủi ro nhất (D1, D3) |
| D17 | Trợ năng | Pane: `Semantics(container, label: "Pane {i} trên {n} — Trình duyệt: {tiêu đề}")` (A3 D22). Mỗi nút: nhãn + tooltip có phím. Ô địa chỉ: `textField` nhãn "Địa chỉ trang". Thanh tiến trình: `Semantics(label: "Đang tải", value: "{n} %")`. Chỉ báo origin có nhãn ("Trang trên máy này" / "Kết nối bảo mật" / "Không bảo mật"). Đọc lên (lịch sự): khi điều hướng **do người dùng** (Enter, lùi, tiến, tải lại) xong → "Đã tải {tiêu đề}"; lỗi → tiêu đề lỗi; agent bắt đầu điều khiển → D25. Nội dung web: engine (VoiceOver đọc WKWebView; Windows xem D2) | Windows: người dùng trình đọc màn hình phải dùng "Mở trong trình duyệt hệ thống" |
| D18 | `BrowserController` (W4) | Một đối tượng mỗi pane trình duyệt, trên interface `BrowserEngine` (§3.3). API: `navigate(Uri)`, `back()`, `forward()`, `reload()`, `stop()`, `Future<BrowserPageInfo> waitForLoad({Duration timeout})`, `Future<Object?> evalJs(String body, {Duration timeout})`, `Future<Uint8List> screenshot()`, `List<ConsoleEntry> console({int since, int limit})`, `List<NetworkEntry> network({int since, int limit})`, `BrowserPaneState get state`. Lỗi là `BrowserError(code, message)` với mã của D9 A5b cộng `forbidden_origin`, `timeout`, `eval_error`, `not_serializable`, `result_too_large`, `unavailable`, `navigation_blocked`, `load_failed`, `browser_limit`, `no_room` | — |
| D19 | Ngữ nghĩa `evalJs` | `body` là **thân một hàm async** (`return …` để trả giá trị; dùng được `await`). Desktop dựng văn bản script: hàm bọc + kiểm origin trong trang (D20) + `JSON.stringify` kết quả + gửi về qua kênh cầu nối (D21) kèm **nonce 128 bit** của lần gọi. Engine chạy script trực tiếp (`runJavaScript` / `executeScript`) — **không** dùng `eval()` nên CSP của trang không chặn. `undefined` → `null`. Không tuần tự hoá được (vòng, DOM node, `window`) → `not_serializable`. Ngoại lệ → `eval_error` với `message` ≤ 2 KiB. Kết quả JSON ≤ **48 KiB** (khung IPC A5b 64 KiB) → vượt thì `result_too_large`. Hết giờ mặc định 10 s, tối đa 30 s → `timeout`. Chỉ khung trên cùng | Muốn chạy trong iframe phải tự lấy `contentWindow` (cùng origin) |
| D20 | Cổng an toàn agent (W4) | Origin hiện tại không phải **local** (D11) và cài đặt "Cho phép agent điều khiển mọi trang" tắt → `evalJs`, `screenshot`, `console`, `network` trả `forbidden_origin`. `navigate`, `back/forward/reload/stop`, `waitForLoad`, `list` luôn được (không đọc nội dung). Kiểm **hai lần**: ở Dart trước khi gọi và **trong script** (`location` lúc chạy, chống trang đã chuyển đi giữa chừng); screenshot kiểm URL trước và sau khi chụp, khác → bỏ ảnh, `forbidden_origin`. A6 mở rộng cổng của W4 từ "eval" sang cả ba thao tác đọc nội dung, vì ảnh chụp/console của trang đã đăng nhập lộ dữ liệu y như eval | Agent không chụp được trang tài liệu công khai nếu người dùng chưa bật cài đặt |
| D21 | Cầu nối trang → ShellX | Một script đầu tài liệu `browser_bootstrap.js` (asset, khung trên cùng, thế giới của trang): móc `console.*`, `error`, `unhandledrejection`, `PerformanceObserver` (resource + navigation), bọc `fetch`/`XMLHttpRequest` để biết phương thức và mã; chuyển `target=_blank`/`window.open` (macOS, D10). Gửi qua **một** kênh: macOS `JavaScriptChannel` "ShellxBrowser"; Windows `window.chrome.webview.postMessage` → `webMessage`. Mọi message là JSON `{"t": "console"|"net"|"title"|"eval", …}` ≤ 64 KiB (đủ cho kết quả eval 48 KiB), sai dạng/quá cỡ/loại lạ → bỏ. `title` cần vì plugin macOS không báo đổi tiêu đề. Đây là **dữ liệu không tin cậy** (trang tự gửi được message giả): không bao giờ là lệnh, chỉ ghi vào bộ đệm console/network hoặc khớp nonce của một lần eval đang chờ. Trang **không** gọi được hàm nào của ShellX | Trang cố ý giả console/network làm agent hiểu sai (chỉ ảnh hưởng chính trang đó) |
| D22 | Console | Bộ đệm vòng **500** mục mỗi pane, giữ qua điều hướng (mỗi mục có `url`), xoá khi đóng pane. Mục: `seq` (tăng dần), `ts`, `level` (`log`, `info`, `warn`, `error`, `debug`), `text` (đối số nối bằng khoảng trắng, đối tượng qua `JSON.stringify` an toàn, ≤ **2 KiB**), `url`. Lỗi chưa bắt → `error` | Log dài bị cắt |
| D23 | Network | **Nỗ lực tốt nhất**: không engine nào (qua plugin) cho xem mạng thật. Từ `PerformanceObserver`: URL, loại (`initiatorType`), thời lượng, cỡ truyền; từ bọc `fetch`/XHR: phương thức, mã trạng thái. Không header, không body (riêng tư). Bộ đệm vòng **500**, URL ≤ 2 KiB. Kết quả luôn mang `partial: true` | Không thấy request của Service Worker/WebSocket frame/request bị chặn trước khi tạo |
| D24 | Ảnh chụp và chờ tải | Chụp **khung nhìn** (không cả trang) thành PNG ở tỉ lệ điểm ảnh màn hình: macOS `WKWebView.takeSnapshot`; Windows `CapturePreview` (bản vá D2a). Với A7, ảnh ghi ra `<app support>/browser/shots/<32 hex>.png` (thư mục 0700, file 0600) và trả **đường dẫn** (khung IPC ≤ 64 KiB); file bị xoá sau 10 phút, khi thoát, và khi khởi động. `waitForLoad`: xong khi lần điều hướng hiện tại kết thúc (macOS `onPageFinished`, Windows `LoadingState.navigationCompleted`); lỗi tải → `BrowserError('load_failed', loại)`; mặc định 15 s, tối đa 60 s | Ảnh cả trang (cuộn) chờ A7+ |
| D25 | Dấu "agent đang điều khiển" | Mỗi lệnh agent (D18, đến từ A7) bật dấu **"Agent"** trên thanh công cụ trong 10 s kể từ lệnh cuối (UI-A6 §2.4); đọc lên "Agent đang điều khiển pane trình duyệt" một lần mỗi đợt (cách đợt trước ≥ 60 s). Người dùng luôn thấy agent đang làm gì trên trang | — |
| D26 | Hồ sơ (W5) | **macOS:** WKWebView dùng kho dữ liệu mặc định **của app** (`~/Library/WebKit/pro.shellx.desktop`, tách khỏi Safari). "Giữ dữ liệu" tắt → `BrowserNative.clearWebsiteData()` (`WKWebsiteDataStore.default().removeData(ofTypes: allWebsiteDataTypes(), modifiedSince: .distantPast)`) **khi khởi động** (trước webview đầu tiên — dọn cả sau crash) và **khi thoát**. **Windows:** `WebviewController.initializeEnvironment(userDataPath:)` một lần trước webview đầu: tắt → `%LOCALAPPDATA%\ShellX\webview\s-<16 hex>` mới mỗi lần chạy; mọi thư mục `s-*` khác bị xoá khi khởi động (không xoá được lúc thoát vì tiến trình WebView2 còn giữ khoá); bật → `%LOCALAPPDATA%\ShellX\webview\profile`. Không bao giờ trỏ vào hồ sơ Edge/Chrome. Đổi công tắc: macOS tắt → xoá ngay; Windows áp dụng từ lần mở sau (UI nói rõ) | Crash trên Windows để lại thư mục cũ tới lần mở sau |
| D27 | Cài đặt | Khoá settings (UI ghi, A5b D13): `browser_keep_data` (bool, mặc định `false`), `browser_agent_all_origins` (bool, mặc định `false`). Tray: submenu mới **"Trình duyệt"** ngay sau "Terminal" (A5a D13): ☐ "Giữ dữ liệu trình duyệt (cookie, đăng nhập)", ☐ "Cho phép agent điều khiển mọi trang", "Xóa dữ liệu trình duyệt". Bật "mọi trang" → hộp xác nhận (UI-A6 §5) | — |
| D28 | Giới hạn | Tối đa **8** pane trình duyệt mỗi app (mỗi pane là tiến trình WebKit/Edge ~100–200 MB). Vượt → toast "Đã đạt tối đa 8 pane trình duyệt". Không tính vào giới hạn 32 phiên (A1 D8) | Người cần nhiều hơn phải đóng bớt |
| D29 | Khôi phục (W6) | A5a `layout.json` (v vẫn 1) thêm loại lá `{"browser": "<paneKey>", "url": "<URL>" \| null}`. URL lưu khi là `http`/`https`, **bỏ userinfo**, bỏ fragment, ≤ 2048 ký tự; khác → `null` (khôi phục thành `about:blank`). Khi nạp: lá trình duyệt được dựng với id âm mới; trang **chỉ tải khi tab của nó hiện lần đầu** (tab đang chọn tải ngay) — không mở 8 trang lúc khởi động. Quá D28 → bỏ lá. Chế độ gắn lại A5b D18: lá trình duyệt luôn dựng lại từ URL (pane trình duyệt sống trong UI, không trong daemon). Không lưu lịch sử lùi/tiến, cuộn, form | Hạ cấp về bản trước A6 thấy lá lạ → A5a D11 bỏ cả `layout.json` (có `.bak`) |
| D30 | Điện thoại | Không đổi protocol: pane trình duyệt không là phiên, không có trong `session.list`, không vào relay. Phiên điện thoại mở vẫn thành tab mới (A3 D24) | — |
| D31 | Cỡ và sắp xếp | Pane trình duyệt tham gia đủ các thao tác A3: chia, đóng, chuyển focus theo hướng, phóng to, cân bằng, kéo đường chia, đổi cỡ bằng phím. Tối thiểu **240 × 160 px** logic (gồm đầu pane + thanh công cụ). Không có "lưới" nên không gọi `resize` phiên nào (A3 D13 chỉ cho terminal). Pane bị ẩn (tab khác/phóng to pane khác) **giữ** webview (không tải lại khi hiện lại) | Trang ẩn vẫn chạy JS (tốn CPU nếu trang nặng) |
| D32 | Hộp thoại JS | `alert`/`confirm`/`prompt` (macOS: `setOnJavaScriptAlertDialog`/`Confirm`/`TextInput`) → hộp thoại A1 nhỏ trên cửa sổ, tiêu đề = host trang; đồng thời ghi một mục console `info` "[dialog] …". Windows: hộp thoại mặc định của WebView2. Đang có `evalJs` chờ mà trang mở hộp thoại → eval tiếp tục chờ tới hết giờ | Agent gặp `confirm()` sẽ hết giờ (A7 có thể thêm lệnh trả lời hộp thoại) |
| D33 | Nhật ký và riêng tư | Không bao giờ log URL, tiêu đề, chữ console, script hay kết quả eval; chỉ loại sự kiện, mã lỗi, `runtimeType`. Dữ liệu duyệt web chỉ ở máy. Trang chính sách riêng tư §4 + HANDOFF §16 thêm: bố cục lưu URL pane trình duyệt (có thể chứa token trong query, vd. Jupyter) | — |
| D34 | Vòng đời engine | Tạo engine khi pane được dựng; `dispose` khi pane đóng (huỷ eval đang chờ với `not_found`). Thoát app: dispose tất cả rồi D26. Engine lỗi khi khởi tạo → giao diện lỗi D14 (`unavailable`) | — |
| D35 | Daemon A5b | Pane trình duyệt sống trong **tiến trình UI**. Engine headless của daemon (A5b D2/D3) **không** đăng ký plugin webview. A7 tới bằng `ui.browser.*` mà daemon chuyển tiếp tới UI (A5b D9/D22); không có UI → `not_found` | Agent không dùng được trình duyệt khi cửa sổ ShellX đã thoát |
| D36 | Ngoài phạm vi engine | Phóng to trang (⌘+/−), tìm trong trang (⌘F), in, tải file, hộp chọn file, quyền camera/mic/vị trí (từ chối hết), thông báo web, PWA, tiện ích mở rộng | — |
| D37 | Menu chuột phải | Trong nội dung web: menu của engine (có "Inspect Element" khi inspectable). Trên đầu pane/thanh công cụ: menu A3 + "Sao chép địa chỉ trang", "Mở trong trình duyệt hệ thống" | — |
| D38 | Hình dạng lệnh A7 | §3.6. A6 hiện thực `BrowserCommandHandler.handle(Map request) → Future<Map>` (thuần, có test), **không** nối vào IPC; A7 chỉ cần đăng ký nó cho `ui.browser.*` | Nếu A7 đổi khung tin nhắn, chỉ lớp nối đổi |

**Sửa A2:** D9 — ⌥-click cổng mở pane trình duyệt (D8); bấm thường giữ nguyên. Menu dòng thêm mục cổng (D8).
**Sửa A3:** P1 "mỗi pane = một phiên agent" → mỗi pane **terminal** = một phiên; pane trình duyệt không phải phiên (D4). D2 getter → pane terminal hoạt động (D6). D7 → ngoại lệ D5. D13 chỉ pane terminal. D21 menu thêm "Mở pane trình duyệt".
**Sửa A5a:** §3.1 thêm lá trình duyệt (D29); bộ kiểm D11 chấp nhận lá đó.
**Sửa A5b:** D18 chế độ gắn lại giữ lá trình duyệt (D29); D2/D3 danh sách plugin không gồm webview (D35).

---

## 3. Kiến trúc

```
third_party/webview_windows/ (mới, vendored 0.4.0 + SHELLX_PATCHES.md)   chụp, chuyển phím, huỷ tải, chặn scheme, focus (D2)
apps/desktop
 ├─ assets/browser/browser_bootstrap.js (mới)    script đầu tài liệu (D10, D21–D23)
 ├─ lib/src/browser/ (mới)
 │   ├─ browser_url.dart          parseAddressInput, classifyOrigin, isNavigable, urlForRestore    (D9–D11, D29)
 │   ├─ browser_engine.dart       BrowserEngine (interface), sự kiện engine, BrowserEngineFactory   (D1, D2, D34)
 │   ├─ browser_bridge.dart       buildEvalScript, parseBridgeMessage, ConsoleEntry, NetworkEntry   (D19, D21–D23)
 │   ├─ browser_controller.dart   BrowserController: lệnh, cổng an toàn, bộ đệm, chờ, ảnh, dấu agent (D18–D25)
 │   ├─ browser_registry.dart     Provider: id pane âm → BrowserController; cấp id; giới hạn 8       (D4, D28)
 │   ├─ browser_profile.dart      Hồ sơ theo nền tảng, dọn khi khởi động/thoát                       (D26)
 │   ├─ browser_commands.dart     BrowserCommandHandler (hình dạng lệnh A7)                           (D38)
 │   ├─ browser_host.dart         AppBrowserHost + browserCommandHandlerProvider (A7 nối vào IPC)     (D38)
 │   ├─ browser_chords.dart       chuỗi chord dùng chung Dart/Swift/C++                               (D15)
 │   ├─ browser_dialogs.dart      hàng đợi hộp thoại alert/confirm/prompt                            (D32)
 │   ├─ shots_dir.dart            thư mục ảnh 0700/0600, dọn 10 phút                                  (D24)
 │   └─ engines/
 │       ├─ wk_webview_engine.dart    macOS: webview_flutter_wkwebview + kênh BrowserNative          (D1)
 │       └─ webview2_engine.dart      Windows: webview_windows (vendored)                             (D2)
 ├─ lib/src/terminal/terminal_tabs.dart   TerminalTab.browsers, openBrowser, closePane cho id âm, D5, D6
 ├─ lib/src/platform/settings_store.dart  + browser_keep_data, browser_agent_all_origins              (D27)
 ├─ lib/src/tray/…                        submenu "Trình duyệt"                                        (D27)
 ├─ lib/src/ui/terminal/
 │   ├─ browser_pane_view.dart (mới)      thanh công cụ, ô địa chỉ, tiến trình, chỉ báo, lỗi, dấu agent (D12–D17, D25)
 │   ├─ pane_tree_view.dart (A3)          lá âm → BrowserPaneView; cỡ tối thiểu D31
 │   ├─ terminal_shortcuts.dart           OpenBrowserIntent + intent trình duyệt; browserForwardedChords (D15)
 │   ├─ terminal_workspace_page.dart      action, vùng "thanh công cụ trình duyệt" (D16)
 │   ├─ session_tab_row.dart / session_sidebar.dart   ⌥-click cổng, menu dòng                    (D7, D8)
 ├─ lib/src/restore/restore_snapshot.dart (A5a)   SavedBrowser                                         (D29)
 ├─ macos/Runner/BrowserNative.swift (mới)        snapshot, stop, user script, xoá dữ liệu, chặn phím (D1, D15, D26)
 └─ windows/runner/…                              không đổi (phần native nằm trong plugin vendored)
```

Agent (`packages/shellx_agent`), `shellx_core`, mobile, relay, `term/`: **không đổi**.

### 3.1 Mô hình pane

- `TerminalTab` (A3) thêm `Map<int, BrowserPaneState> browsers` (id âm → bản ghi bất biến: `url`, `title`, `loading`, `progress`, `canGoBack`, `canGoForward`, `error` (`BrowserLoadErrorKind?`), `agentActive`, `userNavigation`; getter `origin`). `panes` vẫn chỉ chứa `PaneSession`.
- `TerminalTab.activeTerminalPane` (D6) — getter A3 uỷ quyền vào đây thay vì `focused`.
- `TerminalTabs.openBrowser({int? tabId, Uri? url, SplitAxis axis = SplitAxis.row, bool focus = true}) → int?` (id pane; ném `BrowserError` `not_found`/`browser_limit`/`no_room`, giao diện đổi thành toast); `closePane(int id)` nhận id âm; `focusPane(int id)` nhận id âm; `tabOfPane(int id) → TerminalTab?`; `updateBrowser(int id, BrowserPaneState state)`.
- Engine thì không nằm trong state: `BrowserRegistry` (Riverpod) giữ `BrowserController` theo id, tạo khi `openBrowser`, huỷ khi pane đóng.

### 3.2 `BrowserEngine` (interface, có fake cho test)

```dart
abstract interface class BrowserEngine {
  Stream<BrowserEngineEvent> get events;   // UrlChanged, TitleChanged, LoadStarted, LoadProgress(int),
                                           // LoadFinished, LoadFailed(kind), HistoryChanged(back, fwd),
                                           // BridgeReceived(String json), NavigationBlocked,
                                           // DownloadBlocked, ShortcutForwarded(chord)
  BridgeTransport get transport;           // webkit | webview2 (D21)
  Future<void> load(Uri url);
  Future<void> goBack(); Future<void> goForward(); Future<void> reload(); Future<void> stop();
  Future<void> runScript(String script);   // không trả giá trị; kết quả qua BridgeReceived (D19)
  Future<Uint8List> capturePng();          // D24
  Future<void> setForwardedChords(List<String> chords);   // D15
  Widget buildView();                      // platform view (macOS) / texture (Windows)
  Future<void> dispose();
}
```

### 3.3 `BrowserController`

Nghe `events`, giữ `BrowserPaneState` (báo ra qua `onState`, registry chép vào `TerminalTabs.updateBrowser`); `navigate`/`reload` đặt `loading = true` **ngay** (không chờ sự kiện đầu của engine) để `waitForLoad` gọi ngay sau đó chờ đúng trang mới; ghi console/network vào bộ đệm vòng, khớp kết quả eval theo nonce, thực thi cổng D20 với `browser_agent_all_origins`, đặt dấu D25 (`agentCommand()` gọi bởi `BrowserCommandHandler`, không bởi thanh công cụ).

### 3.4 Trợ lý native macOS (`BrowserNative.swift`, kênh `pro.shellx.desktop/browser`)

`snapshot(id) → PNG`, `stop(id)`, `addBootstrap(id, source)` (WKUserScript `.atDocumentStart`, `forMainFrameOnly: true`), `clearWebsiteData()`, `setForwardedChords([chord])`; sự kiện ngược `shortcut(id, chord)` khi monitor chặn một chord (D15). `id` = `webViewIdentifier`.

### 3.5 Bản vá Windows (`third_party/webview_windows/SHELLX_PATCHES.md`)

(a) phương thức `capturePreview` → `ICoreWebView2::CapturePreview(PNG)` vào `IStream` → bytes; (b) `setForwardedAccelerators([chord])` + sự kiện `acceleratorKey` từ `ICoreWebView2Controller::add_AcceleratorKeyPressed` (đặt `Handled = TRUE` cho chord trong danh sách); (c) `add_DownloadStarting` → `Cancel = TRUE` + sự kiện `downloadBlocked`; (d) `add_NavigationStarting` (chỉ khung trên cùng) → scheme ngoài `http`/`https`/`about` thì `Cancel = TRUE` + sự kiện `navigationBlocked`; (e) phương thức `moveFocus` → `MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC)`. Mỗi bản vá có test Dart cho phần kênh và kiểm tay.

### 3.6 Hình dạng lệnh A7 (`ui.browser.*`, D38)

Theo khung A5b D9 (`{"t", "q", …}` → `result`/`error`). `pane` = id pane (âm). Mọi lệnh trên pane bật D25.

| `t` | Trường yêu cầu | `result` |
|---|---|---|
| `ui.browser.list` | — | `{panes: [{pane, tab, url, title, loading, origin}]}` |
| `ui.browser.open` | `url`, `tab?` (mặc định tab đang chọn), `target?` (pane để chia), `direction?` `right`\|`down`, `focus?` (mặc định **false**: agent không cướp bàn phím) | `{pane, tab}` |
| `ui.browser.navigate` | `pane`, `url`, `wait?` `none`\|`load` (mặc định `load`), `timeoutMs?` | `{url, title}` |
| `ui.browser.back` / `forward` / `reload` / `stop` | `pane` | `{}` |
| `ui.browser.wait` | `pane`, `timeoutMs?` (≤ 60000) | `{url, title}` |
| `ui.browser.eval` | `pane`, `script` (thân hàm async, ≤ 32 KiB), `timeoutMs?` (≤ 30000) | `{json: "<chuỗi JSON ≤ 48 KiB>"}` |
| `ui.browser.screenshot` | `pane` | `{path, width, height, bytes}` |
| `ui.browser.console` | `pane`, `since?` (seq), `limit?` (≤ 200), `level?` | `{entries: [{seq, ts, level, text, url}], next}` |
| `ui.browser.network` | `pane`, `since?`, `limit?` (≤ 200) | `{entries: [{seq, ts, url, type, method?, status?, durationMs?, size?}], next, partial: true}` |
| `ui.browser.close` | `pane` | `{}` |

Lỗi: `bad_request` (thiếu/sai trường, URL không hợp lệ theo D9/D10), `unknown_type`, `not_found` (pane/tab), `no_room` (A3 D4/D31), `forbidden_origin`, `navigation_blocked`, `timeout`, `eval_error`, `not_serializable`, `result_too_large`, `load_failed`, `browser_limit`, `unavailable`. Các lệnh DOM tiện dụng (`query`, `click`, `fill`) là việc của A7, dựng trên `eval` và cùng cổng D20.

### 3.7 Khôi phục (A5a)

`SavedPaneNode` thêm `SavedBrowser({required String key, String? url})`; `RestoreSnapshot.tryParse` nhận `{"browser", "url"}`; `TerminalTabs.restore` dựng lá trình duyệt bằng `openBrowserRestored(tabId, key, url)` (không tải tới khi tab hiện, D29); `RestorePersistence` cấp `paneKey` cho id âm như id phiên.

---

## 4. Luồng dữ liệu

```
⌘⇧B ─► OpenBrowserIntent ─► TerminalTabs.openBrowser(url: cổng của pane terminal hoạt động)
          ├─ D28 (≤ 8) ✗─► toast · D31 chỗ ✗─► toast paneSplitNoRoom
          └─ id âm ─► splitPane(layout) ─► BrowserRegistry.create ─► BrowserEngineFactory (mac/win)
                     └─ BrowserPaneView ─► engine.buildView() ─► load(url)
engine.events ─► BrowserController ─► BrowserPaneState (url, title, progress…) ─► thanh công cụ / đầu pane
trang console.log ─► bootstrap ─► kênh ─► parseBridgeMessage ─► bộ đệm 500
A7 (sau này) ─► daemon ui.browser.eval ─► UI BrowserCommandHandler ─► BrowserController.evalJs
          ─► cổng D20 ─► buildEvalScript(nonce) ─► engine.runScript ─► kênh {t:eval, nonce} ─► JSON ≤ 48 KiB
phím ⌘L khi web có focus ─► monitor native / accelerator ─► ShortcutForwarded ─► Intent Flutter
```

---

## 5. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Dev server chưa chạy | Trang lỗi D14 "Chưa có gì chạy ở localhost:PORT", "Thử lại" |
| Server dừng khi trang đang mở | Trang giữ nội dung cũ (engine); tải lại → trang lỗi |
| Trang chuyển hướng sang origin không cục bộ giữa lúc eval | Script tự kiểm origin → `forbidden_origin` (D20) |
| Trang treo vòng lặp vô hạn | Eval hết giờ (`timeout`); thanh công cụ vẫn dùng được (engine riêng tiến trình) |
| Tiến trình web crash | Trang lỗi D14 loại `crashed` + "Tải lại" |
| Windows thiếu WebView2 Runtime | Trang lỗi `unavailable` + link tải (D14) |
| 9 pane trình duyệt | Toast D28 |
| Đóng tab khi eval đang chờ | Eval trả `not_found`, engine huỷ |
| Kéo đường chia qua pane trình duyệt | Như A3; webview đổi cỡ mỗi khung hình (không có SIGWINCH) |
| Menu/hộp thoại/bảng thông báo mở đè lên pane | Vẽ đè bình thường (D1, D2); dự phòng D3 thì ẩn webview và hiện ảnh chụp |
| URL dài/có ký tự Unicode | Ô hiện URL đã giải mã IDN/percent cho dễ đọc, lưu dạng mã hoá |
| Trang đổi tiêu đề liên tục | Đầu pane cập nhật tối đa 4 lần/s |
| Message cầu nối sai dạng/quá cỡ/quá nhiều | Bỏ; tối đa 200 message/s mỗi pane, vượt thì bỏ phần dư (đếm vào một mục `warn` "[shellx] dropped N") |
| `about:blank` | Không chỉ báo origin; agent eval được (origin `none` coi như local — trang rỗng) |

---

## 6. Kiểm thử

- **`browser_url_test`** (thuần): D9 đủ các nhánh (số cổng, 0/65536, scheme, IPv6, `*.localhost`, khoảng trắng, `javascript:`, `file:`), D11, D29 `urlForRestore` (userinfo, fragment, độ dài).
- **`browser_bridge_test`**: `buildEvalScript` chứa nonce, kiểm origin, không chứa `eval(`; `parseBridgeMessage` với message hợp lệ/sai dạng/quá cỡ; cắt 2 KiB.
- **`browser_controller_test`** (`FakeBrowserEngine`, `fake_async`): sự kiện → `BrowserPaneState`; `waitForLoad` ngay sau `navigate` chờ trang mới; eval thành công/lỗi/không tuần tự hoá/quá cỡ/hết giờ/nonce sai bị bỏ; cổng D20 (cả trong script); screenshot đổi URL giữa chừng → bỏ; console/network vòng 500 và `since`; `waitForLoad` thành công/lỗi/hết giờ; dấu agent 10 s; giới hạn 200 message/s.
- **`terminal_tabs_browser_test`**: id âm, `openBrowser` chia phải với URL cổng, D5 (terminal cuối thoát mã 0 giữ lại; đóng terminal cuối đóng tab), D6 getter, D28, D31 tối thiểu, `resize` không bao giờ gọi cho id âm, ⌥-click tái dùng pane.
- **`browser_profile_test`**, **`shots_dir_test`** (thư mục tạm): D26, D24 quyền và dọn.
- **`browser_commands_test`**: mỗi lệnh §3.6 và mỗi mã lỗi.
- **Widget:** `browser_pane_view_test` (thanh công cụ, ô địa chỉ D9, Esc/Enter, chỉ báo, tiến trình, trang lỗi, dấu agent, nhãn Semantics), phím tắt (⌘⇧B, ⌘L, ⌘R, ⌘[, ⌘], Esc chỉ khi tải), `ShortcutForwarded` → intent, vùng Ctrl+F6.
- **Khôi phục:** `restore_snapshot_test` lá trình duyệt; `terminal_tabs_restore_test` tải lười.
- **Thử tay (HANDOFF §16, ⚠ MANUAL):** macOS và Windows thật — nhúng, vẽ đè menu/toast/hộp thoại, bàn phím và IME tiếng Việt trong ô nhập của trang, ⌘L/Ctrl+L khi ô trang có focus, VoiceOver đọc trang, Narrator (ghi giới hạn), ảnh chụp, cookie sau khi thoát, WebView2 thiếu, DPI 150 %, 8 pane.

---

## 7. Ngoài phạm vi A6

Mở API ra CLI/socket (**A7**); lệnh DOM tiện dụng (`query`/`click`/`fill`, A7); ảnh cả trang; xem header/body mạng; DevTools Protocol; nhiều tab trong một pane trình duyệt; pane trình duyệt trên điện thoại; tab chỉ có trình duyệt; đồng bộ cookie với trình duyệt hệ thống; tìm trong trang, phóng to trang, in, tải file, hộp chọn file, quyền thiết bị (D36); Narrator cho nội dung web trên Windows (chỉ có với dự phòng D3); phím tắt tuỳ biến (**A9**).
