### Task 10: Sidebar grouped by machine, status pills, brand header

**Files (fork):**
- Create: `Sources/ShellX/Sidebar/SidebarMachineGrouping.swift` (pure model)
- Create: `Sources/ShellX/Sidebar/SidebarStatusPill.swift` (pure mapping + small AppKit view)
- Create: `Sources/ShellX/Sidebar/SidebarMachineHeaderCellView.swift` (AppKit cell, modelled on `Cells/SidebarGroupHeaderRowView.swift:12`)
- Create: `Sources/ShellX/Sidebar/SidebarBrandHeaderView.swift` (logo + "ShellX" in `ShellXFonts.display(size: 14)`, then "YOUR MACHINES" label with an `Add_Plus` button)
- Modify: `Sources/SidebarWorkspaceRenderItem.swift:13` (add `case machineHeader(SidebarMachineHeaderModel)`)
- Modify: `Sources/ContentView.swift:11745-11936` `WorkspaceListRenderContext` (build machine sections, then reuse the existing `renderItems(...)` per section)
- Modify: `Sources/Sidebar/AppKitList/SidebarWorkspaceTableController.swift` (~1099 `heightOfRow`, ~1130 cell creation) and `SidebarWorkspaceTableRowHeightCalculator.swift` (header row height)
- Modify: `Cells/SidebarWorkspaceRowCellView.swift:892` (show the pill next to the compact glyph)
- Modify: `Sources/FeatureFlags.swift:68` (`isAppKitSidebarListEnabled` always `true`; the legacy SwiftUI list is not extended)
- Test: `cmuxTests/SidebarMachineGroupingTests.swift`, `cmuxTests/SidebarStatusPillTests.swift`

**Interfaces:**
- Consumes: `ShellXIcon` coolicon names (Task 8), `ShellXPalette` (Task 1), `ShellXFonts` (Task 7), `ShellXLogo` (Task 9).
- Produces (Wave 2 extends these with remote devices):

```swift
enum SidebarMachineKey: Hashable { case local; case ssh(target: String) }      // target = remoteDisplayTarget, e.g. "ubuntu@vm01"
struct LocalMachineInfo: Equatable { let name: String; let isLaptop: Bool; static func current() -> LocalMachineInfo }
struct SidebarMachineInput<ID: Hashable>: Equatable { let workspaceID: ID; let sshTarget: String?; let sshConnected: Bool }
struct SidebarMachineHeaderModel: Equatable { let key: SidebarMachineKey; let title: String; let note: String; let coolicon: String; let isOnline: Bool }
struct SidebarMachineSection<ID: Hashable>: Equatable { let header: SidebarMachineHeaderModel; let workspaceIDs: [ID] }
enum SidebarMachineGrouping {
  static func sections<ID: Hashable>(for inputs: [SidebarMachineInput<ID>], local: LocalMachineInfo) -> [SidebarMachineSection<ID>]
}
enum SidebarStatusPill: Equatable { case waiting, running, done, error
  static func from(_ kind: SidebarCompactStatusGlyph.Kind) -> SidebarStatusPill?
  var title: String   // localized: "waiting"/"running"/"done"/"error"; vi "chờ bạn"/"chạy"/"xong"/"lỗi"
  var color: ShellXColor
}
```

Rules: the local section is always first, even with no workspaces; SSH sections follow in order of first appearance; a user workspace group that spans machines shows its group header inside each machine section with only that machine's rows; `LocalMachineInfo.current()` uses `Host.current().localizedName` and `isLaptop` = `sysctl hw.model` contains `MacBook`. Header: local → title = machine name, note = "this Mac" (vi "máy này"), coolicon `Laptop`/`Desktop`, online = true; SSH → title = target, note = "SSH", coolicon `Data`, online = any of its workspaces connected. Pill mapping: `needsInput` → waiting; `running`, `subagents`, `pending` → running; `unseen` → done; `error` → error; everything else → nil.

- [ ] **Step 1: Write the failing tests**

```swift
let mac = LocalMachineInfo(name: "MacBook Pro", isLaptop: true)
@Test func localFirstThenSSHInOrder() {
  let s = SidebarMachineGrouping.sections(for: [
    .init(workspaceID: 1, sshTarget: "ubuntu@vm01", sshConnected: true),
    .init(workspaceID: 2, sshTarget: nil, sshConnected: false),
    .init(workspaceID: 3, sshTarget: "root@vm02", sshConnected: true)], local: mac)
  #expect(s.map(\.header.key) == [.local, .ssh(target: "ubuntu@vm01"), .ssh(target: "root@vm02")])
  #expect(s[0].workspaceIDs == [2])
  #expect(s[0].header.coolicon == "Laptop" && s[1].header.coolicon == "Data")
}
@Test func localSectionShownWhenEmpty() {
  #expect(SidebarMachineGrouping.sections(for: [SidebarMachineInput<Int>](), local: mac).map(\.header.key) == [.local])
}
@Test func disconnectedHostKeepsRowsAndShowsOffline() {   // Review Focus 4
  let s = SidebarMachineGrouping.sections(for: [.init(workspaceID: 7, sshTarget: "ubuntu@vm01", sshConnected: false)], local: mac)
  #expect(s[1].header.isOnline == false && s[1].workspaceIDs == [7])
}
@Test func differentUsersSameHostAreDifferentMachines() {   // Review Focus 4
  let s = SidebarMachineGrouping.sections(for: [
    .init(workspaceID: 1, sshTarget: "ubuntu@vm01", sshConnected: true),
    .init(workspaceID: 2, sshTarget: "root@vm01", sshConnected: true)], local: mac)
  #expect(s.count == 3)
}
@Test func pillMapping() {
  #expect(SidebarStatusPill.from(.needsInput) == .waiting)
  #expect(SidebarStatusPill.from(.subagents) == .running)
  #expect(SidebarStatusPill.from(.unseen) == .done)
  #expect(SidebarStatusPill.from(.idle) == nil)
  #expect(SidebarStatusPill.running.color == ShellXPalette.running)
}
@Test func headerAndRowHeightsIgnoreTextLength() {   // Review Focus 5
  let short = SidebarWorkspaceTableRowHeightCalculator.height(forMachineHeaderTitle: "Mac")
  let long  = SidebarWorkspaceTableRowHeightCalculator.height(forMachineHeaderTitle: String(repeating: "Máy tính văn phòng tầng 3 ", count: 6))
  #expect(short == long)
}
```

- [ ] **Step 2: Run** `scripts/shellx/test-app.sh SidebarMachineGroupingTests SidebarStatusPillTests` — Expected: FAIL.

- [ ] **Step 3: Implement the models, then wire the render items, header cell, pill and brand header.** Labels truncate with `.byTruncatingTail`. New strings: `sidebar.machines.title` ("YOUR MACHINES"), `sidebar.machine.thisMac` ("this Mac"), `sidebar.machine.ssh` ("SSH"), `sidebar.pill.waiting|running|done|error`, `sidebar.machines.add.ssh` ("Add a machine over SSH…") — the `Add_Plus` button opens the existing SSH workspace flow.

- [ ] **Step 4: Run the tests** — Expected: PASS. Build `--tag w1`, open two local workspaces and one SSH workspace; compare with the mockup: brand header, "YOUR MACHINES", a "MacBook … · this Mac" section, an SSH section with `Data` icon, pills colored per palette.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): sidebar grouped by machine with status pills and ShellX brand header"
```

