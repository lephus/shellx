# Task 12 constraints (verbatim excerpts) — a big item in full: ai.item in parts

## Spec (binding; Vietnamese) — table header, B4, B16 (lines 73–74, 78, 90):

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B4 | Thân trong `ai.result` | `ai.result` có thêm `body` (byte JSON) tuỳ chọn. Dữ liệu lớn hơn một thân thì điện thoại **kéo từng phần** (`part`): mỗi lần một yêu cầu, nằm trong ngân sách yêu cầu sẵn có (60 dồn, 30/giây), không cần cửa sổ gửi mới. Mã mới: `no_images`, `confirm`, `busy_turn`, `not_ready`, `undo_off`, `too_big`. Điện thoại cũ đọc mã lạ thành câu chung. | — |
| B16 | Xem đủ | `ai.item {sid, rid, i, part}` → `ai.result {body: {"i", "r", "part", "parts", "text"}}`. Desktop dựng **bản đầy đủ** của mục `i` một lần (đầu ra lệnh, dòng cắt ở 2 000 ký tự như desktop; mọi diff, mỗi tệp ≤ 1 MiB; input JSON; form câu hỏi; chữ), giữ 60 s theo (điện thoại, sid, i, rev), trả từng lát ≤ 36 KiB. Tổng ≤ 2 MiB, lớn hơn thì `too_big` và vẫn "Xem trên máy tính". `rev` đổi giữa chừng (lệnh còn chạy) thì tải lại từ đầu. Điện thoại: "Xem đủ" → trang xem toàn màn hình (dòng ảo hoá, chữ đơn cách, dùng lại khung diff), "Đang tải 3/12". Câu hỏi `big` xem đủ rồi trả lời được trên điện thoại (hub đã kiểm bằng `form.accepts`). | — |

## Spec §4.1 row ai.item and the rule under the table (lines 108–109, 114, 124); §7 row ai.item (line 198); §8 B16 (line 214); §9 Review Focus 3 (line 228):

| `t` | Chiều | Trường | Trả lời |
|---|---|---|---|
| `ai.item` | ĐT → DT | `sid`, `rid`, `i`, `part` | `ai.result {body}` (B16) |

Mọi loại mới có mặt trong `aiUnavailableReply` (không có cửa sổ thì trả `unavailable` ngay, điện thoại không phải chờ 10 s), `_ridOf` (từ chối `busy` cần `rid`) và `_towardsPhone`.

| `ai.item` khi lệnh còn chạy | `rev` đổi → tải lại từ đầu |

- **B16:** chia lát, `rev` đổi, quá 2 MiB.
3. **Một tin quá cỡ làm rơi cả kênh** (ảnh, `ai.item`, `ai.changes` với rất nhiều tệp, tiêu đề lịch sử dài). Test cỡ lớn nhất mỗi loại.

## Plan rulings R14, R15, R22 (plan lines 64, 65, 72) and Review Focus 3 (line 99):

- **R14 — full items are sliced by escaped size** (B16): the full view is JSON text cut into slices whose JSON-escaped size is ≤ 36 KiB (never splitting a surrogate pair), so a body stays ≤ 48 KiB whatever the text. *Cost if wrong:* more parts for text full of quotes.
- **R15 — a V2-2b request the computer cannot take fails at once on the phone** (`AiRequestException('unsupported')`, nothing sent). *Cost if wrong:* none.
- **R22 — "Xem đủ" on every open tool card with a body** (B16): the mirror cuts a call's input without saying so, so the phone cannot tell every cut card. *Cost if wrong:* a button that sometimes loads what is already shown.
3. **One oversize message drops the whole channel** — images, `ai.item`, `ai.changes` with many files, long history titles. [Task 2: "the largest of each V2-2b message fits one sealed batch with its envelope". Task 12: "Review Focus 3: quotes, backslashes and control characters, the worst escaping, still fit". Task 14: "at most 50 sessions, titles cut; what could not be sent back is left out (Review Focus 3)". Task 16: "a part at the limit is taken, and one message holds it (Review Focus 3)". Task 24: "ten thousand changed files with long paths fit one body; the rest is counted (Review Focus 3)", "a confirm lists what fits of ten thousand touched files", "a file of nearly 1 MiB fits one message; one over is too_big (Review Focus 3)". Task 10's config view is cut to one body by `encodeConfigView`.]

## Plan Global Constraints: No content in logs, Protocol, Old peers, Request budget (lines 82–85):

- **No content in logs (D12, B25):** no prompt, agent text, path, file name, diff, image, URL, header or body in any log; new log lines print only `error.runtimeType`. `toString()` of every new `ai.*` message is `'<Type>(…)'`; of every new body/view/record `'…'` (`with Redacted`) or `'<Name>(…)'`; each pinned by a test. Push data carries only an integer id, two option ids and a tag beyond V2-2a's (B25).
- **Protocol (exact values):** `kAiProtocol = 2`; `kAiMaxBodyBytes = 48 * 1024` (unchanged); `kAiMaxBlobPartBytes = kAiMaxBodyBytes`; `kAiMaxPromptBytes = 32 * 1024`; `kAiMaxPromptFiles = 20`; `kAiMaxPathBytes = 1024`; slices ≤ 36 KiB escaped (`kAiSliceBytes`), full item ≤ 2 MiB (`kAiFullItemBytes`), cached 60 s, ≤ 4 per phone; history ≤ 50 sessions per page, titles ≤ 120 bytes; config ≤ 40 choices per option, names ≤ 60 characters; changes ≤ 200 files; `ai.files` ≤ 8 suggestions; images ≤ 5 × 10 MiB, ≤ 20 MiB per phone, kept ≤ 2 minutes unused, ≤ 4 parts in flight; new result codes `no_images`, `confirm`, `busy_turn`, `not_ready`, `undo_off`, `too_big` (+ `unsupported` made by the phone itself). Every new message fits one sealed batch with its envelope (pinned per kind).
- **Old peers:** a malformed `ai.*` message is skipped and an unknown kind ignored, never dropping the channel; every V2-2b feature is gated by router `ai ≥ 2` AND listing `f` (R3); an older desktop or service never receives a V2-2b request; an older phone ignores `body`, `f`, `src`, `img` and the new header keys.
- **Request budget** unchanged (60 at once, then 30/s per phone; acks and detaches free); every new request kind, each `ai.blob` part included, costs one token and gets exactly one `ai.result`.

## Cross-task rules from earlier reviews (SDD ledger)

- Every V2-2b `MachineAi` request method must go through `MachineAi._feature` (R3/R15: router `ai ≥ 2` AND listing `f`; else `AiRequestException('unsupported')` at once, nothing sent).
- Every hub request goes through Task 10's `_ask` (one `ai.result` per request, to the phone that asked only; a body over one message is never sent: `too_big`).
