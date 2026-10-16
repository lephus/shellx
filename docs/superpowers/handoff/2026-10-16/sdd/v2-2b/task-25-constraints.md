# Task 25 constraints (verbatim excerpts) — Phone: Changes sheet, diff page, revert

## Spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md` (binding; Vietnamese) — criteria 6, 14 (lines 36, 44); B1, B19, B20 (lines 75, 93, 94):

6. **Thay đổi, hoàn tác.** Từ dòng "Lượt 3 · 2 tệp đổi" mở danh sách tệp (+/−), chạm một tệp xem diff; "Hoàn tác lượt này" hỏi lại kèm danh sách tệp, rồi hoàn tác trên máy tính; pane AI trên máy tính ghi "Đã hoàn tác 2 tệp (từ điện thoại)".
14. **Bản cũ.** Điện thoại V2-2b với desktop V2-2a, hoặc cửa sổ V2-2b với dịch vụ nền V2-2a: không hiện nút nào của V2-2b, phần V2-2a chạy như cũ. Điện thoại V2-2a với desktop V2-2b: như cũ. Mọi test hiện có vẫn xanh.

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B1 | Khả năng (hai lớp) | Điện thoại chỉ dùng một tính năng V2-2b khi **cả hai**: (a) router báo `ai: 2` trong `session.list.result` (`kAiProtocol = 2` ở tiến trình giữ relay: daemon khi bật dịch vụ nền), chứng minh đường chuyển tiếp hiểu V2-2b; (b) listing của cửa sổ có `"f": [...]` liệt kê tính năng hub làm được (`config`, `blob`, `files`, `changes`, `revert`, `item`, `history`, `folder`, `push_answer`, `acp_head`). Thiếu một trong hai thì nút tương ứng không hiện. | — |
| B19 | Thay đổi, hoàn tác | Tách `AiUndo` (thuần Dart, không widget) khỏi `aiRevert`: `plan(turn?)` (tệp đổi, tệp bị sửa sau lượt) và `apply(plan, keep)`. Desktop panel và hub dùng chung. Tin: `ai.changes {sid, rid, turn?}` → `{"scope", "turn"?, "files": [{"p", "k": "a|m|d", "plus"?, "minus"?}], "after": [đường dẫn], "turns": {"first", "last", "done"}, "off"?, "more"?}` (≤ 200 tệp); `ai.diff {sid, rid, turn?, path}` → vùng đổi của một tệp như diff của mục gương, hoặc `{"binary": true}` / `{"missing": true}`; `ai.revert {sid, rid, turn?, keep?}` → desktop **tính lại lúc làm**: có tệp bị sửa sau lượt mà chưa có `keep` thì `confirm` kèm danh sách, điện thoại hỏi như hộp thoại B14 của desktop rồi gửi lại với `keep: clean|all`; đang có lượt chạy → `busy_turn`; hoàn tác tắt → `undo_off`. Pane AI trên desktop ghi "Đã hoàn tác N tệp (từ điện thoại)." | Thao tác phá huỷ từ màn hình nhỏ: có hỏi lại, chống chạm nhầm 400 ms. |
| B20 | Hoàn tác trên điện thoại | Dòng hết lượt "Lượt 3 · 2 tệp đổi +44 −5" chạm được → bảng Thay đổi (lượt này / cả phiên) → trang diff. "Hoàn tác lượt này" màu đỏ, mờ khi đang có lượt chạy, hỏi lại kèm danh sách tệp; nút trong hộp hỏi chống chạm 400 ms (§13 V2-2). | — |

## Spec §5 (lines 149–150, 160–166), §6 (lines 180–184), §7 (line 197), §8 (lines 216, 220), §9 RF4 (line 229):

| Khoá | EN | VI |
|---|---|---|
| `aiChanges` / `aiThisTurn` / `aiWholeSession` | Changes / This turn / Whole session | Thay đổi / Lượt này / Cả phiên |
| `aiRevertTurn` | Revert this turn | Hoàn tác lượt này |
| `aiRevertConfirm` | Revert {n} files to before turn {turn}? | Đưa {n} tệp về như trước lượt {turn}? |
| `aiRevertTouched` | {n} files changed after this turn. | {n} tệp đã đổi sau lượt này. |
| `aiRevertOnlyClean` / `aiRevertAll` | Only unchanged files / Revert all | Chỉ tệp chưa đổi sau đó / Hoàn tác hết |
| `aiRevertBusy` | Wait for the turn to finish. | Chờ lượt này xong. |
| `aiRevertedFromPhone` (desktop) | Reverted {n} files (from your phone). | Đã hoàn tác {n} tệp (từ điện thoại). |

- Không có đường nào trả lời mà không có một lần chạm của người dùng (D13 giữ nguyên). Nút trên thông báo chỉ mang hai lựa chọn "một lần"; câu trả lời chỉ gửi sau khoá Face ID của app; không gửi lại sau khi mất kênh.
- Chế độ bỏ qua xin quyền không bao giờ được liệt kê hay đặt từ điện thoại (B11).
- Đường dẫn từ điện thoại (B13, B19) chỉ là đường dẫn desktop đã đưa và phải nằm trong thư mục phiên; desktop kiểm lại lúc làm.
- Ảnh chỉ nằm trong bộ nhớ desktop tới khi gửi cho agent (B12).
- Không log nội dung; `toString` của mọi tin mới trả `Tên(…)`, có test.

