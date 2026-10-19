### Spec Compliance
- **Issues found.** On this branch, no code path I could find contacts a forbidden host at launch with default settings. The brief's file list is covered (`remoteConfigFetchEnabled`, `submissionURL`, `ShellXNetworkPolicy`, Help menu, docs links, guard, app-host suite). The deviations:
  - The brief says to hide a link when ShellX has no page for it. Two links instead open the homepage: `Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/KeyboardShortcutsSection.swift:142` ("Chord docs") and `Sources/AppDelegate+WorkspaceActionSave.swift:277` ("Open Docs" for custom commands). See Important #5.
  - The `CLOUD_ALLOWLIST` reasons claim more than Task 5's brief covers. See Important #2.
  - One app-host test is vacuous, and four upstream tests now fail without being updated. See Important #3 and #4.
- **Cannot verify from diff:**
  - Whether the app and CLI targets compile and link (R2: CI only). Static checks:
    - No `import Sentry`/`PostHog`, `SentrySDK`, `PostHogSDK` or other SDK types remain anywhere in Sources/CLI/Packages. The only hit is a comment in `ios/`.
    - Every removed symbol has zero remaining references (`TransportSentryReporter(delivery:)`, `SentryEventScrubber`, `TerminalWorkSentry*`, `CLISentryRuntimePolicy`, `sentryRefreshMemoryContext`, `CmuxHelpResource` cases).
    - The surviving no-ops keep their signatures and `@MainActor` annotations.
    - The iOS call sites (`ios/cmux/AppCompositionRoot.swift:127,141,159`) still match the narrowed `MobileCrashReporter`/`TransportSentryReporter` APIs.
    - `cmux.xcodeproj/project.pbxproj` no longer has the PostHog build file, the PostHog product dependency, or the `sentry-cocoa`/`posthog-ios` remote references. The app links Sentry only through the local `CmuxSentryReporting`, which no longer depends on sentry-cocoa.
  - Whether `https://shellx.pro/schema/shellx.json` exists.
  - Whether `github.com/lephus/shellx` is public. All linked `docs/` and `skills/` files do exist on `main`.
  - Live launch traffic for code that Task 5 owns: presence, `MobileHostService` (iroh), `CloudTelemetryUploader`. This needs Task 5 plus Task 13's live audit.

Checks I ran (read-only; SwiftPM ran on copies in the scratchpad, not in the worktree):
- `python3 tests/test_shellx_no_phone_home.py`: 9/9 OK.
- All `tests/test_shellx_*.py`: OK.
- `tests/test_settings_configuration_review_paths.py`: OK.
- `scripts/localization_catalog.py check`: 0 parity errors.
- `scripts/lint-pbxproj-test-wiring.sh`: ok.
- `swift test` on copies of the packages:
  - ShellXBrand: 8 passed.
  - CmuxSentryTelemetry: 47 passed. It builds with no sentry-cocoa and no new warnings.
  - CmuxMobileCrashReporting: 3 passed.
  - CmuxFeedback: 18 passed.
  - CmuxSettingsUI: 261 passed. This includes the WIP commit's `SettingsRowAnchorResolutionTests` edit, which is correct.

### Strengths
- **SDK removal is complete and consistent.**
  - pbxproj: the PostHog build file, product dependency and package reference are gone, and so is the sentry-cocoa package reference.
  - The workspace `Package.resolved` dropped both pins. The per-package `Package.resolved` files are deleted, and so are the iOS pins.
  - `CmuxSentryTelemetry` keeps its products. `TransportSentryReporter` becomes a real no-op, and its test proves the diagnostic ring is never exported.
  - The DSNs, the PostHog key and host, and the `cmux.com/api/client-config` URL are all gone from the source.
- **Feature flags are guarded at three levels.** The call site in `AppDelegate.swift:1844` checks `remoteConfigFetchEnabled`, as do `postHogControlPlaneRequest` (`FeatureFlags.swift:638`) and `loadPostHogControlPlaneFlags` (`:657`). The default `remoteFlagValueProvider` returns nil.
- **Every feedback entry point ends in `mailto:` + `ShellXBrand.contactEmail`:**
  - Help menu
  - Sidebar help
  - The ⌘ shortcut via `.feedbackComposerRequested`
  - Socket `feedback.open`
  - The Settings host action
  - HTTP submit fails closed because there is no default endpoint, and `ShellXFeedbackMailTests` covers this.
- **Telemetry is off.** It is hard-off, and the setting row is hidden consistently in four places: the AppSection row, the curated search entry, `SettingsSearchIndex`, and the palette toggle.
- **The guard is well built and not vacuous.**
  - It parses the Swift policy, so the host list cannot drift.
  - Every non-network literal is listed with a reason. Allowlist entries must still exist and must still name a forbidden host.
  - Catalog keys that name a forbidden host must be unused.
  - My categorisation of every hit: 0 live, 13 literals removed with reasons, 55 allowlisted, 177 real comments, 96 catalog lines, 282 package-test lines.
