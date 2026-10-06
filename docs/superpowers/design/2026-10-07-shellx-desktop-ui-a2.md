# ShellX desktop A2 — UI addendum (dòng ngữ cảnh, workspace, đổi tên tab)

- **Ngày:** 2026-10-07 · **Phạm vi:** A2 của `docs/superpowers/specs/2026-10-07-desktop-sidebar-a2-design.md` (ràng buộc; quyết định C1–C8, D1–D19). Tài liệu này **thêm** vào UI doc A1 `2026-10-06-shellx-desktop-ui.md`; mọi token, kiểu chữ, trạng thái, quy tắc focus và copy của A1 vẫn giữ. Gọi tắt "A1 §N" cho các mục UI doc A1.
- **Nguyên tắc (giữ A1):** cửa sổ là terminal trước tiên. Mọi thay đổi chỉ nằm trong sidebar 220 px; **không có gì làm đổi cỡ terminal** (đổi cỡ = desktop lấy driver, A1 D6).
- **Không có token màu mới.** Mọi màu lấy từ A1 §1.1. Tương phản dưới đây đo theo công thức WCAG 2.x (đo lại cho A2).

---

## 1. Token dùng lại và kích thước mới

### 1.1 Màu (tất cả từ A1 §1.1)

| Dùng cho | Token | Trên nền | Tương phản |
|---|---|---|---|
| Chữ dòng ngữ cảnh (nhánh, thư mục, dấu " · ", "+N") | `textSecondary` `#93A5A9` | `bgSidebar` / `rowHover` / `rowSelected` / `rowPressed` | 6.8 / 6.22 / 5.41 / 4.72 |
| Cổng (liên kết) | `accent` `#5FD4E2` | `bgSidebar` / `rowHover` / `rowSelected` / `rowPressed` | 10.0 / 9.11 / 7.93 / 6.91 |
| Tên workspace | `textSecondary` (thường), `textPrimary` (khi nhóm thu gọn chứa tab đang chọn) | `bgSidebar` / `rowHover` | 6.8 / 6.22; `textPrimary` 13.1 / 11.9 |
| Số tab trên tiêu đề | `textSecondary` | như trên | ≥ 6.22 |
| Nền đích thả (tiêu đề, nhóm trống) | `primarySoft` `#0E363C` + viền 1 px `accent` | — | chữ `textSecondary` 5.09, `textPrimary` 9.74; viền `accent` 7.45 (≥ 3) |
| Vạch chỉ chỗ thả | `accent` | `bgSidebar` | 10.0 (≥ 3) |
| Ô đổi tên | nền `surfaceInset` `#0D1315`, viền 1 px `accent`, chữ `textTitle` | — | chữ 16.2; viền 10.7 |
| Gợi ý nhóm trống | `textSecondary` | `bgSidebar` | 6.8 |

`dim` (4.32) **không** dùng cho chữ ở bất kỳ chỗ nào trong A2 (A1 §1.1).

### 1.2 Kích thước mới (thêm vào `ShellxSizes`)

