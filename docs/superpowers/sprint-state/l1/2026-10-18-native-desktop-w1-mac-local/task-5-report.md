# Task 5 report: Cloud-only features off; device mirroring parked behind `remoteMachines`

Branch `shellx/l1-t5`, worktree `/Users/richard/Documents/helper/shellx-wt/l1-t5`, base 23a01f51aa.
Scope: the brief plus ruling R17 (CLI and socket entry points). No local app build (R2). Commit
messages carry no attribution line (user rule, relayed by the controller).

## Commits

- e365ec6cd5 test(shellx): Cloud-off guard, ShellXCloudOffTests suite and ShellXCloudGate package tests
- 3ba068a26a feat(shellx): switch off cloud, billing and account UI; park device mirroring behind remoteMachines
- b6d41c056c feat(shellx): refuse the hidden vm-pty-connect Cloud helper; guard pre-dispatch Cloud verbs
- 778dc9c1cc test(shellx): upstream tests assert ShellX Cloud-off behaviour

## Design

There are three switches. None of them gates a Manaflow service on `remoteMachines`.

- **`ShellXFeatures.cloud = false`** (new, `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXFeatures.swift:16`).
  - Covers Manaflow Cloud: sign-in and accounts, Cloud machines, VPN, remotes, AI-account upload,
    billing and Pro.
  - It is documented as permanent: it never follows `remoteMachines`.
  - Why a new switch: `CmuxCloud` cannot see `ShellXBrand`, and the CLI target does not link
    `CmuxCloud`. I did not add a `CmuxCloud -> ShellXBrand` package dependency, so the link risk from
    the earlier CI failure does not come back.
- **`CloudMachinesFeature.isAvailable(policy:)` / `isEnabled(defaults:policy:)`** return a literal
  `false` (`CloudMachinesFeature.swift:20,28`).
  - Every app-side accessor (`isAvailable`, `isEnabled`, `offMainIsAvailable`, `offMainIsEnabled`)
    routes through these two.
  - So every upstream Cloud gate is now closed, including the managed-policy (`DisableCloud`) code
    paths.
- **`ShellXFeatures.codeRouter`** (Task 4) gates the CodeRouter items.

**`ShellXCloudGate`** (new, `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXCloudGate.swift`) holds
the pure decision logic and is tested with `swift test`.

- **Socket method prefixes:**
  - Cloud: `auth.`, `vm.`, `remotes.`, `aiAccounts.`, `billing.`
  - CodeRouter: `coderouter.`
  - Exception: `auth.login` stays local, because it is the socket-password handshake.
- **CLI verbs:**
  - Cloud: `auth`, `login`, `logout`, `billing`, `vm`, `cloud`, `vpn`, `remotes`, `remote`, `ai-accounts`,
    `vm-pty-attach`, `vm-pty-connect`, `vm-tui-connect`, `vm-ssh-attach`
  - CodeRouter: `coderouter`, `cr`
- I added `remotes`, `aiAccounts` and `vpn` beyond R17's list. Their clients use
  `AuthEnvironment.vmAPIBaseURL` (cmux.com) or `vm.tunnel_*`.

## Checklist: brief "Files"

- [x] **CloudMachinesFeature constant false:** `Packages/macOS/CmuxCloud/Sources/CmuxCloud/Machines/CloudMachinesFeature.swift:20,28`.
- [x] **DevicesFeature no longer depends on Cloud; follows `remoteMachines`:**
  - `Sources/Devices/DevicesFeature.swift:43` has `guard ShellXFeatures.remoteMachines else { return false }`.
  - `cloudEnabled` is ignored.
- [x] **MobileHostService `isListeningEnabled` gated on `remoteMachines`:** `Sources/Mobile/MobileHostService.swift:763`, the first statement.
- [x] **PresenceSettings `isEnabled` gated on `remoteMachines`:** `Sources/Cloud/PresenceSettings.swift:39`.
- [x] **Shortcuts ⌘Y / ⌘⇧Y, defaults and actions removed:**
  - The `newCloudWorkspace` / `newCloudMachine` cases are removed from both enums:
    - `ShortcutAction.swift`, plus its `+Defaults`, `+Group` and `+DisplayName` extensions;
    - `Sources/KeyboardShortcutSettings.swift`: the cases, labels and defaults.
  - Routing is removed from `AppDelegate.swift`, the former ⌘Y / ⌘⇧Y blocks before New Window.
  - Other references removed: `AppDelegate+DockShortcutRouting.swift`, `ContentView+RightSidebarCommandPalette.swift`
    and `CmuxSurfaceTabBarBuiltInAction.shortcutAction`.
  - Shortcut displays now show `.unbound`: `CloudMenuContent`, `CloudNewMachineButton` and `CloudWelcomeWindowController:264`.
  - Enumerated copies updated: `CmuxConfigSchema.generated.swift` (the `shortcuts.bindings` enum),
    `docs/configuration.md` (the plus-button section is rewritten and the ⌘Y text removed) and
    `skills/cmux-settings/references/shortcut-actions.md`.
  - Both enums still agree with each other and with the schema. The CmuxSettings and CmuxSettingsUI
    package tests pass.
