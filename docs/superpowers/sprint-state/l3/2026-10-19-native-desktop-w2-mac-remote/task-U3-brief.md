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

