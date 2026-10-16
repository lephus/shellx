# Binding requirements for the Task 15 review (verbatim from the spec and the plan)

## Spec decisions this task implements (spec §3, Vietnamese, verbatim)
| D4 | Mở tool | Từ: hàng tool trên sidebar; nút tool (🧩) trên thanh pane AI; bảng lệnh ("Mở tool: <tên>", "Thêm tool…"); thẻ dự án trong Cài đặt. Mở tool thì vùng tool của workspace đó mở và tool thành tool đang xem. Tool thuộc workspace khác workspace của tab đang chọn: chọn tab gần nhất của workspace đó trước (không có tab nào thì vùng nội dung để trống, vùng tool vẫn hiện). Tab AI đang mở panel Thay đổi/Tệp thì panel đóng lại khi vùng tool mở (như demo); người dùng mở lại được. | — |
| D7 | Windows | Engine `webview_win_floating` 3.0.3: một cửa sổ WebView2 thật đặt trên cửa sổ Flutter, theo interface của `webview_flutter`, nên dùng chung mã engine với macOS. **Chưa ai chạy trên máy Windows thật**, nên khoá tệp `tool-embed = auto | on | off` (mặc định `auto`): `auto` là nhúng trên macOS, **mở bằng trình duyệt hệ thống trên Windows**. Khi nhúng trên Windows: Flutter không vẽ được lên trên WebView2, nên mỗi khi có lớp phủ (hộp thoại, menu, bảng lệnh, panel thông báo, tìm kiếm) ShellX ẩn trang và hiện một tấm thay thế mang tên tool; khi trang giữ bàn phím, phím tắt ShellX không tới (bấm ra ngoài trang để dùng). **Loại bỏ:** `webview_windows` 0.4.0 vendored (bản cuối 02/2024, lỗi #230 làm chết phím tắt khi bấm vào trang, năm bản vá C++ không kiểm được từ đây); bản fork `webview_flutter_windows` (cần Flutter ≥ 3.44). | Người dùng Windows mở tool bằng trình duyệt cho tới khi chạy bước kiểm §11.2 và đổi `auto`. |
| D8 | Dữ liệu web | **Một kho dữ liệu chung cho mọi tool**, tách khỏi Safari/Chrome/Edge, **giữ qua các lần mở ShellX** (giữ đăng nhập). macOS: kho mặc định của app (`WKWebsiteDataStore.default()`, `~/Library/WebKit/<bundle id>`). Windows: thư mục dữ liệu `%LOCALAPPDATA%\ShellX\tools`, profile `tools`. Cài đặt có "Xoá dữ liệu của tool" (xoá hết, hỏi lại trước). **Loại bỏ** mỗi tool một kho: macOS cần `WKWebsiteDataStore(forIdentifier:)` (macOS 14+, app hỗ trợ từ 12) và phải vá plugin. | Hai tool ở `localhost` dùng cùng tên cookie thì đè nhau, y như trong trình duyệt thường (cookie không tách theo cổng, RFC 6265 §8.5). |
| D15 | Cờ điện thoại | Mặc định tắt. Bật ở: hộp thoại Thêm tool, nút 📱 trên thanh của tool, menu chuột phải của hàng tool, thẻ dự án. **Chỉ tool `http` trên máy này** (`localhost`, `127.0.0.1`, `[::1]`) bật được (V2-4 E1); tool khác thấy nút mờ kèm lý do "Chỉ tool http trên máy này mở được trên điện thoại." Tắt cờ thì V2-4 đóng ngay mọi kết nối của điện thoại tới tool đó. | — |
| D20 | Khi nào không nhúng | `tool-embed = off`, hoặc `auto` trên Windows: mọi lối mở tool (D4) mở URL bằng trình duyệt hệ thống, vùng tool không hiện; hàng tool trên sidebar có ↗. Phím ⌘⇧B lúc đó mở hộp thoại Thêm tool khi workspace chưa có tool, còn không thì không làm gì. | — |
| D22 | Cài đặt | **Cài đặt › Dự án:** thẻ mỗi dự án có danh sách tool (tên, URL, cờ điện thoại, Sửa, Xoá) và "Thêm tool". Cuối trang: "Dữ liệu của tool: Xoá…" và "Hiện tool trong ShellX: Tự động / Luôn / Không, mở bằng trình duyệt" (chính là `tool-embed`). | — |
| D23 | Sửa, xoá | Sửa tên, URL, cờ điện thoại trong cùng hộp thoại. Đổi URL thì trang đang mở tải lại ở URL mới. Xoá hỏi lại ("Xoá tool "Bảng việc"? Trang của nó đóng lại. Dữ liệu web của nó không bị xoá."), đóng chip và trang. | — |
| D24 | Riêng tư | Không log URL, đường dẫn, tiêu đề trang, nội dung; chỉ log loại lỗi. `toString()` của tool trả `Tool(…)`. Không gửi gì ra ngoài máy: trang tải thẳng từ URL của tool. | — |

## Spec §4.3 strings this task shows (verbatim)
| `toolsGroup` | Tools | Tool |
| `toolAdd` | Add tool | Thêm tool |
| `toolPhoneOnlyLocal` | Only http tools on this computer can open on a phone. | Chỉ tool http trên máy này mở được trên điện thoại. |
| `toolClearData` | Clear tool data… | Xoá dữ liệu của tool… |
| `toolClearDataConfirm` | Sign every tool out and clear its cookies and storage? | Đăng xuất mọi tool và xoá cookie, bộ nhớ của chúng? |
| `toolEmbedSetting` | Show tools in ShellX | Hiện tool trong ShellX |
| `toolEmbedAuto` / `On` / `Off` | Automatic / Always / No, open in browser | Tự động / Luôn / Không, mở bằng trình duyệt |

## The plan's rulings this task consumes (verbatim)
- **R16 — clearing tool data on Windows.**
  - With a live page: `clearCache()`, which is WebView2's `ClearBrowsingDataAll` on the shared `tools` profile.
  - Without one: the `%LOCALAPPDATA%\ShellX\tools` folder is deleted.
  - *Cost if wrong:* data WebView2 keeps outside the profile's browsing data stays until a clear with no page open.
- **R20 — adding from the window opens the tool; adding from Settings does not.** The window's entry points are the sidebar footer, ⌘⇧B with no tool, the palette and the AI header. *Cost if wrong:* one more click after adding in Settings.

## Controller rulings added to this task (verbatim from the ledger)
- (a) its first test drives `settings.tool.<id>.edit` (rename through the card's Edit, Save → the registry has the new name) so its title's "edit" is true (no new test); (b) the brief's `confirmClearToolData` already catches a failed `clearAll` and logs only `runtimeType` (chunk 2's carried Windows FileSystemException item: `WinFloatingDataStore.clearAll` can throw while a just-closed page's WebView2 is still exiting) — pin it with one test (the fake store throws a FileSystemException carrying a path → no crash, the one log line is `tool data not cleared (FileSystemException)`, no path) — D24.

## The plan's Global Constraints and the controller's rulings (sections B, C, E)
Read sections B, C and E of: /Users/richard/Documents/helper/shellx/.superpowers/sdd/2026-10-15-v2-3-tools-desktop/constraints.md
- Suite totals: the plan's numbers + 58 (earlier tasks' ruled tests) + this task's ruled test; Task 15's expected total is 3848 passed, 9 skipped (plan 3789 + 58 + 1).
