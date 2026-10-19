### Task 4: No phone-home — telemetry, remote flags, feedback, docs links

**Files (fork):**
- Modify: `Sources/AppDelegate.swift:1845-1925` (don't start Sentry, PostHog or `CmuxFeatureFlags` remote fetch)
- Modify: `Sources/SentryHelper.swift:9-45` (keep `sentryBreadcrumb`/`sentryCaptureWarning`/`sentryCaptureError` signatures as no-ops; remove `import Sentry`)
- Modify: `Sources/PostHogAnalytics.swift` and the files that call it (`PostHogContextCalls.swift`, `PostHogProductAnalyticsSink.swift`, `Sources/Auth/PostHogIdentityObserver.swift`, `ProductAnalytics+App.swift`, `AppDelegate+ProductAnalytics.swift`) — keep call-site APIs as no-ops
- Modify: `CLI/CLISocketSentryTelemetry.swift` (no-op), `Packages/Shared/CmuxSentryTelemetry` (keep API, drop the `sentry-cocoa` dependency), `cmux.xcodeproj/project.pbxproj:14361-14362,20059-20070,1556-1559,2885` (remove `sentry-cocoa` and `posthog-ios` package references and links)
- Modify: `Sources/FeatureFlags.swift:523,634` (`start()` never POSTs; flags resolve from local defaults)
- Modify: `Sources/TelemetrySettings.swift:10` (`enabledForCurrentLaunch` always `false`) and hide the `sendAnonymousTelemetry` setting row
- Modify: `Packages/macOS/CmuxFeedback/.../FeedbackComposerSettings.swift:31` (no HTTP submit; "Send feedback" opens `mailto:` + `ShellXBrand.contactEmail`)
- Modify: `Sources/App/CmuxHelpResource.swift` (Help menu: one item "ShellX website" → `ShellXBrand.websiteURL`, one "Source code" → `ShellXBrand.sourceCodeURL`; remove the cmux docs items), `CLI/CMUXCLI+DocsSettings.swift` (point to `https://shellx.pro`), and the scattered docs links listed in spec §9 (`ContentView.swift:15813-15816`, `AboutPanelView.swift:11`, `DockEmptyView.swift:91,102`, `AppDelegate+WorkspaceActionSave.swift:275`, CmuxSettingsUI sections, `CLI/cmux.swift:45827`, `CLI/CMUXCLI+Guide.swift:80`; hide a link when there is no ShellX page for it)
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXNetworkPolicy.swift`
- Test: `tests/test_shellx_no_phone_home.py`, `cmuxTests/ShellXNoPhoneHomeTests.swift`

**Interfaces:**
- Consumes: `ShellXBrand`.
- Produces: `ShellXNetworkPolicy.forbiddenHosts: [String]` in `ShellXBrand` (`cmux.com`, `cmux.dev`, `manaflow`, `stack-auth.com`, `sentry.io`, `posthog.com`, `axiom.co`, `coderouter.dev`, `workers.dev`, `relay.cmux.dev`) — used by the static test here and by Task 13's audit.

- [ ] **Step 1: Write the failing tests**

```python
def test_no_sentry_or_posthog_packages():
    pbx = read("cmux.xcodeproj/project.pbxproj")
    assert "sentry-cocoa" not in pbx and "posthog-ios" not in pbx
    assert offenders(r"^\s*import (Sentry|PostHog)\b", roots=["Sources", "CLI", "Packages"], allow=[]) == []

def test_no_forbidden_hosts_in_reachable_code():
    for host in FORBIDDEN_HOSTS:   # mirrors ShellXNetworkPolicy.forbiddenHosts
        assert offenders(re.escape(host), roots=["Sources", "CLI", "Packages/macOS", "Packages/Shared", "Resources"], allow=CLOUD_ALLOWLIST) == [], host
```

`CLOUD_ALLOWLIST` holds only files whose code becomes unreachable in Task 5 (e.g. `AuthEnvironment.swift`, `MobileHostV2Installation.swift`, `config/iroh/managed-relay-catalog.json`), each with reason `"unreachable: ShellXFeatures.remoteMachines == false / Cloud hard-off (Task 5)"`. Wave 2 removes entries as it replaces the transports.

```swift
@Test func telemetryAndRemoteFlagsAreOff() {
  #expect(TelemetrySettings.enabledForCurrentLaunch == false)
  #expect(CmuxFeatureFlags.remoteConfigFetchEnabled == false)
}
@Test func feedbackUsesMail() {
  #expect(FeedbackComposerSettings.submissionURL.absoluteString == "mailto:phule9225@gmail.com")
}
```

- [ ] **Step 2: Run** `python3 -m pytest tests/test_shellx_no_phone_home.py -q` and `scripts/shellx/test-app.sh ShellXNoPhoneHomeTests` — Expected: FAIL.

- [ ] **Step 3: Make the changes listed under Files.** Add `static var remoteConfigFetchEnabled: Bool { false }` to `CmuxFeatureFlags` and guard the POST with it. Expose `FeedbackComposerSettings.submissionURL`.

- [ ] **Step 4: Run the tests** — Expected: PASS. `./scripts/reload.sh --tag w1 --build-only` — Expected: builds without the Sentry/PostHog packages.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): remove Sentry/PostHog, stop remote flag fetch, mail feedback, ShellX help links"
```

