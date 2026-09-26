#!/usr/bin/env bash
# Runs ON THE VPS, streamed by deploy.yml:  ssh vps bash -s -- <image-tag> <app-dir> < deploy/rollout.sh
# (VPS spec §6.1 step 4). Everything is wrapped in main(), called only on the very last line, so bash
# has already read this whole script off its stdin pipe before anything inside it runs (a command
# that itself touched fd 0 mid-script could otherwise eat bytes the interpreter had not read yet).
#
# If deploy.yml staged new config into <app-dir>/.incoming/ (docker-compose.yml, relay.env,
# nginx-proxy/, backup/), swaps it into place first, moving the current files into <app-dir>/.prev/
# so a bad relay.env or docker-compose.yml rolls back together with IMAGE_TAG instead of restarting
# the old image with the new, broken config. Then pulls the new images, points .env at them, restarts
# the stack and waits up to 60 s for the relay's healthcheck; if the pull fails or the relay does not
# come up healthy, restores .prev/ and the previous IMAGE_TAG, restarts again and fails. Touches
# nothing outside <app-dir> (relative paths are under $HOME).
set -euo pipefail

main() {
  local new_tag="$1"
  local app_dir="$2"
  local health_timeout="${HEALTH_TIMEOUT_SECONDS:-60}"
  local relay_uid="${RELAY_UID:-1000}"
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
  local old_tag
  old_tag="$(sed -n 's/^IMAGE_TAG=//p' .env | tail -n 1)"

  # The four items deploy.yml rsyncs into .incoming/: staged, then swapped into place together, so a
  # bad relay.env or docker-compose.yml rolls back with IMAGE_TAG instead of sinking the old image.
  local config_items=(docker-compose.yml relay.env nginx-proxy backup)

  # Moves the current four items into .prev/ (replacing any older .prev/), then moves .incoming/'s
  # items into place. A no-op if deploy.yml did not stage anything (no .incoming/), which keeps every
  # caller that never creates .incoming/ byte-for-byte identical to before this change.
  stage_config() {
    if [[ -d .incoming ]]; then
      rm -rf .prev
      mkdir .prev
      local item
      for item in "${config_items[@]}"; do
        if [[ -e "$item" ]]; then mv "$item" ".prev/$item"; fi
      done
      for item in "${config_items[@]}"; do
        if [[ -e ".incoming/$item" ]]; then mv ".incoming/$item" "./$item"; fi
      done
      rm -rf .incoming
    fi
  }

  # Moves .prev/'s items back into place. A no-op if there is nothing staged this run (no .prev/).
  restore_config() {
    if [[ -d .prev ]]; then
      local item
      for item in "${config_items[@]}"; do
        if [[ -e ".prev/$item" ]]; then
          rm -rf "$item"
          mv ".prev/$item" "./$item"
        fi
      done
    fi
  }

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

  # Swap the staged config into place before `compose pull`: compose needs the new docker-compose.yml
  # (image references may have changed) and the relay needs the new relay.env once it restarts.
  stage_config

  # Pull first: if the images cannot be pulled, restore the staged config and leave .env and the
  # running stack as they were.
  if ! IMAGE_TAG="$new_tag" docker compose pull; then
    restore_config
    exit 1
  fi
  set_tag "$new_tag"
  # A `compose up -d` that fails outright (bad network, volume, daemon hiccup) is treated exactly
  # like an unhealthy relay: it falls straight into the rollback branch below.
  if docker compose up -d --remove-orphans && wait_healthy; then
    echo "relay is healthy on $new_tag"
    exit 0
  fi

  echo "::error::relay not healthy within ${health_timeout}s on $new_tag; rolling back to ${old_tag:-nothing}" >&2
  docker compose logs --no-color --tail 50 relay >&2 || true
  restore_config
  if [[ -n "$old_tag" ]]; then
    set_tag "$old_tag"
    if ! docker compose up -d --remove-orphans || ! wait_healthy; then
      echo "::error::the previous release ($old_tag) is not healthy either" >&2
    fi
  fi
  exit 1
}

main "$@"
