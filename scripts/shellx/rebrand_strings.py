#!/usr/bin/env python3
"""Rewrite the user-visible product name cmux -> ShellX (Python 3.9+).

    python3 scripts/shellx/rebrand_strings.py           # rewrite in place
    python3 scripts/shellx/rebrand_strings.py --check   # exit 1 if anything would change
    python3 scripts/shellx/rebrand_strings.py --list    # print every change (file, key, before -> after)

Wave 2+ reruns it after each upstream merge. A second run is a no-op.

What it rewrites (values only, never catalog keys, never code identifiers):
  * every locale's `stringUnit.value` in the macOS string catalogs:
    Resources/{Localizable,InfoPlist,ConfigPackErrors}.xcstrings, TunnelExtension/InfoPlist.xcstrings
    (its display name shares an omission record with the metadata below) and
    Packages/{macOS,Shared}/*/Sources/**/*.xcstrings (iOS catalogs are out of scope);
  * the English "source" (and per-locale identity "values") the localization
    metadata keeps next to the catalog: scripts/localization-allowed-omissions.json,
    scripts/localization-plurals.json (the checker matches them byte for byte);
  * Resources/Info.plist `NS*UsageDescription` strings;
  * the string literal passed as `defaultValue:` to String(localized:),
    LocalizedStringResource(...), localized(...), localizedCount/Format(...),
    automationLocalized(...) and *.string(...) localization helpers in Sources/,
    CLI/, Packages/macOS/*/Sources and Packages/Shared/*/Sources, with the same
    rules as the catalog so catalog English and the Swift default stay identical;
  * plain CLI help/usage literals in CLI/*.swift (a literal that contains
    "Usage: cmux ", "Run 'cmux " or "'cmux --help'"). Program-name plumbing and
    every other literal are left alone.

Files are edited token by token: only the four letters of each rewritten
`cmux` change, so `git diff` shows the changed values and nothing else.

Rules, applied to each ASCII-bounded word `cmux` (any case; "cmuxを" and
"cmux가" count as words, "cmuxterm"/"CMUX_PORT"/"cmux_port" do not):
  1. paths and file names ShellX owns (global constraints, names on disk):
     `~/.config/cmux` -> `~/.config/shellx`, `.cmux/` -> `.shellx/`,
     `cmux.json` -> `shellx.json`, `.local/state/cmux` -> `.local/state/shellx`,
     `Application Support/cmux` -> `Application Support/ShellX`,
     `bin/cmux` -> `bin/shellx` (the bundled/installed CLI), `cmux.app` -> `ShellX.app`;
  2. never rewritten: URLs and domains (cmux.com, cmux.dev, <x>.cmux.sh,
     github.com/manaflow-ai/cmux, cmux://), reverse-DNS ids (com.cmuxterm...,
     ai.manaflow.cmux), `CMUX_*` names, and identifiers glued with `- _ . : /`
     on either side (cmux-cli, cmux-tui, cmux_source, cmux.sock, cmux:exec,
     foo-cmux, $cmux, @cmux), and an option or setting value (`--agent cmux`,
     `chat.defaultAgent cmux`). Exceptions: English compound adjectives
     (`cmux-aware`, `cmux-managed`, `cmux-owned`, ... see COMPOUND_SUFFIXES) and,
     in translations, `cmux-<Word>` compounds that are not an identifier copied
     from the English value (German "cmux-Browser", Danish "cmux-udvidelse")
     become `ShellX-...`;
  3. the command name becomes lowercase `shellx`:
     `` `cmux `` / `` `cmux` `` (code spans), a quoted bare `'cmux'` / "cmux",
     a leading `cmux: ` program prefix, `cmux` before a flag/placeholder
     (` -`, ` <`, ` [`), and `cmux <subcommand>` when <subcommand> is in
     SUBCOMMANDS and the occurrence looks like a command (see is_command);
  4. everything else -> `ShellX`.
Values listed in PRESERVE_VALUES and keys in PRESERVE_KEYS (upstream
attribution and license credit) are never touched.

Ruling (shell commands): a bare `cmux <word>` is the `shellx` command, not
prose, only when <word> is in SUBCOMMANDS and the context says "command":
  strong (always enough): the subcommand is hyphenated (reload-config); the
  occurrence is quoted ('cmux restore ...'); a flag/placeholder/option list
  follows within two more words, or a format argument/pipe/closing quote follows
  directly; Usage:/run/retry/try/`$ `/`| ` precedes it; "<label>: cmux x %@";
  or, in a translation, the English value of the same key used that subcommand
  as a command;
  weak: the key is CLI help (cli.*, *.cli.*, *.usage), the occurrence starts a
  line, or See/See also:/Use/Example: precedes it. Weak hints are enough for
  verbs (`cmux notify`), but for subcommands that are also nouns
  (NOUN_SUBCOMMANDS: browser, cloud, workspace, session ...) only inside CLI help
  and only at a line start or after See/Use.
  Never: an article/determiner before it ("the cmux browser", "a cmux
  workspace") or a comma right after the subcommand ("cmux workspace, machine").
Upstream subcommands added later fall back to "ShellX <word>" until they are
added to SUBCOMMANDS; `--list` shows every decision for review after a merge.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import namedtuple
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Upstream credit and license text: shown exactly as written.
PRESERVE_VALUES = frozenset({
    "cmux (Manaflow, Inc.)",
    "Copyright (c) 2024-present Manaflow, Inc.",
})
# Catalog keys whose values stay as upstream wrote them (attribution). None today:
# the About attribution list is code (AboutLicenseContent.attributions), not catalog text.
PRESERVE_KEYS = frozenset()

# Top-level CLI subcommands (CLI/cmux.swift dispatch plus commands handled before it).
SUBCOMMANDS = frozenset("""
agent agent-hibernation ai-accounts auth automation billing break-pane browser browser-back browser-forward
browser-reload browser-status canvas capabilities capture-pane claude-hook claude-teams clear-history clear-log
clear-notifications clear-progress clear-status close-surface close-window close-workspace cloud codex codex-hook
codex-teams coderouter comments config current current-window current-workspace debug-terminals detach-tab diff
disable-browser dismiss-notification display-message docs drag-surface-to-split enable-browser env events feed
feed-hook feedback find-window focus-pane focus-panel focus-webview focus-window fork get-url glaeda guide help hooks
identify import ios iroh-diag is-webview-focused join-pane jump-to-last-prompt jump-to-unread last-pane layout
list-buffers list-log list-notifications list-pane-surfaces list-panels list-panes list-status list-windows
list-workspaces local-tmux local-zellij log login logout mark-notification-read markdown memory mobile mosh
mosh-tmux move-surface move-tab-to-new-workspace move-workspace-to-window navigate new-pane new-split new-surface
new-window new-workspace notify omc omo omx open open-browser open-notification paste paste-buffer ping pipe-pane
popup pr project read-screen read-selection record recover refresh-surfaces reload-config remote
remote-daemon-status remotes rename-tab rename-window rename-workspace reorder-surface reorder-workspace
reorder-workspaces resize-pane resize-window respawn-pane restore restore-session review right-sidebar rpc
screenshot select-workspace send send-key send-key-panel send-panel session session-debug sessions set-app-focus set-buffer
set-hook set-progress set-status settings shortcuts shot sidebar sidebar-state simulate-app-active
simulate-sidebar-drag simulator socket-status split-off ssh ssh-pty-attach ssh-session-attach ssh-session-cleanup
ssh-session-end ssh-session-list ssh-tmux sudo surface surface-health surface-resume swap-pane tab-action themes
tmux todo top tree trigger-flash vault vm vm-pty-attach vm-pty-connect vm-ssh-attach vm-tui-connect vpn wait-for
welcome window workspace workspace-action workspace-group
""".split())

# English compounds that are prose, not identifiers: "cmux-aware" -> "ShellX-aware".
COMPOUND_SUFFIXES = frozenset("""
aware managed owned specific native side wide style provided hosted launched started created controlled drawn
bundled branded only compatible enabled based powered
""".split())

WORD = re.compile(r"(?<![A-Za-z0-9_])cmux(?![A-Za-z0-9_])", re.I)
OPEN_QUOTES = "'\"“‘「『«„‚"
CLOSE_QUOTES = "'\"”’」』»“‘"
# A character glued before `cmux` that makes it part of an identifier, URL or path.
GLUE_BEFORE = set("./-@$\\=&?#:~")
OPTION_VALUE = re.compile(r"(?:(?<!\S)--[a-z][\w-]*|\b[a-z]\w*\.[A-Za-z]\w*) $")
SUB = re.compile(r" ([a-z][a-z0-9]*(?:-[a-z0-9]+)*)")
# After the subcommand: a flag, placeholder or option list (also after up to two more lowercase
# words: "cmux billing checkout --plan"), or directly a format argument, pipe or closing quote.
ARGS_AFTER = re.compile(r"(?: [a-z][a-z0-9-]*){0,2}(?: -\S| <| \[)| %| \||[)'\"’”`]")
STRONG_PREFIX = re.compile(r"(?:\b(?:[Uu]sage:|[Rr]un|[Rr]etry|[Tt]ry)\s+|[$|] )$")
WEAK_PREFIX = re.compile(r"\b(?:[Ss]ee(?: also:)?|[Uu]se|[Ee]xample:)\s+$")
ARTICLE_PREFIX = re.compile(r"\b(?:the|a|an|this|that|your|its|our|their|another|any|every|each)\s+$", re.I)
CLI_KEY = re.compile(r"^(?:cli|sudo\.cli)\.|\.cli\.|\.usage(?:\.|$)")
# Subcommands that are also everyday nouns ("cmux cloud", "the cmux browser"): weak hints
# (line start, See/Use before it) do not make them commands; strong ones still do.
NOUN_SUBCOMMANDS = frozenset("""
agent automation browser canvas cloud config docs feedback hooks markdown memory mobile project remote remotes
review session sessions settings sidebar simulator surface themes tree window workspace
""".split())
INTERPOLATION = "\ufffc"  # stands in for a Swift `\(...)` interpolation while rules run


def is_cli_key(key: str | None) -> bool:
    return bool(key) and bool(CLI_KEY.search(key))


def classify(text: str, start: int, key: str | None, en_context: str | None,
             en_command_subs: frozenset[str] | None) -> tuple[str | None, str | None]:
    """Return (replacement for the four letters, subcommand when it is a command) or (None, None)."""
    end = start + 4
    before, after = text[:start], text[end:]
    prev = before[-1:]
    # 1. ShellX's own paths and files.
    path_end = not re.match(r"[-\w]", after)
    if path_end and (before.endswith(".config/") or before.endswith(".local/state/")):
        return "shellx", None
    if path_end and before.endswith("Application Support/"):
        return "ShellX", None
    if before.endswith("bin/") and not re.match(r"[-.\w]", after):
        return "shellx", None
    if prev == "." and after.startswith("/") and not before[-2:-1].isalnum():
        return "shellx", None
    if after.startswith(".json") and not re.match(r"[A-Za-z0-9_]", after[5:6]) and prev not in ("-", "_", "."):
        return "shellx", None
    if after.startswith(".app") and not re.match(r"[A-Za-z0-9_]", after[4:6]) and prev not in GLUE_BEFORE:
        return "ShellX", None
    # 2. Identifiers, URLs, domains, paths.
    if prev in GLUE_BEFORE or after.startswith("://") or re.match(r"[.:/][A-Za-z0-9_]", after):
        return None, None
    if OPTION_VALUE.search(before):
        return None, None  # `--agent cmux`, `chat.defaultAgent cmux`: a value naming an identifier
    if after.startswith("-"):
        word = re.match(r"-([a-z0-9]+)", after)
        if word:
            if word.group(1) in COMPOUND_SUFFIXES:
                return "ShellX", None
            if en_context is None:
                return None, None  # English or a Swift default: cmux-tui, cmux-cli, cmux-chat ...
            token = re.match(r"-[a-z0-9][a-z0-9.\-]*", after).group(0).rstrip(".-")
            if ("cmux" + token).lower() in en_context.lower():
                return None, None  # identifier copied from the English value
        return "ShellX", None  # a translation's compound: cmux-Browser, cmux-udvidelse
    # 3. The command name.
    if prev == "`":
        return "shellx", None
    if prev and prev in OPEN_QUOTES and after[:1] and after[:1] in CLOSE_QUOTES:
        return "shellx", None
    if start == 0 and after.startswith(": "):
        return "shellx", None
    if re.match(r" (?:-|<|\[)", after) or re.search(r"\b[Uu]sage: $", before):
        return "shellx", None
    if is_cli_key(key) and re.match(r" %(?:\d+\$)?@", after):
        return "shellx", None  # "cmux %1$@ failed": the subcommand is the argument
    sub = SUB.match(after)
    if sub and sub.group(1) in SUBCOMMANDS and is_command(text, start, sub, prev, key, en_command_subs):
        return "shellx", sub.group(1)
    # 4. The product name.
    return "ShellX", None


def is_command(text: str, start: int, sub: re.Match, prev: str, key: str | None,
               en_command_subs: frozenset[str] | None) -> bool:
    before = text[:start]
    name = sub.group(1)
    if ARTICLE_PREFIX.search(before):
        return False
    quoted = bool(prev) and prev in OPEN_QUOTES
    rest = text[start + 4 + sub.end():]
    if rest.startswith(",") and not ("-" in name or quoted):
        return False  # "cmux workspace, machine, ..." is a list of nouns
    if any((
        "-" in name,
        quoted,
        bool(ARGS_AFTER.match(rest)),
        before.endswith(": ") and bool(re.match(r"(?: [a-z][a-z0-9-]*){0,2} %", rest)),  # "Open it with: cmux sidebar open %@"
        bool(STRONG_PREFIX.search(before)),
        en_command_subs is not None and name in en_command_subs,
    )):
        return True
    line_start = not before[before.rfind("\n") + 1:].strip()
    if name in NOUN_SUBCOMMANDS:
        # CLI help only: an example line ("  cmux browser open <url>") or "See also: cmux workspace status".
        return is_cli_key(key) and (line_start or bool(WEAK_PREFIX.search(before)))
    return is_cli_key(key) or line_start or bool(WEAK_PREFIX.search(before))


def edits(text: str, key: str | None = None, en_context: str | None = None,
          en_command_subs: frozenset[str] | None = None) -> tuple[list[tuple[int, str]], set[str]]:
    """Positions of `cmux` to replace (each replacement covers exactly 4 chars) and the command subcommands seen."""
    if text in PRESERVE_VALUES or (key is not None and key in PRESERVE_KEYS):
        return [], set()
    result: list[tuple[int, str]] = []
    commands: set[str] = set()
    for match in WORD.finditer(text):
        replacement, command = classify(text, match.start(), key, en_context, en_command_subs)
        if replacement is not None:
            result.append((match.start(), replacement))
        if command:
            commands.add(command)
    return result, commands


def apply(text: str, changes: list[tuple[int, str]]) -> str:
    for position, replacement in sorted(changes, reverse=True):
        text = text[:position] + replacement + text[position + 4:]
    return text


def rebrand(text: str, key: str | None = None, en_context: str | None = None,
            en_command_subs: frozenset[str] | None = None) -> str:
    """The rebranded text. `en_context` is the key's English value when `text` is a translation."""
    if en_context is not None and en_command_subs is None:
        en_command_subs = frozenset(edits(en_context, key)[1])
    return apply(text, edits(text, key, en_context, en_command_subs)[0])


