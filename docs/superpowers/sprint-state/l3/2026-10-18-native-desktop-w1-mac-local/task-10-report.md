# W1 Task 10 report: sidebar grouped by machine, status pills, brand header

Status: DONE_WITH_CONCERNS (app code has not been compiled; see "Unverified symbols" and "Concerns")
Branch: `shellx/l3-sidebar` (worktree `shellx-wt-l3`), not pushed.

Commits:
- `5a81a55625` feat(shellx): pure sidebar machine grouping and status pill models in ShellXBrand
- `8f21bed177` feat(shellx): sidebar grouped by machine with status pills and ShellX brand header

## What was implemented

### Package (pure, AppKit-free, `public`, Swift 6 mode)
`Packages/Shared/ShellXBrand/Sources/ShellXBrand/Sidebar/`
- `SidebarMachineGrouping.swift`
  - `SidebarMachineKey: Hashable, Sendable { case local; case ssh(target:) }` plus `stableID: UUID` (deterministic FNV-1a based UUID, used for row identity).
  - `LocalMachineInfo: Equatable, Sendable { name, isLaptop }`, `current()` (probed once per process and cached), `isLaptop(hardwareModel:hasInternalBattery:)`.
  - `SidebarMachineInput<ID: Hashable & Sendable>: Equatable, Sendable { workspaceID, sshTarget, sshConnected }`.
  - `SidebarMachineLabels { thisMac, ssh }`, with `.english`, passed in so the model needs no bundle.
  - `SidebarMachineHeaderModel: Hashable, Sendable { key, title, note, coolicon, isOnline }`.
  - `SidebarMachineSection<ID> { header, workspaceIDs }`.
  - `SidebarMachineGrouping.sections(for:local:labels: = .english)`. Rules: the local section always comes first, even when it is empty. SSH sections follow in the order each one first appears. The key is the trimmed target, so `user@host` is the machine identity and a blank target counts as local. A local header gets title = machine name, note = "this Mac", coolicon `Laptop` or `Desktop`, online = true. An SSH header gets title = target, note = "SSH", coolicon `Data`, online = any of its workspaces connected.
