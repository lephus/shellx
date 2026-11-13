# ShellX cho Windows giống bản Mac: lộ trình và Phần 1 (Settings)

- **Ngày:** 2026-11-13
- **Trạng thái:** thứ tự các phần và phạm vi Settings đã được người dùng đồng ý trong hội thoại; văn bản này chờ người dùng duyệt.
- **Phạm vi:** app Windows trong `windows/` (Rust, GPUI `=0.2.2` đã chép vào repo). Bản Mac là chuẩn để so và không bị sửa.
- **Thay thế:** các đợt 2–5 của `2026-11-01-windows-mac-parity-design.md` (mục 3 ở dưới nói đợt nào thành phần nào). Các quy tắc của đặc tả đó và của `2026-11-12-shellx-windows-usable-design.md` vẫn giữ.
- **Tài liệu đi kèm:** `2026-11-13-mac-settings-inventory.md`, bảng kê từng dòng Settings của Mac đọc từ mã nguồn (`develop` feea7e57ba). Mọi tên dòng, khoảng giá trị và kích thước trong văn bản này lấy từ đó.

Chú thích nguồn: **[người dùng]** là lời hoặc lựa chọn của người dùng; **[người viết]** là quyết định của người viết, đổi được.

## 1. Ý định

Người dùng mở ShellX trên máy Windows và thấy thiếu nhiều thứ so với bản Mac, rõ nhất ở Settings:

- "hiện tại máy win chưa giống mac như ở setting" **[người dùng]**
- "tôi muốn giống 100% như bản cài trên mac" **[người dùng]**
- "lập kế hoạch cho cả chuỗi đi" **[người dùng]**

Người dùng đã đồng ý ba điều:

1. Settings trên Windows có cùng khung như Mac: cột trái chia nhóm, ô tìm kiếm, nội dung bên phải.
2. Năm mục mới chạy thật trước: Themes, Terminal, Keyboard Shortcuts, Workspace Colors, Sidebar. Mục của chức năng Windows chưa có thì chưa hiện.
3. "Giống 100%" là một chuỗi tám phần làm nối nhau, Settings là phần đầu, làm từ ngày 2026-11-14.

## 2. Hiện trạng đã kiểm chứng

| Điều | Nguồn |
|---|---|
| Hai app không chung mã giao diện. Mac: fork cmux, riêng `Sources/` khoảng 640 nghìn dòng Swift. Windows: khoảng 47 nghìn dòng Rust trong ba crate. | `wc -l` ngày 2026-11-13 |
| Kế hoạch giống Mac mới xong đợt 1 (2026-11-01). 214 commit Windows sau đó là đăng nhập và vòng "Windows dùng được" (1.7.1). Đợt 2–5 chưa bắt đầu. | `git log f492af36f2..develop -- windows` |
| Settings của Mac: cửa sổ riêng 980×680, cột trái 210 chia 8 nhóm, 22 mục, có tìm kiếm. Tám mục được kê chi tiết có hơn 300 dòng. | bảng kê, mục D và các bảng 1–8 |
| Settings của Windows: một tấm phủ trong cửa sổ chính, 6 mục: Tài khoản, Terminal (chọn shell), Hiển thị, Cập nhật, Ngôn ngữ, Giới thiệu. | `windows/shellx-app/src/ui/settings.rs` |
| Windows chỉ có một bộ màu cố định: `shellx-model/src/palette.rs` là hằng số; `ui/theme.rs` bọc chúng thành hàm (139 chỗ gọi), nhưng app còn 27 chỗ gọi thẳng `palette::` và 45 màu viết tay. | `grep` ngày 2026-11-13 |
| Phím tắt Windows viết cứng trong `shellx-model/src/keys.rs` (`app_binding`), 14 lệnh `AppCommand`. | file đó |
| Windows chỉ lưu một cài đặt: `settings.json` trong thư mục native, dạng `{"shell": …}`. | `shellx-app/src/local_pty/settings.rs` |
| Terminal Windows: phông JetBrains Mono cỡ 14, lề 6, scrollback 10 MB, đều là hằng số. Chưa vẽ thanh cuộn, con trỏ chưa nhấp nháy. | `ui/term_view.rs`, `term_core.rs` |
| Mọi workspace Windows có vạch màu tím cố định `RAIL_PURPLE`. Thẻ workspace chưa có menu chuột phải. | `ui/sidebar.rs` |
| Bản Mac phát hành với `remoteMachines = false` và relay không gửi `can_host`, nên PC chưa mở được terminal của Mac. | `ShellXFeatures.swift:3`, `shellx-core/src/api.rs` |
| Giao diện sáng của chính bản Mac chưa được rà hết (Tasks 4–7 của kế hoạch appearance chưa làm). | ghi chú phát hành 1.7.0 |
| Ở đây không có máy Windows. Giao diện Windows build và chụp ảnh được trên Mac (`windows/dev/mac-shot.sh`); mã chỉ dành cho Windows được biên dịch kiểm bằng `scripts/shellx/check-windows-build.sh`. | `windows/README.md` |

## 3. Lộ trình tám phần

Mỗi phần kết thúc bằng một bản cài thử để người dùng kiểm trên máy Windows thật. Mỗi phần từ 2 trở đi có đặc tả và kế hoạch riêng, viết khi tới lượt; văn bản này chỉ chốt thứ tự, thứ người dùng sẽ thấy, và các dòng Settings mà phần đó mở ra. Thứ tự do người dùng duyệt **[người dùng]**.

