#!/usr/bin/env python3
"""Turns the tail of the remote e2e log into GitHub error annotations.

CI job logs need authentication to read; check-run annotations do not. After a
failed "Remote e2e" step the workflow runs

    python3 scripts/shellx/remote-e2e/annotate_log.py "$RUNNER_TEMP/e2e.log"

which prints workflow commands (`::error title=...::message`) on stdout:
one annotation with the names of the failing tests (`FAIL:` / `ERROR:` lines of
the unittest summary), then a window of the log split into at most MAX_CHUNKS
parts. That is at most 10 annotations, GitHub's limit of error annotations per
step.

The window (`window`) starts at the last per-process dump of the harness
(Harness.dump_logs prints a block of `----- process` lines first) and runs to
the end of the log, so it holds the failing test's process logs and the
unittest report after them. A window longer than MAX_WINDOW_LINES keeps its
head and the last TAIL_LINES lines. Without a dump it is the last TAIL_LINES
lines. Each annotation stays under MAX_MESSAGE_BYTES (the Checks API caps an
annotation message at 64 KB).

The log is already redacted by Harness.dump_logs, but this filters again: a
line that matches a ticket, an enrollment invite or a secret assignment is
replaced by a placeholder, never printed (an `assertNotRegex` failure message,
for one, carries the whole text it matched in unredacted). Escape sequences
and control characters are removed BEFORE that check, so a ticket that a
control character splits in two is still caught. Stdlib only; the patterns are
the harness's own.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Optional, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import DUMP_MARKER, INVITE_RE, TICKET_RE  # noqa: E402

TAIL_LINES = 200
MAX_CHUNKS = 9
MAX_WINDOW_LINES = 1080
MAX_LINE_CHARS = 400
MAX_MESSAGE_BYTES = 60_000
MAX_FAILING_NAMES = 20
DROPPED = "[line dropped: it matched a ticket, invite or secret pattern]"
SECRET_RE = re.compile(r"(?:CMUX_RELAY_HMAC_SECRET|SHELLX_FAKE_PASSWORD)\s*[=:]")
FAILING_RE = re.compile(r"^(?:FAIL|ERROR): ")
ESCAPE_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
CONTROL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


def escape_message(text: str) -> str:
    """The data escaping of a GitHub workflow command."""
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def escape_property(text: str) -> str:
    """The property (`title=`) escaping of a GitHub workflow command."""
    return escape_message(text).replace(":", "%3A").replace(",", "%2C")


def clean_line(line: str) -> str:
    """`line` safe to print: escape sequences and control characters removed
    first, then a placeholder when what is left matches a ticket, an invite or
    a secret assignment; long lines cut."""
    line = CONTROL_RE.sub("", ESCAPE_RE.sub("", line))
    if TICKET_RE.search(line) or INVITE_RE.search(line) or SECRET_RE.search(line):
        return DROPPED
    return line if len(line) <= MAX_LINE_CHARS else line[:MAX_LINE_CHARS] + "..."


def chunk(lines: Sequence[str], max_chunks: int = MAX_CHUNKS) -> list[list[str]]:
    """`lines` in order as at most `max_chunks` runs of equal size (the last may
    be shorter)."""
    if not lines:
        return []
    size = -(-len(lines) // max_chunks)
    return [list(lines[start:start + size]) for start in range(0, len(lines), size)]


def window(lines: Sequence[str]) -> list[str]:
    """The part of the log to annotate: from the first line of the last block
    of DUMP_MARKER lines to the end; at most MAX_WINDOW_LINES (the head and the
    last TAIL_LINES, with a line saying how many were left out). Without a
    marker: the last TAIL_LINES lines."""
    start = None
    for index in range(len(lines) - 1, -1, -1):
        if lines[index].startswith(DUMP_MARKER):
            start = index
        elif start is not None:
            break
    if start is None:
        return list(lines[-TAIL_LINES:])
    selected = list(lines[start:])
    if len(selected) <= MAX_WINDOW_LINES:
        return selected
    head = selected[:MAX_WINDOW_LINES - TAIL_LINES - 1]
    omitted = len(selected) - len(head) - TAIL_LINES
    return head + [f"[{omitted} lines omitted]"] + selected[-TAIL_LINES:]


def fit(lines: Sequence[str], budget: int = MAX_MESSAGE_BYTES) -> list[str]:
    """`lines` while their escaped message stays within `budget` bytes; a last
    line says how many were cut."""
    out: list[str] = []
    size = 0
    for index, line in enumerate(lines):
        cost = len(escape_message(line).encode()) + len("%0A")
        if size + cost > budget - 100:
            out.append(f"[{len(lines) - index} lines cut: annotation size limit]")
            break
        out.append(line)
        size += cost
    return out


def failing_tests(text: str) -> list[str]:
    """The `FAIL: ...` and `ERROR: ...` lines of the unittest summary, once each."""
    names: list[str] = []
    for line in text.splitlines():
        if FAILING_RE.match(line):
            name = clean_line(line)
            if name not in names:
                names.append(name)
    return names[:MAX_FAILING_NAMES]


def command(title: str, message: str) -> str:
    return f"::error title={escape_property(title)}::{escape_message(message)}"


def build_commands(text: str) -> list[str]:
    """The workflow commands for a log: the failing tests, then the log tail."""
    names = failing_tests(text)
    commands = [command("e2e failing tests",
                        "\n".join(names) if names else "no FAIL:/ERROR: line in the log; see the parts below")]
    parts = chunk([clean_line(line) for line in window(text.splitlines())])
    for number, lines in enumerate(parts, start=1):
        commands.append(command(f"e2e log (part {number}/{len(parts)})", "\n".join(fit(lines))))
    return commands


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 1:
        print("usage: annotate_log.py LOG_FILE", file=sys.stderr)
        return 2
    try:
        text = Path(args[0]).read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        print(command("e2e log", f"cannot read the e2e log: {type(error).__name__}"))
        return 0
    for line in build_commands(text):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
