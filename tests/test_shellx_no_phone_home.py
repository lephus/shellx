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

CLOUD_REASON = "unreachable: ShellXFeatures.remoteMachines == false / Cloud hard-off (Task 5)"

# Whole files whose code only runs for cmux Cloud, Stack Auth, iroh device
# mirroring, the phone host, CodeRouter, cloud VMs or billing. Task 5 switches
# all of that off; Wave 2 removes entries as it swaps the transports.
CLOUD_ALLOWLIST = [
    ("CLI/CMUXCLI+CoderouterPassthrough.swift", CLOUD_REASON),
    ("CLI/CMUXCLI+VMTui.swift", CLOUD_REASON),
    ("Packages/Shared/CmuxAuthRuntime/Sources/CmuxAuthRuntime/Client/StackAuthClient.swift", CLOUD_REASON),
    ("Packages/Shared/CmuxAuthRuntime/Sources/CmuxAuthRuntime/Coordinator/AuthConfig.swift", CLOUD_REASON),
    ("Packages/Shared/CmuxIrohTransport/Package.resolved", CLOUD_REASON),
    ("Packages/Shared/CmuxIrohTransport/Package.swift", CLOUD_REASON),
    ("Packages/Shared/CmuxIrxTransport/Package.resolved", CLOUD_REASON),
    ("Packages/Shared/CmuxIrxTransport/Package.swift", CLOUD_REASON),
    ("Packages/macOS/CmuxCloud/Sources/CmuxCloud/Environment/AuthEnvironment.swift", CLOUD_REASON),
    ("Packages/macOS/CmuxCloud/Sources/CmuxCloud/VMClient/VMClient.swift", CLOUD_REASON),
    ("Packages/macOS/CmuxCloud/Sources/CmuxCloud/VMClient/VMTunnelManager.swift", CLOUD_REASON),
    ("Packages/macOS/CmuxFeedback/Sources/CmuxFeedback/DogfoodSink/DogfoodFeedbackService.swift", CLOUD_REASON),
    ("Resources/coderouter-cli.json", CLOUD_REASON),
    ("Resources/en.lproj/cloud-agent-skill.md", CLOUD_REASON),
    ("Sources/Cloud/CloudSecurityExplainer.swift", CLOUD_REASON),
    ("Sources/Cloud/CodeRouterHandoffClient.swift", CLOUD_REASON),
    ("Sources/Cloud/PresenceSettings.swift", CLOUD_REASON),
    ("Sources/Mobile/MobileHostV2Installation.swift", CLOUD_REASON),
    ("Sources/Mobile/Pairing/MobilePairingView.swift", CLOUD_REASON),
    ("Sources/PricingPlansScreen.swift", CLOUD_REASON),
]

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
    ('"https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json"',
     "$id/default inside the embedded config schema, generated from upstream's web/data (not in ShellX); used for local validation only"),
]

# Package test targets never ship in the app; their fixtures use upstream URLs.
SKIPPED_PATH_PARTS = [("/Tests/", "package test targets are not shipped")]

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
    return path.endswith(".xcstrings") or any(part in path for part, _reason in SKIPPED_PATH_PARTS)


def reachable_offenders(pattern, roots, allow):
    """offenders() hits outside comments, package tests and catalogs, after
    removing NON_NETWORK_LITERALS from each line."""
    regex = re.compile(pattern)
    lines_by_path = {}
    hits = []
    for hit in offenders(pattern, roots=roots, allow=allow):
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
        if regex.search(line):
            hits.append(hit)
    return hits


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
        imports = (r"^\s*(?:@\w+\s+)*(?:public |internal |package |private |fileprivate )?import\s+"
                   r"(?:(?:struct|class|enum|protocol|func|var|let|typealias)\s+)?(Sentry|PostHog)\b")
        self.assertEqual(offenders(imports, roots=["Sources", "CLI", "Packages"], allow=[]), [])

    def test_no_forbidden_hosts_in_reachable_code(self):
        self.assertTrue(FORBIDDEN_HOSTS, "ShellXNetworkPolicy.forbiddenHosts is missing")
        for host in FORBIDDEN_HOSTS:
            self.assertEqual(reachable_offenders(host_pattern(host), HOST_ROOTS, CLOUD_ALLOWLIST), [], host)

    def test_cloud_allowlist_entries_are_live(self):
        pattern = "|".join(host_pattern(h) for h in EXPECTED_FORBIDDEN_HOSTS)
        for path, reason in CLOUD_ALLOWLIST:
            self.assertEqual(reason, CLOUD_REASON, path)
            self.assertTrue((ROOT / path).is_file(), f"stale allowlist entry: {path}")
            self.assertTrue(re.search(pattern, read(path)), f"allowlisted file no longer names a forbidden host: {path}")

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
        key_pattern = "|".join(re.escape(f'"{key}"') for key in sorted(keys))
        hits = [
            hit for hit in offenders(key_pattern, roots=["Sources", "CLI", "Packages/macOS", "Packages/Shared"], allow=CLOUD_ALLOWLIST)
            if not is_skipped(hit.rsplit(":", 1)[0])
        ]
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
        self.assertSourceMatches("Sources/ContentView.swift",
                                 r"private func presentFeedbackComposer\(\) \{\s*FeedbackComposerBridge\.openMailDraft\(\)")

    def test_help_menu_points_to_shellx(self):
        resource = "Sources/App/CmuxHelpResource.swift"
        self.assertSourceHas(resource, "ShellXBrand.websiteURL")
        self.assertSourceHas(resource, "ShellXBrand.sourceCodeURL")
        self.assertSourceLacks(resource, "https://")
        commands = "Sources/App/CmuxHelpCommands.swift"
        self.assertSourceHas(commands, "helpResourceButton(.website)")
        self.assertSourceHas(commands, "helpResourceButton(.sourceCode)")
        self.assertSourceLacks(commands, "helpResourceButton(.discord)")


if __name__ == "__main__":
    unittest.main()
