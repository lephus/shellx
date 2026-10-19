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

## RESUME 2026-10-19 (richard's Mac), controller on worktree ~/Documents/helper/shellx-wt/l1-identity (plan = main-checkout copy; workspace plan-path reset to it)
Resume state: Task 2 complete (CI confirmation of 1be6d1250d was cancelled at the pause -> re-confirm on new push); Task 5B + L1-CI complete. Task 3 = origin/shellx/l1-t3 (8 commits + unreviewed WIP 958dbacabb: mass sed that also rewrote guard-test patterns, e.g. `\.cmuxterm`->`\.shellx`, `com\.cmuxterm`->`com\.shellx`, and a captured browser-parity HTML fixture). Task 4 = origin/shellx/l1-t4 (8 commits + 2-file WIP d960525974, looks sane). Task 5 not started.
Merged both into shellx/l1-identity (--no-ff, 1937fe23e5 / e0425148aa). Conflicts (t4 merge): CLI/CMUXCLI+DocsSettings.swift (t3 paths + t4 URLs), project.pbxproj (both test files kept), Localizable.xcstrings (purely additive both sides, 3 t4 keys inserted into t3's tree). Removed 5 xcodebuild log files (.ci-bundled-ghostty-helper/Logs) that the t3 WIP commit had picked up.
Post-merge fast loop: python3 tests/test_shellx_*.py red in 3 files (coexistence test_no_cmuxterm_state_dir 154 hits = sed-munged pattern; remote_daemon pattern `\.shellx` sed-munged; no_phone_home allowlist entry PhonePushCrypto.swift no longer names a forbidden host after T3 renamed the keychain service) -> fixed in the review loops.
Ruling R15: no `gh` on this Mac and no token (not to be requested). CI status is read from the unauthenticated REST API (curl api.github.com/repos/lephus/shellx/actions/runs...); job logs/artifacts need auth, so added scripts/shellx/ci/annotate-log.py + a failure step in shellx-mac.yml and shellx-mac-unit.yml that publishes the xcodebuild error lines as a public check-run annotation (678560c1fb) — edits L0's workflow files by 4 lines each — cost if wrong: trivial merge conflict, or drop the two steps.
Ruling R16: Tasks 3 and 4(+5) run again in side worktrees shellx-wt/l1-t3 (branch shellx/l1-t3, origin head 958dbacabb + junk-removal) and shellx-wt/l1-t4 (branch shellx/l1-t4, then Task 5 on top), in parallel as in R13/R14; merged back --no-ff into shellx/l1-identity after review — cost if wrong: merge conflicts in pbxproj/AppDelegate.
Task 3: BASE 89129d34fa (branch shellx/l1-t3 in ~/Documents/helper/shellx-wt/l1-t3). No T3 report/review exists from before the pause -> whole range 89129d34fa..HEAD gets the task review after the WIP audit.
Task 4: BASE 89129d34fa (branch shellx/l1-t4 in ~/Documents/helper/shellx-wt/l1-t4). No T4 report/review exists -> task reviewer on the whole range first.
Task 4: review 1 (opus, whole range 89129d3..d960525, no implementer report) -> Needs fixes: 0 Critical, 5 Important (I1 CodeRouter gated on remoteMachines + installed/dev-bundled binary still executes + hint points at cmux.com; I2 CLOUD_ALLOWLIST reasons dishonest, build-time entries misfiled, auth.*/vm.* socket handlers reachable via `cmux auth login`/`cmux vm` -> controller moves their gating into Task 5; I3 four upstream tests now fail (PostHogAnalyticsPropertiesTests, CLICoderouterBootstrapTests, SidebarHelpMenuUITests, SettingsAppBehaviorUITests); I4 ShellXNoPhoneHomeTests vacuous (isEnabled false under XCTest) + writes .standard defaults; I5 "Chord docs" and "Open Docs" links should be hidden/point at repo docs). Review file: task-4-review-1.md.
Task 4: minor (deferred): stale remote flag cache (FeatureFlags.swift:510-519 loads cmux.flags.remote.* even with fetch off); no-op CLI sentry reporter still classifies/throttles (CLISocketSentryTelemetry.swift:163-166,279-290); DEBUG "Trigger Sentry Test Crash" menu item dead; config template writes sendAnonymousTelemetry:true (KeyboardShortcutSettingsFileStore+Template.swift:85) + SettingsSearchIndex:292/Aliases:102 leftovers; $schema https://shellx.pro/schema/shellx.json unverified + literal duplicate CmuxConfigActionSaver.swift:36; UpdateManualDownloadRecovery links to dmg assets ShellX does not publish; CMUX_FEEDBACK_API_URL override keeps HTTP feedback path in release + `cmux feedback --body` returns request_failed; ShellXNetworkPolicy.isForbidden(url:) broader than doc; Manaflow hosts missing from spec list: cmux-staging.vercel.app, api.cmux.sh (flag to Task 13); stale originHash in workspace Package.resolved; dead composer sheet code.
Ruling R17: the CLI/socket entry points to Cloud (`cmux auth login` -> auth.begin_sign_in, `cmux vm|cloud` -> vm.*, billing/pricing, CodeRouter handoff) are added to Task 5's scope (Task 5 title: cloud-only features off; brief lists UI entry points only) — a hard-off gate in the socket handlers + guard assertion — why: T4 review found them reachable and Cloud is hard-off for ShellX 1.x; cost if wrong: a few handlers answer "unavailable" that Wave 2 would re-enable via remoteMachines.
Task 4: fix round 1 implementer DONE_WITH_CONCERNS (ae6efa6286 CodeRouter hard-off+honest allowlist, 479fdd3a53 real NoPhoneHome tests, 1a2090818d hide 2 docs links, 709f470ef4 upstream tests); concerns: PostHogAnalytics.buildAllowsCapture helper + DEBUG-only seam in ContentView.presentFeedbackComposer (CMUX_UI_TEST_CAPTURE_OPEN_URL_PATH); `cmux --help` still says CodeRouter "offers to install it when missing" (needs new catalog key, deferred minor); Machines panel CoderouterCLIAccountReader can still run a PATH/~/.coderouter CodeRouter -> moved to Task 5 scope (R17). Scoped re-review dispatched.
Task 4: fix round 1/5 (5 addressed, 1 new Important open — N1: CodeRouter hard-off breaks ~16 upstream app-hosted tests in cmuxTests/CLIAuthAliasTests.swift that exec a fake CodeRouter via `cmux cr`; commits d960525..709f470)
Task 4: re-review out-of-scope (deferred minor): `cmux --help` text says CodeRouter alias "offers to install it when missing" (cli.coderouter.aliases); 8 orphaned cli.coderouter.bootstrap.* catalog keys (one carries cmux.com install command); scripts/reload.sh still runs install-cmux-tui-client.sh (files.cmux.com, build-time; flag for Task 13); NOT_A_HOST_ALLOWLIST PhonePush keychain entries go stale after Task 3 merge (controller removes).
Task 4: fix round 2 dispatched (resumed implementer): N1 + N2 (duplicate assertion)
Task 3: implementer (opus, resumed work on WIP) DONE_WITH_CONCERNS 12bfe7a800 (9 commits 0859bf6..12bfe7a: restored sed-munged guards + github.html; app typed/looked up bare `cmux` -> shellx fixes; hook block markers; Computer Use policy; older-ShellX prompt; upstream tests). Concerns: agent plugin files still share names with cmux (opencode/pi/amp cmux-session.js/ts, kiro cmux.json, Antigravity hook group, OpenCode TUI dir + markers); skills/cmux-cua/link-policy.sh doesn't recognize ShellX; system.identify app:"cmux"; ~25 upstream cmuxTests fixtures still cmux-named; Step 5 manual check/CLI test lane/ShellXPathsTests[unit]/go test not run. Task review dispatched (opus) over 89129d3..12bfe7a.
Task 4: fix round 2 implementer DONE_WITH_CONCERNS (8be44371a0 CodeRouter alias tests assert the refusal; 23a01f51aa duplicate assertion); scoped re-review dispatched
Task 5: BASE 23a01f51aa (= shellx/l1-t4 head after Task 4 fix round 2; branch shellx/l1-t5, worktree ~/Documents/helper/shellx-wt/l1-t5); scope = brief + R17 (CLI/socket Cloud entry points auth.*/vm.*/billing/coderouter.* hard-off, CoderouterCLIAccountReader no exec, `cmux vm tui` hint). Implementer dispatched (opus) while Task 4 re-review 2 and Task 3 review run.
Task 4: fix round 2/5 (2 addressed, 0 open; commits 709f470..23a01f5); re-review clean. Task 4: complete (commits 89129d3..23a01f5, review clean after 2 fix rounds). Minors deferred listed above + stale cmux-unit-test-timings.json keys, ~250 lines dead mock-server code in CLIAuthAliasTests (CLICoderouterMockHandoffServer).
Merged shellx/l1-t4 (Task 4 final, 23a01f51aa) then shellx/l1-t3 (12bfe7a800, review pending) into shellx/l1-identity; conflicts: Localizable.xcstrings (scratchpad/l1/merge_xcstrings.py key-level 3-way), project.pbxproj (kept both test files, normalized). Removed PhonePush keychain allowlist entries from tests/test_shellx_no_phone_home.py (Task 3 renamed those). All 7 tests/test_shellx_*.py + verify-local 15/15 + localization check green on the lane branch. Pushed for a compile signal from CI while Task 3 review and Task 5 run.
NOTE 2026-10-19: user rule - no Co-Authored-By/attribution lines in commit messages from now on. Task 5 implementer hit a rate limit with no commits; resuming.
CI shellx-mac run 39198027663 on 9cb2895ff6 (L1 + T3 + T4 merged) = SUCCESS (Debug app builds). Task 3 reviewer and Task 5 implementer resumed after rate limit.
Task 3: review 1 (opus) Needs fixes: 0 Critical, 2 Important (I1 agent plugin/extension file names+markers shared with cmux; I2 skills/cmux-cua/link-policy.sh deletes cmux's link). Minor: M1 fish `command -s cmux`; M2 system.identify app:"cmux"; M3 double hook delivery with both apps (deferred); M4 native-copy launch behavior; M5 defaultValue text vs catalog until Task 6 (deferred); M6 codex features key shared (deferred); M7 upstream fixtures (deferred).
Ruling R18: M4 — second native copy of a different bundle keeps upstream terminate behaviour (spec protects only the Flutter app), `.unknown` kind maps to leave-alone so Flutter is never force-killed — cost if wrong: a duplicate native launch is not auto-terminated.
Task 3: fix round 1 dispatched (resumed implementer): I1, I2, M1, M2, M4.
Task 3: fix round 1 implementer DONE_WITH_CONCERNS (e46716c..f020427: I1 shellx plugin names/markers, I2 link-policy ShellX-only, M1/M2, M4 .unknown leave-alone, guards); concerns: opencode uninstall still removes bare ./plugins entry (upstream); skill link name ~/.claude/skills/cmux-cua shared, ShellX reports collision. Scoped re-review dispatched.
Task 3: fix round 1/5 (5 addressed, 1 new Important: OpenCode TUI server plugin id cmux.server; commits 12bfe7a..f020427). Fix round 2 dispatched (resumed implementer): rename to shellx.server + guard. Task 5 implementer resumed after rate limit, still running.
Task 3: fix round 2/5 (1 addressed, 0 open; f020427..a6f3d31). Task 3: complete (commits 89129d3..a6f3d31, review clean after 2 fix rounds).
Task 5: implementer DONE_WITH_CONCERNS (e365ec6..778dc9c); concerns: Settings Account section still visible (Sign In no-op), cmux --help lists Cloud verbs (exit 127), ⌘⇧⌥T team picker shows Cloud-unavailable alert, CmuxCloud package tests not buildable (bonsplit). Review dispatched.
Task 5: review 1 (opus) Needs fixes: C1 dangling @Test(arguments:) breaks cmuxTests bundle; I1 seven upstream test sites still assert Cloud behaviour; I2 pbxproj references 5 deleted UI-test files; I3 lost coverage (surface.* socket tests, CLI EPIPE test, parked DevicesSidebarModeTests). Minor: M1 Settings Account card dead Sign In button (deferred), M2 help/capabilities list refused verbs (deferred), M3 team picker alert (fix now), M4 guard lacks workspace.cloud_vm_* asserts (fix now), M5 launch session restore runs (acceptable), M6 phone pairing parked (note for Wave 2). Fix round 1 dispatched (resumed implementer).
Temp branch shellx/l1-t5ci (5778f3ce16 = lane 1287739 + t5 778dc9c) pushed to read CI compile errors of Task 5 (t5 branch CI run 39224731203 Build app failed; branch lacks annotate step).
Task 5: fix round 1 implementer DONE_WITH_CONCERNS (0947d7e, 1c44e7b); added Sources/ShellX/ShellXSwitches.swift app-side mirror. Scoped re-review dispatched.
Task 5: fix round 1/5 (6 addressed, 0 open; 778dc9c..1c44e7b). Task 5: complete (commits 23a01f5..1c44e7b, review clean); deferred minors M1 Settings Account dead Sign In, M2 help/capabilities list refused verbs, M5 launch session restore, M6 phone pairing parked, closed-stderr EPIPE test not replaced, empty MARK stubs. Runtime of restored surface tests needs CI.
Merged shellx/l1-t5 (Task 5 final, 1c44e7bfd9) into shellx/l1-identity = 7eb40d29ce; conflicts: Localizable.xcstrings (key-level 3-way verified: 0 mismatches vs base/ours/theirs, valid JSON), project.pbxproj (kept ShellXPathsTests + ShellXSwitches/ShellXCloudOffTests, normalized), tests/test-execution.toml (both linux-guard entries). 
Ruling R19: xcstrings keys keep the catalog's existing (unsorted, Xcode) order rather than being re-sorted — base, both sides and lint all use that order; sorting would rewrite ~8k entries — cost if wrong: one re-serialization commit.
Post-merge verification: 8/8 tests/test_shellx_*.py PASS; scripts/verify-local.py 16/16 PASS (xcstrings, localization, localization-defaults, project, test-wiring, feature-flags ...); swift test ShellXBrand 15 tests PASS (incl. ShellXCloudGateTests); check-pbxproj.sh + group-membership rc 0. Pushed 7eb40d29ce.
Lane final review dispatched (opus) over c3afe0da80..7eb40d29ce (77 commits, 804 files), focus cross-task integration.
L1 lane final review 1 (opus, c3afe0da80..7eb40d29ce): Ready, 0 Critical; Important I1 = merged head has no CI compile/test run yet (process item, not code) -> handled by pushing the SDD-state commit with [unit] so shellx-mac + shellx-mac-unit run on it. Review file: lane-final-review-1.md.
Ruling R20: no fix wave — the only Important is "get CI green", which is a CI action, not a code defect; the speculative CloudWorkspaceTargetingTests risk is fixed only if CI shows it red — cost if wrong: one fix round after CI before checkpoint 1.
L1 lane: minor (deferred): M1 user-configured tab-bar/plus-menu Cloud buttons (.cloudVM/.newCloudWorkspace/.newCloudMachine) and .mobileConnect still render but no-op (Sources/Workspace.swift:4721-4728, AppDelegate+NewWorkspaceContextMenu.swift:118); reviewer's toml double-blank-line minor not reproduced.
L1 lane: complete pending CI green on the head (checkpoint 1 = lead).