| Phần | Người dùng thấy gì khi xong | Mở thêm trong Settings | Phụ thuộc và rủi ro chính |
|---|---|---|---|
| **1. Settings** | Cửa sổ Settings như Mac; đổi theme, phông, phím tắt, màu workspace, sidebar và thấy ngay | Themes, Terminal, Keyboard Shortcuts, Workspace Colors, Sidebar, App, Reset (các dòng ở mục 5.4) | Bộ điều khiển giao diện mới; cửa sổ thứ hai của GPUI trên Windows |
| **1b. Terminal và App còn lại** **[người viết]** | Thanh cuộn terminal, con trỏ nhấp nháy, báo đã chép, hỏi trước khi đóng tab/workspace/cửa sổ, phóng to chữ toàn app | Các dòng Terminal và App ghi "1b" ở mục 5.4 | Nhỏ; gộp vào đầu Phần 2 nếu người dùng muốn |
| **2. Bảng lệnh và thông báo** (đợt 2 cũ) | Ô tìm kiếm trên header mở bảng lệnh; chuông mở bảng thông báo; vòng sáng quanh ô có thông báo | Các dòng thông báo trong App, Sidebar, Workspace Colors; hai dòng bảng lệnh | Thông báo đến từ chuỗi OSC của terminal; thông báo Windows (toast) cần AppUserModelID |
| **3. Workspace** (đợt 2 cũ) | Nhóm workspace, menu chuột phải đầy đủ trên thẻ, đổi tên, mô tả, màu tuỳ chọn, kéo thả sắp xếp, mở lại phiên sau khi tắt app | Mô tả workspace, "Choose Custom Color…", Workspace Layouts, Resume Commands | Khôi phục phiên là phần lớn nhất |
| **4. Agent** (đợt 3 cũ) | Thẻ hiện "claude-code · Working", cần nhập, xong; thông báo theo agent | Các dòng agent trong Terminal, Sidebar, App; "Open in Terminal…" của Themes | Cần lệnh `shellx` cho Windows và hook của từng agent |
| **5. Sidebar phải** (đợt 4 cũ) | Cây file, tìm trong thư mục, Git và Git Graph, nút bật trên header | Thẻ "Right Sidebar Tabs", Dock Max Width | Git Graph phải viết lại bằng Rust |
| **6. Trình duyệt và xem file** (đợt 5 cũ) | Tab trình duyệt nhúng (WebView2), xem Markdown, sửa file | Mục Browser, Import Browser Data; các dòng Markdown và File Editor của App | WebView2 nhúng vào cửa sổ GPUI chưa ai thử |
| **7. Automation** | Tạo và chạy automation, sơ đồ luồng | Mục Automation | Phụ thuộc Phần 4 |
| **8. Điện thoại và máy khác** | Ghép iPhone/Android bằng QR, PC mở terminal của Mac và ngược lại | Mục Mobile, Devices, Networking | Cần quyết định phía relay và bản Mac (mục 7.2 của đặc tả 2026-11-12) |

Chưa xếp vào phần nào, làm sau Phần 8 hoặc chen vào khi người dùng cần **[người viết]**: TextBox, Sleepy Mode, Global Hotkey, Beta Features, file `shellx.json`, Custom Sidebars, Computer Use, Cloud, trình đọc màn hình.

Không bao giờ có trên Windows vì gắn với macOS: App Icon, Dock Badge, Menu Bar Only, Show in Menu Bar, Option as Alt, Background Blur kiểu macOS, tmux cục bộ, Import from Another Terminal (đọc cấu hình app Mac). Mỗi thứ này được ghi "không áp dụng" thay vì "thiếu".

Ước lượng của người viết, chưa phải số đo: mỗi phần từ một đến vài ngày làm việc của agent, cộng thời gian người dùng kiểm trên máy thật. Phần 3, 5, 6 và 8 là các phần dài.

## 4. Quy tắc cho mọi phần

1. **Không có nút chết.** Một dòng, nút hay mục chỉ hiện khi nó làm được việc nó ghi. Thứ chưa làm được thì chưa hiện.
2. **Mặc định theo Mac.** Mục tiêu là giống Mac, nên giá trị mặc định của mỗi dòng là giá trị mặc định của Mac, kể cả khi Windows hiện đang làm khác. Bản cập nhật vì thế đổi một số thứ người dùng Windows đang thấy; mỗi phần phải liệt kê đủ các thay đổi đó (Phần 1: bảng ở cuối mục 5.4). Ngoại lệ phải ghi rõ lý do. **[người viết, suy từ "giống 100%" của người dùng; xem mục 7, điểm 1]**
3. **Không mất phím.** Không phím nào bị nuốt im lặng. Trên GPUI-Windows, `stop_propagation` trên một lần nhấn phím chữ làm mất ký tự (không có `WM_CHAR`), nên mỗi trình xử lý phím chỉ chặn đúng phím nó dùng.
4. **Chữ lấy từ Mac.** Tiếng Anh chép đúng `defaultValue` của Mac; tiếng Việt lấy từ bảng chuỗi tiếng Việt của Mac khi có, không thì dịch theo giọng các chuỗi Windows đang có. Hai bảng nằm trong `shellx-model/src/strings.rs`.
5. **Kích thước lấy từ Mac**, đổi điểm (pt) thành pixel logic 1:1.
6. **Công nghệ giữ nguyên:** Rust, GPUI `=0.2.2` trong repo, libghostty-vt, ConPTY. Không thêm crate nếu kế hoạch không ghi lý do. Không webview cho giao diện chính.
7. **Màu:** màu mềm, không nút gradient, không phát sáng; primary `#60a5fa`; đang chạy màu vàng.
8. **Quy tắc là hàm thuần có test** trong `shellx-model`, chạy được trên Mac. Test đỏ được commit trước bản sửa.
9. **Không đụng app ShellX đang chạy của người dùng** trên Mac (`/Applications/ShellX.app`).
10. **Bản cài thử không phải bản phát hành.** Nó mang nhãn thử, không đè bản công khai, không tự cập nhật người dùng thật. Phát hành là quyết định của người dùng sau khi kiểm.

