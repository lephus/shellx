# ShellX desktop A6 — UI addendum (pane trình duyệt, thanh công cụ, chỉ báo, trang lỗi, cài đặt)

- **Ngày:** 2026-10-07 · **Phạm vi:** A6 của `docs/superpowers/specs/2026-10-07-desktop-browser-a6-design.md` (ràng buộc; quyết định W1–W7, D1–D38). Tài liệu này **thêm** vào UI doc A1 `2026-10-06-shellx-desktop-ui.md` ("A1 §N"), A2 ("A2 §N"), A4 ("A4 §N"), A3 `2026-10-07-shellx-desktop-ui-a3.md` ("A3 §N") và A5 `2026-10-07-shellx-desktop-ui-a5.md` ("A5 §N"); mọi token, kiểu chữ, trạng thái, quy tắc focus và copy của các tài liệu đó vẫn giữ.
- **Nguyên tắc:** cửa sổ vẫn là terminal trước tiên. Thanh công cụ trình duyệt **gọn, tối, cùng họ màu** với đầu pane A3; chỉ nội dung web có màu của trang. Không hoạt ảnh lặp; mở/đóng pane **tức thì** (A3). Tab không có pane trình duyệt trông giống hệt A3.
- **Không có token màu mới.** Mọi màu từ A1 §1.1. Tương phản đo theo WCAG 2.x (đã tính lại cho mọi cặp mới bên dưới).

---

## 1. Token dùng lại và kích thước mới

### 1.1 Màu

| Dùng cho | Token | Trên nền | Tương phản |
|---|---|---|---|
| Nền thanh công cụ | `bgSidebar` `#111B1E` | — | — |
| Nền ô địa chỉ | `surfaceInset` `#0D1315` | — | — |
| Viền ô địa chỉ (thường) | `line` `#243337` | `bgSidebar` | trang trí (1,34); ô nhận diện bằng nền + chữ |
| Viền ô địa chỉ (focus) | `accent` 1 px + halo `primarySoft` 2 px (A1 §3.4) | `bgSidebar` | 10.0 (≥ 3) |
| Chữ URL (không focus) | `textSecondary` `#93A5A9`, host `textPrimary` | `surfaceInset` | 7.31 / 14.0 |
| Chữ URL (đang sửa) | `textPrimary` | `surfaceInset` | 14.0 |
| Gợi ý trống ("Nhập địa chỉ hoặc cổng") | `textPlaceholder` `#6F8186` | `surfaceInset` | 4.6 |
| Lỗi ô ("Không phải địa chỉ web") | `err` `#F07178` | `surfaceInset` | 6.55 |
| Biểu tượng nút (thường) | `textSecondary` | `bgSidebar` / hover `rowHover` | 6.83 / 6.22 |
| Biểu tượng nút (mờ) | `dim` `#6C8288` | `bgSidebar` | trang trí (nút mờ không bấm được, WCAG 1.4.11 ngoại lệ "inactive") |
| Biểu tượng nút (nhấn) | `textPrimary` trên `rowPressed` | — | 9.03 |
| Chỉ báo "trang trên máy này" / ổ khoá | `textSecondary` | `surfaceInset` | 7.31 |
| Chỉ báo "Không bảo mật" (biểu tượng + chữ) | `warn` `#E9C46A` | `surfaceInset` | 11.21 |
| Thanh tiến trình | `accent` `#5FD4E2` | `bgSidebar` | 10.0 (≥ 3) |
| Dấu "Agent" | chữ + biểu tượng `warn` trên `warnBg`, viền `warnBorder` (như dải driver A1 §2.5) | `warnBg` | 9.24 |
| Biểu tượng địa cầu đầu pane | `textSecondary` (không focus) / `textPrimary` (focus); `accent` khi đang tải | `bgSidebar` / `rowSelected` | 6.83 / 11.5 / 7.93 |
| Trang lỗi: nền | `bgTerminal` `#0B1215` | — | — |
| Trang lỗi: tiêu đề / mô tả | `textTitle` / `textSecondary` | `bgTerminal` | ≥ 13 / ≥ 7 |

