# ShellX v1.0 — Đặc tả thiết kế

- **Ngày:** 2026-09-25
- **Trạng thái:** Đã chốt qua brainstorming; chuyển sang lập kế hoạch triển khai
- **Phạm vi:** Desktop agent (macOS/Windows), mobile app (iOS/Android), relay trên Cloudflare, vị trí landing page trong kiến trúc

---

## 1. Mục tiêu

ShellX cho phép người dùng điều khiển terminal trên máy tính (macOS/Windows) từ điện thoại, ở bất kỳ đâu có Internet, mà không cần mang laptop theo. Máy tính chạy một agent nền ở tray; điện thoại mở các phiên terminal trên máy đó thông qua một relay trên Cloudflare, với kênh mã hóa đầu cuối mà relay không đọc được.

**Đối tượng:** sản phẩm phát hành công khai, ai cũng đăng ký tài khoản được.

### Tiêu chí thành công

1. Người dùng mới cài agent, đăng ký tài khoản và ghép nối điện thoại trong dưới 3 phút.
2. Từ điện thoại mở được phiên terminal và dùng được các chương trình toàn màn hình (`vim`, `htop`); Ctrl, Esc, Tab, phím mũi tên hoạt động đúng.
3. Điện thoại mất mạng vài phút rồi quay lại: phiên vẫn còn chạy, output phát sinh trong lúc mất kết nối được bù lại (trong giới hạn bộ đệm 256 KiB mỗi phiên).
4. Relay, hoặc bất kỳ ai có mật khẩu tài khoản nhưng chưa quét QR tại máy, không đọc được và không điều khiển được terminal.
5. Độ trễ gõ phím mục tiêu dưới 150 ms (trung vị) khi điện thoại và máy tính ở cùng khu vực địa lý.

---

## 2. Nhật ký quyết định

| # | Chủ đề | Quyết định |
|---|---|---|
| D1 | Đối tượng | Sản phẩm công khai, nhiều người dùng |
| D2 | Vai trò desktop app v1.0 | Chỉ là agent nền ở tray/menu bar. Mọi phiên terminal do điện thoại mở. Máy tính không hiển thị terminal |
| D3 | Tài khoản | Email + mật khẩu. Không OTP, không xác thực email. Kiểm tra định dạng email và chặn domain email tạm (yopmail, mailinator, …) |
| D4 | Tin cậy thiết bị | Đăng nhập **và** quét QR một lần cho mỗi cặp (điện thoại, máy). Một điện thoại điều khiển được nhiều máy; một máy ghép được với nhiều điện thoại |
| D5 | Tính năng v1.0 | Nhiều phiên dạng tab; thanh phím phụ; copy/paste, chỉnh cỡ chữ, xoay ngang; giữ máy không ngủ |
| D6 | Công nghệ | Flutter cho desktop và mobile; các package Dart thuần dùng chung cho giao thức và mã hóa; relay viết bằng TypeScript |
| D7 | Hạ tầng | Cloudflare (Workers, Durable Objects, D1, R2, Pages) thay cho VPS. Tên miền `shellx.pro` |
| D8 | Landing page | Astro, triển khai trên Cloudflare Pages. Nội dung marketing làm ở spec riêng |
| D9 | Ngôn ngữ giao diện | Tiếng Việt và tiếng Anh ngay từ v1.0 |

---

## 3. Phạm vi

### 3.1 Trong phạm vi v1.0

- Desktop agent cho macOS 12+ và Windows 10 bản 1809+ (bản đầu tiên có ConPTY).
- Mobile app cho iOS 15+ và Android 8.0 (API 26)+.
- Relay: REST API tài khoản/thiết bị/ghép nối và hub WebSocket.
- Trang chính sách quyền riêng tư và điều khoản sử dụng trên `shellx.pro` (bắt buộc khi nộp app lên store), kèm trang chủ tối thiểu có link tải.

### 3.2 Ngoài phạm vi v1.0

- Hiển thị/mirror terminal trên desktop.
- Push notification.
- Truyền file.
- Kết nối P2P (WebRTC).
- Lệnh cần quyền admin/UAC trên Windows.
- Giữ phiên sau khi agent khởi động lại.
- Tự động cập nhật (chỉ thông báo có bản mới).
- Thu phí.
- Xác thực email, OTP, quên mật khẩu qua email.
- Nội dung marketing của landing page (spec riêng).

---

## 4. Kiến trúc

```
                         ┌──────────────────────────────────────────────┐
                         │  Cloudflare                                  │
                         │  shellx.pro           → Landing page (Astro) │
                         │  download.shellx.pro  → R2: bản cài desktop  │
                         │  relay.shellx.pro     → Worker + Durable     │
                         │                         Object + D1          │
                         └───────▲──────────────────────────▲───────────┘
                           WSS   │                          │  WSS
                    ┌────────────┴──┐                ┌──────┴─────────┐
                    │  Mobile app   │                │ Desktop agent  │
                    │  iOS/Android  │                │ macOS/Windows  │
                    └───────┬───────┘                └──────┬─────────┘
                            └════ Kênh mã hóa đầu cuối ═════┘
```

