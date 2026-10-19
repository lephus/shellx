# Task 9 report: IME candidate placement, mouse selection + copy, safe bracketed paste, per-monitor DPI

Status: DONE. Commit b120faadc0 on shellx/l6-windows, pushed. Its parent 563cb95db7 is Task 10a's commit, which was already on the remote.
CI run 39172747108 passed on the first round. All four jobs are green:
- app: 7m36s
- model
- remote-e2e
- installer

The run contains 563cb95db7 as well. Its own run, 39171946097, ended cancelled after my run started.
The Windows build of shellx-app has only the 2 warnings that were already there (`TermCore::size`, `PaneHost::len/is_empty`). None come from Task 9 code.

## What was built

### `shellx-model/src/selection.rs`
This code has no GPUI and no ghostty, and its tests run on the Mac.
- `Selection::anchor()` / `head()`.
- `Selection::shifted(delta, rows)`: moves the selection by `delta` rows. It returns `None` once any selected row has left the viewport.
- `drag_selection(origin_span, over_span)`: one rule for plain, word and line drags. The span the click selected always stays selected, and the selection grows from its far end.
- `line_span(row, cols)`.
- `to_crlf(text)`: CRLF row joins for the clipboard.
- `char_cells(c)`: a small wcwidth table.
  - Combining marks and zero-width characters: 0.
  - CJK, Hangul, fullwidth and emoji: 2.
  - Precomposed Vietnamese letters: 1.
- `ime_rect(cursor, origin, cell_w, cell_h, preedit, range_utf16)`: window-space rect of a range of the preedit. The preedit starts at the cursor cell, and the rect is offset by the cells of the preedit chars before the range. It is at least one cell wide.
- `windows_ime_anchor(rect)`: moves the rect down half a row. Reason: GPUI 0.2.2 on Windows anchors both the IMM32 composition window and the candidate window at `(x, y + h/2)` of `bounds_for_range` (events.rs `retrieve_caret_position`), and it asks for that rect only at `WM_IME_STARTCOMPOSITION`. After the shift, the anchor point is the bottom edge of the cursor row, so the candidate list opens under the line, as in Windows Terminal.
- `ime_index_for_point`: the inverse of `ime_rect`.

### `shellx-app/src/term_core.rs`
- Removed `#[allow(dead_code)]` from `selection_text`, which is now used.
- New methods:
  - `viewport_offset()` (the scrollbar offset)
  - `scroll_to_bottom()`
  - `cursor_position()` (also while the cursor is hidden)
- New tests:
  - `selection_text_wide_chars_and_rows`
  - `viewport_offset_follows_output_and_wheel`
  - `smoke_input_paths`, which runs the smoke function below on the Mac

### `shellx-app/src/ui/term_view.rs`
**IME**
- Behavior kept from before:
  - While a preedit exists, keys go to the IME (map_key `composing`).
  - The preedit is drawn inline with the spike's underline and background.
  - Only `replace_text_in_range` sends text: one `send_text` of the whole committed string.
- The preedit is now also drawn while the app hides the cursor. It uses `cursor_position()` when the frame has no cursor.
- When composition starts, the selection is cleared and the view scrolls to the bottom.
- The old `cursor_bounds`, cached at paint time, is replaced by a `Grid` stored in prepaint: snapped origin, cell metrics, cols/rows, and the IME cell.
- `bounds_for_range` = `windows_ime_anchor(ime_rect(..))` over this pane's grid. Each split pane has its own origin, and the input handler is registered only for the focused pane.
- `character_index_for_point` uses the same geometry.

**Selection**
- Mouse handling is registered in `TermElement::paint` through `window.on_mouse_event`, with a prepaint hitbox. These are bubble listeners that never stop propagation, so TermView's focus handler and panes.rs `focus_pane` (model focus) still run. As the Task 8 review note asked, model focus and GPUI focus stay in step.
- Gestures:
  - Left mouse down: `click_count` 1 selects a cell, 2 a word (`word_at` over a one-char-per-cell row map; wide-char tails are `\0`), 3 or more a line.
  - Shift+click extends from the current anchor.
  - Moves are handled anywhere while dragging (GPUI calls `SetCapture`). If the button is up, the drag ends.
  - A single click with no movement selects nothing, so `has_selection` stays false.
- Drawing: `TERM_SELECTION` rects over the `spans`, painted after the cell backgrounds and before the cursor and text.
- `has_selection()` now reflects reality, so Ctrl+C copies only while something is selected.
- When the selection is cleared:
  - Typed input: an encoded chord, an IME commit, or the start of a composition.
  - Paste.
  - A grid resize.
- Output or the mouse wheel moving the viewport (offset delta, via `follow_viewport`) shifts the selection with the content. It is dropped once a selected row leaves the viewport.
- Rule documented in the module doc: when the scrollback is full, output scrolls without changing the offset. The selection then stays on the same screen rows until the next input.

