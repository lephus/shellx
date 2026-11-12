# Sourced by the desktop release scripts (bash 3.2 compatible); not run on its own.
#
# The Google Desktop OAuth client (contracts section 10) is compiled into the Mac and Windows
# apps at build time (option_env! in shellx-core/src/config.rs). The values live in
# ~/.shellx-release/google-desktop-oauth.env and reach a build through the environment:
# SHELLX_GOOGLE_DESKTOP_CLIENT_ID and SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET.
# Nothing here prints a value, and a value never goes into an argument list.

# 0 and silent when both variables look right; otherwise one stderr line naming the variable, 1.
shellx_require_google_desktop_client() {
  local how='a release build needs the Desktop OAuth client (set -a; . ~/.shellx-release/google-desktop-oauth.env; set +a)'
  if ! [[ "${SHELLX_GOOGLE_DESKTOP_CLIENT_ID:-}" =~ ^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$ ]]; then
    echo "error: SHELLX_GOOGLE_DESKTOP_CLIENT_ID is missing or not a Google OAuth client id; $how" >&2
    return 1
  fi
  if ! [[ "${SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET:-}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "error: SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET is missing or malformed; $how" >&2
    return 1
  fi
}

# 0 when both values occur in the bytes under <file-or-directory>, else 1. Prints nothing; each
# value reaches grep through a pipe (-f <(...)), never as an argument.
shellx_binary_has_google_desktop_client() {
  local path="$1"
  # An empty value is an empty grep pattern, which matches any line: never "present".
  [[ -n "${SHELLX_GOOGLE_DESKTOP_CLIENT_ID:-}" && -n "${SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET:-}" ]] || return 1
  grep -r -q -a -F -f <(printf '%s\n' "${SHELLX_GOOGLE_DESKTOP_CLIENT_ID:-}") "$path" 2>/dev/null || return 1
  grep -r -q -a -F -f <(printf '%s\n' "${SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET:-}") "$path" 2>/dev/null || return 1
}
