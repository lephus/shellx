# ShellX Link P2: Mac phục vụ điện thoại thật

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Một "điện thoại" (vai do `shellx-link-probe` đóng) làm được trọn đường đi qua `relay.shellx.pro`:
- đăng nhập tài khoản ShellX với tư cách thiết bị `mobile`;
- ghép cặp với Mac bằng QR, Mac đồng ý tại chỗ;
- tự xin vé kết nối;
- thấy trạng thái các phiên Claude Code;
- duyệt quyền, trả lời câu hỏi, duyệt plan;
- chat với agent (gửi, nhận tin, dừng).

**Architecture:**
- **Relay Node** nhận thiết bị `mobile`. Thêm hai bảng `phone_pairings` và `phone_grants`. Điện thoại có grant thì được cấp vé `connect` lane `link`.
- **Ghép cặp:**
  - QR trên Mac chứa host key và một mã dùng một lần.
  - Điện thoại gửi qua relay khoá của mình kèm bằng chứng HMAC tính từ mã đó.
  - Mac kiểm bằng chứng, người dùng bấm Đồng ý, rồi Mac lưu khoá điện thoại vào Keychain (theo bundle id và theo tài khoản).
  - Sau cùng Mac báo relay cấp grant. Relay chỉ gỡ được tin cậy, không thêm được.
- **`shellx-link`:**
  - giao thức có thêm `call_id`, luật mở rộng enum, trả lời question và exit_plan, phiên agent và chat;
  - target mới `ShellXLinkAccount` là phần điện thoại: gọi HTTP relay, ghép cặp, xin vé, kiểm slot;
  - relay transport bắt buộc `wss`, và đăng ký host theo kiểu make-before-break.
- **Mac** nối nguồn trạng thái và chat có sẵn (`AgentChatTranscriptService`) vào ShellX Link.

**Tech Stack:**
- Swift 6.0 (macOS 14 / iOS 17), CryptoKit, `URLSession`, Security (Keychain);
- TypeScript Hono + vitest + SQLite (relay);
- Rust (`shellx-core`, `fake-api`).

**Spec:** `docs/superpowers/specs/2026-10-22-shellx-ios-agent-remote-design.md` (§2, §3 "Lần đầu mở", §7.2, §7.4, §7.6). Ledger: `docs/superpowers/ledgers/shellx-ios.md` (mục "D-iOS-1" và "Mang sang P2"). Plan P1: `docs/superpowers/plans/2026-10-22-shellx-link-p1-spike.md`.

## Global Constraints

- `shellx-link/` không phụ thuộc đường dẫn nào ngoài chính nó và không chép code từ `ios/`, `Packages/iOS/`, `Packages/Shared/`, `cmux-tui/`. `scripts/shellx/check-link-license.sh` phải luôn xanh. Target mới `ShellXLinkAccount` cũng theo luật này và không import `CmuxAgentChat` hay bất kỳ code GPL nào: app iOS sẽ dùng lại nó (spec §7.1, G6).
- Code liên kết vào app (`Sources/`, `Packages/`, `shellx-link/`) phải tương thích Swift 6.0 (`skills/cmux-architecture/references/swift-6-0-compatibility.md`).
- Không dùng dịch vụ Manaflow nào.
- Mục tiêu độ trễ (spec §7.4), p95, đo qua relay thật:
  - bấm Cho phép → hook nhận quyết định: < 500 ms;
  - trạng thái đổi trên Mac → điện thoại: < 1 s;
  - xử lý ở một bên → bên kia gỡ: < 2 s.
  - Không đạt thì báo người dùng, không lặng lẽ hạ mục tiêu.
- Mọi quyết định đều idempotent (A1).
- v1 chỉ phục vụ Claude Code: host chỉ liệt kê việc chờ và phiên có agent `claude`. Kiểu dữ liệu và giao thức vẫn trung lập với agent; thêm Codex sau chỉ là thêm adapter trên Mac.
- **[người viết plan]** Trong P2, điện thoại không bao giờ nhận mode `bypass` (permission) hay `bypassPermissions` (exit plan). Hai mode này chỉ bấm được trên Mac.
- Điện thoại chỉ được tin khi có đủ ba điều kiện:
  1. cùng tài khoản;
  2. có bằng chứng từ QR đang hiện trên chính Mac đó;
  3. người dùng bấm Đồng ý trên Mac.
- Vé, khoá, mã ghép cặp, token và mật khẩu không bao giờ được log, in ra hay nằm trên dòng lệnh. Probe đọc mật khẩu và QR từ stdin hoặc file.
- Mọi chữ hiển thị phải có cả vi và en (`skills/cmux-localization`), kèm báo cáo audit localization.
- Build và chạy app:
  - chỉ dùng tagged build (`CMUX_DEV_BACKEND_MODE=local`, tag `link`), không chạy `xcodebuild` trần, không đụng ShellX hay cmux đang chạy của người dùng;
  - file Swift mới trong `Sources/` phải thêm vào app target theo `skills/cmux-dev-workflow`;
  - sau khi thêm file trong `cmuxTests/` thì chạy `scripts/sync-test-wiring`.
- Socket method mới theo `skills/cmux-socket-policy`: không cướp focus. Method DEBUG không có trong bản Release.
- Nhánh làm việc `feat/shellx-link-p2` tách từ `develop`, mở PR vào `develop`. Push `develop` thì được. `main` là deploy production: hỏi người dùng trước khi bất cứ thứ gì lên `main` hoặc VPS.

## Review Focus

1. **Gỡ ghép cặp khi phiên đang chạy:** phiên của khoá đó đóng ngay, handshake sau đó bị từ chối, xin vé nhận `not_granted`. Test ở Task 8 (`testDisconnectClosesLiveSessionsOfKey`) và Task 9 (`testRevokeUntrustsAndDisconnectsBeforeRelayCall`).
2. **QR cũ, QR bị chụp lại, hai điện thoại quét cùng một QR:** yêu cầu mang bằng chứng của mã cũ không bao giờ hiện lên Mac và bị từ chối; mỗi QR chỉ ghép được một điện thoại. Test ở Task 9 (`testProofForOldOfferIsDeniedNotShown`, `testOfferIsSingleUse`).
3. **Gia hạn đăng ký mỗi 120 s trong lúc điện thoại đang kết nối:** đăng ký mới sống trước khi đăng ký cũ đóng, và điện thoại kết nối đúng lúc chuyển vẫn vào được. Test ở Task 4 (`testRenewalOverlapsOldRegistration`, `testConnectRetriesSlotOffline`).
4. **Một lệnh trên điện thoại hết giờ chờ, rồi kết quả đến muộn:** kết quả muộn bị bỏ, lệnh sau không nhận nhầm. Test ở Task 2 (`testLateResultOfTimedOutCallIsDropped`).
5. **Chat rất lớn** (kết quả tool 1 MB, 200 tin): chữ mỗi mục cắt còn 4096 byte, trang lịch sử tự thu nhỏ cho vừa 65 519 byte. Test ở Task 3 (`testChatEntryTextTruncated`, `testHistoryPageShrinksToFit`).

---

### Task 1: Bật relay2 trên VPS và đo WAN bằng code P1

Task này chạy trên code P1 ở đầu `develop` (worktree riêng), trước khi Task 9 bỏ `debug_invite`. Đây là cổng của P2: không đạt mục tiêu thì dừng lại và báo người dùng.

**Files:**
- Modify: `docs/superpowers/ledgers/shellx-ios.md` (mục D-iOS-1, thêm "Đo WAN")

**Interfaces:**
- Consumes: probe P1 (`keygen`, `watch`, `bench`) và `shellx.link.debug_invite`, như ledger mục "Spike P1".
- Produces: D-iOS-1 được chốt (đạt hoặc không đạt) bằng số đo WAN.

- [ ] **Step 1: Kiểm pin.** Chạy `git merge-base --is-ancestor 08de0bb35efbd46e3cade25446fdb6ffffac41bc origin/main`. Kỳ vọng exit 0. Ngày 2026-10-27, `main` đã chứa pin này.
- [ ] **Step 2: Tạo source tarball.** Chạy `scripts/shellx/relay2/source-tarball.sh 08de0bb35efbd46e3cade25446fdb6ffffac41bc <thư mục scratch>`. Đưa cho người dùng đường dẫn, sha256 và lệnh `scp` theo `deploy/README.md` mục "Relay v2" bước 2.
- [ ] **Step 3: Người dùng làm trên VPS** theo `deploy/README.md` mục "Relay v2", bước 1–5, và danh sách trong ledger:
  - `CMUX_RELAY_HMAC_SECRET` đặt tay, không qua chat;
  - timeout nginx 330 s;
  - build relay2;
  - `COMPOSE_PROFILES=relay2`;
  - `RELAY2_ENABLED=true`.

  Agent không bao giờ thấy secret. Hỏi người dùng trước khi deploy chạy.
