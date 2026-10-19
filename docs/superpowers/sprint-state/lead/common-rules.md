# ShellX 12h sprint — rules every lane agent follows (L0 lead, T+0 = 2026-10-19 ~02:50 +07, resumed ~04:10 after the repo move)

**Repo move (binding):** ShellX now IS cmux: everything (cmux tree at the root, `relay/`, `web/`, `deploy/`, `docs/`) is ONE repo, `lephus/shellx`, local `/Users/lehuuphu/Documents/myProjects/shellx`. Wherever a plan says "fork" or `lephus/shellx-pro`, read this repo. `lephus/shellx-pro` and `~/Documents/myProjects/shellx-pro*` are frozen: never commit or push there. Spike branches `shellx/w0-spikes`, `shellx/w0-bridge` exist locally in this repo.

Master plan (read §Global Constraints, §Review Focus, §Contracts K1–K5, your lane's Clock row, §Checkpoints):
`/Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/plans/2026-10-19-native-desktop-12h-sprint.md`
Spec: `/Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md`
Ledger (read-only for lanes; L0 writes it): `/Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/ledgers/native-desktop.md` — section "Sprint rulings" (D1–D3) is binding.

Repo: `/Users/lehuuphu/Documents/myProjects/shellx` = GitHub `lephus/shellx` (public). Submodules (`ghostty`, `vendor/bonsplit`, `homebrew-cmux`) are not checked out in new worktrees; if you need one, `git submodule update --init <path> --reference ~/Documents/myProjects/shellx-pro/<path>` (saves disk/network).

## How to run your lane
- Execute your lane plan with superpowers:subagent-driven-development: you are the lane controller; dispatch a fresh implementer per task + task reviewer, fix loop, final review. Keep the SDD ledger in the plan's workspace (`scripts/sdd-workspace`), inside YOUR worktree.
- Work only in your own worktree/branch. Never commit to `main`. Never touch another lane's worktree.
- Rulings, not stalls: decide ambiguities yourself (spec > plan), record `Ruling: … — why — cost if wrong` in your SDD ledger and in your final report. Contract (K1–K5) changes are NOT yours: if one is truly needed, stub around it, continue, and put it in the report as "K-change request".
- Never wait on the user. Steps that need the user (Windows PC checks, VPS secrets, deploy, Typometer, keychain prompts) → prepare everything, skip, list them under "Needs user" in the report.

## Pushing (user allowed new branches, 2026-10-19)
- You MAY push your own lane branch to `origin` (`phule9225.github.com:lephus/shellx.git`, SSH) as often as CI needs. Never push `main` (a `main` push of `relay/`, `web/`, `deploy/` deploys production), never force-push a branch you did not create, never push `shellx/sprint` unless you are L0.
- No container images or other artifacts published anywhere (Manaflow license answer pending).
- `gh run list/view/watch -R lephus/shellx` is fine for CI.

## Machine limits
- Disk: 37 GB free at T+0. Keep ≥ 15 GB free. Before any large build check `df -h /`. Never record xctrace traces. Delete your own build outputs you no longer need; never delete anything you did not create.
- Only ONE local Xcode build at a time on this Mac: take the lock with `shlock -f ~/.shellx-build.lock -p $$` (loop with `sleep 30` until it succeeds), `rm -f ~/.shellx-build.lock` after. Prefer CI for app builds; locally run package-level tests (`swift test --package-path …`, `cargo test -p …`, `npm test`, `python3 tests/test_shellx_*.py`).
- A Flutter ShellX is installed at `/Applications/ShellX.app` with the same bundle id `pro.shellx.desktop`; never kill or modify it. Never touch the user's own cmux (`com.cmuxterm.app`).

## Security / product rules that bite
- No Manaflow servers, no third-party services, no telemetry; no BUSL code (fork `web/`, `workers/*`, `services/iroh-relay-minter/`, `cmux-tui/relays/cloudflare-do/`); GPL-compatible deps; rustls only.
- Relay sees only ciphertext; on-site approval; invitation PSK never reaches the ShellX server in clear.
- Never ask for or print secret values. Palette spec §7.4, no gradients, primary #60a5fa, running = yellow. UI strings Vietnamese.

## Report (your final message, ≤ 40 lines; full detail in a file)
Write the full report to `/Users/lehuuphu/Documents/myProjects/shellx/.superpowers/sprint/<lane>-report.md` (overwrite on each report), and return only: branch + head sha, tasks done/cut, test + CI status (run ids), "ready <sha>" if mergeable, Rulings, K-change requests, Needs user.