# ---------------------------------------------------------------- JSON files

STRING_TOKEN = re.compile(r'"(?:[^"\\]|\\.)*"')
AFTER_KEY = re.compile(r"\s*:")


def value_tokens(raw: str):
    """String tokens in document order that are values (not object keys)."""
    for match in STRING_TOKEN.finditer(raw):
        if not AFTER_KEY.match(raw, match.end()):
            yield match


def walk_values(node, path=()):
    """(path, string) for every string value in document order (matches value_tokens)."""
    if isinstance(node, dict):
        for name, child in node.items():
            yield from walk_values(child, path + (name,))
    elif isinstance(node, list):
        for index, child in enumerate(node):
            yield from walk_values(child, path + (index,))
    elif isinstance(node, str):
        yield path, node


# One rewritten value: file, location (JSON path or Swift line:key), old and new text.
Change = namedtuple("Change", "path where before after")


def rewrite_json(relative: str, select, changes: list[Change]) -> str | None:
    """Rewrite selected string values of one JSON file in place of their tokens.

    `select(path, value, document)` returns (key, en_context, en_command_subs) for
    a value to rebrand, or None to leave it.
    """
    path = ROOT / relative
    raw = path.read_text(encoding="utf-8")
    document = json.loads(raw)
    pieces: list[str] = []
    last = 0
    tokens = list(value_tokens(raw))
    values = list(walk_values(document))
    if len(tokens) != len(values):
        raise SystemExit(f"{relative}: could not align {len(tokens)} string tokens with {len(values)} values")
    for token, (value_path, value) in zip(tokens, values):
        if json.loads(token.group(0)) != value:
            raise SystemExit(f"{relative}: token at offset {token.start()} does not match {value_path}")
        if "mux" not in value and "MUX" not in value:
            continue
        chosen = select(value_path, value, document)
        if chosen is None:
            continue
        key, en_context, en_command_subs = chosen
        new_value = apply(value, edits(value, key, en_context, en_command_subs)[0])
        if new_value == value:
            continue
        encoded = json.dumps(new_value, ensure_ascii=False)
        if json.dumps(value, ensure_ascii=False) != token.group(0):
            # Escaping style differs from json.dumps: swap the letters inside the raw token.
            encoded = raw_token_rewrite(token.group(0), value, key, en_context, en_command_subs)
        pieces.append(raw[last:token.start()])
        pieces.append(encoded)
        last = token.end()
        changes.append(Change(relative, "/".join(map(str, value_path)), value, new_value))
    if not pieces:
        return None
    pieces.append(raw[last:])
    return "".join(pieces)


