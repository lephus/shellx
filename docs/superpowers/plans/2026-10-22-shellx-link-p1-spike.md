# ShellX Link P1: package, giao thức và spike duyệt quyền

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Một client thử (`shellx-link-probe`) kết nối tới ShellX trên Mac qua relay bằng giao thức riêng ShellX Link, thấy các yêu cầu xin quyền của Claude Code đang chờ, và duyệt được một yêu cầu trong < 500 ms (p95 round trip).

**Architecture:** Swift package mới `shellx-link/` (giấy phép MIT, code ShellX tự viết, sau này app iOS dùng lại) gồm bốn target:
- Noise `XX_25519_ChaChaPoly_SHA256` dựng trên CryptoKit;
- bộ mã hoá frame JSON;
- client relay nói giao thức điều khiển của `cmux-relay`;
- lớp phiên host/client.

Mac đăng ký thêm một `link_slot` trên relay v2. ShellX app nối lớp host vào `FeedCoordinator`. Terminal không nằm trong P1.

**Tech Stack:**
- Swift 6.0 (swift-tools 6.0, macOS 14 / iOS 17), CryptoKit, `URLSessionWebSocketTask`;
- Rust `snow` (chỉ để sinh test vector);
- TypeScript Hono + vitest (relay);
- Rust `shellx-core`.

**Spec:** `docs/superpowers/specs/2026-10-22-shellx-ios-agent-remote-design.md` (§7.1, §7.2, §7.4, §7.6)

## Global Constraints

- `shellx-link/` không phụ thuộc vào bất kỳ đường dẫn nào ngoài chính nó. Không chép code từ `ios/`, `Packages/iOS/`, `Packages/Shared/`, `cmux-tui/` (spec §7.1). Đọc để hiểu giao thức thì được.
- `shellx-link/LICENSE` là MIT, chủ bản quyền ShellX. Đây là quyết định của người viết plan, người dùng có thể đổi.
- Code liên kết vào app (`Sources/`, `Packages/`, `shellx-link/`) phải tương thích Swift 6.0 (`skills/cmux-architecture/references/swift-6-0-compatibility.md`).
- Không có dịch vụ Manaflow nào. Relay là `relay.shellx.pro` (Node) cộng `cmux-relay` (đường `/v2/relay`).
- Mục tiêu độ trễ: bấm Cho phép tới hook nhận quyết định < 500 ms p95. Trạng thái đổi trên Mac tới client < 1 s (spec §7.4).
- Mọi quyết định trả lời đều idempotent. Trả lời một yêu cầu đã xử lý thì nhận `already_handled`, không resolve lần hai (spec A1).
- Build và chạy app theo CLAUDE.md: chỉ dùng tagged build (`CMUX_DEV_BACKEND_MODE=local`, tag `link`), không đụng ShellX/cmux đang chạy của người dùng, không chạy `xcodebuild` trần.
- Không push, không deploy relay khi chưa hỏi người dùng.

## Review Focus

1. **Mac mất kết nối relay giữa chừng** (Wi-Fi rớt, ShellX bị tắt rồi mở lại): client kết nối lại phải nhận snapshot mới, không giữ item cũ. Test ở Task 5 (`testReconnectGetsFreshSnapshot`).
2. **Mac duyệt trước, client duyệt sau** cùng một yêu cầu: client nhận `already_handled`, hook không bị resolve lần hai. Test ở Task 7 (`testReplyAfterMacResolvedIsAlreadyHandled`).
3. **Hai client cùng kết nối:** cả hai nhận `agent.changed`. Một client duyệt thì client kia thấy item đó trong `resolved`. Test ở Task 5 (`testTwoClientsSeeResolution`).
4. **Tool input rất lớn** (ví dụ Write một file 2 MB): preview bị cắt còn 8 KiB, frame vẫn dưới giới hạn. Test ở Task 3 (`testOversizeFrameRejected`) và Task 7 (`testToolInputPreviewTruncated`).
5. **Vé relay hết hạn sau 120 s** trong lúc host chạy lâu: mỗi lần đăng ký lại, host lấy vé mới qua provider. Test ở Task 4 (`testReRegisterAsksForFreshTicket`).

---

### Task 1: Khung package `shellx-link`, ranh giới giấy phép, ledger

**Files:**
- Create: `shellx-link/Package.swift`, `shellx-link/LICENSE`, `shellx-link/README.md`
- Create: `shellx-link/Sources/ShellXLinkCore/ShellXLink.swift` (chỉ có `public enum ShellXLink { public static let protocolVersion = 1 }`)
- Create: `scripts/shellx/check-link-license.sh`
- Create: `shellx-link/Tests/ShellXLinkCoreTests/PackageBoundaryTests.swift`
- Create: `docs/superpowers/ledgers/shellx-ios.md`

