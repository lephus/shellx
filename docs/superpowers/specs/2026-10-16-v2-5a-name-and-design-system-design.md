# V2-5a — Tên app mới và hệ thiết kế mới — Đặc tả thiết kế

- **Ngày:** 2026-10-16
- **Branch:** `shellx-v2`. Không đẩy lên `main` khi người dùng chưa cho phép (đẩy `main` là phát hành app desktop).
- **Trạng thái:** Phần A của đề xuất V2-5, người dùng duyệt ngày 16/10: "làm theo khuyến nghị, Nhưng tên app nên để tên đầy đủ". Cập nhật bắt buộc lúc 11:25 cùng ngày thay dòng font và icon: "tôi muốn bạn sử dụng font chữ SF Mono cho mobile và desktop app ; icon trong app thì dùng cupertino". Các quyết định A1–A50 chi tiết hoá phần A. Chỗ đề xuất để ngỏ do người viết spec chốt, có ghi giá nếu sai.
- **Nền:** bắt đầu sau khi `v2-2b`, `v2-3`, `v2-4` đã gộp vào `shellx-v2`. Tài liệu viết theo trạng thái gộp đó (đọc mã ngày 16/10: `shellx-v2` `eb0b6dc`, `v2-2b` `fd48288`, `v2-3` `bfff4c0`, `v2-4` `e3ca11f`). A làm trước B (`2026-10-16-v2-5b-ai-assistant-design.md`) và C (`2026-10-16-v2-5c-voice-conversation-design.md`); hai spec đó dùng token và component của A.
- **Nguồn đã kiểm (16/10/2026):**
  - nghiên cứu `design-system-and-naming.md` (cả bài), `references.md` §1.4 và §4; ba ảnh công khai của file Figma (bìa Community, hai ảnh Dribbble), chỉ để xem;
  - mã ở các worktree; hai tài liệu thiết kế cũ;
  - trang developer.apple.com/fonts (đọc bằng WebFetch); giấy phép phần mềm macOS Tahoe 26 và iOS/iPadOS 27 (PDF của Apple);
  - tệp font trên máy Mac này (macOS 26.5) và trong repo, đọc các bảng `name`, `OS/2`, `fvar`, `hmtx`, `cmap` bằng một parser chỉ-đọc;
  - Flutter 3.41.4 (`cupertino/icons.dart` có 1 322 glyph; `ButtonStyle.backgroundBuilder`; `FontVariation` là const); `pubspec.lock` (`cupertino_icons` 1.0.9).
  - Mọi tỉ lệ tương phản tính lại theo công thức WCAG 2.x; gradient nội suy trong sRGB như Flutter, lấy 101 điểm mẫu.
- **Ký hiệu:** "A1" là quyết định của tài liệu này; "V2-4 E12" là của spec V2-4; "§6.3 NC" là mục 6.3 của `design-system-and-naming.md`. **DT** = desktop, **ĐT** = điện thoại.
- **A được phép sửa:** package mới `packages/shellx_design`; `pubspec.yaml` gốc (thêm vào `workspace:`); `apps/desktop`, `apps/mobile` (theme, component, màn hình ở §8, tên ở §4, mã native nạp font ở §6.3); `third_party/xterm` (chỉ trường độ đậm của `TerminalStyle`, §6.8); `release/windows/shellx.iss` **chỉ ba dòng hiển thị** (A10, file của đồng đội). **Không sửa:** `web/**`, `relay/**`, phần còn lại của `release/**`, `.github/**`, `term/**`, bố cục màn AI (B), giao diện giọng nói (C), giao thức.
- **Tài liệu này thay:**
  - trong `docs/superpowers/design/2026-10-06-shellx-desktop-ui.md`: §1.1 (màu), phần bán kính của §1.2 (kích thước cố định giữ), §1.3 (font, cỡ chữ), §1.4 (đổ bóng), màu và hình của §2.8 (toast), §3.3 (nút), §3.4 (ô nhập), §3.5 (tooltip), câu "system UI font" ở §7, và việc sau số 1 của §7 (package dùng chung: làm ở đây);
  - trong `docs/superpowers/design/2026-09-25-shellx-mobile-ui.html`: token `--a-*`, `--t-*`, font Raleway, hình của `.btn`, `.input`, `.m`, `.steps`, `.sheet`, `.banner`, `.badge`.
  - Bố cục, kích thước cố định, bàn phím, trợ năng và câu chữ trong hai tài liệu đó vẫn giữ hiệu lực.

---

## 1. Mục tiêu

Một tên và một diện mạo cho cả hai app:
- Chỗ nào hệ điều hành hay app hiện tên app thì hiện **"ShellX: Remote AI agents"**. Mọi định danh (tệp, thư mục, bundle id, khoá hệ thống) vẫn là **ShellX**, để không ai mất đăng nhập, khoá thiết bị hay điện thoại đã ghép.
- Một hệ thiết kế dùng chung ở `packages/shellx_design` theo phong cách "Online Bike Shopping App": navy nhám, neumorphism nhẹ, gradient cyan → indigo, đạt tương phản WCAG, không làm chậm danh sách.
- **SF Mono** cho giao diện, terminal và code trên iPhone và Mac, lấy từ hệ điều hành, không bao giờ đóng gói. **JetBrains Mono** (đã có trong cả hai app) trên Android và Windows, và là dự phòng trên iPhone, Mac khi không nạp được SF Mono (không dùng Menlo, A33).
- Icon **Cupertino** qua một lớp vai trò duy nhất `ShellxIcons`.
- B và C xây trên token và component của A, không tự đặt màu, font hay icon.

### Tiêu chí thành công (đo được)

1. **Tên.** Tên dài hiện ở:
   - màn hình chính iPhone (hệ thống cắt bớt, đã chấp nhận) và Cài đặt › Ứng dụng;
   - launcher, Recents, đầu thông báo của Android;
   - Finder, Launchpad, Dock, ⌘-Tab trên Mac;
   - Task Manager và Cài đặt › Ứng dụng của Windows (một mục duy nhất sau khi cập nhật từ 1.0.0);
   - tiêu đề cửa sổ khi không có tab, tooltip khay, dòng phiên bản ở Cài đặt ĐT, splash, đăng nhập, onboarding.
2. **Định danh.** Cập nhật desktop 1.0.0 lên bản A trên macOS và Windows: vẫn đăng nhập, điện thoại đã ghép vẫn kết nối, thư mục dữ liệu không đổi, không có shortcut thứ hai, "Khởi động cùng máy" vẫn chạy.
3. **Tương phản.** Test tương phản xanh:
   - chữ ≥ 4.5:1 trên mọi bề mặt nó nằm;
   - chữ trắng trên gradient `accent` ≥ 3:1 ở mọi điểm (chỉ dùng cho chữ đậm ≥ 15 px và icon);
   - chữ trắng trên `accentStrong` ≥ 4.5:1 ở mọi điểm;
   - viền ô nhập và vòng focus ≥ 3:1.
4. **Font.** iPhone và Mac vẽ giao diện bằng SF Mono của hệ thống (spike §6.3 đạt); Android và Windows bằng JetBrains Mono. Repo và gói cài không chứa tệp SF Mono nào (test). Cả hai họ chữ đủ 134 chữ tiếng Việt. App ĐT nhỏ đi (bỏ 18 tệp Raleway).
5. **Icon.** Không còn `Icons.*` hay `CupertinoIcons.*` ngoài `ShellxIcons` (guard). Bảng §7.4 có 95 vai trò (87 cho icon hiện có, 8 vai trò `voice*` cho C): 91 vai trò dùng glyph Cupertino; 4 vai trò dùng glyph Material đã liệt kê (A45).
6. **Không style cứng mới.** Guard xanh; hai lớp adapter (`ui/theme` của DT, `core/design` của ĐT) không còn mã hex.
7. **Hiệu năng.** Danh sách máy, phiên AI 200 mục, sidebar 30 tab cuộn 60 fps trên máy tham chiếu (§12). Không có `BackdropFilter` ngoài `ShellxGlass`, trừ một chỗ có sẵn ở màn quét QR (A44). Không đổ bóng trong mục danh sách, trừ mục đang chọn.
8. **Không vỡ gì.** Mọi test hiện có xanh sau các sửa ở §4.3 và §10.

---

## 2. Kiểm tra hiện trạng (đọc mã ngày 16/10)

| Mảng | Hiện có | Hệ quả cho A |
|---|---|---|
| Tên và định danh | "ShellX" vừa là tên hiển thị vừa là định danh: `PRODUCT_NAME`, `BINARY_NAME`, `ProductName`/`CompanyName` (quyết định `%APPDATA%\pro.shellx\ShellX`), `appName` của `local_notifier`/`launch_at_startup`, shortcut, khối profile shell (§5, §6.3 NC). Dấu `:` không hợp lệ trong tên tệp Windows; `path_provider` đổi nó thành `_`, tức là dời thư mục dữ liệu. | A1–A10: chỉ đổi khoá hiển thị |
| Màu DT | Một theme tối. 37 màu `static const` trong hai tệp (`shellx_desktop_theme.dart:6-55`, `terminal_colors.dart`); 594 chỗ gọi trong 75 tệp; 0 mã hex ngoài `ui/theme`. | A16: đổi giá trị, giữ tên |
| Màu ĐT | Sáng, tối, theo máy (`adaptive_theme`, mặc định `system`, `main.dart`). `AppColors` có 39 vai trò. Ngoài `core/design`: 15 hex, 20 `Colors.*`, 21 `TextStyle(`. Toast trắng cả khi tối (`popup_handler.dart:60-117`). | A22, A25, A26, A41, A46 |
| Font | DT: font hệ thống (SF Pro/Segoe), có test ghim "không `fontFamily`" (`theme_test.dart:16-22, 53-74`). ĐT: Raleway 18 tệp. Terminal: JetBrains Mono (DT thêm bản Light). Trên Mac này (macOS 26.5): SF Mono hệ thống mang tên ẩn `.SF NS Mono`, là font biến thiên `wght` 295–900, đủ 134/134 chữ Việt; Menlo chỉ 88/134; JetBrains Mono 134/134. | A31–A37 |
| Icon | Material: DT 74 loại, ĐT 60 loại, hợp lại 103 loại. Không nơi nào lưu `codePoint`. `cupertino_icons` 1.0.9 có trong lock (ĐT ràng buộc `^1.0.8`). SDK 3.41.4 có 1 322 glyph Cupertino. | A45 |
| Component | DT có component trung tâm (`ShellxPrimaryButton`, `ShellxIconButton`, `showShellxMenu`, `NoticeToast`, `buildDialogTheme`); chip và thẻ làm tay. ĐT có `AppButton`, `AppTextField`, `NoticeBanner`; 8 bottom sheet tự đặt màu, 5 cái tự bo 26. `SegmentedButton`: 2 ở ĐT, 1 ở DT. Không theme `dialog`, `bottomSheet`, `popupMenu` (màu suy từ seed). | A38–A43 |
| Nút và test | Nhiều test tìm `FilledButton` theo key (`daemon_dialogs_test`, `pages_test`, `ssh_connect_dialog_test`, `tool_dialog_test`, `ai_ask_card_test`). `ButtonStyle.backgroundBuilder` có từ Flutter 3.22; repo dùng 3.41.4. | A38 |
| Terminal | `TerminalColors` chép y hệt ở hai app; `config_theme.dart` dùng nó làm nền cho theme người dùng. `TerminalStyle.toTextStyle` của `third_party/xterm` chỉ đặt `fontWeight`. | A24, A37 |
| Giấy phép | ĐT có trang giấy phép (`showLicensePage` ở `settings_page.dart`). DT chỉ đăng ký `LicenseRegistry`, không có trang. | A47 |
| Test | Không có golden. Có test giá trị token, test hình học (26 tệp DT, 11 tệp ĐT), test ghim tên (§4.4 NC). | §4.3, §10 |
| Phát hành | `release/windows/shellx.iss` và workflow là của đồng đội trên `main`. `inno.test.mjs` không ghim `AppName`, `AppVerName`, `UninstallDisplayName`. | A10 |
| Màn khởi động gốc | iOS: storyboard nền trắng. Android: trắng hoặc `?android:colorBackground`. | A48 |

---

