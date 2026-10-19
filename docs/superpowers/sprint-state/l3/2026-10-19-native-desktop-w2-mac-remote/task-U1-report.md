# W2 Task U1 report: remote machine groups and sign-in in the sidebar

Status: DONE_WITH_CONCERNS. The package logic is tested (70/70 green). The app code has not been compiled; CI will be its first build (ruling 5).
Branch: `shellx/l3-sidebar` (worktree `shellx-wt-l3`), not pushed.

Commits:
- `606cd222da` feat(shellx): pure remote machine sections, snapshot and sign-in error mapping in ShellXRemoteUI
- `fe8dfc2e1e` feat(shellx): remote machine groups and sign-in in the sidebar

## What was implemented

### ShellXBrand (pure, no ShellXRemoteCore dependency)
`Packages/Shared/ShellXBrand/Sources/ShellXBrand/Sidebar/SidebarMachineGrouping.swift`
- `SidebarMachineKey.remote(machineID:)`. Its `stableID` seed is `"shellx.machine.remote:" + id`.
- `SidebarMachineInput.remoteMachineID: String?`, defaulting to nil in the init.
- `SidebarMachineHeaderAction: Hashable, Sendable { requestAccess, waiting(code:), open, reconnecting, connecting }`. It is Hashable, not just Equatable, because the header model is Hashable.
- `SidebarMachineHeaderModel.isDimmed` (default false) and `.action` (default nil). Existing callers are unchanged.
- `SidebarRemoteSectionDescriptor { machineID, header, showsRows }`: a module-neutral descriptor for one remote section.
- `SidebarMachineGrouping.sections(for:local:remote: [SidebarRemoteSectionDescriptor], labels:)`. Order is local, then the remote sections in descriptor order, then SSH; the first descriptor wins when an id repeats.
  - A workspace whose `remoteMachineID` matches a descriptor goes under that machine, or is hidden when `showsRows == false`.
  - A workspace that names an unknown machine falls back to the usual SSH or local grouping, so it never disappears.
- W1's `sections(for:local:labels:)` is now a wrapper that passes `remote: []`. The W1 tests pass unchanged.

### ShellXRemoteUI (new target and product; depends on ShellXBrand and ShellXRemoteCore; imports Foundation only)
`Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/`
- `RemoteMachineSections.swift`
  - `RemoteMachineLabels { offlineLastSeen (format with %@), neverSeen }` with an `.english` default.
  - `ordered(_:)`: `isThisMachine` is dropped; online machines come before offline ones; each group is sorted by `localizedStandardCompare`, then by id.
  - `coolicon(for:)`: macos → Laptop, windows → Desktop.
  - `action(for:)` follows the brief, plus the rules in "Decisions" below.
  - `lastSeenText`: 24 h "HH:mm" in an injected time zone, or "—".
  - `header(for:labels:timeZone:)`:
    - online: note "", dot `done`, not dimmed.
    - offline: note "offline · last seen HH:mm" built with `String(format:)`, dimmed.
  - `descriptors(...)`: offline machines get `showsRows = false`.
  - The extension `SidebarMachineGrouping.sections(for:local:remote: [RemoteMachine], now:, labels: = .english, remoteLabels: = .english, timeZone: = .current)`.
- `RemoteUISnapshot.swift`
  - `RemoteUISnapshot` is a struct (Equatable, Sendable) with the brief's fields, all defaulted.
  - It adds `.signedOut` and `remoteMachineID(forWorkspace:)`.
- `SignInErrorMessage.swift`
  - `SignInErrorLabels` has an `.english` default.
  - `SignInErrorMessage.text(forCode:labels:)` maps `invalid_credentials` to the credentials text, `network` to the network text, and returns any other code as is.
  - `text(for: any Error, labels:)` does the same for a `ShellXCoreError`. Any other error is shown as the network text.
- `Package.swift` adds the `ShellXRemoteUI` product and target and the `ShellXRemoteUITests` test target.

