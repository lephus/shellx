#!/usr/bin/env python3
"""Checks of the ShellX Android release bundle (plan 3H): manifest, Google Play's target API rule, permissions,
native code, debug-only code, the R8 mapping, Firebase and the Google web client id.

Standard library only (Python 3.9). Run with `python3 -I`.
"""
from __future__ import annotations

import argparse
import datetime
import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
import zipfile
from dataclasses import dataclass

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
APPLICATION_ID = "com.shellx.prod"
MIN_SDK = "26"
NEVER_ALLOWED_PERMISSIONS = {
    "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS": "S3 §7.4c",
    "com.google.android.gms.permission.AD_ID": "the Advertising ID declaration says no",
}
DEBUG_ONLY_ACTIVITIES = ("androidx.activity.ComponentActivity", "androidx.compose.ui.tooling.PreviewActivity")

RULES_FILE = "release/mobile/android-play-target-sdk.txt"
PERMISSIONS_FILE = "release/mobile/android-permissions.txt"
PLAY_RULES_URL = "https://developer.android.com/google/play/requirements/target-sdk"


class RuleTableError(ValueError):
    pass


@dataclass(frozen=True)
class Manifest:
    package: str
    version_code: str
    version_name: str
    min_sdk: str
    target_sdk: str
    application: dict
    permissions: tuple
    activities: tuple


def _attr(element, name: str) -> str:
    return element.get(ANDROID_NS + name, "") if element is not None else ""


def parse_manifest(xml_text: str) -> Manifest:
    root = ET.fromstring(xml_text)
    uses_sdk = root.find("uses-sdk")
    application = root.find("application")
    app_attrs = {}
    activities = []
    if application is not None:
        for key, value in application.attrib.items():
            if key.startswith(ANDROID_NS):
                app_attrs[key[len(ANDROID_NS):]] = value
        activities = [_attr(a, "name") for a in application.findall("activity")]
    permissions = [_attr(p, "name") for p in root if p.tag in ("uses-permission", "uses-permission-sdk-23")]
    return Manifest(
        package=root.get("package", ""),
        version_code=_attr(root, "versionCode"),
        version_name=_attr(root, "versionName"),
        min_sdk=_attr(uses_sdk, "minSdkVersion"),
        target_sdk=_attr(uses_sdk, "targetSdkVersion"),
        application=app_attrs,
        permissions=tuple(permissions),
        activities=tuple(activities),
    )


