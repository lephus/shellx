# V2-4 — Tool trên điện thoại — Đặc tả thiết kế

- **Ngày:** 2026-10-15
- **Branch:** `shellx-v2`, đẩy lên `main` sau khi test và review.
- **Trạng thái:** Người dùng giao: "soạn spec và làm tất cả V2-2b V2-3 V2-4" (15/10). Các quyết định E1–E22 do người viết spec chốt, mỗi quyết định ghi cái giá nếu sai. Người dùng xem lại khi tiện.
- **Phụ thuộc:** danh sách tool và cờ điện thoại của V2-3 (`ToolEntry`, `ToolRegistry`, `phoneAllowed`, spec `2026-10-15-v2-3-tools-desktop-design.md` D1, D2, D15). **Không** cần engine trình duyệt desktop.
- **Hướng đã được duyệt (14/10, trang đề xuất, mục "Tool trên điện thoại đi đường nào"):**
  1. Bật "Điện thoại" cho một tool trên desktop. Chỉ tool đã bật mới mở được.
  2. App mở một cổng loopback trên máy (127.0.0.1) và cho webview của nó tải từ đó.
  3. Mỗi request đóng gói thành tin `tool.*` trong kênh mã hoá đầu cuối; relay chỉ chuyển byte, không đọc được.
  4. Desktop gọi đúng URL của tool, chặn mọi URL khác, rồi gửi trả lời chia thành khung ≤ 64 KiB.
  5. Bấm trong tool trên điện thoại → request mới đi cùng đường; pane tool trên desktop thấy cùng dữ liệu vì hai bên dùng chung một server.
  - "Không thêm server: điện thoại và desktop vẫn đi qua relay hiện có." Rủi ro đã nêu: băng thông relay (chỉ tool đã bật; giới hạn kích thước; báo rõ khi chậm); webview tải qua cổng loopback (iOS ATS, Android cleartext), WebSocket qua đường hầm.
- **Nền:** `shellx-v2` tại `d8ad686`.
- **Nguồn đã kiểm ngày 15/10/2026:** mã kênh (relay TypeScript, Noise, `AgentChannel`, `MachineClient`, router, mux, V2-2 `ai.*`); `dart:io` của Dart 3.11.1 trong SDK đã cài; pub.dev (`webview_flutter` 4.14.1, `webview_flutter_android` 4.12.0, `webview_flutter_wkwebview` 3.25.1 là bản mới nhất chạy trên Flutter 3.41.4); Apple (ATS `NSAllowsLocalNetworking`, TN3179, TN2277); Android (network security config, cleartext); Vite (`allowedHosts`, token WebSocket, CVE-2025-24010), Next.js `allowedDevOrigins`, Jupyter Server (`check_host`, `check_origin`); RFC 6265. Đo: ChaCha20-Poly1305 thuần Dart của kênh ≈ 32 MiB/s trên Apple M4.
- **Ký hiệu:** "E1" là quyết định của tài liệu này; "V2-2 D3" là của spec V2-2; "V2-3 D15" là của spec V2-3. **ĐT** = điện thoại, **DT** = desktop.
- **V2-4 được phép sửa:** `packages/shellx_core/lib/src/protocol/` (chỉ thêm), `packages/shellx_agent` (proxy, router, mux), `packages/shellx_client`, daemon, app desktop (phần nối), app mobile. **Không sửa:** relay, mô hình phiên AI.

---

## 1. Mục tiêu

Ra khỏi bàn, người dùng mở tool của mình (bảng việc, dashboard, bản dev của sản phẩm đang chạy ở `localhost` trên máy tính) **trên điện thoại**, dùng như trên máy tính: bấm, gõ, xem cập nhật trực tiếp. Không mở cổng nào ra Internet, không cần VPN, không thêm server: mọi byte đi trong kênh mã hoá đầu cuối sẵn có.

### Tiêu chí thành công (đo được)

