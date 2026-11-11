#!/usr/bin/env bash
# Runs inside shellx-winbuild (windows/cross/Dockerfile). /src is the repo export with
# the ghostty submodule filled in, /out receives the installer, /cache is the
# shellx-winbuild-cargo volume. Mirrors the app + installer jobs of
# .github/workflows/shellx-windows.yml as far as a Linux host allows.
set -euo pipefail

TARGET=x86_64-pc-windows-msvc
export CARGO_TARGET_DIR=/cache/target
export ZIG_LOCAL_CACHE_DIR=/cache/zig-local
export PYTHONDONTWRITEBYTECODE=1
# The container runs as root; hand /src (zig-pkg, anything else written there) and /out
# back to the host user on every exit so the next run can replace them.
if [[ -n "${HOST_UID:-}" ]]; then
  trap 'chown -R "$HOST_UID:${HOST_GID:-$HOST_UID}" /src /out 2>/dev/null || true' EXIT
fi
unset CMUX_GHOSTTY_SRC
cd /src/windows
# /src is a git archive, so cmux-remote's build.rs cannot ask git for HEAD: the driver passes
# the exported commit (what a clean checkout reports).
[[ "${CMUX_TUI_BUILD_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || { echo "set CMUX_TUI_BUILD_COMMIT to the exported commit" >&2; exit 1; }

# zig needs ZIG_LIBC to find the CRT + SDK that cargo-xwin downloads.
# shellcheck source=zig-libc-msvc.sh
source /opt/winbuild/zig-libc-msvc.sh

version="$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"$/\1/p' Cargo.toml)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "cannot read the workspace version: '$version'" >&2; exit 1; }
echo "== ShellX for Windows $version"
rustc --version; cargo-xwin --version; zig version

step() { echo; echo "== $*"; }

step "fetch crates (locked)"
cargo fetch --locked

step "test shellx-model (Linux host, as the CI model job)"
cargo test --locked -p shellx-model
python3 -I -m unittest discover -s /src/windows/installer -v

step "build shellx-desktop.exe ($TARGET)"
cargo xwin build --release --locked -p shellx-app --target "$TARGET"

step "build shellx-remote ($TARGET)"
cargo xwin build --release --locked -p shellx-remote --target "$TARGET"

exe="$CARGO_TARGET_DIR/$TARGET/release/shellx-desktop.exe"
stage=/work/staged
rm -rf "$stage" /work/dist
mkdir -p "$stage" /work/dist
cp "$exe" "$stage/"
find "$CARGO_TARGET_DIR/$TARGET/release" -maxdepth 1 -name '*.dll' -exec cp {} "$stage/" \;

step "imports (static CRT check)"
llvm-readobj --coff-imports "$stage/shellx-desktop.exe" | sed -n 's/^ *Name: \(.*\.dll\)$/\1/Ip' | sort -u | tee /work/dependents.log
grep -qi '^KERNEL32' /work/dependents.log || { echo "no imports listed" >&2; exit 1; }
if grep -iE 'VCRUNTIME140|MSVCP140|api-ms-win-crt' /work/dependents.log; then
  echo "shellx-desktop.exe imports the dynamic VC++ runtime" >&2
  exit 1
fi

step "installer (Inno Setup under wine)"
win() { echo "Z:${1//\//\\}"; }
iscc_log=/work/iscc.log
set +e
xvfb-run -a wine "C:\\InnoSetup\\ISCC.exe" \
  "/DAppVersion=$version" \
  "/DSourceDir=$(win "$stage")" \
  "/DOutputDir=$(win /work/dist)" \
  "/DAppIcon=$(win /src/windows/shellx-app/resources/app_icon.ico)" \
  "$(win /src/windows/installer/shellx-native.iss)" >"$iscc_log" 2>&1
code=$?
set -e
tr -d '\r' <"$iscc_log" | tail -n 25
[[ $code -eq 0 ]] || { echo "ISCC failed with exit code $code" >&2; exit 1; }
setup="/work/dist/ShellX-Setup-$version.exe"
[[ -f "$setup" ]] || { echo "ISCC did not produce $setup" >&2; exit 1; }

python3 -I /src/windows/installer/check_coexistence.py

cp "$setup" "$stage/shellx-desktop.exe" /out/
cp /work/dependents.log /out/
(cd /out && sha256sum "ShellX-Setup-$version.exe" shellx-desktop.exe | tee SHA256SUMS)
echo "== done: /out/ShellX-Setup-$version.exe"
