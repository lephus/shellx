#!/usr/bin/env python3
"""Exercise the real release producer, checksums, and native SSH hello protocol.

ShellX builds its SSH helper with scripts/shellx/build_remote_daemon.sh and
serves it from download.shellx.pro (see scripts/verify_remote_daemon_release.py).
"""

import hashlib
import json
import platform
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
TARGETS = {("darwin", "arm64"), ("darwin", "amd64"),
           ("linux", "arm64"), ("linux", "amd64")}


class RemoteDaemonReleaseTests(unittest.TestCase):
    def test_release_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            version = "0.64.25"
            subprocess.run([str(ROOT / "scripts/shellx/build_remote_daemon.sh"), version,
                            "--output-dir", directory], check=True)
            manifest = json.loads((output / "manifest.json").read_text())
            self.assertEqual(manifest["appVersion"], version)
            self.assertEqual(manifest["releaseTag"], f"v{version}")
            self.assertEqual(manifest["schemaVersion"], 1)
            self.assertEqual(len(manifest["entries"]), len(TARGETS))
            self.assertEqual({(e["goOS"], e["goArch"]) for e in manifest["entries"]}, TARGETS)
            base_url = f"https://download.shellx.pro/desktop/shellx-remote/{version}"
            self.assertEqual(manifest["releaseURL"], base_url)
            self.assertEqual(manifest["checksumsAssetName"], "checksums.txt")
            self.assertEqual(manifest["checksumsURL"], f"{base_url}/checksums.txt")
            checksums = dict(line.split()[::-1] for line in (output / "checksums.txt").read_text().splitlines())
            self.assertEqual(len(checksums), len(TARGETS))
            self.assertEqual(sorted(p.name for p in output.iterdir()),
                             sorted(["checksums.txt", "manifest.json"] + list(checksums)))
            for entry in manifest["entries"]:
                name = f"shellx-remote-{entry['goOS']}-{entry['goArch']}"
                self.assertEqual(entry["assetName"], name)
                self.assertEqual(entry["downloadURL"], f"{base_url}/{name}")
                binary = output / name
                self.assertGreater(binary.stat().st_size, 0)
                digest = hashlib.sha256(binary.read_bytes()).hexdigest()
                self.assertEqual(entry["sha256"], digest)
                self.assertEqual(checksums[name], digest)

            # Run the artifact, rather than accepting an arbitrary file with a hash.
            go_os = {"Darwin": "darwin", "Linux": "linux"}[platform.system()]
            go_arch = {"arm64": "arm64", "aarch64": "arm64", "x86_64": "amd64"}[platform.machine()]
            binary = output / f"shellx-remote-{go_os}-{go_arch}"
            hello = subprocess.run([str(binary), "serve", "--stdio"],
                                   input='{"id":1,"method":"hello","params":{}}\n',
                                   capture_output=True, text=True, check=True, timeout=15)
            response = json.loads(hello.stdout.splitlines()[0])
            self.assertTrue(response["ok"], response)
            self.assertEqual(response["result"]["name"], "shellx-remote")
            self.assertEqual(response["result"]["version"], version)
            required = {"proxy.stream.push", "pty.session", "pty.session.token",
                        "pty.session.persistent_daemon", "pty.write.notification",
                        "pty.resize.notification", "pty.attach.cancel"}
            self.assertTrue(required <= set(response["result"]["capabilities"]), response)


if __name__ == "__main__":
    unittest.main()
