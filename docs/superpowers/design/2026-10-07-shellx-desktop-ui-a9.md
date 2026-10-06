# ShellX desktop A9 — UI addendum (cấu hình, bảng lệnh, vấn đề cấu hình, trình sửa phím tắt, chuỗi phím)

- **Ngày:** 2026-10-07 · **Phạm vi:** A9 của `docs/superpowers/specs/2026-10-07-desktop-config-a9-design.md` (ràng buộc; D1–D46). Tài liệu này **thêm** vào UI doc A1 `2026-10-06-shellx-desktop-ui.md` ("A1 §N") và các addendum A2–A6 ("A3 §N"…); mọi token, kiểu chữ, trạng thái, quy tắc focus và copy của chúng vẫn giữ.
- **Nguyên tắc:** cửa sổ là terminal trước tiên. Không có file cấu hình → **không thấy gì mới** ngoài ba phím tắt mới (⌘, ⌘⇧, ⌘⇧P) và submenu khay "Cấu hình". Mọi bề mặt mới là **lớp phủ tạm** (như bảng thông báo A4 §5), không có trang Cài đặt.
- **Không có token màu mới.** Màu từ A1 §1.1; riêng vùng terminal lấy nền chủ đề người dùng (spec D15). Tương phản đo theo WCAG 2.x.

---

## 1. Token dùng lại và kích thước mới

### 1.1 Màu

| Dùng cho | Token | Trên nền | Tương phản |
|---|---|---|---|
| Hộp bảng lệnh / bảng vấn đề / phím tắt | `surface` + viền `border` + `e1` | `scrim` không dùng (lớp phủ không chặn, như A4 §5.2) | — |
| Ô tìm | `surfaceInset`, viền `borderInput`; focus viền `accent` | `surface` | viền 3.3 / 7.9 (≥ 3) |
| Mục được chọn (con trỏ bàn phím) | `rowSelected` + vòng 2 px `accent` (chỉ khi focus bàn phím) | `surface` | vòng 7.93 |
| Tên mục | `textPrimary` | `surface` / `rowSelected` | 11.9 / 11.5 |
| Mô tả, loại mục, chữ trong keycap | `textSecondary` | `surface` / `rowSelected` | 6.5 / 6.0 |
| Keycap (ô phím) | nền `surfaceInset`, viền 1 px `border`, chữ `textPrimary` | `surface` | chữ 13.6 |
| Chữ khớp trong kết quả | `accent` w600 | `surface` / `rowSelected` | 8.6 / 7.93 |
| Mức lỗi (biểu tượng + nhãn) | `err` | `surface` | 5.4 |
| Mức cảnh báo | `warn` | `surface` | 9.6 |
| Mức ghi chú | `textSecondary` | `surface` | 6.5 |
| Toast vấn đề có lỗi | toast lỗi A1 §2.8 (`noticeBg`/`noticeText`/`noticeBorder`) | — | A1 |
| Toast chỉ cảnh báo, "Đã tải lại cấu hình", "Đang dùng … Ghostty" | toast trung tính A1 §2.8 | — | A1 |
| Nút "Xem" trong toast | chữ `accent` w600 (trung tính) / `noticeText` gạch chân (lỗi) | nền toast | 7.9 / 11.4 |
| Chỉ báo chuỗi phím | nền `surface`, viền `accent` 1 px, chữ `textPrimary` | nền terminal bất kỳ | viền 7.9 trên `bgTerminal`; trên chủ đề sáng viền vẫn ≥ 3 vì nằm trên `surface` |
| Viền focus pane (A3 D16) trên chủ đề | `accent` nếu ≥ 3:1 với nền chủ đề, không thì `bgTerminal` | nền chủ đề | ≥ 3 (spec D15) |
| Vùng terminal (gồm lề, nền phía sau pane) | `background` của chủ đề | — | lựa chọn của người dùng; cảnh báo `lowContrast` < 4,5 |

### 1.2 Kích thước mới (thêm vào `ShellxSizes`)

