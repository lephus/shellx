# ShellX desktop A4 — UI addendum (badge, dòng thông báo, vòng sáng, bảng thông báo, thông báo hệ thống)

- **Ngày:** 2026-10-07 · **Phạm vi:** A4 của `docs/superpowers/specs/2026-10-07-desktop-notifications-a4-design.md` (ràng buộc; quyết định N1–N9, D1–D27). Tài liệu này **thêm** vào UI doc A1 `2026-10-06-shellx-desktop-ui.md` ("A1 §N") và UI addendum A2 `2026-10-07-shellx-desktop-ui-a2.md` ("A2 §N"); mọi token, kiểu chữ, trạng thái, quy tắc focus và copy của hai tài liệu đó vẫn giữ.
- **Nguyên tắc (giữ A1):** cửa sổ là terminal trước tiên. Mọi dấu hiệu thông báo là **dấu nhỏ hoặc lớp phủ**; **không có gì làm đổi cỡ terminal** (đổi cỡ = desktop lấy driver, A1 D6). Không có hoạt ảnh lặp/nhấp nháy (A1 §1.5).
- **Không có token màu mới.** Mọi màu lấy từ A1 §1.1. Tương phản đo theo công thức WCAG 2.x (đo lại cho A4, bảng §1.1).

---

## 1. Token dùng lại và kích thước mới

### 1.1 Màu (tất cả từ A1 §1.1)

| Dùng cho | Token | Trên nền | Tương phản |
|---|---|---|---|
| Nền badge số chưa đọc | `accent` `#5FD4E2` | `bgSidebar` / `rowHover` / `rowSelected` / `rowPressed` | 10.0 / 9.11 / 7.93 / 6.91 (thành phần ≥ 3) |
| Chữ trong badge | `onPrimary` `#04282D` | `accent` | **8.91** |
| Chữ dòng thông báo | `textSecondary` `#93A5A9` | `bgSidebar` / `rowHover` / `rowSelected` / `rowPressed` | 6.8 / 6.22 / 5.41 / 4.72 |
| Icon đầu dòng thông báo | `accent` | như trên | ≥ 6.91 |
| Icon đầu dòng thông báo, chấm chưa đọc trong bảng — **lệnh lỗi** (✗, mã ≠ 0) | `err` `#F07178` | `bgSidebar` / `rowHover` / `rowSelected` / `rowPressed` / `surface` | 6.12 / 5.57 / 4.85 / 4.22 / 5.79 (thành phần ≥ 3) |
| Bảng: vòng con trỏ bàn phím trên mục "Tab đã đóng" (không nhảy được) | `dim` `#6C8288` (chỉ cho vòng, không cho chữ) | `rowSelected` | 3.42 (thành phần ≥ 3) |
| Chấm tổng hợp trên tiêu đề nhóm, chấm chưa đọc trong bảng, chấm trên nút chuông | `accent` | `bgSidebar` / `rowHover` / `surface` / `rowSelected` | 10.0 / 9.11 / 9.47 / 7.93 |
| Vòng sáng (nét ngoài) | `accent` 100 % | `bgTerminal` `#0B1215` | **10.8** |
| Vòng sáng (nét trong, "glow") | `accent` 40 % (`#665FD4E2`, trùng màu vùng chọn của terminal) | `bgTerminal` | trang trí; nét ngoài đã đạt ≥ 3 |
| Bảng: nền | `surface` `#172023`, viền 1 px `border`, `e1` | — | — |
| Bảng: tiêu đề "Thông báo" | `textPrimary` | `surface` | 12.38 |
| Bảng: dòng 1 (tab · workspace), thời gian | `textSecondary` | `surface` / `rowHover` / `rowSelected` | 6.47 / 6.22 / 5.41 |
| Bảng: nội dung (chưa đọc) | `textPrimary` | `surface` / `rowSelected` | 12.38 / 10.36 |
| Bảng: nội dung (đã đọc) | `textSecondary` | `surface` / `rowSelected` | 6.47 / 5.41 |
| Bảng: nút "Đánh dấu tất cả đã đọc" | `accent` | `surface` / `rowHover` | 9.47 / 9.11 |

