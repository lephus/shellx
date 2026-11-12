#!/usr/bin/env python3
"""Writes the open-source licence notices the ShellX Android app shows in Settings > About > Licenses (plan 3H, Task 7).

The libraries are the non-ShellX releaseRuntimeClasspath entries of app/gradle.lockfile; each one's licence comes from
its POM in the Gradle cache (or from a parent POM). The file carries, offline and in a stable order:
- each library's name, version, licence name and URL;
- the Apache-2.0 text once (scripts/licence-texts/Apache-2.0.txt), referenced from each Apache library;
- for every other licence except the Android SDK and Play Core terms of use: the library's own licence text with its
  copyright line, from the artifact (META-INF/LICENSE*, LICENSE*, also inside an aar's classes.jar) or else from
  scripts/licence-texts/<group>_<artifact>.txt; when neither exists the generator stops naming the library;
- the contents of any META-INF/NOTICE* file of an artifact (Apache-2.0 section 4(d));
- the third-party notices that Google's aars embed (third_party_licenses.json/.txt, or the metadata form), each
  component's text once, attributed to the aar it came from.
Without --check the notice file is written; with --check it is only compared with what would be written.
"""
from __future__ import annotations

import argparse
import io
import json
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_DIR = Path(__file__).resolve().parents[1]
MAX_PARENTS = 5
HEADER = "Open-source software in ShellX for Android\n\n"
SECTION_LIBRARIES = "== Libraries =="
SECTION_TEXTS = "== Licence texts =="
SECTION_EMBEDDED = "== Notices embedded in Google libraries =="
APACHE_TITLE = "Apache License, Version 2.0"
APACHE_TEXT_HEADER = "LICENCE TEXT: " + APACHE_TITLE
APACHE_FILE = "Apache-2.0.txt"
VENDORED_DIR = "shellx-android/scripts/licence-texts"
TERMS_OF_USE = ("android software development kit license", "play core software development kit terms of service")
MAX_TEXT_BYTES = 400_000
COPYRIGHT_RE = re.compile(r"copyright|\(c\)|\u00a9", re.IGNORECASE)
HINT = "run shellx-android/scripts/dev.sh lock and a build first"


def libraries(lockfile: Path) -> list[tuple[str, str, str]]:
    found: dict[tuple[str, str], str] = {}
    for line in lockfile.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        coordinate, configurations = line.split("=", 1)
        if "releaseRuntimeClasspath" not in configurations.split(","):
            continue
        parts = coordinate.split(":")
        if len(parts) != 3 or parts[0].startswith("com.shellx."):
            continue
        found[(parts[0], parts[1])] = parts[2]
    return [(g, a, found[(g, a)]) for g, a in sorted(found)]


def find_pom(cache: Path, group: str, artifact: str, version: str) -> Path | None:
    folder = cache / group / artifact / version
    if not folder.is_dir():
        return None
    matches = sorted(folder.glob("*/%s-%s.pom" % (artifact, version)))
    return matches[0] if matches else None


def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def child(element: ET.Element, name: str) -> ET.Element | None:
    for item in element:
        if local(item.tag) == name:
            return item
    return None


def child_text(element: ET.Element, name: str) -> str:
    found = child(element, name)
    return (found.text or "").strip() if found is not None else ""


def describe(cache: Path, group: str, artifact: str, version: str) -> tuple[str, list[tuple[str, str]]]:
    coordinate = "%s:%s:%s" % (group, artifact, version)
    name = ""
    current = (group, artifact, version)
    for depth in range(MAX_PARENTS + 1):
        pom = find_pom(cache, *current)
        if pom is None:
            raise SystemExit("generate-licences: no POM for %s:%s:%s in %s: run shellx-android/scripts/dev.sh lock "
                             "and a build first" % (current + (cache,)))
        root = ET.parse(pom).getroot()
        if depth == 0:
            name = child_text(root, "name") or artifact
        licences = []
        container = child(root, "licenses")
        if container is not None:
            for item in container:
                if local(item.tag) != "license":
                    continue
                licence_name = child_text(item, "name")
                if licence_name:
                    licences.append((licence_name, child_text(item, "url")))
        if licences:
            return name, licences
        parent = child(root, "parent")
        if parent is None:
            break
        current = (child_text(parent, "groupId"), child_text(parent, "artifactId"), child_text(parent, "version"))
    raise SystemExit("generate-licences: no licence in the POM of %s or its parents" % coordinate)


def kind_of(licence_name: str, url: str) -> str:
    if licence_name.lower().startswith(TERMS_OF_USE):
        return "terms"
    if "apache" in (licence_name + " " + url).lower():
        return "apache"
    return "own"


def artifact_files(cache: Path, group: str, artifact: str, version: str) -> list[Path]:
    folder = cache / group / artifact / version
    found = [p for p in folder.glob("*/*") if p.suffix in (".jar", ".aar")
             and not p.name.endswith(("-sources.jar", "-javadoc.jar"))]
    return sorted(found, key=lambda p: p.name)


