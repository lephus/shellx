#!/usr/bin/env python3
"""ShellX never phones home to Manaflow or any third party.

No Sentry or PostHog SDK is linked or imported, telemetry and the remote
feature-flag fetch are off, feedback opens a mail draft to ShellX, the Help
menu points at ShellX, and no reachable source names a forbidden host.

The forbidden hosts are parsed from `ShellXNetworkPolicy.forbiddenHosts`
(ShellXBrand), so this guard and the Swift policy cannot drift apart.
"""

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from shellx_guard import ROOT, offenders, read  # noqa: E402


POLICY_SWIFT = "Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXNetworkPolicy.swift"

# The plan's list (W1 Task 4). The Swift policy must hold exactly these.
EXPECTED_FORBIDDEN_HOSTS = [
    "cmux.com",
    "cmux.dev",
    "manaflow",
    "stack-auth.com",
    "sentry.io",
    "posthog.com",
    "axiom.co",
    "coderouter.dev",
    "workers.dev",
    "relay.cmux.dev",
]


def parse_forbidden_hosts():
    """`ShellXNetworkPolicy.forbiddenHosts` as written in the Swift source."""
    path = ROOT / POLICY_SWIFT
    if not path.exists():
        return []
    match = re.search(r"forbiddenHosts\s*(?::\s*\[String\])?\s*=\s*\[(.*?)\]", read(POLICY_SWIFT), re.S)
    if not match:
        return []
    return re.findall(r'"([^"]+)"', match.group(1))


FORBIDDEN_HOSTS = parse_forbidden_hosts()  # mirrors ShellXNetworkPolicy.forbiddenHosts

# Code ShellX ships. Packages/iOS is upstream's iPhone app, which ShellX does
# not build; the SDK-import check below still covers it.
HOST_ROOTS = ["Sources", "CLI", "Packages/macOS", "Packages/Shared", "Resources"]

# Reasons shared by several allowlist entries.
TASK5_GATED = ("gated in Task 5 by ShellXFeatures.cloud == false: no menu, palette, footer or shortcut entry, "
               "HostAccountFlow sign-in and billing refuse first, socket auth.*/vm.*/remotes.*/aiAccounts.* "
               "and the CLI verbs are refused (tests/test_shellx_cloud_off.py)")
TASK5_CODEROUTER = ("gated in Task 5 by ShellXFeatures.codeRouter == false: socket coderouter.* refused, "
                    "no handoff service is created and mint() refuses first (tests/test_shellx_cloud_off.py)")
TASK5_PARKED = ("parked behind ShellXFeatures.remoteMachines == false (Task 5); "
                "Wave 2 swaps the transport before flipping it")
NOT_A_HOST = "email domain comparison, not a network host"

