#!/usr/bin/env python3
"""List (or download) Windows SDK payloads from the Visual Studio 17 release manifest.

usage: vsmanifest.py list <regex>          print matching SDK payload file names
       vsmanifest.py get <outdir> <regex>  download matching payloads (sha256-checked)
"""
import hashlib
import json
import os
import re
import sys
import urllib.request

CHANNEL = "https://aka.ms/vs/17/release/channel"
CACHE = os.environ.get("VSMANIFEST_CACHE", "vsmanifest.json")


def fetch_json(url):
    with urllib.request.urlopen(url, timeout=120) as r:
        return json.load(r)


def manifest():
    if os.path.exists(CACHE):
        with open(CACHE) as f:
            return json.load(f)
    ch = fetch_json(CHANNEL)
    item = next(i for i in ch["channelItems"] if i.get("id") == "Microsoft.VisualStudio.Manifests.VisualStudio")
    m = fetch_json(item["payloads"][0]["url"])
    with open(CACHE, "w") as f:
        json.dump(m, f)
    return m


def sdk_payloads(m):
    pkgs = [p for p in m["packages"] if re.match(r"^Win1[01]SDK_10\.0\.\d+$", p.get("id", ""))]
    pkgs.sort(key=lambda p: int(p["id"].rsplit(".", 1)[1]))
    pkg = pkgs[-1]
    return pkg["id"], pkg.get("payloads", [])


def matches(rx, file_name):
    """The callers' regexes name a payload behind a backslash ("\\\\<cab>$"); the manifest has
    used both "\\" and "/" as its separator, so match against the backslash form."""
    return rx.search(file_name.replace("/", "\\"))


def main():
    m = manifest()
    pid, payloads = sdk_payloads(m)
    mode = sys.argv[1]
    if mode == "list":
        rx = re.compile(sys.argv[2], re.I)
        print(pid)
        for p in payloads:
            if matches(rx, p["fileName"]):
                print(p["fileName"], p.get("size"))
    elif mode == "get":
        out, rx = sys.argv[2], re.compile(sys.argv[3], re.I)
        os.makedirs(out, exist_ok=True)
        for p in payloads:
            name = p["fileName"].replace("\\", "/").rsplit("/", 1)[-1]
            if not matches(rx, p["fileName"]):
                continue
            dst = os.path.join(out, name)
            if not os.path.exists(dst):
                urllib.request.urlretrieve(p["url"], dst)
            h = hashlib.sha256(open(dst, "rb").read()).hexdigest()
            if h.lower() != p["sha256"].lower():
                sys.exit(f"sha256 mismatch for {name}")
            print("ok", name)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
