# ShellX v1.0 — Tổng quan kế hoạch và hợp đồng interface

> **For agentic workers:** Đây là tài liệu gốc của bộ kế hoạch ShellX v1.0. Mỗi kế hoạch con (01–06) được thực thi bằng superpowers:subagent-driven-development (khuyến nghị) hoặc superpowers:executing-plans. Mọi kế hoạch con **phải** tuân theo "Global Constraints" và "Hợp đồng interface" dưới đây; tên lớp, chữ ký hàm, khóa lưu trữ và định dạng dây (wire format) ở đây là bắt buộc.

**Goal:** Xây dựng ShellX v1.0 — điều khiển terminal máy tính (macOS/Windows) từ điện thoại qua relay Cloudflare với kênh mã hóa đầu cuối.

**Architecture:** Relay TypeScript (Worker + Durable Object `UserHub` + D1) chỉ chuyển khung đã mã hóa giữa các thiết bị cùng tài khoản. Ba package Dart thuần (`shellx_core`, `shellx_agent`, `shellx_client`) chứa toàn bộ logic giao thức, mã hóa Noise, quản lý phiên; hai app Flutter (desktop, mobile) chỉ là lớp giao diện và adapter nền tảng.

**Tech Stack:** Dart 3.11 / Flutter 3.41 (pub workspaces), `cryptography`, `cbor`, `http`, `flutter_pty`, `xterm`; TypeScript, Hono, Cloudflare Workers/Durable Objects/D1, Vitest + `@cloudflare/vitest-pool-workers`; Astro; GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-25-shellx-v1-design.md`

---

## 1. Bộ kế hoạch và thứ tự thực thi

| # | File | Nội dung | Phụ thuộc |
|---|---|---|---|
| 01 | `2026-09-25-shellx-v1-01-relay.md` | `relay/` — Worker, API, D1, `UserHub`, test | — |
| 02 | `2026-09-25-shellx-v1-02-core.md` | `packages/shellx_core` + gốc Dart workspace | — |
| 03 | `2026-09-25-shellx-v1-03-agent-client.md` | `packages/shellx_agent`, `packages/shellx_client`, `packages/shellx_e2e` | 02 (API), 01 (chỉ cho task E2E) |
| 04 | `2026-09-25-shellx-v1-04-desktop.md` | `apps/desktop` (Flutter macOS/Windows) | 02, 03 |
| 05 | `2026-09-25-shellx-v1-05-mobile.md` | `apps/mobile` (Flutter iOS/Android) | 02, 03 |
| 06 | `2026-09-25-shellx-v1-06-web-ci.md` | `web/` (Astro), `.github/workflows`, script phát hành | — (CI job tham chiếu lệnh test của các plan khác) |

**Đợt thực thi:**
- **Đợt 1 (song song):** 01, 02, 06.
- **Đợt 2:** 03 (task E2E cuối cùng cần relay của 01 chạy được bằng `wrangler dev`).
- **Đợt 3 (song song):** 04, 05.

Mỗi kế hoạch chạy trên một git worktree/nhánh riêng tách từ `feat/shellx-v1` và được merge về `feat/shellx-v1` khi xong. Xung đột duy nhất được dự kiến là danh sách `workspace:` trong `pubspec.yaml` gốc (mỗi plan thêm đúng một dòng cho package của mình) — giải quyết bằng cách giữ tất cả các dòng.

---

## 2. Global Constraints

Giá trị sao chép nguyên văn từ spec; mọi task ngầm định phải thỏa mãn.

- Dart SDK `^3.11.0`; Flutter 3.41 (stable). Node ≥ 22 cho relay và web.
- Nền tảng: macOS 12+, Windows 10 bản 1809+, iOS 15+, Android 8.0 (API 26)+.
- Tên miền: `relay.shellx.pro` (production), `relay-staging.shellx.pro` (staging), `download.shellx.pro` (R2), `shellx.pro` (landing).
- Khung WebSocket tối đa **64 KiB**; tối đa **500 khung/giây** mỗi kết nối.
- Nhịp tim: client gửi văn bản `ping` mỗi **30 s**; không nhận `pong` trong **10 s** thì coi là mất kết nối.
- Kết nối lại: thời gian chờ tăng dần **1 s → tối đa 30 s**, có độ trễ ngẫu nhiên.
- Tối đa **10 phiên** mỗi máy. Bộ đệm vòng **256 KiB** mỗi phiên. Cửa sổ gửi **256 KiB**. Mỗi tin `output` tối đa **16 KiB**. Agent gom tin mỗi **16 ms** (hoặc ngay khi output chờ ≥ 16 KiB). Mobile `ack` khi nhận thêm **≥ 32 KiB** hoặc **100 ms** sau lần nhận cuối.
- Mã ghép nối: **32 byte**, dùng một lần, hết hạn **5 phút**.
- Mật khẩu **8–128** ký tự, argon2id **m = 19 456 KiB, t = 2, p = 1**, lưu dạng chuỗi PHC.
- Token thiết bị: **32 byte** ngẫu nhiên, base64url; D1 lưu SHA-256; hết hạn sau **90 ngày** không dùng; `last_used_at` cập nhật tối đa **1 lần/giờ**.
- Rate limit (chu kỳ 60 s): đăng nhập **10/IP**, **5/email**; đăng ký **3/IP**.
- Khóa app mobile khi mở app và khi quay lại sau **hơn 5 phút** ở nền.
- Mã đóng WebSocket: **4001 replaced**, **4002 revoked**, **4003 rate_limited**.
- Không bao giờ ghi log payload, token hay mật khẩu. Không bao giờ truyền dữ liệu ứng dụng không mã hóa.
- Giao diện song ngữ **tiếng Việt và tiếng Anh**.
- Commit: Conventional Commits (`feat:`, `fix:`, `test:`, `chore:`, `docs:`), mỗi task ít nhất một commit.

---

## 3. Quy ước repo

```
shellx/
  pubspec.yaml                 # Dart pub workspace gốc (plan 02 tạo)
  analysis_options.yaml        # include: package:lints/recommended.yaml (plan 02 tạo)
  packages/shellx_core/        # plan 02
  packages/shellx_agent/       # plan 03
  packages/shellx_client/      # plan 03
  packages/shellx_e2e/         # plan 03 (publish_to: none, chỉ chứa test)
  apps/desktop/                # plan 04
  apps/mobile/                 # plan 05
  relay/                       # plan 01
  web/                         # plan 06
  .github/workflows/           # plan 06
