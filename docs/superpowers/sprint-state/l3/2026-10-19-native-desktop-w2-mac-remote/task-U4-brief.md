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

