#!/usr/bin/env bash
# Builds ShellX-Setup-<version>.exe for Windows without a Windows machine or GitHub Actions:
# cross-compiles x86_64-pc-windows-msvc in a Docker container on the ShellX VPS
# (windows/cross/Dockerfile) and downloads the unsigned installer to this Mac.
#
#   scripts/shellx/release/build-windows-cross.sh [OUT_DIR]
#   scripts/shellx/release/build-windows-cross.sh --preflight
#
# Builds the committed HEAD (git archive), not the working tree. The ghostty submodule is
# fetched on the VPS at the commit HEAD pins. Env:
#   SHELLX_VPS          ssh destination        (default higio@42.115.41.70)
#   SHELLX_VPS_SSH_OPTS extra ssh options      (default -S ~/.ssh/cm-shellx-vps, the ControlMaster;
#                                               set but empty means no options)
#   SHELLX_WINBUILD_DIR build dir on the VPS   (default phu/shellx/.winbuild, relative to ~)
#   SHELLX_WINBUILD_TAG docker image tag       (default the windows/cross tree hash)
#   SHELLX_WINBUILD_KEEP_TARGET=1 keep the cargo target dir in the cache volume
#   SHELLX_WINBUILD_MIN_FREE_GIB  free GiB the VPS needs in ~ to start (default 14: 4 stay free
#                                 for deploys, up to 10 for the image, caches and target)
#
# The VPS is shared with a production service. Guards (the preflight), checked before every
# build and alone with --preflight (exit 0 = a build may start, 1 = it must not):
# - at least SHELLX_WINBUILD_MIN_FREE_GIB GiB free in the build user's home;
# - one Windows build at a time: every run is the container shellx-winbuild-run, and none
#   may already be running.
# After a build, when the free space is under the minimum, older shellx-winbuild image tags
# are removed (only those; never other images, never a prune).
#
# Differences from the CI build (.github/workflows/shellx-windows.yml, windows-2025):
# - clang-cl/lld-link 18 + llvm-rc against the MSVC CRT and Windows SDK that cargo-xwin
#   downloads (xwin), not cl.exe/link.exe/rc.exe from Visual Studio.
# - gpui 0.2.2's build.rs only compiles its HLSL on a Windows host; the container patches
#   it (windows/cross/patch-gpui-build-rs.py) and runs the SDK's fxc.exe under wine.
# - Tests: shellx-model and the installer unittests run on the Linux host (as the CI model
#   job). The Windows-target tests, the --smoke/--version runs and the install/uninstall
#   smoke of the CI app/installer jobs do NOT run here; smoke the installer on a Windows PC.
# - Same as CI: Rust from cmux-tui/rust-toolchain.toml, zig from ghostty/build.zig.zon,
#   --locked, static CRT (checked), Inno Setup 6.7.1, unsigned.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$repo"
vps="${SHELLX_VPS:-higio@42.115.41.70}"
# No colon: an explicitly empty SHELLX_VPS_SSH_OPTS means no options.
read -r -a ssh_opts <<< "${SHELLX_VPS_SSH_OPTS-"-S $HOME/.ssh/cm-shellx-vps"}"
min_free="${SHELLX_WINBUILD_MIN_FREE_GIB:-14}"
[[ "$min_free" =~ ^[0-9]+$ ]] || { echo "SHELLX_WINBUILD_MIN_FREE_GIB must be a whole number of GiB: '$min_free'" >&2; exit 1; }

vssh() { ssh ${ssh_opts[@]+"${ssh_opts[@]}"} "$vps" "$@"; }
vps_free_gib() { vssh "df -Pk ~ | awk 'NR==2 {print int(\$4/1048576)}'"; }
preflight() {
  local free running
  free="$(vps_free_gib)"
  [[ "$free" =~ ^[0-9]+$ ]] || { echo "cannot read the free disk space on the VPS: '$free'" >&2; exit 1; }
  if (( free < min_free )); then
    echo "VPS has $free GiB free in ~; a Windows build needs $min_free (4 stay free for deploys)" >&2
    exit 1
  fi
  running="$(vssh "docker ps -q -f 'name=^shellx-winbuild-run\$'")"
  if [[ -n "$running" ]]; then
    echo "another Windows build is running on the VPS" >&2
    exit 1
  fi
  echo "preflight: $free GiB free, no Windows build running"
}
if [[ "${1:-}" == --preflight ]]; then
  preflight
  exit 0
fi

# The sign-in button needs Google's official mark in the commit being built.
branding_args=()
[[ -z "${SHELLX_GOOGLE_BRANDING_ROOT:-}" ]] || branding_args=(--root "$SHELLX_GOOGLE_BRANDING_ROOT")
python3 scripts/shellx/check-google-branding.py --git-rev HEAD ${branding_args[@]+"${branding_args[@]}"} >&2 || exit 1
out_dir="${1:-$repo/dist/windows}"
remote="${SHELLX_WINBUILD_DIR:-phu/shellx/.winbuild}"
volume=shellx-winbuild-cargo