```

`pubspec.yaml` gốc:

```yaml
name: shellx_workspace
publish_to: none
environment:
  sdk: ^3.11.0
workspace:
  - packages/shellx_core
dev_dependencies:
  lints: ^6.0.0
```

Mỗi package/app thành viên có `resolution: workspace` trong pubspec và được thêm vào danh sách `workspace:` bởi plan tạo ra nó.

- Dev dependency cho mọi package Dart thuần: `test: ^1.30.0`, `fake_async: ^1.3.3` (Flutter 3.41.7 ghim `test_api 0.7.10`; `test` mới hơn làm hỏng việc giải phụ thuộc khi app Flutter vào workspace). App Flutter dùng `flutter_test` của SDK.
- `pubspec.lock` nằm trong `.gitignore` trong giai đoạn phát triển song song v1.0 (tránh xung đột merge); sẽ commit lockfile gốc trước khi phát hành.

**Lệnh test chuẩn** (plan 06 dùng trong CI):
- `dart test` trong `packages/shellx_core`, `packages/shellx_agent`, `packages/shellx_client`.
- `dart test` trong `packages/shellx_e2e` (cần relay chạy tại `http://127.0.0.1:8787`, bật bằng biến môi trường `SHELLX_E2E_RELAY=http://127.0.0.1:8787`; không có biến thì các test bị skip).
- `npm test` trong `relay/`.
- `flutter test` trong `apps/desktop` và `apps/mobile`; `flutter test integration_test -d macos|windows` trong `apps/desktop`.
- `npm run build` trong `web/`.

---

## 4. Hợp đồng interface — định dạng dây (relay ↔ client)

Nguồn: spec mục 6 và 10. Relay (TypeScript) và `shellx_core` (Dart) phải cài đặt **byte-for-byte** giống nhau.

### 4.1 Khung relay (khung nhị phân WebSocket)

```
Byte 0 : version = 1
Byte 1 : type
  0x01 DATA      [2..17]  peer device_id (UUID, 16 byte, big-endian như chuỗi hex)
                 [18..25] channel_id (8 byte)
                 [26..]   payload
  0x02 PRESENCE  [2..17]  device_id | [18] 0 = offline, 1 = online
  0x03 ERROR     [2..3]   code (uint16 big-endian) | [4..19] device_id | [20..27] channel_id
  0x04 EVENT     [2..]    CBOR map, khóa và giá trị đều là text string
```

- Mã lỗi: `1 peer_offline`, `2 frame_too_large`, `3 rate_limited`, `4 bad_frame`. ERROR không gắn với peer dùng `device_id` = UUID nil và `channel_id` = 8 byte 0.
- EVENT duy nhất ở v1.0: `{"event": "pairing_removed", "agent_id": "<uuid>", "mobile_id": "<uuid>"}`. Relay tự mã hóa CBOR tối giản (map major type 5, key/value text string major type 3); không dùng thư viện CBOR có "records"/tag mở rộng.
- Khung văn bản: chỉ `ping` (client → hub) và `pong` (hub → client, qua `setWebSocketAutoResponse`).
- UUID trong JSON luôn là chuỗi chữ thường dạng `8-4-4-4-12`.

### 4.2 Payload kênh (bên trong DATA)

```
Byte 0 : kind — 0x01 HS1_IK | 0x02 HS1_IKPSK2 | 0x03 HS2 | 0x04 TRANSPORT
Byte 1.. : Noise message
```

