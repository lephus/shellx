#!/usr/bin/env python3
"""Manaflow Cloud is hard-off in ShellX; device mirroring waits for Wave 2.

Sign-in, accounts, Cloud machines, billing, Pro and CodeRouter have no entry
point: no menu, palette command, footer button, shortcut, CLI verb or socket
method reaches them. Each gate is a constant that stays false (`ShellXFeatures.cloud`,
`ShellXFeatures.codeRouter`, `CloudMachinesFeature`). Device discovery, the
mobile host listener and presence are parked behind `ShellXFeatures.remoteMachines`,
which Wave 2 flips; no Manaflow service is gated on that switch.

The checks read the sources, so a handler or verb added later without its
gate fails here.
"""

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from shellx_guard import ROOT, read  # noqa: E402


FEATURES = "Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXFeatures.swift"
GATE = "Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXCloudGate.swift"
CLOUD_FEATURE = "Packages/macOS/CmuxCloud/Sources/CmuxCloud/Machines/CloudMachinesFeature.swift"
SHORTCUT_ACTION = "Packages/macOS/CmuxSettings/Sources/CmuxSettings/Values/ShortcutAction.swift"
SHORTCUT_DEFAULTS = "Packages/macOS/CmuxSettings/Sources/CmuxSettings/Values/ShortcutAction+Defaults.swift"
APP_SHORTCUTS = "Sources/KeyboardShortcutSettings.swift"
SCHEMA = "Packages/macOS/CmuxFoundation/Sources/CmuxFoundation/ConfigValidation/CmuxConfigSchema.generated.swift"
CLI_MAIN = "CLI/cmux.swift"
CATALOG = "Resources/Localizable.xcstrings"
LOCALES = ["en", "de", "fr", "ar", "es", "zh-Hant", "zh-Hans", "ko", "ja"]

CLOUD_OFF = r"guard ShellXFeatures\.cloud else"
CODEROUTER_OFF = r"guard ShellXFeatures\.codeRouter else"
PARKED = r"guard ShellXFeatures\.remoteMachines else"

# Files that implement or gate a Manaflow service. None may mention
# remoteMachines: flipping it for ShellX's own relay must not bring one back.
MANAFLOW_FILES = [
    GATE,
    CLOUD_FEATURE,
    "CLI/CMUXCLI+CoderouterPassthrough.swift",
    "Sources/Cloud/CoderouterCLIAccountReader.swift",
    "Sources/Cloud/CodeRouterHandoffClient.swift",
    "Sources/Auth/HostAccountFlow.swift",
    "Sources/PricingPlansScreen.swift",
    "Sources/ProWelcomeChecklist.swift",
    "Sources/ContentView+AuthCommandPalette.swift",
    "Sources/ContentView+ProCommandPalette.swift",
    "Sources/Cloud/CloudWelcomeWindowController.swift",
]


def strip_comments(text):
    return "\n".join(line for line in text.splitlines() if not line.strip().startswith("//"))


def body(path, signature):
    """The brace-delimited body after the first match of `signature`."""
    return body_in(read(path), signature, path)


def body_in(text, signature, path="<text>"):
    match = re.search(signature, text)
    if not match:
        raise AssertionError(f"{path}: no declaration matching {signature!r}")
    start = text.index("{", match.end() - 1 if text[match.end() - 1] == "{" else match.end())
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:index]
    raise AssertionError(f"{path}: unbalanced body for {signature!r}")


def first_statement(path, signature):
    return first_statement_in(body(path, signature))


def first_statement_in(text):
    for line in text.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith(("//", "#if", "#endif", "#else", "cmuxDebugLog")):
            return stripped
    return ""


def swift_string_list(path, name):
    match = re.search(name + r"\s*=\s*\[(.*?)\]", read(path), re.S)
    if not match:
        raise AssertionError(f"{path}: no list {name}")
    return re.findall(r'"([^"]+)"', match.group(1))


def socket_refused(method):
    if method in swift_string_list(GATE, "localSocketMethods"):
        return False
    prefixes = (swift_string_list(GATE, "cloudSocketMethodPrefixes")
                + swift_string_list(GATE, "codeRouterSocketMethodPrefixes"))
    return any(method.startswith(prefix) for prefix in prefixes)


