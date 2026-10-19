# Task 2 report — App identity (bundle ids, name, team, scheme, update feed)

Branch `shellx/l1-identity` (worktree `~/Documents/myProjects/shellx-wt-l1`), base `c3afe0da80`.
No local Xcode build (ruling R2); CI verifies the build after the controller pushes.

## Commits

| SHA | Subject |
| --- | --- |
| 4429a6b625 | feat(shellx): shared guard helper and the app identity guard (red) |
| 387adce482 | feat(shellx): ShellX bundle ids, product names, URL scheme and update feed; drop the tunnel extension from the app |
| 364d4dedcb | feat(shellx): updater never starts Sparkle without an EdDSA key; ShellX dev ids and fallback feed |
| 67c5432942 | feat(shellx): stop building the cmux Computer Use helper; pin its trust to the ShellX team |
| cc357b0eca | feat(shellx): Swift and scripts use ShellX bundle ids, team, URL schemes and notification names |
| 6ca675ee31 | test(shellx): identity fixtures follow the ShellX bundle ids, team and schemes; guard Swift literals |

## What was implemented

1. **Guard helper** `tests/shellx_guard.py`: `read(path)`, `offenders(pattern, roots, allow)` (walks text files, skips
   binary files and `.git`/`.build`/`build`/`DerivedData`/`node_modules`; allow entries are `(path, reason)`, a path
   ending in `/` allows a directory, an empty reason raises), `png_size(path)`, `sha256(path)`. Paths are repo-relative
   and resolve against the repo root, so the cwd does not matter. Own tests: `tests/test_shellx_guard.py` (6 tests).
2. **Identity guard** `tests/test_shellx_identity.py` (stdlib unittest, ruling R1; the plan's 3 pytest snippets
   translated 1:1, `ALLOWLIST = []`) plus 11 more tests (product names/module names/scheme/Sparkle key per
   configuration, test hosts, every project bundle id under `pro.shellx.desktop`, no tunnel embed/dependency,
   URL types use the build setting, reload.sh names/ids, Swift has no `com.cmuxterm.app` bundle-id literal outside a
   reasoned line allowlist, team ids come from ShellX, distributed notification names, auth/SSH URL schemes,
   Computer Use helper not built). Both registered in `tests/test-execution.toml`, lane `linux-guard` (next to
   `test_shellx_entitlements.py`).