- Noise: `Noise_IK_25519_ChaChaPoly_BLAKE2s` (kết nối thường) và `Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s` (ghép nối). Mobile là initiator, agent là responder.
- Prologue = UTF-8 `"shellx/1"` ‖ 16 byte UUID agent ‖ 16 byte UUID mobile.
- Payload HS1/HS2 và tin nhắn ứng dụng mã hóa bằng CBOR (xem 5.4).

### 4.3 REST API

Đúng như spec mục 10.2 (kể cả `DELETE /v1/account {password}` → `204` / `401 invalid_credentials`, đóng WebSocket mọi thiết bị với 4002). Base URL cấu hình được (production `https://relay.shellx.pro`, dev `http://127.0.0.1:8787`).

**Mã lỗi chung:** token thiếu/sai/hết hạn trên REST → `401 unauthorized`; sai email/mật khẩu → `401 invalid_credentials`; rate limit → `429 rate_limited` (client rẽ nhánh theo status 429). `GET /v1/ws` với token thiếu/sai bị từ chối bằng HTTP 401 **trước** khi nâng cấp WebSocket (client coi như `revoked`). `DELETE /v1/account` đọc body JSON `{"password"}`.

**Giới hạn khung:** 64 KiB tính trên **toàn bộ** khung nhị phân, kể cả header 26 byte của DATA. `shellx_core` export `kMaxSealedBatchBytes = 65493`; `SecureChannel.seal` ném `ArgumentError` nếu batch CBOR vượt mức này, nên agent phải chia output chờ gửi thành nhiều TRANSPORT (tối đa 3 tin `output` 16 KiB mỗi batch).

**Relay dev server (plan 01 sở hữu, plan 03 E2E và plan 06 CI dùng):** trong `relay/`, `npm run dev` phải áp dụng D1 migrations cục bộ trước rồi phục vụ tại `127.0.0.1:8787` (chấp nhận thêm `-- --ip 127.0.0.1 --port 8787`). Môi trường dev đặt biến `RATE_LIMITS_ENABLED = "false"` để tắt mọi rate limit (E2E tạo nhiều tài khoản từ cùng IP); production/staging luôn bật. Cấu hình wrangler dùng file `relay/wrangler.jsonc`; các biến phiên bản là `MIN_AGENT`, `MIN_MOBILE`, `LATEST_AGENT_VERSION`, `MAC_URL`, `WIN_URL`. Lỗi luôn là `{"error": {"code": "<snake_case>", "message": "<text>"}}`. Timestamp trong JSON là số nguyên unix **mili giây** (hoặc `null`).

`GET /v1/devices` trả:

```json
[{"id": "…", "kind": "agent", "name": "MacBook-Pro", "platform": "macos",
  "online": true, "last_seen_at": 1790000000000, "paired_with_me": false}]
```

`GET /v1/version` trả:

```json
{"min_agent": "1.0.0", "min_mobile": "1.0.0",
 "latest_agent": {"version": "1.0.0", "mac_url": "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
                  "win_url": "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe"}}
```

---

## 5. Hợp đồng interface — Dart

Mỗi package export mọi API công khai qua một file duy nhất (`lib/shellx_core.dart`, `lib/shellx_agent.dart`, `lib/shellx_client.dart`). Cài đặt đặt trong `lib/src/…`. Chữ ký dưới đây là bắt buộc; được thêm thành viên private/hàm phụ trợ, không được đổi tên hay kiểu.

### 5.1 `shellx_core` — tiện ích và khung relay

```dart
// lib/src/util/bytes.dart
const String nilUuid = '00000000-0000-0000-0000-000000000000';
Uint8List uuidToBytes(String uuid);              // FormatException nếu sai định dạng
String uuidFromBytes(Uint8List bytes);            // 16 byte → chuỗi chữ thường 8-4-4-4-12
String base64UrlNoPad(Uint8List bytes);
Uint8List fromBase64UrlNoPad(String input);       // FormatException nếu sai
bool constantTimeEquals(Uint8List a, Uint8List b);

// lib/src/relay/channel_id.dart
final class ChannelId {
  ChannelId(Uint8List bytes);                     // ArgumentError nếu length != 8
  factory ChannelId.random([Random? random]);     // mặc định Random.secure()
  static final ChannelId zero;
  final Uint8List bytes;
  // == và hashCode theo nội dung; toString() = hex 16 ký tự
}

// lib/src/relay/frames.dart
const int kRelayProtocolVersion = 1;
const int kMaxFrameBytes = 64 * 1024;
abstract final class RelayCloseCode {
  static const int replaced = 4001;
  static const int revoked = 4002;
  static const int rateLimited = 4003;
}
enum RelayErrorCode {
  peerOffline(1), frameTooLarge(2), rateLimited(3), badFrame(4);
  const RelayErrorCode(this.wire);
  final int wire;
  static RelayErrorCode fromWire(int wire);       // FrameFormatException nếu không biết
}
final class FrameFormatException implements Exception {
  const FrameFormatException(this.message);
  final String message;
}
sealed class RelayFrame {
  const RelayFrame();
  Uint8List encode();
  static RelayFrame decode(Uint8List bytes);      // FrameFormatException nếu hỏng/không biết type
}
final class DataFrame extends RelayFrame {
  DataFrame({required this.peer, required this.channel, required this.payload});
  final String peer; final ChannelId channel; final Uint8List payload;
}
final class PresenceFrame extends RelayFrame {
  const PresenceFrame({required this.deviceId, required this.online});
  final String deviceId; final bool online;
}
final class ErrorFrame extends RelayFrame {
  ErrorFrame({required this.code, this.deviceId = nilUuid, ChannelId? channel});
  final RelayErrorCode code; final String deviceId; final ChannelId channel;
}
final class EventFrame extends RelayFrame {
  const EventFrame(this.event);
  final Map<String, String> event;
}
```

