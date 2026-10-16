# Task 16 constraints (verbatim excerpts) — images from the phone: ai.blob, ai.prompt {blobs}

## Spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md` (binding; Vietnamese) — success criterion 3 (line 33); B12 (line 86):

3. **Ảnh.** Chọn tối đa 5 ảnh (thư viện hoặc camera) → hàng ảnh nhỏ → Gửi. Agent trên máy tính nhận ảnh; máy tính hiện ảnh trong tin; điện thoại hiện "2 ảnh". 5 ảnh chụp từ iPhone gửi xong trong ≤ 10 s qua Wi-Fi.

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B12 | Ảnh | `ai.blob {rid, blob, part, parts, mime?, data}` (ĐT → DT; `data` ≤ 48 KiB; `mime` ở phần 0); mỗi phần một `ai.result`; điện thoại để ≤ 4 phần đang bay. Desktop giữ blob theo điện thoại trong bộ nhớ (≤ 5 × 10 MiB, ≤ 20 MiB mỗi điện thoại), bỏ sau 2 phút không dùng, khi điện thoại rời đi, hoặc khi đã gửi. `ai.prompt` thêm `blobs: [id]`: hub kiểm đủ phần, loại ảnh theo byte đầu (PNG/JPEG/GIF/WebP), agent nhận ảnh (`no_images` nếu không), rồi gửi kèm ảnh qua đường base64 ngoài isolate UI của desktop. Mục gương của tin người dùng có `img: n`. **Điện thoại:** `image_picker` 1.2.4, thư viện (tối đa 5) và camera, thu về ≤ 2048 px, JPEG chất lượng 85 (ảnh HEIC đổi sang JPEG). Mất kênh giữa chừng thì gửi lại **ảnh**, không bao giờ tự gửi lại tin. | Ảnh rất lớn bị thu nhỏ còn 2048 px. |

## Spec §4.1 rows ai.blob, ai.prompt and the rule under the table (lines 108–109, 112, 121, 124); §4.2 (line 130); §6 (lines 183–184); §7 (line 195); §8 (lines 207, 212); §9 Review Focus 3 (line 228):

| `t` | Chiều | Trường | Trả lời |
|---|---|---|---|
| `ai.blob` | ĐT → DT | `rid`, `blob`, `part`, `parts`, `mime?`, `data` | `ai.result` mỗi phần (B12) |
| `ai.prompt` | ĐT → DT | thêm `blobs?`, `files?` | — |

Mọi loại mới có mặt trong `aiUnavailableReply` (không có cửa sổ thì trả `unavailable` ngay, điện thoại không phải chờ 10 s), `_ridOf` (từ chối `busy` cần `rid`) và `_towardsPhone`.

- Mục gương tin người dùng: thêm `img` (số ảnh), `src` (`phone`).

- Ảnh chỉ nằm trong bộ nhớ desktop tới khi gửi cho agent (B12).
- Không log nội dung; `toString` của mọi tin mới trả `Tên(…)`, có test.

| Tình huống | Hành vi |
|---|---|
| Mất kênh khi đang tải ảnh | Tải lại ảnh khi có kênh; tin chưa gửi vẫn nằm trong ô nhập |

- **Mỗi tin mới:** round-trip; sai trường → `null`; lớn nhất vừa một lô; `aiUnavailableReply`; ngân sách `busy`.
- **B12:** ghép phần, thiếu phần, sai loại ảnh, vượt cỡ, hết hạn 2 phút, điện thoại rời đi; desktop nhận `ImageBlock` đúng.
3. **Một tin quá cỡ làm rơi cả kênh** (ảnh, `ai.item`, `ai.changes` với rất nhiều tệp, tiêu đề lịch sử dài). Test cỡ lớn nhất mỗi loại.

## Plan rulings R15, R17, R19, R23 (plan lines 65, 67, 69, 73):

