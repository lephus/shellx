#!/usr/bin/env bash
# Licence boundary check for shellx-ios/, the closed-source ShellX iOS app. The app may use only
# Apple frameworks, its own code and the MIT package shellx-link/; never GPL code from ios/,
# Packages/, Sources/, cmux-tui/ or shellx-core/, and never a package downloaded from the network.
#
#   scripts/shellx/check-ios-license.sh [--root <repository root>]
#
# Exits 1 and prints each offending path when:
#   1. a package manifest under shellx-ios/ (Package.swift, Package@swift-*.swift) has a `url:` or
#      `id:` label (a network package or binary), `unsafeFlags`, or a `path:` that is not a plain
#      string literal or that resolves outside shellx-ios/ and shellx-link/;
#   2. a project.pbxproj under shellx-ios/ has an XCRemoteSwiftPackageReference, or a `path` or
#      `relativePath` that uses a build setting (`$`), is absolute, or resolves outside those two
#      folders (relative values are resolved against the folder holding the .xcodeproj, which errs
#      on the strict side);
#   3. a .swift file under shellx-ios/ imports a module outside ALLOWED_MODULES, or has an import
#      whose module cannot be read;
#   4. a text file under shellx-ios/ contains the word "Manaflow" (any case);
#   5. anything under shellx-ios/ is a symlink (it could pull in files from anywhere);
#   6. scripts/shellx/check-link-license.sh (next to this script) fails.
# Checks 1 and 3 read Swift with a small lexer (python3), so comments and string literals never
# count, while `;`, line breaks, attributes and `import struct X.Y` do not hide an import.
#
# ALLOWED_MODULES is an allowlist on purpose: a new GPL module added under Packages/ is blocked
# without anyone having to remember to update this script.
set -u
set -f

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || { echo "check-ios-license: --root needs a directory" >&2; exit 2; }
      ROOT="$(cd "$2" && pwd -P)" || exit 2
      shift
      ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "check-ios-license: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

APP="$ROOT/shellx-ios"
LINK="$ROOT/shellx-link"
if [ ! -d "$APP" ]; then
  echo "check-ios-license: missing $APP"
  exit 1
fi

# ShellXDemo: the app's own demo target (shellx-ios/Packages/ShellXAppCore, "Try without an account").
ALLOWED_MODULES="
  Swift _Concurrency Darwin Dispatch Foundation os OSLog Observation Combine Synchronization RegexBuilder
  SwiftUI UIKit CoreFoundation CoreGraphics CoreImage CoreText CoreMedia CoreVideo CoreHaptics
  CoreTransferable QuartzCore ImageIO UniformTypeIdentifiers Accessibility TipKit
  CryptoKit Security LocalAuthentication AuthenticationServices Network
  Speech AVFoundation AVFAudio AVKit AudioToolbox Vision VisionKit PhotosUI
  UserNotifications BackgroundTasks AppIntents WidgetKit ActivityKit StoreKit SafariServices
  LinkPresentation NaturalLanguage MetricKit
  XCTest Testing PackageDescription
  ShellXLinkCore ShellXLinkRelay ShellXLinkSession ShellXLinkAccount
  ShellXAppCore ShellXDemo ShellXAppTestSupport ShellX
"

fail=0
violation() {
  echo "violation: $1: $2"
  fail=1
}

# The path relative to the root, for messages.
rel() { echo "${1#"$ROOT"/}"; }

# Lexically normalises an absolute path (resolves "." and ".." without touching the disk).
normalize() {
  local out="" part IFS='/'
  for part in $1; do
    case "$part" in
      '' | .) ;;
      ..) out="${out%/*}" ;;
      *) out="$out/$part" ;;
    esac
  done
  echo "${out:-/}"
}