### 1.2 Kích thước mới (thêm vào `ShellxSizes`)

| Tên | Giá trị | Ghi chú |
|---|---|---|
| `browserToolbar` | 32 | chiều cao thanh công cụ (dưới đầu pane A3 22) |
| `browserToolbarPadH` | 6 | lề ngang |
| `browserButton` | 28 | nút biểu tượng 28×28 (A1 §1.2), glyph 16 |
| `browserButtonGap` | 2 | giữa các nút |
| `browserAddressHeight` | 24 | ô địa chỉ, `r6` |
| `browserAddressPadH` | 8 | lề trong ô |
| `browserOriginIcon` | 14 | chỉ báo origin trong ô |
| `browserProgress` | 2 | thanh tiến trình, dính đáy thanh công cụ (vẽ đè, không chiếm chỗ) |
| `browserMinWidth` | 240 | cỡ tối thiểu pane (spec D31) |
| `browserMinHeight` | 160 | gồm đầu pane + thanh công cụ |
| `browserAgentMark` | 20 | chiều cao dấu "Agent" (`rPill`), lề ngang 8 |
| `browserErrorMaxWidth` | 420 | khối nội dung trang lỗi |

### 1.3 Cỡ chữ lớn

Thanh công cụ cao `max(32, scale(16) + 16)`; ô địa chỉ cao `max(24, scale(16) + 8)`; chữ ô `body` theo `textScaler`; biểu tượng giữ 16.

---

## 2. Pane trình duyệt

### 2.1 Giải phẫu (terminal trái, trình duyệt phải, pane trình duyệt focus)

```
x=221 (sau sidebar)
┌─────────────────────────────────┬┬──────────────────────────────────────────────────┐
│● zsh — ~/work/app           [ ] ││┏🌐━Vite + React━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[×]━┓│ ← đầu pane A3 22: địa cầu thay chấm,
│ ~/work/app % npm run dev        ││┃ ‹  ›  ⟳ │ ⌂ localhost:5173/about        │ ↗ ┃│   tiêu đề trang
│   VITE ready in 312 ms          ││┃▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔┃│ ← thanh công cụ 32, bgSidebar;
│   ➜ Local: http://localhost:5173││┃                                                ┃│   tiến trình 2 px accent ở đáy khi tải
│                                 ││┃         (nội dung web — màu của trang)         ┃│
│                                 ││┃                                                ┃│
└─────────────────────────────────┴┴┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛┘
```

**Thanh công cụ (32):** `|6| ‹ 28 |2| › 28 |2| ⟳/✕ 28 |6| [ô địa chỉ flex] |6| [Agent]? |6| ↗ 28 |6|`

- `‹` lùi `Icons.arrow_back` · `›` tiến `Icons.arrow_forward` · `⟳` tải lại `Icons.refresh`, **đổi thành** `✕` dừng `Icons.close` khi đang tải (cùng chỗ, không nhảy bố cục) · `↗` "Mở trong trình duyệt hệ thống" `Icons.open_in_new`.
- Nút mờ (`dim`, không bấm, vẫn trong thứ tự Tab với `enabled: false` trong Semantics) khi không có lịch sử; `↗` mờ khi URL không phải http/https.
- **Ô địa chỉ (24, `r6`, `surfaceInset`):** `|8| chỉ báo origin 14 |6| URL (body, 1 dòng, cắt giữa) |8|`. Không focus: URL rút gọn để dễ đọc — bỏ scheme cho origin local và secure (chỉ báo đã nói), **giữ** `http://` cho insecure; host `textPrimary`, phần còn lại `textSecondary`; IDN/percent giải mã. Focus: URL đầy đủ, chọn hết, `textPrimary`.
- **Dấu "Agent"** (spec D25): `Icons.smart_toy_outlined` 14 + chữ `caption` w600 "Agent", nền `warnBg`, viền `warnBorder`, `rPill`, cao 20; hiện 10 s sau lệnh agent cuối; tooltip `browserAgentMarkTooltip`. Không là điểm dừng Tab.
- Thanh công cụ không kéo được cửa sổ.

### 2.2 Chỉ báo origin (spec D11)

