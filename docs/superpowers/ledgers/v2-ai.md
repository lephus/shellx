# V2 AI — execution ledger (branch shellx-v2)

## V2-1a (foundation) — planning rulings

Plan: `docs/superpowers/plans/2026-10-14-v2-ai-foundation.md` (spec `docs/superpowers/specs/2026-10-14-ai-pane-design.md`, approved by the user with "bắt đầu làm đi", 2026-10-14). The user fast-tracks: no separate plan-review stop.

Ruling R1: host code (login env, agent catalog/resolver, process, crash registry, checkpoints, runtime) lives in `package:shellx_ai/host.dart` (pure Dart), not `apps/desktop/lib/src/ai/` — `dart test` with real processes and git on macOS and the Windows CI; the desktop only wires it (V2-1b) — cost if wrong: one move.
Ruling R2: Gemini CLI runs from the pinned npm package `@google/gemini-cli@0.64.0` (bin from its package.json, `--acp`), like the ACP registry, not `gemini` from PATH; OpenCode stays `opencode acp` from PATH — cost if wrong: one catalog entry.
Ruling R3: checkpoints use plumbing (`add -A`, `write-tree`, `commit-tree`, `update-ref`), never `git commit`; every call passes `-c core.autocrlf=false -c core.fsmonitor=false -c commit.gpgSign=false -c gc.auto=0 -c maintenance.auto=false -c core.logAllRefUpdates=false -c core.hooksPath=<shadow>/hooks`; `$GIT_DIR/info/attributes` = `* -text -filter -ident -working-tree-encoding`; inherited `GIT_*` removed — no hook, no GPG, byte-exact restore — cost if wrong: undo off, never the user's repo.
Ruling R4: before every snapshot, nested repositories (untracked entries ending in `/`) and new files over 50 MiB go into the managed `info/exclude` and out of the shadow index — verified 2026-10-14 (git 2.56): with GIT_DIR elsewhere, `git add -A` aborts the whole add on a nested repo without commits — cost if wrong: such files cannot be undone.
Ruling R5: restore writes back files present in the checkpoint with `git restore --source --worktree --pathspec-from-file`, and deletes in Dart the files absent from it plus the folders left empty — cost if wrong: an empty folder stays.
Ruling R6: a remembered "Bypass permissions" mode is never re-applied to a new session (Review Focus 6, never auto-allow) — cost if wrong: one extra click.
Ruling R7: V2-1 splits into V2-1a (pure-Dart foundation, this plan) and V2-1b (desktop tab) — the foundation is testable without Flutter.

## V2-1a — baseline (2026-10-14, before Task 1)
0e71bb6 docs(v2): spec V2-1 — desktop AI tab without a terminal
- Dart SDK version: 3.11.1 (stable) (Tue Feb 24 00:03:07 2026 -0800) on "macos_arm64"
- git version 2.56.0
- v26.11.1
- agents on PATH: claude 
- shellx_core: 341 passing; shellx_agent: 778 passing (dart test, 2026-10-14)

## V2-1a (foundation) — execution

