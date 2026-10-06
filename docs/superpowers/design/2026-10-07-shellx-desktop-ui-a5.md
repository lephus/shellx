# ShellX desktop A5 — UI addendum (khôi phục phiên, vạch khôi phục, cài đặt, đóng bất thường, phiên nền)

- **Ngày:** 2026-10-07 · **Phạm vi:** A5a (`docs/superpowers/specs/2026-10-07-desktop-restore-a5a-design.md`, R0–R8, D1–D26) và A5b (`docs/superpowers/specs/2026-10-07-desktop-daemon-a5b-design.md`, B1–B9, D1–D30) — cả hai ràng buộc. Tài liệu này **thêm** vào UI doc A1 `2026-10-06-shellx-desktop-ui.md` ("A1 §N"), A2, A4, A3 addendum ("A3 §N"); mọi token, kiểu chữ, trạng thái, quy tắc focus và copy của các tài liệu đó vẫn giữ.
- **Nguyên tắc:** khôi phục phải **gần như vô hình** — người dùng mở app và thấy chỗ làm việc của mình; chỉ có một vạch mờ cho biết đâu là nội dung cũ. Không splash, không thanh tiến trình, không hộp thoại khi mọi thứ ổn. Hộp thoại chỉ khi người dùng **phải chọn** (thoát lần đầu, thoát hoàn toàn, daemon không tương thích, daemon không khởi động được).
- **Không có token màu mới.** Mọi màu từ A1 §1.1. Tương phản đo theo WCAG 2.x.
- Phần §2–§5 thuộc **A5a**; §6–§8 thuộc **A5b**; §9 copy dùng chung (cột "Mốc").

---

## 1. Token dùng lại và kích thước mới

| Dùng cho | Token / giá trị | Trên nền | Tương phản |
|---|---|---|---|
| Vạch khôi phục (chữ) | SGR `2` (mờ) trên màu chữ mặc định terminal `textPrimary` `#D4E1E4` → xterm vẽ với alpha mờ ≈ `#7C8689` | `bgTerminal` `#0B1215` | ≈ 5,0 (≥ 4,5 — mờ nhưng vẫn đọc được) |
| Dải đóng bất thường / dải phiên nền (nền) | `rowSelected` `#1F2F34`, viền dưới 1 px `line` | — | — |
| Chữ dải | `textPrimary` | `rowSelected` | 11,5 |
| Biểu tượng dải (thông tin) | `textSecondary` `Icons.history` 16 | `rowSelected` | 6,0 |
| Biểu tượng dải (lỗi phiên nền) | `err` `Icons.error_outline` 16 | `rowSelected` | 5,1 (≥ 3) |
| Nút chữ trong dải | `accent` `bodyStrong` | `rowSelected` | 7,93 |
| Toast "Không mở lại được n pane" | toast trung tính A1 §2.8 (`rowSelected`, `border`, `textPrimary`) | — | 11,5 |

Kích thước mới (`ShellxSizes`): không có. Dải dùng đúng số đo dải đăng nhập A1 §2.4 (cao 36, lề trái 12, khe 8, nút chữ 28 cao, padding 0/10). Cỡ chữ lớn: cao dải `max(36, scale(18) + 18)`.

---

## 2. Vạch khôi phục trong terminal (A5a D8, D23)

```
│ 4998                                                                   │
│ 4999                                                                   │
│ 5000                                                                   │
│ — Phiên được khôi phục · 14:32 —                                       │  ← SGR 2 (mờ), một dòng, căn trái cột 0
│ ~/work/shellx %  _                                                     │  ← prompt của shell mới
```

- Là **chữ trong buffer xterm**, không phải widget: cuộn cùng nội dung, chọn/sao chép được, theo cỡ chữ terminal, tự gói nếu pane hẹp. Không nền, không viền.
- Byte chính xác: `ESC[0m` `ESC[2m` + `terminalRestoredDivider(time)` + `ESC[0m` + `\r\n`. Dấu gạch là **em dash** U+2014 có khoảng trắng hai bên; dấu chấm giữa là U+00B7.
- Thời gian theo A5a D23: `14:32` / `hôm qua 14:32` / `6/10 14:32` (vi); `14:32` / `yesterday 14:32` / `Oct 6 14:32` (en). Luôn 24 giờ, giờ địa phương lúc lưu nội dung lần cuối.
- Pane không có nội dung cũ → **không** có vạch (pane trông như A3).
- Trình đọc màn hình: vạch là chữ terminal thường; không có thông báo đọc lên riêng cho từng pane (dải §4 hoặc không gì cả).
- Pane nhỏ hơn bề rộng vạch: chữ gói xuống dòng như mọi chữ terminal (chấp nhận).

