### Task 7: ShellX palette, dark-only, terminal defaults, Space Grotesk

**Files (fork):**
- Modify: `Packages/macOS/CmuxFoundation/Sources/CmuxFoundation/Color/CmuxAccentColor.swift:16` (default "cmux" mode color = `ShellXPalette.primary`)
- Modify: `Packages/macOS/CmuxAppKitSupportUI/.../WindowChrome/Sidebar/` `WindowChromeSidebarTintDefaults` (default = `ShellXPalette.panel`, opacity 1.0)
- Modify: `Sources/Sidebar/SidebarAppearanceSupport.swift:167,306,345` (badge = primary; selection = `raise`), `Cells/SidebarWorkspaceRowSupportViews.swift:10` `SidebarRowPalette` (text/textHi/muted)
- Modify: `Sources/Panels/Panel.swift:134` `WorkspaceAttentionFlashAccent.strokeColor` and the notification ring in `Sources/GhosttyTerminalView.swift` (~10601) → `primaryLine`, 1 px
- Modify: `Sources/Sidebar/SidebarCompactStatusGlyph.swift:295` `color()` → error=`error`, needsInput=`primary`, running/subagents/pending=`running`, unseen=`done`, others=`muted`
- Modify: `TerminalAdaptiveDefaultThemeSettings.swift` (built-in default only: background `bg`, cursor `primary`, foreground `text`, ANSI 16 tuned to the palette — record the 16 values in a comment table)
- Modify: app startup (`AppDelegate`) — force `NSApp.appearance = NSAppearance(named: .darkAqua)`; hide the appearance (light/dark/system) setting
- Create: `Resources/Fonts/SpaceGrotesk[wght].ttf` (from `https://github.com/google/fonts/tree/main/ofl/spacegrotesk`, OFL; verify the license file ships beside it) and set `ATSApplicationFontsPath = Fonts` in `Resources/Info.plist`
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXFonts.swift` — `public enum ShellXFonts { public static func display(size: CGFloat, weight: Font.Weight = .bold) -> Font }` ("Space Grotesk", falls back to system if missing)
- Test: `cmuxTests/ShellXThemeTests.swift`

**Interfaces:**
- Consumes: `ShellXPalette`.
- Produces: `ShellXFonts.display(size:weight:)` for the sidebar wordmark (Task 10).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func accentDefaultsToShellXPrimary() { #expect(CmuxAccentColor.default.resolvedHex == "#60a5fa") }
@Test func statusGlyphColors() {
  #expect(SidebarCompactStatusGlyph.color(for: .needsInput).hex == "#60a5fa")
  #expect(SidebarCompactStatusGlyph.color(for: .running).hex == "#e8c468")
  #expect(SidebarCompactStatusGlyph.color(for: .unseen).hex == "#6fd49a")
  #expect(SidebarCompactStatusGlyph.color(for: .error).hex == "#e88a8a")
}
@Test func defaultTerminalThemeUsesPalette() {
  let t = TerminalAdaptiveDefaultThemeSettings.resolve(userConfig: .empty)
  #expect(t.background.hex == "#0b0716" && t.cursor.hex == "#60a5fa")
}
@Test func userGhosttyThemeWins() {   // Review Focus 2
  let t = TerminalAdaptiveDefaultThemeSettings.resolve(userConfig: .init(background: "#ffffff"))
  #expect(t.background.hex == "#ffffff")
}
@Test func appIsDarkOnly() { #expect(ShellXAppearance.forcedAppearanceName == .darkAqua) }
```

Map these onto the real resolver/accessor names; add `hex` helpers on `NSColor` in the test target if needed.

- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXThemeTests` — Expected: FAIL.

- [ ] **Step 3: Make the changes listed under Files.** While there, replace any gradient used on a button or row background with the flat token (Global Constraints); leave gradients that are content fades (e.g. text overflow masks).

- [ ] **Step 4: Run the tests** — Expected: PASS. Build `--tag w1`, launch, and compare by eye against `docs/superpowers/design/2026-10-18-native-desktop/huong-d-mockup.html` (shellx repo): background, sidebar, selection, ring and pills use the palette.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): ShellX palette, dark-only appearance, terminal defaults and Space Grotesk"
```

