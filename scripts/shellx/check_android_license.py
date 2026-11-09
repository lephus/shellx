#!/usr/bin/env python3
"""The checks behind scripts/shellx/check-android-license.sh (see its header for the rules)."""
from __future__ import annotations

import argparse
import os
import posixpath
import re
import sys
from pathlib import Path

TREES = ["shellx-android", "shellx-link/kotlin"]
ALLOWED_ROOTS = ["shellx-android", "shellx-link/kotlin", "shellx-link/vectors", "shellx-link/spec"]
BUILD_ROOTS = ["shellx-android/build.gradle.kts", "shellx-link/kotlin/build.gradle.kts"]
SKIP_DIRS = {"build", ".gradle", ".kotlin", ".idea", "__pycache__"}
ALLOWLIST = "scripts/shellx/android-license-allowlist.txt"
SHIP_LICENCES = {"Apache-2.0", "MIT", "BSD-2-Clause", "BSD-3-Clause", "Bouncy-Castle", "Google-SDK"}
TEST_LICENCES = SHIP_LICENCES | {"EPL-1.0", "EPL-2.0", "ICU", "CDDL-1.1"}
WILDCARDS = {"androidx.*:*", "org.jetbrains.kotlin:*", "org.jetbrains.kotlinx:*"}
GOOGLE_GROUPS = {"com.google.android.gms", "com.google.firebase", "com.google.android.datatransport",
                 "com.google.android.play", "com.google.android.libraries.identity.googleid"}
PATH_CALLS = re.compile(r"\b(Paths\.get|Path\.of|includeBuild|fileTree|files|file|File|srcDirs|srcDir|dir|"
                        r"resolveSibling|resolve|uri|from|apply)\s*\(")
# Calls that always resolve against the project folder (Project.file and friends), whatever their receiver.
PROJECT_CALLS = {"srcDir", "srcDirs", "includeBuild", "apply", "from", "uri"}
# Calls resolved against the working directory of the Gradle daemon when their first argument is a string.
CWD_CALLS = {"File", "Paths.get", "Path.of"}
ROOT_TOKENS = re.compile(r"\b(?:rootProject|rootDir|rootDirectory|settingsDir|settingsDirectory)\b")
MODULE_TOKENS = re.compile(r"\b(?:projectDir|projectDirectory|buildDir|buildDirectory)\b")
MODULE_RECEIVER = re.compile(r"^(?:project\.)?(?:(?:layout\.)?(?:projectDirectory|projectDir|buildDirectory|buildDir)"
                             r"(?:\.get\(\))?(?:\.asFile)?\.)?$")
ENV_TOKENS = re.compile(r"\bSystem\s*\.\s*(?:getenv|getProperty)\b|\bgradleUserHomeDir\b|\buserHome\b")
PARENT = re.compile(r"\.\s*(?:parentFile|parent)\b|\b(?:getParentFile|getParent)\s*\(")
URL_SCHEME = re.compile(r"^([A-Za-z][A-Za-z0-9+.-]+):")
TEST_CONFIG = re.compile(r"^test(?:[A-Z]|$)|UnitTest|AndroidTest|ScreenshotTest|HostTest|DeviceTest|TestFixtures")
ANDROID_CONFIG = re.compile(r"^(?:debug|release)(?:[A-Z]\w*)?RuntimeClasspath$")
STRICT_LOCKING = re.compile(r"\blockMode\s*(?:\.\s*set\s*\(|=)\s*LockMode\s*\.\s*STRICT\b")
DESUGARING = re.compile(r"\b(?:coreLibraryDesugaring|isCoreLibraryDesugaringEnabled)\b")
ROOTS_TEXT = "shellx-android/, shellx-link/kotlin/, shellx-link/vectors/ and shellx-link/spec/"
REPO_CALL = re.compile(r"\b(maven|mavenLocal|jcenter|ivy|flatDir)\s*[({]")
REPO_CONFIGURED = re.compile(r"\b(google|mavenCentral|gradlePluginPortal)\s*\{")
REPO_BLOCK = re.compile(r"\brepositories\s*\{")
ALLOWED_REPO = re.compile(r"\b(?:google|mavenCentral|gradlePluginPortal)\s*\(\s*\)")
PLUGIN_MANAGEMENT = re.compile(r"\bpluginManagement\s*\{")
COMPANY = re.compile(r"(?<![A-Za-z0-9_])manaflow(?![A-Za-z0-9_])", re.IGNORECASE)
GRADLE_PROPERTIES = "shellx-android/gradle.properties"
SDK_DOWNLOAD = re.compile(r"^[ \t]*android\.builder\.sdkDownload[ \t]*[=:][ \t]*(\S*)[ \t]*$", re.MULTILINE)


