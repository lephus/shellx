### Task 14: Mac↔Mac acceptance, checkpoint 2

**Files:** none new (fixes go to the owning task's files). Lane report to L0 (L0 writes the ledger).

- [ ] **Step 1: Preconditions.** G2 done (relay2 + API v2 live, `curl -s https://relay.shellx.pro/v1/version` → 200) and D2/D3 deployed; else run Steps 3–5 against `shellx-fake-api` + local `cmux-relay` (`SHELLX_API_BASE`, DEBUG) and say so in the report.
- [ ] **Step 2: Builds.** Dev tag `l5` (Task 9 recipe) and, at checkpoint 2, L0's integration Release build from `shellx/sprint` with `remoteMachines` flipped. Before L0's build exists: host = dev app, viewer = the e2e harness CLI (`shellx-core-cli` + stock `cmux-tui remote connect`) against the same API.
- [ ] **Step 3: Two builds, distinct paths (Review Focus 1).** Both apps running: `ps -o args= -p $(pgrep -f "cmux-tui server start")` shows two `--session shellx-<hash8>` values; `ls -ld $TMPDIR/sx-*` → two dirs `drwx------`; `ls -l ~/Library/Application\ Support/ShellX/remote/` → two bundle-id dirs; both machines listed on both apps.
- [ ] **Step 4: Pair, approve, view, type.** From the dev app request access to the Release app; codes and fingerprints match on both screens (photo for the report); approve on the Release app; open the session; in the viewer pane type `tieengs Vieetj` with macOS Vietnamese Telex and with EVKey → the host pane shows `tiếng Việt` (Review Focus 4); `vim` arrows and Ctrl-C work; remote split (`tab create terminal` from the viewer CLI or the pane's split) opens a new tab on the host (D7).
- [ ] **Step 5: Outages (Review Focus 2, 5).** Host Wi-Fi off 30 s → viewer sidebar `reconnecting…`, viewer UI stays responsive (drag the sidebar while waiting), back within 35 s after Wi-Fi on. Quit the host app → viewer shows `offline · last seen HH:MM` within 90 s; relaunch → viewer reconnects without a new pairing. Force-quit the host (`kill -9`), relaunch → `pgrep -fc "cmux-tui server start --session shellx-<hash8>"` → `1`.
- [ ] **Step 6: Spoofing (Review Focus 3).** Two requests at once from the two apps to a third session (or via harness CLI): the prompt shows two different codes; approving one never lets the other in (`remote enroll pending` on the host empties only for the approved invitation).
- [ ] **Step 7: Network audit.** `python3 scripts/shellx/audit_network.py --app "<ShellX DEV l5.app>" --seconds 120 --out /tmp/l5-audit.json` (W1 Task 13) with `SHELLX_REMOTE_MACHINES=1`: the only non-loopback endpoint is `relay.shellx.pro` (record in the report; the script's loopback-only rule needs an allowlist flag for this run — add `--allow-host relay.shellx.pro` if W1 did not).
- [ ] **Step 8: Report** "ready <sha>" with: CI run ids (`shellx-remote`, `shellx-mac`), Steps 3–7 results, known limitations (D7: `\n`→`\r`, focused-terminal projection, invites sealed to the device key), open questions still open.

---

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

### Task U2: Request-access sheet (code + fingerprint)

**Files:**
- Create: `Sources/ShellX/Remote/UI/RequestAccessSheet.swift`, `Sources/ShellX/Remote/UI/RequestAccessModel.swift`
- Test: `cmuxTests/ShellXRemoteUITests.swift`

**Interfaces:**
- Consumes: `OutgoingPairing`, `PairingDisplay` (L5 Task 10); `ShellXRemoteService.outgoing`, `requestAccess(to:)`.
- Produces: `struct RequestAccessModel: Equatable { init(pairing: OutgoingPairing, machineName: String); let title: String; let codeText: String /* "123 456" */; let fingerprintText: String /* "a1b2 c3d4 e5f6 0718" */; let statusText: String?; let showsSpinner: Bool; let primaryAction: Action?; let closesAutomatically: Bool }` with `enum Action { case retry }`.
- Layout: `raise` panel, title (`remote.request.title`), code in 28 pt monospaced `textHi`, label `remote.request.code`; fingerprint 13 pt monospaced `muted` with label `remote.request.fingerprint`; instructions `remote.request.instructions`; footer secondary `common.cancel` (dismiss; the pairing expires server-side). `.waiting` → spinner; `.approved` → `remote.request.approved` in `done`, auto-close after 1 s and `openSession`; `.denied` → `error` text; `.expired`/`.failed` → text + primary `remote.request.retry` (calls `requestAccess` again).

- [ ] **Step 1: Write the failing tests** — `waitingShowsCodeFingerprintAndSpinner` (codeText `"123 456"`, fingerprintText `"a1b2 c3d4 e5f6 0718"`, showsSpinner, no action); `approvedClosesAutomatically`; `deniedShowsErrorWithoutRetry`; `expiredOffersRetry`; `vietnameseTitleTruncatesNotWraps` (model title for a 120-char name equals the full name; the view applies `.lineLimit(1)` — snapshot the view's `lineLimit` via the model's `titleLineLimit == 1`).
- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXRemoteUITests` — Expected: FAIL.
- [ ] **Step 3: Implement**; present as a sheet on the key window from U1's header action.
- [ ] **Step 4: Run** — Expected: PASS; check by eye with fixtures.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx): request-access sheet with code and fingerprint"`

### Task U3: On-site approval prompt on the target Mac

**Files:**
- Create: `Sources/ShellX/Remote/UI/ApprovalPromptPanel.swift`, `Sources/ShellX/Remote/UI/ApprovalPromptModel.swift`
- Modify: the notifications feed entry point used by the title-bar bell (W1 Task 11) — add one "approval needed" item per pending request
- Test: `cmuxTests/ShellXRemoteUITests.swift`

**Interfaces:**
- Consumes: `PairingRequest` (L5 Task 10); `ShellXRemoteService.pendingApprovals`, `approve(_:)`, `deny(_:)`.
- Produces: `struct ApprovalPromptModel: Equatable { init(queue: [PairingRequest], now: Date); let current: PairingRequest?; let title: String; let codeText: String; let fingerprintText: String; let warning: String?; let canApprove: Bool; let queueText: String? /* "1 / 2" */ }`; `final class ApprovalPromptPanel: NSPanel` (floating, titled, not closable by Esc while a request is shown; becomes key so the buttons take clicks).
- Rules: `current` = oldest non-expired request; requests with `now ≥ expiresAt` are dropped (the panel closes when the queue empties); `suspicious` → `warning = remote.approve.suspicious` in `error`, `canApprove = false`; buttons: primary `remote.approve.approve` (disabled when `!canApprove`), secondary `remote.approve.deny`; approve/deny errors shown inline (`fingerprint_mismatch` → the suspicious text). Never auto-approve; no default button (Return does nothing) so a stray keypress cannot approve.

- [ ] **Step 1: Write the failing tests** — `showsOldestRequestWithCodeAndFingerprint`; `suspiciousRequestCannotBeApproved` (Review Focus 3: `canApprove == false`, warning present); `expiredRequestsAreDropped` (`firstSeen + 301 s` → `current == nil`); `queueTextCountsPending` (`"1 / 2"`); `returnKeyHasNoDefaultAction` (panel `defaultButtonCell == nil`).
- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXRemoteUITests` — Expected: FAIL.
- [ ] **Step 3: Implement**; the service's `pendingApprovals` change shows/updates the panel; add the bell item.
- [ ] **Step 4: Run** — Expected: PASS; check by eye with a fixture request and a suspicious one.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx): on-site approval prompt comparing code and fingerprint"`

### Task U4: Offline and reconnecting states for remote sessions

**Files:**
- Create: `Sources/ShellX/Remote/UI/RemoteLinkBanner.swift`, `Sources/ShellX/Remote/UI/RemoteLinkBannerModel.swift`
- Modify: the workspace content container that hosts the presence strip (spec §7.1 "dải hiện diện"; find it next to the session bar view) — show the banner for workspaces in `remoteWorkspaces`
- Test: `cmuxTests/ShellXRemoteUITests.swift`

**Interfaces:**
- Consumes: `LinkState`, `RemoteMachine`; `ShellXRemoteService.remoteWorkspaces`, `machines`. The pane itself already prints `[ShellX] đang kết nối lại… / reconnecting…` from the attach wrapper (L5 Task 10, D8).
- Produces: `struct RemoteLinkBannerModel: Equatable { init(machine: RemoteMachine, now: Date); let text: String?; let tone: Tone; let showsSpinner: Bool }`, `enum Tone { case muted, error }`.
- Rules: `.connected`/`.idle` → `text == nil` (no banner); `.connecting`/`.reconnecting` → `remote.banner.reconnecting`, `muted`, spinner, plus "· retry in Ns" from `retryAt` (`max(0, ceil)`); `.offline` → `remote.banner.offline`, `muted`; `.failed(code)` → `remote.banner.failed` with the code, `error`. Banner height fixed 28 pt, flat `raise` fill, 1 px `line` bottom border; never covers the terminal (it pushes the pane down) and never blocks input.

- [ ] **Step 1: Write the failing tests** — `connectedShowsNoBanner`; `reconnectingShowsCountdown` (`retryAt = now + 3.2` → text ends with `"retry in 4s"`); `offlineExplainsResume`; `failedShowsCodeInErrorTone`; `bannerHeightIsFixed`.
- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXRemoteUITests` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — Expected: PASS. With L5's dev build: open a remote session, turn the host's Wi-Fi off → banner shows reconnecting with countdown and the pane prints the wrapper message; Wi-Fi on → banner disappears.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx): offline and reconnecting banner for remote sessions"`. Report "ready <sha>" to L0.

---

## Open questions and risks (unverified when this plan was written)

1. **D2 / D3 conflict with the L4 plan as written** (its target `GET` omits `requester_x25519_b64`; its ticket mint refuses `connect` to one's own machine with 400). Without D2 no pairing can be approved; without D3 Task 8 Step 6's placeholder path must pass. L0 must rule at T+0 and tell L4.
2. **`requester_fingerprint`**: the L4 plan copies the requester **machine's** noise-key fingerprint (`sha256(key).hex[0:16]`). D1 makes that key the same as `requester_x25519`, so local and server fingerprints match. This breaks if any client registers a different key than it pairs with (L6 must follow D1). L4 also revokes grants when a machine re-registers with a new key, so wiping `state_dir` means pairing again.
3. **`--remote-state-dir` durability with `--ephemeral`**: assumed enrolled devices persist across daemon restarts (Task 8 `test_enrolled_device_reconnects_after_daemon_restart` decides). If not, every host relaunch forces re-pairing.
4. **`server start` has no `--exit-with-parent`**: an app crash leaves an orphan daemon until next launch (mitigated by `serverStop` first). The orphan keeps the slot registered while heartbeats stop.
5. **Disk (7.6 GB free)**: cmux-tui-core tests run only on CI; the local cmux-tui release build plus two app builds may not fit — G0 must free ≥ 30 GB (master gate).
6. **Static link of `shellx-core` into the app**: native libs list (Security/CoreFoundation for the platform verifier) and Rust std alongside the nucleo cdylib are assumed fine; Task 9 Step 4 verifies.
7. **Sprint limitations** (D7): remote `\n` arrives as `\r` (raw PTY-write export in the ghostty fork is post-sprint); viewers see the host's focused terminal plus remote-created tabs, not the full session list; attach snapshot turns palette colors into fixed RGB.
8. **Windows ACLs** for `shellx-core`'s state dir are not hardened in the sprint (Task 2 note); L6 stores the token there.
9. **`requester_x25519` is the long-lived device key** (D1): invites have no forward secrecy; acceptable because single-use and ≤ 300 s, revisit with Keychain storage.
10. **Upstream gate files** (`DevicesFeature`, `MobileHostService`, `PresenceSettings`) are edited by both L1 (W1 Task 5) and L5 (Task 13): Task 13 waits for checkpoint 1 to avoid a conflict.
