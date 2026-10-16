# Task 17 constraints (verbatim excerpts) — `@` files from the phone: ai.files, ai.prompt {files}

## Spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md` (binding; Vietnamese) — success criterion 4 (line 34); B13 (line 87):

4. **`@` tệp.** Gõ `@sr` → tối đa 8 gợi ý tệp của dự án trong ≤ 1 s; chọn thì thành nhắc tệp như trên máy tính.

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B13 | Nhắc tệp | `ai.files {sid, rid, q}` → `ai.result {body: {"files": [đường dẫn tương đối]}}` (≤ 8, dùng chỉ mục dự án và bộ so khớp của ô nhập desktop). `ai.prompt` thêm `files: [đường dẫn]`: hub chỉ nhận đường dẫn **nằm trong thư mục của phiên**, có thật, rồi gửi `ResourceLinkBlock` như desktop. Ô nhập điện thoại: gõ `@` hiện gợi ý. | — |

## Spec §4.1 rows ai.files, ai.prompt and the rule under the table (lines 108–109, 113, 121, 124); §6 (lines 182, 184); §8 (lines 207, 213):

| `t` | Chiều | Trường | Trả lời |
|---|---|---|---|
| `ai.files` | ĐT → DT | `sid`, `rid`, `q` | `ai.result {body}` (B13) |
| `ai.prompt` | ĐT → DT | thêm `blobs?`, `files?` | — |

Mọi loại mới có mặt trong `aiUnavailableReply` (không có cửa sổ thì trả `unavailable` ngay, điện thoại không phải chờ 10 s), `_ridOf` (từ chối `busy` cần `rid`) và `_towardsPhone`.

- Đường dẫn từ điện thoại (B13, B19) chỉ là đường dẫn desktop đã đưa và phải nằm trong thư mục phiên; desktop kiểm lại lúc làm.
- Không log nội dung; `toString` của mọi tin mới trả `Tên(…)`, có test.

- **Mỗi tin mới:** round-trip; sai trường → `null`; lớn nhất vừa một lô; `aiUnavailableReply`; ngân sách `busy`.
- **B13:** đường dẫn ngoài thư mục phiên bị từ chối.

## Plan rulings R15, R18 (plan lines 65, 68):

- **R15 — a V2-2b request the computer cannot take fails at once on the phone** (`AiRequestException('unsupported')`, nothing sent). *Cost if wrong:* none.
- **R18 — a path from a phone must be one the window offered** (B13, B19): relative, no `..`, ≤ 1 KiB, and checked again by the window (inside the session folder, there). *Cost if wrong:* a file the phone typed by hand is refused.

## Plan Global Constraints: No content in logs, Protocol, Old peers, Request budget (lines 82–85):

- **No content in logs (D12, B25):** no prompt, agent text, path, file name, diff, image, URL, header or body in any log; new log lines print only `error.runtimeType`. `toString()` of every new `ai.*` message is `'<Type>(…)'`; of every new body/view/record `'…'` (`with Redacted`) or `'<Name>(…)'`; each pinned by a test. Push data carries only an integer id, two option ids and a tag beyond V2-2a's (B25).
- **Protocol (exact values):** `kAiProtocol = 2`; `kAiMaxBodyBytes = 48 * 1024` (unchanged); `kAiMaxBlobPartBytes = kAiMaxBodyBytes`; `kAiMaxPromptBytes = 32 * 1024`; `kAiMaxPromptFiles = 20`; `kAiMaxPathBytes = 1024`; slices ≤ 36 KiB escaped (`kAiSliceBytes`), full item ≤ 2 MiB (`kAiFullItemBytes`), cached 60 s, ≤ 4 per phone; history ≤ 50 sessions per page, titles ≤ 120 bytes; config ≤ 40 choices per option, names ≤ 60 characters; changes ≤ 200 files; `ai.files` ≤ 8 suggestions; images ≤ 5 × 10 MiB, ≤ 20 MiB per phone, kept ≤ 2 minutes unused, ≤ 4 parts in flight; new result codes `no_images`, `confirm`, `busy_turn`, `not_ready`, `undo_off`, `too_big` (+ `unsupported` made by the phone itself). Every new message fits one sealed batch with its envelope (pinned per kind).
- **Old peers:** a malformed `ai.*` message is skipped and an unknown kind ignored, never dropping the channel; every V2-2b feature is gated by router `ai ≥ 2` AND listing `f` (R3); an older desktop or service never receives a V2-2b request; an older phone ignores `body`, `f`, `src`, `img` and the new header keys.
- **Request budget** unchanged (60 at once, then 30/s per phone; acks and detaches free); every new request kind, each `ai.blob` part included, costs one token and gets exactly one `ai.result`.

## Cross-task rules from earlier reviews (SDD ledger)

- Every V2-2b `MachineAi` request method must go through `MachineAi._feature` (R3/R15: router `ai ≥ 2` AND listing `f`; else `AiRequestException('unsupported')` at once, nothing sent).
- Every hub request about a session goes through Task 10's `_ask` (one `ai.result` per request, to the phone that asked only; a body over one message is never sent: `too_big`); `_prompt` answers once, to the asking phone only.
- V2-1 D16 (the desktop composer's `@`): a mention goes to the agent as a `resource_link` (`uri` the file URL, `name` the base name, `title` the path); the composer's project index and matcher (`AiProjectFiles.index`, `aiMatchFiles`) are what the phone's `@` uses.
