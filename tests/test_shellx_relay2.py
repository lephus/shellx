#!/usr/bin/env python3
"""ShellX relay2 image: static guards for Dockerfile, dockerignore allowlist and CI workflow."""

import re
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCKERFILE = ROOT / "scripts/shellx/relay2/Dockerfile"
SCRIPT = ROOT / "scripts/shellx/relay2/source-tarball.sh"
DOCKERIGNORE = ROOT / "scripts/shellx/relay2/Dockerfile.dockerignore"
WORKFLOW = ROOT / ".github/workflows/shellx-relay2.yml"
CHECKOUT = "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2"


ALLOW = ["Cargo.toml", "Cargo.lock", "rust-toolchain.toml", "crates", "bindings", "vendor", "build-support"]


class ShellxRelay2Tests(unittest.TestCase):
    def test_dockerfile(self):
        text = DOCKERFILE.read_text()
        test_at = text.index("cargo test -p cmux-relay --locked")
        build_at = text.index("cargo build -p cmux-relay --locked --release")
        self.assertLess(test_at, build_at)
        self.assertIn("COPY cmux-tui/Cargo.toml cmux-tui/Cargo.lock cmux-tui/rust-toolchain.toml ./", text)
        for d in ["crates", "bindings", "vendor", "build-support"]:
            self.assertIn(f"COPY cmux-tui/{d} {d}\n", text)
        self.assertNotIn("COPY . ", text)
        self.assertNotIn("relays", text)
        self.assertIn("ARG CARGO_BUILD_JOBS=2", text)
        self.assertIn("ENV CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS}", text)
        self.assertIn("USER 10001:10001", text)
        self.assertIn("EXPOSE 8787", text)
        self.assertIn('ENTRYPOINT ["/usr/local/bin/cmux-relay"]', text)
        self.assertIn('CMD ["serve"]', text)

    def test_dockerignore_is_allowlist(self):
        lines = [
            line.strip()
            for line in DOCKERIGNORE.read_text().splitlines()
            if line.strip() and not line.strip().startswith("#")
        ]
        self.assertEqual(lines, ["*"] + [f"!cmux-tui/{p}" for p in ALLOW])

    def test_workflow(self):
        text = WORKFLOW.read_text()
        self.assertIn("contents: read", text)
        for bad in ["packages: write", "docker push", "docker login", "ghcr.io", "secrets.", "manaflow"]:
            self.assertNotIn(bad, text.lower() if bad == "manaflow" else text)
        self.assertEqual(
            re.findall(r"uses:\s*(\S+)", text),
            ["actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd"],
        )
        self.assertIn(CHECKOUT, text)
        self.assertIn("source-tarball.sh", text)
        self.assertIn('echo "::add-mask::$secret"', text)
        self.assertIn("timeout 20 docker run", text)
        self.assertIn("refusing a non-loopback open relay", text)
        for path in ["Cargo.toml", "rust-toolchain.toml", "vendor/**", "bindings/**", "build-support/**"]:
            self.assertIn(f"      - cmux-tui/{path}\n", text)
        self.assertIn("shellx-relay2:${{ github.sha }}", text)
        self.assertIn("    branches: [feat/relay-v2, main]\n", text)
        self.assertNotIn("l4-relay2", text)
        self.assertNotIn("shellx-pro", text)

    def test_image_source_label(self):
        text = DOCKERFILE.read_text()
        self.assertIn('org.opencontainers.image.source="https://github.com/lephus/shellx"', text)
        self.assertNotIn("shellx-pro", text)

    def test_source_tarball_contents(self):
        self.assertTrue(SCRIPT.exists() and SCRIPT.stat().st_mode & 0o111)
        tracked = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", str(SCRIPT)],
            capture_output=True,
        )
        if tracked.returncode != 0:
            self.skipTest("source-tarball.sh is not committed yet; archive tests committed content")
        with tempfile.TemporaryDirectory() as tmp:
            out = subprocess.run(
                [str(SCRIPT), "HEAD", tmp], capture_output=True, text=True, check=True
            ).stdout.split()
            path, digest, sha = out
            self.assertRegex(sha, r"^[0-9a-f]{40}$")
            self.assertRegex(digest, r"^[0-9a-f]{64}$")
            self.assertEqual(Path(path).name, f"relay2-src-{sha}.tar.gz")
            with tarfile.open(path) as tar:
                names = tar.getnames()
        self.assertIn(f"{sha}/cmux-tui/crates/cmux-relay/Cargo.toml", names)
        self.assertIn(f"{sha}/scripts/shellx/relay2/Dockerfile", names)
        for forbidden in ["cmux-tui/relays/", "web/", "relay/", "deploy/", "docs/", "workers/", "services/"]:
            self.assertEqual([n for n in names if n[len(sha) + 1 :].startswith(forbidden)], [], forbidden)


if __name__ == "__main__":
    unittest.main()