### 5.2 `shellx_core` — Noise

```dart
// lib/src/noise/…
final class NoiseKeyPair {
  NoiseKeyPair({required this.privateKey, required this.publicKey});
  final Uint8List privateKey;   // 32 byte X25519
  final Uint8List publicKey;    // 32 byte
  static Future<NoiseKeyPair> generate();
  static Future<NoiseKeyPair> fromPrivateKey(Uint8List privateKey);
}
enum NoisePattern { ik, ikPsk2 }  // 'Noise_IK_25519_ChaChaPoly_BLAKE2s' / 'Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s'
final class NoiseException implements Exception {
  const NoiseException(this.message);
  final String message;
}
final class NoiseHandshake {
  NoiseHandshake.initiator({required NoisePattern pattern, required NoiseKeyPair localStatic,
      required Uint8List remoteStatic, required Uint8List prologue, Uint8List? psk, NoiseKeyPair? ephemeral});
  NoiseHandshake.responder({required NoisePattern pattern, required NoiseKeyPair localStatic,
      required Uint8List prologue, Uint8List? psk, NoiseKeyPair? ephemeral});
  // psk bắt buộc (32 byte) khi pattern == ikPsk2, cấm khi ik → ArgumentError.
  // ephemeral chỉ dùng cho test vector.
  Future<Uint8List> writeMessage([Uint8List? payload]);
  Future<Uint8List> readMessage(Uint8List message);   // trả payload đã giải mã; NoiseException nếu lỗi
  bool get isComplete;
  Uint8List? get remoteStatic;                        // responder có sau khi đọc message 1
  Uint8List get handshakeHash;
  NoiseTransport split();                             // StateError nếu chưa complete
}
final class NoiseTransport {
  Future<Uint8List> encrypt(Uint8List plaintext);     // plaintext ≤ 65519 byte
  Future<Uint8List> decrypt(Uint8List ciphertext);    // NoiseException nếu xác thực thất bại
}
```

### 5.3 `shellx_core` — payload kênh, kênh bảo mật, URI ghép nối

```dart
// lib/src/channel/payload.dart
enum PayloadKind {
  hs1Ik(0x01), hs1IkPsk2(0x02), hs2(0x03), transport(0x04);
  const PayloadKind(this.wire);
  final int wire;
}
final class ChannelPayload {
  ChannelPayload(this.kind, this.noiseMessage);
  final PayloadKind kind; final Uint8List noiseMessage;
  Uint8List encode();
  static ChannelPayload decode(Uint8List bytes);     // FrameFormatException
}
Uint8List buildPrologue({required String agentDeviceId, required String mobileDeviceId});

// lib/src/channel/secure_channel.dart
const int kMaxOutputChunk = 16 * 1024;
final class SecureChannel {
  SecureChannel(NoiseTransport transport);
  Future<Uint8List> seal(List<AppMessage> messages); // trả ChannelPayload(transport, ciphertext).encode()
  Future<List<AppMessage>> open(Uint8List noiseMessage); // NoiseException / FormatException
}

// lib/src/pairing/pairing_uri.dart
// Định dạng: shellx://pair?v=1&d=<uuid>&k=<base64url 32 byte>&s=<base64url 32 byte>
final class PairingUri {
  PairingUri({required this.agentDeviceId, required this.agentPublicKey, required this.secret});
  final String agentDeviceId; final Uint8List agentPublicKey; final Uint8List secret;
  String toUriString();
  static PairingUri parse(String input);             // FormatException
}
```

### 5.4 `shellx_core` — tin nhắn

