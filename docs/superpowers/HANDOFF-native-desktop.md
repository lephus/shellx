# Handoff: ShellX native desktop (state 2026-10-19 07:11 +07)

Read this first on a new machine or in a new agent session. It replaces the lead agent's local memory, which does not travel. Binding detail lives in:

- Spec: `docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md`
- Ledger (decisions, rulings, spike results, sprint log): `docs/superpowers/ledgers/native-desktop.md` — read "Sprint rulings", "Sprint 2026-10-19" and "Repo move".
- Sprint master plan: `docs/superpowers/plans/2026-10-19-native-desktop-12h-sprint.md` (lanes, contracts K1–K5, gates G0–G3, checkpoints).
- Lane plans: `docs/superpowers/plans/2026-10-18-native-desktop-w1-mac-local.md`, `2026-10-19-native-desktop-w2-server.md`, `-w2-mac-remote.md`, `-w3-release-share.md`, `-w4-windows-mvp.md`.
- Lead's lane rules and lane reports: `docs/superpowers/sprint-state/lead/` (paths in them assume `/Users/lehuuphu/Documents/myProjects/...`; adjust to your checkout).

## What ShellX is now

ShellX is cmux (Manaflow, GPL-3.0) with ShellX changes, on `main` of `lephus/shellx`: the cmux tree with full history at the repo root, plus ShellX's `relay/` (API + relay, Node), `web/` (shellx.pro, Astro), `deploy/` (VPS, Docker + nginx-proxy). The Flutter apps (desktop + mobile 1.0.0) were deleted; they live at tag `flutter-final`. `lephus/shellx-pro` (the earlier mirror of cmux) is frozen: never code there. macOS = cmux app rebranded; Windows = GPUI app on `cmux-tui`; remote = cmux-tui remote protocol through a self-hosted `cmux-relay` ("relay2") with tickets minted by the ShellX API.

## Update 2026-10-19 evening (richard's Mac): lanes merged into `main`

The sprint resumed on another Mac and stopped again on the user's "làm xong, commit và push tất cả lên main; sau đó dừng".

- `main` now holds `shellx/sprint` (L1 identity, L2 look, L3 sidebar, L6 Windows; checkpoint-1 merges, sprint head `577b086832`) and `shellx/l5-remote` (head `0abe36a511`), as `--no-ff` merges `a48fd2c30c` and `8618f29945`. All five lanes passed their final reviews; lane SDD state is under `docs/superpowers/sprint-state/<lane>/`.
- **Not on `main`:** L4 `feat/relay-v2` (merging it deploys API v2 to production, gate G2 still waits on the user).
- **Local checks on the merged `main`:** `scripts/verify-local.py --all` passed 15/15, all `tests/test_shellx_*.py` passed, and `swift test` on ShellXBrand passed 298 tests. Cargo was not run on this Mac.
- **Still owed:**
  - CI for the merged code. `shellx-mac` runs only on `shellx/**` pushes, so push `main` to a `shellx/*` branch to get a run.
  - The checkpoint-1 Release build smoke test (a tagged `cp1` Release build of the pre-L6 sprint succeeded locally on Xcode 26.6, launch not done).
  - The L1 `shellx-mac-unit` run 39233474076.
  - The L5 `shellx-mac` run 39233991465.
  - The K4 adapter `extension ShellXRemoteService: ShellXRemoteServicing {}` and the L3 Important items before flipping `ShellXFeatures.remoteMachines`.
  - Task 14 GUI e2e / checkpoint 2.
  - Ledger "Checkpoint 1" on `shellx/sprint` lists the rest.

## Sprint state at the stop

The 12-hour sprint started 02:50 and was stopped by the user at 07:11. Every lane branch is pushed. Its SDD ledger (progress, task briefs, reports, rulings) is committed on the branch under `docs/superpowers/sprint-state/<lane>/`. Commits titled `wip(shellx): sprint paused …` hold an implementer's **unfinished, unreviewed** code: re-run that task's review loop before relying on them.

