# ShellX desktop A3 — UI addendum (chia pane, đường chia, đầu pane, phóng to, gộp chú ý)

- **Ngày:** 2026-10-07 · **Phạm vi:** A3 của `docs/superpowers/specs/2026-10-07-desktop-splits-a3-design.md` (ràng buộc; quyết định P1–P9, D1–D30). Tài liệu này **thêm** vào UI doc A1 `2026-10-06-shellx-desktop-ui.md` ("A1 §N"), UI addendum A2 `2026-10-07-shellx-desktop-ui-a2.md` ("A2 §N") và A4 `2026-10-07-shellx-desktop-ui-a4.md` ("A4 §N"); mọi token, kiểu chữ, trạng thái, quy tắc focus và copy của ba tài liệu đó vẫn giữ.
- **Nguyên tắc (giữ A1):** cửa sổ là terminal trước tiên. **Tab một pane trông giống hệt A4** — không đầu pane, không viền, không đường chia. Mọi thứ của A3 chỉ hiện khi tab có ≥ 2 pane. Không hoạt ảnh lặp; chia/đóng/phóng to **tức thì** (như chuyển tab A1 §1.5).
- **Không có token màu mới.** Mọi màu từ A1 §1.1. Tương phản đo theo WCAG 2.x.

---

## 1. Token dùng lại và kích thước mới

### 1.1 Màu (tất cả từ A1 §1.1)

| Dùng cho | Token | Trên nền | Tương phản |
|---|---|---|---|
| Đường chia (thường) | `line` `#243337` | `bgTerminal` | trang trí (1,3); ranh giới đã rõ nhờ đầu pane + viền focus |
| Đường chia (hover/kéo) | `accent` `#5FD4E2` | `bgTerminal` | 10.8 (≥ 3) |
| Nền đầu pane — pane focus | `rowSelected` `#1F2F34` | — | — |
| Nền đầu pane — pane không focus | `bgSidebar` `#111B1E` | — | — |
| Tiêu đề đầu pane — focus | `textPrimary` `#D4E1E4` | `rowSelected` | 11.5 |
| Tiêu đề đầu pane — không focus | `textSecondary` `#93A5A9` | `bgSidebar` | 6.8 |
| Tiêu đề pane đã thoát | `textSecondary` | `rowSelected` / `bgSidebar` | 6.0 / 6.8 |
| Chỉ báo phóng to ("Phóng to · 2/3") | `accent` | `rowSelected` | 7.93 |
| Chấm chưa đọc trên đầu pane / chỉ báo phóng to | `accent` | `rowSelected` / `bgSidebar` | 7.93 / 10.0 (≥ 3) |
| × đầu pane | `textSecondary` → hover `textPrimary` trên `rowPressed` | `rowSelected` / `bgSidebar` | 6.0 / 6.8; hover 9.4 |
| Viền focus pane | `accent` 100 % | `bgTerminal` / `rowSelected` | 10.8 / 7.93 (≥ 3, WCAG 2.4.11/1.4.11) |
| Dấu số pane (dòng sidebar) | `textSecondary` | `bgSidebar` / `rowHover` / `rowSelected` / `rowPressed` | 6.8 / 6.22 / 5.41 / 4.72 |

**Không làm mờ** pane không focus (spec D16): mọi chữ terminal giữ tương phản bảng màu A1.

### 1.2 Kích thước mới (thêm vào `ShellxSizes`)