### App (`Sources/ShellX/Remote/UI/`, wired into the cmux target with `scripts/wire-app-sources.py`)
- `ShellXRemoteServicing.swift`
  - `@MainActor protocol ShellXRemoteServicing: AnyObject`: the K4 members as get-only properties, plus `changePublisher: AnyPublisher<Void, Never>`.
    - A constrained extension supplies `changePublisher` from `objectWillChange` for any `ObservableObject` with `ObservableObjectPublisher`. The real service will only need to declare the conformance.
  - `ShellXRemoteUIGate.isEnabled = ShellXFeatures.remoteMachines || usesFixtures`. `usesFixtures` is DEBUG with `SHELLX_REMOTE_UI_FIXTURES == "1"`.
  - `ShellXRemoteServiceProvider.makeService()` returns the fixture in that DEBUG case and nil otherwise. The note `// ShellX: bind ShellXRemoteService.shared here when L5 Task 13 lands` is at :70.
  - `ShellXRemoteUIModel.shared` (`ObservableObject`) has `service` and `@Published snapshot: RemoteUISnapshot?`.
    - `snapshot` is nil while the gate is off, and the model never publishes then.
    - It refreshes on the main queue after `changePublisher` fires, and only publishes when the snapshot changes.
    - `showsSignInRow` is true when the gate is on and the user is signed out.
- `RemoteUISnapshot.swift`
  - `RemoteUISnapshot(service:)`, which also filters out `isThisMachine`.
  - `RemoteMachineLabels.localized` and `SignInErrorLabels.localized`.
- `ShellXRemoteFixtureService.swift` (DEBUG only)
  - Starts signed out.
  - `signIn` accepts any non-empty email and password except "wrong". "wrong" or an empty field throws `ShellXCoreError(code: "invalid_credentials")`.
  - Signed in, it serves:
    - an online, granted "PC Windows · văn phòng" (windows, matching the mockup);
    - an offline "Mac mini" with `lastSeen` set to 3 h ago;
    - "MacBook Air" with `.requested(pairingID: "p1", code: "123456")`;
    - "Mac Studio", online with `.none`. This one is extra, so the "Request access" button shows.
  - `requestAccess` flips that machine to requested and returns "123456".
  - `openSession` goes from connecting to connected after 0.8 s, so "connecting…" shows.
- `ShellXRemoteUIActions.swift`
  - `requestAccess(to:)` calls the service, then the U2 hook `presentRequestAccess: ((machineID, code) -> Void)?`, at the line marked `// ShellX: present RequestAccessSheet (U2)`.
  - `openSession(on:)` and `presentSignIn()`. A failure beeps.
  - `handleClick(on: ShellXSidebarHeaderRow) -> Bool`: the sign-in row opens the sheet, and a `.remote` header with action `.open` opens a session.
- `SignInSheet.swift`
  - `SignInSheetModel` holds email, password, `errorText` (from the mapping) and `isSubmitting`.
  - `SignInSheet` (SwiftUI):
    - The title is `remote.signin.title`, followed by a TextField (`remote.signin.email`) and a SecureField (`remote.signin.password`; Return submits).
    - Errors show inline in `ShellXPalette.error`.
    - Buttons are secondary Cancel (`common.cancel`) and primary `remote.signin.submit`, with a spinner while the request runs.
    - The sheet is dark only.
  - `ShellXSheetButtonStyle`: the primary style is a primarySoft fill, a 1 px primaryLine border and primaryText; the secondary style is raise + border + text. No gradients.
  - `SignInSheetPresenter`: one sheet at a time, built on the existing `CloudSheetWindow` and `NSApp.cmuxMainWindowForModalPresentation`, the same pattern as `CloudNetworkPolicySheetPresenter`.

### Sidebar (W1 files)
- `ShellXSidebarHeaderRow.swift`
  - Adds `case signIn`, with a fixed height equal to `SidebarMachineHeaderLayout.height`, row id `.shellXSignInRow`, and a placeholder UUID that matches no workspace.
  - The cell factory has a `.signIn` case, and the metrics gain `signInHeight` and `actionButtonHeight`.
- `SidebarMachineHeaderCellView.swift`
  - An empty note drops " · ".
  - `alphaValue` is 0.5 when `isDimmed` (:104).
  - Trailing action (`configureAction` :120):
    - `.requestAccess` shows a `ShellXSidebarActionButton` (primarySoft / primaryLine / primaryText, 18 px tall, drawn flat), which calls `ShellXRemoteUIActions.requestAccess` (:163).
    - `.waiting(code)`, `.connecting` and `.reconnecting` show muted text with `remote.machine.waiting` (`String(format:)`), `.connecting` and `.reconnecting`.
    - The action takes at most 45 % of the row width; the title shrinks first and truncates.
  - All labels use `.byTruncatingTail`, set both as a paragraph style and as the field's line-break mode.
