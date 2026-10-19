# W2 Task U3 report: on-site approval prompt comparing code and fingerprint

Status: DONE_WITH_CONCERNS. The package logic is tested (120/120 green; 31 new). The app code is not built with xcodebuild (rule); it and the new cmuxTests file were type-checked with `swiftc -typecheck` (Swift 5 mode, macOS 14) against the real package modules and the real U1/U2/U3 app files, with two stubs (see "Uncompiled symbols"). CI remains the first real build.
Branch: `shellx/l3-sidebar` (worktree `shellx-wt/l3-sidebar`), not pushed. One commit on top of BASE `62e123b837`: `feat(shellx): on-site approval prompt comparing code and fingerprint`.

## What was implemented

### Package (`ShellXRemoteUI`, pure, Foundation + ShellXRemoteCore only)
- `ApprovalPromptModel.swift`
  - `ApprovalPromptLabels` (title `%@`, compare, suspicious, approve, deny, queue `%lld`/`%lld`, network, codeLabel, fingerprintLabel) with `.english` defaults; the app injects the localized set.
  - `ApprovalPromptModel` (`Equatable, Sendable`): `init(queue:now:labels:failureCode:isBusy:)`. Fields: `current`, `title` (+ `titleLineLimit == 1`), `compareText`, `codeText` ("482 915" via `PairingDisplay.code`), `fingerprintText` ("8877 6655 4433 2211" via `PairingDisplay.fingerprint`), `warning`, `errorText`, `canApprove`, `canDeny`, `isBusy`, `queueText`, `approveTitle`, `denyTitle`, `codeLabel`, `fingerprintLabel`, `nextExpiry`.
  - Rules (binding, from the brief): `current` = oldest non-expired request (stable for equal `firstSeen`); `now >= expiresAt` drops a request; nothing pending gives an all-empty model. `suspicious` => `warning = remote.approve.suspicious` and `canApprove = false`. A `fingerprint_mismatch` failure code => the same suspicious text, `canApprove = false` for that request, no second inline error. Any other failure code is shown inline in `errorText` (`network` => the network label, else the code as is) and the request stays approvable. `canDeny` is true for every request (suspicious too) unless busy. `queueText` = `String(format: labels.queue, 1, pending)` only with 2+ pending (English "1 of 2", Vietnamese catalog text "1 / 2").