1. **Danh sách.** Bật 📱 cho một tool trên desktop: trong ≤ 1 s, bộ chọn phiên trên trang máy của điện thoại có nhóm "Tool" với hàng của tool đó (tên, "shop-web · localhost:5173").
2. **Mở nhanh.** App nhỏ (≤ 1 MB, ≤ 30 request): từ lúc chạm tới lúc thấy trang ≤ 3 s trên mạng thường.
3. **Dùng thật.** Bấm, gõ (kể cả Telex), gửi form được; dữ liệu đổi trên điện thoại thì pane tool trên desktop thấy (cùng một server).
4. **Trực tiếp.** WebSocket chạy: app Vite trên điện thoại tự cập nhật khi sửa tệp trên máy tính (HMR).
5. **Tắt là tắt.** Tắt 📱 trên desktop: trong ≤ 1 s trang trên điện thoại hiện "Tool này không còn mở được trên điện thoại.", và không request nào nữa tới được tool.
6. **Chỉ đúng tool.** Từ điện thoại không với tới được cổng hay máy nào khác ngoài cổng của tool đã bật. App khác trên điện thoại gọi vào cổng loopback của ShellX thì bị từ chối (403).
7. **Không làm rơi kênh.** Tải một phản hồi 50 MB qua tool: kênh không rơi, terminal và phiên AI trên cùng điện thoại vẫn chạy (không bị relay đóng vì vượt 500 khung/giây, không mất heartbeat trên mạng thường).
8. **Vào nền rồi quay lại.** App vào nền rồi mở lại: trang tự tải lại và dùng tiếp được.
9. **Bản cũ.** Điện thoại cũ với desktop mới: không nhận tin `tool.*` nào. Điện thoại mới với desktop cũ: không có nhóm "Tool", không chờ vô hạn. Có test cả hai chiều. Mọi test hiện có vẫn xanh.

---

## 2. Kiểm tra hiện trạng (đọc mã ngày 2026-10-15)

| Mảng | Hiện có | Hệ quả cho V2-4 |
|---|---|---|
| Tin trong kênh | `AppMessage` là map CBOR có khoá `t`; `t` lạ → `null` → bỏ qua. Tin đã biết mà sai trường thì kênh rơi. `ai.*` tránh điều đó: giải mã theo tiền tố, lỗi thành `null` (`shellx_core/lib/src/protocol/messages.dart:93-95`, `ai_messages.dart:37-106`) | E6: `tool.*` theo đúng mẫu `ai.*` |
| Cỡ | Một lô niêm phong ≤ 65 493 byte (`kMaxSealedBatchBytes`); một tin quá cỡ làm `seal` ném và **cả kênh rơi** (terminal, AI cũng rơi) (`secure_channel.dart:12-38`, `agent_channel.dart:16-32,118-143`) | E7: mọi tin `tool.*` kiểm cỡ trước khi gửi; dữ liệu ≤ 48 KiB mỗi tin |
| Byte nhị phân | CBOR `bytes` (terminal `output`, AI `body`), không base64 | E6: thân HTTP và tin WebSocket là CBOR `bytes` |
| Relay | Khung ≤ 64 KiB; 500 khung/giây mỗi thiết bị, vượt thì đóng **cả kết nối** (4003); bên nhận tồn > 4 MiB thì bị đóng; chỉ trả heartbeat khi bên nhận tồn ≤ 64 KiB (lỗi M4 đã biết) (`relay/src/hub/user-hub.ts`, `frame-budgets.ts`) | E7: nhịp gửi có trần, cửa sổ nhỏ theo điện thoại |
| Gửi từ điện thoại | `MachineClient._send` gửi **một khung relay cho mỗi lần gọi**, không gộp (`shellx_client/lib/src/machine_client.dart:800-817`) | E8: hộp thư gộp 16 ms cho `tool.*` |
| Gửi từ desktop | `AgentChannel` gộp 16 ms; xả ngay khi `OutputMessage` chờ ≥ 16 KiB; không giới hạn hàng chờ | E7: đếm cả dữ liệu tool; tự giới hạn nhịp |
| Hộp thư desktop | `AgentService` xử lý tin vào **lần lượt từng cái**, `await` mỗi `handle` (`agent_service.dart:205-218,322`) | E9: `handle` của tool trả ngay, mọi I/O chạy nền |
| Ai giữ relay | Mặc định cửa sổ; bật dịch vụ nền thì daemon giữ relay và shell, cửa sổ nối qua mux | E5: proxy chạy ở tiến trình giữ relay |
| Tin mux | Map CBOR `{t, q?, …}`; tin không có `q` mà bên kia không biết thì bị bỏ qua êm (V2-2 §4.6) | E5: `tool.serve` không có `q` |
| App mobile | Không có webview. `url_launcher` có sẵn. iOS 15+, Android `minSdk 26`, `targetSdk 36`. Info.plist không có ATS; Android không có network security config (cleartext bị chặn) | E11, E12 |
| Vòng đời app | Vào nền thì `suspend()` relay, kênh rơi; quay lại thì bắt tay và attach lại (`session_holder.dart:315-335`) | E13: đóng server khi vào nền, mở lại khi quay về |
| `dart:io` 3.11.1 | `HttpClient` mặc định đi qua proxy môi trường (`http_proxy`) không chừa localhost; tự giải nén; tự theo chuyển hướng. `HttpServer` mặc định thêm `X-Frame-Options`, `Content-Type`… `WebSocket.connect` chưa có `maxPayloadLength` | E9, E10: tắt hết, tự giới hạn |

