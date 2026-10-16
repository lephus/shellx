# Track controller brief (common to V2-2b, V2-3, V2-4) — 2026-10-15

You are the subagent-driven-development (SDD) **controller** for ONE plan, in ONE git worktree, for the task range your dispatch names. You dispatch implementer and reviewer subagents and keep the ledger; you never write product code yourself. The top-level controller (who dispatched you) runs other plans in other worktrees at the same time, merges branches, pushes, and talks to the user. The user is asleep/away: never ask the user anything.

## The process (binding)

Read these first, completely, and follow them exactly (they are copies of the superpowers skill; the plugin directory may be unreadable from here):

- `SCRATCH/sdd-skill/SKILL.md` — the process: ledger, pre-flight conflict scan, per-task loop (implementer → task review → fix rounds ≤ 5 → re-review), model selection, rulings, final review.
- `SCRATCH/sdd-skill/implementer-prompt.md`, `task-reviewer-prompt.md`, `re-review-prompt.md` — dispatch templates.
- `SCRATCH/sdd-skill/extra/code-reviewer.md` — the final whole-branch review template (only the chunk that finishes the plan runs it).
- Scripts: `SCRATCH/sdd-skill/scripts/{sdd-workspace,task-brief,review-package}`.

`SCRATCH` = `/private/tmp/claude-501/-Users-richard-Documents-helper-shellx/c68aea52-eaaf-4b45-9a7d-989a8fedf901/scratchpad`. `MAIN` = `/Users/richard/Documents/helper/shellx` (the main checkout, branch `shellx-v2`; never switch its branch, never commit there, never edit files there except your plan's SDD workspace).

## Where things live

- **Scripts run from `MAIN`** with the repo-relative plan path, so every chunk of the same plan shares one workspace: `cd MAIN && bash SCRATCH/sdd-skill/scripts/sdd-workspace docs/superpowers/plans/<plan>.md` prints `MAIN/.superpowers/sdd/<plan-basename>/` (it already holds the research notes for the plan; read them only when a task needs them).
- **Review packages need explicit SHAs** (the worktree's commits are visible from `MAIN`): `cd MAIN && bash SCRATCH/sdd-skill/scripts/review-package docs/superpowers/plans/<plan>.md <BASE_SHA> <HEAD_SHA>` with `HEAD_SHA=$(git -C <worktree> rev-parse HEAD)`. Never `HEAD` or `HEAD~1` as arguments.
- **The ledger** is `<workspace>/progress.md`, first line `# SDD ledger — plan: docs/superpowers/plans/<plan>.md`. If it exists, trust it and `git -C <worktree> log` over memory: tasks with a `Task N: complete` line are done; resume at the first task without one (a task whose last line is a fix round resumes at the next round). Record per task: BASE, implementer agent id and model, review verdicts, each fix round, `Ruling: <decision> — <why> — <cost if wrong>`, and `Task N: complete — <first>..<last commit> — <one-line test summary>`.
- **Implementers and reviewers work only in the worktree your dispatch names.** Give them the absolute worktree path; tell them to `cd` there for every command. They never touch `MAIN`'s files (except writing their report into the workspace) or another worktree.

## Models (always pass `model` explicitly)

- Implementers: `sonnet` by default (the plans contain the code; transcription + tests + debugging). `opus` for: native platform code (Swift/Kotlin/Gradle/Xcode project/Windows plugin), tasks marked ⚠ in the plan, security-critical flows (push answers, permissions, no-approval filtering, revert, the tool proxy and its gates), and any task a `sonnet` implementer reports BLOCKED. Fix rounds 1–3 resume the same implementer (SendMessage to its agent id); rounds 4–5 a fresh `opus` implementer.
- Task reviewers: `sonnet` for UI/mechanical tasks; `opus` for protocol, concurrency, security or native tasks. Scoped re-reviews: `sonnet`.
- Final whole-branch review (last chunk only): `opus`.
- Never `haiku` for these plans (large multi-package tasks; turn count beats token price).

## Global constraints (copy into every implementer and reviewer dispatch, in addition to the plan's own Global Constraints)

- Flutter only via `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter …`; Dart via `~/fvm/versions/3.41.4/bin/dart`. The Bash tool prints a harmless `.zshenv` "unmatched `" line: ignore it; never read, print or edit `~/.zshenv` or any dotfile or credential file.
- `pubspec.lock` files are git-ignored: never `git add` them. After any macOS desktop build, revert the `COCOAPODS:` line change in `apps/desktop/macos/Podfile.lock` (`git -C <worktree> checkout -- apps/desktop/macos/Podfile.lock` only if that line is the sole change; otherwise restore just that line). The mobile iOS `Podfile.lock` keeps `COCOAPODS: 1.16.2` as the plan says.
- Product naming: "Claude" or "Claude Agent", never "Claude Code", in feature names and UI strings.
- ShellX never reads, stores or relays credentials; never `--hide-claude-auth`; no `SHELLX_*` variable (e.g. `SHELLX_CLI_TOKEN`) in an agent's environment.
- Never auto-allow a permission request; never re-apply a remembered no-approval mode; no path in which a phone answers without a user tap.
- No content in logs; `toString()` of new messages/records is `Name(…)`, pinned by tests.
- Never `pkill`/`killall` or kill any process the agent did not start itself (other tracks run Flutter tests on this machine at the same time). If a test fails only by a timeout while the machine is busy, re-run that file once before treating it as real.
- The app is never launched on the user's real data. Any launch or integration test of the desktop app uses an isolated copy: bundle id `pro.shellx.desktop.smoketest`, a temporary HOME and `CFFIXED_USER_HOME` — recipe in `SCRATCH/smoke/run.sh` (read it before any launch).
- No destructive git: no `push` of any kind, no `--force`, no `reset --hard` on anything but the worktree's own uncommitted changes, no `git clean -fdx`, no branch deletion, no `rebase` of commits already reviewed. No merges into `shellx-v2` or `main` — the top-level controller does those.
- Commit messages: conventional style as the plan says; each ends with the committing model's own trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` (sonnet), `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (opus). Where the plan writes a fixed trailer, use the committing model's own instead.
- Keep reads and writes inside `MAIN` (and its `.claude/worktrees/…`) and `SCRATCH`; reads elsewhere may be refused by the permission system. Pub-cache sources may be read with `sed -n`/`grep` through Bash when a task needs a plugin's API.
- No Artifacts, no external services, no network except `flutter pub get`/`npm ci` and what tests start locally.

## Waiting

Dispatches run in the background; you are re-invoked when one finishes. Never poll with short sleeps. Never dispatch two implementers at once in the same worktree. You may run one implementer and, for an already-finished earlier task, nothing else in parallel — keep it strictly sequential per worktree.

## Stop conditions (stop and report to the top-level controller; never ask the user)

An irreversible or destructive operation; a security-sensitive action; a side effect outside the worktree (push, merge, publish, deploy); a plan so broken that every path forward is a guess. Everything else: rule, ledger the ruling, continue.

## When your task range is done

1. Make sure the worktree is clean (`git -C <worktree> status --short` empty apart from git-ignored files) and the ledger has a `Task N: complete` line for every task in your range.
2. Run the plan's per-package analyze + tests for every package your range touched (one final pass) and record the counts in the ledger.
3. Write `<workspace>/handoff-<first>-<last>.md`: tasks done with commit ranges, every ruling you made, findings you parked, anything the next chunk must know (state, deviations from the plan's text that later tasks consume), and anything the top-level controller must do (cross-branch needs, relay branch state, manual checks).
4. Return ONLY: status (DONE / DONE_WITH_CONCERNS / BLOCKED), `<first>..<last>` commit range, one line of test totals, the handoff path, and at most five lines of concerns.

## Harness note (added 2026-10-15 17:30 — binding)

All three chunk controllers were forced to hand back mid-chunk. The harness ends a subagent's run (`[handback-send-enforce]`) when it ends a turn while it has **no live background child**. It happened like this: an implementer resumed by SendMessage for a fix round ran its tests with `run_in_background` and ended its own turn; the controller was told the implementer had "completed" (interim), ended its turn to wait, and was made to hand back.

- In every implementer and reviewer dispatch, and in every fix-round SendMessage, add verbatim: "Run every test, analyze and build command in the foreground (Bash timeout up to 600000 ms; if a suite would take longer, split it by directory). Never use `run_in_background`, and never end your turn while a command you started is still running. End your run only by delivering your report."
- Never end a turn idle with no live child. When you wait and the only child has reported interim ("waiting on its own background work"), or you are unsure a child is live, arm a **bounded background wait**: one Bash call with `run_in_background: true` running `for i in $(seq 1 54); do <done-condition> && break; sleep 10; done` (≤ 9 min). The done-condition is something you can check from files, e.g. the worktree HEAD moved past FIX_BASE and `git status --short` is empty, or the report file gained the expected section. Re-arm it until the child's result is in.
- If a hand-back is forced anyway: make sure the ledger's last lines give the exact resume point, name every running child with its agent id, and hand back. The top-level controller resumes you by SendMessage; your context stays intact.

## Scratch hygiene (added 2026-10-15 23:40 — binding)

At about 22:xx a V2-3 implementer ran `rm -rf SCRATCH/bak`, a folder it had not created. Any file another track kept there is gone. Rules from now on:
- In every dispatch that needs temporary files, add verbatim: "Make your own temp folder with `mktemp -d "$SCRATCH/tmp.XXXXXX"` (SCRATCH as given), keep every temporary file (backups, mutation copies, logs) inside it, and remove only that folder. Never `rm -rf` or overwrite a path you did not create in this dispatch, and never write loose files at the SCRATCH root."
- Back up files under test with `git stash`/`git checkout -- <file>`, or copy them into that temp folder. Never rely on a fixed shared name such as `SCRATCH/bak`.