---

## 3. Cài đặt: submenu tray "Terminal" (A5a D13)

```
Mở cửa sổ terminal
────────────────────────────────────
Terminal                                ▸ ┌───────────────────────────────────────┐
                                          │ ✓ Lưu nội dung terminal khi thoát     │
                                          │ Xóa nội dung đã lưu                   │  (mờ khi chưa có nội dung nào được lưu)
                                          └───────────────────────────────────────┘
Thông báo                               ▸   (A4 §7)
```

- Vị trí: **ngay trước** "Thông báo" (A4 §7) ở **cả** menu đã đăng nhập và chưa đăng nhập.
- Checkbox áp dụng **ngay** (không hỏi). Bỏ chọn → nội dung đã lưu bị xoá ngay; không có toast (tray không có chỗ hiện), menu dựng lại: "Xóa nội dung đã lưu" mờ.
- "Xóa nội dung đã lưu": xoá ngay, **không hỏi** (chỉ xoá bộ nhớ đệm; shell đang chạy không bị ảnh hưởng; nội dung sẽ được lưu lại ở lần lưu sau nếu công tắc bật). Sau khi xoá, mục mờ cho tới lần lưu kế.
- macOS: tray menu là `NSMenu` — dấu ✓ hệ thống. Windows: menu ngữ cảnh — dấu ✓ hệ thống.

---

## 4. Dải "đóng bất thường" (A5a D12, D24)

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ ⟲  ShellX đã đóng bất thường lần trước. Đã mở lại 5 tab; nội dung tính tới 14:31.  Đóng │  ← cao 36, rowSelected, viền dưới line
├──────────────────────────────────────────────────────────────────────────────────┤
│ (terminal)                                                                        │
```

- Vị trí: đầu vùng terminal, **dưới** dải đăng nhập A1 §2.4 nếu cả hai cùng hiện (dải đăng nhập trên, dải này dưới). Là hàng bố cục (đổi cỡ terminal — chấp nhận vì hiện một lần ngay khi mở, trước khi người dùng gõ; giống quy tắc dải đăng nhập A1 §2.3).
- Trái 12: `Icons.history` 16 `textSecondary`, khe 8, chữ `body` `textPrimary` một dòng, cắt cuối (tooltip đầy đủ khi bị cắt). Phải 8: nút chữ "Đóng" (`actionClose`).
- Không có thời gian `{time}` (không có nội dung nào được lưu: công tắc tắt) → dùng biến thể ngắn `restoreAbnormalNoText`.
- Không tự ẩn (WCAG 2.2.1). Đóng: nút "Đóng"; Esc khi focus ở dải. Biến mất bằng fade `exit` 120 ms (giảm chuyển động → tức thì). Focus bàn phím sau khi đóng về terminal.
- Thứ tự Tab: dải nằm **sau** sidebar, **trước** terminal (vùng 0,5 giữa A1 §3.6 vùng 2 và vùng 1); F6 đi qua nó khi hiện.
- `Semantics(liveRegion: true, container: true)`; đọc lên một lần (lịch sự) khi xuất hiện.

---

## 5. Toast khôi phục thiếu pane (A5a D7)

Toast **trung tính** A1 §2.8, một lần sau khi khôi phục xong: `restorePanesFailed` "Không mở lại được {count} pane" (số nhiều). Hiện 4 s (A1 `toast`). Không có nút hành động.

---

## 6. Menu ứng dụng và tray: hai kiểu thoát (A5b D14)

### 6.1 macOS — menu ứng dụng (hiện khi icon Dock hiện, A1 D10)

```
ShellX
  Giới thiệu ShellX
  ───────────────
  Ẩn ShellX                         ⌘H
  ───────────────
  Thoát ShellX                      ⌘Q     ← chỉ thoát giao diện (shell vẫn chạy)
  Thoát hoàn toàn                  ⌥⌘Q     ← dừng mọi shell và phiên nền
