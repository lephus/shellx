#!/usr/bin/env bash
# Runs ON THE VPS, streamed by deploy.yml:  ssh vps bash -s -- <image-tag> <app-dir> < deploy/rollout.sh
# (VPS spec §6.1 step 4). Pulls the new images, points .env at them, restarts the stack and waits up
# to 60 s for the relay's healthcheck; if it is not healthy, puts the previous IMAGE_TAG back,
# restarts again and fails. Touches nothing outside <app-dir> (relative paths are under $HOME).
set -euo pipefail

new_tag="$1"
app_dir="$2"
health_timeout="${HEALTH_TIMEOUT_SECONDS:-60}"
relay_uid="${RELAY_UID:-1000}"
case "$app_dir" in
  /*) ;;
  *) app_dir="$HOME/$app_dir" ;;
esac
cd "$app_dir"

# Check data/ before creating anything: a missing or wrongly owned data/ must stop here, untouched.
if [[ ! -d data ]]; then
  echo "::error::$app_dir/data does not exist: create it and give it to uid $relay_uid first: mkdir -p $app_dir/data && sudo chown $relay_uid:$relay_uid $app_dir/data" >&2
  exit 1
fi
if [[ "$(ls -nd data | awk '{print $3}')" != "$relay_uid" ]]; then
  echo "::error::$app_dir/data must belong to uid $relay_uid (the relay's node user): sudo chown $relay_uid:$relay_uid $app_dir/data" >&2
  exit 1
fi
mkdir -p backups downloads/desktop nginx-proxy backup
touch .env
if ! grep -q '^PROXY_NETWORK=.' .env; then
  echo "::error::PROXY_NETWORK is not set in $app_dir/.env (deploy/README.md, step 2)" >&2
  exit 1
fi
old_tag="$(sed -n 's/^IMAGE_TAG=//p' .env | tail -n 1)"

set_tag() {
  local tmp
  tmp="$(mktemp .env.XXXXXX)"
  grep -v '^IMAGE_TAG=' .env > "$tmp" || true
  printf 'IMAGE_TAG=%s\n' "$1" >> "$tmp"
  mv "$tmp" .env
}

relay_health() {
  local id
  id="$(docker compose ps -q relay)"
  if [[ -z "$id" ]]; then
    echo missing
    return
  fi
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id"
}

wait_healthy() {
  local deadline=$((SECONDS + health_timeout))
  while ((SECONDS < deadline)); do
    if [[ "$(relay_health)" == healthy ]]; then return 0; fi
    sleep 2
  done
  return 1
}

# Pull first: if the images cannot be pulled, .env and the running stack stay as they were.
IMAGE_TAG="$new_tag" docker compose pull
set_tag "$new_tag"
# A `compose up -d` that fails outright (bad network, volume, daemon hiccup) is treated exactly
# like an unhealthy relay: it falls straight into the rollback branch below.
if docker compose up -d --remove-orphans && wait_healthy; then
  echo "relay is healthy on $new_tag"
  exit 0
fi

echo "::error::relay not healthy within ${health_timeout}s on $new_tag; rolling back to ${old_tag:-nothing}" >&2
docker compose logs --no-color --tail 50 relay >&2 || true
if [[ -n "$old_tag" ]]; then
  set_tag "$old_tag"
  if ! docker compose up -d --remove-orphans || ! wait_healthy; then
    echo "::error::the previous release ($old_tag) is not healthy either" >&2
  fi
fi
exit 1