- [x] **Menus are not shown:**
  - File-menu Cloud rows: removed from `Sources/cmuxApp.swift`.
  - Cloud menu: `cloudCommands` is no longer installed (`cmuxApp.swift:1097`).
  - Status-item Cloud section: the `cloudMenuEntries` / `onCloudMenuWillOpen` arguments are removed (`AppDelegate.swift:11078`).
  - Help menu: the Cloud Diagnostics, Upgrade, DEBUG pricing preview, Cloud sidebar lab, CloudWelcome
    debug and Pro checklist rows are removed (`Sources/App/CmuxHelpCommands.swift:14`).
- [x] **Command palette has no Sign In/Out/team, Cloud or Pro commands:**
  - Contributions start with `guard ShellXFeatures.cloud else { return [] }`, and handler
    registration with `... { return }`.
  - Locations: `ContentView+AuthCommandPalette.swift:15,65,121,241` and `ContentView+ProCommandPalette.swift:35,60`.
- [x] **CloudWelcome `shouldPresentAutomatically` is false:**
  - First statement at `CloudWelcomeWindowController.swift:102`.
  - Its Debug-menu entry (`cloudWelcomeDebugMenuItems`) is removed from the Help menu.
- [x] **Footer policy: no account button, Cloud button or Pro badge:**
  - `Sources/VerticalTabsSidebar+EmptyAreasAndFooter.swift:96-113`:
    - `cloudOnlyControls = [.account, .cloud, .upgrade]` is hidden while cloud is off;
    - `isUpgradeVisible` returns false.
  - Also hidden: `parkedControls = [.mobileConnect]` (phone pairing) while `remoteMachines` is false.
- [x] **RightSidebarMode `.machines` unavailable:** `RightSidebarMode+Availability.swift:110` has `return ShellXFeatures.remoteMachines && machinesEnabled`.
- [x] **Billing refresh after the auth callback is unreachable:**
  - `AppDelegate.handleAuthCallbackURLInProcess`: first statement `guard ShellXFeatures.cloud else { return false }` (`AppDelegate.swift:1598`).
  - `NativePricingPlanRefresh.refreshForProWelcomeChecklist` is gated (`PricingPlansScreen.swift:400`).
- [x] **PricingPlansScreen / ProWelcomeChecklist entry points are unreachable:**
  - Every presenter refuses first: `ProUpgradePresenter` `currentUpgradeOffer` (nil), `present`, `prefetch`,
    `presentAppPricingWeb`, `presentNativePricingPreview`, `presentCheckout` and `presentBillingPortal`
    (`PricingPlansScreen.swift:46-137`).
  - `ProWelcomeChecklistPresenter.present` and `presentIfNewlyPro`, plus `presentProWelcomeWeb` (`ProWelcomeChecklist.swift:239,245,261`).
  - `HostAccountFlow.upgradeOffer` returns nil and `isProUpgradeAvailable` returns false (`HostAccountFlow.swift:32,38`), which hides the Settings Pro card.
- [x] **Test:** `cmuxTests/ShellXCloudOffTests.swift` (`struct ShellXCloudOffTests`), wired with `scripts/sync-test-wiring`. It contains:
  - `cloudIsOff`
  - `deviceMirroringIsParkedBehindRemoteMachines`
  - `noCloudShortcutsOrPaletteCommands`, which checks both shortcut enums, the action ids and the three palette catalogs
  - `footerHasNoAccountCloudOrPro`
  - `noUpgradeOffer`
  - `cloudSocketMethodsAreRefusedBeforeAnyHandler`
  - `cloudCLIVerbsAreRefusedWithoutTheSocket`, which runs the bundled CLI against a missing socket path

