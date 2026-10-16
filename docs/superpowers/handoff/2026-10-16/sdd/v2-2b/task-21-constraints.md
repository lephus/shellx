# Task 21 constraints (verbatim excerpts) — Android buttons: flutter_local_notifications, background handler, replace by tag

## Spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md` (binding; Vietnamese) — criterion 1 (line 31); B5, B6, B8, B9, B10 (lines 79–84):

1. **Nút trên thông báo.** Thông báo xin quyền có hai nút **"Từ chối"** và **"Cho phép"**. Chạm "Cho phép": mở khoá máy, app mở, qua khoá Face ID của app thì câu trả lời được gửi **đúng một lần**; trang phiên hiện "Đã cho phép: Sửa src/main.ts" trong ≤ 3 s sau khi app mở. Yêu cầu đã được trả lời ở nơi khác hay đã hết: "Yêu cầu này đã được trả lời ở nơi khác." và **không trả lời gì khác**.

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B5 | Delegate thông báo iOS (sửa lỗi V2-2a) | `AppDelegate.application(_:didFinishLaunchingWithOptions:)` gọi `FLTFirebaseMessagingPlugin.configureNotificationCenterDelegate()` (theo README 16.7.0) và đăng ký category `ai_perm` (B8) ngay tại đó. Không thêm `flutter_local_notifications` trên iOS. | — |
| B6 | Relay | Thêm hai khoá tuỳ chọn vào `POST /v1/notifications`: `category` (chỉ nhận `ai_perm`) và `tag` (`^[A-Za-z0-9_.:-]{1,64}$`); sai thì 400. FCM: thêm `apns.payload.aps.category` và `android.notification.tag`; **giữ nguyên khối `notification`** (không có tin chỉ-data, không cần bảng khả năng theo máy). Relay cũ bỏ qua hai khoá. Nhánh `v2-2b-relay`, gộp khi người dùng đồng ý triển khai. | Chưa triển khai relay thì thông báo vẫn như cũ, không có nút. |
| B7 | Desktop xin đẩy kèm nút | `AiPush` có thêm `permission` (id) và hai lựa chọn: **allow** = lựa chọn `allow_once` đầu tiên **không** bật chế độ bỏ qua xin quyền; **reject** = lựa chọn `reject_once` đầu tiên. Không bao giờ `allow_always`/`reject_always` (đổi hành vi về sau, trái tinh thần D13). Thiếu một trong hai thì thông báo thường như cũ. Câu hỏi không có nút. `aiNotice` thêm `data` `perm`, `allow`, `reject` và xin `category: ai_perm`, `tag: ai-<epoch>-<pane>-<perm>`. Hàm nhận diện chế độ bỏ qua xin quyền chuyển sang `package:shellx_ai` để hub dùng. | — |
| B8 | Nút trên iOS | Category `ai_perm` đăng ký native trong `AppDelegate`: **"Từ chối"** trước (`.destructive` + `.foreground`), **"Cho phép"** sau (`.foreground` + `.authenticationRequired`). "Từ chối" đứng trước để cú chạm đúp trên Apple Watch không bao giờ cho phép. Tên nút theo ngôn ngữ máy (`Localizable.strings` en/vi). Chạm nút → iOS mở khoá và mở app → `firebase_messaging` đưa `RemoteMessage.actionIdentifier` qua `getInitialMessage()` / `onMessageOpenedApp`. | Một lần mở khoá và chuyển sang app cho mỗi câu trả lời. |
| B9 | Nút trên Android | Thêm `flutter_local_notifications` 22.3.2 (bật desugaring) và hàm `onBackgroundMessage` (chưa có). Khi tin có `perm`/`allow`/`reject`, hàm này hiện lại **cùng `tag`** một thông báo có hai nút (`showsUserInterface: true`, mở app, cần mở khoá máy) thay cho thông báo hệ thống vẽ. Không mạng trong hàm nền. Chạm nút hay chạm thân của thông báo thay thế đều đi qua `NotificationOpener`. Thông báo thay thế không kịp hiện (máy chặn chạy nền) thì vẫn còn thông báo thường. | Một số máy Android (Xiaomi, Huawei…) có thể không hiện nút. |
| B10 | Gửi câu trả lời | Chỉ khi app **đã ở trước và đã qua khoá Face ID của app**: kiểm dữ liệu (máy đã ghim, `ai_session`, `perm` là số, lựa chọn là đúng một trong hai id mang theo), gửi **một** `ai.answer` bằng kênh thường, chờ `ai.result`, không bao giờ gửi lại sau khi mất kênh (D13). Rồi mở trang phiên kèm kết quả: `ok` → "Đã cho phép: <việc>" / "Đã từ chối: <việc>"; `stale` → "Yêu cầu này đã được trả lời ở nơi khác."; `not_found` → "Phiên AI này đã đóng trên máy tính."; `on_computer` → "Trả lời yêu cầu này trên máy tính."; mất kênh/hết giờ → "Có thể chưa gửi được. Xem trong phiên." **Trả lời không cần mở app** (chạy nền) là việc sau: không áp được khoá Face ID của app, Android phải chạy isolate riêng với kết nối relay thứ hai. | — |

## Spec §4.3 (lines 133–143), §6 (lines 180, 184), §7 (lines 190–194), §8 B10 (line 210), §12 (line 262):

### 4.3 Thông báo (relay, nhánh `v2-2b-relay`)

Thân `POST /v1/notifications` thêm `category?` (`ai_perm`), `tag?`. `data` thêm `perm`, `allow`, `reject` (vẫn ≤ 10 khoá cùng `kind`, `ai_session`, `agent_id`; giá trị ≤ 256 ký tự, quá thì bỏ nút). FCM:

```json
{"message": {"token": "…",
  "notification": {"title": "MacBook · Claude", "body": "Cần bạn trả lời: Sửa src/main.ts"},
  "data": {"kind": "ai", "ai_session": "k3f9za.-12", "agent_id": "…", "perm": "41", "allow": "allow", "reject": "reject"},
  "android": {"priority": "high", "notification": {"tag": "ai-k3f9za--12-41"}},
  "apns": {"payload": {"aps": {"sound": "default", "category": "ai_perm"}}}}}
```

- Không có đường nào trả lời mà không có một lần chạm của người dùng (D13 giữ nguyên). Nút trên thông báo chỉ mang hai lựa chọn "một lần"; câu trả lời chỉ gửi sau khoá Face ID của app; không gửi lại sau khi mất kênh.
- Không log nội dung; `toString` của mọi tin mới trả `Tên(…)`, có test.

| Tình huống | Hành vi |
|---|---|
| Chạm nút khi yêu cầu đã được trả lời trên máy tính | `stale` → "đã được trả lời ở nơi khác", không trả lời gì |
| Chạm nút sau khi máy tính khởi động lại | sid cũ → B23; không khớp thì mở trang máy, không trả lời |
| Chạm nút khi app đang khoá Face ID | Chờ mở khoá xong mới gửi; huỷ khoá thì không gửi |

- **B10:** dữ liệu push sai bị bỏ; chỉ gửi sau khi mở khoá app; mọi mã kết quả ra đúng câu; không gửi lại.

| Rủi ro | Mức | Xử lý |
|---|---|---|
| Android thay thông báo không kịp (máy chặn chạy nền) | Trung bình | Vẫn còn thông báo thường |

## Plan rulings R7, R21 (plan lines 57, 71):

- **R7 — a push answer waits for the app lock, and only so long** (B10, §7): sent after the lock is passed; dropped (nothing sent) when an unlock attempt ends still locked, when the app leaves the foreground first, or after 2 minutes. *Cost if wrong:* the user taps again in the session.
- **R21 — Android re-draws only a push with an `ai-` tag** (B9): only the relay of Task 7 sets `android.notification.tag`; a push through an older relay stays as FCM drew it — no buttons, and never two notifications for one request. *Cost if wrong:* Android buttons wait for the relay deploy, like iOS's.

## Plan Global Constraints: Toolchain, Lock files, Never auto-allow, No content in logs, Mobile (plan lines 77, 78, 81, 82, 87):

- **Toolchain:** Flutter only via `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter …`; Dart via `~/fvm/versions/3.41.4/bin/dart`. Flutter 3.41.4 / Dart 3.11.1. New packages pinned exactly: `image_picker: 1.2.4`, `flutter_local_notifications: 22.3.2` (Android core-library desugaring `com.android.tools:desugar_jdk_libs:2.1.4`). `firebase_messaging` stays `^16.7.0`.
- **Lock files:** `pubspec.lock` files are git-ignored: never `git add` them. After a macOS desktop build, revert the `COCOAPODS:` line change in `apps/desktop/macos/Podfile.lock`. After an iOS mobile build that adds pods, commit the new pod lines in `apps/mobile/ios/Podfile.lock` with `COCOAPODS: 1.16.2` kept.
- **Never auto-allow (D13, spec §6):** no path in which a phone answers without a user tap; a notification button is that tap, and its answer goes only after the app's own lock (R7); push buttons offer only the first `allow_once` that turns on no no-approval mode and the first `reject_once` — never `allow_always`/`reject_always`; no answer is ever resent after a lost channel; a no-approval mode is never listed for, nor set from, a phone (R16); a remembered no-approval mode is never re-applied.
- **No content in logs (D12, B25):** no prompt, agent text, path, file name, diff, image, URL, header or body in any log; new log lines print only `error.runtimeType`. `toString()` of every new `ai.*` message is `'<Type>(…)'`; of every new body/view/record `'…'` (`with Redacted`) or `'<Name>(…)'`; each pinned by a test. Push data carries only an integer id, two option ids and a tag beyond V2-2a's (B25).
- **Mobile:** strings in `apps/mobile/lib/l10n/intl_en.arb` and `intl_vi.arb` (same keys; `test/l10n_test.dart` checks), generated with `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart run intl_utils:generate`; routes and DI with `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart run build_runner build --delete-conflicting-outputs`; generated files committed. Colours and type from `context.colors` / `context.typo` only; no looping animation except a spinner while loading and the existing mic pulse. Page width 120 (`apps/mobile/analysis_options.yaml`).

## Controller rulings and cross-task contracts (SDD ledger)

- Ruling (F11): where a brief's format command names whole directories, any file outside the task's Files block that it changes is restored to HEAD and reported, never committed.
- Builds (Step 7, the task's own text): `flutter build apk --debug` and `flutter build ios --simulator --debug --no-codesign` are builds, not launches. After the iOS build, `apps/mobile/ios/Podfile.lock` gains exactly the `flutter_local_notifications` pod lines (PODS, DEPENDENCIES, EXTERNAL SOURCES, SPEC CHECKSUMS) and keeps `COCOAPODS: 1.16.2` (precedent: Task 18's `image_picker_ios` lines).
- Task 20 produced (consumed here): `PushMessage({title, body, data, action})`, `pushDataOf`, `PushAnswer.of`, `S.pushActionAllow`/`pushActionReject`, `PushController` routing a button tap to `PushAnswerer` (which answers only after the app's lock, once).
- Mobile `flutter analyze` has one pre-existing info (`unnecessary_import`, `test/features/terminal/ime_in_place_edit_test.dart:2:8`) — not this task's finding.