def raw_token_rewrite(token: str, value: str, key, en_context, en_command_subs) -> str:
    targets = edits(value, key, en_context, en_command_subs)[0]
    raw_hits = [m.start() for m in WORD.finditer(token)]
    value_hits = [m.start() for m in WORD.finditer(value)]
    if len(raw_hits) != len(value_hits):
        raise SystemExit(f"cannot map escaped JSON token {token[:60]!r}")
    by_value = dict(zip(value_hits, raw_hits))
    return apply(token, [(by_value[position], replacement) for position, replacement in targets])


def english_text(entry: dict) -> str:
    english = entry.get("localizations", {}).get("en")
    if not english:
        return ""
    return "\n".join(value for path, value in walk_values(english) if path[-1:] == ("value",))


def catalog_select(english_cache: dict):
    def select(value_path, value, document):
        if len(value_path) < 5 or value_path[0] != "strings" or value_path[2] != "localizations" \
                or value_path[-1] != "value" or value_path[-2] != "stringUnit":
            return None
        key, locale = value_path[1], value_path[3]
        if locale == "en":
            return key, None, None
        if key not in english_cache:
            english = english_text(document["strings"][key])
            english_cache[key] = (english, frozenset(edits(english, key)[1]))
        english, subs = english_cache[key]
        return key, english, subs
    return select