| Lane | Branch | Plan / tasks | State |
| --- | --- | --- | --- |
| L0 setup | `shellx/sprint` | master plan L0.1, W1 Task 1 | done; CI `shellx-mac` green (run 39165768325). L1–L3 branched from `c3afe0da80` |
| L1 identity | `shellx/l1-identity` | W1 Tasks 2–5, 5B | Tasks 2, 5B and lane CI complete; Task 3 (coexistence with the Flutter app, same bundle id) and Task 4 (no phone-home to Manaflow, never cut) mid-way on side branches below; Task 5 not started |
| L2 look | `shellx/l2-look` | W1 Tasks 6, 7, 8, 9 (verify), 11, 12 | Tasks 6, 9 complete; Task 7 fix round on a side branch; Task 8 (coolicons import, 445 files in the WIP commit) and Task 12 (Vietnamese, side branch) mid-way; Task 11 not started |
| L3 sidebar | `shellx/l3-sidebar` | W1 Task 10, then W2-mac-remote Part B U1–U4 | Task 10 and U1 complete; U2 request-access sheet mid-way (WIP commit); U3, U4 not started |
| L4 server | `feat/relay-v2` | W2 server, all tasks | **DONE**, reviewed, ready: merge into `main` with `--no-ff` (keeps pinned relay2 source commit `57dd520ccf` reachable). Fallback `feat/relay-v2-subdomain`; W3 A2 Flutter 1.0.1 on `feat/flutter-1.0.1` (based on `flutter-final`) |
| L5 Mac remote | `shellx/l5-remote` | W2-mac-remote Part A Tasks 1–14 | Tasks 1–12 and 6b complete per its ledger (several on side branches below); a Task 7 fix-round re-review was open at the stop; small WIP in the remote-e2e harness. Task 13 waits for checkpoint 1; Task 14 (e2e) open |
| L6 Windows | `shellx/l6-windows` | W4 Windows MVP | Tasks 1–12b and 14 complete; Tasks 13a/13b (remote view of a Mac) and 15 (docs) were mid-way, nothing uncommitted. Windows code builds only on GitHub Windows runners |
| L7 share | — | W3 Part B | not started (stretch) |

**Task side branches not yet merged into their lane branch** (lane controllers ran some tasks in their own worktree/branch and merge them back after review; merge them before resuming the lane):

| Side branch | Lane | Content |
| --- | --- | --- |
| `shellx/l1-t3` | L1 | W1 Task 3 coexistence, 8 commits + WIP commit (83 files, unreviewed) |
| `shellx/l1-t4` | L1 | W1 Task 4 no phone-home, 8 commits + WIP commit (2 files) |
| `shellx/l2-look-t7fix` | L2 | Task 7 fix round, 2 commits |
| `shellx/l2-look-t12` | L2 | Task 12 Vietnamese, WIP commit (20 files) |
| `shellx/l5-swift` | L5 | Task 10 (Swift service), 3 commits, reviewed |
| `shellx/l5-build` | L5 | Tasks 9, 11, 12 (bundle/build, daemon), 11 commits, reviewed |
| `shellx/l5-vpty` | L5 | Task 7 virtual PTY (already merged) |

Spike branches kept in this repo: `shellx/w0-spikes` (GPUI terminal spike, Windows CI), `shellx/w0-bridge` (Mac bridge spike).

## Resume on another machine

