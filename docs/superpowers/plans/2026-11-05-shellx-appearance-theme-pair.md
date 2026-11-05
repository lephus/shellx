# ShellX Appearance Switch and Light/Dark Theme Pair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Settings **Appearance** menu (System / Light / Dark) switch the whole ShellX window and the terminal live. The terminal uses a light/dark theme pair, set by section in a smaller gallery (12 dark + 12 light). Every native ShellX surface must be readable in Light.

**Architecture:**
- **Palette:** `ShellXPalette` tokens become dynamic colors with a dark and a light value, resolved by the view's effective appearance.
- **Dark lock:** the lock in `AppearanceSettings` / `cmuxApp` is removed, so the upstream cmux appearance machinery (already light/dark and pair aware) runs again.
- **Gallery:** it writes one side of the Ghostty `theme = light:X,dark:Y` pair per click, and filters to a curated list.
- **Surfaces:** each ShellX surface that forced dark or drew fixed dark colors is moved onto the dynamic tokens.

**Tech Stack:**
- Swift 6.0, SwiftUI + AppKit.
- Packages: `ShellXBrand`, `CmuxSettingsUI`, `CmuxTerminalCore`, `CmuxAppKitSupportUI`.
- App target `cmux`, XCTest + Swift Testing.
- Python guard tests in `tests/`.
- React web surface `webviews/src/automations` (bun).

**Spec:** `docs/superpowers/specs/2026-11-05-shellx-appearance-theme-pair-design.md`

## Global Constraints

- **The Appearance menu:**
  - Values are System / Light / Dark, stored in the existing app appearance setting (`appearanceMode` / `catalog.app.appearance`).
  - Light and Dark force that appearance. System follows macOS live.
  - Chrome, terminal and built-in browser pages all follow it.
- **Row copy and placement:**
  - The row is titled "Appearance" (vi "Giao diện") and sits at the top of Themes.
  - Its subtitle says it switches ShellX, the terminal and web pages.
  - The "Browser Theme" row is removed.
- **Defaults:**
  - Appearance defaults to **Dark**, for existing users and new installs.
  - No migration from `browser.theme`.
  - `browser.theme` is still read and validated but has no effect, shows no warning and is marked deprecated in the schema and docs.
- **No config writes:**
  - Updating ShellX never writes the user's Ghostty config.
  - With no `theme =` line, dark resolves to ShellX's default dark (`ShellXTerminalTheme.name` = "ShellX") and light to **"Catppuccin Latte"** (Claude's pick of a soft built-in light theme).
  - An existing single theme stays the dark side. If it is itself a light theme, it becomes the light side and dark keeps "ShellX".
- **Gallery clicks:**
  - A click under **Dark Themes** sets only the dark side. A click under **Light Themes** sets only the light side.
  - The first click writes the managed pair block, filling the other side with the theme it currently resolves to.
  - A hand- or CLI-written pair is read as is, and a click changes only its own side.
- **Badges:**
  - A card that fills a slot shows that slot's badge (🌙 Dark / ☀ Light) in whatever section it is classified into.
  - A card that fills both slots shows both badges.
  - The row subtitle names both sides.
- **Curated gallery (exact Ghostty names):**
  - Dark: ShellX, Catppuccin Mocha, iTerm2 Solarized Dark, GitHub Dark Default, TokyoNight, Rose Pine, Gruvbox Dark, Everforest Dark Hard, Atom One Dark, Nord, Ayu Mirage, Kanagawa Wave.
  - Light: Catppuccin Latte, iTerm2 Solarized Light, GitHub Light Default, TokyoNight Day, Rose Pine Dawn, Gruvbox Light, Everforest Light Med, Atom One Light, Nord Light, Ayu Light, Kanagawa Lotus, One Half Light.
  - "Search all themes" searches every theme.
  - The themes in use always appear in their section, even outside the curated set.
