# Task 5B report: `shellx-remote`, the SSH remote helper ShellX builds itself

Status: DONE_WITH_CONCERNS. The code and tests are finished and green. The manual SSH check (Step 5, second half) is left for the user.
Branch: `shellx/l1-5b` in `/Users/lehuuphu/Documents/myProjects/shellx-wt-l1-5b`, base `c3afe0da80`. Nothing was pushed.

## Commits
| SHA | Subject |
|---|---|
| 2f060a11d3 | feat(shellx): shellx-remote helper uses ~/.shellx, /tmp/shellx-remote-<uid> and busybox name shellx |
| 7f266c7041 | feat(shellx): SSH bootstrap installs shellx-remote under ~/.shellx; Release builds ignore the dev daemon fallback |
| c78de9976e | feat(shellx): relay bootstrap staging, daemon cache and docs name shellx-remote under ~/.shellx |
| c84c0f8171 | feat(shellx): CLI ssh relay and remote-daemon-status use ~/.shellx and download.shellx.pro |
| b65b978f9a | feat(shellx): build_remote_daemon.sh cross-builds shellx-remote; manifests point at download.shellx.pro |

## What was implemented

### Go helper (`daemon/remote`)
- New file `cmd/cmuxd-remote/shellx_names.go` holds three constants: `remoteHelperName = "shellx-remote"`, `remoteCLIName = "shellx"` and `remoteStateDirName = ".shellx"`. Every runtime name in the code now comes from these constants:
  - persistent daemon root: `~/.shellx/daemon/<ver>/<slot>/`
  - socket dir: `/tmp/shellx-remote-<uid>/shellx-<hash>.sock`
  - the `CMUX_REMOTE_DAEMON_SOCKET_DIR` override child: `shellx-remote-<uid>`
  - fallback socket dir: `$TMPDIR/shellx-remote-<uid>-<rand>`
  - relay files: `~/.shellx/relay/<port>.{auth,slot,shell}` and `~/.shellx/socket_addr`
  - hook log and settings: `~/.shellx/claude-hook.log` and `~/.shellx/claude-settings/`
  - tmux wait-for signals: `~/.shellx/wait-for/`
  - installed hook CLI: `~/.shellx/bin/shellx`
  - busybox argv0 `shellx`, and the `shellx-remote*` prefix enters CLI mode
  - `hello` name `shellx-remote`; usage and log lines also say `shellx-remote`
- Kept unchanged, as instructed: the Go module path `github.com/manaflow-ai/cmux/daemon/remote` and the package dir `cmd/cmuxd-remote` (both internal). The build script uses `-o` to name the binary.
- `README.md` and `.gitignore` were updated (the README Distribution section now describes download.shellx.pro and the build script).