- [ ] **Step 4: Kiểm relay2 đã sống.**
  - Chạy `curl -sS -o /dev/null -w '%{http_code}\n' https://relay.shellx.pro/v2/relay`. Kỳ vọng khác 404 của relay Node. Ghi mã nhận được vào ledger.
  - Người dùng chạy lệnh kiểm `nginx -T` ở README bước 4. Kỳ vọng thấy khối `location = /v2/relay`.
- [ ] **Step 5: Bật Mac host.** Tagged build `link` từ `develop`, chạy với `SHELLX_REMOTE_MACHINES=1` và API mặc định (production). Người dùng tự đăng nhập tài khoản ShellX trong sheet đăng nhập của app. Kỳ vọng log có `link host registering slot`.
- [ ] **Step 6: Đo.** Mac nối hotspot 4G của iPhone (tắt Wi-Fi trên iPhone), rồi chạy hai lần `bench --count 50`, mỗi lần bằng invite mới (`keygen` → `debug_invite` → `bench --socket …`), như ledger mục "Spike P1".
  - Lúc này cả hai chặng Mac↔VPS đều đi 4G, nên số đo là **cận trên** của thực tế (Mac thật ở nhà dùng mạng cố định). Ghi rõ điều này.
  - Đo thêm một lần trên Wi-Fi nhà để so.
- [ ] **Step 7: Cổng.** Đạt khi Cho phép → hook có p95 < 500 ms và Mac đổi → client có p95 < 1 s.
  - Đạt: ghi D-iOS-1 là "chốt".
  - Không đạt: dừng P2 và đưa số đo cho người dùng.
- [ ] **Step 8: Commit** (`docs(shellx-ios): relay2 live, WAN bench closes D-iOS-1`).

### Task 2: Giao thức: `call_id`, luật mở rộng, trả lời question và exit_plan

**Files:**
- Modify: `shellx-link/spec/PROTOCOL.md` (§3 thêm "Mở rộng" và `call_id`; §4 bảng message, PendingItem, Enums; §5 luật 3; §7 lỗi kèm `call_id`)
- Create: `shellx-link/Sources/ShellXLinkCore/Messages/LinkDecision.swift`
- Modify: `shellx-link/Sources/ShellXLinkCore/Messages/LinkMessage.swift`, `PendingItem.swift`, `LinkCodec.swift`
- Modify: `shellx-link/spec/vectors/messages.json`
- Modify: `shellx-link/Sources/ShellXLinkSession/LinkHost.swift`, `LinkClient.swift`, `AgentFeedSource.swift`
- Modify: `shellx-link/Sources/shellx-link-probe/main.swift` (chỉ sửa cho biên dịch được, `approve` gửi `.permission(.once)`)
- Modify: `Sources/ShellX/Remote/Link/ShellXLinkFeedSource.swift` (đổi chữ ký; chỉ xử lý `.permission`, các loại khác trả `.unknown` cho tới Task 10; điền `modes`)
- Test: `shellx-link/Tests/ShellXLinkCoreTests/LinkCodecTests.swift`, `shellx-link/Tests/ShellXLinkSessionTests/LinkSessionTests.swift`, `FakeFeedSource.swift`, `cmuxTests/ShellXLinkFeedSourceTests.swift`

**Interfaces:**
- Consumes: codec, `LinkHost`, `LinkClient` của P1.
- Produces:
  - **Enum mở.** Mỗi enum có `init(wire: String)` và `var wire: String`; chuỗi lạ thành `.other(String)`:
    - `PermissionMode`: `once`, `always`, `all`, `deny`;
    - `ExitPlanMode`: `ultraplan`, `autoAccept` = `auto_accept`, `manual`, `deny`;
    - `ReplyOutcome`: `delivered`, `alreadyHandled` = `already_handled`, `unknown`;
    - `PendingItem.Kind`: `permission`, `question`, `exitPlan` = `exit_plan`.
  - **`LinkDecision`:** `.permission(PermissionMode)`, `.question(selections: [String])`, `.exitPlan(ExitPlanMode, feedback: String?)`, `.other(kind: String)`. Trên wire:
    - `{"kind":"permission","mode":"once"}`;
    - `{"kind":"question","selections":["<label>"]}`;
    - `{"kind":"exit_plan","mode":"manual","feedback":"…"}`.
  - **`LinkMessage`:**
    - `.snapshotGet(callId:)`;
    - `.snapshot(callId:revision:pending:)`;
    - `.reply(callId:requestId:decision:)`;
    - `.replyResult(callId:requestId:outcome:)`;
    - `.error(code:message:callId: String?)`.
  - **`PendingItem`** thêm:
    - `modes: [String]` (bắt buộc, có thể rỗng);
    - `questions: [PendingQuestion]?`;
    - `planPreview: String?` (≤ 8192 byte; luật thu nhỏ §6 áp dụng như `tool_input_preview`, bước 3 bỏ cả hai).
  - **Câu hỏi:** `PendingQuestion { id, header?, prompt, multiSelect (multi_select), options: [PendingQuestionOption { id, label, description? }] }`.
  - **Codec:** `LinkCodecError.badJSON(callId: String?)`, và `LinkCodec.maxCallIdBytes = 64`.
  - `AgentFeedSource.reply(requestId: String, decision: LinkDecision) async -> ReplyOutcome`.
  - `LinkClient.reply(requestId: String, decision: LinkDecision) async throws -> ReplyOutcome`.
  - `LinkClientError.remote(code: String, message: String)`: host trả `error` có `call_id` cho đúng lệnh đó.

**Luật ghi vào PROTOCOL.md:**
- **Mở rộng:**
  - mọi trường enum chuỗi (`kind`, `mode`, `outcome`, `decision.kind`, và các enum Task 3 thêm) đều là enum mở: giá trị lạ vẫn giải mã được, không phải `bad_json`;
  - được thêm trường tuỳ chọn bất cứ lúc nào;
  - thêm trường bắt buộc hoặc đổi nghĩa một trường thì phải tăng `v`.
  - `v` vẫn là 1: P2 sửa v1 trước khi phát hành, vì chưa có bản P1 nào ra ngoài spike.
- **`call_id`:**
  - client tự chọn, 1–64 byte, không trùng với lệnh nào khác của nó đang chờ trong phiên;
  - host trả đúng một câu trả lời mang lại `call_id` đó;
  - client bỏ câu trả lời có `call_id` mà nó không còn chờ (đã hết giờ);
  - luật P1 "trả `agent.reply.result` theo thứ tự đến cho cùng `request_id`" vẫn giữ.
- **§5 luật 3 viết lại:** trả `unknown` và giữ nguyên item khi gặp một trong các trường hợp:
  - `decision.kind` khác `kind` của item;
  - mode không có trong `modes` của item;
  - có selection không trùng `label` nào trong `questions` của item;
  - `decision.kind` lạ.
- **§7:** frame host không giải mã được thì host trả `error` `bad_request`, kèm `call_id` khi đọc được nó.
- **Hướng dẫn client:** item có `kind` lạ thì hiện thẻ chung "Mở trên Mac", không có nút.

- [ ] **Step 1: Viết PROTOCOL.md và vector.**
  - `vectors` mới: `reply_permission`, `reply_question`, `reply_exit_plan`, `reply_result`, `snapshot_get`, `snapshot_with_question`, `snapshot_with_plan`, `error_with_call_id`.
  - `decode_only`:
    - `reply_unknown_mode` → `.permission(.other("bypass2"))`;
    - `pending_unknown_kind`;
    - `reply_unknown_decision_kind`.
  - `decode_errors`:
    - `reply_without_call_id` → `bad_json` (callId nil);
    - `reply_call_id_65_bytes` → `bad_json` (callId nil);
    - `reply_missing_request_id` → `bad_json` (callId `"c1"`).
