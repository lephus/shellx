# ShellX V2.5 research: design system and app name

Read-only research, 2026-10-16. Nothing in the repository was modified.

## 0. Sources and conventions

- App code: worktree `/Users/richard/Documents/helper/shellx/.claude/worktrees/v2-2b` (branch `v2-2b`; HEAD was `5e09e85` when I started and `640141b` at the end, a push-notification change with no style impact). Other agents have uncommitted edits there (mobile `machine_list_page.dart`, `intl_*.arb` and the generated l10n files, new `machine_ai_lines*` files), so mobile ARB line counts may drift by a few. Paths below are relative to that root unless prefixed.
- `origin/main:<path>`: the local `origin/main` ref, which is **stale** (`e74b02f`). The real remote `main` is `6ba1f0a` (checked with `git ls-remote`; the commit object is present locally). Its diff against `e74b02f` touches only mobile store-release files (`release/mobile/**`), `apps/mobile` signing/build number, and `web/` copy. `.github/` and `release/{macos,windows,scripts}` are identical in both. Files from the newer commit are prefixed `main@6ba1f0a:`.
- Theme files on `origin/main` and `v2-2b` are identical for the desktop theme and the mobile design folder (checked with `git diff --stat`).
- Two in-flight branches (not merged) add UI that a restyle will meet: `v2-3` adds `apps/desktop/lib/src/ui/tools/*` (tool area, bar, dock, sidebar group) and edits `session_sidebar.dart`, `pane_tree_view.dart`, `terminal_overlays.dart`, `terminal_workspace_page.dart`; `v2-4` adds `apps/mobile/lib/features/tools/*` (tool page, web engine) and edits `settings_page.dart`.
- Counts come from `grep` over `lib/` excluding generated l10n (`lib/l10n/`, `shared/src/l10n.dart`, `shared/src/intl/`), `*.gr.dart`, `*.config.dart`. "Outside theme" means outside `apps/desktop/lib/src/ui/theme/`; for mobile, outside `apps/mobile/lib/core/design/`.
- Network use, all read-only: `git ls-remote origin`, `git fetch --dry-run` (changed nothing), and `curl` HEAD on the public download URLs and `/v1/version`.

## 1. Summary for planning

1. **Desktop is one dark theme, fully tokenised, with no light mode** (documented decision, `docs/superpowers/design/2026-10-06-shellx-desktop-ui.md:11`). All 68 hex colour literals live in two files (`apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart` 40, of which 37 are colour tokens and 3 are shadow colours; `terminal_colors.dart` 28). Outside them there are **0** hex literals and **21** raw `Colors.*` (20 are `Colors.transparent`, 1 is `Colors.white` for the QR quiet zone, `pages/pairing_page.dart:86`).
2. Changing colour *values* on desktop is a two-file change. Changing token *names*, adding a light mode, or changing metrics is not: tokens are `static const` (`ShellxDesktopColors`, 594 references in 75 files; `ShellxText` 216 in 62; `ShellxSizes` 351 in 41; `ShellxSpace` 342 in 57; `ShellxRadius` 80 in 46), so they cannot follow a runtime theme switch without touching every call site.
3. **Desktop chrome font is the platform font** (SF Pro / Segoe UI, no `fontFamily` anywhere, on purpose: `design/...desktop-ui.md:60`, `:422`). Terminal and code use bundled JetBrains Mono (default weight Light via a separate `JetBrainsMonoLight` family). There is no `google_fonts` anywhere in the repo. A global UI font is a one-line change in `buildDesktopTheme()` because `uiFont()` copies the family from `textTheme.bodyMedium` (`shellx_desktop_theme.dart:474-480`), but tests pin "no UI font" (`theme_test.dart:16-22,53-74`, section 4.2).
4. **Mobile supports light, dark and system** (`adaptive_theme`, selector at `features/settings/presentation/pages/settings_page.dart:309-334`). Palette in `core/design/{light,dark}_colors.dart`, one `ThemeDataFactory`. Chrome font is bundled Raleway (18 files), terminal font JetBrains Mono. Outside `core/design`: 15 hex literals, 20 non-transparent raw `Colors.*` (7 more are `transparent`), 21 `TextStyle(`, 55 literal radii. Biggest off-token spots: `qr_scanner_page.dart` (25 hits), `core/handler/popup_handler.dart` (toasts: white card with black text in both themes), `terminal_page.dart`.
5. **There are no image golden tests in either app** (0 `matchesGoldenFile`; `shortcut_golden_test.dart` is a text fixture). One pixel test measures terminal-font ink (`apps/desktop/test/terminal/terminal_font_weight_test.dart`). What a restyle breaks is exact-value token tests and ~26 desktop / ~11 mobile tests with geometry assertions.
6. **The display name and the file/identity names are different things and must be decoupled before renaming.** Load-bearing "ShellX" strings: `ShellX.app`, `ShellX.exe`, Windows `ProductName`/`CompanyName` (they decide the app-data folder), `local_notifier`/`launch_at_startup` `appName`, shell-profile markers, `~/Library/Application Support/ShellX`, `%LOCALAPPDATA%\ShellX`, installer/dmg file names, `pro.shellx.desktop`, `com.shellx.prod`, `shellx://`.
7. **A colon is invalid in Windows file names** (and awkward on macOS), so `ShellX: Remote AI agents` cannot reach `ProductName`, `BINARY_NAME`, `PRODUCT_NAME`, or any `appName` handed to a plugin. `path_provider` replaces `:` with `_` and would silently move the Windows app-data folder (sign-in, device key, settings, lock files).
8. **Both 1.0.0 desktop installers are live** (`curl -I` returned 200 for `ShellX-1.0.0.dmg` and `ShellX-Setup-1.0.0.exe`; relay `/v1/version` names them; tag `desktop-v1.0.0` exists on the remote). iOS build `1.0.0+1` is already on App Store Connect (`main@6ba1f0a` commit `e3802e3`). So an installed base and store records exist; in-place upgrade paths matter.
9. There is **no auto-updater** (no Sparkle, WinSparkle, Squirrel). "Check for updates" opens a download link from the relay (`apps/desktop/lib/src/agent/update_check.dart:26-71`), trusted only if it is `https` on `shellx.pro` or a subdomain (`:58-71`). Installer upgrade detection is the Inno `AppId` GUID, not the name.
10. Brand drift already exists across surfaces: apps are teal/cyan (`#2DBFCF` dark primary, `#0097A8` light), the website is violet/pink (`web/src/layouts/Base.astro:138-148`, Space Grotesk display font), Android adaptive-icon background is `#140F2A` (violet).

## 2. Desktop app (`apps/desktop`)

### 2.1 Where theme things are defined

| Thing | Location |
|---|---|
| Colour tokens (`ShellxDesktopColors`: 37 colours plus `disabledOpacity`) | `apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart:6-55` |
| Spacing / radii | `:58-61` (`s2..s32`), `:64-66` (`r4, r6, r8, r12, pill`) |
| Fixed sizes (`ShellxSizes`, ~170 consts: sidebar 220, rows 30, header bands 38/36, dialogs 400/480/520, ...) | `:70-334` |
| Text styles (`ShellxText`: caption 11, small 12, body 13, bodyStrong 13/600, dialogBody 14, label 12.5, dialogTitle 17, emptyTitle 15; no `fontFamily`) | `:337-366` |
| Shadows / motion | `:369-381`, `:384-402` (`ShellxMotion.of(context, d)` zeroes durations for reduced motion) |
| Focus-ring shape for filled buttons | `:408-468` (`OutsideFocusRingBorder`, `buttonShape`) |
| `uiFont()` helper | `:474-480` |
| `ThemeData` for the window (`buildDesktopTheme`: `ColorScheme.dark`, scaffold, dividers, `InputDecorationTheme` 36px fields, `SwitchTheme`, `TooltipTheme`) | `:483-574` |
| Dialog-only theme (`buildDialogTheme`: text theme, Filled/Outlined/Text button styles) | `:579-676`, applied only at `apps/desktop/lib/src/ui/dialogs/route_dialog.dart:192-196` |
| Destructive button style | `:679-697` |
| Terminal colours + ANSI palette (copied from mobile, `TerminalColors`) | `apps/desktop/lib/src/ui/theme/terminal_colors.dart:5-61` |
| AI pane mono style `kAiMono` (JetBrainsMono 12/17) and `AiSizes` | `apps/desktop/lib/src/ui/ai/ai_theme.dart:7-28` |
| `MaterialApp` (`theme: buildDesktopTheme()`, `themeMode: ThemeMode.dark`) | `apps/desktop/lib/src/ui/app.dart:18-27` |
| Font licence registration | `apps/desktop/lib/src/ui/theme/font_licenses.dart` |
| Design source of truth (tokens, states, dialogs, copy) | `docs/superpowers/design/2026-10-06-shellx-desktop-ui.md` (+ `...-a2..a9.md`); AI pane demo CSS in `docs/superpowers/design/2026-10-14-ai-pane-demo/` |

