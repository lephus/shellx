"""Process control for the ShellX remote end-to-end test.

Topology (everything on 127.0.0.1, one run = one harness dir):

    shellx-fake-api  --(2 s HMAC tickets, sealed invites)--> shellx-core-cli (host, viewer)
    cmux-relay (stock)  <-- register --  patched cmux-tui daemon (host) <-- virtual PTY --> fake_app.py
                        <-- connect  --  cmux-tui remote connect (viewer) <-- viewer_cli

Rules this file keeps (lane L5 constraints):
- Every process starts with an empty environment (the equivalent of `env -i`)
  plus HOME, TMPDIR, XDG_RUNTIME_DIR and CMUX_TUI_CONFIG inside the harness
  dir and a minimal PATH. The relay HMAC secret goes by environment only.
  shellx-core-cli takes its params in argv, so the run's random fake-account
  password (auth.login) and the invite (pair.approve) are in that short-lived
  process's argv; the app calls the Core in-process instead.
- The relay HMAC secret is random per run. Tickets, invites and the secret are
  never printed or logged by the harness; its own log has method names and
  result codes only, and anything it copies from a failing command is
  redacted. `logs()` returns every process log so the test can scan them.
- The harness dir lives under a short /tmp root (macOS sun_path is 104
  bytes) and `close()` removes it with every ticket, invite and key in it.

Where this harness deliberately differs from the ShellX app (all test-only; the
app is Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore: RemoteCommandLine,
ShellXClientLinkSupervisor, ShellXTicketRefresher, ReconnectBackoff):
(a) The invite spawn of `remote connect` passes a SECOND relay-route triple, the
    invite route's origin, so that both route candidates read the refreshed
    ticket file (see `relay_credential_args`). cmux keeps only scheme://host:port
    of an invite route, and the invite's own static connect ticket would expire
    during the 2 s-ticket stress test. The app passes one triple; ledger ruling
    R32 accepted that (in production, with 120 s tickets, an expired invite
    ticket costs one extra ~1 s backoff step). The enrolled restart argv has
    exactly the app's single triple (`enrolled_connect_argv`).
(b) The harness refresher is latency-aware: it starts the next mint early enough
    that the file keeps REFRESH_MARGIN of life while the mint runs
    (`refresh_delay`). The app's ShellXTicketRefresher is half-life with a 1 s
    floor (TicketSchedule.nextRefresh); that is enough for its 120 s tickets and
    cannot be used with the 2 s tickets this e2e runs.
(c) The app mints a fresh ticket before every spawn (LinkStateMachine
    mintTicket); the harness only relies on the refresher keeping the file
    fresh and does not mint on each restart.
"""

from __future__ import annotations

import base64
import json
import os
import pwd
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
from pathlib import Path
from typing import Callable, Optional, Sequence

HERE = Path(__file__).resolve().parent
FAKE_APP = HERE / "fake_app.py"
ISSUER = "shellx-relay"
EMAIL = "e2e@shellx.test"
MIN_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"
# Stock cmux-relay serves /v1/relay and /ws (cmux-relay/src/relay.rs:244-245);
# production K2 serves /v2/relay behind its own front end (D6).
RELAY_PATH = "/v1/relay"
# Shortest wait between two mints of the same ticket (see start_ticket_refresher).
REFRESH_FLOOR = 0.1
# Life a ticket file must keep beyond the next mint's expected latency.
REFRESH_MARGIN = 0.5
# How many of the latest mint latencies the refresher schedules by.
LATENCY_WINDOW = 5
# `remote connect --headless --json` prints one JSON object per line with this
# `event` when connected and on every topology change.
SNAPSHOT_EVENT = "connection-snapshot"

TICKET_RE = re.compile(r"v2\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]*")
INVITE_RE = re.compile(r"cmux://enroll/[A-Za-z0-9_=-]+")


def wait_until(timeout: float, check: Callable[[], object], interval: float = 0.5) -> bool:
    """Polls `check` until it returns something truthy or `timeout` seconds pass.
    A `HarnessError` (a dead process) is re-raised at once; any other exception
    counts as "not yet"."""
    deadline = time.monotonic() + timeout
    while True:
        try:
            if check():
                return True
        except HarnessError:
            raise
        except Exception:
            pass
        if time.monotonic() >= deadline:
            return False
        time.sleep(interval)


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def relay_route(relay_url: str) -> str:
    """D6: the relay URL from tickets.mint as a cmux-tui relay route."""
    for plain, routed in (("wss://", "relay+wss://"), ("ws://", "relay+ws://")):
        if relay_url.startswith(plain):
            return routed + relay_url[len(plain):]
    raise HarnessError(f"relay_url has an unexpected scheme ({relay_url.split(':', 1)[0]})")


def route_origin(route: str) -> str:
    """`scheme://host:port` of a route: what cmux keeps of an invite route."""
    scheme, rest = route.split("://", 1)
    return f"{scheme}://{rest.split('/', 1)[0]}"


