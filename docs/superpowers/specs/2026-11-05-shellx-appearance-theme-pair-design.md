# ShellX Appearance and Light/Dark Theme Pair — design

Date: 2026-11-05 · Branch: `feat/shellx-appearance-theme-pair` (from `develop` fa868f0472)
Mockup (local, not committed): `.superpowers/brainstorm/98104-1793872573/content/theme-pair.html` in the session scratchpad, option A chosen.

## Intent

Settings → Themes has a **System / Light / Dark** menu that today does nothing useful. The user reads it as ShellX's appearance switch and expects it to work:

- Choose **Light** and the terminal switches to the user's light theme.
- Choose **Dark** and it switches to the user's dark theme.
- Choose **System** and ShellX follows macOS Light/Dark.

The whole window follows: the sidebar and title bar take their colors from the theme in use, as they already do when a theme is picked.

Today the menu fails for two reasons:

1. **ShellX is locked to dark** (old spec §7.4).
   - `ShellXAppearance.forcedAppearance` (`Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXAppearance.swift`) pins `NSApp.appearance` to `.darkAqua`.
   - `AppearanceSettings.enforceShellXDarkOnly` pins the stored `appearanceMode` to `dark`.
   - The live apply always synchronizes the terminal theme with the forced appearance (`Sources/AppearanceSettings.swift`, `defaultLiveEnvironment`).
2. **The gallery writes one theme for both appearances.** `TerminalThemeGalleryModel.select(_:)` sets `next.light = name` and `next.dark = name`.

The user's diagnosis is that dark and light themes have different names. "Abernathy" has no light twin, and "Adwaita Dark" pairs with "Adwaita". So ShellX cannot guess the other side. The user has to pick one theme for each appearance.

## Goals

1. The System / Light / Dark menu is ShellX's appearance switch.
   - **Light** and **Dark** force that appearance.
   - **System** follows macOS live.
   - The app chrome, the terminal theme and the built-in browser's page theme all follow it.
2. The terminal uses a **light/dark theme pair**, which Ghostty already supports (`theme = light:X,dark:Y`, `CmuxTerminalThemePair`, `CmuxManagedThemeBlock.encodedThemeValue(light:dark:)`).
3. The gallery assigns by section (**option A, decided by the user**):
   - clicking a card under **Dark Themes** sets the dark theme;
   - clicking under **Light Themes** sets the light theme;
   - each section highlights its own selected card with a small badge (🌙 Dark / ☀ Light);
   - the row subtitle shows both, e.g. "Dark: Abernathy · Light: Solarized Light".
4. Switching appearance swaps the terminal theme live, with no restart, in every open terminal.

## Non-goals

- The App Icon Automatic / Light / Dark options. All three are the same image today; leave them alone.
- Windows and iPhone.
- Per-workspace themes, or schedules such as "light during the day".
- Assigning a light-section theme to the Dark slot, or the reverse. Option A accepts this limit. The CLI `cmux themes set --light/--dark` still allows any pair.

## Anti-goals

- **Unreadable UI in Light.** Unlocking light shows every place that hard-codes dark colors. Examples: white text on white, invisible borders, dark-only images in the sidebar, Settings, popovers, the Automations web page or dialogs. A light mode that looks broken is worse than no light mode.
- **A theme change after updating.** An existing user who never touches the menu must see exactly what they see today.
- **Lost pairs.** A pair written by the CLI or by hand in the Ghostty config must survive. Opening Settings must never collapse it to one theme.

## Decisions (by the user)

- The menu is the appearance switch, and the whole window follows it.
- Gallery assignment works by section (option A).
- **Ship in one go.** Light and System ship only when every native ShellX surface reached in normal use is readable in Light. That covers the window chrome, sidebar, title bar, Settings, popovers, menus, dialogs, sheets, the command palette, the notification and agent UI, and images that exist only in a dark version. There is no hidden or "Beta" Light option and no staged release. The plan lists the full audit, and every item in it is a task.