- [ ] **Step 2: Viết test fail.**
  - `LinkCodecTests`: golden vector, `testUnknownEnumValuesDecodeToOther`, `testBadJSONCarriesCallId`, `testPlanPreviewShrinksLikeToolInput`.
  - `LinkSessionTests`:
    - `testReplyCarriesCallIdAndResultMatches`;
    - `testLateResultOfTimedOutCallIsDropped`: `FakeFeedSource` trả lời chậm 200 ms, `requestTimeout` 50 ms; lệnh thứ hai cho cùng request nhận kết quả của chính nó;
    - `testHostEchoesCallIdOnBadRequest`: gửi frame thô qua `SecureChannel`;
    - `testQuestionDecisionReachesFeed`;
    - `testExitPlanDecisionCarriesFeedback`.

  Chạy `swift test --package-path shellx-link`. Kỳ vọng FAIL.
- [ ] **Step 3: Cài đặt.**
  - Bỏ `lateReplyResults`. Waiter của `LinkClient` đổi thành `[String: Waiter<LinkMessage>]` theo `call_id`; id là `"c<số đếm>"`.
  - Mac `ShellXLinkFeedSource`: `modes` của permission là các mode `allows(...)` cho phép, trừ `bypass`.
- [ ] **Step 4: Chạy lại.**
  - `swift test --package-path shellx-link`. Kỳ vọng PASS.
  - `scripts/shellx/test-app.sh ShellXLinkFeedSourceTests`. Kỳ vọng PASS.
- [ ] **Step 5: Commit** (`feat(shellx-link): call ids, open enums, question and plan replies`).

### Task 3: Giao thức: phiên agent và chat

**Files:**
- Modify: `shellx-link/spec/PROTOCOL.md` (bảng message, kiểu `AgentSession` và `ChatEntry`, luật thu nhỏ frame)
- Create: `shellx-link/Sources/ShellXLinkCore/Messages/AgentSession.swift`, `ChatEntry.swift`
- Modify: `LinkMessage.swift`, `LinkCodec.swift`, `spec/vectors/messages.json`
- Create: `shellx-link/Sources/ShellXLinkSession/AgentSessionSource.swift`, `AgentChatSource.swift`
- Modify: `LinkHost.swift`, `LinkClient.swift`
- Test: `LinkCodecTests.swift`, `LinkSessionTests.swift`; Create: `shellx-link/Tests/ShellXLinkSessionTests/FakeSessionSource.swift`, `FakeChatSource.swift`

**Interfaces:**
- Consumes: `call_id`, enum mở, `LinkClientError.remote` (Task 2).
- Produces:
  - **Message mới:**

    | `t` | Bên gửi | Trường |
    | --- | --- | --- |
    | `agent.sessions.get` | client | `call_id` |
    | `agent.sessions` | host | `call_id`, `revision`, `sessions` |
    | `agent.sessions.changed` | host | `revision`, `upserted`, `removed` (mảng `session_id`) |
    | `chat.history.get` | client | `call_id`, `session_id`, `before_seq` (tuỳ chọn), `limit` (1–50) |
    | `chat.history` | host | `call_id`, `session_id`, `entries`, `has_more` |
    | `chat.entries` | host | `session_id`, `entries` (upsert theo `id`) |
    | `chat.send` | client | `call_id`, `session_id`, `text` (1–16 384 byte) |
    | `chat.send.result` | host | `call_id`, `outcome` |
    | `chat.interrupt` | client | `call_id`, `session_id`, `hard` (bool) |
    | `chat.interrupt.result` | host | `call_id`, `outcome` |

    Trong Swift, mỗi dòng là một case `LinkMessage` cùng tên kiểu camelCase: `.sessionsGet(callId:)`, `.sessions(callId:revision:sessions:)`, `.sessionsChanged(revision:upserted:removed:)`, `.chatHistoryGet(callId:sessionId:beforeSeq:limit:)`, `.chatHistory(callId:sessionId:entries:hasMore:)`, `.chatEntries(sessionId:entries:)`, `.chatSend(callId:sessionId:text:)`, `.chatSendResult(callId:outcome:)`, `.chatInterrupt(callId:sessionId:hard:)`, `.chatInterruptResult(callId:outcome:)`.
  - `revision` của phiên agent theo đúng luật §4 của `agent.changed`, nhưng dùng bộ đếm riêng.
  - **`AgentSession`** gồm:
    - `sessionId`, `agent`, `workspaceId`, `workspaceTitle`;
    - `title?`;
    - `state: AgentState` (enum mở: `idle`, `working`, `needsInput` = `needs_input`, `ended`);
    - `stateSinceMs: Int64?`, `lastActivityMs: Int64?`.
  - **`ChatEntry`** gồm:
    - `id`, `seq: Int`;
    - `role: ChatEntryRole` (enum mở: `user`, `agent`, `system`);
    - `kind: ChatEntryKind` (enum mở: `prose`, `thought`, `toolUse` = `tool_use`, `status`, `other`);
    - `text`, `truncated: Bool?`, `toolName: String?`, `tsMs: Int64`.

    `ChatEntry.maxTextBytes = 4096`. `static func cut(_ text: String) -> (text: String, truncated: Bool)` cắt chữ còn tối đa `maxTextBytes` byte, đúng ranh giới Unicode scalar. Bên tạo entry đặt `truncated = true` khi có cắt, và bỏ trường này khi không cắt.
  - **Kết quả:** `ChatSendOutcome` (enum mở: `submitted`, `notFound` = `not_found`, `busy`, `failed`) và `ChatInterruptOutcome` (`sent`, `notFound`, `failed`).
  - **Nguồn dữ liệu cho host:**
    - `protocol AgentSessionSource: Sendable`, gồm:
      - `func sessions() async -> (revision: Int, sessions: [AgentSession])`;
      - `func sessionChanges() -> AsyncStream<(revision: Int, upserted: [AgentSession], removed: [String])>`, multicast như `AgentFeedSource.changes()`.
    - `protocol AgentChatSource: Sendable`, gồm:
      - `func history(sessionId: String, beforeSeq: Int?, limit: Int) async -> (entries: [ChatEntry], hasMore: Bool)?` (nil nghĩa là không có phiên này);
      - `func send(sessionId: String, text: String) async -> ChatSendOutcome`;
      - `func interrupt(sessionId: String, hard: Bool) async -> ChatInterruptOutcome`;
      - `func entries() -> AsyncStream<(sessionId: String, entries: [ChatEntry])>`.
  - `LinkHost.init(key:trustedClients:feed:sessions: (any AgentSessionSource)? = nil, chat: (any AgentChatSource)? = nil, hostVersion:machineName:)`. Thiếu nguồn nào thì lệnh tương ứng nhận `error` mã `unsupported` kèm `call_id`. Phiên không tồn tại thì nhận `error` `not_found` kèm `call_id`.
  - **`LinkClient`:**
    - `sessions() async throws -> (revision: Int, sessions: [AgentSession])`;
    - `nonisolated let sessionChanges`;
    - `chatHistory(sessionId:beforeSeq:limit:) async throws -> (entries: [ChatEntry], hasMore: Bool)`;
    - `chatSend(sessionId:text:) async throws -> ChatSendOutcome`;
    - `chatInterrupt(sessionId:hard:) async throws -> ChatInterruptOutcome`;
    - `nonisolated let chatEntries: AsyncStream<(sessionId: String, entries: [ChatEntry])>`.

**Luật thu nhỏ frame (ghi vào §6):**
- `chat.history`: bỏ dần mục cũ nhất cho tới khi vừa frame, và đặt `has_more = true`.
- `chat.entries`: chia thành nhiều frame, mỗi frame tự đủ nghĩa.
- `agent.sessions`: bỏ `title` của mọi phiên. Vẫn không vừa thì không gửi và ghi log.

- [ ] **Step 1: Viết PROTOCOL.md và vector.** Thêm một vector cho mỗi message mới, cộng hai vector decode-only: `session_unknown_state` và `entry_unknown_kind`.
- [ ] **Step 2: Viết test fail.**
  - `LinkCodecTests`: golden vector, `testChatEntryTextTruncated` (2 MB chữ còn ≤ 4096 byte, UTF-8 hợp lệ, `truncated == true`).
  - `LinkSessionTests`:
    - `testSessionsSnapshotThenChanges`;
    - `testSessionChangeGapForcesResync`;
    - `testChatHistoryRoundTrip`;
    - `testHistoryPageShrinksToFit`: 50 mục 4096 byte vẫn ra frame ≤ 65 519, có `has_more`;
    - `testChatEntriesPushedToEveryClient`;
    - `testChatSendAndInterruptOutcomes`;
    - `testMissingChatSourceAnswersUnsupported`;
    - `testUnknownSessionAnswersNotFound`.

  Chạy `swift test --package-path shellx-link`. Kỳ vọng FAIL.