3. **Xcode project** (`cmux.xcodeproj/project.pbxproj`) — exact settings changed, per target/configuration:
   - `cmux` app target `A5001050`
     - Debug `A5001082`: `PRODUCT_BUNDLE_IDENTIFIER` `com.cmuxterm.app.debug` → `pro.shellx.desktop.debug`;
       `PRODUCT_NAME` `"cmux DEV"` → `"ShellX DEV"`; **added** `PRODUCT_MODULE_NAME = cmux_DEV` (keeps the Swift
       module name every `cmuxTests` file imports with `@testable import cmux_DEV`); `CMUX_AUTH_CALLBACK_SCHEME`
       `"cmux-dev"` → `"shellx-dev"`; `SPARKLE_PUBLIC_KEY` → `""`.
     - Release `A5001083`: `PRODUCT_BUNDLE_IDENTIFIER` `com.cmuxterm.app` → `pro.shellx.desktop`; `PRODUCT_NAME`
       `cmux` → `ShellX`; **added** `PRODUCT_MODULE_NAME = cmux`; `CMUX_AUTH_CALLBACK_SCHEME` `cmux` → `shellx`;
       `SPARKLE_PUBLIC_KEY` → `""`.
     - buildPhases: removed `7A0CE1000000000000000060 /* Embed System Extensions */`; dependencies: removed
       `7A0CE1000000000000000062 /* PBXTargetDependency */` (cmuxTunnelExtension). Objects deleted: PBXBuildFile
       `7A0CE…0049` (cmuxTunnel.systemextension in Embed System Extensions), PBXCopyFilesBuildPhase `7A0CE…0060`,
       PBXTargetDependency `7A0CE…0062`, PBXContainerItemProxy `7A0CE…0061`. The `cmuxTunnelExtension` target, its
       sources and entitlements stay.
     - Executable name is now `ShellX DEV` / `ShellX` (follows `PRODUCT_NAME`).
   - `CmuxDockTilePlugin` Debug `D1320AA0D1320AA0D1320AB2`: `com.cmuxterm.app.docktileplugin.debug` →
     `pro.shellx.desktop.docktileplugin.debug`; Release `…AB3`: `com.cmuxterm.app.docktileplugin` →
     `pro.shellx.desktop.docktileplugin`. Product name kept `CmuxDockTilePlugin` (Info.plist `NSDockTilePlugIn`
     names `CmuxDockTilePlugin.plugin`; internal name, not user-visible).
   - `cmuxTunnelExtension` (not embedded any more) Debug `7A0CE…0063` / Release `7A0CE…0064`: `CMUX_TEAM_ID_PREFIX`
     `"7WLXT3NR37."` → `"W4RF3W4VTZ."`; bundle ids → `pro.shellx.desktop.debug.tunnel` / `pro.shellx.desktop.tunnel`.
   - `cmuxTests` Debug `F1000011…`: `pro.shellx.desktop.apptests`, `TEST_HOST =
     "$(BUILT_PRODUCTS_DIR)/ShellX DEV.app/Contents/MacOS/ShellX DEV"`; Release `F1000012…`: same id,
     `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/ShellX.app/Contents/MacOS/ShellX"`.
   - `cmuxUITests` `C117776A…` / `442A6A86…`: `com.cmuxterm.appuitests` → `pro.shellx.desktop.appuitests`.
   - `cmuxCLITests` `C1175700…0A` / `…0B`: `com.cmuxterm.clitests` → `pro.shellx.desktop.clitests`.
   - Not changed here: `CMUX_SIDEBAR_EXTENSION_POINT_ID` and `cmux-cli` `PRODUCT_NAME` (Task 3), `DEVELOPMENT_TEAM ""`,
     the product file reference path `cmux.app` and the schemes' `BuildableName="cmux.app"` (cosmetic; Xcode resolves by
     blueprint id and rewrites them on save).
4. **Info.plist**: `SUFeedURL` = `https://download.shellx.pro/desktop/appcast.xml` (`ShellXBrand.updateFeedURL`),
   `SUEnableAutomaticChecks` = `false`. `CFBundleURLTypes` already registers `$(CMUX_AUTH_CALLBACK_SCHEME)` (now
   `shellx`/`shellx-dev`); no literal `cmux` scheme.
5. **Empty Sparkle key cannot hurt startup**: Sparkle 2 (checked in its sources, `SUPublicKeys.m` / `SPUUpdater.m`)
   decodes `""` to a 0-byte key, marks it invalid and fails `start()` with "The EdDSA public key is not valid". cmux
   catches that and would show an update error on every launch (no crash). `UpdateController` now reads
   `SUPublicEDKey` (`hasUpdateSigningKey(infoValue:)`): without a non-empty key it never starts Sparkle, keeps
   `SUEnableAutomaticChecks` off and answers a manual check with "No Updates Available" (same path as DEV builds).
   Also: dev-like ids are `pro.shellx.desktop.debug|staging[.<tag>]`, and the fallback feed is ShellX's.