| Tên | Giá trị | Ghi chú |
|---|---|---|
| `paletteWidth` | 560 | bảng lệnh; `min(560, rộng cửa sổ − 48)` |
| `paletteTop` | 56 | cách mép trên vùng terminal (macOS: dưới dải 28 px) |
| `paletteMaxHeight` | 420 | `min(420, cao cửa sổ − 96)`; danh sách cuộn |
| `paletteRow` | 36 | mục một dòng; mục có mô tả 48 |
| `paletteField` | 40 | ô tìm (lớn hơn `input` 36 để dễ thấy) |
| `problemsWidth` | 600 | bảng vấn đề; `min(600, rộng − 48)` |
| `problemsMaxHeight` | 480 | danh sách cuộn |
| `problemRow` | 52 | vị trí + thông điệp (2 dòng) |
| `shortcutsWidth` | 720 | trình sửa phím; `min(720, rộng − 48)` |
| `shortcutsHeight` | 600 | `min(600, cao − 64)` |
| `shortcutsRow` | 40 | một action |
| `keycapHeight` | 20 | ô phím; đệm ngang 6, `r4`, chữ `small` |
| `keycapGap` | 4 | giữa các ô phím |
| `sequenceIndicatorHeight` | 28 | chỉ báo chuỗi phím, `rPill` |

### 1.3 Cỡ chữ lớn

Mục bảng lệnh cao `max(36, scale(18) + 18)`; ô phím cao `max(20, scale(16) + 4)`; bảng vấn đề dòng 2 xuống dòng tự do (không cắt). Mọi chữ theo `textScaler`.

---

## 2. Bảng lệnh (⌘⇧P / Ctrl+Shift+P, spec D33)

### 2.1 Giải phẫu

```
                     vùng terminal (chủ đề người dùng)
            ╭───────────────────────── 560 ─────────────────────────╮  y = 56
            │ ┌─────────────────────────────────────────────────┐   │
            │ │ 🔍 chia xu│                                      │   │ 40  ô tìm, focus
            │ └─────────────────────────────────────────────────┘   │
            │───────────────────────────────────────────────────────│ 1 px line
            │▌Chia xuống dưới                        [⌘][⇧][D]      │ 36  mục chọn (rowSelected)
            │ Chia sang phải                            [⌘][D]      │
            │ Lint                       Lệnh của bạn               │ 48  mục có mô tả
            │   npm run lint                                        │
            │ Tải lại cấu hình               Cấu hình  [⌘][⇧][,]    │
            ╰───────────────────────────────────────────────────────╯
```

- Hộp: `surface`, viền 1 px `border`, `r8`, `e1`, đệm 6. Canh giữa ngang **trong vùng terminal** (không trong cả cửa sổ: sidebar vẫn nhìn thấy). Không có lớp mờ; bấm ra ngoài → đóng.
- **Ô tìm** 40: `surfaceInset`, `r6`, biểu tượng `Icons.search` 16 `textSecondary` lề trái 10, chữ `body` `textPrimary`, gợi ý `paletteSearchHint` `textPlaceholder`. Không có nút xoá (Esc khi ô có chữ → xoá chữ; ô trống → đóng).
- **Mục**: đệm 0/10, `r6`. Trái: tên (`body`, chữ khớp `accent` w600). Phải (cách 8): nhãn loại `caption` `textSecondary` ("Lệnh của bạn" / "Đoạn chữ" / "Cấu hình"; action ShellX không có nhãn loại), rồi keycap của trigger đầu tiên (spec D29; chuỗi: hai cụm keycap cách 6, ví dụ `[⌃][A] [C]`). Mục `command`/`snippet`: dòng 2 `small` `textSecondary` = chữ lệnh, một dòng, cắt cuối, ký tự xuống dòng hiện `⏎`.
- **Thứ tự khi ô trống**: dùng gần đây (≤ 8) → mục cấu hình có vấn đề ("Xem vấn đề cấu hình" khi có) → action ShellX theo nhóm của §4 → lệnh của bạn → đoạn chữ.
- **Không có kết quả**: dòng 36 canh giữa `body` `textSecondary` "Không có lệnh nào khớp".
- Mở: tức thì (không hoạt ảnh) — bảng lệnh là công cụ bàn phím, độ trễ cảm nhận phải bằng 0.

### 2.2 Bàn phím và focus

| Phím | Hành vi |
|---|---|
| ⌘⇧P / Ctrl+Shift+P | Mở (focus ô tìm, chọn mục đầu); đang mở → đóng |
| Gõ | Lọc ngay (spec D33: không dấu, không hoa thường; tiền tố > đầu từ > dãy con) |
| ↑ / ↓, Ctrl+P / Ctrl+N | Con trỏ lên/xuống, **vòng** (danh sách ngắn, như VS Code); cuộn theo |
| Page Up / Page Down | 8 mục |
| Enter | Chạy mục, đóng bảng, bàn phím về pane (hoặc theo action: "Phím tắt…" mở hộp §4) |
| Esc | Ô có chữ → xoá chữ; ô trống → đóng, bàn phím về chỗ trước khi mở |
| Tab / Shift+Tab | Giữ trong ô tìm (bẫy focus; danh sách không là điểm dừng — điều khiển bằng ↑/↓ như combobox) |
| Phím tắt cửa sổ khác | Chạy, đóng bảng trước (như A4 §5.3) |

