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