| Tên | Giá trị | Ghi chú |
|---|---|---|
| `paneDivider` | 1 | nét đường chia, chiếm 1 px bố trí |
| `paneDividerHit` | 6 | vùng bấm, canh giữa nét (2,5 px mỗi bên đè lên pane) |
| `paneHeader` | 22 | đầu pane khi ≥ 2 pane |
| `paneHeaderPadH` | 8 | lề ngang trong đầu pane |
| `paneHeaderDot` | 6 | chấm trạng thái trong đầu pane (ô 12) |
| `paneHeaderClose` | 18 | nút × nhìn 18 (`r4`), vùng bấm 22×22 = cả chiều cao đầu pane; glyph 12 |
| `paneFocusOutline` | 1 | viền focus (vẽ = 1 px thiết bị dưới 2×, 2 px ở 2×; sửa đợt cuối S-2) |
| `paneDividerActive` | 3 | dải `accent` khi hover/kéo đường chia, chỉ vẽ (bố trí giữ 1 px; sửa đợt cuối S-1) |
| `paneRingInset` | 2 | vòng chú ý của pane **không** focus lùi vào trong pane (sửa đợt cuối S-3) |
| `pillIconOnlyBelow` | 260 | pane hẹp hơn → dải driver chỉ còn biểu tượng (sửa đợt cuối S-4) |
| `paneMinCols` | 20 | cột tối thiểu (D4) |
| `paneMinRows` | 5 | dòng tối thiểu (D4) |
| `paneResizeStep` | 0.05 | bước đổi cỡ bằng phím (D12) |
| `paneCountIcon` | 12 | biểu tượng số pane ở dòng sidebar |
| `paneCountGap` | 2 | giữa biểu tượng và chữ số |

Kích thước tối thiểu theo px của một pane: `rộng = paneMinCols × cell.width + 20` (padding A1 10/10), `cao = paneMinRows × cell.height + 12 + 22` (padding 6/6 + đầu pane).

### 1.3 Cỡ chữ lớn

Đầu pane cao `max(22, scale(16) + 6)`; chữ `small` theo `textScaler`. Dấu số pane: chữ `caption` theo `textScaler`, biểu tượng giữ 12.

---

## 2. Vùng terminal có nhiều pane

### 2.1 Giải phẫu (chia phải rồi chia xuống bên phải; pane 3 focus)

