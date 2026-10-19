# Task 9: IME (keep + candidate placement), mouse selection, copy, safe bracketed paste, DPI

Binding constraints: `../constraints.md`; Review Focus 1 (composed text leaves as ONE UTF-8 write) and 2 (paste markers). Builds on `ui/term_view.rs` (spike IME via `EntityInputHandler`, marked text drawn inline), `TermCore::{paste, send_text, selection_text}` (Task 5), model `shellx_model::selection::{Selection, Cell, cell_at, word_at, selected_text}`, `shellx_model::keys` (`KeyCtx.has_selection`, `AppCommand::{Copy, Paste}`). GPUI 0.2.2 source: `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/gpui-0.2.2/`. UI builds only on CI.

## IME (keep the spike's behavior, fix placement)
- Keep: while marked text exists, keys go to the IME (map_key `composing`), the preedit is drawn inline at the cursor with the spike's underline/bg, and only `replace_text_in_range` (commit) sends text: exactly ONE `TermCore::send_text(committed)` per commit (never per keystroke, never the preedit).
- Fix `bounds_for_range`: return the screen-space bounds of the cursor cell (+ the preedit width for ranges inside the marked text) using the pane's actual origin and cell metrics, so the Windows candidate window (Telex/Unikey/EVKey, Japanese IME) appears under the cursor of the focused pane — also in split panes and after scrolling. `character_index_for_point` consistent with it.
- A unit-testable pure helper for the geometry (e.g. `ime_rect(cursor: Cell, origin, cell_w, cell_h, preedit_utf16_range)`) in a GPUI-free module with tests run on the Mac (`cargo test -p shellx-app --lib` works on macOS because GPUI is cfg(windows); needs the ghostty submodule + Zig only if that module links ghostty — keep the helper free of ghostty types so `cargo test -p shellx-app --lib <helper>` still needs a ghostty build… if the crate's lib test build requires libghostty, put the helper in `shellx-model` instead (`shellx_model::selection` or a new `ime_geom.rs`) and test it there.

## Selection + copy (Windows Terminal style)
- Left-drag selects (linear stream selection); double-click selects a word (`word_at`); triple-click selects the line; Shift+click extends. Selection drawn as `TERM_SELECTION` rects over the selected cells (under the text). Selection is cleared on any typed input/paste and when the selected rows scroll out (simplest acceptable rule: clear on new output that scrolls the viewport; document).
- Copy: `AppCommand::Copy` (Ctrl+Shift+C, or Ctrl+C while a selection exists — `has_selection` now reflects reality) writes the selected text to the clipboard (`cx.write_to_clipboard(ClipboardItem::new_string(..))`) with CRLF row joins, then clears the selection. Prefer libghostty's `TermCore::selection_text(start, end)` (correct for wide chars); fall back to `selection::selected_text` only if needed. Plain Ctrl+C without a selection still goes to the shell (SIGINT).
- Paste: `AppCommand::Paste` (Ctrl+Shift+V, Shift+Insert) reads clipboard text and calls `TermCore::paste(text)` — which normalizes newlines, strips embedded `\x1b[200~`/`\x1b[201~`, and brackets only when the shell enabled mode 2004. Remove the spike's ad-hoc paste code. Right-click: no menu in the MVP.
- Mouse reporting: if the terminal has mouse tracking on (vim, htop with mouse), Shift+drag still selects (WT behavior); full mouse reporting to the app is out of scope unless trivial with `ghostty_vt` mouse encoding (do not add it now).

## DPI
- Per-monitor DPI (manifest PerMonitorV2 from the spike): recompute cell metrics from the window's scale factor on every prepaint (cheap) and on `on_display_changed`/scale changes; resize PTYs when cols/rows change. 150 %/200 % must render crisp (GPUI handles DirectWrite at device scale; just never cache pixel metrics across scale changes). Window moved between monitors with different scale → grid re-measured, no blurry text, PTY size updated.

## Tests
- Model/helper tests on the Mac for geometry and selection glue you add.
- `--smoke` (CI, headless): add checks that exercise the real paste path end to end with PowerShell where possible: write `"\x1b[?2004h"`-capable check is not possible with PowerShell 5.1 PSReadLine reliably — so instead in smoke, create a `TermCore` over a recording link, feed `"\x1b[?2004h"`, `paste("echo a\x1b[201~b\n")`, assert ONE write `"\x1b[200~echo ab\r\x1b[201~"`; and IME commit: `send_text("tiếng Việt")` = one write with the exact bytes `74 69 e1 ba bf 6e 67 20 56 69 e1 bb 87 74`. (If Task 5 already covers these as unit tests that CI runs, do not duplicate — reference them.)

## CI / acceptance
- `app` job green. Report the manual G1/G3 checks this task enables (Telex/Unikey/EVKey candidate window position in a split pane; select + Ctrl+C copies, Ctrl+C without selection interrupts `ping -t`; paste of a multi-line script into PowerShell does not execute lines one by one when PSReadLine bracketed paste is on; 150 %/200 %).

## Commit
`feat(shellx-app): IME candidate placement, mouse selection and copy, safe bracketed paste, per-monitor DPI`