def required_target_sdk(rules_text: str, today: datetime.date):
    rules = []
    for number, raw in enumerate(rules_text.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        try:
            if len(parts) != 2:
                raise ValueError(line)
            rules.append((datetime.date.fromisoformat(parts[0]), int(parts[1])))
        except ValueError:
            raise RuleTableError('%s line %d: expected "<YYYY-MM-DD> <api level>", got "%s"'
                                 % (RULES_FILE, number, raw.strip()))
    in_force = [r for r in rules if r[0] <= today]
    if not in_force:
        raise RuleTableError("%s has no rule in force on %s" % (RULES_FILE, today.isoformat()))
    newest = max(r[0] for r in rules)
    if (today - newest).days > 365:
        raise RuleTableError("the newest rule in %s is from %s, more than 365 days ago: read %s and add "
                             "this year's line" % (RULES_FILE, newest.isoformat(), PLAY_RULES_URL))
    since, level = max(in_force)
    return level, since


def read_permission_list(text: str) -> list:
    names = []
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            names.append(line)
    return names


def manifest_problems(m: Manifest, *, version_name: str, version_code: str, catalog_target_sdk: str,
                      required_sdk: int, required_since: datetime.date, permissions: list) -> list:
    found = []
    if m.package != APPLICATION_ID:
        found.append("application id is %s, expected %s" % (m.package, APPLICATION_ID))
    if m.version_code != version_code:
        found.append("versionCode is %s, shellx-android/version.properties says %s" % (m.version_code, version_code))
    if m.version_name != version_name:
        found.append("versionName is %s, shellx-android/version.properties says %s" % (m.version_name, version_name))
    if m.min_sdk != MIN_SDK:
        found.append("minSdkVersion is %s, expected %s" % (m.min_sdk, MIN_SDK))
    if m.target_sdk != catalog_target_sdk:
        found.append("targetSdkVersion is %s, the version catalog's androidTargetSdk is %s"
                     % (m.target_sdk, catalog_target_sdk))
    if not m.target_sdk.isdigit() or int(m.target_sdk) < required_sdk:
        found.append("targetSdkVersion %s is below %d, which Google Play requires since %s (%s)"
                     % (m.target_sdk, required_sdk, required_since.isoformat(), RULES_FILE))
    for attr in ("debuggable", "testOnly", "usesCleartextTraffic"):
        if m.application.get(attr) == "true":
            found.append("android:%s is true" % attr)
    if m.application.get("allowBackup") != "false":
        found.append("android:allowBackup is not false (S3 §7.3: nothing is backed up)")
    for name in m.activities:
        if name in DEBUG_ONLY_ACTIVITIES:
            found.append("declares the debug-only activity %s" % name)
    for p in m.permissions:
        if p in NEVER_ALLOWED_PERMISSIONS:
            found.append("requests %s, which ShellX never ships (%s)" % (p, NEVER_ALLOWED_PERMISSIONS[p]))
        elif p not in permissions:
            found.append("requests %s, which %s does not list (a new permission changes the Data safety "
                         "answers or needs a Play declaration)" % (p, PERMISSIONS_FILE))
    for p in permissions:
        if p not in m.permissions:
            found.append("%s lists %s, which the bundle does not request: remove it from the list"
                         % (PERMISSIONS_FILE, p))
    return found


MAPPING_ENTRY = "BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map"
DEBUG_ONLY_PACKAGES = (
    "org.junit.", "junit.", "org.robolectric.", "com.github.takahirom.roborazzi.", "androidx.test.",
    "androidx.compose.ui.test.", "androidx.compose.ui.tooling.", "kotlinx.coroutines.test.", "kotlin.test.",
    "mockwebserver3.", "okhttp3.mockwebserver.", "okhttp3.logging.", "leakcanary.", "com.shellx.core.testing.",
    "com.shellx.app.testing.", "com.shellx.app.screenshots.", "com.shellx.app.debug.",
)
DEBUG_ONLY_ALLOWED = ("androidx.compose.ui.tooling.preview.",)
DEBUG_ONLY_NAMES = ("FakeRelayAccount", "FakeIdentityProvider", "InMemorySecretStore", "FakeTranscriber",
                    "FakeVoicePermissions", "SHELLX_DEMO")
FORBIDDEN_SDKS = (
    "com.google.firebase:firebase-analytics", "com.google.firebase:firebase-crashlytics",
    "com.google.firebase:firebase-perf", "com.google.firebase:firebase-inappmessaging",
    "com.google.android.gms:play-services-measurement", "com.google.android.gms:play-services-ads",
    "com.google.android.gms:play-services-analytics", "com.google.android.gms:play-services-appset",
)
CLIENT_ID_RE = re.compile(r"^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$")
LEDGER_FILE = "docs/superpowers/ledgers/shellx-signin-rollout.md"
LEDGER_CLIENT = "ShellX Web (Android sign-in)"
FIREBASE_PROJECT = "shellxpro"

PT_LOAD = 1
PT_GNU_RELRO = 0x6474E552
PAGE_16K = 0x4000


def elf_problems(entry: str, data: bytes) -> list:
    """Google Play's 16 KB page size rule for one native library (developer.android.com/guide/practices/page-sizes)."""
    not_elf = ["%s: not an ELF shared library" % entry]
    if len(data) < 52 or data[:4] != b"\x7fELF" or data[4] not in (1, 2) or data[5] not in (1, 2):
        return not_elf
    order = "<" if data[5] == 1 else ">"
    try:
        if data[4] == 2:
            phoff, = struct.unpack_from(order + "Q", data, 32)
            phentsize, phnum = struct.unpack_from(order + "HH", data, 54)
            fmt, t, vaddr, memsz, align = "IIQQQQQQ", 0, 3, 6, 7
        else:
            phoff, = struct.unpack_from(order + "I", data, 28)
            phentsize, phnum = struct.unpack_from(order + "HH", data, 42)
            fmt, t, vaddr, memsz, align = "IIIIIIII", 0, 2, 5, 7
        headers = [struct.unpack_from(order + fmt, data, phoff + i * phentsize) for i in range(phnum)]
    except struct.error:
        return not_elf
    found = []
    loads = [h for h in headers if h[t] == PT_LOAD]
    low = [h[align] for h in loads if h[align] < PAGE_16K]
    if low:
        found.append("%s: a LOAD segment is aligned to %d bytes; Google Play needs 16 KB (16384)" % (entry, min(low)))
    for h in headers:
        if h[t] != PT_GNU_RELRO:
            continue
        end = h[vaddr] + h[memsz]
        if end % PAGE_16K == 0:
            continue
        if any(l[vaddr] <= h[vaddr] < l[vaddr] + l[memsz] and l[vaddr] + l[memsz] == end for l in loads):
            continue
        found.append("%s: GNU_RELRO ends at %#x, inside a 16 KB page that also holds writable data" % (entry, end))
    return found


def _allowed(name: str) -> bool:
    return any(name.startswith(a) for a in DEBUG_ONLY_ALLOWED)


def debug_only_hits(dex: dict, mapping_text: str) -> list:
    hits = set()
    for line in mapping_text.splitlines():
        if not line or line[0] in " \t#" or " -> " not in line:
            continue
        original = line.split(" -> ", 1)[0].strip()
        simple = original.rsplit(".", 1)[-1].split("$", 1)[0]
        by_package = original.startswith(DEBUG_ONLY_PACKAGES) and not _allowed(original)
        if by_package or simple in DEBUG_ONLY_NAMES:
            hits.add("%s (R8 mapping)" % original)
    for entry, blob in dex.items():
        allowed = [("L" + a.replace(".", "/")).encode() for a in DEBUG_ONLY_ALLOWED]
        for package in DEBUG_ONLY_PACKAGES:
            needle = ("L" + package.replace(".", "/")).encode()
            start = blob.find(needle)
            while start != -1:
                if not any(blob.startswith(a, start) for a in allowed):
                    hits.add("%s (%s)" % (needle.decode(), entry))
                    break
                start = blob.find(needle, start + 1)
        for name in DEBUG_ONLY_NAMES:
            if name.encode() in blob:
                hits.add("%s (%s)" % (name, entry))
    return sorted(hits)


def lockfile_problems(text: str) -> list:
    found = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("empty="):
            continue
        coordinate, _, configurations = line.partition("=")
        if "releaseRuntimeClasspath" not in configurations.split(","):
            continue
        group_artifact = ":".join(coordinate.split(":")[:2])
        if group_artifact.startswith(FORBIDDEN_SDKS):
            found.append("%s is on the release classpath: ShellX declares no analytics, advertising or crash "
                         "reporting" % coordinate)
    return found


def google_services_app_id(text: str):
    try:
        data = json.loads(text)
    except ValueError:
        return None, ["google-services.json is not valid JSON"]
    if not isinstance(data, dict):
        return None, ["google-services.json is not valid JSON"]
    found = []
    info = data.get("project_info")
    project = info.get("project_id") if isinstance(info, dict) else None
    if project != FIREBASE_PROJECT:
        found.append("google-services.json is for project %s, expected %s" % (project, FIREBASE_PROJECT))
    app_id = None
    for client in data.get("client") or []:
        try:
            if client["client_info"]["android_client_info"]["package_name"] == APPLICATION_ID:
                app_id = client["client_info"]["mobilesdk_app_id"]
                break
        except (KeyError, TypeError):
            continue
    if app_id is None:
        found.append("google-services.json has no client for %s" % APPLICATION_ID)
    return (None if found else app_id), found


def google_web_client_problems(oauth_xml: str, ledger_text):
    try:
        root = ET.fromstring(oauth_xml)
    except ET.ParseError:
        return None, ["google_oauth.xml is not valid XML"]
    value = None
    for node in root.iter("string"):
        if node.get("name") == "google_web_client_id":
            value = (node.text or "").strip()
            break
    if value is None:
        return None, ["google_oauth.xml has no google_web_client_id string"]
    if not CLIENT_ID_RE.match(value):
        return None, ['google_web_client_id is "%s", not a Google OAuth client id: fill it from %s (client "%s", '
                      'plan 1D)' % (value, LEDGER_FILE, LEDGER_CLIENT)]
    if ledger_text is not None:
        for line in ledger_text.splitlines():
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) < 3 or cells[1] != LEDGER_CLIENT:
                continue
            ledger_id = cells[-1].replace("`", "").strip()
            if ledger_id and not ledger_id.startswith("pending") and ledger_id != value:
                return None, ['google_web_client_id %s differs from the Web client id %s in %s (client "%s")'
                              % (value, ledger_id, LEDGER_FILE, LEDGER_CLIENT)]
    return value, []


