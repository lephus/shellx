# Task 7 report: ShellX palette, dark-only, terminal defaults, Space Grotesk

Lane L2, branch `shellx/l2-look`. Status: DONE_WITH_CONCERNS (no app build allowed; see Concerns).

## Changes per file

### ShellXBrand (new pure pieces, `swift test`-able)
- `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXAppearance.swift` (new): `forcedAppearanceName: NSAppearance.Name = .darkAqua`, `forcedModeRawValue = "dark"`, `forcedAppearance`.
- `.../ShellXStatus.swift` (new): `needsYou/running/done/error/idle` -> `primary/running/done/error/muted` (spec §7.4 status table).
- `.../ShellXTerminalTheme.swift` (new): built-in terminal theme (bg/fg/cursor/cursor-text/selection + 16 ANSI as `ShellXColor`, comment table) and `ghosttyConfigContents` (Ghostty theme-file format). `name = "ShellX"`.
- `.../ShellXFonts.swift` (new): `ShellXFonts.display(size:weight: = .bold) -> Font` ("Space Grotesk", system fallback when the family is not registered), `familyName`.
- `Tests/ShellXBrandTests/ShellXThemeTokensTests.swift` (new): 9 tests (appearance, status colors, theme values, 16 ANSI, contrast floors, config contents, font fallback/custom, bundled TTF registers under "Space Grotesk").

