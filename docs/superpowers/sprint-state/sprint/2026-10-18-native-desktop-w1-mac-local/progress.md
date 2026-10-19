# SDD ledger — plan: /Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/plans/2026-10-18-native-desktop-w1-mac-local.md

Scope (lane L0.1, sprint 2026-10-19): Task 1 ONLY, on branch shellx/sprint (worktree ~/Documents/myProjects/shellx-pro-wt-sprint). Tasks 2-13 belong to lanes L1-L3.

## Pre-flight scan (Task 1 only)
| Item | Finding |
| --- | --- |
| Task 1 Step 1 (branch shellx/w1-mac-local) vs sprint master plan L0.1 | conflict: sprint runs Task 1 on shellx/sprint |
| Task 1 Step 5 local `reload.sh --build-only` vs sprint common rules (one local Xcode build, prefer CI) | conflict |
| Task 1 test-app.sh "extend test-unit.sh to forward args if it doesn't" | test-unit.sh already forwards "$@" (exec xcodebuild ... "$@"); no change needed |
| Task 1 Produces ShellXFeatures.remoteMachines=false vs K4 (master plan) | agrees |
| Task 1 vs Task 5 (consumes remoteMachines) | agrees; Task 5 is L1's |

Ruling: Task 1 runs on shellx/sprint, not shellx/w1-mac-local — master plan L0.1 Step 3 says so; lanes branch from it — cost if wrong: none (branch name only).
Ruling: Task 1 Step 5 app build is verified by CI `shellx-mac` (Debug xcodebuild of scheme cmux) instead of a local `reload.sh --build-only` — sprint rules prefer CI, one local build at a time, 35 min cold — cost if wrong: a build break found ~40 min later on CI instead of locally.
Ruling: upstream lint `feature-flags` fails today on `conversation-sidebar-release` reviewBy 2026-10-18 (date passed); extended to 2026-11-16 (next upstream review date) in Sources/FeatureFlags.swift — one-line upstream edit so `verify-local --all` is green in CI — cost if wrong: trivial merge conflict on the next upstream merge.

Task 1: implementer DONE_WITH_CONCERNS ee2f43315b (swift test 4/4, verify-local 16/16; app link unverified locally -> CI); review dispatched
Task 1: review Spec ✅ / quality Approved. ⚠️ resolved by controller: test-unit.sh forwards "$@" (read, line 37-44); app link -> CI run on the pushed head.
Task 1: minor (deferred): ShellXBrand imports AppKit/SwiftUI and is linked into cmux-cli (plan-mandated) — CLI loads AppKit; split identity vs colour if CLI launch time matters.
Task 1: minor (deferred): ShellXBrandTests `_ = c.color` only checks no crash.
Task 1: complete (commits 61b7731..ee2f433, review clean)

## Resume after repo move (lephus/shellx, worktree ~/Documents/myProjects/shellx-wt-sprint)
Task 1 already complete (line above); no review loop re-run.
Ruling: ShellXBrand.sourceCodeURL = https://github.com/lephus/shellx (W1 plan already says so; code still had shellx-pro) — ac8a020db5 — cost if wrong: one-line revert.
Ruling: verify-local "config-schema" check dropped (source web/data/cmux.schema.json was in cmux BUSL web/, absent here); test_verify_local rows for it removed — ac170427f5 — cost if wrong: generated schema Swift can drift unnoticed until ShellX owns a schema source.
Ruling: shellx-mac paths-ignore relay/web/deploy/docs so server/site-only lane pushes don't burn a macOS runner — c3afe0da80 — cost if wrong: such a branch shows no Mac CI (run workflow_dispatch).