inside_allowed() {
  case "$1" in
    "$APP" | "$APP"/* | "$LINK" | "$LINK"/*) return 0 ;;
  esac
  return 1
}

# check_path <file> <base dir> <value> <what>
check_path() {
  case "$3" in
    /* | '~'*)
      violation "$(rel "$1")" "$4 \"$3\" is absolute"
      return
      ;;
  esac
  if ! inside_allowed "$(normalize "$2/$3")"; then
    violation "$(rel "$1")" "$4 \"$3\" points outside shellx-ios/ and shellx-link/"
  fi
}

# Every file under shellx-ios/, except build output, matching the find tests given ("-name x" ...).
app_files() {
  find "$APP" \( -name .build -o -name .derived -o -name .swiftpm -o -name xcuserdata -o -name DerivedData \) -prune \
    -o "$@" -print
}

# 1 and 3. Swift sources and package manifests, read with a lexer that blanks comments and the
# contents of string literals (keeping line breaks), so what is left is code.
# Arguments: app dir, link dir, root dir, allowed modules. Standard input: NUL-separated .swift paths.
# (read -d '' rather than $(cat <<...): bash 3.2 misparses quotes and parentheses in a heredoc
# inside a command substitution.)
IFS= read -r -d '' SWIFT_CHECK <<'PY' || true
import os
import re
import sys

app, link, root = sys.argv[1], sys.argv[2], sys.argv[3]
allowed = set(sys.argv[4].split())
problems = []


class Literal:
    def __init__(self, start, end, body_start, body_end, plain):
        self.start, self.end, self.body_start, self.body_end, self.plain = start, end, body_start, body_end, plain


def lex(text):
    """Returns (code, literals by start offset). `code` is `text` with comments and string literal
    contents replaced by spaces; a literal is plain when it is single-line, raw-free and escape-free."""
    out, literals, n = list(text), {}, len(text)

    def blank(start, end):
        for k in range(start, end):
            if out[k] != "\n":
                out[k] = " "

    def interpolation(k):
        depth = 1
        while k < n:
            end = string(k) if text[k] in '#"' else None
            if end is not None:
                k = end
                continue
            if text[k] == "(":
                depth += 1
            elif text[k] == ")":
                depth -= 1
                if depth == 0:
                    return k + 1
            k += 1
        return n

    def string(i):
        j = i
        while j < n and text[j] == "#":
            j += 1
        hashes = j - i
        if j >= n or text[j] != '"':
            return None
        multiline = text.startswith('"""', j)
        body = j + (3 if multiline else 1)
        closer = ('"""' if multiline else '"') + "#" * hashes
        escape = "\\" + "#" * hashes
        k, escaped = body, False
        while k < n:
            if text.startswith(escape, k):
                escaped = True
                k += len(escape)
                k = interpolation(k + 1) if k < n and text[k] == "(" else k + 1
                continue
            if text.startswith(closer, k):
                end = k + len(closer)
                literals[i] = Literal(i, end, body, k, not hashes and not multiline and not escaped)
                return end
            if text[k] == "\n" and not multiline:
                break
            k += 1
        literals[i] = Literal(i, k, body, k, False)
        return k

    i = 0
    while i < n:
        if text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end < 0 else end
        elif text.startswith("/*", i):
            depth, end = 1, i + 2
            while end < n and depth:
                if text.startswith("/*", end):
                    depth, end = depth + 1, end + 2
                elif text.startswith("*/", end):
                    depth, end = depth - 1, end + 2
                else:
                    end += 1
        elif text[i] in '#"' and string(i) is not None:
            literal = literals[i]
            blank(literal.body_start, literal.body_end)
            i = literal.end
            continue
        else:
            i += 1
            continue
        blank(i, end)
        i = end
    return "".join(out), literals


def where(path, code, offset):
    return "%s:%d" % (os.path.relpath(path, root), code.count("\n", 0, offset) + 1)


def skip_space(code, k):
    while k < len(code) and code[k].isspace():
        k += 1
    return k


IMPORT = re.compile(r"(?<![A-Za-z0-9_`.])import(?![A-Za-z0-9_`])")
IMPORTED = re.compile(r"\s*(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(`?)([A-Za-z_][A-Za-z0-9_]*)\1")
LABEL = re.compile(r"(?<![A-Za-z0-9_`.])(url|id|path)\s*:")
UNSAFE = re.compile(r"(?<![A-Za-z0-9_])unsafeFlags(?![A-Za-z0-9_])")
MANIFEST = re.compile(r"Package(@swift-[0-9.]+)?\.swift")


def check_imports(path, code):
    for match in IMPORT.finditer(code):
        after = skip_space(code, match.end())
        before = code[:match.start()].rstrip()[-1:]
        if (after < len(code) and code[after] == ":") or before in ("(", ","):
            continue  # `import` used as an argument label: f(import: x), func f(import value: Int)
        module = IMPORTED.match(code, match.end())
        if module is None:
            problems.append((where(path, code, match.start()), "an import whose module cannot be read"))
        elif module.group(2) not in allowed:
            problems.append((where(path, code, match.start()),
                             "imports %s, which is not on the allowlist" % module.group(2)))


def inside_allowed(target):
    return any(target == base or target.startswith(base + os.sep) for base in (app, link))


def check_manifest(path, text, code, literals):
    if UNSAFE.search(code):
        problems.append((where(path, code, UNSAFE.search(code).start()), "unsafeFlags"))
    for match in LABEL.finditer(code):
        spot = where(path, code, match.start())
        label = match.group(1)
        if label != "path":
            problems.append((spot, "network package (`%s:` label)" % label))
            continue
        literal = literals.get(skip_space(code, match.end()))
        follow = skip_space(code, literal.end) if literal else len(code)
        if literal is None or not literal.plain or follow >= len(code) or code[follow] not in ",)":
            problems.append((spot, "path: is not a plain string literal"))
            continue
        value = text[literal.body_start:literal.body_end]
        if value.startswith(("/", "~")):
            problems.append((spot, 'path "%s" is absolute' % value))
        elif not inside_allowed(os.path.normpath(os.path.join(os.path.dirname(path), value))):
            problems.append((spot, 'path "%s" points outside shellx-ios/ and shellx-link/' % value))


for path in sys.stdin.read().split("\0"):
    if not path:
        continue
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    code, literals = lex(text)
    check_imports(path, code)
    if MANIFEST.fullmatch(os.path.basename(path)):
        check_manifest(path, text, code, literals)

for spot, message in problems:
    print("violation: %s: %s" % (spot, message))
sys.exit(1 if problems else 0)
PY
if ! swift_output="$(app_files -type f -name '*.swift' | tr '\n' '\0' |
  python3 -I -c "$SWIFT_CHECK" "$APP" "$LINK" "$ROOT" "$ALLOWED_MODULES" 2>&1)"; then
  echo "$swift_output"
  fail=1
