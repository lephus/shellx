# Task 7 report: custom title bar, machine sidebar, coolicons, §7.4 theme

Status: DONE. Commit f168cbfe76 on shellx/l6-windows (pushed; parent 8002a99089 = Task 6).
CI run 39168776979: success on the first round. app job 8m26s (release build, `--smoke-ui-assets` PASS, `--smoke` PASS, `--version`, artifact `shellx-desktop` uploaded). model and remote-e2e jobs also green.

## What was built
- `src/app.rs` became `src/ui/`, all `#[cfg(windows)]` through `mod ui` in main.rs:
  - `ui/mod.rs`: `pub fn run()`.
  - `ui/app.rs`: Application with `.with_assets(Assets)`, embedded fonts, a `Services` Global holding `lang: Lang::from_env()`, and a 1200×760 window (min 720×420) using `TitlebarOptions { title: "ShellX", appears_transparent: true }`.
  - `ui/theme.rs`: palette `Rgba` → `gpui::Hsla`, one fn per token. UI font "Segoe UI Variable Text" with fallback "Segoe UI", 13 px; small text 11 px; pill text 10 px; wordmark Space Grotesk Bold 16 px; caption glyph font "Segoe Fluent Icons" with fallback "Segoe MDL2 Assets", 10 px. Session row colors `#1a1430` (selected) and `#161026` (hover). Close hover is ERROR at 0.9.
  - `ui/assets.rs`: `AssetSource` over `crate::icons` (it only adapts the table) and re-exports `Icon`.
  - `ui/root.rs`: RootView. Title bar on top; below it a row with the sidebar (when visible) and the main area (BG, holds the one TermView, overflow hidden). Ctrl+Shift+B and Ctrl+, are caught in a root `capture_key_down` through `shellx_model::keys::map_key` (composing comes from TermView). Only ToggleSidebar and OpenSettings are handled; every other key reaches the terminal unchanged, which leaves Task 8 room to route the rest. `open_settings` is a no-op hook for Task 11.
  - `ui/titlebar.rs`: 40 px bar, PANEL background, 1 px LINE bottom border. The whole bar is `WindowControlArea::Drag`. From left to right:
    - sidebar toggle (WindowSidebar 16 px, MUTED, TEXT on hover)
    - centered search box, at most 360 px wide (RAISE background, 1 px BORDER, radius 6, Search icon and placeholder in MUTED, display only)
    - BellRing (display only)
    - Settings (calls the `open_settings` hook)
    - Min / Max-or-Restore / Close caption buttons, 46 px wide, using glyphs E921 / E922 / E923 / E8BB. Each has `.occlude()` + `.window_control_area(Min|Max|Close)` and no click handler on purpose: Windows performs the action from the hit-test, and a GPUI handler would swallow the NC click.

    Every interactive child occludes the drag hitbox. In GPUI 0.2.2 the hit-test returns the first control area it finds under the mouse, and the parent's Drag area is registered first, so without occluding the children the buttons would act as drag areas.
  - `ui/sidebar.rs`: 290 px wide, PANEL background, 1 px LINE right border. From top to bottom:
    - brand row: logo 20 px via `img(Resource::Embedded)`, which keeps full color, plus "ShellX" in Space Grotesk Bold 16 TEXT_HI
    - "MÁY CỦA BẠN" (11 px MUTED) with the AddPlus button (no-op)
    - the groups from `build_groups`: icon (Desktop/Laptop 16 MUTED), title 13 px SEMIBOLD TEXT_HI, "· máy này" 11 MUTED, 6 px DONE dot (MUTED when offline); dimmed groups at 50 % opacity with the subtitle
    - session rows under this PC: Terminal 13 px + title (OSC title, else "PowerShell"), selected background `#1a1430`, hover `#161026` when not selected, click focuses the terminal; the pill comes from `Status::pill` (Idle, so none)
    - footer pinned at the bottom with a LINE top border: ShieldCheck in DONE + E2E footer, 11 px MUTED
  - `ui/term_view.rs`: the spike's TermView/TermElement moved with git mv. Colors come from theme; it gains `composing()` and `terminal_title()`. IME, paste, scroll, the a11y window title and quit-on-exit are unchanged.
