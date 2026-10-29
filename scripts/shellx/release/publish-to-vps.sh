#!/usr/bin/env bash
# Puts one native ShellX desktop release on download.shellx.pro from this Mac, without GitHub Actions.
# It does what .github/workflows/shellx-publish.yml does, from a local release folder instead of a
# GitHub release.
#
# Usage: scripts/shellx/release/publish-to-vps.sh [--dry-run] <version> <dist-dir>
#
# <dist-dir> holds what scripts/shellx/release/make-feeds.sh writes next to the installers:
#   ShellX-<version>.dmg               required
#   ShellX-Setup-<version>.exe         optional: without it this is a Mac-only release. The live
#                                      latest-windows.json is then kept (no new one is uploaded), so
#                                      Windows machines are not told about a version they cannot get.
#   appcast.xml, latest-macos.json     required
#   latest-windows.json                required with the exe, ignored without it
#   SHA256SUMS                         required. What is uploaded is a copy filtered to the files this
#                                      release uploads: a Mac-only release never lists an exe.
#
# Steps, as in the workflow:
#   1. check SHA256SUMS and the feeds against the installers (the workflow's checks), locally
#   2. refuse a version the VPS or download.shellx.pro already has: installers are immutable (release
#      X.Y.(Z+1) instead). A folder left by an interrupted upload is refused too, and the message says
#      whether removing it is safe (it is when no live feed points at this version yet).
#   3. rsync the installers (--ignore-existing, so an installer is never replaced) into
#      <app-dir>/downloads/desktop/<version>/ (rsync writes a temporary name and renames it; folders 755,
#      files 644 so nginx in the web container can traverse and read them)
#   4. check the installers over HTTPS (size)
#   5. LAST, the feeds: appcast.xml, latest-macos.json and SHA256SUMS (and latest-windows.json, before
#      them, with an exe) into <app-dir>/downloads/desktop/, then check the appcast answers with the
#      new version. Sparkle and the relay never point at a file that is not served yet.
#
# Environment (same as deploy/vps-deploy.sh):
#   SHELLX_VPS            ssh target, default higio@42.115.41.70
#   SHELLX_VPS_SSH_OPTS   ssh options. Default "-o ControlPath=~/.ssh/cm-shellx-vps" (an open
#                         ControlMaster connection, see deploy/README.md), and ONLY for the default
#                         target: with another SHELLX_VPS set this too ("" for plain ssh). Every ssh and
#                         rsync also gets BatchMode=yes, ServerAliveInterval=15, ServerAliveCountMax=4.
#   APP_DIR               ShellX's folder on the VPS, relative to the ssh user's home, default phu/shellx
#   DOWNLOAD_BASE_URL     must be https://download.shellx.pro, the address the apps read the feeds from,
#                         unless SHELLX_ALLOW_OTHER_DOWNLOAD_URL=1 is set as well (a staging site)
#
# --dry-run runs the local checks, prints every command for the VPS and runs none of them.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/shellx/release/publish-to-vps.sh [--dry-run] <version> <dist-dir>

Publishes ShellX-<version>.dmg (and ShellX-Setup-<version>.exe, if present) plus the feeds to
download.shellx.pro through the VPS, without GitHub Actions. A release without the exe is a Mac-only
release: the live latest-windows.json is kept. See deploy/README.md, "Deploying without GitHub Actions".

  --dry-run   do the local checks, print the commands for the VPS, run none of them

Environment: SHELLX_VPS (default higio@42.115.41.70), SHELLX_VPS_SSH_OPTS (default
"-o ControlPath=~/.ssh/cm-shellx-vps", only for the default target), APP_DIR (default phu/shellx).
EOF
}