class SwitchesAreConstant(unittest.TestCase):
    def test_shellx_switches_are_false(self):
        text = read(FEATURES)
        for name in ("remoteMachines", "codeRouter", "cloud"):
            self.assertRegex(text, rf"public static let {name} = false\b", name)

    def test_cloud_machines_feature_is_constant_false(self):
        for signature in (r"static func isAvailable\(policy: ManagedDevicePolicy\) -> Bool \{",
                          r"static func isEnabled\(\s*defaults: UserDefaults,\s*policy: ManagedDevicePolicy\s*\) -> Bool \{"):
            self.assertEqual(first_statement(CLOUD_FEATURE, signature), "false", signature)

    def test_no_manaflow_service_is_gated_on_remote_machines(self):
        for path in MANAFLOW_FILES:
            self.assertNotIn("remoteMachines", strip_comments(read(path)), path)


class DeviceMirroringIsParked(unittest.TestCase):
    def test_devices_feature_follows_remote_machines_not_cloud(self):
        text = body("Sources/Devices/DevicesFeature.swift", r"static func isAvailable\(")
        self.assertIn("ShellXFeatures.remoteMachines", text)
        self.assertNotIn("CloudMachinesFeature", text)
        self.assertNotIn("cloudEnabled ??", text)

    def test_mobile_host_listening_and_presence_wait_for_remote_machines(self):
        self.assertRegex(first_statement(
            "Sources/Mobile/MobileHostService.swift",
            r"static func isListeningEnabled\(\s*defaults: UserDefaults,\s*buildFlavor: BuildFlavor\s*\) -> Bool \{"), PARKED)
        self.assertRegex(first_statement(
            "Sources/Cloud/PresenceSettings.swift", r"static func isEnabled\(defaults: UserDefaults = \.standard\) -> Bool \{"),
            PARKED)

    def test_mobile_pairing_waits_for_remote_machines(self):
        self.assertRegex(first_statement(
            "Sources/AppDelegate.swift", r"func performMobileConnectWorkspaceAction\([^{]*\{"), PARKED)

    def test_pairing_window_waits_for_remote_machines(self):
        self.assertRegex(first_statement(
            "Sources/Mobile/Pairing/MobilePairingWindowController.swift", r"func show\(\) \{"), PARKED)

    def test_machines_sidebar_mode_waits_for_remote_machines(self):
        text = body("Sources/RightSidebarMode+Availability.swift",
                    r"func isAvailable\(\s*feedEnabled: Bool,\s*machinesEnabled: Bool,[^{]*\{")
        self.assertRegex(text, r"case \.machines:(?:\s*//[^\n]*)*\s*return ShellXFeatures\.remoteMachines && machinesEnabled")


class CloudShortcutsAreGone(unittest.TestCase):
    REMOVED = ("newCloudWorkspace", "newCloudMachine")

    def test_shortcut_actions_are_removed_everywhere(self):
        for path in (SHORTCUT_ACTION, SHORTCUT_DEFAULTS, APP_SHORTCUTS, SCHEMA,
                     "Packages/macOS/CmuxSettings/Sources/CmuxSettings/Values/ShortcutAction+Group.swift",
                     "Packages/macOS/CmuxSettings/Sources/CmuxSettings/Values/ShortcutAction+DisplayName.swift",
                     "Sources/AppDelegate+DockShortcutRouting.swift",
                     "skills/cmux-settings/references/shortcut-actions.md"):
            for name in self.REMOVED:
                self.assertNotRegex(read(path), rf"(case \.?|\"|bindings\.){name}\b", f"{path}: {name}")

    def test_cmd_y_defaults_are_gone(self):
        self.assertNotRegex(read(SHORTCUT_DEFAULTS), r'ShortcutStroke\(key: "y", command: true')
        self.assertNotRegex(read(APP_SHORTCUTS), r'StoredShortcut\(key: "y", command: true')
        self.assertNotRegex(read("docs/configuration.md"), r"Cmd\+(Shift\+)?Y\b")

    def test_cloud_shortcut_routing_is_gone(self):
        text = read("Sources/AppDelegate.swift")
        for name in self.REMOVED:
            self.assertNotIn(f"action: .{name})", text)
        self.assertNotIn('debugSource: "shortcut.cmdY"', text)