| Origin | Biểu tượng | Chữ cạnh biểu tượng | Tooltip / nhãn |
|---|---|---|---|
| local | `Icons.computer_outlined` `textSecondary` | — | `browserOriginLocal` |
| secure | `Icons.lock_outline` `textSecondary` | — | `browserOriginSecure` |
| insecure | `Icons.warning_amber_rounded` `warn` | `browserOriginInsecure` (`caption` w600 `warn`, sau biểu tượng 4 px, trước URL 6 px) | `browserOriginInsecure` |
| none (`about:blank`) | không | — | — |

### 2.3 Tiến trình tải (spec D13)

- Thanh 2 px `accent` vẽ đè lên mép dưới thanh công cụ (đè lên vạch `line` nếu có), từ trái, rộng = `progress %` của pane.
- macOS: theo `onProgress`, chuyển tiếp chiều rộng `fast` 80 ms. Windows: 30 % tức thì khi bắt đầu, ẩn ngay khi xong. Giảm chuyển động: không chuyển tiếp.
- Đầu pane: địa cầu chuyển `accent` khi đang tải.

### 2.4 Trạng thái pane

| Trạng thái | Nhìn |
|---|---|
| Focus, nội dung web có bàn phím | Viền focus A3 (1 px `accent`), đầu pane `rowSelected` |
| Focus, thanh công cụ có bàn phím | Như trên + vòng focus A1 trên điều khiển đang focus |
| Không focus | Đầu pane `bgSidebar`; thanh công cụ không đổi |
| Đang tải | Thanh 2 px, nút ⟳ → ✕, địa cầu `accent` |
| Lỗi tải | Trang lỗi §3 thay nội dung web (thanh công cụ vẫn dùng được) |
| Agent đang điều khiển | Dấu "Agent" §2.1 |
| Chờ tải lần đầu (khôi phục, tab chưa hiện) | Nội dung `bgTerminal` trống, URL đã có trong ô; tải khi tab hiện |
| Phóng to (A3) | Như A3 §2.3; đầu pane có "Phóng to · i/n" |

### 2.5 Đầu pane (A3 §2.1, cho pane trình duyệt)

`|8| 🌐 Icons.public 12 trong ô 12 |6| tiêu đề trang (small, flex, ellipsis) |4| [Phóng to · i/n] |4| × 18 |4|`. Không có 📱/👁/chấm chưa đọc (không phải phiên). Tiêu đề: `document.title` → host → `browserUntitled` "Trình duyệt". Cập nhật ≤ 4 lần/s.

---

## 3. Trang lỗi (spec D14)

```
┌──────────────────────────────────────────────────┐
│ ‹  ›  ⟳ │ ⌂ localhost:3000/                │ ↗  │
├──────────────────────────────────────────────────┤
│                                                  │
│        Chưa có gì chạy ở localhost:3000          │ ← textTitle, title (16 w600)
│                                                  │
│   Khởi động server trong terminal (vd.           │ ← textSecondary, body, căn giữa, ≤ 420
│   npm run dev) rồi thử lại.                       │
│                                                  │
│          [ Thử lại ]  [ Mở trong trình duyệt ]   │ ← nút A1 §3.3: primary + secondary
│                                                  │
└──────────────────────────────────────────────────┘
```

- Nền `bgTerminal`; khối giữa theo chiều dọc, rộng tối đa 420, lề 24. Thứ tự nút theo A1 (macOS primary bên phải; Windows primary bên trái).
- Focus: khi lỗi hiện do thao tác bàn phím của người dùng → "Thử lại" nhận focus; do agent → không cướp focus.
- `liveRegion` cho tiêu đề (đọc một lần).