version="$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"$/\1/p' windows/Cargo.toml)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "cannot read windows/Cargo.toml version: '$version'" >&2; exit 1; }
commit="$(git rev-parse HEAD)"
ghostty_sha="$(git ls-tree HEAD ghostty | awk '$2 == "commit" {print $3}')"
[[ -n "$ghostty_sha" ]] || { echo "HEAD has no ghostty submodule entry" >&2; exit 1; }
ghostty_url="$(git config -f .gitmodules submodule.ghostty.url)"
tag="${SHELLX_WINBUILD_TAG:-$(git rev-parse --short=12 HEAD:windows/cross)}"
image="shellx-winbuild:$tag"
if [[ -n "$(git status --porcelain -- windows cmux-tui shellx-core)" ]]; then
  echo "warning: uncommitted changes under windows/, cmux-tui/ or shellx-core/ are NOT built" >&2
fi
echo "ShellX for Windows $version from $commit (ghostty $ghostty_sha), image $image"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

preflight

# 1. Image (cached by docker; the tag is the windows/cross tree hash).
git archive --format=tar.gz -o "$tmp/cross.tgz" HEAD:windows/cross
vssh "mkdir -p ~/$remote && cat > ~/$remote/cross.tgz" < "$tmp/cross.tgz"
vssh "set -euo pipefail
  cd ~/$remote
  rm -rf cross
  mkdir cross
  tar -C cross -xzf cross.tgz
  cd cross
  docker build -q -t $image . >/dev/null
  echo image $image ready"

# 2. Sources: the three trees the windows workspace needs, plus the pinned ghostty.
git archive --format=tar.gz -o "$tmp/src.tgz" HEAD windows cmux-tui shellx-core
vssh "cat > ~/$remote/src.tgz" < "$tmp/src.tgz"
vssh "set -euo pipefail
  cd ~/$remote
  mkdir -p src out
  # A run killed before its exit trap can leave root-owned files behind.
  docker run --rm --name shellx-winbuild-run -v \$PWD/src:/src -v \$PWD/out:/out $image chown -R \$(id -u):\$(id -g) /src /out
  cd src
  rm -rf windows cmux-tui shellx-core
  # Fresh modification times: git archive stamps the commit time, which can make the kept
  # cargo cache skip a changed file.
  tar -xmzf ../src.tgz
  if [[ \"\$(git -C ghostty rev-parse HEAD 2>/dev/null)\" != $ghostty_sha ]]; then
    rm -rf ghostty
    mkdir ghostty
    cd ghostty
    git init -q
    git remote add origin $ghostty_url
    git fetch -q --depth 1 origin $ghostty_sha
    git checkout -q FETCH_HEAD
  fi"

# 3. Build, host tests, installer.
vssh "set -euo pipefail
  cd ~/$remote
  rm -rf out
  mkdir out
  docker volume create $volume >/dev/null
  docker run --rm --cpus 4 --memory 10g --name shellx-winbuild-run \
    -e HOST_UID=\$(id -u) -e HOST_GID=\$(id -g) -e CMUX_TUI_BUILD_COMMIT=$commit \
    -v $volume:/cache -v \$PWD/src:/src -v \$PWD/out:/out \
    $image bash /opt/winbuild/build-in-container.sh 2>&1 | tee build.log \
    | grep -E '^(==|error)|^test .* FAILED|test result|Successful compile' || true
  test -f out/ShellX-Setup-$version.exe || { tail -60 build.log; exit 1; }"

# 4. Download.
mkdir -p "$out_dir"
vssh "cat ~/$remote/out/ShellX-Setup-$version.exe" > "$out_dir/ShellX-Setup-$version.exe"
vssh "cat ~/$remote/out/SHA256SUMS" > "$out_dir/SHA256SUMS.remote"
(cd "$out_dir" && shasum -a 256 "ShellX-Setup-$version.exe" | tee "ShellX-Setup-$version.exe.sha256")
grep -q "$(cut -d' ' -f1 "$out_dir/ShellX-Setup-$version.exe.sha256")" "$out_dir/SHA256SUMS.remote" \
  || { echo "checksum mismatch after download" >&2; exit 1; }

# 5. Free the big intermediates; keep the registry, xwin and zig caches for the next run.
if [[ "${SHELLX_WINBUILD_KEEP_TARGET:-0}" != 1 ]]; then
  vssh "docker run --rm --name shellx-winbuild-run -v $volume:/cache $image rm -rf /cache/target /cache/zig-local"
fi

# 6. Disk: when under the minimum, remove older shellx-winbuild image tags (only those).
free_after="$(vps_free_gib </dev/null || true)"
echo "VPS: ${free_after:-?} GiB free after the build"
if [[ "$free_after" =~ ^[0-9]+$ ]] && (( free_after < min_free )); then
  old_tags=()
  while IFS= read -r t; do
    [[ -z "$t" || "$t" == "<none>" || "$t" == "$tag" ]] || old_tags+=("$t")
  done < <(vssh "docker images shellx-winbuild --format '{{.Tag}}'" </dev/null)
  for t in ${old_tags[@]+"${old_tags[@]}"}; do
    echo "removing image shellx-winbuild:$t"
    vssh "docker image rm shellx-winbuild:$t" </dev/null >/dev/null \
      || echo "warning: could not remove shellx-winbuild:$t" >&2
  done
  echo "VPS: $(vps_free_gib </dev/null) GiB free"
fi
echo "Built $out_dir/ShellX-Setup-$version.exe (unsigned)"