Not used: `ThemeExtension`, `TextTheme` overrides for the main window, `CardTheme`, `ChipTheme`, `DialogTheme`, `google_fonts`, `dynamic_color`.

Hidden coupling to test before touching `textTheme`: `ShellxText` styles set size/height/weight only, so they inherit colour, letter spacing and family from the ambient `DefaultTextStyle`, which is `ThemeData.textTheme.bodyMedium` (the window is a `Scaffold`, `app.dart:63`). This is Flutter's normal merge behaviour; I did not render it to confirm the effective letter spacing.

### 2.2 Light and dark

- Dark only. `app.dart:24-25` passes only `theme:` and forces `ThemeMode.dark`; there is no `darkTheme`.
- Windows title bar forced dark: `apps/desktop/lib/src/ui/window_host.dart:199` (`setBrightness(Brightness.dark)`); macOS uses a hidden/transparent title bar (`:191-197`).
- User terminal themes (Ghostty format) are separate from the chrome. `light:A,dark:B` pairs resolve to the dark side, a `light:`-only value is used as is (`apps/desktop/lib/src/config/config_theme.dart:65-72`); the pane focus ring adapts to the terminal background (`:83-92`). So a light terminal can sit inside dark chrome.
- The built-in terminal palette is itself named `ShellX` (`apps/desktop/lib/src/config/theme_listing.dart:18`; a user theme file called `shellx` is rejected, `:31-37`). That name appears in Settings > Appearance and in `config_show.dart:45`.

### 2.3 Fonts

| | Chrome | Terminal | Code in AI pane |
|---|---|---|---|
| Desktop | Platform default (no `fontFamily`; `ShellxText` 11/12/12.5/13/14/15/17 px). Reason in the design doc: "Vietnamese diacritics render best in SF/Segoe at 13 px" (`design/...desktop-ui.md:422`) | `JetBrainsMonoLight` default, `JetBrainsMono` for `font-weight = regular`; user `font-family` (Ghostty config) first, bundled fonts as fallback; size 13 default, 9-28; line height 1.2 plus `adjust-cell-height` (`apps/desktop/lib/src/terminal/terminal_style.dart:5-43`) | `kAiMono` JetBrainsMono 12/17 (`ai_theme.dart:23-28`); markdown body 13/20 in the platform font (`ui/ai/ai_markdown.dart:84-91`); code viewer uses third-party `atomOneDarkTheme` colours (`ui/ai/ai_file_viewer.dart:179-183`) |
| Mobile | Raleway (bundled, weights 100-900 + italics, 18 files), lining numerals feature on every style (`core/design/typography.dart:8`) | JetBrainsMono Regular/Bold/Italic/BoldItalic, default 14, range 8-32 (`core/settings/app_settings.dart:17-19`; `features/terminal/presentation/terminal_metrics.dart:13`) | JetBrainsMono 12-13 (`ai_items.dart:617`, `ai_markdown.dart:111`) |
| Web | Space Grotesk (display) + system sans; JetBrains Mono (`web/src/layouts/Base.astro:115-148`) | n/a | n/a |

- Bundled fonts: desktop `apps/desktop/pubspec.yaml:83-108` (JetBrainsMono 85-95, JetBrainsMonoLight 99-108) with `assets/fonts/*.ttf` (6 files) and `assets/licenses/JetBrainsMono-OFL.txt`; mobile `apps/mobile/pubspec.yaml:99-157` (Raleway 101-146, JetBrainsMono 147-157), generated constants `lib/shared/src/fonts.gen.dart`.
- Literal family strings outside theme files: desktop `'JetBrainsMono'` at `ai_theme.dart:24`, `pages/confirm_page.dart:93`; `ai_file_viewer.dart:175` reads `kAiMono`.
- The terminal font is the same family on both apps, but only desktop ships the Light cut and defaults to it ("reads heavier than Ghostty", `terminal_style.dart:7-11`).

### 2.4 Reusable components: central vs ad hoc

Central (themed once, reused):

| Component | Where | Reuse |
|---|---|---|
| Window `ThemeData`: inputs (36px, r6), switch, tooltip, dividers | `shellx_desktop_theme.dart:483-574` | all |
| Dialog shell + body layout, labelled field, field error | `ui/dialogs/route_dialog.dart:43`, `dialog_layout.dart:12,117,142` | `DialogBody` 11 refs, `LabeledField` 8 |
| Dialog button styles (Filled/Outlined/Text) | `buildDialogTheme` `:579-676` | dialog pages only |
| Primary button, icon button, scrollbar | `ui/terminal/terminal_overlays.dart:30,92,253` | 8 / 9 / 10 refs |
| Context menu | `ui/terminal/shellx_menu.dart:50` (`showShellxMenu`) | 14 call sites, 66 `ShellxMenuEntry` |
| Info/notice strips, toast, driver pill, empty state | `info_strip.dart:11`, `terminal_overlays.dart:393,446,543,836` | 3-10 refs each |
| Destructive button | `shellx_desktop_theme.dart:679` | 6 refs |

Ad hoc (hand-built from tokens each time; no shared component):

- Chips: `AgentChip` (`ui/terminal/agent_chip.dart:10`, pill with `warnBg`), `_PrChip` (`session_tab_row.dart:1326`), `CopyModeChip` (`pane_tree_view.dart:1570`), AI config chips are `TextButton`s (`ai/ai_config_chips.dart:119-134`), one stock `Chip(` in `ai_timeline.dart`.
- Cards: no `Card`. Hand-rolled boxes (`surface` + `border` + `r8`): `ai_ask_card.dart`, `ai_notice_card.dart`, `ai_folder_card.dart`, `ai_tool_card.dart`, `onboarding/whats_new_card.dart`, `_ProjectCard` (`settings/pages/projects_page.dart:53`).
- Tabs: no `TabBar`. Tabs are vertical rows in the sidebar: `SessionSidebar` (`ui/terminal/session_sidebar.dart:42`, ~2,000 lines), `SessionTabRow` (`session_tab_row.dart:57`, ~1,500 lines), `WorkspaceHeader` (`workspace_header.dart:16`), pane headers (`pane_tree_view.dart:1077`), SSH dialog tab strip (`ssh_connect_parts.dart:4`).
- Sidebar surface: `bgSidebar` at `session_sidebar.dart:1771,1822`, width `ShellxSizes.sidebarWidth` 220.
- Settings: `SettingsOverlay` (`ui/settings/settings_overlay.dart:41`) with its own `_NavItem` (`:501-560`, literal 36 height, 14 padding, 2px accent bar), `SettingRow` (`settings_row.dart:83`) with its own switches, slider, text fields.
- Buttons outside dialogs: stock `FilledButton` (22 refs), `OutlinedButton` (24), `TextButton` (53), `IconButton` (17; the counts include the theme definitions themselves) take the stock M3 look unless given a style, because `buildDialogTheme` is not applied outside `RouteDialogHost` (its own comment says the workspace "keeps its own explicit styles", `:576-578`).
- Stock Material otherwise: `TextField` 24 uses (themed by `InputDecorationTheme`), `Switch` 3, `Slider` 1, `DropdownMenu` 1, `SegmentedButton` 1, `ListTile` 2, stock `AlertDialog`/`Dialog` through `showDialog` (so a second dialog style next to `RouteDialogHost`) in `ai/ai_log_dialog.dart:19`, `ai/ai_changes_panel.dart:45-52`, `ai/ai_history.dart:29-70`, `ai/ai_config_chips.dart:41-45`, `ai/ai_agents_section.dart:88-156` and `settings/pages/advanced_page.dart:23-25`; these take the window theme, not `buildDialogTheme`.
- Icons: 149 `Icons.*` references (Material icons) across the UI.