**Interfaces:**
- Produces:
  - Các target `ShellXLinkCore` (thuần, không I/O), `ShellXLinkRelay` (phụ thuộc Core), `ShellXLinkSession` (phụ thuộc Core + Relay);
  - executable `shellx-link-probe` (phụ thuộc Session);
  - platforms `.macOS(.v14), .iOS(.v17)`, `swiftLanguageModes: [.v6]`.

- [ ] **Step 1: Viết script kiểm tra ranh giới** `scripts/shellx/check-link-license.sh`. Script thoát mã 1 và in đường dẫn vi phạm khi gặp một trong ba trường hợp:
  - `shellx-link/Package.swift` có `path:` hoặc `.package(path:` trỏ ra ngoài `shellx-link/`;
  - có `.package(url:` (P1 không cho dùng dependency bên ngoài);
  - có file trong `shellx-link/Sources` chứa chuỗi `Manaflow`.
- [ ] **Step 2: Viết test fail** `PackageBoundaryTests.testBoundaryScriptPasses`. Test chạy script (đường dẫn tính từ `#filePath`) và assert exit code 0. Chạy `swift test --package-path shellx-link`. Kỳ vọng FAIL, vì package chưa build được hoặc script chưa có.
- [ ] **Step 3: Tạo `Package.swift`, `LICENSE` (MIT, "Copyright (c) 2026 ShellX"), README** (một đoạn: mục đích, giấy phép, quy tắc không chép code GPL).
- [ ] **Step 4: Chạy lại test.** Chạy `swift test --package-path shellx-link`. Kỳ vọng PASS. Thử thêm tạm `.package(path: "../Packages/Shared/ShellXBrand")` thì script phải báo lỗi. Bỏ dòng đó đi.
- [ ] **Step 5: Ghi ledger** `docs/superpowers/ledgers/shellx-ios.md` với các mục:
  - "Giấy phép (2026-10-22)":
    - `cmux-tui/Cargo.toml:60` ghi `license = "MIT"`, nhưng không có file LICENSE nào. `LICENSE` ở gốc (Manaflow GPL) nói cmux-tui theo "license that this file or their own notices state", tức là đang **mơ hồ**, phải hỏi Manaflow;
    - `ghostty/LICENSE` là MIT;
    - `shellx-core` là GPL-3.0-or-later. Tác giả: Phu.le và "Richard". Không thấy code chép từ Manaflow. Người dùng phải xác nhận "Richard" là ai trước khi nhúng `shellx-core` vào app App Store.
  - "D-iOS-0":
    - ShellX Link dùng phiên Noise riêng trên `link_slot`. Lý do: `Service` enum đóng (`cmux-remote-protocol/src/rpc.rs:120`); đăng ký lần hai trên cùng slot sẽ thay daemon (`cmux-relay/src/relay.rs:684-730`).
- [ ] **Step 6: Commit**

```bash
git add shellx-link scripts/shellx/check-link-license.sh docs/superpowers/ledgers/shellx-ios.md
git commit -m "feat(shellx-link): MIT package skeleton with a license boundary check"
```

### Task 2: Noise XX trên CryptoKit, kiểm bằng vector sinh từ `snow`

**Files:**
- Create: `shellx-link/vectors/gen/Cargo.toml`, `shellx-link/vectors/gen/src/main.rs` (crate Rust riêng, không thuộc workspace nào)
- Create: `shellx-link/vectors/noise_xx.json`
- Create: `shellx-link/Sources/ShellXLinkCore/Noise/NoiseHandshake.swift`, `NoiseCipherState.swift`, `NoiseKeys.swift`
- Test: `shellx-link/Tests/ShellXLinkCoreTests/NoiseTests.swift`

**Interfaces:**
- Produces:

```swift
public struct NoiseStaticKey: Sendable { public init(); public init(rawPrivate: Data) throws
  public var publicKey: Data { get }; public var rawPrivate: Data { get } }   // Curve25519, 32 bytes
public enum NoiseRole: Sendable { case initiator, responder }
public enum NoiseError: Error, Equatable { case untrustedPeer, decryptFailed, badMessage, nonceExhausted }
public struct NoiseHandshake {
  public static let protocolName = "Noise_XX_25519_ChaChaPoly_SHA256"
  public static let prologue = Data("shellx-link/1".utf8)
  public init(role: NoiseRole, local: NoiseStaticKey, trusts: @escaping @Sendable (Data) -> Bool,
              ephemeralForTesting: NoiseStaticKey? = nil)
  public mutating func writeMessage(payload: Data) throws -> Data
  public mutating func readMessage(_ message: Data) throws -> Data      // returns payload
  public var isComplete: Bool { get }
  public mutating func split() throws -> NoiseTransport                  // after message 3
  public var remoteStatic: Data? { get }
}
public struct NoiseTransport: Sendable {
  public mutating func encrypt(_ plaintext: Data) throws -> Data         // ≤ 65535 bytes ciphertext
  public mutating func decrypt(_ ciphertext: Data) throws -> Data
}
```