- Cả điện thoại và agent đều **chủ động kết nối ra** relay; không cần mở port ở router nhà người dùng.
- Mỗi thiết bị giữ đúng **một** kết nối WebSocket tới relay.
- Worker xác thực token rồi chuyển WebSocket vào **Durable Object `UserHub` của tài khoản** (mỗi tài khoản đúng một hub, `idFromName(user_id)`). Vì mọi thiết bị của một tài khoản nối vào cùng một hub, việc "chỉ chuyển gói tin trong cùng tài khoản" được đảm bảo bởi cấu trúc.
- Relay chỉ thấy khung có payload đã mã hóa; không biết nội dung terminal, kể cả số tab đang mở.

### 4.1 Thành phần

| Thành phần | Trách nhiệm |
|---|---|
| **Relay** (`relay/`, TypeScript) | Đăng ký/đăng nhập, lưu thiết bị và ghép nối trong D1, theo dõi online/offline, chuyển tiếp khung giữa các thiết bị cùng tài khoản |
| **`shellx_core`** (Dart thuần) | Khung relay, tin nhắn ứng dụng (CBOR), giao thức Noise, client REST, client WebSocket có tự kết nối lại |
| **`shellx_agent`** (Dart thuần) | Quản lý phiên terminal, bộ đệm vòng, gom output, kiểm soát lưu lượng, bên nhận khi ghép nối, danh sách thiết bị tin cậy. Làm việc với PTY qua interface `Pty` |
| **`shellx_client`** (Dart thuần) | Kết nối tới từng máy, trạng thái tab và gắn lại phiên, bên khởi tạo khi ghép nối |
| **Desktop app** (`apps/desktop/`, Flutter) | Tray, cửa sổ đăng nhập/onboarding/QR, adapter `flutter_pty`, lưu trữ bảo mật, giữ máy không ngủ, tự khởi động |
| **Mobile app** (`apps/mobile/`, Flutter) | Màn hình đăng nhập, danh sách máy, quét QR, terminal (`xterm.dart`) theo tab, thanh phím phụ, khóa sinh trắc học |
| **Landing** (`web/`, Astro) | Trang chủ, privacy, terms, link tải |

Tách `shellx_agent` và `shellx_client` thành Dart thuần để chạy được test end-to-end không cần giao diện.

### 4.2 Tên miền

| Tên miền | Dịch vụ |
|---|---|
| `shellx.pro` | Landing page (Cloudflare Pages) |
| `relay.shellx.pro` | Worker production |
| `relay-staging.shellx.pro` | Worker staging |
| `download.shellx.pro` | R2 bucket công khai chứa bản cài desktop |

### 4.3 Cấu trúc repo

```
shellx/
  pubspec.yaml               # gốc Dart pub workspace
  packages/
    shellx_core/
    shellx_agent/
    shellx_client/
  apps/
    desktop/
    mobile/
  relay/                     # Worker (Hono) + Durable Object UserHub + D1 migrations (wrangler)
  web/                       # Astro
  docs/
```

---

## 5. Tài khoản, định danh thiết bị và ghép nối

### 5.1 Khóa thiết bị

- Lần đầu chạy, mỗi thiết bị tạo một cặp khóa **X25519** tĩnh.
- Khóa bí mật không bao giờ rời thiết bị; lưu qua `flutter_secure_storage` (Keychain trên macOS/iOS, trên Windows: khóa AES lưu trong Windows Credential Manager, dữ liệu mã hóa AES-GCM trong thư mục dữ liệu của app, Keystore trên Android).
- Cài lại app thường sinh khóa mới nên phải ghép nối lại (trên macOS, mục Keychain có thể còn sau khi gỡ app, khi đó khóa cũ được dùng lại và ghép nối vẫn còn hiệu lực).

### 5.2 Tài khoản

- **Email:** cắt khoảng trắng, chuyển chữ thường, kiểm tra bằng biểu thức chính quy thực dụng (một phần của RFC 5322). Domain và mọi domain cha của nó không được nằm trong danh sách `disposable-email-domains`; danh sách được đóng gói vào Worker lúc build bằng script.
- **Mật khẩu:** 8–128 ký tự. Băm bằng **argon2id** (m = 19 456 KiB, t = 2, p = 1), lưu dạng chuỗi PHC.
- **Đăng ký / đăng nhập** luôn kèm thông tin thiết bị `{kind, name, platform, public_key}`. Nếu khóa công khai đó đã có trong tài khoản thì dùng lại `device_id` cũ; nếu chưa thì tạo thiết bị mới. `name` là hostname (agent) hoặc tên model máy (mobile).
- **Token thiết bị:** 32 byte ngẫu nhiên, mã hóa base64url, gửi qua header `Authorization: Bearer <token>`. D1 chỉ lưu SHA-256 của token. Token hết hạn khi `last_used_at` cũ hơn 90 ngày; `last_used_at` cập nhật tối đa một lần mỗi giờ.
- **Giới hạn tần suất** (rate limiting binding của Workers, chu kỳ 60 giây): đăng nhập 10 lần/IP và 5 lần/email; đăng ký 3 lần/IP. Vượt giới hạn trả HTTP 429.
- **Đổi mật khẩu:** chỉ token của agent được gọi, không cần mật khẩu cũ (máy đang đăng nhập là bằng chứng; thay cho "quên mật khẩu"). Sau khi đổi: thu hồi token của mọi thiết bị khác và đóng WebSocket của chúng (mã 4002). **Ghép nối giữ nguyên.**
- **Đăng xuất trên agent:** xóa token, xóa các bản ghi ghép nối của agent trong D1, xóa danh sách tin cậy cục bộ, đóng mọi phiên. Đăng nhập lại phải ghép nối lại.
- **Đăng xuất trên mobile:** chỉ xóa token. Khóa thiết bị (một khóa chung cho điện thoại, vì lúc đăng nhập phải gửi khóa công khai trước khi biết `user_id`) và danh sách máy đã ghim (lưu theo `user_id`) được giữ lại, để đăng nhập lại cùng tài khoản không mất ghép nối. Tài khoản khác đăng nhập trên cùng điện thoại không thấy danh sách máy đã ghim đó.
- **Xóa tài khoản** (bắt buộc theo quy định App Store 5.1.1(v)): trong Cài đặt của mobile app, người dùng nhập lại mật khẩu để xác nhận. Relay xóa người dùng cùng mọi thiết bị, token và ghép nối, rồi đóng WebSocket của mọi thiết bị với mã 4002.
- **Agent nhận 4002 (hoặc bị từ chối 401 khi kết nối):** agent không phân biệt được "đổi mật khẩu" với "xóa tài khoản", nên luôn: xóa token, đóng mọi phiên, **giữ** khóa thiết bị và danh sách tin cậy, rồi hiện cửa sổ đăng nhập. Khi đăng nhập lại thành công, nếu `user_id` khác `user_id` đã lưu thì xóa danh sách tin cậy (đổi tài khoản hoặc tài khoản cũ đã bị xóa); cùng `user_id` thì giữ nguyên ghép nối.
- **Hỗ trợ khẩn cấp:** script quản trị `relay/scripts/reset-password.ts` chạy qua `wrangler d1` để đặt lại mật khẩu thủ công.