- `SidebarStatusPill.swift`
  - `SidebarStatusPill: CaseIterable, Sendable { waiting, running, done, error }`, `color` (primary/running/done/error), `textColor` (waiting uses primaryText, per the mockup's `.p-wait`), `fillAlpha = 0.12`, `title` (`String(localized:defaultValue:bundle: .main)` so the app catalog localizes it).
  - `SidebarMachineHeaderLayout.height` (28) and `height(forTitle:)` (returns the constant).
- No change to `Package.swift`.

W2 extensibility: adding `case remote(machineID:)` to `SidebarMachineKey` only needs a new `stableID` seed. `SidebarMachineInput` can gain `remoteMachineID: String? = nil` without breaking callers. A `sections(for:local:remote:now:)` overload can wrap the existing grouping, which keeps no state. The app's `SidebarMachineSectionRenderItems` only iterates sections and reads `header.key.stableID`, so a new key case needs no app switch changes.

### App (`Sources/ShellX/Sidebar/`, all wired into the cmux target with `scripts/wire-app-sources.py`)
- `SidebarStatusPill+CompactGlyph.swift`: `SidebarStatusPill.from(_ kind: SidebarCompactStatusGlyph.Kind)` is an exhaustive switch. needsInput maps to waiting; running, subagents and pending map to running; unseen maps to done; error maps to error; waiting, pullRequest, idle, branch and terminal map to nil.
- `SidebarStatusPillView.swift`: a capsule drawn directly in the view, with the status color at 12% as fill and the status color as text. No border, gradient or shadow.
- `ShellXSidebarHeaderRow.swift`: `enum ShellXSidebarHeaderRow { case brand; case machine(SidebarMachineHeaderModel) }` with `rowHeight`, `rowId` and `placeholderWorkspaceId`. The placeholder is a UUID that matches no workspace, so close, selection and drop lookups find nothing. Also holds `ShellXSidebarHeaderMetrics`, the `ShellXSidebarHeaderCell` protocol, and the `ShellXSidebarHeaderCells.cell(for:in:owner:)` factory.
- `SidebarMachineHeaderCellView.swift`: AppKit `NSTableCellView` modelled on `SidebarGroupHeaderTableCellView` (manual layout). Shows the icon, then "title · note" in one tail-truncating label, then an online dot (`ShellXPalette.done`, or `muted` when offline). The dot has an accessibility label (Online/Offline).
- `SidebarBrandHeaderView.swift`: `SidebarBrandHeaderCellView` is the first table row. It shows the logo (`NSApp.applicationIconImage`) and `ShellXBrand.appName` in `systemFont(14, .semibold)`, then "YOUR MACHINES" with an `Add_Plus` button (`SidebarHeaderGlyphButton`). Also `ShellXAddMachinePrompt`: an NSAlert with a `user@host` field that hands `ssh://<target>` to `AppDelegate.shared?.handleCmuxSSHURLs(from:)`, the existing SSH link flow (managed-policy check, trust confirmation, `cmux ssh` launch).
- `ShellXSidebarIcon.swift`: returns `NSImage(named: coolicon)` if the asset exists, else an SF Symbol template (laptopcomputer, desktopcomputer, server.rack, plus).
- `SidebarMachineSectionRenderItems.swift`: `SidebarMachineInput<UUID>(workspace:)` (sshTarget = `remoteDisplayTarget`, connected = `remoteConnectionState == .connected`), `SidebarMachineLabels.localized`, and `SidebarMachineSectionRenderItems.renderItems(tabs:groupsById:orderedGroups:effectiveMembership:local:)`.
- Each `// ShellX: swap for ShellXIcon/ShellXFonts/ShellXLogo after W1 Tasks 7-9 merge` note sits where the logo, font and coolicons are used: `ShellXSidebarIcon.swift:5` and `SidebarBrandHeaderView.swift:23,28,48`.

## How render items, heights and cells are wired (upstream edits, each marked `// ShellX:`)
- Render items: `Sources/SidebarWorkspaceRenderItem.swift:17` adds `case machineHeader(SidebarMachineHeaderModel)`. Its `id` (`:26`) is `.machine(stableID)` and its `rowWorkspaceId` (`:37`) is `stableID`, which matches no workspace. The pin-tier closure gets the new case (`:167`). `numberedWorkspaceIds(tabs:groupsById:)` (`:210`, which backs ⌘1–9) now numbers rows in machine-grouped order, so it agrees with the row hints.
- Per-section `renderItems(...)`: `SidebarMachineSectionRenderItems.renderItems` (`Sources/ShellX/Sidebar/SidebarMachineSectionRenderItems.swift:32-70`) emits, for each section, `.machineHeader` and then the existing `SidebarWorkspaceRenderItem.renderItems(...)` over only that section's tabs. It passes the global effective membership restricted to those tabs, and `groupsById`/`orderedGroups` filtered to the groups referenced in that section. Groups no section references (durable empty groups) stay with the local section, so empty headers are not emitted once per section. A group that spans machines therefore shows its header in each section that holds one of its rows, with only that section's rows. Members of a collapsed group stay hidden everywhere.
- `Sources/ContentView.swift:11900`: `WorkspaceListRenderContext` builds `workspaceRenderItems` with the sectioned builder.
- Unique row identity for a group header repeated in another section: `Sources/SidebarWorkspaceRenderItemID.swift:11` adds one optional `machineSection` field (included in `==` and `hash`). `.group(id, repeatedInMachineSection:)` is at `:31`, `.machine(_:)` at `:24`, and `.shellXBrandHeader` at `:41`. `Sources/ContentView.swift:12522-12552` builds the table rows. It prepends the brand row and maps `.machineHeader` to a header row. The first appearance of a group header keeps `.group(id)`; each repeat is re-identified with `.group(id, repeatedInMachineSection: <that section's stableID>)`. This goes through `SidebarWorkspaceTableRowConfiguration.reidentifiedGroupHeader(as:)` (`SidebarWorkspaceTableRowConfiguration.swift:207`). The group-header init gained `rowId:` (`:123`), and `applyingUnreadSnapshot` passes `rowId: id` (`:263`) so the per-section identity survives unread repaints. The ordinary single-machine case is unchanged.
- Row configuration: `shellXHeaderRow` (`SidebarWorkspaceTableRowConfiguration.swift:41`) and `init(shellXHeader:environment:)` (`:186`). `presentationSnapshot` keeps it (`:285`) and `estimatedHeight` returns the fixed height (`:292`).
- Heights: `SidebarWorkspaceTableRowHeightCalculator.height(forMachineHeaderTitle:)` (`SidebarWorkspaceTableRowHeightCalculator.swift:28`) delegates to the package constant. `SidebarWorkspaceTableRowHeightCache.measureHostedRow` returns `shellXHeaderRow.rowHeight` (`SidebarWorkspaceTableRowHeightCache.swift:181`), so `heightOfRow` (controller `:1099`, unchanged) reads it through the cache or the estimate.
- Cells: controller `viewFor` (`SidebarWorkspaceTableController.swift:1128`) calls `ShellXSidebarHeaderCells.cell(...)`. `reconfigureVisibleRows` has a `ShellXSidebarHeaderCell` case (`:2525`) so an online/offline flip repaints in place.
- Header rows are inert:
  - `pasteboardWriterForRow` returns nil for them (`:1180`).
  - They are filtered out of the reorder drop targets (`:1947`) and the bonsplit drop targets (`SidebarWorkspaceTableDropTargetGeometryGate.swift:51`).
  - Click dispatch already returns `.invalid` for rows with no models or actions.
  - Middle-click close looks up the placeholder id and finds nothing.
  - Double-click needs a workspace model.
- Pill: `SidebarWorkspaceRowCellView.swift:38/334/901/1345-1358`. The pill is configured next to the compact glyph from `glyph?.kind` and laid out at the title line's trailing edge, before the close/badge slot (as in the mockup's `.right`). The title width shrinks by the pill's width. Row height is unaffected, because the pill only exists in compact mode, where the title is already one line.
- Flag: `Sources/FeatureFlags.swift:380` makes `isAppKitSidebarListEnabled` always `true`. The legacy SwiftUI `ForEach` only got `case .machineHeader: EmptyView()` (`ContentView.swift:14481`).
- `cmuxTests/WorkspaceGroupTests.swift:213`: added the new case to an exhaustive switch.
- `cmux.xcodeproj`:
  - 7 app files wired via `wire-app-sources.py`.
  - 2 test files wired via `sync-test-wiring`.
  - The existing `ShellXBrand` product dependency added to cmuxTests' `packageProductDependencies` (one line, the same pattern as CmuxWorkspaces: not in its Frameworks phase), so the cmuxTests files can `import ShellXBrand`.

