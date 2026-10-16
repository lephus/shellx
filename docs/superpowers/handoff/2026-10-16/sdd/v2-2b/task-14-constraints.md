# Task 14 constraints (verbatim excerpts) — session history, resume, folder for a tab without one

## Spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md` (binding; Vietnamese) — B17, B18 (lines 73–74, 91–92):

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B17 | Lịch sử phiên | `ai.history {sid, rid, cursor?}` → `{"sessions": [{"acp", "title", "at"}], "next"?, "current"?}` (≤ 50 mỗi trang, tiêu đề cắt ≤ 120 ký tự); agent của phiên chưa sẵn sàng → `not_ready` (điện thoại thử lại khi phiên chạy); agent không hỗ trợ `session/list` → nút không hiện (cờ trong header). Mở một mục: `ai.open` thêm `resume: <acp>` và khoá thư mục của phiên đó → desktop mở tab AI mới tiếp phiên cũ (`select: false`), phát lại như D15. | Hai tab cùng một phiên agent nếu người dùng mở hai lần (desktop cũng vậy). |
| B18 | Chọn thư mục | `ai.folder {sid, rid, folder}` (khoá từ listing, D9) cho tab `no_folder`: desktop làm như nút "Dùng thư mục này" của tab (quên runtime cũ, đặt `cwd`), rồi agent chạy (D15). Điện thoại: thay câu "Chọn thư mục trên máy tính" bằng danh sách thư mục và nút "Dùng thư mục này". | — |

## Spec §4.1 rows ai.history, ai.folder, ai.open and the rule under the table (lines 108–109, 115–116, 122, 124); §8 (lines 208, 215); §9 Review Focus 3 (line 228):

| `t` | Chiều | Trường | Trả lời |
|---|---|---|---|
| `ai.history` | ĐT → DT | `sid`, `rid`, `cursor?` | `ai.result {body}` (B17) |
| `ai.folder` | ĐT → DT | `sid`, `rid`, `folder` | `ai.result` (B18) |
| `ai.open` | ĐT → DT | thêm `resume?` | — |

Mọi loại mới có mặt trong `aiUnavailableReply` (không có cửa sổ thì trả `unavailable` ngay, điện thoại không phải chờ 10 s), `_ridOf` (từ chối `busy` cần `rid`) và `_towardsPhone`.

- **B7:** chọn đúng `allow_once` không bỏ qua quyền và `reject_once`; thiếu thì không nút; daemon cũ bỏ khoá mới.
- **B17/B18:** trang lịch sử, `not_ready`, `resume` mở tab không chọn; khoá thư mục lạ bị từ chối.
3. **Một tin quá cỡ làm rơi cả kênh** (ảnh, `ai.item`, `ai.changes` với rất nhiều tệp, tiêu đề lịch sử dài). Test cỡ lớn nhất mỗi loại.

## V2-2 spec `docs/superpowers/specs/2026-10-14-v2-2-phone-ai-design.md` D9, D14, D15 (lines 96, 101, 102) — what B17/B18 build on:

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| D9 | Phiên mới từ điện thoại | Chỉ với agent máy tính báo sẵn sàng (chưa biết thì coi là sẵn sàng, như V2-1b) và một **thư mục do máy tính đưa ra:** gốc dự án của các workspace cục bộ, cộng thư mục của các tab AI đang mở. Điện thoại gửi khoá (`ws:<id>` hoặc `path:<thư mục>`), không bao giờ gửi đường dẫn tự gõ. Tab AI mới vào đúng workspace, **không được chọn** trên desktop, và agent chạy ngay. Cấu hình nhớ theo agent được dùng như desktop, không bao giờ áp lại "Bỏ qua mọi quyền" (V2-1a R6). | Dự án chưa thuộc workspace nào phải đặt gốc trên máy tính trước. |
| D14 | Một phiên không chạy được | Tab AI chưa có thư mục, hoặc agent đã tắt/xoá trong Cài đặt: danh sách ghi "Chọn thư mục trên máy tính" / "Agent đang tắt trên máy tính"; mở ra thì thấy đúng câu đó, không có ô nhập. | — |
| D15 | Tab khôi phục chưa chạy | Điện thoại mở một tab AI vừa khôi phục mà agent chưa chạy thì agent chạy và `session/load` phát lại lịch sử, như khi người dùng nhìn tab đó trên desktop (V2-1b B11). | Một agent chạy khi người dùng chỉ nhìn trên điện thoại. |

## Plan rulings R3, R4, R15, R18 (plan lines 53, 54, 65, 68):

- **R3 — capability = router `ai ≥ 2` AND listing `f`** (B1): learned from `session.list.result` and the window's listing; the AI session page asks `session.list` once when the protocol is unknown (opened from a push) and holds the listing while open. *Cost if wrong:* one extra round trip when a page opens cold.
- **R4 — one answer for everything:** a V2-2b request the hub does not take (yet), or an `AiRaw` with an integer `rid`, gets `refused` from a window and `unavailable` where no window serves AI. *Cost if wrong:* none (a phone never sends what `f` does not name).
- **R15 — a V2-2b request the computer cannot take fails at once on the phone** (`AiRequestException('unsupported')`, nothing sent). *Cost if wrong:* none.
- **R18 — a path from a phone must be one the window offered** (B13, B19): relative, no `..`, ≤ 1 KiB, and checked again by the window (inside the session folder, there). *Cost if wrong:* a file the phone typed by hand is refused.