### 2.3 Trạng thái

| Trạng thái | Hiện |
|---|---|
| Mục bị vô hiệu ngữ cảnh (vd. "Phóng to pane" khi tab 1 pane, "Dán" khi không có tab) | **Ẩn** (spec D33) |
| Không có tab nào | Chỉ action không cần tab: Tab mới, Workspace mới, mục cấu hình, bảng thông báo |
| Lệnh của bạn khi không có terminal | Hiện; chạy → toast `userCommandNoTerminal` |

---

## 3. Vấn đề cấu hình (spec D8, D36)

### 3.1 Toast

```
╭──────────────────────────────────────────────╮
│ ⚠ Cấu hình có 2 vấn đề           Xem     ×   │   lỗi: toast lỗi A1; chỉ cảnh báo: toast trung tính
╰──────────────────────────────────────────────╯
```

- Vị trí, thời gian, tạm dừng khi rê/focus: A1 §2.8 (lỗi 6 s, trung tính 4 s). Nút "Xem" là nút chữ (hit 28, đệm 0/8), đứng trước ×; Tab: "Xem" → ×.
- Toast khác của A9 (trung tính): `configReloaded`, `configGhosttyNotice` (một lần), `configOpenFailed`/`configWriteFailed` (lỗi), `userCommandNoTerminal` (trung tính).

### 3.2 Bảng vấn đề

```
╭─────────────────────────────── 600 ────────────────────────────────╮
│ Vấn đề trong cấu hình                                           ×  │ 44
│ ~/.config/shellx/config · Ghostty: ~/.config/ghostty/config        │ 18 caption textSecondary
│────────────────────────────────────────────────────────────────────│
│ ⛔ Lỗi        config, dòng 3                                        │ 52
│              font-size: “to” không hợp lệ (cần 9–28)               │
│ ⚠ Cảnh báo   config, dòng 7                                        │
│              Hệ điều hành giữ ⌘Q                                    │
│ ⓘ Ghi chú    config, dòng 9                                        │
│              ⌃C sẽ không còn tới shell                              │
│────────────────────────────────────────────────────────────────────│
│                             [Tải lại cấu hình] [Mở file cấu hình]  │ 52
╰────────────────────────────────────────────────────────────────────╯
```

- Hộp: như bảng lệnh (`surface`, `r8`, `e1`), canh giữa vùng terminal, `y = 56`. Tiêu đề `bodyStrong` `textPrimary`; dòng 2: đường dẫn file đang đọc, `~` thay home, cắt giữa.
- Mục: cột trái 96 = biểu tượng 14 (`Icons.error_outline` `err` / `Icons.warning_amber` `warn` / `Icons.info_outline` `textSecondary`) + nhãn mức `small` cùng màu (màu **không** là tín hiệu duy nhất — WCAG 1.4.1). Phải: dòng 1 `small` `textSecondary` vị trí ("config, dòng 3" — tên file gốc, dòng 0 → chỉ tên file); dòng 2 `body` `textPrimary` thông điệp, xuống dòng tự do. Sắp xếp: lỗi → cảnh báo → ghi chú, rồi theo file, dòng.
- Không vấn đề: thân `body` `textSecondary` "Cấu hình không có vấn đề." canh giữa, đệm 24.
- Chân: nút phụ "Tải lại cấu hình", nút chính "Mở file cấu hình" (A1 §3.3), canh phải, đệm 12.
- Bàn phím: mở → focus nút "Mở file cấu hình"; danh sách là vùng đọc (mỗi mục một node Semantics, Tab không dừng ở từng mục — trình đọc màn hình duyệt bằng phím của nó; ↑/↓ cuộn danh sách khi nó có focus); Tab: danh sách → "Tải lại" → "Mở file" → × (bẫy); Esc/× → đóng, focus về chỗ cũ. Nạp lại khi bảng mở → nội dung cập nhật tại chỗ, đọc lên "Cấu hình có {n} vấn đề" / "Cấu hình không có vấn đề."

---

## 4. Trình sửa phím tắt (spec D32)

### 4.1 Giải phẫu

