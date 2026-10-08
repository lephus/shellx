# A11 — Đợt chất lượng P1 (desktop + mobile) — Đặc tả thiết kế

- **Ngày:** 2026-10-07
- **Trạng thái:** Người dùng vắng mặt và giao toàn quyền quyết định sản phẩm cho người viết spec (như A1–A10). Phạm vi do người dùng nêu (ràng buộc): mục 14–30 của §5 trong `docs/superpowers/research/2026-10-07-cmux-gap-analysis.md`, trừ 23–24 (hoãn sang A12, D36). D1–D36 do người viết spec chốt, ghi ở bảng §3 kèm cái giá nếu sai.
- **Lộ trình:** A1 → A2 → A4 → A3 → A5a → A5b → A6 → A7 → A8 → A9 → A10 → **A11 (tài liệu này)** → A12 (hook agent + resume + PR status).
- **Nền:** `main` sau A10 (đã gộp, kể cả mobile Task 13–16) và A5b Task 9. A11 **không** sửa `src/mux/*`, `src/agent/*`, `daemon_main.dart`, protocol điện thoại, relay (D34). Ngoại lệ có chủ đích duy nhất ngoài `apps/`: `term/` (Rust CLI, T15).
- **Giữ nguyên:** spec A1–A10 (đặc biệt A9 D5 cú pháp file, D8 "cấu hình hiệu lực là hàm thuần của file", D24 bảng phím, D32 khối phím do ShellX quản lý; A10 D3 thanh tìm, D23 bất biến focus F1–F7, D25 thế hệ `layout.json`). A11 **thêm**, và ghi rõ chỗ **sửa** ở D10 (phím ⌘,), D16 (`cursor-style-blink` từ "không hỗ trợ" thành hỗ trợ) và D18 (`layout.json` thêm khoá tuỳ chọn).
- **Ký hiệu:** "A9 D32" = quyết định D32 của spec A9; "D1" không tiền tố = của tài liệu này. "Tab" = một hàng trong sidebar (một cây pane, A3); "workspace" = nhóm tab có tên trong sidebar (A2). **Lưu ý thuật ngữ:** bảng gap analysis và cmux gọi hàng sidebar là "workspace"; ở ShellX đó là **tab**. Plan: `docs/superpowers/plans/2026-10-07-quality-p1-a11.md`.

---

## 1. Mục tiêu

Biến ShellX từ "không còn lỗi" (A10) thành "dễ chịu khi dùng cả ngày": chỉnh được mọi thứ bằng một cửa sổ Cài đặt thay vì sửa file, soạn lệnh bằng phím macOS quen tay (⌘←, ⌥⌫), chọn chữ bằng ba cú bấm và chế độ copy kiểu vim, mở lại tab lỡ đóng cùng nội dung cuộn, đi lại giữa các pane đã focus, ghim và ghi chú tab, chia/chuyển pane, tìm chữ trong mọi terminal, phóng chữ riêng cho từng workspace, lần chạy đầu có hướng dẫn — và trên điện thoại: chạm thông báo lúc đang kết nối vẫn mở đúng tab, danh sách máy cho thấy tab nào có chữ mới, nháp riêng cho từng terminal, bàn xoay mũi tên, tuỳ chọn không co terminal khi mở bàn phím.

### Tiêu chí thành công (đo được)

1. **Cài đặt:** ⌘, mở lớp phủ Cài đặt (7 trang: Chung, Giao diện, Terminal, Phím tắt, Agent, Điện thoại, Nâng cao). Ô tìm "cursor" → trong ≤ 100 ms chỉ còn các dòng khớp, kèm tên trang. Đổi cỡ chữ bằng thanh trượt → mẫu trong trang đổi **ngay** (≤ 1 khung hình), thả chuột → file cấu hình có đúng một dòng `font-size = 15` trong khối quản lý, mọi pane đổi cỡ trong ≤ 1 s (watcher A9), **không** byte nào khác của file đổi. Chọn chủ đề bằng phím mũi tên → mẫu đổi màu; Enter ghi `theme = …`; Esc đóng mà không ghi gì. Giá trị sai (gõ `font-size` = `abc`) không bao giờ vào file. Dòng do người dùng tự viết, dòng ở file include, dòng ở file Ghostty: GUI nói rõ nguồn và (với include) khoá lại.
2. **Soạn lệnh macOS:** ở prompt zsh có `echo hello world`, ⌘← đưa con trỏ về đầu dòng, ⌘→ về cuối, ⌥⌫ xoá một từ lùi, ⌘⌫ xoá tới đầu dòng; trong `vim` (màn hình thay thế) các phím này **không** gửi `Ctrl-A` (không tăng số) mà đi theo đường cũ.
3. **Chọn chữ:** bấm đúp chọn từ (có sẵn), bấm ba chọn **cả dòng logic** (dòng bị xuống hàng vẫn là một); ⌥-kéo chọn hình chữ nhật; sao chép hình chữ nhật dán ra từng dòng cắt cùng cột. Chế độ copy (⌘⇧M): `h j k l w b e 0 $ gg G`, `v V Ctrl-v`, `y` sao chép và thoát, Esc thoát; bàn phím Telex/Hàn/Nhật vẫn điều khiển được (dùng phím vật lý, D13).
4. **Mở lại:** đóng tab có 3 pane, ⌘⇧T → tab hiện lại **cùng bố cục, cùng thư mục từng pane, kèm cuộc ra cũ** (có vạch phân cách A5a), đúng workspace và đúng vị trí. Đóng 12 tab liên tiếp rồi ⌘⇧T 12 lần: chỉ 10 lần đầu có kết quả. Thoát app: lịch sử mất sạch, **không** có chữ terminal nào ghi ra đĩa.
5. **Quay lại focus:** chuyển A → B → C → trong pane tách D, ⌘⌃[ lần lượt về C, B, A; ⌘⌃] đi tiếp; tab đã đóng bị bỏ qua; bấm quay lại **không** tự ghi thêm lịch sử.
6. **Cấu hình:** `adjust-cell-height = 15%` làm dòng cao hơn 15 % và cả lưới PTY tính lại; `cursor-style-blink = true` làm con trỏ nhấp nháy 530 ms/530 ms **chỉ ở pane đang focus**, chương trình ẩn con trỏ (`ESC[?25l`) vẫn ẩn; `font-feature` được nhận (ghi chú "không có tác dụng: ShellX không bao giờ ghép ligature").
7. **Sidebar:** ghim tab → tab lên đầu workspace, có biểu tượng ghim, kéo không đặt được tab thường lên trên tab ghim, ⌘W trên tab ghim hỏi xác nhận (trừ `confirm-close-surface = false`). Mô tả một dòng (≤ 120 ký tự) và trạng thái (5 giá trị) hiện dưới tên tab, sống qua khởi động lại.
8. **Pane:** hoán đổi pane focus với hàng xóm, tách pane thành tab riêng, chuyển pane sang tab khác — phiên shell **không** bị tắt, chữ còn nguyên; chuyển tab sang workspace khác bằng menu (kéo thả đã có).
9. **Tìm mọi terminal:** ⌘⇧F, gõ `error` → trong ≤ 300 ms (10 pane × 10 000 dòng) danh sách ≤ 200 dòng khớp theo tab/pane; Enter nhảy tới pane, mở thanh tìm với đúng từ khoá và cuộn tới dòng đó.
10. **Phóng chữ theo workspace:** ⌘⌥= trong workspace A làm mọi tab của A to hơn 1 pt; workspace B không đổi; sống qua khởi động lại; ⌘+ toàn cục vẫn cộng chồng lên.
11. **Lần đầu & sau cập nhật:** cài mới → tour 4 thẻ một lần (có phím tắt lấy từ bảng phím hiệu lực, không cứng); cập nhật lên bản mới → thẻ "Có gì mới" một lần (không hiện ở cài mới). Phím tắt toàn cục (nếu đặt) ẩn/hiện cửa sổ từ app khác.
12. **CLI:** `shellx config validate` = `config check` (cùng mã thoát); `shellx doctor` in từng dòng ✓/✗ (app chạy, CLI trong PATH, cấu hình, skill) và thoát 1 nếu có ✗; agent chạy nền trong tab của workspace X gọi `shellx new-tab` (không `--workspace`) → tab mới ở **workspace X**, không lọt vào workspace người dùng đang xem và không cướp focus.
13. **Mobile:** chạm thông báo lúc app vừa mở lại và chưa kết nối xong → khi tab của phiên đó xuất hiện, **tab đó** được chọn (trước đây: tab đầu tiên). Danh sách máy: máy dùng lần cuối nổi lên đầu nhóm online với nhãn "Dùng gần nhất"; thẻ máy hiện "2 tab · 1 có chữ mới"; danh sách lỗi có nút "Thử lại"; trạng thái trống có hướng dẫn. Gõ dở ở terminal A, sang B, quay lại A → nháp còn. Bàn xoay mũi tên: vuốt/kéo theo hướng gửi mũi tên lặp, nhanh dần theo khoảng cách. Bật "Giữ cỡ terminal khi mở bàn phím": mở bàn phím **không** gửi `resize` (đếm bằng test), dòng chứa con trỏ vẫn nhìn thấy.
14. **Riêng tư:** chạy tiêu chí 1–13 với log debug → log không chứa chữ terminal, từ khoá tìm, giá trị cài đặt, đường dẫn, mô tả tab, nội dung clipboard (`grep` chuỗi thử nghiệm rỗng).
15. **Không hồi quy:** mọi test A1–A10 xanh; phím tắt có sẵn không đổi **trừ** hai thay đổi có chủ đích ở D10 (fixture vàng cập nhật, ghi rõ trong test `a11Changes`); một pane không đổi hành vi khi không dùng tính năng mới; tệp cấu hình của người dùng **không bao giờ** bị ghi nếu họ không bấm gì trong Cài đặt.

---

## 2. Kiểm tra hiện trạng (đọc mã ngày 2026-10-07, trước khi quyết)

Mục có HAVE bị **bỏ hoặc thu nhỏ**.

