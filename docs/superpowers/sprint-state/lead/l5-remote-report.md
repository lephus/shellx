# l5-remote interim report (2026-10-19 ~05:00 +07) — lead could not be reached by SendMessage from this lane

## Answer to lead re old vPTY worktree
c38992fd2b is a commit of lephus/shellx (this repo), branch shellx/l5-vpty (worktree ~/Documents/myProjects/shellx-wt-l5-vpty), pushed, merged --no-ff into shellx/l5-remote (a3811a5ecd). The old repo has no such object; its shellx/l5-vpty is still 36d7697869. The uncommitted files in ~/Documents/myProjects/shellx-pro-wt-l5-vpty (03:18) were copied at resume (ruling R10) and are the base of 00a93cd521 (+ fixes 631a63d7c6, c38992fd2b). 
=> ~/Documents/myProjects/shellx-pro-wt-l5-vpty and ~/Documents/myProjects/shellx-pro-wt-l5 are NO LONGER NEEDED (remove at will). Keep ~/Documents/myProjects/shellx-pro/cmux-tui/target (this lane's shared CARGO_TARGET_DIR).

## Progress
Tasks 1-7 complete (reviews clean). Task 8 next.

## ready (package) f749732953 — for L0 / L3 (Task 10 says: merge early into shellx/sprint, Part B builds on it)
Branch shellx/l5-swift @ f749732953 (pushed): ShellXRemoteCore library product in Packages/Shared/ShellXBrand (models, RemotePaths, backoff, LinkStateMachine, BridgeFrame, InviteURI, ApprovalGate, RelayRoute, RemoteCommandLine, ShellXCoreClient, PairingDisplay; 34 swift tests green locally), linked into the cmux app target in project.pbxproj. Branch base 8afed49289 = l5-remote incl. shellx-core + virtual PTY (no Swift app code yet). shellx-mac CI run pending on the branch.

## ready c6c1875324 (after Task 8) — shellx/l5-remote
shellx-core (K3: config/auth/version/machines/tickets/pair, sealed invite D4), virtual PTY seam in cmux-tui-core, remote e2e harness + .github/workflows/shellx-remote.yml. CI shellx-remote run 39173969849 green (core ubuntu+macOS, ShellXBrand swift tests, bridge-e2e: 11 virtual_pty tests + 4 e2e tests ok on Linux).
K-change requests so far: (1) K3 pair.approve `fingerprint` should be required (core already fails closed without it); (2) D4 invite not authenticated to the target — bind to target device key + show target fp on requester; (3) K2/D6: cmux strips the path from invite routes, a pathless route dials /v1/relay -> relay.shellx.pro must also serve /v1/relay (stock cmux-relay serves only /v1/relay and /ws, so /v2/relay needs an nginx rewrite anyway).
Note for L6: sealed invite refuses empty pairing_id on both ends; pairing_id must match [A-Za-z0-9_-]{1,128}; KAT in shellx-core/src/seal.rs tests.

## Disk alarm (l5, ~06:40)
df shows 11 GB free (floor 15). l5 uses: shared cmux-tui target 4.0 GB (~/Documents/myProjects/shellx-pro/cmux-tui/target), shellx-core target 1.7 GB, ghostty submodules 2 x 0.8 GB. ~/Library/Developer/Xcode/DerivedData is 14 GB (other lanes' Xcode builds, not touched by l5). l5 removed its merged worktrees (shellx-wt-l5-vpty, shellx-wt-l5-swift). l5 is doing no local Xcode builds (R18); app compile evidence comes from shellx-mac CI.
