# Task 6 constraints (verbatim excerpts)

## Spec (binding): success criterion 11 (line 41)
11. **Nối lại.** ShellX trên máy tính khởi động lại: trang phiên trên điện thoại tự nối vào đúng phiên trong ≤ 5 s sau khi tab về, có dòng "Đã nối lại sau khi ShellX khởi động lại."

## Spec decisions B1, B22, B23 (lines 75, 96, 97)
| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B1 | Khả năng (hai lớp) | Điện thoại chỉ dùng một tính năng V2-2b khi **cả hai**: (a) router báo `ai: 2` trong `session.list.result` (`kAiProtocol = 2` ở tiến trình giữ relay: daemon khi bật dịch vụ nền), chứng minh đường chuyển tiếp hiểu V2-2b; (b) listing của cửa sổ có `"f": [...]` liệt kê tính năng hub làm được (`config`, `blob`, `files`, `changes`, `revert`, `item`, `history`, `folder`, `push_answer`, `acp_head`). Thiếu một trong hai thì nút tương ứng không hiện. | — |
| B22 | Nối lại sau khởi động lại | Header có thêm `acp`. Khi phiên nhận `gone`/`desktop_closed`, hoặc lần attach lại sau `unavailable` thất bại: giữ listing tối đa 30 s; listing `available: true` có **đúng một** phiên cùng `acp`, cùng agent và thư mục → attach sid mới, đổi khoá nháp, hiện "Đã nối lại sau khi ShellX khởi động lại."; không có hoặc có từ hai phiên → giữ trang đóng với "Mở danh sách phiên". | — |
| B23 | Thông báo của sid cũ | Chạm thông báo mang sid của lần chạy trước: nếu listing đang giữ có phiên cùng `acp` thì mở phiên đó; không thì mở trang máy như cũ. | — |

## Spec §4.2 header (line 129), §5 strings (lines 149-150, 171-172)
- Header: thêm `model {id, name}`, `acp`, `hist` (agent có `session/list`), `undo` (`on`/`off`).

| Khoá | EN | VI |
|---|---|---|
| `aiReattached` | Reconnected after ShellX restarted. | Đã nối lại sau khi ShellX khởi động lại. |
| `aiOpenList` | Open the session list | Mở danh sách phiên |

## Spec §7 edge (line 193), §8 tests (lines 218, 220), §9 Review Focus 1 (line 226)
| Chạm nút sau khi máy tính khởi động lại | sid cũ → B23; không khớp thì mở trang máy, không trả lời |
- **B22/B23:** một phiên khớp → nối lại; hai phiên → không.
- **App mobile (widget):** từng màn mới, chống chạm 400 ms ở hoàn tác, các trạng thái.
1. **Câu trả lời trúng nhầm yêu cầu:** runtime đổi trên cùng pane (B3), thông báo cũ chạm muộn, sid của lần chạy trước (B23). Test: mọi đường đều ra `stale` hoặc mở trang, không bao giờ trả lời.

## Plan rulings R3, R15, R20 (plan lines 53, 65, 70) and Review Focus 1 (plan line 97)
- **R3 — capability = router `ai ≥ 2` AND listing `f`** (B1): learned from `session.list.result` and the window's listing; the AI session page asks `session.list` once when the protocol is unknown (opened from a push) and holds the listing while open. *Cost if wrong:* one extra round trip when a page opens cold.
- **R15 — a V2-2b request the computer cannot take fails at once on the phone** (`AiRequestException('unsupported')`, nothing sent). *Cost if wrong:* none.
- **R20 — B23 remaps only sids this app run has seen** (B23): a push sid that a listing of this run named, and that the current listing no longer names, opens the one session with the same `acp`, agent and folder, else the machine page; a sid never seen opens its page as in V2-2a (the push carries no `acp`, so the phone cannot tell a sid of the previous run from a tab opened while it slept). *Cost if wrong:* such a page shows "closed" with B22's "Mở danh sách phiên".

1. **An answer lands on another request** — a pane's runtime replaced (B3), a notification tapped late, a sid from before ShellX restarted (B23). Every path ends `stale` or opens a page; nothing answers another request. [Task 1: "an answer to the old runtime's request is stale; the new request stays asked", "a queued prompt of the old runtime is not the new one's either". Task 6: "a session of the previous run opens as the one session of the same agent session now", "none, or two, of the same agent session now: the machine opens". Task 20: "stale says it was answered elsewhere and sends nothing else", "an old sid gets not_found, then the page: …", "bad data sends nothing: …", "a lost channel is never retried (…)", "a cancelled unlock sends nothing, also when the app is unlocked later".]