- [ ] **Step 1: Viết bộ sinh vector.**
  - Bộ sinh dùng `snow` (khoá phiên bản bằng `Cargo.lock`, cùng phiên bản `cmux-tui` đang dùng) và `fixed_ephemeral_key_for_testing_only`.
  - Nó in ra `noise_xx.json` gồm: các khoá cố định của initiator và responder (static + ephemeral, hex), prologue `shellx-link/1`, payload của 3 tin handshake (`""`, `"hello-r"`, `"hello-i"`), ciphertext từng tin, và hai tin transport mỗi chiều (`"ping"` và `"pong"`) cùng ciphertext của chúng.
  - Chạy `cargo run --manifest-path shellx-link/vectors/gen/Cargo.toml > shellx-link/vectors/noise_xx.json`. Commit cả file JSON, để CI Swift không cần Rust.
- [ ] **Step 2: Viết test fail** trong `NoiseTests`:
  - `testMatchesSnowVectors`: dựng hai đầu với khoá trong vector, so từng ciphertext byte-đúng-byte, rồi giải mã transport ra `"ping"` / `"pong"`.
  - `testHandshakeRoundTripRandomKeys`: kết thúc có `remoteStatic` bằng public key của đầu kia.
  - `testUntrustedPeerRejected`: `trusts` trả `false` thì `readMessage` ở tin 2 (phía initiator) hoặc tin 3 (phía responder) ném `.untrustedPeer`.
  - `testTamperedCiphertextFails`: lật 1 bit thì ném `.decryptFailed`.
  - `testNonceIncrementsLittleEndianCounter`: hai lần mã hoá cùng plaintext cho ra hai ciphertext khác nhau, và giải mã đúng thứ tự.
- [ ] **Step 3: Chạy** `swift test --package-path shellx-link --filter NoiseTests`. Kỳ vọng FAIL (chưa có kiểu).
- [ ] **Step 4: Cài đặt theo Noise spec rev 34 §5.**
  - Nonce ChaChaPoly là 4 byte 0 cộng counter 8 byte **little-endian** (CryptoKit nhận nonce 12 byte).
  - HKDF dùng HMAC-SHA256 theo §4.3, không dùng `HKDF` của CryptoKit vì khác cách chia output.
  - DH dùng `Curve25519.KeyAgreement`.
  - Kiểm tra `trusts(remoteStatic)` ngay khi đọc được `s` của đầu kia.
- [ ] **Step 5: Chạy lại** lệnh ở Step 3. Kỳ vọng PASS cả 5 test.
- [ ] **Step 6: Commit** (`feat(shellx-link): Noise XX handshake and transport, checked against snow vectors`).

### Task 3: Frame và message của ShellX Link v1, kèm đặc tả

**Files:**
- Create: `shellx-link/spec/PROTOCOL.md`, `shellx-link/spec/vectors/messages.json`
- Create: `shellx-link/Sources/ShellXLinkCore/Messages/LinkMessage.swift`, `PendingItem.swift`, `LinkCodec.swift`
- Test: `shellx-link/Tests/ShellXLinkCoreTests/LinkCodecTests.swift`

**Interfaces:**
- Produces:

```swift
public struct PendingItem: Codable, Equatable, Sendable {
  public var requestId: String; public var kind: Kind      // .permission | .question | .exitPlan
  public var agent: String                                   // "claude" in P1
  public var workspaceId: String; public var workspaceTitle: String
  public var toolName: String?; public var toolInputPreview: String?   // ≤ 8192 UTF-8 bytes
  public var createdAtMs: Int64
}
public enum PermissionMode: String, Codable, Sendable { case once, always, all, deny }
public enum ReplyOutcome: String, Codable, Sendable { case delivered, alreadyHandled = "already_handled", unknown }
public enum LinkMessage: Equatable, Sendable {
  case hello(clientVersion: String, deviceName: String)
  case welcome(protocolVersion: Int, hostVersion: String, machineName: String)
  case error(code: String, message: String)                // "protocol_mismatch", "bad_request", …
  case snapshotGet
  case snapshot(revision: Int, pending: [PendingItem])
  case changed(revision: Int, added: [PendingItem], resolved: [String])
  case reply(requestId: String, mode: PermissionMode)
  case replyResult(requestId: String, outcome: ReplyOutcome)
  case ping(nonce: UInt64), pong(nonce: UInt64)
  case unknown(type: String)                               // forward compatible: never throws on new types
}
public enum LinkCodec {
  public static let maxFrameBytes = 65_519                 // Noise max message 65535 − 16 tag
  public static func encode(_ m: LinkMessage) throws -> Data   // throws LinkCodecError.frameTooLarge
  public static func decode(_ d: Data) throws -> LinkMessage   // throws .badJSON / .wrongVersion
}
```