### 5.3 Ghép nối bằng QR

1. Trên tray chọn **"Ghép nối điện thoại…"**. Agent sinh **mã ghép nối** 32 byte ngẫu nhiên, dùng một lần, hết hạn sau 5 phút hoặc khi đóng cửa sổ QR. Mỗi lúc chỉ có tối đa một mã hiệu lực.
2. Cửa sổ hiện QR chứa URI:
   `shellx://pair?v=1&d=<agent_device_id>&k=<agent_public_key_b64url>&s=<pairing_secret_b64url>`
3. Điện thoại (đã đăng nhập) quét QR. Nếu `d` không có trong `GET /v1/devices` của tài khoản, báo *"Máy này không thuộc tài khoản của bạn. Hãy đăng nhập cùng tài khoản trên máy tính."* và dừng.
4. Điện thoại bắt tay **Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s** với agent qua hub: khóa công khai của agent lấy **từ QR**, mã ghép nối làm PSK.
5. Ngay sau bắt tay, điện thoại gửi tin `pair.confirm`. Agent giải mã thành công tin này (chứng minh điện thoại có đúng mã ghép nối) thì:
   - lưu `{mobile_device_id, public_key, name, paired_at}` vào **danh sách tin cậy cục bộ** (secure storage);
   - vô hiệu hóa mã ghép nối;
   - gọi `POST /v1/pairings` (bản ghi chỉ để hiển thị);
   - hiện thông báo "Đã ghép nối với <tên điện thoại>" và đóng cửa sổ QR.
6. Điện thoại ghim `{agent_device_id, agent_public_key}`.

Sai mã ghép nối làm điện thoại không giải mã được tin bắt tay thứ hai; điện thoại báo *"Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính."* (cùng câu với mục 12).

### 5.4 Kết nối hằng ngày

- Điện thoại bắt tay **Noise_IK_25519_ChaChaPoly_BLAKE2s** bằng khóa đã ghim.
- Agent chỉ chấp nhận khóa có trong danh sách tin cậy cục bộ. **Agent là nguồn sự thật về tin cậy, không phải server.**

### 5.5 Thu hồi

- **Tray → "Thiết bị đã ghép" → Thu hồi:** agent xóa khóa khỏi danh sách tin cậy (hiệu lực ngay), đóng các kênh và phiên đang gắn với điện thoại đó, rồi gọi `DELETE /v1/pairings/:agent_id/:mobile_id`.
- **Mobile → Cài đặt → Bỏ ghép nối một máy:** điện thoại xóa khóa đã ghim và gọi API xóa ghép nối. Hub gửi sự kiện `pairing_removed` cho agent; agent xóa khóa khỏi danh sách tin cậy. (Relay chỉ có thể *bớt* tin cậy, không bao giờ *thêm* được.)

### 5.6 Khóa app mobile

Face ID / vân tay / mã máy qua `local_auth`. Mặc định bật. Yêu cầu mở khóa khi mở app và khi quay lại sau hơn 5 phút ở nền.

---

## 6. Giao thức truyền

### 6.1 WebSocket

- URL: `wss://relay.shellx.pro/v1/ws`, header `Authorization: Bearer <token>`.
- **Khung văn bản** chỉ dùng cho nhịp tim: client gửi `ping` mỗi 30 giây, hub trả `pong` bằng `setWebSocketAutoResponse` (không đánh thức Durable Object). Không nhận `pong` trong 10 giây thì client coi như mất kết nối.
- **Khung nhị phân** là khung relay (mục 6.2).

### 6.2 Khung relay

