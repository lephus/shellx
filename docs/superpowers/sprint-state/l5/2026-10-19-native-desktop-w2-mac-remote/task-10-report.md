# Task 10 report: ShellXRemoteCore

Worktree /Users/lehuuphu/Documents/myProjects/shellx-wt-l5-swift, branch shellx/l5-swift.
Commits: 8702b7e16d (package + tests), 58a0573d25 (pbxproj link).

## Implemented
Library product + target `ShellXRemoteCore` (Foundation only) and test target `ShellXRemoteCoreTests` in Packages/Shared/ShellXBrand/Package.swift. Files under Sources/ShellXRemoteCore: RemoteModels, SHA256Pure (internal pure-Swift SHA-256, tested vs "abc", "", 448-bit vectors), RemotePaths, ReconnectBackoff (also holds TicketSchedule), LinkStateMachine, BridgeFrame, InviteURI, ApprovalGate, RelayRoute, RemoteCommandLine, ShellXCoreClient (+ JSONValue per R3), PairingDisplay. Note: no separate TicketSchedule.swift (folded into ReconnectBackoff.swift).

## Deviations / verified-against-source
All argv flags verified, none needed to change:
- server start: main.rs:696-699 (--session/--socket), 765-766 (--ephemeral/--headless), 794/802/810 (--remote-state-dir/-link-socket/-admin-socket), 830/835/846 (--relay/--relay-slot/--relay-ticket-file). `server start` rewrite to --headless: main.rs rewrite_server_start (~1321-1350); explicit --headless is fine.
- server stop --force: localization.rs:1284 and cli.rs:829.
- remote enroll: remote_cli.rs parse_enroll_admin_args (1389-1480): --session/--state-dir/--admin-socket/--json/--ttl/--advertise/--relay-route/--relay-slot/--relay-ticket-file; approve/deny take the invitation id as positional (placed right after the action).
- remote connect: remote_cli.rs:283 (--invite-file), 404-415 (--device-name, --state-dir, --local-socket, --relay-slot, --relay-ticket-file), 467-469 (--exit-with-parent/--headless/--json); positional route at ~505.
- attach: main.rs:690-705 (`attach`, --socket, --terminal accepted among startup options).
- enrollCreate uses the `ttlSeconds` parameter for --ttl (brief literal "300" is the caller's value).

Invite format deviations (R4), source identity.rs:67-79 and shellx-core pairing.rs:111-161:
- The invitation id JSON field is `id` (brief wrote `invitation_id`); InviteSummary.invitationID maps from `id`.
- daemonFingerprint is the invite's `daemon_fingerprint` field, accepted only if it equals base64url-nopad(SHA-256(daemon_public_key)[..16]) (same check as shellx-core). Also checks version == 1, relay+ws|wss|https|do scheme, slot non-empty, <=256 bytes, no whitespace/control. `secret` and `ticket` are not declared in the decoding struct, so never decoded.

attachShellCommand: returns `'sh' '-c' '<script>' 'sh' '<client>' '<sock>' '<id>'`, every word single-quoted (like CloudFileExplorerService shellQuote; always quotes, so `'term_1'` matches). Values travel as positional params ($1..$3), so no value is ever re-parsed as shell. Script verified under /bin/sh (loop/exit path). Strings verbatim: `\r\n[ShellX] đang kết nối lại… / reconnecting…\r\n`, `[ShellX] phiên đã kết thúc / session ended` after 10 consecutive failures, exit 0; exit 0 on clean attach exit.

LinkStateMachine choices where the brief was silent: mintFailed fatal codes (unauthorized/forbidden/not_logged_in) emit only [.publish(.failed)] (spawn never ran); events ignored in states where they make no sense (retryDue outside reconnecting, exited while offline/idle/failed, machineOffline while idle); `connected` publishes .connected and resets attempt.
ApprovalGate: approve allowed while age <= 300 s; entry consumed on any decide (single use).

## Tests
`swift test --package-path Packages/Shared/ShellXBrand`: 30 tests (5 existing ShellXBrand + 25 new), all pass, no warnings (Swift 6 mode). RED: first run with stub target failed to compile ("cannot find 'PairingRequest' in scope" etc.), GREEN after implementation. Extra tests beyond the brief: sha256 vectors, exact path layout, enroll/connect argv, frame wire format, invite rejection cases, JSON param encoding, stop event, pairing expiry.

## pbxproj
Linked to the `cmux` app target only (not cmux-cli): XCSwiftPackageProductDependency 5E11A00000000000000000A4, PBXBuildFile 5E11A00000000000000000A5, frameworks phase entry (next to ShellXBrand A2), packageProductDependencies entry. `plutil -lint` OK. `verify-local.py --only test-wiring` first failed only on section ordering; applied `scripts/sync-test-wiring` normalization (1-line reorder of the new PBXBuildFile) and it now passes. No Xcode build run (CI shellx-mac.yml). `--affected` ran the other 5 checks green.

## Cleanup
Deleted Packages/Shared/ShellXBrand/.build. Disk 23 GB free. Not pushed.

## Concerns
- Windows/L3 consumers should know the invite id field is `id`.
- Pending app targets that also need the product (cmux-cli does not) — not linked by design.

## Fix round 1 (R17)
Change: RemoteCommandLine.attachShellCommand now records `date +%s` before each attach, resets the failure counter when the attach ran >= 10 s (attachResetAfterSeconds), gives up after 45 consecutive failures (attachMaxConsecutiveFailures) with sleep 2 (attachRetryDelaySeconds); named constants; messages verbatim; exit 0 on give-up and clean exit. Public signature unchanged; internal overload takes retryDelaySeconds/maxFailures/resetAfterSeconds.
Covering tests (run real /bin/sh with a fake client in a temp dir): attachWrapperGivesUpAfterMaxConsecutiveFailures (exactly 3 attempts, status 0, message), attachWrapperCleanExitStopsWithoutMessage, attachWrapperResetsCounterAfterLongAttach (attempt 3 runs 3 s with resetAfter 2, give-up at attempt 5 not 3), attachWrapperProductionDefaults (45 / sleep 2 / 10).
Command: `swift test --package-path Packages/Shared/ShellXBrand` -> "Test run with 34 tests in 1 suite passed after 4.290 seconds", no warnings. Commit: see git log (fix(shellx): attach wrapper counts consecutive failures and outlasts the link backoff).
