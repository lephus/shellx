# Task L1-CI report
Status: DONE_WITH_CONCERNS
Commit: 788412bb76 ci(shellx): opt-in shellx-mac-unit job for app-hosted ShellX suites (branch shellx/l1-ci)
Files: .github/workflows/shellx-mac-unit.yml (new), scripts/shellx/test-app.sh (args after `--` forwarded to xcodebuild via test-unit.sh; old usage unchanged)
Validation: PyYAML safe_load ok; bash -n ok; stubbed test-app.sh prints `test -only-testing:cmuxTests/A -only-testing:cmuxTests/B -x y=1` for `A B -- -x y=1` and `test -only-testing:cmuxTests/A` for `A`. actionlint not installed. No xcodebuild run.
Design: suite resolution step first; all later steps gated on run=='true' (no suites -> notice, exit 0). Resolve packages uses scheme cmux-unit. Test step tees unit.log, fails on TEST FAILED or missing TEST SUCCEEDED. Same action SHAs as shellx-mac.yml.
Concerns:
- Suite name = file basename (per brief); if a file's @Suite/struct name differs, -only-testing will match nothing (xcodebuild then may still print TEST SUCCEEDED with zero tests).
- Steps gated per-step rather than job-split; `if` on job uses head_commit message (push only).
- Workflow untested on GitHub.

## Fix round 1
1. Concurrency group now includes 'run' for dispatch/[unit] runs and github.run_id otherwise, so skipped runs never cancel a live one.
2. Test step, after the success check: requires `Test run with N tests` / `Executed N tests` (N>0) and a suite line (`Suite X started|passed|failed` or `Test Suite 'X'`) per requested suite; the echoed -only-testing arg does not match. Fails with ::error::.
Validation: YAML load ok; extracted step passes bash -n; regex sanity-tested on sample logs (match on suite line, no match on the command-line echo).
Concern: Swift Testing suites with a custom display name print the quoted name, so they would be reported missing; suite names must equal struct names.