```
╭──────────────────────────────────────── 720 ─────────────────────────────────────────╮
│ Phím tắt                                                                          ×  │ 44
│ ┌──────────────────────────────────────────────────────────────────────────────────┐ │
│ │ 🔍 Tìm phím tắt                                                                   │ │ 36
│ └──────────────────────────────────────────────────────────────────────────────────┘ │
│  TAB                                                                                 │ 24 caption textSecondary
│  Tab mới                                   [⌘][T] ×   [⌃][⌥][N] ×   Thêm phím  Đặt lại│ 40
│  Đóng pane hoặc tab                        [⌘][W] ×                  Thêm phím       │
│  Đóng cả tab                               Chưa gán                  Thêm phím       │
│  PANE                                                                                │
│  Chia sang phải                            ┌ Bấm tổ hợp phím… (Esc để huỷ) ┐  Huỷ   │ ← đang ghi
│  Chia xuống dưới                           [⌘][⇧][D] ×                Thêm phím       │
│    ⚠ ⌘D đang dùng cho “Chia sang phải”.                     [Huỷ] [Thay thế]         │ ← xung đột
│  …                                                                                   │
│──────────────────────────────────────────────────────────────────────────────────────│
│  Phím viết tay trong file vẫn được giữ.                           [Mở file cấu hình] │ 52
╰──────────────────────────────────────────────────────────────────────────────────────╯
```

- Hộp: `surface`, `r8`, `e1`, canh giữa **cửa sổ** (rộng hơn vùng terminal), `scrim` A1 phía sau (đây là hộp thoại chỉnh sửa, chặn cửa sổ; Esc/× đóng).
- Nhóm theo thứ tự: Tab, Pane, Thông báo, Chỉnh sửa, Cỡ chữ, Trình duyệt, Cửa sổ (vùng, bảng lệnh), Cấu hình, Lệnh của bạn (một hàng mỗi `command`/`snippet`, action `run_command:<tên>`). Tiêu đề nhóm `caption` w600 `textSecondary` chữ hoa (vi: chữ hoa có dấu).
- **Hàng** 40: tên action `body` `textPrimary` (trái, rộng 280, cắt cuối + tooltip); các phím hiện tại dạng keycap, mỗi phím có nút × (hit 20, glyph 12, `textSecondary` → hover `textPrimary`); "Chưa gán" `small` `textSecondary` khi không có; bên phải: nút chữ "Thêm phím", "Đặt lại" (chỉ khi khác mặc định). Phím **đặt trong file ngoài khối quản lý**: keycap viền nét đứt, tooltip "Đặt trong file cấu hình, dòng N"; × của nó vẫn bỏ được (ghi `unbind` vào khối).
- Hàng hover `rowHover`; hàng có focus bàn phím: vòng 2 px `accent`.
- **Ghi phím:** "Thêm phím" → ô ghi (viền 1 px `accent`, `r4`, nền `surfaceInset`) chữ `shortcutsRecording` + nút "Huỷ"; tổ hợp vừa bấm hiện trực tiếp thành keycap (bổ trợ hiện ngay khi giữ). Thả bổ trợ mà không có phím chính → không ghi. Phím chính → kiểm:
  - Bị từ chối (spec D25 mức lỗi): ô ghi viền `err`, chữ lý do `small` `err` dưới hàng (thông điệp `configProblem*`), vẫn ở chế độ ghi.
  - Ghi chú D25 (vd. Ctrl+C tới shell): chấp nhận, ghi, hiện ghi chú `small` `textSecondary` dưới hàng 4 s.
  - Xung đột (trigger đang của action khác): dòng xung đột `warnBg`/`warnBorder` dưới hàng: "⚠ {phím} đang dùng cho “{action}”." + [Huỷ] [Thay thế] (focus "Thay thế"). Thay thế → bỏ phím ở action kia + gán ở action này (một lần ghi file).
  - Hợp lệ → ghi file → nạp lại → đọc lên `shortcutsAssigned`.
- Chân: `small` `textSecondary` "Phím viết tay trong file vẫn được giữ." + nút "Mở file cấu hình".

### 4.2 Bàn phím

| Phím | Hành vi |
|---|---|
| Mở hộp | Focus ô tìm |
| Tab / Shift+Tab | Ô tìm → (mỗi hàng) × của từng phím → "Thêm phím" → "Đặt lại" (khi có) → … → "Mở file cấu hình" → × của hộp; bẫy trong hộp |
| Enter / Space trên nút | Bấm nút |
| Đang ghi | Mọi phím là dữ liệu, **trừ**: Esc → huỷ ghi (không bao giờ ghi Esc); Tab/Shift+Tab trơn → huỷ ghi và di chuyển focus (không bẫy bàn phím, WCAG 2.1.2); F6/Shift+F6 trơn → từ chối (spec D25) |
| Esc (không ghi) | Đóng hộp, focus về chỗ cũ |

Trong hộp, phím tắt cửa sổ **không** chạy (hộp chặn, để ghi được ⌘T…).