```

- "Thoát hoàn toàn" là mục thường (không phải mục "alternate" ẩn sau ⌥): luôn nhìn thấy. Phím ⌥⌘Q thay hành vi mặc định "Quit and Keep Windows" của macOS (ShellX không dùng tính năng khôi phục cửa sổ của AppKit).

### 6.2 Tray (cả hai hệ điều hành, cả menu đã/chưa đăng nhập)

```
…
────────────────────────────────────
Thoát                                   ← thoát giao diện, shell vẫn chạy
Thoát hoàn toàn                         ← dừng mọi shell và phiên nền
```

- Windows: không có phím tắt cho "Thoát hoàn toàn" (tray và menu ngữ cảnh). Ctrl+Shift+Q không gán.
- Tooltip không có (menu hệ thống).

---

## 7. Hộp thoại phiên nền (A5b)

Mọi hộp: container A1 §4 (`surface`, `r12`, `e2`, padding 24, rộng 440), tiêu đề `dialogTitle`, thân `dialogBody` `textDialog2`, hàng nút theo A1 §4 (macOS `[phụ] [chính]`, Windows `[chính] [phụ]`). Esc = nút phụ (trừ §7.4). Một hộp tại một thời điểm (A1 `WindowRouter`).

### 7.1 Thoát lần đầu khi còn phiên (D14) — một lần duy nhất

```
┌──────────────────────────────────────────────────────┐
│ Shell vẫn chạy sau khi thoát                          │
│                                                      │
│ 3 tab vẫn chạy nền và điện thoại vẫn kết nối được.   │
│ Mở lại ShellX để quay về đúng chỗ. Muốn dừng mọi     │
│ shell, chọn Thoát hoàn toàn (⌥⌘Q).                   │
│                                                      │
│                          [Thoát hoàn toàn] [Thoát]   │
└──────────────────────────────────────────────────────┘
```

- Nút chính (mặc định, Enter): **"Thoát"** (`quitUiAction`). Nút phụ: **"Thoát hoàn toàn"** — kiểu Secondary (không destructive: bước kế tiếp của nó có hộp xác nhận A1 riêng nếu còn phiên). Esc = huỷ (ở lại).
- Không có ô "Không hỏi lại": hộp chỉ hiện **một lần** (khoá UI `quit_keeps_sessions_explained` đặt `true` khi hộp đóng bằng "Thoát" hoặc "Thoát hoàn toàn"; Esc không đặt).
- Windows: thân thay "(⌥⌘Q)" bằng "(trong menu khay hệ thống)" — chuỗi riêng `quitUiExplainedBodyWindows`.
- Không còn phiên nào → không có hộp; ⌘Q thoát ngay.

### 7.2 Thoát hoàn toàn (D14)

Hộp xác nhận A1 (`confirmQuitTitle` "Thoát ShellX?", thân `confirmQuitBody` — giữ nguyên chữ A1 vì nghĩa không đổi: tab bị đóng, điện thoại mất kết nối), nút destructive "Thoát" → đổi nhãn thành **"Thoát hoàn toàn"** (`confirmQuitAllAction`). Không còn phiên → không hỏi.

### 7.3 Phiên nền đang chạy bản cũ (D19)

```
┌──────────────────────────────────────────────────────┐
│ Phiên nền đang chạy bản cũ                            │
│                                                      │
│ ShellX 1.6.0 cần khởi động lại phiên nền (bản 1.5.2) │
│ đang giữ 4 phiên. Khởi động lại sẽ dừng các shell đó; │
│ tab, pane, thư mục và nội dung gần nhất được mở lại. │
│ Để sau thì ShellX đóng lại, shell và điện thoại vẫn  │
│ chạy với bản cũ.                                     │
│                                                      │
│                  [Để sau] [Khởi động lại phiên nền]   │
└──────────────────────────────────────────────────────┘
```

- Nút chính: "Khởi động lại phiên nền" — kiểu **Destructive** (dừng shell đang chạy), **focus ban đầu ở "Để sau"** (A1 §4 quy tắc destructive). Esc = "Để sau". Bấm nền mờ: bỏ qua.
- Trong lúc khởi động lại: nút chính ở trạng thái loading (A1 §3.3), hai nút bị khoá; xong → hộp đóng, cửa sổ hiện chỗ làm việc đã khôi phục.

### 7.4 Không khởi động được phiên nền (D16)

```
┌──────────────────────────────────────────────────────┐
│ Không khởi động được phiên nền                        │
│                                                      │
│ ShellX cần phiên nền để chạy shell. Thử lại; nếu vẫn │
│ lỗi, khởi động lại máy hoặc cài lại ShellX.          │
│                                                      │
│                                   [Thoát] [Thử lại]   │
└──────────────────────────────────────────────────────┘
```

- Chính "Thử lại" (loading khi đang thử); phụ "Thoát" (thoát UI). Esc không đóng (không có trạng thái "ở lại" hợp lệ); bấm nền bỏ qua.
- Cửa sổ phía sau: trạng thái trống A1 §2.7 **không** có nút "Mở tab mới" (thân `daemonUnavailableEmpty` "Đang chờ phiên nền…").

### 7.5 Dải "phiên nền đã dừng" (D15)

Như dải §4 (cao 36, `rowSelected`), hai biến thể:
- **Đã khởi động lại:** `Icons.history` `textSecondary`, chữ `daemonRestartedStrip` "Phiên nền đã dừng bất ngờ và đã được khởi động lại. Các shell được mở lại ở thư mục cũ." + nút "Đóng".
- **Không khởi động lại được:** `Icons.error_outline` `err`, chữ `daemonLostStrip` "Phiên nền đã dừng. Các shell không còn chạy." + nút chữ "Thử lại" (loading: spinner 12 thay nhãn) + nút "Đóng" chỉ ẩn dải.
- Trong ≤ 3 s chờ khởi động lại: không hiện gì (tránh nhấp nháy); quá 3 s → biến thể lỗi.

---

## 8. Trợ năng

- Dải §4/§7.5: `liveRegion`, nhãn = chữ dải; nút có nhãn đầy đủ ("Đóng thông báo khôi phục" — `restoreStripCloseLabel`; "Thử khởi động lại phiên nền" — `daemonRetryLabel`).
- Hộp §7: focus ban đầu theo A1 §4 (destructive → nút phụ); tiêu đề là `Semantics(header: true)`.
- Vạch §2: chữ terminal; tương phản ≥ 4,5 (§1).
- Không có thao tác chỉ bằng chuột; không có chuyển động lặp.

---

## 9. Copy (vi + en, khoá ARB)

| Mốc | Khoá | vi | en |
|---|---|---|---|
| A5a | `terminalRestoredDivider` (`{time}` String) | — Phiên được khôi phục · {time} — | — Session restored · {time} — |
| A5a | `restoreTimeYesterday` (`{time}`) | hôm qua {time} | yesterday {time} |
| A5a | `trayTerminal` | Terminal | Terminal |
| A5a | `trayRestoreScrollback` | Lưu nội dung terminal khi thoát | Save terminal contents on quit |
| A5a | `trayClearSavedScrollback` | Xóa nội dung đã lưu | Clear saved contents |
| A5a | `restoreAbnormalStrip` (`{count}` int, `{time}` String) | ShellX đã đóng bất thường lần trước. Đã mở lại {count} tab; nội dung tính tới {time}. | ShellX didn't close normally last time. Reopened {count, plural, =1{1 tab} other{{count} tabs}}; contents as of {time}. |
| A5a | `restoreAbnormalNoText` (`{count}` int) | ShellX đã đóng bất thường lần trước. Đã mở lại {count} tab. | ShellX didn't close normally last time. Reopened {count, plural, =1{1 tab} other{{count} tabs}}. |
| A5a | `restoreStripCloseLabel` | Đóng thông báo khôi phục | Dismiss restore notice |
| A5a | `restorePanesFailed` (`{count}` int) | Không mở lại được {count} pane | {count, plural, =1{Couldn't reopen 1 pane} other{Couldn't reopen {count} panes}} |
| A5b | `trayQuitUi` (thay `trayQuit` trong menu) | Thoát | Quit |
| A5b | `trayQuitAll` | Thoát hoàn toàn | Quit Completely |
| A5b | `appMenuQuitAll` | Thoát hoàn toàn | Quit Completely |
| A5b | `quitUiExplainedTitle` | Shell vẫn chạy sau khi thoát | Your shells keep running |
| A5b | `quitUiExplainedBody` (`{count}` int) | {count} tab vẫn chạy nền và điện thoại vẫn kết nối được. Mở lại ShellX để quay về đúng chỗ. Muốn dừng mọi shell, chọn Thoát hoàn toàn (⌥⌘Q). | {count, plural, =1{1 tab keeps} other{{count} tabs keep}} running in the background and your phones stay connected. Open ShellX again to pick up where you left off. To stop every shell, choose Quit Completely (⌥⌘Q). |
| A5b | `quitUiExplainedBodyWindows` (`{count}` int) | {count} tab vẫn chạy nền và điện thoại vẫn kết nối được. Mở lại ShellX để quay về đúng chỗ. Muốn dừng mọi shell, chọn Thoát hoàn toàn trong menu khay hệ thống. | {count, plural, =1{1 tab keeps} other{{count} tabs keep}} running in the background and your phones stay connected. Open ShellX again to pick up where you left off. To stop every shell, choose Quit Completely in the tray menu. |
| A5b | `quitUiAction` | Thoát | Quit |
| A5b | `quitAllAction` | Thoát hoàn toàn | Quit Completely |
| A5b | `confirmQuitAllAction` | Thoát hoàn toàn | Quit Completely |
| A5b | `daemonOldTitle` | Phiên nền đang chạy bản cũ | The background service is out of date |
| A5b | `daemonOldBody` (`{app}`, `{old}` String; `{count}` int) | ShellX {app} cần khởi động lại phiên nền (bản {old}) đang giữ {count} phiên. Khởi động lại sẽ dừng các shell đó; tab, pane, thư mục và nội dung gần nhất được mở lại. Để sau thì ShellX đóng lại, shell và điện thoại vẫn chạy với bản cũ. | ShellX {app} needs to restart the background service (version {old}), which holds {count, plural, =1{1 session} other{{count} sessions}}. Restarting stops those shells; tabs, panes, folders and recent contents are reopened. Choose Later to close ShellX and keep the shells and phones running on the old version. |
| A5b | `daemonOldRestart` | Khởi động lại phiên nền | Restart Service |
| A5b | `daemonOldLater` | Để sau | Later |
| A5b | `daemonStartFailedTitle` | Không khởi động được phiên nền | Couldn't start the background service |
| A5b | `daemonStartFailedBody` | ShellX cần phiên nền để chạy shell. Thử lại; nếu vẫn lỗi, khởi động lại máy hoặc cài lại ShellX. | ShellX needs its background service to run shells. Try again; if it still fails, restart the computer or reinstall ShellX. |
| A5b | `daemonRetry` | Thử lại | Try Again |
| A5b | `daemonRetryLabel` | Thử khởi động lại phiên nền | Try restarting the background service |
| A5b | `daemonUnavailableEmpty` | Đang chờ phiên nền… | Waiting for the background service… |
| A5b | `daemonRestartedStrip` | Phiên nền đã dừng bất ngờ và đã được khởi động lại. Các shell được mở lại ở thư mục cũ. | The background service stopped unexpectedly and was restarted. Shells were reopened in their folders. |
| A5b | `daemonLostStrip` | Phiên nền đã dừng. Các shell không còn chạy. | The background service stopped. Shells are no longer running. |

Quy tắc copy A1 giữ: "tab", "pane", "shell", "terminal", "workspace" giữ tiếng Anh; "Xóa"/"Hủy" kiểu cũ (A2 D13); "phiên nền" là tên tiếng Việt cho daemon trong mọi chữ người dùng thấy (không dùng chữ "daemon"); tiếng Anh dùng "background service". Tiếng Việt không chia số nhiều (ICU `other` duy nhất). `trayQuit` cũ đổi nghĩa thành thoát giao diện → khoá mới `trayQuitUi` để test bắt mọi chỗ dùng cũ.

---

## 10. Wireframe tổng — mở lại sau crash (macOS)

```
┌────────────────────┬───────────────────────────────────────────────────────────────┐
│ ● ● ●   ShellX     │                        server — ~/work/api                    │
│ 🔔  +              ├───────────────────────────────────────────────────────────────┤
│ ▾ Mặc định     2   │ ⟲ ShellX đã đóng bất thường lần trước. Đã mở lại 5 tab; …  Đóng │
│   ● zsh 1          ├────────────────────────────┬┬─────────────────────────────────┤
│ ▾ API          3   │● zsh — ~/work/api        × ││● zsh — ~/work/api/web          │
│ ▌ ● server  ▥2     │ $ npm test                 ││ webpack compiled                │
│   ● zsh 4          │  ✓ 212 passing             ││ — Phiên được khôi phục · 14:31 —│
│   ● logs           │ — Phiên được khôi phục · 14:31 — ││ ~/work/api/web % _        │
│                    │ ~/work/api % _             ││                                 │
└────────────────────┴────────────────────────────┴┴─────────────────────────────────┘
```
