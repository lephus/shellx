# Task 23 constraints (verbatim excerpts) — Desktop: `AiUndo` extracted from the Changes panel

## Spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md` (binding; Vietnamese) — §2 (line 62); B19 (line 93); §8 B19 (line 216); §9 Review Focus 4 (line 229); §12 (line 263):

| Mảng | Hiện có | Hệ quả |
|---|---|---|
| Hoàn tác | API runtime có (`changesSince`, `changedAfterTurn`, `revert`, `fileBefore`); **logic hoàn tác nằm trong widget desktop** (`ai_changes_panel.dart:116-191`, hộp thoại B14 của V2-1b) | B19: tách lớp `AiUndo` dùng chung |

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B19 | Thay đổi, hoàn tác | Tách `AiUndo` (thuần Dart, không widget) khỏi `aiRevert`: `plan(turn?)` (tệp đổi, tệp bị sửa sau lượt) và `apply(plan, keep)`. Desktop panel và hub dùng chung. Tin: `ai.changes {sid, rid, turn?}` → `{"scope", "turn"?, "files": [{"p", "k": "a|m|d", "plus"?, "minus"?}], "after": [đường dẫn], "turns": {"first", "last", "done"}, "off"?, "more"?}` (≤ 200 tệp); `ai.diff {sid, rid, turn?, path}` → vùng đổi của một tệp như diff của mục gương, hoặc `{"binary": true}` / `{"missing": true}`; `ai.revert {sid, rid, turn?, keep?}` → desktop **tính lại lúc làm**: có tệp bị sửa sau lượt mà chưa có `keep` thì `confirm` kèm danh sách, điện thoại hỏi như hộp thoại B14 của desktop rồi gửi lại với `keep: clean|all`; đang có lượt chạy → `busy_turn`; hoàn tác tắt → `undo_off`. Pane AI trên desktop ghi "Đã hoàn tác N tệp (từ điện thoại)." | Thao tác phá huỷ từ màn hình nhỏ: có hỏi lại, chống chạm nhầm 400 ms. |

- **B19:** `AiUndo` dùng chung cho desktop (test desktop cũ vẫn xanh) và hub; `confirm`; `busy_turn`; ghi chú trên pane.
4. **Hoàn tác từ điện thoại khi máy tính đang làm việc:** lượt đang chạy, tệp vừa đổi. Test `busy_turn`, `confirm`.

| Rủi ro | Mức | Xử lý |
|---|---|---|
| Tách `AiUndo` làm hỏng hoàn tác trên desktop | Trung bình | Test desktop hiện có phải xanh; test mới cho lớp tách |

## Plan Global Constraints: No content in logs, Desktop, Commands (plan lines 82, 88, 89):

- **No content in logs (D12, B25):** no prompt, agent text, path, file name, diff, image, URL, header or body in any log; new log lines print only `error.runtimeType`. `toString()` of every new `ai.*` message is `'<Type>(…)'`; of every new body/view/record `'…'` (`with Redacted`) or `'<Name>(…)'`; each pinned by a test. Push data carries only an integer id, two option ids and a tag beyond V2-2a's (B25).
- **Desktop:** strings in `apps/desktop/lib/l10n/app_en.arb` + `app_vi.arb`, generated with `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n` (generated `lib/l10n/app_localizations*.dart` committed).
- **Commands (verified 2026-10-15):** `cd packages/<p> && ~/fvm/versions/3.41.4/bin/dart test [file]` and `~/fvm/versions/3.41.4/bin/dart analyze` for `shellx_core`, `shellx_ai`, `shellx_agent`, `shellx_client`, `shellx_e2e`; `cd apps/<app> && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test [file]` and `… flutter analyze` for `desktop`, `mobile`; `cd relay && npm ci && npm test && npm run typecheck`. Format only the files a task touches: `~/fvm/versions/3.41.4/bin/dart format <files>` from the package or app directory.

## Plan Review Focus 4 (plan line 100):

4. **A revert from the phone while the computer works** — a turn running, a file just changed. [Task 24: "while a turn runs a revert is busy_turn, and nothing goes back (Review Focus 4)", "a file the computer changed after the phone looked asks first; "clean" leaves it (Review Focus 4)". Task 25: "a revert asks first with the files; a tap in its first 400 ms does nothing (Review Focus 4)", "files changed after the turn: the computer asks, the phone offers only-unchanged or all (Review Focus 4)", "while a turn runs the revert is dim and says to wait; busy_turn …".]

## Controller rulings and cross-task contracts (SDD ledger)

- Ruling (F4): Task 23 matches its `aiRevert` replace block in `apps/desktop/lib/src/ui/ai/ai_changes_panel.dart` by content; its "lines 113-191 at 38a786d" are informational (Task 6 moved `AiTurns`/`aiTurnsOf`/`aiUndoOffOf` out of that file to `package:shellx_ai`'s `undo_view.dart`, re-exported). Today `aiRevert`'s doc comment starts at line 80 and the next item's doc (`/// "Reviewed" (§4.4) …`) at line 162.
- Task 24 consumes this task's `AiUndo`, `AiUndoPlan`, `AiUndoBusy`/`AiUndoFailed`/`AiUndoNothing`, `AiUndoDone` exactly as the brief's Interfaces state.
- Desktop pre-existing test noise (not this task's finding): `ai_phone_test.dart` prints `ShellX: AI session for a phone failed: StateError`.
