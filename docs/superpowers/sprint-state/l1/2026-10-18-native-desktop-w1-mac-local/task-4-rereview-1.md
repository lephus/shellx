### Finding Verdicts

- **I1 (CodeRouter gate): ADDRESSED.**
  - Own switch: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXFeatures.swift:9` adds `public static let codeRouter = false`. It does not reference `remoteMachines`, and the passthrough file no longer mentions `remoteMachines` (the guard checks this).
  - No exec, no download: `CLI/cmux.swift:6291-6294` starts `runCoderouterAlias` with `guard ShellXFeatures.codeRouter, let resolvedPath = resolveCoderouterExecutable(...) else { throw Self.coderouterNotAvailable() }`.
    - This is the only caller of `execCoderouter` (cmux.swift:6307,6332) and of `resolveCoderouterExecutable`.
    - Both `cmux cr` and the passthrough `cmux coderouter <verb>` (cmux.swift:6420) go through it. An installed, PATH, `~/.coderouter`, `$CODEROUTER_INSTALL` or bundled binary is never looked up.
  - Neutral message, exit 127: `CLI/CMUXCLI+CoderouterPassthrough.swift:67-72` returns `CLIError(message:exitCode: 127)` with "CodeRouter is not available in ShellX.".
    - `bootstrapCoderouter`, the cmux.com installer URL and command, the curl download and the child runner are all deleted.
    - `git grep` finds no remaining reference to a removed symbol. The `coderouterChildEnvironment` hits in cmux.swift are a different, unlabeled overload.
    - The catalog key `cli.coderouter.unavailable` has all 9 locales. The JSON parses and `localization_catalog.py check` reports 0 parity errors.
  - Install script skipped: `scripts/reload.sh:2140-2142` no longer calls `install-coderouter-client.sh`. No other script, workflow or pbxproj phase references it or `coderouter-cli.json`. The new guard test `test_coderouter_is_never_downloaded_or_run` enforces this.
  - Package test `codeRouterIsHardOff`: I ran `swift test` on a copy of `Packages/`. ShellXBrand passes 9 of 9, and the copy is deleted.

- **I2 (allowlist honesty): ADDRESSED.** Evidence is in `tests/test_shellx_no_phone_home.py:57-140`.
  - I checked every reason against the file it describes (`grep` of each file).
  - `NOT_A_HOST_ALLOWLIST` now holds the three non-host cases correctly:
    - `PhonePushCrypto:236` and `PhonePushSharedStateStorage:36` are keychain names, tagged for Task 3.
    - `DogfoodFeedbackService:62` is an email-domain check.
    - `VMTunnelManager:179` is a string comparison.
  - `BUILD_TIME_ALLOWLIST` now holds the iroh-ffi `Package.swift` and `Package.resolved` files of CmuxIrohTransport and CmuxIrxTransport, and `Resources/coderouter-cli.json`, each with a build-time reason.
  - The previously unscanned `cmux.xcodeproj/project.pbxproj:20026` and the workspace `Package.resolved:16` are now covered by `test_no_forbidden_hosts_in_xcode_project_or_workspace_pins`. Only the exact iroh-ffi literal is allowed.
  - The `CLOUD_ALLOWLIST` reasons now name what each host is for and the gate. They match the files:
    - `VMClient` has pricing links in error text.
    - `PricingPlansScreen` has a mailto.
    - `CloudSecurityExplainer` has learn-more links.
    - `PresenceSettings` and `MobileHostV2Installation` are parked behind `remoteMachines`.
  - The `auth.*`/`vm.*` gating is Task 5 under ruling R17, so the "gated in Task 5" wording is consistent with `progress.md`.
  - `python3 tests/test_shellx_no_phone_home.py`: 13 of 13 OK. All `tests/test_shellx_*.py` files pass.

- **I3 (upstream tests): ADDRESSED for the four named items. One adjacent family is not (see N1).**
  - `cmuxTests/PostHogAnalyticsPropertiesTests.swift:69-90`: the two control-plane tests now assert `postHogControlPlaneRequest == nil`, with and without consent. They also assert that no `releaseControlDistinctID` is stored. No test still expects a cmux.com host.
  - `cmuxCLITests/CLICoderouterBootstrapTests.swift`: rewritten.
    - Non-interactive and PTY-with-`y` runs get the neutral message and exit 127.
    - No `[y/N]`, curl, install.sh or cmux.com appears in the output.
    - An installed binary on PATH, in `~/.coderouter` or in `$CODEROUTER_INSTALL` is never exec'd (no args file).
    - `cmux coderouter login` is refused.
    - The helpers `BundledCLITestSupport` and `CLITestBundleAnchor` exist.
  - `cmuxUITests/SidebarHelpMenuUITests.swift`: the help-menu test and the three `FeedbackComposerShortcutUITests` now assert exactly one `mailto:` draft, no "cmux" in it, and no composer sheet. They read the draft through the DEBUG capture file. Their helpers are file-private and used in the same file.
  - `cmuxUITests/SettingsAppBehaviorUITests.swift`: I confirmed the file had only a doc-comment mention of telemetry (checked `git grep` at `d960525974`), and no assertion. The note is updated.

- **I4 (vacuous NoPhoneHome test): ADDRESSED.** Details are under "Special-attention items".
  - `cmuxTests/ShellXNoPhoneHomeTests.swift:36-66` (analytics test), `:68-74` (release-build gate), `:76-103` (flag fetch).
  - All defaults are private suites that are removed afterwards. Nothing writes `.standard`.

- **I5 (docs links): ADDRESSED. Both links are hidden.**
  - "Chord docs": `KeyboardShortcutsSection.swift:139-147` no longer has the `Link`. The "Open cmux.json" button stays.
  - "Open Docs" for custom commands: `Sources/AppDelegate+WorkspaceActionSave.swift:206-212` and `:268-272`.
    - The button and the `.alertSecondButtonReturn` case are removed, and OK is now the second button.
    - The `ShellXBrand` import is dropped. No `ShellXBrand` or `NSWorkspace` use remains in the file.
  - Hiding is right: `docs/configuration.md` only mentions chords in passing, not the syntax.
  - Guards `test_docs_links_without_a_shellx_page_are_hidden` and `test_repository_docs_links_name_existing_files` pass.

#### Special-attention items

- **(a) `PostHogAnalytics.buildAllowsCapture`: correct, production behavior unchanged, and the test can fail.**
  - Equivalence: the old `isEnabled` ended with `#if DEBUG return env["CMUX_POSTHOG_ENABLE"] == "1" #else return false`. The new `isDebugBuild && env["CMUX_POSTHOG_ENABLE"] == "1"` is the same truth table.
  - `Sources/PostHogAnalytics.swift:74-99` compiles: the default argument `PostHogAnalytics.isDebugBuild` matches the repo pattern (`MobileDeviceListLocalFirst`, `PresenceClient`), and `nonisolated static` members are fine.
  - Non-vacuity of `analyticsNeverCaptureWithTheLaunchTelemetrySwitch`:
    - `MacSentryStartupPolicy.isRunningUnderXCTest(environment:)` (`Sources/App/MacSentryStartupPolicy.swift:46-57`) inspects only the dictionary passed in. The injected `["CMUX_POSTHOG_ENABLE": "1"]` has no XCTest markers, so the XCTest guard does not fire.
    - The test host is the Debug `cmux_DEV` (`#if canImport(cmux_DEV)`), so the debug gate passes.
    - Therefore only `TelemetrySettings.enabledForCurrentLaunch == false` stops capture. If telemetry were on, `startIfNeededOnWorkQueue` would call `contextCalls.register`, set `didStart`, and the daily/hourly captures plus the identify flush would reach the recorder.
    - The assertions on the recorder, `isCaptureEnabled` and the suite would then fail.
    - Initializer argument order matches the declaration, and `PostHogContextCalls(register:)` is the memberwise init.
  - `releaseBuildsNeverCapture` tests the release answer through the helper from a Debug host. This is reasonable and honest.