def omissions_select(value_path, value, document):
    key = value_path[0]
    if value_path[1:] == ("source",):
        return key, None, None
    if len(value_path) == 5 and value_path[1] == "identityLocales" and value_path[3] == "values":
        english = document[key].get("source", "")
        return key, english, frozenset(edits(english, key)[1])
    return None


def plurals_select(value_path, value, document):
    return (value_path[0], None, None) if value_path[1:] == ("source",) else None


# --------------------------------------------------------------- Info.plist

USAGE = re.compile(r"(<key>NS\w*UsageDescription</key>\s*<string>)([^<]*)(</string>)")


def rewrite_info_plist(relative: str, changes: list[Change]) -> str | None:
    raw = (ROOT / relative).read_text(encoding="utf-8")

    def replace(match):
        value = match.group(2)
        new_value = rebrand(value, key=None)
        if new_value != value:
            changes.append(Change(relative, match.group(1).split("</key>")[0][5:], value, new_value))
        return match.group(1) + new_value + match.group(3)

    text = USAGE.sub(replace, raw)
    return None if text == raw else text


# ------------------------------------------------------------------- Swift

SWIFT_ROOTS = ("Sources", "CLI", "Packages/macOS", "Packages/Shared")
SWIFT_SKIP = frozenset((".build", "Tests", "DerivedData", "node_modules", "vendor", "Examples", "Prototypes"))
LOCALIZED_CALL = re.compile(
    r"(?:\bString\s*\(\s*localized\s*:|\bLocalizedStringResource\s*\("
    r"|\b(?:localized|localizedCount|localizedFormat|automationLocalized)\s*\("
    r"|\b[A-Za-z_]*[Ll]ocaliz[A-Za-z0-9_]*\.string\s*\()\s*"
    r'(?P<key>"(?:\\.|[^"\\\n])*")'
)
DEFAULT_LABEL = re.compile(r"defaultValue\s*:\s*")
HELP_MARKER = re.compile(r"Usage: cmux |Run 'cmux |'cmux --help'")


