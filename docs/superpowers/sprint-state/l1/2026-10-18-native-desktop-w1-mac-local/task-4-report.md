# Task 4 report: No phone-home (telemetry, remote flags, feedback, docs links)

Branch `shellx/l1-t4`, worktree `/Users/richard/Documents/helper/shellx-wt/l1-t4`, base 89129d34fa.

The original implementer's context was lost when the sprint paused (WIP commit d960525974), so no
implementer report exists for commits d208dfaf0f..d960525974. This file starts at the fix round for
`task-4-review-1.md`.

## Fix round 1

Commits (on top of d960525974):

- ae6efa6286 fix(shellx): CodeRouter is hard-off on its own switch; guard allowlist reasons are precise
- 479fdd3a53 test(shellx): ShellXNoPhoneHomeTests drive the real capture and flag paths with private defaults
- 1a2090818d fix(shellx): hide the Chord docs and custom-commands Open Docs links (no ShellX page)
- 709f470ef4 test(shellx): upstream tests assert ShellX behavior (no control-plane request, feedback mail draft, no telemetry row)

No local app build (R2). Every Swift edit was re-read against the signatures it uses
(`CLIError(message:exitCode:)`, `UITestCaptureSink.appendLineIfConfigured(envKey:line:)`, the
`PostHogAnalytics` and `CmuxFeatureFlags` initializers in their declared parameter order,
`PostHogContextCalls(register:)`).

### I1: CodeRouter gated on the wrong switch, installed binary ran, cmux.com hint (ae6efa6286)

- `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXFeatures.swift:9`: new
  `ShellXFeatures.codeRouter = false`. It is documented as permanent and does not follow
  `remoteMachines`.
- `CLI/cmux.swift:6291-6294`: `runCoderouterAlias` starts with
  `guard ShellXFeatures.codeRouter, let resolvedPath = resolveCoderouterExecutable(...) else { throw Self.coderouterNotAvailable() }`.
  Every `cmux cr` and every passthrough `cmux coderouter <verb>` hits this guard before it looks
  for a bundled, PATH or `~/.coderouter` binary. The exec and handoff code below it is now
  unreachable.
- `CLI/CMUXCLI+CoderouterPassthrough.swift`:
  - Removed: the cmux.com installer URL and install command, `bootstrapCoderouter`, the installer
    download, the child runner, the DEBUG installer seam, and the `remoteMachines` gate.
  - New `coderouterNotAvailable()` (`:67`) prints "CodeRouter is not available in ShellX." and
    exits 127, the existing convention.
- `Resources/Localizable.xcstrings`: new key `cli.coderouter.unavailable`, with all 9 locales.
- `scripts/reload.sh:2140`: no longer calls `scripts/install-coderouter-client.sh`; a comment
  explains why. That call was the only caller (I checked scripts/ and .github/).
  - The script and `Resources/coderouter-cli.json` are kept.
  - The manifest is in no Xcode resources phase and in no folder reference, so nothing bundles it.
  - No `tests/test_reload_*` test depends on that line.
- Tests:
  - `cmuxCLITests/CLICoderouterBootstrapTests.swift` is rewritten:
    - Non-interactive: neutral message, exit 127, no curl, install.sh, cmux.com or `[y/N]`, nothing
      created.
    - PTY with `y` already typed: no prompt, exit 127.
    - An installed binary on PATH, in `~/.coderouter` or in `$CODEROUTER_INSTALL` is never exec'd:
      exit 127 and no args file.
    - `cmux coderouter login` is refused the same way.
  - `ShellXNetworkPolicyTests.codeRouterIsHardOff`.
  - Guard `test_coderouter_is_never_downloaded_or_run`, which checks that:
    - the switch is false, and the guard sits at the top of `runCoderouterAlias`;
    - the passthrough code has no remoteMachines, curl, install.sh, readLine or Process();
    - no script or workflow line that is not a comment runs install-coderouter-client.sh, which I
      confirmed by running it against the old reload.sh, where it fails;
    - the pbxproj does not mention coderouter-cli.json or bin/coderouter.

### I2: CLOUD_ALLOWLIST reasons, build-time entries, unscanned pins (ae6efa6286)

All changes are in `tests/test_shellx_no_phone_home.py:57-140`.

