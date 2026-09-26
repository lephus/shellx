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
# the stack with --force-recreate (so a container whose own config did not change, such as `backup`,
# is recreated too — otherwise it keeps its old bind-mount inode, which a later `rm -rf .prev` deletes
# out from under it, and its cron job silently stops working) and waits up to 60 s for BOTH the
# relay's and the web's healthcheck. If the pull fails, or either service does not come up healthy,
# restores .prev/ and the previous IMAGE_TAG, restarts again and fails. On success, best-effort prunes
# older ShellX images so the disk does not fill up. Touches nothing outside <app-dir> (relative paths
# are under $HOME).
#
# Crash safety of the config swap (stage_config): the backup of the live config is first built into
# <app-dir>/.prev.new/ by COPYING (not moving) the live items, so the live config stays untouched
# while that happens. Only once .prev.new/ is completely built does the script `rm -rf .prev && mv
# .prev.new .prev` (a single rename), and only then does it remove each live item and move its
# replacement in from .incoming/. Recovery, run at the very start of every deploy, before anything
# else:
#   - A leftover .prev.new/ (the previous run died while building or renaming it) is always
#     discarded. The live config was never touched at that point, so nothing is lost; the next run
#     rebuilds .prev.new/ from scratch.
#   - A live item that is missing while .incoming/ and .prev/ both still exist (the previous run died
#     after removing a live item but before moving its replacement in) is healed by copying it back
#     from .prev/ (copy, not move, so .prev/ is left intact) before the swap is attempted again. This
#     guarantees the live config is never left with a missing file. It does not guarantee .prev/ ends
#     up byte-for-byte the config from before the crashed run for every item — an item the crashed run
#     had already fully swapped in keeps its new value in the rebuilt .prev/ too — so a manual rollback
#     right after such a double failure may be a no-op for that one item; deploying again fixes it.
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

  # A crash while building the previous config's backup always leaves .prev.new/ behind, never a
  # partially written .prev/: discard it unconditionally before anything else runs.
  rm -rf .prev.new

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

  # True (status 0) if every item in .incoming/ is byte-identical to the live item; both sides missing
  # counts as identical too. False as soon as one item differs.
  items_identical() {
    local item
    for item in "${config_items[@]}"; do
      if [[ -e "$item" && -e ".incoming/$item" ]]; then
        diff -rq "$item" ".incoming/$item" >/dev/null 2>&1 || return 1
      elif [[ -e "$item" || -e ".incoming/$item" ]]; then
        return 1
      fi
    done
    return 0
  }

  # A live item can be missing here only if a previous run crashed after removing it but before moving
  # its replacement in from .incoming/ (see the header comment). Heal it from .prev/ before staging is
  # attempted again, so stage_config never backs up a "live" config with a hole in it.
  heal_missing_live_items() {
    if [[ -d .incoming && -d .prev ]]; then
      local item
      for item in "${config_items[@]}"; do
        if [[ ! -e "$item" && -e ".prev/$item" ]]; then
          cp -a ".prev/$item" "./$item"
        fi
      done
    fi
  }

  # Moves the current four items into .prev/ (replacing any older .prev/), then moves .incoming/'s
  # items into place. A no-op if deploy.yml did not stage anything (no .incoming/), which keeps every
  # caller that never creates .incoming/ byte-for-byte identical to before this change. Also a no-op
  # beyond discarding .incoming/ when the staged config is identical to the live one, so redeploying
  # the same config (only a new image) never disturbs .prev/.
  stage_config() {
    if [[ -d .incoming ]]; then
      if items_identical; then
        rm -rf .incoming
        return
      fi
      rm -rf .prev.new
      mkdir .prev.new
      local item
      for item in "${config_items[@]}"; do
        if [[ -e "$item" ]]; then cp -a "$item" ".prev.new/$item"; fi
      done
      rm -rf .prev
      mv .prev.new .prev
      for item in "${config_items[@]}"; do
        if [[ -e ".incoming/$item" ]]; then
          rm -rf "./$item"
          mv ".incoming/$item" "./$item"
        fi
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

  service_health() {
    local service="$1" id
    id="$(docker compose ps -q "$service")"
    if [[ -z "$id" ]]; then
      echo missing
      return
    fi
    docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id"
  }

  all_healthy() {
    local service
    for service in relay web; do
      if [[ "$(service_health "$service")" != healthy ]]; then
        return 1
      fi
    done
    return 0
  }

  wait_healthy() {
    local deadline=$((SECONDS + health_timeout))
    while ((SECONDS < deadline)); do
      if all_healthy; then return 0; fi
      sleep 2
    done
    return 1
  }

  # Best effort: never fails the deploy. Keeps images newer than a week (the tag just deployed, the
  # one just rolled back from, and anything else recent); every older ShellX image built by an earlier
  # deploy is removed, so the VPS disk does not fill up over time.
  prune_old_images() {
    docker image prune -af \
      --filter "label=org.opencontainers.image.source=https://github.com/lephus/shellx" \
      --filter "until=168h" >/dev/null 2>&1 || true
  }

  heal_missing_live_items

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
  # A `compose up -d` that fails outright (bad network, volume, daemon hiccup) is treated exactly like
  # an unhealthy service: it falls straight into the rollback branch below. --force-recreate recreates
  # every container, not only the ones whose own config changed (see the header comment).
  if docker compose up -d --remove-orphans --force-recreate && wait_healthy; then
    echo "relay and web are healthy on $new_tag"
    prune_old_images
    exit 0
  fi

  echo "::error::relay/web not healthy within ${health_timeout}s on $new_tag; rolling back to ${old_tag:-nothing} (see why on the VPS: docker compose logs --tail 50 relay web)" >&2
  restore_config
  if [[ -n "$old_tag" ]]; then
    set_tag "$old_tag"
    if ! docker compose up -d --remove-orphans --force-recreate || ! wait_healthy; then
      echo "::error::the previous release ($old_tag) is not healthy either" >&2
    fi
  fi
  exit 1
}

main "$@"
