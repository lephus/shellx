# Thông báo đẩy (push notification) — Đặc tả thiết kế

- **Ngày:** 2026-10-05
- **Trạng thái:** Người dùng đã chọn từng quyết định N1–N7 trong brainstorming (2026-10-05) rồi giao toàn quyền ("chế độ vắng mặt"); các điểm còn mở do controller quyết, ghi ở N8–N12.
- **Phạm vi:** relay (bảng token, 2 endpoint, gửi FCM), agent (nhận biết sự kiện, gửi lên relay), khối tích hợp shell (`term/shell/`) và shell của phiên ShellX (hook), app mobile (Firebase Messaging), app desktop (cài đặt ngưỡng), chính sách quyền riêng tư.
- **Sửa spec v1 (`2026-09-25-shellx-v1-design.md`):** §3.2 "Push notification" ngoài phạm vi → nay trong phạm vi. Tiêu chí thành công 4 ("relay … không đọc được … terminal") có **ngoại lệ**: nội dung thông báo (N3).

---

## 1. Mục tiêu

Khi một lệnh chạy lâu trên máy tính kết thúc, hoặc một chương trình chủ động gửi thông báo, mọi điện thoại đã ghép nối với máy đó nhận một thông báo hệ thống — **kể cả khi app mobile đã đóng hoặc chạy nền lâu**.

### Tiêu chí thành công

1. Lệnh chạy ≥ ngưỡng (mặc định 30 giây) trong một phiên ShellX hoặc một terminal máy tính được chia sẻ kết thúc → trong vòng 5 giây (khi mạng bình thường) mọi điện thoại đã ghép nối nhận thông báo "✓ <lệnh> · 3 phút 12 giây" hoặc "✗ <lệnh> · mã 1 · 45 giây".
2. `printf '\e]9;Build xong\a'`, `printf '\e]777;notify;Tiêu đề;Nội dung\a'` hoặc `shellx notify "Build xong"` → thông báo ngay (không phụ thuộc ngưỡng).
3. App mobile đóng hẳn: thông báo vẫn hiện (iOS qua APNs, Android qua FCM). Chạm vào thông báo mở app tới đúng máy (và đúng phiên nếu phiên còn).
4. Relay thiếu cấu hình Firebase vẫn chạy bình thường; chỉ không gửi push (trả `503 push_unavailable`, agent bỏ qua).
5. Không làm chậm terminal: nhận biết sự kiện chạy trên luồng output agent đã đọc sẵn; gửi push không chặn gì.
6. App mobile cũ và agent cũ không bị ảnh hưởng (endpoint mới, trường mới đều tùy chọn).

---

## 2. Nhật ký quyết định

| # | Chủ đề | Quyết định |
|---|---|---|
| N1 | Khi nào phải tới được | Kể cả khi app mobile đóng hoặc chạy nền lâu → push thật qua FCM (Android) và APNs qua FCM (iOS) |
| N2 | Sự kiện | Cả hai: (a) lệnh chạy lâu kết thúc, kèm mã thoát và thời gian; (b) thông báo chủ động: OSC 9, OSC 777 `notify`, lệnh `shellx notify` |
| N3 | Nội dung qua relay/FCM | **Dạng rõ** (người dùng chọn sau khi được cảnh báo về cam kết E2E). Hệ quả: sửa chính sách quyền riêng tư (§9) trước khi phát hành |
| N4 | Nguồn | Cả phiên ShellX (điện thoại mở) lẫn terminal máy tính chia sẻ qua `shellx-term` (dùng được khi P4 xong) |
| N5 | Người nhận | **Luôn** mọi điện thoại đã ghép nối với agent đó, kể cả điện thoại đang xem phiên |
| N6 | Ngưỡng | Mặc định 30 giây; chỉnh trong Cài đặt app desktop: Tắt, 10 giây, 30 giây, 1 phút, 5 phút. Thông báo chủ động không phụ thuộc ngưỡng |
| N7 | Đường gửi | Relay làm cổng push: mobile đăng ký FCM token với relay; agent gọi relay; relay tra ghép nối và gọi FCM HTTP v1 bằng service account trên VPS. Loại bỏ: agent gọi FCM trực tiếp (phải nhúng khóa Firebase vào app desktop), bên thứ ba |
| N8 | Công tắc "hiện nội dung" | Không làm trong bản này (YAGNI, thời gian); chính sách quyền riêng tư nói rõ N3 |
| N9 | Nhận biết lệnh | Agent đọc chuỗi OSC trong output: `OSC 133;C` (lệnh bắt đầu), `OSC 133;D;<mã>` (kết thúc), `OSC 633;E;<dòng lệnh>` (dòng lệnh, quy ước của VS Code). Hook trong shell phát các chuỗi này (§5). Thời gian do agent đo |
| N10 | Chống spam | Agent: tối đa 6 thông báo mỗi phút mỗi máy (vượt thì bỏ, ghi log đếm). Relay: tối đa 120 lệnh `POST /v1/notifications` mỗi giờ mỗi agent (`429`) |
| N11 | Snapshot | Không phát sự kiện từ `snapshot` của `shellx-term` (là output cũ phát lại); chỉ từ output trực tiếp |
| N12 | Firebase | Dự án `shellxpro` (tài khoản riêng của người dùng). App Android và iOS id `com.shellx.prod` |

