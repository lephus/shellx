# W2 Task U2 report: request-access sheet with code and fingerprint

Status: DONE_WITH_CONCERNS. Package logic is tested (89/89 green). The app code is not built with xcodebuild (rule); it was type-checked with `swiftc -typecheck` (Swift 5 mode, macOS 14) against the real package modules and the real U1/U2 app files, with two stubs (see "Uncompiled symbols"). CI remains the first real build.
Branch: `shellx/l3-sidebar` (worktree `shellx-wt/l3-sidebar`), not pushed. One commit on top of the WIP: `feat(shellx): request-access sheet with code and fingerprint` (WIP base `4077bddaa3`/`baa6015b59`, U2 BASE `4bbaac28ed`).

## Audit of the WIP (4077bddaa3) against the brief and the Part B rulings

Correct as found (kept):
- `RequestAccessModel` fields, `Action.retry`, `closesAutomatically`, `autoCloseDelay == 1`, `titleLineLimit == 1`, localized-labels injection (package has English defaults only).
- All five brief tests exist with real assertions: `waitingShowsCodeFingerprintAndSpinner`, `approvedClosesAutomatically`, `deniedShowsErrorWithoutRetry`, `expiredOffersRetry`, `vietnameseTitleTruncatesNotWraps` (120-char name kept whole, `titleLineLimit == 1`), plus `failedOffersRetryWithReadableCode`, `modelIsEquatableAcrossStatusChanges`, `currentPairing...`. Code and fingerprint are asserted in the approved state too.
- Sheet layout matches the brief: raise background, title 15 pt `textHi` `lineLimit(state.titleLineLimit)` + `.truncationMode(.tail)`, code 28 pt monospaced `textHi` with label `remote.request.code`, fingerprint 13 pt monospaced `muted` with label `remote.request.fingerprint`, instructions `remote.request.instructions` (may wrap; truncating it would cut "approve only if..."), 18 pt fixed status row (spinner / done / error / muted text), secondary `common.cancel` (`.cancelAction`), primary `remote.request.retry` only for expired/failed and deliberately NOT a default action. Only `ShellXPalette` tokens, flat fills, 1 px borders (via `ShellXSheetButtonStyle`), no gradients, `colorScheme` dark.
- Localizable.xcstrings: +520 lines are exactly 8 new keys (`remote.request.title/instructions/code/fingerprint/approved/denied/expired/retry`), each with en and de, fr, es, ar, ja, ko, zh-Hans, zh-Hant, vi (state translated); en/vi verbatim from the brief; no removed or changed existing keys; inserted after U1's block. `common.cancel` (vi "Huỷ") and `remote.signin.error.network` already existed with vi.
- Gate: the presenter is only reachable through `ShellXRemoteUIActions`, which returns early when `ShellXRemoteUIModel.shared.service` is nil (gate off). `RequestAccessSheetPresenter.shared` is lazy, so nothing is created or runs with `ShellXFeatures.remoteMachines == false`.

Defects found and fixed:
1. **Tasks outlived the sheet (item d).** The retry `Task` was untracked and held `self` strongly. After Cancel, a finishing retry still called `refresh()`, which could schedule the auto-close and then call `onApproved` -> `openSession` on a machine the user had walked away from. Now `RequestAccessTracker.stop()` is checked by every path (refresh, retry result, auto-close), the retry and auto-close Tasks are stored and cancelled in `stop()`, both use `[weak self]`, and the Combine subscription is dropped.
2. **Stale pairing could stand in for the new request.** `currentPairing` fell back to the newest pairing when `expectedCode` matched nothing, so for the moment before the service published the new request an older (e.g. expired, with "Try again") pairing's code was shown. Tightened: with an expected code only a pairing with that code is shown, otherwise nothing (spinner). RED test first.
3. **Leftover candidates during a retry.** While a retry was in flight, a service change could surface another unrelated older pairing for the same machine. The tracker now shows nothing while `isRetrying`.
4. **Retry decision logic was app-only and untestable.** Moved the superseded set, the in-flight flag, "retry only for expired/failed", "auto-close once per pairing" and "stopped" into the pure package type `RequestAccessTracker` (10 tests). The app model is now a thin Task owner.
5. **Possible compile error.** `RequestAccessSheetPresenter.present` bound `if let model` and later declared a local `let model` in the same function, a shadowing pattern that can trip "use of local variable before its declaration". Renamed (`current`, `newModel`, `newSheet`). Also dropped the redundant `isRetrying` publisher/`.disabled`.
6. **Fixture regression.** The WIP expired the MacBook Air's pending request 8 s after sign-in, so U1's "waiting · 123 456" header vanished almost immediately. Now that pairing stays waiting (click its header to reopen the sheet); the first request to any machine expires after 6 s ("Expired" + "Try again"), every later one is approved after 4 s (sheet shows Approved, closes after 1 s, session opens). DEBUG only.
7. **pbxproj ids.** The WIP used sha1-derived ids (`92E17B07...`, `A212508A...`). Ruling 13 says new ids use `5E13C3`; renumbered to `5E13C3000000000000000020` (PBXBuildFile) and `...21` (PBXFileReference). Unique (grep: 2 and 3 occurrences, all this file). U1's five files keep their wire-app-sources ids (unchanged, out of scope).
8. Restored the `// ShellX: present RequestAccessSheet (U2)` marker at the hook call in `ShellXRemoteUIActions.requestAccess`.

