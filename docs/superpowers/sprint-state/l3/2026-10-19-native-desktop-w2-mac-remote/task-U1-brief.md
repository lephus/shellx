# Part B — Mac remote UI (lane L3, after W1 Task 10)

Prerequisites: W1 Task 10 merged on `shellx/l3-sidebar`; L5 Task 10 merged into `shellx/sprint` (merge sprint into `shellx/l3-sidebar` when L5 posts "ready (package)"). Until L5 Task 13 lands, views read a `RemoteUISnapshot` built from fixtures; after it lands, `RemoteUISnapshot(service:)` reads `ShellXRemoteService.shared`. All views: palette §7.4 tokens from `ShellXPalette`, flat fills, 1 px borders, coolicons via `ShellXIcon`, labels truncate with `.byTruncatingTail`, fixed row/header heights (W1 RF5). Primary button = `primarySoft` fill + `primaryLine` border + `primaryText`; secondary = `raise` + `border` + `text`.

Strings (add to the catalog with Vietnamese):

| Key | English | Tiếng Việt |
| --- | --- | --- |
| `remote.signin.row` | Sign in to see your other machines | Đăng nhập để thấy các máy khác |
| `remote.signin.title` | Sign in to ShellX | Đăng nhập ShellX |
| `remote.signin.error.credentials` | Email or password is incorrect | Email hoặc mật khẩu không đúng |
| `remote.signin.error.network` | Can't reach relay.shellx.pro | Không kết nối được relay.shellx.pro |
| `remote.machine.offline` | offline · last seen %@ | ngoại tuyến · lần cuối %@ |
| `remote.machine.requestAccess` | Request access | Xin quyền |
| `remote.machine.waiting` | waiting · %@ | đang chờ · %@ |
| `remote.machine.reconnecting` | reconnecting… | đang kết nối lại… |
| `remote.machine.connecting` | connecting… | đang kết nối… |
| `remote.request.title` | Request access to %@ | Xin quyền vào %@ |
| `remote.request.instructions` | On %@, approve only if the code and fingerprint match this screen. | Trên %@, chỉ chấp thuận nếu mã và vân tay khớp với màn hình này. |
| `remote.request.code` | Code | Mã |
| `remote.request.fingerprint` | This Mac's fingerprint | Vân tay của máy này |
| `remote.request.approved` | Approved | Đã được chấp thuận |
| `remote.request.denied` | Denied | Bị từ chối |
| `remote.request.expired` | Expired | Đã hết hạn |
| `remote.request.retry` | Try again | Thử lại |
| `remote.approve.title` | %@ wants to view and control this Mac | %@ muốn xem và điều khiển máy này |
| `remote.approve.compare` | Approve only if the code and fingerprint match the other screen. | Chỉ chấp thuận nếu mã và vân tay khớp với màn hình máy kia. |
| `remote.approve.suspicious` | The fingerprint does not match what the server reports. Do not approve. | Vân tay không khớp với thông tin máy chủ. Đừng chấp thuận. |
| `remote.approve.approve` | Approve | Chấp thuận |
| `remote.approve.deny` | Deny | Từ chối |
| `remote.approve.queue` | %lld of %lld | %lld / %lld |
| `remote.banner.reconnecting` | Reconnecting to %@… | Đang kết nối lại tới %@… |
| `remote.banner.offline` | %@ is offline. The session resumes when ShellX opens there. | %@ đang ngoại tuyến. Phiên tiếp tục khi ShellX được mở trên máy đó. |
| `remote.banner.failed` | Can't connect to %@ (%@) | Không kết nối được tới %@ (%@) |
| `common.cancel` | Cancel | Huỷ |

### Task U1: Remote machine groups and sign-in in the sidebar

**Files:**
- Modify: `Sources/ShellX/Sidebar/SidebarMachineGrouping.swift`, `Sources/ShellX/Sidebar/SidebarMachineHeaderCellView.swift`, `Sources/ShellX/Sidebar/SidebarBrandHeaderView.swift` (W1 Task 10 files)
- Create: `Sources/ShellX/Remote/UI/RemoteUISnapshot.swift`, `Sources/ShellX/Remote/UI/SignInSheet.swift`
- Test: `cmuxTests/SidebarMachineGroupingTests.swift` (extend), `cmuxTests/ShellXRemoteUITests.swift`