def relay_credential_args(route: str, slot: str, ticket_file: str) -> list[str]:
    """`remote connect` relay credentials for an INVITE spawn: the full `route`
    and, when it has a path, its origin (test-only, see the module docstring).

    The second triple is for the invite spawn only. cmux keeps only
    `scheme://host:port` of an invite route (identity.rs
    credential_free_route_hint), so an invite adds that origin as a second route
    candidate carrying the invite's own static connect ticket
    (remote_cli.rs start_connected: `relay_routes.entry(route).or_insert`).
    That ticket was minted at pairing time. Once it has expired, a dial on the
    origin candidate gets `invalid-ticket` and cmux treats it as non-retryable
    (provider/relay.rs `open` retries once, with the same static ticket;
    `relay_rejection`: "relay rejected the authenticated operation"), so the
    client ends for good. That needs both of these:
    - a relay that, like the stock cmux-relay, does not reject at the HTTP
      upgrade: it accepts the WebSocket and checks the ticket afterwards, in
      the Allocate control message (cmux-relay relay.rs);
    - the stale origin candidate being the one that is selected and opened.
    Naming the origin here too makes every candidate read the refreshed file.

    An enrolled restart has no invite, hence exactly one candidate (the
    positional route): cmux refuses a relay credential route that is not a
    candidate (remote_cli.rs start_connected, `relay_route_not_candidate`). It
    must never get this second triple; see `enrolled_connect_argv`."""
    args = ["--relay-route", route, "--relay-slot", slot, "--relay-ticket-file", ticket_file]
    if route_origin(route) != route:
        args += ["--relay-route", route_origin(route), "--relay-slot", slot, "--relay-ticket-file", ticket_file]
    return args


def _connect_flags(state_dir: str, local_socket: str, device_name: str) -> list[str]:
    """The flags both spawns share, in the order of Swift RemoteCommandLine.connect."""
    return ["--state-dir", state_dir, "--local-socket", local_socket, "--headless", "--json",
            "--exit-with-parent", "--device-name", device_name]


def invite_connect_argv(cmux_tui: str, route: str, slot: str, ticket_file: str, invite_file: str,
                        state_dir: str, local_socket: str, device_name: str) -> list[str]:
    """First spawn of the viewer's client: enrolls with the sealed invite. The
    positional route comes first; then one `--relay-route` triple per route
    candidate that needs the refreshed ticket file (the full route and its
    origin, see `relay_credential_args`)."""
    return [cmux_tui, "remote", "connect", route, *relay_credential_args(route, slot, ticket_file),
            *_connect_flags(state_dir, local_socket, device_name), "--invite-file", invite_file]


def enrolled_connect_argv(cmux_tui: str, route: str, slot: str, ticket_file: str, daemon_fingerprint: str,
                          state_dir: str, local_socket: str, device_name: str) -> list[str]:
    """Restart of an enrolled client, no invite: the same argv as Swift
    RemoteCommandLine.connect (RemoteCommandLine.swift:37-45) with
    `--daemon <fingerprint>`. The route stays positional and the single relay
    credential is the shorthand `--relay-slot S --relay-ticket-file F` (no
    `--relay-route`): cmux then has exactly one candidate, the positional route,
    and the credential is keyed to it.

    `--exit-with-parent` is kept as in the app: the client exits when the
    harness process (its direct parent) exits, which is what the harness wants
    (no client survives a killed or cancelled CI run); the harness itself stops
    clients through `_stop`."""
    return [cmux_tui, "remote", "connect", route, "--relay-slot", slot, "--relay-ticket-file", ticket_file,
            *_connect_flags(state_dir, local_socket, device_name), "--daemon", daemon_fingerprint]


def refresh_delay(left: float, latencies: Sequence[float]) -> float:
    """Seconds to wait before the next mint of a ticket that has `left` seconds
    of life: half the remaining life, or earlier so that the mint (as slow as
    the slowest of `latencies`) finishes with REFRESH_MARGIN of life left in
    the file; never less than REFRESH_FLOOR."""
    slowest = max(latencies, default=0.0)
    return max(REFRESH_FLOOR, min(left / 2, left - slowest - REFRESH_MARGIN))


def next_latencies(recent: Sequence[float], latency: float, cold: bool) -> list[float]:
    """The refresher's latency window after a mint. The first mint of a
    refresher is cold (process start, page cache): when `cold` the window
    restarts from the second mint, so one slow first mint does not keep the
    refresher at REFRESH_FLOOR for the next LATENCY_WINDOW mints."""
    window = [] if cold else list(recent)
    return (window + [latency])[-LATENCY_WINDOW:]


def is_snapshot_line(line: str) -> bool:
    """True for the `{"event":"connection-snapshot",...}` line that `remote
    connect --headless --json` prints once connected (remote_cli.rs
    connect_with_flags); what ShellXClientLinkSupervisor.isSnapshotLine matches."""
    if not line.startswith("{"):
        return False
    try:
        value = json.loads(line)
    except ValueError:
        return False
    return isinstance(value, dict) and value.get("event") == SNAPSHOT_EVENT


