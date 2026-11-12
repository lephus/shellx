#!/usr/bin/env bash
# Builds ShellX-Setup-<version>.exe for Windows without a Windows machine or GitHub Actions:
# cross-compiles x86_64-pc-windows-msvc in a Docker container on the ShellX VPS
# (windows/cross/Dockerfile) and downloads the unsigned installer to this Mac.
#
#   scripts/shellx/release/build-windows-cross.sh [OUT_DIR]
#   scripts/shellx/release/build-windows-cross.sh --preflight
#   scripts/shellx/release/build-windows-cross.sh --unlock
#   scripts/shellx/release/build-windows-cross.sh -h | --help
# Any other argument that starts with "-", or more than one argument, prints the usage (exit 2)
# before anything reaches the VPS.
#
# Builds the committed HEAD (git archive), not the working tree. The ghostty submodule is
# fetched on the VPS at the commit HEAD pins. Env:
#   SHELLX_VPS          ssh destination        (default higio@42.115.41.70)
#   SHELLX_VPS_SSH_OPTS extra ssh options      (default -S ~/.ssh/cm-shellx-vps, the ControlMaster;
#                                               set but empty means no options)
#   SHELLX_WINBUILD_DIR build dir on the VPS   (default phu/shellx/.winbuild, relative to ~; not empty,
#                                               no "." or ".." part, no leading "/", only A-Z a-z 0-9 . _ - /)
#   SHELLX_WINBUILD_TAG docker image tag       (default the windows/cross tree hash)
#   SHELLX_WINBUILD_KEEP_TARGET=1 keep the cargo target dir in the cache volume
#   SHELLX_WINBUILD_MIN_FREE_GIB  free GiB the VPS needs in ~ to start (default 14: 4 stay free
#                                 for deploys, up to 10 for the image, caches and target)
#   SHELLX_BUILD_LABEL  a test label (a lower-case letter, then up to 9 lower-case letters or
#                       digits): the installer becomes ShellX-Setup-<version>-<label>-<commit10>.exe
#                       and About and reports show "ShellX <version> (<label> <commit10>)"; the
#                       version inside the app and the installer stays <version> (Ruling 25)
#
# Output in OUT_DIR: the installer, its .sha256 and SHA256SUMS.remote, and a folder
# <installer name without .exe>-symbols holding shellx-desktop.exe and shellx_desktop.pdb of the
# same build (to map a crash file's addresses later, Ruling 11), each checked against the
# remote sums. The PDB is never in the installer. A failed symbols download is a warning; the
# last line names what the folder holds.
#
# The VPS is shared with a production service. Guards (the preflight), checked before every
# build and alone with --preflight (read-only; exit 0 = a build may start, 1 = it must not):
# - at least SHELLX_WINBUILD_MIN_FREE_GIB GiB free in the build user's home;
# - one Windows build at a time: no build holds the lock ~/<build dir>/.lock, and no container
#   shellx-winbuild-run (the name of every container a run starts) is running.
# A build takes the lock (an atomic mkdir) before it changes anything on the VPS and writes its
# owner line into .lock/owner: "<host> pid <pid> <UTC start> <commit>". Every refusal because of
# a held lock prints that line. On exit (also after a failed step or Ctrl-C) a run removes the
# lock only while the owner line is still its own; otherwise it leaves it and says so.
# A lock left by a lost connection makes the next run refuse. --unlock prints the owner line and
# removes the lock unless a shellx-winbuild-run container is running or the owner is a live pid
# on this host. A run that is still uploading from another machine has no container yet, so use
# --unlock only when the owner shown is no longer running.
# After a build, when the free space is under the minimum, older shellx-winbuild image tags
# are removed (only those; never other images, never a prune).
#
# Differences from the CI build (.github/workflows/shellx-windows.yml, windows-2025):
# - clang-cl/lld-link 18 + llvm-rc against the MSVC CRT and Windows SDK that cargo-xwin
#   downloads (xwin), not cl.exe/link.exe/rc.exe from Visual Studio.
# - The vendored gpui 0.2.2 (windows/vendor, patch (d)) compiles its HLSL for a Windows
#   target on any build host; the container runs the SDK's fxc.exe under wine.
# - Tests: shellx-model and the installer unittests run on the Linux host (as the CI model
#   job). The Windows-target tests, the --smoke/--version runs and the install/uninstall
#   smoke of the CI app/installer jobs do NOT run here; smoke the installer on a Windows PC.
# - Same as CI: Rust from cmux-tui/rust-toolchain.toml, zig from ghostty/build.zig.zon,
#   --locked, static CRT (checked), Inno Setup 6.7.1, unsigned.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: scripts/shellx/release/build-windows-cross.sh [OUT_DIR]    build the installer on the VPS (OUT_DIR: dist/windows)
       scripts/shellx/release/build-windows-cross.sh --preflight  check the VPS guards only (read-only)
       scripts/shellx/release/build-windows-cross.sh --unlock     remove a stale build lock (refused while a build runs)