```
Byte 0 : version = 1
Byte 1 : type
  0x01 DATA      [2..17]  peer device_id (UUID, 16 byte)
                 [18..25] channel_id (8 byte)
                 [26..]   payload (mục 6.3)
  0x02 PRESENCE  [2..17]  device_id | [18] 0 = offline, 1 = online          (hub → client)
  0x03 ERROR     [2..3]   code (uint16, big-endian)
                 [4..19]  device_id | [20..27] channel_id                   (hub → client)
  0x04 EVENT     [2..]    CBOR {event, ...}                                  (hub → client)
```

- DATA từ client lên hub: `peer` là thiết bị đích. Hub chuyển xuống thiết bị đích với `peer` được thay bằng thiết bị nguồn.
- Mã lỗi: `1 peer_offline`, `2 frame_too_large`, `3 rate_limited`, `4 bad_frame`.
- Sự kiện: `{event: "pairing_removed", agent_id, mobile_id}`.
- Mã đóng WebSocket: `4001 replaced` (cùng thiết bị vừa kết nối lần nữa), `4002 revoked` (token bị thu hồi), `4003 rate_limited`.
- Giới hạn: khung tối đa 64 KiB; mỗi kết nối tối đa 500 khung/giây (token bucket). Vượt giới hạn: hub gửi ERROR `rate_limited` rồi đóng với mã 4003.
- Khi một thiết bị kết nối, hub gửi cho nó PRESENCE của mọi thiết bị đang online trong tài khoản và báo thiết bị mới online cho các thiết bị còn lại. Khi ngắt, hub báo offline và ghi `last_seen_at` vào D1.

### 6.3 Kênh mã hóa (payload của DATA)

```
Byte 0 : kind
  0x01 HS1_IK       Noise message 1 — Noise_IK_25519_ChaChaPoly_BLAKE2s
  0x02 HS1_IKPSK2   Noise message 1 — Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s (ghép nối)
  0x03 HS2          Noise message 2
  0x04 TRANSPORT    Noise transport message
Byte 1.. : Noise message
```

- Bên khởi tạo là **mobile**, bên nhận là **agent**. Mobile sinh `channel_id` ngẫu nhiên cho mỗi lần bắt tay.
- **Prologue:** `"shellx/1" || agent_device_id || mobile_device_id` (buộc danh tính thiết bị vào kênh, hub không tráo `device_id` được).
- **Payload HS1** (CBOR): `{proto: 1, app: "<phiên bản app>", name: "<tên thiết bị>", platform}`.
- **Payload HS2** (CBOR): `{proto: 1, app, status}` với `status ∈ {"ok", "untrusted", "pairing_invalid", "proto_unsupported"}`. Status khác `"ok"` thì agent hủy kênh ngay sau khi gửi HS2.
- Agent giữ tối đa một kênh cho mỗi `mobile_device_id`; HS1 mới từ cùng điện thoại thay thế kênh cũ.
- Mọi lỗi giải mã: hủy kênh; mobile bắt tay lại với `channel_id` mới. **Không có chế độ truyền không mã hóa.**
- Noise được cài đặt trong `shellx_core` bằng package `cryptography` và phải vượt qua bộ test vector chính thức của Noise cho hai pattern trên.

### 6.4 Tin nhắn ứng dụng

Payload của mỗi TRANSPORT là **mảng CBOR gồm 1..n tin nhắn**. Mỗi tin nhắn là map CBOR có khóa `t`. `id` của phiên là số nguyên do agent cấp: bắt đầu từ một giá trị ngẫu nhiên trong `[1, 2^31)` mỗi lần agent khởi động rồi tăng dần, để điện thoại không gắn nhầm vào phiên mới trùng id sau khi agent khởi động lại.

| `t` | Chiều | Trường | Ý nghĩa |
|---|---|---|---|
| `pair.confirm` | M → A | — | Xác nhận ghép nối (mục 5.3) |
| `session.list` | M → A | — | Hỏi danh sách phiên |
| `session.list.result` | A → M | `sessions: [{id, index, shell, created_at, attached}]` | Danh sách phiên trên máy |
| `session.open` | M → A | `cols, rows` | Mở phiên mới |
| `session.opened` | A → M | `id, index, shell` | Phiên đã mở và gắn vào điện thoại này |
| `session.attach` | M → A | `id, cols, rows, last_seq` | Gắn vào phiên có sẵn |
| `session.attached` | A → M | `id` | Đã gắn; output bù đã gửi trước tin này |
| `session.reset` | A → M | `id` | Client xóa màn hình; output tiếp theo bắt đầu từ đầu bộ đệm |
| `output` | A → M | `id, seq, data` | Output terminal; `seq` là vị trí byte đầu tiên của `data` |
| `ack` | M → A | `id, seq` | Đã nhận tới vị trí byte `seq` |
| `input` | M → A | `id, data` | Phím/dữ liệu gõ vào |
| `resize` | M → A | `id, cols, rows` | Đổi kích thước |
| `session.close` | M → A | `id` | Đóng phiên |
| `session.exited` | A → M | `id, exit_code` | Phiên đã kết thúc |
| `session.detached` | A → M | `id, reason` | `reason ∈ {"taken_over", "closed_by_host"}` |
| `error` | A → M | `code, message, id?` | `code ∈ {"session_limit", "session_not_found", "spawn_failed"}` |

### 6.5 Gom tin nhắn và kiểm soát lưu lượng