- `assets/icons/`: the 20 coolicons, unmodified (all use `stroke="currentColor"`; GPUI's `svg()` renders an alpha mask and tints it with text_color, so no file needed normalizing). Plus `logo.svg` from shellx `web/public/favicon.svg` with a header comment and width/height 512 → 40 (viewBox unchanged), so GPUI's img rasterizes it at 80 px instead of 1024 px.
- `src/icons.rs` (GPUI-free): `Icon` (21 variants) with `ALL`, `path()` = "icons/<file>", `bytes()` via include_bytes!, plus `by_path`, `list` and `looks_like_svg`. `looks_like_svg` skips whitespace, an XML declaration and comments (each coolicon starts with a `<!-- -->` credit line), then requires `<svg` and a `viewBox`.
- `src/shell_info.rs` (GPUI-free): `this_machine(COMPUTERNAME)` returns the brief's MachineInfo with fallback name "PC Windows"; `session_title` falls back to LocalShell; `SHELL_STRINGS` lists the 7 Str values the shell draws.
- `src/smoke.rs` / `main.rs`: `--smoke-ui-assets` checks that every `Icon::ALL` path resolves to embedded SVG bytes with a viewBox and that every SHELL_STRINGS entry is non-empty in vi and en; it prints `smoke-ui-assets: PASS`. Per the controller ruling, `--smoke` runs these checks first; no workflow change was made.

## Evidence
- Mac: `cd windows && cargo test --locked -p shellx-app --bin shellx-desktop` → 14 passed (8 new: icons ×4, shell_info ×4). `cargo run -p shellx-app -- --smoke-ui-assets` → `smoke-ui-assets: 21 icons, 7 strings x 2 languages` / `PASS`, exit 0.
- CI 39168776979, app job log: `smoke-ui-assets: PASS`, then `smoke: … echo ok … unicode ok … resize ok … smoke: PASS in 2.7s`. shellx-app built with a single warning (`TermCore::size` unused, from before this task).
- Tests were written together with the code, not red-first.

## What the window should look like (G3 check)
- No Windows caption. A 40 px dark-violet bar (#100b1d) runs across the top with a thin line under it. Far left: a sidebar-panel icon in muted lilac that brightens on hover. Middle: a rounded search field (#171128 with a #2a2145 border) reading "Tìm phiên, máy, lệnh… Ctrl+K" with a magnifier; clicking it does nothing. Right: a bell and a gear, then three flat caption buttons (—, □/restore, ✕). Hovering min or max shows a #171128 square; hovering close shows a soft red (#e88a8a at 90 %) with a brighter glyph.
- Things to try on the bar:
  - Drag the empty bar to move the window; double-click it to maximize.
  - Hover the max button on Windows 11: the snap-layout flyout should appear.
  - Maximize: the max glyph becomes the restore glyph.
  - Close quits the app.
- Left sidebar, 290 px wide, on #100b1d with a thin right border:
  - ShellX logo (purple tile with mint/lilac chevrons) and "ShellX" in Space Grotesk bold.
  - "MÁY CỦA BẠN" in small muted caps with a "+" on the right.
  - A desktop icon, the PC's name (COMPUTERNAME) in bold, "· máy này" and a small green dot.
  - One highlighted row (#1a1430) with a terminal icon and the terminal title. PowerShell usually sets this to its exe path, so expect a long, truncated path; "PowerShell" shows if no title is set.
  - At the bottom, above a thin line: a green shield and "Mã hoá đầu cuối · relay.shellx.pro".
- The rest of the window is the terminal on #0b0716. It should behave as before, including typing, Telex IME and resizing.
- Ctrl+Shift+B (or the toggle button) hides and shows the sidebar, and the terminal reflows to the new width. Ctrl+, does nothing yet.
- With `SHELLX_LANG=en` the strings switch to English.

## Concerns / deviations
1. The caption buttons are `h_full` inside a 40 px bar that has a 1 px bottom border, so they are 46×39, not 46×40.
2. The mockup's letter-spacing on "MÁY CỦA BẠN" is not reproduced: GPUI 0.2.2 has no letter-spacing.
3. Bell, settings and sidebar-toggle icons are all MUTED with TEXT on hover. The mockup draws bell and settings in TEXT; the brief only specified the toggle.
4. The search box uses RAISE as the brief says (the mockup used #140f24). The sidebar header text is 11 px per the brief (the mockup used 10.5).
5. build_groups gets a UTC offset of 0. Only this PC is listed, and it is never offline; a real offset is needed once remote machines arrive (Task 12).
6. `logo.svg` width/height changed to 40 (viewBox unchanged). The logo is the ShellX web favicon (ShellX's own logo, committed by ShellX contributors in 604a220c90), not cmux/Manaflow web code.
7. Font fallbacks are not verified visually:
   - "Segoe UI Variable Text" missing (Windows 10): GPUI logs an error and uses Segoe UI.
   - "Segoe Fluent Icons" missing: GPUI falls back to the system font, and the MDL2 glyphs come through the DirectWrite fallback list.
   - Logo sharpness at 125/150 % scaling is also unchecked.
8. Index sharing: my staged `git mv app.rs → ui/term_view.rs` was swept into Task 6's commit 8002a99089. That commit alone did not build on Windows (main.rs still had `mod app;`); f168cbfe76 fixes it. Task 6's own CI run 39168588868 was likely cancelled by the workflow's cancel-in-progress when I pushed; run 39168776979 covers both commits and is green. I committed with explicit paths (`git commit -- <paths>`), nothing of mine is left staged, and I did not touch the workflow or windows/Cargo.{toml,lock}.
9. Pre-existing Mac dead-code warnings (fonts constants, TermCore methods) remain; the new GPUI-free helpers carry a `cfg_attr(not(windows), allow(dead_code))`.

## Files
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/src/ui/{mod,app,theme,assets,root,titlebar,sidebar,term_view}.rs
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/src/{icons,shell_info,smoke,main}.rs
- /Users/lehuuphu/Documents/myProjects/shellx-wt-l6/windows/shellx-app/assets/icons/*.svg (21 files)
