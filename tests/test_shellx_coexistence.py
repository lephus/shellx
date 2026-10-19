#!/usr/bin/env python3
"""ShellX runs beside an installed cmux without sharing its runtime names.

Sockets, config/state/Application Support paths, the CLI command, the bundled
agent wrappers, hook markers, pasteboard/UTI types, keychain services and the
`~/.cmuxterm` / `~/.cmux` state trees all carry ShellX names (plan Task 3).
"""

import plistlib
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from shellx_guard import ROOT, offenders, read  # noqa: E402

PBXPROJ = "cmux.xcodeproj/project.pbxproj"
ROOTS = ["Sources", "CLI", "Packages", "Resources"]

FORBIDDEN = [r"/tmp/cmux", r"\.config/cmux", r"\.local/state/cmux", r"Application Support/cmux",
             r'"__cmux"', r"\bcom\.cmux\.", r"/usr/local/bin/cmux\b", r"cmux\.sock"]

# (path, reason): files or directories (trailing "/") that may keep cmux names.
ALLOWLIST = [
    ("Packages/iOS/", "cmux's iOS app packages; the ShellX Mac app and CLI neither build nor link them"),
    ("Resources/Localizable.xcstrings", "UI copy is L2 Task 6 (ruling R8); path text in copy follows there"),
    ("Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Resources/Localizable.xcstrings",
     "UI copy is L2 Task 6 (ruling R8)"),
    ("Packages/macOS/CmuxFoundation/Sources/CmuxFoundation/Resources/Localizable.xcstrings",
     "UI copy is L2 Task 6 (ruling R8)"),
]


def _package_test_dirs():
    """Every `Packages/<platform>/<package>/Tests/` directory.

    Package tests hold fixtures (temp dirs, sample sockets, paths of other
    users' machines). Tests that assert ShellX's own names run against the
    sources with `swift test`, so a stale identity there fails that package.
    """
    entries = []
    for tests_dir in sorted((ROOT / "Packages").glob("*/*/Tests")):
        rel = tests_dir.relative_to(ROOT).as_posix() + "/"
        entries.append((rel, "package test fixtures; identity assertions run with swift test"))
    return entries


# (literal, reason): a hit is dropped when its line contains the literal. These
# names are not ShellX runtime names, so they stay even in otherwise clean files.
LINE_ALLOW = [
    ('"com.cmux.app"', "bundle id of cmux's iOS app (mobile pairing target); not a ShellX name"),
    ("cmux-ios-com.cmux.app", "URL scheme of cmux's iOS app (mobile pairing target)"),
    ('new Function("__cmux"', "parameter name of an in-page browser REPL function, not a hook marker"),
    ("cmux.socketListenerDidStart", "in-process NotificationCenter name (ruling R3)"),
    ("cmux.socketCommand", "in-process thread-dictionary key (ruling R3)"),
    ("cmux.socketControlPasswordDidChange", "in-process NotificationCenter name (ruling R3)"),
    ("cmux.socket-capability", "HKDF context label of the socket capability token; app and CLI derive the same value"),
    ("/tmp/cmux-cloud-cli.sock", "socket path baked into cmux cloud VM images; cloud is off (Task 5)"),
    ("/tmp/cmux/provision.log", "log path on cmux cloud VMs; cloud is off (Task 5)"),
    ('"/usr/local/bin/cmux"', "CLI path baked into cmux cloud VM images; cloud is off (Task 5)"),
    ("/usr/local/bin/cmux >/dev/null", "cloud VM bootstrap links its baked daemon to the baked CLI path (Task 5)"),
    ("[ ! -x /usr/local/bin/cmux ]", "cloud VM bootstrap links its baked daemon to the baked CLI path (Task 5)"),
    ("/tmp/cmux-ssh-[0-9]+", "recognizes the flat /tmp ControlPath of older cmux builds so ShellX never reuses it"),
    (".config/cmux/env", "env file on cmux cloud VMs written by their baked CLI; cloud is off (Task 5)"),
    (".cmux/bin/cmux", "cloud VM TUI client path (cloud is off); ~/.shellx/bin/shellx is the SSH relay CLI (Task 5B)"),
    ("$cmux_home/.config/cmux", "cloud VM bootstrap for the VM's baked cmux user; cloud is off (Task 5)"),
    ("! -f /etc/cmux/zsh-bootstrap-v5", "cloud VM bootstrap probes the VM's baked cmux CLI; cloud is off (Task 5)"),
]


def coexistence_offenders(pattern):
    hits = []
    allow = ALLOWLIST + _package_test_dirs()
    for hit in offenders(pattern, roots=ROOTS, allow=allow):
        path, number = hit.rsplit(":", 1)
        line = read(path).splitlines()[int(number) - 1]
        if not any(literal in line for literal, _reason in LINE_ALLOW):
            hits.append(f"{hit}: {line.strip()[:160]}")
    return hits


