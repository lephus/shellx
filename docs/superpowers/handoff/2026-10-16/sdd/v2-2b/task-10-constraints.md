# Task 10 constraints (verbatim excerpts) — mode and model from the phone; the hub's request helper

## Spec (binding; Vietnamese) — table header, B4, B7, B11 (lines 73–74, 78, 81, 85):

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B4 | Thân trong `ai.result` | `ai.result` có thêm `body` (byte JSON) tuỳ chọn. Dữ liệu lớn hơn một thân thì điện thoại **kéo từng phần** (`part`): mỗi lần một yêu cầu, nằm trong ngân sách yêu cầu sẵn có (60 dồn, 30/giây), không cần cửa sổ gửi mới. Mã mới: `no_images`, `confirm`, `busy_turn`, `not_ready`, `undo_off`, `too_big`. Điện thoại cũ đọc mã lạ thành câu chung. | — |
| B7 | Desktop xin đẩy kèm nút | `AiPush` có thêm `permission` (id) và hai lựa chọn: **allow** = lựa chọn `allow_once` đầu tiên **không** bật chế độ bỏ qua xin quyền; **reject** = lựa chọn `reject_once` đầu tiên. Không bao giờ `allow_always`/`reject_always` (đổi hành vi về sau, trái tinh thần D13). Thiếu một trong hai thì thông báo thường như cũ. Câu hỏi không có nút. `aiNotice` thêm `data` `perm`, `allow`, `reject` và xin `category: ai_perm`, `tag: ai-<epoch>-<pane>-<perm>`. Hàm nhận diện chế độ bỏ qua xin quyền chuyển sang `package:shellx_ai` để hub dùng. | — |
| B11 | Chế độ, model | `ai.config.get {sid, rid}` → `ai.result {body}`: các tuỳ chọn thuộc nhóm `mode`, `model`, `thought_level`, `model_config` cùng lựa chọn hiện tại; **bỏ mọi lựa chọn bật chế độ bỏ qua xin quyền** (hàm B7) và với chế độ chỉ đưa những id đã biết là an toàn (`default`, `plan`, `acceptEdits`, `auto`, `auto_edit` và id agent không bị hàm B7 gắn cờ); tên cắt ≤ 60 ký tự; tối đa 40 lựa chọn mỗi tuỳ chọn (cờ `more`). `ai.config {sid, rid, body: {"id", "value"}}` hoặc `{"mode"}`: desktop kiểm lại với tuỳ chọn **lúc đó** (có, đúng nhóm, giá trị nằm trong danh sách, không bỏ qua xin quyền → `on_computer`) rồi `setConfig` và `rememberConfig` như chip desktop. Agent từ chối → `refused`. Header thêm `model {id, name}`. | Muốn "Bỏ qua mọi quyền" phải làm trên máy tính. |

## Spec §4.1 rows ai.config.get / ai.config / ai.result and the rule under the table (lines 110–111, 120, 124):

| `t` | Chiều | Trường | Trả lời |
|---|---|---|---|
| `ai.config.get` | ĐT → DT | `sid`, `rid` | `ai.result {body}` (B11) |
| `ai.config` | ĐT → DT | `sid`, `rid`, `body` | `ai.result` |
| `ai.result` | DT → ĐT | thêm `body?` | — |

Mọi loại mới có mặt trong `aiUnavailableReply` (không có cửa sổ thì trả `unavailable` ngay, điện thoại không phải chờ 10 s), `_ridOf` (từ chối `busy` cần `rid`) và `_towardsPhone`.

## Spec §6 (lines 178–184), §8 B11 (line 211), §9 Review Focus 3 and 5 (lines 228, 230):

## 6. Riêng tư, an ninh và log

- Không có đường nào trả lời mà không có một lần chạm của người dùng (D13 giữ nguyên). Nút trên thông báo chỉ mang hai lựa chọn "một lần"; câu trả lời chỉ gửi sau khoá Face ID của app; không gửi lại sau khi mất kênh.
- Chế độ bỏ qua xin quyền không bao giờ được liệt kê hay đặt từ điện thoại (B11).
- Đường dẫn từ điện thoại (B13, B19) chỉ là đường dẫn desktop đã đưa và phải nằm trong thư mục phiên; desktop kiểm lại lúc làm.
- Ảnh chỉ nằm trong bộ nhớ desktop tới khi gửi cho agent (B12).
- Không log nội dung; `toString` của mọi tin mới trả `Tên(…)`, có test.

- **B11:** lọc chế độ bỏ qua xin quyền (cả id lạ có chữ "bypass", "yolo"…); kiểm lại lúc đặt; `rememberConfig` không nhớ bỏ qua quyền.
3. **Một tin quá cỡ làm rơi cả kênh** (ảnh, `ai.item`, `ai.changes` với rất nhiều tệp, tiêu đề lịch sử dài). Test cỡ lớn nhất mỗi loại.
5. **Chế độ bỏ qua xin quyền lọt qua** bằng một id lạ hay qua `ai.config` gửi thẳng. Test cả danh sách và lúc đặt.

## Plan rulings R4, R15, R16 (plan lines 54, 65, 66) and Review Focus 3, 5 (lines 99, 101):

