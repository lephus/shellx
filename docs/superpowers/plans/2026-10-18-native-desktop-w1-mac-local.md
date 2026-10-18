# ShellX native desktop — Wave 1: ShellX for Mac, local Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the cmux fork into ShellX for Mac that runs fully on its own: ShellX name, icon, colors, coolicons and Vietnamese; nothing talks to Manaflow or any third party; cloud-only features are gone; the sidebar groups sessions by machine (this Mac + SSH hosts) with status pills; and it is no slower than cmux.

**Architecture:** Work in the fork `~/Documents/myProjects/shellx-pro` on branch `shellx/w1-mac-local`. ShellX-only code lives in a new Swift package `Packages/Shared/ShellXBrand` (identity constants, palette, coolicons + icon map, feature switches) and in `Sources/ShellX/` (app-side views and pure models). Edits to upstream files are kept to wiring so later `upstream` merges stay small. Internal identifiers (`CMUX_*` env vars, `Cmux*` types/modules, package names) are not renamed. Remote machines (device mirroring) stay compiled but switched off behind `ShellXFeatures.remoteMachines = false` until Wave 2.

**Tech Stack:** Swift 6.0 language mode for app-linked code (Xcode targets `SWIFT_VERSION = 5.0` stay), SwiftUI + AppKit, Swift Testing for new tests (XCTest only for UI tests), Python 3 + pytest for static guard tests in `tests/`, `rsvg-convert` (installed) for icons, Sparkle 2.9.5 (kept).

**Spec:** `docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md` — §2.2 criteria 1, 3, 7; §4; §5 (Vietnamese IME, languages); §7.1 (local parts), §7.4 (visual system, binding values); §8.2; §8.6 (local + SSH); §9 (every row except iOS); §10 wave 1; §12; C1, C2, C6, C7, C13. Wave 0 ledger `docs/superpowers/ledgers/native-desktop.md` (shellx repo) is binding for which helpers are excluded and for the perf baseline file.

## Global Constraints

- **Prerequisite:** Wave 0 Tasks 1–3 done (clone, `shellx.release.entitlements`, `scripts/shellx/sign-and-notarize.sh`, `scripts/shellx/perf/perf_mac.py`, baseline JSON in the ledger).
- **Identity:** app `pro.shellx.desktop` (Release) / `pro.shellx.desktop.debug` (Debug), product name `ShellX` / `ShellX DEV`, Team ID `W4RF3W4VTZ`, URL scheme `shellx`, CLI command `shellx`, minimum macOS 14.0.
- **Coexistence with cmux:** ShellX must run at the same time as an installed cmux without sharing sockets, config, state, CLI name, hook markers, UTIs, URL scheme or keychain items.
- **Names on disk:** `~/.config/shellx/shellx.json` (and `dock.json`, `sidebars/` beside it), per-project `shellx.json` / `.shellx/shellx.json`, `~/.local/state/shellx`, `~/Library/Application Support/ShellX`, sockets `shellx.sock` / `shellx-<uid>.sock` / `/tmp/shellx-*.sock`, hook marker `"__shellx"`, UTI prefix `pro.shellx`. Ghostty config path `~/.config/ghostty/config` is unchanged and still read.
- **Palette (spec §7.4, exact):** bg `#0b0716`, panel `#100b1d`, raise `#171128`, line `#211a37`, border `#2a2145`, text `#cdc7e0`, textHi `#e6e2f2`, muted `#8a83a6`, primary `#60a5fa`, primarySoft = primary α 0.12, primaryLine = primary α 0.45, primaryText `#93c5fd`, running `#e8c468`, done `#6fd49a`, error `#e88a8a`.
- **Status → color:** waiting-for-you = primary (+ ring), running = running, done = done, error = error, idle = no pill (muted).
- **No gradients, glows or colored shadows** on UI components; the logo is the only exception. Primary button = primarySoft fill + 1 px primaryLine border + primaryText; secondary = raise fill + border + text.
- **Dark appearance only** (C2).
- **Icons:** coolicons v4.1 only (CC BY 4.0, credit "coolicons by Kryston Schwarze"). SF Symbols remain only as the fallback for symbol names that come from user configuration.
- **Strings:** every new user-visible string uses `String(localized: "<key>", defaultValue: "<English>")` and is added to the catalog with the repo's tooling (`skills/cmux-localization/SKILL.md`, `scripts/localize-changes`), so `python3 scripts/localization_catalog.py check` stays green. After Task 12 that includes `vi`.
- **No outbound traffic** to Manaflow, cmux.com/dev, Stack Auth, Sentry, PostHog, Axiom, coderouter or iroh relays (spec §4, §9, C6).
- **Tests:** new Swift tests use Swift Testing (`import Testing`, `@Test`, `#expect`). After adding a file under `cmuxTests/`, run `scripts/sync-test-wiring`. App-host tests run through `scripts/shellx/test-app.sh <Suite>` (Task 1). Static guards are `tests/test_shellx_*.py`, registered in `tests/test-execution.toml` in the same lane as `test_localizable_xcstrings_structure.py`.
- **Builds:** only through `./scripts/reload.sh --tag <tag>`; never a bare `xcodebuild` app build; never touch a running `com.cmuxterm.app`.
- **Git:** commit after every task on `shellx/w1-mac-local`; merge into the fork's `main` locally at the end; never push without asking.

## Review Focus

1. **cmux and ShellX installed together.** Both apps open at once; `cmux` CLI talks to cmux and `shellx` CLI to ShellX; hooks installed by one don't overwrite the other's. Test added to Task 3 (static guard + manual side-by-side check).
2. **The user's Ghostty theme must still win.** ShellX's default terminal colors apply only when the user has no theme/colors in their Ghostty config. Test added to Task 7.
3. **Icon names from user config.** Custom commands, workspace groups and `sidebar.compactStatusIcons` may name arbitrary SF Symbols; they must still render (fallback), never crash or show blank. Test added to Task 8.
4. **SSH hosts that drop or reconnect.** A host whose connection is lost keeps its section with an offline header and its rows; two different `user@host` targets are two machines. Tests added to Task 10.
5. **Long Vietnamese text.** Vietnamese labels are longer than English; machine names can be long. Rows and headers must keep a fixed height and truncate with an ellipsis instead of growing or clipping. Tests added to Task 10.

---

### Task 1: Branch, test runner, and the `ShellXBrand` package

**Files (fork):**
- Create: `scripts/shellx/test-app.sh`
- Create: `Packages/Shared/ShellXBrand/Package.swift`
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXBrand.swift`
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXPalette.swift`
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXFeatures.swift`
- Test: `Packages/Shared/ShellXBrand/Tests/ShellXBrandTests/ShellXBrandTests.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (add the local package; link `ShellXBrand` to the `cmux` app and `cmux-cli` targets)

