### Task 5: Cloud-only features off; device mirroring parked behind `remoteMachines`

**Files (fork):**
- Modify: `Packages/macOS/CmuxCloud/.../Machines/CloudMachinesFeature.swift` (`isAvailable`/`isEnabled` constant `false`)
- Modify: `Sources/Devices/DevicesFeature.swift:35` (no longer depends on Cloud; returns `ShellXFeatures.remoteMachines`)
- Modify: `Sources/Mobile/MobileHostService.swift:756` (`isListeningEnabled` → `ShellXFeatures.remoteMachines`), `Sources/Cloud/PresenceSettings.swift` (`isEnabled` → `ShellXFeatures.remoteMachines`)
- Modify: shortcuts ⌘Y / ⌘⇧Y (`ShortcutAction+Defaults.swift:85-86`, `Sources/KeyboardShortcutSettings.swift:470-476`, routing `AppDelegate.swift:15768-15782,18316`) — remove the defaults and the actions
- Modify: menus `Sources/cmuxApp.swift:931-938`, `Sources/cmuxApp+CloudMenu.swift`, status-item section `AppDelegate.swift:11159` — not shown
- Modify: command palette `Sources/ContentView+AuthCommandPalette.swift` — drop Sign In/Out/team (:12-60) and Cloud commands (:114)
- Modify: `Sources/Cloud/CloudWelcomeWindowController.swift:92` (`shouldPresentAutomatically` → `false`) and remove its Debug menu entry
- Modify: `Sources/VerticalTabsSidebar+EmptyAreasAndFooter.swift:92` `SidebarFooterPresentationPolicy` — no account button, cloud button or Pro badge
- Modify: `RightSidebarMode+Availability.swift:106` (`.machines` unavailable while `remoteMachines == false`)
- Modify: billing refresh after auth callback (`AppDelegate.swift:1615`) and `PricingPlansScreen` / `ProWelcomeChecklist` entry points — unreachable
- Test: `cmuxTests/ShellXCloudOffTests.swift`

**Interfaces:**
- Consumes: `ShellXFeatures.remoteMachines` (Task 1).
- Produces: nothing new; Wave 2 re-enables `DevicesFeature`, `MobileHostService` listening and presence by flipping `remoteMachines` after swapping their transport and auth.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func cloudIsOff() {
  #expect(CloudMachinesFeature.isAvailable == false)
  #expect(DevicesFeature.isAvailable == false)
  #expect(CloudWelcomeWindowController.shouldPresentAutomatically == false)
}
@Test func noCloudShortcutsOrPaletteCommands() {
  let defaults = ShortcutAction.defaultBindings.map(\.keyEquivalentDescription)
  #expect(!defaults.contains("⌘Y") && !defaults.contains("⌘⇧Y"))
  #expect(AuthCommandPalette.commandIDs.isEmpty)
}
@Test func footerHasNoAccountCloudOrPro() {
  let p = SidebarFooterPresentationPolicy.resolve(/* current defaults */)
  #expect(!p.showsAccountButton && !p.showsCloudButton && !p.showsProBadge)
}
```

Use the real member names from those types; add a small accessor where the value is only computed inline.

- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXCloudOffTests` — Expected: FAIL.

- [ ] **Step 3: Make the changes listed under Files.**

- [ ] **Step 4: Run the tests** — Expected: PASS. Build `--tag w1`, launch, and confirm by eye: no Cloud menu, no CloudWelcome window, no account/Pro in the sidebar footer, ⌘Y does nothing.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): switch off cloud, billing and account UI; park device mirroring behind remoteMachines"
```
