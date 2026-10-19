#!/usr/bin/env python3
"""Print GitHub Actions annotations for the failures in an xcodebuild log.

Job logs and artifacts need an authenticated API call, but check-run
annotations are public, so a lane without `gh` can still read why a build
failed. Usage: annotate-log.py LOG [TITLE]
"""

import re
import sys

PATTERN = re.compile(
    r"error:|\*\* (BUILD|TEST) FAILED|Failing tests|Test Case .* failed|Issue recorded|✘|Undefined symbols|ld: "
)
MAX_LINES = 60
MAX_WIDTH = 400


def escape(text):
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def main(argv):
    if len(argv) < 2:
        print("usage: annotate-log.py LOG [TITLE]", file=sys.stderr)
        return 2
    title = argv[2] if len(argv) > 2 else "xcodebuild"
    seen = []
    with open(argv[1], errors="replace") as handle:
        for line in handle:
            line = line.rstrip()
            if PATTERN.search(line) and line not in seen:
                seen.append(line[:MAX_WIDTH])
    if not seen:
        print(f"::error title={title}::no error lines found in {argv[1]}")
        return 0
    body = "\n".join(seen[:MAX_LINES])
    if len(seen) > MAX_LINES:
        body += f"\n... {len(seen) - MAX_LINES} more"
    print(f"::error title={title} errors::{escape(body)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
