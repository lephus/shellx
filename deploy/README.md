# Deploying ShellX to the VPS

Everything ShellX puts on the VPS lives in **one folder, `~/phu/shellx`**, in the home of the SSH
user that deploys (decision V8, `docs/superpowers/specs/2026-09-26-shellx-vps-infra-design.md`).
The only exception is five small files copied once into nginx-proxy's `vhost.d` directory (step 5).

```
~/phu/shellx/
  docker-compose.yml     # from deploy/docker-compose.yml (compose project "shellx")
  relay.env              # from deploy/relay.env (versions, download links; no secrets)
  .env                   # IMAGE_TAG (written by deploy.yml), PROXY_NETWORK and, for push and
                         # admin, FCM_SERVICE_ACCOUNT and ADMIN_PASSWORD (written by you, once)
  secrets/fcm.json       # Firebase service account key (push; by hand, never synced — see below)
  data/relay.db          # the SQLite database (bind mount ./data:/data, owned by uid 1000)
  backups/relay-<YYYY-MM-DD>.db   # daily at 03:00, the 14 newest are kept
  downloads/desktop/<version>/    # installers, uploaded by release-desktop.yml
  nginx-proxy/           # from deploy/nginx-proxy/: the originals of the vhost.d files (step 5)
  backup/                # from deploy/backup/: the backup container's scripts
  .incoming/             # deploy.yml stages docker-compose.yml, relay.env, nginx-proxy/, backup/
                         # here before rollout.sh swaps them into place (transient)
  .build-src/<sha>/      # only vps-deploy.sh (no Actions): the sources the images are built from;
                         # removed after a good deploy (transient)
  .prev/                 # the four items above, as they were before the last deploy that CHANGED
                         # them (a code-only deploy leaves it alone, so it can be older — R3)
  .prev.new/             # rollout.sh builds .prev/'s replacement here first, so a crash mid-swap
                         # never leaves a partially written .prev/ (transient; see rollout.sh's header)
```

| Container | Image | What it does |
|---|---|---|
| `relay` | `ghcr.io/lephus/shellx-relay:<commit>` | `relay.shellx.pro` (REST + WebSocket) and `admin.shellx.pro` (admin dashboard, by Host header), port 8080 on the proxy network only |
| `web` | `ghcr.io/lephus/shellx-web:<commit>` | `shellx.pro`, `www.shellx.pro` (→ `shellx.pro`), `download.shellx.pro` |
| `backup` | `alpine:3.22` + sqlite | `sqlite3 .backup` of `data/relay.db` every day at 03:00 VPS time |

(Without GitHub Actions the same deploy runs from the Mac: see "Deploying without GitHub Actions".)
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
deploy code that has actually been merged. Finally it checks `https://relay.shellx.pro/v1/version`,
`https://shellx.pro/` and `https://admin.shellx.pro/api/session`.

## First-time setup

Do this after the DNS A records of `shellx.pro`, `www`, `relay`, `admin` and `download` point at the VPS:
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
   - `release-desktop.yml`'s `publish` job uploads installers to the same VPS with these same
     `production` secrets and variables (see `release/README.md`). None of these are
     **repository** secrets or variables.
   - Remove the old `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` secrets.
4. **First deploy.** Push to `main` or run **Actions → Deploy → Run workflow**. The first run pushes
   the two images to GHCR as *private* packages, so the VPS cannot pull them and the run fails at
   the pull step. Make both public once — github.com/lephus → Packages → `shellx-relay` and
   `shellx-web` → Package settings → Change visibility → Public (they contain no secrets) — then
   re-run the workflow.