- **Localization and rulings are followed.**
  - New keys carry all 9 locales.
  - R8: only added keys were edited in the catalogs.
  - R9: AboutPanelView changes only URL literals.
  - The Swift suite is named after its file and wired into the cmuxTests Sources phase.

### Issues

#### Critical (Must Fix)
None found on this branch. Important #2 becomes Critical if Task 5 lands without gating the socket `auth.*` and `vm.*` handlers.

#### Important (Should Fix)
1. **CodeRouter is gated on the wrong switch, and running an installed binary is not gated at all.** (`CLI/CMUXCLI+CoderouterPassthrough.swift:93`)
   - **Wrong switch.** `guard ShellXFeatures.remoteMachines, isatty…` stops the `curl https://cmux.com/coderouter/install.sh | sh` bootstrap only while `remoteMachines` is false. Wave 2 flips that flag for ShellX's own remote machines. CodeRouter is a Manaflow service that no Wave 2 transport replaces, so that flip silently brings back the cmux.com download.
   - **Execution is ungated.** `cmux cr …` (`CLI/cmux.swift:6287`) still runs any CodeRouter found first in the app bundle, then on PATH, then in `~/.coderouter`. Every dev or tagged build bundles one: `scripts/reload.sh:2140` runs `scripts/install-coderouter-client.sh`, which downloads Manaflow's binary from github.com/manaflow-ai into `Contents/Resources/bin/coderouter`. That includes the `reload.sh --tag w1` build named in the brief.
   - **Hint still points at cmux.com.** The "not installed" message still tells the user to curl from cmux.com.
   - **Fix:**
     - Use a dedicated always-false switch (or no switch at all) for both bootstrap and passthrough exec.
     - Print a neutral "CodeRouter is not available in ShellX" message.
     - Skip `install-coderouter-client.sh` for ShellX builds.