- `SidebarBrandHeaderView.swift`: `SidebarSignInRowCellView` (:127) shows a "User_Circle" icon (SF fallback `person.crop.circle`) and the `remote.signin.row` text in primaryText. It has the accessibility role `.button`, and `accessibilityPerformPress` opens the sheet.
- `SidebarMachineSectionRenderItems.swift`
  - `SidebarMachineInput(workspace:remoteMachineID:)`.
  - The new overload `renderItems(..., remote: RemoteUISnapshot?)` (:56). When signed in, it uses the RemoteUI grouping, which takes `remoteMachineID` from `remoteWorkspaces`, with the localized labels and `now: Date()`. When `remote` is nil or the user is signed out, it runs the exact W1 call.
  - The old signature (:36) passes `ShellXRemoteUIModel.shared.snapshot`, so ⌘1–9 numbering (`numberedWorkspaceIds`) matches the sidebar.
- `ShellXSidebarIcon.swift` gains the `User_Circle` fallback.

## Upstream edits (wiring only, each marked `// ShellX:`)
- `Sources/ContentView.swift`
  - :11399 adds `@ObservedObject private var shellXRemoteUI = ShellXRemoteUIModel.shared` to `VerticalTabsSidebar`. This follows the existing `.shared` observer pattern, and the Equatable gate is bypassed by design.
  - :11902 passes `remote: shellXRemoteUI.snapshot` to `renderItems`.
  - :12531 inserts the sign-in row after the brand row when `showsSignInRow` is true: `[brandHeaderRow] + signInRows + …`.
- `Sources/Sidebar/AppKitList/SidebarWorkspaceTableController.swift:1043`: in `dispatchRowClick`, before `return .invalid`, a ShellX header row is routed to `ShellXRemoteUIActions.handleClick`. That function returns `.dispatched` when it acted.
- `Sources/SidebarWorkspaceRenderItemID.swift:43`: adds `shellXSignInRowUUID` and `.shellXSignInRow` (kind 5).
- `cmux.xcodeproj/project.pbxproj`
  - The 5 new app files were added by `wire-app-sources.py`.
  - The `ShellXRemoteUI` product is linked into the cmux app, copying L5's 58a0573d25 pattern:
    - `5E13C3000000000000000011` is the PBXBuildFile in the app Frameworks phase (:3344, :9333).
    - `5E13C3000000000000000010` is the XCSwiftPackageProductDependency (:20604), listed in the app's packageProductDependencies (:14134).
  - `normalize-pbxproj.py` was run, and `check-pbxproj.sh` exits 0.

## Gate off = W1 sidebar
- With `ShellXFeatures.remoteMachines == false` (unchanged) and no env var, `makeService()` returns nil and `snapshot` stays nil. As a result:
  - `showsSignInRow` is false;
  - `renderItems` takes the W1 branch, with the same call and labels;
  - the model never publishes, so no extra renders happen.
- Release builds contain no fixture code (`#if DEBUG`).

## TDD evidence (package; full logs under `u1-evidence/`)
RED (`u1-evidence/red-1.txt`): tests written, models not yet present:
```
$ swift test --package-path Packages/Shared/ShellXBrand
.../SidebarMachineRemoteSectionTests.swift:8:115: error: cannot find type 'SidebarRemoteSectionDescriptor' in scope
.../SidebarMachineRemoteSectionTests.swift:8:75: error: cannot find type 'SidebarMachineHeaderAction' in scope
.../ShellXRemoteUITests.swift:39:97: error: extra argument 'remoteMachineID' in call
rc=1 (108 errors)
```
GREEN (`u1-evidence/green-final.txt`, after the last change):
```
✔ Suite SidebarMachineModelTests passed
✔ Suite ShellXBrandTests passed
✔ Suite SidebarMachineRemoteSectionTests passed
✔ Suite SidebarStatusPillModelTests passed
✔ Suite ShellXRemoteUITests passed
✔ Test run with 70 tests in 5 suites passed   (0 warnings)
```
`ShellXRemoteUITests` (12 tests, all with real assertions):
- The brief's cases:
  - `remoteMachinesSitBetweenLocalAndSSH`
  - `onlineBeforeOfflineThenByName` ("PC 9" sorts before "PC 10")
  - `offlineRemoteIsDimmedWithLastSeenAndNoRows`: "offline · last seen 14:05" in UTC; the tagged workspace is hidden and does not fall back elsewhere.
  - `thisMachineIsNeverARemoteSection`: a workspace tagged with this machine stays local.
  - `headerActionFollowsAccessAndLink`: covers every access/link combination, including offline.
  - `remoteWorkspaceRowsGroupUnderTheirMachine`
  - `longRemoteNameKeepsHeaderHeight`: 6× "Máy tính văn phòng tầng 3 ".
  - `signInErrorMapping`