- [ ] **Step 3: Cài đặt.** Host đăng ký luồng `sessionChanges` và `entries` trước khi gửi `welcome`, giống cách làm với `changes()` ở P1.
- [ ] **Step 4: Chạy lại** `swift test --package-path shellx-link`. Kỳ vọng PASS.
- [ ] **Step 5: Commit** (`feat(shellx-link): agent sessions and chat messages`).

### Task 4: Relay transport: bắt buộc `wss`, make-before-break, thử lại `slot-offline`, đọc claims của vé

**Files:**
- Modify: `shellx-link/Sources/ShellXLinkRelay/RelayControl.swift` (`RelayEndpoint.control`, `RelayError`, `RelayTicket`)
- Modify: `shellx-link/Sources/ShellXLinkRelay/RelayHostRegistration.swift`, `RelayClientConnector.swift`
- Modify: `Sources/ShellX/Remote/Link/ShellXLinkHostController.swift` (log từng `RelayHostEvent`)
- Test: `shellx-link/Tests/ShellXLinkRelayTests/RelayTicketTests.swift`, `RelayIntegrationTests.swift`; Create: `shellx-link/Tests/ShellXLinkRelayTests/RelayEndpointTests.swift`

**Interfaces:**
- Consumes: `RelayHostRegistration`, `RelayClientConnector` của P1.
- Produces:
  - `RelayError.insecureTransport(scheme: String)`. `RelayEndpoint.control(_:)` chỉ nhận `ws`, `http`, `relay+ws` khi host là loopback (`localhost`, `127.0.0.0/8`, `::1`). Ngoài ra chỉ nhận `wss`, `https`, `relay+wss`.
  - `public struct RelayTicketClaims: Equatable, Sendable { slot: String; permission: String; role: String; expiresAtUnix: Int64 }` và `extension RelayTicket { public var claims: RelayTicketClaims? }`. Thuộc tính này đọc phần giữa của `v2.<b64url JSON>.<sig>` và không kiểm chữ ký.
  - `public enum RelayHostEvent: Equatable, Sendable { case registered, renewed, failed(code: String), gaveUp(code: String) }`.
  - `RelayHostRegistration.init(relayURL:slot:renewLead: Duration = .seconds(20), maxConsecutiveFailures: Int = 5, onEvent: @escaping @Sendable (RelayHostEvent) -> Void = { _ in }, tickets:)`.
  - `RelayClientConnector.connect(relayURL:slot:ticket:slotOfflineRetries: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2)])`.

**Hành vi:**
- **Gia hạn:**
  - Mỗi đăng ký nhớ `expiresAtUnix` của vé nó dùng. Đăng ký kế tiếp mở socket mới tại thời điểm `max(lifetime / 2, lifetime − renewLead)` tính từ lúc đăng ký.
  - Khi socket mới nhận `registered` thì đóng socket cũ và phát `.renewed`. Một `register` mới trên cùng slot sẽ thắng (`cmux-relay/src/relay.rs:684-730`).
  - Gia hạn lỗi thì giữ socket cũ tới khi nó chết, và thử lại theo backoff.
- **Điểm dừng:**
  - Sau lần đăng ký đầu, mỗi lần lỗi phát `.failed(code)`. `code` là mã server, hoặc `closed`, `timeout`, `url`.
  - Lỗi liên tiếp đủ `maxConsecutiveFailures` lần thì `run` ném `RelayError.server` (hoặc lỗi cuối) và phát `.gaveUp`. Vòng ngoài của `ShellXLinkHostController` xin vé mới, chờ backoff và ghi log.
- **Thử lại `slot-offline`:** client gặp `slot-offline` thì thử lại theo `slotOfflineRetries`, dùng lại cùng vé (vé dùng lại được trong hạn của nó).

- [ ] **Step 1: Viết test fail.**
  - `RelayEndpointTests`: `testPlainWebSocketRefusedForRemoteHost`, `testLoopbackPlainAllowed`, `testSecureSchemesAllowed`.
  - `RelayTicketTests`: `testClaimsParseSlotPermissionExpiry`, `testClaimsNilForMalformedTicket`.
  - `RelayIntegrationTests`, theo đúng cách bật `cmux-relay` local mà file đang dùng:
    - `testRenewalOverlapsOldRegistration`: vé sống 6 s, `renewLead` 3 s; một client kết nối mỗi 100 ms suốt lúc chuyển đều vào được; có event `.renewed`;
    - `testConnectRetriesSlotOffline`: client kết nối 300 ms trước khi host đăng ký;
    - `testRegistrationGivesUpAfterConsecutiveFailures`: sau lần đầu, provider trả vé hỏng; `run` ném lỗi sau 5 lần.
- [ ] **Step 2: Chạy** `swift test --package-path shellx-link --filter ShellXLinkRelayTests`. Kỳ vọng FAIL.
- [ ] **Step 3: Cài đặt.** Thêm timeout 10 s cho `tearDown` của `RelayIntegrationTests` (nợ trong ledger).
- [ ] **Step 4: Chạy lại** `swift test --package-path shellx-link`. Kỳ vọng PASS.
- [ ] **Step 5: Commit** (`feat(shellx-link): wss only, make-before-break host registration, slot-offline retry`).

### Task 5: Relay v2 nhận điện thoại

**Files:**
- Create: `relay/migrations/0008_phones.sql`
- Create: `relay/src/v2/phones.ts` (`phonePairingRoutes`, `phoneGrantRoutes`)
- Modify: `relay/src/v2/guard.ts` (`requireMobile`, `phoneGrant(db, deviceId, machineId)`)
- Modify: `relay/src/v2/relay-tickets.ts` (nhánh cho `mobile`)
- Modify: `relay/src/app.ts` (gắn `/v2/phone-pairings`, `/v2/phone-grants`)
- Modify: `relay/src/http/errors.ts` (`Errors.mobileOnly()`, mã `mobile_only`, 403)
- Test: Create `relay/test/v2-phones.test.ts`, `relay/test/migrate-0008.test.ts`; Modify `relay/test/v2-relay-tickets.test.ts`

**Interfaces:**
- Consumes: `requireAuth`, `accountMachine`, `ownMachine`, `PAIRING_TTL_MS`, `PAIRING_VISIBLE_MS`, `MAX_PENDING_PER_TARGET`, `limiters.pairingCreate`, `mintTicket`/`ticketClaims` (code có sẵn).
- Produces:
  - **Bảng `phone_pairings`:**
    - `id`, `user_id`;
    - `device_id` → devices, cascade;
    - `machine_id` → machines, cascade;
    - `client_key` BLOB 32;
    - `proof` TEXT (b64url của 32 byte);
    - `status` thuộc `pending`/`approved`/`denied`/`expired`;
    - `created_at`, `decided_at`.
  - **Bảng `phone_grants`:**
    - `id`, `user_id`;
    - `device_id`, `machine_id` (cả hai cascade);
    - `client_key` BLOB 32;
    - `pairing_id`, `created_at`;
    - `UNIQUE (device_id, machine_id)`.
  - **Route** (mọi route `requireAuth`):

    | Route | Ai gọi | Kết quả |
    | --- | --- | --- |
    | `POST /v2/phone-pairings {machine_id, client_key_b64, proof_b64}` | mobile | 201 `{pairing_id}`. Yêu cầu mới hơn từ cùng điện thoại tới cùng máy thay yêu cầu cũ. Tối đa 10 yêu cầu chờ mỗi máy. Rate limit theo device. |
    | `GET /v2/phone-pairings/:id` | mobile (người gửi) | `{status}`, và khi `approved` có thêm `machine: {machine_id, name, link_slot}` |
    | `GET /v2/phone-pairings?role=target` | desktop | `{pairings: [{pairing_id, device_name, platform, client_key_b64, proof_b64, created_at_unix}]}` gửi tới máy của caller, chỉ yêu cầu `pending` còn hạn |
    | `POST /v2/phone-pairings/:id/approve` | desktop của máy đích | 204, upsert grant |
    | `POST /v2/phone-pairings/:id/deny` | desktop của máy đích, hoặc mobile người gửi | 204 |
    | `GET /v2/phone-grants` | mobile | `{grants: [{grant_id, machine_id, name, platform, online, link_slot, fingerprint}]}` |
    | `GET /v2/phone-grants` | desktop | `{grants: [{grant_id, device_id, device_name, platform, client_key_b64, created_at_unix, last_seen_unix}]}` của máy mình |
    | `DELETE /v2/phone-grants/:id` | mobile chủ grant, hoặc desktop của máy | 204 |

  - **`POST /v2/relay/tickets` cho mobile:**
    - body `{permission: "connect", lane: "link", target_machine_id}`;
    - không có grant thì `not_granted`;
    - `register` thì 403;
    - thiếu `lane: "link"` thì 400;
    - vé có `slot` là `link_slot` của máy đích, role `client`.

    Nhánh desktop giữ nguyên.
  - Relay **không** kiểm `proof`, vì nó không biết mã. Relay chỉ chuyển `proof` cho Mac. Dọn dẹp giống `purgePairings`.