| Loại | Tiêu đề | Mô tả |
|---|---|---|
| `refused` + host local | `browserErrorLocalRefusedTitle` | `browserErrorLocalRefusedBody` |
| `refused`/`unreachable` khác | `browserErrorUnreachableTitle` | `browserErrorUnreachableBody` |
| `dns` | `browserErrorDnsTitle` | `browserErrorDnsBody` |
| `timeout` | `browserErrorTimeoutTitle` | `browserErrorUnreachableBody` |
| `certificate` | `browserErrorCertTitle` | `browserErrorCertBody` (không có nút bỏ qua) |
| `crashed` | `browserErrorCrashedTitle` | `browserErrorCrashedBody`, nút chính "Tải lại" |
| `unavailable` (Windows thiếu WebView2) | `browserErrorRuntimeTitle` | `browserErrorRuntimeBody`; nút chính `browserErrorRuntimeAction` mở `https://developer.microsoft.com/microsoft-edge/webview2/` bằng trình duyệt hệ thống; không có "Thử lại" |
| khác | `browserErrorGenericTitle` | `browserErrorUnreachableBody` |

---

## 4. Lối mở

### 4.1 Phím tắt (gợi ý hiện trong menu/tooltip)

| Hành động | macOS | Windows | Phạm vi |
|---|---|---|---|
| Mở pane trình duyệt (chia phải) | ⌘⇧B | Ctrl+Shift+Alt+B (Alt trái) | toàn cửa sổ |
| Focus ô địa chỉ | ⌘L | Ctrl+L | pane trình duyệt focus |
| Tải lại | ⌘R | Ctrl+R, F5 | pane trình duyệt focus |
| Lùi / Tiến | ⌘[ / ⌘] | Alt+← / Alt+→ | pane trình duyệt focus |
| Dừng | Esc (chỉ khi đang tải) | Esc (chỉ khi đang tải) | pane trình duyệt focus |
| Đóng pane, chuyển pane, chuyển vùng | A3 §5, A1 §3.6 | A3 §5, A1 §3.6 | cả khi nội dung web có focus |

### 4.2 Menu terminal (A3 §4.1)

Thêm sau "Chia xuống dưới": **"Mở pane trình duyệt  ⌘⇧B"**.

### 4.3 Menu dòng tab (A3 §4.2)

Trong nhóm chia, sau "Chia xuống dưới": "Mở pane trình duyệt" (`⌘⇧B`). Nhóm cổng A2 (A2 §5.1: "Mở cổng {port} trong trình duyệt") thêm mục song song theo cùng quy tắc A2 V12: một hoặc hai cổng → mỗi cổng một mục `browserOpenPortInPane` "Mở :{port} trong pane trình duyệt" ngay sau mục A2 của cổng đó; từ 3 cổng → một mục `browserOpenPortInPaneMenu` "Mở cổng trong pane trình duyệt…" mở menu con (tối đa 5 cổng nhỏ nhất, mỗi mục `browserOpenPortInPane`).

### 4.4 Cổng trên dòng sidebar (A2)

- Bấm: như A2 (trình duyệt hệ thống). ⌥-click (Windows Alt+click): pane trình duyệt (spec D8).
- Con trỏ khi giữ ⌥ trên cổng: vẫn `click`. Tooltip cổng hai dòng: dòng A2 + `browserPortAltClickHint` "⌥-click: mở trong pane trình duyệt" (Windows "Alt+click: …").

### 4.5 Menu chuột phải trên đầu pane / thanh công cụ trình duyệt

```
 ╭──────────────────────────────────────────╮
 │ Sao chép địa chỉ trang                   │
 │ Mở trong trình duyệt hệ thống            │
 │──────────────────────────────────────────│
 │ Chia sang phải                       ⌘D  │  ← A3 (pane mới là terminal)
 │ Chia xuống dưới                     ⌘⇧D  │
 │ Phóng to pane                       ⌘⇧↩  │
 │ Cân bằng pane                       ⌘⌃=  │
 │──────────────────────────────────────────│
 │ Đóng pane                            ⌘W  │
 ╰──────────────────────────────────────────╯
```

---

## 5. Cài đặt (tray, spec D27)

```
ShellX ▸ … ▸ Terminal ▸ (A5a)
          ▸ Trình duyệt ▸ ☐ Giữ dữ liệu trình duyệt (cookie, đăng nhập)
                          ☐ Cho phép agent điều khiển mọi trang
                          ─────────────
                          Xóa dữ liệu trình duyệt
          ▸ Thông báo ▸ (A4)
```

