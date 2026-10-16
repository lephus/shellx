# Task 24 constraints (verbatim excerpts) — Changes, diff and revert from the phone; the desktop pane note

## Spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md` (binding; Vietnamese) — criteria 6, 14 (lines 36, 44); B1, B4, B19, B20 (lines 75, 78, 93, 94):

6. **Thay đổi, hoàn tác.** Từ dòng "Lượt 3 · 2 tệp đổi" mở danh sách tệp (+/−), chạm một tệp xem diff; "Hoàn tác lượt này" hỏi lại kèm danh sách tệp, rồi hoàn tác trên máy tính; pane AI trên máy tính ghi "Đã hoàn tác 2 tệp (từ điện thoại)".
14. **Bản cũ.** Điện thoại V2-2b với desktop V2-2a, hoặc cửa sổ V2-2b với dịch vụ nền V2-2a: không hiện nút nào của V2-2b, phần V2-2a chạy như cũ. Điện thoại V2-2a với desktop V2-2b: như cũ. Mọi test hiện có vẫn xanh.

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B1 | Khả năng (hai lớp) | Điện thoại chỉ dùng một tính năng V2-2b khi **cả hai**: (a) router báo `ai: 2` trong `session.list.result` (`kAiProtocol = 2` ở tiến trình giữ relay: daemon khi bật dịch vụ nền), chứng minh đường chuyển tiếp hiểu V2-2b; (b) listing của cửa sổ có `"f": [...]` liệt kê tính năng hub làm được (`config`, `blob`, `files`, `changes`, `revert`, `item`, `history`, `folder`, `push_answer`, `acp_head`). Thiếu một trong hai thì nút tương ứng không hiện. | — |
| B4 | Thân trong `ai.result` | `ai.result` có thêm `body` (byte JSON) tuỳ chọn. Dữ liệu lớn hơn một thân thì điện thoại **kéo từng phần** (`part`): mỗi lần một yêu cầu, nằm trong ngân sách yêu cầu sẵn có (60 dồn, 30/giây), không cần cửa sổ gửi mới. Mã mới: `no_images`, `confirm`, `busy_turn`, `not_ready`, `undo_off`, `too_big`. Điện thoại cũ đọc mã lạ thành câu chung. | — |
| B19 | Thay đổi, hoàn tác | Tách `AiUndo` (thuần Dart, không widget) khỏi `aiRevert`: `plan(turn?)` (tệp đổi, tệp bị sửa sau lượt) và `apply(plan, keep)`. Desktop panel và hub dùng chung. Tin: `ai.changes {sid, rid, turn?}` → `{"scope", "turn"?, "files": [{"p", "k": "a|m|d", "plus"?, "minus"?}], "after": [đường dẫn], "turns": {"first", "last", "done"}, "off"?, "more"?}` (≤ 200 tệp); `ai.diff {sid, rid, turn?, path}` → vùng đổi của một tệp như diff của mục gương, hoặc `{"binary": true}` / `{"missing": true}`; `ai.revert {sid, rid, turn?, keep?}` → desktop **tính lại lúc làm**: có tệp bị sửa sau lượt mà chưa có `keep` thì `confirm` kèm danh sách, điện thoại hỏi như hộp thoại B14 của desktop rồi gửi lại với `keep: clean|all`; đang có lượt chạy → `busy_turn`; hoàn tác tắt → `undo_off`. Pane AI trên desktop ghi "Đã hoàn tác N tệp (từ điện thoại)." | Thao tác phá huỷ từ màn hình nhỏ: có hỏi lại, chống chạm nhầm 400 ms. |
| B20 | Hoàn tác trên điện thoại | Dòng hết lượt "Lượt 3 · 2 tệp đổi +44 −5" chạm được → bảng Thay đổi (lượt này / cả phiên) → trang diff. "Hoàn tác lượt này" màu đỏ, mờ khi đang có lượt chạy, hỏi lại kèm danh sách tệp; nút trong hộp hỏi chống chạm 400 ms (§13 V2-2). | — |

## Spec §4.1 (lines 106–124), §5 (line 166), §6 (lines 180–184), §7 (line 197), §8 (lines 207, 216), §9 RF3, RF4 (lines 228–229):

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

| Khoá | EN | VI |
|---|---|---|
| `aiRevertedFromPhone` (desktop) | Reverted {n} files (from your phone). | Đã hoàn tác {n} tệp (từ điện thoại). |