## TDD evidence (package)
RED (models absent):
```
$ swift test --package-path Packages/Shared/ShellXBrand
.../SidebarMachineModelTests.swift:121:23: error: cannot find 'LocalMachineInfo' in scope
.../SidebarMachineModelTests.swift:123:28: error: cannot find 'LocalMachineInfo' in scope
error: fatalError
```
GREEN (final run, after the last change):
```
$ swift test --package-path Packages/Shared/ShellXBrand
✔ Suite SidebarMachineModelTests passed
✔ Suite SidebarStatusPillModelTests passed
✔ Test run with 23 tests in 3 suites passed after 0.004 seconds.
```
`swift build` of the package shows no warnings.

Package tests (`Tests/ShellXBrandTests/SidebarMachineModelTests.swift`, `SidebarStatusPillModelTests.swift`):
- Brief cases: localFirstThenSSHInOrder, localSectionShownWhenEmpty, disconnectedHostKeepsRowsAndShowsOffline, differentUsersSameHostAreDifferentMachines, pill colors, pill titles, headerHeightIgnoresTextLength.
- Extra cases: an SSH machine is online when any of its workspaces is; per-machine order is kept; a blank target counts as local; local and desktop header note/icon; SSH header title/note/icon; injectable labels; stable IDs; laptop detection; current machine has a name.

App-side tests (written, wired, not run this sprint):
- `cmuxTests/SidebarStatusPillTests.swift`: pillMapping via `from(_:)`, plus `headerAndRowHeightsIgnoreTextLength` via `SidebarWorkspaceTableRowHeightCalculator.height(forMachineHeaderTitle:)`.
- `cmuxTests/SidebarMachineGroupingTests.swift`: a repeated group header's ids are distinct per section; header row ids do not collide with workspace or group rows.