**Interfaces:**
- Produces:
  - `scripts/shellx/test-app.sh <Suite> [<Suite>…]` — runs the app-hosted `cmux-unit` scheme limited to `-only-testing:cmuxTests/<Suite>` via `scripts/test-unit.sh` (extend that script to forward extra `xcodebuild` args if it doesn't).
  - `public enum ShellXBrand` with `static let` values: `appName = "ShellX"`, `cliName = "shellx"`, `bundleID = "pro.shellx.desktop"`, `teamID = "W4RF3W4VTZ"`, `urlScheme = "shellx"`, `configDirectoryName = "shellx"`, `configFileName = "shellx.json"`, `projectConfigDirectoryName = ".shellx"`, `appSupportDirectoryName = "ShellX"`, `socketBaseName = "shellx"`, `hookMarker = "__shellx"`, `utiPrefix = "pro.shellx"`, `websiteURL: URL` = `https://shellx.pro`, `sourceCodeURL: URL` = `https://github.com/lephus/shellx-pro`, `contactEmail = "phule9225@gmail.com"`, `updateFeedURL: URL` = `https://download.shellx.pro/desktop/appcast.xml`.
  - `public struct ShellXColor: Equatable, Sendable { init(hex: UInt32, alpha: Double = 1); var hexString: String /* "#rrggbb" */; var alpha: Double; var color: SwiftUI.Color; var nsColor: NSColor }`.
  - `public enum ShellXPalette` with `static let` `bg, panel, raise, line, border, text, textHi, muted, primary, primarySoft, primaryLine, primaryText, running, done, error: ShellXColor` (values in Global Constraints).
  - `public enum ShellXFeatures { public static let remoteMachines = false }` — Wave 2 flips it.

- [ ] **Step 1: Branch**

```bash
cd ~/Documents/myProjects/shellx-pro && git switch main && git switch -c shellx/w1-mac-local
```

- [ ] **Step 2: Write the failing package tests**

```swift
@Test func paletteMatchesSpec() {
  #expect(ShellXPalette.bg.hexString == "#0b0716")
  #expect(ShellXPalette.primary.hexString == "#60a5fa")
  #expect(ShellXPalette.running.hexString == "#e8c468")
  #expect(ShellXPalette.done.hexString == "#6fd49a")
  #expect(ShellXPalette.error.hexString == "#e88a8a")
  #expect(ShellXPalette.primarySoft.hexString == "#60a5fa" && ShellXPalette.primarySoft.alpha == 0.12)
  #expect(ShellXPalette.primaryLine.alpha == 0.45)
}
@Test func identity() {
  #expect(ShellXBrand.bundleID == "pro.shellx.desktop")
  #expect(ShellXBrand.cliName == "shellx")
  #expect(ShellXFeatures.remoteMachines == false)
}
```

Add one `#expect` per remaining palette token with its spec value.

- [ ] **Step 3: Run** `swift test --package-path Packages/Shared/ShellXBrand` — Expected: FAIL (types missing).

- [ ] **Step 4: Implement the package** (`swift-tools-version: 6.0`, `.macOS(.v14)`, library product `ShellXBrand`), then link it in the project.

- [ ] **Step 5: Run** `swift test --package-path Packages/Shared/ShellXBrand` — Expected: PASS. Then `CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag w1 --build-only` — Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Packages/Shared/ShellXBrand scripts/shellx/test-app.sh scripts/test-unit.sh cmux.xcodeproj/project.pbxproj
git commit -m "feat(shellx): ShellXBrand package (identity, palette, feature switches) and app test runner"
```

### Task 2: App identity — bundle ids, name, team, scheme, update feed

**Files (fork):**
- Modify: `cmux.xcodeproj/project.pbxproj` (app + `CmuxDockTilePlugin` bundle ids and product names; `CMUX_TEAM_ID_PREFIX` → `W4RF3W4VTZ.`; `CMUX_AUTH_CALLBACK_SCHEME` → `shellx` / `shellx-dev`; `SPARKLE_PUBLIC_KEY` → empty; remove the `cmuxTunnelExtension` target from the app's embed phase and dependencies; exclude helpers listed as excluded in the W0 ledger)
- Modify: `Resources/Info.plist` (`SUFeedURL` → `ShellXBrand.updateFeedURL` value; `SUEnableAutomaticChecks` = `false` until Wave 3 sets the EdDSA key)
- Modify: `scripts/reload.sh:11-12` (`APP_NAME="ShellX DEV"`, `BUNDLE_ID="pro.shellx.desktop.debug"`)
- Modify: Swift team-ID pins: `CLI/cmux.swift:3128,3134,3717,4821`, `CLI/CMUXCLI+Sudo.swift:102`, `ComputerUseHelperTrust.swift:19`, `CodeRouterDebugServerIdentityPolicy.swift:24`, `Sources/Cloud/CodeRouterSocketPeerVerifier.swift` (use `ShellXBrand.teamID` where the file can import it; otherwise the literal `W4RF3W4VTZ`)
- Modify: every non-test Swift literal `com.cmuxterm.app` used as *our own* bundle id (151 files mention `com.cmuxterm`; replace with `ShellXBrand.bundleID`-derived values; leave MDM-domain strings for Task 4)
- Create: `tests/shellx_guard.py` (shared helpers for every `tests/test_shellx_*.py`)
- Test: `tests/test_shellx_identity.py`

**Interfaces:**
- Consumes: `ShellXBrand` (Task 1).
- Produces:
  - tagged dev builds are `ShellX DEV <tag>.app` with bundle id `pro.shellx.desktop.debug.<tag>`;
  - `tests/shellx_guard.py`: `read(path) -> str`, `offenders(pattern: str, roots: list[str], allow: list[tuple[str, str]]) -> list[str]` (walks text files under `roots`, returns `"path:line"` hits whose path is not in `allow`; every allow entry is `(path, reason)`), `png_size(path) -> tuple[int, int]`, `sha256(path) -> str`. Later tasks import these.

- [ ] **Step 1: Write the failing guard test**

```python
def test_app_bundle_ids_are_shellx():
    pbx = read("cmux.xcodeproj/project.pbxproj")
    assert "PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop;" in pbx
    assert "PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop.debug;" in pbx
    assert "com.cmuxterm.app;" not in pbx and "7WLXT3NR37" not in pbx

def test_no_upstream_team_id_in_sources():
    assert offenders(r"7WLXT3NR37", roots=["Sources", "CLI", "Packages", "Resources", "scripts"], allow=ALLOWLIST) == []

def test_update_feed_is_shellx():
    info = plistlib.load(open("Resources/Info.plist", "rb"))
    assert info["SUFeedURL"] == "https://download.shellx.pro/desktop/appcast.xml"
    assert info["SUEnableAutomaticChecks"] is False
```

`offenders` and `read` come from `tests/shellx_guard.py`; `ALLOWLIST` is a module-level list of `(path, reason)` that starts empty.

- [ ] **Step 2: Run** `python3 -m pytest tests/test_shellx_identity.py -q` — Expected: FAIL.

- [ ] **Step 3: Make the identity changes listed under Files.**

- [ ] **Step 4: Run the test** — Expected: PASS. Run `./scripts/reload.sh --tag w1 --build-only` — Expected: `ShellX DEV w1.app` builds; `defaults read "<app>/Contents/Info" CFBundleIdentifier` prints `pro.shellx.desktop.debug.w1`.

- [ ] **Step 5: Register the test lane and commit**

```bash
git add -A tests/test_shellx_identity.py tests/test-execution.toml cmux.xcodeproj Resources/Info.plist scripts/reload.sh Sources CLI Packages
git commit -m "feat(shellx): ShellX bundle ids, team, URL scheme and update feed; drop tunnel extension"
```

### Task 3: Coexistence — paths, sockets, CLI name, hook marker, UTIs

**Files (fork):**
- Modify: `Packages/macOS/CmuxSettings/Sources/CmuxSettings/SocketControl/SocketControlSettings.swift:23-25,358` (socket names from `ShellXBrand.socketBaseName`, `/tmp/shellx-last-cli-path`)
- Modify: `CmuxStateDirectory.swift:33` (`~/.local/state/shellx`)
- Modify: the 46 Application Support sites (`ShellX` directory), `KeyboardShortcutSettingsFileStore.swift:20` and `CmuxConfig.swift:1846` plus the other config-path references (197 refs in 52 files: `~/.config/shellx/shellx.json`, per-project `shellx.json` / `.shellx/shellx.json`)
- Modify: `cmux.xcodeproj/project.pbxproj` (`cmux-cli` `PRODUCT_NAME = shellx`; exported UTIs `com.cmux.*` → `pro.shellx.*`; sidebar extension point `com.cmuxterm.app.cmux.sidebar` → `pro.shellx.desktop.sidebar`)
- Modify: `Sources/App/CmuxCLIPathInstaller.swift:55` (`/usr/local/bin/shellx`), `Sources/HostSettingsActions.swift:161`, `Sources/TerminalController+SocketCleanup.swift:54`, `Sources/RemoteInteractiveShellBootstrapBuilder.swift:274` (`~/.shellx/bin/shellx`), `Resources/shell-integration/*`, `Resources/bin/cmux-*-wrapper` (rename to `shellx-*-wrapper`), `cmux.sdef` (suite name ShellX)
- Modify: `CLI/CMUXCLI+AgentHookCatalog.swift` and `cmux-codex-hook-*.sh` (marker `"__shellx"`; hook command `shellx claude-hook` etc.)
- Modify: keychain service names (`com.cmuxterm.app.socket-control`, `com.cmuxterm.iroh.*.v1`, `ai.manaflow.cmux.phone-push.*`) → `pro.shellx.desktop.*`
- Test: `tests/test_shellx_coexistence.py`, `cmuxTests/ShellXPathsTests.swift`

**Interfaces:**
- Consumes: `ShellXBrand` (Task 1), tagged build (Task 2).
- Produces: the bundled CLI at `Contents/Resources/bin/shellx`; Task 13's perf harness calls it.

- [ ] **Step 1: Write the failing tests**

```python
FORBIDDEN = [r"/tmp/cmux", r"\.config/cmux", r"\.local/state/cmux", r"Application Support/cmux",
             r'"__cmux"', r"\bcom\.cmux\.", r"/usr/local/bin/cmux\b", r"cmux\.sock"]
def test_no_cmux_runtime_names():
    for pat in FORBIDDEN:
        assert offenders(pat, roots=["Sources", "CLI", "Packages", "Resources"], allow=ALLOWLIST) == [], pat
def test_cli_product_is_shellx():
    assert re.search(r"PRODUCT_NAME = shellx;", read("cmux.xcodeproj/project.pbxproj"))
```

```swift
@Test func runtimePathsAreShellX() {
  #expect(CmuxStateDirectory.defaultURL.path.hasSuffix("/.local/state/shellx"))
  #expect(SocketControlSettings.defaultSocketFileName.hasPrefix("shellx"))
  #expect(CmuxConfig.userConfigURL.path.hasSuffix("/.config/shellx/shellx.json"))
}
```

Use the real accessor names in those types (read them first). If an accessor doesn't exist, add a `static var` that the existing code already computes inline, and use it at the call site.

- [ ] **Step 2: Run** `python3 -m pytest tests/test_shellx_coexistence.py -q` and `scripts/shellx/test-app.sh ShellXPathsTests` — Expected: FAIL.

- [ ] **Step 3: Make the renames listed under Files.** Environment variable names (`CMUX_*`) stay as they are.

- [ ] **Step 4: Run both tests and the CLI tests** — Expected: PASS for the new tests. Run `xcodebuild test-without-building -only-testing:cmuxCLITests` through the repo's CLI test lane; update CLI tests whose expected text names `cmux` as the command.

- [ ] **Step 5: Manual side-by-side check (Review Focus 1)**

Install upstream cmux (if not present) and launch it together with `ShellX DEV w1.app`. In a cmux terminal, `cmux identify` (or the equivalent status command) reaches cmux. In a ShellX terminal, `shellx identify` reaches ShellX. `ls /tmp | grep -E 'cmux|shellx'` shows separate sockets. Record the result in the ledger.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(shellx): own sockets, config/state paths, CLI name, hook marker and UTIs so ShellX coexists with cmux"
```

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

### Task 5: Cloud-only features off; device mirroring parked behind `remoteMachines`

**Files (fork):**
- Modify: `Packages/macOS/CmuxCloud/.../Machines/CloudMachinesFeature.swift` (`isAvailable`/`isEnabled` constant `false`)
- Modify: `Sources/Devices/DevicesFeature.swift:35` (no longer depends on Cloud; returns `ShellXFeatures.remoteMachines`)
- Modify: `Sources/Mobile/MobileHostService.swift:756` (`isListeningEnabled` → `ShellXFeatures.remoteMachines`), `Sources/Cloud/PresenceSettings.swift` (`isEnabled` → `ShellXFeatures.remoteMachines`)
- Modify: shortcuts ⌘Y / ⌘⇧Y (`ShortcutAction+Defaults.swift:85-86`, `Sources/KeyboardShortcutSettings.swift:470-476`, routing `AppDelegate.swift:15768-15782,18316`) — remove the defaults and the actions
- Modify: menus `Sources/cmuxApp.swift:931-938`, `Sources/cmuxApp+CloudMenu.swift`, status-item section `AppDelegate.swift:11159` — not shown
- Modify: command palette `Sources/ContentView+AuthCommandPalette.swift` — drop Sign In/Out/team (:12-60) and Cloud commands (:114)
- Modify: `Sources/Cloud/CloudWelcomeWindowController.swift:92` (`shouldPresentAutomatically` → `false`) and remove its Debug menu entry
- Modify: `Sources/VerticalTabsSidebar+EmptyAreasAndFooter.swift:92` `SidebarFooterPresentationPolicy` — no account button, cloud button or Pro badge
- Modify: `RightSidebarMode+Availability.swift:106` (`.machines` unavailable while `remoteMachines == false`)
- Modify: billing refresh after auth callback (`AppDelegate.swift:1615`) and `PricingPlansScreen` / `ProWelcomeChecklist` entry points — unreachable
- Test: `cmuxTests/ShellXCloudOffTests.swift`

**Interfaces:**
- Consumes: `ShellXFeatures.remoteMachines` (Task 1).
- Produces: nothing new; Wave 2 re-enables `DevicesFeature`, `MobileHostService` listening and presence by flipping `remoteMachines` after swapping their transport and auth.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func cloudIsOff() {
  #expect(CloudMachinesFeature.isAvailable == false)
  #expect(DevicesFeature.isAvailable == false)
  #expect(CloudWelcomeWindowController.shouldPresentAutomatically == false)
}
@Test func noCloudShortcutsOrPaletteCommands() {
  let defaults = ShortcutAction.defaultBindings.map(\.keyEquivalentDescription)
  #expect(!defaults.contains("⌘Y") && !defaults.contains("⌘⇧Y"))
  #expect(AuthCommandPalette.commandIDs.isEmpty)
}
@Test func footerHasNoAccountCloudOrPro() {
  let p = SidebarFooterPresentationPolicy.resolve(/* current defaults */)
  #expect(!p.showsAccountButton && !p.showsCloudButton && !p.showsProBadge)
}
```

Use the real member names from those types; add a small accessor where the value is only computed inline.

- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXCloudOffTests` — Expected: FAIL.

