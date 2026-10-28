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
#   SHA256SUMS                         required; lines for files this release does not have are ignored
#
# Steps, as in the workflow:
#   1. check SHA256SUMS and the feeds against the installers (the workflow's checks), locally
#   2. refuse a version the VPS or download.shellx.pro already has: installers are immutable (release
#      X.Y.(Z+1) instead)
#   3. rsync the installers into <app-dir>/downloads/desktop/<version>/ (rsync writes a temporary name and
#      renames it; folders 755, files 644 so nginx in the web container can traverse and read them)
#   4. check the installers over HTTPS (size)
#   5. LAST, the feeds: appcast.xml, latest-macos.json and SHA256SUMS (and latest-windows.json, before
#      them, with an exe) into <app-dir>/downloads/desktop/, then check the appcast answers with the
#      new version. Sparkle and the relay never point at a file that is not served yet.
#
# Environment (same as deploy/vps-deploy.sh):
#   SHELLX_VPS            ssh target, default higio@42.115.41.70
#   SHELLX_VPS_SSH_OPTS   ssh options, default "-o ControlPath=~/.ssh/cm-shellx-vps" (an open
#                         ControlMaster connection, see deploy/README.md); "" for plain ssh
#   APP_DIR               ShellX's folder on the VPS, relative to the ssh user's home, default phu/shellx
#   DOWNLOAD_BASE_URL     default https://download.shellx.pro
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
"-o ControlPath=~/.ssh/cm-shellx-vps"), APP_DIR (default phu/shellx).
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

DEFAULT_SSH_OPTS='-o ControlPath=~/.ssh/cm-shellx-vps'
VPS="${SHELLX_VPS:-higio@42.115.41.70}"
SSH_OPTS_TEXT="${SHELLX_VPS_SSH_OPTS-$DEFAULT_SSH_OPTS}"
APP_DIR="${APP_DIR:-phu/shellx}"
DOWNLOAD_BASE_URL="${DOWNLOAD_BASE_URL:-https://download.shellx.pro}"