- [ ] **Step 1: Viết test fail** trong `v2-phones.test.ts`, mỗi `it` một hành vi:
  - mobile tạo yêu cầu cho máy cùng tài khoản;
  - desktop đích thấy yêu cầu kèm khoá, proof và tên điện thoại;
  - approve tạo grant, và trạng thái phía mobile có `machine_id`, `name`, `link_slot`;
  - máy của tài khoản khác trả `machine_not_found` khi tạo yêu cầu và khi xin vé;
  - desktop không tạo được yêu cầu, mobile không approve được;
  - desktop khác (cùng tài khoản, không phải máy đích) không approve được;
  - yêu cầu hết hạn sau 5 phút;
  - yêu cầu mới thay yêu cầu cũ;
  - rate limit;
  - mobile có grant xin được vé đúng `link_slot`;
  - không có grant thì `not_granted`; `register` và thiếu lane đều bị từ chối;
  - gỡ grant (bởi điện thoại hoặc bởi máy) thì xin vé nhận `not_granted`;
  - token mobile gọi `POST /v2/machines`, `/v2/pairings`, `/v2/shares` vẫn nhận 403 `desktop_only`.

  Thêm `migrate-0008.test.ts`: tạo đủ hai bảng, và xoá device hoặc machine thì xoá theo các hàng liên quan.
- [ ] **Step 2: Chạy** `npm --prefix relay test -- test/v2-phones.test.ts test/migrate-0008.test.ts test/v2-relay-tickets.test.ts`. Kỳ vọng FAIL.
- [ ] **Step 3: Cài đặt.**
- [ ] **Step 4: Chạy lại** `npm --prefix relay test` và `npm --prefix relay run typecheck`. Kỳ vọng PASS.
- [ ] **Step 5: Commit** (`feat(relay): phones pair with machines and get link-lane tickets`).

### Task 6: `shellx-core`: các lệnh `phones.*` cho Mac

**Files:**
- Create: `shellx-core/src/phones.rs`
- Modify: `shellx-core/src/lib.rs` (dispatch), `shellx-core/src/api.rs` (kiểu request/response)
- Modify: `shellx-core/fake-api/src/lib.rs` (năm route phía desktop của Task 5, helper `add_phone_pairing(...)`, `has_phone_grant(...)`)
- Test: Create `shellx-core/tests/phones.rs`
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/ShellXCoreClient+Phones.swift`
- Test: Create `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/ShellXCoreClientPhonesTests.swift`

**Interfaces:**
- Consumes: các route desktop của Task 5; `require_machine`, `auth::load_session`, `http::send` (code có sẵn).
- Produces:
  - **Lệnh core:**
    - `phones.pending {}` → `{"pairings": [...]}` (các trường như route ở Task 5);
    - `phones.approve {pairing_id}` → `{}`;
    - `phones.deny {pairing_id}` → `{}`;
    - `phones.grants {}` → `{"grants": [...]}`;
    - `phones.revoke {grant_id}` → `{}`.

    Lỗi: `not_logged_in`, `not_registered`, và mã của server đi thẳng qua.
  - **Swift:**
    - `public struct PhonePairingRequest: Equatable, Sendable { id, deviceName, platform, clientKey: Data, proof: Data, createdAt: Date }`;
    - `public struct PairedPhone: Equatable, Sendable { grantID, deviceID, deviceName, platform, clientKey: Data, createdAt: Date, lastSeen: Date? }`;
    - `extension ShellXCoreClient`:
      - `pendingPhonePairings() throws -> [PhonePairingRequest]`;
      - `approvePhonePairing(_ id: String) throws`;
      - `denyPhonePairing(_ id: String) throws`;
      - `pairedPhones() throws -> [PairedPhone]`;
      - `revokePhone(grantID: String) throws`.

      Tất cả chặn trên FFI, nên không gọi trên main thread.

- [ ] **Step 1: Viết test fail.**
  - Rust: `phones_pending_lists_target_requests`, `phones_approve_then_grants_lists_phone`, `phones_revoke_removes_grant`, `phones_require_login`, `phones_approve_expired_passes_server_code`.
  - Swift: `testPendingDecodesKeysAndProof`, `testBadKeyLengthIsBadResponse`. Test Swift dùng một `ShellXCoreCalling` giả.
- [ ] **Step 2: Chạy** `cargo test --manifest-path shellx-core/Cargo.toml --test phones` và `swift test --package-path Packages/Shared/ShellXBrand --filter ShellXCoreClientPhonesTests`. Kỳ vọng FAIL.
- [ ] **Step 3: Cài đặt.**
- [ ] **Step 4: Chạy lại.** `cargo test --manifest-path shellx-core/Cargo.toml` và `swift test --package-path Packages/Shared/ShellXBrand`. Kỳ vọng PASS.
- [ ] **Step 5: Commit** (`feat(shellx-core): phones.* for pairing approval and grants`).

### Task 7: Phía điện thoại: `PairingOffer` và target `ShellXLinkAccount`

**Files:**
- Create: `shellx-link/Sources/ShellXLinkCore/Pairing/PairingOffer.swift`
- Create: `shellx-link/Sources/ShellXLinkAccount/RelayAPI.swift`, `PhonePairing.swift`, `LinkConnector.swift`
- Modify: `shellx-link/Package.swift` (target `ShellXLinkAccount` phụ thuộc Core + Relay + Session; test target `ShellXLinkAccountTests`; probe phụ thuộc thêm `ShellXLinkAccount`)
- Modify: `shellx-link/spec/PROTOCOL.md` (thêm §9 "Ghép cặp và tin cậy")
- Create: `shellx-link/spec/vectors/pairing.json`
- Test: Create `shellx-link/Tests/ShellXLinkCoreTests/PairingOfferTests.swift`, `shellx-link/Tests/ShellXLinkAccountTests/RelayAPITests.swift`, `PhonePairingTests.swift`, `StubURLProtocol.swift`

**Interfaces:**
- Consumes: `RelayTicket.claims`, `RelayClientConnector.connect(... slotOfflineRetries:)`, `RelayError.insecureTransport` (Task 4); `LinkClient.connect` (P1); các route mobile (Task 5).
- Produces:
  - **`PairingOffer`:** `public struct PairingOffer: Equatable, Sendable`, gồm:
    - `static let lifetime: TimeInterval = 300`;
    - `machineID`, `linkSlot`, `hostKey: Data` (32), `code: Data` (16), `machineName`;
    - `static func make(machineID:linkSlot:hostKey:machineName:) -> PairingOffer`, mã ngẫu nhiên từ `SystemRandomNumberGenerator`;
    - `init(uri: String) throws`, lỗi `PairingOfferError`: `.badURI`, `.unsupportedVersion`, `.badField(String)`;
    - `var uri: String` = `shellx-link://pair?v=1&m=<machine_id>&s=<link_slot>&k=<host key b64url>&c=<code b64url>&n=<tên máy, percent-encoded>`;
    - `func proof(clientKey: Data) -> Data` = HMAC-SHA256, khoá là `code`, thông điệp là `"shellx-link-pair/1" ‖ 0x00 ‖ UTF-8(machineID) ‖ 0x00 ‖ clientKey`;
    - `func verify(proof: Data, clientKey: Data) -> Bool`, so sánh thời gian hằng bằng `HMAC.isValidAuthenticationCode`.

    `description` không bao giờ in `code`.
  - **`RelayAPI`:** `public struct RelayAPI: Sendable`, khởi tạo bằng `init(baseURL: URL, session: URLSession = .shared, clientVersion: String)`. `baseURL` phải là `https`, trừ loopback; nếu không thì ném `RelayError.insecureTransport`. Gồm các hàm:
    - `login(email:password:deviceName:clientKey:) async throws -> AccountSession`. Hàm gọi `POST /v1/auth/login` với `device {kind: "mobile", platform: "ios", name, public_key: b64url(clientKey)}`. `AccountSession { userID, deviceID, token }` không in token;
    - `requestPairing(offer:clientKey:token:) async throws -> String`;
    - `pairingStatus(id:token:) async throws -> PhonePairingStatus`, với `.pending`, `.approved(machineID:name:linkSlot:)`, `.denied`, `.expired`;
    - `machines(token:) async throws -> [PairedMachineListing]`, với `PairedMachineListing { grantID, machineID, name, platform, online: Bool, linkSlot, fingerprint }` lấy từ `GET /v2/phone-grants`;
    - `mintConnectTicket(machineID:expectedSlot:token:) async throws -> (ticket: RelayTicket, relayURL: URL)`. Hàm kiểm `claims.slot == expectedSlot` và `claims.permission == "connect"`;
    - `unpair(grantID:token:) async throws`.
  - **`RelayAPIError`:** `.http(status: Int, code: String)`, `.badResponse`, `.slotMismatch`, `.notConnectTicket`.
  - **Ghép cặp:**
    - `public struct PairedMachine: Codable, Equatable, Sendable { machineID, name, linkSlot, hostKey: Data }`;
    - `PhonePairing.pair(offerURI:clientKey:api:token:pollInterval: Duration = .seconds(2)) async throws -> PairedMachine`. Hàm chờ tối đa `PairingOffer.lifetime`. Host key luôn lấy từ offer, không lấy từ relay. `machine_id` hoặc `link_slot` relay trả mà khác offer thì ném `.badResponse`. Bị từ chối thì ném `PhonePairingError.denied`; hết hạn thì ném `.expired`.
  - **Kết nối:** `LinkConnector.connect(machine:key:api:token:clientVersion:deviceName:) async throws -> LinkClient`. Hàm xin vé (đã kiểm slot), gọi `RelayClientConnector.connect` (có thử lại `slot-offline`), rồi gọi `LinkClient.connect` với host key đã ghim.
  - **§9 PROTOCOL.md** ghi: URI của QR, công thức proof, các route relay, thời điểm khoá điện thoại được tin (sau khi người dùng bấm Đồng ý trên Mac), host key được ghim từ QR, và relay chỉ gỡ được tin cậy.