## 3. Nhật ký quyết định

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| A1 | Tên hiển thị | "ShellX: Remote AI agents" (24 ký tự, giống nhau ở EN và VI) ở đúng các chỗ của §4.1. Câu văn giữ chữ ngắn ("Đăng nhập ShellX", "Quit ShellX?"). | — (đã duyệt) |
| A2 | Định danh | Giữ "ShellX" ở mọi chỗ của §4.2; test ghim ở §4.3. | — (đã duyệt) |
| A3 | iOS | Chỉ đổi `CFBundleDisplayName` trong `Info.plist`. Không thêm khoá này vào `en.lproj`/`vi.lproj/InfoPlist.strings`: tên giống nhau ở hai ngôn ngữ, giữ một nguồn. `CFBundleName` (`shellx_mobile`, nội bộ) giữ. | Muốn tên tiếng Việt khác: thêm một dòng vào mỗi tệp `.strings`. |
| A4 | Android | `android:label` viết thẳng như hôm nay, không thêm `@string/app_name`. Recents lấy từ `onGenerateTitle`. | Muốn dịch tên: chuyển sang `@string` và `values-vi`. |
| A5 | macOS | `PRODUCT_NAME` giữ (nó quyết định `ShellX.app`, tệp chạy, `CFBundleName`, menu ứng dụng, bảng About). Thêm vào `Runner/Info.plist`: `CFBundleDisplayName = ShellX` (trùng tên tệp: điều kiện để Finder dùng tên bản địa hoá) và `LSHasLocalizedDisplayName = true`. Thêm `Runner/en.lproj/InfoPlist.strings` chứa tên dài, gắn vào Resources của target Runner. Chỉ `en.lproj`: Finder dùng nó cho mọi ngôn ngữ hệ thống, và app không khai thêm ngôn ngữ nên menu hệ thống của AppKit không đổi. Finder, Launchpad, Spotlight, Dock, ⌘-Tab, Mục đăng nhập, hộp xin quyền hiện tên dài; thanh menu và About vẫn "ShellX". Không định danh nào đổi. | Finder vẫn hiện "ShellX" (bộ nhớ đệm LaunchServices) hoặc hiện dấu `:` lạ: chỉ mất tên dài ở đó; gỡ bằng cách xoá một tệp và hai khoá. |
| A6 | Tiêu đề cửa sổ DT | Không có tab: `appTitle`. Có tab: giữ "{tab} — ShellX". Bỏ chữ cứng ở `window_host.dart:19`, `window_host.dart:187` (`init` nhận `title`; `main.dart:166` truyền `l10n.appTitle`), `terminal_pane.dart:316` (pane header macOS khi không có tab), `windows/runner/main.cpp:39`. | — |
| A7 | Khay | `trayTooltip` = tên dài. | — |
| A8 | Windows `FileDescription` | Tên dài. `ProductName`, `CompanyName`, `InternalName`, `OriginalFilename` giữ. `shellx-mux.exe` là bản chép của `ShellX.exe` nên cũng hiện tên dài trong Task Manager. | Task Manager có hai dòng cùng tên dài (hôm nay là hai dòng "ShellX"). |
| A9 | Hộp lỗi, thông báo DT | Tiêu đề `MessageBox` (`main.dart:816-821`, gọi ở `:108` và `:794`) = `appTitle`, vì đó là tiêu đề một cửa sổ. Tiêu đề thông báo (`main.dart:798`, `tray_actions.dart:213`) giữ "ShellX": hệ thống đã ghi tên app ngay phía trên. | — |
| A10 | Trình cài Windows | Chỉ đổi `AppName`, `AppVerName`, `UninstallDisplayName` trong `release/windows/shellx.iss`. `AppId`, thư mục, nhóm, tên shortcut, `LaunchProgram,ShellX`, `AppPublisher` giữ. Không thêm test vào `release/tests`. **File của đồng đội: báo người dùng trước khi gộp vào `main`.** | Câu trong trình cài thành "Cài đặt ShellX: Remote AI agents…"; muốn ngắn thì chỉ đổi `UninstallDisplayName`. |
| A11 | Dòng phiên bản ĐT | "ShellX: Remote AI agents {version} ({build})". Dòng "Phiên bản {version}" của DT không có tên, giữ. | — |
| A12 | Tên trên splash, đăng nhập, onboarding | ĐT: `ShellxBrandHeader` (logo hiện có + tên dài) ở splash (giữa màn, logo trên, tên dưới), ở đăng nhập và đăng ký (thay logo trơn), và dòng thương hiệu trên trạng thái rỗng lần đầu của danh sách máy (đó là onboarding của ĐT). DT: `ShellxBrandLine` (tên dài, kiểu `label`, màu `accent`) trên tiêu đề hộp thoại đăng nhập/đăng ký và onboarding. Không làm logo mới. | Hộp thoại đăng nhập DT cao thêm 24 px; test "cao dưới 520" của `app_dialogs_test.dart` phải vẫn xanh. |
| A13 | Splash | `MaterialApp` tạm của splash (`splash_page.dart:105`) có `onGenerateTitle: appTitle`, để Recents hiện tên dài ngay từ đầu. | — |
| A14 | Store, website | Ngoài repo hoặc cần người dùng đồng ý: ghi thành việc sau (§13.2). | — |
| A15 | Package | `packages/shellx_design`: package Flutter đầu tiên trong `packages/`, `resolution: workspace`. Phụ thuộc Flutter SDK và `cupertino_icons: 1.0.9` (ghim đúng phiên bản). Không phụ thuộc `xterm` (bảng terminal là `Color`; mỗi app tự dựng `TerminalTheme`). Không chứa tệp font. | — |
| A16 | Không đổi chỗ gọi | Lớp `static const` của DT (`ShellxDesktopColors`, `ShellxRadius`, `ShellxSpace`, `ShellxShadows`, `ShellxText`, `ShellxMotion`) giữ tên và trỏ vào hằng của package. `AppColors`/`AppTypography` của ĐT giữ tên vai trò, đổi giá trị, thêm vai trò mới. Lớp của package mang tên khác để không trùng. | Tên cũ như `ShellxRadius.r6` = 10 hay `display32` = 30 dễ nhầm; đổi tên hàng loạt là việc sau. |
| A17 | Lớp navy | Tám bậc từ ảnh tham chiếu (§5.3): `navy900 #1C222E` lõm (ô nhập, terminal), `navy850 #222834` trang, `navy825 #242C3B` thanh, `navy800 #28303F` hover trên trang, `navy750 #2C3547` bề mặt (thẻ, sheet, hộp thoại, menu), `navy700 #323B4F` nổi hoặc đang chọn, `navy650 #38445A` nhấn trên trang và hover trên bề mặt, `navy600 #3F4B62` nhấn trên bề mặt. DT: terminal `navy900`, sidebar `navy850`. | — |
| A18 | Màu chữ | Màu đặc bằng trắng 100/87/75/60/50/38 % phủ lên trang: `#FFFFFF`, `#E2E3E5`, `#CACCD1`, `#A7A9AE`, `#8E9096`, `#767A81`. Không dùng alpha cho chữ, để tương phản tính được trên mọi bề mặt. DT: `textTitle` 100 %, `textPrimary` 87 %. ĐT: `primaryText` 100 %, vì ĐT dùng một vai trò cho cả tiêu đề và thân. | Trên bề mặt sáng hơn trang, chữ sáng hơn "87 % thật" một chút. |
| A19 | Đường mảnh | Đường chia và viền trang trí là alpha: tối dùng trắng 8 % (`line`, `divider`) và 10 % (`border`); sáng dùng navy 10 %. Viền ô nhập là màu đặc ≥ 3:1 (`#76829C` tối, `#717C92` sáng). Không chỗ nào suy alpha từ `line`/`border` (đã kiểm). | Một đường alpha trên nền lạ trông khác ý: đổi màu đặc tại chỗ đó. |
| A20 | Sửa tương phản gradient | Hai gradient, đi từ trên trái xuống dưới phải. `accent` `#1A9BD8 → #4E4AF2`: điểm sáng `#1A9BD8` giữ sắc của màu đo trên nút tìm kiếm trong ảnh (`#39AFE7`) và hạ độ sáng cho tới khi đạt ngưỡng; chữ trắng ≥ 3.12:1 ở mọi điểm; dùng cho icon, chữ đậm ≥ 15 px, mảng trang trí. `accentStrong` `#157CAD → #4E4AF2`: chữ trắng ≥ 4.65:1 ở mọi điểm; dùng cho mọi chữ khác. Hover = phủ đen 8 %, nhấn = phủ đen 16 %; phủ trắng thì tương phản tụt (`accentStrong` + trắng 8 % chỉ còn 4.07:1). Quy tắc chọn ở §5.5. | Gradient kém rực hơn ảnh gốc (chữ trắng trên `#34C8E8` chỉ 1.99:1). |
| A21 | Màu nhấn đơn | `cyan #34C8E8` cho vòng focus, vạch chọn, chấm đang chạy, icon đang bật, tiến trình (7.44:1 trên trang). Link `#5EADEE`: cùng sắc với azure `#3D9CEA` của ảnh, sáng hơn để đạt 4.5:1 trên `navy700` (`#3D9CEA` chỉ 4.18 trên `navy750`, 3.81 trên `navy700`); `#3D9CEA` giữ làm `azure` cho trang trí. DT: text button, link markdown, nút trên dải dùng `link`; chỗ khác giữ `accent`. | Hai màu xanh trên một màn: một cho trạng thái, một cho link. |
| A22 | `primary`, `onPrimary`, `onAccent` | `primary` là màu đặc: tối `#34C8E8` với mực `onPrimary #0E1A26` (8.85:1); sáng `#1767AD` với chữ trắng (5.87:1). `primaryFill` = `primary`. Vai trò mới `onAccent #FFFFFF` cho chữ và icon trên gradient. `AppButton` đặt `IconTheme(onAccent)` cho `prefix`/`suffix`. Ba chỗ tô `onPrimary` cho icon trong `AppButton` (`session_picker.dart:162`, `machine_list_page.dart:608`, `machine_list_page.dart:665`) bỏ màu tự tô; `app_error_view.dart:29-35` bỏ màu tự đặt. | Chỗ dùng `onPrimary` trên gradient sẽ ra icon navy trên indigo (2.9:1): test component bắt. |
| A23 | Màu trạng thái | Chỉnh lại cho nền navy (§5.6): đỏ cũ `#F07178` chỉ 4.30:1 trên `navy750`. | — |
| A24 | Terminal mặc định | Palette "ShellX" mới (§5.7): nền `#1C222E` (= `bgTerminal`), chữ `#DDE3EC`, đen ANSI `#2C3547`, đen sáng `#8590A6` (4.96:1), vùng chọn cyan 30 %. Sáu sắc ANSI và bản sáng giữ nguyên (≥ 5.57:1 trên nền mới). Tên "ShellX" giữ. Theme của người dùng không đổi; khoá nào họ không khai thì lấy giá trị mặc định mới. | Ai thích nền gần đen cũ phải chọn một theme khác. |
| A25 | Biến thể sáng (chỉ ĐT) | §5.4, cùng sắc navy/azure. Trang `#EAEFF5`, sáng hơn phông `#E3EAF3` của ảnh để chữ trạng thái đạt 4.5:1. Gradient và wedge giống bản tối. Neumorphism sáng: bóng navy-xám ở dưới phải, trắng ở trên trái. | Light mode trông đục: chỉnh bóng. |
| A26 | Mặc định tối cho máy mới | `main.dart`: chế độ `adaptive_theme` đã lưu thắng. Chưa có thì đọc khoá mới `shellx_theme_default` (`SharedPreferences`). Chưa có nữa thì: máy chưa có `shellx_installed` (cài mới, `core/platform/fresh_install.dart`) → `dark`; có rồi (người dùng cũ) → `system`. Ghi kết quả vào `shellx_theme_default` để lần mở sau giữ nguyên. | Người cũ cài lại app thì được nền tối thay vì theo máy. |
| A27 | Bán kính | Theo đề xuất: 10 cho nút, chip, nút icon; 16 cho thẻ và ô nhập; 28 cho sheet, hộp thoại, khung lớn; viên thuốc cho tag. Thêm `tiny 6` cho dấu nhỏ (badge 16 px, phím tắt, ô đổi tên 22 px). DT đổi giá trị dưới tên cũ: `r4 → 6`, `r6 → 10`, `r8 → 16`, `r12 → 28`, `pill` giữ; ô nhập đặt rõ 16. ĐT: `AppButton` 15 → 10, ô nhập 13 → 16, thẻ 18 → 16, banner 13 → 16, sheet 26 → 28, hộp thoại 28. | Ô nhập DT cao 36 px với bo 16 gần như viên thuốc: đổi một hằng. |
| A28 | Neumorphism | Cặp nổi: bóng tối dưới phải + bóng sáng trên trái. Lõm: bóng trong, vẽ bằng `ShellxInsetBox` vì `BoxShadow` không có inset. Giá trị ở §5.8, dạng alpha để dùng được trên mọi bậc navy. Nổi: nút phụ, mục đang chọn (hàng sidebar, mục cài đặt, segment), thẻ đứng riêng, ô active của thanh dưới. Lõm: ô nhập ĐT, rãnh segmented, rãnh thanh trượt. Nhấn là "lún": mất bóng, nền `pushed`. | — |
| A29 | Kính | `ShellxGlass`: nền `navy700` 80 % (sáng: trắng 80 %); viền 1 px gradient trắng 20 % → 4 %; làm mờ σ 16 **chỉ** khi phía sau tĩnh (wedge, trang), còn trên nội dung chuyển động thì `blur: false`. Trên kính chỉ dùng chữ `textPrimary` trở lên: chữ 60 % chỉ còn 3.71:1 khi kính nằm trên đầu sáng của wedge. Được dùng ở: trạng thái rỗng (kể cả lời chào ở trang chủ AI), đăng nhập và onboarding, màn giọng nói, thẻ ô soạn AI. Trong A: thẻ các bước ở trạng thái rỗng lần đầu của danh sách máy (ĐT). | — |
| A30 | Wedge | `ShellxWedge`: tam giác ở góc (mặc định trên phải, rộng 45 %, cao 70 %), gradient dọc `#1A9BD8 → #3C65CF`. Đầu sáng hạ như A20, nên chữ trắng đậm ≥ 15 px đè lên vẫn ≥ 3.12:1. Không chữ thường, chữ phụ hay ô điều khiển nào nằm trên wedge; không bao giờ sau terminal, webview, văn bản dài. Nơi dùng như A29. Trong A: trạng thái rỗng terminal DT, splash, đăng nhập, đăng ký, trạng thái rỗng lần đầu ĐT. | Wedge tối hơn ảnh gốc (`#3BA2EA`). |
| A31 | Họ chữ | **SF Mono** cho giao diện, terminal mặc định và code trên iOS và macOS. **JetBrains Mono** (đã kèm trong cả hai app, 134/134 chữ Việt) trên Android và Windows. Không chọn font OFL "giống SF Mono" nào khác: JetBrains Mono đã có, đã kiểm tiếng Việt, không phải thêm tệp. Bỏ Raleway. `font-family` của người dùng cho terminal vẫn đứng đầu. Họ chữ do `ThemeData` cấp theo nền tảng (`ShellxFonts.uiFamily`); kiểu chữ không tự mang họ chữ. | Giao diện Android/Windows khác Mac một chút (JetBrains Mono hẹp hơn 3 %, nét khác). |
| A32 | Giấy phép SF Mono | §6.2. Không bao giờ đóng gói, ghi xuống đĩa hay gửi đi tệp hay dữ liệu của SF Mono. Chỉ nạp vào bộ nhớ để hiển thị khi app chạy trên iOS/macOS. Android/Windows không bao giờ yêu cầu họ chữ "SF Mono", kể cả bản người dùng tự cài. Test: không tệp SF Mono nào trong repo hay trong khai báo font. | Nếu Apple coi việc đọc bảng font là sao chép: tắt bằng một hằng, hai nền tảng Apple dùng JetBrains Mono. |
| A33 | Nạp SF Mono | Phương thức native (§6.3) lấy font monospaced của hệ thống (`NSFont`/`UIFont.monospacedSystemFont`), dựng lại tệp sfnt từ `CTFontCopyTable` cho bản thường và bản nghiêng, trả về qua kênh. Dart nạp bằng `FontLoader('SF Mono')` **trước** `runApp`, chờ tối đa 500 ms. **Spike làm đầu tiên**, tiêu chí đạt/trượt ở §6.3. Hỏng hay quá giờ thì không đăng ký gì; `ThemeData` tự rơi sang JetBrains Mono (danh sách dự phòng). **Không dùng Menlo làm dự phòng:** đo trên máy này, Menlo chỉ có 88/134 chữ Việt (thiếu ả ấ ầ ẩ ẫ ắ ẳ ẵ ẻ ế ề ể ễ ỉ ỏ ố ồ ổ ỗ ở và chữ hoa tương ứng), chữ Việt sẽ lẫn hai font trong một từ. Cập nhật 11:25 ghi Menlo; dự phòng JetBrains Mono thay Menlo và đã chốt, không mở lại. | Mất SF Mono trên một nền tảng: nền tảng đó trông như Android/Windows. |
| A34 | Thang chữ đơn cách | Font đơn cách rộng hơn: SF Mono 0.618 em mỗi ký tự; SF Pro trung bình 0.437 em trên mẫu chữ của app (§6.6). Giảm cỡ: DT −1 px cho cỡ ≥ 12.5, `small` 12 → 11.5, `caption` 11 giữ; ĐT −1 px cho cỡ 14–20, −2 px cho cỡ ≥ 24, giữ cỡ ≤ 13. **Chiều cao dòng tính bằng px giữ nguyên**, nên không bố cục dọc nào đổi (hàng 30/46/62/78, sidebar 220). Bảng ở §6.5. | Sidebar hiện ít hơn khoảng 25 % ký tự mỗi tên tab (có "…" và tooltip). |
| A35 | Độ đậm, nghiêng | SF Mono của hệ thống là font biến thiên (`wght` 295–900, mặc định 295 = Light). Mọi kiểu đặt cả `fontWeight` và `FontVariation('wght', n)` qua hàm `shellxWeight` của package. Mọi `fontWeight:` ngoài adapter (DT 18 chỗ, ĐT 9 chỗ) và các getter `.bold/.semiBold/.medium/.heavy` của ĐT đi qua hàm này. JetBrains Mono (tĩnh) bỏ qua `wght`: 500 lấy mặt Regular, 600 lấy mặt Bold. `.heavy` (800) đổi thành 700. Nghiêng: SF Mono Italic của hệ thống; JetBrains Mono Italic đã kèm. Toàn app bọc `DefaultTextHeightBehavior(leadingDistribution: even)`. | Trên Android/Windows chữ 600 đậm hơn trên Mac. |
| A36 | Kiểm đọc được DT | Kiểm tay §12 mục 6 trước khi gộp: Windows 100 % và macOS ở 11–12 px. Trượt trên Windows thì thang DT trên Windows tăng 1 px (`ShellxTypeScale.desktopWindowsBoost` đổi từ 0 mặc định thành 1), không đổi font. Dự phòng Inter của đề xuất ban đầu không còn áp dụng: cập nhật 11:25 chọn font đơn cách cho cả app. | Chữ Windows rộng hơn, sidebar hiện ít ký tự hơn nữa. |
| A37 | Terminal | Mặc định DT: macOS dùng SF Mono `wght` 300 (giống JetBrains Mono Light hôm nay), `font-weight = regular` thì 400, ô đậm 700; Windows giữ JetBrains Mono Light/Regular. ĐT: iOS SF Mono 400/700; Android JetBrains Mono. `third_party/xterm` thêm `TerminalStyle.normalWeight`/`boldWeight`, đưa vào `FontVariation('wght')`. Cỡ mặc định giữ (DT 13, ĐT 14). | SF Mono rộng hơn JetBrains Mono 3 %: cùng cửa sổ thì ít cột hơn khoảng 3 %. |
| A38 | Nút gradient | Giữ widget `FilledButton` (nhiều test tìm `FilledButton` theo key) và vẽ gradient bằng `ButtonStyle.backgroundBuilder`. Builder tự vẽ phủ hover/nhấn (lớp ink nằm dưới gradient đặc) và bo góc. ĐT: `AppButton` vẽ bằng `Ink(decoration: gradient)`. | — |
| A39 | Theme Material | Điền đủ cho cả hai app: `ColorScheme` (cả `surfaceContainer*`, `surfaceTint` trong suốt), `dialogTheme`, `bottomSheetTheme`, `popupMenuTheme`, `menuTheme`/`dropdownMenuTheme`, `switchTheme`, `sliderTheme`, `progressIndicatorTheme`, `textSelectionTheme`, `tooltipTheme`, `textButtonTheme`, `iconTheme`. 8 lời gọi `showModalBottomSheet` bỏ `backgroundColor`/`shape` tự đặt. Các `AlertDialog` của DT theo `dialogTheme` của cửa sổ. | — |
| A40 | Segmented | `ShellxSegmented<T>` (DT, ĐT) thay cả ba `SegmentedButton`: Cài đặt › Giao diện (ĐT), chọn ngôn ngữ VI│EN trong ô giọng nói của terminal (`voice_composer.dart`, ĐT; C không sửa tệp này) và bảng Thay đổi của AI (DT). C dùng cùng component cho VI│EN của chế độ giọng nói. | — |
| A41 | Toast | ĐT: thay toast trắng (`popup_handler.dart`) bằng toast theo token. DT: `NoticeToast` đổi màu và bo. | — |
| A42 | Thanh dưới ĐT | A làm `ShellxBottomBar` và test; B đặt nó vào app. | — |
| A43 | Ô nhập DT | Theo theme (nền `navy900`, viền `#76829C`, bo 16), không vẽ bóng trong: 24 `TextField` dùng theme, bọc từng cái là đổi chỗ gọi. ĐT: `AppTextField`, `PasswordTextField` có bóng trong. | DT kém "lõm" hơn ĐT một chút. |
| A44 | Hiệu năng | Không `BoxShadow` trong mục danh sách, trừ một mục đang chọn. Tối đa 6 phần tử nổi mỗi màn ĐT, 4 mỗi cửa sổ DT (chưa tính bóng của menu và hộp thoại). `BackdropFilter` chỉ có trong `ShellxGlass`, tối đa 1 mỗi màn, không trên terminal, webview, bản ghi. Ngoại lệ có sẵn, giữ: lớp mờ σ 3 sau sheet lỗi của màn quét QR (`qr_scanner_page.dart:292`), có trong bảng gốc của guard. Painter có `RepaintBoundary`, `shouldRepaint` chỉ khi đầu vào đổi. Không hoạt ảnh lặp trong phần của A (sóng âm và quả cầu của C theo luật riêng: V2-5c §4.4, C30). Test ở §10.5. | — |
| A45 | Icon | `CupertinoIcons` (font của `cupertino_icons` 1.0.9, ghim đúng ở package; app ĐT bỏ ràng buộc riêng `^1.0.8`). Mọi icon đi qua `ShellxIcons` (§7.4: 87 vai trò cho icon hiện có, cộng 8 vai trò `voice*` A khai sẵn cho C): 91 vai trò dùng glyph Cupertino; 4 vai trò không có glyph Cupertino hợp nghĩa dùng glyph Material liệt kê rõ: `terminal` (`Icons.terminal_rounded`), `faceId` (`Icons.face_rounded`), `fingerprint` (`Icons.fingerprint_rounded`), `sshHost` (`Icons.dns_rounded`). Đổi `lib/` và `test/` (`find.byIcon`) cùng một commit. Icon khay và icon app không đổi. | Một glyph khó đọc ở 12–14 px: đổi glyph của vai trò đó ở một chỗ. |
| A46 | Guard chống style cứng | §10.4: màu, kiểu chữ, cỡ, độ đậm, đổ bóng, làm mờ, icon chỉ đến từ package hoặc adapter. | — |
| A47 | Giấy phép, ghi công | `registerShellxDesignLicenses()` (package) đăng ký mục ghi công CC BY 4.0 (§9.3). OFL của JetBrains Mono đã được mỗi app đăng ký; giấy phép của `cupertino_icons` Flutter tự gom. SF Mono không đi kèm app nên không có giấy phép nào để gửi kèm. Be Vietnam Pro của đề xuất ban đầu đã bị bỏ theo cập nhật 11:25, nên không thêm giấy phép OFL nào. Trang giấy phép có `applicationLegalese` = `licensesLegalese`. DT thêm nút "Giấy phép và ghi công…" ở Cài đặt › Chung, dưới dòng phiên bản. | Trang giấy phép DT là trang Material toàn cửa sổ (có nút quay lại; Esc không đóng). |
| A48 | Màn khởi động gốc | Nền `#222834` cho: iOS `LaunchScreen.storyboard` (ảnh logo giữ); Android `drawable/launch_background.xml`, `drawable-v21/launch_background.xml`, `NormalTheme` ở `values` và `values-night`, thêm `values-v31/styles.xml` với `android:windowSplashScreenBackground`. Màu khai ở `values/colors.xml` (`shellx_page`). | Ai chọn giao diện sáng thấy một khoảnh navy lúc mở. |
| A49 | Ranh giới với B, C | A không đổi bố cục màn AI (B) và giao diện giọng nói (C). Ở các tệp đó A chỉ đổi token, component (chip, thẻ, nút, sheet), font, icon. | — |
| A50 | Token DT thêm và bỏ | Thêm `onAccent`, `link`, `overlayHover #38445A`, `overlayPressed #3F4B62`, `pushed #28303F`. Bỏ `primaryHover`, `primaryPressed`: chỉ nút chính dùng, nay nút chính là gradient. | — |