| Mục | Kết quả | Bằng chứng | Hệ quả cho A11 |
|---|---|---|---|
| 14 Cài đặt GUI | MISSING | không có `settings` trong `lib/src/ui`; chỉ `ShortcutsSheet`, `CommandPalette`, `ConfigProblemsPanel` (đều là `A9Overlay`) và menu khay | Làm (T8–T10) |
| 14 Hai kho cấu hình | Có thật | tệp `~/.config/shellx/config` (`ShellxConfig`: font, chủ đề, phím, lệnh…) **và** `SettingsStore` (`SettingKeys`: thông báo, CLI, dịch vụ nền, chia sẻ, mở cùng máy…) điều khiển bằng `TrayAction` → `TrayActions.handle`; A9 D38 chủ ý để công tắc app ở khay | Không gộp; mỗi khoá đúng **một** chủ (D4) |
| 14 Ghi file từ GUI | Một nửa | `ConfigFileWriter.edit` (nguyên tử, giữ BOM/CRLF, so `expected`) nhưng chỉ nhận `BindingEdit` cho khối phím; chưa có chỉnh khoá thường | Mở rộng (D5) |
| 14 Liệt kê chủ đề | MISSING | `config_theme.dart` chỉ giải một tên; `ConfigPaths.themeDirs` có thư mục nhưng không ai liệt kê | Thêm `listThemes` (T10) |
| 15 Bấm đúp | **HAVE** | xterm `onDoubleTapDown` → `selectWord` | Bỏ |
| 15 Bấm ba | MISSING | `TerminalGestureDetector` không có tap thứ 3 | Làm (T3) |
| 15 Chọn hình chữ nhật | Một nửa | `TerminalController.setSelectionMode(SelectionMode.block)` có, không có đường vào từ chuột | Làm (T3) |
| 15 Chế độ copy | MISSING | không có `copy` mode; `TerminalController.setSelection`, `highlight` đủ để dựng | Làm (T4) |
| 16 Tìm mọi terminal | MISSING, **rẻ** | A10 `searchBuffer(Buffer, needle)` thuần, `FindSessions.open(paneId)` | Làm gọn (T11) |
| 16 Vạch đánh dấu agent trên scrollbar | MISSING | cần hook agent | Hoãn A12 |
| 17 Mở lại | MISSING | `close`/`closePane`/`_removeTab` không lưu gì; **nhưng** A5a có đủ: `captureSnapshot` `_save` (cây pane → `SavedTab`), `encodeScrollback`, `_runRestore(RestorePlan)` | Tái dùng (T5) |
| 18 Lịch sử focus | MISSING | `paneHistory` chỉ trong một tab | Làm (T6) |
| 19 Ghim / mô tả / trạng thái | MISSING | `Workspace` chỉ có `name`, `collapsed`, `ssh`; `TerminalTab` chỉ có `customTitle` | Làm (T13) |
| 19 PR status qua `gh` | MISSING, **nặng** | cần `gh` đã đăng nhập, mạng, thăm dò định kỳ, kiểm thử với GitHub | **Hoãn A12** |
| 20 Kiểu con trỏ, lề | **HAVE** | A9: `cursor-style`, `window-padding-x/y` | Bỏ |
| 20 Nhấp nháy con trỏ | Chưa hỗ trợ | A9 D16: `cursor-style-blink` chỉ ghi chú; xterm 4.0.0 `RenderTerminal` không nhấp nháy, mà đổi `TerminalTheme` thì **xoá cache chữ** | Làm bằng `DesktopTerminal.setCursorVisibleMode` (D17, T7) |
| 20 Chiều cao ô | MISSING | `desktopTerminalStyle` cố định `height: 1.2` (xterm `TerminalStyle.height` có sẵn) | Làm (T7) |
| 20 Tắt ligature | **Vô nghĩa** | xterm vẽ **từng ô một** (`painter.paintLine` theo ô), ligature không bao giờ hình thành | Chỉ nhận khoá + ghi chú (D16) |
| 20 Độ mờ / blur | MISSING | `TerminalView.backgroundOpacity` có; cần sửa `MainFlutterWindow.swift` (đã có `AppChannel`) | Làm cuối, tách riêng (T22) |
| 21 Cử chỉ soạn thảo | Một nửa | `CursorKeysInputHandler`: ⌥←/→ → `ESC b/f`; ⌘←/→/⌫ không có (xterm bỏ qua Meta nên ⌘← thành ← thường); ⌥⌫ xterm gửi `Ctrl-W` | Làm bằng action có biết màn hình thay thế (D11, T1) |
| 22 Kéo tab sang workspace | **HAVE** | `SidebarWorkspaces.moveTab` + kéo thả | Chỉ thêm menu/palette |
| 22 Hoán đổi / tách / chuyển pane | MISSING | `pane_layout.dart` có `removePane`, `siblingLeaf`; `_adoptPane` | Làm (T12) |
| 25 Phím toàn cục | MISSING | `window_manager` không đăng ký phím hệ thống | Thêm `hotkey_manager` (T17) |
| 25 Cập nhật + What's New | Một nửa | `update_check.dart` chỉ báo và mở trang tải | Chỉ làm "Có gì mới" (T16); cài tự động **không** (D23) |
| 25 "Open With" Finder | MISSING | cần Info.plist document types + xử lý `open-file` | **Hoãn** (ngoài phạm vi, D2) |
| 26 Cỡ chữ theo workspace | MISSING | `terminalFontSizeProvider` toàn cục; `TerminalPane` tính **một** `style` cho mọi tab | Làm (T14) |
| 27 Tour & trạng thái trống | Một nửa | `EmptyTerminalState` có tiêu đề + nút, không gợi ý phím; `onboarding_page` là đăng nhập/ghép đôi | Làm (T16) |
| 28 Mobile mở đúng tab lúc kết nối | **BUG** | `NotificationOpener.open`: `workspace.tabs.peek().indexWhere` rỗng khi chưa kết nối → không chọn gì, mất `sessionId` | Làm (T2) |
| 28 Mobile đếm chưa đọc | MISSING | protocol không mang trạng thái "chưa đọc"; **không đổi protocol** (D34) → tính cục bộ "có chữ mới" | Làm (T20) |
| 28 Mobile máy nhớ / Thử lại / trống | Một nửa | `MachineListPage` có `_EmptyState` (hướng dẫn ghép đôi) và `state.error`; thiếu nhớ máy, đếm, nút Thử lại rõ | Làm (T20) |
| 29 Mobile nháp theo terminal | MISSING | `VoiceComposerController` một ô cho cả trang | Làm (T18) |
| 29 Mobile bàn xoay mũi tên | MISSING | `ExtraKeysBar` chỉ có 4 phím mũi tên rời | Làm (T19) |
| 29 Mobile chiều cao theo bàn phím | Một nửa | `_TerminalPageState` đã theo dõi `viewInsets` và đo lại lưới (có resize) | Thêm tuỳ chọn cỡ cố định (T21) |
| 30 `config validate` | **HAVE** dưới tên khác | `shellx config check` (A9 D39) | Chỉ thêm bí danh `validate` (T15) |
| 30 `SHELLX_WORKSPACE_ID` | **Thay bằng cơ chế tốt hơn** | `SHELLX_TAB_ID`/`SHELLX_PANE_ID` đã có trong env (A7 D29); workspace của tab đổi khi kéo tab → biến môi trường sẽ cũ | Không thêm biến; CLI gửi `fromTab`, UI tra workspace hiện tại (D26) |
| 30 `shellx doctor` | MISSING | — | Làm (T15) |
| 30 `events` stream, tham chiếu ngắn | Bỏ | gap analysis ghi "verify"; A7 đã có | Bỏ |
| 23–24 Hook agent, resume | — | — | **Hoãn A12** (D36) |

---