**Interfaces:**
- Consumes: `RemoteMachine`, `LinkState` (L5 Task 10); `ShellXRemoteService` `machines`, `isSignedIn`, `remoteWorkspaces`, `requestAccess`, `openSession`, `signIn` (L5 Task 13).
- Produces: `SidebarMachineKey` gains `case remote(machineID: String)`; `SidebarMachineInput` gains `let remoteMachineID: String?` (default `nil`); `SidebarMachineGrouping.sections(for:local:remote: [RemoteMachine], now: Date)` (W1's `sections(for:local:)` stays as a wrapper passing `remote: []`, so W1 tests keep passing); `SidebarMachineHeaderModel` gains `let isDimmed: Bool` and `let action: SidebarMachineHeaderAction?` with `enum SidebarMachineHeaderAction: Equatable { case requestAccess, waiting(code: String), open, reconnecting, connecting }`; `struct RemoteUISnapshot { machines: [RemoteMachine]; isSignedIn: Bool; remoteWorkspaces: [UUID: String]; pendingApprovals: [PairingRequest]; outgoing: [OutgoingPairing] }`.
- Rules: order = local, then remote machines (online first, then offline; each by `name` localized-standard), then SSH (W1 order). `isThisMachine` is never a remote section. Remote header: coolicon `Laptop` (macos) / `Desktop` (windows); online → note `""`, dot `done`; offline → note `remote.machine.offline` with `lastSeen` as `HH:mm` (24 h, local time; `—` when nil), `isDimmed = true` (alpha 0.5), **no rows** (U14) even if workspaces are tagged; action: `access == .none` → `.requestAccess`; `.requested(_, code)` → `.waiting(code: PairingDisplay.code(code))`; granted + `.idle`/`.connected` → `.open`; `.connecting` → `.connecting`; `.reconnecting` → `.reconnecting`. Rows: workspaces whose id is in `remoteWorkspaces` go under that machine. Signed out (gate on) → one row `remote.signin.row` under "YOUR MACHINES" opening `SignInSheet` (email field, secure field, primary "Sign in", inline error from `ShellXCoreError.code`: `invalid_credentials` → `remote.signin.error.credentials`, `network` → `remote.signin.error.network`, else the code).

- [ ] **Step 1: Write the failing tests**

```swift
let mac = LocalMachineInfo(name: "MacBook Pro", isLaptop: true)
func rm(_ id: String, _ name: String, online: Bool, access: RemoteMachine.Access = .granted, link: LinkState = .idle, last: Date? = nil) -> RemoteMachine { … }
@Test func remoteMachinesSitBetweenLocalAndSSH() {
  let s = SidebarMachineGrouping.sections(for: [.init(workspaceID: 1, sshTarget: "u@vm", sshConnected: true, remoteMachineID: nil)], local: mac, remote: [rm("m1", "Mac mini", online: true)], now: t0)
  #expect(s.map(\.header.key) == [.local, .remote(machineID: "m1"), .ssh(target: "u@vm")])
}
@Test func onlineBeforeOfflineThenByName() {}
@Test func offlineRemoteIsDimmedWithLastSeenAndNoRows() {
  let s = SidebarMachineGrouping.sections(for: [.init(workspaceID: 9, sshTarget: nil, sshConnected: false, remoteMachineID: "m1")], local: mac,
    remote: [rm("m1", "Mac mini", online: false, last: date("14:05"))], now: t0)
  #expect(s[1].header.isDimmed && s[1].header.note == "offline · last seen 14:05" && s[1].workspaceIDs.isEmpty)
}
@Test func thisMachineIsNeverARemoteSection() {}
@Test func headerActionFollowsAccessAndLink() { /* .none → .requestAccess; .requested(code "123456") → .waiting("123 456"); granted+.reconnecting → .reconnecting */ }
@Test func remoteWorkspaceRowsGroupUnderTheirMachine() {}
@Test func longRemoteNameKeepsHeaderHeight() { /* W1 RF5 calculator, 6× "Máy tính văn phòng tầng 3 " */ }
@Test func signInErrorMapping() { /* invalid_credentials / network / other */ }
```

- [ ] **Step 2: Run** `scripts/shellx/test-app.sh SidebarMachineGroupingTests ShellXRemoteUITests` — Expected: FAIL.
- [ ] **Step 3: Implement**; header action button: `.requestAccess` → small primary button calling `requestAccess` then presenting U2's sheet; `.open` → clicking the header calls `openSession`; trailing dot colors per palette.
- [ ] **Step 4: Run** the tests — Expected: PASS. Dev build with fixtures (DEBUG env `SHELLX_REMOTE_UI_FIXTURES=1` injects a snapshot with one online, one offline, one requested machine): compare with the mockup's machine groups.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx): remote machine groups and sign-in in the sidebar"`

