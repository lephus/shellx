#!/usr/bin/env python3
"""Route every SF Symbol in the macOS app through ``ShellXIcon`` (coolicons).

Usage:
    python3 scripts/shellx/icon_codemod.py --list [--sf-names PLIST]
    python3 scripts/shellx/icon_codemod.py --apply

``--list`` prints the literal SF Symbol names the app uses (one per line,
sorted). It was run once before the codemod and frozen in
``scripts/shellx/icon-literal-symbols.txt``; ``tests/test_shellx_icons.py``
checks that every one of them has an entry in ``icon-map.json``. A literal
counts when it is a valid SF Symbol name (CoreGlyphs ``name_availability``)
and either contains a dot (``doc.on.doc``: never plain prose) or sits in an
icon context (its line, or the declaration it belongs to, mentions
symbol/icon/image/glyph/systemName).

``--apply`` rewrites, in ``Sources/``, ``Packages/macOS/*`` and
``Packages/Shared/*``:

* ``Image(systemName: x)``                     -> ``ShellXIcon.image(x)``
* ``NSImage(systemSymbolName: x, accessibilityDescription: d)``
                                              -> ``ShellXIcon.nsImage(x, accessibilityDescription: d)``
* ``Label(title, systemImage: x)``             -> ``ShellXLabel(title, icon: x)``
* ``CmuxSystemSymbolImage(systemName: x, ...)`` -> ``CmuxSystemSymbolImage(symbolName: x, ...)``
  (the view resolves through ``ShellXIcon.nsImage``; the label is renamed so
  the guard pattern stays meaningful)

and adds ``import ShellXIcons`` (after the last unconditional import, never
inside ``#if``) to each file that now names ``ShellXIcon``/``ShellXLabel``.
The rewrite is idempotent. Strings and comments are never rewritten. The
ShellXIcons package itself and the custom sidebar DSL's user-written Swift
(``SKIP_PREFIXES``) are skipped; see ``tests/test_shellx_icons.py``.

Not covered (done by hand once, guarded by the test): project-owned
wrappers whose parameter is labelled ``systemImage:`` (renamed ``icon:``),
``ContentUnavailableView(_:systemImage:description:)`` and comments that
spell the SF Symbol APIs.
"""
from __future__ import annotations

import argparse
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ROOTS = ["Sources", "Packages/macOS", "Packages/Shared"]
SNAPSHOT = ROOT / "scripts/shellx/icon-literal-symbols.txt"
SF_NAMES_PLIST = Path("/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist")

# Never rewritten: the ShellXIcon implementation itself and the custom
# sidebar DSL, whose *user-written* Swift source spells `Image(systemName:)`.
SKIP_PREFIXES = (
    "Packages/Shared/ShellXBrand/",
    "Packages/macOS/CmuxSwiftRender/Tests/CmuxSwiftRenderTests/Corpus/",
    "Packages/macOS/CmuxSwiftRender/Tests/CmuxSwiftRenderTests/SwiftViewInterpreterTests.swift",
)

# Valid SF Symbol names that only ever appear as key/letter strings here.
NOT_ICONS = {"a", "k"}
ICON_CONTEXT = re.compile(r"(?i)symbol|icon|image|glyph|systemname")
DECL = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|package|static|class|"
    r"nonisolated|override|final|lazy|mutating|indirect)\s+)*(?:var|let|func|enum|struct|class|extension)\s+`?(\w+)"
)


def swift_files() -> list[Path]:
    files: list[Path] = []
    for root in ROOTS:
        for path in sorted((ROOT / root).rglob("*.swift")):
            rel = path.relative_to(ROOT).as_posix()
            if "/.build/" in f"/{rel}" or rel.startswith(SKIP_PREFIXES):
                continue
            files.append(path)
    return files


_TOP_LEVEL_TOKEN = re.compile(r'//|/\*|(#*)("""|")')
_BLOCK_COMMENT_TOKEN = re.compile(r"/\*|\*/")
_STRING_TOKENS: dict[tuple[bool, int], "re.Pattern[str]"] = {}


