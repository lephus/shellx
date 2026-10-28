#!/usr/bin/env bash
# Deploys ShellX's VPS stack (relay + web + backup) from this Mac, without GitHub Actions. It does what
# .github/workflows/deploy.yml does, except that the images are built ON THE VPS and never pushed to a
# registry:
#
#   1. refuse a dirty relay/, web/ or deploy/ tree, and a HEAD that is not on origin/main (fetched first)
#   2. check the connection, take a lock (on the Mac and ~/phu/shellx/.deploy.lock on the VPS), and
#      refuse unless the VPS has 4 GB of disk under Docker's root and 1.5 GB of available memory
#   3. rsync the build sources (tracked files of relay/, web/ and deploy/web/, plus the compose file and
#      relay.env for the preflight) to <app-dir>/.build-src/<sha>/ on the VPS
#   4. over ssh, docker build ghcr.io/lephus/shellx-relay:<sha> (this runs every relay test, as in CI)
#      and ghcr.io/lephus/shellx-web:<sha> (each under `timeout 30m`), then the same preflight as CI
#      (the compose file resolves, the relay's config loads from relay.env)
#   5. rsync docker-compose.yml, relay.env, nginx-proxy/ and backup/ into <app-dir>/.incoming/
#   6. copy deploy/rollout.sh to <app-dir>/.rollout/<sha>.sh and start it DETACHED there with
#      SHELLX_LOCAL_IMAGES=1 (setsid nohup, output in <sha>.log, exit code in <sha>.exit): a dropped ssh
#      session can no longer kill compose half way through a recreate or a rollback. This script polls the
#      exit marker over ssh and shows the log as it grows. rollout.sh swaps the config in, recreates,
#      health-checks and rolls back exactly as in CI, and the detached wrapper releases the VPS lock.
#   7. check the public endpoints (the same retries as deploy.yml)
#   8. remove <app-dir>/.build-src/<sha> and the rollout files (kept when any earlier step failed)
#
# Everything on the VPS stays inside <app-dir> (default ~/phu/shellx): the VPS hosts other projects.
# Output is the step names, the build output, rollout.sh's own lines and what the smoke checks print;
# never a secret, never the content of a log (rollout.sh only hints at the command to run on the VPS).
# While it runs the Mac is kept awake with `caffeinate -i` when that exists (closing the lid still sleeps).
#
# If the connection drops during step 6 the rollout carries on (or has finished) on the VPS; the script
# says how to look (docker compose ps, the log) and that running it again heals.
#
# Environment:
#   SHELLX_VPS            ssh target, default higio@42.115.41.70
#   SHELLX_VPS_SSH_OPTS   ssh options. Default "-o ControlPath=~/.ssh/cm-shellx-vps" (an already open
#                         ControlMaster connection: see deploy/README.md "Deploying without GitHub
#                         Actions"), and ONLY for the default target: with another SHELLX_VPS you must set
#                         this too (the empty string = plain ssh), so production's master is never reused
#                         for a different host. Every ssh and rsync also gets BatchMode=yes,
#                         ServerAliveInterval=15 and ServerAliveCountMax=4.
#   APP_DIR               ShellX's folder on the VPS, relative to the ssh user's home, default phu/shellx
#   RELAY2_ENABLED        true or false: also check GET /v2/relay. Unset: asked of the VPS (it is true
#                         when the VPS's .env has COMPOSE_PROFILES with relay2 in its comma list).
#   SHELLX_ALLOW_NON_MAIN=1   deploy a HEAD that is not an ancestor of origin/main (prints a warning)
#   SHELLX_ROLLOUT_TIMEOUT    seconds to wait for the rollout, default 1500 (it keeps running after that)
#   SHELLX_ROLLOUT_POLL       seconds between polls of the rollout, default 5
#   SHELLX_SMOKE_ATTEMPTS, SHELLX_SMOKE_INTERVAL   smoke check retries (default 10) and seconds between
#                         them (default 15)
#   SHELLX_LOCK_DIR       where the Mac-side lock lives, default $TMPDIR (or /tmp)
#
# Usage: deploy/vps-deploy.sh [--dry-run]     (--dry-run prints the commands and runs none of the remote ones)
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: deploy/vps-deploy.sh [--dry-run]

Builds ShellX's relay and web images on the VPS from the checked-out commit (which must be on
origin/main) and rolls them out (no GitHub Actions). See deploy/README.md, "Deploying without GitHub
Actions".

  --dry-run   print every command (and the scripts that would run on the VPS), run none of them

Environment: SHELLX_VPS (default higio@42.115.41.70), SHELLX_VPS_SSH_OPTS (default
"-o ControlPath=~/.ssh/cm-shellx-vps", only for the default target), APP_DIR (default phu/shellx),
RELAY2_ENABLED (true|false), SHELLX_ALLOW_NON_MAIN=1.
EOF
}