- Windows, đổi "Giữ dữ liệu": thông báo trung tính một lần (toast A1 trên cửa sổ nếu hiện, không thì thông báo hệ thống) `browserKeepDataRestartNote`.
- "Xóa dữ liệu trình duyệt": xoá ngay (macOS; Windows xoá thư mục `profile` và đánh dấu tải lại các pane) → toast `browserDataCleared`.
- Bật "Cho phép agent điều khiển mọi trang" → hộp xác nhận (A1 §4 confirm ngắn 400, phá huỷ = không; nút chính bình thường, focus ban đầu "Hủy"):

```
╭────────────────────────────────────────────────╮
│ Cho phép agent điều khiển mọi trang?           │
│                                                │
│ Agent trên máy này (qua dòng lệnh ShellX) sẽ   │
│ chạy được JavaScript, chụp ảnh và đọc console  │
│ của mọi trang trong pane trình duyệt — kể cả   │
│ trang bạn đã đăng nhập. Chỉ bật khi bạn tin    │
│ các agent đang chạy.                           │
│                                   [Hủy] [Bật]  │
╰────────────────────────────────────────────────╯
```

---

## 6. Bàn phím và focus (sửa A1 §3.6, A3 §6)

- Vòng vùng (Ctrl+F6 / Ctrl+Shift+F6; F6 khi ngoài terminal **và** ngoài nội dung web): **1** pane focus (terminal hoặc nội dung web) → **1b** thanh công cụ trình duyệt (chỉ khi pane focus là trình duyệt; vào ô địa chỉ) → **2** sidebar → **3** dải đăng nhập. Ngược lại theo chiều ngược.
- Trong thanh công cụ: Tab/Shift+Tab: ‹ › ⟳ ô ↗ (dấu Agent không dừng). Enter trên nút = bấm. Esc ở bất kỳ điều khiển nào của thanh công cụ → nội dung web.
- Ô địa chỉ: ⌘L/Ctrl+L vào ô (chọn hết); Enter điều hướng → nội dung web; Esc trả URL → nội dung web; lỗi D9 → không thêm dòng chữ dưới ô (thanh công cụ không đổi cao): ô có viền `err` 1 px, tooltip lỗi hiện ngay 3 s, đọc lên `browserAddressInvalid`; chữ người dùng gõ giữ nguyên.
- Mở pane bằng ⌘⇧B: có URL → nội dung web nhận focus; `about:blank` → ô địa chỉ. Mở do ⌥-click → nội dung web. Mở do agent (A7) → không đổi focus.
- Hộp thoại/menu đóng → focus về chỗ cũ (nội dung web hoặc điều khiển thanh công cụ).

---

## 7. Copy (vi + en, khoá ARB)

"pane", "tab", "Agent" giữ tiếng Anh (A3 §7). Phím trong `{shortcut}` từ nền tảng.