DRY_RUN=0
ARGS=()
while (($# > 0)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help) usage; exit 0 ;;
    -*) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done
if ((${#ARGS[@]} != 2)); then
  usage >&2
  exit 2
fi
VERSION="${ARGS[0]}"
DIST_ARG="${ARGS[1]}"

PROD_URL=https://download.shellx.pro
DEFAULT_VPS=higio@42.115.41.70
DEFAULT_SSH_OPTS='-o ControlPath=~/.ssh/cm-shellx-vps'
FIXED_SSH_OPTS='-o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4'
VPS="${SHELLX_VPS:-$DEFAULT_VPS}"
APP_DIR="${APP_DIR:-phu/shellx}"
DOWNLOAD_BASE_URL="${DOWNLOAD_BASE_URL:-$PROD_URL}"

fail() {
  echo "error: $*" >&2
  exit 1
}

# --- validate the inputs (these end up in remote commands) --------------------------------------------

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version '$VERSION' is not X.Y.Z"
dotdot_re='(^|/)\.\.?(/|$)'
if [[ ! "$APP_DIR" =~ ^[A-Za-z0-9._/-]+$ ]] || [[ "$APP_DIR" == /* ]] || [[ "$APP_DIR" == -* ]] || [[ "$APP_DIR" =~ $dotdot_re ]]; then
  fail "APP_DIR may contain only letters, digits and . _ - /, must be relative, must not start with '-', and must not contain a '.' or '..' path segment"
fi
if [[ ! "$VPS" =~ ^[A-Za-z0-9._@-]+$ ]] || [[ "$VPS" == -* ]]; then
  fail "SHELLX_VPS must look like user@host (letters, digits and . _ @ - only, not starting with '-')"
fi
[[ "$DOWNLOAD_BASE_URL" =~ ^https?://[A-Za-z0-9.:-]+$ ]] || fail "DOWNLOAD_BASE_URL must be a plain http(s)://host URL"
# The feeds are what the apps read from https://download.shellx.pro: they must be checked against that
# address, as the workflow does, and not against whatever the environment happens to say.
if [[ "$DOWNLOAD_BASE_URL" != "$PROD_URL" && "${SHELLX_ALLOW_OTHER_DOWNLOAD_URL:-}" != 1 ]]; then
  fail "DOWNLOAD_BASE_URL is $DOWNLOAD_BASE_URL, not $PROD_URL. The feeds would be checked against it and published for the apps to read; set SHELLX_ALLOW_OTHER_DOWNLOAD_URL=1 as well if that is really what you want (a staging site)"
fi
[[ -d "$DIST_ARG" ]] || fail "$DIST_ARG is not a directory"
DIST="$(cd "$DIST_ARG" && pwd)"

# The default ControlPath is production's shared connection: it only goes with the production target.
if [[ -n "${SHELLX_VPS_SSH_OPTS+set}" ]]; then
  SSH_OPTS_TEXT="$SHELLX_VPS_SSH_OPTS"
elif [[ "$VPS" == "$DEFAULT_VPS" ]]; then
  SSH_OPTS_TEXT="$DEFAULT_SSH_OPTS"
else
  fail "SHELLX_VPS is $VPS, not the default target $DEFAULT_VPS: set SHELLX_VPS_SSH_OPTS too (the empty string for plain ssh), so the shared connection to the production VPS is never reused for another host"
fi

SSH=(ssh)
if [[ "$SSH_OPTS_TEXT" =~ [^[:space:]] ]]; then
  read -r -a ssh_opts <<<"$SSH_OPTS_TEXT"
  SSH+=("${ssh_opts[@]}")
fi
read -r -a fixed_opts <<<"$FIXED_SSH_OPTS"
SSH+=("${fixed_opts[@]}")
RSYNC_SSH="ssh ${SSH_OPTS_TEXT:+$SSH_OPTS_TEXT }$FIXED_SSH_OPTS"

for tool in ssh rsync curl python3; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is not installed"
done

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

# shasum ships with macOS (and with perl on Linux); sha256sum is the fallback.
if command -v shasum >/dev/null 2>&1; then
  SHA256=(shasum -a 256)
elif command -v sha256sum >/dev/null 2>&1; then
  SHA256=(sha256sum)
else
  fail "neither shasum nor sha256sum is installed"
fi

sha256_of() { "${SHA256[@]}" "$1" | cut -d' ' -f1; }

size_of() { wc -c <"$1" | tr -d '[:space:]'; }

# --- a lock per version (two publishes of one version at once would race), cleanup, staying awake --------

LOCK_BASE="${SHELLX_LOCK_DIR:-${TMPDIR:-/tmp}}"
LOCK_BASE="${LOCK_BASE%/}"
lock_key="$(printf '%s' "$VPS:$APP_DIR:$VERSION" | cksum | cut -d' ' -f1)"
MAC_LOCK="$LOCK_BASE/shellx-vps-publish-$lock_key.lock"
MAC_LOCK_HELD=0
UPLOAD_TMP=""

cleanup() {
  local rc=$?
  trap - EXIT
  if [[ -n "$UPLOAD_TMP" ]]; then rm -rf "$UPLOAD_TMP"; fi
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
  if ! mkdir "$MAC_LOCK" 2>/dev/null; then
    holder="$(cat "$MAC_LOCK/pid" 2>/dev/null || true)"
    if [[ "$holder" =~ ^[0-9]+$ ]] && ! kill -0 "$holder" 2>/dev/null; then
      echo "note: removing the lock of a publish that is not running any more (pid $holder)" >&2
      rm -f "$MAC_LOCK/pid"
      rmdir "$MAC_LOCK" 2>/dev/null || true
      mkdir "$MAC_LOCK" 2>/dev/null || fail "could not take the publish lock $MAC_LOCK"
    else
      fail "another publish of $VERSION is running on this Mac (pid ${holder:-unknown}). If none is, remove its lock: rm -rf $MAC_LOCK"
    fi
  fi
  echo "$$" >"$MAC_LOCK/pid"
  MAC_LOCK_HELD=1
  # Stay awake (idle sleep only) while this runs; caffeinate ends when we do.
  if command -v caffeinate >/dev/null 2>&1; then
    caffeinate -i -w "$$" >/dev/null 2>&1 &
  fi
fi

# --- 1. the release folder -----------------------------------------------------------------------------

DMG="ShellX-$VERSION.dmg"
EXE="ShellX-Setup-$VERSION.exe"
HAVE_EXE=0
[[ -f "$DIST/$EXE" ]] && HAVE_EXE=1

step "ShellX desktop $VERSION from $DIST to $VPS:$APP_DIR/downloads/desktop"
if ((DRY_RUN)); then
  echo "dry run: local checks run, the commands for the VPS are printed and not run"
fi

UPLOADED=("$DMG" appcast.xml latest-macos.json)
if ((HAVE_EXE)); then
  UPLOADED+=("$EXE" latest-windows.json)
fi
for name in "${UPLOADED[@]}" SHA256SUMS; do
  [[ -f "$DIST/$name" ]] || fail "$DIST/$name not found"
done
if ((HAVE_EXE)); then
  echo "Windows installer present: $EXE and latest-windows.json are published too"
else
  echo "no $EXE in $DIST: Mac-only release. The live latest-windows.json is kept; no new one is uploaded."
  if [[ -f "$DIST/latest-windows.json" ]]; then
    echo "note: $DIST/latest-windows.json is ignored (there is no installer for it to point at)"
  fi
fi

# --- 2. checksums and feeds (the workflow's "Check checksums and feeds") ---------------------------------

step "Check checksums and feeds"
UPLOAD_TMP="$(mktemp -d)"
SUMS_UPLOAD="$UPLOAD_TMP/SHA256SUMS"
# SHA256SUMS lines are "<64 hex>  <name>". What gets uploaded is a copy with only the lines of the files
# this release uploads (a Mac-only SHA256SUMS may still list the exe, which is not there), in the original
# order, and each of those files must be listed. The copy is what is verified, too. (The format check
# captures grep's output instead of piping it into another grep: under pipefail a grep -q that exits early
# fails the pipeline.)
bad_lines="$(grep -Ev '^([0-9a-f]{64}  [^/[:space:]]+)?$' "$DIST/SHA256SUMS" || true)"
[[ -z "$bad_lines" ]] || fail "$DIST/SHA256SUMS has a line that is not '<sha256>  <file name>'"
: >"$SUMS_UPLOAD"
listed=" "
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -n "$line" ]] || continue
  name="${line:66}"
  for wanted in "${UPLOADED[@]}"; do
    if [[ "$name" == "$wanted" ]]; then
      printf '%s\n' "$line" >>"$SUMS_UPLOAD"
      listed="$listed$name "
    fi
  done
done <"$DIST/SHA256SUMS"
for name in "${UPLOADED[@]}"; do
  [[ "$listed" == *" $name "* ]] || fail "SHA256SUMS does not list $name"
done
chmod 644 "$SUMS_UPLOAD"
if ! sums_out="$(cd "$DIST" && "${SHA256[@]}" -c "$SUMS_UPLOAD" 2>&1)"; then
  printf '%s\n' "$sums_out" >&2
  fail "the checksums in SHA256SUMS do not match the files"
fi

(
  cd "$DIST"
  VERSION="$VERSION" HAVE_EXE="$HAVE_EXE" DOWNLOAD_BASE_URL="$DOWNLOAD_BASE_URL" python3 -I - <<'PY'
import hashlib, json, os, re
v = os.environ["VERSION"]
base = f"{os.environ['DOWNLOAD_BASE_URL']}/desktop/{v}/"
targets = [("macos", f"ShellX-{v}.dmg")]
if os.environ["HAVE_EXE"] == "1":
    targets.append(("windows", f"ShellX-Setup-{v}.exe"))
for platform, name in targets:
    m = json.load(open(f"latest-{platform}.json"))
    assert m["version"] == v, (platform, m["version"])
    assert m["url"] == base + name, (platform, m["url"])
    assert m["sha256"] == hashlib.sha256(open(name, "rb").read()).hexdigest(), platform
feed = open("appcast.xml").read()
assert f'url="{base}ShellX-{v}.dmg"' in feed, "appcast enclosure url"
assert "sparkle:edSignature=" in feed, "appcast signature"
assert re.search(r"<sparkle:shortVersionString>" + re.escape(v) + "<", feed), "appcast version"
print("feeds ok")
PY
)

# --- 3. refuse to overwrite a published version --------------------------------------------------------

# Runs ON the VPS ($1 = app dir, relative to the home; $2 = version). Exit 0: the version folder is
# missing or empty (an earlier upload may have died before its first file landed). Exit 3: it has files,
# or it cannot be listed (a failing ls -A counts as "not free", never as "empty").
read -r -d '' REMOTE_CHECK <<'EOF' || true
dir="$1/downloads/desktop/$2"
[ -e "$dir" ] || exit 0
[ -d "$dir" ] || exit 3
listing="$(ls -A "$dir")" || exit 3
[ -z "$listing" ] || exit 3
exit 0
EOF

# Why a version folder that is not free is not free, and what to do. Reads the LIVE feeds from the
# website: if one of them points at this version, it is published; if none does (and all could be read),
# the folder is what an interrupted upload left, and removing it is safe.
explain_not_free() {
  local feed body pointing=0 unreadable=0 dir="$APP_DIR/downloads/desktop/$VERSION"
  echo "error: $VPS:$dir already has files; bump the version instead of overwriting." >&2
  for feed in appcast.xml latest-macos.json latest-windows.json; do
    if body="$(curl -sf --connect-timeout 10 --max-time 30 "$DOWNLOAD_BASE_URL/desktop/$feed?feedcheck=$$-$(date +%s)")"; then
      if [[ "$body" == */desktop/$VERSION/* ]]; then
        pointing=1
        echo "  the live $feed points at $VERSION" >&2
      fi
    else
      unreadable=1
      echo "  could not read the live $feed" >&2
    fi
  done
  if ((pointing)); then
    echo "$VERSION is published (a live feed points at it): do not touch the folder, release the next version." >&2
  elif ((unreadable)); then
    echo "Could not check the live feeds, so it is not known whether $VERSION is published: look at $DOWNLOAD_BASE_URL/desktop/ by hand before removing anything." >&2
  else
    echo "No live feed points at $VERSION: the folder is what an interrupted upload left behind. Removing it is safe; then run this again:" >&2
    echo "  ssh ${SSH_OPTS_TEXT:+$SSH_OPTS_TEXT }$VPS rm -rf $dir" >&2
  fi
}

step "Refuse to overwrite a published version"
if ((DRY_RUN)); then
  echo "+ ssh connection check, then:"
  printf '+'
  words "${SSH[@]}" "$VPS" bash -s -- "$APP_DIR" "$VERSION"
  printf ' <<script (exit 3 = %s/downloads/desktop/%s/ has files or cannot be listed)\n' "$APP_DIR" "$VERSION"
  printf '%s\n' "$REMOTE_CHECK" | sed 's/^/    | /'
  echo '    script'
  echo "+ curl: each of the installer URLs below must answer 404 now"
else
  if ! "${SSH[@]}" -o ConnectTimeout=15 "$VPS" true; then
    cat >&2 <<EOF
error: cannot reach $VPS without a password prompt. If it uses a password, open one shared connection
first (it stays up for 10 hours, and every ssh and rsync below reuses it):

  ssh -fN -M -S ~/.ssh/cm-shellx-vps -o ControlPersist=10h $VPS

(SHELLX_VPS_SSH_OPTS="$SSH_OPTS_TEXT" is what this script passes to ssh.)
EOF
    exit 1
  fi
  rc=0
  printf '%s\n' "$REMOTE_CHECK" | "${SSH[@]}" "$VPS" bash -s -- "$APP_DIR" "$VERSION" || rc=$?
  case "$rc" in
    0) echo "$APP_DIR/downloads/desktop/$VERSION is free on $VPS" ;;
    3) explain_not_free; exit 1 ;;
    *) fail "could not check $VPS:$APP_DIR/downloads/desktop/$VERSION (ssh status $rc)" ;;
  esac
  INSTALLERS=("$DMG")
  if ((HAVE_EXE)); then INSTALLERS+=("$EXE"); fi
  for name in "${INSTALLERS[@]}"; do
    url="$DOWNLOAD_BASE_URL/desktop/$VERSION/$name"
    # Unique query string: never read (or seed) a cached 404 for the real URL.
    code="$(curl -s -o /dev/null -w '%{http_code}' "$url?precheck=$$-$(date +%s)" || true)"
    case "$code" in
      404) echo "$url is free" ;;
      000) fail "cannot reach $DOWNLOAD_BASE_URL (is the web container on the VPS running?)" ;;
      *) fail "$url already answers HTTP $code; bump the version instead of overwriting" ;;
    esac
  done
fi

# --- 4. upload the installers --------------------------------------------------------------------------

VERSION_DIR="$APP_DIR/downloads/desktop/$VERSION"
step "Upload installers (rsync into $VERSION_DIR/)"
# Mode 755 on every level: nginx (uid 101, in the web image) must traverse downloads/, desktop/ and the
# version folder to serve the files inside it. (The workflow's rsync --chmod=F644 is not understood by
# the rsync that ships with macOS, so the modes are set on the VPS after the upload.)
# (APP_DIR and VERSION were validated above: safe characters only, so remote paths need no quoting.)
run "${SSH[@]}" "$VPS" "mkdir -p $VERSION_DIR && chmod 755 $APP_DIR/downloads $APP_DIR/downloads/desktop $VERSION_DIR"
UPLOAD=("$DIST/$DMG")
CHMOD_FILES="$VERSION_DIR/$DMG"
if ((HAVE_EXE)); then
  UPLOAD+=("$DIST/$EXE")
  CHMOD_FILES="$CHMOD_FILES $VERSION_DIR/$EXE"
fi
# --ignore-existing: an installer that is already there is never replaced, whatever the checks above saw.
run rsync -t --ignore-existing -e "$RSYNC_SSH" "${UPLOAD[@]}" "$VPS:$VERSION_DIR/"
run "${SSH[@]}" "$VPS" "chmod 644 $CHMOD_FILES"

# --- 5. verify the installers over HTTPS ---------------------------------------------------------------

step "Verify the installers over HTTPS"
verify_id="$$-$(date +%s)"
if ((DRY_RUN)); then
  echo "+ curl -sfIL $DOWNLOAD_BASE_URL/desktop/$VERSION/$DMG?verify=...  (Content-Length must be $(size_of "$DIST/$DMG"))"
  if ((HAVE_EXE)); then
    echo "+ curl -sfIL $DOWNLOAD_BASE_URL/desktop/$VERSION/$EXE?verify=...  (Content-Length must be $(size_of "$DIST/$EXE"))"
  fi
else
  for name in "${INSTALLERS[@]}"; do
    url="$DOWNLOAD_BASE_URL/desktop/$VERSION/$name"
    remote_size="$(curl -sfIL "$url?verify=$verify_id" | tr -d '\r' | awk 'tolower($1) == "content-length:" { size = $2 } END { print size }')"
    local_size="$(size_of "$DIST/$name")"
    if [[ "$remote_size" != "$local_size" ]]; then
      fail "$url has size '$remote_size', expected $local_size"
    fi
    echo "$url has $local_size bytes"
  done
fi

# --- 6. the feeds, last --------------------------------------------------------------------------------

# rsync sends its files in file-list order, not in command-line order, so each feed gets its own call:
# the order is the order below. Every call writes a temporary name and renames it: readers see the old
# or the new file. SHA256SUMS goes last.
FEEDS_DIR="$APP_DIR/downloads/desktop"
step "Upload the feeds (appcast.xml, latest-macos.json, SHA256SUMS last)"
FEEDS=()
if ((HAVE_EXE)); then FEEDS+=(latest-windows.json); fi
FEEDS+=(appcast.xml latest-macos.json SHA256SUMS)
CHMOD_FEEDS=""
for name in "${FEEDS[@]}"; do
  src="$DIST/$name"
  if [[ "$name" == SHA256SUMS ]]; then src="$SUMS_UPLOAD"; fi
  run rsync -t -e "$RSYNC_SSH" "$src" "$VPS:$FEEDS_DIR/"
  CHMOD_FEEDS="$CHMOD_FEEDS $FEEDS_DIR/$name"
done
run "${SSH[@]}" "$VPS" "chmod 644$CHMOD_FEEDS"
if ((! HAVE_EXE)); then
  echo "kept the live $VPS:$FEEDS_DIR/latest-windows.json (no Windows installer in this release)"
fi

if ((DRY_RUN)); then
  echo "+ curl -sf $DOWNLOAD_BASE_URL/desktop/appcast.xml?verify=...  (must mention $DMG)"
else
  # Captured, then matched with [[ ]]: `curl | grep -q` fails under pipefail when grep exits early.
  appcast="$(curl -sf "$DOWNLOAD_BASE_URL/desktop/appcast.xml?verify=$verify_id")" \
    || fail "$DOWNLOAD_BASE_URL/desktop/appcast.xml could not be read"
  [[ "$appcast" == *"$DMG"* ]] || fail "$DOWNLOAD_BASE_URL/desktop/appcast.xml does not serve $VERSION"
  echo "$DOWNLOAD_BASE_URL/desktop/appcast.xml serves $VERSION"
fi

if ((DRY_RUN)); then
  step "Dry run finished: nothing was run on $VPS (this is what a real run reports)"
else
  step "Published ShellX desktop $VERSION"
fi
echo "| File | URL | SHA-256 |"
echo "|---|---|---|"
echo "| $DMG | $DOWNLOAD_BASE_URL/desktop/$VERSION/$DMG | $(sha256_of "$DIST/$DMG") |"
if ((HAVE_EXE)); then
  echo "| $EXE | $DOWNLOAD_BASE_URL/desktop/$VERSION/$EXE | $(sha256_of "$DIST/$EXE") |"
fi
