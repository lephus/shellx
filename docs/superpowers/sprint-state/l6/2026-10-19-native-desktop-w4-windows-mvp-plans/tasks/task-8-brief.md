# Task 8: Tabs + split panes UI

Binding constraints: `../constraints.md`. Spec §7.1 ("Khu vực chính": session bar; panes split like cmux), Review Focus 4. Builds on Task 7's `ui/` (root.rs, sidebar.rs, term_view.rs) and the model: `shellx_model::tabs::{Tabs, PaneTarget, CloseOutcome, TabId}`, `shellx_model::layout::{Layout, Axis, Rect, PaneId}`, `shellx_model::keys::{map_key, KeyIn, KeyCtx, KeyAction, AppCommand, Dir}`. GPUI 0.2.2 source: `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/gpui-0.2.2/`. UI builds only on CI (windows-2025).

## Behavior
- RootView owns one `Tabs` model and a `HashMap<PaneId, Entity<TermView>>`. Each pane = its own TermView with its own `TermCore` + `LocalPty` (PowerShell). All structure changes go through the model; the view map is reconciled from it (create views for new panes, drop views — which kills the child — for removed ones).
- `ui/panes.rs`: renders the active tab's split tree via `Layout::rects(bounds, divider = 1.0)` — absolutely positioned children inside the main area, 1 px dividers in LINE. No divider dragging (MVP). Inactive tabs keep their views alive (not rendered), PTYs keep running.
- Session bar (top of main area, 36 px, bg PANEL? — mockup: same as `.presence`/session bar; use PANEL with bottom LINE): `Icon::Terminal` + "<tab title> › <machine name>" (TEXT_HI › MUTED). The "Tiếp tục trên điện thoại", "Chia sẻ" and More buttons are out of the MVP (do not render).
- Sidebar: under "this machine", one session row per tab (title = focused pane's terminal title, fallback `Str::LocalShell`), active tab highlighted; click selects the tab; a row-level close button is NOT needed. The `Icon::AddPlus` next to the machine group header? No — add a small "+" (`Icon::AddPlus`, 14 px) at the right of the THIS-MACHINE group header that opens a new local tab (tooltip `Str::NewTab`). The machines-header AddPlus stays reserved for pairing (Task 12).
- Keyboard: TermView's key handler calls `map_key` (ctx: has_selection from the view — false until Task 9 — and composing = IME marked text present). `KeyAction::App(cmd)` → emit to RootView (a GPUI event or a callback) and stop propagation; `Chord(c)` → `TermCore::send_chord`; `Text` → let it through to the input handler; `Ignore` → nothing. Commands: NewTab (Ctrl+Shift+T), ClosePane (Ctrl+Shift+W), NextTab/PrevTab (Ctrl+Tab, Ctrl+Shift+Tab, Ctrl+PgDn/PgUp), SplitRight (Alt+Shift+=), SplitDown (Alt+Shift+-), FocusPane(dir) (Alt+arrows, via `Tabs::focus_dir` with the same bounds used for rendering), ToggleSidebar (Ctrl+Shift+B). Copy/Paste are wired in Task 9 (keep them as no-op arms now, but Paste may keep the spike's existing paste behavior until Task 9 replaces it).
- Focus: clicking a pane focuses it (model + GPUI focus handle); the focused pane gets keyboard focus after every structural change; unfocused panes render normally (no dimming in MVP).
- Pane end: when a pane's `LocalPty::is_closed()` turns true (poll on the existing refresh timer or the reader thread's EOF), call `Tabs::close_pane` and reconcile: `PaneClosed` → sibling takes the space, focus moves; `TabClosed` → switch tab; `Respawned` → a fresh PowerShell tab appears (the app never quits or shows an empty window because the last shell exited). Same path for Ctrl+Shift+W.
- Window close button still quits the app (all children killed via Drop).
- Each pane resizes its PTY to its own rect (cols/rows from cell metrics) whenever layout or window size changes.

## Smoke
- Extend `--smoke` (headless, no GPUI): build `Tabs`, open two splits and a second tab, spawn real `LocalPty` shells for each pane (TermCore), close panes in an order that exercises PaneClosed → TabClosed → Respawned, assert the live shell set matches the model's panes after each step and that every dropped pane's child exited (`is_closed()` within 5 s). Put this orchestration in a GPUI-free module (e.g. `src/workspace.rs` — "PaneHost": map PaneId → TermCore/LocalPty + reconcile(&Tabs)) that RootView also uses, so the smoke tests the real code path.

## CI / acceptance
- `app` job green (build, `--smoke` PASS incl. the new pane checks, `--smoke-ui-assets` PASS). Stage only your files; push; iterate.
- Report: manual G3 checks the user should do (split right/down, Alt+arrows, exit last shell → new tab).

## Commit
`feat(shellx-app): tabs and split panes over the model, respawn when the last shell exits`
