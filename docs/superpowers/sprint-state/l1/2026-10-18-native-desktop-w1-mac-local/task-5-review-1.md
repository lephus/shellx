### Spec Compliance

Reviewed: base 23a01f51aa to head 778dc9c1cc (`shellx/l1-t5`). I read all of the production changes, the new tests, and every rewritten or trimmed upstream test.

What I ran:
- every `tests/test_shellx_*.py` guard: all pass;
- `swift test` on ShellXBrand, in a scratch copy: 15 tests pass;
- `xcrun swiftc -parse` on every added or modified Swift file: no errors;
- two mutations of the CLI guard (dropping `vpn` from the gate, and adding a `case "machines"` that sends `vm.list`): both were caught.

**Brief "Files" items: all done**
- `CloudMachinesFeature` `isAvailable(policy:)` / `isEnabled(defaults:policy:)` return a literal `false`: `Packages/macOS/CmuxCloud/.../CloudMachinesFeature.swift:20,28`.
- `DevicesFeature.isAvailable` starts with `guard ShellXFeatures.remoteMachines`, and the Cloud term is gone: `Sources/Devices/DevicesFeature.swift:43`.
- `MobileHostService.isListeningEnabled` gate: `Sources/Mobile/MobileHostService.swift:763`.
- `PresenceSettings.isEnabled` gate: `Sources/Cloud/PresenceSettings.swift:39`.
- ⌘Y / ⌘⇧Y are removed from both enums, both defaults tables, the group, the display names, dock routing, the schema, the docs and the skill reference. The routing in `AppDelegate.swift` (the old 15681-15696 block) is gone.
- Menus:
  - File-menu Cloud rows removed (`cmuxApp.swift:929`).
  - `cloudCommands` is not installed (`cmuxApp.swift:1097`).
  - The status item no longer passes `cloudMenuEntries` / `onCloudMenuWillOpen`. Both parameters have defaults (`MenuBarExtraController.swift:64-65`), so this compiles.
  - Help-menu Cloud, Pro and debug rows removed (`CmuxHelpCommands.swift:14-24`).
- Palette: every contribution and registration function guards first (`ContentView+AuthCommandPalette.swift:15,65,121,241`, `ContentView+ProCommandPalette.swift:35,60`).
- CloudWelcome `shouldPresentAutomatically` guards first (`CloudWelcomeWindowController.swift:102`). Its debug menu entry is removed.
- Footer: `SidebarFooterPresentationPolicy` hides account, Cloud and upgrade, and `isUpgradeVisible` returns false (`VerticalTabsSidebar+EmptyAreasAndFooter.swift:94-115`).
- `.machines` availability uses `ShellXFeatures.remoteMachines && machinesEnabled` (`RightSidebarMode+Availability.swift:110`).
- Billing refresh after an auth callback cannot be reached:
  - `handleAuthCallbackURLInProcess` guards first (`AppDelegate.swift:1598`);
  - `HostAccountFlow.handleCallbackURL` / `refreshBillingPlanAndReportSuccess` guard first (`HostAccountFlow.swift:212,315`);
  - `NativePricingPlanRefresh` guards first (`PricingPlansScreen.swift:400`).
- Pricing and Pro entry points:
  - all `ProUpgradePresenter` presenters guard first (`PricingPlansScreen.swift:46-137`);
  - so do `ProWelcomeChecklistPresenter` and `presentProWelcomeWeb`;
  - `HostAccountFlow.upgradeOffer` / `isProUpgradeAvailable` are covered too.
- Test: `cmuxTests/ShellXCloudOffTests.swift`. The struct name matches the file name (R5), and the pbxproj is wired. However, **the cmuxTests bundle that contains it does not compile** (see C1).

**R17 items: all done**
- **Sign-in and the `auth.*` socket methods:**
  - The CLI gate runs right after `rawCommandArgs` (`CLI/cmux.swift:6417`). It exits 127 with "Cloud is not available in ShellX.", before any socket or network use.
  - The socket gate `shellXUnavailableServiceResponse` (`TerminalController.swift:449`) runs before the focus check in all four v2 entry points: `TerminalController.swift:3033` and `:3372`, and `TerminalController+ControlSocketAsync.swift:114` and `:559`.
  - I traced `processCommand`, `processV2Command` and `handleSocketLine` into these four entry points; none bypasses them.
  - `auth.login` stays local, and it is in fact the socket-password handshake (`ControlCommandCoordinator+System.swift:30`).
  - As a backstop, `HostAccountFlow.startSignIn`, `startSignInForPane`, `signIn(timeout:)`, `handleCallbackURL` and `switchAccount` all refuse first.
