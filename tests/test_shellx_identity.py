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


# The `cmux` app target's configurations and the dock tile plugin's.
APP_DEBUG = "A5001082"
APP_RELEASE = "A5001083"
APP_TARGET = "A5001050"


class ShellXIdentityTests(unittest.TestCase):
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

    def test_reload_script_builds_shellx_dev(self):
        script = read("scripts/reload.sh")
        self.assertContains('APP_NAME="ShellX DEV"\n', script)
        self.assertContains('BUNDLE_ID="pro.shellx.desktop.debug"\n', script)
        self.assertContains('BASE_APP_NAME="ShellX DEV"\n', script)
        self.assertContains('APP_NAME="ShellX DEV ${TAG_SLUG}"', script)
        self.assertContains('BUNDLE_ID="pro.shellx.desktop.debug.${TAG_ID}"', script)
        self.assertLacks("cmux DEV", script)
        self.assertLacks("com.cmuxterm.app", script)


if __name__ == "__main__":
    unittest.main()
