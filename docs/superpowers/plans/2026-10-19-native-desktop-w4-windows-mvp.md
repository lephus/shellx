# ShellX Windows MVP (GPUI) — sprint lane L6 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Tóm tắt (cho người dùng):** Lane L6 biến bản thử GPUI (`spikes/windows-term`) thành app ShellX cho Windows bản MVP trong 10 giờ, chỉ build trên GitHub Actions. Kết quả: terminal PowerShell vẽ bằng GPU, nhiều phiên và chia khung, sidebar gom theo máy, bộ màu §7.4 và icon coolicons, gõ tiếng Việt (giữ preedit của bản thử), chọn chữ + sao chép + dán an toàn, đăng nhập, xin quyền xem một máy Mac (hiện mã 6 số, chờ Mac chấp thuận) và xem/gõ vào terminal của Mac qua relay v2, kiểm tra cập nhật, bộ cài `ShellX-Setup-2.0.0-sprint.exe` chưa ký, cài riêng cho người dùng, **chạy song song với bản Flutter** (không thay thế). Nếu cổng G1 cho thấy bộ gõ hỏng trên GPUI, lane chuyển sang nhánh dự phòng ở cuối file và chỉ giao terminal tại chỗ.

**Goal:** Ship, by T+10 of the 2026-10-19 sprint, a CI-built Windows MVP of ShellX (GPUI 0.2.2) that runs local ConPTY terminals with tabs and splits, matches the §7.4 look, types Vietnamese, logs in through `shellx-core`, pairs with and views a Mac terminal over relay v2 as a client, checks for updates, and installs per-user with an unsigned Inno Setup installer.

**Architecture:** One Cargo workspace at `windows/` in the fork with three crates: `shellx-model` (pure Rust, no GPUI, no libghostty: palette, strings, key mapping, paste encoding, split tree, tabs, sidebar, remote/pairing state machine, update rule, `shellx-core` JSON envelope; tested on the Mac in seconds), `shellx-remote` (GPUI-free client for the cmux-tui remote protocol over `cmux-relay`, built on `cmux-terminal-client`'s Rust API; integration-tested against a real `cmux-tui` daemon + `cmux-relay` on Linux CI and on the Mac), and `shellx-app` (GPUI 0.2.2 window; Windows-only UI modules behind `cfg(windows)`, plus the spike's `TermCore` over ConPTY and libghostty-vt). Local and remote panes share one `TermCore` (libghostty-vt `Terminal` + `RenderState` + `KeyEncoder`) and differ only in their byte link (`PtyLink`).

**Tech Stack:** Rust 2024 (toolchain from `.github/actions/setup-cmux-tui-rust`, `rust-version = "1.91"`), `gpui = "=0.2.2"` (Direct3D 11 + DirectWrite), `ghostty-vt` / `cmux-pty` / `cmux-terminal-client` / `cmux-remote` path crates from `cmux-tui/crates`, `shellx-core` (K3, path crate from lane L5), Zig 0.16.0 (libghostty-vt), Inno Setup 6.7.1, GitHub Actions `windows-2025` + `ubuntu-24.04`.

**Spec:** `docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md` (§2.2 items 2–3, §7, §7.4, §8.3, §11). Master plan (binding contracts K3, K5, gate G1, cut lines): `docs/superpowers/plans/2026-10-19-native-desktop-12h-sprint.md`. Ledger: `docs/superpowers/ledgers/native-desktop.md` ("Windows build (W0 Task 6)", D-W0-1). Mockup: `docs/superpowers/design/2026-10-18-native-desktop/huong-d-mockup.html`; icons `docs/superpowers/design/2026-10-18-native-desktop/coolicons/`. All `docs/…` paths are in the shellx repo (`~/Documents/myProjects/shellx`); all other paths are in the fork worktree `~/Documents/myProjects/shellx-wt-l6` unless prefixed.

## Global Constraints