## 3. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| D1 | Nền, độc lập | `main` sau A10. Mỗi task gộp độc lập vào `main` (không có tính năng nửa vời nhìn thấy được); thứ tự trong plan là gợi ý, ràng buộc cứng duy nhất: T8 → T9 → T10; T7 trước T8 (lược đồ cài đặt liệt kê khoá T7 thêm); T22 sau T9 | Xung đột nhỏ ở `terminal_workspace_page.dart`/`keybind_actions.dart` giữa các task — mỗi task chỉ **thêm** dòng |
| D2 | Phạm vi | Mục 14–22, 25–30 của §5, thu nhỏ theo bảng §2. **Bỏ:** 16 vạch scrollbar, 19 PR status, 20 ligature (vô nghĩa) và lề/kiểu con trỏ (đã có), 25 "Open With" và cài đặt cập nhật tự động, 30 `events`/tham chiếu ngắn. **Hoãn A12:** 23, 24, PR status, đặt mô tả/trạng thái từ CLI/hook | — |
| D3 | Cài đặt — bề mặt | **Một lớp phủ** trong cửa sổ chính (`A9Overlay.settings`, cùng cơ chế bảng lệnh/phím tắt/vấn đề: bẫy focus, Esc đóng, trả focus), **không** cửa sổ hệ điều hành thứ hai (app là một engine Flutter; cửa sổ hệ điều hành thứ hai cần engine thứ hai). Kích thước 880×600 tối đa, co theo cửa sổ; thanh trang bên trái 200 px, nội dung cuộn bên phải; cửa sổ < 640 px: thanh trang thành hàng tab ngang. Bảy trang: **Chung, Giao diện, Terminal, Phím tắt, Agent, Điện thoại, Nâng cao** (§4.1). Mở bằng ⌘, / Ctrl+, (`open_settings`), mục "Cài đặt…" đầu submenu khay "Cấu hình" (khoá `trayConfigSettings`), bảng lệnh | Người muốn cửa sổ riêng: chưa có |
| D4 | **Một nguồn sự thật** | Hai kho **giữ nguyên**, mỗi khoá đúng **một chủ**, Cài đặt chỉ là giao diện thứ hai của chủ đó: (a) **khoá của file** (`font-*`, `theme`, màu, `cursor-*`, `scrollback-limit`, `window-padding-*`, `macos-option-as-alt`, `confirm-close-surface`, `working-directory`, `adjust-cell-height`, `background-opacity`…) → chủ là **tệp cấu hình**; Cài đặt luôn **đọc `ConfigState`** (không giữ bản sao) và **ghi tệp** (D5); (b) **công tắc app** (thông báo, ngưỡng lệnh dài, điều khiển CLI, cho phép ngoài, cài PATH, hook SSH, dịch vụ nền, lưu scrollback, mở cùng máy, giữ máy thức, chia sẻ terminal, truy cập từ xa) → chủ là **`SettingsStore`/dịch vụ**; Cài đặt gọi **cùng `TrayActions.handle(TrayAction)`** mà khay gọi và đọc cùng provider (`trayLocalStateProvider`, `agentControllerProvider`), nên khay và Cài đặt không bao giờ lệch. Không khoá nào ở cả hai. Mỗi dòng của (a) có chú thích nhỏ "Lưu trong tệp cấu hình" (§4) | Người muốn công tắc app trong tệp: A9 D38 đã từ chối, giữ |
| D5 | Cách GUI ghi tệp | `ConfigFileWriter.edit` nhận thêm biến đổi văn bản tuỳ ý (`editText`); `applyKeyEdits(text, edits)` thuần, `SetKey(key, value)` / `ResetKey(key)`. **Khối thứ hai** `# >>> shellx-managed settings >>>` … `# <<< shellx-managed settings <<<` (cuối tệp, sau khối phím nếu có). Luật: (1) `SetKey`: nếu khoá có dòng **ngoài** mọi khối ở tệp chính → sửa **giá trị của dòng cuối cùng** tại chỗ (giữ cách viết khoá, khoảng trắng, đuôi dòng); không thì đặt/thay dòng trong khối; (2) `ResetKey`: xoá dòng trong khối; mọi dòng của người dùng ngoài khối bị **chú thích hoá** (`# ` + dòng gốc — không xoá, người dùng khôi phục được); nếu nguồn hiệu lực là tệp **Ghostty** thì thay vào đó đặt `key =` (giá trị rỗng = về mặc định ShellX, A9 D5) trong khối; (3) khoá **danh sách** (`font-family` nhiều dòng, `palette`, `keybind`, `command`, `snippet`, `config-file`) không sửa bằng GUI (chỉ `font-family` đơn dòng); (4) khoá mà nguồn hiệu lực là **file include** → hàng chỉ đọc, "Đặt trong {file}:{dòng}" + nút "Mở file"; (5) tệp có dấu khối hỏng/đôi → từ chối (`ConfigWriteRefused.damagedBlock`), toast, không ghi; (6) chỉ ghi khi người dùng **bấm/nhập** (không bao giờ khi mở trang, không khi tải); thanh trượt ghi khi **thả** (tối đa 1 lần/300 ms); (7) giữ BOM/CRLF, giới hạn 1 MiB (A9). Sau ghi: `ConfigController.load(ownWrite: true)` (như `ShortcutsSheet`) | Tệp bị người dùng sửa tay giữa lúc mở Cài đặt: `expected` bytes thất bại → toast "Tệp đã đổi, thử lại" và nạp lại |
| D6 | Kiểm tra giá trị | **Không viết bộ kiểm tra thứ hai.** `validateSetting(key, raw)` dựng một `ConfigEntry` và chạy chính `buildShellxConfig` (A9), đọc `ConfigProblem` của khoá đó: `error` hoặc `badValue` → từ chối kèm thông điệp có sẵn `problemText`; `outOfRange` (giá trị bị kẹp) → từ chối với gợi ý khoảng. Điều khiển có khoảng (thanh trượt, lựa chọn) không thể sinh giá trị sai; ô gõ (font-family, thư mục, màu hex) kiểm khi rời ô / Enter, hiện lỗi dưới ô (`err`), **không ghi** | Bộ phân tích đổi → Cài đặt tự theo (đúng ý) |
| D7 | Tìm trong Cài đặt | Ô tìm ở đầu thanh trang (⌘F / `/` trong lớp phủ). Khớp theo nhãn EN+VI, tên khoá (`font-size`) và từ khoá (`khoá` ARB), dùng `matchScore` của bảng lệnh (A9). Có truy vấn → danh sách **phẳng** các dòng khớp, mỗi dòng ghi tên trang (bấm nhãn trang để mở trang đó và nhấp sáng dòng 1 s); không khớp → "Không có cài đặt nào khớp" + gợi ý "Mở tệp cấu hình". Số kết quả đọc lên lịch sự ≤ 1 lần/500 ms (A9 D44) | — |
| D8 | Xem trước trực tiếp | Trang Giao diện có **mẫu terminal thật** (`TerminalView` chỉ đọc, 8 dòng ANSI cố định: lời nhắc, `ls --color`, diff, lỗi đỏ, 16 màu, emoji/CJK, con trỏ) vẽ bằng chính `TerminalStyle`/`TerminalTheme` của app. Điều khiển chủ đề (danh sách có tìm), cỡ chữ (thanh trượt 9–28 bước 0,5 + ô số), độ đậm (Nhẹ/Thường) cập nhật mẫu **khi rê/focus/kéo** qua `settingsPreviewProvider` (không ghi, không chạm pane thật); **cam kết** (ghi tệp) khi Enter/bấm/thả. Esc hoặc rời trang → bỏ xem trước. Font-family: ô gõ + gợi ý từ tên đã dùng; cam kết khi rời ô, rồi `FontProbe` (A9 D11) cảnh báo nếu chưa cài | Mẫu lệch pane thật nếu pane có override theo workspace (D19): ghi chú dưới mẫu |
| D9 | Nội dung các trang | **Chung:** ngôn ngữ app (đã có `locale.dart`; **hoãn**: chưa làm ở T9–10, chọn ngôn ngữ vẫn theo hệ thống), mở cùng máy, giữ máy thức, dịch vụ nền (A5b), "Mở tour" (**hoãn sang T16**), cập nhật (phiên bản + nút kiểm; **hoãn sang A12**). **Giao diện:** chủ đề, font, cỡ, độ đậm, chiều cao ô, lề, con trỏ (kiểu + nhấp nháy), màu con trỏ/chọn (ô hex), độ mờ/blur (khi có, T22). **Terminal:** scrollback, thư mục tab mới, Option-as-Alt (mac), xác nhận đóng, lưu scrollback khi thoát, xoá nội dung đã lưu, phím toàn cục ẩn/hiện (T17; **hoãn**: ô này vào cùng T17). **Phím tắt:** nội dung `ShortcutsSheet` tái dùng (`ShortcutsEditor`) + lệnh/snippet của người dùng (chỉ đọc, "Sửa trong tệp"). **Agent:** thông báo máy tính + chỉ-khi-nền, ngưỡng lệnh dài, dòng lệnh `shellx` (điều khiển, cho phép ngoài, cài PATH, sao chép lệnh cài skill), hook SSH. **Điện thoại:** truy cập từ xa, ghép đôi, thiết bị đã ghép + thu hồi, chia sẻ terminal máy tính (các mục khay "Điện thoại"). **Nâng cao:** đọc cấu hình Ghostty (`ghostty-config`), vấn đề cấu hình (số + "Xem"), "Mở tệp cấu hình", "Tải lại", đường dẫn tệp + nút sao chép, "Đặt lại tất cả khoá do Cài đặt tạo" (xoá khối quản lý settings — hỏi xác nhận). Mỗi trang đầu có link "Mở tệp cấu hình" (D10). Mọi mục của khay Terminal/Thông báo/Dòng lệnh/SSH/Cấu hình **còn nguyên** ở khay | Trang Điện thoại khi chưa đăng nhập: các dòng bị khoá + nút "Đăng nhập" |
| D10 | ⌘, và `open_config` | **Đổi có chủ đích (A9 D37/D46):** `open_settings` lấy ⌘, / Ctrl+, (chuẩn macOS/Windows); `open_config` (mở **tệp**) chuyển sang ⌘⌥, / Ctrl+Shift+Alt+, và vẫn ở bảng lệnh, khay, nút "Mở tệp cấu hình" trong Cài đặt. Người đã tự `keybind = super+comma=open_config` giữ nguyên (dòng của họ thắng). Fixture vàng: một dòng **đổi** (`open_config`), một dòng **thêm** (`open_settings`), ghi trong `a11Changes` | Người quen ⌘, mở tệp: một lần ngạc nhiên, nút "Mở tệp" ngay trang đầu |
| D11 | Cử chỉ soạn thảo macOS | Action `edit_line:<op>` (op: `line_start` → `\x01`, `line_end` → `\x05`, `delete_line` → `\x15`, `delete_word` → `\x1b\x7f`, `delete_word_forward` → `\x1bd`). Mặc định chỉ macOS: ⌘←, ⌘→, ⌘⌫, ⌥⌫, ⌥⌦. `enabled` = pane focus **đang chạy** và **không ở màn hình thay thế** (vim, less, htop nhận phím như cũ → phím rơi xuống terminal); gửi qua `sendUserText` (thành driver, A1 D6). Windows: không thêm (Home/End/Ctrl+Backspace đã đúng ở PowerShell/cmd). Không đổi ⌥←/→ (đã `ESC b/f`) | Người dùng shell không hiểu `ESC DEL` (hiếm): tự `unbind` |
| D12 | Chọn chữ | Bấm ba = chọn **dòng logic** (nối các hàng `isWrapped`, tối đa 256 hàng), `SelectionMode.line`. ⌥-kéo (Windows: Alt-kéo, Alt trái) = `SelectionMode.block`; chế độ trở lại `line` ở lần chọn thường kế tiếp. Cài bằng một `Listener` ngoài đấu trường cử chỉ (cùng cách `link_layer.dart` — xterm 4.0.0 không báo tap thứ ba) đếm bấm trong `kDoubleTapTimeout` và `kDoubleTapSlop`. Chương trình bật chế độ chuột: chỉ giữ ⌥ mới chọn (giống iTerm2) — không đổi hành vi hiện tại khi không giữ phím | Triple-click trong TUI chuột: không chọn (như hôm nay) |
| D13 | Chế độ copy | Action `toggle_copy_mode` (mac ⌘⇧M, Windows Ctrl+Shift+M). Mô hình thuần `CopyModeState` (con trỏ dòng/cột tuyệt đối trong `Buffer`, neo, kiểu chọn) + `CopyModeKey` → trạng thái mới; phím: `h j k l`/mũi tên; `w b e` (từ: ký tự chữ-số-gạch dưới; còn lại là phân cách); `0 ^ $`; `gg G`; `Ctrl-u/d` nửa trang, `Ctrl-b/f` trang; `v` ký tự, `V` dòng, `Ctrl-v` khối; `y`/Enter sao chép và thoát; `/` mở thanh tìm (thoát chế độ), `n N` kết quả sau/trước của thanh tìm; Esc: xoá chọn, rồi thoát; `q` thoát. **Mọi phím được nuốt** (không tới chương trình). Khớp phím theo `LogicalKeyboardKey` **vật lý** (`keyH`…), không theo ký tự, để Telex/Hàn/Kana không phá (cmux #5292). Vẽ: ô con trỏ bằng `TerminalController.highlight` màu `accent`, vùng chọn là selection của xterm; chip "COPY MODE" góc dưới phải pane (§4.3). Cuộn pane để giữ con trỏ trong khung. Màn hình thay thế: chỉ màn hình hiện thấy. Pane mất focus / tab đổi / pane thoát → thoát chế độ | Người dùng muốn `Ctrl-[` thoát: không (Esc) |
| D14 | Mở lại mục đã đóng | `ClosedItems` (Riverpod, **chỉ trong bộ nhớ**, không bao giờ ghi đĩa): tối đa **10** mục, tổng chữ ≤ **2 MiB** (bỏ mục cũ nhất). Ghi khi `TerminalTabs.close`/`closePane` chạy (mọi đường: ×, ⌘W, chuột giữa, menu, CLI `close`): mục **tab** (cây pane → `SavedTab` bằng `_save` đã công khai hoá, workspace id, vị trí, chữ từng pane từ `encodeScrollback`, `launch` SSH qua `forReconnect`) hoặc mục **pane** (pane của tab tách đôi: cwd/launch/chữ + `tabId`). `reopen_closed` (mac ⌘⇧T, Windows Ctrl+Shift+Alt+T): mục **mới nhất**; tab → `_runRestore` với `RestorePlan` một tab (tái dùng 100 % đường khôi phục A5a: vạch phân cách D8, grid ước lượng, đặt vào workspace cũ, không có thì workspace hiện tại, chọn tab); pane → chia phải pane focus của tab cũ nếu còn, không thì mở thành tab. Pane đã `exited` mà không phải SSH-có-thể-nối-lại: vẫn ghi (chữ có ích). Không ghi mục nếu chẳng có chữ lẫn cwd. Bảng lệnh "Mở lại tab đã đóng" (vô hiệu khi rỗng). Thoát app → lịch sử mất. Toast "Đã mở lại “{tên}”" | Mất chữ khi app sập: chấp nhận (bộ nhớ) |
| D15 | Lịch sử focus | `FocusHistory` (Riverpod): chồng `(tabId, paneId)` ≤ 50, ghi khi **người dùng** đổi tab/pane (chọn tab, bấm pane, ⌘1–9, goto_split, jump_to_unread); **không** ghi: đóng tab (người kế nhiệm tự chọn), khôi phục, `focus_history` chính nó. Loại trùng liên tiếp. Action `focus_history:back|forward` (mac ⌘⌃[ / ⌘⌃], Windows Ctrl+Alt+[ / ]); bỏ qua mục đã chết khi đi; ở đầu/cuối: không làm gì (không toast). Đi lại không xoá "tiến" (như trình duyệt); ghi mới cắt phần "tiến" | — |
| D16 | Khoá cấu hình mới | Thêm vào bảng A9 §3.1 (chỉ tệp ShellX, **không** đọc từ Ghostty): `adjust-cell-height = N%` hoặc `N` (đều là phần trăm; −10…50; mặc định 0; `height = 1,2 × (1 + N/100)`; ngoài khoảng → kẹp + `outOfRange`); `cursor-style-blink = true\|false` (mặc định `false` = hôm nay; thôi ghi chú `unsupportedValue`); `font-feature = …` nhận mọi giá trị hợp lệ về cú pháp, ghi chú `unsupportedValue` "ShellX không bao giờ ghép ligature"; `background-opacity`, `background-blur` ở T22 (D25). Mặc định mọi khoá = hành vi hôm nay (một người không đặt khoá nào không thấy gì đổi) | Người muốn nhấp nháy theo DECSCUSR của chương trình: không |
| D17 | Cơ chế nhấp nháy | Không đổi `TerminalTheme` (xoá cache chữ). `DesktopTerminal` ghi nhớ ý chương trình (`_wantsCursor`, ghi đè `setCursorVisibleMode`) và một `CursorBlinker` (Timer 530 ms) chỉ chạy cho pane **đang focus của cửa sổ đang hoạt động** gọi `super.setCursorVisibleMode(wants && phase)` + `notifyListeners()`; mất focus/ẩn cửa sổ → dừng và con trỏ về trạng thái `wants`. `MediaQuery.disableAnimations` → không nhấp nháy. Gõ phím → pha "hiện" lại ngay (con trỏ không tắt khi đang gõ) | Một TUI đọc `cursorVisibleMode` qua `shellx read`: A7 đọc buffer, không đọc cờ này — kiểm bằng test |
| D18 | Ghim, mô tả, trạng thái | Trên **tab**. Mô hình: `TabMeta {pinned, description (≤ 120, một dòng, cắt theo grapheme như `clipName`), status (none/inProgress/review/blocked/done)}` trong `TerminalTab` và `SavedTab` (khoá tuỳ chọn `pinned`, `desc`, `status` trong `layout.json`; bản cũ đọc bỏ qua khoá lạ, bản mới đọc file cũ cho mặc định; **không** tăng `version`). Ghim: tab ghim **nổi lên đầu workspace** (thứ tự giữa các tab ghim giữ nguyên, kéo thả bị kẹp: không đặt tab thường lên trên tab ghim và ngược lại), biểu tượng ghim cạnh tên, "Đóng tab" (⌘W, ×, chuột giữa, menu) hỏi xác nhận (trừ `confirm-close-surface = false`; `shellx close` của CLI giữ luật A7 D18). Mô tả: menu chuột phải "Đặt mô tả…" (ô nhập tại chỗ như đổi tên), hiện dưới tên (1 dòng, `textSecondary`, trên dòng ngữ cảnh A2). Trạng thái: menu "Trạng thái ▸" (5 mục), chấm màu bên trái tên (xám/xanh dương/vàng/đỏ/xanh lá) + nhãn cho trình đọc màn hình; không đổi vòng chú ý A4. **Không** có CLI/hook đặt các giá trị này ở A11 (hoãn A12 cùng hook agent) | PR status: hoãn A12 |
| D19 | Cỡ chữ theo workspace | `Workspace.fontStep` (số thực, −6…+10 điểm, mặc định 0) lưu trong JSON workspace (khoá `zoom`; thiếu = 0; giá trị lạ bị bỏ). Cỡ hiệu lực của một tab = `clamp(toàn cục + bước của workspace chứa tab, 9, 28)`. Action `increase_workspace_font_size[:N]` (mac ⌘⌥=), `decrease_…` (⌘⌥-), `reset_workspace_font_size` (⌘⌥0); Windows: Ctrl+Alt+= và Ctrl+Alt+-, reset không gán. Chỉ tính cho workspace của tab đang chọn. Lưới PTY của các tab trong workspace tính lại (settler A10 gom). Sidebar: tooltip tiêu đề workspace thêm "Cỡ chữ +2" khi ≠ 0 | Lưới tab mới mở dùng cỡ toàn cục lúc đo đầu: lưới đúng lại ở lần layout đầu (như mọi pane, A5a D17) |
| D20 | Pane: hoán đổi, tách, chuyển | Action không gán phím (để khỏi đụng bảng): `swap_split:left\|right\|up\|down` (đổi **chỗ** pane focus với láng giềng cùng hướng — theo hình học `paneRects`; focus ở lại phiên cũ), `break_pane` (pane → tab mới cuối workspace, chọn tab đó; không làm gì nếu tab chỉ một pane), `join_pane` (menu/palette "Chuyển pane tới tab ▸" liệt kê ≤ 20 tab khác; chia phải pane focus của tab đích). Phiên **không bị tắt**: chỉ `PaneSession` đổi tab; `tabId` môi trường của shell (A7) không đổi → CLI `@tab` của pane đã chuyển trỏ về tab cũ (giới hạn đã biết, ghi HANDOFF). "Chuyển tab tới workspace ▸" thêm vào menu chuột phải của hàng tab và bảng lệnh ("Chuyển tab tới {workspace}") dùng `SidebarWorkspaces.moveTab` có sẵn. Mọi thao tác tôn trọng cỡ tối thiểu pane A3 D4 (không đủ chỗ → toast `PaneNoRoomNotice`) | Người muốn kéo pane giữa tab: P2 |
| D21 | Tìm mọi terminal | Action `search_all` (mac ⌘⇧F, Windows Ctrl+Shift+Alt+F), lớp phủ kiểu bảng lệnh (ô tìm + danh sách). Tìm trong **buffer chính** (cuộn + màn hình) của mọi pane còn sống, không phân biệt hoa thường, chữ thuần, ≥ 2 ký tự, debounce 150 ms, ngân sách 8 ms mỗi lát (`BufferSearch.step`), nhường vòng sự kiện giữa các lát; tối đa 200 dòng kết quả (tối đa 20/pane), mỗi dòng: nhãn tab · "Pane n" (khi tách) · số dòng · đoạn ≤ 120 ký tự quanh chỗ khớp (đã lọc ký tự điều khiển) có tô. Enter/bấm: chọn tab, focus pane, mở thanh tìm A10 với đúng từ khoá, nhảy tới kết quả có `startRow` ≥ dòng đã chọn. Đoạn trích chỉ trong bộ nhớ lớp phủ, vứt khi đóng | Tìm trong 100 pane: chậm hơn, vẫn không đứng UI (lát) |
| D22 | Phím toàn cục ẩn/hiện | Khoá cấu hình `global-hotkey = <trigger>` (cú pháp trigger A9 D22, **một** tổ hợp, bắt buộc có ít nhất một bổ trợ, qua luật D25 của A9 và **cấm** các tổ hợp chỉ-Shift); mặc định **trống = tắt**. Gói `hotkey_manager` (pin chính xác; cùng tác giả `window_manager`/`tray_manager`), phạm vi hệ thống; đăng ký lúc khởi động và khi giá trị đổi, `unregisterAll` khi thoát. Bấm: cửa sổ đang hoạt động → ẩn (về khay như đóng cửa sổ A1); đang ẩn/nền → hiện + focus (đường `openTerminalWindow`). Đăng ký thất bại (phím bị chiếm) → vấn đề cấu hình `unsupportedValue` + toast một lần, app chạy tiếp. Ô ghi phím ở Cài đặt › Terminal (dùng bộ ghi của `ShortcutsEditor`). macOS không cần quyền; ⚠ MANUAL | Gói không tương thích Flutter 3.41: tự viết kênh gốc (RegisterEventHotKey/RegisterHotKey) — rủi ro ghi trong plan T17 |
| D23 | "Có gì mới" | Ghi `last_seen_version` (SettingsStore) mỗi lần khởi động xong. Khác phiên bản đã lưu **và** đã có giá trị cũ → thẻ "Có gì mới" một lần (lớp phủ nhỏ, nút "Đã hiểu"/"Xem thêm" mở trang phát hành). Nội dung từ tài sản `assets/whats_new.json` (`{ "1.2.0": { "en": [...], "vi": [...] } }`, tối đa 5 gạch đầu dòng mỗi ngôn ngữ; thiếu phiên bản → không hiện, vẫn ghi phiên bản). Cài mới (chưa có giá trị) → **không** hiện, hiện tour (D24). Không cài đặt tự động (tray "Tải bản cập nhật" giữ nguyên) | — |
| D24 | Tour & trạng thái trống | Tour 4 thẻ (lớp phủ, ← → / Tab, "Bỏ qua", "Xong"): Tab mới & chia pane; Thông báo & vòng chú ý; Bảng lệnh & tìm; Cài đặt & phím tắt. Phím tắt trong thẻ lấy từ `actionShortcutLabel` (theo bảng hiệu lực, **không cứng**; action bị `unbind` → không hiện gợi ý). Hiện **một lần** khi cài mới (`tour_done`), mở lại từ Cài đặt › Chung và bảng lệnh. Trạng thái trống có gợi ý phím: `EmptyTerminalState` thêm 3 dòng gợi ý (⌘T, ⌘⇧P, ⌘,); bảng thông báo rỗng ("Chưa có thông báo — vòng sáng hiện ở pane khi agent cần bạn"); tìm mọi terminal không kết quả; Cài đặt không kết quả. Không có hoạt ảnh mới (giảm chuyển động) | — |
| D25 | Độ mờ / blur macOS | Khoá `background-opacity` (0,3–1; mặc định 1) và `background-blur` (`true\|false\|số>0`=true; mặc định `false`); chỉ **vùng terminal** (nền pane + lề) mờ, sidebar/đầu pane/toast giữ đặc. Chỉ khi opacity < 1 hoặc blur bật, kênh `AppChannel.setBackdrop(opacity, blur)` làm cửa sổ không-đặc (`isOpaque=false`, `backgroundColor=.clear`, `FlutterViewController.backgroundColor=.clear`) và thêm `NSVisualEffectView` (`.behindWindow`, `.hudWindow`) dưới Flutter view khi blur; mặc định (đặc) **không chạm** cửa sổ. Windows: `notOnThisPlatform` (ghi chú, không lỗi). Kênh lỗi → quay về đặc + ghi chú. Làm **cuối cùng** (T22) vì chỉ thử tay được | Không đạt thử tay → bỏ T22 (mọi thứ khác không phụ thuộc) |
| D26 | CLI | (a) `shellx config validate` = `config check` (cùng `ui.config.check`, cùng mã thoát); (b) `shellx doctor [--json]`: chạy cục bộ trong Rust, mỗi dòng `✓/✗ <mục>`: app đang chạy (socket), phiên bản CLI ↔ app, `shellx` trong PATH, skill đã cài (`~/.claude/skills/shellx`), và khi app chạy: `config check` (số lỗi/cảnh báo); thoát 1 nếu có ✗; **không** in nội dung tệp hay đường dẫn của người dùng; (c) **workspace mặc định của người gọi:** khi `new-tab`/`ssh`/`workspace new`-không-`--workspace` mà có `SHELLX_PANE_ID` (hoặc `SHELLX_TAB_ID`), CLI gửi `fromPane` (và `fromTab`); `_tabNew` tra `tabOfSession(fromPane)` rồi `SidebarState.workspaceOf(tab.id)` **hiện tại** (pane đã chuyển tab thì theo tab mới; không phải biến môi trường cũ) và mở ở đó; không có `fromPane` hoặc pane không còn → thử `workspaceOf(fromTab)`; rồi → workspace hiện tại như hôm nay. Mặc định vẫn **không** focus (A7 D14) — kiểm bằng test. **Không** thêm `SHELLX_WORKSPACE_ID` (sẽ cũ khi kéo tab; không cần đụng agent/mux) | Script ngoài tab ShellX: không đổi |
| D27 | Mobile: chạm thông báo | `TerminalWorkspace.pendingSelect(sessionId)` (một giá trị): `NotificationOpener.open` nếu chưa thấy tab → ghi nhớ; khi danh sách tab đổi (kết nối xong, `session.list`, mở lại) và có tab id đó → `select`, rồi xoá; hết hạn sau 30 s hoặc khi người dùng tự chọn tab. Máy chưa ghép vẫn không mở gì (không đổi) | — |
| D28 | Mobile: danh sách máy | (a) **Nhớ máy:** `AppSettings.lastMachineId` (lưu khi mở terminal của máy); trong nhóm online, máy đó lên đầu + nhãn "Dùng gần nhất"; offline không đổi chỗ. Không tự mở terminal lúc khởi động (bất ngờ). (b) **Chữ mới:** `TerminalTabController.unseen` (đã có output kể từ lần cuối tab được xem: tab không active hoặc trang không hiện), `WorkspaceRegistry.unseenCount(agentId)`; thẻ máy: "2 tab · 1 có chữ mới" (chấm `accent`, đọc cho trình đọc màn hình); bấm máy → tab đầu tiên có chữ mới được chọn. Không protocol mới, không lưu qua khởi động. (c) **Lỗi/trống:** `state.error` → khối lỗi giữa trang với nút "Thử lại" (`refresh`) và dòng "Kiểm tra kết nối"; danh sách rỗng giữ `_EmptyState` ghép đôi nhưng thêm nút "Tải lại" | Đếm sai khi tab bị đóng: tính lại từ `tabs` mỗi lần |
| D29 | Mobile: nháp | `TerminalTabController.draft` (String, trong bộ nhớ phiên app, không ghi đĩa). Ô soạn giọng nói nạp nháp của tab active khi chuyển tab và ghi lại mỗi thay đổi (debounce 200 ms); gửi thành công xoá nháp; tab đóng → xoá. Không ghi đĩa (có thể chứa bí mật) | Mất nháp khi app bị hệ điều hành giết: chấp nhận |
| D30 | Mobile: bàn xoay mũi tên | `ArrowPadKey` đứng **trước** bốn phím mũi tên (không thay): kéo một ngón theo hướng quá 14 dp → gửi mũi tên rồi lặp; khoảng cách từ điểm bắt đầu quyết định tốc độ (14–28 dp: 4/s; 28–56: 10/s; > 56: 20/s); chạm nhanh không làm gì; nhấc ngón dừng. Trục trội thắng (không đường chéo). Trợ năng: `Semantics` với hành động tuỳ biến lên/xuống/trái/phải (mỗi hành động gửi một mũi tên). Ctrl/Alt đang chốt áp dụng như phím thường (`ExtraKeysController`) | Người thích bốn phím: vẫn còn |
| D31 | Mobile: cỡ cố định | `AppSettings.fixedTerminalHeight` (mặc định **tắt**), công tắc trong Cài đặt: "Giữ cỡ terminal khi mở bàn phím". Bật: lưới được đo bằng chiều cao **không trừ `viewInsets`** nên mở/đóng bàn phím **không gửi `resize`**; vùng terminal được dịch lên `shift = clamp(cursorBottom − (visibleBottom − 8), 0, inset)` (hàm thuần `cursorShift`) để dòng con trỏ luôn nhìn thấy (animate 150 ms, bỏ khi giảm chuyển động). Tắt: hành vi hôm nay | Dòng cuối bị bàn phím che nếu `cursorShift` sai: ⚠ thử tay |
| D32 | Phím mặc định mới (tổng hợp) | macOS / Windows: `open_settings` ⌘, / Ctrl+,; `open_config` ⌘⌥, / Ctrl+Shift+Alt+,; `edit_line:*` ⌘←, ⌘→, ⌘⌫, ⌥⌫, ⌥⌦ / —; `toggle_copy_mode` ⌘⇧M / Ctrl+Shift+M; `reopen_closed` ⌘⇧T / Ctrl+Shift+Alt+T; `focus_history:back` ⌘⌃[ / Ctrl+Alt+[; `focus_history:forward` ⌘⌃] / Ctrl+Alt+]; `search_all` ⌘⇧F / Ctrl+Shift+Alt+F; `increase_workspace_font_size` ⌘⌥= / Ctrl+Alt+=; `decrease_workspace_font_size` ⌘⌥- / Ctrl+Alt+-; `reset_workspace_font_size` ⌘⌥0 / —. Không phím mặc định: `swap_split`, `break_pane`, `join_pane`, `toggle_pin_tab`, `show_tour`, `show_whats_new`. Windows dùng **Alt trái** (A3 D20, A9 D26). Mọi action mới vào bảng lệnh (A9 D26 `inPalette`) và `shortcuts_sheet` | Chọn phím khác: người dùng tự `keybind` |
| D33 | Riêng tư | Xem §5. | — |
| D34 | Không đổi | `packages/shellx_core` protocol, `shellx_agent`, `shellx_client`, relay, `src/mux/*`, `daemon_main.dart`, `agent_side.dart`: **không sửa**. `term/` chỉ thêm lệnh `doctor`, bí danh `config validate`, trường `fromTab` | — |
| D35 | Thử tay và gộp | Mỗi task có mục ⚠ riêng ở §9; executor ghi "pending manual" vào ledger `## A11 — execution`; **task không gộp cho tới khi mục ⚠ của nó passed** (như A10 D40). T22 có thể bị **bỏ** hoàn toàn nếu thử tay thất bại | — |
| D36 | A12 | Hook agent (`shellx integrations install`), resume phiên agent sau khôi phục, trạng thái Running/Needs-input/Idle, PR status qua `gh`, đặt mô tả/trạng thái tab từ CLI/hook, vạch scrollbar theo prompt agent, "Open With", cài đặt cập nhật tự động, tìm regex | — |

---

## 4. Giao diện và chuỗi (EN + VI)

Theme/token/khoảng cách: `ShellxDesktopColors`, `ShellxText`, `ShellxSpace`, `ShellxSizes` hiện có (UI-A9). "SSH", "tmux", "pane", "tab", "workspace" giữ nguyên tiếng Anh trong bản VI; `⌘`/`Ctrl` lấy từ nền tảng, không dịch. Mọi chuỗi vào `lib/l10n/app_en.arb` + `app_vi.arb` (desktop), `intl_en.arb` + `intl_vi.arb` (mobile).

### 4.1 Cài đặt (desktop)

Lớp phủ: nền `surface`, viền `border`, bo `r12`, bóng như bảng lệnh; trên cùng tiêu đề "Cài đặt" + nút ✕; thanh trang trái (mục chọn = `primarySoft` + vạch `accent` 2 px trái); ô tìm trên cùng thanh trang. Mỗi **dòng cài đặt**: nhãn (`body`), mô tả một dòng (`caption`, `textSecondary`), điều khiển bên phải; dưới cùng (nếu khoá của tệp) chú thích `caption` "Lưu trong tệp cấu hình · `font-size`". Dòng không sửa được: điều khiển mờ + dòng giải thích (`textSecondary`) + nút "Mở file". Lỗi giá trị: dòng `err` dưới điều khiển, liên kết `aria-live` lịch sự. Footer cố định: "Mở tệp cấu hình" (link) · "Tải lại" · "{n} vấn đề cấu hình" khi có.

| Khoá ARB | EN | VI |
|---|---|---|
| `settingsTitle` | Settings | Cài đặt |
| `settingsSearch` | Search settings | Tìm cài đặt |
| `settingsNoMatch` | No setting matches “{query}” | Không có cài đặt nào khớp “{query}” |
| `settingsNoMatchHint` | Not here? Open the configuration file. | Không thấy? Mở tệp cấu hình. |
| `settingsPageGeneral` | General | Chung |
| `settingsPageAppearance` | Appearance | Giao diện |
| `settingsPageTerminal` | Terminal | Terminal |
| `settingsPageKeys` | Keyboard shortcuts | Phím tắt |
| `settingsPageAgents` | Agents | Agent |
| `settingsPagePhone` | Phone | Điện thoại |
| `settingsPageAdvanced` | Advanced | Nâng cao |
| `settingsOpenFile` | Open configuration file | Mở tệp cấu hình |
| `settingsReload` | Reload | Tải lại |
| `settingsSavedInFile` | Saved in the configuration file · {key} | Lưu trong tệp cấu hình · {key} |
| `settingsSetIn` | Set in {file}, line {line} | Đặt trong {file}, dòng {line} |
| `settingsFromGhostty` | From your Ghostty configuration. Changing it here overrides it for ShellX. | Lấy từ cấu hình Ghostty của bạn. Đổi ở đây sẽ ghi đè cho ShellX. |
| `settingsMultiLine` | Set on several lines. Edit it in the file. | Được đặt ở nhiều dòng. Hãy sửa trong tệp. |
| `settingsReset` | Reset to default | Về mặc định |
| `settingsResetAll` | Undo everything changed here | Hoàn tác mọi thay đổi đã làm ở đây |
| `settingsResetAllConfirm` | Remove the settings ShellX wrote to your configuration file? Lines you wrote yourself stay. | Xoá các cài đặt ShellX đã ghi vào tệp cấu hình? Dòng bạn tự viết được giữ nguyên. |
| `settingsFileChanged` | The file changed while you were editing. Reloaded, try again. | Tệp đã đổi trong lúc bạn chỉnh. Đã nạp lại, hãy thử lại. |
| `settingsFileDamaged` | The managed block in the file is damaged. Open the file to fix it. | Khối do ShellX quản lý trong tệp bị hỏng. Hãy mở tệp để sửa. |
| `settingsFileUnwritable` | Couldn’t save the file | Không lưu được tệp |
| `settingsPreviewLabel` | Preview | Xem trước |
| `settingsPreviewNote` | The preview doesn’t include this workspace’s own zoom. | Bản xem trước không gồm cỡ chữ riêng của workspace này. |
| `settingsTheme` | Theme | Chủ đề |
| `settingsFontFamily` | Font | Font |
| `settingsFontFamilyHint` | A font installed on this computer | Một font đã cài trên máy |
| `settingsFontSize` | Font size | Cỡ chữ |
| `settingsFontWeight` | Text weight | Độ đậm chữ |
| `settingsFontWeightLight` | Light | Nhẹ |
| `settingsFontWeightRegular` | Regular | Thường |
| `settingsCellHeight` | Line height | Chiều cao dòng |
| `settingsPadding` | Padding | Lề |
| `settingsCursorStyle` | Cursor | Con trỏ |
| `settingsCursorBlock` | Block | Khối |
| `settingsCursorBar` | Bar | Thanh |
| `settingsCursorUnderline` | Underline | Gạch chân |
| `settingsCursorBlink` | Blinking cursor | Con trỏ nhấp nháy |
| `settingsScrollback` | Scrollback lines | Số dòng cuộn lại |
| `settingsScrollbackNote` | Applies to panes opened from now on. | Áp dụng cho pane mở từ bây giờ. |
| `settingsWorkingDir` | New tabs start in | Tab mới bắt đầu ở |
| `settingsWorkingDirHome` | Home folder | Thư mục chính |
| `settingsWorkingDirInherit` | The current pane’s folder | Thư mục của pane hiện tại |
| `settingsWorkingDirPath` | A folder… | Một thư mục… |
| `settingsOptionAsAlt` | Option key as Alt | Phím Option làm Alt |
| `settingsConfirmClose` | Ask before closing | Hỏi trước khi đóng |
| `settingsConfirmCloseRunning` | When a command is running | Khi có lệnh đang chạy |
| `settingsConfirmCloseNever` | Never | Không bao giờ |
| `settingsConfirmCloseAlways` | Always | Luôn luôn |
| `settingsGlobalHotkey` | Show or hide ShellX from anywhere | Ẩn/hiện ShellX từ mọi nơi |
| `settingsGlobalHotkeyNone` | Not set | Chưa đặt |
| `settingsGlobalHotkeyRecord` | Press the keys… | Nhấn tổ hợp phím… |
| `settingsGlobalHotkeyTaken` | That shortcut is used by another app | Tổ hợp này đang được ứng dụng khác dùng |
| `settingsGhosttyConfig` | Read fonts and colors from Ghostty | Đọc font và màu từ Ghostty |
| `settingsOpenTour` | Show the tour again | Xem lại phần hướng dẫn |
| `settingsVersion` | Version {version} | Phiên bản {version} |
| `settingsProblems` | {n} configuration problems | {n} vấn đề cấu hình |
| `settingsLoginNeeded` | Sign in to manage the phone connection | Đăng nhập để quản lý kết nối điện thoại |
| `settingsCommandsNote` | Your commands and snippets are edited in the file. | Lệnh và đoạn chữ của bạn được sửa trong tệp. |
| `settingsConfigPath` | Configuration file | Tệp cấu hình |
| `actionOpenSettings` | Settings | Cài đặt |
| `trayConfigSettings` | Settings… | Cài đặt… |

Các dòng của trang Agent / Điện thoại / Chung dùng lại nhãn khay đã dịch (`trayDesktopNotifications`, `trayNotifyThreshold`, `trayCliControl`, `trayRemoteAccess`, `trayKeepAwake`, `trayLaunchAtStartup`, `trayBackgroundService`, `trayRestoreScrollback`…) — không dịch lại.

### 4.2 Phím tắt, mở lại, lịch sử focus, hoán đổi, tìm mọi terminal

| Khoá ARB | EN | VI |
|---|---|---|
| `actionEditLineStart` | Move to line start | Về đầu dòng |
| `actionEditLineEnd` | Move to line end | Về cuối dòng |
| `actionEditDeleteLine` | Delete to line start | Xoá tới đầu dòng |
| `actionEditDeleteWord` | Delete previous word | Xoá từ phía trước |
| `actionEditDeleteWordForward` | Delete next word | Xoá từ phía sau |
| `actionToggleCopyMode` | Copy mode | Chế độ copy |
| `actionReopenClosed` | Reopen closed tab | Mở lại tab đã đóng |
| `actionFocusBack` | Back to previous pane | Quay lại pane trước |
| `actionFocusForward` | Forward to next pane | Tới pane kế |
| `actionSearchAll` | Find in all terminals | Tìm trong mọi terminal |
| `actionIncreaseWorkspaceFont` | Bigger text in this workspace | Chữ lớn hơn trong workspace này |
| `actionDecreaseWorkspaceFont` | Smaller text in this workspace | Chữ nhỏ hơn trong workspace này |
| `actionResetWorkspaceFont` | Reset text size in this workspace | Đặt lại cỡ chữ trong workspace này |
| `actionSwapSplit` | Swap pane with neighbour | Đổi chỗ pane với pane bên cạnh |
| `actionBreakPane` | Move pane to its own tab | Chuyển pane thành tab riêng |
| `actionJoinPane` | Move pane to another tab | Chuyển pane sang tab khác |
| `actionTogglePinTab` | Pin or unpin tab | Ghim / bỏ ghim tab |
| `actionShowTour` | Show the tour | Xem hướng dẫn |
| `actionShowWhatsNew` | What’s new | Có gì mới |
| `reopenedTab` | Reopened “{name}” | Đã mở lại “{name}” |
| `reopenNothing` | Nothing to reopen | Không có gì để mở lại |
| `copyModeChip` | COPY MODE | CHẾ ĐỘ COPY |
| `copyModeHint` | y copy · v select · Esc exit | y chép · v chọn · Esc thoát |
| `copyModeCopied` | Copied | Đã chép |
| `searchAllPlaceholder` | Find in all terminals | Tìm trong mọi terminal |
| `searchAllNeedTwo` | Type at least 2 characters | Gõ ít nhất 2 ký tự |
| `searchAllNone` | No matches in open terminals | Không có kết quả trong các terminal đang mở |
| `searchAllCapped` | Showing the first {n} matches | Hiển thị {n} kết quả đầu tiên |
| `searchAllLine` | Line {n} | Dòng {n} |
| `moveTabToWorkspace` | Move tab to workspace | Chuyển tab tới workspace |
| `movePaneToTab` | Move pane to tab | Chuyển pane tới tab |

### 4.3 Sidebar (ghim, mô tả, trạng thái, chip chế độ copy)

Ghim: biểu tượng 12 px `textSecondary` cạnh tên (mục "Bỏ ghim" khi đã ghim). Mô tả: `ShellxText.small`, `textSecondary`, 1 dòng cắt `…`. Trạng thái: chấm 8 px trái tên (`textSecondary` / `accent` / `warn` / `err` / `ok`), `Semantics.label` = nhãn. Chip chế độ copy: góc dưới phải pane, `surface` 90 %, viền `accent`, chữ `caption` `copyModeChip` + `copyModeHint`; không chặn chuột.

| Khoá ARB | EN | VI |
|---|---|---|
| `tabPin` | Pin tab | Ghim tab |
| `tabUnpin` | Unpin tab | Bỏ ghim tab |
| `tabPinned` | Pinned | Đã ghim |
| `tabPinnedCloseTitle` | Close pinned tab? | Đóng tab đã ghim? |
| `tabPinnedCloseBody` | “{name}” is pinned. | “{name}” đã được ghim. |
| `tabSetDescription` | Set description… | Đặt mô tả… |
| `tabDescriptionPlaceholder` | What is this tab for? | Tab này dùng để làm gì? |
| `tabStatus` | Status | Trạng thái |
| `tabStatusNone` | No status | Không có trạng thái |
| `tabStatusInProgress` | In progress | Đang làm |
| `tabStatusReview` | Needs review | Cần xem lại |
| `tabStatusBlocked` | Blocked | Bị chặn |
| `tabStatusDone` | Done | Xong |
| `workspaceZoomTip` | Text size {step} | Cỡ chữ {step} |

### 4.4 Tour, Có gì mới, trạng thái trống

| Khoá ARB | EN | VI |
|---|---|---|
| `tourSkip` | Skip | Bỏ qua |
| `tourNext` | Next | Tiếp |
| `tourDone` | Done | Xong |
| `tourStep` | {n} of {total} | {n}/{total} |
| `tourTabsTitle` | Tabs and panes | Tab và pane |
| `tourTabsBody` | Open a tab with {newTab}. Split the pane with {splitRight} or {splitDown}. | Mở tab bằng {newTab}. Chia pane bằng {splitRight} hoặc {splitDown}. |
| `tourNotifyTitle` | Know when an agent needs you | Biết khi nào agent cần bạn |
| `tourNotifyBody` | A glowing ring appears on the pane. Jump to it with {jumpUnread}. | Một vòng sáng hiện ở pane. Nhảy tới đó bằng {jumpUnread}. |
| `tourFindTitle` | Find your way | Tìm đường nhanh |
| `tourFindBody` | Find text with {find}, everywhere with {searchAll}, and run any command from {palette}. | Tìm chữ bằng {find}, trong mọi terminal bằng {searchAll}, và chạy mọi lệnh từ {palette}. |
| `tourSettingsTitle` | Make it yours | Chỉnh theo ý bạn |
| `tourSettingsBody` | Open Settings with {settings}. Everything is also in a plain text file. | Mở Cài đặt bằng {settings}. Mọi thứ cũng nằm trong một tệp văn bản thường. |
| `whatsNewTitle` | What’s new in {version} | Có gì mới ở bản {version} |
| `whatsNewDone` | Got it | Đã hiểu |
| `whatsNewMore` | See all changes | Xem mọi thay đổi |
| `emptyHintNewTab` | {shortcut} New tab | {shortcut} Tab mới |
| `emptyHintPalette` | {shortcut} Command palette | {shortcut} Bảng lệnh |
| `emptyHintSettings` | {shortcut} Settings | {shortcut} Cài đặt |
| `notificationsEmptyTitle` | No notifications yet | Chưa có thông báo |
| `notificationsEmptyBody` | A glowing ring appears on a pane when an agent needs you. | Một vòng sáng hiện ở pane khi agent cần bạn. |

Gợi ý phím không có (action bị `unbind`) → chuỗi dùng `withShortcut`/bỏ dòng (A9 D29), không bao giờ để trống ngoặc.

### 4.5 CLI (tiếng Anh, như A7 D11)

```
$ shellx doctor
✓ ShellX is running (socket reachable)
✓ CLI 1.2.0 matches the app
✗ shellx is not in your PATH — run: ShellX tray › Command line › Install in PATH
✓ Agent skills installed (~/.claude/skills/shellx)
✓ Configuration: no problems
1 problem found.
```
Mã thoát 0 khi không có ✗, 1 khi có. `--json`: một đối tượng `{ "checks": [{"id","ok","message"}] , "ok": bool }`.

### 4.6 Mobile

| Khoá | EN | VI |
|---|---|---|
| `machineLastUsed` | Last used | Dùng gần nhất |
| `machineTabsActivity` | {tabs} tabs · {unseen} with new output | {tabs} tab · {unseen} có chữ mới |
| `machineNewOutput` | New output | Có chữ mới |
| `machinesErrorTitle` | Couldn’t load your computers | Không tải được danh sách máy |
| `machinesRetry` | Try again | Thử lại |
| `machinesCheckConnection` | Check your internet connection. | Hãy kiểm tra kết nối mạng. |
| `machinesReload` | Reload | Tải lại |
| `arrowPadLabel` | Arrow pad. Drag to move the cursor. | Bàn xoay mũi tên. Kéo để di chuyển con trỏ. |
| `arrowPadUp` | Up | Lên |
| `arrowPadDown` | Down | Xuống |
| `arrowPadLeft` | Left | Trái |
| `arrowPadRight` | Right | Phải |
| `settingsFixedHeight` | Keep terminal size when the keyboard opens | Giữ cỡ terminal khi mở bàn phím |
| `settingsFixedHeightHint` | The keyboard covers the terminal instead of shrinking it. | Bàn phím che lên terminal thay vì làm nó co lại. |

---

## 5. Riêng tư và log

- **Không bao giờ log** (kể cả `debugPrint`, kể cả `kDebugMode`): chữ trong buffer, từ khoá tìm (tìm một terminal hay mọi terminal), đoạn trích kết quả, **giá trị** cài đặt (font, thư mục, màu, phím, lệnh), mô tả tab, tên workspace, đường dẫn thư mục người dùng, nội dung clipboard (kể cả chữ vừa `y` ở chế độ copy), chữ của mục "mở lại", nháp mobile, nội dung ghi chú phát hành. Cho phép: loại sự kiện (`settings_saved`, `reopen_closed`, `copy_mode_enter`), `runtimeType` của lỗi, **số** (số mục, số kết quả — **không** gắn với từ khoá), tên **khoá** cấu hình (`font-size`, không kèm giá trị).
- `toString()` của `SettingEdit`, `ClosedItem`, `CopyModeState`, `GlobalHit`, `TabMeta`, `FocusEntry` trả `'…'` (test ghim).
- **Bộ nhớ, không đĩa:** `ClosedItems` (chữ terminal), nháp mobile, đoạn trích tìm mọi terminal chỉ sống trong bộ nhớ; thoát app là mất. `layout.json` thêm `pinned/desc/status` — **mô tả do người dùng gõ có thể là bí mật**: cùng quyền 0600 và vị trí với `layout.json` (A5a §5), không bao giờ đưa lên điện thoại/relay/log; `shellx` CLI `ls` **không** in mô tả (A11 không thêm trường vào đầu ra CLI).
- Tệp cấu hình do người dùng sở hữu: Cài đặt chỉ ghi khi người dùng thao tác (D5); sao lưu tạm = chính cơ chế thay thế nguyên tử của A9 (không để lại bản sao).
- `last_seen_version` và `tour_done` là SettingsStore (không nhạy cảm).
- Chính sách riêng tư (`web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`): thêm một câu ở T23 — "Lịch sử tab vừa đóng chỉ nằm trong bộ nhớ của máy tính, mất khi thoát ứng dụng".

## 6. Lỗi và biên

| Tình huống | Hành vi |
|---|---|
| Mở Cài đặt khi tệp cấu hình chưa tồn tại | Hiển thị mặc định; ghi lần đầu tạo tệp từ mẫu (A9 D37) rồi thêm khối |
| Tệp không đọc được / UTF-16 / quá lớn | Mọi điều khiển của khoá-tệp bị khoá + banner "Không ghi được: {lý do}" + "Mở tệp" |
| Khoá do include đặt | Hàng chỉ đọc (D5.4) |
| Hai dòng cùng khoá trong tệp chính | Sửa dòng **cuối** (đang hiệu lực) |
| Khoá bị thay đổi bởi người dùng sửa tay trong lúc Cài đặt mở | Điều khiển theo `ConfigState` mới (watcher A9); ghi đang dở thất bại `expected` → toast `settingsFileChanged` |
| Giá trị gõ không hợp lệ | Lỗi dưới ô, không ghi (D6) |
| Xem trước chủ đề không tồn tại / tệp hỏng | Mẫu dùng bảng màu ShellX + dòng lỗi dưới danh sách |
| Công tắc app thất bại (ví dụ cài PATH cần mật khẩu bị huỷ) | Thông báo có sẵn của `TrayActions` (cùng đường), công tắc về trạng thái thật |
| Chưa đăng nhập, trang Điện thoại | Dòng bị khoá + "Đăng nhập" |
| `edit_line` ở pane đã thoát / màn hình thay thế | Không làm gì, phím rơi xuống terminal |
| Triple-click trên dòng rỗng | Chọn dòng rỗng (không lỗi) |
| ⌥-kéo khi chương trình bật chuột | Chọn (giữ ⌥); thả → về `line` |
| Chế độ copy ở pane thoát giữa chừng | Thoát chế độ, không lỗi |
| Chế độ copy, bộ đệm đang nhận cuộc ra | Con trỏ copy theo **neo** (`CellAnchor`) nên bám dòng khi cuộn; cuộc ra mới không kéo pane xuống đáy |
| `reopen_closed` khi rỗng | Toast `reopenNothing` |
| Mở lại tab mà workspace đã xoá | Vào workspace hiện tại |
| Mở lại pane mà tab cũ đã đóng | Thành tab mới |
| Đạt giới hạn phiên (`SessionLimit`) khi mở lại | Toast giới hạn (có sẵn); mục **giữ lại** trong lịch sử |
| Lịch sử focus trỏ tab đã đóng | Bỏ mục, thử mục kế |
| Ghim hết mọi tab của workspace | Hợp lệ; thứ tự giữ |
| Mô tả có xuống dòng/ký tự điều khiển | Xuống dòng → khoảng trắng; điều khiển bỏ; cắt 120 grapheme |
| `layout.json` cũ không có khoá mới | Mặc định (không ghim, không mô tả) |
| `swap_split` ở tab một pane | Không làm gì |
| `join_pane` sang tab không đủ chỗ | `PaneNoRoomNotice`, không đổi gì |
| `break_pane` pane đang phóng to (zoom) | Bỏ zoom trước khi tách |
| Tìm mọi terminal khi 0 pane | `searchAllNone` |
| Phím toàn cục bị chiếm | D22 |
| `background-opacity` ngoài khoảng | Kẹp + `outOfRange` (A9) |
| Mobile: chạm thông báo của máy chưa ghép | Không mở gì (giữ) |
| Mobile: `pendingSelect` mà tab không bao giờ xuất hiện | Hết hạn 30 s |
| Mobile: bàn xoay + bàn phím cứng | Độc lập |
| Mobile: cỡ cố định + xoay ngang | Đo lại như hôm nay (đổi hướng là đổi cỡ thật) |

## 7. Kiểm thử

- **Rust (`term/`):** `cargo test` — `doctor` (bảng kiểm với `env` giả, mã thoát), bí danh `config validate`, `new-tab` gửi `fromTab` khi có `SHELLX_TAB_ID` và không `--workspace`, không gửi khi có `--workspace`.
- **Desktop thuần:** `edit_line_test`, `triple_select_test`, `copy_mode_state_test`, `copy_mode_motions_test`, `closed_items_test`, `focus_history_test`, `shellx_config_a11_test` (khoá mới), `cursor_blinker_test` (`fake_async`), `config_key_edits_test` (**quan trọng nhất**: từng luật D5, CRLF/BOM, byte còn lại không đổi), `setting_validation_test`, `settings_schema_test` (mọi khoá `ShellxConfig` + mọi `TrayAction` công tắc có đúng một dòng; không dòng nào trùng khoá; tìm), `theme_listing_test`, `tab_meta_test` + `restore_snapshot_meta_test`, `workspace_zoom_test`, `pane_move_test` (hoán đổi/tách/chuyển trên cây), `global_search_test`, `whats_new_test`, `tour_state_test`.
- **Desktop widget:** `settings_overlay_test` (trang, tìm, khoá dòng, ghi), `settings_preview_test`, `settings_agents_test` (công tắc gọi đúng `TrayAction`), `copy_mode_ui_test`, `pin_describe_status_ui_test`, `reopen_closed_ui_test`, `search_all_ui_test`, `tour_ui_test`, `shortcut_golden_test` (thêm `a11Additions` + `a11Changes`).
- **Mobile:** `pending_select_test`, `machine_list_a11_test`, `unseen_output_test`, `draft_test`, `arrow_pad_test`, `cursor_shift_test` + `terminal_fixed_height_test` (đếm `resize`).
- **Tích hợp thật:** không thêm (A10 `pty_*` giữ).
- **Thử tay (⚠ MANUAL):** §9.

## 8. Review Focus

1. **Cài đặt làm hỏng tệp của người dùng** — mất dòng, mất chú thích, đổi CRLF, xoá nhầm dòng của người dùng khi "về mặc định", ghi khi chỉ mở trang, ghi đè bản người dùng vừa sửa tay. Ghim: `config_key_edits_test` (bất biến "mọi byte ngoài dòng đích giữ nguyên" bằng so sánh sau khi loại dòng đích, kiểm cả `\r\n` và BOM), `settings_overlay_test` ("opening writes nothing").
2. **Hai nguồn sự thật lệch nhau** — một khoá hiện ở khay và Cài đặt với giá trị khác nhau, hoặc ở cả tệp lẫn kho. Ghim: `settings_schema_test` (mỗi khoá đúng một chủ), `settings_agents_test` (khay và Cài đặt cùng provider).
3. **Kiểm tra giá trị tách khỏi bộ phân tích** — Cài đặt cho qua giá trị mà bộ nạp từ chối (tệp "đỏ" sau khi lưu). Ghim: `setting_validation_test` chạy **cùng** `buildShellxConfig`; mọi giá trị GUI ghi được đọc lại thành đúng giá trị đó (round-trip).
4. **Xem trước rò vào pane thật / không dọn** — Esc không bỏ xem trước; xem trước ghi tệp. Ghim: `settings_preview_test`.
5. **`edit_line` gửi Ctrl-A vào vim** hoặc vào pane đã thoát. Ghim: `edit_line_test` (màn hình thay thế → `isEnabled == false`).
6. **Chế độ copy nuốt phím sai chỗ** — rò phím ra chương trình, kẹt chế độ sau khi pane đóng/tab đổi, hỏng với bàn phím không Latin. Ghim: `copy_mode_ui_test` ("every key is swallowed", "exits when the pane goes", phím vật lý với `LogicalKeyboardKey.keyH` mà ký tự khác).
7. **Lịch sử đóng rò chữ hoặc nở vô hạn** — ghi đĩa, vượt 10/2 MiB, giữ tham chiếu `Terminal`. Ghim: `closed_items_test` (giới hạn, `toString`), `reopen_closed_ui_test` ("nothing written to disk": thư mục restore không đổi).
8. **Mở lại làm hai bản session / sai workspace / cướp focus.** Ghim: `terminal_tabs_restore_test` mở rộng.
9. **`layout.json` mới làm bản cũ hỏng hoặc bản mới đọc file cũ hỏng.** Ghim: `restore_snapshot_meta_test` (cả hai chiều, khoá lạ).
10. **Nhấp nháy ăn CPU hoặc làm con trỏ chương trình ẩn hiện sai.** Ghim: `cursor_blinker_test` (dừng khi mất focus, không đổi `wants`), đo số lần `notifyListeners`/giây ≤ 2 mỗi pane focus.
11. **Hoán đổi/chuyển pane làm mồ côi phiên** (shell còn chạy nhưng không có pane) hoặc đóng nhầm phiên. Ghim: `pane_move_test` (tập session id trước = sau).
12. **Phím toàn cục** — đăng ký rò khi thoát, bắt cả phím gõ thường. Ghim: lớp bọc `GlobalHotkey` có giao diện giả; test `unregisterAll` khi dispose; ⚠ thử tay.
13. **CLI mở tab ở workspace sai / cướp focus.** Ghim: `ui_command_handler` test mở rộng (fromTab, không focus).
14. **Mobile: `pendingSelect` chọn tab sai sau khi người dùng đã tự chọn**; đếm "chữ mới" không tắt khi xem; nháp rò sang tab khác; resize khi bật cỡ cố định. Ghim: `pending_select_test`, `unseen_output_test`, `draft_test`, `terminal_fixed_height_test`.
15. **Riêng tư** — test bắt `debugPrint` chạy qua tìm/đóng-mở/ghi cài đặt/copy mode, khẳng định không chứa chuỗi thử nghiệm.
16. **Trợ năng** — lớp phủ Cài đặt, tour, tìm mọi terminal: nhãn, bẫy focus, Esc, trả focus; chấm trạng thái có nhãn chữ; bàn xoay có hành động ngữ nghĩa.

## 9. ⚠ Kiểm tay (chỉ người ngồi trước Mac/điện thoại/Windows làm được)

Executor ghi từng mục "pending manual" vào ledger `## A11 — execution`; **task không gộp cho tới khi mục ⚠ của nó passed** (D35).

**Mac (macOS 13+, Retina, thêm màn hình ngoài nếu có):**
- ⚠ T1: zsh, bash, fish; Terminal gõ tiếng Việt Telex giữa dòng rồi ⌘←; `vim`, `less`, `htop`: ⌘← không gửi `Ctrl-A`; ⌥⌫ xoá đúng từ ở cả ba shell.
- ⚠ T3/T4: ⌥-kéo hình chữ nhật trong `ls -l`; chế độ copy với bàn phím ABC, Telex (gõ `y`, `v`), Hàn (2-set), Nhật (Kana) — `y`/`v`/`h` vẫn tác dụng; VoiceOver đọc chip.
- ⚠ T5: đóng/mở lại tab SSH và tab `claude`; mở lại 10 lần liền; kiểm `lsof -p <pid giao diện>` không mở tệp lạ.
- ⚠ T7: nhấp nháy mượt trên màn hình 60 và 120 Hz, CPU nhàn (Activity Monitor < 2 % khi nhấp nháy), `adjust-cell-height` với vim/htop không vỡ lưới.
- ⚠ T9/T10: Cài đặt ở cửa sổ nhỏ (640 px) và to; VoiceOver đi qua các trang; gõ Telex **vào ô tìm cài đặt** và ô font; đổi chủ đề/cỡ chữ khi đang chạy `htop`; sửa tay tệp trong lúc Cài đặt mở; chế độ tối/sáng hệ thống.
- ⚠ T12: kéo thả/menu chuyển pane khi đang chạy `top` ở pane đó — top vẫn chạy.
- ⚠ T16: tour lần đầu (xoá `tour_done` bằng cách xoá dữ liệu app), "Có gì mới" sau khi cài đè bản mới.
- ⚠ T17: phím toàn cục từ Safari/Slack/ở Space khác/khi màn hình khoá; phím bị app khác chiếm (⌘⇧Space của Spotlight? ⌃Space đổi bộ gõ — bị D25 A9 chặn).
- ⚠ T22: cửa sổ trong suốt + blur; kéo cửa sổ; Mission Control; chế độ tối/sáng; Stage Manager; toàn màn hình; **nếu cửa sổ nhấp nháy hoặc chữ vỡ → bỏ T22**.

**Windows 10 1809+/11:**
- ⚠ T1 (kiểm không có hồi quy Home/End/Ctrl+Backspace), T3/T4 (Alt-kéo), T5, T9/T10 (Notepad sửa tay song song), T17 (phím toàn cục với RDP/AltGr bàn phím Đức/Ba Lan).

**iPhone / Android thật:**
- ⚠ T2: tắt hẳn app, chạm thông báo (đã đăng nhập, mạng chậm) → đúng tab; chạm khi máy offline.
- ⚠ T18: gõ dở, sang tab khác, quay lại, xoay ngang, khoá màn hình.
- ⚠ T19: bàn xoay trong `vim`/`claude` (duyệt lịch sử); TalkBack/VoiceOver hành động; không kích hoạt nhầm khi cuộn thanh phím.
- ⚠ T20: tab có output nền (`yes | head`) → số "có chữ mới" đúng, tắt khi xem; Wi-Fi tắt → lỗi + Thử lại.
- ⚠ T21: bật cỡ cố định, mở bàn phím trong `vim` ở dòng cuối, trong `claude`; xoay ngang; đo `resize` trên máy tính (không có khi mở bàn phím).

## 10. Ngoài phạm vi A11

A12: hook agent + `shellx integrations install`, resume phiên agent, trạng thái Running/Needs-input/Idle trong sidebar, PR status qua `gh`, đặt mô tả/trạng thái từ CLI/hook, vạch scrollbar theo prompt agent. Hoãn không hẹn: "Open With" trong Finder, tự cài cập nhật, tìm regex, kéo thả pane giữa tab bằng chuột, nhóm workspace gập/ghim, mẫu bố cục, ligature (không thể với xterm 4.0.0), phím toàn cục kiểu "quick terminal" thả xuống, blur trên Windows, đặt cấu hình bằng CLI (`shellx config set`). Còn lại của §5 gap analysis: P2 (31–40).