- **`CLOUD_ALLOWLIST`**: each entry now says what the host is for and which gate keeps it
  unreachable.
  - Entries that are reachable through sign-in, Cloud, vm, billing or the CodeRouter handoff end
    with "gated in Task 5 (hard-off Cloud, socket handlers + CLI)". These are VMTui, StackAuthClient,
    AuthConfig, AuthEnvironment, VMClient, cloud-agent-skill.md, CloudSecurityExplainer,
    CodeRouterHandoffClient and PricingPlansScreen.
  - Presence, MobileHostV2Installation and MobilePairingView say "parked behind
    ShellXFeatures.remoteMachines == false (Task 5); Wave 2 swaps the transport".
  - `CMUXCLI+CoderouterPassthrough.swift` is removed: it no longer names a host.
- **`NOT_A_HOST_ALLOWLIST`** (new):
  - `PhonePushCrypto.swift` and `PhonePushSharedStateStorage.swift`: "keychain service name, renamed
    by Task 3 (coexistence); entry becomes stale at merge". They are not renamed here.
  - `DogfoodFeedbackService.swift`: "email domain comparison, not a network host".
  - `VMTunnelManager.swift`: a host string comparison, not a request.
- **`BUILD_TIME_ALLOWLIST`** now also holds the iroh-ffi `Package.swift` and `Package.resolved` of
  CmuxIrohTransport and CmuxIrxTransport, and `Resources/coderouter-cli.json`. Each has a reason.
- **New scan:** `cmux.xcodeproj/project.pbxproj` and the workspace `Package.resolved` are scanned
  line by line (`test_no_forbidden_hosts_in_xcode_project_or_workspace_pins`).
  - Only the literal `"https://github.com/manaflow-ai/iroh-ffi.git"` is allowed
    (`BUILD_TIME_PROJECT_LITERALS`, reason "build-time: ...").
  - Removing those literals makes the test fail on pbxproj:20026 and Package.resolved:16, so it is
    not vacuous.
- `test_allowlist_entries_are_live_and_reasoned` checks that:
  - no file appears twice;
  - every reason is more than a token;
  - every entry still exists and still names a forbidden host;
  - every project literal is still present.

The PhonePush entries are expected to fail this test after Task 3 merges. The controller then removes
them.

### I3: Upstream tests that failed (709f470ef4)

- `cmuxTests/PostHogAnalyticsPropertiesTests.swift:69-90`: the two control-plane tests now assert
  that no request is built, with or without consent, and that opt-out stores no
  `cmux.flags.releaseControlDistinctID`. They no longer require a cmux.com host.
- `cmuxCLITests/CLICoderouterBootstrapTests.swift`: see I1.
- `cmuxUITests/SidebarHelpMenuUITests.swift`:
  - `testHelpMenuSendFeedbackOpensMailDraft` and all 3 `FeedbackComposerShortcutUITests` tests
    (Cmd+Opt+F; with the sidebar hidden; from Settings) assert:
    - exactly one `mailto:` draft;
    - the draft does not contain "cmux";
    - the composer's email field and Send button never appear.
  - The tests no longer mention founders@cmux.com.
  - To avoid launching Mail, `Sources/ContentView.swift:10280-10291` `presentFeedbackComposer()`
    first writes the draft URL through the existing DEBUG-only `CMUX_UI_TEST_CAPTURE_OPEN_URL_PATH`
    `UITestCaptureSink`, as `TerminalLinkOpenCoordinator` already does. ContentView now imports
    `CmuxTestSupport`, which the app already links.
  - The guard's feedback check now reads the whole function body: it must end in
    `openMailDraft()` and must not mention `isFeedbackComposerPresented`.
- `cmuxUITests/SettingsAppBehaviorUITests.swift:90-95`: this suite has no telemetry assertion. Its
  only reference was the TIER 3 note, which now says the row is hidden in ShellX.
  `testMenuBarOnlyDisablesShowInMenuBarRow` compares toggle counts before and after, so the hidden
  row does not affect it.
