# ShellX Sign-in 1D: Rollout — Google/Apple Setup, Relay Deploy (1A + 3F), Desktop 1.8.0 and iPhone Releases, Force Update, Password Cut-over Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take Google / Apple sign-in from merged code (plans 1A, 1B, 1C, 3F on `develop`) to production in the order of S1 §7, with the user doing every outward step, then remove what only existed for passwords.

**Architecture:** A runbook in five phases (0 setup, 1 relay deploy, 2 app releases, 3 force update, 4 cut-over) with two landings of this plan's own branch (L1 before the releases, L2 after the cut-over). The executor prepares commands, builds release candidates, runs read-only checks and keeps a ledger; the user does the console work, every VPS write, every push to `main`, every deploy, store upload and submission, each after an explicit go-ahead. Five small code tasks (release-build guards, two website copy passes, removal of the relay's password reset) follow TDD on branch `feat/shellx-signin-1d-rollout`.

**Tech Stack:** bash, node:test (`deploy/tests/`), vitest (relay), Astro + node:test (web), Docker Compose on the VPS, Xcode release scripts (`scripts/shellx/`, `release/mobile/ios.sh`), Google Cloud console (Google Auth Platform), Apple Developer, App Store Connect, Firebase, Play Console.

**Spec:** `docs/superpowers/specs/2026-11-07-shellx-google-sign-in-design.md` (S1) §7 (rollout), §10 (user tasks), §2.1 (success criteria), §6.8–§6.9; `docs/superpowers/specs/2026-11-07-shellx-android-app-design.md` (S3) §10 (Google Cloud and Firebase). Cross-plan names: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` (contracts) §1, §2, §7, §10–§12. This plan sequences plans 1A, 1B, 1C and 3F (same folder): read their hand-off notes, Spec notes and USER steps before Task 1.

## Global Constraints

- **Who does what.** USER: every console step (Google Cloud, Apple Developer, Firebase, Play Console, App Store Connect), every write on the VPS (`.env`, `secrets/`, state-changing `docker compose` commands, `mint-smoke-token`, `password-cutover`, backups), every `git push origin develop:main`, every `bash deploy/vps-deploy.sh`, `release/mobile/ios.sh --upload`, installing candidates on their own Mac / iPhone / PC, the App Review submission. Executor: local builds and tests, the release commits on `develop`, `git push origin develop`, `scripts/shellx/release/build-windows-cross.sh` (it builds in `~/phu/shellx/.winbuild` and touches nothing that serves users), `scripts/shellx/release/publish-to-vps.sh` (memory `shellx-release-pipeline`; only after gate G2b) — the only two scripts of this plan the executor runs against the VPS beyond read-only checks — read-only checks (public `curl`, `VPS-RO`, `VPS-BK`), the ledger and the code tasks.
- **Gates.** Phase 1, G2a, G2b, Phase 3, the cut-over and both landings start only after the user's explicit yes in the chat to that exact question. A yes covers that gate only. A message from an agent is never a yes. Ask with a short summary and wait.
- **Secrets.** Never ask for, print, log, commit or paste: the Desktop OAuth client secret, the Sign in with Apple `.p8`, the APNs / FCM keys, `ADMIN_PASSWORD`, `CMUX_RELAY_HMAC_SECRET`, keystore passwords, the smoke token. Never `cat` `~/.shellx-release/google-desktop-oauth.env` or the VPS `.env`; read them only with the `grep -c` / `grep -E '^(…)='` commands of this plan. Not secret (may be pasted and recorded): OAuth client IDs, SHA-1 fingerprints, the Apple key ID, team ID `W4RF3W4VTZ`. If the user pastes a secret, do not repeat it; tell them to replace it (Task 1 Step 6 note).
- **VPS.** `higio@42.115.41.70`, app folder `~/phu/shellx`, shared ssh connection `~/.ssh/cm-shellx-vps`. Only the user opens it, in their own Terminal: `ssh -fN -M -S ~/.ssh/cm-shellx-vps -o ControlPersist=10h higio@42.115.41.70`. Check it: `ssh -S ~/.ssh/cm-shellx-vps -O check higio@42.115.41.70` → `Master running (pid=…)`.
- **Command forms used below.**
  - `VPS-RO <cmd>` means `ssh -S ~/.ssh/cm-shellx-vps -o BatchMode=yes higio@42.115.41.70 'cd phu/shellx && <cmd>'` (read-only host commands).
  - `VPS-BK` + a script means `ssh -S ~/.ssh/cm-shellx-vps -o BatchMode=yes higio@42.115.41.70 'cd phu/shellx && docker compose exec -T backup sh -s' <<'EOF'` … `EOF`: a read-only script inside the `backup` container, whose `sqlite3` reads `/data/relay.db` (mounted read-only) and `/backups/`. Every `sqlite3` call there uses `-readonly`.
  - The executor runs `VPS-RO` / `VPS-BK` itself. If the connection is closed, ask the user to open it; if the session refuses the command, hand it to the user as a `!` command.
  - `VPS shell` means: the user runs it in their own Terminal after `ssh -S ~/.ssh/cm-shellx-vps higio@42.115.41.70` and `cd ~/phu/shellx`, then pastes the output (it never contains a secret).
  - `!` commands for the user are one line starting `! cd /Users/lehuuphu/Documents/myProjects/shellx && ` (a `!` command runs in the session's current folder).
- **Two checkouts.** `M` = `/Users/lehuuphu/Documents/myProjects/shellx` (the main checkout, on `develop`): release commits, builds (`build-shellx/`, `dist/`, `build/release/ios/` live here), pushes and deploys. `W` = `M/.claude/worktrees/signin-1d-rollout` (this plan's branch): code tasks and the ledger. In the commands below `M` and `W` stand for these absolute paths: substitute them (shell variables do not survive between Bash calls). In `M`, `git add` only explicit paths; never stage the user's untracked plan files or the modified spec.
- **Fix forward.** Once Phase 1 is live, never deploy a commit that lacks the 1A merge and never set `IMAGE_TAG` back below it: the pre-1A relay checks a password against `user?.password_hash ?? dummyHash` (`relay/src/routes/auth.ts:87`), so the dummy password `shellx-dummy-password` would open every passwordless account. Before every deploy: `git -C <checkout> merge-base --is-ancestor <A1> HEAD && echo has-1A` → `has-1A` (`A1` from the ledger). Never overwrite a published desktop version: a broken 1.8.0 is fixed by 1.8.1.
- **Values (contracts §2, §7, §10–§12).** VPS `.env`: `GOOGLE_CLIENT_IDS=<iOS prod>,<iOS dev>,<Web>,<Desktop>` (full client IDs, comma-separated, no spaces), `APPLE_TEAM_ID=W4RF3W4VTZ`, `APPLE_SIWA_KEY_ID=<key id>`, `APPLE_SIWA_KEY_PATH=/secrets/siwa.p8`; `APPLE_CLIENT_IDS` unset; `PASSWORD_LOGIN` unset until the cut-over, then `off`; `TEST_IDP_ISSUER` / `TEST_IDP_JWKS_PATH` never on the VPS. Bundle ids / packages `com.shellx.prod`, `com.shellx.dev`. Desktop release `1.8.0`; `MIN_MACOS=1.8.0`, `MIN_WINDOWS=1.8.0` in Phase 3. Every OAuth client lives in Google Cloud project `shellxpro` (the Firebase project).
- **Never** quit, relaunch or replace the user's running ShellX (`/Applications/ShellX.app`) or cmux, and never open a candidate yourself: the user installs candidates.
- **Language.** Talk to the user in Vietnamese; keep console labels, commands and values exactly as written here (English). The ledger is English.
- **Ledger.** `docs/superpowers/ledgers/shellx-signin-rollout.md` in `W`. Every result goes in with its date, from real command output or the user's report, never predicted. Commit with `git -C W add docs/superpowers/ledgers/shellx-signin-rollout.md && git -C W commit -m "docs(shellx): sign-in rollout ledger — <what>"`.
- **Resume.** This plan runs over weeks. At the start of every session: read the ledger's Status table, rerun Task 0 Step 3, continue at the first unchecked step.
- **Landing (contracts §1, CLAUDE.md).** This plan lands twice (Task 9, Task 20): review subagent (`skills/cmux-review/SKILL.md`, correctness first), the user's merge directive, `git merge --no-ff` into `develop` in `M`, `git push origin develop`. Never merge into `main`; `main` moves only by the user's `git push origin develop:main`.
- **Commits** in `W`: a code task commits once, test and code together, with explicit `git add <paths>`; ledger updates are their own commits. Never commit this plan or the contracts file.

## Review Focus

1. **A desktop release built without the Desktop OAuth client** (env not loaded, or the Windows container never received it). 1.8.0 has no password field, so nobody could sign in. Expected: both build scripts refuse before building, and refuse an app whose binary lacks the client. Pinned in Task 2 (`deploy/tests/release-google-client.test.mjs`) and by the `present` lines Task 10 expects.
2. **A force update to a version that cannot be downloaded** (Windows exe missing). Windows users would be blocked with nothing to install. Expected: each `MIN_*` rises only when its installer answers `200`. Pinned in Task 14 Step 1.
3. **A cut-over that strands people**: an account whose email is not a Google account and never switched in-app, an iPhone build not yet on the App Store, the user's own devices still on a password. Expected: a readiness report and a gate before any date. Pinned in Task 15.
4. **A relay rollback below the 1A merge** after passwordless accounts exist (the dummy-password hole above). Expected: fix forward only, and an ancestor check before every deploy. Pinned in Tasks 6, 7, 13, 14, 20.
5. **Apple's code exchange failing for one bundle** (the Sign in with Apple key serves only its primary App ID's group), which silently stops revocation. Expected: `com.shellx.dev` grouped under `com.shellx.prod`, and no `apple_token_exchange_failed` after an Apple sign-in on ShellX Dev. Pinned in Task 3 and Task 12 Step 5.

## Phase map

| Phase | Tasks | Gate (the user's yes to) | User runs |
| --- | --- | --- | --- |
| 0 Preparation | 1–5 | — | consoles, the Desktop secret file, VPS `.env` and key |
| 1 Relay deploy | 6–7 | "deploy the relay (1A + 3F)" | push `main`, deploy, smoke, simulator checks |
| L1 | 8–9 | merge directive | — |
| 2 Releases | 10–13 | G2a "build 1.8.0 and the iPhone build", G2b "publish" | installs, live checks, TestFlight upload, push `main`, deploy, App Review |
| 3 Force update | 14 | "force update" | push `main`, deploy |
| 4 Cut-over | 15–16 | the date, then "cut over now" | backup, `PASSWORD_LOGIN=off`, `password-cutover` |
| L2 | 17–20 | merge directives, "deploy the leftovers" | push `main`, deploy |

Phase 0 and Task 2 may start before 1A–1C land. Phase 1 needs 1A and 3F on `develop`; Phase 2 needs 1B and 1C too.

## File map

| File | Task | Change |
| --- | --- | --- |
| `docs/superpowers/ledgers/shellx-signin-rollout.md` | 0 | create: the rollout ledger |
| `scripts/shellx/release/google-desktop-client.sh` | 2 | create: guard and binary check, sourced by both build scripts |
| `scripts/shellx/sign-and-notarize.sh` | 2 | `--build` refuses without the client and checks the built app |
| `scripts/shellx/release/build-windows-cross.sh` | 2 | refuses without the client; passes it to the container on stdin |
| `windows/cross/build-in-container.sh` | 2 | refuses without the client; checks `shellx-desktop.exe` |
| `deploy/tests/release-google-client.test.mjs` | 2 | create: tests of the four above |
| `shellx-ios/Config/Debug.xcconfig`, `shellx-ios/Config/Release.xcconfig` | 1 | real `SHELLX_GOOGLE_IOS_CLIENT` values (only if plan 1C left the placeholder) |
| `shellx-android/app/src/main/res/values/google_oauth.xml` | 1 | `google_web_client_id` = client 6 (only while it holds a placeholder; contracts §16) |
| `web/src/i18n/ui.ts`, `web/src/pages/terms.md`, `web/src/pages/privacy.md`, `web/tests/site.test.mjs` | 8, 18 | sign-in copy, deletion path, no-password copy |
| `relay/src/scripts/reset-password.ts`, `reset-cli.ts`, `reset-db.ts`, `relay/test/reset-password.test.ts` | 17 | delete |
| `relay/test/line-prompter.test.ts`, `relay/test/cutover-leftovers.test.ts` | 17 | create |
| `relay/package.json`, `relay/README.md`, `deploy/README.md`, `relay/src/scripts/line-prompter.ts`, `relay/test/auth.test.ts`, `relay/dev.env` | 17 | drop the reset script and its mentions |
| In `M` on `develop` (release commits): `cmux.xcodeproj/project.pbxproj`, `windows/{Cargo.toml,Cargo.lock,README.md}`, `windows/shellx-app/resources/shellx.manifest`, `windows/shellx-model/src/lib.rs`, `shellx-ios/Config/Version.xcconfig`, `deploy/relay.env`, `web/src/site.config.json` | 10, 11, 13, 14 | versions, pointers, minimums |

---

### Task 0: Worktree, ledger and preconditions

**Files:** Create `docs/superpowers/ledgers/shellx-signin-rollout.md` (in `W`).

**Interfaces:**
- Produces: `W`; the ledger with the sections below; merge SHAs `A1` (1A), `F3` (3F), `B1` (1B), `C1` (1C).

- [ ] **Step 1: Create the worktree** with superpowers:using-git-worktrees, at this location and branch:

```bash
git -C /Users/lehuuphu/Documents/myProjects/shellx branch --show-current   # must print develop; otherwise stop and ask the user
git -C /Users/lehuuphu/Documents/myProjects/shellx pull --ff-only origin develop
git -C /Users/lehuuphu/Documents/myProjects/shellx worktree add .claude/worktrees/signin-1d-rollout -b feat/shellx-signin-1d-rollout develop
```

Expected: `Preparing worktree (new branch 'feat/shellx-signin-1d-rollout')`.

- [ ] **Step 2: Planning files.** Read this plan, the contracts and plans 1A, 1B, 1C, 3F from `M/docs/superpowers/plans/` (they may be untracked there). Never copy or commit them in `W`.

- [ ] **Step 3: Preconditions (rerun at every session start)**

```bash
git -C /Users/lehuuphu/Documents/myProjects/shellx fetch origin
git -C /Users/lehuuphu/Documents/myProjects/shellx log --merges --reverse --format='%H %s' origin/develop | grep -E "'feat/shellx-(signin-1a-relay|android-3f-relay-fcm|signin-1b-desktop|signin-1c-ios)'"
```

Expected: for each landed plan, lines naming its branch; the first line of a plan is its landing merge. Record those SHAs in the ledger table "Merges" (`A1`, `F3`, `B1`, `C1`). Missing 1A or 3F blocks Phase 1; missing 1B or 1C blocks Phase 2. Phase 0 and Task 2 go on regardless.

- [ ] **Step 4: Create the ledger** at `W/docs/superpowers/ledgers/shellx-signin-rollout.md` with exactly this skeleton, then commit it (Global Constraints, "Ledger"; `<what>` = `start`):

```markdown
# Ledger: ShellX sign-in rollout (plan 1D)