- `ApprovalPromptTracker.swift` (`Sendable` value type, same idea as U2's `RequestAccessTracker`): `model(queue:now:labels:)`, `begin(_:requestID:queue:now:)`, `finish(_:requestID:failureCode:)`, `prune(queue:)`, `stop()`.
  - `begin` is the structural gate. It returns true (call the service) only if not stopped, no other decision in flight, the id is still the oldest unexpired request (so a stale button or a request that expired/was replaced between draw and click cannot act on a different request), and the model allows it (approve needs `canApprove`, so a suspicious request or a server `fingerprint_mismatch` can never be approved; deny needs `canDeny`).
  - `finish` hides a decided request at once even if the service lags in dropping it; a failure is kept per request and shown inline; results after `stop()` or for another request are ignored. `prune` forgets requests the service no longer lists.

### App (`Sources/ShellX/Remote/UI/`, wired into the cmux target)
- `ApprovalPromptPanel.swift`
  - `ApprovalPromptLabels.localized` (String(localized:defaultValue:), same pattern as U1/U2).
  - `ApprovalPromptViewModel` (observable state + `onApprove`/`onDeny` callbacks with the id the buttons were drawn for).
  - `ApprovalPromptView` (SwiftUI, width 400, dark only, palette tokens only): title row 20 pt fixed height, 15 pt `textHi`, one line, tail truncation (+ tooltip), queue text right-aligned; `remote.approve.compare` under it; one flat bordered box holding the code (28 pt monospaced) and the fingerprint (16 pt monospaced) one above the other, neither truncated; the suspicious warning in a flat box with a 1 px `error` border; the inline error in `error`; buttons: secondary Deny, primary Approve (`.disabled(!canApprove)`), both `ShellXSheetButtonStyle` (primarySoft/primaryLine/primaryText, raise/border/text). No gradients, no shadows, no keyboard shortcuts.
  - `ApprovalPromptPanel: NSPanel`: titled, floating, `hidesOnDeactivate = false`, `canBecomeKey = true`, `canBecomeMain = false`, no `.closable`, traffic-light buttons hidden. Structurally no default button: `defaultButtonCell` is overridden (getter nil, setter ignored), `cancelOperation` (Esc) and `performClose` do nothing, no `.keyboardShortcut` anywhere. Sized like `CloudSheetWindow` (hosting controller with no sizing options, the view reports its ideal size and the panel applies it on a later main-queue turn, top-left anchored).
- `ApprovalPromptController.swift` (`@MainActor`): follows `service.changePublisher` (receive on main, `MainActor.assumeIsolated`, same as U1/U2), reads `pendingApprovals`, asks the tracker for a model, shows/updates the panel (`orderFrontRegardless` + `makeKey`, no app activation) and closes it when nothing is left. An expiry Task sleeps until the shown request's `expiresAt` (bounded to 3600 s and re-armed, so a far-off deadline cannot overflow) and refreshes, so an expired request disappears without a click; the timer is cancelled whenever the panel closes. Approve/Deny run in `Task { @MainActor }` (`approve` failure code = `ShellXCoreError.code`, else `network`); a refused `begin` just redraws. `stop()` cancels the decision Task, the subscription and closes the panel. It never touches `ShellXRemoteUIModel.shared` (it is started from that singleton's initializer). The bell hook comment is in place: `// ShellX: TODO bell item (W1 Task 11, after checkpoint 1)`.
- Start-up wiring: `ShellXRemoteUIModel.init` creates the controller only when it has a service and starts it (`// ShellX:` marker). Gate off (`ShellXFeatures.remoteMachines == false`, no env) => `service == nil` => no controller, no panel, no timer. `ShellXFeatures.remoteMachines` is unchanged. No upstream (non-ShellX) file was edited.
- DEBUG fixture (`ShellXRemoteFixtureService`): signing in (any non-empty email and password except "wrong") now also serves two `pendingApprovals`: "Mac Studio" (code 482915, fingerprint 8877665544332211 = the fingerprint the fixture server reports for that machine, `suspicious: false`) and "MacBook Air" (code 730264, fingerprint deadbeef01234567, which is neither the Air's `1122334455667788` nor any other fixture fingerprint, `suspicious: true`, one second newer so the queue reads "1 of 2"). `approve` waits 0.4 s (busy state visible), throws `fingerprint_mismatch` for a suspicious request (it stays listed), `pairing_not_pending` for an unknown id, else removes it; `deny` removes it; sign-out clears them. `ownFingerprint` changed from `a1b2c3d4e5f60718` (collided with fixture-pc) to `5a6b7c8d9e0f1a2b`, distinct from every fixture machine and request fingerprint (U2 review note).
- Catalog: 7 new keys, each with en, de, fr, es, ar, ja, ko, zh-Hans, zh-Hant, vi (state translated): `remote.approve.title/compare/suspicious/approve/deny/queue` (en and vi verbatim from the brief; `queue` en "%lld of %lld", vi "%lld / %lld") plus one extra, `remote.approve.fingerprint` ("Fingerprint" / "Vân tay"), because the existing `remote.request.fingerprint` reads "This Mac's fingerprint", which is wrong on the approving side. The code label reuses `remote.request.code` and Cancel is not needed (no cancel on this panel). Added with `localize_changes.insert_catalog_entry` + `localization_catalog.merge` (script in the session scratchpad); +455 lines, no existing line changed.
- `cmuxTests/ShellXRemoteUITests.swift` (new, Swift Testing, conservative; not executed this sprint): `returnKeyHasNoDefaultAction` (`defaultButtonCell == nil`, and still nil after assigning one), `panelIsFloatingKeyAndNotClosable`, `escapeAndPerformCloseDoNothing`. It deliberately imports no ShellX package modules (the cmuxTests target does not link ShellXRemoteUI).

## Files
- New (package): `Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/ApprovalPromptModel.swift`, `.../ApprovalPromptTracker.swift`; tests `Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/ApprovalPromptModelTests.swift` (17), `.../ApprovalPromptTrackerTests.swift` (14)
- New (app): `Sources/ShellX/Remote/UI/ApprovalPromptPanel.swift`, `Sources/ShellX/Remote/UI/ApprovalPromptController.swift`, `cmuxTests/ShellXRemoteUITests.swift`
- Modified: `Sources/ShellX/Remote/UI/ShellXRemoteServicing.swift` (+6, wiring), `Sources/ShellX/Remote/UI/ShellXRemoteFixtureService.swift` (DEBUG), `Resources/Localizable.xcstrings` (+7 keys), `cmux.xcodeproj/project.pbxproj` (+12 lines)
- Evidence: `u3-evidence/` (red-1, green-1, green-final, verify-local-final, typecheck)

## TDD evidence
- RED (`u3-evidence/red-1.txt`): both test files written first; `swift test` failed to compile: `cannot find 'ApprovalPromptLabels' in scope` (and the model/tracker types), rc=1, 164 error lines.
- GREEN (`u3-evidence/green-1.txt`): after the implementation, `swift test --filter ApprovalPrompt` -> `Test run with 31 tests in 2 suites passed`, rc=0. (The first GREEN attempt failed to compile only because the tracker tests called mutating `begin` inside `#expect`; fixed in the tests to bind the result first.)
- Final (`u3-evidence/green-final.txt`): `swift test --package-path Packages/Shared/ShellXBrand` -> `Test run with 120 tests in 9 suites passed` (was 89), 0 warnings, 0 errors.
- Brief test cases in the package: `showsOldestRequestWithCodeAndFingerprint`, `suspiciousRequestCannotBeApproved`, `expiredRequestsAreDropped` (+301 s; also exact 300 s dropped, 299 s kept), `queueTextCountsPending` ("1 / 2" with the catalog's `%lld / %lld` text; "1 of 2" in English; nil for one pending). `returnKeyHasNoDefaultAction` is in cmuxTests (AppKit only).

## Verification output
```
$ swift test --package-path Packages/Shared/ShellXBrand      -> 120 tests in 9 suites passed
$ python3 scripts/verify-local.py --all --swift-changed main -> PASSED: 16/16 selected checks ran (swift-syntax 66 files, xcstrings, localization, localization-defaults, project, test-wiring-sync, wire-app-sources, test-wiring, package-groups, feature-flags, ...)
$ python3 scripts/localization_catalog.py check              -> 10 catalogs, 9 locales: 0 parity errors
$ python3 scripts/normalize-pbxproj.py                       -> rc 0, no further change
$ bash scripts/check-pbxproj.sh                              -> rc 0
$ python3 scripts/wire-app-sources.py --check                -> ok
$ scripts/sync-test-wiring --check                           -> ok (checked 1292 test files)
$ python3 -m unittest tests/test_shellx_*.py                 -> OK (9 tests)
$ swiftc -typecheck -swift-version 5 -target arm64-apple-macos14.0 (see u3-evidence/typecheck.txt), -D DEBUG and release -> rc 0, no diagnostics; also clean with -strict-concurrency=complete; cmuxTests/ShellXRemoteUITests.swift compiled together with the app files (Testing macro plugin) -> rc 0
```
Not run (rule): xcodebuild, reload.sh, test-app.sh.

## Wiring map (file:line)
- Gate/start: `ShellXRemoteServiceProvider.makeService()` (nil with the gate off) -> `ShellXRemoteUIModel.init(service:)` `Sources/ShellX/Remote/UI/ShellXRemoteServicing.swift:100` (property), `:104` (creates `ApprovalPromptController` only with a service), `:116-118` (`// ShellX:` marker + `approvalPrompt?.start()`).
- Controller: `Sources/ShellX/Remote/UI/ApprovalPromptController.swift` `start()` :37 (subscribes to `service.changePublisher`, first pass next turn), `refresh()` :59 (bell TODO :64), `decide(_:requestID:)` :79 (`tracker.begin` :80, `tracker.finish` :102), `present(title:)` :107, `closePanel()` :119 (cancels the expiry Task), `scheduleExpiry(at:)` :130, `stop()` :51.
- Panel: `ApprovalPromptPanel.swift` `ApprovalPromptViewModel` :36, `ApprovalPromptView` :51, `ApprovalPromptPanel` :191, `isFloatingPanel` :202, `canBecomeKey` :234, `defaultButtonCell` override :238, `cancelOperation` :244, `performClose` :247.
- Buttons -> `ApprovalPromptViewModel.onApprove/onDeny` (set in the controller init) -> `decide` -> `Task { @MainActor }` -> `service.approve(_:)` / `service.deny(_:)`.
- Fixture: `ShellXRemoteFixtureService.swift` `ownFingerprint` :30, `fixtureApprovals(now:)` :79, `approve` (mismatch :134), `signIn` seeds :164.
- pbxproj: app Sources phase `A1E08FB2F5093B9F4507AF9C` (Controller) and `84FAC7125E6D12AD734C2FF0` (Panel) at project.pbxproj:15076-15077 (build files :361-362, file refs :5128-5129, group :12420-12421); test file `6CDDB319FED107C3EB57AE87` / `0766083F21AAC8FF1BDCB01C` in the cmuxTests Sources phase and group (wire-app-sources.py and sync-test-wiring ids, as in U1; the `5E13C3` prefix applies only to ids I hand-add and I added none).

## Security (Review Focus 3)
- The code and the requester's fingerprint are rendered together in one box whenever a request is shown, for suspicious and normal requests alike, never truncated. Tested: `fingerprintIsAlwaysShownWithTheCode`.
- Never auto-approve: nothing in the controller calls `approve` except the Approve button, and `begin` refuses a suspicious request (`suspiciousRequestIsNeverApprovedButCanBeDenied`), a server `fingerprint_mismatch` (`aFingerprintMismatchFromTheServiceBlocksApprovingThatRequest`), an expired request, a stale button for a different request, a second decision while one is in flight, and anything after `stop()`. Deny is available for every request.
- No default button: structural (`defaultButtonCell` overridden to nil), no `.keyboardShortcut`, Esc and performClose are no-ops, the panel has no close button; cmuxTests checks it.
- The click acts on the request id the buttons were drawn for, and the tracker re-checks it against the live queue and `now` at click time.
- Nothing is logged; no code/fingerprint/invite string reaches a log or beep path.

## Uncompiled symbols (each grepped or type-checked; T = type-checked by swiftc)
- T `NSPanel` subclass with a designated `init(viewModel:)` calling `super.init(contentRect:styleMask:backing:defer:)`; `NSWindow.defaultButtonCell` get/set override; `cancelOperation(_:)`, `performClose(_:)`, `canBecomeKey/Main`, `isFloatingPanel`, `hidesOnDeactivate`, `becomesKeyOnlyIfNeeded`, `collectionBehavior [.moveToActiveSpace, .fullScreenAuxiliary]`, `standardWindowButton(_:)`, `orderFrontRegardless()`, `makeKey()`.
- T `NSHostingController(rootView:)` + `sizingOptions = []` + `NSHostingView(rootView:).fittingSize` (same as `Sources/Cloud/CloudSheetWindow.swift`), SwiftUI `.onGeometryChange(for:of:action:)` (same as `CloudSheetContent`).
- T `ShellXSheetButtonStyle`, `ShellXRemoteServicing`, `ShellXRemoteUIModel` (U1 files, real).
- T `MainActor.assumeIsolated` in the Combine sink (same as U1/U2), `Task { @MainActor [weak self] in ... guard let self }`, `Task.sleep(nanoseconds:)`.
- STUBBED in the type-check: `NSApplication.cmuxMainWindowForModalPresentation(preferring:)` (`Sources/CmuxModalAlertPresentation.swift:40`) and `ShellXSidebarHeaderRow` (U1 sidebar enum, used by `ShellXRemoteUIActions.handleClick`); neither is used by U3 code.
- Package: Swift 6 language mode; model and tracker are `Sendable` value types. App target is Swift 5.0, macOS 14.0.

## Decisions
1. Model gained `failureCode`/`isBusy` inputs and the tracker owns the decision state; the brief's `init(queue:now:)` still works (labels, failure and busy default).
2. `queueText` is nil with a single pending request (the brief shows only the "1 / 2" case).
3. Extra catalog key `remote.approve.fingerprint` (see above); `remote.request.code` reused for the code label.
4. The panel appears in front of other apps (floating level, `orderFrontRegardless`) without activating ShellX, because the person at this Mac must notice an approval request; it also moves to the active Space.
5. The fixture serves the approvals only after sign-in (signed out has no approvals, like the real service).
6. Bell item skipped per the controller ruling; only the TODO comment exists.

## Concerns
1. App code and the cmuxTests file have not been built by xcodebuild or executed. The type-check covers every U3 file in DEBUG and release, but it used the local macOS SDK and two stubs, so CI is the first real build. Riskiest spots: the `defaultButtonCell` property override, the NSPanel designated initializer, and `orderFrontRegardless()` + `makeKey()` behaviour for an inactive app.
2. If ShellX is not the active app when a request arrives, the first click on the panel may only activate the app (standard AppKit behaviour for a non-key-app window); the buttons then work on the next click. Not changed because auto-activating the app was judged worse (focus-steal policy).
3. A new request can appear under the pointer while the person is clicking elsewhere; there is no arming delay on the buttons. The panel opens centered, away from where the Approve button of the previous panel was, and approving a suspicious request is impossible, but a short disabled period for a newly shown request could be added later.
4. The wall-clock expiry timer uses `Task.sleep`, which does not count system sleep. After waking a sleeping Mac an expired request can stay on screen until the timer fires, but the tracker re-checks `now` on every click, so an expired request still cannot be approved or denied (a refused click redraws and drops it).
5. The fixture's `fingerprint_mismatch` path is only reachable through the service, not through the UI (the UI refuses suspicious approvals before calling it), which is intended; the inline mismatch display is covered by the package tests.
6. A request that outlives its 300 s only via a `firstSeen` in the future would stay up; `firstSeen` is the service's own local clock (L5), so this is not expected.
7. The SDD artifacts under `.superpowers/sdd/` are gitignored by default; this commit force-adds the report and evidence the same way U2 did.