6. **reload.sh**: `APP_NAME="ShellX DEV"`, `BUNDLE_ID="pro.shellx.desktop.debug"`, `BASE_APP_NAME="ShellX DEV"`,
   tagged `ShellX DEV <tag>` / `pro.shellx.desktop.debug.<tag>`, Release product `ShellX`, all socket-marker bundle-id
   cases → `pro.shellx.desktop.*` (kept in lockstep with `SocketPathMarkerFiles`), tagged auth scheme
   `shellx-dev-<tag>`. `--bundle-id` now refuses `pro.shellx.desktop` and its non-debug children **and every
   `com.cmuxterm.app*` id** (a tagged build must never quit a user's ShellX or cmux). Helpers it uses kept consistent:
   `scripts/cmux-debug-cli.sh`, `scripts/lib/mobile-attach.sh` (sourced by reload.sh), `CLI/cmux_open.swift`
   (tagged dev app path), `MenuBarBuildHintFormatter` (`ShellX DEV <tag>` parsing).
7. **Team id**: every pin is ShellX's. App/CLI use `ShellXBrand.teamID` (`CLI/cmux.swift` arm-server + tagged
   requirements and team check, coderouter requirements, `CMUXCLI+Sudo.swift`, `Sources/Cloud/CodeRouterSocketPeerVerifier.swift`);
   packages without ShellXBrand use the literal `W4RF3W4VTZ` (`ComputerUseHelperTrust`,
   `CodeRouterDebugServerIdentityPolicy`). No `7WLXT3NR37` left under Sources, CLI, Packages, Resources, scripts
   (allowlist empty; test fixtures that used it as an arbitrary team now use `W4RF3W4VTZ`).
8. **Computer Use helper excluded**: `scripts/build-app-bundled-resources.sh` no longer builds `cmux Computer Use.app`
   (`CMUX_CUA_HELPER_BUILD` defaults to `0`; `=1` restores the upstream build, used by
   `tests/test_build_app_bundled_resources.sh`), removes a helper an earlier build left, and the skip-stamp includes
   the mode. `reload.sh` drops the helper instead of building it. Pin changed to `W4RF3W4VTZ`, so an installed cmux's
   helper is never trusted. Result: Computer Use is unavailable in ShellX (the existing "no trusted helper" path).
   This also removes the build-time clone of `github.com/manaflow-ai/cmux-cua`.
9. **Swift bundle-id literals (ruling R3)** → ShellX (`ShellXBrand.bundleID`-derived in app/CLI, literal
   `pro.shellx.desktop[.channel]` in packages): `SocketPathMarkerFiles` (stable/nightly/rc/staging/debug ids — the
   root most derivations read), `SocketControlSettings`, `BuildFlavor+ReleaseChannel`, `SessionSnapshotFileLocation`,
   `BrowserHistoryLocation`, `CmuxGhosttyConfigPathResolver.releaseBundleIdentifier`, `DebugEventLog`,
   `MobileHostIdentity`, `VMTunnelManager`, `CloudTelemetryUploader`, `SudoBrokerPaths`, `AuthEnvironment`,
   `KeychainStackTokenStore` fallback (`<bundle>.auth`), CLI theme socket→bundle mapping, restore-session channel
   check, browser-settings defaults domain, docs settings path, app fallbacks (`AgentHookDeliveryProcess`,
   `AgentJournalLifecycleCenter`, `AgentMessageCenter`, `NotificationFeedHistoryStore`, `ClosedItemHistory`,
   `CmuxAgentChatConfig`, `GhosttyCrashBreadcrumb`, `HiveComputersService`, `KeyboardShortcutSettingsFileStore`,
   socket client capability audience, workspace-create idempotency store), `AppBundleIconPersistencePolicy`
   (`ShellX.app`), `AboutLicenseContent`, `StartupBreadcrumbLog`, `FilePreviewPanel` (also hides other ShellX builds).
   Distributed notifications (OS-wide): `pro.shellx.desktop.themes.reload-config` (CLI → app) and
   `pro.shellx.desktop.appIconDidChange` (app → dock tile plugin; the plugin target does not link ShellXBrand, so both
   ends spell the literal).