5. **nginx-proxy settings (the only files outside the folder).** After the first deploy synced
   `~/phu/shellx/nginx-proxy/`, copy its five files into nginx-proxy's `vhost.d` directory, then
   recreate the ShellX containers so nginx-proxy regenerates its configuration:

   ```bash
   PROXY=nginx-proxy   # the name of the nginx-proxy container (docker ps)
   VHOST_D="$(docker inspect "$PROXY" --format '{{range .Mounts}}{{if eq .Destination "/etc/nginx/vhost.d"}}{{.Source}}{{end}}{{end}}')"
   echo "$VHOST_D"     # must print a directory; stop here if it is empty
   for f in relay.shellx.pro admin.shellx.pro shellx.pro www.shellx.pro download.shellx.pro; do
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
   off for the five names (the privacy policy promises no access logs), give the relay's WebSockets
   120 s timeouts and cap request bodies at 32 KiB (16 KiB for admin). If `deploy/nginx-proxy/` ever
   changes, edit the copies in `vhost.d` the same way (keeping the companion's block) and recreate
   the containers again.
6. **Check.**

   ```bash
   curl https://relay.shellx.pro/v1/version
   curl https://admin.shellx.pro/api/session                # {"enabled":false,...} until "Admin" below
   curl -sI https://shellx.pro/ | head -1                   # HTTP/2 200
   curl -sI https://www.shellx.pro/privacy/ | grep -i ^location   # https://shellx.pro/privacy/
   docker compose -f ~/phu/shellx/docker-compose.yml ps     # relay (healthy), web (healthy), backup
   ```

   **nginx-proxy's HTTP→HTTPS redirect still logs client IPs (I3).** `deploy/nginx-proxy/shellx.pro`
   (and the other four files) turn `access_log off` for the HTTPS server block only — that is the
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

## Push notifications (once, by hand)

The relay sends push notifications through Firebase Cloud Messaging only when it has a service
account key; without one it runs normally and push is simply off (`docker compose logs relay` shows
`push_disabled` once at startup).

1. In the Firebase console of project `shellxpro`: Project settings → Service accounts → **Generate
   new private key** (a JSON file). Keep it secret: anyone holding it can send notifications to
   your phones. (APNs for iOS: Project settings → Cloud Messaging → Apple app → upload the `.p8` key.)
2. Put it on the VPS, readable by the relay's uid 1000 only, in the folder that is **never** synced
   by deploys:

   ```bash
   # Docker creates ./secrets as root if the relay started before it existed: take it back first.
   sudo mkdir -p ~/phu/shellx/secrets
   sudo chown <deploy-user>:<deploy-user> ~/phu/shellx/secrets && sudo chmod 755 ~/phu/shellx/secrets
   # A private upload folder in your home (never /tmp: world-listable, default file mode)
   mkdir -m 700 -p ~/fcm-upload
   # from your machine: scp fcm.json <deploy-user>@<vps>:fcm-upload/fcm.json
   sudo install -o 1000 -g 1000 -m 400 ~/fcm-upload/fcm.json ~/phu/shellx/secrets/fcm.json
   rm -rf ~/fcm-upload
   echo "FCM_SERVICE_ACCOUNT=/secrets/fcm.json" >> ~/phu/shellx/.env
   cd ~/phu/shellx && docker compose up -d --force-recreate relay
   docker compose logs relay | grep push_   # push_enabled {"project":"shellxpro"}
   ```

   `docker-compose.yml` mounts `./secrets` read-only at `/secrets` and passes `FCM_SERVICE_ACCOUNT`
   from `.env` (rollout.sh keeps every `.env` line except `IMAGE_TAG`). To turn push off, remove the
   line and recreate the relay. **Rotating the key:** create a new key in the Firebase console, copy it
   into `~/fcm-upload/` on the VPS as above (`mkdir -m 700 -p ~/fcm-upload` first), then `sudo install -o
   1000 -g 1000 -m 400 ~/fcm-upload/fcm.json ~/phu/shellx/secrets/fcm.json && rm -rf ~/fcm-upload` (the file is read-only and owned by uid 1000,
   so a plain `cp` over it fails), `docker compose up -d --force-recreate relay`, and delete the old
   key in the console.

### iPhone push (APNs)

The native iPhone app gets its alerts straight from APNs: the Mac calls `POST /v2/notifications`,
and the relay signs with an APNs provider key (Apple Developer → Keys, team `W4RF3W4VTZ`, Apple Push
Notifications service enabled). Without it the relay runs normally and logs `apns_disabled`.

```bash
mkdir -m 700 -p ~/apns-upload
# from your machine: scp AuthKey_<KEYID>.p8 <deploy-user>@<vps>:apns-upload/apns.p8
sudo install -o 1000 -g 1000 -m 400 ~/apns-upload/apns.p8 ~/phu/shellx/secrets/apns.p8
rm -rf ~/apns-upload
printf 'APNS_KEY_PATH=/secrets/apns.p8\nAPNS_KEY_ID=<KEYID>\nAPNS_TEAM_ID=W4RF3W4VTZ\n' >> ~/phu/shellx/.env
cd ~/phu/shellx && docker compose up -d --force-recreate relay
docker compose logs relay | grep apns_   # apns_enabled
```

One key serves both APNs hosts: Debug builds (`com.shellx.dev`) register sandbox tokens, App Store
builds (`com.shellx.prod`) production ones, and the relay sends each token to its own host.

### Android push (FCM)

The Android app gets its "needs you" alerts from the same `POST /v2/notifications` call that
reaches iPhones: the relay sends each Android phone granted that Mac an FCM data-only message with
the service account key above. Nothing else is set up on the VPS. Check it after a deploy:

```bash
cd ~/phu/shellx && docker compose logs relay | grep push_   # push_enabled {"project":"shellxpro"}
```

With `push_disabled` instead, Android phones get nothing (iPhones still get APNs): do steps 1–2
above. Both Android apps, `com.shellx.prod` and `com.shellx.dev`, must be apps of Firebase project
`shellxpro`; FCM refuses a token from another project (`fcm_send_failed` with `SENDER_ID_MISMATCH`)
and the relay keeps such a token. `POST /v2/notifications` answers 503 `push_unavailable` only when
both the FCM and the APNs key are missing. Each call logs one `v2_notification` line with
`recipients`, `fcm_recipients`, `sent` and `tokens_removed`, never what the alert says or a token.

The website only builds once the country hosting the VPS replaces `[quốc gia]` in
`web/src/pages/privacy.md` and `web/src/pages/terms.md` (update their `updated:` dates too). Until
then every deploy stops at the web image build, so fill it in before the first deploy.

## Sign in with Google and Apple (once, by hand)

The relay checks Google and Apple ID tokens against their published keys (S1 §6.2) and, for an Apple
ID, exchanges the iPhone's authorization code for a refresh token so it can revoke ShellX's access when
the Apple ID is removed or the account deleted. All of it is set once by hand in the VPS's `.env`
(never in this repository):

- `GOOGLE_CLIENT_IDS`: the iOS clients of `com.shellx.prod` and `com.shellx.dev`, the Web client
  (Android's `serverClientId`) and the Desktop client, comma-separated, no spaces. Without it every
  Google sign-in answers 401 and the relay logs `google_sign_in_disabled`.
- `APPLE_TEAM_ID=W4RF3W4VTZ`
- `APPLE_SIWA_KEY_ID=<key id>`
- `APPLE_SIWA_KEY_PATH=/secrets/siwa.p8`: a key with Sign in with Apple enabled (it may be the APNs key
  if that key has both services). Without the key the relay logs `apple_siwa_disabled`: Apple sign-in
  itself works, but no refresh token is stored and nothing is revoked.
- `APPLE_CLIENT_IDS` stays unset (default `com.shellx.prod,com.shellx.dev`).

```bash
mkdir -m 700 -p ~/siwa-upload
# from your machine: scp AuthKey_<KEYID>.p8 <deploy-user>@<vps>:siwa-upload/siwa.p8
sudo install -o 1000 -g 1000 -m 400 ~/siwa-upload/siwa.p8 ~/phu/shellx/secrets/siwa.p8
rm -rf ~/siwa-upload
printf 'GOOGLE_CLIENT_IDS=<id1>,<id2>,<id3>,<id4>\nAPPLE_TEAM_ID=W4RF3W4VTZ\nAPPLE_SIWA_KEY_ID=<KEYID>\nAPPLE_SIWA_KEY_PATH=/secrets/siwa.p8\n' >> ~/phu/shellx/.env
cd ~/phu/shellx && docker compose up -d --force-recreate relay
docker compose logs relay | grep -E 'google_sign_in|apple_siwa'   # apple_siwa_enabled, and no google_sign_in_disabled
```

Never set `TEST_IDP_ISSUER` or `TEST_IDP_JWKS_PATH` here: they switch on a test identity provider and
exist for test relays only.

### Password cut-over (the day password sign-in ends)

Run these on the VPS in `~/phu/shellx`, in this order:

1. Switch password sign-in off and recreate the relay; the log shows `password_login_off`:

   ```bash
   sed -i '/^PASSWORD_LOGIN=/d' .env && echo 'PASSWORD_LOGIN=off' >> .env && docker compose up -d --force-recreate relay
   docker compose logs relay | grep password_login_off
   ```

2. Dry run (counts only):

   ```bash
   docker compose exec relay npm run -s password-cutover
   ```

3. Remove every password and password session:

   ```bash
   docker compose exec relay npm run -s password-cutover -- --yes
   ```

Step 3 cannot be undone except by restoring a backup. Sessions that signed in with Google or Apple stay.

## Admin (admin.shellx.pro)

The relay also answers `admin.shellx.pro` (same container, chosen by Host header): a small dashboard
with account and device statistics and the minimum app versions (force update). The DNS record
already points at the VPS; the `relay` service routes both names and gets a separate certificate for
each (`LETSENCRYPT_SINGLE_DOMAIN_CERTS`), so admin's can never break the relay's. Without a password
the dashboard is off: `/api/session` answers `{"enabled":false,...}` and every other call 503.

1. **Once, after the first deploy that ships `deploy/nginx-proxy/admin.shellx.pro`** (VPS set up
   before admin existed): copy it into `vhost.d` exactly like step 5, so admin requests are not
   logged either:

   ```bash
   PROXY=proxy   # the nginx-proxy container's name (docker ps; "proxy" on the current VPS)
   VHOST_D="$(docker inspect "$PROXY" --format '{{range .Mounts}}{{if eq .Destination "/etc/nginx/vhost.d"}}{{.Source}}{{end}}{{end}}')"
   echo "$VHOST_D"     # must print a directory; stop here if it is empty
   target="$VHOST_D/admin.shellx.pro"
   if sudo grep -qs 'access_log off' "$target"; then echo "$target already has our lines"
   elif sudo test -e "$target"; then echo "$target exists WITHOUT our lines -- merge ~/phu/shellx/nginx-proxy/admin.shellx.pro into it BY HAND, keeping the companion's block"
   else sudo cp ~/phu/shellx/nginx-proxy/admin.shellx.pro "$target"; fi
   ```

   (`sudo test`/`sudo grep`: a named volume's directory is readable by root only.) The next step
   recreates the relay, which makes nginx-proxy include the file; check it afterwards with
   `docker exec "$PROXY" nginx -T 2>/dev/null | grep -A3 'server_name admin.shellx.pro'`.
2. **Enable** (on the VPS):

   ```bash
   cd ~/phu/shellx && echo "ADMIN_PASSWORD=$(openssl rand -hex 24)" >> .env && grep ADMIN_PASSWORD .env && docker compose up -d relay
   docker compose logs relay | grep admin_   # admin_enabled {"host":"admin.shellx.pro"}
   ```

   Keep the printed password in your password manager; it is the only sign-in, and it lives only in
   `.env` (never in the repository or `relay.env`, which deploys overwrite; `rollout.sh` keeps every
   `.env` line except `IMAGE_TAG` and rewrites the file with mode 0600). Hex because Compose reads `.env`
   itself: a `$`, quote or `#` in the value would be interpolated or cut off. At least 16 characters,
   or the relay keeps admin off and logs `admin_disabled {"reason":"password_too_short"}`.