`dim` (4.32) **không** dùng cho chữ ở bất kỳ chỗ nào trong A4.

### 1.2 Kích thước mới (thêm vào `ShellxSizes`)

| Tên | Giá trị | Ghi chú |
|---|---|---|
| `badgeHeight` | 16 | badge số chưa đọc, `rPill` |
| `badgeMinWidth` | 16 | một chữ số → hình tròn |
| `badgePadH` | 4 | đệm ngang (2 chữ số trở lên) |
| `badgeGap` | 4 | giữa tiêu đề và badge, giữa badge và dấu 📱 |
| `notificationLine` | 14 | `caption` 11/14 |
| `notificationGap` | 2 | giữa dòng tiêu đề và dòng thông báo, giữa dòng thông báo và dòng ngữ cảnh |
| `notificationIcon` | 11 | icon đầu dòng thông báo |
| `notificationIconGap` | 4 | |
| `rowWithNotification` | 46 | 6 + 18 + 2 + 14 + 6 (không có ngữ cảnh) |
| `rowWithNotificationAndContext` | 62 | 6 + 18 + 2 + 14 + 2 + 14 + 6 |
| `ringWidth` | 2 | nét ngoài vòng sáng |
| `ringGlowWidth` | 1 | nét trong, `accent` 40 % |
| `aggregateDot` | 6 | chấm tổng hợp trên tiêu đề nhóm |
| `panelWidth` | 360 | bảng thông báo |
| `panelMaxHeight` | 480 | thực tế `min(480, cao cửa sổ − 64)` |
| `panelOffsetY` | 4 | dưới đáy dải đầu sidebar |
| `panelHeader` | 36 | tiêu đề bảng |
| `panelItem` | 52 | 8 + 16 (dòng 1, `small`) + 2 + 18 (dòng 2, `body`) + 8 |
| `panelUnreadSlot` | 16 | ô chấm chưa đọc bên trái (chấm 6) |
| `panelEmptyIcon` | 24 | |
| `headerBellGap` | 4 | giữa nút chuông và `+` ở dải đầu sidebar |
| `bellDot` | 6 | chấm trên nút chuông, tâm tại (19, 7) trong ô nhìn 24 |

Thang khoảng cách, bo góc, độ nổi, chuyển động: A1 §1.2–§1.5 (không thêm token).

### 1.3 Cỡ chữ lớn

Chiều cao dòng tab = `6 + scale(18) + [2 + scale(14)]` cho dòng thông báo + `[2 + scale(14)]` cho dòng ngữ cảnh `+ 6`, tối thiểu theo bảng sau (thay công thức A2 §1.3 cho dòng tab):

| Có dòng thông báo | Có dòng ngữ cảnh | Tối thiểu | Công thức |
|---|---|---|---|
| — | — | 30 | `max(30, scale(18) + 12)` (A1) |
| — | ✓ | 46 | `max(46, scale(18) + scale(14) + 14)` (A2) |
| ✓ | — | 46 | `max(46, scale(18) + scale(14) + 14)` |
| ✓ | ✓ | 62 | `max(62, scale(18) + 2·scale(14) + 16)` |

Badge: cao `max(16, scale(14) + 2)`; chữ theo `textScaler`. Mục bảng: `max(52, scale(16) + scale(18) + 18)`.

---

## 2. Dòng tab có thông báo

### 2.1 Giải phẫu

```
|6|8 |—8—| title (body/bodyStrong, flex, ellipsis) |4|( 3 )|4|📱|4|👁|2|×|8|   ← dòng tiêu đề 18
                                                       badge                            2
|6|— 32 —|🔔|4| Build xong (caption, textSecondary, ellipsis)       |8|               ← dòng thông báo 14
                                                                                        2
|6|— 32 —| main · ~/work/shellx · :3000                              |8|               ← dòng ngữ cảnh A2 14
```