# Whole files whose forbidden-host code runs only behind a Cloud, account,
# billing or pairing entry point that Task 5 switches off. Each reason names
# what the host is for and which gate keeps it unreachable. Wave 2 removes
# entries as it replaces the transports.
CLOUD_ALLOWLIST = [
    ("Packages/Shared/CmuxAuthRuntime/Sources/CmuxAuthRuntime/Client/StackAuthClient.swift",
     "Stack Auth API base, used only by sign-in (palette, footer, `cmux auth login` -> auth.*); " + TASK5_GATED),
    ("Packages/Shared/CmuxAuthRuntime/Sources/CmuxAuthRuntime/Coordinator/AuthConfig.swift",
     "sign-in callback URL on cmux.com, used only by sign-in; " + TASK5_GATED),
    ("Packages/macOS/CmuxCloud/Sources/CmuxCloud/Environment/AuthEnvironment.swift",
     "cmux.com and Stack Auth endpoints for sign-in, Cloud and billing; " + TASK5_GATED),
    ("Packages/macOS/CmuxCloud/Sources/CmuxCloud/VMClient/VMClient.swift",
     "Cloud VM API pricing links in error text (Cloud UI, `cmux vm|cloud` -> vm.*); " + TASK5_GATED),
    ("Resources/en.lproj/cloud-agent-skill.md",
     "Cloud agent skill text naming cmux.com/pricing for the agent to report (never fetched); "
     "opened from the Machines panel and socket vm.cloud_agent_open, " + TASK5_GATED),
    ("Sources/Cloud/CloudSecurityExplainer.swift",
     "learn-more links shown only in the Cloud machine UI; " + TASK5_GATED),
    ("Sources/Cloud/CodeRouterHandoffClient.swift",
     "CodeRouter handoff, needs a Stack Auth session (sign-in and the coderouter socket handlers); "
     + TASK5_CODEROUTER),
    ("Sources/Cloud/PresenceSettings.swift",
     "presence heartbeat service (opt-in with phone pairing); " + TASK5_PARKED),
    ("Sources/Mobile/MobileHostV2Installation.swift",
     "phone-host v2 relay origins (opt-in pairing); MobileHostService listening " + TASK5_PARKED),
    ("Sources/Mobile/Pairing/MobilePairingView.swift",
     "link to cmux's iPhone app in the pairing view; device pairing " + TASK5_PARKED),
    ("Sources/PricingPlansScreen.swift",
     "Enterprise mailto in the Pro pricing screen; billing entry points are unreachable after Task 5, "
     + TASK5_GATED),
]

# Whole files that name a forbidden host without contacting it.
NOT_A_HOST_ALLOWLIST = [
    ("Packages/macOS/CmuxCloud/Sources/CmuxCloud/VMClient/VMTunnelManager.swift",
     "host string comparison that labels a Cloud tunnel as cmux's, not a network request"),
    ("Packages/macOS/CmuxFeedback/Sources/CmuxFeedback/DogfoodSink/DogfoodFeedbackService.swift", NOT_A_HOST),
]

# Build-time inputs: SwiftPM, Xcode or a dev script reads these while
# building; the app never contacts the host. Re-hosting is release work (Wave 3).
IROH_FFI_PIN = ("build-time: SwiftPM fetches the iroh-ffi package from github.com/manaflow-ai while "
                "resolving packages; the app never contacts it")
BUILD_TIME_ALLOWLIST = [
    ("Packages/Shared/CmuxTerminalClient/Package.swift",
     "build-time: SwiftPM downloads the prebuilt cmux-terminal-client xcframework; the app never contacts it"),
    ("Packages/Shared/CmuxIrohTransport/Package.swift", IROH_FFI_PIN),
    ("Packages/Shared/CmuxIrohTransport/Package.resolved", IROH_FFI_PIN),
    ("Packages/Shared/CmuxIrxTransport/Package.swift", IROH_FFI_PIN),
    ("Packages/Shared/CmuxIrxTransport/Package.resolved", IROH_FFI_PIN),
    ("Resources/coderouter-cli.json",
     "build-time manifest read only by scripts/install-coderouter-client.sh, which no ShellX build "
     "runs (reload.sh skips it); not in any Xcode resources phase, never bundled"),
]

# The Xcode project and the workspace pins live outside HOST_ROOTS. They may
# name a forbidden host only through these exact literals.
PROJECT_PIN_FILES = [
    "cmux.xcodeproj/project.pbxproj",
    "cmux.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
]
BUILD_TIME_PROJECT_LITERALS = [
    ("cmux.xcodeproj/project.pbxproj", '"https://github.com/manaflow-ai/iroh-ffi.git"',
     "build-time: XCRemoteSwiftPackageReference Xcode resolves for CmuxIrohTransport; the app never contacts it"),
    ("cmux.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
     '"https://github.com/manaflow-ai/iroh-ffi.git"', IROH_FFI_PIN),
]

ALL_FILE_ALLOWLISTS = CLOUD_ALLOWLIST + NOT_A_HOST_ALLOWLIST + BUILD_TIME_ALLOWLIST