## 5. Phần 1: Settings

### 5.1 Mục tiêu

1. `Ctrl+,` và nút bánh răng mở một cửa sổ Settings bố cục như Mac.
2. Mọi dòng trong mục 5.4 đổi được và có tác dụng ngay trên các cửa sổ và terminal đang mở, trừ các dòng ghi "chỉ áp dụng cho terminal mở sau".
3. Mọi cài đặt còn nguyên sau khi tắt mở app.
4. Sáu mục Windows đang có vẫn đủ, không mất dòng nào.
5. Với cài đặt mặc định, cửa sổ chính chỉ khác bản 1.7.1 ở đúng các điểm trong bảng "Thay đổi so với 1.7.1" cuối mục 5.4; màu khung app không đổi.

### 5.2 Phản mục tiêu

Làm xong vẫn là thất bại nếu xảy ra một trong các điều sau:

- cửa sổ chính với cài đặt mặc định khác bản 1.7.1 ở một điểm không có trong bảng "Thay đổi so với 1.7.1";
- một dòng hiện ra mà không làm gì, hoặc cần khởi động lại mà không nói;
- gõ chữ thường hoặc tiếng Việt qua Unikey vào ô tìm kiếm, ô mã màu, ô ghi phím tắt bị mất hay lặp ký tự;
- người dùng tự khoá mình: một phím tắt mới làm không mở lại được Settings bằng chuột, hoặc một theme làm chữ trên sidebar không đọc được;
- `settings.json` hỏng làm app không mở được, hoặc bị ghi đè mất phần người dùng đã có;
- file cài đặt, log hay báo cáo chẩn đoán chứa token, email hoặc nội dung terminal.

### 5.3 Cửa sổ và khung

- **Cửa sổ riêng**, như Mac: tiêu đề "Settings" / "Cài đặt", cỡ nội dung 980×680, nhỏ nhất 820×540, đổi cỡ được, có nút đóng, không thu nhỏ. Lý do chọn cửa sổ riêng thay cho tấm phủ: người dùng nhìn thấy terminal đổi theme, phông, màu ngay bên cạnh khi đang chỉnh. **[người viết]**
  - Mở lần hai thì đưa cửa sổ đang có lên trước, không mở thêm.
  - `Esc` đóng cửa sổ khi không có menu hay ô ghi phím đang mở. Đóng cửa sổ chính thì cửa sổ Settings đóng theo.
  - Vị trí và cỡ được nhớ. Mục đang xem được nhớ; lần đầu mở là Tài khoản.
  - Lớp phủ bắt buộc cập nhật và hộp đăng nhập vẫn thuộc cửa sổ chính. "Đăng nhập…" trong Tài khoản đưa cửa sổ chính lên trước và mở hộp đăng nhập ở đó.
  - **Đường lùi:** nội dung Settings là một khối giao diện không biết nó nằm trong cửa sổ nào. Nó chạy được ở hai chỗ: cửa sổ riêng (mặc định) và tấm phủ trong cửa sổ chính với cùng bố cục. Biến môi trường `SHELLX_SETTINGS_HOST=panel` ép dùng tấm phủ, và app tự dùng tấm phủ khi không mở được cửa sổ thứ hai. Nhờ vậy nếu trên máy thật cửa sổ riêng không nhận phím, không gõ được tiếng Việt hay không vẽ được nút cửa sổ, người dùng vẫn chạy tiếp được danh sách kiểm mà không chờ bản build khác. Danh sách kiểm ghi cách đặt biến này.
- **Cột trái** rộng 210: ô tìm kiếm ở trên, rồi các nhóm. Mỗi dòng mục có biểu tượng (ô 16) và tên.
- **Bên phải:** một mục mỗi lúc, cuộn dọc; lề 20, khoảng cách giữa các thẻ 14. Tiêu đề thẻ 13 đậm vừa, màu phụ. Thẻ bo góc 13, viền 1. Dòng: lề ngang 14, dọc 9; tên 13 đậm vừa; chú thích 10, màu phụ, tối đa 2 dòng; vạch chia 1 giữa các dòng.

Nhóm và mục hiện trong Phần 1, theo thứ tự của Mac:

| Nhóm | Mục hiện | Mục của Mac chưa hiện |
|---|---|---|
| General | Account, App, Themes | Sleepy Mode |
| Terminal | Terminal | TextBox |
| Workspace | Workspace Colors | |
| Sidebar & Dock | Sidebar | Custom Sidebars |
| Agents & Automation | (cả nhóm chưa hiện) | Automation, Computer Use |
| Browser & Files | (cả nhóm chưa hiện) | Browser, Import Browser Data |
| Remote & Devices | (cả nhóm chưa hiện) | Mobile, Cloud, Devices, Networking |
| Keyboard & Advanced | Keyboard Shortcuts, Reset | Global Hotkey, Beta Features, shellx.json |
| ShellX (chỉ Windows) **[người viết]** | Updates, About | |

Nơi ở mới của sáu mục cũ **[người viết]**: Tài khoản thành mục Account; chọn shell và Hiển thị thành hai thẻ trong mục Terminal; Ngôn ngữ thành dòng đầu của mục App; Cập nhật và Giới thiệu thành hai mục trong nhóm "ShellX" ở cuối, vì Windows không có thanh menu để chứa chúng như Mac.

### 5.4 Các dòng của Phần 1

