"""Shared helpers for the ShellX look-lane guard tests (L2).

Prefers the identity lane's `shellx_guard` when present; otherwise defines
the same functions locally with identical signatures.
"""
from __future__ import annotations

import hashlib
import os
import re
import struct
from pathlib import Path

try:  # pragma: no cover - depends on lane merge order
    from shellx_guard import offenders, png_size, read, sha256  # type: ignore
except ImportError:
    ROOT = Path(__file__).resolve().parent.parent

    def read(path: str) -> str:
        return (ROOT / path).read_text(encoding="utf-8")

    def offenders(pattern: str, roots: list[str], allow: list[tuple[str, str]]) -> list[str]:
        rx = re.compile(pattern)
        allowed = {p for p, _reason in allow}
        hits: list[str] = []
        for root in roots:
            base = ROOT / root
            files = [base] if base.is_file() else sorted(p for p in base.rglob("*") if p.is_file())
            for f in files:
                rel = f.relative_to(ROOT).as_posix()
                if rel in allowed:
                    continue
                try:
                    text = f.read_text(encoding="utf-8")
                except (UnicodeDecodeError, OSError):
                    continue
                for n, line in enumerate(text.splitlines(), 1):
                    if rx.search(line):
                        hits.append(f"{rel}:{n}")
        return hits

    def png_size(path: str) -> tuple[int, int]:
        with open(ROOT / path, "rb") as fh:
            head = fh.read(24)
        if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
            raise ValueError(f"not a PNG: {path}")
        w, h = struct.unpack(">II", head[16:24])
        return w, h

    def sha256(path: str) -> str:
        return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