### 2.5 Hard-coded and token usage, grouped by directory (outside `ui/theme`)

| Directory (`apps/desktop/lib/src/...`) | Dart files / LOC | `ShellxDesktopColors.` refs | `ShellxText.` refs | raw `Colors.*` | `TextStyle(` | `fontSize:` | `fontWeight:` | `EdgeInsets` with literals |
|---|---|---|---|---|---|---|---|---|
| `ui/terminal` | 38 / 15,009 | 258 | 70 | 15 | 0 | 0 | 10 | 20 |
| `ui/ai` | 30 / 8,400 | 194 | 79 | 1 | 4 | 5 | 2 | 47 |
| `ui/config` (palette, shortcuts, problems, search) | 7 / 2,505 | 57 | 26 | 0 | 0 | 0 | 3 | 19 |
| `ui/settings` | 9 / 2,260 | 32 | 16 | 3 | 0 | 3 | 1 | 21 |
| `ui/settings/pages` | 9 / 1,421 | 28 | 19 | 0 | 0 | 1 | 1 | 24 |
| `ui/onboarding` | 2 / 353 | 11 | 4 | 0 | 0 | 0 | 0 | 4 |
| `ui/dialogs` | 3 / 428 | 6 | 2 | 1 | 0 | 0 | 0 | 1 |
| `ui/pages` (login, pairing, confirm, ...) | 5 / 652 | 2 | 0 | 1 | 0 | 0 | 0 | 1 |
| `ui` (top level) | 9 / 954 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `config` + `terminal` (non-UI Dart that touches style) | - | 6 | 0 | 0 | 1 | 3 | 1 | 2 |
| **Total outside theme** | | **594** | **216** | **21** (20 transparent) | **5** | **12** | **18** | **139** |
| Inside `ui/theme` (3 files, 769 LOC) | | 55 | 9 | 3 | 9 | 8 | 5 | 2 |

- Hex `Color(0x...)`: 0 outside theme, 68 inside (40 + 28).
- Other token usage outside theme: `ShellxSizes.` 351 refs / 41 files, `ShellxSpace.` 342 / 57, `ShellxRadius.` 80 / 46, `ShellxShadows` 14 files, `ShellxMotion` 14 files, `TerminalColors.` 4 refs, all in `config/config_theme.dart:29-30,186,266` (the default terminal palette and the base for user themes; the file importing `terminal_colors.dart` is the only consumer outside the theme folder).
- The 5 `TextStyle(` outside theme: `ai/ai_markdown.dart:84`, `ai/ai_diff_view.dart:61`, `ai/ai_permission_bar.dart:288`, `ai/ai_theme.dart:23`, `config/font_probe.dart:23` (a font probe, not UI). The 12 `fontSize:` are mostly terminal-font plumbing; the visible ones are `ai_markdown.dart:85,127`, `ai_diff_view.dart:61`, `ai_theme.dart:25`.
- The 18 `fontWeight:` are all `w600` except `settings_overlay.dart:524` (w400/w600). Files: `terminal_overlays.dart:827`, `notifications_panel.dart:315,490`, `workspace_header.dart:122`, `command_palette.dart:560`, `pane_tree_view.dart:1266`, `attention_marks.dart:41`, `agent_badge.dart:71`, `agent_chip.dart:63`, `remote_strip.dart:230`, `resume_banner.dart:161`, ...
- Hot files by hard-coded style hits: `terminal_overlays.dart` 6, `notifications_panel.dart` 5, `ai_markdown.dart` 4, `workspace_header.dart` 3, `session_tab_row.dart` 3.
- Other colour sources not under app tokens: `atomOneDarkTheme` from `re_highlight` (code viewer), user terminal themes, `Colors.white` QR background (needed for QR contrast, `design/...desktop-ui.md:252`).

### 2.6 Blast radius, desktop

| Change | Where it lands | Cost |
|---|---|---|
| New dark palette (values only) | 2 files, 68 literals; tests pinning literals (section 4.2) | Low |
| New terminal default palette | `terminal_colors.dart` plus mobile's copy (identical values, desktop file says "copied verbatim from apps/mobile") | Low, but two copies; design doc follow-up #1 (a shared `packages/shellx_design`) was never done |
| UI font | `ThemeData(fontFamily:)` in `buildDesktopTheme`, fonts + licences in `pubspec.yaml`; check 220px sidebar widths, 30px rows, Vietnamese coverage; update `theme_test.dart:16-22,53-74` | Low to medium |
| Radii / sizes / spacing | `ShellxSizes/Space/Radius` consts are central, but numbers also sit in 139 literal `EdgeInsets`, `settings_overlay.dart:_NavItem`, and are asserted by 26 test files | Medium to high |
| Light mode | Every token is `static const`; needs instance/theme-extension tokens, 594 + 216 call sites in ~75 files, light variants of terminal chrome, window title bar, tray icons | High |
| Brand icons | `apps/desktop/macos/Runner/Assets.xcassets/AppIcon.appiconset/` (7 PNG sizes), `apps/desktop/windows/runner/resources/app_icon.ico`, `apps/desktop/assets/tray/*` (3 states x png/ico) | Asset work |
| New v2-3 surfaces (`ui/tools/*`) | Merge into `session_sidebar.dart` etc. | Land tokens before v2-3 merges |

## 3. Mobile app (`apps/mobile`)

### 3.1 Where theme things are defined

| Thing | Location |
|---|---|
| `AppColors` interface (39 getters: 23 inherited from the team base, many unused such as `mainGold`/`mediumRed`/`blueGrey`; 16 added for ShellX: `onPrimary`, `primarySoft`, `ok`/`okDot`, `warn`/`warnSoft`, `errorSoft`, `scrim`, `link`, `primaryFill`, `keyAccent`, `keyboard*`) | `apps/mobile/lib/core/design/app_colors.dart:5-82` |
| Light palette (also base class of dark) | `core/design/light_colors.dart:4-143` |
| Dark palette (extends Light; overrides) | `core/design/dark_colors.dart:5-100` |
| Terminal palette `TerminalColors` (dark in both themes; adds `muted`) | `core/design/terminal_colors.dart:5-67` |
| Typography (`AppTypography`: display56 down to metadata8, all with lining numerals; Raleway comes from `ThemeData`) | `core/design/typography.dart:3-203` |
| `DesignSystem` InheritedWidget and `context.colors` / `context.typo` | `core/design/design_system.dart:5-39` |
| `ThemeDataFactory.create(Brightness)`: `ColorScheme.fromSeed(...).copyWith(9 roles)`, filled/segmented/text button themes, progress, scaffold, divider, bottom-nav theme (unused), `AppBarTheme`, `fontFamily: Raleway`, Cupertino back-swipe transitions | `core/design/theme_data_factory.dart:6-92` |
| Wiring | `lib/main.dart:9-23` (`AdaptiveTheme` light/dark/initial), `features/app/app.dart:44-82` (`DesignSystem` + `MaterialApp.router`, `theme:` only; dark chosen by rebuilding with the other brightness), `features/app/splash_page.dart:96-118` |
| Design source | `docs/superpowers/design/2026-09-25-shellx-mobile-ui.html` (`--a-*`, `--t-*` tokens) |

Not set in `ThemeData` (so stock M3 tinted from the seed): `dialogTheme`, `bottomSheetTheme`, `switchTheme`, `sliderTheme`, `inputDecorationTheme`, `cardTheme`, `chipTheme`, `tooltipTheme`, `textTheme`. `ColorScheme.fromSeed` fills every role not overridden (surface containers, secondary, tertiary), so `showConfirmDialog` (`shared/src/confirm_dialog.dart:5`, plain `AlertDialog`), sliders and popup menus take seed-derived colours, not tokens.

### 3.2 Light and dark