def swift_files() -> list[Path]:
    files = []
    for root in SWIFT_ROOTS:
        for path in sorted((ROOT / root).rglob("*.swift")):
            parts = path.relative_to(ROOT).parts
            if root.startswith("Packages/") and (len(parts) < 4 or parts[3] != "Sources"):
                continue
            if SWIFT_SKIP.isdisjoint(parts[:-1]):
                files.append(path)
    return files


def skip_string(text: str, index: int) -> int:
    """Index just past the Swift string literal (or raw literal) starting at `index`."""
    hashes = 0
    while text[index + hashes] == "#":
        hashes += 1
    quote = index + hashes
    multi = text.startswith('"""', quote)
    opener = '"""' if multi else '"'
    closer = opener + "#" * hashes
    position = quote + len(opener)
    while position < len(text):
        if text.startswith(closer, position):
            return position + len(closer)
        char = text[position]
        if char == "\\" and text.startswith("#" * hashes, position + 1):
            escape = position + 1 + hashes
            if text[escape:escape + 1] == "(":
                position = skip_interpolation(text, escape + 1)
                continue
            position = escape + 1
            continue
        if char == "\n" and not multi:
            return position
        position += 1
    return position


def skip_interpolation(text: str, index: int) -> int:
    """Index just past the `)` closing an interpolation whose `(` precedes `index`."""
    depth = 1
    position = index
    while position < len(text) and depth:
        char = text[position]
        if char == '"' or (char == "#" and re.match(r'#+"', text[position:position + 8])):
            position = skip_string(text, position)
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        position += 1
    return position