---

## 4. Tên app

### 4.1 Đổi (chỉ khoá hiển thị)

| # | Tệp | Khoá | Giá trị mới | Ghi chú |
|---|---|---|---|---|
| 1 | `apps/mobile/ios/Runner/Info.plist:9-10` | `CFBundleDisplayName` | `ShellX: Remote AI agents` | màn hình chính (bị cắt), Cài đặt, Spotlight, Siri |
| 2 | `apps/mobile/android/app/src/main/AndroidManifest.xml` (`<application>`) | `android:label` | `ShellX: Remote AI agents` | launcher, Cài đặt › Ứng dụng, đầu thông báo |
| 3 | `apps/mobile/lib/l10n/intl_en.arb`, `intl_vi.arb` (sinh lại `shared/src/l10n.dart`, `shared/src/intl/messages_*.dart`) | `appTitle` | tên dài (§9.1) | Recents, trang giấy phép, nhãn đọc màn hình của logo |
| 4 | như dòng 3 | `settingsVersion` | `ShellX: Remote AI agents {version} ({build})` | A11 |
| 5 | `apps/mobile/lib/features/app/splash_page.dart:105` | `MaterialApp.onGenerateTitle` | `S.of(context).appTitle` | A13 |
| 6 | `apps/desktop/lib/l10n/app_en.arb:3`, `app_vi.arb:3` (sinh lại `app_localizations*.dart`) | `appTitle` | tên dài | tiêu đề cửa sổ khi không có tab, `MessageBox` |
| 7 | `app_en.arb:50`, `app_vi.arb:39` | `trayTooltip` | tên dài | A7 |
| 8 | `apps/desktop/lib/src/ui/window_host.dart:19` | `windowTitleFor(null, …)` | `l10n.appTitle` | có tab: `windowTitle` giữ "{title} — ShellX" |
| 9 | `window_host.dart:187`, `apps/desktop/lib/main.dart:166` | `WindowManagerHost.init({required String title})` | `l10n.appTitle` | tiêu đề lúc mở |
| 10 | `apps/desktop/lib/src/ui/terminal/terminal_pane.dart:316` | chữ pane header macOS khi không có tab | `l10n.appTitle` | thay tiêu đề hệ thống đã ẩn |
| 11 | `apps/desktop/windows/runner/main.cpp:39` | `window.Create(L"…")` | `L"ShellX: Remote AI agents"` | trước khi Dart đặt tiêu đề |
| 12 | `apps/desktop/windows/runner/Runner.rc:93` | `FileDescription` | `ShellX: Remote AI agents` | A8 |
| 13 | `apps/desktop/lib/main.dart:816-821` (`_windowsErrorBox`, gọi ở `:108`, `:794`) | tiêu đề `MessageBox` | `l10n.appTitle` | A9 |
| 14 | `apps/desktop/macos/Runner/Info.plist` | thêm `CFBundleDisplayName` = `ShellX`, `LSHasLocalizedDisplayName` = `true` | — | A5 |
| 15 | `apps/desktop/macos/Runner/en.lproj/InfoPlist.strings` (mới, gắn vào Resources của Runner) | `"CFBundleDisplayName"` | `ShellX: Remote AI agents` | A5 |
| 16 | `release/windows/shellx.iss:22` ⚠ file của đồng đội | `AppName` | `ShellX: Remote AI agents` | A10 |
| 17 | `release/windows/shellx.iss:24` ⚠ | `AppVerName` | `ShellX: Remote AI agents {#AppVersion}` | A10 |
| 18 | `release/windows/shellx.iss:44` ⚠ | `UninstallDisplayName` | `ShellX: Remote AI agents` | A10 |

### 4.2 Giữ "ShellX" (định danh và câu)

| Định danh | Ở đâu | Vì sao giữ (§6.3 NC) |
|---|---|---|
| `ShellX.app`, `PRODUCT_NAME = ShellX`, `Contents/MacOS/ShellX`, `CFBundleName` | `macos/Runner/Configs/AppInfo.xcconfig:8` | Workflow kiểm `…/Release/ShellX.app` (`release-desktop.yml:160-164`); `make-dmg.sh:12` luôn đặt tên `ShellX.app` trong dmg; đổi tên thì người dùng kéo thả có hai app cùng bundle id; LaunchAgent của macOS 12 trỏ đường dẫn tệp chạy; `:` là ký tự phân cách đường dẫn cũ của macOS. |
| `ShellX.exe`, `BINARY_NAME`, `InternalName`, `OriginalFilename` | `windows/CMakeLists.txt:7`, `Runner.rc` | Dịch vụ nền chép `ShellX.exe` thành `shellx-mux.exe` (`windows_runtime_copy.dart:136-146`); workflow, `windows-check.yml`, `build-installer.ps1`, Inno `AppExeName`, taskkill/tasklist, `inno.test.mjs` đều cần tên này; giá trị `Run` lưu đường dẫn tệp. |
| `ProductName "ShellX"`, `CompanyName "pro.shellx"` | `Runner.rc` | Quyết định `%APPDATA%\pro.shellx\ShellX` (`path_provider` đổi `:` thành `_`): đổi là mất khoá thiết bị, token, điện thoại tin cậy, cài đặt; `quit.signal` và `[UninstallDelete]` của trình cài trỏ thư mục cũ. |
| Bundle id `pro.shellx.desktop`, `com.shellx.prod` | `AppInfo.xcconfig:11`, `project.pbxproj`, `build.gradle.kts` | Keychain, `UserDefaults`, thư mục app-support, mục đăng nhập, quyền TCC, App Store, Play, Firebase. |
| `appName: 'ShellX'` của `local_notifier` và `launch_at_startup` | `notifier.dart:29`, `launch_at_login.dart:17` | AUMID và shortcut `ShellX.lnk` của toast: `:` làm hỏng tên tệp; tên khác tạo shortcut thứ hai, AUMID mới, mất quyền thông báo; giá trị `HKCU\…\Run\ShellX` là thứ trình cài gỡ (`shellx.iss:199-205`). |
| Shortcut Start menu và desktop, `DefaultDirName`, `DefaultGroupName`, `AppId` | `shellx.iss:20-31, 70-71` | Tên tệp `.lnk` (không có `:`), cùng tên với shortcut của `local_notifier`; cập nhật dùng lại thư mục cũ; `AppId` là định danh nâng cấp và gỡ cài. |
| Thư mục dữ liệu `~/Library/Application Support/ShellX`, `%LOCALAPPDATA%\ShellX\{bin,term,restore,cli,mux}`, `%APPDATA%\ShellX\config`, `~/.config/shellx` | `sharing_paths.dart`, `mux_paths.dart`, `restore_paths.dart`, `config_paths.dart` | Đã có trên máy người dùng, trong test Rust và trong trình gỡ. |
| Khối profile shell `# >>> ShellX >>>`, `# <<< ShellX <<<`, `*.shellx-backup` | `shell_blocks.dart`, `term/shell/*` | Đã ghi trong `.zshrc`/`.bashrc`/profile PowerShell của người dùng; trình gỡ tìm đúng chuỗi này. |
| Tên tệp `ShellX-<v>.dmg`, `ShellX-Setup-<v>.exe`, `.aab`, volume dmg `ShellX` | `version.mjs:38-43`, `make-dmg.sh`, `android.sh` | Relay `/v1/version`, website, `resolve-version.mjs`: tên mới bị coi là chưa phát hành và tải lên cạnh bản cũ. |
| `shellx://`, CLI `shellx`, `shellx-term`, `shellx-mux` | `pairing_uri.dart:28`, `term/` | URI ghép đôi, lệnh của người dùng, script. |
| Theme terminal "ShellX" | `config/theme_listing.dart:18` | Tên trong tệp cấu hình của người dùng (`theme = ShellX`). |
| `CFBundleName = shellx_mobile` (iOS) | `Info.plist:22-23` | Nội bộ; iOS hiện `CFBundleDisplayName`. |
| Tiêu đề thông báo DT "ShellX" | `main.dart:798`, `tray_actions.dart:213` | Hệ thống đã ghi tên app phía trên (A9). |
| Câu có "ShellX" | ARB DT 64 dòng, ARB ĐT 22–24 dòng, `NS*UsageDescription`, "ShellX đang khóa", "Mở khóa ShellX", "Đăng nhập ShellX", "Quit ShellX?" | Đã duyệt: câu giữ chữ ngắn. |
| `AppPublisher=ShellX`, `PRODUCT_COPYRIGHT`, `LegalCopyright` | `shellx.iss:25`, `AppInfo.xcconfig:14`, `Runner.rc` | Tên nhà phát hành, không phải tên app. |

### 4.3 Test ghim tên

**Phải đổi:**
- `apps/mobile/test/platform_config_test.dart:28` (`CFBundleDisplayName` dài), `:123` (`android:label="ShellX: Remote AI agents"`), `:243` (giấy phép Raleway: bỏ). Thêm: hai tệp `InfoPlist.strings` không chứa `CFBundleDisplayName`; `CFBundleName` vẫn `shellx_mobile`; bundle id giữ (đã có).
- `apps/mobile/test/features/settings/settings_page_test.dart:172, 277, 557`: "ShellX: Remote AI agents 1.0.0 (1)".
- `apps/mobile/test/shared/shellx_logo_test.dart:13`: nhãn đọc màn hình là tên dài.
- `apps/desktop/test/ui/window_flow_test.dart:748`: `windowTitleFor(null, l10n)` là tên dài; `:752` giữ.

**Thêm:**
- `apps/desktop/test/platform/identity_pins_test.dart`:
  - `Runner.rc`: `FileDescription` dài; `ProductName`, `CompanyName`, `InternalName`, `OriginalFilename` giữ;
  - `CMakeLists.txt`: `BINARY_NAME` = `ShellX`; `main.cpp`: tiêu đề dài;
  - `AppInfo.xcconfig`: `PRODUCT_NAME`, bundle id giữ; `Info.plist`: hai khoá A5; `en.lproj/InfoPlist.strings`: tên dài;
  - `notifier.dart` và `launch_at_login.dart`: `appName: 'ShellX'`.
- Test ARB: `appTitle`, `trayTooltip` (DT) và `appTitle`, `settingsVersion` (ĐT) ở cả EN và VI; `windowTitle` giữ.
- `splash_page_test.dart`: `MaterialApp` của splash có tiêu đề là tên dài.
- Inno: không thêm test trong `release/tests` (A10); test hiện có vẫn xanh.

**Giữ** (câu và định danh): `lock_gate_test.dart`, `app_lock_controller_test.dart:78-83`, `login_page_test.dart:63-64`, các câu trong `l10n_test.dart`, `tray_menu_test.dart:184`, `agent_controller_test.dart:1092`, `theme_listing_test.dart`, `end_to_end_macos_test.dart:97`, `mux_paths_test.dart:19-23`, `release/tests/*`, `term/tests/*`. Giá trị giả `PackageInfo(appName: 'ShellX')` giữ: app không đọc `appName` lúc chạy.

---

## 5. Token: package `shellx_design`

### 5.1 Package

```
packages/shellx_design/
  pubspec.yaml                 name shellx_design; resolution: workspace; flutter SDK; cupertino_icons: 1.0.9
  lib/shellx_design.dart       export mọi thứ dưới đây
  lib/src/palette.dart         ShellxPalette (tối, dùng chung), ShellxLightPalette (sáng, chỉ ĐT)
  lib/src/gradients.dart       ShellxGradients
  lib/src/radii.dart           ShellxRadii
  lib/src/spacing.dart         ShellxSpacing
  lib/src/elevation.dart       ShellxElevation (.dark, .light), ShellxInsetShadow
  lib/src/type_scale.dart      ShellxFonts, ShellxTypeScale, shellxWeight()
  lib/src/system_font.dart     ShellxSystemFont (kênh native + FontLoader), ShellxFontStatus
  lib/src/motion.dart          ShellxDurations, ShellxCurves
  lib/src/terminal_palette.dart ShellxTerminalPalette
  lib/src/icons.dart           ShellxIcons
  lib/src/contrast.dart        contrastRatio(), compositeOver(), minContrastOnGradient()
  lib/src/licenses.dart        registerShellxDesignLicenses()
  lib/src/widgets/             inset_box.dart, wedge.dart, glass.dart, slant_border.dart, gradient_layer.dart
  test/                        §10.1
```

`pubspec.yaml` gốc thêm `packages/shellx_design` vào `workspace:`. Hai app thêm `shellx_design: any`; app ĐT bỏ `cupertino_icons: ^1.0.8`.

### 5.2 API

| Lớp, hàm | Nội dung |
|---|---|
| `ShellxPalette`, `ShellxLightPalette` | màu §5.3, §5.4, §5.6 (`static const Color`) |
| `ShellxGradients` | `accent`, `accentStrong`, `wedge`, `glassBorderDark`, `glassBorderLight` (`const LinearGradient`) |
| `ShellxRadii` | `tiny 6`, `control 10`, `card 16`, `sheet 28`, `pill 999` |
| `ShellxSpacing` | `s2, s4, s6, s8, s12, s16, s20, s24, s32, s40, s48` |
| `ShellxElevation` | `ShellxElevation.dark` / `.light`: `raised`, `raisedSmall`, `float1`, `float2`, `cta` (`List<BoxShadow>`), `inset` (`ShellxInsetShadow`) |
| `ShellxFonts` | `systemMono = 'SF Mono'`, `bundledMono = 'JetBrainsMono'`, `bundledMonoLight = 'JetBrainsMonoLight'`, `uiFamily(TargetPlatform)`, `uiFallback(TargetPlatform)`, `isApple(TargetPlatform)` |
| `ShellxTypeScale` | kiểu chữ không màu, không họ chữ, cho DT và ĐT (§6.5); `desktopWindowsBoost` |
| `shellxWeight(TextStyle, FontWeight)` | đặt `fontWeight` và `FontVariation('wght', w.value)` cùng lúc |
| `ShellxSystemFont.load({Duration timeout})` | §6.3; trả `ShellxFontStatus` (`loaded` hoặc `fallback(reason)`) |
| `ShellxDurations`, `ShellxCurves` | §5.8 |
| `ShellxTerminalPalette` | §5.7 |
| `ShellxIcons` | §7.4 (`static const IconData`) |
| `contrastRatio(a, b)`, `compositeOver(fg, bg)`, `minContrastOnGradient(g, text, {samples = 101})` | cho test và kiểm debug |
| `ShellxInsetBox`, `ShellxWedge`, `ShellxGlass`, `ShellxSlantBorder`, `shellxGradientLayer(...)` | widget §7 (`shellxGradientLayer` trả `ButtonLayerBuilder` cho `backgroundBuilder`) |
| `registerShellxDesignLicenses()` | ghi công §9.3 |

### 5.3 Bảng màu tối (DT, ĐT tối)

Cột tương phản ghi theo thứ tự lõm · trang · bề mặt · nổi khi có bốn số.