- **Badge** nằm **ngay sau tiêu đề** (tiêu đề co lại trước, badge không bao giờ bị cắt), cách 4; sau badge 4 rồi các dấu A1. Không có chưa đọc → không có badge và **không giữ chỗ** (tiêu đề giãn ra). (Sửa A1 §2.2: chỗ badge không còn ở sau ×.)
- Badge: cao 16, rộng tối thiểu 16, đệm ngang 4, `rPill`, nền `accent`, chữ `caption` **w600** `onPrimary`, canh giữa. Nội dung `1`…`99`, `99+`. Chữ số dạng tabular (`FontFeature.tabularFigures()`).
- **Dòng thông báo**: lề trái 32 (`contextInset`, thẳng tiêu đề), icon `Icons.notifications_none` 11 `accent` (**`err`** khi thông báo mới nhất là lệnh lỗi ✗, để phân biệt với tin nhắn thường mà không chỉ dựa vào chữ), 4, chữ `caption` `textSecondary` một dòng, cắt cuối. Chữ = D9 (spec). Dòng chuông: "Chuông" (bell không có chữ khác).
- Chữ được **dựng lúc vẽ** theo ngôn ngữ đang hiện (lưu dữ liệu thông báo, không lưu chuỗi), nên "Chuông"/"Bell", "mã 1"/"exit 1" luôn theo ngôn ngữ hiện tại.
- Thứ tự: tiêu đề → thông báo → ngữ cảnh A2. Dòng thông báo **biến mất khi đọc**; dòng cao/thấp tức thì (không hoạt ảnh, A1 §1.5 "chèn dòng tức thì").
- Tooltip trên dòng thông báo (chờ 500 ms, bên phải sidebar như A1 §3.1, max-width 360): chữ đầy đủ (không cắt, tối đa 200 ký tự), chỉ khi bị cắt.
- Thanh chọn 3×18 `accent` (A1) canh giữa **cả dòng** (46/62).

### 2.2 Trạng thái

Giữ A1 §3.1 và A2 §2.5. Thêm:

| Trạng thái | Nhìn |
|---|---|
| Có chưa đọc, không chọn | badge + dòng thông báo; nền theo A1 (thường/hover/nhấn) |
| Có chưa đọc, đang chọn, chưa đủ 1 s | như trên trên nền `rowSelected`; badge tương phản 7.93 |
| Vừa đọc | badge và dòng thông báo biến mất tức thì |
| Tab đã thoát (mã ≠ 0) có chưa đọc | badge + dòng thông báo vẫn hiện (chữ `textSecondary` như tiêu đề) |
| Đang đổi tên | badge ẩn (không giữ chỗ), dòng thông báo vẫn hiện |

---

## 3. Tiêu đề workspace — chấm tổng hợp

```
|6|4|▸|4| Backend (small 600)                 |4|●|4|3|  (ô số 24, số canh giữa) |6|
                                                6
```

- Chỉ khi nhóm **thu gọn** và có ít nhất một tab chưa đọc (D22). Chấm 6 `accent` tròn, canh giữa dọc, mép phải chấm cách **mép trái của chữ số** 4 (đo theo chữ số thật, không theo ô 24 nó canh giữa trong đó). Khi hiện, tên nhóm nhường 10 (6 + 4); không hiện → không chiếm chỗ.
- Kết hợp với "thu gọn + chứa tab đang chọn" (A2 §3.2) bình thường: thanh 3×12 bên trái và chấm bên phải cùng hiện.
- Tooltip trên tiêu đề (đã có của A2 nếu có) không đổi; ý nghĩa ở Semantics (§8).

---

## 4. Vòng sáng quanh terminal

```
┌──────────────────────────────────────────────────────┐ ← vùng terminal (dưới pane header / dải đăng nhập)
│┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓│   nét ngoài 2 px accent, sát mép vùng
│┃┌──────────────────────────────────────────────────┐┃│   nét trong 1 px accent 40 %
│┃│ richard@mbp shellx % claude                      │┃│   chữ terminal bắt đầu ở padding A1 (10/6)
│┃│ ...                                              │┃│   → vòng (3 px) không chạm chữ
```