- [ ] **Step 3: Make the changes listed under Files.**

- [ ] **Step 4: Run the tests** — Expected: PASS. Build `--tag w1`, launch, and confirm by eye: no Cloud menu, no CloudWelcome window, no account/Pro in the sidebar footer, ⌘Y does nothing.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): switch off cloud, billing and account UI; park device mirroring behind remoteMachines"
```

### Task 5B: SSH remote helper built by ShellX (`shellx-remote`)

**Files (fork):**
- Modify: `daemon/remote` (Go): runtime names `~/.cmux/daemon/…` → `~/.shellx/daemon/…`, socket dir `/tmp/cmuxd-remote-<uid>/` → `/tmp/shellx-remote-<uid>/`, busybox argv[0] name `cmux` → `shellx`, binary name `cmuxd-remote` → `shellx-remote`
- Modify: `Packages/macOS/CmuxRemoteSession/Sources/CmuxRemoteSession/Session/RemoteSessionCoordinator+Bootstrap.swift` (binary/dir names; keep the dev-only fallback `CMUX_REMOTE_DAEMON_ALLOW_LOCAL_BUILD=1` + `CMUX_REMOTE_DAEMON_BINARY`, and confirm Release builds ignore it), `scripts/verify_remote_daemon_release.py` (asset names, `releaseURL`/download base `https://download.shellx.pro/desktop/shellx-remote/<version>/`; manifest key `CMUXRemoteDaemonManifestJSON` unchanged)
- Create: `scripts/shellx/build_remote_daemon.sh` (Go cross-build for `darwin/arm64`, `darwin/amd64`, `linux/arm64`, `linux/amd64` into `dist/shellx-remote/<version>/` + `checksums.txt`; uploading to download.shellx.pro is Wave 3 and needs the user's OK)
- Test: `daemon/remote` Go tests, `tests/test_shellx_remote_daemon.py`

**Interfaces:**
- Consumes: Task 3 client-side names (`~/.shellx/bin/shellx` in `RemoteInteractiveShellBootstrapBuilder`).
- Produces: `scripts/shellx/build_remote_daemon.sh <version>` (Wave 3's release pipeline calls it); Task 10 tests SSH sections with `CMUX_REMOTE_DAEMON_ALLOW_LOCAL_BUILD=1 CMUX_REMOTE_DAEMON_BINARY=dist/shellx-remote/<version>/shellx-remote-<os>-<arch>` on a tagged Debug build.

- [ ] **Step 1: Install Go** at the version in `daemon/remote/go.mod` (not installed on this Mac yet); `go version` matches.

- [ ] **Step 2: Write the failing tests**

```python
def test_manifest_points_to_shellx_download_host():
    src = read("scripts/verify_remote_daemon_release.py")
    assert "download.shellx.pro/desktop/shellx-remote" in src
    assert "github.com/manaflow-ai" not in src
def test_no_cmux_runtime_names_in_go_daemon():
    assert offenders(r"\.cmux/|cmuxd-remote-|/tmp/cmuxd", roots=["daemon/remote"], allow=[]) == []
```

Update the existing Go tests that assert the old paths so they assert the new ones (they fail first).

- [ ] **Step 3: Run** `python3 -m pytest tests/test_shellx_remote_daemon.py -q` and `cd daemon/remote && go test ./...` — Expected: FAIL.

- [ ] **Step 4: Make the renames, write `build_remote_daemon.sh`.**

- [ ] **Step 5: Run the tests** — Expected: PASS. `scripts/shellx/build_remote_daemon.sh 0.1.0` produces four binaries and `checksums.txt`. With the dev fallback env vars, a tagged Debug build opens an SSH workspace to a test host (any Linux VM the user names, or `localhost` with Remote Login on) and the remote side shows `~/.shellx/daemon/`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(shellx): shellx-remote SSH helper built by ShellX, served from download.shellx.pro"
```

### Task 6: ShellX name in the UI, CLI help and About

**Files (fork):**
- Create: `scripts/shellx/rebrand_strings.py`
- Modify: `Resources/Localizable.xcstrings`, `Resources/InfoPlist.xcstrings`, `Resources/Info.plist:120-174`, `ConfigPackErrors.xcstrings`, the 10 package catalogs, and Swift `defaultValue:` literals (about 796) — via the script
- Modify: menus `Sources/cmuxApp.swift:528-575` ("About ShellX", "Quit ShellX", "Open shellx.json", "Make ShellX the Default Terminal")
- Modify: `Sources/App/About/AboutPanelView.swift:10-55`, `Sources/AboutLicenseContent.swift:9,33`
- Modify: CLI usage/help text in `CLI/cmux.swift` and `CLI/CMUXCLI+*.swift` where the program name is printed
- Modify: accent-color setting label "cmux" → "ShellX" (`CmuxAccentColor` mode display text)
- Test: `tests/test_shellx_branding.py`, `cmuxTests/ShellXAboutTests.swift`

**Interfaces:**
- Consumes: `ShellXBrand`.
- Produces: `python3 scripts/shellx/rebrand_strings.py [--check]` — rules in this order: `` `cmux `` → `` `shellx `` (command in code spans), `cmux.json` → `shellx.json`, `~/.config/cmux` → `~/.config/shellx`, `.cmux/` → `.shellx/`, whole word `cmux` → `ShellX`; never touches catalog keys, `CMUX_` names or lines listed in its `PRESERVE` set (attribution strings). `--check` exits 1 if a change would be made. Wave 2+ reruns it after upstream merges.
- `AboutLicenseContent.attributions: [Attribution]` where `struct Attribution { let name: String; let license: String; let url: URL? }`.

- [ ] **Step 1: Write the failing tests**

```python
def test_no_cmux_in_english_ui_strings():
    cat = json.load(open("Resources/Localizable.xcstrings"))
    hits = [k for k, v in cat["strings"].items()
            if re.search(r"\bcmux\b", en_value(v) or "", re.I) and k not in PRESERVE_KEYS]
    assert hits == []

def test_rebrand_script_is_idempotent():
    assert subprocess.run([sys.executable, "scripts/shellx/rebrand_strings.py", "--check"]).returncode == 0
```

```swift
@Test func aboutCreditsUpstreamAndAssets() {
  let names = AboutLicenseContent.attributions.map(\.name)
  #expect(names.contains("cmux (Manaflow, Inc.)"))
  #expect(names.contains("Ghostty"))
  #expect(names.contains("coolicons by Kryston Schwarze"))
  #expect(names.contains("Space Grotesk"))
  #expect(AboutLicenseContent.sourceCodeURL == ShellXBrand.sourceCodeURL)
}
```

- [ ] **Step 2: Run** both tests — Expected: FAIL.

- [ ] **Step 3: Write `rebrand_strings.py`, run it, and make the About/menu/CLI edits.** About shows the logo (Task 9 asset; use a placeholder until then), "ShellX", version, "GPL-3.0-or-later — source: github.com/lephus/shellx-pro", and the attribution list with licenses (cmux: GPL-3.0-or-later; Ghostty: MIT; coolicons: CC BY 4.0; Space Grotesk: OFL-1.1).

- [ ] **Step 4: Run** the new tests plus the existing catalog tests (`python3 -m pytest tests/test_localizable_xcstrings_structure.py tests/test_localization_defaults.py tests/test_lint_xcstrings.py -q`, `python3 scripts/localization_catalog.py check`) — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): ShellX name across UI strings, menus, CLI help and About with attributions"
```

### Task 7: ShellX palette, dark-only, terminal defaults, Space Grotesk

**Files (fork):**
- Modify: `Packages/macOS/CmuxFoundation/Sources/CmuxFoundation/Color/CmuxAccentColor.swift:16` (default "cmux" mode color = `ShellXPalette.primary`)
- Modify: `Packages/macOS/CmuxAppKitSupportUI/.../WindowChrome/Sidebar/` `WindowChromeSidebarTintDefaults` (default = `ShellXPalette.panel`, opacity 1.0)
- Modify: `Sources/Sidebar/SidebarAppearanceSupport.swift:167,306,345` (badge = primary; selection = `raise`), `Cells/SidebarWorkspaceRowSupportViews.swift:10` `SidebarRowPalette` (text/textHi/muted)
- Modify: `Sources/Panels/Panel.swift:134` `WorkspaceAttentionFlashAccent.strokeColor` and the notification ring in `Sources/GhosttyTerminalView.swift` (~10601) → `primaryLine`, 1 px
- Modify: `Sources/Sidebar/SidebarCompactStatusGlyph.swift:295` `color()` → error=`error`, needsInput=`primary`, running/subagents/pending=`running`, unseen=`done`, others=`muted`
- Modify: `TerminalAdaptiveDefaultThemeSettings.swift` (built-in default only: background `bg`, cursor `primary`, foreground `text`, ANSI 16 tuned to the palette — record the 16 values in a comment table)
- Modify: app startup (`AppDelegate`) — force `NSApp.appearance = NSAppearance(named: .darkAqua)`; hide the appearance (light/dark/system) setting
- Create: `Resources/Fonts/SpaceGrotesk[wght].ttf` (from `https://github.com/google/fonts/tree/main/ofl/spacegrotesk`, OFL; verify the license file ships beside it) and set `ATSApplicationFontsPath = Fonts` in `Resources/Info.plist`
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXFonts.swift` — `public enum ShellXFonts { public static func display(size: CGFloat, weight: Font.Weight = .bold) -> Font }` ("Space Grotesk", falls back to system if missing)
- Test: `cmuxTests/ShellXThemeTests.swift`

**Interfaces:**
- Consumes: `ShellXPalette`.
- Produces: `ShellXFonts.display(size:weight:)` for the sidebar wordmark (Task 10).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func accentDefaultsToShellXPrimary() { #expect(CmuxAccentColor.default.resolvedHex == "#60a5fa") }
@Test func statusGlyphColors() {
  #expect(SidebarCompactStatusGlyph.color(for: .needsInput).hex == "#60a5fa")
  #expect(SidebarCompactStatusGlyph.color(for: .running).hex == "#e8c468")
  #expect(SidebarCompactStatusGlyph.color(for: .unseen).hex == "#6fd49a")
  #expect(SidebarCompactStatusGlyph.color(for: .error).hex == "#e88a8a")
}
@Test func defaultTerminalThemeUsesPalette() {
  let t = TerminalAdaptiveDefaultThemeSettings.resolve(userConfig: .empty)
  #expect(t.background.hex == "#0b0716" && t.cursor.hex == "#60a5fa")
}
@Test func userGhosttyThemeWins() {   // Review Focus 2
  let t = TerminalAdaptiveDefaultThemeSettings.resolve(userConfig: .init(background: "#ffffff"))
  #expect(t.background.hex == "#ffffff")
}
@Test func appIsDarkOnly() { #expect(ShellXAppearance.forcedAppearanceName == .darkAqua) }
```

Map these onto the real resolver/accessor names; add `hex` helpers on `NSColor` in the test target if needed.

- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXThemeTests` — Expected: FAIL.

- [ ] **Step 3: Make the changes listed under Files.** While there, replace any gradient used on a button or row background with the flat token (Global Constraints); leave gradients that are content fades (e.g. text overflow masks).

- [ ] **Step 4: Run the tests** — Expected: PASS. Build `--tag w1`, launch, and compare by eye against `docs/superpowers/design/2026-10-18-native-desktop/huong-d-mockup.html` (shellx repo): background, sidebar, selection, ring and pills use the palette.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): ShellX palette, dark-only appearance, terminal defaults and Space Grotesk"
```

### Task 8: coolicons everywhere

**Files (fork):**
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/Resources/Coolicons.xcassets/` (all 442 coolicons v4.1 SVGs from the `krystonschwarze/coolicons` v4.1 release, one imageset each named like `Terminal`, `Bell_Ring`, `Window_Sidebar`; `"preserves-vector-representation": true`, `"template-rendering-intent": "template"`)
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/Resources/icon-map.json` (`{ "<sf.symbol.name>": "<Coolicon_Name>" }` for every literal symbol the app uses)
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXIcon.swift`
- Create: `scripts/shellx/import_coolicons.py` (builds the asset catalog from the release zip) and `scripts/shellx/icon_codemod.py`
- Modify: about 670 call sites — `Image(systemName:)` (~470), `systemImage:` labels (~153), `NSImage(systemSymbolName:)` (~46) — via the codemod; plus `RenderableSystemSymbol`, `SidebarCompactStatusGlyph` symbol names, `RightSidebarMode` icons, `CmuxButtonIcon`
- Modify: the `Package.swift` of every package whose sources the codemod touched (add the `ShellXBrand` dependency)
- Test: `Packages/Shared/ShellXBrand/Tests/ShellXBrandTests/ShellXIconTests.swift`, `tests/test_shellx_icons.py`

**Interfaces:**
- Consumes: `ShellXBrand` package.
- Produces:
  - `public enum ShellXIcon { static func image(_ sfSymbol: String) -> Image; static func nsImage(_ sfSymbol: String, accessibilityDescription: String?) -> NSImage?; static func cooliconName(for sfSymbol: String) -> String?; static func image(coolicon: String) -> Image; static func nsImage(coolicon: String) -> NSImage? }`. `image(_:)` returns the mapped coolicon as a template image, or `Image(systemName:)` when the name is unmapped (user-supplied names).
  - `ShellXLabel(_ title: LocalizedStringKey, icon: String)` view replacing `Label(_, systemImage:)`.
  - Coolicon names used by later tasks: `Laptop`, `Desktop`, `Data`, `Mobile`, `Link`, `Terminal`, `Bell_Ring`, `Add_Plus`, `Search_Magnifying_Glass`, `Settings`, `Circle_Check`, `Shield_Check`, `Users`, `Window_Sidebar`, `More_Horizontal`, `Qr_Code`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func mappedSymbolUsesCoolicon() { #expect(ShellXIcon.cooliconName(for: "terminal") == "Terminal") }
@Test func everyMappedCooliconExists() {
  for (_, name) in ShellXIcon.map { #expect(ShellXIcon.nsImage(coolicon: name) != nil, "\(name)") }
}
@Test func unmappedUserSymbolFallsBack() {   // Review Focus 3
  #expect(ShellXIcon.cooliconName(for: "figure.surfing") == nil)
  #expect(ShellXIcon.nsImage("figure.surfing", accessibilityDescription: nil) != nil)
}
```

```python
def test_no_direct_sf_symbol_calls_outside_shellxicon():
    pat = r"Image\(systemName:|systemImage:|NSImage\(systemSymbolName:"
    assert offenders(pat, roots=["Sources", "Packages/macOS", "Packages/Shared"], allow=DYNAMIC_ALLOWLIST) == []
def test_every_literal_symbol_is_mapped():
    used = literal_symbols_before_codemod()   # read from scripts/shellx/icon_codemod.py --list (frozen snapshot file)
    mapping = json.load(open(MAP_PATH))
    assert sorted(set(used) - set(mapping)) == []
```

`DYNAMIC_ALLOWLIST` = `ShellXIcon.swift` and the call sites whose symbol name comes from user config (custom commands, workspace group `iconSymbol`, `sidebar.compactStatusIcons`), each with reason.

- [ ] **Step 2: Run** `swift test --package-path Packages/Shared/ShellXBrand` and `python3 -m pytest tests/test_shellx_icons.py -q` — Expected: FAIL.

- [ ] **Step 3: Import the icons, write the map, implement `ShellXIcon`, run the codemod.** For each SF symbol pick the nearest coolicon by meaning; where coolicons has none, pick the closest and list it in `scripts/shellx/icon-substitutions.md` (spec §15). Agent logos in `Assets.xcassets/AgentIcons/*` are brand logos and stay.

- [ ] **Step 4: Run the tests** — Expected: PASS. Build `--tag w1` — Expected: builds; spot-check the sidebar, settings, command palette, browser panel and file preview: no SF Symbols visible.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): replace SF Symbols with coolicons v4.1 via ShellXIcon"
```

### Task 9: App icon from the ShellX logo

**Files (fork):**
- Create: `design/shellx-logo.svg` (copy of shellx repo `web/public/favicon.svg`)
- Create: `scripts/shellx/gen_app_icons.sh` (`rsvg-convert` → every size of `Assets.xcassets/AppIcon.appiconset` light and `_dark`, `AppIcon-Debug.appiconset` with a "DEV" band drawn by `magick`, `AppIconLight`/`AppIconDark` imagesets, and `ShellXLogo` imageset for About/sidebar)
- Modify: `Assets.xcassets/AppIcon.appiconset/*`, `AppIcon-Debug.appiconset/*`, `AppIconLight`, `AppIconDark`, new `ShellXLogo.imageset`
- Test: `tests/test_shellx_app_icon.py`

**Interfaces:**
- Produces: image asset `ShellXLogo` (vector PDF or 1024 px PNG) used by About (Task 6) and the sidebar header (Task 10).

- [ ] **Step 1: Write the failing test**

```python
def test_app_icon_sizes():
    contents = json.load(open("Assets.xcassets/AppIcon.appiconset/Contents.json"))
    for img in contents["images"]:
        w, h = png_size(f"Assets.xcassets/AppIcon.appiconset/{img['filename']}")
        side = int(float(img["size"].split("x")[0]) * int(img["scale"][0]))
        assert (w, h) == (side, side), img["filename"]
def test_logo_source_matches_web():
    assert sha256("design/shellx-logo.svg") == EXPECTED_SHA256   # sha of shellx web/public/favicon.svg at copy time
```

- [ ] **Step 2: Run** — Expected: FAIL (old icons or missing logo).

- [ ] **Step 3: Write and run `gen_app_icons.sh`.**

- [ ] **Step 4: Run the test** — Expected: PASS. Build `--tag w1`; the Dock shows the "> <" logo.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): app icon and logo assets from the shellx.pro logo"
```

### Task 10: Sidebar grouped by machine, status pills, brand header

**Files (fork):**
- Create: `Sources/ShellX/Sidebar/SidebarMachineGrouping.swift` (pure model)
- Create: `Sources/ShellX/Sidebar/SidebarStatusPill.swift` (pure mapping + small AppKit view)
- Create: `Sources/ShellX/Sidebar/SidebarMachineHeaderCellView.swift` (AppKit cell, modelled on `Cells/SidebarGroupHeaderRowView.swift:12`)
- Create: `Sources/ShellX/Sidebar/SidebarBrandHeaderView.swift` (logo + "ShellX" in `ShellXFonts.display(size: 14)`, then "YOUR MACHINES" label with an `Add_Plus` button)
- Modify: `Sources/SidebarWorkspaceRenderItem.swift:13` (add `case machineHeader(SidebarMachineHeaderModel)`)
- Modify: `Sources/ContentView.swift:11745-11936` `WorkspaceListRenderContext` (build machine sections, then reuse the existing `renderItems(...)` per section)
- Modify: `Sources/Sidebar/AppKitList/SidebarWorkspaceTableController.swift` (~1099 `heightOfRow`, ~1130 cell creation) and `SidebarWorkspaceTableRowHeightCalculator.swift` (header row height)
- Modify: `Cells/SidebarWorkspaceRowCellView.swift:892` (show the pill next to the compact glyph)
- Modify: `Sources/FeatureFlags.swift:68` (`isAppKitSidebarListEnabled` always `true`; the legacy SwiftUI list is not extended)
- Test: `cmuxTests/SidebarMachineGroupingTests.swift`, `cmuxTests/SidebarStatusPillTests.swift`

**Interfaces:**
- Consumes: `ShellXIcon` coolicon names (Task 8), `ShellXPalette` (Task 1), `ShellXFonts` (Task 7), `ShellXLogo` (Task 9).
- Produces (Wave 2 extends these with remote devices):

```swift
enum SidebarMachineKey: Hashable { case local; case ssh(target: String) }      // target = remoteDisplayTarget, e.g. "ubuntu@vm01"
struct LocalMachineInfo: Equatable { let name: String; let isLaptop: Bool; static func current() -> LocalMachineInfo }
struct SidebarMachineInput<ID: Hashable>: Equatable { let workspaceID: ID; let sshTarget: String?; let sshConnected: Bool }
struct SidebarMachineHeaderModel: Equatable { let key: SidebarMachineKey; let title: String; let note: String; let coolicon: String; let isOnline: Bool }
struct SidebarMachineSection<ID: Hashable>: Equatable { let header: SidebarMachineHeaderModel; let workspaceIDs: [ID] }
enum SidebarMachineGrouping {
  static func sections<ID: Hashable>(for inputs: [SidebarMachineInput<ID>], local: LocalMachineInfo) -> [SidebarMachineSection<ID>]
}
enum SidebarStatusPill: Equatable { case waiting, running, done, error
  static func from(_ kind: SidebarCompactStatusGlyph.Kind) -> SidebarStatusPill?
  var title: String   // localized: "waiting"/"running"/"done"/"error"; vi "chờ bạn"/"chạy"/"xong"/"lỗi"
  var color: ShellXColor
}
```

Rules: the local section is always first, even with no workspaces; SSH sections follow in order of first appearance; a user workspace group that spans machines shows its group header inside each machine section with only that machine's rows; `LocalMachineInfo.current()` uses `Host.current().localizedName` and `isLaptop` = `sysctl hw.model` contains `MacBook`. Header: local → title = machine name, note = "this Mac" (vi "máy này"), coolicon `Laptop`/`Desktop`, online = true; SSH → title = target, note = "SSH", coolicon `Data`, online = any of its workspaces connected. Pill mapping: `needsInput` → waiting; `running`, `subagents`, `pending` → running; `unseen` → done; `error` → error; everything else → nil.

- [ ] **Step 1: Write the failing tests**

```swift
let mac = LocalMachineInfo(name: "MacBook Pro", isLaptop: true)
@Test func localFirstThenSSHInOrder() {
  let s = SidebarMachineGrouping.sections(for: [
    .init(workspaceID: 1, sshTarget: "ubuntu@vm01", sshConnected: true),
    .init(workspaceID: 2, sshTarget: nil, sshConnected: false),
    .init(workspaceID: 3, sshTarget: "root@vm02", sshConnected: true)], local: mac)
  #expect(s.map(\.header.key) == [.local, .ssh(target: "ubuntu@vm01"), .ssh(target: "root@vm02")])
  #expect(s[0].workspaceIDs == [2])
  #expect(s[0].header.coolicon == "Laptop" && s[1].header.coolicon == "Data")
}
@Test func localSectionShownWhenEmpty() {
  #expect(SidebarMachineGrouping.sections(for: [SidebarMachineInput<Int>](), local: mac).map(\.header.key) == [.local])
}
@Test func disconnectedHostKeepsRowsAndShowsOffline() {   // Review Focus 4
  let s = SidebarMachineGrouping.sections(for: [.init(workspaceID: 7, sshTarget: "ubuntu@vm01", sshConnected: false)], local: mac)
  #expect(s[1].header.isOnline == false && s[1].workspaceIDs == [7])
}
@Test func differentUsersSameHostAreDifferentMachines() {   // Review Focus 4
  let s = SidebarMachineGrouping.sections(for: [
    .init(workspaceID: 1, sshTarget: "ubuntu@vm01", sshConnected: true),
    .init(workspaceID: 2, sshTarget: "root@vm01", sshConnected: true)], local: mac)
  #expect(s.count == 3)
}
@Test func pillMapping() {
  #expect(SidebarStatusPill.from(.needsInput) == .waiting)
  #expect(SidebarStatusPill.from(.subagents) == .running)
  #expect(SidebarStatusPill.from(.unseen) == .done)
  #expect(SidebarStatusPill.from(.idle) == nil)
  #expect(SidebarStatusPill.running.color == ShellXPalette.running)
}
@Test func headerAndRowHeightsIgnoreTextLength() {   // Review Focus 5
  let short = SidebarWorkspaceTableRowHeightCalculator.height(forMachineHeaderTitle: "Mac")
  let long  = SidebarWorkspaceTableRowHeightCalculator.height(forMachineHeaderTitle: String(repeating: "Máy tính văn phòng tầng 3 ", count: 6))
  #expect(short == long)
}
```

- [ ] **Step 2: Run** `scripts/shellx/test-app.sh SidebarMachineGroupingTests SidebarStatusPillTests` — Expected: FAIL.

- [ ] **Step 3: Implement the models, then wire the render items, header cell, pill and brand header.** Labels truncate with `.byTruncatingTail`. New strings: `sidebar.machines.title` ("YOUR MACHINES"), `sidebar.machine.thisMac` ("this Mac"), `sidebar.machine.ssh` ("SSH"), `sidebar.pill.waiting|running|done|error`, `sidebar.machines.add.ssh` ("Add a machine over SSH…") — the `Add_Plus` button opens the existing SSH workspace flow.

- [ ] **Step 4: Run the tests** — Expected: PASS. Build `--tag w1`, open two local workspaces and one SSH workspace; compare with the mockup: brand header, "YOUR MACHINES", a "MacBook … · this Mac" section, an SSH section with `Data` icon, pills colored per palette.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): sidebar grouped by machine with status pills and ShellX brand header"
```

### Task 11: Title bar — sidebar toggle, search, bell, settings

**Files (fork):**
- Create: `Sources/ShellX/Titlebar/ShellXTitlebarAccessory.swift` (AppKit accessory hosting a SwiftUI view)
- Create: `Sources/ShellX/Titlebar/ShellXTitlebarModel.swift` (pure)
- Modify: the window setup that installs titlebar accessories (next to `Update/UpdateTitlebarAccessory.swift`)
- Test: `cmuxTests/ShellXTitlebarModelTests.swift`

**Interfaces:**
- Consumes: existing actions — toggle sidebar (⌘B), open command palette (⌘K / existing palette action), open notifications panel, open settings; `SidebarUnreadModel` unread count; `ShellXIcon`; `ShellXPalette`.
- Produces: `struct ShellXTitlebarModel: Equatable { let unreadCount: Int; var badgeText: String? /* nil for 0, "1"…"9", "9+" */; let searchPlaceholder: String /* "Search sessions, machines, commands…" */ }`.

- [ ] **Step 1: Write the failing test**

```swift
@Test func badgeText() {
  #expect(ShellXTitlebarModel(unreadCount: 0).badgeText == nil)
  #expect(ShellXTitlebarModel(unreadCount: 3).badgeText == "3")
  #expect(ShellXTitlebarModel(unreadCount: 12).badgeText == "9+")
}
```

- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXTitlebarModelTests` — Expected: FAIL.

