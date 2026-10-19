# L1 lane final review 1 (opus), c3afe0da80..7eb40d29ce, read-only

Verdict: Ready (condition: green CI on the merged head before checkpoint 1).
Ran: 8/8 tests/test_shellx_*.py, verify-local 16/16, swift test ShellXBrand 15/15.
Clean: Task 5 code vs Task 3 renames; pbxproj file refs/groups/phases (ShellXSwitches in app, 3 ShellX*Tests in cmuxTests, TEST_HOST ShellX DEV); ShellXBrand link set (no Task 2 regression); test-execution.toml entries; 26 lane localization keys present; no removed symbol used by tests (576 names diffed); gates consistent (ShellXCloudGate uses cloud/codeRouter, ShellXSwitches mirror guarded, 4 v2 socket entry points gated before focus check, CLI gate before OwnedProcessSupervisor, CloudCreationGate .proceed); guards parse real dispatch tables (non-vacuous); Swift 6.0 OK.
Critical: none.
Important I1: merged head never compiled/run in CI (last green app build 9cb2895ff6 pre-Task 5; app-hosted ShellXPaths/NoPhoneHome/CloudOff + ~30 rewritten upstream cmuxTests never run; watch CloudWorkspaceTargetingTests.selectionFlow cmuxTests/CloudWorkspaceTargetingTests.swift:28,33). Fix: [unit] push so shellx-mac + shellx-mac-unit run; gate that test with .enabled(if: ShellXSwitches.cloud) if it fails.
Minor M1: Sources/Workspace.swift:4721-4728 surfaceTabBarBuiltInActionIsAvailable true for .cloudVM/.newCloudWorkspace/.newCloudMachine; .mobileConnect only flag/MDM (also AppDelegate+NewWorkspaceContextMenu.swift:118) -> user-configured buttons draw but no-op. Fix: return CloudMachinesFeature.isEnabled / ShellXFeatures.remoteMachines && ...
Minor M2: double blank line in tests/test-execution.toml (controller: not reproduced, no consecutive blank lines in the file).
