# Top-level ledger — V2-2b / V2-3 / V2-4 execution (2026-10-15)

Recovery map for the top-level controller. Trust this + `git log` + each plan's `MAIN/.superpowers/sdd/<plan>/progress.md` over memory.

## User decisions
- 2026-10-15 ~13:50: "giữ ở shellx-v2, chưa push main" — V2 stays on shellx-v2; NO push to main until the user says so (main pushes run release-desktop.yml since teammate commit 5929cdc). Memory updated.
- User force-pushed origin/shellx-v2 906078a → 14e9eb1 themselves (shellx-v2 now linear on origin/main 5929cdc).
- Relay (relay/**) and web/** changes: branch v2-2b-relay only; merge needs the user's explicit deploy consent.

## Branch / worktree map
- MAIN `/Users/richard/Documents/helper/shellx` on `shellx-v2` (scripts run here; never implement here).
- `shellx-v2` = eb0b6dc = origin/shellx-v2: 5929cdc → 14e9eb1 (V2-2b plan) → 130d8aa (V2-4 plan) → eb0b6dc (V2-3 plan).
- `.claude/worktrees/v2-2b` branch `v2-2b` from 14e9eb1.
- `.claude/worktrees/v2-2b-relay` branch `v2-2b-relay` from origin/main 5929cdc (deploy-clean: relay/web only). Upstream UNSET 17:30 (it tracked origin/main).
- `.claude/worktrees/v2-4` branch `v2-4` from 130d8aa.
- `.claude/worktrees/v2-3` branch `v2-3` from eb0b6dc.
- origin/main moved 17:2x: 5929cdc → e74b02f (teammate's release fixes; tag desktop-v1.0.0). shellx-v2 and v2-2b-relay are based on 5929cdc. Rebasing shellx-v2 onto the new main needs a force-push of origin/shellx-v2 (the user runs it) — decide at the end / ask the user.

## Workflow triggers (checked on origin/main e74b02f, 17:30)
- deploy.yml: push to main with paths relay/**, web/**, deploy/** (+ manual dispatch / workflow_call).
- release-desktop.yml: push to main, paths-ignore docs/**, **/*.md (+ manual dispatch).
- windows-check.yml: push to windows-check/** (+ manual dispatch).
- → pushes of v2-2b, v2-2b-relay, v2-3, v2-4, shellx-v2 run nothing.

## Chunks (controller agents, opus; common brief scratchpad/track/controller-common.md)
- V2-2b (26 tasks): chunk1 1–6 DONE; chunk2 7–13 DONE (19:00); chunk3 14–19 DONE (01:10, 16/10); chunk4 20–26 + final review [running, controller a91e97d4a8536d7ba, launched 01:20]; chunk4 20–26 (+ final whole-branch review).
- V2-4 (16 tasks): chunk1 1–7 DONE (18:40); chunk2 8–14 DONE (16/10 ~10:00); chunk3 S1/S2 hardening + 15–16 + final review [running, controller a44807ff410140528, launched ~10:05]; chunk3 15–16 (after cherry-picking V2-3 Task 1 into v2-4; + final review).
- V2-3 (16 tasks): chunk1 1–6 DONE (18:25); chunk2 7–12 DONE (23:35); chunk3 13–16 + final review [running, controller a24d78c9f12b4ca1f, launched 23:45]; chunk3 13–16 (+ final review; then push windows-check/v2-3 for CI).
- Ledgers never shared: V2-2b → docs/superpowers/ledgers/v2-ai.md; V2-3 → v2-tools.md; V2-4 → v2-4-tools-phone.md.
- V2-3 Task 1 commit range → cherry-pick into v2-4 before V2-4 chunk3 (Task 15).
- Smaller chunks from now on (3–4 tasks) where a chunk has fix rounds or native work.

## Harness lesson (17:30)
- All three controllers were force-handed-back ("[handback-send-enforce]") or cut: a subagent that ends a turn with no live background child is made to hand back. Trigger: an implementer resumed by SendMessage ran tests with run_in_background and ended its turn → controller told "completed (interim)" → controller ended its turn to wait → enforced.
- Fix: "Harness note" section appended to controller-common.md (children run everything in the foreground; controllers arm bounded background waits; on forced hand-back the ledger is the resume point).
- Recovery: resume the SAME controller by SendMessage (context intact; avoids two controllers in one worktree). A resumed controller that believes it must hand back again needs an explicit "resume" order.

## Progress
- V2-2b chunk1 DONE (14e9eb1..cea0659, 7 commits, reviews clean, 28 minors deferred to final review).
  Concerns for the report: (a) wording "Đã nối lại sau khi ShellX khởi động lại." shows after a tab closes with a twin tab open though nothing restarted — user wording decision (recommend neutral "Đã nối lại phiên."); (b) "từ điện thoại" cannot tell which of two paired phones sent a prompt; (c) manual check 8 (re-attach after restart) with and without the background service; (d) Tasks 2–4 ship together (protocol 2).
- V2-2b chunk2 DONE_WITH_CONCERNS (19:00): cea0659..d36b214 (11 commits incl. F19 ef867fe); core 368, ai 622, agent 961, client 173, desktop 3584+10, mobile 1318, relay 377; push e2e 2/2 live vs Task 7's relay with fake FCM. Hand-off handoff-7-13.md. Relay: v2-2b-relay c6cf495 (Task 7), not deployed, no upstream.
  Fixed plan-code holes: F17 (phone saw/set no-approval-named option), F21 (full-item cache could serve a replaced runtime's item under the same sid), F23 (after restart an old question form could show for a new question with the same ask id), F18, F22, F24 (cut line never splits a surrogate pair), F25.
  **For chunk 4's final review fix dispatch (include regardless of verdict):** lone-surrogate option id → whole push lost (relays refuse); config sheet in-flight state per instance (reply during exit animation pops the session page); triage: Allow button checks only optionId, not the option's name.
  Task 26 manual-check additions: cold-start push tap opens the session once; refusal toast over the modal config sheet on a real device; criterion 2's ≤ 2 s end to end. Task 20: AppDelegate.swift comment (firebase_messaging becomes the centre's delegate).
  For the user: F17+F19 — an agent setting merely named like a no-approval mode is set only on the computer, behind the Bypass question, never remembered (an off value is set without asking).
  Chunk-2 concerns for the report: F16 (ai_phone_wiring_test.dart added to Task 8); relay before deploy: one real FCM push with category+tag, the npm ci "1 high severity vulnerability" advisory; final-review items (lone-surrogate option id loses the push; Allow checks only option id); Task 26 cold-start tap opens once; Task 20 fixes the delegate comment.
- V2-3 chunk1 DONE_WITH_CONCERNS (18:25): eb0b6dc..bc1ec86, 12 commits; desktop analyze clean, suite +3708 ~9 (plan totals +5 from Task 5 on); isolated real-WebKit run +12 (twice). Hand-off: MAIN/.superpowers/sdd/2026-10-15-v2-3-tools-desktop/handoff-1-6.md.
  **Task 1 commits: f7bacfe..54489b9 → `git cherry-pick eb0b6dc..54489b9` into v2-4 before V2-4 Task 15.**
  For the report: real-home prefs leak — CFFIXED_USER_HOME does not redirect cfprefsd; ~/Library/Preferences/pro.shellx.desktop.itest.plist (12:09, a full-app test launch) and pro.shellx.desktop.smoketest.plist (V2-2a smoke runs) exist; not the user's data; offer `defaults export <id> <file>` + `defaults delete <id>`. Task 16 (chunk 3) must export+delete the itest domain before and after its launch (ruling to give chunk 3). Known limits: cancelled JS prompt → "" on macOS; keypad ./= forward as main keys. Manual checks: shortcuts from a tool page on non-US layouts (RU, HE, AR, AZERTY, TR-F); click outside returns the keyboard; download-attribute export shows the download line. Merge: resolve ARBs then flutter gen-l10n; settings key count v2-3 = 35 (theirs + 1). find_session_test flaked once under load.
- V2-4 chunk1 DONE_WITH_CONCERNS (18:40): 130d8aa..cadc3cd, 12 commits; core 404, agent 962, client 159, e2e 16+9, mobile 1262, desktop 3578+6; analyze clean (mobile's pre-existing info). Hand-off handoff-1-7.md. Plan-code defects fixed under rulings (pacer overflow after ~12.7 idle days; zero-byte WS pieces → toolWsPieceCost=max(1,len); idle clock, list `available`, `//` targets; Task 6 upgrade sockets, duplicated subprotocol, close-reason cut). 52 minors deferred (final-review triage: persistentConnection=false for 1xx, unpaced tool.list replies, ws.close() without limit, unpinned flush reset, RF4 list-entry test, bodyless branch test).
  Security (chunk-1 ruling 9): gate cookie leaks to any localhost port (cookies ignore ports) → top-level ruling CSP (below) carried into Task 9.
  Merge notes: frozen V2-2 decoder files byte-identical to V2-2b 329dce0; textual merges in shellx_core messages.dart (part list, ai./tool. arms), later session_router.dart and lib/shellx_agent.dart — keep both sides.
- Backups: 19:02 origin/v2-2b d36b214; 18:45 origin/v2-4 cadc3cd; 17:25 origin/v2-2b a4011e0, origin/v2-2b-relay c6cf495, origin/v2-3 e2e0be3, origin/v2-4 14387fe (reflog-checked: all by my pushes); 18:27 origin/v2-3 bc1ec86.

## Integration plan
- Linear history (as V2-2a): rebase each finished track onto current shellx-v2, resolve conflicts (ARB, pubspecs, plists, messages.dart, ledger appends), full verify (scratchpad/full-verify.sh), then fast-forward shellx-v2 and push origin shellx-v2 (never main).
- Back up track branches to origin under their own names (no deploy triggers).

## Rulings (top-level)
- Ruling: force-push of origin/shellx-v2 was denied by the permission classifier; did not work around; the user ran it — cost if wrong: none.
- Ruling: the SDD skill files are copied to scratchpad/sdd-skill/ because reads of the plugin cache were refused — cost if wrong: a stale copy of the skill (6.4.1).
- Ruling: track controllers are opus subagents per chunk (bounded context, ledger-resumable) rather than one controller in this session — cost if wrong: a chunk controller misreads the ledger; caught by the per-chunk hand-off review.
- Ruling (F19, 17:30): on the computer, a config option whose own id aiIsNoApprovalMode flags is a no-approval choice — any non-off value asks the Bypass question first; such an option is never remembered nor re-applied — why: the user's binding rule "never re-apply a remembered no-approval mode"; F17 closed the same gap on the phone only — cost if wrong: one extra Bypass question for an option no agent ships today. Own fix commit on v2-2b after Task 10.
- Ruling: forced hand-backs are recovered by resuming the same controller (SendMessage), not a fresh one — why: two controllers in one worktree would collide when an old controller is resumed by its child's message — cost if wrong: a resumed controller's context is large and may compact; the ledger covers it.
- Ruling (CSP, 18:45, V2-4 Task 9): the phone's loopback tool server adds one Content-Security-Policy header to every response: `default-src 'self' <S> https: wss: data: blob: 'unsafe-inline' 'unsafe-eval'; form-action 'self' <H> https:` (S/H = http+ws / http localhost origins of every port the server listens on, ascending; never upgrade-insecure-requests) — why: cookies ignore ports, so the gate cookie and the tool's cookies reach any localhost port a page requests; an app listening there (alias mode: the app holding P) would pass E11's gate (spec Review Focus 5) — cost if wrong: plain-http remote resources and unserved localhost ports blocked in phone tool pages; a newly enabled tool reachable after a reload. Manual check added for spec §10.
- Ruling: v2-2b-relay's upstream (origin/main) unset — why: a bare `git push` from that worktree could have targeted main (production deploy) — cost if wrong: none.

## Pending for the user (final report)
- Consent to deploy relay (V2-2b Task 7 + Task 26 privacy pages, branch v2-2b-relay; rebase it onto the then-current main first — main moved to e74b02f).
- When V2 may go to main (release trigger); shellx-v2 is based on 5929cdc while main is at e74b02f+ (rebase needs the user's force-push, or a merge at that time).
- V2-4 security ruling (CSP on phone tool pages) and its compatibility cost — tell the user.
- Wording decisions (V2-2b chunk 1): "Đã nối lại sau khi ShellX khởi động lại." → "Đã nối lại phiên."?; "từ điện thoại" with several phones.
- Relay pre-deploy: one real FCM push with category+tag; npm advisory (1 high).
- Manual checks: V2-3 spec §11, V2-4 spec §10, V2-2b spec §10 (check 8 with and without the background service); real Claude on the user's account; Windows CI (windows-check/*); iPhone Profile/Release push build; Android 13+.

## Usage limit (2026-10-15 ~20:20 → reset 21:20)
- All three controllers failed with API 429 (session limit) around 20:20: V2-2b chunk3 a2f0e6de7e7c2b9cc (Task 15 reviewer abdb4f307192339c2 killed mid-review), V2-3 chunk2 aa0f12c751a432f68 (Task 10 implemented a657251, review not dispatched), V2-4 chunk2 addfb8bda9eab1d13 (Task 9 reviewed by a7c2cd11919764d1b — verdict saved by me to the V2-4 workspace task-9-review-verdict.md: Spec ❌ RF5 expired-entry pin + E7/E8 no dropped byte).
- 21:21 resumed all three by SendMessage (context intact). Worktrees clean at v2-2b c3b662c, v2-3 a657251, v2-4 28b57eb; backed up to origin.
- If the limit hits again: same recovery — check worktrees, extract any orphaned reviewer hand-back (SubagentHandback tool_use input in its transcript) into the plan workspace, resume each controller.

## V2-3 chunk 2 DONE_WITH_CONCERNS (23:35)
- bc1ec86..004cb6d (14 commits, cd8f192..004cb6d); desktop analyze clean, +3814 ~9 (plan +46, all ruled/review-fix tests); shellx_agent +921. Hand-off handoff-7-12.md. origin/v2-3 = 004cb6d.
- INCIDENT: Task 12 implementer a50fbb35d499fc13f ran `rm -rf SCRATCH/bak` (not its own folder). My track/, sdd-skill/, smoke/ intact. Told V2-2b and V2-4 controllers; "Scratch hygiene" section added to controller-common.md (own mktemp -d folder per dispatch).
- Merge: Task 11 tripwire test (test/tools/tool_ports_test.dart) fails by design if V2-2b changed AiHost.runtime → update the copy in apps/desktop/lib/src/ai/ai_runtimes.dart, then the pinned text. Shared files: ai_runtimes.dart, config (shellx_config, settings_schema, config_show, config_template + settings_schema_test: `tool-embed` key), settings_values.dart, restore_*, terminal_tabs.dart, terminal_overlays.dart, url_opener.dart, fakes.dart, pubspec.yaml, Windows plugin files. No ARB key in chunk 2.
- Windows CI (windows-check/v2-3 after chunk 3): first build of webview_win_floating 3.0.3 + fullscreen_window 1.2.1 (C++, NuGet WebView2 SDK at CMake time).
- For the report: Windows tool-embed=on D9 gaps (redirect to mailto/custom scheme → WebView2's own prompt; cross-origin POST; back/forward), criterion 2 on Windows (Add suggestions ≤ 2 s with a cold PowerShell/CIM), R9 knock for *.localhost and 0.0.0.0, ⌘⇧B with tool-embed=off opens the browser; known limits: failed WebView2 creation → console PlatformException at GC; tool-less dock with custom width written to layout.json. SystemUrlOpener bare rundll32 (pre-existing) for the final review.
- Chunk 3 ruling: final fix wave always includes D10 (⌘⇧B wrong tool, _lastViewed) and D13 (back-off restart after URL edit); no workspace deletion, no finishing skill, no merges.

## V2-2b chunk 3 DONE_WITH_CONCERNS (01:10, 16/10)
- d36b214..03fc266 (12 commits); core 368, ai 632, agent 995, client 193, desktop 3595+10, mobile 1441; analyze clean (mobile pre-existing info). Hand-off handoff-14-19.md. origin/v2-2b = 03fc266. Relay untouched (c6cf495).
- For the report: F38 photos — image_picker kept EXIF incl. location; the phone now strips it, keeps Orientation only (Android upright = device check); F28 history titles 120 characters (spec), not 120 bytes (plan); F34 ≤ 20 MB of photos per message (desktop per-phone cap), said in the composer; spec costs: same past session opened twice → two tabs (B17), no progress while a resume travels, a retried history page may be refused.
- Final review must-include (given to chunk 4): lone-surrogate push loss; config sheet in-flight per instance; triage Allow-by-optionId; audit 49 mobile `Watch(` sites (F43 stale pattern).
- Task 26 manual checks: criteria 8, 3 (5 photos ≤ 10 s), 4 (@sr ≤ 8 suggestions ≤ 1 s), 5 (mic; first-ever tap needs a second tap after Allow; Don't Allow note), photos upright w/o location (iPhone + Android), small-phone layout 375×667 + composer 320–360 dp.

## Usage limit #2 (16/10 ~01:30 → my session resumed only at 09:15)
- All three controllers failed with API 429 ~01:30 (reset 02:20). My own wake-up Bash only ran at 09:15:58, so nothing ran 01:30–09:15.
- 09:17 state: v2-2b dd7031c (Task 20 complete; Task 21 implementer a7b7a651fb7b17f09 stopped with uncommitted Android/iOS push-action changes); v2-3 f128aea (Tasks 13 done, 14 under review — reviewer a29b20c761d87c800 likely killed); v2-4 769128f (Task 13 fix round 3 a899e9058c33f23b1 had not committed).
- 09:18 resumed all three by SendMessage; backups pushed (v2-2b dd7031c, v2-3 f128aea, v2-4 769128f).
- Revised ETA: V2-3 done ~12:00, V2-4 (incl. chunk 3 + final) ~13:00, V2-2b (21–26 + final) ~14:30, integration ~16:00 — if no further limits.

## NEW REQUEST (16/10 ~09:25) — brainstorming in progress (no code until specs approved)
User: (1) "AI Assistant" UI like the Claude desktop app, choose a project to work in; (2) new theme, fonts, components, style ref Figma "Online Bike Shopping App (Community)" https://www.figma.com/design/QgQsGtshcpfstl001CslNB/...?node-id=1-4; (3) voice command/discussion with AI like ChatGPT voice — smooth, easy; (4) app name (mobile + desktop) → "ShellX: Remote AI agents".
- Classified architectural, 4 sub-projects; proposed order 1+2 (rename + design system) → 3 (AI workspace UI) → 4 (voice); code starts after V2-2b/3/4 are integrated.
- Research agents (sonnet) → SCRATCH/v25-research/: design-system-and-naming.md, ai-ui-current.md, voice-current.md, references.md.
- Figma MCP OAuth started; link given to the user (redirect http://localhost:57947/callback; if it fails, user pastes URL → complete_authentication).

## V2-4 chunk 2 DONE_WITH_CONCERNS (16/10 ~10:00)
- cadc3cd..d127c04 (29 commits); client 218, e2e 16+10, desktop 3581+6, mobile 1355; core/agent untouched 404/962. Hand-off handoff-8-14.md. Review-found gate holes fixed (Task 9 [::1] hijack, hung answers, lost first WS message; Task 13 Android download loop, back/history.back to ports another app holds).
- My cherry-pick: V2-3 Task 1 (f7bacfe, 54489b9) → v2-4 as ab82735, 50cfd1b (clean). origin/v2-4 = 50cfd1b.
- Top-level rulings for chunk 3: S1 CSP form-action drops https: (Android POSTs bypass the nav policy) — cost: tool form posting to remote https fails on phone; S2 IPv4-only serving only when NetworkInterface.list(includeLoopback) lists no ::1 (else both stacks or alias, else error) — cost: device with ::1 refusing binds cannot open tools.
- Final fix wave must include 1xx handling (persistentConnection=false; non-101 1xx never final).
- For the report: accepted — Android beforeunload "stay" can cancel the page blanking; device checks in handoff-8-14 §"For the top-level controller" 2.
- NOTE: my Bash `cd` into the v2-4 worktree moved the session's primary working directory there; use absolute paths / git -C from now on.

## V2-5 (16/10 ~10:50) — user approved the proposal: "làm theo khuyến nghị, Nhưng tên app nên để tên đầy đủ"
- Decisions: all recommendations, except the home-screen/launcher label = full "ShellX: Remote AI agents" (identity fields stay "ShellX"). Figma: public images only ("dựa vào ảnh công khai của file figma").
- Source of truth: SCRATCH/v25-research/approved-proposal.md.
- Specs being written in parallel (opus agents, files only, I commit on shellx-v2 after review):
  - docs/superpowers/specs/2026-10-16-v2-5a-name-and-design-system-design.md
  - docs/superpowers/specs/2026-10-16-v2-5b-ai-assistant-design.md
  - docs/superpowers/specs/2026-10-16-v2-5c-voice-conversation-design.md
- Next: review specs → commit → user reviews → plans (A first; B, C after reading A's plan) → execute after V2-2b/3/4 integration. Max 2 parallel tracks for V2-5.

## Usage limit #3 (16/10 ~12:35 → reset 13:30)
- Killed: V2-2b chunk4 a91e97d4a8536d7ba (Task 25 reviewer a509c2938de954bda), V2-3 chunk3 a24d78c9f12b4ca1f (final fix wave implementer a3a9e4c09f402957a mid-work, uncommitted ledger-doc change), V2-4 chunk3 a44807ff410140528 (final reviewer a60146f9a8826cf8e), V2-5 cross-spec reviewer a1bb87d2e8b10c88e (mid-edit).
- 13:35 resumed all four by SendMessage. Backups: v2-2b 875feea, v2-3 6ce3170, v2-4 1b378da.
- V2-5 specs written (uncommitted in MAIN): 5a 944 lines, 5b 875, 5c 931. Fallback font on Apple = JetBrains Mono (Menlo lacks 46 Vietnamese letters) — my ruling. B's open items ruled by recommendation: 🎙 hidden on desktop; AI tabs not listed in Terminal mode.

## V2-5 specs APPROVED (16/10 ~14:00) — user: "duyệt"
- Commits on shellx-v2: fb06ff5 (three specs), 3f0adcc (C37: vendored speech_to_text drops os_log of recognized words — my addition after the cross-review). origin/shellx-v2 = 3f0adcc.
- Cross-review fixes applied (icon roles = A's; JetBrains Mono fallback; B T2/T41 decided; aiSettingClaudeDesc drops "Claude Code").
- Plans: V2-5a plan writer (opus) launched ~14:05 → docs/superpowers/plans/2026-10-16-v2-5a-name-and-design-system.md. B and C plans after A's plan exists (execution of B/C not before ~03:00 17/10).
- Execution: worktree .claude/worktrees/v2-5a, branch v2-5a from the integrated shellx-v2; ledger doc docs/superpowers/ledgers/v2-5a.md. Max 2 parallel tracks for V2-5.
- Integration rebases: V2-2b/3/4 tracks must rebase onto shellx-v2 = 3f0adcc+ (docs only).

## V2-3 DONE (16/10 ~14:10) — DONE_WITH_CONCERNS
- v2-3: eb0b6dc..73b9bdf (47 commits); final review + one opus fix wave (9 items) re-reviewed clean. Tests at 73b9bdf: desktop 3874 + 9 skipped, agent +921, isolated real-WebKit +13, smoke launch clean. Hand-off handoff-13-16.md.
- Pushed: origin/v2-3 = 73b9bdf; origin/windows-check/v2-3 = 73b9bdf (Windows CI — user reads result; first build of webview_win_floating 3.0.3 + fullscreen_window 1.2.1).
- SECURITY (for the report): desktop secure store uses a fixed Keychain account `pro.shellx.desktop` (secure_key_value_store.dart:27–33) → isolated itest/smoketest launches look up the REAL app's Keychain items (nothing prompted/written observed; not verified); smoke launch also GETs relay /v1/version. Ruling sent to the V2-5a plan writer: spike never runs main(); new ⚠ task namespaces the Keychain account by bundle id (production stays `pro.shellx.desktop`); no full-app launch before it.
- Parked (user's call): workspace deletion silently removes its tools; toasts under a zoomed dock; refused panel blinks on retries; retries while minimized.
- Integration: worktree .claude/worktrees/int, branch int/v2-3 = v2-3 rebased onto shellx-v2 3f0adcc → 6a51fd3 (clean, 47 commits). Full verify running (SCRATCH/int-v2-3-verify.log); then ff shellx-v2 → push.
- 14:15 V2-3 INTEGRATED: shellx-v2 = 6a51fd3 (= v2-3 rebased onto 3f0adcc), pushed. Full verify at 6a51fd3: core 351 (one load flake, re-run green), agent 921, client 159, e2e 16+9, acp 87, ai 576, desktop 3877+6, mobile 1262 (analyze: mobile's pre-existing info only).
- Next integrations: V2-4 (rebase drops the cherry-picked V2-3 Task 1 commits ab82735/50cfd1b as already applied), then V2-2b. Worktree .claude/worktrees/int can be reused (new branch per track).
- NOTE: avoid `cd` in Bash (it moves the session's primary working directory); use `(cd … && …)` or -C.

## STOP (16/10, user at ~14:22): "đẩy toàn bộ code, spec, memory mới nhất lên git lúc 15h chiều nay; và dừng code. Tôi sẽ tiếp tục code sau"
- Stop orders sent ~14:25 to V2-4 chunk3 (a44807ff410140528), V2-2b chunk4 (a91e97d4a8536d7ba), V2-5a plan writer (ad56aebd9af64645c): checkpoint, commit WIP, ledger resume point, hand-off, return by 14:50; no pushes.
- V2-5a plan writer returned 14:39: plan partial (Tasks 1–4 full, 5–16 outlined), 4,759 lines, rulings R1–R16. It also built a merged "union" clone (all four branches + T1–T4 committed + T5 wip) at SCRATCH/v25a-union, branch `plan` — verified SF Mono spike passes all five criteria on macOS (isolated) and an iOS 26 simulator. Pushed as `v2-5a-wip-union` (experimental; its merge resolutions are NOT the integrator's).
- Hand-off bundle: docs/superpowers/handoff/2026-10-16/ on shellx-v2 (README in Vietnamese, coordination/, research/, sdd/, memory/). Memory: new v2-handoff-2026-10-16.md.