### Accent (CmuxFoundation)
- `Packages/macOS/CmuxFoundation/Package.swift`: path dependency `../../Shared/ShellXBrand`.
- `.../Color/CmuxAccentColor.swift`: `cmuxBlue(isDark:)` (the built-in "ShellX Blue" mode and the custom fallback) = `ShellXPalette.primary` in both schemes.
- `.../ConfigValidation/CmuxConfigSchema.generated.swift`: `sidebarAppearance.tintColor` default `#100B1D`, `tintOpacity` default `1.0` (keeps the schema's documented defaults equal to the catalog).
- `Tests/CmuxFoundationTests/CmuxAccentColorTests.swift`: expectations -> `[96,165,250]` / `#60A5FA`.

### Sidebar tint (CmuxAppKitSupportUI + CmuxSettings)
- `Packages/macOS/CmuxAppKitSupportUI/Package.swift`, `Packages/macOS/CmuxSettings/Package.swift`: ShellXBrand path dependency.
- `.../WindowChrome/Sidebar/WindowChromeSidebarTintDefaults.swift`: default hex `ShellXPalette.panel` (`#100B1D`, new `shellXPanelHex`), opacity `1.0`.
- `.../WindowChrome/Sidebar/WindowChromeSidebarPresetOption.swift`: `.nativeSidebar` (default preset) tint = panel @ 1.0. Needed because `cmuxApp.migrateSidebarAppearanceDefaultsIfNeeded` writes the native preset's tint into defaults on a fresh install, which would otherwise overwrite the new default with `#000000`/0.18.
- `Packages/macOS/CmuxSettings/.../Keys/SidebarAppearanceCatalogSection.swift`: catalog `tintColor` / `tintOpacity` defaults mirror the above.

### Terminal default theme (CmuxTerminalCore)
- `Packages/macOS/CmuxTerminalCore/Package.swift`: ShellXBrand dependency.
- `.../Config/GhosttyConfig.swift`: `cmuxDefaultLightThemeName = cmuxDefaultDarkThemeName = "ShellX"`; the built-in fallback contents (used when no theme file of that name exists, i.e. always on a normal install) = `ShellXTerminalTheme.ghosttyConfigContents` for both schemes. The decision rule (`UserAppearanceConfigSummary.shouldApplyDefaultAppearance = !hasThemeDirective && !hasExplicitTerminalColorDirective`, gated by `terminal.adaptiveDefaultTheme`) is untouched.
- Tests: `GhosttyConfigManagedDefaultAppearanceTests.swift` (light/dark test -> one theme for both; new `builtInManagedDefaultIsTheShellXTheme`, `userGhosttyColorsWinOverTheShellXDefault`, `nonColorSettingsKeepTheShellXDefault`), `GhosttyConfigAdaptiveAppearanceRegressionTests.swift` and `GhosttyConfigThemeParityTests.swift` (no-config scenarios now expect the one ShellX palette for both appearances).

### Dark-only (app)
- `Sources/AppearanceSettings.swift`: live environment's `setApplicationAppearance` always sets `ShellXAppearance.forcedAppearance` and the terminal sync passes it; new `AppearanceSettings.enforceShellXDarkOnly(defaults:)` pins `appearanceMode = "dark"`; the live `AppearanceSettingsUserDefaultsObserver` environment enforces + applies dark whatever was stored.
- `Sources/cmuxApp.swift`: `enforceShellXDarkOnly()` right before the launch `resolvedMode()`/`applyAppearance(duringLaunch:)` (the earliest existing appearance handling, in `cmuxApp.init`, before AppDelegate's didFinishLaunching); `applyAppearance()` (AppStorage onChange) applies/pins dark.
- `Packages/macOS/CmuxSettingsUI/.../Sections/ThemesSection.swift`: Appearance (light/dark/system) `ThemePickerRow` removed from the Themes card.
- `.../Navigation/CuratedSettingEntry+Default.swift`, `Sources/SettingsSearchIndex.swift`, `Sources/SettingsSearchAliases.swift`: the "Appearance" search entry/anchor/alias removed; `Tests/CmuxSettingsUITests/SettingsRowAnchorResolutionTests.swift` drops `setting:themes:appearance`.

### Sidebar look (app)
- `Sources/Sidebar/SidebarAppearanceSupport.swift`: default (non-subtle, left-rail) selection in a dark sidebar = `raise` (#171128); solid-fill style and light sidebars keep the accent; `sidebarIsShellXSelectionFill(_:)`; names on the raise selection draw `textHi`. Badge: unchanged code, its fallback is the accent, whose default is now `primary`.
- `Sources/Sidebar/AppKitList/Cells/SidebarWorkspaceRowSupportViews.swift` (`SidebarRowPalette`): dark sidebar titles `textHi`, metadata `muted` (through the existing contrast-floor helper), `usesShellXSelection`.
- `Sources/Sidebar/SidebarCompactStatusGlyph.swift`: `color()` maps through `ShellXStatus`: error=`error`, needsInput=`primary`, running/subagents/pending=`running`, unseen=`done`, all others (waiting, idle, branch, terminal, every PR state)=`muted`; `needsInputColor` = primary.
- `Sources/Sidebar/AppKitList/Cells/SidebarWorkspaceRowCellView.swift`: the glyph is not flattened on the ShellX raise selection (status colors stay visible on the selected row).

### Attention ring (app)
- `Sources/Panels/Panel.swift`: `WorkspaceAttentionFlashAccent.strokeColor` = accent at `primaryLine` alpha 0.45 (exactly `primaryLine` with the default accent); notification + flash ring glow opacity/radius 0; `PanelOverlayRingMetrics.lineWidth = 1`. The GhosttyTerminalView notification ring (~10967) reads these, so it becomes 1 px primaryLine with no shadow; same for `WorkspaceAttentionFlashRingView` and the tmux overlay.

### Gradients
- `Sources/TextBoxInput.swift`: pre-Tahoe text box pill fallback: gradient fill + gradient stroke -> flat `raise` fill + 1 px `border` stroke.

### Space Grotesk
- `Resources/Fonts/SpaceGrotesk[wght].ttf` (136,676 bytes, sha256 `acad6de1...79f72`, google/fonts `ofl/spacegrotesk`), `Resources/Fonts/OFL.txt` beside it.
- `cmux.xcodeproj/project.pbxproj`: folder reference `Fonts` (path Fonts) in the `Resources` group + `Fonts in Resources` in the app target's Resources phase (`A5001102`), so it lands in `ShellX.app/Contents/Resources/Fonts/`. Normalized with `scripts/normalize-pbxproj.py`.
- `Resources/Info.plist`: `ATSApplicationFontsPath = Fonts` (first key, away from L1's SUFeedURL edits).

### Tests (app-hosted, written, not run: no app builds)
- `cmuxTests/ShellXThemeTests.swift` (new, Swift Testing; wired with `scripts/sync-test-wiring`): `accentDefaultsToShellXPrimary`, `statusGlyphColors`, `darkSidebarSelectionIsTheRaiseToken`, `attentionRingIsAFlatOnePixelPrimaryLine`, `sidebarTintDefaultsToPanel`, `appIsDarkOnly`, `defaultTerminalThemeUsesPalette`, `userGhosttyThemeWins` (Review Focus 2). Brief names mapped to real APIs: `CmuxAccentColor()`, `SidebarCompactStatusGlyph(kind:tooltip:).color(...)`, `GhosttyConfig.cmuxDefaultThemeConfigContents` + `shouldApplyManagedDefaultAppearance`.
- Updated for the new colors: `cmuxTests/SidebarCompactAgentStatusTests.swift`, `cmuxTests/WorkspaceUnitTests.swift`, `cmuxTests/AuthEnvironmentTests.swift`, `cmuxTests/GhosttyConfigTests.swift` (theme-file name via constant).

### Guard (python unittest)
- `tests/test_shellx_theme.py` (new, registered in `tests/test-execution.toml`, linux-guard lane): font + OFL ship (sha256), Info.plist key, Fonts folder in the app Resources phase/group, display font family name, appearance picker hidden, live appearance forced dark and enforced before launch resolution, no gradient outside an allowlist.

## The 16 ANSI values (ShellXTerminalTheme)

| # | name | hex | source | contrast on bg |
|---|---|---|---|---|
| 0 | black | `#211a37` | `line` | 1.2 |
| 1 | red | `#e88a8a` | `error` | 8.0 |
| 2 | green | `#6fd49a` | `done` | 10.9 |
| 3 | yellow | `#e8c468` | `running` | 11.9 |
| 4 | blue | `#60a5fa` | `primary` | 7.8 |
| 5 | magenta | `#c49af0` | soft violet | 8.7 |
| 6 | cyan | `#6fc8d9` | soft cyan | 10.4 |
| 7 | white | `#cdc7e0` | `text` | 12.2 |
| 8 | bright black | `#6e6790` | between border and muted | 3.8 |
| 9 | bright red | `#f2a7a7` | error, lighter | 10.3 |
| 10 | bright green | `#93e2b4` | done, lighter | 13.0 |
| 11 | bright yellow | `#f2d68f` | running, lighter | 14.0 |
| 12 | bright blue | `#93c5fd` | `primary-text` | 11.0 |
| 13 | bright magenta | `#d9b8f7` | magenta, lighter | 11.5 |
| 14 | bright cyan | `#96dbe7` | cyan, lighter | 12.9 |
| 15 | bright white | `#e6e2f2` | `text-hi` | 15.7 |

background `#0b0716` (bg), foreground `#cdc7e0` (text), cursor `#60a5fa` (primary), cursor-text `#0b0716`, selection-background `#233356` (primary 28% over bg; text-hi on it 9.8:1), selection-foreground `#e6e2f2`.

## Gradients
Changed (flat token now):
- `Sources/TextBoxInput.swift` `TextBoxInputGlassPillBackground.fallback` (input pill fill + stroke) -> `raise` + `border`.
- Ring glows (not gradients, but spec "no glows"): notification/flash ring shadow 0.

Left (allowlisted in `tests/test_shellx_theme.py` with reasons):
- Content fades/masks: `ModeBarLabelEdgeFade.swift`, `SidebarScrim.swift`, `TerminalSizeBoundsOverlayView.swift`.
- DEBUG-only feed button style variants: `Feed/FeedPanelView.swift` (`.liquid`, `.halo`; release uses `.solid`).
- Decorative art: `SleepyFaceView.swift`, `Cloud/CloudWelcomeMedia.swift` (cloud UI hidden), `App/ComputerUseCursorOverlayController.swift`, `CmuxComputerUse/AgentCursorPointerView.swift`, `ProBadgeStyle.swift` (logo gradient, the spec's exception).
- `CmuxSettingsUI/Rows/ThemeWindowThumbnail.swift`: wallpaper art inside the now-hidden appearance picker.
- `CmuxSwiftRender*`: interpreter/renderer for user-authored views.
- `Panels/BrowserPanelView.swift` omnibar suggestion popover overlay/border gradient: popover chrome, not a button/row; follow-up.

## TDD evidence (RED -> GREEN)
1. ShellXBrand: wrote `ShellXThemeTokensTests.swift` first.
   - RED `swift test --package-path Packages/Shared/ShellXBrand` -> `error: cannot find 'ShellXFonts' in scope` (and the other new types) / `error: fatalError`.
   - GREEN after adding the 4 files + font: `✔ Test run with 13 tests in 2 suites passed`.
2. CmuxFoundation accent: updated `CmuxAccentColorTests` first.
   - RED `swift test --package-path Packages/macOS/CmuxFoundation --filter CmuxAccentColorTests` -> `Expectation failed: (rgbBytes(accent.nsColor(isDark: true)) → [0, 145, 255]) == [96, 165, 250]` ... `Test run with 12 tests in 1 suite failed ... with 13 issues`.
   - GREEN -> `✔ Test run with 12 tests in 1 suite passed`.
3. CmuxTerminalCore terminal default (ran by symlinking the user's cached GhosttyKit.xcframework for the same ghostty commit cb1ef709 into the worktree, then removed it; SwiftPM prints a non-fatal "unexpected binary name" notice):
   - RED (new tests against the old GhosttyConfig.swift): `builtInManagedDefaultIsTheShellXTheme ... (config.backgroundColor.hexString() → "#1E1E1E") == "#0B0716"`, `cursorColor → "#98989D" == "#60A5FA"`, light/dark name equality failures, etc.
   - GREEN: full package `swift test --package-path Packages/macOS/CmuxTerminalCore` -> `✔ Test run with 507 tests in 79 suites passed` (after updating `GhosttyConfigThemeParityTests` no-config fixture to the ShellX palette).
4. CmuxSettings (compile + regression): `swift test --package-path Packages/macOS/CmuxSettings` -> `✔ Test run with 488 tests in 70 suites passed`.
5. CmuxSettingsUI (compile + regression of the hidden row): `Test run with 261 tests in 45 suites failed ... with 1 issue` — the one issue is `ProUpgradeCardModelTests.maxIsOfferedNoUpgrade` ("ShellX Max" vs the test's "cmux Max"), from Task 6's string rename, not this task.
6. Guard: `python3 tests/test_shellx_theme.py` RED with Info.plist/ThemesSection/AppearanceSettings stashed -> `FAILED (failures=3)` (picker hidden, plist key, forced dark); GREEN -> `Ran 7 tests ... OK`.
7. Other checks: `python3 scripts/localization_catalog.py check` -> `10 catalogs, 9 locales: 0 parity errors`; `python3 scripts/verify-local.py --all --swift-changed` -> 16/16 PASSED (swift-syntax, xcstrings, localization, project normalization, test wiring); all `tests/test_shellx_*.py` OK; `scripts/sync-test-wiring --check` ok. `tests/test_ci_test_execution_registry.py` has the same 3 failures with and without my changes (pre-existing).
- Not run (lane override): app build, `cmuxTests` (incl. `ShellXThemeTests`), `CmuxAppKitSupportUI` package tests (needs the `vendor/bonsplit` submodule, not checked out; the tint-defaults file was typechecked standalone with `swiftc -typecheck`). Step 4's build-and-compare-by-eye was skipped.

## Rulings
- Ruling: the built-in terminal default lives in `CmuxTerminalCore.GhosttyConfig` (managed default theme name + fallback contents), not `TerminalAdaptiveDefaultThemeSettings.swift` — that file only reads the on/off toggle; the palette and the "user config wins" rule are in the core — cost if wrong: none functionally; the brief's file list is off by one layer.
- Ruling: both managed theme names = "ShellX" and both schemes get the ShellX palette — ShellX is dark-only (spec §7.4), and no light ShellX palette exists — cost if wrong: if a light variant is wanted later, split `cmuxDefaultLightThemeName` again and restore the per-scheme tests.
- Ruling: Review Focus 2 kept as is: managed default applies only when `terminal.adaptiveDefaultTheme` is on (default true) and the resolved user Ghostty config has no `theme` and no background/foreground/bold-color/palette/cursor/selection directive; tested in CmuxTerminalCore (run) and `ShellXThemeTests.userGhosttyThemeWins` (written) — cost if wrong: none expected.
- Ruling: ShellXBrand is a real path dependency of CmuxFoundation, CmuxAppKitSupportUI, CmuxSettings and CmuxTerminalCore (no mirrored literals) — the Xcode project already references `Packages/Shared/ShellXBrand` as a local package, so the same package identity resolves; CmuxFoundation/CmuxSettings/CmuxTerminalCore resolved and built under SwiftPM — cost if wrong: an Xcode resolution error in CI's app build; fallback is literal mirrors.
- Ruling: dark-only enforced by (a) pinning `appearanceMode = "dark"` in UserDefaults at `cmuxApp.init` before the launch appearance apply and on every live observer apply, and (b) the live environment always setting `NSApp.appearance = darkAqua` — the stored mode also drives Ghostty split-theme sides, SwiftUI `preferredColorScheme` and chrome, so pinning it is the only way all of them resolve dark; `AppearanceMode`/`mode(for:)` semantics left untouched so upstream appearance unit tests (which inject environments) keep passing — cost if wrong: a hand-edited `app.appearance` in shellx.json is silently ignored.
- Ruling: forced in `cmuxApp.init` (where the existing launch appearance apply lives, before AppDelegate.didFinishLaunching), not in AppDelegate — "as early as the existing appearance handling" — cost if wrong: none.
- Ruling: DEBUG-only Startup Appearance preview window keeps its explicit Light/Dark preview buttons (developer tool; its "stored" option resolves dark) — cost if wrong: a debug-only light preview.
- Ruling: `sidebarAppearance.matchTerminalBackground` default stays `true`, so the panel tint (#100b1d @ 1.0) shows only when "match terminal background" is off; by default the sidebar shows the terminal background, which is ShellX `bg` (#0b0716) — flipping it changes window/backdrop compositing paths that cannot be verified without an app build, and with a matched light user theme the unmatched panel would mix schemes — cost if wrong: sidebar is `bg` instead of `panel` by default; one-line flip in `SidebarAppearanceCatalogSection.matchTerminalBackground` + `WindowChromeSidebarTintDefaults.matchesTerminalBackground` after a visual check.
- Ruling: ShellX sidebar text tokens (textHi/muted) and the `raise` selection apply only when the sidebar scheme is dark; a light sidebar (matched light user theme) keeps semantic colors/accent selection — keeps rows readable when the user's theme wins — cost if wrong: light-theme users see cmux-style rows.
- Ruling: badge "= primary" satisfied through the accent (badge fallback = accent, default accent = primary), so the accent/badge color settings still override — cost if wrong: none.
- Ruling: status glyph "others = muted" includes waiting and every pull-request state (merged purple dropped), per the brief — cost if wrong: merged PRs lose their purple.
- Ruling: the glyph is not flattened to the selected foreground on the ShellX raise selection (only on other selection fills) — the raise block keeps status colors readable and the mockup shows colored status on the current row — cost if wrong: none.
- Ruling: attention ring uses the accent at 0.45 alpha (= `primaryLine` by default) instead of a fixed `primaryLine`, so a user accent still tints it; user-configured ring colors keep full alpha — cost if wrong: none.
- Ruling: the flash ring shares the 1 px / no-glow treatment (same metrics and presentation type) — cost if wrong: navigation flash is subtler.
- Ruling: Settings strings for "Adapt Default Theme to Appearance" left as is (no new user-visible strings added in this task) — cost if wrong: the toggle's subtitle still mentions light/dark; follow-up string pass.

## Files changed
New: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/{ShellXAppearance,ShellXFonts,ShellXStatus,ShellXTerminalTheme}.swift`, `Packages/Shared/ShellXBrand/Tests/ShellXBrandTests/ShellXThemeTokensTests.swift`, `Resources/Fonts/SpaceGrotesk[wght].ttf`, `Resources/Fonts/OFL.txt`, `cmuxTests/ShellXThemeTests.swift`, `tests/test_shellx_theme.py`.
Modified: `Packages/macOS/CmuxFoundation/{Package.swift, Sources/CmuxFoundation/Color/CmuxAccentColor.swift, Sources/CmuxFoundation/ConfigValidation/CmuxConfigSchema.generated.swift, Tests/CmuxFoundationTests/CmuxAccentColorTests.swift}`, `Packages/macOS/CmuxAppKitSupportUI/{Package.swift, .../WindowChromeSidebarTintDefaults.swift, .../WindowChromeSidebarPresetOption.swift}`, `Packages/macOS/CmuxSettings/{Package.swift, .../SidebarAppearanceCatalogSection.swift}`, `Packages/macOS/CmuxSettingsUI/{.../ThemesSection.swift, .../CuratedSettingEntry+Default.swift, Tests/.../SettingsRowAnchorResolutionTests.swift}`, `Packages/macOS/CmuxTerminalCore/{Package.swift, .../GhosttyConfig.swift, Tests/.../GhosttyConfigManagedDefaultAppearanceTests.swift, .../GhosttyConfigAdaptiveAppearanceRegressionTests.swift, .../GhosttyConfigThemeParityTests.swift}`, `Resources/Info.plist`, `Sources/{AppearanceSettings,cmuxApp,SettingsSearchIndex,SettingsSearchAliases,TextBoxInput}.swift`, `Sources/Panels/Panel.swift`, `Sources/Sidebar/{SidebarAppearanceSupport,SidebarCompactStatusGlyph}.swift`, `Sources/Sidebar/AppKitList/Cells/{SidebarWorkspaceRowCellView,SidebarWorkspaceRowSupportViews}.swift`, `cmux.xcodeproj/project.pbxproj`, `cmuxTests/{AuthEnvironmentTests,GhosttyConfigTests,SidebarCompactAgentStatusTests,WorkspaceUnitTests}.swift`, `tests/test-execution.toml`.

## Concerns
1. No app build: app-target Swift (AppearanceSettings, cmuxApp, Panel, sidebar files, TextBoxInput) is only syntax-checked (`verify-local --swift-changed`) and partly typechecked standalone; CI's Debug build is the first compile. Package changes compiled and tested (except CmuxAppKitSupportUI, which needs `vendor/bonsplit`).
2. App-hosted tests not run. I updated the tests I found that pin cmux blue / old glyph colors / Apple System Colors, but raster/pixel tests in `cmuxTests/SidebarAppKitRowCellTests.swift` (e.g. description prose expected near `secondaryLabelColor` within 0.12) and similar may need tuning once the controller runs the app tests.
3. Sidebar default is still terminal-matched (`bg`), not `panel` (see the matchTerminalBackground ruling).
4. Pre-existing, not mine: `CmuxSettingsUITests.ProUpgradeCardModelTests.maxIsOfferedNoUpgrade` ("ShellX Max" vs "cmux Max", Task 6) and 3 failures in `tests/test_ci_test_execution_registry.py`.
5. Spec §7.4 also says the terminal font defaults to JetBrains Mono; not in this task's brief, not done.
6. The browser omnibar suggestion popover still has a subtle overlay/border gradient (allowlisted, follow-up).
7. Temporary GhosttyKit symlink and all `.build` dirs were removed; disk at 19 GB free afterwards.

## Fix round 1 (commit 1cc9b042b1 on shellx/l2-look-t7fix, worktree shellx-wt-l2-t7fix, on top of aed4d49960)

### Changes
1. Sidebar shows `panel` by default (controller ruling: spec wins).
   - `Packages/macOS/CmuxSettings/Sources/CmuxSettings/Keys/SidebarAppearanceCatalogSection.swift`: `matchTerminalBackground` default `false`. Every app fallback reads this (`Workspace.usesSharedSurfaceBackdrop`, the `@AppStorage` in cmuxApp/ContentView, the settings-file template).
   - `Packages/macOS/CmuxAppKitSupportUI/.../WindowChromeSidebarTintDefaults.swift`: `matchesTerminalBackground = false` (the fallback used by `WindowAppearanceResolver.currentFromUserDefaults`); doc updated.
   - `Packages/macOS/CmuxFoundation/.../CmuxConfigSchema.generated.swift`: schema default `matchTerminalBackground: false` (tint `#100B1D` / 1.0 were already done).
   - Fresh install: `migrateSidebarAppearanceDefaultsIfNeeded` never writes `sidebarMatchTerminalBackground`, and it writes the native preset's tint (panel @ 1.0, from round 0), so a fresh install draws the opaque panel. A stored value (UserDefaults, or `sidebarAppearance.matchTerminalBackground` in shellx.json, or cmux's legacy applied-default key) still wins, because every reader is `defaults.object(...) as? Bool ?? default`.
   - With matching off, the sidebar scheme is the ambient scheme (pinned dark), so the dark text tokens from round 0 always apply on the panel.
   - Test: `CmuxAppKitSupportUITests.WindowAppearanceResolverTests.sidebarDrawsPanelUntilTheUserOptsIntoMatching` (renamed from `sidebarMatchesTerminalBackgroundUntilTheUserOptsOut`): default not unified, opt-in true is unified, false again is not. Guard `test_sidebar_defaults_to_the_panel_tint` (catalog, AppKit constant, tint hex/opacity, schema defaults).
2. Omnibar suggestion popover: `Sources/Panels/BrowserPanelView.swift` material + gradient overlay + gradient stroke -> flat `ShellXPalette.raise` fill + 1 px `ShellXPalette.border` stroke; removed the now-unused `popupOverlayGradientColors` / `popupBorderGradientColors`; black drop shadow kept (not a colored shadow). Dropped from the guard allowlist; new guard `test_omnibar_popover_is_flat`.
3. `Packages/macOS/CmuxSettingsUI/Tests/CmuxSettingsUITests/ProUpgradeCardModelTests.swift:53`: expectation `"cmux Max"` -> `"ShellX Max"`. No other Task 6 string expectations in that package's tests (the only other "cmux" hit is a historical comment in AccountTeamCardModelTests).

### Covering tests (commands, output)
- `swift test --package-path Packages/macOS/CmuxSettingsUI` -> `✔ Test run with 261 tests in 45 suites passed` (was 260/261).
- `swift test --package-path Packages/macOS/CmuxSettings` -> `✔ Test run with 488 tests in 70 suites passed`.
- `swift test --package-path Packages/macOS/CmuxFoundation --filter "CmuxAccentColorTests|CmuxConfig"` -> accent tests pass; 3 failures in `CmuxConfigSemanticValidatorTests` ("global cmux.json" vs "global shellx.json" message, and the missing `web/data/cmux.schema.json`). Same 3 failures with my changes stashed, so they predate this fix (rebrand plus the removed web/).
- CmuxAppKitSupportUI package tests: not runnable (`vendor/bonsplit/Package.swift` missing). `WindowChromeSidebarTintDefaults.swift` passes `swiftc -typecheck` standalone against a fresh ShellXBrand build; the resolver test edit is syntax-checked.
- `python3 tests/test_shellx_theme.py` -> `Ran 9 tests ... OK`.
- `python3 scripts/localization_catalog.py check` -> `10 catalogs, 9 locales: 0 parity errors`.
- `python3 scripts/verify-local.py --all --swift-changed` -> `PASSED: 16/16`.
- ShellXBrand not touched (built only for the typecheck). All `.build` dirs removed afterwards.

### Rulings
- Ruling: users' stored match values are left as they are; there is no migration that forces `false` — "users who already set it keep their value"; a fresh ShellX bundle id has no stored value anyway — cost if wrong: anyone carrying a stored `true` keeps the bg sidebar.

### Concerns
- Still no app build. `cmuxTests` were not run; app tests that assume the sidebar matches the terminal by default may need their expectations flipped (I found none that rely on the default: the ones I checked set the key explicitly).

## Fix round 1b (commit on shellx/l2-look-t7fix after 1cc9b042b1)
- `Packages/macOS/CmuxFoundation/Tests/CmuxFoundationTests/CmuxConfigSemanticValidatorTests.swift` (lines 285, 301): expected message `"global cmux.json"` -> `"global shellx.json"`, matching Task 6's rebranded validator text (`CmuxConfigSemanticValidator.swift:70`, "is only supported in the global shellx.json").
- `swift test --package-path Packages/macOS/CmuxFoundation` (full package) -> `✘ Test run with 723 tests in 110 suites failed ... with 1 issue`. The single issue is pre-existing and left alone as instructed: CmuxFoundationTests `CmuxConfigSemanticValidatorTests` test "embedded schema is byte-for-byte web/data/cmux.schema.json" (CmuxConfigSemanticValidatorTests.swift:25). It fails because `web/data/cmux.schema.json` no longer exists after the repo move.
