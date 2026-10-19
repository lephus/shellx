#!/usr/bin/env python3
"""ShellX remote end to end: fake ShellX API + stock cmux-relay + the patched
cmux-tui daemon whose terminal is a fake Mac app over the virtual PTY socket,
and shellx-core-cli on two "machines" (host and viewer).

Proves sealed-invite enrollment, viewing, Vietnamese input, a relay outage
with 2 s tickets, and a daemon restart; and the GUI-free parts of plan Task 14:
a 30 s relay outage with production (120 s) tickets (Step 5, Review Focus 2),
a stale daemon stopped before start (Step 5, Review Focus 5), two concurrent
pairing requests of which only the approved one gets in (Step 6, Review Focus
3), and two host daemons side by side (Step 3, Review Focus 1). The harness is
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
import signal
import sys
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "shellx" / "remote-e2e"))

from harness import CoreError, Harness, Machine, is_socket, wait_until  # noqa: E402

BUILD = (
    "(cd cmux-tui && CARGO_INCREMENTAL=0 cargo build -p cmux-tui -p cmux-relay --locked) && "
    "(cd shellx-core && CARGO_INCREMENTAL=0 cargo build --workspace --locked), then run with "
    "SHELLX_E2E_BIN=$PWD/cmux-tui/target/debug SHELLX_E2E_CORE_BIN=$PWD/shellx-core/target/debug"
)
NEEDS = {"SHELLX_E2E_BIN": ("cmux-tui", "cmux-relay"), "SHELLX_E2E_CORE_BIN": ("shellx-core-cli", "shellx-fake-api")}
ENROLL_TEST = "test_enroll_via_sealed_invite_and_view"
# Seconds. A bounded upper limit for a probabilistic window, not a fix: with the register ticket
# at 2 s the daemon is reachable ~1 s in every ~6-7 s after a relay restart and the viewer's own
# jittered retry has to land in one (see test_reconnect_after_relay_restart_with_2s_tickets).
# It does not make "relay rejected the authenticated operation" go away; that error ends the
# client and is only handled by the harness restarting it (enrolled_connect_argv).
RECONNECT_BUDGET = 120
# Plan Task 14 Step 5: a 30 s outage, the viewer back within 35 s of the end of it. With 120 s
# tickets nothing expires during the outage; the daemon re-registers on its registration backoff
# (doubling to a 5 s cap, cmux-remote provider/relay.rs run_registration_loop) and the viewer's
# client, which stays up, redials on its own.
OUTAGE = 30
OUTAGE_RECOVERY_BUDGET = 35


def missing_binaries() -> list[str]:
    missing = []
    for env, names in NEEDS.items():
        base = os.environ.get(env, "")
        for name in names:
            if not base or not os.access(os.path.join(base, name), os.X_OK):
                missing.append(f"{env}/{name}")
    return missing


class E2ECase(unittest.TestCase):
    """One harness per test: relay and fake API, then `prepare` (machines, daemons, viewers).
    Every test ends with no invite, HMAC secret or password in any file, and the harness dir gone."""

    TICKET_TTL = 2

    def setUp(self):
        missing = missing_binaries()
        if missing:
            message = f"missing {', '.join(missing)}; build: {BUILD}"
            if os.environ.get("SHELLX_E2E_REQUIRE") == "1":
                self.fail(message)
            self.skipTest(message)
        self.h = Harness(os.environ["SHELLX_E2E_BIN"], os.environ["SHELLX_E2E_CORE_BIN"], ticket_ttl=self.TICKET_TTL)
        try:
            self.h.start_relay()
            self.h.start_api()
            self.prepare()
        except BaseException:
            self.h.dump_logs(sys.stderr)
            self.h.close()
            raise

    def prepare(self) -> None:
        raise NotImplementedError

    def signed_in(self, *names: str) -> list[Machine]:
        """Machines of the one e2e account, each logged in and registered (own slot)."""
        machines = [self.h.machine(name) for name in names]
        for machine in machines:
            machine.login()
            machine.register()
        return machines

    def view(self, viewer: Machine, host: Machine) -> str:
        """Pairs, enrolls and connects `viewer` to `host`, opens a workspace there; its terminal id."""
        inv = self.h.pair(viewer, host)
        self.h.connect_viewer(viewer, host)
        self.h.approve_pending(host, inv)
        self.h.viewer_cli("workspace", "create", "--name", "e2e", "--json")
        return self.h.first_terminal()

    def tearDown(self):
        if self._failed():
            self.h.dump_logs(sys.stderr)
        leaks = self.h.secret_leaks()  # before close removes the dir; every test, every file
        self.h.close()
        self.assertEqual(leaks, [], "invite URI, HMAC secret or account password found in these files")
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


class RemoteE2E(E2ECase):
    def prepare(self) -> None:
        self.host, self.viewer = self.signed_in("host", "viewer")
        self.h.start_host_daemon(self.host)
        if self._testMethodName != ENROLL_TEST:
            self.term = self.view(self.viewer, self.host)

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
        started = time.monotonic()
        # Upstream cmux, not the harness, sets the pace: the daemon's relay lease ends at its
        # ticket's whole-second expiry (1-2 s here) and it re-registers only after a registration
        # backoff that doubles to 5 s and never resets (cmux-remote provider/relay.rs
        # run_registration_loop), so with 2 s tickets it is reachable ~1 s in every ~6-7 s. A new
        # viewer connection must land in such a window from the client's own 0-5 s jittered retry.
        # 45 s was not always enough: CI run 39175354906 ended with the viewer still dialling.
        self.assertTrue(wait_until(RECONNECT_BUDGET, lambda: self.h.viewer_ok("terminal", "list", "--json")),
                        f"viewer did not reconnect within {RECONNECT_BUDGET} s")
        self.h.note(f"viewer reconnected {time.monotonic() - started:.1f} s after the relay restart")
        for log in self.h.logs(): self.assertNotRegex(log, r"v2\.[A-Za-z0-9_-]{20,}\.")   # no ticket in any log

    def test_enrolled_device_reconnects_after_daemon_restart(self):
        self.h.restart_host_daemon(self.host)         # same --remote-state-dir, fresh --ephemeral mux
        self.assertTrue(wait_until(45, lambda: self.h.viewer_ok("workspace", "list", "--json")))
        self.assertEqual(self.h.host_cli(self.host, "remote", "enroll", "pending", "--json"), [])

    def test_stale_daemon_is_stopped_before_start(self):                     # plan Step 5, Review Focus 5
        # A force-quit or crashed app leaves its daemon running (`server start` has no
        # --exit-with-parent). The next launch runs the app's spawn: RemoteCommandLine.serverStop
        # (`server stop --force` on the session's mux socket), then serverStart.
        stale = self.h.abandon_host_daemon(self.host)
        self.assertEqual(self.h.session_daemon_pids(self.host), [stale.pid])
        self.h.start_host_daemon(self.host)
        self.assertEqual(self.host.last_stop_rc, 0)
        self.assertTrue(wait_until(15, lambda: stale.poll() is not None, 0.2), "the stale daemon is still running")
        self.assertEqual(self.h.session_daemon_pids(self.host), [self.h.daemon_proc(self.host).pid])
        self.assertTrue(wait_until(45, lambda: self.h.viewer_ok("workspace", "list", "--json")))

        # kill -9: nothing stops it cleanly, its mux, admin and link socket files stay behind.
        killed = self.h.abandon_host_daemon(self.host, kill=True)
        self.assertEqual(killed.returncode, -signal.SIGKILL)
        self.assertEqual(self.h.session_daemon_pids(self.host), [])
        self.h.start_host_daemon(self.host)
        self.assertEqual(self.host.last_stop_rc, 0)                    # `not_running`
        self.assertEqual(self.h.session_daemon_pids(self.host), [self.h.daemon_proc(self.host).pid])
        self.assertTrue(wait_until(45, lambda: self.h.viewer_ok("workspace", "list", "--json")))
        self.h.viewer_cli("workspace", "create", "--name", "after-kill", "--json")
        self.assertIn("SHELLX-FAKE-APP", self.h.viewer_cli("terminal", self.h.first_terminal(), "screen", "read"))
        self.assertEqual(self.h.host_cli(self.host, "remote", "enroll", "pending", "--json"), [])
        devices = self.h.host_cli(self.host, "remote", "enroll", "devices", "--json")
        self.assertEqual([d["name"] for d in devices], [self.viewer.session])   # still enrolled, no new pairing


class ProductionTicketOutage(E2ECase):
    TICKET_TTL = 120                                                         # production ticket lifetime

    def prepare(self) -> None:
        self.host, self.viewer = self.signed_in("host", "viewer")
        self.h.start_host_daemon(self.host)
        self.term = self.view(self.viewer, self.host)

    def test_thirty_second_relay_outage_recovers_with_long_tickets(self):  # plan Step 5, Review Focus 2
        self.h.stop_relay()
        stopped = time.monotonic()
        # The link is really down: the viewer's client cannot answer from the host.
        self.assertTrue(wait_until(20, lambda: not self.h.viewer_ok("terminal", "list", "--json")),
                        "the viewer still answers with the relay down")
        time.sleep(max(0.0, OUTAGE - (time.monotonic() - stopped)))
        self.h.start_relay()                                                 # same port + secret
        started = time.monotonic()
        back = wait_until(OUTAGE_RECOVERY_BUDGET, lambda: self.h.viewer_ok("terminal", "list", "--json"))
        elapsed = time.monotonic() - started
        self.h.note(f"viewer back {elapsed:.1f} s after a {OUTAGE} s relay outage (120 s tickets)")
        print(f"[e2e] viewer back {elapsed:.1f} s after the relay restart (budget {OUTAGE_RECOVERY_BUDGET} s)",
              file=sys.stderr)
        self.assertTrue(back and elapsed <= OUTAGE_RECOVERY_BUDGET,
                        f"viewer not back within {OUTAGE_RECOVERY_BUDGET} s of the relay restart ({elapsed:.1f} s)")
        self.assertIn("SHELLX-FAKE-APP", self.h.viewer_cli("terminal", self.term, "screen", "read"))


class ConcurrentPairing(E2ECase):
    def prepare(self) -> None:
        self.host, self.a, self.b = self.signed_in("host", "viewera", "viewerb")
        self.h.start_host_daemon(self.host)

    def test_concurrent_requests_only_approved_viewer_gets_in(self):        # plan Step 6, Review Focus 3
        with ThreadPoolExecutor(2) as pool:
            req_a, req_b = pool.map(lambda viewer: viewer.core("pair.request", to_machine_id=self.host.machine_id),
                                    (self.a, self.b))
        pending = self.host.core("pair.pending")["pairings"]
        self.assertEqual(sorted(p["pairing_id"] for p in pending), sorted([req_a["pairing_id"], req_b["pairing_id"]]))
        item_a = self.h.pending_item(self.host, req_a, pending)              # each matches what its viewer shows
        item_b = self.h.pending_item(self.host, req_b, pending)
        self.assertNotEqual(item_a["code"], item_b["code"])
        self.assertNotEqual(item_a["fingerprint"], item_b["fingerprint"])

        inv = self.h.approve_pairing(self.a, self.host, req_a, item_a)        # Approve on A's request only
        self.assertEqual(self.b.core("pair.poll", pairing_id=req_b["pairing_id"], write_invite_to="invite.uri"),
                         {"status": "pending"})
        self.assertFalse((self.b.core_dir / "tickets" / "invite.uri").exists())   # B has no invite
        with self.assertRaises(CoreError) as refused:                         # nor a ticket to the host
            self.b.core("tickets.mint", permission="connect", target_machine_id=self.host.machine_id,
                        write_to="connect.ticket")
        self.assertEqual(refused.exception.code, "not_granted")

        self.h.connect_viewer(self.a, self.host)
        self.assertEqual([p["invitation_id"] for p in self.h.host_cli(self.host, "remote", "enroll", "pending", "--json")],
                         [inv])
        self.h.approve_pending(self.host, inv, viewer=self.a)                # the daemon approves only A's invitation

        # B runs the app's connect without an invite, even holding a valid connect ticket for the
        # host's slot (worst case, e.g. a leaked file): it knows no daemon, so it never enrolls.
        leaked = self.host.core("tickets.mint", permission="connect", target_machine_id=self.host.machine_id,
                                write_to="leaked-connect.ticket")["path"]
        try:
            rc = self.h.try_uninvited_connect(self.b, self.host, leaked)
        finally:
            os.unlink(leaked)
        self.assertIsNotNone(rc, "B's uninvited connect was still running")
        self.assertNotEqual(rc, 0)
        self.assertFalse(self.h.viewer_ok("workspace", "list", "--json", viewer=self.b))
        self.assertEqual(self.h.host_cli(self.host, "remote", "enroll", "pending", "--json"), [])
        devices = self.h.host_cli(self.host, "remote", "enroll", "devices", "--json")
        self.assertEqual([d["name"] for d in devices], [self.a.session])

        self.h.viewer_cli("workspace", "create", "--name", "e2e", "--json", viewer=self.a)
        term = self.h.first_terminal(viewer=self.a)
        self.assertIn("SHELLX-FAKE-APP", self.h.viewer_cli("terminal", term, "screen", "read", viewer=self.a))
        self.assertEqual(self.b.core("pair.poll", pairing_id=req_b["pairing_id"]), {"status": "pending"})


class TwoHosts(E2ECase):
    def prepare(self) -> None:
        self.host1, self.host2, self.viewer = self.signed_in("host1", "host2", "viewer")
        self.h.start_host_daemon(self.host1)
        self.h.start_host_daemon(self.host2)

    def test_two_host_daemons_coexist_with_distinct_paths(self):            # plan Step 3, Review Focus 1
        h1, h2 = self.host1, self.host2
        listed = {m["machine_id"] for m in self.viewer.core("machines.list")["machines"]}
        self.assertLessEqual({h1.machine_id, h2.machine_id}, listed)          # one account, two machines
        self.assertNotEqual(h1.slot, h2.slot)
        self.assertNotEqual(h1.session, h2.session)
        self.assertFalse({str(p) for p in h1.paths().values()} & {str(p) for p in h2.paths().values()})
        for host in (h1, h2):                                                 # both daemons up at once
            daemon = self.h.daemon_proc(host)
            self.assertIsNone(daemon.poll(), host.name)
            self.assertEqual(self.h.session_daemon_pids(host), [daemon.pid], host.name)
            for key in ("mux_sock", "bridge_sock", "admin_sock", "link_sock"):
                self.assertTrue(is_socket(host.paths()[key]), f"{host.name}.{key}")
        status1, status2 = (self.h.host_cli(host, "remote", "enroll", "status", "--json") for host in (h1, h2))
        self.assertNotEqual(status1["daemon_fingerprint"], status2["daemon_fingerprint"])

        term = self.view(self.viewer, h1)
        self.assertEqual(self.h.host_cli(h2, "remote", "enroll", "devices", "--json"), [])
        screen = self.h.viewer_cli("terminal", term, "screen", "read")
        self.assertIn(f"SHELLX-FAKE-APP {h1.session} ready", screen)        # host 1's app ...
        self.assertNotIn(h2.session, screen)                                  # ... not host 2's
        self.h.viewer_cli("terminal", term, "write", "--text", "host-one-only\r")
        self.assertIn(b"host-one-only", self.h.fake_app_input(h1))
        self.assertNotIn(b"host-one-only", self.h.fake_app_input(h2, timeout=2))


if __name__ == "__main__":
    unittest.main()
