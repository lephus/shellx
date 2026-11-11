#!/usr/bin/env bash
# Compiles the committed HEAD of the Windows app (shellx-model, shellx-remote, shellx-app,
# all targets) for x86_64-pc-windows-msvc from this Mac, in a local Docker container
# (windows/cross/check.Dockerfile). No installer, no exe: exit 0 means it compiles.
#
#   scripts/shellx/check-windows-build.sh [--vps]
#
# Checks the committed HEAD (git archive), not the working tree. The ghostty submodule comes
# from the first of $CMUX_GHOSTTY_SRC, <repo>/ghostty, <main worktree>/ghostty that has the
# commit HEAD pins. Sources are extracted with fresh modification times: git archive stamps
# files with the commit time, which could make the kept cargo cache skip a changed file.
#
# Docker: image shellx-wincheck:<hash of the four recipe files>, built on first use; cache
# volume shellx-wincheck-cache (cargo registry, xwin CRT/SDK, zig, target); one run at a time
# (container shellx-wincheck-run), at most 8 CPUs, 6 GB of memory, 6 cargo jobs.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo"

if [[ "${1:-}" == --vps ]]; then
  echo "VPS route not built: the local route passed (see Task T1)" >&2
  exit 2
fi
if [[ $# -gt 0 ]]; then
  echo "usage: scripts/shellx/check-windows-build.sh [--vps]" >&2
  exit 2
fi

if [[ -n "$(git status --porcelain -- windows cmux-tui shellx-core)" ]]; then
  echo "warning: uncommitted changes under windows/, cmux-tui/ or shellx-core/ are NOT checked" >&2
fi
commit="$(git rev-parse HEAD)"
ghostty_sha="$(git ls-tree HEAD ghostty | awk '$2 == "commit" {print $3}')"
[[ -n "$ghostty_sha" ]] || { echo "HEAD has no ghostty submodule entry" >&2; exit 1; }

tmp_dirs=()
cleanup() { [[ ${#tmp_dirs[@]} -eq 0 ]] || rm -rf "${tmp_dirs[@]}"; }
trap cleanup EXIT

# 1. Image, keyed by the working-tree bytes of its recipe (it can change without a commit).
cross="$repo/windows/cross"
recipe=(check.Dockerfile llvm-rc.sh zig-libc-msvc.sh check-in-container.sh)
tag="$(cd "$cross" && cat "${recipe[@]}" | shasum -a 256 | cut -c1-12)"
image="shellx-wincheck:$tag"
if ! docker image inspect "$image" >/dev/null 2>&1; then
  ctx="$(mktemp -d "${TMPDIR:-/tmp}/shellx-wincheck-image.XXXXXX")"
  tmp_dirs+=("$ctx")
  (cd "$cross" && cp "${recipe[@]}" "$ctx/")
  echo "== building $image"
  docker build -f "$ctx/check.Dockerfile" -t "$image" "$ctx"
fi

# 2. Sources: the three trees the windows workspace needs, plus the pinned ghostty.
src="$(mktemp -d "${TMPDIR:-/tmp}/shellx-wincheck.XXXXXX")"
tmp_dirs+=("$src")
git archive HEAD windows cmux-tui shellx-core | tar -x -m -C "$src"
candidates=()
[[ -z "${CMUX_GHOSTTY_SRC:-}" ]] || candidates+=("$CMUX_GHOSTTY_SRC")
candidates+=("$repo/ghostty")
main_worktree="$(git worktree list --porcelain | awk '/^worktree / {print substr($0, 10); exit}')"
[[ -z "$main_worktree" ]] || candidates+=("$main_worktree/ghostty")
ghostty_dir=""
for dir in "${candidates[@]}"; do
  # A submodule that is not checked out is an empty directory, where git would answer for
  # the superproject: require the submodule's own .git.
  if [[ -e "$dir/.git" ]] && git -C "$dir" cat-file -e "$ghostty_sha^{commit}" 2>/dev/null; then
    ghostty_dir="$dir"
    break
  fi
done
if [[ -z "$ghostty_dir" ]]; then
  echo "no ghostty checkout has commit $ghostty_sha (tried: ${candidates[*]});" \
    "set CMUX_GHOSTTY_SRC to a ghostty checkout that has it" >&2
  exit 1
fi
git -C "$ghostty_dir" archive --prefix=ghostty/ "$ghostty_sha" | tar -x -m -C "$src"
echo "Checking $commit for Windows (ghostty $ghostty_sha from $ghostty_dir), image $image"

# 3. Check.
docker volume create shellx-wincheck-cache >/dev/null
status=0
docker run --rm --init --name shellx-wincheck-run --memory 6g --cpus 8 -e CARGO_BUILD_JOBS=6 \
  -e CMUX_TUI_BUILD_COMMIT="$commit" \
  -v shellx-wincheck-cache:/cache -v "$src":/src \
  "$image" bash /opt/winbuild/check-in-container.sh || status=$?
if [[ $status -ne 0 ]]; then
  echo "Windows check of $commit FAILED (exit $status)" >&2
  exit "$status"
fi
echo "Checked $commit for Windows (x86_64-pc-windows-msvc): OK"