---

## 3. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| E1 | Mở được gì | Chỉ tool có cờ 📱 bật **và** `phoneAllowed` (V2-3 D15): `http`, host là `localhost`, `127.0.0.1` hoặc `[::1]`, cổng 1–65535. Điện thoại gọi tool bằng **id** do desktop đưa, không bao giờ bằng URL (như V2-2 D9 với thư mục). | Tool `https` hay ở máy khác trong mạng chưa mở được trên điện thoại. |
| E2 | Origin trên điện thoại | **Cùng cổng với tool**: server của điện thoại nghe `127.0.0.1:P` **và** `[::1]:P` (P là cổng của tool), webview tải `http://localhost:P/<trang bắt đầu>`. Trang nhận `Host`, `Origin`, `Referer` giống hệt trên máy tính, nên kiểm tra host của Vite, Next.js, Jupyter, Django vẫn qua; cookie và URL tuyệt đối `localhost:P` vẫn đúng. Luôn dùng tên `localhost` trên điện thoại (ATS của iOS 17+ cho phép tên, có thể chặn IP). | Tool chỉ nhận đúng `Host: 127.0.0.1:P` thì phải thêm `localhost` vào danh sách host của nó. |
| E3 | Cổng bị chiếm hoặc < 1024 | Nếu không nghe được P (app khác giữ, hoặc P < 1024 mà hệ điều hành cấm), điện thoại nghe một cổng tạm P′ và báo P′ trong mỗi request (`alias`). Desktop khi đó đổi đúng chỗ, không đụng thân: `Host` thành của tool; `Origin`, `Referer` từ `localhost:P′` thành origin của tool; `Location` tuyệt đối trỏ về tool và `Access-Control-Allow-Origin` thành `localhost:P′`. Trang hiện dải "Đang mở ở cổng P′ vì cổng P bận trên điện thoại. Link ghi rõ cổng P có thể không chạy." | URL ghi cứng `:P` trong mã trang hỏng ở chế độ này. |
| E4 | App nhiều cổng | Khi một tool đang mở, điện thoại phục vụ luôn **mọi tool đã bật của cùng workspace** trên cổng của chúng (frontend :5173 gọi API :8000 vẫn chạy nếu API cũng là tool đã bật). Không bật thì trang gọi tới đó nhận 502 "Tool ở cổng 8000 chưa bật cho điện thoại". | — |
| E5 | Proxy ở đâu | Ở **tiến trình giữ relay**: cửa sổ khi chạy một mình; daemon khi bật dịch vụ nền. Ở chế độ dịch vụ nền, cửa sổ đẩy danh sách tool đã bật cho daemon qua mux `tool.serve {b}` (`b` là JSON), gửi lại mỗi lần đổi; daemon chỉ giữ trong bộ nhớ và quảng bá `tools` trong `hello.caps`. Cửa sổ thoát thì tool vẫn mở được với danh sách cuối (như terminal của daemon). Daemon khởi động lại khi chưa có cửa sổ: danh sách rỗng, điện thoại thấy "Mở ShellX trên máy tính để dùng tool." **Loại bỏ:** luôn chạy proxy ở cửa sổ (byte đi mux hai lần; tool chết khi cửa sổ thoát dù server dev vẫn chạy trong shell của daemon). | Daemon phải có thêm mã proxy (cùng một lớp thuần Dart, dùng chung). |
| E6 | Giao thức | Tin mới §4: `tool.list`, `tool.list.result`, `tool.open`, `tool.opened`, `tool.close`, `tool.req`, `tool.res`, `tool.data`, `tool.ack`, `tool.ws.msg`, `tool.end`. **Giải mã không bao giờ làm rơi kênh:** sai trường hay loại `tool.*` lạ thành `null`. **Phong bì phẳng:** khoá ngắn, header là mảng phẳng `[tên, giá trị, …]`, dữ liệu là CBOR `bytes`, không số thực. **Cờ khả năng:** `session.list.result` có thêm `tools: 1`, chỉ trả cho `session.list {desktop: true}` và chỉ khi tiến trình có proxy tool. Desktop không bao giờ gửi `tool.*` cho điện thoại chưa hỏi. | — |
| E7 | Cỡ và nhịp | **Cỡ:** dữ liệu ≤ 48 KiB mỗi tin (`kToolMaxChunkBytes`); khối header ≤ 32 KiB; mọi tin kiểm `encodeBatch([m]).length ≤ kMaxSealedBatchBytes` trước khi gửi. **Cửa sổ:** mỗi luồng 256 KiB mỗi chiều, ack cộng dồn; mỗi điện thoại tổng ≤ 512 KiB đang bay theo mỗi chiều (để relay không tồn quá lâu và heartbeat vẫn được trả). **Đầy cửa sổ thì dừng đọc nguồn** (tạm dừng luồng phản hồi của tool, hoặc dừng đọc socket của webview), **không bao giờ bỏ byte** như terminal. **Nhịp desktop:** dữ liệu tool ≤ 8 MiB/s và ≤ 150 khung/giây cho cả máy (xô token), chừa chỗ cho terminal, AI, heartbeat dưới trần 500 khung/giây của relay. `AgentChannel` xả ngay khi dữ liệu tool chờ ≥ 48 KiB. | Mạng rất nhanh vẫn chỉ ~8 MiB/s. |
| E8 | Gửi từ điện thoại | `MachineClient` có **hộp thư gộp** cho `tool.*`: gom 16 ms, chia lô bằng `splitIntoBatches` (chuyển sang `shellx_core` để hai bên dùng chung), tối đa 100 khung/giây cho tool. Ack của mọi luồng gộp ≤ 1 lô mỗi 50 ms. | — |
| E9 | Proxy trên desktop | **Đích cố định:** chỉ nối tới `127.0.0.1:P` rồi `[::1]:P` của tool, **không bao giờ phân giải tên**; `HttpClient.findProxy` trả `DIRECT` (bỏ `http_proxy`), `autoUncompress = false`, `followRedirects = false`. **Request:** phương thức là token ≤ 16 ký tự, không `CONNECT`/`TRACE`/`TRACK`; đích phải bắt đầu bằng `/`, ≤ 8 KiB, không có CR, LF, NUL, khoảng trắng, `#`; dựng `Uri(scheme: 'http', host: <ip>, port: P, …)`, không nối chuỗi. **Header:** tên là token, giá trị không CR/LF/NUL, ≤ 100 header, ≤ 32 KiB; bỏ header hop-by-hop, `Forwarded`, `X-Forwarded-*`, `Via`, cookie cổng của điện thoại; `Host`/`Origin`/`Referer` như E2/E3. **Cờ kiểm lại ở mỗi lần mở luồng**, không lấy từ danh sách cũ. Tắt cờ, xoá tool, đổi URL thì mọi luồng của tool đó bị huỷ (`tool.end {disabled}` / `{gone}`). `handle` không bao giờ `await` I/O. | — |
| E10 | Giới hạn | ≤ 32 luồng HTTP và ≤ 16 WebSocket mỗi điện thoại; mở luồng 120 lần dồn rồi 60/giây, vượt thì `busy` (điện thoại trả 503). Thân request ≤ 64 MiB (413). Một tin WebSocket ≤ 16 MiB (đóng 1009). Nối tới tool quá 5 s: `refused`. Chờ header phản hồi quá 60 s: `timeout` (504). Đang truyền thì không giới hạn thời gian (SSE, long-poll). Luồng không nhận được ack nào trong 5 phút thì huỷ. | Upload trên 64 MiB phải làm trên máy tính. |
| E11 | Server trên điện thoại | Chỉ nghe loopback (`InternetAddress.loopbackIPv4`, `loopbackIPv6` với `v6Only`), không bao giờ `any`. **Kiểm `Host`:** chỉ nhận `localhost:<cổng đang phục vụ>`, `127.0.0.1:…`, `[::1]:…`; khác thì 403 (chống DNS rebinding). **Cookie cổng:** webview mở trước `http://localhost:P/__shellx/enter?n=<nonce dùng một lần, sống 10 s>&to=<trang>`; server trả 303 kèm `Set-Cookie: __shellx_<P>=<bí mật 128 bit>; Path=/; HttpOnly; SameSite=Strict`, `Cache-Control: no-store`, `Referrer-Policy: no-referrer`. Mọi request (kể cả nâng cấp WebSocket) phải có cookie này, so sánh thời gian hằng, nếu không thì 403. Tiền tố `/__shellx/` không bao giờ được chuyển đi; cookie bị gỡ trước khi chuyển; `Set-Cookie` của tool trùng tên bị bỏ. Nâng cấp WebSocket và phương thức không an toàn: có `Origin` thì phải là origin của điện thoại; `Sec-Fetch-Site: cross-site` thì 403. Bỏ mọi header mặc định của `HttpServer`. | `fetch(…, {credentials: 'omit'})` tới chính origin bị 403 (hiếm). |
| E12 | Webview | `webview_flutter` 4.14.1 (`webview_flutter_android` 4.12.0, `webview_flutter_wkwebview` 3.25.1). **Điều hướng trang chính:** các origin điện thoại đang phục vụ và `about:blank` thì cho; trang `http`/`https` khác thì hỏi "Mở <host> bằng trình duyệt?" rồi giao `url_launcher`; scheme khác chặn. **Không kênh JS** vào app. **Quyền** camera, micro, vị trí: từ chối. **Hộp thoại JS:** hộp thoại của app ghi tên tool. **Tải tệp, chọn tệp:** chưa hỗ trợ ("Tải tệp chưa làm được trên điện thoại."). **Dữ liệu web:** kho mặc định của webview trong app, giữ qua các lần mở (giữ đăng nhập); Cài đặt › "Xoá dữ liệu của tool". Tiến trình web bị dừng thì tải lại. | Tool cần tải hay chọn tệp phải dùng trên máy tính. |
| E13 | Vòng đời | Server chỉ nghe khi trang tool đang mở **và** app ở trước. App vào nền: đóng server (Apple TN2277), huỷ mọi luồng (`tool.end {aborted}`), relay cũng đã ngắt. Quay lại: bắt tay lại, mở lại server (cổng có thể khác), tải lại trang. Rời trang: đóng server, gửi `tool.close`. | Mỗi lần quay lại app thì trang tải lại (Vite tự nối lại). |
| E14 | iOS, Android | iOS `Info.plist`: `NSAppTransportSecurity › NSAllowsLocalNetworking = true`. Android: `res/xml/network_security_config.xml` cho phép cleartext **chỉ** với `localhost` và `127.0.0.1`, khai trong manifest. Không đổi gì khác (FCM, relay vẫn TLS). | — |
| E15 | Giao diện điện thoại | **Bộ chọn phiên** của trang máy có nhóm **"Tool"** sau "Phiên AI": mỗi tool một hàng (🧩, tên, "workspace · localhost:P"). Có cờ `tools` mà chưa tool nào bật: "Chưa có tool nào bật cho điện thoại. Trên máy tính: thanh của tool › 📱 Điện thoại." **Trang tool** (`ToolRoute`) chồng lên trang máy: thanh trên (‹, tên, "localhost:P · qua máy tính", ↻, ⋯: Về trang đầu, Tải lại), thanh tiến trình mảnh, webview. Lần tải đầu: "Đang tải qua đường hầm…". Nút back của Android lùi trong trang trước, hết trang thì đóng. | Tool không có trên danh sách máy (cần mở kênh tới máy). |
| E16 | Trạng thái lỗi trên điện thoại | `refused`: "Không có gì chạy ở localhost:P trên máy tính." + tự thử lại như V2-3 D13; `disabled`: "Tool này không còn mở được trên điện thoại."; `gone`: "Tool này đã bị xoá trên máy tính."; mất kênh: dải "Đang kết nối lại…", trang giữ nguyên, có kênh lại thì tải lại; `available: false`: "Mở ShellX trên máy tính để dùng tool."; `busy`: trang nhận 503, không báo thêm. | — |
| E17 | Đồng ý | Cờ 📱 của từng tool (mặc định tắt) là sự đồng ý; không thêm công tắc chung. Chỉ điện thoại đã ghép đôi, đang có kênh IK hợp lệ mới tới được (V2-2 D3). Thu hồi điện thoại hay "Thoát hẳn" thì mọi luồng của điện thoại đó bị huỷ. | — |
| E18 | Riêng tư, log | Nội dung (URL, đường dẫn, header, cookie, thân) chỉ đi trong kênh mã hoá đầu cuối; relay chỉ thấy cỡ và nhịp (lộ mức độ hoạt động, chấp nhận). Không log nội dung ở đâu cả, kể cả lỗi (chỉ loại lỗi). `toString()` mọi tin `tool.*` trả `Tên(…)`, có test. | — |
| E19 | Bản cũ | Điện thoại cũ + desktop mới: không bao giờ nhận `tool.*`. Điện thoại mới + desktop cũ: không có `tools: 1` nên không có nhóm Tool. Cửa sổ mới + daemon cũ: daemon thiếu cap `tools` nên cửa sổ không đẩy, điện thoại không thấy tool. Có test với bộ giải mã đóng băng của V2-2 (`d8ad686`). | — |
| E20 | Hiệu năng mong đợi | Mỗi request tốn một vòng qua relay; webview mở ~6 kết nối mỗi host, nên app dev Vite rất nhiều module có thể mất vài giây lần đầu; bản build thường nhanh hơn nhiều. Bộ nhớ đệm của webview giữ tài nguyên `immutable`. Trang dài hơn 3 s thì thanh tiến trình ghi "Đang tải qua máy tính… (n request)". | — |
| E21 | Không làm | Tool `https`, `*.localhost`, máy khác trong mạng; tải và chọn tệp; service worker trên iOS (WKWebView cần App-Bound Domains); thông báo đẩy cho tool; tool trên danh sách máy. | — |
| E22 | Chỉ báo trên desktop | Không có trong V2-4 (desktop không hiện "điện thoại đang mở tool này"). | Người dùng không biết điện thoại nào đang mở tool. |