---

## 5. Chỉ báo chuỗi phím (spec D28)

```
 vùng terminal
 │ $ _                                                  │
 │                                                      │
 │                                   ╭──────────────╮   │
 │                                   │ ⌃A …         │   │ 28, góc dưới phải, cách 12/12
 │                                   ╰──────────────╯   │
```

- Pill `surface`, viền 1 px `accent`, `rPill`, đệm 0/10, chữ `small` `textPrimary` (keycap không viền, dạng chữ `⌃A …` / `Ctrl+A …`). Góc dưới phải của **vùng terminal** (cách 12/12, trên mọi pane; pill driver A1 nằm góc trên phải nên không đè). Hiện tức thì, biến mất tức thì.
- Đọc lên lịch sự một lần khi vào chờ: `sequencePendingAnnounce`. Huỷ không đọc.

---

## 6. Khay (spec D45)

```
ShellX ▸ … ▸ Dòng lệnh ▸ (A7)
          ▸ Cấu hình ▸ Mở file cấu hình
                       Tải lại cấu hình
                       Phím tắt…
                       ─────────────
                       ⚠ 2 vấn đề cấu hình…      (chỉ khi có lỗi/cảnh báo)
```

Mục khay đưa cửa sổ lên trước (A1 D11) rồi làm việc của nó. "Tải lại" xong → toast trên cửa sổ nếu cửa sổ đang hiện, không thì không gì (vấn đề vẫn có ở mục ⚠).

---

## 7. Copy (vi + en, khoá ARB)

"pane", "tab", "workspace" giữ tiếng Anh (A3 §7). Phím trong `{shortcut}` từ nền tảng, không dịch. File mẫu (spec D37) và đầu ra CLI **tiếng Anh** (A7 D11). `{hint}` là cú pháp nguyên văn (vd. `9–28`, `block, bar, underline`, `#RRGGBB`), không dịch.

### 7.1 Chung

| Khoá | vi | en |
|---|---|---|
| `configProblemsToast` | Cấu hình có {count} vấn đề | "{count, plural, =1{1 problem in the configuration} other{{count} problems in the configuration}}" |
| `configProblemsShow` | Xem | Show |
| `configReloaded` | Đã tải lại cấu hình | Configuration reloaded |
| `configGhosttyNotice` | Đang dùng font và màu từ cấu hình Ghostty (tắt bằng ghostty-config = false) | Using fonts and colours from your Ghostty config (turn off with ghostty-config = false) |
| `configProblemsTitle` | Vấn đề trong cấu hình | Configuration problems |
| `configProblemsNone` | Cấu hình không có vấn đề. | No problems in the configuration. |
| `configProblemWhere` | {file}, dòng {line} | {file}, line {line} |
| `configSeverityError` | Lỗi | Error |
| `configSeverityWarning` | Cảnh báo | Warning |
| `configSeverityInfo` | Ghi chú | Note |
| `configOpenFile` | Mở file cấu hình | Open configuration file |
| `configReload` | Tải lại cấu hình | Reload configuration |
| `configOpenFailed` | Không mở được {path} | Couldn't open {path} |
| `configWriteFailed` | Không lưu được phím tắt vào {path} | Couldn't save the shortcut to {path} |
| `userCommandNoTerminal` | Không có terminal để chạy lệnh này | There's no terminal to run this in |

### 7.2 Thông điệp vấn đề (`ConfigProblemCode` → khoá; placeholder `{key}` `{value}` `{hint}` `{detail}`)