- [ ] **Step 3: Implement.** Layout per spec §7.1: `Window_Sidebar` button; centered search field look-alike (click or ⌘K opens the palette; `Search_Magnifying_Glass` icon; `⌘K` key cap); `Bell_Ring` with a primary badge; `Settings`. Flat colors only. Keep existing titlebar items that still apply (update accessory).

- [ ] **Step 4: Run the test** — Expected: PASS. Build and check by eye; each button triggers its action.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): ShellX title bar with search, notifications bell and settings"
```

### Task 12: Vietnamese

**Files (fork):**
- Modify: `cmux.xcodeproj/project.pbxproj:14328` (`knownRegions` += `vi`)
- Modify: `scripts/localization_catalog.py:18` (`LOCALES` += `"vi"`)
- Modify: `Resources/Localizable.xcstrings` (~8,400 keys), `InfoPlist.xcstrings` (29), `ConfigPackErrors.xcstrings`, the 10 package catalogs — add `vi`
- Create: `scripts/shellx/l10n/vi-glossary.md`, `scripts/shellx/l10n/export_missing.py`, `scripts/shellx/l10n/import_translations.py`
- Test: existing localization tests + `tests/test_shellx_vi.py`

**Interfaces:**
- Consumes: all strings added in Tasks 6, 10, 11.
- Produces: `vi` complete in every catalog; `AppLanguage.vi` (already in `Packages/macOS/CmuxSettings/.../AppLanguage.swift:6`) now shows translated UI.

Glossary (binding): workspace → "phiên"; pane → "khung"; split → "chia khung"; tab/surface → "tab"; sidebar → "thanh bên"; command palette → "bảng lệnh"; notification → "thông báo"; agent → "agent"; browser → "trình duyệt"; machine → "máy"; settings → "Cài đặt"; terminal → "terminal"; keep `ShellX`, command names, file paths, key caps and `%@`/`%lld` placeholders verbatim and in the same order.

- [ ] **Step 1: Write the failing test**

```python
def test_vi_is_complete_and_placeholders_match():
    for path in CATALOGS:
        cat = json.load(open(path))
        for key, entry in cat["strings"].items():
            if entry.get("shouldTranslate") is False: continue
            vi = value(entry, "vi"); en = value(entry, "en")
            assert vi, f"{path}:{key} missing vi"
            assert placeholders(vi) == placeholders(en), f"{path}:{key}"