10. **URL scheme family** `shellx`, `shellx-nightly`, `shellx-rc`, `shellx-dev`, `shellx-dev-<tag>`:
    `AuthEnvironment.callbackScheme` (feeds `CmuxSSHURLRequest.activeSupportedSchemes`, workspace links, browser
    callback policy), `AuthCallbackRouter.builtInSchemes` (cmux's schemes are no longer accepted),
    `CmuxSSHURLRequest.supportedSchemes`; the embedded-browser "callback-shaped" blocker covers both families.
11. **Signing scripts**: `scripts/sign-cmux-bundle.sh` reads the main executable from `CFBundleExecutable` (was
    hard-coded `MacOS/cmux`); `scripts/shellx/sign-and-notarize.sh` drops the bundle-id/name overrides and the
    `cmux.app` → `ShellX.app` rename (the target produces `ShellX.app` now).

## Tests and results

- `python3 tests/test_shellx_identity.py` → 14 tests OK. `python3 tests/test_shellx_guard.py` → 6 OK.
  `python3 tests/test_shellx_entitlements.py` → OK.
- `python3 scripts/verify-local.py --all --jobs 3` → `PASSED: 15/15 selected checks ran.`
- `swift test --package-path …` (final run after the last commit): ShellXBrand 4, CmuxSettings 488, CmuxUpdater 102,
  CmuxControlSocket 617, CmuxComputerUse 37, CmuxBrowser 736, CmuxWorkspaces 319, CmuxAuthRuntime 305, CmuxSudoBroker 97,
  CmuxPhonePush 11, CMUXMobileCore 521, CmuxIrxTransport 240, CMUXDebugLog 0 — all passed. CmuxFoundation 723 tests with
  pre-existing failures only (schema file, plus a `ProcessSnapshotServiceTests` timing flake that passes on rerun).
- Shell/node tests: `tests/test_build_app_bundled_resources.sh`, `tests/test_reload_build_only_keeps_tagged_app.sh`,
  `tests/test_reload_release_configuration.sh`, `tests/test_reload_shared_derived_data.sh`,
  `tests/test_cmux_debug_cli_helper.sh`, `tests/test_start_cmux_profiling.sh`, `tests/test_sign_cmux_bundle_tunnel_gate.sh`
  pass; `python3 tests/test_codex_wrapper_computer_use_mcp.py`, `python3 tests/test_open_wrapper.py` pass;
  `node --test scripts/lib/mobile-attach.test.mjs` 48/49 (the 1 failure reads the removed
  `.github/workflows/reload-build.yml`; it fails the same on the base commit).
- Could not run locally: CmuxCloud and CmuxTerminalCore package tests (need `GhosttyKit.xcframework`), app-hosted
  `cmuxTests` / `cmuxUITests` / `cmuxCLITests` (need an Xcode build, R2/R5), `tests/test_cli_socket_autodiscovery.py`
  (needs a built `cmux-cli`). Their fixtures were updated by reading the code paths (see below).
- CmuxBrowser/CmuxWorkspaces need `vendor/bonsplit` (submodule not checked out): I temporarily copied the same commit
  (`d67d1b11`) from `~/Documents/myProjects/shellx-pro/vendor/bonsplit` into the worktree's empty submodule dir to run
  them, and emptied the dir again afterwards (no git change; nothing outside the worktree touched).
- Pre-existing, unrelated failures seen: CmuxFoundation (`web/data/cmux.schema.json` left with BUSL `web/`; a timing flake in
  `ProcessSnapshotServiceTests`, green on rerun),
  CmuxIrohTransport 1 network-timeout test (`CmxIrohPrivatePathTransportGateTests`).

### TDD evidence (RED → GREEN)

- Identity guard, before any change (`python3 tests/test_shellx_identity.py`): `FAILED (failures=8)` — missing
  `PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop;`, `7A0CE1000000000000000062` still in the app target, missing
  `PRODUCT_NAME = "ShellX DEV";`, `com.cmuxterm.clitests`, team-id offenders, missing `APP_NAME="ShellX DEV"`, missing
  ShellX TEST_HOST, `SUFeedURL` = manaflow appcast. After pbxproj/Info.plist/reload.sh: 1 failure (team id) → after the
  Swift commit: `Ran 14 tests … OK`.
- Updater: `swift test --filter UpdateSigningKeyGatingTests` → compile errors `type 'UpdateController' has no member
  'hasUpdateSigningKey'` → after the change the whole package passes (102 tests).
- Computer Use trust: new `onlyTheShellXTeamIsTrusted` run against the old pin → `✘ … teamIdentifier → "7WLXT3NR37") ==
  "W4RF3W4VTZ"` (3 issues) → GREEN after the pin change (37 tests).
- Auth router: new `AuthCallbackRouterSchemeTests` against the old cmux scheme set → `acceptsTheShellXSchemes` and
  `rejectsTheCmuxSchemes` fail → GREEN with the shellx set.
- Helper build: the new ShellX case in `tests/test_build_app_bundled_resources.sh` with the removal step disabled →
  `FAIL: the ShellX build kept the cmux Computer Use helper` → passes with it.
- Swift-literal guard: mutation check (put `com.cmuxterm.app` back into `SocketPathMarkerFiles.stableBundleIdentifier`)
  → the guard fails on that line; restored.
- `tests/shellx_guard.py` tests were written together with the helper (not test-first).

## Self-review

- Completeness vs brief: bundle ids, product names, team prefix, scheme, Sparkle key, tunnel embed/deps, excluded
  helper, Info.plist feed + auto-checks, reload.sh lines 11-12, every listed team pin, `com.cmuxterm.app` own-id
  literals, `tests/shellx_guard.py`, `tests/test_shellx_identity.py`, toml registration — done. Brief step 4's
  `reload.sh --tag w1 --build-only` is replaced by the static reload.sh checks (R2).
- `PRODUCT_MODULE_NAME` pinned to the old module names so ~1000 `@testable import cmux_DEV|cmux` stay valid
  ("internal identifiers not renamed").
- YAGNI: no new ShellXBrand dependencies added to packages (literals + comments instead; the Swift guard keeps them
  consistent); no shared constant module invented.

## Concerns

1. Build verified only by CI (R2). Highest-risk spots: `PRODUCT_NAME`/`PRODUCT_MODULE_NAME` change (executable is now
   `ShellX DEV`), removed Embed System Extensions phase, `import ShellXBrand` added to 20 app/CLI files.
2. UI tests that drive Sparkle through `CMUX_UI_TEST_FEED_URL` will now see the updater not start (no EdDSA key) —
   expected until Wave 3 sets the key.
3. Dev/CI scripts not used by ShellX still name `cmux DEV` / `com.cmuxterm.app.*` (e.g. `scripts/reloadp.sh`,
   `reloads.sh`, `launch-tagged-automation.sh`, `run-tests-v1/v2.sh`, `scripts/ci/*app-host*`, perf/soak/fuzz scripts,
   `scripts/verify-app-bundle-channel-metadata.sh`). Follow-up if any of them gets used.
4. `scripts/shellx/perf/perf_mac.py` keeps refusing `com.cmuxterm.app` (it protects the user's cmux; correct as is).
5. `AuthEnvironment.callbackScheme` change also renames the scheme in sign-in URLs sent to the (soon unreachable,
   Task 5) cmux web backend — irrelevant once Cloud is off.

## `com.cmuxterm` categories deliberately left (with reason)

| Category | Where | Reason |
| --- | --- | --- |
| os_log subsystems / `Bundle.main.bundleIdentifier ?? "com.cmuxterm.app"` subsystem fallbacks, `com.cmuxterm.cli` subsystems | many files | in-process label (R3) |
| DispatchQueue labels / thread names (`com.cmuxterm.app.sessionPersistence`, `com.cmuxterm.event-log`, …) | many | in-process (R3) |
| In-process NotificationCenter names `com.cmuxterm.app.displayReconfiguration`, `.screenChangeReconcile`; `CodingUserInfoKey` `com.cmuxterm.session-snapshot.trusted`; NSError domain `com.cmuxterm.cli.agent-hook.*` | AppDelegate, SessionSnapshotCodingTrust, CLI | in-process (R3) |
| UNNotification category/action ids `com.cmuxterm.app.userNotification*` | TerminalNotificationStore | scoped to this app by the OS |
| Keychain services `com.cmuxterm.app.socket-control`, `com.cmuxterm.app.surface-resume-approvals`, `com.cmuxterm.iroh.*.v1`, `com.cmuxterm.irx.*`, `com.cmuxterm.deviceRegistry.*`, `com.cmuxterm.cloud.*` | CLI/cmux.swift, CmuxSettings, SessionPersistence, transports | Task 3 owns keychain service names |
| Sidebar extension point `com.cmuxterm.app.cmux.sidebar` (+ `CMUX_SIDEBAR_EXTENSION_POINT_ID`, `write-sidebar-extension-point.sh`) | CmuxExtensionKit, pbxproj | Task 3 |
| On-disk dirs not derived from our bundle id (`Application Support/cmux`, `com.cmuxterm.simulator-tools`, `~/.secrets/cmuxterm-dev.env`) | various | Task 3 paths |
| MDM payload domain `ManagedDevicePolicy.releasePayloadDomain = "com.cmuxterm.app"`, `BrowserURLAllowlistPolicy` doc | CmuxSettings | Task 4 (brief: leave MDM-domain strings) |
| `com.cmuxterm.cua` (helper TCC identity), `com.cmuxterm.coderouter` (peer identifier in requirements) | CmuxComputerUse, build-cmux-cua.sh, CLI/Cloud verifiers | names of cmux-signed binaries, not ours; with the ShellX team pin they never validate |
| `com.cmuxterm.app.tunnel` os_log subsystem | TunnelExtension | extension not shipped |
| iOS packages and `ios/` (`Packages/iOS/*`, `MacBuildChannel`, `com.cmux.app` ids) | iOS | cmux's iOS app; ShellX mobile is Flutter |
| `cmux*.entitlements` at repo root (cmux release/nightly/rc), `Examples/`, `KeyboardPinningLab/`, `coderouter/` | root | not used by ShellX builds (ShellX signs with `shellx.release.entitlements`) |
| Test fixtures that only pass an arbitrary id through (`com.cmuxterm.tests`, `com.cmuxterm.test`, …) | tests | do not assert our identity (R3) |
| Doc comments describing upstream behavior (e.g. `CmuxStateDirectory.swift:10`) | various | Task 3 edits those files; comments only |

## Fix round 1 (review: Critical — dock tile plugin cannot import ShellXBrand)

Base: `89129d34fa` (branch HEAD after the Task 5B / CI merges).

- Finding confirmed: `Sources/App/AppBundleIconPersistencePolicy.swift` is compiled by both the `cmux` app and
  `CmuxDockTilePlugin` (build file `F4350A120000000000000001` in Sources phase `D1320AA0D1320AA0D1320AB0`); the plugin
  links no package products, so `import ShellXBrand` would fail the plugin build (and with it the app).
- Fix: the file no longer imports ShellXBrand; it spells `"pro.shellx.desktop"` and `"ShellX.app"` with a comment.
  New guard `test_dock_tile_shared_policy_spells_the_shellx_identity` reads `ShellXBrand.swift` and asserts both
  literals equal `bundleID` and `"\(appName).app"`.
- New static guard `test_every_target_compiling_shellxbrand_links_it` (+ helper
  `targets_compiling_shellxbrand_without_linking_it`): for every PBXNativeTarget, every file in its Sources phase that
  contains `import ShellXBrand` requires `/* ShellXBrand */` in that target's packageProductDependencies. Sanity check:
  with every ShellXBrand link removed from a copy of the project text it reports 21 (target, file) pairs, so it sees
  the app and CLI files.
- RED (before the fix), `python3 tests/test_shellx_identity.py`:
  `AssertionError: Lists differ: [('CmuxDockTilePlugin', 'Sources/App/AppBundleIconPersistencePolicy.swift')] != []`,
  `Ran 15 tests … FAILED (failures=1)`.
- GREEN: `python3 tests/test_shellx_identity.py` → `Ran 16 tests … OK`; every `python3 tests/test_shellx_*.py`
  (entitlements, guard, identity, perf_harness, remote_daemon) → OK; `python3 scripts/verify-local.py --all --jobs 3`
  → `PASSED: 15/15 selected checks ran.` No SwiftPM `.build` dirs left under Packages.