Task 4 (spec §12 checks, run by the controller, 2026-10-14):
- §12.1 Claude recorded (adapter 0.90.0, bin `dist/index.js`, engines node >=22; node v26.11.1). Protocol 1, `loadSession` true, prompt → `end_turn`, hello.txt edited. 57 messages kept (5 `_`-extension messages dropped; `_meta` stripped; project → `/project`; the user's installed plugin/skill commands and plugin agent personas removed). Recording cost $0.26 on the user's own account. Findings:
  - `tool_call` arrives with a generic title ("Read File", "Edit", "Terminal") and empty rawInput; `tool_call_update`s refine title ("Read hello.txt", "ls"), locations, rawInput and the diff — the card must show the merged, updated title.
  - Only Edit asked permission (default mode lets Read and a read-only `ls` run); options were allow-once / allow-with-updates ("Yes, allow all edits during this session") / reject — as in the spec.
  - `usage_update` carries `size` 1 000 000 and a `cost`; `session_info_update` with the title arrives after the turn; the prompt result carries an extra `usage` object (ignored).
  - `configOptions`: mode, model, effort (`thought_level`), fast (`model_config`, a select on/off — not a boolean), agent (no category; lists installed plugin personas).
  - `initialize` also sends `auth.logout`, `providers` (unknown, ignored) and session capabilities list/resume/close/delete/fork/additionalDirectories.
  - `session/load` replays the user message, the finished tool calls (final titles) and the agent text as one chunk; its result repeats `sessionId`, modes and configOptions.
- §12.2 Codex: not installed here — pending manual (spec §9). `@agentclientprotocol/codex-acp@2.2.2`: bin `dist/index.js`, no `engines` field (npm view).
- §12.3 D17 Flutter packages: moved to plan V2-1b.
- §12.4 Gemini CLI without `fs/*`: not installed here — pending manual. `@google/gemini-cli@0.64.0`: bin `bundle/gemini.js`, engines node >=20.
- §12.5 Claude elicitation form for multiple-choice: not observed (the recording asked no question) — pending manual.
- No finding contradicts the spec.

## V2-1b (desktop) — execution

Prerequisite (2026-10-14): `git log --oneline -1` on shellx-v2: `f6a5946 fix(v2-ai): AiHost.startup after a launch does not sweep the agents of this run` (V2-1a Tasks 1–9 landed); apps/desktop `flutter test`: 3091 passing, 10 skipped (`All other tests passed!`).
- Task 1 (D17): flutter_markdown_plus 1.0.12, re_editor 0.10.0, re_highlight 0.0.3, diff_match_patch 0.4.1 resolve and build on Flutter 3.41.4 (macOS debug build ok); re_editor needs autofocus false + showCursorWhenReadOnly false in tests.
- Task 30 (2026-10-14): flutter analyze: `No issues found!`; flutter test: 3248 passing, 10 skipped; flutter build macos --debug: `✓ Built build/macos/Build/Products/Debug/ShellX.app` (the build only rewrites the `COCOAPODS:` version line of `macos/Podfile.lock` with the local CocoaPods 1.17.0; not committed); Windows (`windows-check` or a PC): pending; packages/shellx_acp and packages/shellx_ai untouched by V2-1b: yes (the diff since Task 1 is empty).
- Review greps (§8, D20, D21): `debugPrint(` only `ai_startup.dart` `'ShellX: stopped $stopped stray agent(s)'`, a count; "Claude Code" only `agentNamesClaude` and `aiSettingClaudeDesc`, EN and VI; `hide-claude-auth`: nothing; `answerPermission(` only `ai_permission_bar.dart` (a key or a click).
- ⚠ Manual checks (spec §9): 1 Claude: pending; 2 Codex: pending; 3 Gemini CLI, OpenCode: pending; 4 Telex, VoiceOver, Narrator: pending; 5 large project: pending; 6 proxy, no Node, no Command Line Tools: pending; 7 drop, processes, .cmd shim, run sheet colours, keys stay in the pane: pending.
- Findings that contradict the spec or the rulings B1–B16: none. The landed V2-1a against its plan: `AiRuntime.start` checks the folder with async `Directory(cwd).exists()` (the plan had `existsSync`), real IO that never completes under a widget test's fake clock; `test/support/ai_fakes.dart` (Task 10) answers that check from `existsSync()` in the test's zone, for the fake runtimes' folders only. Nothing else needed a change: the desktop code compiled against the landed API as the plan wrote it.

V2-1a results (2026-10-14, subagent-driven; each task reviewed, fix rounds re-reviewed):
- Task 1 JSON-RPC 38ded65 · Task 2 ACP types + schema conformance a19bab7..c598566 · Task 3 AcpClient + fake agent ba7c0ef..c55207f · Task 4 recorded Claude session 26e3786..e5097f9 · Task 5 session model d948971 · Task 6 login env/catalog/resolver da8c1ab · Task 7 process/registry 5e04dc8 · Task 8 checkpoints 5d5608f..a802e4b · Task 9 runtime/host ef8272e, f6a5946, b5c5d4f.
- Suites at b5c5d4f: shellx_acp 87, shellx_ai 383, shellx_core 341, shellx_agent 778, shellx_client 113, shellx_e2e 16 (+9 skipped), desktop 3096 → 3253 with V2-1b, mobile 839.
- Review fixes beyond the plan (each with a failing test first): redacted toString pinned for every ACP class by a source scan; the fake agent ends a turn cleanly when the client hangs up mid-question; on Windows an explicit `.cmd`/`.bat` agent is never run; checkpoints clear a stale `index.lock`, never delete `.git` paths, retry a failed git lookup, init with `--template=` (a global template hook cannot veto checkpoints); a resumed tab keeps its `session/load` replay after a sign-in or setup card; Stop clears "needs input"; undo is re-probed after a transient failure; `AiHost.launch` waits for the crash sweep.
- Privacy/safety sweep (Task 10 Step 2): no content logging in either package, no `runInShell`, no `--hide-claude-auth`, the only `PermissionSelected` is the user's own pick, model and protocol libraries are `dart:io`-free.
- Pending manual (spec §9): Windows (CI and a real machine), Codex/Gemini/OpenCode sessions, Telex and screen readers, a ~100 000-file project.

V2-1b results (2026-10-14/15, away mode; patch series of 30 tasks, then reviews):
- Reviews: six cluster reviews (1–9, 10–11, 12–16, 17–19, 20–24, 25–29) → fix wave F1–F3 (parallel worktrees, cherry-picked); final whole-branch review (opus, 0 Critical / 6 Important / 11 Minor) → fix wave G1–G3 + follow-ups G1b, G3 rounds 1–3; every fix round re-reviewed. Ledger: `.superpowers/sdd/2026-10-14-v2-ai-desktop/progress.md`.
- Fixed from the final review: a home folder or disk root is never a default project (and gets no checkpoints / `@` index); a paste with text + picture keeps the text; question cards keep their picks off-screen; "Check again" after installing Node/git/CLI (Windows PATH from the registry); output capped by characters (1 MB line 22.8 s → 5 ms); a session that cannot reopen offers "Start a new session"; quit asks while AI works; stopping an agent kills its leftover children (never ShellX or its ancestors; Windows pid by pid, never `taskkill /T`); restored titles kept; pane-level 1–9/Esc; Time Machine exclusion of the AI data.
- Suites at 39406cb (main): shellx_acp 87, shellx_ai 536, shellx_core 341, shellx_agent 778, shellx_client 113, shellx_e2e 16 (+9 skipped), desktop 3544 (+5 skipped), mobile 839.
- Launch smoke (macOS, isolated profile: bundle id `pro.shellx.desktop.smoketest`, scratch HOME): the app stays up, AI first tab renders (widget tree read over the VM service), no exception.
- Not fixed: M-10 (with the background service on, an AI tab's terminal pane can come back as its own tab after a relaunch — needs a restore-schema change). Out of the AI path, pre-existing: `taskkill /T` in `process_tree.dart` via `pr_status.dart` and `agent_command_runner.dart`.
- Windows CI: branch `windows-check/v2-ai` at 39406cb (result to be read in GitHub Actions). Manual checks of spec §9: all pending.

## V2-2a (phone) — execution

- Tasks 1–11 subagent-driven in worktrees, pair reviews (1+2, 3+4, 5+6, 7+8, 9+10) and a review of Task 11; integrated on `v2-2-int` (shellx-v2 + V2-2) and reviewed whole (opus: 0 Critical / 4 Important / 11 Minor) → fix wave P1 (hub, pushes, resync) + Task 9 rounds; every round re-reviewed. Ledger: `.superpowers/sdd/2026-10-14-v2-2-phone-ai/progress.md`.
- Compatibility matrix (Task 12 Step 2): shellx_core compatibility 3, shellx_client compatibility 2, mux/router 7 — all pass (old phone ↔ new desktop, new phone ↔ old desktop, new window ↔ old service).
- Privacy sweep (Step 3): only error runtimeTypes logged; no config path from phones; answers only from the hub's checked `_answer`, the controller's tap methods and the source's forwarding; `remote` and the client are `dart:io`-free.
- Rulings beyond the spec (spec §13): resync when > 120 items behind; pushes when the watching phone is silent 10 s or leaves, and after 60 s even if the desktop shows the session; question pushes carry no question text; `on_computer` refusal for no-approval options from a phone; D15 starts only never-started runtimes; one re-attach after `unavailable`; a 400 ms settle guard on the phone's permission/question panels and Stop.
- Manual checks of spec §10: all pending (real phone, push on a locked screen, Wi-Fi drop mid-stream, a 500-item session, VoiceOver/TalkBack, Telex).
- Next (spec §11.2, V2-2b): answering on the notification, config changes from the phone, images and the voice composer, undo on the phone, full big cards, session history, AI sessions on the machine list, reconnect after a desktop restart, "You · from the phone" on the desktop.

## V2-2b (phone, part two) — planning rulings

Plan: `docs/superpowers/plans/2026-10-15-v2-2b-phone-ai-more.md` (spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md`, decisions B1–B26). The relay task (Task 7) and the privacy pages (Task 26) live on branch `v2-2b-relay` until the user approves a production deploy.

Ruling R1 (B3): one library-level counter `_nextRequestId` in `session_state.dart`, shared by every `AiSessionState` of the process; never goes back in a run — cost if wrong: ids only grow (no wrap within a run in practice).
Ruling R2 (B2): every `ai.*` message read from the wire keeps the map it came as (an `Expando`, `AiMessage.wire`); `encodeBatch` writes `wire` for AI messages; an unknown `ai.*` kind decodes to `AiRaw`, a malformed known kind is still skipped; keys that are no strings are dropped from a wire map — cost if wrong: one map kept per decoded AI message.
Ruling R3 (B1): a phone may use a V2-2b feature only when the router's `ai` is at least 2 (learned from `session.list.result`) and the window's last listing names it (`f`); the AI session page asks `session.list` once when the protocol is unknown and holds the listing while open — cost if wrong: one round trip more for a page opened from a push.
Ruling R4: a V2-2b request kind the hub does not take yet, or an `AiRaw` with an integer `rid`, is answered `refused` by the hub, and `unavailable` where no window serves AI (slot, background service) — cost if wrong: none, every request still gets one answer.
Ruling R5 (B8): "Deny" is not `.destructive` (options `[.foreground]`), so it is the first non-destructive action, the one an Apple Watch double tap runs; "Allow" is `[.foreground, .authenticationRequired]` — B8's goal (a double tap never allows) wins over its option list — cost if wrong: "Deny" is drawn plain, not red.
Ruling R6 (B10): the action title of "Đã cho phép: <việc>" comes from the push body with the head "Cần bạn trả lời: " or "Needs your answer: " cut off; no new data key (B25) — cost if wrong: a body in other words is shown whole.
Ruling R7 (B10): a push answer waits for the app's lock; it is dropped (nothing sent) when an unlock attempt ends still locked, when the app leaves the foreground before it is sent, or after 2 minutes — cost if wrong: the user answers in the app after a slow unlock.
Ruling R8 (B12): iOS gets `NSPhotoLibraryUsageDescription` (App Store policy, image_picker README) though it is never prompted (`requestFullMetadata: false`) — cost if wrong: one more line in Info.plist.
Ruling R9 (B14): "huỷ"/"cancel" as the last word drops that utterance only; it never clears what was typed — cost if wrong: clearing the field takes a tap.
Ruling R10 (B21): a tap on a machine's AI line opens the one waiting session when exactly one waits, else the AI chooser sheet — cost if wrong: one more tap with several sessions.
Ruling R11 (B21): a second string `machineAiSessions` ("✦ 2 phiên AI") for a line with nobody waiting — cost if wrong: one more string.
Ruling R12 (B19): a phone's revert opens the desktop pane's Changes panel and writes its note there, as the desktop's own revert does — cost if wrong: the panel opens on the computer without a click there.
Ruling R13 (B25): the privacy pages (`web/**`) deploy on merge to `main` like `relay/**`, so they are committed on `v2-2b-relay` — cost if wrong: the pages wait for the relay's go-ahead.
Ruling R14 (B16): an item in full is JSON text cut into slices of at most 36 KiB once JSON-escaped; a slice never splits a surrogate pair — cost if wrong: a few more parts for text full of quotes.
Ruling R15: a phone request of a V2-2b feature fails at once with `unsupported`, sending nothing, when the feature cannot be used (R3) — cost if wrong: none.
Ruling R16 (B11): a phone is offered only the choices `aiTurnsOnNoApproval` does not flag, never a switch named like a no-approval mode; the window checks again when setting (`on_computer`) — cost if wrong: "Bypass permissions" stays a computer-only choice (as B11 wants).
Ruling R17 (B12): image (blob) numbers are the phone's own, kept per phone on the desktop and taken by the prompt — cost if wrong: an upload whose prompt failed is sent again.
Ruling R18 (B13, B19): a path from a phone is used only when it is one the window offers right now, relative, without `..`, at most `kAiMaxPathBytes`; the window checks it again inside the session folder — cost if wrong: a file renamed meanwhile is refused.
Ruling R19 (B12): past 5 images or 20 MiB per phone, the desktop drops that phone's least recently used images instead of refusing the new one (a retried upload uses new numbers); an image over 10 MiB, or alone over 20 MiB, is `too_large` — cost if wrong: an image uploaded long before its prompt is uploaded again.
Ruling R20 (B23): a push sid this app run saw in a listing, which the current listing no longer names, opens the one session with the same `acp`, agent and folder, else the machine page; a sid never seen opens as in V2-2a (the push carries no `acp`) — cost if wrong: such a page shows "closed" with "Mở danh sách phiên".
Ruling R21 (B9): Android re-draws only a push that came with an `ai-` tag (only the relay of Task 7 sets it); through an older relay the push stays as FCM drew it, without buttons, never twice — cost if wrong: Android buttons wait for the relay deploy, like iOS's.
Ruling R22 (B16): "Xem đủ" shows on every open tool card with a body, since the mirror cuts a call's input without a flag — cost if wrong: the button sometimes loads what is already shown.
Ruling R23 (B12, §7): images lost with the channel are uploaded again by the next tap on Send, which then sends the prompt; nothing is uploaded or sent by itself — cost if wrong: the upload starts at the tap, not when the channel returns.

## V2-2b — execution

- Relay B6 (Task 7) on `v2-2b-relay` at `c6cf495`, not deployed: merging it to `main` deploys the relay, so it waits for the user's approval.

Task 26 — finish (2026-10-16, product at `3072513` on `v2-2b`). Ledger of the run: `.superpowers/sdd/2026-10-15-v2-2b-phone-ai-more/progress.md`.

Counts (baseline `14e9eb1`, before Task 1 → final):
- shellx_core 351 → 368; shellx_ai 576 → 642; shellx_agent 916 → 1002; shellx_client 159 → 197.
- apps/desktop 3574 + 10 skipped → 3619 + 6 skipped (= 3615 + 10: the 4 `test/cli/cli_binary_test.dart` tests run once `shellx_e2e` has built `term/target/debug/shellx-term`); run in three batches, 1205 / 1160 + 2 / 1254 + 4.
- apps/mobile 1262 → 1522.
- shellx_e2e 16 + 10 skipped (its relay tests skip without `SHELLX_E2E_RELAY`).
- Analyze: `No issues found!` everywhere; mobile only the pre-existing info (`unnecessary_import`, `test/features/terminal/ime_in_place_edit_test.dart:2:8`).
- Load flake, passed alone: desktop `test/terminal/global_search_test.dart` "stops at 20 per pane and 200 overall" (180 hits in one 8 ms slice).
- Generated files fresh: `intl_utils:generate` (then `dart format` at 120, F12), `build_runner`, desktop `gen-l10n` — `git status` empty.

Commits per task (on `v2-2b` unless said):
- Task 1 `14e9eb1..5500423` · Task 2 `5500423..329dce0` · Task 3 `329dce0..9731353` · Task 4 `9731353..c24fbfa`
- Task 5 `c24fbfa..67093c4` · Task 6 `67093c4..cea0659` · Task 7 `5929cdc..c6cf495` (`v2-2b-relay`) + `cea0659..3156840`
- Task 8 `3156840..f916d83` · Task 9 `f916d83..6dc1d59` · Task 10 `6dc1d59..a4011e0` · F19 `a4011e0..ef867fe`
- Task 11 `ef867fe..6e87a91` · Task 12 `6e87a91..c9036d5` · Task 13 `c9036d5..d36b214` · Task 14 `d36b214..7a06fa0`
- Task 15 `7a06fa0..edf917a` · Task 16 `edf917a..7af32c5` · Task 17 `7af32c5..cee5f53` · Task 18 `cee5f53..30d42fa`
- Task 19 `30d42fa..03fc266` · Task 20 `03fc266..dd7031c` · Task 21 `dd7031c..640141b` · Task 22 `640141b..8ad948d`
- Task 23 `8ad948d..6f11366` · Task 24 `6f11366..7f998a1` · Task 25 `7f998a1..3072513`
- Task 26 `b8d0197` (`v2-2b-relay`, privacy pages) + this ledger commit.

Compatibility matrix (spec criterion 14, Review Focus 2):

| Phone | Computer | What holds | Pinned by | Result |
|---|---|---|---|---|
| V2-2b | V2-2a desktop (router `ai: 1`, listing without `f`) | no V2-2b button, no V2-2b request (`unsupported` at once, nothing sent); V2-2a as before | client `ai_v2b_compat_test.dart`; "unsupported at once, nothing sent" in `ai_requests`, `ai_images`, `ai_history`, `ai_files`, `ai_changes` | pass |
| V2-2b | V2-2b window behind a V2-2a service (`ai: 1`, listing with `f`) | as above | client `ai_v2b_compat_test.dart` ("the router says ai 1 …") | pass |
| V2-2a | V2-2b desktop | the V2-2a decoder (frozen `d8ad686`) reads every listing, header, result (body ignored), skips every new kind | core `ai_messages_v2b_test.dart` (5) + `ai_messages_test.dart` (3, frozen `5e04dc8`) | pass |
| any | V2-2b service without a window | every request, an unknown kind with a `rid` included, gets `unavailable` at once | agent `mux_ai_verbatim_test.dart` | pass |
| V2-2b build | V2-2a desktop (`38a786d` build) | live: list, open, send, answer; no V2-2b button | — | pending manual |
| V2-2a build | V2-2b desktop | live: list, open, send, answer | — | pending manual |

- Runs: core `--plain-name compatibility` 8; agent `mux_ai_verbatim` 7, `mux_ai_edges` 29, `mux_ai_server` 2, `ai_router` 5; client `ai_v2b_compat` 6, `ai_test` 5, and the 5 "unsupported" tests — all pass.

Privacy and safety sweep (spec §6, D12, D13, B25):
- 1 Logs: no content logged. Hits read: `debugPrint` imports (`ai_phone.dart:4`, `ai_undo.dart:1`); `AlertDialog(` (`ai_changes_sheet.dart:423`, `machine_list_page.dart:102`); `push_controller.dart` `_log(step, error)` = `PushController $step error: ${error.runtimeType}`, debug only, literal steps.
- 1 widened to all 76 non-test Dart files V2-2b added or changed: 20 `debugPrint` lines, each a literal + `error.runtimeType`; `NotificationSender`'s `_log` (before V2-2b) logs counts and an API error code. The relay diff adds no log line.
- 2 toString: beyond `'…(…)'` only `PushMessage(agentId, sessionId)` (`b2954b4`, before V2-2b, two ids) and `AiRefused($code)` (V2-2a; V2-2b's `body` not printed).
- 2 widened: `AgentNotification($title, $body, $data)` (before V2-2b; `category`/`tag` not printed; `grep -rn "AgentNotification(" packages apps | grep -i "print\|log"` prints nothing); `AiRequestException($code)` (body never printed, pinned); core `_describe` (before V2, non-AI messages; every `ai.*` message and `AiRaw` print `'$runtimeType(…)'`).
- 3 Answers, only: the `AiControl` interface (`ai_phone_hub.dart:87,90`); the hub's `_answer` after its checks (`:1372,1381,1383,1393`); `_RuntimeControl.answerPermission` (`on_computer` check) and `answerAsk` (`ai_phone.dart:385-402`).
- 3 (phone): the panels' taps → the controller's tap methods (`ai_session_page.dart:533,549` → `ai_session_controller.dart:251,257`); the push answerer's single call (`push_answerer.dart:139`): after the app lock (R7), once per request, only for a button's action id (iOS `actionIdentifier`, Android `selectedNotificationAction`).
- 4 No-approval predicates only in: the config view's filters and refusals (`config_view.dart:217-264`, `:334-363`; the hub calls the refusals, `ai_phone_hub_requests.dart:101,109`); the push choices (`aiPushChoices`, `ai_phone_hub.dart:327`); `_RuntimeControl` `answerPermission`, `setConfig`, `setMode` (`ai_phone.dart:394-433`). `no always option in pushes`.
- 5 Push data: `kind`, `ai_session`; with buttons only `perm`, `allow`, `reject`, `category: ai_perm` and the tag `ai-<sid>-<id>` (`agent_notifications.dart:96-105`); the relay adds `agent_id`.
- 6 flutter_local_notifications behind Android: `AndroidPushActions.start()` returns null off Android (`android_push_actions.dart:161`); the background handler returns off Android (`:218`) and is registered only when `start()` gave an instance (`firebase_push_messaging.dart:32-34`). Other hits unrelated (`SessionEnforcer.initialize`, speech `initialize`).
- 7 `remote and client are io-free`; `remote.dart` transitively too (27 files); `machine_ai.dart` reaches `dart:io` only through the `shellx_core` barrel it imported before V2-2b.

Native builds (builds only, nothing launched):
- `flutter build apk --debug`: `✓ Built build/app/outputs/flutter-apk/app-debug.apk` (Gradle 25.2 s).
- `flutter build ios --simulator --debug --no-codesign`: `✓ Built build/ios/iphonesimulator/Runner.app` (Xcode 25.4 s); `pod install` wrote `COCOAPODS: 1.17.0`, set back to `1.16.2` (its only change).
- `flutter build macos --debug`: `✓ Built build/macos/Build/Products/Debug/ShellX.app`; `macos/Podfile.lock` (`COCOAPODS:` line only) restored. `git status` empty.

Relay end to end (relay 127.0.0.1:18787, fake FCM 18788; account, DBs and logs in a temp folder; each relay stopped by its PID):
- `v2-2b-relay` (`c6cf495`): `npm ci` (pre-existing advisory "1 high severity vulnerability"); `npm test` 24 files / 377 tests pass; `npm run typecheck` clean.
- New relay, `SHELLX_E2E_EXPECT_ACTIONS=1`: `push_e2e_test.dart` 2/2 — data `perm`/`allow`/`reject` (+ `agent_id`), `apns.payload.aps.category` `ai_perm`, `android.notification.tag` `ai-k3f9za--12-41`. First run: the terminal test read `0 giây` for `sleep 1` (load flake, T26-4); re-run 2/2.
- Old relay (`5929cdc` = `shellx-v2`'s, `git archive` + `npm ci`), no flag: 2/2 — the desktop works with the old relay, without buttons.
- Control, old relay with the flag: fails on `apns.payload.aps` = `{sound: default}` (no category), as expected.

Rulings made while executing (id — decision — cost if wrong; full text in the SDD ledger and hand-offs):
- Process: work on `v2-2b` in its own worktree, merged into `shellx-v2` by the top-level controller — one merge step.
- Process: relay (Task 7) and privacy pages (Task 26) on `v2-2b-relay` in its own worktree; never merged or pushed without the user's deploy consent — none.
- Process: each commit ends with the committing model's own Co-Authored-By trailer — cosmetic.
- F19 — on the computer, a config option whose own id names a no-approval mode asks the Bypass question for any non-off value and is never remembered nor re-applied — one extra Bypass question.
- F1 — baseline counts recorded in the SDD ledger, written here by Task 26 — none.
- F2 — Task 4's `MachineAi._feature` shipped with `// ignore: unused_element` until Task 10 — one lint suppression for six tasks.
- F3 (revised) — Task 24 replaced the first test of `ai_phone_hub_v2b_test.dart` by "every kind's feature word is in `AiPhoneHub.offered`" (the plan's removal alone left it asserting nothing) — none.
- F4 — Task 23 matched its `aiRevert` replace block by content (Task 6 had moved helpers out of the file) — none.
- F6 — the plan's `git switch` / `git worktree add/remove` commands replaced by the two worktrees above — none.
- F11 — a format command naming whole directories never commits a file outside the task's Files block — none.
- F12 — after `intl_utils:generate`, the three generated l10n files are formatted at 120 columns so commits hold only new entries — none.
- F13 — Task 7 created `## V2-2b — execution` in this ledger; Task 26 appends under it — none.
- F14 — the live-relay e2e runs on ports 18787/18788 with its DB and fake FCM account outside the repo, the relay stopped by its own PID — none.
- F15 — Task 9's simulator build ran `pod install`; `COCOAPODS: 1.16.2` restored — some CDN traffic.
- F16 — `apps/desktop/test/ai/ai_phone_wiring_test.dart` (missing from Task 8's Files block) pins B7's data, category and tag on both push paths — none.
- F17 — on the phone path, a config option whose own id names a no-approval mode is never offered, whatever its kind; setting it is `on_computer` at the hub and at the window — an option merely named like one (e.g. `bypass_cache`) can only be set on the computer.
- F18 — `AiModesView.toString` pinned by a test — none.
- F20 — an empty config view shows only the sheet's title (no new string) — one empty sheet.
- F21 — a cached full item is reused only for the very `TimelineItem` it was built from (identity and `rev`) — a rebuild on an item replaced without a rev bump.
- F22 — the full-item cache's 60 s life, 4-per-phone cap and drop on `phoneGone` pinned — none.
- F23 — a loaded full question form belongs to its own (ask id, item) and sid; cleared when the page follows its session to a new sid; a late load dropped — the form loads again after a restart.
- F24 — the 4 000-character line cut uses `clipForDisplay` (no split surrogate pair) — none.
- F25 — "Xem đủ" on agent text and thought follows `AiMarkdown`'s own cut — one more file.
- F26 — Task 14's hub test pins `_ask` passing a refusal's code and body through — none.
- F27 — `_Reply.refuse(String code, [body])`: the code is non-nullable — none.
- F28 — history titles cut to 120 characters (spec B17), not 120 bytes (plan); constant `kAiHistoryTitleChars` — one constant to rename back.
- F29 — Task 18's `_UserBubble` keeps Task 13's "Xem đủ" button — none.
- F30 — the hub edges test's empty listing equals `AiListing(features: rig.hub.features)` — none.
- F31 — the history sheet shows its spinner, never "Chưa có phiên nào…", while a load is on its way — none.
- F32 — `MachineAi.uploadImage` stops at a lost channel or a sibling's failure, also for parts waiting out `busy` — none.
- F33 — blob numbers start at a secure-random value per `MachineAi`, then consecutive — none.
- F34 — one message's photos stay within 20 MB (the desktop store's per-phone cap), said in the composer — one string pair.
- F35 — Task 18's build checks (iOS simulator, APK) ran; `COCOAPODS: 1.16.2` kept — download traffic.
- F36 — the phone refuses an `@` query over 200 bytes (`too_large`), matching the hub — none.
- F37 — the desktop's per-folder `@` index is fresh only for the session state that read it at the same last ended turn — an extra index read when two sessions alternate.
- F38 — photos leave the phone without their metadata except an Orientation tag (JPEG, PNG, WebP stripped; GIF unchanged; an unwalkable file refused) — the plan's `requestFullMetadata: false` stripped nothing — ~150 lines; a photo with a broken structure cannot be sent.
- F39 — the composer's image note is cleared when a send starts — none.
- F40 — a first-ever mic permission refusal is said in the note — none.
- F41 — text typed while the mic hears is kept: a user edit ends the listen — a listen ends at the first keystroke.
- F42 — the AI dictation controller stays a second copy beside the terminal's (the plan's stated cost) — two copies to keep in step.
- F43 — the dock's `Watch` follows the dictation through a page signal (signals_flutter's `Watch.didUpdateWidget` re-runs the builder untracked) — one page signal.
- F44 — the machine list's tap that opens the one waiting session carries the route key `ai:<agentId>/<sid>` like every other AI-session open path — none.
- F45 — Task 26's relay runs in the relay worktree; the "old relay" check uses the relay of `5929cdc` extracted with `git archive` into a temporary folder — one `npm ci` download.
- F46 — the privacy pages also say that a photo leaves without its embedded information such as location, capture time or camera model (orientation kept), and that the phone can only point at files inside the session's folder, each path checked again by the computer — two sentences to remove.
- F47 — Android: each AI notification is redrawn under its own id (a hash of its tag, 1 ≤ id < 2^27), untagged and silent, only while FCM's `(tag, 0)` is still showing and the id is free, and FCM's is then cancelled; the background handler is registered only after the plugin started — with the plan's id 0, the plugin's shared PendingIntents let an older notification's button answer the newest request (D13) — the replacement is two steps; a re-delivered push may leave a second, plain notification; a hash collision leaves that push without buttons.
- F48 — B21's "nhả" = the list stops holding the machine's AI listing (`unwatch`); the channel itself stays until it ends — an idle channel per released machine until it ends.
- F49 — the machine-list AI line is not gated by router `ai ≥ 2` / `f` (it uses only V2-2a requests and works with a V2-2a desktop) — a V2-2a desktop's card shows a working AI line.
- F50 — Task 24's client changes test uses the shared `ScriptedDesktop`/`readyAi` instead of a private copy — none.
- T26-1 — the site test's EN fact is `inside the session’s folder` (U+2019), as the page renders it (the markdown turns `'` into `’`); the page source keeps `'` — none.
- T26-2 — desktop counted 3619 + 6 skipped, not 3615 + 10: `cli_binary_test.dart` ran (the `shellx_e2e` run had built `shellx-term`) — none.
- T26-3 — the old relay also ran once with `SHELLX_E2E_EXPECT_ACTIONS=1`, as a control (fails on the missing category) — one run.
- T26-4 — the terminal push test's `0 giây` for `sleep 1` (2 of 4 runs, load average 15–51) taken as a load flake: the duration is floored from the agent's own marker times (`command_tracker.dart:59,68`, `notification_text.dart:62`), code V2-2b did not touch — a real regression there would look the same.

Branch `v2-2b-relay` (no upstream; nothing merged or pushed):
- `c6cf495` feat(relay): category and tag on POST /v1/notifications for AI permission buttons (V2-2b B6).
- `b8d0197` docs(web): privacy — AI sessions on the phone and what their notifications carry (V2-2b B25); site tests 55 → 57 (56 pass, 1 skipped, as before).
- `git diff --stat 5929cdc..v2-2b-relay`: only `relay/**` and `web/**` (8 files).
- Waiting for the user's approval: merging deploys the relay and the website.

⚠ Manual checks (spec §10 first, in its order, then the others; each needs an iPhone with a Profile/Release build with APNs, an Android 13+ phone and a Samsung or Xiaomi, and the Mac):
1. V2-2a push taps (B5): an AI push tapped with the app killed, in the background, in the foreground opens the right session; the in-app banner in the foreground; a cold-start tap opens it exactly once — pending manual.
2. "Từ chối" / "Cho phép" on an iPhone (B8, R5, Task 20) — pending manual:
   - swipe, long press, lock screen; "Cho phép" asks for the phone's unlock, opens the app, sends only after the app's own lock (Face ID);
   - within ≤ 3 s the session page shows "Đã cho phép: <việc>" (criterion 1); a request answered on the computer shows "Yêu cầu này đã được trả lời ở nơi khác." and answers nothing;
   - an Apple Watch double tap must deny (R5);
   - app lock on, cold launch (or resume after > 5 min): cancelling the lock screen's first prompt drops the answer without a word (R7) — check what the user sees and that nothing was sent.
3. Android 13+ and a Samsung or Xiaomi (B9, Task 21) — pending manual:
   - the notification with two buttons replaces the plain one (one, never two); a button unlocks, opens the app and answers;
   - `POST_NOTIFICATIONS` refused; a force-stopped app (no push at all);
   - two AI permission notifications: the older one's "Từ chối" answers that request only (F47); an answered notification goes away;
   - the buttons version shows silently in the shade, no second heads-up (F47); if no AI push ever shows buttons, the plugin may not be registered in FCM's background isolate.
4. The new relay deployed, after the user approves `v2-2b-relay` — pending manual:
   - before the deploy: one real FCM push with `category` and `tag` through the `v2-2b-relay` relay (only a fake FCM was used here);
   - look at the pre-existing `npm ci` advisory ("1 high severity vulnerability").
5. Photos (B12) — pending manual:
   - five HEIC photos from an iPhone reach the agent;
   - criterion 3: five iPhone photos go in ≤ 10 s over Wi-Fi; the agent receives them; the phone shows "5 ảnh";
   - upright and without location: an iPhone photo and an Android camera photo, both portrait (F38 keeps only Orientation; Android not checked in review).
6. The mic in the AI composer in Vietnamese; "gửi" sends (B14, criterion 5) — pending manual:
   - the mic hears and "gửi" sends;
   - the first-ever tap needs a second tap after "Allow" (the OS prompt makes the app `inactive`);
   - "Don't Allow" shows the note (F40).
7. A revert from the phone, and the desktop pane's note "Đã hoàn tác N tệp (từ điện thoại)." (B19, B20, criterion 6); the revert question on a narrow phone (three buttons when files changed after the turn) and the sheet's 44 pt targets; a revert tapped right after a turn ends lists the files that turn changed (F51) — pending manual.
8. Restart ShellX while the phone shows a session: it re-attaches (B22, criterion 11) — pending manual:
   - in ≤ 5 s after the tab returns, with "Đã nối lại sau khi ShellX khởi động lại.";
   - twice: with the background service (it re-lists phones for the new window) and without it;
   - by design: a restart slower than B22's 30 s leaves the page closed with "Mở danh sách phiên".
9. The machine list with 2–3 computers online for 10 minutes (B21, criterion 10): each online computer's AI line in ≤ 3 s; no unusual battery drop; "✦" renders in the device's font; a computer asleep or unreachable gets its line back when online — pending manual.
10. Criterion 2 end to end: a mode or model chosen on the phone changes on the computer in ≤ 2 s; on a device, the refusal toast shows over the "Chế độ và model" sheet — pending manual.
11. Criterion 4: on a large project, `@sr` gives ≤ 8 suggestions in ≤ 1 s — pending manual.
12. Criterion 8 end to end: "Lịch sử phiên" → a past session opens on the computer in a new tab, the computer's selected tab stays selected; the phone shows the replayed history — pending manual.
13. Small-phone layout (375×667, keyboard up): four `@` suggestions, a thumbnail row and a note together; the composer at 320–360 dp with attach, mic, Force stop and Send (possible RenderFlex overflow) — pending manual.
14. The two live rows of the compatibility matrix (list, open, send, answer): a V2-2b phone build against the V2-2a desktop (`38a786d` build), no V2-2b button; a V2-2a phone build against the V2-2b desktop — pending manual.

Next: V2-3 (tools by URL on the desktop).
