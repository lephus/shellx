# V2-2b — Điện thoại và phiên AI, phần hai — Đặc tả thiết kế

- **Ngày:** 2026-10-15
- **Branch:** `shellx-v2`, đẩy lên `main` sau khi test và review. **Riêng phần relay** nằm ở nhánh `v2-2b-relay` và chỉ gộp vào `main` khi người dùng đồng ý, vì mọi thay đổi `relay/**` trên `main` tự triển khai lên server thật (`.github/workflows/deploy.yml`).
- **Trạng thái:** Người dùng giao: "soạn spec và làm tất cả V2-2b V2-3 V2-4" (15/10). Các quyết định B1–B26 do người viết spec chốt, mỗi quyết định ghi cái giá nếu sai. Người dùng xem lại khi tiện.
- **Nền:** spec V2-2 (`2026-10-14-v2-2-phone-ai-design.md`), nhất là §11.2 (danh sách V2-2b) và §13; `shellx-v2` tại `d8ad686`.
- **Tài liệu này thay** chữ "trả lời ngay trên thông báo: app mở ở nền (iOS cho khoảng 30 s)… relay coi kết nối thứ hai là `replaced`" ở V2-2 §11.2 bằng B6–B10 (nút mở app). Trả lời mà không mở app là việc sau (B10).
- **Nguồn đã kiểm ngày 15/10/2026:** mã nguồn tại `d8ad686` (hub, router, mux, `MachineAi`, `AiRuntime`, mô hình, relay `notifications.ts` / `fcm.ts` / `user-hub.ts`, app mobile phần push, voice, AI); mã nguồn gói trong `~/.pub-cache` (`firebase_messaging` 16.7.0, `flutter_local_notifications` 22.3.2); Apple (thông báo có nút, `UNNotificationActionOptions`, delegate trước khi khởi động xong), Android (thông báo, cleartext, giới hạn chạy nền), FlutterFire (issue #18699, PR #18357, #18501), pub.dev (`image_picker` 1.2.4, `flutter_local_notifications` 22.3.2), ACP `session/list`.
- **Ký hiệu:** "B1" là quyết định của tài liệu này; "D13" là của spec V2-2; "V2-1 D10" là của spec V2-1. **ĐT** = điện thoại, **DT** = desktop.
- **V2-2b được phép sửa:** như V2-2 (giao thức chỉ thêm, `shellx_ai` remote, `shellx_agent`, `shellx_client`, daemon, app mobile, phần nối desktop), **thêm:** mô hình V2-1a ở đúng hai chỗ (B3 id duy nhất, B24 nguồn của tin), lớp hoàn tác của desktop (B19, tách khỏi widget), relay (B6, nhánh riêng).

---

## 1. Mục tiêu

Làm nốt những gì V2-2a để lại, để người dùng ra khỏi bàn vẫn làm trọn một phiên AI trên điện thoại:
- trả lời xin quyền ngay từ thông báo;
- đổi chế độ, model;
- gửi ảnh, nhắc tệp bằng `@`, nói thay vì gõ;
- xem thay đổi, xem diff, hoàn tác một lượt;
- xem đủ một thẻ lớn;
- mở lại phiên cũ, chọn thư mục cho tab chưa có;
- thấy phiên AI ngay trên danh sách máy;
- tự nối lại sau khi máy tính khởi động lại ShellX;
- trên máy tính thấy rõ tin nào gửi từ điện thoại.

Kèm hai sửa lỗi của V2-2a tìm thấy khi nghiên cứu (B3, B5).

### Tiêu chí thành công (đo được)

1. **Nút trên thông báo.** Thông báo xin quyền có hai nút **"Từ chối"** và **"Cho phép"**. Chạm "Cho phép": mở khoá máy, app mở, qua khoá Face ID của app thì câu trả lời được gửi **đúng một lần**; trang phiên hiện "Đã cho phép: Sửa src/main.ts" trong ≤ 3 s sau khi app mở. Yêu cầu đã được trả lời ở nơi khác hay đã hết: "Yêu cầu này đã được trả lời ở nơi khác." và **không trả lời gì khác**.
2. **Chế độ, model.** Chạm dòng phụ "Claude · Hỏi trước · Opus" → bảng chọn chế độ, model, mức suy nghĩ; chọn xong, máy tính đổi trong ≤ 2 s. Không bao giờ thấy chế độ bỏ qua xin quyền.
3. **Ảnh.** Chọn tối đa 5 ảnh (thư viện hoặc camera) → hàng ảnh nhỏ → Gửi. Agent trên máy tính nhận ảnh; máy tính hiện ảnh trong tin; điện thoại hiện "2 ảnh". 5 ảnh chụp từ iPhone gửi xong trong ≤ 10 s qua Wi-Fi.
4. **`@` tệp.** Gõ `@sr` → tối đa 8 gợi ý tệp của dự án trong ≤ 1 s; chọn thì thành nhắc tệp như trên máy tính.
5. **Giọng nói.** Nút micro trong ô nhập AI; nói thì chữ hiện vào ô; nói "gửi" ở cuối thì gửi.
6. **Thay đổi, hoàn tác.** Từ dòng "Lượt 3 · 2 tệp đổi" mở danh sách tệp (+/−), chạm một tệp xem diff; "Hoàn tác lượt này" hỏi lại kèm danh sách tệp, rồi hoàn tác trên máy tính; pane AI trên máy tính ghi "Đã hoàn tác 2 tệp (từ điện thoại)".
7. **Xem đủ.** Thẻ bị cắt có "Xem đủ"; mở ra tải hết (≤ 2 MiB) với "Đang tải 3/12".
8. **Lịch sử.** "Lịch sử phiên" liệt kê phiên cũ của agent; chạm một phiên → máy tính mở tab AI mới (không chuyển tab đang xem) và điện thoại vào phiên đó với lịch sử phát lại.
9. **Thư mục.** Tab AI chưa có thư mục: điện thoại chọn một thư mục máy tính đưa ra → agent chạy.
10. **Danh sách máy.** Mở danh sách máy: mỗi máy đang online có dòng "✦ 2 phiên AI · 1 cần bạn" trong ≤ 3 s.
11. **Nối lại.** ShellX trên máy tính khởi động lại: trang phiên trên điện thoại tự nối vào đúng phiên trong ≤ 5 s sau khi tab về, có dòng "Đã nối lại sau khi ShellX khởi động lại."
12. **Nguồn tin.** Tin gửi từ điện thoại hiện "Bạn · từ điện thoại" trên máy tính (cả khi đang xếp hàng).
13. **An toàn id.** Một câu trả lời không bao giờ rơi vào yêu cầu của runtime khác cùng pane (có test).
14. **Bản cũ.** Điện thoại V2-2b với desktop V2-2a, hoặc cửa sổ V2-2b với dịch vụ nền V2-2a: không hiện nút nào của V2-2b, phần V2-2a chạy như cũ. Điện thoại V2-2a với desktop V2-2b: như cũ. Mọi test hiện có vẫn xanh.

---

## 2. Kiểm tra hiện trạng (đọc mã ngày 2026-10-15)

| Mảng | Hiện có | Hệ quả |
|---|---|---|
| Id yêu cầu | Id xin quyền, câu hỏi, tin xếp hàng đếm **theo từng `AiSessionState`** (`session_state.dart:90`); mỗi runtime một state mới (`ai_host.dart:116`). sid (`<epoch>.<pane>`) **không đổi** khi pane đổi runtime (chọn lại thư mục, tắt/bật agent) | **Lỗi V2-2a:** `{sid, permission: 0}` của runtime cũ có thể trúng yêu cầu số 0 của runtime mới → B3 |
| Dịch vụ nền chuyển tiếp | Daemon **giải mã rồi mã hoá lại** mọi tin `ai.*` (`mux_ai.dart:12-28,179-182`): loại mới bị bỏ, khoá mới bị cắt. Cửa sổ mới vẫn nối được daemon cũ (cùng `kMuxProtocol = 1`) | B1, B2 |
| `ai.result` | Không có thân (`ai_messages.dart:365-382`) | B4 |
| Push iOS | `firebase_messaging` 16.7.0; README bắt app UIScene gọi `FLTFirebaseMessagingPlugin.configureNotificationCenterDelegate()` trong `didFinishLaunching`; `AppDelegate.swift` **không gọi** | **Lỗi V2-2a có thể có:** chạm thông báo bị lỡ ở vài trạng thái khởi động → B5 |
| Push agent | `AiPush` không mang id yêu cầu hay lựa chọn; `aiNotice` gửi `{title, body, data: {kind, ai_session}}`; relay thêm `agent_id` | B7 |
| Relay | `POST /v1/notifications` bỏ qua khoá lạ cấp trên cùng; FCM: `notification {title, body}`, `data`, `android.priority high`, `apns.aps.sound`; không `category`, không `tag`. Sửa `relay/**` trên `main` = triển khai thật | B6 |
| Mobile push | Không có `flutter_local_notifications`, không có `onBackgroundMessage`; chạm thông báo mở thẳng phiên (`notification_opener.dart`), không trả lời gì | B8, B9 |
| Chế độ/model | `AiRuntime.setConfig`, `setMode`; desktop: chip, hỏi lại trước "bỏ qua quyền", `rememberConfig` không bao giờ nhớ chế độ bỏ qua quyền. Điện thoại chỉ đọc `mode` | B11 |
| Ảnh | Desktop: ≤ 5 ảnh, ≤ 10 MiB, PNG/JPEG/GIF/WebP theo byte đầu, base64 ngoài isolate UI (`ai_images.dart`). Hub chỉ gửi `[TextBlock]` | B12 |
| Giọng nói | `SpeechInput`, `VoiceCommandParser` (từ khoá "gửi"), `VoiceComposer` gắn với terminal | B14 |
| Hoàn tác | API runtime có (`changesSince`, `changedAfterTurn`, `revert`, `fileBefore`); **logic hoàn tác nằm trong widget desktop** (`ai_changes_panel.dart:116-191`, hộp thoại B14 của V2-1b) | B19: tách lớp `AiUndo` dùng chung |
| Thẻ lớn | Desktop giữ đủ nội dung; điện thoại nhận bản cắt hoặc `big` | B16 |
| Lịch sử | `AiRuntime.listSessions`, desktop `showAiHistory` mở tab mới với `sessionId` | B17 |
| Danh sách máy | Không mở kênh nào; listing AI chỉ có khi đã vào trang máy | B21 |
| Sau khởi động lại | sid có epoch; listing có `acp`; trang phiên giữ sid cố định | B22 |
| Nguồn tin | `UserItem(turn, blocks)`, `QueuedPrompt(id, blocks)` không có nguồn | B24 |

---

## 3. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B1 | Khả năng (hai lớp) | Điện thoại chỉ dùng một tính năng V2-2b khi **cả hai**: (a) router báo `ai: 2` trong `session.list.result` (`kAiProtocol = 2` ở tiến trình giữ relay: daemon khi bật dịch vụ nền), chứng minh đường chuyển tiếp hiểu V2-2b; (b) listing của cửa sổ có `"f": [...]` liệt kê tính năng hub làm được (`config`, `blob`, `files`, `changes`, `revert`, `item`, `history`, `folder`, `push_answer`, `acp_head`). Thiếu một trong hai thì nút tương ứng không hiện. | — |
| B2 | Chuyển tiếp nguyên văn | Từ V2-2b, daemon chuyển tiếp `ai.*` **nguyên văn**: mỗi `AiMessage` giữ map gốc đã giải mã và dùng lại khi mã hoá; loại `ai.*` lạ thành `AiRaw` (giữ map, chiều theo nguồn: từ điện thoại thì vào cửa sổ, từ `ai.out` của cửa sổ thì ra điện thoại). Kiểm cỡ như cũ. Nhờ vậy lần thêm sau chỉ cần sửa cửa sổ. | — |
| B3 | Id duy nhất (sửa lỗi V2-2a) | Id xin quyền, câu hỏi và tin xếp hàng lấy từ **một bộ đếm cho cả tiến trình cửa sổ** (dùng chung cho mọi `AiSessionState`), không bao giờ quay lại 0 trong một lần chạy. Cặp `(sid, id)` vì vậy chỉ chỉ một yêu cầu. Làm **đầu tiên**, trước mọi việc khác. | — |
| B4 | Thân trong `ai.result` | `ai.result` có thêm `body` (byte JSON) tuỳ chọn. Dữ liệu lớn hơn một thân thì điện thoại **kéo từng phần** (`part`): mỗi lần một yêu cầu, nằm trong ngân sách yêu cầu sẵn có (60 dồn, 30/giây), không cần cửa sổ gửi mới. Mã mới: `no_images`, `confirm`, `busy_turn`, `not_ready`, `undo_off`, `too_big`. Điện thoại cũ đọc mã lạ thành câu chung. | — |
| B5 | Delegate thông báo iOS (sửa lỗi V2-2a) | `AppDelegate.application(_:didFinishLaunchingWithOptions:)` gọi `FLTFirebaseMessagingPlugin.configureNotificationCenterDelegate()` (theo README 16.7.0) và đăng ký category `ai_perm` (B8) ngay tại đó. Không thêm `flutter_local_notifications` trên iOS. | — |
| B6 | Relay | Thêm hai khoá tuỳ chọn vào `POST /v1/notifications`: `category` (chỉ nhận `ai_perm`) và `tag` (`^[A-Za-z0-9_.:-]{1,64}$`); sai thì 400. FCM: thêm `apns.payload.aps.category` và `android.notification.tag`; **giữ nguyên khối `notification`** (không có tin chỉ-data, không cần bảng khả năng theo máy). Relay cũ bỏ qua hai khoá. Nhánh `v2-2b-relay`, gộp khi người dùng đồng ý triển khai. | Chưa triển khai relay thì thông báo vẫn như cũ, không có nút. |
| B7 | Desktop xin đẩy kèm nút | `AiPush` có thêm `permission` (id) và hai lựa chọn: **allow** = lựa chọn `allow_once` đầu tiên **không** bật chế độ bỏ qua xin quyền; **reject** = lựa chọn `reject_once` đầu tiên. Không bao giờ `allow_always`/`reject_always` (đổi hành vi về sau, trái tinh thần D13). Thiếu một trong hai thì thông báo thường như cũ. Câu hỏi không có nút. `aiNotice` thêm `data` `perm`, `allow`, `reject` và xin `category: ai_perm`, `tag: ai-<epoch>-<pane>-<perm>`. Hàm nhận diện chế độ bỏ qua xin quyền chuyển sang `package:shellx_ai` để hub dùng. | — |
| B8 | Nút trên iOS | Category `ai_perm` đăng ký native trong `AppDelegate`: **"Từ chối"** trước (`.destructive` + `.foreground`), **"Cho phép"** sau (`.foreground` + `.authenticationRequired`). "Từ chối" đứng trước để cú chạm đúp trên Apple Watch không bao giờ cho phép. Tên nút theo ngôn ngữ máy (`Localizable.strings` en/vi). Chạm nút → iOS mở khoá và mở app → `firebase_messaging` đưa `RemoteMessage.actionIdentifier` qua `getInitialMessage()` / `onMessageOpenedApp`. | Một lần mở khoá và chuyển sang app cho mỗi câu trả lời. |
| B9 | Nút trên Android | Thêm `flutter_local_notifications` 22.3.2 (bật desugaring) và hàm `onBackgroundMessage` (chưa có). Khi tin có `perm`/`allow`/`reject`, hàm này hiện lại **cùng `tag`** một thông báo có hai nút (`showsUserInterface: true`, mở app, cần mở khoá máy) thay cho thông báo hệ thống vẽ. Không mạng trong hàm nền. Chạm nút hay chạm thân của thông báo thay thế đều đi qua `NotificationOpener`. Thông báo thay thế không kịp hiện (máy chặn chạy nền) thì vẫn còn thông báo thường. | Một số máy Android (Xiaomi, Huawei…) có thể không hiện nút. |
| B10 | Gửi câu trả lời | Chỉ khi app **đã ở trước và đã qua khoá Face ID của app**: kiểm dữ liệu (máy đã ghim, `ai_session`, `perm` là số, lựa chọn là đúng một trong hai id mang theo), gửi **một** `ai.answer` bằng kênh thường, chờ `ai.result`, không bao giờ gửi lại sau khi mất kênh (D13). Rồi mở trang phiên kèm kết quả: `ok` → "Đã cho phép: <việc>" / "Đã từ chối: <việc>"; `stale` → "Yêu cầu này đã được trả lời ở nơi khác."; `not_found` → "Phiên AI này đã đóng trên máy tính."; `on_computer` → "Trả lời yêu cầu này trên máy tính."; mất kênh/hết giờ → "Có thể chưa gửi được. Xem trong phiên." **Trả lời không cần mở app** (chạy nền) là việc sau: không áp được khoá Face ID của app, Android phải chạy isolate riêng với kết nối relay thứ hai. | — |
| B11 | Chế độ, model | `ai.config.get {sid, rid}` → `ai.result {body}`: các tuỳ chọn thuộc nhóm `mode`, `model`, `thought_level`, `model_config` cùng lựa chọn hiện tại; **bỏ mọi lựa chọn bật chế độ bỏ qua xin quyền** (hàm B7) và với chế độ chỉ đưa những id đã biết là an toàn (`default`, `plan`, `acceptEdits`, `auto`, `auto_edit` và id agent không bị hàm B7 gắn cờ); tên cắt ≤ 60 ký tự; tối đa 40 lựa chọn mỗi tuỳ chọn (cờ `more`). `ai.config {sid, rid, body: {"id", "value"}}` hoặc `{"mode"}`: desktop kiểm lại với tuỳ chọn **lúc đó** (có, đúng nhóm, giá trị nằm trong danh sách, không bỏ qua xin quyền → `on_computer`) rồi `setConfig` và `rememberConfig` như chip desktop. Agent từ chối → `refused`. Header thêm `model {id, name}`. | Muốn "Bỏ qua mọi quyền" phải làm trên máy tính. |
| B12 | Ảnh | `ai.blob {rid, blob, part, parts, mime?, data}` (ĐT → DT; `data` ≤ 48 KiB; `mime` ở phần 0); mỗi phần một `ai.result`; điện thoại để ≤ 4 phần đang bay. Desktop giữ blob theo điện thoại trong bộ nhớ (≤ 5 × 10 MiB, ≤ 20 MiB mỗi điện thoại), bỏ sau 2 phút không dùng, khi điện thoại rời đi, hoặc khi đã gửi. `ai.prompt` thêm `blobs: [id]`: hub kiểm đủ phần, loại ảnh theo byte đầu (PNG/JPEG/GIF/WebP), agent nhận ảnh (`no_images` nếu không), rồi gửi kèm ảnh qua đường base64 ngoài isolate UI của desktop. Mục gương của tin người dùng có `img: n`. **Điện thoại:** `image_picker` 1.2.4, thư viện (tối đa 5) và camera, thu về ≤ 2048 px, JPEG chất lượng 85 (ảnh HEIC đổi sang JPEG). Mất kênh giữa chừng thì gửi lại **ảnh**, không bao giờ tự gửi lại tin. | Ảnh rất lớn bị thu nhỏ còn 2048 px. |
| B13 | Nhắc tệp | `ai.files {sid, rid, q}` → `ai.result {body: {"files": [đường dẫn tương đối]}}` (≤ 8, dùng chỉ mục dự án và bộ so khớp của ô nhập desktop). `ai.prompt` thêm `files: [đường dẫn]`: hub chỉ nhận đường dẫn **nằm trong thư mục của phiên**, có thật, rồi gửi `ResourceLinkBlock` như desktop. Ô nhập điện thoại: gõ `@` hiện gợi ý. | — |
| B14 | Giọng nói | Nút micro trong ô nhập AI, dùng lại `SpeechInput` và `VoiceCommandParser`: chữ cuối được nối vào ô nhập; từ khoá "gửi"/"send" ở cuối thì gửi. Mất kênh hoặc phiên đóng thì ngừng nghe. Sửa câu xin quyền micro và nhận giọng nói cho khỏi chỉ nhắc terminal. | — |
| B15 | Câu quyền | iOS: `NSCameraUsageDescription` mới; câu micro và nhận giọng nói chung cho terminal và AI. Android: không cần quyền mới cho trình chọn ảnh hệ thống; camera dùng intent hệ thống. | — |
| B16 | Xem đủ | `ai.item {sid, rid, i, part}` → `ai.result {body: {"i", "r", "part", "parts", "text"}}`. Desktop dựng **bản đầy đủ** của mục `i` một lần (đầu ra lệnh, dòng cắt ở 2 000 ký tự như desktop; mọi diff, mỗi tệp ≤ 1 MiB; input JSON; form câu hỏi; chữ), giữ 60 s theo (điện thoại, sid, i, rev), trả từng lát ≤ 36 KiB. Tổng ≤ 2 MiB, lớn hơn thì `too_big` và vẫn "Xem trên máy tính". `rev` đổi giữa chừng (lệnh còn chạy) thì tải lại từ đầu. Điện thoại: "Xem đủ" → trang xem toàn màn hình (dòng ảo hoá, chữ đơn cách, dùng lại khung diff), "Đang tải 3/12". Câu hỏi `big` xem đủ rồi trả lời được trên điện thoại (hub đã kiểm bằng `form.accepts`). | — |
| B17 | Lịch sử phiên | `ai.history {sid, rid, cursor?}` → `{"sessions": [{"acp", "title", "at"}], "next"?, "current"?}` (≤ 50 mỗi trang, tiêu đề cắt ≤ 120 ký tự); agent của phiên chưa sẵn sàng → `not_ready` (điện thoại thử lại khi phiên chạy); agent không hỗ trợ `session/list` → nút không hiện (cờ trong header). Mở một mục: `ai.open` thêm `resume: <acp>` và khoá thư mục của phiên đó → desktop mở tab AI mới tiếp phiên cũ (`select: false`), phát lại như D15. | Hai tab cùng một phiên agent nếu người dùng mở hai lần (desktop cũng vậy). |
| B18 | Chọn thư mục | `ai.folder {sid, rid, folder}` (khoá từ listing, D9) cho tab `no_folder`: desktop làm như nút "Dùng thư mục này" của tab (quên runtime cũ, đặt `cwd`), rồi agent chạy (D15). Điện thoại: thay câu "Chọn thư mục trên máy tính" bằng danh sách thư mục và nút "Dùng thư mục này". | — |
| B19 | Thay đổi, hoàn tác | Tách `AiUndo` (thuần Dart, không widget) khỏi `aiRevert`: `plan(turn?)` (tệp đổi, tệp bị sửa sau lượt) và `apply(plan, keep)`. Desktop panel và hub dùng chung. Tin: `ai.changes {sid, rid, turn?}` → `{"scope", "turn"?, "files": [{"p", "k": "a|m|d", "plus"?, "minus"?}], "after": [đường dẫn], "turns": {"first", "last", "done"}, "off"?, "more"?}` (≤ 200 tệp); `ai.diff {sid, rid, turn?, path}` → vùng đổi của một tệp như diff của mục gương, hoặc `{"binary": true}` / `{"missing": true}`; `ai.revert {sid, rid, turn?, keep?}` → desktop **tính lại lúc làm**: có tệp bị sửa sau lượt mà chưa có `keep` thì `confirm` kèm danh sách, điện thoại hỏi như hộp thoại B14 của desktop rồi gửi lại với `keep: clean|all`; đang có lượt chạy → `busy_turn`; hoàn tác tắt → `undo_off`. Pane AI trên desktop ghi "Đã hoàn tác N tệp (từ điện thoại)." | Thao tác phá huỷ từ màn hình nhỏ: có hỏi lại, chống chạm nhầm 400 ms. |
| B20 | Hoàn tác trên điện thoại | Dòng hết lượt "Lượt 3 · 2 tệp đổi +44 −5" chạm được → bảng Thay đổi (lượt này / cả phiên) → trang diff. "Hoàn tác lượt này" màu đỏ, mờ khi đang có lượt chạy, hỏi lại kèm danh sách tệp; nút trong hộp hỏi chống chạm 400 ms (§13 V2-2). | — |
| B21 | Danh sách máy | Khi danh sách máy đang hiện và relay đã nối: mở kênh tới tối đa **6** máy đang online đã ghép đôi (máy dùng gần nhất trước), lấy listing AI, giữ nghe tới khi rời màn, app vào nền hoặc máy offline thì nhả. Thẻ máy có dòng "✦ 2 phiên AI · 1 cần bạn" (màu cảnh báo khi có phiên chờ); chạm dòng này → phiên đang chờ (một phiên) hoặc bộ chọn phiên. Máy lỗi bắt tay thì không hiện lỗi trên danh sách. Kéo xuống để làm mới. | Mỗi lần mở danh sách tốn một lần bắt tay mỗi máy (pin, dữ liệu). |
| B22 | Nối lại sau khởi động lại | Header có thêm `acp`. Khi phiên nhận `gone`/`desktop_closed`, hoặc lần attach lại sau `unavailable` thất bại: giữ listing tối đa 30 s; listing `available: true` có **đúng một** phiên cùng `acp`, cùng agent và thư mục → attach sid mới, đổi khoá nháp, hiện "Đã nối lại sau khi ShellX khởi động lại."; không có hoặc có từ hai phiên → giữ trang đóng với "Mở danh sách phiên". | — |
| B23 | Thông báo của sid cũ | Chạm thông báo mang sid của lần chạy trước: nếu listing đang giữ có phiên cùng `acp` thì mở phiên đó; không thì mở trang máy như cũ. | — |
| B24 | "Bạn · từ điện thoại" | `enum PromptSource { computer, phone }` trên `UserItem` và `QueuedPrompt`, truyền qua `send(…, source)`, `enqueue`, `beginTurn`. Hub gửi `phone`. Desktop ghi **"Bạn · từ điện thoại"** / "You · from your phone" trên tin và trên hàng đang xếp hàng. Mục gương có `src: "phone"`; điện thoại ghi "từ điện thoại" dưới tin của chính nó. Phát lại bằng `session/load` không giữ được nguồn (agent không lưu): tin cũ ghi "Bạn". | — |
| B25 | Riêng tư | Không có nội dung mới nào rời kênh mã hoá đầu cuối ngoài: id yêu cầu (số), hai id lựa chọn, một tag (B7). Trang Quyền riêng tư nói rõ thông báo AI mang gì (tên việc dạng rõ như N3; câu hỏi chỉ "<agent> hỏi bạn"; id). Không log nội dung (D12), kể cả ảnh, đường dẫn, diff. | — |
| B26 | Thứ tự làm | B3 → B1, B2, B4 (nền giao thức) → B24 → B22, B23 → B7 + B6 (nhánh relay) + B5 → B11 → B16 → B17, B18 → B12, B13, B14, B15 → B8, B9, B10 → B21 → B19, B20. | — |

---

## 4. Giao thức (chỉ thêm)

### 4.1 Tin mới và trường mới

| `t` | Chiều | Trường | Trả lời |
|---|---|---|---|
| `ai.config.get` | ĐT → DT | `sid`, `rid` | `ai.result {body}` (B11) |
| `ai.config` | ĐT → DT | `sid`, `rid`, `body` | `ai.result` |
| `ai.blob` | ĐT → DT | `rid`, `blob`, `part`, `parts`, `mime?`, `data` | `ai.result` mỗi phần (B12) |
| `ai.files` | ĐT → DT | `sid`, `rid`, `q` | `ai.result {body}` (B13) |
| `ai.item` | ĐT → DT | `sid`, `rid`, `i`, `part` | `ai.result {body}` (B16) |
| `ai.history` | ĐT → DT | `sid`, `rid`, `cursor?` | `ai.result {body}` (B17) |
| `ai.folder` | ĐT → DT | `sid`, `rid`, `folder` | `ai.result` (B18) |
| `ai.changes` | ĐT → DT | `sid`, `rid`, `turn?` | `ai.result {body}` (B19) |
| `ai.diff` | ĐT → DT | `sid`, `rid`, `turn?`, `path` | `ai.result {body}` |
| `ai.revert` | ĐT → DT | `sid`, `rid`, `turn?`, `keep?` | `ai.result` (`confirm` kèm `body`) |
| `ai.result` | DT → ĐT | thêm `body?` | — |
| `ai.prompt` | ĐT → DT | thêm `blobs?`, `files?` | — |
| `ai.open` | ĐT → DT | thêm `resume?` | — |

Mọi loại mới có mặt trong `aiUnavailableReply` (không có cửa sổ thì trả `unavailable` ngay, điện thoại không phải chờ 10 s), `_ridOf` (từ chối `busy` cần `rid`) và `_towardsPhone`.

### 4.2 Thân và header

- Listing: thêm `"f": [...]` (B1).
- Header: thêm `model {id, name}`, `acp`, `hist` (agent có `session/list`), `undo` (`on`/`off`).
- Mục gương tin người dùng: thêm `img` (số ảnh), `src` (`phone`).
- Mux `ai.push`: thêm `perm`, `allow`, `reject`, `tag` (daemon cũ bỏ qua → thông báo thường).

### 4.3 Thông báo (relay, nhánh `v2-2b-relay`)

Thân `POST /v1/notifications` thêm `category?` (`ai_perm`), `tag?`. `data` thêm `perm`, `allow`, `reject` (vẫn ≤ 10 khoá cùng `kind`, `ai_session`, `agent_id`; giá trị ≤ 256 ký tự, quá thì bỏ nút). FCM:

```json
{"message": {"token": "…",
  "notification": {"title": "MacBook · Claude", "body": "Cần bạn trả lời: Sửa src/main.ts"},
  "data": {"kind": "ai", "ai_session": "k3f9za.-12", "agent_id": "…", "perm": "41", "allow": "allow", "reject": "reject"},
  "android": {"priority": "high", "notification": {"tag": "ai-k3f9za--12-41"}},
  "apns": {"payload": {"aps": {"sound": "default", "category": "ai_perm"}}}}}
```

---

## 5. Giao diện điện thoại (chuỗi EN / VI)

| Khoá | EN | VI |
|---|---|---|
| `pushActionAllow` / `pushActionReject` | Allow / Deny | Cho phép / Từ chối |
| `aiPushAllowed` / `aiPushDenied` | Allowed: {title} / Denied: {title} | Đã cho phép: {title} / Đã từ chối: {title} |
| `aiPushMaybeNotSent` | It may not have been sent. Check the session. | Có thể chưa gửi được. Xem trong phiên. |
| `aiConfigTitle` | Mode and model | Chế độ và model |
| `aiConfigMode` / `Model` / `Effort` | Mode / Model / Thinking | Chế độ / Model / Mức suy nghĩ |
| `aiAttachPhoto` / `aiTakePhoto` | Photo library / Camera | Thư viện ảnh / Chụp ảnh |
| `aiImagesCount` | {n, plural, one{1 image} other{{n} images}} | {n} ảnh |
| `aiImageFailed` | The image wasn't sent. Retry | Ảnh chưa gửi được. Thử lại |
| `aiNoImages` | {agent} doesn't take images. | {agent} không nhận ảnh. |
| `aiChanges` / `aiThisTurn` / `aiWholeSession` | Changes / This turn / Whole session | Thay đổi / Lượt này / Cả phiên |
| `aiRevertTurn` | Revert this turn | Hoàn tác lượt này |
| `aiRevertConfirm` | Revert {n} files to before turn {turn}? | Đưa {n} tệp về như trước lượt {turn}? |
| `aiRevertTouched` | {n} files changed after this turn. | {n} tệp đã đổi sau lượt này. |
| `aiRevertOnlyClean` / `aiRevertAll` | Only unchanged files / Revert all | Chỉ tệp chưa đổi sau đó / Hoàn tác hết |
| `aiRevertBusy` | Wait for the turn to finish. | Chờ lượt này xong. |
| `aiRevertedFromPhone` (desktop) | Reverted {n} files (from your phone). | Đã hoàn tác {n} tệp (từ điện thoại). |
| `aiViewAll` / `aiLoadingParts` | View all / Loading {part}/{parts} | Xem đủ / Đang tải {part}/{parts} |
| `aiHistory` | Session history | Lịch sử phiên |
| `aiUseFolder` | Use this folder | Dùng thư mục này |
| `machineAiLine` | ✦ {n} AI sessions · {w} need you | ✦ {n} phiên AI · {w} cần bạn |
| `aiReattached` | Reconnected after ShellX restarted. | Đã nối lại sau khi ShellX khởi động lại. |
| `aiOpenList` | Open the session list | Mở danh sách phiên |
| `aiYouFromPhone` (desktop) | You · from your phone | Bạn · từ điện thoại |
| `aiFromPhone` | from phone | từ điện thoại |

---

## 6. Riêng tư, an ninh và log

- Không có đường nào trả lời mà không có một lần chạm của người dùng (D13 giữ nguyên). Nút trên thông báo chỉ mang hai lựa chọn "một lần"; câu trả lời chỉ gửi sau khoá Face ID của app; không gửi lại sau khi mất kênh.
- Chế độ bỏ qua xin quyền không bao giờ được liệt kê hay đặt từ điện thoại (B11).
- Đường dẫn từ điện thoại (B13, B19) chỉ là đường dẫn desktop đã đưa và phải nằm trong thư mục phiên; desktop kiểm lại lúc làm.
- Ảnh chỉ nằm trong bộ nhớ desktop tới khi gửi cho agent (B12).
- Không log nội dung; `toString` của mọi tin mới trả `Tên(…)`, có test.

---

## 7. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Chạm nút khi yêu cầu đã được trả lời trên máy tính | `stale` → "đã được trả lời ở nơi khác", không trả lời gì |
| Chạm nút sau khi máy tính khởi động lại | sid cũ → B23; không khớp thì mở trang máy, không trả lời |
| Chạm nút khi app đang khoá Face ID | Chờ mở khoá xong mới gửi; huỷ khoá thì không gửi |
| Mất kênh khi đang tải ảnh | Tải lại ảnh khi có kênh; tin chưa gửi vẫn nằm trong ô nhập |
| Desktop V2-2a hoặc dịch vụ nền V2-2a | B1: không hiện tính năng mới |
| Hoàn tác khi máy tính vừa sửa tệp | Tính lại lúc làm, hỏi `confirm` |
| `ai.item` khi lệnh còn chạy | `rev` đổi → tải lại từ đầu |
| Danh sách máy với máy chưa tin cậy | Không hiện dòng AI, không báo lỗi |

---

## 8. Kiểm thử

- **B3:** hai runtime nối tiếp trên cùng một pane: id yêu cầu không trùng; câu trả lời cho id cũ → `stale`.
- **B1/B2:** điện thoại V2-2b với router `ai: 1` không gửi tin mới; daemon V2-2b chuyển nguyên văn một loại `ai.*` lạ và khoá lạ; bộ giải mã đóng băng V2-2a đọc lô mới không lỗi.
- **Mỗi tin mới:** round-trip; sai trường → `null`; lớn nhất vừa một lô; `aiUnavailableReply`; ngân sách `busy`.
- **B7:** chọn đúng `allow_once` không bỏ qua quyền và `reject_once`; thiếu thì không nút; daemon cũ bỏ khoá mới.
- **B6 (relay):** test TypeScript cho `category`, `tag` hợp lệ/không; hình dạng FCM; e2e push trong `packages/shellx_e2e`.
- **B10:** dữ liệu push sai bị bỏ; chỉ gửi sau khi mở khoá app; mọi mã kết quả ra đúng câu; không gửi lại.
- **B11:** lọc chế độ bỏ qua xin quyền (cả id lạ có chữ "bypass", "yolo"…); kiểm lại lúc đặt; `rememberConfig` không nhớ bỏ qua quyền.
- **B12:** ghép phần, thiếu phần, sai loại ảnh, vượt cỡ, hết hạn 2 phút, điện thoại rời đi; desktop nhận `ImageBlock` đúng.
- **B13:** đường dẫn ngoài thư mục phiên bị từ chối.
- **B16:** chia lát, `rev` đổi, quá 2 MiB.
- **B17/B18:** trang lịch sử, `not_ready`, `resume` mở tab không chọn; khoá thư mục lạ bị từ chối.
- **B19:** `AiUndo` dùng chung cho desktop (test desktop cũ vẫn xanh) và hub; `confirm`; `busy_turn`; ghi chú trên pane.
- **B21:** mở/nhả kênh theo màn, tối đa 6, máy lỗi im lặng.
- **B22/B23:** một phiên khớp → nối lại; hai phiên → không.
- **B24:** nguồn đi suốt từ hub tới widget desktop; phát lại thì "Bạn".
- **App mobile (widget):** từng màn mới, chống chạm 400 ms ở hoàn tác, các trạng thái.

---

## 9. Review Focus

1. **Câu trả lời trúng nhầm yêu cầu:** runtime đổi trên cùng pane (B3), thông báo cũ chạm muộn, sid của lần chạy trước (B23). Test: mọi đường đều ra `stale` hoặc mở trang, không bao giờ trả lời.
2. **Dịch vụ nền cũ nuốt tin mới** khiến điện thoại chờ mãi: test với daemon V2-2a giả.
3. **Một tin quá cỡ làm rơi cả kênh** (ảnh, `ai.item`, `ai.changes` với rất nhiều tệp, tiêu đề lịch sử dài). Test cỡ lớn nhất mỗi loại.
4. **Hoàn tác từ điện thoại khi máy tính đang làm việc:** lượt đang chạy, tệp vừa đổi. Test `busy_turn`, `confirm`.
5. **Chế độ bỏ qua xin quyền lọt qua** bằng một id lạ hay qua `ai.config` gửi thẳng. Test cả danh sách và lúc đặt.

---

## 10. ⚠ Kiểm tay (cần người: iPhone, Android, máy Mac; bản Profile/Release có APNs)

1. **Trước hết (V2-2a):** chạm thông báo AI khi app đã tắt, đang ở nền, đang ở trước: mở đúng phiên (B5). Banner trong app khi app ở trước.
2. Nút "Từ chối"/"Cho phép" trên iPhone (vuốt hoặc nhấn giữ thông báo), màn khoá, Apple Watch (chạm đúp không cho phép).
3. Android 13+ và một máy Samsung/Xiaomi: thông báo có nút thay thông báo thường; chạm nút mở app, trả lời.
4. Relay mới đã triển khai (sau khi người dùng đồng ý B6).
5. Chọn 5 ảnh HEIC từ iPhone: gửi được, agent thấy ảnh.
6. Micro trong ô nhập AI (tiếng Việt), từ khoá "gửi".
7. Hoàn tác một lượt từ điện thoại; pane trên máy tính hiện ghi chú.
8. Khởi động lại ShellX trên máy tính khi điện thoại đang mở phiên: tự nối lại.
9. Danh sách máy với 2–3 máy online: dòng AI, pin không tụt bất thường sau 10 phút mở màn.

---

## 11. Phạm vi

**Trong V2-2b:** mọi thứ ở §3–§8. Relay ở nhánh riêng tới khi được đồng ý.

**Ngoài V2-2b:** trả lời không cần mở app (chạy nền); tệp tuỳ ý từ điện thoại (PDF…); `@` cho thư mục; hiện tên điện thoại cụ thể ("từ iPhone của …").

---

## 12. Rủi ro

| Rủi ro | Mức | Xử lý |
|---|---|---|
| Thay đổi relay = triển khai thật | Trung bình | Nhánh riêng, chờ đồng ý; thay đổi chỉ thêm, relay có test và tự quay lui khi kiểm sức khoẻ hỏng |
| `firebase_messaging` 16.7.0 lỗi thông báo trước trong app UIScene (#18699) | Thấp–TB | Pha nút mở app không đăng thông báo cục bộ trên iOS; kiểm §10.1 |
| Android thay thông báo không kịp (máy chặn chạy nền) | Trung bình | Vẫn còn thông báo thường |
| Tách `AiUndo` làm hỏng hoàn tác trên desktop | Trung bình | Test desktop hiện có phải xanh; test mới cho lớp tách |
| Mở kênh tới nhiều máy tốn pin | Thấp–TB | Tối đa 6, chỉ khi màn đang hiện |
| HEIC không đổi sang JPEG ở vài đường iOS | Thấp | Desktop kiểm byte đầu, báo rõ; kiểm §10.5 |