def decode(data: bytes) -> str:
    text = data.decode("utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n")
    return text.strip("\n").rstrip()


EMBEDDED_NAMES = tuple(prefix + name for prefix in ("", "res/raw/") for name in (
    "third_party_licenses.json", "third_party_licenses.txt", "third_party_licenses", "third_party_license_metadata"))


def wanted(name: str) -> bool:
    return bool(file_kind(name)) or name in EMBEDDED_NAMES


def zip_entries(data: bytes, nested_label: str) -> list[tuple[str, str, bytes]]:
    """(label, entry name, bytes) of the licence, notice and embedded-notice files of a jar or aar, and of an aar's
    classes.jar (labelled nested_label)."""
    out: list[tuple[str, str, bytes]] = []
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for name in sorted(z.namelist()):
            if name == "classes.jar":
                with zipfile.ZipFile(io.BytesIO(z.read(name))) as inner:
                    for inner_name in sorted(inner.namelist()):
                        if wanted(inner_name) and inner_name not in EMBEDDED_NAMES:
                            out.append((nested_label, inner_name, inner.read(inner_name)))
            elif wanted(name) and not name.endswith("/"):
                out.append(("", name, z.read(name)))
    return out


def file_kind(entry: str) -> str:
    """'licence' or 'notice' for LICENSE*/COPYING* and NOTICE* at the top or in META-INF, else ''."""
    parts = entry.split("/")
    if len(parts) > 2 or (len(parts) == 2 and parts[0] != "META-INF"):
        return ""
    stem, dot, extension = parts[-1].lower().rpartition(".")
    if not dot:
        stem = extension
    elif extension not in ("txt", "md"):
        return ""
    if stem.startswith(("license", "licence", "copying")):
        return "licence"
    if stem.startswith("notice"):
        return "notice"
    return ""


def from_artifacts(files: list[Path]) -> tuple[list[tuple[str, str]], list[tuple[str, str]], list[tuple[str, list[tuple[str, str]]]]]:
    """(licence texts, notice files, embedded notices per aar) found in a library's artifacts."""
    licences: list[tuple[str, str]] = []
    notices: list[tuple[str, str]] = []
    embedded: list[tuple[str, list[tuple[str, str]]]] = []
    for path in files:
        entries = zip_entries(path.read_bytes(), "classes.jar")
        raw = {name: data for label, name, data in entries if not label}
        for label, name, data in entries:
            kind = file_kind(name) if len(data) <= MAX_TEXT_BYTES else ""
            where = "%s in %s of the library" % (name, label) if label else "%s in the library" % name
            if kind == "licence":
                licences.append((where, decode(data)))
            elif kind == "notice":
                notices.append((where, decode(data)))
        if path.suffix == ".aar":
            found = embedded_notices(raw)
            if found:
                embedded.append((path.name, found))
    return licences, notices, embedded


def embedded_notices(raw: dict[str, bytes]) -> list[tuple[str, str]]:
    """Google's third-party notices of an aar: (component, text), sorted by component."""
    pairs: list[tuple[str, int, int]] = []
    for prefix in ("", "res/raw/"):
        if prefix + "third_party_licenses.json" in raw:
            index = json.loads(raw[prefix + "third_party_licenses.json"].decode("utf-8"))
            pairs = [(name, spec["start"], spec["length"]) for name, spec in index.items()]
            body = raw[prefix + "third_party_licenses.txt"] if prefix + "third_party_licenses.txt" in raw \
                else raw[prefix + "third_party_licenses"]
            break
        if prefix + "third_party_license_metadata" in raw and prefix + "third_party_licenses" in raw:
            for line in raw[prefix + "third_party_license_metadata"].decode("utf-8").splitlines():
                span, _, name = line.partition(" ")
                start, _, length = span.partition(":")
                if name and start.isdigit() and length.isdigit():
                    pairs.append((name.strip(), int(start), int(length)))
            body = raw[prefix + "third_party_licenses"]
            break
    else:
        return []
    return sorted((name, decode(body[start:start + length])) for name, start, length in pairs)


class Library:
    def __init__(self, group: str, artifact: str, version: str, name: str, licences: list[tuple[str, str]]):
        self.group, self.artifact, self.version, self.name, self.licences = group, artifact, version, name, licences

    @property
    def coordinate(self) -> str:
        return "%s:%s:%s" % (self.group, self.artifact, self.version)


