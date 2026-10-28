# ShellX mobile workspaces — Đợt 1: danh sách và quản lý workspace — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Màn chính app iOS thành danh sách workspace của từng Mac (như sidebar desktop); chạm vào một workspace ra màn có hàng chip pane (pane agent = chat có mic và gửi ảnh / file, pane shell = ô giữ chỗ); tạo, đổi tên, đóng workspace từ điện thoại.

**Architecture:** ShellX Link thêm hai feature `workspaces` (đọc danh sách + thay đổi theo revision) và `workspace_control` (tạo / đổi tên / đóng). `LinkHost` nhận hai protocol nguồn mới; Mac cài đặt chúng bằng dữ liệu `Workspace`/`TabManager` sẵn có và các hàm mobile của cmux (`v2MobileWorkspaceCreate`, `v2MobileWorkspaceAction`, `v2MobileWorkspaceClose`). iOS thêm `WorkspaceSet` vào `MachineConnection`/`MachineHub`, rồi thay màn chat gộp bằng `WorkspaceListScreen` và `WorkspaceScreen`.

**Tech Stack:** Swift 6.0; shellx-link (MIT, XCTest); app Mac (cmux fork, Swift Testing trong `cmuxTests`); app iOS 17+ SwiftUI (`ShellXAppCore` test bằng `swift test`, render test trong `ShellXTests`).

**Spec:** `docs/superpowers/specs/2026-10-28-shellx-mobile-workspaces-design.md` (đọc mục 1.1, 3, 6, 7.1, 7.3, 8.1, 8.2, 9). Mockup: `.superpowers/brainstorm/56669-1793188282/content/workspace-v2.html`, `structure.html` (hướng A).

## Global Constraints

- Link v1 giữ `v: 1`; chỉ thêm message và trường tuỳ chọn; frame ≤ 65 519 byte UTF-8 (`LinkCodec.maxFrameBytes`); trường tên `snake_case`; trường tuỳ chọn rỗng thì bỏ, không `null`.
- Feature chỉ dùng khi host báo trong `welcome.features`; Mac 1.5.1 (không báo) và app iOS cũ phải chạy với nhau như hôm nay.
- iOS: chỉ Apple frameworks + `shellx-link`; `scripts/shellx/check-ios-license.sh` xanh; mọi chuỗi giao diện mới vào `shellx-ios/ShellX/Localizable.xcstrings` có `en` và `vi`.
- Mac: code app tương thích Swift 6.0; lệnh từ điện thoại không đổi workspace / pane đang chọn, không đưa cửa sổ lên trước, không mở hộp thoại; không thêm method socket v2; `RemoteRelayCommandPolicy` không đổi.
- Không ghi log tên workspace, tên tab, thư mục.
- Màu theo spec mục 6: nền `#0b0716`, khối `#17122a`, chủ đạo `#60a5fa`, chạy `#e8c468`, xong `#6fd49a`, lỗi `#e88a8a`; nút màu đặc dịu, không gradient. Dùng color asset / `AgentStateStyle` sẵn có thay vì mã màu rời.
- Theo CLAUDE.md: thêm / xoá file trong `cmuxTests/` thì chạy `./scripts/sync-test-wiring`; không thoát / thay app ShellX người dùng đang chạy.

## Review Focus

1. Mac có 2 cửa sổ chính: danh sách gồm workspace của cả hai, `order` liên tục theo cửa sổ rồi tới vị trí trong cửa sổ, không trùng id (Task 3 test `twoWindowsListedInOrder`).
2. Đổi tên với tên toàn khoảng trắng, có ký tự điều khiển hoặc dài hơn 128 ký tự: Mac nhận tên đã làm sạch / cắt; tên rỗng sau khi làm sạch → `failed`, không gọi Mac (Task 3 test `renameSanitizesTitle`, Task 1 test `renameTitleCap`). **Lệch spec 6.3 (người điều phối quyết):** đường mobile của cmux chỉ cho `rename`, không cho `clear_name`, nên đợt 1 không có "tên rỗng = về tên tự động"; nút Lưu trên iPhone tắt khi tên rỗng.
3. Đóng workspace cuối cùng, hoặc workspace mà Mac bảo vệ: điện thoại nhận `refused` và hiện câu dễ hiểu, danh sách không đổi (Task 3 test `closeLastWorkspaceRefused`, Task 4 test `refusedCloseKeepsRow`).
4. Mac gửi `workspace.changed` có revision nhảy cóc (mất một thay đổi) hoặc mất mạng giữa chừng: điện thoại xin lại cả danh sách, không hiện workspace ma (Task 4 test `gapRefetchesList`, `reconnectReplacesList`).
5. Workspace đang mở trên điện thoại bị đóng trên Mac, hoặc phiên agent của chip đang xem kết thúc: màn workspace quay về danh sách / chip biến mất kèm báo ngắn, không crash vì id không còn (Task 6 test `closedWorkspaceDismisses`).