- Extras:
  - `offlineWithoutLastSeenShowsDashAndUsesInjectedLabels`: covers the vi label, 23:59, and the +7 time zone shift to 06:59.
  - `onlineRemoteHeaderHasEmptyNoteIconAndIsNotDimmed`
  - `workspaceTaggedWithUnknownMachineStaysVisible`
  - `snapshotLooksUpRemoteWorkspaces`

`SidebarMachineRemoteSectionTests` (5 tests):
- descriptor order between local and SSH;
- hidden rows are dropped, not moved to another section;
- duplicate descriptors collapse to the first;
- distinct remote stableIDs;
- local and SSH headers have no action and are not dimmed.

## Verification
- `swift test --package-path Packages/Shared/ShellXBrand`: 70/70, 0 warnings.
- `python3 scripts/verify-local.py --all --swift-changed main`: 16/16 PASSED (swift-syntax over 54 files, xcstrings, localization, localization-defaults, project, wire-app-sources, feature-flags, …). Log in `u1-evidence/verify-local.txt`.
- `python3 scripts/localization_catalog.py check`: 10 catalogs, 9 locales, 0 parity errors.
- `bash scripts/check-pbxproj.sh`: rc 0. `wire-app-sources.py --check`: ok.
- `tests/test_shellx_*.py`: pass.
- I did not run xcodebuild, reload.sh or test-app.sh.

## Localization (`Resources/Localizable.xcstrings`)
- 12 keys, each with en, de, fr, es, ar, ja, ko, zh-Hans, zh-Hant and vi:
  - `remote.signin.row`, `.title`, `.error.credentials`, `.error.network`
  - `remote.machine.offline`, `.requestAccess`, `.waiting`, `.reconnecting`, `.connecting`
  - Added by me: `remote.signin.submit` ("Sign in"/"Đăng nhập"), `remote.signin.email` ("Email"/"Địa chỉ email"), `remote.signin.password` ("Password"/"Mật khẩu").
- The English and Vietnamese values are verbatim from the brief.
- I added them with `localize_changes.insert_catalog_entry` and `localization_catalog.merge`, as W1 did. The script is `scratchpad/add_u1_strings.py`.
- Cancel reuses `common.cancel`.
- "—" (never seen) is a literal and is not localized.
- The package hard-codes only `.english` defaults; the app injects `.localized`.

## Upstream symbols referenced but not compiled (each checked by grep)
- `CloudSheetWindow(rootView:)`, `.window`, `.beginSheet(on:)` and `.orderFrontFloating()` (`Sources/Cloud/CloudSheetWindow.swift`, `@MainActor`, internal).
- `NSApplication.cmuxMainWindowForModalPresentation(preferring:)` (`Sources/CmuxModalAlertPresentation.swift:40`).
- `SidebarWorkspaceTableRowConfiguration(shellXHeader:environment:)`, `.shellXHeaderRow` (private(set)), and `dispatchRowClick` / `RowClickDispatchOutcome.dispatched` in the `@MainActor` controller.
- `SidebarWorkspaceListMetrics.rowOuterHorizontalPadding` and `rowContentHorizontalPadding`.
- `MainActor.assumeIsolated` inside `.receive(on: DispatchQueue.main).sink`, the same pattern as `SidebarWorkspaceRowCellView.swift:102`.
- `@ObservedObject private var … = X.shared` in `VerticalTabsSidebar`, the same pattern as `@State … KeyboardShortcutSettingsObserver.shared`.
- The constrained protocol extension `where Self: ObservableObject, Self.ObjectWillChangePublisher == ObservableObjectPublisher` supplying a `@MainActor` protocol requirement for the fixture.
- `switch` over `SidebarMachineHeaderAction?` with enum-case patterns and `nil`.
- `accessibilityPerformPress()` override on an `NSTableCellView`.
- `NSButton` subclass: `draw(_:)` paints the fill and border, then calls `super`. Since `isBordered = false`, the cell draws only the title.
- SwiftUI `.autocorrectionDisabled()`, `.onSubmit`, `.keyboardShortcut(.defaultAction/.cancelAction)`, `RoundedRectangle.strokeBorder`, and `ProgressView().controlSize(.small)`.