class Report:
    def __init__(self) -> None:
        self.items = []

    def add(self, path: str, message: str, line: int = 0) -> None:
        where = "%s:%d" % (path, line) if line else path
        self.items.append((path, line, "violation: %s: %s" % (where, message)))


# ---- Kotlin DSL reading -------------------------------------------------------------------------

def string_end(text: str, i: int) -> int:
    """text[i] is the opening quote of a string literal; return the index just after its end."""
    if text.startswith('"""', i):
        j = text.find('"""', i + 3)
        return len(text) if j < 0 else j + 3
    j = i + 1
    while j < len(text):
        ch = text[j]
        if ch == "\\":
            j += 2
            continue
        if ch == '"':
            return j + 1
        if ch == "$" and text.startswith("${", j):
            depth = 0
            j += 1
            while j < len(text):
                if text[j] == '"':
                    j = string_end(text, j)
                    continue
                if text[j] == "{":
                    depth += 1
                elif text[j] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
        j += 1
    return len(text)


def blank_comments(text: str) -> str:
    """Replace comments by spaces (newlines kept); string literals are left as written."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif text.startswith("/*", i):
            depth = 0
            j = i
            while j < n:
                if text.startswith("/*", j):
                    depth += 1
                    j += 2
                elif text.startswith("*/", j):
                    depth -= 1
                    j += 2
                    if depth == 0:
                        break
                else:
                    j += 1
            out.append("".join(c if c == "\n" else " " for c in text[i:j]))
            i = j
        elif text[i] == '"':
            j = string_end(text, i)
            out.append(text[i:j])
            i = j
        elif text[i] == "'":
            m = re.match(r"'(?:\\.|[^'\\])'", text[i:])
            if m:
                out.append(m.group(0))
                i += len(m.group(0))
            else:
                out.append(text[i])
                i += 1
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def blank_strings(code: str) -> str:
    out = []
    i = 0
    while i < len(code):
        if code[i] == '"':
            j = string_end(code, i)
            out.append('"' + "".join(c if c == "\n" else " " for c in code[i + 1:j - 1]) + '"' if j - i >= 2 else code[i:j])
            i = j
        else:
            out.append(code[i])
            i += 1
    return "".join(out)


def string_literals(code: str):
    """Yield (start, end, body, is_plain) for every string literal of code (comments already blanked)."""
    i = 0
    while i < len(code):
        if code[i] == '"':
            j = string_end(code, i)
            raw = code[i:j]
            if raw.startswith('"""'):
                yield i, j, raw, False
            else:
                body = raw[1:-1] if raw.endswith('"') and len(raw) >= 2 else raw[1:]
                yield i, j, body, "$" not in body and "\\" not in body
            i = j
        else:
            i += 1


def block_end(bare: str, start: int) -> int:
    """bare[start - 1] is an opening brace (strings blanked); return the index after its partner."""
    depth = 1
    i = start
    while i < len(bare) and depth:
        if bare[i] == "{":
            depth += 1
        elif bare[i] == "}":
            depth -= 1
        i += 1
    return i


def call_end(bare: str, start: int) -> int:
    """bare[start - 1] is an opening parenthesis (strings blanked); return the index after its partner."""
    depth = 1
    i = start
    while i < len(bare) and depth:
        if bare[i] == "(":
            depth += 1
        elif bare[i] == ")":
            depth -= 1
        i += 1
    return i


def receiver_before(bare: str, idx: int) -> str:
    """The receiver chain written before the call that starts at idx, without spaces ("" when there is none)."""
    j = idx
    while True:
        k = j
        while k > 0 and bare[k - 1] in " \t\r\n":
            k -= 1
        if k == 0 or bare[k - 1] != ".":
            break
        k -= 1
        while k > 0 and bare[k - 1] in "?!":
            k -= 1
        while k > 0 and bare[k - 1] in " \t\r\n":
            k -= 1
        while k > 0 and bare[k - 1] in ")]":
            close = bare[k - 1]
            opener = "(" if close == ")" else "["
            depth = 0
            m = k - 1
            while m >= 0:
                if bare[m] == close:
                    depth += 1
                elif bare[m] == opener:
                    depth -= 1
                    if depth == 0:
                        break
                m -= 1
            k = max(m, 0)
        while k > 0 and (bare[k - 1].isalnum() or bare[k - 1] in "_$"):
            k -= 1
        if k >= j:
            break
        j = k
    return re.sub(r"\s+", "", bare[j:idx])