- **Agent gom theo kênh:** mỗi 16 ms gửi một TRANSPORT chứa mọi tin đang chờ (của mọi phiên), hoặc gửi ngay khi output chờ đạt 16 KiB. Mỗi tin `output` tối đa 16 KiB.
- **Mobile** gửi `input` ngay khi có phím; dữ liệu dán lớn hơn 16 KiB được cắt thành nhiều tin.
- **`seq`:** luồng output của mỗi phiên được đánh số theo byte, bắt đầu từ 0. Client giữ `received` = `seq + len(data)` của tin cuối cùng.
- **`ack`:** mobile gửi khi nhận thêm ≥ 32 KiB kể từ `ack` trước, hoặc 100 ms sau lần nhận cuối nếu còn dữ liệu chưa ack.
- **Cửa sổ gửi:** agent ngừng gửi output của một phiên khi `sent - acked > 256 KiB`, nhưng **vẫn đọc PTY** vào bộ đệm vòng. Khi được gửi tiếp mà dữ liệu cần gửi đã bị ghi đè, agent gửi `session.reset` rồi gửi lại từ đầu bộ đệm.

---

## 7. Phiên terminal (agent)

- **Shell:**
  - macOS: shell mặc định trong bản ghi tài khoản người dùng (đọc bằng `dscl . -read /Users/<user> UserShell`), chạy dạng login shell (`-l`) để nạp PATH từ profile; nếu không đọc được thì dùng `/bin/zsh`.
  - Windows: `pwsh.exe` nếu có trong PATH, nếu không thì `powershell.exe`.
- **Môi trường:** thư mục ban đầu là home; `TERM=xterm-256color`, `COLORTERM=truecolor`, `LANG=en_US.UTF-8` nếu chưa đặt, `SHELLX=1`.
- **Giới hạn:** tối đa **10 phiên** mỗi máy. Vượt thì trả `error {code: "session_limit"}`.
- **Bộ đệm vòng** 256 KiB mỗi phiên, lưu `[start, end)` theo `seq`. Agent đọc PTY liên tục kể cả khi không có client gắn vào; khi đầy thì ghi đè dữ liệu cũ nhất.
- **Một client mỗi phiên:** `session.attach` từ điện thoại khác làm client cũ nhận `session.detached {reason: "taken_over"}`. Kênh của client bị hủy thì phiên trở thành không gắn (không cần tin nhắn).
- **Gắn lại:**
  - `last_seq ≥ start`: gửi output từ `last_seq` tới `end`.
  - `last_seq < start`: gửi `session.reset`, rồi output từ `start`.
  - Sau đó áp dụng `cols, rows` của tin attach. Nếu kích thước không đổi, agent resize sang `(cols, rows - 1)` rồi về `(cols, rows)` để ép các ứng dụng toàn màn hình vẽ lại.
  - Cuối cùng gửi `session.attached`.
- **Tiêu đề tab** do mobile quyết định: tiêu đề terminal (OSC 0/2) nếu shell đặt, không thì `"<shell> <index>"`.
- **Kết thúc phiên:** khi shell thoát (gửi `session.exited`), khi điện thoại gửi `session.close`, hoặc khi đóng từ tray (`session.detached {reason: "closed_by_host"}` rồi `session.exited`). Đóng phiên nghĩa là đóng PTY và kết thúc toàn bộ cây tiến trình con.
- v1.0 **không tự đóng** phiên bị bỏ quên.
- Thoát agent hoặc khởi động lại máy: mọi phiên mất.

---

## 8. Desktop agent

### 8.1 Package chính

`flutter_pty`, `tray_manager`, `window_manager`, `launch_at_startup`, `flutter_secure_storage`, `shared_preferences`, `local_notifier`, `qr_flutter`, `win32` (Windows), `flutter_riverpod`, `flutter_localizations`/`intl`.

### 8.2 Lần chạy đầu tiên

1. Cửa sổ **đăng nhập / đăng ký**.
2. Onboarding: bật "Khởi động cùng hệ thống" (mặc định bật); trên macOS hướng dẫn cấp **Full Disk Access** (nút mở `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`); giải thích rằng gập nắp laptop thì máy vẫn ngủ.
3. Ẩn cửa sổ; từ đó chỉ còn icon tray. macOS dùng `LSUIElement = true` (không hiện Dock).

Chỉ một bản agent chạy cùng lúc (khóa file trong thư mục dữ liệu ứng dụng).

### 8.3 Menu tray

```
● Đã kết nối — user@email.com
─────────────────────────────
✓ Cho phép truy cập từ xa
  Phiên đang hoạt động (n)      ▸  [từng phiên: Đóng] · Đóng tất cả
  Ghép nối điện thoại…
  Thiết bị đã ghép              ▸  [từng thiết bị: Thu hồi]
─────────────────────────────
✓ Giữ máy không ngủ
✓ Khởi động cùng hệ thống
  Đổi mật khẩu…
  Đăng xuất
  Thoát
```