class NoCloudUIEntryPoint(unittest.TestCase):
    def test_menus_have_no_cloud_entries(self):
        app = read("Sources/cmuxApp.swift")
        self.assertNotRegex(strip_comments(app), r"^\s*cloudCommands\s*$", "Cloud menu is installed")
        self.assertNotIn("performNewCloudWorkspaceOnResolvedMachineAction", app)
        self.assertNotIn("performNewCloudMachineAction", app)
        help_menu = read("Sources/App/CmuxHelpCommands.swift")
        for gone in ("showCloudDiagnostics", "cloudWelcomeDebugMenuItems", "ProUpgradePresenter",
                     "ProWelcomeChecklistPresenter", "cloudSidebarDebugLabController"):
            self.assertNotIn(gone, help_menu)
        status_item = body("Sources/AppDelegate.swift", r"return MenuBarExtraController\(")
        self.assertNotIn("cloudMenuEntries", status_item)
        self.assertNotIn("CloudMenuModel", status_item)

    def test_palette_contributes_no_account_cloud_or_pro_command(self):
        for path, signature in (
            ("Sources/ContentView+AuthCommandPalette.swift", r"static func commandPaletteAuthCommandContributions\(\)[^{]*\{"),
            ("Sources/ContentView+AuthCommandPalette.swift", r"static func commandPaletteCloudCommandContributions\([^{]*\{"),
            ("Sources/ContentView+ProCommandPalette.swift", r"static func commandPaletteProCommandContributions\(\)[^{]*\{"),
        ):
            self.assertRegex(first_statement(path, signature), CLOUD_OFF + r" \{ return \[\] \}", signature)
        for path, signature in (
            ("Sources/ContentView+AuthCommandPalette.swift", r"func registerAuthCommandHandlers\([^{]*\{"),
            ("Sources/ContentView+AuthCommandPalette.swift", r"func registerCloudCommandHandlers\([^{]*\{"),
            ("Sources/ContentView+ProCommandPalette.swift", r"func registerProCommandHandlers\([^{]*\{"),
        ):
            self.assertRegex(first_statement(path, signature), CLOUD_OFF + r" \{ return \}", signature)

    def test_cloud_welcome_never_presents_itself(self):
        self.assertRegex(first_statement(
            "Sources/Cloud/CloudWelcomeWindowController.swift",
            r"static func shouldPresentAutomatically\([^{]*\{"), CLOUD_OFF + r" \{ return false \}")

    def test_footer_hides_account_cloud_and_pro(self):
        text = body("Sources/VerticalTabsSidebar+EmptyAreasAndFooter.swift", r"enum SidebarFooterPresentationPolicy \{")
        self.assertRegex(text, r"cloudOnlyControls: \[SidebarFooterControl\] = \[\.account, \.cloud, \.upgrade\]")
        self.assertRegex(text, r"parkedControls: \[SidebarFooterControl\] = \[\.mobileConnect\]")
        self.assertRegex(first_statement("Sources/VerticalTabsSidebar+EmptyAreasAndFooter.swift",
                                         r"static func isVisible\([^{]*\{"),
                         r"if !ShellXFeatures\.cloud, cloudOnlyControls\.contains\(control\) \{ return false \}")
        self.assertRegex(first_statement("Sources/VerticalTabsSidebar+EmptyAreasAndFooter.swift",
                                         r"static func isUpgradeVisible\([^{]*\{"), CLOUD_OFF + r" \{ return false \}")


