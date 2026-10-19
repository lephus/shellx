#!/usr/bin/env python3
"""Binary-free tests of the pure parts of the remote e2e harness
(scripts/shellx/remote-e2e/harness.py).

The e2e itself needs built binaries and runs in CI (shellx-remote.yml); these
pin what it must keep: the two `remote connect` argvs, the ticket refresh
schedule and the "connected" line.
    python3 tests/test_shellx_remote_harness.py
"""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "shellx" / "remote-e2e"))

import harness  # noqa: E402

CMUX = "/bin/cmux-tui"
ROUTE = "relay+ws://127.0.0.1:4242/v1/relay"
ORIGIN = "relay+ws://127.0.0.1:4242"
SLOT = "slot-1"
TICKET = "/h/core/tickets/connect.ticket"
FINGERPRINT = "ab" * 32
STATE, SOCKET, DEVICE = "/h/c", "/h/run/client.sock", "e2e-viewer"


def invite_argv(route: str = ROUTE) -> list[str]:
    return harness.invite_connect_argv(CMUX, route, SLOT, TICKET, "/h/invite.uri", STATE, SOCKET, DEVICE)


def enrolled_argv(route: str = ROUTE) -> list[str]:
    return harness.enrolled_connect_argv(CMUX, route, SLOT, TICKET, FINGERPRINT, STATE, SOCKET, DEVICE)


def option_values(argv: list[str], name: str) -> list[str]:
    return [argv[i + 1] for i, a in enumerate(argv) if a == name]


class InviteArgv(unittest.TestCase):
    def test_positional_route_first_then_two_relay_route_triples(self):
        argv = invite_argv()
        self.assertEqual(argv[:4], [CMUX, "remote", "connect", ROUTE])
        self.assertEqual(argv[4:16], [
            "--relay-route", ROUTE, "--relay-slot", SLOT, "--relay-ticket-file", TICKET,
            "--relay-route", ORIGIN, "--relay-slot", SLOT, "--relay-ticket-file", TICKET])
        # Exactly two triples, the full route and the origin, each with its own slot and file.
        self.assertEqual(option_values(argv, "--relay-route"), [ROUTE, ORIGIN])
        self.assertEqual(option_values(argv, "--relay-slot"), [SLOT, SLOT])
        self.assertEqual(option_values(argv, "--relay-ticket-file"), [TICKET, TICKET])

    def test_invite_and_app_flags_but_no_daemon_pin(self):
        argv = invite_argv()
        self.assertEqual(option_values(argv, "--invite-file"), ["/h/invite.uri"])
        self.assertNotIn("--daemon", argv)
        for flag in ("--headless", "--json", "--exit-with-parent"):
            self.assertEqual(argv.count(flag), 1, flag)
        self.assertEqual(option_values(argv, "--state-dir"), [STATE])
        self.assertEqual(option_values(argv, "--local-socket"), [SOCKET])
        self.assertEqual(option_values(argv, "--device-name"), [DEVICE])

    def test_a_route_without_a_path_gets_one_triple(self):
        argv = invite_argv(ORIGIN)
        self.assertEqual(option_values(argv, "--relay-route"), [ORIGIN])

    def test_no_secret_in_argv(self):
        # Paths only: the ticket and the invite stay in files.
        self.assertFalse(any(harness.TICKET_RE.search(a) or harness.INVITE_RE.search(a) for a in invite_argv()))


class EnrolledArgv(unittest.TestCase):
    def test_one_credential_no_relay_route(self):
        argv = enrolled_argv()
        # cmux refuses a relay credential route that is not a route candidate, and an enrolled
        # restart has a single candidate: the positional route.
        self.assertNotIn("--relay-route", argv)
        self.assertEqual(option_values(argv, "--relay-slot"), [SLOT])
        self.assertEqual(option_values(argv, "--relay-ticket-file"), [TICKET])
        self.assertNotIn("--invite-file", argv)
        self.assertEqual(option_values(argv, "--daemon"), [FINGERPRINT])
        self.assertEqual(argv.count(ROUTE), 1)
        self.assertNotIn(ORIGIN, argv)

    def test_positional_route_first(self):
        self.assertEqual(enrolled_argv()[:7], [CMUX, "remote", "connect", ROUTE,
                                               "--relay-slot", SLOT, "--relay-ticket-file"])

    def test_byte_for_byte_the_swift_argv(self):
        # RemoteCommandLine.connect (RemoteCommandLine.swift) with an enrolled record and no invite.
        self.assertEqual(enrolled_argv(), [
            CMUX, "remote", "connect", ROUTE, "--relay-slot", SLOT, "--relay-ticket-file", TICKET,
            "--state-dir", STATE, "--local-socket", SOCKET, "--headless", "--json", "--exit-with-parent",
            "--device-name", DEVICE, "--daemon", FINGERPRINT])

    def test_flags_follow_the_swift_source(self):
        source = (ROOT / "Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/RemoteCommandLine.swift").read_text()
        body = source[source.index("public static func connect("):]
        body = body[:body.index("/// Pane patience")]
        swift_flags = re.findall(r'"(--[a-z-]+)"', body)
        harness_flags = [a for a in enrolled_argv() if a.startswith("--")]
        self.assertEqual([f for f in swift_flags if f != "--invite-file"], harness_flags)


