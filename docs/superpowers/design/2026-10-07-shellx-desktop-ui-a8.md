# ShellX desktop A8 — UI addendum (workspace SSH, trạng thái kết nối, hộp kết nối, tmux, cổng từ xa)

- **Ngày:** 2026-10-07 · **Phạm vi:** A8 của `docs/superpowers/specs/2026-10-07-desktop-ssh-a8-design.md` (ràng buộc; S1–S7, D1–D44). Tài liệu này **thêm** vào UI doc A1 `2026-10-06-shellx-desktop-ui.md` ("A1 §N"), A2 ("A2 §N"), A3 ("A3 §N"), A4 ("A4 §N"), A5 ("A5 §N"), A6 ("A6 §N"); mọi token, kiểu chữ, trạng thái, quy tắc focus và copy của các tài liệu đó vẫn giữ.
- **Nguyên tắc:** pane SSH trông **như pane cục bộ** — khác biệt chỉ là một dấu nhỏ và chữ trong dòng ngữ cảnh. Trạng thái kết nối dùng lại ngôn ngữ chấm của A1 (không màu mới). Không có hộp mật khẩu: xác thực là chữ trong terminal. Không hoạt ảnh lặp (chấm "đang kết nối" là chấm nhỏ tĩnh, không nhấp nháy).
- **Không có token màu mới.** Mọi màu từ A1 §1.1. Tương phản theo WCAG 2.x, tính lại cho mọi cặp mới bên dưới.

---

## 1. Token dùng lại và kích thước mới

### 1.1 Màu

| Dùng cho | Token | Trên nền | Tương phản |
|---|---|---|---|
| Dấu SSH / dấu tmux trên dòng và đầu pane | `textSecondary` `#93A5A9` | `bgSidebar` / `rowSelected` | 6.8 / 6.0 (≥ 3, thành phần không phải chữ) |
| Chấm "đang kết nối" (chấm đặc 4 px giữa ô 8) | `textSecondary` | `bgSidebar` / `rowSelected` | 6.8 / 6.0 |
| Chấm "mất kết nối"/"không kết nối được" | vòng rỗng 1,5 px `err` `#F07178` (đúng chấm thoát A1) | `bgSidebar` | 6.1 |
| Biểu tượng máy chủ trên tiêu đề workspace | `textSecondary` | `bgSidebar` / `rowHover` | 6.8 / 6.2 |
| Dải pane: nền / viền trên | `bgSidebar` / `line` | — | — |
| Dải pane: chữ chính | `textPrimary` | `bgSidebar` | 13.1 |
| Dải pane: chữ phụ (đếm giờ, gợi ý tmux) | `textSecondary` | `bgSidebar` | 6.8 |
| Dải pane: biểu tượng `Icons.link_off` | `err` (disconnected/failed) | `bgSidebar` | 6.1 |
| Vạch "— Đã kết nối lại · 14:32 —" | SGR mờ (`ESC[2m`) trên `textPrimary` của terminal, như vạch A5a | `bgTerminal` | 5.0 (giống vạch A5a, đã đo ở A5 §1.1) |
| Dòng mờ "[Mất kết nối tới …]" | như dòng thoát A1 §2.6: mờ, tên máy **không** đỏ | `bgTerminal` | 5.0 |
| Cổng từ xa (liên kết) | `accent` (như A2 §2.4) | `bgSidebar` | 10.0 |
| Hộp kết nối: thẻ đang chọn (gạch chân 2 px) | `accent` | `surface` | 9.6 |
| Hộp kết nối: chữ thẻ không chọn | `textDialog2` | `surface` | 7.9 |
| Danh sách gợi ý/phiên tmux: dòng chọn | nền `primarySoft`, chữ `textTitle` | — | 12.2 |
| Nhãn nhóm gợi ý ("Trong ~/.ssh/config", "Gần đây") | `textSecondary` `caption` | `surface` | 6.2 |
| "đang gắn ở nơi khác" | `warn` `caption` | `surface` | 9.0 |

### 1.2 Kích thước mới (thêm vào `ShellxSizes`)