- Searched for other tests of removed behavior: PostHog, Sentry, `sendAnonymousTelemetry`,
  `founders@`, `cmux.com`, Feedback composer, help-menu ids, and the removed CodeRouter symbols.
  - `GhosttyConfigTests` telemetry tests test the catalog setting's stored value, which is
    unchanged, so they are not affected.
  - `tests/test_cli_broken_pipe_writes.py` still has its DEBUG capture probe.
  - `tests/run_posthog_crash_launch.py` is a manual harness that nothing runs (see Concerns).
- Test wiring is unchanged: no files were added, removed or renamed.

### I4: Vacuous ShellXNoPhoneHomeTests (479fdd3a53)

- `cmuxTests/ShellXNoPhoneHomeTests.swift`:
  - **`analyticsNeverCaptureWithTheLaunchTelemetrySwitch`** builds
    `PostHogAnalytics(workQueue:userDefaults: <private suite>, capturePostHog/flushPostHog/contextCalls: recorder, environment: ["CMUX_POSTHOG_ENABLE": "1"])`
    with the default `telemetryEnabled`.
    - It calls trackActive, trackDailyActive, trackHourlyActive, capture, register and identify,
      then drains the queue.
    - It asserts that the recorder is empty and the suite is empty.
    - I did not follow the review's `environment: [:], telemetryEnabled: { true }`: in a Debug test
      host that is off only because of the debug opt-in gate. With no XCTest markers and the opt-in
      set, only `TelemetrySettings.enabledForCurrentLaunch` keeps capture off, so this test is not
      vacuous.
  - **`releaseBuildsNeverCapture`**: `Sources/PostHogAnalytics.swift:81-99` moves the build decision
    into `PostHogAnalytics.buildAllowsCapture(environment:isDebugBuild:)`. `isEnabled` calls it, so
    the release answer can be tested from a Debug host.
  - **`remoteFeatureFlagsAreNeverFetched`** (@MainActor, private suite):
    - no request is built with or without consent;
    - `loadPostHogControlPlaneFlags` returns nil (`Sources/FeatureFlags.swift:653`, now internal);
    - after `CmuxFeatureFlags(defaults:, telemetryEnabled: true, pinsFlagsToLocalValues: false).start()`
      with the default loader, there is no remote value for any flag and no `cmux.flags.remote.*`
      key in the suite.
  - The suite struct name still matches the file; the feedback, help and schema tests are kept.

### I5: Links with no ShellX page (1a2090818d)

Nothing under docs/ covers shortcut chords or cmux.json actions. cmux's pages were on cmux.com.
So both links are hidden.

- `Packages/macOS/CmuxSettingsUI/.../KeyboardShortcutsSection.swift:139`: the "Chord docs" Link is
  removed; "Open cmux.json" stays.
- `Sources/AppDelegate+WorkspaceActionSave.swift:206-212`:
  - The "Open Docs" alert button and its `.alertSecondButtonReturn` case are removed; OK is now the
    second button and falls to `default`.
  - The `ShellXBrand` import is dropped because nothing uses it any more.
- `cmuxUITests/SettingsShortcutsBehaviorUITests.swift` notes are updated.
- The catalog keys `settings.shortcuts.chords.docsButton` and `settings.settingsJSON.docsButton` stay
  (R8). The second one is still used by SettingsJSONSection.
- New guards:
  - `test_docs_links_without_a_shellx_page_are_hidden`;
  - `test_repository_docs_links_name_existing_files`: every remaining
    `github.com/lephus/shellx/blob/main/...` or `sourceCodeURL + "/blob/main/..."` target in
    Sources, CLI and Packages exists in the repository. There are 12 such links today.

### Verification (fast loop)

```
$ for f in tests/test_shellx_*.py; do python3 $f; done
tests/test_shellx_entitlements.py: Ran 2 tests  OK
tests/test_shellx_guard.py: Ran 6 tests  OK
tests/test_shellx_identity.py: Ran 14 tests  OK
tests/test_shellx_no_phone_home.py: Ran 13 tests in 15.674s  OK
tests/test_shellx_perf_harness.py: Ran 7 tests  OK
tests/test_shellx_remote_daemon.py: Ran 8 tests  OK

$ python3 scripts/verify-local.py --all --jobs 3
PASSED: 15/15 selected checks ran. Native compilation, app tests and app launch were not checked.

$ scripts/sync-test-wiring ; bash scripts/lint-pbxproj-test-wiring.sh
sync-test-wiring: clean (checked 1290 test files)
lint-pbxproj-test-wiring: ok (checked 1290 Swift files)

$ python3 scripts/localization_catalog.py check
10 catalogs, 9 locales: 0 parity errors

$ swift test --package-path Packages/Shared/ShellXBrand
✔ Test run with 9 tests in 2 suites passed   (includes codeRouterIsHardOff)
$ swift test --package-path Packages/macOS/CmuxSettingsUI
✔ Test run with 261 tests in 45 suites passed after 18.949 seconds.
$ swift test --package-path Packages/macOS/CmuxFeedback
✔ Test run with 18 tests in 4 suites passed after 0.121 seconds.
```