- Vẽ bằng `IgnorePointer` + `CustomPaint`/`DecoratedBox` **đè lên** `Positioned.fill` của vùng terminal (cùng `Stack` với pill driver, A1 §2.3); không thêm padding, không đổi constraints của `TerminalView` → không resize PTY.
- Góc vuông (vùng terminal không bo). Không có bóng ra ngoài.
- Thứ tự lớp: terminal < vòng < pill driver < toast (pill và toast nằm trên vòng).
- **Chuyển động:** hiện `AnimatedOpacity` 0→1 `base` 150 ms `easeOutCubic`; tắt 1→0 `exit` 120 ms `easeIn`. Không lặp, không nhấp nháy. Giảm chuyển động (`ShellxMotion.of` → `Duration.zero`) → **vòng tĩnh**, hiện/tắt tức thì.
- Không có tab nào (trạng thái trống A1 §2.7) → không vòng.

---

## 5. Nút chuông và bảng thông báo

### 5.1 Nút chuông ở dải đầu sidebar

```
macOS:  |● ● ●|——— 80 ———|        spacer        |[🔔]|4|[+]|8|
Windows:|                         spacer        |[🔔]|4|[+]|8|
```

- `ShellxIconButton` như `+` (A1 §3.2): hit 28, nhìn 24, `r6`, icon 16 `textSecondary`; hover `rowHover` + icon `textPrimary`; nhấn `rowPressed`; vòng focus.
- Icon: `Icons.notifications_none` khi tổng = 0; `Icons.notifications` (đặc) + chấm 6 `accent` tại góc trên phải (tâm (19, 7) trong ô 24) khi tổng > 0. Đang mở bảng → nền `rowSelected` (trạng thái "bật").
- Tooltip `notificationsPanelTooltip`: "Thông báo  ⌘⇧I" / "Notifications  Ctrl+Shift+I".
- Thứ tự Tab trong vùng sidebar (A1 §3.6): chuông → `+` → danh sách.

### 5.2 Bảng (popover)

```
 x=6 (trong cửa sổ, trùng mép thanh chọn 3 px của dòng → thanh không lộ ra bên trái bảng), y = đáy dải đầu sidebar + 4
╭──────────────────────────────────────── 360 ───────────────────────────────────╮
│ Thông báo                                        Đánh dấu tất cả đã đọc        │ 36
│────────────────────────────────────────────────────────────────────────────────│ 1 px line
│ ●  claude · Backend                                              vừa xong      │
│    Claude cần bạn trả lời                                                      │ 52
│ ●  api · Backend                                                   2 phút      │
│    ✗ npm test · mã 1 · 45 giây                                                 │
│    zsh 1 · Mặc định                                                   12:04     │
│    Chuông ×3                                                                    │
│    Tab đã đóng · build                                                1 giờ    │
│    ✓ cargo build · 3 phút 12 giây                                              │
╰────────────────────────────────────────────────────────────────────────────────╯
```

- Hộp: `surface`, viền 1 px `border`, `r8`, `e1`, padding 4. Cao theo nội dung, tối đa `min(480, cao cửa sổ − 64)`; danh sách cuộn (thanh cuộn phủ A1 §2.2), **thanh cuộn luôn hiện khi danh sách dài hơn bảng** (không chỉ khi rê chuột), để mục bị khuất không trông như không tồn tại.
- **Tiêu đề** 36: "Thông báo" `small` w600 `textPrimary`, lề trái 8. Phải: nút chữ "Đánh dấu tất cả đã đọc" (`small` w600 `accent`, cao 28, đệm 0/8, hover `rowHover` `r6`), **mờ 38 %** khi tổng chưa đọc = 0. Dưới tiêu đề: vạch 1 px `line`.
- **Mục** 52, `r6`, đệm 8/8:
  - Ô trái 16: chấm 6 `accent` nếu mục chưa đọc (`err` nếu là lệnh lỗi ✗); trống nếu đã đọc.
  - Dòng 1 (16): `small` `textSecondary`: "`<tab>` · `<workspace>`" (workspace chỉ khi sidebar có tiêu đề nhóm, A2 D10), cắt cuối; phải: thời gian tương đối `caption` `textSecondary`, cách 8.
  - Dòng 2 (18): `body`, `textPrimary` (chưa đọc) / `textSecondary` (đã đọc), một dòng, cắt cuối. Chữ = D9; chuông gộp "Chuông ×N".
  - Tab đã đóng: dòng 1 "Tab đã đóng · `<tên cuối>`"; không nhảy được (Enter/bấm không làm gì, con trỏ mặc định, không hover).