class NoBillingOrSignIn(unittest.TestCase):
    GATED = [
        ("Sources/AppDelegate.swift", r"func handleAuthCallbackURLInProcess\([^{]*\{", "return false"),
        ("Sources/PricingPlansScreen.swift", r"static var currentUpgradeOffer: CmuxPlanTier\? \{", "return nil"),
        ("Sources/PricingPlansScreen.swift", r"(?s)static func present\(\s*source: ProUpgradeSource,.*?\n    \) \{", "return"),
        ("Sources/PricingPlansScreen.swift", r"static func prefetch\(source: ProUpgradeSource\) \{", "return"),
        ("Sources/PricingPlansScreen.swift", r"static func presentAppPricingWeb\(source: ProUpgradeSource\) \{", "return"),
        ("Sources/PricingPlansScreen.swift", r"static func presentNativePricingPreview\(\) \{", "return"),
        ("Sources/PricingPlansScreen.swift", r"static func presentCheckout\([^{]*\{", "return"),
        ("Sources/PricingPlansScreen.swift", r"static func presentBillingPortal\(\) \{", "return"),
        ("Sources/ProWelcomeChecklist.swift", r"static func present\(\) \{", "return"),
        ("Sources/ProWelcomeChecklist.swift", r"static func presentIfNewlyPro\([^{]*\{", "return"),
        ("Sources/ProWelcomeChecklist.swift", r"static func presentProWelcomeWeb\(\) \{", "return"),
        ("Sources/Auth/HostAccountFlow.swift", r"func startSignIn\(\) \{", "return"),
        ("Sources/Auth/HostAccountFlow.swift", r"func startSignInForPane\(\) -> URL\? \{", "return nil"),
        ("Sources/Auth/HostAccountFlow.swift", r"func signIn\(timeout: TimeInterval\) async -> Bool \{", "return false"),
        ("Sources/Auth/HostAccountFlow.swift", r"func handleCallbackURL\([^{]*\{", "return false"),
        ("Sources/Auth/HostAccountFlow.swift", r"func switchAccount\(\) async \{", "return"),
        ("Sources/Auth/HostAccountFlow.swift", r"func refreshBillingPlanAndReportSuccess\(\) async -> Bool \{", "return false"),
        ("Sources/Auth/HostAccountFlow.swift", r"var isProUpgradeAvailable: Bool \{", "return false"),
        ("Sources/Auth/HostAccountFlow.swift", r"var upgradeOffer: CmuxPlanTier\? \{", "return nil"),
    ]

    def test_billing_pro_and_sign_in_entry_points_refuse_first(self):
        for path, signature, refusal in self.GATED:
            self.assertRegex(first_statement(path, signature), CLOUD_OFF + r" \{ " + re.escape(refusal) + r" \}",
                             f"{path}: {signature}")

    def test_native_pricing_refresh_is_gated(self):
        text = body("Sources/PricingPlansScreen.swift", r"enum NativePricingPlanRefresh \{")
        signatures = re.findall(r"static func \w+\([^)]*\)[^{]*\{", text)
        self.assertTrue(signatures)
        for signature in signatures:
            self.assertRegex(first_statement_in(body_in(text, re.escape(signature))), CLOUD_OFF, signature)


class SocketMethodsAreRefused(unittest.TestCase):
    ENTRY_FILES = ["Sources/TerminalController.swift", "Sources/TerminalController+ControlSocketAsync.swift"]

    def test_every_dispatch_entry_refuses_before_running(self):
        """Each v2 entry (sync socket, async socket, main lane, async main lane)
        asks the gate before its focus check, i.e. before any handler."""
        entries = 0
        for path in self.ENTRY_FILES:
            text = read(path)
            for match in re.finditer(r"Self\.focusSuppressionResponse\(", text):
                entries += 1
                preceding = text[max(0, match.start() - 600):match.start()]
                self.assertIn("Self.shellXUnavailableServiceResponse(", preceding,
                              f"{path}: focus check at offset {match.start()} without the ShellX gate before it")
        self.assertEqual(entries, 4, "expected the four v2 entry points")
        self.assertIn("ShellXCloudGate.unavailableService(forSocketMethod: method)",
                      body("Sources/TerminalController.swift",
                           r"static func shellXUnavailableServiceResponse\([^{]*\{"))

    def test_every_cloud_socket_method_is_refused(self):
        literal = re.compile(r'"((?:auth|vm|remotes|aiAccounts|coderouter|billing|team)\.[A-Za-z0-9_.]+)"')
        roots = ["Sources", "Packages/macOS/CmuxControlSocket/Sources"]
        methods = set()
        for root in roots:
            for path in (ROOT / root).rglob("*.swift"):
                for found in literal.findall(path.read_text(encoding="utf-8")):
                    methods.add(found)
        self.assertGreater(len([m for m in methods if m.startswith("vm.")]), 40, "parsed too few vm.* methods")
        not_refused = sorted(m for m in methods if not socket_refused(m)
                             and m not in swift_string_list(GATE, "localSocketMethods")
                             and not m.endswith((".json", ".swift")))
        self.assertEqual(not_refused, [], "Cloud socket methods the ShellX gate does not refuse")
        self.assertFalse(socket_refused("auth.login"), "socket password login must stay local")