- **(b) DEBUG seam in `Sources/ContentView.swift:10280-10291`: safe.**
  - The seam sits inside `#if DEBUG`, so it is compiled out of release builds.
  - In a Debug build it writes only if `CMUX_UI_TEST_CAPTURE_OPEN_URL_PATH` is set. Otherwise `UITestCaptureSink` returns false before any I/O and `openMailDraft()` runs.
  - The only line written is the constant `mailto:phule9225@gmail.com`: no user path, no user data.
  - Signatures: `UITestCaptureSink()` has a public init with a default environment, and `appendLineIfConfigured(envKey:line:)` is public and returns Bool.
  - `import CmuxTestSupport` is already used unconditionally by other app files. The package exports only `TestCaptureWriting` and `UITestCaptureSink`, so there is no name clash.
  - `FeedbackComposerSettings.submissionURL` is public.
  - The feedback notification handler is already gated to the key or main window, so the UI tests' "exactly one draft" assertion is sound.

### New Breakage in the Fix Diff

- **N1 (Important): the CodeRouter hard-off breaks about 16 upstream app-hosted tests that the fix did not touch.**
  - `cmuxTests/CLIAuthAliasTests.swift:546-1478` runs the bundled CLI as `cmux cr ...` / `cmux coderouter ...` against fake CodeRouter executables on PATH. It expects the fake to be exec'd.
  - They passed at `d960525974`. Now every one gets exit 127 and "CodeRouter is not available in ShellX.". Typical failing assertions are `result.status == 41`, `37`, `23`, `0`, and stdout equal to the fake's output.
  - Affected tests:
    - `crAliasPrefersCoderouter` (546), `aliasExecPreservesStdioAndExitStatus` (589), `npmLauncherUsesNativeVendorExecutable` (629)
    - `aliasExecKeepsNormalTerminationSignalBehavior` (695), `capabilitiesDoesNotTouchControlSocket` (736)
    - `closesHighInheritedDescriptorBeyondCurrentLimit` (770), `closesInheritedDescriptorThree` (831), `closedStandardInputStaysClosed` (878)
    - `crFallbackManagementCommandDoesNotRequestHandoff` (929), `routedCommandClassificationIsExact` (974)
    - `rejectsUnsupportedExecutableBeforeArm` (1027), `rejectsUnrelatedFallbackBeforeArm` (1086), `rejectsUnsignedExecutableBeforeArm` (1126), `boundsCapabilityProbeBeforeArm` (1168)
    - `childEnvironmentExcludesCmuxControlValues` (1251), `launchFailureDoesNotExposePathOrSystemError` (1436)
  - The implementer's search for "tests of removed behavior" missed this family. This is the same class of problem as I3.
  - Fix: delete or rewrite these tests to assert the refusal, as `CLICoderouterBootstrapTests` now does. The pure policy tests in the same file (`launchPolicy.commandRequiresHandoff`, protocol codec, the alias help localization) can stay.