All three `.build` directories were removed afterwards. CmuxSentryTelemetry was not touched. The
app-host suites run on CI only:

- `ShellXNoPhoneHomeTests` and `PostHogAnalyticsPropertiesTests` run through `[unit]` /
  shellx-mac-unit (ShellX* only).
- `CLICoderouterBootstrapTests` and the UI tests run through the upstream lanes.

### Concerns and follow-ups (not fixed)

- `cmux --help` still prints "coderouter|cr ... (aliases for the CodeRouter CLI; offers to install
  it when missing)" (`cli.coderouter.aliases`, CLI/CMUXCLI+TaskHelp.swift:219). That text is now
  untrue: the command always refuses. Changing it needs a new catalog key (R8) or a copy decision
  from L2.
- The app-side `CoderouterCLIAccountReader.runCLI` (Machines panel, `Sources/Cloud`) can still exec a
  CodeRouter found on PATH or in `~/.coderouter`. No bundled copy exists any more. It is reachable
  only from the Machines panel, which Task 5 hides; Task 5 should cover it with the CodeRouter
  socket handlers (R17).
- `tests/run_posthog_crash_launch.py` is an unregistered manual harness for the removed PostHog SDK.
  It also refuses non-`com.cmuxterm` bundle ids. It can be deleted later.
- The review's Minor findings are still deferred, as instructed.

## Fix round 2

Responds to `task-4-rereview-1.md`, which found I1 to I5 addressed and two items still open (N1, N2).

Commits (on top of 709f470ef4):

- 8be44371a0 test(shellx): CodeRouter alias tests assert the refusal instead of exec'ing a fake CodeRouter
- 23a01f51aa test(shellx): drop the duplicated control-plane request assertion

### N1: Upstream CodeRouter alias tests that exec'd a fake CodeRouter (8be44371a0)

**`cmuxTests/CLIAuthAliasTests.swift` (`CLICoderouterAliasTests`)**

- **Deleted, 14 tests.** Each one needed a CodeRouter to be exec'd or probed, which ShellX never does.
  The commit message lists their names:
  - crAliasPrefersCoderouter, aliasExecPreservesStdioAndExitStatus, npmLauncherUsesNativeVendorExecutable
  - aliasExecKeepsNormalTerminationSignalBehavior, capabilitiesDoesNotTouchControlSocket
  - closesHighInheritedDescriptorBeyondCurrentLimit, closesInheritedDescriptorThree, closedStandardInputStaysClosed
  - crFallbackManagementCommandDoesNotRequestHandoff
  - rejectsUnsupportedExecutableBeforeArm, rejectsUnrelatedFallbackBeforeArm, rejectsUnsignedExecutableBeforeArm, boundsCapabilityProbeBeforeArm
  - launchFailureDoesNotExposePathOrSystemError
- **Rewritten as pure policy tests, 2 tests.** Their exec halves are dropped:
  - `routedCommandClassificationIsExact` (`:614`) keeps the `launchPolicy.commandRequiresHandoff`
    expectations. It also gains the near-match cases its exec half used to cover: `codex-helper`,
    `Codex` and `-- codex`.
  - `childEnvironmentExcludesCmuxControlValues` (`:654`) keeps only the
    `launchPolicy.childEnvironment` expectations.