Plan: `docs/superpowers/plans/2026-11-07-shellx-signin-1d-rollout.md`. Spec: S1 §7, §10, §2.1. Branch: `feat/shellx-signin-1d-rollout`.
Nothing secret is written here: client IDs, SHA-1 fingerprints, key IDs and team IDs only.

## Status

| Phase | State | Date | Evidence |
| --- | --- | --- | --- |
| 0 Preparation | pending | | |
| 1 Relay deploy (1A + 3F) | pending | | |
| L1 landing | pending | | |
| 2 Desktop 1.8.0 and iPhone | pending | | |
| 3 Force update | pending | | |
| 4 Cut-over | pending | | |
| L2 leftovers and landing | pending | | |

## Merges

| Plan | Merge SHA on develop |
| --- | --- |
| 1A (A1) | |
| 3F (F3) | |
| 1B (B1) | |
| 1C (C1) | |

## Google OAuth clients (Google Cloud project shellxpro)

| # | Name | Type | Bundle / package | SHA-1 | Client ID |
| --- | --- | --- | --- | --- | --- |
| 1 | ShellX iOS | iOS | com.shellx.prod | — | |
| 2 | ShellX iOS (dev) | iOS | com.shellx.dev | — | |
| 3 | ShellX Android (dev) | Android | com.shellx.dev | debug key | |
| 4 | ShellX Android (upload key) | Android | com.shellx.prod | upload key | |
| 5 | ShellX Android (Play signing) | Android | com.shellx.prod | Play App Signing key | |
| 6 | ShellX Web (Android sign-in) | Web application | — | — | |
| 7 | ShellX Desktop | Desktop app | — | — | |

Consent screen: . Desktop secret file `~/.shellx-release/google-desktop-oauth.env`: .

## Apple

## Firebase

## VPS

## Releases

## Checks

## Live checks (S1 §2.1)

| Check | Criterion | App and build | Result | Seconds to signed in | Date |
| --- | --- | --- | --- | --- | --- |

## Cut-over

## Incidents and rollbacks

