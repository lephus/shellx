#!/usr/bin/env python3
"""ShellX builds and serves its own SSH remote helper (`shellx-remote`).

The helper never shares runtime names with an installed cmux on the same
remote host (`~/.shellx/...`, `/tmp/shellx-remote-<uid>/`, busybox name
`shellx`), and release manifests point at download.shellx.pro, not GitHub.
"""

import os
import re
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from shellx_guard import ROOT, offenders, read  # noqa: E402


BUILD_SCRIPT = "scripts/shellx/build_remote_daemon.sh"

# Swift code that names, uploads or locates the SSH daemon on the remote host.
SWIFT_DAEMON_ROOTS = [
    "Packages/macOS/CmuxRemoteSession/Sources",
    "Packages/macOS/CmuxRemoteDaemon/Sources",
    "Packages/macOS/CmuxRemoteWorkspace/Sources",
    "Packages/macOS/CmuxCore/Sources/CmuxCore/Remote",
    "Packages/macOS/CmuxFoundation/Sources/CmuxFoundation/RemoteBootstrapStagingCommandBuilder.swift",
    "Sources/RemoteTui",
]
# Lines that may still name cmux's helper, as (literal, reason). They sit in files
# that must otherwise stay clean, so they are filtered per line rather than
# allow-listing whole files with shellx_guard.offenders.
ALLOWED_SWIFT_LITERALS = [
    ("/run/cmuxd-remote.sock", "cloud VM images bake cmux's daemon socket; cloud is off (Task 5)"),
    ("/usr/local/bin/cmuxd-remote", "cloud VM images bake cmux's daemon binary; cloud is off (Task 5)"),
    ("cmuxd-remote is pre-baked", "doc comment on the cloud VM path; cloud is off (Task 5)"),
    ("Cloud VM's cmuxd-remote", "doc comment on the cloud VM endpoint; cloud is off (Task 5)"),
    ("cmuxd-remote baked into the Freestyle snapshot", "doc comment on the cloud VM hello; cloud is off (Task 5)"),
    ('name: "cmuxd-remote",', "hello name of the baked cloud VM daemon; cloud is off (Task 5)"),
    ('"./cmd/cmuxd-remote"', "Go package directory keeps upstream's internal name"),
]


def line_offenders(pattern, roots, allowed_literals):
    """offenders() hits whose line contains none of the allowed literals."""
    hits = []
    for hit in offenders(pattern, roots=roots, allow=[]):
        path, number = hit.rsplit(":", 1)
        line = read(path).splitlines()[int(number) - 1]
        if not any(literal in line for literal, _reason in allowed_literals):
            hits.append(hit)
    return hits


class ShellXRemoteDaemonTests(unittest.TestCase):
    def test_manifest_points_to_shellx_download_host(self):
        src = read("scripts/verify_remote_daemon_release.py")
        self.assertIn("download.shellx.pro/desktop/shellx-remote", src)
        self.assertNotIn("github.com/manaflow-ai", src)
        self.assertNotIn("github\\.com", src)

    def test_no_cmux_runtime_names_in_go_daemon(self):
        self.assertEqual(offenders(r"\.cmux/|\.shellx|cmuxd-remote-|/tmp/cmuxd", roots=["daemon/remote"], allow=[]), [])

    def test_go_daemon_uses_shellx_runtime_names(self):
        names = read("daemon/remote/cmd/cmuxd-remote/shellx_names.go")
        self.assertRegex(names, r'remoteHelperName\s*=\s*"shellx-remote"')
        self.assertRegex(names, r'remoteCLIName\s*=\s*"shellx"')
        self.assertRegex(names, r'remoteStateDirName\s*=\s*"\.shellx"')
        main = read("daemon/remote/cmd/cmuxd-remote/main.go")
        self.assertIn('filepath.Join(home, remoteStateDirName, "daemon")', main)
        self.assertIn('fmt.Sprintf(remoteHelperName+"-%d", os.Getuid())', main)
        self.assertIn("base == remoteCLIName", main)
        self.assertIn("strings.HasPrefix(base, remoteHelperName)", main)
        # Non-test Go sources never name cmux's home directory or helper.
        sources = [p.relative_to(ROOT).as_posix()
                   for p in (ROOT / "daemon/remote").rglob("*.go") if not p.name.endswith("_test.go")]
        self.assertEqual(offenders(r'"\.cmux"|"cmuxd-remote', roots=sources, allow=[]), [])

    def test_swift_daemon_install_paths_are_shellx(self):
        bootstrap = read("Packages/macOS/CmuxRemoteSession/Sources/CmuxRemoteSession/Session/"
                         "RemoteSessionCoordinator+Bootstrap.swift")
        self.assertIn(".shellx/bin/shellx-remote/", bootstrap)
        self.assertEqual(line_offenders(r"\.cmux/|\"\.cmux\"|cmuxd-remote", SWIFT_DAEMON_ROOTS,
                                        ALLOWED_SWIFT_LITERALS), [])

    def test_release_builds_ignore_the_dev_daemon_fallback(self):
        bootstrap = read("Packages/macOS/CmuxRemoteSession/Sources/CmuxRemoteSession/Session/"
                         "RemoteSessionCoordinator+Bootstrap.swift")
        gate = re.search(r"static let isDebugBuild: Bool = \{\s*#if DEBUG\s*true\s*#else\s*false\s*#endif",
                         bootstrap)
        self.assertIsNotNone(gate, "dev fallback must be compiled out of Release builds")
        self.assertRegex(bootstrap, r"guard isDebugBuild else \{ return false \}")

    def test_build_script_cross_builds_four_targets_into_dist(self):
        script = ROOT / BUILD_SCRIPT
        self.assertTrue(script.is_file(), BUILD_SCRIPT)
        self.assertTrue(script.stat().st_mode & stat.S_IXUSR, "build script must be executable")
        text = script.read_text(encoding="utf-8")
        for target in ("darwin arm64", "darwin amd64", "linux arm64", "linux amd64"):
            self.assertIn(target, text)
        self.assertIn("dist/shellx-remote", text)
        self.assertIn("checksums.txt", text)
        self.assertIn("https://download.shellx.pro/desktop/shellx-remote", text)

    def test_build_script_fails_clearly_without_go(self):
        with tempfile.TemporaryDirectory() as empty:
            env = {"PATH": "/usr/bin:/bin", "HOME": empty, "GO": os.path.join(empty, "missing-go")}
            result = subprocess.run(["/bin/bash", str(ROOT / BUILD_SCRIPT), "0.1.0"],
                                    capture_output=True, text=True, env=env, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("go", result.stderr.lower())
        self.assertIn("not found", result.stderr.lower())

    def test_dist_output_is_git_ignored(self):
        lines = [line.strip() for line in read(".gitignore").splitlines()]
        self.assertIn("/dist/", lines)


if __name__ == "__main__":
    unittest.main()