---

## 3. Kiến trúc

```
 shell (hook OSC 133/633, OSC 9/777)
   │ output
   ▼
 Agent ── NotificationDetector (theo phiên) ── NotificationSender ──HTTPS──▶ Relay
                                                                         │ tra pairings + push_tokens
                                                                         ▼
                                                              FCM HTTP v1 ──▶ APNs / Android
                                                                         ▼
                                                                    Điện thoại
 App mobile ── firebase_messaging: token ──HTTPS PUT──▶ Relay (push_tokens)
```

| Thành phần | Nơi ở | Việc |
|---|---|---|
| `OscEventParser` | `packages/shellx_agent/lib/src/notify/` | Đọc chuỗi OSC 133/633/9/777 trong output, chịu cắt giữa khung, giới hạn bộ nhớ (như `OscTitleParser`) |
| `CommandTracker` | `packages/shellx_agent/lib/src/notify/` | Theo từng phiên: lệnh bắt đầu (thời điểm, dòng lệnh) → kết thúc (mã) → sự kiện nếu ≥ ngưỡng |
| `NotificationSender` | `packages/shellx_agent/lib/src/notify/` | Gom sự kiện, chống spam (N10), gọi `ShellxApi.sendNotification`; lỗi thì bỏ, không thử lại vô hạn |
| Nối vào phiên | `SessionManager`, `DesktopSessionManager` | Cho output trực tiếp qua detector (không qua snapshot) |
| Hook phiên ShellX | `packages/shellx_agent/lib/src/pty/` | Shell do agent mở chạy kèm hook (zsh/bash/pwsh) |
| Hook terminal chia sẻ | `term/shell/block.*` | Nhánh shell bên trong của khối tích hợp cài hook |
| API | `packages/shellx_core` | `ShellxApi.registerPushToken`, `deletePushToken`, `sendNotification` |
| Relay | `relay/` | Migration `0003_push_tokens.sql`, `PUT/DELETE /v1/devices/me/push-token`, `POST /v1/notifications`, `FcmClient` |
| Mobile | `apps/mobile` | `firebase_core`, `firebase_messaging`; xin quyền; đăng ký token; hiện banner khi app ở foreground; chạm → mở máy/phiên |
| Desktop | `apps/desktop` | Cài đặt "Thông báo lệnh chạy lâu" (Tắt/10 s/30 s/1 phút/5 phút), lưu settings, truyền cho agent |

---

## 4. Agent

### 4.1 Chuỗi được nhận biết

