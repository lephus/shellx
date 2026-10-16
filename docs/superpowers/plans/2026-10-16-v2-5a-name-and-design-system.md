# ShellX V2-5a — The app's full display name and the new design system Implementation Plan

Status: complete — tasks 1–4 written in full (code verified by runs); tasks 5–16 written on 2026-10-16 ~16:45 at a compact level (files, interfaces, exact values, tests, commands; full code only for native, security and tricky logic), at the user's request to finish all V2-5 plans within about an hour. Implementers write the remaining code from the spec; reviewers check against the spec.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Everywhere the OS or the app shows the app's name it reads "ShellX: Remote AI agents" while every identifier stays "ShellX", and both apps take one shared design system (`packages/shellx_design`): navy neumorphism with a cyan → indigo gradient that passes WCAG, the system's SF Mono on iPhone and Mac (never bundled) and JetBrains Mono elsewhere, Cupertino icons through one role table, without slowing a list.

**Architecture:**
- **Package `packages/shellx_design`** (first Flutter package in `packages/`, `resolution: workspace`): `ShellxPalette`/`ShellxLightPalette`, `ShellxGradients`, `ShellxRadii`, `ShellxSpacing`, `ShellxElevation`, `ShellxDurations`/`ShellxCurves`, `ShellxTerminalPalette`, `ShellxFonts`, `ShellxTypeScale`, `shellxWeight`, `ShellxSystemFont`, `ShellxIcons`, contrast helpers, `registerShellxDesignLicenses()`, and the shared widgets (`ShellxInsetBox`, `ShellxWedge`, `ShellxGlass`, `ShellxSlantBorder`, `shellxGradientLayer`). No font file, no xterm.
- **Adapters, call sites unchanged (A16).** Desktop: the `static const` classes of `ui/theme` keep their names and point at the package (`ShellxText` becomes getters so the Windows boost of A36 can work). Phone: `AppColors`/`AppTypography`/`ThemeDataFactory` keep their roles with new values. Each app themes every Material component (A39).
- **SF Mono (A31–A33).** A runner method (`SystemMonoFont.swift`, macOS and iOS) rebuilds the system monospaced font in memory as an sfnt from `CTFontCopyTable` and Dart registers it with `FontLoader('SF Mono')` before `runApp`; on failure nothing is registered and `fontFamilyFallback` gives JetBrains Mono. Every style sets `fontWeight` and the `wght` axis together (`shellxWeight`).
- **Names (§4).** Only display keys change (ARB `appTitle`, `trayTooltip`, `settingsVersion`, iOS `CFBundleDisplayName`, Android `android:label`, macOS `InfoPlist.strings`, Windows `FileDescription`, window titles, three Inno lines); identities are pinned by tests.

**Tech Stack:** Dart 3.11.1 / Flutter 3.41.4 (`~/fvm/versions/3.41.4/bin`, not on PATH); `cupertino_icons` 1.0.9 (exact); CoreText (Swift) in both runners; `flutter_test` (`paints` matcher), `integration_test` (spike only), `package:flutter_secure_storage` 10.3.4 (Task 2); Riverpod on desktop; signals + get_it + injectable + auto_route + intl_utils + flutter_gen on mobile (generated code is committed).

**Spec:** `docs/superpowers/specs/2026-10-16-v2-5a-name-and-design-system-design.md` (binding, Vietnamese; decisions A1–A50, §4 names, §5 tokens, §6 type and SF Mono, §7 components and `ShellxIcons`, §8 screens, §9 strings, §10 tests, §11 Review Focus, §12 manual checks). Consumers that A's names must serve: V2-5b §4.0 and T48 (icon roles; B adds `newSession`, `folder`, `branch`… to `ShellxIcons`), V2-5c §4.8 (the eight `voice*` roles A declares) and C4/C5 (`ShellxGlass blur: false` on the transcript, `ShellxWedge` and the accent gradient in the full-screen overlay, `ShellxSegmented` for VI│EN). Research: `SCRATCH/v25-research/design-system-and-naming.md`; approved proposal with its 11:25 UPDATE: `SCRATCH/v25-research/approved-proposal.md` (`SCRATCH` = `/private/tmp/claude-501/-Users-richard-Documents-helper-shellx/c68aea52-eaaf-4b45-9a7d-989a8fedf901/scratchpad`).

## Prerequisite and how this plan was made

Work in the worktree `/Users/richard/Documents/helper/shellx/.claude/worktrees/v2-5a` on branch `v2-5a`, made from `shellx-v2` **after** V2-2b, V2-3 and V2-4 are merged into it. **Never push:** a push to `main` starts a desktop release; the controller merges and pushes.

**Code read (2026-10-16):** `shellx-v2` `3f0adcc`, `v2-2b` `875feea`, `v2-3` `73b9bdf`, `v2-4` `1b378da` (the spec read `eb0b6dc`/`fd48288`/`bfff4c0`/`e3ca11f`; the branches moved since — symbol anchors below, not line numbers). The plan was written against the **union** of the four trees, built in a private scratch repo (`git merge-tree` of the three branches into `shellx-v2`).

**Where two branches both change a file the plan edits (expect the integrator's resolution, put A's lines next to it):**
- `apps/mobile/lib/features/terminal/presentation/widgets/session_picker.dart` — v2-2b (`aiOnly`, B21/B22) and v2-4 (the Tool group, E15) conflict around the groups; A only changes the sheet's colours/shape (A39), the `AppButton` prefix icon colour (A22) and icons.
- `apps/mobile/lib/l10n/intl_en.arb`, `intl_vi.arb` and the generated `lib/shared/src/{l10n,intl/messages_en,intl/messages_vi}.dart` — both add keys at the end; A edits `appTitle`, `settingsVersion` and adds `licensesLegalese` (anchor on the key names, regenerate).
- `apps/mobile/lib/core/router/app_router.dart` (+ `.gr.dart`), `lib/core/dependency/dependency.config.dart` — both add entries; A does not touch them (regenerate only if a task says so).
- `apps/desktop/lib/src/ui/ai/ai_images.dart` — v2-2b and v2-3 conflict on imports; A only changes icons there (Task 8).
- `packages/shellx_agent/lib/src/session/session_router.dart`, `packages/shellx_client/test/support/harness.dart` — not A's files.
- Semantic, not textual: v2-2b's `ai_chooser.dart` switch over `SessionChoice?` misses v2-4's `OpenTool()` (the analyzer reports `non_exhaustive_switch_statement`); the integrator adds the case. Not A's.

**How this plan was checked.** Tasks 1–4 were written and run in that scratch union (conflicts resolved there by taking both sides; generated mobile code regenerated). Baseline before A: `apps/desktop` 3921 tests pass, 10 skipped, analyze clean; `apps/mobile` 1614 pass, analyze shows only the pre-existing `unnecessary_import` info in `test/features/terminal/ime_in_place_edit_test.dart`. Results with Tasks 1–4 applied:
- `packages/shellx_design`: 62 tests pass, analyze clean.
- `apps/desktop`: 3924 pass (3 new, Task 2), 10 skipped, analyze clean.
- SF Mono spike, **macOS** (isolated build of Task 1, bundle id `pro.shellx.desktop.itest`, temporary HOME): `regular=223892 italic=200956 ms=38 missing=0 status=true width=618.2 jetbrains=600.0 ink=763787<913995<1209917<1354620 italicDiffers=true added=0` → all five criteria pass.
- SF Mono spike, **iOS simulator** (iPhone 17 Pro, iOS 26): `regular=223892 italic=200956 ms=12 missing=0 status=true width=618.2 jetbrains=600.0 ink=551574<703428<1002506<1146466 italicDiffers=true added=0` → all five pass.
- The system's SF Mono (`.SF NS Mono`) has two axes, `Weight` and a private `YAXS`, both 294.673–900, default 294.673. AppKit's named weights move both (Regular: `wght` 400, `YAXS` 324.3; Bold: `wght` 683.3, `YAXS` 335.8). See R4.

Timing-sensitive pre-existing test: `packages/shellx_core/test/util/terminal_links_test.dart` "path performance" can fail on a busy machine; rerun it alone before suspecting a change.

## Rulings (each with "cost if wrong")

Task 1 copies these into the ledger `docs/superpowers/ledgers/v2-5a.md`.

- **R1 — Keychain service from the running bundle id (controller's binding ruling, 2026-10-16).** The desktop secure store used a fixed Keychain service `pro.shellx.desktop` (`SecureKeyValueStore.defaultStorage`, flutter_secure_storage's `MacOsOptions.accountName`, which is `kSecAttrService`), so any isolated test build that runs the app's `main()` read the real app's items. Task 2 (⚠, opus) makes the service the running bundle id (`PackageInfo.packageName` = `NSBundle.mainBundle.bundleIdentifier`): exactly `pro.shellx.desktop` for the released app (existing users keep their items), the bundle id itself for any other (`pro.shellx.desktop.itest`, `.smoketest`), `pro.shellx.desktop.unknown` for an empty id; unit tests pin both cases and that both processes pass `info.packageName`. **The SF Mono spike never runs the app's `main()`** (its own integration-test entrypoint: the font channel only — no secure store, relay or settings; the iOS harness likewise). **No V2-5a task launches the full desktop app before Task 2 is done;** a full launch (Task 16 only) also calls the relay's public `GET /v1/version` (read-only). *Cost if wrong:* a test build sees no sign-in (by design).
- **R2 — `ShellxElevation` exposes every list twice:** as the fields of `ShellxElevation.dark`/`.light` (the spec's API) and as `static const` lists (`darkFloat1`, `darkRaisedSmall`…), because a field of a const object is not a constant expression and the desktop's `ShellxShadows.e1` must stay `static const`. Also `float1Elevation` 8 and `float1ShadowColor` `#73000000` (the desktop's `e1Elevation`/`e1ShadowColor`, so the adapter holds no hex). *Cost if wrong:* two names for one list.
- **R3 — `ShellxText` becomes getters** (`static TextStyle get body => ShellxTypeScale.desktopFor(ShellxTypeScale.desktopBody, defaultTargetPlatform)`), so A36's `ShellxTypeScale.desktopWindowsBoost` really applies to Windows only. Checked: no `ShellxText` use in `lib/` or `test/` is in a const context (analyze clean with getters). *Cost if wrong:* a later `const` use of `ShellxText.x` fails to compile (use `ShellxTypeScale.desktopX`).
- **R4 — only `wght` is set, `YAXS` stays at its default.** The spec sets `FontVariation('wght', n)` (A35); the system also moves a private `YAXS` axis with weight. The spike passes with `wght` alone. *Cost if wrong:* ShellX's SF Mono may look a hair lighter than Xcode's at the same weight; add `FontVariation('YAXS', …)` in `shellxWeight` (one function).
- **R5 — theme text styles carry `wght` too (`shellxWeightedTextTheme`).** The spec says every style sets both (A35) but not how text that only takes a theme style is drawn; without the axis, a plain `Text`, a Material label or a markdown `strong` (flutter_markdown merges `fontWeight: bold` over a style that carries `wght` 400) would be drawn at SF Mono's default 295 (Light) or at the wrong weight. Both adapters pass their `textTheme`/`primaryTextTheme` through `shellxWeightedTextTheme`, and markdown style sheets set `strong`/headings through `shellxWeight` (Tasks 11, 12). *Cost if wrong:* none known (static fonts ignore the axis).
- **R6 — per-platform spike switches.** Besides `ShellxSystemFont.enabled` (A32), `enabledOnMacOS` and `enabledOnIOS` (both `true` after the spike passed on both): a spike failure on one platform flips that constant only and the platform runs on JetBrains Mono. Disabled → `fallback(unsupported)`, without a log line (as Android/Windows). *Cost if wrong:* none.
- **R7 — `ShellxFontStatus.toString()` is `ShellxFontStatus(…)`** (the global "`Name(…)`" rule); the only log line is `ShellX: SF Mono not loaded (<reason>)`. *Cost if wrong:* none.
- **R8 — the coverage check runs on the upright and the italic** and reports the union in `missing` (§6.3 names the font, §6.4 shows both files at 134 + 5). *Cost if wrong:* none (both cover all).
- **R9 — the spike's "no new file" criterion looks at the whole temporary HOME on macOS** (the recipe's isolation; the app is not sandboxed) and at the app container on iOS (`Directory.systemTemp.parent`). *Cost if wrong:* a write outside HOME would be missed; the loader has no file API at all.
- **R10 — `minContrastOnGradient` takes an optional `overlay`** (the hover/pressed shades) so §10.1's "cùng hai gradient khi phủ đen 8 % và 16 % vẫn đạt" is one call; `ShellxGradients.hoverShade` `#14000000` and `pressedShade` `#29000000` hold the two shades (§5.5). *Cost if wrong:* none.
- **R11 — `ShellxDurations.toastVisiblePhone` = 3 s** next to `toastVisible` 4 s / `toastVisibleError` 6 s (§5.8 "toast hiện 4 s, lỗi 6 s (DT), 3 s (ĐT)"). *Cost if wrong:* none.
- **R12 — mobile line heights are written as `oldSize * oldHeight / newSize`** (e.g. `paragraph`: `14 * 1.57 / 13`), so the px line height is exactly the old one (§6.5 rounds: 21.98 is shown as 22). *Cost if wrong:* none.
- **R13 — `fontWeight:` in `lib/src/config/shellx_config.dart` stays.** It is the `ShellxConfig(fontWeight: …)` argument (the terminal's `font-weight` setting, a `TerminalFontWeight`), not a style; the desktop guard baseline keeps that one entry (§10.4 says `fontWeight:` 0 "after A" for styles). Likewise the guard keeps the config parsers' `Color(0x` (`config/config_color.dart`, the user's hex colours) and the probe's `TextStyle(` (`config/font_probe.dart`), and the file viewer's `fontFamily:` (re_editor needs a family: `ShellxFonts.uiFamily`). *Cost if wrong:* four baseline entries.
- **R14 — package tests run with `flutter test` in `packages/shellx_design`** (Global Constraints, every task's checks and Task 16). The only CI that runs package tests (`.github/workflows/windows-check.yml`) is outside A's files (spec header): adding the package there is a follow-up. *Cost if wrong:* CI does not run the package's tests until then.
- **R15 — the spike's macOS run uses a throw-away worktree of `HEAD`** (V2-3's Task 6 recipe), so Task 1 commits its code first and records the results in a second commit. *Cost if wrong:* none.
- **R16 — the mobile app gets `integration_test` as a dev dependency** (the spike's simulator run); `pod install` adds its lines to `ios/Podfile.lock`, which are committed with `COCOAPODS: 1.16.2` kept. *Cost if wrong:* none (dev dependency plugins stay out of release builds).


**Rulings added 2026-10-16 ~16:45 (compact completion of Tasks 5–16):**

- **R17 — a user `font-family` for the terminal gets no weights and no SF Mono in its fallback.** When the config names a family (`families` not empty), `desktopTerminalStyle` leaves `normalWeight`/`boldWeight` null (no `wght` axis) and builds the fallback as today: `[...families.skip(1), bundled JetBrains Mono (Light or Regular), ...xterm's]` — **never** `'SF Mono'`. The SF Mono default with `wght` 300/400/700 applies only when no family is named (macOS). *Why:* today's contract (`terminal_style.dart` doc: "a named family is drawn as the system has it"); a `wght` on a user's variable font would override the instance they chose, and an unweighted SF Mono in the fallback would draw missing glyphs at its default 295 (Light). JetBrains Mono is static, so it needs no axis. Same rule on iOS has no case (the phone has no user family). *Cost if wrong:* a user who names a variable font sees its default instance, as today; to weight it, set the two fields in the user branch too (one line).
- **R18 — the fourth `SegmentedButton` also becomes `ShellxSegmented`.** A40 counts three (`settings_page.dart`, `voice_composer.dart`, desktop `ai_changes_panel.dart`); the union has a fourth, `SegmentedButton<bool>` in `apps/mobile/lib/features/ai/presentation/widgets/ai_changes_sheet.dart` (V2-2b's phone mirror of the desktop panel). Task 12 replaces it with `ShellxSegmented<bool>` (A49 allows component swaps in AI files); until then Task 6 keeps `ThemeDataFactory.segmentedButtonTheme`, token-coloured, and Task 12 deletes it once no `SegmentedButton` is left. *Cost if wrong:* one sheet keeps a Material segmented control in token colours.
- **R19 — the theme default (A26) is a pure function, written only when it decides.** `resolveInitialThemeMode({required SharedPreferences prefs, required AdaptiveThemeMode? saved})` in `apps/mobile/lib/core/platform/theme_default.dart`; key `shellx_theme_default` stores `AdaptiveThemeMode.name` (`'dark'`/`'system'`); an unknown stored string counts as absent. A saved `adaptive_theme` mode wins and nothing is written; a stored default is returned as is; otherwise fresh install (no `shellx_installed`) → `dark`, else `system`, and that result is written. `main.dart` reads it **before** DI (which sets `shellx_installed`). *Cost if wrong:* none.
- **R20 — `ShellxIconButton`'s gradient variant is its existing toggle flag.** `selected == true` draws the gradient (`ShellxGradients.accent`, white glyph, outside ring); `selected` false/null draws the flat or raised variant chosen by the new `variant` field. *Why:* §7.1 "gradient khi đang bật"; the flag already marks the "on" state for semantics. *Cost if wrong:* a toggled icon button looks louder than wanted; draw `accent` glyph instead (one branch).
- **R21 — both apps' new components share one API shape** (`ShellxSegmented<T>({segments, selected, onChanged})` with `ShellxSegment<T>(value, label, {icon})`, `ShellxChip`, `ShellxCard` with `ShellxCardVariant`), as two classes (one per app, spec §7: desktop `ui/components/`, phone `shared/src/`), so V2-5b/C code reads the same on both. *Cost if wrong:* none.
- **R22 — the raw-style guard counts raw text, comments included.** The counter is a regex over the file text (no parser); a comment that names `Icons.x` counts and is reworded. *Why:* deterministic, no analyzer dependency in a test. *Cost if wrong:* a doc comment needs rewording.

- **R30 — Android 12+ dark devices also get `values-night-v31/styles.xml`.** A48 names only `values-v31`. Android picks resources by qualifier precedence, and night mode outranks the API level. On a dark Android 12+ phone, `values-night/styles.xml` would therefore win over `values-v31`, and the system splash would lose `windowSplashScreenBackground`. So Task 14 writes both `values-v31` (Light parent) and `values-night-v31` (dark parent), each with `android:windowSplashScreenBackground` = `@color/shellx_page`. flutter_native_splash ships the same pair. *Cost if wrong:* one extra XML file.
- **R31 — The desktop "Licenses and credits…" button always shows.** It is not gated on the version: a test with no desktop services has no version line but still has the button. It is a `TextButton` keyed `settings.licenses`, placed right after the version line (or where that line would be), and it takes the theme's `link` style. `applicationVersion` is passed only when the version is known. *Cost if wrong:* none.
- **R32 — No identity test reads `release/`.** A10 adds no test to `release/tests`. Task 13's `identity_pins_test.dart` reads only `apps/desktop` files. Task 15 instead checks that the diff of `shellx.iss` is exactly its three lines, and that the kept identity lines are byte-equal to before (a `grep` step). *Cost if wrong:* a later rename of an Inno shortcut or folder is not caught by a test. A follow-up could add one to `release/tests` with the teammate's consent.
- **R33 — One home for the desktop §10.5 checks: `apps/desktop/test/ui/design_budget_test.dart`.** Task 9's outline also mentions the 30-tab sidebar count. If Task 9 already created that test, Task 11 keeps it where it is and adds its own checks to the same file, never a second copy. The ≤ 2 bound must hold once Task 11 makes the selected row a raised tile. *Cost if wrong:* none.
- **R34 — There are 9 `showModalBottomSheet` calls, not 8.** The integrated tree has 9 (spec A39 says 8). The extra one is V2-2b's `ai_new_session_sheet.dart`. All 9 lose their own `backgroundColor`/`shape`, and a source-scan test pins this for every present and future call. Likewise the desktop has 7 `AlertDialog(` users, not 6. All 7 follow `dialogTheme`. `browser/engines/wk_webview_engine.dart`'s `setOnJavaScriptAlertDialog` is not a Material dialog and is left alone. *Cost if wrong:* none.
- **R35 — The full-app smoke launch (Task 16) ends with a leftover check.** After stopping the app by its PID:
  - `pgrep -f "$SCRATCH"` must be empty. Any process still running from the scratch path is one this recipe started, and is stopped by its own PID.
  - `launchctl print gui/$(id -u) | grep -c 'pro.shellx.desktop.smoketest'` must be 0. Otherwise `launchctl bootout gui/$(id -u)/<that label>` removes only that label.

  Why: the app may start a background service or a login item, and those live in the user's real launchd domain even with a temporary HOME. *Cost if wrong:* a stray `.smoketest` job until the next logout.

- **R18 (from the Tasks 5–10 writer) — applied in Task 12.** The phone's `features/ai/presentation/widgets/ai_changes_sheet.dart` has a fourth `SegmentedButton<bool>` that A40 did not count: "Lượt này" (`true`) vs "Cả phiên" (`false`), in the column keyed `ai.changes.sheet`. Task 12 replaces it with `ShellxSegmented<bool>`, which Task 10 introduces with the desktop's API. The keys `ai.changes.turn`/`ai.changes.session` stay on the segment labels, and the "Lượt này" segment stays disabled while there is no turn. A test pins it (Task 12). *Cost if wrong:* none; it is one Material segmented control fewer.

---

## Global Constraints

- **Branch and scope:**
  - Worktree `.claude/worktrees/v2-5a`, branch `v2-5a` (from the integrated `shellx-v2`); commit there, **never push, merge or force**.
  - A may change (spec header): new `packages/shellx_design`; root `pubspec.yaml` (`workspace:`); `apps/desktop`, `apps/mobile` (theme, components, the screens of §8, names of §4, the native SF Mono loaders of §6.3); `third_party/xterm` (only `TerminalStyle`'s weight fields, §6.8); `release/windows/shellx.iss` **only its three display lines** (A10, a teammate's file). **Never:** `web/**`, `relay/**`, the rest of `release/**`, `.github/**`, `term/**`, the AI screens' layout (V2-5b), the voice UI (V2-5c), protocols.
- **Tooling:**
  - Flutter only via `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter …`; Dart via `~/fvm/versions/3.41.4/bin/dart` (Flutter 3.41.4 / Dart 3.11.1). After a `pubspec.yaml` change: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get` at the repo root.
  - `pubspec.lock` files are git-ignored and never added.
  - After a macOS desktop build in the worktree, revert only the `COCOAPODS:` line of `apps/desktop/macos/Podfile.lock`.
  - The mobile iOS `Podfile.lock` keeps `COCOAPODS: 1.16.2`; new pod lines are committed.
  - Mobile generated code: `PATH=~/fvm/versions/3.41.4/bin:$PATH dart run intl_utils:generate` then `PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/shared/src/l10n.dart lib/shared/src/intl/messages_en.dart lib/shared/src/intl/messages_vi.dart`; routes, DI, `fonts.gen.dart`, `assets.gen.dart`: `PATH=~/fvm/versions/3.41.4/bin:$PATH dart run build_runner build --delete-conflicting-outputs` in `apps/mobile`. Desktop strings: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n` in `apps/desktop`. Generated files are committed.
  - Format only the files a task touches (`dart format <files>`; mobile page width 120 from its `analysis_options.yaml`, everything else 80).
- **Every task that changes code ends green:** each touched package's analyze clean and tests passing, run from its directory:
  - `packages/shellx_design`, `apps/desktop`, `apps/mobile`: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze` and `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test` (the mobile analyze may show only the pre-existing info above);
  - `third_party/xterm` has no tests: the two apps' suites cover it.
- **Exact values come from the spec** (hex, sizes, roles, glyphs, strings, copied verbatim in the tasks). Product naming: "Claude" or "Claude Agent", never "Claude Code", in UI strings. Vietnamese strings are the spec's, word for word.
- **Security and privacy:** ShellX never reads, stores or relays credentials; never `--hide-claude-auth`; no `SHELLX_*` variable in an agent's environment; never auto-allow a permission request, never re-apply a remembered no-approval mode. No content in logs (the font loader logs only its reason). `toString()` of every new record returns `Name(…)`, pinned by a test.
- **SF Mono licence (A32, §6.2):** never bundled, never written to disk, cached, sent or logged; no SF Mono file anywhere in the repo or in a `fonts:` declaration (`no_bundled_sf_test.dart`); Android and Windows never ask for the family.
- **App launches:**
  - The desktop app is never launched on the user's real data. Any desktop launch or integration test uses the isolated recipe (Task 1 Step 9): a throw-away worktree, bundle id `pro.shellx.desktop.itest` (or `.smoketest`), a temporary `HOME` and `CFFIXED_USER_HOME`; from Task 2 on, such a build also has its own Keychain service (R1), so it never touches the real items. Never touch the `pro.shellx.desktop` preferences domain. **No full-app launch before Task 2 is done (R1).** Never `flutter test -d macos` or `flutter run` in the worktree.
  - iOS simulator runs of a test harness are allowed (boot your own simulator and shut it down after; leave simulators others booted alone). Real devices are manual checks for the user (§12).
- **Processes:** never `pkill`/`killall`; stop only processes you started, by PID.
- **Commits:** conventional messages (`feat(v2-design): …`, `test(v2-design): …`, `fix(v2-design): …`, `docs(v2-design): …`), at least one per task, each ending with the committing model's own trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` or `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. ⚠ tasks are done with opus.

## Review Focus

Spec §11, each pinned by tests in the task that owns the code.

1. **The long name leaks into an identity** (`ProductName`, `PRODUCT_NAME`, `BINARY_NAME`, `appName`, a shortcut, a bundle id): the Windows data folder moves, sign-in, shortcut and AUMID are lost. Pinned by: Task 13 `identity_pins_test.dart` and `platform_config_test.dart`; Task 2 pins the Keychain service of the released bundle id.
2. **SF Mono misused:** not really used (wrong family, loaded after the first frame, silently on JetBrains Mono), bundled/written/sent, or a wrong weight because the font is variable. Pinned by: Task 1 `system_font_test.dart` (fake channel and loader), `no_bundled_sf_test.dart`, the spike criteria 3–4 on macOS and iOS; Task 4 `fonts_test.dart` (`shellxWeight`, weighted text theme); Task 5/6 `main` loads before `runApp`; Task 7 guard (`fontWeight:` 0 outside adapters).
3. **Contrast:** small text on `accent` instead of `accentStrong`, secondary text on glass or the wedge, a link on a raised surface, hover lowering contrast, light mode. Pinned by: Task 3 `contrast_test.dart` (every pair of §5.3–§5.7, gradients with both shades, the glass rule); Task 9/10 component tests (`accentStrong` for desktop labels, `AppButton` switching to `accentStrong` below 15 px).
4. **A theme gap or a wrong role:** a Material widget coloured from the seed, a white toast in dark mode, `onPrimary` (navy ink) on the gradient, a new Material icon. Pinned by: Task 5 `theme_test.dart` (every component theme of A39), Task 6 `design_tokens_test.dart`, Task 7 raw-style guards, Task 8 `icons_test.dart` + guard `Icons.` 0, Task 10 toast test.
5. **Performance and overflow:** shadows or blur in list items; a monospaced UI overflowing (driver pill, buttons, bottom-bar labels at 1.3×, the brand header at 320 pt). Pinned by: Task 11/12 §10.5 tests (≤ 2 `BoxShadow` in a 30-tab sidebar, 0 in 8 machine rows and a 50-item AI timeline, no `BackdropFilter` outside `ShellxGlass`), Task 10 2× text tests, manual §12 items 7 and 11.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| Create `packages/shellx_design/{pubspec.yaml,analysis_options.yaml,lib/shellx_design.dart,lib/src/type_scale.dart,lib/src/system_font.dart}`, `test/{system_font,fonts,no_bundled_sf}_test.dart`; Modify root `pubspec.yaml` | package skeleton, families, the loader | 1 |
| Create `apps/desktop/macos/Runner/SystemMonoFont.swift`, `apps/mobile/ios/Runner/SystemMonoFont.swift`; Modify `MainFlutterWindow.swift`, `AppDelegate.swift` (iOS), both `project.pbxproj`, both apps' `pubspec.yaml`, `apps/mobile/ios/Podfile.lock` | the native loaders | 1 |
| Create `apps/{desktop,mobile}/integration_test/sf_mono_spike_test.dart`, `docs/superpowers/ledgers/v2-5a.md` | the spike, the ledger | 1 |
| Modify `apps/desktop/lib/src/platform/secure_key_value_store.dart`, `lib/src/agent/{agent_side,ui_services}.dart`, `lib/main.dart`, `lib/daemon_main.dart`, `test/platform/storage_test.dart`; Create `test/platform/keychain_service_test.dart` | Keychain service per bundle id (R1) | 2 |
| Create `packages/shellx_design/lib/src/{palette,gradients,radii,spacing,elevation,motion,terminal_palette,contrast}.dart`, `test/{palette,contrast}_test.dart` | tokens and contrast | 3 |
| Modify `packages/shellx_design/lib/src/type_scale.dart`; Create `lib/src/widgets/{inset_box,wedge,glass,slant_border,gradient_layer}.dart`, `test/widgets_test.dart`; Modify `test/fonts_test.dart` | type scale, weight, shared widgets | 4 |
| Tasks 5–16 | see their outlines | 5–16 |

---

### Task 1: ⚠ The SF Mono spike — the package skeleton, the font loader, both native runners, the spike on macOS and iOS

Spec §6.3 asks for the spike first, with five pass criteria on each Apple platform (bytes for the upright and the italic over 100 KB in ≤ 150 ms; a glyph for the 134 Vietnamese letters and 5 combining marks; 10 × "m" at 100 = 618 ± 2 px; ink rising with `wght` 300 < 400 < 600 < 700 and the italic differing; no new file in the app's folders). The code is the production loader: `ShellxSystemFont` in the new package, `SystemMonoFont.swift` in both runners. The spike's entrypoint **never runs the app's `main()`** (R1): it only calls the font channel and `ShellxSystemFont.load()`.

**Fallback if the spike fails (A33):** on a platform where any criterion fails, set that platform's switch to `false` (`ShellxSystemFont.enabledOnMacOS` or `enabledOnIOS`, R6), note the failing criterion and numbers in the ledger, and carry on: that platform runs on JetBrains Mono (the UI family stays "SF Mono" and `fontFamilyFallback: ['JetBrainsMono']` takes over because nothing registers the family). Never Menlo (88/134 Vietnamese letters).

**Files:**
- Create: `packages/shellx_design/pubspec.yaml`, `analysis_options.yaml`, `lib/shellx_design.dart`, `lib/src/type_scale.dart` (`ShellxFonts` only; Task 4 adds the scale), `lib/src/system_font.dart`
- Create: `packages/shellx_design/test/system_font_test.dart`, `test/fonts_test.dart`, `test/no_bundled_sf_test.dart`
- Modify: `pubspec.yaml` (root `workspace:`)
- Create: `apps/desktop/macos/Runner/SystemMonoFont.swift`; Modify: `apps/desktop/macos/Runner/MainFlutterWindow.swift` (`awakeFromNib`), `apps/desktop/macos/Runner.xcodeproj/project.pbxproj`, `apps/desktop/pubspec.yaml`
- Create: `apps/mobile/ios/Runner/SystemMonoFont.swift`; Modify: `apps/mobile/ios/Runner/AppDelegate.swift` (`didInitializeImplicitFlutterEngine`), `apps/mobile/ios/Runner.xcodeproj/project.pbxproj`, `apps/mobile/pubspec.yaml`, `apps/mobile/ios/Podfile.lock`
- Create: `apps/desktop/integration_test/sf_mono_spike_test.dart`, `apps/mobile/integration_test/sf_mono_spike_test.dart`
- Create: `docs/superpowers/ledgers/v2-5a.md`

**Interfaces:**
- Consumes: nothing.
- Produces (later tasks and V2-5b/C rely on these names):
  - `ShellxFonts.systemMono == 'SF Mono'`, `bundledMono == 'JetBrainsMono'`, `bundledMonoLight == 'JetBrainsMonoLight'`, `isApple(TargetPlatform) → bool`, `uiFamily(TargetPlatform) → String`, `uiFallback(TargetPlatform) → List<String>`.
  - `ShellxSystemFont.load({Duration timeout = ShellxSystemFont.timeout}) → Future<ShellxFontStatus>` (never throws; call once in each app's `main`, after `ensureInitialized`, before `runApp` — Tasks 5, 6); `ShellxSystemFont.enabled`, `enabledOnMacOS`, `enabledOnIOS` (`const bool`); `ShellxSystemFont.channel` (`MethodChannel('pro.shellx.design/system_font')`); `@visibleForTesting loadWith({required TargetPlatform platform, required bool enabled, Duration timeout, MethodChannel channel, ShellxFontRegistrar register, void Function(String) log})`.
  - `ShellxFontStatus` (`.loaded()`, `.fallback(ShellxFontFallbackReason)`, `isLoaded`, `reason`); `enum ShellxFontFallbackReason { unsupported, channel, timeout, coverage, loader }`; `typedef ShellxFontRegistrar = Future<void> Function(String family, List<Uint8List> fonts)`.
  - Native: channel `pro.shellx.design/system_font`, method `monospaced`, no arguments → `{'regular': Uint8List, 'italic': Uint8List?, 'missing': List<int>}` or the error `unavailable`.

- [ ] **Step 1: Create the package and add it to the workspace**

`packages/shellx_design/pubspec.yaml`:

````yaml
name: shellx_design
description: >-
  ShellX's shared design system (V2-5a): colours, gradients, radii, spacing,
  shadows, the type scale, motion, the terminal palette, the icon roles and
  the shared widgets, used by both apps. It never ships a font file.
version: 1.0.0
publish_to: none
resolution: workspace

environment:
  sdk: ^3.11.0
  flutter: ">=3.41.0"

dependencies:
  flutter:
    sdk: flutter
  # A45: the Cupertino icon font, pinned exactly. Both apps take it from here.
  cupertino_icons: 1.0.9

dev_dependencies:
  flutter_lints: ^6.0.0
  flutter_test:
    sdk: flutter
````

`packages/shellx_design/analysis_options.yaml`:

````yaml
include: package:flutter_lints/flutter.yaml
````

`packages/shellx_design/lib/shellx_design.dart` (Task 3 and Task 4 add exports):

````dart
/// ShellX's shared design system (V2-5a): tokens, type, icons and the shared
/// widgets. Both apps reach it through their own adapters (desktop
/// `ui/theme`, phone `core/design`).
library;

export 'src/system_font.dart';
export 'src/type_scale.dart';
````

Root `pubspec.yaml`, in `workspace:` after `packages/shellx_ai`:

````diff
diff --git a/pubspec.yaml b/pubspec.yaml
index ac5eb11..9b39ed5 100644
--- a/pubspec.yaml
+++ b/pubspec.yaml
@@ -9,6 +9,7 @@ workspace:
   - packages/shellx_e2e
   - packages/shellx_acp
   - packages/shellx_ai
+  - packages/shellx_design
   - apps/desktop
   - apps/mobile
 dev_dependencies:
````

- [ ] **Step 2: Write the failing tests**

`packages/shellx_design/test/system_font_test.dart` (fake channel through the test messenger, fake registrar):

````dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_design/shellx_design.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final regular = Uint8List.fromList(List.filled(16, 1));
  final italic = Uint8List.fromList(List.filled(16, 2));

  late List<MethodCall> calls;
  late List<(String, List<Uint8List>)> registered;
  late List<String> logs;

  void answer(Future<Object?> Function() reply) {
    messenger.setMockMethodCallHandler(ShellxSystemFont.channel, (call) {
      calls.add(call);
      return reply();
    });
  }

  Future<void> register(String family, List<Uint8List> fonts) async {
    registered.add((family, fonts));
  }

  Future<ShellxFontStatus> load({
    TargetPlatform platform = TargetPlatform.macOS,
    bool enabled = true,
    ShellxFontRegistrar? registrar,
  }) => ShellxSystemFont.loadWith(
    platform: platform,
    enabled: enabled,
    register: registrar ?? register,
    log: logs.add,
  );

  setUp(() {
    calls = [];
    registered = [];
    logs = [];
  });

  tearDown(
    () => messenger.setMockMethodCallHandler(ShellxSystemFont.channel, null),
  );

  test(
    'bytes: the loader gets "SF Mono" with the upright and the italic',
    () async {
      answer(
        () async => {'regular': regular, 'italic': italic, 'missing': <int>[]},
      );
      final status = await load();
      expect(status, const ShellxFontStatus.loaded());
      expect(status.isLoaded, isTrue);
      expect(calls.single.method, 'monospaced');
      expect(calls.single.arguments, isNull);
      expect(registered.single.$1, 'SF Mono');
      expect(registered.single.$2, [regular, italic]);
      expect(logs, isEmpty);
    },
  );

  test('no italic: the upright alone', () async {
    answer(() async => {'regular': regular, 'missing': <int>[]});
    expect(await load(), const ShellxFontStatus.loaded());
    expect(registered.single.$2, [regular]);
  });

  test('iOS asks the runner too', () async {
    answer(() async => {'regular': regular, 'missing': <int>[]});
    expect(
      await load(platform: TargetPlatform.iOS),
      const ShellxFontStatus.loaded(),
    );
    expect(calls, hasLength(1));
  });

  group('every failure registers nothing and falls back, without throwing', () {
    final cases =
        <String, (Future<Object?> Function(), ShellxFontFallbackReason)>{
          'an error': (
            () async => throw PlatformException(code: 'unavailable'),
            ShellxFontFallbackReason.channel,
          ),
          'null': (() async => null, ShellxFontFallbackReason.channel),
          'not a map': (() async => 'x', ShellxFontFallbackReason.channel),
          'no upright': (
            () async => {'italic': italic, 'missing': <int>[]},
            ShellxFontFallbackReason.channel,
          ),
          'empty upright': (
            () async => {'regular': Uint8List(0), 'missing': <int>[]},
            ShellxFontFallbackReason.channel,
          ),
          'no missing list': (
            () async => {'regular': regular},
            ShellxFontFallbackReason.channel,
          ),
          'a missing letter': (
            () async => {
              'regular': regular,
              'italic': italic,
              'missing': [0x1EA0],
            },
            ShellxFontFallbackReason.coverage,
          ),
          'over 500 ms': (
            () => Future<Object?>.delayed(
              const Duration(milliseconds: 700),
              () => {'regular': regular, 'missing': <int>[]},
            ),
            ShellxFontFallbackReason.timeout,
          ),
        };
    cases.forEach((name, c) {
      test(name, () async {
        answer(c.$1);
        final status = await load();
        expect(status, ShellxFontStatus.fallback(c.$2));
        expect(status.isLoaded, isFalse);
        expect(registered, isEmpty);
        expect(logs, ['ShellX: SF Mono not loaded (${c.$2.name})']);
      });
    });

    test('no runner (MissingPluginException)', () async {
      final status = await load();
      expect(
        status,
        const ShellxFontStatus.fallback(ShellxFontFallbackReason.channel),
      );
      expect(registered, isEmpty);
    });

    test('the engine refuses the bytes', () async {
      answer(() async => {'regular': regular, 'missing': <int>[]});
      final status = await load(
        registrar: (_, _) async => throw Exception('bad font'),
      );
      expect(
        status,
        const ShellxFontStatus.fallback(ShellxFontFallbackReason.loader),
      );
      expect(logs, ['ShellX: SF Mono not loaded (loader)']);
    });
  });

  test('Android, Windows, Linux: the runner is never asked', () async {
    answer(() async => {'regular': regular, 'missing': <int>[]});
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.fuchsia,
    ]) {
      expect(
        await load(platform: platform),
        const ShellxFontStatus.fallback(ShellxFontFallbackReason.unsupported),
      );
    }
    expect(calls, isEmpty);
    expect(registered, isEmpty);
    expect(logs, isEmpty);
  });

  test('switched off: the runner is never asked', () async {
    answer(() async => {'regular': regular, 'missing': <int>[]});
    expect(
      await load(enabled: false),
      const ShellxFontStatus.fallback(ShellxFontFallbackReason.unsupported),
    );
    expect(calls, isEmpty);
  });

  test('the switches default to on (A32)', () {
    expect(ShellxSystemFont.enabled, isTrue);
    expect(ShellxSystemFont.enabledOnMacOS, isTrue);
    expect(ShellxSystemFont.enabledOnIOS, isTrue);
    expect(ShellxSystemFont.timeout, const Duration(milliseconds: 500));
    expect(ShellxSystemFont.channel.name, 'pro.shellx.design/system_font');
  });

  test('toString carries no content', () {
    expect(const ShellxFontStatus.loaded().toString(), 'ShellxFontStatus(…)');
    expect(
      const ShellxFontStatus.fallback(
        ShellxFontFallbackReason.coverage,
      ).toString(),
      'ShellxFontStatus(…)',
    );
  });
}
````

`packages/shellx_design/test/fonts_test.dart` (Task 4 extends it):

````dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_design/shellx_design.dart';

void main() {
  test('families by platform (§6.1): SF Mono only on iOS and macOS', () {
    for (final p in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      expect(ShellxFonts.isApple(p), isTrue);
      expect(ShellxFonts.uiFamily(p), 'SF Mono');
      expect(ShellxFonts.uiFallback(p), ['JetBrainsMono']);
    }
    for (final p in [
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.fuchsia,
    ]) {
      expect(ShellxFonts.isApple(p), isFalse);
      expect(ShellxFonts.uiFamily(p), 'JetBrainsMono');
      expect(ShellxFonts.uiFallback(p), isEmpty);
    }
    expect(ShellxFonts.systemMono, 'SF Mono');
    expect(ShellxFonts.bundledMono, 'JetBrainsMono');
    expect(ShellxFonts.bundledMonoLight, 'JetBrainsMonoLight');
  });
}
````

`packages/shellx_design/test/no_bundled_sf_test.dart` (A32, Review Focus 2):

````dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// V2-5a A32, §6.2 rule 1: SF Mono is never in the repository and never
/// declared as a font. Runs from `packages/shellx_design`; the workspace
/// root is two levels up.
void main() {
  final root = Directory('../..').absolute;

  // Build output, dependencies, tools' caches and other worktrees: not the
  // repository's own files.
  const skipped = {
    '.git',
    '.dart_tool',
    '.claude',
    '.gradle',
    '.symlinks',
    'build',
    'ephemeral',
    'node_modules',
    'Pods',
    'target',
  };

  Iterable<File> files(Directory dir) sync* {
    for (final entity in dir.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (entity is Directory) {
        if (!skipped.contains(name)) yield* files(entity);
      } else if (entity is File) {
        yield entity;
      }
    }
  }

  test('the workspace root is the repository', () {
    expect(File('${root.path}/pubspec.yaml').existsSync(), isTrue);
    expect(Directory('${root.path}/apps/desktop').existsSync(), isTrue);
    expect(Directory('${root.path}/apps/mobile').existsSync(), isTrue);
  });

  test('no SF Mono file anywhere in the repository', () {
    final named = RegExp(r'SF-?Mono|SFNSMono', caseSensitive: false);
    final found = [
      for (final f in files(root))
        if (named.hasMatch(f.uri.pathSegments.last)) f.path,
    ];
    expect(found, isEmpty);
  });

  test('no pubspec declares an "SF Mono" font', () {
    final family = RegExp(
      r'''family:\s*["']?SF\s*Mono''',
      caseSensitive: false,
    );
    final pubspecs = [
      for (final f in files(root))
        if (f.uri.pathSegments.last == 'pubspec.yaml') f,
    ];
    expect(pubspecs.length, greaterThanOrEqualTo(10));
    final declaring = [
      for (final f in pubspecs)
        if (family.hasMatch(f.readAsStringSync())) f.path,
    ];
    expect(declaring, isEmpty);
  });
}
````

- [ ] **Step 3: Run them to see them fail**

````bash
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get
cd packages/shellx_design && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
````

Expected: compilation fails (`ShellxSystemFont`, `ShellxFonts` undefined); `no_bundled_sf_test.dart` alone would pass.

- [ ] **Step 4: Write the families and the loader**

`packages/shellx_design/lib/src/type_scale.dart` (this task: `ShellxFonts` only):

````dart
import 'package:flutter/foundation.dart';

/// V2-5a A31, §6.1: the font families by platform. SF Mono is the system's
/// own on iOS and macOS, loaded at run time ([ShellxSystemFont]) and never
/// bundled; JetBrains Mono ships in both apps and is used everywhere else,
/// and on iOS and macOS when SF Mono did not load.
abstract final class ShellxFonts {
  /// The family [ShellxSystemFont] registers the system's SF Mono under.
  static const String systemMono = 'SF Mono';

  /// Bundled by both apps (`assets/fonts/JetBrainsMono-*.ttf`).
  static const String bundledMono = 'JetBrainsMono';

  /// The desktop's Light cut as its own family (the terminal default).
  static const String bundledMonoLight = 'JetBrainsMonoLight';

  /// iOS and macOS: the platforms whose system font ShellX may display.
  static bool isApple(TargetPlatform platform) =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  /// The UI family of [platform]. A32: never "SF Mono" off Apple platforms,
  /// not even when the user installed it there.
  static String uiFamily(TargetPlatform platform) =>
      isApple(platform) ? systemMono : bundledMono;

  /// What the engine falls back to when [uiFamily] is not registered.
  static List<String> uiFallback(TargetPlatform platform) =>
      isApple(platform) ? const [bundledMono] : const [];
}
````

`packages/shellx_design/lib/src/system_font.dart`:

````dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'type_scale.dart';

/// Why [ShellxSystemFont.load] registered nothing (V2-5a §6.3).
enum ShellxFontFallbackReason {
  /// Not iOS or macOS, switched off ([ShellxSystemFont.enabled], a
  /// platform's switch, or `FORCE_BUNDLED_MONO` in a debug build).
  unsupported,

  /// The native side failed, is missing, or answered something unreadable.
  channel,

  /// No answer within the time limit.
  timeout,

  /// The system font lacks a Vietnamese letter or combining mark.
  coverage,

  /// The engine refused the bytes.
  loader,
}

/// What [ShellxSystemFont.load] did: SF Mono registered, or the app runs on
/// the bundled JetBrains Mono for [reason].
@immutable
final class ShellxFontStatus {
  const ShellxFontStatus.loaded() : reason = null;

  const ShellxFontStatus.fallback(ShellxFontFallbackReason this.reason);

  /// Null when SF Mono was registered.
  final ShellxFontFallbackReason? reason;

  bool get isLoaded => reason == null;

  @override
  bool operator ==(Object other) =>
      other is ShellxFontStatus && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'ShellxFontStatus(…)';
}

/// Registers the font files under a family (production: [FontLoader]).
typedef ShellxFontRegistrar =
    Future<void> Function(String family, List<Uint8List> fonts);

/// V2-5a §6.3: the system's SF Mono on iOS and macOS. Its real name is
/// hidden (`.SF NS Mono`), so the runner rebuilds it in memory from its
/// tables (`SystemMonoFont.swift`) and Dart registers the bytes as
/// [ShellxFonts.systemMono] before `runApp`.
///
/// A32: the bytes stay in this process's memory. Nothing is written,
/// cached, sent or logged; Android and Windows never ask for the family.
abstract final class ShellxSystemFont {
  /// A32: one switch that stops reading the system font everywhere.
  static const bool enabled = true;

  /// The spike's per-platform result (plan Task 1): false sends that
  /// platform to JetBrains Mono.
  static const bool enabledOnMacOS = true;
  static const bool enabledOnIOS = true;

  /// The runner's channel (`SystemMonoFont.swift` in both apps).
  static const MethodChannel channel = MethodChannel(
    'pro.shellx.design/system_font',
  );

  /// §6.3: how long `main` waits for the runner.
  static const Duration timeout = Duration(milliseconds: 500);

  /// Debug builds only: `--dart-define=FORCE_BUNDLED_MONO=true` tries the
  /// fallback; release builds ignore it.
  static const bool _forceBundled = bool.fromEnvironment('FORCE_BUNDLED_MONO');

  /// Called once by each app's `main`, after
  /// `WidgetsFlutterBinding.ensureInitialized()` and before `runApp`.
  /// Never throws.
  static Future<ShellxFontStatus> load({Duration timeout = timeout}) {
    final platform = defaultTargetPlatform;
    final on =
        enabled &&
        !(kDebugMode && _forceBundled) &&
        switch (platform) {
          TargetPlatform.macOS => enabledOnMacOS,
          TargetPlatform.iOS => enabledOnIOS,
          _ => false,
        };
    return loadWith(platform: platform, enabled: on, timeout: timeout);
  }

  /// [load] with its parts given (tests).
  @visibleForTesting
  static Future<ShellxFontStatus> loadWith({
    required TargetPlatform platform,
    required bool enabled,
    Duration timeout = timeout,
    MethodChannel channel = ShellxSystemFont.channel,
    ShellxFontRegistrar register = registerFonts,
    void Function(String message) log = _log,
  }) async {
    ShellxFontStatus fail(ShellxFontFallbackReason reason) {
      log('ShellX: SF Mono not loaded (${reason.name})');
      return ShellxFontStatus.fallback(reason);
    }

    if (!enabled || !ShellxFonts.isApple(platform)) {
      return const ShellxFontStatus.fallback(
        ShellxFontFallbackReason.unsupported,
      );
    }
    Object? answer;
    try {
      answer = await channel
          .invokeMethod<Object?>('monospaced')
          .timeout(timeout);
    } on TimeoutException {
      return fail(ShellxFontFallbackReason.timeout);
    } catch (_) {
      return fail(ShellxFontFallbackReason.channel);
    }
    if (answer is! Map) return fail(ShellxFontFallbackReason.channel);
    final regular = answer['regular'];
    final italic = answer['italic'];
    final missing = answer['missing'];
    if (regular is! Uint8List || regular.isEmpty || missing is! List) {
      return fail(ShellxFontFallbackReason.channel);
    }
    if (missing.isNotEmpty) return fail(ShellxFontFallbackReason.coverage);
    try {
      await register(ShellxFonts.systemMono, [
        regular,
        if (italic is Uint8List && italic.isNotEmpty) italic,
      ]);
    } catch (_) {
      return fail(ShellxFontFallbackReason.loader);
    }
    return const ShellxFontStatus.loaded();
  }

  /// Production [ShellxFontRegistrar]: one [FontLoader] for the family.
  static Future<void> registerFonts(String family, List<Uint8List> fonts) {
    final loader = FontLoader(family);
    for (final bytes in fonts) {
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    return loader.load();
  }

  static void _log(String message) => debugPrint(message);
}
````

- [ ] **Step 5: Run the package's checks**

````bash
cd packages/shellx_design && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
````

Expected: `No issues found!`; `+21: All tests passed!`.

- [ ] **Step 6: The macOS runner**

`apps/desktop/macos/Runner/SystemMonoFont.swift` (the `SystemMonoFontTables` part is shared word for word with iOS):

````swift
import AppKit
import CoreText
import FlutterMacOS

/// V2-5a §6.3: the system's monospaced font (SF Mono). Its real name (`.SF NS Mono`) is hidden, so
/// Flutter cannot ask for it: the font is rebuilt in memory as an sfnt from its own tables and handed
/// to Dart, which registers it as "SF Mono" before `runApp`.
///
/// A32: the bytes stay in memory. Nothing is written, cached, sent or logged. The window's engine only
/// (registered in `MainFlutterWindow.awakeFromNib`); the background service never asks.
enum SystemMonoFont {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "pro.shellx.design/system_font", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "monospaced" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) as CTFont
      DispatchQueue.global(qos: .userInitiated).async {
        let italic = CTFontCreateCopyWithSymbolicTraits(font, 13, nil, .traitItalic, .traitItalic)
        let answer = SystemMonoFontTables.answer(regular: font, italic: italic)
        DispatchQueue.main.async { result(answer) }
      }
    }
  }
}

/// The part both runners share, word for word (`apps/mobile/ios/Runner/SystemMonoFont.swift`).
enum SystemMonoFontTables {
  /// The 134 Vietnamese letters with marks (U+1EA0–U+1EF9 and the 44 in Latin-1 and Latin Extended-A
  /// and -B) and the five combining marks Vietnamese input methods produce.
  static let vietnamese: [UInt16] =
    Array(0x1EA0...0x1EF9)
    + [
      0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C8, 0x00C9, 0x00CA, 0x00CC, 0x00CD, 0x00D2, 0x00D3,
      0x00D4, 0x00D5, 0x00D9, 0x00DA, 0x00DD, 0x00E0, 0x00E1, 0x00E2, 0x00E3, 0x00E8, 0x00E9,
      0x00EA, 0x00EC, 0x00ED, 0x00F2, 0x00F3, 0x00F4, 0x00F5, 0x00F9, 0x00FA, 0x00FD, 0x0102,
      0x0103, 0x0110, 0x0111, 0x0128, 0x0129, 0x0168, 0x0169, 0x01A0, 0x01A1, 0x01AF, 0x01B0,
    ]
    + [0x0300, 0x0301, 0x0303, 0x0309, 0x0323]

  /// `{regular, italic?, missing}`, or the `unavailable` error.
  static func answer(regular: CTFont, italic: CTFont?) -> Any {
    guard let upright = sfnt(of: regular) else {
      return FlutterError(code: "unavailable", message: nil, details: nil)
    }
    var missing = Set(self.missing(in: regular))
    var reply: [String: Any] = ["regular": FlutterStandardTypedData(bytes: upright)]
    if let italic = italic, let slanted = sfnt(of: italic) {
      missing.formUnion(self.missing(in: italic))
      reply["italic"] = FlutterStandardTypedData(bytes: slanted)
    }
    reply["missing"] = missing.sorted()
    return reply
  }

  /// The code points of [vietnamese] that [font] has no glyph for.
  static func missing(in font: CTFont) -> [Int] {
    var missing: [Int] = []
    for unit in vietnamese {
      var character = unit
      var glyph: CGGlyph = 0
      if !CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) || glyph == 0 {
        missing.append(Int(unit))
      }
    }
    return missing
  }

  /// [font] as an sfnt file: its tables sorted by tag, each 4-byte aligned with its checksum;
  /// `head.checkSumAdjustment` left at 0. Nil when CoreText gives no tables.
  static func sfnt(of font: CTFont) -> Data? {
    guard let list = CTFontCopyAvailableTables(font, []) else { return nil }
    var tables: [(tag: UInt32, data: Data)] = []
    for index in 0..<CFArrayGetCount(list) {
      // The array holds the tags themselves, not CF objects (CTFont.h).
      let tag = UInt32(truncatingIfNeeded: UInt(bitPattern: CFArrayGetValueAtIndex(list, index)))
      if let table = CTFontCopyTable(font, tag, []) {
        tables.append((tag, table as Data))
      }
    }
    tables.sort { $0.tag < $1.tag }
    let tags = Set(tables.map { $0.tag })
    let version: UInt32
    if tags.contains(0x676C_7966) {  // 'glyf'
      version = 0x0001_0000
    } else if tags.contains(0x4346_4620) {  // 'CFF '
      version = 0x4F54_544F  // 'OTTO'
    } else {
      return nil
    }
    let count = tables.count
    var power = 1
    var log2 = 0
    while power * 2 <= count {
      power *= 2
      log2 += 1
    }
    var out = Data()
    out.appendBigEndian(version)
    out.appendBigEndian(UInt16(count))
    out.appendBigEndian(UInt16(power * 16))
    out.appendBigEndian(UInt16(log2))
    out.appendBigEndian(UInt16(count * 16 - power * 16))
    var records = Data()
    var body = Data()
    var offset = 12 + 16 * count
    for (tag, table) in tables {
      var bytes = Data(table)
      if tag == 0x6865_6164, bytes.count >= 12 {  // 'head': checkSumAdjustment = 0
        bytes.replaceSubrange(8..<12, with: [0, 0, 0, 0])
      }
      let length = bytes.count
      let padded = (length + 3) & ~3
      bytes.append(contentsOf: [UInt8](repeating: 0, count: padded - length))
      records.appendBigEndian(tag)
      records.appendBigEndian(checksum(bytes))
      records.appendBigEndian(UInt32(offset))
      records.appendBigEndian(UInt32(length))
      body.append(bytes)
      offset += padded
    }
    out.append(records)
    out.append(body)
    return out
  }

  /// The sfnt table checksum: the sum of the big-endian 32-bit words, wrapping.
  static func checksum(_ data: Data) -> UInt32 {
    var sum: UInt32 = 0
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      var index = 0
      while index + 3 < raw.count {
        let word =
          UInt32(raw[index]) << 24 | UInt32(raw[index + 1]) << 16 | UInt32(raw[index + 2]) << 8
          | UInt32(raw[index + 3])
        sum = sum &+ word
        index += 4
      }
    }
    return sum
  }
}

extension Data {
  fileprivate mutating func appendBigEndian(_ value: UInt32) {
    append(contentsOf: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
  }

  fileprivate mutating func appendBigEndian(_ value: UInt16) {
    append(contentsOf: [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
  }
}
````

Register it in `MainFlutterWindow.awakeFromNib`, after `AppChannel.register` (the UI path only; the daemon returns earlier):

````diff
diff --git a/apps/desktop/macos/Runner/MainFlutterWindow.swift b/apps/desktop/macos/Runner/MainFlutterWindow.swift
index ea0e375..3b70025 100644
--- a/apps/desktop/macos/Runner/MainFlutterWindow.swift
+++ b/apps/desktop/macos/Runner/MainFlutterWindow.swift
@@ -22,6 +22,8 @@ class MainFlutterWindow: NSWindow {
     LaunchAtLoginChannel.register(
       messenger: flutterViewController.engine.binaryMessenger)
     AppChannel.register(messenger: flutterViewController.engine.binaryMessenger)
+    // V2-5a §6.3: SF Mono for the window's engine only (the service never draws text).
+    SystemMonoFont.register(messenger: flutterViewController.engine.binaryMessenger)
     browserNative = BrowserNative(controller: flutterViewController)
 
     super.awakeFromNib()
````

Add the file to the Runner target (`apps/desktop/macos/Runner.xcodeproj/project.pbxproj`, four lines next to `BrowserNative.swift`; ids `5A5F0001…A001`/`5A5F0002…A001` are new):

````diff
diff --git a/apps/desktop/macos/Runner.xcodeproj/project.pbxproj b/apps/desktop/macos/Runner.xcodeproj/project.pbxproj
index ffd5192..bafcb97 100644
--- a/apps/desktop/macos/Runner.xcodeproj/project.pbxproj
+++ b/apps/desktop/macos/Runner.xcodeproj/project.pbxproj
@@ -24,6 +24,7 @@
 		331C80D8294CF71000263BE5 /* RunnerTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 331C80D7294CF71000263BE5 /* RunnerTests.swift */; };
 		335BBD1B22A9A15E00E9071D /* GeneratedPluginRegistrant.swift in Sources */ = {isa = PBXBuildFile; fileRef = 335BBD1A22A9A15E00E9071D /* GeneratedPluginRegistrant.swift */; };
 		A6B0000100000000000000A1 /* BrowserNative.swift in Sources */ = {isa = PBXBuildFile; fileRef = A6B0000200000000000000A2 /* BrowserNative.swift */; };
+		5A5F0001000000000000A001 /* SystemMonoFont.swift in Sources */ = {isa = PBXBuildFile; fileRef = 5A5F0002000000000000A001 /* SystemMonoFont.swift */; };
 		33CC10F12044A3C60003C045 /* AppDelegate.swift in Sources */ = {isa = PBXBuildFile; fileRef = 33CC10F02044A3C60003C045 /* AppDelegate.swift */; };
 		33CC10F32044A3C60003C045 /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = 33CC10F22044A3C60003C045 /* Assets.xcassets */; };
 		33CC10F62044A3C60003C045 /* MainMenu.xib in Resources */ = {isa = PBXBuildFile; fileRef = 33CC10F42044A3C60003C045 /* MainMenu.xib */; };
@@ -69,6 +70,7 @@
 		335BBD1A22A9A15E00E9071D /* GeneratedPluginRegistrant.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = GeneratedPluginRegistrant.swift; sourceTree = "<group>"; };
 		33CC10ED2044A3C60003C045 /* shellx_desktop.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = shellx_desktop.app; sourceTree = BUILT_PRODUCTS_DIR; };
 		A6B0000200000000000000A2 /* BrowserNative.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BrowserNative.swift; sourceTree = "<group>"; };
+		5A5F0002000000000000A001 /* SystemMonoFont.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SystemMonoFont.swift; sourceTree = "<group>"; };
 		33CC10F02044A3C60003C045 /* AppDelegate.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppDelegate.swift; sourceTree = "<group>"; };
 		33CC10F22044A3C60003C045 /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; name = Assets.xcassets; path = Runner/Assets.xcassets; sourceTree = "<group>"; };
 		33CC10F52044A3C60003C045 /* Base */ = {isa = PBXFileReference; lastKnownFileType = file.xib; name = Base; path = Base.lproj/MainMenu.xib; sourceTree = "<group>"; };
@@ -180,6 +182,7 @@
 				33CC10F02044A3C60003C045 /* AppDelegate.swift */,
 				A6B0000200000000000000A2 /* BrowserNative.swift */,
 				33CC11122044BFA00003C045 /* MainFlutterWindow.swift */,
+				5A5F0002000000000000A001 /* SystemMonoFont.swift */,
 				33E51913231747F40026EE4D /* DebugProfile.entitlements */,
 				33E51914231749380026EE4D /* Release.entitlements */,
 				33CC11242044D66E0003C045 /* Resources */,
@@ -463,6 +466,7 @@
 				33CC11132044BFA00003C045 /* MainFlutterWindow.swift in Sources */,
 				33CC10F12044A3C60003C045 /* AppDelegate.swift in Sources */,
 				A6B0000100000000000000A1 /* BrowserNative.swift in Sources */,
+				5A5F0001000000000000A001 /* SystemMonoFont.swift in Sources */,
 				335BBD1B22A9A15E00E9071D /* GeneratedPluginRegistrant.swift in Sources */,
 			);
 			runOnlyForDeploymentPostprocessing = 0;
````

`apps/desktop/pubspec.yaml`, in `dependencies:` after `shellx_core: any`:

````diff
diff --git a/apps/desktop/pubspec.yaml b/apps/desktop/pubspec.yaml
index 5c591ba..1d1082a 100644
--- a/apps/desktop/pubspec.yaml
+++ b/apps/desktop/pubspec.yaml
@@ -53,6 +53,8 @@ dependencies:
   shellx_agent: any
   shellx_ai: any
   shellx_core: any
+  # V2-5a: the shared design system (tokens, type, icons, widgets).
+  shellx_design: any
   tray_manager: ^0.5.3
   # V2-3 D6: WKWebView as a platform view on macOS (tools). Pinned exactly:
   # wkwebview 3.26+ needs Flutter 3.44 / Dart 3.12.
````

- [ ] **Step 7: The iOS runner**

`apps/mobile/ios/Runner/SystemMonoFont.swift` (UIKit entry point; `SystemMonoFontTables` identical to macOS):

````swift
import CoreText
import Flutter
import UIKit

/// V2-5a §6.3: the system's monospaced font (SF Mono). Its real name is hidden, so Flutter cannot ask
/// for it: the font is rebuilt in memory as an sfnt from its own tables and handed to Dart, which
/// registers it as "SF Mono" before `runApp`.
///
/// A32: the bytes stay in memory. Nothing is written, cached, sent or logged.
enum SystemMonoFont {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "pro.shellx.design/system_font", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "monospaced" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
      let italic = font.fontDescriptor.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: 13) as CTFont }
      DispatchQueue.global(qos: .userInitiated).async {
        let answer = SystemMonoFontTables.answer(regular: font as CTFont, italic: italic)
        DispatchQueue.main.async { result(answer) }
      }
    }
  }
}

/// The part both runners share, word for word (`apps/desktop/macos/Runner/SystemMonoFont.swift`).
enum SystemMonoFontTables {
  /// The 134 Vietnamese letters with marks (U+1EA0–U+1EF9 and the 44 in Latin-1 and Latin Extended-A
  /// and -B) and the five combining marks Vietnamese input methods produce.
  static let vietnamese: [UInt16] =
    Array(0x1EA0...0x1EF9)
    + [
      0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C8, 0x00C9, 0x00CA, 0x00CC, 0x00CD, 0x00D2, 0x00D3,
      0x00D4, 0x00D5, 0x00D9, 0x00DA, 0x00DD, 0x00E0, 0x00E1, 0x00E2, 0x00E3, 0x00E8, 0x00E9,
      0x00EA, 0x00EC, 0x00ED, 0x00F2, 0x00F3, 0x00F4, 0x00F5, 0x00F9, 0x00FA, 0x00FD, 0x0102,
      0x0103, 0x0110, 0x0111, 0x0128, 0x0129, 0x0168, 0x0169, 0x01A0, 0x01A1, 0x01AF, 0x01B0,
    ]
    + [0x0300, 0x0301, 0x0303, 0x0309, 0x0323]

  /// `{regular, italic?, missing}`, or the `unavailable` error.
  static func answer(regular: CTFont, italic: CTFont?) -> Any {
    guard let upright = sfnt(of: regular) else {
      return FlutterError(code: "unavailable", message: nil, details: nil)
    }
    var missing = Set(self.missing(in: regular))
    var reply: [String: Any] = ["regular": FlutterStandardTypedData(bytes: upright)]
    if let italic = italic, let slanted = sfnt(of: italic) {
      missing.formUnion(self.missing(in: italic))
      reply["italic"] = FlutterStandardTypedData(bytes: slanted)
    }
    reply["missing"] = missing.sorted()
    return reply
  }

  /// The code points of [vietnamese] that [font] has no glyph for.
  static func missing(in font: CTFont) -> [Int] {
    var missing: [Int] = []
    for unit in vietnamese {
      var character = unit
      var glyph: CGGlyph = 0
      if !CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) || glyph == 0 {
        missing.append(Int(unit))
      }
    }
    return missing
  }

  /// [font] as an sfnt file: its tables sorted by tag, each 4-byte aligned with its checksum;
  /// `head.checkSumAdjustment` left at 0. Nil when CoreText gives no tables.
  static func sfnt(of font: CTFont) -> Data? {
    guard let list = CTFontCopyAvailableTables(font, []) else { return nil }
    var tables: [(tag: UInt32, data: Data)] = []
    for index in 0..<CFArrayGetCount(list) {
      // The array holds the tags themselves, not CF objects (CTFont.h).
      let tag = UInt32(truncatingIfNeeded: UInt(bitPattern: CFArrayGetValueAtIndex(list, index)))
      if let table = CTFontCopyTable(font, tag, []) {
        tables.append((tag, table as Data))
      }
    }
    tables.sort { $0.tag < $1.tag }
    let tags = Set(tables.map { $0.tag })
    let version: UInt32
    if tags.contains(0x676C_7966) {  // 'glyf'
      version = 0x0001_0000
    } else if tags.contains(0x4346_4620) {  // 'CFF '
      version = 0x4F54_544F  // 'OTTO'
    } else {
      return nil
    }
    let count = tables.count
    var power = 1
    var log2 = 0
    while power * 2 <= count {
      power *= 2
      log2 += 1
    }
    var out = Data()
    out.appendBigEndian(version)
    out.appendBigEndian(UInt16(count))
    out.appendBigEndian(UInt16(power * 16))
    out.appendBigEndian(UInt16(log2))
    out.appendBigEndian(UInt16(count * 16 - power * 16))
    var records = Data()
    var body = Data()
    var offset = 12 + 16 * count
    for (tag, table) in tables {
      var bytes = Data(table)
      if tag == 0x6865_6164, bytes.count >= 12 {  // 'head': checkSumAdjustment = 0
        bytes.replaceSubrange(8..<12, with: [0, 0, 0, 0])
      }
      let length = bytes.count
      let padded = (length + 3) & ~3
      bytes.append(contentsOf: [UInt8](repeating: 0, count: padded - length))
      records.appendBigEndian(tag)
      records.appendBigEndian(checksum(bytes))
      records.appendBigEndian(UInt32(offset))
      records.appendBigEndian(UInt32(length))
      body.append(bytes)
      offset += padded
    }
    out.append(records)
    out.append(body)
    return out
  }

  /// The sfnt table checksum: the sum of the big-endian 32-bit words, wrapping.
  static func checksum(_ data: Data) -> UInt32 {
    var sum: UInt32 = 0
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      var index = 0
      while index + 3 < raw.count {
        let word =
          UInt32(raw[index]) << 24 | UInt32(raw[index + 1]) << 16 | UInt32(raw[index + 2]) << 8
          | UInt32(raw[index + 3])
        sum = sum &+ word
        index += 4
      }
    }
    return sum
  }
}

extension Data {
  fileprivate mutating func appendBigEndian(_ value: UInt32) {
    append(contentsOf: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
  }

  fileprivate mutating func appendBigEndian(_ value: UInt16) {
    append(contentsOf: [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
  }
}
````

Register it in `AppDelegate.didInitializeImplicitFlutterEngine`, after `GeneratedPluginRegistrant.register`:

````diff
diff --git a/apps/mobile/ios/Runner/AppDelegate.swift b/apps/mobile/ios/Runner/AppDelegate.swift
index 3196f96..f429212 100644
--- a/apps/mobile/ios/Runner/AppDelegate.swift
+++ b/apps/mobile/ios/Runner/AppDelegate.swift
@@ -20,6 +20,10 @@ import firebase_messaging
 
   func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
     GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
+    // V2-5a §6.3: SF Mono for Dart's FontLoader, before the first frame.
+    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ShellxSystemMonoFont") {
+      SystemMonoFont.register(messenger: registrar.messenger())
+    }
   }
 
   /// V2-2b B8: the buttons of an AI permission push (`aps.category` = `ai_perm`). "Deny" is the first action
````

Add the file to the Runner target (`apps/mobile/ios/Runner.xcodeproj/project.pbxproj`, four lines next to `AppDelegate.swift`):

````diff
diff --git a/apps/mobile/ios/Runner.xcodeproj/project.pbxproj b/apps/mobile/ios/Runner.xcodeproj/project.pbxproj
index e7048b9..97cf939 100644
--- a/apps/mobile/ios/Runner.xcodeproj/project.pbxproj
+++ b/apps/mobile/ios/Runner.xcodeproj/project.pbxproj
@@ -15,6 +15,7 @@
 		5E1A0C302F8A4B0100D1C0DE /* Localizable.strings in Resources */ = {isa = PBXBuildFile; fileRef = 5E1A0C312F8A4B0100D1C0DE /* Localizable.strings */; };
 		71C0E869FD625ADA0EDFCEE7 /* GoogleService-Info.plist in Resources */ = {isa = PBXBuildFile; fileRef = 3698DA38B951340983708CE3 /* GoogleService-Info.plist */; };
 		74858FAF1ED2DC5600515810 /* AppDelegate.swift in Sources */ = {isa = PBXBuildFile; fileRef = 74858FAE1ED2DC5600515810 /* AppDelegate.swift */; };
+		5A5F0001000000000000B001 /* SystemMonoFont.swift in Sources */ = {isa = PBXBuildFile; fileRef = 5A5F0002000000000000B001 /* SystemMonoFont.swift */; };
 		97C146FC1CF9000F007C117D /* Main.storyboard in Resources */ = {isa = PBXBuildFile; fileRef = 97C146FA1CF9000F007C117D /* Main.storyboard */; };
 		97C146FE1CF9000F007C117D /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = 97C146FD1CF9000F007C117D /* Assets.xcassets */; };
 		97C147011CF9000F007C117D /* LaunchScreen.storyboard in Resources */ = {isa = PBXBuildFile; fileRef = 97C146FF1CF9000F007C117D /* LaunchScreen.storyboard */; };
@@ -63,6 +64,7 @@
 		5E1A0C2F2F8A4B0100D1C0DE /* Runner.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Runner.entitlements; sourceTree = "<group>"; };
 		74858FAD1ED2DC5600515810 /* Runner-Bridging-Header.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = "Runner-Bridging-Header.h"; sourceTree = "<group>"; };
 		74858FAE1ED2DC5600515810 /* AppDelegate.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = AppDelegate.swift; sourceTree = "<group>"; };
+		5A5F0002000000000000B001 /* SystemMonoFont.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SystemMonoFont.swift; sourceTree = "<group>"; };
 		7AEDDFCC7E2E3A1F1DE64320 /* Pods-Runner.profile.xcconfig */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = text.xcconfig; name = "Pods-Runner.profile.xcconfig"; path = "Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig"; sourceTree = "<group>"; };
 		7AFA3C8E1D35360C0083082E /* Release.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; name = Release.xcconfig; path = Flutter/Release.xcconfig; sourceTree = "<group>"; };
 		8590EBAF728E1AC4E465C25B /* Pods_Runner.framework */ = {isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = Pods_Runner.framework; sourceTree = BUILT_PRODUCTS_DIR; };
@@ -159,6 +161,7 @@
 				1498D2321E8E86230040F4C2 /* GeneratedPluginRegistrant.h */,
 				1498D2331E8E89220040F4C2 /* GeneratedPluginRegistrant.m */,
 				74858FAE1ED2DC5600515810 /* AppDelegate.swift */,
+				5A5F0002000000000000B001 /* SystemMonoFont.swift */,
 				74858FAD1ED2DC5600515810 /* Runner-Bridging-Header.h */,
 			);
 			path = Runner;
@@ -421,6 +424,7 @@
 			buildActionMask = 2147483647;
 			files = (
 				74858FAF1ED2DC5600515810 /* AppDelegate.swift in Sources */,
+				5A5F0001000000000000B001 /* SystemMonoFont.swift in Sources */,
 				1498D2341E8E89220040F4C2 /* GeneratedPluginRegistrant.m in Sources */,
 			);
 			runOnlyForDeploymentPostprocessing = 0;
````

`apps/mobile/pubspec.yaml`: the package (which pins `cupertino_icons` 1.0.9, so the app drops its own `^1.0.8`, A45) and `integration_test` (R16):

````diff
diff --git a/apps/mobile/pubspec.yaml b/apps/mobile/pubspec.yaml
index 6c92b5d..f44f742 100644
--- a/apps/mobile/pubspec.yaml
+++ b/apps/mobile/pubspec.yaml
@@ -18,7 +18,6 @@ dependencies:
   adaptive_theme: ^3.7.2
   async: ^2.13.0
   auto_route: 11.1.0
-  cupertino_icons: ^1.0.8
   easy_refresh: ^3.4.0
   equatable: ^2.0.8
   flutter_secure_storage: ^10.3.4
@@ -61,6 +60,8 @@ dependencies:
   shellx_ai: any
   shellx_client: any
   shellx_core: any
+  # V2-5a: the shared design system (tokens, type, icons, widgets); it also pins cupertino_icons.
+  shellx_design: any
   # Voice input (voice spec V4), BSD-3-Clause. Pinned exactly: 7.5.0+ needs Dart ^3.12 / Flutter 3.44.
   speech_to_text: 7.4.0
   url_launcher: ^6.3.2
@@ -84,6 +85,9 @@ dev_dependencies:
   fake_async: ^1.3.3
   flutter_lints: ^6.0.0
   http: ^1.6.0
+  # V2-5a Task 1: the SF Mono spike runs on a simulator or a device (integration_test/).
+  integration_test:
+    sdk: flutter
   # V2-4 E12: the tool page's web view engine is tested against a fake web view platform. Both come
   # with webview_flutter (their versions follow its pin); declared like the shared_preferences one.
   plugin_platform_interface: ^2.1.8
````

- [ ] **Step 8: The spike entrypoints**

`apps/desktop/integration_test/sf_mono_spike_test.dart`:

````dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shellx_design/shellx_design.dart';

/// V2-5a §6.3, the SF Mono spike: its five pass criteria on a real Apple
/// platform, through the runner's channel and [ShellxSystemFont.load] only.
/// It never runs the app's `main()`: no settings, no Keychain, no relay.
/// macOS: only in the isolated build of plan Task 1 (bundle id
/// pro.shellx.desktop.itest, a temporary HOME). iOS: a simulator or device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SF Mono spike: bytes, coverage, width, weights, no files', (
    tester,
  ) async {
    final root = _appRoot();
    final before = _files(root);

    // 1. The upright and the italic, each over 100 KB, within 150 ms.
    final watch = Stopwatch()..start();
    final answer = await ShellxSystemFont.channel
        .invokeMapMethod<String, Object?>('monospaced');
    final ms = watch.elapsedMilliseconds;
    final regular = answer!['regular']! as Uint8List;
    final italic = answer['italic']! as Uint8List;
    // 2. A glyph for each of the 134 letters and the 5 combining marks.
    final missing = answer['missing']! as List<Object?>;

    final status = await ShellxSystemFont.load();

    // 3. Drawn with the loaded family: SF Mono is 0.618 em a cell.
    final sfMono = _width(ShellxFonts.systemMono);
    final jetBrains = _width(ShellxFonts.bundledMono);

    // 4. More ink at each heavier weight; the italic is not the upright.
    final ink = <double, double>{};
    for (final weight in [300.0, 400.0, 600.0, 700.0]) {
      ink[weight] = _ink(await _draw(tester, weight: weight));
    }
    final upright = await _draw(tester, weight: 400);
    final slanted = await _draw(tester, weight: 400, italic: true);

    // 5. Nothing new in the app's folders.
    final added = _files(root).difference(before);

    debugPrint(
      'SF Mono spike: regular=${regular.length} italic=${italic.length} '
      'ms=$ms missing=${missing.length} status=${status.isLoaded} '
      'width=${sfMono.toStringAsFixed(1)} '
      'jetbrains=${jetBrains.toStringAsFixed(1)} '
      'ink=${ink.values.map((v) => v.round()).join('<')} '
      'italicDiffers=${!listEquals(upright, slanted)} added=${added.length}',
    );

    expect(regular.length, greaterThan(100 * 1024));
    expect(italic.length, greaterThan(100 * 1024));
    expect(ms, lessThanOrEqualTo(150));
    expect(missing, isEmpty);
    expect(status, const ShellxFontStatus.loaded());
    expect(sfMono, closeTo(618, 2));
    expect(jetBrains, closeTo(600, 2));
    expect(ink[400]!, greaterThan(ink[300]!));
    expect(ink[600]!, greaterThan(ink[400]!));
    expect(ink[700]!, greaterThan(ink[600]!));
    expect(listEquals(upright, slanted), isFalse);
    expect(added, isEmpty);
  });
}

/// Where this app may write: macOS, the recipe's temporary HOME; iOS, the
/// app's container.
Directory _appRoot() => Platform.isIOS
    ? Directory.systemTemp.parent
    : Directory(Platform.environment['HOME']!);

Set<String> _files(Directory root) {
  final found = <String>{};
  try {
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      found.add(entity.path);
    }
  } on FileSystemException {
    // A folder the OS keeps closed: nothing of ours is in it.
  }
  return found;
}

double _width(String family) {
  final painter = TextPainter(
    text: TextSpan(
      text: 'mmmmmmmmmm',
      style: TextStyle(
        fontFamily: family,
        fontSize: 100,
        fontWeight: FontWeight.w400,
        fontVariations: const [FontVariation('wght', 400)],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The RGBA pixels of a line of SF Mono at [weight], black on white.
Future<Uint8List> _draw(
  WidgetTester tester, {
  required double weight,
  bool italic = false,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xFFFFFFFF),
            padding: const EdgeInsets.all(4),
            child: Text(
              'Đăng nhập ShellX llll|||| mmmm',
              style: TextStyle(
                fontFamily: ShellxFonts.systemMono,
                fontSize: 32,
                color: const Color(0xFF000000),
                fontWeight: FontWeight.values[(weight ~/ 100) - 1],
                fontVariations: [FontVariation('wght', weight)],
                fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = (await image.toByteData())!;
    image.dispose();
    return bytes.buffer.asUint8List();
  }))!;
}

/// Sum of (255 − red) over the pixels: how much ink.
double _ink(Uint8List rgba) {
  var sum = 0.0;
  for (var i = 0; i < rgba.length; i += 4) {
    sum += 255 - rgba[i];
  }
  return sum;
}
````

`apps/mobile/integration_test/sf_mono_spike_test.dart` (the same test, formatted at the mobile width 120):

````dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shellx_design/shellx_design.dart';

/// V2-5a §6.3, the SF Mono spike: its five pass criteria on a real Apple
/// platform, through the runner's channel and [ShellxSystemFont.load] only.
/// It never runs the app's `main()`: no settings, no Keychain, no relay.
/// macOS: only in the isolated build of plan Task 1 (bundle id
/// pro.shellx.desktop.itest, a temporary HOME). iOS: a simulator or device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SF Mono spike: bytes, coverage, width, weights, no files', (
    tester,
  ) async {
    final root = _appRoot();
    final before = _files(root);

    // 1. The upright and the italic, each over 100 KB, within 150 ms.
    final watch = Stopwatch()..start();
    final answer = await ShellxSystemFont.channel.invokeMapMethod<String, Object?>('monospaced');
    final ms = watch.elapsedMilliseconds;
    final regular = answer!['regular']! as Uint8List;
    final italic = answer['italic']! as Uint8List;
    // 2. A glyph for each of the 134 letters and the 5 combining marks.
    final missing = answer['missing']! as List<Object?>;

    final status = await ShellxSystemFont.load();

    // 3. Drawn with the loaded family: SF Mono is 0.618 em a cell.
    final sfMono = _width(ShellxFonts.systemMono);
    final jetBrains = _width(ShellxFonts.bundledMono);

    // 4. More ink at each heavier weight; the italic is not the upright.
    final ink = <double, double>{};
    for (final weight in [300.0, 400.0, 600.0, 700.0]) {
      ink[weight] = _ink(await _draw(tester, weight: weight));
    }
    final upright = await _draw(tester, weight: 400);
    final slanted = await _draw(tester, weight: 400, italic: true);

    // 5. Nothing new in the app's folders.
    final added = _files(root).difference(before);

    debugPrint(
      'SF Mono spike: regular=${regular.length} italic=${italic.length} '
      'ms=$ms missing=${missing.length} status=${status.isLoaded} '
      'width=${sfMono.toStringAsFixed(1)} '
      'jetbrains=${jetBrains.toStringAsFixed(1)} '
      'ink=${ink.values.map((v) => v.round()).join('<')} '
      'italicDiffers=${!listEquals(upright, slanted)} added=${added.length}',
    );

    expect(regular.length, greaterThan(100 * 1024));
    expect(italic.length, greaterThan(100 * 1024));
    expect(ms, lessThanOrEqualTo(150));
    expect(missing, isEmpty);
    expect(status, const ShellxFontStatus.loaded());
    expect(sfMono, closeTo(618, 2));
    expect(jetBrains, closeTo(600, 2));
    expect(ink[400]!, greaterThan(ink[300]!));
    expect(ink[600]!, greaterThan(ink[400]!));
    expect(ink[700]!, greaterThan(ink[600]!));
    expect(listEquals(upright, slanted), isFalse);
    expect(added, isEmpty);
  });
}

/// Where this app may write: macOS, the recipe's temporary HOME; iOS, the
/// app's container.
Directory _appRoot() => Platform.isIOS ? Directory.systemTemp.parent : Directory(Platform.environment['HOME']!);

Set<String> _files(Directory root) {
  final found = <String>{};
  try {
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      found.add(entity.path);
    }
  } on FileSystemException {
    // A folder the OS keeps closed: nothing of ours is in it.
  }
  return found;
}

double _width(String family) {
  final painter = TextPainter(
    text: TextSpan(
      text: 'mmmmmmmmmm',
      style: TextStyle(
        fontFamily: family,
        fontSize: 100,
        fontWeight: FontWeight.w400,
        fontVariations: const [FontVariation('wght', 400)],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The RGBA pixels of a line of SF Mono at [weight], black on white.
Future<Uint8List> _draw(
  WidgetTester tester, {
  required double weight,
  bool italic = false,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xFFFFFFFF),
            padding: const EdgeInsets.all(4),
            child: Text(
              'Đăng nhập ShellX llll|||| mmmm',
              style: TextStyle(
                fontFamily: ShellxFonts.systemMono,
                fontSize: 32,
                color: const Color(0xFF000000),
                fontWeight: FontWeight.values[(weight ~/ 100) - 1],
                fontVariations: [FontVariation('wght', weight)],
                fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = (await image.toByteData())!;
    image.dispose();
    return bytes.buffer.asUint8List();
  }))!;
}

/// Sum of (255 − red) over the pixels: how much ink.
double _ink(Uint8List rgba) {
  var sum = 0.0;
  for (var i = 0; i < rgba.length; i += 4) {
    sum += 255 - rgba[i];
  }
  return sum;
}
````

Then analyze both apps (`flutter test` does not run `integration_test/`):

````bash
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get
(cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze)
(cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze)
````

Expected: desktop `No issues found!`; mobile only the pre-existing `unnecessary_import` info.

Run both apps' suites (Global Constraints) — expected: every test passes, the counts unchanged.

- [ ] **Step 9: Commit the code (the macOS recipe builds `HEAD`, R15)**

````bash
git add pubspec.yaml packages/shellx_design apps/desktop/macos/Runner/SystemMonoFont.swift apps/desktop/macos/Runner/MainFlutterWindow.swift apps/desktop/macos/Runner.xcodeproj/project.pbxproj apps/desktop/pubspec.yaml apps/desktop/integration_test/sf_mono_spike_test.dart apps/mobile/ios/Runner/SystemMonoFont.swift apps/mobile/ios/Runner/AppDelegate.swift apps/mobile/ios/Runner.xcodeproj/project.pbxproj apps/mobile/pubspec.yaml apps/mobile/integration_test/sf_mono_spike_test.dart
git commit -m "feat(v2-design): shellx_design skeleton and the SF Mono loader — the system font rebuilt in memory on macOS and iOS, JetBrains Mono otherwise

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

- [ ] **Step 10: Run the spike on macOS — the isolated recipe**

From the worktree root. The recipe makes a throw-away worktree of `HEAD`, gives it the bundle id `pro.shellx.desktop.itest`, builds **the spike entrypoint as the app** (never `main()`, R1), starts it with a temporary `HOME`, waits for the result and stops **only that PID**. Never run it with `flutter test integration_test/…` or `-d macos` in your checkout.

````bash
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/shellx-itest.XXXXXX")
git worktree add --detach "$SCRATCH/wt" HEAD
(
  cd "$SCRATCH/wt"
  PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get > /dev/null
  sed -i '' 's/^PRODUCT_BUNDLE_IDENTIFIER = .*/PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop.itest/' \
    apps/desktop/macos/Runner/Configs/AppInfo.xcconfig
  grep -q '^PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop.itest$' apps/desktop/macos/Runner/Configs/AppInfo.xcconfig \
    || { echo 'bundle id not changed: stop'; exit 1; }
  cd apps/desktop
  PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug -t integration_test/sf_mono_spike_test.dart || exit 1
  mkdir -p "$SCRATCH/home"
  HOME="$SCRATCH/home" CFFIXED_USER_HOME="$SCRATCH/home" \
    build/macos/Build/Products/Debug/ShellX.app/Contents/MacOS/ShellX > "$SCRATCH/itest.log" 2>&1 &
  PID=$!
  python3 - "$SCRATCH/itest.log" "$PID" <<'EOF'
import os, signal, sys, time
log, pid = sys.argv[1], int(sys.argv[2])
for _ in range(360):  # 3 minutes at most
    text = open(log, errors='replace').read()
    if 'All tests passed!' in text or 'Some tests failed' in text:
        break
    time.sleep(0.5)
os.kill(pid, signal.SIGTERM)  # only the app this recipe started
EOF
  grep -E 'SF Mono spike|^flutter: [0-9]+:[0-9]+ \+' "$SCRATCH/itest.log" | tail -5
)
find "$SCRATCH/home" -mindepth 1 | head
git worktree remove --force "$SCRATCH/wt" && rm -rf "$SCRATCH"
````

Expected (the run of 2026-10-16 on macOS 26.5; the build also compiles `shellx-term` with cargo, a few minutes the first time):
- no `bundle id not changed: stop`;
- `flutter: SF Mono spike: regular=223892 italic=200956 ms=… missing=0 status=true width=618.2 jetbrains=600.0 ink=…<…<…<… italicDiffers=true added=0`;
- `flutter: 00:0N +2: All tests passed!`;
- `find` prints nothing (the temporary HOME stayed empty).

- [ ] **Step 11: Run the spike on an iOS simulator**

Boot a simulator nobody else is using (leave already-booted ones alone), run the harness, shut down only the one you booted:

````bash
xcrun simctl list devices available | grep -i iphone
SIM=<an iPhone that is Shutdown, its UUID>
xcrun simctl boot "$SIM"
(cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test integration_test/sf_mono_spike_test.dart -d "$SIM")
xcrun simctl shutdown "$SIM"
sed -i '' 's/^COCOAPODS: .*/COCOAPODS: 1.16.2/' apps/mobile/ios/Podfile.lock
git diff --stat apps/mobile/ios/Podfile.lock
````

Expected: `SF Mono spike: regular=223892 italic=200956 ms=… missing=0 status=true width=618.2 jetbrains=600.0 ink=…<…<…<… italicDiffers=true added=0` and `All tests passed!` (about two minutes of Xcode build). `Podfile.lock` gains exactly the `integration_test` lines (R16):

````diff
diff --git a/apps/mobile/ios/Podfile.lock b/apps/mobile/ios/Podfile.lock
index 031d019..1f11629 100644
--- a/apps/mobile/ios/Podfile.lock
+++ b/apps/mobile/ios/Podfile.lock
@@ -73,6 +73,8 @@ PODS:
     - GoogleUtilities/Privacy
   - image_picker_ios (0.0.1):
     - Flutter
+  - integration_test (0.0.1):
+    - Flutter
   - local_auth_darwin (0.0.1):
     - Flutter
     - FlutterMacOS
@@ -109,6 +111,7 @@ DEPENDENCIES:
   - flutter_local_notifications (from `.symlinks/plugins/flutter_local_notifications/ios`)
   - flutter_secure_storage_darwin (from `.symlinks/plugins/flutter_secure_storage_darwin/darwin`)
   - image_picker_ios (from `.symlinks/plugins/image_picker_ios/ios`)
+  - integration_test (from `.symlinks/plugins/integration_test/ios`)
   - local_auth_darwin (from `.symlinks/plugins/local_auth_darwin/darwin`)
   - mobile_scanner (from `.symlinks/plugins/mobile_scanner/darwin`)
   - package_info_plus (from `.symlinks/plugins/package_info_plus/ios`)
@@ -148,6 +151,8 @@ EXTERNAL SOURCES:
     :path: ".symlinks/plugins/flutter_secure_storage_darwin/darwin"
   image_picker_ios:
     :path: ".symlinks/plugins/image_picker_ios/ios"
+  integration_test:
+    :path: ".symlinks/plugins/integration_test/ios"
   local_auth_darwin:
     :path: ".symlinks/plugins/local_auth_darwin/darwin"
   mobile_scanner:
@@ -181,6 +186,7 @@ SPEC CHECKSUMS:
   GoogleDataTransport: a24e58982ab3ba2f64d79613e027fe7f57e88539
   GoogleUtilities: 4e0c2ad9fa0d0d18b5c4df8bf57b461cba35b0bb
   image_picker_ios: e0ece4aa2a75771a7de3fa735d26d90817041326
+  integration_test: 4a889634ef21a45d28d50d622cf412dc6d9f586e
   local_auth_darwin: c3ee6cce0a8d56be34c8ccb66ba31f7f180aaebb
   mobile_scanner: 9157936403f5a0644ca3779a38ff8404c5434a93
   nanopb: fad817b59e0457d11a5dfbde799381cd727c1275
````

The real-iPhone run (iOS 26/27) and `--dart-define=FORCE_BUNDLED_MONO=true` are manual checks (§12 item 1, listed in the ledger).

- [ ] **Step 12: The ledger**

Create `docs/superpowers/ledgers/v2-5a.md`:

````markdown
# V2-5a — name and design system — ledger

Plan: `docs/superpowers/plans/2026-10-16-v2-5a-name-and-design-system.md`. Spec: `docs/superpowers/specs/2026-10-16-v2-5a-name-and-design-system-design.md`.

## Rulings

<copy R1–R16 of the plan's "Rulings" section here, verbatim>

## SF Mono spike (§6.3)

| Platform | regular / italic bytes | ms | missing | width (618 ± 2) | ink 300<400<600<700 | italic differs | new files | Result |
|---|---|---|---|---|---|---|---|---|
| macOS <version> (isolated build, pro.shellx.desktop.itest, temporary HOME) | <from Step 10> | | | | | | | pass / fail: <criterion> |
| iOS simulator <device, iOS version> | <from Step 11> | | | | | | | |
| iPhone (real device) | manual, §12 item 1 | | | | | | | pending |

Switches after the spike: `ShellxSystemFont.enabledOnMacOS = <true/false>`, `enabledOnIOS = <true/false>` (R6).

## Manual checks pending (§12)

1–14 of spec §12, unchecked.
````

Fill the two rows from Steps 10–11 (numbers as printed). If a platform failed a criterion: set its switch to `false` in `packages/shellx_design/lib/src/system_font.dart`, update `system_font_test.dart`'s "the switches default to on" expectation for it, rerun Step 5, and say so in the ledger.

- [ ] **Step 13: Commit the results**

````bash
git add docs/superpowers/ledgers/v2-5a.md apps/mobile/ios/Podfile.lock
git commit -m "docs(v2-design): V2-5a ledger — rulings, the SF Mono spike on macOS and the iOS simulator

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

### Task 2: ⚠ The desktop Keychain service comes from the running bundle id (R1)

The controller's binding ruling (R1). Security-relevant: use opus. No V2-5a task launches the full desktop app before this task is committed.

**Files:**
- Modify: `apps/desktop/lib/src/platform/secure_key_value_store.dart`
- Modify: `apps/desktop/lib/src/agent/agent_side.dart` (`buildAgentSide`), `apps/desktop/lib/src/agent/ui_services.dart` (`buildUiServices`), `apps/desktop/lib/main.dart` (both calls), `apps/desktop/lib/daemon_main.dart` (`daemonMain` → `_serve` → `buildAgentSide`)
- Modify: `apps/desktop/test/platform/storage_test.dart`
- Create: `apps/desktop/test/platform/keychain_service_test.dart`

**Interfaces:**
- Consumes: `PackageInfo.packageName` (already read in `main.dart` and `daemon_main.dart`; on macOS it is `NSBundle.mainBundle.bundleIdentifier`).
- Produces: `const String kProductionBundleId = 'pro.shellx.desktop'`; `String keychainServiceFor(String bundleId)`; `SecureKeyValueStore({required String bundleId, FlutterSecureStorage? storage})`; `static FlutterSecureStorage SecureKeyValueStore.storageFor(String bundleId)`; `buildAgentSide(…, required String bundleId)`, `buildUiServices(…, required String bundleId)`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/platform/keychain_service_test.dart`:

````dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/secure_key_value_store.dart';

/// V2-5a Task 2: the Keychain service comes from the running bundle id, so
/// an isolated test build never touches the released app's items.
void main() {
  Map<String, String> macOptions(String bundleId) =>
      SecureKeyValueStore.storageFor(bundleId).mOptions.toMap();

  test('the released app keeps pro.shellx.desktop (its users\' items)', () {
    expect(kProductionBundleId, 'pro.shellx.desktop');
    expect(keychainServiceFor('pro.shellx.desktop'), 'pro.shellx.desktop');
    final options = macOptions('pro.shellx.desktop');
    expect(options['accountName'], 'pro.shellx.desktop');
    expect(options['usesDataProtectionKeychain'], 'false');
  });

  test('any other bundle id gets its own service, equal to the id', () {
    for (final id in [
      'pro.shellx.desktop.itest',
      'pro.shellx.desktop.smoketest',
      'pro.shellx.desktop2',
      'com.example.other',
    ]) {
      expect(keychainServiceFor(id), id);
      expect(macOptions(id)['accountName'], id);
      expect(macOptions(id)['usesDataProtectionKeychain'], 'false');
    }
    expect(keychainServiceFor(''), 'pro.shellx.desktop.unknown');
    expect(macOptions('')['accountName'], isNot('pro.shellx.desktop'));
  });

  test('both processes pass the running bundle id, nothing else', () {
    final main = File('lib/main.dart').readAsStringSync();
    final daemon = File('lib/daemon_main.dart').readAsStringSync();
    final passed = RegExp(r'bundleId: ([\w.]+),');
    expect(passed.allMatches(main).map((m) => m[1]), [
      'info.packageName',
      'info.packageName',
    ]);
    expect(passed.allMatches(daemon).map((m) => m[1]), [
      'info.packageName',
      'bundleId',
    ]);
    // The store is the only place that names Keychain options.
    final lib = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('MacOsOptions('))
        .map((f) => f.path.replaceAll(r'\', '/'));
    expect(lib, ['lib/src/platform/secure_key_value_store.dart']);
  });
}
````

`apps/desktop/test/platform/storage_test.dart`, the store now names its bundle id:

````diff
diff --git a/apps/desktop/test/platform/storage_test.dart b/apps/desktop/test/platform/storage_test.dart
index 9f24985..43b698f 100644
--- a/apps/desktop/test/platform/storage_test.dart
+++ b/apps/desktop/test/platform/storage_test.dart
@@ -10,7 +10,7 @@ void main() {
 
   test('SecureKeyValueStore reads, writes and deletes', () async {
     FlutterSecureStorage.setMockInitialValues({});
-    final store = SecureKeyValueStore();
+    final store = SecureKeyValueStore(bundleId: kProductionBundleId);
     expect(await store.read('auth_token'), isNull);
     await store.write('auth_token', 'secret');
     expect(await store.read('auth_token'), 'secret');
````

- [ ] **Step 2: Run it to see it fail**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/platform/keychain_service_test.dart test/platform/storage_test.dart
````

Expected: compilation fails (`kProductionBundleId`, `keychainServiceFor`, `storageFor`, the `bundleId` parameter undefined).

- [ ] **Step 3: The store**

`apps/desktop/lib/src/platform/secure_key_value_store.dart` (whole file):

````dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shellx_core/shellx_core.dart';

/// The bundle id of the released app (`macos/Runner/Configs/AppInfo.xcconfig`).
const String kProductionBundleId = 'pro.shellx.desktop';

/// The Keychain service (`kSecAttrService`, flutter_secure_storage's
/// `accountName`) of the app whose bundle id is [bundleId].
///
/// The released app keeps `pro.shellx.desktop`, where its users' items (the
/// device key, the sign-in, the trusted phones) already are. Any other
/// bundle id, such as an isolated test build (`pro.shellx.desktop.itest`,
/// `.smoketest`), gets a service of its own, equal to that id: it never
/// reads, writes or deletes the released app's items. An empty id (never
/// seen: every app bundle has one) is not the released app either.
String keychainServiceFor(String bundleId) =>
    bundleId.isEmpty ? '$kProductionBundleId.unknown' : bundleId;

/// [KeyValueStore] over flutter_secure_storage.
///
/// The app must construct exactly one [SecureKeyValueStore] and share that
/// same instance process-wide: `DeviceIdentity.loadOrCreate` (generate the
/// device key only once under concurrent calls) and `TrustedStore` both rely
/// on one instance per underlying storage, rather than separate instances
/// that happen to point at the same underlying storage.
///
/// * macOS: login keychain, service [keychainServiceFor] of the running
///   bundle id (`pro.shellx.desktop` for the released app). The legacy
///   (file-based) keychain is used on purpose: the data-protection keychain
///   needs a `keychain-access-groups` entitlement backed by a provisioning
///   profile, which a Developer ID app outside the App Store does not have.
/// * Windows: values are encrypted with a key held in the current user's
///   Windows Credential Manager and stored in the app's support directory,
///   readable only by the current Windows user.
final class SecureKeyValueStore implements KeyValueStore {
  /// [bundleId]: the running app's (`PackageInfo.packageName`, which is
  /// `CFBundleIdentifier` on macOS).
  SecureKeyValueStore({required String bundleId, FlutterSecureStorage? storage})
    : _storage = storage ?? storageFor(bundleId);

  /// The storage of the app whose bundle id is [bundleId].
  static FlutterSecureStorage storageFor(String bundleId) =>
      FlutterSecureStorage(
        mOptions: MacOsOptions(
          accountName: keychainServiceFor(bundleId),
          usesDataProtectionKeychain: false,
        ),
      );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
````

- [ ] **Step 4: Pass the running bundle id from both processes**

````diff
diff --git a/apps/desktop/lib/daemon_main.dart b/apps/desktop/lib/daemon_main.dart
index 1dcd826..8a809c9 100644
--- a/apps/desktop/lib/daemon_main.dart
+++ b/apps/desktop/lib/daemon_main.dart
@@ -63,7 +63,12 @@ Future<void> daemonMain() async {
         await cleanupOldRuntimes(localAppData: local, keep: info.version);
       }
     }
-    await _serve(paths: paths, environment: environment, version: info.version);
+    await _serve(
+      paths: paths,
+      environment: environment,
+      version: info.version,
+      bundleId: info.packageName,
+    );
   } catch (error) {
     debugPrint('ShellX daemon: stopped: ${error.runtimeType}');
     try {
@@ -79,6 +84,7 @@ Future<void> _serve({
   required MuxPaths paths,
   required Map<String, String> environment,
   required String version,
+  required String bundleId,
 }) async {
   final locale = resolveAppLocale(PlatformDispatcher.instance.locales);
   final l10n = lookupAppLocalizations(locale);
@@ -124,6 +130,7 @@ Future<void> _serve({
       ),
     ),
     deviceName: deviceNameFromHostname(Platform.localHostname),
+    bundleId: bundleId,
     remoteTools: remoteTools,
     cliPaths: cliPaths,
     // The listener below is this daemon's: shells are told its address and
diff --git a/apps/desktop/lib/main.dart b/apps/desktop/lib/main.dart
index 122f8a2..f79f5a9 100644
--- a/apps/desktop/lib/main.dart
+++ b/apps/desktop/lib/main.dart
@@ -336,6 +336,7 @@ Future<void> _start(_Startup startup) async {
       appVersion: info.version,
       relayBase: relayBase,
       deviceName: deviceName,
+      bundleId: info.packageName,
       sharingSetup: sharingSetup,
       windows: Platform.isWindows,
       stopRemoteRetries: stopRemoteRetries,
@@ -358,6 +359,7 @@ Future<void> _start(_Startup startup) async {
       relayBase: relayBase,
       sharingSetup: sharingSetup,
       deviceName: deviceName,
+      bundleId: info.packageName,
       remoteTools: remoteTools,
       cliPaths: cli?.paths,
       cliSocket: cliService?.address,
diff --git a/apps/desktop/lib/src/agent/agent_side.dart b/apps/desktop/lib/src/agent/agent_side.dart
index d608148..02dee5a 100644
--- a/apps/desktop/lib/src/agent/agent_side.dart
+++ b/apps/desktop/lib/src/agent/agent_side.dart
@@ -46,6 +46,7 @@ AgentSide buildAgentSide({
   required Uri relayBase,
   required TerminalSharingSetup? sharingSetup,
   required String deviceName,
+  required String bundleId,
   required RemoteTools remoteTools,
   required Future<void> Function() quitApp,
   Future<void> Function()? deletePastedImages,
@@ -97,7 +98,7 @@ AgentSide buildAgentSide({
   // The process's one SecureKeyValueStore; DesktopServices builds the one
   // TrustedStore over it.
   final services = DesktopServices(
-    secureStore: SecureKeyValueStore(),
+    secureStore: SecureKeyValueStore(bundleId: bundleId),
     settings: settings,
     api: api,
     createApi: () => ShellxApi(baseUri: relayBase),
diff --git a/apps/desktop/lib/src/agent/ui_services.dart b/apps/desktop/lib/src/agent/ui_services.dart
index 9b20452..5ab0f5e 100644
--- a/apps/desktop/lib/src/agent/ui_services.dart
+++ b/apps/desktop/lib/src/agent/ui_services.dart
@@ -23,6 +23,7 @@ DesktopServices buildUiServices({
   required String appVersion,
   required Uri relayBase,
   required String deviceName,
+  required String bundleId,
   required TerminalSharingSetup? sharingSetup,
   required Future<void> Function() quitApp,
   Future<void> Function()? deletePastedImages,
@@ -31,7 +32,7 @@ DesktopServices buildUiServices({
   DevicePlatform? platform,
   required bool windows,
 }) => DesktopServices(
-  secureStore: SecureKeyValueStore(),
+  secureStore: SecureKeyValueStore(bundleId: bundleId),
   settings: settings,
   api: ShellxApi(baseUri: relayBase),
   createApi: () => ShellxApi(baseUri: relayBase),
````

- [ ] **Step 5: Run the checks**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/platform/secure_key_value_store.dart lib/main.dart lib/daemon_main.dart lib/src/agent/agent_side.dart lib/src/agent/ui_services.dart test/platform/keychain_service_test.dart test/platform/storage_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
````

Expected: `No issues found!`; the whole suite passes with 3 tests more than before (3924 / 10 skipped on the union this plan was checked on).

- [ ] **Step 6: Ledger and commit**

Append to `docs/superpowers/ledgers/v2-5a.md` under a new `## Task 2` heading: "Keychain service = running bundle id; `pro.shellx.desktop` for the released app (existing items kept); isolated builds (`.itest`, `.smoketest`) get their own service and never touch the real items."

````bash
git add apps/desktop/lib/src/platform/secure_key_value_store.dart apps/desktop/lib/src/agent/agent_side.dart apps/desktop/lib/src/agent/ui_services.dart apps/desktop/lib/main.dart apps/desktop/lib/daemon_main.dart apps/desktop/test/platform/storage_test.dart apps/desktop/test/platform/keychain_service_test.dart docs/superpowers/ledgers/v2-5a.md
git commit -m "fix(v2-design): the Keychain service is the running bundle id — pro.shellx.desktop for the released app, its own for an isolated test build

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

### Task 3: The package's tokens — palette, gradients, radii, spacing, shadows, motion, terminal palette, contrast

Spec §5.2–§5.8 and the contrast tests of §10.1. Every value is the spec's; every contrast the spec measures is pinned with its floor and its measured value (± 0.05: the spec rounds composites).

**Files:**
- Create: `packages/shellx_design/lib/src/{palette,gradients,radii,spacing,elevation,motion,terminal_palette,contrast}.dart`
- Modify: `packages/shellx_design/lib/shellx_design.dart`
- Create: `packages/shellx_design/test/palette_test.dart`, `test/contrast_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `ShellxPalette` (dark: `navy900…navy600`, `white100…white38`, `hairline`, `hairlineStrong`, `handle`, `fieldOutline`, `cyan`, `onCyan`, `cyanSoft`, `azure`, `link`, `onAccent`, `accentLight`, `accentStrongLight`, `indigo`, `wedgeBottom`, `ok`, `okSoft`, `warn`, `warnSoft`, `warnLine`, `error`, `errorSoft`, `onError`, `errorHover`, `noticeBg`, `noticeText`, `noticeLine`, `inProgress`, `scrim`, `scrollThumb`, `scrollThumbHover`, `keyboardBackground`, `keyboardKey`, `keyboardInk`, `glassFill`), `ShellxLightPalette` (`page`, `surface`, `raised`, `inset`, `text`, `textSecondary`, `placeholder`, `hairline`, `handle`, `fieldOutline`, `primary`, `primarySoft`, `ok`, `okDot`, `okSoft`, `warn`, `warnSoft`, `error`, `errorSoft`, `scrim`, `keyboard*`, `keyboardLink`, `keyboardError`, `glassFill`, `glassBorder`), `ShellxGradients` (`accent`, `accentStrong`, `wedge`, `glassBorderDark`, `glassBorderLight`, `hoverShade`, `pressedShade`), `ShellxRadii` (`tiny`, `control`, `card`, `sheet`, `pill`), `ShellxSpacing` (`s2…s48`), `ShellxElevation` (`dark`/`light` with `raised`, `raisedSmall`, `float1`, `float2`, `cta`, `inset`; the `static const` lists `darkRaised`, `darkRaisedSmall`, `darkInset`, `darkFloat1`, `darkFloat2`, `darkCta`, `lightRaised`, `lightRaisedSmall`, `lightInset`, `lightFloat1`, `lightFloat2`, `lightCta`; `float1Elevation`, `float1ShadowColor`; R2), `ShellxInsetShadow(List<BoxShadow> shadows)`, `ShellxDurations` (`fast`, `press`, `exit`, `base`, `toastIn`, `slide`, `sheet`, `toastVisible`, `toastVisibleError`, `toastVisiblePhone`, `tooltipWait`, `scrollbarFade`, `dragExpandDelay`, `of(context, d)`), `ShellxCurves` (`fast`, `press`, `exit`, `base`, `slide`), `ShellxTerminalPalette` (§5.7), `contrastRatio(Color, Color)`, `compositeOver(Color fg, Color bg)`, `minContrastOnGradient(LinearGradient, Color, {int samples = 101, Color? overlay})`.

- [ ] **Step 1: Write the failing tests**

`packages/shellx_design/test/palette_test.dart`:

````dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_design/shellx_design.dart';

/// V2-5a §5.3–§5.8: every token's exact value.
void main() {
  test('dark palette (§5.3)', () {
    final values = <Color, int>{
      ShellxPalette.navy900: 0xFF1C222E,
      ShellxPalette.navy850: 0xFF222834,
      ShellxPalette.navy825: 0xFF242C3B,
      ShellxPalette.navy800: 0xFF28303F,
      ShellxPalette.navy750: 0xFF2C3547,
      ShellxPalette.navy700: 0xFF323B4F,
      ShellxPalette.navy650: 0xFF38445A,
      ShellxPalette.navy600: 0xFF3F4B62,
    };
    values.forEach((c, v) => expect(c, Color(v)));
    expect(ShellxPalette.white100, const Color(0xFFFFFFFF));
    expect(ShellxPalette.white87, const Color(0xFFE2E3E5));
    expect(ShellxPalette.white75, const Color(0xFFCACCD1));
    expect(ShellxPalette.white60, const Color(0xFFA7A9AE));
    expect(ShellxPalette.white50, const Color(0xFF8E9096));
    expect(ShellxPalette.white38, const Color(0xFF767A81));
    expect(ShellxPalette.hairline, const Color(0x14FFFFFF));
    expect(ShellxPalette.hairlineStrong, const Color(0x1AFFFFFF));
    expect(ShellxPalette.handle, const Color(0x33FFFFFF));
    expect(ShellxPalette.fieldOutline, const Color(0xFF76829C));
    expect(ShellxPalette.cyan, const Color(0xFF34C8E8));
    expect(ShellxPalette.onCyan, const Color(0xFF0E1A26));
    expect(ShellxPalette.cyanSoft, const Color(0xFF253E4D));
    expect(ShellxPalette.azure, const Color(0xFF3D9CEA));
    expect(ShellxPalette.link, const Color(0xFF5EADEE));
    expect(ShellxPalette.onAccent, const Color(0xFFFFFFFF));
    expect(ShellxPalette.accentLight, const Color(0xFF1A9BD8));
    expect(ShellxPalette.accentStrongLight, const Color(0xFF157CAD));
    expect(ShellxPalette.indigo, const Color(0xFF4E4AF2));
    expect(ShellxPalette.wedgeBottom, const Color(0xFF3C65CF));
    expect(ShellxPalette.scrim, const Color(0x99000000));
    expect(ShellxPalette.scrollThumb, const Color(0xFF3D424C));
    expect(ShellxPalette.scrollThumbHover, const Color(0xFF4E535D));
    expect(ShellxPalette.keyboardBackground, const Color(0xFF1E1F21));
    expect(ShellxPalette.keyboardKey, const Color(0xFF47484B));
    expect(ShellxPalette.keyboardInk, const Color(0xFFFFFFFF));
    expect(ShellxPalette.glassFill, const Color(0xCC323B4F));
  });

  test('status colours (§5.6)', () {
    expect(ShellxPalette.ok, const Color(0xFF5ED39C));
    expect(ShellxPalette.okSoft, const Color(0xFF293D40));
    expect(ShellxPalette.warn, const Color(0xFFF5B94E));
    expect(ShellxPalette.warnSoft, const Color(0xFF3B3937));
    expect(ShellxPalette.warnLine, const Color(0xFF554B3A));
    expect(ShellxPalette.error, const Color(0xFFFF8A94));
    expect(ShellxPalette.errorSoft, const Color(0xFF3D3440));
    expect(ShellxPalette.onError, const Color(0xFF2A0A0C));
    expect(ShellxPalette.errorHover, const Color(0xFFFF98A1));
    expect(ShellxPalette.noticeBg, const Color(0xFF453F50));
    expect(ShellxPalette.noticeText, const Color(0xFFFFD9DB));
    expect(ShellxPalette.noticeLine, const Color(0xFF5F4959));
    expect(ShellxPalette.inProgress, const Color(0xFF6EA8FE));
  });

  test('light palette (§5.4)', () {
    expect(ShellxLightPalette.page, const Color(0xFFEAEFF5));
    expect(ShellxLightPalette.surface, const Color(0xFFF5F7FA));
    expect(ShellxLightPalette.raised, const Color(0xFFFFFFFF));
    expect(ShellxLightPalette.inset, const Color(0xFFE0E6EE));
    expect(ShellxLightPalette.text, const Color(0xFF141A26));
    expect(ShellxLightPalette.textSecondary, const Color(0xFF4E586B));
    expect(ShellxLightPalette.placeholder, const Color(0xFF596376));
    expect(ShellxLightPalette.hairline, const Color(0x1A141A26));
    expect(ShellxLightPalette.handle, const Color(0x33141A26));
    expect(ShellxLightPalette.fieldOutline, const Color(0xFF717C92));
    expect(ShellxLightPalette.primary, const Color(0xFF1767AD));
    expect(ShellxLightPalette.primarySoft, const Color(0xFFDCE8F3));
    expect(ShellxLightPalette.ok, const Color(0xFF256B45));
    expect(ShellxLightPalette.okDot, const Color(0xFF2E8A57));
    expect(ShellxLightPalette.okSoft, const Color(0xFFE9F0EC));
    expect(ShellxLightPalette.warn, const Color(0xFF7F4C00));
    expect(ShellxLightPalette.warnSoft, const Color(0xFFF2EDE6));
    expect(ShellxLightPalette.error, const Color(0xFFB0202B));
    expect(ShellxLightPalette.errorSoft, const Color(0xFFF7E9EA));
    expect(ShellxLightPalette.scrim, const Color(0x73141A26));
    expect(ShellxLightPalette.keyboardBackground, const Color(0xFFD1D4DA));
    expect(ShellxLightPalette.keyboardKey, const Color(0xFFFFFFFF));
    expect(ShellxLightPalette.keyboardInk, const Color(0xFF000000));
    expect(ShellxLightPalette.keyboardLink, const Color(0xFF14598F));
    expect(ShellxLightPalette.keyboardError, const Color(0xFFA3161D));
    expect(ShellxLightPalette.glassFill, const Color(0xCCFFFFFF));
    expect(ShellxLightPalette.glassBorder, const Color(0x14141A26));
  });

  test('gradients (§5.5): stops and directions', () {
    void check(
      LinearGradient g,
      List<int> colors,
      Alignment begin,
      Alignment end,
    ) {
      expect(g.colors, [for (final c in colors) Color(c)]);
      expect(g.stops, isNull);
      expect(g.begin, begin);
      expect(g.end, end);
    }

    check(
      ShellxGradients.accent,
      [0xFF1A9BD8, 0xFF4E4AF2],
      Alignment.topLeft,
      Alignment.bottomRight,
    );
    check(
      ShellxGradients.accentStrong,
      [0xFF157CAD, 0xFF4E4AF2],
      Alignment.topLeft,
      Alignment.bottomRight,
    );
    check(
      ShellxGradients.wedge,
      [0xFF1A9BD8, 0xFF3C65CF],
      Alignment.topCenter,
      Alignment.bottomCenter,
    );
    check(
      ShellxGradients.glassBorderDark,
      [0x33FFFFFF, 0x0AFFFFFF],
      Alignment.topLeft,
      Alignment.bottomRight,
    );
    check(
      ShellxGradients.glassBorderLight,
      [0x14141A26, 0x05141A26],
      Alignment.topLeft,
      Alignment.bottomRight,
    );
    expect(ShellxGradients.hoverShade, const Color(0x14000000));
    expect(ShellxGradients.pressedShade, const Color(0x29000000));
  });

  test('terminal palette (§5.7)', () {
    expect(ShellxTerminalPalette.background, const Color(0xFF1C222E));
    expect(ShellxTerminalPalette.foreground, const Color(0xFFDDE3EC));
    expect(ShellxTerminalPalette.cursor, const Color(0xFFDDE3EC));
    expect(ShellxTerminalPalette.white, const Color(0xFFDDE3EC));
    expect(ShellxTerminalPalette.selection, const Color(0x4D34C8E8));
    expect(ShellxTerminalPalette.black, const Color(0xFF2C3547));
    expect(ShellxTerminalPalette.brightBlack, const Color(0xFF8590A6));
    expect(
      [
        ShellxTerminalPalette.red,
        ShellxTerminalPalette.green,
        ShellxTerminalPalette.yellow,
        ShellxTerminalPalette.blue,
        ShellxTerminalPalette.magenta,
        ShellxTerminalPalette.cyan,
      ],
      const [
        Color(0xFFF07178),
        Color(0xFF7ED492),
        Color(0xFFE9C46A),
        Color(0xFF82AAFF),
        Color(0xFFC792EA),
        Color(0xFF5FD4E2),
      ],
    );
    expect(
      [
        ShellxTerminalPalette.brightRed,
        ShellxTerminalPalette.brightGreen,
        ShellxTerminalPalette.brightYellow,
        ShellxTerminalPalette.brightBlue,
        ShellxTerminalPalette.brightMagenta,
        ShellxTerminalPalette.brightCyan,
        ShellxTerminalPalette.brightWhite,
      ],
      const [
        Color(0xFFFF8F95),
        Color(0xFF9BE3AB),
        Color(0xFFF2D68C),
        Color(0xFFA5C2FF),
        Color(0xFFDAB3F1),
        Color(0xFF8FE3EC),
        Color(0xFFFFFFFF),
      ],
    );
    expect(
      ShellxTerminalPalette.searchHitBackground,
      ShellxTerminalPalette.yellow,
    );
    expect(
      ShellxTerminalPalette.searchHitBackgroundCurrent,
      ShellxTerminalPalette.cyan,
    );
    expect(
      ShellxTerminalPalette.searchHitForeground,
      ShellxTerminalPalette.background,
    );
    expect(ShellxTerminalPalette.chrome, const Color(0xFF242C3B));
    expect(ShellxTerminalPalette.chrome2, const Color(0xFF2C3547));
    expect(ShellxTerminalPalette.line, const Color(0xFF343944));
    expect(ShellxTerminalPalette.dim, const Color(0xFF767A81));
    expect(ShellxTerminalPalette.muted, const Color(0xFFA7A9AE));
    expect(ShellxTerminalPalette.title, const Color(0xFFFFFFFF));
    expect(ShellxTerminalPalette.secondaryAction, const Color(0xFF323B4F));
    expect(ShellxTerminalPalette.onCyan, const Color(0xFF0E1A26));
    expect(ShellxTerminalPalette.noticeBackground, const Color(0xFF453F50));
    expect(ShellxTerminalPalette.noticeText, const Color(0xFFFFD9DB));
    expect(ShellxTerminalPalette.noticeBorder, const Color(0xFF5F4959));
    expect(
      ShellxTerminalPalette.driverBannerBackground,
      const Color(0xFF3B3937),
    );
    expect(ShellxTerminalPalette.driverBannerBorder, const Color(0xFF554B3A));
  });

  test('radii and spacing (§5.8)', () {
    expect(
      [
        ShellxRadii.tiny,
        ShellxRadii.control,
        ShellxRadii.card,
        ShellxRadii.sheet,
        ShellxRadii.pill,
      ],
      [6, 10, 16, 28, 999],
    );
    expect(
      [
        ShellxSpacing.s2,
        ShellxSpacing.s4,
        ShellxSpacing.s6,
        ShellxSpacing.s8,
        ShellxSpacing.s12,
        ShellxSpacing.s16,
        ShellxSpacing.s20,
        ShellxSpacing.s24,
        ShellxSpacing.s32,
        ShellxSpacing.s40,
        ShellxSpacing.s48,
      ],
      [2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48],
    );
  });

  test('shadows (§5.8), dark and light', () {
    List<(double, double, double, int)> shape(List<BoxShadow> s) => [
      for (final b in s)
        (b.offset.dx, b.offset.dy, b.blurRadius, b.color.toARGB32()),
    ];
    final dark = ShellxElevation.dark;
    expect(shape(dark.raised), [
      (4.0, 4.0, 12.0, 0x59000000),
      (-3.0, -3.0, 10.0, 0x0FFFFFFF),
    ]);
    expect(shape(dark.raisedSmall), [
      (2.0, 2.0, 6.0, 0x59000000),
      (-1.0, -1.0, 4.0, 0x0DFFFFFF),
    ]);
    expect(shape(dark.inset.shadows), [
      (2.0, 2.0, 6.0, 0x73000000),
      (-1.0, -1.0, 3.0, 0x0DFFFFFF),
    ]);
    expect(shape(dark.float1), [(0.0, 4.0, 16.0, 0x73000000)]);
    expect(shape(dark.float2), [(0.0, 16.0, 48.0, 0x8C000000)]);
    expect(shape(dark.cta), [(0.0, 8.0, 20.0, 0x664E4AF2)]);
    final light = ShellxElevation.light;
    expect(shape(light.raised), [
      (4.0, 4.0, 12.0, 0x40566A8C),
      (-4.0, -4.0, 12.0, 0xFFFFFFFF),
    ]);
    expect(shape(light.raisedSmall), [
      (2.0, 2.0, 6.0, 0x33566A8C),
      (-2.0, -2.0, 6.0, 0xFFFFFFFF),
    ]);
    expect(shape(light.inset.shadows), [
      (2.0, 2.0, 6.0, 0x33566A8C),
      (-1.0, -1.0, 3.0, 0xCCFFFFFF),
    ]);
    expect(shape(light.float1), [(0.0, 4.0, 16.0, 0x1F141A26)]);
    expect(shape(light.float2), [(0.0, 12.0, 32.0, 0x29141A26)]);
    expect(shape(light.cta), [(0.0, 6.0, 16.0, 0x404E4AF2)]);
    // The const lists are the same objects the instances hold.
    expect(
      identical(ShellxElevation.dark.float1, ShellxElevation.darkFloat1),
      isTrue,
    );
    expect(ShellxElevation.float1Elevation, 8);
    expect(ShellxElevation.float1ShadowColor, const Color(0x73000000));
  });

  test('motion (§5.8)', () {
    expect(ShellxDurations.fast, const Duration(milliseconds: 80));
    expect(ShellxDurations.press, const Duration(milliseconds: 100));
    expect(ShellxDurations.exit, const Duration(milliseconds: 120));
    expect(ShellxDurations.base, const Duration(milliseconds: 150));
    expect(ShellxDurations.toastIn, const Duration(milliseconds: 160));
    expect(ShellxDurations.slide, const Duration(milliseconds: 200));
    expect(ShellxDurations.sheet, const Duration(milliseconds: 250));
    expect(ShellxDurations.toastVisible, const Duration(seconds: 4));
    expect(ShellxDurations.toastVisibleError, const Duration(seconds: 6));
    expect(ShellxDurations.toastVisiblePhone, const Duration(seconds: 3));
    expect(ShellxDurations.tooltipWait, const Duration(milliseconds: 500));
    expect(ShellxDurations.scrollbarFade, const Duration(milliseconds: 800));
    expect(ShellxDurations.dragExpandDelay, const Duration(milliseconds: 600));
    expect(ShellxCurves.fast, Curves.easeOut);
    expect(ShellxCurves.press, Curves.easeOut);
    expect(ShellxCurves.exit, Curves.easeIn);
    expect(ShellxCurves.base, Curves.easeOutCubic);
    expect(ShellxCurves.slide, Curves.easeOutCubic);
  });

  testWidgets('reduced motion turns every duration to zero', (tester) async {
    late Duration normal, reduced;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          normal = ShellxDurations.of(context, ShellxDurations.slide);
          return MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                reduced = ShellxDurations.of(context, ShellxDurations.slide);
                return const SizedBox();
              },
            ),
          );
        },
      ),
    );
    expect(normal, const Duration(milliseconds: 200));
    expect(reduced, Duration.zero);
  });
}
````

`packages/shellx_design/test/contrast_test.dart`:

````dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_design/shellx_design.dart';

/// V2-5a §10.1: every contrast the spec measures (§5.3–§5.7), with its
/// floor (text 4.5:1, bold text from 15 px and everything that is not text
/// 3:1) and the value the spec gives (± 0.05: the spec rounds composites).
void main() {
  const inset = ShellxPalette.navy900;
  const page = ShellxPalette.navy850;
  const surface = ShellxPalette.navy750;
  const raised = ShellxPalette.navy700;

  /// [fg] on [bg]; an [fg] with alpha is composited over [bg] first.
  double ratio(Color fg, Color bg) =>
      contrastRatio(fg.a < 1 ? compositeOver(fg, bg) : fg, bg);

  void pair(String name, Color fg, Color bg, double measured, double floor) {
    final r = ratio(fg, bg);
    expect(r, closeTo(measured, 0.05), reason: '$name: $r');
    expect(r, greaterThanOrEqualTo(floor), reason: '$name: $r');
  }

  void onFour(String name, Color fg, List<double> measured, double floor) {
    final bgs = [inset, page, surface, raised];
    for (var i = 0; i < measured.length; i++) {
      pair('$name on layer $i', fg, bgs[i], measured[i], floor);
    }
  }

  group('dark (§5.3)', () {
    test('text on every layer: inset · page · surface · raised', () {
      onFour('white100', ShellxPalette.white100, [
        15.94,
        14.78,
        12.30,
        11.21,
      ], 4.5);
      onFour('white87', ShellxPalette.white87, [12.41, 11.51, 9.58, 8.73], 4.5);
      onFour('white75', ShellxPalette.white75, [9.92, 9.20, 7.65, 6.97], 4.5);
      onFour('white60', ShellxPalette.white60, [6.78, 6.28, 5.23, 4.76], 4.5);
      pair('white50 on inset', ShellxPalette.white50, inset, 4.99, 4.5);
      pair(
        'white60 on a bar',
        ShellxPalette.white60,
        ShellxPalette.navy825,
        5.96,
        4.5,
      );
      onFour('link', ShellxPalette.link, [6.59, 6.11, 5.09, 4.64], 4.5);
      onFour('cyan', ShellxPalette.cyan, [8.02, 7.44, 6.19, 5.64], 4.5);
    });

    test('layers read apart: hover < selected; pressed on a surface', () {
      pair('navy800 vs page', ShellxPalette.navy800, page, 1.12, 1);
      pair('navy700 vs page', ShellxPalette.navy700, page, 1.32, 1.25);
      pair('navy650 vs surface', ShellxPalette.navy650, surface, 1.25, 1);
    });

    test('field outline and focus ring ≥ 3:1 (not text)', () {
      for (final (bg, v) in [(inset, 4.13), (page, 3.83), (surface, 3.19)]) {
        pair('fieldOutline', ShellxPalette.fieldOutline, bg, v, 3);
      }
    });

    test('ink on accents and soft fills', () {
      pair(
        'onCyan on cyan',
        ShellxPalette.onCyan,
        ShellxPalette.cyan,
        8.85,
        4.5,
      );
      pair(
        'white87 on cyanSoft',
        ShellxPalette.white87,
        ShellxPalette.cyanSoft,
        8.72,
        4.5,
      );
      pair(
        'link on cyanSoft',
        ShellxPalette.link,
        ShellxPalette.cyanSoft,
        4.63,
        4.5,
      );
      pair('azure on page', ShellxPalette.azure, page, 5.03, 4.5);
      // Azure on a surface is for text from 18 px only.
      pair('azure on surface', ShellxPalette.azure, surface, 4.18, 3);
      expect(ratio(ShellxPalette.azure, surface), lessThan(4.5));
      expect(ratio(ShellxPalette.azure, raised), lessThan(4.5));
    });

    test('white on the gradient stops', () {
      pair(
        'accentLight',
        ShellxPalette.white100,
        ShellxPalette.accentLight,
        3.12,
        3,
      );
      pair(
        'accentStrongLight',
        ShellxPalette.white100,
        ShellxPalette.accentStrongLight,
        4.65,
        4.5,
      );
      pair('indigo', ShellxPalette.white100, ShellxPalette.indigo, 5.86, 4.5);
      pair(
        'wedgeBottom',
        ShellxPalette.white100,
        ShellxPalette.wedgeBottom,
        5.31,
        4.5,
      );
      // Why the stop moved (A20): the reference's cyan holds 1.99:1.
      expect(
        contrastRatio(ShellxPalette.white100, const Color(0xFF34C8E8)),
        closeTo(1.99, 0.05),
      );
    });

    test(
      'glass over the wedge\'s light end: textPrimary and up only (A29)',
      () {
        final glass = compositeOver(
          ShellxPalette.glassFill,
          ShellxPalette.accentLight,
        );
        for (final text in [
          ShellxPalette.white100,
          ShellxPalette.white87,
          ShellxPalette.white75,
        ]) {
          expect(contrastRatio(text, glass), greaterThanOrEqualTo(4.5));
        }
        expect(
          contrastRatio(ShellxPalette.white87, glass),
          closeTo(6.79, 0.05),
        );
        expect(
          contrastRatio(ShellxPalette.white75, glass),
          closeTo(5.42, 0.05),
        );
        expect(
          contrastRatio(ShellxPalette.white60, glass),
          closeTo(3.71, 0.05),
        );
        expect(contrastRatio(ShellxPalette.white60, glass), lessThan(4.5));
      },
    );
  });

  group('gradients (§5.5), 101 samples', () {
    test('accent: white ≥ 3:1 everywhere, also hovered and pressed', () {
      const g = ShellxGradients.accent;
      final white = ShellxPalette.onAccent;
      expect(minContrastOnGradient(g, white), closeTo(3.12, 0.05));
      expect(minContrastOnGradient(g, white), greaterThanOrEqualTo(3));
      expect(
        minContrastOnGradient(g, white, overlay: ShellxGradients.hoverShade),
        closeTo(3.63, 0.05),
      );
      expect(
        minContrastOnGradient(g, white, overlay: ShellxGradients.pressedShade),
        closeTo(4.29, 0.05),
      );
    });

    test(
      'accentStrong: white ≥ 4.5:1 everywhere, also hovered and pressed',
      () {
        const g = ShellxGradients.accentStrong;
        final white = ShellxPalette.onAccent;
        expect(minContrastOnGradient(g, white), closeTo(4.65, 0.05));
        expect(minContrastOnGradient(g, white), greaterThanOrEqualTo(4.5));
        expect(
          minContrastOnGradient(g, white, overlay: ShellxGradients.hoverShade),
          closeTo(5.34, 0.05),
        );
        expect(
          minContrastOnGradient(
            g,
            white,
            overlay: ShellxGradients.pressedShade,
          ),
          closeTo(6.15, 0.05),
        );
        // A white overlay would drop it under 4.5 (why hover shades black).
        expect(
          minContrastOnGradient(g, white, overlay: const Color(0x14FFFFFF)),
          lessThan(4.5),
        );
      },
    );

    test('wedge: white ≥ 3:1', () {
      expect(
        minContrastOnGradient(ShellxGradients.wedge, ShellxPalette.white100),
        closeTo(3.12, 0.05),
      );
      expect(
        minContrastOnGradient(ShellxGradients.wedge, ShellxPalette.white100),
        greaterThanOrEqualTo(3),
      );
    });

    test('samples include both ends', () {
      const g = LinearGradient(colors: [Color(0xFF000000), Color(0xFFFFFFFF)]);
      expect(minContrastOnGradient(g, const Color(0xFF000000)), 1);
      expect(minContrastOnGradient(g, const Color(0xFFFFFFFF)), 1);
    });
  });

  group('status, dark (§5.6)', () {
    test('on every layer and on their soft fills', () {
      onFour('ok', ShellxPalette.ok, [8.56, 7.93, 6.60, 6.02], 4.5);
      onFour('warn', ShellxPalette.warn, [9.06, 8.40, 6.99, 6.37], 4.5);
      onFour('error', ShellxPalette.error, [7.07, 6.55, 5.46, 4.97], 4.5);
      onFour('inProgress', ShellxPalette.inProgress, [
        6.60,
        6.12,
        5.09,
        4.64,
      ], 4.5);
      pair('ok on okSoft', ShellxPalette.ok, ShellxPalette.okSoft, 6.14, 4.5);
      pair(
        'warn on warnSoft',
        ShellxPalette.warn,
        ShellxPalette.warnSoft,
        6.53,
        4.5,
      );
      pair(
        'error on errorSoft',
        ShellxPalette.error,
        ShellxPalette.errorSoft,
        5.28,
        4.5,
      );
      pair(
        'onError on error',
        ShellxPalette.onError,
        ShellxPalette.error,
        8.12,
        4.5,
      );
      pair(
        'onError on errorHover',
        ShellxPalette.onError,
        ShellxPalette.errorHover,
        8.94,
        4.5,
      );
      pair(
        'noticeText on noticeBg',
        ShellxPalette.noticeText,
        ShellxPalette.noticeBg,
        7.79,
        4.5,
      );
      // A23: the old red failed on a surface.
      expect(
        contrastRatio(const Color(0xFFF07178), surface),
        closeTo(4.30, 0.05),
      );
    });
  });

  group('light (§5.4)', () {
    const l = (
      inset: ShellxLightPalette.inset,
      page: ShellxLightPalette.page,
      surface: ShellxLightPalette.surface,
      raised: ShellxLightPalette.raised,
    );
    void onLight(String name, Color fg, List<double> measured, double floor) {
      final bgs = [l.inset, l.page, l.surface, l.raised];
      for (var i = 0; i < measured.length; i++) {
        pair('$name on light layer $i', fg, bgs[i], measured[i], floor);
      }
    }

    test('text, status and the primary on every layer', () {
      onLight('text', ShellxLightPalette.text, [
        13.87,
        15.07,
        16.23,
        17.42,
      ], 4.5);
      onLight('textSecondary', ShellxLightPalette.textSecondary, [
        5.70,
        6.19,
        6.67,
        7.16,
      ], 4.5);
      onLight('primary', ShellxLightPalette.primary, [
        4.67,
        5.07,
        5.47,
        5.87,
      ], 4.5);
      onLight('ok', ShellxLightPalette.ok, [5.12, 5.56, 5.99, 6.43], 4.5);
      onLight('warn', ShellxLightPalette.warn, [5.70, 6.19, 6.66, 7.15], 4.5);
      onLight('error', ShellxLightPalette.error, [5.42, 5.88, 6.34, 6.80], 4.5);
      onLight('fieldOutline', ShellxLightPalette.fieldOutline, [
        3.34,
        3.63,
        3.91,
      ], 3);
      pair(
        'placeholder on inset',
        ShellxLightPalette.placeholder,
        l.inset,
        4.82,
        4.5,
      );
    });

    test('ink on fills and on the keyboard', () {
      pair(
        'white on primary',
        ShellxPalette.white100,
        ShellxLightPalette.primary,
        5.87,
        4.5,
      );
      pair(
        'primary on primarySoft',
        ShellxLightPalette.primary,
        ShellxLightPalette.primarySoft,
        4.72,
        4.5,
      );
      pair(
        'ok on okSoft',
        ShellxLightPalette.ok,
        ShellxLightPalette.okSoft,
        5.55,
        4.5,
      );
      pair('okDot on page', ShellxLightPalette.okDot, l.page, 3.72, 3);
      pair(
        'warn on warnSoft',
        ShellxLightPalette.warn,
        ShellxLightPalette.warnSoft,
        6.14,
        4.5,
      );
      pair(
        'error on errorSoft',
        ShellxLightPalette.error,
        ShellxLightPalette.errorSoft,
        5.76,
        4.5,
      );
      pair(
        'white on error',
        ShellxPalette.white100,
        ShellxLightPalette.error,
        6.80,
        4.5,
      );
      pair(
        'keyboard link',
        ShellxLightPalette.keyboardLink,
        ShellxLightPalette.keyboardBackground,
        4.95,
        4.5,
      );
      pair(
        'keyboard error',
        ShellxLightPalette.keyboardError,
        ShellxLightPalette.keyboardBackground,
        5.26,
        4.5,
      );
      pair(
        'keyboard secondary',
        ShellxLightPalette.textSecondary,
        ShellxLightPalette.keyboardBackground,
        4.82,
        4.5,
      );
    });

    test('light glass over the wedge\'s light end', () {
      final glass = compositeOver(
        ShellxLightPalette.glassFill,
        ShellxPalette.accentLight,
      );
      expect(
        contrastRatio(ShellxLightPalette.text, glass),
        closeTo(14.05, 0.05),
      );
      expect(
        contrastRatio(ShellxLightPalette.textSecondary, glass),
        closeTo(5.78, 0.05),
      );
    });
  });

  group('terminal (§5.7)', () {
    const bg = ShellxTerminalPalette.background;
    test('foreground, ANSI and their bright forms ≥ 4.5:1', () {
      pair('foreground', ShellxTerminalPalette.foreground, bg, 12.35, 4.5);
      pair('brightBlack', ShellxTerminalPalette.brightBlack, bg, 4.96, 4.5);
      for (final c in [
        ShellxTerminalPalette.red,
        ShellxTerminalPalette.green,
        ShellxTerminalPalette.yellow,
        ShellxTerminalPalette.blue,
        ShellxTerminalPalette.magenta,
        ShellxTerminalPalette.cyan,
        ShellxTerminalPalette.brightRed,
        ShellxTerminalPalette.brightGreen,
        ShellxTerminalPalette.brightYellow,
        ShellxTerminalPalette.brightBlue,
        ShellxTerminalPalette.brightMagenta,
        ShellxTerminalPalette.brightCyan,
        ShellxTerminalPalette.brightWhite,
      ]) {
        expect(contrastRatio(c, bg), greaterThanOrEqualTo(5.5), reason: '$c');
      }
      expect(contrastRatio(ShellxTerminalPalette.red, bg), closeTo(5.57, 0.05));
      expect(
        contrastRatio(ShellxTerminalPalette.brightWhite, bg),
        closeTo(15.94, 0.05),
      );
      // The old bright black fails on the new background.
      expect(contrastRatio(const Color(0xFF6C8288), bg), closeTo(3.94, 0.05));
    });

    test('text on the selection; a black block is visible', () {
      final selected = compositeOver(ShellxTerminalPalette.selection, bg);
      expect(
        contrastRatio(ShellxTerminalPalette.foreground, selected),
        closeTo(6.43, 0.05),
      );
      expect(
        contrastRatio(ShellxTerminalPalette.foreground, selected),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(ShellxTerminalPalette.black, bg),
        closeTo(1.30, 0.05),
      );
    });

    test('the phone\'s chrome', () {
      pair(
        'muted on chrome',
        ShellxTerminalPalette.muted,
        ShellxTerminalPalette.chrome,
        5.96,
        4.5,
      );
      pair(
        'muted on chrome2',
        ShellxTerminalPalette.muted,
        ShellxTerminalPalette.chrome2,
        5.23,
        4.5,
      );
      pair(
        'onCyan on cyan',
        ShellxTerminalPalette.onCyan,
        ShellxTerminalPalette.cyan,
        10.05,
        4.5,
      );
    });
  });
}
````

- [ ] **Step 2: Run them to see them fail**

````bash
cd packages/shellx_design && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/palette_test.dart test/contrast_test.dart
````

Expected: compilation fails (`ShellxPalette` … undefined).

- [ ] **Step 3: Write the tokens**

`packages/shellx_design/lib/src/palette.dart`:

````dart
import 'package:flutter/painting.dart';

/// V2-5a §5.3, §5.6: the dark palette both apps share (the desktop, and the
/// phone in dark mode). Navy layers from the reference, text as solid
/// colours (white 100/87/75/60/50/38 % over the page, A18) so contrast can
/// be computed on any surface, hairlines as alpha (A19).
abstract final class ShellxPalette {
  // Navy layers (A17), darkest first.
  /// Inset: fields, tracks, the terminal, the desktop pane.
  static const Color navy900 = Color(0xFF1C222E);

  /// The phone's page; the desktop sidebar.
  static const Color navy850 = Color(0xFF222834);

  /// Bars: the phone's bottom bar and terminal chrome.
  static const Color navy825 = Color(0xFF242C3B);

  /// Hover on the page; pushed (a pressed raised element).
  static const Color navy800 = Color(0xFF28303F);

  /// Surfaces: cards, sheets, dialogs, menus, toasts.
  static const Color navy750 = Color(0xFF2C3547);

  /// Raised or selected; tooltips.
  static const Color navy700 = Color(0xFF323B4F);

  /// Pressed on the page; hover on a surface.
  static const Color navy650 = Color(0xFF38445A);

  /// Pressed on a surface.
  static const Color navy600 = Color(0xFF3F4B62);

  // Text (A18): solid, never alpha.
  static const Color white100 = Color(0xFFFFFFFF);
  static const Color white87 = Color(0xFFE2E3E5);
  static const Color white75 = Color(0xFFCACCD1);
  static const Color white60 = Color(0xFFA7A9AE);

  /// Placeholder, on [navy900] only.
  static const Color white50 = Color(0xFF8E9096);

  /// Decoration only, never text.
  static const Color white38 = Color(0xFF767A81);

  // Lines (A19).
  /// Dividers: white 8 %.
  static const Color hairline = Color(0x14FFFFFF);

  /// Decorative borders: white 10 %.
  static const Color hairlineStrong = Color(0x1AFFFFFF);

  /// A sheet's drag handle: white 20 %.
  static const Color handle = Color(0x33FFFFFF);

  /// A field's outline: solid, ≥ 3:1 on inset, page and surface.
  static const Color fieldOutline = Color(0xFF76829C);

  // Accents (A21, A22).
  /// The single accent: focus, selection bar, running dot, an icon that is
  /// on, progress.
  static const Color cyan = Color(0xFF34C8E8);

  /// Ink on [cyan].
  static const Color onCyan = Color(0xFF0E1A26);

  /// Tinted background: badges, a selected list item.
  static const Color cyanSoft = Color(0xFF253E4D);

  /// Decoration, or text from 18 px on the page.
  static const Color azure = Color(0xFF3D9CEA);

  /// Links and text buttons.
  static const Color link = Color(0xFF5EADEE);

  /// Text and icons on a gradient.
  static const Color onAccent = Color(0xFFFFFFFF);

  // Gradient stops (A20, A30).
  static const Color accentLight = Color(0xFF1A9BD8);
  static const Color accentStrongLight = Color(0xFF157CAD);
  static const Color indigo = Color(0xFF4E4AF2);
  static const Color wedgeBottom = Color(0xFF3C65CF);

  // Status (§5.6).
  /// Also the online dot.
  static const Color ok = Color(0xFF5ED39C);
  static const Color okSoft = Color(0xFF293D40);
  static const Color warn = Color(0xFFF5B94E);
  static const Color warnSoft = Color(0xFF3B3937);
  static const Color warnLine = Color(0xFF554B3A);
  static const Color error = Color(0xFFFF8A94);
  static const Color errorSoft = Color(0xFF3D3440);
  static const Color onError = Color(0xFF2A0A0C);
  static const Color errorHover = Color(0xFFFF98A1);
  static const Color noticeBg = Color(0xFF453F50);
  static const Color noticeText = Color(0xFFFFD9DB);
  static const Color noticeLine = Color(0xFF5F4959);
  static const Color inProgress = Color(0xFF6EA8FE);

  // Others.
  /// Behind dialogs and sheets.
  static const Color scrim = Color(0x99000000);
  static const Color scrollThumb = Color(0xFF3D424C);
  static const Color scrollThumbHover = Color(0xFF4E535D);

  /// The phone's extra-keys bar follows the system keyboard (as before).
  static const Color keyboardBackground = Color(0xFF1E1F21);
  static const Color keyboardKey = Color(0xFF47484B);
  static const Color keyboardInk = Color(0xFFFFFFFF);

  /// Glass ([navy700] at 80 %, A29).
  static const Color glassFill = Color(0xCC323B4F);
}

/// V2-5a §5.4: the phone's light variant, same navy and azure hues (A25).
abstract final class ShellxLightPalette {
  static const Color page = Color(0xFFEAEFF5);
  static const Color surface = Color(0xFFF5F7FA);
  static const Color raised = Color(0xFFFFFFFF);

  /// Inset and fields; also pushed.
  static const Color inset = Color(0xFFE0E6EE);
  static const Color text = Color(0xFF141A26);
  static const Color textSecondary = Color(0xFF4E586B);

  /// On [inset].
  static const Color placeholder = Color(0xFF596376);

  /// Dividers and decorative borders: navy 10 %.
  static const Color hairline = Color(0x1A141A26);
  static const Color handle = Color(0x33141A26);
  static const Color fieldOutline = Color(0xFF717C92);

  /// Solid: links, an icon that is on, focus, the key accent.
  static const Color primary = Color(0xFF1767AD);
  static const Color primarySoft = Color(0xFFDCE8F3);
  static const Color ok = Color(0xFF256B45);
  static const Color okDot = Color(0xFF2E8A57);
  static const Color okSoft = Color(0xFFE9F0EC);
  static const Color warn = Color(0xFF7F4C00);
  static const Color warnSoft = Color(0xFFF2EDE6);
  static const Color error = Color(0xFFB0202B);
  static const Color errorSoft = Color(0xFFF7E9EA);
  static const Color scrim = Color(0x73141A26);
  static const Color keyboardBackground = Color(0xFFD1D4DA);
  static const Color keyboardKey = Color(0xFFFFFFFF);
  static const Color keyboardInk = Color(0xFF000000);
  static const Color keyboardLink = Color(0xFF14598F);
  static const Color keyboardError = Color(0xFFA3161D);
  static const Color glassFill = Color(0xCCFFFFFF);
  static const Color glassBorder = Color(0x14141A26);
}
````

`packages/shellx_design/lib/src/gradients.dart`:

````dart
import 'package:flutter/painting.dart';

import 'palette.dart';

/// V2-5a §5.5. Which one carries text (A20):
/// - any regular text, or bold text under 15 px: [accentStrong];
/// - bold (≥ 600) from 15 px, icons, areas without text: [accent].
/// Hover and pressed shade the gradient black ([hoverShade], [pressedShade]);
/// white over it would drop the contrast.
abstract final class ShellxGradients {
  /// White ≥ 3.12:1 everywhere: icons, bold text from 15 px, decoration.
  static const LinearGradient accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ShellxPalette.accentLight, ShellxPalette.indigo],
  );

  /// White ≥ 4.65:1 everywhere: every other text.
  static const LinearGradient accentStrong = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ShellxPalette.accentStrongLight, ShellxPalette.indigo],
  );

  /// The corner wedge (A30), top to bottom.
  static const LinearGradient wedge = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [ShellxPalette.accentLight, ShellxPalette.wedgeBottom],
  );

  /// Glass's 1 px border, dark: white 20 % to 4 %.
  static const LinearGradient glassBorderDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x33FFFFFF), Color(0x0AFFFFFF)],
  );

  /// Glass's 1 px border, light: navy 8 % to 2 %.
  static const LinearGradient glassBorderLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x14141A26), Color(0x05141A26)],
  );

  /// Hover over a gradient: black 8 %.
  static const Color hoverShade = Color(0x14000000);

  /// Pressed over a gradient: black 16 %.
  static const Color pressedShade = Color(0x29000000);
}
````

`packages/shellx_design/lib/src/radii.dart`:

````dart
/// V2-5a A27, §5.8: corner radii.
abstract final class ShellxRadii {
  /// Small marks: a 16 px badge, a key cap, the 22 px rename field.
  static const double tiny = 6;

  /// Buttons, chips, icon buttons.
  static const double control = 10;

  /// Cards and fields.
  static const double card = 16;

  /// Sheets, dialogs, large panels.
  static const double sheet = 28;

  /// Tags.
  static const double pill = 999;
}
````

`packages/shellx_design/lib/src/spacing.dart`:

````dart
/// V2-5a §5.8: the spacing scale (px).
abstract final class ShellxSpacing {
  static const double s2 = 2, s4 = 4, s6 = 6, s8 = 8, s12 = 12, s16 = 16;
  static const double s20 = 20, s24 = 24, s32 = 32, s40 = 40, s48 = 48;
}
````

`packages/shellx_design/lib/src/elevation.dart`:

````dart
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Inner shadows (A28): [BoxShadow] has no inset, so [ShellxInsetBox] paints
/// these inside its shape.
@immutable
final class ShellxInsetShadow {
  const ShellxInsetShadow(this.shadows);

  final List<BoxShadow> shadows;
}

/// V2-5a A28, §5.8: soft neumorphism. Raised = a dark shadow bottom-right
/// and a light one top-left; pressed loses both. Alpha values, so they
/// work on every navy layer. Each list is also a `static const` of its
/// own, for the desktop's `static const` tokens.
@immutable
final class ShellxElevation {
  const ShellxElevation._({
    required this.raised,
    required this.raisedSmall,
    required this.float1,
    required this.float2,
    required this.cta,
    required this.inset,
  });

  /// The phone's raised elements.
  final List<BoxShadow> raised;

  /// The desktop's raised elements; a selected segment.
  final List<BoxShadow> raisedSmall;

  /// Menus, toasts, tooltips.
  final List<BoxShadow> float1;

  /// Dialogs, sheets.
  final List<BoxShadow> float2;

  /// The phone's main button: one per screen.
  final List<BoxShadow> cta;

  /// The phone's fields, segmented tracks, slider tracks.
  final ShellxInsetShadow inset;

  static const ShellxElevation dark = ShellxElevation._(
    raised: darkRaised,
    raisedSmall: darkRaisedSmall,
    float1: darkFloat1,
    float2: darkFloat2,
    cta: darkCta,
    inset: ShellxInsetShadow(darkInset),
  );

  static const ShellxElevation light = ShellxElevation._(
    raised: lightRaised,
    raisedSmall: lightRaisedSmall,
    float1: lightFloat1,
    float2: lightFloat2,
    cta: lightCta,
    inset: ShellxInsetShadow(lightInset),
  );

  static const List<BoxShadow> darkRaised = [
    BoxShadow(offset: Offset(4, 4), blurRadius: 12, color: Color(0x59000000)),
    BoxShadow(offset: Offset(-3, -3), blurRadius: 10, color: Color(0x0FFFFFFF)),
  ];
  static const List<BoxShadow> darkRaisedSmall = [
    BoxShadow(offset: Offset(2, 2), blurRadius: 6, color: Color(0x59000000)),
    BoxShadow(offset: Offset(-1, -1), blurRadius: 4, color: Color(0x0DFFFFFF)),
  ];
  static const List<BoxShadow> darkInset = [
    BoxShadow(offset: Offset(2, 2), blurRadius: 6, color: Color(0x73000000)),
    BoxShadow(offset: Offset(-1, -1), blurRadius: 3, color: Color(0x0DFFFFFF)),
  ];

  /// The desktop's old `e1`.
  static const List<BoxShadow> darkFloat1 = [
    BoxShadow(offset: Offset(0, 4), blurRadius: 16, color: Color(0x73000000)),
  ];

  /// The desktop's old `e2`.
  static const List<BoxShadow> darkFloat2 = [
    BoxShadow(offset: Offset(0, 16), blurRadius: 48, color: Color(0x8C000000)),
  ];
  static const List<BoxShadow> darkCta = [
    BoxShadow(offset: Offset(0, 8), blurRadius: 20, color: Color(0x664E4AF2)),
  ];

  static const List<BoxShadow> lightRaised = [
    BoxShadow(offset: Offset(4, 4), blurRadius: 12, color: Color(0x40566A8C)),
    BoxShadow(offset: Offset(-4, -4), blurRadius: 12, color: Color(0xFFFFFFFF)),
  ];
  static const List<BoxShadow> lightRaisedSmall = [
    BoxShadow(offset: Offset(2, 2), blurRadius: 6, color: Color(0x33566A8C)),
    BoxShadow(offset: Offset(-2, -2), blurRadius: 6, color: Color(0xFFFFFFFF)),
  ];
  static const List<BoxShadow> lightInset = [
    BoxShadow(offset: Offset(2, 2), blurRadius: 6, color: Color(0x33566A8C)),
    BoxShadow(offset: Offset(-1, -1), blurRadius: 3, color: Color(0xCCFFFFFF)),
  ];
  static const List<BoxShadow> lightFloat1 = [
    BoxShadow(offset: Offset(0, 4), blurRadius: 16, color: Color(0x1F141A26)),
  ];
  static const List<BoxShadow> lightFloat2 = [
    BoxShadow(offset: Offset(0, 12), blurRadius: 32, color: Color(0x29141A26)),
  ];
  static const List<BoxShadow> lightCta = [
    BoxShadow(offset: Offset(0, 6), blurRadius: 16, color: Color(0x404E4AF2)),
  ];

  /// The desktop's `e1Elevation`: [darkFloat1] for Material surfaces that
  /// only take an elevation (the menu of `showMenu`).
  static const double float1Elevation = 8;

  /// The colour of [darkFloat1].
  static const Color float1ShadowColor = Color(0x73000000);
}
````

`packages/shellx_design/lib/src/motion.dart`:

````dart
import 'package:flutter/widgets.dart';

/// V2-5a §5.8. Use [of] so reduced motion turns every duration to zero.
abstract final class ShellxDurations {
  /// Hover, colour.
  static const Duration fast = Duration(milliseconds: 80);

  /// The phone's press.
  static const Duration press = Duration(milliseconds: 100);
  static const Duration exit = Duration(milliseconds: 120);

  /// A dialog coming in, a fade.
  static const Duration base = Duration(milliseconds: 150);
  static const Duration toastIn = Duration(milliseconds: 160);

  /// A segment's tile, the bottom bar's active tile.
  static const Duration slide = Duration(milliseconds: 200);
  static const Duration sheet = Duration(milliseconds: 250);

  /// How long a desktop toast stays: 4 s, an error 6 s.
  static const Duration toastVisible = Duration(seconds: 4);
  static const Duration toastVisibleError = Duration(seconds: 6);

  /// How long a phone toast stays.
  static const Duration toastVisiblePhone = Duration(seconds: 3);
  static const Duration tooltipWait = Duration(milliseconds: 500);
  static const Duration scrollbarFade = Duration(milliseconds: 800);

  /// Hovering a dragged tab over a collapsed header expands it.
  static const Duration dragExpandDelay = Duration(milliseconds: 600);

  /// [duration], or zero when the platform asks for reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// V2-5a §5.8: the curves that go with [ShellxDurations].
abstract final class ShellxCurves {
  static const Curve fast = Curves.easeOut;
  static const Curve press = Curves.easeOut;
  static const Curve exit = Curves.easeIn;
  static const Curve base = Curves.easeOutCubic;
  static const Curve slide = Curves.easeOutCubic;
}
````

`packages/shellx_design/lib/src/terminal_palette.dart`:

````dart
import 'package:flutter/painting.dart';

/// V2-5a A24, §5.7: the default "ShellX" terminal palette and the phone's
/// terminal chrome, dark in both phone modes. The colours only: each app
/// builds its own xterm `TerminalTheme` from them (the package does not
/// depend on xterm). A user's own theme keeps its colours; a key it leaves
/// out takes these.
abstract final class ShellxTerminalPalette {
  /// The desktop's `bgTerminal`.
  static const Color background = Color(0xFF1C222E);
  static const Color foreground = Color(0xFFDDE3EC);
  static const Color cursor = foreground;

  /// Cyan 30 %.
  static const Color selection = Color(0x4D34C8E8);

  // ANSI 0–7.
  /// A visible block on [background] (1.30:1).
  static const Color black = Color(0xFF2C3547);
  static const Color red = Color(0xFFF07178);
  static const Color green = Color(0xFF7ED492);
  static const Color yellow = Color(0xFFE9C46A);
  static const Color blue = Color(0xFF82AAFF);
  static const Color magenta = Color(0xFFC792EA);
  static const Color cyan = Color(0xFF5FD4E2);
  static const Color white = foreground;

  // ANSI 8–15.
  /// 4.96:1 on [background] (the old `#6C8288` is 3.94:1 there).
  static const Color brightBlack = Color(0xFF8590A6);
  static const Color brightRed = Color(0xFFFF8F95);
  static const Color brightGreen = Color(0xFF9BE3AB);
  static const Color brightYellow = Color(0xFFF2D68C);
  static const Color brightBlue = Color(0xFFA5C2FF);
  static const Color brightMagenta = Color(0xFFDAB3F1);
  static const Color brightCyan = Color(0xFF8FE3EC);
  static const Color brightWhite = Color(0xFFFFFFFF);

  static const Color searchHitBackground = yellow;
  static const Color searchHitBackgroundCurrent = cyan;
  static const Color searchHitForeground = background;

  // The phone's terminal chrome.
  static const Color chrome = Color(0xFF242C3B);
  static const Color chrome2 = Color(0xFF2C3547);

  /// Lines in the chrome (solid).
  static const Color line = Color(0xFF343944);

  /// Decoration only.
  static const Color dim = Color(0xFF767A81);

  /// Secondary text on the chrome: 5.96:1 on [chrome], 5.23:1 on [chrome2].
  static const Color muted = Color(0xFFA7A9AE);
  static const Color title = Color(0xFFFFFFFF);

  /// "Đóng tab" on the session-ended card.
  static const Color secondaryAction = Color(0xFF323B4F);

  /// Text on a [cyan] button.
  static const Color onCyan = Color(0xFF0E1A26);

  /// A floating notice (`session_limit`).
  static const Color noticeBackground = Color(0xFF453F50);
  static const Color noticeText = Color(0xFFFFD9DB);
  static const Color noticeBorder = Color(0xFF5F4959);

  /// "Máy tính đang dùng terminal này" over a desktop terminal (text:
  /// [yellow]).
  static const Color driverBannerBackground = Color(0xFF3B3937);
  static const Color driverBannerBorder = Color(0xFF554B3A);
}
````

`packages/shellx_design/lib/src/contrast.dart`:

````dart
import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// WCAG 2.x contrast ratio of two opaque colours: 1 to 21.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [foreground] painted over the opaque [background].
Color compositeOver(Color foreground, Color background) =>
    Color.alphaBlend(foreground, background);

/// The lowest contrast of [text] over [gradient], sampled at [samples]
/// evenly spaced points and interpolated in sRGB as Flutter does; with
/// [overlay] (a hover or pressed shade) painted over the gradient first.
double minContrastOnGradient(
  LinearGradient gradient,
  Color text, {
  int samples = 101,
  Color? overlay,
}) {
  final colors = gradient.colors;
  final stops =
      gradient.stops ??
      [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)];
  Color at(double t) {
    if (t <= stops.first) return colors.first;
    for (var i = 1; i < stops.length; i++) {
      if (t <= stops[i]) {
        final span = stops[i] - stops[i - 1];
        final local = span == 0 ? 0.0 : (t - stops[i - 1]) / span;
        return Color.lerp(colors[i - 1], colors[i], local)!;
      }
    }
    return colors.last;
  }

  var lowest = double.infinity;
  for (var i = 0; i < samples; i++) {
    var colour = at(i / (samples - 1));
    if (overlay != null) colour = compositeOver(overlay, colour);
    lowest = math.min(lowest, contrastRatio(text, colour));
  }
  return lowest;
}
````

`packages/shellx_design/lib/shellx_design.dart`:

````dart
/// ShellX's shared design system (V2-5a): tokens, type, icons and the shared
/// widgets. Both apps reach it through their own adapters (desktop
/// `ui/theme`, phone `core/design`).
library;

export 'src/contrast.dart';
export 'src/elevation.dart';
export 'src/gradients.dart';
export 'src/motion.dart';
export 'src/palette.dart';
export 'src/radii.dart';
export 'src/spacing.dart';
export 'src/system_font.dart';
export 'src/terminal_palette.dart';
export 'src/type_scale.dart';
````

- [ ] **Step 4: Run the package's checks**

````bash
cd packages/shellx_design && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
````

Expected: `No issues found!`; `+47: All tests passed!`.

- [ ] **Step 5: Commit**

````bash
git add packages/shellx_design
git commit -m "feat(v2-design): the shared tokens — navy palette and its light variant, contrast-fixed gradients, radii, spacing, neumorphic shadows, motion, the terminal palette, contrast helpers

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
````

### Task 4: The package's type scale, `shellxWeight`, and the shared widgets

Spec §6.5 (both scales, line heights in px kept), A35 (`shellxWeight`), A36 (`desktopWindowsBoost`), R3, R5, and §7's shared widgets (A28 inset, A29 glass, A30 wedge, the bottom bar's slanted tile, A38's gradient layer).

**Files:**
- Modify: `packages/shellx_design/lib/src/type_scale.dart` (whole file below), `lib/shellx_design.dart`
- Create: `packages/shellx_design/lib/src/widgets/{inset_box,wedge,glass,slant_border,gradient_layer}.dart`
- Modify: `packages/shellx_design/test/fonts_test.dart` (whole file below); Create: `test/widgets_test.dart`

**Interfaces:**
- Consumes: Task 3's `ShellxPalette`, `ShellxLightPalette`, `ShellxGradients`, `ShellxRadii`, `ShellxElevation`, `ShellxInsetShadow`.
- Produces:
  - `TextStyle shellxWeight(TextStyle style, FontWeight weight)`; `TextTheme shellxWeightedTextTheme(TextTheme theme)`.
  - `ShellxTypeScale.desktopWindowsBoost` (`0`), `desktopFor(TextStyle, TargetPlatform, {double boost})`, `desktopCaption`, `desktopSmall`, `desktopBody`, `desktopBodyStrong`, `desktopLabel`, `desktopDialogBody`, `desktopEmptyTitle`, `desktopDialogTitle`, `desktopDisplay`, `desktopCode`; `mobileDisplay56`, `mobileDisplay42`, `mobileDisplay36`, `mobileDisplay32`, `mobileHeading28`, `mobileHeading26`, `mobileHeading24`, `mobileHeading20`, `mobileTitle`, `mobileSubHeader`, `mobileSubHeader15`, `mobileParagraph`, `mobileParagraph13`, `mobileMetadata12`, `mobileMetadata11`, `mobileMetadata10`, `mobileMetadata8`, `mobileAppBarTitle` (all `const TextStyle`, no colour, no family).
  - `ShellxInsetBox({required Color color, required ShellxInsetShadow shadow, required BorderRadius borderRadius, BorderSide? border, EdgeInsetsGeometry? padding, Widget? child})`, `ShellxInsetPainter`.
  - `ShellxWedge({ShellxWedgeCorner corner = topRight, double widthFactor = 0.45, double heightFactor = 0.7})`, `enum ShellxWedgeCorner`, `ShellxWedgePainter.points(Size)`.
  - `ShellxGlass({required Widget child, bool blur = true, BorderRadius borderRadius = 16, EdgeInsetsGeometry? padding})`, `ShellxGlass.sigma` (16), `ShellxGradientBorderPainter`.
  - `ShellxSlantBorder({BorderSide side, double radius = 10, double slant = 4})` (an `OutlinedBorder`).
  - `ButtonLayerBuilder shellxGradientLayer({required LinearGradient gradient, required BorderRadius borderRadius, required double disabledOpacity})`.

- [ ] **Step 1: Write the failing tests**

`packages/shellx_design/test/fonts_test.dart` (whole file):

````dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_design/shellx_design.dart';

void main() {
  test('families by platform (§6.1): SF Mono only on iOS and macOS', () {
    for (final p in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      expect(ShellxFonts.isApple(p), isTrue);
      expect(ShellxFonts.uiFamily(p), 'SF Mono');
      expect(ShellxFonts.uiFallback(p), ['JetBrainsMono']);
    }
    for (final p in [
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.fuchsia,
    ]) {
      expect(ShellxFonts.isApple(p), isFalse);
      expect(ShellxFonts.uiFamily(p), 'JetBrainsMono');
      expect(ShellxFonts.uiFallback(p), isEmpty);
    }
    expect(ShellxFonts.systemMono, 'SF Mono');
    expect(ShellxFonts.bundledMono, 'JetBrainsMono');
    expect(ShellxFonts.bundledMonoLight, 'JetBrainsMonoLight');
  });

  test('shellxWeight sets the weight and the wght axis together (A35)', () {
    const base = TextStyle(
      fontSize: 12,
      fontVariations: [FontVariation('wght', 400)],
    );
    for (final w in [
      FontWeight.w300,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
    ]) {
      final s = shellxWeight(base, w);
      expect(s.fontWeight, w);
      expect(s.fontVariations, [FontVariation('wght', w.value.toDouble())]);
      expect(s.fontSize, 12);
    }
  });

  test('a theme\'s text styles carry wght = their weight', () {
    final theme = shellxWeightedTextTheme(
      ThemeData(useMaterial3: true).textTheme,
    );
    for (final style in [
      theme.displayLarge,
      theme.headlineSmall,
      theme.titleLarge,
      theme.titleMedium,
      theme.bodyLarge,
      theme.bodyMedium,
      theme.bodySmall,
      theme.labelLarge,
      theme.labelSmall,
    ]) {
      final weight = style!.fontWeight ?? FontWeight.w400;
      expect(style.fontVariations, [
        FontVariation('wght', weight.value.toDouble()),
      ]);
    }
    expect(
      shellxWeightedTextTheme(
        const TextTheme(bodyMedium: TextStyle()),
      ).bodyMedium!.fontVariations,
      [const FontVariation('wght', 400)],
    );
  });

  group('type scale (§6.5): new sizes, line heights in px as before', () {
    void scale(TextStyle s, double size, double linePx, FontWeight weight) {
      expect(s.fontSize, size);
      expect(s.fontSize! * s.height!, closeTo(linePx, 0.01));
      expect(s.fontWeight, weight);
      expect(s.fontVariations, [
        FontVariation('wght', weight.value.toDouble()),
      ]);
      expect(s.fontFamily, isNull, reason: 'the theme gives the family');
      expect(s.color, isNull);
    }

    test('desktop', () {
      scale(ShellxTypeScale.desktopCaption, 11, 14, FontWeight.w500);
      scale(ShellxTypeScale.desktopSmall, 11.5, 16, FontWeight.w400);
      scale(ShellxTypeScale.desktopBody, 12, 18, FontWeight.w400);
      scale(ShellxTypeScale.desktopBodyStrong, 12, 18, FontWeight.w600);
      scale(ShellxTypeScale.desktopLabel, 11.5, 16, FontWeight.w600);
      scale(ShellxTypeScale.desktopDialogBody, 13, 20, FontWeight.w400);
      scale(ShellxTypeScale.desktopEmptyTitle, 14, 20, FontWeight.w600);
      scale(ShellxTypeScale.desktopDialogTitle, 16, 22, FontWeight.w600);
      scale(ShellxTypeScale.desktopDisplay, 22, 28, FontWeight.w600);
      scale(ShellxTypeScale.desktopCode, 12, 17, FontWeight.w400);
    });

    test('phone', () {
      const w = FontWeight.w400;
      scale(ShellxTypeScale.mobileDisplay56, 54, 78.4, w);
      scale(ShellxTypeScale.mobileDisplay42, 40, 63, w);
      scale(ShellxTypeScale.mobileDisplay36, 34, 54, w);
      scale(ShellxTypeScale.mobileDisplay32, 30, 48, w);
      scale(ShellxTypeScale.mobileHeading28, 26, 42, w);
      scale(ShellxTypeScale.mobileHeading26, 24, 39, w);
      scale(ShellxTypeScale.mobileHeading24, 22, 36, w);
      scale(ShellxTypeScale.mobileHeading20, 19, 32, w);
      scale(ShellxTypeScale.mobileTitle, 17, 28.98, w);
      scale(ShellxTypeScale.mobileSubHeader, 15, 26, w);
      scale(ShellxTypeScale.mobileSubHeader15, 14, 24.375, w);
      scale(ShellxTypeScale.mobileParagraph, 13, 21.98, w);
      scale(ShellxTypeScale.mobileParagraph13, 13, 20.41, w);
      scale(ShellxTypeScale.mobileMetadata12, 12, 19, w);
      scale(ShellxTypeScale.mobileMetadata11, 11, 11 * 19 / 12, w);
      scale(ShellxTypeScale.mobileMetadata10, 10, 16, w);
      scale(ShellxTypeScale.mobileMetadata8, 8, 12.8, w);
      expect(ShellxTypeScale.mobileAppBarTitle.fontSize, 16);
      expect(ShellxTypeScale.mobileAppBarTitle.fontWeight, FontWeight.w700);
    });

    test('the Windows boost (A36): off by default; +n px, same line px', () {
      expect(ShellxTypeScale.desktopWindowsBoost, 0);
      const body = ShellxTypeScale.desktopBody;
      for (final p in TargetPlatform.values) {
        expect(identical(ShellxTypeScale.desktopFor(body, p), body), isTrue);
      }
      final boosted = ShellxTypeScale.desktopFor(
        body,
        TargetPlatform.windows,
        boost: 1,
      );
      expect(boosted.fontSize, 13);
      expect(boosted.fontSize! * boosted.height!, closeTo(18, 1e-9));
      expect(
        identical(
          ShellxTypeScale.desktopFor(body, TargetPlatform.macOS, boost: 1),
          body,
        ),
        isTrue,
      );
    });
  });
}
````

`packages/shellx_design/test/widgets_test.dart`:

````dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_design/shellx_design.dart';

void main() {
  Widget frame(Widget child, {Brightness brightness = Brightness.dark}) =>
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: Center(child: SizedBox(width: 200, height: 100, child: child)),
        ),
      );

  group('ShellxWedge (A30)', () {
    test('the triangle sits in its corner: 45 % across, 70 % down', () {
      const size = Size(200, 100);
      expect(
        const ShellxWedgePainter(
          corner: ShellxWedgeCorner.topRight,
          widthFactor: 0.45,
          heightFactor: 0.7,
        ).points(size),
        const [Offset(110, 0), Offset(200, 0), Offset(200, 70)],
      );
      expect(
        const ShellxWedgePainter(
          corner: ShellxWedgeCorner.bottomLeft,
          widthFactor: 0.45,
          heightFactor: 0.7,
        ).points(size),
        const [Offset(90, 100), Offset(0, 100), Offset(0, 30)],
      );
    });

    testWidgets('paints the wedge gradient; no semantics, no taps', (
      tester,
    ) async {
      var tapped = 0;
      await tester.pumpWidget(
        frame(
          Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => tapped++,
                  child: const ColoredBox(color: Color(0xFF000000)),
                ),
              ),
              const Positioned.fill(child: ShellxWedge()),
            ],
          ),
        ),
      );
      final wedge = find.byType(ShellxWedge);
      expect(
        find.descendant(of: wedge, matching: find.byType(CustomPaint)),
        paints..path(
          includes: const [Offset(190, 10)],
          excludes: const [Offset(10, 90), Offset(120, 60)],
        ),
      );
      expect(
        find.descendant(of: wedge, matching: find.byType(RepaintBoundary)),
        findsOneWidget,
      );
      await tester.tapAt(tester.getTopRight(wedge) + const Offset(-5, 5));
      expect(tapped, 1, reason: 'the tap went through');
      final semantics = tester.ensureSemantics();
      expect(
        find.descendant(of: wedge, matching: find.byType(ExcludeSemantics)),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('ShellxGlass (A29)', () {
    testWidgets('blurs only when asked', (tester) async {
      await tester.pumpWidget(frame(const ShellxGlass(child: Text('x'))));
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.pumpWidget(
        frame(const ShellxGlass(blur: false, child: Text('x'))),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('fill and border follow the brightness', (tester) async {
      Color fill() =>
          (tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: find.byType(ShellxGlass),
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .color!;
      await tester.pumpWidget(
        frame(const ShellxGlass(blur: false, child: Text('x'))),
      );
      expect(fill(), ShellxPalette.glassFill);
      await tester.pumpWidget(
        frame(
          const ShellxGlass(blur: false, child: Text('x')),
          brightness: Brightness.light,
        ),
      );
      await tester.pumpAndSettle(); // MaterialApp animates a theme change.
      expect(fill(), ShellxLightPalette.glassFill);
      expect(ShellxGlass.sigma, 16);
    });
  });

  group('ShellxInsetBox (A28)', () {
    testWidgets('paints the fill, then each inner shadow, then the border', (
      tester,
    ) async {
      await tester.pumpWidget(
        frame(
          ShellxInsetBox(
            color: ShellxPalette.navy900,
            shadow: ShellxElevation.dark.inset,
            borderRadius: BorderRadius.circular(16),
            border: const BorderSide(color: ShellxPalette.fieldOutline),
            child: const SizedBox.expand(),
          ),
        ),
      );
      final box = find.descendant(
        of: find.byType(ShellxInsetBox),
        matching: find.byType(CustomPaint),
      );
      expect(
        box,
        paints
          ..rrect(color: ShellxPalette.navy900)
          ..save()
          ..clipRRect()
          ..path(color: const Color(0x73000000))
          ..path(color: const Color(0x0DFFFFFF))
          ..restore()
          ..rrect(
            color: ShellxPalette.fieldOutline,
            style: PaintingStyle.stroke,
          ),
      );
    });

    test('repaints only when its look changes', () {
      final a = ShellxInsetPainter(
        color: ShellxPalette.navy900,
        shadow: ShellxElevation.dark.inset,
        borderRadius: BorderRadius.circular(16),
      );
      final b = ShellxInsetPainter(
        color: ShellxPalette.navy900,
        shadow: ShellxElevation.dark.inset,
        borderRadius: BorderRadius.circular(16),
      );
      final c = ShellxInsetPainter(
        color: ShellxPalette.navy850,
        shadow: ShellxElevation.dark.inset,
        borderRadius: BorderRadius.circular(16),
      );
      expect(a.shouldRepaint(b), isFalse);
      expect(a.shouldRepaint(c), isTrue);
    });
  });

  group('ShellxSlantBorder', () {
    test('the top edge rises 4 px from left to right, corners rounded 10', () {
      const border = ShellxSlantBorder();
      final path = border.getOuterPath(const Rect.fromLTWH(0, 0, 56, 36));
      expect(
        path.contains(const Offset(28, 1.5)),
        isFalse,
        reason: 'above the slope',
      );
      expect(path.contains(const Offset(28, 3)), isTrue);
      expect(path.contains(const Offset(28, 35)), isTrue);
      expect(
        path.contains(const Offset(0.5, 0.5)),
        isFalse,
        reason: 'a rounded corner',
      );
      expect(path.contains(const Offset(55.5, 35.5)), isFalse);
      expect(border.radius, 10);
      expect(border.slant, 4);
      expect(border.copyWith(side: const BorderSide(width: 2)).side.width, 2);
      expect(border.scale(2).radius, 20);
    });
  });

  group('shellxGradientLayer (A38)', () {
    final radius = BorderRadius.circular(10);
    final builder = shellxGradientLayer(
      gradient: ShellxGradients.accentStrong,
      borderRadius: radius,
      disabledOpacity: 0.38,
    );

    Future<(BoxDecoration, BoxDecoration)> layers(
      WidgetTester tester,
      Set<WidgetState> states,
    ) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) =>
              builder(context, states, const SizedBox(width: 80, height: 32)),
        ),
      );
      final boxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .toList();
      return (
        boxes[0].decoration as BoxDecoration,
        boxes[1].decoration as BoxDecoration,
      );
    }

    testWidgets('idle: the gradient, rounded, no shade', (tester) async {
      final (back, shade) = await layers(tester, {});
      expect(back.gradient, ShellxGradients.accentStrong);
      expect(back.borderRadius, radius);
      expect(shade.color, const Color(0x00000000));
      expect(shade.borderRadius, radius);
    });

    testWidgets('hovered: black 8 %; pressed: black 16 %', (tester) async {
      expect(
        (await layers(tester, {WidgetState.hovered})).$2.color,
        const Color(0x14000000),
      );
      expect(
        (await layers(tester, {WidgetState.pressed})).$2.color,
        const Color(0x29000000),
      );
      expect(
        (await layers(tester, {
          WidgetState.hovered,
          WidgetState.pressed,
        })).$2.color,
        const Color(0x29000000),
      );
    });

    testWidgets('disabled: the gradient faded, no shade', (tester) async {
      final (back, shade) = await layers(tester, {
        WidgetState.disabled,
        WidgetState.hovered,
      });
      final faded = back.gradient! as LinearGradient;
      expect(faded.colors.first.a, closeTo(0.38, 0.01));
      expect(faded.colors.last.a, closeTo(0.38, 0.01));
      expect(shade.color, const Color(0x00000000));
    });
  });
}
````

- [ ] **Step 2: Run them to see them fail**

````bash
cd packages/shellx_design && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/fonts_test.dart test/widgets_test.dart
````

Expected: compilation fails (`shellxWeight`, `ShellxTypeScale`, `ShellxWedge` … undefined).

- [ ] **Step 3: The type scale**

`packages/shellx_design/lib/src/type_scale.dart` (whole file):

````dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TextTheme;
import 'package:flutter/painting.dart';

/// V2-5a A31, §6.1: the font families by platform. SF Mono is the system's
/// own on iOS and macOS, loaded at run time ([ShellxSystemFont]) and never
/// bundled; JetBrains Mono ships in both apps and is used everywhere else,
/// and on iOS and macOS when SF Mono did not load.
abstract final class ShellxFonts {
  /// The family [ShellxSystemFont] registers the system's SF Mono under.
  static const String systemMono = 'SF Mono';

  /// Bundled by both apps (`assets/fonts/JetBrainsMono-*.ttf`).
  static const String bundledMono = 'JetBrainsMono';

  /// The desktop's Light cut as its own family (the terminal default).
  static const String bundledMonoLight = 'JetBrainsMonoLight';

  /// iOS and macOS: the platforms whose system font ShellX may display.
  static bool isApple(TargetPlatform platform) =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  /// The UI family of [platform]. A32: never "SF Mono" off Apple platforms,
  /// not even when the user installed it there.
  static String uiFamily(TargetPlatform platform) =>
      isApple(platform) ? systemMono : bundledMono;

  /// What the engine falls back to when [uiFamily] is not registered.
  static List<String> uiFallback(TargetPlatform platform) =>
      isApple(platform) ? const [bundledMono] : const [];
}

/// [style] at [weight]: sets `fontWeight` and the variable font's `wght`
/// axis together (A35). The system's SF Mono is one variable font whose
/// default is 295 (Light): a weight alone would not change it. JetBrains
/// Mono is static and ignores the axis (500 draws Regular, 600 Bold).
TextStyle shellxWeight(TextStyle style, FontWeight weight) => style.copyWith(
  fontWeight: weight,
  fontVariations: [FontVariation('wght', weight.value.toDouble())],
);

/// [theme] with each style's `wght` axis set to its weight, so text that
/// only takes a theme style (a plain `Text`, a Material label) is never
/// drawn at SF Mono's default Light.
TextTheme shellxWeightedTextTheme(TextTheme theme) {
  TextStyle? weighted(TextStyle? style) => style == null
      ? null
      : shellxWeight(style, style.fontWeight ?? FontWeight.w400);
  return TextTheme(
    displayLarge: weighted(theme.displayLarge),
    displayMedium: weighted(theme.displayMedium),
    displaySmall: weighted(theme.displaySmall),
    headlineLarge: weighted(theme.headlineLarge),
    headlineMedium: weighted(theme.headlineMedium),
    headlineSmall: weighted(theme.headlineSmall),
    titleLarge: weighted(theme.titleLarge),
    titleMedium: weighted(theme.titleMedium),
    titleSmall: weighted(theme.titleSmall),
    bodyLarge: weighted(theme.bodyLarge),
    bodyMedium: weighted(theme.bodyMedium),
    bodySmall: weighted(theme.bodySmall),
    labelLarge: weighted(theme.labelLarge),
    labelMedium: weighted(theme.labelMedium),
    labelSmall: weighted(theme.labelSmall),
  );
}

/// V2-5a A34, §6.5: the type scale of both apps for a monospaced UI font:
/// smaller sizes, the same line heights in px (no vertical layout moves).
/// No colour and no family (the theme gives the family per platform); each
/// style sets its weight and `wght` together.
abstract final class ShellxTypeScale {
  /// A36: px added to every desktop size on Windows, line heights kept,
  /// should the legibility check of JetBrains Mono at 11–12 px fail. 0: off.
  static const double desktopWindowsBoost = 0;

  /// [style] (a `desktop*` style) as drawn on [platform]: on Windows,
  /// [boost] px larger with the same line height in px.
  static TextStyle desktopFor(
    TextStyle style,
    TargetPlatform platform, {
    double boost = desktopWindowsBoost,
  }) {
    if (platform != TargetPlatform.windows || boost == 0) return style;
    final size = style.fontSize!;
    final line = size * style.height!;
    return style.copyWith(
      fontSize: size + boost,
      height: line / (size + boost),
    );
  }

  // Desktop (`ShellxText`): size / line px, weight.
  /// 11/14, 500: shortcut hints in menus, tooltips; the context line.
  static const TextStyle desktopCaption = TextStyle(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
  );

  /// 11.5/16, 400: pane headers, tooltips, chips.
  static const TextStyle desktopSmall = TextStyle(
    fontSize: 11.5,
    height: 16 / 11.5,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );

  /// 12/18, 400: tab names, strips, menu items, toasts.
  static const TextStyle desktopBody = TextStyle(
    fontSize: 12,
    height: 18 / 12,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );

  /// 12/18, 600: the selected tab, button labels.
  static const TextStyle desktopBodyStrong = TextStyle(
    fontSize: 12,
    height: 18 / 12,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
  );

  /// 11.5/16, 600: field labels, the brand line.
  static const TextStyle desktopLabel = TextStyle(
    fontSize: 11.5,
    height: 16 / 11.5,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
  );

  /// 13/20, 400: dialog bodies, field values, AI markdown.
  static const TextStyle desktopDialogBody = TextStyle(
    fontSize: 13,
    height: 20 / 13,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );

  /// 14/20, 600: empty-state titles.
  static const TextStyle desktopEmptyTitle = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
  );

  /// 16/22, 600: dialog titles.
  static const TextStyle desktopDialogTitle = TextStyle(
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
  );

  /// 22/28, 600: for V2-5b (the AI home greeting).
  static const TextStyle desktopDisplay = TextStyle(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
  );

  /// 12/17, 400: code in the AI pane (`kAiMono`), in the platform's family.
  static const TextStyle desktopCode = TextStyle(
    fontSize: 12,
    height: 17 / 12,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );

  // Phone (`AppTypography`): the old line px over the new size. Weight 400;
  // the getters' `.medium`, `.semiBold`, `.bold`, `.heavy` go through
  // [shellxWeight].
  static const TextStyle mobileDisplay56 = TextStyle(
    fontSize: 54,
    height: 56 * 1.4 / 54,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileDisplay42 = TextStyle(
    fontSize: 40,
    height: 42 * 1.5 / 40,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileDisplay36 = TextStyle(
    fontSize: 34,
    height: 36 * 1.5 / 34,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileDisplay32 = TextStyle(
    fontSize: 30,
    height: 32 * 1.5 / 30,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileHeading28 = TextStyle(
    fontSize: 26,
    height: 28 * 1.5 / 26,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileHeading26 = TextStyle(
    fontSize: 24,
    height: 26 * 1.5 / 24,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileHeading24 = TextStyle(
    fontSize: 22,
    height: 24 * 1.5 / 22,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileHeading20 = TextStyle(
    fontSize: 19,
    height: 20 * 1.6 / 19,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileTitle = TextStyle(
    fontSize: 17,
    height: 18 * 1.61 / 17,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileSubHeader = TextStyle(
    fontSize: 15,
    height: 16 * 1.625 / 15,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileSubHeader15 = TextStyle(
    fontSize: 14,
    height: 15 * 1.625 / 14,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileParagraph = TextStyle(
    fontSize: 13,
    height: 14 * 1.57 / 13,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileParagraph13 = TextStyle(
    fontSize: 13,
    height: 1.57,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileMetadata12 = TextStyle(
    fontSize: 12,
    height: 19 / 12,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileMetadata11 = TextStyle(
    fontSize: 11,
    height: 19 / 12,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileMetadata10 = TextStyle(
    fontSize: 10,
    height: 1.6,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileMetadata8 = TextStyle(
    fontSize: 8,
    height: 1.6,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );

  /// The phone's AppBar title: 16, 700 (was 17).
  static const TextStyle mobileAppBarTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
  );
}
````

- [ ] **Step 4: The shared widgets**

`packages/shellx_design/lib/src/widgets/inset_box.dart`:

````dart
import 'package:flutter/widgets.dart';

import '../elevation.dart';

/// V2-5a A28: an inset ("pressed in") box. [BoxShadow] has no inset, so the
/// inner [shadow] is painted inside the shape: fields on the phone, the
/// segmented track, the slider track. Its own layer ([RepaintBoundary]),
/// repainted only when its size or look changes.
class ShellxInsetBox extends StatelessWidget {
  const ShellxInsetBox({
    super.key,
    required this.color,
    required this.shadow,
    required this.borderRadius,
    this.border,
    this.padding,
    this.child,
  });

  final Color color;
  final ShellxInsetShadow shadow;
  final BorderRadius borderRadius;

  /// Drawn over the shadow (a field's outline).
  final BorderSide? border;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: ShellxInsetPainter(
        color: color,
        shadow: shadow,
        borderRadius: borderRadius,
        border: border,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    ),
  );
}

/// What [ShellxInsetBox] paints: the fill, each inner shadow, the border.
class ShellxInsetPainter extends CustomPainter {
  const ShellxInsetPainter({
    required this.color,
    required this.shadow,
    required this.borderRadius,
    this.border,
  });

  final Color color;
  final ShellxInsetShadow shadow;
  final BorderRadius borderRadius;
  final BorderSide? border;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = borderRadius.toRRect(rect);
    canvas.drawRRect(shape, Paint()..color = color);
    canvas.save();
    canvas.clipRRect(shape);
    for (final s in shadow.shadows) {
      // Everything outside the shape, moved by the offset and blurred: what
      // falls back inside is the inner shadow.
      final outside = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(s.blurRadius * 2 + s.offset.distance + 1))
        ..addRRect(shape.shift(s.offset));
      canvas.drawPath(
        outside,
        Paint()
          ..color = s.color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.blurSigma),
      );
    }
    canvas.restore();
    final side = border;
    if (side != null && side.style != BorderStyle.none && side.width > 0) {
      canvas.drawRRect(shape.deflate(side.width / 2), side.toPaint());
    }
  }

  @override
  bool shouldRepaint(ShellxInsetPainter old) =>
      old.color != color ||
      old.shadow != shadow ||
      old.borderRadius != borderRadius ||
      old.border != border;
}
````

`packages/shellx_design/lib/src/widgets/wedge.dart`:

````dart
import 'package:flutter/widgets.dart';

import '../gradients.dart';

/// The corner a [ShellxWedge] sits in.
enum ShellxWedgeCorner { topLeft, topRight, bottomLeft, bottomRight }

/// V2-5a A30: the diagonal blue wedge of the reference, a right triangle in
/// a corner ([widthFactor] of the width along the edge, [heightFactor] of
/// the height down the side), filled with [ShellxGradients.wedge]. Only on
/// empty states, the splash, sign-in and onboarding (and V2-5b/C's places);
/// never behind the terminal, a web view or long text, and only bold white
/// text from 15 px may sit on it. Not hit-testable, no semantics, its own
/// layer.
class ShellxWedge extends StatelessWidget {
  const ShellxWedge({
    super.key,
    this.corner = ShellxWedgeCorner.topRight,
    this.widthFactor = 0.45,
    this.heightFactor = 0.7,
  });

  final ShellxWedgeCorner corner;
  final double widthFactor;
  final double heightFactor;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: ShellxWedgePainter(
            corner: corner,
            widthFactor: widthFactor,
            heightFactor: heightFactor,
          ),
        ),
      ),
    ),
  );
}

/// What [ShellxWedge] paints.
class ShellxWedgePainter extends CustomPainter {
  const ShellxWedgePainter({
    required this.corner,
    required this.widthFactor,
    required this.heightFactor,
  });

  final ShellxWedgeCorner corner;
  final double widthFactor;
  final double heightFactor;

  /// The triangle in [size]: the corner itself, a point along the top or
  /// bottom edge and a point down or up the side.
  List<Offset> points(Size size) {
    final w = size.width * widthFactor;
    final h = size.height * heightFactor;
    final right = size.width;
    final bottom = size.height;
    return switch (corner) {
      ShellxWedgeCorner.topRight => [
        Offset(right - w, 0),
        Offset(right, 0),
        Offset(right, h),
      ],
      ShellxWedgeCorner.topLeft => [Offset(w, 0), Offset.zero, Offset(0, h)],
      ShellxWedgeCorner.bottomRight => [
        Offset(right - w, bottom),
        Offset(right, bottom),
        Offset(right, bottom - h),
      ],
      ShellxWedgeCorner.bottomLeft => [
        Offset(w, bottom),
        Offset(0, bottom),
        Offset(0, bottom - h),
      ],
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = points(size);
    final bounds = Rect.fromPoints(
      p[0],
      p[2],
    ).expandToInclude(Rect.fromPoints(p[1], p[1]));
    final path = Path()..addPolygon(p, true);
    canvas.drawPath(
      path,
      Paint()..shader = ShellxGradients.wedge.createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(ShellxWedgePainter old) =>
      old.corner != corner ||
      old.widthFactor != widthFactor ||
      old.heightFactor != heightFactor;
}
````

`packages/shellx_design/lib/src/widgets/glass.dart`:

````dart
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../gradients.dart';
import '../palette.dart';
import '../radii.dart';

/// V2-5a A29: frosted glass — [ShellxPalette.glassFill] (light: white 80 %)
/// with a 1 px gradient border. [blur] (σ 16) only where what is behind
/// stays still (the wedge, the page); over content that moves (a list, the
/// AI transcript) it is false. Only `textPrimary` or brighter text sits on
/// it. The app's only [BackdropFilter].
class ShellxGlass extends StatelessWidget {
  const ShellxGlass({
    super.key,
    required this.child,
    this.blur = true,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(ShellxRadii.card),
    ),
    this.padding,
  });

  final Widget child;
  final bool blur;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;

  /// σ of [blur].
  static const double sigma = 16;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final panel = CustomPaint(
      foregroundPainter: ShellxGradientBorderPainter(
        gradient: dark
            ? ShellxGradients.glassBorderDark
            : ShellxGradients.glassBorderLight,
        borderRadius: borderRadius,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? ShellxPalette.glassFill : ShellxLightPalette.glassFill,
          borderRadius: borderRadius,
        ),
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
    if (!blur) return panel;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: panel,
      ),
    );
  }
}

/// A 1 px border of [gradient] around a rounded rectangle.
class ShellxGradientBorderPainter extends CustomPainter {
  const ShellxGradientBorderPainter({
    required this.gradient,
    required this.borderRadius,
    this.width = 1,
  });

  final Gradient gradient;
  final BorderRadius borderRadius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      borderRadius.toRRect(rect).deflate(width / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = gradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(ShellxGradientBorderPainter old) =>
      old.gradient != gradient ||
      old.borderRadius != borderRadius ||
      old.width != width;
}
````

`packages/shellx_design/lib/src/widgets/slant_border.dart`:

````dart
import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// V2-5a §7.1: the phone bottom bar's active tile — a rounded rectangle
/// whose top edge rises [slant] px from left to right, as in the
/// reference.
class ShellxSlantBorder extends OutlinedBorder {
  const ShellxSlantBorder({super.side, this.radius = 10, this.slant = 4});

  final double radius;
  final double slant;

  /// The corners, clockwise from the top left; the top edge slopes.
  List<Offset> corners(Rect rect) => [
    Offset(rect.left, rect.top + slant),
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ];

  Path _path(Rect rect) {
    final points = corners(rect);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final previous = points[(i + points.length - 1) % points.length];
      final corner = points[i];
      final next = points[(i + 1) % points.length];
      final r = math.min(
        radius,
        math.min((corner - previous).distance, (next - corner).distance) / 2,
      );
      final from = corner + _unit(previous - corner) * r;
      final to = corner + _unit(next - corner) * r;
      if (i == 0) {
        path.moveTo(from.dx, from.dy);
      } else {
        path.lineTo(from.dx, from.dy);
      }
      path.quadraticBezierTo(corner.dx, corner.dy, to.dx, to.dy);
    }
    return path..close();
  }

  static Offset _unit(Offset o) => o.distance == 0 ? o : o / o.distance;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  ShellxSlantBorder scale(double t) => ShellxSlantBorder(
    side: side.scale(t),
    radius: radius * t,
    slant: slant * t,
  );

  @override
  ShellxSlantBorder copyWith({BorderSide? side}) =>
      ShellxSlantBorder(side: side ?? this.side, radius: radius, slant: slant);

  @override
  bool operator ==(Object other) =>
      other is ShellxSlantBorder &&
      other.side == side &&
      other.radius == radius &&
      other.slant == slant;

  @override
  int get hashCode => Object.hash(side, radius, slant);
}
````

`packages/shellx_design/lib/src/widgets/gradient_layer.dart`:

````dart
import 'package:flutter/material.dart';

import '../gradients.dart';

/// V2-5a A38: a `ButtonStyle.backgroundBuilder` that paints [gradient]
/// behind a button's label. The widget stays a [FilledButton] (tests find
/// them by key); Material's ink would sit under the opaque gradient, so the
/// layer shades itself — black 8 % hovered, 16 % pressed — and rounds its
/// own corners. Disabled: the gradient at [disabledOpacity].
ButtonLayerBuilder shellxGradientLayer({
  required LinearGradient gradient,
  required BorderRadius borderRadius,
  required double disabledOpacity,
}) => (context, states, child) {
  final disabled = states.contains(WidgetState.disabled);
  final shade = disabled
      ? null
      : states.contains(WidgetState.pressed)
      ? ShellxGradients.pressedShade
      : states.contains(WidgetState.hovered)
      ? ShellxGradients.hoverShade
      : null;
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: disabled ? gradient.scale(disabledOpacity) : gradient,
      borderRadius: borderRadius,
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: shade ?? const Color(0x00000000),
        borderRadius: borderRadius,
      ),
      child: child,
    ),
  );
};
````

`packages/shellx_design/lib/shellx_design.dart` (whole file; Task 8 adds `src/icons.dart`, Task 14 `src/licenses.dart`):

````dart
/// ShellX's shared design system (V2-5a): tokens, type, icons and the shared
/// widgets. Both apps reach it through their own adapters (desktop
/// `ui/theme`, phone `core/design`).
library;

export 'src/contrast.dart';
export 'src/elevation.dart';
export 'src/gradients.dart';
export 'src/motion.dart';
export 'src/palette.dart';
export 'src/radii.dart';
export 'src/spacing.dart';
export 'src/system_font.dart';
export 'src/terminal_palette.dart';
export 'src/type_scale.dart';
export 'src/widgets/glass.dart';
export 'src/widgets/gradient_layer.dart';
export 'src/widgets/inset_box.dart';
export 'src/widgets/slant_border.dart';
export 'src/widgets/wedge.dart';
````

- [ ] **Step 5: Run the package's checks**

````bash
cd packages/shellx_design && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
````

Expected: `No issues found!`; `+62: All tests passed!`.

- [ ] **Step 6: Commit**

````bash
git add packages/shellx_design
git commit -m "feat(v2-design): the monospaced type scale with weight axes, the Windows boost switch, and the shared widgets — inset box, wedge, glass, slanted tile, gradient button layer

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
````

### Task 5: The desktop adapter — tokens, theme, fonts, terminal

Spec A16–A19, A21, A24, A27, A31, A34, A35, A37, A38 (theme), A39, A43, A50; §5.9 (DT), §6.1, §6.5 (DT), §6.8; §10.2; R3, R5, R17.

**Files:**
- Modify: `apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart` (`ShellxDesktopColors`, `ShellxSpace`, `ShellxRadius`, `ShellxShadows`, `ShellxText`, `ShellxMotion`, `uiFont`, `buildDesktopTheme`, `buildDialogTheme`, `destructiveButtonStyle`; new `shellxPrimaryButtonStyle`, `shellxSecondaryButtonStyle`, `shellxTextButtonStyle`)
- Modify: `apps/desktop/lib/src/ui/theme/terminal_colors.dart` (`TerminalColors` reads `ShellxTerminalPalette`)
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart` (`ShellxPrimaryButton` → `shellxPrimaryButtonStyle()`)
- Modify: `apps/desktop/lib/src/ui/ai/ai_theme.dart` (`kAiMono`), `ui/ai/ai_file_viewer.dart` (re_editor `CodeEditorStyle`), `ui/pages/confirm_page.dart` (drop `fontFamily: 'JetBrainsMono'`)
- Modify: `apps/desktop/lib/src/ui/app.dart` (`ShellxDesktopApp` `builder:`), `apps/desktop/lib/main.dart` (`main`)
- Modify: `apps/desktop/lib/src/terminal/terminal_style.dart` (`desktopTerminalStyle`)
- Modify: `third_party/xterm/lib/src/ui/terminal_text_style.dart` (`TerminalStyle`), `third_party/xterm/SHELLX_PATCHES.md`
- Modify `apps/desktop/pubspec.yaml`: add `shellx_design: any` under `dependencies` if Task 1 did not (workspace resolution).
- Tests: rewrite `apps/desktop/test/ui/theme_test.dart`; modify `test/ui/notifications_panel_test.dart`, `test/ui/attention_ring_test.dart`, `test/ui/find_bar_test.dart`, `test/terminal/find_session_test.dart`, `test/ui/app_dialogs_test.dart`, `test/terminal/terminal_style_test.dart`; create `test/ui/font_coverage_test.dart`.

**Interfaces:**
- Consumes: Task 1 `ShellxFonts.{systemMono, bundledMono, bundledMonoLight, uiFamily, uiFallback}`, `ShellxSystemFont.load()`; Task 3 `ShellxPalette.*`, `ShellxGradients.{accent, accentStrong, hoverShade, pressedShade}`, `ShellxRadii.{tiny, control, card, sheet, pill}`, `ShellxSpacing.*`, `ShellxElevation.{darkFloat1, darkFloat2, darkRaisedSmall, darkInset, float1Elevation, float1ShadowColor}`, `ShellxDurations.*`, `ShellxCurves.*`, `ShellxTerminalPalette.*`, `contrastRatio`; Task 4 `ShellxTypeScale.desktop*`, `ShellxTypeScale.desktopFor`, `shellxWeight`, `shellxWeightedTextTheme`, `shellxGradientLayer`.
- Produces (Tasks 9, 11, V2-5b):
  - `ShellxDesktopColors` new: `onAccent`, `link`, `overlayHover`, `overlayPressed`, `pushed` (`static const Color`); removed: `primaryHover`, `primaryPressed`.
  - `ShellxShadows.raised` (`static const List<BoxShadow>` = `ShellxElevation.darkRaisedSmall`), `ShellxShadows.inset` (`static const ShellxInsetShadow inset = ShellxInsetShadow(ShellxElevation.darkInset)`).
  - `ShellxText.display` (getter, 22/28 600); every `ShellxText.*` a `static TextStyle get` (R3).
  - `ShellxMotion.slide` (`Duration`), `ShellxMotion.slideCurve` (`Curve`).
  - `ButtonStyle shellxPrimaryButtonStyle()`, `ButtonStyle shellxSecondaryButtonStyle()`, `ButtonStyle shellxTextButtonStyle()`, `ButtonStyle destructiveButtonStyle()` (kept name, new layer).
  - xterm: `TerminalStyle({…, double? normalWeight, double? boldWeight})`, fields `normalWeight`, `boldWeight`, `copyWith(normalWeight:, boldWeight:)`.

**Tests first** (all red before the change):
- `test/ui/theme_test.dart` (rewrite):
  - `'colours point at the package (§5.9)'`: each `ShellxDesktopColors` token `==` its `ShellxPalette` constant and the hex: `bgTerminal` `0xFF1C222E` (navy900), `bgSidebar` `0xFF222834` (navy850), `rowHover` `0xFF28303F` (navy800), `rowSelected` `0xFF323B4F` (navy700), `rowPressed` `0xFF38445A` (navy650), `line` `0x14FFFFFF` (hairline), `surface` `0xFF2C3547` (navy750), `surfaceInset` `0xFF1C222E`, `border` `0x1AFFFFFF` (hairlineStrong), `borderInput` `0xFF76829C` (fieldOutline), `textPrimary` `0xFFE2E3E5`, `textTitle` `0xFFFFFFFF`, `textSecondary` `0xFFA7A9AE`, `textDialog2` `0xFFCACCD1`, `textPlaceholder` `0xFF8E9096`, `dim` `0xFF767A81`, `accent` = `primary` `0xFF34C8E8` (cyan), `onPrimary` `0xFF0E1A26` (onCyan), `primarySoft` `0xFF253E4D` (cyanSoft), `ok` `0xFF5ED39C`, `warn` `0xFFF5B94E`, `warnBg` `0xFF3B3937`, `warnBorder` `0xFF554B3A`, `err` = `errDialog` `0xFFFF8A94`, `onErr` `0xFF2A0A0C`, `statusInProgress` `0xFF6EA8FE`, `noticeBg` `0xFF453F50`, `noticeText` `0xFFFFD9DB`, `noticeBorder` `0xFF5F4959`, `scrim` `0x99000000`, `scrollThumb` `0xFF3D424C`, `scrollThumbHover` `0xFF4E535D`, `destructiveHover` `0xFFFF98A1`; new `onAccent` `0xFFFFFFFF`, `link` `0xFF5EADEE`, `overlayHover` `0xFF38445A`, `overlayPressed` `0xFF3F4B62`, `pushed` `0xFF28303F`.
  - `'radii, space, shadows, motion'`: `ShellxRadius.r4/r6/r8/r12` = 6/10/16/28, `pill` = `ShellxRadii.pill`; `ShellxShadows.e1 == ShellxElevation.darkFloat1`, `e2 == darkFloat2`, `raised == darkRaisedSmall`, `e1Elevation == 8`, `e1ShadowColor == Color(0x73000000)`; `ShellxMotion.slide == ShellxDurations.slide`, `slideCurve == ShellxCurves.slide`.
  - `'ShellxText follows §6.5'` (each `fontSize`, `fontSize * height` closeTo px, weight via `fontWeight` **and** `fontVariations` `[FontVariation('wght', w)]`): `caption` 11/14/500, `small` 11.5/16/400, `body` 12/18/400, `bodyStrong` 12/18/600, `label` 11.5/16/600, `dialogBody` 13/20/400, `emptyTitle` 14/20/600, `dialogTitle` 16/22/600, `display` 22/28/600; no `fontFamily`; `kAiMono` 12/17, `fontFamily == null`, weight 400 + `wght` 400.
  - `'row backgrounds rise'`: `computeLuminance` hover < selected < pressed; `contrastRatio(rowSelected, bgSidebar)` closeTo(1.32, 0.01) and > 1.25.
  - `'families by platform'`: with `debugDefaultTargetPlatformOverride = TargetPlatform.macOS`, `buildDesktopTheme().textTheme.bodyMedium!.fontFamily == 'SF Mono'`, `fontFamilyFallback == ['JetBrainsMono']`; Windows → `'JetBrainsMono'`, fallback empty; `uiFont(const TextStyle(), theme.textTheme)` copies both; `textTheme.bodyMedium!.fontVariations` contains `FontVariation('wght', 400)` (R5). Reset the override in `tearDown`.
  - `'colour scheme'`: `surfaceContainerLowest/Low/Container/High/Highest` = navy900, navy850, navy750, navy750, navy700; `surfaceTint == Colors.transparent`.
  - `'every A39 component theme'`: `inputDecorationTheme` filled, `fillColor` navy900, enabled outline `0xFF76829C` radius 16, focused `0xFF34C8E8` width 1.5, disabled side colour at alpha 0.5, hovered (via `WidgetStateInputBorder.resolve({WidgetState.hovered})`) `textSecondary`; `switchTheme.thumbColor.resolve({selected})` `0xFF0E1A26`, `trackColor.resolve({selected})` `0xFF34C8E8`; `sliderTheme.activeTrackColor` cyan; `progressIndicatorTheme.color` cyan; `textSelectionTheme.selectionColor == ShellxTerminalPalette.selection`; `iconTheme` non-null; `dialogTheme` (bg navy750, `RoundedRectangleBorder` r28, side `hairlineStrong`, `barrierColor` scrim); `bottomSheetTheme` (navy750, top r28); `popupMenuTheme`, `menuTheme`, `dropdownMenuTheme.menuStyle` (navy750, r16, side `hairlineStrong`); `tooltipTheme` (decoration colour navy700, r10, border `hairlineStrong`, `textStyle` = `ShellxText.small` in `textPrimary`, padding 4/8, shadow `float1`); `filledButtonTheme`, `outlinedButtonTheme`, `textButtonTheme` non-null.
  - `'primary button paints accentStrong'` (widget test, pump `ShellxPrimaryButton` and a dialog `FilledButton` under `buildDialogTheme`): `style.backgroundBuilder != null`; a `DecoratedBox` whose `BoxDecoration.gradient == ShellxGradients.accentStrong`; label colour `0xFFFFFFFF`; hovered → the overlay `ShellxGradients.hoverShade` (`0x14000000`) painted, pressed → `pressedShade` (`0x29000000`), disabled → `Opacity` 0.38; focused → shape is `OutsideFocusRingBorder`; still `find.byType(FilledButton)`.
  - `'secondary and text styles'`: secondary bg navy700, hovered navy650 (`overlayHover`), pressed `pushed` with `elevation`/shadow none, shadow `raisedSmall` at rest, inside ring; text button fg `link` `0xFF5EADEE`, hovered bg `rowHover`, pressed `rowPressed`.
  - `'destructive style has its own layer'`: pumped `FilledButton(style: destructiveButtonStyle())` paints solid `0xFFFF8A94`, hovered `0xFFFF98A1`, pressed `0xFFFF8A94` + `0x29000000`; no `LinearGradient` in its subtree.
- Hex pins rewritten through tokens: `notifications_panel_test.dart` `0xFF1F2F34` → `ShellxDesktopColors.rowSelected`; `attention_ring_test.dart` (the two pins), `find_bar_test.dart`, `find_session_test.dart` (`#5FD4E2` → `ShellxDesktopColors.accent`); `app_dialogs_test.dart` (switch thumb when on → `ShellxDesktopColors.onPrimary`).
- `test/terminal/terminal_style_test.dart` (macOS override): `desktopTerminalStyle(13)` → `fontFamily 'SF Mono'`, `fontFamilyFallback.first == 'JetBrainsMonoLight'` then xterm's list, `normalWeight 300`, `boldWeight 700`, `toTextStyle().fontVariations == [FontVariation('wght', 300)]`, `toTextStyle(bold: true)` → `FontWeight.bold` + `wght` 700; `regular: true` → `normalWeight 400`, fallback first `'JetBrainsMono'`; `families: ['Fira Code']` on macOS → `fontFamily 'Fira Code'`, fallback `['JetBrainsMonoLight', ...xterm's]`, no `'SF Mono'`, both weights null, `fontVariations` null (R17); Windows → `'JetBrainsMonoLight'` (regular: `'JetBrainsMono'`), weights null. `test/terminal/terminal_font_weight_test.dart` unchanged and green.
- `test/ui/font_coverage_test.dart`: read each `assets/fonts/JetBrainsMono-*.ttf` (6 files), parse the `cmap` table (format 4 and 12 subtables, read-only, in the test file), assert every code point of U+1EA0–U+1EF9 plus the 44 of Task 1's `SystemMonoFontTables.vietnamese` list and the marks U+0300, U+0301, U+0303, U+0309, U+0323 maps to a non-zero glyph (134 + 5).
- Geometry tests whose widths depend on font size get the new numbers from a run (never a looser matcher); heights do not change.

**Implementation notes:**
- Colours (A16, §5.9): every `ShellxDesktopColors` value is `ShellxPalette.<name>` (no `Color(0x` left in `ui/theme/*.dart`, Task 7). Mapping: `bgTerminal`/`surfaceInset` navy900, `bgSidebar` navy850, `rowHover` navy800, `rowSelected` navy700, `rowPressed` navy650, `surface` navy750, `line` hairline, `border` hairlineStrong, `borderInput` fieldOutline, `textTitle` white100, `textPrimary` white87, `textDialog2` white75, `textSecondary` white60, `textPlaceholder` white50, `dim` white38, `accent`/`primary` cyan, `onPrimary` onCyan, `primarySoft` cyanSoft, `ok`, `warn`, `warnBg` warnSoft, `warnBorder` warnLine, `err`/`errDialog` error, `onErr` onError, `statusInProgress` inProgress, `noticeBg`, `noticeText`, `noticeBorder` noticeLine, `scrim`, `scrollThumb`, `scrollThumbHover`, `destructiveHover` errorHover, `onAccent`, `link`, `overlayHover` navy650, `overlayPressed` navy600, `pushed` navy800. Delete `primaryHover`/`primaryPressed` (A50) and the `buildDialogTheme` lines that use them.
- `ShellxText` (R3): `static TextStyle get body => ShellxTypeScale.desktopFor(ShellxTypeScale.desktopBody, defaultTargetPlatform);` for each of the nine; `kAiMono` stays `const` = `ShellxTypeScale.desktopCode` (12/17, 400 + `wght` 400, no family).
- `buildDesktopTheme()`: `fontFamily: ShellxFonts.uiFamily(defaultTargetPlatform)`, `fontFamilyFallback: ShellxFonts.uiFallback(defaultTargetPlatform)`; `textTheme`/`primaryTextTheme` through `shellxWeightedTextTheme` (R5); `ColorScheme.dark(...)` with the five `surfaceContainer*` and `surfaceTint: Colors.transparent`; the A39 component themes with the values in the tests above; `inputDecorationTheme` (A43) border `WidgetStateInputBorder.resolveWith` (focused cyan 1.5, hovered `textSecondary`, disabled `fieldOutline` at alpha 0.5, error `error`), `contentPadding` 0/10, height 36 kept; `filledButtonTheme: FilledButtonThemeData(style: shellxPrimaryButtonStyle())`, `outlinedButtonTheme: …shellxSecondaryButtonStyle()`, `textButtonTheme: …shellxTextButtonStyle()`.
- `shellxPrimaryButtonStyle()` (A38, §7.1): `minimumSize` (80, 32), padding 0/14, `textStyle` `ShellxText.bodyStrong` (12/600), `foregroundColor` `onAccent`, `backgroundColor` transparent, `overlayColor` transparent, `elevation` 0, `shape: buttonShape(outsideRing: true)`, `backgroundBuilder: shellxGradientLayer(gradient: ShellxGradients.accentStrong, borderRadius: BorderRadius.circular(ShellxRadius.r6), disabledOpacity: 0.38)`. `ShellxPrimaryButton` builds its `FilledButton` with it (busy spinner 14 px white before the label, width kept — existing behaviour). `buildDialogTheme` keeps its dialog type and the 32/80/14 sizing on top of it.
- `shellxSecondaryButtonStyle()`: bg navy700 → hovered `overlayHover` → pressed `pushed`; `textPrimary` label; shadow `ShellxShadows.raised` at rest via a `backgroundBuilder` that draws a `DecoratedBox(boxShadow:)` only when not pressed/disabled; `buttonShape(outsideRing: false)`.
- `shellxTextButtonStyle()`: fg `link`; overlay hovered `rowHover`, pressed `rowPressed`; inside ring; disabled 0.38.
- `destructiveButtonStyle()`: own `backgroundBuilder` — solid `error`, hovered `errorHover`, pressed `error` with `ShellxGradients.pressedShade` on top; fg `onErr`; outside ring; so the theme's gradient never shows through.
- `TerminalColors`: every colour from `ShellxTerminalPalette` (§5.7: bg `#1C222E`, fg `#DDE3EC`, ANSI black `#2C3547`, bright black `#8590A6`, selection cyan 30 %); builds the `TerminalTheme` as today. Config themes and user keys are unchanged (A24).
- xterm patch (§6.8): `TerminalStyle` gains `final double? normalWeight; final double? boldWeight;` (constructor named params, `copyWith`, `fromTextStyle` leaves both null); `toTextStyle` adds `fontVariations: w == null ? null : [FontVariation('wght', w)]` with `w = bold ? boldWeight : normalWeight`. Cell measuring (10 × "m") unchanged. Add a `SHELLX_PATCHES.md` entry: "V2-5a: `TerminalStyle.normalWeight/boldWeight` → `wght` axis (variable system fonts)".
- `desktopTerminalStyle` (A37, R17): `final mac = defaultTargetPlatform == TargetPlatform.macOS;` no families + mac → `fontFamily: ShellxFonts.systemMono`, fallback `[bundled, ...const TerminalStyle().fontFamilyFallback]`, `normalWeight: regular ? 400 : 300`, `boldWeight: 700`; otherwise exactly today's code (no weights). `bundled` = `regular ? kTerminalFontFamily : kTerminalFontFamilyLight` as today. Doc comment states R17.
- `ai_file_viewer.dart`: `CodeEditorStyle(fontFamily: ShellxFonts.uiFamily(defaultTargetPlatform), fontFamilyFallback: ShellxFonts.uiFallback(defaultTargetPlatform), …)` (R13 baseline entry). `confirm_page.dart`: remove `fontFamily: 'JetBrainsMono'`.
- `main.dart` (A33): `await ShellxSystemFont.load();` right after `WidgetsFlutterBinding.ensureInitialized()`, before the version check; never in `daemon_main.dart`. `app.dart` `builder:` wraps `child` in `DefaultTextHeightBehavior(textHeightBehavior: const TextHeightBehavior(leadingDistribution: TextLeadingDistribution.even), child: …)` (A35), inside any existing builder wrapping.

**Commands** (from each dir):
- `apps/desktop`: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze` and `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test` (expect 3924 + new tests, 10 skipped).
- `packages/shellx_design`: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test` (unchanged, still green).
- `apps/mobile`: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/features/terminal` (the xterm change reaches the phone).
- `dart format` on touched files (80 columns).

**Commit:** `feat(v2-design): the desktop adapter takes the package — navy tokens, SF Mono theme, gradient buttons, weighted terminal`

### Task 6: The phone adapter — colours, typography, theme, fonts, terminal, the dark default

Spec A16, A18, A22, A25, A26, A31–A35, A37, A39, A41 (theme), §5.4, §5.9 (ĐT), §6.1, §6.5 (ĐT), §6.8, §10.3; R5, R12, R18, R19.

**Files:**
- Modify: `apps/mobile/lib/core/design/{app_colors,light_colors,dark_colors,typography,theme_data_factory,terminal_colors}.dart`
- Create: `apps/mobile/lib/core/platform/theme_default.dart` (export from `lib/core/core.dart`)
- Modify: `apps/mobile/lib/main.dart` (`main`), `lib/features/app/{app,splash_page}.dart` (`DefaultTextHeightBehavior`), `lib/features/app/font_licenses.dart` (`registerFontLicenses`)
- Modify: `lib/features/terminal/presentation/terminal_metrics.dart` (`shellxTerminalStyle`)
- Modify: every `lib/**` file with `FontFamily.jetBrainsMono` or `FontFamily.raleway` except `terminal_metrics.dart` (17 + 1 uses in 13 files: find with `grep -rn "FontFamily\." lib --include=*.dart | grep -v '\.gen\.dart'`)
- Delete: `apps/mobile/assets/fonts/Raleway-*.ttf` (18 files), `apps/mobile/assets/licenses/Raleway-OFL.txt`; Modify `apps/mobile/pubspec.yaml` (remove the `Raleway` family and its licence asset; add `shellx_design: any` if Task 1 did not); regenerate `lib/shared/src/{fonts,assets}.gen.dart`
- Tests: rewrite `test/core/design/design_tokens_test.dart`; create `test/core/platform/theme_default_test.dart`, `test/core/design/font_coverage_test.dart`; modify `test/platform_config_test.dart`, `test/app_test.dart`, `test/features/terminal/{terminal_page,terminal_metrics}_test.dart`

**Interfaces:**
- Consumes: Task 1 `ShellxFonts.*`, `ShellxSystemFont.load()`; Task 3 `ShellxPalette.*`, `ShellxLightPalette.*`, `ShellxGradients.{accent, accentStrong, wedge}`, `ShellxElevation` (`.dark`, `.light`), `ShellxTerminalPalette`, `contrastRatio`, `minContrastOnGradient`; Task 4 `ShellxTypeScale.mobile*`, `shellxWeight`, `shellxWeightedTextTheme`.
- Produces (Tasks 10, 12, V2-5b/C):
  - `AppColors` new getters: `Color get raised`, `Color get inset`, `Color get onAccent`, `Color get okSoft`, `LinearGradient get gradientStrong`, `LinearGradient get wedge`, `ShellxElevation get elevation`; `Gradient get gradient` now `ShellxGradients.accent`.
  - `const String themeDefaultKey = 'shellx_theme_default'`; `AdaptiveThemeMode resolveInitialThemeMode({required SharedPreferences prefs, required AdaptiveThemeMode? saved})` (R19; sync, writes via `prefs.setString` unawaited-safe — see code).
  - `shellxTerminalStyle(double fontSize)` unchanged signature, platform-dependent family and weights.

**Tests first:**
- `design_tokens_test.dart` (rewrite), per brightness (`DarkColors()` / `LightColors()`), exact hex: `background` `0xFF222834`/`0xFFEAEFF5`, `surface` `0xFF2C3547`/`0xFFF5F7FA`, `raised` `0xFF323B4F`/`0xFFFFFFFF`, `inset` `0xFF1C222E`/`0xFFE0E6EE`, `primaryText` `0xFFFFFFFF`/`0xFF141A26`, `secondaryText` `0xFFA7A9AE`/`0xFF4E586B`, `disable` `0xFF8E9096`/`0xFF596376`, `border` `0xFF76829C`/`0xFF717C92`, `divider` `0x14FFFFFF`/`0x1A141A26`, `primary` = `primaryFill` = `accent` `0xFF34C8E8`/`0xFF1767AD`, `onPrimary` `0xFF0E1A26`/`0xFFFFFFFF`, `onAccent` `0xFFFFFFFF` both, `primarySoft` `0xFF253E4D`/`0xFFDCE8F3`, `link` `0xFF5EADEE`/`0xFF1767AD`, `ok` `0xFF5ED39C`/`0xFF256B45`, `okDot` `0xFF5ED39C`/`0xFF2E8A57`, `warn` `0xFFF5B94E`/`0xFF7F4C00`, `warnSoft` = `lightGold` `0xFF3B3937`/`0xFFF2EDE6`, `error` = `mainRed` `0xFFFF8A94`/`0xFFB0202B`, `errorSoft` = `lightRed` `0xFF3D3440`/`0xFFF7E9EA`, `okSoft` = `lightGreen` `0xFF293D40`/`0xFFE9F0EC`, `scrim` `0x99000000`/`0x73141A26`, `keyAccent` `0xFF34C8E8`/`0xFF1767AD`, `keyboardLink` `0xFF5EADEE`/`0xFF14598F`, `keyboardError` `0xFFFF8A94`/`0xFFA3161D`, `keyboardBackground/Key/Ink` unchanged values; `gradient == ShellxGradients.accent`, `gradientStrong == ShellxGradients.accentStrong`, `wedge == ShellxGradients.wedge`, `elevation == ShellxElevation.dark` / `.light`; leftovers `mainGreen`, `mainGold`, `mediumRed`, `mediumOrange`, `blueGrey` = `ok`, `warn`, `error`, `warn`, `0xFF1C222E` (light: `0xFF141A26`).
  - The 11 existing contrast pairs, both brightnesses, with the new values (all pass; e.g. `keyAccent` on `keyboardKey` dark 4.60, light 5.87); new: `minContrastOnGradient(gradient, onAccent) ≥ 3.0`, `minContrastOnGradient(gradientStrong, onAccent) ≥ 4.5`; `primaryText` and `secondaryText` on `raised` and on `inset` ≥ 4.5; `disable` (placeholder) on `inset` closeTo(4.99, 0.01) dark / closeTo(4.82, 0.01) light and ≥ 4.5. (The `AppButton` expectations move to Task 10.)
  - `'no hex in the adapter'`: no `Color(0x` in `lib/core/design/*.dart` (read the files).
  - Theme (`ThemeDataFactory.create(b)`), both brightnesses: `fontFamily` per `debugDefaultTargetPlatformOverride` (iOS `'SF Mono'` + `['JetBrainsMono']`, Android `'JetBrainsMono'` + `[]`), never `'Raleway'`; `textTheme.bodyMedium!.fontVariations` has `wght` 400; `appBarTheme.titleTextStyle!.fontSize == 16`; `colorScheme.surfaceContainerLowest…Highest` dark navy900, navy850, navy750, navy750, navy700, light `0xFFFFFFFF`, `0xFFEAEFF5`, `0xFFF5F7FA`, `0xFFF5F7FA`, `0xFFFFFFFF`; `surfaceTint` transparent; `dialogTheme` r28, bg `surface`, `titleTextStyle` size 19 weight 700, `contentTextStyle` size 13; `bottomSheetTheme` top r28, bg `surface`, `showDragHandle` true, `dragHandleSize` (36, 4), `dragHandleColor` = `ShellxPalette.handle` / `ShellxLightPalette.handle`, `modalBarrierColor` = `scrim`, `elevation` 0 (the 90 % cap and `float2` are the sheet call sites', Task 12); `popupMenuTheme` bg `surface`, `RoundedRectangleBorder` r16 with side `divider` (item height 44 is set on the items, Task 12); `switchTheme` selected thumb `onPrimary`, track `primary`; `sliderTheme.activeTrackColor == primary`; `progressIndicatorTheme.color == primary`; `textSelectionTheme.cursorColor == primary`; `textButtonTheme` fg `link`.
- `test/core/platform/theme_default_test.dart` (`SharedPreferences.setMockInitialValues`): `'saved mode wins'` (saved `light`, prefs empty → `light`, `themeDefaultKey` not written); `'stored default is kept'` (`{'shellx_theme_default': 'system'}`, `shellx_installed` absent → `system`); `'fresh install defaults to dark'` (empty → `dark`, key now `'dark'`); `'existing user follows the system'` (`{'shellx_installed': true}` → `system`, key now `'system'`); `'unknown stored value is ignored'` (`'blue'`, fresh → `dark`).
- `platform_config_test.dart`: no `assets/fonts/Raleway-*` file; `pubspec.yaml` has no `Raleway` (family nor licence); the Raleway licence assertion (`:243`) removed.
- `app_test.dart` `'both font licences are registered'` → `'the JetBrains Mono licence is registered'`: the `LicenseRegistry` has a `JetBrains Mono` entry and none named `Raleway`.
- `terminal_page_test.dart:1555-1561`: the voice field's and hint's `TextStyle.fontFamily == null`; the effective family from `DefaultTextStyle`/theme is `'SF Mono'` on iOS, `'JetBrainsMono'` on Android (two platform overrides).
- `test/features/terminal/terminal_metrics_test.dart` (extend): iOS → `shellxTerminalStyle(14)` `fontFamily 'SF Mono'`, fallback first `'JetBrainsMono'`, `normalWeight 400`, `boldWeight 700`; Android → `'JetBrainsMono'`, weights null.
- `test/core/design/font_coverage_test.dart`: as Task 5's, over `apps/mobile/assets/fonts/JetBrainsMono-*.ttf` (4 files): 134 letters + 5 marks.

**Implementation notes:**
- `DarkColors`/`LightColors` return the §5.9 table through `ShellxPalette`/`ShellxLightPalette` constants only (dark: navy850, navy750, navy700, navy900, white100, white60, white50, fieldOutline, hairline, cyan, onCyan, onAccent, cyanSoft, link, ok, warn, warnSoft, error, errorSoft, okSoft, scrim; light: page, surface, raised, inset, text, textSecondary, placeholder, fieldOutline, hairline, primary, primarySoft, ok, okDot, warn, warnSoft, error, errorSoft, okSoft, scrim, keyboardLink, keyboardError). `keyAccent` dark cyan / light primary; `keyboardError` dark `error`. No `Color(0x` left in `lib/core/design` (§10.4).
- `AppTypography` (§6.5 ĐT, R12; instance getters reached by `context.typo`): each getter = `ShellxTypeScale.mobile*.copyWith(color: …, fontFeatures: liningFigures)`, weight 400 through `shellxWeight`; the `ColorTextStyle` extension (same file) `.medium/.semiBold/.bold` = `shellxWeight(this, FontWeight.w500/w600/w700)`, `.heavy` = `shellxWeight(this, FontWeight.w700)` (was `w800`). Sizes: display56 54, display42 40, display36 34, display32 30, heading28 26, heading26 24, heading24 22, heading20 19, title 17, subHeader 15, subHeader15 14, paragraph 13, paragraph13 13, metadata12/11/10/8 unchanged; px line heights unchanged.
- `ThemeDataFactory.create(b)`: `ColorScheme.fromSeed(…).copyWith(primary, onPrimary, primaryContainer: primarySoft, surface, onSurface: primaryText, onSurfaceVariant: secondaryText, error, outline: border, outlineVariant: divider, surfaceContainer*…, surfaceTint: Colors.transparent)`; `fontFamily: ShellxFonts.uiFamily(defaultTargetPlatform)`, `fontFamilyFallback: ShellxFonts.uiFallback(defaultTargetPlatform)` (replaces both `FontFamily.raleway` at `:60`, `:82`); `textTheme`/`primaryTextTheme` through `shellxWeightedTextTheme`; AppBar title `ShellxTypeScale.mobileAppBarTitle`; A39 themes (dialog r28 `surface`, title `heading20` 700, body `paragraph`, actions via `textButtonTheme` `link`; bottom sheet top r28, `surface`, drag handle `handle` 36×4, `modalBarrierColor` scrim, `elevation` 0; popup menu r16 `surface`; switch thumb `onPrimary` on `primary` when on, off thumb `secondaryText` on `inset` with `border` outline; slider/progress `primary` on `inset`; text selection `primary` at alpha 0.30, cursor/handle `primary`; icon `primaryText`; text button `link`). `segmentedButtonTheme` kept with token colours (R18).
- `resolveInitialThemeMode` (R19) — complete code (`lib/core/platform/theme_default.dart`):

```dart
import 'dart:async';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fresh_install.dart' show installMarkerKey;

/// A26: the theme a launch starts with. Read before DI sets [installMarkerKey].
const String themeDefaultKey = 'shellx_theme_default';

AdaptiveThemeMode resolveInitialThemeMode({
  required SharedPreferences prefs,
  required AdaptiveThemeMode? saved,
}) {
  if (saved != null) return saved;
  final stored = prefs.getString(themeDefaultKey);
  for (final mode in AdaptiveThemeMode.values) {
    if (mode.name == stored) return mode;
  }
  final fresh = !(prefs.getBool(installMarkerKey) ?? false);
  final mode = fresh ? AdaptiveThemeMode.dark : AdaptiveThemeMode.system;
  unawaited(prefs.setString(themeDefaultKey, mode.name)); // the cache updates synchronously
  return mode;
}
```

- `main.dart`: `WidgetsFlutterBinding.ensureInitialized(); await ShellxSystemFont.load(); registerFontLicenses(); final prefs = await SharedPreferences.getInstance(); final themeMode = resolveInitialThemeMode(prefs: prefs, saved: await AdaptiveTheme.getThemeMode());` then `runApp` as today with `initial: themeMode`. `app.dart` and `splash_page.dart` `MaterialApp.builder` wrap in `DefaultTextHeightBehavior(… leadingDistribution: even)` (A35).
- Remove the `fontFamily: FontFamily.jetBrainsMono` / `FontFamily.raleway` arguments so code follows the theme (A31); drop now-unused `fonts.gen.dart` imports. `font_licenses.dart` registers JetBrains Mono only.
- `shellxTerminalStyle` (A37, §6.8): iOS → `TerminalStyle(fontSize:, fontFamily: ShellxFonts.systemMono, fontFamilyFallback: [ShellxFonts.bundledMono, ...const TerminalStyle().fontFamilyFallback], normalWeight: 400, boldWeight: 700)`; else `fontFamily: ShellxFonts.bundledMono` (the `FontFamily.jetBrainsMono` value), no weights. `TerminalColors` (ĐT) reads `ShellxTerminalPalette` (§5.7), builds its `TerminalTheme`.
- Regenerate: `PATH=~/fvm/versions/3.41.4/bin:$PATH dart run build_runner build --delete-conflicting-outputs` (updates `fonts.gen.dart` — no `raleway` — and `assets.gen.dart` — no `ralewayOFL`); commit both.

**Commands** (`apps/mobile`): `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get` (root), build_runner as above, `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze` (only the pre-existing `unnecessary_import` info), `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`; `dart format` touched files (120 columns).

**Commit:** `feat(v2-design): the phone adapter takes the package — navy and light tokens, SF Mono theme, dark default, Raleway removed`

### Task 7: Raw-style guards in both apps, with their baselines

Spec A46, §10.4; R13, R22. Runs after Tasks 5–6 (the baseline is taken then; Tasks 8–12 lower it).

**Files:**
- Create: `apps/desktop/test/design/raw_style_guard_test.dart`, `apps/desktop/test/design/raw_style_baseline.dart`
- Create: `apps/mobile/test/design/raw_style_guard_test.dart`, `apps/mobile/test/design/raw_style_baseline.dart`

**Interfaces:**
- Consumes: nothing from the package.
- Produces: `const Map<String, Map<String, int>> rawStyleBaseline` in each `raw_style_baseline.dart` (path relative to the app root, e.g. `'lib/src/ui/ai/ai_theme.dart'` → pattern → count; only non-zero entries; keys sorted). Later tasks edit it downward. `Map<String, int> countRawStyles(String source)` (top-level in the guard test file).

**Tests first** (each guard test file):
- `'the counter matches only whole tokens'`: `countRawStyles('AppColors.red Colors.red Colors.transparent CupertinoIcons.add Icons.add ShellxIcons.add _Icons.x TextStyle( fontWeight: BoxShadow( ImageFilter.blur(')` == `{'Colors.': 1, 'CupertinoIcons.': 1, 'Icons.': 1, 'TextStyle(': 1, 'fontWeight:': 1, 'BoxShadow(': 1, 'ImageFilter.blur(': 1}`.
- `'no new hard-coded style (§10.4)'`: scan, compare exactly with `rawStyleBaseline`; fail with one line per difference — higher: `new hard-coded style: <file> <pattern> <baseline> → <now>`; lower: `lower the baseline: <file> <pattern> <baseline> → <now>` — then print the whole current map as Dart source (`const Map<String, Map<String, int>> rawStyleBaseline = {…};`) ready to paste.
- `'adapters hold no hex'`: desktop `lib/src/ui/theme/*.dart`, mobile `lib/core/design/*.dart` contain no `Color(0x`.

**Implementation notes:**
- Patterns (exact list, each compiled as `RegExp('(?<![A-Za-z0-9_])' + RegExp.escape(p))`, except `Colors.` which is `(?<![A-Za-z0-9_])Colors\.(?!transparent\b)`): `Color(0x`, `Color.fromARGB(`, `Color.fromRGBO(`, `Colors.`, `TextStyle(`, `fontSize:`, `fontWeight:`, `fontFamily:`, `BoxShadow(`, `BackdropFilter(`, `ImageFilter.blur(`, `Icons.`, `CupertinoIcons.`. Raw text, comments included (R22).
- Scan `lib/**/*.dart` from the app root (`Directory('lib')`, tests run with cwd = app root), excluding by path: suffixes `.g.dart`, `.gr.dart`, `.config.dart`, `.gen.dart`; prefixes `lib/l10n/`, `lib/shared/src/intl/`; file `lib/shared/src/l10n.dart`; adapters `lib/src/ui/theme/` (desktop), `lib/core/design/` (mobile). Paths with `/` separators, sorted.
- Baseline: run the test once, paste the printed map into `raw_style_baseline.dart` with a header comment ("§10.4: exact counts; lower when a task removes a style; never raise"). Union counts before A for orientation (generated/adapters excluded) — desktop: `Icons.` 171, `fontWeight:` 19, `fontSize:` 12, `TextStyle(` 5, `fontFamily:` 5, `Color(0x` 1, `Colors.` 1; mobile: `Icons.` 104, `TextStyle(` 22, `fontSize:` 21, `fontFamily:` 20, `Colors.` 20, `Color(0x` 15, `fontWeight:` 9, `BoxShadow(` 5, `BackdropFilter(` 1, `ImageFilter.blur(` 1; after Tasks 5–6 `fontFamily:` is lower in both (mobile: the 17 + 1 `FontFamily.*` uses removed, A31; desktop: `confirm_page.dart`, `kAiMono`).
- End state (Task 16 checks): `Icons.`, `CupertinoIcons.` 0; `fontWeight:` 0 except R13's `shellx_config.dart`; `BackdropFilter(`/`ImageFilter.blur(` 1 each in `lib/features/pairing/presentation/pages/qr_scanner_page.dart`; `lib/core/handler/popup_handler.dart` absent; R13's other entries (`config/config_color.dart` `Color(0x`, `config/font_probe.dart` `TextStyle(`, `ai_file_viewer.dart` `fontFamily:`) stay.

**Commands:** in `apps/desktop` and `apps/mobile`: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/design` then the full `flutter analyze` + `flutter test`.

**Commit:** `test(v2-design): raw-style guards in both apps with exact baselines (§10.4)`

### Task 8: `ShellxIcons` and every Material icon replaced

Spec A45, §7.4, §10.1 `icons_test.dart`, success criterion 5. One commit for `lib/` and `test/` (A45).

**Files:**
- Create: `packages/shellx_design/lib/src/icons.dart`, `packages/shellx_design/test/icons_test.dart`; Modify `packages/shellx_design/lib/shellx_design.dart` (export)
- Modify: every `apps/desktop/{lib,test}/**/*.dart` and `apps/mobile/{lib,test}/**/*.dart` with `Icons.` (desktop 74 glyph kinds, mobile 60), incl. `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart` (`kPhoneIcon`), `ui/ai/ai_tool_card.dart` (`_icon`), mobile `features/ai/presentation/widgets/ai_items.dart`
- Modify: `apps/mobile/pubspec.yaml` (drop `cupertino_icons: ^1.0.8`; the package pins 1.0.9); both `test/design/raw_style_baseline.dart` (`Icons.` → 0)
- Scratch (not committed): `SCRATCH/v25a-tools/replace_icons.py`

**Interfaces:**
- Consumes: Task 1's package pubspec (`cupertino_icons: 1.0.9`).
- Produces (Tasks 9–12, V2-5b T48, V2-5c §4.8): `abstract final class ShellxIcons` with the 95 `static const IconData` roles of §7.4 (names exactly: `add, back, close, more, chevronRight, expand, collapse, openExternal, refresh, search, settings, tune, edit, moveFile, delete, copy, undo, send, queue, stop, stopCircle, scrollToEnd, maximize, restore, sidePanel, splitRight, splitDown, download, update, signOut, mention, scanQr, keyboard, mic, micOn, attachPhoto, camera, pin, resume, history, check, success, successOutline, failure, warning, error, danger, info, infoFill, pending, waiting, dotFill, dot, radioOn, checkboxOn, checkboxOff, checkboxMixed, prOpen, prMerged, offline, visible, hidden, notifications, notificationsUnread, notificationsOff, ai, agentProgram, thinking, fetch, switchMode, plan, file, readText, image, folderMissing, tool, toolOther, tab, tmux, lock, phone, laptop, desktop, terminal, faceId, fingerprint, sshHost, voiceMode, voiceMicOn, voiceMicOff, voiceEnd, voiceStopTurn, voiceExpand, voiceCollapse, voiceNeedsYou`) and `static const Map<String, IconData> roles` (95 entries, name → constant; V2-5b adds its roles to both).

**Tests first** (`packages/shellx_design/test/icons_test.dart`):
- `'Cupertino font except the four Material fallbacks'`: for every `roles` entry, `fontFamily == 'CupertinoIcons'` and `fontPackage == 'cupertino_icons'`, except exactly `terminal`, `faceId`, `fingerprint`, `sshHost` which have `fontFamily == 'MaterialIcons'` and equal `Icons.terminal_rounded`, `Icons.face_rounded`, `Icons.fingerprint_rounded`, `Icons.dns_rounded`; 91 Cupertino, 4 Material.
- `'voice roles (V2-5c §4.8)'`: `voiceMode == CupertinoIcons.waveform`, `voiceMicOn == CupertinoIcons.mic`, `voiceMicOff == CupertinoIcons.mic_slash`, `voiceEnd == CupertinoIcons.xmark`, `voiceStopTurn == CupertinoIcons.stop_fill`, `voiceExpand == CupertinoIcons.arrow_up_left_arrow_down_right`, `voiceCollapse == CupertinoIcons.chevron_down`, `voiceNeedsYou == CupertinoIcons.exclamationmark_triangle`.
- `'roles lists every declared constant'`: parse `lib/src/icons.dart` with `RegExp(r'static const IconData (\w+)')`; the set equals `roles.keys.toSet()`, length 95, and `roles[name]` is the same glyph (`codePoint`) as declared (spot-check `add`, `fetch` = `CupertinoIcons.globe`, `tool` = `square_grid_2x2`, `toolOther` = `wrench`, `phone` = `device_phone_portrait`).
- `'cupertino_icons pinned'`: `File('pubspec.yaml')` contains a line `  cupertino_icons: 1.0.9`.
- App side (same commit): desktop `test/ui/ai/ai_tool_card_test.dart` gains `'tool kinds share the §7.4 table'` — `read→file, edit→edit, delete→delete, move→moveFile, search→search, execute→terminal, fetch→fetch, think→thinking, switchMode→switchMode, other→toolOther` via `find.byIcon(ShellxIcons.x)`; mobile `test/features/ai/ai_items_test.dart` likewise for `fetch` (globe) and `other` (`toolOther`). Every existing `find.byIcon(Icons.x)` in `test/**` becomes `find.byIcon(ShellxIcons.<role>)`.

**Implementation notes:**
- `icons.dart`: the 95 roles with the glyphs of §7.4 verbatim (e.g. `back` `chevron_back`, `settings` `gear_alt`, `tune` `slider_horizontal_3`, `moveFile` `square_pencil`, `queue` `text_badge_plus`, `maximize` `arrow_up_left_arrow_down_right`, `restore` `arrow_down_right_arrow_up_left`, `sidePanel` `sidebar_right`, `splitRight` `square_split_2x1`, `splitDown` `square_split_1x2`, `download` `arrow_down_to_line`, `signOut` `square_arrow_right`, `pin` `pin_fill`, `resume` `arrow_counterclockwise`, `history`/`pending` `clock`, `radioOn` `largecircle_fill_circle`, `checkboxMixed` `minus_square`, `prOpen` `arrow_branch`, `prMerged` `arrow_merge`, `offline` `wifi_slash`, `agentProgram` `chevron_left_slash_chevron_right`, `thinking` `lightbulb`, `switchMode` `arrow_right_arrow_left`, `folderMissing` `folder_badge_minus`, `tab` `square_on_square`, `tmux` `square_split_2x2`, …); imports `package:flutter/cupertino.dart` and `package:flutter/material.dart` (for the four `Icons.*`). One-line doc per role naming its use.
- Replacement (deterministic): `replace_icons.py` holds the "Thay `Icons.*`" column as a dict (`arrow_back`/`arrow_back_ios_new`→`back`, `expand_more`/`keyboard_arrow_down`→`expand`, `expand_less`/`keyboard_arrow_up`→`collapse`, `search_off`→`search`, `send`/`arrow_upward`→`send`, `stop`/`stop_rounded`→`stop`, `fullscreen`/`open_in_full`→`maximize`, `check`/`check_rounded`→`check`, `warning_amber`/`warning_amber_rounded`→`warning`, `circle_outlined`/`radio_button_unchecked`→`dot`, `cloud_off_outlined`/`link_off`→`offline`, `notifications_none`/`notifications_active_outlined`→`notifications`, `public`/`cloud_download_outlined`→`fetch`, `image_outlined`/`broken_image_outlined`→`image`, `lock_outline`/`key_outlined`→`lock`, `phone_iphone_outlined`/`smartphone`→`phone`, `add_photo_alternate_outlined`/`photo_library_outlined`→`attachPhoto`, `mic_none`→`mic`, `mic`→`micOn`, `terminal`→`terminal`, …); it rewrites `(?<![A-Za-z0-9_])Icons\.(\w+)` → `ShellxIcons.<role>` and **exits non-zero on any glyph not in the dict** (checked on the union: every glyph maps). Context-dependent first, by hand: `Icons.extension_outlined` → `ShellxIcons.toolOther` in `ui/ai/ai_tool_card.dart` (`ToolKind.other`) and mobile `ai_items.dart`; → `ShellxIcons.tool` in `ui/tools/tool_bar.dart`, `ui/tools/tool_project_list.dart`, `ui/tools/tool_sidebar_group.dart`, `ui/terminal/session_sidebar.dart`, `ui/ai/ai_header.dart`, mobile `session_picker.dart`. `kPhoneIcon = ShellxIcons.phone`. Desktop `ToolKind.fetch` changes from cloud to `ShellxIcons.fetch` (globe, §7.4).
- Add `import 'package:shellx_design/shellx_design.dart';` where needed; remove `package:flutter/material.dart` only if it becomes unused. Tray and app icons unchanged. `uses-material-design: true` stays (four fallbacks).
- Lower both baselines: every `Icons.` entry removed; `CupertinoIcons.` none.

**Commands:** `packages/shellx_design`, `apps/desktop`, `apps/mobile`: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get` (root), `flutter analyze`, `flutter test` (all three); `dart format` touched files.

**Commit:** `feat(v2-design): ShellxIcons — 95 Cupertino roles replace every Material icon in both apps`

### Task 9: Desktop components

Spec A12 (DT), A38 (widgets), A40, A41 (DT), A44, §7.1, §7.3, §10.2 "Component mới", §10.5 (DT); R20, R21.

**Files:**
- Create: `apps/desktop/lib/src/ui/components/{shellx_chip,shellx_segmented,shellx_card,shellx_brand_line}.dart`
- Create: `apps/desktop/test/ui/components/{shellx_chip,shellx_segmented,shellx_card,shellx_brand_line,shellx_icon_button,notice_toast,shellx_menu,dialog_box}_test.dart`, `apps/desktop/test/ui/components/sidebar_shadow_test.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart` (`ShellxIconButton`, `NoticeToast`), `ui/terminal/shellx_menu.dart` (`showShellxMenu`), `ui/dialogs/route_dialog.dart` (`RouteDialogHost` box), `ui/dialogs/dialog_layout.dart` (`DialogBody`), `ui/pages/login_page.dart`, `ui/pages/onboarding_page.dart` (`DialogBody(brand: true)`), `ui/ai/ai_changes_panel.dart` (`SegmentedButton<AiChangesScope>` → `ShellxSegmented<AiChangesScope>`)
- Modify: `apps/desktop/test/design/raw_style_baseline.dart` (lower if counts drop)

**Interfaces:**
- Consumes: Task 4 `ShellxInsetBox`, `ShellxInsetShadow`, `shellxGradientLayer`; Task 5 `ShellxDesktopColors.{onAccent, overlayHover, overlayPressed, pushed, …}`, `ShellxShadows.{e1, e2, raised, inset}`, `ShellxText.*`, `ShellxMotion.{slide, slideCurve}`, `ShellxRadius.*`, `OutsideFocusRingBorder`, `buttonShape`; Task 3 `ShellxGradients.{accent, accentStrong, hoverShade, pressedShade}`; Task 8 `ShellxIcons`; `AppLocalizations.appTitle`.
- Produces (Task 11, V2-5b):
  - `ShellxChip({Key? key, required String label, IconData? icon, bool selected = false, VoidCallback? onPressed, String? tooltip})`.
  - `class ShellxSegment<T> { const ShellxSegment({required T value, required String label, IconData? icon}); }`; `ShellxSegmented<T>({Key? key, required List<ShellxSegment<T>> segments, required T selected, required ValueChanged<T>? onChanged})` (`onChanged == null` → disabled).
  - `enum ShellxCardVariant { flat, raised, inset }`; `ShellxCard({Key? key, required Widget child, ShellxCardVariant variant = ShellxCardVariant.flat, VoidCallback? onTap, EdgeInsetsGeometry padding = const EdgeInsets.all(12)})`.
  - `ShellxBrandLine({Key? key})` (reads `AppLocalizations.of(context).appTitle`).
  - `enum ShellxIconButtonVariant { flat, raised }`; `ShellxIconButton(…, ShellxIconButtonVariant variant = ShellxIconButtonVariant.flat)` (existing params kept; `selected == true` → gradient, R20).
  - `DialogBody({…, bool brand = false})`.

**Tests first:**
- `shellx_chip_test.dart`: size 24 high, padding 0/10, label `ShellxText.small`-sized 11.5 weight 500 (`wght` 500), radius 10, icon 14; rest: border `hairlineStrong` (`0x1AFFFFFF`), transparent fill, no `BoxShadow`; hovered fill navy800 `0xFF28303F`; pressed `pushed`; `selected: true` → `ShellxGradients.accentStrong` gradient, label `0xFFFFFFFF` weight 600, hovered/pressed overlay `0x14000000`/`0x29000000`; focus ring inside (rest) / outside (selected); `onPressed: null` → `Opacity` 0.38.
- `shellx_segmented_test.dart`: track 28 high, padding 2, radius 10, `ShellxInsetBox` with `ShellxShadows.inset`; segments 24 high, radius 8, min width 56, padding 0/10, text 11.5; unselected text `textSecondary`, hovered `textPrimary` on navy800; selected `accentStrong`, white 600, shadow `raisedSmall`; the tile animates with `ShellxMotion.slide` (pump half → between positions; with `MediaQuery(disableAnimations: true)` → final at once); **one tab stop** (Tab from before moves focus onto the control, a second Tab leaves it); `→`/`←` change the selection and call `onChanged` with the next/previous value (no wrap at the ends); `Semantics` per segment: `isButton`, `isSelected` (true on the selected only), `isInMutuallyExclusiveGroup`, `label` = segment label; `onChanged: null` → 0.38 and no callback.
- `shellx_card_test.dart`: radius 16, padding 12; `flat` navy750 + `hairlineStrong` side, no shadow; `raised` shadow `ShellxShadows.raised`; `inset` uses `ShellxInsetBox`; with `onTap`: hovered `overlayHover`, pressed `pushed`, focus ring inside; without `onTap` no `InkWell`/`FocusableActionDetector`.
- `shellx_brand_line_test.dart`: text `'ShellX: Remote AI agents'` once Task 13 lands — until then assert it equals `AppLocalizations.of(ctx).appTitle` (EN and VI); style `ShellxText.label` (11.5/16/600) in `accent` `0xFF34C8E8`; `DialogBody(brand: true)` draws it 8 px above the title (`tester.getBottomLeft(brand).dy + 8 == getTopLeft(title).dy`); `brand: false` has none.
- `app_dialogs_test.dart` (existing): the sign-in dialog stays `lessThan(520)` high with the brand line (A12).
- `shellx_icon_button_test.dart`: hit 28, visual 24, glyph 16, radius 10; `flat` transparent, hovered navy800 + glyph `textPrimary`, pressed navy650; `raised` navy700 + `ShellxShadows.raised`; `selected: true` → `ShellxGradients.accent` gradient, glyph `0xFFFFFFFF`, pressed overlay `0x29000000`, outside ring; `busy` → 12 px spinner (as today).
- `notice_toast_test.dart`: radius 16, max width 420, padding 8/12, shadow `ShellxShadows.e1`; normal: bg navy750, border `hairlineStrong`, text `textPrimary`; error: `noticeBg` `0xFF453F50`, border `noticeLine` `0xFF5F4959`, text `noticeText` `0xFFFFD9DB`; hover pauses the timer (existing behaviour kept).
- `shellx_menu_test.dart`: menu bg navy750, radius 16, side `hairlineStrong`, shadow `e1`, padding 4; item height 28, radius 10, padding 0/10; hovered item bg `overlayHover`, text `textTitle`, shortcut hint `textDialog2`; pressed `overlayPressed`; disabled item 0.38 and keeps its slot.
- `dialog_box_test.dart`: `RouteDialogHost` box radius 28, bg navy750, side `hairlineStrong`, shadow `e2`, barrier `0x99000000`; widths 400/480/520 unchanged.
- `test/ui/ai/ai_changes_safety_test.dart` (the panel's test) stays green and gains `'the scope control is ShellxSegmented'`: `find.byType(ShellxSegmented<AiChangesScope>)` one, `find.byType(SegmentedButton<AiChangesScope>)` none; tapping the other scope changes the list as before.
- `sidebar_shadow_test.dart` (§10.5 DT, Review Focus 5; reuse the `SessionSidebar` harness of `test/ui/sidebar_polish_test.dart`): pump `SessionSidebar` with 30 tabs, one selected; `find.descendant(of: sidebar, matching: …)` collecting every `BoxDecoration.boxShadow` (and `Material.elevation > 0`) → total `BoxShadow` count ≤ 2. Green now; Task 11 (raised selected row) must keep it green.

**Implementation notes:**
- Values per §7.1 table rows "Chip", "Chip đang chọn", "Segmented", "Segment đang chọn", "Thẻ", "Nút icon", "Toast", "Menu", "Hộp thoại", "Dòng thương hiệu"; colours only through `ShellxDesktopColors`/`ShellxGradients`, no `Color(0x`, no `fontWeight:` (use `shellxWeight`) — the guard must not rise.
- Gradient fills reuse `shellxGradientLayer` (hover/pressed shades, disabled opacity) inside a `FilledButton`-free `DecoratedBox`; painters in a `RepaintBoundary` (A44).
- `ShellxSegmented`: one `Focus` node for the whole control (`FocusableActionDetector` with `ArrowLeft`/`ArrowRight` intents); the selected tile is an `AnimatedAlign`/`AnimatedPositioned` with `ShellxDurations.of(context, ShellxMotion.slide)`; segments are not separately focusable; the outside ring wraps the selected segment when the control has focus.
- `ShellxBrandLine` sits in `DialogBody` above the title with `SizedBox(height: 8)`; `login_page.dart` (sign-in and sign-up) and `onboarding_page.dart` pass `brand: true` (A12); nothing else.
- `NoticeToast` timing from `ShellxMotion` (`toastVisible` 4 s, `toastVisibleError` 6 s, existing names kept).
- No `BoxShadow` on chips, flat cards, menu items or segments other than the selected one (A44).

**Commands** (`apps/desktop`): `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze`; `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/components test/ui/app_dialogs_test.dart test/design` then the full `flutter test`; `dart format` touched files.

**Commit:** `feat(v2-design): desktop components — chip, segmented, card, brand line; icon button, toast, menu and dialog box on tokens`

### Task 10: Phone components

Spec A12 (ĐT), A22, A27, A28, A38 (ĐT), A40, A41, A42, §7.1, §10.3 "Component mới"; R21.

**Files:**
- Modify: `apps/mobile/lib/shared/src/{app_button,app_text_field,notice_banner,confirm_dialog,app_error_view}.dart`, `lib/features/auth/presentation/widgets/password_text_field.dart`, `lib/core/handler/popup_handler.dart` (`PopupHandler.showMessage`, `showLoading`)
- Modify (A22, `AppButton` icon colour only): `lib/features/terminal/presentation/widgets/session_picker.dart` (the "Phiên mới" prefix), `lib/features/machines/presentation/pages/machine_list_page.dart` (two prefixes)
- Create: `apps/mobile/lib/shared/src/{shellx_bottom_bar,shellx_segmented,shellx_chip,shellx_card,shellx_brand_header}.dart`; export from `lib/shared/shared.dart`
- Create: `apps/mobile/test/shared/{app_button,app_text_field,toast,shellx_bottom_bar,shellx_segmented,shellx_chip,shellx_card,shellx_brand_header}_test.dart`; modify `test/shared/app_error_view_test.dart`
- Modify: `apps/mobile/test/design/raw_style_baseline.dart` (`popup_handler.dart` entry gone; others lowered)

**Interfaces:**
- Consumes: Task 4 `ShellxInsetBox`, `ShellxSlantBorder`, `ShellxWedge`, `shellxWeight`; Task 6 `AppColors.{raised, inset, onAccent, okSoft, gradient, gradientStrong, elevation, …}`, `AppTypography.*`; Task 3 `ShellxDurations.{press, slide, toastVisiblePhone}`, `ShellxCurves.*`, `ShellxPalette.navy825`, `ShellxElevation` lists; Task 8 `ShellxIcons`; `S.of(context).appTitle`; `ShellxLogo` (existing).
- Produces (Task 12, V2-5b, V2-5c):
  - `class ShellxBottomBarItem { const ShellxBottomBarItem({required IconData icon, required String label, int? badgeCount, bool badgeDot = false}); }`; `ShellxBottomBar({Key? key, required List<ShellxBottomBarItem> items, required int currentIndex, required ValueChanged<int>? onTap})`.
  - `ShellxSegment<T>`, `ShellxSegmented<T>({Key? key, required List<ShellxSegment<T>> segments, required T selected, required ValueChanged<T>? onChanged})` (same shape as desktop, R21).
  - `ShellxChip({Key? key, required String label, IconData? icon, bool selected = false, VoidCallback? onPressed})`.
  - `enum ShellxCardVariant { flat, raised, inset }`; `ShellxCard({Key? key, required Widget child, ShellxCardVariant variant = ShellxCardVariant.flat, VoidCallback? onTap, EdgeInsetsGeometry padding = const EdgeInsets.all(16)})`.
  - `ShellxBrandHeader({Key? key, bool splash = false})`.

**Tests first:**
- `app_button_test.dart` (moved from design tokens, §10.3): height 54, radius 10; an `Ink` whose `BoxDecoration.gradient == ShellxGradients.accent`; label 15 / weight 700 (`wght` 700) in `onAccent` `0xFFFFFFFF` (default `textColor` becomes `onAccent`); `prefix`/`suffix` icon colour from `IconTheme` = `onAccent`; shadow `elevation.cta`; pressed → `Transform.scale` 0.98 within `ShellxDurations.press`; disabled → opacity 0.45, no shadow; with `MediaQuery(textScaler: TextScaler.linear(0.9))` (`scale(15) < 15`) the gradient is `ShellxGradients.accentStrong`; a `backgroundColor` override (destructive) → solid colour, no gradient.
- `app_text_field_test.dart` (and `PasswordTextField`): height 52, radius 16, fill `inset`, border 1.5 `border`, `ShellxInsetBox` present; focused → border `primary` width 2; error → border `error` and the error text 4 px below in `paragraph13` bold `error`.
- `toast_test.dart` (A41): `PopupHandler().showMessage(…)` in dark theme → toast at top centre, radius 16, bg `0xFF2C3547` (navy750, **not** `Colors.white`), icon 20 coloured `ok`/`warn`/`error`/`primary` by `ToastificationType`, title 14 / 600, description 13 `secondaryText`; error kind bg `errorSoft`; auto-close `ShellxDurations.toastVisiblePhone` (3 s); swipe up dismisses (as today); light theme bg `0xFFF5F7FA`.
- `shellx_bottom_bar_test.dart`: bar height 64 + bottom safe area, bg navy825 `0xFF242C3B` (light `raised`), top radius 28, shadow `float1` mirrored up (negative `dy`); items equal width, each ≥ 48×48, icon 24, label 12 / 600 `maxLines: 1`; label text scale capped: at `TextScaler.linear(2.0)` the label's effective scale is 1.3; inactive icon/label `secondaryText`; active: a 56×36 tile with `ShellxSlantBorder(radius: 10, slant: 4)`, `gradient` `accent`, shadow `cta`, icon white, label `primaryText` weight 700; tapping item 2 calls `onTap(2)`, the tile slides over `ShellxDurations.slide` (mid-pump between) and lands at once with `disableAnimations: true`; `HapticFeedback.selectionClick` called (mock `SystemChannels.platform`, `HapticFeedback.vibrate` with `HapticFeedbackType.selectionClick`); badge dot 8 `accent`, count pill 16 high `error` with `onError` text; semantics: bar `container` + `explicitChildNodes`, each item `isButton`, `isSelected` on the current only, `isInMutuallyExclusiveGroup`, `label`; `onTap: null` → 0.45 and not tappable.
- `shellx_segmented_test.dart`: track ≥ 48 high, padding 4, radius 14, `ShellxInsetBox`; segments ≥ 40 high, radius 10, text 13 / 600, up to 2 lines at 320 pt and 2× text (grows, never clips: no `RenderParagraph.didExceedMaxLines`); selected `gradientStrong`, white 600, `raisedSmall`; semantics as desktop; tap changes selection; `onChanged: null` → 0.45.
- `shellx_chip_test.dart`: height 36, padding 0/14, 13 / 600, radius 10, icon 18; bg `raised`, border `ShellxPalette.hairlineStrong` (dark) / `ShellxLightPalette.hairline` (light) (§7.1), no shadow; selected `gradientStrong`, white 600; disabled 0.45.
- `shellx_card_test.dart`: radius 16, padding 16; `flat` `surface` + border; `raised` `elevation.raised`; `inset` `ShellxInsetBox`; pressable: pressed fill `inset` (the phone has no `pushed` role: sunken = `inset`), no shadow, focus ring inside.
- `shellx_brand_header_test.dart`: header: `ShellxLogo(size: 48)` + `S.of(context).appTitle` in `context.typo.title` weight 700, `maxLines: 2`; splash: logo 72 above, `heading20` 700 below, centred; at 320 pt width with `TextScaler.linear(2.0)` the name wraps to 2 lines without overflow (no exception, `didExceedMaxLines` false); logo semantics label = `appTitle`.
- `app_error_view_test.dart`: the retry `AppButton` icon takes `onAccent` from `IconTheme` (no own colour).

**Implementation notes:**
- `AppButton` (A22, A27, A38; `context.colors`, `context.typo`): `radius` default 15 → 10; the existing `Ink` gets `BoxDecoration(gradient: small ? colors.gradientStrong : colors.gradient, borderRadius: radius, boxShadow: state.isDisable ? null : colors.elevation.cta)` with `small = MediaQuery.textScalerOf(context).scale(15) < 15`; `IconTheme.merge(data: IconThemeData(color: colors.onAccent))` around `prefix`/`suffix`; press scale 0.98 via `AnimatedScale(duration: ShellxDurations.press)`; disabled `Opacity(0.45)`; existing loading spinner kept; `backgroundColor` param non-null → solid fill (no gradient). Remove the self-set `onPrimary` icon colours at `session_picker.dart` ("Phiên mới"), `machine_list_page.dart` (both prefixes) and `app_error_view.dart` (A22).
- `AppTextField`/`PasswordTextField` (A28, A43 ĐT): `ShellxInsetBox(color: colors.inset, shadow: colors.elevation.inset, borderRadius: 16, border: BorderSide(color: colors.border, width: 1.5))` around a borderless `TextField`; focus/error borders as in the tests; text 15.
- `notice_banner.dart` radius 13 → 16; `confirm_dialog.dart` follows `dialogTheme` (drop own shape/colour), its destructive action uses `AppButton(backgroundColor: colors.error)`.
- Toast (`popup_handler.dart`, A41): `toastification.show(alignment: Alignment.topCenter, autoCloseDuration: ShellxDurations.toastVisiblePhone, backgroundColor: kind == error ? colors.errorSoft : colors.surface, foregroundColor: colors.primaryText, primaryColor: <ok|warn|error|primary>, borderRadius: BorderRadius.circular(16), boxShadow: colors.elevation.float1, …)`; icon `ShellxIcons.success/warning/error/info` size 20; title `context.typo.subHeader15.semiBold` (14/600), description `context.typo.paragraph13` (13) `secondaryText`; no `Colors.*`, no `Color(0x` left (`showLoading`'s `Colors.transparent` is allowed by the guard).
- `ShellxBottomBar` (A42; B places it): `Semantics(container: true, explicitChildNodes: true)`; `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3)` around labels; active tile `AnimatedPositioned` over `ShellxDurations.of(context, ShellxDurations.slide)` (0 with reduced motion); `HapticFeedback.selectionClick()` on change; press `AnimatedScale` 0.96; focus ring cyan 2 px around the item.
- `ShellxBrandHeader` (A12): `Column(ShellxLogo(size: splash ? 72 : 48), SizedBox(8), Text(S.of(context).appTitle, maxLines: 2, textAlign: center, style: splash ? context.typo.heading20.bold : context.typo.title.bold))`. Task 12 places it (splash, login, register, first-run empty state).
- All values through `AppColors`/`AppTypography`/package constants; weights through `shellxWeight` or the `.bold/.semiBold` getters (guard must not rise).

**Commands** (`apps/mobile`): `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze`; `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/shared test/design` then the full `flutter test`; `dart format` touched files (120 columns).

**Commit:** `feat(v2-design): phone components — gradient AppButton, inset fields, dark toast, bottom bar, segmented, chip, card, brand header`

### Task 11: Desktop screens (§8.1)

**Files:**
- Modify `apps/desktop/lib/src/ui/terminal/`:
  - The sidebar and its rows: `session_sidebar.dart` (the selected row in `_TabRow`/`_Item`), `session_tab_row.dart`, `sidebar_new_button.dart`, `sidebar_remote.dart`.
  - The header and the marks on a row: `workspace_header.dart`, `attention_marks.dart`, `agent_badge.dart`, `agent_chip.dart`.
  - The panes: `terminal_pane.dart`, `pane_tree_view.dart`, `terminal_workspace_page.dart`.
  - The strips: `info_strip.dart`, `remote_strip.dart`, `resume_banner.dart`.
  - The overlays: `terminal_overlays.dart` (`EmptyTerminalState`), `notifications_panel.dart`, `find_bar.dart`, `key_sequence.dart`.
- Modify `apps/desktop/lib/src/ui/tools/*` (all files, V2-3).
- Modify `ui/config/{command_palette,search_all_overlay,shortcuts_sheet,config_problems_panel}.dart`.
- Modify `ui/onboarding/{tour_overlay,whats_new_card}.dart`.
- Modify `ui/settings/settings_overlay.dart` (`_NavItem`), `ui/settings/settings_row.dart` and `ui/settings/pages/*`.
- Modify `ui/pages/{login_page,onboarding_page,pairing_page,change_password_page,confirm_page}.dart`.
- Modify `ui/ssh/ssh_connect_dialog.dart` and `ui/tools/tool_dialogs.dart`.
- Modify `ui/ai/*`: tokens, components, fonts and icons only; the layout is V2-5b's (A49). Includes `ai_markdown.dart` and the 7 `AlertDialog(` users of R34:
  - `settings/pages/advanced_page.dart`
  - `tools/tool_dialogs.dart`
  - `ai/ai_log_dialog.dart`
  - `ai/ai_config_chips.dart`
  - `ai/ai_history.dart`
  - `ai/ai_agents_section.dart`
  - `ai/ai_changes_panel.dart`
- Modify `apps/desktop/test/design/raw_style_baseline.dart` (lower it).
- Create `apps/desktop/test/ui/design_budget_test.dart` (R33) and `apps/desktop/test/ui/ai/ai_markdown_style_test.dart`.
- Modify `test/ui/empty_states_test.dart`, `pages_test.dart`, `settings_overlay_test.dart`, `info_strip_test.dart`, `remote_strip_test.dart` and `app_dialogs_test.dart` (keep it green).

**Interfaces:**
- Consumes:
  - **Task 4:** `shellxWeight(TextStyle, FontWeight)`, `ShellxWedge({corner, widthFactor, heightFactor})`, `ShellxWedgeCorner.topRight`, `ShellxWedgePainter.points(Size)`.
  - **Task 5 tokens:** `ShellxDesktopColors.{accent, link, overlayHover, overlayPressed, pushed, rowSelected, textTitle, textPrimary, textSecondary, line, border}`, `ShellxShadows.{raised, inset, e1, e2}`, `ShellxRadius.{r4, r6, r8, r12, pill}`, `ShellxText.*` (getters, R3) and `ShellxMotion.{slide, slideCurve}`.
  - **Task 5 button styles:** `shellxPrimaryButtonStyle()`, `shellxSecondaryButtonStyle()`, `shellxTextButtonStyle()`, `destructiveButtonStyle()`.
  - **Task 8:** `ShellxIcons.*`.
  - **Task 9:** `ShellxChip`, `ShellxSegmented<T>`, `ShellxCard` (its `flat` variant, as Task 9 declares it), `ShellxBrandLine`, `DialogBody(brand: true)`.
- Produces:
  - `const Key('sidebar.selectedBar')`: the 3×18 cyan bar of the selected sidebar row.
  - `const Key('settings.nav.selectedBar')`: the same bar on the selected Settings nav item.
  - `EmptyTerminalState` becomes a `Stack` whose first child is `const Positioned.fill(child: ShellxWedge())`.

**Tests first** (red before the change, green after):
- `test/ui/design_budget_test.dart`:
  - **'sidebar, 30 tabs, one selected: at most 2 BoxShadow under the sidebar (§10.5)'.**
    - Pump through `sidebar_test_harness.dart`.
    - The helper `int boxShadowsUnder(WidgetTester, Finder)` adds up `boxShadow.length` of every `BoxDecoration` on a `DecoratedBox` or an `Ink` below the finder (`Container`/`AnimatedContainer` build a `DecoratedBox`).
    - Expect `<= 2`.
  - **'the selected row is a raised tile with a cyan bar 3×18; other rows have no shadow'.**
    - The selected row's decoration: `boxShadow == ShellxShadows.raised`, colour `ShellxDesktopColors.rowSelected`, radius `ShellxRadius.r6` (10).
    - `tester.getSize(find.byKey(const Key('sidebar.selectedBar')))` is `Size(3, 18)`, and its colour is `ShellxDesktopColors.accent`.
    - Any unselected row: `boxShadowsUnder == 0`.
    - The sidebar width stays 220. Row heights stay 30/46/62/78 (A34).
  - **'no BackdropFilter in the workspace window (A44: no glass on the desktop in A)'.** Pump the workspace page with 2 tabs and expect `find.byType(BackdropFilter)` to find nothing.
- `test/ui/empty_states_test.dart`, in its existing groups:
  - **'empty pane: a ShellxWedge at the top right, and a gradient primary button (§8.1)'.**
    - With no tab, `find.byType(ShellxWedge)` finds one widget, and its `corner == ShellxWedgeCorner.topRight`. With a tab it finds nothing.
    - `pane.empty.open` is a `FilledButton` whose `style.backgroundBuilder` is not null.
  - **'no text or control of the empty state lies on the wedge (A30)'.**
    - At pane sizes 800×600 and 520×400, take the global rect of every `Text` and every `ButtonStyleButton` under `pane.empty`.
    - None of the 4 corners of any rect may lie inside the polygon `ShellxWedgePainter.points(paneSize)`. Use a point-in-polygon helper written in the test.
- `test/ui/ai/ai_markdown_style_test.dart`:
  - **'markdown strong and headings carry wght (R5)'.** Render `**b**` and `# h`. The span's `fontVariations` contains `FontVariation('wght', 700)` and its `fontWeight` is `w700`. Body text uses `ShellxText.dialogBody`'s size.
  - **'markdown links use link (A21)'.** The link span's colour is `ShellxDesktopColors.link`.
- `test/ui/pages_test.dart`:
  - **'login (sign-in and register) and onboarding show ShellxBrandLine above the title (A12)'.** `find.byType(ShellxBrandLine)` finds one widget in each mode, and `tester.getRect(brandLine).bottom + 8 == tester.getRect(title).top` (§7.1: 8 px above the title).
  - `app_dialogs_test.dart`'s "under 520 high" test stays green, unchanged.
- `test/ui/settings_overlay_test.dart`:
  - **'the selected nav item is a raised tile with the cyan bar'.** `boxShadow == ShellxShadows.raised`; `Key('settings.nav.selectedBar')` is 3×18 `accent`. Unselected items have no shadow.
- `test/ui/info_strip_test.dart` and `remote_strip_test.dart`:
  - **'strip buttons use link (A21)'.** `TextButton.style!.foregroundColor!.resolve({})` equals `ShellxDesktopColors.link`, or the style comes from the theme's `textButtonTheme`. Assert the effective colour of the label `Text` via `DefaultTextStyle`/`RichText` colour.
- Guard (Task 7): the baseline's `fontWeight:` counts go to 0 in every file except `lib/src/config/shellx_config.dart` (1, R13). The guard test must fail before the baseline is lowered, then pass.

**Implementation notes:**
- **Sidebar and tab rows (§8.1 row 1):**
  - Colours come from Task 5's map: sidebar `navy850`; hover `rowHover` < selected `rowSelected` (navy700) < pressed `rowPressed` (navy650).
  - The selected row is a tile: radius 10 (`ShellxRadius.r6`), `ShellxShadows.raised`, and a cyan bar 3×18 (`accent`) at the leading edge, vertically centred. Only the selected row has a shadow (A44).
  - Tags are pills (`ShellxRadius.pill`). Text is 12 (`ShellxText.body`/`small` per §6.5). Icons come from `ShellxIcons`.
  - Sizes stay: width 220, rows 30/46/62/78.
- **Panes (row 2):**
  - Pane background `bgTerminal` (navy900). Splits use `line` (hairline). The focus ring is `accent` (cyan).
  - The terminal palette and default font are already done (Task 5). Nothing here sets a font family.
- **Strips, pills, toast, empty state (row 3):**
  - `info_strip`, `remote_strip` and `resume_banner` use tokens. Their buttons use `shellxTextButtonStyle()` (link, A21).
  - `NoticeToast` is already radius 16 (Task 9).
  - `EmptyTerminalState`:
    - It becomes `Stack(children: [const Positioned.fill(child: ShellxWedge()), <the existing Center keyed pane.empty>])`. The wedge is drawn behind the content, top right, at 45 %/70 %.
    - The open button stays `ShellxPrimaryButton` (gradient `accentStrong`, Task 5).
    - The wedge carries no semantics and does not hit-test (Task 4).
- **Overlays (row 4):**
  - Applies to the command palette, search-all, the shortcuts sheet, the config problems panel, notifications, the tour, what's-new, the find bar and the key sequence.
  - Each is navy750, radius 16 (`r8`), border `hairlineStrong` (`border`), `ShellxShadows.e1` (float1).
  - Hovered rows are `overlayHover`, pressed rows `overlayPressed`. Inputs follow the theme (A43). Never give a row its own shadow.
- **Dialogs (row 6):**
  - Everything goes through `RouteDialogHost`/`dialogTheme` (Task 9): radius 28, navy750, float2.
  - `FilledButton` takes the theme's gradient. Secondary buttons take `OutlinedButton` (raised). Text buttons are `link`.
  - Login (both modes) and onboarding pass `DialogBody(brand: true)`.
  - The QR box keeps its white background (`pairing_page.dart`).
  - The 7 `AlertDialog(` users (R34) drop any own `shape:`/`backgroundColor:`.
  - Destructive confirmations keep `destructiveButtonStyle()`.
- **Settings (row 7):**
  - The frame is radius 28.
  - `_NavItem` when selected: a raised tile plus `Key('settings.nav.selectedBar')` 3×18 `accent`, the same build as the sidebar.
  - Switches, sliders and dropdowns follow the theme. Remove their per-widget colours.
  - The licence button is Task 14's.
- **AI pane (row 8; tokens and components only, A49):**
  - Config chips become `ShellxChip`. Cards become `ShellxCard` (flat). Buttons take the new styles.
  - The changes panel's `ShellxSegmented` is already Task 9's.
  - Markdown (`ai_markdown.dart`): the body is `ShellxText.dialogBody`; `a` is `link`; `strong` is `shellxWeight(base, FontWeight.w700)`; `h1`–`h3` go through `shellxWeight(…, FontWeight.w600)` (R5); code is `kAiMono` (Task 5).
- **Every `fontWeight:` left outside `ui/theme/**`** becomes `shellxWeight(style, w)` (A35). R13 keeps `shellx_config.dart`. Lower the baseline in the same commit.
- **No new `BoxShadow(`, `BackdropFilter(` or raw colour.** Values come from `ShellxDesktopColors`/`ShellxShadows`.

**Commands** (from `apps/desktop`):
```bash
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format <touched files>
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
```

**Commits** (one per area, each green):
- `feat(v2-design): desktop sidebar, panes and empty state on the new tokens — raised selected row, wedge (§8.1)`
- `feat(v2-design): desktop overlays, dialogs and Settings on the new components (§8.1)`
- `feat(v2-design): desktop AI pane tokens and components, weighted markdown (§8.1, R5)`
- `test(v2-design): desktop design budget — shadows and blur (§10.5)`

Each ends with the model's own trailer.

---

### Task 12: Phone screens (§8.2)

**Files:**
- Modify `apps/mobile/lib/`:
  - **App and auth:**
    - `features/app/{splash_page,update_required_page,connection_banner}.dart`
    - `features/auth/presentation/pages/{login_page,register_page}.dart`
    - `features/lock/presentation/{lock_gate,biometric_method}.dart`
  - **Machines and pairing:**
    - `features/machines/presentation/pages/machine_list_page.dart` (`_EmptyState`, the machine card)
    - `features/pairing/presentation/pages/qr_scanner_page.dart`
  - **Terminal:**
    - `features/terminal/presentation/pages/terminal_page.dart`
    - `features/terminal/presentation/widgets/{session_picker,extra_keys_bar,arrow_pad,keyboard_cover,link_sheet,view_as_text_sheet,agent_reply_bar}.dart`
  - **AI, tools and Settings:**
    - `features/ai/presentation/**` (tokens and components only, A49; includes `widgets/ai_markdown.dart`, and `widgets/ai_changes_sheet.dart`'s `SegmentedButton<bool>` → `ShellxSegmented<bool>`, R18)
    - `features/tools/presentation/pages/tool_page.dart`
    - `features/settings/presentation/pages/{settings_page,delete_account_page}.dart`
  - **Voice:**
    - `features/voice/presentation/widgets/{voice_composer,mic_button}.dart`
  - **Shared:**
    - `shared/src/confirm_dialog.dart`
    - `core/router/app_transparent_route.dart`
- Modify the 9 `showModalBottomSheet` call sites (R34):
  - `terminal_page.dart` (`_showFontSize`)
  - `link_sheet.dart`, `session_picker.dart`, `view_as_text_sheet.dart`
  - `ai_changes_sheet.dart`, `ai_new_session_sheet.dart`, `ai_history_sheet.dart`, `ai_config_sheet.dart`, `ai_attach_sheet.dart`
- Modify `apps/mobile/test/design/raw_style_baseline.dart`.
- Create `apps/mobile/test/design/design_budget_test.dart`, `apps/mobile/test/features/auth/register_page_test.dart` and `apps/mobile/test/features/ai/ai_markdown_style_test.dart`.
- Modify these tests:
  - `test/features/settings/settings_page_test.dart`
  - `test/features/terminal/terminal_page_test.dart`
  - `test/features/app/splash_page_test.dart`
  - `test/features/auth/login_page_test.dart`
  - `test/features/machines/machine_list_page_test.dart`
  - `test/features/ai/ai_changes_test.dart` (R18)

**Interfaces:**
- Consumes:
  - **Task 4:** `ShellxWedge`, `ShellxWedgeCorner`, `ShellxGlass({child, blur, borderRadius, padding})` and `shellxWeight`.
  - **Task 6:** the `AppColors` roles `raised`, `inset`, `onAccent`, `okSoft`, `gradientStrong`, `wedge` and `elevation`, plus `context.colors` and `context.typo`.
  - **Task 8:** `ShellxIcons.{faceId, fingerprint, lock, update, …}`.
  - **Task 10:**
    - `ShellxSegmented<T>`, `ShellxChip`, `ShellxCard` and `ShellxBrandHeader`, constructors as Task 10 defines them. The splash variant is logo 72 over `heading20` 700.
    - `AppButton` (gradient; its `backgroundColor` override gives a solid destructive fill) and the token toast.
- Produces: none new.

**Tests first:**
- `test/design/design_budget_test.dart`:
  - **'machine list with 8 machines: no BoxShadow inside any machine row (§10.5)'.** Use the same `boxShadowsUnder` helper as the desktop (`DecoratedBox` + `Ink` decorations). Each row gives 0.
  - **'AI session with 50 items: no BoxShadow inside the timeline'.** Use the `ai_session_page_test.dart` harness with 50 items. The timeline list's subtree gives 0.
  - **'terminal page and tool page: no ShellxGlass and no BackdropFilter (§10.5)'.** Both counts are 0.
  - **'BackdropFilter only under ShellxGlass'.**
    - On the first-run machine list: `find.byType(BackdropFilter)` finds exactly 1, and it is a descendant of `ShellxGlass`.
    - In the QR scanner's failure sheet: exactly 1, the kept σ 3 (A44).
  - **'every showModalBottomSheet call leaves backgroundColor and shape to the theme (A39, R34)'.**
    - Scan `lib/**/*.dart` (skipping generated files). For each `showModalBottomSheet` match, take the text up to its balanced closing parenthesis.
    - That text contains neither `backgroundColor:` nor `shape:`.
    - The scan finds at least 9 calls.
- `settings_page_test.dart`:
  - At the existing anchors (`find.byType(SegmentedButton<AdaptiveThemeMode>)`), replace the finder with `ShellxSegmented<AdaptiveThemeMode>`.
  - **'2× text on 320 pt: no label clipped'** stays and is green.
  - **New 'groups are flat ShellxCard (radius 16)'.**
  - **New 'delete account is destructive'**, on the button of `delete_account_page.dart`. Its fill is `colors.error` and its label is `onError` (dark) or white (light). It has no `Ink` gradient.
- `terminal_page_test.dart`, anchor `find.byType(SegmentedButton<VoiceLocale>)`: replace with `ShellxSegmented<VoiceLocale>` (A40).
- `ai_changes_test.dart`, new **'the changes sheet picks the scope with ShellxSegmented<bool>, not a Material SegmentedButton (R18)'**:
  - Open the sheet the way 'the menu opens the whole session; "Lượt này" is the last turn' does.
  - Under `find.byKey(const Key('ai.changes.sheet'))`, `find.byType(ShellxSegmented<bool>)` finds one widget and `find.byType(SegmentedButton<bool>)` finds nothing.
  - Tapping `ai.changes.turn` and then `ai.changes.session` switches the listed scope, as the existing tests expect.
  - With no turn, the "Lượt này" segment is disabled: a tap changes nothing.
  - The existing tests that tap `ai.changes.turn`/`ai.changes.session` stay green unchanged.
- `splash_page_test.dart`:
  - **'loading splash: ShellxBrandHeader centred and ShellxWedge at the top right (A12, §8.2)'.** Both find one widget, and the wedge's `corner == ShellxWedgeCorner.topRight`.
  - The failed state shows the error view without a wedge.
- `login_page_test.dart` and new `register_page_test.dart`, which reuses login's harness:
  - **'the brand header replaces the plain logo; wedge at the top right'.**
  - `find.byType(ShellxBrandHeader)` finds one widget. `find.byType(ShellxWedge)` finds one widget.
  - The `ShellxLogo` only appears inside the header.
- `machine_list_page_test.dart`:
  - **'first run: brand header, wedge, steps card in ShellxGlass with blur'.** `ShellxGlass.blur == true`, and the three steps are under it.
  - **'machine card: flat, radius 16, hairline border; online dot ok'.** The dot's colour is `colors.ok`.
- `ai_markdown_style_test.dart`: **'strong and headings carry wght (R5); links use link'.**
- Guard: lower the baseline.
  - `fontWeight:` 0 everywhere.
  - `popup_handler.dart` absent (Task 10 already).
  - `BoxShadow(` lowered where the screens drop their own.
  - `BackdropFilter(`/`ImageFilter.blur(` = 1 each, in `qr_scanner_page.dart` only (`ShellxGlass` lives in the package, which is not scanned).

**Implementation notes (§8.2):**
- **Splash:**
  - Page background `colors.background`.
  - `Stack(children: [const Positioned.fill(child: ShellxWedge()), Center(child: <ShellxBrandHeader, splash variant>)])` while loading.
  - `onGenerateTitle` is Task 13's.
- **Login and register:**
  - `ShellxBrandHeader` replaces the `Align(… ShellxLogo())` row.
  - `ShellxWedge` top right, behind the header. No field or plain text lies on it (A30); keep the form below the wedge's 70 % height or out of the triangle.
  - Inputs are Task 10's lowered fields (radius 16). `AppButton` is a gradient with `cta`.
- **Lock and update:**
  - Use tokens and `AppButton`.
  - Icons: `ShellxIcons.faceId`/`fingerprint`/`lock` and `update` (Task 8 already maps them; check nothing is hard-coded).
- **Machine list:**
  - The card is `ShellxCard` (flat): `surface`, radius 16, a `divider`/hairline border, no shadow (A44). The online dot is `ok`.
  - `_EmptyState` (first run):
    - `ShellxBrandHeader` on top, and `ShellxWedge` top right of the empty area.
    - The three steps go in `ShellxGlass(blur: true)` (σ 16, the only blur on the screen). Text on the glass is `primaryText` only (A29), never `secondaryText`.
    - The step number circle keeps `primarySoft`/`link`.
  - The error state and the buttons use the gradient `AppButton`.
- **QR scanner:**
  - The camera overlay stays (functional black and white).
  - The failure sheet and the success screen use tokens and `AppButton`.
  - Its `BackdropFilter` σ 3 stays (A44, guard baseline).
- **Terminal:**
  - Chrome comes from the new `TerminalColors`.
  - Sheets follow the theme (top radius 28, handle).
  - The extra-keys bar keeps the system keyboard look. Only the accent changes (`keyAccent`, `keyboardLink`, `keyboardError`).
  - `session_picker.dart`'s sheet loses `backgroundColor`/`shape`. In the "Phiên mới" `AppButton` prefix the icon is no longer self-coloured (A22, done in Task 10; check it).
- **AI (A49):** chips are `ShellxChip`, cards are `ShellxCard`, buttons are `AppButton`, sheets follow the theme. In `ai_changes_sheet.dart`, `SegmentedButton<bool>` becomes `ShellxSegmented<bool>` (R18) with the same two values, labels and keys, and the per-segment `enabled: _turn != null`. If Task 10's API has no per-segment disable, stop and report it rather than dropping the rule. In `ai_markdown.dart`, `strong` and headings go through `shellxWeight` and `a` uses `colors.link`. The layout is untouched.
- **Tool page:** the top bar uses tokens and the icons come from `ShellxIcons`. No glass.
- **Settings:**
  - Each group is a `ShellxCard` (flat, radius 16).
  - Switches and sliders follow the theme (remove per-widget colours).
  - The theme picker is `ShellxSegmented<AdaptiveThemeMode>`, with the same three labels and values as before.
  - The version line is Task 13's; the licence page's legalese is Task 14's.
  - `delete_account_page.dart`'s confirm button is destructive: `AppButton(backgroundColor: colors.error, …)` with a solid fill and the label `onError` (dark) or white (light).
- **Voice:**
  - In `voice_composer.dart`, `SegmentedButton<VoiceLocale>` becomes `ShellxSegmented<VoiceLocale>` with the same values and labels (A40).
  - Raleway was already removed (Task 6).
  - `mic_button.dart` gets token colours only. The new voice UI is C's.
- **Dialogs and routes:** `confirm_dialog.dart` follows `dialogTheme` (drop any own shape or colour). `app_transparent_route.dart`'s barrier is `colors.scrim`.
- **Everywhere:**
  - Every `fontWeight:` becomes `shellxWeight` (A35).
  - Remaining `Colors.`/`Color(0x` become `AppColors` roles, except the camera overlay, which keeps whatever the baseline already lists.
  - Lower the baseline in the same commit.

**Commands** (from `apps/mobile`):
```bash
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format <touched files>
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
```
The mobile analyze may show only the pre-existing info.

**Commits:**
- `feat(v2-design): phone splash, sign-in and first run — brand header, wedge, glass steps (§8.2, A12)`
- `feat(v2-design): phone terminal, AI, tools, Settings and voice on the new components; sheets follow the theme (§8.2, A39, A40)`
- `test(v2-design): phone design budget — shadows, blur, sheets (§10.5)`

---


### Task 13: ⚠ The full name and the identity pins

Only display keys change, and every identity stays "ShellX" (A1, A2, §4.2). Done with opus.

**Every display key** (file, key, new value). `L` = `ShellX: Remote AI agents`.

| # | File | Key / site | New value |
|---|---|---|---|
| 1 | `apps/mobile/ios/Runner/Info.plist` | `CFBundleDisplayName` | `L` (`CFBundleName` stays `shellx_mobile`; nothing is added to `en.lproj`/`vi.lproj/InfoPlist.strings`, A3) |
| 2 | `apps/mobile/android/app/src/main/AndroidManifest.xml` | `<application android:label>` | `L` (written inline, A4) |
| 3 | `apps/mobile/lib/l10n/intl_en.arb`, `intl_vi.arb` | `appTitle` | `L` (both languages) |
| 4 | same | `settingsVersion` | `ShellX: Remote AI agents {version} ({build})` (both) |
| 5 | `apps/mobile/lib/features/app/splash_page.dart` (`build`, the splash `MaterialApp`) | `onGenerateTitle` | `(context) => S.of(context).appTitle` (A13) |
| 6 | `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` | `appTitle` | `L` |
| 7 | same | `trayTooltip` | `L` (A7); `windowTitle` stays `{title} — ShellX` |
| 8 | `apps/desktop/lib/src/ui/window_host.dart` `windowTitleFor` | the no-tab branch | `l10n.appTitle` |
| 9 | `window_host.dart` `WindowManagerHost.init` | `setTitle('ShellX')` | `init({required String title})` → `setTitle(title)`; `lib/main.dart` calls `windowHost.init(title: l10n.appTitle)` |
| 10 | `apps/desktop/lib/src/ui/terminal/terminal_pane.dart` (`build`, the macOS pane header `selected?.label ?? 'ShellX'`) | the no-tab text | `selected?.label ?? l10n.appTitle` (add `final l10n = AppLocalizations.of(context);` in that `build`) |
| 11 | `apps/desktop/windows/runner/main.cpp` | `window.Create(L"ShellX", …)` | `L"ShellX: Remote AI agents"` |
| 12 | `apps/desktop/windows/runner/Runner.rc` | `VALUE "FileDescription"` only | `L` (A8) |
| 13 | `apps/desktop/lib/main.dart` `_windowsErrorBox` | the `MessageBox` title | `_windowsErrorBox(String title, String message)`; both callers (the version check and `_showStartupError`) pass `l10n.appTitle` (A9) |
| 14 | `apps/desktop/macos/Runner/Info.plist` | add `CFBundleDisplayName` = `ShellX` and `LSHasLocalizedDisplayName` = `true` | A5 |
| 15 | new `apps/desktop/macos/Runner/en.lproj/InfoPlist.strings` | `"CFBundleDisplayName"` | `L`, a Runner resource |

Rows 16–18 are Task 15.

**Kept (must not change):**
- **Windows:** `ProductName "ShellX"`, `CompanyName "pro.shellx"`, `InternalName "ShellX"`, `OriginalFilename "ShellX.exe"`, `BINARY_NAME "ShellX"`.
- **macOS:** `PRODUCT_NAME = ShellX`, the bundle ids `pro.shellx.desktop`/`com.shellx.prod`, `CFBundleName` (macOS `$(PRODUCT_NAME)`, iOS `shellx_mobile`).
- **Platform `appName` values:** `appName: 'ShellX'` in `lib/src/platform/notifier.dart` and `lib/src/platform/launch_at_login.dart`.
- **Notification titles** `'ShellX'`: `main.dart` `_showStartupError`, `tray_actions.dart` (A9).
- **Other identities:** the data folders and the terminal theme "ShellX".
- **Every sentence that contains "ShellX"** (ARB and `NS*UsageDescription`).
- **Test fakes:** `PackageInfo(appName: 'ShellX')` values in tests.

**Files:**
- Modify every file in rows 1–15.
- Modify `apps/desktop/macos/Runner.xcodeproj/project.pbxproj`.
- Regenerate the strings:
  - Desktop: `apps/desktop/lib/l10n/app_localizations*.dart`.
  - Mobile: `apps/mobile/lib/shared/src/{l10n,intl/messages_en,intl/messages_vi}.dart`.
- Tests:
  - Create `apps/desktop/test/platform/identity_pins_test.dart`.
  - Modify `apps/desktop/test/ui/window_flow_test.dart` and `apps/desktop/test/l10n/l10n_test.dart`.
  - Modify `apps/mobile/test/platform_config_test.dart`, `test/l10n_test.dart`, `test/features/settings/settings_page_test.dart`, `test/shared/shellx_logo_test.dart` and `test/features/app/splash_page_test.dart`.

**Interfaces:**
- Consumes: none from Tasks 5–12. This task is independent of the design work and can run any time after Task 2.
- Produces:
  - `WindowManagerHost.init({required String title})`
  - `void _windowsErrorBox(String title, String message)` (private)

**Tests first:**

`apps/desktop/test/platform/identity_pins_test.dart` (whole file; run from `apps/desktop`):
```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// V2-5a §4.2, §4.3, Review Focus 1: the long name is display only. Each
/// identity below stays "ShellX": changing one moves the user's data
/// folder, loses the sign-in, or makes a second shortcut / AUMID.
void main() {
  String read(String path) => File(path).readAsStringSync();

  group('Windows', () {
    test('Runner.rc: FileDescription is the long name; the identities stay',
        () {
      final rc = read('windows/runner/Runner.rc');
      expect(rc,
          contains(r'VALUE "FileDescription", "ShellX: Remote AI agents" "\0"'));
      expect(rc, contains(r'VALUE "ProductName", "ShellX" "\0"'));
      expect(rc, contains(r'VALUE "CompanyName", "pro.shellx" "\0"'));
      expect(rc, contains(r'VALUE "InternalName", "ShellX" "\0"'));
      expect(rc, contains(r'VALUE "OriginalFilename", "ShellX.exe" "\0"'));
    });

    test('CMakeLists.txt: BINARY_NAME stays ShellX (ShellX.exe)', () {
      expect(read('windows/CMakeLists.txt'),
          contains('set(BINARY_NAME "ShellX")'));
    });

    test('main.cpp: the first native title is the long name', () {
      expect(read('windows/runner/main.cpp'),
          contains('window.Create(L"ShellX: Remote AI agents", origin, size)'));
    });
  });

  group('macOS', () {
    test('AppInfo.xcconfig: PRODUCT_NAME and the bundle id stay', () {
      final x = read('macos/Runner/Configs/AppInfo.xcconfig');
      expect(x, matches(RegExp(r'^PRODUCT_NAME = ShellX$', multiLine: true)));
      expect(
          x,
          matches(RegExp(r'^PRODUCT_BUNDLE_IDENTIFIER = pro\.shellx\.desktop$',
              multiLine: true)));
    });

    test('Info.plist: CFBundleDisplayName = ShellX (the file name), '
        'LSHasLocalizedDisplayName, CFBundleName from PRODUCT_NAME', () {
      final plist = read('macos/Runner/Info.plist');
      expect(plist,
          contains('<key>CFBundleDisplayName</key>\n\t<string>ShellX</string>'));
      expect(plist,
          contains('<key>LSHasLocalizedDisplayName</key>\n\t<true/>'));
      expect(plist,
          contains(r'<key>CFBundleName</key>' '\n\t' r'<string>$(PRODUCT_NAME)</string>'));
    });

    test('en.lproj/InfoPlist.strings has the long name; en is the only '
        'localization (AppKit menus stay)', () {
      expect(read('macos/Runner/en.lproj/InfoPlist.strings'),
          contains('"CFBundleDisplayName" = "ShellX: Remote AI agents";'));
      final lproj = Directory('macos/Runner')
          .listSync()
          .whereType<Directory>()
          .map((d) => d.uri.pathSegments[d.uri.pathSegments.length - 2])
          .where((n) => n.endsWith('.lproj'))
          .toSet();
      expect(lproj, {'Base.lproj', 'en.lproj'});
    });

    test('the strings file is a Resources member of the Runner target', () {
      final pbx = read('macos/Runner.xcodeproj/project.pbxproj');
      expect(pbx, contains('/* InfoPlist.strings in Resources */ = {isa = PBXBuildFile;'));
      expect(pbx, contains('path = en.lproj/InfoPlist.strings;'));
      expect(pbx, contains('name = InfoPlist.strings;'));
    });
  });

  test("notifications and launch at login keep appName 'ShellX' "
      '(AUMID, ShellX.lnk, the HKCU Run value)', () {
    expect(read('lib/src/platform/notifier.dart'),
        contains("appName: 'ShellX',"));
    expect(read('lib/src/platform/launch_at_login.dart'),
        contains("appName: 'ShellX',"));
  });
}
```

**Changes to existing tests:**
- **Desktop `test/ui/window_flow_test.dart`:**
  - At `expect(windowTitleFor(null, l10n), 'ShellX')`, the value becomes `'ShellX: Remote AI agents'`.
  - `expect(windowTitleFor(tab, l10n), '${tab.label} — ShellX')` stays.
  - Rename the test: `'window title: "<tab> — ShellX", or the long name without tabs'`.
- **Desktop `test/l10n/l10n_test.dart`:** add **'V2-5a names: appTitle and trayTooltip long, windowTitle short (§9.1)'**. For both `lookupAppLocalizations(const Locale('en'))` and `(const Locale('vi'))`:
  - `appTitle == 'ShellX: Remote AI agents'`
  - `trayTooltip == 'ShellX: Remote AI agents'`
  - `windowTitle('a') == 'a — ShellX'`
- **Mobile `test/platform_config_test.dart`:**
  - Its `CFBundleDisplayName` assertion becomes `'<key>CFBundleDisplayName</key>\n\t<string>ShellX: Remote AI agents</string>'`, and the test name says "long display name".
  - Its `android:label` assertion becomes `'android:label="ShellX: Remote AI agents"'`.
  - **New 'iOS: CFBundleName stays shellx_mobile; neither InfoPlist.strings sets CFBundleDisplayName (A3)'**: `'<key>CFBundleName</key>\n\t<string>shellx_mobile</string>'`, and `en.lproj`/`vi.lproj/InfoPlist.strings` do not contain `CFBundleDisplayName`.
  - The bundle-id test is kept as it is.
- **Mobile `test/l10n_test.dart`:** add **'V2-5a names: appTitle and settingsVersion (§9.1)'**. In EN and VI, obtained the file's existing way:
  - `appTitle == 'ShellX: Remote AI agents'`
  - `settingsVersion('1.0.0', '1') == 'ShellX: Remote AI agents 1.0.0 (1)'`
- **Mobile `settings_page_test.dart`:** the three `find.text('ShellX 1.0.0 (1)')` sites become `'ShellX: Remote AI agents 1.0.0 (1)'`. One of them checks `.style!.color == colors.secondaryText`; keep that check.
- **Mobile `shared/shellx_logo_test.dart`:** `find.bySemanticsLabel('ShellX: Remote AI agents')`, and the test name says "the long name".
- **Mobile `features/app/splash_page_test.dart`:** add **'the splash MaterialApp titles the app with the long name (A13)'**. While loading, `tester.widget<Title>(find.byType(Title).first).title == 'ShellX: Remote AI agents'`.
- **Kept as is** (§4.3 "Giữ"):
  - `lock_gate_test.dart`, `app_lock_controller_test.dart`, `login_page_test.dart`
  - the sentences in both `l10n_test.dart` files
  - `tray_menu_test.dart`, `agent_controller_test.dart`, `theme_listing_test.dart`, `end_to_end_macos_test.dart`, `mux_paths_test.dart`
  - `release/tests/*`, `term/tests/*`

**Implementation:**

ARB:
- Desktop `app_en.arb`/`app_vi.arb`:
  - `"appTitle": "ShellX: Remote AI agents"`
  - `"trayTooltip": "ShellX: Remote AI agents"`
- Mobile `intl_en.arb`/`intl_vi.arb`:
  - `"appTitle": "ShellX: Remote AI agents"`
  - `"settingsVersion": "ShellX: Remote AI agents {version} ({build})"`, keeping the existing placeholders metadata.
- Anchor on the key names. V2-2b/V2-4 added keys at the end; leave them.

Dart (desktop):
```dart
// window_host.dart
String windowTitleFor(TerminalTab? selected, AppLocalizations l10n) =>
    selected == null ? l10n.appTitle : l10n.windowTitle(selected.label);
// update its doc comment: '"{tab} — ShellX", or the app title with no tabs.'

  Future<void> init({required String title}) async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await windowManager.setTitle(title);
    // …rest unchanged

// main.dart
  await windowHost.init(title: l10n.appTitle);
  …
    _windowsErrorBox(l10n.appTitle, l10n.windowsVersionUnsupported);
  …
    _windowsErrorBox(l10n.appTitle, l10n.startupFailed);
  …
void _windowsErrorBox(String title, String message) {
  final text = message.toNativeUtf16();
  final caption = title.toNativeUtf16();
  win32.MessageBox(0, text, caption, win32.MB_OK | win32.MB_ICONERROR);
  malloc.free(text);
  malloc.free(caption);
}
```
`notifier.show(title: 'ShellX', …)` stays (A9).

Dart (mobile): in `splash_page.dart`'s `MaterialApp(`, add `onGenerateTitle: (context) => S.of(context).appTitle,`.

Native, complete:
- `apps/desktop/windows/runner/main.cpp`: `if (!window.Create(L"ShellX: Remote AI agents", origin, size)) {`
- `apps/desktop/windows/runner/Runner.rc`: `            VALUE "FileDescription", "ShellX: Remote AI agents" "\0"`. Only this line changes. The file stays ASCII, as the name is ASCII.
- `apps/mobile/ios/Runner/Info.plist`: `<key>CFBundleDisplayName</key>\n\t<string>ShellX: Remote AI agents</string>`
- `apps/mobile/android/app/src/main/AndroidManifest.xml`: `android:label="ShellX: Remote AI agents"`
- `apps/desktop/macos/Runner/Info.plist`: insert after the `CFBundleDevelopmentRegion` pair:
  ```xml
  	<key>CFBundleDisplayName</key>
  	<string>ShellX</string>
  ```
  and after the `LSMinimumSystemVersion` pair:
  ```xml
  	<key>LSHasLocalizedDisplayName</key>
  	<true/>
  ```
- New `apps/desktop/macos/Runner/en.lproj/InfoPlist.strings` (UTF-8):
  ```
  /* Finder, Launchpad, Spotlight, Dock, ⌘-Tab and Login Items show this name; the menu bar and About keep CFBundleName (ShellX). V2-5a A5. */
  "CFBundleDisplayName" = "ShellX: Remote AI agents";
  ```
- `project.pbxproj`: four inserts, modelled on `MainMenu.xib`'s variant group.
  - PBXBuildFile section, after the `MainMenu.xib in Resources` line:
    ```
    		5A5F0001000000000000A002 /* InfoPlist.strings in Resources */ = {isa = PBXBuildFile; fileRef = 5A5F0002000000000000A002 /* InfoPlist.strings */; };
    ```
  - PBXFileReference section, after the `33CC10F52044A3C60003C045 /* Base */` line:
    ```
    		5A5F0003000000000000A002 /* en */ = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = en; path = en.lproj/InfoPlist.strings; sourceTree = "<group>"; };
    ```
  - Group `33CC11242044D66E0003C045 /* Resources */` children, after `MainMenu.xib`: `				5A5F0002000000000000A002 /* InfoPlist.strings */,`
  - Resources build phase `33CC10EB2044A3C60003C045` files, after `MainMenu.xib in Resources`: `				5A5F0001000000000000A002 /* InfoPlist.strings in Resources */,`
  - PBXVariantGroup section, after the `MainMenu.xib` group:
    ```
    		5A5F0002000000000000A002 /* InfoPlist.strings */ = {
    			isa = PBXVariantGroup;
    			children = (
    				5A5F0003000000000000A002 /* en */,
    			);
    			name = InfoPlist.strings;
    			path = Runner;
    			sourceTree = "<group>";
    		};
    ```
  - `knownRegions` already has `en` and `Base`; leave it.
  - Check that the ids are unused: `grep -c 5A5F000.000000000000A002 project.pbxproj` must give 0 before the edit (Task 1 used `…A001`).

**Commands:**
```bash
# desktop strings and checks (apps/desktop)
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
# mobile strings and checks (apps/mobile)
PATH=~/fvm/versions/3.41.4/bin:$PATH dart run intl_utils:generate
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/shared/src/l10n.dart lib/shared/src/intl/messages_en.dart lib/shared/src/intl/messages_vi.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
# no leak into identities: every hit must be a display key above
git grep -n 'Remote AI agents' -- apps ':!**/test/**'
```

Build check without launching, in a throw-away worktree of `HEAD`, after committing:
```bash
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/shellx-name.XXXXXX")
git worktree add --detach "$SCRATCH/wt" HEAD
(cd "$SCRATCH/wt" && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get >/dev/null \
  && cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug \
  && APP=build/macos/Build/Products/Debug/ShellX.app/Contents \
  && plutil -p "$APP/Resources/en.lproj/InfoPlist.strings" \
  && plutil -p "$APP/Info.plist" | grep -E 'CFBundleDisplayName|LSHasLocalizedDisplayName|CFBundleName|CFBundleIdentifier')
git worktree remove --force "$SCRATCH/wt" && rm -rf "$SCRATCH"
```

Expected output:
- `"CFBundleDisplayName" => "ShellX: Remote AI agents"` from the strings file.
- `"CFBundleDisplayName" => "ShellX"`, `"LSHasLocalizedDisplayName" => 1` (or `true`), `"CFBundleName" => "ShellX"` and `"CFBundleIdentifier" => "pro.shellx.desktop"` from the Info.plist.
- Never open the built app.

**Commits:**
- `feat(v2-name): the full display name "ShellX: Remote AI agents" on every OS surface; identities stay ShellX (§4.1, A1–A13)`
- `test(v2-name): pin the identities and the display names (§4.3, Review Focus 1)`

The tests may go in the same commit when they are written first. Use the Opus trailer.

---

### Task 14: ⚠ Native launch screens and the licence page

**Files:**
- **iOS launch screen:** Modify `apps/mobile/ios/Runner/Base.lproj/LaunchScreen.storyboard`: the view's `backgroundColor` only; the `LaunchImage` stays.
- **Android launch screen:**
  - Modify `apps/mobile/android/app/src/main/res/drawable/launch_background.xml` and `drawable-v21/launch_background.xml`.
  - Modify `values/styles.xml` and `values-night/styles.xml` (`NormalTheme`).
  - Modify `values/colors.xml` (add `shellx_page`).
  - Create `values-v31/styles.xml` and `values-night-v31/styles.xml` (R30).
- **The package's licence entry:**
  - Create `packages/shellx_design/lib/src/licenses.dart` and `packages/shellx_design/test/licenses_test.dart`.
  - Modify `packages/shellx_design/lib/shellx_design.dart` (export).
- **The calls:** Modify `apps/desktop/lib/main.dart` (next to `registerFontLicenses()`, before `runApp`) and `apps/mobile/lib/main.dart` (after `registerFontLicenses()`).
- **Strings:** Modify the ARBs:
  - `apps/desktop/lib/l10n/app_{en,vi}.arb` get `settingsLicenses` and `licensesLegalese`.
  - `apps/mobile/lib/l10n/intl_{en,vi}.arb` get `licensesLegalese`; mobile `settingsLicenses` keeps its text.
  - Regenerate both apps' strings.
- **The pages:** Modify `apps/desktop/lib/src/ui/settings/pages/general_page.dart` (button, R31) and `apps/mobile/lib/features/settings/presentation/pages/settings_page.dart` (`_showLicenses`).
- **Tests:**
  - Modify `apps/mobile/test/platform_config_test.dart`, `apps/mobile/test/app_test.dart`, `apps/mobile/test/features/settings/settings_page_test.dart`, `apps/desktop/test/l10n/l10n_test.dart`.
  - Create `apps/desktop/test/ui/settings_licenses_test.dart`.

**Interfaces:**
- Consumes: Task 13's long `appTitle` (the `applicationName`).
- Produces:
  - `void registerShellxDesignLicenses()`
  - `const String shellxDesignReferencePackage = 'Online Bike Shopping App (design reference)'`
  - `const String shellxDesignReferenceText` (the §9.3 text)
  - ARB `licensesLegalese` (both apps) and `settingsLicenses` (desktop)
  - `Key('settings.licenses')`

**Tests first:**
- **`packages/shellx_design/test/licenses_test.dart`.** Use `tearDown(LicenseRegistry.reset)`.
  - **'registers one CC BY 4.0 entry under the design reference name (§9.3)'.** After `registerShellxDesignLicenses()`, `await LicenseRegistry.licenses.toList()` has exactly one entry whose `packages` is `['Online Bike Shopping App (design reference)']`. Its paragraphs joined with `\n` equal `shellxDesignReferenceText`, which equals the §9.3 text verbatim (below).
  - **'no SF Mono entry (A32, A47)'.** No entry's packages or text match `RegExp(r'SF ?Mono', caseSensitive: false)`.
- **Mobile `test/app_test.dart`:**
  - Extend the font licences test, which Task 6 makes JetBrains Mono only: after `registerFontLicenses(); registerShellxDesignLicenses();`, the packages are `{'JetBrains Mono', 'Online Bike Shopping App (design reference)'}`, with no `SF Mono` and no `Raleway`.
  - Add a source check: `lib/main.dart` contains `registerShellxDesignLicenses();` exactly once.
- **Desktop `test/ui/settings_licenses_test.dart`:**
  - **'General: "Licenses and credits…" under the version opens the licence page with the legalese (A47, R31)'.**
    - Pump `GeneralPage` the way `settings_general_a12_test.dart` does.
    - `find.byKey(const Key('settings.licenses'))` shows the text `Licenses and credits…`.
    - Tap, then `pumpAndSettle`: `find.byType(LicensePage)` finds one widget, and `find.text(l10n.licensesLegalese)` finds one widget.
  - **'main.dart registers the design licence once, daemon_main.dart never'.** A source check.
- **Desktop `test/l10n/l10n_test.dart`:** add EN/VI checks:
  - `settingsLicenses`: `Licenses and credits…` / `Giấy phép và ghi công…`
  - `licensesLegalese`: the two §9.1 strings verbatim (below)
- **Mobile `settings_page_test.dart`:** extend the existing licences test. After opening, `find.text(<VI legalese>)` finds one widget. The harness locale is VI; use EN if the harness is EN.
- **Mobile `platform_config_test.dart`, new group 'V2-5a A48: native launch screens are navy #222834':**
  - **iOS:** `LaunchScreen.storyboard` contains `<color key="backgroundColor" red="0.13333333333333333" green="0.15686274509803921" blue="0.20392156862745098" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>` and still contains `image="LaunchImage"`.
  - **Android `values/colors.xml`:** contains `<color name="shellx_page">#222834</color>`; `notification_color` is unchanged.
  - **Android `drawable/` and `drawable-v21/launch_background.xml`:** both contain `<item android:drawable="@color/shellx_page" />`.
  - **Android `values/` and `values-night/styles.xml`:** both have `NormalTheme` with `<item name="android:windowBackground">@color/shellx_page</item>`.
  - **Android `values-v31/` and `values-night-v31/styles.xml`:** both contain `<item name="android:windowSplashScreenBackground">@color/shellx_page</item>` and keep the `Theme.AppCompat` parents.

**Implementation:**

`packages/shellx_design/lib/src/licenses.dart` (whole file):
```dart
import 'package:flutter/foundation.dart';

/// The design reference's CC BY 4.0 attribution (V2-5a §9.3, A47). English,
/// not translated. SF Mono is never bundled, so it has no entry (A32).
const String shellxDesignReferencePackage =
    'Online Bike Shopping App (design reference)';

const String shellxDesignReferenceText =
    "ShellX's visual style (colours, shapes and gradients) is adapted from "
    '"Online Bike Shopping App" by Sourasith '
    '(https://www.figma.com/@sourasithp), Figma Community file '
    'https://www.figma.com/community/file/1149336740234053658, licensed under '
    'CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Changes: '
    'colours re-tuned for contrast; components rebuilt for ShellX. No images '
    'or artwork from the file are used.';

/// Call once in each app's `main()`, before `runApp`.
void registerShellxDesignLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      [shellxDesignReferencePackage],
      shellxDesignReferenceText,
    );
  });
}
```
Export it from `lib/shellx_design.dart`. Call it right after `registerFontLicenses();` in both apps' `main.dart`, never in `daemon_main.dart`.

ARB values, verbatim from §9.1:
- `settingsLicenses` (desktop only):
  - EN: `Licenses and credits…`
  - VI: `Giấy phép và ghi công…`
- `licensesLegalese` (both apps):
  - EN: `Visual style adapted from “Online Bike Shopping App” by Sourasith (Figma Community, CC BY 4.0).`
  - VI: `Phong cách giao diện phỏng theo “Online Bike Shopping App” của Sourasith (Figma Community, CC BY 4.0).`
  - Curly quotes U+201C/U+201D, as written.

Desktop `GeneralPage` (R31), after the `if (version != null)` version `Padding`:
```dart
Align(
  alignment: Alignment.centerLeft,
  child: Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
    child: TextButton(
      key: const Key('settings.licenses'),
      onPressed: () => showLicensePage(
        context: context,
        applicationName: l10n.appTitle,
        applicationVersion: version,
        applicationLegalese: l10n.licensesLegalese,
      ),
      child: Text(l10n.settingsLicenses),
    ),
  ),
),
```
The page is a full-window Material route with a back button; Esc does not close it (A47's accepted cost).

Mobile `_showLicenses`: add `applicationLegalese: strings.licensesLegalese,`.

Native launch screens (A48), complete:
- **iOS `LaunchScreen.storyboard`:** replace the view's `<color key="backgroundColor" red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>` with `<color key="backgroundColor" red="0.13333333333333333" green="0.15686274509803921" blue="0.20392156862745098" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>`. That is #222834: 34/255, 40/255, 52/255.
- **`values/colors.xml`:** add `    <!-- The launch background (V2-5a A48): the page colour navy850. -->` and `    <color name="shellx_page">#222834</color>`.
- **`drawable/launch_background.xml`:** `@android:color/white` becomes `@color/shellx_page`.
- **`drawable-v21/launch_background.xml`:** `?android:colorBackground` becomes `@color/shellx_page`.
- **`values/styles.xml` and `values-night/styles.xml`:** in `NormalTheme`, `?android:colorBackground` becomes `@color/shellx_page`.
- **`values-v31/styles.xml`:**
  ```xml
  <?xml version="1.0" encoding="utf-8"?>
  <resources>
      <!-- Android 12+ draws its own splash first (V2-5a A48): navy, like the Flutter splash. -->
      <style name="LaunchTheme" parent="Theme.AppCompat.Light.NoActionBar">
          <item name="android:windowBackground">@drawable/launch_background</item>
          <item name="android:windowSplashScreenBackground">@color/shellx_page</item>
      </style>
      <style name="NormalTheme" parent="Theme.AppCompat.Light.NoActionBar">
          <item name="android:windowBackground">@color/shellx_page</item>
      </style>
  </resources>
  ```
- **`values-night-v31/styles.xml`:** the same, with `parent="Theme.AppCompat.NoActionBar"` in both styles (R30).

**Commands:**
```bash
# packages/shellx_design, then apps/desktop, then apps/mobile
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
# strings: desktop `flutter gen-l10n`; mobile `dart run intl_utils:generate` + `dart format` of the 3 generated files
```
The Android resources are compiled by Task 16's `flutter build apk --debug`; run it now as well if time allows, since it catches a resource typo.

**Commits:**
- `feat(v2-design): navy native launch screens on iOS and Android, Android 12+ splash included (A48, R30)`
- `feat(v2-design): design reference attribution on both licence pages; desktop Settings › General button (A47, §9.3)`

Use the Opus trailer.

---

### Task 15: ⚠ The Windows installer's three display lines

> **⚠ Flagged: `release/windows/shellx.iss` is a teammate's file on `main` (A10).** Tell the user before this commit is merged to `main`. The controller lists it in the hand-off; §13.2 "Gộp ba dòng Inno vào `main`" needs the user's approval. Nothing else in `release/**` may change.

**Files:** Modify `release/windows/shellx.iss`, these three lines only (anchor on the keys):
- `AppName=ShellX` becomes `AppName=ShellX: Remote AI agents`
- `AppVerName=ShellX {#AppVersion}` becomes `AppVerName=ShellX: Remote AI agents {#AppVersion}`
- `UninstallDisplayName=ShellX` becomes `UninstallDisplayName=ShellX: Remote AI agents`

**Kept, byte-equal (R32):**
- `AppId={{6A3A45BD-0A27-407A-A1FF-3C8D1BE226EE}`
- `DefaultDirName={autopf}\ShellX`
- `DefaultGroupName=ShellX`
- the `{autodesktop}\ShellX` and Start-menu `[Icons]` names
- `{cm:LaunchProgram,ShellX}`
- `AppPublisher=ShellX`
- `#define AppExeName "ShellX.exe"`
- `OutputBaseFilename=ShellX-Setup-{#AppVersion}`
- every `[UninstallDelete]`/`[Code]` path

**Interfaces:** none.

**Tests:** no new test (A10, R32). The existing `release/tests/inno.test.mjs` must still pass.

**Steps:**
1. Edit the three lines.
2. Check that the diff is exactly three lines:
   ```bash
   git diff --numstat -- release/windows/shellx.iss   # expect: 3	3	release/windows/shellx.iss
   git diff -U0 -- release/windows/shellx.iss | grep '^[-+][A-Za-z]' 
   # expect exactly:
   # -AppName=ShellX
   # +AppName=ShellX: Remote AI agents
   # -AppVerName=ShellX {#AppVersion}
   # +AppVerName=ShellX: Remote AI agents {#AppVersion}
   # -UninstallDisplayName=ShellX
   # +UninstallDisplayName=ShellX: Remote AI agents
   grep -c -E '^(AppId=\{\{6A3A45BD-0A27-407A-A1FF-3C8D1BE226EE\}|DefaultDirName=\{autopf\}\\ShellX|DefaultGroupName=ShellX|AppPublisher=ShellX)$' release/windows/shellx.iss   # expect 4
   grep -c 'LaunchProgram,ShellX}' release/windows/shellx.iss   # expect 1
   ```
3. Run the existing installer test (from the worktree root): `node --test release/tests/inno.test.mjs`. Every test passes, as before.
4. Commit alone, with nothing else in it:
   ```
   feat(v2-name): installer shows "ShellX: Remote AI agents" in Apps & features and the wizard (A10)

   Only AppName, AppVerName and UninstallDisplayName change; AppId, folders,
   group, shortcuts and the publisher stay ShellX. release/windows/shellx.iss
   is a teammate's file: needs the user's approval before main.

   Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
   ```

**Notes:** the wizard text becomes "Cài đặt ShellX: Remote AI agents…". That is A10's accepted cost. If the user wants it short, revert `AppName`/`AppVerName` and keep `UninstallDisplayName`. Inno's own `[name]` messages use `AppName`; nothing in the script builds a path from it (checked: every path is literal `ShellX`).

---

### Task 16: Final verification and the ledger

**Files:** Modify `docs/superpowers/ledgers/v2-5a.md`, which Task 1 created. No code changes. Any failure found here goes back to its task as a fix commit (`fix(v2-design): …`), and then this task runs again.

**Interfaces:** none.

**Steps:**

1. **All suites, from each directory.** Record the counts.
   ```bash
   # Flutter packages
   for d in packages/shellx_design apps/desktop apps/mobile; do
     (cd "$d" && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test) || echo "FAIL $d"
   done
   # Dart packages
   for d in packages/shellx_core packages/shellx_agent packages/shellx_client packages/shellx_e2e packages/shellx_acp packages/shellx_ai; do
     (cd "$d" && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test) || echo "FAIL $d"
   done
   node --test release/tests/inno.test.mjs
   ```
   - **Expected:** every package analyze-clean; mobile shows only the pre-existing `unnecessary_import` info.
   - **Desktop count:** ≥ the 3924 of Tasks 1–4, plus the new tests; 10 skipped.
   - **Mobile count:** ≥ 1614, plus the new tests.
   - **Package:** ≥ 62, plus Tasks 8 and 14.
   - **Timing:** if `terminal_links_test.dart` "path performance" fails, rerun it alone first (plan header).

2. **Guard end state (Task 7, §10.4).** Print the two baselines and check:
   - Desktop:
     - `Icons.` and `CupertinoIcons.` are absent.
     - `fontWeight:` appears only in `lib/src/config/shellx_config.dart` (1).
     - R13's other entries are `config/config_color.dart` `Color(0x`, `config/font_probe.dart` `TextStyle(` and the file viewer's `fontFamily:`.
   - Mobile:
     - `Icons.`, `CupertinoIcons.` and `fontWeight:` are absent.
     - `BackdropFilter(` and `ImageFilter.blur(` are 1 each, in `qr_scanner_page.dart` only.
     - `popup_handler.dart` is absent.
   - Adapters: `grep -c 'Color(0x' apps/desktop/lib/src/ui/theme/*.dart apps/mobile/lib/core/design/*.dart` gives 0 for each file.

3. **Builds, without launching, in a throw-away worktree of `HEAD`.** This leaves the worktree's `Podfile.lock` untouched.
   ```bash
   SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/shellx-final.XXXXXX")
   git worktree add --detach "$SCRATCH/wt" HEAD
   cd "$SCRATCH/wt" && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get >/dev/null
   (cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build apk --debug)
   (cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build ios --debug --no-codesign)
   (cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug)
   # no SF Mono file or declaration in any artifact (A32, §6.2)
   find apps/desktop/build/macos/Build/Products/Debug/ShellX.app apps/mobile/build/ios/iphoneos/Runner.app \
     \( -iname '*sf*mono*' -o -iname '*sfnsmono*' -o -iname '*sf-mono*' \) | wc -l          # expect 0
   unzip -l apps/mobile/build/app/outputs/flutter-apk/app-debug.apk | grep -ciE 'sf-?mono|sfnsmono'   # expect 0
   for m in $(find apps/desktop/build/macos/Build/Products/Debug/ShellX.app apps/mobile/build/ios/iphoneos/Runner.app -name FontManifest.json); do
     grep -c 'SF Mono' "$m"; done                                                              # expect 0 each
   unzip -p apps/mobile/build/app/outputs/flutter-apk/app-debug.apk assets/flutter_assets/FontManifest.json | grep -c 'SF Mono'   # expect 0
   # names in the built products (A3, A4, A5)
   plutil -p apps/mobile/build/ios/iphoneos/Runner.app/Info.plist | grep -E 'CFBundleDisplayName|CFBundleName'
   plutil -p apps/desktop/build/macos/Build/Products/Debug/ShellX.app/Contents/Resources/en.lproj/InfoPlist.strings
   ```
   **Expected:**
   - The three builds succeed.
   - Every count above is 0. FontManifest still lists `JetBrainsMono` and `CupertinoIcons`, with no `Raleway` in the mobile manifest.
   - iOS: `"CFBundleDisplayName" => "ShellX: Remote AI agents"` and `"CFBundleName" => "shellx_mobile"`.
   - macOS: the strings file shows the long name.
   - Keep the scratch worktree for step 4.

4. **The isolated smoke launch of the full desktop app.** This is allowed only because Task 2 is done (R1). It uses the same recipe as Task 1 Step 10, with these differences:
   - The bundle id is `pro.shellx.desktop.smoketest`.
   - It builds `main()`, not the spike.
   - It also calls the relay's public `GET /v1/version` (read-only).

   ```bash
   cd "$SCRATCH/wt"
   sed -i '' 's/^PRODUCT_BUNDLE_IDENTIFIER = .*/PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop.smoketest/' apps/desktop/macos/Runner/Configs/AppInfo.xcconfig
   grep -q '^PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop.smoketest$' apps/desktop/macos/Runner/Configs/AppInfo.xcconfig || { echo 'bundle id not changed: stop'; exit 1; }
   (cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug) || exit 1
   mkdir -p "$SCRATCH/home"
   HOME="$SCRATCH/home" CFFIXED_USER_HOME="$SCRATCH/home" \
     apps/desktop/build/macos/Build/Products/Debug/ShellX.app/Contents/MacOS/ShellX > "$SCRATCH/smoke.log" 2>&1 &
   PID=$!
   python3 - "$SCRATCH/smoke.log" "$PID" <<'EOF'
   import os, signal, sys, time
   log, pid = sys.argv[1], int(sys.argv[2])
   time.sleep(25)                      # first frame, sign-in window, version check
   os.kill(pid, signal.SIGTERM)        # only the app this recipe started
   EOF
   grep -E 'SF Mono not loaded|Unhandled|Exception|Error:' "$SCRATCH/smoke.log"   # expect no line
   pgrep -f "$SCRATCH" || echo 'no leftover'                                         # R35
   launchctl print "gui/$(id -u)" | grep -c 'pro.shellx.desktop.smoketest'          # expect 0 (R35)
   cd - && git worktree remove --force "$SCRATCH/wt" && rm -rf "$SCRATCH"
   ```
   **Expected:**
   - No error line. If any line matches, read it and explain it in the ledger; a relay `SocketException` while offline is benign.
   - No `ShellX: SF Mono not loaded (…)` line: the loader is silent on success (R7), so SF Mono was loaded on macOS.
   - No leftover process or launchd job.
   - If any leftover is found, stop it by its own PID, or `launchctl bootout` that single label (R35), and write it in the ledger.
   - Never touch the `pro.shellx.desktop` domain or its Keychain items.

5. **The ledger** (`docs/superpowers/ledgers/v2-5a.md`). Append:
   - **Results:** the test counts per package (step 1); the guard end state (step 2); the build and artifact checks (step 3); the smoke launch (step 4); the date and `HEAD`.
   - **Spike:** the SF Mono spike rows for macOS and iOS (already recorded by Task 1; confirm they are present).
   - **Rulings:** R1–R16 and the new R17+ of Tasks 5–10 and R30–R35, each with its cost if wrong.
   - **Manual checks pending (§12),** as 14 unchecked boxes:
     1. the spike on a real iPhone, and the fallback through `FORCE_BUNDLED_MONO`;
     2. the macOS names and the 1.0.0 → new dmg update;
     3. the Windows install over 1.0.0;
     4. iPhone;
     5. Android 10/14/16;
     6. readability (A36; record the result in the PR);
     7. widths;
     8. icons;
     9. Vietnamese input;
     10. contrast;
     11. performance;
     12. terminal;
     13. licences;
     14. VoiceOver/TalkBack.
   - **Follow-ups (§13.2):**
     - store names (the user, in the consoles);
     - `web/**` (needs consent);
     - **the three Inno lines need the user's approval before `main` (Task 15, A10, flagged);**
     - a new app and tray icon;
     - the Windows 11 caption colour;
     - renaming the old tokens after B and C;
     - JetBrains Mono into the package;
     - an OFL font closer to SF Mono;
     - **R14:** add `packages/shellx_design`'s `flutter test` to `.github/workflows/windows-check.yml` (outside A's files).

6. **Commit:**
   ```
   docs(v2-design): V2-5a ledger — final counts, guard end state, builds, smoke launch, manual checks and follow-ups

   Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
   ```
   Use the trailer of the model that commits. Never push, merge or force: the controller merges, and a push to `main` releases the desktop app.

## Self-review (partial — the writer stopped at 15:00)

- **Spec coverage:** every section of the spec maps to a task above (§4 → 13, 15; §5 → 3, 5, 6; §6 → 1, 4, 5, 6; §7.1–7.3 → 4, 9, 10; §7.4 → 8; §8 → 11, 12, 14; §9 → 13, 14; §10.1 → 1, 3, 4, 8, 14; §10.2 → 5, 9, 11, 13; §10.3 → 6, 10, 12, 13; §10.4 → 7; §10.5 → 9, 11, 12; §11 → Review Focus; §12 → ledger; §13.2 → Task 16). Tasks 5–16 still need full steps and code.
- **Placeholder scan:** Tasks 1–4 have none (their code is the code that ran). Tasks 5–16 are outlines by the controller's order.
- **Type consistency:** names produced by Tasks 1–4 are the ones the outlines consume (`shellxPrimaryButtonStyle`, `ShellxTypeScale.desktopFor`, `ShellxElevation.darkRaisedSmall`, `ShellxWedgeCorner`, `ShellxInsetShadow`, `shellxWeightedTextTheme`).
- **Review Focus:** the five lines are pinned in Tasks 1–4 (2, 3 partly) and assigned to Tasks 5–13 for the rest.