The group-spanning-machines rule is covered only through the app code (it needs `Workspace` instances); the package covers the grouping it builds on.

## Verification
- `python3 scripts/verify-local.py --all --swift-changed main` passed 16/16. That run includes swift-syntax over 29 changed files, xcstrings, localization parity, localization-defaults (6852 comparisons, 0 mismatches), project, test-wiring, wire-app-sources and feature-flags.
- `tests/test_shellx_*.py` pass.
- `python3 scripts/localization_catalog.py check` reports 10 catalogs, 9 locales, 0 parity errors.
- No xcodebuild, reload.sh or test-app.sh was run, per the rulings.

## Localization
13 new keys in `Resources/Localizable.xcstrings`, each with en, de, fr, ar, es, zh-Hant, zh-Hans, ko and ja, plus vi:
- `sidebar.machines.title` (vi "Máy của bạn")
- `sidebar.machine.thisMac` ("máy này")
- `sidebar.machine.ssh` ("SSH"; recorded as a technical omission in `scripts/localization-allowed-omissions.json`, so en, ja and vi only, the same treatment as `menu.help.ssh`)
- `sidebar.pill.waiting|running|done|error` ("chờ bạn", "chạy", "xong", "lỗi")
- `sidebar.machines.add.ssh` ("Thêm máy qua SSH…")
- `sidebar.machines.add.ssh.title`, `.message` and `.connect` (the prompt dialog)
- `sidebar.machine.online` and `sidebar.machine.offline` (accessibility labels for the online dot)

Cancel reuses `common.cancel`. `vi` is accepted by the catalog check, because it only validates the 9 required locales and extra locales such as `uk` already exist. `vi` is not in the pbxproj `knownRegions`, and neither is `uk`. Whether vi actually ships at runtime is untested.

`./scripts/localize-changes` cannot run on this branch. It fails reading `web/i18n/routing.ts`, which was removed together with cmux's `web/`. I added the entries with the tool's own helpers (`localize_changes.insert_catalog_entry` and `localization_catalog.merge_text`) through a scratch script, so formatting and validation match the tool.

## Symbols used by app code that could not be verified by compilation
These were all checked by grep against their declarations, but none has been compiled:
- `Workspace.remoteDisplayTarget`, `.remoteConnectionState`, and `WorkspaceRemoteConnectionState.connected` (CmuxCore, imported).
- `SidebarHeaderGlyphButton()`, `.glyphImage`, `.onClick` and `.setRevealed(_:)`.
- `AppDelegate.shared?.handleCmuxSSHURLs(from:) -> Bool` and `SidebarWorkspaceListMetrics.rowOuterHorizontalPadding/rowContentHorizontalPadding`.
- `SidebarCompactStatusGlyph.Kind` cases, including `.pullRequest(PullRequestState)`, and `model.fontScale: CGFloat`.
- The private memberwise init of `SidebarWorkspaceRenderItemID` with the defaulted `machineSection` var.
- The private designated init of `SidebarWorkspaceTableRowConfiguration`, called from the new delegating init.
- The protocol-existential pattern `case let cell as ShellXSidebarHeaderCell` in the controller switch, where the protocol has an NSView superclass constraint.
- `SidebarMachineInput<UUID>(workspace:)` from a constrained extension on a generic struct in another module.
- `[brandHeaderRow] + ...compactMap { ... }` with captured `var`s mutated inside the closure.
- The cmuxTests `@MainActor` suites calling the `@MainActor` `SidebarWorkspaceRenderItem.id`.
- The ShellXBrand package compiles under Swift 6. The app files are written for Swift 5 mode.