| Tên | Giá trị | Ghi chú |
|---|---|---|
| `rowWithContext` | 46 | 6 + 18 (dòng tiêu đề) + 2 + 14 (dòng ngữ cảnh) + 6 |
| `contextLine` | 14 | dòng `caption` 11/14 |
| `contextGap` | 2 | giữa dòng tiêu đề và dòng ngữ cảnh |
| `contextInset` | 32 | lề trái dòng ngữ cảnh = 8 (padding) + 16 (ô chấm) + 8, thẳng hàng với tiêu đề |
| `portHit` | 24 | chiều cao vùng bấm một cổng (WCAG 2.5.8), canh giữa dòng ngữ cảnh |
| `portGap` | 4 | giữa hai cổng |
| `portPadH` | 2 | đệm ngang trong vùng bấm cổng (nền hover `rowPressed`, `r4`) |
| `portsMaxShare` | 0.6 | cụm cổng chiếm tối đa 60 % bề rộng dòng ngữ cảnh |
| `branchMaxShare` | 0.45 | nhánh tối đa 45 % phần còn lại (tối thiểu 48 px nếu đủ chỗ) |
| `pathMin` | 24 | thư mục hẹp hơn mức này thì bỏ hẳn |
| `workspaceHeader` | 28 | chiều cao tiêu đề nhóm |
| `workspaceHeaderTop` | 8 | khoảng trên mỗi tiêu đề (trừ tiêu đề đầu: dùng `listTop` 4) |
| `chevronHit` | 20 | vùng mũi tên thu gọn (icon 14) |
| `headerAddHit` | 24 | nút `+` trên tiêu đề (icon 14, nhìn 20 `r4`) |
| `headerCountMin` | 16 | bề rộng tối thiểu ô số tab |
| `collapsedMarkHeight` | 12 | thanh `accent` 3×12 ở mép trái tiêu đề khi nhóm thu gọn chứa tab đang chọn |
| `renameField` | 22 | chiều cao ô đổi tên trong dòng/tiêu đề |
| `renameMaxLength` | 64 | ký tự |
| `dropLine` | 2 | vạch chỉ chỗ thả |
| `dragAutoScrollZone` | 32 | vùng mép trên/dưới danh sách tự cuộn khi kéo |
| `dragAutoScrollSpeed` | 240 | px/giây |
| `dragExpandDelay` | 600 ms | rê tab trên tiêu đề nhóm thu gọn → tự mở rộng |
| `emptyWorkspaceRow` | 30 | dòng gợi ý của nhóm trống |

Thang khoảng cách, bo góc, độ nổi, chuyển động: A1 §1.2–§1.5 (không thêm token).

### 1.3 Cỡ chữ lớn

- Dòng có ngữ cảnh: `max(46, scale(18) + scale(14) + 14)` (14 = 6 + 2 + 6).
- Dòng không ngữ cảnh: công thức A1 `max(30, scale(18) + 12)`.
- Tiêu đề nhóm: `max(28, scale(16) + 12)`.
- Dòng gợi ý nhóm trống: `max(30, scale(14) + 16)`.
- Sidebar tính vị trí cuộn bằng tổng chiều cao từng mục (không còn giả định mọi dòng cao bằng nhau như A1).

---

## 2. Dòng tab có ngữ cảnh

### 2.1 Giải phẫu

```
|6|8 |—8—|  title (body / bodyStrong khi chọn, 1 dòng, ellipsis) |4|📱|4|👁|2|×|8|   ← dòng tiêu đề 18 (giữ A1 §2.2)
         ↑ chấm 8 trong ô 16                                                         2
|6|— 32 (contextInset) —| main · ~/w/shellx/apps · :3000 :5173 +1  |8|               ← dòng ngữ cảnh 14, caption 11/14
                        └──────────── 168 px ở sidebar 220 ─────────┘
```

- Dòng tiêu đề **giống hệt A1** (chấm, tiêu đề, dấu điện thoại, nút ×, thanh chọn 3×18 canh giữa **cả dòng 46**).
- Dòng ngữ cảnh: `caption` (11/14, 500), một dòng, không xuống dòng. Phần nào không có thì bỏ cả phần đó lẫn dấu ngăn. Dấu ngăn: `" · "` (`textSecondary`).
- Thứ tự cố định: **nhánh · thư mục · cổng**.
- Không có phần nào (phiên không hook, chưa có cổng) → **dòng 30 px của A1**, không chừa chỗ trống.
- Tab đã thoát (mã ≠ 0): giữ dòng ngữ cảnh cuối cùng, chữ `textSecondary`, cổng **không** còn là liên kết (cũng `textSecondary`, không hover).

### 2.2 Bố trí khi chật (hàm thuần `layoutContextLine`, D12)

Bề rộng W = bề rộng dòng − 32 − 8 (168 px ở 220).