- Supported: system, light, dark. Mode is stored by `adaptive_theme`; selector is a `SegmentedButton` in Settings (`settings_page.dart:309-334`, shown at `:238-240`). Brightness helper `core/extensions/adaptive_theme_mode_x.dart:5`.
- Terminal screens stay dark in both modes (`TerminalColors`, 53 refs / 4 files, 46 in `terminal_page.dart`). Extra-keys bar follows the system keyboard look (`keyboard*` roles).
- Contrast is engineered: light `primaryFill`/`link` are `#007785` (not `#0097A8`) for AA, with tests (section 4.3).
- Native launch screens are not themed by the Dart tokens. iOS `Base.lproj/LaunchScreen.storyboard:22` is a white background with a 168x185 `LaunchImage`; Android `drawable/launch_background.xml:4` is white and `drawable-v21/launch_background.xml:4` is `?android:colorBackground` (follows light/dark through `values/styles.xml` and `values-night/styles.xml`). Android adaptive-icon background is `#140F2A` (`values/ic_launcher_background.xml:3`), notification accent `#0097A8` (`values/colors.xml:4`).

### 3.3 Fonts

See the table in 2.3. Extra facts: `AppBarTheme` repeats `fontFamily: Raleway` (`theme_data_factory.dart:82`); 18 `FontFamily.jetBrainsMono` references outside `core/design` (terminal, AI items, link sheet, voice composer, QR card); `terminal_page_test.dart:1560-1561` asserts JetBrainsMono for the voice field and Raleway for its hint.

### 3.4 Reusable components

| Component | Where | Style source | Reuse |
|---|---|---|---|
| `AppButton` (54pt, radius 15, 45% opacity when disabled, loading state) | `shared/src/app_button.dart:16` | tokens | 23 uses / 14 files |
| `AppTextField` (52pt, radius 13), `PasswordTextField` | `shared/src/app_text_field.dart`, `features/auth/presentation/widgets/password_text_field.dart` | tokens | 3 uses |
| `NoticeBanner` (radius 13), `StatusCircle` (76px), `ShellxLogo` | `shared/src/*.dart` | tokens | 5 / 5 / 4 uses |
| `AppErrorWidget`, `StateView` | `shared/src/app_error_view.dart`, `state_view.dart` | tokens | a few |
| Confirm dialog | `shared/src/confirm_dialog.dart:5` | stock `AlertDialog` | 2 |
| Bottom sheets | 8 call sites: `session_picker.dart:70`, `view_as_text_sheet.dart:11`, `link_sheet.dart:8`, `terminal_page.dart:292`, `ai_history_sheet.dart:14`, `ai_config_sheet.dart:11`, `ai_attach_sheet.dart:6`, `ai_new_session_sheet.dart:9` | all repeat `backgroundColor: context.colors.surface`; 5 repeat the top radius 26; no `bottomSheetTheme` | ad hoc |
| Toasts | `core/handler/popup_handler.dart:60-117` (`toastification`) | hard-coded `Colors.white` card, black text, `Colors.blueAccent`/`yellowAccent`, `Colors.grey.shade800`; ignores dark mode | off-token |
| Page transition | `core/router/app_transparent_route.dart:15` (`Colors.black12`) | off-token | 1 |
| Lock screen over everything | `features/lock/presentation/lock_gate.dart` | tokens | 1 |
| Stock Material | `TextButton`/`FilledButton`/`OutlinedButton` 28 refs (includes the theme definitions), `IconButton` 18, `Slider` 2, `SegmentedButton` 3, `AppBar` 3, `Divider` 11 | `ThemeDataFactory` for buttons/AppBar only | |
| Team-base leftovers | `shared/src/{interface_pagination_view,sliver_pagination_view,load_more_retry_item}.dart` reference only each other (apparently unused, ~430 LOC, 10 raw style hits); ignore in estimates | | |

No `Card`, `Chip`, `Switch(` or `NavigationBar` anywhere in `lib/`.

### 3.5 Hard-coded and token usage (outside `core/design`)

| Directory (`apps/mobile/lib/...`) | LOC | hex `Color(0x)` | raw `Colors.*` | `TextStyle(` | `fontSize:` | literal radius |
|---|---|---|---|---|---|---|
| `features/ai/presentation` | 4,567 | 0 | 0 | 4 | 4 | 21 |
| `features/terminal/presentation` | 4,434 | 7 | 3 | 7 | 9 | 8 |
| `features/pairing/presentation` | 584 | 6 | 12 | 1 | 1 | 5 |
| `features/settings/presentation` | 975 | 0 | 1 | 4 | 2 | 3 |
| `features/machines/presentation` | 764 | 0 | 0 | 1 | 0 | 6 |
| `features/voice/presentation` | 727 | 1 | 0 | 1 | 1 | 2 |
| `core/handler` + `core/router` | - | 1 | 9 | 1 | 1 | 2 |
| `shared/src` | 1,385 | 0 | 2 | 2 | 2 | 8 |
| **Total outside design** | | **15** | **27** (20 non-transparent) | **21** | **20** | **55** |
| Inside `core/design` (7 files, 733 LOC) | | 95 (+1 `Color.fromARGB`) | 5 | 18 | 18 | 0 |

- Token usage: `context.colors.x` 58 direct + 288 through local `colors.x` aliases (40 files); `context.typo.*` 165 (31 files); `TerminalColors.*` 53 (4 files). Most used colour roles: `secondaryText` 105, `primaryText` 31, `divider` 24, `link` 23, `surface` 20.
- Other literals: `EdgeInsets` with numbers 145, `Icons.*` 99, `FontFamily.*` 18.
- The 15 hex literals: `popup_handler.dart:107`, `terminal_page.dart:888,905,1189`, `arrow_pad.dart:216`, `extra_keys_bar.dart:64,152`, `agent_reply_bar.dart:43`, `mic_button.dart:48`, `qr_scanner_page.dart:50,105,222,224,233,240`.
- Hot files by hard-coded hits: `pairing/.../qr_scanner_page.dart` 25, `terminal/.../terminal_page.dart` 15, `core/handler/popup_handler.dart` 13, `ai/.../ai_items.dart` 11, `ai/.../ai_dock.dart` 9, `settings_page.dart` 8, `machine_list_page.dart` 7.

### 3.6 Navigation shell and screens

- No bottom nav, drawer or tab bar anywhere (`bottomNavigationBarTheme` is set at `theme_data_factory.dart:66-72` but no widget uses it). One flat `auto_route` stack on the root navigator: `core/router/app_router.dart:7-32`. Guards: `UpdateGuard` (`core/router/update_guard.dart`), `AuthGuard` (`auth_guard.dart`).
- Launch: `main.dart` > `SplashPage`/`AppLaunch` (`features/app/splash_page.dart:35-118`, a temporary `MaterialApp`) > `RootApp` (`features/app/app.dart:12`) with `ToastificationWrapper`, `LockGate` in `MaterialApp.router(builder:)` (`app.dart:73`).

| Route (initial = Machine list) | File | LOC | What it is |
|---|---|---|---|
| `MachineListRoute` (initial) | `features/machines/presentation/pages/machine_list_page.dart` | 563 | Paired computers, online first, offline group, scan entry, first-run steps |
| `TerminalRoute` | `features/terminal/presentation/pages/terminal_page.dart` | 1,380 | Dark chrome bar, tab row, xterm, extra keys, voice, font sheet |
| `AiSessionRoute` | `features/ai/presentation/pages/ai_session_page.dart` | 755 | AI conversation + dock (plan, permission/question, queue, composer) |
| `AiItemRoute` | `.../ai_item_page.dart` | 208 | One AI item in full |
| `QrScannerRoute` | `features/pairing/presentation/pages/qr_scanner_page.dart` | 495 | Camera, framed target, failure sheet, success screen |
| `SettingsRoute` | `features/settings/presentation/pages/settings_page.dart` | 527 | Font size, biometric lock, notifications, paired computers, theme, terms, privacy, licences, account, version footer |
| `DeleteAccountRoute` | `.../delete_account_page.dart` | 133 | Re-enter password, red button |
| `LoginRoute`, `RegisterRoute` | `features/auth/presentation/pages/` | 138, 103 | Public, behind `UpdateGuard` |
| `UpdateRequiredRoute` | `features/app/update_required_page.dart` | 44 | Blocks an outdated app, opens the store |
| `SplashRoute` | `features/app/splash_page.dart` | 122 | `@RoutePage` but not in the router config |
| Overlays | `LockGate` (186), `ConnectionBanner` (`features/app/connection_banner.dart`, 90), sheets and dialogs above | | |

v2-4 (unmerged) adds a tool page (`features/tools/presentation/pages/tool_page.dart`) with a web engine, and edits `settings_page.dart`.

## 4. Tests a restyle would break

### 4.1 Golden and screenshot tests

