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

## Lane L2 (Mac look), branch shellx/l2-look from shellx/sprint c3afe0da80, worktree ~/Documents/myProjects/shellx-wt-l2
Scope: Tasks 6, 7, 8, 9 (verify only), 11, 12. Tasks 2-5B = L1, Task 10 = L3 (parallel, merged by L0 at checkpoint 1, L1 first).
Workspace marker rewritten to the worktree-relative plan path so the SDD scripts resolve this directory (plan text identical).

### Pre-flight scan (L2 tasks)
| Pair / task | Produces vs consumes | Finding |
| --- | --- | --- |
| T6 About <- T9 ShellXLogo | T9 produces ShellXLogo imageset, T6 About shows it | order conflict (6 before 9) -> run T9 first |
| T6 -> T12 | T6 rewrites English values, T12 translates them | agrees (T12 last) |
| T11 -> T12 | T11 adds strings, T12 translates | agrees |
| T7 -> L3 T10 | ShellXFonts.display(size:weight:) | agrees; L3 stubs until checkpoint merge |
| T8 -> L3 T10, T11 | coolicon names Laptop, Desktop, Data, Mobile, Link, Terminal, Bell_Ring, Add_Plus, Search_Magnifying_Glass, Settings, Circle_Check, Shield_Check, Users, Window_Sidebar, More_Horizontal, Qr_Code | agrees if full v4.1 set imported (only 20 SVGs local -> download v4.1 release) |
| T7 vs T8 | both edit SidebarCompactStatusGlyph.swift (colors vs symbol names) | sequential, no conflict |
| T9 vs repo state | AppIcon sets already replaced by 8f92748113 (W0) | master plan says "verify only" |
| T6/T8/T9 tests vs L1 T2 tests/shellx_guard.py | L1 creates the shared helper on its branch | add/add conflict risk -> ruling below |
| T6 vs L1 T4 | both edit Sources/App/About/AboutPanelView.swift (L1: docs link :11) | expected merge conflict; keep About edits minimal/structural |
| T6 vs L1 T3 | rebrand rules cmux.json->shellx.json, ~/.config/cmux->~/.config/shellx in UI strings; L1 renames the real paths | agrees |
| T6 CLI help vs L1 T3 (CLI name) | both edit CLI/cmux.swift | ruling below |
| T12 vs L1/L3 new strings | strings added on other lanes after T12 lack vi | test_shellx_vi red after merge until rerun -> report to L0 |
| T6 self | About text "source: github.com/lephus/shellx-pro" vs ShellXBrand.sourceCodeURL = lephus/shellx (repo move) | conflict -> ruling |
| T6/T7/T10/T11 self | app-hosted tests (cmuxTests, test-app.sh) vs shellx-mac CI (does not build or run cmuxTests) and one-local-build rule | gap -> ruling |
| T7 self | test names (resolve(userConfig:), ShellXAppearance) are placeholders "map onto real names" | agrees (plan says map) |
| T8 self | coolicons in an SPM package xcassets vs `swift test` (CLI SwiftPM may not compile .xcassets) | risk -> ruling |
| T11 self | ShellXTitlebarModel(unreadCount:) init vs `let searchPlaceholder` stored property | agrees if placeholder has a default |
| T12 self | 9.1k keys / ~56k English words in macOS catalogs; iOS catalogs out of scope (W1 = every row except iOS) | size -> ruling |

