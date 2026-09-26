# Deploying ShellX to the VPS

Everything ShellX puts on the VPS lives in **one folder, `~/phu/shellx`**, in the home of the SSH
user that deploys (decision V8, `docs/superpowers/specs/2026-09-26-shellx-vps-infra-design.md`).
The only exception is four small files copied once into nginx-proxy's `vhost.d` directory (step 5).

```
~/phu/shellx/
  docker-compose.yml     # from deploy/docker-compose.yml (compose project "shellx")
  relay.env              # from deploy/relay.env (versions, download links; no secrets)
  .env                   # IMAGE_TAG (written by deploy.yml) and PROXY_NETWORK (written by you, once)
  data/relay.db          # the SQLite database (bind mount ./data:/data, owned by uid 1000)
  backups/relay-<YYYY-MM-DD>.db   # daily at 03:00, the 14 newest are kept
  downloads/desktop/<version>/    # installers, uploaded by release-desktop.yml
  nginx-proxy/           # from deploy/nginx-proxy/: the originals of the vhost.d files (step 5)
  backup/                # from deploy/backup/: the backup container's scripts
  .incoming/             # deploy.yml stages docker-compose.yml, relay.env, nginx-proxy/, backup/
                         # here before rollout.sh swaps them into place (transient)
  .prev/                 # the four items above, as they were before the last deploy that CHANGED
                         # them (a code-only deploy leaves it alone, so it can be older — R3)
  .prev.new/             # rollout.sh builds .prev/'s replacement here first, so a crash mid-swap
                         # never leaves a partially written .prev/ (transient; see rollout.sh's header)
```

| Container | Image | What it does |
|---|---|---|
| `relay` | `ghcr.io/lephus/shellx-relay:<commit>` | `relay.shellx.pro` (REST + WebSocket), port 8080 on the proxy network only |
| `web` | `ghcr.io/lephus/shellx-web:<commit>` | `shellx.pro`, `www.shellx.pro` (→ `shellx.pro`), `download.shellx.pro` |
| `backup` | `alpine:3.22` + sqlite | `sqlite3 .backup` of `data/relay.db` every day at 03:00 VPS time |