| Chuỗi | Ý nghĩa |
|---|---|
| `ESC ] 133 ; C BEL/ST` | Lệnh bắt đầu chạy |
| `ESC ] 133 ; D [; <mã>] BEL/ST` | Lệnh kết thúc; thiếu mã = 0 |
| `ESC ] 633 ; E ; <dòng lệnh> [; <nonce>] BEL/ST` | Dòng lệnh sắp chạy (thoát ký tự theo quy ước VS Code: `\\` → `\`, `\x3b` → `;`) |
| `ESC ] 9 ; <nội dung> BEL/ST` | Thông báo chủ động. **Bỏ qua** khi nội dung bắt đầu bằng `<số>;` (OSC 9;4 là thanh tiến trình của ConEmu/Windows Terminal) |
| `ESC ] 777 ; notify ; <tiêu đề> ; <nội dung> BEL/ST` | Thông báo chủ động (quy ước của urxvt/WezTerm) |

Payload tối đa 4 KiB mỗi chuỗi (dài hơn thì bỏ qua); tiêu đề/nội dung cắt còn 200 ký tự. Các chuỗi này đi qua nguyên vẹn tới điện thoại và cửa sổ (terminal bỏ qua OSC lạ).

### 4.2 Sự kiện và nội dung

- **Lệnh kết thúc:** có `C` rồi `D`, thời gian `D − C` ≥ ngưỡng (N6; ngưỡng "Tắt" thì không phát). `D` không có `C` trước đó → bỏ. Dòng lệnh lấy từ `E` gần nhất trước `C`; không có thì dùng "Lệnh".
  - Tiêu đề: `<tên máy>` (tên thiết bị agent) — và tên phiên: phiên ShellX "Phiên <index>"; terminal máy tính "<ứng dụng> — <tiêu đề cửa sổ>" (rỗng thì tên ứng dụng).
  - Nội dung: `✓ <dòng lệnh> · <thời gian>` nếu mã 0, ngược lại `✗ <dòng lệnh> · mã <mã> · <thời gian>`. Thời gian: "45 giây", "3 phút 12 giây", "1 giờ 4 phút". Ngôn ngữ: tiếng Việt nếu ngôn ngữ hệ thống của máy tính là `vi`, ngược lại tiếng Anh ("exit", "s", "min", "h").
- **Thông báo chủ động:** OSC 9 → tiêu đề như trên, nội dung = payload. OSC 777 → tiêu đề = `<tiêu đề chương trình>` (rỗng thì như trên), nội dung = payload.
- **Dữ liệu kèm:** `agent_id`, `session_id` (để chạm vào mở đúng chỗ), `kind` = `command` | `message`.

### 4.3 Gửi

- `NotificationSender` gọi `POST /v1/notifications` bằng token của agent (như các lệnh REST hiện có). Không có mạng hay relay trả lỗi → bỏ thông báo đó (không xếp hàng: thông báo trễ vài phút thường vô nghĩa). `401` → không làm gì thêm (luồng `AgentRevoked` hiện có lo).
- Chống spam N10: cửa sổ trượt 60 giây, tối đa 6; vượt thì bỏ.
- Relay trả `202 {sent: 0}` (không điện thoại nào nhận được) → agent ngừng gửi 15 phút (theo từng runtime); `sent > 0` hoặc runtime mới thì hết ngừng.
- Ngưỡng đổi trong Cài đặt có hiệu lực ngay cho lệnh kết thúc sau đó.

### 4.4 Hook cho phiên ShellX (agent mở shell)

Agent mở shell kèm một hook nhỏ, **không sửa file cấu hình của người dùng**:
- **zsh:** đặt `ZDOTDIR` sang một thư mục tạm của agent chứa `.zshenv`/`.zprofile`/`.zshrc`/`.zlogin` gọi lại đúng file của người dùng (theo `ZDOTDIR` gốc hoặc `HOME`), rồi `.zshrc` thêm `preexec`/`precmd` phát `633;E`, `133;C`, `133;D;$?`. Khôi phục `ZDOTDIR` gốc trong shell.
- **bash:** `--rcfile <file của agent>` nạp `~/.bashrc` rồi cài `PROMPT_COMMAND` và bẫy `DEBUG` (chỉ phát `C` một lần mỗi dòng lệnh).
- **PowerShell:** `-NoExit -Command ". '<script của agent>'"`: script dot-source profile của người dùng (nếu `-NoProfile` không có), bọc hàm `prompt` và dùng `PSReadLine` `AddToHistoryHandler`/`CommandValidationHandler` để phát `E`/`C`, `prompt` phát `D` với `$LASTEXITCODE`/`$?`.
- Hàm `shellx` được định nghĩa trong hook **chỉ khi chưa có lệnh nào tên `shellx`**: `shellx notify <chữ…>` phát `OSC 777;notify;;<chữ>`. Lệnh con khác → in hướng dẫn ngắn.
- Không cài được hook (shell lạ) → phiên chạy bình thường, chỉ không có thông báo lệnh.

### 4.5 Hook cho terminal máy tính chia sẻ

Nhánh "đang ở đúng cửa sổ đã bọc" của khối tích hợp (`term/shell/block.zsh`, `block.bash`, `block.ps1`) cài cùng hook như §4.4 trong shell bên trong. Khối vẫn chỉ gồm ASCII và vẫn không để lại biến phụ khi không bọc. Bản khối mới được P4 cài khi người dùng bật/cập nhật (bộ cài thay nội dung giữa hai dấu).

---

## 5. Relay

- **Migration `0003_push_tokens.sql`:** bảng `push_tokens(device_id TEXT PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE, token TEXT NOT NULL, platform TEXT NOT NULL CHECK (platform IN ('android','ios')), updated_at INTEGER NOT NULL)`; chỉ mục duy nhất trên `token` (một token chỉ thuộc một thiết bị: đăng ký lại ở thiết bị khác thì chuyển).
- **`PUT /v1/devices/me/push-token`** `{token, platform}` — chỉ thiết bị `mobile`; token 1..4096 ký tự. `204`.
- **`DELETE /v1/devices/me/push-token`** — `204`. Đăng xuất (`/v1/auth/logout`) và xóa thiết bị cũng xóa token (cascade/explicit).
- **`POST /v1/notifications`** `{title, body, data?}` — chỉ thiết bị `agent`. Tiêu đề ≤ 200, nội dung ≤ 1000 ký tự, `data` là map chuỗi→chuỗi ≤ 10 khóa. Người nhận = điện thoại có bản ghi ghép nối với agent này (bảng ghép nối hiện có) **và** có token. Trả `202 {sent: n}`; `503 push_unavailable` khi thiếu cấu hình Firebase; `429` theo N10.
- **`FcmClient`:** FCM HTTP v1 (`https://fcm.googleapis.com/v1/projects/<project>/messages:send`), lấy OAuth token bằng JWT RS256 ký bằng service account (`node:crypto`, không thêm thư viện), cache token tới khi gần hết hạn. Tin nhắn có `notification {title, body}`, `data`, `android.priority=high`, `apns.payload.aps.sound=default`. Lỗi `UNREGISTERED`/`INVALID_ARGUMENT` cho một token → xóa token đó. Lỗi khác → log, không thử lại.
- **Cấu hình:** `FCM_SERVICE_ACCOUNT` = đường dẫn file JSON service account (mount chỉ đọc vào container); thiếu hoặc hỏng → push tắt, relay vẫn chạy (log một dòng khi khởi động). `deploy/` thêm mount và hướng dẫn.
- Log không ghi nội dung thông báo hay token.