Ruling: Task order 9, 6, 7, 8, 11, 12 — T6 About consumes T9's ShellXLogo — cost if wrong: none.
Ruling: L2 guard tests import a lane helper tests/shellx_look_guard.py that re-exports L1's tests/shellx_guard.py when present and otherwise defines the same read/offenders/png_size/sha256 locally — avoids an add/add conflict on shellx_guard.py with L1 — cost if wrong: L0 deletes the fallback half after checkpoint 1.
Ruling: Task 9 keeps the W0 AppIcon PNGs (8f92748113); gen_app_icons.sh renders only design/shellx-logo.svg -> ShellXLogo imageset and verifies sizes; AppIcon regeneration from SVG only if test_shellx_app_icon fails — master plan "verify only" — cost if wrong: AppIcon not reproducible from the SVG until W3.
Ruling: About shows "source: github.com/lephus/shellx" (ShellXBrand.sourceCodeURL) instead of the plan's shellx-pro — repo move (common rules) — cost if wrong: one string.
Ruling: CLI help text (Task 6) is changed only through rebrand_strings.py on user-visible string literals; program-name plumbing stays L1 Task 3's — fewer CLI/cmux.swift conflicts — cost if wrong: a few help lines still say cmux until L0 reruns the script after merge.
Ruling: pure models/logic that tests need go where `swift test` reaches them when they are ShellX-owned (ShellXBrand: fonts, appearance, icon map, titlebar badge model may live there); app-hosted cmuxTests files are still written per plan, compiled/run by one local test-app.sh run at the end only if the build lock and disk (>=15 GB after build) allow; otherwise listed for L0 — CI has no cmuxTests step — cost if wrong: app-hosted test breakage found at checkpoint 1.
Ruling: coolicons ship as vector PDFs (or xcassets if SwiftPM CLI processes them) inside ShellXBrand resources, loaded via Bundle.module, template rendering — swift test must see them — cost if wrong: switch format later, ShellXIcon API unchanged.
Ruling: Task 12 translates macOS catalogs (Resources/*.xcstrings, Packages/macOS/*, Packages/Shared/CMUXMobileCore if localization_catalog.py check covers it); iOS catalogs untouched. Translation batches are produced by parallel translator subagents that write only JSON files in the workspace (no repo edits), while Tasks 7-11 run; import is one sequential implementer — cost if wrong: uneven wording, fixed in the read-through.
Ruling: tests/test_shellx_*.py are unittest scripts run as `python3 tests/<file>` — shellx-mac.yml runs them that way and pytest is not installed; a pytest-only file passes silently — cost if wrong: none.
Task 9: implementer DONE 985753c106..5c3df0464e (unittest 3/3; pytest->unittest fixed before review); review dispatched
Ruling: the next task's implementer may start while the previous task's read-only review runs (fix rounds then commit on top) — 12 h sprint, reviews are read-only — cost if wrong: a fix round's commit interleaves with the next task's commits (review packages still use exact ranges).
Task 9: review Spec ✅ / quality Approved (⚠️ PDF render + visual check need a build -> CI/checkpoint smoke)
Task 9: minor (deferred): gen_app_icons.sh uses sips (macOS-only) undocumented in Requires line
Task 9: minor (deferred): test reads scale via img["scale"][0] (1x-9x only)
Task 9: minor (deferred): test also compares against web/public/favicon.svg (redundant with sha pin; FileNotFound if web/ absent)
Task 9: minor (deferred): shellx_look_guard fallback offenders() unused until later tasks; must mirror L1 shellx_guard
Task 9: complete (commits c3afe0d..5c3df04, review clean)
Task 12 prep: 26 vi batches (7515 unique English strings, 8783 units) translated by parallel translators, all validate OK (l10n/)
Task 6: implementer DONE_WITH_CONCERNS f2dd7a202e (branding 9/9, catalog check 0 errors, defaults 0 mismatches, verify-local 15/15; ShellXAboutTests not run); review dispatched
Task 7: dispatched (opus) on top of f2dd7a202e while Task 6 review runs; branch pushed at f2dd7a202e for early CI
Task 6: review Spec ❌ (catalog English vs Swift defaults differ for ~31 keys behind helper wrappers) / quality Needs fixes
Task 6: minor (deferred): CloudVMLoadingPanel.swift:80,109 matches "local cmux web server"/"[cmux]" output text that now says ShellX (Cloud-only)
Task 6: minor (deferred): About window title literal "About cmux" in CmuxAppKitSupportUI AboutWindowKind.swift:39, AboutTitlebarDebugOptions.swift:74
Task 6: minor (deferred): cli.help.agentMessages "resolved like ShellX agent message" should be `shellx agent message`
Task 6: minor (deferred): rebrand rerun loses English-command signal once English says shellx; SUBCOMMANDS static list drifts
Task 6: minor (deferred): .cmux/ -> .shellx/ also rewrites ~/.cmux/local-tmux|local-zellij; Application Support/cmux and bin/cmux text assume L1 renames — L1/L0 confirm at merge
Task 6: minor (deferred): ~648 non-localized user-visible literals (logs, some CLI/app errors, settings confirm alert command text) still say cmux
Task 6: minor (deferred): AboutPanelView GitHub/commit links still manaflow-ai (L1 Task 4 scope)
Ruling: Task 6 fix round runs in a temporary worktree ~/Documents/myProjects/shellx-wt-l2-fix (branch shellx/l2-look-t6fix from f2dd7a202e) and is cherry-picked onto shellx/l2-look — Task 7's implementer commits with `git add -A` in the main lane worktree concurrently — cost if wrong: a cherry-pick conflict to resolve.
Task 6: fix round 1 implementer DONE 0fae2bd257 (side worktree; branding 12/12 incl. Swift-default/catalog parity over 9,993 sites, 137 pre-existing upstream drift keys exempt); re-review dispatched
Task 6: fix round 1/5 (1 addressed, 0 open — helper-wrapped defaults rebranded + parity guard; commits f2dd7a2..0fae2bd on shellx/l2-look-t6fix, to cherry-pick after Task 7 commits)
Task 6: minor (deferred): positional-default / let-defaultValue detection heuristics are loose (no false positives seen; parity test is the net)
Task 6: minor (deferred): 137 pre-existing upstream default/catalog drift keys exempt from parity (tests/shellx_default_drift.json)
Task 6: fix cherry-picked onto shellx/l2-look as aed4d49960 (after Task 7's 8f5afc16ce); branding 12/12, --check exit 0 on the lane branch; side worktree removed
Task 6: complete (commits 5c3df04..f2dd7a2 + aed4d49, review clean after fix round 1)
Task 6: gap found later (Task 7 report): CmuxSettingsUI package test expects "cmux Max" (now "ShellX Max") — fix in Task 7 fix round or final wave
Task 7: implementer DONE_WITH_CONCERNS 8f5afc16ce (ShellXBrand 13/13, CmuxFoundation 12/12, CmuxTerminalCore 507/507, CmuxSettings 488, CmuxSettingsUI 260/261 [Task 6 string], test_shellx_theme 7/7; app target only syntax-checked); review dispatched
Ruling: Task 8 icons must keep SF-Symbol sizing behaviour at existing call sites (scale with .font/imageScale, template tint); preferred = coolicons as custom symbols (.symbolset, strokes outlined at dev time e.g. picosvg) in an asset catalog; plain 24 pt images would break ~670 layouts — cost if wrong: icon sizing pass later.
Ruling: icon resources go in a separate resource-bearing target/product of the ShellXBrand package (e.g. ShellXIcons) linked to the app + UI packages only, so cmux-cli (which links ShellXBrand) never carries or touches a resource bundle — plan puts ShellXIcon.swift in ShellXBrand — cost if wrong: one more product name in Package.swift.
Ruling: Task 12 (vi import) runs in parallel with Task 8 in side worktree ~/Documents/myProjects/shellx-wt-l2-t12 (branch shellx/l2-look-t12 from aed4d49960), cherry-picked after Task 8; Task 11 strings get a small vi top-up after Task 11 — catalogs/l10n tooling don't overlap Task 8's Swift codemod — cost if wrong: JSON conflict in a catalog at cherry-pick.
Task 8: dispatched (opus) on aed4d49960; Task 12: dispatched (opus) in side worktree shellx/l2-look-t12
Task 7: review Spec ✅ / quality Approved, 1 Important (sidebar defaults to bg because matchTerminalBackground stays true; spec §7.4 says panel for sidebar)
Ruling: Task 7 sidebar default = panel (#100b1d) — matchTerminalBackground default flipped to false — spec §7.4 table ("panel: sidebar, thanh tiêu đề") outranks the implementer's ruling — cost if wrong: one-line flip back.
Ruling: omnibar suggestion popover gradient is removed in the Task 7 fix round (spec bans gradients on every UI component, not only buttons/rows) — cost if wrong: none.
Task 7: minor (deferred): status glyphs ignore `secondary` on a light user-theme sidebar (contrast)
Task 7: minor (deferred): flash ring shares 0.45 alpha / 1 px -> fainter navigation flash (check by eye)
Task 7: minor (deferred): CmuxConfigSchema.generated.swift hand-edited under a "do not edit" header (source schema absent)
Task 7: minor (deferred): enforceShellXDarkOnly writes defaults inside the defaults observer (one extra harmless apply)
Task 7: minor (deferred): CLI diff/markdown viewer still defaults to "Apple System Colors" (cmux_open.swift:3458,3470, diffSurface.mjs)
Task 7: minor (deferred): "Adapt Default Theme to Appearance" copy still talks light/dark; ThemesSection keeps an unused appearance model
Task 7: minor (deferred): ShellXTerminalTheme.swift:187 comment 3.7:1 vs report 3.8
Task 7: fix round 1 implementer DONE 1cc9b042b1 (side worktree; CmuxSettingsUI 261/261, CmuxSettings 488/488, theme 9/9); extra: CmuxConfigSemanticValidatorTests cmux.json expectation (Task 6 gap) requested in same worktree
CI: 39174936475 green on f2dd7a202e (Tasks 9+6, cold 62 min); pushed aed4d49960