- [ ] **Step 1: Viết test fail.**
  - `PairingOfferTests`:
    - `testURIRoundTrip`;
    - `testProofMatchesVector` (vector trong `pairing.json` sinh bằng CryptoKit một lần rồi ghi cứng);
    - `testVerifyRejectsOtherKeyOrMachine`;
    - `testParseRejectsBadFields` (khoá 31 byte, thiếu `c`, `v=2`);
    - `testDescriptionHidesCode`.
  - `RelayAPITests` (`URLProtocol` giả):
    - `testLoginSendsMobileDevice`;
    - `testMintChecksSlotClaim`;
    - `testMintRejectsRegisterTicket`;
    - `testHTTPErrorCodeSurfaced`;
    - `testPlainHTTPRefusedForRemoteHost`.
  - `PhonePairingTests`:
    - `testPairPollsUntilApproved`;
    - `testPairDeniedThrows`;
    - `testHostKeyComesFromOfferNotRelay`;
    - `testApprovedSlotMismatchThrows`.

  Chạy `swift test --package-path shellx-link`. Kỳ vọng FAIL.
- [ ] **Step 2: Cài đặt.**
- [ ] **Step 3: Chạy lại** `swift test --package-path shellx-link`, rồi `scripts/shellx/check-link-license.sh`. Kỳ vọng PASS và exit 0.
- [ ] **Step 4: Commit** (`feat(shellx-link): phone-side pairing, relay API and connector`).

### Task 8: Mac: khoá trong Keychain theo bundle và tài khoản, gỡ ghép cặp