def string_literals(text: str):
    """(start, end) of every top-level Swift string literal, skipping comments."""
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        if text.startswith("//", index):
            newline = text.find("\n", index)
            index = length if newline < 0 else newline
            continue
        if text.startswith("/*", index):
            depth, index = 1, index + 2
            while index < length and depth:
                if text.startswith("/*", index):
                    depth, index = depth + 1, index + 2
                elif text.startswith("*/", index):
                    depth, index = depth - 1, index + 2
                else:
                    index += 1
            continue
        if char == '"' or (char == "#" and re.match(r'#+"', text[index:index + 8])):
            end = skip_string(text, index)
            yield index, end
            index = end
            continue
        index += 1


def decode_literal(literal: str) -> tuple[str, list[int | None]] | None:
    """Decoded text of a non-raw Swift literal and, per decoded char, its offset in `literal`.

    Escapes and interpolations map to None; rules never rewrite through them.
    Returns None for raw (`#"..."#`) literals.
    """
    if literal.startswith("#"):
        return None
    chars: list[str] = []
    offsets: list[int | None] = []
    if literal.startswith('"""'):
        body_start = literal.find("\n") + 1
        body_end = literal.rfind("\n")
        if body_start <= 0 or body_end < body_start:
            return None
        indent = literal[body_end + 1:len(literal) - 3]
        lines = []
        position = body_start
        for line in literal[body_start:body_end].split("\n"):
            strip = len(indent) if line.startswith(indent) else len(line) - len(line.lstrip(" \t"))
            lines.append((position + strip, line[strip:]))
            position += len(line) + 1
        segments = []
        for number, (offset, line) in enumerate(lines):
            segments.append((offset, line))
            if number < len(lines) - 1:
                segments.append((None, "\n"))
    else:
        segments = [(1, literal[1:-1])]
    pending_continuation = False
    for offset, segment in segments:
        if offset is None:
            if pending_continuation:
                pending_continuation = False
                continue
            chars.append("\n")
            offsets.append(None)
            continue
        index = 0
        while index < len(segment):
            char = segment[index]
            if char != "\\":
                chars.append(char)
                offsets.append(offset + index)
                index += 1
                continue
            following = segment[index + 1:index + 2]
            if following == "(":
                end = skip_interpolation(segment, index + 2)
                chars.append(INTERPOLATION)
                offsets.append(None)
                index = end
                continue
            if following == "":
                pending_continuation = True  # backslash at end of a multi-line line
                index += 1
                continue
            if following == "u" and segment[index + 2:index + 3] == "{":
                close = segment.find("}", index + 3)
                chars.append(chr(int(segment[index + 3:close], 16)))
                offsets.append(None)
                index = close + 1
                continue
            mapping = {"n": "\n", "r": "\r", "t": "\t", '"': '"', "'": "'", "\\": "\\", "0": "\0"}
            chars.append(mapping.get(following, following))
            offsets.append(None)
            index += 2
    return "".join(chars), offsets