## Files (diff vs U2 BASE 4bbaac28ed, source files only)
- `Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/RequestAccessModel.swift` (WIP; `currentPairing` tightened at :62-78, function at :68)
- `Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/RequestAccessTracker.swift` (new)
- `Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/RequestAccessModelTests.swift` (WIP + tightened/added tests)
- `Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/RequestAccessTrackerTests.swift` (new, 10 tests)
- `Sources/ShellX/Remote/UI/RequestAccessSheet.swift` (labels, `RequestAccessSheetModel`, `RequestAccessSheet`, `RequestAccessSheetPresenter`)
- `Sources/ShellX/Remote/UI/ShellXRemoteUIActions.swift` (hook + `.waiting` click reopens the sheet)
- `Sources/ShellX/Remote/UI/ShellXRemoteFixtureService.swift` (DEBUG: outgoing pairings)
- `Resources/Localizable.xcstrings` (+8 keys), `cmux.xcodeproj/project.pbxproj` (+4 lines)
- Evidence: `u2-evidence/` (red-3, green-model-3, red-4, green-tracker, green-final, verify-local-final, typecheck; earlier WIP logs red, red-2, green, verify-local kept as found)

## TDD evidence
- RED 1 (`u2-evidence/red-3.txt`): tightened `currentPairing` tests written first; compiled, failed at runtime: `aKnownCodeNeverFallsBackToAnotherPairing` (returned "stray" for expectedCode 000000 and 222222) and `currentPairingIs...` (returned "stray"); 3 issues, rc=1.
- GREEN 1 (`green-model-3.txt`): `RequestAccessModelTests` 9/9 after the one-expression implementation.
- RED 2 (`red-4.txt`): tracker tests written first: `cannot find 'RequestAccessTracker' in scope`, rc=1.
- GREEN 2 (`green-tracker.txt`): `swift test --filter RequestAccess` -> `Test run with 19 tests in 2 suites passed`.
- Final (`green-final.txt`): `swift test --package-path Packages/Shared/ShellXBrand` -> `Test run with 89 tests in 7 suites passed` (was 78: +10 tracker tests, +1 model test), 0 warnings, 0 errors.

## Verification output
```
$ swift test --package-path Packages/Shared/ShellXBrand      -> 89 tests in 7 suites passed
$ python3 scripts/verify-local.py --all --swift-changed main -> PASSED: 16/16 selected checks ran (swift-syntax 59 files, xcstrings, localization, localization-defaults, project, wire-app-sources, feature-flags, ...)
$ python3 scripts/localization_catalog.py check              -> 10 catalogs, 9 locales: 0 parity errors
$ python3 scripts/normalize-pbxproj.py                       -> rc 0, no further change
$ bash scripts/check-pbxproj.sh                              -> rc 0
$ python3 scripts/wire-app-sources.py --check                -> ok
$ python3 -m unittest tests/test_shellx_*.py                 -> OK
$ swiftc -typecheck -swift-version 5 -target arm64-apple-macos14.0 (see typecheck.txt), -D DEBUG and release -> rc 0, no diagnostics
```
Not run (rule): xcodebuild, reload.sh, test-app.sh.

## Wiring map (file:line)
- Header "Request access" button -> `Sources/ShellX/Sidebar/SidebarMachineHeaderCellView.swift:164-165` -> `ShellXRemoteUIActions.requestAccess` `Sources/ShellX/Remote/UI/ShellXRemoteUIActions.swift:10-21` (hook marker `// ShellX: present RequestAccessSheet (U2)` at :15) -> `presentRequestAccess(to:expectedCode:)` :38-41 -> `RequestAccessSheetPresenter.shared.present(...)` `Sources/ShellX/Remote/UI/RequestAccessSheet.swift:244` (sheet on `NSApp.cmuxMainWindowForModalPresentation(preferring: NSApp.keyWindow)` :268 via `CloudSheetWindow.beginSheet(on:)` :271, floating fallback :274).
- Clicking a "waiting · code" header -> `Sources/Sidebar/AppKitList/SidebarWorkspaceTableController.swift:1043-1046` (U1 hook) -> `handleClick` `.waiting` :65-67 -> same presenter; a sheet already up for that machine just follows the code (`RequestAccessSheetModel.follow`).
- Approved -> `RequestAccessSheetModel.scheduleAutoClose` (RequestAccessSheet.swift:121, delay `RequestAccessModel.autoCloseDelay`) -> `onApproved` -> presenter `dismiss()` + `ShellXRemoteUIActions.openSession(on:)` (closure set at RequestAccessSheet.swift:255, fired at :129).
- Retry -> `RequestAccessSheetModel.retry` :85 -> `service.requestAccess` in a main-actor Task -> tracker follows the NEW pairing; the old one is superseded.
- Cancel / Esc -> `RequestAccessSheetModel.cancel` -> `stop()` :112 (cancels retry + auto-close Tasks, drops the subscription) -> `onCancel` -> presenter `dismiss()`.
- Fixture: `ShellXRemoteFixtureService.swift:66` (`requestAccess` creates the `OutgoingPairing` with fingerprint `a1b2c3d4e5f60718`), `:90` (`finish`).
- pbxproj: `5E13C3000000000000000020` PBXBuildFile (project.pbxproj:3141, app Sources phase :16471), `5E13C3000000000000000021` PBXFileReference (:7724, Sources group :12413). Phase A5001051 is the cmux app target.
- Package: `RequestAccessModel.swift`, `RequestAccessTracker.swift` in `ShellXRemoteUI` (already a product linked into the app by U1).