- None. Zero `matchesGoldenFile`, no `alchemist`/`golden_toolkit`, no `.png`/`.golden` under any `test/`, no Maestro or `qa/` folder. `apps/desktop/test/ui/shortcut_golden_test.dart` is a frozen text fixture of the key-binding tables (`:7-14`).
- One pixel-based test: `apps/desktop/test/terminal/terminal_font_weight_test.dart:20-34` renders the terminal in `JetBrainsMono` vs `JetBrainsMonoLight` from `assets/fonts/*.ttf` and compares ink; it depends on those asset file names.
- `apps/desktop/integration_test/pty_test.dart` is a PTY smoke test, no screenshots. `packages/*/test` have no widget tests.
- Test volume for scale: desktop 327 files / 750 `testWidgets`; mobile 99 files / 567 `testWidgets`.

### 4.2 Desktop tests that assert colour, font or size

| File | What it pins |
|---|---|
| `apps/desktop/test/ui/theme_test.dart` | `:7-14` dark `ColorScheme`/scaffold; `:16-22` no `fontFamily` and not JetBrainsMono, body 13/18; `:24-35` literal hex of `bgTerminal`, `bgSidebar`, `accent`, `warnBg`, `scrim`, terminal selection, sidebar 220, window sizes; `:37-51` row fill luminance order and 1.25 contrast; `:53-74` dialog text styles carry the platform family, title 17; `:76-91` focus ring shapes; `:93-100` field padding |
| `apps/desktop/test/ui/app_dialogs_test.dart` | `:65` dialog width 400; `:436,466` divider and ring colours; 9 geometry assertions |
| Token-by-name colour asserts (survive value changes, break on renames) | `terminal_workspace_test.dart` (8), `agent_badge_ui_test.dart` (6, `:146-151`), `pane_tree_view_test.dart` (4, `:604-697`), `notifications_panel_test.dart` (3, `:660-680`), `sidebar_attention_test.dart` (2), `sidebar_workspaces_ui_test.dart` (2), `info_strip_test.dart` (2), `agent_chip_test.dart` (2, `:48-51`), `find_bar_test.dart` (1, `:77`), `attention_ring_test.dart` |
| Geometry (`getSize`/`getRect`/`size.*`): 161 refs in 26 files | `pane_tree_view_test.dart` 26, `sidebar_polish_test.dart` 20, `sidebar_attention_test.dart` 17, `terminal_workspace_test.dart` 14, `notifications_panel_test.dart` 12, `sidebar_workspaces_ui_test.dart` 10, `sidebar_rows_test.dart` 10, `app_dialogs_test.dart` 9, `ai/ai_permission_bar_test.dart` 9 |
| Token size asserts: `ShellxSizes.` 47 refs / 13 files | `pane_tree_view_test.dart` 12, `sidebar_polish_test.dart` 9, `sidebar_rows_test.dart` 5 |
| Terminal colour/font (not chrome) | `config/config_theme_test.dart`, `terminal/terminal_appearance_test.dart`, `terminal/terminal_style_test.dart`, `ui/settings_preview_test.dart:234-300` (sample font size/family), `terminal/terminal_font_weight_test.dart` |

### 4.3 Mobile tests that assert colour, font or size

| File | What it pins |
|---|---|
| `apps/mobile/test/core/design/design_tokens_test.dart` (150 lines) | tests start at `:11` exact light hex values; `:32` dark; `:51` terminal palette; `:59` group of WCAG contrast checks (11 pairs in both brightnesses, plus `:65` terminal muted text, `:95` light values); `:112` lining numerals and themed button colours; `:125` `AppButton` 54pt, radius 15, opacity 0.45, light fill `#007785` |
| `features/terminal/terminal_page_test.dart` | `:138` terminal background, `:784-816` status dot colours, `:454` 44x44 target, `:1560-1561` font families, `:1575-1577` voice link/error colours, 16 geometry asserts |
| Role-name colour asserts | `extra_keys_bar_test.dart:121-129`, `settings_page_test.dart:277-279`, `machine_list_page_test.dart:136`, `machine_list_a11_test.dart:149,163`, `ai/ai_entry_pages_test.dart:254-255`, `ai/ai_session_page_test.dart:1346-1349`, `shared/app_error_view_test.dart:31-34`, `agent_reply_bar_test.dart:158-165` |
| Geometry (63 refs / 11 files) | `ai_items_test.dart` (44-60px targets), `ai_timeline_test.dart`, `extra_keys_bar_test.dart`, `machine_list_page_test.dart`, `ai_dock_test.dart`, `settings_page_test.dart:268` |

Contrast tests in `design_tokens_test.dart` double as a safety net for a new palette; they will fail on the old values, so update them rather than delete them.

### 4.4 Tests that pin the name

| File | Pins |
|---|---|
| `apps/mobile/test/platform_config_test.dart` | `:28` iOS `CFBundleDisplayName` = `ShellX`; `:41,111` vi permission strings begin "ShellX dùng ..."; `:17-24` bundle id `com.shellx.prod`; `:168-169` `applicationId`/`namespace`; `:179` `android:label="ShellX"`; `:206-207` channel strings |
| `apps/mobile/test/app_test.dart:622-667`, `features/lock/lock_gate_test.dart`, `app_lock_controller_test.dart:78-83`, `features/settings/settings_page_test.dart:172,277,557` ("ShellX 1.0.0 (1)"), `features/auth/login_page_test.dart:63-64`, `l10n_test.dart:44-164` | UI strings containing "ShellX" |
| `release/tests/inno.test.mjs` | `:11-12` `OutputBaseFilename=ShellX-Setup-{#AppVersion}`; `:22-23` `AppExeName "ShellX.exe"`; `:36-37` `AppId`; `:42,120,126` taskkill by `{#AppExeName}`; `:46,79` `{userappdata}\pro.shellx\ShellX`; `:54-66,93-127` `%LOCALAPPDATA%\ShellX\{bin,term,restore,cli,mux}`; `:60` `Run\ShellX` |
| `release/tests/{announce,version,resolve-version,macos-scripts,build-installer}.test.mjs`, `web/tests/site.test.mjs:12-13`, `relay/test/*.ts` | installer file names `ShellX-<v>.dmg`, `ShellX-Setup-<v>.exe`; `ShellX.app`, `Contents/MacOS/ShellX` fixtures |
| `term/tests/*.rs` | `Library/Application Support/ShellX/...`, `ShellX\bin` |
| `apps/desktop/test/mux/mux_paths_test.dart:19-23` | `pro.shellx.desktop/mux` |

## 5. Every place the app name appears

Legend: "display" = free text, safe to localise; "identity" = a path, id, process or file name that code or tools look up.

### 5.1 iOS (`apps/mobile/ios`)

| Place | Value | Controls | Kind |
|---|---|---|---|
| `Runner/Info.plist:9-10` `CFBundleDisplayName` | `ShellX` | Home-screen label, Settings > Apps | display |
| `Runner/Info.plist:22-23` `CFBundleName` | `shellx_mobile` | Internal short name | display (not ShellX today) |
| `Runner/Info.plist:38-47` five `NS*UsageDescription` | each starts "ShellX uses ..." | Permission prompts (camera, Face ID, mic, photos, speech) | display |
| `Runner/en.lproj/InfoPlist.strings:2-6`, `Runner/vi.lproj/InfoPlist.strings:2-6` | same five prompts, en and vi | Localised prompts. They do **not** localise `CFBundleDisplayName`; a per-language app name would need `"CFBundleDisplayName" = "..."` lines added here | display |
| `Runner/{en,vi}.lproj/Localizable.strings` | push action buttons only | no name | - |
| `Runner.xcodeproj/project.pbxproj` `PRODUCT_BUNDLE_IDENTIFIER` | `com.shellx.prod` (+ `.RunnerTests`); `PRODUCT_NAME = $(TARGET_NAME)` | Bundle id for App Store, push, Firebase | identity |
| `Runner/GoogleService-Info.plist` | Firebase project `shellxpro`, bundle `com.shellx.prod` | Push | identity |
| `Runner/Base.lproj/LaunchScreen.storyboard` | image only, white background | no name | - |
| Store name | App Store Connect > ShellX (build 1 uploaded, `main@6ba1f0a` `e3802e3`) | Edited in the console, not in the repo; no fastlane/metadata folder exists | outside repo |

