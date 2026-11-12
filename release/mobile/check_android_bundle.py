#!/usr/bin/env python3
"""Checks of the ShellX Android release bundle (plan 3H): manifest, Google Play's target API rule, permissions.

Standard library only (Python 3.9). Run with `python3 -I`.
"""
from __future__ import annotations

import datetime
import xml.etree.ElementTree as ET
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