Cột "Mặc định" theo quy tắc 2 ở mục 4 (mặc định của Mac); chữ đậm là chỗ khác hành vi Windows hiện nay hoặc là ngoại lệ. Dòng của Mac không có trong các bảng dưới thì chưa hiện; bảng "Chưa hiện" nói nó về ở phần nào.

**Themes**

| Dòng | Điều khiển | Mặc định | Ghi chú |
|---|---|---|---|
| Appearance | Ba ô hình: System / Light / Dark | Dark | System theo chế độ sáng/tối của Windows và đổi theo khi Windows đổi |
| Accent Color | ShellX Blue / System / Custom, kèm ô màu khi Custom | ShellX Blue `#60a5fa` | System lấy màu nhấn của Windows. Tô workspace đang chọn, viền tiêu điểm và các điểm nhấn ShellX tự vẽ |
| Terminal Theme | Dòng tóm tắt "Light: X · Dark: Y" và nút Revert khi vừa đổi | Light: Catppuccin Latte · Dark: ShellX | Revert trả cặp trước đó |
| (thư viện theme) | Ô "Search all themes", hai nhóm "Dark Themes" / "Light Themes" (nhóm đang dùng đứng trước), lưới thẻ xem trước | — | Bấm thẻ đặt theme cho phía của nhóm đó và terminal đổi ngay |

Chưa hiện: App Icon (không áp dụng), nút "Open in Terminal…" (Phần 4).

**Terminal**

| Dòng | Điều khiển | Mặc định | Ghi chú |
|---|---|---|---|
| (thẻ Shell hiện có) | như hiện nay | Tự động | không đổi |
| (thẻ Hiển thị hiện có) | như hiện nay | như hiện nay | không đổi |
| Tab Bar Font Size | Thanh trượt 8–14, bước 0,5, nút Reset | 11 | Windows hiện đã là 11 |
| Scroll Speed | Thanh trượt 0,25–3,0, bước 0,05, nút Reset | 1,00× | Nhân với quãng cuộn hiện tại |
| Copy on Selection | Công tắc | tắt | |
| Confirm Unsafe Pastes | Công tắc | **bật (ngoại lệ, Mac là tắt)** | Chính là thanh hỏi trước khi dán nhiều dòng đang có. Giữ bật vì PowerShell và Command Prompt chạy ngay từng dòng được dán |
| Font | Danh sách: Default và các họ phông đơn cách đã cài | Default (JetBrains Mono) | |
| Font Size | Ô tăng giảm 4–96, bước 0,5 | **13** | Windows hiện là 14 |
| Cursor Style | Block / Bar / Underline / Hollow | Block | |
| Horizontal Padding | Ô tăng giảm 0–200 | **2** | Windows hiện là 6 |
| Vertical Padding | Ô tăng giảm 0–200 | **2** | Windows hiện là 6 |
| Scrollback Limit | Ô số, MB, 0–100000 | **50 MB** | Windows hiện là 10. Chỉ áp dụng cho terminal mở sau |
| Middle-Click Paste | Công tắc | **bật** | Windows hiện chỉ chuyển tiêu điểm. Lần bấm đầu lên ô chưa có tiêu điểm vẫn chỉ chuyển tiêu điểm, như chuột phải |

Chưa hiện, về ở Phần 1b: Show Terminal Scroll Bar, Blinking Cursor, Show Copy Confirmation, Reflow Hard-Wrapped Text on Copy, Session Content Width và Alignment, Background Opacity, Text Editing Gestures (cần bản đồ phím cho Windows), Runaway Memory Guardrail. Về ở Phần 3: Resume Commands. Về ở Phần 4: các dòng agent, Password Input Indicator. Về ở Phần 8: Predictive Local Echo. Không áp dụng: Import from Another Terminal, Option as Alt, Background Blur, tmux cục bộ, ba dòng thu hồi bộ vẽ (đặc thù bộ vẽ của Mac).

**Keyboard Shortcuts**

| Dòng | Điều khiển | Ghi chú |
|---|---|---|
| (thanh tìm) | Ô "Search shortcuts", nút "Detect Shortcut" / "Listening…", nút xoá | Lọc theo chữ hoặc theo tổ hợp phím vừa nhấn |
| Một dòng cho mỗi lệnh Windows có | Nút ghi phím (rộng 160) và nút X | X bỏ gán; sau khi bỏ, X đổi thành mũi tên khôi phục |
| Reset Default Shortcuts | Nút "Reset Defaults" | Trả mọi lệnh về phím mặc định |

- Lệnh có dòng: 14 lệnh `AppCommand` hiện có, thêm Back và Forward (hiện chỉ là nút trên header). Tên dòng và `actionId` lấy từ lệnh tương ứng của Mac trong bảng kê mục B khi có; lệnh Windows không có lệnh tương ứng thì đặt tên theo README.
- Phím mặc định là các phím đang ghi trong `windows/README.md`. Các phím phụ đang có (`Shift+Insert`, `Ctrl+PageUp`, `Ctrl+PageDown`) giữ làm phím phụ cố định, không có dòng; khi người dùng gán chính tổ hợp đó cho lệnh khác thì phím phụ nhường.
- Quy tắc nhận một tổ hợp **[người viết]**: phải có Ctrl hoặc Alt, hoặc là một phím F1–F12. Bị từ chối kèm một câu giải thích: phím trần, `Alt+F4`, `Alt+Space`, tổ hợp có phím Windows, và `Ctrl+Alt+…` (Windows coi là AltGr, tức là chữ).
- Tổ hợp `Ctrl+chữ` không có Shift được nhận, kèm chú thích dưới dòng rằng phím này sẽ không còn tới shell.
- Trùng phím: như Mac, tổ hợp bị từ chối và không lưu, hiện dải báo đỏ nêu tên lệnh đang giữ phím đó, có nút Undo.
- Trong lúc ô ghi phím đang nghe, phím nhấn không chạy lệnh nào của app; `Esc` thôi ghi.
- Mọi nơi hiện phím tắt (tooltip, menu "+ ▾", menu trợ giúp) đọc từ bảng phím hiện hành.
- Nút bánh răng luôn mở được Settings, kể cả khi lệnh Settings bị bỏ gán.

