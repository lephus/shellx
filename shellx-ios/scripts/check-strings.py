#!/usr/bin/env python3
"""Checks that every string the ShellX iOS app shows exists in English and Vietnamese.

    check-strings.py [--root <shellx-ios dir>]

Exits 1 and prints each problem when:
  - a catalog key (ShellX/**/*.xcstrings) lacks a translated, non-empty `en` or `vi` value,
    including every plural branch the language needs (en: one, other; vi: other);
  - a key has `extractionState: stale`;
  - the `vi` text equals the `en` text and the key is not listed in scripts/strings-identity.txt;
  - a key used in ShellX/**/*.swift as `String(localized: "<key>"` or
    `LocalizedStringResource("<key>"` is not in its catalog (Localizable, or the `table:` given);
  - ShellX/**/*.swift has a bare literal `Text("`, `Button("`, `Label("`, `.navigationTitle("`
    or `.alert("`. Use a catalog key, or `Text(verbatim:)` for text that is never translated.
Keys marked `shouldTranslate: false` need no translations.
"""

import argparse
import json
import os
import re
import sys

LANGUAGES = ("en", "vi")
PLURAL_BRANCHES = {"en": ("one", "other"), "vi": ("other",)}
DEFAULT_TABLE = "Localizable"

BARE_LITERAL = re.compile(r'(?<![A-Za-z0-9_])(?:Text|Button|Label)\(\s*"|\.(?:navigationTitle|alert)\(\s*"')
KEY_USE = re.compile(r'(?<![A-Za-z0-9_])(?:String\(\s*localized:|LocalizedStringResource\()\s*"')
TABLE_ARGUMENT = re.compile(r'\s*,[^)]*?\btable:\s*"([^"]+)"')
COMMENT_LINE = ("//", "/*", "*")
# A printf-style specifier, which is what a Swift interpolation becomes in a catalog key.
FORMAT_SPECIFIER = r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?[@dDuUxXoOfFeEgGcCsSpaA]"
SWIFT_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", '"': '"', "'": "'", "\\": "\\"}


def string_units(node, path=()):
    """Yields (path, stringUnit) for every stringUnit in one localization."""
    if not isinstance(node, dict):
        return
    if isinstance(node.get("stringUnit"), dict):
        yield path, node["stringUnit"]
    for name, child in sorted(node.items()):
        if name != "stringUnit" and isinstance(child, dict):
            yield from string_units(child, path + (name,))


def check_localization(key, language, localization, problems, where):
    if not isinstance(localization, dict):
        problems.append('%s: "%s": %s is missing' % (where, key, language))
        return {}
    units = list(string_units(localization))
    if not units:
        problems.append('%s: "%s": %s has no text' % (where, key, language))
    values = {}
    for path, unit in units:
        label = "/".join(path) or "value"
        value = unit.get("value", "")
        if unit.get("state") != "translated":
            problems.append('%s: "%s": %s %s is "%s", not translated' % (where, key, language, label, unit.get("state")))
        if not isinstance(value, str) or not value.strip():
            problems.append('%s: "%s": %s %s is empty' % (where, key, language, label))
        values[path] = value
    plural = localization.get("variations", {}).get("plural")
    if isinstance(plural, dict):
        for branch in PLURAL_BRANCHES[language]:
            if branch not in plural:
                problems.append('%s: "%s": %s plural lacks "%s"' % (where, key, language, branch))
    return values


def check_catalog(path, display, identity, problems):
    """Checks one .xcstrings file and returns its keys."""
    try:
        with open(path, encoding="utf-8") as handle:
            catalog = json.load(handle)
    except (OSError, ValueError) as error:
        problems.append("%s: unreadable catalog (%s)" % (display, error))
        return set()
    strings = catalog.get("strings", {})
    for key, entry in sorted(strings.items()):
        if entry.get("extractionState") == "stale":
            problems.append('%s: "%s": stale (no longer used in code); delete it' % (display, key))
        if entry.get("shouldTranslate") is False:
            continue
        localizations = entry.get("localizations", {})
        values = {
            language: check_localization(key, language, localizations.get(language), problems, display)
            for language in LANGUAGES
        }
        english, vietnamese = values["en"], values["vi"]
        copied = vietnamese and all(english.get(path) == text for path, text in vietnamese.items())
        if copied and key not in identity:
            problems.append(
                '%s: "%s": vi is the English text; translate it, or list the key in scripts/strings-identity.txt'
                % (display, key))
    return set(strings)