---

## 4. Giao thức

### 4.1 Tin `tool.*`

Khoá ngắn snake_case. `id` là số luồng (u32) do điện thoại đặt, duy nhất trong một kênh. `tool` là id tool (V2-3 D2). `head` là mảng phẳng `[tên₁, giá trị₁, tên₂, giá trị₂, …]` (chuỗi; byte ngoài ASCII của header HTTP đi theo Latin-1).

| `t` | Chiều | Trường | Ý nghĩa |
|---|---|---|---|
| `tool.list` | ĐT → DT | — | Xin danh sách và nhận mỗi lần nó đổi, tới khi kênh rơi |
| `tool.list.result` | DT → ĐT | `available`, `body` | Danh sách (§4.2); `available: false` khi tiến trình chưa có danh sách |
| `tool.open` | ĐT → DT | `rid`, `tool` | Sắp mở tool: desktop kiểm cờ và thử nối tới cổng |
| `tool.opened` | DT → ĐT | `rid`, `ok`, `code?`, `body?` | Kết quả; `body` liệt kê các tool cùng workspace để phục vụ (E4): `[{id, port, path}]` |
| `tool.close` | ĐT → DT | `tool` | Rời trang; desktop huỷ mọi luồng của tool đó với điện thoại này |
| `tool.req` | ĐT → DT | `id`, `tool`, `m`, `target`, `head`, `alias?`, `ws?`, `end` | Mở luồng HTTP; `ws: true` là nâng cấp WebSocket; `end: true` khi không có thân |
| `tool.res` | DT → ĐT | `id`, `status`, `head`, `end` | Header phản hồi; `101` khi WebSocket mở được |
| `tool.data` | hai chiều | `id`, `data`, `end` | Một mẩu thân (≤ 48 KiB) |
| `tool.ack` | hai chiều | `acks` | Mảng phẳng `[id₁, n₁, id₂, n₂, …]`: đã nhận tới `n` byte (cộng dồn) của mỗi luồng |
| `tool.ws.msg` | hai chiều | `id`, `data`, `text`, `fin` | Một mẩu tin WebSocket; tin lớn chia nhiều mẩu, mẩu cuối `fin: true` |
| `tool.end` | hai chiều | `id`, `code?`, `ws_code?`, `ws_reason?` | Kết thúc hoặc huỷ luồng; `code`: `refused`, `disabled`, `gone`, `busy`, `too_large`, `timeout`, `desktop_closed`, `unavailable`, `aborted`, `bad_request` (hoặc từ mới hơn, đọc thành `aborted`) |