- Không có đường nào trả lời mà không có một lần chạm của người dùng (D13 giữ nguyên). Nút trên thông báo chỉ mang hai lựa chọn "một lần"; câu trả lời chỉ gửi sau khoá Face ID của app; không gửi lại sau khi mất kênh.
- Chế độ bỏ qua xin quyền không bao giờ được liệt kê hay đặt từ điện thoại (B11).
- Đường dẫn từ điện thoại (B13, B19) chỉ là đường dẫn desktop đã đưa và phải nằm trong thư mục phiên; desktop kiểm lại lúc làm.
- Ảnh chỉ nằm trong bộ nhớ desktop tới khi gửi cho agent (B12).
- Không log nội dung; `toString` của mọi tin mới trả `Tên(…)`, có test.

| Tình huống | Hành vi |
|---|---|
| Hoàn tác khi máy tính vừa sửa tệp | Tính lại lúc làm, hỏi `confirm` |

- **Mỗi tin mới:** round-trip; sai trường → `null`; lớn nhất vừa một lô; `aiUnavailableReply`; ngân sách `busy`.
- **B19:** `AiUndo` dùng chung cho desktop (test desktop cũ vẫn xanh) và hub; `confirm`; `busy_turn`; ghi chú trên pane.
3. **Một tin quá cỡ làm rơi cả kênh** (ảnh, `ai.item`, `ai.changes` với rất nhiều tệp, tiêu đề lịch sử dài). Test cỡ lớn nhất mỗi loại.
4. **Hoàn tác từ điện thoại khi máy tính đang làm việc:** lượt đang chạy, tệp vừa đổi. Test `busy_turn`, `confirm`.

## Plan rulings R4, R12, R15, R18 (plan lines 54, 62, 65, 68):

- **R4 — one answer for everything:** a V2-2b request the hub does not take (yet), or an `AiRaw` with an integer `rid`, gets `refused` from a window and `unavailable` where no window serves AI. *Cost if wrong:* none (a phone never sends what `f` does not name).
- **R12 — a phone's revert opens the desktop pane's Changes panel** (B19) and writes "Đã hoàn tác N tệp (từ điện thoại)." at its foot, like the desktop's own revert. *Cost if wrong:* the panel opens without the user asking.
- **R15 — a V2-2b request the computer cannot take fails at once on the phone** (`AiRequestException('unsupported')`, nothing sent). *Cost if wrong:* none.
- **R18 — a path from a phone must be one the window offered** (B13, B19): relative, no `..`, ≤ 1 KiB, and checked again by the window (inside the session folder, there). *Cost if wrong:* a file the phone typed by hand is refused.

## Plan Global Constraints: No content in logs, Protocol, Old peers, Request budget, Desktop (plan lines 82–85, 88):

- **No content in logs (D12, B25):** no prompt, agent text, path, file name, diff, image, URL, header or body in any log; new log lines print only `error.runtimeType`. `toString()` of every new `ai.*` message is `'<Type>(…)'`; of every new body/view/record `'…'` (`with Redacted`) or `'<Name>(…)'`; each pinned by a test. Push data carries only an integer id, two option ids and a tag beyond V2-2a's (B25).
- **Protocol (exact values):** `kAiProtocol = 2`; `kAiMaxBodyBytes = 48 * 1024` (unchanged); `kAiMaxBlobPartBytes = kAiMaxBodyBytes`; `kAiMaxPromptBytes = 32 * 1024`; `kAiMaxPromptFiles = 20`; `kAiMaxPathBytes = 1024`; slices ≤ 36 KiB escaped (`kAiSliceBytes`), full item ≤ 2 MiB (`kAiFullItemBytes`), cached 60 s, ≤ 4 per phone; history ≤ 50 sessions per page, titles ≤ 120 bytes; config ≤ 40 choices per option, names ≤ 60 characters; changes ≤ 200 files; `ai.files` ≤ 8 suggestions; images ≤ 5 × 10 MiB, ≤ 20 MiB per phone, kept ≤ 2 minutes unused, ≤ 4 parts in flight; new result codes `no_images`, `confirm`, `busy_turn`, `not_ready`, `undo_off`, `too_big` (+ `unsupported` made by the phone itself). Every new message fits one sealed batch with its envelope (pinned per kind).
- **Old peers:** a malformed `ai.*` message is skipped and an unknown kind ignored, never dropping the channel; every V2-2b feature is gated by router `ai ≥ 2` AND listing `f` (R3); an older desktop or service never receives a V2-2b request; an older phone ignores `body`, `f`, `src`, `img` and the new header keys.
- **Request budget** unchanged (60 at once, then 30/s per phone; acks and detaches free); every new request kind, each `ai.blob` part included, costs one token and gets exactly one `ai.result`.
- **Desktop:** strings in `apps/desktop/lib/l10n/app_en.arb` + `app_vi.arb`, generated with `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n` (generated `lib/l10n/app_localizations*.dart` committed).