Pushing to `main` a change under `relay/`, `web/`, `deploy/` or `.github/workflows/deploy.yml` runs
`.github/workflows/deploy.yml`: build both images (the relay build runs every relay test; the web
build refuses the `[quốc gia]` placeholder, checks pages and links, and `nginx -t`-validates its
nginx config), a cheap preflight (the compose file resolves, and the freshly built relay image's
config loads from `deploy/relay.env`), push both images to GHCR, rsync `docker-compose.yml`,
`relay.env`, `nginx-proxy/` and `backup/` into `~/phu/shellx/.incoming/` (a staging folder, still
inside the app dir), then run `deploy/rollout.sh` over SSH: swap `.incoming/` into place (moving the
current four items into `~/phu/shellx/.prev/` first, unless the staged config is byte-identical to
the live one, in which case neither is touched — M5), pull, set `IMAGE_TAG`, `docker compose up -d
--remove-orphans --force-recreate` (so every container is recreated, not only the ones whose own
config changed — this is what keeps the `backup` container's bind mount fresh across deploys — C2),
wait up to 60 s for BOTH the relay's and the web's healthcheck (M3). If the pull fails, or either
service never turns healthy, it puts back the config it swapped in — only if this deploy swapped one
(so a bad `relay.env` or `docker-compose.yml` never outlives its `IMAGE_TAG`, while a failed code-only
deploy leaves the live config and `.prev/` alone instead of restoring an older, stale `.prev/` — R3)
— and, on the health failure path, the previous `IMAGE_TAG` too, recreating the `backup` container
after any restore (its bind-mounted `backup/` was replaced). It prints only a hint to check the logs
on the VPS yourself, never the logs' own content, into the Actions output (M11). On success it best-effort prunes old ShellX images (I4). A `workflow_dispatch` run is
refused unless the requested `ref` is already an ancestor of `origin/main` (M2), so it can only
deploy code that has actually been merged. Finally it checks `https://relay.shellx.pro/v1/version`
and `https://shellx.pro/`.

## First-time setup

Do this after the DNS A records of `shellx.pro`, `www`, `relay` and `download` point at the VPS:
letsencrypt-companion can only get certificates for names that resolve to it. Run the commands on
the VPS as the deploy user unless a step says otherwise.

1. **Prerequisites, deploy user and folder.** On the VPS, check the tools rollout.sh and the backup
   container need:

   ```bash
   docker compose version   # must print "Docker Compose version v2...."; v1 (docker-compose) is not
                             # enough (rollout.sh uses `docker compose ... --force-recreate`)
   rsync --version | head -1
   umask                     # the default 022 is fine; the commands below tighten data/ and backups/
                              # to 700 regardless of it
   ```

   Use an existing user or create one (`sudo adduser shellx`); it must be in the `docker` group
   (`sudo usermod -aG docker <user>`, then log in again). On your own machine, create a key used only
   for deploys: `ssh-keygen -t ed25519 -f shellx-deploy -C shellx-deploy -N ''`, and append
   `shellx-deploy.pub` to the deploy user's `~/.ssh/authorized_keys`. Then, on the VPS:

   ```bash
   mkdir -p ~/phu/shellx/{data,backups,downloads/desktop,nginx-proxy,backup}
   sudo chown 1000:1000 ~/phu/shellx/data      # the relay runs as uid 1000 (node) and must write here
   sudo chmod 700 ~/phu/shellx/data            # sudo: data/ now belongs to uid 1000, not to you
   chmod 700 ~/phu/shellx/backups
     # Both hold the database or its backups, which carry user emails and password hashes (M9).
     # uid 1000 still owns and can write data/, and the backup container (it runs as root inside its
     # own container) can still read and write both.
   ```
2. **Proxy network.** Find the Docker network of nginx-proxy (`docker network ls`; it is the network
   the `nginx-proxy` container is attached to, see `docker inspect nginx-proxy`) and record it:

   ```bash
   echo "PROXY_NETWORK=<that network name>" > ~/phu/shellx/.env
   ```
3. **GitHub.** On your machine run `ssh-keyscan -t ed25519 <VPS address>` and compare the printed key
   with the VPS's own `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` fingerprint (`ssh-keygen -lf -`
   on the scanned line). Then, in the repository:
   - Settings → Environments → **New environment** → name `production` → **Deployment branches and
     tags** → **Selected branches and tags** → add `main` (the `deploy` job declares
     `environment: production`, so only a run on `main` can read what you add next).
   - Add as **Environment secrets** of `production`: `VPS_HOST` (address), `VPS_USER` (deploy user),
     `VPS_SSH_KEY` (the whole private key file `shellx-deploy`), `VPS_KNOWN_HOSTS` (the verified
     `ssh-keyscan` line). Add as **Environment variables** of `production`: `VPS_APP_DIR` =
     `phu/shellx` (optional: that is the default; relative to the deploy user's home) and, only if
     sshd on the VPS does not listen on the default port 22, `VPS_SSH_PORT` (digits only; both
     workflows validate it and refuse anything else).
   - Repeat the same four secrets and the two variables on the existing `release` Environment (see
     `release/README.md`): `release-desktop.yml`'s `publish` job uploads installers to the same VPS
     and needs them too. None of these are **repository** secrets or variables.
   - Remove the old `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` secrets.
4. **First deploy.** Push to `main` or run **Actions → Deploy → Run workflow**. The first run pushes
   the two images to GHCR as *private* packages, so the VPS cannot pull them and the run fails at
   the pull step. Make both public once — github.com/lephus → Packages → `shellx-relay` and
   `shellx-web` → Package settings → Change visibility → Public (they contain no secrets) — then
   re-run the workflow.
5. **nginx-proxy settings (the only files outside the folder).** After the first deploy synced
   `~/phu/shellx/nginx-proxy/`, copy its four files into nginx-proxy's `vhost.d` directory, then
   recreate the ShellX containers so nginx-proxy regenerates its configuration:

   ```bash
   PROXY=nginx-proxy   # the name of the nginx-proxy container (docker ps)
   VHOST_D="$(docker inspect "$PROXY" --format '{{range .Mounts}}{{if eq .Destination "/etc/nginx/vhost.d"}}{{.Source}}{{end}}{{end}}')"
   echo "$VHOST_D"     # must print a directory; stop here if it is empty
   for f in relay.shellx.pro shellx.pro www.shellx.pro download.shellx.pro; do
     target="$VHOST_D/$f"
     if [ -e "$target" ] && grep -q 'access_log off' "$target"; then
       echo "$target already has our lines; leaving it alone (edit it by hand if deploy/nginx-proxy/$f changed)"
     elif [ -e "$target" ]; then
       echo "$target already exists WITHOUT our lines (it is very likely only the letsencrypt companion's own ACME block) -- merge ~/phu/shellx/nginx-proxy/$f into it BY HAND, keeping that block; do not overwrite it"
     else
       sudo cp ~/phu/shellx/nginx-proxy/$f "$target"
     fi
   done
   cd ~/phu/shellx && docker compose up -d --force-recreate relay web
   docker exec "$PROXY" nginx -T 2>/dev/null | grep -A3 'server_name relay.shellx.pro' | head   # shows the include
   ```

   Copy, do not symlink: a link to `~/phu/shellx/...` would point nowhere inside the proxy
   container. A plain `nginx -s reload` is not enough either: nginx-proxy only includes
   `vhost.d/<host>` if the file existed when it last generated its configuration, which it does on
   container start/stop events. The letsencrypt companion may append its own
   `## Start of configuration add by letsencrypt container` block to these files; the loop above never
   overwrites a file that already exists without our `access_log off` marker line, precisely so that
   block is never clobbered — it tells you to merge by hand instead (M7). These files turn access logs
   off for the four names (the privacy policy promises no access logs), give the relay's WebSockets
   120 s timeouts and cap request bodies at 32 KiB. If `deploy/nginx-proxy/` ever changes, edit the
   copies in `vhost.d` the same way (keeping the companion's block) and recreate the containers again.
6. **Check.**

   ```bash
   curl https://relay.shellx.pro/v1/version
   curl -sI https://shellx.pro/ | head -1                   # HTTP/2 200
   curl -sI https://www.shellx.pro/privacy/ | grep -i ^location   # https://shellx.pro/privacy/
   docker compose -f ~/phu/shellx/docker-compose.yml ps     # relay (healthy), web (healthy), backup
   ```

   **nginx-proxy's HTTP→HTTPS redirect still logs client IPs (I3).** `deploy/nginx-proxy/shellx.pro`
   (and the other three files) turn `access_log off` for the HTTPS server block only — that is the
   only block nginx-proxy includes them into. Port 80 answers with its own, separate redirect server
   block (shared by every site behind this nginx-proxy), which keeps its default access log. We
   cannot safely change that shared, un-owned block from ShellX's files alone. Verify what your proxy
   actually does:

   ```bash
   docker exec "$PROXY" nginx -T 2>/dev/null | grep -n -B3 -A8 'server_name shellx.pro'   # the :80
     # block above the :443 one has no "access_log off" — that is the gap
   curl -sI http://shellx.pro/            # a plain HTTP request; nginx-proxy logs this one
   docker logs --tail 3 "$PROXY"          # the request you just made, with your client IP
   ```

   Pick one (this is your decision, not something the code can decide for you):
   - Set `DISABLE_ACCESS_LOGS=true` on the `nginx-proxy` container itself — turns logging off for
     *every* site behind it, including any you might add later that does want logs.
   - Disclose in the privacy policy that a bare `http://` request's client IP is logged briefly before
     the redirect (`web/src/pages/{,en/}privacy.md`), leaving the shared block as is.
   - Bound `nginx-proxy`'s own log retention (its `docker-compose.yml`/`logging:` block, outside
     `~/phu/shellx`) instead of turning logging off.
   This is tracked as an open item for you in `docs/superpowers/HANDOFF.md` §4; the privacy policy
   text is not changed until you pick one.

The website only builds once the country hosting the VPS replaces `[quốc gia]` in
`web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`, `web/src/pages/terms.md` and
`web/src/pages/en/terms.md` (update their `updated:` dates too). Until then every deploy stops at the
web image build, so fill it in before the first deploy.

## Operations

All commands run in `~/phu/shellx`.

- **Logs:** `docker compose logs -f relay` (metadata only: time, `device_id`, error kind; never IPs,
  e-mail addresses, tokens or payloads). Docker keeps at most 3 × 10 MB per container.
- **Roll back:** Actions → Deploy → Run workflow with `ref` = an older, full 40-character commit SHA
  that is already an ancestor of `main` (the workflow refuses anything else — M2; images are rebuilt
  from that commit; this also re-stages and re-swaps `docker-compose.yml`, `relay.env`, `nginx-proxy/`
  and `backup/` as they were at that commit), or on the VPS set `IMAGE_TAG=<older sha>` in `.env` and
  run `docker compose up -d --force-recreate` (this alone does not touch the four config items). Images of every
  deployed commit stay in GHCR (the VPS's local Docker cache only keeps images from the last 7 days
  after a healthy deploy — see "Disk usage" below — so an older rollback may need to re-pull). A
  failed automatic rollout already restores the config it swapped in and the previous `IMAGE_TAG` on
  its own (see above); to redo that by hand after a *successful* deploy you regret, on the VPS: `cd
  ~/phu/shellx && for f in docker-compose.yml relay.env nginx-proxy backup; do [ -e ".prev/$f" ] &&
  rm -rf "$f" && mv ".prev/$f" "./$f"; done` (the `[ -e ".prev/$f" ]` guard skips any item `.prev/`
  does not have, instead of deleting the live item and then failing to restore it — M5) and set
  `IMAGE_TAG` back in `.env`, then `docker compose up -d --remove-orphans --force-recreate`.
  **Check `.prev/` first:** it holds the config from before the last deploy that *changed* the config,
  not necessarily from before the last deploy — code-only deploys leave it alone, so after a few of
  them it can be much older than the release you are rolling back to. Compare before restoring
  (`for f in docker-compose.yml relay.env nginx-proxy backup; do diff -r ".prev/$f" "$f"; done`);
  if it is not the config you want, roll back with the workflow instead (it re-stages the config of
  the chosen commit).
- **Versions and download links:** edit `deploy/relay.env` and push `main`.
- **Emergency password reset:** see `relay/README.md` (`docker compose exec relay node dist/scripts/reset-password.js …`).
- **Backups:** `backups/relay-<date>.db`, written at 03:00 VPS time (mode 0600 — `umask 077` in
  `backup-once.sh`, M9), the 14 newest are kept. The backup container runs as root, so
  `backup-once.sh` hands each finished file to the owner of `backups/` (the deploy user) — readable by
  that user only, never by anyone else. The backup reads the live database through a read-only mount,
  which needs the relay running; while the relay is stopped the backup is skipped (`docker compose
  logs backup` says so) and nothing is lost, since a stopped relay changes nothing. Copy them off the
  VPS as the deploy user if you like, e.g. from your machine: `rsync -a
  <deploy-user>@<vps>:phu/shellx/backups/ ./shellx-backups/` (no sudo needed; if `docker compose logs
  backup` ever says a file "stays root's", use `ssh <deploy-user>@<vps> sudo cat
  phu/shellx/backups/relay-<date>.db > relay-<date>.db` for that one, which needs passwordless sudo)
  — and delete copies older than 14 days, because the privacy policy says deleted data survives in
  backups for at most 14 days.
- **Backup freshness:** `ls -lt backups | head -2` should always show a file from within the last day
  or two. If it does not, the nightly cron stopped running — check `docker compose logs backup`. This
  used to fail silently from the third deploy on, because `docker compose up -d` (without
  `--force-recreate`) never recreated the `backup` container even though its bind-mounted `backup/`
  scripts had changed underneath it; `rollout.sh` now always passes `--force-recreate` (C2), and
  recreates `backup` alone after a restore that no full restart follows (a failed pull — R3). If you
  ever swap `backup/` by hand, run `docker compose up -d --no-deps --force-recreate backup` too.
- **Restore a backup:**

  ```bash
  docker compose stop relay
  sudo install -o 1000 -g 1000 -m 0640 backups/relay-2026-10-01.db data/relay.db
  sudo rm -f data/relay.db-wal data/relay.db-shm
  docker compose start relay
  ```

  (`install` creates `data/relay.db` already owned by uid 1000 and mode 0640, in one step — plain
  `cp` instead would leave it owned by whichever user ran the command, which breaks the relay if the
  deploy user is not uid 1000 — I2.)
- **Rebuild on a new VPS:** repeat the first-time setup, restore the newest backup to `data/relay.db`
  (as above) and copy the installers to `downloads/`, then re-run the Deploy workflow.
- **Disk usage:** `docker system df` shows how much space images, containers and volumes use. After
  every healthy deploy, `rollout.sh` best-effort removes ShellX images (`org.opencontainers.image.source`
  label) older than 7 days, so a failure to prune never fails the deploy itself (I4); it does not
  touch anything else `docker system df` reports (build cache, unrelated images, volumes).

## Tests of the deploy scripts

`node --test deploy/tests/*.test.mjs` runs `rollout.sh` against a fake `docker` (health of both
relay and web, rollback, pull failure, missing `PROXY_NETWORK`, wrong `data/` owner, staging and
restoring `.incoming/`/`.prev/` config, restoring only a config this run swapped in, recreating
`backup` after a restore, `--force-recreate` on the rollback too, skipping a no-op restage,
recovering from a crash mid-swap, pruning images only after success) and `backup/backup-once.sh`
with the local `sqlite3` (rotation, missing and unreadable databases, 0600 file mode, handing each
file to the owner of `backups/`).