def log_has_snapshot(text: str) -> bool:
    """True if any complete line of a client log is a connection snapshot (a
    half-written last line does not parse and counts on the next read)."""
    return any(is_snapshot_line(line) for line in text.splitlines())


def invitation_id(uri: str) -> str:
    """The `id` of a `cmux://enroll/<b64url(json)>` invite (identity.rs:106-125)."""
    body = uri.strip().removeprefix("cmux://enroll/")
    raw = base64.urlsafe_b64decode(body + "=" * (-len(body) % 4))
    return json.loads(raw)["id"]


def mkdir_private(path: Path) -> Path:
    path.mkdir(mode=0o700, parents=False, exist_ok=False)
    os.chmod(path, 0o700)
    return path


class HarnessError(RuntimeError):
    pass


class CoreError(HarnessError):
    def __init__(self, machine: str, method: str, code: str, message: str) -> None:
        super().__init__(f"{machine}: {method} -> {code}: {message}")
        self.code = code


class MintStats:
    """What one ticket refresher saw: how many mints, the cold first latency and
    the slowest mint, to attribute a CI failure to a slow API/CLI."""

    def __init__(self, first_latency: float) -> None:
        self.first = first_latency
        self.maximum = first_latency
        self.count = 1
        self.failures = 0

    def record(self, latency: float) -> None:
        self.count += 1
        self.maximum = max(self.maximum, latency)