Chưa hiện: Base Keymap, Shortcut Chords (cần `shellx.json`), Show Shortcut Hints While Holding Modifier Keys (Phần 2), Pane Resize Step (Phần 3, khi có lệnh đổi cỡ ô bằng phím).

**Workspace Colors**

| Dòng | Điều khiển | Mặc định | Ghi chú |
|---|---|---|---|
| Workspace Color Indicator | Left Rail / Solid Fill | Left Rail | |
| Subtle Selection Highlight | Công tắc; mờ khi Solid Fill | bật | |
| Brighten Colors in Dark Mode | Công tắc; mờ khi Left Rail | bật | |
| Unselected Fill Opacity | Thanh trượt 0–1, bước 0,05; mờ khi Left Rail | 70% | |
| Selection Highlight | Ô màu, nhãn mã màu hoặc "Default", nút Reset khi đã đổi | Default (theo Accent) | |
| 16 dòng bảng màu | Ô màu, mã màu, chú thích "Base: #HEX" | 16 màu của Mac (bảng kê mục C) | Đổi một màu thì mọi workspace dùng tên màu đó đổi theo |
| Reset Palette | Nút "Reset" | — | |

Để mục này có nghĩa, Phần 1 thêm một menu chuột phải tối thiểu trên thẻ workspace **[người viết]**: mục "Workspace Color" mở danh sách 16 màu và "Clear Color". Workspace mới vẫn là Purple. Màu của workspace sống tới khi tắt app, vì Windows chưa khôi phục phiên (Phần 3).

Chưa hiện: Notification Badge và Pane Flash (Phần 2); "Choose Custom Color…" và các màu "Custom N" (Phần 3).

**Sidebar**

| Dòng | Điều khiển | Mặc định | Ghi chú |
|---|---|---|---|
| Sidebar Background | Follow Theme / Match Terminal / Custom Color | Follow Theme | |
| Sidebar Color | Ô màu; chỉ hiện khi chọn Custom Color | `#100B1D` | |
| Sidebar Font Size | Thanh trượt 10–20, bước 0,5, nút Reset | **12,5** | Tên workspace Windows hiện là 12. Co giãn tên workspace, dòng phụ và nhãn theo cùng tỉ lệ |
| Hide All Sidebar Details | Công tắc | tắt | Bật thì chỉ còn tên workspace; các dòng bên dưới mờ đi |
| Wrap Workspace Titles in Sidebar | Công tắc | tắt | |
| Truncate Path From Start | Công tắc | tắt | Tắt: cắt ở cuối đường dẫn. Nếu Windows hiện cắt khác thì ghi vào bảng thay đổi |
| Show Branch + Directory in Sidebar | Công tắc | bật | |

Chưa hiện: các dòng thông báo (Phần 2); mô tả workspace, Sidebar Branch Layout, Stack Branch and Directory (Phần 3); các dòng agent, log, tiến độ, metadata (Phần 4); Dock Max Width, thẻ Right Sidebar Tabs, PR, Watch Git Status, cổng đang nghe (Phần 5); mở liên kết trong trình duyệt ShellX (Phần 6); SSH (Phần 8). Không áp dụng cho tới Phần 8: Show Cloud and Device Icons.

**App**

| Dòng | Điều khiển | Mặc định | Ghi chú |
|---|---|---|---|
| Language | System / English / Tiếng Việt | System | Áp dụng ngay nếu làm được; không thì hiện "Restart ShellX to apply" như Mac. `SHELLX_LANG` vẫn thắng và dòng này nói rõ khi biến đó đang đặt |
| New Workspace Placement | Top / After current / End | After current | Windows hiện đã đặt sau workspace đang đứng |
| Inherit Workspace Working Directory | Công tắc | bật | Workspace mới mở ở thư mục của workspace đang đứng. Nếu Windows hiện mở ở thư mục nhà thì ghi vào bảng thay đổi |
| Keep Workspace Open When Closing Last Surface | Công tắc | tắt | Tắt: đóng terminal cuối thì workspace đóng theo. Workspace cuối cùng vẫn được thay bằng một terminal mới như hiện nay |
| Include Panes and Tabs in Focus History | Công tắc | **tắt** | Back/Forward của Windows hiện đi qua cả vùng chia; mặc định mới chỉ đi qua workspace |
| Equalize Splits on Create | Công tắc | tắt | |
| Hide Tab Close Button | Công tắc | tắt | |

Chưa hiện, về ở Phần 1b: Global Font Magnification, nhóm "Warn Before…" (Quit, Closing Tab, Tab Close Button, Closing Workspace, Closing Window), Focus Pane on First Click. Các dòng còn lại của App về theo phần của chức năng tương ứng (thông báo: Phần 2; layout: Phần 3; agent: Phần 4; file và Markdown: Phần 6). Không áp dụng: App Icon, Dock Badge, Menu Bar Only, Show in Menu Bar.

**Reset:** một nút "Reset All Settings" ở giữa, không hỏi lại, như Mac. Nó trả mọi cài đặt của mục 5.4 về mặc định, kể cả shell đã chọn và phím tắt. Nó không đăng xuất, không đụng `links.json`, không đụng chế độ hiển thị đã nhớ (`render.json`).

**Account, Updates, About:** nội dung và hành vi như hiện nay, vẽ lại bằng thẻ và dòng của khung mới.