LICENCE_NAMES = (b"third_party_licenses", b"third_party_license_metadata")   # resource names in resources.pb
LICENCE_ASSET_ENTRY = "base/assets/licenses/third_party_licenses.txt"        # the fallback's file
LICENCE_PLACEHOLDER = b"Debug License Info"


def licence_notice_problems(resources: bytes, res_files: dict, asset) -> list:
    """The bundle must carry open-source licence notices: Google's plugin resources or the bundled asset."""
    if asset:
        return []
    if all(name in resources for name in LICENCE_NAMES):
        for entry in sorted(res_files):
            if LICENCE_PLACEHOLDER in res_files[entry]:
                return ["%s holds the licences plugin's debug placeholder (\"Debug License Info\"): the plugin "
                        "did not see the release dependencies" % entry]
        return []
    return ["the bundle has no open-source licence notices: neither the resources raw/third_party_licenses and "
            "raw/third_party_license_metadata (Google's OSS licences plugin) nor "
            "assets/licenses/third_party_licenses.txt"]


def _read_text(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def _source_checks(args, violations, missing):
    """Firebase file, OAuth file (and ledger), lockfile. Returns (app id, web client id)."""
    def text_of(path):
        if path is None:
            return None
        try:
            return _read_text(path)
        except OSError:
            missing.append(path)
            violations.append("missing %s" % path)
            return None
    app_id = web_id = None
    services = text_of(args.google_services)
    if services is not None:
        app_id, found = google_services_app_id(services)
        violations.extend(found)
    oauth = text_of(args.google_oauth)
    ledger = text_of(args.rollout_ledger)
    if oauth is not None:
        web_id, found = google_web_client_problems(oauth, ledger)
        violations.extend(found)
    lock = text_of(args.lockfile)
    if lock is not None:
        violations.extend(lockfile_problems(lock))
    return app_id, web_id


def _bundle_checks(args, violations, missing, app_id, web_id):
    inputs = {}
    for key, path in (("rules", args.play_rules), ("permissions", args.permissions), ("manifest", args.manifest_xml),
                      ("config", args.bundle_config)):
        try:
            inputs[key] = _read_text(path)
        except OSError:
            missing.append(path)
            violations.append("missing %s" % path)
    mapping_file = None
    if args.mapping is not None:
        try:
            with open(args.mapping, "rb") as f:
                mapping_file = f.read()
        except OSError:
            missing.append(args.mapping)
            violations.append("missing %s" % args.mapping)
    if missing:
        return None
    try:
        today = datetime.date.fromisoformat(args.today)
        required, since = required_target_sdk(inputs["rules"], today)
    except RuleTableError as e:
        violations.append(str(e))
        return None
    manifest = parse_manifest(inputs["manifest"])
    violations.extend(manifest_problems(
        manifest, version_name=args.version_name, version_code=args.version_code,
        catalog_target_sdk=args.catalog_target_sdk, required_sdk=required, required_since=since,
        permissions=read_permission_list(inputs["permissions"])))
    try:
        z = zipfile.ZipFile(args.aab)
        names = z.namelist()
    except (zipfile.BadZipFile, OSError):
        violations.append("%s is not an app bundle" % args.aab)
        return None
    with z:
        dex = {n: z.read(n) for n in names if re.match(r"^[^/]+/dex/classes\d*\.dex$", n)}
        if not dex:
            violations.append("the bundle has no dex files (base/dex/classes*.dex)")
        libraries = [n for n in names if re.match(r"^[^/]+/lib/[^/]+/[^/]+\.so$", n)]
        for n in libraries:
            violations.extend(elf_problems(n, z.read(n)))
        if libraries:
            m = re.search(r'"alignment"\s*:\s*"([A-Za-z0-9_]+)"', inputs["config"])
            if not m or m.group(1) not in ("PAGE_ALIGNMENT_16K", "PAGE_ALIGNMENT_64K"):
                violations.append("the bundle has native libraries but its config asks for %s zip alignment; it "
                                  "must ask for PAGE_ALIGNMENT_16K (Android Gradle plugin 8.5.1 or later)"
                                  % (m.group(1) if m else "no"))
        embedded = z.read(MAPPING_ENTRY) if MAPPING_ENTRY in names else None
        if embedded is None:
            violations.append("the bundle has no R8 mapping (%s)" % MAPPING_ENTRY)
        if mapping_file is not None:
            if not mapping_file:
                violations.append("%s is empty (did R8 run?)" % args.mapping)
            elif embedded is not None and embedded != mapping_file:
                violations.append("the bundle's R8 mapping differs from %s" % args.mapping)
        scanned = mapping_file if mapping_file is not None else embedded
        hits = debug_only_hits(dex, scanned.decode("utf-8", "replace") if scanned else "")
        if hits:
            violations.append("release contains debug-only code: %s" % ", ".join(hits))
        resources = b"".join(z.read(n) for n in names if re.match(r"^[^/]+/resources\.pb$", n))
        res_files = {n: z.read(n) for n in names if re.match(r"^base/res/", n) and not n.endswith("/")}
        licence_asset = z.read(LICENCE_ASSET_ENTRY) if LICENCE_ASSET_ENTRY in names else None
    if app_id and app_id.encode() not in resources:
        violations.append("the bundle's resources do not hold the Firebase app id %s (the google-services plugin "
                          "did not run for release)" % app_id)
    if web_id and web_id.encode() not in resources:
        violations.append("the bundle's resources do not hold google_web_client_id %s" % web_id)
    if b"ic_google_g" not in resources:
        violations.append('the bundle\'s resources do not hold Google\'s "G" (drawable/ic_google_g): plan 3D Task 9 '
                          'Steps 7\u20139 (USER) are not done, or the resource shrinker dropped it '
                          '(res/raw/keep_google_branding.xml)')
    violations.extend(licence_notice_problems(resources, res_files, licence_asset))
    native = "%d libraries 16 KB aligned" % len(libraries) if libraries else "none"
    return ("bundle checks passed: %s %s (%s), target SDK %s (Google Play needs %d since %s), %d permissions, "
            "native code: %s, R8 mapping %d bytes"
            % (manifest.package, manifest.version_name, manifest.version_code, manifest.target_sdk, required,
               since.isoformat(), len(manifest.permissions), native, len(embedded or b"")))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="check_android_bundle.py", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("sources", "bundle"):
        p = sub.add_parser(name)
        p.add_argument("--google-services", required=True)
        p.add_argument("--google-oauth", required=True)
        p.add_argument("--rollout-ledger")
        p.add_argument("--lockfile")
        if name == "bundle":
            p.add_argument("--mapping")
            for flag in ("aab", "manifest-xml", "bundle-config", "version-name", "version-code",
                         "catalog-target-sdk", "play-rules", "permissions", "today"):
                p.add_argument("--" + flag, required=True)
    args = parser.parse_args(argv)
    violations, missing = [], []
    app_id, web_id = _source_checks(args, violations, missing)
    summary = None
    if args.command == "bundle":
        summary = _bundle_checks(args, violations, missing, app_id, web_id)
    else:
        summary = "source checks passed: Firebase app %s, Google web client %s" % (app_id, web_id)
    if violations:
        for v in violations:
            print("violation: %s" % v)
        return 1
    print(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