## Concerns / deviations
1. **Laptop rule deviation.** The brief's rule (`hw.model` contains "MacBook") is false on this very MacBook Pro: `hw.model` is `Mac14,7`, as on all Apple silicon. `isLaptop` is now `hw.model contains "MacBook" || internal battery present` (IOKit power sources). The name comes from `SCDynamicStoreCopyComputerName` first, then `Host.current().localizedName`, because `Host.current()` can block on DNS on the main thread. Both are probed once per process. ShellXBrand now autolinks IOKit and SystemConfiguration, and the cmux-cli target links ShellXBrand too. Both are system frameworks.
2. **"Opens the existing SSH workspace flow".** The app has no in-app "new SSH workspace" UI. The existing flow is ssh:// links and `cmux ssh`. I added a small host prompt that feeds an `ssh://` link into `handleCmuxSSHURLs`, which brings its own trust dialog. That adds 3 strings. If you want a different entry point (command palette, docs), it is a single function to swap: `ShellXAddMachinePrompt.present()`.
3. **Pills follow the compact glyph, so they show only when `sidebar.compactAgentStatus` is on**, and that setting defaults to off. Showing them by default needs either that default flipped or a separate status source.
4. **Brand header is the first table row, so it scrolls with the list.** A pinned header would mean reworking the table's top inset, scrim and titlebar overlays. Header text uses system label colors so light mode stays readable. The pill and dot colors are the dark palette tokens, so the yellow pill is low-contrast in light mode.
5. **Reordering across sections.** Drag reorder still moves workspaces in the global tab order, and a row stays in its own machine section. Dropping a workspace among another machine's rows reorders it but does not move it to that machine. Keyboard next/previous workspace still follows tab order. ⌘1–9 now follows section order, consistent with the hints.
6. **Hidden sidebar pruning.** While the sidebar is hidden, the live row ids passed by ContentView are groups and tabs only, so header rows and repeated group headers are pruned and rebuilt on reveal (a forced reload). This is harmless but costs one extra reload.
7. **Test behaviour changes.** Forcing the AppKit list means `cmuxTests/SidebarSnapshotOwnerTests.swift:67`, which overrides the flag to `false`, no longer reaches the SwiftUI path. Any cmuxTests that count sidebar rows will now see the brand and machine header rows. None of these tests are executed this sprint, so expect failures when cmuxTests next runs.
8. The online/offline dot updates only when the sidebar body re-renders. I did not add a new observation of `remoteConnectionState`; existing row observation is expected to trigger it.
9. Catalog entries have no `comment` field, matching the Swift call sites, which pass no `comment:`.

---

## Fix round 1 (commit `fa28dda193`)

Status: DONE. The app code is still not compiled locally; CI is the first build.

1. **Pills shown with default settings (spec §7.1 ruling).**
   - `SidebarWorkspaceSnapshotBuilder.swift:100` adds `statusPillGlyphKind: SidebarCompactStatusGlyph.Kind?` to the snapshot (marked).
   - `SidebarWorkspaceSnapshotFactory.swift:156-172` fills it with `compactStatusGlyph?.kind` when compact mode is on. When compact mode is off, it runs a lean `SidebarCompactStatusGlyph.resolve(Input(agentEntries:lifecycleStates:hasActiveAgent:))`.
   - Cost per row per snapshot, only when compact mode is off:
     - one `partition` pass over the status entries, reusing `statusEntries.rows` (already sorted when metadata is shown; it only fetches and sorts them again when metadata is hidden);
     - a flatMap over the panels' lifecycle states;
     - building a tooltip string from the agent entries.
     - There are no pull-request, branch or directory lookups, and those states map to no pill anyway.
   - The leading compact glyph stays gated exactly as upstream (`compactStatusGlyph` unchanged).
   - The cell (`SidebarWorkspaceRowCellView.swift:900-905`) uses the compact glyph when there is one. Otherwise it builds `SidebarCompactStatusGlyph(kind: statusPillGlyphKind ?? .terminal, tooltip: "").applyingUnread(model.unreadCount, …)`, so unread still turns a settled row into `.unseen`, which shows as "done".