Trên đường truyền, mỗi frame là một object JSON UTF-8 có dạng `{"v":1,"t":"<type>",…}`.
- Tên `t`: `hello`, `welcome`, `error`, `agent.snapshot.get`, `agent.snapshot`, `agent.changed`, `agent.reply`, `agent.reply.result`, `ping`, `pong`.
- Khoá JSON dùng `snake_case`.

- [ ] **Step 1: Viết `PROTOCOL.md`**, ngắn gọn, gồm:
  - Tầng truyền: circuit `cmux-relay` khung Single. Mỗi tin WebSocket nhị phân là một tin Noise.
  - Handshake: 3 tin đầu.
  - Frame: định dạng ở trên.
  - Bảng message, kèm ai gửi và khi nào.
  - Luật version: host gửi `error protocol_mismatch` rồi đóng kết nối khi `v` khác 1.
  - Luật idempotent của `agent.reply`.
  - Việc cắt preview 8 KiB.

  Viết `spec/vectors/messages.json`: mỗi loại message một cặp `{message, json}`, để Windows và Android sau này kiểm tra theo.
- [ ] **Step 2: Viết test fail:**
  - `testGoldenVectorsRoundTrip`: mọi mục trong `messages.json` phải decode ra đúng message, rồi encode lại ra JSON tương đương về ngữ nghĩa.
  - `testUnknownTypeDecodesAsUnknown`: `{"v":1,"t":"future.thing"}` decode ra `.unknown(type: "future.thing")`.
  - `testWrongVersionThrows`: `"v":2` thì ném `.wrongVersion`.
  - `testOversizeFrameRejected`: snapshot 70 000 byte thì ném `.frameTooLarge`.
- [ ] **Step 3: Chạy** `swift test --package-path shellx-link --filter LinkCodecTests`. Kỳ vọng FAIL.
- [ ] **Step 4: Cài đặt** `LinkCodec` bằng `JSONEncoder` / `JSONDecoder` với `keyEncodingStrategy = .convertToSnakeCase`, cùng một `struct` phong bì có `v` và `t`.
- [ ] **Step 5: Chạy lại** lệnh ở Step 3. Kỳ vọng PASS.
- [ ] **Step 6: Commit** (`feat(shellx-link): v1 message codec, protocol doc and golden vectors`).

### Task 4: Client relay cho `cmux-relay`, phía host và phía client

**Files:**
- Create: `shellx-link/Sources/ShellXLinkRelay/RelayControl.swift`, `RelayHostRegistration.swift`, `RelayClientConnector.swift`, `RelayCircuit.swift`
- Create: `shellx-link/Tests/ShellXLinkRelayTests/RelayIntegrationTests.swift`, `TestTicketMinter.swift`

**Interfaces:**
- Consumes: không.
- Produces:

```swift
public struct RelayTicket: Sendable { public var ticket: String; public var expiresAtUnix: Int64 }
public typealias TicketProvider = @Sendable () async throws -> RelayTicket
public protocol RelayCircuit: Sendable {            // one joined circuit, binary in/out
  func send(_ data: Data) async throws
  func receive() async throws -> Data               // throws RelayError.closed at end
  func close() async
}
public actor RelayHostRegistration {
  public init(relayURL: URL, slot: String, tickets: TicketProvider)
  public func run(onCircuit: @escaping @Sendable (any RelayCircuit) async -> Void) async throws  // re-registers on drop, until cancelled
}
public enum RelayClientConnector {
  public static func connect(relayURL: URL, slot: String, ticket: RelayTicket) async throws -> any RelayCircuit
}
public enum RelayError: Error, Equatable { case closed, server(code: String, retryable: Bool), protocolViolation(String) }
```

Hành vi phải khớp với implementation tham khảo:
- `cmux-tui/crates/cmux-remote/src/provider/relay.rs`: `join_circuit` ở `:1033`, `relay_circuit_url` ở `:1685`, khung `Single` cho `relay+wss`;
- `cmux-tui/crates/cmux-relay/src/relay.rs`: xử lý `Register` / `Connect` / `Join` từ `:390`.