| Khoá | vi | en |
|---|---|---|
| `browserOpenPane` | Mở pane trình duyệt | Open browser pane |
| `browserOpenPortInPane` | Mở :{port} trong pane trình duyệt | Open :{port} in a browser pane |
| `browserOpenPortInPaneMenu` | Mở cổng trong pane trình duyệt… | Open port in a browser pane… |
| `browserPortAltClickHint` | {modifier}-click: mở trong pane trình duyệt | {modifier}-click: open in a browser pane |
| `browserBack` | Lùi  {shortcut} | Back  {shortcut} |
| `browserForward` | Tiến  {shortcut} | Forward  {shortcut} |
| `browserReload` | Tải lại  {shortcut} | Reload  {shortcut} |
| `browserStop` | Dừng  Esc | Stop  Esc |
| `browserOpenExternal` | Mở trong trình duyệt hệ thống | Open in system browser |
| `browserCopyAddress` | Sao chép địa chỉ trang | Copy page address |
| `browserAddressLabel` | Địa chỉ trang | Page address |
| `browserAddressHint` | Nhập địa chỉ hoặc cổng | Enter an address or port |
| `browserAddressInvalid` | Không phải địa chỉ web | Not a web address |
| `browserOriginLocal` | Trang trên máy này | Page on this computer |
| `browserOriginSecure` | Kết nối bảo mật | Secure connection |
| `browserOriginInsecure` | Không bảo mật | Not secure |
| `browserUntitled` | Trình duyệt | Browser |
| `browserLoadingLabel` | Đang tải | Loading |
| `browserAgentMark` | Agent | Agent |
| `browserAgentMarkTooltip` | Một agent trên máy này đang điều khiển trang | An agent on this computer is controlling this page |
| `browserAnnounceAgent` | Agent đang điều khiển pane trình duyệt | An agent is controlling the browser pane |
| `browserAnnounceLoaded` | Đã tải {title} | Loaded {title} |
| `browserPaneRegionLabel` | Pane {index} trên {count} — Trình duyệt: {title} | Pane {index} of {count} — Browser: {title} |
| `browserToolbarRegionLabel` | Thanh công cụ trình duyệt | Browser toolbar |
| `browserSchemeBlocked` | Pane trình duyệt chỉ mở trang http và https | The browser pane only opens http and https pages |
| `browserDownloadBlocked` | Pane trình duyệt không tải file xuống — dùng “Mở trong trình duyệt hệ thống” | The browser pane doesn’t download files — use “Open in system browser” |
| `browserLimitReached` | Đã đạt tối đa {count} pane trình duyệt | You’ve reached the maximum of {count} browser panes |
| `browserErrorLocalRefusedTitle` | Chưa có gì chạy ở {host} | Nothing is running at {host} |
| `browserErrorLocalRefusedBody` | Khởi động server trong terminal (vd. npm run dev) rồi thử lại. | Start the server in a terminal (for example npm run dev), then try again. |
| `browserErrorUnreachableTitle` | Không kết nối được tới {host} | Can’t reach {host} |
| `browserErrorUnreachableBody` | Kiểm tra địa chỉ và kết nối mạng rồi thử lại. | Check the address and your network, then try again. |
| `browserErrorDnsTitle` | Không tìm thấy {host} | Can’t find {host} |
| `browserErrorDnsBody` | Tên miền không tồn tại hoặc mạng chưa sẵn sàng. | The domain doesn’t exist or the network isn’t ready. |
| `browserErrorTimeoutTitle` | {host} phản hồi quá lâu | {host} took too long to respond |
| `browserErrorCertTitle` | Kết nối tới {host} không an toàn | The connection to {host} isn’t secure |
| `browserErrorCertBody` | Chứng chỉ của trang không hợp lệ. ShellX không mở trang này; bạn có thể mở trong trình duyệt hệ thống. | The site’s certificate isn’t valid. ShellX won’t open this page; you can open it in your system browser. |
| `browserErrorCrashedTitle` | Trang đã dừng bất ngờ | The page stopped unexpectedly |
| `browserErrorCrashedBody` | Tải lại để mở lại trang. | Reload to open the page again. |
| `browserErrorRuntimeTitle` | Cần Microsoft Edge WebView2 Runtime | Microsoft Edge WebView2 Runtime is required |
| `browserErrorRuntimeBody` | Pane trình duyệt dùng WebView2 của Windows. Cài WebView2 Runtime rồi mở lại pane. | The browser pane uses Windows WebView2. Install the WebView2 Runtime, then open the pane again. |
| `browserErrorRuntimeAction` | Tải WebView2 | Get WebView2 |
| `browserErrorGenericTitle` | Không mở được trang | Can’t open the page |
| `browserErrorRetry` | Thử lại | Try again |
| `browserTrayMenu` | Trình duyệt | Browser |
| `browserTrayKeepData` | Giữ dữ liệu trình duyệt (cookie, đăng nhập) | Keep browser data (cookies, sign-ins) |
| `browserTrayAgentAllOrigins` | Cho phép agent điều khiển mọi trang | Let agents control any page |
| `browserTrayClearData` | Xóa dữ liệu trình duyệt | Clear browser data |
| `browserKeepDataRestartNote` | Thay đổi có hiệu lực khi mở lại ShellX. | The change takes effect when you reopen ShellX. |
| `browserDataCleared` | Đã xóa dữ liệu trình duyệt | Browser data cleared |
| `browserConfirmAllOriginsTitle` | Cho phép agent điều khiển mọi trang? | Let agents control any page? |
| `browserConfirmAllOriginsBody` | Agent trên máy này (qua dòng lệnh ShellX) sẽ chạy được JavaScript, chụp ảnh và đọc console của mọi trang trong pane trình duyệt — kể cả trang bạn đã đăng nhập. Chỉ bật khi bạn tin các agent đang chạy. | Agents on this computer (through the ShellX command line) will be able to run JavaScript, take screenshots and read the console of any page in a browser pane — including pages you’re signed in to. Only turn this on if you trust the agents you run. |
| `browserConfirmAllOriginsAction` | Bật | Turn on |
| `browserDialogTitle` | {host} cho biết | {host} says |

