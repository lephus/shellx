# Task 3: shellx-model — split tree, tabs, grid selection

Binding constraints: `../constraints.md`. Files: ONLY `windows/shellx-model/src/{layout.rs, tabs.rs, selection.rs}` plus `pub mod` lines in `lib.rs`. Pure Rust; do NOT edit Cargo.toml/Cargo.lock. TDD (tests in each file). Run `cd ~/Documents/myProjects/shellx-wt-l6/windows && cargo test --locked -p shellx-model`. Commit locally only, staging only your files. `Dir {Left, Right, Up, Down}` already exists in `keys.rs` (re-exported from lib.rs) — reuse it, don't redefine.

## layout.rs — split tree of one tab
- `#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)] pub struct PaneId(pub u64);`
- `pub enum Axis { Row /* children side by side, divider vertical: "split right" */, Column /* stacked: "split down" */ }`
- `pub struct Rect { pub x: f32, pub y: f32, pub w: f32, pub h: f32 }` (Copy, PartialEq, Debug).
- `pub enum Node { Leaf(PaneId), Split { axis: Axis, ratio: f32 /* share of the first child, 0.1..=0.9 */, first: Box<Node>, second: Box<Node> } }`; `pub struct Layout { root: Node }`.
- API:
  - `Layout::new(pane) -> Layout`
  - `split(&mut self, target: PaneId, axis: Axis, new_pane: PaneId) -> bool` — replaces leaf `target` with `Split{axis, 0.5, Leaf(target), Leaf(new_pane)}`; false if target absent.
  - `close(&mut self, pane: PaneId) -> Close` where `pub enum Close { Closed { focus: PaneId }, Last, NotFound }`: removes the leaf; its parent split is replaced by the sibling subtree (sibling takes the whole space); `focus` = the leaf of the sibling subtree nearest the closed pane (closing a `first` child → leftmost/topmost leaf of the sibling; closing a `second` → the sibling's last leaf). Closing the only leaf → `Last` (layout unchanged).
  - `panes(&self) -> Vec<PaneId>` in reading order (depth-first, first before second).
  - `contains(pane) -> bool`, `len() -> usize`.
  - `rects(&self, bounds: Rect, divider: f32) -> Vec<(PaneId, Rect)>` — each split gives `first` `ratio * (extent - divider)` and `second` the rest after the divider; all f32, no rounding.
  - `neighbor(&self, pane: PaneId, dir: Dir, bounds: Rect, divider: f32) -> Option<PaneId>` — geometric: among panes whose rect lies entirely on the `dir` side of `pane`'s rect (e.g. Right: other.x >= pane.x + pane.w - ε) and overlaps it on the perpendicular axis, choose the closest edge, tie → largest overlap, tie → reading order.
  - `set_ratio(&mut self, first_leaf_of_split: PaneId, …)` — NOT needed (no divider dragging in the MVP; YAGNI).
- Tests: split/close round trips; `close_gives_space_to_sibling` (3-pane tree: close middle, the rects of the remaining two cover the bounds); `close_focus_moves_to_neighbor`; `close_last_reports_last`; `rects_respect_divider_and_ratio`; `neighbor_in_each_direction` on a 2×2 grid (split right, then split each column down).

## tabs.rs — tabs of layouts, pane ownership, local/remote targets
- `#[derive(Clone, Debug, PartialEq, Eq)] pub enum PaneTarget { Local, Remote { machine_id: String, terminal_id: String } }`
- `pub struct TabId(pub u64)` (Copy, Eq, Hash, Debug).
- `pub struct Tab { pub id: TabId, pub layout: Layout, pub focused: PaneId }` and `pub struct Tabs { tabs: Vec<Tab>, active: usize, targets: BTreeMap<PaneId, PaneTarget>, next_pane: u64, next_tab: u64 }`.
- `Tabs::new() -> (Tabs, PaneId)` — starts with one Local tab.
- `new_tab(&mut self, target: PaneTarget) -> (TabId, PaneId)` — appended after the active tab and made active.
- `split_focused(&mut self, axis: Axis, target: PaneTarget) -> PaneId` — splits the active tab's focused pane; the new pane gets focus. (A remote pane's split target is decided by the caller, e.g. a new remote terminal on the same machine; the model just records it.)
- `close_pane(&mut self, pane: PaneId) -> CloseOutcome` with `pub enum CloseOutcome { PaneClosed { tab: TabId, focus: PaneId }, TabClosed { closed: TabId, active: TabId }, Respawned { tab: TabId, pane: PaneId }, NotFound }`:
  - pane in a multi-pane tab → that pane only; sibling takes the space; focus = layout's `Closed{focus}` (only if the closed pane was focused; otherwise focus unchanged).
  - last pane of a tab while other tabs exist → the tab is removed; active becomes the tab to its left (or the new first tab when it was the first).
  - last pane of the last tab → a fresh Local tab is created (new TabId, new PaneId) and is active: `Respawned`. The app never ends up with zero tabs.
  - the closed pane's target is removed from `targets`.