| Tên | Giá trị | Ghi chú |
|---|---|---|
| `remoteMark` | 12 | glyph dấu SSH/tmux trên dòng (cạnh dấu số pane A3, cùng cỡ `paneCountIcon`) |
| `remoteMarkGap` | 2 | giữa glyph và chữ (nếu có) |
| `connectingDot` | 4 | chấm "đang kết nối" (giữa ô 8; hình khác cả ba chấm A1 — WCAG 1.4.1) |
| `remoteStrip` | 32 | dải trạng thái trong pane (đáy pane, vẽ đè lên terminal, không đổi lưới PTY) |
| `remoteStripPadH` | 8 | |
| `remoteStripButton` | 24 | nút chữ nhỏ trong dải (`small` w600, `r6`, lề ngang 8) |
| `connectDialogWidth` | 520 | = `dialogWidthLong` A1 |
| `connectTabBar` | 32 | hàng thẻ SSH \| tmux |
| `suggestionRow` | 28 | dòng gợi ý / dòng phiên tmux một dòng |
| `tmuxRow` | 40 | dòng phiên tmux hai dòng (tên + chi tiết) |
| `suggestionListMax` | 8 | số dòng tối đa trước khi cuộn |

### 1.3 Cỡ chữ lớn

Dải pane cao `max(32, scale(18) + 14)`; dòng gợi ý `max(28, scale(18) + 10)`; dòng tmux `max(40, scale(18) + scale(14) + 8)`. Glyph giữ 12/16.

---

## 2. Sidebar

### 2.1 Dòng tab (A2 §2.1 + A3 §3 + A4)

```
|6|● vim — main.go            ①  ▥2  ⌂ |4|×|     ← ⌂ = Icons.dns_outlined 12 (pane focus là SSH)
|6|  feat/x · ~/work/api · :8000          |       ← ngữ cảnh từ xa: ~ là home của MÁY CHỦ
```