| Hằng (`ShellxPalette`) | Hex | Vai trò | Tương phản đo |
|---|---|---|---|
| `navy900` | `#1C222E` | lõm: ô nhập, rãnh, nền terminal, nền pane DT | — |
| `navy850` | `#222834` | trang ĐT, sidebar DT | trắng 14.78 |
| `navy825` | `#242C3B` | thanh: thanh dưới ĐT, chrome terminal ĐT | `white60` 5.96 |
| `navy800` | `#28303F` | hover trên trang; `pushed` | 1.12 so với trang |
| `navy750` | `#2C3547` | bề mặt: thẻ, sheet, hộp thoại, menu, toast | trắng 12.30 |
| `navy700` | `#323B4F` | nổi, đang chọn, tooltip | 1.32 so với trang |
| `navy650` | `#38445A` | nhấn trên trang; hover trên bề mặt (`overlayHover`) | 1.25 so với bề mặt |
| `navy600` | `#3F4B62` | nhấn trên bề mặt (`overlayPressed`) | — |
| `white100` | `#FFFFFF` | tiêu đề | 15.94 · 14.78 · 12.30 · 11.21 |
| `white87` | `#E2E3E5` | chữ chính | 12.41 · 11.51 · 9.58 · 8.73 |
| `white75` | `#CACCD1` | thân hộp thoại, nhãn | 9.92 · 9.20 · 7.65 · 6.97 |
| `white60` | `#A7A9AE` | chữ phụ | 6.78 · 6.28 · 5.23 · 4.76 |
| `white50` | `#8E9096` | placeholder (chỉ trên `navy900`) | 4.99 trên lõm |
| `white38` | `#767A81` | trang trí, không dùng cho chữ | — |
| `hairline` | `#14FFFFFF` (trắng 8 %) | đường chia (`line`, `divider`) | — |
| `hairlineStrong` | `#1AFFFFFF` (trắng 10 %) | viền trang trí (`border`) | — |
| `handle` | `#33FFFFFF` (trắng 20 %) | tay kéo sheet | — |
| `fieldOutline` | `#76829C` | viền ô nhập | 4.13 · 3.83 · 3.19 (≥ 3 phi chữ) |
| `cyan` | `#34C8E8` | nhấn đơn: focus, vạch chọn, chấm chạy, icon bật, tiến trình | 8.02 · 7.44 · 6.19 · 5.64 |
| `onCyan` | `#0E1A26` | mực trên `cyan` | 8.85 |
| `cyanSoft` | `#253E4D` | nền nhạt: badge, chọn trong danh sách | `white87` 8.72; `link` 4.63 |
| `azure` | `#3D9CEA` | trang trí, chữ ≥ 18 px | 5.03 trang; 4.18 bề mặt (không cho chữ nhỏ) |
| `link` | `#5EADEE` | link, text button | 6.59 · 6.11 · 5.09 · 4.64 |
| `accentLight` | `#1A9BD8` | điểm sáng của `accent`, đầu wedge | trắng 3.12 |
| `accentStrongLight` | `#157CAD` | điểm sáng của `accentStrong` | trắng 4.65 |
| `indigo` | `#4E4AF2` | điểm tối của gradient | trắng 5.86 |
| `wedgeBottom` | `#3C65CF` | đáy wedge | trắng 5.31 |
| `scrim` | `#99000000` | sau hộp thoại, sheet | — |
| `scrollThumb`, `scrollThumbHover` | `#3D424C`, `#4E535D` | thanh cuộn | — |
| `keyboardBackground`, `keyboardKey`, `keyboardInk` | `#1E1F21`, `#47484B`, `#FFFFFF` | thanh phím phụ ĐT theo bàn phím hệ thống (giữ như cũ) | — |
| `glassFill` | `#CC323B4F` (`navy700` 80 %) | nền kính | trên đầu sáng wedge: `white87` 6.79, `white75` 5.42, `white60` 3.71 |

### 5.4 Bảng màu sáng (chỉ ĐT)

| Hằng (`ShellxLightPalette`) | Hex | Vai trò | Tương phản đo (lõm · trang · bề mặt · nổi) |
|---|---|---|---|
| `page` | `#EAEFF5` | trang | — |
| `surface` | `#F5F7FA` | thẻ, sheet, hộp thoại | — |
| `raised` | `#FFFFFF` | nổi, đang chọn, chip | — |
| `inset` | `#E0E6EE` | lõm, ô nhập; `pushed` | — |
| `text` | `#141A26` | chữ chính, tiêu đề | 13.87 · 15.07 · 16.23 · 17.42 |
| `textSecondary` | `#4E586B` | chữ phụ | 5.70 · 6.19 · 6.67 · 7.16 |
| `placeholder` | `#596376` | placeholder trên `inset` | 4.82 |
| `hairline` | `#1A141A26` (navy 10 %) | đường chia, viền trang trí | — |
| `handle` | `#33141A26` | tay kéo sheet | — |
| `fieldOutline` | `#717C92` | viền ô nhập | 3.34 · 3.63 · 3.91 |
| `primary` | `#1767AD` | màu đặc, link, icon bật, focus, `keyAccent` | 4.67 · 5.07 · 5.47 · 5.87; trắng trên nó 5.87 |
| `primarySoft` | `#DCE8F3` | nền nhạt | `primary` trên nó 4.72 |
| `ok`, `okDot`, `okSoft` | `#256B45`, `#2E8A57`, `#E9F0EC` | trạng thái tốt | `ok` 5.12 · 5.56 · 5.99 · 6.43, trên `okSoft` 5.55; `okDot` 3.72 trên trang |
| `warn`, `warnSoft` | `#7F4C00`, `#F2EDE6` | cảnh báo | 5.70 · 6.19 · 6.66 · 7.15; trên `warnSoft` 6.14 |
| `error`, `errorSoft` | `#B0202B`, `#F7E9EA` | lỗi | 5.42 · 5.88 · 6.34 · 6.80; trên `errorSoft` 5.76; trắng trên `error` 6.80 |
| `scrim` | `#73141A26` | sau hộp thoại, sheet | — |
| bàn phím | nền `#D1D4DA`, phím `#FFFFFF`, mực `#000000`, link `#14598F`, lỗi `#A3161D` | thanh phím phụ ĐT | link 4.95, lỗi 5.26, chữ phụ 4.82 trên nền |
| `glassFill`, viền kính | `#CCFFFFFF`, `#14141A26` | kính | trên đầu sáng wedge: chữ chính 14.05, chữ phụ 5.78 |

### 5.5 Gradient

| Hằng | Điểm màu | Chữ trắng thấp nhất (101 điểm) | Hover (phủ đen 8 %) | Nhấn (phủ đen 16 %) | Dùng cho |
|---|---|---|---|---|---|
| `accent` | `#1A9BD8 → #4E4AF2`, trên trái → dưới phải | 3.12 (ở điểm sáng; giữa dải 4.48) | 3.63 | 4.29 | icon trên gradient, chữ đậm ≥ 15 px, mảng trang trí |
| `accentStrong` | `#157CAD → #4E4AF2`, trên trái → dưới phải | 4.65 (giữa dải 5.48) | 5.34 | 6.15 | mọi chữ khác |
| `wedge` | `#1A9BD8 → #3C65CF`, trên → dưới | 3.12 | — | — | wedge |
| `glassBorderDark` | `#33FFFFFF → #0AFFFFFF`, trên trái → dưới phải | — | — | — | viền kính tối |
| `glassBorderLight` | `#14141A26 → #05141A26` | — | — | — | viền kính sáng |

Quy tắc chọn:
- Chữ thường bất kỳ cỡ, hoặc chữ đậm dưới 15 px → `accentStrong`.
- Chữ đậm (≥ 600) từ 15 px, icon, mảng không chữ → `accent` (dùng `accentStrong` cũng được).
- DT: mọi nút, chip, segment có chữ dùng `accentStrong` (chữ 11.5–12 px); nút icon đang bật dùng `accent`.
- ĐT: `AppButton` (chữ 15/700) dùng `accent`, tự chuyển `accentStrong` khi `MediaQuery.textScalerOf(context).scale(15) < 15`. Chip và segment (13/600) dùng `accentStrong`. Icon trên gradient (thanh dưới, nút icon) dùng `accent`.
- Trạng thái: hover phủ `#14000000`, nhấn phủ `#29000000`, tắt dùng độ mờ của app (DT 0.38, ĐT 0.45). Không phủ trắng lên gradient.

### 5.6 Màu trạng thái (tối)

| Hằng | Hex | Tương phản đo |
|---|---|---|
| `ok` (cũng là chấm online) | `#5ED39C` | 8.56 · 7.93 · 6.60 · 6.02 |
| `okSoft` | `#293D40` | `ok` trên nó 6.14 |
| `warn` | `#F5B94E` | 9.06 · 8.40 · 6.99 · 6.37 |
| `warnSoft` (`warnBg` DT) | `#3B3937` | `warn` trên nó 6.53 |
| `warnLine` (`warnBorder` DT) | `#554B3A` | — |
| `error` (`err`, `errDialog` DT) | `#FF8A94` | 7.07 · 6.55 · 5.46 · 4.97 |
| `errorSoft` | `#3D3440` | `error` trên nó 5.28 |
| `onError` | `#2A0A0C` | trên `error` 8.12 |
| `errorHover` (`destructiveHover` DT) | `#FF98A1` | `onError` trên nó 8.94 |
| `noticeBg`, `noticeText`, `noticeLine` | `#453F50`, `#FFD9DB`, `#5F4959` | chữ 7.79 |
| `inProgress` (`statusInProgress` DT) | `#6EA8FE` | 6.60 · 6.12 · 5.09 · 4.64 |

### 5.7 Terminal (hai app, tối ở cả hai chế độ)

| Hằng (`ShellxTerminalPalette`) | Hex | Ghi chú |
|---|---|---|
| `background` | `#1C222E` | = `bgTerminal` DT |
| `foreground`, `cursor`, `white` (ANSI 7) | `#DDE3EC` | 12.35 trên nền |
| `selection` | `#4D34C8E8` (cyan 30 %) | chữ trên vùng chọn 6.43 |
| `black` (ANSI 0) | `#2C3547` | 1.30 so với nền: thấy được khối nền đen |
| `brightBlack` (ANSI 8) | `#8590A6` | 4.96 (cũ `#6C8288` trên nền mới chỉ 3.94) |
| `red`, `green`, `yellow`, `blue`, `magenta`, `cyan` | `#F07178`, `#7ED492`, `#E9C46A`, `#82AAFF`, `#C792EA`, `#5FD4E2` | giữ; 5.57–9.54 trên nền mới |
| bản sáng của sáu sắc trên, `brightWhite` | `#FF8F95`, `#9BE3AB`, `#F2D68C`, `#A5C2FF`, `#DAB3F1`, `#8FE3EC`, `#FFFFFF` | giữ; 7.30–15.94 |
| `searchHitBackground`, `searchHitBackgroundCurrent`, `searchHitForeground` | `yellow`, `cyan`, `background` | giữ |
| `chrome`, `chrome2` | `#242C3B`, `#2C3547` | chrome terminal ĐT |
| `line` | `#343944` | đường trong chrome (màu đặc) |
| `dim`, `muted`, `title` | `#767A81`, `#A7A9AE`, `#FFFFFF` | `muted` 5.96 trên `chrome`, 5.23 trên `chrome2` |
| `secondaryAction`, `onCyan` | `#323B4F`, `#0E1A26` | `onCyan` trên `cyan` 10.05 |
| `noticeBackground`, `noticeText`, `noticeBorder` | `#453F50`, `#FFD9DB`, `#5F4959` | |
| `driverBannerBackground`, `driverBannerBorder` | `#3B3937`, `#554B3A` | chữ `yellow` |

### 5.8 Bán kính, khoảng cách, đổ bóng, chuyển động

**Bán kính** (`ShellxRadii`): `tiny 6`, `control 10`, `card 16`, `sheet 28`, `pill 999`.

**Khoảng cách** (`ShellxSpacing`): 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48.

**Đổ bóng** (`ShellxElevation`):

| Hằng | Tối | Sáng | Dùng |
|---|---|---|---|
| `raised` | (4,4) mờ 12 `#59000000` + (−3,−3) mờ 10 `#0FFFFFFF` | (4,4) mờ 12 `#40566A8C` + (−4,−4) mờ 12 `#FFFFFFFF` | phần tử nổi ĐT |
| `raisedSmall` | (2,2) mờ 6 `#59000000` + (−1,−1) mờ 4 `#0DFFFFFF` | (2,2) mờ 6 `#33566A8C` + (−2,−2) mờ 6 `#FFFFFFFF` | phần tử nổi DT, segment đang chọn |
| `inset` (bóng trong) | (2,2) mờ 6 `#73000000` + (−1,−1) mờ 3 `#0DFFFFFF` | (2,2) mờ 6 `#33566A8C` + (−1,−1) mờ 3 `#CCFFFFFF` | ô nhập ĐT, rãnh segmented, rãnh slider |
| `float1` | (0,4) mờ 16 `#73000000` (= `e1` cũ) | (0,4) mờ 16 `#1F141A26` | menu, toast, tooltip |
| `float2` | (0,16) mờ 48 `#8C000000` (= `e2` cũ) | (0,12) mờ 32 `#29141A26` | hộp thoại, sheet |
| `cta` | (0,8) mờ 20 `#664E4AF2` | (0,6) mờ 16 `#404E4AF2` | nút chính ĐT, một nút mỗi màn |

**Chuyển động** (`ShellxDurations`, `ShellxCurves`; giảm chuyển động thì mọi thời lượng = 0): `fast` 80 ms `easeOut` (hover, màu); `press` 100 ms `easeOut` (nhấn ĐT); `exit` 120 ms `easeIn`; `base` 150 ms `easeOutCubic` (hộp thoại vào, mờ dần); `toastIn` 160 ms; `slide` 200 ms `easeOutCubic` (ô của segment, ô active của thanh dưới); `sheet` 250 ms; toast hiện 4 s, lỗi 6 s (DT), 3 s (ĐT); `tooltipWait` 500 ms; `scrollbarFade` 800 ms; `dragExpandDelay` 600 ms.

### 5.9 Hai app dùng token thế nào (không đổi chỗ gọi)

Luồng: hằng của package → adapter (DT: lớp `static const` trong `ui/theme`; ĐT: `LightColors`/`DarkColors`, `AppTypography`, `ThemeDataFactory`) → widget qua tên cũ. Họ chữ do `ThemeData` cấp theo nền tảng; SF Mono được nạp trước `runApp` (§6.3).

**DT `ShellxDesktopColors`** (mọi giá trị là hằng của `ShellxPalette`):

| Token | Cũ | Mới | | Token | Cũ | Mới |
|---|---|---|---|---|---|---|
| `bgTerminal` | `#0B1215` | `#1C222E` | | `accent` | `#5FD4E2` | `#34C8E8` |
| `bgSidebar` | `#111B1E` | `#222834` | | `primary` | `#2DBFCF` | `#34C8E8` |
| `rowHover` | `#172427` | `#28303F` | | `onPrimary` | `#04282D` | `#0E1A26` |
| `rowSelected` | `#1F2F34` | `#323B4F` | | `primarySoft` | `#0E363C` | `#253E4D` |
| `rowPressed` | `#26393E` | `#38445A` | | `ok` | `#7ED492` | `#5ED39C` |
| `line` | `#243337` | `#14FFFFFF` | | `warn` | `#E9C46A` | `#F5B94E` |
| `surface` | `#172023` | `#2C3547` | | `warnBg`, `warnBorder` | `#2A2412`, `#4A3F1C` | `#3B3937`, `#554B3A` |
| `surfaceInset` | `#0D1315` | `#1C222E` | | `err`, `errDialog` | `#F07178`, `#F26A70` | `#FF8A94` |
| `border` | `#2B373A` | `#1AFFFFFF` | | `onErr` | `#2A0A0C` | `#2A0A0C` |
| `borderInput` | `#5E7176` | `#76829C` | | `statusInProgress` | `#6EA8FE` | `#6EA8FE` |
| `textPrimary` | `#D4E1E4` | `#E2E3E5` | | `noticeBg`, `noticeText`, `noticeBorder` | `#2A1416`, `#FFD9DB`, `#5A2A2E` | `#453F50`, `#FFD9DB`, `#5F4959` |
| `textTitle` | `#E8F0F2` | `#FFFFFF` | | `scrim` | `#99000000` | `#99000000` |
| `textSecondary` | `#93A5A9` | `#A7A9AE` | | `scrollThumb`, `scrollThumbHover` | `#2B373A`, `#3A4A4E` | `#3D424C`, `#4E535D` |
| `textDialog2` | `#A7B6BA` | `#CACCD1` | | `destructiveHover` | `#F4848A` | `#FF98A1` |
| `textPlaceholder` | `#6F8186` | `#8E9096` | | `primaryHover`, `primaryPressed` | `#4CCAD8`, `#26A9B8` | bỏ (A50) |
| `dim` | `#6C8288` | `#767A81` | | mới: `onAccent`, `link`, `overlayHover`, `overlayPressed`, `pushed` | — | `#FFFFFF`, `#5EADEE`, `#38445A`, `#3F4B62`, `#28303F` |

Lớp khác của DT: `ShellxRadius.r4/r6/r8/r12/pill` = `ShellxRadii.tiny/control/card/sheet/pill`; `ShellxSpace` = `ShellxSpacing`; `ShellxShadows.e1`/`e2` = `float1`/`float2` (giá trị không đổi), thêm `raised` (= `raisedSmall` tối) và `inset`; `ShellxText` = `ShellxTypeScale.desktop*` (§6.5); `ShellxMotion` = `ShellxDurations`/`ShellxCurves` (giá trị không đổi). `TerminalColors` của hai app đọc `ShellxTerminalPalette`, mỗi app tự dựng `TerminalTheme`.

**ĐT `AppColors`** (giá trị tối / sáng):