---

## 6. App mobile

- Thêm `firebase_core`, `firebase_messaging`; cấu hình sinh bởi `flutterfire configure --project=shellxpro` (`firebase_options.dart`, `google-services.json`, `GoogleService-Info.plist`). iOS: capability Push Notifications + Background Modes (remote-notification) trong entitlements.
- **Xin quyền thông báo** sau khi đăng nhập và có ít nhất một máy đã ghép nối (Android 13+: `POST_NOTIFICATIONS`). Từ chối → không hỏi lại tự động; Cài đặt có dòng "Thông báo: đang tắt — mở Cài đặt hệ thống".
- **Token:** lấy sau khi có quyền; `PUT` lên relay; nghe `onTokenRefresh` để gửi lại; đăng xuất → `DELETE`. Lỗi mạng → thử lại ở lần mở app sau.
- **Foreground:** FCM không tự hiện → app hiện banner trong app (toastification sẵn có) với tiêu đề + nội dung.
- **Chạm thông báo** (`getInitialMessage`, `onMessageOpenedApp`): mở máy `agent_id`; nếu `session_id` là một tab đang có thì chuyển tới tab đó.
- Firebase chưa cấu hình (thiếu file) → app chạy bình thường, không có push (khởi tạo Firebase trong `try`).

---

## 7. App desktop

- Cài đặt **"Thông báo khi lệnh chạy lâu xong"**: Tắt / 10 giây / 30 giây (mặc định) / 1 phút / 5 phút, trong menu tray (menu con) theo cách các cài đặt hiện có. Lưu trong settings; agent đọc giá trị hiện tại mỗi lần lệnh kết thúc.
- Thông báo chủ động không có công tắc riêng trong bản này.

---

## 8. Tương thích

