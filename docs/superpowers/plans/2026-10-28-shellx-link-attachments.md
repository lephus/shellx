# ShellX Link: gửi ảnh và tệp từ iPhone — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trên iPhone, người dùng đính kèm ảnh (thư viện ảnh, chọn nhiều) và tệp (app Tệp) vào một tin nhắn. Ảnh/tệp đi qua ShellX Link tới phiên Claude Code đang chạy trên Mac, rồi Claude nhận chúng cùng câu nhắn.

**Architecture:**
- **Giao thức Link v1** thêm ba lệnh tải lên theo từng mẩu: `attach.begin`, `attach.chunk` và `attach.end`. Lệnh `chat.send` thêm danh sách `attachments`, và `welcome` thêm `features`. Chỉ thêm trường tuỳ chọn và lệnh mới, `v` vẫn là 1.
- **`LinkHost`** giữ các mẩu đang tải trong bộ nhớ, riêng cho từng phiên Link. Khi có `chat.send`, nó trao bytes cho `AgentChatSource`.
- **Phía Mac:**
  - Ảnh: dùng đường có sẵn `agentChatSend` → `saveImageData`, tức lưu file tạm và gõ đường dẫn đã escape.
  - Tệp: thêm `saveAttachmentData`. Mac tự đặt thư mục, điện thoại không bao giờ chỉ định được đường dẫn.
- **iPhone:**
  - Ảnh: chọn bằng `PhotosPicker`, rồi thu nhỏ bằng ImageIO.
  - Tệp: chọn bằng `fileImporter`.
  - Ô nhập có nút "+" và hàng ô đính kèm. Nút chỉ hiện khi Mac quảng bá `attachments`.

**Tech Stack:** Swift 6.0, SwiftUI (iOS 17+), ShellX Link (Noise over relay), XCTest / Swift Testing.

**Spec:** không có tài liệu thiết kế riêng. Ngày 2026-10-28 người dùng bỏ qua phần hỏi đáp ("làm đi"), nên mục **Quyết định** dưới đây chính là spec. Tất cả là lựa chọn của agent, đã báo người dùng trong chat.

## Quyết định (spec)

- **Cách dùng (người dùng):** chụp màn hình lỗi hoặc chọn một tệp, kèm một câu nhắn ("sửa lỗi này"), gửi chung một tin. Tin có thể chỉ có đính kèm mà không có chữ.
- **Giới hạn:**
  - tối đa **5** đính kèm mỗi tin;
  - mỗi đính kèm tối đa **10 485 760 bytes** (10 MiB, bằng `maxClipboardImageSize` của Mac);
  - mỗi phiên Link giữ tối đa **5** upload chưa gửi.