`session.list.result` có thêm `tools: 1` (E6).

### 4.2 Danh sách (`tool.list.result`, `body` JSON)

```json
{"v": 1,
 "tools": [{"id": "k3f9za7q1m", "name": "Bảng việc", "ws": "shop-web",
            "port": 4000, "path": "/", "group": "ws:abc"}]}
```

`group` gom các tool cùng workspace (E4). Không gửi tool chưa bật.

### 4.3 Mux (cửa sổ ↔ dịch vụ nền)

`tool.serve {b}` (cửa sổ → daemon, không có `q`): `b` là JSON bytes `{"v": 1, "tools": [{"id", "name", "ws", "group", "url"}]}` gồm mọi tool đã bật và hợp lệ. Gửi khi cửa sổ nối vào và mỗi lần đổi. Daemon cũ bỏ qua êm.

---

## 5. Luồng một request

1. Webview gửi `GET /src/main.ts` tới `localhost:5173` trên điện thoại.
2. Server điện thoại kiểm `Host` và cookie cổng (E11), gỡ cookie, gán `id`, gửi `tool.req` qua hộp thư gộp (E8).
3. Desktop kiểm cờ và request (E9), nối `127.0.0.1:5173`, gửi request.
4. Header phản hồi về thành `tool.res`, thân thành các `tool.data` ≤ 48 KiB theo cửa sổ và nhịp (E7).
5. Điện thoại ghi thân vào phản hồi HTTP của webview, ack sau mỗi 64 KiB hoặc 50 ms.
6. Hết thân: `tool.data {end: true}`. Lỗi giữa chừng: `tool.end {code}` và điện thoại cắt phản hồi.