- **R4 — one answer for everything:** a V2-2b request the hub does not take (yet), or an `AiRaw` with an integer `rid`, gets `refused` from a window and `unavailable` where no window serves AI. *Cost if wrong:* none (a phone never sends what `f` does not name).
- **R15 — a V2-2b request the computer cannot take fails at once on the phone** (`AiRequestException('unsupported')`, nothing sent). *Cost if wrong:* none.
- **R16 — what mode/model choices a phone sees** (B11): every choice the no-approval predicate does not flag (Claude's `default`, `plan`, `acceptEdits`, `auto`, and other agents' unflagged ones); a boolean option named like a no-approval mode is not offered; the window checks again when setting (`on_computer`). *Cost if wrong:* "Bypass permissions" stays a computer-only choice.
3. **One oversize message drops the whole channel** — images, `ai.item`, `ai.changes` with many files, long history titles. [Task 2: "the largest of each V2-2b message fits one sealed batch with its envelope". Task 12: "Review Focus 3: quotes, backslashes and control characters, the worst escaping, still fit". Task 14: "at most 50 sessions, titles cut; what could not be sent back is left out (Review Focus 3)". Task 16: "a part at the limit is taken, and one message holds it (Review Focus 3)". Task 24: "ten thousand changed files with long paths fit one body; the rest is counted (Review Focus 3)", "a confirm lists what fits of ten thousand touched files", "a file of nearly 1 MiB fits one message; one over is too_big (Review Focus 3)". Task 10's config view is cut to one body by `encodeConfigView`.]
5. **A no-approval mode slips through,** by an id nobody listed or by an `ai.config` sent directly. [Task 10: "R16: an id that only says it (yolo, clearAndBypass, danger-full-access) is never offered, nor a switch named like one", the refusal tests of `aiConfigRefusal` (`on_computer` whatever was offered), "the phone gets the choices without "Bypass permissions"; its choice reaches the agent and is remembered as the chip remembers it". Task 8: "the allow button is never an answer that turns on a mode acting without asking (Review Focus 5)".]

## Plan Global Constraints: Never auto-allow, No content in logs, Protocol, Old peers, Request budget (lines 81–85):

- **Never auto-allow (D13, spec §6):** no path in which a phone answers without a user tap; a notification button is that tap, and its answer goes only after the app's own lock (R7); push buttons offer only the first `allow_once` that turns on no no-approval mode and the first `reject_once` — never `allow_always`/`reject_always`; no answer is ever resent after a lost channel; a no-approval mode is never listed for, nor set from, a phone (R16); a remembered no-approval mode is never re-applied.
- **No content in logs (D12, B25):** no prompt, agent text, path, file name, diff, image, URL, header or body in any log; new log lines print only `error.runtimeType`. `toString()` of every new `ai.*` message is `'<Type>(…)'`; of every new body/view/record `'…'` (`with Redacted`) or `'<Name>(…)'`; each pinned by a test. Push data carries only an integer id, two option ids and a tag beyond V2-2a's (B25).
- **Protocol (exact values):** `kAiProtocol = 2`; `kAiMaxBodyBytes = 48 * 1024` (unchanged); `kAiMaxBlobPartBytes = kAiMaxBodyBytes`; `kAiMaxPromptBytes = 32 * 1024`; `kAiMaxPromptFiles = 20`; `kAiMaxPathBytes = 1024`; slices ≤ 36 KiB escaped (`kAiSliceBytes`), full item ≤ 2 MiB (`kAiFullItemBytes`), cached 60 s, ≤ 4 per phone; history ≤ 50 sessions per page, titles ≤ 120 bytes; config ≤ 40 choices per option, names ≤ 60 characters; changes ≤ 200 files; `ai.files` ≤ 8 suggestions; images ≤ 5 × 10 MiB, ≤ 20 MiB per phone, kept ≤ 2 minutes unused, ≤ 4 parts in flight; new result codes `no_images`, `confirm`, `busy_turn`, `not_ready`, `undo_off`, `too_big` (+ `unsupported` made by the phone itself). Every new message fits one sealed batch with its envelope (pinned per kind).
- **Old peers:** a malformed `ai.*` message is skipped and an unknown kind ignored, never dropping the channel; every V2-2b feature is gated by router `ai ≥ 2` AND listing `f` (R3); an older desktop or service never receives a V2-2b request; an older phone ignores `body`, `f`, `src`, `img` and the new header keys.
- **Request budget** unchanged (60 at once, then 30/s per phone; acks and detaches free); every new request kind, each `ai.blob` part included, costs one token and gets exactly one `ai.result`.

## Cross-task rules from earlier reviews (SDD ledger)

- Task 4 hand-off: every V2-2b `MachineAi` request method (Tasks 10, 12, 14, 16, 17, 24) must go through `MachineAi._feature` (the old-peer gate R3/R15: router `ai ≥ 2` AND listing `f`; otherwise `AiRequestException('unsupported')` at once and nothing sent). Task 10 removes the `// ignore: unused_element` above `_feature` (Ruling F2) and its client test pins R15.
- `MachineAi.can` reads `MachineAi._listing` (kept across a lost channel), not the workspace's stale-guarded listing (Task 4/6 design).
