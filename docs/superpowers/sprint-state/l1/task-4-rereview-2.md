### Finding Verdicts

- **N1 - ADDRESSED.**
  - All 16 listed tests are gone or rewritten. I compared the method list of `cmuxTests/CLIAuthAliasTests.swift` at 709f470ef4 with the current file (23a01f51aa).
    - Deleted (14): `crAliasPrefersCoderouter`, `aliasExecPreservesStdioAndExitStatus`, `npmLauncherUsesNativeVendorExecutable`, `aliasExecKeepsNormalTerminationSignalBehavior`, `capabilitiesDoesNotTouchControlSocket`, `closesHighInheritedDescriptorBeyondCurrentLimit`, `closesInheritedDescriptorThree`, `closedStandardInputStaysClosed`, `crFallbackManagementCommandDoesNotRequestHandoff`, `rejectsUnsupportedExecutableBeforeArm`, `rejectsUnrelatedFallbackBeforeArm`, `rejectsUnsignedExecutableBeforeArm`, `boundsCapabilityProbeBeforeArm`, `launchFailureDoesNotExposePathOrSystemError`.
    - Rewritten as pure policy tests (2): `routedCommandClassificationIsExact` (`CLIAuthAliasTests.swift:613-625`) and `childEnvironmentExcludesCmuxControlValues` (`:653-726`). Neither starts a process any more.
    - Added (1): `everyAliasIsRefusedBeforeExecProbeOrArm` (`:553-611`).
    - Kept unchanged: `validatesTaggedDebugServerSigningFields` (`:434`), `validatesHandoffSocketPathLimit` (`:468`), `validatesExactRawArmResponseSchema` (`:482`), `aliasHelpUsesRequestedLocalization` (`:627`), `testTopLevelLoginAliasesAuthLogin` (`:298`) and `testTopLevelLogoutAliasesAuthLogout` (`:358`).
  - No remaining test depends on a CodeRouter being exec'd. I grepped `cmuxTests cmuxCLITests cmuxUITests cmuxCLITestSupport tests tests_v2 scripts .github Packages/*/Tests` for `coderouter`, `"cr"`, `CODEROUTER_*`, `CMUX_CODEROUTER`, `writeExecutable`, `#!/bin/sh` and `bin/coderouter`.
    - The only fake-binary writers left are `cmuxCLITests/CLICoderouterBootstrapTests.swift` and the new test. Both assert the refusal and that no marker or args file appears.
    - `cmuxTests/CLICoderouterCommandTests.swift` runs only cmux-owned verbs (`status`, `machines`, `claude`, `agent`), which go through the mock socket. The one `#!/bin/sh` fixture (`:710`) is a fake `claude` agent, not CodeRouter.
    - `CoderouterCLIAccountReaderTests` uses an injected `isExecutable` closure with no process (this is Task 5 territory).
    - No script, workflow or `tests/` file runs `cmux cr`. The only mention of `install-coderouter-client.sh` is a guard that asserts nothing calls it.
    - The only references to the removed test names are stale timing keys in `scripts/ci/cmux-unit-test-timings.json:215,1787`. `cmux_unit_test_shard.py` uses that file as a cost lookup and `generate_test_timings.py` regenerates it, so this is harmless.
  - The renamed test `testCoderouterUnknownVerbIsRefusedWithoutTheSocket` (`CLICoderouterCommandTests.swift:811-834`) sets `AppleLanguages=(en)` and asserts status 127, the refusal message and no socket traffic. Its header comment (`:196-199`) is updated.

- **N2 - ADDRESSED.** `cmuxTests/PostHogAnalyticsPropertiesTests.swift:78` is now the only `postHogControlPlaneRequest(telemetryEnabled: true, ...) == nil` assertion in that test. The opt-out test (`:88`) is unchanged.

#### Production-code coherence (item 2)

I read the production code and compared it with the tests.