### 5.2 Android (`apps/mobile/android`)

| Place | Value | Controls | Kind |
|---|---|---|---|
| `app/src/main/AndroidManifest.xml:16` `android:label` | literal `ShellX` (no `@string/app_name`) | Launcher label, Settings > Apps, notification header | display |
| `app/src/main/res/values/strings.xml:4-6`, `values-vi/strings.xml:3-4` | channel id `shellx_notifications`, channel name/description (no app name) | Notification channel | id |
| `app/build.gradle.kts:12,28` | `namespace`/`applicationId = com.shellx.prod`; Kotlin package `com/shellx/prod/MainActivity.kt` | Play listing id | identity |
| `app/google-services.json` | package `com.shellx.prod` | Firebase | identity |
| Recents/task label | `MaterialApp.onGenerateTitle` > ARB `appTitle` (`features/app/app.dart:57`) | Android recents | display |
| `release/mobile/android.sh` (`main@6ba1f0a`) | output file `ShellX-com.shellx.prod-<version>.aab`; refuses wrong signing key | file name only | filename |
| Store name | Play Console > ShellX (edited there) | | outside repo |

### 5.3 macOS (`apps/desktop/macos`)

| Place | Value | Controls | Kind |
|---|---|---|---|
| `Runner/Configs/AppInfo.xcconfig:8` `PRODUCT_NAME` | `ShellX` | `ShellX.app`, executable `Contents/MacOS/ShellX` (`CFBundleExecutable=$(EXECUTABLE_NAME)`), `CFBundleName`, About panel title, menu-bar app name, Finder name. This xcconfig is the Runner target's base config (`project.pbxproj:590,722,742`) | **identity** |
| `AppInfo.xcconfig:11` `PRODUCT_BUNDLE_IDENTIFIER` | `pro.shellx.desktop` | Keychain service/account (`lib/src/platform/secure_key_value_store.dart:12-25`), `NSUserDefaults`, app-support folder `~/Library/Application Support/pro.shellx.desktop` (`lib/src/mux/mux_paths.dart:5`), login-item label (`macos/Runner/MainFlutterWindow.swift:37`), CI check `release-desktop.yml:165-169` | **identity, do not change** |
| `AppInfo.xcconfig:14` | `PRODUCT_COPYRIGHT = Copyright (c) 2026 pro.shellx` | About panel | display |
| `Runner/Info.plist:15-16` | `CFBundleName = $(PRODUCT_NAME)`; **no `CFBundleDisplayName`**, no `InfoPlist.strings`, no localisations besides `Base.lproj` | | |
| `Runner/Base.lproj/MainMenu.xib:25-61` | `APP_NAME` placeholders ("About/Hide/Quit APP_NAME"), same as Flutter's stock template | App menu labels. How AppKit fills them was not verified here | display |
| `Runner.xcodeproj/project.pbxproj:69,147,253,505,520,535`, `xcschemes/Runner.xcscheme:18,34,69,86` | `shellx_desktop.app` (stale labels from the project name; the real product is `ShellX.app`) | Xcode scheme and `TEST_HOST` only | stale |
| `Runner/MainFlutterWindow.swift:84` | macOS 12 LaunchAgent plist stores `Bundle.main.executablePath` | A renamed executable leaves a dangling login item on macOS 12 (13+ uses `SMAppService`, bundle based) | path |
| `Runner/Info.plist:25-26` `LSUIElement` | true | no name | - |

### 5.4 Windows (`apps/desktop/windows`)

