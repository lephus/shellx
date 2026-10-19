# Task 3 report — Coexistence (sockets, paths, CLI name, hook markers, UTIs, keychain) — finish & repair

Branch `shellx/l1-t3` (worktree `~/Documents/helper/shellx-wt/l1-t3`), BASE 89129d34fa.
Earlier range (unreviewed, kept): 4aa136c059..a5385bf04b (8 feature commits), 958dbacabb (WIP, 83 files), b9c185a14e (junk removal).
This session: 0859bf6efb..12bfe7a800 (9 commits, 86 files, +356/-330). Nothing pushed.

Status: DONE_WITH_CONCERNS (see "Remaining gaps" and "Needs user / CI").

## Commits created this session

| sha | subject |
| --- | --- |
| 0859bf6efb | fix(shellx): restore guard patterns and the captured github.html the paused WIP sed rewrote |
| 13128e3785 | fix(shellx): app runs, types and recognizes the bundled shellx CLI, never a bare cmux |
| c4a1feeaaf | fix(shellx): Kimi, Rovo Dev and Hermes hook blocks carry ShellX markers |
| 76b7dd2a7b | fix(shellx): Computer Use client lookup and dev scripts follow ShellX paths |
| da6ece2a13 | fix(shellx): older-ShellX prompt offers "Quit it and open ShellX" / "Cancel" |
| 379d68448a | test(shellx): upstream wrapper, shell and CLI tests use the shellx CLI and ShellX paths |
| f7e341a36f | fix(shellx): normalize project.pbxproj after the Copy CLI renames |
| 618e76c61f | test(shellx): guard the bundled-CLI name the app types or runs and the agent hook block markers |
| 12bfe7a800 | test(shellx): package and open-command tests follow the renamed markers, dirs and tagged sockets |

## A. Audit of WIP commit 958dbacabb (83 files)

| File group | Verdict | Notes |
| --- | --- | --- |
| `tests/test_shellx_coexistence.py` | **reverted** (0859bf6efb) | sed turned the `~/.cmuxterm` pattern into `\.shellx` (154 false hits, comment "`~/.shellx` moved to `~/.shellx`") and the iroh keychain pattern `com\.cmuxterm\.iroh\.` into `com\.shellx\.iroh\.` (vacuous) |
| `tests/test_shellx_identity.py` | **reverted** | the `com\.cmuxterm\.app` scan + its R3 allowlist became `com\.shellx\.app` (guard vacuous) |
| `tests/test_shellx_remote_daemon.py` | **reverted** | `\.cmuxterm` → `\.shellx` made `test_no_cmux_runtime_names_in_go_daemon` fail on 62 hits |
| `tests/browser-parity/fixtures/corpus/github.html` | **reverted** byte-for-byte | captured third-party page (cmux README prose) |
| `tests/test_macos_info_plist.py` | kept | UTIs are `pro.shellx.*` in Resources/Info.plist:359-409 |
| `Examples/CustomSidebars/*` (README + 10 js) | kept | `~/.config/shellx/sidebars/` is where the app reads sidebars; the 5 bundled CmuxSettings templates are byte-identical copies (CustomSidebarTemplateCatalogTests); `cmux sidebar …` CLI prose left for L2 copy |
| `daemon/remote/README.md`, `cmd/cmuxd-remote/claude_hook.go` | kept | relay bootstrap writes `bin/shellx-claude-wrapper` (RemoteInteractiveShellBootstrapBuilder.swift:426), so findRealClaude must skip that name. `go test` not runnable here (no Go) |
| `Packages/macOS/CmuxSettings/Tests/**` (6 files) | kept | match code; `swift test` 488/488 |
| `Resources/bin/{agy,grok,muse,open,cmux-sudo,shellx-*-wrapper}` | kept | `$self_dir/shellx` follows the renamed bundled CLI |
| `cmuxCLITests/*` (3) | kept + **fixed** | `BundledCLITestSupport` was self-contradictory (`lastPathComponent == "cmux"` && path contains `bin/shellx`); sibling product is `shellx` |
| `cmuxTests/*` (12) | kept + **fixed** | `BundledCLILinkageTests` same contradiction; `RemoteShellPromptRelayTests` expected `$HOME/.cmux/bin/shellx-codex-wrapper` → `$HOME/.shellx/bin/…`; `CMUXOpenCommandTests` tagged socket must be `shellx-debug-<tag>.sock`; fixture app path cmux.app → ShellX.app |
| `tests/*.py`/`*.sh` wrapper/shim/claude-teams/omo/pi/hermes/issue_* (36) | kept + **fixed** | wrapper and `~/.shellx` renames are right, but fake bundled CLIs were still named `cmux` (wrappers look up `$self_dir/shellx` / `command -v shellx`) → 7 real regressions vs base fixed in 379d68448a |
| `tests/test_ci_change_areas.py`, `test_ci_nightly_push_throttle.py` | kept | path renames correct; tests cannot run here (no `yaml` module / workflows deleted in the fork — same at base) |
| `tests/test_strip_release_bundle.sh`, `test_cmux_debug_cli_helper.sh` | kept (+ fixed the latter) | debug-CLI helper now targets `/tmp/shellx-debug-<tag>.sock` |
| xcodebuild log files | already removed by b9c185a14e | |