- **Icon tray** có 3 trạng thái: bình thường, mất kết nối (xám), đang có điện thoại điều khiển (màu nổi).
- **Thông báo hệ thống** mỗi khi một điện thoại mở phiên mới ("<tên điện thoại> vừa mở phiên terminal"). Mặc định bật.
- **Tắt "Cho phép truy cập từ xa":** ngắt WebSocket tới relay và đóng mọi phiên; hỏi xác nhận nếu đang có phiên. Trạng thái bật/tắt được nhớ qua các lần khởi động.
- **Giữ máy không ngủ** (mặc định bật):
  - macOS: tiến trình con `caffeinate -i -w <pid agent>`.
  - Windows: `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)`.
  - Chỉ chặn máy tự ngủ khi để yên; không chặn ngủ khi gập nắp.
- **Đổi mật khẩu…:** cửa sổ nhập mật khẩu mới hai lần.

### 8.4 Lưu trữ

- Secure storage: khóa bí mật thiết bị, token, `device_id`, `user_id`, email, danh sách tin cậy.
- `shared_preferences`: các công tắc cài đặt.

### 8.5 Quyền và phát hành theo nền tảng

- **macOS:** mở shell không cần quyền. Lệnh chạm vào Desktop/Documents/Downloads sẽ bật hộp thoại TCC trên màn hình laptop, nên onboarding hướng dẫn cấp Full Disk Access (không bắt buộc). Phát hành ngoài Mac App Store (sandbox không cho spawn shell), ký Developer ID, notarize, bật hardened runtime, không bật App Sandbox.
- **Windows:** không cần quyền đặc biệt; shell chạy với quyền người dùng thường. Không hỗ trợ lệnh cần UAC.

---

## 9. Mobile app

### 9.1 Package chính

App dựng trên base Flutter của team (`flutter-base/yallabb`): kiến trúc feature-first (data/domain/presentation), `get_it` + `injectable` (DI), `auto_route` (điều hướng), `signals_flutter` (`Controller` + `StateSignal`), `intl_utils` (`S.of(context)`), design system/`adaptive_theme`/`toastification` của base. Package riêng của ShellX: `xterm`, `mobile_scanner`, `local_auth`, `flutter_secure_storage`, `flutter_localizations`/`intl`. REST và relay đi qua `shellx_core` (`package:http`), không dùng tầng `dio`/refresh token của base. Font JetBrains Mono đóng gói sẵn cho terminal. Không dùng `cryptography_flutter`: `shellx_core` ghim backend Dart thuần (DartX25519, DartChacha20, DartBlake2s) để mọi nền tảng chạy đúng phần mã đã kiểm bằng test vector.

### 9.2 Màn hình

1. **Đăng nhập / Đăng ký.**
2. **Danh sách máy** (agent của tài khoản): tên, icon hệ điều hành, chấm online/offline (từ `GET /v1/devices` + PRESENCE), "Lần cuối online: …" khi offline. Máy chưa ghép có nhãn "Chưa ghép nối"; bấm vào mở màn quét QR.
3. **Quét QR.**
4. **Terminal của một máy:** hàng tab ở trên (`+` mở phiên mới, `×` đóng phiên), vùng `xterm.dart`, thanh phím phụ ngay trên bàn phím. Mở màn này lần đầu thì gửi `session.list` và cho phép gắn vào phiên có sẵn.
5. **Cài đặt:** cỡ chữ mặc định, khóa sinh trắc học, bỏ ghép nối từng máy, đăng xuất, **xóa tài khoản** (nhập lại mật khẩu, cảnh báo không hoàn tác được), phiên bản app.

**Thiết kế giao diện (người dùng đã duyệt 2026-09-25):** `docs/superpowers/design/2026-09-25-shellx-mobile-ui.html` quy định bố cục, câu chữ và trạng thái của từng màn hình, gồm cả bảng màu tối (base chưa có) và các chi tiết sau:
- Nút "Aa" trên thanh terminal mở thanh trượt cỡ chữ (ngoài thao tác chụm hai ngón).
- Thẻ máy hiện số tab đang mở trên điện thoại này.
- Màn đăng nhập có câu "Quên mật khẩu? Đổi mật khẩu trong ShellX trên máy tính đang đăng nhập."
- Phiên đã thoát: tab giữ nguyên nội dung và hiện thẻ "Phiên đã kết thúc" với hai nút "Đóng tab" / "Mở phiên mới".
- Sau khi bị đóng với 4002, màn đăng nhập có băng rôn "Phiên đăng nhập đã hết hiệu lực. Hãy đăng nhập lại." và điền sẵn email.
- Chọn phiên có sẵn là bottom sheet; máy chưa có phiên thì mở thẳng phiên mới. Lần đầu dùng (chưa có máy) hiện 3 bước ghép nối và nút "Quét mã QR".
- Giao diện sáng/tối theo máy; vùng terminal luôn nền tối; mọi vùng chạm cao ít nhất 44 pt.

### 9.3 Thanh phím phụ

Một hàng cuộn ngang: `Esc` `Tab` `Ctrl` `Alt` `↑` `↓` `←` `→` `|` `~` `/` `-` `Home` `End` `PgUp` `PgDn` `Dán`.

`Ctrl` và `Alt` là phím dính: chạm một lần áp dụng cho phím kế tiếp; chạm hai lần khóa lại cho tới khi chạm lần nữa.

### 9.4 Tương tác