DRY_RUN=0
while (($# > 0)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

DEFAULT_VPS=higio@42.115.41.70
DEFAULT_SSH_OPTS='-o ControlPath=~/.ssh/cm-shellx-vps'
# Every ssh and rsync: never prompt (a missing shared connection must fail, not hang), and notice a dead
# connection within a minute (4 missed 15 s probes).
FIXED_SSH_OPTS='-o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4'
VPS="${SHELLX_VPS:-$DEFAULT_VPS}"
APP_DIR="${APP_DIR:-phu/shellx}"
SMOKE_ATTEMPTS="${SHELLX_SMOKE_ATTEMPTS:-10}"
SMOKE_INTERVAL="${SHELLX_SMOKE_INTERVAL:-15}"
ROLLOUT_TIMEOUT="${SHELLX_ROLLOUT_TIMEOUT:-1500}"
ROLLOUT_POLL="${SHELLX_ROLLOUT_POLL:-5}"
# 4 GB under Docker's root dir (images, build cache) and 1.5 GB of available memory (relay tests, astro build).
MIN_DISK_KB=4194304
MIN_MEM_KB=1572864

# --- validate the inputs (these end up in remote commands and in an rm -rf) ---------------------------

# Same rule as deploy.yml's VPS_APP_DIR: relative, no leading '-', no '.' or '..' path segment. The
# dotdot pattern lives in a variable: some bash versions strip backslashes from an inline =~ pattern.
dotdot_re='(^|/)\.\.?(/|$)'
if [[ ! "$APP_DIR" =~ ^[A-Za-z0-9._/-]+$ ]] || [[ "$APP_DIR" == /* ]] || [[ "$APP_DIR" == -* ]] || [[ "$APP_DIR" =~ $dotdot_re ]]; then
  echo "error: APP_DIR may contain only letters, digits and . _ - /, must be relative, must not start with '-', and must not contain a '.' or '..' path segment" >&2
  exit 1
fi
if [[ ! "$VPS" =~ ^[A-Za-z0-9._@-]+$ ]] || [[ "$VPS" == -* ]]; then
  echo "error: SHELLX_VPS must look like user@host (letters, digits and . _ @ - only, not starting with '-')" >&2
  exit 1
fi
if [[ ! "$SMOKE_ATTEMPTS" =~ ^[0-9]+$ ]] || [[ ! "$SMOKE_INTERVAL" =~ ^[0-9]+$ ]] || ((SMOKE_ATTEMPTS < 1)); then
  echo "error: SHELLX_SMOKE_ATTEMPTS (at least 1) and SHELLX_SMOKE_INTERVAL must be whole numbers" >&2
  exit 1
fi
if [[ ! "$ROLLOUT_TIMEOUT" =~ ^[0-9]+$ ]] || ((ROLLOUT_TIMEOUT < 1)) || [[ ! "$ROLLOUT_POLL" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "error: SHELLX_ROLLOUT_TIMEOUT (whole seconds, at least 1) and SHELLX_ROLLOUT_POLL (seconds) must be numbers" >&2
  exit 1
fi
case "${RELAY2_ENABLED:-}" in
  '' | true | false) ;;
  *) echo "error: RELAY2_ENABLED must be true or false (or unset: the VPS is asked)" >&2; exit 1 ;;
esac

# The default ControlPath is production's shared connection: it only goes with the production target.
if [[ -n "${SHELLX_VPS_SSH_OPTS+set}" ]]; then
  SSH_OPTS_TEXT="$SHELLX_VPS_SSH_OPTS"
elif [[ "$VPS" == "$DEFAULT_VPS" ]]; then
  SSH_OPTS_TEXT="$DEFAULT_SSH_OPTS"
else
  echo "error: SHELLX_VPS is $VPS, not the default target $DEFAULT_VPS: set SHELLX_VPS_SSH_OPTS too (the empty string for plain ssh), so the shared connection to the production VPS is never reused for another host" >&2
  exit 1
fi

# ssh as an array (the shell never re-splits it); the same options as one string for rsync -e.
SSH=(ssh)
if [[ "$SSH_OPTS_TEXT" =~ [^[:space:]] ]]; then
  read -r -a ssh_opts <<<"$SSH_OPTS_TEXT"
  SSH+=("${ssh_opts[@]}")
fi
read -r -a fixed_opts <<<"$FIXED_SSH_OPTS"
SSH+=("${fixed_opts[@]}")
RSYNC_SSH="ssh ${SSH_OPTS_TEXT:+$SSH_OPTS_TEXT }$FIXED_SSH_OPTS"

for tool in git ssh rsync curl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool is not installed" >&2; exit 1; }
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# --- helpers ------------------------------------------------------------------------------------------

step() { printf '\n==> %s\n' "$*"; }

# Prints its arguments as one readable shell line, each quoted only if it needs it (for --dry-run).
words() {
  local a
  for a in "$@"; do
    case "$a" in
      '' | *[!A-Za-z0-9_/.,:=@%+~-]*) printf " '%s'" "$(printf '%s' "$a" | sed "s/'/'\\\\''/g")" ;;
      *) printf ' %s' "$a" ;;
    esac
  done
}

# Runs the command, or only prints it with --dry-run.
run() {
  if ((DRY_RUN)); then
    printf '+'
    words "$@"
    printf '\n'
  else
    "$@"
  fi
}

# Streams a script to `bash -s` on the VPS. Args: the script text, then its arguments.
run_remote_script() {
  local script="$1"
  shift
  if ((DRY_RUN)); then
    printf '+'
    words "${SSH[@]}" "$VPS" bash -s -- "$@"
    printf ' <<script\n'
    printf '%s\n' "$script" | sed 's/^/    | /'
    echo '    script'
  else
    printf '%s\n' "$script" | "${SSH[@]}" "$VPS" bash -s -- "$@"
  fi
}

fail() {
  echo "error: $*" >&2
  exit 1
}

# --- 1. what to deploy ---------------------------------------------------------------------------------

SHA="$(git rev-parse HEAD)"
if [[ ! "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
  fail "could not resolve HEAD to a full commit sha"
fi
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

dirty="$(git status --porcelain --untracked-files=normal -- relay web deploy)"
if [[ -n "$dirty" ]]; then
  {
    echo "relay/, web/ or deploy/ has uncommitted changes (the VPS must run exactly the commit $SHA):"
    printf '%s\n' "$dirty" | sed -n '1,20p'
  } >&2
  if ((DRY_RUN)); then
    echo "warning: --dry-run goes on, but a real run would refuse here" >&2
  else
    fail "commit or stash them first"
  fi
fi

# Only what is already on origin/main may go to production (deploy.yml refuses the same for a manual run).
# The fetch comes first so "on main" is judged against the real main, not a stale copy.
allow_non_main=0
[[ "${SHELLX_ALLOW_NON_MAIN:-}" == 1 ]] && allow_non_main=1
fetched=1
if ((DRY_RUN)); then
  echo "+ git fetch origin main   (dry run: not run; the check below uses the origin/main you already have)"
elif ! git fetch --quiet origin '+refs/heads/main:refs/remotes/origin/main'; then
  fetched=0
fi
if ((! fetched)); then
  if ((allow_non_main)); then
    echo "warning: could not fetch origin/main; SHELLX_ALLOW_NON_MAIN=1, so going on without the check" >&2
  else
    fail "could not fetch origin/main, so HEAD cannot be checked against it (SHELLX_ALLOW_NON_MAIN=1 skips the check)"
  fi
elif ! git merge-base --is-ancestor HEAD refs/remotes/origin/main 2>/dev/null; then
  if ((allow_non_main)); then
    {
      echo "!!!!!!!!!! WARNING !!!!!!!!!!"
      echo "!!! SHELLX_ALLOW_NON_MAIN=1: deploying $SHA, which is NOT an ancestor of origin/main."
      echo "!!! Production will run code that is not on main."
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    } >&2
  elif ((DRY_RUN)); then
    echo "warning: HEAD is not an ancestor of origin/main; a real run would refuse here" >&2
  else
    fail "HEAD ($SHA) is not an ancestor of origin/main. Merge and push it to main first (or SHELLX_ALLOW_NON_MAIN=1 to deploy it anyway)"
  fi
fi

BUILD_SRC="$APP_DIR/.build-src/$SHA"
ROLLOUT_DIR="$APP_DIR/.rollout"
WHO="$(printf '%s@%s' "$(id -un 2>/dev/null || echo mac)" "$(hostname -s 2>/dev/null || echo host)" | tr -c 'A-Za-z0-9._@-' '_')"

# --- the remote scripts (single-quoted: nothing in them is expanded on the Mac) --------------------------

# Takes the deploy lock: ~/phu/shellx/.deploy.lock is a directory (mkdir is atomic) with an `owner` file
# "<sha> <time> <who>". Args: sha, app dir, who. Exit 9: held; the holder is printed.
read -r -d '' REMOTE_LOCK <<'EOF' || true
set -u
sha="$1"; app_dir="$2"; who="$3"
case "$app_dir" in /*) ;; *) app_dir="$HOME/$app_dir" ;; esac
mkdir -p "$app_dir/.rollout" || exit 1
if mkdir "$app_dir/.deploy.lock" 2>/dev/null; then
  printf '%s %s %s\n' "$sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$who" > "$app_dir/.deploy.lock/owner"
  exit 0
fi
printf 'held by: %s\n' "$(cat "$app_dir/.deploy.lock/owner" 2>/dev/null || echo unknown)"
exit 9
EOF

# Gives the lock back, only if it is ours (the owner file starts with our sha). Args: sha, app dir.
read -r -d '' REMOTE_UNLOCK <<'EOF' || true
sha="$1"; app_dir="$2"
case "$app_dir" in /*) ;; *) app_dir="$HOME/$app_dir" ;; esac
if [ "$(cut -d' ' -f1 "$app_dir/.deploy.lock/owner" 2>/dev/null)" = "$sha" ]; then
  rm -f "$app_dir/.deploy.lock/owner"
  rmdir "$app_dir/.deploy.lock" 2>/dev/null
fi
exit 0
EOF

# Measures the disk under Docker's root dir and the available memory. Prints @@ROOT, @@DISK_KB, @@MEM_KB.
read -r -d '' REMOTE_RESOURCES <<'EOF' || true
set -u
root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)" || root=""
disk=""
if [ -n "$root" ]; then
  disk="$(df -Pk "$root" 2>/dev/null | awk 'NR==2 {print $4}')"
fi
mem="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)"
echo "@@ROOT ${root:-unknown}"
echo "@@DISK_KB ${disk:-0}"
echo "@@MEM_KB ${mem:-0}"
EOF

# Wrapped in main() and called on the last line, like rollout.sh: bash has read the whole script off its
# stdin pipe before any docker command can touch fd 0. Each build is cut off after 30 minutes.
read -r -d '' REMOTE_BUILD <<'EOF' || true
set -euo pipefail
main() {
  local sha="$1" app_dir="$2"
  case "$app_dir" in
    /*) ;;
    *) app_dir="$HOME/$app_dir" ;;
  esac
  cd "$app_dir/.build-src/$sha"
  export DOCKER_BUILDKIT=1

  echo "==> Build the relay image (runs the relay tests)"
  timeout 30m docker build -t "ghcr.io/lephus/shellx-relay:$sha" relay

  echo "==> Build the web image (refuses the [quốc gia] placeholder, checks pages and links)"
  timeout 30m docker build -f web/Dockerfile -t "ghcr.io/lephus/shellx-web:$sha" .

  echo "==> Preflight (compose file and relay config), before anything is staged"
  IMAGE_TAG=x PROXY_NETWORK=x docker compose -f deploy/docker-compose.yml config -q
  docker run --rm --env-file deploy/relay.env "ghcr.io/lephus/shellx-relay:$sha" \
    node -e "import('./dist/config.js').then(({ loadConfig }) => loadConfig(process.env)).catch((err) => { console.error(err.message); process.exit(1); })"
}
main "$@"
EOF

# Starts rollout.sh (already copied to .rollout/<sha>.sh) DETACHED and returns at once. The wrapper it
# writes runs it with SHELLX_LOCAL_IMAGES=1, writes the exit code to <sha>.exit (renamed into place, so a
# reader never sees half of it) and gives the lock back, whatever happens. Args: sha, app dir.
read -r -d '' REMOTE_LAUNCH <<'EOF' || true
set -eu
main() {
  local sha="$1" app_dir="$2"
  case "$app_dir" in /*) ;; *) app_dir="$HOME/$app_dir" ;; esac
  cd "$app_dir/.rollout"
  if [ ! -f "$sha.sh" ]; then
    echo "error: $app_dir/.rollout/$sha.sh is missing" >&2
    exit 1
  fi
  rm -f "$sha.exit" "$sha.exit.tmp" "$sha.pid" "$sha.log"
  cat > "$sha.run.sh" <<'WRAP'
#!/usr/bin/env bash
sha="$1"
app_dir="$2"
dir="$app_dir/.rollout"
echo "$$" > "$dir/$sha.pid"
release_lock() {
  if [ "$(cut -d' ' -f1 "$app_dir/.deploy.lock/owner" 2>/dev/null)" = "$sha" ]; then
    rm -f "$app_dir/.deploy.lock/owner"
    rmdir "$app_dir/.deploy.lock" 2>/dev/null
  fi
  return 0
}
trap release_lock EXIT
trap 'exit 143' HUP TERM INT
SHELLX_LOCAL_IMAGES=1 bash "$dir/$sha.sh" "$sha" "$app_dir"
rc=$?
release_lock
printf '%s\n' "$rc" > "$dir/$sha.exit.tmp"
mv "$dir/$sha.exit.tmp" "$dir/$sha.exit"
exit "$rc"
WRAP
  : > "$sha.log"
  if command -v setsid >/dev/null 2>&1; then
    setsid nohup bash "$sha.run.sh" "$sha" "$app_dir" > "$sha.log" 2>&1 < /dev/null &
  else
    nohup bash "$sha.run.sh" "$sha" "$app_dir" > "$sha.log" 2>&1 < /dev/null &
  fi
  echo "rollout started in the background: $app_dir/.rollout/$sha.log"
}
main "$@"
EOF

# One look at the detached rollout. Prints the log from byte <offset> on, then "@@SIZE <bytes>" and
# "@@STATE RUNNING|DEAD|EXIT <code>", each on a line of its own. The exit marker is read first: when it
# exists the log is complete. Args: sha, app dir, offset.
read -r -d '' REMOTE_POLL <<'EOF' || true
sha="$1"; app_dir="$2"; off="$3"
case "$app_dir" in /*) ;; *) app_dir="$HOME/$app_dir" ;; esac
dir="$app_dir/.rollout"
state=RUNNING
rc=""
if [ -f "$dir/$sha.exit" ]; then
  state=EXIT
  rc="$(cat "$dir/$sha.exit")"
elif [ -f "$dir/$sha.pid" ]; then
  pid="$(cat "$dir/$sha.pid")"
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    # It may have finished between the two tests: the marker decides.
    if [ -f "$dir/$sha.exit" ]; then
      state=EXIT
      rc="$(cat "$dir/$sha.exit")"
    else
      state=DEAD
    fi
  fi
fi
size=0
if [ -f "$dir/$sha.log" ]; then
  size="$(wc -c < "$dir/$sha.log" | tr -d ' ')"
  head -c "$size" "$dir/$sha.log" | tail -c +"$((off + 1))"
fi
printf '\n@@SIZE %s\n@@STATE %s %s\n' "$size" "$state" "$rc"
EOF

# Whether COMPOSE_PROFILES in the VPS's .env lists relay2: the same parse as rollout.sh's relay2_enabled
# (last COMPOSE_PROFILES line, quotes and spaces dropped, a comma list). Exit 0 yes, 1 no; prints nothing.
read -r -d '' REMOTE_RELAY2 <<'EOF' || true
app_dir="$1"
case "$app_dir" in /*) ;; *) app_dir="$HOME/$app_dir" ;; esac
profiles="$(sed -n 's/^COMPOSE_PROFILES=//p' "$app_dir/.env" | tail -n 1 | tr -d "\"' ")"
case ",$profiles," in
  *,relay2,*) exit 0 ;;
  *) exit 1 ;;
esac
EOF

# --- locks, cleanup, keeping the Mac awake -------------------------------------------------------------

# Mac side: a directory made with mkdir (atomic), holding our pid. A lock whose pid is gone is a crash
# leftover and is replaced.
LOCK_BASE="${SHELLX_LOCK_DIR:-${TMPDIR:-/tmp}}"
LOCK_BASE="${LOCK_BASE%/}"
lock_key="$(printf '%s' "$VPS:$APP_DIR" | cksum | cut -d' ' -f1)"
MAC_LOCK="$LOCK_BASE/shellx-vps-deploy-$lock_key.lock"
MAC_LOCK_HELD=0
REMOTE_LOCK_HELD=0   # we took ~/phu/shellx/.deploy.lock on the VPS
HANDED_OFF=0         # the detached wrapper owns that lock from here on
ROLLOUT_FINISHED=0
HINT_SHOWN=0
FILE_LIST=""

acquire_mac_lock() {
  local holder
  if ! mkdir "$MAC_LOCK" 2>/dev/null; then
    holder="$(cat "$MAC_LOCK/pid" 2>/dev/null || true)"
    if [[ "$holder" =~ ^[0-9]+$ ]] && ! kill -0 "$holder" 2>/dev/null; then
      echo "note: removing the lock of a deploy that is not running any more (pid $holder)" >&2
      rm -f "$MAC_LOCK/pid"
      rmdir "$MAC_LOCK" 2>/dev/null || true
      mkdir "$MAC_LOCK" 2>/dev/null || fail "could not take the deploy lock $MAC_LOCK"
    else
      fail "another deploy to $VPS:$APP_DIR is running on this Mac (pid ${holder:-unknown}). If none is, remove its lock: rm -rf $MAC_LOCK"
    fi
  fi
  echo "$$" >"$MAC_LOCK/pid"
  MAC_LOCK_HELD=1
}

# What to do after a lost connection or a timeout: the rollout is detached and carries on by itself.
detached_hint() {
  HINT_SHOWN=1
  {
    echo "The rollout runs detached on the VPS: it keeps going (or has finished), and it puts the config and"
    echo "IMAGE_TAG back by itself if relay or web is not healthy. Look, with the connection open again"
    echo "(deploy/README.md, \"Deploying without GitHub Actions\"):"
    echo "  ssh ${SSH_OPTS_TEXT:+$SSH_OPTS_TEXT }$VPS 'cd $APP_DIR && docker compose ps'"
    echo "  ssh ${SSH_OPTS_TEXT:+$SSH_OPTS_TEXT }$VPS 'tail -n 50 $ROLLOUT_DIR/$SHA.log; cat $ROLLOUT_DIR/$SHA.exit'"
    echo "Running deploy/vps-deploy.sh again heals: once the rollout is over (its lock is gone) it rebuilds,"
    echo "re-stages and rolls out again. A lock left by a crash: ssh ${SSH_OPTS_TEXT:+$SSH_OPTS_TEXT }$VPS rm -rf $APP_DIR/.deploy.lock"
    echo "(only when no rollout process is left: ssh ... pgrep -af rollout)."
  } >&2
}

cleanup() {
  local rc=$?
  trap - EXIT
  if [[ -n "$FILE_LIST" ]]; then rm -f "$FILE_LIST"; fi
  # Before the hand-off the VPS lock is ours alone; after it, the detached wrapper gives it back.
  if ((REMOTE_LOCK_HELD && ! HANDED_OFF && ! DRY_RUN)); then
    if ! printf '%s\n' "$REMOTE_UNLOCK" | "${SSH[@]}" -o ConnectTimeout=10 "$VPS" bash -s -- "$SHA" "$APP_DIR" >/dev/null 2>&1; then
      echo "warning: could not give back $VPS:$APP_DIR/.deploy.lock; remove it before the next deploy: ssh ${SSH_OPTS_TEXT:+$SSH_OPTS_TEXT }$VPS rm -rf $APP_DIR/.deploy.lock" >&2
    fi
  fi
  if ((HANDED_OFF && ! ROLLOUT_FINISHED && ! HINT_SHOWN && rc != 0)); then
    detached_hint
  fi
  if ((MAC_LOCK_HELD)); then
    rm -f "$MAC_LOCK/pid"
    rmdir "$MAC_LOCK" 2>/dev/null || true
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if ((! DRY_RUN)); then
  acquire_mac_lock
  # Stay awake (idle sleep only) for as long as this script runs; caffeinate ends when we do.
  if command -v caffeinate >/dev/null 2>&1; then
    caffeinate -i -w "$$" >/dev/null 2>&1 &
  fi
fi

step "ShellX VPS deploy of ${SHA:0:12} ($BRANCH) to $VPS:$APP_DIR, images built on the VPS (no GitHub Actions)"
if ((DRY_RUN)); then
  echo "dry run: the commands below are printed, not run"
else
  echo "Mac lock: $MAC_LOCK"
fi

# --- 2. reach the VPS, find ShellX's folder, lock, resources --------------------------------------------

step "Check the connection to $VPS and the ShellX folder $APP_DIR"
if ((DRY_RUN)); then
  printf '+'
  words "${SSH[@]}" -o ConnectTimeout=15 "$VPS" true
  printf '\n+'
  words "${SSH[@]}" "$VPS" "test -f $APP_DIR/.env && test -d $APP_DIR/data"
  printf '\n'
else
  if ! "${SSH[@]}" -o ConnectTimeout=15 "$VPS" true; then
    cat >&2 <<EOF
error: cannot reach $VPS without a password prompt. If it uses a password, open one shared connection
first (it stays up for 10 hours, and every ssh and rsync below reuses it):

  ssh -fN -M -S ~/.ssh/cm-shellx-vps -o ControlPersist=10h $VPS

(SHELLX_VPS_SSH_OPTS="$SSH_OPTS_TEXT" is what this script passes to ssh. A host key ssh does not
know yet fails the same way: run "ssh $VPS" once by hand.)
EOF
    exit 1
  fi
  if ! "${SSH[@]}" "$VPS" "test -f $APP_DIR/.env && test -d $APP_DIR/data"; then
    fail "$VPS:$APP_DIR is not a set-up ShellX folder (no .env or data/ in it); nothing was changed (deploy/README.md, First-time setup)"
  fi
fi

step "Take the deploy lock on the VPS ($APP_DIR/.deploy.lock)"
if ((DRY_RUN)); then
  run_remote_script "$REMOTE_LOCK" "$SHA" "$APP_DIR" "$WHO"
else
  lock_rc=0
  printf '%s\n' "$REMOTE_LOCK" | "${SSH[@]}" "$VPS" bash -s -- "$SHA" "$APP_DIR" "$WHO" || lock_rc=$?
  case "$lock_rc" in
    0) REMOTE_LOCK_HELD=1 ;;
    9)
      {
        echo "error: another deploy holds $VPS:$APP_DIR/.deploy.lock (see 'held by' above)."
        echo "If it is a leftover of a crash, check that nothing is running and remove it:"
        echo "  ssh ${SSH_OPTS_TEXT:+$SSH_OPTS_TEXT }$VPS 'pgrep -af rollout; cd $APP_DIR && docker compose ps'"
        echo "  ssh ${SSH_OPTS_TEXT:+$SSH_OPTS_TEXT }$VPS rm -rf $APP_DIR/.deploy.lock"
      } >&2
      exit 1
      ;;
    *) fail "could not take the deploy lock on $VPS (ssh status $lock_rc)" ;;
  esac
fi

step "Check the VPS has room to build (4 GB of disk under Docker's root, 1.5 GB of available memory)"
if ((DRY_RUN)); then
  run_remote_script "$REMOTE_RESOURCES"
else
  resources="$(printf '%s\n' "$REMOTE_RESOURCES" | "${SSH[@]}" "$VPS" bash -s)" || fail "could not measure the free disk and memory on $VPS"
  docker_root="$(printf '%s\n' "$resources" | sed -n 's/^@@ROOT //p')"
  disk_kb="$(printf '%s\n' "$resources" | sed -n 's/^@@DISK_KB //p')"
  mem_kb="$(printf '%s\n' "$resources" | sed -n 's/^@@MEM_KB //p')"
  if [[ ! "$disk_kb" =~ ^[0-9]+$ ]] || ((disk_kb == 0)); then
    fail "could not read the free disk under Docker's root dir (${docker_root:-unknown}) on $VPS: is docker usable by this user?"
  fi
  if [[ ! "$mem_kb" =~ ^[0-9]+$ ]] || ((mem_kb == 0)); then
    fail "could not read MemAvailable from /proc/meminfo on $VPS"
  fi
  gb() { awk -v kb="$1" 'BEGIN { printf "%.1f", kb / 1048576 }'; }
  echo "free under $docker_root: $(gb "$disk_kb") GB; available memory: $(gb "$mem_kb") GB"
  if ((disk_kb < MIN_DISK_KB)); then
    fail "only $(gb "$disk_kb") GB free under Docker's root dir ($docker_root) on $VPS; the build needs at least 4 GB. Free space first (docker system df; docker builder prune; docker image prune), nothing was changed"
  fi
  if ((mem_kb < MIN_MEM_KB)); then
    fail "only $(gb "$mem_kb") GB of memory is available on $VPS; the build needs at least 1.5 GB (the relay tests and the astro build). Stop something or try later, nothing was changed"
  fi
fi

# --- 3. build sources ----------------------------------------------------------------------------------

step "Copy the build sources to $APP_DIR/.build-src/${SHA:0:12}... on the VPS"
FILE_LIST="$(mktemp)"
# Only files git tracks: node_modules, build outputs, .env files and every other ignored file stay home.
# relay/ is the relay image's build context; web/ and deploy/web/ are what web/Dockerfile COPYs; the
# compose file and relay.env feed the preflight.
git ls-files -z -- relay web deploy/web deploy/docker-compose.yml deploy/relay.env >"$FILE_LIST"
run "${SSH[@]}" "$VPS" "mkdir -p $BUILD_SRC"
run rsync -rlpt --from0 "--files-from=$FILE_LIST" -e "$RSYNC_SSH" ./ "$VPS:$BUILD_SRC/"

# --- 4. build ------------------------------------------------------------------------------------------

step "Build both images on the VPS"
run_remote_script "$REMOTE_BUILD" "$SHA" "$APP_DIR"

# --- 5. stage the config -------------------------------------------------------------------------------

step "Stage the deploy files into $APP_DIR/.incoming/"
run "${SSH[@]}" "$VPS" "mkdir -p $APP_DIR/.incoming/nginx-proxy $APP_DIR/.incoming/backup"
run rsync -rt -e "$RSYNC_SSH" deploy/docker-compose.yml deploy/relay.env "$VPS:$APP_DIR/.incoming/"
run rsync -rt --delete -e "$RSYNC_SSH" deploy/nginx-proxy/ "$VPS:$APP_DIR/.incoming/nginx-proxy/"
run rsync -rt --delete -e "$RSYNC_SSH" deploy/backup/ "$VPS:$APP_DIR/.incoming/backup/"
# deploy.yml says --chmod=D755,F644, which the rsync that ships with macOS (openrsync) rejects: the same
# modes are set on the VPS instead (nginx, uid 101 in the web image, and the backup container must read them).
run "${SSH[@]}" "$VPS" "find $APP_DIR/.incoming -type d -exec chmod 755 {} + && find $APP_DIR/.incoming -type f -exec chmod 644 {} +"

# --- 6. roll out, detached -----------------------------------------------------------------------------

# Follows the detached rollout until its exit marker appears: polls over ssh every ROLLOUT_POLL seconds,
# shows the log as it grows (rollout.sh's own lines and compose's output; no secret is in them) and gives
# up waiting (not the rollout) after ROLLOUT_TIMEOUT seconds or 3 failed polls in a row.
follow_rollout() {
  local offset=0 fails=0 deadline out data size_line size state_line code
  deadline=$((SECONDS + ROLLOUT_TIMEOUT))
  while :; do
    if out="$(printf '%s\n' "$REMOTE_POLL" | "${SSH[@]}" "$VPS" bash -s -- "$SHA" "$APP_DIR" "$offset")" \
      && [[ "$out" == *$'\n@@SIZE '*$'\n@@STATE '* ]]; then
      fails=0
      data="${out%$'\n'@@SIZE *}"
      size_line="${out##*$'\n'@@SIZE }"
      size="${size_line%%$'\n'*}"
      state_line="${out##*$'\n'@@STATE }"
      printf '%s' "$data"
      if [[ "$size" =~ ^[0-9]+$ ]]; then offset="$size"; fi
      case "$state_line" in
        EXIT\ *)
          [[ -z "$data" || "$data" == *$'\n' ]] || printf '\n'
          code="${state_line#EXIT }"
          ROLLOUT_FINISHED=1
          REMOTE_LOCK_HELD=0 # the wrapper gave it back before writing the marker
          if [[ "$code" == 0 ]]; then
            echo "the rollout finished: exit 0"
            return 0
          fi
          fail "the rollout failed (exit ${code:-?}). rollout.sh put the previous config and IMAGE_TAG back where it could; its lines are above. More: ssh ${SSH_OPTS_TEXT:+$SSH_OPTS_TEXT }$VPS 'cd $APP_DIR && docker compose ps; tail -n 50 $ROLLOUT_DIR/$SHA.log'"
          ;;
        DEAD*)
          [[ -z "$data" || "$data" == *$'\n' ]] || printf '\n'
          ROLLOUT_FINISHED=1
          detached_hint
          fail "the detached rollout is gone without writing its exit code (killed?). Look at docker compose ps before anything else."
          ;;
      esac
    else
      fails=$((fails + 1))
      if ((fails >= 3)); then
        echo >&2
        echo "error: lost the ssh connection to $VPS ($fails polls in a row failed)." >&2
        detached_hint
        exit 1
      fi
    fi
    if ((SECONDS >= deadline)); then
      echo >&2
      echo "error: the rollout is still running after ${ROLLOUT_TIMEOUT}s; this script stops waiting for it." >&2
      detached_hint
      exit 1
    fi
    sleep "$ROLLOUT_POLL"
  done
}

step "Roll out, detached on the VPS (swaps in the staged config; the previous config and IMAGE_TAG come back if relay or web is not healthy within 60 s)"
run rsync -t -e "$RSYNC_SSH" deploy/rollout.sh "$VPS:$ROLLOUT_DIR/$SHA.sh"
if ((DRY_RUN)); then
  run_remote_script "$REMOTE_LAUNCH" "$SHA" "$APP_DIR"
  echo "+ then, every ${ROLLOUT_POLL}s for at most ${ROLLOUT_TIMEOUT}s, until $ROLLOUT_DIR/$SHA.exit exists:"
  run_remote_script "$REMOTE_POLL" "$SHA" "$APP_DIR" 0
else
  HANDED_OFF=1 # from here on the detached wrapper owns the VPS lock
  launch_rc=0
  printf '%s\n' "$REMOTE_LAUNCH" | "${SSH[@]}" "$VPS" bash -s -- "$SHA" "$APP_DIR" || launch_rc=$?
  if ((launch_rc != 0 && launch_rc != 255)); then
    HANDED_OFF=0 # it never started: the lock is still ours and the cleanup gives it back
    fail "could not start the rollout on $VPS (status $launch_rc)"
  fi
  follow_rollout
fi

# --- 7. the public endpoints ---------------------------------------------------------------------------

# The same retries as deploy.yml (10 attempts, 15 s apart) while a first certificate is issued.
check() {
  local attempt
  for attempt in $(seq 1 "$SMOKE_ATTEMPTS"); do
    if curl -fsS --connect-timeout 10 --max-time 30 -o /dev/null "$1"; then
      echo "$1 answers"
      return 0
    fi
    echo "$1 not answering yet (attempt $attempt/$SMOKE_ATTEMPTS)"
    if ((attempt < SMOKE_ATTEMPTS)); then sleep "$SMOKE_INTERVAL"; fi
  done
  echo "error: $1 did not answer after $SMOKE_ATTEMPTS attempts" >&2
  return 1
}

# Same retry loop, but on an exact status: url, accepted status codes (space separated), curl args...
check_status() {
  local url="$1" accepted="$2" code attempt want
  shift 2
  for attempt in $(seq 1 "$SMOKE_ATTEMPTS"); do
    code="$(curl -s --connect-timeout 10 --max-time 30 -o /dev/null -w '%{http_code}' "$@" "$url" || true)"
    for want in $accepted; do
      if [ "$code" = "$want" ]; then
        echo "$url answers $code"
        return 0
      fi
    done
    echo "$url answered $code, expected $accepted (attempt $attempt/$SMOKE_ATTEMPTS)"
    if ((attempt < SMOKE_ATTEMPTS)); then sleep "$SMOKE_INTERVAL"; fi
  done
  echo "error: $url did not answer $accepted after $SMOKE_ATTEMPTS attempts" >&2
  return 1
}

# The Node relay owns /v2/relay/tickets whether or not relay2 runs: 401 without a session. The body is
# matched with [[ ]], not a pipe into grep -q (under pipefail grep's early exit can fail the pipeline).
check_tickets() {
  local attempt body
  for attempt in $(seq 1 "$SMOKE_ATTEMPTS"); do
    body="$(curl -s --connect-timeout 10 --max-time 30 -w '\n%{http_code}' -X POST https://relay.shellx.pro/v2/relay/tickets || true)"
    if [[ "${body##*$'\n'}" == 401 && "$body" == *'"code":"unauthorized"'* ]]; then
      echo "https://relay.shellx.pro/v2/relay/tickets answers 401 unauthorized"
      return 0
    fi
    echo "tickets route not answering 401 unauthorized yet (attempt $attempt/$SMOKE_ATTEMPTS)"
    if ((attempt < SMOKE_ATTEMPTS)); then sleep "$SMOKE_INTERVAL"; fi
  done
  echo "error: POST https://relay.shellx.pro/v2/relay/tickets did not answer 401 unauthorized" >&2
  return 1
}

# true when relay2 runs on the VPS: RELAY2_ENABLED if set, else whether its .env has COMPOSE_PROFILES
# listing relay2. Nothing from .env leaves the VPS but the exit code.
relay2_enabled() {
  case "${RELAY2_ENABLED:-}" in
    true | false) echo "$RELAY2_ENABLED"; return 0 ;;
  esac
  local rc=0
  printf '%s\n' "$REMOTE_RELAY2" | "${SSH[@]}" "$VPS" bash -s -- "$APP_DIR" || rc=$?
  case "$rc" in
    0) echo true ;;
    1) echo false ;;
    *) echo "error: could not read $APP_DIR/.env on $VPS to see whether relay2 is enabled (ssh status $rc)" >&2; return 1 ;;
  esac
}

step "Check the public endpoints (retries while a first certificate is issued)"
if ((DRY_RUN)); then
  echo "+ check https://relay.shellx.pro/v1/version"
  echo "+ check https://shellx.pro/"
  echo "+ check https://admin.shellx.pro/api/session"
  echo "+ check POST https://relay.shellx.pro/v2/relay/tickets answers 401 unauthorized"
  if [[ -n "${RELAY2_ENABLED:-}" ]]; then
    echo "+ RELAY2_ENABLED=$RELAY2_ENABLED: GET https://relay.shellx.pro/v2/relay is checked only when it is true (400 or 426)"
  else
    echo "+ is relay2 on? ask the VPS (COMPOSE_PROFILES in $APP_DIR/.env, as a comma list):"
    run_remote_script "$REMOTE_RELAY2" "$APP_DIR"
    echo "+ if yes: check GET https://relay.shellx.pro/v2/relay answers 400 or 426"
  fi
else
  check https://relay.shellx.pro/v1/version
  check https://shellx.pro/
  # 200 whether or not ADMIN_PASSWORD is set on the VPS ({"enabled": false} without it).
  check https://admin.shellx.pro/api/session
  check_tickets
  relay2="$(relay2_enabled)"
  if [ "$relay2" = true ]; then
    # cmux-relay refuses a plain GET (400 or 426); the Node relay would answer 404 JSON.
    check_status https://relay.shellx.pro/v2/relay "400 426"
  fi
fi

# --- 8. clean up ---------------------------------------------------------------------------------------

step "Remove the build sources and the rollout files from the VPS"
# APP_DIR (safe characters only, relative, no '..') and SHA (40 hex) were validated above, so the paths
# need no quoting and cannot leave ShellX's folder.
run "${SSH[@]}" "$VPS" "rm -rf -- $BUILD_SRC && rm -f -- $ROLLOUT_DIR/$SHA.sh $ROLLOUT_DIR/$SHA.run.sh $ROLLOUT_DIR/$SHA.log $ROLLOUT_DIR/$SHA.exit $ROLLOUT_DIR/$SHA.exit.tmp $ROLLOUT_DIR/$SHA.pid"

if ((DRY_RUN)); then
  step "Dry run finished: nothing was run on $VPS"
else
  step "Deployed ${SHA:0:12} to $VPS:$APP_DIR"
fi