---

### Task 1: Message `workspace.*` trong ShellX Link (codec + PROTOCOL.md §4/§6)

**Files:**
- Create: `shellx-link/Sources/ShellXLinkCore/Messages/Workspace.swift`
- Modify: `shellx-link/Sources/ShellXLinkCore/Messages/LinkMessage.swift`, `shellx-link/Sources/ShellXLinkCore/Messages/LinkCodec.swift`, `shellx-link/Sources/ShellXLinkCore/ShellXLink.swift` (hằng feature), `shellx-link/spec/PROTOCOL.md` (§4 bảng message + mục "Workspace", "Features"; §6 thứ tự cắt)
- Test: `shellx-link/Tests/ShellXLinkCoreTests/LinkCodecTests.swift`

**Interfaces:**
- Produces (ShellXLinkCore, public, `Codable, Equatable, Sendable`):
  - `struct LinkWorkspace { workspaceId: String; title: String; order: Int; directory: String?; branch: String?; ports: [Int]?; terminals: [LinkTerminal] }` — wire `workspace_id`, `title`, `order`, `directory`, `branch`, `ports`, `terminals`. `func shrunk(step: Int) -> LinkWorkspace?` bỏ theo thứ tự: 1 `ports`, 2 `directory`, 3 `branch`, 4 `title` của mọi terminal (thành `""`); bước ngoài 1...4 trả nil.
  - `struct LinkTerminal { terminalId: String; title: String; order: Int; selected: Bool; sessionId: String? }` — wire `terminal_id`, `title`, `order`, `selected`, `session_id`.
  - `enum WorkspaceControlOutcome: LinkWireEnum { case ok, notFound, refused, failed, other(String) }` — wire `ok`, `not_found`, `refused`, `failed`.
  - `LinkMessage` thêm: `.workspacesGet(callId:)` (`workspace.list.get`), `.workspaces(callId:revision:workspaces:)` (`workspace.list`), `.workspacesChanged(revision:upserted:removed:)` (`workspace.changed`; `removed` là mảng `workspace_id`), `.workspaceCreate(callId:)` (`workspace.create`), `.workspaceCreateResult(callId:outcome:workspaceId:)` (`workspace.create.result`, `workspace_id` chỉ có khi `ok`), `.workspaceRename(callId:workspaceId:title:)` (`workspace.rename`), `.workspaceRenameResult(callId:outcome:)`, `.workspaceClose(callId:workspaceId:)` (`workspace.close`), `.workspaceCloseResult(callId:outcome:)`.
  - `ShellXLink.workspacesFeature = "workspaces"`, `ShellXLink.workspaceControlFeature = "workspace_control"`, `ShellXLink.maxWorkspaceTitleBytes = 512` (UTF-8 byte của `title` trong `workspace.rename`; ~128 ký tự tiếng Việt).

- [ ] **Step 1: Viết test hỏng** trong `LinkCodecTests`: `testWorkspaceListRoundTrip` (một `.workspaces` có 2 workspace, một có `branch`/`ports`/`directory`, một không; terminal có và không có `session_id`) — encode rồi decode bằng nhau, và JSON không chứa khoá `ports`/`branch`/`directory`/`session_id` ở bản ghi không có chúng; `testWorkspaceChangedRoundTrip`; `testWorkspaceControlRoundTrip` cho cả 6 message điều khiển, `workspace_id` vắng trong `.workspaceCreateResult` khi outcome `.refused`; `testUnknownOutcomeKeepsWire` (`"outcome":"busy"` → `.other("busy")`); `renameTitleCap` — decode `workspace.rename` có `title` 513 byte vẫn thành công (codec không cắt; host kiểm, Task 2); `testWorkspaceShrinkOrder` — `shrunk(step: 1)` bỏ `ports`, `step: 4` còn `title` workspace nhưng terminal title rỗng, `step: 5` nil.
- [ ] **Step 2: Chạy, thấy hỏng.** `cd shellx-link && swift test --filter LinkCodecTests` → lỗi biên dịch "cannot find 'LinkWorkspace'".
- [ ] **Step 3: Cài đặt** các kiểu và case trên, theo đúng khuôn `AgentSession`/`Sessions`/`SessionsChanged` trong `LinkCodec` (body struct riêng, `call(...)` cho message có `call_id`). Thêm vào PROTOCOL.md §4: các dòng bảng, mục "### Workspace" (trường như trên, quy tắc revision giống danh sách phiên, chỉ liệt kê workspace cục bộ và surface terminal), hai feature trong "### Features"; §6: thứ tự cắt của `workspace.list`/`workspace.changed` (dùng `shrunk(step:)`, không vừa thì bỏ workspace cuối và host phải gửi lại đủ ở frame sau — chép quy tắc của `agent.sessions`).
- [ ] **Step 4: Chạy lại** `swift test --filter LinkCodecTests` → PASS; `swift test` toàn package → PASS.
- [ ] **Step 5: Commit** `feat(shellx-link): workspace list and control messages`.