fi

# 2. Xcode projects.
while IFS= read -r pbxproj; do
  [ -n "$pbxproj" ] || continue
  project_dir="$(dirname "$(dirname "$pbxproj")")"
  if grep -q 'XCRemoteSwiftPackageReference' "$pbxproj"; then
    violation "$(rel "$pbxproj")" "XCRemoteSwiftPackageReference (a package downloaded from the network)"
  fi
  while IFS= read -r value; do
    [ -n "$value" ] || continue
    case "$value" in
      *'$'*) violation "$(rel "$pbxproj")" "path \"$value\" uses a build setting; write a plain relative path" ;;
      *) check_path "$pbxproj" "$project_dir" "$value" "path" ;;
    esac
  done <<<"$(grep -oE '(^|[^A-Za-z_])(path|relativePath) = ("[^"]*"|[^;]*);' "$pbxproj" |
    sed -E 's/^[^A-Za-z_]?(path|relativePath) = //; s/;$//; s/^"(.*)"$/\1/')"
done <<<"$(app_files -type f -name project.pbxproj)"

# 5. Symlinks.
while IFS= read -r link_path; do
  [ -n "$link_path" ] || continue
  violation "$(rel "$link_path")" "is a symlink; copy the file in instead"
done <<<"$(app_files -type l)"

# 4. The word Manaflow (any case; "manaflow-ai" and "cmux.manaflow.com" count, an identifier such
#    as testManaflowStringFails does not) in the app's text files.
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  violation "$(rel "$hit")" "mentions Manaflow"
done <<<"$(grep -rIilw --exclude-dir=.build --exclude-dir=.derived --exclude-dir=.swiftpm --exclude-dir=xcuserdata \
  --exclude-dir=DerivedData 'manaflow' "$APP")"

# 5. The shellx-link boundary.
if ! link_output="$(bash "$SCRIPT_DIR/check-link-license.sh" 2>&1)"; then
  echo "$link_output"
  violation "shellx-link" "scripts/shellx/check-link-license.sh failed"
fi

if [ "$fail" -eq 0 ]; then
  echo "check-ios-license: ok"
fi
exit "$fail"