# Literals that name a forbidden host but never reach it. They are removed from
# a line before the host scan; the rest of the line is still checked.
NON_NETWORK_LITERALS = [
    ('"ai.manaflow.cmux"',
     "reverse-DNS os_log subsystem, not a host (R3 keeps os_log subsystems)"),
    ('"https://github.com/manaflow-ai/cmux/releases/",',
     "UpdateFeedResolver prefix that classifies a feed URL; never fetched (ShellX's feed is download.shellx.pro)"),
    ('"https://files.cmux.com/stable/",',
     "UpdateFeedResolver prefix that classifies a feed URL; never fetched (ShellX's feed is download.shellx.pro)"),
    ('"https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux-settings.schema.json"',
     "legacy $schema value matched to migrate an old settings file; never fetched"),
    ('"$id": "https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json",',
     "$id inside the embedded config schema (generated from upstream's web/data, not in ShellX); local validation only"),
    ('"default": "https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json",',
     "default of $schema inside the embedded config schema; local validation only, never written or fetched"),
]

# Package test targets never ship in the app; their fixtures use upstream URLs.
SKIPPED_PATH_PARTS = [("/Tests/", "package test targets are not shipped")]
SKIPPED_FILES = [(POLICY_SWIFT, "the forbidden-host list itself")]

SLASH_COMMENT_SUFFIXES = {".swift", ".m", ".mm", ".h", ".c", ".cc", ".cpp", ".js", ".mjs", ".ts", ".tsx", ".go", ".rs", ".zig"}
HASH_COMMENT_SUFFIXES = {"", ".sh", ".bash", ".zsh", ".fish", ".py", ".rb", ".toml", ".yml", ".yaml", ".conf"}


def host_pattern(host):
    # `cmux.com` must not match `cmux.commandPalette…`, nor `cmux.dev` match
    # `cmux.devices…`; a following `-`, `/`, `.` or quote still counts.
    return re.escape(host) + r"(?![A-Za-z0-9_])"


def is_comment(path, line):
    stripped = line.strip()
    suffix = Path(path).suffix
    if suffix in SLASH_COMMENT_SUFFIXES:
        return stripped.startswith(("//", "/*", "*"))
    if suffix in HASH_COMMENT_SUFFIXES:
        return stripped.startswith("#")
    return False


def is_skipped(path):
    return (path.endswith(".xcstrings")
            or any(path == skipped for skipped, _reason in SKIPPED_FILES)
            or any(part in path for part, _reason in SKIPPED_PATH_PARTS))


def reachable_offenders(hosts, roots, allow):
    """`{host: ["path:line", ...]}` for lines that name a host, outside
    comments, package tests and catalogs, after removing NON_NETWORK_LITERALS.
    One walk over the roots serves every host."""
    regexes = {host: re.compile(host_pattern(host)) for host in hosts}
    catalog_allow = [(path, "string catalogs: see test_catalog_strings_naming_forbidden_hosts_are_unused")
                     for path in catalogs()]
    combined = "|".join(host_pattern(host) for host in hosts)
    lines_by_path = {}
    hits = {host: [] for host in hosts}
    for hit in offenders(combined, roots=roots, allow=list(allow) + catalog_allow):
        path, number = hit.rsplit(":", 1)
        if is_skipped(path):
            continue
        if path not in lines_by_path:
            lines_by_path[path] = read(path).splitlines()
        line = lines_by_path[path][int(number) - 1]
        if is_comment(path, line):
            continue
        for literal, _reason in NON_NETWORK_LITERALS:
            line = line.replace(literal, "")
        for host, regex in regexes.items():
            if regex.search(line):
                hits[host].append(hit)
    return hits


def is_comment_hit(hit):
    """Whether the `"path:line"` from offenders() is a comment line."""
    path, number = hit.rsplit(":", 1)
    return is_comment(path, read(path).splitlines()[int(number) - 1])


def code_lines(path):
    """The lines of `path` that are not comments."""
    return [line for line in read(path).splitlines() if not is_comment(path, line)]


def catalogs():
    found = []
    for root in HOST_ROOTS:
        found.extend(sorted((ROOT / root).rglob("*.xcstrings")))
    return [p.relative_to(ROOT).as_posix() for p in found if ".build" not in p.parts]