| Vai trò | Tối | Sáng | Vai trò | Tối | Sáng |
|---|---|---|---|---|---|
| `background` | `#222834` | `#EAEFF5` | `ok`, `okDot` | `#5ED39C` | `#256B45`, `#2E8A57` |
| `surface` | `#2C3547` | `#F5F7FA` | `warn` | `#F5B94E` | `#7F4C00` |
| `raised` (mới) | `#323B4F` | `#FFFFFF` | `warnSoft`, `lightGold` | `#3B3937` | `#F2EDE6` |
| `inset` (mới) | `#1C222E` | `#E0E6EE` | `error`, `mainRed` | `#FF8A94` | `#B0202B` |
| `primaryText` | `#FFFFFF` | `#141A26` | `errorSoft`, `lightRed` | `#3D3440` | `#F7E9EA` |
| `secondaryText` | `#A7A9AE` | `#4E586B` | `okSoft` (mới), `lightGreen` | `#293D40` | `#E9F0EC` |
| `disable` (placeholder) | `#8E9096` | `#596376` | `scrim` | `#99000000` | `#73141A26` |
| `border` (viền ô nhập) | `#76829C` | `#717C92` | `keyAccent` | `#34C8E8` | `#1767AD` |
| `divider` | `#14FFFFFF` | `#1A141A26` | `keyboardLink` | `#5EADEE` | `#14598F` |
| `primary`, `primaryFill`, `accent` | `#34C8E8` | `#1767AD` | `keyboardError` | `#FF8A94` | `#A3161D` |
| `onPrimary` | `#0E1A26` | `#FFFFFF` | `keyboardBackground`, `keyboardKey`, `keyboardInk` | giữ | giữ |
| `onAccent` (mới) | `#FFFFFF` | `#FFFFFF` | `gradient` | `ShellxGradients.accent` | như tối |
| `primarySoft` | `#253E4D` | `#DCE8F3` | `gradientStrong`, `wedge` (mới) | `accentStrong`, `wedge` | như tối |
| `link` | `#5EADEE` | `#1767AD` | `elevation` (mới) | `ShellxElevation.dark` | `.light` |
| `white`, `black` | giữ | giữ | `mainGreen`, `mainGold`, `mediumRed`, `mediumOrange`, `blueGrey` (sau A không còn chỗ dùng) | = `ok`, `warn`, `error`, `warn`, `navy900` | = `ok`, `warn`, `error`, `warn`, `text` |

`ThemeDataFactory`: `ColorScheme` đặt `primary`, `onPrimary`, `primaryContainer = primarySoft`, `surface`, `onSurface = primaryText`, `onSurfaceVariant = secondaryText`, `error`, `outline = border`, `outlineVariant = divider`, `surfaceContainerLowest…Highest` (tối: `navy900`, `navy850`, `navy750`, `navy750`, `navy700`; sáng: `#FFFFFF`, `page`, `surface`, `surface`, `raised`), `surfaceTint` trong suốt; cùng các theme ở A39.

---

## 6. Chữ

### 6.1 Họ chữ theo nền tảng

| Nền tảng | Giao diện | Code (AI, khối code) | Terminal mặc định | Nguồn |
|---|---|---|---|---|
| macOS | SF Mono | SF Mono | SF Mono `wght` 300; `font-weight = regular` → 400; ô đậm 700 | hệ thống, nạp lúc chạy (§6.3) |
| iOS | SF Mono | SF Mono | SF Mono 400; ô đậm 700 | hệ thống, nạp lúc chạy (§6.3) |
| Windows | JetBrains Mono | JetBrains Mono | JetBrains Mono Light; `regular` → Regular (như hôm nay) | đã kèm trong app (`apps/desktop/assets/fonts`) |
| Android | JetBrains Mono | JetBrains Mono | JetBrains Mono Regular (như hôm nay) | đã kèm trong app (`apps/mobile/assets/fonts`) |
| Mọi nền tảng | — | — | `font-family` của người dùng đứng đầu | cấu hình người dùng |

`ShellxFonts.uiFamily(p)` = `'SF Mono'` khi `p` là iOS hay macOS, ngược lại `'JetBrainsMono'`. `ShellxFonts.uiFallback(p)` = `['JetBrainsMono']` trên iOS/macOS, rỗng ở nơi khác. `buildDesktopTheme()` và `ThemeDataFactory.create()` đặt `fontFamily`, `fontFamilyFallback` từ hai hàm này theo `defaultTargetPlatform`. Nạp SF Mono hỏng thì họ "SF Mono" không tồn tại và engine tự dùng `JetBrainsMono`. `uiFont()` của DT vẫn chép họ chữ và danh sách dự phòng từ theme. Vì giao diện đã đơn cách, các chỗ tự đặt họ chữ cho code bỏ họ chữ và theo theme: DT `kAiMono` (`ai_theme.dart:24`) và `confirm_page.dart:93`; ĐT 17 chỗ `FontFamily.jetBrainsMono` trong 13 tệp (AI, markdown, phím phụ, link sheet, ô giọng nói, thẻ QR, Cài đặt…). Chỉ kiểu của terminal (`terminal_style.dart`, `terminal_metrics.dart`) còn đặt họ chữ, qua `ShellxFonts` (§6.8).

### 6.2 Giấy phép SF Mono

Trích nguyên văn (đọc ngày 16/10/2026):
- developer.apple.com/fonts, thoả thuận của bản tải về: "you may use the Apple Font solely for creating mock-ups of user interfaces to be used in software products running on Apple's iOS, OS X or tvOS operating systems" và "You may not embed the Apple Font in any software programs or other products." Trang tả SF Mono: "supports Latin, Greek, and Cyrillic scripts".
- Giấy phép macOS Tahoe 26, §2.E "Fonts": "you may use the fonts included with the Apple Software to display and print content while running the Apple Software; however, you may only embed fonts in content if that is permitted by the embedding restrictions accompanying the font in question."
- Giấy phép iOS và iPadOS 27: không có mục font riêng. Font nằm trong "Apple Software" ("documentation, interfaces, content, fonts and any data that came with your Device"), được cấp phép để dùng trên thiết bị.
- `OS/2.fsType` của `/System/Library/Fonts/SFNSMono.ttf` = `0x0004` ("preview & print"), áp cho việc nhúng font vào tài liệu.

Cách đọc của spec (không phải ý kiến pháp lý): bản tải về của SF Mono chỉ dùng làm mock-up, không được nhúng vào phần mềm, nên **không bao giờ đóng gói**. Font SF Mono có sẵn trong hệ điều hành được dùng để hiển thị nội dung khi app chạy trên macOS/iOS. Quy tắc bắt buộc:
1. Không tệp SF Mono nào trong repo, trong khai báo `fonts:` hay trong gói cài (test §10.1).
2. Byte font chỉ ở trong bộ nhớ của tiến trình. Không ghi đĩa, không cache, không gửi đi, không đưa vào log.
3. Không nhúng vào nội dung xuất ra (app không xuất PDF hay tệp có font).
4. Android và Windows không bao giờ yêu cầu họ chữ "SF Mono" (`uiFamily` trả `JetBrainsMono`).

### 6.3 Nạp SF Mono trên iOS và macOS

Font hệ thống mang tên ẩn (bắt đầu bằng dấu chấm, `.SF NS Mono`), nên Flutter không gọi được nó theo tên. Cần một phương thức native.

- **Kênh:** `pro.shellx.design/system_font`, phương thức `monospaced`, không tham số. Trả `{'regular': Uint8List, 'italic': Uint8List?, 'missing': List<int>}` hoặc lỗi `unavailable`.
- **macOS:** `apps/desktop/macos/Runner/SystemMonoFont.swift`, đăng ký trong `MainFlutterWindow.awakeFromNib` cạnh `AppChannel.register`. Lấy `NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)`; bản nghiêng bằng `CTFontCreateCopyWithSymbolicTraits(font, 13, nil, .traitItalic, .traitItalic)`.
- **iOS:** `apps/mobile/ios/Runner/SystemMonoFont.swift`, đăng ký trong `didInitializeImplicitFlutterEngine` qua `engineBridge.pluginRegistry.registrar(forPlugin: "ShellxSystemMonoFont")`. Lấy `UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)` (bắc cầu sang `CTFont`); bản nghiêng bằng `fontDescriptor.withSymbolicTraits(.traitItalic)`.
- **Dựng sfnt** (cùng một đoạn Swift ở hai runner): danh sách bảng từ `CTFontCopyAvailableTables(font, [])`, mỗi bảng lấy bằng `CTFontCopyTable(font, tag, [])`. Phiên bản sfnt `0x00010000` khi có `glyf`, `OTTO` khi có `CFF `. Bản ghi bảng xếp theo thẻ; dữ liệu căn 4 byte; checksum từng bảng; `head.checkSumAdjustment` để 0. Không ghi tệp.
- **Độ phủ:** `CTFontGetGlyphsForCharacters` cho 134 chữ Việt và 5 dấu kết hợp (U+0300, U+0301, U+0303, U+0309, U+0323); mã điểm thiếu trả trong `missing`.
- **Dart** (`ShellxSystemFont.load()`):
  - chỉ chạy khi `ShellxFonts.isApple(defaultTargetPlatform)`; nơi khác trả `fallback(unsupported)` ngay;
  - gọi kênh với hạn 500 ms; `missing` không rỗng thì coi là trượt (`coverage`);
  - có byte thì `FontLoader('SF Mono')..addFont(regular)..addFont(italic)`, rồi `load()`;
  - kết quả `loaded` hoặc `fallback(reason)`, với `reason` thuộc `unsupported`, `channel`, `timeout`, `coverage`, `loader`; log chỉ ghi `reason`, không ghi nội dung.
- **Thời điểm:** `main()` của hai app gọi ngay sau `WidgetsFlutterBinding.ensureInitialized()` và trước `runApp`, để khung đầu tiên đã dùng đúng font. Tiến trình nền của DT (`daemon_main.dart`) không nạp.
- **Tắt:** hằng `ShellxSystemFont.enabled` (mặc định `true`) để tắt hẳn (A32). Bản debug nhận `--dart-define=FORCE_BUNDLED_MONO=true` để thử nhánh dự phòng; bản release bỏ qua cờ này.

**Spike (việc đầu tiên của plan).** Chạy trên Mac (macOS 26), iPhone thật (iOS 26 hoặc 27) và simulator iOS. Đạt khi cả năm điều đúng trên một nền tảng:
1. Kênh trả byte bản thường và bản nghiêng (mỗi bản trên 100 KB) trong ≤ 150 ms; `FontLoader.load()` không lỗi.
2. Native báo đủ glyph cho 134 chữ Việt và 5 dấu kết hợp.
3. Flutter vẽ bằng họ chữ đã nạp: 10 chữ "m" ở cỡ 100 rộng 618 ± 2 px (SF Mono), không phải 600 (JetBrains Mono).
4. `wght` 300, 400, 600, 700 cho lượng mực tăng dần (đo pixel như `terminal_font_weight_test.dart`); bản nghiêng khác bản đứng.
5. Không tệp mới trong thư mục của app sau khi nạp (so danh sách tệp trước và sau).

Trượt bất kỳ điều nào trên một nền tảng thì nền tảng đó dùng JetBrains Mono; ghi kết quả vào PR; phần còn lại của A làm tiếp.

### 6.4 Phủ tiếng Việt (đo bằng parser `cmap` chỉ-đọc)

| Tệp | 134 chữ Việt | 5 dấu kết hợp | Ghi chú |
|---|---|---|---|
| `/System/Library/Fonts/SFNSMono.ttf` (macOS 26.5) | 134 | 5 | biến thiên `wght` 295–900 (mặc định 295) và trục riêng `YAXS`; có ⌘ ⌥ ⇧ ⌃ ⏎ ← → … — “ ” · ▸ ▾ ✓ • ─ │ ╭ █; không có ký hiệu Powerline |
| `/System/Library/Fonts/SFNSMonoItalic.ttf` | 134 | 5 | thiếu ⌘ ⌥ ⇧ ⌃ ⏎ ← → ✓ và ký tự khung (engine lấy từ font khác) |
| `/System/Library/Fonts/Menlo.ttc` (cả 4 mặt) | 88 | 5 | thiếu 46: Ả ả Ấ ấ Ầ ầ Ẩ ẩ Ẫ ẫ Ắ ắ Ẳ ẳ Ẵ ẵ Ẻ ẻ Ế ế Ề ề Ể ể Ễ ễ Ỉ ỉ Ỏ ỏ Ố ố Ồ ồ Ổ ổ Ỗ ỗ Ở ở … → không làm dự phòng (A33) |
| `JetBrainsMono-Regular.ttf`, `JetBrainsMono-Light.ttf` (repo) | 134 | 5 | đủ ký hiệu trên và cả Powerline |

Bản iOS được kiểm trên máy thật bằng tiêu chí 2 của spike.

### 6.5 Thang chữ

**DT** (`ShellxText`, lấy từ `ShellxTypeScale.desktop*`; không mang họ chữ; độ đậm qua `shellxWeight`):

| Kiểu | Hôm nay (cỡ/dòng, đậm) | Mới | Dùng cho |
|---|---|---|---|
| `caption` | 11/14, 500 | 11/14, 500 | gợi ý phím trong menu, tooltip; dòng ngữ cảnh |
| `small` | 12/16, 400 | 11.5/16, 400 | pane header, tooltip, chip |
| `body` | 13/18, 400 | 12/18, 400 | tên tab, dải, mục menu, toast |
| `bodyStrong` | 13/18, 600 | 12/18, 600 | tên tab đang chọn, nhãn nút |
| `label` | 12.5/16, 600 | 11.5/16, 600 | nhãn ô nhập, dòng thương hiệu |
| `dialogBody` | 14/20, 400 | 13/20, 400 | thân hộp thoại, giá trị ô nhập, thân markdown AI |
| `emptyTitle` | 15/20, 600 | 14/20, 600 | tiêu đề trạng thái rỗng |
| `dialogTitle` | 17/22, 600 | 16/22, 600 | tiêu đề hộp thoại |
| `display` (mới) | — | 22/28, 600 | dành cho B (lời chào ở trang chủ AI) |
| `kAiMono` | 12/17, JetBrains Mono | 12/17, họ chữ của nền tảng | code trong pane AI |
| terminal | 13 (người dùng 9–28) | giữ | |

Nếu A36 bật trên Windows, mọi cỡ trong bảng (trừ terminal) cộng 1 px; chiều cao dòng giữ.

**ĐT** (`AppTypography`; getter giữ tên; chiều cao dòng tính bằng px giữ nguyên):

| Getter | Hôm nay (cỡ/dòng px) | Mới | | Getter | Hôm nay | Mới |
|---|---|---|---|---|---|---|
| `display56` | 56/78.4 | 54/78.4 | | `subHeader` | 16/26 | 15/26 |
| `display42` | 42/63 | 40/63 | | `subHeader15` | 15/24.4 | 14/24.4 |
| `display36` | 36/54 | 34/54 | | `paragraph` | 14/22 | 13/22 |
| `display32` | 32/48 | 30/48 | | `paragraph13` | 13/20.4 | 13/20.4 |
| `heading28` | 28/42 | 26/42 | | `metadata12` | 12/19 | 12/19 |
| `heading26` | 26/39 | 24/39 | | `metadata11` | 11/17.4 | 11/17.4 |
| `heading24` | 24/36 | 22/36 | | `metadata10` | 10/16 | 10/16 |
| `heading20` | 20/32 | 19/32 | | `metadata8` | 8/12.8 | 8/12.8 |
| `title` (và tiêu đề AppBar) | 18/29 (AppBar 17) | 17/29 (AppBar 16) | | | | |

Độ đậm ĐT: thường 400, `.medium` 500, `.semiBold` 600, `.bold` 700, `.heavy` 700 (trước là 800). `liningFigures` giữ (vô hại với font đơn cách).

### 6.6 Độ rộng (đo từ `hmtx`, không tính kerning)

| Mẫu | SF Pro 13 (DT hôm nay) | SF Mono 12 (DT mới) | JetBrains Mono 12 (Windows mới) | Raleway 16 (ĐT hôm nay) | SF Mono 15 (ĐT mới) |
|---|---|---|---|---|---|
| `claude · ~/work/shellx` | 117 | 163 | 158 | 169 | 204 |
| `Đăng nhập ShellX` | 97 | 119 | 115 | 132 | 148 |
| `ShellX: Remote AI agents` | 136 | 178 | 173 | 187 | 223 |
| `main · ~/work · :3000` | 115 | 156 | 151 | 154 | 195 |
| `Điện thoại đang dùng terminal này — gõ để dùng lại` | 277 | 371 | 360 | 384 | 464 |
| `Trợ lý AI` | 44 | 67 | 65 | 61 | 83 |

SF Pro đo bằng `SFNS.ttf` của hệ thống (bản mặc định). Hệ quả, đã kiểm cho từng chỗ đề xuất nêu:
- **Sidebar 220 px:** vùng tên tab khoảng 148 px khi không có dấu, 112 px khi có hai dấu. Chứa 19 và 15 ký tự (hôm nay khoảng 26 và 19). Tên dài có "…" và tooltip (đã có). Hàng 30/46/62/78 và sidebar 220 giữ.
- **Dòng ngữ cảnh** (`caption` 11): khoảng 168 px, chứa 24 ký tự.
- **Pill người lái** ở `body` 12: 371 px + icon và đệm = 415 px, vẫn dưới trần 560; pane hẹp hơn 520 dùng câu ngắn (đã có).
- **Nút DT** 12/600: "Mở tab mới" khoảng 74 px + đệm 28; tối thiểu 80 giữ.
- **Chip DT** 11.5: "Claude ▾" khoảng 57 px + icon và đệm.
- **Hộp thoại** 400/480/520: chữ xuống dòng nhiều hơn, chiều cao theo nội dung (đã có); dòng thương hiệu 11.5 px rộng 171 px.
- **Thanh dưới ĐT:** mỗi mục 125 pt trên máy 375 pt; "Trợ lý AI" 12/600 rộng 67 px, ở 1.3× chữ 87 px.
- **Tiêu đề thương hiệu ĐT** (17/700, 253 px): một dòng trên máy 375 pt; xuống 2 dòng trên máy 320 pt (cho phép `maxLines: 2`).

