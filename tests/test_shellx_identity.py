#!/usr/bin/env python3
"""ShellX app identity: bundle ids, product names, team, URL scheme, update feed."""

import plistlib
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from shellx_guard import ROOT, offenders, read  # noqa: E402

PBXPROJ = "cmux.xcodeproj/project.pbxproj"

# (path, reason) entries for files that may still carry the upstream team id.
ALLOWLIST = []


def build_settings(pbx, config_id):
    """The buildSettings block text of the XCBuildConfiguration `config_id`."""
    match = re.search(
        r"^\t\t" + re.escape(config_id) + r" /\* \w+ \*/ = \{\n(.*?)^\t\t\};",
        pbx,
        re.S | re.M,
    )
    if match is None:
        raise AssertionError(f"build configuration {config_id} not found")
    return match.group(1)


def target_block(pbx, target_id):
    match = re.search(
        r"^\t\t" + re.escape(target_id) + r" /\* [^*]+ \*/ = \{\n\t\t\tisa = PBXNativeTarget;\n(.*?)^\t\t\};",
        pbx,
        re.S | re.M,
    )
    if match is None:
        raise AssertionError(f"native target {target_id} not found")
    return match.group(1)


# Swift that ships in the Mac app or its CLI (the iOS packages are cmux's iOS app).
SWIFT_ROOTS = ["Sources", "CLI", "Packages/macOS", "Packages/Shared"]

# `com.cmuxterm.app…` strings that are not ShellX's bundle id, each with the
# reason it stays. Matched against the source line.
CMUX_ID_LINE_ALLOW = [
    (r"subsystem", "os_log subsystem: in-process label (ruling R3)"),
    (r"label: \"com\.shellx\.app\.", "DispatchQueue label: in-process (R3)"),
    (r"releaseBundleIdentifier = \"com\.shellx\.app\"", "GhosttyTerminalView: only an os_log subsystem (R3)"),
    (r"Notification\.Name\(\"com\.shellx\.app\.(displayReconfiguration|screenChangeReconcile)\"\)",
     "in-process NotificationCenter names (R3)"),
    (r"\"com\.shellx\.app\.userNotification", "UNNotification category ids, scoped to this app (R3)"),
    (r"releasePayloadDomain = \"com\.shellx\.app\"", "MDM payload domain: Task 4"),
]

# The `cmux` app target's configurations and the dock tile plugin's.
APP_DEBUG = "A5001082"
APP_RELEASE = "A5001083"
APP_TARGET = "A5001050"