```dart
// lib/src/protocol/handshake_payloads.dart
const int kAppProtocolVersion = 1;
enum DevicePlatform { macos, windows, ios, android }          // wire = name
enum DeviceKind { agent, mobile }                              // wire = name
enum HandshakeStatus {
  ok('ok'), untrusted('untrusted'), pairingInvalid('pairing_invalid'), protoUnsupported('proto_unsupported');
  const HandshakeStatus(this.wire); final String wire;
}
final class Hs1Payload {    // CBOR {proto, app, name, platform}
  Hs1Payload({required this.proto, required this.app, required this.name, required this.platform});
  final int proto; final String app; final String name; final DevicePlatform platform;
  Uint8List encode(); static Hs1Payload decode(Uint8List bytes);   // FormatException
}
final class Hs2Payload {    // CBOR {proto, app, status}
  Hs2Payload({required this.proto, required this.app, required this.status});
  final int proto; final String app; final HandshakeStatus status;
  Uint8List encode(); static Hs2Payload decode(Uint8List bytes);
}

// lib/src/protocol/messages.dart
// Khóa CBOR: "t" + snake_case: id, index, shell, created_at, attached, sessions, cols, rows,
// last_seq, seq, data (byte string), exit_code, reason, code, message.
sealed class AppMessage {
  const AppMessage();
  String get type;                                    // giá trị "t"
  Map<String, Object?> toMap();
  static AppMessage? fromMap(Map<Object?, Object?> map); // null nếu "t" không biết; FormatException nếu thiếu trường
}
final class PairConfirm extends AppMessage { const PairConfirm(); }                       // pair.confirm
final class SessionList extends AppMessage { const SessionList(); }                       // session.list
final class SessionInfo {
  const SessionInfo({required this.id, required this.index, required this.shell,
      required this.createdAt, required this.attached});
  final int id; final int index; final String shell; final int createdAt; final bool attached;
}
final class SessionListResult extends AppMessage { const SessionListResult(this.sessions); final List<SessionInfo> sessions; }
final class SessionOpen extends AppMessage { const SessionOpen({required this.cols, required this.rows}); final int cols, rows; }
final class SessionOpened extends AppMessage { const SessionOpened({required this.id, required this.index, required this.shell}); final int id, index; final String shell; }
final class SessionAttach extends AppMessage { const SessionAttach({required this.id, required this.cols, required this.rows, required this.lastSeq}); final int id, cols, rows, lastSeq; }
final class SessionAttached extends AppMessage { const SessionAttached({required this.id}); final int id; }
final class SessionReset extends AppMessage { const SessionReset({required this.id}); final int id; }
final class OutputMessage extends AppMessage { const OutputMessage({required this.id, required this.seq, required this.data}); final int id, seq; final Uint8List data; }  // t = "output"
final class AckMessage extends AppMessage { const AckMessage({required this.id, required this.seq}); final int id, seq; }                                                   // t = "ack"
final class InputMessage extends AppMessage { const InputMessage({required this.id, required this.data}); final int id; final Uint8List data; }                             // t = "input"
final class ResizeMessage extends AppMessage { const ResizeMessage({required this.id, required this.cols, required this.rows}); final int id, cols, rows; }                  // t = "resize"
final class SessionClose extends AppMessage { const SessionClose({required this.id}); final int id; }
final class SessionExited extends AppMessage { const SessionExited({required this.id, required this.exitCode}); final int id, exitCode; }
enum DetachReason { takenOver('taken_over'), closedByHost('closed_by_host'); const DetachReason(this.wire); final String wire; }
final class SessionDetached extends AppMessage { const SessionDetached({required this.id, required this.reason}); final int id; final DetachReason reason; }
enum AppErrorCode { sessionLimit('session_limit'), sessionNotFound('session_not_found'), spawnFailed('spawn_failed'); const AppErrorCode(this.wire); final String wire; }
final class ErrorMessage extends AppMessage { const ErrorMessage({required this.code, required this.message, this.id}); final AppErrorCode code; final String message; final int? id; }  // t = "error"

Uint8List encodeBatch(List<AppMessage> messages);    // CBOR array of maps
List<AppMessage> decodeBatch(Uint8List bytes);        // bỏ qua tin có "t" không biết; FormatException nếu không phải array
```

### 5.5 `shellx_core` — lưu trữ, định danh, REST, kết nối relay

