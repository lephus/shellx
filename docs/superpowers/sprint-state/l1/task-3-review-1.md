### Spec Compliance
Issues found. Review Focus 1 says hooks installed by one app must not overwrite the other's. That is still violated for several agent integrations. The code keeps cmux's plugin file names, ownership markers and group key, so ShellX overwrites cmux's files on install and deletes them on uninstall (I1). For the Computer Use skill, ShellX deletes or re-points cmux's skill link when a ShellX Claude or Codex session starts (I2). Every other "Files (fork)" bullet in the brief is done, and the Swift code that writes and reads each renamed name agrees (details below).

Brief bullets, one by one (checked against the code at head 12bfe7a800):
- Socket names come from `ShellXBrand.socketBaseName`, and `/tmp/shellx-last-cli-path` is used. Done. The CLI resolver now reuses the CmuxSettings constants (CLI/CLISocketPathResolver.swift:134-141), so the app and the CLI cannot drift apart.
- `CmuxStateDirectory` is `~/.local/state/shellx`, and Application Support is `ShellX` everywhere. Done. The guard patterns `Application Support/cmux` and `appendingPathComponent("cmux")` find nothing.
- Config paths are `~/.config/shellx/shellx.json`, per-project `.shellx/shellx.json` / `shellx.json`, `dock.json` and `sidebars/`. Done in every reader: CmuxConfig, NotificationHookCache, VaultAgentRegistry, AgentExternalLauncherRegistry, DockSplitStore, CLI ConfigValidation/DocsSettings, CmuxConfigLocation and KeyboardShortcutSettingsFileStore.
- pbxproj: `PRODUCT_NAME = shellx` in both cmux-cli configurations, the "Copy CLI" phase copies `shellx` and the 6 `shellx-*-wrapper` files, and `CMUX_SIDEBAR_EXTENSION_POINT_ID = pro.shellx.desktop.sidebar` (x2). Done.
- UTIs: the 5 exported types are `pro.shellx.*`. Every pasteboard type in Sources and Packages matches them (DragOverlayRoutingPolicy, GhosttyTerminalView, RightSidebarModeDragPayload, CmuxWebView, SidebarWorkspaceDragSession, NSPasteboard+CloudSidebar). Done.
- CLI installer writes `/usr/local/bin/shellx`. HostSettingsActions, TerminalController+SocketCleanup and the bootstrap builder use `~/.shellx/{relay,bin}` and `bin/shellx` (R7). Done.
- Every lookup of the bundled CLI was renamed: AppDelegate (sudo runner, CLI test paths), CLIForwardingLaunchRouter, AgentHookDeliveryProcess, AgentSessionOwnedProcessLauncher, DiffSidecarBridge, MachinesPanelView, CloudVMActionLauncher, TerminalSurface+RuntimeSurfaceCreation, SudoVerifiedHelper (`Resources/bin/shellx`), DiffViewerPickerCommandRunner, cmux_open and `system.identify` cli path. `git grep` finds no reader left that looks for `bin/cmux`, `cmux-*-wrapper`, `~/.cmuxterm` or `Application Support/cmux` in Sources, CLI, Packages/*/Sources or Resources. One fish fallback is the exception (M1).
- shell-integration (zsh, bash, fish, nushell), the wrappers renamed to `shellx-*-wrapper`, and the sdef suite "ShellX Suite". Done.
- Hook catalog uses `shellx hooks <agent>`, the pinned markers are `shellx-*-hook-v*`, codex scripts are `~/.shellx/hooks/shellx-codex-hook-*.sh`, the Claude marker is `"__shellx"`, and the legacy-command adoption now matches only `shellx`. Kimi, Rovo Dev and Hermes block markers are ShellX's own. Done. The plugin files listed in the same catalog are not done (I1).
- Keychain services: socket-control (CLI and CmuxSettings), surface-resume-approvals, iroh `*.v1`, and the phone-push services are all `pro.shellx.desktop.*`. Done. The legacy-migration path in `SocketControlPasswordStore` now reads and deletes only ShellX's own item, never cmux's.
- Tests: `tests/test_shellx_coexistence.py` (16 tests) is registered in test-execution.toml. `cmuxTests/ShellXPathsTests.swift` is wired in pbxproj and the struct name equals the file basename. Every API it calls exists (`CmuxConfigStore.defaultGlobalConfigPath` is `nonisolated static`, `CmuxSettingsFileStore.defaultPrimaryPath`, `CmuxCLIPathInstaller().destinationPath`, `SessionSnapshotFileLocation.cmuxDirectoryURL`).
- Review Focus 5 (ruling R6): done for the Flutter app. One deviation for another native ShellX copy (M4).

Cannot verify from the diff (needs CI or a manual run):
- App and cmuxTests/cmuxCLITests compile on CI (`[unit]`).
- Brief Step 5, side-by-side with cmux.
- Whether LaunchServices launches a second bundle with the same id at all while the Flutter app runs (it may simply activate the Flutter app).
- Codex config `hooks = true` shared-key behaviour on uninstall.
- `go test` for claude_hook.go.

Checks I ran:
- `python3 tests/test_shellx_*.py`: all 6 files OK. The coexistence suite has 16 tests.
- Mutation-style check of each guard pattern with `git grep` against base 89129d34fa and head. Every FORBIDDEN pattern and every bundled-CLI pattern matches at base, and the only matches at head are LINE_ALLOW lines (cloud VM, cmux iOS app, in-process labels). So none of the guards is vacuous.
- `swift test` of CmuxWindowing in a scratchpad copy, deleted afterwards: 40/40 pass.
- Upstream tests: test_pi_wrapper, test_amp_wrapper_hooks, test_hermes_wrapper_hooks, test_macos_info_plist and test_issue_2448 pass. test_codex_wrapper_hook_append needs a built CLI.
- `localization_catalog.py check`: 0 parity errors. All 5 `singleInstance.olderShellX.*` keys have the 9 locales.
- The worktree is still clean.

### Strengths
- The WIP audit holds up. The identity and remote-daemon guards are back to base, apart from removing the 3 Task-3 allowlist entries, which is correct. The coexistence guard's `.cmuxterm` and iroh patterns forbid the old names again. No `com.shellx` (wrong namespace) remains anywhere in the code.
- The second implementer found real bugs that would only have surfaced at runtime:
  - The bundled CLI lookup returned nil in AgentSessionOwnedProcessLauncher.
  - The app typed ` cmux restore` and ` cmux welcome` into ShellX terminals.
  - The restore-lease owner check was wrong.
  - Kimi, Rovo Dev and Hermes block markers would have deleted cmux's blocks.
  - BundledCLITestSupport contradicted itself.
- The guards forbid old names instead of asserting new ones, and every allowlist entry has a reason. `test_app_runs_and_types_the_shellx_cli` guards exactly the class of bug found above.
- Single-instance decisions are pure and tested in CmuxWindowing. The Flutter app is classified by its bundle contents (FlutterMacOS.framework, or no `bin/shellx`). It is asked about even with the replace override, never force-terminated, and left running when it launches later. Cancel and a refused quit end with an explanation instead of a silent exit.
- Compile-level read of the new Swift (I cannot build):
  - Only two files gained `import ShellXBrand`: CmuxCLIPathInstaller and AgentSessionOwnedProcessLauncher. Both are only in the app target's Sources phase (A5001051), which links ShellXBrand.
  - CmuxSettings declares the ShellXBrand dependency in Package.swift.
  - Files that mention `ShellXBrand.` without importing it mention it only in comments.
  - The new `Action` case is handled in the only switch (AppDelegate).
  - `StartupBreadcrumbLog.append(_:fields:)` has a default for `fields`, `NSApp.activate()` needs macOS 14 (the deployment target), and AppDelegate is `@MainActor`.
- The app ignores an inherited `CMUX_SOCKET_PATH` when `CMUX_BUNDLE_ID` names another app. So a ShellX launched from a cmux terminal does not bind cmux's socket.

### Issues

#### Critical (Must Fix)
None found. The app build cannot be judged until CI runs.

#### Important (Should Fix)

**I1. Agent plugin, extension and group files are shared with cmux. ShellX overwrites cmux's on install, deletes them on uninstall, and rewrites them automatically (Review Focus 1).**

Where:
- CLI/CMUXCLI+AgentHookCatalog.swift:50,58,65,74,83: opencode `plugins/cmux-session.js`, pi `extensions/cmux-session.ts`, omp `extensions/cmux-omp-session.ts`, campfire `extensions/cmux-campfire-session.ts`, amp `plugins/cmux-session.ts`.
- The matching filename and marker constants:
  - CLI/cmux.swift:36479-36480: `cmux-opencode-session-plugin-marker`, `cmux-session.js`.
  - CLI/cmux.swift:43905-43907: `cmux-feed-plugin-marker`, `cmux-feed.js`.
  - CLI/cmux.swift:28820,28831,36917: OpenCode TUI dir `cmux`, `.cmux-owned`, ownership marker.
  - CLI/CMUXCLI+PiExtension.swift:5-6, CMUXCLI+AmpExtension.swift:4-5, CMUXCLI+OmpExtension.swift:4-5, CMUXCLI+CampfireExtension.swift:4-5.
- Antigravity: CLI/cmux.swift:37262 and 37306 set `existing["cmux"] = <ShellX group>` with no condition.

What happens:
- `installOpenCodePluginHooks` (cmux.swift:37170-37195) treats any file that contains the cmux marker as its own. It writes ShellX's plugin, which spawns `shellx`, over cmux's plugin, which spawns `cmux`.
- `uninstallOpenCodePluginHooks` (37226-37240) deletes cmux's plugin file. `removeOpenCodeTUIPlugin` removes cmux's TUI package.
- Pi does this without any user action. `shellx hooks pi session-start` calls `refreshManagedPiExtensionIfNeeded` (cmux.swift:45446, PiExtension.swift:78-110). That rewrites any marker-matching `cmux-session.ts` to ShellX's source, and cmux does the same in reverse, so the two apps keep overwriting each other.
- Antigravity install replaces cmux's `cmux` hook group.
- This contradicts Review Focus 1 directly, and the catalog is a brief file.

Fix scope:
- Give every ShellX-written file, directory and key its own name and marker:
  - `shellx-session.js`, `shellx-feed.js`, `shellx-session.ts`, `shellx-omp-session.ts`, `shellx-campfire-session.ts`.
  - OpenCode TUI dir `shellx` with `.shellx-owned` and `shellx-opencode-*-marker`.
  - `shellx-{pi,amp,omp,campfire}-session-extension-marker` and `.shellx-session.lock`.
  - Antigravity group key `shellx`.
- Update the catalog `configFile` entries and the registration matching in `updateOpenCodePluginRegistration` (cmux.swift:37020-37022, 37133-37136).
- Make sure no code path adopts a file that carries a `cmux-*` marker.
- Update the python and Swift tests that encode these names.
- Extend the coexistence guard to forbid `cmux-session\.(js|ts)`, `cmux-(omp|campfire)-session\.ts`, `cmux-feed\.js`, `cmux-[a-z]+-(session-(plugin|extension)|feed-plugin|tui-plugin[a-z-]*)-marker`, `antigravityHookGroupName = "cmux"` and `openCodeTUIPluginDirectoryName = "cmux"`.

Lower priority (Minor, no overwrite): Kiro `~/.kiro/agents/cmux.json` and Grok `.grok/hooks/cmux-session.json` already merge entries by marker, so both apps' entries coexist. Renaming them would still be cleaner, and the Kiro agent gets `name: "cmux"` (cmux.swift:37633).

**I2. `skills/cmux-cua/link-policy.sh` treats cmux's skill link as ShellX-managed, so ShellX deletes or re-points it on every Claude or Codex launch.**

Where:
- link-policy.sh:127-143 counts a link as "managed" only for `cmux*.app` paths, `/tmp/cmux-*` / `DerivedData/cmux-*` builds and `com.cmuxterm.*` bundle ids.
- shellx-claude-wrapper:2401-2403 and shellx-codex-wrapper:239 call `cmux_cua_skill_reconcile` on every launch where Computer Use is enabled (the default).

What happens:
- With cmux's opt-in skill link at `~/.claude/skills/cmux-cua` (or `~/.agents/skills/cmux-cua`), every ShellX session deletes it. The legacy `cmux-computer-use` / `codex-cua` links are deleted the same way. With the ShellX opt-in set, ShellX re-points the link to ShellX.app instead.
- ShellX never recognizes its own links (`ShellX*.app`, `pro.shellx.*`), so it can neither upgrade nor retire them.

Fix: in ShellX's copy of the policy, treat as managed only ShellX bundles: `/Applications/ShellX*.app`, `~/Applications/ShellX*.app`, the DerivedData / `/tmp/shellx-*` build roots, and bundle ids matching `pro.shellx.desktop*`. Then cmux's link reads as "user" and is never touched. Ideally also install under a ShellX link name. Add a python test, or extend test_claude_wrapper_computer_use_skill.py, with a cmux-owned link that must survive a ShellX launch. The scope is `skills/cmux-cua/link-policy.sh` plus that test.

#### Minor (Nice to Have)
- **M1. A fish fallback can still run cmux's CLI.** Resources/shell-integration/fish/config.fish:203 has `set cli (command -s cmux)` in the welcome-banner fallback. When the bundled CLI is not executable it runs cmux's `welcome`. Change it to `command -s shellx` and add `command -s cmux` to the guard's bare-CLI patterns (`command -v cmux\b` does not match fish).
- **M2. `system.identify` and the CLI still call the product "cmux".** `system.identify` returns `app: "cmux"` (Sources/TerminalController.swift:3803) and `CLIVersionSkew.cliProduct = "cmux"`. Since the `CMUX_*` env names are kept, `shellx` run in a cmux terminal (and `cmux` run in a ShellX terminal) follows `CMUX_SOCKET_PATH` to the other app, and nothing can tell the products apart. Setting both to `"shellx"` is cheap and lets the version-skew path name the mismatch.
- **M3. Plan-level note for the controller, not this task.** Both apps' persistent hook entries coexist (good), but each entry follows the shared `CMUX_BUNDLED_CLI_PATH`/`CMUX_SOCKET_PATH`. With both installed, every hook event reaches the host app twice. Consider a ruling: hook commands check `CMUX_BUNDLE_ID`, as the app already does for socket overrides.
- **M4. A second native ShellX copy still exits silently.** Ruling R6 asks for the modal for "another ShellX instance" too. The code keeps upstream behaviour for a native copy of a different bundle: the newcomer yields with `_exit(0)` and activates the running app (AppDelegate enforceSingleInstance `.yieldToExisting`), and the running instance's observer force-terminates it (`.terminateDuplicate`). That is acceptable UX but deviates from R6 wording, so the controller should confirm. Also, `.unknown` (nil `bundleURL`) maps to `.terminateDuplicate`, which calls `forceTerminate`. Mapping `.unknown` to leave-alone would make "never force-kill the Flutter app" unconditional.
- **M5. UI copy and string defaults are left for Task 6 (ruling R8).** Many `defaultValue:` strings were edited for existing keys while their catalog entries kept the old text (e.g. CmuxSettingChangeError, automation.error.engineUnavailable, settings.section.settingsJSON). The UI shows the catalog value, so these edits have no effect until Task 6. Some new text is mixed: "Run the cmux CLI inside that app's bundle (Contents/Resources/bin/shellx)" (CLIVersionSkew.swift:149) and "the same directory as `cmux.json`" in comments. CmuxConfigSchema.generated.swift was edited by hand, so a regeneration would revert it.
- **M6. Legacy codex feature block.** CmuxCodexConfigEditor still removes the legacy `# cmux hooks codex feature` block written by very old cmux builds (report concern 3). Leave it or drop the legacy matching. Separately, both apps rely on the same `[features] hooks = true` key, so uninstalling one can turn the feature off for the other. It is an edge case; record it.
- **M7. Stale fixtures and leftovers outside this task.**
  - Fixtures in upstream cmuxTests that this branch did not touch still use cmux names (report concern 5). No lane runs them, but `[unit]` compiles them; they hold strings only, and I found no renamed symbol.
  - scripts/cmux-debug-cli.sh:75 has a dead `Application Support/cmux/tag-app-cache` path.
  - scripts/ci/run-app-host-xcodebuild.sh:569 has a bundle-id leftover from Task 2.

### Assessment
**Task quality:** Needs fixes.
**Reasoning:** Sockets, paths, the CLI name, UTIs, keychain items and the Flutter prompt are done, consistent and guarded by guards that would catch a regression. Review Focus 1 still fails in two places: ShellX overwrites, deletes and keeps rewriting cmux's OpenCode, Pi, Amp, OMP, Campfire and Antigravity integration files (I1), and it deletes cmux's Computer Use skill link on every ShellX Claude or Codex launch (I2).