class Machine:
    """One ShellX install: its own shellx-core state dir (0700) and
    SHELLX_CORE_CONFIG, cmux-tui state dirs and sockets.

    The refreshers and the two `remote connect` argvs differ from the app in
    three test-only ways, listed in the module docstring (a second origin
    relay-route triple on the invite spawn, a latency-aware refresher, no mint
    before every spawn)."""

    def __init__(self, harness: "Harness", name: str) -> None:
        self.h = harness
        self.name = name
        self.session = f"e2e-{name}"
        self.dir = mkdir_private(harness.root / name)
        self.core_dir = mkdir_private(self.dir / "core")
        self.home = mkdir_private(self.dir / "home")
        self.tmp = mkdir_private(self.dir / "tmp")
        self.run_dir = mkdir_private(self.dir / "run")
        self.dstate = mkdir_private(self.dir / "d")  # daemon --remote-state-dir
        self.cstate = mkdir_private(self.dir / "c")  # client --state-dir
        self.bridge_dir = mkdir_private(self.dir / "b")
        self.bridge_sock = self.bridge_dir / "s.sock"
        self.mux_sock = self.run_dir / "mux.sock"
        self.client_sock = self.run_dir / "client.sock"
        self.app_input_log = harness.log_dir / f"fake-app-{name}.input.log"
        self.config = json.dumps({
            "api_base": harness.api_base,
            "state_dir": str(self.core_dir),
            "app_version": "2.0.0",
            "os_version": "e2e",
            "platform": "macos",
            "device_name": self.session,
        })
        self.machine_id = ""
        self.slot = ""
        self.relay_url = ""
        self.invite_path: Optional[str] = None
        self.refreshers: dict[str, tuple[threading.Event, threading.Thread, str]] = {}
        self.mint_stats: dict[str, MintStats] = {}
        self.daemon_runs = 0
        self.core_lock = threading.Lock()
        self.client_runs = 0
        self.client_route = ""     # the full relay route of the viewer's client
        self.client_ticket = ""    # the refreshed connect ticket file of the viewer's client

    # shellx-core ---------------------------------------------------------
    def core(self, method: str, **params) -> dict:
        """Runs `shellx-core-cli <method> '<json>'` and returns the `ok` value.
        Params can carry a password or an invite (the CLI takes argv only);
        the harness logs the method and the result code, never params.

        Calls on one machine are serialized: the state store assumes one
        process owns a state dir (shellx-core store.rs sweep_stale_temps
        removes other writers' temp files when a store opens), and every CLI
        call is its own process. In the app one Core owns the dir."""
        env = self.h.env(self, {"SHELLX_CORE_CONFIG": self.config})
        argv = [str(self.h.core_bin / "shellx-core-cli"), method, json.dumps(params)]
        with self.core_lock:
            started = time.monotonic()
            proc = subprocess.run(argv, env=env, cwd=self.h.root, stdin=subprocess.DEVNULL,
                                  capture_output=True, text=True, timeout=60)
        lines = proc.stdout.strip().splitlines()
        try:
            envelope = json.loads(lines[-1])
        except (IndexError, json.JSONDecodeError):
            self.h.note(f"core {self.name} {method} -> unreadable (rc={proc.returncode})")
            raise HarnessError(f"{self.name}: {method}: no envelope (rc={proc.returncode})")
        if "ok" in envelope:
            self.h.note(f"core {self.name} {method} -> ok ({(time.monotonic() - started) * 1000:.0f} ms)")
            return envelope["ok"]
        error = envelope.get("error") or {}
        code = str(error.get("code", "?"))
        self.h.note(f"core {self.name} {method} -> {code}")
        raise CoreError(self.name, method, code, self.h.redact(str(error.get("message", ""))))

    def login(self) -> dict:
        return self.core("auth.login", email=EMAIL, password=self.h.password)

    def register(self) -> dict:
        reg = self.core("machines.register", name=self.session, platform="macos",
                        os_version="e2e", app_version="2.0.0")
        self.machine_id, self.slot = reg["machine_id"], reg["slot"]
        return reg

    def start_ticket_refresher(self, write_to: str, permission: str, target: Optional[str] = None) -> str:
        """Mints one ticket into `<core>/tickets/<write_to>` now, then keeps it
        fresh from a thread: the next mint starts at half the remaining life,
        or earlier so that it finishes (slowest of the last mints) with at
        least REFRESH_MARGIN of life left in the file; never sooner than
        REFRESH_FLOOR (`refresh_delay`). Test-only: the app's
        ShellXTicketRefresher is half-life with a 1 s floor.

        With 2 s tickets whose expiry is a whole second, a fresh ticket has
        1-2 s left, and cmux treats an expired ticket as fatal (the relay's
        `invalid-ticket` becomes "relay rejected the authenticated operation",
        cmux-remote provider/relay.rs relay_authentication_error and
        relay_rejection). Pure half-life scheduling, measured after the mint
        returns, left the file expired for most of a slow mint (seen at 0.6-7 s
        under load: the relay refused a connect ticket 0.4 s past its expiry
        that the next mint replaced 1.3 s later).

        The first mint is cold, so the latency window restarts from the second
        mint (`next_latencies`); the slowest mint is logged by
        `note_mint_stats` (on stop and in `Harness.dump_logs`)."""
        if write_to in self.refreshers:
            return self.refreshers[write_to][2]
        params = {"permission": permission, "write_to": write_to}
        if target:
            params["target_machine_id"] = target
        started = time.monotonic()
        first = self.core("tickets.mint", **params)
        first_latency = time.monotonic() - started
        self.relay_url = first["relay_url"]
        stats = self.mint_stats[write_to] = MintStats(first_latency)
        stop = threading.Event()

        def loop(expires_at: float, latency: float) -> None:
            recent, cold = [latency], True
            while True:
                if stop.wait(refresh_delay(expires_at - time.time(), recent)):
                    return
                started = time.monotonic()
                try:
                    expires_at = float(self.core("tickets.mint", **params)["expires_at_unix"])
                except Exception as error:  # API briefly unreachable: retry in 1 s
                    self.h.note(f"refresher {self.name}/{write_to}: {type(error).__name__}")
                    expires_at = time.time() + 2
                    stats.failures += 1
                    continue
                latency = time.monotonic() - started
                stats.record(latency)
                recent, cold = next_latencies(recent, latency, cold), False

        thread = threading.Thread(target=loop, args=(float(first["expires_at_unix"]), first_latency),
                                  name=f"tickets-{self.name}-{write_to}", daemon=True)
        thread.start()
        self.refreshers[write_to] = (stop, thread, first["path"])
        return first["path"]

    def note_mint_stats(self) -> None:
        """One harness-log line per refresher: mints, failed mints, the cold
        first latency and the slowest latency (all mints)."""
        for write_to, stats in list(self.mint_stats.items()):
            self.h.note(f"refresher {self.name}/{write_to}: mints={stats.count} failed={stats.failures} "
                        f"first={stats.first:.2f} s max={stats.maximum:.2f} s")

    def stop_refreshers(self) -> None:
        for stop, _, _ in self.refreshers.values():
            stop.set()
        for _, thread, _ in self.refreshers.values():
            thread.join(timeout=70)
        self.refreshers.clear()
        self.note_mint_stats()