```dart
// lib/src/storage/key_value_store.dart
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}
final class InMemoryKeyValueStore implements KeyValueStore { /* Map<String,String> */ }

// lib/src/identity/device_identity.dart
abstract final class DeviceIdentity {
  static const String storageKey = 'device_private_key';     // base64url khóa bí mật
  static Future<NoiseKeyPair> loadOrCreate(KeyValueStore store);
}
// BẮT BUỘC (plan 04/05): mỗi app dùng MỘT instance KeyValueStore dùng chung cho cả tiến trình
// (ví dụ một Riverpod provider duy nhất ở desktop, một @lazySingleton get_it ở mobile). Bảo đảm "chỉ sinh một khóa khi gọi đồng thời" chỉ đúng
// với các lời gọi trên cùng một instance.

// lib/src/api/…
final class DeviceInfo {
  DeviceInfo({required this.kind, required this.name, required this.platform, required this.publicKey});
  final DeviceKind kind; final String name; final DevicePlatform platform; final Uint8List publicKey;
  Map<String, Object?> toJson();    // {"kind","name","platform","public_key"(base64url)}
}
final class AuthResult { const AuthResult({required this.userId, required this.deviceId, required this.token}); final String userId, deviceId, token; }
final class RemoteDevice {
  const RemoteDevice({required this.id, required this.kind, required this.name, required this.platform,
      required this.online, required this.lastSeenAt, required this.pairedWithMe});
  final String id; final DeviceKind kind; final String name; final DevicePlatform platform;
  final bool online; final DateTime? lastSeenAt; final bool pairedWithMe;
}
final class LatestAgent { const LatestAgent({required this.version, required this.macUrl, required this.winUrl}); final String version; final Uri macUrl, winUrl; }
final class VersionInfo { const VersionInfo({required this.minAgent, required this.minMobile, required this.latestAgent}); final String minAgent, minMobile; final LatestAgent latestAgent; }
final class ApiException implements Exception {
  const ApiException({required this.status, required this.code, required this.message});
  final int status; final String code; final String message;   // status 0 + code "network" khi lỗi mạng
}
final class ShellxApi {
  ShellxApi({required Uri baseUri, http.Client? httpClient});
  String? token;
  Future<AuthResult> register(String email, String password, DeviceInfo device);
  Future<AuthResult> login(String email, String password, DeviceInfo device);
  Future<void> logout();
  Future<void> changePassword(String newPassword);
  Future<void> deleteAccount(String password);   // DELETE /v1/account
  Future<List<RemoteDevice>> devices();
  Future<void> createPairing(String mobileId);
  Future<void> deletePairing(String agentId, String mobileId);
  Future<VersionInfo> version();
}
int compareVersions(String a, String b);   // semver "x.y.z": âm/0/dương

// lib/src/relay/relay_connection.dart
abstract interface class RelaySocket {
  Stream<Object> get messages;          // String (khung văn bản) hoặc Uint8List (khung nhị phân)
  void sendText(String text);
  void sendBytes(Uint8List bytes);
  Future<void> close([int? code, String? reason]);
  int? get closeCode;                   // có giá trị sau khi stream messages kết thúc
}
typedef RelaySocketConnector = Future<RelaySocket> Function(Uri uri, Map<String, String> headers);
Future<RelaySocket> ioRelaySocketConnector(Uri uri, Map<String, String> headers);   // dart:io WebSocket

final class Backoff {
  Backoff({Duration initial = const Duration(seconds: 1), Duration max = const Duration(seconds: 30), Random? random});
  Duration next();   // base = min(max, initial * 2^attempt); trả base/2 + random(0..base/2)
  void reset();
}
enum RelayConnectionState { disconnected, connecting, connected, revoked, replaced, stopped }
final class RelayConnection {
  RelayConnection({required Uri wsUri, required String? Function() token,
      RelaySocketConnector connector = ioRelaySocketConnector, Backoff? backoff,
      Duration pingInterval = const Duration(seconds: 30), Duration pongTimeout = const Duration(seconds: 10)});
  RelayConnectionState get state;
  Stream<RelayConnectionState> get states;   // broadcast
  Stream<RelayFrame> get frames;             // broadcast; khung hỏng bị bỏ qua
  void start();
  Future<void> stop();                       // → stopped, không kết nối lại
  bool send(RelayFrame frame);               // false nếu chưa connected
  void reconnectNow();                       // bỏ qua backoff (mobile quay lại foreground)
}
// Đóng với 4002 → revoked, 4001 → replaced: KHÔNG tự kết nối lại. Mã khác → kết nối lại theo Backoff.
```

### 5.6 `shellx_agent`