def build_settings(pbx, config_id):
    match = re.search(
        r"^\t\t" + re.escape(config_id) + r" /\* \w+ \*/ = \{\n(.*?)^\t\t\};",
        pbx,
        re.S | re.M,
    )
    if match is None:
        raise AssertionError(f"build configuration {config_id} not found")
    return match.group(1)


WRAPPERS = ["amp", "claude", "codex", "hermes-agent", "hermes-python", "pi"]


class ShellXCoexistenceTests(unittest.TestCase):
    def assertIn(self, member, container, msg=None):  # noqa: N802 - keep failure output short
        if member not in container:
            self.fail(msg or f"{member!r} not found")

    def assertNotIn(self, member, container, msg=None):  # noqa: N802
        if member in container:
            self.fail(msg or f"{member!r} unexpectedly found")

    def assertNotRegex(self, text, pattern, msg=None):  # noqa: N802
        match = re.search(pattern, text)
        if match:
            line = text[:match.start()].count("\n") + 1
            self.fail(msg or f"{pattern!r} matched at line {line}")

    def test_no_cmux_runtime_names(self):
        for pat in FORBIDDEN:
            self.assertEqual(coexistence_offenders(pat), [], pat)

    def test_no_cmux_app_support_dir_or_bundled_cli(self):
        # `<Application Support|state|cache>/cmux` directory names and `Resources/bin/cmux`.
        for pat in (r'appendingPathComponent\("cmux"(, isDirectory: (true|false))?\)', r"(?<![\w.])bin/cmux(?![-\w.])"):
            self.assertEqual(coexistence_offenders(pat), [], pat)

    def test_app_runs_and_types_the_shellx_cli(self):
        # The app finds its bundled CLI by name and types it into terminals (session
        # restore, welcome banner, wake hint); a bare `cmux` would reach an installed cmux.
        for pat in (r'forResource: "cmux", withExtension: nil, subdirectory: "bin"',
                    r'cliStartupExecutableToken = "cmux"', r'fallbackExecutable: "cmux"',
                    r'typedCommandText = " cmux ', r'"cmux focus-panel ', r'_cmux_wrapper_path "cmux"',
                    r"\bwhich cmux \|", r"command -v cmux\b", r"command -s cmux\b"):
            self.assertEqual(coexistence_offenders(pat), [], pat)
        self.assertIn('public static let cliStartupExecutableToken = "shellx"',
                      read("Packages/macOS/CMUXAgentLaunch/Sources/CMUXAgentLaunch/AgentRestoreLaunch.swift"))

    def test_agent_config_block_markers_are_shellx(self):
        # Hook blocks ShellX writes into third-party agent configs carry its own markers,
        # so installing or removing them never touches cmux's blocks.
        base = "Packages/macOS/CMUXAgentLaunch/Sources/CMUXAgentLaunch/"
        self.assertIn('"# shellx hooks rovodev begin"', read(base + "RovoDevHookConfig.swift"))
        self.assertIn('"# shellx hooks hermes-agent begin"', read(base + "HermesAgentHookConfig.swift"))
        self.assertIn('"# shellx-kimi-hooks-', read(base + "KimiCodeHookConfig.swift"))
        self.assertEqual(coexistence_offenders(r'"# cmux hooks (rovodev|hermes-agent) |"# cmux-kimi-hooks-'), [])

    def test_agent_integration_files_are_shellx(self):
        # Plugin/extension files, ownership markers, the OpenCode TUI package dir and
        # the Antigravity hook group are ShellX's own, so installing, refreshing or
        # removing ShellX's integration never adopts, rewrites or deletes cmux's.
        for pat in (r"cmux-session\.(js|ts)\b(?!on)", r"cmux-(omp|campfire)-session\.ts", r"cmux-feed\.js",
                    r"cmux-(pi|amp|omp|campfire)-session-extension-marker", r"cmux-opencode-[a-z-]*marker",
                    r"cmux-feed-plugin-marker", r'antigravityHookGroupName = "cmux"',
                    r'openCodeTUIPluginDirectoryName = "cmux"', r'"\./plugins/cmux"', r"plugins/cmux/",
                    r"\.cmux-session\.lock", r'Symbol\.for\("cmux\.(session|feed|pi)\.',
                    r'id: \\?"cmux\.(server|session|feed|tui)\\?"'):
            self.assertEqual(coexistence_offenders(pat), [], pat)
        catalog = read("CLI/CMUXCLI+AgentHookCatalog.swift")
        for config_file in ("plugins/shellx-session.js", "extensions/shellx-session.ts", "plugins/shellx-session.ts",
                            "extensions/shellx-omp-session.ts", "extensions/shellx-campfire-session.ts"):
            self.assertIn(f'configFile: "{config_file}"', catalog)

    def test_cua_skill_link_policy_manages_only_shellx_bundles(self):
        # ~/.claude/skills/cmux-cua links into a cmux bundle belong to cmux.
        policy = read("skills/cmux-cua/link-policy.sh")
        managed = policy.split("cmux_cua_skill_target_is_managed() {", 1)[1].split("\n}\n", 1)[0]
        self.assertNotIn("== com.cmuxterm", managed)
        self.assertIn('"$bundle_id" == pro.shellx.desktop.*', managed)
        self.assertIn("/Applications/ShellX*.app", managed)
        self.assertNotRegex(managed, r"/Applications/cmux\*\.app|/tmp/cmux-\*")

    def test_cli_product_is_shellx(self):
        pbx = read(PBXPROJ)
        self.assertRegex(pbx, r"PRODUCT_NAME = shellx;")
        # Both configurations of the cmux-cli target (module name stays internal).
        for config_id in ("B9000008A1B2C3D4E5F60719", "B9000009A1B2C3D4E5F60719"):
            settings = build_settings(pbx, config_id)
            self.assertIn("PRODUCT_NAME = shellx;", settings)
            self.assertIn("PRODUCT_MODULE_NAME = cmux_cli;", settings)
        # The product the "Copy CLI" phase puts in Contents/Resources/bin.
        self.assertIn(
            'B9000004A1B2C3D4E5F60719 /* shellx */ = {isa = PBXFileReference; explicitFileType = '
            '"compiled.mach-o.executable"; includeInIndex = 0; path = shellx; sourceTree = BUILT_PRODUCTS_DIR; };',
            pbx,
        )
        self.assertIn("/* shellx in Copy CLI */", pbx)

    def test_cli_install_path_is_shellx(self):
        installer = read("Sources/App/CmuxCLIPathInstaller.swift")
        self.assertIn('"/usr/local/bin/\\(ShellXBrand.cliName)"', installer)

    def test_agent_wrappers_are_shellx(self):
        pbx = read(PBXPROJ)
        for name in WRAPPERS:
            self.assertFalse((ROOT / f"Resources/bin/cmux-{name}-wrapper").exists(), name)
            self.assertTrue((ROOT / f"Resources/bin/shellx-{name}-wrapper").is_file(), name)
            self.assertIn(f'path = "Resources/bin/shellx-{name}-wrapper";', pbx)
        hits = offenders(r"cmux-(amp|claude|codex|hermes-agent|hermes-python|pi)-wrapper",
                         roots=ROOTS + ["CLI", "cmux.xcodeproj", "scripts", "tests", "cmuxTests", "cmuxCLITests",
                                        "daemon/remote"],
                         allow=[("tests/test_shellx_coexistence.py", "this guard names the old wrappers")])
        self.assertEqual(hits, [])

    def test_hook_marker_and_commands_are_shellx(self):
        wrapper = read("Resources/bin/shellx-claude-wrapper")
        self.assertIn('"__shellx":{"managed":"claude-hooks"', wrapper)
        self.assertNotIn("__cmux", wrapper)
        catalog = read("CLI/CMUXCLI+AgentHookCatalog.swift")
        self.assertIn('hookMarker: "shellx hooks codex"', catalog)
        self.assertNotRegex(catalog, r'hookMarker: "cmux hooks')
        definitions = read("CLI/CMUXCLI+AgentHookDefinitions.swift")
        self.assertIn('let command = "shellx hooks \\(def.name) \\(event.cmuxSubcommand)"', definitions)
        self.assertNotIn("command -v cmux ", definitions)
        self.assertIn('"/tmp/shellx-debug-\\(slug).sock"', definitions)

    def test_no_cmuxterm_state_dir(self):
        # Local `~/.cmuxterm` moved to `~/.shellx` (ruling R12), like the remote helper (Task 5B).
        pattern = r'(["/~]|\$HOME/|HOME%/}/)\.cmuxterm\b|"\.cmuxterm'
        self.assertEqual(coexistence_offenders(pattern), [])

    def test_local_dot_cmux_trees_are_shellx(self):
        # Codex hook scripts, SSH control sockets and the local tmux registry.
        self.assertIn('.appendingPathComponent(".shellx", isDirectory: true)',
                      read("CLI/CMUXCLI+CodexFireAndForgetHooks.swift"))
        self.assertIn('appendingPathComponent(".shellx")',
                      read("Packages/macOS/CmuxFoundation/Sources/CmuxFoundation/SSHControlSocketDirectory.swift"))
        self.assertIn('.appendingPathComponent(".shellx", isDirectory: true)', read("CLI/LocalTmuxSessionRegistry.swift"))

    def test_remote_bootstrap_uses_shellx_home(self):
        # Matches the shellx-remote helper (Task 5B): ~/.shellx/{relay,bin}, bin/shellx.
        for path in ("Sources/RemoteInteractiveShellBootstrapBuilder.swift",
                     "Sources/SessionRemoteWorkspaceSnapshot+Restore.swift"):
            text = read(path)
            self.assertNotRegex(text, r"\.cmux/", path)
            self.assertIn("$HOME/.shellx/bin/shellx", text)
        builder = read("Sources/RemoteInteractiveShellBootstrapBuilder.swift")
        self.assertIn('"mkdir -p \\"$HOME/.shellx/relay\\""', builder)
        self.assertIn("$HOME/.shellx/bin/shellx-codex-wrapper", builder)

    def test_keychain_services_are_shellx(self):
        self.assertIn('private static let service = "\\(ShellXBrand.bundleID).socket-control"', read("CLI/cmux.swift"))
        store = read("Packages/macOS/CmuxSettings/Sources/CmuxSettings/SocketControl/SocketControlPasswordStore.swift")
        self.assertNotIn("com.cmuxterm.app.socket-control", store)
        self.assertIn('"pro.shellx.desktop.surface-resume-approvals"', read("Sources/SessionPersistence.swift"))
        iroh = offenders(r"com\.cmuxterm\.iroh\.", roots=["Packages/Shared", "Packages/macOS", "Sources", "CLI"],
                         allow=_package_test_dirs())
        self.assertEqual(iroh, [])
        self.assertIn('"pro.shellx.desktop.iroh.endpoint-identity.v1"',
                      read("Packages/Shared/CmuxIrohTransport/Sources/CmuxIrohTransport/CmxIrohKeychainIdentityStore.swift"))
        push = offenders(r"ai\.manaflow\.cmux\.phone-push", roots=["Packages/macOS/CmuxPhonePush/Sources"], allow=[])
        self.assertEqual(push, [])
        self.assertIn('"pro.shellx.desktop.phone-push.shared-state"',
                      read("Packages/macOS/CmuxPhonePush/Sources/CmuxPhonePush/PhonePushSharedStateStorage.swift"))

    def test_exported_utis_are_shellx(self):
        with open(ROOT / "Resources/Info.plist", "rb") as f:
            info = plistlib.load(f)
        exported = [entry["UTTypeIdentifier"] for entry in info["UTExportedTypeDeclarations"]]
        ours = [uti for uti in exported if uti != "com.splittabbar.tabtransfer"]  # Bonsplit's own type
        self.assertTrue(ours)
        for uti in ours:
            self.assertTrue(uti.startswith("pro.shellx."), uti)

    def test_sidebar_extension_point_is_shellx(self):
        pbx = read(PBXPROJ)
        self.assertEqual(pbx.count("CMUX_SIDEBAR_EXTENSION_POINT_ID = pro.shellx.desktop.sidebar;"), 2)
        self.assertNotIn("com.cmuxterm.app.cmux.sidebar", pbx)
        point = read("Packages/macOS/CmuxExtensionKit/Sources/CmuxExtensionKit/Sidebar/CMUXSidebarExtensionPoint.swift")
        self.assertIn('public static let baseIdentifier = "pro.shellx.desktop.sidebar"', point)
        self.assertIn('POINT_ID="pro.shellx.desktop.sidebar"', read("scripts/write-sidebar-extension-point.sh"))
        self.assertIn('CMUX_SIDEBAR_EXTENSION_POINT_ID="${BUNDLE_ID}.sidebar"', read("scripts/reload.sh"))

    def test_scripting_suite_is_shellx(self):
        sdef = read("Resources/cmux.sdef")
        self.assertIn('<suite name="ShellX Suite"', sdef)
        self.assertNotIn('suite name="cmux', sdef)

    def test_runtime_names_come_from_shellx_brand(self):
        socket = read("Packages/macOS/CmuxSettings/Sources/CmuxSettings/SocketControl/SocketControlSettings.swift")
        self.assertIn('"\\(ShellXBrand.socketBaseName).sock"', socket)
        state = read("Packages/macOS/CmuxSettings/Sources/CmuxSettings/SocketControl/CmuxStateDirectory.swift")
        self.assertIn("public static let directoryName = ShellXBrand.configDirectoryName", state)
        location = read("Packages/macOS/CmuxSettings/Sources/CmuxSettings/Stores/CmuxConfigLocation.swift")
        self.assertIn('".config/\\(ShellXBrand.configDirectoryName)/\\(ShellXBrand.configFileName)"', location)


if __name__ == "__main__":
    unittest.main()