- **N2 (Minor): duplicated assertion.** `cmuxTests/PostHogAnalyticsPropertiesTests.swift:84-85` repeats the identical `postHogControlPlaneRequest(telemetryEnabled: true, ...) == nil` expectation. Copy-paste leftover; harmless.

No compile-level problems found in the other changed Swift files. I checked, by reading against the real declarations:
- the `CLIError(message:exitCode:)` usage;
- the `ShellXBrand` import in cmux.swift;
- that `resolveCoderouterExecutable` is non-throwing (the `try` was correctly dropped);
- the `CmuxFeatureFlags` initializer order, `remoteValue(for:)` and `allFlags`;
- that `loadPostHogControlPlaneFlags` is now internal `nonisolated static` inside a `@MainActor` class, and its `init` closure still calls it;
- the `CmuxSettingsUI` package, which builds and passes (261 of 261, on a copy, now deleted).

### Out-of-Scope Observations

- `cmux --help` still says the CodeRouter alias "offers to install it when missing" (`cli.coderouter.aliases`, `CLI/cmux.swift:5610`), which is now untrue. `CLIAuthAliasTests.aliasHelpUsesRequestedLocalization` asserts the Japanese version of that text. Changing it needs a new catalog key under R8, so it stays deferred as a Minor.
- The eight orphaned `cli.coderouter.bootstrap.*` catalog keys remain. One still carries the cmux.com install command. The guard proves no code references them.
- The app-side `Sources/Cloud/CoderouterCLIAccountReader.runCLI` can still exec a CodeRouter from PATH or `~/.coderouter`. It is reachable from the Machines panel and the `coderouter.*` socket handlers. This belongs to Task 5 under R17.
- `scripts/reload.sh` still runs `install-cmux-tui-client.sh`, so dev and tagged builds download and bundle a client from `files.cmux.com` (build-time). The `cmux vm tui` command that uses it is Cloud-gated in Task 5. Flag for the Task 13 audit.
- `NOT_A_HOST_ALLOWLIST` holds the two PhonePush keychain-name entries. After Task 3 renames those strings, `test_allowlist_entries_are_live_and_reasoned` will fail until the controller removes the entries. The reason text says so.
- The Minor items from review 1 are still deferred, as instructed: stale remote flag cache, no-op CLI reporter work, dead Sentry debug menu item, config-template telemetry key, `$schema` URL, update-recovery link, the `CMUX_FEEDBACK_API_URL` override, and the `isForbidden(url:)` doc.

### Verdict

**Fix round:** Findings remain open. I1-I5 are all addressed with file:line evidence, and the two special-attention items (a) and (b) hold. One new Important breakage is open: **N1**, about 16 tests in `cmuxTests/CLIAuthAliasTests.swift` that exec a fake CodeRouter through `cmux cr` / `cmux coderouter` and now fail. Rewrite or delete them with a reason. Nothing else needs rework.
