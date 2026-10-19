# Task 8 report: tabs and split panes UI

Status: DONE. Commit 10c18e58ba on shellx/l6-windows, pushed; its parent 6463ad16fa is another lane's shellx-remote fix.
CI run 39170733197 passed on the first round. All four jobs are green:
- app: 8m10s. Release build, `--smoke-ui-assets` PASS, `--smoke` PASS including the new pane checks.
- model
- remote-e2e
- installer

The run also covers 87da2d498a (Task 14 phase B: static CRT and installer job) and 6463ad16fa. My push cancelled the run that 6463ad16fa had started (cancel-in-progress), but 39170733197 contains that commit and is green.

## What was built
- `src/workspace.rs` (new, no GPUI; the window and `--smoke` share this code path):
  - `PaneHost<P>` maps each pane of every tab in a `Tabs` (inactive tabs included) to a live value. Calling `reconcile(&tabs, spawn)` first removes the values of panes the model no longer has. It returns them in `Reconciled { added, removed }`, and dropping them kills their shells. It then spawns values for new panes. If a spawn fails, the panes handled before the error stay reconciled.
  - `model_panes(&Tabs)` lists all panes.
  - `estimate_pane_area(viewport_w, viewport_h, sidebar)` subtracts the fixed chrome: `TITLEBAR_H` 40, `SESSION_BAR_H` 36, `SIDEBAR_W` 290. `DIVIDER` is 1.0.
  - `spawn_local_pane(cols, rows, extra_args)` returns a `LocalPane { core, link, reader }`. It is the one way a PowerShell pane is started.
  - `titlebar::HEIGHT` and `sidebar::WIDTH` now come from these constants.
- `local_pty.rs`: the child now sits behind `Arc<Mutex<..>>`, and a new `ExitProbe` (`LocalPty::exit_probe()`) can still see the shell after the link is dropped. `Drop` kills the child as before.
- `ui/panes.rs` (new) renders the active tab's tree:
  - Each `TermView` is placed with absolute position at its `Layout::rects(bounds, 1.0)` rect inside a `relative` container with a LINE background. The 1 px gaps therefore show as the LINE dividers.
  - No divider dragging.
  - `PaneArea` keeps the size from the last layout (a `canvas` measures it), keyed by viewport size and sidebar visibility. If the key is stale it falls back to `estimate_pane_area`. When the measured size differs from what a frame used, it asks for one more frame (`on_next_frame` → `refresh`, because `refresh` does nothing while drawing).
  - Rendering and `Tabs::focus_dir` use the same `PaneArea::bounds`.
  - A mouse down on a pane calls `RootView::focus_pane`.
- `ui/root.rs`: RootView owns one `Tabs` and a `PaneHost<PaneView>`, where `PaneView` holds the `Entity<TermView>` and RootView's `Subscription` to its events.
  - `reconcile` creates and subscribes views for new panes, drops the views of removed panes, then focuses the active tab's focused pane.
  - Commands:
    - NewTab
    - ClosePane: closes the focused pane through `close_pane`.
    - NextTab / PrevTab
    - SplitRight (Row) / SplitDown (Column)
    - FocusPane(dir): `focus_dir` with the rendered bounds.
    - ToggleSidebar
    - OpenSettings: still a no-op hook.
    - Copy / Paste: no-op arms.
  - `TermEvent::Exited` → `close_pane`. Every outcome other than NotFound (PaneClosed, TabClosed, Respawned) reconciles. The app never quits because a shell ended.
  - Session bar: 36 px, PANEL background with a LINE bottom border, then Terminal icon 14 px MUTED, the tab title (TEXT_HI), "›" and the machine name (MUTED).
  - The root `on_key_down` replaces Task 7's capture handler. It is a bubble-phase fallback for app commands that no pane handled.
- `ui/term_view.rs`:
  - The key handler is now `map_key`, with ctx `has_selection()` (false until Task 9) and `composing` (marked text present):
    - `App(Paste)` keeps the spike's paste.
    - `App(Copy)` is swallowed.
    - Other `App(cmd)` → `cx.emit(TermEvent::Command)` plus stop propagation.
    - `Chord` → `send_chord`; propagation stops only if it was encoded.
    - `Text` / `Ignore` do nothing.
  - The 500 ms poll now emits `TermEvent::Exited` when `LocalPty::is_closed()` is true (child exit, or the sticky write failure) instead of calling `cx.quit()`.
  - A pane whose shell failed to start shows its error and never emits Exited, so a failed spawn cannot loop. Ctrl+Shift+W still closes it.
  - Only the focused pane writes the a11y window title (the cursor-line stopgap), so split panes do not fight over it.
- `ui/sidebar.rs`:
  - One session row per tab. The title is the focused pane's OSC title, else `Str::LocalShell`. The active tab is highlighted, and a click calls `select_tab`.
  - A 14 px AddPlus button (`sidebar-new-tab`) sits at the right of this PC's group header. It opens a new local tab, and its tooltip `Str::NewTab` is a small RAISE/BORDER box.
  - The AddPlus on the machines header is unchanged (kept for Task 12).
- `shell_info.rs`: `Str::NewTab` was added to `SHELL_STRINGS` (now 8 strings).
- `smoke.rs` / `main.rs`:
  - `--smoke` runs the existing session checks, then `panes()`.
  - A new `--smoke-panes` flag runs only the pane checks. It is for local debugging, and the workflow does not use it.
  - Pane checks, through `PaneHost` with real `LocalPty` + `TermCore` panes:
    1. Build tab 1 = p1 | (p2 over p3), and tab 2 = p4.
    2. p2's shell runs `exit` → poll `is_closed` → `close_pane` gives `PaneClosed{t1, focus p3}`.
    3. The Ctrl+Shift+W path on tab 1's focused pane p3 gives `PaneClosed{t1, focus p1}`.
    4. Closing p1 gives `TabClosed{t1 → t2}`.
    5. Closing p4 gives `Respawned{p5}`, and p5 shows a prompt.
    6. Dropping the host ends every shell.
  - After each step: the live shells equal `model_panes`, every live shell `!is_closed()`, and every dropped pane's `ExitProbe` reports exited within 5 s.

