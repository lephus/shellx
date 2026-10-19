# W2 Task U4 report: offline and reconnecting banner for remote sessions

Status: DONE_WITH_CONCERNS. Package logic tested (161/161 green; 24 new). The app code is not built with xcodebuild (rule). It was type-checked with `swiftc -typecheck` (Swift 5 mode, macOS 14, DEBUG and release, also `-strict-concurrency=complete`) against the real package modules and the real U1-U4 app files, and the banner/gate/fixture were additionally RUN in a throw-away AppKit harness (not part of the repo) that renders the real SwiftUI views to bitmaps. CI remains the first real build.
Branch: `shellx/l3-sidebar` (worktree `shellx-wt/l3-sidebar`), not pushed. One commit on BASE `6a9cba0a9d`: `e96ca97ff9 feat(shellx): offline and reconnecting banner for remote sessions`.

## What was implemented

### Package `ShellXRemoteUI` (pure, Foundation + ShellXRemoteCore only)
`Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/RemoteLinkBannerModel.swift`
- `RemoteLinkBannerLabels { reconnecting, offline, failed, retryIn }` with `.english` defaults (values verbatim from the brief; `retryIn` = "retry in %llds").
- `RemoteLinkBannerModel: Equatable, Sendable`, `init(machine:now:labels: = .english)`. Fields: `text: String?`, `tone` (`.muted` / `.error`), `showsSpinner`, `lineLimit == 1`, `refreshDates`.
  - `.idle` / `.connected` -> `text == nil`, no spinner.
  - `.connecting` -> `remote.banner.reconnecting`, muted, spinner, no countdown.
  - `.reconnecting(_, retryAt)` -> reconnecting text + `" · "` + `retryIn` with `max(0, ceil(retryAt - now))` (e.g. retryAt = now + 3.2 -> "… · retry in 4s"), muted, spinner. A retryAt in the past -> "retry in 0s". A non-finite retryAt -> no countdown suffix. The number is capped at 86 400 so no Int trap.
  - `.offline` -> `remote.banner.offline`, muted. `.failed(code)` -> `remote.banner.failed` with the code verbatim, error tone.
  - Machine name is `RemoteMachine.name`; a blank name falls back to the machine id (no extra catalog key). `String(format:)` is given the name as an argument, so a `%` in a name is safe.
  - `static let height: Double = 28` and `borderWidth = 1` (the view uses these constants).
  - `refreshDates`: the moments the text changes next while a countdown shows, each a whole number of seconds before `retryAt` (so "4s" steps to "3s" exactly on the second), strictly later than `now`, ending at `retryAt`, at most `maxRefreshes = 600` (the last 10 minutes). Empty without a countdown and once it reached 0, so nothing ticks after that.
  - `static func machine(forWorkspace:in: RemoteUISnapshot?) -> RemoteMachine?`: the machine of a remote workspace; nil for a local workspace, a nil/signed-out snapshot, or a workspace tagged with a machine the snapshot does not list (no banner then).

### App (`Sources/ShellX/Remote/UI/RemoteLinkBanner.swift`, new, wired into the cmux target)
- `RemoteLinkBannerLabels.localized` (`String(localized:defaultValue:)`, same pattern as U1-U3).
- `RemoteLinkBanner: View`: one 28 pt line, flat `raise` fill, 1 px `line` bottom border (inside the 28 pt), 12 pt text, `lineLimit(1)` + `.truncationMode(.tail)`, `muted` / `error` text, 12 pt spinner (`ProgressView` small, scaled 0.75, frame 12x12) when `showsSpinner`, `.environment(\.colorScheme, .dark)`, `.allowsHitTesting(false)`, no focusable control, accessibility label = the text. Palette tokens only, no gradients/shadows.
- `View.shellXRemoteLinkBanner(workspaceID:isSelected:)` -> `ShellXRemoteLinkBannerModifier`:
  - `remoteUIEnabled` (static let, read once = `ShellXRemoteUIGate.isEnabled`, the same fixed-per-launch gate that decides whether `ShellXRemoteUIModel.shared` has a service). Off: `body` returns `content` untouched; nothing is observed and no timer exists.
  - On: `ShellXRemoteLinkBannerHost` checks `ShellXRemoteUIModel.shared.service != nil` (DEBUG corner: `SHELLX_REMOTE_MACHINES=1` without fixtures leaves the service nil -> content untouched).
  - With a service: `ShellXRemoteLinkBannerLayer` (`@ObservedObject` on `ShellXRemoteUIModel.shared`) = `VStack(spacing: 0) { banner; content }`. The banner is an `if let` child (machine found in `snapshot` via `RemoteLinkBannerModel.machine`, text non-nil), so the VStack and the content's position in it are the same whether or not a banner shows.
  - Countdown: a banner for the selected workspace with `refreshDates` is wrapped in `TimelineView(.explicit([now] + refreshDates))`, which re-renders on the whole seconds only and stops at `retryAt`. A banner for a non-selected (hidden, mounted) workspace or without a countdown is a plain static view (no timeline). No `Timer` anywhere; no banner means no TimelineView.