```dart
abstract interface class Pty {
  Stream<Uint8List> get output;
  Future<int> get exitCode;
  void write(Uint8List data);
  void resize(int cols, int rows);
  void kill();                               // kết thúc cả cây tiến trình
}
final class ShellCommand {
  const ShellCommand({required this.executable, required this.arguments, required this.name});
  final String executable; final List<String> arguments; final String name;   // name ví dụ "zsh", "pwsh"
}
abstract interface class PtyFactory {
  Pty spawn(ShellCommand command, {required String workingDirectory,
      required Map<String, String> environment, required int cols, required int rows});
}
abstract interface class ShellResolver { Future<ShellCommand> resolve(); }
typedef ProcessRunner = Future<ProcessResult> Function(String executable, List<String> arguments);
final class PlatformShellResolver implements ShellResolver {
  PlatformShellResolver({required String operatingSystem, required Map<String, String> environment,
      ProcessRunner? run, Future<bool> Function(String executable)? isOnPath});
}
final class ProcessPtyFactory implements PtyFactory { const ProcessPtyFactory(); }   // dart:io Process, không TTY; dùng cho E2E
Map<String, String> buildSessionEnvironment(Map<String, String> base);  // TERM, COLORTERM, LANG mặc định, SHELLX=1

final class RingBuffer {
  RingBuffer(int capacity);
  int get start; int get end;
  void append(Uint8List data);
  Uint8List read(int from, int maxBytes);   // yêu cầu start <= from <= end
}

final class OutboundMessage { const OutboundMessage(this.mobileId, this.message); final String mobileId; final AppMessage message; }
final class SessionSummary {
  const SessionSummary({required this.id, required this.index, required this.shell,
      required this.createdAt, required this.attachedMobileId});
  final int id, index; final String shell; final DateTime createdAt; final String? attachedMobileId;
}
final class SessionOpenedEvent { const SessionOpenedEvent(this.mobileId, this.sessionId); final String mobileId; final int sessionId; }
final class SessionManager {
  SessionManager({required PtyFactory ptyFactory, required ShellResolver shellResolver,
      required String homeDirectory, required Map<String, String> baseEnvironment,
      int maxSessions = 10, int bufferCapacity = 256 * 1024, int sendWindow = 256 * 1024});
  Stream<OutboundMessage> get outbound;      // đồng bộ (sync broadcast), giữ thứ tự
  Future<void> handle(String mobileId, AppMessage message);
  void mobileDisconnected(String mobileId);  // phiên đang gắn → không gắn
  void closeSessionsAttachedTo(String mobileId);
  void closeSession(int id);                 // đóng từ tray: SessionDetached(closedByHost) + SessionExited
  void closeAll();
  List<SessionSummary> get sessions;
  Stream<void> get changes;
  Stream<SessionOpenedEvent> get opened;
}
// cols/rows nhận từ mobile được kẹp vào [1, 1000].

final class TrustedDevice {
  TrustedDevice({required this.mobileId, required Uint8List publicKey, required this.name, required this.pairedAt}); // copies publicKey (not const)
  final String mobileId; final Uint8List publicKey; final String name; final DateTime pairedAt;
  Map<String, Object?> toJson(); static TrustedDevice fromJson(Map<String, Object?> json);
}
final class TrustedStore {
  TrustedStore(KeyValueStore store);
  static const String storageKey = 'trusted_devices';    // JSON array
  Future<List<TrustedDevice>> list();
  Future<TrustedDevice?> find(String mobileId);
  Future<void> add(TrustedDevice device);                // thay thế nếu trùng mobileId
  Future<void> remove(String mobileId);
  Future<void> clear();
  Stream<void> get changes;
}
final class PairingOffer { const PairingOffer({required this.secret, required this.expiresAt}); final Uint8List secret; final DateTime expiresAt; }
final class PairingCodeManager {
  PairingCodeManager({DateTime Function()? now, Random? random});
  PairingOffer create({Duration ttl = const Duration(minutes: 5)});   // thay mã cũ
  Uint8List? get activeSecret;                                         // null nếu không có/hết hạn
  void invalidate();
}

sealed class AgentEvent { const AgentEvent(); }
final class MobilePaired extends AgentEvent { const MobilePaired(this.device); final TrustedDevice device; }
final class SessionOpenedByMobile extends AgentEvent { const SessionOpenedByMobile({required this.mobileName, required this.sessionId}); final String mobileName; final int sessionId; }
final class ActiveChannelsChanged extends AgentEvent { const ActiveChannelsChanged(this.count); final int count; }
final class AgentRevoked extends AgentEvent { const AgentRevoked(); }   // relay → revoked (4002 hoặc 401 khi kết nối)
// AgentService.start()/stop() chỉ bật/tắt kết nối relay, KHÔNG đóng phiên: app phải gọi sessions.closeAll()
// khi tắt truy cập từ xa, đăng xuất, AgentRevoked và thoát.
// SessionManager nhận thêm `Random? random`; id phiên đầu tiên ngẫu nhiên trong [1, 2^31) rồi tăng dần.
// Pty.output phải đóng khi tiến trình kết thúc.
final class AgentService {
  AgentService({required RelayConnection relay, required ShellxApi api, required String deviceId,
      required NoiseKeyPair identity, required TrustedStore trusted, required SessionManager sessions,
      required PairingCodeManager pairing, required String appVersion,
      Duration flushInterval = const Duration(milliseconds: 16)});
  Future<void> start();
  Future<void> stop();
  Stream<AgentEvent> get events;
  int get activeChannelCount;
  PairingUri startPairing();
  void cancelPairing();
  Future<void> revoke(String mobileId);
}
```

### 5.7 `shellx_client`