**Thay đổi so với 1.7.1 khi chưa chỉnh gì** (hệ quả của quy tắc 2; người làm bổ sung dòng nào phát hiện thêm, không được có thay đổi nào ngoài bảng):

| Thứ thay đổi | 1.7.1 | Sau Phần 1 (như Mac) |
|---|---|---|
| Cỡ chữ terminal | 14 | 13 |
| Lề trong của terminal | 6 | 2 |
| Scrollback của terminal mở sau | 10 MB | 50 MB |
| Tám màu ANSI (ô 0, 5, 6, 8, 10, 11, 13, 14) | bảng `ANSI` trong `palette.rs` | file theme `ShellX` |
| Vùng chọn trong terminal | primary 30%, chữ giữ màu | nền `#233356`, chữ `#e6e2f2` |
| Thẻ workspace đang chọn | nền `#1a1430`, viền `#2a2145` | nền pha màu nhấn và viền mảnh như Mac (Subtle Selection Highlight bật) |
| Cỡ chữ sidebar | tên workspace 12 | 12,5, các chữ khác theo cùng tỉ lệ |
| Chuột giữa trong terminal | chỉ chuyển tiêu điểm | dán |
| Back/Forward | đi qua workspace và vùng chia | chỉ đi qua workspace |
| Vạch màu của workspace | vạch `#6a1b9a` cao hết thẻ, sát mép trái | vạch Purple làm sáng như Mac (`#7f1dba`), rộng 3, cách mép 3 và 5, bo tròn đầu |
| Thư mục của workspace mới | thư mục nhà | thư mục của terminal đang chọn (Inherit Workspace Working Directory bật); về thư mục nhà khi không biết thư mục đó hoặc thư mục đã mất |

Không đổi: bộ màu khung app (trùng `ShellXPalette` của Mac), phông JetBrains Mono, vị trí workspace mới, cỡ chữ thanh tab, và việc hỏi trước khi dán nhiều dòng.

### 5.5 Theme và màu

- **Nguồn theme:** 464 file theme Ghostty trong `Resources/ghostty/themes` (1,8 MB), gồm `ShellX`. Chúng được đóng vào file exe lúc build bằng build script, không chép thành bản thứ hai trong repo **[người viết]**. Các script build chéo hiện chỉ đóng gói `windows`, `cmux-tui` và `shellx-core`, nên phải thêm thư mục theme vào gói. App còn đọc thêm thư mục `themes` trong thư mục native của người dùng; tên trùng thì file của người dùng thắng.
- **Một nguồn cho màu terminal:** file theme `ShellX` là nguồn duy nhất của màu terminal mặc định. Bảng `ANSI`, `TERM_*` trong `palette.rs` bị bỏ; một test canh rằng theme ShellX được đóng vào exe khớp file trong `Resources/`.
- **Một theme định nghĩa:** `background`, `foreground`, `cursor-color`, `cursor-text`, `selection-background`, `selection-foreground`, `palette` 0–15. Khoá thiếu: `cursor-color` lấy `foreground`, `cursor-text` lấy `background`, màu vùng chọn đảo nền và chữ (như mặc định của Ghostty), còn lại lấy giá trị của theme ShellX.
- **Sáng hay tối:** độ sáng `0,299R + 0,587G + 0,114B` của `background` dưới 0,5 là tối; không có `background` là tối.
- **Cặp sáng/tối:** lưu hai tên. Appearance quyết định phía nào đang dùng. Bấm một thẻ chỉ đổi phía của nhóm chứa thẻ đó.
- **Terminal** lấy nền, chữ, con trỏ, vùng chọn và 16 màu ANSI từ theme đang dùng. Mọi ô terminal đang mở vẽ lại ngay.
- **Khung app** (nền, panel, viền, chữ, chữ phụ) được suy ra từ theme đang dùng bằng một hàm thuần:
  - theme ShellX cho ra đúng bộ màu `palette.rs` hiện nay, từng giá trị;
  - theme khác: các tầng nền đi từng bước từ `background` về phía `foreground`; chữ lấy từ `foreground`;
  - sidebar theo quy tắc của Mac: theme tối khác ShellX thì nền sáng thêm 2%, theme sáng thì tối thêm 3%; màu chữ sidebar chọn theo độ đọc được của nền;
  - mỗi theme trong 464 theme phải cho chữ chính trên nền đạt tương phản ít nhất 4,5:1 và chữ phụ ít nhất 3:1; hàm tự đẩy màu chữ ra xa nền cho tới khi đạt. Có test chạy qua cả 464 theme.
- **Màu nhấn (Accent)** tô: thẻ workspace đang chọn, vạch dưới tab đang chọn của vùng có tiêu điểm, con trỏ và viền tiêu điểm của ô nhập, nút chính (nền 12%, viền 45%, chữ là màu nhấn đã chỉnh cho đủ tương phản), liên kết, và ô sáng của kết quả tìm kiếm. Với ShellX Blue trên theme ShellX, nút chính cho ra đúng các màu hiện nay (chữ `#93c5fd`); đây là một ca test cố định. Thẻ đang chọn theo cách vẽ của Mac cho cả hai trạng thái của Subtle Selection Highlight và cho Solid Fill; độ pha và độ dày viền lấy từ mã Mac.
- **Màu trạng thái** (đang chạy vàng, xong xanh, lỗi đỏ) giữ nguyên sắc ở mọi theme, không theo màu nhấn. Nền và chấm trạng thái giữ đúng mã màu. Chữ vẽ bằng màu trạng thái hoặc màu nhấn (nhãn pill, chữ nút, liên kết) được hàm suy màu chỉnh đậm nhạt cho tới khi đạt 4,5:1 trên nền của nó; test 464 theme phủ cả các chữ này. Trên theme ShellX kết quả phải là đúng màu hiện nay.
- Nút Google giữ nguyên màu theo quy định của Google.
- Sau thay đổi này, app không còn chỗ nào gọi thẳng hằng màu của `palette.rs` hay viết màu tay cho khung; tất cả đi qua `ui/theme.rs`. Có một test canh việc này.
- **Ô màu:** GPUI không có hộp chọn màu của hệ thống. Ô màu là một ô vuông bấm được, mở một bảng nhỏ gồm ô nhập `#RRGGBB` và một lưới màu gợi ý (16 màu bảng màu và 16 màu ANSI của theme) **[người viết]**. Mã không hợp lệ thì không lưu và ô báo đỏ.