3. **Change the password:** `sed -i '/^ADMIN_PASSWORD=/d' .env`, then the command of step 2 again.
   **Disable:** `sed -i '/^ADMIN_PASSWORD=/d' .env && docker compose up -d relay`.

Sessions live in the relay's memory only (12 h, HttpOnly cookie): any relay restart — a deploy, a
password change, `docker compose up -d relay` — signs you out, and you simply sign in again. That
restart also drops the apps' WebSockets for a moment; they reconnect on their own. 5 wrong passwords
from one IP within 15 minutes lock that IP out for the rest of the window.

## Relay v2

`relay2` is `cmux-relay` (Rust), the transport of the native desktop apps' remote feature
(`wss://relay.shellx.pro/v2/relay`). The Node relay still mints the tickets (`POST /v2/relay/tickets`)
and serves everything else; nginx-proxy sends only the exact path `/v2/relay` to relay2 (rewritten to
cmux-relay's own `/v1/relay`), so `/v2/relay/tickets` stays on the Node relay.

**Why it is built on the VPS.** There is no public image of relay2 (the licence question to the
upstream authors is open), so nothing is pulled or pushed for it: it is built from a pinned commit of
`lephus/shellx`, whose source you stage by hand. The compose service `relay2` only exists under the
profile `relay2`; a deploy without `COMPOSE_PROFILES=relay2` in the VPS's `.env` behaves exactly as
before (relay + web + backup). deploy.yml never syncs `relay2-src/`.

**Merge procedure (read first).** The relay2 pin `08de0bb35efbd46e3cade25446fdb6ffffac41bc` in
`docker-compose.yml` must stay reachable from `main`, because the rollout stages and the workflow
rollback checks require it. Merge `feat/relay-v2` with a real merge commit (`git merge --no-ff`;
never squash, never rebase), or re-pin compose to a commit that is on `main` before enabling relay2.
The pin is the first commit whose cmux-relay reads `CMUX_RELAY_ALLOWED_ORIGINS` (the browser share
viewer's Origin allowlist); an older pin answers every viewer 403. It reaches `main` with the share
links branch (`shellx/l7-share`), so merge that one with `--no-ff` too.

**G2 pre-check, before you push main with migration 0005 (once).** deploy.yml deploys `main`, so the
push that carries migration 0005 IS the production deploy of it. Migration 0005 rebuilds the
`devices` table (to allow `kind = 'desktop'`) and fails closed: on any dangling reference it rolls back,
the relay stays unhealthy and the deploy rolls back. So, before that push, look for dangling references
on a COPY of the production database, never on the live file `data/relay.db`. On the VPS, with the newest
nightly backup as the copy (it may be up to 24 h old; 0005 still fails closed on anything newer):

```bash
cd ~/phu/shellx
B=$(ls -1t backups/relay-*.db | head -n 1)
mkdir -p /tmp/fkcheck && cp "$B" /tmp/fkcheck/relay.db
docker run --rm -v /tmp/fkcheck:/w alpine:3.22 sh -c 'apk add -q sqlite && sqlite3 /w/relay.db "PRAGMA foreign_key_check;"'
rm -rf /tmp/fkcheck
```

Any output row means a dangling reference: stop, do not deploy, and report it. No output is the go.

1. **VPS prerequisites** (once). The Rust build needs about 2 GB of RAM including swap and 4 GB of
   free disk:

   ```bash
   docker compose version && docker buildx version
   free -h        # RAM + swap >= 2 GB
   df -h ~        # >= 4 GB free
   ```

2. **Stage the source** (for every new pinned commit; it is `08de0bb35efbd46e3cade25446fdb6ffffac41bc` today, the sha in
   `docker-compose.yml`). On your Mac, in any checkout of `lephus/shellx` that has that commit:

   ```bash
   scripts/shellx/relay2/source-tarball.sh 08de0bb35efbd46e3cade25446fdb6ffffac41bc /tmp   # prints the path, its sha256 and the sha
   scp /tmp/relay2-src-08de0bb35efbd46e3cade25446fdb6ffffac41bc.tar.gz <deploy-user>@<vps>:phu/shellx/
   ```

   On the VPS, compare `sha256sum relay2-src-08de0bb35efbd46e3cade25446fdb6ffffac41bc.tar.gz` with the value the script printed, then:

   ```bash
   cd ~/phu/shellx && mkdir -p relay2-src && tar -xzf relay2-src-08de0bb35efbd46e3cade25446fdb6ffffac41bc.tar.gz -C relay2-src
   ls relay2-src/08de0bb35efbd46e3cade25446fdb6ffffac41bc/scripts/shellx/relay2/Dockerfile
   ```

   Keep the previous `relay2-src/<sha>` directory until the next good deploy: a rollback restores the
   previous `docker-compose.yml`, which builds from that directory. Nothing deletes these directories.
3. **Secret, by hand** (never in the repository, `relay.env`, a chat or a log). One value shared by the
   Node relay (signs tickets) and relay2 (verifies them); the Node relay uses its bytes verbatim, so no
   trailing spaces or quotes:

   ```bash
   cd ~/phu/shellx
   grep -q '^CMUX_RELAY_HMAC_SECRET=' .env || printf 'CMUX_RELAY_HMAC_SECRET=%s\n' "$(openssl rand -hex 32)" >> .env
   chmod 600 .env
   ```

   Without it `/v2` tickets answer 503 and v1 is untouched. `CMUX_RELAY_ISSUER=shellx-relay` is already
   in `relay.env` and in the compose file; keep both exactly that text.
4. **nginx-proxy settings.** `nginx-proxy/relay.shellx.pro` now has 330 s timeouts (above cmux-relay's
   300 s idle timeout). step 5's loop leaves an existing file alone, so edit the copy in `vhost.d` by
   hand (keep the letsencrypt companion's block): set `proxy_read_timeout 330s;` and
   `proxy_send_timeout 330s;`. After the first deploy with relay2, check that nginx-proxy generated the
   exact-match location and the rewrite:

   ```bash
   PROXY=$(docker ps --format '{{.Names}}' | grep -m1 nginx-proxy)
   docker exec "$PROXY" nginx -T 2>/dev/null | grep -B2 -A8 'location = /v2/relay'
   ```

   It must show a `location = /v2/relay` block that proxies to relay2 with `/v1/relay`, and the
   `/` location still going to the relay. If your nginx-proxy version ignores `VIRTUAL_PATH` with `=`
   or `VIRTUAL_DEST`, use the fallback below.
5. **Enable.** First build relay2 once by hand, so the first deploy does not run a cold Rust build
   inside the 30-minute deploy job, then add the profile and deploy (push `main` or run the workflow):

   ```bash
   cd ~/phu/shellx && docker compose --profile relay2 build relay2
   grep -q '^COMPOSE_PROFILES=' .env || echo 'COMPOSE_PROFILES=relay2' >> .env
   ```

   If `.env` already has a `COMPOSE_PROFILES` line, add `relay2` to it by hand. rollout.sh then
   requires `relay2-src/<sha>/scripts/shellx/relay2/Dockerfile`, runs `docker compose build relay2`,
   pulls only `relay web backup` and waits for relay, relay2 and web (`relay, relay2 and web are
   healthy on <tag>`). A missing source or a failed build ends like a failed pull: config and
   `IMAGE_TAG` stay as they were. Then set the repository variable `RELAY2_ENABLED` to `true`
   (Settings, Environments, production, Variables) so deploy.yml also checks that
   `GET https://relay.shellx.pro/v2/relay` answers 400 or 426; the `/v2/relay/tickets` check (401
   `unauthorized`, served by the Node relay) always runs. Note: a workflow_dispatch rollback to a
   pre-v2 commit makes that `/v2/relay/tickets` check red although the rollout worked (expected; check
   the relay logs instead).
6. **Fallback: own subdomain.** If the path routing does not work on your nginx-proxy, branch
   `feat/relay-v2-subdomain` serves relay2 at `wss://relay2.shellx.pro/v1/relay` (own hostname and
   certificate, `nginx-proxy/relay2.shellx.pro`, DNS A record for `relay2.shellx.pro` first, and add
   that file to step 5's loop).
7. **Roll back / switch off.** On the VPS, first remove the container, then drop the profile:

   ```bash
   cd ~/phu/shellx
   docker compose --profile relay2 rm -sf relay2   # stops and removes it; v1 is untouched
   sed -i '/^COMPOSE_PROFILES=/d' .env             # or remove only `relay2` from the line by hand
   ```

   and set `RELAY2_ENABLED` to `false`. Order matters: Compose does not treat a service of an
   inactive profile as an orphan, so neither an `up` with orphan removal nor later deploys touch a relay2
   container that already runs (`restart: unless-stopped`), and nginx-proxy would keep sending
   `/v2/relay` to it. A bad deploy rolls back automatically as described above; the images of the
   previous relay2 commit are rebuilt from its kept `relay2-src/<sha>` directory if the local cache
   was pruned.

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
- **Smoke test of relay2:** from your machine, in `relay/`, run `SHELLX_SMOKE_TOKEN="$(ssh <deploy-user>@<vps> 'cd ~/phu/shellx && docker compose exec -T relay npm run -s mint-smoke-token')" npm run relay2:smoke`. Each mint replaces the previous token, and the smoke logs it out.
- **Emergency password reset (until the password cut-over):** see `relay/README.md` (`docker compose exec relay node dist/scripts/reset-password.js …`).
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

## Deploying without GitHub Actions

When Actions is not available (billing, an outage, a quick fix) everything deploy.yml and
`shellx-publish.yml` do can be done from the Mac, through ssh, with two scripts. Nothing goes
through GitHub or GHCR: the relay and web images are **built on the VPS** and tagged exactly as CI
tags them (`ghcr.io/lephus/shellx-relay:<sha>`, `ghcr.io/lephus/shellx-web:<sha>`), and the same
`rollout.sh` swaps the config in, recreates the containers, health-checks and rolls back. It needs
`git`, `ssh`, `rsync` and `curl` on the Mac (`python3` for the publish script), and a deploy user on
the VPS that is in the `docker` group, with the folder set up as in "First-time setup" (steps 1, 2 and 5;
step 4, making the GHCR packages public, is not needed). The build runs the relay tests and the web
checks like CI does, on the VPS, which it shares with other projects: check `free -h` and `docker
system df` before the first run, and `docker builder prune` now and then (the build cache is not
touched by rollout.sh's image prune).

**1. A shared ssh connection (password login).** With a password every ssh and rsync of a deploy
would ask for it again. Open one connection first; it stays up for 10 hours and the scripts reuse it
(their default `SHELLX_VPS_SSH_OPTS` is `-o ControlPath=~/.ssh/cm-shellx-vps`):

```bash
ssh -fN -M -S ~/.ssh/cm-shellx-vps -o ControlPersist=10h higio@42.115.41.70   # asks for the password once
ssh -S ~/.ssh/cm-shellx-vps -O check higio@42.115.41.70                       # "Master running"
ssh -S ~/.ssh/cm-shellx-vps -O exit higio@42.115.41.70                        # close it when done
```

With a key login, `export SHELLX_VPS_SSH_OPTS=''` (or `'-i ~/.ssh/key'`) is enough. Every ssh and
rsync of both scripts runs with `-o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4`:
they never stop to ask for a password (they stop with this same hint instead), and a dead connection is
noticed within a minute. That default `ControlPath` is production's socket, so it only applies to the
default target: with another `SHELLX_VPS` the scripts refuse until you also set `SHELLX_VPS_SSH_OPTS`
(`''` for plain ssh), so the production master is never reused for a different host.

**2. Deploy the checked-out commit: `deploy/vps-deploy.sh`.**

```bash
deploy/vps-deploy.sh --dry-run    # prints every command and the script that runs on the VPS; runs none
deploy/vps-deploy.sh
```

| Variable | Default | |
|---|---|---|
| `SHELLX_VPS` | `higio@42.115.41.70` | ssh target |
| `SHELLX_VPS_SSH_OPTS` | `-o ControlPath=~/.ssh/cm-shellx-vps`, for the default target only | ssh options; empty string = plain ssh |
| `APP_DIR` | `phu/shellx` | ShellX's folder, relative to the ssh user's home (same rules as `VPS_APP_DIR`) |
| `RELAY2_ENABLED` | asked of the VPS | `true`/`false`: also check `GET /v2/relay` (see "Relay v2 without Actions") |
| `SHELLX_ALLOW_NON_MAIN` | unset | `1`: deploy a `HEAD` that is not on `origin/main` (prints a loud warning) |
| `SHELLX_ROLLOUT_TIMEOUT`, `SHELLX_ROLLOUT_POLL` | `1500`, `5` | seconds the script waits for the rollout, and between two looks at it |

What it does, in this order (it prints each step's name):

1. **Refuses** a dirty `relay/`, `web/` or `deploy/` (the VPS gets exactly `HEAD`), and a `HEAD` that is
   not an ancestor of `origin/main`: it runs `git fetch origin main` first, so "on main" is judged
   against the real main. `SHELLX_ALLOW_NON_MAIN=1` overrides (and also covers a failed fetch).
2. **Checks the connection and the folder, takes two locks, checks the room.** A `mkdir` lock on the Mac
   (a leftover of a dead run is replaced; another live run is refused) and `~/phu/shellx/.deploy.lock` on
   the VPS (a directory; its `owner` file names the holder). If the VPS lock is held the script prints who
   and how to clear a stale one: check `pgrep -af rollout` and `docker compose ps`, then
   `ssh <opts> <vps> rm -rf phu/shellx/.deploy.lock`. Then it refuses unless there are at least 4 GB free
   under Docker's root dir (`docker info --format '{{.DockerRootDir}}'`) and 1.5 GB of `MemAvailable`.
3. **Copies the build sources**: the tracked files of `relay/`, `web/`, `deploy/web/` (never
   `node_modules`, build output or any ignored file) to `~/phu/shellx/.build-src/<sha>/`.
4. **Builds on the VPS**: `docker build` of both images, each under `timeout 30m` (the relay build runs
   its tests), then deploy.yml's preflight (the compose file resolves, the new relay image loads
   `relay.env`). Nothing that runs is touched yet.
5. **Stages the config** into `.incoming/` like deploy.yml.
6. **Rolls out, detached.** `rollout.sh` is copied (not streamed) to `~/phu/shellx/.rollout/<sha>.sh` and
   started with `setsid nohup`, `SHELLX_LOCAL_IMAGES=1`, output in `.rollout/<sha>.log`, the exit code in
   `.rollout/<sha>.exit` and the lock given back when it ends. So a dropped ssh session cannot kill
   compose half way through a recreate or a rollback. The script polls the exit marker every
   `SHELLX_ROLLOUT_POLL` seconds and shows the log as it grows (rollout.sh's own lines and compose's
   output; no secret is in them), for at most `SHELLX_ROLLOUT_TIMEOUT` seconds. The Mac is kept awake with
   `caffeinate -i` meanwhile (closing the lid still sleeps it).
   **If the connection is lost** (three polls in a row fail), or the timeout passes, the rollout carries
   on by itself (or has finished) and the script says so, with the commands to look:
   `ssh <opts> <vps> 'cd phu/shellx && docker compose ps'` and
   `ssh <opts> <vps> 'tail -n 50 phu/shellx/.rollout/<sha>.log; cat phu/shellx/.rollout/<sha>.exit'`.
   **Running the script again heals**: once the rollout is over (its lock is gone) it rebuilds, re-stages
   and rolls out again; rollout.sh recovers from a half-done swap by itself.
7. **Checks the public endpoints** (`relay.shellx.pro/v1/version`, `shellx.pro`,
   `admin.shellx.pro/api/session`, the tickets route, and `/v2/relay` when relay2 is on) with deploy.yml's
   10 attempts, 15 s apart.
8. **Cleans up**: removes `.build-src/<sha>` and the rollout files. A failed run leaves them to look at
   (`rm -rf ~/phu/shellx/.build-src` is always safe); a failed build changes nothing that runs.

Every file it writes or removes on the VPS is inside `~/phu/shellx` (the images live in Docker, as
always). It prints step names, build output, rollout.sh's lines and the checks; never a secret or any other
log's content. Differences from CI: the macOS `rsync` does not understand `--chmod=D755,F644`, so the same
modes are set on the VPS after the copy, and there is no GHCR login or push.

`SHELLX_LOCAL_IMAGES=1` is what makes `rollout.sh` skip the pull of `relay` and `web`: it checks that
both `ghcr.io/lephus/shellx-{relay,web}:<sha>` exist on the VPS (a missing one ends like a failed pull:
nothing restarted, config put back), still pulls `backup` (alpine) and still builds relay2. Unset, it
does exactly what it did before.

**3. Publish a desktop release: `scripts/shellx/release/publish-to-vps.sh <version> <dist-dir>`.**
`<dist-dir>` is what `make-feeds.sh` wrote next to the installers. The script runs the same checks as
`shellx-publish.yml` (`SHA256SUMS`, feeds against installers), refuses a version that
`~/phu/shellx/downloads/desktop/<version>/` or `download.shellx.pro` already has (installers are
immutable: release X.Y.(Z+1) instead), rsyncs the installers (`--ignore-existing`; folders 755, files
644), checks their size over HTTPS, and only then uploads the feeds, `appcast.xml`, `latest-macos.json`
and `SHA256SUMS` last (`latest-windows.json` before them, when there is an exe), and checks the appcast
serves the new version. The `SHA256SUMS` it uploads is a copy with only the lines of the files it uploads.
The feeds are checked against `https://download.shellx.pro`, the address the apps read; another
`DOWNLOAD_BASE_URL` is refused unless `SHELLX_ALLOW_OTHER_DOWNLOAD_URL=1` is set too. It uses the same
`SHELLX_VPS`, `SHELLX_VPS_SSH_OPTS` and `APP_DIR` (and the same ssh options and ControlPath rule), takes a
per-version lock on the Mac, and `--dry-run` runs the local checks and prints the rest.

**An interrupted upload.** If the connection dies while the installers are going up, the next run
refuses ("already has files"; a version folder it cannot list counts as not free too). It then reads the
LIVE `appcast.xml`, `latest-macos.json` and `latest-windows.json` from the website: if none points at the
version, the folder is a leftover and the message gives the exact `ssh ... rm -rf
phu/shellx/downloads/desktop/<version>` that is safe; if one does, the version is published and the
only way forward is the next version; if a feed cannot be read, it tells you to look before removing
anything. Nothing is removed for you.

**Mac-only release.** Without `ShellX-Setup-<version>.exe` in `<dist-dir>` nothing of Windows is
uploaded and the live `latest-windows.json` stays, so Windows machines are not told about a version
they cannot get. Build the folder with `SHELLX_NO_WINDOWS=1 scripts/shellx/release/make-feeds.sh
<ShellX.app> <version> <dist-dir> <sparkle-bin-dir>` (no exe needed, no `latest-windows.json`). Sparkle
(`appcast.xml`) updates Mac users right away. To make the relay announce the version too, move
`MAC_URL` (and `LATEST_AGENT_VERSION`, if Windows may be told as well) in `deploy/relay.env` and
deploy (step 2); leave `WIN_URL` on the last version that has an exe. The website has one
`desktopVersion` (`web/src/site.config.json`) for both download links: keep it on the last release
that has both installers until the Windows exe of the new version is published too.

**Relay v2 without Actions.** relay2 is switched on by the line `COMPOSE_PROFILES=relay2` in the VPS's
**`.env`** (the file `rollout.sh` and `docker compose` read; not `relay.env`, which is only the relay
container's environment and is overwritten by every deploy). `RELAY2_ENABLED` is read by nothing on
the VPS: it is the GitHub variable that told deploy.yml to also check `GET /v2/relay`. `vps-deploy.sh`
answers that question itself by reading `COMPOSE_PROFILES` in the VPS's `.env` as a comma list, the way
`rollout.sh` does (`relay2` in the list; `relay20` or `my-relay2` is not it); set
`RELAY2_ENABLED=true` or `false` in your shell to override. The "Relay v2" section above has the reasons
and the nginx step; from the Mac, with the shared connection open, the whole procedure is:

```bash
S='-o ControlPath=~/.ssh/cm-shellx-vps'; V=higio@42.115.41.70
PIN=$(sed -n 's#^ *context: \./relay2-src/\([0-9a-f]\{40\}\) *$#\1#p' deploy/docker-compose.yml | head -n 1)
scripts/shellx/relay2/source-tarball.sh "$PIN" /tmp            # prints the path, its sha256 and the sha
scp $S "/tmp/relay2-src-$PIN.tar.gz" "$V:phu/shellx/"
ssh $S $V "cd phu/shellx && sha256sum relay2-src-$PIN.tar.gz && mkdir -p relay2-src && tar -xzf relay2-src-$PIN.tar.gz -C relay2-src"
#   compare that sha256 with the one the script printed, then (the secret is never printed; a missing
#   final newline in .env is added first, so the new line is not glued to the last one):
ssh $S $V 'cd phu/shellx && touch .env && { [ -z "$(tail -c1 .env)" ] || echo >> .env; } && { grep -q "^CMUX_RELAY_HMAC_SECRET=" .env || printf "CMUX_RELAY_HMAC_SECRET=%s\n" "$(openssl rand -hex 32)" >> .env; } && chmod 600 .env'
#   edit nginx-proxy's copy of relay.shellx.pro by hand (Relay v2, step 4), then build once and switch on:
ssh $S $V 'cd phu/shellx && docker compose --profile relay2 build relay2 && { [ -z "$(tail -c1 .env)" ] || echo >> .env; } && { grep -q "^COMPOSE_PROFILES=" .env || echo COMPOSE_PROFILES=relay2 >> .env; }'
deploy/vps-deploy.sh                                            # now builds, rolls out and checks relay2 too
```

To switch it off, follow "Relay v2", step 7 (remove the container first, then the `COMPOSE_PROFILES`
line); `vps-deploy.sh` then stops checking `/v2/relay` by itself.

**Rollback.** A deploy whose relay or web is not healthy within 60 s rolls itself back (config and
`IMAGE_TAG`, as in "Operations"); the detached rollout's own lines are in `.rollout/<sha>.log` and
its exit code in `.rollout/<sha>.exit`. To go back after a *good* deploy:

- *The previous release's images are still on the VPS* (they are kept for 7 days after a healthy
  deploy; `docker image ls | grep shellx-`): on the VPS, `cd ~/phu/shellx`, put the old sha in `.env`
  (`sed -i 's/^IMAGE_TAG=.*/IMAGE_TAG=<old sha>/' .env`) and `docker compose up -d --remove-orphans
  --force-recreate`. Do not do this for a sha whose images are gone: the images were never pushed, so
  Compose would try GHCR and fail.
- *Otherwise, or to bring back that commit's config too* (`docker-compose.yml`, `relay.env`,
  `nginx-proxy/`, `backup/`): deploys always build `HEAD`, so `git revert` the bad change and run
  `deploy/vps-deploy.sh`; or check out an older commit that already contains these scripts
  (`git switch --detach <old sha> && deploy/vps-deploy.sh`, then `git switch -`): it rebuilds that
  commit's images and re-stages its config.
- *The config only*: the `.prev/` recipe in "Operations".

## Tests of the deploy scripts

`node --test deploy/tests/*.test.mjs` runs `rollout.sh` against a fake `docker` (health of relay and web, and of relay2 plus its build/source staging when the profile is on, rollback, pull failure, missing `PROXY_NETWORK`, wrong `data/` owner, staging and
restoring `.incoming/`/`.prev/` config, restoring only a config this run swapped in, recreating
`backup` after a restore, `--force-recreate` on the rollback too, skipping a no-op restage,
recovering from a crash mid-swap, pruning images only after success, and `SHELLX_LOCAL_IMAGES=1`:
no pull of relay and web, `backup` still pulled, a missing local image taking the failed-pull path) and `backup/backup-once.sh`
with the local `sqlite3` (rotation, missing and unreadable databases, 0600 file mode, handing each
file to the owner of `backups/`). `compose.test.mjs` checks `docker-compose.yml` (memory ceiling,
push and admin settings) and that every name it routes has its `nginx-proxy/` file in step 5.
`vps-deploy.test.mjs`, `vps-deploy-options.test.mjs` and `publish-to-vps.test.mjs` (fakes in
`vps-fakes.mjs`) run `vps-deploy.sh` (in a throwaway git repository with an `origin`) and
`publish-to-vps.sh` against a fake `ssh`, `rsync`, `curl`, `docker`, `timeout` and `caffeinate`. The fake
`ssh` and `rsync` work on a sandbox "remote home", so the scripts sent to the VPS (locks, launcher, poll,
relay2 question, version-folder check) and `rollout.sh` itself really run: the detached rollout surviving
a dropped connection, a failing and a slow rollout, the origin/main check and its override, the room check,
both locks and their release on every path, the order of the steps, what is sent, nothing outside
`phu/shellx`, the fixed ssh options, the ControlPath rule, relay2 detection, `--dry-run`, input
validation, the immutable-version refusal and its recovery message, feeds last, the filtered
`SHA256SUMS`, and the Mac-only release.