WebSocket: `tool.req {ws: true}` → desktop mở `WebSocket.connect` tới tool (cùng đích cố định) → `tool.res {status: 101}` → điện thoại hoàn tất nâng cấp với webview → hai chiều `tool.ws.msg` → `tool.end` khi một bên đóng (kèm mã đóng).

---

## 6. Giao diện và chuỗi (EN + VI)

| Khoá | EN | VI |
|---|---|---|
| `pickerTools` | Tools | Tool |
| `toolRowSub` | {workspace} · localhost:{port} | {workspace} · localhost:{port} |
| `toolsEmpty` | No tools are on for phone yet. On the computer: the tool's bar › 📱 Phone. | Chưa có tool nào bật cho điện thoại. Trên máy tính: thanh của tool › 📱 Điện thoại. |
| `toolViaComputer` | localhost:{port} · via computer | localhost:{port} · qua máy tính |
| `toolLoadingTunnel` | Loading through the tunnel… | Đang tải qua đường hầm… |
| `toolSlow` | Loading through your computer… ({count} requests) | Đang tải qua máy tính… ({count} request) |
| `toolRefusedPhone` | Nothing is running at localhost:{port} on the computer. | Không có gì chạy ở localhost:{port} trên máy tính. |
| `toolDisabled` | This tool can no longer be opened on the phone. | Tool này không còn mở được trên điện thoại. |
| `toolGone` | This tool was deleted on the computer. | Tool này đã bị xoá trên máy tính. |
| `toolNeedsDesktop` | Open ShellX on the computer to use tools. | Mở ShellX trên máy tính để dùng tool. |
| `toolOtherPort` | Opened on port {alias} because port {port} is busy on this phone. Links that name port {port} may not work. | Đang mở ở cổng {alias} vì cổng {port} bận trên điện thoại. Link ghi rõ cổng {port} có thể không chạy. |
| `toolSiblingOff` | The tool on port {port} isn't on for phone. | Tool ở cổng {port} chưa bật cho điện thoại. |
| `toolOpenExternal` | Open {host} in your browser? | Mở {host} bằng trình duyệt? |
| `toolNoDownloads` | Downloads don't work on the phone yet. | Tải tệp chưa làm được trên điện thoại. |
| `toolHome` | Start page | Về trang đầu |
| `toolClearDataPhone` | Clear tool data | Xoá dữ liệu của tool |

