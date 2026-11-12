#!/usr/bin/env python3
"""Writes the open-source licence notices the ShellX Android app shows in Settings > About > Licenses (plan 3H, Task 7).

The libraries are the non-ShellX releaseRuntimeClasspath entries of app/gradle.lockfile; each one's licence comes from
its POM in the Gradle cache (or from a parent POM). Without --check the notice file is written; with --check it is only
compared with what would be written.
"""
from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_DIR = Path(__file__).resolve().parents[1]
MAX_PARENTS = 5
HEADER = "Open-source software in ShellX for Android\n\n"


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


def notice_text(libs: list[tuple[str, str, str]], cache: Path) -> str:
    out = [HEADER]
    for group, artifact, version in libs:
        name, licences = describe(cache, group, artifact, version)
        out.append("%s (%s:%s:%s)\n" % (name, group, artifact, version))
        for licence_name, url in licences:
            out.append(("License: %s %s" % (licence_name, url)).rstrip() + "\n")
        out.append("\n")
    return "".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="only report whether the notice file is up to date")
    parser.add_argument("--lockfile", type=Path, default=ANDROID_DIR / "app" / "gradle.lockfile")
    parser.add_argument("--gradle-cache", type=Path, default=Path.home() / ".gradle" / "caches" / "modules-2" / "files-2.1")
    parser.add_argument("--out", type=Path,
                        default=ANDROID_DIR / "app" / "src" / "main" / "assets" / "licenses" / "third_party_licenses.txt")
    args = parser.parse_args()
    libs = libraries(args.lockfile)
    text = notice_text(libs, args.gradle_cache)
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
