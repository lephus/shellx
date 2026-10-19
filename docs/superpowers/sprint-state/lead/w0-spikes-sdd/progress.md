# SDD ledger — plan: docs/superpowers/plans/2026-10-18-native-desktop-w0-spikes.md

Spec: docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md (binding).
Repos: fork = ~/Documents/myProjects/shellx-pro (created by Task 1); shellx = ~/Documents/myProjects/shellx (ledger docs/superpowers/ledgers/native-desktop.md, spec).

## Pre-flight scan

| Pair / task | Produces → consumes | Finding |
|---|---|---|
| T1 → T2..T8 | clone, Zig 0.16.0, built tagged app, project ledger file | ok |
| T1 ↔ T8 | project ledger `docs/superpowers/ledgers/native-desktop.md` created by T1, appended by every task, summarized by T8 | ok |
| T2 ↔ T3 | both commit on fork "main" per plan text | conflict with SDD rule "no implementation on main without consent" → Ruling R1 |
| T2 (self) | test uses `python3 -m pytest`; pytest not installed on this Mac | → Ruling R2 |
| T2 (self) | Step 6 needs keychain profile `shellx-notary` created by the user | user-gated; asked user at start |
| T3 → W1 T13 | `perf_mac.py` incl. `hitches`, `compare` | ok (W1 consumes later) |
| T3 (self) | Typometer needs the user (GUI + permissions); Java present, Typometer not installed | user-gated; `--keystroke-ms` optional (null skipped by compare) |
| T4 → T5 | running relay topology + ticket notes | ok, sequential |
| T5 (self) | 3-day time-box prototype; design judgment | dispatch on most capable model |
| T6 ↔ T7 | same workflow file `.github/workflows/shellx-windows-spike.yml` (T6 creates, T7 extends) | ok, sequential |
| T6 (self) | push to lephus/shellx-pro needs the user's OK | stop-and-ask at that step |
| T7 (self) | manual checks need a physical Windows PC | user-gated; asked user at start |
| T8 (self) | email draft only, user sends | ok |

## Rulings

- Ruling R1: Tasks 2–3 commit on fork branch `shellx/w0-base` (from `main` @ d0b2cd7e), not on `main`; Task 8 merges it into the fork's `main` locally — SDD forbids implementation on main without consent, and the user's standing rule allows local merges of finished plan branches (never push) — cost if wrong: one extra local merge commit.
- Ruling R2: Python guard tests run with pytest from a venv `~/.venvs/shellx-pro` (`python3 -m venv` + `pip install pytest`) unless Task 1 finds the fork already standardizes another runner for `tests/*.py`, in which case follow the fork's convention — pytest is not installed system-wide — cost if wrong: test command lines in later briefs change.
- Ruling R3: spike-only work (Tasks 4–7) lives on fork branch `shellx/w0-spikes` branched from `shellx/w0-base`; never merged — plan text — cost: none.
- Ruling R5 (resolves R2): the fork standardizes Python tests as stdlib `unittest` scripts (`#!/usr/bin/env python3`, `unittest.TestCase`), run as `python3 tests/<file>.py`, each registered in `tests/test-execution.toml` (static checks → lane `linux-guard`; new tests may not be `legacy`); the fork's pre-commit hook validates that registry. No pytest/venv. Plan steps saying `python3 -m pytest` are read as this — follow the house convention over plan text — cost if wrong: a test file converted back to pytest style.
- Ruling R6: the Task 1 unit baseline is partial (215 started / 214 passed / 0 failed, stopped at 60 min after a ~55 min cold compile); Task 8 reruns `./scripts/test-unit.sh test` on the warm cache with a 120 min budget and records the full baseline — the cold compile, not the tests, ate the budget — cost if wrong: an upstream-failing test is mistaken for a regression in W1, caught at W1 T13.
- Ruling R7: `reload.sh --build-only` deletes its artifact; any task that must launch the app builds with `./scripts/reload.sh --tag <tag>` (or `--release` where the plan says) without `--build-only` — Task 1 evidence — cost: none.
- Ruling R8: before launching any ShellX-id build that still carries cmux code (W0), run `defaults write pro.shellx.desktop sendAnonymousTelemetry -bool false` and `defaults write pro.shellx.desktop SUEnableAutomaticChecks -bool false` so the launch neither reports to Sentry/PostHog nor offers the upstream cmux update from manaflow's appcast — the no-phone-home work lands only in W1 T4 — cost if wrong: one launch's worth of anonymous telemetry.
- Ruling R4: project-ledger and spec commits go on the shellx repo's current branch `main` (docs only, local, never pushed) — matches how the approved spec/plans were committed — cost if wrong: docs commits to move to a branch.

## Progress
Task 1: dispatched (implementer sonnet; BASE fork=none yet, shellx=c98c3ba2)
Task 1: complete — shellx a23fac61 (ledger docs/superpowers/ledgers/native-desktop.md); fork untouched at d0b2cd7e; review Approved, 0 Critical/0 Important. Parked Minor: ledger line 64 says verify-local "1/1 affected check" but log says "1/2 selected checks ran (swift-syntax 0 files)"; line 66 "stopped by me" → "stopped at the 60 min budget" — Task 2 implementer fixes both wording nits while appending its Signing section.
User-gate: keychain profile shellx-notary created by user and verified (notarytool history OK) — Task 2 Step 6 unblocked
User-gate: user HAS a physical Windows 11 PC for Task 7 manual checks ("có") — schedule with user when Task 7 reaches Step 3.
User-gate: user APPROVED pushing branch `shellx/w0-spikes` to lephus/shellx-pro for Windows CI ("ok") — covers Task 6 and Task 7 pushes to that branch only; no other branch, no main.
Task 2: dispatched (implementer sonnet; BASE fork=d0b2cd7e on new branch shellx/w0-base, shellx=a23fac61)
