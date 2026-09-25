# SDD ledger — plan: docs/superpowers/plans/2026-09-25-shellx-v1-06-web-ci.md

Worktree: /Users/lehuuphu/Documents/myProjects/shellx/.worktrees/web-ci (branch feat/shellx-v1-web-ci, from feat/shellx-v1 @ fe345d3)
Spec: docs/superpowers/specs/2026-09-25-shellx-v1-design.md ; Overview: docs/superpowers/plans/2026-09-25-shellx-v1-00-overview.md

## Pre-flight scan

Evidence: plan author built the site and all scripts in a scratch dir from the plan text and ran them (site checks 16 pass/1 skip; release tests 24/24 on macOS; shellcheck + actionlint clean). Inno Setup compile only verifiable on Windows (Task 7 CI `installer` job).

| Tasks | Shared file / interface | Producer → consumer | Finding |
|---|---|---|---|
| 1 → 2 | web/src/layouts/Base.astro, src/i18n/ui.ts, tests/site.test.mjs | 1 creates, 2 adds legal pages + tests | OK — additive |
| 3 → 6 | release/scripts/version.mjs, resolve-version.mjs | 3 produces, 6 workflow calls | OK |
| 4 → 6 | release/macos/*.sh | 4 produces, 6 calls | OK |
| 5 → 6,7 | release/windows/shellx.iss, build-installer.ps1 | 5 produces, 6 release + 7 CI installer job call | OK |
| 7 | .github/workflows/ci.yml references jobs for plans 01–05 (paths not present on this branch yet) | expected to pass only after merge of all plans | Ruling below |
| each 1–7 | self-consistency | verified by author scratch run | OK |

Rulings:
- Ruling: CI jobs for relay/dart/e2e/desktop/mobile cannot pass on this branch alone (their code lands from other plans); Task 7 verification here = actionlint clean + web/release/installer jobs logically correct; full CI green is checked after merging all plans into feat/shellx-v1 — cost if wrong: CI fixes discovered at integration time.
- Ruling: legal-page choices (operator named only "ShellX", Vietnamese law, minimum age 16, logs ≤30 days, deletion ≤30 days) kept as drafted and surfaced to the user for legal review — cost if wrong: text edits before launch.

Model plan: implementers haiku (full content in plan); reviewers sonnet; final review opus.

## Progress
Task 1: implemented by ad04e71b6df67f2b2 (haiku), commit f964de9; review dispatched (sonnet)
Task 1: ⚠️ build execution — resolved: implementer report has RED/GREEN evidence (7 pass/1 skip); ⚠️ Pages /privacy redirect — platform behavior, covered by Task 2 README curl check.
Task 1: minor (deferred): English copy uses straight apostrophe instead of brief's curly ’ (web/src/i18n/ui.ts:32,35)
Task 1: minor (deferred): rel="noopener" inert without target=_blank (web/src/components/Downloads.astro:22)
Task 1: complete (commits fe345d3..f964de9, review clean)
Task 2: implementer ad2d62d07f11cc0da (haiku) dispatched, base f964de9
Task 2: implemented by ad2d62d07f11cc0da, commits 9d5d46e bc244ec; review dispatched (sonnet)
Ruling: installer/uninstaller use `taskkill /F /T /IM ShellX.exe` (kill whole tree) instead of `/F /IM` — plan 04 found killing only the agent leaves shells/child processes running; plan text patched in commit 6ef4f3f before Task 5 — cost if wrong: none (tree kill is strictly safer).
Ruling: privacy policy must say Windows keys live in DPAPI-encrypted storage (flutter_secure_storage 10.x on Windows), not Credential Manager — plan text patched (6ef4f3f); web/src/pages/privacy.md:49 and en/privacy.md:49 get fixed in Task 2's fix round — cost if wrong: wording only.
Task 2: review spec ✅ quality Approved; controller-confirmed gap (DPAPI wording) → fix round 1/5 dispatched to ad2d62d07f11cc0da (FIX_BASE 6ef4f3f)
Task 2: fix round 1/5 (1 addressed, 0 open — DPAPI wording; commits 6ef4f3f..2b5f369)
Task 2: complete (commits f964de9..2b5f369, review clean)
Task 3: implementer a518d122a8d8a3af7 (haiku) dispatched, base 2b5f369
Task 3: implemented commit 802bb09; review dispatched (sonnet)
Task 3: ⚠️ workflow wiring — resolved: belongs to Task 6.
Task 3: minor (deferred): missing PUBSPEC_PATH surfaces raw ENOENT (plan-mandated)
Task 3: minor (deferred): no test for empty INPUT_DRY_RUN default-to-dry-run (plan-mandated)
Task 3: complete (commits 2b5f369..802bb09, review clean)
Task 4: implementer afb1a89a62de0c9b8 (haiku) dispatched, base 802bb09
Task 4: implemented commit 96740ad; review dispatched (sonnet)
Task 4: ⚠️ real Apple signing/notarization + GHA env semantics — resolved: cannot run here; exercised by Task 6 dry-run workflow and first real release.
Task 4: minor (deferred): import-certificate.sh removes decoded .p12 only on success path (plan-mandated; RUNNER_TEMP ephemeral)
Task 4: minor (deferred): temp keychain deletion deferred to Task 6 workflow — verify there
Task 4: complete (commits 802bb09..96740ad, review clean)
Task 5: implementer a44c012d3447e5358 (haiku) dispatched, base 96740ad
Task 5: implemented commit cccd7b2; review dispatched (sonnet)
Task 5: ⚠️ real ISCC compile + live install/uninstall + plan-04 build output path + signing — resolved: Windows CI installer job (Task 7) and release workflow (Task 6); build output path ShellX.exe per plan 04.
Task 5: minor (deferred): build-installer.ps1 doesn't validate -Version format
Task 5: minor (deferred): no AppMutex guard for concurrent installer runs
Task 5: complete (commits 96740ad..cccd7b2, review clean)
Task 6: implementer a236b898a3c43ff50 (sonnet) dispatched (incl. keychain cleanup step if missing), base cccd7b2
Task 6: implemented commits 7bed4a7 5806273 (keychain cleanup already present); review dispatched (sonnet)
Task 6: ⚠️ azure/artifact-signing-action input names, CDN cache-key on query strings, cross-plan paths — resolved: first real/dry run; resolve-version.mjs dry_run semantics verified in Task 3 review.
Task 6: minor (deferred): prepare job lacks timeout-minutes
Task 6: minor (deferred): Cloudflare secrets at publish job-level env instead of upload step only
Task 6: minor (deferred): no in-workflow defense-in-depth that non-dry runs are tag-triggered (relies on resolve-version.mjs)
Task 6: complete (commits cccd7b2..5806273, review clean)
Task 7: implementer a3c52f5409c34ad4c (haiku) dispatched, base 5806273
Task 7: implemented commit ae2a9ea; review dispatched (sonnet)
Task 7: ⚠️ dependent jobs green only after plans 01–05 merge; runner image contents; branch-protection setting — resolved: integration CI run after merge; branch protection is a user/admin action.
Task 7: minor (deferred): e2e job has no explicit relay teardown
Task 7: minor (deferred): changes job checks out before paths-filter (plan-mandated)
Task 7: complete (commits 5806273..ae2a9ea, review clean)
Final review: dispatched abe180c3cd0e44482 (opus) over fe345d3..ae2a9ea
Final review: With fixes — 4 Important (privacy: agent-after-deletion wording; privacy: uninstall data claims + missing [UninstallDelete]; Windows installer lacks VC++ runtime DLLs; release secrets hardening: SHA-pin third-party actions + GitHub Environment `release`) + minors. All 13 deferred minors triaged "can wait" (keychain deletion resolved).
Ruling: fix all 4 Important now plus cheap minors (pubspec.lock filter, PR-only cancel, pin /T in test, README required-check + first-launch order, D1 Time Travel note) in ONE fix wave — cost if wrong: small doc/workflow churn.
Ruling: Workers invocation-log IP capture concern belongs to the relay plan — carried to relay (plan 01) as a ruling to verify/disable invocation logs.
Final fix wave: dispatched aa3e2fb19d02268e6 (sonnet), FIX_BASE ae2a9ea
Final fix wave: commits b43856c 0758653 47b28e5 50efb92; scoped re-review dispatched (sonnet)
Final fix re-review: items 1–9 ADDRESSED; SHAs verified against GitHub API; NEW Critical: `environment: release` + README's tag-only deployment rule blocks the documented workflow_dispatch dry run from main.
Ruling (breaker, no second fix wave): allow tag `desktop-v*` AND branch `main` in the `release` Environment (README + corrected inline comment; YAML keys unchanged) — main is PR-protected, dry-run steps never use secrets, publish additionally requires a desktop-v tag; chose this over a conditional/empty `environment:` expression whose GitHub semantics are unverified — cost if wrong: release secrets readable by workflows running on main.
Ruling applied by a1bd3429a3ada7fde (haiku), controller verifies the small diff.
