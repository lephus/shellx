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

## Lane L1 (Mac identity), worktree ~/Documents/myProjects/shellx-wt-l1, branch shellx/l1-identity from c3afe0da80 — Tasks 2, 3, 4, 5, 5B
Controller start 2026-10-19 05:05 +07. Plan file = main checkout copy (same tasks as worktree copy; only shellx-pro→shellx path text differs).

### Pre-flight scan (L1 tasks)
| Pair / task | Produces vs consumes | Finding |
| --- | --- | --- |
| T2 self | pytest tests vs repo runner | repo has no pytest (ledger "Python tests"): unittest scripts run as `python3 tests/x.py` (CI does that) → ruling R1 |
| T2 self | Step 4 local reload.sh build | conflicts with common rules (one local build, prefer CI) → ruling R2 |
| T2 self | "replace every com.cmuxterm.app literal" (200 Swift files, ~460 hits) vs Global "internal identifiers not renamed" | ambiguous → ruling R3 |
| T2 → T3/T4/T5/T5B | tests/shellx_guard.py (read, offenders, png_size, sha256) | consumed by all later guards; L2 Task 6/9 also import it (parallel lane may create the same file) → ruling R4 |
| T2 ↔ T3 | both edit project.pbxproj (bundle ids vs CLI PRODUCT_NAME/UTIs) | sequential, no conflict |
| T3 self | Swift app-host test ShellXPathsTests via test-app.sh | needs cmux-unit compile (~55 min, ~10 GB DerivedData; disk 26 GB free) → ruling R5 |
| T3 self | Review Focus #5 (master): Flutter /Applications/ShellX.app same bundle id → native build silently exits | not in W1 plan text; master plan assigns it to T3 → ruling R6 |
| T3 ↔ T5B | T3 guard `/tmp/cmux` also matches `/tmp/cmuxd-remote-*` (T5B's names); T5B consumes T3's `~/.shellx/bin/shellx` | overlap → ruling R7 |
| T3 ↔ L2 T6 | T3 renames config paths `cmux.json`; L2 rebrand_strings rewrites UI strings incl. `cmux.json` in catalogs | L1 does not bulk-edit xcstrings → ruling R8 |
| T4 ↔ L2 T6 | T4 fixes docs link AboutPanelView.swift:11; L2 T6 rewrites AboutPanelView.swift:10-55 | overlap → ruling R9 |
| T4 ↔ T5 | both edit AppDelegate.swift (1845-1925 vs 1615/11159/15768) and FeatureFlags.swift (T4 523/634; L3 T10 edits :68) | sequential T4→T5; different hunks from L3 |
| T4 ↔ T13 (L0) | ShellXNetworkPolicy.forbiddenHosts in ShellXBrand | agrees |
| T4 self | ShellXNoPhoneHomeTests app-host | → R5 |
| T5 self | ShellXCloudOffTests app-host | → R5 |
| T5 ↔ K4 | DevicesFeature/MobileHost/Presence return ShellXFeatures.remoteMachines (L5/L3 flip it later) | agrees with K4 |
| T5B self | Step 1 install Go | not installed; side effect outside worktree → ruling R10 |
| T5B self | Step 5 SSH manual check needs a host | needs user → listed under Needs user |
| T5B ↔ T2-T5 | daemon/remote, CmuxRemoteSession/CmuxCore remote daemon names, verify_remote_daemon_release.py | disjoint from T2/T4/T5 files → ruling R11 (parallel side worktree) |

Ruling R1: Python guards are stdlib unittest files `tests/test_shellx_*.py` runnable as `python3 tests/test_shellx_x.py` (plan's pytest snippets translated 1:1) and registered in tests/test-execution.toml next to test_shellx_entitlements.py — repo has no pytest; CI loops `python3 tests/test_shellx_*.py` — cost if wrong: none (same assertions).
Ruling R2: app builds are verified by CI shellx-mac (Debug build of scheme cmux) on pushed heads instead of local reload.sh; bundle-id-of-tagged-build check done statically on reload.sh logic — sprint rules — cost if wrong: break found ~60 min later on CI.
Ruling R3: replace com.cmuxterm.* where it names OUR app or reaches an OS-wide namespace another app could share (bundle-id comparisons/derivations, UserDefaults suites, keychain services, distributed notifications, Mach/XPC/launchd labels, pasteboard/UTI types, app group, on-disk paths); leave in-process-only labels (DispatchQueue labels, in-process NotificationCenter names, os_log subsystems) and test fixtures — Global "internal identifiers not renamed" + coexistence goal — cost if wrong: a few more literal renames later.
Ruling R4: tests/shellx_guard.py exactly per the plan signature (read, offenders(pattern, roots, allow), png_size, sha256); if L2 also creates it, L0 keeps one copy at merge — cost if wrong: trivial add/add conflict.
Ruling R5: app-hosted Swift suites (ShellXPathsTests, ShellXNoPhoneHomeTests, ShellXCloudOffTests) are written + wired (scripts/sync-test-wiring), and pure logic is put in ShellXBrand where possible so `swift test` covers it fast; app-host suites run on CI through a new opt-in workflow `.github/workflows/shellx-mac-unit.yml` (workflow_dispatch + push to shellx/** only when the head commit message contains `[unit]`) running scripts/shellx/test-app.sh — local compile would take ~10 GB of the 26 GB free and the build lock for ~1 h — cost if wrong: one more CI file for L0 to own.
Ruling R6: Task 3 owns master Review Focus #5: when another app with our bundle id is already running, the native app shows a modal explaining it (old Flutter ShellX at its path / another ShellX instance) with "Quit it and open ShellX" / "Cancel" instead of silently exiting; decision logic pure in ShellXBrand (swift test), UI wiring in the existing single-instance guard — spec §8.2 keeps the Flutter id — cost if wrong: one alert's wording.
Ruling R7: Task 3 does not rename remote-daemon names (cmuxd-remote, ~/.cmux/daemon, /tmp/cmuxd-remote-*); its guard allowlists those hits with reason "Task 5B"; after T5B merges, the allowlist entries are removed (follow-up step) — cost if wrong: a temporary allowlist.
Ruling R8: L1 edits Localizable catalogs only for keys it adds; UI copy saying "cmux" is L2 Task 6 — cost if wrong: none.
Ruling R9: Task 4 changes only the URL literal(s) in AboutPanelView.swift (one-line edits) so L2's Task 6 rewrite merges cleanly — cost if wrong: small conflict at checkpoint 1.
Ruling R10: Go 1.22.x installed from go.dev to ~/.local/go1.22 (no shell profile change; scripts take GO from PATH/env) — plan Step 1; dev tool only — cost if wrong: ~250 MB in ~/.local.
Ruling R11: Task 5B runs in parallel in a side worktree ~/Documents/myProjects/shellx-wt-l1-5b on local branch shellx/l1-5b (never pushed) and is merged --no-ff into shellx/l1-identity after its review — files are disjoint from T2/T4/T5; SDD's no-parallel rule exists for file conflicts — cost if wrong: one merge conflict to resolve in CLI/cmux.swift.
Task 2: BASE c3afe0da80; implementer dispatched (opus) 05:10
Task 5B: BASE c3afe0da80 on side branch shellx/l1-5b (worktree ~/Documents/myProjects/shellx-wt-l1-5b); implementer dispatched (opus) 05:10
Task 5B: implementer DONE_WITH_CONCERNS b65b978f9a (go test, swift test 4 pkgs, guards pass); review dispatched (sonnet)
Task L1-CI (controller-added, ruling R5): BASE c3afe0da80 side branch shellx/l1-ci worktree ~/Documents/myProjects/shellx-wt-l1-ci; implementer dispatched (sonnet)
Task 5B: review Needs fixes (1 Important: Go helper ~/.cmuxterm shared state on remote host); minors deferred: Go user-facing 'cmux' strings; dead upstream release tooling names cmuxd-remote; source-regex Release-gate test brittle; shellx_guard import fallback duplicates helpers (drop after Task 2 merge)
Task 5B: fix round 1 dispatched (resume implementer)
Task L1-CI: implementer DONE_WITH_CONCERNS 788412bb76 (yaml ok; concern: suite name = file basename)
Task L1-CI: review Needs fixes (2 Important: concurrency group cancels unit runs on non-[unit] pushes; zero-test run passes); minor (deferred): validate suites input charset; display grep filter misses Swift Testing lines
Task L1-CI: fix round 1 dispatched (resume)
Task 5B: fix round 1 implementer DONE f7027788a3; scoped re-review dispatched
Task 5B: fix round 1/5 (1 addressed, 0 open; commits b65b978..f702778)
Task 5B: complete (commits c3afe0d..f702778 on shellx/l1-5b, review clean) — merge into shellx/l1-identity pending; carry to Task 3: RemoteInteractiveShellBootstrapBuilder relay/bin paths, SessionRemoteWorkspaceSnapshot+Restore.swift:397, fish config.fish:469, local ~/.cmuxterm list in task-5B-report.md
Task 5B: needs user: Step 5 manual SSH check on a tagged Debug build
Task L1-CI: fix round 1 implementer DONE_WITH_CONCERNS c429adabfc (suite names must equal struct names); re-review dispatched
Task L1-CI: fix round 1/5 (2 addressed, 0 open; commits 788412b..c429ada); minor (deferred): suite-line check false-negative if a suite has a custom display name
Task L1-CI: complete (commits c3afe0d..c429ada, review clean)
Task 2: implementer DONE_WITH_CONCERNS 6ca675ee31 (identity 14, guard 6, verify-local 15/15, 14 pkg suites); concerns: PRODUCT_NAME ShellX changes executable name (PRODUCT_MODULE_NAME pinned cmux/cmux_DEV), Embed System Extensions phase removed, app-host fixtures unrun
Merged shellx/l1-ci and shellx/l1-5b into shellx/l1-identity (clean); post-merge guard failure test_shellx_remote_daemon (allow-entry format vs Task 2 helper) → 5B implementer fixing
Task 2: review dispatched (opus)
Pushed shellx/l1-identity 89129d34fa → shellx-mac run 39175982776 (cold); shellx-mac-unit 39175982936 skipped (no [unit]).
Disk 12 GB free at 06:18 (other lanes + 5.3 GB SwiftPM .build dirs from Task 2's package tests) → removed merged side worktrees (l1-ci, l1-5b), go build cache, all .build dirs in shellx-wt-l1 → 19 GB. lane-context now requires deleting .build after swift test.
Ruling R7 (amended): 5B merged before Task 3 starts, so Task 3's guard needs no 5B allowlist; Task 3 also moves RemoteInteractiveShellBootstrapBuilder + SessionRemoteWorkspaceSnapshot+Restore.swift:397 remote paths $HOME/.cmux/{relay,bin} → $HOME/.shellx/{relay,bin} with bin/shellx (5B report concern 1) — cost if wrong: none.
Ruling R12: local ~/.cmuxterm/ (shims, tmux-compat store, hook stores …) → ~/.shellx/ (same dir 5B uses on the remote for the same files, mirroring upstream where local+remote shared ~/.cmuxterm); if a subpath would collide with a ~/.cmux-derived subpath under ~/.shellx, implementer reports it — coexistence ("state" not shared with cmux) — cost if wrong: a dir rename later.
Ruling R13: Task 3 runs in side worktree ~/Documents/myProjects/shellx-wt-l1-t3 (branch shellx/l1-t3 from 89129d34fa) so Task 2 fix rounds can proceed in the main worktree in parallel; merged back --no-ff after review — cost if wrong: merge conflicts in pbxproj.
Task 3: BASE 89129d34fa (shellx/l1-t3); implementer dispatched (opus) 06:22
Ruling R14: Task 4 (then Task 5 on top) runs in side worktree ~/Documents/myProjects/shellx-wt-l1-t4 (branch shellx/l1-t4 from 89129d34fa) in parallel with Task 3 — 4h to checkpoint 1, files mostly disjoint (AppDelegate hunks 1845-1925/15768 vs 18660; pbxproj package refs vs CLI target) — cost if wrong: merge conflicts resolved at merge time.
Task 4: BASE 89129d34fa (shellx/l1-t4); implementer dispatched (opus) 06:25
Task 2: review Needs fixes (1 Critical: AppBundleIconPersistencePolicy imports ShellXBrand but is compiled by CmuxDockTilePlugin which doesn't link it → app build breaks)
Task 2: minor (deferred): start-cmux-profiling half-migrated (process discovery still cmux names; fixture models impossible bundle)
Task 2: minor (deferred): identity Swift-literal guard allowlist is line-regex, not file-scoped
Task 2: minor (deferred, W3 note): UpdateController writes SUEnableAutomaticChecks=false to user defaults in the no-key case, so pre-W3 installs keep auto-checks off after the EdDSA key ships unless W3 bumps the migration key
Task 2: minor (deferred): some app-host fixtures still use 'cmux DEV.app/Contents/MacOS/cmux DEV' paths (cosmetic)
Task 2: fix round 1 dispatched (resume implementer, main worktree)
CI shellx-mac 39175982776 FAILED: CmuxDockTilePlugin link error (confirms Task 2 Critical); pushed 1be6d1250d (fix) for a new run
Task 2: fix round 1 implementer DONE 1be6d1250d; scoped re-review dispatched
Task 2: fix round 1/5 (1 addressed, 0 open; commits 89129d3..1be6d12)
Task 2: complete (commits c3afe0d..1be6d12, review clean; CI build confirmation pending run 39177226153)