def literals_in(code: str, start: int):
    """Yield (literal text, is_plain) for every string literal in the parentheses opened just before start.
    Returns the list and the index after the closing parenthesis."""
    found = []
    depth = 1
    i = start
    while i < len(code) and depth:
        ch = code[i]
        if ch == '"':
            j = string_end(code, i)
            raw = code[i:j]
            if raw.startswith('"""'):
                found.append((raw, False))
            else:
                body = raw[1:-1] if raw.endswith('"') and len(raw) >= 2 else raw[1:]
                found.append((body, "$" not in body and "\\" not in body))
            i = j
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        i += 1
    return found


def line_of(code: str, index: int) -> int:
    return code.count("\n", 0, index) + 1


# ---- checks -------------------------------------------------------------------------------------

def walk(root: Path):
    """Yield (relative path, absolute path) of every file and symlink below the two trees."""
    for tree in TREES:
        base = root / tree
        if not base.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(str(base)):
            dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
            for name in sorted(dirnames) + sorted(filenames):
                full = Path(dirpath) / name
                yield full.relative_to(root).as_posix(), full


def load_allowlist(root: Path, report: Report):
    entries = {}
    path = root / ALLOWLIST
    if not path.is_file():
        report.add(ALLOWLIST, "allowlist is missing")
        return entries
    seen = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 3 or ":" not in parts[0]:
            report.add(ALLOWLIST, "line is not '<group>:<artifact> <scope> <licence>': %r" % raw.strip(), number)
            continue
        key, scope, licence = parts
        group, artifact = key.split(":", 1)
        if key in seen:
            report.add(ALLOWLIST, "%s is listed twice (lines %d and %d)" % (key, seen[key], number), number)
            continue
        seen[key] = number
        if scope not in ("ship", "test"):
            report.add(ALLOWLIST, "%s: scope %r is neither ship nor test" % (key, scope), number)
            continue
        if "GPL" in licence.upper():
            report.add(ALLOWLIST, "%s: copyleft licence %s is never allowed" % (key, licence), number)
            continue
        if licence not in (SHIP_LICENCES if scope == "ship" else TEST_LICENCES):
            report.add(ALLOWLIST, "%s: licence %s is not allowed for scope %s" % (key, licence, scope), number)
            continue
        if "*" in key and key not in WILDCARDS:
            report.add(ALLOWLIST, "%s: wildcards are allowed only in %s" % (key, ", ".join(sorted(WILDCARDS))), number)
            continue
        if group in GOOGLE_GROUPS and artifact == "*":
            report.add(ALLOWLIST, "%s: Google SDKs must be listed by artifact name" % key, number)
            continue
        if licence == "Google-SDK" and group not in GOOGLE_GROUPS:
            report.add(ALLOWLIST, "%s: Google-SDK is allowed only for %s" % (key, ", ".join(sorted(GOOGLE_GROUPS))), number)
            continue
        entries[key] = scope
    return entries


def lookup(entries, group: str, artifact: str):
    exact = "%s:%s" % (group, artifact)
    if exact in entries:
        return entries[exact]
    if "%s:*" % group in entries:
        return entries["%s:*" % group]
    best = None
    for key in entries:
        g, _, a = key.partition(":")
        if g.endswith(".*") and a == "*" and group.startswith(g[:-1]):
            if best is None or len(g) > len(best[0]):
                best = (g, entries[key])
    return best[1] if best else None