- Nhấn giữ để chọn chữ và copy; dán dùng bracketed paste khi ứng dụng bật chế độ này.
- Chụm hai ngón để đổi cỡ chữ.
- Xoay ngang hoặc đổi kích thước vùng terminal thì gửi `resize`.
- Bàn phím rời (iPad, Bluetooth) dùng được.
- Một điện thoại giữ đồng thời kênh tới mọi máy đang có tab mở, khi app ở foreground.
- App xuống nền: iOS cắt kết nối. Khi quay lại, app kết nối lại, bắt tay lại và gắn lại các tab bằng `last_seq`.

### 9.5 Lưu trữ

Secure storage: khóa bí mật thiết bị, token, `device_id`, danh sách máy đã ghim theo `user_id`.

---

## 10. Relay

### 10.1 Công nghệ

TypeScript, Hono, wrangler, D1, Durable Object dùng SQLite storage và WebSocket Hibernation API, rate limiting binding. argon2id chạy bằng module WASM **import tĩnh** (Workers không cho biên dịch WASM động lúc chạy). Cần gói Workers Paid.

### 10.2 API

Mọi lỗi trả JSON `{error: {code, message}}`.

| Method & đường dẫn | Xác thực | Body | Kết quả / lỗi |
|---|---|---|---|
| `POST /v1/auth/register` | — | `{email, password, device}` | `201 {user_id, device_id, token}`; `400 invalid_email`, `400 disposable_email`, `400 weak_password`, `409 email_taken`, `429` |
| `POST /v1/auth/login` | — | `{email, password, device}` | `200 {user_id, device_id, token}`; `401 invalid_credentials`, `429` |
| `POST /v1/auth/logout` | token | — | `204`. Token agent: xóa thêm ghép nối của agent |
| `POST /v1/auth/password` | token agent | `{new_password}` | `204`; `403 agent_only`, `400 weak_password` |
| `DELETE /v1/account` | token | `{password}` | `204`; `401 invalid_credentials`. Xóa người dùng (cascade thiết bị, token, ghép nối) và đóng WebSocket mọi thiết bị với 4002 |
| `GET /v1/devices` | token | — | `200 [{id, kind, name, platform, online, last_seen_at, paired_with_me}]` (không trả khóa công khai) |
| `POST /v1/pairings` | token agent | `{mobile_id}` | `201`; `404 device_not_found` |
| `DELETE /v1/pairings/:agent_id/:mobile_id` | token của một trong hai bên | — | `204`; hub gửi `pairing_removed` cho bên còn lại |
| `GET /v1/ws` | token | — | `101` → chuyển vào `UserHub` |
| `GET /v1/version` | — | — | `{min_agent, min_mobile, latest_agent: {version, mac_url, win_url}}` (lấy từ biến môi trường) |

`device` = `{kind: "agent" | "mobile", name, platform: "macos" | "windows" | "ios" | "android", public_key}` với `public_key` là base64url 32 byte.

### 10.3 D1

```sql
CREATE TABLE users (
  id                  TEXT PRIMARY KEY,           -- UUID
  email               TEXT NOT NULL UNIQUE,       -- đã chuẩn hóa chữ thường
  password_hash       TEXT NOT NULL,              -- chuỗi PHC argon2id
  password_changed_at INTEGER NOT NULL,           -- unix ms
  created_at          INTEGER NOT NULL
);

CREATE TABLE devices (
  id           TEXT PRIMARY KEY,                  -- UUID
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind         TEXT NOT NULL CHECK (kind IN ('agent', 'mobile')),
  name         TEXT NOT NULL,
  platform     TEXT NOT NULL CHECK (platform IN ('macos', 'windows', 'ios', 'android')),
  public_key   BLOB NOT NULL,                     -- X25519, 32 byte
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER,
  UNIQUE (user_id, public_key)
);

CREATE TABLE tokens (
  token_hash   BLOB PRIMARY KEY,                  -- SHA-256
  device_id    TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  created_at   INTEGER NOT NULL,
  last_used_at INTEGER NOT NULL
);

CREATE TABLE pairings (
  agent_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  mobile_id  TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (agent_id, mobile_id)
);
```

### 10.4 Durable Object `UserHub`

- Nhận WebSocket từ Worker kèm `device_id` và `kind` đã xác thực; `ctx.acceptWebSocket(ws)` và lưu `{device_id, kind}` bằng `serializeAttachment`.
- Thiết bị đã có kết nối mà kết nối lần nữa: đóng kết nối cũ với mã 4001.
- Chuyển khung DATA, gửi PRESENCE, áp giới hạn khung (mục 6.2).
- Phương thức RPC cho Worker: `online(): string[]`, `disconnect(deviceIds: string[], code: number)`, `notifyPairingRemoved(agentId, mobileId)`.

### 10.5 Vận hành

- Hai môi trường `staging` và `production` trong `relay/wrangler.jsonc`; migration bằng `wrangler d1 migrations`.
- Log chỉ ghi siêu dữ liệu (thời điểm, `device_id`, mã lỗi, kích thước khung). **Không bao giờ ghi payload, token hay mật khẩu.**

---

## 11. Landing page (`web/`)

- Astro, xuất trang tĩnh, triển khai trên Cloudflare Pages tại `shellx.pro`.
- v1.0 tối thiểu: trang chủ đơn giản có link tải (macOS, Windows, App Store, Google Play), `/privacy`, `/terms`, song ngữ Việt/Anh.
- Nội dung và thiết kế marketing đầy đủ: spec riêng.

---

## 12. Xử lý lỗi