2. **The `CLOUD_ALLOWLIST` reasons are not all honest.** (`tests/test_shellx_no_phone_home.py:62-85`) Every entry carries "unreachable: … Cloud hard-off (Task 5)", which is wrong for several of them:
   - **Not hosts at all:**
     - `PhonePushCrypto.swift:236` and `PhonePushSharedStateStorage.swift:36` are keychain service names. Under R3 these are Task 3's rename, not unreachable code.
     - `DogfoodFeedbackService.swift:62` is an `@manaflow.ai` email-domain check.
   - **Build-time inputs filed as Cloud:**
     - `CmuxIrohTransport`/`CmuxIrxTransport` `Package.swift`/`Package.resolved` (iroh-ffi from github.com/manaflow-ai).
     - `Resources/coderouter-cli.json` (the dev-build download manifest).
     - These belong in `BUILD_TIME_ALLOWLIST`. The same iroh-ffi reference in `cmux.xcodeproj/project.pbxproj:20026` and the workspace `Package.resolved:16` is not scanned at all.
   - **Reachable through entry points Task 5's brief does not touch.** Task 5 lists menus, palette, footer, shortcuts, CloudWelcome, the machines sidebar, MobileHost and presence. It lists no CLI or socket handlers.
     - `cmux auth login` → socket `auth.begin_sign_in` (`CLI/cmux.swift:7117-7135`) → `AuthEnvironment`/`StackAuthClient`/`AuthConfig` (cmux.com, api.stack-auth.com).
     - `cmux vm|cloud …` → `vm.*` → `VMClient.swift`.
     - The `cmux vm tui` help prints `curl …cmux.com/tui/install-static.sh` (`CMUXCLI+VMTui.swift:79,337`).
     - `cmux cr` (see #1).
   - **Fix:**
     - Give each entry a precise reason, and move build-time entries to `BUILD_TIME_ALLOWLIST`.
     - Have the controller add the socket `auth.*`/`vm.*`/billing gating to Task 5, plus a guard assertion for that gating.
3. **Upstream tests now fail and were neither updated nor replaced:**
   - `cmuxTests/PostHogAnalyticsPropertiesTests.swift:72` and `:111`: `try #require(CmuxFeatureFlags.postHogControlPlaneRequest(…))` is now nil, and `:99` expects host `cmux.com`.
   - `cmuxCLITests/CLICoderouterBootstrapTests.swift:94` and `:118`: they expect the interactive install offer and confirm prompt, which can no longer appear.
   - `cmuxUITests/SidebarHelpMenuUITests.swift:107`: it expects the composer sheet and "founders@cmux.com", but the sheet is never presented now.
   - `cmuxUITests/SettingsAppBehaviorUITests`: it expects the telemetry row.
   - **Fix:** rewrite these to assert the ShellX behaviour (nil request, no prompt and exit 127, mail draft), or remove them with a reason.
4. **One app-host test is vacuous.** (`cmuxTests/ShellXNoPhoneHomeTests.swift:19-21`)
   - `analyticsNeverCapture` passes even if release capture were on. Under XCTest, `PostHogAnalytics.isEnabled` returns false at `Sources/PostHogAnalytics.swift:77` because `isRunningUnderXCTest` is true.
   - `telemetryAndRemoteFlagsAreOff` only reads two literal constants.
   - `postHogControlPlaneRequest(telemetryEnabled: true)` with default arguments writes a persistent `cmux.flags.releaseControlDistinctID` into the test host's `.standard` defaults.
   - **Fix:**
     - Build `PostHogAnalytics(environment: [:], telemetryEnabled: { true }, capturePostHog: recorder)`, call `trackActive`/`capture`, and assert the recorder stays empty.
     - Build `CmuxFeatureFlags(defaults: ephemeral, telemetryEnabled: true)` with the default loader, call `start()`, and assert that no request happens or no remote value appears.
     - Pass an ephemeral defaults suite.
5. **A brief requirement is missed: hide a link when there is no ShellX page.**
   - "Chord docs" (`KeyboardShortcutsSection.swift:142`) and "Open Docs" for custom commands (`AppDelegate+WorkspaceActionSave.swift:277`) open the shellx.pro homepage.
   - Other settings links in the same diff point at existing GitHub docs (for example `SettingsJSONSection` → `docs/configuration.md`).
   - **Fix:** hide these two links, or point them at `ShellXBrand.sourceCodeURL` + `/blob/main/docs/configuration.md#…` like their siblings. The sidebar and About "Docs" → website stand-ins are acceptable; About is constrained by R9.

#### Minor
- **Stale remote flag cache.** `Sources/FeatureFlags.swift:510-519` still loads cached `cmux.flags.remote.*` values even when `remoteConfigFetchEnabled == false`. A value cached by an earlier ShellX dev build (same bundle id, fetched from cmux.com) stays authoritative forever. Fix: `remoteValuesByKey = (pinsFlagsToLocalValues || !Self.remoteConfigFetchEnabled) ? [:] : …`.
- **The no-op CLI reporter still does work.** `CLI/CLISocketSentryTelemetry.swift:163-166,279-290` still classifies errors and claims a throttled capture slot, which writes `ClaudeHookSessionStore` state on error paths for events that are never sent. Return early outside the DEBUG capture probe.
- **Dead debug menu item.** The DEBUG "Trigger Sentry Test Crash" item is still wired to an empty `triggerSentryTestCrash`. Remove the menu item.
- **Leftovers still advertise the hidden telemetry setting:**
  - The generated config template writes `"sendAnonymousTelemetry": true` (`Sources/KeyboardShortcutSettingsFileStore+Template.swift:85`), which tells users telemetry is on by default.
  - `SettingsSearchIndex.swift:292` maps a settings path to the removed `telemetry` row.
  - `SettingsSearchAliases.swift:102` keeps an alias for it.
- **Unverified `$schema` URL.** `https://shellx.pro/schema/shellx.json` is written into every new config, and editors warn if it 404s. It is also duplicated as a literal in `Sources/CmuxConfigActionSaver.swift:36`; use `CmuxSettingsFileStore.schemaURLString` there.
- **Broken update-recovery link.** `Packages/macOS/CmuxUpdater/Sources/CmuxUpdater/UpdateManualDownloadRecovery.swift:53-67` links to `github.com/lephus/shellx/releases/…/cmux-macos-<arch>.dmg` assets that ShellX does not publish (ShellX ships from download.shellx.pro). Return nil until Wave 3 defines release assets.
- **HTTP feedback path survives in release builds.** The `CMUX_FEEDBACK_API_URL` override keeps an HTTP feedback upload path in release builds, and `cmux feedback --body …` returns `request_failed` instead of opening the mail draft. Make the override DEBUG-only, and have the CLI submit open the mail draft.
- **`isForbidden(url:)` is broader than documented.** `ShellXNetworkPolicy.isForbidden(url:)` treats the first path component on any host as an organization, but its doc says "on a code host". Restrict it to github.com and raw.githubusercontent.com, or fix the doc.
- **Manaflow hosts the spec list misses.** `cmux-staging.vercel.app` (`CloudTelemetryUploader.swift:23`, DEBUG only; `AuthEnvironment.swift:388,440,498`) and `api.cmux.sh` (`AuthEnvironment.swift:722`) are not in the spec's 10-entry list. Flag them for the plan owner and Task 13.
- **Stale `originHash`.** The workspace `Package.resolved` keeps its old `originHash` after its pins were removed by hand. This is probably harmless under `-disableAutomaticPackageResolution`, which only fails on missing or unsatisfied pins. Regenerate it on the next resolve.
- **Dead composer sheet.** `isFeedbackComposerPresented` and `SidebarFeedbackComposerSheet` can no longer be reached. Clean them up later.

### Assessment
**Task quality:** Needs fixes.
**Reasoning:** The core work is solid and verified in package builds: the Sentry and PostHog SDKs are fully removed, telemetry and remote flags are off, feedback goes by mail, and the Help menu is rebuilt. Not one path reachable at launch names a forbidden host. But the CodeRouter gate rides on a flag that Wave 2 will flip and leaves binary execution open. The allowlist overstates what Task 5 covers. Four upstream tests now fail. One new app-host test cannot fail.

### Forbidden-host literals still present (scanned roots: Sources, CLI, Packages/macOS, Packages/Shared, Resources)
No forbidden-host literal remains outside the allowlist and the reasoned literals. "Today" means this branch; "After T5" means Task 5 as briefed.

| path:line | host | Reachable today | After T5 |
|---|---|---|---|
| Sources/PricingPlansScreen.swift:581 | cmux.com (mailto) | user action in Pro/pricing UI (needs account) | no |
| Sources/Cloud/CloudSecurityExplainer.swift:7,26 | cmux.com/docs | user click in Cloud UI | no |
| Sources/Cloud/CodeRouterHandoffClient.swift:96,255 | coderouter.dev | only with a Stack session | yes after `cmux auth login` (not in T5) |
| Sources/Cloud/PresenceSettings.swift:22,27 (16 comment) | workers.dev, presence.cmux.dev | opt-in (pairing off by default) | no |
| Sources/Mobile/MobileHostV2Installation.swift:46-48 | workers.dev | opt-in (pairing) | no |
| Sources/Mobile/Pairing/MobilePairingView.swift:35 | github.com/manaflow-ai | click in pairing view | no |
| CLI/CMUXCLI+CoderouterPassthrough.swift:16 (11 comment) | cmux.com | printed on `cmux cr`; download blocked; exec of installed/dev-bundled CodeRouter yes | same (not in T5) |
| CLI/CMUXCLI+VMTui.swift:79,337 | cmux.com | printed hint | same (not in T5) |
| Packages/macOS/CmuxCloud/…/AuthEnvironment.swift:204,305,312,337,375,417,460,490,499,578,597,616,691,701,709,739 (184,294,324 comments) | cmux.com, api.stack-auth.com | sign-in (palette, footer, `cmux auth login`) and Cloud | `cmux auth login` still open unless T5 gates `auth.*` |
| Packages/Shared/CmuxAuthRuntime/…/StackAuthClient.swift:41; AuthConfig.swift:57-58 | stack-auth.com, cmux.com | same as above | same |
| Packages/macOS/CmuxCloud/…/VMClient.swift:137,1676 (1102 comment) | cmux.com | `cmux vm/cloud` and Cloud UI (needs auth) | CLI path not in T5 |
| Packages/macOS/CmuxCloud/…/VMTunnelManager.swift:179 (113 comment) | cmux.com (string compare) | no network | no |
| Packages/macOS/CmuxFeedback/…/DogfoodFeedbackService.swift:62 (58,83 comments) | manaflow (email domain) | not a host | n/a |
| Packages/macOS/CmuxPhonePush/…/PhonePushCrypto.swift:236; PhonePushSharedStateStorage.swift:36 | manaflow (keychain name) | not a host (R3 → T3) | n/a |
| Packages/Shared/CmuxIrohTransport/Package.swift:20, Package.resolved:7; CmuxIrxTransport/Package.swift:23, Package.resolved:7 | github.com/manaflow-ai | build-time only | build-time |
| Packages/Shared/CmuxTerminalClient/Package.swift:17 (BUILD_TIME) | manaflow-ai/cmux releases | build-time only | build-time |
| Resources/coderouter-cli.json:4 | github.com/manaflow-ai | dev builds download and bundle the binary (reload.sh) | same |
| Resources/en.lproj/cloud-agent-skill.md:185 | cmux.com/pricing (text) | Cloud agent skill text | no |
| `NON_NETWORK_LITERALS` (13 lines): os_log subsystem `ai.manaflow.cmux` at TerminalController+AuthTeam.swift:7, VaultAgentRegistry.swift:460, PhonePushClient.swift:9, and CmuxAuthRuntime ×5; KeyboardShortcutSettingsFileStore.swift:14; CmuxConfigSchema.generated.swift:13,23; UpdateFeedResolver.swift:54-55 | — | no network (the feed resolver only classifies; its fallback is download.shellx.pro) | — |
| Not scanned: cmux.xcodeproj/project.pbxproj:20026, workspace Package.resolved:16 | github.com/manaflow-ai (iroh-ffi) | build-time | build-time |
