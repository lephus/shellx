# SDD ledger — plan: /Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/plans/2026-10-19-native-desktop-w2-mac-remote.md

Scope: lane L3, Part B Tasks U1-U4 only (Part A = L5). Branch shellx/l3-sidebar after W1 Task 10 (W1 ledger in ../2026-10-18-native-desktop-w1-mac-local/progress.md).

## Pre-flight scan (U1-U4)
| Pair / task | Produces vs consumes | Finding |
| --- | --- | --- |
| U1 vs W1 T10 | U1 extends SidebarMachineKey/Input/HeaderModel, adds sections(for:local:remote:now:), keeps W1 wrapper | T10 put pure models in ShellXBrand target (ruling W1); ShellXBrand cannot see RemoteMachine (ShellXRemoteCore) -> conflict of module placement |
| U1-U4 vs L5 T10 | consume RemoteMachine, LinkState, PairingRequest, OutgoingPairing, PairingDisplay | present on local branch shellx/l5-swift (8702b7e16d + fixes), not yet on sprint -> merge l5-swift |
| U1-U4 vs L5 T13 | consume ShellXRemoteService (K4 + additive outgoing/isSignedIn/remoteWorkspaces/signIn), ShellXRemoteGate | not written yet -> conflict |
| U3 vs W1 T11 (L2) | U3 adds an item to the title-bar bell feed | T11 not on branch -> conflict |
| U4 vs spec 7.1 presence strip | U4 hosts banner in the presence strip container | no presence strip exists in the app yet -> conflict |
| U1 self | tests via scripts/shellx/test-app.sh | app-host build not possible (disk, W1 ruling) -> conflict |
| U2 self | sheet presented from U1 header action; approved -> openSession | agrees |
| U3 self | NSPanel defaultButtonCell == nil test | app-only (AppKit) -> cmuxTests, unexecuted |
| U4 self | banner fixed 28 pt, pushes pane down | agrees |
| Part B strings | 27 keys with vi | agrees (catalog took vi in T10) |