- **New, `everyAliasIsRefusedBeforeExecProbeOrArm` (`:553`).** It puts fake `coderouter` and `cr`
  executables on PATH and points the CLI at the mock handoff socket. Each fake appends to a marker
  file and answers `capabilities`. It then runs seven invocations:
  - `cr --version`
  - `coderouter --version`
  - `coderouter capabilities --json`
  - `cr login --device-auth`
  - `coderouter launch`
  - `coderouter codex`
  - `cr pi`

  For every invocation it asserts:
  - exit 127;
  - empty stdout;
  - "CodeRouter is not available in ShellX." on stderr;
  - no temporary path leaked on stderr.

  After all seven runs it asserts that the marker file is absent and that the socket never received
  a request.
- **Unchanged:** the signing-field, socket-path and arm-schema tests, and `aliasHelpUsesRequestedLocalization`.
- **Removed helper:** the private `makeSocketPath` is gone because nothing used it any more. The
  extension's `makeSocketPath` calls resolve to `CLINotifyProcessTestSupport`'s helper. The
  `runCLI` parameters that no caller sets any more keep their default values, which produces no
  warnings.

**`cmuxTests/CLICoderouterCommandTests.swift:811`**

- `testCoderouterUnknownVerbStillPassesThroughToTheInstalledCLI` already expected 127 and no socket
  traffic, so it still passed.
- It is renamed to `testCoderouterUnknownVerbIsRefusedWithoutTheSocket` and now also asserts the
  refusal message, with `AppleLanguages` pinned to `(en)`.
- The header comment no longer says other verbs "still exec" CodeRouter.

**Repository-wide search**

I searched cmuxTests, cmuxCLITests, cmuxUITests, cmuxCLITestSupport, tests/, tests_v2/, scripts/,
.github/ and Packages/*/Tests for `"cr"`, `"coderouter"`, `cmux cr`, `cmux coderouter`,
`CMUX_CODEROUTER*`, `bin/coderouter`, and Python or shell `cr`/`coderouter` invocations. I found no
other test or script that runs CodeRouter through the CLI. The remaining hits do not depend on the
removed behaviour:

- `CLICoderouterBootstrapTests`, already rewritten in round 1.
- `CoderouterCLIAccountReaderTests`, which tests the app-side reader with an injected
  `isExecutable`. That reader belongs to Task 5.
- The cmux-owned verbs `status`, `machines`, `claude` and `agent` in `CLICoderouterCommandTests`,
  which go through the socket and never exec CodeRouter.
- `tests/test_cloud_vm_skill_coverage.py`, which checks docs text.
- A comment in `ControlCommandExecutionPolicyTests`.
- An omission record in `scripts/localization-allowed-omissions.json`.

`scripts/ci/cmux-unit-test-timings.json` still lists `CLICoderouterAliasTests` and the old method
name. The sharder treats that file as a cost lookup and the CI timing job regenerates it, so a stale
key does no harm.

**Parse check.** `xcrun swiftc -parse` succeeds on every edited Swift file from rounds 1 and 2. It
only parses the source and does not build anything.

### N2: Duplicated assertion (23a01f51aa)

`cmuxTests/PostHogAnalyticsPropertiesTests.swift:77`: one of the two identical
`postHogControlPlaneRequest(telemetryEnabled: true, ...) == nil` expectations is removed.

### Verification (fast loop)

```
$ scripts/sync-test-wiring ; bash scripts/lint-pbxproj-test-wiring.sh
sync-test-wiring: clean (checked 1290 test files)
lint-pbxproj-test-wiring: ok (checked 1290 Swift files)
$ for f in tests/test_shellx_*.py; do python3 $f; done
entitlements 2 OK, guard 6 OK, identity 14 OK, no_phone_home 13 OK, perf_harness 7 OK, remote_daemon 8 OK
$ python3 scripts/localization_catalog.py check
10 catalogs, 9 locales: 0 parity errors
$ python3 scripts/verify-local.py --all --jobs 3
PASSED: 15/15 selected checks ran. Native compilation, app tests and app launch were not checked.
```

No package source changed in this round, so `swift test` was not rerun.

### Concerns

- Still deferred from round 1:
  - The `cmux --help` text for the CodeRouter alias, which `aliasHelpUsesRequestedLocalization`
    still asserts in Japanese.
  - The app-side `CoderouterCLIAccountReader` exec, which belongs to Task 5.
- The CLI and app-host suites were not compiled or run here (R2). They run on CI.