### 5.6 Lưu trữ

- Một file: `settings.json` trong thư mục native (file đang giữ `{"shell": …}`); khoá `shell` giữ nguyên dạng.
- Khoá mới dùng đúng đường dẫn `shellx.json` của Mac khi Mac có (ví dụ `app.appearance`, `app.accentColor`, `terminal.scrollSpeed`, `workspaceColors.indicatorStyle`, `shortcuts.bindings`), để sau này file `shellx.json` của Windows khớp với Mac. Dòng Mac lưu ở chỗ khác (cặp theme, phông, cỡ chữ, con trỏ, lề, scrollback, cỡ chữ sidebar và thanh tab) dùng tên khoá Ghostty tương ứng dưới một khoá `terminalConfig` **[người viết]**.
- File chỉ chứa giá trị khác mặc định. Khoá app không biết được giữ nguyên khi ghi lại.
- Ghi an toàn: ghi ra file tạm rồi đổi tên. File không đọc được thì đổi tên thành `settings.json.bad-<giây unix>`, ghi một dòng log không kèm nội dung, và app chạy với mặc định, như `links.json` hiện nay.
- Giá trị ngoài khoảng bị kẹp về khoảng; giá trị sai kiểu bị bỏ qua từng khoá, không làm hỏng các khoá khác.
- Thanh trượt và ô số ghi file sau khi người dùng ngừng kéo một nhịp ngắn, không ghi theo từng điểm ảnh.
- **Nhiều ShellX cùng chạy:** mỗi lần mở app là một tiến trình riêng và tất cả dùng chung một `settings.json`. Một thay đổi có tác dụng ngay trong tiến trình vừa chỉnh; tiến trình khác nhận ở lần mở sau. Phần 1 không theo dõi file **[người viết]**. Để tiến trình cũ không ghi đè giá trị mới: mỗi lần ghi là đọc lại file rồi chỉ đổi đúng khoá vừa chỉnh. "Reset All Settings" xoá các khoá của mục 5.4 theo cùng cách.
- Mô hình cài đặt (kiểu dữ liệu, mặc định, khoảng, đọc, ghi) và danh mục dòng (mục, tên, chú thích, loại điều khiển, khoá, từ đồng nghĩa để tìm) nằm trong `shellx-model`. Danh mục là nguồn duy nhất cho cả việc vẽ lẫn chỉ mục tìm kiếm.

### 5.7 Tìm kiếm

- Ô "Search" / "Tìm kiếm" ở đầu cột trái. Ô trống thì hiện danh sách nhóm. Có chữ thì hiện danh sách phẳng các kết quả xếp hạng, mỗi kết quả là một mục hoặc một dòng (kèm tên mục làm chú thích); không có gì thì hiện "No Results".
- Chỉ mục gồm các mục và các dòng đang hiện trên Windows, kể cả chú thích và từ đồng nghĩa. Dòng chưa hiện không có trong chỉ mục.
- So khớp không phân biệt hoa thường và dấu tiếng Việt; mọi từ trong ô phải khớp. Xếp hạng: khớp nguyên, rồi đầu chuỗi, đầu từ, giữa chuỗi.
- Bấm một kết quả: mở mục đó, cuộn dòng vào giữa (kết quả là mục thì cuộn lên đầu) và làm dòng sáng lên một lúc bằng màu nhấn rồi tắt dần.

### 5.8 Cách kiểm chứng

- Test thuần trong `shellx-model` (`cargo test -p shellx-model`): mô hình cài đặt, đọc và ghi file, kẹp giá trị, danh mục dòng, tìm kiếm, đọc file theme, phân loại sáng/tối, suy màu khung và tương phản trên 464 theme, quy tắc nhận phím tắt, trùng phím, bảng phím sau khi gán lại.
- Test của app chạy với `--release` (`cargo test --release -p shellx-app`), vì bản debug vấp lỗi hashbrown đã biết.
- Mã chỉ dành cho Windows biên dịch qua `scripts/shellx/check-windows-build.sh --release`.
- Ảnh chụp trên Mac bằng `windows/dev/mac-shot.sh`:
  - cửa sổ chính với cài đặt mặc định, so với ảnh chụp từ commit trước khi bắt đầu Phần 1: chỉ khác ở các điểm trong bảng "Thay đổi so với 1.7.1". Ảnh phải có chữ nhiều màu ANSI và một vùng chọn, vì dấu nhắc lệnh trống không cho thấy các khác biệt đó. Thêm một test thuần: bộ màu khung suy từ theme ShellX bằng đúng từng giá trị `palette.rs`;
  - từng mục Settings, bằng tiếng Việt và tiếng Anh;
  - cửa sổ chính với Appearance Light, và với hai theme tối khác ShellX.
  - Cần một biến môi trường phát triển để mở Settings ở một mục cho trước, như `SHELLX_DEV_PREVIEW=settings` hiện có.