| Khoá | vi | en |
|---|---|---|
| `configProblemSyntax` | Dòng không có dấu “=” (dạng đúng: khoá = giá trị) | Line has no “=” (expected key = value) |
| `configProblemBadKey` | “{key}” không phải tên khoá hợp lệ | “{key}” is not a valid key name |
| `configProblemUnknownKey` | ShellX không có khoá “{key}” | ShellX has no key “{key}” |
| `configProblemBadValue` | {key}: “{value}” không hợp lệ (cần {hint}) | {key}: “{value}” is not valid (expected {hint}) |
| `configProblemOutOfRange` | {key}: {value} nằm ngoài {hint}, đã dùng {detail} | {key}: {value} is outside {hint}, using {detail} |
| `configProblemDuplicate` | {key}: thay cho dòng {detail} | {key}: replaces line {detail} |
| `configProblemIncludeMissing` | Không tìm thấy file “{value}” | File “{value}” not found |
| `configProblemIncludeCycle` | “{value}” đã được nạp (vòng lặp config-file) | “{value}” is already loaded (config-file loop) |
| `configProblemIncludeDepth` | config-file lồng quá 4 tầng | config-file is nested more than 4 levels |
| `configProblemUnreadable` | Không đọc được file — đang giữ cấu hình trước | Can't read the file — keeping the previous configuration |
| `configProblemNotUtf8` | File không phải UTF-8 — đang giữ cấu hình trước | The file isn't UTF-8 — keeping the previous configuration |
| `configProblemTooLarge` | File lớn hơn 256 KiB — đang giữ cấu hình trước | The file is larger than 256 KiB — keeping the previous configuration |
| `configProblemThemeNotFound` | Không tìm thấy chủ đề “{value}” | Theme “{value}” not found |
| `configProblemFontNotFound` | Không tìm thấy font “{value}” — dùng JetBrains Mono | Font “{value}” not found — using JetBrains Mono |
| `configProblemFontNotMonospace` | Font “{value}” không đơn cách — cột có thể lệch | Font “{value}” isn't monospaced — columns may not line up |
| `configProblemLowContrast` | Chữ và nền tương phản thấp ({detail}:1, nên từ 4,5:1) | Low text/background contrast ({detail}:1, aim for 4.5:1) |
| `configProblemUnsupportedValue` | {key} = {value} chưa được hỗ trợ (dùng {hint}) | {key} = {value} isn't supported (using {hint}) |
| `configProblemNotOnThisPlatform` | {key} chỉ có tác dụng trên macOS | {key} only has an effect on macOS |
| `configProblemBadTrigger` | “{value}” không phải tổ hợp phím hợp lệ | “{value}” is not a valid key combination |
| `configProblemUnknownAction` | Không có action “{value}” | There's no action “{value}” |
| `configProblemBadActionParam` | “{value}” không hợp lệ (cần {hint}) | “{value}” is not valid (expected {hint}) |
| `configProblemReservedTrigger` | Hệ điều hành giữ {value} | {value} is reserved by the system |
| `configProblemPlainKeyTrigger` | {value} dùng để gõ chữ — thêm Ctrl, Alt hoặc ⌘ | {value} is for typing — add Ctrl, Alt or ⌘ |
| `configProblemRegionTrigger` | F6 và Shift+F6 luôn dùng để chuyển vùng | F6 and Shift+F6 always move between regions |
| `configProblemShellKeyTrigger` | {value} sẽ không còn tới shell | {value} will no longer reach the shell |
| `configProblemOptionKeyTrigger` | {value} sẽ không còn gõ ký tự Option | {value} will no longer type its Option character |
| `configProblemAltGrTrigger` | {value} chỉ chạy với Alt trái; AltGr vẫn gõ ký tự | {value} works with the left Alt only; AltGr still types characters |
| `configProblemMissionControlTrigger` | Mission Control có thể giữ {value} | Mission Control may take {value} |
| `configProblemUnsupportedPrefix` | Tiền tố “{value}” không được hỗ trợ | The “{value}” prefix isn't supported |
| `configProblemSequenceTooLong` | Chuỗi phím tối đa 2 bước | Key sequences have at most 2 steps |
| `configProblemSequencePrefixShadows` | {value} là đầu một chuỗi phím nên không còn chạy một mình | {value} starts a key sequence, so it no longer works on its own |
| `configProblemUnknownCommand` | Không có lệnh “{value}” | There's no command “{value}” |
| `configProblemCommandLimit` | Quá 200 lệnh — bỏ phần sau | More than 200 commands — the rest are ignored |
| `configProblemInternal` | Lỗi không mong đợi — đang giữ cấu hình trước | Unexpected error — keeping the previous configuration |

### 7.3 Bảng lệnh và action

