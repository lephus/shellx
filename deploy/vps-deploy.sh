#!/usr/bin/env bash
# Deploys ShellX's VPS stack (relay + web + backup) from this Mac, without GitHub Actions. It does what
# .github/workflows/deploy.yml does, except that the images are built ON THE VPS and never pushed to a
# registry:
#
#   1. refuse a dirty relay/, web/ or deploy/ tree; the commit to deploy is HEAD
#   2. rsync the build sources (tracked files of relay/, web/ and deploy/web/, plus the compose file and
#      relay.env for the preflight) to <app-dir>/.build-src/<sha>/ on the VPS
#   3. over ssh, docker build ghcr.io/lephus/shellx-relay:<sha> (this runs every relay test, as in CI)
#      and ghcr.io/lephus/shellx-web:<sha>, then the same preflight as CI (the compose file resolves,
#      the relay's config loads from relay.env)
#   4. rsync docker-compose.yml, relay.env, nginx-proxy/ and backup/ into <app-dir>/.incoming/
#   5. stream deploy/rollout.sh to the VPS with SHELLX_LOCAL_IMAGES=1 (it does not pull relay and web;
#      it swaps the config in, recreates, health-checks and rolls back exactly as in CI)
#   6. check the public endpoints (the same retries as deploy.yml)
#   7. remove <app-dir>/.build-src/<sha> (kept when any earlier step failed, to look at)
#
# Everything on the VPS stays inside <app-dir> (default ~/phu/shellx): the VPS hosts other projects.
# Output is the step names, the build output and what the smoke checks print; never a secret, never the
# content of a log (rollout.sh only hints at the command to run on the VPS).
#
# Environment:
#   SHELLX_VPS            ssh target, default higio@42.115.41.70
#   SHELLX_VPS_SSH_OPTS   ssh options, default "-o ControlPath=~/.ssh/cm-shellx-vps" (an already open
#                         ControlMaster connection: see deploy/README.md "Deploying without GitHub
#                         Actions"). Set it to the empty string to use plain ssh with your own keys.
#   APP_DIR               ShellX's folder on the VPS, relative to the ssh user's home, default phu/shellx
#   RELAY2_ENABLED        true or false: also check GET /v2/relay. Unset: asked of the VPS (it is true
#                         when the VPS's .env has COMPOSE_PROFILES with relay2).
#   SHELLX_SMOKE_ATTEMPTS, SHELLX_SMOKE_INTERVAL   smoke check retries (default 10) and seconds between
#                         them (default 15)
#
# Usage: deploy/vps-deploy.sh [--dry-run]     (--dry-run prints the commands and runs none of the remote ones)
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: deploy/vps-deploy.sh [--dry-run]

Builds ShellX's relay and web images on the VPS from the checked-out commit and rolls them out
(no GitHub Actions). See deploy/README.md, "Deploying without GitHub Actions".

  --dry-run   print every command (and the script that would run on the VPS), run none of them

Environment: SHELLX_VPS (default higio@42.115.41.70), SHELLX_VPS_SSH_OPTS (default
"-o ControlPath=~/.ssh/cm-shellx-vps"), APP_DIR (default phu/shellx), RELAY2_ENABLED (true|false).
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

DEFAULT_SSH_OPTS='-o ControlPath=~/.ssh/cm-shellx-vps'
VPS="${SHELLX_VPS:-higio@42.115.41.70}"
SSH_OPTS_TEXT="${SHELLX_VPS_SSH_OPTS-$DEFAULT_SSH_OPTS}"
APP_DIR="${APP_DIR:-phu/shellx}"
SMOKE_ATTEMPTS="${SHELLX_SMOKE_ATTEMPTS:-10}"
SMOKE_INTERVAL="${SHELLX_SMOKE_INTERVAL:-15}"

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
case "${RELAY2_ENABLED:-}" in
  '' | true | false) ;;
  *) echo "error: RELAY2_ENABLED must be true or false (or unset: the VPS is asked)" >&2; exit 1 ;;
esac

# ssh as an array (the shell never re-splits it); the same options as one string for rsync -e.
SSH=(ssh)
if [[ "$SSH_OPTS_TEXT" =~ [^[:space:]] ]]; then
  read -r -a ssh_opts <<<"$SSH_OPTS_TEXT"
  SSH+=("${ssh_opts[@]}")
fi
RSYNC_SSH="ssh $SSH_OPTS_TEXT"

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

# --- 1. what to deploy ---------------------------------------------------------------------------------