**Files:**
- Create: `Sources/ShellX/Remote/Link/ShellXLinkSecretStorage.swift` (protocol và `KeychainLinkSecretStorage`)
- Modify: `Sources/ShellX/Remote/Link/ShellXLinkKeyStore.swift` (viết lại trên storage)
- Modify: `Sources/ShellX/Remote/Link/ShellXLinkHostController.swift` (thêm `accountID`, thử lại lỗi Keychain tạm thời, đối chiếu với relay, `revoke(clientKey:)`)
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/RemoteLinkHosting.swift` (`start(machineID:linkSlot:accountID:)`), `ShellXRemoteService.swift:384-389` (truyền `accountOwnerID`)
- Modify: `shellx-link/Sources/ShellXLinkSession/LinkHost.swift` (`disconnect(clientKey:)`)
- Modify: `Sources/ShellX/Remote/Link/TerminalController+ShellXLinkDebug.swift` (`debug_invite` tin khoá qua API mới, tên `debug probe`; Task 9 sẽ bỏ hẳn lệnh này)
- Test: `cmuxTests/ShellXLinkKeyStoreTests.swift` (viết lại), `shellx-link/Tests/ShellXLinkSessionTests/LinkSessionTests.swift`

**Interfaces:**
- Consumes: `pairedPhones()` (Task 6).
- Produces:
  - **Storage:** `protocol ShellXLinkSecretStorage: Sendable`, gồm:
    - `func read(account: String) throws -> Data?`;
    - `func add(_ data: Data, account: String) throws -> Bool` (trả false khi item đã có);
    - `func update(_ data: Data, account: String) throws`.

    Lỗi là `ShellXLinkSecretError`: `.transient(OSStatus)` cho `errSecInteractionNotAllowed`, `.failed(OSStatus)` cho các mã khác.
  - **`KeychainLinkSecretStorage`:**
    - service `"\(Bundle.main.bundleIdentifier ?? "pro.shellx.desktop").shellx-link"`;
    - account `"host-key.<accountID>"` và `"trusted-clients.<accountID>"`;
    - `kSecUseDataProtectionKeychain: true`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, theo mẫu `KeychainShellXShareStore`.
  - **`ShellXLinkKeyStore`:** `init(storage:accountID:)`, gồm:
    - `hostKey() throws -> NoiseStaticKey`: tạo lần đầu bằng `add`; nếu `add` trả false thì đọc lại khoá đã lưu;
    - `load() throws`;
    - `trust(_ phone: TrustedPhone) throws`;
    - `untrust(key: Data) throws`;
    - `retainOnly(keys: Set<Data>) throws`: chỉ bớt, không bao giờ thêm;
    - `trustedClients() -> Set<Data>`;
    - `trustedPhones() -> [TrustedPhone]`.

    `TrustedPhone { key: Data, deviceID: String, name: String, pairedAt: Date }`. JSON lưu là `{"version":2,"phones":[{"key","device_id","name","paired_at"}]}`.
  - **`ShellXLinkHostController`:**
    - `static func loadKeys(_ keys: ShellXLinkKeyStore, sleep: (Duration) async throws -> Void) async throws -> NoiseStaticKey`. Lỗi `.transient` thì thử lại theo `ReconnectBackoff`. Dữ liệu hỏng thì dừng, log `link_keys_corrupt`, và không thay khoá;
    - đối chiếu `retainOnly(keys: Set(pairedPhones().map(\.clientKey)))` lúc host chạy và mỗi 10 phút, chỉ khi lời gọi thành công;
    - `func revoke(clientKey: Data) async` gọi `untrust`, rồi `host.disconnect(clientKey:)`.
  - `LinkHost.disconnect(clientKey: Data) async`: đóng mọi phiên đang sống đã xác thực bằng khoá đó. Phiên mới vẫn bị chặn qua `trustedClients`.
  - **[người viết plan]** File P1 trong `~/Library/Application Support/ShellX/link/` không được đọc nữa và cũng không bị xoá.

- [ ] **Step 1: Viết test fail.**
  - `ShellXLinkKeyStoreTests`, dùng storage trong bộ nhớ định nghĩa trong file test:
    - `testHostKeyScopedByAccount`;
    - `testConcurrentFirstHostKeyUsesStoredOne`;
    - `testTrustUntrustPersist`;
    - `testRetainOnlyNeverAdds`;
    - `testCorruptTrustedListThrowsAndIsNotReplaced`;
    - `testTransientKeyErrorIsRetried` (gọi `loadKeys`).
  - `LinkSessionTests`: `testDisconnectClosesLiveSessionsOfKey` (hai client với hai khoá; ngắt một thì client đó nhận `sessionClosed`, client kia vẫn chạy) và `testHandshakeRejectedAfterUntrust`.
- [ ] **Step 2: Chạy** `scripts/shellx/test-app.sh ShellXLinkKeyStoreTests` và `swift test --package-path shellx-link --filter LinkSessionTests`. Kỳ vọng FAIL.
- [ ] **Step 3: Cài đặt.**
- [ ] **Step 4: Chạy lại** cả hai lệnh, thêm `swift test --package-path Packages/Shared/ShellXBrand`. Kỳ vọng PASS.
- [ ] **Step 5: Build tagged** `link`. Mở app với `SHELLX_REMOTE_MACHINES=1`. Kỳ vọng log có `link host registering slot` và không có hộp thoại Keychain.
- [ ] **Step 6: Commit** (`feat(shellx): link keys in the Keychain per build and account, revoke disconnects`).

### Task 9: Mac: ghép cặp iPhone (QR, Đồng ý, danh sách, gỡ)

**Files:**
- Create: `Sources/ShellX/Remote/Link/ShellXPhonePairingCoordinator.swift`
- Create: `Sources/ShellX/Remote/UI/PhonePairingSheet.swift` (SwiftUI, cùng `PhonePairingSheetPresenter` theo mẫu `RequestAccessSheetPresenter`)
- Modify: `Sources/ShellX/Remote/UI/ShellXRemoteUIActions.swift` (`presentPhonePairing()`)
- Modify: context menu của dòng tiêu đề "Mac này" trong sidebar ShellX (tìm theo `ShellXSidebarHeaderRow.machine` với key local). Thêm một mục "Ghép cặp iPhone…" / "Pair iPhone…"; đây là lối vào duy nhất **[người viết plan]**
- Modify: `Sources/ShellX/Remote/Link/TerminalController+ShellXLinkDebug.swift`: xoá `shellx.link.debug_invite`. Thêm hai lệnh DEBUG, cả hai đi qua coordinator:
  - `shellx.link.debug_pairing_offer {}` → `{offer_uri}`;
  - `shellx.link.debug_pairing_approve {pairing_id}` → `{approved: true}`.

  Cập nhật danh sách method socket tương ứng.
- Modify: `Resources/Localizable.xcstrings`
- Test: Create `cmuxTests/ShellXPhonePairingCoordinatorTests.swift`

**Interfaces:**
- Consumes: `PairingOffer` (Task 7); phone API của `ShellXCoreClient` (Task 6); `ShellXLinkKeyStore.trust/untrust`, `ShellXLinkHostController.revoke(clientKey:)` (Task 8); `ShellXQRCode.makeImage(payload:)`.
- Produces:
  - `protocol PhonePairingCalling: Sendable` bọc năm lệnh `phones.*` (để test).
  - `@MainActor final class ShellXPhonePairingCoordinator: ObservableObject`:
    - `@Published` `offer: PairingOffer?`, `candidates: [Candidate]`, `phones: [PairedPhone]`, `errorText: String?`;
    - `Candidate { id: String, deviceName, platform, clientKey: Data }`;
    - `open()`, `close()`;
    - `approve(_ id: String) async throws`, `deny(_ id: String) async`;
    - `refreshPhones() async`, `revoke(_ phone: PairedPhone) async throws`.

**Luật:**
- **Lúc mở:** `open()` tạo offer mới và poll `phones.pending` mỗi `ShellXRemoteService.pollInterval` (2 s) trong lúc mở. Offer quá `PairingOffer.lifetime` thì tạo mới. `close()` dừng poll và bỏ offer.
- **Mac chưa sẵn sàng:** khi host chưa chạy (gate tắt hoặc chưa có `link_slot`), sheet hiện thông báo đó và không có QR.
- **Kiểm bằng chứng:** chỉ yêu cầu có proof khớp **offer hiện tại** mới thành `Candidate`. Các yêu cầu khác bị `deny` lặng lẽ và chỉ được đếm trong log (`pairing_proof_mismatch`).
- **Đồng ý:**
  - Thứ tự: `trust` trước, rồi mới `phones.approve`. Approve lỗi thì `untrust` và hiện lỗi.
  - Approve xong thì offer được tạo mới (mỗi QR một điện thoại) **[người viết plan]**.
- **Gỡ:** gọi `revoke(clientKey:)` của host trước (bỏ tin cậy và đóng phiên ngay), rồi mới gọi `phones.revoke`. Relay lỗi thì hiện lỗi; tin cậy ở Mac đã mất (fail closed).
- **Chữ hiển thị (vi / en):**
  - "Ghép cặp iPhone…" / "Pair iPhone…";
  - "Quét mã này bằng app ShellX trên iPhone" / "Scan this code with the ShellX app on your iPhone";
  - "%@ muốn điều khiển Mac này" / "%@ wants to control this Mac";
  - "Đồng ý" / "Allow", "Từ chối" / "Deny";
  - "Điện thoại đã ghép cặp" / "Paired phones";
  - "Gỡ" / "Remove";
  - "Mac này chưa sẵn sàng phục vụ điện thoại" / "This Mac is not ready to serve phones yet".

- [ ] **Step 1: Viết test fail** trong `ShellXPhonePairingCoordinatorTests`:
  - `testValidProofBecomesCandidate`;
  - `testProofForOldOfferIsDeniedNotShown`;
  - `testOfferIsSingleUse`;
  - `testApproveTrustsBeforeRelayAndRollsBackOnFailure`;
  - `testRevokeUntrustsAndDisconnectsBeforeRelayCall`;
  - `testCloseStopsPolling`.

  Chạy `scripts/sync-test-wiring`, rồi `scripts/shellx/test-app.sh ShellXPhonePairingCoordinatorTests`. Kỳ vọng FAIL.
- [ ] **Step 2: Cài đặt** coordinator, sheet, mục menu, lệnh DEBUG và chuỗi.
- [ ] **Step 3: Chạy lại** test ở Step 1. Kỳ vọng PASS.
- [ ] **Step 4: Xem bằng mắt.**
  - Chụp sheet ở cả ba trạng thái (QR, có Candidate, danh sách điện thoại), sáng và tối, bằng một test tạm `cacheDisplay` → PNG. Không commit test tạm này.
  - Kiểm theo HIG và gu màu: màu dịu, không nút gradient, màu chính `#60a5fa`.
- [ ] **Step 5: Audit localization** theo `skills/cmux-localization`. Ghi kết quả vào mô tả commit.
- [ ] **Step 6: Commit** (`feat(shellx): pair an iPhone from the Mac with QR and on-Mac consent`).

### Task 10: Mac: nguồn dữ liệu Link cho việc chờ, phiên agent và chat

**Files:**
- Modify: `Sources/ShellX/Remote/Link/ShellXLinkFeedSource.swift`
- Create: `Sources/ShellX/Remote/Link/ShellXLinkSessionSource.swift`, `ShellXLinkChatSource.swift`
- Modify: `Sources/Mobile/AgentChat/AgentChatTranscriptService.swift` (`addFrameObserver(_:) -> UUID`, `removeFrameObserver(_:)`; có observer thì coi như có subscriber)
- Modify: `Sources/TerminalController+MobileChat.swift`: tách phần thân của `mobile.chat.send` và `mobile.chat.interrupt` thành `agentChatSend(sessionID:text:) async -> V2CallResult` và `agentChatInterrupt(sessionID:hard:) async -> V2CallResult`. Cả RPC mobile lẫn Link đều gọi chung hai hàm này (`skills/cmux-shared-behavior`)
- Modify: `Sources/TerminalController.swift:6916,6938,6963` (`feed.*.reply` trả `delivered` bằng giá trị Bool của `deliverReply`, theo nợ trong ledger)
- Modify: `ShellXLinkHostController.swift`, `Sources/ShellX/Remote/ShellXRemoteService+App.swift` (truyền hai nguồn mới vào `LinkHost`)
- Test: `cmuxTests/ShellXLinkFeedSourceTests.swift` (mở rộng); Create `cmuxTests/ShellXLinkSessionSourceTests.swift`, `cmuxTests/ShellXLinkChatSourceTests.swift`

**Interfaces:**
- Consumes: `LinkDecision`, `PendingQuestion`, `modes` (Task 2); `AgentSessionSource`, `AgentChatSource`, `AgentSession`, `ChatEntry` (Task 3); `WorkstreamPayload.question/exitPlan`, `WorkstreamDecision`, `ChatSessionDescriptor`, `ChatSessionEventFrame`, `AgentChatTranscriptService.history(sessionID:beforeSeq:limit:)`.
- Produces: `ShellXLinkFeedSource` đầy đủ, `ShellXLinkSessionSource`, `ShellXLinkChatSource` (đều `@MainActor`).