- `CLI/cmux.swift:6280-6295`: `runCoderouterAlias` starts with `guard ShellXFeatures.codeRouter, let resolvedPath = resolveCoderouterExecutable(...) else { throw Self.coderouterNotAvailable() }`.
- `CLI/CMUXCLI+CoderouterPassthrough.swift:67-77`: the thrown error is `CLIError(message: ..., exitCode: 127)` with the default text "CodeRouter is not available in ShellX.". The `en` value of `cli.coderouter.unavailable` in `Resources/Localizable.xcstrings:656129` is the same string.
- `CLI/cmux.swift:46146-46148` writes `Error: <message>` to stderr and exits with `exitCode`, so the test's `contains` check and status 127 hold.
- `CLI/cmux.swift:6420`: `cr` and non-owned `coderouter` verbs reach the alias before any socket work. `OwnedProcessSupervisor` only matches `__owned-process-supervisor` and `__codex-teams-app-server-supervisor`.
- Each of the 7 argument vectors in `everyAliasIsRefusedBeforeExecProbeOrArm` takes the passthrough path. `["coderouter", "launch"]`, `["coderouter", "codex"]` and `["coderouter", "capabilities", "--json"]` are not in `cmuxOwnedCoderouterVerbs` (`CLI/CMUXCLI+Coderouter.swift:73-80`).
- **It fails if the refusal is removed.**
  - A fake `coderouter` and `cr` sit on `PATH`, which is `root` only. They write `CODEROUTER_MARKER_FILE` and exit 41.
  - Without the guard, the CLI would resolve the fake and exec it (the test sets `CMUX_CODEROUTER_TEST_ALLOW_UNSIGNED`).
  - The `status == 127`, empty stdout and message checks would then fail. So would the marker-file-absent check and the "No alias may arm a handoff" check.
  - `waitForRequest(timeout: 0.2)` is true only if the mock server saw a connection. The server signals only on a connection or on stop (stop runs in the `defer`, after the assertion), so a quiet CLI gives false and the check passes.
  - `runCLI` strips `CMUX_*` from the inherited environment and then sets `AppleLanguages=(en)`, so the English text is deterministic.
- `routedCommandClassificationIsExact` matches `CodeRouterLaunchPolicy.commandRequiresHandoff` (`Packages/macOS/CmuxControlSocket/.../CodeRouterLaunchPolicy.swift:10`), which accepts exactly `codex`, `opencode` and `pi` as first argument. The three near-match cases (`codex-helper`, `Codex`, `["--", "codex"]`) from the old exec loop are now direct policy assertions.
- `childEnvironmentExcludesCmuxControlValues` matches `CodeRouterLaunchPolicy.childEnvironment(_:forHandoff:preserveProviderCredentials:)`. I checked every expectation against the filter:
  - The `CMUX_`, `CMUXD_`, `DYLD_` and `CODEROUTER_HANDOFF_*` prefixes are dropped.
  - The `forHandoff` network keys (`HTTP_PROXY` family, `SSL_CERT_*`, and so on) are dropped, including the lowercase `https_proxy`.
  - `AWS_REGION`, `AWS_PROFILE`, `GOOGLE_CLOUD_PROJECT` and `SSH_AUTH_SOCK` are kept.
  - `preserveProviderCredentials: true` keeps `OPENAI_API_KEY`, `GITHUB_TOKEN`, `AWS_ACCESS_KEY_ID` and `CUSTOM_SECRET_TOKEN`.
  - The test is `func ... ()` with no `try`, so removing `throws` is consistent.
  - These two tests are pure policy and would not fail if the refusal were removed. That is expected, since they do not test it.