| Tình huống | Cách xử lý |
|---|---|
| Mất kết nối tới relay | Kết nối lại với thời gian chờ tăng dần 1 s → tối đa 30 s, cộng độ trễ ngẫu nhiên. Agent thử mãi; mobile thử khi ở foreground và kết nối lại ngay khi app quay lại. Mobile hiện băng rôn "Mất kết nối, đang thử lại…" |
| Máy offline | Máy màu xám, "Lần cuối online: …"; không mở được tab |
| HS2 `untrusted` | "Máy không còn tin cậy điện thoại này. Hãy ghép nối lại." và xóa khóa đã ghim |
| Mã QR sai hoặc hết hạn (HS2 `pairing_invalid` hoặc không giải mã được HS2) | "Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính." |
| Lệch phiên bản (HS2 `proto_unsupported`, hoặc `/v1/version` cao hơn phiên bản app) | "Cần cập nhật app" kèm link tải |
| `error session_limit` | "Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên." |
| `error spawn_failed` | Hiện lý do lỗi trong tab |
| WebSocket đóng với 4002 | Xóa token, về màn hình đăng nhập |
| WebSocket đóng với 4001 | Không tự kết nối lại (một phiên bản khác của app đã kết nối) |
| Giải mã thất bại / khung hỏng | Hủy kênh và bắt tay lại; không bao giờ truyền không mã hóa |
| HTTP 429 | "Thử lại sau ít phút." |

---

## 13. Kiểm thử

- **`shellx_core`:** Noise IK và IKpsk2 với bộ test vector chính thức; mã hóa/giải mã khung relay và tin nhắn CBOR; logic kết nối lại với đồng hồ giả lập.
- **`shellx_agent`:** quản lý phiên với `Pty` giả; bộ đệm vòng, `seq`, gắn lại, reset, cửa sổ gửi; danh sách tin cậy; giới hạn 10 phiên; luồng ghép nối bên nhận.
- **`shellx_client`:** trạng thái tab, gắn lại theo `last_seq`, xử lý `session.reset`, luồng ghép nối bên khởi tạo, lịch gửi `ack`.
- **Relay:** Vitest với `@cloudflare/vitest-pool-workers` (workerd thật, có D1 và Durable Object): đăng ký/đăng nhập, kiểm tra email và domain tạm, token, đổi mật khẩu thu hồi token, **không chuyển khung giữa hai tài khoản**, PRESENCE, giới hạn khung, mã đóng 4001/4002/4003.
- **Desktop:** test tích hợp PTY thật (`flutter_pty`) chạy trên máy macOS và Windows trong CI; test widget cho các cửa sổ.
- **Mobile:** test widget cho thanh phím phụ (logic phím dính), quản lý tab.
- **End-to-end (không giao diện):** `shellx_agent` (với adapter `Pty` dùng `Process` của `dart:io`) và `shellx_client` chạy với relay cục bộ `wrangler dev`: đăng ký → ghép nối → mở phiên → `echo hello` → kiểm tra output → ngắt kết nối → gắn lại → kiểm tra output bù. Các ca bảo mật: khóa lạ bị từ chối, mã QR hết hạn, mã QR sai.

---

## 14. Phát hành và CI

- **CI (GitHub Actions):** test Dart packages, test relay, test tích hợp desktop trên `macos-latest` và `windows-latest`, test widget mobile, test end-to-end.
- **macOS:** `.dmg`, ký Developer ID, notarize bằng `notarytool`.
- **Windows:** bộ cài Inno Setup `.exe`, ký code (chứng chỉ OV hoặc Azure Trusted Signing).
- Bản cài desktop tải lên R2 theo đường dẫn `desktop/<version>/…`, phục vụ qua `download.shellx.pro`.
- **Mobile:** App Store và Google Play, trỏ tới `https://shellx.pro/privacy`.
- **Cập nhật:** agent gọi `/v1/version` khi khởi động và mỗi 24 giờ; có bản mới thì hiện thông báo kèm link tải. Mobile chặn sử dụng khi phiên bản thấp hơn `min_mobile`.

---

## 15. Rủi ro và việc cần xác minh sớm

| # | Rủi ro | Cách xử lý |
|---|---|---|
| R1 | argon2id trên Workers: module WASM phải import tĩnh và vừa giới hạn CPU/bộ nhớ | Làm spike đầu tiên khi dựng relay; đo thời gian băm với tham số ở mục 5.2 |
| R2 | Chi phí Cloudflare tính theo số tin nhắn WebSocket vào Durable Object | Kiểm bảng giá hiện hành và ước tính chi phí mỗi người dùng trước khi mở đăng ký công khai; thiết kế đã gom tin 16 ms và giới hạn cửa sổ gửi |
| R3 | `flutter_pty` trên Windows (ConPTY) | Test tích hợp trên Windows trong CI ngay từ đầu, với `pwsh`, `powershell` và một ứng dụng toàn màn hình |
| R4 | Noise tự cài đặt trên package `cryptography` | Bắt buộc vượt test vector chính thức trước khi dùng; review riêng phần này |
| R5 | App Flutter tốn RAM khi chỉ nằm ở tray | Đo trên macOS và Windows; chấp nhận cho v1.0 |
| R6 | Hộp thoại TCC trên macOS vẫn có thể xuất hiện | Onboarding hướng dẫn Full Disk Access; ghi rõ trong tài liệu người dùng |