### Wiring (upstream edit, marked `// ShellX:`)
- `Sources/ContentView.swift:1849-1851`, in `terminalContent(appearance:)`, in the `ForEach(mountedWorkspaces)` block: `.shellXRemoteLinkBanner(workspaceID: tab.id, isSelected: isSelectedWorkspace)` inserted directly after `WorkspaceContentView(...)` and before `.opacity/.allowsHitTesting/.accessibilityHidden/.zIndex`, so those four modifiers cover banner + pane together (a hidden workspace stays hidden and non-hit-testable). Nothing inside `WorkspaceContentView` or the terminal portal code was touched. The ZStack's titlebar top padding (`WorkspacePresentationModeContentTopPaddingModifier`) stays outside, so the banner sits at the top of the content area below the titlebar.
- Why not inside `WorkspaceContentView` (:199): its `body` ends in a long modifier chain (minimal-mode safe area, cloud failure presentation) and its `bonsplitView` has `.id(splitZoomRenderIdentity)`; the ForEach site is a single-line, wiring-only insertion.

### View identity and portal geometry
- Gate off (release default; `ShellXFeatures.remoteMachines == false`, no env): the modifier body is `content`; no VStack, no observation, no timer. Verified by the harness: gate false, `service == nil`, `snapshot == nil`, content top at 0.
- Gate on, workspace not remote: the VStack contains only `content`; its frame is the same (a VStack holding one flexible child). The content's identity does not depend on the workspace becoming remote, because the VStack is always present when the gate is on and the banner is only an optional first child.
- Verified in the harness (real `NSHostingView`, real fixture service, real modifier): an `onAppear`/`onDisappear` probe in the content fired 1/0 times across every banner change (idle, connecting, reconnecting, offline, failed, connected), i.e. the content subtree is never rebuilt when a banner appears or goes away; it only moves down by exactly 28 pt (bitmap: content top 0 -> 28 -> 0). A local workspace beside it stayed at 0.
- NOT verified (needs the real app): how the AppKit-portal-hosted terminal reacts when its SwiftUI anchor moves down 28 pt (it should resync as it does for sidebar width/titlebar padding changes), and minimal presentation mode (see Concerns 1 and 2).

### DEBUG fixture (`ShellXRemoteFixtureService.swift`, DEBUG only, ~25 lines)
- `openSession(on:)` now tags the selected workspace (`AppDelegate.shared?.tabManager?.selectedTabId`, the same read as `Sources/Cloud/CloudTreeStyleGalleryWindow.swift:113`) as a remote workspace of that machine, then steps the machine's link, one step per open of the same machine: open 1: connecting (0.8 s) -> reconnecting with a 10 s `retryAt` -> offline when the countdown ends; open 2: connecting -> failed("network"); open 3: connecting -> connected (no banner); then around again. `openCounts` resets on sign-out. Header action for an online machine with link offline/failed is `.open` (U1 rule), so the cycle can be clicked through. This changes U1's fixture result of the first open (was connected after 0.8 s) which the ruling allowed.

### Catalog (`Resources/Localizable.xcstrings`)
4 keys, each with en, de, fr, es, ar, ja, ko, zh-Hans, zh-Hant, vi (state translated); +260 lines, no existing line changed. The three `remote.banner.*` keys did not exist before. en and vi are verbatim from the brief / ruling:
- `remote.banner.reconnecting` "Reconnecting to %@…" / "Đang kết nối lại tới %@…"
- `remote.banner.offline` "%@ is offline. The session resumes when ShellX opens there." / "%@ đang ngoại tuyến. Phiên tiếp tục khi ShellX được mở trên máy đó."
- `remote.banner.failed` "Can't connect to %@ (%@)" / "Không kết nối được tới %@ (%@)"
- `remote.banner.retryIn` (extra, per ruling) "retry in %llds" / "thử lại sau %llds"
Added with `localize_changes.insert_catalog_entry` + `localization_catalog.merge` (script: session scratchpad `add_u4_strings.py`).