def test_key_shellx_strings_read_naturally():
    assert value_of("sidebar.pill.waiting", "vi") == "chờ bạn"
    assert value_of("sidebar.machine.thisMac", "vi") == "máy này"
```

- [ ] **Step 2: Run** `python3 -m pytest tests/test_shellx_vi.py -q` — Expected: FAIL.

- [ ] **Step 3: Translate in batches.** `export_missing.py` writes batches of ≤ 300 keys (key, English, comment) to JSON; translate each batch following the glossary (parallel agents are fine; each batch is independent); `import_translations.py` merges them, refusing any entry whose placeholders differ. Then read through the ~300 most visible strings (menus, sidebar, settings top level, notifications, title bar, About) as a Vietnamese user and fix awkward wording.

- [ ] **Step 4: Run** `python3 -m pytest tests/test_shellx_vi.py tests/test_localizable_xcstrings_structure.py tests/test_localization_catalog.py tests/test_localization_defaults.py tests/test_lint_xcstrings.py -q` and `python3 scripts/localization_catalog.py check` — Expected: PASS. Switch the app language to Tiếng Việt and check the sidebar, menus and settings.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): Vietnamese localization"
```

### Task 13: Wave 1 close-out — speed, network audit, upstream drill, merge

**Files:**
- Create (fork): `scripts/shellx/audit_network.py`
- Modify (shellx repo): `docs/superpowers/ledgers/native-desktop.md`