Same-mistake scan: no other test/script had its *forbidden* pattern rewritten; the identity allowlist edits in e791cc07ac (removing the Task-3 entries) are correct.

## Earlier commits: bugs found and fixed (not in the WIP)

- `Sources/Panels/AgentSessionOwnedProcessLauncher.swift:8` looked up `bin/cmux` via `Bundle.url(forResource:)` → nil after the rename (agent session supervisor broken). Now `ShellXBrand.cliName`.
- Session restore typed ` cmux restore <kind> <id>` into ShellX terminals (`AgentRestoreLaunch.cliStartupExecutableToken`), fork/resume fallbacks `"cmux"`, and the restore-lease watcher check (`AgentRestoreLeaseOwner` expected executable basename `cmux`) → all `shellx`. Welcome banner (` shellx welcome`), wake hint (`shellx focus-panel`), nushell `which`/welcome lookups, wrapper/hook/Amp fallbacks, Cloud freestyle attach lookup, hook-monitor attribution, app-bundle bin heuristics (accept ShellX*.app).
- `AgentLauncherPrefix.nonLauncherNames` had `"cmux", "shellx-claude-wrapper"` (sed) → adds `"shellx"`.
- Hook blocks in Kimi/Rovo Dev/Hermes configs used cmux's begin/end markers (ShellX install/uninstall would replace/delete cmux's block) → `# shellx hooks <agent>`, `# shellx-kimi-hooks-<id>`; Hermes pinned marker `shellx-hermes-agent-hook-v2`.
- Bundled `skills/cmux-cua/client-policy.sh` looked for the Computer Use helper under `Application Support/cmux` (cmux's install) → `Application Support/ShellX/cmux-cua/helper`.
- Package tests the earlier commits never updated: CMUXAgentLaunch (25 failures: codex hook script names, config paths, Hermes ownership), CmuxFoundation (16: codex feature/trust markers, `~/.shellx/ssh`), CmuxRemoteWorkspace (2), CmuxControlSocket (1). All fixed.
- `cmuxTests/ShellXPathsTests.swift` called `CmuxConfig.defaultGlobalConfigPath()` (no such type) → `CmuxConfigStore.defaultGlobalConfigPath()`; would not have compiled on the `[unit]` lane.
- `scripts/cleanup-dev-builds.sh` read `/tmp/cmux-last-cli-path` and matched `cmux DEV` → reload.sh names; `tests/claude_teams_test_utils.py` → `/tmp/shellx-last-cli-path`.
- `project.pbxproj` was not normalized (verify-local `project`/`test-wiring` red) → normalized.

## B. Brief "Files (fork)" checklist

| Bullet | State | Evidence |
| --- | --- | --- |
| SocketControlSettings socket names from `ShellXBrand.socketBaseName`; `/tmp/shellx-last-cli-path` | done | SocketControlSettings.swift:25,27,358; TerminalController+SocketCleanup.swift:22; scripts/reload.sh:486,502,805 |
| CmuxStateDirectory `~/.local/state/shellx` | done | CmuxStateDirectory.swift:34 (`ShellXBrand.configDirectoryName`), :37 App Support `ShellX` |
| 46 Application Support sites → `ShellX` | done | 26 `"ShellX"`/`appSupportDirectoryName` sites, the rest are bundle-id scoped; guards `Application Support/cmux` and `appendingPathComponent("cmux")` clean |
| KeyboardShortcutSettingsFileStore:20, CmuxConfig:1846 | done | KeyboardShortcutSettingsFileStore.swift:21,26; CmuxConfig.swift:1846 |
| Other config-path refs (`~/.config/shellx/shellx.json`, `.shellx/shellx.json`, `dock.json`, `sidebars/`) | done (functional) / partly (copy) | guard `\.config/cmux` clean; project lookups in CmuxConfig, DockSplitStore, AgentExternalLauncherRegistry, CLI config/docs use `.shellx/shellx.json`. Remaining `cmux.json` text is comments + UI/help copy (L2 Task 6, R8) |
| pbxproj `cmux-cli` PRODUCT_NAME `shellx` | done | project.pbxproj:19453,19473; guard `test_cli_product_is_shellx` |
| Exported UTIs `pro.shellx.*` | done | Info.plist:359,379,389,399,409; pasteboard types in Sources/Packages match |
| Sidebar extension point `pro.shellx.desktop.sidebar` | done | project.pbxproj:19351,19403; CMUXSidebarExtensionPoint.swift:13; scripts/write-sidebar-extension-point.sh |
| CmuxCLIPathInstaller `/usr/local/bin/shellx` | done | CmuxCLIPathInstaller.swift:56 |
| HostSettingsActions:161, TerminalController+SocketCleanup:54 | done | both `Contents/Resources/bin/shellx` |
| RemoteInteractiveShellBootstrapBuilder `~/.shellx/{relay,bin}`, `bin/shellx` (R7) | done | RemoteInteractiveShellBootstrapBuilder.swift:58,274,275,394,400; SessionRemoteWorkspaceSnapshot+Restore.swift:397 |
| `Resources/shell-integration/*` incl. fish `config.fish` | done | zsh/bash/fish (config.fish:201,227,469) in e791cc07ac; nushell completed in 13128e3785 |
| `Resources/bin/cmux-*-wrapper` → `shellx-*-wrapper` | done | 6 wrappers renamed + pbxproj Copy CLI; guard `test_agent_wrappers_are_shellx` |
| `cmux.sdef` suite ShellX | done | Resources/cmux.sdef:5 |
| AgentHookCatalog + codex hook scripts (`__shellx`, `shellx hooks …`) | done | AgentHookCatalog.swift:12 etc.; CodexHookScriptName.swift:32,66; shellx-claude-wrapper:89,96; ClaudeHookSettings `:-shellx`; + agent config block markers (c4a1feeaaf) |
| Keychain services → `pro.shellx.desktop.*` | done | cmux.swift:2994, SocketControlPasswordStore.swift:28, SessionPersistence.swift:1020, iroh stores (`pro.shellx.desktop.iroh.*.v1`), PhonePushCrypto.swift:236, PhonePushSharedStateStorage.swift:36 |
| Tests: `tests/test_shellx_coexistence.py`, `cmuxTests/ShellXPathsTests.swift` | done | guard 16 tests green; ShellXPathsTests wired (pbxproj, suite struct = basename), runs on CI `[unit]` |
| Older-instance guard (R6 / Review Focus 5) | done | pure logic CmuxWindowing `SingleInstanceConflictPolicy` (+ OlderShellXConflictTests, 40/40 pass); AppDelegate `resolveOlderShellXBeforeLaunch` / `promptToQuitOlderShellX`: modal names the old app's path, buttons now "Quit it and open ShellX" / "Cancel"; asks even with the replace override; an older ShellX launched later is left running; never force-terminated; strings `String(localized:defaultValue:)` in the catalog (9 locales), `localization_catalog.py check` green |

## C. Commands run (tail output)

- `python3 tests/test_shellx_*.py` (each): coexistence `Ran 16 tests … OK`; entitlements 2 OK; guard 6 OK; identity 14 OK; perf_harness 7 OK; remote_daemon 8 OK.
- `python3 scripts/verify-local.py --all --jobs 3`: `PASSED: 15/15 selected checks ran.` (was 13/15 at start: `project`, `test-wiring` failed on the unnormalized pbxproj).
- `bash scripts/lint-pbxproj-test-wiring.sh`: `lint-pbxproj-test-wiring: ok (checked 1290 Swift files)`; `./scripts/sync-test-wiring --check`: ok.
- `python3 scripts/localization_catalog.py check`: `10 catalogs, 9 locales: 0 parity errors`.
- `swift test --package-path` (every `.build` removed afterwards):
  ShellXBrand 4 ✔; CmuxWindowing 40 ✔; CmuxSettings 488 ✔; CMUXAgentLaunch 844 ✔ (was 25 failures); CmuxIrohTransport 655 ✔; CmuxPhonePush 11 ✔; CmuxExtensionKit 19 ✔; CmuxSudoBroker 97 ✔; CmuxRemoteWorkspace 199 ✔ (was 2); CmuxGit 215 ✔; CmuxControlSocket 617 ✔ (was 1); CmuxComputerUse 37 ✔; CmuxRemoteDaemon 32 ✔; CMUXDebugLog 9 ✔; CmuxSyncStore 49 ✔;
  CmuxFoundation 723: only `embedded schema is byte-for-byte web/data/cmux.schema.json` fails — pre-existing (web/data absent at 89129d34fa too); one flaky fd-reuse test (`Launch failure closes capture pipes`) passed on re-run (filter run 21/21 ✔).
  Not runnable: CmuxWorkspaces, CmuxRemoteSession (need the `vendor/bonsplit` submodule, not initialized per lane rules).
- Upstream python/sh tests (116 files touching wrappers, shims, shell integration, Resources/bin, reload/debug scripts), run on the branch and on a temporary worktree of 89129d34fa (removed afterwards): final branch **76 pass, 0 regressions vs base**; 40 fail identically at base (no built CLI / `yaml` module / deleted upstream workflows / Python 3.9 / network). 4 pass now that did not at base (amp wrapper, claude wrapper hooks [base timed out], mutual shim loop, coexistence). `test_ci_app_host_socket_evidence.py` flakes under the parallel load and passes alone (`Ran 8 tests … OK`).
- Swift-test-only expectations (`cmuxTests`, `cmuxCLITests`) changed in this branch were read against the code they drive (cannot run locally, R2).

## Remaining gaps / concerns

1. **Agent plugin files still share names with cmux** (coexistence): `~/.config/opencode/plugins/cmux-session.js`, `~/.pi/agent/extensions/cmux-session.ts`, `~/.config/amp/plugins/cmux-session.ts`, `~/.kiro/agents/cmux.json`, Antigravity hook group `cmux`, OpenCode TUI plugin dir `cmux`, and their ownership markers (`cmux-*-session-extension-marker`, `cmux-opencode-*-marker`, CLI/cmux.swift:28820-28831, 36479, 37262, 43905). Installing ShellX's integration overwrites cmux's file and vice versa. Not in the brief's list; needs its own pass (many python tests encode these names).
2. **`skills/cmux-cua/link-policy.sh`** treats `cmux*.app` / `com.cmuxterm.*` bundles as owners of `~/.claude/skills/cmux-cua` and does not recognize `ShellX*.app` / `pro.shellx.*`; the skill link name is shared with cmux. Needs a dedicated fix (Task 2/3 follow-up).
3. ShellX's codex config editor still removes the *legacy* `# cmux hooks codex feature begin` block in `~/.codex/config.toml` (only very old cmux builds wrote it). Current cmux markers are untouched.
4. `system.identify` reports `app: "cmux"` and `CLIVersionSkew.cliProduct = "cmux"`, so a ShellX CLI that reaches cmux's socket (e.g. run inside a cmux terminal, which exports `CMUX_SOCKET_PATH`) cannot tell the products apart. Env names stay per brief; consider `app: "shellx"` in both.
5. Upstream app-host suite `cmuxTests/` (not run by any CI lane) still has ~25 files whose fixtures encode cmux names for logic that is now ShellX-named (e.g. `CMUXCLIErrorOutputRegressionTests` tagged sockets `/tmp/cmux-debug-<slug>.sock`, SSHStartup* fake `cmux` CLIs on PATH, `CLIGenericHookPersistenceTests` adopting legacy cmux hooks that ShellX now deliberately ignores). Only files this branch touched were reconciled.
6. UI/help copy still says `cmux` (CLI usage, `cmux.json` in settings rows, `cmux restore --surface` hints): L2 Task 6 (R8). Contributor skills docs (`skills/cmux-debugging`, `cmux-dev-workflow`) still mention `/tmp/cmux-debug*.log`.
7. `scripts/ci/run-app-host-xcodebuild.sh:569` looks for xcresult stdout named after `com.cmuxterm.app(.debug)` (Task 2 bundle-id leftover; the ShellX `[unit]` lane uses `test-unit.sh`, not this script).
8. Upstream behaviour kept: a running native ShellX still terminates a *different-bundle native* copy that launches after it (`duplicateLaunchAction == .terminateDuplicate`); only the Flutter app is protected. A native ShellX built before Task 3 (bundled `bin/cmux`) is classified as an older ShellX and gets the prompt (asks, never kills).
9. My batch run invoked `tests/test_bundled_ghostty_theme_picker_helper.sh`, which calls xcodebuild for a helper; it failed immediately (missing `vendor/bonsplit`), nothing was built, and its `.ci-bundled-ghostty-helper/` log dir was deleted. It was excluded from the final run.

## D. Needs user / CI

- Brief Step 5 (manual side-by-side with an installed cmux: `cmux identify` vs `shellx identify`, separate sockets in `/tmp`): needs a tagged app build — not done (R2).
- Brief Step 4 cmuxCLITests lane (`xcodebuild test-without-building -only-testing:cmuxCLITests`): CI only.
- `ShellXPathsTests` (app-hosted): runs on CI through `shellx-mac-unit.yml` when a pushed head message contains `[unit]`.
- App compile of the Swift edits (new `import ShellXBrand` in `AgentSessionOwnedProcessLauncher.swift`, app target only): CI `shellx-mac`.
- Review Focus 5 behaviour with the Flutter `/Applications/ShellX.app` running: manual on a Release-id build.
- `go test ./...` in `daemon/remote` (claude_hook.go wrapper name): needs Go on this Mac.

## Fix round 1 (review task-3-review-1.md)

Commits (no attribution lines, per the new user rule):

| sha | subject |
| --- | --- |
| e46716cf66 | fix(shellx): agent plugin and extension files are ShellX's own, never cmux's |
| 936a963ebc | fix(shellx): Computer Use skill links into a cmux bundle are cmux's, never ShellX's |
| 1549a0294a | fix(shellx): fish fallback runs shellx; system.identify names the product shellx |
| 63d77980e4 | fix(shellx): an unidentified duplicate launch is left running, never force-terminated |
| f02042729f | test(shellx): guard agent integration names, the cua link policy and fish CLI lookup |

- **I1 (done):**
  - Renamed files: `plugins/shellx-session.js`, `shellx-feed.js`, `extensions/shellx-session.ts` (Pi), `plugins/shellx-session.ts` (Amp), `shellx-omp-session.ts`, `shellx-campfire-session.ts`. The Pi wrapper uses the same names.
  - OpenCode TUI: package dir `plugins/shellx` with `.shellx-owned`, package name `shellx-opencode-plugin`, registration spec `./plugins/shellx`, stale spec `shellx-session`.
  - Markers: `shellx-{pi,amp,omp,campfire}-session-extension-marker`, `shellx-opencode-{session-plugin,tui-plugin,tui-plugin-server,tui-plugin-ownership}-marker`, `shellx-feed-plugin-marker`. Also `.shellx-session.lock`.
  - Plugin ids are `shellx.session`, `shellx.feed` and `shellx.tui`, and the in-process `Symbol.for` keys are renamed too. Otherwise a cmux plugin loaded first would have suppressed ShellX's in the same OpenCode/Pi process.
  - Antigravity group key is `shellx`. Kiro and Grok are unchanged, as ruled.
  - Every ownership check matches only `shellx-*` markers now, so a `cmux-*` file is never adopted, rewritten or deleted.
  - Tests updated: 13 python files, cmuxTests OpenCodeHookRegressionTests and CLIGenericHookPersistenceTests (Antigravity group), and cmuxCLITests CLIClaudeHookTimeoutRegressionTests.
  - Guard `test_agent_integration_files_are_shellx` forbids the old names and pins the catalog entries.
  - Not changed: OpenCode registration removal still drops a bare `"./plugins"` entry on uninstall (upstream legacy form). It is noted here, but no cmux file is deleted.
- **I2 (done):**
  - `link-policy.sh` treats a link as managed only when it points into a ShellX bundle: `ShellX*.app` under /Applications, /Applications/Utilities or ~/Applications, `DerivedData/cmux-*/Build/Products/*/ShellX*.app`, or `/tmp/shellx-*/…/ShellX*.app`, with a bundle id of `pro.shellx.desktop` or `pro.shellx.desktop.*`.
  - New `test_claude_never_touches_a_cmux_owned_skill_link`: a link into `~/Applications/cmux.app` (`com.cmuxterm.app`) survives a ShellX launch both with and without the opt-in. Against the old policy it fails, so the test is not vacuous.
  - The managed-link fixtures in the Claude and Codex tests are now older ShellX builds.
  - Guard `test_cua_skill_link_policy_manages_only_shellx_bundles`.
  - Not done: the link name `~/.claude/skills/cmux-cua` is still shared with cmux. ShellX leaves cmux's link alone and reports a collision instead.
- **M1 (done):**
  - `config.fish:203` now uses `command -s shellx`.
  - The guard also forbids `command -s cmux`.
- **M2 (done):**
  - `system.identify` returns `app: "shellx"`, and `CLIVersionSkew.cliProduct` is `"shellx"`.
  - The same-product fixtures in CLIVersionSkewMessageTests and CLIVersionSkewErrorTests are updated. The other-product (`cmux-next`) cases are unchanged.
  - No other producer or consumer of the field was found.
  - Left for L2: the localized other-product hint still says "(Contents/Resources/bin/shellx)" (copy, R8).
- **M4 (done):**
  - `duplicateLaunchAction` maps `.unknown` (nil bundle URL) to `.leaveOlderShellXRunning`. OlderShellXConflictTests has a new case.
  - A verified native copy of a different bundle keeps the upstream terminate.
- **M3, M5, M6, M7:** deferred, as ruled.

Verification:
- `python3 tests/test_shellx_*.py`: all 6 files OK. The coexistence suite now has 18 tests.
- `verify-local --all --jobs 3`: 15/15 PASSED.
- `lint-pbxproj-test-wiring`: ok (1290 files).
- `localization_catalog.py check`: 0 parity errors.
- `verify-local --swift-changed HEAD`: Swift parse OK.
- `swift test` CmuxWindowing: 41/41 pass. The `.build` directory was removed.
- Python tests that pass:
  - test_claude_wrapper_computer_use_skill, including the new test
  - test_codex_wrapper_computer_use_mcp
  - test_pi_wrapper
  - test_opencode_server_entry
  - test_agy_wrapper_hooks
  - test_shell_welcome_banner_startup
- Python tests that need a built CLI and cannot run here (same at base): test_{pi,amp,omp,campfire}_extension_install, test_opencode_plugin_install, test_pi_extension_dispatch, test_omp_subagent_lifecycle.
- test_opencode_v2_tui_bridge needs `bun install`.
- Not compiled locally: the CLI Swift (cmux.swift and the extensions) and cmuxTests/cmuxCLITests. They need the CI build and the `[unit]` lane.

## Fix round 2 (task-3-rereview-1.md)

- a6f3d31842 fix(shellx): OpenCode TUI server plugin id is shellx.server
  - The server-entry rewrite in CLI/cmux.swift:36979 now produces `shellx.server`.
  - Tests updated: tests/test_opencode_v2_tui_bridge.py:34,329, tests/test_opencode_server_entry.py:199 and cmuxTests/OpenCodeHookRegressionTests.swift:183.
  - No other code reads that id: `git grep cmux.server` matches nothing outside the browser-parity fixtures.
  - The coexistence guard forbids `id: "cmux.(server|session|feed|tui)"` in both the plain and the Swift-escaped form. I checked the pattern against both forms with re.search.
- Verification:
  - `tests/test_shellx_*.py`: all 6 files OK.
  - verify-local --all: 15/15 PASSED.
  - lint-pbxproj-test-wiring: ok.
  - localization check: 0 parity errors.
  - test_opencode_server_entry: PASS.
  - Not run: test_opencode_v2_tui_bridge (needs `bun install`) and the Swift suites (need CI).