def swift_literal(text, start):
    """Parses the Swift string literal whose opening quote ends at `start`.

    Returns (parts, end): the literal text between interpolations, and the index after the closing
    quote. Returns (None, start) for a literal it cannot follow (multi-line, unterminated)."""
    parts, current, index = [], [], start
    while index < len(text):
        char = text[index]
        if char == '"':
            parts.append("".join(current))
            return parts, index + 1
        if char == "\n":
            return None, start
        if char == "\\" and index + 1 < len(text):
            following = text[index + 1]
            if following == "(":
                depth, index = 1, index + 2
                while index < len(text) and depth:
                    depth += {"(": 1, ")": -1}.get(text[index], 0)
                    index += 1
                parts.append("".join(current))
                current = []
                continue
            if following == "u" and text[index + 2:index + 3] == "{":
                close = text.find("}", index)
                current.append(chr(int(text[index + 3:close], 16)))
                index = close + 1
                continue
            current.append(SWIFT_ESCAPES.get(following, following))
            index += 2
            continue
        current.append(char)
        index += 1
    return None, start


def check_swift(root, catalogs, problems):
    app = os.path.join(root, "ShellX")
    for directory, _, files in sorted(os.walk(app)):
        for name in sorted(files):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(directory, name)
            display = os.path.relpath(path, root)
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            lines = text.split("\n")
            for number, line in enumerate(lines, start=1):
                stripped = line.lstrip()
                if stripped.startswith(COMMENT_LINE):
                    continue
                if BARE_LITERAL.search(line):
                    problems.append(
                        "%s:%d: bare string literal; use a catalog key or Text(verbatim:): %s"
                        % (display, number, stripped))
            for match in KEY_USE.finditer(text):
                number = text.count("\n", 0, match.start()) + 1
                if lines[number - 1].lstrip().startswith(COMMENT_LINE):
                    continue
                parts, end = swift_literal(text, match.end())
                if parts is None:
                    continue
                table_match = TABLE_ARGUMENT.match(text, end)
                table = table_match.group(1) if table_match else DEFAULT_TABLE
                keys = catalogs.get(table, set())
                if len(parts) == 1:
                    found = parts[0] in keys
                    shown = parts[0]
                else:
                    pattern = re.compile(FORMAT_SPECIFIER.join(re.escape(part) for part in parts))
                    found = any(pattern.fullmatch(key) for key in keys)
                    shown = "%@".join(parts)
                if not found:
                    problems.append('%s:%d: key "%s" is not in %s.xcstrings' % (display, number, shown, table))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        help="the shellx-ios directory (default: the one holding this script)")
    root = os.path.abspath(parser.parse_args().root)

    identity_path = os.path.join(root, "scripts", "strings-identity.txt")
    identity = set()
    if os.path.exists(identity_path):
        with open(identity_path, encoding="utf-8") as handle:
            identity = {line.strip() for line in handle if line.strip() and not line.lstrip().startswith("#")}

    problems = []
    catalogs = {}
    for directory, _, files in sorted(os.walk(os.path.join(root, "ShellX"))):
        for name in sorted(files):
            if name.endswith(".xcstrings"):
                path = os.path.join(directory, name)
                catalogs[name[:-len(".xcstrings")]] = check_catalog(
                    path, os.path.relpath(path, root), identity, problems)
    if DEFAULT_TABLE not in catalogs:
        problems.append("ShellX/%s.xcstrings is missing" % DEFAULT_TABLE)

    check_swift(root, catalogs, problems)

    for problem in problems:
        print(problem)
    if problems:
        print("check-strings: %d problem(s)" % len(problems), file=sys.stderr)
        return 1
    print("check-strings: ok (%d keys)" % sum(len(keys) for keys in catalogs.values()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