- **Dấu SSH:** `Icons.dns_outlined` 12 `textSecondary`, **sau** dấu số pane A3, **trước** 📱 (thứ tự: badge A4 → số pane → SSH/tmux → 📱 → 👁). Hiện khi **pane focus** của tab là pane SSH. Tooltip `sidebarRemoteMark` "SSH: devbox" (đặt bên phải sidebar, chờ 500 ms). Không phải điểm dừng Tab; nằm trong nhãn dòng (§8).
- **Dấu tmux:** `Icons.view_quilt_outlined` 12 `textSecondary`, cùng chỗ; tooltip `sidebarTmuxMark` "tmux: main" (từ xa: "tmux: main · devbox" `sidebarTmuxRemoteMark`).
- Tab trong workspace SSH của chính máy đó **vẫn** hiện dấu (kéo tab sang workspace khác vẫn nhận ra).
- **Dòng ngữ cảnh:** như A2 §2.2 (thứ tự nhánh · thư mục · cổng, cùng thuật toán chật). Thư mục từ xa rút `~` theo home **từ xa** (OSC 6973 `home`), luôn `/` (không bao giờ `\`). Không có tiền tố máy chủ (dấu đã nói); tooltip đầy đủ của A2 §2.2 bước 5 thêm `devbox:` trước thư mục: `feat/x · devbox:~/work/api · :8000`.
- **Cổng từ xa:** cùng kiểu liên kết A2 §2.4. Tooltip `remotePortTooltip` "Mở cổng 8000 trên devbox (chuyển tiếp qua SSH)"; đã chuyển tiếp → `remotePortForwarded` "localhost:53012 → devbox:8000". Bấm khi đang chuyển tiếp lần đầu: liên kết nhấn (`rowPressed`) tới khi trình duyệt mở (≤ 2 s), không spinner.

### 2.2 Chấm trạng thái (A1 §3.1, cho pane focus là SSH/tmux từ xa)

| Trạng thái | Chấm (ô 16) | Nhãn trợ năng thêm |
|---|---|---|
| `connecting` | chấm đặc 4 px `textSecondary` giữa ô 8 (A1 có: đặc 8 = rảnh, vòng + tâm = chạy lệnh, vòng rỗng = thoát) | `sshStateConnecting` |
| `connected` | như A1 (idle `ok`, chạy lệnh `accent`) | — |
| `disconnected` | vòng rỗng `err` (= chấm thoát A1) | `sshStateDisconnected` |
| `failed` | vòng rỗng `err` (= chấm thoát A1) | `sshStateFailed` |
| `exited` | như A1 (chấm thoát) | — |

Giảm chuyển động: không ảnh hưởng (không hoạt ảnh).

### 2.3 Tiêu đề workspace SSH (A2 §3.1)

```
|6|4|▾|4| ⌂ devbox (small 600, ellipsis)                |4|[ 3 | + ]|6|6|
          ↑ Icons.dns_outlined 12 textSecondary, 4 px trước tên
```

- Chấm tổng hợp **không** có (trạng thái đã trên từng dòng). `+` (tooltip `workspaceNewRemoteTab` "Tab SSH mới tới devbox") mở tab SSH.
- Menu tiêu đề (A2 §5.2) thêm nhóm trên cùng: "Tab SSH mới" (⌘T khi workspace là hiện tại), "Tab cục bộ mới", "Kết nối lại mọi pane" (mờ khi không có pane `disconnected`/`failed`), vạch, rồi các mục A2.

---

## 3. Pane

### 3.1 Đầu pane (A3 §2.1, khi tab có ≥ 2 pane)

`|8| chấm (§2.2) |6| ⌂ 12 |4| tiêu đề (small, flex) |4| [📱/👁] [chưa đọc] [Phóng to · i/n] |4| × |4|` — dấu SSH/tmux trước tiêu đề, tooltip như §2.1. Pane cục bộ không đổi.

### 3.2 Dải trạng thái kết nối (trong pane, đáy)

Hiện khi pane là `disconnected` hoặc `failed`. Vẽ **đè** lên đáy vùng terminal (Stack, không đổi lưới, không resize PTY — pane đã không còn phiên sống). Nền `bgSidebar`, vạch trên 1 px `line`, cao 32.

```
┌────────────────────────────────────────────────────────────────────────────┐
│ ~ $ make test                                                              │
│ …                                                                          │
│ [Mất kết nối tới devbox] — Enter để kết nối lại                    (mờ)    │
├────────────────────────────────────────────────────────────────────────────┤
│ ⛓ Mất kết nối tới devbox · Thử lại sau 12 giây       [Kết nối lại] [Đóng pane] │ ← 32, bgSidebar
└────────────────────────────────────────────────────────────────────────────┘
```

| Trạng thái | Chữ chính | Chữ phụ | Nút |
|---|---|---|---|
| `disconnected`, đang chờ | `sshStateDisconnected` | `sshRetryIn` (đếm ngược mỗi giây, `textSecondary`) | **Kết nối lại**, Đóng pane |
| `disconnected`, đang thử | `sshStateDisconnected` | `sshRetrying` | Đóng pane |
| `disconnected`, đã ngừng (30 phút) | `sshStateDisconnected` | `sshAutoRetryStopped` | **Kết nối lại**, Đóng pane |
| `failed`, mã 255 | `sshStateFailed` | — | **Thử lại**, Đóng pane |
| `failed`, mã ≠ 255, đã dùng hook | `sshStateFailed` | `sshFailedHookHint` | **Thử lại**, Thử lại không dùng hook, Đóng pane |

- `|8| Icons.link_off 16 err |6| chữ chính (body, textPrimary) |4| · chữ phụ (body, textSecondary, ellipsis) | flex |6| nút… |8|`. Bề rộng hẹp (< 360): chữ phụ ẩn trước (vẫn trong nhãn trợ năng), rồi chữ chính ellipsis; nút không bao giờ bị cắt.
- Nút: kiểu Secondary nhỏ (A1 §3.3, cao 24, `small` w600), nút chính đậm hơn (Primary nhỏ). Thứ tự theo A1 (macOS chính bên phải; Windows chính bên trái).
- Gợi ý tmux (`sshTmuxHint`) là tooltip của chữ chính khi pane là SSH thường (không tmux).
- Dòng mờ trong terminal: `sshDisconnectedLine` / `sshFailedLine` (như dòng thoát A1 §2.6: mờ, con trỏ ẩn; không tô đỏ phần nào). Enter trong pane = nút chính.
- Pane trong tab không chọn: dải vẫn có (thấy khi chọn tab); chấm dòng (§2.2) đã báo.

### 3.3 Đang kết nối

Không dải. Terminal hiện đúng những gì ssh in (lời nhắc mật khẩu, câu hỏi host key). Chấm nhỏ §2.2 trên dòng/đầu pane. Không spinner, không lớp phủ (lời nhắc mật khẩu phải đọc được ngay).

### 3.4 Vạch kết nối lại

Ngay khi phiên mới gắn vào pane: dòng `ESC[0m ESC[2m — Đã kết nối lại · 14:32 — ESC[0m` (`sshReconnectedDivider`, giờ theo A5a D23), rồi output mới. Con trỏ hiện lại.

---

## 4. Hộp "Kết nối tới máy chủ" (spec D42)

Container A1 §4 (`surface`, `r12`, `e2`, padding 24, rộng 520), tiêu đề `dialogTitle`. Esc = Huỷ. Một hộp tại một thời điểm (A1 `WindowRouter`, route mới `SshConnectRoute(tab)`).

### 4.1 Thẻ SSH

```
┌──────────────────────────────────────────────────────────┐
│ Kết nối tới máy chủ                                    ✕ │ ← ✕ chỉ Windows (A1 §4)
│  SSH    tmux                                             │ ← hàng thẻ 32; thẻ chọn: gạch 2 px accent
│  ▔▔▔                                                     │
│ Máy chủ                                                  │ ← label
│ ┌──────────────────────────────────────────────────────┐ │
│ │ dev▏                                                 │ │ ← input 36, gợi ý devbox hoặc user@host:2222
│ └──────────────────────────────────────────────────────┘ │
│ ┌──────────────────────────────────────────────────────┐ │ ← danh sách gợi ý (surfaceInset, r6, viền border)
│ │ TRONG ~/.SSH/CONFIG                                  │ │   nhãn nhóm caption textSecondary
│ │▌devbox                                               │ │ ← dòng chọn: primarySoft + thanh accent 3
│ │ dev-db                                               │ │
│ │ GẦN ĐÂY                                              │ │
│ │ me@dev.example.com:2222                              │ │
│ └──────────────────────────────────────────────────────┘ │
│ Thư mục trên máy chủ (không bắt buộc)                    │
│ ┌──────────────────────────────────────────────────────┐ │
│ │ /srv/app                                             │ │
│ └──────────────────────────────────────────────────────┘ │
│ ☐ Không cài hook ShellX trên máy này                     │
│   Hook cho ShellX biết thư mục, nhánh và cổng trên máy   │ ← caption textSecondary
│   chủ. Tắt khi máy chủ không phải Unix.                  │
│                                      [Huỷ] [Kết nối]     │
└──────────────────────────────────────────────────────────┘
```

- Ô "Máy chủ" nhận focus khi mở. Danh sách gợi ý hiện ngay (cả khi ô trống: mọi gợi ý), lọc theo **chuỗi con** không phân biệt hoa thường; khớp làm đậm (`bodyStrong`). Tối đa 8 dòng rồi cuộn. ↑/↓ di chuyển chọn (vòng ở hai đầu: không), Enter khi có dòng chọn → điền ô **và** kết nối; Tab → điền ô, sang ô kế. Không có gì khớp → danh sách ẩn.
- Lỗi D4 hiện dưới ô khi bấm Kết nối (A1 §3.4 lỗi trường: viền `errDialog`, chữ `sshHostInvalid`), focus giữ ở ô.
- Chọn một đích nằm trong danh sách "không hook" → ô kiểm tự đánh dấu.
- "Kết nối": hộp đóng **ngay**; tab mới được chọn, terminal nhận focus (người dùng gõ mật khẩu nếu cần). Không có ssh (D3) → hộp vẫn đóng, toast lỗi `sshUnavailable`.

### 4.2 Thẻ tmux

```
┌──────────────────────────────────────────────────────────┐
│ Kết nối tới máy chủ                                      │
│  SSH    tmux                                             │
│         ▔▔▔▔                                             │
│ Phiên tmux trên                                          │
│ ┌──────────────────────────────────────────────────────┐ │
│ │ Máy này                                          ▾   │ │ ← cùng ô có gợi ý như 4.1; mục đầu "Máy này"
│ └──────────────────────────────────────────────────────┘ │   (Windows: không có "Máy này")
│ ┌──────────────────────────────────────────────────────┐ │
│ │▌main                                    3 cửa sổ     │ │ ← dòng 40: tên bodyStrong; dòng 2 caption:
│ │  hoạt động 5 phút trước                              │ │   "hoạt động …" textSecondary
│ │ build                    1 cửa sổ · đang gắn ở nơi khác│ │   "đang gắn ở nơi khác" warn
│ │  hoạt động hôm qua 18:02                             │ │
│ └──────────────────────────────────────────────────────┘ │
│ Tên phiên mới                                            │
│ ┌────────────────────────────────────┐ [Tạo và gắn]      │
│ │ notes                              │                   │
│ └────────────────────────────────────┘                   │
│                                        [Huỷ] [Gắn]       │
└──────────────────────────────────────────────────────────┘
```

| Trạng thái danh sách | Nội dung (giữa vùng danh sách, `body` `textSecondary`) |
|---|---|
| Đang lấy | `tmuxLoading` (sau 300 ms mới hiện, tránh nháy) |
| Rỗng | `tmuxEmpty` |
| Không có tmux | `tmuxUnavailable` |
| Lỗi (255 / hết giờ) | `tmuxListFailed` + nút liên kết "Thử lại" |

- Đổi "Phiên trên" → lấy lại danh sách (huỷ lần lấy trước). Dòng đầu được chọn sẵn; ↑/↓, Enter = Gắn; nháy đúp = Gắn.
- "Tên phiên mới": tên sai (D25) → lỗi dưới ô `tmuxNameInvalid`. "Tạo và gắn" = `new-session -A` (tên đã có → gắn vào nó).
- "Gắn" mờ khi không có dòng chọn.
- Thời gian "hoạt động": hôm nay `HH:mm` hoặc "{n} phút trước" (< 60 phút), hôm qua, cũ hơn — cùng hàm định dạng A4 (`relativeTime`).

---

## 5. Menu, phím tắt, tray

### 5.1 Phím tắt

| Hành động | macOS | Windows | Phạm vi |
|---|---|---|---|
| Kết nối SSH… (hộp, thẻ SSH) | ⌘⇧K | Ctrl+Shift+K | toàn cửa sổ |
| Tab mới (trong workspace SSH: tab SSH) | ⌘T | Ctrl+Shift+T | như A1 |
| Kết nối lại (pane `disconnected`/`failed` focus) | Enter (trong pane) | Enter | pane |

### 5.2 Menu

- **`+` đầu sidebar** — chuột phải / Shift+F10 / phím Menu: "Tab mới ⌘T", "Kết nối SSH… ⌘⇧K", "Gắn phiên tmux…". Bấm trái giữ A1 (tab mới theo workspace hiện tại — workspace SSH thì tab SSH).
- **Menu terminal (A3 §4.1)** trên pane SSH: sau "Chia xuống dưới" thêm "Chia cục bộ sang phải" (`paneSplitLocalRight`, mở shell cục bộ ở home máy mình). Pane `disconnected`/`failed`: thêm "Kết nối lại" đầu menu.
- **Menu dòng tab (A3 §4.2):** tab có pane `disconnected`/`failed` → "Kết nối lại" (`rowReconnect`) đầu menu (kết nối lại mọi pane mất kết nối của tab).
- **Menu tiêu đề workspace SSH:** §2.3.

### 5.3 Tray

```
ShellX ▸ … ▸ Dòng lệnh ▸ (A7)
          ▸ SSH ▸ Kết nối SSH…
                  Gắn phiên tmux…
                  ─────────────
                  ☑ Cài hook ShellX trên máy chủ (thư mục, nhánh, cổng)
                  Xóa danh sách máy gần đây          ← mờ khi danh sách rỗng
          ▸ Thông báo ▸ (A4)
```

Hai mục đầu hiện cửa sổ rồi mở hộp. "Xóa danh sách máy gần đây" → xoá ngay, toast trung tính `sshRecentCleared`.

---

## 6. Bàn phím và focus

- Hộp kết nối: thứ tự Tab: thẻ SSH/tmux (mũi tên ←/→ đổi thẻ, như tab bar) → ô Máy chủ → danh sách gợi ý **không** là điểm dừng (điều khiển bằng ↑/↓ từ ô, `aria-activedescendant` kiểu: Semantics `selected`) → ô Thư mục → ô kiểm → Huỷ → Kết nối. Thẻ tmux: thẻ → ô "Phiên trên" → danh sách phiên (là điểm dừng; ↑/↓, Enter) → ô Tên phiên mới → Tạo và gắn → Huỷ → Gắn.
- Đóng hộp bằng Kết nối/Gắn → focus vào terminal của tab mới; Huỷ/Esc → focus về chỗ cũ.
- Dải trạng thái (§3.2): nút trong vòng vùng A1 §3.6 như một phần của pane: Ctrl+F6 từ terminal pane `disconnected` tới nút chính của dải; Esc trở lại terminal. Enter trong terminal = nút chính (không cần vào dải).
- Pane `disconnected` nhận phím khác Enter: bỏ qua (như pane thoát A3).

---

## 7. Copy (vi + en, khoá ARB)

"SSH", "tmux", "pane", "tab", "workspace", "hook" giữ tiếng Anh trong bản Việt (A3 §7). `{host}` là `SshTarget.key`; `{name}` tên phiên tmux.

| Khoá | vi | en |
|---|---|---|
| `sshConnectMenu` | Kết nối SSH… | Connect over SSH… |
| `tmuxAttachMenu` | Gắn phiên tmux… | Attach tmux session… |
| `sshDialogTitle` | Kết nối tới máy chủ | Connect to a server |
| `sshDialogTabSsh` | SSH | SSH |
| `sshDialogTabTmux` | tmux | tmux |
| `sshHostLabel` | Máy chủ | Server |
| `sshHostHint` | devbox hoặc user@host:2222 | devbox or user@host:2222 |
| `sshHostInvalid` | Không phải tên máy chủ hợp lệ | Not a valid server name |
| `sshSuggestionsConfig` | Trong ~/.ssh/config | In ~/.ssh/config |
| `sshSuggestionsRecent` | Gần đây | Recent |
| `sshSuggestionsCount` | {count} gợi ý | {count, plural, one{1 suggestion} other{{count} suggestions}} |
| `sshRemoteDirLabel` | Thư mục trên máy chủ (không bắt buộc) | Folder on the server (optional) |
| `sshRemoteDirInvalid` | Đường dẫn phải bắt đầu bằng / hoặc ~ | The path must start with / or ~ |
| `sshNoHookLabel` | Không cài hook ShellX trên máy này | Don’t install the ShellX hook on this server |
| `sshNoHookHelp` | Hook cho ShellX biết thư mục, nhánh và cổng trên máy chủ. Tắt khi máy chủ không phải Unix. | The hook tells ShellX the folder, branch and ports on the server. Turn it off for servers that aren’t Unix. |
| `sshConnectAction` | Kết nối | Connect |
| `sshUnavailable` | Không tìm thấy lệnh ssh trên máy này | Can’t find the ssh command on this computer |
| `sshUnavailableWindows` | Không tìm thấy ssh. Bật “OpenSSH Client” trong Settings → Apps → Optional features. | Can’t find ssh. Turn on “OpenSSH Client” in Settings → Apps → Optional features. |
| `tmuxSourceLabel` | Phiên tmux trên | tmux sessions on |
| `tmuxSourceLocal` | Máy này | This computer |
| `tmuxLoading` | Đang lấy danh sách phiên… | Loading sessions… |
| `tmuxEmpty` | Chưa có phiên tmux nào | No tmux sessions yet |
| `tmuxUnavailable` | tmux chưa được cài trên {where} | tmux isn’t installed on {where} |
| `tmuxListFailed` | Không lấy được danh sách phiên trên {where}. Kết nối SSH tới máy này một lần (để không phải nhập mật khẩu) rồi thử lại. | Couldn’t list sessions on {where}. Connect to it over SSH once (so no password is needed), then try again. |
| `tmuxRetry` | Thử lại | Try again |
| `tmuxWindows` | {count, plural, other{{count} cửa sổ}} | {count, plural, one{1 window} other{{count} windows}} |
| `tmuxAttachedElsewhere` | đang gắn ở nơi khác | attached elsewhere |
| `tmuxLastActive` | hoạt động {time} | active {time} |
| `tmuxAttachAction` | Gắn | Attach |
| `tmuxNewLabel` | Tên phiên mới | New session name |
| `tmuxNameInvalid` | Tên chỉ gồm tối đa 64 ký tự, không có “:” hay “.” | Use up to 64 characters, without “:” or “.” |
| `tmuxCreateAction` | Tạo và gắn | Create and attach |
| `sidebarRemoteMark` | SSH: {host} | SSH: {host} |
| `sidebarTmuxMark` | tmux: {name} | tmux: {name} |
| `sidebarTmuxRemoteMark` | tmux: {name} · {host} | tmux: {name} · {host} |
| `sshStateConnecting` | Đang kết nối tới {host} | Connecting to {host} |
| `sshStateDisconnected` | Mất kết nối tới {host} | Lost connection to {host} |
| `sshStateFailed` | Không kết nối được tới {host} | Couldn’t connect to {host} |
| `sshRetryIn` | Thử lại sau {seconds, plural, other{{seconds} giây}} | Retrying in {seconds, plural, one{1 second} other{{seconds} seconds}} |
| `sshRetrying` | Đang kết nối lại… | Reconnecting… |
| `sshAutoRetryStopped` | Đã ngừng tự kết nối lại | Stopped retrying |
| `sshFailedHookHint` | Máy chủ có thể không chạy được hook ShellX | The server may not support the ShellX hook |
| `sshReconnectAction` | Kết nối lại | Reconnect |
| `sshRetryAction` | Thử lại | Try again |
| `sshRetryPlainAction` | Thử lại không dùng hook | Try without the hook |
| `sshClosePaneAction` | Đóng pane | Close pane |
| `sshTmuxHint` | Chạy trong tmux để chương trình vẫn chạy khi mất kết nối | Run inside tmux to keep programs running when the connection drops |
| `sshDisconnectedLine` | [Mất kết nối tới {host}] — Enter để kết nối lại | [Lost connection to {host}] — press Enter to reconnect |
| `sshFailedLine` | [Không kết nối được tới {host}] — Enter để thử lại | [Couldn’t connect to {host}] — press Enter to try again |
| `sshReconnectedDivider` | — Đã kết nối lại · {time} — | — Reconnected · {time} — |
| `workspaceNewRemoteTab` | Tab SSH mới tới {host} | New SSH tab on {host} |
| `workspaceNewLocalTab` | Tab cục bộ mới | New local tab |
| `workspaceReconnectAll` | Kết nối lại mọi pane | Reconnect all panes |
| `workspaceRemoteLabel` | Workspace SSH {host} | SSH workspace {host} |
| `rowReconnect` | Kết nối lại | Reconnect |
| `paneSplitLocalRight` | Chia cục bộ sang phải | Split right on this computer |
| `remotePortTooltip` | Mở cổng {port} trên {host} (chuyển tiếp qua SSH) | Open port {port} on {host} (forwarded over SSH) |
| `remotePortForwarded` | localhost:{local} → {host}:{port} | localhost:{local} → {host}:{port} |
| `remotePortForwardFailed` | Không chuyển tiếp được cổng {port} | Couldn’t forward port {port} |
| `sshTrayMenu` | SSH | SSH |
| `sshTrayHook` | Cài hook ShellX trên máy chủ (thư mục, nhánh, cổng) | Install the ShellX hook on servers (folder, branch, ports) |
| `sshTrayClearRecent` | Xóa danh sách máy gần đây | Clear recent servers |
| `sshRecentCleared` | Đã xóa danh sách máy gần đây | Recent servers cleared |
| `sshAnnounceConnected` | Đã kết nối tới {host} | Connected to {host} |
| `sshAnnounceDisconnected` | Mất kết nối tới {host} | Lost connection to {host} |
| `sshAnnounceReconnected` | Đã kết nối lại tới {host} | Reconnected to {host} |
| `paneRemoteSuffix` | , trên {host} | , on {host} |

- Tiêu đề tự động của tab tmux "tmux: {tên}" do agent đặt (spec D26) — giống nhau ở mọi ngôn ngữ, không có khoá ARB.
- `port`, `local`, `count`, `seconds` là `int`; `where` là `tmuxSourceLocal` hoặc `{host}`; `time` là chuỗi đã định dạng.

---

## 8. Trợ năng

- **Nhãn dòng (A2 §8 + A3):** thêm `paneRemoteSuffix` (", trên devbox") sau tiêu đề khi pane focus là SSH/tmux từ xa; trạng thái `connecting`/`disconnected`/`failed` thêm nhãn §2.2 (", Mất kết nối tới devbox"). Dấu SSH/tmux trong `ExcludeSemantics` (nhãn đã nói).
- **Pane:** nhãn A3 "Pane {i} trên {n} — {title}" + `paneRemoteSuffix`; tab một pane: "Terminal {title}" + hậu tố.
- **Dải trạng thái:** `Semantics(container, liveRegion: true, label: chữ chính + chữ phụ)` — đọc **một lần** khi xuất hiện; đếm ngược **không** đọc từng giây (chữ phụ đổi không phát lại live region: chỉ cập nhật `value`). Nút là `button` với nhãn chữ.
- **Đọc lên (lịch sự, ≤ 1 lần / 3 s, như A4):** `sshAnnounceConnected` khi một pane do người dùng mở (không phải khôi phục) chuyển `connected`; `sshAnnounceDisconnected` khi pane **đang chọn** mất kết nối; `sshAnnounceReconnected` khi pane đang chọn kết nối lại.
- **Hộp kết nối:** thẻ là `Semantics(selected, button)` trong nhóm `tabBar`; danh sách gợi ý `Semantics(selected: true)` cho dòng chọn và ô có `hint` số kết quả ("3 gợi ý"); lỗi trường đọc ngay (A1 §3.4).
- **Tương phản:** §1.1 — chữ ≥ 6.0:1, thành phần không phải chữ ≥ 3:1.
- **Mục tiêu bấm:** nút dải 24 cao × ≥ 64 rộng; dòng gợi ý 28; dòng tmux 40 (≥ 24, WCAG 2.5.8).
- **Bàn phím:** mọi thao tác có phím hoặc mục menu: kết nối (⌘⇧K, menu `+`, tray), gắn tmux (menu, tray, hộp), kết nối lại (Enter, menu dòng, menu terminal, nút dải), mở cổng từ xa (menu dòng A2 "Mở cổng N…" dùng cùng đường chuyển tiếp) (WCAG 2.1.1).
- **Giảm chuyển động:** không có hoạt ảnh mới.

---

## 9. Wireframe

### 9.1 Sidebar với workspace SSH (macOS)

```
┌──────────────────────────────┐
│ ▾ Mặc định              2    │
│   ● zsh                      │
│     main · ~/w/shellx        │
│   ● vim — notes.md           │
│ ▾ ⌂ devbox              3    │
│ ▌ ● vim — main.go   ▥2 ⌂     │ ← chọn; pane focus là SSH
│     feat/x · ~/work/api · :8000
│   · zsh             ⌂        │ ← chấm nhỏ: đang kết nối
│   ● tmux: main      ▦        │ ← ▦ = view_quilt
│   ○ zsh             ⌂        │ ← vòng rỗng err: mất kết nối
└──────────────────────────────┘
```

### 9.2 Hai pane: cục bộ | SSH mất kết nối

```
┌─────────────────────────────┬┬───────────────────────────────────────────┐
│● zsh — ~/w/shellx       [×] ││● ⌂ zsh — ~/work/api                    [×] │
│ % git status                ││ $ make test                                │
│                             ││ [Mất kết nối tới devbox] — Enter để kết nối lại
│                             │├────────────────────────────────────────────┤
│                             ││⛓ Mất kết nối tới devbox · Thử lại sau 6 giây [Kết nối lại][Đóng pane]│
└─────────────────────────────┴┴───────────────────────────────────────────┘
```

### 9.3 Thẻ tmux, máy chủ chưa đăng nhập không mật khẩu

```
│ Phiên tmux trên   [ devbox                         ▾ ] │
│ ┌────────────────────────────────────────────────────┐ │
│ │  Không lấy được danh sách phiên trên devbox.       │ │
│ │  Kết nối SSH tới máy này một lần … rồi thử lại.    │ │
│ │                    Thử lại                         │ │
│ └────────────────────────────────────────────────────┘ │
```

---

## 10. Nhất quán với mobile

Không đổi app mobile (spec D36). Điện thoại thấy thư mục `devbox:/home/me/work/api` trong dòng phiên (chuỗi đã có chỗ). Hiển thị dấu SSH/tmux trên điện thoại cần protocol mới — follow-up sau A8.