def mask(text: str) -> str:
    """Blank out comments and string-literal contents (same length, newlines
    kept) so code patterns never match inside them. Interpolations
    ``\\( ... )`` inside strings are kept as code. Escapes (``\\"``) are left
    as they are. Jumps from token to token with regexes; a whole-tree pass
    takes a few seconds."""
    out = list(text)
    n = len(text)

    def blank(a: int, b: int, fill: str) -> None:
        out[a:b] = ["\n" if c == "\n" else fill for c in text[a:b]]

    def skip_string(j: int, multiline: bool, hashes: int) -> int:
        token = _STRING_TOKENS.get((multiline, hashes))
        if token is None:
            close = ('"""' if multiline else '"') + "#" * hashes
            token = re.compile(re.escape("\\" + "#" * hashes) + "|" + re.escape(close) + ("" if multiline else r"|\n"))
            _STRING_TOKENS[(multiline, hashes)] = token
        while True:
            m = token.search(text, j)
            if m is None:
                blank(j, n, "_")
                return n
            blank(j, m.start(), "_")
            if not m.group().startswith("\\"):
                return m.start()  # the closing quote, or the end of a single-line string
            k = m.end()
            if k < n and text[k] == "(":
                depth = 0
                while k < n:
                    if text[k] == "(":
                        depth += 1
                    elif text[k] == ")":
                        depth -= 1
                        if depth == 0:
                            break
                    k += 1
            j = k + 1

    i = 0
    while i < n:
        m = _TOP_LEVEL_TOKEN.search(text, i)
        if m is None:
            break
        i = m.start()
        if m.group() == "//":
            j = text.find("\n", i)
            j = n if j < 0 else j
            blank(i, j, " ")
            i = j
        elif m.group() == "/*":
            depth, j = 0, i
            while True:
                c = _BLOCK_COMMENT_TOKEN.search(text, j)
                if c is None:
                    j = n
                    break
                j = c.end()
                depth += 1 if c.group() == "/*" else -1
                if depth == 0:
                    break
            blank(i, j, " ")
            i = j
        else:
            hashes = len(m.group(1))
            multiline = m.group(2) == '"""'
            end = skip_string(m.end(), multiline, hashes)
            i = end + (3 if multiline else 1) + hashes
    return "".join(out)