1. `git clone git@github.com:lephus/shellx.git && cd shellx && git fetch --all`. Submodules (`ghostty`, `vendor/bonsplit`, `homebrew-cmux`) only when you build the Mac app: `git submodule update --init --recursive`.
2. One worktree per lane: `git worktree add ../shellx-wt-l5 shellx/l5-remote` (same for the others).
3. In each worktree copy the lane state back where the SDD skill expects it: `mkdir -p .superpowers/sdd && cp -R docs/superpowers/sprint-state/<lane>/. .superpowers/sdd/` (the `sprint` and `l1`–`l3` state is the W1 plan workspace `2026-10-18-native-desktop-w1-mac-local`; L5 `2026-10-19-native-desktop-w2-mac-remote`; L6 `2026-10-19-native-desktop-w4-windows-mvp-plans`). L4's state is in `docs/superpowers/sprint-state/lead/l4-server-report.md` (its workspace was closed).
4. Run each lane as a lane controller with `superpowers:subagent-driven-development` on its plan, resuming at the first task without a `Task N: complete` line in `progress.md`; finish any open review loop first.
5. Lead work next: checkpoint 1 = merge L1 → L2 → L3 into `shellx/sprint` (`--no-ff`, L1 first), CI green, local Release build + smoke; then flip `ShellXFeatures.remoteMachines` on `shellx/sprint` only, L5 Task 13, e2e Mac↔Mac (checkpoint 2), W1 Task 13 perf compare against `scripts/shellx/perf/baselines/cmux-122037ee4d.json`.

## Waiting on the user

- **Gate G2 (VPS + production):** steps in `docs/superpowers/sprint-state/lead/l4-server-report.md` "Needs user": FK pre-check on a copy of `relay.db`, merge `feat/relay-v2` `--no-ff` + push `main` (= production deploy of API v2; relay2 stays off), set `CMUX_RELAY_HMAC_SECRET` by hand, nginx-proxy exact-path route or DNS `relay2.shellx.pro`, stage/build relay2 from the source tarball, vhost, `npm run relay2:smoke`.
- **Gate G1:** hands-on checks of the Windows build on the user's Windows 11 PC (Telex/Unikey/EVKey, 150/200 % scaling, Typometer vs Windows Terminal, Narrator).
- Typometer keystroke latency on the Mac baseline build.
- Manaflow's answer to the license email (sent 2026-10-19): until then no public relay image.

## How this user wants work run

- Write to the user in Vietnamese. They say "tiếp tục" / "chạy" to keep going: run lanes in parallel without check-ins, settle ambiguities with recorded rulings, stop only for irreversible or outward-facing steps.
- Never ask for or print secret values; the user sets them by hand (VPS shell or `! ` commands). Ask before deploys and paid resources.
- Pushing new branches of `lephus/shellx` is allowed without asking. Pushing `main` is the user's call when it touches `relay/`, `web/` or `deploy/`: `deploy.yml` deploys production (and a push of more than 1000 commits ignores its path filter). Docs-only `main` pushes deploy nothing.
- When a Vietnamese instruction is ambiguous about which repo or branch, ask (2026-10-19 lost an hour to "không cần fork đâu, cấp nhánh làm mới hết", which meant "stop using the fork").
- UI taste: soft solid colours, no gradient buttons, primary `#60a5fa`, running state = yellow, Vietnamese strings; palette in spec §7.4.

## Gotchas learned the hard way

- Disk is the bottleneck on the dev Mac (460 GB, often < 20 GB free). Keep ≥ 15 GB. `xcrun xctrace` leaves ~5 GB of `instruments*.ktrace` scratch per 30 s recording in `getconf DARWIN_USER_TEMP_DIR` (the perf harness now cleans it); never record traces casually.
- APFS is case-insensitive: cmux's `Packages/` and a stray `packages/` are the same directory. Never `rm -rf packages`.
- The Flutter ShellX at `/Applications/ShellX.app` shares bundle id `pro.shellx.desktop`; the native build exits while it runs (W1 Task 3 handles it). Never touch the user's own cmux (`com.cmuxterm.app`).
- Only one local Xcode build at a time (`~/.shellx-build.lock`); prefer CI (`shellx-mac` on `shellx/**` pushes, ~60 min cold).
- Xcode 26.2 `-O` SIL linker crash and Release builds need `CMUX_WIREGUARD_GO_REQUIRE=0` without Go (ledger "Signing").
- cmux tests that check the removed `web/`, `workers/` and cmux workflows still exist (`tests/test_ci_*`, `test_web_validation`, schema parity tests …); `shellx-mac` doesn't run them; W1 deletes or skips them.
- Signing: Apple team `W4RF3W4VTZ`, Developer ID on the dev Mac's keychain (`scripts/shellx/sign-and-notarize.sh`).