- Branch `shellx/l6-windows` in the fork; worktree `~/Documents/myProjects/shellx-wt-l6`. Push only `git push git@phule9225.github.com:lephus/shellx.git shellx/l6-windows`. Never push `main`. No PRs: report "ready <sha>" to L0 (master Task L0.2).
- Builds of `shellx-app` happen on CI only (`windows-2025`). The Mac runs `cargo test` for `shellx-model` (always) and `shellx-remote` (Task 6, Task 13), never builds GPUI.
- Batch pushes: one push per CI-verified task (or two adjacent tasks), never per commit. A task that waits on CI may hand the wait to the next Mac-only task (see "Parallel rule").
- ShellX code lives in `windows/` and `.github/workflows/shellx-windows.yml`. Edits under `cmux-tui/` are limited to `cfg` gating needed by the Windows client path (Task 6), each one ≤ 10 lines and commented `// ShellX: Windows client path`.
- Version `2.0.0`; installer file `ShellX-Setup-2.0.0-sprint.exe`, unsigned, per-user (`PrivilegesRequired=lowest`), `MinVersion=10.0.17763` (ConPTY).
- Executable name `shellx-desktop.exe` (never `ShellX.exe`: the Flutter installer and uninstaller run `taskkill /IM "ShellX.exe"`, which is case-insensitive).
- Native state dir `%LOCALAPPDATA%\ShellX\native\` with `core\` (shellx-core `state_dir`) and `remote\` (cmux-remote client identity). Never under `%APPDATA%\pro.shellx\ShellX` or `%LOCALAPPDATA%\ShellX\{bin,term,restore,cli,mux}` (the Flutter uninstaller deletes those).
- API base `https://relay.shellx.pro`; relay `wss://relay.shellx.pro/v2/relay` (K2; take the URL from `tickets.mint`, never hard-code it elsewhere). Platform string `windows`, header `X-ShellX-Platform: windows` (sent by shellx-core).
- Palette §7.4 only (values in Task 2), no gradients, glows or colored shadows on any UI element; primary `#60a5fa`; running = `#e8c468`. Dark theme only.
- Fonts: terminal JetBrains Mono (embedded); wordmark and large headings Space Grotesk (embedded); UI text Segoe UI Variable, fallback Segoe UI.
- Icons: coolicons v4.1 SVGs drawn with `gpui::svg()` and tinted with the text color; About credits "coolicons by Kryston Schwarze" (CC BY 4.0).
- UI strings Vietnamese by default; English table selected by `SHELLX_LANG=en`.
- No telemetry, no Manaflow endpoints: `cmux-terminal-client` / `cmux-remote` are built with `default-features = false` (no `iroh-transport`, no `wireguard-transport`).
- Licenses: `shellx-*` crates `GPL-3.0-or-later`; no code from BUSL dirs (`web/`, `workers/*`, `services/iroh-relay-minter/`, `cmux-tui/relays/cloudflare-do/`); GPUI example code (Apache-2.0) adapted with a header comment naming its origin.
- Windows terminal keys follow Windows Terminal: copy `Ctrl+Shift+C` (and `Ctrl+C` only while a selection exists), paste `Ctrl+Shift+V` / `Shift+Insert`; plain `Ctrl+C` / `Ctrl+V` go to the shell.
- Never ask for secrets in chat; the app stores the account token only through shellx-core.

## Review Focus

1. **Vietnamese typed into a remote Mac terminal** (master Review Focus 4): Telex composition committed on Windows must leave as one UTF-8 write of the composed text (`tiếng Việt` = `74 69 e1 ba bf 6e 67 20 56 69 e1 bb 87 74`), never as raw keystrokes or per-keystroke preedit. Test: Task 12 `remote_commit_sends_composed_utf8` (fake link) and Task 13 e2e `vietnamese_round_trip`.
2. **Paste that contains the bracketed-paste end marker** (`\x1b[201~`) or a lone `\x1b[200~`: a reasonable user expects the clipboard text to arrive as data, never to break out of bracketed paste and run as typed commands. Test: Task 2 `paste_strips_embedded_markers`.
3. **The Mac goes offline, the relay restarts or the connect ticket expires while a remote pane is open:** the pane must show "ngoại tuyến"/"đang kết nối lại…", refuse input, never block the UI thread, and reconnect with backoff (1, 2, 4, 8, 16, 30 s cap) using a freshly minted ticket. Test: Task 4 `disconnect_backs_off_and_mints_new_ticket`, Task 13 e2e `reconnects_after_daemon_restart`.
4. **The last pane closes** (shell `exit`, `Ctrl+Shift+W`, or a remote terminal ending): only that pane closes, its sibling takes the space, focus moves to a neighbor, and closing the last pane of the last tab opens a fresh local tab instead of quitting the app or leaving an empty window. Test: Task 3 `closing_last_pane_of_last_tab_respawns`.
5. **The Flutter ShellX for Windows is installed and running:** installing or uninstalling the native build must not stop, replace or delete anything of the Flutter app (different AppId, exe name, install dir, Start-menu name, data dirs). Test: Task 14 `installer_coexists_with_flutter` (static check of the compiled `.iss` defines in CI).

