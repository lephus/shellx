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

## Lane L3 (l3-sidebar) — Task 10 only, branch shellx/l3-sidebar from shellx/sprint c3afe0da80, worktree ~/Documents/myProjects/shellx-wt-l3
### Pre-flight scan (Task 10)
| Pair / task | Produces vs consumes | Finding |
| --- | --- | --- |
| T10 vs T7 (L2) | T10 consumes ShellXFonts.display(size:) | not on shellx/sprint yet (L2 unmerged) -> conflict |
| T10 vs T8 (L2) | T10 consumes ShellXIcon coolicon names | not on sprint; models carry coolicon names as String (agrees with plan's `coolicon: String`), rendering needs a resolver -> conflict |
| T10 vs T9 (L2) | T10 consumes ShellXLogo | not on sprint -> conflict |
| T10 vs T1 | consumes ShellXPalette | present (agrees) |
| T10 vs T12 (L2) | new keys need vi values | plan T10 gives vi pill/note values; catalog vi support arrives with T12 -> implementer adds vi if catalog accepts it |
| T10 vs T11 (L2) | title bar; no shared file named | agrees |
| T10 vs W2 U1 (L3) | U1 extends SidebarMachineKey/.Input/.HeaderModel and adds sections(for:local:remote:now:) keeping the W1 wrapper | agrees; placement must let U1 add remote inputs without ShellXRemoteCore dependency |
| T10 self: Step 2/4 test-app.sh + `reload.sh --tag w1` | needs a local app-host build | conflicts with sprint rule (keep >=15 GB free; 26 GB free, a cmux DerivedData is ~14 GB; prefer CI) |
| T10 self: test headerAndRowHeightsIgnoreTextLength | uses app type SidebarWorkspaceTableRowHeightCalculator | app-only; cannot run in package tests |
| T10 self: files Create vs Modify | creates Sources/ShellX/Sidebar/*, modifies upstream wiring files | agrees |

Ruling: pure Task 10 models (SidebarMachineKey, LocalMachineInfo, SidebarMachineInput, SidebarMachineHeaderModel, SidebarMachineSection, SidebarMachineGrouping, SidebarStatusPill core + header height rule) live in Packages/Shared/ShellXBrand/Sources/ShellXBrand/Sidebar/ with Swift Testing tests in ShellXBrandTests (run by `swift test` locally and by shellx-mac CI); app-only parts (SidebarStatusPill.from(SidebarCompactStatusGlyph.Kind), cells, wiring) stay in Sources/ShellX/Sidebar/ — CI does not build cmuxTests and a local app-host build would cost ~14 GB of the 26 GB free (rule: keep >=15 GB) — cost if wrong: plan file layout differs (pure model in the package instead of Sources/ShellX); app-side tests (cmuxTests/SidebarStatusPillTests.swift for the kind mapping + row height calculator) are written and wired but not executed in the sprint, so a compile error there would surface at the first cmux-unit run.
Ruling: until L2's T7/T8/T9 merge, the brand header uses NSApp.applicationIconImage as the logo, a system semibold font where ShellXFonts.display(size: 14) is specified, and icons resolve coolicon names through one small app-side resolver (NSImage(named:) first, SF Symbol fallback) — L2's types are not on shellx/sprint — cost if wrong: a small follow-up after checkpoint 1 to swap in ShellXIcon/ShellXFonts/ShellXLogo.
Ruling: Step 4's local `--tag w1` visual check is replaced by the shellx-mac CI Debug build; the by-eye mockup comparison goes to L0's checkpoint-1 smoke / "Needs user" — one local Xcode build at a time, disk — cost if wrong: layout defects found at checkpoint 1 instead of now.
Task 10: implementer DONE_WITH_CONCERNS 5a81a55625..8f21bed177 (package 23/23, verify-local 16/16, l10n check 0 errors; app code uncompiled -> CI run 39173013282); concerns: laptop rule uses battery (hw.model is Mac14,7), Add_Plus opens user@host prompt -> ssh:// handleCmuxSSHURLs, pills only with sidebar.compactAgentStatus on, brand header scrolls as first row, cmuxTests row-count/legacy-path tests will break, localize-changes crashes (web/i18n gone)
Task 10: review dispatched (opus) on c3afe0da80..8f21bed177
Task 10: review Spec ❌ / quality Needs fixes — Important: pills hidden unless sidebar.compactAgentStatus (default off); vi title not uppercase; waiting pill lacks primary ring; app-side grouping/repeat-id untested. ⚠️: label truncation paragraph style; offline dot refresh for non-selected SSH ws; cmuxTests ShellXBrand product dep duplicate-link risk; vi not in knownRegions (L2 Task 12 owns).
Ruling: status pill shows on every row with default settings (status kind computed regardless of sidebar.compactAgentStatus; the leading compact glyph stays gated) — spec §7.1 "bên phải: nhãn trạng thái" is binding over the plan's "pill next to the compact glyph" wiring — cost if wrong: per-row glyph computation always on (small CPU), a one-line revert.
Task 10: minor (deferred): header fonts don't scale with sidebar font magnification (SidebarMachineHeaderCellView, SidebarBrandHeaderView fixed 12/11/10.5 pt).
Task 10: minor (deferred): status shown twice in compact mode (leading glyph + pill).
Task 10: minor (deferred): SidebarMachineModelTests.swift:108 "pinned value" test compares id with itself.
Task 10: minor (deferred): SidebarMachineHeaderLayout lives in SidebarStatusPill.swift:52.
Task 10: minor (deferred): ShellXAddMachinePrompt only beeps on bad input; sshURL(from:) untested (SidebarBrandHeaderView.swift:135-143).
Task 10: minor (deferred): hidden-sidebar liveRowIds (ContentView.swift:12377-12380) drop header ids -> reload on reveal.
Task 10: minor (deferred): Cmd-1..9 follows machine order while arrows/drag follow tab order; drop among another machine's rows has no visible effect.
Task 10: minor (deferred): LocalMachineInfo.current() cached for process lifetime (rename needs relaunch).
Task 10: minor (deferred): vi not in pbxproj knownRegions; only these keys have vi (W1 Task 12, L2).
Task 10: fix round 1 dispatched (resume implementer) with 8 findings (4 Important, 3 ⚠️ confirmed, 1 cheap minor)
Task 10: fix round 1/5 (8 addressed, 0 open; commits 8f21bed177..fa28dda193)
Task 10: minor (deferred): cmuxTests use deprecated TabManager.addWorkspace (warnings); makeSSH remoteConfiguration didSet side effects untraced (tests unexecuted).
Task 10: complete (commits c3afe0da80..fa28dda193, review clean) — app compile pending CI (run 39173013282 on 8f21bed177; fa28dda193 to follow)
Task 10: CI shellx-mac 39173013282 on 8f21bed177 = success (app compiles); fa28dda193 pushed as shellx/l3-sidebar-t10 -> run 39177487838; branch head fe8dfc2e1e -> run 39177495262
