#!/usr/bin/env python3
"""Binary-free tests of the pure parts of the remote e2e harness
(scripts/shellx/remote-e2e/harness.py, annotate_log.py).

The e2e itself needs built binaries and runs in CI (shellx-remote.yml); these
pin what it must keep: the two `remote connect` argvs, the ticket refresh
schedule, the "connected" line, and the CI annotation chunking.
    python3 tests/test_shellx_remote_harness.py
"""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "shellx" / "remote-e2e"))

import annotate_log  # noqa: E402
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


SWIFT = ROOT / "Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/RemoteCommandLine.swift"


def swift_array(function: str) -> list[str]:
    """The argv array literal a `RemoteCommandLine.<function>(...)` returns, element by element:
    a string literal as its value, anything else (`paths.session`, `route`) as its Swift text."""
    source = SWIFT.read_text()
    body = source[source.index(f"public static func {function}("):]
    body = body[body.index("{") + 1:]
    literal = body[body.index("[") + 1:body.index("]")]
    return [item[1:-1] if item.startswith('"') else item
            for item in (part.strip() for part in literal.split(",")) if item]


class ServerArgv(unittest.TestCase):
    """The daemon spawns of ShellXDaemonSupervisor, mirrored byte for byte: every element of the
    Swift array, with each Swift expression passed in as the value it names."""

    def test_stop_is_the_swift_server_stop(self):
        self.assertEqual(harness.server_stop_argv(CMUX, "paths.session", "paths.muxSocket.path"),
                         [CMUX, *swift_array("serverStop")])

    def test_start_is_the_swift_server_start(self):
        argv = harness.server_start_argv(
            CMUX, "paths.session", "paths.muxSocket.path", "paths.daemonStateDir.path", "paths.adminSocket.path",
            "paths.linkSocket.path", "route", "slot", "ticketFile.path")
        self.assertEqual(argv, [CMUX, *swift_array("serverStart")])

    def test_stop_names_the_session_and_its_mux_socket_and_forces(self):
        argv = harness.server_stop_argv(CMUX, "e2e-host", "/h/run/mux.sock")
        self.assertEqual(argv, [CMUX, "server", "stop", "--session", "e2e-host", "--socket", "/h/run/mux.sock", "--force"])


class UninvitedConnect(unittest.TestCase):
    def test_the_app_connect_argv_without_invite_or_daemon(self):
        # RemoteCommandLine.connect with inviteFile nil and daemonFingerprint nil: what a viewer whose
        # pairing was not approved could run. It must equal the enrolled argv minus `--daemon FP`.
        argv = harness.uninvited_connect_argv(CMUX, ROUTE, SLOT, TICKET, STATE, SOCKET, DEVICE)
        self.assertEqual(argv + ["--daemon", FINGERPRINT], enrolled_argv())
        self.assertNotIn("--invite-file", argv)
        self.assertNotIn("--daemon", argv)


class DaemonProcesses(unittest.TestCase):
    MUX = "/private/tmp/sx-abc/host/run/mux.sock"
    START = f"/b/cmux-tui server start --session e2e-host --socket {MUX} --headless --ephemeral"

    def test_only_live_daemons_of_this_session_and_socket(self):
        ps = "\n".join([
            f"  101 Ss   {self.START} --relay relay+ws://127.0.0.1:1/v1/relay",
            f"  102 S    /b/cmux-tui server start --session e2e-host2 --socket {self.MUX}2 --headless",
            f"  103 Z    {self.START}",                                                   # zombie
            "  104 S    /b/cmux-tui server start --session e2e-host --socket /private/tmp/sx-other/host/run/mux.sock",
            f"  105 S    /b/cmux-tui server stop --session e2e-host --socket {self.MUX} --force",
            f"  106 S+   grep server start --session e2e-host --socket {self.MUX}x",
            f"  107 R    {self.START}",
            "garbage",
        ])
        self.assertEqual(harness.session_daemon_pids(ps, "e2e-host", self.MUX), [101, 107])

    def test_no_daemon(self):
        self.assertEqual(harness.session_daemon_pids("", "e2e-host", self.MUX), [])


class MachinePaths(unittest.TestCase):
    """Review Focus 1 at harness level: no two machines of one harness share a path (state dirs,
    sockets, logs), and every socket fits macOS sun_path (104 bytes with the NUL)."""

    def setUp(self):
        self.h = harness.Harness("/nonexistent/bin", "/nonexistent/core")
        self.machines = [self.h.machine(name) for name in ("host1", "host2", "viewer")]

    def tearDown(self):
        self.h.close()
        self.assertFalse(Path(self.h.root).exists())

    def test_no_two_machines_share_a_path(self):
        seen: dict[str, str] = {}
        for machine in self.machines:
            for key, path in machine.paths().items():
                self.assertNotIn(str(path), seen, f"{machine.name}.{key} == {seen.get(str(path))}")
                seen[str(path)] = f"{machine.name}.{key}"
        for machine in self.machines:
            others = [m for m in self.machines if m is not machine]
            for key, path in machine.paths().items():
                for other in others:
                    self.assertFalse(Path(path).is_relative_to(other.dir) if hasattr(Path, "is_relative_to")
                                     else str(path).startswith(str(other.dir) + "/"), f"{machine.name}.{key}")

    def test_every_socket_and_the_daemon_dirs_are_per_machine(self):
        names = {"bridge_sock", "mux_sock", "admin_sock", "link_sock", "client_sock", "dstate", "cstate", "core_dir"}
        for machine in self.machines:
            self.assertLessEqual(names, set(machine.paths()), machine.name)
            for key in ("bridge_sock", "mux_sock", "admin_sock", "link_sock", "client_sock"):
                self.assertLessEqual(len(str(machine.paths()[key]).encode()), 103, key)

    def test_sessions_are_distinct(self):
        self.assertEqual(len({m.session for m in self.machines}), len(self.machines))


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


