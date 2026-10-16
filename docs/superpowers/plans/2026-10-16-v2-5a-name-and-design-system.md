# ShellX V2-5a — The app's full display name and the new design system Implementation Plan

Status: partial — tasks 1–4 written in full; tasks 5–16 outlined only (plan writer stopped 2026-10-16 15:00 on the controller's order).

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

### Task 5: The desktop adapter — tokens, theme, fonts, terminal — UNFINISHED (plan writer stopped 2026-10-16 15:00)

Started in the scratch union and analyze-clean, not yet run against the suite. What is decided:
- `ShellxDesktopColors`: every value a `ShellxPalette` constant per spec §5.9's table (e.g. `bgTerminal = navy900`, `rowSelected = navy700`, `rowPressed = navy650`, `line = hairline`, `border = hairlineStrong`, `textPrimary = white87`, `textTitle = white100`, `accent = primary = cyan`, `onPrimary = onCyan`, `err = errDialog = error`, `warnBg = warnSoft`, `warnBorder = warnLine`, `noticeBorder = noticeLine`, `destructiveHover = errorHover`); new `onAccent`, `link`, `overlayHover` (navy650), `overlayPressed` (navy600), `pushed` (navy800); `primaryHover`/`primaryPressed` removed (A50) — their only user, `ShellxPrimaryButton` (`ui/terminal/terminal_overlays.dart`), takes `shellxPrimaryButtonStyle()` in this task.
- `ShellxSpace` = `ShellxSpacing`; `ShellxRadius.r4/r6/r8/r12/pill` = `ShellxRadii.tiny/control/card/sheet/pill`; `ShellxShadows.e1/e2` = `ShellxElevation.darkFloat1/darkFloat2`, `e1Elevation`/`e1ShadowColor` from the package, new `raised` (= `darkRaisedSmall`) and `inset`; `ShellxMotion` = `ShellxDurations`/`ShellxCurves` (+ `slide`, `slideCurve`); `ShellxText` getters over `ShellxTypeScale.desktopFor(…, defaultTargetPlatform)` (R3) with new `display`.
- `buildDesktopTheme()`: `fontFamily: ShellxFonts.uiFamily(defaultTargetPlatform)`, `fontFamilyFallback: ShellxFonts.uiFallback(…)`, `textTheme`/`primaryTextTheme` through `shellxWeightedTextTheme` (R5); `ColorScheme.dark` with `surfaceContainerLowest…Highest` = navy900, navy850, navy750, navy750, navy700 and `surfaceTint` transparent; inputs (A43): fill navy900, outline `borderInput` (hover `textSecondary` via `WidgetStateInputBorder`), radius 16, focus cyan 1.5 px, disabled outline at 50 %; switch thumb `onPrimary` on a `primary` track when on (fixes `app_dialogs_test.dart:466`); slider, progress, text selection (`ShellxTerminalPalette.selection`), icon, dialog (r28, navy750, `hairlineStrong`, scrim), bottom sheet, popup menu, menu and dropdown menu (navy750, r16, `hairlineStrong`, `float1`), tooltip (navy700, r10, `hairlineStrong`, `small`, `float1`); window-level `filledButtonTheme` = `shellxPrimaryButtonStyle()` (gradient `accentStrong` through `shellxGradientLayer`, white label, outside ring), `outlinedButtonTheme` = `shellxSecondaryButtonStyle()` (raised navy700 + `raisedSmall`, hover `overlayHover`, pressed `pushed` without shadow, inside ring), `textButtonTheme` = `shellxTextButtonStyle()` (`link`; hover `rowHover`, pressed `rowPressed`). `buildDialogTheme` adds the dialog type and the 32/80/14 sizing on top. `destructiveButtonStyle()` brings its own `backgroundBuilder` (solid `error`, hover `errorHover`, pressed `error` + black 16 %) so the theme's gradient never shows through it.
- Code family: `kAiMono` (`ui/ai/ai_theme.dart`) stays `const`, family removed, weight 400 + `wght`; `ai_file_viewer.dart` passes `ShellxFonts.uiFamily/uiFallback` to re_editor's `CodeEditorStyle` (R13); `pages/confirm_page.dart` drops `fontFamily: 'JetBrainsMono'`.
- Terminal (§6.8, A37): `third_party/xterm/lib/src/ui/terminal_text_style.dart` — `TerminalStyle` gains `double? normalWeight`, `double? boldWeight` (constructor, `copyWith`, `fromTextStyle` keeps null), `toTextStyle` adds `fontVariations: [FontVariation('wght', bold ? boldWeight : normalWeight)]` when set; record it in `third_party/xterm/SHELLX_PATCHES.md`. `apps/desktop/lib/src/terminal/terminal_style.dart` `desktopTerminalStyle`: on macOS (`defaultTargetPlatform`) with no user family: family `ShellxFonts.systemMono`, fallback `[regular ? JetBrainsMono : JetBrainsMonoLight, ...xterm's]`, `normalWeight` 300 (`regular` → 400), `boldWeight` 700; Windows unchanged; a user `font-family` stays first and then **no** weights are set (ruling to add: a user's own variable font is drawn as the system has it). `TerminalColors` (`ui/theme/terminal_colors.dart`) reads `ShellxTerminalPalette` (§5.7) and builds the `TerminalTheme`.
- `apps/desktop/lib/main.dart`: `await ShellxSystemFont.load();` right after `WidgetsFlutterBinding.ensureInitialized()` (before the version check), never in `daemon_main.dart`; `ShellxDesktopApp` (`ui/app.dart`) `builder:` wraps the app in `DefaultTextHeightBehavior(textHeightBehavior: TextHeightBehavior(leadingDistribution: TextLeadingDistribution.even))` (A35).

**Files:** Modify `apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart`, `ui/theme/terminal_colors.dart`, `ui/terminal/terminal_overlays.dart` (`ShellxPrimaryButton`), `ui/ai/ai_theme.dart`, `ui/ai/ai_file_viewer.dart`, `ui/pages/confirm_page.dart`, `ui/app.dart`, `lib/main.dart`, `lib/src/terminal/terminal_style.dart`, `third_party/xterm/lib/src/ui/terminal_text_style.dart`, `third_party/xterm/SHELLX_PATCHES.md`. Tests: rewrite `apps/desktop/test/ui/theme_test.dart` (§10.2: tokens point at the package and the new hex; families by platform with `debugDefaultTargetPlatformOverride` macOS → `'SF Mono'` + `['JetBrainsMono']`, Windows → `'JetBrainsMono'`; `uiFont()` copies the fallback list; `ShellxText` = §6.5; hover < selected < pressed, selected/sidebar 1.32; every A39 component theme; the gradient `backgroundBuilder` of `ShellxPrimaryButton` and of the dialog `FilledButton`, white label, hover/pressed/disabled, outside ring; the destructive style's own layer); update pinned hex at `notifications_panel_test.dart` (`0xFF1F2F34`), `attention_ring_test.dart`, `find_bar_test.dart`, `find_session_test.dart` (old `#5FD4E2` → the new `accent`), `app_dialogs_test.dart` (switch thumb → `onPrimary`); `terminal_style_test.dart` (macOS: `'SF Mono'`, 300/400/700, JetBrains Mono fallbacks; Windows as before); keep `terminal_font_weight_test.dart`; new `test/ui/font_coverage_test.dart` (parse `cmap` of `assets/fonts/JetBrainsMono-*.ttf`: the 134 letters and 5 marks — the same list as `SystemMonoFontTables.vietnamese`); geometry tests whose widths depend on font size get the new numbers (never a looser matcher).

**Interfaces:** Consumes Tasks 1, 3, 4. Produces `shellxPrimaryButtonStyle()`, `shellxSecondaryButtonStyle()`, `shellxTextButtonStyle()`, `destructiveButtonStyle()`, the new `ShellxDesktopColors` tokens, `ShellxShadows.raised/inset`, `ShellxText.display`, `ShellxMotion.slide/slideCurve`, `TerminalStyle.normalWeight/boldWeight` — used by Tasks 9 and 11 and by V2-5b.

**Spec decisions:** A16, A17, A18, A19, A21, A24, A27, A31, A34, A35, A37, A38 (theme part), A39, A43, A50; §5.9, §6.1, §6.5 (DT), §6.8, §10.2.

### Task 6: The phone adapter — colours, typography, theme, fonts, terminal, the dark default — UNFINISHED (plan writer stopped 2026-10-16 15:00)

**Files:** Modify `apps/mobile/lib/core/design/{app_colors,light_colors,dark_colors,typography,theme_data_factory,terminal_colors}.dart`; `lib/main.dart` (`ShellxSystemFont.load()` after `ensureInitialized`, then the A26 theme default); Create `lib/core/platform/theme_default.dart` (export from `core/core.dart`): saved `adaptive_theme` mode wins; else `SharedPreferences` key `shellx_theme_default`; else no `shellx_installed` (fresh install, `core/platform/fresh_install.dart`, read **before** DI sets it) → `dark`, else → `system`; write the result to `shellx_theme_default`. `lib/features/app/{app,splash_page}.dart` (`DefaultTextHeightBehavior` even, A35). Remove Raleway: the 18 `assets/fonts/Raleway-*.ttf`, `assets/licenses/Raleway-OFL.txt`, the `Raleway` family in `pubspec.yaml`, its licence in `features/app/font_licenses.dart`; regenerate `lib/shared/src/{fonts,assets}.gen.dart` (build_runner). Remove the 17 `FontFamily.jetBrainsMono` (13 files: AI, markdown, extra keys, link sheet, voice composer (`voice_composer.dart`, also `FontFamily.raleway` at its hint), QR card, Settings, `view_as_text_sheet.dart`, `session_picker.dart`, `ai_file_diff_page.dart`, `ai_item_page.dart`, `ai_changes_sheet.dart`, `ai_dock.dart`, `ai_items.dart`, `ai_markdown.dart`, `arrow_pad.dart`, `extra_keys_bar.dart`, `terminal_page.dart`) so code follows the theme; `features/terminal/presentation/terminal_metrics.dart` `shellxTerminalStyle`: iOS `ShellxFonts.systemMono` (fallback `JetBrainsMono`) with `normalWeight` 400 / `boldWeight` 700, Android `JetBrainsMono`.

Decided values (§5.9 `AppColors` table, dark / light): `background` navy850/#EAEFF5, `surface` navy750/#F5F7FA, new `raised` navy700/#FFFFFF, new `inset` navy900/#E0E6EE, `primaryText` white100/#141A26, `secondaryText` white60/#4E586B, `disable` white50/#596376, `border` fieldOutline (#76829C/#717C92), `divider` hairline (#14FFFFFF/#1A141A26), `primary` = `primaryFill` = `accent` cyan/#1767AD, `onPrimary` onCyan/white, new `onAccent` white, `primarySoft` cyanSoft/#DCE8F3, `link` #5EADEE/#1767AD, `ok`,`okDot` #5ED39C / #256B45,#2E8A57, `warn` #F5B94E/#7F4C00, `warnSoft`,`lightGold` #3B3937/#F2EDE6, `error`,`mainRed` #FF8A94/#B0202B, `errorSoft`,`lightRed` #3D3440/#F7E9EA, new `okSoft`,`lightGreen` #293D40/#E9F0EC, `scrim` #99000000/#73141A26, `keyAccent` #34C8E8/#1767AD, `keyboardLink` #5EADEE/#14598F, `keyboardError` #FF8A94/#A3161D, `keyboard*` kept, `gradient` = `ShellxGradients.accent`, new `gradientStrong`, `wedge`, `elevation` (`ShellxElevation.dark/light`); leftovers `mainGreen`, `mainGold`, `mediumRed`, `mediumOrange`, `blueGrey` = `ok`, `warn`, `error`, `warn`, navy900 (light: `text`). No `Color(0x` left in `core/design` (§10.4). `AppTypography` getters = `ShellxTypeScale.mobile*` + colour + `liningFigures`; `.medium/.semiBold/.bold` through `shellxWeight`; `.heavy` → 700. `ThemeDataFactory.create`: `ColorScheme.fromSeed(…).copyWith(…)` plus `surfaceContainerLowest…Highest` (dark navy900, navy850, navy750, navy750, navy700; light #FFFFFF, page, surface, surface, raised) and transparent `surfaceTint`; `fontFamily`/`fontFamilyFallback` from `ShellxFonts` (no Raleway), weighted text themes (R5), AppBar title `ShellxTypeScale.mobileAppBarTitle`; A39 themes: dialog (r28, `surface`, title `heading20` bold, body `paragraph`, text buttons `link`), bottom sheet (top r28, `surface`, drag handle `handle` 36×4, `float2`, max 90 %), popup menu (items 44), switch, slider, progress, text selection, icon, text button (`link`).

Tests: rewrite `test/core/design/design_tokens_test.dart` (§10.3: new hex both brightnesses; the 11 old contrast pairs with the new values — all pass, computed while writing this plan: e.g. `keyAccent` dark on `keyboardKey` 4.60, light 5.87 — plus `onAccent` on `accent` ≥ 3 / `accentStrong` ≥ 4.5, text on `raised` and `inset`, placeholder on `inset` 4.99/4.82; the AppButton expectations move to Task 10); `test/platform_config_test.dart` (no `Raleway-*` file, no Raleway declaration; `:243` Raleway licence assertion removed); `terminal_page_test.dart:1555-1561` (`fontFamily == null` on the voice field and hint; effective family is the theme's: iOS `'SF Mono'`, Android `'JetBrainsMono'`); `test/app_test.dart` "both font licences are registered" becomes JetBrains Mono only; three-case A26 test with `SharedPreferences.setMockInitialValues`; `test/core/design/font_coverage_test.dart` for `assets/fonts/JetBrainsMono-*.ttf`.

**Interfaces:** Consumes Tasks 1, 3, 4. Produces the new `AppColors` roles (`raised`, `inset`, `onAccent`, `okSoft`, `gradientStrong`, `wedge`, `elevation`), `resolveInitialThemeMode(...)` (name to fix when written) — used by Tasks 10, 12, V2-5b/C.

**Spec decisions:** A16, A18, A22, A25, A26, A31–A35, A37, A39, A41 (theme part), §5.4, §5.9 (ĐT), §6.1, §6.5 (ĐT), §6.8, §10.3.

### Task 7: Raw-style guards in both apps, with their baselines — UNFINISHED (plan writer stopped 2026-10-16 15:00)

**Files:** Create `apps/desktop/test/design/raw_style_guard_test.dart`, `apps/desktop/test/design/raw_style_baseline.dart`, `apps/mobile/test/design/raw_style_guard_test.dart`, `apps/mobile/test/design/raw_style_baseline.dart`.

What to build (§10.4): scan `lib/**/*.dart` minus generated files (`*.g.dart`, `*.gr.dart`, `*.config.dart`, `*.gen.dart`, `lib/l10n/**`, `shared/src/l10n.dart`, `shared/src/intl/**`) and the adapters (`lib/src/ui/theme/**` DT, `lib/core/design/**` ĐT); count per file `Color(0x`, `Color.fromARGB(`, `Color.fromRGBO(`, `Colors.` (minus `Colors.transparent`), `TextStyle(`, `fontSize:`, `fontWeight:`, `fontFamily:`, `BoxShadow(`, `BackdropFilter(`, `ImageFilter.blur(`, `Icons.`, `CupertinoIcons.`, each only when no letter, digit or `_` precedes it (regex `(?<![A-Za-z0-9_])`); compare with the baseline map and require an **exact** match (a higher count: "new hard-coded style"; a lower one: fail and print the line to lower the baseline). On failure, print the whole current map as Dart source so it can be pasted. Adapters: no `Color(0x` in `lib/src/ui/theme/*.dart` / `lib/core/design/*.dart`.

Union counts measured while writing (before A; generated and adapters excluded) — desktop: `Icons.` 171, `fontWeight:` 19, `fontSize:` 12, `TextStyle(` 5, `fontFamily:` 5, `Color(0x` 1, `Colors.` 1; mobile: `Icons.` 104, `TextStyle(` 22, `fontSize:` 21, `fontFamily:` 20, `Colors.` 20, `Color(0x` 15, `fontWeight:` 9, `BoxShadow(` 5, `BackdropFilter(` 1, `ImageFilter.blur(` 1. The baseline is taken **after Tasks 5–6** (so `fontFamily:` already dropped on mobile) and lowered by Tasks 8–12; end state: `Icons.`, `CupertinoIcons.` 0; `fontWeight:` 0 except R13's config entry; `BackdropFilter(`/`ImageFilter.blur(` 1 each in `qr_scanner_page.dart`; `popup_handler.dart` absent.

**Interfaces:** none produced.

**Spec decisions:** A46, §10.4, R13.

### Task 8: `ShellxIcons` and every Material icon replaced — UNFINISHED (plan writer stopped 2026-10-16 15:00)

**Files:** Create `packages/shellx_design/lib/src/icons.dart`, `packages/shellx_design/test/icons_test.dart`; Modify `packages/shellx_design/lib/shellx_design.dart`; every `apps/{desktop,mobile}/lib/**` and `test/**` file with `Icons.` (one commit, A45); both guard baselines (`Icons.` → 0).

What to build: `abstract final class ShellxIcons` with the **95** `static const IconData` roles of spec §7.4 exactly (87 roles + 8 `voice*`; 91 `CupertinoIcons.*`, 4 Material fallbacks: `terminal` = `Icons.terminal_rounded`, `faceId` = `Icons.face_rounded`, `fingerprint` = `Icons.fingerprint_rounded`, `sshHost` = `Icons.dns_rounded`), plus `static const Map<String, IconData> roles` (for the test; V2-5b adds its roles to both). `icons_test.dart`: every role `fontFamily == 'CupertinoIcons'` and `fontPackage == 'cupertino_icons'` except exactly those 4 (`MaterialIcons`); the 8 `voice*` glyphs of §7.4; `roles` has 95 entries and matches every `static const IconData` declared in `icons.dart` (parse the source); the package `pubspec.yaml` pins `cupertino_icons: 1.0.9`. Replacement: a deterministic script mapping each `Icons.<glyph>` by §7.4's "Thay `Icons.*`" column; checked on the union: **every glyph used in both apps maps** (desktop 74 kinds, mobile 60). Context-dependent: `Icons.extension_outlined` → `ShellxIcons.toolOther` in `ui/ai/ai_tool_card.dart` (`ToolKind.other`) and mobile `ai_items.dart`, `ShellxIcons.tool` elsewhere (`ui/tools/tool_bar.dart`, `tool_project_list.dart`, `tool_sidebar_group.dart`, `session_sidebar.dart`, `ai/ai_header.dart`, mobile `session_picker.dart`); `kPhoneIcon` (`terminal_overlays.dart`) = `ShellxIcons.phone`; the AI tool-card kind table of §7.4 (`fetch` → `fetch` globe in both apps). Add `import 'package:shellx_design/shellx_design.dart';` where needed; tests' `find.byIcon(Icons.x)` change in the same commit. Tray and app icons unchanged.

**Interfaces:** Produces `ShellxIcons.*` (all 95 names of §7.4) — consumed by Tasks 9–12, V2-5b T48, V2-5c §4.8.

**Spec decisions:** A45, §7.4, §10.1 `icons_test.dart`, success criterion 5.

### Task 9: Desktop components — UNFINISHED (plan writer stopped 2026-10-16 15:00)

**Files:** Create `apps/desktop/lib/src/ui/components/{shellx_chip,shellx_segmented,shellx_card,shellx_brand_line}.dart` and their tests under `apps/desktop/test/ui/components/`; Modify `ui/terminal/terminal_overlays.dart` (`ShellxIconButton`: flat / raised / gradient-when-on variants, bo 10; `NoticeToast`: bo 16, max 420, `float1`, normal navy750 + `hairlineStrong` + `textPrimary`, error `noticeBg`/`noticeLine`/`noticeText`), `ui/terminal/shellx_menu.dart` (`showShellxMenu`: navy750, bo 16, `hairlineStrong`, `float1`, padding 4; items 28 high, bo 10, padding 0/10, hover `overlayHover` + `textTitle`, hints `textDialog2`, pressed `overlayPressed`), `ui/dialogs/{route_dialog,dialog_layout}.dart` (box bo 28, navy750, `hairlineStrong`, `float2`, scrim 60 %; `DialogBody` gains a `brand` flag drawing `ShellxBrandLine` 8 px above the title), `ui/ai/ai_changes_panel.dart` (its `SegmentedButton` → `ShellxSegmented`, A40).

Component values (§7.1): `ShellxChip` 24 high, padding 0/10, 11.5/500, bo 10, icon 14, `hairlineStrong` border on transparent, hover navy800, pressed `pushed`, selected `accentStrong` + white 600 (hover/pressed shades), rings (inside; selected outside); `ShellxSegmented<T>` track 28 high, padding 2, bo 10, inset (`ShellxInsetBox`), segments 24 high, bo 8, min 56, padding 0/10, 11.5 text, unselected `textSecondary` (hover `textPrimary` on navy800), selected `accentStrong` + white 600 + `raisedSmall`, tile slides in `slide`, one tab stop, ←/→ change, `Semantics(button, selected, inMutuallyExclusiveGroup, label)`; `ShellxCard` (`flat` navy750 + `hairlineStrong`, `raised`, `inset`; bo 16, padding 12; pressable: hover `overlayHover`, pressed `pushed`, inside ring); `ShellxBrandLine` (`appTitle`, `label`, `accent`). Perf (§10.5): sidebar 30 tabs with one selected → ≤ 2 `BoxShadow` under the sidebar. Tests per §10.2 "Component mới".

**Interfaces:** Consumes Tasks 4, 5, 8. Produces `ShellxChip`, `ShellxSegmented<T>`, `ShellxCard`, `ShellxBrandLine`, `DialogBody(brand: true)` — consumed by Task 11 and V2-5b ("chip / segmented / thẻ / menu của A").

**Spec decisions:** A38 (widgets), A40, A41 (DT), A44, §7.1, §7.3, §10.2, §10.5 (DT).

### Task 10: Phone components — UNFINISHED (plan writer stopped 2026-10-16 15:00)

**Files:** Modify `apps/mobile/lib/shared/src/{app_button,app_text_field,notice_banner,confirm_dialog,app_error_view}.dart`, `lib/features/auth/presentation/widgets/password_text_field.dart`, `lib/core/handler/popup_handler.dart` (toast); Create `lib/shared/src/{shellx_bottom_bar,shellx_segmented,shellx_chip,shellx_card,shellx_brand_header}.dart` (export from `shared.dart`) and tests under `apps/mobile/test/shared/`.

Values (§7.1): `AppButton` 54 high, bo 10, `Ink(decoration: gradient)` `accent` (→ `accentStrong` when `MediaQuery.textScalerOf(context).scale(15) < 15`), label 15/700 `onAccent`, `IconTheme(onAccent)` for `prefix`/`suffix` (A22: drop the self-coloured icons at `session_picker.dart` (the "Phiên mới" prefix), `machine_list_page.dart` (two prefixes) and `app_error_view.dart`), `cta` shadow, press scale 0.98 in `press`, disabled 0.45; a `backgroundColor` override (destructive, transparent text-like uses) keeps a solid fill. `AppTextField`/`PasswordTextField`: 52 high, bo 16, `inset` fill, 1.5 px `border`, inner shadow via `ShellxInsetBox`, focus `primary` 2 px, error `error` + text 4 px below. Toast: top centre, bo 16, `surface` (dark navy750, never white), icon 20 by kind (`ok`, `warn`, `error`, `primary`), title 14/600, description 13 `secondaryText`, error `errorSoft`, 3 s, swipe up to close. `ShellxBottomBar` (B places it): 64 + safe area, `navy825` (light `raised`), top bo 28, `float1` flipped up, equal items ≥ 48×48, icon 24, label 12/600 one line, text scale capped 1.3×; active: 56×36 `ShellxSlantBorder` tile, `accent`, `cta`, white icon, label `primaryText` 700, slides in `slide` (instant with reduced motion), `HapticFeedback.selectionClick()`; badge dot 8 `accent` or count pill 16 `error`/`onError`; `Semantics(container, explicitChildNodes)` and per item `Semantics(button, selected, inMutuallyExclusiveGroup, label)`. `ShellxSegmented<T>` (track ≥ 48, padding 4, bo 14, segments ≥ 40, bo 10, 13/600, up to 2 lines), `ShellxChip` (36 high, padding 0/14, 13/600, `raised`), `ShellxCard` (bo 16, padding 16), `ShellxBrandHeader` (logo 48 + `title` 700 name, `maxLines: 2`; splash: logo 72 over `heading20` 700). Tests per §10.3 "Component mới" (2 lines at 320 pt, 1.3× labels, toast dark not white).

**Interfaces:** Consumes Tasks 4, 6, 8. Produces `ShellxBottomBar`, `ShellxSegmented<T>`, `ShellxChip`, `ShellxCard`, `ShellxBrandHeader` — consumed by Task 12, V2-5b (bottom bar, chips) and V2-5c (VI│EN segmented).

**Spec decisions:** A22, A27, A28, A38 (ĐT), A40, A41, A42, §7.1, §10.3.

### Task 11: Desktop screens (§8.1) — UNFINISHED (plan writer stopped 2026-10-16 15:00)

**Files:** `ui/terminal/{session_sidebar,session_tab_row,workspace_header,sidebar_new_button,sidebar_remote,attention_marks,agent_badge,agent_chip,terminal_pane,pane_tree_view,info_strip,remote_strip,resume_banner,terminal_overlays,notifications_panel,find_bar,key_sequence}.dart`, `ui/terminal/terminal_workspace_page.dart`, `ui/tools/*`, `ui/config/{command_palette,search_all_overlay,shortcuts_sheet,config_problems_panel}.dart`, `ui/onboarding/{tour_overlay,whats_new_card}.dart`, `ui/settings/{settings_overlay,settings_row}.dart`, `ui/settings/pages/*`, `ui/pages/*`, `ui/ssh/ssh_connect_dialog.dart`, `ui/tools/tool_dialogs.dart`, `ui/ai/*` (tokens/components only, layout kept — V2-5b), the 6 `AlertDialog` users. Every remaining `fontWeight:` → `shellxWeight` (guard: 0 except R13); markdown `strong`/headings through `shellxWeight` (R5); links `link`; the terminal empty state gets `ShellxWedge` top-right and a gradient primary button; the selected sidebar row is a raised tile (`raisedSmall`) + cyan bar 3×18; Settings nav item likewise; "Giấy phép và ghi công…" button lives in Task 14. Lower the guard baseline.

**Interfaces:** Consumes Tasks 5, 8, 9.

**Spec decisions:** §8.1, A21 (link on strips/markdown), A29/A30 places (DT), A44, A49, §10.5 (DT).

### Task 12: Phone screens (§8.2) — UNFINISHED (plan writer stopped 2026-10-16 15:00)

**Files:** `features/app/{splash_page,update_required_page,connection_banner}.dart`, `features/auth/presentation/pages/{login_page,register_page}.dart`, `features/lock/presentation/{lock_gate,biometric_method}.dart`, `features/machines/presentation/pages/machine_list_page.dart` (cards flat bo 16; online dot `ok`; first-run empty state: brand line + `ShellxWedge` + steps card in `ShellxGlass` σ 16), `features/pairing/presentation/pages/qr_scanner_page.dart` (camera overlay kept; failure sheet and success screen by token; its `BackdropFilter` σ 3 stays, A44), `features/terminal/presentation/{pages/terminal_page,widgets/session_picker,widgets/extra_keys_bar,widgets/arrow_pad,widgets/keyboard_cover,widgets/link_sheet,widgets/view_as_text_sheet,widgets/agent_reply_bar}.dart`, `features/ai/presentation/**` (tokens/components only), `features/tools/presentation/pages/tool_page.dart`, `features/settings/presentation/pages/{settings_page,delete_account_page}.dart` (groups as flat cards; theme picker `ShellxSegmented<AdaptiveThemeMode>`; delete-account button destructive), `features/voice/presentation/widgets/{voice_composer,mic_button}.dart` (`SegmentedButton<VoiceLocale>` → `ShellxSegmented`, A40), `shared/src/confirm_dialog.dart`, `core/router/app_transparent_route.dart`; the 8 `showModalBottomSheet` calls lose their own `backgroundColor`/`shape` (A39). Remaining `fontWeight:` → `shellxWeight`; guard lowered (`popup_handler.dart` gone from it). Tests: `settings_page_test.dart` (`ShellxSegmented<AdaptiveThemeMode>`, the 2× text on 320 pt test stays green), `terminal_page_test.dart:1528` (`ShellxSegmented<VoiceLocale>`), §10.5 (8 machines: 0 `BoxShadow` in rows; AI session 50 items: 0 in the timeline; no `ShellxGlass` on the terminal and tool pages).

**Interfaces:** Consumes Tasks 6, 8, 10.

**Spec decisions:** §8.2, A12 (ĐT brand header on splash/login/register/first-run), A29/A30 places (ĐT), A39, A40, A41, A44, A49, §10.3, §10.5 (ĐT).

### Task 13: ⚠ The full name and the identity pins — UNFINISHED (plan writer stopped 2026-10-16 15:00)

**Files (spec §4.1, verbatim values in §9):** `apps/mobile/ios/Runner/Info.plist` (`CFBundleDisplayName` = `ShellX: Remote AI agents`; `CFBundleName` stays `shellx_mobile`; no key added to `en.lproj`/`vi.lproj/InfoPlist.strings`), `apps/mobile/android/app/src/main/AndroidManifest.xml` (`android:label="ShellX: Remote AI agents"`), `apps/mobile/lib/l10n/intl_{en,vi}.arb` (`appTitle` = `ShellX: Remote AI agents`; `settingsVersion` = `ShellX: Remote AI agents {version} ({build})`; regenerate), `features/app/splash_page.dart` (`MaterialApp.onGenerateTitle: (context) => S.of(context).appTitle`, A13), `apps/desktop/lib/l10n/app_{en,vi}.arb` (`appTitle`, `trayTooltip` = the long name; `windowTitle` stays `{title} — ShellX`; `flutter gen-l10n`), `apps/desktop/lib/src/ui/window_host.dart` (`windowTitleFor(null, l10n)` → `l10n.appTitle`; `WindowManagerHost.init({required String title})`), `lib/main.dart` (`windowHost.init(title: l10n.appTitle)`; `_windowsErrorBox(title, message)` with `l10n.appTitle` at both calls; notification titles stay "ShellX", A9), `ui/terminal/terminal_pane.dart` (the macOS pane header with no tab → `l10n.appTitle`), `apps/desktop/windows/runner/main.cpp` (`window.Create(L"ShellX: Remote AI agents", …)`), `apps/desktop/windows/runner/Runner.rc` (`FileDescription` only), `apps/desktop/macos/Runner/Info.plist` (add `CFBundleDisplayName` = `ShellX`, `LSHasLocalizedDisplayName` = true), new `apps/desktop/macos/Runner/en.lproj/InfoPlist.strings` (`"CFBundleDisplayName" = "ShellX: Remote AI agents";`) added to the Runner target's Resources as a variant group like `MainMenu.xib` (pbxproj ids `5A5F0001…A002`, `5A5F0002…A002`, `5A5F0003…A002`). Identities stay (spec §4.2 table).

Tests: change `apps/mobile/test/platform_config_test.dart` (`:28` long `CFBundleDisplayName`, `:123` long `android:label`; add: the two `InfoPlist.strings` have no `CFBundleDisplayName`, `CFBundleName` = `shellx_mobile`), `settings_page_test.dart:172, 277, 557` ("ShellX: Remote AI agents 1.0.0 (1)"), `shared/shellx_logo_test.dart:13` (semantics label long), `apps/desktop/test/ui/window_flow_test.dart:748` (`windowTitleFor(null, l10n)` long; `:752` kept); add `apps/desktop/test/platform/identity_pins_test.dart` (`Runner.rc` `FileDescription` long, `ProductName`, `CompanyName`, `InternalName`, `OriginalFilename` kept; `CMakeLists.txt` `BINARY_NAME` = `ShellX`; `main.cpp` long title; `AppInfo.xcconfig` `PRODUCT_NAME` and bundle id kept; `Info.plist` the two A5 keys; `en.lproj/InfoPlist.strings` long; `notifier.dart` and `launch_at_login.dart` `appName: 'ShellX'`), ARB tests for `appTitle`, `trayTooltip` (DT) and `appTitle`, `settingsVersion` (ĐT) in EN and VI, `splash_page_test.dart` (the splash's `MaterialApp` title is the long name). Kept as is: the tests listed in spec §4.3 "Giữ". Check: `flutter build macos --debug` in a throw-away worktree (no launch) shows `Contents/Resources/en.lproj/InfoPlist.strings`; revert the `COCOAPODS:` line if the build ran in the worktree.

**Interfaces:** none new.

**Spec decisions:** A1–A9, A11, A13, §4.1–§4.3, §9.1–§9.2, Review Focus 1.

### Task 14: ⚠ Native launch screens and the licence page — UNFINISHED (plan writer stopped 2026-10-16 15:00)

**Files:** `apps/mobile/ios/Runner/Base.lproj/LaunchScreen.storyboard` (background #222834, logo kept), `apps/mobile/android/app/src/main/res/drawable/launch_background.xml`, `drawable-v21/launch_background.xml`, `values/styles.xml`, `values-night/styles.xml` (`NormalTheme`), new `values-v31/styles.xml` (`android:windowSplashScreenBackground`), `values/colors.xml` (`shellx_page` #222834) (A48); `packages/shellx_design/lib/src/licenses.dart` + test (`registerShellxDesignLicenses()`: one `LicenseEntryWithLineBreaks(['Online Bike Shopping App (design reference)'], <the §9.3 text verbatim>)`), both apps' `main.dart` call it once; new ARB `licensesLegalese` (EN/VI §9.1) in both apps, `settingsLicenses` (DT only: "Licenses and credits…" / "Giấy phép và ghi công…"); DT Settings › General button under the version line opening `showLicensePage(applicationName: appTitle, applicationLegalese: licensesLegalese)`; ĐT `showLicensePage` gets `applicationLegalese`. Tests: licence entry present, no SF Mono entry; platform_config_test pins the launch colours.

**Spec decisions:** A47, A48, §9.3, manual §12 items 4, 5, 13.

### Task 15: ⚠ The Windows installer's three display lines — UNFINISHED (plan writer stopped 2026-10-16 15:00)

**Flagged: `release/windows/shellx.iss` is a teammate's file on `main`; tell the user before it is merged to `main` (A10).** Change only `AppName=ShellX: Remote AI agents` (`:22`), `AppVerName=ShellX: Remote AI agents {#AppVersion}` (`:24`), `UninstallDisplayName=ShellX: Remote AI agents` (`:44`). Keep `AppId`, folders, group, shortcut names, `LaunchProgram,ShellX`, `AppPublisher`. No new test in `release/tests`; run the existing `release/tests/inno.test.mjs` (`node --test`) to show it still passes. Separate commit.

**Spec decisions:** A10, §4.1 rows 16–18, §13.2.

### Task 16: Final verification and the ledger — UNFINISHED (plan writer stopped 2026-10-16 15:00)

Run analyze + tests for `packages/shellx_design`, `apps/desktop`, `apps/mobile` and every other package (`shellx_core`, `shellx_agent`, `shellx_client`, `shellx_e2e`, `shellx_acp`, `shellx_ai` with `dart analyze`/`dart test`); builds without launching: `flutter build apk --debug`, `flutter build ios --debug --no-codesign`, `flutter build macos --debug` in a throw-away worktree; search the built `.app`, `.apk` and iOS `Runner.app` for any `SF*Mono*` file (none); the isolated smoke launch of the full desktop app (allowed only because Task 2 is done; bundle id `pro.shellx.desktop.smoketest`, temporary HOME, own Keychain service, stop by PID; it calls the relay's public `/v1/version`): no exception, SF Mono loaded on macOS; record test counts, guard end state (Task 7), spike rows, and the 14 manual checks of §12 (unchecked) in the ledger; follow-ups of §13.2 plus R14's CI line.

---

## Self-review (partial — the writer stopped at 15:00)

- **Spec coverage:** every section of the spec maps to a task above (§4 → 13, 15; §5 → 3, 5, 6; §6 → 1, 4, 5, 6; §7.1–7.3 → 4, 9, 10; §7.4 → 8; §8 → 11, 12, 14; §9 → 13, 14; §10.1 → 1, 3, 4, 8, 14; §10.2 → 5, 9, 11, 13; §10.3 → 6, 10, 12, 13; §10.4 → 7; §10.5 → 9, 11, 12; §11 → Review Focus; §12 → ledger; §13.2 → Task 16). Tasks 5–16 still need full steps and code.
- **Placeholder scan:** Tasks 1–4 have none (their code is the code that ran). Tasks 5–16 are outlines by the controller's order.
- **Type consistency:** names produced by Tasks 1–4 are the ones the outlines consume (`shellxPrimaryButtonStyle`, `ShellxTypeScale.desktopFor`, `ShellxElevation.darkRaisedSmall`, `ShellxWedgeCorner`, `ShellxInsetShadow`, `shellxWeightedTextTheme`).
- **Review Focus:** the five lines are pinned in Tasks 1–4 (2, 3 partly) and assigned to Tasks 5–13 for the rest.