Ruling: merge local branch shellx/l5-swift (L5 Task 10 ShellXRemoteCore, unpushed, still in L5 review) into shellx/l3-sidebar before U1 — Part B consumes its real types; dispatcher allows merging L5 when it has them — cost if wrong: L5 fix commits after the merge must be re-merged (L0 merges l5 anyway; same commits, no conflict).
Ruling: pure Part B models (remote section mapping, header action, RequestAccessModel, ApprovalPromptModel, RemoteLinkBannerModel, sign-in error mapping, RemoteUISnapshot) live in a new package target ShellXRemoteUI (deps ShellXBrand + ShellXRemoteCore) with Swift Testing tests in ShellXRemoteUITests (swift test + CI); ShellXBrand's grouping gets a module-neutral remote input so it needs no ShellXRemoteCore dependency; views/panels in Sources/ShellX/Remote/UI/ — same reason as the W1 ruling (CI builds no cmuxTests, no local app-host build) — cost if wrong: one more package product linked in the pbxproj; plan's cmuxTests/ShellXRemoteUITests holds only AppKit-only checks and is not executed in the sprint.
Ruling: until L5 Task 13 lands, the UI binds to an app-side protocol ShellXRemoteServicing (K4 members verbatim + additive outgoing/hostState/isSignedIn/remoteWorkspaces/signIn/signOut) with a DEBUG fixture implementation (SHELLX_REMOTE_UI_FIXTURES=1); UI is on only when ShellXFeatures.remoteMachines (false) or, DEBUG only, that env var — K4 is the contract; L5's service is not written yet — cost if wrong: an adapter `extension ShellXRemoteService: ShellXRemoteServicing {}` after merge, or renames if L5 deviates from K4.
Ruling: U3's title-bar bell item is skipped (W1 Task 11 bell is L2's, not on this branch); the floating approval panel is the on-site prompt — cost if wrong: one follow-up hook into the bell feed after checkpoint 1.
Ruling: U4 banner sits at the top of the workspace content area for workspaces in remoteWorkspaces (no presence strip exists yet) — cost if wrong: banner moves into the strip when W3 builds it.
Merged shellx/l5-swift f749732953 -> d58b7b7189. pbxproj conflict: L3's cmuxTests ShellXBrand product-dependency id 5E11A00000000000000000A4 collided with L5's ShellXRemoteCore A4.
Ruling: L3's id renumbered to 5E13C3000000000000000001 (L3 ids use prefix 5E13C3… from here on) — L5's is upstream of L3 in the merge order — cost if wrong: none (ids are opaque; check-pbxproj rc=0).
U1 BASE d58b7b7189
U1: implementer DONE_WITH_CONCERNS d58b7b7189..fe8dfc2e1e (70 package tests, l10n 0 err, check-pbxproj 0); concerns: offline-machine workspaces hidden incl. selected; now unused; fixture 4th machine; failed/offline link -> .open
U1: review Spec ❌ (common.cancel lacks vi "Huỷ") / quality Needs fixes; no compile risks found statically.
Ruling: an offline remote machine with access .none shows no header action (brief: .none -> .requestAccess) — an offline machine cannot approve a request (U14), a button that can only fail is noise — cost if wrong: one-line mapping change.
U1: minor (deferred): non-ShellXCoreError errors (incl. CancellationError) map to the network text (SignInErrorMessage.swift) — brief says "else the code".
U1: minor (deferred): offline-machine workspaces hidden; a selected one cannot be revealed (SidebarMachineGrouping.swift:249-253) — revisit with U4.
U1: minor (deferred): `now` unused in sections(); last-seen from earlier days shows HH:mm only.
U1: minor (deferred): sign-in text fields use system .roundedBorder, not raise/border tokens.
U1: minor (deferred): NSTableView row action vs embedded Request-access button click untested.
U1: fix round 1 dispatched (common.cancel vi; clear password; DEBUG gate also SHELLX_REMOTE_MACHINES)
U1: fix round 1/5 (3 addressed, 0 open; commits fe8dfc2e1e..4bbaac28ed)
U1: complete (commits d58b7b7189..4bbaac28ed, review clean)
U2 BASE 4bbaac28ed
RESUME 2026-10-19 on richard's Mac (paths: main checkout /Users/richard/Documents/helper/shellx, worktree /Users/richard/Documents/helper/shellx-wt/l3-sidebar; plan-path rewritten; gh CLI absent -> CI watched via api.github.com with curl). HEAD baa6015b59; WIP commit 4077bddaa3 (U2, unreviewed) re-enters implement->review. CI baseline of baa6015b59 pushed as side branch shellx/l3-sidebar-wip1 (earlier runs for fe8dfc2e1e/baa6015b59 were cancelled at the stop, so U1 app code is not yet CI-compiled).
Ruling: disk is no longer scarce (242 GB free) but keep W1/U1 ruling: no local xcodebuild in implementers; CI (shellx-mac) is the compile check — cold build ~60 min, one local build lock otherwise — cost if wrong: compile errors found a CI round later.
U2 BASE 4bbaac28ed (WIP 4077bddaa3 on top)
U2: implementer DONE_WITH_CONCERNS 4bbaac28ed..62e123b837 (89 package tests, verify-local 16/16, swiftc typecheck); concerns: app uncompiled (CI), waiting header w/o outgoing pairing shows spinner only, cancel mid-retry cancels Task not service call
U2: review (opus) Spec compliant / quality Approved; no Critical/Important. Warnings resolved by controller: (3) instructions text wraps (RequestAccessSheet.swift:164) — Ruling: instructions may wrap (brief gives no truncation for it; truncating the compare-code-and-fingerprint sentence would cut the security instruction) — cost if wrong: add lineLimit(2); (5) retry assumes L5 gives each pair.request a fresh OutgoingPairing.id (plan T13 :746 says so) — cost if wrong: spinner after retry until a K-change/fix; (4) waiting-header click reopening the sheet is a benign extra; (2) brief Step 4 by-eye check -> L0 checkpoint smoke.
U2: minor (deferred): fixture requestCounts reset on sign-out can let a stale timer settle a new pairing (DEBUG only; ShellXRemoteFixtureService.swift:77-87,133)
U2: minor (deferred): ShellXRemoteUIActions.swift:67 recovers raw code by stripping spaces from display string
U2: minor (deferred): retry errors only beep (RequestAccessSheet.swift:96); raw failure codes shown unlocalized (RequestAccessModel.swift:112)
U2: minor (deferred): machine id shown in title if machine list empty after sign-out (RequestAccessSheet.swift:51,74), spinner until Cancel
U2: minor (deferred): app-side RequestAccessSheetModel glue untested; replacing a sheet during 1 s approved window drops that openSession (RequestAccessSheet.swift:244-251); fixture ownFingerprint equals fixture-pc fingerprint (:23)
U2: complete (commits 4bbaac28ed..62e123b837, review clean) — app compile pending CI
U2 pushed 62e123b837 to origin shellx/l3-sidebar (CI for U1+U2 app code)
U3 BASE 62e123b837
U3: implementer DONE_WITH_CONCERNS 62e123b837..221485b0a3 (package 120/120, verify-local 16/16, swiftc typecheck incl. cmuxTests); concerns: app uncompiled (CI), defaultButtonCell override / NSPanel init riskiest, no arming delay on buttons, first click may only activate app; extra key remote.approve.fingerprint; implementers force-add .superpowers/ files into git (cleanup commit due before final).
Ruling: U3 bell item skipped (carried from preflight) — W1 Task 11 not on branch — cost: one hook after checkpoint 1.
U3: review (opus) Spec compliant (warnings) / quality Needs fixes — Important 1: Approve can fire on a request the person had no time to compare (next request swapped under the pointer; makeKey + keyboard focus: Tab Tab Space can press Approve) ; Important 2: decision bound to pairing id only, not to the code+fingerprint the person compared (same id with changed requester key would be approved).
U3: minor (deferred): single in-flight slot blocks whole queue (Tracker:41,81-85); raw failure codes unlocalized (Model:131); requesterName not sanitized (newline/bidi) and its test proves nothing (ApprovalPromptModelTests.swift:199-204); AppKit test shallow, controller untested; denied request can reappear after prune (Tracker:83); Task.sleep ignores system sleep.
U3: warnings resolved: W1 pbxproj ids tool-derived (as U1) ok; W2 deny() is non-throwing in K4 so deny errors cannot be shown — nothing to do; W3 compare/warning/error/code/fingerprint wrap, not truncate — Ruling: security text and digits must never be truncated, panel height may vary — cost if wrong: add lineLimit; W5 K-change request: K4 approve(_:) binds to pairing id only; L5 core should seal only to the requester key whose fingerprint was displayed (approve should carry the expected fingerprint) — not ours, reported.
U3: fix round 1 dispatched (resume implementer) with Important 1+2
U3: fix round 1/5 implemented 221485b0a3..6a9cba0a9d (137 package tests); re-review dispatched
U3: re-review (opus) fix round 1: both Important ADDRESSED, no new Critical/Important.
U3: fix round 1/5 (2 addressed, 0 open; commits 221485b0a3..6a9cba0a9d)
U3: minor (deferred, for final review triage): arming clock counts time while another decision is in flight (ApprovalPromptTracker.swift:88,120-128: repeat-click after a long busy could approve B at the first enabled click; narrow); backwards clock stretches the wait (ApprovalPromptTracker.swift:57-60, test name misleading); first-click behavior of becomesKeyOnlyIfNeeded + .focusable(false) unverified without a real build (keyboard-only users cannot decide — by design for the security prompt; VoiceOver activation to confirm at smoke).
Ruling: Approve and Deny buttons are .focusable(false) and the panel does not makeKey on arrival (Tab-Space from a terminal must never approve) — keyboard-only users cannot approve from the keyboard — cost if wrong: restore focusability behind the arming delay.
U3: complete (commits 62e123b837..6a9cba0a9d, review clean after 1 fix round) — app compile pending CI
U4 BASE 6a9cba0a9d
CI shellx-mac run 39193496466 on 62e123b837 (W1 T10 + U1 + U2 app code) = success
U4: implementer DONE_WITH_CONCERNS 6a9cba0a9d..e96ca97ff9 (package 161/161, verify-local 16/16, swiftc typecheck, throw-away AppKit harness); anchor Sources/ContentView.swift:1849 ForEach(mountedWorkspaces) modifier; concerns: portal geometry + minimal mode unverified; extra key remote.banner.retryIn
U4: review (opus) Spec compliant / quality Approved; no Critical/Important. Warnings: portal resync on 28 pt shift + minimal presentation mode unverified (first dev build / L0 smoke).
U4: minor (deferred): bannerHeightIsFixed mostly asserts constants; " · " separator hard-coded; countdown frozen if retryAt-now>600s (not reachable with ReconnectBackoff); out-of-sight ticking when sidebar selection hides tabs; doc comment nits.
U4: complete (commits 6a9cba0a9d..e96ca97ff9, review clean)
Coordinator note (L5): call forgetRemoteWorkspace(_:) when a workspace closes; tolerate remote workspaces whose machine id is no longer in machines. User rule from now: NO Co-Authored-By/attribution lines in commit messages.
Final review (opus): mergeable yes, no Critical. Important (fix BEFORE ShellXFeatures.remoteMachines flips, not before merge) — Ruling: deferred to the lead/post-checkpoint-1 pass, they do not affect gate-off — cost if wrong: gate flip with these defects: (1) workspaces on offline remote machines vanish (SidebarMachineGrouping.swift:264 / RemoteMachineSections.swift:102) — keep rows dimmed; (2) requesterName unsanitized (ApprovalPromptModel.swift:142); (3) raw/unlocalized failure codes, non-core errors read as network, requestAccess/openSession failures only beep (ApprovalPromptModel.swift:149, ApprovalPromptController.swift:100, SignInErrorMessage.swift:35, ShellXRemoteUIActions.swift:20,36, RequestAccessSheet.swift:96).
Final minors: hidden-sidebar liveRowIds drops header ids (ContentView.swift:12383); cmuxTests lacks ShellXBrand PBXBuildFile; forget hook misses last-workspace/window teardown.
K4 conformance: ShellXRemoteServicing matches L5 ShellXRemoteService member by member; adapter = `extension ShellXRemoteService: ShellXRemoteServicing {}`, return .shared at ShellXRemoteServicing.swift:87, make ShellXRemoteUIGate.isEnabled follow ShellXRemoteGate.