**Copy**
- `AppCommand::Copy` → `TermCore::selection_text` (libghostty, aware of wide chars and soft wraps) → `to_crlf` → `cx.write_to_clipboard(ClipboardItem::new_string(..))`, then the selection is cleared.
- If libghostty returns nothing, it falls back to `selection::selected_text` over the cell map.
- Ctrl+Shift+C with no selection does nothing.
- Plain Ctrl+C with no selection is still the `ctrl+c` chord (SIGINT).

**Paste**
- `AppCommand::Paste` (Ctrl+Shift+V or Shift+Insert) → clipboard text → `TermCore::paste`, which normalizes newlines, strips embedded markers and brackets only under mode 2004. The spike's inline paste code is gone.
- Right-click does nothing.
- No mouse reporting: a plain drag selects even under mouse tracking, and so does Shift+drag.

**DPI**
- Metrics are recomputed on every prepaint from `window.scale_factor()`, with the line height in whole device pixels.
- New: the grid origin is snapped to a device pixel. The 6 px padding gives fractional device positions at 125 %.
- `observe_window_bounds` notifies the view when the scale changes. GPUI 0.2.2 has no `on_display_changed`; WM_DPICHANGED arrives as `bounds_changed`, which also refreshes the window.
- The PTY is resized when cols/rows change. Pixel metrics are never cached across frames.

**Cursor**
- The pane shows the I-beam cursor (`cursor_text()`).

### `shellx-app/src/ui/root.rs`
- The root-level Copy/Paste fallback (focus outside a pane) forwards to the focused pane's `clipboard_command`.

### `shellx-app/src/smoke.rs`
- New `input_paths()` plus one call line in `run()`, over a recording link:
  1. Feed `ESC[?2004h`, then `paste("echo a\x1b[201~b\n")` → exactly one write: `ESC[200~echo ab\rESC[201~`.
  2. `send_text("tiếng Việt")` → one write: `74 69 e1 ba bf 6e 67 20 56 69 e1 bb 87 74`.
  3. Copy of "ab漢字c" plus a second row through `selection_text` + `to_crlf` → `"ab漢字c\r\nok"`.

## Evidence
- Mac:
  - `cd windows && CARGO_INCREMENTAL=0 cargo test --locked -p shellx-model` → 109 passed. Eight of these are new selection/IME tests: shifted, drag_grows_from_the_origin_span, crlf, char_cells, ime_rect in a split pane (Telex, Japanese and astral preedits), the windows anchor, and ime_index_for_point inverting ime_rect.
  - `CARGO_INCREMENTAL=0 cargo test --locked -p shellx-app --bin shellx-desktop` → 29 passed, 3 of them new.
- CI 39172747108, app job, `--smoke`:
  ```
  smoke-ui-assets: PASS
  smoke-core: config.set OK, machines.list -> not_logged_in
  smoke-input: bracketed paste, IME commit (one UTF-8 write), copy ok
  smoke: … echo ok … unicode ok (tiếng Việt echoed by the shell) … resize ok
  smoke: panes … ok
  smoke: PASS in 3.76s
  ```
- The GPUI code (mouse events, hitbox, clipboard, observe_window_bounds, cursor_text) compiled on CI on the first try. It cannot be built on the Mac.

## Manual G1/G3 checks this enables (Windows)
1. **IME placement.** Split the window (Alt+Shift+=, then Alt+Shift+-). In the bottom-right pane:
   - The Windows Vietnamese Telex keyboard, and Unikey/EVKey (Telex), compose inline at the cursor. `tiếng Việt` + Enter shows correctly.
   - Microsoft Japanese IME: type `kanji`, then Space. The candidate list opens directly under the cursor row of that pane, not at the window's top-left and not over the preedit.
   - Repeat in the left pane, after `cls`, and after scrolling back with the wheel. Composing jumps to the bottom, and the list follows the cursor.
2. **Selection.**
   - Drag to select across rows: the highlight is primary at 30 %, under the text.
   - Double-click a path such as `C:\Users\x\a.txt` selects it whole.
   - Triple-click selects the line.
   - Shift+click extends the selection.
   - Typing clears the selection.
   - With `ping -t localhost` running, a selection moves up with the output and disappears once it scrolls off.
3. **Copy.**
   - Select, then Ctrl+C: Notepad gets the text with CRLF line breaks, and CJK text is not doubled.
   - Ctrl+Shift+C does the same.
   - With no selection, Ctrl+C interrupts `ping -t`.
4. **Paste.**
   - Ctrl+Shift+V or Shift+Insert of a multi-line script into PowerShell 7 or PSReadLine 2.x (bracketed paste on) lands as one multi-line edit buffer. Nothing runs until Enter.
   - Clipboard text containing `ESC[201~` does not break out of the paste.
   - Plain Ctrl+V still goes to the shell.
5. **DPI.**
   - At 150 % and 200 %, the text is crisp and rows are aligned.
   - Move the window between monitors with different scale: the grid is re-measured, the text stays sharp, and `$Host.UI.RawUI.WindowSize` matches the visible cols/rows.