---

## G1 decision point (≈ T+1, user on the Windows PC)

The user runs W0 Task 7 Step 3 checks on `shellx-term-spike.exe` (artifact `shellx-term-spike` of run `39149103261`, already green: build + `--smoke` PASS incl. `tiếng Việt` round-trip). The lane does **not** wait: Tasks 1–4 continue. When L0 relays the result:

| Result | Lane action |
| --- | --- |
| All pass, or only Narrator fails (expected: GPUI 0.2.2 has no UIA) | Stay on this plan. |
| Latency > 110 % of Windows Terminal | Stay; record numbers in the lane report; perf work is after the sprint. |
| IME cosmetic only (candidate window misplaced, preedit not drawn, but committed text correct for Telex, Unikey and EVKey) | Stay; Task 9 Step 1 fixes `bounds_for_range` / preedit drawing (already scoped there). |
| IME broken (committed text wrong or lost in any of Telex built-in / Unikey / EVKey, e.g. Unikey backspace-and-resend corrupts the line, or no commit arrives) | Switch to **Fallback branch G1-FAIL** at the end of this file, from the next task boundary. |

## Parallel rule

`shellx-model` tasks (2, 3, 4) touch only `windows/shellx-model/` and need no CI. While a CI-bound task waits on a run (typically 12–25 min), the controller may dispatch the next not-yet-done model task to a second implementer; they never edit the same files. From T+6 L2 may join (master clock "L2 frees → helps L6 UI polish"): give it Task 11 (update + settings/about) and Task 14 (installer), which touch disjoint files.

## Clock (agent wall-clock, CI included)

| Task | Window | CI | Notes |
| --- | --- | --- | --- |
| 1 Workspace, promote spike, CI | 0:00–0:50 | yes | first cold CI ~25 min |
| 2 Model: palette, strings, keys, paste | 0:20–0:55 | no | during Task 1 CI wait |
| 3 Model: split tree + tabs | 0:55–1:35 | no | |
| 4 Model: sidebar, remote state, update, core envelope | 1:35–2:20 | no | G1 result arrives ~1:00–1:20 |
| 5 TermCore + PtyLink + fonts + ANSI palette | 1:00–1:50 | yes | |
| 6 Remote client compiles on Windows + Linux e2e | 1:50–2:50 | yes | riskiest; early on purpose |
| 7 App shell: title bar, sidebar, icons | 2:50–3:45 | yes | |
| 8 Tabs + splits UI | 3:45–4:40 | yes | |
| 9 IME keep, selection, copy, bracketed paste, DPI | 4:40–5:35 | yes | |
| 10 shellx-core bridge, login, register, machines in sidebar | 5:35–6:35 | yes | needs L5 core (≈T+3) |
| 11 Update check + settings/about | 6:00–6:40 | yes | helper (L2) |
| 12 Pairing requester flow | 6:35–7:30 | yes | needs L4 API deployed (G2 ≈T+3:30) for a live run; fakes otherwise |
| 13 Remote Mac terminal view | 7:30–8:30 | yes | needs L5 bridge for G3 live run |
| 14 Installer | 6:40–7:30 | yes | helper (L2) |
| 15 README, a11y stopgap, G3 checklist, lane report | 8:30–9:00 | no | |
| buffer / fixes | 9:00–10:00 | | checkpoint 2 at T+10 |