def check_lockfile(rel: str, text: str, entries, report: Report) -> None:
    named = set()
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        coords, _, confs = line.partition("=")
        configs = [c for c in confs.split(",") if c]
        named.update(configs)
        if coords == "empty":
            continue
        parts = coords.split(":")
        if len(parts) < 3:
            report.add(rel, "unreadable lockfile line %r" % line, number)
            continue
        group, artifact, version = parts[0], parts[1], parts[2]
        ships = any(not TEST_CONFIG.search(c) for c in configs)
        scope = "ship" if ships else "test"
        allowed = lookup(entries, group, artifact)
        label = "%s:%s:%s" % (group, artifact, version)
        if allowed is None:
            report.add(rel, "%s (%s) is not on %s" % (label, scope, ALLOWLIST), number)
        elif scope == "ship" and allowed == "test":
            report.add(rel, "%s (ship) is allowed on test classpaths only; move its allowlist line to ship" % label,
                       number)
    # An Android module locks both build types (a missing debug line would leave the debug app unchecked);
    # a JVM module locks runtimeClasspath.
    needed = ["debugRuntimeClasspath", "releaseRuntimeClasspath"] if any(ANDROID_CONFIG.match(c) for c in named) \
        else ["runtimeClasspath"]
    for config in needed:
        if config not in named:
            report.add(rel, "gradle.lockfile has no %s line; run shellx-android/scripts/dev.sh lock" % config)


def inside_roots(path: str) -> bool:
    return any(path == r or path.startswith(r + "/") for r in ALLOWED_ROOTS)


def build_root(rel: str) -> str:
    return "shellx-android" if rel.startswith("shellx-android/") else "shellx-link/kotlin"


def anchors(call: str, receiver: str, context: str):
    """The folders a literal path in this call may be resolved from: the module folder, the build root, or both
    when the receiver is not one the check knows."""
    if ROOT_TOKENS.search(context):
        return ["root"]
    if call in PROJECT_CALLS:
        return ["module"]
    if call in ("file", "files", "fileTree", "dir", "resolve", "resolveSibling") and MODULE_RECEIVER.match(receiver):
        return ["module"]
    if call in CWD_CALLS and MODULE_TOKENS.search(context):
        return ["module"]
    return ["module", "root"]


def resolved_paths(rel: str, literal: str, call: str, where):
    if call == "resolveSibling":
        literal = posixpath.join("..", literal)
    folders = {"module": posixpath.dirname(rel), "root": build_root(rel)}
    return [posixpath.normpath(posixpath.join(folders[w], literal)) for w in where]


def has_parent_segment(text: str) -> bool:
    return ".." in text.split("/")


def check_kts(rel: str, text: str, report: Report) -> None:
    code = blank_comments(text)
    bare = blank_strings(code)
    for m in REPO_CALL.finditer(bare):
        report.add(rel, "repository %s is not allowed; only google() and mavenCentral()" % m.group(1),
                   line_of(code, m.start()))
    for m in DESUGARING.finditer(bare):
        report.add(rel, "core library desugaring is not allowed: it ships desugar_jdk_libs (GPLv2 with the "
                        "Classpath Exception) outside every lockfile", line_of(code, m.start()))
    for m in REPO_CONFIGURED.finditer(bare):
        report.add(rel, "%s { … } can change the repository URL or content; write %s()" % (m.group(1), m.group(1)),
                   line_of(code, m.start()))
    for m in REPO_BLOCK.finditer(bare):
        body = bare[m.end():block_end(bare, m.end()) - 1]
        rest = re.sub(r"[\s;]+", " ", ALLOWED_REPO.sub(" ", body)).strip()
        if rest:
            report.add(rel, "repositories { } may hold only google(), mavenCentral() and, in pluginManagement, "
                            "gradlePluginPortal(); found: %s" % rest[:60], line_of(code, m.start()))
    plugin_blocks = []
    if posixpath.basename(rel) == "settings.gradle.kts":
        plugin_blocks = [(m.end(), block_end(bare, m.end())) for m in PLUGIN_MANAGEMENT.finditer(bare)]
    for m in re.finditer(r"\bgradlePluginPortal\s*\(", bare):
        if not any(a <= m.start() < b for a, b in plugin_blocks):
            report.add(rel, "gradlePluginPortal() is allowed only in the pluginManagement { } block of "
                            "settings.gradle.kts", line_of(code, m.start()))
    seen = set()

    def add(message: str, line: int) -> None:
        if (line, message) not in seen:
            seen.add((line, message))
            report.add(rel, message, line)

    for m in PARENT.finditer(bare):
        add("navigates to a parent folder (parent, parentFile); write a relative path instead",
            line_of(code, m.start()))
    covered = []
    for m in PATH_CALLS.finditer(bare):
        call = m.group(1)
        line = line_of(code, m.start())
        end = call_end(bare, m.end())
        covered.append((m.end(), end))
        receiver = receiver_before(bare, m.start())
        context = receiver + bare[m.end():end]
        if ENV_TOKENS.search(context):
            add("%s(…) path is built from the environment (System.getenv, user.home)" % call, line)
        if call in CWD_CALLS and bare[m.end():end].lstrip().startswith('"'):
            add("%s(\"…\") is relative to the working directory of the Gradle daemon; use file(…) or "
                "rootProject.file(…)" % call, line)
        where = anchors(call, receiver, context)
        for literal, plain in literals_in(code, m.end()):
            scheme = URL_SCHEME.match(literal) if plain else None
            if not plain:
                add("%s(…) path is not a plain string literal" % call, line)
            elif scheme and scheme.group(1).lower() != "file":
                continue
            elif scheme or literal.startswith("/") or literal.startswith("~"):
                add('%s("%s") is absolute' % (call, literal), line)
            elif not all(inside_roots(path) for path in resolved_paths(rel, literal, call, where)):
                origin = {"module": "", "root": " (from the build root)"}.get(where[0], "") if len(where) == 1 \
                    else " (from the module folder or the build root)"
                add('%s("%s") points outside %s%s' % (call, literal, ROOTS_TEXT, origin), line)
    # A path kept in a variable is checked from both folders, since the call that uses it is not known.
    for start, _, body, plain in string_literals(code):
        if any(a <= start < b for a, b in covered) or not has_parent_segment(body):
            continue
        line = line_of(code, start)
        if not plain:
            add('"%s" builds a path with ".." from a template; write a plain relative path' % body, line)
        elif not all(inside_roots(path) for path in resolved_paths(rel, body, "", ["module", "root"])):
            add('"%s" points outside %s when used as a path from the module folder or the build root; '
                'write it inside file(…) or rootProject.file(…)' % (body, ROOTS_TEXT), line)