- Compile and wiring checks:
  - `xcrun swiftc -parse -warnings-as-errors cmuxTests/CLIAuthAliasTests.swift` passes. `-parse` also passes for `CLICoderouterCommandTests.swift` and `PostHogAnalyticsPropertiesTests.swift`.
  - `BundledCLITestSupport.bundledCLIPath(for:)` and `BundledCLILinkageTests` exist (`cmuxTests/BundledCLILinkageTests.swift:3,8,101`).
  - `Comment(rawValue:)` is already used in the file.
  - `makeSocketPath` has two remaining references (`CLIAuthAliasTests.swift:300,360`). Both sit in the `CLINotifyProcessIntegrationRegressionTests` extension and resolve to `CLINotifyProcessTestSupport.swift:23`, which this round did not touch. The deleted `makeSocketPath` was a `private` method of `CLICoderouterAliasTests`, and nothing else referenced it.
  - `bash scripts/lint-pbxproj-test-wiring.sh` reports ok (1290 Swift files). `./scripts/sync-test-wiring --check` reports ok and exits 0. The fix diff touches no pbxproj.
  - The remaining private helpers (`runCLI`, `writeExecutable`, `ProcessResult`, `launchPolicy`, `protocolCodec`, `debugIdentityPolicy`, and the file-private mock server) are all used. `runCLI`'s unused-by-callers parameters have defaults and are read in the body. Swift emits no unused-declaration warnings for private members anyway.
  - No other file references `CLICoderouterAliasTests` or `CLICoderouterMock*`. `CLIMockAcceptLoopRegistry` and `cliMockWriteAll` live in `CLIMockSocketServerSupport.swift`.
- Python guards: `tests/test_shellx_*.py` all pass (entitlements 2, guard 6, identity 14, no_phone_home 13, perf_harness 7, remote_daemon 8).

#### Coverage of non-CodeRouter behaviour (item 3)

- Nothing was lost.
- The file-descriptor, closed-stdin and signal tests exercised `execCoderouter`, which is `private` and called only from `runCoderouterAlias`. They also used `setCoderouterSpawnAttributes`, which is used only in the CodeRouter paths.
- `CLIStandardDescriptors.openAtLaunch` has just two readers: `main` (records it) and `execCoderouter`.
- The capability-probe, signing, native-executable and launch-failure tests exercised helpers that are CodeRouter-only.
- The surviving tests in the file use the fixtures that remain: `CLICoderouterMockHandoffServer` (new test), `CodeRouterHandoffProtocol` and `CodeRouterLaunchPolicy` (pure tests), and `runCLI` (new test and the help test).
- The auth `login`/`logout` alias tests are untouched.

### New Breakage in the Fix Diff

None. There is no Critical or Important breakage, and no Minor breakage that changes behaviour or compilation.

### Out-of-Scope Observations

- `testCoderouterUnknownVerbIsRefusedWithoutTheSocket` (`CLICoderouterCommandTests.swift:811`) uses an empty `PATH` and `HOME`, so it would also see the "not available" error with the flag removed. `ShellXFeatures.codeRouter` and the executable lookup share one `guard`, so a failed lookup throws the same error. It is correct for what it asserts (message, 127, no socket). The test that proves the hard-off is `everyAliasIsRefusedBeforeExecProbeOrArm`, plus the source guard `test_coderouter_is_never_downloaded_or_run`.
- `CLICoderouterMockHandoffServer` (`CLIAuthAliasTests.swift:29-295`) is now used only to bind a socket and see that nothing connects. About 250 lines of response-signing and mutation machinery (`CLICoderouterMockResponseMutation`, `response(for:...)`, `capabilityEnvironment`, `commandSnapshot`) are dead code. This is harmless, with no warning. It can be trimmed or kept in case a later wave re-enables CodeRouter.
- Stale text, all already tracked or cosmetic:
  - `cmux --help` and `aliasHelpUsesRequestedLocalization` still say the alias offers to install CodeRouter. This was deferred in round 1 because it needs a new catalog key under R8.
  - The comment at `CLI/CMUXCLI+Coderouter.swift:73-76` says non-owned verbs "behave exactly as before" through "the installed CodeRouter CLI".
  - `scripts/ci/cmux-unit-test-timings.json:215,1787` still list the old suite and test names.
- The app-side `CoderouterCLIAccountReader` exec, the orphaned `cli.coderouter.bootstrap.*` catalog keys and `reload.sh`'s `install-cmux-tui-client.sh` remain as noted in review 1. They stay with Task 5 and the Task 13 audit.
- I did not compile or run the app-host tests (read-only review, no xcodebuild). The conclusions on runtime behaviour come from reading the production code against the test code and from `swiftc -parse`.

### Verdict

**Fix round:** All findings addressed, no new Critical/Important breakage.