- **`cmux vm|cloud` and `vm.*`:**
  - refused in the CLI and on the socket;
  - the hidden helpers `vm-pty-connect` (which dials before the socket, `cmux.swift:6524`), `vm-pty-attach`, `vm-tui-connect` and `vm-ssh-attach` are refused;
  - the `agent` alias refuses at the top of `runVMAgentCommand` (`CMUXCLI+VMTransfer.swift:1886`).
- **The `cmux vm tui` curl hint** is removed (`CMUXCLI+VMTui.swift:78,335`). The new key carries 9 locales. The catalog diff only adds the 2 new keys (R8).
- **Billing:** `vm.billing_checkout` and `auth.team.*` fall under the gate's prefixes, and `cmux billing` is refused.
- **CodeRouter:**
  - `coderouter.*` socket methods are refused;
  - no handoff service is created (`TerminalController.swift:1145`);
  - `mint()` guards first (`CodeRouterHandoffClient.swift:162`);
  - `CoderouterCLIAccountReader.runCLI` guards first (`:335`). `runProcess` has no other caller.
- **No Manaflow service is gated on `remoteMachines`.** `ShellXFeatures.cloud` is a separate constant, documented as permanent, and the guard checks that the Manaflow files never mention `remoteMachines`.
- **The no-phone-home allowlist claims are now true.** I checked each `TASK5_*` reason against the code. The VMTui entry was correctly dropped.
- **`tests/test_shellx_cloud_off.py`** exists, is registered in the linux-guard lane, and is non-vacuous for the CLI (my two mutations confirm it).

**Remaining reachable paths:** none starts Stack Auth, cmux.com, VM, billing or CodeRouter network work that I could find:
- Footer, palette, menus, shortcuts and the status item: removed or gated.
- `cmux.json` / plus-menu built-ins `.newCloudWorkspace`, `.newCloudMachine` and `.cloudVM`: they hit `CloudCreationGate` (`.proceed`), then the coordinator's `allowsOperation` (`CloudMachinesFeature.isEnabled`, false). The result is `false`, a beep, and no network.
- `workspace.cloud_vm_open/bind/terminal_ready`: they are under the `workspace.` prefix, which the gate does not cover, but each starts with a `CloudMachinesFeature.offMainIsEnabled()` guard.
- Debug socket methods `debug.native_pricing.show` / `debug.pro_welcome_checklist.show`: they reach presenters that now refuse first.
- iroh hosting: `MobileHostIrxRuntime.isNetworkingAllowed` = pairing (parked) || `DevicesFeature` (parked) || incoming access, which is itself gated on `DevicesFeature.isAvailable`.
- Launch: `auth.start()` still runs session restore. That restore only goes to the network when stored tokens exist, and no ShellX path can create tokens (see M5).

### Strengths
- **Clean three-switch design.** `cloud` is permanent, `codeRouter` comes from Task 4, and `remoteMachines` is only for Wave 2.
- **The pure decision logic sits in `ShellXCloudGate`** in ShellXBrand and is tested with `swift test` (R5). There is no new `CmuxCloud -> ShellXBrand` link edge.
- **Defence in depth.** Each feature is closed at the CLI before connecting, at all four socket entries before any handler, and with refuse-first guards in HostAccountFlow, the presenters, `mint` and `runCLI`.
- **Easy to review.** Gates are the first statement of each function, and the guard asserts exactly that. Commit messages list every test deletion with a reason.
- **Files that newly use `ShellXFeatures` / `ShellXCloudGate` all import `ShellXBrand`.** All are in the app or CLI targets, which link it.
- **I found no remaining uses of the removed shortcut cases.** Every surviving `.newCloud*` reference is the separate `CmuxSurfaceTabBarBuiltInAction` enum, and its switches stay exhaustive.

### Issues

#### Critical