- **Trạng thái mục:** hover `rowHover`; con trỏ bàn phím: `rowSelected` + vòng focus 2 px `accent` bên trong `r6` (chỉ khi focus bàn phím, A1 §3); trên mục "Tab đã đóng" vòng là `dim` (Enter không làm gì); nhấn `rowPressed`.
- **Thời gian tương đối:** < 60 s "vừa xong" / "now"; < 60 phút "{n} phút" / "{n} min"; < 24 giờ "{n} giờ" / "{n} h"; từ 24 giờ trở lên và thuộc ngày hôm qua "Hôm qua HH:mm" / "Yesterday HH:mm"; cũ hơn "dd/MM HH:mm" (vi, ví dụ "05/10 22:05") / "MMM d, HH:mm" (en, ví dụ "Oct 5, 22:05"); giờ 24 h. Cập nhật mỗi 30 s khi bảng mở.
- **Trống:** canh giữa, đệm 24: `Icons.notifications_none` 24 `textSecondary` → 8 → "Chưa có thông báo nào" `body` `textPrimary` → 4 → gợi ý `caption` `textSecondary` (canh giữa, tối đa 2 dòng) "Chương trình trong tab gửi thông báo bằng OSC 9, 99, 777 hoặc lệnh shellx notify." Nút "Đánh dấu tất cả…" mờ.
- **Chân** (chỉ khi có mục): dòng 24, `caption` `textSecondary`, lề trái 8: "Chưa đọc tiếp theo  ⌘⇧U" / "Next unread  Ctrl+Shift+U".
- **Mở:** fade + `translateY −4→0` `base` 150 ms; đóng: fade `exit` 120 ms; giảm chuyển động → tức thì.

### 5.3 Bàn phím và focus

| Phím | Hành vi |
|---|---|
| ⌘⇧I / Ctrl+Shift+I | Mở (focus vào mục **đầu tiên chưa đọc**, không có thì mục đầu); đang mở → đóng |
| ↑ / ↓ | Con trỏ lên/xuống (không vòng), cuộn theo |
| Home / End | Mục đầu / cuối |
| Enter / Space | Nhảy tới tab của mục (chọn tab, mở rộng workspace, đánh dấu đọc ngay, focus terminal), đóng bảng. Tab đã đóng: không làm gì, trình đọc màn hình đọc "Tab đã đóng" |
| Tab / Shift+Tab | Giữa danh sách và nút "Đánh dấu tất cả đã đọc" (bẫy focus trong bảng) |
| Esc, ⌘⇧I, bấm ra ngoài | Đóng; bàn phím về chỗ đã có trước khi mở (terminal hoặc sidebar) |
| ⌘⇧U / Ctrl+Shift+U | Nhảy tới chưa đọc tiếp theo (D13); bảng đang mở thì đóng trước |

Phím tắt cửa sổ khác (⌘T, ⌘W, ⌘1–9) vẫn chạy khi bảng mở (đóng bảng trước).

---

## 6. Thông báo hệ thống (copy)

| Trường hợp | Tiêu đề | Nội dung |
|---|---|---|
| OSC 9 / `shellx notify` | `<tên tab>` | `<chữ>` |
| OSC 777 / OSC 99 có tiêu đề chương trình | `<tên tab>` | `<tiêu đề chương trình>: <chữ>` |
| Lệnh chạy lâu | `<tên tab>` | `✓ npm test · 3 phút 12 giây` / `✗ npm test · mã 1 · 45 giây` (câu push, ngôn ngữ app) |
| Chuông | `<tên tab>` | `attentionBellBody` "Chuông trong tab này" / "Bell in this tab" |
| Gộp (D15) | `<tên tab>` | `systemNotifyCoalesced` "{count} thông báo mới · {text}" / "{count} new notifications · {text}" |

- `<tên tab>` = `TerminalTab.label` (tên tuỳ chỉnh A2 hoặc tự động); khi sidebar có tiêu đề nhóm: "`<tên tab>` · `<workspace>`".
- Không có tiền tố "ShellX" (hệ điều hành đã hiện tên/icon app). Âm thanh: âm mặc định của hệ thống (người dùng tắt trong Cài đặt hệ thống).
- Cắt: tiêu đề 80 ký tự, nội dung 200 ký tự (`…`).