Các tin điều khiển là JSON text với `"type"` kebab-case (`RelayControl` trong `cmux-remote-protocol/src/relay.rs:99`). Trường `protocol` dùng đúng giá trị mà `cmux-relay` chấp nhận; đọc chỗ nó kiểm tra để lấy. `lane` là token ngẫu nhiên do client tạo, `generation` bắt đầu từ 0. Đọc `relay.rs` cho đúng định dạng và luật của hai trường này. Host trả `Pong` khi nhận `Ping`.

- [ ] **Step 1: Viết `TestTicketMinter`** (chỉ dùng trong test). Nó cài HMAC-SHA256 trên `signingPayload` giống `relay/src/v2/tickets.ts:36-47`, với claims version 2, issuer `shellx-relay`, lifetime 120 s, và trả ra `v2.<b64url(json)>.<b64url(sig)>`.
- [ ] **Step 2: Viết test tích hợp fail.** Test khởi động `$CMUX_RELAY_BIN serve` với env `CMUX_RELAY_HMAC_SECRET`, `CMUX_RELAY_ISSUER=shellx-relay`, `CMUX_RELAY_BIND=127.0.0.1:<port>`, giống `relay/test/relay2-interop.test.ts:11-29`. Nếu biến `CMUX_RELAY_BIN` không có thì `XCTSkip`. Các test:
  - `testClientAndHostExchangeBytes`: host đăng ký slot `s1`, client connect, rồi gửi `[0x01,0x02]` mỗi chiều và nhận lại đúng.
  - `testTwoCircuitsOnOneRegistration`: hai client lần lượt connect. Host nhận hai lần `onCircuit`, và mỗi cặp chỉ thấy byte của mình.
  - `testBadTicketSurfacesServerError`: chữ ký sai thì ném `RelayError.server`.
  - `testReRegisterAsksForFreshTicket`: đóng socket điều khiển của host (test có hook `_dropControlForTesting()`). Kỳ vọng provider được gọi ≥ 2 lần và client mới vẫn connect được.
- [ ] **Step 3: Build relay rồi chạy test.**
  - `cargo build --manifest-path cmux-tui/Cargo.toml -p cmux-relay --release`
  - `CMUX_RELAY_BIN=$PWD/cmux-tui/target/release/cmux-relay swift test --package-path shellx-link --filter RelayIntegrationTests`
  
  Kỳ vọng FAIL.
- [ ] **Step 4: Cài đặt** bằng `URLSessionWebSocketTask`. Mỗi circuit là một WebSocket riêng tới URL circuit. Sau `Ready`, mỗi tin `.data` là một frame.
- [ ] **Step 5: Chạy lại** lệnh ở Step 3. Kỳ vọng PASS cả 4 test.
- [ ] **Step 6: Commit** (`feat(shellx-link): cmux-relay host registration and client circuits`).

### Task 5: Phiên ShellX Link: host, client và nguồn feed trừu tượng

**Files:**
- Create: `shellx-link/Sources/ShellXLinkSession/AgentFeedSource.swift`, `LinkHost.swift`, `LinkClient.swift`, `SecureChannel.swift`
- Create: `shellx-link/Sources/ShellXLinkSession/Testing/InMemoryCircuit.swift` (public, dùng cho test và probe)
- Test: `shellx-link/Tests/ShellXLinkSessionTests/LinkSessionTests.swift`, `FakeFeedSource.swift`

**Interfaces:**
- Consumes: `NoiseHandshake`, `NoiseTransport`, `LinkCodec`, `LinkMessage`, `PendingItem` (Task 2-3), `RelayCircuit`, `RelayHostRegistration` (Task 4).
- Produces:

```swift
public protocol AgentFeedSource: Sendable {
  func snapshot() async -> (revision: Int, pending: [PendingItem])
  func changes() -> AsyncStream<(revision: Int, added: [PendingItem], resolved: [String])>  // multicast: each call = new subscriber
  func reply(requestId: String, mode: PermissionMode) async -> ReplyOutcome
}
public struct SecureChannel: Sendable {          // Noise over a RelayCircuit, one LinkMessage per Noise message
  public static func open(_ c: any RelayCircuit, role: NoiseRole, key: NoiseStaticKey,
                          trusts: @escaping @Sendable (Data) -> Bool) async throws -> SecureChannel
  public func send(_ m: LinkMessage) async throws
  public func receive() async throws -> LinkMessage
  public var peerKey: Data { get }
}
public actor LinkHost {
  public init(key: NoiseStaticKey, trustedClients: @escaping @Sendable () -> Set<Data>,
              feed: any AgentFeedSource, hostVersion: String, machineName: String)
  public func serve(_ circuit: any RelayCircuit) async      // one session; returns when it ends
}
public actor LinkClient {
  public static func connect(_ circuit: any RelayCircuit, key: NoiseStaticKey, hostKey: Data,
                             clientVersion: String, deviceName: String) async throws -> LinkClient
  public func snapshot() async throws -> (revision: Int, pending: [PendingItem])
  public func reply(requestId: String, mode: PermissionMode) async throws -> ReplyOutcome
  public nonisolated var changes: AsyncStream<(revision: Int, added: [PendingItem], resolved: [String])> { get }
}
public func makeInMemoryCircuitPair() -> (any RelayCircuit, any RelayCircuit)
```

