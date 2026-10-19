## Global Constraints

- **Prerequisite:** Wave 0 Tasks 1–3 done (clone, `shellx.release.entitlements`, `scripts/shellx/sign-and-notarize.sh`, `scripts/shellx/perf/perf_mac.py`, baseline JSON in the ledger).
- **Identity:** app `pro.shellx.desktop` (Release) / `pro.shellx.desktop.debug` (Debug), product name `ShellX` / `ShellX DEV`, Team ID `W4RF3W4VTZ`, URL scheme `shellx`, CLI command `shellx`, minimum macOS 14.0.
- **Coexistence with cmux:** ShellX must run at the same time as an installed cmux without sharing sockets, config, state, CLI name, hook markers, UTIs, URL scheme or keychain items.
- **Names on disk:** `~/.config/shellx/shellx.json` (and `dock.json`, `sidebars/` beside it), per-project `shellx.json` / `.shellx/shellx.json`, `~/.local/state/shellx`, `~/Library/Application Support/ShellX`, sockets `shellx.sock` / `shellx-<uid>.sock` / `/tmp/shellx-*.sock`, hook marker `"__shellx"`, UTI prefix `pro.shellx`. Ghostty config path `~/.config/ghostty/config` is unchanged and still read.
- **Palette (spec §7.4, exact):** bg `#0b0716`, panel `#100b1d`, raise `#171128`, line `#211a37`, border `#2a2145`, text `#cdc7e0`, textHi `#e6e2f2`, muted `#8a83a6`, primary `#60a5fa`, primarySoft = primary α 0.12, primaryLine = primary α 0.45, primaryText `#93c5fd`, running `#e8c468`, done `#6fd49a`, error `#e88a8a`.
- **Status → color:** waiting-for-you = primary (+ ring), running = running, done = done, error = error, idle = no pill (muted).
- **No gradients, glows or colored shadows** on UI components; the logo is the only exception. Primary button = primarySoft fill + 1 px primaryLine border + primaryText; secondary = raise fill + border + text.
- **Dark appearance only** (C2).
- **Icons:** coolicons v4.1 only (CC BY 4.0, credit "coolicons by Kryston Schwarze"). SF Symbols remain only as the fallback for symbol names that come from user configuration.
- **Strings:** every new user-visible string uses `String(localized: "<key>", defaultValue: "<English>")` and is added to the catalog with the repo's tooling (`skills/cmux-localization/SKILL.md`, `scripts/localize-changes`), so `python3 scripts/localization_catalog.py check` stays green. After Task 12 that includes `vi`.
- **No outbound traffic** to Manaflow, cmux.com/dev, Stack Auth, Sentry, PostHog, Axiom, coderouter or iroh relays (spec §4, §9, C6).
- **Tests:** new Swift tests use Swift Testing (`import Testing`, `@Test`, `#expect`). After adding a file under `cmuxTests/`, run `scripts/sync-test-wiring`. App-host tests run through `scripts/shellx/test-app.sh <Suite>` (Task 1). Static guards are `tests/test_shellx_*.py`, registered in `tests/test-execution.toml` in the same lane as `test_localizable_xcstrings_structure.py`.
- **Builds:** only through `./scripts/reload.sh --tag <tag>`; never a bare `xcodebuild` app build; never touch a running `com.cmuxterm.app`.
- **Git:** commit after every task on `shellx/w1-mac-local`; merge into the fork's `main` locally at the end; never push without asking.

## Review Focus

1. **cmux and ShellX installed together.** Both apps open at once; `cmux` CLI talks to cmux and `shellx` CLI to ShellX; hooks installed by one don't overwrite the other's. Test added to Task 3 (static guard + manual side-by-side check).
2. **The user's Ghostty theme must still win.** ShellX's default terminal colors apply only when the user has no theme/colors in their Ghostty config. Test added to Task 7.
3. **Icon names from user config.** Custom commands, workspace groups and `sidebar.compactStatusIcons` may name arbitrary SF Symbols; they must still render (fallback), never crash or show blank. Test added to Task 8.
4. **SSH hosts that drop or reconnect.** A host whose connection is lost keeps its section with an offline header and its rows; two different `user@host` targets are two machines. Tests added to Task 10.
5. **Long Vietnamese text.** Vietnamese labels are longer than English; machine names can be long. Rows and headers must keep a fixed height and truncate with an ellipsis instead of growing or clipping. Tests added to Task 10.

---