## Decisions (no architectural forks; noted for review)
1. **Actions on an offline machine.**
   - `.none` and granted give nil, since there is nothing to request or open.
   - `.requested` still shows "waiting · code".
   - On an online machine, granted with `.failed` or `.offline` link gives `.open`, so a click retries. The brief does not cover these link states.
2. **A workspace tagged with an unknown machine** (signed out, machine removed, or this machine) falls back to SSH or local instead of vanishing. Only offline machines hide their rows (U14).
3. **The fixture serves a fourth machine** (Mac Studio, `.none`) on top of the three the ruling names, so the "Request access" button can be seen. It also starts signed out, so the sign-in row shows first.
4. **Header click for `.open`** goes through the controller's row-click dispatch, the same path workspace rows use. The trailing button is a real `NSButton`, which NSTableView forwards clicks to, as W1's add button relies on.
5. **The sign-in row is its own `ShellXSidebarHeaderRow.signIn` table row** after the brand row, not part of the brand cell. This keeps the brand row's fixed height unchanged when the gate is off.
6. **No cmuxTests were added** (ruling 1). The brief's `cmuxTests/...` files are replaced by the package tests.

## Concerns
1. The app code is uncompiled, and CI is its first build. The riskiest spots:
   - the protocol-extension default for `changePublisher`;
   - `MainActor.assumeIsolated` inside the sink;
   - the `@ObservedObject` default initializer reading a `@MainActor` static.
   Each follows an existing pattern in the repo or a standard language rule.
2. Workspaces on an offline remote machine are hidden from the sidebar. If one of them is the selected workspace, the list cannot reveal it. A group whose only members are hidden loses its header in that section.
3. `now` in `sections(for:local:remote:now:)` is accepted, as the brief's signature asks, but not read. Last-seen is always a clock time, even when it was days ago. A later task may want "yesterday"/date text.
4. The online dot and header state refresh through `ShellXRemoteUIModel` publishing. With the real service, `remoteWorkspaces` changes for workspaces created by L5 must reach `changePublisher`; any `ObservableObject` with `@Published` does this.
5. Light mode: the remote header's colors are the dark palette tokens, as in W1 (dark only, per the palette ruling).

---

## Fix round 1 (commit `4bbaac28ed`)

Status: DONE. The app code is still not compiled locally (no xcodebuild).

1. **`common.cancel` vi.** Added `vi = "Huỷ"` (state translated) to `Resources/Localizable.xcstrings` with `localization_catalog.merge`, so the SignInSheet Cancel button is localized.
2. **Password not kept.** `SignInSheetModel` (`Sources/ShellX/Remote/UI/SignInSheet.swift`) sets `password = ""`:
   - after a successful sign-in, before `onFinished(true)`;
   - after a failed attempt, together with the inline error;
   - on cancel.
   The email is kept for a retry. The value the request sends is captured in a local before the call.
3. **K4 env gate.** `ShellXRemoteUIGate.isEnabled` is now `ShellXFeatures.remoteMachines || usesFixtures || remoteMachinesRequested`.
   - `remoteMachinesRequested` is DEBUG with `SHELLX_REMOTE_MACHINES == "1"`, the variable L5's `ShellXRemoteGate` reads.
   - Fixtures are still served only for `SHELLX_REMOTE_UI_FIXTURES == "1"`. With only `SHELLX_REMOTE_MACHINES` set, the provider returns nil, `snapshot` stays nil, and nothing remote shows (no sign-in row).
   - The bind point has a new note: `// ShellX: once it lands, ShellXRemoteUIGate.isEnabled must follow ShellXRemoteGate.`
   - Release builds are unchanged: both env reads are `#if DEBUG`, and `ShellXFeatures.remoteMachines` is still false.

Ruling noted, no change: an offline machine with access `.none` shows no action.

Covering tests: none of these three changes is package logic; the gate and the sheet model are app-only and cmuxTests is not built (ruling 1). The checks below cover them.

Commands and output:
```
$ python3 -c "...strings['common.cancel']['localizations']['vi']"
{'stringUnit': {'state': 'translated', 'value': 'Huỷ'}}
$ python3 scripts/localization_catalog.py check
10 catalogs, 9 locales: 0 parity errors
$ python3 scripts/verify-local.py --all --swift-changed main
PASSED: 16/16 selected checks ran.        (log: u1-evidence/verify-local-fix1.txt)
$ swift test --package-path Packages/Shared/ShellXBrand
✔ Test run with 70 tests in 5 suites passed
$ bash scripts/check-pbxproj.sh
rc 0
```