## Hand-off to 3D / 3H
```

- [ ] **Step 5: Baseline in `W`**

```bash
(cd /Users/lehuuphu/Documents/myProjects/shellx/.claude/worktrees/signin-1d-rollout/web && npm ci && npm run build)
(cd /Users/lehuuphu/Documents/myProjects/shellx/.claude/worktrees/signin-1d-rollout && node --test deploy/tests/*.test.mjs)
(cd /Users/lehuuphu/Documents/myProjects/shellx/.claude/worktrees/signin-1d-rollout/relay && npm ci && npm test && npm run typecheck)
```

Expected: both node:test runs end with `# fail 0`; vitest shows no `failed`; `tsc` prints no `error TS`. If the untouched branch is red, stop and report; do not fix unrelated failures.

---

## Phase 0 — Preparation

### Task 1: Google OAuth consent screen, the seven clients, the Desktop secret file and the iPhone client IDs

**Files:** Modify (only if they still hold `0-shellx-placeholder`): `shellx-ios/Config/Debug.xcconfig`, `shellx-ios/Config/Release.xcconfig` (the `SHELLX_GOOGLE_IOS_CLIENT` line plan 1C Task 8 added). Modify (only while it holds a placeholder): `shellx-android/app/src/main/res/values/google_oauth.xml` (string `google_web_client_id`, contracts §16; the file comes from plan 3D).

**Interfaces:**
- Produces: the ledger's client table; `~/.shellx-release/google-desktop-oauth.env` (mode 600, exactly two lines `SHELLX_GOOGLE_DESKTOP_CLIENT_ID=…` and `SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET=…`); `SHELLX_GOOGLE_IOS_CLIENT` = the client ID without `.apps.googleusercontent.com` (Debug: client 2, Release: client 1); `google_web_client_id` = client 6's full ID (Android's `serverClientId`; plan 3H's release checks compare it with the ledger).

- [ ] **Step 1: Print the debug SHA-1** (public, not secret) for the user:

```bash
"/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" -list -v -keystore "$HOME/.android/debug.keystore" -alias androiddebugkey -storepass android | grep 'SHA1:'
```

Expected: `SHA1: ` and 20 colon-separated hex bytes. If the keystore does not exist, client 3 is `pending (3H)`.

- [ ] **Step 2: USER — consent screen.** Google Cloud console → project `shellxpro` → ☰ → APIs & Services → OAuth consent screen (it opens Google Auth Platform; direct link `https://console.cloud.google.com/auth/overview?project=shellxpro`). If it says it is not configured: **Get started** → App name `ShellX`, User support email = your email → Audience **External** → Contact information = your email → agree → **Create**. Then:
  - **Branding:** App name `ShellX`; no app logo (a logo needs brand verification); Application home page `https://shellx.pro`; privacy policy `https://shellx.pro/privacy`; terms of service `https://shellx.pro/terms`; Authorized domains `shellx.pro`; developer contact = your email → **Save**.
  - **Data Access → Add or remove scopes:** tick `openid`, `.../auth/userinfo.email`, `.../auth/userinfo.profile` → **Update** → **Save**.
  - **Audience → Publish app → Confirm** (status "In production").
  - If Google asks you to verify `shellx.pro`: Google Search Console with the same account → Add property → Domain `shellx.pro` → add the DNS TXT record it shows → Verify.

- [ ] **Step 3: USER — the two `com.shellx.prod` SHA-1s.** Play Console → ShellX → Test and release → App integrity → Play app signing → Settings: copy the SHA-1 of **App signing key certificate** and of **Upload key certificate** (search Play Console for "App signing" if the menu moved). If there is no app signing key yet (no AAB uploaded), run in your own Terminal `keytool -list -v -keystore ~/.shellx-release/shellx-upload.jks` (it asks for the store password; never paste it in chat) and copy its `SHA1:` line; client 5 is then `pending (3H)`.

- [ ] **Step 4: USER — create the clients.** Google Auth Platform → **Clients → + Create client**, once per row. Reuse a client that already exists with the same name or the same package + SHA-1 (plan 1C Task 8 Step 5 may have made clients 1–2; Firebase may have auto-created an Android client); Google refuses a duplicate package + SHA-1.

| # | Application type | Name | Fields |
| --- | --- | --- | --- |
| 1 | iOS | `ShellX iOS` | Bundle ID `com.shellx.prod`, Team ID `W4RF3W4VTZ` |
| 2 | iOS | `ShellX iOS (dev)` | Bundle ID `com.shellx.dev`, Team ID `W4RF3W4VTZ` |
| 3 | Android | `ShellX Android (dev)` | Package `com.shellx.dev`, SHA-1 from Step 1 |
| 4 | Android | `ShellX Android (upload key)` | Package `com.shellx.prod`, upload key SHA-1 |
| 5 | Android | `ShellX Android (Play signing)` | Package `com.shellx.prod`, app signing key SHA-1 (skip while pending) |
| 6 | Web application | `ShellX Web (Android sign-in)` | no JavaScript origins, no redirect URIs |
| 7 | Desktop app | `ShellX Desktop` | — ; in the "OAuth client created" dialog press **Download JSON**: Google shows the secret only now |

  No redirect URI is entered anywhere: the iOS clients use the reversed-client-ID scheme `com.googleusercontent.apps.<prefix>:/oauth2redirect` on their own, the Desktop client accepts the `http://127.0.0.1:<port>/oauth2/callback` loopback without registration, and the Web client is only Android's `serverClientId`. Then paste in the chat the client IDs of rows 1–7 and the SHA-1s you used. Never paste the Desktop client secret. Never delete these clients or reset the Desktop secret after a release: every installed app carries them.

- [ ] **Step 5: Check and record the IDs.** Each ID must match `^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$`, and all of them must start with the same digits (the project number). Fill the ledger table (IDs, SHA-1s, `pending (3H)` where skipped) and the consent-screen line ("In production", date). A mismatch → ask the user to recheck that row.

- [ ] **Step 6: USER — the Desktop secret file.** In your own Terminal (not the chat), with the JSON downloaded in Step 4:

```bash
umask 077; mkdir -p ~/.shellx-release && python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["installed"]; print("SHELLX_GOOGLE_DESKTOP_CLIENT_ID=" + d["client_id"]); print("SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET=" + d["client_secret"])' "<the downloaded client_secret_….json>" > ~/.shellx-release/google-desktop-oauth.env
```

  Then keep the JSON in your password manager or delete it. Include `~/.shellx-release` in the backup you already keep of the upload key. Note for the executor: if the user ever pastes the secret in the chat, do not repeat it; before 1.8.0 ships, ask them to add a new secret to client 7 (Clients → ShellX Desktop → Add secret), rewrite the file with it and disable the old one; after 1.8.0 ships, leave it (installed apps carry it; Google treats a desktop client secret as not confidential).

- [ ] **Step 7: Check the file without printing it**

```bash
stat -f '%Lp' ~/.shellx-release/google-desktop-oauth.env
grep -c -E '^SHELLX_GOOGLE_DESKTOP_CLIENT_ID=[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$' ~/.shellx-release/google-desktop-oauth.env
grep -c -E '^SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET=[A-Za-z0-9_-]+$' ~/.shellx-release/google-desktop-oauth.env
grep -c -v -E '^SHELLX_GOOGLE_DESKTOP_CLIENT_(ID|SECRET)=' ~/.shellx-release/google-desktop-oauth.env
grep -c -F 'SHELLX_GOOGLE_DESKTOP_CLIENT_ID=<client 7 ID from the ledger>' ~/.shellx-release/google-desktop-oauth.env
```

  Expected: `600`, `1`, `1`, `0`, `1`. Record "checked <date>" in the ledger.

- [ ] **Step 8: iPhone client IDs.** Needs 1C on `develop`: first `git -C W merge --no-edit develop`. Then `grep -n '^SHELLX_GOOGLE_IOS_CLIENT = ' shellx-ios/Config/Debug.xcconfig shellx-ios/Config/Release.xcconfig` in `W`.
  - If both already hold real prefixes equal to clients 2 and 1: skip to Step 10.
  - If they hold `0-shellx-placeholder`: set Debug to client 2's ID without `.apps.googleusercontent.com`, Release to client 1's. No other line changes.
  - If the line does not exist, 1C has not landed: come back to this step later.

- [ ] **Step 9: Verify and commit the IDs.** `pgrep -fl xcodebuild` must show no ShellX build from another checkout (wait if it does). Run `shellx-ios/scripts/dev.sh test release` in `W`. Expected: `==> test release: passed` and no line containing `is not a Google iOS client id yet`. Then:

```bash
git -C /Users/lehuuphu/Documents/myProjects/shellx/.claude/worktrees/signin-1d-rollout add shellx-ios/Config/Debug.xcconfig shellx-ios/Config/Release.xcconfig
git -C /Users/lehuuphu/Documents/myProjects/shellx/.claude/worktrees/signin-1d-rollout commit -m "chore(shellx-ios): Google iOS client ids"
```

- [ ] **Step 10: Android Web client id, then the ledger.** Contracts §16 has 1D fill it from the ledger; plan 3H refuses a release while it is a placeholder. After `git -C W merge --no-edit develop`, run `grep -n 'google_web_client_id' W/shellx-android/app/src/main/res/values/google_oauth.xml` (with `W` substituted):
  - it holds client 6's ID: nothing to do;
  - it holds a value that does not match `^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$` (plan 3D's placeholder `0-shellx-placeholder.apps.googleusercontent.com`): put client 6's full ID in its place, change nothing else, run `(cd W && shellx-android/scripts/dev.sh test app)` (expected `==> test app: passed`; 3D's `GoogleWebClient` tests accept a real ID), then `git -C W add shellx-android/app/src/main/res/values/google_oauth.xml && git -C W commit -m "chore(shellx-android): Google Web client id"`;
  - it holds another Google client ID: stop and ask the user which one is right;
  - the file does not exist (plan 3D has not landed): write `google_web_client_id: pending (3D)` under "Hand-off to 3D / 3H" and redo this step at Task 9 Step 1 and Task 20 Step 1.

  Then commit the ledger (`<what>` = `Google OAuth clients`).

---

### Task 2: Release builds carry the Desktop OAuth client

The Mac and Windows apps get the Desktop client at build time (`option_env!`, contracts §10). The Mac's Xcode build inherits the shell's environment, but the Windows release build runs in Docker on the VPS (`build-windows-cross.sh`), which receives nothing from the Mac. The executor does this task while the user works on Tasks 1, 3 and 4.

**Files:**
- Create: `scripts/shellx/release/google-desktop-client.sh`
- Modify: `scripts/shellx/sign-and-notarize.sh` (source the helper after `REPO_ROOT=`; `build_app`, lines 39-66)
- Modify: `scripts/shellx/release/build-windows-cross.sh` (top, header comment "Env:", step 3 at lines 83-93)
- Modify: `windows/cross/build-in-container.sh` (after `cd /src/windows`; after the `shellx-app` build step)
- Test: `deploy/tests/release-google-client.test.mjs` (create)

**Interfaces:**
- Produces, in `scripts/shellx/release/google-desktop-client.sh` (sourced, bash 3.2 compatible):
  - `shellx_require_google_desktop_client`: returns 0 silently when `SHELLX_GOOGLE_DESKTOP_CLIENT_ID` matches `^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$` and `SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET` matches `^[A-Za-z0-9_-]+$`. Otherwise prints one line to stderr and returns 1, checking the ID first:
    - `error: SHELLX_GOOGLE_DESKTOP_CLIENT_ID is missing or not a Google OAuth client id; a release build needs the Desktop OAuth client (set -a; . ~/.shellx-release/google-desktop-oauth.env; set +a)`
    - `error: SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET is missing or malformed; a release build needs the Desktop OAuth client (set -a; . ~/.shellx-release/google-desktop-oauth.env; set +a)`
  - `shellx_binary_has_google_desktop_client <file-or-directory>`: returns 0 when both values occur in the bytes under that path (`grep -r -q -a -F`), 1 otherwise; prints nothing. Each value goes to grep through `-f <(printf '%s\n' "$value")`, never as an argument, so it never shows in a process list.
- Produces the console lines Task 10 expects: `==> Google Desktop OAuth client: present` (Mac, stderr) and `== Google Desktop OAuth client: present` (Windows container).

- [ ] **Step 1: Write the failing tests** in `deploy/tests/release-google-client.test.mjs`:

```js
// Plan 1D Task 2: desktop release builds carry the Google Desktop OAuth client. The scripts run from a
// sandbox copy (REPO_ROOT = the sandbox), against fake ensure-ghosttykit, xcodebuild and ssh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const HELPER = 'scripts/shellx/release/google-desktop-client.sh';
const ID = '123456789012-abcdefghijklmnopqrstuvwxyz012345.apps.googleusercontent.com';
const SECRET = 'GOCSPX-fake-0123456'; // short on purpose: the secret scans of Tasks 9 and 10 look for 20+ characters
const GOOD = { SHELLX_GOOGLE_DESKTOP_CLIENT_ID: ID, SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET: SECRET };
const env = (extra = {}) => ({ PATH: process.env.PATH, HOME: process.env.HOME, ...extra });
const withBin = (root, extra = {}) => env({ PATH: `${join(root, 'bin')}:${process.env.PATH}`, ...extra });

function sandbox(...rels) {
  const root = mkdtempSync(join(tmpdir(), 'shellx-release-'));
  for (const rel of rels) { mkdirSync(dirname(join(root, rel)), { recursive: true }); cpSync(join(repo, rel), join(root, rel)); }
  return root;
}
function script(path, body) { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, `#!/usr/bin/env bash\n${body}\n`); chmodSync(path, 0o755); }
const sourced = (call, extra) => spawnSync('bash', ['-c', `. "${join(repo, HELPER)}" && ${call}`], { encoding: 'utf8', env: env(extra) });

const FAKE_XCODEBUILD = `prev=; dd=
for a in "$@"; do [[ "$prev" == -derivedDataPath ]] && dd="$a"; prev="$a"; done
bin="$dd/Build/Products/Release/ShellX.app/Contents/MacOS/ShellX"; mkdir -p "$(dirname "$bin")"
if [[ "$FAKE_EMBED" == yes ]]; then printf 'x\\0%s\\0%s\\0' "$SHELLX_GOOGLE_DESKTOP_CLIENT_ID" "$SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET" > "$bin"; else printf 'x\\0' > "$bin"; fi`;

const FAKE_SSH = `i=$(( $(ls "$CALLS" | grep -c '\\.argv$') + 1 ))
printf '%s' "$*" > "$CALLS/$i.argv"; cat > "$CALLS/$i.stdin"
case "$*" in
  *"cat ~/phu/shellx/.winbuild/out/ShellX-Setup-9.9.9.exe"*) printf 'EXE' ;;
  *"cat ~/phu/shellx/.winbuild/out/SHA256SUMS"*) printf '%s  ShellX-Setup-9.9.9.exe\\n' "$(printf 'EXE' | shasum -a 256 | cut -d' ' -f1)" ;;
esac
exit 0`;

test('the guard names the missing or malformed variable and never prints a value', () => {
  for (const [extra, name] of [
    [{}, 'SHELLX_GOOGLE_DESKTOP_CLIENT_ID'],
    [{ ...GOOD, SHELLX_GOOGLE_DESKTOP_CLIENT_ID: '0-shellx-placeholder' }, 'SHELLX_GOOGLE_DESKTOP_CLIENT_ID'],
    [{ SHELLX_GOOGLE_DESKTOP_CLIENT_ID: ID }, 'SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET'],
    [{ ...GOOD, SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET: 'has space' }, 'SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET'],
  ]) {
    const r = sourced('shellx_require_google_desktop_client', extra);
    assert.deepEqual([r.status, r.stdout], [1, ''], name);
    assert.match(r.stderr, new RegExp(`^error: ${name} `));
    for (const value of Object.values(extra)) assert.ok(!r.stderr.includes(value), 'a value was printed');
  }
  const ok = sourced('shellx_require_google_desktop_client', GOOD);
  assert.deepEqual([ok.status, ok.stdout, ok.stderr], [0, '', '']);
});

test('the binary check needs both values in the built bytes and prints nothing', () => {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-bin-'));
  writeFileSync(join(dir, 'both'), Buffer.concat([Buffer.from([0, 1]), Buffer.from(ID), Buffer.from([0]), Buffer.from(SECRET), Buffer.from([255])]));
  writeFileSync(join(dir, 'id-only'), Buffer.concat([Buffer.from(ID), Buffer.from([0])]));
  const run = (f) => sourced(`shellx_binary_has_google_desktop_client "${join(dir, f)}"`, GOOD);
  for (const [f, status] of [['both', 0], ['id-only', 1]]) assert.deepEqual([run(f).status, run(f).stdout, run(f).stderr], [status, '', ''], f);
});

test('sign-and-notarize.sh --build needs the client before building, and in the built app', () => {
  const root = sandbox('scripts/shellx/sign-and-notarize.sh', HELPER);
  const marker = join(root, 'ensure.called');
  script(join(root, 'scripts/ensure-ghosttykit.sh'), `touch "${marker}"`);
  script(join(root, 'bin/xcodebuild'), FAKE_XCODEBUILD);
  const run = (extra) => spawnSync('bash', [join(root, 'scripts/shellx/sign-and-notarize.sh'), '--build', join(root, 'dd')], { encoding: 'utf8', env: withBin(root, extra) });
  const refused = run({});
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /^error: SHELLX_GOOGLE_DESKTOP_CLIENT_ID /m);
  assert.equal(existsSync(marker), false, 'the build started without the client');
  const missing = run({ ...GOOD, FAKE_EMBED: 'no' });
  assert.deepEqual([missing.status, missing.stdout], [1, '']);
  assert.match(missing.stderr, /does not carry the Google Desktop OAuth client/);
  const built = run({ ...GOOD, FAKE_EMBED: 'yes' });
  assert.equal(built.status, 0, built.stderr);
  assert.match(built.stdout, /\/dd\/Build\/Products\/Release\/ShellX\.app\n$/);
  assert.match(built.stderr, /==> Google Desktop OAuth client: present/);
  for (const r of [refused, missing, built]) assert.ok(!(r.stdout + r.stderr).includes(SECRET));
});

test('build-windows-cross.sh refuses before any ssh without the client', () => {
  const root = sandbox('scripts/shellx/release/build-windows-cross.sh', HELPER);
  const log = join(root, 'ssh.log');
  script(join(root, 'bin/ssh'), `echo "$*" >> "${log}"; exit 1`);
  const r = spawnSync('bash', [join(root, 'scripts/shellx/release/build-windows-cross.sh'), join(root, 'out')], { encoding: 'utf8', input: '', env: withBin(root, { SHELLX_GOOGLE_DESKTOP_CLIENT_ID: ID }) });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /^error: SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET /m);
  assert.equal(existsSync(log), false, 'ssh ran without the client');
});

test('build-windows-cross.sh gives the container the client on stdin, never on a command line', () => {
  const root = sandbox('scripts/shellx/release/build-windows-cross.sh', HELPER);
  for (const [rel, text] of Object.entries({
    'windows/Cargo.toml': '[workspace.package]\nversion = "9.9.9"\n', 'windows/cross/Dockerfile': 'FROM scratch\n',
    'cmux-tui/README.md': 'x\n', 'shellx-core/README.md': 'x\n',
    '.gitmodules': '[submodule "ghostty"]\n\tpath = ghostty\n\turl = https://example.invalid/ghostty.git\n',
  })) { mkdirSync(dirname(join(root, rel)), { recursive: true }); writeFileSync(join(root, rel), text); }
  const git = (...args) => assert.equal(spawnSync('git', ['-C', root, ...args]).status, 0, args.join(' '));
  git('init', '-q'); git('add', 'windows', 'cmux-tui', 'shellx-core', '.gitmodules');
  git('update-index', '--add', '--cacheinfo', `160000,${'a'.repeat(40)},ghostty`);
  git('-c', 'user.name=t', '-c', 'user.email=t@t.invalid', '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'fixture');
  const calls = join(root, 'calls'); mkdirSync(calls);
  script(join(root, 'bin/ssh'), FAKE_SSH);
  const r = spawnSync('bash', [join(root, 'scripts/shellx/release/build-windows-cross.sh'), join(root, 'out')], { encoding: 'utf8', input: '', env: withBin(root, { CALLS: calls, ...GOOD }) });
  assert.equal(r.status, 0, r.stderr);
  const n = readdirSync(calls).filter((f) => f.endsWith('.argv')).length;
  const argv = (i) => readFileSync(join(calls, `${i}.argv`), 'utf8');
  for (let i = 1; i <= n; i++) assert.ok(!argv(i).includes(ID) && !argv(i).includes(SECRET), `ssh call ${i} carries a value in its arguments`);
  const builds = Array.from({ length: n }, (_, i) => i + 1).filter((i) => argv(i).includes('build-in-container.sh'));
  assert.equal(builds.length, 1);
  assert.match(argv(builds[0]), /-e SHELLX_GOOGLE_DESKTOP_CLIENT_ID -e SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET\s/);
  assert.equal(readFileSync(join(calls, `${builds[0]}.stdin`), 'utf8'), `${ID}\n${SECRET}\n`);
  assert.ok(!(r.stdout + r.stderr).includes(SECRET));
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `(cd W && node --test deploy/tests/release-google-client.test.mjs)`
Expected: `# fail 5`. The helper file does not exist (the first two and the copies fail), the Mac build starts without the client, and the Windows script fails on `cannot read windows/Cargo.toml version` or runs ssh.

- [ ] **Step 3: Implement**
  - `scripts/shellx/release/google-desktop-client.sh`: the two functions of the Interfaces block, with a header comment saying the Desktop client is compiled in at build time (contracts §10), the values live in `~/.shellx-release/google-desktop-oauth.env`, and nothing here prints a value.
  - `scripts/shellx/sign-and-notarize.sh`: after `REPO_ROOT=…`, source `"$SCRIPT_DIR/release/google-desktop-client.sh"`. First line of `build_app`: `shellx_require_google_desktop_client || exit 1`. After `xcodebuild … build >&2` and before `echo "$products/$PRODUCT_NAME.app"`: when `shellx_binary_has_google_desktop_client "$products/$PRODUCT_NAME.app/Contents/MacOS"` fails, print `error: $products/$PRODUCT_NAME.app does not carry the Google Desktop OAuth client; rebuild with the client loaded` to stderr and `exit 1`; otherwise print `==> Google Desktop OAuth client: present` to stderr. Add the two variables to the header's "Optional env" list as required for `--build`.
  - `scripts/shellx/release/build-windows-cross.sh`: right after `set -euo pipefail`, source `"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/google-desktop-client.sh"` and run `shellx_require_google_desktop_client || exit 1`. In step 3, pipe `printf '%s\n%s\n' "$SHELLX_GOOGLE_DESKTOP_CLIENT_ID" "$SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET"` into that `vssh`; the remote script starts `set -euo pipefail`, then `IFS= read -r SHELLX_GOOGLE_DESKTOP_CLIENT_ID`, `IFS= read -r SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET`, `export SHELLX_GOOGLE_DESKTOP_CLIENT_ID SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET`; append ` -e SHELLX_GOOGLE_DESKTOP_CLIENT_ID -e SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET` right after `-e CMUX_TUI_BUILD_COMMIT=$commit` (names only: `docker run` takes the values from its environment). Add both to the header's "Env:" list.
  - `windows/cross/build-in-container.sh`: after `cd /src/windows`, refuse unless both variables match the two regexes above, with `error: SHELLX_GOOGLE_DESKTOP_CLIENT_ID / SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET missing or malformed (build-windows-cross.sh passes them)` and `exit 1`. After `exe=…`, check both values are in `$exe` with `grep -q -a -F -f <(printf '%s\n' "…")`; on failure `error: shellx-desktop.exe does not carry the Google Desktop OAuth client` and `exit 1`; on success `echo "== Google Desktop OAuth client: present"`. (Lines starting `==` or `error` pass the host's output filter.)

- [ ] **Step 4: Run the tests to see them pass**

Run: `(cd W && node --test deploy/tests/release-google-client.test.mjs && node --test deploy/tests/*.test.mjs && bash -n scripts/shellx/sign-and-notarize.sh scripts/shellx/release/build-windows-cross.sh windows/cross/build-in-container.sh scripts/shellx/release/google-desktop-client.sh)`
Expected: `# fail 0` twice; `bash -n` prints nothing.

- [ ] **Step 5: Commit**

```bash
git -C W add scripts/shellx/release/google-desktop-client.sh scripts/shellx/sign-and-notarize.sh scripts/shellx/release/build-windows-cross.sh windows/cross/build-in-container.sh deploy/tests/release-google-client.test.mjs
git -C W commit -m "build(shellx): desktop release builds require and check the Google Desktop OAuth client"
```

(`W` stands for the absolute path of the worktree.)

---

### Task 3: Sign in with Apple — App IDs and the key (USER)

**Interfaces:**
- Produces: ledger "Apple" lines: capability state of both App IDs, key name, Key ID (10 characters, `^[A-Z0-9]{10}$`).
- Decision (Spec note 2): `com.shellx.prod` is the primary App ID; `com.shellx.dev` is grouped with it, so the one key the relay holds (contracts §2 has one `APPLE_SIWA_KEY_ID`) can mint client secrets for both bundles.

- [ ] **Step 1: USER — App IDs.** https://developer.apple.com/account/resources/identifiers/list:
  - `com.shellx.prod` → Capabilities → tick **Sign In with Apple** → **Edit** → **Enable as a primary App ID** → Save → Save → Confirm.
  - `com.shellx.dev` → Capabilities → tick **Sign In with Apple** → **Edit** → **Group with an existing primary App ID** → `com.shellx.prod` → Save → Save → Confirm. If plan 1C Task 8 Step 6 already enabled it as a primary App ID, open the same Edit dialog and switch it to the group.

- [ ] **Step 2: USER — the key.** https://developer.apple.com/account/resources/authkeys/list → **+** → Key Name `ShellX Sign in with Apple` → tick **Sign in with Apple** → **Configure** → Primary App ID `com.shellx.prod` → Save → Continue → Register → **Download** (`AuthKey_<KEYID>.p8`, downloadable once). Keep it in your password manager and in a private folder on this Mac until Task 5; never in the repository or the chat. Paste only the Key ID.

- [ ] **Step 3: Record** in the ledger "Apple": both capability states, the key name, the Key ID (check the regex), and that the `.p8` waits for Task 5. Commit the ledger (`<what>` = `Apple`).

Rollback: a wrong key → revoke it on the Keys page and make a new one (Task 5 then uploads the new file and Key ID). Removing the capability later breaks Apple sign-in in released iPhone builds.

---

### Task 4: Firebase — the dev app and the Android API key restriction

**Interfaces:**
- Consumes: SHA-1s from Task 1; plan 3A Task 10 (the Firebase files).
- Produces: ledger "Firebase": `google-services.json` state, the key's last 6 characters, the restriction entries, items pending for 3H.

- [ ] **Step 1: Check the Firebase files** in `W` (after `git -C W merge --no-edit develop`):

```bash
for f in shellx-android/app/src/{debug,release}/google-services.json; do python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["project_info"]["project_id"], ",".join(sorted(c["client_info"]["android_client_info"]["package_name"] for c in d["client"])))' "$f"; done
```

  Expected, twice: `shellxpro com.shellx.dev,com.shellx.prod`. If a file is missing or `com.shellx.dev` is absent, do plan 3A Task 10 (Steps 1–5) in `W` exactly as written there, then rerun this step.

- [ ] **Step 2: Print the key to restrict** (non-secret, committed): `python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sorted({k["current_key"][-6:] for c in d["client"] for k in c["api_key"]}))' shellx-android/app/src/release/google-services.json`. Expected: one 6-character value.

- [ ] **Step 3: USER — restrict it.** https://console.cloud.google.com/apis/credentials?project=shellxpro → API keys → the key whose **Show key** ends with those 6 characters (usually "Android key (auto created by Firebase)") → **Application restrictions: Android apps** → **+ Add** each: `com.shellx.prod` + upload key SHA-1; `com.shellx.prod` + app signing key SHA-1 (only when known); `com.shellx.dev` + debug SHA-1 (only when known) → leave **API restrictions** unchanged → **Save**. The relay never uses this key (it uses the service account), so nothing in production changes.

- [ ] **Step 4: Record** the results and every `pending (3H)` item (Play signing SHA-1 for the API key and for client 5; debug SHA-1 if Task 1 Step 1 found no keystore) under "Firebase" and "Hand-off to 3D / 3H". Commit the ledger (`<what>` = `Firebase`).

---

### Task 5: VPS environment and the Phase 0 check

**Interfaces:**
- Consumes: client IDs 1, 2, 6, 7 (Task 1), the Key ID and `.p8` (Task 3).
- Produces: the VPS `.env` lines of Global Constraints "Values"; `~/phu/shellx/secrets/siwa.p8` (uid 1000, mode 400). The running relay ignores both until Phase 1: today's `docker-compose.yml` passes only the variables it lists, and `rollout.sh` keeps every `.env` line across deploys.

- [ ] **Step 1: Nothing to clash with.** `VPS-RO grep -c -E "^(GOOGLE_CLIENT_IDS|APPLE_TEAM_ID|APPLE_SIWA_KEY_ID|APPLE_SIWA_KEY_PATH|APPLE_CLIENT_IDS|PASSWORD_LOGIN|TEST_IDP_ISSUER|TEST_IDP_JWKS_PATH)=" .env`. Expected: `0`. Otherwise, before Step 3, give the user (VPS shell) one `sed -i '/^NAME=/d' .env` per name found.

- [ ] **Step 2: USER — upload the key.** VPS shell: `mkdir -m 700 -p ~/siwa-upload`. Your own Mac Terminal: `scp -o ControlPath=~/.ssh/cm-shellx-vps "<path of AuthKey_<KEYID>.p8>" higio@42.115.41.70:siwa-upload/siwa.p8`. VPS shell: `sudo install -o 1000 -g 1000 -m 400 ~/siwa-upload/siwa.p8 ~/phu/shellx/secrets/siwa.p8 && rm -rf ~/siwa-upload`.

- [ ] **Step 3: USER — the `.env` lines** (file `~/phu/shellx/.env` on the VPS). The executor fills in the four client IDs (order: 1, 2, 6, 7) and the Key ID from the ledger and gives the user this one VPS-shell line:

```bash
{ [ -z "$(tail -c1 .env)" ] || echo >> .env; } && printf '%s\n' 'GOOGLE_CLIENT_IDS=<id1>,<id2>,<id6>,<id7>' 'APPLE_TEAM_ID=W4RF3W4VTZ' 'APPLE_SIWA_KEY_ID=<KEYID>' 'APPLE_SIWA_KEY_PATH=/secrets/siwa.p8' >> .env && chmod 600 .env
```

  Do not recreate the relay now.

- [ ] **Step 4: Phase 0 check**

```bash
VPS-RO grep -E "^(GOOGLE_CLIENT_IDS|APPLE_TEAM_ID|APPLE_SIWA_KEY_ID|APPLE_SIWA_KEY_PATH|APPLE_CLIENT_IDS|PASSWORD_LOGIN|TEST_IDP_ISSUER|TEST_IDP_JWKS_PATH|FCM_SERVICE_ACCOUNT|APNS_KEY_PATH)=" .env; stat -c "%n %u:%g %a" .env secrets/siwa.p8 secrets/fcm.json secrets/apns.p8
```

  Expected: exactly six `.env` lines: `GOOGLE_CLIENT_IDS=` with the four ledger IDs in order, `APPLE_TEAM_ID=W4RF3W4VTZ`, `APPLE_SIWA_KEY_ID=<KEYID>`, `APPLE_SIWA_KEY_PATH=/secrets/siwa.p8`, `FCM_SERVICE_ACCOUNT=/secrets/fcm.json`, `APNS_KEY_PATH=/secrets/apns.p8`. Then `.env … 600`, and `1000:1000 400` for each of the three key files. No `APPLE_CLIENT_IDS`, `PASSWORD_LOGIN` or `TEST_IDP_*` line.

- [ ] **Step 5: Close Phase 0.** Tasks 1–5 done (Task 2 may still be open), `pending (3H)` items listed. Ledger: Status "0 Preparation" → `done`, the VPS section filled. Commit (`<what>` = `phase 0`).

Rollback: nothing that runs has changed. To undo, delete the four lines (`sed -i`) and `secrets/siwa.p8`, revoke the Apple key, delete the Google clients.

---

## Phase 1 — Relay deploy (1A + 3F together)

### Task 6: Deploy the relay

**Interfaces:**
- Consumes: `A1`, `F3` (Task 0), the Phase 0 VPS state.
- Produces: `main` = `develop` at the deployed commit, recorded as "Phase 1 deploy" in the ledger.

- [ ] **Step 1: Preconditions in `M`.** Task 0 Step 3 shows `A1` and `F3`. Then:

```bash
git -C /Users/lehuuphu/Documents/myProjects/shellx branch --show-current            # develop
git -C /Users/lehuuphu/Documents/myProjects/shellx pull --ff-only origin develop
git -C /Users/lehuuphu/Documents/myProjects/shellx status --short -- relay web deploy  # must print nothing
(cd /Users/lehuuphu/Documents/myProjects/shellx/relay && npm ci && npm test && npm run typecheck && npm run build)
(cd /Users/lehuuphu/Documents/myProjects/shellx && node --test deploy/tests/*.test.mjs)
(cd /Users/lehuuphu/Documents/myProjects/shellx/web && npm ci && npm run build)
```

  Expected: `develop`; nothing from `status`; no failed vitest file and no `error TS`; `# fail 0` twice.

- [ ] **Step 2: Foreign keys on the newest backup** (the README's G2 pre-check, on a copy, never the live file):

```bash
ssh -S ~/.ssh/cm-shellx-vps -o BatchMode=yes higio@42.115.41.70 'cd phu/shellx && docker compose exec -T backup sh -s' <<'EOF'
B=$(ls -1t /backups/relay-*.db | head -n 1); echo "$B"; sqlite3 -readonly "$B" 'PRAGMA foreign_key_check;' | wc -l
EOF
```

  Expected: a `/backups/relay-<date>.db` path and `0`. Any other number: stop and report; migration 0010 would fail closed.

- [ ] **Step 3: What deploys.** `git -C /Users/lehuuphu/Documents/myProjects/shellx log --oneline origin/main..develop -- relay web deploy`. Put this list in the go-ahead question.

- [ ] **Step 4: Gate.** Ask (Vietnamese): deploy relay + web from `develop` (list above; 1A + 3F; the privacy page of 1A goes live too), Phase 0 checked, foreign-key check `0`, the fix-forward rule. Wait for an explicit yes.

- [ ] **Step 5: Push `develop`** (executor): `git -C /Users/lehuuphu/Documents/myProjects/shellx push origin develop`.

- [ ] **Step 6: USER — `main`.** `! cd /Users/lehuuphu/Documents/myProjects/shellx && git push origin develop:main`. Then the executor: `git -C /Users/lehuuphu/Documents/myProjects/shellx fetch origin && test "$(git -C /Users/lehuuphu/Documents/myProjects/shellx rev-parse origin/main)" = "$(git -C /Users/lehuuphu/Documents/myProjects/shellx rev-parse develop)" && echo main-is-develop` → `main-is-develop`. (If GitHub Actions works again, this push starts `deploy.yml`; then skip Step 8 and watch that run instead.)

- [ ] **Step 7: Dry run.** Shared connection check (Global Constraints); `git -C /Users/lehuuphu/Documents/myProjects/shellx merge-base --is-ancestor <A1> HEAD && echo has-1A` → `has-1A`; `(cd /Users/lehuuphu/Documents/myProjects/shellx && deploy/vps-deploy.sh --dry-run)`. Expected: the last step line `==> Dry run finished: nothing was run on higio@42.115.41.70` and no line containing `a real run would refuse here`.

- [ ] **Step 8: USER — deploy.** `! cd /Users/lehuuphu/Documents/myProjects/shellx && bash deploy/vps-deploy.sh`. Expected last step line: `==> Deployed <sha12> to higio@42.115.41.70:phu/shellx`. If it reports a lost connection or a timeout, the rollout goes on by itself: run the two look commands it prints; running the script again heals.

- [ ] **Step 9: Record** the deployed SHA and time under "Releases"; commit the ledger (`<what>` = `phase 1 deploy`).

---

### Task 7: Verify Phase 1

**Interfaces:**
- Consumes: the deployed relay; ShellX Dev from `W` (it holds the real iOS client IDs after Task 1).
- Produces: ledger "Checks" lines E1–E5, L1, M1, S1, U1 and live checks P1a–P1b.

- [ ] **Step 1: Public endpoints**

```bash
curl -s -X POST https://relay.shellx.pro/v1/auth/nonce -H 'content-type: application/json' -d '{}' -w '\n%{http_code}\n'
curl -s -X POST https://relay.shellx.pro/v1/auth/register -H 'content-type: application/json' -d '{}' -w '\n%{http_code}\n'
curl -s -X POST https://relay.shellx.pro/v1/auth/login -H 'content-type: application/json' -d '{}' -w '\n%{http_code}\n'
curl -s -X POST https://relay.shellx.pro/v1/auth/google -H 'content-type: application/json' -d '{"id_token":"x","nonce":"y","device":{"kind":"mobile","name":"check","platform":"ios","public_key":"x"}}' -w '\n%{http_code}\n'
curl -s -H 'X-ShellX-Platform: macos' https://relay.shellx.pro/v1/version
```

  Expected: E1 `{"nonce":"<43 base64url chars>","expires_in":600}` then `201`; E2 code `registration_closed` then `410`; E3 status `400` (not `410`: passwords stay on until Phase 4); E4 `400` or `401` (the route exists; not `404`); E5 `"min_agent":"1.2.0"` and `"version":"1.7.0"` (unchanged).

- [ ] **Step 2: Startup events**

```bash
VPS-RO docker compose logs relay 2>/dev/null | grep -o -E "google_sign_in_disabled|apple_siwa_enabled|apple_siwa_disabled|test_idp_enabled|password_login_off|push_enabled|push_disabled|apns_enabled|apns_disabled" | sort | uniq -c
VPS-RO docker compose logs relay 2>/dev/null | grep push_enabled | tail -n 1
```

  Expected (L1): exactly three names, `apns_enabled`, `apple_siwa_enabled`, `push_enabled`; the last line mentions `shellxpro`. Any other name: stop. `google_sign_in_disabled` → `GOOGLE_CLIENT_IDS` missing; `apple_siwa_disabled` → key path or Key ID wrong; `push_disabled` → `FCM_SERVICE_ACCOUNT` (deploy/README "Android push (FCM)"). Fix `.env` (USER, VPS shell) and `docker compose up -d --force-recreate relay`, then repeat this step.

- [ ] **Step 3: Migration applied** (M1)

```bash
ssh -S ~/.ssh/cm-shellx-vps -o BatchMode=yes higio@42.115.41.70 'cd phu/shellx && docker compose exec -T backup sh -s' <<'EOF'
sqlite3 -readonly /data/relay.db "SELECT COUNT(*) FROM schema_migrations WHERE name = '0010_identities.sql';"
EOF
```

  Expected: `1`.

- [ ] **Step 4: USER — relay2 smoke** (S1). First the executor runs `(cd /Users/lehuuphu/Documents/myProjects/shellx/relay && npm ci)`. Then the user, in their own Terminal (the smoke asks questions):

```bash
cd ~/Documents/myProjects/shellx/relay && SHELLX_SMOKE_TOKEN="$(ssh -S ~/.ssh/cm-shellx-vps higio@42.115.41.70 'cd phu/shellx && docker compose exec -T relay npm run -s mint-smoke-token')" npm run relay2:smoke
```

  Press Enter at `API base [https://relay.shellx.pro]:` if asked. Expected last line: `relay2 smoke: OK (registered, lease <n> s)`.

- [ ] **Step 5: USER — old apps untouched** (U1). Your Mac (1.7.0) still shows you signed in; the iPhone app paired with it still opens a workspace of that Mac.

- [ ] **Step 6: USER — live checks on the simulator** (S1 §2.1 / §6.8; the real iPhone keeps its pairing). Needs 1C on `develop` and Task 1 Step 9 done; if 1C lands later, run this step then, before Task 10. Executor: `git -C W merge --no-edit develop`; `pgrep -fl xcodebuild` shows no other ShellX build; `(cd W && shellx-ios/scripts/dev.sh sim)`; it exits 0 and the Simulator shows ShellX Dev (Debug builds talk to `https://relay.shellx.pro`). USER, in the Simulator:
  - **P1a (criterion 4, only if your ShellX account's email is a Google account):** Continue with Google with that Google account. Expected: "This email already has a ShellX account. Open ShellX on a device that is still signed in, go to Settings › Account › Switch to Google sign-in, then try again." and nothing else changes.
  - **P1b (G3, §6.8, criterion 5), three times, with a throwaway Google account:** Continue with Google → start a stopwatch when Google's sheet closes → stop it when the app shows the first-Mac screen (a new, empty account) → Settings › Account › Delete Account… → Delete Account → sign in with the same Google account → back at the sign-in screen. Expected: all three times under 2 s; each deletion ends at the sign-in screen.
  Record P1a / P1b in "Live checks" with the times.

- [ ] **Step 7: Close Phase 1.** All of Steps 1–6 as expected → Status "1 Relay deploy" → `done`; commit the ledger (`<what>` = `phase 1 verified`).

Rollback:
- An unhealthy rollout puts back the previous config and `IMAGE_TAG` by itself. Then run `VPS-BK` with `sqlite3 -readonly /data/relay.db "SELECT COUNT(*) FROM users WHERE password_hash IS NULL;"`: it must print `0`. Anything else means passwordless accounts face the pre-1A relay (Global Constraints "Fix forward"): tell the user at once and fix forward (a fixed commit through `develop` → `main` → deploy).
- A healthy relay with a wrong setting: correct `.env` (USER, VPS shell) and `docker compose up -d --force-recreate relay`.
- A code defect: fix forward on a branch from `develop` with a failing test first, the user's merge directive, then Task 6 Steps 5–8. Never `IMAGE_TAG` below `A1`.

---

## Landing L1

### Task 8: Website copy for Google sign-in

Published by the Phase 2 pointer deploy (Task 13), when desktop 1.8.0 exists. Wording follows contracts §12: the in-app deletion path is "Settings › Account › Delete Account…".

**Files:**
- Modify: `web/src/i18n/ui.ts` (`step1`)
- Modify: `web/src/pages/terms.md` (`updated:`, §2 third bullet, §10 first sentence)
- Modify: `web/src/pages/privacy.md` (only if it still has `Settings → Account → Delete account` or `Settings → Delete account`: those and `updated:`)
- Test: `web/tests/site.test.mjs`

- [ ] **Step 1: Write the failing test.** In `web/tests/site.test.mjs`, the privacy loop's in-app needle must be `'Settings › Account › Delete Account…'`: plan 1A Task 15 already writes it; change any older needle (`'Settings → Account → Delete account'` or `'Settings → Delete account'`) to it. Then add:

```js
test('the website points at Google sign-in and at the in-app deletion path of the phone apps', () => {
  const home = readPage('/');
  assert.ok(home.includes('sign in with Google'), '/ must say how to sign in');
  assert.ok(!home.includes('create an account'), '/ still says "create an account"');
  const terms = readPage('/terms/');
  assert.ok(terms.includes('Settings › Account › Delete Account…'), '/terms/ must name the in-app deletion path');
  assert.ok(!terms.includes('You register with'), '/terms/ still describes registering');
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `(cd W/web && npm run build)`
Expected: FAIL: the new test (no "sign in with Google"). The privacy test fails too only when Step 1 had to change its needle.

- [ ] **Step 3: Change the copy**, exactly:
  - `ui.ts` `step1`: `'Install ShellX on your computer and sign in with Google.'`
  - `terms.md` §2 third bullet: `- You sign in with your own Google account or, in the iPhone app, with your own Apple ID.`
  - `terms.md` §10 first sentence: `You may stop using the Service at any time and delete your account in the phone app (**Settings › Account › Delete Account…**) or as described in the [Privacy Policy](/privacy/#delete-account).`
  - `privacy.md`: replace every `Settings → Account → Delete account` or `Settings → Delete account` with `Settings › Account › Delete Account…`; nothing else. When there is none (plan 1A already wrote the contracts §12 wording), leave `privacy.md` untouched, `updated:` included.
  - Each page changed here: `updated:` = `date +%F`.

- [ ] **Step 4: Run it to see it pass**

Run: `(cd W/web && npm run build)` and `grep -c 'Settings → Account → Delete account' W/web/src/pages/privacy.md`
Expected: Astro builds, node:test ends `# fail 0`; grep prints `0`.

- [ ] **Step 5: Commit**

```bash
git -C W add web/src/i18n/ui.ts web/src/pages/terms.md web/src/pages/privacy.md web/tests/site.test.mjs
git -C W commit -m "docs(web): sign in with Google, and the phone apps' deletion path"
```

Localization audit for the hand-off: three English pages changed; the site is English-only by design (`web/tests/site.test.mjs`).

---

### Task 9: Land L1 on `develop`

Runs after Phase 1 is verified (so Task 8's copy is not published before 1.8.0) and before Task 10.

- [ ] **Step 1: Catch up.** `git -C W merge --no-edit develop` (merge, never rebase). Conflicts: keep both sides, rerun Step 2. If the ledger still says `google_web_client_id: pending (3D)` and plan 3D's `google_oauth.xml` now exists, do Task 1 Step 10 now.
- [ ] **Step 2: Verify in `W`:** `node --test deploy/tests/*.test.mjs` (`# fail 0`), `(cd web && npm ci && npm run build)` (`# fail 0`), `python3 scripts/verify-local.py` (last line starts `PASSED:`), and the secret scan `git -C W diff develop...HEAD | grep -c -E 'GOCSPX-[A-Za-z0-9_-]{20,}|BEGIN (EC )?PRIVATE KEY'` → `0` (real secrets have 28 characters after `GOCSPX-`; the test's fake has 12).
- [ ] **Step 3: Review.** A fresh review subagent per `skills/cmux-review/SKILL.md` ("Default pre-merge review"): this plan's Goal, Tasks 1, 2, 8, base `git merge-base develop HEAD`, head SHA, the diff; correctness first (the guards cannot be bypassed, no value reaches argv or output, copy matches contracts §12). Fix confirmed findings test-first in new commits; rerun Step 2.
- [ ] **Step 4: Gate** — ask for a merge directive with the review summary (the iPhone client IDs are app configuration).
- [ ] **Step 5: Merge**

```bash
git -C /Users/lehuuphu/Documents/myProjects/shellx branch --show-current                 # develop; otherwise stop
git -C /Users/lehuuphu/Documents/myProjects/shellx status --short --untracked-files=no   # only the user's own modified files; stop if relay/, web/, deploy/, scripts/, windows/, shellx-ios/ or shellx-android/ appear
git -C /Users/lehuuphu/Documents/myProjects/shellx pull --ff-only origin develop
git -C /Users/lehuuphu/Documents/myProjects/shellx merge --no-ff feat/shellx-signin-1d-rollout -m "Merge branch 'feat/shellx-signin-1d-rollout' into develop (L1)"
(cd /Users/lehuuphu/Documents/myProjects/shellx && node --test deploy/tests/*.test.mjs)
git -C /Users/lehuuphu/Documents/myProjects/shellx push origin develop
```

  Expected: the merge commit, `# fail 0`, the push accepted. Record the merge SHA (Status "L1 landing" → `done`) and commit the ledger in `W`.

---

## Phase 2 — Desktop 1.8.0 and the iPhone build

### Task 10: Desktop 1.8.0 release candidates

**Interfaces:**
- Consumes: L1 on `develop` (guards), `B1` and `C1`, `~/.shellx-release/google-desktop-oauth.env`.
- Produces in `M`: `build-shellx/Build/Products/Release/ShellX.app` (1.8.0), `dist/1.8.0/ShellX-1.8.0.dmg`, `dist/1.8.0/ShellX-Setup-1.8.0.exe`, `dist/1.8.0/{appcast.xml,latest-macos.json,latest-windows.json,SHA256SUMS}`.

- [ ] **Step 1: Gate G2a.** Show `git -C M log --first-parent --merges --oneline df63759fbb..develop` (what 1.8.0 contains since 1.7.0) and ask: bump to 1.8.0, build Mac + Windows, build the iPhone release (Task 11), commit and push the bumps to `develop`. Wait for a yes.
- [ ] **Step 1b: Google branding assets present** (contracts §11; plan 1B Task 9, plan 1C Task 9 Steps 6–8). From `M`: `ls Assets.xcassets/GoogleG.imageset windows/shellx-app/assets/google shellx-ios/ShellX/Assets.xcassets/GoogleG.imageset` lists the official "G" files in all three places. If any is missing, the desktop release scripts (`make-dmg.sh`, `build-windows-cross.sh`) and `release/mobile/ios.sh --check-app` refuse to build: hand the user the pending USER download step of 1B / 1C (`! … bash scripts/shellx/fetch-google-branding.sh` and 1C's asset step), land those commits, then continue. Never take a Google logo from anywhere else.
- [ ] **Step 2: Local checks**, all run from `M` after `git -C M pull --ff-only origin develop`: `(cd shellx-core && cargo test --workspace --locked)`, `swift test --package-path Packages/Shared/ShellXBrand`, `(cd windows && cargo test --locked -p shellx-model)`, `python3 scripts/verify-local.py`. Expected: every suite passes; `PASSED:`.
- [ ] **Step 3: Mac bump** (from `M`). Read the current values: `grep -o -E 'MARKETING_VERSION = [0-9.]+;|CURRENT_PROJECT_VERSION = [0-9]+;' cmux.xcodeproj/project.pbxproj | sort | uniq -c` → two lines of 12 each (today `1.7.0` and `123`; with other values, put them in place of `1\.7\.0` and `123` below and use their build number + 1). Then `sed -i '' -e 's/MARKETING_VERSION = 1\.7\.0;/MARKETING_VERSION = 1.8.0;/' -e 's/CURRENT_PROJECT_VERSION = 123;/CURRENT_PROJECT_VERSION = 124;/' cmux.xcodeproj/project.pbxproj`. Rerun the grep: `12 CURRENT_PROJECT_VERSION = 124;` and `12 MARKETING_VERSION = 1.8.0;`. Commit `cmux.xcodeproj/project.pbxproj`: `build(shellx): ShellX 1.8.0 (build 124)`.
- [ ] **Step 4: Windows bump.** `windows/Cargo.toml` `[workspace.package] version = "1.8.0"`; in `windows/Cargo.lock` only the `version` line right under `name = "shellx-app"`, `name = "shellx-model"` and `name = "shellx-remote"` (other crates share version numbers: never replace blindly); `windows/README.md` (`Version 1.8.0` and both `ShellX-Setup-1.8.0`); `windows/shellx-app/resources/shellx.manifest` `version="1.8.0.0"`; `windows/shellx-model/src/lib.rs` `assert_eq!(VERSION, "1.8.0");`. Run `(cd windows && cargo test --locked -p shellx-model version_matches_workspace)` → `test result: ok. 1 passed`. Commit those five files: `build(shellx): ShellX for Windows 1.8.0`. Then `git -C M push origin develop`.
- [ ] **Step 5: Mac build** (about 15 min):

```bash
(cd /Users/lehuuphu/Documents/myProjects/shellx && set -a && . ~/.shellx-release/google-desktop-oauth.env && set +a && CMUX_GHOSTTYKIT_NO_PREBUILT=1 SHELLX_UNIVERSAL=1 scripts/shellx/sign-and-notarize.sh --build)
```

  Expected: stderr shows `==> Google Desktop OAuth client: present`; the last stdout line is the path of `build-shellx/Build/Products/Release/ShellX.app`.
- [ ] **Step 6: Sign, notarize, dmg** (about 20 min): `scripts/shellx/sign-and-notarize.sh build-shellx/Build/Products/Release/ShellX.app` → `==> signed, notarized and stapled: …`; then `scripts/shellx/release/make-dmg.sh build-shellx/Build/Products/Release/ShellX.app 1.8.0 dist/1.8.0` → prints `dist/1.8.0/ShellX-1.8.0.dmg`.
- [ ] **Step 7: Windows build** (shared connection open):

```bash
(cd /Users/lehuuphu/Documents/myProjects/shellx && set -a && . ~/.shellx-release/google-desktop-oauth.env && set +a && scripts/shellx/release/build-windows-cross.sh dist/1.8.0)
```

  Expected: a line `== Google Desktop OAuth client: present` and the last line `Built dist/1.8.0/ShellX-Setup-1.8.0.exe (unsigned)` (the script prints the absolute path). If the Windows build cannot succeed, stop and ask the user whether 1.8.0 ships Mac-only (deploy/README.md "Mac-only release": `SHELLX_NO_WINDOWS=1` for make-feeds, `WIN_URL`, `desktopVersion` and `MIN_WINDOWS` stay).
- [ ] **Step 8: Feeds:** `scripts/shellx/release/make-feeds.sh build-shellx/Build/Products/Release/ShellX.app 1.8.0 dist/1.8.0 build-shellx/SourcePackages/artifacts/sparkle/Sparkle/bin`. A macOS keychain prompt for account `shellx` may appear: **USER** clicks **Always Allow** (not Allow); an exit 1 with an empty log means the prompt timed out (memory `shellx-release-pipeline`): rerun. Expected: `appcast.xml`, `latest-macos.json`, `latest-windows.json`, `SHA256SUMS` in `dist/1.8.0/`.
- [ ] **Step 9: Secret scan:** `git -C M log -p df63759fbb..HEAD | grep -c -E 'GOCSPX-[A-Za-z0-9_-]{20,}'` → `0`. Record the build number, both sha256 values (`shasum -a 256 dist/1.8.0/ShellX-1.8.0.dmg dist/1.8.0/ShellX-Setup-1.8.0.exe`) and the commit under "Releases"; commit the ledger.

---

### Task 11: iPhone release candidate and TestFlight

**Interfaces:**
- Consumes: L1 on `develop` (real `SHELLX_GOOGLE_IOS_CLIENT`), `C1`, Task 3 (capability).
- Produces: build `<v> (<b>)` on TestFlight, recorded under "Releases".

- [ ] **Step 1: USER — the store state.** App Store Connect → Apps → ShellX: (a) has version 1.0.0 ever been released on the App Store? (b) TestFlight → Builds: the highest build number. (Today the App Store has no ShellX: `curl -s 'https://itunes.apple.com/lookup?bundleId=com.shellx.prod&country=vn'` → `"resultCount":0`.)
- [ ] **Step 2: Version.** In `M/shellx-ios/Config/Version.xcconfig`: `MARKETING_VERSION` stays `1.0.0` if 1.0.0 was never released, else `1.0.1` (release/mobile/README.md "Same app"). `CURRENT_PROJECT_VERSION` = 1 + the highest of: the file's value, the user's TestFlight number, and every `<n>` in `build/release/ios/ShellX-*-<n>.uploaded`. Commit that file: `build(shellx-ios): ShellX iOS <v> (<b>)`; push `develop`.
- [ ] **Step 3: Build.** `pgrep -fl xcodebuild` shows no other ShellX build; `(cd M && release/mobile/ios.sh)`. Expected last line: `Not uploaded. After testing it, upload this build with: release/mobile/ios.sh --upload`, and no `ios.sh:` refusal. A `!!!` block listing a new or renewed `com.shellx.prod` profile is expected once (the Sign in with Apple capability): record it; any other `!!!` change → stop and ask the user.
- [ ] **Step 4: USER — upload.** `! cd /Users/lehuuphu/Documents/myProjects/shellx && release/mobile/ios.sh --upload`. Expected: `==> uploaded ShellX <v> (<b>). App Store Connect > ShellX > TestFlight lists it after processing (about 5-30 minutes).` Record it.

---

### Task 12: Live checks on real devices (S1 §2.1)

Every check is the user's, on their own devices; the executor gives the steps, runs the log checks and records results. Order matters: P2a before P2b.

**Interfaces:**
- Consumes: `dist/1.8.0/ShellX-1.8.0.dmg`, the TestFlight build, ShellX Dev built from `M` (L1 holds the real IDs), the Mac's QR.
- Produces: rows P2a–P2e in "Live checks"; criterion 2 stays `pending (3H)`.

ShellX Dev goes on the iPhone with `(cd M && shellx-ios/scripts/dev.sh device)`; it needs the iPhone connected and unlocked, and its device id in `~/.config/shellx/iphone-device-id` (or ask the user for it, not secret, and pass `--device-id <id>`).

- [ ] **Step 1: USER — P2a, Mac 1.8.0 switch (§6.3b, first half of criterion 1).** Quit ShellX yourself, open `dist/1.8.0/ShellX-1.8.0.dmg` (Finder, in `M`), drag ShellX to Applications → Replace, open it. Expected: the sheet "Switch to Google sign-in" ("ShellX now signs in with Google. Switching keeps this computer, your phones and your share links.") → **Continue with Google** (plan 1B's sheet; **Switch…** is the same action's button in Settings › Account) → the browser opens Google → choose your Google account → back in ShellX: "Signed in as <email>" → Done. Settings › Account shows that email, "Sign-in methods" lists "Google account", **Delete Account…** opens `https://shellx.pro/privacy#delete-account` at the deletion section. The paired iPhone app still opens this Mac's workspaces. If the candidate fails, reinstall 1.7.0 from `https://download.shellx.pro/desktop/1.7.0/ShellX-1.7.0.dmg`.
- [ ] **Step 2: USER — P2b, iPhone switch (second half of criterion 1).** Use the iPhone app that today holds a password session paired with this Mac, and install the new build of that same app over it: ShellX → the TestFlight build of Task 11; ShellX Dev → `(cd M && shellx-ios/scripts/dev.sh device)`. Expected: the banner "Switch to Google sign-in" → **Switch** → the same Google account (time it: Google's sheet closes → home) → the same Macs and workspaces, no QR scan, under 2 s.
- [ ] **Step 3: USER — P2c, ShellX on TestFlight (the review build).** If this app is not the one Step 2 switched: on its sign-in screen tap **Try without an account** → a sample Mac with workspaces, agent sessions and waiting requests under a "Demo · Exit" banner → **Exit** returns to sign-in; then Continue with Google → your account; if it was never paired, pair it with the Mac's QR (right-click "This Mac" → Pair Phone…). In both cases open a workspace of your Mac. If Step 2 switched this app, do the **Try without an account** check at the start of Step 4 on ShellX Dev's sign-in screen instead (the demo ships in every build).
- [ ] **Step 4: USER — P2d, Apple with a hidden email (criterion 3).** On ShellX Dev (install it if needed; if it is signed in, Settings › Account › Sign out, which removes ShellX Dev's own pairing; this step pairs it again). If this Apple ID ever signed in to ShellX: iPhone Settings → your name → Sign-In & Security → Sign in with Apple → ShellX → Stop Using Apple ID. Then **Sign in with Apple** → **Hide My Email** → "Connect to Your Mac" → on the Mac: right-click "This Mac" → **Pair Phone…** → scan the QR with ShellX Dev → the Mac's request shows "Allowing lets this Apple ID sign in to your ShellX account and manage it, including deleting the account." → **Allow** → ShellX Dev shows the home with that Mac. Then ShellX Dev → Settings › Account → Sign out → Sign in with Apple again (time it: Apple's sheet closes → next screen) → it lands in the account without "Connect to Your Mac". On the Mac: Settings › Account → Sign-in methods shows "Apple ID", "Hidden email", "Added from <iPhone name>" → **Remove** → ShellX Dev shows the sign-in screen at its next request.
- [ ] **Step 5: Apple log check** (Review Focus 5):

```bash
VPS-RO docker compose logs relay 2>/dev/null | grep -o -E "apple_link_required|apple_link_requested|apple_link_redeemed|identity_removed|apple_token_exchange_failed|apple_revoke_failed|apple_revoke_skipped" | sort | uniq -c
```

  Expected: `apple_link_required`, `apple_link_requested`, `apple_link_redeemed`, `identity_removed` present; none of `apple_token_exchange_failed`, `apple_revoke_failed`, `apple_revoke_skipped`. Otherwise recheck Task 3 (grouping, key's primary App ID) and Task 5 (Key ID), then repeat Step 4.
- [ ] **Step 6: USER — P2e, Windows (if you have a Windows PC).** Install `dist/1.8.0/ShellX-Setup-1.8.0.exe` → Continue with Google → the same account → Settings shows the email; the Macs are listed. No PC: record `not run (no Windows PC)`; the user accepts it explicitly at G2b.
- [ ] **Step 7: Record** P2a–P2e, the times (criterion 5: the three of P1b, P2b's and P2d's, each under 2 s), and criterion 2 as `pending (3H: Android first, then desktop)`. Any failure: no publishing; fix forward (failing test first, review, merge directive), rebuild the candidates (an unpublished 1.8.0 may be rebuilt; the iPhone needs a new build number), repeat the failed checks. Commit the ledger.

---

### Task 13: Publish desktop 1.8.0, deploy the pointers, submit the iPhone build

**Interfaces:**
- Consumes: Tasks 10–12.
- Produces: `https://download.shellx.pro/desktop/1.8.0/…` live; `deploy/relay.env` and `web/src/site.config.json` at 1.8.0 on `main`; the iPhone build submitted.

- [ ] **Step 1: Gate G2b.** Summarize Task 12's results and ask: publish desktop 1.8.0, deploy the pointers and Task 8's copy, submit the iPhone build. Wait for a yes.
- [ ] **Step 2: Publish** (shared connection open): `(cd M && scripts/shellx/release/publish-to-vps.sh --dry-run 1.8.0 dist/1.8.0)`, then without `--dry-run`. Expected: `https://download.shellx.pro/desktop/appcast.xml serves 1.8.0` and the file table. If the session refuses the command, give the user `! cd /Users/lehuuphu/Documents/myProjects/shellx && scripts/shellx/release/publish-to-vps.sh 1.8.0 dist/1.8.0`.
- [ ] **Step 3: Check the files:** `curl -sI https://download.shellx.pro/desktop/1.8.0/ShellX-1.8.0.dmg | head -1` and the same for `ShellX-Setup-1.8.0.exe` → `HTTP/2 200`; `curl -s https://download.shellx.pro/desktop/latest-macos.json` and `latest-windows.json` contain `1.8.0`.
- [ ] **Step 4: Pointer commit** in `M`: `deploy/relay.env` `LATEST_AGENT_VERSION=1.8.0`, `MAC_URL=https://download.shellx.pro/desktop/1.8.0/ShellX-1.8.0.dmg`, `WIN_URL=https://download.shellx.pro/desktop/1.8.0/ShellX-Setup-1.8.0.exe`; `web/src/site.config.json` `"desktopVersion": "1.8.0"`. Run `node --test deploy/tests/compose.test.mjs` and `(cd web && npm ci && npm run build)` from `M` → `# fail 0` twice. Commit both files: `release(shellx): point the website and relay at desktop 1.8.0`; push `develop`.
- [ ] **Step 5: USER — `main` and deploy:** Task 6 Steps 6–8 again (push, `main-is-develop`, `has-1A`, dry run, deploy).
- [ ] **Step 6: Check:** `curl -s -H 'X-ShellX-Platform: macos' https://relay.shellx.pro/v1/version` and with `windows` → `"version":"1.8.0"`; `curl -s https://shellx.pro/ | grep -c 'sign in with Google'` ≥ 1; `curl -s https://shellx.pro/ | grep -c 'desktop/1.8.0/ShellX-1.8.0.dmg'` ≥ 1; `curl -s https://shellx.pro/terms/ | grep -c -F 'Settings › Account › Delete Account…'` and the same for `/privacy/` → `1` or more; E1 of Task 7 still `201`.
- [ ] **Step 7: USER — App Review.** App Store Connect → ShellX → App Store → iOS App → version `<v>` (create it with **+** if Task 11 chose 1.0.1) → Build: **+** → the Task 11 build → App Review Information: untick **Sign-in required**; Notes: `Without a Mac running ShellX, tap “Try without an account” on the sign-in screen: it opens a sample Mac with workspaces, agent sessions and requests waiting for you. Full use needs a Mac running ShellX (https://shellx.pro). To delete an account: Settings › Account › Delete Account….` → Version Release: **Automatically release this version** → Save → **Add for Review** → **Submit to App Review**. App Privacy stays as it is unless you decide otherwise (release/mobile/README.md "App Privacy").
- [ ] **Step 8: Record** everything; Status "2" → `done` once the review is submitted (the approval is checked in Task 15). Commit the ledger.

Rollback: before Step 2 nothing is public. After it, installers are immutable: fix forward with 1.8.1 (Tasks 10, 12, 13), and do not start Phase 3 until a good 1.8.x is out. The pointers move back only by a new pointer commit and deploy, but Sparkle already offers 1.8.0: ship 1.8.1 rather than going back. App Review rejects: fix, raise the build number, Task 11 Steps 3–4, resubmit.

---

## Phase 3 — Force update

### Task 14: Require desktop 1.8.0

- [ ] **Step 1: Downloadable first** (Review Focus 2): `curl -sI https://download.shellx.pro/desktop/1.8.0/ShellX-1.8.0.dmg | head -1` → `HTTP/2 200` is required for `MIN_MACOS`; `curl -sI https://download.shellx.pro/desktop/1.8.0/ShellX-Setup-1.8.0.exe | head -1` → `HTTP/2 200` is required for `MIN_WINDOWS` (otherwise it stays `1.2.0`, recorded).
- [ ] **Step 2: Gate.** Ask: raise the minimums (which of the two), effects (≤ 1.7.0 desktops show "Update required" and stop remote access until they update). Wait for a yes.
- [ ] **Step 3: Commit** in `M`: `deploy/relay.env` `MIN_MACOS=1.8.0` and (per Step 1) `MIN_WINDOWS=1.8.0`; `node --test deploy/tests/compose.test.mjs` → `# fail 0`; commit `deploy/relay.env`: `release(shellx): require desktop 1.8.0 (MIN_MACOS, MIN_WINDOWS)` (name only `MIN_MACOS` when Step 1 held Windows back); push `develop`.
- [ ] **Step 4: USER — `main` and deploy:** Task 6 Steps 6–8.
- [ ] **Step 5: Check:** `curl -s -H 'X-ShellX-Platform: macos' https://relay.shellx.pro/v1/version` → `"min_agent":"1.8.0"`; with `windows` → `"min_agent":"1.8.0"` (or `1.2.0` when Step 1 held it back). Optional USER check: a 1.7.0 desktop shows "Update required" at its next check (on launch or within 6 h). Status "3" → `done`; commit the ledger.

Rollback: set the minimum(s) back to `1.2.0`, commit, push, Task 6 Steps 6–8.

---

## Phase 4 — Cut-over and leftovers

### Task 15: Cut-over readiness and the date

- [ ] **Step 1: Readiness numbers** (read-only, no personal data):

```bash
ssh -S ~/.ssh/cm-shellx-vps -o BatchMode=yes higio@42.115.41.70 'cd phu/shellx && docker compose exec -T backup sh -s' <<'EOF'
sqlite3 -readonly /data/relay.db <<'SQL'
SELECT 'password_accounts', COUNT(*) FROM users WHERE password_hash IS NOT NULL;
SELECT 'password_sessions_used_7d', COUNT(*) FROM tokens WHERE auth_method = 'password' AND last_used_at >= (CAST(strftime('%s','now') AS INTEGER) - 7 * 86400) * 1000;
SELECT 'active_password_accounts_without_google_7d', COUNT(*) FROM users u
 WHERE u.password_hash IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM identities i WHERE i.user_id = u.id AND i.provider = 'google')
   AND EXISTS (SELECT 1 FROM devices d JOIN tokens t ON t.device_id = d.id WHERE d.user_id = u.id AND t.last_used_at >= (CAST(strftime('%s','now') AS INTEGER) - 7 * 86400) * 1000);
SELECT 'password_sessions_used_7d_by_app', d.kind, d.platform, COALESCE(d.app_version, 'unknown'), COUNT(*)
  FROM tokens t JOIN devices d ON d.id = t.device_id
 WHERE t.auth_method = 'password' AND t.last_used_at >= (CAST(strftime('%s','now') AS INTEGER) - 7 * 86400) * 1000
 GROUP BY d.kind, d.platform, d.app_version;
SQL
EOF
```

  Expected: one `name|count` line per query (the last may have several rows or none). Record them under "Cut-over".
- [ ] **Step 2: Gate conditions**, each recorded yes/no:
  - (a) Phase 3 live: Task 14 Step 5 still answers `1.8.0`.
  - (b) The iPhone build is on the App Store: `curl -s 'https://itunes.apple.com/lookup?bundleId=com.shellx.prod&country=vn'` → `"resultCount":1` with `"version":"<v of Task 11>"` (for `1.0.0`, the USER also confirms in App Store Connect that build `<b>` is "Ready for Distribution").
  - (c) Windows 1.8.0 published, or the user accepts that Windows ≤ 1.7.0 users lose sign-in.
  - (d) USER: their own Mac, iPhone apps and any Windows PC show Google (or Apple) under Settings › Account.
  - (e) USER: admin.shellx.pro → "Phiên bản đang dùng" → tables Desktop and Mobile: devices below 1.8.0 (desktop) and on the old mobile builds.
- [ ] **Step 3: USER — the date.** Present Steps 1–2 in Vietnamese, including what `active_password_accounts_without_google_7d` means: those accounts can come back after the cut-over only if their email is a Google account (linking by email, S1 §7), otherwise only by switching in-app before the date. The user picks the date (and may announce it on Discord). Record it.

---

### Task 16: The cut-over

- [ ] **Step 1: Gate** on the chosen day: rerun Task 15 Step 1, show the numbers, ask "cut over now?". Wait for a yes.
- [ ] **Step 2: USER — fresh backup** (VPS shell): `docker compose exec -T -e BACKUP_DATE="$(date +%F)-precutover" backup sh /backup/backup-once.sh`. Expected: `backup: wrote /backups/relay-<date>-precutover.db`. (It rotates out with the others after 14 days, as the privacy policy says.)
- [ ] **Step 3: USER — switch password sign-in off** (VPS shell):

```bash
sed -i '/^PASSWORD_LOGIN=/d' .env && { [ -z "$(tail -c1 .env)" ] || echo >> .env; } && echo 'PASSWORD_LOGIN=off' >> .env && docker compose up -d --force-recreate relay
```

- [ ] **Step 4: Check:** `VPS-RO docker compose logs relay 2>/dev/null | grep -c password_login_off` → `1`; `curl -s -X POST https://relay.shellx.pro/v1/auth/login -H 'content-type: application/json' -d '{}' -w '\n%{http_code}\n'` and the same for `/v1/auth/password` → code `password_sign_in_removed`, `410`; `/v1/auth/register` → `registration_closed`, `410`; E1 → `201`.
- [ ] **Step 5: USER — dry run** (VPS shell): `docker compose exec -T relay npm run -s password-cutover`. Expected: `password-cutover: dry run: <N> account(s) with a password, <M> password session(s); run again with --yes to remove them.`
- [ ] **Step 6: USER — the cut-over** (VPS shell): `docker compose exec -T relay npm run -s password-cutover -- --yes`. Expected: `password-cutover: removed <N'> password(s) and <M'> password session(s).` (close to the dry run's numbers).
- [ ] **Step 7: Check:** `VPS-RO docker compose exec -T relay npm run -s password-cutover` → `… dry run: 0 account(s) with a password, 0 password session(s); …`. USER: the Mac 1.8.0, the iPhone apps and ShellX Dev are still signed in and open a workspace.
- [ ] **Step 8: Record** N, M, N', M', times and the user's report; Status "4" → `done`; commit the ledger. Tell the user Task 19 (plan 1C Task 15) may start.

Rollback: before Step 6, `sed -i '/^PASSWORD_LOGIN=/d' .env && docker compose up -d --force-recreate relay` turns passwords back on. After Step 6 there is no undo: passwords and password sessions are gone. Restoring `relay-<date>-precutover.db` (deploy/README.md "Restore a backup") also discards every change made since; only on the user's explicit decision. Otherwise fix forward: people sign in with Google, or Apple on iPhone.

---

### Task 17: Remove the relay's password reset (S1 §6.9)

After Task 16 only. Passwords are gone, so a reset changes nothing (plan 1A Spec note 11).

**Files:**
- Delete: `relay/src/scripts/reset-password.ts`, `relay/src/scripts/reset-cli.ts`, `relay/src/scripts/reset-db.ts`, `relay/test/reset-password.test.ts`
- Create: `relay/test/line-prompter.test.ts`, `relay/test/cutover-leftovers.test.ts`
- Modify: `relay/package.json` (`scripts`), `relay/README.md` (the `## Emergency password reset` section and every other `reset-password` mention), `deploy/README.md` (the "Emergency password reset" bullet of `## Operations`), `relay/src/scripts/line-prompter.ts` (doc comment naming the test file), `relay/test/auth.test.ts` (comment "e.g. the reset-password script in the same volume" → "e.g. an operator script in the same volume"), `relay/dev.env` (line 1: "(`npm run dev`, `npm run reset-password`)" → "(`npm run dev`)")

- [ ] **Step 1: Move the prompter test and write the failing test.** Move `describe("createLinePrompter", …)` with its two tests unchanged from `relay/test/reset-password.test.ts` into `relay/test/line-prompter.test.ts` (imports: `describe, expect, it` from `vitest`, `createLinePrompter` from `../src/scripts/line-prompter.js`), and delete it from the old file. Create `relay/test/cutover-leftovers.test.ts`:

```ts
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { expect, it } from "vitest";

const RELAY_DIR = join(import.meta.dirname, "..");

it("password reset is gone after the cut-over (S1 §6.9): no script, no npm command, no runbook", () => {
  const pkg = JSON.parse(readFileSync(join(RELAY_DIR, "package.json"), "utf8")) as { scripts: Record<string, string> };
  expect(pkg.scripts["reset-password"]).toBeUndefined();
  for (const file of ["reset-password.ts", "reset-cli.ts", "reset-db.ts"]) expect(existsSync(join(RELAY_DIR, "src/scripts", file))).toBe(false);
  for (const doc of ["README.md", "../deploy/README.md"]) expect(readFileSync(join(RELAY_DIR, doc), "utf8")).not.toContain("reset-password");
});
```

- [ ] **Step 2: Run them**

Run: `(cd W/relay && npx vitest run test/line-prompter.test.ts test/cutover-leftovers.test.ts)`
Expected: `line-prompter` passes (2 tests); `cutover-leftovers` FAILS on the `reset-password` script.

- [ ] **Step 3: Remove** the four files, the `"reset-password"` script line, the README section and bullet, and update the two comments and `relay/dev.env`'s first line (Files). Keep `prompter.ts`, `line-prompter.ts` and the `password-cutover` / `mint-smoke-token` scripts.

- [ ] **Step 4: Verify**

Run: `(cd W/relay && npx vitest run test/line-prompter.test.ts test/cutover-leftovers.test.ts && npm test && npm run typecheck && npm run build && ls dist/scripts)` and `git -C W grep -n -e reset-password -e reset-cli -e reset-db -- relay deploy scripts ':!relay/test/cutover-leftovers.test.ts'` (that test names the removed files on purpose)
Expected: `Test Files  2 passed (2)`; the full suite has no failed file; no `error TS`; `dist/scripts` lists no `reset-*`; the grep prints nothing.

- [ ] **Step 5: Commit**

```bash
git -C W add -A relay/src/scripts relay/test/reset-password.test.ts relay/test/line-prompter.test.ts relay/test/cutover-leftovers.test.ts relay/test/auth.test.ts relay/package.json relay/README.md relay/dev.env deploy/README.md
git -C W commit -m "refactor(relay): remove the password reset after the cut-over (S1 §6.9)"
```

---

### Task 18: Website copy after the cut-over

**Files:**
- Modify: `web/src/i18n/ui.ts` (`security3`, `faqA3`)
- Modify: `web/src/pages/terms.md` (`updated:`, §3 bullets 1, 3 and 4)
- Test: `web/tests/site.test.mjs`

- [ ] **Step 1: Write the failing test.** In the test "home carries the full marketing content statically", replace the needle `'argon2id'` with `'SHA-256'`. Add:

```js
test('after the cut-over the home page and the terms describe no password', () => {
  const home = readPage('/');
  for (const gone of ['argon2id', 'password hash', 'Passwords are hashed']) assert.ok(!home.includes(gone), `/ still says "${gone}"`);
  const terms = readPage('/terms/');
  assert.ok(terms.includes('ShellX has no passwords'), '/terms/ must say there are no passwords');
  assert.ok(!terms.includes('your password'), '/terms/ still mentions your password');
});
```

- [ ] **Step 2: Run it to see it fail.** `(cd W/web && npm run build)` → FAIL on `argon2id` and `ShellX has no passwords`.

- [ ] **Step 3: Change the copy**, exactly:
  - `security3`: `'Sign-in goes through Google, or Apple on iPhone, so ShellX stores no password; access tokens are stored only as SHA-256 hashes.'`
  - `faqA3`: replace its first sentence with `Only your email, the Google account or Apple ID you sign in with, device information, pairing records, and the push token of phones that allowed notifications, kept until sign-out.`; the rest of the text stays.
  - `terms.md` §3 bullet 1: `- You are responsible for keeping the Google account or Apple ID you sign in with secure, and for protecting the devices you are signed in on.`
  - §3 bullet 3: `- If you lose your phone: on your Mac, open ShellX, right-click “This Mac”, choose **Pair Phone…** and remove that phone under **Paired phones**, so it can no longer control the Mac. If that phone signed in with an Apple ID, also remove the Apple ID under **Settings › Account** on your computer, which signs out every device that used it.`
  - §3 bullet 4: `- ShellX has no passwords: you sign in with Google, or with Apple on iPhone. If you lose access to that Google account or Apple ID, we cannot restore your access to the ShellX account; you can sign in with another account and ask us to delete the old one as described in the [Privacy Policy](/privacy/#delete-account).`
  - `updated:` = `date +%F`. `privacy.md` is unchanged (Spec note 10).

- [ ] **Step 4: Run it to see it pass.** `(cd W/web && npm run build)` → Astro builds, `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git -C W add web/src/i18n/ui.ts web/src/pages/terms.md web/tests/site.test.mjs
git -C W commit -m "docs(web): no passwords after the cut-over"
```

Localization audit: two English pages; English-only site.

---

### Task 19: iPhone password removal (plan 1C Task 15)

- [ ] **Step 1:** The user confirms in the chat that the cut-over is done (Task 16 Step 8 recorded it).
- [ ] **Step 2:** Run plan 1C Task 15 exactly as written (`docs/superpowers/plans/2026-11-07-shellx-signin-1c-ios.md`), in its own worktree and branch `feat/shellx-signin-1c-ios-cutover` from `develop`, including its review and its landing with the user's merge directive.
- [ ] **Step 3:** Record its merge SHA in the ledger. It ships with the next iPhone build (not part of this plan's releases); add that to "Hand-off".

---

### Task 20: Verify and hand off (landing L2)

- [ ] **Step 1: Catch up and verify in `W`:** `git -C W merge --no-edit develop` (and Task 1 Step 10 if the ledger still says `google_web_client_id: pending (3D)` and the file now exists); then `node --test deploy/tests/*.test.mjs`, `(cd relay && npm ci && npm test && npm run typecheck && npm run build)`, `(cd web && npm ci && npm run build)`, `python3 scripts/verify-local.py`, and the secret scan of Task 9 Step 2. Expected: `# fail 0`, no failed file, no `error TS`, `PASSED:`, `0`.
- [ ] **Step 2: Whole-branch review** as Task 9 Step 3 over `git merge-base develop HEAD..HEAD`, correctness first (Task 17 removes nothing still used; copy is true after the cut-over; the ledger holds no secret). Fix findings test-first; rerun Step 1.
- [ ] **Step 3: Gate** — merge directive; then Task 9 Step 5 with the message `Merge branch 'feat/shellx-signin-1d-rollout' into develop (L2)`.
- [ ] **Step 4: Gate** — "deploy the leftovers?"; then Task 6 Steps 5–8 (`has-1A` included).
- [ ] **Step 5: Check:** `VPS-RO docker compose exec -T relay ls dist/scripts` lists no `reset-*`; `curl -s https://shellx.pro/ | grep -c 'stores no password'` ≥ 1; `curl -s https://shellx.pro/terms/ | grep -c 'ShellX has no passwords'` ≥ 1; Task 16 Step 4's endpoint checks still hold.
- [ ] **Step 6: Close the ledger:** Status "L2" → `done`; "Hand-off to 3D / 3H" lists the Web client ID (Android `serverClientId`), the Android client IDs and SHA-1s or `pending`, the API key restriction state, criterion 2 pending, and the follow-up of Spec note 6. Commit it in `W`, then merge it as Task 9 Step 5 (a docs-only merge; no directive needed beyond Step 3's).
- [ ] **Step 7: Report to the user** (Vietnamese): the phases with dates and SHAs, the live-check results, what waits (3H items, plan 1C Task 15's iPhone release), this plan's Contract additions and Spec notes for the contracts owner. Add one line to the memory note `shellx-release-pipeline`: desktop release builds now run with `set -a; . ~/.shellx-release/google-desktop-oauth.env; set +a` and refuse without it. `cmux notify` if a socket is available.
- [ ] **Step 8: Clean up:** remove `W` with the mechanism that created it (`git -C /Users/lehuuphu/Documents/myProjects/shellx worktree remove .claude/worktrees/signin-1d-rollout` for a git worktree); keep the branch.

Rollback: the leftovers deploy is an ordinary deploy. An unhealthy rollout restores itself; anything else is fixed forward (Task 7's rollback rules, never below `A1`).

---

## Spec notes

1. **Deletion path wording.** Contracts §12, plan 1C (strings, App Review note) and plan 1A Task 15 (privacy page) all use "Settings › Account › Delete Account…". Task 8 checks the privacy page, converts any older arrow wording, and brings the terms page in line.
2. **Apple App IDs.** Plan 1C Task 8 Step 6 enables Sign in with Apple on both App IDs as primary. The relay holds one key (contracts §2: one `APPLE_SIWA_KEY_ID`), and a Sign in with Apple key mints client secrets only for its primary App ID's group, so `com.shellx.dev` sign-ins would get no refresh token and could never be revoked. Task 3 groups `com.shellx.dev` under `com.shellx.prod`; Task 12 Step 5 checks it.
3. **Plan 1C Task 14 Step 4** hands its live checks to this plan: `dev.sh device` builds ShellX Dev (`com.shellx.dev`, its own Keychain), which never sees the App Store 1.0.0 (5) app's password session. Task 12 runs the switch on whichever app holds the paired password session, the Apple link on ShellX Dev, and deletion and timing on the simulator with a throwaway account, so the real iPhone keeps its pairing. Task 7 Step 6 and Task 12 replace 1C's live checks.
4. **S1 §10 "Android × 2"** lists three SHA-1s; a Google Android OAuth client holds one package and one SHA-1, so Task 1 makes three (dev/debug, prod/upload, prod/Play signing).
5. **Build-time client on Windows.** Contracts §10 and plan 1B ask 1D to export the Desktop client "for both desktop release builds", but the Windows release build runs in Docker on the VPS and inherits nothing from the Mac. Task 2 passes it on stdin and makes both builds refuse without it.
6. **Desktop password plumbing stays.** Plan 1B has no post-cut-over task; its "Kept until the cut-over" list (`auth.login`, `ShellXAccount.signIn(email:password:)`, `ShellXRemoteService.signIn(email:password:)` with the DEBUG dev credentials, Windows `AccountEvent::LoginSubmitted`, the unused Mac and Windows strings) is used by dozens of Rust, Swift and Windows test call sites against the fake API (`shellx-core/tests/*.rs`, `Packages/Shared/ShellXBrand/Tests`, `windows/shellx-app/src/smoke.rs`), and by local relays (which keep `PASSWORD_LOGIN=on`). No UI reaches it and production answers 410. Removing it means migrating those tests to the fake Google flow, which is out of this rollout's scope; 1D keeps it, extending contracts §3's "until the cut-over", and lists it as a follow-up in the hand-off.
7. **Two landings.** Contracts §1 has one merge after the final review. 1D spans weeks, and its release guards and sign-in copy must be on `develop` before Phase 2, so it lands twice (Task 9, Task 20), each after its own review and merge directive.
8. **Website publish timing.** `vps-deploy.sh` ships web and relay together from `main`, so 1A's privacy page goes live with Phase 1, before the iPhone build with deletion is on the App Store (plan 1A Spec note 14 wanted later). Accepted: today's page already describes the removed Flutter app's deletion, and no store listing points at the page until 3H.
9. **Terms numbering.** Plan 1A Spec note 13 names terms §2, §3, §8; the in-app deletion sentence is in §10 (Termination). Tasks 8 and 18 edit §2, §3 and §10.
10. **Privacy page after the cut-over** keeps "until password sign-in is switched off" for older accounts (still true, and `site.test.mjs` pins `argon2id` there).
11. **Contracts §7** ("the first desktop release after 1.8.0 that contains 2B"): 1.8.0 is cut from `develop`'s head at G2a; if 2B has landed by then, 1.8.0 is that release. G2a shows the user what 1.8.0 contains.
12. **iPhone version:** `1.0.0 (<b>)` while 1.0.0 was never released on the App Store (true today: the lookup answers `resultCount` 0), else `1.0.1`, per `release/mobile/README.md`.
13. **S1 §2.1 criteria 2 and 5.** Criterion 2 starts on Android, so it waits for 3H; 1D checks its new-account half on the simulator. Criterion 5 (p95 < 2 s) is checked as "every timed sample under 2 s" over the five stopwatch samples of Task 7 Step 6 and Task 12 Steps 2 and 4.
14. **Vietnamese spelling:** plan 1B writes "Xóa tài khoản…" (Mac glossary), plan 1C "Xoá tài khoản…" (iPhone). The website is English-only, so 1D needs neither; a later string pass may align them.
15. **Dogfood builds after 1.8.0:** tagged / DEBUG desktop builds have no compiled Desktop client unless built with the env file loaded; they can also take `SHELLX_GOOGLE_DESKTOP_CLIENT_ID` / `_SECRET` at run time (plan 1B), and production refuses their dev-credential password sign-in after the cut-over.
16. **Register after the cut-over.** S1 §6.9 has `/v1/auth/register` answer `password_sign_in_removed` once `PASSWORD_LOGIN=off`; contracts §2 (and plan 1A Task 12) make it always `410 registration_closed`. Task 16 Step 4 expects the contracts' code.

## Contract additions

For the contracts owner (this plan does not edit the contracts file):

1. **Desktop OAuth client for releases (1D; consumers: every later desktop release, incl. the one with 2B).** File `~/.shellx-release/google-desktop-oauth.env` (mode 600, two lines `SHELLX_GOOGLE_DESKTOP_CLIENT_ID=…`, `SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET=…`), loaded with `set -a; . ~/.shellx-release/google-desktop-oauth.env; set +a` before `scripts/shellx/sign-and-notarize.sh --build` and `scripts/shellx/release/build-windows-cross.sh`; both refuse without it (`scripts/shellx/release/google-desktop-client.sh`: `shellx_require_google_desktop_client`, `shellx_binary_has_google_desktop_client`).
2. **Rollout ledger (1D; consumers 3D, 3H):** `docs/superpowers/ledgers/shellx-signin-rollout.md` holds the OAuth client IDs (the Web client is Android's `serverClientId`), the SHA-1s, the Apple Key ID, and the items left `pending (3H)` (Play App Signing SHA-1 for client 5 and the API key restriction).
3. **Google Cloud project:** every OAuth client of every app lives in project `shellxpro` (the Firebase project), with consent screen "ShellX", External, in production, scopes `openid email profile`.
4. **Apple:** `com.shellx.prod` is the primary App ID for Sign in with Apple; `com.shellx.dev` is grouped with it; one key `ShellX Sign in with Apple` (primary `com.shellx.prod`) lives on the VPS at `/secrets/siwa.p8`.
5. **Android OAuth clients:** three, named `ShellX Android (dev)`, `ShellX Android (upload key)`, `ShellX Android (Play signing)` (Spec note 4).