---

## 7. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Kênh rơi khi đang tải | Luồng huỷ; dải "Đang kết nối lại…"; có kênh lại thì tải lại trang |
| Tool tắt cờ khi trang đang mở | `tool.end {disabled}` cho mọi luồng; trang chuyển sang E16 |
| Desktop đổi URL tool (cổng khác) | `tool.end {gone}`; danh sách mới; điện thoại mở lại nếu người dùng chạm |
| Request vượt giới hạn | 413 / 431 / 1009 như E10, không làm rơi kênh |
| Tool trả header > 32 KiB | 502 "Phản hồi của tool quá lớn" |
| Cùng cổng của hai máy | Mở tool của máy thứ hai thì trang của máy thứ nhất đóng (một server mỗi cổng) |
| Điện thoại bị thu hồi | Desktop huỷ mọi luồng của nó (E17) |
| Cửa sổ thoát (chạy một mình) | Relay dừng; điện thoại thấy máy offline |
| Cửa sổ thoát (dịch vụ nền) | Tool vẫn chạy với danh sách cuối (E5) |
| Proxy môi trường (`http_proxy`) trên máy tính | Bị bỏ qua (E9), có test |
| Tool chuyển hướng ra origin khác | `Location` giữ nguyên; webview hỏi trước khi mở ngoài (E12) |

---

## 8. Kiểm thử