- **Removed toggle:** "Adapt Default Theme to Appearance" is removed from Settings (Themes and Terminal sections, curated entries, search index). Its stored value keeps being read on the no-theme path.
- **Light ships complete:** every native ShellX surface reached in normal use is readable in Light. There is no hidden or Beta Light option.
- **Color taste:** soft colors, primary `#60a5fa`, no gradients except the existing allow-list, yellow means running.
- **Swift 6.0:** app-linked Swift stays Swift 6.0 compatible.
- **Localization:** every new or changed string goes through `Resources/Localizable.xcstrings` with en, de, fr, ar, es, zh-Hant, zh-Hans, ko, ja, vi (`skills/cmux-localization`), checked by `python3 scripts/localization_catalog.py check`.
- **Commands:**
  - package tests: `swift test --package-path Packages/Shared/ShellXBrand` (and `Packages/macOS/CmuxSettingsUI`, `Packages/macOS/CmuxTerminalCore`)
  - app tests: `scripts/shellx/test-app.sh <Suite>`
  - guard: `python3 tests/test_shellx_theme.py`
  - web: `cd webviews && bun test src/automations`
  - Never run bare `xcodebuild`. Never touch `/Applications/ShellX.app`.
- **Process:**
  - Commit each failing test before its fix.
  - Disk paths are case-insensitive but git is not: keep `Packages/`, `Sources/`, `Resources/`, `cmuxTests/` casing exactly and check `git status --short` for lowercase variants before committing.
  - Branch `feat/shellx-appearance-theme-pair`.

## Review Focus

1. **An existing user who never opens Settings updates ShellX** (stored `appearanceMode = dark`, single `theme = Abernathy`). Window, terminal and browser look exactly as before, and the Ghostty config file is byte-identical. Pinned in Task 2 and Task 3.
2. **System while macOS flips Light↔Dark with ShellX open.** Chrome, every open terminal, the Settings gallery highlight and the Automations page all switch without a restart. Pinned in Tasks 2, 3 and 8.
3. **A CLI pair `light:Nord Light,dark:Abernathy`, then a click on "Rose Pine Dawn".** The result is `light:Rose Pine Dawn,dark:Abernathy`. Abernathy stays badged under Dark Themes even though it is outside the curated list. Pinned in Task 3.
4. **No `theme =` line, then a click on "TokyoNight".** The managed block becomes `light:Catppuccin Latte,dark:TokyoNight`, and the light side still shows Catppuccin Latte. Pinned in Task 3.
5. **Light text contrast:**
   - Every text token is at least 4.5:1 on the light bg/panel/raise.
   - Status colors are at least 3:1.
   - The selected-row title is at least 4.5:1 on the light selection fill.

   No surface draws near-white text on a light fill. Pinned in Task 1 and Task 4.

---

### Task 1: Dynamic ShellX palette with light tokens (ShellXBrand)

**Files:**
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXDynamicColor.swift`
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXPalette.swift:92-159` (tokens), `ShellXTerminalTheme.swift` (use `.dark`), every compile error in ShellXBrand and its app callers that needs a fixed color (switch those to `.dark` / `.resolved(isDark:)`)
- Test: `Packages/Shared/ShellXBrand/Tests/ShellXBrandTests/ShellXDynamicColorTests.swift`, update `ShellXThemeTokensTests.swift`

**Interfaces:**
- Produces:
  - `public struct ShellXDynamicColor: Sendable, Equatable { public let dark: ShellXColor; public let light: ShellXColor; public init(dark: ShellXColor, light: ShellXColor); public func resolved(isDark: Bool) -> ShellXColor; public var nsColor: NSColor; public var color: Color }`
  - `nsColor` is `NSColor(name:dynamicProvider:)`, picking `dark` when the appearance best matches `.darkAqua` / `.vibrantDark` / `.accessibilityHighContrastDarkAqua`, otherwise `light`. `color` is `Color(nsColor:)`.
  - Every `ShellXPalette` token becomes `ShellXDynamicColor`. The arrays `effectHighlightStops` and `waitingBorderStops` become `[ShellXDynamicColor]`.
  - Existing dark values stay byte-identical as `.dark`.
  - `public static func isDark(_ appearance: NSAppearance?) -> Bool` on `ShellXDynamicColor`, shared by later tasks.

Light values, Claude's call per the spec's color taste:

| token | light | token | light |
|---|---|---|---|
| bg | `#f7f7fb` | selectionTitle | `#0f1b33` |
| panel | `#f0eff6` | selectionSecondary | `#44557a` |
| raise | `#ffffff` | rowHover | `#e9e6f3` |
| line | `#e4e2ee` | unfocusedTabIndicator | `#a7a1bf` |
| border | `#d6d3e4` | selectionPillBacking | `#ffffff` α0.6 |
| text | `#2a2540` | selectionWaitingRing | `#2563eb` α0.7 |
| textHi | `#15121f` | effectWorkingBase | `#8a6a1f` |
| muted | `#615b7a` | effectWorkingHighlight | `#d4a017` |
| primary | `#60a5fa` | effectFlash | `#a78bfa` α0.18 |
| primarySoft | `#60a5fa` α0.16 | highlight stops | `#d6578a #c98a1c #2f9e5b #1f8fbf #5468d8 #8b5cd6 #d6578a` |
| primaryLine | `#60a5fa` α0.6 | waitingBorderStops | same as dark |
| primaryText | `#2563eb` | running | `#a16207` |
| done | `#2f855a` | error | `#c53030` |

- [ ] **Step 1: Write the failing tests**
  - `darkValuesUnchanged`: `ShellXPalette.bg.dark.hex == 0x0b0716`, `panel.dark.hex == 0x100b1d` and `primary.dark.hex == 0x60a5fa`, plus each other dark token's hex from the current file.
  - `resolvesByAppearance`:
    - `ShellXPalette.bg.nsColor` resolved under `NSAppearance(named: .aqua)` gives `#f7f7fb`.
    - Under `.darkAqua` it gives `#0b0716`. Use `performAsCurrentDrawingAppearance`, then convert to sRGB.
  - `lightTextContrast`, using a WCAG relative-luminance helper in the test:
    - `text`, `textHi`, `muted` and `primaryText` are ≥ 4.5 on light `bg`, `panel` and `raise`;
    - `running`, `done` and `error` are ≥ 3.0 on light `panel`;
    - `selectionTitle` is ≥ 4.5 on `ShellXSelectionTint`'s light fill (Task 4 will reuse this assertion).
  - Update `ShellXThemeTokensTests` so it reads `.dark` wherever it compared a `ShellXColor`.
- [ ] **Step 2: Run** `swift test --package-path Packages/Shared/ShellXBrand --filter "ShellXDynamicColor|ShellXThemeTokens"`. Expected: build failure. Commit the tests.
- [ ] **Step 3: Implement** `ShellXDynamicColor` and the light tokens. Then make the app compile:
  - callers drawing UI use `.color` / `.nsColor`, which now adapt;
  - callers needing a fixed color use `.dark` (terminal theme, launch art, hex strings written to config) or `.resolved(isDark:)`.

  Run `scripts/test-unit.sh build` to find every break.
- [ ] **Step 4: Run** the same command plus `swift test --package-path Packages/Shared/ShellXBrand` and `scripts/test-unit.sh build`. Expected: PASS / BUILD SUCCEEDED.
- [ ] **Step 5: Commit** `feat(shellx): ShellX colors adapt to light and dark`.

---

### Task 2: Unlock appearance and the Appearance menu

**Files:**
- Modify:
  - `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXAppearance.swift`: replace the forced members with `public static let defaultModeRawValue = "dark"`, the new-install default.
  - `Sources/AppearanceSettings.swift:65-81, 101-113, 316-325`.
  - `Sources/cmuxApp.swift:219-220, 1337-1341`.
  - The appearance catalog key default in `Packages/macOS/CmuxSettings` (default = dark).
  - `Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/ThemesSection.swift`: Appearance row first, using `Rows/ThemePickerRow.swift`; remove `browserThemeRow` and `adaptiveDefaultThemeRow`.
  - `Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/TerminalSection.swift`: remove the adaptive toggle row.
  - `Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Navigation/CuratedSettingEntry+Default.swift`: re-add `appearance`, drop `browser.theme` and `terminal.adaptiveDefaultTheme`.
  - `Sources/SettingsSearchIndex.swift`, `Sources/SettingsSearchAliases.swift`.
  - `Sources/Panels/BrowserPanel.swift:167-199`: `BrowserThemeMode.mode(defaults:)` always returns `.system`, so pages follow the app.
  - The schema and docs entry for `browser.theme`: deprecated, "replaced by app.appearance".
- Test:
  - update `cmuxTests/ShellXThemeTests.swift:94-116`, `Packages/Shared/ShellXBrand/Tests/ShellXBrandTests/ShellXThemeTokensTests.swift:14-18` and `tests/test_shellx_theme.py:7-8, 88-104`;
  - add cases to `cmuxTests/AppearanceSettingsTests.swift`.

