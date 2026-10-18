#!/usr/bin/env python3
"""Static check that shellx-native.iss coexists with the Flutter ShellX installer.

The Flutter values are hard-coded from tag `flutter-final`
(`git show flutter-final:release/windows/shellx.iss`). Stdlib only.
Usage: check_coexistence.py [path/to/shellx-native.iss]; exit 1 on any problem.
"""
import os
import re
import sys

FLUTTER_APP_ID = "{6A3A45BD-0A27-407A-A1FF-3C8D1BE226EE}"
FLUTTER_APP_NAME = "ShellX"
FLUTTER_EXE = "ShellX.exe"
FLUTTER_DIR = r"{autopf}\ShellX"
FLUTTER_GROUP = "ShellX"
FLUTTER_SHORTCUTS = {r"{autoprograms}\ShellX", r"{autodesktop}\ShellX"}
FLUTTER_KILLED = ("shellx.exe", "shellx-mux.exe")
ALLOWED_DELETE = r"{localappdata}\shellx\native"


def parse(text):
    defines, sections, section = {}, {}, None
    for raw in text.splitlines():
        line = raw.strip()
        m = re.match(r'#define\s+(\w+)\s+"([^"]*)"', line)
        if m:
            defines[m.group(1)] = m.group(2)
            continue
        m = re.match(r"\[(\w+)\]$", line)
        if m:
            section = m.group(1).lower()
            sections.setdefault(section, [])
            continue
        if section and line and not line.startswith(";") and not line.startswith("#"):
            sections[section].append(line)
    return defines, sections


def resolve(value, defines):
    return re.sub(r"\{#(\w+)\}", lambda m: defines.get(m.group(1), m.group(0)), value)


def check(text):
    """Return a list of problems (empty when the script coexists)."""
    defines, sections = parse(text)
    problems = []
    setup = {}
    for line in sections.get("setup", []):
        k, _, v = line.partition("=")
        setup[k.strip()] = resolve(v.strip(), defines)

    def need(key):
        if key not in setup:
            problems.append("[Setup] %s is missing" % key)
        return setup.get(key, "")

    app_id = need("AppId").replace("{{", "{")
    if app_id.lower() == FLUTTER_APP_ID.lower():
        problems.append("AppId equals the Flutter AppId")
    if need("AppName").lower() == FLUTTER_APP_NAME.lower():
        problems.append("AppName equals the Flutter AppName")
    if need("DefaultDirName").lower() == FLUTTER_DIR.lower():
        problems.append("DefaultDirName equals the Flutter install dir")
    if need("DefaultGroupName").lower() == FLUTTER_GROUP.lower():
        problems.append("DefaultGroupName equals the Flutter group")
    exe = defines.get("AppExeName", "")
    if not exe:
        problems.append("AppExeName is not defined")
    if exe.lower() == FLUTTER_EXE.lower():
        problems.append("exe name equals the Flutter exe")
    for line in sections.get("icons", []):
        m = re.search(r'Name:\s*"([^"]*)"', line)
        if m:
            name = resolve(m.group(1), defines)
            if name.lower() in {s.lower() for s in FLUTTER_SHORTCUTS}:
                problems.append("shortcut %s equals a Flutter shortcut" % name)
            if name.rstrip("\\").lower().endswith("\\shellx"):
                problems.append("shortcut %s is named like the Flutter app" % name)

    for raw in text.splitlines():
        low = resolve(raw, defines).lower()
        if "taskkill" in low and any(k in low for k in FLUTTER_KILLED):
            problems.append("taskkill of a Flutter process: %s" % raw.strip())

    for sec in ("installdelete", "uninstalldelete"):
        for line in sections.get(sec, []):
            m = re.search(r'Name:\s*"([^"]*)"', line)
            target = resolve(m.group(1), defines).lower() if m else line.lower()
            if target.startswith("{app}"):
                continue
            if target.startswith(r"{userappdata}\pro.shellx"):
                problems.append("[%s] touches the Flutter data dir: %s" % (sec, line))
            elif target.startswith(r"{localappdata}\shellx"):
                if not (target == ALLOWED_DELETE or target.startswith(ALLOWED_DELETE + "\\")):
                    problems.append("[%s] touches Flutter data: %s" % (sec, line))
    return problems


def main(argv):
    path = argv[1] if len(argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "shellx-native.iss")
    with open(path, encoding="utf-8") as f:
        problems = check(f.read())
    for p in problems:
        print("FAIL:", p)
    if problems:
        return 1
    print("installer_coexists_with_flutter: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