class AnnotateLog(unittest.TestCase):
    TICKET = "v2." + "A" * 24 + "." + "B" * 10
    INVITE = "cmux://enroll/" + "Q" * 30

    def test_message_escaping(self):
        self.assertEqual(annotate_log.escape_message("100%\r\nnext\nlast"), "100%25%0D%0Anext%0Alast")
        self.assertEqual(annotate_log.escape_message("a:b,c"), "a:b,c")
        self.assertEqual(annotate_log.escape_property("a:b,c%\n"), "a%3Ab%2Cc%25%0A")

    def test_chunks_keep_order_and_are_at_most_nine(self):
        for count in (0, 1, 5, 9, 10, 17, 200, 201):
            lines = [f"line {n}" for n in range(count)]
            parts = annotate_log.chunk(lines)
            self.assertLessEqual(len(parts), annotate_log.MAX_CHUNKS, count)
            self.assertEqual([line for part in parts for line in part], lines, count)
            self.assertTrue(all(parts), count)             # no empty part
            self.assertEqual(len({len(part) for part in parts[:-1]}), max(0, min(1, len(parts) - 1)), count)  # equal size

    def test_two_hundred_lines_make_nine_parts(self):
        parts = annotate_log.chunk([str(n) for n in range(200)])
        self.assertEqual(len(parts), 9)
        self.assertEqual([len(p) for p in parts], [23] * 8 + [16])

    def test_commands_summary_first_then_numbered_parts(self):
        log = "\n".join([f"line {n}" for n in range(500)]
                        + ["ERROR: test_a (m.C.test_a)", "FAIL: test_b (m.C.test_b)", "FAIL: test_b (m.C.test_b)",
                           "Ran 2 tests"])
        commands = annotate_log.build_commands(log)
        self.assertLessEqual(len(commands), 10)
        self.assertEqual(commands[0], "::error title=e2e failing tests::ERROR: test_a (m.C.test_a)"
                                      "%0AFAIL: test_b (m.C.test_b)")
        n = len(commands) - 1
        self.assertEqual(n, 9)
        for number, line in enumerate(commands[1:], start=1):
            self.assertTrue(line.startswith(f"::error title=e2e log (part {number}/{n})::"), line[:60])
        tail = "%0A".join(c.split("::", 2)[2] for c in commands[1:])
        self.assertIn("line 304", tail)
        self.assertNotIn("line 303", tail)                  # only the last 200 lines
        self.assertTrue(tail.endswith("Ran 2 tests"))

    def test_every_command_is_one_line_and_special_characters_are_escaped(self):
        commands = annotate_log.build_commands("a\r\nb 100%\n\x1b[31mred\x00\x1b[0m\n" + "x" * 1000)
        for line in commands:
            self.assertNotIn("\n", line)
            self.assertNotIn("\r", line)
            self.assertNotIn("\x1b", line)
            self.assertTrue(line.startswith("::error title="))
        body = "\n".join(commands[1:])
        self.assertIn("b 100%25", body)
        self.assertNotIn("x" * 500, body)                   # long lines are cut

    def test_ticket_invite_and_secret_lines_are_never_printed(self):
        log = "\n".join([
            "before", f"assert no ticket in {self.TICKET} here", f"uri {self.INVITE}",
            "CMUX_RELAY_HMAC_SECRET=deadbeef", "SHELLX_FAKE_PASSWORD: hunter2", f"FAIL: test {self.TICKET}",
            "after"])
        output = "\n".join(annotate_log.build_commands(log))
        for secret in (self.TICKET, "A" * 24, self.INVITE, "deadbeef", "hunter2"):
            self.assertNotIn(secret, output)
        self.assertIn("before", output)
        self.assertIn("after", output)
        self.assertIn(annotate_log.DROPPED.split(":")[0], output)

    def test_a_ticket_split_by_a_control_character_is_dropped(self):
        # Stripping control characters joins the two halves into a ticket: the filter must run after.
        half = "A" * 12
        for joint in ("\x00", "\x1b", "\x07", "\x1b[31m", "\x1b[0m\x00"):
            line = f"token v2.{half}{joint}{half}.{'B' * 10} end"
            self.assertEqual(annotate_log.clean_line(line), annotate_log.DROPPED, repr(joint))
            output = "\n".join(annotate_log.build_commands(f"FAIL: x\n{line}\n"))
            self.assertNotIn(half * 2, output, repr(joint))
        invite = "cmux://enroll/" + "Q" * 10 + "\x01" + "Q" * 10
        self.assertEqual(annotate_log.clean_line(invite), annotate_log.DROPPED)

    def test_the_window_starts_at_the_last_process_dump(self):
        dump = [f"{annotate_log.DUMP_MARKER} table: 2 processes -----", f"{annotate_log.DUMP_MARKER} relay-1 pid=1 rc=None",
                f"{annotate_log.DUMP_MARKER} api pid=2 rc=None", "----- logs/harness.log (last 80 lines, redacted) -----"]
        lines = ([f"early {n}" for n in range(300)] + dump + [f"first dump {n}" for n in range(50)]
                 + ["test_b ... FAIL"] + dump + [f"last dump {n}" for n in range(400)]
                 + ["FAIL: test_b (m.C.test_b)", "Ran 2 tests"])
        window = annotate_log.window(lines)
        self.assertEqual(window[0], dump[0])                       # the start of the LAST dump
        self.assertNotIn("first dump 49", window)
        self.assertEqual(window[-1], "Ran 2 tests")
        self.assertIn("last dump 0", window)                       # more than the last 200 lines
        commands = annotate_log.build_commands("\n".join(lines))
        self.assertLessEqual(len(commands) - 1, annotate_log.MAX_CHUNKS)
        body = "%0A".join(c.split("::", 2)[2] for c in commands[1:])
        self.assertTrue(body.startswith(dump[0]))
        self.assertTrue(body.endswith("Ran 2 tests"))

    def test_a_long_dump_keeps_its_head_and_the_tail(self):
        lines = [f"{annotate_log.DUMP_MARKER} table: 1 processes -----"] + [f"x {n}" for n in range(5000)] + ["Ran 1 test"]
        window = annotate_log.window(lines)
        self.assertEqual(len(window), annotate_log.MAX_WINDOW_LINES)
        self.assertEqual(window[0], lines[0])
        self.assertEqual(window[-annotate_log.TAIL_LINES:], lines[-annotate_log.TAIL_LINES:])
        self.assertIn("lines omitted", window[-annotate_log.TAIL_LINES - 1])

    def test_no_dump_marker_keeps_the_last_lines(self):
        lines = [f"line {n}" for n in range(500)]
        self.assertEqual(annotate_log.window(lines), lines[-annotate_log.TAIL_LINES:])

    def test_each_annotation_stays_under_the_64_kb_message_limit(self):
        log = "\n".join([f"{annotate_log.DUMP_MARKER} table -----"] + ["%" * 2000] * 6000)
        for command in annotate_log.build_commands(log):
            self.assertLess(len(command.encode()), 64 * 1024)

    def test_every_harness_dump_starts_with_the_marker(self):
        import io
        h = harness.Harness("/nonexistent/bin", "/nonexistent/core")
        try:
            out = io.StringIO()
            h.dump_logs(out)                                   # even with no process
        finally:
            h.close()
        self.assertEqual(harness.DUMP_MARKER, annotate_log.DUMP_MARKER)
        self.assertTrue(out.getvalue().splitlines()[0].startswith(annotate_log.DUMP_MARKER))
        self.assertEqual(annotate_log.window(out.getvalue().splitlines())[0], out.getvalue().splitlines()[0])

    def test_no_failing_line_still_gives_a_summary(self):
        commands = annotate_log.build_commands("only noise\n")
        self.assertEqual(len(commands), 2)
        self.assertTrue(commands[0].startswith("::error title=e2e failing tests::no FAIL:/ERROR: line"))

    def test_empty_log(self):
        commands = annotate_log.build_commands("")
        self.assertEqual(len(commands), 1)

    def test_main_prints_commands_and_survives_a_missing_log(self):
        import contextlib
        import io
        import os
        import tempfile

        out = io.StringIO()
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(out):
            path = os.path.join(tmp, "e2e.log")
            with open(path, "w", encoding="utf-8") as f:
                f.write("FAIL: test_x (m.C.test_x)\nRan 1 test\n")
            self.assertEqual(annotate_log.main([path]), 0)
            self.assertEqual(annotate_log.main([os.path.join(tmp, "missing.log")]), 0)
        lines = out.getvalue().splitlines()
        self.assertEqual(lines[0], "::error title=e2e failing tests::FAIL: test_x (m.C.test_x)")
        self.assertEqual(lines[1], "::error title=e2e log (part 1/2)::FAIL: test_x (m.C.test_x)")
        self.assertEqual(lines[2], "::error title=e2e log (part 2/2)::Ran 1 test")
        self.assertEqual(lines[3], "::error title=e2e log::cannot read the e2e log: FileNotFoundError")


if __name__ == "__main__":
    unittest.main()