| Khoá | vi | en |
|---|---|---|
| `paletteTitle` | Bảng lệnh | Command palette |
| `paletteSearchLabel` | Tìm lệnh | Search commands |
| `paletteSearchHint` | Gõ tên lệnh… | Type a command… |
| `paletteNoResults` | Không có lệnh nào khớp | No matching commands |
| `paletteResultCount` | {count} lệnh | {count, plural, =1{1 command} other{{count} commands}} |
| `paletteKindUserCommand` | Lệnh của bạn | Your command |
| `paletteKindSnippet` | Đoạn chữ | Snippet |
| `paletteKindConfig` | Cấu hình | Configuration |
| `actionNewTab` | Tab mới | New tab |
| `actionCloseSurface` | Đóng pane hoặc tab | Close pane or tab |
| `actionCloseTab` | Đóng cả tab | Close whole tab |
| `actionNewWorkspace` | Workspace mới | New workspace |
| `actionToggleNotifications` | Bảng thông báo | Notifications |
| `actionJumpToUnread` | Tới thông báo chưa đọc | Jump to unread |
| `actionCopy` | Sao chép | Copy |
| `actionPaste` | Dán | Paste |
| `actionSelectAll` | Chọn tất cả | Select all |
| `actionGotoTab` | Tới tab {n} | Go to tab {n} |
| `actionNextTab` / `actionPreviousTab` | Tab sau / Tab trước | Next tab / Previous tab |
| `actionSplitRight` / `actionSplitDown` | Chia sang phải / Chia xuống dưới | Split right / Split down |
| `actionFocusPane` | {direction, select, left{Sang pane bên trái} right{Sang pane bên phải} up{Lên pane trên} other{Xuống pane dưới}} | {direction, select, left{Focus pane on the left} right{Focus pane on the right} up{Focus pane above} other{Focus pane below}} |
| `actionResizePane` | {direction, select, left{Dời đường chia sang trái} right{Dời đường chia sang phải} up{Dời đường chia lên} other{Dời đường chia xuống}} | {direction, select, left{Move divider left} right{Move divider right} up{Move divider up} other{Move divider down}} |
| `actionToggleZoom` | Phóng to / bỏ phóng to pane | Zoom or unzoom pane |
| `actionEqualize` | Cân bằng pane | Equalize panes |
| `actionFontBigger` / `actionFontSmaller` / `actionFontReset` | Chữ to hơn / Chữ nhỏ hơn / Cỡ chữ mặc định | Bigger text / Smaller text / Default text size |
| `actionNextRegion` / `actionPreviousRegion` | Vùng tiếp theo / Vùng trước | Next region / Previous region |
| `actionOpenBrowser` | Mở pane trình duyệt | Open browser pane |
| `actionBrowserFocusAddress` | Tới ô địa chỉ | Go to address bar |
| `actionBrowserReload` / `actionBrowserBack` / `actionBrowserForward` / `actionBrowserStop` | Tải lại trang / Trang trước / Trang sau / Dừng tải | Reload page / Back / Forward / Stop loading |
| `actionReloadConfig` | Tải lại cấu hình | Reload configuration |
| `actionOpenConfig` | Mở file cấu hình | Open configuration file |
| `actionCommandPalette` | Bảng lệnh | Command palette |
| `actionShowShortcuts` | Phím tắt… | Keyboard shortcuts… |
| `actionShowConfigProblems` | Xem vấn đề cấu hình | Show configuration problems |
| `actionRunCommand` | Chạy “{name}” | Run “{name}” |
| `actionSendText` | Gửi chữ vào terminal | Send text to the terminal |
| `actionIgnore` | Bỏ qua phím | Ignore key |

### 7.4 Phím tắt, chuỗi phím, khay, hỏi khi đóng

| Khoá | vi | en |
|---|---|---|
| `shortcutsTitle` | Phím tắt | Keyboard shortcuts |
| `shortcutsSearchLabel` | Tìm phím tắt | Search shortcuts |
| `shortcutsGroup` | {group, select, tabs{Tab} panes{Pane} notifications{Thông báo} editing{Chỉnh sửa} font{Cỡ chữ} browser{Trình duyệt} window{Cửa sổ} config{Cấu hình} other{Lệnh của bạn}} | {group, select, tabs{Tabs} panes{Panes} notifications{Notifications} editing{Editing} font{Text size} browser{Browser} window{Window} config{Configuration} other{Your commands}} |
| `shortcutsAdd` | Thêm phím | Add shortcut |
| `shortcutsAddFor` | Thêm phím cho “{action}” | Add a shortcut for “{action}” |
| `shortcutsReset` | Đặt lại | Reset |
| `shortcutsRemove` | Bỏ {shortcut} | Remove {shortcut} |
| `shortcutsNone` | Chưa gán | Not set |
| `shortcutsRecording` | Bấm tổ hợp phím… (Esc để huỷ) | Press a key combination… (Esc to cancel) |
| `shortcutsConflict` | {shortcut} đang dùng cho “{action}”. | {shortcut} is used by “{action}”. |
| `shortcutsReplace` | Thay thế | Replace |
| `shortcutsCancel` | Huỷ | Cancel |
| `shortcutsFromFile` | Đặt trong file cấu hình, dòng {line} | Set in the configuration file, line {line} |
| `shortcutsAssigned` | Đã gán {shortcut} cho “{action}” | {shortcut} now runs “{action}” |
| `shortcutsRemoved` | Đã bỏ {shortcut} | Removed {shortcut} |
| `shortcutsResetDone` | Đã đặt lại “{action}” | “{action}” reset |
| `shortcutsFooter` | Phím viết tay trong file vẫn được giữ. | Shortcuts written in the file are kept. |
| `sequencePending` | {shortcut} … | {shortcut} … |
| `sequencePendingAnnounce` | Đã bấm {shortcut}, chờ phím tiếp theo | {shortcut} pressed, waiting for the next key |
| `trayConfig` | Cấu hình | Configuration |
| `trayConfigOpen` | Mở file cấu hình | Open configuration file |
| `trayConfigReload` | Tải lại cấu hình | Reload configuration |
| `trayConfigShortcuts` | Phím tắt… | Keyboard shortcuts… |
| `trayConfigProblems` | ⚠ {count} vấn đề cấu hình… | {count, plural, =1{⚠ 1 configuration problem…} other{⚠ {count} configuration problems…}} |
| `confirmCloseAlwaysBody` | Shell trong tab này sẽ đóng. | The shell in this tab will close. |
| `confirmCloseAlwaysPanesBody` | {count} pane trong tab này sẽ đóng. | {count, plural, =1{1 pane in this tab will close.} other{{count} panes in this tab will close.}} |
| `confirmClosePaneAlwaysBody` | Shell trong pane này sẽ đóng. | The shell in this pane will close. |