## Evidence
- Mac: `cd windows && CARGO_INCREMENTAL=0 cargo test --locked -p shellx-app --bin shellx-desktop` → 19 passed. Five of them are new workspace tests:
  - reconcile across tabs and drops
  - tab close + respawn
  - spawn error
  - pane-area estimate
  - focus_dir vs rendered rects
- Mac: `--smoke-ui-assets` → `21 icons, 8 strings x 2 languages` / PASS.
- Mac: `PS1='PS> ' SHELLX_SHELL=/bin/sh cargo run -p shellx-app -- --smoke-panes` → all 5 steps OK on real Unix PTYs in 0.5 s.
- CI 39170733197, app job log:
  ```
  smoke-ui-assets: PASS
  smoke: … echo ok … unicode ok … resize ok (shell reports 120 columns)
  smoke: panes open: live [1,2,3,4]
  smoke: panes shell exit -> PaneClosed: live [1,3,4], removed [2] (exited)
  smoke: panes Ctrl+Shift+W -> PaneClosed: live [1,4], removed [3] (exited)
  smoke: panes last pane of a tab -> TabClosed: live [4], removed [1] (exited)
  smoke: panes last pane of last tab -> Respawned: live [5], added [5], removed [4] (exited)
  smoke: panes respawned shell PaneId(5) shows a prompt
  smoke: panes ok in 891ms
  smoke: PASS in 3.4s
  ```
- The GPUI code (root/panes/sidebar/term_view) compiled on CI on the first try. It cannot be built on the Mac.

## Manual G3 checks (Windows)
1. Start: one pane, sidebar row "PowerShell" (or the shell's title) highlighted, and the session bar reads "<title> › <PC name>".
2. Alt+Shift+= splits right: the new pane has the cursor and a 1 px line sits between the panes. Alt+Shift+- splits the focused pane down. Each pane reflows to its own size (e.g. run `$Host.UI.RawUI.WindowSize` in each).
3. Alt+←/→/↑/↓ moves focus between panes, with a solid cursor in the focused pane and hollow cursors elsewhere. A mouse click on a pane focuses it too.
4. Ctrl+Shift+T, or the small "+" right of the PC name in the sidebar (hover shows "Tab mới"), adds a tab. The sidebar then shows one row per tab. Click a row, or use Ctrl+Tab / Ctrl+Shift+Tab / Ctrl+PgDn / Ctrl+PgUp, to switch. A long-running command in a background tab keeps running: switch away and back.
5. Typing `exit` in a split pane closes only that pane. Its sibling takes the space and gets focus.
6. Ctrl+Shift+W does the same for the focused pane. On the last pane of a tab it closes the tab, and the neighbor tab becomes active.
7. Typing `exit` in the very last pane of the last tab opens a fresh PowerShell tab within about 0.5 s. The window never closes or goes empty.
8. Ctrl+Shift+B hides and shows the sidebar, and the panes reflow. Resizing or maximizing the window reflows all panes.
9. Telex IME in a split pane still composes inline. Ctrl+C / Ctrl+V still go to the shell, and Ctrl+Shift+V pastes.
10. The window close button quits the app, and no powershell.exe stays behind (Task Manager).

## Concerns / deviations
1. Two dead-code warnings remain in the Windows build of shellx-app:
   - `TermCore::size` (pre-existing)
   - `PaneHost::len` / `is_empty`, which only the tests use (the module's `allow(dead_code)` applies only off Windows)

   This is cosmetic. I did not spend another CI round on it; it can be dropped with the next task's push.
2. The pane area size can be stale for one frame. GPUI 0.2.2 has no synchronous child layout for absolutely positioned children, so the first frame after a window or sidebar change uses the size estimated from the chrome constants. The measured size follows on the next frame. A wrong estimate (e.g. odd DPI rounding) would show at worst for one frame: a sub-pixel LINE edge, or one extra PTY resize.
3. The root key fallback only fires when an event reaches the root div. I did not check (on GPUI Windows) whether a keystroke with no focused element reaches it. That should not happen in practice, because every structural change refocuses a pane, but a click on the sidebar empty space could leave focus nowhere.
4. Ctrl+Alt+<named key> now goes to text (the `map_key` AltGr rule from Task 2). The spike encoded it as a chord. Alt+arrows and Ctrl+Tab are app commands now and no longer reach the shell (Windows Terminal does the same).
5. Every pane is local: `PaneTarget` is ignored when spawning (Task 13 adds remote links there).
6. Closing a pane drops its `LocalPty` on the UI thread (kill, then `ClosePseudoConsole`). On older Windows 10 builds `ClosePseudoConsole` can wait for the output pipe to drain. The reader thread keeps draining into an unbounded channel, so it should not block.

## Files
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/src/workspace.rs (new)
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/src/ui/panes.rs (new)
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/src/ui/{root,term_view,sidebar,titlebar,mod}.rs
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/src/{local_pty,smoke,main,shell_info}.rs

I did not touch the workflow, `windows/.cargo/`, `windows/Cargo.toml` or `Cargo.lock`. I committed with explicit paths, and nothing is left staged.