### 6.7 Kiểm đọc được

§12 mục 6. Người kiểm xem sidebar 30 tab, menu, tooltip, Cài đặt, palette ở Windows 100 % (JetBrains Mono 11–12 px) và macOS (SF Mono):
- dấu tiếng Việt (ặ, ẫ, ỗ, ữ, ợ, Ẩ) không bị cắt ở hàng 30 px, mục menu 28 px, chip 24 px, ô đổi tên 22 px;
- phân biệt được `Il1`, `O0`, `rn/m`;
- không nhoè đến mức khó đọc so với hôm nay.

Kết quả ghi vào PR. Trượt trên Windows thì bật A36.

### 6.8 Terminal

- **DT** (`terminal_style.dart`): `desktopTerminalStyle` lấy họ chữ mặc định theo nền tảng. macOS: `'SF Mono'`, dự phòng `JetBrainsMonoLight`/`JetBrainsMono`, rồi dự phòng của xterm; `normalWeight` 300 (`regular` → 400), `boldWeight` 700. Windows giữ như hôm nay. `font-family` của người dùng đứng đầu như cũ.
- **ĐT** (`terminal_metrics.dart`): `shellxTerminalStyle` dùng `'SF Mono'` (dự phòng `JetBrainsMono`) trên iOS với 400/700; Android giữ `JetBrainsMono`.
- **`third_party/xterm`:** `TerminalStyle` thêm `double? normalWeight`, `double? boldWeight`. `toTextStyle` thêm `fontVariations: [FontVariation('wght', bold ? boldWeight : normalWeight)]` khi có giá trị. Đo ô vẫn bằng 10 chữ "m" như cũ.
- Bảng màu ở §5.7.

---

## 7. Component

Vị trí: phần dùng chung nằm trong package (`ShellxInsetBox`, `ShellxWedge`, `ShellxGlass`, `ShellxSlantBorder`, `shellxGradientLayer`, `ShellxIcons`). Component của DT ở `apps/desktop/lib/src/ui/components/` (mới) cùng các lớp hiện có (`ShellxPrimaryButton`, `ShellxIconButton` trong `terminal_overlays.dart`; `buildDialogTheme`). Component của ĐT ở `apps/mobile/lib/shared/src/`.

### 7.1 Component và trạng thái

| Component | Kích thước, hình, chữ | Mặc định | Hover (DT) | Nhấn | Focus (bàn phím) | Tắt | Đang chạy |
|---|---|---|---|---|---|---|---|
| Nút chính gradient | DT: cao 32, tối thiểu 80, đệm 0/14, bo 10, chữ 12/600 trắng, `accentStrong`, không bóng. ĐT `AppButton`: cao 54, bo 10, chữ 15/700 trắng, `accent` (§5.5), bóng `cta` | gradient | phủ đen 8 % | phủ đen 16 %; ĐT thêm co 0.98 trong `press` | vòng `cyan` 2 px **ngoài** nút, cách 2 px (`OutsideFocusRingBorder`) | DT 0.38, ĐT 0.45 độ mờ, không bóng | DT: vòng xoay 14 px trắng trước chữ, bề rộng giữ; ĐT: vòng xoay thay chữ (như cũ) |
| Nút phụ nổi | như trên; nền `navy700`/`raised`, chữ `textPrimary`, bóng `raisedSmall` (DT) / `raised` (ĐT) | nổi | nền `navy650` | lún: nền `pushed`, mất bóng | vòng 2 px **trong** bo | như trên | như trên |
| Nút huỷ diệt | nền `error`, chữ `onError` (tối) / trắng (sáng), không gradient | — | `errorHover` | phủ đen 16 % | vòng ngoài | như trên | như trên |
| Text button | chữ `link`, không nền | — | nền `navy800` | nền `navy650` | vòng trong | 0.38 / 0.45 | — |
| Nút icon | DT `ShellxIconButton`: chạm 28, hình 24, glyph 16, bo 10. ĐT: chạm 44, hình 40, glyph 22, bo 10. Biến thể: phẳng, nổi, gradient (`accent`, glyph trắng) khi đang bật | trong suốt / nổi / gradient | nền `navy800`, glyph `textPrimary` | nền `navy650`; gradient: phủ đen 16 % | vòng trong; gradient: vòng ngoài | DT không có (dùng `busy`); ĐT 0.45 | DT: glyph thành vòng xoay 12 px (như cũ) |
| Chip | DT cao 24, đệm 0/10, chữ 11.5/500; ĐT cao 36, đệm 0/14, chữ 13/600; bo 10; icon 14/18 | viền `hairlineStrong`, nền trong suốt (DT) hoặc `raised` (ĐT), không bóng | nền `navy800` | nền `pushed` | vòng trong; đang chọn: vòng ngoài | 0.38 / 0.45 | — |
| Chip đang chọn | `accentStrong`, chữ trắng 600 | | phủ đen 8 % | phủ đen 16 % | | | |
| Segmented `ShellxSegmented<T>` | DT: rãnh cao 28, đệm 2, bo 10, segment cao 24, bo 8, tối thiểu 56, đệm 0/10, chữ 11.5. ĐT: rãnh tối thiểu 48, đệm 4, bo 14, segment tối thiểu 40, bo 10, chữ 13/600, tối đa 2 dòng (cao lên, không cắt) | rãnh lõm (`inset`), segment chưa chọn chữ `textSecondary` | segment chưa chọn: chữ `textPrimary`, nền `navy800` | lún | một tab stop; ←/→ đổi chọn (DT); vòng ngoài quanh segment đang chọn | 0.38 / 0.45 | — |
| Segment đang chọn | `accentStrong`, chữ trắng 600, bóng `raisedSmall`; trượt sang chỗ mới trong `slide` | | | | | | |
| Ô nhập lõm | DT: cao 36, đệm 0/10, bo 16, nền `navy900`, viền 1 px `fieldOutline`, chữ 13/20, placeholder `white50`. ĐT: cao 52, bo 16, nền `inset`, viền 1.5 px `border`, bóng trong (`ShellxInsetBox`), chữ 15 | — | viền `textSecondary` | — | viền `cyan` 1.5 px (DT) / `primary` 2 px (ĐT) | viền mờ 50 %, chữ mờ | — |
| Lỗi ô nhập | viền `error`; chữ lỗi `error` 4 px dưới (DT `small`, ĐT `paragraph13` đậm) | | | | | | |
| Thẻ `ShellxCard` | bo 16; đệm DT 12, ĐT 16. Biến thể `flat`: nền `navy750`/`surface` + viền `hairlineStrong`; `raised`: thêm bóng nổi; `inset`: `ShellxInsetBox` | — | thẻ bấm được: nền `overlayHover` | lún: nền `pushed` | vòng trong | 0.38 / 0.45 | — |
| Thẻ kính `ShellxGlass` | bo 16, nền `glassFill`, viền gradient 1 px, mờ σ 16 hoặc không (A29) | — | — | — | — | — | — |
| Bottom sheet (ĐT) | bo trên 28, nền `surface`, tay kéo 36×4 `handle`, bóng `float2`, cao tối đa 90 %, vùng an toàn | — | — | — | — | — | — |
| Hộp thoại | DT: hộp của `RouteDialogHost` và `dialogTheme`: bo 28, nền `navy750`, viền `hairlineStrong`, bóng `float2`, scrim 60 %, rộng giữ (400/480/520). ĐT: `dialogTheme` bo 28, nền `surface`, tiêu đề `heading20` đậm, thân `paragraph`, nút text `link` | — | — | — | Esc, Enter, thứ tự Tab như cũ | — | — |
| Toast | DT `NoticeToast`: bo 16, tối đa 420, đệm 8/12, `float1`; thường: nền `navy750`, viền `hairlineStrong`, chữ `textPrimary`; lỗi: `noticeBg`/`noticeLine`/`noticeText`. ĐT: trên giữa, bo 16, nền `surface` (tối `navy750`), icon 20 theo loại (`ok`, `warn`, `error`, `primary`), tiêu đề 14/600, mô tả 13 `secondaryText`; lỗi dùng `errorSoft` | — | DT: dừng đếm giờ | ĐT: vuốt lên để đóng (như cũ) | — | — | — |
| Menu | DT `showShellxMenu`: nền `navy750`, bo 16, viền `hairlineStrong`, `float1`, đệm 4; mục cao 28, bo 10, đệm 0/10. ĐT `popupMenuTheme` tương tự (mục 44) | — | mục: nền `overlayHover`, chữ `textTitle`, gợi ý phím `textDialog2` | nền `overlayPressed` | mục được trỏ như hover | mục tắt 0.38, giữ chỗ | — |
| Tooltip (DT) | nền `navy700`, viền `hairlineStrong`, bo 10, đệm 4/8, `small` `textPrimary`, `float1` | — | — | — | — | — | — |
| Thanh dưới `ShellxBottomBar` (ĐT, B đặt vào) | cao 64 + vùng an toàn; nền `navy825` (sáng: `raised`), bo trên 28, bóng `float1` lật lên; mỗi mục chiếm đều, chạm tối thiểu 48×48, icon 24 trên, nhãn 12/600 dưới, `maxLines: 1`; chữ co theo 1.3× tối đa | icon và nhãn `secondaryText` | — | ô co 0.96 trong `press` | vòng `cyan` 2 px quanh mục | 0.45, không bấm | — |
| Mục đang chọn của thanh dưới | ô 56×36, `ShellxSlantBorder(bo 10, cạnh trên dốc 4 px)`, `accent`, bóng `cta`; icon trắng trên ô; nhãn `primaryText` 700; ô trượt sang mục mới trong `slide`; `HapticFeedback.selectionClick()` | | | | | | |
| Huy hiệu thanh dưới | chấm 8 px `accent` hoặc viên đếm cao 16 nền `error`, chữ `onError`, ở góc trên phải icon | | | | | | |
| Wedge `ShellxWedge` | tam giác góc, `wedge` gradient, không semantics, không nhận chạm, `RepaintBoundary` | — | — | — | — | — | — |
| Dòng/tiêu đề thương hiệu | DT `ShellxBrandLine`: `appTitle`, `label`, `accent`, cách tiêu đề 8 px. ĐT `ShellxBrandHeader`: logo 48 + tên `title` 700 (`maxLines: 2`); splash: logo 72 trên, tên `heading20` 700 dưới, căn giữa | — | — | — | — | — | — |

Ngữ nghĩa trợ năng: segment và mục thanh dưới là `Semantics(button: true, selected: …, inMutuallyExclusiveGroup: true, label: nhãn)`; thanh dưới là `Semantics(container: true, explicitChildNodes: true)`. Nút gradient giữ nhãn của nút. Wedge và kính không có semantics riêng. Logo đọc `appTitle`.

### 7.2 Kính và wedge: chỗ được dùng

| Chỗ (đề xuất đã duyệt) | Kính | Wedge | Ai làm |
|---|---|---|---|
| Trạng thái rỗng: terminal DT (không có tab) | — | góc trên phải pane | A |
| Trạng thái rỗng lần đầu của danh sách máy (onboarding ĐT) | thẻ các bước, mờ σ 16 | góc trên phải vùng rỗng | A |
| Splash ĐT | — | góc trên phải | A |
| Đăng nhập, đăng ký ĐT | — | góc trên phải, sau tiêu đề thương hiệu | A |
| Hộp thoại đăng nhập, onboarding DT | — (dòng thương hiệu) | — (nút đóng của Windows ở góc trên phải) | A |
| Lời chào ở trang chủ AI | được | được | B |
| Thẻ ô soạn AI | được; trên bản ghi đang cuộn thì `blur: false` | — | B |
| Màn giọng nói: lớp phủ toàn màn hình; thanh giọng nói ở chỗ thẻ ô soạn | được; thanh nằm trên bản ghi nên `blur: false` | được (lớp phủ) | C |

### 7.3 Giới hạn hiệu năng

- Không `BoxShadow` trong mục của danh sách hay lưới (sidebar, dòng thời gian AI, danh sách máy, kết quả palette), trừ một mục đang chọn.
- ĐT: tối đa 6 phần tử nổi (mỗi cái 2 bóng) mỗi màn, cộng một `cta` và một `float2`. DT: tối đa 4 phần tử nổi mỗi cửa sổ, cộng bóng của menu và hộp thoại đang mở.
- `BackdropFilter` chỉ có trong `ShellxGlass`; tối đa một kính làm mờ mỗi màn; chỉ khi phía sau tĩnh; không bao giờ trên `TerminalView`, webview của trang tool, bản ghi AI, hay trong mục danh sách. Ngoại lệ có sẵn duy nhất: màn quét QR (A44).
- `ShellxWedge`, `ShellxInsetBox` vẽ bằng `CustomPainter` trong `RepaintBoundary`, `shouldRepaint` chỉ khi kích thước, góc hay màu đổi.
- Không hoạt ảnh lặp trong A. Giảm chuyển động thì mọi thời lượng = 0.

### 7.4 Icon: `ShellxIcons` (87 vai trò thay 103 icon Material, cộng 8 vai trò `voice*` cho C)

`ShellxIcons` là lớp `static const IconData` duy nhất của app. Chỗ gọi đặt tên vai trò, không đặt tên glyph. Glyph Cupertino đã kiểm có trong `cupertino/icons.dart` của Flutter 3.41.4.