- `focus(&mut self, pane)`, `focus_dir(&mut self, dir, bounds, divider) -> bool`, `select(&mut self, tab: TabId) -> bool`, `next_tab()`, `prev_tab()` (wrap around), `active(&self) -> &Tab`, `tabs(&self) -> &[Tab]`, `target(&self, pane) -> Option<&PaneTarget>`, `panes_on_machine(&self, machine_id) -> Vec<PaneId>` (remote panes for a machine; used to mark them offline).
- PaneIds are unique across all tabs for the lifetime of `Tabs` (never reused).
- Tests (name them): `closing_last_pane_of_last_tab_respawns` (Review Focus 4: single tab, close its pane → Respawned, exactly one tab, one Local pane, pane id differs from the closed one), `closing_a_split_pane_keeps_tab`, `closing_last_pane_of_a_tab_selects_left_neighbor`, `pane_ids_never_reused`, `next_prev_wrap`, `remote_targets_are_tracked_and_dropped_on_close`.

## selection.rs — grid selection (viewport coordinates)
- `#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)] pub struct Cell { pub row: u16, pub col: u16 }` (row first so Ord is reading order).
- `pub struct Selection { anchor: Cell, head: Cell }`: `new(at)`, `extend(&mut self, to)`, `is_empty()` (anchor == head), `ordered() -> (Cell, Cell)`, `spans(&self, cols: u16) -> Vec<(u16 /*row*/, u16 /*start col*/, u16 /*end col exclusive*/)>` — linear (stream) selection like Windows Terminal: first row from start.col to end of line, middle rows full, last row to head.col inclusive.
- `pub fn cell_at(x: f32, y: f32, cell_w: f32, cell_h: f32, cols: u16, rows: u16) -> Cell` — floor, clamped to the grid; negative → 0.
- `pub fn selected_text(sel: &Selection, lines: &[String], cols: u16) -> String` — `lines[row]` indexed by char (one char per cell; wide-char cells are a known limitation, document it in a comment); trailing spaces of each row trimmed; rows joined with `"\r\n"` (Windows clipboard); rows beyond `lines.len()` are empty.
- `pub fn word_at(line: &str, col: u16) -> (u16, u16)` — start..end (exclusive) of the run of non-separator chars around `col`; separators = whitespace and `` ()[]{}<>'"`,;|│ ``; on a separator → (col, col+1).
- Tests: single-row, multi-row (reverse drag gives the same text), trailing-space trim, CRLF join, `cell_at` clamping, `word_at` on a path `C:\Users\phu\x.txt` (backslash and colon are NOT separators), Vietnamese text `tiếng Việt` (char indexing, not bytes).

## Commit
`feat(shellx-model): split tree, tabs with respawn on last close, grid selection`
Report to the report path given in your dispatch.