# --- validate the inputs (these end up in remote commands) --------------------------------------------

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: version '$VERSION' is not X.Y.Z" >&2; exit 1; }
dotdot_re='(^|/)\.\.?(/|$)'
if [[ ! "$APP_DIR" =~ ^[A-Za-z0-9._/-]+$ ]] || [[ "$APP_DIR" == /* ]] || [[ "$APP_DIR" == -* ]] || [[ "$APP_DIR" =~ $dotdot_re ]]; then
  echo "error: APP_DIR may contain only letters, digits and . _ - /, must be relative, must not start with '-', and must not contain a '.' or '..' path segment" >&2
  exit 1
fi
if [[ ! "$VPS" =~ ^[A-Za-z0-9._@-]+$ ]] || [[ "$VPS" == -* ]]; then
  echo "error: SHELLX_VPS must look like user@host (letters, digits and . _ @ - only, not starting with '-')" >&2
  exit 1
fi
[[ "$DOWNLOAD_BASE_URL" =~ ^https?://[A-Za-z0-9.:-]+$ ]] || { echo "error: DOWNLOAD_BASE_URL must be a plain http(s)://host URL" >&2; exit 1; }
[[ -d "$DIST_ARG" ]] || { echo "error: $DIST_ARG is not a directory" >&2; exit 1; }
DIST="$(cd "$DIST_ARG" && pwd)"

SSH=(ssh)
if [[ "$SSH_OPTS_TEXT" =~ [^[:space:]] ]]; then
  read -r -a ssh_opts <<<"$SSH_OPTS_TEXT"
  SSH+=("${ssh_opts[@]}")
fi
RSYNC_SSH="ssh $SSH_OPTS_TEXT"

for tool in ssh rsync curl python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool is not installed" >&2; exit 1; }
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
  echo "error: neither shasum nor sha256sum is installed" >&2
  exit 1
fi

sha256_of() { "${SHA256[@]}" "$1" | cut -d' ' -f1; }

size_of() { wc -c <"$1" | tr -d '[:space:]'; }

# --- 1. the release folder -----------------------------------------------------------------------------

DMG="ShellX-$VERSION.dmg"
EXE="ShellX-Setup-$VERSION.exe"
HAVE_EXE=0
[[ -f "$DIST/$EXE" ]] && HAVE_EXE=1

step "ShellX desktop $VERSION from $DIST to $VPS:$APP_DIR/downloads/desktop"
if ((DRY_RUN)); then
  echo "dry run: local checks run, the commands for the VPS are printed and not run"
fi

REQUIRED=("$DMG" appcast.xml latest-macos.json SHA256SUMS)
if ((HAVE_EXE)); then
  REQUIRED+=("$EXE" latest-windows.json)
fi
for name in "${REQUIRED[@]}"; do
  [[ -f "$DIST/$name" ]] || { echo "error: $DIST/$name not found" >&2; exit 1; }
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
SUMS_TMP="$(mktemp)"
trap 'rm -f "$SUMS_TMP"' EXIT
# SHA256SUMS lines are "<64 hex>  <name>". Only the files this release has are checked, and each of
# them must be listed: a Mac-only SHA256SUMS may still mention the exe, which is simply not there.
if grep -Ev '^$' "$DIST/SHA256SUMS" | grep -Eqv '^[0-9a-f]{64}  [^/[:space:]]+$'; then
  echo "error: $DIST/SHA256SUMS has a line that is not '<sha256>  <file name>'" >&2
  exit 1
fi
: >"$SUMS_TMP"
for name in "${REQUIRED[@]}"; do
  [[ "$name" == SHA256SUMS ]] && continue
  line="$(awk -v n="$name" 'substr($0, 65, 2) == "  " && substr($0, 67) == n' "$DIST/SHA256SUMS")"
  [[ -n "$line" ]] || { echo "error: SHA256SUMS does not list $name" >&2; exit 1; }
  printf '%s\n' "$line" >>"$SUMS_TMP"
done
if ! sums_out="$(cd "$DIST" && "${SHA256[@]}" -c "$SUMS_TMP" 2>&1)"; then
  printf '%s\n' "$sums_out" >&2
  echo "error: the checksums in SHA256SUMS do not match the files" >&2
  exit 1
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

# Runs ON the VPS ($1 = app dir, relative to the home; $2 = version). Exit 3: the folder has files.
# Empty or missing is fine (an earlier upload may have died before its first file landed).
read -r -d '' REMOTE_CHECK <<'EOF' || true
set -eu
dir="$1/downloads/desktop/$2"
if [ -d "$dir" ] && [ -n "$(ls -A "$dir")" ]; then
  exit 3
fi
EOF

step "Refuse to overwrite a published version"
if ((DRY_RUN)); then
  printf '+'
  words "${SSH[@]}" "$VPS" bash -s -- "$APP_DIR" "$VERSION"
  printf ' <<script (exit 3 = %s/downloads/desktop/%s/ already has files)\n' "$APP_DIR" "$VERSION"
  printf '%s\n' "$REMOTE_CHECK" | sed 's/^/    | /'
  echo '    script'
  echo "+ curl: each of the installer URLs below must answer 404 now"
else
  rc=0
  printf '%s\n' "$REMOTE_CHECK" | "${SSH[@]}" "$VPS" bash -s -- "$APP_DIR" "$VERSION" || rc=$?
  case "$rc" in
    0) echo "$APP_DIR/downloads/desktop/$VERSION is free on $VPS" ;;
    3) echo "error: $VPS:$APP_DIR/downloads/desktop/$VERSION already has files; bump the version instead of overwriting" >&2; exit 1 ;;
    *) echo "error: could not check $VPS:$APP_DIR/downloads/desktop/$VERSION (ssh status $rc); if it uses a password, open the shared connection first (deploy/README.md)" >&2; exit 1 ;;
  esac
  INSTALLERS=("$DMG")
  if ((HAVE_EXE)); then INSTALLERS+=("$EXE"); fi
  for name in "${INSTALLERS[@]}"; do
    url="$DOWNLOAD_BASE_URL/desktop/$VERSION/$name"
    # Unique query string: never read (or seed) a cached 404 for the real URL.
    code="$(curl -s -o /dev/null -w '%{http_code}' "$url?precheck=$$-$(date +%s)" || true)"
    case "$code" in
      404) echo "$url is free" ;;
      000) echo "error: cannot reach $DOWNLOAD_BASE_URL (is the web container on the VPS running?)" >&2; exit 1 ;;
      *) echo "error: $url already answers HTTP $code; bump the version instead of overwriting" >&2; exit 1 ;;
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
run rsync -t -e "$RSYNC_SSH" "${UPLOAD[@]}" "$VPS:$VERSION_DIR/"
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
      echo "error: $url has size '$remote_size', expected $local_size" >&2
      exit 1
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
for name in "${FEEDS[@]}"; do
  run rsync -t -e "$RSYNC_SSH" "$DIST/$name" "$VPS:$FEEDS_DIR/"
done
CHMOD_FEEDS=""
for name in "${FEEDS[@]}"; do
  CHMOD_FEEDS="$CHMOD_FEEDS $FEEDS_DIR/$name"
done
run "${SSH[@]}" "$VPS" "chmod 644$CHMOD_FEEDS"
if ((! HAVE_EXE)); then
  echo "kept the live $VPS:$FEEDS_DIR/latest-windows.json (no Windows installer in this release)"
fi

if ((DRY_RUN)); then
  echo "+ curl -sf $DOWNLOAD_BASE_URL/desktop/appcast.xml?verify=...  (must mention $DMG)"
else
  curl -sf "$DOWNLOAD_BASE_URL/desktop/appcast.xml?verify=$verify_id" | grep -qF "$DMG" \
    || { echo "error: $DOWNLOAD_BASE_URL/desktop/appcast.xml does not serve $VERSION" >&2; exit 1; }
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
