# Binding requirements for the Task 14 review (verbatim from the spec and the plan)

## Spec decisions this task implements (spec §3, Vietnamese, verbatim)
| D4 | Mở tool | Từ: hàng tool trên sidebar; nút tool (🧩) trên thanh pane AI; bảng lệnh ("Mở tool: <tên>", "Thêm tool…"); thẻ dự án trong Cài đặt. Mở tool thì vùng tool của workspace đó mở và tool thành tool đang xem. Tool thuộc workspace khác workspace của tab đang chọn: chọn tab gần nhất của workspace đó trước (không có tab nào thì vùng nội dung để trống, vùng tool vẫn hiện). Tab AI đang mở panel Thay đổi/Tệp thì panel đóng lại khi vùng tool mở (như demo); người dùng mở lại được. | — |
| D15 | Cờ điện thoại | Mặc định tắt. Bật ở: hộp thoại Thêm tool, nút 📱 trên thanh của tool, menu chuột phải của hàng tool, thẻ dự án. **Chỉ tool `http` trên máy này** (`localhost`, `127.0.0.1`, `[::1]`) bật được (V2-4 E1); tool khác thấy nút mờ kèm lý do "Chỉ tool http trên máy này mở được trên điện thoại." Tắt cờ thì V2-4 đóng ngay mọi kết nối của điện thoại tới tool đó. | — |
| D18 | Trợ năng | Mọi nút có nhãn đọc được; chip là nút có trạng thái chọn. VoiceOver đọc trong trang chỉ ở mức platform view của Flutter cho phép (issue #41722 còn mở); "Mở bằng trình duyệt" là lối thay thế. | Người dùng trình đọc màn hình nên dùng trình duyệt. |
| D20 | Khi nào không nhúng | `tool-embed = off`, hoặc `auto` trên Windows: mọi lối mở tool (D4) mở URL bằng trình duyệt hệ thống, vùng tool không hiện; hàng tool trên sidebar có ↗. Phím ⌘⇧B lúc đó mở hộp thoại Thêm tool khi workspace chưa có tool, còn không thì không làm gì. | — |
| D21 | Sidebar | Dưới mỗi workspace có tool: nhóm **"Tool"** (thu gọn được), mỗi tool một hàng: 🧩, tên, dòng phụ `host:port` (thêm "· cả điện thoại" khi bật cờ). Hàng sáng lên khi nó là tool đang xem của vùng tool đang mở. Chuột phải: Mở, Mở bằng trình duyệt, Sửa…, Cho mở trên điện thoại, Xoá… Chân sidebar: nút **"Thêm tool"** cạnh "Phiên AI mới"; thêm vào workspace của tab đang chọn. | — |
| D23 | Sửa, xoá | Sửa tên, URL, cờ điện thoại trong cùng hộp thoại. Đổi URL thì trang đang mở tải lại ở URL mới. Xoá hỏi lại ("Xoá tool "Bảng việc"? Trang của nó đóng lại. Dữ liệu web của nó không bị xoá."), đóng chip và trang. | — |
| D24 | Riêng tư | Không log URL, đường dẫn, tiêu đề trang, nội dung; chỉ log loại lỗi. `toString()` của tool trả `Tool(…)`. Không gửi gì ra ngoài máy: trang tải thẳng từ URL của tool. | — |

## Spec §4.1 layout and §4.3 strings this task shows (verbatim)
| `toolsGroup` | Tools | Tool |
| `toolAdd` | Add tool | Thêm tool |
| `toolPhoneOnlyLocal` | Only http tools on this computer can open on a phone. | Chỉ tool http trên máy này mở được trên điện thoại. |
| `toolAlsoPhone` | · on phone too | · cả điện thoại |
| `toolOpenInBrowser` | Open in browser | Mở bằng trình duyệt |
| `toolDeleteConfirm` | Delete the tool "{name}"? Its page closes. Its web data stays. | Xoá tool "{name}"? Trang của nó đóng lại. Dữ liệu web của nó không bị xoá. |

## Success criterion 1 (verbatim)
1. **Thêm nhanh.** Từ nút "Thêm tool" ở chân sidebar: chọn một gợi ý cổng, bấm "Thêm". Sau ≤ 3 lần bấm, vùng tool mở và trang hiện lên.

## The plan's rulings this task consumes (verbatim)
- **R11 — tool rows are not arrow-key stops, and group folding lasts for the run.** A2's arrow navigation walks tabs only; ⌘⇧P "Open tool: …" reaches every tool. *Cost if wrong:* keyboard users open tools from the palette.
- **R14 — a workspace shown without a tab ("loose", D4).**
  - Opening a tool of a workspace with no tab shows that workspace's dock beside an empty content area. The tab selected before stays selected underneath.
  - Pane commands (split, break, paste, focus) do nothing there. ⌘T and "New AI session" open the new tab in that workspace.
  - Any tab selection ends it. It is not restored.
  - *Cost if wrong:* after a restart, the dock of a workspace without tabs shows only when one of its tools is opened again.
- **R20 — adding from the window opens the tool; adding from Settings does not.** The window's entry points are the sidebar footer, ⌘⇧B with no tool, the palette and the AI header. *Cost if wrong:* one more click after adding in Settings.

## Controller ruling added to this task (verbatim from the ledger)
- R14 in the sidebar's own keyboard selection: session_sidebar.dart's `_onKey` selects tabs through `workspaces.step`/`selectVisible` (one workspace) and `go(i)` → `select(target)` (several); arrowing off the tab still selected under a loose workspace and back re-selects the same id and loose stays. Add `clearLoose()` where those paths select a tab (not on a header move), with one test (two workspaces, loose B, the sidebar cursor on the tab underneath: down to B's header, up again → loose ends).

## The plan's Global Constraints and the controller's rulings (sections B, C, E)
Read sections B, C and E of: /Users/richard/Documents/helper/shellx/.superpowers/sdd/2026-10-15-v2-3-tools-desktop/constraints.md
- Suite totals: the plan's numbers + 55 (earlier tasks' ruled tests) + this task's 3 ruled tests; Task 14's expected total is 3845 passed, 9 skipped (plan 3787 + 55 + 3).
- Controller rulings on the implementer's concerns (pre-review follow-up, verbatim in substance): (1) the tool row's height covers both text lines at every text scale and stays 36 px at 1× (one expression shared by heightFor and build), one test; (2) the sidebar list's own focus is a Tab stop only when it has tab rows or headers to walk (UI §3.6 "an empty list is no tab stop"), one test; (3) the one-workspace `_endLoose()` calls are removed (a single workspace cannot show loose while it has a tab); the go() row-branch call and its test stay.
