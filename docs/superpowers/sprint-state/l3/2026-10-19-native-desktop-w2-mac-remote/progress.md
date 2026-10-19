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