SHELLX_WINBUILD_DIR (default phu/shellx/.winbuild) is a relative path below ~ on the VPS: not empty,
no "." or ".." part, no leading "/", only A-Z a-z 0-9 . _ - /.
EOF
}
# A mistyped option must not become OUT_DIR and start a build on the shared VPS.
mode=build
if [[ $# -gt 1 ]]; then
  usage >&2; exit 2
fi
case "${1:-}" in
  --preflight) mode=preflight ;;
  --unlock) mode=unlock ;;
  -h|--help) usage; exit 0 ;;
  -*) usage >&2; exit 2 ;;
esac

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$repo"
vps="${SHELLX_VPS:-higio@42.115.41.70}"
# No colon: an explicitly empty SHELLX_VPS_SSH_OPTS means no options.
read -r -a ssh_opts <<< "${SHELLX_VPS_SSH_OPTS-"-S $HOME/.ssh/cm-shellx-vps"}"
min_free="${SHELLX_WINBUILD_MIN_FREE_GIB:-14}"
[[ "$min_free" =~ ^[0-9]+$ ]] || { echo "SHELLX_WINBUILD_MIN_FREE_GIB must be a whole number of GiB: '$min_free'" >&2; exit 1; }
# The build dir goes unquoted into remote commands (~/$remote, its rm -rf, the lock's mkdir and
# rmdir): only a plain relative path below ~ is accepted.
remote="${SHELLX_WINBUILD_DIR-phu/shellx/.winbuild}"
remote_ok=1
[[ -n "$remote" && "$remote" != /* && "$remote" != *..* && "$remote" =~ ^[A-Za-z0-9._/-]+$ ]] || remote_ok=0
IFS=/ read -r -a remote_parts <<< "$remote"
for part in ${remote_parts[@]+"${remote_parts[@]}"}; do
  [[ -n "$part" && "$part" != . ]] || remote_ok=0
done
if [[ $remote_ok -ne 1 ]]; then
  echo "SHELLX_WINBUILD_DIR must be a relative path below ~ on the VPS (not empty, no '.' or '..' part," \
    "no leading '/', only A-Z a-z 0-9 . _ - /): '$remote'" >&2
  exit 2
fi
lock="~/$remote/.lock"
# The owner line names this host; only A-Z a-z 0-9 . _ - survive, so it can be single-quoted remotely.
this_host="$(hostname -s 2>/dev/null || hostname)"
this_host="${this_host//[^A-Za-z0-9._-]/_}"
owner_re='^[A-Za-z0-9._: -]+$'

vssh() { ssh ${ssh_opts[@]+"${ssh_opts[@]}"} "$vps" "$@"; }
vps_free_gib() { vssh "df -Pk ~ | awk 'NR==2 {print int(\$4/1048576)}'"; }
# A failure to ask docker is a refusal (exit 1), never "no build running".
vps_build_running() {
  local out
  out="$(vssh "docker ps -q -f 'name=^shellx-winbuild-run\$'")" \
    || { echo "cannot ask docker on the VPS whether a build is running" >&2; exit 1; }
  [[ -n "$out" ]]
}
# Read-only. Sets lock_state (held or free) and lock_owner (its owner line, empty if none).
read_lock() {
  local out
  out="$(vssh "if [ -e $lock ]; then echo held; cat $lock/owner 2>/dev/null || true; else echo free; fi")"
  lock_state="$(printf '%s\n' "$out" | sed -n 1p)"
  lock_owner="$(printf '%s\n' "$out" | sed -n 2p)"
  case "$lock_state" in
    held|free) ;;
    *) echo "cannot read the build lock on the VPS: '$out'" >&2; exit 1 ;;
  esac
}
refuse_held() {
  echo "another Windows build holds the lock $lock on the VPS" >&2
  echo "  owner: ${1:-(no owner recorded)}" >&2
  echo "  use scripts/shellx/release/build-windows-cross.sh --unlock only when that run is no longer running" >&2
  exit 1
}
# Read-only: never creates or removes the lock.
preflight() {
  local free
  free="$(vps_free_gib)"
  [[ "$free" =~ ^[0-9]+$ ]] || { echo "cannot read the free disk space on the VPS: '$free'" >&2; exit 1; }
  if (( free < min_free )); then
    echo "VPS has $free GiB free in ~; a Windows build needs $min_free (4 stay free for deploys)" >&2
    exit 1
  fi
  read_lock
  [[ $lock_state == free ]] || refuse_held "$lock_owner"
  if vps_build_running; then
    echo "another Windows build is running on the VPS" >&2
    exit 1
  fi
  echo "preflight: $free GiB free, no Windows build running"
}
unlock() {
  local o_host o_word o_pid o_rest result
  read_lock
  if [[ $lock_state == free ]]; then
    echo "no build lock $lock on the VPS"
    return 0
  fi
  if [[ -n "$lock_owner" ]]; then
    echo "build lock $lock, owner: $lock_owner"
  else
    echo "build lock $lock has no owner file (a run stopped while taking it, or an older script took it)"
  fi
  if vps_build_running; then
    echo "a Windows build is running on the VPS (container shellx-winbuild-run); the lock stays" >&2
    exit 1
  fi
  if [[ -n "$lock_owner" ]]; then
    [[ "$lock_owner" =~ $owner_re ]] || { echo "unexpected owner line; check the VPS by hand: '$lock_owner'" >&2; exit 1; }
    read -r o_host o_word o_pid o_rest <<< "$lock_owner"
    if [[ "$o_host" == "$this_host" && "$o_word" == pid && "$o_pid" =~ ^[0-9]+$ ]] && kill -0 "$o_pid" 2>/dev/null; then
      echo "the owner, pid $o_pid on this Mac, is still running; the lock stays" >&2
      exit 1
    fi
  fi
  # Remove only the lock that was read: if its owner line changed meanwhile, touch nothing.
  result="$(vssh "if [ \"\$(cat $lock/owner 2>/dev/null)\" = '$lock_owner' ]; then rm -f $lock/owner && rmdir $lock && echo removed; else echo changed; fi")"
  case "$result" in
    removed) echo "removed the build lock $lock${lock_owner:+ (owner: $lock_owner)}" ;;
    changed) echo "the build lock $lock changed while unlocking; nothing removed" >&2; exit 1 ;;
    *) echo "cannot remove the build lock $lock on the VPS: '$result'" >&2; exit 1 ;;
  esac
}
case "$mode" in
  preflight) preflight; exit 0 ;;
  unlock) unlock; exit 0 ;;
esac

# The sign-in button needs Google's official mark in the commit being built.
branding_args=()
[[ -z "${SHELLX_GOOGLE_BRANDING_ROOT:-}" ]] || branding_args=(--root "$SHELLX_GOOGLE_BRANDING_ROOT")
python3 scripts/shellx/check-google-branding.py --git-rev HEAD ${branding_args[@]+"${branding_args[@]}"} >&2 || exit 1
out_dir="${1:-$repo/dist/windows}"
volume=shellx-winbuild-cargo

version="$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"$/\1/p' windows/Cargo.toml)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "cannot read windows/Cargo.toml version: '$version'" >&2; exit 1; }
commit="$(git rev-parse HEAD)"
label="${SHELLX_BUILD_LABEL:-}"
file_label=""
label_env=""
if [[ -n "$label" ]]; then
  [[ "$label" =~ ^[a-z][a-z0-9]{0,9}$ ]] || { echo "SHELLX_BUILD_LABEL must be a lower-case letter then up to 9 letters or digits: '$label'" >&2; exit 1; }
  file_label="$label-${commit:0:10}"
  label_env="-e SHELLX_BUILD_LABEL=$label"
fi
setup_name="ShellX-Setup-$version${file_label:+-$file_label}.exe"
symbols_dir="${setup_name%.exe}-symbols"
ghostty_sha="$(git ls-tree HEAD ghostty | awk '$2 == "commit" {print $3}')"
[[ -n "$ghostty_sha" ]] || { echo "HEAD has no ghostty submodule entry" >&2; exit 1; }
ghostty_url="$(git config -f .gitmodules submodule.ghostty.url)"
tag="${SHELLX_WINBUILD_TAG:-$(git rev-parse --short=12 HEAD:windows/cross)}"
image="shellx-winbuild:$tag"
if [[ -n "$(git status --porcelain -- windows cmux-tui shellx-core)" ]]; then
  echo "warning: uncommitted changes under windows/, cmux-tui/ or shellx-core/ are NOT built" >&2
fi
echo "ShellX for Windows $version from $commit (ghostty $ghostty_sha), image $image${file_label:+, label $file_label}"

tmp="$(mktemp -d)"
locked=0
owner="$this_host pid $$ $(date -u +%Y-%m-%dT%H:%M:%SZ) ${commit:0:10}"
# On every exit (success, a failed step, Ctrl-C): drop the temp dir and the lock this run took,
# but only while its owner line is still this run's. Keeps the run's own exit status.
cleanup() {
  local status=$? release
  trap - EXIT INT TERM
  rm -rf "$tmp"
  if [[ $locked -eq 1 ]]; then
    release="$(vssh "if [ ! -d $lock ]; then echo gone; elif [ \"\$(cat $lock/owner 2>/dev/null)\" = '$owner' ]; then rm -f $lock/owner && rmdir $lock && echo released; else echo foreign; cat $lock/owner 2>/dev/null || true; fi" </dev/null)" \
      || release=error
    case "$(printf '%s\n' "$release" | sed -n 1p)" in
      released) ;;
      gone) echo "the build lock $lock was already gone when this run ended" >&2 ;;
      foreign) echo "left the build lock $lock in place: its owner is no longer this run ($(printf '%s\n' "$release" | sed -n 2p))" >&2 ;;
      *) echo "could not remove the build lock $lock on the VPS ($owner); this run has ended, so:" \
           "scripts/shellx/release/build-windows-cross.sh --unlock" >&2 ;;
    esac
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

preflight
# The lock: an atomic mkdir, before anything on the VPS changes, then the owner line in the same
# command (if that write fails, the lock is dropped again). A second run fails here.
lock_result="$(vssh "mkdir -p ~/$remote && if mkdir $lock 2>/dev/null; then if printf '%s\n' '$owner' > $lock/owner; then echo taken; else rm -f $lock/owner; rmdir $lock; echo no-owner; fi; else echo held; cat $lock/owner 2>/dev/null || true; fi")"
case "$(printf '%s\n' "$lock_result" | sed -n 1p)" in
  taken) locked=1 ;;
  held) refuse_held "$(printf '%s\n' "$lock_result" | sed -n 2p)" ;;
  *) echo "cannot take the build lock on the VPS: '$lock_result'" >&2; exit 1 ;;
esac

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
    -e HOST_UID=\$(id -u) -e HOST_GID=\$(id -g) -e CMUX_TUI_BUILD_COMMIT=$commit $label_env \
    -v $volume:/cache -v \$PWD/src:/src -v \$PWD/out:/out \
    $image bash /opt/winbuild/build-in-container.sh 2>&1 | tee build.log \
    | grep -E '^(==|error)|^test .* FAILED|test result|Successful compile' || true
  test -f out/$setup_name || { tail -60 build.log; exit 1; }"

# 4. Download the installer (the deliverable).
mkdir -p "$out_dir"
vssh "cat ~/$remote/out/$setup_name" > "$out_dir/$setup_name"
vssh "cat ~/$remote/out/SHA256SUMS" > "$out_dir/SHA256SUMS.remote"
(cd "$out_dir" && shasum -a 256 "$setup_name" | tee "$setup_name.sha256")
grep -q "$(cut -d' ' -f1 "$out_dir/$setup_name.sha256")" "$out_dir/SHA256SUMS.remote" \
  || { echo "checksum mismatch after download" >&2; exit 1; }

# 5. Free the big intermediates; keep the registry, xwin and zig caches for the next run.
# Before the symbols download: those files are in ~/<build dir>/out, not in the volume, and a
# failure below must not leave the target in the volume (B-2 review m8).
if [[ "${SHELLX_WINBUILD_KEEP_TARGET:-0}" != 1 ]]; then
  vssh "docker run --rm --name shellx-winbuild-run -v $volume:/cache $image rm -rf /cache/target /cache/zig-local"
fi

# 6. The exe and its PDB, side by side, outside the installer (Ruling 11). Best effort: the
# installer is the deliverable, so a failure here is a warning, never an exit. The folder is
# emptied first, so a file from an earlier build is never taken for this build's.
rm -rf "${out_dir:?}/$symbols_dir"
mkdir -p "$out_dir/$symbols_dir"
# <file in out/>: downloaded into the symbols folder, and its sum is in SHA256SUMS.remote.
fetch_checked() {
  local f="$1" sum
  vssh "cat ~/$remote/out/$f" > "$out_dir/$symbols_dir/$f" </dev/null || return 1
  sum="$(shasum -a 256 "$out_dir/$symbols_dir/$f" | cut -d' ' -f1)"
  grep -q "$sum  $f" "$out_dir/SHA256SUMS.remote"
}
symbols=""
if fetch_checked shellx-desktop.exe; then
  symbols="exe"
  if vssh "test -f ~/$remote/out/shellx_desktop.pdb" </dev/null && fetch_checked shellx_desktop.pdb; then
    symbols="exe and PDB"
  else
    rm -f "$out_dir/$symbols_dir/shellx_desktop.pdb"
    echo "warning: no intact shellx_desktop.pdb from this build; crash files cannot be mapped to code" >&2
  fi
else
  rm -rf "${out_dir:?}/$symbols_dir"
  echo "warning: the exe for the symbols folder did not download intact (the installer is fine)" >&2
fi

# 7. Disk: when under the minimum, remove older shellx-winbuild image tags (only those).
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
echo "Built $out_dir/$setup_name (unsigned)${symbols:+; $symbols in $out_dir/$symbols_dir}"