**Interfaces:**
- Consumes: `perf_mac.py` and the baseline JSON (Wave 0 Task 3), `ShellXNetworkPolicy.forbiddenHosts` (Task 4), bundled CLI `shellx` (Task 3).
- Produces: `python3 scripts/shellx/audit_network.py --app <path.app> --seconds 120 --out <file.json>` — launches the app, drives it through the CLI (new workspace, 3 splits, run `ls`, open settings), samples `lsof -nP -i -a -p <pid>` for every process in the bundle once per second, and writes the set of remote endpoints; exits 1 if any endpoint is not loopback.

- [ ] **Step 1: Speed gate**

```bash
./scripts/reload.sh --tag w1-perf --release --build-only
python3 scripts/shellx/perf/perf_mac.py --app "<ShellX DEV w1-perf.app>" --cli "<app>/Contents/Resources/bin/shellx" --runs 5 --out /tmp/perf-shellx-w1.json
python3 scripts/shellx/perf/perf_mac.py compare <baseline-from-ledger>.json /tmp/perf-shellx-w1.json --max-regression 0.10
```

Expected: exit 0. Ask the user for one Typometer run on the ShellX build. A regression over 10 % blocks the merge: find the cause before continuing.

- [ ] **Step 1b: Smoothness (spec §2.2 criterion 3)**