### Task 2: `LinkHost`/`LinkClient` phục vụ `workspaces` và `workspace_control` (+ PROTOCOL.md §10, probe)

**Files:**
- Create: `shellx-link/Sources/ShellXLinkSession/WorkspaceSource.swift`, `shellx-link/Tests/ShellXLinkSessionTests/FakeWorkspaceSource.swift`, `shellx-link/Tests/ShellXLinkSessionTests/WorkspaceSessionTests.swift`
- Modify: `shellx-link/Sources/ShellXLinkSession/LinkHost.swift` (init, `welcome` features, nhánh `converse`, đẩy `workspace.changed`), `shellx-link/Sources/ShellXLinkSession/LinkClient.swift`, `shellx-link/Sources/shellx-link-probe/Commands.swift` (+ `main.swift` nếu cần đăng ký lệnh), `shellx-link/spec/PROTOCOL.md` §10
- Test: `WorkspaceSessionTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `public protocol WorkspaceSource: Sendable { func workspaces() async -> (revision: Int, workspaces: [LinkWorkspace]); func workspaceChanges() -> AsyncStream<(revision: Int, upserted: [LinkWorkspace], removed: [String])> }` — cùng quy tắc multicast / `onTermination` như `AgentSessionSource`.
  - `public protocol WorkspaceControl: Sendable { func createWorkspace() async -> (outcome: WorkspaceControlOutcome, workspaceId: String?); func renameWorkspace(workspaceId: String, title: String) async -> WorkspaceControlOutcome; func closeWorkspace(workspaceId: String) async -> WorkspaceControlOutcome }`
  - `LinkHost.init(..., workspaces: (any WorkspaceSource)? = nil, workspaceControl: (any WorkspaceControl)? = nil, ...)` (cả init public lẫn init nội bộ có `timings`). Có `workspaces` thì báo feature `workspaces`; có `workspaceControl` thì báo `workspace_control`. Thiếu nguồn thì gọi tương ứng → `error unsupported` kèm `call_id`.
  - `LinkClient`: `public nonisolated let workspaceChanges: AsyncStream<(revision: Int, upserted: [LinkWorkspace], removed: [String])>`; `public func workspaces() async throws -> (revision: Int, workspaces: [LinkWorkspace])`; `public func createWorkspace() async throws -> (outcome: WorkspaceControlOutcome, workspaceId: String?)`; `public func renameWorkspace(workspaceId: String, title: String) async throws -> WorkspaceControlOutcome`; `public func closeWorkspace(workspaceId: String) async throws -> WorkspaceControlOutcome`.
  - probe: `shellx-link-probe workspaces` (in danh sách rồi theo dõi thay đổi), `workspace-create`, `workspace-rename <id> <title>`, `workspace-close <id>`.

- [ ] **Step 1: Viết test hỏng** (`WorkspaceSessionTests`, theo khuôn `LinkSessionTests` / `InMemoryCircuitTests`): `testWelcomeListsWorkspaceFeatures` (có cả hai nguồn → features chứa `workspaces`, `workspace_control`; không nguồn → không có); `testWorkspacesUnsupportedWithoutSource` (`LinkClientError.remote(code: "unsupported", …)`); `testWorkspaceListAndChangePushed` (nguồn giả upsert một workspace → client thấy `workspaceChanges` revision 1 trong < 1 s); `testCreateRenameCloseReachControl` (nguồn giả ghi lại lời gọi; outcome trả về đúng); `testRenameTitleTooLongIsBadRequest` (`title` 513 byte → `error bad_request` có `call_id`, nguồn không bị gọi); `testOversizedListIsShrunk` (60 workspace có thư mục dài → frame đến được, `ports`/`directory` đã bỏ).
- [ ] **Step 2: Chạy, thấy hỏng.** `cd shellx-link && swift test --filter WorkspaceSessionTests` → lỗi biên dịch.
- [ ] **Step 3: Cài đặt** host: đăng ký `workspaceChanges()` trước `welcome` như `sessionChanges`; trả lời `workspace.list.get` qua hàm cắt kiểu `shrunkSessions` (dùng `LinkWorkspace.shrunk(step:)`); lệnh điều khiển chạy trong `group.addTask`, không chặn vòng đọc; kiểm `title` ≤ `ShellXLink.maxWorkspaceTitleBytes` trước khi gọi nguồn. Client: thêm continuation cho `workspaceChanges`, các hàm gọi theo khuôn `sessions()` / `chatSend`. PROTOCOL.md §10: viết lại đoạn "Default deny" (bỏ câu "No field … names … a workspace or a terminal for the host to open"), thêm 4 dòng vào bảng "Allowed calls" (`workspace.list.get` đọc; `workspace.create` tạo workspace ở thư mục Mac tự chọn, không tham số đường dẫn / lệnh; `workspace.rename`; `workspace.close` giữ luật Mac), thêm đoạn "Workspaces" chép phân tích của spec mục 9 (ba câu hỏi, scope chỉ workspace cục bộ, MDM `refused`, không log tên); đổi câu "Out of reach for a phone in v1" cho khớp (spawning terminals vẫn ngoài tầm trong đợt 1, trừ việc tạo workspace).
- [ ] **Step 4: Chạy** `swift test` (cả package) → PASS; `swift build --product shellx-link-probe` → build xanh.
- [ ] **Step 5: Commit** `feat(shellx-link): serve workspace list and control to phones`.

### Task 3: Mac — `ShellXLinkWorkspaceSource` (danh sách + điều khiển) nối vào Link host

**Files:**
- Create: `Sources/ShellX/Remote/Link/ShellXLinkWorkspaceSource.swift`, `cmuxTests/ShellXLinkWorkspaceSourceTests.swift`
- Modify: `Sources/ShellX/Remote/Link/ShellXLinkHostController.swift` (nhận và chuyển `workspaces`/`workspaceControl` cho `LinkHost`), `Sources/ShellX/Remote/ShellXRemoteService+App.swift:55-63` (truyền một `ShellXLinkWorkspaceSource()` cho cả hai tham số)
- Test: `cmuxTests/ShellXLinkWorkspaceSourceTests.swift`

**Interfaces:**
- Consumes: Task 2 (`WorkspaceSource`, `WorkspaceControl`, `LinkWorkspace`, `LinkTerminal`, `WorkspaceControlOutcome`).
- Produces: `@MainActor final class ShellXLinkWorkspaceSource: WorkspaceSource, WorkspaceControl`, với các điểm tiêm cho test (khuôn `ShellXLinkSessionSource`):
  - `typealias Snapshot = @MainActor () -> [LinkWorkspace]` — mặc định `ShellXLinkWorkspaceSource.liveWorkspaces`: duyệt `AppDelegate.shared.listMainWindowSummaries()` → `tabManagerFor(windowId:)` → `tabs` (bỏ workspace từ xa / SSH), `order` tăng dần liên tục; `directory` = `currentDirectory` rút `~`; `branch` = `gitBranch?.branch`; `ports` = `listeningPorts` (rỗng → nil); terminal từ `TerminalController.shared.mobileTerminalPanels(in:)` (thứ tự không gian), `selected` = panel đang focus của workspace, `sessionId` = phiên Claude Code chưa kết thúc có `descriptor.terminalID` trùng id panel (đọc từ `TerminalController.shared.agentChatTranscriptService`, như `ShellXLinkSessionSource.listedRecords`).
  - `struct Control { create: @MainActor () async -> V2CallResult; rename: @MainActor (_ workspaceId: String, _ title: String) -> V2CallResult; close: @MainActor (_ workspaceId: String) -> V2CallResult; isBlocked: @MainActor () -> Bool }` — mặc định: `v2MobileWorkspaceCreate(params: [:])`, `v2MobileWorkspaceAction(params: ["action": "rename", "workspace_id": id, <khoá tên mà hàm đó đọc>: title])`, `v2MobileWorkspaceClose(params: ["workspace_id": id, "force": true])`, `MobileRemoteControlPolicy.isDisabled`.
  - `init(snapshot: @escaping Snapshot = liveWorkspaces, control: Control = .live, changeSignal: …)`; `static func sanitizedTitle(_ raw: String) -> String` (bỏ ký tự điều khiển và xuống dòng, cắt khoảng trắng hai đầu, tối đa 128 ký tự).
  - Ánh xạ kết quả: `.ok` → `ok` (create kèm `workspace_id` từ payload); lỗi `not_found` → `notFound`; `protected`, `confirmation_required` và `isBlocked()` → `refused`; còn lại → `failed`.

- [ ] **Step 1: Viết test hỏng** (Swift Testing, `@Suite("ShellX Link workspace source", .serialized)`, khuôn `ShellXLinkSessionSourceTests`): `listMapsSnapshot` (snapshot giả 2 workspace → `workspaces()` revision 0 trả đúng); `changeBumpsRevisionOnce` (đổi snapshot rồi phát tín hiệu → một `workspaceChanges` revision 1 có workspace đổi trong `upserted`; phát lại khi không đổi → không có frame); `removedWorkspaceListedInRemoved`; `twoWindowsListedInOrder` (snapshot thật với 2 `TabManager` nếu test hiện có dựng được cửa sổ, nếu không thì kiểm hàm dựng thứ tự nhận vào danh sách cửa sổ); `renameSanitizesTitle` (`"  a\u{0007}b\n  "` → control nhận `"ab"`; 200 ký tự → 128; `"  \n "` → `failed`, control không bị gọi); `closeLastWorkspaceRefused` (control giả trả `.err(code: "protected", …)` → `.refused`); `blockedPolicyRefusesAll` (`isBlocked` true → cả ba lệnh `refused`, control không bị gọi); `createDoesNotChangeSelection` (dùng `TerminalController.shared.v2MobileWorkspaceCreate(params: [:], tabManager: tm)` với một `TabManager` test → `tm.selectedTabId` không đổi, số tab +1; bỏ qua nếu đã có test cmux tương đương — ghi tên test đó vào commit).
- [ ] **Step 2: Chạy, thấy hỏng.** `./scripts/sync-test-wiring && scripts/shellx/test-app.sh ShellXLinkWorkspaceSourceTests` → lỗi biên dịch.
- [ ] **Step 3: Cài đặt** nguồn. Tín hiệu thay đổi: chỉ gắn khi có subscriber; nghe `$tabs` của mỗi `TabManager` cửa sổ chính và `objectWillChange` của từng `Workspace`, gộp và điều tốc ≤ 10 lần/giây trên main (`throttle(for: .milliseconds(100), latest: true)`), rồi dựng lại danh sách, so với bản đã phát, chỉ phát khi khác (revision +1, `upserted` = bản ghi mới hoặc đổi, `removed` = id biến mất). Gắn lại khi tập cửa sổ chính đổi. `workspaces()` dựng lại và phát chênh lệch trước khi trả (như `ShellXLinkSessionSource.sessions()`). Không log tên. Nối vào `ShellXLinkHostController` và `ShellXRemoteService+App.swift`.
- [ ] **Step 4: Chạy** `scripts/shellx/test-app.sh ShellXLinkWorkspaceSourceTests ShellXLinkSessionSourceTests` → PASS.
- [ ] **Step 5: Commit** `feat(shellx): serve the Mac's workspaces over ShellX Link`.