| Tình huống | Hành vi |
|---|---|
| Hoàn tác khi máy tính vừa sửa tệp | Tính lại lúc làm, hỏi `confirm` |

- **B19:** `AiUndo` dùng chung cho desktop (test desktop cũ vẫn xanh) và hub; `confirm`; `busy_turn`; ghi chú trên pane.
- **App mobile (widget):** từng màn mới, chống chạm 400 ms ở hoàn tác, các trạng thái.
4. **Hoàn tác từ điện thoại khi máy tính đang làm việc:** lượt đang chạy, tệp vừa đổi. Test `busy_turn`, `confirm`.

## Plan rulings R3, R12, R15 (plan lines 53, 62, 65):

- **R3 — capability = router `ai ≥ 2` AND listing `f`** (B1): learned from `session.list.result` and the window's listing; the AI session page asks `session.list` once when the protocol is unknown (opened from a push) and holds the listing while open. *Cost if wrong:* one extra round trip when a page opens cold.
- **R12 — a phone's revert opens the desktop pane's Changes panel** (B19) and writes "Đã hoàn tác N tệp (từ điện thoại)." at its foot, like the desktop's own revert. *Cost if wrong:* the panel opens without the user asking.
- **R15 — a V2-2b request the computer cannot take fails at once on the phone** (`AiRequestException('unsupported')`, nothing sent). *Cost if wrong:* none.

## Plan Global Constraints: Naming, No content in logs, Old peers, Mobile (plan lines 79, 82, 84, 87):

- **Naming:** "Claude" or "Claude Agent", never "Claude Code", in feature names and UI strings.
- **No content in logs (D12, B25):** no prompt, agent text, path, file name, diff, image, URL, header or body in any log; new log lines print only `error.runtimeType`. `toString()` of every new `ai.*` message is `'<Type>(…)'`; of every new body/view/record `'…'` (`with Redacted`) or `'<Name>(…)'`; each pinned by a test. Push data carries only an integer id, two option ids and a tag beyond V2-2a's (B25).
- **Old peers:** a malformed `ai.*` message is skipped and an unknown kind ignored, never dropping the channel; every V2-2b feature is gated by router `ai ≥ 2` AND listing `f` (R3); an older desktop or service never receives a V2-2b request; an older phone ignores `body`, `f`, `src`, `img` and the new header keys.
- **Mobile:** strings in `apps/mobile/lib/l10n/intl_en.arb` and `intl_vi.arb` (same keys; `test/l10n_test.dart` checks), generated with `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart run intl_utils:generate`; routes and DI with `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart run build_runner build --delete-conflicting-outputs`; generated files committed. Colours and type from `context.colors` / `context.typo` only; no looping animation except a spinner while loading and the existing mic pulse. Page width 120 (`apps/mobile/analysis_options.yaml`).

## Plan Review Focus 4 (plan line 100):

4. **A revert from the phone while the computer works** — a turn running, a file just changed. [Task 24: "while a turn runs a revert is busy_turn, and nothing goes back (Review Focus 4)", "a file the computer changed after the phone looked asks first; "clean" leaves it (Review Focus 4)". Task 25: "a revert asks first with the files; a tap in its first 400 ms does nothing (Review Focus 4)", "files changed after the turn: the computer asks, the phone offers only-unchanged or all (Review Focus 4)", "while a turn runs the revert is dim and says to wait; busy_turn …".]

## Controller rulings and cross-task contracts (SDD ledger)

- Task 6 contract (H1): `AiSessionController(@factoryParam String agentId, @factoryParam String sid, SessionHolder session, AiDrafts drafts, WorkspaceRegistry registry)` positional in this order; `can(feature)` reads the listing kept across a lost channel; page `_Header({…, VoidCallback? onSubtitle, List<AiHeaderAction> menu = const []})`.
- Task 13: `AiItemActions({onViewAll, onChanges, required child})` with `static AiItemActions? maybeOf(BuildContext)`; Task 25 sets `onChanges`.
- Task 24 produced (consumed here): `MachineAi.changes/diff/revert` through `_feature` (`unsupported` at once without the feature), the bodies of `changes_view.dart`, result codes `confirm` (with body), `busy_turn`, `undo_off`, `too_big`.
- Ruling (F11): where a brief's format command names whole directories, any file outside the task's Files block that it changes is restored to HEAD and reported, never committed.
- Ruling (F12): after `dart run intl_utils:generate` in apps/mobile, run `~/fvm/versions/3.41.4/bin/dart format lib/shared/src/l10n.dart lib/shared/src/intl/messages_en.dart lib/shared/src/intl/messages_vi.dart` from apps/mobile so the commit holds only the new entries; `intl_utils` may renumber its `mN` helpers and `build_runner` its `_iN` aliases in `app_router.gr.dart` (generator output, acceptable).
- The session page is ~760 lines and holds since Tasks 18–19: `_images`, `_mentions`, `_suggestions`, `_note` (cleared at each send, F39), `_dictation`, `_dictationMade` (F43, a page signal the dock's `Watch` reads).
- Mobile `flutter analyze` has one pre-existing info (`unnecessary_import`, `test/features/terminal/ime_in_place_edit_test.dart:2:8`) — not this task's finding.