- Một bản cài thử có nhãn, build chéo như vòng trước, để trên Desktop của Mac này.
- `windows/WINDOWS-TEST-CHECKLIST.md` thêm một mục "Settings" khoảng 12 bước cho máy thật: mở cửa sổ, gõ tiếng Việt vào ô tìm, đổi Light/Dark, đổi một theme, đổi phông và cỡ chữ, gán lại một phím rồi dùng nó, gán trùng để thấy báo đỏ, đổi màu một workspace, đổi nền sidebar, Reset All Settings, tắt mở app và thấy cài đặt còn nguyên.
- `windows/README.md` cập nhật phần Settings và phím tắt.

Điều các kiểm chứng trên không chứng minh được: hành vi trên Windows thật của cửa sổ thứ hai, của ô ghi phím và của màu nhấn hệ thống. Chỉ danh sách kiểm trên máy thật mới cho biết.

### 5.9 Thứ tự làm và thứ bị cắt nếu hết ngày

Phần 1 lớn hơn một ngày làm của đợt 1 trước đây. Thứ tự dưới đây để mỗi bước xong là một trạng thái dùng được; hết ngày thì dừng ở cuối một bước và phần còn lại sang ngày sau **[người viết]**:

1. Mô hình cài đặt và lưu trữ; bộ điều khiển (công tắc, chọn đoạn, danh sách, thanh trượt, ô tăng giảm, ô số, ô màu); cửa sổ và khung với các mục cũ dời vào.
2. Themes, cùng việc đưa mọi màu của app qua `theme.rs`.
3. Terminal.
4. Sidebar và App.
5. Workspace Colors, cùng menu màu trên thẻ.
6. Keyboard Shortcuts.
7. Tìm kiếm, Reset, README, danh sách kiểm, bản cài thử.

Bước 1 phải xong trước. Các bước 2 đến 6 độc lập với nhau sau bước 1 và có thể giao cho các agent chạy song song, trừ việc mỗi bước đều thêm khoá vào mô hình cài đặt và chuỗi vào `strings.rs` (cần gộp cẩn thận).

### 5.10 Để lại cho người làm

Tên file, tên kiểu, cách chia module; cách các cửa sổ nhận tin cài đặt đổi; độ trễ ghi file; các bước pha màu cụ thể của khung (miễn đạt ràng buộc ở 5.5); cách lọc phông đơn cách; hoạt ảnh làm sáng dòng; biểu tượng của từng mục (gần nhất với SF Symbol của Mac trong bộ biểu tượng đang có); câu chữ tiếng Việt cho chuỗi Mac chưa dịch; hình dạng cụ thể của biến môi trường xem trước; cách đóng theme vào exe.

## 6. Rủi ro

- **Không có máy Windows.** Mọi thứ chỉ được chứng minh trên Windows khi người dùng chạy danh sách kiểm. Giảm rủi ro bằng quy tắc thuần có test và bằng đường lùi ở 5.3.
- **Cửa sổ thứ hai của GPUI trên Windows** chưa được app này dùng lần nào. Các bản vá GPUI trong repo (khôi phục thiết bị, chế độ hiển thị tương thích) mới chỉ được nghĩ cho một cửa sổ.
- **Ô ghi phím tắt** đụng đúng chỗ đã từng làm mất phím (quy tắc 3, mục 4).
- **Khối lượng.** Khoảng 55 dòng mới, một bộ điều khiển, bộ máy theme, bảng phím gán lại được. Mục 5.9 là cách chịu rủi ro này.
- **Gộp song song.** `strings.rs` và mô hình cài đặt là hai điểm mọi nhánh cùng sửa.
- **Giao diện sáng** của chính bản Mac chưa hoàn thiện, nên không có ảnh chuẩn để so; Windows dựa vào ràng buộc tương phản.

## 7. Quyết định của người viết cần người dùng xem

1. **Mặc định theo Mac**, nên bản cập nhật đổi chín thứ người dùng Windows đang thấy (bảng cuối mục 5.4: cỡ chữ 13, lề 2, màu ANSI, thẻ đang chọn, chuột giữa dán, Back/Forward…). Ngoại lệ duy nhất là vẫn hỏi trước khi dán nhiều dòng. Lựa chọn ngược lại là giữ nguyên mọi thứ Windows đang làm và chỉ dùng mặc định của Mac cho thứ Windows chưa có; khi đó Windows mặc định không giống Mac.
2. Settings là cửa sổ riêng, chạy được cả dưới dạng tấm phủ làm đường lùi (5.3).
11. Nhiều ShellX cùng chạy không đồng bộ cài đặt tức thì; tiến trình khác nhận ở lần mở sau (5.6).
12. Màu nhấn tô những gì, và chữ màu trạng thái được chỉnh đậm nhạt trên nền sáng (5.5).
3. Thêm "Phần 1b" vào lộ trình cho các dòng Terminal và App cần chức năng nhỏ chưa có (mục 3).
4. Phần 1 thêm menu chuột phải tối thiểu trên thẻ workspace chỉ để chọn màu (5.4).
5. Cập nhật và Giới thiệu nằm trong một nhóm "ShellX" riêng của Windows; Ngôn ngữ vào mục App; Hiển thị vào mục Terminal (5.3).
6. Ô màu là bảng nhỏ gồm ô mã màu và lưới màu gợi ý (5.5).
7. Theme đóng vào exe; khoá cài đặt dùng tên của Mac (5.5, 5.6).
8. Quy tắc nhận tổ hợp phím trên Windows (5.4, Keyboard Shortcuts).
9. "Reset All Settings" không hỏi lại, như Mac.
10. Phần 1 có thể dài hơn một ngày; dừng ở cuối một bước của 5.9.