| Vai trò | Glyph | Thay `Icons.*` | App |
|---|---|---|---|
| `add` | `CupertinoIcons.add` | `add` | DT+ĐT |
| `back` | `CupertinoIcons.chevron_back` | `arrow_back`, `arrow_back_ios_new` | DT+ĐT |
| `close` | `CupertinoIcons.xmark` | `close` | DT+ĐT |
| `more` | `CupertinoIcons.ellipsis` | `more_horiz` | DT+ĐT |
| `chevronRight` | `CupertinoIcons.chevron_right` | `chevron_right` | DT+ĐT |
| `expand` | `CupertinoIcons.chevron_down` | `expand_more`, `keyboard_arrow_down` | DT+ĐT |
| `collapse` | `CupertinoIcons.chevron_up` | `expand_less`, `keyboard_arrow_up` | DT+ĐT |
| `openExternal` | `CupertinoIcons.arrow_up_right_square` | `open_in_new` | DT+ĐT |
| `refresh` | `CupertinoIcons.arrow_clockwise` | `refresh` | DT+ĐT |
| `search` | `CupertinoIcons.search` | `search`, `search_off` | DT+ĐT |
| `settings` | `CupertinoIcons.gear_alt` | `settings_outlined` | DT+ĐT |
| `tune` | `CupertinoIcons.slider_horizontal_3` | `tune` | DT |
| `edit` | `CupertinoIcons.pencil` | `edit_outlined` | DT+ĐT |
| `moveFile` | `CupertinoIcons.square_pencil` | `drive_file_rename_outline` (thẻ tool AI, kind `move`) | DT+ĐT |
| `delete` | `CupertinoIcons.trash` | `delete_outline` | DT+ĐT |
| `copy` | `CupertinoIcons.doc_on_doc` | `copy` | ĐT |
| `undo` | `CupertinoIcons.arrow_uturn_left` | `undo` | DT |
| `send` | `CupertinoIcons.arrow_up` | `send`, `arrow_upward` | DT+ĐT |
| `queue` | `CupertinoIcons.text_badge_plus` | `playlist_add` | ĐT |
| `stop` | `CupertinoIcons.stop_fill` | `stop`, `stop_rounded` | DT+ĐT |
| `stopCircle` | `CupertinoIcons.stop_circle` | `stop_circle_outlined` | DT |
| `scrollToEnd` | `CupertinoIcons.arrow_down` | `arrow_downward` | DT+ĐT |
| `maximize` | `CupertinoIcons.arrow_up_left_arrow_down_right` | `fullscreen`, `open_in_full` | DT |
| `restore` | `CupertinoIcons.arrow_down_right_arrow_up_left` | `close_fullscreen` | DT |
| `sidePanel` | `CupertinoIcons.sidebar_right` | `vertical_split_outlined` | DT |
| `splitRight` | `CupertinoIcons.square_split_2x1` | `view_column_outlined` | DT |
| `splitDown` | `CupertinoIcons.square_split_1x2` | `view_agenda_outlined` | DT |
| `download` | `CupertinoIcons.arrow_down_to_line` | `download_outlined` | DT |
| `update` | `CupertinoIcons.arrow_down_circle` | `system_update_alt` | ĐT |
| `signOut` | `CupertinoIcons.square_arrow_right` | `logout` | ĐT |
| `mention` | `CupertinoIcons.at` | `alternate_email` | DT |
| `scanQr` | `CupertinoIcons.qrcode_viewfinder` | `qr_code_2` | ĐT |
| `keyboard` | `CupertinoIcons.keyboard` | `keyboard_outlined` | ĐT |
| `mic` | `CupertinoIcons.mic` | `mic_none` | ĐT |
| `micOn` | `CupertinoIcons.mic_fill` | `mic` | ĐT |
| `attachPhoto` | `CupertinoIcons.photo_on_rectangle` | `add_photo_alternate_outlined`, `photo_library_outlined` | ĐT |
| `camera` | `CupertinoIcons.camera` | `photo_camera_outlined` | ĐT |
| `pin` | `CupertinoIcons.pin_fill` | `push_pin` | DT |
| `resume` | `CupertinoIcons.arrow_counterclockwise` | `history_rounded` | DT |
| `history` | `CupertinoIcons.clock` | `history` | DT |
| `check` | `CupertinoIcons.checkmark` | `check`, `check_rounded` | DT+ĐT |
| `success` | `CupertinoIcons.checkmark_circle_fill` | `check_circle` | DT |
| `successOutline` | `CupertinoIcons.checkmark_circle` | `check_circle_outline` | DT |
| `failure` | `CupertinoIcons.xmark_circle_fill` | `cancel` | DT |
| `warning` | `CupertinoIcons.exclamationmark_triangle` | `warning_amber`, `warning_amber_rounded` | DT+ĐT |
| `error` | `CupertinoIcons.exclamationmark_circle` | `error_outline` | DT+ĐT |
| `danger` | `CupertinoIcons.exclamationmark_octagon` | `dangerous_outlined` | ĐT |
| `info` | `CupertinoIcons.info_circle` | `info_outline` | DT+ĐT |
| `infoFill` | `CupertinoIcons.info_circle_fill` | `info` | ĐT |
| `pending` | `CupertinoIcons.clock` | `schedule` | DT |
| `waiting` | `CupertinoIcons.hourglass` | `hourglass_empty` | DT |
| `dotFill` | `CupertinoIcons.circle_fill` | `circle` | DT |
| `dot` | `CupertinoIcons.circle` | `circle_outlined`, `radio_button_unchecked` | DT |
| `radioOn` | `CupertinoIcons.largecircle_fill_circle` | `radio_button_checked` | DT |
| `checkboxOn` | `CupertinoIcons.checkmark_square_fill` | `check_box` | ĐT |
| `checkboxOff` | `CupertinoIcons.square` | `check_box_outline_blank` | ĐT |
| `checkboxMixed` | `CupertinoIcons.minus_square` | `indeterminate_check_box_outlined` | ĐT |
| `prOpen` | `CupertinoIcons.arrow_branch` | `call_split` | DT |
| `prMerged` | `CupertinoIcons.arrow_merge` | `merge_type` | DT |
| `offline` | `CupertinoIcons.wifi_slash` | `cloud_off_outlined`, `link_off` | DT+ĐT |
| `visible` | `CupertinoIcons.eye` | `visibility_outlined` | DT+ĐT |
| `hidden` | `CupertinoIcons.eye_slash` | `visibility_off_outlined` | ĐT |
| `notifications` | `CupertinoIcons.bell` | `notifications_none`, `notifications_active_outlined` | DT+ĐT |
| `notificationsUnread` | `CupertinoIcons.bell_fill` | `notifications` | DT |
| `notificationsOff` | `CupertinoIcons.bell_slash` | `notifications_off_outlined` | ĐT |
| `ai` | `CupertinoIcons.sparkles` | `auto_awesome` | DT+ĐT |
| `agentProgram` | `CupertinoIcons.chevron_left_slash_chevron_right` | `smart_toy_outlined` | DT |
| `thinking` | `CupertinoIcons.lightbulb` | `psychology_outlined` (thẻ tool AI, kind `think`) | DT+ĐT |
| `fetch` | `CupertinoIcons.globe` | `public`, `cloud_download_outlined` (thẻ tool AI, kind `fetch`) | DT+ĐT |
| `switchMode` | `CupertinoIcons.arrow_right_arrow_left` | `swap_horiz` (thẻ tool AI, kind `switchMode`) | DT+ĐT |
| `plan` | `CupertinoIcons.list_bullet` | `checklist` | ĐT |
| `file` | `CupertinoIcons.doc` | `description_outlined` | DT+ĐT |
| `readText` | `CupertinoIcons.doc_text` | `article_outlined` | DT+ĐT |
| `image` | `CupertinoIcons.photo` | `image_outlined`, `broken_image_outlined` | DT+ĐT |
| `folderMissing` | `CupertinoIcons.folder_badge_minus` | `folder_off_outlined` | DT |
| `tool` | `CupertinoIcons.square_grid_2x2` | `extension_outlined` (tool web V2-3) | DT+ĐT |
| `toolOther` | `CupertinoIcons.wrench` | `extension_outlined` (thẻ tool AI, kind `other`) | DT+ĐT |
| `tab` | `CupertinoIcons.square_on_square` | `tab` | DT |
| `tmux` | `CupertinoIcons.square_split_2x2` | `view_quilt_outlined` | DT |
| `lock` | `CupertinoIcons.lock` | `lock_outline`, `key_outlined` | DT+ĐT |
| `phone` | `CupertinoIcons.device_phone_portrait` | `phone_iphone_outlined`, `smartphone` | DT+ĐT |
| `laptop` | `CupertinoIcons.device_laptop` | `laptop_mac` | ĐT |
| `desktop` | `CupertinoIcons.device_desktop` | `desktop_windows_outlined` | ĐT |
| `terminal` | `Icons.terminal_rounded` (Material, dự phòng: Cupertino chỉ có `</>` là "code") | `terminal` | DT+ĐT |
| `faceId` | `Icons.face_rounded` (Material, dự phòng: Cupertino không có Face ID) | `face_outlined` | ĐT |
| `fingerprint` | `Icons.fingerprint_rounded` (Material, dự phòng: Cupertino không có vân tay) | `fingerprint` | ĐT |
| `sshHost` | `Icons.dns_rounded` (Material, dự phòng: Cupertino không có máy chủ) | `dns_outlined` | DT |
| `voiceMode` | `CupertinoIcons.waveform` | — (mới: nút vào chế độ giọng nói, V2-5c C2) | ĐT |
| `voiceMicOn` | `CupertinoIcons.mic` | — (mới: Tắt mic khi micro đang được phép mở, V2-5c) | ĐT |
| `voiceMicOff` | `CupertinoIcons.mic_slash` | — (mới: Bật mic; dấu trên sóng âm và quả cầu, V2-5c) | ĐT |
| `voiceEnd` | `CupertinoIcons.xmark` | — (mới: Kết thúc chế độ giọng nói, V2-5c) | ĐT |
| `voiceStopTurn` | `CupertinoIcons.stop_fill` | — (mới: Dừng lượt, V2-5c) | ĐT |
| `voiceExpand` | `CupertinoIcons.arrow_up_left_arrow_down_right` | — (mới: mở toàn màn hình, V2-5c) | ĐT |
| `voiceCollapse` | `CupertinoIcons.chevron_down` | — (mới: thu về thanh, V2-5c) | ĐT |
| `voiceNeedsYou` | `CupertinoIcons.exclamationmark_triangle` | — (mới: dấu "cần bạn cho phép", V2-5c) | ĐT |

Thẻ tool của AI (`ai_tool_card.dart:69-80` ở DT, `ai_items.dart` ở ĐT) dùng cùng một bảng ở hai app: `read` → `file`, `edit` → `edit`, `delete` → `delete`, `move` → `moveFile`, `search` → `search`, `execute` → `terminal`, `fetch` → `fetch` (hôm nay DT vẽ đám mây, ĐT vẽ quả địa cầu: nay cùng quả địa cầu), `think` → `thinking`, `switchMode` → `switchMode`, `other` → `toolOther`. Tool web của V2-3/V2-4 dùng `tool`. Hằng `kPhoneIcon` (`terminal_overlays.dart:441`) = `ShellxIcons.phone`. Hai vai trò `history` và `pending` cùng glyph đồng hồ: khác ngữ cảnh, giữ (sáu vai trò `voice*` cũng trùng glyph với `mic`, `close`, `stop`, `maximize`, `expand`, `warning` theo cùng luật). Tám vai trò `voice*` là của chế độ giọng nói (V2-5c §4.8); A khai chúng trong `ShellxIcons` cùng các vai trò khác, nên C không sửa package. B thêm vai trò mới của mình vào cùng lớp, với glyph ghi ở V2-5b §4.0 (ví dụ `folder`, `branch`); vai trò đã có trong bảng này thì B dùng đúng tên và glyph ở đây.

---

## 8. Màn hình đổi trong A

### 8.1 Desktop

| Khu vực | Tệp chính | Đổi gì |
|---|---|---|
| Khung cửa sổ, sidebar, hàng tab | `session_sidebar.dart`, `session_tab_row.dart`, `workspace_header.dart`, `sidebar_new_button.dart`, `sidebar_remote.dart`, `attention_marks.dart`, `agent_badge.dart`, `agent_chip.dart` | màu mới (§5.9); hàng đang chọn là ô nổi (`raisedSmall`) + vạch `cyan` 3×18; bo 10; tag dạng viên; chữ 12 (SF Mono/JetBrains Mono); icon `ShellxIcons`; kích thước giữ (220; hàng 30/46/62/78) |
| Pane và vùng làm việc | `terminal_pane.dart`, `pane_tree_view.dart`, `terminal_workspace_page.dart`, `ui/tools/*` (V2-3) | nền `navy900`; đường chia mảnh; vòng focus `cyan`; palette terminal mới; terminal mặc định theo §6.8 |
| Dải, pill, toast, trạng thái rỗng | `info_strip.dart`, `remote_strip.dart`, `resume_banner.dart`, `terminal_overlays.dart` | dải theo token; nút trên dải dùng `link`; toast bo 16; trạng thái rỗng có wedge góc trên phải và nút chính gradient |
| Overlay | `command_palette.dart`, `search_all_overlay.dart`, `shortcuts_sheet.dart`, `config_problems_panel.dart`, `notifications_panel.dart`, `tour_overlay.dart`, `whats_new_card.dart`, `find_bar.dart`, `key_sequence.dart` | nền `navy750`, bo 16, viền mảnh, `float1`; hàng hover `overlayHover`; ô nhập lõm |
| Menu, tooltip | `shellx_menu.dart`, `tooltipTheme` | §7.1 |
| Hộp thoại | `route_dialog.dart`, `dialog_layout.dart` (`DialogBody` thêm cờ `brand`), `pages/*`, `ssh_connect_dialog.dart`, `tools/tool_dialogs.dart`, 6 tệp dùng `AlertDialog` | bo 28, `navy750`, `float2`; nút chính gradient (`accentStrong`), nút phụ nổi, text button `link`; dòng thương hiệu ở đăng nhập/đăng ký/onboarding; ô QR giữ nền trắng |
| Cài đặt | `settings_overlay.dart` (`_NavItem`), `settings_row.dart`, `pages/*` | khung bo 28; mục nav đang chọn là ô nổi + vạch `cyan`; switch, slider, dropdown theo theme; ô nhập lõm; nút "Giấy phép và ghi công…" ở Chung |
| Pane AI (chỉ token và component) | `ui/ai/*` | chip cấu hình → `ShellxChip`; thẻ → `ShellxCard.flat`; nút → kiểu mới; `SegmentedButton` ở bảng Thay đổi → `ShellxSegmented`; link markdown `link`; thân markdown `dialogBody`; `kAiMono` theo họ chữ nền tảng; bố cục giữ (B) |
| Tên | `window_host.dart`, `terminal_pane.dart`, `tray_presenter.dart`, `main.dart`, `windows/runner/*`, `macos/Runner/*` | §4.1 |

### 8.2 Điện thoại

| Màn | Tệp chính | Đổi gì |
|---|---|---|
| Màn khởi động gốc | `LaunchScreen.storyboard`, hai `launch_background.xml`, `styles.xml` (`values`, `values-night`, `values-v31` mới), `values/colors.xml` | nền navy `#222834` (A48) |
| Splash | `splash_page.dart` | nền trang; `ShellxBrandHeader` ở giữa; wedge; `onGenerateTitle` |
| Đăng nhập, đăng ký | `login_page.dart`, `register_page.dart`, `password_text_field.dart`, `app_text_field.dart` | tiêu đề thương hiệu; wedge; ô nhập lõm bo 16; `AppButton` gradient + `cta` |
| Khoá | `lock_gate.dart`, `biometric_method.dart` | token; nút gradient; icon `faceId`/`fingerprint`/`lock` |
| Bắt cập nhật | `update_required_page.dart` | token; nút gradient; icon `update` |
| Danh sách máy | `machine_list_page.dart`, `connection_banner.dart`, `notice_banner.dart` | thẻ máy `flat` bo 16, viền mảnh; chấm online `ok`; trạng thái rỗng lần đầu: dòng thương hiệu + wedge + thẻ các bước là `ShellxGlass`; trạng thái lỗi; nút gradient |
| Quét QR | `qr_scanner_page.dart` | lớp phủ camera giữ (đen/trắng có chức năng); sheet lỗi và màn thành công theo token, nút gradient |
| Terminal | `terminal_page.dart`, `session_picker.dart` (cả nhóm Tool của V2-4), `extra_keys_bar.dart`, `arrow_pad.dart`, `keyboard_cover.dart`, `link_sheet.dart`, `view_as_text_sheet.dart`, `agent_reply_bar.dart` | chrome theo `TerminalColors` mới; sheet theo theme (bo 28); terminal SF Mono (iOS) / JetBrains Mono (Android); thanh phím phụ giữ kiểu bàn phím hệ thống, chỉ đổi màu nhấn |
| AI (chỉ token và component) | `ai_*` | chip, thẻ, sheet, nút theo component; icon `ShellxIcons`; bố cục giữ (B) |
| Trang tool (V2-4) | `tool_page.dart` | thanh trên theo token; icon |
| Cài đặt | `settings_page.dart`, `delete_account_page.dart` | nhóm là thẻ `flat` bo 16; switch, slider theo theme; chọn giao diện là `ShellxSegmented`; dòng phiên bản tên dài; trang giấy phép có dòng ghi công; nút xoá tài khoản là nút huỷ diệt |
| Toast, hộp thoại | `popup_handler.dart`, `confirm_dialog.dart` | toast mới; `AlertDialog` theo `dialogTheme` |
| Giọng nói (chỉ token và component) | `voice_composer.dart`, `mic_button.dart` | `FontFamily.raleway` ở `voice_composer.dart:184` bỏ; màu theo token; chọn ngôn ngữ `SegmentedButton<VoiceLocale>` → `ShellxSegmented` (A40); giao diện giọng nói mới là của C |

---

## 9. Chuỗi (EN / VI)

### 9.1 ARB

| Khoá | App | EN | VI |
|---|---|---|---|
| `appTitle` | DT, ĐT | ShellX: Remote AI agents | ShellX: Remote AI agents |
| `trayTooltip` | DT | ShellX: Remote AI agents | ShellX: Remote AI agents |
| `windowTitle` (giữ) | DT | {title} — ShellX | {title} — ShellX |
| `settingsVersion` | ĐT | ShellX: Remote AI agents {version} ({build}) | ShellX: Remote AI agents {version} ({build}) |
| `settingsLicenses` (mới) | DT (ĐT đã có khoá cùng tên cho mục Giấy phép của mình, giữ chữ cũ) | Licenses and credits… | Giấy phép và ghi công… |
| `licensesLegalese` (mới) | DT, ĐT | Visual style adapted from “Online Bike Shopping App” by Sourasith (Figma Community, CC BY 4.0). | Phong cách giao diện phỏng theo “Online Bike Shopping App” của Sourasith (Figma Community, CC BY 4.0). |

### 9.2 Ngoài ARB

| Nơi | Chuỗi |
|---|---|
| iOS `CFBundleDisplayName`; Android `android:label`; macOS `en.lproj/InfoPlist.strings` `CFBundleDisplayName`; Windows `FileDescription`; `main.cpp` (tiêu đề ban đầu); Inno `AppName`, `UninstallDisplayName` | `ShellX: Remote AI agents` |
| Inno `AppVerName` | `ShellX: Remote AI agents {#AppVersion}` |
| macOS `Info.plist` `CFBundleDisplayName` | `ShellX` |

### 9.3 Ghi công (`LicenseRegistry`, một mục, tiếng Anh, không dịch)

Tên mục: `Online Bike Shopping App (design reference)`. Nội dung:

> ShellX's visual style (colours, shapes and gradients) is adapted from "Online Bike Shopping App" by Sourasith (https://www.figma.com/@sourasithp), Figma Community file https://www.figma.com/community/file/1149336740234053658, licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Changes: colours re-tuned for contrast; components rebuilt for ShellX. No images or artwork from the file are used.

---

## 10. Kiểm thử

### 10.1 Package (`packages/shellx_design/test`, chạy `flutter test` trong package; plan thêm lệnh này vào nơi đang chạy test của các package khác)

- `palette_test.dart`: đúng hex mọi hằng ở §5.3–§5.7; điểm màu gradient; bán kính, khoảng cách, thời lượng, đổ bóng (§5.8).
- `contrast_test.dart`:
  - mọi cặp ghi số ở §5.3–§5.7 với ngưỡng của nó (chữ 4.5, phi chữ 3);
  - `minContrastOnGradient(accent, white) ≥ 3.0`, `(accentStrong, white) ≥ 4.5`; cùng hai gradient khi phủ đen 8 % và 16 % vẫn đạt; `wedge ≥ 3.0`;
  - trên `compositeOver(glassFill, accentLight)`: `white100`, `white87`, `white75` ≥ 4.5, còn `white60` < 4.5 (giữ lý do của quy tắc kính);
  - ANSI ≥ 4.5 trên nền terminal; chữ trên vùng chọn ≥ 4.5.
- `fonts_test.dart`: `uiFamily`/`uiFallback` theo nền tảng (iOS, macOS → `'SF Mono'` + `['JetBrainsMono']`; Android, Windows, Linux → `'JetBrainsMono'` + `[]`); `shellxWeight` đặt cả `fontWeight` và `wght`; `ShellxTypeScale` đúng bảng §6.5 (cỡ mới, chiều cao dòng px như cũ).
- `system_font_test.dart` (kênh giả, bộ nạp giả):
  - có byte → bộ nạp nhận họ `'SF Mono'` với bản thường và bản nghiêng;
  - lỗi, `null`, `missing` không rỗng, quá 500 ms → không nạp, trả `fallback(reason)` đúng, không ném lỗi;
  - Android/Windows: không gọi kênh; `enabled = false`: không gọi kênh;
  - log chỉ có `reason`.