- **Ảnh:** thu nhỏ để cạnh dài tối đa **2000 px**, mã hoá **JPEG chất lượng 0.85**, tên `<tên gốc không đuôi>.jpg`. Ảnh vẫn quá 10 MiB thì báo lỗi, không gửi. GIF và ảnh động bị chuyển thành ảnh tĩnh JPEG.
- **Tệp:** gửi nguyên bytes, giữ tên gốc. Mac lọc tên (bỏ `/`, `\`, ký tự điều khiển, dấu `.` ở đầu; tối đa 100 bytes UTF-8; tên rỗng thành `file`).
- **Trên Mac:**
  - Ảnh lưu như ảnh dán từ clipboard (`saveImageData`). Tệp lưu vào `<thư mục tạm của TerminalPasteboardService>/shellx-attachments/<UUID>/<tên đã lọc>`, quyền 0600, đăng ký "owned" để được dọn như ảnh tạm.
  - Mac xoá prompt, gõ lần lượt các đường dẫn đã escape, mỗi đường dẫn cách nhau một dấu cách, rồi dán chữ và Enter. Tin chỉ có đính kèm thì Enter sau đường dẫn cuối.
  - Đây đúng là thứ tự `agentChatSend` đang làm cho ảnh.
- **Tải lên:**
  - Mỗi mẩu tối đa **45 000 bytes** dữ liệu gốc (base64 trong JSON, vừa khung 65 519 bytes).
  - Các mẩu gửi theo thứ tự `offset`, mẩu nào cũng chờ trả lời (timeout 10 s mỗi mẩu như mọi call).
  - `attach.end` kiểm tra SHA-256 của toàn bộ bytes.
- **Gating:** `welcome.features` có `"attachments"` khi chat source của host nhận đính kèm. iPhone chỉ hiện nút "+" khi Mac của phiên đích có feature đó. Bản Windows và Mac cũ không có feature nên không thấy nút.
- **Giao diện iPhone:**
  - Nút "+" (`plus`) bên trái ô gõ mở menu **Ảnh** / **Tệp**.
  - Đính kèm hiện thành hàng ô 56 pt phía trên ô gõ: ảnh là thumbnail, tệp là icon `doc` kèm tên. Mỗi ô có nút ✕.
  - Có chữ hoặc có đính kèm thì nút bên phải là **Gửi**, không có gì thì là mic.
  - Đang tải lên thì nút Gửi hiện vòng tiến độ và ô nhập bị khoá.
  - Gửi lỗi (mất kết nối, quá giới hạn, Mac từ chối) thì trả lại chữ và đính kèm vào ô nhập, kèm thông báo như lỗi gửi hiện nay.
- **Bong bóng tin ở màn hình chính:** dưới chữ có dòng "📎 2 tệp". Tin chỉ có đính kèm thì bong bóng chỉ có dòng đó. Màn hình agent không cần echo, vì Claude Code tự ghi đường dẫn và `[Image #n]` vào transcript.
- **Không làm trong đợt này:** chụp ảnh bằng camera, tải lên song song, nối lại upload dở sau khi rớt mạng, xem trước tệp trên iPhone, bản Windows.

## Global Constraints

- App-linked Swift phải tương thích Swift 6.0 (`skills/cmux-architecture/references/swift-6-0-compatibility.md`).
- `shellx-ios/` chỉ import module có trong allowlist của `scripts/shellx/check-ios-license.sh`. `PhotosUI`, `ImageIO`, `UniformTypeIdentifiers` và `CoreTransferable` đã có sẵn.
- Không dùng code GPL trong `shellx-ios/` hay `shellx-link/` (MIT).
- Mọi chuỗi hiển thị trên iPhone nằm trong `shellx-ios/ShellX/Localizable.xcstrings`, đủ en và vi, qua `scripts/check-strings.py`.
- Không bao giờ log bytes, tên tệp hay nội dung đính kèm. Log chỉ số lượng và kích thước.
- Chỉ build qua `shellx-ios/scripts/dev.sh`, `scripts/shellx/test-app.sh` và `swift test --package-path …`, không gọi `xcodebuild` trần.
- Hằng số dùng chung: `ShellXLink.maxAttachmentBytes = 10_485_760`, `ShellXLink.maxAttachmentsPerMessage = 5`, `ShellXLink.maxAttachmentChunkBytes = 45_000`, feature `"attachments"`.

## Review Focus

1. **Mất mạng giữa lúc tải lên:** upload dở bị bỏ trên Mac khi phiên Link kết thúc, và iPhone trả lại đính kèm vào ô nhập. Test: `testUploadsDieWithTheSession` (Task 2), `testFailedSendGivesTheAttachmentsBack` (Task 4).
2. **Tên tệp độc hại** (`../../.ssh/x`, `\u{0}`, chỉ có dấu chấm, tên 300 bytes): không bao giờ ra khỏi thư mục UUID. Test: `saveAttachmentDataKeepsHostileNamesInsideItsFolder` (Task 3).
3. **Gửi tới một phiên đã kết thúc:** Mac trả `not_found` trước khi ghi bất kỳ tệp nào. Test: `testAttachmentsToADeadSessionWriteNothing` (Task 3).
4. **Ảnh HEIC/PNG khổng lồ từ thư viện:** được thu nhỏ còn ≤ 2000 px, không để hết bộ nhớ (dùng thumbnail của ImageIO, không decode full). Test: `testLargePhotoIsDownscaledToJPEG` (Task 5).
5. **Mac cũ không có feature:** không có nút "+"; gửi đính kèm tới host không hỗ trợ thì lỗi rõ ràng, không gửi mất chữ. Test: `testHostWithoutAttachmentsAdvertisesNothing` (Task 2), `testAttachButtonOnlyForMacsThatAcceptThem` (Task 4).

---

### Task 1: Giao thức và codec

**Files:**
- Modify: `shellx-link/Sources/ShellXLinkCore/Messages/LinkMessage.swift`, `LinkCodec.swift`, `shellx-link/Sources/ShellXLinkCore/ShellXLink.swift` (hằng số)
- Create: `shellx-link/Sources/ShellXLinkCore/Messages/Attachment.swift`
- Modify: `shellx-link/spec/PROTOCOL.md` (bảng mục 4, quy tắc mới ở mục 5, mục 10), `shellx-link/spec/vectors/messages.json`
- Modify (để build xanh, đổi pattern theo arity mới): `shellx-link/Sources/ShellXLinkSession/LinkClient.swift`, `LinkHost.swift`, `shellx-link/Sources/shellx-link-probe/{main,Commands}.swift`, `shellx-link/Tests/**`, `shellx-ios/Packages/ShellXAppCore/Sources/**`, `shellx-ios/Packages/ShellXAppCore/Tests/**`
- Test: `shellx-link/Tests/ShellXLinkCoreTests/LinkCodecTests.swift`

**Interfaces:**
- Produces:
  - `public enum AttachmentKind: LinkWireEnum { case image, file, other(String) }` (wire: `"image"`, `"file"`)
  - `LinkMessage`:
    - `.welcome(protocolVersion: Int, hostVersion: String, machineName: String, features: [String])` — wire `features`, tuỳ chọn, bỏ trống khi rỗng.
    - `.chatSend(callId: String, sessionId: String, text: String, attachments: [String])` — wire `attachments`, tuỳ chọn, bỏ trống khi rỗng.
    - `.attachBegin(callId: String, kind: AttachmentKind, name: String, size: Int)` — `attach.begin`.
    - `.attachReady(callId: String, attachmentId: String)` — `attach.ready`.
    - `.attachChunk(callId: String, attachmentId: String, offset: Int, data: Data)` — `attach.chunk`; trên dây `data` là base64 chuẩn có padding.
    - `.attachChunkResult(callId: String, attachmentId: String, received: Int)` — `attach.chunk.result`.
    - `.attachEnd(callId: String, attachmentId: String, sha256: Data)` — `attach.end`; trên dây `sha256` là 64 ký tự hex thường.
    - `.attachEndResult(callId: String, attachmentId: String)` — `attach.end.result`.
  - `ShellXLink.maxAttachmentBytes`, `.maxAttachmentsPerMessage`, `.maxAttachmentChunkBytes`, `.attachmentsFeature = "attachments"`.

- [ ] **Step 1: Viết test hỏng**
  - Trong `LinkCodecTests`, thêm `testAttachmentFramesRoundTrip`: mỗi case mới cộng `.welcome(…features: ["attachments"])` và `.chatSend(…attachments: ["a1","a2"])` encode/decode ra đúng giá trị ban đầu.
  - Thêm `testWelcomeAndSendWithoutNewFieldsStillDecode`: JSON không có `features` hay `attachments` thì decode thành `[]`, và encode `[]` không ghi khoá đó ra.
  - Thêm `testFullChunkFitsAFrame`: `attach.chunk` với `data` dài 45 000 bytes và `call_id`/`attachment_id` 64 bytes encode được, ≤ 65 519 bytes.
  - Thêm `testChunkDataMustBeBase64`: `"data":"%%%"` là `bad_json`.
  - Thêm vector mới vào `messages.json` (một vector cho mỗi `t` mới, cộng welcome/chat.send có trường mới) để `testGoldenVectors` có sẵn phủ chúng.
- [ ] **Step 2: Chạy và xác nhận test hỏng**
  - Lệnh: `swift test --package-path shellx-link --filter LinkCodecTests`
  - Kỳ vọng: lỗi biên dịch hoặc FAIL ở các test mới.
- [ ] **Step 3: Làm cho test qua**
  - Thêm các case và encode/decode theo kiểu đang dùng trong `LinkCodec` (struct `Codable` riêng cho mỗi body, khoá snake_case).
  - Sửa mọi chỗ khớp `.welcome`/`.chatSend` theo arity mới; logic chưa đổi.
  - `LinkClient` và `LinkHost` coi các case mới là "không được gửi tới phía này" giống các nhánh hiện có: host thấy `attachReady`/`attachChunkResult`/`attachEndResult` thì trả `bad_request`; client bỏ qua các frame host-only.
- [ ] **Step 4: Viết spec**
  - `PROTOCOL.md` mục 4: thêm 6 dòng vào bảng; ghi `welcome.features` và `chat.send.attachments`; ghi rằng có `attachments` (1–5 id) thì `text` được rỗng (0–16 384 bytes); thêm mã lỗi `too_large`.
  - Mục 5, thêm "Attachments":
    - `size` từ 1 tới 10 485 760, lớn hơn thì `too_large`;
    - mẩu đi theo thứ tự, `offset` phải bằng số bytes đã nhận, `data` từ 1 tới 45 000 bytes, sai thì `bad_request`;
    - `attach.end` khi chưa đủ bytes hoặc sai SHA-256 thì `bad_request`, và upload bị bỏ;
    - id chỉ có nghĩa trong phiên Link đã tạo nó, và hết khi phiên kết thúc;
    - một upload chỉ dùng được cho một `chat.send` và bị xoá ngay sau đó, dù kết quả thế nào;
    - tối đa 5 upload chưa gửi mỗi phiên;
    - `chat.send` có id lạ, chưa `end` hoặc trùng thì `bad_request`;
    - host không có feature thì trả `unsupported` cho mọi `attach.*`.
  - Mục 10:
    - thêm `attach.*` vào bảng lệnh được phép. Tác dụng trên Mac: giữ bytes trong bộ nhớ; ghi tệp vào thư mục tạm do host đặt tên, chỉ khi `chat.send` tới một phiên *live*;
    - thêm đoạn phân tích: điện thoại không chọn đường dẫn, tên đã được lọc và nằm trong thư mục UUID mới, quyền 0600, host không bao giờ mở hay chạy tệp, đường dẫn chỉ được gõ vào terminal của chính phiên live đó (giống văn bản), giới hạn kích thước chặn việc làm đầy đĩa/bộ nhớ;
    - sửa câu "No field of any message names … a path" cho đúng: vẫn không có trường nào là đường dẫn trên host.
- [ ] **Step 5: Chạy toàn bộ test**
  - `swift test --package-path shellx-link` → PASS.
  - `shellx-ios/scripts/dev.sh test core` → PASS.
  - `scripts/shellx/check-link-license.sh` → ok.
- [ ] **Step 6: Commit**: `feat(shellx-link): attach.* frames, welcome features and chat.send attachments`

### Task 2: Tải lên trong phiên Link (host và client)

**Files:**
- Modify: `shellx-link/Sources/ShellXLinkSession/AgentChatSource.swift`, `LinkHost.swift`, `LinkClient.swift`
- Create: `shellx-link/Sources/ShellXLinkSession/AttachmentUploads.swift` (state của một phiên)
- Modify: `shellx-link/Tests/ShellXLinkSessionTests/FakeChatSource.swift`
- Test: `shellx-link/Tests/ShellXLinkSessionTests/AttachmentSessionTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `public struct ChatAttachment: Equatable, Sendable { public let kind: AttachmentKind; public let name: String; public let data: Data }`
  - `AgentChatSource` thêm hai requirement, có default trong extension:
    - `var acceptsAttachments: Bool { get }` — default `false`;
    - `func send(sessionId: String, text: String, attachments: [ChatAttachment]) async -> ChatSendOutcome` — default: không có đính kèm thì gọi `send(sessionId:text:)`, có thì trả `.failed`.
  - `LinkHost`:
    - `welcome.features = chat?.acceptsAttachments == true ? ["attachments"] : []`;
    - khi `chat.send` có id thì gọi `chat.send(sessionId:text:attachments:)`.
  - `LinkClient`:
    - `public nonisolated let hostFeatures: Set<String>` (lấy từ `welcome`);
    - `public func uploadAttachment(kind: AttachmentKind, name: String, data: Data, progress: @Sendable (Int) -> Void = { _ in }) async throws -> String` — trả id; `progress` nhận số bytes đã gửi; lỗi host đi ra như `LinkClientError.rejected(code:message:)`;
    - `public func chatSend(sessionId: String, text: String, attachments: [String] = []) async throws -> ChatSendOutcome`.

- [ ] **Step 1: Viết test hỏng.** Trong `AttachmentSessionTests` dùng `FakeChatSource(acceptsAttachments: true)`, ghi lại các `ChatAttachment` nhận được:
  - `testImageAndFileReachTheChatSourceWithTheText`: client tải lên một tệp 100 000 bytes (3 mẩu) và một ảnh 10 bytes, rồi `chatSend(text: "fix this", attachments: [a, b])`. Fake nhận đúng 2 đính kèm, đúng thứ tự, kind, name và bytes; `progress` được gọi với giá trị tăng dần, giá trị cuối là 100 000.
  - `testAttachmentsWithoutTextAreSent`: `text: ""` kèm 1 id → `.submitted`.
  - `testOversizeIsRefusedAtBegin`: `size: 10_485_761` → `rejected(code: "too_large", …)`.
  - `testOutOfOrderChunkIsRefused`: tự gửi `attach.chunk` với `offset` sai → `error bad_request`.
  - `testWrongDigestDropsTheUpload`: `attach.end` sai SHA → `bad_request`, và `chat.send` dùng id đó sau đó cũng `bad_request`.
  - `testUploadIsUsedOnce`: gửi lại id đã dùng → `bad_request`.
  - `testSixthPendingUploadIsRefused`.
  - `testUploadsDieWithTheSession`: phiên mới không dùng được id của phiên cũ → `bad_request`.
  - `testHostWithoutAttachmentsAdvertisesNothing`: chat source mặc định → `hostFeatures` rỗng, `attach.begin` → `unsupported`.
- [ ] **Step 2: Chạy và xác nhận test hỏng**: `swift test --package-path shellx-link --filter AttachmentSessionTests` → FAIL.
- [ ] **Step 3: Làm cho test qua**
  - `AttachmentUploads` là một struct thuộc state của `runSession`. Nó giữ `[id: (kind, name, size, data, finished)]`, id là UUID string do host tạo.
  - Kiểm tra `chat.send`: chuyển các upload thành `ChatAttachment` và xoá chúng *trước* khi gọi chat source.
  - Điều kiện chữ hiện tại (`1...maxSendTextBytes`) đổi thành `0...` khi có 1–5 id, và vẫn `1...` khi không có id. Hơn 5 id thì `bad_request`.
  - Thứ tự gửi của mỗi session vẫn đi qua `sendOrder` như hiện nay.
- [ ] **Step 4: Chạy lại**: `swift test --package-path shellx-link` → PASS.
- [ ] **Step 5: Commit**: `feat(shellx-link): hosts take attachment uploads and hand them to chat.send`

### Task 3: Mac nhận đính kèm

**Files:**
- Modify: `Packages/macOS/CmuxTerminal/Sources/CmuxTerminal/Services/Pasteboard/TerminalPasteboardService+ImageMaterialization.swift` (hoặc file mới `TerminalPasteboardService+Attachments.swift` cùng thư mục)
- Modify: `Sources/TerminalController+MobileChat.swift` (`agentChatSend`), `Sources/TerminalController.swift` (`v2MobileTerminalPasteImage` hoặc một hàm anh em cho tệp)
- Modify: `Sources/ShellX/Remote/Link/ShellXLinkChatSource.swift`
- Test: `Packages/macOS/CmuxTerminal/Tests/CmuxTerminalTests/Services/TerminalPasteboardServiceTests.swift`, `cmuxTests/ShellXLinkChatSourceTests.swift`

**Interfaces:**
- Consumes: `ChatAttachment`, `AgentChatSource.acceptsAttachments` và `send(sessionId:text:attachments:)` (Task 2).
- Produces:
  - `public func saveAttachmentData(_ data: Data, fileName: String) -> String?` trên `TerminalPasteboardService`: trả đường dẫn đã escape cho shell; trả nil khi rỗng, > `maxClipboardImageSize`, hoặc ghi lỗi.
  - Dict đính kèm của `agentChatSend` nhận thêm `"kind": "file"` cùng `"name"`. Không có `kind` thì vẫn là ảnh như cũ.
  - `ShellXLinkChatSource`:
    - `nonisolated var acceptsAttachments: Bool { true }`;
    - `Send` đổi thành `(String, String, [ChatAttachment]) async -> V2CallResult`.

- [ ] **Step 1: Viết test hỏng**
  - `saveAttachmentDataKeepsHostileNamesInsideItsFolder` (Swift Testing, trong `TerminalPasteboardServiceTests`): với các tên `"../../.ssh/authorized_keys"`, `"a\u{0}b"`, `"..."`, `String(repeating: "é", count: 300)` và `""`, đường dẫn trả về (bỏ escape) nằm đúng một cấp dưới `scratch/shellx-attachments/<uuid>/`; tên cuối không chứa `/`, không bắt đầu bằng `.` và dài ≤ 100 bytes; tên rỗng thành `file`; bytes khớp; quyền `0o600`.
  - `saveAttachmentDataRefusesOversize`: 10 485 761 bytes → nil, không tạo thư mục nào.
  - `ShellXLinkChatSourceTests.testAttachmentsGoToTheSendCommandInOrder`: send command giả nhận đúng mảng `ChatAttachment`.
  - `testAttachmentsToADeadSessionWriteNothing`: phiên không live → `.notFound`, send command không được gọi.
- [ ] **Step 2: Chạy và xác nhận test hỏng**
  - `swift test --package-path Packages/macOS/CmuxTerminal --filter TerminalPasteboardServiceTests` → FAIL.
  - `scripts/shellx/test-app.sh ShellXLinkChatSourceTests` → FAIL.
- [ ] **Step 3: Làm cho test qua**
  - Lọc tên theo mục Quyết định; ghi file với quyền `0o600`; `registerOwnedTemporaryImageFile` cho file đó.
  - Trong `agentChatSend`, một đính kèm `kind == "file"` thì lưu bằng `saveAttachmentData` rồi gõ đường dẫn, dùng cùng cách tách bằng dấu cách và cùng nhánh lỗi như ảnh.
  - `ShellXLinkChatSource.send(sessionId:text:attachments:)`:
    - kiểm `hasLiveAgent` trước;
    - đổi ảnh thành `["data_b64", "format": <đuôi tên, mặc định "jpg">]`;
    - đổi tệp thành `["kind": "file", "name", "data_b64"]`;
    - `send(sessionId:text:)` cũ gọi bản mới với `[]`.
  - Không log tên hay bytes.
- [ ] **Step 4: Chạy lại** hai lệnh ở Step 2 → PASS; rồi chạy `python3 scripts/verify-local.py` theo phạm vi thay đổi.
- [ ] **Step 5: Commit**: `feat(shellx): the Mac pastes phone attachments into the agent's prompt`

### Task 4: Lõi iPhone (ShellXAppCore)

**Files:**
- Create: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Composer/OutgoingAttachment.swift`
- Modify: `…/Link/MachineConnection.swift` (giữ `hostFeatures` của client hiện tại), `…/Link/MachineHub.swift`, `…/Home/HomeModel.swift`, `…/Home/HomeEntry.swift`, `…/Agent/AgentThreadModel.swift`, `…/Composer/ComposerValidation.swift` (hoặc nơi đang định nghĩa nó)
- Modify: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppTestSupport/FakeMacChat.swift`, `FakeMac.swift`
- Test: `…/Tests/ShellXAppCoreTests/AttachmentSendTests.swift`, `HomeModelTests.swift`

**Interfaces:**
- Consumes: `LinkClient.hostFeatures`, `uploadAttachment`, `chatSend(sessionId:text:attachments:)` (Task 2).
- Produces:
  - `public struct OutgoingAttachment: Identifiable, Equatable, Sendable { public let id: UUID; public let kind: AttachmentKind; public let name: String; public let data: Data }`
  - `ComposerValidation`: thêm `public init(_ text: String, attachmentCount: Int)`. Chữ rỗng mà có ≥1 đính kèm thì `.ok("")`. Thêm `case tooManyAttachments` (> 5) và `case attachmentTooLarge(name: String)`, cùng `static func check(_ attachments: [OutgoingAttachment]) -> ComposerValidation?`.
  - `MachineHub`:
    - `public func acceptsAttachments(_ machineID: String) -> Bool`;
    - `public func chatSend(_ ref: SessionRef, text: String, attachments: [OutgoingAttachment], progress: @Sendable (Double) -> Void) async throws -> ChatSendOutcome` — tải lên rồi gửi trong cùng một `withLink`. Bản text-only cũ vẫn giữ.
  - `HomeEntry.Content.userSaid(text:target:viaVoice:attachments: [String]?)`: tên các đính kèm; `nil` cho dữ liệu cũ (decode được dữ liệu đã lưu).
  - `HomeModel`:
    - `submit(_ text: String, attachments: [OutgoingAttachment] = [], to:viaVoice:) async -> ComposerValidation`;
    - `public private(set) var uploadProgress: Double?`.
  - `AgentThreadModel.send(_ text: String, attachments: [OutgoingAttachment] = [], viaVoice:) async -> AgentSendResult`.
  - `AgentSendResult.keepsDraft` cũng đúng khi upload lỗi.
  - `FakeMac`: `public init(…, acceptsAttachments: Bool = true)`, `public var receivedAttachments: [ChatAttachment]`.

- [ ] **Step 1: Viết test hỏng (`AttachmentSendTests` với `FakeMac`)**
  - `testPhotoAndTextReachTheMac`: `HomeModel.submit("sửa lỗi này", attachments: [img])` → `FakeMac.receivedAttachments` có đúng một phần tử, với `kind`, `name` và `data` bằng của `img`; entry là `.userSaid(text: "sửa lỗi này", …, attachments: ["shot.jpg"])`.
  - `testAttachmentOnlyMessageIsSent`.
  - `testSixAttachmentsAreRefusedOnThePhone`: trả `.tooManyAttachments`, không gọi gì tới Mac.
  - `testOversizeAttachmentIsRefusedOnThePhone`.
  - `testFailedSendGivesTheAttachmentsBack`: Mac offline → `AgentThreadModel.send` trả `.offline` (`keepsDraft`); `HomeModel` ghi note lỗi và không thêm entry `userSaid`.
  - `testAttachButtonOnlyForMacsThatAcceptThem`: `hub.acceptsAttachments` true với `FakeMac()`, false với `FakeMac(acceptsAttachments: false)`.
  - `HomeModelTests.testOldHistoryWithoutAttachmentsStillLoads`: JSON đã lưu kiểu cũ decode được, `attachments == nil`.
- [ ] **Step 2: Chạy và xác nhận test hỏng**: `shellx-ios/scripts/dev.sh test core` → FAIL.
- [ ] **Step 3: Làm cho test qua**
  - Validation chạy trước mọi call.
  - Upload xong mới gửi, tất cả trong một `withLink`.
  - `progress` là số bytes đã gửi chia tổng số bytes.
  - `uploadProgress` về `nil` khi xong.
- [ ] **Step 4: Chạy lại**: `shellx-ios/scripts/dev.sh test core` → PASS.
- [ ] **Step 5: Commit**: `feat(shellx-ios): send attachments with a message through the hub`

### Task 5: Giao diện đính kèm trên iPhone

**Files:**
- Create: `shellx-ios/ShellX/UI/Composer/AttachmentPreparer.swift`, `AttachMenu.swift`, `AttachmentStrip.swift`
- Modify: `shellx-ios/ShellX/UI/Composer/ComposerBar.swift`, `ShellX/UI/Home/{HomeScreen,HomeView,HomeActions,UserMessageBubble}.swift`, `ShellX/UI/Agent/{AgentScreen,AgentView}.swift`, `ShellX/Localizable.xcstrings`
- Modify: `shellx-ios/ShellX/Debug/DemoComposition.swift` (FakeMac của demo nhận đính kèm)
- Test: `shellx-ios/ShellXTests/AttachmentPreparerTests.swift`, `MicButtonRenderTests.swift` (composer), `HomeRenderTests.swift`

**Interfaces:**
- Consumes: `OutgoingAttachment`, `ComposerValidation(_:attachmentCount:)`, `MachineHub.acceptsAttachments`, `HomeModel.submit(_:attachments:to:viaVoice:)`, `HomeModel.uploadProgress`, `AgentThreadModel.send(_:attachments:viaVoice:)` (Task 4).
- Produces:
  - `enum AttachmentPreparer`:
    - `static func image(from data: Data, name: String) throws -> OutgoingAttachment` — ImageIO thumbnail `maxPixelSize 2000` có `CreateThumbnailWithTransform`, rồi JPEG 0.85;
    - `static func file(at url: URL) throws -> OutgoingAttachment` — bọc bằng security-scoped access; lớn hơn 10 MiB thì throw.
  - `ComposerBar` thêm hai tham số:
    - `attachments: Binding<[OutgoingAttachment]>?` — nil thì không có nút "+";
    - `sending: Double?` — tiến độ, không nil thì khoá ô nhập.
  - `send` của ComposerBar đổi thành `(String, [OutgoingAttachment]) -> Void`.
  - `UserMessageBubble` nhận `attachments: [String]?`.

- [ ] **Step 1: Viết test hỏng**
  - `testLargePhotoIsDownscaledToJPEG`: ảnh PNG 4032×3024 tạo trong test → kết quả là JPEG (bắt đầu bằng `FF D8`), cạnh dài 2000, `name` đuôi `.jpg`.
  - `testSmallPhotoKeepsItsSize`: 800×600 giữ nguyên 800×600.
  - `testFileOverTenMiBIsRefused`.
  - Render tests (light/dark, en/vi qua `SnapshotWriter`):
    - `composer-attachments`: 1 ảnh + 1 tệp, chưa có chữ;
    - `composer-sending`: `sending: 0.4`;
    - `home-attachments`: bong bóng có dòng "📎 2 tệp" và một bong bóng chỉ có đính kèm.
- [ ] **Step 2: Chạy và xác nhận test hỏng**: `shellx-ios/scripts/dev.sh test app` → FAIL.
- [ ] **Step 3: Làm cho test qua**
  - **Nút "+":** `Menu` có hai mục:
    - "Ảnh" mở `PhotosPicker(selection:maxSelectionCount: 5 - attachments.count, matching: .images)`, tải mỗi mục bằng `loadTransferable(type: Data.self)`;
    - "Tệp" mở `.fileImporter(allowedContentTypes: [.item], allowsMultipleSelection: true)`.
  - **Chuẩn bị ảnh/tệp:** chạy ngoài main actor. Lỗi (quá lớn, đọc không được) hiện đúng dòng chữ lỗi đỏ như "Too long" hiện có.
  - **Nút bên phải:** là Gửi khi `!text.isEmpty || !attachments.isEmpty`. Khi `sending != nil` nút hiện `ProgressView(value:)` tròn.
  - **Màn hình chính:** giữ `@State attachments` cạnh `draft`. Chỉ truyền binding khi Mac của đích nhận đính kèm (`hub.acceptsAttachments(target.machineID)`). Gửi xong thì xoá; lỗi thì để nguyên.
  - **Màn hình agent:** như màn hình chính. Trả lại chữ và đính kèm theo `keepsDraft`.
  - **Chuỗi mới (en / vi):**
    - `composer.attach` "Attach" / "Đính kèm";
    - `composer.attach.photos` "Photos" / "Ảnh";
    - `composer.attach.files` "Files" / "Tệp";
    - `composer.attachment.remove %@` "Remove %@" / "Bỏ %@";
    - `composer.attach.tooLarge %@` "%@ is over 10 MB" / "%@ lớn hơn 10 MB";
    - `composer.attach.tooMany` "Up to 5 attachments" / "Tối đa 5 tệp đính kèm";
    - `composer.attach.unreadable %@` "Can't read %@" / "Không đọc được %@";
    - `home.attachments %lld` (plural) "📎 %lld file(s)" / "📎 %lld tệp";
    - `composer.sending` (VoiceOver) "Sending attachments" / "Đang gửi tệp đính kèm".
- [ ] **Step 4: Chạy lại**
  - `shellx-ios/scripts/dev.sh test all` → PASS, kể cả licence, strings và bản Release không lọt code Debug.
  - Xem ảnh render bằng `dev.sh screenshots <scratch>`.
- [ ] **Step 5: Commit**: `feat(shellx-ios): attach photos and files to a message`

### Task 6: Thử trên iPhone (người dùng, ngoài vòng subagent)

- [ ] Cài bản demo bằng `shellx-ios/scripts/dev.sh device --demo --device-id <id>`. Chọn 2 ảnh + 1 tệp, gửi kèm chữ, xem thumbnail, nút ✕, vòng tiến độ, và bong bóng "📎".
- [ ] Đầu-cuối với Mac thật thì cần relay2 + route phone đã deploy (P3 Task 11): ảnh phải hiện `[Image #1]` trong Claude Code; tệp hiện đường dẫn, và Claude đọc được (có thể hỏi quyền đọc ngoài workspace; quyền đó tới điện thoại như một thẻ "Cần bạn").