Run the same hitch scenario as the W0 baseline (`perf_mac.py hitches`, see Wave 0 Task 3) on the ShellX build. Expected: hitch time per second ≤ 110 % of cmux's, and no single hitch over one frame at the display's refresh rate during the sidebar toggles.

- [ ] **Step 1c: Vietnamese typing on Mac (spec §5)**

In a ShellX terminal, type `tieengs Vieetj` with the macOS built-in Vietnamese Telex input source and with EVKey (or Unikey for Mac): `tiếng Việt` appears; the preedit is visible while composing; backspace inside a composition removes one character. Record the result in the ledger; a failure blocks the merge.

- [ ] **Step 2: Network audit**

Run `audit_network.py` on the same build. Expected: exit 0, no non-loopback endpoint (Wave 1 has no ShellX network service yet; don't open a browser pane during the audit).

- [ ] **Step 3: Upstream merge drill (spec §13)**

```bash
git switch -c shellx/merge-drill && git fetch upstream
git merge --no-commit --no-ff upstream/main; git diff --name-only --diff-filter=U | wc -l
git merge --abort; git switch shellx/w1-mac-local; git branch -D shellx/merge-drill
```

Record the conflict count and the conflicting files in the ledger. Then `python3 scripts/shellx/rebrand_strings.py --check` documents how much a real merge would need to re-brand.

- [ ] **Step 4: Full test pass**

```bash
python3 -m pytest tests/test_shellx_*.py -q
swift test --package-path Packages/Shared/ShellXBrand
./scripts/test-unit.sh test 2>&1 | tail -20
```

Expected: ShellX tests all pass; `test-unit.sh` failures are only the upstream baseline failures listed in the W0 ledger.

- [ ] **Step 5: Merge locally and write the ledger**

```bash
git switch main && git merge --no-ff shellx/w1-mac-local -m "Merge W1: ShellX for Mac, local"
```

Ledger section `## W1 summary` (shellx repo): perf JSON vs baseline, audit result, merge-drill numbers, excluded helpers, icon substitutions, open issues. Commit the ledger. Do not push either repo; tell the user W1 is merged locally and ask before any push.