```dart
final class PinnedMachine {
  const PinnedMachine({required this.agentId, required this.publicKey, required this.pairedAt});
  final String agentId; final Uint8List publicKey; final DateTime pairedAt;
  Map<String, Object?> toJson(); static PinnedMachine fromJson(Map<String, Object?> json);
}
final class PinnedStore {
  PinnedStore(KeyValueStore store, {required String userId});   // khóa 'pinned_machines_<userId>'
  Future<List<PinnedMachine>> list();
  Future<PinnedMachine?> find(String agentId);
  Future<void> add(PinnedMachine machine);
  Future<void> remove(String agentId);
}

enum PairingFailure { notInAccount, invalidOrExpired, agentOffline, protocolUnsupported, timeout }
final class PairingException implements Exception { const PairingException(this.failure); final PairingFailure failure; }
enum MachineConnectionFailure { untrusted, protocolUnsupported, agentOffline, timeout }
sealed class MachineConnectionState { const MachineConnectionState(); }
final class MachineIdle extends MachineConnectionState { const MachineIdle(); }
final class MachineConnecting extends MachineConnectionState { const MachineConnecting(); }
final class MachineReady extends MachineConnectionState { const MachineReady(); }
final class MachineFailed extends MachineConnectionState { const MachineFailed(this.failure); final MachineConnectionFailure failure; }
final class AppErrorException implements Exception { const AppErrorException(this.code, this.message); final AppErrorCode code; final String message; }
final class MachineConnectionException implements Exception { const MachineConnectionException(this.failure); final MachineConnectionFailure failure; }
// MachineClient.connect() và các request khi kênh mất ném MachineConnectionException.
// ClientService.start()/stop() tự start/stop RelayConnection; gọi lại start() sau stop() được (mobile dùng khi vào/ra foreground).

sealed class TabEvent { const TabEvent(); }
final class TabOutput extends TabEvent { const TabOutput(this.text); final String text; }  // đã giải mã UTF-8 dạng luồng
final class TabReset extends TabEvent { const TabReset(); }
final class TabExited extends TabEvent { const TabExited(this.exitCode); final int exitCode; }
final class TabDetached extends TabEvent { const TabDetached(this.reason); final DetachReason reason; }
final class TabError extends TabEvent { const TabError(this.code, this.message); final AppErrorCode code; final String message; }
final class ClientTab {
  int get id; int get index; String get shell;
  int get received;                // tổng byte output đã nhận (last_seq khi gắn lại)
  bool get isAttached;             // false sau TabDetached/TabExited
  Stream<TabEvent> get events;     // broadcast
}
final class MachineClient {
  String get agentId;
  MachineConnectionState get state;
  Stream<MachineConnectionState> get states;
  Future<void> connect();                                             // bắt tay IK; ném theo MachineFailed
  Future<List<SessionInfo>> listSessions();
  Future<ClientTab> openSession({required int cols, required int rows}); // AppErrorException
  Future<ClientTab> attach(int id, {required int cols, required int rows});
  List<ClientTab> get tabs;
  void input(int id, Uint8List data);                                 // cắt > 16 KiB
  void resize(int id, int cols, int rows);                            // bỏ qua nếu cols < 1 hoặc rows < 1
  Future<void> closeTab(int id);
  // Khi kết nối relay phục hồi: tự bắt tay lại và gắn lại mọi tab isAttached == true với lastSeq = received.
}
final class ClientService {
  ClientService({required RelayConnection relay, required ShellxApi api, required String deviceId,
      required String userId, required NoiseKeyPair identity, required PinnedStore pinned,
      required String appVersion, required String deviceName, required DevicePlatform platform,
      Duration handshakeTimeout = const Duration(seconds: 10)});
  Future<void> start();
  Future<void> stop();
  bool isOnline(String agentId);
  Stream<PresenceFrame> get presence;
  Future<void> pair(PairingUri uri);          // PairingException
  MachineClient machine(String agentId);      // StateError nếu chưa ghim; cùng agentId trả cùng instance
  Future<void> unpair(String agentId);
}
```

---

## 6. Review Focus (toàn bộ dự án)

Năm loại đầu vào/tình huống spec ngụ ý nhưng dễ bị bỏ sót, xếp theo khả năng gây lỗi cho người dùng. Plan sở hữu phải có test cho dòng tương ứng.

1. **Ký tự UTF-8 nhiều byte (tiếng Việt, emoji) bị cắt ngang ranh giới giữa hai tin `output`** — người dùng mong thấy chữ đúng, không có ký tự `�` giữa dòng. Chủ sở hữu: plan 03 (`ClientTab` giải mã UTF-8 dạng luồng, tạo bộ giải mã mới khi `session.reset`).
2. **Tab bị thiết bị khác chiếm (`taken_over`) không được tự gắn lại khi kết nối phục hồi** — nếu không, điện thoại và máy tính bảng giành phiên qua lại vô hạn. Chủ sở hữu: plan 03.
3. **`session.attach` với `last_seq` lớn hơn `end`, hoặc `id` không tồn tại (agent đã khởi động lại)** — agent trả `session.reset` (trường hợp thứ nhất) hoặc `error session_not_found` (trường hợp thứ hai); client đóng tab với thông báo "Phiên đã kết thúc". Chủ sở hữu: plan 03 (agent + client), plan 05 (thông báo UI).
4. **Kích thước terminal bằng 0 hoặc cực lớn** (bàn phím đang trượt, xoay màn hình) — agent kẹp vào [1, 1000], client không gửi khi cols/rows < 1. Chủ sở hữu: plan 03, plan 05.
5. **Email có khoảng trắng/chữ hoa, domain con của domain email tạm (`x.yopmail.com`), đăng nhập bằng email khác chữ hoa** — chuẩn hóa để cùng một tài khoản; domain con vẫn bị chặn. Chủ sở hữu: plan 01.