### Swift side
- **CmuxRemoteSession:**
  - **Install path:** the probe and install path is `~/.shellx/bin/shellx-remote/<ver>/<os>-<arch>/shellx-remote`.
  - **Relay provisioning:** relay files live under `~/.shellx/relay`, the address in `~/.shellx/socket_addr`, the CLI wrapper at `~/.shellx/bin/shellx`, and the daemon link is `~/.shellx/bin/shellx-remote-current`.
  - **Diagnostics:** the log path is `~/.shellx/daemon/...`.
  - **Other files:** the TTY path, the dev build output name, and the upload and error texts.
  - **Orphan cleanup:** it now matches `shellx-remote` only. Before, it would have matched (and SIGTERM'd) an installed cmux's `cmuxd-remote` ssh transports.
- **Release gate (asked to confirm):** before this change, Release builds did NOT ignore the fallback. `allowLocalDaemonBuildFallback` read the env var with no build check, so a Release app with `CMUX_REMOTE_DAEMON_ALLOW_LOCAL_BUILD=1` + `CMUX_REMOTE_DAEMON_BINARY` would upload any binary. This is now enforced in `Packages/macOS/CmuxRemoteSession/Sources/CmuxRemoteSession/Session/RemoteSessionCoordinator+Bootstrap.swift`:
  - New `static let isDebugBuild` (`#if DEBUG true #else false`).
  - `allowLocalDaemonBuildFallback(environment:isDebugBuild:)` starts with `guard isDebugBuild else { return false }`.
  - `explicitRemoteDaemonBinaryURL` goes through that same function, and so do `buildLocalDaemonBinary` and `remoteDaemonVersion()`.
  - The Xcode project has only Debug and Release configs. Debug sets `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG`, and this package already uses `#if DEBUG`.
  - Tagged Debug builds (reload.sh) keep the fallback.
  - `shellx remote-daemon-status` reports `dev_local_build_fallback` as true only in Debug (`CLI/cmux.swift`).
- **CmuxFoundation:** `RemoteBootstrapStagingCommandBuilder` stages into `~/.shellx/relay/<port>.bootstrap.sh`.
- **CmuxRemoteWorkspace:** the local cache file is `<state>/remote-daemons/<ver>/<os>-<arch>/shellx-remote`, matching the CLI, and the staging file is `.shellx-remote-<uuid>`.
- **CmuxCore/Remote, CmuxRemoteDaemon, Sources/RemoteTui:** doc comments only.
- **CLI/cmux.swift:**
  - relay auth path `~/.shellx/relay/<port>.auth`
  - `cmux ssh` relay bootstrap lines (`~/.shellx/relay`, `~/.shellx/bin/shellx`, fallback `command -v shellx`)
  - `remote-daemon-status`: `curl -fLO <downloadURL>` / `<checksumsURL>` replaces the `gh release download --repo manaflow-ai/cmux` commands; `attestation_verify_command` is removed (download.shellx.pro has no attestations); the cache name is `shellx-remote`; the help text is updated
- **Left untouched (cloud is off, Task 5):** baked cloud-VM names (`/run/cmuxd-remote.sock`, `/usr/local/bin/cmuxd-remote`, the Freestyle hello). `VMClient.swift` was not touched.

### Release scripts
- **`scripts/shellx/build_remote_daemon.sh <version> [--output-dir <dir>]`:**
  - Takes Go from `$GO` or PATH. If Go is missing it fails with `error: go not found...; install Go 1.22 ... or set GO=/path/to/go`.
  - Checks that the version is a safe path segment.
  - Builds darwin/arm64, darwin/amd64, linux/arm64 and linux/amd64 in parallel with `CGO_ENABLED=0 -trimpath -buildvcs=false -ldflags "-s -w -X main.version=<v>"`.
  - Writes to `dist/shellx-remote/<version>/`: four `shellx-remote-<os>-<arch>` files, `checksums.txt` and `manifest.json`.
  - The manifest uses `releaseURL = https://download.shellx.pro/desktop/shellx-remote/<version>`, `releaseTag = v<version>`, and per-file `downloadURL` values.
  - It then runs the verify script on the output. It does not upload anything.
- **`scripts/verify_remote_daemon_release.py`:**
  - The release URL must equal `https://download.shellx.pro/desktop/shellx-remote/<appVersion>`. The GitHub regex is gone.
  - Asset names are `shellx-remote-<os>-<arch>`, with `checksums.txt` and `manifest.json`. The nightly/rc suffix logic is removed because each version has its own directory.
  - `--verify-cli` runs `Contents/Resources/bin/shellx` (Task 3's bundled CLI name).
  - `CMUXRemoteDaemonManifestJSON` is unchanged.
- **`.gitignore`:** `/dist/` added.

### Go 1.22
Installed Go 1.22.12 for darwin/arm64 from go.dev (sha256 checked) into `~/.local/go1.22`, with no profile edits (ruling R10). Every command used `PATH=$HOME/.local/go1.22/bin:$PATH GOTOOLCHAIN=local`.

## Tests and results (final run, all on HEAD b65b978f9a)
| Command | Result |
|---|---|
| `cd daemon/remote && go test -count=1 -ldflags='-B gobuildid' ./...` | ok (8.9s); `go vet ./...` clean |
| `swift test --package-path Packages/macOS/CmuxRemoteSession` | 241 tests / 39 suites passed |
| `swift test --package-path Packages/macOS/CmuxFoundation` | 723 tests, 1 failure that was already there: `CmuxConfigSemanticValidatorTests` "embedded schema is byte-for-byte web/data/cmux.schema.json" (the file left with BUSL web/, see ac170427f5) |
| `swift test --package-path Packages/macOS/CmuxCore` | 144 passed |
| `swift test --package-path Packages/macOS/CmuxRemoteDaemon` | 32 passed |
| `swift test --package-path Packages/macOS/CmuxRemoteWorkspace` | 199 passed |
| `python3 tests/test_shellx_remote_daemon.py` | 8 OK (also passes when run from `/tmp`) |
| `python3 tests/test_remote_daemon_release_verification.py` | 14 OK |
| `python3 tests/test_remote_daemon_release_assets.py` (real build + hello on the host binary) | OK |
| `python3 tests/test_shellx_entitlements.py` | OK |
| `scripts/shellx/build_remote_daemon.sh 0.1.0` | 4 binaries + checksums.txt + manifest.json in dist/shellx-remote/0.1.0/; `shasum -c` OK; `file` shows Mach-O arm64/x86_64 and static ELF aarch64/x86-64; `./shellx-remote-darwin-arm64 version` prints 0.1.0; hello over stdio is ok; a `shellx` symlink enters CLI mode. `git check-ignore` confirms `.gitignore:96:/dist/`. The dist output was deleted afterwards. |

Notes on running the tests:
- **Go tests on this Mac:** with Go 1.22.12 on macOS 26, test binaries abort with `dyld: missing LC_UUID load command`. This was already the case at base, before any change. `-ldflags='-B gobuildid'` fixes it, and with it the base tree passes too. Release binaries built with `-s -w` run fine.
- **`vendor/bonsplit`:** the submodule is not checked out, but CmuxRemoteSession needs it. I fetched the pinned commit `d67d1b1` (19 MB) into the scratchpad and symlinked it in only for the test runs, then restored the empty placeholder. Nothing was committed, `.git/modules` was not touched, and the tree is clean.

## TDD evidence (RED before GREEN)
- **Python guard:** first run `python3 tests/test_shellx_remote_daemon.py` gave `Ran 8 tests ... FAILED (failures=8)`, then `OK`.
- **Go:**
  - New `shellx_names_test.go` plus existing tests updated to the new names.
  - First `go test` gave `FAIL` on 15 tests, for example:
    - `TestShellXPersistentDaemonDefaultRootIsUnderDotShellX: root = ".../.cmux/daemon/dev/shellx-slot"`
    - `TestShellXBusyboxNameEntersCLIMode: shouldRunCLIForInvocation("shellx", []) = false` and `("cmuxd-remote", ["ping"]) = true`
    - `TestShellXHelloNamesTheHelper: name:cmuxd-remote`
    - `TestPersistentDaemonSocketDirFallsBackFromUnsafeSymlink`
    - `TestWrapperBinaryDispatchesIntoCLI`
    - `TestTmuxWaitForSignalPath`
  - After the change: `ok`.
- **CmuxRemoteSession:** the fixtures were renamed first and the new suite was held back while running: `Test run with 237 tests in 38 suites failed ... with 19 issues`. This covered the probe, relay teardown, inherited-forward recovery and Codex wrapper suites. After the change: 241 passed. The new `ShellXRemoteDaemonNamesTests` covers install paths, relay/wrapper/cleanup scripts, orphan cleanup ignoring cmux's helper, and the Release gate.
- **CmuxFoundation and CmuxRemoteWorkspace:** with filters, RED gave `30 tests ... failed with 4 issues` and `9 tests ... failed with 1 issue`. GREEN as in the table above.
- **Release verification:** the new test file against the old script gave `FAILED (failures=6, errors=2)`; the old test file against the new script gave `FAILED (failures=4, errors=2)`. Both pass when matched.

## Files changed (73)
- Go: `daemon/remote/{README.md,.gitignore}`, plus `cmd/cmuxd-remote/`:
  - new: `shellx_names.go`, `shellx_names_test.go`
  - sources: `main.go`, `cli.go`, `claude_hook*.go`, `agent_launch.go`, `persistent_lifecycle.go`, `tmux_wait_signal.go`, `ws_pty.go`, `cloud_cli_bridge.go`
  - tests: 11 `*_test.go` files
- Swift packages: CmuxRemoteSession (11 sources, 11 tests, new `ShellXRemoteDaemonNamesTests.swift`), CmuxFoundation (1 source, 2 tests), CmuxRemoteWorkspace (2 sources, 2 tests), CmuxCore/Remote (3 comments), CmuxRemoteDaemon (2 comments), `Sources/RemoteTui/*` (3 comments).
- CLI: `CLI/cmux.swift`.
- App-host tests (they run later on CI, ruling R5): `cmuxTests/GhosttyConfigTests.swift` (orphan fixtures), `cmuxTests/WorkspaceRemoteConnectionTests.swift` (relay cleanup and upload paths).
- Scripts and tests: `scripts/shellx/build_remote_daemon.sh` (new), `scripts/verify_remote_daemon_release.py`, `tests/test_shellx_remote_daemon.py` (new, registered in the `linux-guard` lane after `test_shellx_perf_harness.py`), `tests/test_remote_daemon_release_assets.py` (now drives the ShellX script), `tests/test_remote_daemon_release_verification.py`, `tests/test-execution.toml`, `.gitignore`.

## Self-review findings
- I read the diff for every commit. The Go and Swift renames are consistent with each other. The Go side reads exactly what the Swift relay and staging side writes (`~/.shellx/relay/<port>.*`, `~/.shellx/socket_addr`, `~/.shellx/bin/shellx` → `shellx-remote-current`), and the Swift relay-script tests run those scripts against real files.
- The `remoteHelperName+"..."` format strings are constant expressions, so `go vet` is clean.
- `gofmt -l` lists `tmux_compat.go` and `tmux_corpus_ws_pty_test.go`. Both are untouched and already had the issue at base.
- `tests/test_shellx_remote_daemon.py` imports `tests/shellx_guard.py` (from Task 2) when it is present, and otherwise uses a local fallback with the same `read`/`offenders` contract. That helper is not in my base, so there is no add/add conflict. Every allowlist entry in the Swift guard is actually used (checked), and each is either a cloud-baked name or the Go package dir `./cmd/cmuxd-remote`.
- I could not compile-check `CLI/cmux.swift` locally because there are no app builds (ruling R2). The edits are string literals plus a `#if DEBUG` closure, and I checked by grep that `verifyCommand` and `signerWorkflow` have no other uses. CI will compile it.

## Concerns / follow-ups
1. **Needs Task 3 (or the controller) before SSH works end to end.** The remote `~/.cmux` tree is shared with `Sources/RemoteInteractiveShellBootstrapBuilder.swift`, which is outside my scope. That file still writes and reads `$HOME/.cmux/relay` (lines 58, 400-401, 440 `.../<port>.shell`), `export PATH="$HOME/.cmux/bin:$PATH"` (273), `CMUX_BUNDLED_CLI_PATH="$HOME/.cmux/bin/cmux"` (274), `$HOME/.cmux/bin/cmux-codex-wrapper` (275) and `cmux_cli="$HOME/.cmux/bin/cmux"` (394, 428). All of these must become `$HOME/.shellx/...`, with `bin/shellx` in place of `bin/cmux`. The codex wrapper file name `cmux-codex-wrapper` is kept; my side installs it at `~/.shellx/bin/cmux-codex-wrapper`. `Sources/SessionRemoteWorkspaceSnapshot+Restore.swift:397` (`$HOME/.cmux/bin/cmux`) needs the same change. The Go helper removes `~/.shellx/relay/<port>.shell`, so the shell state dir must move as well. App-host tests that will follow these changes: `cmuxTests/{ShellStartupMatrixTests,RemoteInitialCommandBootstrap*Tests,SSHRemoteCommandChainingTests,SSHStartupSignalLifecycleTests,FishShellIntegrationTests,RemoteShellPromptRelayTests}.swift` and `WorkspaceRemoteConnectionTests.swift:215,424`. The Task 3 ruling R7 allowlist can then drop the 5B entries.
2. **`~/.cmuxterm` on the remote is not renamed.** It is outside the brief and the guard regex. The Go helper still uses `~/.cmuxterm/{claude-teams-bin,omo-bin,omx-bin,omc-bin,cmux-claude-node-options,omo-config}` and `~/.cmuxterm/tmux-compat-store.json` on the remote host. On a host that also runs cmux's helper (including `ssh localhost` on this Mac), tmux-compat state and the agent shim dirs would be shared. I'd suggest moving them under `~/.shellx/` in a small follow-up. I didn't guess the local macOS counterpart, which is Task 3's.
3. **Dead upstream GitHub-release tooling still names `cmuxd-remote`.** This covers `scripts/build_remote_daemon_release_assets.sh` + `generate_remote_daemon_release_manifest.py` (no longer referenced by any test; its verify step would now fail on cmux names), `scripts/release_asset_guard.js`, `scripts/prune_nightly_release_assets.py`, `tests/test_ci_nightly_prune_python_compat.sh` and `tests_v2/test_ssh_*`. The `tests_v2` tests need a live app and an SSH host, so I couldn't run them here. Removing or retargeting all of these is the controller's call.
4. **User-facing "cmux" in Go messages is unchanged.** Error prefixes such as `cmux: no relay connection...`, `cmux claude-teams:` and the CLI usage text in the Go helper still say cmux. The L2 string rebrand only covers the Swift catalogs, so these need a separate decision.
5. **`tests/test_ci_signing_keychain_is_deleted_before_bundle_code.py` was already failing at base** ("found only 0 keychain jobs") because the release workflows were removed. It is not related to this task.
6. **Needs user:** Step 5's manual check. With a tagged Debug build (CI, ruling R2), run `CMUX_REMOTE_DAEMON_ALLOW_LOCAL_BUILD=1 CMUX_REMOTE_DAEMON_BINARY=dist/shellx-remote/<v>/shellx-remote-<os>-<arch>`, open an SSH workspace to a Linux VM or to `localhost` with Remote Login on, and confirm that `~/.shellx/daemon/` and `~/.shellx/bin/shellx-remote/` appear on the remote. This only makes sense after item 1 lands.
7. Uploading to download.shellx.pro is Wave 3 and needs the user's OK. Nothing was uploaded.

---

## Fix round 1: remote `~/.cmuxterm` (Important review finding)

Commit: `f7027788a3 feat(shellx): shellx-remote keeps agent shims, node-options, omo config and tmux-compat store under ~/.shellx`

### Changes
On the remote host, the Go helper no longer touches `~/.cmuxterm`. Everything it kept there now goes under `~/.shellx`, using the existing `remoteStateDirName` constant (its doc comment in `shellx_names.go` is extended):

| What | File:line | Before | After |
|---|---|---|---|
| tmux-compat store | `tmux_compat.go:1296` | `~/.cmuxterm/tmux-compat-store.json` | `~/.shellx/tmux-compat-store.json` |
| Agent tmux shim dirs | `agent_launch.go:290` | `~/.cmuxterm/<shimdir>` | `~/.shellx/{claude-teams-bin,omo-bin,omx-bin,omc-bin}` |
| Node options restore module | `agent_launch.go:362` | `~/.cmuxterm/cmux-claude-node-options` | `~/.shellx/cmux-claude-node-options` |
| OMO shadow config | `agent_launch.go:536` | `~/.cmuxterm/omo-config` | `~/.shellx/omo-config` |

- The tmux-compat store's lock file sits beside the JSON file, so it moved with it and the cross-process lock is now private to ShellX. The code that opens the store directory has no hard-coded name.
- Tests updated: `agent_launch_temp_test.go`, `agent_launch_shell_test.go` and `tmux_split_ref_test.go` now expect the `.shellx` paths.
- New test `TestShellXAgentShimsAndTmuxStoreAreUnderDotShellX` in `shellx_names_test.go`:
  - checks the store path, the omo config dir, the shim dir and the node-options module path;
  - checks that after all of these run, `~/.shellx` is the only entry in `$HOME`, so nothing lands in cmux's directories.
- Guard: in `tests/test_shellx_remote_daemon.py`, `test_no_cmux_runtime_names_in_go_daemon` now uses the regex `\.cmux/|\.cmuxterm|cmuxd-remote-|/tmp/cmuxd` over `daemon/remote` with no allowlist. Two comments were reworded so that no literal `.cmuxterm` is left in daemon/remote.
- Swift packages in my scope: they don't build any remote `~/.cmuxterm` path. The only hits are `os_log` subsystems `com.cmuxterm.app`, in `RemoteSessionCoordinator+ReverseRelay.swift:6`, `RemoteSessionCoordinator+BootstrapDiagnostics.swift:5` and `Sources/RemoteTui/SSHTuiWorkspaceCoordinator.swift:9`. Ruling R3 says to leave those, so no Swift package was touched in this round.

### RED, then GREEN
- **RED**, after extending the guard and updating the tests:
  - `python3 tests/test_shellx_remote_daemon.py` gave `FAIL: test_no_cmux_runtime_names_in_go_daemon ... Lists differ: ['daemon/remote/cmd/cmuxd-remote/agent_lau…296'] != []` and `FAILED (failures=1)`.
  - `go test -count=1 -ldflags='-B gobuildid' ./...` gave `FAIL` on:
    - `TestClaudeTeamsShellSnapshotKeepsManagedTmuxAheadOfRebuiltPath` (`.../.cmuxterm/claude-teams-bin/tmux`, want `.../.shellx/...`)
    - `TestEnsureClaudeNodeOptionsRestoreModuleLivesInPrivateHomeDirectory`
    - `TestEnsureClaudeNodeOptionsRestoreModuleRefusesSymlinkedDirectory`
    - `TestShellXAgentShimsAndTmuxStoreAreUnderDotShellX`, with five failed checks: store, omo config, shim dir, node options, and the stray `.cmuxterm` directory
- **GREEN**:
  - `go vet ./...` is clean.
  - `go test -count=1 -ldflags='-B gobuildid' ./...` gives `ok … 8.946s`.
  - `python3 tests/test_shellx_remote_daemon.py` gives `OK` (8 tests).
  - `python3 tests/test_remote_daemon_release_assets.py` gives `OK` (real cross-build plus hello).
  - `gofmt -l` on the edited files lists nothing.

### Local macOS `~/.cmuxterm` counterparts (Task 3's; not changed here)
- `Resources/shell-integration/fish/config.fish:469` (`set -l shim_state "$HOME/.cmuxterm"`). This shell integration also runs inside the remote relay shell, so Task 3 should keep it in line with the remote `~/.shellx`.
- `Resources/bin/cmux-claude-wrapper:981`
- `CLI/CMUXCLI+TmuxCompatStore.swift:44` (the local tmux-compat store)
- `CLI/cmux.swift`: lines 389, 5399, 26994, 27013, 28861, 36315, 43016, 43879
- `CLI/CMUXCLI+{AgentJournalEmission:211,CodexForkSessionWatcher:50,SessionsList:79,VMTransfer:1214/1254/1595,VMTui:89/95}`
- `CLI/CodexTurnLedger.swift:57`
- `CLI/cmux_open.swift:44`
- `Sources/{AgentHookDeliveryProcess:254,AutomationConfigStore:41,CmuxEventBus:707,Feed/FeedJumpResolver:116/137/230,OpenDiffViewerAgentBaselineLookup:144,RestorableAgentTypes:211,TerminalSurfaceRuntimeWiring:252}`
- `Packages/macOS/{CMUXAgentLaunch/.../WorkstreamPersistence.swift:47,CmuxMobileHost/.../AgentChatHookSessionStore.swift:65,CmuxCloudTui/.../CloudTuiClientPaths.swift:38/43}`
- `CmuxSettingsUI` `automations.json` copy (L2 strings)
- Cloud wireguard paths in `CmuxCloud` (cloud is off)

---

## Integration fix (after merging into shellx/l1-identity)

Commit (on shellx/l1-identity, main worktree): see `git log -1 -- tests/test_shellx_remote_daemon.py` ("test(shellx): remote-daemon guard uses tests/shellx_guard.py and filters cloud-baked literals per line").

### The failure
Task 2's `tests/shellx_guard.py` expects each `allow` entry to be a `(path, reason)` tuple, and it allows whole files. `test_swift_daemon_install_paths_are_shellx` passed bare literal strings, so it raised `ValueError: allow entry needs (path, reason)`.

### The fix
- **Import:** the local fallback is gone. The test now imports `ROOT, offenders, read` from `tests/shellx_guard.py` only, the same way `test_shellx_identity.py` does (`sys.path.insert` of the tests dir).
- **Allowed cmux names:** they are now `ALLOWED_SWIFT_LITERALS`, a list of `(literal, reason)` pairs: the cloud-baked names (cloud is off, Task 5) and the Go package dir `./cmd/cmuxd-remote`.
- **Per-line filtering:** a small `line_offenders()` helper calls `offenders(..., allow=[])` and drops a hit only when its line contains one of those literals. Whole files are not allow-listed, because files like `RemoteSessionCoordinator.swift` and `+Bootstrap.swift` have to stay clean apart from those few lines.
- **Sanity check:** without the literals the scan finds 10 hits; with them it finds 0.

### Results
- `python3 tests/test_shellx_entitlements.py`: OK
- `python3 tests/test_shellx_guard.py`: OK
- `python3 tests/test_shellx_identity.py`: OK
- `python3 tests/test_shellx_perf_harness.py`: OK
- `python3 tests/test_shellx_remote_daemon.py`: OK (8 tests; also OK when run from `/tmp`)
- `python3 scripts/verify-local.py --all --jobs 3`: PASSED, 15/15 checks