## Files
- New: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/RemoteLinkBannerModel.swift`; `Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/RemoteLinkBannerModelTests.swift` (24 tests); `Sources/ShellX/Remote/UI/RemoteLinkBanner.swift`.
- Modified: `Sources/ContentView.swift` (+3), `Sources/ShellX/Remote/UI/ShellXRemoteFixtureService.swift` (DEBUG), `Resources/Localizable.xcstrings`, `cmux.xcodeproj/project.pbxproj` (+4 lines from `wire-app-sources.py`: build file `59A0EF9FC63A4CA36EF3F83F`, file ref `45F3355FE7BE8DE9DC2D13CA`, group child :12424, Sources phase :16377; no hand-written ids).
- Evidence (untracked): `u4-evidence/` red-1, green-1, green-final, verify-local-final, typecheck, typecheck-stubs.swift, harness-fixtures.txt, harness-gate-off.txt, harness sources, `screens/*.png` (rendered banner states).
- No cmuxTests added: the only AppKit-visible checks (height, truncation, no layout shift, gate off) cannot live in cmuxTests because that target does not link `ShellXRemoteUI` (U3 note); the package tests plus the harness cover them.

## TDD evidence
- RED (`u4-evidence/red-1.txt`): test file written first; `swift test` failed to compile: `cannot find 'RemoteLinkBannerLabels' in scope` (and the model type), rc=1, 88 error lines.
- GREEN (`green-1.txt`): `--filter RemoteLinkBanner` -> 24 tests in 2 suites passed. One test expectation of mine was wrong at first (a distantFuture retryAt: I expected no refresh dates, the model bounds them to the last 600 s); I fixed the test to assert the bound, not the model.
- Brief cases: `connectedShowsNoBanner`, `reconnectingShowsCountdown` (retryAt = now + 3.2 -> "Reconnecting to Mac mini… · retry in 4s"), `offlineExplainsResume`, `failedShowsCodeInErrorTone`, `bannerHeightIsFixed` (`RemoteLinkBannerModel.height == 28` for every state, also with a very long name).
- Edge tests: retryAt in the past -> "retry in 0s" and no refresh dates; retryAt == now -> 0s; ceil boundaries (0.01 -> 1s, 1 -> 1s, 1.01 -> 2s, 29.5 -> 30s); connecting has spinner and no countdown; distantFuture/infinite retryAt bounded; refresh dates aligned to the deadline (texts 3s, 2s, 1s, 0s) and bounded; no refresh dates for non-countdown states; machine name used; blank name falls back to id; `%` in a name safe; Vietnamese labels injected; failed shows code verbatim (also `pairing_not_pending`); equality; English labels equal the catalog values; lookup: tagged workspace -> machine, local workspace -> nil, unknown machine -> nil, nil / signed-out snapshot -> nil.
- Full suite (`green-final.txt`): `swift test --package-path Packages/Shared/ShellXBrand` -> 161 tests in 11 suites passed (was 137), 0 warnings.

## Verification output
```
swift test --package-path Packages/Shared/ShellXBrand       -> Test run with 161 tests in 11 suites passed
python3 scripts/verify-local.py --all --swift-changed main  -> PASSED: 16/16 selected checks ran   (u4-evidence/verify-local-final.txt)
python3 scripts/localization_catalog.py check               -> 10 catalogs, 9 locales: 0 parity errors
bash scripts/check-pbxproj.sh                               -> rc 0
python3 scripts/normalize-pbxproj.py                        -> rc 0 (no further change)
python3 scripts/wire-app-sources.py --check                 -> ok
python3 -m unittest tests/test_shellx_*.py                  -> OK (9 tests)
swiftc -typecheck -swift-version 5 -target arm64-apple-macos14.0, -D DEBUG and release, and -strict-concurrency=complete (DEBUG) -> rc 0, no diagnostics   (u4-evidence/typecheck.txt; a deliberate error in a copy was caught, so the files really are compiled)
```
Harness runs (u4-evidence/harness-*.txt, screens/): 600x300 `NSHostingView` with a red probe as the "terminal":
- fixtures on: content top 0 (idle) -> 28 (connecting, reconnecting, offline, failed) -> 0 (connected); a local workspace stays 0; a hidden (not selected) remote workspace also reserves 28 so its terminal size does not jump when it is selected; the countdown ticked from "retry in 10s" to "retry in 7s" about 3.3 s later without any click; text truncates with "…" at 220 pt width; content `onAppear/onDisappear` = 1/0 over the whole run.
- gate off (no env): `ShellXRemoteUIGate.isEnabled == false`, `service == nil`, `snapshot == nil`, content top 0.
Not run (rule): xcodebuild, reload.sh, test-app.sh.

## Uncompiled / unverified upstream symbols
- Type-checked with stubs (stub = same signature, body trivial): `NSApplication.cmuxMainWindowForModalPresentation(preferring:)` (`Sources/CmuxModalAlertPresentation.swift:40`), `ShellXSidebarHeaderRow` (U1 sidebar enum), `TabManager.selectedTabId` (`Sources/TabManager.swift:272`, `UUID?`), `AppDelegate.shared` / `AppDelegate.tabManager` (`Sources/AppDelegate.swift:563`, `:715`, MainActor class). The fixture's use matches `Sources/Cloud/CloudTreeStyleGalleryWindow.swift:113`.
- The `ContentView` edit itself is not compiled (the file is too large to stub). It was type-checked as a replica of the call site (`ForEach { WorkspaceContentView-like.shellXRemoteLinkBanner(...).opacity(...).allowsHitTesting(...).accessibilityHidden(...).zIndex(...) }`, in `Stubs.swift`), and the only upstream symbols it uses are `tab.id` and `isSelectedWorkspace`, both defined a few lines above in the same closure.
- SwiftUI used and compiled against the local SDK (Xcode 26.6) with a macOS 14 target: `TimelineView(.explicit(_))`, `ProgressView().controlSize(.small).scaleEffect`, `.overlay(alignment:)`, `ViewModifier` with `@ViewBuilder func body`. The harness ran them on this Mac (macOS 26); I could not run them on macOS 14.

## Decisions (no architectural forks)
1. Banner is at the top of the workspace content area, above the tab bar (no presence strip exists, per the ruling).
2. Blank machine name falls back to the machine id, not a localized word, to avoid a second extra catalog key and a sentence-start capitalization problem ("… is offline").
3. `retryAt` in the past shows "retry in 0s" (the brief's `max(0, ceil)`) and stops ticking; the service's next state change replaces it.
4. Refresh moments are deadline-aligned and bounded (`maxRefreshes = 600`), instead of a free-running 1 Hz timer, so there is no timer after the countdown ends and none for a banner without a countdown.
5. A non-selected mounted workspace shows its banner statically (no TimelineView) but still reserves the 28 pt, so toggling the selection does not resize its terminal.
6. The fixture's first open no longer ends at "connected" (ruling allowed the cycle).

## Concerns
1. Terminal portal geometry: a banner appearing moves the SwiftUI anchor of the AppKit-hosted terminal down 28 pt and changes the terminal's rows. This should resync like other layout changes, but it is not verified in the real app; the first CI/dev build should look at it (reconnect with the DEBUG fixture, `SHELLX_REMOTE_UI_FIXTURES=1`, click the "PC Windows" header).
2. Minimal presentation mode: `WorkspaceContentView` ignores the top safe area there (its tab bar lives under the titlebar). With a banner above it in the VStack the banner takes the safe-area-respecting top position and the pane starts below the banner, so the content no longer extends under the titlebar while a banner shows. Not tested; cosmetic at worst, and only for a remote workspace with a banner.
3. The 12 pt spinner is a scaled small `ProgressView` (16 pt natively); it looks right in the harness screenshot but is not a custom-drawn 12 pt control.
4. Every mounted workspace's Layer observes `ShellXRemoteUIModel.shared` while the remote UI has a service, so any snapshot change re-evaluates N cheap bodies (a dictionary lookup each). Gate off: none.
5. DEBUG fixture: `openSession` tags whatever workspace is selected, including a local one, which then moves under the machine's sidebar group (that is what a real remote workspace would do). A fixture reconnect task is not cancelled on sign-out; it only ends with a no-op update.
6. U3's report file `task-U3-report.md` shows as modified in the worktree (it was modified before this task, I did not touch or stage it).