## Checklist: R17 additions

- [x] **Sign-in / `cmux auth login`:**
  - CLI: verbs refused before connecting (`CLI/cmux.swift:6417`); exit 127, "Cloud is not available in ShellX."
  - Socket: every `auth.*` method except `auth.login` is refused with `not_available`.
  - As a backstop, `HostAccountFlow` refuses first in `startSignIn`, `startSignInForPane`, `signIn(timeout:)`,
    `handleCallbackURL`, `switchAccount` and `refreshBillingPlanAndReportSuccess` (`HostAccountFlow.swift:180-315`).
  - So the remaining Settings Account card cannot start a Stack Auth flow either (see Concerns).
- [x] **Socket gate on every v2 entry:**
  - `TerminalController.shellXUnavailableServiceResponse(method:id:)` (`TerminalController.swift:449`) runs
    before the focus check in all four entries:
    - sync socket (`TerminalController.swift:3033`);
    - main lane `processParsedV2Command` (`:3372`);
    - async socket (`TerminalController+ControlSocketAsync.swift:114`);
    - async main lane (`:559`).
  - The answer is `{"error":{"code":"not_available","message":"Cloud is not available in ShellX."}}`,
    with the CodeRouter message for `coderouter.*`.
- [x] **`cmux vm|cloud` and the vm.* handlers:**
  - CLI refusal as above.
  - `cmux agent <provider>` (the `vm agent` alias) refuses at the first statement of `runVMAgentCommand` (`CMUXCLI+VMTransfer.swift:1886`).
  - `vm-pty-connect`, which dials the Cloud PTY before any socket, is refused as well (commit b6d41c056c).
- [x] **`cmux vm tui` cmux.com hint removed:**
  - The usage text no longer contains the curl command.
  - The error now uses the new key `cli.vm.tui.clientMissingNoInstaller`. The old key is orphaned but kept (R8).
  - `CMUXCLI+VMTui.swift` no longer names a forbidden host.
- [x] **Billing and team socket handlers:** `vm.billing_checkout` and `auth.team.*` fall under the prefixes; `billing.` is reserved for the future. `cmux billing` is refused in the CLI.
- [x] **CodeRouter handoff:**
  - `coderouter.*` socket methods are refused.
  - `attachAuth` creates no handoff service while `codeRouter` is false (`TerminalController.swift:1145`).
  - `CodeRouterHandoffClient.mint` refuses first (`CodeRouterHandoffClient.swift:162`).
  - The CLI refuses `coderouter`/`cr`, including the cmux-owned verbs, with the same message and exit 127 as Task 4.
- [x] **`CoderouterCLIAccountReader.runCLI` never execs:** `guard ShellXFeatures.codeRouter` as the first statement (`CoderouterCLIAccountReader.swift:335`). Tests that inject `run:` are unaffected.
- [x] **Phone pairing:**
  - `performMobileConnectWorkspaceAction` (`AppDelegate.swift:8694`) is gated on `remoteMachines`.
  - So is `MobilePairingWindowController.show` (`MobilePairingWindowController.swift:40`).
  - This makes the no_phone_home "parked" claims for MobilePairingView and MobileHostV2Installation true.
- [x] **no_phone_home allowlist claims are now true:**
  - `TASK5_GATED` now names the real gates. CodeRouterHandoffClient uses the new `TASK5_CODEROUTER` reason.
  - The VMTui entry is removed, because the file no longer names a host.
- [x] **New guard `tests/test_shellx_cloud_off.py`:** 27 tests, registered in `tests/test-execution.toml` (linux-guard, next to `test_shellx_entitlements.py`). It reads the sources and asserts:
  - the three switches are constant false, and no Manaflow file mentions `remoteMachines`;
  - devices, listener, presence, pairing and the Machines mode are parked (first statements);
  - the ⌘Y actions are gone from both enums, the schema, the groups, the display names, dock routing,
    the skill reference and the docs, and the routing is gone;
  - menus, status item and Help have no Cloud entries;
  - the palette, CloudWelcome and footer gates are first statements;
  - 19 billing, Pro and sign-in entry points refuse first, and every `NativePricingPlanRefresh` func is gated;
  - every function that calls `focusSuppressionResponse(` calls the ShellX gate before it (exactly 4 entries);
  - every `"auth.|vm.|remotes.|aiAccounts.|coderouter.|billing.|team.*"` method literal in Sources and
    CmuxControlSocket is refused by the gate's parsed prefix lists (at least 40 vm.* found), and
    `auth.login` is not;
  - the CLI gate is the statement right after `rawCommandArgs`;
  - every case of the top-level `switch command` whose body sends a Cloud socket method or calls a Cloud
    runner is a refused verb (`agent` is checked through `runVMAgentCommand`);
  - pre-dispatch `if command == "..." { try runVM... }` verbs are refused;
  - CodeRouter never execs or mints;
  - the new catalog keys carry all 9 locales.
  - **Mutation checks:** I removed `vpn` and the `remotes.` prefix from the gate, and separately removed
    one async gate call. Each mutation made the guard fail, naming the verb, the methods or the entry.