def rewrite_literal(literal: str, key: str | None) -> tuple[list[tuple[int, str]], str, str] | None:
    """Edits (offsets in `literal`) plus the decoded text before and after, or None when nothing changes."""
    decoded = decode_literal(literal)
    if decoded is None:
        return None
    text, offsets = decoded
    changes = edits(text, key)[0]
    if not changes:
        return None
    raw_changes = []
    for position, replacement in changes:
        span = offsets[position:position + 4]
        if None in span or span != list(range(span[0], span[0] + 4)):
            raise SystemExit(f"cannot map Swift literal {literal[:60]!r}")
        raw_changes.append((span[0], replacement))
    return raw_changes, text, apply(text, changes)


def rewrite_swift(path: Path, changes: list[Change]) -> str | None:
    raw = path.read_text(encoding="utf-8")
    if "mux" not in raw and "MUX" not in raw:
        return None
    relative = path.relative_to(ROOT).as_posix()
    targets: dict[int, tuple[int, str | None]] = {}
    for call in LOCALIZED_CALL.finditer(raw):
        key = json.loads(call.group("key")) if "\\" not in call.group("key") else call.group("key")[1:-1]
        suffix_end = skip_call(raw, call.end())
        label = DEFAULT_LABEL.search(raw, call.end(), suffix_end)
        if not label:
            continue
        start = label.end()
        if raw[start:start + 1] not in ('"', "#"):
            continue
        targets.setdefault(start, (skip_string(raw, start), key))
    defaults = set(targets)
    if relative.startswith("CLI/"):
        for start, end in string_literals(raw):
            if start in defaults or any(s <= start < e for s, (e, _k) in targets.items()):
                continue
            decoded = decode_literal(raw[start:end])
            if decoded and HELP_MARKER.search(decoded[0]):
                targets[start] = (end, "cli.help")
    # Edits are collected file-wide: a localized call nested in a help literal's
    # interpolation is its own target, and the outer literal never edits inside it.
    file_edits: dict[int, str] = {}
    for start in sorted(targets):
        end, key = targets[start]
        result = rewrite_literal(raw[start:end], key)
        if result is None:
            continue
        literal_edits, before, after = result
        for offset, replacement in literal_edits:
            file_edits[start + offset] = replacement
        line = raw.count("\n", 0, start) + 1
        changes.append(Change(relative, f"{line}:{key}", before, after))
    return apply(raw, list(file_edits.items())) if file_edits else None