class CLIVerbsAreRefused(unittest.TestCase):
    CLOUD_CALL = re.compile(
        r'sendV2\(method: "(?:vm|remotes|aiAccounts|coderouter|billing)\.|sendV2\(method: "auth\.(?!login")'
        r"|run(?:VPN|Remotes|AIAccounts|Coderouter|CloudDomains|AuthTeam|VMPtyAttach|VMTuiConnect|VMSSHAttach)\w*\(")

    def test_gate_runs_before_any_dispatch(self):
        text = read(CLI_MAIN)
        start = text.index("let rawCommandArgs = Array(args[(index + 1)...])")
        following = [line.strip() for line in text[start:].splitlines()[1:] if line.strip()]
        self.assertEqual(following[0], "if let service = ShellXCloudGate.unavailableService(forCLICommand: command) {")
        self.assertEqual(following[1], "throw Self.shellXUnavailable(service)")

    def test_every_dispatch_case_reaching_cloud_is_refused(self):
        """The top-level verb switch (the one with `case "auth", "login", "logout"`):
        every verb whose case reaches a Cloud socket method or Cloud runner is refused."""
        source = read(CLI_MAIN)
        anchor = source.index('case "auth", "login", "logout":')
        start = source.rindex("\n        switch command {", 0, anchor)
        text = "\n" + body_in(source[start:], r"switch command \{", CLI_MAIN)
        cases = list(re.finditer(r"\n        case ((?:\"[^\"]+\"(?:, )?)+):", text))
        refused = set(swift_string_list(GATE, "cloudCLICommands") + swift_string_list(GATE, "codeRouterCLICommands"))
        checked = 0
        for index, match in enumerate(cases):
            end = cases[index + 1].start() if index + 1 < len(cases) else len(text)
            labels = re.findall(r'"([^"]+)"', match.group(1))
            if not self.CLOUD_CALL.search(text[match.end():end]):
                continue
            checked += 1
            for label in labels:
                if label == "agent":
                    continue  # local verbs; its Cloud alias stops in runVMAgentCommand (below)
                self.assertIn(label, refused, f"CLI verb {label!r} reaches Cloud without the ShellX gate")
        self.assertGreaterEqual(checked, 5, "parsed too few Cloud CLI cases")

    def test_vm_agent_alias_refuses_first(self):
        self.assertRegex(first_statement("CLI/CMUXCLI+VMTransfer.swift", r"func runVMAgentCommand\([^{]*\{"),
                         CLOUD_OFF + r" \{ throw Self\.shellXUnavailable\(\.cloud\) \}")

    def test_vm_tui_names_no_installer_host(self):
        self.assertNotIn("cmux.com", read("CLI/CMUXCLI+VMTui.swift"))


class CodeRouterNeverRuns(unittest.TestCase):
    def test_account_reader_never_execs(self):
        self.assertRegex(first_statement("Sources/Cloud/CoderouterCLIAccountReader.swift",
                                         r"private static func runCLI\(_ arguments: \[String\], environment: \[String: String\]\)[^{]*\{"),
                         CODEROUTER_OFF)

    def test_handoff_client_never_mints(self):
        self.assertRegex(first_statement("Sources/Cloud/CodeRouterHandoffClient.swift",
                                         r"func mint\(teamID explicitTeamID: String\? = nil\)[^{]*\{"), CODEROUTER_OFF)
        self.assertRegex(read("Sources/TerminalController.swift"),
                         r"self\.codeRouterHandoffService = ShellXFeatures\.codeRouter\s*\?")


class RefusalCopyIsLocalized(unittest.TestCase):
    KEYS = ["shellx.cloud.unavailable", "cli.vm.tui.clientMissingNoInstaller"]

    def test_new_keys_carry_every_locale(self):
        strings = json.loads(read(CATALOG))["strings"]
        for key in self.KEYS:
            self.assertIn(key, strings)
            localizations = strings[key]["localizations"]
            self.assertEqual(sorted(localizations), sorted(LOCALES), key)
            for locale, entry in localizations.items():
                value = entry["stringUnit"]["value"]
                self.assertNotIn("cmux.com", value, f"{key}/{locale}")


if __name__ == "__main__":
    unittest.main()
