# Task 7: App shell — custom title bar, sidebar, coolicons, theme

Binding constraints: `../constraints.md`. Mockup (layout authority): `docs/superpowers/design/2026-10-18-native-desktop/huong-d-mockup.html` (the "Hướng D" section, CSS vars at its lines 64–84); spec §7.1 (behavior), §7.4 (visual rules). GPUI 0.2.2 source for API lookup: `~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/gpui-0.2.2/` (examples/, src/). The UI compiles only on CI (windows-2025); you cannot build it on the Mac, so read GPUI's source for every API you use and keep each CI round-trip productive (`cargo check` errors come back in ~10–15 min warm).

## Files
- Restructure `windows/shellx-app/src/app.rs` into `src/ui/` (all `#[cfg(windows)]` via `mod ui` in main.rs): `ui/mod.rs` (pub fn run), `ui/app.rs` (Application, fonts registration, asset source, window options, global services), `ui/theme.rs` (shellx_model::palette → `gpui::Hsla`/`Rgba`; text sizes: UI 13 px Segoe UI Variable Text → fallback "Segoe UI"; small 11 px; wordmark Space Grotesk Bold 16 px), `ui/assets.rs` (`AssetSource` over `include_bytes!` of every SVG; `pub enum Icon { AddPlus, BellRing, ChevronDown, CircleCheck, Cloud, Command, Data, Desktop, Laptop, Link, Mobile, MoreHorizontal, QrCode, Search, Settings, Share, ShieldCheck, Terminal, Users, WindowSidebar, Logo }` with `fn path(self) -> &'static str` and `Icon::ALL`), `ui/root.rs` (RootView: title bar + sidebar + main area holding the existing single TermView for now; Task 8 adds tabs/splits), `ui/titlebar.rs`, `ui/sidebar.rs`, `ui/term_view.rs` (the spike's TermView/TermElement moved verbatim + theme colors; keep the IME code intact).
- `assets/icons/*.svg`: copy the 20 files from `docs/superpowers/design/2026-10-18-native-desktop/coolicons/` + `logo.svg` from `web/public/favicon.svg` (the logo keeps its own gradient — the only allowed gradient). Coolicons use `stroke="currentColor"`/`fill="currentColor"`? Check: `gpui::svg()` tints with `text_color`; if a file hard-codes a color, normalize it to `currentColor`/black so tinting works, and note it.
- `src/smoke.rs`: add `--smoke-ui-assets` (cross-platform, no GPUI): every `Icon::ALL` path resolves to embedded bytes that start with `<svg` (after optional XML prolog/whitespace) and contain `viewBox`; every Str used by the shell UI is non-empty in vi and en. Exit 0 / print `smoke-ui-assets: PASS`. Put the icon table in a GPUI-free module (e.g. `src/icons.rs` with `Icon`, `path`, `bytes`) so the smoke and `ui/assets.rs` share it; `ui/assets.rs` then only adapts it to `AssetSource`. Add a CI step running it in the `app` job.

## Title bar (40 px, bg PANEL, 1 px bottom border LINE) — spec §7.1
- Window created with `TitlebarOptions { title: Some("ShellX"), appears_transparent: true, .. }`; whole bar `.window_control_area(WindowControlArea::Drag)` except interactive children.
- Left: logo (16 px) is in the sidebar, not here; the bar starts with the sidebar toggle button (`Icon::WindowSidebar`, 16 px, MUTED, hover TEXT) — toggles sidebar visibility (also `AppCommand::ToggleSidebar`, Ctrl+Shift+B).
- Center: search box 360 px max, bg RAISE, 1 px BORDER, radius 6, `Icon::Search` + placeholder `Str::SearchPlaceholder` in MUTED. Display only in the MVP (no palette) — clicking does nothing; that is a known cut, not a bug.
- Right: `Icon::BellRing` (no badge in MVP), `Icon::Settings` (emits OpenSettings; Task 11 attaches a panel — for now a no-op hook), then Windows caption buttons 46×40 px each: minimize, maximize/restore, close, drawn with the "Segoe Fluent Icons" font (fallback "Segoe MDL2 Assets") glyphs `\u{E921}` min, `\u{E922}` max, `\u{E923}` restore, `\u{E8BB}` close, color TEXT, hover bg RAISE (close hover bg ERROR at 0.9 and glyph TEXT_HI), each with `.window_control_area(Min|Max|Close)` so Windows snap layouts/hit-testing work. No gradients, glows or shadows.

## Sidebar (290 px, bg PANEL, 1 px right border LINE) — spec §7.1 items 1–3 and 6
1. Header: logo 20 px + "ShellX" in Space Grotesk Bold 16 px TEXT_HI.
2. Row: `Str::MachinesHeader` (11 px, MUTED, letter-spacing as mockup) + `Icon::AddPlus` button on the right (no-op in this task; Task 12 hooks pairing).
3. Machine groups from `shellx_model::sidebar::build_groups(...)`. For now the only machine is this PC: `MachineInfo { machine_id: "local", name: <COMPUTERNAME env, fallback "PC Windows">, platform: "windows", online: true, last_seen_unix: 0, fingerprint: "", is_this_machine: true }`. Group header: icon (Desktop/Laptop, 16 px, MUTED), title TEXT_HI 13 px, note "máy này" MUTED 11 px, online dot 6 px DONE. Under it: one session row per local tab (for now: the single terminal) with `Icon::Terminal` + the terminal title (fallback `Str::LocalShell`), selected row bg `#1a1430` (mockup `.sess.cur`), hover `#161026`. Dimmed groups (offline) at 50 % opacity with the subtitle. Status pills via `palette::Status::pill` (none for local shells in the MVP).
4. Footer pinned to the bottom: `Icon::ShieldCheck` (DONE color) + `Str::E2eFooter` 11 px MUTED.
- "THIẾT BỊ ĐANG KẾT NỐI" (item 5) is out of the MVP.

## Main area
- bg BG; contains the TermView filling the space (the spike's grid). Keep resize-to-PTY working.

## CI / acceptance
- `app` job green: release build, `--smoke` PASS, `--smoke-ui-assets` PASS, artifact `shellx-desktop` uploaded.
- Report: a written description of what the window should look like for the user to verify at G3 (no screenshot is possible headless). If you can, add a `--screenshot <path>` flag? NO (YAGNI).
- Stage only your files; push `git push origin shellx/l6-windows`; iterate until green.

## Commit
`feat(shellx-app): custom title bar, machine sidebar, coolicons, §7.4 theme`
