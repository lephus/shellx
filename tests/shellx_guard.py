"""Shared helpers for the ShellX static guards (tests/test_shellx_*.py).

Paths are repository-relative POSIX strings and resolve against the repository
root, so the guards behave the same whatever the current directory is.
"""

import hashlib
import os
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Directories never scanned by offenders(): VCS metadata, dependency checkouts
# and build output are not ShellX sources.
_SKIPPED_DIRS = frozenset({
    ".git", ".build", ".swiftpm", "build", "DerivedData", "node_modules", "__pycache__",
})


def _resolve(path):
    return ROOT / path


def read(path):
    """The text of the repository file at `path`."""
    return _resolve(path).read_text(encoding="utf-8")


def _is_allowed(rel_path, allow):
    for allowed_path, _reason in allow:
        if allowed_path.endswith("/"):
            if rel_path.startswith(allowed_path):
                return True
        elif rel_path == allowed_path:
            return True
    return False


def _text_lines(file_path):
    try:
        data = file_path.read_bytes()
    except OSError:
        return None
    if b"\0" in data[:8192]:
        return None
    try:
        return data.decode("utf-8").splitlines()
    except UnicodeDecodeError:
        return None


def _walk(root_path):
    if root_path.is_file():
        yield root_path
        return
    for dirpath, dirnames, filenames in os.walk(root_path):
        dirnames[:] = sorted(d for d in dirnames if d not in _SKIPPED_DIRS)
        for name in sorted(filenames):
            yield Path(dirpath) / name


def offenders(pattern, roots, allow):
    """`"path:line"` for every line matching `pattern` in text files under `roots`.

    `allow` is a list of `(path, reason)`; a hit in an allowed file is skipped. A
    path ending in "/" allows every file below that directory. Every entry needs
    a reason so the allowlist documents why the name is still there.
    """
    for entry in allow:
        if len(entry) != 2 or not entry[1].strip():
            raise ValueError(f"allow entry needs (path, reason): {entry!r}")
    regex = re.compile(pattern)
    hits = []
    for root in roots:
        root_path = _resolve(root)
        if not root_path.exists():
            continue
        for file_path in _walk(root_path):
            rel_path = file_path.relative_to(ROOT).as_posix()
            if _is_allowed(rel_path, allow):
                continue
            lines = _text_lines(file_path)
            if lines is None:
                continue
            for number, line in enumerate(lines, start=1):
                if regex.search(line):
                    hits.append(f"{rel_path}:{number}")
    return hits


def png_size(path):
    """`(width, height)` from the IHDR chunk of the PNG at `path`."""
    with open(_resolve(path), "rb") as f:
        header = f.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"not a PNG file: {path}")
    width, height = struct.unpack(">II", header[16:24])
    return width, height


def sha256(path):
    """Hex SHA-256 digest of the file at `path`."""
    digest = hashlib.sha256()
    with open(_resolve(path), "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()