1. **Cổng:** đo cụm `:p1 :p2 :p3` (tối đa 3 cổng nhỏ nhất, cách nhau `portGap` 4 + đệm 2×2 mỗi cổng) và `+N` nếu còn. Nếu cụm > 60 % W thì bớt cổng (giữ cổng nhỏ nhất) và tăng N, tới khi vừa hoặc còn 1 cổng. Cổng **không bao giờ bị cắt chữ**.
2. Phần còn lại R = W − cụm cổng − dấu ngăn.
3. **Nhánh:** bề rộng tự nhiên, tối đa `max(48, 0.45 × R)` (nếu R < 48 thì tối đa R); quá thì **cắt cuối** (`feat/mobile-ui-p…`).
4. **Thư mục:** phần còn lại; quá thì **cắt giữa** theo thành phần: giữ thành phần đầu (`~`, gốc `/` hoặc ổ `C:`), thay các thành phần giữa bằng `…`, và giữ **nhiều thành phần cuối nhất** còn vừa: `~/…/apps/desktop`. Nếu cắt rồi vẫn > chỗ, cắt giữa theo ký tự (`~/wo…sktop`). Nếu chỗ < 24 px → bỏ thư mục.
5. Toàn bộ dòng ngữ cảnh có tooltip (chờ 500 ms, đặt **bên phải sidebar** như tooltip tiêu đề A1 §3.1, max-width 360) với chuỗi đầy đủ không cắt: `main · ~/work/shellx/apps/desktop · :3000 :5173 :8080 :9229` — chỉ hiện khi có phần bị cắt hoặc bị bỏ.

### 2.3 Hiển thị thư mục