SHA="$(git rev-parse HEAD)"
if [[ ! "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: could not resolve HEAD to a full commit sha" >&2
  exit 1
fi
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

dirty="$(git status --porcelain --untracked-files=normal -- relay web deploy)"
if [[ -n "$dirty" ]]; then
  {
    echo "relay/, web/ or deploy/ has uncommitted changes (the VPS must run exactly the commit $SHA):"
    printf '%s\n' "$dirty" | head -n 20
  } >&2
  if ((DRY_RUN)); then
    echo "warning: --dry-run goes on, but a real run would refuse here" >&2
  else
    echo "error: commit or stash them first" >&2
    exit 1
  fi
fi

BUILD_SRC="$APP_DIR/.build-src/$SHA"

step "ShellX VPS deploy of ${SHA:0:12} ($BRANCH) to $VPS:$APP_DIR, images built on the VPS (no GitHub Actions)"
if ((DRY_RUN)); then
  echo "dry run: the commands below are printed, not run"
fi

# --- the remote scripts (single-quoted: nothing in them is expanded on the Mac) --------------------------

# Wrapped in main() and called on the last line, like rollout.sh: bash has read the whole script off its
# stdin pipe before any docker command can touch fd 0.
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
  docker build -t "ghcr.io/lephus/shellx-relay:$sha" relay

  echo "==> Build the web image (refuses the [quốc gia] placeholder, checks pages and links)"
  docker build -f web/Dockerfile -t "ghcr.io/lephus/shellx-web:$sha" .

  echo "==> Preflight (compose file and relay config), before anything is staged"
  IMAGE_TAG=x PROXY_NETWORK=x docker compose -f deploy/docker-compose.yml config -q
  docker run --rm --env-file deploy/relay.env "ghcr.io/lephus/shellx-relay:$sha" \
    node -e "import('./dist/config.js').then(({ loadConfig }) => loadConfig(process.env)).catch((err) => { console.error(err.message); process.exit(1); })"
}
main "$@"
EOF

# --- 2. reach the VPS, find ShellX's folder ------------------------------------------------------------

step "Check the connection to $VPS and the ShellX folder $APP_DIR"
if ((DRY_RUN)); then
  printf '+'
  words "${SSH[@]}" -o BatchMode=yes -o ConnectTimeout=15 "$VPS" true
  printf '\n+'
  words "${SSH[@]}" "$VPS" "test -f $APP_DIR/.env && test -d $APP_DIR/data"
  printf '\n'
else
  if ! "${SSH[@]}" -o BatchMode=yes -o ConnectTimeout=15 "$VPS" true; then
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
    echo "error: $VPS:$APP_DIR is not a set-up ShellX folder (no .env or data/ in it); nothing was changed (deploy/README.md, First-time setup)" >&2
    exit 1
  fi
fi

# --- 3. build sources ----------------------------------------------------------------------------------

step "Copy the build sources to $APP_DIR/.build-src/${SHA:0:12}... on the VPS"
FILE_LIST="$(mktemp)"
trap 'rm -f "$FILE_LIST"' EXIT
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

# --- 6. roll out ---------------------------------------------------------------------------------------

step "Roll out (swaps in the staged config; the previous config and IMAGE_TAG come back if relay or web is not healthy within 60 s)"
if ((DRY_RUN)); then
  printf '+'
  words "${SSH[@]}" "$VPS" "env SHELLX_LOCAL_IMAGES=1 bash -s -- $SHA $APP_DIR"
  printf ' < deploy/rollout.sh\n'
else
  "${SSH[@]}" "$VPS" "env SHELLX_LOCAL_IMAGES=1 bash -s -- $SHA $APP_DIR" <deploy/rollout.sh
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

# The Node relay owns /v2/relay/tickets whether or not relay2 runs: 401 without a session.
check_tickets() {
  local attempt body
  for attempt in $(seq 1 "$SMOKE_ATTEMPTS"); do
    body="$(curl -s --connect-timeout 10 --max-time 30 -w '\n%{http_code}' -X POST https://relay.shellx.pro/v2/relay/tickets || true)"
    if [ "$(printf '%s' "$body" | tail -n 1)" = 401 ] && printf '%s' "$body" | grep -q '"code":"unauthorized"'; then
      echo "https://relay.shellx.pro/v2/relay/tickets answers 401 unauthorized"
      return 0
    fi
    echo "tickets route not answering 401 unauthorized yet (attempt $attempt/$SMOKE_ATTEMPTS)"
    if ((attempt < SMOKE_ATTEMPTS)); then sleep "$SMOKE_INTERVAL"; fi
  done
  echo "error: POST https://relay.shellx.pro/v2/relay/tickets did not answer 401 unauthorized" >&2
  return 1
}

# true when relay2 runs on the VPS: RELAY2_ENABLED if set, else whether its .env has COMPOSE_PROFILES with
# relay2 (the line rollout.sh reads). grep -q prints nothing, so no .env content leaves the VPS.
relay2_enabled() {
  case "${RELAY2_ENABLED:-}" in
    true | false) echo "$RELAY2_ENABLED"; return 0 ;;
  esac
  local rc=0
  "${SSH[@]}" "$VPS" "grep -Eq '^COMPOSE_PROFILES=.*relay2' $APP_DIR/.env" || rc=$?
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
    echo "+ is relay2 on? ask the VPS: ${SSH[*]} $VPS \"grep -Eq '^COMPOSE_PROFILES=.*relay2' $APP_DIR/.env\""
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

step "Remove the build sources from the VPS"
# APP_DIR (safe characters only, relative, no '..') and SHA (40 hex) were validated above, so the path
# needs no quoting and cannot leave ShellX's folder.
run "${SSH[@]}" "$VPS" "rm -rf -- $BUILD_SRC"

if ((DRY_RUN)); then
  step "Dry run finished: nothing was run on $VPS"
else
  step "Deployed ${SHA:0:12} to $VPS:$APP_DIR"
fi