Critical path (Tasks 1, 5, 6, 7, 8, 9, 10, 12, 13, 15) ≈ 8 h 50 min; model tasks run in CI waits; Tasks 11 and 14 go to the helper. Cut order if behind at checkpoint 2 (master): Task 13 first (Windows ships local-only MVP + login/pairing UI), then Task 12, then Task 11's settings panel (keep the update banner).

---

## File Structure

```
windows/
  Cargo.toml                    workspace (members below), [workspace.package] edition 2024, rust-version 1.91, license GPL-3.0-or-later
  Cargo.lock                    committed; CI builds with --locked
  README.md                     build/run, smoke flags, a11y stopgap, latency procedure (Task 15)
  shellx-model/                 pure Rust; deps: serde, serde_json only
    src/lib.rs                  re-exports
    src/palette.rs              §7.4 tokens, status pills, ANSI 16, terminal defaults
    src/strings.rs              Lang, Str keys, vi/en tables, fmt helpers
    src/keys.rs                 KeyIn -> KeyAction (app commands, copy/paste, chords, text)
    src/paste.rs                encode_paste (normalize newlines, strip markers, bracket)
    src/selection.rs            grid selection model (anchor/head, per-row spans, point->cell)
    src/layout.rs               split tree: split, close, focus by direction, rects
    src/tabs.rs                 tabs of layouts, pane ownership, local/remote targets
    src/sidebar.rs              MachineInfo -> MachineGroup rows (order, offline text, icons, access)
    src/remote_state.rs         pairing + connection state machine, backoff
    src/update.rs               version.check result -> UpdateStatus
    src/core_api.rs             CoreCall trait, envelope parser, typed K3 calls, FakeCore
  shellx-remote/                GPUI-free remote client (Task 6)
    src/lib.rs                  RemoteClient API used by the app
    tests/relay_e2e.rs          #[ignore] e2e vs real cmux-relay + cmux-tui daemon (Unix only)
    tests/support/mod.rs        spawns relay + daemon, mints tickets, approves enrollments
  shellx-app/
    Cargo.toml, build.rs        from the spike; bin name shellx-desktop
    resources/                  shellx.rc, shellx.manifest (from spike), app_icon.ico
    assets/icons/*.svg          the 20 coolicons + logo.svg
    assets/fonts/*.ttf          JetBrainsMono-{Regular,Bold,Italic,BoldItalic}.ttf, SpaceGrotesk-Bold.ttf, OFL texts
    src/main.rs                 flags: --smoke, --smoke-ui-assets; else app::run (windows)
    src/term_core.rs            TermCore (Terminal + RenderState + KeyEncoder) over a PtyLink
    src/local_pty.rs            ConPTY PtyLink (from spike session.rs)
    src/remote_link.rs          PtyLink over shellx-remote attachment (Task 13)
    src/core_bridge.rs          CoreCall impl over shellx_core (Task 10)
    src/smoke.rs                headless checks (spike smoke + new ones)
    src/ui/mod.rs               cfg(windows) UI root
    src/ui/app.rs               Application, assets, fonts, window, global services
    src/ui/theme.rs             palette -> gpui::Hsla, text styles
    src/ui/assets.rs            AssetSource over include_bytes! icons
    src/ui/root.rs              RootView: title bar + sidebar + main + overlays
    src/ui/titlebar.rs          custom title bar, window controls
    src/ui/sidebar.rs           renders shellx_model::sidebar groups
    src/ui/panes.rs             renders a tab's split tree of TermViews
    src/ui/term_view.rs         TermView + TermElement (spike app.rs, extended)
    src/ui/text_field.rs        single-line input (from gpui examples/input.rs)
    src/ui/login.rs             login panel
    src/ui/pairing.rs           request-access panel (code, waiting, result)
    src/ui/settings.rs          settings/about panel, update banner
  installer/
    shellx-native.iss           Inno Setup script (from shellx repo release/windows/shellx.iss, reduced)
    Vietnamese.isl              copied from shellx repo release/windows/Vietnamese.isl
    build-installer.ps1         from shellx repo release/windows/build-installer.ps1, adapted
.github/workflows/shellx-windows.yml
```

---