**C1. The cmuxTests bundle does not compile: two dangling `@Test(arguments:)` attributes.**
When a parameterized test function was deleted, its attribute was left behind. It now stacks onto the next test function.
- `cmuxTests/AccountUpgradeOfferTests.swift:26-31`: a `@Test(arguments: [(CmuxPlanTier, CmuxPlanTier?)…])` sits directly above `@Test func footerBadgeAndPaletteNeverOfferAnUpgrade()` (line 35), a function with no parameters.
- `cmuxTests/UpgradeAnalyticsTests.swift:78-79`: a `@Test("the welcome card's Upgrade…", arguments: [CloudWelcomeTrigger…])` sits directly above `@Test("Enable, Not Now…") func welcomeOtherOutcomes()` (line 81).
- Two `@Test` attributes on one function, or arguments for a function with no parameters, are macro errors. `swiftc -parse` does not catch them, and the report's "static review" missed them.
- Effect: the `[unit]` job (`cmux-unit` scheme) cannot build the bundle, so `ShellXCloudOffTests` and every other ShellX suite fail.
- Fix: delete lines 26-31 in AccountUpgradeOfferTests and lines 78-79 in UpgradeAnalyticsTests.
- I scanned every edited test file for stacked `@Test` attributes; these are the only two.

#### Important

**I1. Upstream tests still assert behaviour this task switched off.**
They compile, but they fail on a full cmux-unit or cmuxCLITests run. The report's sweep missed them:
- `cmuxTests/CmuxSocketEventMapperTests.swift:225-330` (`CodeRouterHandoffClientTests`): `client.mint()` is expected to succeed and send a request, but `mint` now throws `sessionUnavailable` first.
- `cmuxTests/HostAccountFlowTeamChangeTests.swift:20-36`: `successfulAuthCallbackRefreshesThePaidEntitlement` expects `handleCallbackURL(...) == true` and a refreshed billing state.
- `cmuxTests/MobileHostIrohAdmissionTests.swift:388`: `#expect(MobileHostService.isListeningEnabled(defaults:, buildFlavor: .stable))` after opting in, which is now parked.
- `cmuxTests/RightSidebarCommandPaletteTests.swift:121-126`: `XCTAssertTrue(RightSidebarMode.machines.isAvailable())`, `contributions.count == 5`, and the `.machines` palette contribution expected to be non-nil.
- `cmuxCLITests/CLIExplicitSurfaceRoutingTests.swift:141` (`vmTreeUsesCloudLinkErrorMessageInHumanOutput`): runs `cmux vm tree`, which now exits 127.
- `cmuxTests/CloudTreeOneMachineManyWorkspacesTests.swift:150,703`: `runCLICloudCommand(["vm","tree"])` and `["vm","open",…]`.
- `cmuxTests/CmuxTuiSurfaceProviderTests.swift:1267`: runs `vm-tui-connect --config …` and expects status 0.

Fix: rewrite each one to assert the ShellX outcome, or delete it, as was done for the others. Then rerun the report's search to include `mint(`, `handleCallbackURL(`, `isListeningEnabled(` with a positive expectation, `machines.isAvailable()`, and every CLI argument array that starts with a refused verb.

**I2. The pbxproj still references the five deleted UI-test files.**
- Files: `CloudSectionHeaderActionsUITests`, `CloudTeamPickerPlacementUITests`, `DeviceDiscoverabilityUITests`, `NewMachineSheetKindUITests` and `SettingsComputersBehaviorUITests`.
- Each still has 4 entries in `cmux.xcodeproj/project.pbxproj`, for example lines 922, 5617, 9591 and 17758 for CloudSectionHeaderActions. The deleted cmuxTests files were unwired correctly (0 entries), but `sync-test-wiring` evidently covers only cmuxTests.
- Effect: the `cmuxUITests` target cannot build, because these input files are missing. That target is in the `cmux` and `cmux-ci` scheme test actions. ShellX CI does not catch this, because `shellx-mac` only builds the app and `cmux-unit` holds only cmuxTests.
- Fix: remove the PBXBuildFile, PBXFileReference, group and Sources-phase entries for each file. Then run `scripts/check-pbxproj.sh`.

**I3. Coverage lost for code that is still live or only parked.**
- **`SurfaceSocketCommandTests`.** The deleted 11 tests include the `surface.catalog`, `surface.project` and `surface.new_terminal` tests (reuse, placement, focus, background unread).
  - These socket methods are not refused.
  - Only cloud machine IDs get `cloud_disabled` (`Sources/Surfaces/SurfaceSocketCommands.swift:34,56,92`). Device and SSH machines still run through them.
  - The fixture already supports `withFixture(device: true)` (`SurfaceSocketCommandTests.swift:345`).
  - The file now keeps an unused `Fixture` and `FakeCloudProvider`.
  - Fix: switch the `surface.*` tests to `device: true` instead of deleting them. Delete only the tests driven by `vm.*`.