```
x=221 (sau sidebar)                         ↓ đường chia 1 px (vùng bấm 6)
┌─────────────────────────────────────┬┬────────────────────────────────────┐ ← dưới đầu pane macOS 28 / dải đăng nhập
│● zsh — ~/work/shellx            [ ] ││● vim main.dart                 [ ] │ ← đầu pane 22, bgSidebar, small textSecondary
│ ~/work/shellx % _                   ││ 1 import 'package:…'               │
│                                     ││ 2                                  │
│                                     │├────────────────────────────────────┤ ← đường chia ngang
│                                     │┏●━claude━━━━━━━━━━━━━━━━━━━━━━━[×]━┓ ← pane focus: đầu rowSelected,
│                                     │┃ ✻ Do you want to proceed?         ┃   chữ textPrimary, × hiện,
│                                     │┃                                   ┃   viền 1 px accent quanh cả pane
└─────────────────────────────────────┴┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

- **Đầu pane (22):** `|8|● 6 trong ô 12|6| tiêu đề (small, flex, 1 dòng, ellipsis) |4|📱 12|4|👁 12|4|• 6|4|[Phóng to · 2/3]|4|× 18|4|`. Dấu điện thoại theo A1 §2.2 nhưng 12 px. Chấm trạng thái: màu A1 (`ok` rảnh, `accent` đang chạy lệnh, vòng `err` đã thoát). Tiêu đề = tên tự động của **pane** (OSC 0/2 hoặc "zsh 3"), không dùng tên tuỳ chỉnh của tab.
- **× đầu pane:** hiện khi hover đầu pane hoặc pane focus; chỗ luôn giữ (tiêu đề không nhảy). Tooltip `paneCloseTooltip` "Đóng pane  ⌘W". Không là điểm dừng Tab (⌘W và menu thay).
- **Chuột giữa** trên đầu pane = ×. **Nháy đúp** đầu pane = bật/tắt phóng to.
- Đầu pane **không** kéo được cửa sổ (đầu pane macOS 28 vẫn là vùng kéo).
- **Terminal trong pane:** padding A1 (10/6) giữ nguyên; clip trong pane; thanh cuộn overlay A1 trong mép phải pane.
- **Viền focus:** 1 px `accent` vẽ đè (không nhận chuột) **trong** hình chữ nhật pane (đầu + terminal), không đổi constraints. Chỉ khi ≥ 2 pane và không phóng to. **Sửa đợt cuối S-2:** mép viền khớp điểm ảnh thiết bị của cửa sổ (làm tròn từng mép), bề dày `max(1, floor(dpr))` điểm ảnh thiết bị (1,25× → 1 px thiết bị = 0,8 px logic) — viền luôn là một nét `accent` đặc, không nhoè ở 125 %.
- **Dải driver A1 §2.5:** trong pane của phiên đó (góc phải trên **dưới đầu pane**, quy tắc dời xuống giữ nguyên); bề rộng tối đa `min(560, pane − 24)`; pane < 520 → chữ ngắn. **Sửa đợt cuối S-4:** pane < 260 → chỉ biểu tượng 📱 trong viên tròn 28×28 (nền/viền như dải), tooltip và nhãn trợ năng là câu đầy đủ `terminalDriverPhone` (lời dặn không bao giờ bị cắt); viên này nhận chuột (cho tooltip). Quy tắc dời xuống dùng **chiều cao thật** của dải (dải ngắn xuống 2 dòng cao ~52), không giả định 28.
- **Toast A1 §2.8:** vẫn một cái, đáy giữa **cả vùng terminal** (không theo pane).

### 2.2 Đường chia

- Nét 1 px `line`, chiếm 1 px giữa hai pane. Vùng bấm 6 px canh giữa nét (`MouseRegion` + `GestureDetector`, đè lên mép hai pane, không chiếm chỗ).
- Con trỏ: `SystemMouseCursors.resizeColumn` (đường dọc) / `resizeRow` (đường ngang).
- Hover (chờ 0 ms) hoặc đang kéo: nét đổi sang `accent` (`fast` 80 ms; giảm chuyển động → tức thì). **Sửa đợt cuối S-1:** khi hover/kéo vẽ một **dải `accent` 3 px** (`paneDividerActive` × nét mảnh: 3 px ở 1× và 2×, 3 px thiết bị ở 1,25×) canh giữa nét, nằm trong vùng bấm 6 px — cạnh viền focus cùng màu vẫn thấy rõ. Chỉ vẽ: bố trí vẫn 1 px, pane không xê dịch.
- Nét (thường và dải) khớp điểm ảnh thiết bị của cửa sổ, bề dày thường `max(1, floor(dpr))` px thiết bị (sửa đợt cuối S-2).
- Kéo: tỉ lệ theo vị trí con trỏ trong nút cha, kẹp theo cỡ tối thiểu (§1.2) của **mọi** pane hai bên. Nháy đúp: cân bằng nút đó (spec D11).
- Tooltip: không (đường chia hẹp, tooltip che chữ).

### 2.3 Phóng to

```
┌───────────────────────────────────────────────────────────────────────────┐
│● claude                                    [• Phóng to · 3/3]          [×] │ ← đầu pane vẫn hiện khi phóng to
│ ✻ Do you want to proceed?                                                   │
│                                                                             │   không viền focus, không đường chia
└───────────────────────────────────────────────────────────────────────────┘
```

- Chỉ báo `paneZoomedIndicator` "Phóng to · {index}/{count}": `caption` w600 `accent`, không nền; đứng trước ×. Có chấm `accent` 6 đứng trước chữ khi **pane ẩn** có chưa đọc (A4). Bấm chỉ báo = bỏ phóng to (vùng bấm 22 cao). **Sửa đợt cuối N-5:** con trỏ `click`, tooltip `paneUnzoom` "Bỏ phóng to".
- Chuyển tức thì (không phóng/thu hoạt ảnh).

### 2.4 Trạng thái pane

| Trạng thái | Nhìn |
|---|---|
| Focus | đầu `rowSelected`, chữ `textPrimary`, × hiện, viền `accent` |
| Không focus | đầu `bgSidebar`, chữ `textSecondary`, × khi hover |
| Không focus, hover đầu | đầu `rowHover` |
| Có chưa đọc (A4) | vòng A4 (2 px + 1 px 40 %) quanh **pane** (đè lên viền focus nếu pane đó focus); pane **không** focus: vòng lùi vào trong `paneRingInset` 2 px (sửa đợt cuối S-3); chấm `accent` trên đầu pane |
| Đã thoát (mã ≠ 0) | chấm vòng `err`, tiêu đề `textSecondary`; dòng thoát A1 §2.6 trong buffer |
| Điện thoại lái | dải driver trong pane; 👁 `warn` trên đầu pane |
| Không đủ chỗ để chia | toast trung tính `paneSplitNoRoom` |

### 2.5 Vòng sáng theo pane (sửa A4 §4)

Vòng A4 vẽ trong **hình chữ nhật của từng pane** có chưa đọc thuộc tab đang chọn (gồm cả đầu pane). Tab một pane: hình chữ nhật pane = vùng terminal A4 → **trùng khít A4**.

**Sửa đợt cuối S-3:** pane **không** focus vẽ vòng lùi vào trong 2 px (`paneRingInset`), nên vòng của nó không bao giờ dính với viền focus của pane bên cạnh thành một vạch dày (trước đây pane có vòng trông như pane đang focus). Pane focus: vòng đúng mép pane (đè viền focus). Dấu hiệu mạnh hơn của pane focus trên đầu pane giữ nguyên: nền `rowSelected`, tiêu đề `textPrimary` (pane không focus: `bgSidebar`, `textSecondary`), × hiện. Thứ tự lớp trong pane: terminal < viền focus < vòng < dải driver. Chuyển động như A4.

---

## 3. Dòng sidebar của tab có nhiều pane

```
|6|8 |—8—| title (pane focus) |4|(2)|4|▥2|4|📱|4|👁|2|×|8|     ← dòng tiêu đề
                                   badge  └ dấu số pane: icon 12 + 2 + chữ số caption, textSecondary