**Quy tắc map:**
- **Việc chờ:** item `.pending` có payload `permissionRequest`, `question` hoặc `exitPlan`, **và** `item.source == .claude`. Thẻ của Codex hay agent khác không lên điện thoại (sửa lỗi ghi trong ledger).
- **Exit plan:**
  - `modes = ["ultraplan","auto_accept","manual","deny"]`, tức mọi `WorkstreamExitPlanMode` trừ `.bypassPermissions`;
  - `plan_preview` là `plan` cắt còn 8192 byte;
  - `feedback` dài quá 4096 byte thì trả `unknown`.
- **Câu hỏi:**
  - `questions` lấy từ `WorkstreamQuestionPrompt`; mỗi trường chữ cắt còn 1024 byte; `modes` rỗng;
  - quyết định hợp lệ khi có ít nhất một selection và mọi selection đều trùng một `label`; khi đó map sang `.question(selections:)`.
- **Phiên agent:**
  - `ChatSessionDescriptor` có `agentKind == .claude` và `kind == .agent`;
  - `workspace_title` tra như feed (`liveWorkspace`);
  - trạng thái map `idle`/`working(since)`/`needsInput(since)`/`ended`;
  - thay đổi lấy từ frame observer `.stateChanged`, `.descriptorChanged`, `.sessionRemoved`. Mỗi lô thay đổi tăng `revision` đúng 1.
- **Chat:**
  - `ChatRole` map `user`/`agent`/`system`;
  - `ChatMessageKind`:

    | Mac | Link |
    | --- | --- |
    | `prose` | `prose` |
    | `thought` | `thought` |
    | `toolUse` | `tool_use` (tên tool và tóm tắt một dòng) |
    | `terminal` | `tool_use` (`Bash`, lệnh) |
    | `fileEdit` | `tool_use` (tên tool, đường dẫn) |
    | `status` | `status` |
    | loại khác | `other` (tóm tắt ngắn) |

  - đẩy khi có frame `.appended` hoặc `.updated`;
  - `.streamingProse` và `.reset` bỏ qua trong P2 **[người viết plan, P3 quyết]**.
- **Gửi và ngắt:**
  - `send` thành công thì `submitted`; `not_found` thì `notFound`; `input_queue_full` thì `busy`; lỗi khác thì `failed`;
  - `interrupt` thành công thì `sent`; `not_found` thì `notFound`; lỗi khác thì `failed`.

- [ ] **Step 1: Viết test fail.**
  - Feed:
    - `testOnlyClaudeItemsArePending`;
    - `testQuestionItemCarriesQuestionsAndAnswers`;
    - `testExitPlanItemModesExcludeBypass`;
    - `testExitPlanFeedbackDelivered`;
    - `testSelectionNotAnOptionIsUnknown`;
    - `testFeedReplySocketReportsNotDelivered`.
  - Phiên agent: `testClaudeSessionsListedWithState`, `testStateChangeEmitsUpsertWithNextRevision`, `testRemovedSessionEmitsRemoved`.
  - Chat:
    - `testHistoryMapsMessages`;
    - `testEntryTextCutTo4096Bytes`;
    - `testSendUsesSharedPathAndMapsBusy`;
    - `testFrameObserverKeepsTranscriptTailing` (chỉ có observer Link, không có client mobile, mà transcript vẫn được tail).

  Chạy `scripts/sync-test-wiring`, rồi `scripts/shellx/test-app.sh ShellXLinkFeedSourceTests ShellXLinkSessionSourceTests ShellXLinkChatSourceTests`. Kỳ vọng FAIL.
- [ ] **Step 2: Cài đặt.**
- [ ] **Step 3: Chạy lại** test ở Step 1. Chạy thêm các test hiện có của mobile chat và Feed: tìm bằng `ls cmuxTests | grep -E 'MobileChat|AgentChat|FeedCoordinator'`. Kỳ vọng PASS hết.
- [ ] **Step 4: Commit** (`feat(shellx): serve questions, plans, agent sessions and chat over ShellX Link`).

### Task 11: Probe đóng vai điện thoại, chạy trọn đường, đo lại WAN

**Files:**
- Modify: `shellx-link/Sources/shellx-link-probe/main.swift`
- Modify: `shellx-link/README.md` (cách dùng probe)
- Modify: `docs/superpowers/ledgers/shellx-ios.md` (mục "P2 kết quả" và "Mang sang P3")
- Modify: `docs/superpowers/specs/2026-10-22-shellx-ios-agent-remote-design.md` (bỏ câu cũ về việc thay `cmux-tui` ở §9)

**Interfaces:**
- Consumes: `RelayAPI`, `PhonePairing`, `LinkConnector`, `LinkClient` (Task 2, 3, 7); hai lệnh DEBUG của Task 9.
- Produces: các lệnh của probe. Mọi lệnh nhận `--state <dir>`. Thư mục này chứa:
  - `phone.key`: khoá static Link, quyền 0600;
  - `session.json`: token, quyền 0600;
  - `machines.json`: các máy đã ghép cặp, kèm host key.

  Danh sách lệnh:
  - `login --api <url> --email <email> --password-stdin`;
  - `pair --offer-file <file>` (file chứa URI của QR, không đưa URI lên dòng lệnh);
  - `machines`, `unpair --machine <id>`;
  - `watch --machine <id>`;
  - `sessions --machine <id>`;
  - `approve <request_id> [--mode once]`;
  - `answer <request_id> --select <label>…`;
  - `plan <request_id> --mode manual [--feedback-file <f>]`;
  - `chat-history <session_id>`;
  - `chat-send <session_id> --text-file <f>`;
  - `chat-stop <session_id> [--hard]`;
  - `bench --count 50 --socket <path>` (như P1, nhưng dùng vé do probe tự xin).

  Bỏ hết tuỳ chọn `--invite`.

- [ ] **Step 1: Cài đặt probe.** Probe là CLI mỏng; logic đã có test ở Task 2–7.
- [ ] **Step 2: Chạy trọn đường ở local.** Môi trường:
  - relay Node local, đủ 8 migration;
  - `cmux-relay` local dùng chung secret;
  - app tag `link` với `SHELLX_REMOTE_MACHINES=1` và `SHELLX_API_BASE=http://127.0.0.1:8787`;
  - một tài khoản dev dùng một lần, như ledger mục "Spike P1".

  Các bước:
  1. `login`.
  2. `debug_pairing_offer > offer.txt` (file 0600), rồi `pair`.
  3. Bấm Đồng ý trong sheet (hoặc gọi `debug_pairing_approve`).
  4. `watch`. Trong app, Claude Code tạo lần lượt một thẻ xin quyền, một câu hỏi (`AskUserQuestion`) và một plan. Trả lời bằng `approve`, `answer`, `plan`. Kỳ vọng Claude chạy tiếp mỗi lần.
  5. `sessions`. Kỳ vọng trạng thái đi qua `working` → `needs_input` → `idle`.
  6. `chat-send` "liệt kê file", rồi `chat-history`. Kỳ vọng thấy câu trả lời.
  7. `chat-stop`.
  8. Trong lúc `watch` đang chạy, bấm Gỡ trong sheet. Kỳ vọng `watch` kết thúc ngay. Chạy `watch` lại thì handshake bị từ chối, xin vé nhận `not_granted`.

  Ghi log vào ledger.
- [ ] **Step 3: Bench local** hai lần. Ghi p50/p95 vào ledger.
- [ ] **Step 4: WAN, cần người dùng đồng ý trước.**
  - Route mới của relay chỉ lên production khi vào `main`. Hỏi người dùng có cho merge và deploy không.
  - Nếu được: lặp lại Step 2 với API thật, và Step 3 qua 4G như Task 1. Cổng giống Task 1.
  - Nếu không: ghi "chưa đo WAN của P2" trong ledger.
- [ ] **Step 5: Ledger.**
  - Mục "P2 kết quả".
  - Mục "Mang sang P3", gồm:
    - kênh `terminal`;
    - xem trước chữ đang chạy (`streamingProse`);
    - lưu token và máy đã ghép cặp của app iOS trong Keychain;
    - thẻ khôi phục từ log hết hạn lúc khởi động;
    - biên dịch thử bằng Swift 6.0.
  - Sửa câu cũ ở §9 của spec.
- [ ] **Step 6: Commit** (`feat(shellx-link): probe plays a paired phone end to end; P2 results`).

---

**Ngoài phạm vi P2:**
- app iOS (P3);
- kênh `terminal` (P3);
- APNs và đồng bộ gỡ thông báo (P4);
- skill (P5);
- AI điều phối (P6);
- adapter Codex;
- Android.