## Plan Review Focus 3, 4 (plan lines 99–100):

3. **One oversize message drops the whole channel** — images, `ai.item`, `ai.changes` with many files, long history titles. [Task 2: "the largest of each V2-2b message fits one sealed batch with its envelope". Task 12: "Review Focus 3: quotes, backslashes and control characters, the worst escaping, still fit". Task 14: "at most 50 sessions, titles cut; what could not be sent back is left out (Review Focus 3)". Task 16: "a part at the limit is taken, and one message holds it (Review Focus 3)". Task 24: "ten thousand changed files with long paths fit one body; the rest is counted (Review Focus 3)", "a confirm lists what fits of ten thousand touched files", "a file of nearly 1 MiB fits one message; one over is too_big (Review Focus 3)". Task 10's config view is cut to one body by `encodeConfigView`.]
4. **A revert from the phone while the computer works** — a turn running, a file just changed. [Task 24: "while a turn runs a revert is busy_turn, and nothing goes back (Review Focus 4)", "a file the computer changed after the phone looked asks first; "clean" leaves it (Review Focus 4)". Task 25: "a revert asks first with the files; a tap in its first 400 ms does nothing (Review Focus 4)", "files changed after the turn: the computer asks, the phone offers only-unchanged or all (Review Focus 4)", "while a turn runs the revert is dim and says to wait; busy_turn …".]

## Controller rulings and cross-task contracts (SDD ledger)

- Ruling (F3 revised, chunk 1): at Task 24, the first test of `packages/shellx_agent/test/ai/ai_phone_hub_v2b_test.dart` ("a V2-2b request whose feature the hub does not offer yet is answered refused…") is replaced by an assertion that every kind's feature word of `_requests()` is in `AiPhoneHub.offered`; the AiRaw and budget tests stay — the plan's removal alone would leave it filtering an empty list (`[] == []`, a test that asserts nothing).
- H2 (chunk 1): the plan writer never ran Task 24's hub test "every listing names changes and revert" in its final form: run it first.
- Ruling (F27, chunk 3): `const _Reply.refuse(String this.code, [this.body]);` — the code is non-nullable; every refusal passes a code.
- Every new hub request goes through `_ask` (`ai_phone_hub_requests.dart`); every new `MachineAi` request method goes through `_feature` (the old-peer rule R15: no feature → `AiRequestException('unsupported')`, nothing sent).
- Ruling (F30, chunk 3): `ai_phone_hub_edges_test.dart`'s empty-listing test equals `AiListing(features: rig.hub.features)`, so it follows `offered` by itself.
- `AiPhoneHub.offered` today: `{acpHead, pushAnswer, config, item, history, folder, blob, files}`; this task adds `changes`, `revert`.
- Task 23 produced `AiUndo` (`plan({int? turn, String? only})`, `apply(AiUndoPlan, {required bool keepTouched})`), `AiUndoPlan` (`turn`, `paths`, `after`, `touched`, `someClean`), `AiUndoBusy`/`AiUndoFailed`/`AiUndoNothing`, `AiUndoDone({ok, count, busy})`.
- Ruling (F11): where a brief's format command names whole directories, any file outside the task's Files block that it changes is restored to HEAD and reported, never committed.
- Desktop pre-existing test noise (not this task's finding): `ai_phone_test.dart` prints `ShellX: AI session for a phone failed: StateError`.
- From Task 23's review (cross-task, binding on Task 24): `AiUndoFailed` covers both "git did not answer" and "the turn has no restore point" (ai_undo.dart:19-21), so `undo_off` must be worked out by Task 24 itself (e.g. `aiUndoOffOf` / the turn whose restore point the phone's `turn` means); `AiUndo.apply` trusts `plan.paths` and `AiUndoPlan` has a public const constructor, so the window must apply only a plan returned by `AiUndo.plan()` at that moment — never one built from what the phone sent; `apply(plan, keepTouched: true)` with every file touched returns `ok: true, count: 0` without calling the runtime.