def own_text(lib: Library, candidates: list[tuple[str, str]], texts_dir: Path, has_artifact: bool) -> list[tuple[str, str]]:
    """The library's own licence text(s) for its non-Apache, non-terms licences, with a copyright line."""
    usable: list[tuple[str, str]] = []
    for where, text in candidates:
        if "Apache License" not in text and COPYRIGHT_RE.search(text) and (where, text) not in usable:
            usable.append((where, text))
    if usable:
        return usable
    vendored = texts_dir / ("%s_%s.txt" % (lib.group, lib.artifact))
    if vendored.is_file():
        return [("vendored %s/%s" % (VENDORED_DIR, vendored.name), decode(vendored.read_bytes()))]
    needing = ", ".join(n for n, u in lib.licences if kind_of(n, u) == "own")
    raise SystemExit("generate-licences: no licence text with a copyright line for %s (%s): its artifact ships none; "
                     "add the project's own licence text as %s/%s_%s.txt%s"
                     % (lib.coordinate, needing, VENDORED_DIR, lib.group, lib.artifact,
                        "" if has_artifact else " (and %s: no jar or aar is in the Gradle cache)" % HINT))


def block(title: str, text: str) -> str:
    return "%s\n\n%s\n\n" % (title, text)


def notice_text(libs: list[tuple[str, str, str]], cache: Path, texts_dir: Path) -> str:
    apache_used = False
    entries: list[str] = []
    embedded_ids: dict[str, int] = {}
    embedded_names: dict[int, set] = {}
    embedded_bodies: list[str] = []
    embedded_sections: list[str] = []
    for group, artifact, version in libs:
        name, licences = describe(cache, group, artifact, version)
        lib = Library(group, artifact, version, name, licences)
        files = artifact_files(cache, group, artifact, version)
        found_licences, found_notices, found_embedded = from_artifacts(files)
        out = ["%s (%s)\n" % (name, lib.coordinate)]
        kinds = []
        for licence_name, url in licences:
            kind = kind_of(licence_name, url)
            kinds.append(kind)
            line = ("License: %s %s" % (licence_name, url)).rstrip()
            if kind == "terms":
                line += " (terms of use, not an open-source licence: no licence text is reproduced here)"
            out.append(line + "\n")
        if "apache" in kinds:
            apache_used = True
            out.append('Licence text: %s (full text in the section "Licence texts" below)\n' % APACHE_TITLE)
        entry = "".join(out)
        if "own" in kinds:
            for where, text in own_text(lib, found_licences, texts_dir, bool(files)):
                entry += block("Licence text of %s (%s):" % (name, where), text)
        for where, text in found_notices:
            entry += block("Notice of %s (%s):" % (name, where), text)
        entries.append(entry if entry.endswith("\n\n") else entry + "\n")
        for aar_name, components in found_embedded:
            lines = ["Embedded in %s\n" % lib.coordinate]
            for component, text in components:
                if text not in embedded_ids:
                    embedded_ids[text] = len(embedded_ids) + 1
                    embedded_bodies.append(text)
                number = embedded_ids[text]
                embedded_names.setdefault(number, set()).add(component)
                lines.append("  %s (text E%d)\n" % (component, number))
            embedded_sections.append("".join(lines) + "\n")
    out = [HEADER, SECTION_LIBRARIES + "\n\n"] + entries
    if apache_used:
        apache = decode((texts_dir / APACHE_FILE).read_bytes()) if (texts_dir / APACHE_FILE).is_file() else None
        if apache is None:
            raise SystemExit("generate-licences: %s/%s is missing" % (VENDORED_DIR, APACHE_FILE))
        out.append(SECTION_TEXTS + "\n\n")
        out.append(block(APACHE_TEXT_HEADER, apache))
    if embedded_sections:
        out.append(SECTION_EMBEDDED + "\n\n")
        out.extend(embedded_sections)
        for number, text in enumerate(embedded_bodies, 1):
            out.append(block("EMBEDDED NOTICE TEXT E%d: %s" % (number, ", ".join(sorted(embedded_names[number]))), text))
    return "".join(out).rstrip("\n") + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="only report whether the notice file is up to date")
    parser.add_argument("--lockfile", type=Path, default=ANDROID_DIR / "app" / "gradle.lockfile")
    parser.add_argument("--gradle-cache", type=Path, default=Path.home() / ".gradle" / "caches" / "modules-2" / "files-2.1")
    parser.add_argument("--licence-texts", type=Path, default=ANDROID_DIR / "scripts" / "licence-texts",
                        help="texts vendored for libraries whose artifact ships none, and Apache-2.0.txt")
    parser.add_argument("--out", type=Path,
                        default=ANDROID_DIR / "app" / "src" / "main" / "assets" / "licenses" / "third_party_licenses.txt")
    args = parser.parse_args()
    libs = libraries(args.lockfile)
    text = notice_text(libs, args.gradle_cache, args.licence_texts)
    if args.check:
        if args.out.is_file() and args.out.read_bytes() == text.encode("utf-8"):
            print("generate-licences: ok (%d libraries)" % len(libs))
            return 0
        print("generate-licences: stale; run python3 shellx-android/scripts/generate-licences.py")
        return 1
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print("generate-licences: wrote %d libraries to %s" % (len(libs), args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
