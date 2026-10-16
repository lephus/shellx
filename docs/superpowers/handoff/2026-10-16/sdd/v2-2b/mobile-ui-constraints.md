# Mobile UI constraints (verbatim excerpts) — Tasks 11 ("Chế độ và model" sheet) and 13 ("Xem đủ" viewer)

## Spec (binding; Vietnamese) — success criteria 2 and 7 (lines 32, 37); B11, B16 (lines 85, 90):

2. **Chế độ, model.** Chạm dòng phụ "Claude · Hỏi trước · Opus" → bảng chọn chế độ, model, mức suy nghĩ; chọn xong, máy tính đổi trong ≤ 2 s. Không bao giờ thấy chế độ bỏ qua xin quyền.
7. **Xem đủ.** Thẻ bị cắt có "Xem đủ"; mở ra tải hết (≤ 2 MiB) với "Đang tải 3/12".

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B11 | Chế độ, model | `ai.config.get {sid, rid}` → `ai.result {body}`: các tuỳ chọn thuộc nhóm `mode`, `model`, `thought_level`, `model_config` cùng lựa chọn hiện tại; **bỏ mọi lựa chọn bật chế độ bỏ qua xin quyền** (hàm B7) và với chế độ chỉ đưa những id đã biết là an toàn (`default`, `plan`, `acceptEdits`, `auto`, `auto_edit` và id agent không bị hàm B7 gắn cờ); tên cắt ≤ 60 ký tự; tối đa 40 lựa chọn mỗi tuỳ chọn (cờ `more`). `ai.config {sid, rid, body: {"id", "value"}}` hoặc `{"mode"}`: desktop kiểm lại với tuỳ chọn **lúc đó** (có, đúng nhóm, giá trị nằm trong danh sách, không bỏ qua xin quyền → `on_computer`) rồi `setConfig` và `rememberConfig` như chip desktop. Agent từ chối → `refused`. Header thêm `model {id, name}`. | Muốn "Bỏ qua mọi quyền" phải làm trên máy tính. |
| B16 | Xem đủ | `ai.item {sid, rid, i, part}` → `ai.result {body: {"i", "r", "part", "parts", "text"}}`. Desktop dựng **bản đầy đủ** của mục `i` một lần (đầu ra lệnh, dòng cắt ở 2 000 ký tự như desktop; mọi diff, mỗi tệp ≤ 1 MiB; input JSON; form câu hỏi; chữ), giữ 60 s theo (điện thoại, sid, i, rev), trả từng lát ≤ 36 KiB. Tổng ≤ 2 MiB, lớn hơn thì `too_big` và vẫn "Xem trên máy tính". `rev` đổi giữa chừng (lệnh còn chạy) thì tải lại từ đầu. Điện thoại: "Xem đủ" → trang xem toàn màn hình (dòng ảo hoá, chữ đơn cách, dùng lại khung diff), "Đang tải 3/12". Câu hỏi `big` xem đủ rồi trả lời được trên điện thoại (hub đã kiểm bằng `form.accepts`). | — |

## Spec §5 strings (lines 149–150, 154–155, 167):

| Khoá | EN | VI |
|---|---|---|
| `aiConfigTitle` | Mode and model | Chế độ và model |
| `aiConfigMode` / `Model` / `Effort` | Mode / Model / Thinking | Chế độ / Model / Mức suy nghĩ |
| `aiViewAll` / `aiLoadingParts` | View all / Loading {part}/{parts} | Xem đủ / Đang tải {part}/{parts} |

## Spec §8 (line 220) and §9 Review Focus 5 (line 230):

- **App mobile (widget):** từng màn mới, chống chạm 400 ms ở hoàn tác, các trạng thái.
5. **Chế độ bỏ qua xin quyền lọt qua** bằng một id lạ hay qua `ai.config` gửi thẳng. Test cả danh sách và lúc đặt.

## Plan rulings R3, R15, R16, R22 (plan lines 53, 65, 66, 72):

- **R3 — capability = router `ai ≥ 2` AND listing `f`** (B1): learned from `session.list.result` and the window's listing; the AI session page asks `session.list` once when the protocol is unknown (opened from a push) and holds the listing while open. *Cost if wrong:* one extra round trip when a page opens cold.
- **R15 — a V2-2b request the computer cannot take fails at once on the phone** (`AiRequestException('unsupported')`, nothing sent). *Cost if wrong:* none.
- **R16 — what mode/model choices a phone sees** (B11): every choice the no-approval predicate does not flag (Claude's `default`, `plan`, `acceptEdits`, `auto`, and other agents' unflagged ones); a boolean option named like a no-approval mode is not offered; the window checks again when setting (`on_computer`). *Cost if wrong:* "Bypass permissions" stays a computer-only choice.
- **R22 — "Xem đủ" on every open tool card with a body** (B16): the mirror cuts a call's input without saying so, so the phone cannot tell every cut card. *Cost if wrong:* a button that sometimes loads what is already shown.

## Plan Global Constraints: Naming, No content in logs, Old peers, Mobile (lines 79, 82, 84, 87):

- **Naming:** "Claude" or "Claude Agent", never "Claude Code", in feature names and UI strings.
- **No content in logs (D12, B25):** no prompt, agent text, path, file name, diff, image, URL, header or body in any log; new log lines print only `error.runtimeType`. `toString()` of every new `ai.*` message is `'<Type>(…)'`; of every new body/view/record `'…'` (`with Redacted`) or `'<Name>(…)'`; each pinned by a test. Push data carries only an integer id, two option ids and a tag beyond V2-2a's (B25).
- **Old peers:** a malformed `ai.*` message is skipped and an unknown kind ignored, never dropping the channel; every V2-2b feature is gated by router `ai ≥ 2` AND listing `f` (R3); an older desktop or service never receives a V2-2b request; an older phone ignores `body`, `f`, `src`, `img` and the new header keys.
- **Mobile:** strings in `apps/mobile/lib/l10n/intl_en.arb` and `intl_vi.arb` (same keys; `test/l10n_test.dart` checks), generated with `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart run intl_utils:generate`; routes and DI with `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart run build_runner build --delete-conflicting-outputs`; generated files committed. Colours and type from `context.colors` / `context.typo` only; no looping animation except a spinner while loading and the existing mic pulse. Page width 120 (`apps/mobile/analysis_options.yaml`).

## Controller rulings (SDD ledger)

- Ruling (F12): after `dart run intl_utils:generate` in apps/mobile, run `~/fvm/versions/3.41.4/bin/dart format lib/shared/src/l10n.dart lib/shared/src/intl/messages_en.dart lib/shared/src/intl/messages_vi.dart` from apps/mobile so the commit holds only the new entries (the generator writes 80 columns, the committed files are at 120).
- Ruling (F11): a format command naming whole directories never commits a file outside the task's Files block (restored to HEAD and reported).
- Task 6 contract (H1): `AiSessionController(@factoryParam String agentId, @factoryParam String sid, SessionHolder session, AiDrafts drafts, WorkspaceRegistry registry)` positional in this order; `can(feature)` reads `MachineAi._listing` (kept across a lost channel); page `_Header({…, VoidCallback? onSubtitle, List<AiHeaderAction> menu = const []})`, key `ai.status.tap` when `onSubtitle` is set.
- Mobile `flutter analyze` has one pre-existing info (`unnecessary_import`, `test/features/terminal/ime_in_place_edit_test.dart:2:8`) — not a task's finding.