- `icons_test.dart`: mọi hằng `ShellxIcons` có `fontFamily == 'CupertinoIcons'` và `fontPackage == 'cupertino_icons'`, trừ đúng 4 vai trò dự phòng (`MaterialIcons`); tám vai trò `voice*` có đúng glyph ở §7.4; `pubspec.yaml` ghim `cupertino_icons: 1.0.9`.
- `widgets_test.dart`: `ShellxWedge` (đa giác đúng góc, không semantics, không nhận chạm); `ShellxGlass` (có `BackdropFilter` chỉ khi `blur: true`); `ShellxInsetBox` (vẽ bóng trong); `ShellxSlantBorder` (đường viền); `shellxGradientLayer` (phủ đúng theo hover, nhấn, tắt; bo đúng góc).
- `no_bundled_sf_test.dart`: quét repo từ gốc workspace: không tệp tên chứa `SF-Mono`, `SFNSMono` hay `SFMono`; không khai báo font nào tên "SF Mono" trong mọi `pubspec.yaml`.

### 10.2 Desktop

- `test/ui/theme_test.dart` viết lại:
  - token trỏ đúng hằng của package và đúng hex mới;
  - họ chữ theo nền tảng (`debugDefaultTargetPlatformOverride` = macOS → `'SF Mono'` + dự phòng `JetBrainsMono`; Windows → `'JetBrainsMono'`); `uiFont()` chép cả danh sách dự phòng;
  - `ShellxText` đúng §6.5; nền hàng tăng dần (hover < selected < pressed), selected so với sidebar 1.32 > 1.25;
  - component theme đủ (A39).
- Ghim hex cũ phải đổi (viết lại qua token): `notifications_panel_test.dart:397` (`0xFF1F2F34`), `attention_ring_test.dart:70, 77`, `find_bar_test.dart:10-11`, `find_session_test.dart:7-8` (từ `#5FD4E2` sang `accent` mới), `app_dialogs_test.dart:466` (núm switch khi bật → `onPrimary`).
- Nút: `ShellxPrimaryButton` và `FilledButton` trong hộp thoại có `backgroundBuilder` vẽ `accentStrong`, chữ trắng, hover/nhấn/tắt, vòng focus ngoài; widget vẫn là `FilledButton` (test cũ tìm theo key vẫn chạy).
- Component mới: `ShellxChip`, `ShellxSegmented` (←/→, một tab stop, semantics chọn), `ShellxCard`, `ShellxBrandLine`.
- Tên: §4.3 và `test/platform/identity_pins_test.dart`.
- Terminal: `terminal_style_test.dart` (macOS: `'SF Mono'` với 300/400/700 và dự phòng JetBrains Mono; Windows như cũ); `terminal_font_weight_test.dart` giữ.
- Font: `test/ui/font_coverage_test.dart` đọc `cmap` của `assets/fonts/JetBrainsMono-*.ttf`: đủ 134 chữ và 5 dấu.
- Hình học: test có bề rộng phụ thuộc cỡ chữ cập nhật số mới; không nới lỏng dạng khẳng định. Chiều cao không đổi (dòng px giữ).

### 10.3 Điện thoại

- `test/core/design/design_tokens_test.dart` viết lại:
  - hex mới cho cả hai độ sáng;
  - giữ 11 cặp tương phản cũ cho cả hai độ sáng (với giá trị mới), thêm: `onAccent` trên `accent`/`accentStrong`, chữ trên `raised` và `inset`, placeholder trên `inset`;
  - `AppButton`: cao 54, bo 10, `Ink` có gradient `accent`, chữ `onAccent`, tắt 0.45; khi `textScaler.scale(15) < 15` thì `accentStrong`.
- `settings_page_test.dart`: `SegmentedButton<AdaptiveThemeMode>` → `ShellxSegmented<AdaptiveThemeMode>` (`:224-265`); dòng phiên bản (`:172, 277, 557`); test "2× chữ trên 320 pt, không nhãn nào bị cắt" giữ và phải xanh.
- `terminal_page_test.dart:1555-1561`: ô giọng nói và gợi ý không tự đặt họ chữ (`fontFamily == null`); họ chữ hiệu lực là của theme (iOS `'SF Mono'`, Android `'JetBrainsMono'`); `:1528` tìm `ShellxSegmented<VoiceLocale>` thay `SegmentedButton<VoiceLocale>` (A40); `:138` giữ (theo token).
- `platform_config_test.dart`: §4.3; thêm: không còn tệp `Raleway-*` và không còn khai báo Raleway.
- Mặc định giao diện (A26): ba trường hợp với `SharedPreferences` giả (đã lưu chế độ; cài mới; người dùng cũ).
- Component mới: `ShellxBottomBar` (chọn, ô trượt, semantics `selected` + `inMutuallyExclusiveGroup`, chữ tối đa 1.3×, giảm chuyển động thì nhảy thẳng, huy hiệu), `ShellxSegmented`, `ShellxChip`, `ShellxCard`, `ShellxBrandHeader` (2 dòng ở 320 pt), toast (tối: nền `navy750`, không trắng), sheet theo theme (bo 28, tay kéo).
- Font: `test/core/design/font_coverage_test.dart` cho `assets/fonts/JetBrainsMono-*.ttf`.

### 10.4 Guard chống style cứng (cả hai app, `test/design/raw_style_guard_test.dart`)

- Quét `lib/**/*.dart`, trừ tệp sinh (`*.g.dart`, `*.gr.dart`, `*.config.dart`, `*.gen.dart`, `lib/l10n/**`, `shared/src/l10n.dart`, `shared/src/intl/**`) và adapter (`lib/src/ui/theme/**` của DT, `lib/core/design/**` của ĐT).
- Đếm theo tệp: `Color(0x`, `Color.fromARGB(`, `Color.fromRGBO(`, `Colors.` (trừ `Colors.transparent`), `TextStyle(`, `fontSize:`, `fontWeight:`, `fontFamily:`, `BoxShadow(`, `BackdropFilter(`, `ImageFilter.blur(`, `Icons.`, `CupertinoIcons.`. Mỗi mẫu chỉ khớp khi không có chữ, số hay `_` đứng ngay trước nó, nên `AppColors.`, `ShellxDesktopColors.`, `ShellxIcons.` không bị đếm và `Icons.` không khớp bên trong `CupertinoIcons.`.
- So với bảng gốc `test/design/raw_style_baseline.dart` (tệp → mẫu → số) và phải **khớp đúng**: số tăng thì hỏng ("style cứng mới"); số giảm thì hỏng kèm lời nhắc hạ bảng gốc. Bảng gốc lập ở commit đầu của A rồi hạ dần. Sau A: `Icons.`, `CupertinoIcons.`, `fontWeight:` đều 0; `BackdropFilter(` và `ImageFilter.blur(` chỉ còn 1 mỗi loại ở `qr_scanner_page.dart` (A44); `popup_handler.dart` 0.
- Adapter: `lib/src/ui/theme/*.dart` (DT) và `lib/core/design/*.dart` (ĐT) không có `Color(0x` (mọi màu từ package).

### 10.5 Hiệu năng

- DT: sidebar 30 tab, một tab đang chọn: cây con của sidebar có ≤ 2 `BoxShadow`.
- ĐT: danh sách 8 máy: 0 `BoxShadow` trong các mục; phiên AI 50 mục: 0 trong dòng thời gian.
- `ShellxGlass` không có trong cây của trang terminal và trang tool. Trên trang phiên AI, `ShellxGlass` nằm trên bản ghi (thẻ ô soạn của B, thanh giọng nói của C) có `blur: false`: không có `BackdropFilter` trong cây khi lớp phủ toàn màn hình của C đóng.
- `BackdropFilter` chỉ nằm dưới `ShellxGlass`, trừ chỗ có sẵn của màn quét QR (guard).

---

## 11. Review Focus

1. **Tên dài lọt vào định danh.** Ai đó đổi `ProductName`, `PRODUCT_NAME`, `BINARY_NAME`, `appName`, tên shortcut hay bundle id → dời thư mục dữ liệu, mất đăng nhập, shortcut và AUMID thứ hai. Test: `identity_pins_test.dart`, `platform_config_test.dart`.
2. **SF Mono dùng sai.** Không thật sự được dùng (họ chữ sai, nạp sau khung đầu, lặng lẽ rơi về JetBrains Mono); bị đóng gói, ghi đĩa hay gửi đi (vi phạm giấy phép); độ đậm sai vì font biến thiên (chữ đậm thành Light). Test: kênh giả, `no_bundled_sf_test`, `shellxWeight` và guard `fontWeight:`; spike tiêu chí 3 và 4.
3. **Tương phản.** Chữ nhỏ trên `accent` thay vì `accentStrong`; chữ phụ trên kính hay wedge; link trên bề mặt nổi; hover làm tụt tương phản; light mode. Test: `contrast_test.dart`, test component.
4. **Theme sót hoặc nhầm vai trò.** Widget Material lấy màu từ seed; toast trắng; `onPrimary` (mực navy) trên gradient; icon Material mới lọt vào. Test: guard, `theme_test.dart`, `design_tokens_test.dart`.
5. **Hiệu năng và tràn chữ.** Bóng hay làm mờ trong danh sách; giao diện đơn cách làm tràn chữ (pill, nút, nhãn thanh dưới ở 1.3×, tiêu đề thương hiệu ở 320 pt). Test: §10.5, test 2× chữ; kiểm tay §12.

---

## 12. ⚠ Kiểm tay (cần người: Mac, máy Windows, iPhone, điện thoại Android)

1. **Spike SF Mono** (§6.3) trên Mac (macOS 26), iPhone thật (iOS 26/27), simulator iOS: đủ năm tiêu chí. Thử nhánh dự phòng bằng `--dart-define=FORCE_BUNDLED_MONO=true`.
2. **macOS:** Finder, Launchpad, Spotlight, Dock, ⌘-Tab, Mục đăng nhập, hộp xin quyền hiện tên dài; thanh menu và About là "ShellX". Cập nhật từ 1.0.0 bằng dmg (thay `ShellX.app`): vẫn đăng nhập, điện thoại vẫn vào. Tiêu đề cửa sổ khi không có tab và khi có tab; tooltip khay.
3. **Windows:** cài đè lên 1.0.0: Cài đặt › Ứng dụng có một mục "ShellX: Remote AI agents"; shortcut Start và desktop vẫn "ShellX" và mở được; toast vẫn hiện; Task Manager và trang Khởi động hiện tên dài; vẫn đăng nhập; trình cài tiếng Việt và tiếng Anh đọc được; gỡ cài sạch.
4. **iPhone:** màn hình chính (tên bị cắt), Cài đặt › Ứng dụng, Spotlight; màn khởi động navy (gỡ rồi cài lại để bỏ bộ nhớ đệm launch screen); máy cài mới mở lần đầu ở chế độ tối; người dùng cũ giữ "Theo máy"; light mode; hộp xin quyền.
5. **Android 10, 14, 16:** launcher, Recents, đầu thông báo, Cài đặt › Ứng dụng; splash navy (Android 12+ có splash hệ thống); JetBrains Mono trên toàn giao diện.
6. **Đọc được** (§6.7, A36): Windows 100 % và 125 %, macOS: sidebar 30 tab, menu, tooltip, Cài đặt, palette. Ghi kết quả vào PR.
7. **Độ rộng:** tên tab dài có "…" và tooltip; pill người lái ở pane 520–560 px; nút hộp thoại; nhãn thanh dưới ở 1.3× chữ (màn thử của component); tiêu đề thương hiệu ở máy 320 pt (2 dòng) và 375 pt (1 dòng).
8. **Icon:** dấu 12–14 px ở sidebar (điện thoại, mắt, ghim, SSH, tmux) đọc ra; hướng `splitRight` (hai ô cạnh nhau) và `splitDown` (hai ô chồng nhau) đúng; bốn glyph Material dự phòng không lạc tông.
9. **Gõ tiếng Việt:** Telex/VNI trong ô nhập lõm (gạch chân lúc soạn chữ hiện rõ); chữ tổ hợp (ký tự + dấu kết hợp) hiện đúng trong SF Mono và JetBrains Mono.
10. **Tương phản:** soi màu nút gradient ở góc sáng, chip đang chọn, kính trên wedge, link trên thẻ nổi; cả tối và sáng.
11. **Hiệu năng:** Android tầm trung (Impeller) cuộn danh sách 8 máy, phiên AI 200 mục, Cài đặt, màn có kính; DevTools không có khung raster > 16 ms khi cuộn. Laptop Windows ở 100 %: cuộn sidebar 30 tab, mở palette, Cài đặt. Mac Retina tương tự.
12. **Terminal:** macOS SF Mono Light mặc định; `font-weight = regular` ra Regular; ô đậm đậm thật; iOS SF Mono; số cột ít hơn hôm nay khoảng 3 %; vim và htop căn ô đúng; `font-family` của người dùng vẫn thắng.
13. **Giấy phép:** ĐT Cài đặt › Giấy phép có dòng ghi công và mục "Online Bike Shopping App (design reference)"; DT Cài đặt › Chung › "Giấy phép và ghi công…" mở trang; không có mục SF Mono.
14. **VoiceOver, TalkBack:** thanh dưới (màn thử), segmented, nút gradient; logo đọc tên dài.

---

## 13. Phạm vi, thứ tự, việc sau

### 13.1 Phạm vi

**Trong A:** §3–§10.

**Ngoài A:** bố cục màn AI và trang chủ AI (B); giao diện giọng nói (C); website, tên trên store; icon app và icon khay; light mode cho DT; đổi tên shortcut Windows; màu thanh tiêu đề Windows.

### 13.2 Việc sau

| Việc | Ai | Ghi chú |
|---|---|---|
| Đổi tên trên App Store Connect và Play Console thành "ShellX: Remote AI agents" (24 ký tự, dưới trần 30) | người dùng, trong console | ngoài repo |
| Website `web/**`: `src/i18n/ui.ts`, `Base.astro` (`application-name`, `og:site_name`, chân trang), `public/site.webmanifest` (`name`, `short_name`), JSON-LD ở `Home.astro`, các trang pháp lý | cần người dùng đồng ý (đẩy `main` là triển khai) | chỉ liệt kê |
| Gộp ba dòng Inno vào `main` | người dùng duyệt (file của đồng đội) | A10 |
| Icon app mới hợp nền navy (cả icon khay, nền icon thích ứng Android `#140F2A`) | việc riêng | ngoài A |
| Màu thanh tiêu đề Windows 11 (DWM caption) theo navy | việc riêng | cần mã native |
| Đổi tên token cũ (`r6` → `control`, `display32` → tên theo vai trò) | sau B và C | đổi chỗ gọi hàng loạt |
| Đưa JetBrains Mono vào package (một bản cho hai app) | sau | đổi đường dẫn tài nguyên, test pixel |
| Font OFL gần SF Mono hơn cho Android/Windows | tuỳ chọn | phải kiểm tiếng Việt từ tệp font |

### 13.3 Thứ tự gợi ý cho plan

1. Spike SF Mono (§6.3).
2. Package: token, test token và tương phản.
3. Adapter DT và ĐT (màu, thang chữ, họ chữ, nạp font); guard với bảng gốc.
4. Tên (§4) và test ghim.
5. Component (§7.1) và test.
6. Icon: `ShellxIcons` và đổi toàn bộ `Icons.*` trong một commit riêng.
7. Màn hình (§8).
8. Màn khởi động gốc, giấy phép.
9. Kiểm tay (§12).

---

## 14. Rủi ro

| Rủi ro | Mức | Xử lý |
|---|---|---|
| Nạp SF Mono không chạy trên một bản iOS/macOS, hoặc bị chặn sau này | Trung bình | Spike trước; tự rơi sang JetBrains Mono; hằng tắt |
| Việc đọc bảng font hệ thống bị coi là vi phạm giấy phép | Thấp | Chỉ hiển thị, trong bộ nhớ; không đóng gói, ghi, gửi; hằng tắt (A32) |
| Font biến thiên: độ đậm không ăn (chữ đậm thành Light) | Trung bình | `shellxWeight` mọi nơi; guard `fontWeight:`; spike tiêu chí 4 |
| Giao diện đơn cách rộng làm tràn hay cắt chữ | Trung bình | Thang −1 px, dòng px giữ; test 2× chữ; kiểm tay §12 mục 7 |
| JetBrains Mono khó đọc ở 11–12 px trên Windows 100 % | Trung bình | A36: +1 px trên Windows |
| Tên dài lọt vào định danh | Thấp | §4.2, test ghim |
| Finder không hiện tên bản địa hoá, hoặc dấu `:` hiện lạ | Thấp–TB | Kiểm tay; gỡ một tệp |
| Glyph Cupertino khó đọc ở 12–14 px trên DT | Trung bình | Đổi glyph một chỗ trong `ShellxIcons` |
| B, C đặt chữ sai gradient hay sai bề mặt | Trung bình | Test tương phản và guard chạy cho mọi commit |
| Android tầm thấp giật khi cuộn | Trung bình | Ngân sách bóng và làm mờ; test §10.5 |
| Xung đột khi gộp vì A chạm rất nhiều tệp | Cao | A làm trước B, C; không đổi bố cục AI; đổi icon trong một commit riêng |
| File Inno của đồng đội | Thấp–TB | Chỉ ba dòng; báo người dùng |
| Theme terminal của người dùng đổi màu ở khoá họ không khai | Thấp | Ghi trong ghi chú phát hành |
| Logo cũ (teal) trên nền navy | Thấp | Việc sau: icon app |
| Dung lượng app | Thấp | DT không thêm font; ĐT bỏ Raleway; font icon được tree-shake |

---

## 15. Mục mở

Không có. Dự phòng font trên iPhone và Mac đã chốt: không nạp được SF Mono thì dùng JetBrains Mono, không dùng Menlo (Menlo chỉ có 88/134 chữ tiếng Việt, §6.4; A33).