class ShellXIdentityTests(unittest.TestCase):
    maxDiff = None

    # Short failure messages: the haystacks are whole project files.
    def assertContains(self, needle, haystack):
        self.assertTrue(needle in haystack, f"missing: {needle!r}")

    def assertLacks(self, needle, haystack):
        self.assertFalse(needle in haystack, f"still present: {needle!r}")

    def test_app_bundle_ids_are_shellx(self):
        pbx = read(PBXPROJ)
        self.assertContains("PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop;", pbx)
        self.assertContains("PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop.debug;", pbx)
        self.assertTrue("com.cmuxterm.app;" not in pbx and "7WLXT3NR37" not in pbx)

    def test_no_upstream_team_id_in_sources(self):
        self.assertEqual(
            offenders(r"7WLXT3NR37", roots=["Sources", "CLI", "Packages", "Resources", "scripts"], allow=ALLOWLIST),
            [],
        )

    def test_update_feed_is_shellx(self):
        with open(ROOT / "Resources/Info.plist", "rb") as f:
            info = plistlib.load(f)
        self.assertEqual(info["SUFeedURL"], "https://download.shellx.pro/desktop/appcast.xml")
        self.assertIs(info["SUEnableAutomaticChecks"], False)

    def test_app_names_scheme_and_sparkle_key_per_configuration(self):
        pbx = read(PBXPROJ)
        debug = build_settings(pbx, APP_DEBUG)
        release = build_settings(pbx, APP_RELEASE)
        self.assertContains('PRODUCT_NAME = "ShellX DEV";', debug)
        self.assertContains("PRODUCT_NAME = ShellX;", release)
        self.assertContains("PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop.debug;", debug)
        self.assertContains("PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop;", release)
        # The Swift module keeps its upstream name: every cmuxTests file does
        # `@testable import cmux_DEV` / `cmux`.
        self.assertContains("PRODUCT_MODULE_NAME = cmux_DEV;", debug)
        self.assertContains("PRODUCT_MODULE_NAME = cmux;", release)
        self.assertContains('CMUX_AUTH_CALLBACK_SCHEME = "shellx-dev";', debug)
        self.assertContains("CMUX_AUTH_CALLBACK_SCHEME = shellx;", release)
        # Wave 3 sets the EdDSA key; until then Sparkle stays unconfigured.
        self.assertContains('SPARKLE_PUBLIC_KEY = "";', debug)
        self.assertContains('SPARKLE_PUBLIC_KEY = "";', release)

    def test_test_hosts_follow_the_app_product_name(self):
        pbx = read(PBXPROJ)
        self.assertContains('TEST_HOST = "$(BUILT_PRODUCTS_DIR)/ShellX DEV.app/Contents/MacOS/ShellX DEV";', pbx)
        self.assertContains('TEST_HOST = "$(BUILT_PRODUCTS_DIR)/ShellX.app/Contents/MacOS/ShellX";', pbx)
        self.assertLacks("cmux DEV.app", pbx)

    def test_every_bundle_id_in_the_project_is_shellx(self):
        pbx = read(PBXPROJ)
        ids = re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = \"?([^;\"]+)\"?;", pbx)
        self.assertTrue(ids)
        for bundle_id in ids:
            self.assertTrue(
                bundle_id == "pro.shellx.desktop" or bundle_id.startswith("pro.shellx.desktop."),
                bundle_id,
            )
        self.assertContains("PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop.docktileplugin;", pbx)
        self.assertContains("PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop.docktileplugin.debug;", pbx)
        self.assertNotRegex(pbx, r"CMUX_TEAM_ID_PREFIX = (?!\"W4RF3W4VTZ\.\";)")

    def test_app_does_not_embed_or_depend_on_the_tunnel_extension(self):
        pbx = read(PBXPROJ)
        app = target_block(pbx, APP_TARGET)
        self.assertLacks("7A0CE1000000000000000062", app)
        self.assertLacks("cmuxTunnel.systemextension in Embed System Extensions", pbx)
        # The extension target and its sources stay in the project.
        self.assertContains("/* cmuxTunnelExtension */ = {", pbx)

    def test_url_scheme_is_registered_from_the_build_setting(self):
        with open(ROOT / "Resources/Info.plist", "rb") as f:
            info = plistlib.load(f)
        schemes = [s for t in info["CFBundleURLTypes"] for s in t.get("CFBundleURLSchemes", [])]
        self.assertContains("$(CMUX_AUTH_CALLBACK_SCHEME)", schemes)
        self.assertLacks("cmux", schemes)
        self.assertLacks("cmux-dev", schemes)

    def test_swift_names_shellx_not_cmux_as_its_bundle_id(self):
        hits = [hit for hit in offenders(r"com\.shellx\.app", roots=SWIFT_ROOTS, allow=[]) if "/Tests/" not in hit
                and hit.split(":")[0].endswith(".swift")]
        unexpected = []
        for hit in hits:
            path, line_number = hit.rsplit(":", 1)
            line = read(path).splitlines()[int(line_number) - 1]
            if line.lstrip().startswith("//"):
                continue  # documentation
            if any(re.search(pattern, line) for pattern, _reason in CMUX_ID_LINE_ALLOW):
                continue
            unexpected.append(f"{hit}: {line.strip()}")
        self.assertEqual(unexpected, [])

    def test_team_ids_in_swift_come_from_shellx(self):
        cli = read("CLI/cmux.swift")
        self.assertContains('certificate leaf[subject.OU] = "\\#(ShellXBrand.teamID)""#', cli)
        self.assertContains("== ShellXBrand.teamID else {", cli)
        self.assertContains("sudoReleaseTeamIdentifier = ShellXBrand.teamID", read("CLI/CMUXCLI+Sudo.swift"))
        trust = read("Packages/macOS/CmuxComputerUse/Sources/CmuxComputerUse/ComputerUseHelperTrust.swift")
        self.assertContains('public static let teamIdentifier = "W4RF3W4VTZ"', trust)

    def test_distributed_notifications_are_shellx_scoped(self):
        # Both ends of each cross-process notification use the same ShellX name.
        self.assertContains('"\\(ShellXBrand.bundleID).themes.reload-config"', read("CLI/CMUXCLI+Themes.swift"))
        self.assertContains('Notification.Name("\\(ShellXBrand.bundleID).themes.reload-config")', read("Sources/AppDelegate.swift"))
        for path in ("Sources/AppIconDockTilePlugin.swift", "Sources/cmuxApp.swift"):
            self.assertContains('Notification.Name("pro.shellx.desktop.appIconDidChange")', read(path))

    def test_auth_and_ssh_url_schemes_are_shellx(self):
        auth = read("Packages/macOS/CmuxCloud/Sources/CmuxCloud/Environment/AuthEnvironment.swift")
        for scheme in ('"shellx-dev"', '"shellx-dev-\\(schemeTag)"', '"shellx-nightly"', '"shellx-rc"', 'return "shellx"'):
            self.assertContains(scheme, auth)
        family = '["shellx", "shellx-nightly", "shellx-rc", "shellx-dev"]'
        self.assertContains(family, read("Packages/Shared/CmuxAuthRuntime/Sources/CmuxAuthRuntime/BrowserSignIn/AuthCallbackRouter.swift"))
        self.assertContains(family, read("Sources/CmuxSSHURLRequest.swift"))
        reload_script = read("scripts/reload.sh")
        self.assertContains('CMUX_AUTH_CALLBACK_SCHEME_VALUE="shellx-dev-${TAG_SLUG}"', reload_script)
        self.assertLacks('"cmux-dev', reload_script)

    def test_computer_use_helper_is_not_built_by_default(self):
        script = read("scripts/build-app-bundled-resources.sh")
        self.assertContains('CMUX_CUA_HELPER_BUILD="${CMUX_CUA_HELPER_BUILD:-0}"', script)
        self.assertContains('if [ "$CMUX_CUA_HELPER_BUILD" = 1 ]; then\n  if [ ! -x "$BUILD_CMUX_CUA" ]', script)
        self.assertContains('if [[ "${CMUX_CUA_HELPER_BUILD:-0}" != "1" ]]; then\n  rm -rf "$CMUX_CUA_HELPER_APP"', read("scripts/reload.sh"))

    def test_reload_script_builds_shellx_dev(self):
        script = read("scripts/reload.sh")
        self.assertContains('APP_NAME="ShellX DEV"\n', script)
        self.assertContains('BUNDLE_ID="pro.shellx.desktop.debug"\n', script)
        self.assertContains('BASE_APP_NAME="ShellX DEV"\n', script)
        self.assertContains('APP_NAME="ShellX DEV ${TAG_SLUG}"', script)
        self.assertContains('BUNDLE_ID="pro.shellx.desktop.debug.${TAG_ID}"', script)
        self.assertLacks("cmux DEV", script)
        # cmux ids only appear in the --bundle-id refusal: a tagged build never
        # takes over (and quits) a user's ShellX or cmux.
        cmux_lines = [line.strip() for line in script.splitlines() if "com.cmuxterm" in line]
        self.assertEqual(len(cmux_lines), 1, cmux_lines)
        self.assertTrue(cmux_lines[0].startswith('if [[ "$BUNDLE_ID_LOWER" == "pro.shellx.desktop" ||'), cmux_lines[0])
        self.assertContains('"$BUNDLE_ID_LOWER" == com.cmuxterm.app.* ]]', cmux_lines[0])


if __name__ == "__main__":
    unittest.main()