|6|— 32 —| 🔔 xong (A4)                                 |8|
|6|— 32 —| main · ~/work/shellx · :3000 (pane focus)    |8|
```

- Dấu số pane (`Icons.view_column_outlined` 12 + `caption` số; **sửa đợt cuối N-3:** gốc cây là chia xuống → `Icons.view_agenda_outlined`): chỉ khi ≥ 2 pane; không bao giờ cắt; tooltip `sidebarPaneCount` "{count} pane". Thứ tự dấu: badge A4 → số pane → 📱 → 👁 → ×.
- × dòng / "Đóng tab": đóng **cả tab**; tooltip × chỉ có gợi ý `⌘W` khi tab 1 pane (spec D6): nhiều pane → tooltip `terminalCloseTabAllPanes` "Đóng tab (mọi pane)".
- Chiều cao dòng: không đổi so với A4 (dấu nằm trên dòng tiêu đề).

---

## 4. Menu

### 4.1 Menu terminal (sửa A1 ruling I6)

```
 ╭──────────────────────────────────────────╮
 │ Sao chép                             ⌘C  │
 │ Dán                                  ⌘V  │
 │ Chọn tất cả                          ⌘A  │
 │──────────────────────────────────────────│
 │ Chia sang phải                       ⌘D  │
 │ Chia xuống dưới                     ⌘⇧D  │
 │ Phóng to pane                       ⌘⇧↩  │  ← chỉ khi ≥ 2 pane; "Bỏ phóng to" khi đang phóng to
 │ Cân bằng pane                       ⌘⌃=  │  ← chỉ khi ≥ 2 pane
 │──────────────────────────────────────────│  ← chỉ khi ≥ 2 pane
 │ Đóng pane                            ⌘W  │  ← chỉ khi ≥ 2 pane
 ╰──────────────────────────────────────────╯