---

## 7. Cài đặt (tray, D20)

```
Thông báo                               ▸ ┌──────────────────────────────────────────┐
                                          │ ✓ Thông báo trên máy tính                │
                                          │ ✓ Chỉ khi cửa sổ không ở phía trước      │  (mờ khi mục trên tắt)
                                          │ ──────────────────────────────────────── │
                                          │ Thông báo khi lệnh chạy lâu xong       ▸ │ → Tắt / 10 giây / 30 giây ✓ / 1 phút / 5 phút
                                          └──────────────────────────────────────────┘
```

Vị trí: menu đã đăng nhập — chỗ submenu ngưỡng cũ (sau "Chia sẻ terminal"); menu chưa đăng nhập — sau "Mở cửa sổ terminal" và vạch, trước dòng trạng thái.

---

## 8. Trợ năng

- **Dòng tab:** nhãn A2 §8 thêm, ngay sau trạng thái: `attentionRowSemantics` "{count} thông báo chưa đọc, mới nhất: {text}" (chữ đầy đủ, không cắt). Ví dụ vi: "api, đang chờ lệnh, 2 thông báo chưa đọc, mới nhất: ✗ npm test · mã 1 · 45 giây, nhánh dev, tab 2 trên 3 trong Backend". Badge, icon, dòng thông báo: `ExcludeSemantics`.
- **Custom actions của dòng** theo đúng thứ tự menu dòng (§10.4): "Đánh dấu đã đọc" (chỉ khi tab có chưa đọc), "Đánh dấu tất cả đã đọc" (chỉ khi tổng > 0), đổi tên, chuyển workspace, lên/xuống, (cổng), "Đóng tab" cuối. Trình đọc màn hình xếp action theo mã định danh cấp lần đầu, nên sidebar đăng ký các nhãn này theo thứ tự menu trước khi dựng dòng; action cổng (tạo lúc chạy) đứng sau "Đóng tab".
- **Tiêu đề nhóm thu gọn có chưa đọc:** nhãn A2 + ", " + `workspaceHasUnread` "có thông báo chưa đọc".
- **Terminal:** khi có vòng, nhãn pane `terminalPaneUnreadLabel` "Terminal {title}, có thông báo chưa đọc".
- **Thông báo đến (D24):** cửa sổ focus, tab không chọn → `SemanticsService.announce(attentionAnnounce, assertiveness: polite)` "Thông báo mới từ {tab}: {text}", tối đa một lần/3 s/tab.
- **Nút chuông:** `Semantics(button, label: notificationsPanelTitle + (tổng > 0 ? ", " + attentionUnreadCount : ""), toggled: đang mở)`.
- **Bảng:** `Semantics(scopesRoute: true, namesRoute: true, label: "Thông báo", explicitChildNodes: true)`; mỗi mục `Semantics(button: !closed, selected: con trỏ, label: …)`; nhãn = các phần nối bằng ", ": tab · [workspace] · chữ · thời gian · [`notificationsItemUnread`] · [`notificationsTabClosed`], ví dụ "api, Backend, ✗ npm test · mã 1 · 45 giây, 2 phút, chưa đọc". Mở bảng: announce "Thông báo, {n} mục".
- **⌘⇧U không còn chưa đọc:** announce + toast trung tính `noUnreadNotifications` "Không còn thông báo chưa đọc".
- **Tương phản:** bảng §1.1 — mọi chữ ≥ 4.72:1, thành phần không phải chữ ≥ 3:1.
- **Giảm chuyển động:** vòng tĩnh; bảng mở/đóng tức thì.
- **Mục tiêu bấm:** nút chuông 28×28; mục bảng 52 cao toàn bề rộng; nút "Đánh dấu tất cả" 28 cao.

---

## 9. Copy (vi + en, khoá ARB)

Giọng văn A1 §5. "tab", "workspace", "terminal" giữ tiếng Anh.