Luồng phiên phía host như sau:
1. Bắt tay Noise.
2. Nhận `hello`, trả `welcome(protocolVersion: 1, …)`.
3. Đăng ký `changes()` và đẩy mỗi thay đổi thành `agent.changed`.
4. Trả lời `agent.snapshot.get`, `agent.reply` và `ping`.

Message không biết thì trả `error bad_request` và giữ phiên. Frame có `v` ≠ 1 thì trả `error protocol_mismatch` rồi đóng.

- [ ] **Step 1: Viết test fail** dùng `makeInMemoryCircuitPair` và `FakeFeedSource` (lưu dictionary pending, có `resolveLocally(requestId:)` để giả lập Mac tự duyệt):
  - `testHelloWelcomeAndSnapshot`: snapshot trả 1 item `permission`, `toolName == "Bash"`.
  - `testReplyDelivered`: kết quả `.delivered`, và fake ghi nhận `mode == .once`.
  - `testReplyTwiceIsAlreadyHandled`: lần 2 trả `.alreadyHandled`.
  - `testChangedPushedWithinOneSecond`: thêm item vào fake thì client nhận `added` trong < 1 s.
  - `testTwoClientsSeeResolution`: hai client, client A reply, client B nhận `resolved == [id]`.
  - `testUntrustedClientDropped`: khoá của client không nằm trong `trustedClients` thì `LinkClient.connect` ném lỗi, và host không gọi feed.
  - `testReconnectGetsFreshSnapshot`: đóng circuit, fake resolve item cũ rồi thêm item mới, client mới chỉ thấy item mới.
- [ ] **Step 2: Chạy** `swift test --package-path shellx-link --filter LinkSessionTests`. Kỳ vọng FAIL.
- [ ] **Step 3: Cài đặt.** `LinkClient` khớp mỗi `reply` với `replyResult` theo `requestId`. Ping được gửi mỗi 20 s; nếu 45 s không nhận được gì thì coi phiên đã chết.
- [ ] **Step 4: Chạy lại** lệnh ở Step 2. Kỳ vọng PASS cả 7 test.
- [ ] **Step 5: Commit** (`feat(shellx-link): host and client sessions over Noise`).

### Task 6: Relay v2 cấp `link_slot` và vé cho lane `link`

**Files:**
- Create: `relay/migrations/0007_link_slot.sql`
- Modify: `relay/src/v2/machines.ts` (POST `/` trả thêm `link_slot`, cả nhánh 201 lẫn 200)
- Modify: `relay/src/v2/relay-tickets.ts` (body có thêm `lane?: "link"`)
- Modify: `shellx-core/src/machines.rs` (`MachineFile` và kết quả `machines.register` có thêm `link_slot`), `shellx-core/src/tickets.rs` (truyền `lane`)
- Test: `relay/test/v2-link-slot.test.ts`, `shellx-core/tests/` (theo kiểu test của `machines` / `tickets` hiện có, dùng `fake-api`)

**Interfaces:**
- Produces:
  - `machines.register` → `{machine_id, slot, link_slot}`.
  - `POST /v2/relay/tickets {machine_id, permission, target_machine_id?, lane?: "link"}`: khi `lane == "link"` thì dùng `link_slot` thay cho `slot`, với cùng luật grant và luật tự kết nối tới chính mình.
  - shellx-core: `tickets.mint` nhận thêm `lane`.

- [ ] **Step 1: Viết test vitest fail** trong `v2-link-slot.test.ts`:
  - register trả `link_slot` dài 22 ký tự và khác `slot`;
  - đăng ký lại cùng thiết bị thì `link_slot` giữ nguyên;
  - ticket với `lane:"link"` có claims `slot == link_slot`;
  - `lane:"terminal"` thì bị 400;
  - connect tới máy khác khi chưa có grant thì `notGranted`.

  Dùng helper trong `relay/test/helpers.ts` giống `v2-relay-tickets.test.ts`.