## TDD evidence

RED (package):

```
$ swift test --package-path Packages/Shared/ShellXBrand
.../ShellXCloudGateTests.swift:56:21: error: cannot find 'ShellXCloudGate' in scope
error: fatalError
```

RED (guard, before the app changes):

```
$ python3 tests/test_shellx_cloud_off.py
FAIL: test_cloud_machines_feature_is_constant_false ... '!policy.isEnforced(.disableCloud)' != 'false'
... (22 FAIL lines: shortcuts, menus, palette, footer, billing, socket entries, CLI gate, CodeRouter, catalog keys)
Ran 25 tests in 0.315s
FAILED (failures=22)
```

GREEN:

```
$ swift test --package-path Packages/Shared/ShellXBrand
✔ Test run with 15 tests in 3 suites passed after 0.001 seconds.
$ python3 tests/test_shellx_cloud_off.py
Ran 27 tests in 0.499s
OK
```

The app-hosted `ShellXCloudOffTests` was written before the code it calls existed (e365ec6cd5 precedes
3ba068a26a). It runs on CI through `[unit]` (shellx-mac-unit); it is not run locally (R2).

## Upstream tests updated or deleted (778dc9c1cc; the commit message lists each with its reason)

I searched cmuxTests, cmuxCLITests, cmuxUITests, tests/, tests_v2/, scripts/, Packages/*/Tests and .github for every
switched-off API, the removed shortcut ids, the palette ids, the footer and Cloud UI identifiers, and the Cloud CLI verbs and
socket methods. There were 54 candidate Swift files. I classified each one at the level of individual test functions.

- **Rewritten to assert ShellX behaviour:**
  - CloudFeatureFlagTests
  - CloudActivationPolicyTests
  - DevicesSidebarModeTests
  - MachinesPanelModelTests
  - MobileHostServiceSettingsTests
  - PresenceHeartbeatClientTests
  - WorkspaceContentViewVisibilityTests (footer)
  - AccountUpgradeOfferTests
  - CommandPaletteAuthCommandTests (the whole file)
  - ShortcutAndCommandPaletteTests (the Cloud catalog is empty)
  - CloudWelcomeTests (never auto-presents)
  - CLICoderouterCommandTests (the agent alias is refused)
  - cmuxCLITests/CLIVPNArgumentValidationTests (vpn exits 127)
  - tests/test_cli_contract_help.py (cloud/vm guide refused)
  - AppDelegateOptionDigitShortcutRoutingTests (compile fix: the ⌘Y actions it cleared no longer exist)
- **Deleted files:**
  - Refused CLI verbs:
    - CLIVMDevTests, CLIVMLayoutEnvTests, CLIVMTransferTests
    - VMDefaultCloudCommandTests, VMSSHTransportFallbackTests
    - CloudDomainsCLIIntegrationTests, CLINotifyProcessIntegrationRegressionTests+Remotes
  - ⌘Y: NewCloudWorkspaceShortcutTests, CloudCmdYActivationRoutingTests.
  - UI tests:
    - Cloud UI: CloudSectionHeaderActions, CloudTeamPickerPlacement, NewMachineSheetKind.
    - Devices need Cloud; parked: DeviceDiscoverability, SettingsComputersBehavior.
  - Seven `cmux vm` Python tests:
    - test_cli_vm_create_name, test_cli_vm_mutation_arguments, test_cli_vm_open_device_target
    - test_cli_vm_resize, test_cli_vm_transfer_progress, test_cli_cloud_hostname, test_vm_scp
    - Their `test-execution.toml` entries were removed too.
- **Deleted functions inside kept files:** SurfaceSocketCommandTests (11 fixture tests), CLICoderouterCommandTests,
  CLIAuthAliasTests (login/logout aliases), CLINotifyProcessIntegrationRegressionTests (2 vm new),
  VMSSHCommandTests (2 vm ssh), CloudWelcomeTests (9 campaign), CloudWorkspaceTargetingTests (2),
  UpgradeAnalyticsTests (1), CloudActivationCoordinatorTests (1), test_cli_broken_pipe_writes.py (4).
- **Before each file deletion:** `shared.py` checked that no declaration in the file is used from another test file.
  The only hit was a VM helper used by the deleted VMSSH tests.
- **Kept on purpose:** tests with injected closures that do not pass through the gates, such as:
  - CloudWorkspaceTargeting/OptimisticShortcut/CreationReveal fixtures. With Cloud off,
    `CloudCreationGate` resolves to `.proceed`, so injected operation controllers behave as before.
  - CloudMenuContent, CoderouterCLIAccountReaderTests (they inject `run:`), and the pure wire and policy tests.

## Commands run (output tails)

```
$ for f in tests/test_shellx_*.py; do python3 $f; done
cloud_off OK (27), entitlements OK, guard OK, identity OK, no_phone_home OK (13), perf_harness OK, remote_daemon OK
$ python3 scripts/verify-local.py --all --jobs 3
PASSED: 15/15 selected checks ran. Native compilation, app tests and app launch were not checked.
$ ./scripts/sync-test-wiring --check ; bash scripts/lint-pbxproj-test-wiring.sh
sync-test-wiring: ok (checked 1282 test files)
lint-pbxproj-test-wiring: ok (checked 1282 Swift files)
$ python3 scripts/localization_catalog.py check ; python3 scripts/lint-xcstrings.py
10 catalogs, 9 locales: 0 parity errors
XCStrings lint passed: 23 catalog(s)
$ whole linux-guard lane vs baseline taken before any edit (scratchpad runner)
274 run; 157 failed (baseline 273 run; 157 failed): no test changed state; the only new entry is test_shellx_cloud_off.py (passes)
$ swift test --package-path Packages/macOS/CmuxSettings      -> 488 tests passed
$ swift test --package-path Packages/macOS/CmuxSettingsUI    -> 261 tests passed
$ swift test --package-path Packages/macOS/CmuxFoundation    -> 723 tests, 1 issue: "embedded schema is byte-for-byte
    web/data/cmux.schema.json" (pre-existing: web/ is not in the fork)
$ swift test --package-path Packages/macOS/CmuxCloud         -> cannot resolve: vendor/bonsplit submodule not checked out
$ xcrun swiftc -parse <every edited/added Swift file>        -> no errors
```

All `.build` directories were removed afterwards.

**Static review of the app edits (R2: not compiled).** I re-read each edit against the real signatures. For example:

- `v2WireId` is file-private in `TerminalController.swift`; the new helper lives in the same file.
- The `CloudMenuAction` memberwise init has an optional `shortcut`.
- `CLIError(message:exitCode:)` and the private `coderouterUnavailable` are in the same extension.

Every file that newly imports `ShellXBrand` belongs only to the `cmux` or `cmux-cli` target (pbxproj
membership was checked with a script). Both targets link `ShellXBrand`. No package source imports it.

## Concerns

1. **Settings Account section is still visible.** Its Sign In button does nothing, because the HostAccountFlow
   backstop refuses before any network flow. The Pro card is hidden.
   - Hiding the whole section means changing `SettingsSectionID`, the mount order and the default
     selection in CmuxSettingsUI. That was outside the brief, so I left it.
   - Suggest: a follow-up, or L2 copy work.
2. **`cmux --help` still lists the Cloud verbs.** That covers `auth`, `vm`/`cloud`, `billing`, `vpn` and
   `remotes`; they now exit 127.
   - Removing them from the usage text needs copy edits in help strings that the contract tests check.
   - This was deferred, like Task 4's CodeRouter help line.
3. **`openTeamPicker` (⌘⇧⌥T) keeps its default.** It now reaches `openCloudTeamPicker`, which shows the
   "Cloud Machines are temporarily unavailable." alert. That is not network traffic, but it is visible
   Cloud copy. The brief named only ⌘Y and ⌘⇧Y. Suggest unbinding it in a follow-up.
4. **The CmuxCloud package was not tested locally.** Its tests need the vendor/bonsplit submodule. No
   CmuxCloud package test references `CloudMachinesFeature`, so I expect no breakage there.
5. **The app, the cmuxTests bundle and the cmuxCLITests/UI test targets were compiled only by reading
   (R2).** The compile-relevant edits are simple, but CI with `[unit]` is the first real compile.
6. **Kept, not run:** the `tests_v2/test_cloud_*` manual harnesses, which need real Cloud VMs. Stale
   timing keys in `scripts/ci/*timings*.json` are harmless, as in Task 4.
7. **Orphaned catalog keys are kept (R8):** `shortcut.newCloud*.label`, `cli.vm.tui.clientMissingSearched`
   and the Cloud and Pro menu keys. `test_catalog_strings_naming_forbidden_hosts_are_unused` passes,
   because the old key with cmux.com is now unused.

## Fix round 1

This round responds to `task-5-review-1.md`: C1, I1, I2, I3, M3 and M4. The other minors are deferred as
instructed. Commits are on top of 778dc9c1cc and carry no attribution line:

- 0947d7e545 fix(shellx): team-picker shortcut passes through; drop deleted UI tests from the project
- 1c44e7bfd9 test(shellx): fix dangling @Test attributes; gate or retarget the remaining Cloud-dependent tests

### C1: dangling `@Test` attributes

- **Removed** the leftover `@Test(arguments:)` attributes:
  - `cmuxTests/AccountUpgradeOfferTests.swift`, formerly lines 26-31;
  - `cmuxTests/UpgradeAnalyticsTests.swift`, formerly lines 78-79.
- **Cause:** my function-removal helper absorbed only one-line attributes. A multi-line `@Test(arguments: [...])` was left behind.
- **Scan of every test file this task edited:** I used a scanner that follows multi-line attributes and skips blank and comment lines.
  - It reports any attribute not followed by a declaration, and any stacked `@Test`.
  - It also flags a trait placed after `arguments:`. It caught two of my new attributes, in MobileHostServiceSettingsTests; both are fixed.
  - The only remaining hit is an unrelated `@preconcurrency import` line.
- **Diff check:** the context line before every deletion block in the diff was checked as well.

### I1: upstream tests still asserting switched-off behaviour

**New mirror.** To let the app-hosted tests gate on the ShellX switches, I added `Sources/ShellX/ShellXSwitches.swift`.

- It is an internal mirror of `ShellXFeatures`, wired with `scripts/wire-app-sources.py`.
- `cmuxTests` does not link ShellXBrand, so the tests cannot import it.
- The guard asserts that the mirror reads `ShellXFeatures`.

**The seven review sites:**

- **CmuxSocketEventMapperTests `CodeRouterHandoffClientTests`:**
  - The 8 `mint()` tests are gated with `.enabled(if: ShellXSwitches.codeRouter)`.
  - New test `mintRefusesBeforeAnyRequestInShellX`: `mint()` throws `.sessionUnavailable` and the handler sees no request.
- **HostAccountFlowTeamChangeTests:**
  - `successfulAuthCallbackRefreshesThePaidEntitlement` is gated on `cloud`.
  - New test `authCallbackNeitherSignsInNorRefreshesBillingInShellX`:
    - `handleCallbackURL` returns false;
    - `refreshBillingPlanAndReportSuccess` returns false;
    - the billing state stays `.unknown`, `upgradeOffer` is nil, and `isProUpgradeAvailable` is false.
- **MobileHostIrohAdmissionTests:** both stable-pairing tests are gated on `remoteMachines`. They are the only callers of the helper at :388.
- **RightSidebarCommandPaletteTests:** the Machines availability, the command count (4 or 5) and the `.machines` command now follow `ShellXSwitches.remoteMachines`.
- **cmuxCLITests/CLIExplicitSurfaceRoutingTests:** deleted `vmTreeUsesCloudLinkErrorMessageInHumanOutput`. The CLI test target cannot see the app switch.
- **CloudTreeOneMachineManyWorkspacesTests:** the 5 tests that run `cmux vm tree` or `cmux vm open` are gated on `cloud`.
- **CmuxTuiSurfaceProviderTests:** `vmTuiConnectPassesReceiptSession` is gated on `cloud`.

**Extended search.** It covered:

- `mint(`, `handleCallbackURL(` and `handleAuthCallbackURLInProcess`;
- positive `#expect` / `XCTAssertTrue` on listener, presence, devices, incoming access or Cloud;
- `machines.isAvailable()`, sign-in, billing refresh, the presenters, the mobile pairing entries and the team picker;
- every CLI argument array that starts with a refused verb;
- every Cloud socket-method literal in cmuxTests and cmuxCLITests.

**Additional sites found:**

- **SSHStartupManualReconnectTests:** 4 tests build their fixture with `cmux vm ssh`. They are gated on `cloud`.
- **SSHStartupSignalLifecycleTests** (XCTest): its private `cmux vm ssh` fixture generator now starts with `XCTSkipUnless(ShellXSwitches.cloud, …)`. I added the `@testable import` that the file lacked.

**Hits left alone because they are pure:**

- recorded `["vm", …]` argument arrays in the machine-create models;
- startup-command string checks for `vm-pty-attach`;
- the capability list (M2, deferred);
- the CodeRouter wire-shape tests;
- the event-mapper redaction tests.

### I2: stale pbxproj entries

- Removed the 20 entries (4 per file) for the 5 deleted cmuxUITests files.
- Every deleted file of this task now has 0 references in the pbxproj.
- `scripts/check-pbxproj.sh` exits 0.
- `scripts/normalize-pbxproj.py` runs through `wire-app-sources`.
- `wire-app-sources --check` is ok for both the app and cmuxUITests.

### I3: coverage restored or retargeted

- **SurfaceSocketCommandTests:** 6 tests are restored on `withFixture(device: true)`:
  - `surface.catalog`;
  - `surface.project` (reuse/placement, rejects, other window);
  - `surface.new_terminal`;
  - the background-open test.
  - Their `vm.tree` and legacy `vm.terminal_new` parts are dropped, and the created-terminal count is now 2.
  - Only Cloud machine ids hit `cloud_disabled`. I did not run these tests (R2), so whether the device fixture passes them is CI's call.
- **test_cli_broken_pipe_writes.py:** `test_consumer_closes_during_large_stdout_write` is restored on the local `capabilities` verb. It sends a 256 KiB result, reads 16 bytes, closes stdout and expects exit 0.
- **DevicesSidebarModeTests and MobileHostServiceSettingsTests:**
  - The upstream files are restored.
  - Tests that need device mirroring carry `.enabled(if: ShellXSwitches.remoteMachines)`. In DevicesSidebarModeTests that is cloudOffDisables, independentPreferences, availability, featureGate and hostListenerGate; in MobileHostServiceSettingsTests it is the two pairing opt-in tests.
  - New ShellX tests run only while the switch is off: `devicesAreParkedInShellX` and `pairingStaysParkedWhateverTheOptIn`, gated with `.enabled(if: !ShellXSwitches.remoteMachines)`.

### M3 and M4

- **M3:**
  - `handleCloudTeamPickerShortcut` and `openCloudTeamPicker` start with `guard ShellXFeatures.cloud else { return false }`.
  - So ⌘⇧⌥T passes through and shows no alert.
  - The guard asserts both functions.
- **M4:**
  - New guard class `CloudHandlersOutsideTheGatedPrefixes`.
  - Every `workspace.cloud_vm_*` literal in the dispatcher must be a case that routes to a `v2WorkspaceCloudVM*` handler.
  - Each handler's first statement must check `CloudMachinesFeature.offMainIsEnabled()`, which is constant false.
  - There are 3 such cases.

### Fast loop

```
$ for f in tests/test_shellx_*.py; do python3 $f; done      -> all OK (cloud_off: 30 tests)
$ ./scripts/sync-test-wiring --check; bash scripts/lint-pbxproj-test-wiring.sh -> ok (1282 files)
$ python3 scripts/wire-app-sources.py --check (app and cmuxUITests)            -> ok
$ bash scripts/check-pbxproj.sh                                                -> exit 0
$ python3 scripts/localization_catalog.py check                                -> 0 parity errors
$ python3 scripts/verify-local.py --all --jobs 3                               -> PASSED: 15/15
$ linux-guard lane vs pre-task baseline                                        -> no state change except the new guard
$ xcrun swiftc -parse on every added or modified Swift file                    -> no errors
```

No package source changed this round, so `swift test` was not rerun.

### Still open

- The app, cmuxTests, cmuxCLITests and cmuxUITests are compiled only on CI (R2).
- I did not run the restored device-fixture surface tests.
- M1, M2, M5 and M6 are deferred.