## Security (Review Focus 3)
- Code and this Mac's fingerprint are rendered together whenever a pairing is shown (all five statuses, tested for approved/waiting); when none is published or a retry is in flight neither is shown (nothing to compare).
- The sheet never approves anything: it has no approve action; Return does nothing (no `.defaultAction`; the retry button is not default). The only automatic step is closing + `openSession` after the SERVICE reports `.approved`.
- The code shown is the one `requestAccess` returned (a different pairing's code is never substituted).
- Nothing is logged.
- The DEBUG fixture simulates the other machine approving/expiring so the UI can be looked at; that is fixture-only and says so.

## Uncompiled symbols (each grepped; type-checked via swiftc where marked T)
- T `CloudSheetWindow(rootView:)`, `.window`, `.beginSheet(on:)`, `.orderFrontFloating()` (`Sources/Cloud/CloudSheetWindow.swift`, real file in the type-check).
- `NSApplication.cmuxMainWindowForModalPresentation(preferring:)` (`Sources/CmuxModalAlertPresentation.swift:40`, `@MainActor`); STUBBED in the type-check with the same signature.
- `ShellXSidebarHeaderRow` (U1, app) STUBBED in the type-check (only for `ShellXRemoteUIActions.handleClick`).
- T `ShellXSheetButtonStyle`, `ShellXRemoteServicing`, `ShellXRemoteUIModel.shared.service`, `ShellXRemoteUIActions.openSession(on:)` (U1 files, real).
- T `MainActor.assumeIsolated` in the Combine sink (same as U1 and `SidebarWorkspaceRowCellView.swift:102`), `Task { @MainActor [weak self] in ... guard let self }`, `Font.system(size:weight:design:)`, `Text.textSelection(.enabled)`, `switch` over `RequestAccessModel.Tone?` with `case .muted, nil`.
- T `String(localized:defaultValue:)` + `String(format:)` for `%@` strings: same pattern as `ContentView.swift:7582`.
- Package: Swift 6 language mode; `RequestAccessTracker` and the model are `Sendable` value types.
- App target is Swift 5.0, macOS 14.0 (project.pbxproj `SWIFT_VERSION`, `MACOSX_DEPLOYMENT_TARGET`).

## Decisions
1. `currentPairing` tightened (above). Cost if wrong: if the real service's `OutgoingPairing.code` format ever differs from what `requestAccess` returns, the sheet shows a spinner instead of a pairing; Cancel still works. L5's plan has both as the raw code ("123456").
2. Retry failure only beeps (as U1's actions) and the old pairing with "Try again" comes back.
3. Expired uses the `muted` tone (the brief names no colour); failed/denied use `error`; approved `done`.
4. Fixture: first request per machine expires (6 s), later ones approve (4 s). The brief's required states waiting/approved/expired are reachable by hand; denied and failed are covered by the package tests only.

## Concerns
1. App code has not been built by xcodebuild. The type-check covers the whole U2 file set and passed in DEBUG and release, but it used the local macOS SDK and two stubs, so CI is still the first real build.
2. A "waiting" header whose pairing is not in `service.outgoing` (e.g. after a relaunch with a service that does not persist outgoing pairings) opens a sheet with title + spinner + Cancel only; there is no own fingerprint to show without a pairing. Revisit when L5 Task 13 defines `outgoing` persistence.
3. Cancelling the sheet while a retry is in flight cancels the Task, not the underlying `service.requestAccess` call; its pairing then expires server-side (same as Cancel in general).
4. If another sheet is already attached to the host, the request sheet falls back to a floating window (same as SignInSheetPresenter).
5. The upstream comment at `SidebarWorkspaceTableController.swift:1043` still says the header click "opens a session"; it also reopens the request sheet for a waiting header now. Not edited (comment only, would touch an upstream file).
6. U1 source-file pbxproj ids are sha1-derived (wire-app-sources.py), not `5E13C3`; U2 uses `5E13C3...20/21` per ruling 13.
