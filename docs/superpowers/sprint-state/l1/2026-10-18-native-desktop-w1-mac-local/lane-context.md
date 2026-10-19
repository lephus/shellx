# Lane L1 context (read with your task brief)

Project: ShellX for Mac = a GPL fork of cmux (Swift/AppKit/SwiftUI). The cmux tree is at the root of the repo `lephus/shellx`.
Lane L1 (Mac identity) does W1 plan Tasks 2, 3, 4, 5, 5B on branch `shellx/l1-identity`. Task 1 is done: package
`Packages/Shared/ShellXBrand` (ShellXBrand identity constants, ShellXPalette, ShellXColor, ShellXFeatures.remoteMachines = false)
is already linked into the `cmux` app and `cmux-cli` targets. Read `Packages/Shared/ShellXBrand/Sources/ShellXBrand/*.swift` before using it.
Other lanes run in parallel: L2 does Tasks 6-9,11,12 (UI strings rebrand "cmux"→"ShellX", palette, icons, Vietnamese), L3 Task 10 (sidebar).

## Global constraints (verbatim from the plan)
- Identity: app `pro.shellx.desktop` (Release) / `pro.shellx.desktop.debug` (Debug), product name `ShellX` / `ShellX DEV`, Team ID `W4RF3W4VTZ`, URL scheme `shellx`, CLI command `shellx`, minimum macOS 14.0.
- Coexistence with cmux: ShellX must run at the same time as an installed cmux without sharing sockets, config, state, CLI name, hook markers, UTIs, URL scheme or keychain items.
- Names on disk: `~/.config/shellx/shellx.json` (and `dock.json`, `sidebars/` beside it), per-project `shellx.json` / `.shellx/shellx.json`, `~/.local/state/shellx`, `~/Library/Application Support/ShellX`, sockets `shellx.sock` / `shellx-<uid>.sock` / `/tmp/shellx-*.sock`, hook marker `"__shellx"`, UTI prefix `pro.shellx`. Ghostty config path `~/.config/ghostty/config` is unchanged and still read.
- Strings: every new user-visible string uses `String(localized: "<key>", defaultValue: "<English>")` and is added to the catalog with the repo's tooling (`skills/cmux-localization/SKILL.md`, `scripts/localize-changes`), so `python3 scripts/localization_catalog.py check` stays green.
- No outbound traffic to Manaflow, cmux.com/dev, Stack Auth, Sentry, PostHog, Axiom, coderouter or iroh relays.
- Tests: new Swift tests use Swift Testing (`import Testing`, `@Test`, `#expect`). After adding a file under `cmuxTests/`, run `scripts/sync-test-wiring`. Static guards are `tests/test_shellx_*.py`, registered in `tests/test-execution.toml` in the same lane as `test_localizable_xcstrings_structure.py` / `test_shellx_entitlements.py`.
- Internal identifiers (`CMUX_*` env vars, `Cmux*` types/modules, package names) are NOT renamed.
- Edits to upstream files are wiring only; ShellX-only code lives in `Packages/Shared/ShellXBrand` and `Sources/ShellX/`.
- No telemetry, no third-party services, no BUSL code, GPL-compatible deps.

## Controller rulings that bind you (full text: progress.md in this directory, "Lane L1")
- R1: the repo has NO pytest. Write guards as stdlib `unittest` files `tests/test_shellx_<name>.py` with `if __name__ == "__main__": unittest.main()`, run as `python3 tests/test_shellx_<name>.py`. Translate the plan's pytest snippets 1:1.
- R2: never run a local Xcode app build (`reload.sh`, `xcodebuild build`) — CI builds the app after the controller pushes. Fast local checks only: `swift test --package-path <pkg>`, `python3 tests/...`, `python3 scripts/verify-local.py --all --jobs 3`, `go test`. If you truly need xcodebuild, STOP and report NEEDS_CONTEXT.
- R3: replace `com.cmuxterm.*` where it names OUR app or reaches an OS-wide namespace another app could share (bundle-id comparisons/derivations, UserDefaults suites, keychain services, distributed notifications, Mach/XPC/launchd labels, pasteboard/UTI types, app group, on-disk paths). Leave in-process-only labels (DispatchQueue labels, in-process NotificationCenter names, os_log subsystems) and test fixtures that don't assert our identity.
- R5: app-hosted Swift suites under `cmuxTests/` are written and wired but run later on CI; put pure decision logic in `ShellXBrand` (or a package with `swift test`) wherever possible so it is tested now.
- R7: remote-daemon names (`cmuxd-remote`, `~/.cmux/daemon`, `/tmp/cmuxd-remote-*`, busybox argv0) belong to Task 5B.
- R8: edit `.xcstrings` catalogs only for keys you add; UI copy saying "cmux" is L2's Task 6.
- R9: in `Sources/App/About/AboutPanelView.swift` change only URL literals.
- Shared helper `tests/shellx_guard.py` (created in Task 2): `read(path) -> str`, `offenders(pattern, roots, allow) -> list["path:line"]`, `png_size(path)`, `sha256(path)`. Paths are relative to the repo root; make it work regardless of the cwd.

## Machine rules
- Work ONLY in your assigned worktree. Never touch /Applications/ShellX.app (a Flutter app with bundle id pro.shellx.desktop) or the user's cmux (com.cmuxterm.app). Never push. Never delete files you did not create outside the repo.
- Submodules (ghostty, vendor/bonsplit) are not checked out; don't init them unless a package test truly needs one.
- Commit in small steps on your branch with `git add <paths>` (not `-A` across unrelated files; `.superpowers/` is git-ignored). Commit messages: `feat(shellx): …`.

## Disk (binding, added 06:20)
- Disk is tight (~19 GB free; must stay ≥ 15 GB). After running `swift test --package-path X`, delete `X/.build` (`rm -rf X/.build`) before moving on. Never leave SwiftPM `.build` dirs behind. Don't copy big directories into the scratchpad.

## App-host suites and CI (Task L1-CI, done)
- `.github/workflows/shellx-mac-unit.yml` runs every `cmuxTests/ShellX*.swift` suite when a pushed head commit message contains `[unit]`. The suite name passed to xcodebuild is the FILE BASENAME, so each file `cmuxTests/ShellXFooTests.swift` must declare `struct ShellXFooTests` (no `@Suite("custom display name")`).