| Place | Value | Controls | Kind |
|---|---|---|---|
| `CMakeLists.txt:3` | `project(shellx_desktop)` | CMake project | internal |
| `CMakeLists.txt:7` `BINARY_NAME` | `ShellX` | `ShellX.exe`; also `add_dependencies(${BINARY_NAME} shellx_term)` (`:73`), install rules; `runner/CMakeLists.txt:4-9` says change it only here | **identity** |
| `runner/Runner.rc:92-98` | `CompanyName "pro.shellx"`, `FileDescription "ShellX"`, `InternalName "ShellX"`, `OriginalFilename "ShellX.exe"`, `ProductName "ShellX"` | Task Manager / file properties text, **and** `path_provider`'s folder `%APPDATA%\<CompanyName>\<ProductName>` (verified in `path_provider_windows-2.3.0/lib/src/path_provider_windows_real.dart:180-246`, which also replaces `< > : " / \ | ? *` with `_`) | `ProductName`/`CompanyName` are **identity**, `FileDescription` display |
| `runner/main.cpp:39` | `window.Create(L"ShellX", ...)` | Initial window title (Dart's `windowManager.setTitle` takes over, `lib/src/ui/window_host.dart:187`) | display |
| `runner/flutter_window.cpp:57,67` | channel names `pro.shellx.desktop/taskbar`, `/app` | no user text | identity |
| `release/windows/shellx.iss` (`origin/main`) | see 6.2 | installer | |
| Dart code that embeds the exe name | `lib/src/mux/windows_runtime_copy.dart:136,146` (daemon is a copy of `ShellX.exe` made as `shellx-mux.exe`; throws if `ShellX.exe` is absent), `lib/daemon_main.dart:58` (`endsWith('shellx-mux.exe')`) | Background service on Windows | **identity** |

Where the Windows app-data folder is used: `getApplicationSupportDirectory()` at `lib/main.dart:137` and `lib/daemon_main.dart:83` holds `shellx.lock`, `activate.signal`, `quit.signal` (`lib/src/platform/single_instance.dart:10-15`), the DPAPI file of `flutter_secure_storage` (device key, access token, trusted phones) and `shared_preferences`. The installer writes `quit.signal` into `%APPDATA%\pro.shellx\ShellX\` (`shellx.iss:146`) and deletes that folder on uninstall (`:91`).

### 5.5 Names compiled into desktop Dart code and plugins

| Place | Value | Controls |
|---|---|---|
| `lib/src/platform/notifier.dart:29` `localNotifier.setup(appName: 'ShellX')` | Windows: `SetCurrentProcessExplicitAppUserModelID("ShellX")` and a Start-menu shortcut `...\Programs\ShellX.lnk` (verified in `local_notifier-0.1.6/windows/local_notifier_plugin.cpp:153-154` and `wintoastlib.cpp:36-37,227-234,507`) | Toast identity, taskbar grouping, notification settings. A colon makes an invalid `.lnk` path |
| `lib/src/platform/launch_at_login.dart:17` `appName: 'ShellX'` | Windows `HKCU\...\Run` value `ShellX` and `StartupApproved` value (`launch_at_startup-0.5.1/lib/src/app_auto_launcher_impl_windows.dart:43-77`); the installer removes that value (`shellx.iss:204`). macOS uses the bundle id label instead | Start at login |
| `lib/main.dart:798` notification title, `:818` Windows `MessageBox` title; `lib/src/tray/tray_actions.dart:213` | `'ShellX'` | Startup-error and tray notices |
| `lib/src/ui/window_host.dart:19,187`; `lib/src/ui/terminal/terminal_pane.dart:316` | `'ShellX'` / `"{tab} — ShellX"` | Window title |
| `lib/src/terminal_sharing/sharing_paths.dart:25,51`; `shell_blocks.dart:8-9,14-25,102-116,297-305`; `config_text.dart:5-6`; `term/shell/block.{zsh,bash,ps1}`; `term/src/*` | `~/Library/Application Support/ShellX/bin/shellx-term`, `%LOCALAPPDATA%\ShellX\bin\shellx-term.exe`, markers `# >>> ShellX >>>` / `# <<< ShellX <<<` written into users' `.zshrc`/`.bashrc`/PowerShell profiles; backups `*.shellx-backup` | Terminal sharing and its uninstall. Existing users already have these blocks on disk |
| `lib/src/mux/mux_paths.dart:19`, `lib/src/restore/restore_paths.dart:13`, `lib/src/ai/ai_paths.dart:22`, `lib/src/config/config_paths.dart:71` | `%LOCALAPPDATA%\ShellX\{mux,restore}`, `%APPDATA%\ShellX\config`; POSIX `~/.config/shellx/config` | State, restore, config files |
| Log-only prefixes | 146 lines like `debugPrint('ShellX: ...')` | Not user-visible |
| `shellx://pair?...` | `packages/shellx_core/lib/src/pairing/pairing_uri.dart:28` | Pairing QR/URI scheme (lower case identifier) |
| `shellx` CLI, `shellx-term`, `shellx-mux`, `agent-skills/shellx*` | lower-case identifiers | Command line, helper binary, docs |
| Built-in terminal theme | `ThemeEntry('ShellX','')` (`config/theme_listing.dart:18`) | Name of the default palette in config and Settings |

### 5.6 `MaterialApp` titles, ARB strings, About-like screens

| Place | Detail |
|---|---|
| Desktop `MaterialApp` title | `app.dart:20` `onGenerateTitle` > ARB `appTitle` = `ShellX` |
| Mobile `MaterialApp.router` title | `features/app/app.dart:57` > ARB `appTitle` |
| Desktop ARB | `apps/desktop/lib/l10n/app_en.arb` 66 lines contain "ShellX" (`appTitle:3`, `windowTitle:47` "{title} — ShellX", `trayTooltip:50`, sign-in/out, quit, update, pairing, tour, onboarding, errors); `app_vi.arb` 65 lines. Generated and committed: `app_localizations_en.dart` / `_vi.dart` (66 each) |
| Mobile ARB | `apps/mobile/lib/l10n/intl_en.arb` 24 lines (`appTitle:48`, `lockTitle:133` "ShellX is locked", `lockReason:135`, `settingsVersion:378` "ShellX {version} ({build})", `emptyStep1/3`, `scannerCardBody:240`, AI strings); `intl_vi.arb` 22. Generated and committed: `shared/src/l10n.dart` (48), `shared/src/intl/messages_{en,vi}.dart` (24, 22). Regenerate with `intl_utils` (mobile) and `flutter gen-l10n` (desktop) |
| About-like UI | Desktop: no About screen; Settings > General shows `Version {version}` (`ui/settings/pages/general_page.dart:52`), macOS standard About panel from the bundle (`orderFrontStandardAboutPanel`, `MainMenu.xib:29-34`). Mobile: Settings footer "ShellX {version} ({build})" (`settings_page.dart:68`) and `showLicensePage(applicationName: appTitle)` (`:46-48`); `ShellxLogo` semantics label (`shared/src/shellx_logo.dart:14`) |
| In-app copy | Most strings use the word mid-sentence ("Sign in to ShellX", "Quit ShellX?", "Open ShellX on the computer"), so the long form does not substitute cleanly |
| `apps/desktop/assets/whats_new.json` | No "ShellX" text (uses `shellx` CLI commands) |
| Package descriptions | `apps/desktop/pubspec.yaml:2`, `apps/mobile/pubspec.yaml:2` |

## 6. Release pipeline and what depends on the name

### 6.1 `release-desktop.yml` (`origin/main`, unchanged in `6ba1f0a`)

| Lines | Step | Name dependency |
|---|---|---|
| `:36` | `DOWNLOAD_BASE_URL: https://download.shellx.pro` | domain |
| `:39-40` | Apple ID and team `W4RF3W4VTZ` | signing identity (not the app name) |
| `:155-157` | `flutter build macos --release` | `PRODUCT_NAME` decides the output folder |
| `:158-185` | "Check the built app (ShellX.app, bundle id pro.shellx.desktop)": path `apps/desktop/build/macos/Build/Products/Release/ShellX.app` (`:160`), bundle id (`:165-169`), `Contents/Helpers/shellx-term` universal (`:170-179`), `CFBundleShortVersionString == pubspec` (`:180-184`) | **`ShellX.app`**, bundle id |
| `:195-199` | `sign-app.sh "$APP" ...Release.entitlements`, `check-team.sh` | none on the name |
| `:207-213` | `notarize.sh "$APP"` (zips as `<basename>.zip`) | none |
| `:214-225` | `make-dmg.sh "$APP" "dist/ShellX-$VERSION.dmg"`, sign + notarize dmg | **`ShellX-<v>.dmg`** |
| `:226-230` | artifact `dist/ShellX-${{ env.VERSION }}.dmg` | file name |
| `:266-275` | `flutter build windows`; require `...\Release\ShellX.exe` and `shellx-term.exe` | **`ShellX.exe`** |
| `:276-288` | Azure signing of `exe,dll` in the folder | none |
| `:311-316` | `build-installer.ps1 ...`; `SETUP_EXE=dist/ShellX-Setup-$VERSION.exe` | **`ShellX-Setup-<v>.exe`** |
| `:328-335` | verify Authenticode of installer, `ShellX.exe`, `shellx-term.exe` | **`ShellX.exe`** |
| `:339-345` | unsigned-release note and artifact | file name |
| `:373-385` | refuse to overwrite: `ShellX-$VERSION.dmg`, `ShellX-Setup-$VERSION.exe` at `$DOWNLOAD_BASE_URL/desktop/$VERSION/$name` | file names |
| `:420-445` | rsync into `$APP_DIR/downloads/desktop/$VERSION/` (`APP_DIR` default `phu/shellx`), verify public URLs and sizes | file names, path |
| `:476-507` | `announce.mjs`, commit message `chore(release): desktop $VERSION is live ...`, tag `desktop-v$VERSION` | tag name |
| `:509-521` | calls `deploy.yml` (images `ghcr.io/lephus/shellx-relay`, `shellx-web`) | not the app name |

### 6.2 Packaging files

| File | Name dependencies |
|---|---|
| `origin/main:release/macos/make-dmg.sh:12,16` | `ditto "$app" "$staging/ShellX.app"` (the app is **renamed to `ShellX.app` inside the dmg regardless of the input name**); `hdiutil create -volname ShellX` (mounted volume name) |
| `release/macos/sign-app.sh`, `notarize.sh`, `check-team.sh`, `import-certificate.sh` | take paths as arguments; only comments say `ShellX.app`; nested `Contents/Helpers/shellx-term` signing (`sign-app.sh:33-37`) |
| `release/windows/shellx.iss` | `:14` `AppExeName "ShellX.exe"`; `:20-21` `AppId={{6A3A45BD-0A27-407A-A1FF-3C8D1BE226EE}` ("Never change it"); `:22` `AppName=ShellX`; `:24` `AppVerName`; `:25` `AppPublisher=ShellX`; `:30-31` `DefaultDirName={autopf}\ShellX`, `DefaultGroupName=ShellX`; `:40` `OutputBaseFilename=ShellX-Setup-{#AppVersion}`; `:44-45` `UninstallDisplayName=ShellX`; `:70-71` Start-menu and desktop shortcuts `ShellX`; `:74` `LaunchProgram,ShellX`; `:79-80` `taskkill` `shellx-mux.exe` and `{#AppExeName}`; `:84` `ShellX.exe --terminal-sharing-cleanup`; `:91` delete `{userappdata}\pro.shellx\ShellX`; `:94-103` delete `{localappdata}\ShellX\{bin,term,restore,cli,mux}`; `:111-119` `tasklist` for `{#AppExeName}`; `:146` `quit.signal` path; `:155` `taskkill`; `:172` user Path entry `...\ShellX\cli`; `:202-205` remove `Run\ShellX`. Upgrade detection is `AppId`; `UsePreviousAppDir` is the Inno default, so an upgrade reuses the old folder |
| `release/windows/build-installer.ps1:12,20,43,57` | requires `ShellX.exe` in `SourceDir`; output `ShellX-Setup-$Version.exe` |
| `release/scripts/version.mjs:38-43` | **single source of the installer file names** (`ShellX-${version}.dmg`, `ShellX-Setup-${version}.exe`), used by `resolve-version.mjs:45` (HEAD probes decide build/skip) and `announce.mjs:22` (writes `MAC_URL`/`WIN_URL`) |
| `release/scripts/announce.mjs:9-11` | edits `deploy/relay.env` and `web/src/site.config.json` |
| `deploy/relay.env:6-7` | `MAC_URL`, `WIN_URL` = the two 1.0.0 file URLs; served by relay `GET /v1/version` (`relay/src/app.ts:66-71`) |
| `deploy/web/nginx.conf:44-62` | serves `/srv/downloads` at `download.shellx.pro`, `Content-Disposition: attachment`, `immutable` one-year cache; no name dependency except the folder layout `desktop/<version>/` |
| `.github/workflows/windows-check.yml:82,106-114` | requires `ShellX.exe` and `shellx-term.exe` |
| `release/README.md:125` | states the contract: "`ShellX.app` with bundle id `pro.shellx.desktop`, and `ShellX.exe`" |
| `main@6ba1f0a:release/mobile/{ios.sh,android.sh,ExportOptions.plist,README.md}` | check team `W4RF3W4VTZ`, bundle `com.shellx.prod`, version, `aps-environment`; `.aab` file name; text mentions "App Store Connect > ShellX", "Play Console > ShellX" |

### 6.3 What a rename to "ShellX: Remote AI agents" could break

Assuming the long name is applied to a field, by field:

| If the long name goes into ... | Effect |
|---|---|
| Windows `Runner.rc` `ProductName` | Illegal `:` becomes `_`: app data moves to `%APPDATA%\pro.shellx\ShellX_ Remote AI agents` (derived from `path_provider_windows` source). Existing 1.0.0 users lose device key, access token, trusted phones and settings on upgrade (must sign in and re-pair); the installer's `quit.signal` (`shellx.iss:146`) and `[UninstallDelete]` (`:91`) point at the old folder, so graceful quit falls back to `taskkill /F`; single-instance and activation files split between versions; `release/tests/inno.test.mjs:46,79` fail |
| Windows `BINARY_NAME` | A `:` cannot be in a file name. Any other new exe name breaks `windows_runtime_copy.dart:136-146` (background service cannot start), the workflow checks (`:269-275`, `:331`), `windows-check.yml:106-110`, `build-installer.ps1:12`, Inno `AppExeName` and all taskkill/tasklist/cleanup lines, `inno.test.mjs`. The HKCU `Run` value stores the exe path and would dangle |
| Windows `FileDescription` | Safe (display only; shown in Task Manager and file properties) |
| Inno `AppName`, `AppVerName`, `UninstallDisplayName`, `DefaultGroupName`, Start-menu / desktop shortcut names (`shellx.iss:22-31,44,70-71,74`) | Display strings. Upgrade detection and uninstall key on `AppId` (`:20-21`), so they can change without creating a second install. Per Inno's normal behaviour (not tested here) an upgrade does not delete a differently named old shortcut, and `DefaultDirName` only matters for fresh installs because an upgrade reuses the previous folder. `local_notifier` also creates `ShellX.lnk` in the same Start-menu folder, so the two shortcut names should stay in step |
| macOS dmg volume name (`make-dmg.sh:16`, `-volname ShellX`) | Display only |
| macOS `PRODUCT_NAME` | `:` is the legacy path separator (Finder shows it as `/`). A renamed `.app` also changes `Contents/MacOS/<name>`; the workflow check at `release-desktop.yml:160-164` fails first (it expects `.../Release/ShellX.app`), and `make-dmg.sh:12` would still force `ShellX.app` inside the dmg. If the check and the script were both changed, users dragging a differently named app to `/Applications` would end up with two apps sharing bundle id `pro.shellx.desktop` (the documented update flow is "replace `ShellX.app`", `docs/superpowers/HANDOFF.md:469,482`). macOS 12 LaunchAgents point at the old executable path. Notarization and signing are unaffected (they depend on identity/team, not the name) |
| macOS `PRODUCT_BUNDLE_IDENTIFIER` | Do not touch: Keychain service/account, `UserDefaults`, app-support folder, login item label, TCC grants and the Developer ID designated requirement all key on it |
| macOS `CFBundleDisplayName` (new key) | Possible way to show a different Finder/Launchpad name without renaming the bundle; a `:` in a display name is unusual on macOS; not tested here |
| `local_notifier` / `launch_at_startup` `appName` | `:` breaks the toast shortcut file name; any other change creates a second Start-menu shortcut, a new AUMID (pinned items, notification permissions) and an orphaned `Run` value that `shellx.iss:204` no longer removes |
| `Info.plist` `CFBundleDisplayName` (iOS) / `android:label` | Safe technically; the string is truncated on home screens (about 10-13 characters on iOS and most Android launchers; platform behaviour, not from the repo). `platform_config_test.dart:28,179` must be updated. Per-language names need `CFBundleDisplayName` in `en.lproj`/`vi.lproj/InfoPlist.strings` and a new `@string/app_name` with `values-vi` |
| App Store Connect / Play Console name | Outside the repo; records already exist. 24 characters fits the 30-character limits (platform rules, not from the repo). The release scripts check bundle id/team/version only |
| ARB `appTitle` / `windowTitle` / `trayTooltip` | Safe; used as titles, sentence subjects ("Sign in to ShellX") and macOS/Windows UI. Needs ARB edits in both apps in en and vi and regenerated Dart (committed). `windowTitleFor` (`window_host.dart:19`) and `window_host.dart:187` are hard-coded `'ShellX'` |
| Installer / dmg file names | Only breaks if these change. `version.mjs:38-43` is the one place that defines them, but they are repeated in the workflow (8 places), `make-dmg.sh`, `shellx.iss:40`, `build-installer.ps1`, `deploy/relay.env`, `relay/dev.env`, `web/src/lib/site.ts:13,17`, tests and READMEs. The published 1.0.0 files and the relay env keep the old names; `resolve-version.mjs` would see a new name as unpublished and `publish` would upload it next to the old one under the same version folder, so bump the version |
| Shell-profile markers, `Application Support/ShellX`, `%LOCALAPPDATA%\ShellX`, `shellx://`, `shellx`/`shellx-term` | Do not rename: on disk in users' profiles, in Rust tests, in the uninstaller |
| Domain `shellx.pro` | If the brand also changes the domain, `update_check.dart:62-71` trusts only `https://shellx.pro` and subdomains; old clients would refuse a new host |
| Auto-updater | None exists, so nothing there depends on the name |
| Signing and notarization | Identity is team `W4RF3W4VTZ` and the certificate, not the product name; `check-team.sh`/`notarize.sh` take paths |

Suggested split (a recommendation, not something I verified in a build): keep `ShellX` as the short name in every identity field and in sentence-style strings; put the long form only into store listings, website and, if wanted, an iOS/Android display name or a new About line.

### 6.4 Mentions in `web/**` and `relay/**` (list only)

- `web/src/i18n/ui.ts` (48 lines), guide pages `web/src/pages/{guides,en/guides}/*.md` (ssh-from-phone, claude-code-on-phone, shellx-vs-termius, shellx-vs-tailscale, remote-terminal-without-vpn), `privacy.md`, `terms.md` (vi + en), `src/lib/llms.ts`, `src/lib/seo.ts:18`, `src/layouts/Base.astro:46-55,108` (meta application-name, og:site_name, footer), `Legal.astro:29`, `Guide.astro:27`, `404.astro:12`, `components/Home.astro:33-74` (JSON-LD names, `alternateName: ['ShellX Terminal', 'shellx.pro']`), `public/site.webmanifest` (`name`, `short_name`), `src/lib/site.ts:5-17` (installer URLs), `src/site.config.json` (`desktopVersion`, `appStoreUrl: null`, `googlePlayUrl: null`), `tests/site.test.mjs:12-13`, `tests/placeholders.test.mjs`, `Dockerfile:2`, `README.md:54-55`, `package.json` name `shellx-web`. FAQ answers in `ui.ts:86-87,218-219` quote `ShellX.app` and `~/Library/Application Support/ShellX/bin/shellx-term uninstall`.
- `relay/`: `README.md:1`, `Dockerfile:2`, `migrations/0001_init.sql:1`, `dev.env:10-11` (download URLs), `test/{app,config,helpers,server}.test.ts` (same URLs), `src/app.ts:66-71` (`/v1/version`). Relay env: `deploy/relay.env`.

## 7. Caveats and not verified

- Nothing was built or run. The macOS `APP_NAME` menu rendering, TCC/Keychain behaviour on a product-name change, and Finder handling of `:` are inferences from platform behaviour, not tested.
- The Windows app-data folder derivation, `local_notifier` AUMID/shortcut behaviour and `launch_at_startup` registry names were verified by reading the plugin sources in `~/.pub-cache/hosted/pub.dev` (versions in `pubspec.lock`).
- Counts are regex counts (`EdgeInsets` with literal numbers and `Icons.*` are approximate). Mobile `core/design` hex counts include the dark and light files.
- The local `origin/main` ref is behind the remote; I used `6ba1f0a` for mobile release files and confirmed the desktop pipeline files are identical.
- `v2-3` and `v2-4` were only inspected by file list, not read.