- **Giao thức (`shellx_core`):** round-trip từng tin; sai trường → `null`, kênh không rơi; `toString` đã giấu; mọi tin lớn nhất vẫn ≤ `kMaxSealedBatchBytes`; bộ giải mã đóng băng V2-2 (`d8ad686`) đọc lô có `tool.*` không lỗi; `session.list.result.tools`.
- **Proxy (`shellx_agent`, với server HTTP/WebSocket thật trên loopback trong test):** đích cố định (thử `@evil.com`, absolute-form, `CONNECT`, CRLF trong header, `Host` lạ); không đi qua `http_proxy` (đặt biến môi trường giả); không theo chuyển hướng; cờ kiểm ở mỗi luồng; tắt cờ huỷ luồng; cửa sổ đầy thì tạm dừng nguồn rồi chạy tiếp, không mất byte (tải 50 MB, so SHA-256); nhịp ≤ 150 khung/giây và ≤ 8 MiB/s; giới hạn E10; WebSocket hai chiều, tin lớn chia mẩu, mã đóng; chế độ cổng tạm E3 (đổi đúng header).
- **Router, mux, daemon:** cờ `tools` chỉ khi có proxy; `tool.serve` từ cửa sổ; daemon cũ bỏ qua; cửa sổ thoát ở chế độ dịch vụ nền vẫn phục vụ.
- **Điện thoại (`shellx_client`):** hộp thư gộp 16 ms và ≤ 100 khung/giây; ack gộp; server loopback thật trong test: kiểm `Host`, cookie cổng (thiếu cookie 403, nonce dùng hai lần 403), gỡ cookie, `/__shellx/` không đi qua, `Sec-Fetch-Site`, nâng cấp WebSocket; cổng bị chiếm → cổng tạm; vào nền đóng server.
- **App mobile (widget):** nhóm Tool trong bộ chọn, danh sách rỗng, trang tool ở các trạng thái E16 (webview giả), dải cổng tạm, hỏi trước khi mở ngoài.
- **Đầu cuối:** desktop + điện thoại trong cùng test qua hub giả (như V2-2): mở tool, tải trang, WebSocket, tắt cờ.

---

## 9. Review Focus

1. **Một tin quá cỡ làm rơi cả kênh** (terminal, AI cũng mất): header rất dài, cookie to, tin WebSocket lớn. Test: tin lớn nhất của mỗi loại vẫn vừa một lô.
2. **Relay đóng kết nối vì quá 500 khung/giây**, trên desktop (rơi mọi điện thoại) hay điện thoại (rơi mọi máy): trang Vite hàng trăm module, tải lớn trên mạng nhanh. Test: đếm khung với xô token.
3. **Mất dữ liệu khi cửa sổ đầy** (chép nhầm cách "vòng đệm rồi reset" của terminal). Test: tải 50 MB, so băm.
4. **Với tới thứ không phải tool** qua đích request, `Host`, chuyển hướng, `http_proxy`. Test: từng đường.
5. **App khác trên điện thoại** gọi vào cổng loopback, hoặc trang ở origin khác (DNS rebinding). Test: thiếu cookie, `Host` lạ, `Origin` lạ.

---

## 10. ⚠ Kiểm tay (cần người, điện thoại thật, máy Mac)

1. iPhone (iOS 17 hoặc 18): tool Vite `http://localhost:5173` mở được; HMR chạy (sửa tệp trên máy tính, trang trên điện thoại đổi); gõ Telex trong ô của trang.
2. Tool khai bằng `http://127.0.0.1:8000` (Django hoặc Jupyter) mở được trên iPhone (E2 dùng `localhost`).
3. Android 10, 14, 16: như mục 1 (cleartext localhost, E14).
4. Cổng thấp (tool ở cổng 80 trên máy tính) và cổng bị chiếm (một app khác trên điện thoại nghe cùng cổng): chế độ cổng tạm E3 và dải báo.
5. App frontend + API hai cổng, cả hai bật: trang gọi API được (E4).
6. Vào nền rồi quay lại: trang tải lại, dùng tiếp.
7. Mạng chậm (Network Link Conditioner 3G): tải ảnh lớn, terminal cùng lúc vẫn chạy, kênh không rơi sau 1 phút.
8. Tắt 📱 trên desktop khi điện thoại đang mở: trang báo trong ≤ 1 s.
9. VoiceOver / TalkBack trong trang tool: ghi lại đọc được tới đâu.

---

## 11. Phạm vi

**Trong V2-4:** mọi thứ ở §3–§8.

**Ngoài V2-4:** E21; sửa lỗi heartbeat M4 trong relay (cần triển khai relay); chỉ báo trên desktop E22; giải mã ở isolate riêng hay AEAD native trên điện thoại.

---

## 12. Rủi ro

| Rủi ro | Mức | Xử lý |
|---|---|---|
| ATS iOS chặn `127.0.0.1` hay `ws://` dù có `NSAllowsLocalNetworking` | Trung bình | E2 luôn dùng `localhost`; §10 mục 1–2 |
| Heartbeat relay (M4) rơi khi tải lớn trên mạng chậm | Trung bình | E7: tối đa 512 KiB đang bay mỗi điện thoại; §10 mục 7 |
| Trang dev nhiều module tải chậm | Trung bình (trải nghiệm) | E20 báo rõ; bộ nhớ đệm webview |
| Giải mã thuần Dart tốn CPU trên điện thoại cũ | Thấp–TB | Đo ở §10; isolate riêng là việc sau |
| Webview gói ghim dưới bản mới nhất | Thấp | Nâng cùng lúc nâng Flutter |