- **`tests/test_cli_broken_pipe_writes.py`.** `test_consumer_closes_during_large_stdout_write` was the only test of the CLI's large-stdout EPIPE path. It used `vm prompt` only as a carrier.
  - Fix: point the same large responder at a local verb, for example the `vault.sessions` responder the file already uses, or any verb that prints a socket result.
- **`DevicesSidebarModeTests`.** `independentPreferencesWithinCloud` and `hostListenerGate` were deleted. They cover `MobileRemoteControlPolicy` and `DevicesFeature` preference logic that Wave 2 re-enables by flipping `remoteMachines`.
  - Fix: keep them behind `.enabled(if: ShellXFeatures.remoteMachines)`, so Wave 2 gets them back automatically instead of flipping without coverage.

#### Minor

**M1. The report's Concern 1, the Settings Account card, is not a brief violation.**
- Settings is not among the brief's "Files", and R17's requirement holds: `startSignIn` / `startSignInForPane` refuse before any flow, `signInURL` stays nil, and the Pro card is hidden.
- It is still a silent dead button.
- Fix: track a follow-up to hide the section or show the neutral "not available in ShellX" text.

**M2. The report's Concern 2, `cmux --help` listing refused verbs, is not a violation.**
- Related: `system.capabilities` (`TerminalController+Capabilities.swift`) still advertises `vm.*` and `auth.*`, so capability-aware agents discover methods that answer `not_available`.
- Fix: a follow-up that removes them from the help text and the capability list.

**M3. The report's Concern 3, the ⌘⇧⌥T team picker, is not a violation.**
- It makes no network call, but it shows "Cloud Machines are temporarily unavailable." (`AppDelegate+CloudTeamPicker.swift:23-35`).
- Fix: unbind the `openTeamPicker` default, or make `handleCloudTeamPickerShortcut` return false while `ShellXFeatures.cloud` is false.

**M4. The guard's socket-literal scan mostly proves itself.**
- It scans only literals under the very prefixes the gate refuses, so it fails only if a prefix is removed. It would not notice a new Cloud method in another namespace.
- Some Cloud handlers outside those prefixes are protected only by constants the guard does not assert on: `workspace.cloud_vm_open/bind/terminal_ready` (`TerminalController+WorkspaceCreate.swift:182,221,267`), `debug.native_pricing.show` and `debug.pro_welcome_checklist.show`.
- Fix: add first-statement assertions for those three `workspace.cloud_vm_*` handlers. That keeps the docstring's promise that "a handler added later without its gate fails here".

**M5. Launch session restore still runs.**
- `MacAuthComposition.start()` (`AppDelegate.swift:2717`) still runs `AuthCoordinator` session restore, plus the PostHog and team observers.
- It contacts Stack Auth only when stored tokens exist. Sign-in is refused and Task 3 renamed the token stores, so no ShellX path can produce tokens. Acceptable.
- Optional fix: add `guard ShellXFeatures.cloud` in `MacAuthComposition.start()` so that is explicit and cheap.

**M6. Phone pairing is now also gated on `remoteMachines`.**
- `MobilePairingWindowController.show` and `performMobileConnectWorkspaceAction` gain this gate, which goes beyond the brief's three items.
- It is consistent with parking the listener, and the Stack Auth sign-in inside the pairing view stays gated by `cloud`.
- Nothing to fix now. Wave 2 must swap pairing's transport before flipping the switch; noting it here for that hand-off.

### Assessment
**Task quality: Needs fixes.**

The Cloud-off design and wiring are correct, and every brief and R17 item is met. I found no reachable path that still contacts Manaflow, Stack Auth, cmux.com, billing or CodeRouter.

The branch cannot pass `[unit]` CI, though:
- C1: two dangling `@Test(arguments:)` attributes break the cmuxTests bundle.
- I2: the deleted UI-test files remain in the pbxproj, which breaks the cmuxUITests target.
- I1: the upstream test sweep missed seven test sites (six in cmuxTests, one in cmuxCLITests) that now assert switched-off behaviour.
- I3: some deleted tests covered live or parked logic and should be retargeted, not removed.

Fix C1, I1, I2 and I3. Re-run the stacked-attribute scan and the extended test search, then push with `[unit]`.
