#!/usr/bin/env python3
"""Let gpui 0.2.2's build script compile its HLSL shaders when the build HOST is not Windows.

gpui's build.rs gates `windows::build()` (fxc -> OUT_DIR/shaders_bytes.rs) on
`#[cfg(target_os = "windows")]`, which is the host's cfg for a build script. On a Linux
host the shaders are never compiled and the release build fails at
`include!(concat!(env!("OUT_DIR"), "/shaders_bytes.rs"))`. The match on
CARGO_CFG_TARGET_OS already selects the target, so both cfg gates are dropped.

Edits the unpacked crate under $CARGO_HOME/registry/src in place (the container's own
CARGO_HOME, never a developer's). Cargo.lock and --locked are unaffected. Idempotent.
"""
import glob
import os
import sys

MARK = "// shellx-cross: host cfg gates removed\n"
OLD_CALL = '        Ok("windows") => {\n            #[cfg(target_os = "windows")]\n            windows::build();\n'
NEW_CALL = '        Ok("windows") => {\n            windows::build();\n'
OLD_MOD = '#[cfg(target_os = "windows")]\nmod windows {\n'
NEW_MOD = "mod windows {\n"


def main() -> int:
    cargo_home = os.environ.get("CARGO_HOME") or os.path.expanduser("~/.cargo")
    paths = glob.glob(os.path.join(cargo_home, "registry/src/*/gpui-0.2.2/build.rs"))
    if not paths:
        print("patch-gpui: gpui-0.2.2 not unpacked; run cargo fetch first", file=sys.stderr)
        return 1
    for path in paths:
        with open(path, encoding="utf-8") as f:
            src = f.read()
        if src.startswith(MARK):
            print(f"patch-gpui: already patched {path}")
            continue
        if src.count(OLD_CALL) != 1 or src.count(OLD_MOD) != 1:
            print(f"patch-gpui: unexpected build.rs layout in {path}", file=sys.stderr)
            return 1
        src = MARK + src.replace(OLD_CALL, NEW_CALL).replace(OLD_MOD, NEW_MOD)
        with open(path, "w", encoding="utf-8") as f:
            f.write(src)
        print(f"patch-gpui: patched {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
