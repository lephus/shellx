#!/usr/bin/env python3
"""ShellX remote: the bundled cmux-tui is built from this fork and shellx-core is
linked statically into the app.

Nothing ShellX builds or ships downloads Manaflow artifacts (files.cmux.com, the
manaflow-ai/cmux workflows), never enables cmux-tui's `iroh-transport`, and the
core's lock carries no TLS stack other than rustls + ring.
"""

import os
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# TODO(checkpoint 1): import from shellx_guard
# Copy of `read`/`offenders` from tests/shellx_guard.py (W1 Task 2), same contract.
_SKIPPED_DIRS = frozenset({
    ".git", ".build", ".swiftpm", "build", "DerivedData", "node_modules", "__pycache__",
    # Cargo build output (shellx-core/target) is not a ShellX source.
    "target",
})


def read(path):
    """The text of the repository file at `path`."""
    return (ROOT / path).read_text(encoding="utf-8")


def _is_allowed(rel_path, allow):
    for allowed_path, _reason in allow:
        if allowed_path.endswith("/"):
            if rel_path.startswith(allowed_path):
                return True
        elif rel_path == allowed_path:
            return True
    return False


def _text_lines(file_path):
    try:
        data = file_path.read_bytes()
    except OSError:
        return None
    if b"\0" in data[:8192]:
        return None
    try:
        return data.decode("utf-8").splitlines()
    except UnicodeDecodeError:
        return None


def _walk(root_path):
    if root_path.is_file():
        yield root_path
        return
    for dirpath, dirnames, filenames in os.walk(root_path):
        dirnames[:] = sorted(d for d in dirnames if d not in _SKIPPED_DIRS)
        for name in sorted(filenames):
            yield Path(dirpath) / name


def offenders(pattern, roots, allow):
    """`"path:line"` for every line matching `pattern` in text files under `roots`.

    `allow` is a list of `(path, reason)`; a path ending in "/" allows a directory.
    """
    for entry in allow:
        if len(entry) != 2 or not entry[1].strip():
            raise ValueError(f"allow entry needs (path, reason): {entry!r}")
    regex = re.compile(pattern)
    hits = []
    for root in roots:
        root_path = ROOT / root
        if not root_path.exists():
            continue
        for file_path in _walk(root_path):
            rel_path = file_path.relative_to(ROOT).as_posix()
            if _is_allowed(rel_path, allow):
                continue
            lines = _text_lines(file_path)
            if lines is None:
                continue
            for number, line in enumerate(lines, start=1):
                if regex.search(line):
                    hits.append(f"{rel_path}:{number}")
    return hits


class ShellXRemoteGuards(unittest.TestCase):
    # Report the custom message only: the default one prints all of project.pbxproj.
    longMessage = False

    def test_cmux_tui_is_built_from_this_fork(self):
        s = read("scripts/shellx/build-cmux-tui.sh")
        self.assertNotIn("files.cmux.com", s); self.assertNotIn("iroh-transport", s)

    def test_shellx_code_never_downloads_manaflow_artifacts(self):
        self.assertEqual(offenders(r"files\.cmux\.com|manaflow-ai/cmux/\.github", roots=["scripts/shellx", "shellx-core", "Sources/ShellX"], allow=[]), [])

    def test_core_lock_has_no_forbidden_crates(self):
        lock = read("shellx-core/Cargo.lock")
        for name in ["aws-lc-rs", "aws-lc-sys", "openssl", "openssl-sys", "native-tls", "iroh"]:
            self.assertNotIn(f'name = "{name}"', lock)

    def test_core_is_linked_statically(self):
        pbx = read("cmux.xcodeproj/project.pbxproj")
        self.assertIn("build-shellx-core.sh", pbx, "pbxproj has no build-shellx-core.sh phase")
        self.assertIn("-lshellx_core", pbx, "pbxproj does not link -lshellx_core")

    def test_remote_sources_import_no_cloud_stack(self):
        self.assertEqual(offenders(r"^\s*import (CmuxCloud|CmuxIrohTransport|CmuxIrxTransport|CMUXAuthCore|CmuxAuthRuntime)\b", roots=["Sources/ShellX/Remote"], allow=[]), [])

    def test_app_delegate_runs_the_remote_service_not_the_debug_bridge(self):
        s = read("Sources/AppDelegate.swift")
        self.assertNotIn("ShellXBridgeDebugStart", s, "the Task 11 DEBUG bridge start must be gone")
        self.assertEqual(offenders(r"ShellXBridgeDebugStart", roots=["Sources"], allow=[]), [])
        lines = s.splitlines()
        for call in ["ShellXRemoteService.shared.startIfEnabled()", "ShellXRemoteService.shared.stopForTermination()"]:
            hits = [line for line in lines if call in line]
            self.assertEqual(len(hits), 1, f"expected one {call} line")
            self.assertIn("// ShellX:", hits[0], f"{call} must be marked // ShellX:")
        terminate = s.index("func applicationWillTerminate(")
        self.assertLess(terminate, s.index("ShellXRemoteService.shared.stopForTermination()"))
        self.assertLess(s.index("ShellXRemoteService.shared.stopForTermination()"), s.index("\n    }", terminate))

    def test_remote_machines_flag_stays_off(self):
        s = read("Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXFeatures.swift")
        self.assertIn("public static let remoteMachines = false", s)
        self.assertIn("public static let upstreamDeviceMirroring = false", s)

    def test_dev_overrides_exist_only_in_debug_builds(self):
        # SHELLX_API_BASE, SHELLX_DEV_* and SHELLX_REMOTE_MACHINES are read only inside `#if DEBUG` blocks.
        for path in ["Sources/ShellX/Remote/ShellXRemoteService+App.swift", "Sources/ShellX/Remote/ShellXRemoteGate.swift"]:
            debug = []
            for number, line in enumerate(read(path).splitlines(), start=1):
                stripped = line.strip()
                if stripped.startswith("#if"):
                    debug.append(stripped == "#if DEBUG")
                elif stripped.startswith("#else") and debug:
                    debug[-1] = False
                elif stripped.startswith("#endif") and debug:
                    debug.pop()
                elif re.search(r'"SHELLX_(API_BASE|DEV_[A-Z]+|REMOTE_MACHINES)"', line):
                    self.assertTrue(debug and debug[-1], f"{path}:{number} reads a dev override outside #if DEBUG")


if __name__ == "__main__":
    unittest.main()