class ShellXNoPhoneHomeTests(unittest.TestCase):
    # Short failure messages: the sources are far too long to print whole.
    def assertSourceHas(self, path, needle):
        self.assertTrue(needle in read(path), f"{needle!r} missing from {path}")

    def assertSourceLacks(self, path, needle):
        self.assertFalse(needle in read(path), f"{needle!r} still in {path}")

    def assertSourceMatches(self, path, pattern):
        self.assertTrue(re.search(pattern, read(path)), f"/{pattern}/ does not match {path}")

    def test_forbidden_hosts_mirror_swift_policy(self):
        self.assertEqual(FORBIDDEN_HOSTS, EXPECTED_FORBIDDEN_HOSTS)

    def test_no_sentry_or_posthog_packages(self):
        for path in ("cmux.xcodeproj/project.pbxproj",
                     "cmux.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"):
            self.assertSourceLacks(path, "sentry-cocoa")
            self.assertSourceLacks(path, "posthog-ios")
        manifests = offenders(r"sentry-cocoa|posthog-ios|getsentry|PostHog/posthog", roots=["Packages"], allow=[])
        manifests = [h for h in manifests if Path(h.rsplit(":", 1)[0]).name in ("Package.swift", "Package.resolved")]
        self.assertEqual(manifests, [])
        imports = (r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public |internal |package |private |fileprivate )?import\s+"
                   r"(?:(?:struct|class|enum|protocol|func|var|let|typealias)\s+)?(Sentry|PostHog)\b")
        self.assertEqual(offenders(imports, roots=["Sources", "CLI", "Packages"], allow=[]), [])

    def test_no_forbidden_hosts_in_reachable_code(self):
        self.assertTrue(FORBIDDEN_HOSTS, "ShellXNetworkPolicy.forbiddenHosts is missing")
        hits = reachable_offenders(FORBIDDEN_HOSTS, HOST_ROOTS, ALL_FILE_ALLOWLISTS)
        for host in FORBIDDEN_HOSTS:
            self.assertEqual(hits[host], [], host)

    def test_allowlist_entries_are_live_and_reasoned(self):
        pattern = "|".join(host_pattern(h) for h in EXPECTED_FORBIDDEN_HOSTS)
        paths = [path for path, _reason in ALL_FILE_ALLOWLISTS]
        self.assertEqual(len(paths), len(set(paths)), "a file is allowlisted twice")
        for path, reason in ALL_FILE_ALLOWLISTS:
            self.assertGreater(len(reason.split()), 4, f"allowlist reason too vague: {path}")
            self.assertTrue((ROOT / path).is_file(), f"stale allowlist entry: {path}")
            self.assertTrue(re.search(pattern, read(path)), f"allowlisted file no longer names a forbidden host: {path}")
        for path, literal, reason in BUILD_TIME_PROJECT_LITERALS:
            self.assertTrue(reason.startswith("build-time: "), path)
            self.assertIn(literal, read(path), f"stale build-time literal in {path}")

    def test_no_forbidden_hosts_in_xcode_project_or_workspace_pins(self):
        # Outside HOST_ROOTS, so scanned here line by line: only the reasoned
        # build-time literals may name a forbidden host.
        regex = re.compile("|".join(host_pattern(h) for h in EXPECTED_FORBIDDEN_HOSTS))
        hits = []
        for path in PROJECT_PIN_FILES:
            literals = [literal for pin_path, literal, _reason in BUILD_TIME_PROJECT_LITERALS if pin_path == path]
            for number, line in enumerate(read(path).splitlines(), start=1):
                for literal in literals:
                    line = line.replace(literal, "")
                if regex.search(line):
                    hits.append(f"{path}:{number}")
        self.assertEqual(hits, [])

    def test_catalog_strings_naming_forbidden_hosts_are_unused(self):
        # Catalog entries are copy, not code. Upstream keys that still name a
        # forbidden host stay in the catalogs (R8: only edit keys you add), but
        # no reachable code may look them up.
        pattern = re.compile("|".join(host_pattern(h) for h in EXPECTED_FORBIDDEN_HOSTS))
        keys = set()
        for catalog in catalogs():
            for key, entry in json.loads(read(catalog)).get("strings", {}).items():
                if pattern.search(key) or pattern.search(json.dumps(entry, ensure_ascii=False)):
                    keys.add(key)
        self.assertTrue(keys)  # the upstream catalogs do carry such keys
        allowed = {path for path, _reason in CLOUD_ALLOWLIST + NOT_A_HOST_ALLOWLIST}
        literal = re.compile(r'"([^"\\\s]+)"')
        hits = []
        for root in ["Sources", "CLI", "Packages/macOS", "Packages/Shared"]:
            for path in sorted((ROOT / root).rglob("*.swift")):
                rel = path.relative_to(ROOT).as_posix()
                if ".build" in path.parts or rel in allowed or is_skipped(rel):
                    continue
                for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
                    if any(m in keys for m in literal.findall(line)) and not is_comment(rel, line):
                        hits.append(f"{rel}:{number}")
        self.assertEqual(hits, [])

    def test_telemetry_and_remote_flag_fetch_are_off(self):
        self.assertSourceMatches("Sources/TelemetrySettings.swift",
                                 r"static let enabledForCurrentLaunch(?:\s*:\s*Bool)?\s*=\s*false\b")
        flags = "Sources/FeatureFlags.swift"
        self.assertSourceMatches(flags, r"static var remoteConfigFetchEnabled: Bool \{ false \}")
        self.assertSourceHas(flags, "guard Self.remoteConfigFetchEnabled")
        app_delegate = "Sources/AppDelegate.swift"
        self.assertSourceLacks(app_delegate, "SentrySDK.start")
        self.assertSourceLacks(app_delegate, "PostHogAnalytics.shared.startIfNeeded()")
        self.assertSourceMatches(app_delegate,
                                 r"if CmuxFeatureFlags\.remoteConfigFetchEnabled[^{]*\{\s*CmuxFeatureFlags\.shared\.start\(\)")

    def test_telemetry_setting_row_is_hidden(self):
        section = "Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/AppSection.swift"
        self.assertSourceHas(section, "if Self.showsTelemetrySetting {")
        self.assertSourceMatches(section, r"static let showsTelemetrySetting = false\b")
        self.assertSourceLacks("Sources/CommandPalette/CommandPaletteSettingsToggle.swift",
                               'settingsKey: "app.sendAnonymousTelemetry"')

    def test_feedback_opens_mail_to_shellx(self):
        settings = "Packages/macOS/CmuxFeedback/Sources/CmuxFeedback/Settings/FeedbackComposerSettings.swift"
        self.assertSourceMatches(settings,
                                 r'static let submissionURL\s*=\s*URL\(string:\s*"mailto:"\s*\+\s*ShellXBrand\.contactEmail\)!')
        self.assertSourceLacks(settings, "https://")
        self.assertSourceHas(settings, 'defaultEndpoint: String = ""')
        self.assertSourceHas("Packages/macOS/CmuxFeedback/Sources/CmuxFeedback/Bridge/FeedbackComposerBridge.swift",
                             "NSWorkspace.shared.open(FeedbackComposerSettings.submissionURL)")
        # The sheet is never presented: the function ends in the mail draft
        # (UI tests record it through the DEBUG-only capture seam instead).
        body = re.search(r"private func presentFeedbackComposer\(\) \{\n(.*?)\n    \}\n",
                         read("Sources/ContentView.swift"), re.S)
        self.assertTrue(body, "presentFeedbackComposer() not found")
        self.assertTrue(body.group(1).rstrip().endswith("FeedbackComposerBridge.openMailDraft()"), body.group(1))
        self.assertNotIn("isFeedbackComposerPresented", body.group(1))

    def test_help_menu_points_to_shellx(self):
        resource = "Sources/App/CmuxHelpResource.swift"
        self.assertSourceHas(resource, "ShellXBrand.websiteURL")
        self.assertSourceHas(resource, "ShellXBrand.sourceCodeURL")
        self.assertSourceLacks(resource, "https://")
        commands = "Sources/App/CmuxHelpCommands.swift"
        self.assertSourceHas(commands, "helpResourceButton(.website)")
        self.assertSourceHas(commands, "helpResourceButton(.sourceCode)")
        self.assertSourceLacks(commands, "helpResourceButton(.discord)")

    def test_docs_links_without_a_shellx_page_are_hidden(self):
        # cmux's "Chord docs" and custom-commands "Open Docs" pages were on
        # cmux.com, and nothing under docs/ covers them, so both are hidden.
        shortcuts = "\n".join(code_lines(
            "Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/KeyboardShortcutsSection.swift"))
        self.assertNotIn("settings.shortcuts.chords.docsButton", shortcuts)
        self.assertNotIn("SettingsKeyboardShortcutsChordDocsLink", shortcuts)
        actions = "\n".join(code_lines("Sources/AppDelegate+WorkspaceActionSave.swift"))
        self.assertNotIn("settings.settingsJSON.docsButton", actions)
        self.assertNotIn("alertSecondButtonReturn", actions)
        self.assertNotIn("websiteURL", actions)

    def test_repository_docs_links_name_existing_files(self):
        # Docs links that stay point at a file in this repository.
        link = re.compile(r'(?:github\.com/lephus/shellx|sourceCodeURL\.absoluteString \+ ")/blob/main/([^"#)`\s]+)')
        hits = offenders(link.pattern, roots=["Sources", "CLI", "Packages/macOS", "Packages/Shared"], allow=[])
        self.assertTrue(hits)
        missing = []
        for hit in hits:
            path, number = hit.rsplit(":", 1)
            for target in link.findall(read(path).splitlines()[int(number) - 1]):
                if not (ROOT / target.rstrip(".")).is_file():
                    missing.append(f"{hit}: {target}")
        self.assertEqual(missing, [])

    def test_coderouter_is_never_downloaded_or_run(self):
        # CodeRouter is a Manaflow service no ShellX wave replaces, so its gate
        # is a switch of its own, not remoteMachines (Wave 2 flips that one).
        self.assertSourceMatches("Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXFeatures.swift",
                                 r"public static let codeRouter = false\b")
        # `cmux cr` and the passthrough refuse before looking for any executable.
        self.assertSourceMatches(
            "CLI/cmux.swift",
            r"func runCoderouterAlias\(\s*commandArgs: \[String\],\s*explicitSocketPath: String\?,[^{]*\{"
            r"(?:\s*//[^\n]*)*\s*guard ShellXFeatures\.codeRouter,\s*"
            r"let resolvedPath = resolveCoderouterExecutable\(environment: environment\) else \{\s*"
            r"throw Self\.coderouterNotAvailable\(\)")
        self.assertSourceLacks("CLI/cmux.swift", "bootstrapCoderouter")
        passthrough = "\n".join(code_lines("CLI/CMUXCLI+CoderouterPassthrough.swift"))
        for needle in ("remoteMachines", "curl", "install.sh", "bootstrapCoderouter", "readLine", "Process()"):
            self.assertNotIn(needle, passthrough)
        self.assertIn('defaultValue: "CodeRouter is not available in ShellX."', passthrough)
        # No ShellX build downloads or bundles the CodeRouter binary.
        hits = offenders(r"install-coderouter-client\.sh", roots=["scripts", ".github"],
                         allow=[("scripts/install-coderouter-client.sh", "the script itself")])
        self.assertEqual([hit for hit in hits if not is_comment_hit(hit)], [])
        pbx = read("cmux.xcodeproj/project.pbxproj")
        self.assertNotIn("coderouter-cli.json", pbx)
        self.assertNotIn("bin/coderouter", pbx)


if __name__ == "__main__":
    unittest.main()
