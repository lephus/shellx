#!/usr/bin/env python3
"""Stand-in for the ShellX macOS app on the virtual PTY socket (no libghostty).

Ported from the W0 bridge spike (shellx/w0-bridge @ 4e1ed7bc41,
spikes/protocol/mac-bridge/fake_app.py). Speaks the frame protocol of
cmux-tui/crates/cmux-tui-core/src/virtual_pty.rs:

    frame = [type u8][len u32 BE][payload], payload <= 16 MiB
    daemon -> app: H hello {"protocol":1,"cols","rows","cwd"}, I input,
                   R resize wish (cols,rows u16 BE), K kill
    app -> daemon: A ack {"surface_id","workspace_id","mode"}, O output,
                   S real grid (cols,rows u16 BE), E exit

Each connection is one terminal. The first terminal while none is bound
attaches to the "focused" Mac terminal (mode=attach); every later one is a new
tab (mode=create), as in sprint rule D7. A hello whose protocol is not 1 is
refused (the connection is closed without an ack). The app owns the grid: it
answers every resize wish with its own grid (the forced echo), and echoes input
back as output the way a shell with echo on would.

--log gets one line per event; --input-log gets the hex of every I payload,
one frame per line ("<conn> <hex>"), so a test can check input byte-exact.
--name puts a name in the banner, so a viewer can tell two hosts' apps apart.

    fake_app.py --socket <dir>/s.sock --log app.log --input-log input.hex [--name e2e-host]
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import socket
import struct
import sys
import threading
import time

PROTOCOL = 1
MAX_FRAME = 16 * 1024 * 1024


def banner(name: str = "") -> bytes:
    """`SHELLX-FAKE-APP [<name> ]ready` and a prompt."""
    label = f"{name} " if name else ""
    return (b"\x1b[1;32mSHELLX-FAKE-APP\x1b[0m " + label.encode() + b"ready\r\n"
            b"\x1b[34mfake@mac\x1b[0m:~$ ")


class App:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.lock = threading.Lock()
        self.bound = 0
        self.count = 0

    def log(self, msg: str) -> None:
        with self.lock, open(self.args.log, "a", encoding="utf-8") as f:
            f.write(f"{time.time():.3f} {msg}\n")

    def log_input(self, conn_id: int, payload: bytes) -> None:
        with self.lock, open(self.args.input_log, "a", encoding="ascii") as f:
            f.write(f"{conn_id} {payload.hex()}\n")

    def serve(self, conn: socket.socket, n: int) -> None:
        bound = False
        try:
            kind, payload = read_frame(conn)
            if kind != "H":
                self.log(f"conn {n} refused: first frame {kind!r} is not a hello")
                return
            hello = json.loads(payload)
            if hello.get("protocol") != PROTOCOL:
                self.log(f"conn {n} refused: protocol {hello.get('protocol')!r} (want {PROTOCOL})")
                return
            with self.lock:
                mode = "attach" if self.bound == 0 else "create"
                self.bound += 1
                bound = True
            self.log(f"conn {n} hello cols={hello.get('cols')} rows={hello.get('rows')} mode={mode}")
            ack = {"surface_id": f"fake-surface-{n}", "workspace_id": "fake-workspace", "mode": mode}
            conn.sendall(frame("A", json.dumps(ack).encode()))
            conn.sendall(frame("S", struct.pack(">HH", self.args.cols, self.args.rows)))
            conn.sendall(frame("O", banner(self.args.name)))
            while True:
                kind, payload = read_frame(conn)
                if kind == "I":
                    self.log_input(n, payload)
                    self.log(f"conn {n} input {len(payload)} bytes")
                    conn.sendall(frame("O", payload.replace(b"\r", b"\r\n")))
                elif kind == "R":
                    self.log(f"conn {n} resize-wish {struct.unpack('>HH', payload)}")
                    conn.sendall(frame("S", struct.pack(">HH", self.args.cols, self.args.rows)))
                elif kind == "K":
                    self.log(f"conn {n} kill")
                    return
                else:
                    self.log(f"conn {n} ignored frame {kind!r}")
        except EOFError:
            self.log(f"conn {n} eof")
        except (OSError, ValueError) as error:
            self.log(f"conn {n} error {type(error).__name__}")
        finally:
            if bound:
                with self.lock:
                    self.bound -= 1
            conn.close()

    def run(self) -> None:
        path = self.args.socket
        if os.path.lexists(path):
            os.unlink(path)
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(path)
        os.chmod(path, 0o600)
        srv.listen(16)
        self.log(f"listening {path}")
        while True:
            conn, _ = srv.accept()
            with self.lock:
                self.count += 1
                n = self.count
            threading.Thread(target=self.serve, args=(conn, n), daemon=True).start()


def frame(kind: str, payload: bytes = b"") -> bytes:
    return bytes([ord(kind)]) + struct.pack(">I", len(payload)) + payload


def read_exact(conn: socket.socket, n: int) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise EOFError
        buf += chunk
    return bytes(buf)


def read_frame(conn: socket.socket) -> tuple[str, bytes]:
    header = read_exact(conn, 5)
    length = struct.unpack(">I", header[1:])[0]
    if length > MAX_FRAME:
        raise ValueError("frame too large")
    return chr(header[0]), read_exact(conn, length)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--socket", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--input-log", required=True)
    ap.add_argument("--cols", type=int, default=100)
    ap.add_argument("--rows", type=int, default=30)
    ap.add_argument("--name", default="")
    args = ap.parse_args()
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    App(args).run()


if __name__ == "__main__":
    main()