- [ ] **Step 2: Chạy** `cd relay && npx vitest run test/v2-link-slot.test.ts`. Kỳ vọng FAIL.
- [ ] **Step 3: Viết migration 0007.** Thêm cột `link_slot TEXT`, backfill bằng `b64url(16 byte ngẫu nhiên)` cho mọi dòng (dùng `hex(randomblob(16))` rồi chuyển đổi trong TS migrate hook nếu SQL thuần không làm được b64url; đọc `relay/src/db` để xem migration TS có được phép không), rồi tạo unique index. Sau đó sửa hai route.
- [ ] **Step 4: Chạy** `cd relay && npm test`. Kỳ vọng PASS toàn bộ, kể cả `migrate-0005.test.ts` và `v2-*.test.ts` cũ.
- [ ] **Step 5: Viết test shellx-core fail** `register_returns_link_slot` và `mint_passes_lane`. Cập nhật `fake-api` cho khớp. Chạy `cd shellx-core && cargo test --workspace --locked`. Kỳ vọng FAIL. Cài đặt, rồi chạy lại cho PASS, cùng với `scripts/c-smoke.sh` và `python3 scripts/check_deps.py`.
- [ ] **Step 6: Commit** (`feat(relay,shellx-core): per-machine link slot and link-lane relay tickets`).

### Task 7: Mac: nối `LinkHost` vào ShellX và Feed

