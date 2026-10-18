#!/usr/bin/env python3
"""Fail if Cargo.lock/metadata has a forbidden crate or a license outside the allowlist."""
import json
import re
import subprocess
import sys

ALLOWED = {
    "MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "ISC", "Zlib",
    "Unicode-3.0", "MPL-2.0", "CDLA-Permissive-2.0",
}
FORBIDDEN_EXACT = {"openssl", "openssl-sys", "native-tls"}
FORBIDDEN_FAMILIES = ("iroh", "aws-lc")  # the name itself, or "<family>-*"
KNOWN_EXCEPTIONS = {"LLVM-exception"}


def is_forbidden(name: str) -> bool:
    return name in FORBIDDEN_EXACT or any(
        name == f or name.startswith(f + "-") for f in FORBIDDEN_FAMILIES
    )


# Workspace members are ours (GPL-3.0-or-later).
OWN_LICENSE = "GPL-3.0-or-later"


def ok_expr(expr: str) -> bool:
    """SPDX subset, fail closed: `A OR B` passes if any alternative passes, `A AND B`
    needs all. Operators are case-insensitive; `WITH` only for KNOWN_EXCEPTIONS; every
    token must be consumed; anything unparsable fails."""
    expr = expr.replace("/", " OR ")
    tokens = re.findall(r"\(|\)|[^\s()]+", expr)
    pos = 0

    def peek():
        return tokens[pos].upper() if pos < len(tokens) else None

    def parse_or():
        nonlocal pos
        v = parse_and()
        while peek() == "OR":
            pos += 1
            r = parse_and()
            v = v or r
        return v

    def parse_and():
        nonlocal pos
        v = parse_atom()
        while peek() == "AND":
            pos += 1
            r = parse_atom()
            v = v and r
        return v

    def parse_atom():
        nonlocal pos
        t = tokens[pos]  # IndexError -> fail closed
        pos += 1
        if t == "(":
            v = parse_or()
            if pos >= len(tokens) or tokens[pos] != ")":
                raise ValueError("unclosed (")
            pos += 1
            return v
        if t == ")" or t.upper() in ("AND", "OR", "WITH"):
            raise ValueError("unexpected token")
        v = t in ALLOWED
        if peek() == "WITH":
            pos += 1
            exc = tokens[pos]
            pos += 1
            v = v and exc in KNOWN_EXCEPTIONS
        return v

    try:
        v = parse_or()
        return v and pos == len(tokens)
    except (IndexError, ValueError):
        return False


def main() -> int:
    raw = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--locked"],
        check=True, capture_output=True, text=True,
    ).stdout
    meta = json.loads(raw)
    members = set(meta["workspace_members"])
    bad = []
    for p in meta["packages"]:
        name = p["name"]
        if is_forbidden(name):
            bad.append(f"{name} {p['version']}: forbidden crate")
            continue
        lic = p.get("license") or ""
        if p["id"] in members:
            if lic != OWN_LICENSE:
                bad.append(f"{name}: workspace license must be {OWN_LICENSE}, got {lic!r}")
            continue
        if not lic or not ok_expr(lic):
            bad.append(f"{name} {p['version']}: license {lic!r} not allowed")
    if bad:
        print("\n".join(bad))
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