## Plan Global Constraints: No content in logs, Protocol, Old peers, Request budget (lines 82–85):

- **No content in logs (D12, B25):** no prompt, agent text, path, file name, diff, image, URL, header or body in any log; new log lines print only `error.runtimeType`. `toString()` of every new `ai.*` message is `'<Type>(…)'`; of every new body/view/record `'…'` (`with Redacted`) or `'<Name>(…)'`; each pinned by a test. Push data carries only an integer id, two option ids and a tag beyond V2-2a's (B25).
- **Protocol (exact values):** `kAiProtocol = 2`; `kAiMaxBodyBytes = 48 * 1024` (unchanged); `kAiMaxBlobPartBytes = kAiMaxBodyBytes`; `kAiMaxPromptBytes = 32 * 1024`; `kAiMaxPromptFiles = 20`; `kAiMaxPathBytes = 1024`; slices ≤ 36 KiB escaped (`kAiSliceBytes`), full item ≤ 2 MiB (`kAiFullItemBytes`), cached 60 s, ≤ 4 per phone; history ≤ 50 sessions per page, titles ≤ 120 bytes; config ≤ 40 choices per option, names ≤ 60 characters; changes ≤ 200 files; `ai.files` ≤ 8 suggestions; images ≤ 5 × 10 MiB, ≤ 20 MiB per phone, kept ≤ 2 minutes unused, ≤ 4 parts in flight; new result codes `no_images`, `confirm`, `busy_turn`, `not_ready`, `undo_off`, `too_big` (+ `unsupported` made by the phone itself). Every new message fits one sealed batch with its envelope (pinned per kind).
- **Old peers:** a malformed `ai.*` message is skipped and an unknown kind ignored, never dropping the channel; every V2-2b feature is gated by router `ai ≥ 2` AND listing `f` (R3); an older desktop or service never receives a V2-2b request; an older phone ignores `body`, `f`, `src`, `img` and the new header keys.
- **Request budget** unchanged (60 at once, then 30/s per phone; acks and detaches free); every new request kind, each `ai.blob` part included, costs one token and gets exactly one `ai.result`.

## Cross-task rules from earlier reviews (SDD ledger)

- Every V2-2b `MachineAi` request method must go through `MachineAi._feature` (R3/R15: router `ai ≥ 2` AND listing `f`; else `AiRequestException('unsupported')` at once, nothing sent).
- Every hub request about a session's control goes through Task 10's `_ask` (one `ai.result` per request, to the phone that asked only; a body over one message is never sent: `too_big`).

## Controller rulings for this task (SDD ledger; they override the brief's text)

- Ruling (F26): Task 14's hub test file gets one extra test pinning `_ask`'s refusal-with-body branch (Task 10 deferred gap): `FakeAiControl.failWith = AiRefused(<code>, body: <bytes>)` makes `listSessions` throw it, and `ai.history` is answered `ok: false` with that code and exactly those body bytes — why: the top-level dispatch asks to pin the deferred `_ask` gaps in a task's own tests where cheap; this is the first `_ask` request whose fake control throws from the request itself — cost if wrong: none (test only). The `too_big` branch stays deferred: no V2-2b body encoder can exceed one body (each bounds itself), so only a test-only path would reach it.
- Ruling (F27): `_Reply.refuse`'s code becomes non-nullable — `const _Reply.refuse(String this.code, [this.body]);` in `ai_phone_hub_requests.dart` (Task 14's Files block) — why: the plan's own Interfaces (lines 9178, 13608) state `_Reply.refuse(String code, [Uint8List? body])`; Task 10's code made it nullable, so `_Reply.refuse(null)` would compile and be sent as `ok: true` (Task 10 deferred minor); every call in the plan passes a non-null String (checked: lines 10333–17690) — cost if wrong: none (compile-time only).
- Ruling (F28): history titles are cut to 120 characters (Unicode code points, the "…" included, never splitting a surrogate pair), not 120 UTF-8 bytes — the constant is `kAiHistoryTitleChars = 120` (replacing the plan's `kAiHistoryTitleBytes`), the cut a private helper in `history_view.dart` shaped like `config_view.dart`'s `_name`, and Task 14's two title assertions check `title.runes.length <= kAiHistoryTitleChars` — why: spec B17 says "tiêu đề cắt ≤ 120 ký tự" (characters), the plan's Global Constraints say bytes with no ruling (the same plan cuts config names by characters, per the spec's "≤ 60 ký tự"); 120 bytes cuts a Vietnamese title at ~50–85 characters; the body stays bounded (50 × 120 × ≤ 4 B of titles; the encoder's over-`kAiRecordBytes` fallback is unchanged); no later task names the constant — cost if wrong: one constant to rename back.