**Files:**
- Create: `Sources/ShellX/Remote/Link/ShellXLinkFeedSource.swift` (`AgentFeedSource` trên `FeedCoordinator`)
- Create: `Sources/ShellX/Remote/Link/ShellXLinkHostController.swift` (khoá host, danh sách client tin cậy, `RelayHostRegistration` + `LinkHost`)
- Modify: `Sources/Feed/FeedCoordinator.swift:121` (`onRevisionChange` thành multicast: giữ handler `feed.changed` cũ, thêm đăng ký cho Link)
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/ShellXRemoteService.swift:300-360` (`registerHost` đọc `link_slot`; `startHost` khởi động link host khi gate bật)
- Modify: thêm local package `shellx-link` (product `ShellXLinkSession`) vào app target theo `skills/cmux-architecture`
- Create: socket method chỉ có trong DEBUG `shellx.link.debug_invite` (theo `skills/cmux-socket-policy`, không cướp focus)
- Test: `cmuxTests/ShellXLinkFeedSourceTests.swift` (chạy `scripts/sync-test-wiring` sau khi thêm)

**Interfaces:**
- Consumes: `AgentFeedSource`, `LinkHost`, `RelayHostRegistration`, `NoiseStaticKey` (Task 2-5); `FeedCoordinator.deliverReply(requestId:decision:)` (`FeedCoordinator.swift:511`); `WorkstreamItem` / `WorkstreamPayload.permissionRequest(requestId:toolName:toolInputJSON:pattern:)`; `tickets.mint {permission, lane:"link"}` (Task 6).
- Produces:
  - `shellx.link.debug_invite {client_key_b64}` → `{relay_url, slot, ticket, expires_at_unix, host_key_b64}`. Lệnh này thêm khoá client vào danh sách tin cậy, rồi tự mint vé `connect` lane `link` tới chính máy này (luật D3).
  - Khoá host lưu ở `~/Library/Application Support/ShellX/link/host-key` (quyền 0600), danh sách tin cậy ở `…/link/trusted-clients.json`. P2 sẽ chuyển sang Keychain cùng ghép cặp thật.

Quy tắc map dữ liệu:
- `PendingItem.requestId` lấy từ `requestId` của payload. `workspaceTitle` lấy từ workstream.
- `toolInputPreview` là `toolInputJSON`, cắt còn 8192 byte UTF-8 và không cắt giữa một ký tự.
- Chỉ item `.pending` mới vào snapshot.
- `reply`: nếu không còn item `.pending` nào có `requestId` này thì trả `.alreadyHandled` và **không** gọi `deliverReply`. Ngược lại thì gọi `deliverReply(requestId:, decision: .permission(mode))` và trả `.delivered`. Map `PermissionMode` sang `WorkstreamPermissionMode` theo tên. Mode mà `FeedPermissionActionPolicy` không cho với agent đó thì trả `.unknown`.

- [ ] **Step 1: Viết test fail** trong `ShellXLinkFeedSourceTests`. Dựng `WorkstreamStore` / `FeedCoordinator` theo cách `FeedCoordinatorTests.swift` đang làm:
  - `testSnapshotListsPendingPermission`.
  - `testChangesEmitsAddedThenResolved`.
  - `testReplyAfterMacResolvedIsAlreadyHandled`: resolve bằng `deliverReply` trước, sau đó gọi `reply` thì nhận `.alreadyHandled`, và waiter chỉ resolve một lần.
  - `testToolInputPreviewTruncated`: input 2 MB thì preview ≤ 8192 byte và là UTF-8 hợp lệ.
  - `testLegacyFeedChangedHandlerStillFires`: handler multicast không làm mất handler cũ.
- [ ] **Step 2: Chạy** `scripts/shellx/test-app.sh ShellXLinkFeedSourceTests`. Kỳ vọng FAIL.
- [ ] **Step 3: Cài đặt** feed source, multicast và controller. Host chỉ chạy khi `ShellXRemoteGate` bật (DEBUG: `SHELLX_REMOTE_MACHINES=1`). Không bật `ShellXFeatures.remoteMachines`.
- [ ] **Step 4: Chạy lại** test ở Step 2. Kỳ vọng PASS. Chạy thêm `scripts/shellx/test-app.sh FeedCoordinatorTests FeedWaiterRegistryTests ShellXCoreFFITests` và `swift test --package-path Packages/Shared/ShellXBrand`. Kỳ vọng PASS.
- [ ] **Step 5: Build tagged.** Chạy `CMUX_DEV_BACKEND_MODE=local` cùng script tagged build (`skills/cmux-dev-workflow/references/tagged-builds.md`) với tag `link`. Kỳ vọng build xong và app mở được.
- [ ] **Step 6: Commit** (`feat(shellx): serve ShellX Link agent feed from the Mac host`).

### Task 8: `shellx-link-probe` và chạy spike

**Files:**
- Create: `shellx-link/Sources/shellx-link-probe/main.swift`
- Modify: `docs/superpowers/ledgers/shellx-ios.md` (mục "Spike P1")

**Interfaces:**
- Consumes: `LinkClient`, `RelayClientConnector`, `NoiseStaticKey` (Task 2-5); `shellx.link.debug_invite` (Task 7).
- Produces: các lệnh CLI
  - `keygen --out <file>` (in public key dạng b64);
  - `snapshot --invite <json> --key <file>`;
  - `watch …`;
  - `approve <request_id> …`;
  - `bench --count 50 …`: tự tạo 50 yêu cầu bằng một hook giả gửi `feed.push` blocking qua `CMUX_TAG=link scripts/cmux-debug-cli.sh`, xem `CLI/CMUXCLI+AgentHook*.swift` để biết đúng payload. Với mỗi yêu cầu, đo hai thứ: thời gian từ `agent.changed` tới lúc nhận, và round trip `agent.reply` → `agent.reply.result`. In p50/p95.

- [ ] **Step 1: Cài đặt probe.** Phần logic đã có test ở Task 5. Probe chỉ là CLI mỏng, nên không viết test riêng.
- [ ] **Step 2: Spike local.**
  - Chạy relay Node local (`relay/README.md`) với `CMUX_RELAY_HMAC_SECRET` và chạy `cmux-relay` local cùng secret đó.
  - Chạy app tag `link` với `SHELLX_REMOTE_MACHINES=1`, trỏ vào API local (xem cách `ShellXBrand.swift:22` đọc override).
  - Chạy `keygen`, rồi `debug_invite`, rồi `watch`.
  - Trong app tag `link`, chạy Claude Code và nhờ nó `git status`. Thẻ xin quyền phải hiện trong `watch`. Chạy `approve`, thì Claude chạy tiếp.
  - Ghi ảnh chụp và log vào ledger.
- [ ] **Step 3: `bench --count 50` local.** Ghi p50/p95 vào ledger.
- [ ] **Step 4: Spike WAN (cần người dùng đồng ý trước khi deploy).**
  - Hỏi người dùng có cho deploy migration 0007 cùng route mới lên `relay.shellx.pro` không.
  - Nếu được: deploy theo `deploy/README.md`, chạy lại Step 2 và Step 3 với API thật, trên mạng 4G (dùng hotspot điện thoại).
  - Nếu không: ghi rõ trong ledger là "chưa đo WAN".
- [ ] **Step 5: Kết luận trong ledger** với mục D-iOS-1 gồm:
  - đạt hay không đạt mục tiêu < 500 ms p95 và < 1 s;
  - các vấn đề gặp phải;
  - những gì P2 cần đổi trong `PROTOCOL.md`.
- [ ] **Step 6: Commit** (`feat(shellx-link): probe CLI and P1 spike results`).

---

**Sau P1:** viết kế hoạch P2 (ghép cặp điện thoại thật qua relay v2 với thiết bị loại `mobile`, Keychain, câu hỏi / plan / chat, Codex adapter để sau), dựa trên D-iOS-1.