(Tiếng Việt không chia số nhiều: các khoá plural ở vi viết một dạng `other{…}`.)

---

## 8. Trợ năng

- **Bảng lệnh:** `Semantics(scopesRoute, namesRoute, label: paletteTitle)`; ô tìm `TextField` có nhãn `paletteSearchLabel`; danh sách mỗi mục `Semantics(selected: <con trỏ>, button: true, label: "<tên>, <loại>, <phím>")`; khi số kết quả đổi đọc lên lịch sự `paletteResultCount` (gộp, ≤ 1 lần/500 ms); con trỏ đổi → đọc mục mới (lịch sự). macOS VoiceOver: ô tìm + danh sách như combobox (`TextField` giữ focus, mục chọn đọc qua announcement — Flutter chưa có `aria-activedescendant`).
- **Bảng vấn đề:** hộp `namesRoute` `configProblemsTitle`; mỗi mục một node "Lỗi, config, dòng 3, font-size …".
- **Trình sửa phím:** mỗi hàng `Semantics(label: "<action>, phím: ⌘T, ⌃⌥N")`; keycap × có nhãn `shortcutsRemove`; ô ghi `liveRegion` đọc tổ hợp đang giữ; ghi xong đọc `shortcutsAssigned`; xung đột đọc nội dung dòng xung đột và focus "Thay thế".
- **Chỉ báo chuỗi:** `sequencePendingAnnounce` một lần; pill `ExcludeSemantics` (đã đọc).
- **Bàn phím:** mọi bề mặt mở được bằng phím (⌘⇧P; bảng lệnh → "Phím tắt…"/"Xem vấn đề"); F6/Shift+F6 không bao giờ bị gán (spec D25); chế độ ghi không bẫy Tab (§4.2).
- **Tương phản:** §1.1; vùng terminal theo chủ đề — cảnh báo `lowContrast`; viền focus tự đổi màu (spec D15).
- **Giảm chuyển động:** không hoạt ảnh mới (bảng lệnh tức thì; hộp phím tắt dùng chuyển cảnh hộp thoại A1, tức thì khi giảm chuyển động).

---

## 9. Wireframe

### 9.1 Chủ đề sáng, hai pane, pane phải focus (macOS)

```
┌──────────────────────┬──────────────────────────────────────────────────────────────┐
│ ● ● ●       [🔔][+]  │                       zsh — ~/app                            │ 28 bgTerminal (chrome giữ tối)
│ ▌● zsh        ▥2  ×  │┌●─zsh──────────────────────┐┏●─vim─────────────────────[×]┓  │ đầu pane A3 giữ token
│                      ││ ~/app %                   │┃ (nền #FDF6E3 của chủ đề)     ┃  │ viền focus = bgTerminal
│                      ││                           │┃                               ┃  │ (accent chỉ 1,6:1 trên nền sáng)
└──────────────────────┴┴───────────────────────────┴┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛──┘
```

### 9.2 Toast + bảng vấn đề sau khi lưu file có lỗi — xem §3.

### 9.3 Chuỗi phím đang chờ — xem §5.

---

## 10. Nhất quán với mobile

App mobile không đọc file cấu hình (ngoài phạm vi). Phiên điện thoại gõ không bị ảnh hưởng bởi phím tắt desktop. Follow-up: đồng bộ chủ đề/font sang mobile qua tài khoản.