class Harness:
    def __init__(self, bin_dir: str, core_bin_dir: str, ticket_ttl: int = 2) -> None:
        self.bin = Path(bin_dir).resolve()
        self.core_bin = Path(core_bin_dir).resolve()
        self.ticket_ttl = ticket_ttl
        self.root = Path(os.path.realpath(tempfile.mkdtemp(prefix="sx-", dir="/tmp")))
        os.chmod(self.root, 0o700)
        self.log_dir = mkdir_private(self.root / "logs")
        self.home = mkdir_private(self.root / "home")
        self.tmp = mkdir_private(self.root / "tmp")
        self.tui_config = self.root / "cmux-tui.json"
        self.tui_config.write_text("{}\n")
        self.secret = secrets.token_hex(32)  # 64 ASCII bytes, relay + fake API only, by env
        self.password = secrets.token_urlsafe(18)
        self.relay_port = free_port()
        self.api_port = free_port()
        self.api_base = f"http://127.0.0.1:{self.api_port}"
        self.user = pwd.getpwuid(os.getuid()).pw_name
        self.procs: dict[str, subprocess.Popen] = {}
        self.machines: dict[str, Machine] = {}
        self.viewer: Optional[Machine] = None
        self.relay_runs = 0
        self._note_lock = threading.Lock()
        self._proc_lock = threading.Lock()
        self._stopping = threading.Event()
        self._supervisor: Optional[threading.Thread] = None
        self._closed = False

    # plumbing ------------------------------------------------------------
    def env(self, machine: Optional[Machine] = None, extra: Optional[dict] = None) -> dict:
        home, tmp = (machine.home, machine.tmp) if machine else (self.home, self.tmp)
        run_dir = machine.run_dir if machine else self.tmp
        env = {
            "HOME": str(home),
            "TMPDIR": f"{tmp}/",
            "XDG_RUNTIME_DIR": str(run_dir),
            "PATH": MIN_PATH,
            "USER": self.user,
            "LOGNAME": self.user,
            "LANG": "en_US.UTF-8" if sys.platform == "darwin" else "C.UTF-8",
            "TERM": "xterm-256color",
            "CMUX_TUI_CONFIG": str(self.tui_config),
        }
        env.update(extra or {})
        return env

    def note(self, line: str) -> None:
        with self._note_lock, open(self.log_dir / "harness.log", "a", encoding="utf-8") as f:
            f.write(f"{time.time():.3f} {line}\n")

    def redact(self, text: str) -> str:
        text = TICKET_RE.sub("<ticket>", text)
        text = INVITE_RE.sub("<invite>", text)
        for value, label in ((self.secret, "<hmac>"), (self.password, "<password>")):
            text = text.replace(value, label)
        return text

    def _spawn(self, name: str, argv: list[str], env: dict) -> subprocess.Popen:
        log = open(self.log_dir / f"{name}.log", "ab")
        try:
            proc = subprocess.Popen(argv, env=env, cwd=self.root, stdin=subprocess.DEVNULL,
                                    stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        finally:
            log.close()
        self.procs[name] = proc
        self.note(f"spawn {name} pid={proc.pid}")
        return proc

    def _stop(self, name: str, sig: int = signal.SIGTERM, grace: float = 10.0) -> None:
        proc = self.procs.pop(name, None)
        if proc is None or proc.poll() is not None:
            return
        for current in (sig, signal.SIGKILL):
            try:
                os.killpg(proc.pid, current)
            except ProcessLookupError:
                break
            try:
                proc.wait(timeout=grace if current != signal.SIGKILL else 10)
                break
            except subprocess.TimeoutExpired:
                continue
        self.note(f"stop {name} rc={proc.returncode}")

    def _proc(self, name: str) -> Optional[subprocess.Popen]:
        with self._proc_lock:
            return self.procs.get(name)

    def _tui(self, machine: Machine, args: list[str], timeout: float = 60) -> subprocess.CompletedProcess:
        """Runs a one-shot cmux-tui command; stdout is returned, never logged."""
        argv = [str(self.bin / "cmux-tui"), *args]
        proc = subprocess.run(argv, env=self.env(machine), cwd=self.root, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=timeout)
        label = " ".join(a for a in args[:3] if not a.startswith("/"))
        self.note(f"tui {machine.name} {label} -> rc={proc.returncode}")
        return proc

    def _tui_ok(self, machine: Machine, args: list[str], timeout: float = 60) -> str:
        proc = self._tui(machine, args, timeout)
        if proc.returncode != 0:
            raise HarnessError(f"cmux-tui {' '.join(args[:3])} failed (rc={proc.returncode}): "
                               f"{self.redact(proc.stderr.strip())[-2000:]}")
        return proc.stdout

    # relay and API -------------------------------------------------------
    def start_relay(self) -> None:
        """Stock cmux-relay on the run's fixed port, with the run's secret and
        the issuer the fake API signs with."""
        self.relay_runs += 1
        env = self.env(None, {"CMUX_RELAY_HMAC_SECRET": self.secret, "CMUX_RELAY_ISSUER": ISSUER})
        argv = [str(self.bin / "cmux-relay"), "serve", "--bind", f"127.0.0.1:{self.relay_port}"]
        proc = self._spawn(f"relay-{self.relay_runs}", argv, env)

        def healthy() -> bool:
            if proc.poll() is not None:
                raise HarnessError("relay exited")
            with urllib.request.urlopen(f"http://127.0.0.1:{self.relay_port}/healthz", timeout=2) as r:
                return r.status == 200

        if not wait_until(30, healthy, 0.2):
            raise HarnessError(f"relay did not become healthy (rc={proc.poll()})")

    def stop_relay(self) -> None:
        """An outage, not a shutdown: the relay is killed (graceful shutdown
        would wait for every WebSocket to close)."""
        self._stop(f"relay-{self.relay_runs}", signal.SIGKILL)

    def start_api(self) -> None:
        env = self.env(None, {"CMUX_RELAY_HMAC_SECRET": self.secret, "SHELLX_FAKE_PASSWORD": self.password})
        argv = [str(self.core_bin / "shellx-fake-api"), "--bind", f"127.0.0.1:{self.api_port}",
                "--relay-url", f"ws://127.0.0.1:{self.relay_port}{RELAY_PATH}",
                "--ticket-ttl", str(self.ticket_ttl), "--issuer", ISSUER]
        proc = self._spawn("api", argv, env)
        log = self.log_dir / "api.log"
        if not wait_until(30, lambda: proc.poll() is None and "listening" in log.read_text(), 0.2):
            raise HarnessError(f"fake API did not start (rc={proc.poll()})")

    def machine(self, name: str) -> Machine:
        machine = Machine(self, name)
        self.machines[name] = machine
        return machine

    # host ----------------------------------------------------------------
    def host_cli(self, host: Machine, *args: str):
        """`cmux-tui <args> --session e2e-<name> --state-dir <remote state>`;
        parsed JSON when `--json` is among the args."""
        out = self._tui_ok(host, [*args, "--session", host.session, "--state-dir", str(host.dstate)])
        return json.loads(out) if "--json" in args else out

    def start_fake_app(self, host: Machine) -> None:
        if self._proc(f"fake-app-{host.name}") is not None:
            return
        argv = [sys.executable, "-I", str(FAKE_APP), "--socket", str(host.bridge_sock),
                "--log", str(self.log_dir / f"fake-app-{host.name}.events.log"),
                "--input-log", str(host.app_input_log)]
        proc = self._spawn(f"fake-app-{host.name}", argv, self.env(host))
        if not wait_until(15, lambda: proc.poll() is None and host.bridge_sock.exists(), 0.1):
            raise HarnessError("fake app did not start")

    def start_host_daemon(self, host: Machine) -> None:
        """Fake app + `cmux-tui server start` (patched daemon, virtual PTY via
        CMUX_SHELLX_BRIDGE_SOCKET), registered at the relay with a refreshed
        register ticket. Returns once the admin socket answers."""
        self.start_fake_app(host)
        ticket = host.start_ticket_refresher("register.ticket", "register")
        route = relay_route(host.relay_url)
        host.daemon_runs += 1
        argv = [str(self.bin / "cmux-tui"), "server", "start", "--session", host.session,
                "--headless", "--ephemeral", "--socket", str(host.mux_sock),
                "--remote-state-dir", str(host.dstate), "--relay", route, "--relay-slot", host.slot,
                "--relay-ticket-file", ticket]
        env = self.env(host, {"CMUX_SHELLX_BRIDGE_SOCKET": str(host.bridge_sock)})
        name = f"daemon-{host.name}-{host.daemon_runs}"
        proc = self._spawn(name, argv, env)

        def ready() -> bool:
            if proc.poll() is not None:
                raise HarnessError("daemon exited")
            return self._tui(host, ["remote", "enroll", "status", "--session", host.session,
                                    "--state-dir", str(host.dstate), "--json"], 10).returncode == 0

        if not wait_until(90, ready):
            raise HarnessError(f"host daemon did not come up (rc={proc.poll()})")

    def restart_host_daemon(self, host: Machine) -> None:
        """Stops the daemon and starts it again with the same remote state
        dir (identity and enrolled devices kept) and a fresh ephemeral mux."""
        self._stop(f"daemon-{host.name}-{host.daemon_runs}", signal.SIGTERM, 20)
        self.start_host_daemon(host)

    # pairing and viewing -------------------------------------------------
    def pair(self, viewer: Machine, host: Machine) -> str:
        """ShellX pairing that carries a cmux enrollment invite sealed to the
        viewer's device key. Returns the cmux invitation id."""
        request = viewer.core("pair.request", to_machine_id=host.machine_id)
        pending = host.core("pair.pending")["pairings"]
        item = next((p for p in pending if p["pairing_id"] == request["pairing_id"]), None)
        if item is None:
            raise HarnessError("host does not see the pairing request")
        if item["suspicious"] or item["fingerprint"] != request["fingerprint"] or item["code"] != request["code"]:
            raise HarnessError("pairing request does not match what the viewer shows")
        ticket = host.core("tickets.mint", permission="connect", target_machine_id=host.machine_id,
                           write_to="invite-connect.ticket")["path"]
        route = relay_route(host.relay_url)
        uri = self._tui_ok(host, ["remote", "enroll", "create", "--session", host.session,
                                  "--state-dir", str(host.dstate), "--advertise", route,
                                  "--relay-route", route, "--relay-slot", host.slot,
                                  "--relay-ticket-file", ticket, "--ttl", "300"]).strip()
        os.unlink(ticket)  # it lives on inside the invite only
        inv = invitation_id(uri)
        # R14: approve fails closed; pass the fingerprint pair.pending showed.
        host.core("pair.approve", pairing_id=request["pairing_id"], invite_uri=uri, fingerprint=item["fingerprint"])
        del uri
        poll = viewer.core("pair.poll", pairing_id=request["pairing_id"], write_invite_to="invite.uri")
        status = self.host_cli(host, "remote", "enroll", "status", "--json")
        if poll.get("status") != "approved":
            raise HarnessError(f"pair.poll status {poll.get('status')!r}")
        # cmux keeps only scheme://host:port of an invite route (identity.rs:2216-2219).
        if poll["relay_route"] != route_origin(route):
            raise HarnessError(f"sealed invite names relay route {poll['relay_route']!r}, not {route_origin(route)!r}")
        if poll["relay_slot"] != host.slot:
            raise HarnessError("sealed invite names another relay slot")
        if poll["daemon_fingerprint"] != status["daemon_fingerprint"]:
            raise HarnessError("sealed invite names another daemon")
        viewer.invite_path = poll["invite_path"]
        return inv

    def connect_viewer(self, viewer: Machine, host: Machine) -> None:
        """`cmux-tui remote connect` through the relay with the sealed invite and
        a refreshed connect ticket (`invite_connect_argv`: the full route and,
        test-only, its origin both read the refreshed file). Returns once the
        host sees the pending enrollment."""
        if not viewer.invite_path:
            raise HarnessError("pair() first")
        viewer.client_ticket = viewer.start_ticket_refresher("connect.ticket", "connect", target=host.machine_id)
        viewer.client_route = relay_route(viewer.relay_url)
        argv = invite_connect_argv(str(self.bin / "cmux-tui"), viewer.client_route, host.slot, viewer.client_ticket,
                                   viewer.invite_path, str(viewer.cstate), str(viewer.client_sock), viewer.session)
        viewer.client_runs += 1
        proc = self._spawn(f"client-{viewer.name}-{viewer.client_runs}", argv, self.env(viewer))
        self.viewer = viewer

        def pending() -> bool:
            if proc.poll() is not None:
                raise HarnessError("client exited")
            return bool(self.host_cli(host, "remote", "enroll", "pending", "--json"))

        if not wait_until(90, pending):
            raise HarnessError(f"no pending enrollment reached the host (client rc={proc.poll()})")

    def approve_pending(self, host: Machine, invitation_id: str) -> None:
        """Approves exactly this invitation at the daemon and waits until the
        viewer's local socket answers; then drops the invite file and starts
        supervising the viewer's client."""
        self.host_cli(host, "remote", "enroll", "approve", invitation_id)
        viewer = self._need_viewer()
        if not wait_until(90, lambda: viewer.client_sock.exists() and self.viewer_ok("workspace", "list", "--json")):
            raise HarnessError("viewer did not come up after approval")
        if viewer.invite_path and os.path.exists(viewer.invite_path):
            os.unlink(viewer.invite_path)
        viewer.invite_path = None
        self._supervise_client(viewer, host)

    def _supervise_client(self, viewer: Machine, host: Machine) -> None:
        """What the ShellX app does for its viewer (Task 12): when `remote
        connect` ends, start it again as an enrolled device (no invite, the
        daemon pinned in the client state dir), with the ticket file the
        refresher keeps fresh, on a 1, 2, 4, 8, 16, 30 s backoff that restarts
        at 1 s once a client has connected (LinkStateMachine: `attempt = 0` on
        `.connected`). Upstream ends the client when the daemon restarted and
        lost its logical session, and on any relay rejection.

        The restart argv is the app's (`enrolled_connect_argv`): one relay
        credential, not the invite spawn's origin triple, because with no invite
        cmux has a single route candidate and refuses a relay credential route
        that is not one. "Connected" is the first `connection-snapshot` line on
        the client's `--json` stdout, as in ShellXClientLinkSupervisor."""
        fingerprint = self.host_cli(host, "remote", "enroll", "status", "--json")["daemon_fingerprint"]
        argv = enrolled_connect_argv(str(self.bin / "cmux-tui"), viewer.client_route, host.slot,
                                     viewer.client_ticket, fingerprint, str(viewer.cstate),
                                     str(viewer.client_sock), viewer.session)
        backoff = (1, 2, 4, 8, 16, 30)

        def loop() -> None:
            attempt = 0
            seen_connected = viewer.client_runs  # the invite client is connected (approve_pending waited)
            while not self._stopping.is_set():
                name = f"client-{viewer.name}-{viewer.client_runs}"
                proc = self._proc(name)
                if seen_connected != viewer.client_runs:
                    try:
                        if log_has_snapshot((self.log_dir / f"{name}.log").read_text(errors="replace")):
                            seen_connected = viewer.client_runs
                            self.note(f"client {viewer.name} connected")
                    except OSError:
                        pass
                if seen_connected == viewer.client_runs:
                    attempt = 0
                if proc is not None and proc.poll() is None:
                    self._stopping.wait(0.2)
                    continue
                delay = backoff[min(attempt, len(backoff) - 1)]
                self.note(f"client {viewer.name} ended (rc={proc.returncode if proc else None}); "
                          f"restart in {delay} s")
                if self._stopping.wait(delay):
                    return
                attempt += 1
                with self._proc_lock:
                    if self._stopping.is_set():
                        return
                    viewer.client_runs += 1
                    self._spawn(f"client-{viewer.name}-{viewer.client_runs}", argv, self.env(viewer))

        self._supervisor = threading.Thread(target=loop, name=f"client-{viewer.name}", daemon=True)
        self._supervisor.start()

    def _need_viewer(self) -> Machine:
        if self.viewer is None:
            raise HarnessError("connect_viewer() first")
        return self.viewer

    def viewer_cli(self, *args: str) -> str:
        viewer = self._need_viewer()
        return self._tui_ok(viewer, ["--socket", str(viewer.client_sock), *args])

    def viewer_ok(self, *args: str) -> bool:
        viewer = self._need_viewer()
        return self._tui(viewer, ["--socket", str(viewer.client_sock), *args], 20).returncode == 0

    def first_terminal(self) -> str:
        """Id of the first terminal the viewer sees (waits for one to appear)."""
        found: list[str] = []

        def look() -> bool:
            found[:] = terminal_ids(json.loads(self.viewer_cli("terminal", "list", "--json")))
            return bool(found)

        if not wait_until(30, look):
            raise HarnessError("viewer sees no terminal")
        return found[0]

    def fake_app_input(self, host: Optional[Machine] = None, settle: float = 0.5, timeout: float = 10) -> bytes:
        """Every input byte the fake app received, in order (all connections),
        once the log has been non-empty and unchanged for `settle` seconds."""
        host = host or self.machines["host"]
        last: Optional[bytes] = None
        stable_since = time.monotonic()
        deadline = time.monotonic() + timeout
        while True:
            data = b""
            if host.app_input_log.exists():
                for line in host.app_input_log.read_text().splitlines():
                    parts = line.split()
                    if len(parts) == 2:
                        data += bytes.fromhex(parts[1])
            now = time.monotonic()
            if data != last:
                last, stable_since = data, now
            elif data and now - stable_since >= settle:
                return data
            if now >= deadline:
                return data
            time.sleep(0.1)

    # evidence and cleanup --------------------------------------------------
    def logs(self) -> list[str]:
        """The text of every log under the harness dir (process output, the
        fake app's logs, cmux's own logs and the harness log)."""
        out = []
        for path in sorted(self.root.rglob("*.log")):
            if path.is_file() and not path.is_symlink():
                out.append(path.read_text(errors="replace"))
        return out

    def secret_leaks(self) -> list[str]:
        """Relative paths of files under the harness dir (all of them, not only
        logs; the fake app's input hex log excluded) that contain an invite URI,
        the run's HMAC secret or the fake account password. Names only, never
        the secret."""
        needles = (b"cmux://enroll/", self.secret.encode(), self.password.encode())
        leaks = []
        if not self.root.exists():
            return leaks
        for path in sorted(self.root.rglob("*")):
            if not path.is_file() or path.is_symlink() or path.name.endswith(".input.log"):
                continue
            try:
                data = path.read_bytes()
            except OSError:
                continue
            if any(n in data for n in needles):
                leaks.append(str(path.relative_to(self.root)))
        return leaks

    def dump_logs(self, stream, lines: int = 80) -> None:
        if not self.root.exists():
            return
        for machine in list(self.machines.values()):
            machine.note_mint_stats()
        for name, proc in list(self.procs.items()):
            print(f"----- process {name} pid={proc.pid} rc={proc.poll()}", file=stream)
        for path in sorted(self.root.rglob("*.log")):
            if not path.is_file() or path.name.endswith(".input.log"):
                continue
            tail = path.read_text(errors="replace").splitlines()[-lines:]
            print(f"----- {path.relative_to(self.root)} (last {len(tail)} lines, redacted) -----", file=stream)
            for line in tail:
                print(self.redact(line), file=stream)
        stream.flush()

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        self._stopping.set()
        if self._supervisor is not None:
            self._supervisor.join(timeout=10)
        for machine in self.machines.values():
            for stop, _, _ in machine.refreshers.values():
                stop.set()
        for name in [n for n in self.procs if n.startswith("client-")]:
            self._stop(name, signal.SIGTERM, 5)
        for name in [n for n in self.procs if n.startswith("daemon-")]:
            self._stop(name, signal.SIGTERM, 10)
        for name in list(self.procs):
            self._stop(name, signal.SIGTERM, 5)
        for machine in self.machines.values():
            machine.stop_refreshers()
        shutil.rmtree(self.root, ignore_errors=True)


def terminal_ids(listing) -> list[str]:
    """Terminal ids from `cmux-tui terminal list --json`, in listed order."""
    value = listing.get("value", listing) if isinstance(listing, dict) else listing
    items = value.get("terminals", value) if isinstance(value, dict) else value
    ids = []
    for item in items if isinstance(items, list) else []:
        if isinstance(item, dict):
            ident = item.get("terminal_id") or item.get("id")
            if ident:
                ids.append(str(ident))
    return ids
