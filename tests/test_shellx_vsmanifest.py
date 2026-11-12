"""windows/cross/vsmanifest.py against a small manifest (no network: VSMANIFEST_CACHE)."""
import json
import os
import subprocess
import sys
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(REPO, "windows", "cross", "vsmanifest.py")
CAB = "2630bae9681db6a9f6722366f47d055c.cab"
# The Dockerfile asks for one cab by its name behind a path separator: "\\<cab>$".
CAB_REGEX = "\\\\" + CAB + "$"


def listing(file_names, regex):
    manifest = {
        "packages": [
            {
                "id": "Win11SDK_10.0.26100",
                "payloads": [{"fileName": n, "size": 1} for n in file_names],
            }
        ]
    }
    with tempfile.TemporaryDirectory() as tmp:
        cache = os.path.join(tmp, "vsmanifest.json")
        with open(cache, "w") as f:
            json.dump(manifest, f)
        out = subprocess.run(
            [sys.executable, "-I", SCRIPT, "list", regex],
            env={**os.environ, "VSMANIFEST_CACHE": cache},
            capture_output=True,
            text=True,
            check=True,
        )
    return out.stdout.splitlines()[1:]


class PayloadNames(unittest.TestCase):
    def test_a_backslash_path_matches_the_dockerfile_regex(self):
        self.assertEqual(listing(["Installers\\" + CAB], CAB_REGEX), ["Installers\\" + CAB + " 1"])

    def test_a_forward_slash_path_matches_the_same_regex(self):
        # Microsoft's manifest switched to "/" (seen 2026-11-12): the cabs were no longer found,
        # so the image build had no fxc.exe.
        self.assertEqual(listing(["Installers/" + CAB], CAB_REGEX), ["Installers/" + CAB + " 1"])

    def test_another_cab_does_not_match(self):
        self.assertEqual(listing(["Installers/x" + CAB, "Installers/other.cab"], CAB_REGEX), [])


if __name__ == "__main__":
    unittest.main()