def matching_paren(masked: str, open_idx: int) -> int:
    depth = 0
    for i in range(open_idx, len(masked)):
        c = masked[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return i
    raise ValueError("unbalanced parentheses")


def top_level_label_spans(masked: str, open_idx: int, close_idx: int) -> dict[str, tuple[int, int]]:
    """Return {label: (start, end)} for top-level argument labels in a call."""
    labels: dict[str, tuple[int, int]] = {}
    depth = 0
    i = open_idx + 1
    arg_start = True
    while i < close_idx:
        c = masked[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            arg_start = True
            i += 1
            continue
        if depth == 0 and arg_start and not c.isspace():
            m = re.match(r"(\w+)\s*:(?!:)", masked[i:close_idx])
            if m:
                labels[m.group(1)] = (i, i + len(m.group(1)))
            arg_start = False
        i += 1
    return labels


# ---------------------------------------------------------------- --list

def sf_symbol_names(plist: Path) -> set[str]:
    with plist.open("rb") as fh:
        return set(plistlib.load(fh)["symbols"].keys())


def literal_symbols(sf_names: set[str]) -> set[str]:
    found: set[str] = set()
    for path in swift_files():
        text = path.read_text(encoding="utf-8")
        masked = mask(text)
        lines = text.splitlines()
        # Literal string tokens: masked text has `"___"` where code had a literal.
        for m in re.finditer(r'"(_+)"', masked):
            literal = text[m.start(1) : m.end(1)]
            if literal not in sf_names or literal in NOT_ICONS:
                continue
            if "." in literal:
                found.add(literal)
                continue
            line_no = text.count("\n", 0, m.start())
            if ICON_CONTEXT.search(masked.splitlines()[line_no]):
                found.add(literal)
                continue
            # Otherwise use the enclosing declaration's name (a `symbolName`
            # computed property, an `IconOption` enum's raw values, ...).
            for back in range(line_no, max(-1, line_no - 60), -1):
                d = DECL.match(lines[back])
                if d:
                    if ICON_CONTEXT.search(d.group(1)):
                        found.add(literal)
                    break
    return found


ICON_API_CALLS = {
    # call pattern: argument label holding the SF Symbol name (None: the first argument)
    r"\bShellXIcon\.(?:image|nsImage)\(": None,
    r"(?<![\w.])ShellXLabel\(": ("icon",),
    r"(?<![\w.])CmuxSystemSymbolImage\(": ("symbolName", "magnified"),
}


def literals_at_icon_calls() -> list[tuple[str, int, str]]:
    """(path, line, literal) for every string literal in the symbol-name
    argument of a ShellXIcon / ShellXLabel / CmuxSystemSymbolImage call.
    Each must be in icon-map.json, or the call quietly draws an SF Symbol."""
    found = []
    for path in swift_files():
        text = path.read_text(encoding="utf-8")
        masked = mask(text)
        for pattern, labels in ICON_API_CALLS.items():
            for m in re.finditer(pattern, masked):
                open_idx = m.end() - 1
                close_idx = matching_paren(masked, open_idx)
                spans = top_level_label_spans(masked, open_idx, close_idx)
                if labels is None:
                    start = open_idx + 1
                else:
                    hit = next((label for label in labels if label in spans), None)
                    if hit is None:
                        continue
                    start = spans[hit][1]
                ends = sorted(s for s, _ in spans.values() if s > start)
                end = ends[0] if ends else close_idx
                if labels is None:
                    depth, i = 0, start
                    while i < end:
                        if masked[i] in "([{":
                            depth += 1
                        elif masked[i] in ")]}":
                            depth -= 1
                        elif masked[i] == "," and depth == 0:
                            end = i
                            break
                        i += 1
                for lit in re.finditer(r'"(_*)"', masked[start:end]):
                    a, b = start + lit.start(1), start + lit.end(1)
                    found.append((path.relative_to(ROOT).as_posix(), text.count("\n", 0, a) + 1, text[a:b]))
    return found


# ---------------------------------------------------------------- --apply

IMAGE_CALL = re.compile(r"(?<![\w.])Image\((\s*)systemName:\s*")
NSIMAGE_CALL = re.compile(r"(?<![\w.])NSImage\((\s*)systemSymbolName:\s*")
LABEL_CALL = re.compile(r"(?<![\w.])Label\(")
CMUX_SYMBOL_CALL = re.compile(r"(?<![\w.])CmuxSystemSymbolImage\((\s*)systemName:")


def rewrite(text: str) -> tuple[str, dict[str, int]]:
    counts = {"Image(systemName:)": 0, "NSImage(systemSymbolName:)": 0, "Label(systemImage:)": 0,
              "CmuxSystemSymbolImage(systemName:)": 0}
    edits: list[tuple[int, int, str]] = []
    masked = mask(text)

    for m in IMAGE_CALL.finditer(masked):
        edits.append((m.start(), m.end(), f"ShellXIcon.image({m.group(1)}"))
        counts["Image(systemName:)"] += 1
    for m in NSIMAGE_CALL.finditer(masked):
        edits.append((m.start(), m.end(), f"ShellXIcon.nsImage({m.group(1)}"))
        counts["NSImage(systemSymbolName:)"] += 1
    for m in CMUX_SYMBOL_CALL.finditer(masked):
        edits.append((m.start(), m.end(), f"CmuxSystemSymbolImage({m.group(1)}symbolName:"))
        counts["CmuxSystemSymbolImage(systemName:)"] += 1
    for m in LABEL_CALL.finditer(masked):
        open_idx = m.end() - 1
        close_idx = matching_paren(masked, open_idx)
        labels = top_level_label_spans(masked, open_idx, close_idx)
        if "systemImage" not in labels:
            continue
        edits.append((m.start(), m.start() + len("Label"), "ShellXLabel"))
        a, b = labels["systemImage"]
        edits.append((a, b, "icon"))
        counts["Label(systemImage:)"] += 1

    if not edits:
        return text, counts
    edits.sort()
    out, last = [], 0
    for a, b, new in edits:
        if a < last:
            raise ValueError("overlapping edits")
        out.append(text[last:a])
        out.append(new)
        last = b
    out.append(text[last:])
    new_text = "".join(out)
    # The CmuxSystemSymbolImage label rename alone needs no import.
    if re.search(r"\bShellX(?:Icon|Label)\b", mask(new_text)):
        new_text = add_import(new_text)
    return new_text, counts


IMPORT_LINE = re.compile(r"^(?:@[\w()]+\s+)*(?:(?:public|internal|private|fileprivate|package)\s+)?import\s+\w")


def add_import(text: str) -> str:
    """Add `import ShellXIcons` after the file's last unconditional import
    (never inside an `#if` block), or above the first declaration when the
    file has no unconditional import."""
    if re.search(r"^(?:@[\w()]+\s+)*(?:\w+\s+)?import ShellXIcons\s*$", text, re.M):
        return text
    lines = text.split("\n")
    depth = 0
    last_import = None
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("#if"):
            depth += 1
        elif stripped.startswith("#endif"):
            depth -= 1
        elif stripped.startswith(("#else", "#elseif")) or not stripped or stripped.startswith(("//", "/*", "*")):
            pass
        elif IMPORT_LINE.match(stripped):
            if depth == 0:
                last_import = index
        else:
            break  # the first declaration ends the import section
    if last_import is not None:
        lines.insert(last_import + 1, "import ShellXIcons")
        return "\n".join(lines)
    # No unconditional import: insert after the leading comment header (a
    # doc comment belongs to the declaration below it).
    insert_at = 0
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith(("///", "/**")) or (stripped and not stripped.startswith(("//", "/*", "*"))):
            break
        insert_at = index + 1
    lines.insert(insert_at, "import ShellXIcons")
    return "\n".join(lines)


def apply() -> dict[str, int]:
    totals: dict[str, int] = {}
    files = 0
    for path in swift_files():
        text = path.read_text(encoding="utf-8")
        new, counts = rewrite(text)
        if new != text:
            path.write_text(new, encoding="utf-8")
            files += 1
        for k, v in counts.items():
            totals[k] = totals.get(k, 0) + v
    totals["files"] = files
    return totals


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--list", action="store_true", help="print literal SF Symbol names in use")
    group.add_argument("--apply", action="store_true", help="rewrite call sites to ShellXIcon")
    parser.add_argument("--sf-names", type=Path, default=SF_NAMES_PLIST)
    args = parser.parse_args(argv)
    if args.list:
        print("# Literal SF Symbol names used by the macOS app before the coolicons codemod.")
        print("# Frozen output of `python3 scripts/shellx/icon_codemod.py --list` (2026-10-19, macOS 26 CoreGlyphs).")
        for name in sorted(literal_symbols(sf_symbol_names(args.sf_names))):
            print(name)
        return 0
    totals = apply()
    for k, v in totals.items():
        print(f"{k}: {v}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