## Claude's calls (the user agreed to the playback; check these while reading)

- **Menu row:**
  - Rename the row from "Browser Theme" to **"Appearance"** (vi "Giao diện").
  - Move it to the top of Themes.
  - Change its subtitle to say that it switches ShellX, the terminal and web pages.
  - The separate browser page-theme control goes away: web pages follow the appearance.
  - Store the value in the existing app appearance setting (`appearanceMode` / `catalog.app.appearance`, values system / light / dark).
  - **No migration from `browser.theme`.** `enforceShellXDarkOnly` has rewritten `appearanceMode` to dark on every launch, so no user has an explicit appearance today. Migrating `browser.theme=light` would turn their whole window light on update, which breaks the "nothing changes after updating" anti-goal.
  - **`browser.theme` key:** keep reading it so the settings file still validates, but it no longer has any effect, shows no warning, and has no Settings control. Mark it deprecated in the schema and docs, and say the appearance setting replaces it.
- **Default for existing users:**
  - After the update, appearance defaults to **Dark**, so nobody's window turns light by surprise. The old forced value was dark.
  - New installs also default to Dark, which keeps the brand. The user can choose System.
- **Light theme default:**
  - Today's config holds one theme. That theme stays the **dark** theme.
  - The light side gets a readable built-in light theme until the user picks one. Pick a soft, low-contrast-glare light theme that ships with Ghostty.
  - If the existing single theme is itself a light theme, it becomes the light side instead, and the dark side keeps ShellX's default dark.
- **No config write on update:**
  - Updating ShellX never writes the user's Ghostty config.
  - With no `theme =` line, the light side and the dark side resolve to ShellX's defaults in code: today's default dark, and the chosen default light theme. Settings and the CLI must read those same defaults.
  - The first click on a gallery card writes the managed pair block. The clicked side gets the clicked theme. The other side gets the theme it currently resolves to, so nothing else changes.
  - A pair the user wrote by hand or through the CLI is read as is. Clicking a card changes only its own side.
- **Badges for a theme in the "other" section:** a pair from the CLI or by hand can put a light-classified theme in the dark slot, or the reverse.
  - The badge shows on the card in whatever section it is classified into, named after the slot it fills (🌙 Dark or ☀ Light).
  - A card used for both slots shows both badges.
  - The row subtitle always names both sides.
- **"Adapt Default Theme to Appearance" toggle:** remove it from Settings, because the pair replaces it. Keep reading its stored value wherever the no-theme-set path still needs it.
- **Light chrome:** remove the dark-only lock where it applies (`ShellXAppearance`, `enforceShellXDarkOnly`, the forced live apply). Then audit and fix the hard-coded dark colors listed under "Anti-goals". Follow the user's taste: soft colors, primary `#60a5fa`, no gradients.

## Constraints

- **Swift 6.0:** app-linked Swift (`Sources/`, `CLI/` and their packages) must stay Swift 6.0 compatible.
- **Localization:** every user-facing string goes through the catalog, with all 10 locales (`skills/cmux-localization`).
- **Gallery:** the gallery already splits themes into Dark and Light groups by the theme's own background (`TerminalThemeGalleryModel.results`). Option A depends on that classification.
- **Verification:**
  - Verify in a tagged build (`CMUX_TAG=…`). Never touch the user's running `/Applications/ShellX.app`.
  - The user dogfoods before any merge.
  - Commit each failing test before its fix.

## Left to the builder

- How to plumb System → live macOS appearance changes into `NSApp.appearance` and `GhosttyApp.synchronizeThemeWithAppearance`.
- Which built-in light theme becomes the default light side. State the choice in the PR.
- The full list of hard-coded dark colors to fix. Present the audit list in the plan.
- The migration code and its tests: old single theme → pair, and old `browser.theme` → appearance.
- Whether the dark-only code is deleted or reduced to a default.