def skip_call(text: str, index: int) -> int:
    """Index of the `)` closing the call whose arguments start at `index` (strings skipped)."""
    depth = 1
    position = index
    while position < len(text):
        char = text[position]
        if char == '"' or (char == "#" and re.match(r'#+"', text[position:position + 8])):
            position = skip_string(text, position)
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return position
        position += 1
    return position


# -------------------------------------------------------------------- main

def catalogs() -> list[str]:
    paths = ["Resources/Localizable.xcstrings", "Resources/InfoPlist.xcstrings", "Resources/ConfigPackErrors.xcstrings",
             "TunnelExtension/InfoPlist.xcstrings"]
    for root in ("Packages/macOS", "Packages/Shared"):
        paths += sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / root).glob("*/Sources/**/*.xcstrings"))
    return paths


def plan() -> tuple[dict[Path, str], list[Change]]:
    changes: list[Change] = []
    outputs: dict[Path, str] = {}
    for relative in catalogs():
        text = rewrite_json(relative, catalog_select({}), changes)
        if text is not None:
            outputs[ROOT / relative] = text
    for relative, select in (("scripts/localization-allowed-omissions.json", omissions_select),
                             ("scripts/localization-plurals.json", plurals_select)):
        text = rewrite_json(relative, select, changes)
        if text is not None:
            outputs[ROOT / relative] = text
    text = rewrite_info_plist("Resources/Info.plist", changes)
    if text is not None:
        outputs[ROOT / "Resources/Info.plist"] = text
    for path in swift_files():
        text = rewrite_swift(path, changes)
        if text is not None:
            outputs[path] = text
    return outputs, changes


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true", help="exit 1 if a change would be made; write nothing")
    parser.add_argument("--list", action="store_true", help="print every change; write nothing")
    args = parser.parse_args(argv)
    outputs, changes = plan()
    if args.list:
        for change in changes:
            print(f"{change.path}\t{change.where}\t{change.before!r}\t->\t{change.after!r}")
    by_file: dict[str, int] = {}
    for change in changes:
        by_file[change.path] = by_file.get(change.path, 0) + 1
    if args.check or args.list:
        for name, count in sorted(by_file.items()):
            print(f"would change {count} value(s) in {name}", file=sys.stderr)
        return 1 if changes else 0
    for path, text in outputs.items():
        path.write_text(text, encoding="utf-8")
    for name, count in sorted(by_file.items()):
        print(f"changed {count} value(s) in {name}")
    print(f"{len(changes)} value(s) in {len(outputs)} file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
