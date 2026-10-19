### Finding Verdicts
- C1: ADDRESSED. The dangling `@Test(arguments:)` is gone from AccountUpgradeOfferTests.swift (now :26-29, next to the doc comment and `@Test func footerBadgeAndPaletteNeverOfferAnUpgrade`) and from UpgradeAnalyticsTests.swift (:78 now leads straight into `welcomeOtherOutcomes`). A scan of every `@Test`/`@Suite` in cmuxTests and cmuxCLITests for an attribute not followed by a declaration found no orphans. The only hits are false positives in CloudTreeMachineResourcesTests.swift (`@Test("...")` then `@MainActor func`); that file is not in the diff. The replacement test uses `CmuxPlanTier.allCases`/`includesPro` (CaseIterable, exists), `SidebarFooterPresentationPolicy.isUpgradeVisible(isProActive:)` (second param defaulted) and `ContentView.commandPaletteProCommandContributions()` (returns [] under `guard ShellXFeatures.cloud`). All three exist.
- I1: ADDRESSED, all seven sites.
  - CmuxSocketEventMapperTests.swift:204-222 adds a Cloud-off test of `mint()` (`sessionUnavailable`, matching `guard ShellXFeatures.codeRouter` at Sources/Cloud/CodeRouterHandoffClient.swift:162). The eight upstream tests are gated `.enabled(if: ShellXSwitches.codeRouter)`.
  - HostAccountFlowTeamChangeTests.swift:20 is gated; the Cloud-off counterpart is at :45-68, and all the API it uses exists.
  - MobileHostIrohAdmissionTests.swift:365,372 are gated on remoteMachines.
  - RightSidebarCommandPaletteTests.swift:121-131 keys its assertions on `ShellXSwitches.remoteMachines`, plain XCTAssert with no trait.
  - CLIExplicitSurfaceRoutingTests: `vmTreeUsesCloudLinkErrorMessageInHumanOutput` is deleted at :141, not gated. That is acceptable, since the CLI refuses `vm`, but the coverage is gone with no Cloud-off replacement.
  - CloudTreeOneMachineManyWorkspacesTests.swift:637,667,801,873,898 are gated on cloud. This covers :150/:703 and the other `cmux vm` CLI cases.
  - CmuxTuiSurfaceProviderTests.swift:1243 is gated on cloud.
  - SSHStartupManualReconnectTests (4 tests) are gated, and SSHStartupSignalLifecycleTests.swift:1462 uses `XCTSkipUnless`. That helper is `throws`, and the file gained the `@testable import`.
- I2: ADDRESSED. project.pbxproj has 0 references to the five deleted UI-test files (CloudSectionHeaderActions, CloudTeamPickerPlacement, DeviceDiscoverability, NewMachineSheetKind, SettingsComputersBehavior). A scan found no file reference pointing at a missing UITests file. `bash scripts/lint-pbxproj-test-wiring.sh` printed "ok (checked 1282 Swift files)" and `./scripts/sync-test-wiring --check` printed "ok (checked 1282 test files)".
- I3: ADDRESSED, one gap.
  - SurfaceSocketCommandTests.swift:421-617 restores catalog, project (x3), new_terminal and background-open tests on `withFixture(device: true)`. `Fixture(device:)`, `livePaneID`, `provider.createdTerminals`/`materialized`/`refreshes` and `Self.ok`/`Self.error`/`Self.resourceIDs` all exist at the base. The handlers gate only cloud-owned machines (SurfaceSocketCommands.swift:34,53,83), so a device machine passes through. I could not run the tests.
  - tests/test_cli_broken_pipe_writes.py:131 adds the large-stdout EPIPE test through `capabilities`, which sends `system.capabilities` (CLI/cmux.swift:7051).
  - DevicesSidebarModeTests and MobileHostServiceSettingsTests are restored and gated on remoteMachines. Each has a `!remoteMachines` twin that asserts the parked behaviour.
  - Gap: `independentPreferencesWithinCloud` and `hostListenerGate` are restored but gated, so they run nowhere until Wave 2.
- M3: ADDRESSED. Sources/AppDelegate+CloudTeamPicker.swift:10 has `guard ShellXFeatures.cloud else { return false }` as the first statement of `handleCloudTeamPickerShortcut`, so the key passes through. `openCloudTeamPicker` has the same guard at :27, so the "Cloud unavailable" alert can no longer appear. `import ShellXBrand` is added.
- M4: ADDRESSED. tests/test_shellx_cloud_off.py:299-322 adds `CloudHandlersOutsideTheGatedPrefixes`. It parses every `workspace.cloud_vm_*` dispatch case, checks the literals match the dispatched set, and asserts each handler's first statement contains `CloudMachinesFeature.offMainIsEnabled()`. It also asserts that `isEnabled` is a constant `false`, and that both team-picker functions refuse first. `python3 tests/test_shellx_cloud_off.py` passes (30 tests OK).

### New Breakage in the Fix Diff
None found. Nothing was compiled; Swift review is by reading only.
- ShellXSwitches.swift is in the app target. Its PBXBuildFile (project.pbxproj:3328) is in Sources phase A5001051 (:16491), which belongs to the PBXNativeTarget at :13995, the same one that lists ShellXBrand in packageProductDependencies (:14030). The file ref is in the Sources group and the path is `ShellX/ShellXSwitches.swift`.
- Drift is not possible. The three values are `= ShellXFeatures.<name>`, not copies. `test_app_side_switch_mirror_reads_shellx_features` (test_shellx_cloud_off.py:116) pins that form. The existing `test_shellx_switches_are_false` pins the underlying `false` values.
- All 13 edited test files have `@testable import cmux_DEV` or `cmux`. The type is internal and non-isolated, so `.enabled(if:)` (an `@autoclosure @Sendable` Bool) can read it. SSHStartupSignalLifecycleTests, which had no app import, gained the conditional `@testable import`.
- Trait syntax is valid:
  - Traits sit between the display name and `arguments:` (MobileHostServiceSettingsTests.swift:16, :29, :49).
  - `.enabled(if: !ShellXSwitches.x)` without a comment is valid.
  - The same-line `@Test(...) func` form is valid.
  - The XCTest classes (RightSidebarCommandPaletteTests, the SSH signal-lifecycle extension) use no traits. They use plain asserts and `XCTSkipUnless`.
- The Sources/ code change is two early `return false` guards, which are straightforward.

### Out-of-Scope Observations
- SurfaceSocketCommandTests.swift:~620-636 keeps empty `// MARK:` stubs left from the deleted vm.* tests: "surface.catalog / vm.tree", "surface.project", "surface.new_terminal / vm.terminal_new", "background opens", "vm.workspace_*", "vm.terminal_close". Cosmetic. The first four now duplicate the new section headers above them.
- The restored surface tests assert `cloud_states` empty and `workspaces == nil` for a device machine. Both are plausible from `surfaceCatalogPayload`, but they are the likeliest place for a runtime mismatch on the first real test run.
- `test_vm_prompt_survives_closed_stderr` was removed in the previous round. Its closed-stderr coverage is not replaced, only the stdout case is.

### Verdict
APPROVE. All of C1, I1, I2, I3, M3 and M4 are addressed. I found no compile-level problem by reading, and both wiring scripts and the Python guards pass. The one real risk left is that the restored surface tests and the new Cloud-off tests were never run. They need one `xcodebuild` test run of cmuxTests, SurfaceSocketCommandTests and the gated suites before merge, which the controller must do since this review could not.