| Khoá | vi | en |
|---|---|---|
| `attentionBell` | Chuông | Bell |
| `attentionBellRepeat` | Chuông ×{count} | Bell ×{count} |
| `attentionBellBody` | Chuông trong tab này | Bell in this tab |
| `attentionUnreadCount` | {count} thông báo chưa đọc | {count, plural, =1{1 unread notification} other{{count} unread notifications}} |
| `attentionRowSemantics` | {count} thông báo chưa đọc, mới nhất: {text} | {count, plural, =1{1 unread notification} other{{count} unread notifications}}, latest: {text} |
| `attentionMarkRead` | Đánh dấu đã đọc | Mark as read |
| `attentionMarkAllRead` | Đánh dấu tất cả đã đọc | Mark all as read |
| `attentionAnnounce` | Thông báo mới từ {tab}: {text} | New notification from {tab}: {text} |
| `workspaceHasUnread` | có thông báo chưa đọc | has unread notifications |
| `terminalPaneUnreadLabel` | Terminal {title}, có thông báo chưa đọc | Terminal {title}, has unread notifications |
| `notificationsPanelTitle` | Thông báo | Notifications |
| `notificationsPanelTooltip` | Thông báo  {shortcut} | Notifications  {shortcut} |
| `notificationsPanelEmptyTitle` | Chưa có thông báo nào | No notifications yet |
| `notificationsPanelEmptyBody` | Chương trình trong tab gửi thông báo bằng OSC 9, 99, 777 hoặc lệnh shellx notify. | Programs in your tabs send notifications with OSC 9, 99, 777 or the shellx notify command. |
| `notificationsPanelNextHint` | Chưa đọc tiếp theo  {shortcut} | Next unread  {shortcut} |
| `notificationsPanelOpened` | Thông báo, {count} mục | {count, plural, =1{Notifications, 1 item} other{Notifications, {count} items}} |
| `notificationsTabClosed` | Tab đã đóng | Tab closed |
| `notificationsTimeNow` | vừa xong | now |
| `notificationsTimeMinutes` | {count} phút | {count} min |
| `notificationsTimeHours` | {count} giờ | {count} h |
| `notificationsTimeYesterday` | Hôm qua {time} | Yesterday {time} |
| `notificationsTimeDate` | {dayPadded}/{month} {time} | {month} {day}, {time} |
| `notificationsMonthShort` | `m1`…`m12` → 01…12 | `m1`…`m12` → Jan…Dec |
| `notificationsItemUnread` | chưa đọc | unread |
| `noUnreadNotifications` | Không còn thông báo chưa đọc | No unread notifications |
| `systemNotifyCoalesced` | {count} thông báo mới · {text} | {count} new notifications · {text} |
| `trayNotifications` | Thông báo | Notifications |
| `trayDesktopNotifications` | Thông báo trên máy tính | Notifications on this computer |
| `trayDesktopNotificationsUnfocused` | Chỉ khi cửa sổ không ở phía trước | Only when the window isn't in front |

- `count` là `int` trong metadata `@`; tiếng Việt không chia số nhiều.
- `time` là `HH:mm`; `day` không đệm, `dayPadded` hai chữ số; `month` của `notificationsTimeDate` là kết quả `notificationsMonthShort` (select theo `m<tháng>`).
- Chuỗi có sẵn dùng lại: `trayNotifyThreshold`, `trayNotifyOff`, `trayNotifySeconds`, `trayNotifyMinutes` (push §7), `sidebarPosition*`, `workspaceHeaderSemantics` (A2).
- Mô tả overlay taskbar Windows dùng `attentionUnreadCount`.

---

## 10. Wireframe

### 10.1 Ba tab, tab "api" có 2 chưa đọc, tab đang chọn "claude" có chưa đọc và cửa sổ không focus (macOS)