2. **Uppercase section label.** `SidebarBrandHeaderView.swift:41` uses `.uppercased(with: .current)`, giving "YOUR MACHINES" and "MÁY CỦA BẠN". Catalog values are unchanged (vi stays "Máy của bạn"), so the rule is "uppercase at render".
3. **Waiting ring.** `SidebarStatusPillView.swift:64-73` adds a 1 px `ShellXPalette.primaryLine` stroke, inset 0.5, drawn for `.waiting` only.
4. **App-side grouping tests.**
   - The repeat-id logic moved out of ContentView into the pure `SidebarMachineSectionRenderItems.rowIds(for:)` (`SidebarMachineSectionRenderItems.swift:77`). ContentView zips items with it (`ContentView.swift:12528-12548`).
   - New cmuxTests cases in `cmuxTests/SidebarMachineGroupingTests.swift`, built on real Workspaces through `TabManager` as in `WorkspaceGroupTests`. SSH is simulated by setting `remoteConfiguration` only, with no connection.
     - `machineInputReadsSSHTargetAndConnection`
     - `localSectionComesFirstThenSSHMachines`
     - `groupSpanningMachinesShowsItsHeaderInEachSectionWithOnlyThatSectionsRows`: header in both sections, the SSH member only under SSH, the anchor never as a row, unique row ids including the per-section repeat.
     - `durableEmptyGroupStaysInTheLocalSection`
     - `rowIdsForSingleMachineMatchItemIds`
   - New cases in `cmuxTests/SidebarStatusPillTests.swift`:
     - `snapshotCarriesPillStateWhenCompactStatusIsOff`: an error agent entry gives pill state `.error` with compact mode off and no glyph, and the pill state equals the glyph kind with compact mode on.
     - `unreadTurnsASettledRowDone`
   - These were not executed (cmuxTests is not built this sprint).
5. **Truncation.** The machine header title and note (`SidebarMachineHeaderCellView.swift:66-82`) and the section label (`SidebarBrandHeaderView.swift:37-50`) carry an `NSParagraphStyle` with `.byTruncatingTail`. The fields keep `lineBreakMode = .byTruncatingTail` and `maximumNumberOfLines = 1`; the section field also gets `truncatesLastVisibleLine`.
6. **Offline dot refresh, traced; no new observation needed.** The chain:
   - `Workspace.$remoteConnectionState` is part of `sidebarObservationPublisher` (`WorkspaceSidebarObservation.swift:345-349`, CombineLatest of `remoteFields`).
   - `VerticalTabsSidebar` subscribes for every workspace, not only the selected one, via `.sidebarWorkspaceObservations(ids: renderContext.workspaceIds, …)` (`ContentView.swift:12094-12100`) → `scheduleWorkspaceSnapshotRefresh` (`:13176`) → `refreshWorkspaceSnapshots` → `workspaceSnapshotCache.refresh` (`:13202`).
   - The snapshot changes whenever the state changes, because `remoteConnectionStatusText` switches on `workspace.remoteConnectionState` (`SidebarWorkspaceSnapshotFactory.swift:313-327`) and `showsRemoteReconnectAffordance` reads it too. So `SidebarRowSnapshotCache.revision` bumps (`Sidebar/SidebarRowSnapshotCache.swift:55-64`).
   - `revision` is `@Observable`-tracked. The body reads it through `workspaceSnapshotCache.value(for:)` in `workspaceRowInput` (`ContentView.swift:15261`), which `appKitWorkspaceTableRows` calls during body evaluation. The body therefore re-runs and rebuilds `SidebarMachineSectionRenderItems.renderItems`, which reads each workspace's live `remoteConnectionState`, so the header's `isOnline` updates.
   - Caveat (upstream behaviour): the refresh is skipped while the sidebar is hidden (`sidebarState.isVisible`). The next reveal rebuilds everything anyway.
7. **cmuxTests package dependency.** cmuxTests now has its own product-dependency object `5E11A00000000000000000A4`, which points at the same `XCLocalSwiftPackageReference` `…A0` and is listed only in cmuxTests' `packageProductDependencies`, not in its Frameworks phase. This mirrors CmuxWorkspaces: cmuxTests uses `5E27010400000000000000A4`, a separate object from the app's `E3B7A3000000000000000102`, and is not in cmuxTests' Frameworks phase. So the test bundle can import the module but does not link a second copy; the symbols come from the host app. `check-pbxproj.sh` passes.
8. **Palette text.**
   - Machine title: `textHi`. Note and icon tint: `muted`.
   - Brand name: `textHi`. Section label and add-button tint: `muted`.
   - No `labelColor` or `secondaryLabelColor` remains under `Sources/ShellX/Sidebar`.

Verification:
```
$ swift test --package-path Packages/Shared/ShellXBrand
✔ Test run with 23 tests in 3 suites passed
$ python3 scripts/verify-local.py --all --swift-changed main
PASSED swift-syntax (31 selected files) … PASSED: 16/16 selected checks ran.
```
No new strings, so the catalog is unchanged; localization and localization-defaults pass.