**Interfaces:**
- Consumes: Task 1 tokens (chrome now adapts when the appearance changes).
- Produces: a live `AppearanceSettings` apply that sets `NSApp.appearance` from the stored mode (nil for System) and calls `GhosttyApp.shared.synchronizeThemeWithAppearance` with the resolved appearance. This is upstream cmux behavior. Later tasks rely on `NSApp.effectiveAppearance` changing.

- [ ] **Step 1: Write the failing tests**
  - `AppearanceSettingsTests.storedLightAppliesLight`: the live environment applies `.aqua`, and the terminal preference is `.light`.
  - `systemFollowsSystem`: `system` → nil app appearance; the terminal preference follows the injected system appearance.
  - `missingStoredModeDefaultsDark`: nothing stored resolves to `dark`, and nothing is written.
  - `storedDarkStaysDark`.
  - `ShellXThemeTests.appIsDarkOnly` is replaced by `appearanceIsUserChoice`: stored `light` is not rewritten.
  - The `tests/test_shellx_theme.py` hidden-picker and forced-dark tests are replaced by `test_appearance_row_first_in_themes` (ThemesSection renders the appearance row before the accent row) and `test_no_forced_appearance` (no `forcedAppearance` and no `enforceShellXDarkOnly` in Sources).
  - `BrowserThemeModeTests.storedValueIgnored`: a stored `light` resolves to `.system`.
- [ ] **Step 2: Run** `scripts/shellx/test-app.sh AppearanceSettingsTests ShellXThemeTests` and `python3 tests/test_shellx_theme.py`. Expected: FAIL. Commit the tests.
- [ ] **Step 3: Implement.** The row title and subtitle use new catalog keys `settings.app.appearance` ("Appearance") and `settings.app.appearance.subtitle` ("Switch ShellX, the terminal and web pages between light and dark. System follows macOS."), translated into all 10 locales.
- [ ] **Step 4: Run** the same commands plus `python3 scripts/localization_catalog.py check`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(shellx): the Appearance menu switches ShellX between light and dark`.

---

### Task 3: Terminal theme pair, set by section, in a curated gallery

**Files:**
- Modify:
  - `Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/Config/GhosttyConfig.swift:24-31` (`cmuxDefaultLightThemeName = "Catppuccin Latte"`, plus its doc comment).
  - `Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Models/TerminalThemeGalleryModel.swift`.
  - `Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/TerminalThemeGallery.swift`.
  - The theme card view, for badges.
  - `Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Environment/TerminalThemeGalleryContext.swift`: add `defaultPair`.
  - `Sources/HostSettingsActions.swift:200`: pass it.
- Create: `Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Models/TerminalThemeCuration.swift`.
- Test: `Packages/macOS/CmuxSettingsUI/Tests/CmuxSettingsUITests/TerminalThemeGalleryModelTests.swift`.

**Interfaces:**
- Produces:
  - `TerminalThemeGalleryContext.defaultPair: CmuxTerminalThemePair`. The host passes `light: GhosttyConfig.cmuxDefaultLightThemeName, dark: GhosttyConfig.cmuxDefaultDarkThemeName`.
  - `enum TerminalThemeCuration { static let dark: [String]; static let light: [String] }`, holding the exact lists from Global Constraints.
  - `TerminalThemeGalleryModel.select(_ name: String, slot: Slot)` replaces `select(_:)`.
  - `TerminalThemeGalleryModel.results` returns `Results { dark: [Theme]; light: [Theme] }`:
    - classified by `colors.isDark`, with unknown counting as dark;
    - with an empty query: curated themes in list order, plus any in-use theme not in the list, appended;
    - with a query: every match.
  - `func badges(for name: String) -> Set<Slot>`.
- **Effective pair:**
  - the managed block when present;
  - otherwise the loaded config's theme value;
  - otherwise `defaultPair`.
  - A plain single theme `X` reads as `dark: X, light: defaultPair.light`, unless `X` is classified light, in which case it reads as `light: X, dark: defaultPair.dark`.
- **Write:** `select` writes `encodedThemeValue(light:dark:)` of the effective pair with only `slot` replaced.

- [ ] **Step 1: Write the failing tests** (the existing temp-config fixture):
  - `selectDarkKeepsLight`: managed `light:Nord Light,dark:Abernathy`, then `select("TokyoNight", slot: .dark)` → `light:Nord Light,dark:TokyoNight`.
  - `selectLightKeepsDark`: the same pair, then `select("Rose Pine Dawn", slot: .light)` → `light:Rose Pine Dawn,dark:Abernathy` (Review Focus 3).
  - `firstPickWithNoThemeFillsDefault`: no theme anywhere, then `select("TokyoNight", slot: .dark)` → `light:Catppuccin Latte,dark:TokyoNight` (Review Focus 4).
  - `singleDarkThemeIsDarkSide`: config `theme = Abernathy`, then `select("Rose Pine Dawn", slot: .light)` → `light:Rose Pine Dawn,dark:Abernathy`.
  - `singleLightThemeIsLightSide`: config `theme = Rose Pine Dawn`, then `select("Nord", slot: .dark)` → `light:Rose Pine Dawn,dark:Nord`.
  - `curatedWhenNoQuery`: with all themes loaded, `results.dark.map(\.name)` starts with the 12 curated dark names in order, and `results.light` likewise.
  - `inUseOutsideCurationShown`: pair `dark:Abernathy` → `results.dark.map(\.name).contains("Abernathy")`.
  - `queryShowsAll`: the query "gruvbox" returns every Gruvbox variant in the catalog.
  - `badgesFollowSlots`: pair `light:X,dark:X` → `badges(for: "X") == [.light, .dark]`.
  - `openingSettingsWritesNothing` (Review Focus 1): loading the model and reading `results` leaves the config file byte-identical.
- [ ] **Step 2: Run** `swift test --package-path Packages/macOS/CmuxSettingsUI --filter TerminalThemeGalleryModel`. Expected: FAIL. Commit the tests.
- [ ] **Step 3: Implement.**
  - The view renders "Dark Themes" first when the slot in use is dark, otherwise "Light Themes" first.
  - Each card's `onSelect` passes its section's slot.
  - The card draws badges from `badges(for:)` as small pills, "🌙 Dark" (blue `#60a5fa`) and "☀ Light" (soft yellow), with new localized labels `settings.terminal.themeGallery.badgeDark` / `.badgeLight`.
  - The subtitle keeps the existing "Light: %1$@ · Dark: %2$@" key.
  - Remove the old "writes both sides" doc comment.
