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
  .prev/                 # the four items above, as they were before the last swap (manual rollback)
```

| Container | Image | What it does |
|---|---|---|
| `relay` | `ghcr.io/lephus/shellx-relay:<commit>` | `relay.shellx.pro` (REST + WebSocket), port 8080 on the proxy network only |
| `web` | `ghcr.io/lephus/shellx-web:<commit>` | `shellx.pro`, `www.shellx.pro` (→ `shellx.pro`), `download.shellx.pro` |
| `backup` | `alpine:3.22` + sqlite | `sqlite3 .backup` of `data/relay.db` every day at 03:00 VPS time |

Pushing to `main` a change under `relay/`, `web/`, `deploy/` or `.github/workflows/deploy.yml` runs
`.github/workflows/deploy.yml`: build both images (the relay build runs every relay test; the web
build refuses the `[quốc gia]` placeholder and checks pages and links), a cheap preflight (the
compose file resolves, and the freshly built relay image's config loads from `deploy/relay.env`),
push both images to GHCR, rsync `docker-compose.yml`, `relay.env`, `nginx-proxy/` and `backup/` into
`~/phu/shellx/.incoming/` (a staging folder, still inside the app dir), then run
`deploy/rollout.sh` over SSH: swap `.incoming/` into place (moving the current four items into
`~/phu/shellx/.prev/` first), pull, set `IMAGE_TAG`, `docker compose up -d --remove-orphans`, wait
up to 60 s for the relay's healthcheck. If the pull fails, or the relay never turns healthy, it
restores `.prev/` (so a bad `relay.env` or `docker-compose.yml` never outlives its `IMAGE_TAG`) and,
on the health failure path, the previous `IMAGE_TAG` too. Finally it checks
`https://relay.shellx.pro/v1/version` and `https://shellx.pro/`.

## First-time setup

Do this after the DNS A records of `shellx.pro`, `www`, `relay` and `download` point at the VPS:
letsencrypt-companion can only get certificates for names that resolve to it. Run the commands on
the VPS as the deploy user unless a step says otherwise.

1. **Deploy user and folder.** Use an existing user or create one (`sudo adduser shellx`); it must be
   in the `docker` group (`sudo usermod -aG docker <user>`, then log in again). On your own machine,
   create a key used only for deploys: `ssh-keygen -t ed25519 -f shellx-deploy -C shellx-deploy -N ''`,
   and append `shellx-deploy.pub` to the deploy user's `~/.ssh/authorized_keys`. Then, on the VPS:

   ```bash
   mkdir -p ~/phu/shellx/{data,backups,downloads/desktop,nginx-proxy,backup}
   sudo chown 1000:1000 ~/phu/shellx/data      # the relay runs as uid 1000 (node) and must write here
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
     `ssh-keyscan` line). Add as an **Environment variable** of `production`: `VPS_APP_DIR` =
     `phu/shellx` (optional: that is the default; relative to the deploy user's home).
   - Repeat the same four secrets and the variable on the existing `release` Environment (see
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
     sudo cp ~/phu/shellx/nginx-proxy/$f "$VHOST_D/$f"
   done
   cd ~/phu/shellx && docker compose up -d --force-recreate relay web
   docker exec "$PROXY" nginx -T 2>/dev/null | grep -A3 'server_name relay.shellx.pro' | head   # shows the include
   ```

   Copy, do not symlink: a link to `~/phu/shellx/...` would point nowhere inside the proxy
   container. A plain `nginx -s reload` is not enough either: nginx-proxy only includes
   `vhost.d/<host>` if the file existed when it last generated its configuration, which it does on
   container start/stop events. The letsencrypt companion may append its own
   `## Start of configuration add by letsencrypt container` block to these files; keep it. These
   files turn access logs off for the four names (the privacy policy promises no access logs), give
   the relay's WebSockets 120 s timeouts and cap request bodies at 32 KiB. If `deploy/nginx-proxy/`
   ever changes, edit the copies in `vhost.d` the same way (keeping the companion's block) and
   recreate the containers again.
6. **Check.**

   ```bash
   curl https://relay.shellx.pro/v1/version
   curl -sI https://shellx.pro/ | head -1                   # HTTP/2 200
   curl -sI https://www.shellx.pro/privacy/ | grep -i ^location   # https://shellx.pro/privacy/
   docker compose -f ~/phu/shellx/docker-compose.yml ps     # relay (healthy), web, backup
   ```

The website only builds once the country hosting the VPS replaces `[quốc gia]` in
`web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`, `web/src/pages/terms.md` and
`web/src/pages/en/terms.md` (update their `updated:` dates too). Until then every deploy stops at the
web image build, so fill it in before the first deploy.

## Operations

All commands run in `~/phu/shellx`.

- **Logs:** `docker compose logs -f relay` (metadata only: time, `device_id`, error kind; never IPs,
  e-mail addresses, tokens or payloads). Docker keeps at most 3 × 10 MB per container.
- **Roll back:** Actions → Deploy → Run workflow with `ref` = an older, full 40-character commit SHA
  (images are rebuilt from that commit; this also re-stages and re-swaps `docker-compose.yml`,
  `relay.env`, `nginx-proxy/` and `backup/` as they were at that commit), or on the VPS set
  `IMAGE_TAG=<older sha>` in `.env` and run `docker compose up -d` (this alone does not touch the
  four config items). Images of every deployed commit stay in GHCR. A failed automatic rollout
  already restores `~/phu/shellx/.prev/` and the previous `IMAGE_TAG` on its own (see above); to redo
  that by hand after a *successful* deploy you regret, on the VPS: `cd ~/phu/shellx && for f in
  docker-compose.yml relay.env nginx-proxy backup; do rm -rf "$f" && mv ".prev/$f" "./$f"; done` and
  set `IMAGE_TAG` back in `.env`, then `docker compose up -d --remove-orphans`.
- **Versions and download links:** edit `deploy/relay.env` and push `main`.
- **Emergency password reset:** see `relay/README.md` (`docker compose exec relay node dist/scripts/reset-password.js …`).
- **Backups:** `backups/relay-<date>.db`, written at 03:00 VPS time; the 14 newest are kept. The
  backup reads the live database through a read-only mount, which needs the relay running; while
  the relay is stopped the backup is skipped (`docker compose logs backup` says so) and nothing is
  lost, since a stopped relay changes nothing. Copy them off the VPS if you like, e.g. from your
  machine: `rsync -a <user>@<vps>:phu/shellx/backups/ ./shellx-backups/` — and delete copies older
  than 14 days, because the privacy policy says deleted data survives in backups for at most 14 days.
- **Restore a backup:**

  ```bash
  docker compose stop relay
  cp backups/relay-2026-10-01.db data/relay.db && rm -f data/relay.db-wal data/relay.db-shm
  sudo chown 1000:1000 data/relay.db
  docker compose start relay
  ```
- **Rebuild on a new VPS:** repeat the first-time setup, copy the newest backup to `data/relay.db`
  (as above) and the installers to `downloads/`, then re-run the Deploy workflow.

## Tests of the deploy scripts

`node --test deploy/tests/*.test.mjs` runs `rollout.sh` against a fake `docker` (health, rollback,
pull failure, missing `PROXY_NETWORK`, wrong `data/` owner, staging and restoring `.incoming/`/
`.prev/` config) and `backup/backup-once.sh` with the local `sqlite3` (rotation, missing and
unreadable databases).