- **R15 — a V2-2b request the computer cannot take fails at once on the phone** (`AiRequestException('unsupported')`, nothing sent). *Cost if wrong:* none.
- **R17 — blob numbers are the phone's own** (B12): unique per `MachineAi`, kept per phone on the desktop, taken by the prompt that uses them. *Cost if wrong:* none.
- **R19 — the image caps evict, they do not refuse** (B12): past 5 images or 20 MiB per phone, the phone's least recently used images are dropped (an upload retried under new numbers is never blocked for 2 minutes); an image over 10 MiB, or alone over the phone's 20 MiB, is `too_large`. *Cost if wrong:* an image uploaded long before its prompt is uploaded again.
- **R23 — images lost with the channel go again with the next Send** (B12, §7): the text and the images stay in the composer ("Ảnh chưa gửi được. Thử lại"), and one tap on Send uploads them again (new numbers) and then sends the prompt; nothing is uploaded or sent by itself. *Cost if wrong:* the upload starts at the tap instead of when the channel returns.

## Plan Global Constraints: Never auto-allow, No content in logs, Protocol, Old peers, Request budget (lines 81–85):

- **Never auto-allow (D13, spec §6):** no path in which a phone answers without a user tap; a notification button is that tap, and its answer goes only after the app's own lock (R7); push buttons offer only the first `allow_once` that turns on no no-approval mode and the first `reject_once` — never `allow_always`/`reject_always`; no answer is ever resent after a lost channel; a no-approval mode is never listed for, nor set from, a phone (R16); a remembered no-approval mode is never re-applied.
- **No content in logs (D12, B25):** no prompt, agent text, path, file name, diff, image, URL, header or body in any log; new log lines print only `error.runtimeType`. `toString()` of every new `ai.*` message is `'<Type>(…)'`; of every new body/view/record `'…'` (`with Redacted`) or `'<Name>(…)'`; each pinned by a test. Push data carries only an integer id, two option ids and a tag beyond V2-2a's (B25).
- **Protocol (exact values):** `kAiProtocol = 2`; `kAiMaxBodyBytes = 48 * 1024` (unchanged); `kAiMaxBlobPartBytes = kAiMaxBodyBytes`; `kAiMaxPromptBytes = 32 * 1024`; `kAiMaxPromptFiles = 20`; `kAiMaxPathBytes = 1024`; slices ≤ 36 KiB escaped (`kAiSliceBytes`), full item ≤ 2 MiB (`kAiFullItemBytes`), cached 60 s, ≤ 4 per phone; history ≤ 50 sessions per page, titles ≤ 120 bytes; config ≤ 40 choices per option, names ≤ 60 characters; changes ≤ 200 files; `ai.files` ≤ 8 suggestions; images ≤ 5 × 10 MiB, ≤ 20 MiB per phone, kept ≤ 2 minutes unused, ≤ 4 parts in flight; new result codes `no_images`, `confirm`, `busy_turn`, `not_ready`, `undo_off`, `too_big` (+ `unsupported` made by the phone itself). Every new message fits one sealed batch with its envelope (pinned per kind).
- **Old peers:** a malformed `ai.*` message is skipped and an unknown kind ignored, never dropping the channel; every V2-2b feature is gated by router `ai ≥ 2` AND listing `f` (R3); an older desktop or service never receives a V2-2b request; an older phone ignores `body`, `f`, `src`, `img` and the new header keys.
- **Request budget** unchanged (60 at once, then 30/s per phone; acks and detaches free); every new request kind, each `ai.blob` part included, costs one token and gets exactly one `ai.result`.

## Cross-task rules from earlier reviews (SDD ledger)

- Every V2-2b `MachineAi` request method must go through `MachineAi._feature` (R3/R15: router `ai ≥ 2` AND listing `f`; else `AiRequestException('unsupported')` at once, nothing sent).
- Every hub request answers exactly one `ai.result`, to the phone that asked only; a body over one message is never sent (`too_big`). Task 10's `_ask` serves session requests; `_prompt` and `_blob` follow their own pattern (`_blob` is about no session).
- V2-2 D13: nothing is ever sent again by itself after a lost channel — a prompt is never resent; R23: the phone uploads the images again only on the user's next Send.
