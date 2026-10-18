#!/usr/bin/env python3
"""ShellX remote end to end: fake ShellX API + stock cmux-relay + the patched
cmux-tui daemon whose terminal is a fake Mac app over the virtual PTY socket,
and shellx-core-cli on two "machines" (host and viewer).

Proves sealed-invite enrollment, viewing, Vietnamese input, a relay outage
with 2 s tickets, and a daemon restart. The harness is
scripts/shellx/remote-e2e/harness.py; CI runs this file from
.github/workflows/shellx-remote.yml.

Needs built binaries; nothing is built here:
    SHELLX_E2E_BIN       cmux-tui target dir with cmux-tui and cmux-relay
    SHELLX_E2E_CORE_BIN  shellx-core target dir with shellx-core-cli and shellx-fake-api
Without them every test is skipped, unless SHELLX_E2E_REQUIRE=1 (CI), which
turns the skip into a failure.
"""

from __future__ import annotations

import os
import sys
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "shellx" / "remote-e2e"))

from harness import Harness, wait_until  # noqa: E402

BUILD = (
    "(cd cmux-tui && CARGO_INCREMENTAL=0 cargo build -p cmux-tui -p cmux-relay --locked) && "
    "(cd shellx-core && CARGO_INCREMENTAL=0 cargo build --workspace --locked), then run with "
    "SHELLX_E2E_BIN=$PWD/cmux-tui/target/debug SHELLX_E2E_CORE_BIN=$PWD/shellx-core/target/debug"
)
NEEDS = {"SHELLX_E2E_BIN": ("cmux-tui", "cmux-relay"), "SHELLX_E2E_CORE_BIN": ("shellx-core-cli", "shellx-fake-api")}
ENROLL_TEST = "test_enroll_via_sealed_invite_and_view"


def missing_binaries() -> list[str]:
    missing = []
    for env, names in NEEDS.items():
        base = os.environ.get(env, "")
        for name in names:
            if not base or not os.access(os.path.join(base, name), os.X_OK):
                missing.append(f"{env}/{name}")
    return missing


class RemoteE2E(unittest.TestCase):
    def setUp(self):
        missing = missing_binaries()
        if missing:
            message = f"missing {', '.join(missing)}; build: {BUILD}"
            if os.environ.get("SHELLX_E2E_REQUIRE") == "1":
                self.fail(message)
            self.skipTest(message)
        self.h = Harness(os.environ["SHELLX_E2E_BIN"], os.environ["SHELLX_E2E_CORE_BIN"], ticket_ttl=2)
        try:
            self.h.start_relay()
            self.h.start_api()
            self.host = self.h.machine("host")
            self.viewer = self.h.machine("viewer")
            for machine in (self.host, self.viewer):
                machine.login()
                machine.register()
            self.h.start_host_daemon(self.host)
            if self._testMethodName != ENROLL_TEST:
                inv = self.h.pair(self.viewer, self.host)
                self.h.connect_viewer(self.viewer, self.host)
                self.h.approve_pending(self.host, inv)
                self.h.viewer_cli("workspace", "create", "--name", "e2e", "--json")
                self.term = self.h.first_terminal()
        except BaseException:
            self.h.dump_logs(sys.stderr)
            self.h.close()
            raise

    def tearDown(self):
        if self._failed():
            self.h.dump_logs(sys.stderr)
        self.h.close()
        self.assertFalse(os.path.exists(self.h.root), "harness dir (and every temp secret) must be removed")

    def _failed(self) -> bool:
        outcome = getattr(self, "_outcome", None)
        errors = getattr(outcome, "errors", None)  # Python <= 3.10 reports after tearDown
        if errors is not None:
            return any(exc_info is not None for _, exc_info in errors)
        result = getattr(outcome, "result", None)  # Python >= 3.11 reports at once
        if result is None:
            return False
        return any(test is self for test, _ in list(result.failures) + list(result.errors))

    def test_enroll_via_sealed_invite_and_view(self):
        inv = self.h.pair(self.viewer, self.host); self.h.connect_viewer(self.viewer, self.host)
        pending = self.h.host_cli(self.host, "remote", "enroll", "pending", "--json")
        self.assertEqual([p["invitation_id"] for p in pending], [inv])        # only ours
        self.h.approve_pending(self.host, inv)
        ws = self.h.viewer_cli("workspace", "create", "--name", "e2e", "--json")
        term = self.h.first_terminal()
        self.assertIn("SHELLX-FAKE-APP", self.h.viewer_cli("terminal", term, "screen", "read"))

    def test_vietnamese_round_trip(self):                                    # Review Focus 4
        self.h.viewer_cli("terminal", self.term, "write", "--text", "tiếng Việt\r")
        self.assertTrue(self.h.fake_app_input().endswith(bytes.fromhex("7469e1babf6e672056 69e1bb8774 0d".replace(" ", ""))))

    def test_reconnect_after_relay_restart_with_2s_tickets(self):            # Review Focus 2 (ticket_ttl=2)
        self.h.stop_relay(); time.sleep(5)           # every ticket written before the outage has expired
        self.h.start_relay()                          # same port + secret
        self.assertTrue(wait_until(45, lambda: self.h.viewer_ok("terminal", "list", "--json")))
        for log in self.h.logs(): self.assertNotRegex(log, r"v2\.[A-Za-z0-9_-]{20,}\.")   # no ticket in any log

    def test_enrolled_device_reconnects_after_daemon_restart(self):
        self.h.restart_host_daemon(self.host)         # same --remote-state-dir, fresh --ephemeral mux
        self.assertTrue(wait_until(45, lambda: self.h.viewer_ok("workspace", "list", "--json")))
        self.assertEqual(self.h.host_cli(self.host, "remote", "enroll", "pending", "--json"), [])


if __name__ == "__main__":
    unittest.main()