```

Bấm chuột phải vào pane không focus → pane đó nhận focus **trước** khi menu mở; menu tác động pane đó.

### 4.2 Menu dòng tab (A2 §5.1 + A4 §10.4 + A3)

Thêm nhóm sau "Dùng tên tự động" (vạch trước): "Chia sang phải" (`⌘D`), "Chia xuống dưới" (`⌘⇧D`), "Cân bằng pane" (`⌘⌃=`, chỉ khi ≥ 2 pane). Chọn mục chia → tab được chọn, chia pane focus của tab, bàn phím về pane mới. Mục "Đóng tab" giữ cuối; **sửa đợt cuối N-2:** tab ≥ 2 pane → nhãn `terminalCloseTabAllPanes` "Đóng tab (mọi pane)" (không gợi ý ⌘W, spec D6).

---

## 5. Phím tắt (gợi ý hiện trong menu/tooltip; nhãn từ nền tảng, không dịch)

| Hành động | macOS | Windows |
|---|---|---|
| Chia sang phải | ⌘D | Ctrl+Shift+D |
| Chia xuống dưới | ⌘⇧D | Ctrl+Shift+Alt+D |
| Focus pane ←/→/↑/↓ | ⌘⌥←/→/↑/↓ | Ctrl+Alt+←/→/↑/↓ |
| Đóng pane | ⌘W | Ctrl+Shift+W |
| Phóng to / bỏ | ⌘⇧↩ | Ctrl+Shift+Enter |
| Cân bằng | ⌘⌃= | Ctrl+Shift+Alt+= |
| Đổi cỡ ←/→/↑/↓ | ⌘⌃←/→/↑/↓ | Ctrl+Shift+Alt+←/→/↑/↓ |

Windows: chord có Alt chỉ khi **Alt trái** (AltGr giữ cho shell, như A1 Ctrl+Alt+số).

---

## 6. Bàn phím và focus (sửa A1 §3.6)

- Vùng 1 "Terminal" = **pane đang focus** của tab đang chọn. Ctrl+F6/F6 vòng vùng như A1 (không đi qua từng pane — các pane đi bằng ⌘⌥mũi tên).
- Chọn tab (sidebar, ⌘1–9, ⌃Tab) → bàn phím vào pane focus đã nhớ của tab đó.
- Đóng pane → bàn phím vào pane focus mới (spec D8). Đóng pane cuối → như đóng tab A1.
- Hộp xác nhận đóng (A1 §4) trả bàn phím về pane focus khi huỷ.

---

## 7. Copy (vi + en, khoá ARB)

Giọng văn A1 §5. "pane", "tab", "terminal" giữ tiếng Anh (như "workspace", A2 D13).

| Khoá | vi | en |
|---|---|---|
| `paneSplitRight` | Chia sang phải | Split right |
| `paneSplitDown` | Chia xuống dưới | Split down |
| `paneZoom` | Phóng to pane | Zoom pane |
| `paneUnzoom` | Bỏ phóng to | Unzoom pane |
| `paneEqualize` | Cân bằng pane | Equalize panes |
| `paneClose` | Đóng pane | Close pane |
| `paneCloseTooltip` | Đóng pane  {shortcut} | Close pane  {shortcut} |
| `paneZoomedIndicator` | Phóng to · {index}/{count} | Zoomed · {index}/{count} |
| `paneRegionLabel` | Pane {index} trên {count} — {title} | Pane {index} of {count} — {title} |
| `paneRegionUnreadLabel` | Pane {index} trên {count} — {title}, có thông báo chưa đọc | Pane {index} of {count} — {title}, has unread notifications |
| `paneDividerLabel` | Đường chia pane | Pane divider |
| `paneSplitNoRoom` | Không đủ chỗ để chia pane này | Not enough room to split this pane |
| `paneAnnounceSplit` | Đã chia, pane {index} trên {count} | Split, pane {index} of {count} |
| `paneAnnounceClosed` | Đã đóng pane, còn {count} | {count, plural, =1{Pane closed, 1 left} other{Pane closed, {count} left}} |
| `paneAnnounceZoomed` | Đã phóng to pane | Pane zoomed |
| `paneAnnounceUnzoomed` | Đã bỏ phóng to | Pane unzoomed |
| `sidebarPaneCount` | {count} pane | {count, plural, =1{1 pane} other{{count} panes}} |
| `terminalCloseTabAllPanes` | Đóng tab (mọi pane) | Close tab (all panes) |
| `confirmCloseRunningPaneBody` | Lệnh đang chạy trong pane này sẽ bị dừng. | The command running in this pane will be stopped. |
| `confirmCloseRunningPaneAction` | Đóng pane | Close pane |
| `confirmCloseRunningPanesBody` | {count} pane đang chạy lệnh sẽ bị dừng. | {count, plural, =1{The command running in 1 pane will be stopped.} other{The commands running in {count} panes will be stopped.}} |

- `index`, `count` là `int`; tiếng Việt không chia số nhiều.
- Đọc lên khi đổi focus bằng phím dùng `paneRegionLabel`.

---

## 8. Trợ năng

- **Pane (≥ 2):** `Semantics(container: true, label: paneRegionLabel | paneRegionUnreadLabel)` bọc cả đầu pane + terminal; đầu pane, chấm, dấu, chỉ báo: `ExcludeSemantics` (đã trong nhãn); `customSemanticsActions`: "Đóng pane", "Phóng to pane"/"Bỏ phóng to", "Chia sang phải", "Chia xuống dưới". Tab một pane: nhãn A1/A4 "Terminal {title}" (không đổi).
- **Đường chia:** `Semantics(slider: true, label: paneDividerLabel, value: "{n} %", onIncrease/onDecrease: ±5 %)`; không là điểm dừng Tab (bàn phím dùng ⌘⌃mũi tên — WCAG 2.5.7 thay thế cho kéo).
- **Dòng sidebar:** nhãn A2/A4 thêm `sidebarPaneCount` ngay sau tiêu đề khi ≥ 2 pane; custom actions thêm "Chia sang phải", "Chia xuống dưới".
- **Đọc lên** (`SemanticsService.sendAnnouncement`, lịch sự): chia, đóng pane, đổi focus bằng phím, phóng to/bỏ (bảng §7). Bấm chuột đổi focus: không đọc (người dùng đang nhìn).
- **Tương phản:** bảng §1.1 — chữ ≥ 4.72:1, thành phần không phải chữ ≥ 3:1. Viền focus 1 px `accent` 10.8:1.
- **Giảm chuyển động:** hover đường chia tức thì; mọi thứ khác đã tức thì.
- **Mục tiêu bấm:** × đầu pane 22×22 (WCAG 2.5.8 ≥ 24 không đạt theo chiều cao → khoảng trống 4 px quanh, ngoại lệ "spacing" 2.5.8 được: không có mục tiêu nào khác trong vòng 24); đường chia 6 px (có lựa chọn bàn phím + menu → ngoại lệ "equivalent").

---

## 9. Wireframe

### 9.1 Ba pane, pane 2 có chưa đọc (không focus), pane 3 focus (macOS)

```
┌──────────────────────┬─────────────────────────────────────┬┬──────────────────────────────────┐
│ ● ● ●       [🔔•][+] │                claude               ││                                  │
│ ▌● claude (1) ▥3  ×  │● zsh — ~/work/shellx             [ ]┃┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓│
│    🔔 Build xong      │ ~/work/shellx % _                  ┃┃● build              •        [ ]┃│ ← vòng A4 quanh pane 2
│    main · ~/w/shellx  │                                    ┃┃ ✓ built in 4.2s                ┃│
│  ● api        📱      │                                    ┃┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛│
│    dev · ~/w/api      │                                    │├──────────────────────────────────┤
│                       │                                    │┌●─claude──────────────────────[×]┐│ ← pane focus, viền 1 px
│                       │                                    ││ ✻ Do you want to proceed?        ││
└───────────────────────┴────────────────────────────────────┴└──────────────────────────────────┘┘
 ▥3 = dấu số pane · (1) = badge tổng · tiêu đề dòng "claude" = pane focus
```

### 9.2 Không đủ chỗ để chia

```
│ … pane 1 hẹp (24 cột) …   │      ╭───────────────────────────────────────╮
│                            │      │ Không đủ chỗ để chia pane này      ×  │  ← toast trung tính A1 §2.8
```

### 9.3 Menu terminal trên pane không focus

Pane 1 không focus, chuột phải → pane 1 focus (viền chuyển), menu §4.1 mở tại con trỏ.

---

## 10. Nhất quán với mobile (follow-up, không làm trong A3)

Điện thoại vẫn liệt kê từng pane là một phiên; nhóm theo tab desktop trên điện thoại cần protocol mới (`tabId` trong `SessionInfo`, opt-in như A2 C4) — để sau A5.