- Home của người dùng ở đầu → `~` (macOS phân biệt hoa thường; Windows **không**, và chấp nhận cả `\` lẫn `/`). Chỉ thay khi trùng nguyên thành phần (`/Users/richard2` không thành `~2`).
- Windows: hiện dấu `\` như hệ thống (`~\work\shellx`), ổ khác giữ nguyên (`D:\src`).
- Không thêm dấu `/` cuối. Thư mục gốc: `/`. Home chính nó: `~`.

### 2.4 Cổng (liên kết)

| Trạng thái | Nhìn |
|---|---|
| Thường | chữ `:3000` `accent`, không gạch chân |
| Hover | gạch chân 1 px `accent`, nền `rowPressed` `r4` trong vùng 24 cao, con trỏ `click` (`fast` 80 ms) |
| Nhấn | nền `rowPressed` |
| Tab đã thoát | `textSecondary`, không tương tác |

- Bấm → `UrlOpener.openLocalPort(port)` → `http://localhost:PORT/`; **không** chọn tab (cú bấm bị cổng giữ, không lan lên dòng). Lỗi → toast lỗi `portOpenFailed`.
- Tooltip mỗi cổng: `portOpenTooltip` "Mở http://localhost:3000" (chờ 500 ms, đặt bên phải sidebar).
- `+N`: chữ `textSecondary`, không phải liên kết; tooltip `portsMoreTooltip` liệt kê **mọi** cổng: "Cổng đang nghe: 3000, 5173, 8080, 9229".
- Bàn phím và trình đọc màn hình: mỗi cổng có mục "Mở cổng N trong trình duyệt" trong menu dòng (§5.1) và custom semantics action (§8).

### 2.5 Trạng thái dòng

Giữ bảng A1 §3.1. Thêm:

| Trạng thái | Nhìn |
|---|---|
| Đang đổi tên | ô đổi tên thay chữ tiêu đề (§4); nút × ẩn (chỗ vẫn giữ); dòng không hover/nhấn |
| Đang bị kéo (nguồn) | cả dòng 38 % độ đục tại chỗ cũ |
| Đang chọn + có ngữ cảnh | nền `rowSelected`, dòng ngữ cảnh vẫn `textSecondary` (5.41) |

---

## 3. Tiêu đề workspace

Chỉ hiện khi có **từ hai workspace** (D10). Một workspace = sidebar A1 nguyên vẹn.

### 3.1 Giải phẫu (28 cao, lề ngang 6 như dòng, `r6`)

```
|6|4|▾|4| Backend (small 600, 1 dòng, ellipsis)          |4| 3 |2|[+]|4|6|
      20 (chevron 14)                                        ≥16   24
 [thu gọn & chứa tab đang chọn: thanh accent 3×12 ở mép trái, tên textPrimary]
```

- Chevron: `Icons.expand_more` (mở) / `Icons.chevron_right` (thu gọn), 14, `textSecondary`. Đổi trạng thái: xoay 90° trong `base` 150 ms `easeOutCubic`; giảm chuyển động → tức thì.
- Tên: `small` 12/16 **w600**, `textSecondary`; tên rỗng không bao giờ xảy ra (Mặc định dùng chuỗi bản địa hoá khi tên lưu là `null`).
- Số tab: `caption` `textSecondary`, căn phải, bề rộng tối thiểu 16, số tab **của nhóm** (kể cả tab đã thoát chưa đóng).
- `+`: `Icons.add` 14 trong vùng 24×24 (nhìn 20, `r4`), chỉ hiện khi hover hoặc khi tiêu đề có focus bàn phím; chỗ luôn được giữ. Hover: nền `rowPressed`, icon `textPrimary`. Tooltip `workspaceNewTab` "Tab mới trong workspace này". Bấm → mở tab trong nhóm này (nhóm thu gọn thì tự mở rộng).
- Khoảng trên mỗi tiêu đề 8 (tiêu đề đầu tiên: 4 = `listTop`). Dòng tab đầu tiên ngay dưới tiêu đề cách 2 (`rowGap`).

### 3.2 Trạng thái

| Trạng thái | Nhìn |
|---|---|
| Thường (mở) | nền trong suốt, chevron xuống |
| Thu gọn | chevron sang phải; các dòng của nhóm không vẽ |
| Thu gọn + chứa tab đang chọn | thanh `accent` 3×12 ở mép trái (canh giữa dọc, `r4`), tên `textPrimary` |
| Hover | nền `rowHover`; `+` hiện |
| Nhấn | `rowPressed` |
| Focus bàn phím | vòng 2 px `accent` bên trong `r6` (A1 §3) |
| Đang đổi tên | ô đổi tên thay tên (§4), cao 22, chữ `small` w600 `textTitle`; số tab và `+` ẩn (giữ chỗ) |
| Đích thả | nền `primarySoft`, viền 1 px `accent`, `r6` |

### 3.3 Tương tác

- Bấm một lần (chevron hoặc tên) → bật/tắt thu gọn. **Double-click tên** → đổi tên (lần bấm đầu của double-click không thu gọn: dùng `onDoubleTap` + `onTap` của cùng `GestureDetector`, Flutter chỉ gọi `onTap` khi không có lần bấm thứ hai trong `kDoubleTapTimeout`).
- Chuột phải / Shift+F10 / phím Menu → menu tiêu đề (§5.2).
- Thu gọn nhóm chứa tab đang chọn: terminal **không đổi**; ⌘1–9, Ctrl+Tab bỏ qua các tab bị ẩn.
- Workspace "hiện tại" = workspace của tab đang chọn; nếu không có tab nào: workspace vừa tạo, hoặc Mặc định. Tab mới (⌘T, `+` trên đầu sidebar) mở vào workspace hiện tại; `+` trên tiêu đề mở vào nhóm đó.

### 3.4 Nhóm trống (mở rộng, 0 tab)

Một dòng gợi ý 30 cao dưới tiêu đề, lề trái 32, `caption` `textSecondary`: `workspaceEmptyHint` "Trống. Kéo tab vào đây hoặc bấm +." Không tương tác, không phải điểm dừng tab; là **đích thả** (nền `primarySoft` + viền `accent` khi đang rê tab trên nó). Semantics: chỉ đọc qua nhãn tiêu đề ("0 tab").

---

## 4. Ô đổi tên tại chỗ (tab và workspace)

- Mở bằng: double-click dòng tab / tên workspace; F2 khi danh sách có focus (trên dòng hoặc tiêu đề); menu "Đổi tên tab" / "Đổi tên workspace"; ⌘⇧N (ô tên của workspace mới).
- Hình: cao 22, nền `surfaceInset`, viền 1 px `accent`, `r4`, padding 0/4 (chữ canh giữa dọc), con trỏ `accent`. Tab: chữ `body` `textTitle`; workspace: `small` w600 `textTitle`. Rộng = chỗ của tên (dòng tab: từ sau ô chấm tới trước các dấu điện thoại; tiêu đề: từ sau chevron tới trước số tab).
- Mở ra: chữ hiện tại được **chọn hết** (tab: tên đang hiển thị, kể cả tên tự động).
- Enter / Numpad Enter → lưu; **mất focus → lưu**; Esc → huỷ. Sau đó bàn phím về chỗ cũ (danh sách nếu mở từ danh sách, terminal nếu mở từ chuột hoặc ⌘⇧N).
- Tối đa 64 ký tự (`maxLength`, không hiện bộ đếm). Cắt khoảng trắng hai đầu.
- Tab: rỗng → về tên tự động (OSC hoặc `<shell> <index>`). Workspace: rỗng → giữ tên cũ.
- Trong lúc sửa, phím tắt cửa sổ có chữ cái (⌘A, ⌘C, ⌘V) thuộc về ô sửa (chọn tất cả/sao chép/dán trong ô) — ô sửa nằm trong `Shortcuts` riêng chặn các intent đó; ⌘T, ⌘W, ⌘1–9 vẫn chạy (lưu ô trước).
- Semantics: `TextField` có nhãn `tabNameField` "Tên tab" / `workspaceNameField` "Tên workspace".

---

## 5. Menu ngữ cảnh

Hình menu A1 §3.1 (`surface`, `r8`, mục 28 cao, gợi ý phím `caption` phải). **Mới:** vạch ngăn 1 px `line`, cách trên/dưới 4 (`ShellxMenuEntry.dividerBefore`). Mục mờ giữ chỗ (38 %).

### 5.1 Menu dòng tab

| Mục (vi / en) | Gợi ý phím | Khi nào |
|---|---|---|
| Đổi tên tab / Rename tab | `F2` | luôn |
| Dùng tên tự động / Use automatic name | — | chỉ khi có tên tuỳ chỉnh |
| — vạch — | | |
| Chuyển tới workspace… / Move to workspace… | — | luôn (mở menu thứ hai, §5.3) |
| Chuyển lên / Move up | `⌥↑` / `Alt+↑` | mờ khi đã ở đầu thứ tự nhìn thấy |
| Chuyển xuống / Move down | `⌥↓` / `Alt+↓` | mờ khi ở cuối |
| — vạch — (chỉ khi có cổng) | | |
| Mở cổng 3000 trong trình duyệt / Open port 3000 in browser | — | một mục mỗi cổng, tối đa 5 cổng nhỏ nhất |
| — vạch — | | |
| Đóng tab / Close tab | `⌘W` / `Ctrl+Shift+W` | luôn (A1, quy tắc D15) |

### 5.2 Menu tiêu đề workspace

| Mục | Gợi ý | Khi nào |
|---|---|---|
| Tab mới trong workspace này / New tab in this workspace | — | luôn |
| Đổi tên workspace / Rename workspace | `F2` | luôn |
| Thu gọn / Collapse — hoặc — Mở rộng / Expand | `←` / `→` | theo trạng thái |
| — vạch — | | |
| Xóa workspace / Delete workspace | — | mờ với Mặc định |

### 5.3 Menu "Chuyển tới workspace…"

Mở tại cùng vị trí menu trước. Mục: mọi workspace **trừ** nhóm hiện tại của tab, theo thứ tự sidebar (tên đầy đủ, ellipsis ở 280 px); vạch; "Workspace mới" / "New workspace" (`⌘⇧N` / `Ctrl+Shift+N`) → tạo workspace (D15, không mở thêm tab) rồi chuyển tab vào đó và mở ô đổi tên. Tab được chuyển vào **cuối** nhóm đích; nhóm đích thu gọn thì tự mở rộng; tab vẫn được chọn.

---

## 6. Kéo thả

- **Bắt đầu:** nhấn giữ chuột trái trên dòng tab và di > 4 px (`Draggable` với `affinity: null`, nút trái). Bấm thường vẫn là chọn tab (A1). Không kéo được tiêu đề workspace trong A2 (sắp xếp workspace: dùng thứ tự tạo; follow-up).
- **Bóng kéo (feedback):** bản sao dòng rộng 208, nền `rowSelected`, viền 1 px `border`, `r6`, `e1`, độ đục 92 %; nguồn ở chỗ cũ 38 %. Con trỏ `grabbing`.
- **Vạch chỗ thả:** 2 px `accent`, bo 1, rộng bằng dòng (lề 6), nằm **giữa khe 2 px** giữa hai dòng (trên dòng đầu: sát dưới tiêu đề; dưới dòng cuối: sát dưới dòng cuối). Nửa trên dòng → thả trước dòng; nửa dưới → thả sau.
- **Rê trên tiêu đề:** tiêu đề thành đích thả (§3.2); thả → vào cuối nhóm. Nhóm thu gọn: rê 600 ms → tự mở rộng (giảm chuyển động: vẫn mở, không hoạt ảnh).
- **Nhóm trống:** dòng gợi ý là đích thả.
- **Tự cuộn:** con trỏ trong 32 px mép trên/dưới danh sách → cuộn 240 px/s.
- **Huỷ:** thả ngoài sidebar hoặc ngoài mọi đích → không đổi gì, bóng biến mất ngay (`Draggable` mặc định; không có hoạt ảnh bay về trong A2). Esc trong lúc kéo: không hỗ trợ trong A2 (Flutter `Draggable` không có huỷ bằng phím; follow-up).
- **Thả:** đổi chỗ ngay, không hoạt ảnh (A1: chèn/chọn dòng tức thì). Tab vẫn được chọn nếu đang được chọn; không chọn tab khác.
- **Một sidebar, một workspace:** khi chỉ có Mặc định (không tiêu đề), kéo thả vẫn sắp xếp lại các dòng (D18).

---

## 7. Copy (vi + en, khoá ARB)

Giọng văn A1 §5. "workspace", "tab" giữ tiếng Anh (D13). Dấu "…" chỉ khi mục mở thêm một bước.

| Khoá | vi | en |
|---|---|---|
| `workspaceDefaultName` | Mặc định | Default |
| `workspaceNumberedName` | Workspace {n} | Workspace {n} |
| `workspaceNew` | Workspace mới | New workspace |
| `workspaceNewTab` | Tab mới trong workspace này | New tab in this workspace |
| `workspaceRename` | Đổi tên workspace | Rename workspace |
| `workspaceDelete` | Xóa workspace | Delete workspace |
| `workspaceCollapse` | Thu gọn | Collapse |
| `workspaceExpand` | Mở rộng | Expand |
| `workspaceEmptyHint` | Trống. Kéo tab vào đây hoặc bấm +. | Empty. Drag a tab here or press +. |
| `workspaceNameField` | Tên workspace | Workspace name |
| `workspaceDeleted` | Đã xóa workspace “{name}”. Các tab đã chuyển về {defaultName}. | Deleted workspace “{name}”. Its tabs moved to {defaultName}. |
| `workspaceHeaderSemantics` | Workspace {name}, {count} tab | Workspace {name}, {count, plural, =1{1 tab} other{{count} tabs}} |
| `workspaceContainsSelected` | có tab đang chọn | contains the selected tab |
| `tabRename` | Đổi tên tab | Rename tab |
| `tabNameField` | Tên tab | Tab name |
| `tabUseAutomaticName` | Dùng tên tự động | Use automatic name |
| `tabMoveTo` | Chuyển tới workspace… | Move to workspace… |
| `tabMoveUp` | Chuyển lên | Move up |
| `tabMoveDown` | Chuyển xuống | Move down |
| `tabOpenPort` | Mở cổng {port} trong trình duyệt | Open port {port} in browser |
| `portOpenTooltip` | Mở http://localhost:{port} | Open http://localhost:{port} |
| `portsMoreTooltip` | Cổng đang nghe: {ports} | Listening ports: {ports} |
| `portOpenFailed` | Không mở được trình duyệt. | Couldn't open the browser. |
| `sidebarBranch` | nhánh {branch} | branch {branch} |
| `sidebarFolder` | thư mục {path} | folder {path} |
| `sidebarPorts` | {count, plural, other{cổng {ports}}} | {count, plural, =1{port {ports}} other{ports {ports}}} |
| `sidebarPositionInWorkspace` | tab {index} trên {count} trong {workspace} | tab {index} of {count} in {workspace} |

- `{ports}` là danh sách số nối bằng ", " (không có dấu `:`), ví dụ "3000, 5173".
- `workspaceHeaderSemantics` vi không chia số nhiều (tiếng Việt không biến đổi); vẫn khai báo `count` là `int` trong `@` metadata.
- Tooltip `+` đầu sidebar (A1 `terminalNewTabTooltip`) **không đổi**; phím ⌘⇧N được nhắc ở mục "Workspace mới" của menu §5.3.

---

## 8. Trợ năng

- **Dòng tab:** nhãn A1 §3.7 mở rộng, các phần nối bằng ", ": tiêu đề · trạng thái · [nhánh X] · [thư mục Y] · [cổng …] · [gốc điện thoại] · [điện thoại xem/dùng] · vị trí. Thư mục đọc dạng đầy đủ đã thay `~` (không cắt). Vị trí: có tiêu đề nhóm → `sidebarPositionInWorkspace` (vị trí trong nhóm); không → A1 `sidebarPosition`. Ví dụ vi: "claude, đang chạy lệnh, nhánh main, thư mục ~/work/shellx, cổng 3000, 5173, tab 2 trên 3 trong Backend".
- **Custom actions của dòng:** "Đóng tab" (A1), "Đổi tên tab", "Chuyển tới workspace…", "Chuyển lên", "Chuyển xuống" (chỉ khi làm được), mỗi cổng "Mở cổng N trong trình duyệt".
- **Tiêu đề nhóm:** `Semantics(header: true, button: true, expanded: !collapsed, label: workspaceHeaderSemantics [+ ", " + workspaceContainsSelected])`, `onTap` = bật/tắt thu gọn; custom actions "Đổi tên workspace", "Tab mới trong workspace này", "Xóa workspace" (trừ Mặc định).
- **Cổng, chevron, `+` tiêu đề, dòng gợi ý:** `ExcludeSemantics` (đã có trong nhãn/hành động của dòng hoặc tiêu đề) — giống dấu và chấm A1.
- **Kéo thả (WCAG 2.5.7):** mọi kết quả kéo đều làm được bằng một cú bấm (menu §5.1/§5.3) và bằng bàn phím (⌥↑/⌥↓, menu). Thông báo sau khi chuyển: `SemanticsService.announce` tên tab + nhãn vị trí mới (live, một lần).
- **Bàn phím (D14):** danh sách vẫn là **một điểm dừng tab**. Khi có tiêu đề: ↑/↓ đi qua tiêu đề + dòng nhìn thấy; Home/End; ←: trên dòng → về tiêu đề nhóm, trên tiêu đề mở → thu gọn; →: trên tiêu đề thu gọn → mở rộng, trên tiêu đề mở → dòng đầu; Enter/Space: dòng → về terminal (A1), tiêu đề → bật/tắt; F2 đổi tên; Shift+F10/Menu; ⌥↑/⌥↓ (Windows Alt+↑/↓) chuyển tab đang chọn; Esc → terminal. Không có tiêu đề: đúng hành vi A1 + F2 + ⌥↑/⌥↓.
- **Tương phản:** bảng §1.1, mọi chữ ≥ 4.72:1, thành phần không phải chữ ≥ 3:1.
- **Giảm chuyển động:** xoay chevron, hover cổng → `Duration.zero` (`ShellxMotion.of`). Tự cuộn khi kéo vẫn chạy (chức năng, không trang trí).
- **Mục tiêu bấm:** cổng 24 cao (bề rộng chữ `:3000` ≈ 30 px + 4 đệm ≥ 24), chevron 20×28 (vùng = cả tiêu đề 28 cao), `+` tiêu đề 24×24.

---

## 9. Wireframe

### 9.1 Ba workspace, tab 2 đang chọn (macOS)

```
┌────────────────────────┬──────────────────────────────────────────────────┐
│ ● ● ●              [+] │                     claude                       │
│ ▾ Mặc định           1 │                                                  │
│  ● zsh 1               │ richard@mbp shellx % claude                      │
│    ~                   │ ╭─────────────────────────────────╮              │
│ ▾ Backend            2 │ │ ✻ Welcome to Claude Code        │              │
│ ▌◉ claude          ×   │ ╰─────────────────────────────────╯              │
│    main · ~/work/shellx│                                                  │
│  ● api       📱        │                                                  │
│    dev · ~/w/api · :8080 :9229                                            │
│ ▸ Frontend           3 │                                                  │
└────────────────────────┴──────────────────────────────────────────────────┘
 ▾/▸ chevron · số tab phải · dòng 2: caption textSecondary, cổng accent
 Dòng "api" thật ra: "dev · ~/w/api · :8080 :9229" cắt vừa 168 px (vẽ tràn ở đây chỉ để minh hoạ)
```

### 9.2 Bố trí khi chật (168 px)

```
 main · ~/work/shellx/apps/desktop                → main · ~/…/apps/desktop
 feat/mobile-ui-pass · ~/w/shellx · :3000         → feat/mobile-u… · ~/w/shellx · :3000
 main · ~/w/x · :3000 :5173 :8080 :9229 :24678    → main · ~/w/x · :3000 :5173 :8080 +2
 a-very-long-branch-name · ~/deep/path · :3000 :4000 :5000 :6000
                                                  → a-very-l… · ~/…/path · :3000 :4000 +2
```

### 9.3 Kéo tab "api" vào Frontend (thu gọn)

```
│ ▾ Backend            2 │
│ ▌◉ claude          ×   │
│    main · ~/work/shellx│
│  ░ api (38 %)          │   ← nguồn mờ tại chỗ
│┏━━━━━━━━━━━━━━━━━━━━━━┓│
│┃▸ Frontend          3 ┃│   ← đích thả: primarySoft + viền accent; rê 600 ms → mở rộng
│┗━━━━━━━━━━━━━━━━━━━━━━┛│
│   ╭──────────────────╮ │
│   │ ● api   📱       │ │   ← bóng kéo, e1, 92 %
│   ╰──────────────────╯ │
```

Sau khi Frontend mở rộng, vạch thả 2 px `accent` giữa hai dòng:

```
│ ▾ Frontend           3 │
│  ● web                 │
│ ━━━━━━━━━━━━━━━━━━━━━━ │   ← thả ở đây: giữa "web" và "storybook"
│  ● storybook           │
```

### 9.4 Đổi tên tab tại chỗ

```
│ ▌● ┌──────────────────┐   │
│    │claude▮           │   │   ← ô 22 cao, surfaceInset, viền accent, chữ đã chọn hết
│    └──────────────────┘   │
│    main · ~/work/shellx   │
```

### 9.5 Nhóm trống + tiêu đề có focus bàn phím

```
│ ┏━━━━━━━━━━━━━━━━━━━━━━┓ │
│ ┃▾ Ops              0 [+]┃ │  ← vòng focus 2 px accent; `+` hiện khi focus
│ ┗━━━━━━━━━━━━━━━━━━━━━━┛ │
│    Trống. Kéo tab vào đây hoặc bấm +.
```

### 9.6 Menu dòng tab (có hai cổng, tên tuỳ chỉnh)

```
 ╭──────────────────────────────────────────╮
 │ Đổi tên tab                          F2  │
 │ Dùng tên tự động                         │
 │──────────────────────────────────────────│
 │ Chuyển tới workspace…                    │
 │ Chuyển lên                           ⌥↑  │
 │ Chuyển xuống                         ⌥↓  │
 │──────────────────────────────────────────│
 │ Mở cổng 3000 trong trình duyệt           │
 │ Mở cổng 5173 trong trình duyệt           │
 │──────────────────────────────────────────│
 │ Đóng tab                             ⌘W  │
 ╰──────────────────────────────────────────╯
```

---

## 10. Nhất quán với mobile (follow-up, không làm trong A2)

1. Mobile hiện `branch · cwd` dưới tên phiên trong danh sách phiên và thanh tab (cùng quy tắc `~` + cắt giữa của §2.3; dùng `caption` của mobile).
2. Đưa hàm `displayPath` / `ellipsizeMiddle` vào gói dùng chung khi có `packages/shellx_design` (A1 §7 follow-up 1).
3. Khi mobile cần cổng: thêm `ports` vào `SessionInfo` theo đúng quy tắc khoá tuỳ chọn của C4.
