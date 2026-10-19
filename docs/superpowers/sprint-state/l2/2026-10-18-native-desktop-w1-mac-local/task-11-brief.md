### Task 11: Title bar — sidebar toggle, search, bell, settings

**Files (fork):**
- Create: `Sources/ShellX/Titlebar/ShellXTitlebarAccessory.swift` (AppKit accessory hosting a SwiftUI view)
- Create: `Sources/ShellX/Titlebar/ShellXTitlebarModel.swift` (pure)
- Modify: the window setup that installs titlebar accessories (next to `Update/UpdateTitlebarAccessory.swift`)
- Test: `cmuxTests/ShellXTitlebarModelTests.swift`

**Interfaces:**
- Consumes: existing actions — toggle sidebar (⌘B), open command palette (⌘K / existing palette action), open notifications panel, open settings; `SidebarUnreadModel` unread count; `ShellXIcon`; `ShellXPalette`.
- Produces: `struct ShellXTitlebarModel: Equatable { let unreadCount: Int; var badgeText: String? /* nil for 0, "1"…"9", "9+" */; let searchPlaceholder: String /* "Search sessions, machines, commands…" */ }`.

- [ ] **Step 1: Write the failing test**

```swift
@Test func badgeText() {
  #expect(ShellXTitlebarModel(unreadCount: 0).badgeText == nil)
  #expect(ShellXTitlebarModel(unreadCount: 3).badgeText == "3")
  #expect(ShellXTitlebarModel(unreadCount: 12).badgeText == "9+")
}
```

- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXTitlebarModelTests` — Expected: FAIL.

- [ ] **Step 3: Implement.** Layout per spec §7.1: `Window_Sidebar` button; centered search field look-alike (click or ⌘K opens the palette; `Search_Magnifying_Glass` icon; `⌘K` key cap); `Bell_Ring` with a primary badge; `Settings`. Flat colors only. Keep existing titlebar items that still apply (update accessory).

- [ ] **Step 4: Run the test** — Expected: PASS. Build and check by eye; each button triggers its action.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): ShellX title bar with search, notifications bell and settings"
```