6. **Vim with mouse on** (`:set mouse=a` over SSH): drag or Shift+drag selects. Nothing is reported to vim (out of scope).

## Concerns / deviations
1. The candidate anchor relies on GPUI 0.2.2 Windows internals: CFS_CANDIDATEPOS at `y + h/2`, set only at WM_IME_STARTCOMPOSITION. The half-row shift is isolated in `windows_ime_anchor` and documented. If a GPUI upgrade starts reading the rect properly, drop the shift.
   - The same point is used for the IMM composition window (CFS_POINT). If an IME draws its own composition window despite our inline preedit, it now sits under the line instead of over it.
   - Because the position is set only once per composition, a candidate list for a long preedit stays at the start of the composition. That is GPUI's behavior, not ours.
2. A full scrollback (10 MB) is the one case where output scrolls without changing the offset. The selection then stays on the same viewport rows until the next input (documented). Task 13 remote panes behave the same.
3. No autoscroll while dragging past the top or bottom edge. The selection clamps to the visible rows.
4. `char_cells` is an approximation, not full wcwidth (no new dependency). It is used only for preedit geometry. Copy uses libghostty.
5. Formatting accident, already undone: `cargo fmt -p shellx-model` also reformatted Task 10a's committed `account.rs`. I confirmed the diff was pure formatting and restored it with `git checkout` before committing. After that I ran `rustfmt` only on my own files.
6. The two pre-existing dead-code warnings (`TermCore::size`, `PaneHost::len/is_empty`) are still there. I did not touch workspace.rs.

## Files
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-model/src/selection.rs
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/src/term_core.rs
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/src/ui/term_view.rs
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/src/ui/root.rs
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/src/smoke.rs: one new function and one call line.

I did not touch Cargo.toml, Cargo.lock, main.rs, the workflow or Task 10a's files. I committed with explicit paths, and nothing is left staged.

## Fix round 1 (review)

### 1. Important: IME candidate position while scrolled back
Before this fix, `ime_cell` used `frame.cursor` (the cursor's position in the viewport) whenever it was visible. When the view was scrolled back k rows with the cursor still on screen, GPUI read `bounds_for_range` at `WM_IME_STARTCOMPOSITION`, before `replace_and_mark_text_in_range` scrolled to the bottom. The candidate window therefore anchored k rows too low, and GPUI never asks again.

Fix:
- New pure helper `shellx_model::selection::ime_cell(live_cursor, rows)`.
- term_view prepaint now always uses `ime_cell(session.cursor_position(), rows)`. That is the live cursor in the active area, which is where the preedit is drawn, since composing scrolls to the bottom.
- `frame.cursor` is now used only to paint the caret when nothing is being composed.

### 2. Minor: selection drift once the scrollback is full
Fix:
- New pure helpers `selection::{Viewport, Follow, follow_viewport(before, after, output_newline)}`:
  - The offset changed → `Shift(delta)`.
  - Offset unchanged, the output contained a newline, the view is at the live bottom, scrollback exists and its total row count did not change → `Clear`. This is the full-scrollback case.
  - Anything else → `Keep`.
- `TermCore::viewport()` (total/offset/len) replaces `viewport_offset()`.
- `TermView::follow_viewport(output_newline, f)` applies the result. The feed passes `batch.contains(&b'\n')`, and the wheel passes `false`.
- One accepted over-clear (documented): with scrollback present but the screen not scrolling (e.g. right after `cls`), a newline also clears the selection.

### Covering tests
- `selection::tests::ime_cell_uses_the_live_cursor`
- `selection::tests::follow_viewport_shifts_keeps_or_clears`: output scroll, wheel, full scrollback with and without a newline, scrolled back into history, and no scrollback yet.
- `term_core::tests::ime_cell_is_the_live_cursor_while_scrolled_back`, on a real libghostty terminal:
  - Setup: 40 lines, then the cursor is placed at row 10, col 4, then the view scrolls back 5 rows.
  - The viewport cursor moves to row 15.
  - `cursor_position()` and `ime_cell` stay at (4, 10).
- `term_core::tests::viewport_offset_follows_output_and_wheel` (updated to use `viewport()`)

Commands and output (Mac):
```
cd windows && CARGO_INCREMENTAL=0 cargo test --locked -p shellx-model
  test result: ok. 118 passed; 0 failed
cd windows && CARGO_INCREMENTAL=0 cargo test --locked -p shellx-app --bin shellx-desktop
  test result: ok. 38 passed; 0 failed
```
These counts include other lanes' new tests that are now in the working tree.

Files changed in this round:
- windows/shellx-model/src/selection.rs
- windows/shellx-app/src/term_core.rs
- windows/shellx-app/src/ui/term_view.rs

CI for fix round 1: run 39174283783 succeeded (app, model, remote-e2e, installer all green), commit 0d9b240787.