- App mobile cũ: không đăng ký token → không nhận push; không gì khác đổi.
- Agent cũ: không gọi `POST /v1/notifications`.
- Relay cũ (chưa deploy): agent nhận `404` → bỏ; mobile `PUT` nhận `404` → bỏ, thử lại lần sau.
- Hook phát OSC: các terminal không hiểu chuỗi đều bỏ qua; VS Code hiểu 633/133 (tích hợp sẵn của nó hoạt động như cũ).

---

## 9. Quyền riêng tư

`web/src/pages/privacy.md` và `web/src/pages/en/privacy.md` thêm mục "Thông báo đẩy" (sửa 2026-10-05 sau review N-b): trong lúc cài đặt "Thông báo khi lệnh chạy lâu xong" trên máy tính đang bật (mặc định 30 giây) — và bất cứ khi nào một chương trình phát chuỗi thông báo — agent gửi nội dung thông báo (tên máy, tên phiên/cửa sổ, dòng lệnh, mã thoát, thời gian, hoặc chữ do chương trình gửi) tới relay ShellX; relay chỉ chuyển tiếp qua Google Firebase Cloud Messaging / Apple Push Notification service tới các điện thoại đã ghép nối với máy đó và đã cho phép thông báo, không lưu nội dung; khi không điện thoại nào nhận được (`202 {sent: 0}`), agent ngừng gửi 15 phút; FCM token của điện thoại được lưu tới khi đăng xuất (hoặc tắt thông báo trong cài đặt điện thoại). Câu hỏi đáp "máy chủ lưu gì" thêm mã thông báo đẩy. Câu "relay không đọc được nội dung terminal" được sửa thành "… ngoại trừ nội dung thông báo đẩy".

---

## 10. Kiểm thử

- **Agent:** `OscEventParser` (từng loại chuỗi, cắt ở mọi byte, OSC 9;4 bị bỏ, quá 4 KiB, UTF-8 hỏng); `CommandTracker` (ngưỡng, `D` không `C`, Tắt, dòng lệnh thoát ký tự); `NotificationSender` (chống spam, lỗi mạng không ném, 404/503 bỏ qua) với `fake_async`; snapshot không phát sự kiện; nội dung vi/en.
- **Hook:** test PTY chạy zsh/bash thật với hook của phiên ShellX: `sleep 1; false` (ngưỡng thử 0) → thấy `633;E`, `133;C`, `133;D;1`; file cấu hình người dùng vẫn được nạp (PATH, alias); `shellx notify x` → `777`. Khối `term/shell/` mới: test của crate `term` (cargo) cho nhánh bên trong.
- **Relay:** vitest/bun test theo kiểu hiện có: PUT/DELETE token (quyền mobile, cascade khi xóa thiết bị/đăng xuất, token chuyển thiết bị), POST notifications (chỉ agent, chỉ điện thoại đã ghép nối và có token, giới hạn độ dài, 429, 503 khi thiếu cấu hình), `FcmClient` với HTTP giả (JWT đúng dạng, cache token, xóa token khi `UNREGISTERED`).
- **Mobile:** test widget/controller cho luồng xin quyền, đăng ký/xóa token (backend giả), banner foreground, chạm mở máy/tab.
- **Desktop:** test menu cài đặt ngưỡng.
- **E2E (relay cục bộ):** agent ↔ relay ↔ "điện thoại" giả: lệnh `sleep` vượt ngưỡng thử → relay gọi FCM giả (biến môi trường trỏ FCM tới máy chủ HTTP cục bộ trong test) với đúng nội dung và token.
- **Kiểm tay (việc chờ người dùng):** máy thật iOS/Android với dự án `shellxpro`, app đóng hẳn.

---

## 11. Việc của người dùng (không làm được thay)

1. Tải khóa APNs (.p8) lên dự án Firebase `shellxpro` (Project settings → Cloud Messaging → Apple app).
2. Tạo service account có quyền FCM, đặt file JSON lên VPS (`~/phu/shellx/secrets/fcm.json`) và đặt `FCM_SERVICE_ACCOUNT` trong `.env` theo `deploy/README.md`; rồi push `main` (deploy relay).
3. Bật Push Notifications cho App ID `com.shellx.prod` trong Apple Developer và tạo lại provisioning profile.
4. Kiểm tay trên máy thật.