def check_sdk_download(root: Path, report: Report) -> None:
    """AGP downloads missing SDK packages unless android.builder.sdkDownload is false (the last value wins)."""
    if not (root / "shellx-android").is_dir():
        return
    props = root / GRADLE_PROPERTIES
    text = props.read_text(encoding="utf-8", errors="replace") if props.is_file() else ""
    values = SDK_DOWNLOAD.findall(text)
    if not values or values[-1] != "false":
        report.add(GRADLE_PROPERTIES, "must set android.builder.sdkDownload=false, so AGP never downloads SDK "
                                      "packages (the user installs them with sdkmanager)")


def run(root: Path) -> int:
    report = Report()
    entries = load_allowlist(root, report)
    check_sdk_download(root, report)
    files = list(walk(root))
    for rel, full in files:
        if full.is_symlink():
            report.add(rel, "symlinks are not allowed")
            continue
        if full.is_dir():
            continue
        name = posixpath.basename(rel)
        ext = posixpath.splitext(name)[1]
        if ext in (".jar", ".aar", ".so") and not rel.endswith("gradle/wrapper/gradle-wrapper.jar"):
            report.add(rel, "vendored binary %s is not allowed" % ext)
            continue
        if ext == ".gradle":
            report.add(rel, "Groovy build scripts are not allowed")
            continue
        try:
            data = full.read_bytes()
        except OSError as error:
            report.add(rel, "unreadable: %s" % error)
            continue
        if b"\0" not in data[:8192]:
            text = data.decode("utf-8", errors="replace")
            if COMPANY.search(text):
                report.add(rel, "names the upstream company")
            if name.endswith(".gradle.kts"):
                check_kts(rel, text, report)
            if name == "gradle.lockfile":
                check_lockfile(rel, text, entries, report)
        if name == "build.gradle.kts" and rel not in BUILD_ROOTS:
            lock = full.parent / "gradle.lockfile"
            if not lock.is_file():
                report.add(posixpath.dirname(rel), "module has no gradle.lockfile; run its dependency locking")
            bare = blank_strings(blank_comments(data.decode("utf-8", errors="replace")))
            if "activateDependencyLocking" not in bare:
                report.add(rel, "module does not lock its runtime classpaths "
                                "(resolutionStrategy.activateDependencyLocking())")
            if not STRICT_LOCKING.search(bare):
                report.add(rel, "module must lock in strict mode, so an unlocked configuration fails: "
                                "dependencyLocking { lockMode.set(LockMode.STRICT) }")
    for path, line, message in sorted(report.items, key=lambda item: (item[0], item[1], item[2])):
        print(message)
    return 1 if report.items else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    args = parser.parse_args()
    return run(Path(args.root))


if __name__ == "__main__":
    sys.exit(main())
