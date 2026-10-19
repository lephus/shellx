# Task 3 report: shellx-model layout / tabs / selection

Built windows/shellx-model/src/{layout,tabs,selection}.rs + pub mod lines in lib.rs, per brief (all named tests present, plus extras: neighbor_prefers_largest_overlap, closing_a_background_tab_keeps_active_tab, new_tab_inserts_after_active, focus_and_focus_dir, rows_beyond_lines_are_empty).

Result: 49 tests pass, clippy -D warnings clean, fmt clean.

TDD honesty: tests and implementation were written in the same pass (no separate stub-RED run). The first test run did go RED on 2 tests (word_at_path_and_separators, pane_ids_never_reused) — both were mistakes in the tests themselves (miscounted column of the path end; pane_ids test assumed a respawn that did not happen), fixed in the tests; implementation unchanged. Clippy flagged one collapsible-if in a test, fixed.

Design notes / concerns:
- Closing a non-active tab's last pane keeps the active tab pointing at the same tab (brief only specified the active case).
- Layout also exposes `root()` and `is_empty()` (always false; clippy len_without_is_empty).
- neighbor tolerance EPS = 0.5 px; Layout::contains/len are O(n) via panes().
- Wide-char cell limitation documented in selected_text.
Commit: "feat(shellx-model): split tree, tabs with respawn on last close, grid selection" (not pushed).