```
┌────────────────────────┬──────────────────────────────────────────────────┐
│ ● ● ●          [🔔•][+]│                     claude                       │
│ ▾ Backend            2 │┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓│
│ ▌◉ claude (1)      ×   │┃ richard@mbp shellx % claude                     ┃│
│    🔔 Claude cần bạn trả lời                                              ┃│
│    main · ~/work/shellx│┃ ╭─────────────────────────────────╮             ┃│
│  ● api (2)   📱        │┃ │ ✻ Do you want to proceed?       │             ┃│
│    🔔 ✗ npm test · mã 1 · 45 giây                                         ┃│
│    dev · ~/w/api · :8080                                                  ┃│
│ ▸ Frontend         • 3 │┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛│
└────────────────────────┴──────────────────────────────────────────────────┘
 (1)/(2) = badge accent, chữ onPrimary · 🔔 = Icons.notifications_none 11 accent
 dòng 2 caption textSecondary · • = chấm tổng hợp (Frontend thu gọn có chưa đọc)
 ┏━┓ = vòng sáng 2 px accent (+1 px 40 % bên trong), chỉ trong vùng terminal
 (vẽ tràn ở đây chỉ để minh hoạ; thực tế mọi dòng cắt vừa 168 px)
```

### 10.2 Bảng thông báo mở, con trỏ ở mục 2

```
┌────────────────────────┬──────────────────────────────────────────────────┐
│ ● ● ●          [🔔•][+]│                     claude                       │
│ ╭───────────────────────────────────────────╮                             │
│ │ Thông báo         Đánh dấu tất cả đã đọc  │                             │
│ │───────────────────────────────────────────│                             │
│ │ ● claude · Backend              vừa xong  │                             │
│ │   Claude cần bạn trả lời                  │                             │
│ │┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓│  ← con trỏ bàn phím          │
│ │┃● api · Backend                   2 phút ┃│                             │
│ │┃  ✗ npm test · mã 1 · 45 giây            ┃│                             │
│ │┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛│                             │
│ │   zsh 1 · Mặc định         Hôm qua 12:04  │                             │
│ │   Chuông ×3                               │                             │
│ │ Chưa đọc tiếp theo  ⌘⇧U                   │                             │
│ ╰───────────────────────────────────────────╯                             │
└────────────────────────┴──────────────────────────────────────────────────┘
```

### 10.3 Bảng trống

```
 ╭───────────────────────────────────────────╮
 │ Thông báo         Đánh dấu tất cả đã đọc  │  ← nút mờ 38 %
 │───────────────────────────────────────────│
 │                    🔕                     │
 │            Chưa có thông báo nào          │
 │   Chương trình trong tab gửi thông báo    │
 │   bằng OSC 9, 99, 777 hoặc lệnh shellx    │
 │   notify.                                 │
 ╰───────────────────────────────────────────╯
```

### 10.4 Menu dòng tab (A2 §5.1 + A4)

```
 ╭──────────────────────────────────────────╮
 │ Đánh dấu đã đọc                          │   ← mờ khi tab không có chưa đọc
 │ Đánh dấu tất cả đã đọc                   │   ← mờ khi tổng = 0
 │──────────────────────────────────────────│
 │ Đổi tên tab                          F2  │
 │ Dùng tên tự động                         │
 │──────────────────────────────────────────│
 │ Chuyển tới workspace…                    │
 │ ...                                      │
 ╰──────────────────────────────────────────╯
```

### 10.5 Thông báo hệ thống

```
 macOS (Notification Center)                    Windows (toast)
 ╭──────────────────────────────────────╮       ╭──────────────────────────────────────╮
 │ [ShellX]  api · Backend         bây giờ│       │ [ShellX] ShellX                      │
 │ ✗ npm test · mã 1 · 45 giây          │       │ api · Backend                        │
 ╰──────────────────────────────────────╯       │ ✗ npm test · mã 1 · 45 giây          │
                                                ╰──────────────────────────────────────╯
 Dock: [icon ShellX ③]                          Taskbar: [icon ShellX •] (chấm accent, nháy cam khi mới)
```

---

## 11. Nhất quán với mobile (follow-up, không làm trong A4)

1. Khi điện thoại cần số chưa đọc: chuyển bộ đếm vào agent/daemon (spec N2) và dùng **cùng** badge (`accent`/`onPrimary`, `99+`) trên thanh tab mobile.
2. Vòng sáng mobile: viền `--t-cyan` 2 px quanh terminal khi phiên đang xem có thông báo (cùng quy tắc tĩnh khi giảm chuyển động).
3. Câu chữ "Chuông", "N thông báo mới · …" dùng chung khi có gói `packages/shellx_design` (A1 §7 follow-up 1).
