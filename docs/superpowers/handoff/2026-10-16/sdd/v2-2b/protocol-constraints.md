# Protocol constraints (verbatim excerpts) — for reviews of Tasks 2–4

## Spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md` (binding; Vietnamese). Decisions B1, B2, B4 (lines 75, 76, 78):

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B1 | Khả năng (hai lớp) | Điện thoại chỉ dùng một tính năng V2-2b khi **cả hai**: (a) router báo `ai: 2` trong `session.list.result` (`kAiProtocol = 2` ở tiến trình giữ relay: daemon khi bật dịch vụ nền), chứng minh đường chuyển tiếp hiểu V2-2b; (b) listing của cửa sổ có `"f": [...]` liệt kê tính năng hub làm được (`config`, `blob`, `files`, `changes`, `revert`, `item`, `history`, `folder`, `push_answer`, `acp_head`). Thiếu một trong hai thì nút tương ứng không hiện. | — |
| B2 | Chuyển tiếp nguyên văn | Từ V2-2b, daemon chuyển tiếp `ai.*` **nguyên văn**: mỗi `AiMessage` giữ map gốc đã giải mã và dùng lại khi mã hoá; loại `ai.*` lạ thành `AiRaw` (giữ map, chiều theo nguồn: từ điện thoại thì vào cửa sổ, từ `ai.out` của cửa sổ thì ra điện thoại). Kiểm cỡ như cũ. Nhờ vậy lần thêm sau chỉ cần sửa cửa sổ. | — |
| B4 | Thân trong `ai.result` | `ai.result` có thêm `body` (byte JSON) tuỳ chọn. Dữ liệu lớn hơn một thân thì điện thoại **kéo từng phần** (`part`): mỗi lần một yêu cầu, nằm trong ngân sách yêu cầu sẵn có (60 dồn, 30/giây), không cần cửa sổ gửi mới. Mã mới: `no_images`, `confirm`, `busy_turn`, `not_ready`, `undo_off`, `too_big`. Điện thoại cũ đọc mã lạ thành câu chung. | — |

## Spec §4.1–§4.2 (lines 106–131):

### 4.1 Tin mới và trường mới

| `t` | Chiều | Trường | Trả lời |
|---|---|---|---|
| `ai.config.get` | ĐT → DT | `sid`, `rid` | `ai.result {body}` (B11) |
| `ai.config` | ĐT → DT | `sid`, `rid`, `body` | `ai.result` |
| `ai.blob` | ĐT → DT | `rid`, `blob`, `part`, `parts`, `mime?`, `data` | `ai.result` mỗi phần (B12) |
| `ai.files` | ĐT → DT | `sid`, `rid`, `q` | `ai.result {body}` (B13) |
| `ai.item` | ĐT → DT | `sid`, `rid`, `i`, `part` | `ai.result {body}` (B16) |
| `ai.history` | ĐT → DT | `sid`, `rid`, `cursor?` | `ai.result {body}` (B17) |
| `ai.folder` | ĐT → DT | `sid`, `rid`, `folder` | `ai.result` (B18) |
| `ai.changes` | ĐT → DT | `sid`, `rid`, `turn?` | `ai.result {body}` (B19) |
| `ai.diff` | ĐT → DT | `sid`, `rid`, `turn?`, `path` | `ai.result {body}` |
| `ai.revert` | ĐT → DT | `sid`, `rid`, `turn?`, `keep?` | `ai.result` (`confirm` kèm `body`) |
| `ai.result` | DT → ĐT | thêm `body?` | — |
| `ai.prompt` | ĐT → DT | thêm `blobs?`, `files?` | — |
| `ai.open` | ĐT → DT | thêm `resume?` | — |

Mọi loại mới có mặt trong `aiUnavailableReply` (không có cửa sổ thì trả `unavailable` ngay, điện thoại không phải chờ 10 s), `_ridOf` (từ chối `busy` cần `rid`) và `_towardsPhone`.

### 4.2 Thân và header

- Listing: thêm `"f": [...]` (B1).
- Header: thêm `model {id, name}`, `acp`, `hist` (agent có `session/list`), `undo` (`on`/`off`).
- Mục gương tin người dùng: thêm `img` (số ảnh), `src` (`phone`).
- Mux `ai.push`: thêm `perm`, `allow`, `reject`, `tag` (daemon cũ bỏ qua → thông báo thường).

## Spec §8 tests (lines 206–207) and §9 Review Focus 2–3 (lines 227–228):

- **B1/B2:** điện thoại V2-2b với router `ai: 1` không gửi tin mới; daemon V2-2b chuyển nguyên văn một loại `ai.*` lạ và khoá lạ; bộ giải mã đóng băng V2-2a đọc lô mới không lỗi.
- **Mỗi tin mới:** round-trip; sai trường → `null`; lớn nhất vừa một lô; `aiUnavailableReply`; ngân sách `busy`.
2. **Dịch vụ nền cũ nuốt tin mới** khiến điện thoại chờ mãi: test với daemon V2-2a giả.
3. **Một tin quá cỡ làm rơi cả kênh** (ảnh, `ai.item`, `ai.changes` với rất nhiều tệp, tiêu đề lịch sử dài). Test cỡ lớn nhất mỗi loại.

## Plan rulings R2, R3, R4, R15 (plan lines 52–54, 65):

- **R2 — verbatim forwarding by wire maps** (B2): each `ai.*` message read from the wire keeps its map in an `Expando` (`AiMessage.wire`); `encodeBatch` and the mux write `wire`; an unknown `ai.*` kind is read as `AiRaw` (forwarded the way it came); a malformed known kind is still skipped. Non-string keys are dropped. *Cost if wrong:* one map kept per decoded message while it lives.
- **R3 — capability = router `ai ≥ 2` AND listing `f`** (B1): learned from `session.list.result` and the window's listing; the AI session page asks `session.list` once when the protocol is unknown (opened from a push) and holds the listing while open. *Cost if wrong:* one extra round trip when a page opens cold.
- **R4 — one answer for everything:** a V2-2b request the hub does not take (yet), or an `AiRaw` with an integer `rid`, gets `refused` from a window and `unavailable` where no window serves AI. *Cost if wrong:* none (a phone never sends what `f` does not name).
- **R15 — a V2-2b request the computer cannot take fails at once on the phone** (`AiRequestException('unsupported')`, nothing sent). *Cost if wrong:* none.

## Plan Review Focus 2–3 (plan lines 98–99):

2. **An older background service swallows new messages and the phone waits forever.** [Task 3: "a window's message of a kind this service does not know reaches the phone as it was sent", "a known kind keeps the keys this service does not know, both ways", "without a window, every V2-2b request and a newer phone's request with a rid are answered unavailable at once; one without a rid gets nothing". Task 4: "the router says ai 1 (a V2-2a desktop, or a V2-2b window behind a V2-2a background service): no V2-2b feature, even one the listing names".]
3. **One oversize message drops the whole channel** — images, `ai.item`, `ai.changes` with many files, long history titles. [Task 2: "the largest of each V2-2b message fits one sealed batch with its envelope". Task 12: "Review Focus 3: quotes, backslashes and control characters, the worst escaping, still fit". Task 14: "at most 50 sessions, titles cut; what could not be sent back is left out (Review Focus 3)". Task 16: "a part at the limit is taken, and one message holds it (Review Focus 3)". Task 24: "ten thousand changed files with long paths fit one body; the rest is counted (Review Focus 3)", "a confirm lists what fits of ten thousand touched files", "a file of nearly 1 MiB fits one message; one over is too_big (Review Focus 3)". Task 10's config view is cut to one body by `encodeConfigView`.]