class RefreshSchedule(unittest.TestCase):
    def test_half_life_when_mints_are_fast(self):
        self.assertAlmostEqual(harness.refresh_delay(2.0, [0.1]), 1.0)

    def test_starts_early_enough_for_the_slowest_recent_mint(self):
        # 2 s of life, a mint that takes 1 s: leave REFRESH_MARGIN of life when it finishes.
        delay = harness.refresh_delay(2.0, [0.2, 1.0, 0.3])
        self.assertAlmostEqual(delay, 2.0 - 1.0 - harness.REFRESH_MARGIN)
        self.assertGreaterEqual(2.0 - (delay + 1.0), harness.REFRESH_MARGIN - 1e-9)

    def test_never_sooner_than_the_floor(self):
        self.assertEqual(harness.refresh_delay(1.0, [1.5]), harness.REFRESH_FLOOR)
        self.assertEqual(harness.refresh_delay(-3.0, [0.1]), harness.REFRESH_FLOOR)

    def test_no_latency_yet(self):
        self.assertAlmostEqual(harness.refresh_delay(2.0, []), 1.0)

    def test_the_cold_first_mint_is_dropped_after_the_second(self):
        cold = 1.5
        self.assertEqual(harness.refresh_delay(1.5, [cold]), harness.REFRESH_FLOOR)   # first wait: conservative
        recent = harness.next_latencies([cold], 0.2, cold=True)
        self.assertEqual(recent, [0.2])
        self.assertGreater(harness.refresh_delay(1.5, recent), 0.5)                    # not back to back

    def test_window_keeps_the_latest_mints(self):
        recent: list[float] = []
        for latency in range(1, 9):
            recent = harness.next_latencies(recent, float(latency), cold=False)
        self.assertEqual(recent, [4.0, 5.0, 6.0, 7.0, 8.0])
        self.assertEqual(len(recent), harness.LATENCY_WINDOW)

    def test_mint_stats(self):
        stats = harness.MintStats(1.5)
        stats.record(0.2)
        stats.record(0.4)
        self.assertEqual((stats.count, stats.first, stats.maximum), (3, 1.5, 1.5))
        stats.record(2.5)
        self.assertEqual(stats.maximum, 2.5)


class SnapshotLine(unittest.TestCase):
    SNAPSHOT = ('{"connection":{"state":"connected","generation":1},"event":"connection-snapshot",'
                '"local_socket":"/h/run/client.sock"}')

    def test_the_connection_snapshot_event(self):
        self.assertTrue(harness.is_snapshot_line(self.SNAPSHOT))

    def test_other_lines_are_not_a_snapshot(self):
        for line in ("/h/run/client.sock", "", "{", "{not json}", "[1]", '"connection-snapshot"',
                     '{"event":"other"}', '{"local_socket":"/h/run/client.sock"}',
                     ' ' + self.SNAPSHOT, "error: relay rejected the authenticated operation"):
            self.assertFalse(harness.is_snapshot_line(line), line)

    def test_the_socket_path_alone_is_not_connected(self):
        # The old check looked for the socket path anywhere in the log.
        self.assertFalse(harness.log_has_snapshot("started /h/run/client.sock\n"))

    def test_log_with_a_snapshot_line(self):
        self.assertTrue(harness.log_has_snapshot(f"noise\n{self.SNAPSHOT}\nmore\n"))
        self.assertFalse(harness.log_has_snapshot("noise\n" + self.SNAPSHOT[:40]))   # half-written line


class RouteHelpers(unittest.TestCase):
    def test_origin_and_relay_route(self):
        self.assertEqual(harness.route_origin(ROUTE), ORIGIN)
        self.assertEqual(harness.route_origin(ORIGIN), ORIGIN)
        self.assertEqual(harness.relay_route("ws://127.0.0.1:4242/v1/relay"), ROUTE)
        self.assertEqual(harness.relay_route("wss://relay.example/v2/relay"), "relay+wss://relay.example/v2/relay")
        with self.assertRaises(harness.HarnessError):
            harness.relay_route("http://127.0.0.1/")


if __name__ == "__main__":
    unittest.main()