- `port`, `count`, `index` là `int`. `modifier` là "⌥" (macOS) / "Alt" (Windows).

---

## 8. Trợ năng

- **Pane:** `Semantics(container, label: browserPaneRegionLabel)` bọc đầu pane + thanh công cụ + nội dung; nội dung web là platform view/texture — engine cung cấp cây trợ năng (macOS VoiceOver đọc được; Windows: không, spec D2 — HANDOFF ghi rõ, "Mở trong trình duyệt hệ thống" là lối thay thế).
- **Thanh công cụ:** `Semantics(container, label: browserToolbarRegionLabel)`; mỗi nút `button`, nhãn không có phím (phím chỉ trong tooltip), `enabled` đúng trạng thái; ô địa chỉ `textField` nhãn `browserAddressLabel`, giá trị = URL đầy đủ; chỉ báo origin nhãn §2.2 (không `ExcludeSemantics`: đây là thông tin an toàn); thanh tiến trình `Semantics(label: browserLoadingLabel, value: "{n} %")` (Windows: không có giá trị); dấu Agent nhãn `browserAgentMarkTooltip`.
- **Đọc lên** (lịch sự): `browserAnnounceLoaded` khi điều hướng do người dùng xong; tiêu đề trang lỗi; `browserAnnounceAgent` (≤ 1 lần / 60 s); `browserAddressInvalid`; toast D10/D28 theo A1.
- **Tương phản:** §1.1 — chữ ≥ 4.6:1, thành phần không phải chữ ≥ 3:1.
- **Mục tiêu bấm:** nút 28×28 (≥ 24, WCAG 2.5.8); ô địa chỉ cao 24 rộng flex.
- **Giảm chuyển động:** thanh tiến trình không chuyển tiếp.
- **Bàn phím:** mọi thao tác thanh công cụ có phím hoặc nằm trong thứ tự Tab; mở pane có phím + menu; ⌥-click cổng có mục menu dòng thay thế (WCAG 2.1.1).

---

## 9. Wireframe

### 9.1 Pane trình duyệt không bảo mật, agent đang điều khiển (Windows)

```
┌─────────────────────────────────────────────────────────────────┐
│ 🌐 Example Domain                                          [×]  │
│ ‹  ›  ⟳ │ ⚠ Không bảo mật  http://example.com/   │[🤖 Agent]│ ↗ │
├─────────────────────────────────────────────────────────────────┤
│                         Example Domain                          │
```

### 9.2 Ô địa chỉ khi sửa, lỗi

```
│ ‹  ›  ⟳ │┃hello world                         ┃│ ↗ │   ← viền err 1 px; tooltip "Không phải địa chỉ web"
```

### 9.3 Ba pane: terminal | (trình duyệt / terminal), trình duyệt phóng to

```
┌───────────────────────────────────────────────────────────────────┐
│ 🌐 Storybook                          Phóng to · 2/3          [×] │
│ ‹  ›  ✕ │ ⌂ localhost:6006/?path=/story/button                │ ↗ │
│▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔                                         │ ← tiến trình 45 %
```

---

## 10. Nhất quán với mobile

Không đổi (spec D30). Hiển thị pane trình duyệt trên điện thoại cần protocol mới — sau A7.