### Task 4: iOS core — `WorkspaceSet`, kết nối, hub, dòng workspace suy ra, Mac giả

**Files:**
- Create: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Link/WorkspaceSet.swift`, `.../Workspaces/WorkspaceRow.swift`, `.../Workspaces/WorkspaceCommandResult.swift`, `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppTestSupport/FakeMacWorkspaces.swift`, tests `WorkspaceSetTests.swift`, `WorkspaceRowTests.swift`, `MachineHubWorkspaceTests.swift` trong `Tests/ShellXAppCoreTests/`
- Modify: `.../Link/MachineEvent.swift`, `.../Link/MachineConnection.swift`, `.../Link/MachineModel.swift`, `.../Link/MachineHub.swift`, `.../ShellXAppTestSupport/FakeMac.swift` (thêm nguồn workspace giả vào `LinkHost`), `FakeMacFleet.swift`/`FakeMacDemoScript.swift` (dữ liệu demo)

**Interfaces:**
- Consumes: Task 2 (`LinkClient.workspaces()`, `workspaceChanges`, `createWorkspace()`, `renameWorkspace`, `closeWorkspace`, `ShellXLink.workspacesFeature`, `.workspaceControlFeature`).
- Produces:
  - `public struct WorkspaceSet: Equatable, Sendable { revision: Int; workspaces: [LinkWorkspace] (theo `order`); mutating func reset(revision:workspaces:); mutating func apply(revision:upserted:removed:) -> RevisionGate.Result; func workspace(_ id: String) -> LinkWorkspace? }`.
  - `MachineEvent.workspaces(WorkspaceSet, supported: Bool)`; `MachineModel.workspaces: WorkspaceSet`, `MachineModel.workspacesSupported: Bool` (true khi host báo `workspaces`; xoá trong `replace(with:)`). `MachineConnection.establish` chỉ gọi `client.workspaces()` khi `hostFeatures` chứa `workspaces`, đọc `workspaceChanges` trong `read` như `sessionChanges` (khoảng hở → gọi lại `workspaces()`).
  - `public enum WorkspaceState: Equatable, Sendable { case needsYou, running, done, error, idle }`.
  - `public struct WorkspaceRow: Identifiable, Equatable, Sendable { id: WorkspaceRef; title; directory; branch; ports: [Int]; state: WorkspaceState; question: String?; terminals: [LinkTerminal] }` với `public struct WorkspaceRef: Hashable, Sendable { machineID: String; workspaceId: String }`; `static func rows(workspaces: WorkspaceSet, sessions: [AgentSession], pending: [MachinePendingItem], finished: Set<String>, machineID: String) -> [WorkspaceRow]` — `needsYou` nếu có pending của workspace (question = câu ngắn của pending đầu tiên, dùng `PendingItem+Preview`), rồi `running` nếu có phiên `working`, rồi `done` nếu một phiên của nó nằm trong `finished` (session id do `SessionFinishDetector` báo xong mà chưa có hoạt động mới), không thì `idle`; `error` để dành, chưa phát.
  - `MachineHub`: `public func workspaceRows(machineID: String) -> [WorkspaceRow]`; `public func otherSessions(machineID: String) -> [MachineSession]` (phiên không có `terminal.sessionId` nào trỏ tới, gồm phiên đã kết thúc); `public func createWorkspace(machineID: String) async -> WorkspaceCommandResult`; `public func renameWorkspace(_ ref: WorkspaceRef, title: String) async -> WorkspaceCommandResult`; `public func closeWorkspace(_ ref: WorkspaceRef) async -> WorkspaceCommandResult`; `public func supportsWorkspaceControl(_ machineID: String) -> Bool`.
  - `public enum WorkspaceCommandResult: Equatable, Sendable { case ok(workspaceId: String?), notFound, refused, failed, offline, unknown }` — `unknown` khi mất kết nối giữa lúc chờ (không gửi lại; spec 7.3); `offline` khi Mac không online.
  - `FakeMac`: `public func setWorkspaces(_: [LinkWorkspace])`, `public func upsertWorkspace(_:)`, `public func removeWorkspace(_:)`, `public var workspaceCalls: [String]` (ghi `create`, `rename:<id>:<title>`, `close:<id>`), `public func setNextWorkspaceOutcome(_: WorkspaceControlOutcome)`.

- [ ] **Step 1: Viết test hỏng:** `WorkspaceSetTests` (`applyNextRevision`, `ignoreOldRevision`, `gapReported`, `sortedByOrder`); `WorkspaceRowTests` (`needsYouWinsOverRunning`, `questionFromFirstPending`, `doneFromFinishedSession`, `idleWithoutAgent`); `MachineHubWorkspaceTests` với `FakeMac` (`listArrivesAfterConnect`, `oldMacWithoutFeatureIsUnsupported` — FakeMac không bật nguồn → `workspacesSupported == false`, phiên vẫn có; `gapRefetchesList`; `reconnectReplacesList` — đổi danh sách trong lúc ngắt, nối lại thấy danh sách mới, không còn workspace cũ; `createRenameCloseCallMac`; `refusedCloseKeepsRow`; `otherSessionsExcludeChippedOnes`).
- [ ] **Step 2: Chạy, thấy hỏng.** `shellx-ios/scripts/dev.sh test core` → lỗi biên dịch.
- [ ] **Step 3: Cài đặt** theo Interfaces; giữ khuôn hiện có của `SessionSet`, `applySessions`, `MachineHub.chatSend` (gọi qua `connection.call`).
- [ ] **Step 4: Chạy** `shellx-ios/scripts/dev.sh test core` → PASS (kể cả test cũ).
- [ ] **Step 5: Commit** `feat(shellx-ios): workspace list in the app core`.

### Task 5: iOS — màn chính `WorkspaceListScreen` thay màn chat gộp

**Files:**
- Create: `shellx-ios/ShellX/UI/Workspaces/WorkspaceListView.swift` (nối hub → màn), `WorkspaceListScreen.swift` (bố cục từ giá trị thuần, cho render test), `WorkspaceRowView.swift`, `MachineGroupHeader.swift`, `OtherSessionsView.swift`, `WorkspaceRenameSheet.swift`, `shellx-ios/ShellXTests/WorkspaceListRenderTests.swift`
- Modify: `shellx-ios/ShellX/UI/SignedInView.swift` (gốc = `WorkspaceListView`), `shellx-ios/ShellX/UI/Home/HomeRoute.swift` (thêm `.workspace(WorkspaceRef)`, `.otherSessions(machineID: String)`), `shellx-ios/ShellX/UI/Settings/SettingsView.swift` (thêm mục "Mac của bạn" → `.machines`), `shellx-ios/ShellX/Localizable.xcstrings`, `shellx-ios/ShellX/SignedInScope.swift`/`AppGraph.swift` (bỏ phần của màn chat gộp), `shellx-ios/ShellX/Debug/DemoComposition.swift`
- Delete: màn chat gộp và phần chỉ nó dùng — `UI/Home/HomeView.swift`, `HomeScreen.swift`, `AgentChips.swift`, `HomeNoteRow.swift`, `UserMessageBubble.swift` (nếu chỉ màn này dùng), `UI/Composer/TargetPicker.swift`, `ShellXAppCore/Home/*` không còn ai dùng (`HomeModel`, `HomeDocument`, `HomeEntry`, `HomeNote`, `MachineSession+PreferredTarget`…), `Storage/ConversationStore.swift` + `StoreDocument.swift` nếu chỉ chat gộp dùng; xoá test tương ứng (`HomeRenderTests`, `HomeActionsTests`, `HomeModelTests`, `ConversationStoreTests`, `PreferredTargetTests`…). `NeedsYouBar`, `ComposerBar`, `MicButton`, `AttachMenu`, `AttachmentStrip`, `SessionFinishDetector` **giữ** (màn khác dùng). Trước khi xoá, `grep` từng kiểu để chắc không còn chỗ dùng.

**Interfaces:**
- Consumes: Task 4 (`MachineHub.workspaceRows`, `otherSessions`, `createWorkspace`, `renameWorkspace`, `closeWorkspace`, `supportsWorkspaceControl`, `WorkspaceRow`, `WorkspaceRef`, `WorkspaceCommandResult`).
- Produces: `HomeRoute.workspace(WorkspaceRef)` — đích tạm là `Text(ref.workspaceId)`; Task 6 thay bằng `WorkspaceView`. `WorkspaceListScreen.Actions { openWorkspace(WorkspaceRef); create(machineID: String); rename(WorkspaceRef, String); close(WorkspaceRef); openPending(); openSettings(); openMachines(); openOtherSessions(machineID: String) }`.

Hành vi (spec 6.1, 6.3, 6.4): tiêu đề "Workspace"; phải: chuông có số (mở `.pending`), ＋, cài đặt; thanh "Cần bạn · N" (`NeedsYouBar`) khi N > 0; nhóm theo Mac (Mac mặc định đầu; ngoại tuyến mờ, "ngoại tuyến · lần cuối HH:MM", không dòng con); dòng workspace: tên, dòng mono `nhánh · thư mục · :cổng`, nhãn trạng thái (`AgentStateStyle`), câu hỏi, viền chủ đạo khi `needsYou`; vuốt trái "Đổi tên" / "Đóng" (chỉ khi `supportsWorkspaceControl`); `WorkspaceRenameSheet` điền sẵn tên hiện tại, nút Lưu tắt khi tên bỏ khoảng trắng hai đầu là rỗng; đóng → `confirmationDialog` "Các terminal trong workspace sẽ bị tắt trên Mac"; ＋ với >1 Mac online → chọn Mac; tạo xong `ok(id)` → mở `.workspace`; `refused` → alert "Mac không cho đóng workspace cuối cùng" (đóng) / "Mac đang chặn điều khiển từ xa" (tạo, đổi tên); `unknown` → "Chưa rõ lệnh đã tới Mac chưa, hãy xem lại danh sách"; kéo để làm mới; Mac không có feature → dòng "Cập nhật ShellX trên Mac để quản lý workspace"; dòng "Phiên agent khác · N" khi N > 0 → `OtherSessionsView` (danh sách phiên, chạm mở `AgentView` qua `SessionRef`). Lần mở đầu tiên của bản mới xoá file dữ liệu chat gộp cũ (một hàm dọn trong `AppComposition`, chạy một lần, cờ trong `UserDefaults`).

- [ ] **Step 1: Viết render test hỏng** `WorkspaceListRenderTests` (khuôn `HomeRenderTests`/`MachinesRenderTests` + `SnapshotWriter`): `rendersGroupsAndStates` (2 Mac, một ngoại tuyến; 4 workspace đủ 4 trạng thái; một dòng có câu hỏi) — kiểm view dựng được và các nhãn có mặt qua accessibility identifier `workspace.row.<id>`, `workspace.state.<id>`; `rendersOldMacBanner`; `rendersOtherSessionsRow`; ghi PNG sáng và tối.
- [ ] **Step 2: Chạy, thấy hỏng.** `shellx-ios/scripts/dev.sh test app` → lỗi biên dịch.
- [ ] **Step 3: Cài đặt** các view, nối route, xoá màn chat gộp, thêm chuỗi `en`/`vi` (khoá kiểu `workspaces.title`, `workspaces.close.confirm`…), Mac giả trong demo có 4 workspace như mockup (`shellx-ios`, `relay`, `web`, `notes`).
- [ ] **Step 4: Chạy** `shellx-ios/scripts/dev.sh test all` → PASS; `scripts/shellx/check-ios-license.sh` → không vi phạm; `python3 shellx-ios/scripts/check-strings.py` → sạch. Xem PNG render ở thư mục `SnapshotWriter` in ra, so với `structure.html` hướng A.
- [ ] **Step 5: Commit** `feat(shellx-ios): the workspace list is the home`.

### Task 6: iOS — màn workspace `WorkspaceView` (chip pane, pane agent, ô giữ chỗ, menu)

**Files:**
- Create: `shellx-ios/ShellX/UI/Workspaces/WorkspaceView.swift` (nối hub), `WorkspaceScreen.swift` (bố cục thuần), `PaneChips.swift`, `ShellPanePlaceholder.swift`, `shellx-ios/ShellXTests/WorkspaceRenderTests.swift`
- Modify: `shellx-ios/ShellX/UI/SignedInView.swift` (đích `.workspace` → `WorkspaceView`), `shellx-ios/ShellX/UI/Agent/AgentView.swift`/`AgentScreen.swift` (tách phần thân để nhúng làm pane, không có thanh điều hướng riêng khi nhúng), `Localizable.xcstrings`

**Interfaces:**
- Consumes: Task 4 (`MachineHub` model `workspaces`, `renameWorkspace`, `closeWorkspace`, `WorkspaceRef`), Task 5 (`HomeRoute.workspace`, `WorkspaceRenameSheet`).
- Produces: `struct WorkspaceView: View { init(scope: SignedInScope, ref: WorkspaceRef, open: @escaping (HomeRoute) -> Void) }`.

Hành vi (spec 6.2, 1.1): thanh trên "‹ Workspace", giữa tên + nhánh (mono), phải `•••`; hàng chip = `terminals` theo `order`, chấm trạng thái khi `sessionId` có phiên (`AgentStateStyle`); chip chọn sẵn: terminal có pending → terminal `selected` → chip đầu; vuốt ngang (`TabView` kiểu `.page` không chấm, hoặc `ScrollView` paging) đổi chip; chip có `sessionId` → thân màn agent (chat, thanh "Cần bạn" của workspace, composer có ＋ đính kèm và mic, nút dừng); chip không có → `ShellPanePlaceholder` ("Xem và gõ terminal có ở bản sau"); không có chip `＋`; `•••`: "Đổi tên workspace", "Đóng workspace…" (đỏ, `confirmationDialog`), không có "Đóng pane"; workspace biến mất khỏi danh sách khi đang mở → `dismiss` + báo ngắn "Workspace đã đóng trên Mac"; chip đang xem biến mất → sang chip kế.

- [ ] **Step 1: Viết render test hỏng** `WorkspaceRenderTests`: `agentChipShowsChat` (chip agent chọn sẵn vì có pending); `shellChipShowsPlaceholder`; `defaultChipFollowsMacSelection`; PNG sáng/tối. Test model (thêm vào `MachineHubWorkspaceTests` hoặc một `WorkspaceScreenModelTests` nếu tách logic chọn chip thành hàm thuần `static func defaultTerminal(in: LinkWorkspace, pending: [MachinePendingItem]) -> String?`): `defaultTerminalPrefersPending`, `closedWorkspaceDismisses` (workspace bị xoá khỏi `WorkspaceSet` → trạng thái màn báo `dismissed`).
- [ ] **Step 2: Chạy, thấy hỏng.** `shellx-ios/scripts/dev.sh test all` → lỗi biên dịch.
- [ ] **Step 3: Cài đặt** theo hành vi trên; tái dùng nguyên `AgentScreen` (đừng viết lại chat / composer).
- [ ] **Step 4: Chạy** `shellx-ios/scripts/dev.sh test all` → PASS; `check-ios-license.sh`, `check-strings.py` sạch; so PNG với `workspace-v2.html`.
- [ ] **Step 5: Commit** `feat(shellx-ios): the workspace screen with pane chips`.

### Task 7: Kiểm thử tích hợp, build dogfood, ledger (người điều phối làm)

**Files:**
- Create: `docs/superpowers/ledgers/shellx-mobile-workspaces.md`

- [ ] **Step 1:** `python3 scripts/verify-local.py` cho các vùng đã đổi; ghi kết quả.
- [ ] **Step 2:** Chạy `shellx-link-probe workspaces` và `workspace-create` với một bản Mac build cục bộ (Release, DerivedData riêng, không đụng `build-shellx/…/Release/ShellX.app` người dùng đang chạy) — chỉ khi máy có thông tin đăng nhập dev; nếu không, ghi lại và để người dùng thử trực tiếp.
- [ ] **Step 3:** Đưa người dùng lệnh ngắn để tự đổi sang bản Mac mới; cài app iOS: `shellx-ios/scripts/dev.sh device --device-id 51B0EA4F-D2C2-56A2-AC2B-3CD87DBAC107` (máy phải mở khoá).
- [ ] **Step 4:** Ghi vào ledger: SHA, test đã chạy (đỏ/xanh), các tiêu chí 2.2 đo được (1, 2, 6), điều chưa kiểm.
- [ ] **Step 5:** Commit ledger; gộp nhánh vào `develop` khi người dùng đồng ý (memory: được push develop khi xong).