- [ ] **Step 4: Run** the same command, then `swift test --package-path Packages/macOS/CmuxTerminalCore` and `python3 scripts/localization_catalog.py check`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(shellx): pick a dark and a light terminal theme from a smaller gallery`.

---

### Task 4: Sidebar in light

**Files:**
- Modify:
  - `Packages/macOS/CmuxAppKitSupportUI/.../WindowChromeSidebarTintDefaults.swift:25,39-51` (the default tint is `ShellXPalette.panel` resolved for the window's appearance; the "untouched" rule compares against either resolved value);
  - `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXSelectionTint.swift:43,56` (composite over the appearance's panel);
  - `Sources/Sidebar/AppKitList/Cells/SidebarWorkspaceRowSupportViews.swift:53-70`;
  - `Sources/Sidebar/AppKitList/Cells/SidebarGroupHeaderPalette.swift:59`;
  - `Sources/ShellX/Sidebar/SidebarMachineHeaderCellView.swift:108-109,270,283-285`;
  - `Sources/ShellX/Sidebar/SidebarStatusPillView.swift:74-88`;
  - `Packages/Shared/ShellXBrand/.../Sidebar/SidebarStatusPill.swift:19-22`;
  - `ShellXStatus.swift:18-22`;
  - `Sources/ShellX/Sidebar/ShellXAutomationsSidebarButton.swift:116,288-296`.
- Test: `ShellXSelectionTintTests.swift`, `ShellXSidebarTextTests.swift`, `ShellXSidebarTintSourceTests.swift` (light cases), `tests/test_shellx_theme.py` (sidebar default assertion now appearance-aware).

**Interfaces:**
- Consumes: `ShellXDynamicColor.resolved(isDark:)` and `isDark(_:)` (Task 1).
- Produces: `ShellXSelectionTint.fill(accent:isDark:) -> ShellXColor`. Rename the existing function if needed, and keep its dark output identical.

- [ ] **Step 1: Write the failing tests**
  - `lightSelectionFillIsLight`: the fill's luminance is greater than 0.7 for the ShellX blue accent.
  - `selectionTitleReadableInLight`: contrast is at least 4.5, reusing Task 1's helper.
  - `darkSelectionUnchanged`: the dark fill hex matches today's value.
  - `defaultTintFollowsAppearance`: under `.aqua` the default tint is `#f0eff6`; under `.darkAqua` it is `#100b1d`.
  - `storedDefaultDarkTintStillCountsAsUntouched`: a stored `#100B1D` (the user's machine) is treated as untouched, so the light sidebar follows the theme.
  - `statusPillReadableInLight`: each status hue is at least 3:1 on the light panel.
- [ ] **Step 2: Run** `swift test --package-path Packages/Shared/ShellXBrand --filter "ShellXSelectionTint|ShellXSidebar"`, then `python3 tests/test_shellx_theme.py`. Expected: FAIL. Commit the tests.
- [ ] **Step 3: Implement.** Every listed view reads the dynamic tokens, or resolves with its own `effectiveAppearance`. Nothing uses a fixed dark hex.
- [ ] **Step 4: Run** the same commands plus `scripts/test-unit.sh build`. Expected: PASS.
- [ ] **Step 5: Commit** `fix(shellx): the sidebar reads well in light`.

---

### Task 5: Title bar, tabs, agent effects and the update badge in light

**Files:**
- Modify:
  - `Sources/ShellX/Tabs/ShellXBonsplitStyles.swift:34-92`, `BonsplitConfiguration+ShellXStyles.swift:20-36`. Light now gets ShellX styles built from the light tokens instead of nil (overrides ruling R6, because the spec requires the window to follow).
  - `Sources/ShellX/AgentActivity/WaitingBorderView.swift:101`.
  - The agent effect draw sites that use `effectWorkingBase`, `effectFlash` and `effectHighlightStops`.
  - `Sources/Update/UpdateTitlebarAccessory.swift:999-1001,2494`: in light the badge glyph sits on `primaryText`, so contrast is at least 4.5.
- Test: `ShellXTitlebarModelTests.swift` and the Bonsplit style tests next to `ShellXBonsplitStyles` (create `cmuxTests/ShellXBonsplitStylesTests.swift` if none exist, then run `scripts/sync-test-wiring`).

**Interfaces:**
- Consumes: Task 1 tokens.

- [ ] **Step 1: Write the failing tests**
  - `lightTabStylesNotNil`.
  - `lightSelectedTabTitleReadable`: contrast at least 4.5 against the light tab bar background.
  - `darkTabStylesUnchanged`.
  - `updateBadgeReadableInLight`: contrast at least 4.5.
- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXBonsplitStylesTests ShellXTitlebarModelTests`. Expected: FAIL. Commit the tests.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `fix(shellx): tabs, title bar and agent effects read well in light`.

---

### Task 6: ShellX sheets and popovers stop forcing dark

**Files:**
- Modify (remove `.environment(\.colorScheme, .dark)` and `appearance = .darkAqua`; tokens adapt):
  - `Sources/ShellX/Remote/UI/SignInSheet.swift:110,178`
  - `RequestAccessSheet.swift:186,263`
  - `PhonePairingSheet.swift:58,253`
  - `ApprovalPromptPanel.swift:119,218`
  - `RemoteLinkBanner.swift:54`
  - `Sources/ShellX/Share/ShellXSharePopover.swift:76,231`
  - `ShellXPhoneHandoffPopover.swift:129`
  - `ShellXSheetButtonStyle`: no fixed foregrounds.
- Keep `ShellXQRCode.swift:21`: the white quiet zone is needed for scanning.
- Test: `tests/test_shellx_theme.py` → `test_no_forced_dark_in_shellx_ui`. No `colorScheme, .dark`, `darkAqua` or `.vibrantDark` may appear under `Sources/ShellX/` except an allow-list with reasons. The allow-list starts empty.

- [ ] **Step 1: Write the failing test.** Run `python3 tests/test_shellx_theme.py`. Expected: FAIL, listing the files above. Commit the test.
- [ ] **Step 2: Implement.** Then run the guard and `scripts/test-unit.sh build`. Expected: PASS.
- [ ] **Step 3: Commit** `fix(shellx): sign-in, pairing, approval and share UI follow the appearance`.

---

### Task 7: Text box, browser popover and About logo in light

**Files:**
- Modify:
  - `Sources/TextBoxInput.swift:149-190`: replace the white strokes and foregrounds with tokens; the pill uses the dynamic `raise` / `border`.
  - `Sources/TextBoxInput.swift:826-889`: keep the dark image scrim, but its buttons must be readable.
  - `Sources/Panels/BrowserPanelView.swift:5440-5447`.
  - `Sources/App/About/AboutPanelView.swift:26`: when `ShellXLogo.pdf` has white parts, add a light variant in `Assets.xcassets/ShellXLogo.imageset` or tint it with a template.
- Keep dark by design: `Sources/Panels/BrowserDesignModePopover.swift` (the design-mode HUD) and `Sources/Cloud/*` (hidden in ShellX). Add both to the Task 6 guard allow-list with that reason. Ruling, cost if wrong: one more small task.
- Test: `test_textbox_uses_tokens` in `tests/test_shellx_theme.py` (no `Color.white.opacity` in `TextBoxInput.swift:140-200`).

- [ ] **Step 1: Write the failing test**, then run it. Expected: FAIL. Commit it.
- [ ] **Step 2: Implement**, then run the guard and `scripts/test-unit.sh build`. Expected: PASS.
- [ ] **Step 3: Commit** `fix(shellx): text box, browser popover and About read well in light`.

---

### Task 8: Automations page follows a live appearance change

**Files:**
- Modify:
  - `Sources/ShellX/Automations/ShellXAutomationsController.swift:189-192`: observe `NSApp.effectiveAppearance` (KVO) and emit `{type:"appearance", appearance:"dark"|"light"}`.
  - `ShellXAutomationsBridgeContract.swift`: add the `appearance` event.
  - `webviews/src/automations/types.ts`, `bridge.ts` (accept the event), `store.ts` (update `context.appearance`).
- Test: `cmuxTests/ShellXAutomationsControllerTests.swift` (an injected appearance change emits the event) and `webviews/src/automations/store.test.ts` (`appearanceEventUpdatesContext`).

- [ ] **Step 1: Write the failing tests.** Run `scripts/shellx/test-app.sh ShellXAutomationsControllerTests` and `cd webviews && bun test src/automations`. Expected: FAIL. Commit the tests.
- [ ] **Step 2: Implement.** Rebuild the bundle with `./scripts/build-webviews-app.sh && ./scripts/build-webviews-app.sh --check`, and do not run `bun run build` first.
- [ ] **Step 3: Run** the same tests. Expected: PASS. **Commit** `fix(shellx): the Automations page switches with the appearance`.

---

### Task 9: Full verification, visual pass and PR

- [ ] **Step 1: Full checks.** Run:

```
python3 scripts/verify-local.py && swift test --package-path Packages/Shared/ShellXBrand && swift test --package-path Packages/macOS/CmuxSettingsUI && swift test --package-path Packages/macOS/CmuxTerminalCore && python3 tests/test_shellx_theme.py && (cd webviews && bun test src/automations) && python3 scripts/localization_catalog.py check && scripts/shellx/test-app.sh AppearanceSettingsTests ShellXThemeTests ShellXAutomationsControllerTests && scripts/test-unit.sh build
```

Expected: all pass. Pre-existing red app tests from project memory do not count; report them.

- [ ] **Step 2: Tagged build for dogfood.**
  - Build `CMUX_TAG=appearance` per `skills/cmux-dev-workflow/references/tagged-builds.md`.
  - Give the user the `! open -b <tagged bundle id>` command.
  - With them, walk through Light, Dark and System, with macOS flipping, across the sidebar, tabs, Settings, sheets, the share popover, the text box, the browser, Automations, the terminal and the gallery picks.
  - Capture before/after screenshots with `skills/cmux-capture`.
- [ ] **Step 3: Review** with a review subagent (`skills/cmux-review/SKILL.md`), correctness first.
- [ ] **Step 4: Open the PR to `develop`** following STYLE.md. Changelog line: `Added: Settings → Themes → Appearance switches ShellX between light, dark and system, and the terminal uses a dark and a light theme you pick from a smaller gallery.` Name the default light theme (Catppuccin Latte) and any curated name that was substituted. Merge only on the user's "merge".
