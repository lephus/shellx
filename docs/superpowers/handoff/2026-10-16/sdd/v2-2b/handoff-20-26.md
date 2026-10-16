# Hand-off — V2-2b chunk 4 (Tasks 20–26), stopped at a checkpoint

**Status (final, after the resume at ~15:15): DONE_WITH_CONCERNS.** Tasks 20–26 are complete, the final whole-branch review is complete, and its one fix wave has been re-reviewed. Nothing was pushed or merged.

## Final update — read this first

**Task 26.** Its review was re-run (sonnet). It found one Important item: the privacy sentence "ShellX không lưu ảnh" was not true of the phone, because the picker's copy stays in the cache. That item went into the fix wave (F55). Task 26 is complete.

**Final whole-branch review** (opus): ready to merge **with fixes**. It found three Important items:
1. A session page opened from a cold notification tap never learned what the computer can do.
2. The config sheet could pop the session page.
3. Dictation kept listening under pushed pages.

It also triaged the flagged minors, 10 as fix and 18 as defer. Details: `progress.md`, section "Final whole-branch review".

**Fix wave** (opus, one dispatch): **`v2-2b` `2e35476..b37d1b0`, 14 commits, one fix per commit.** It covers:
- the three Important items;
- the four must-include items: the lone surrogate gives a plain push; the config sheet pops only itself; Allow also checks the option's name; the `Watch(` audit (46 builders in 18 files, one stale case fixed, the delete-account button);
- F55: the picker's file is deleted after its bytes are read;
- the JPEG strip stops at the first EOI;
- an unheld `shellx-rest-` cursor is refused;
- the exact-rid history test, `DartPluginRegistrant` in the Android background handler, the English "1 needs you", the 400 ms guard test, the desktop queued-row test;
- a "Final review and fix wave" block in `docs/superpowers/ledgers/v2-ai.md`.

**Scoped re-review** (opus): 14 of 15 items addressed, with no new breakage.

**Residual, parked by ruling F57:** on Android, a photo picked from the library still leaves image_picker's full-metadata *original* copy in the app cache (`cacheDir/<uuid>/<name>`, written by image_picker_android and never deleted). iOS and the Android camera are covered. **Before deploying `v2-2b-relay`, do one of:**
- delete those UUID folders (after the read or at start-up), in a follow-up on the product branch;
- reword the privacy sentence on `v2-2b-relay`.

Either way, fix the doc comment at `apps/mobile/lib/features/ai/data/image_picker_source.dart:18-20`.

**Also parked** as follow-ups:
- the push's `detail`/`agentName` are not checked for lone surrogates (`ai_phone_hub.dart:983`);
- a list that fails on a channel that stays ready waits for the next channel;
- the DartPluginRegistrant line has no test.

**Final counts** (all green; analyze clean, mobile keeps its one info):

| Package or app | Result |
|---|---|
| shellx_core | 368 |
| shellx_ai | 642 |
| shellx_agent | 1005 |
| shellx_client | 197 |
| shellx_e2e | 16 + 10 skipped |
| apps/desktop | 3621 + 5 skipped |
| apps/mobile | 1535 |
| relay | 377 |
| web site | 57 |

**Integration** (top-level controller):
- **Fix wave:** cherry-pick `2e35476..b37d1b0` (14 commits, in order) onto `int/v2-2b`.
- **Conflict risk:** the only shared-file touches are `apps/mobile/lib/l10n/intl_en.arb` (one plural) and its regenerated `messages_en.dart`/`l10n.dart`, so re-run `intl_utils:generate` + F12 format if they conflict, and `docs/superpowers/ledgers/v2-ai.md` (an append).
- **Relay branch:** unchanged at `b8d0197`. It stays separate and undeployed, with F57's privacy note to resolve first.
- **Branch heads:** `v2-2b` `b37d1b0`, `v2-2b-relay` `b8d0197`; both trees clean.

---

*(The checkpoint text below was written at the 14:35 stop order. Its "What remains" steps 1–3 are now done.)*

**Status at the stop order: PARTIAL.** Tasks 20–25 were complete; Task 26 was committed, but its review had not closed. The final review had not run.

- Plan: `docs/superpowers/plans/2026-10-15-v2-2b-phone-ai-more.md`. Spec (binding): `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md`.
- SDD workspace (git-ignored, keep it): `/Users/richard/Documents/helper/shellx/.superpowers/sdd/2026-10-15-v2-2b-phone-ai-more/`. The ledger `progress.md` there records every dispatch, verdict, ruling and deferred minor. Its last section, "STOP ORDER", gives the exact resume point.

## Where things are

| Branch | Worktree | HEAD | State |
|---|---|---|---|
| `v2-2b` | `/Users/richard/Documents/helper/shellx/.claude/worktrees/v2-2b` | `2e35476` | clean; `14e9eb1..2e35476` = 42 commits (this chunk: `03fc266..2e35476`, 12); origin/v2-2b (the top-level backup) is still 03fc266 |
| `v2-2b-relay` | `/Users/richard/Documents/helper/shellx/.claude/worktrees/v2-2b-relay` | `b8d0197` | clean; `5929cdc..b8d0197` = 2 commits (Task 7 relay `c6cf495`, Task 26 privacy pages `b8d0197`); no upstream; not deployed |

No process of this chunk is running (Task 26 stopped its test relays by PID; ports 18787/18788 free). One read-only reviewer was still running at the order: Task 26's reviewer, agent `a0e1fcf2861a69ea9` (sonnet). It changes nothing; if its verdict is not in `progress.md`, run the Task 26 review again (see "What remains").

## Tasks done in this chunk

| Task | Commits on `v2-2b` | Review |
|---|---|---|
| 20. iOS buttons `ai_perm`; the answer after the app lock (B8, B10) | `03fc266..dd7031c` | opus, clean |
| 21. Android buttons (flutter_local_notifications, background handler) (B9) | `dd7031c..640141b` (`5e09e85`, fix `640141b` F47) | opus; 1 fix round (a Critical: an older notification's button answered the newest request); sonnet re-review clean |
| 22. AI sessions on the machine list (B21) | `640141b..8ad948d` (`bf48669`, `fd48288` D1, fix `8ad948d`) | opus; 1 fix round; sonnet re-review clean |
| 23. Desktop `AiUndo` extracted from the Changes panel (B19) | `8ad948d..6f11366` | opus, clean |
| 24. Changes, diff, revert from the phone; the pane note (B19, R12, R18) | `6f11366..7f998a1` (`10b3fb1`, fix `7f998a1` F50) | opus; 1 fix round (test double); sonnet re-review clean |
| 25. Phone: Changes sheet, diff page, revert (B20) | `7f998a1..3072513` (`875feea`, fix `3072513` F51, F52) | opus; 1 fix round (stale file list in the revert question; copied diff look); sonnet re-review clean |
| 26. Finish: verification, matrix, sweep, privacy pages, ledger | `3072513..2e35476` (ledger); `v2-2b-relay` `c6cf495..b8d0197` (privacy) | review **not closed** (reviewer a0e1fcf2861a69ea9 running at the order) |

**Test totals** (Task 26's final runs, all green):

| Package or app | Result |
|---|---|
| shellx_core | 368 |
| shellx_ai | 642 |
| shellx_agent | 1002 |
| shellx_client | 197 |
| shellx_e2e | 16 passed + 10 skipped; push e2e 2/2 live on the new relay with `SHELLX_E2E_EXPECT_ACTIONS=1`, 2/2 on the old relay without it |
| apps/desktop | 3619 passed + 6 skipped (= 3615 + 10: four `cli_binary` tests ran because the e2e built `shellx-term`) |
| apps/mobile | 1522 |
| relay | 377 tests; typecheck clean |
| web | site tests 57 (56 pass, 1 skipped) |

Also:
- Analyze is clean everywhere. Mobile shows only its one pre-existing info (`unnecessary_import`, `test/features/terminal/ime_in_place_edit_test.dart:2:8`).
- The generated files are fresh.
- The compatibility matrix passes: 8 + 43 + 11 + 5.
- All seven privacy/safety sweeps are clean.
- The APK debug, iOS simulator and macOS debug builds succeed.
- The Podfile.locks are restored, and the mobile one keeps `COCOAPODS: 1.16.2`.

**Load-only flakes** (passed alone or on re-run; none is V2-2b code):
- core `terminal_links_test.dart` "200k-char path";
- shellx_ai `checkpoint_review_test.dart` "too slow";
- desktop `find_bar_test.dart` and `global_search_test.dart:58`;
- e2e `push_e2e_test.dart:140` ("0 giây" for `sleep 1` under load).

**Known test noise** (not findings):
- desktop `ai_phone_test.dart` prints `ShellX: AI session for a phone failed: StateError`;
- desktop `ai_files_refresh_test.dart` prints `ShellX: folder not listed: StateError`;
- mobile machine-list tests print `MachineAiLines error: MachineConnectionException`.

## Rulings made in this chunk (each: decision — cost if wrong)

All rulings F1–F53 are listed one line each in `task-26-rulings.md`; Task 26 also wrote them into the project ledger `docs/superpowers/ledgers/v2-ai.md`. This chunk's:

- **F44:** the machine list's tap that opens the one waiting session carries the route key `ai:<agentId>/<sid>`, like every other AI-session open path. Cost if wrong: none.
- **F45:** Task 26 runs its relay checks in the relay worktree, with no worktree add or remove. The "old relay" is `5929cdc`'s relay, extracted with `git archive` into a temp folder. Cost if wrong: one `npm ci`.
- **F46:** the privacy pages also say two things: a photo leaves without its embedded information (location, capture time, camera model; orientation kept, per F38); and the phone can only point at files inside the session's folder, each checked again by the computer. Cost if wrong: two sentences to remove.
- **F47 (safety):** on Android each AI notification is redrawn under its own id (a stable hash of its tag, 1 ≤ id < 2^27), untagged and silent. It is drawn only while FCM's `(tag, 0)` is still showing and the id is free; FCM's notification is cancelled after. The background handler is registered only after the plugin started.
  - Why: with the plan's id 0, the plugin's shared PendingIntents let an older notification's "Cho phép" allow the newest request.
  - Cost if wrong: the replacement takes two steps; a re-delivered push may leave a second plain notification; a hash collision leaves that push without buttons.
- **F48:** B21's "nhả" means the list stops holding the machine's listing (`unwatch`); the channel stays open until it ends. Cost if wrong: an idle channel per released machine.
- **F49:** the machine-list AI line is not gated by `ai ≥ 2`/`f`. It uses only V2-2a requests, so it works with a V2-2a desktop. Cost if wrong: a V2-2a desktop's card shows a working AI line.
- **F50:** Task 24's client test uses the shared `ScriptedDesktop`/`readyAi`. Cost if wrong: none.
- **F51 (safety):** the phone's revert question is built from the changes read at the tap. The brief's sheet asked with a stale list, so files a just-ended turn changed were reverted unlisted. Cost if wrong: one extra `ai.changes` per revert tap.
- **F52:** the diff page uses the shared diff-line look and the 4 000-character line cut. Cost if wrong: none.
- **F53:** Task 26 changes no product code; failed checks go to the final review's fix wave. Cost if wrong: none.
- **D1 (accepted by review):** the machine list releases its AI lines whenever anything covers it (`ModalRoute.isCurrent`), not only for pages it pushes itself.

## Deferred "likely fix before merge" items (all chunks)

The full list of 151 deferred minors is in `final-review-minors.md`; 29 of them are flagged "FINAL REVIEW".

**Must go into the fix wave whatever the final reviewer says** (top-level order):
1. A lone-surrogate option id makes both relays refuse the push, so the whole push is lost. It should fall back to a plain push.
2. The config sheet keeps its in-flight state per instance, so a reply during the exit animation can pop the session page.
3. Triage, and fix if cheap: the Allow button checks only `optionId`, not the option's name.
4. Triage, and fix if cheap: an audit of the 49 `Watch(` sites in mobile for F43's stale pattern.

**Flagged cheap fixes:**
- Task 5: the queued-row "từ điện thoại" has no desktop dock test (criterion 12).
- Task 14:
  - the history hub tests' `_ask` helper reads the newest result whatever its rid;
  - refuse a stale hub cursor `shellx-rest-<n>` the hub does not hold.
- Task 15: R3 gate pins (`head.history == false`, a listing without `history`).
- Task 18: every upload error, `unsupported` included, says "Thử lại".
- Task 19: a listen keeps running under a pushed page (`AiItemRoute`, the chooser, and now Task 25's diff page and Changes sheet). Call `stop()` before those pushes.
- Task 20: the toast "Đã cho phép: " has a dangling colon for a push without a title.
- Task 22:
  - computers without phone AI are re-probed on every sync;
  - English plurals for `machineAiLine`/`machineAiSessions` ("1 AI sessions · 1 need you");
  - capture `debugPrint` in two tests.
- Task 24: window-level test gaps (`after`, the session scope, the binary/missing/git-failed branches).
- Task 25:
  - test 4 does not pin the 400 ms window (pump ~350 ms first);
  - a raw code "(confirm)" can reach the UI.

**To triage** (security, privacy or protocol):
- F19: `_applyPreferred`'s second guard knows only `bypassPermissions`.
- Task 12: busy pacing during a full-item load; a theoretical splice across a runtime replacement.
- Task 14: `_ask` has no deadline.
- Task 16:
  - `AiBlobStore` records print image bytes in `toString()`;
  - `prompt` after a lost channel names dropped blobs.
- Task 17 and Task 24: the window's path checks follow symlinks (`@` existence check; `diff` reads through a link).
- Task 18: photo bytes outlive the page (thumbnail cache, the picker's temp copies).
- Task 21: no `DartPluginRegistrant.ensureInitialized()` in the background handler. If the engine does not register the plugin's Dart side in FCM's isolate, Android shows no buttons (safe).
- Task 25: the residual revert race is inherent to the protocol. A whole turn run on the computer while the question is open is reverted unlisted for the session scope; closing it needs a protocol change.

## Manual checks (pending, need a person and devices)

The complete, ordered list is `task-26-manual-checks.md` in the SDD workspace; Task 26 copied it into `docs/superpowers/ledgers/v2-ai.md`.

It covers spec §10 1–9, in order, with:
- check 8 run both with and without the background service;
- the cold-start push tap opening the session exactly once;
- the app-lock case of the push answer;
- the Android two-notification check (F47);
- the "✦" glyph;
- the revert question on a narrow phone.

Then the other checks:
- criterion 2 end to end ≤ 2 s, and the refusal toast over the modal config sheet;
- criteria 3, 4, 5 and 8 as hand-off 14–19 lists them;
- photos upright and without location, on an iPhone and an Android camera;
- the small-phone layout;
- one real FCM push with `category` and `tag` before the relay deploy;
- the two live rows of the compatibility matrix.

## Relay branch

`v2-2b-relay` (`b8d0197`) holds:
- Task 7: optional `category` and `tag` on `POST /v1/notifications`;
- Task 26: the privacy pages and the site test.

Scope check: `git diff --stat 5929cdc..v2-2b-relay` lists only `relay/**` and `web/**`. It is waiting for the user's approval to deploy, because merging it to `main` deploys the relay and the website. `main` has moved since (`e74b02f`): rebase it onto the current `main` before merging.

Before deploying:
- send one real FCM push with category and tag;
- look at the pre-existing `npm ci` "1 high severity vulnerability" advisory.

## What remains, in order

1. **Finish Task 26.**
   - If `progress.md` has no verdict from reviewer `a0e1fcf2861a69ea9`, run the Task 26 review again. Use sonnet, the task-reviewer template, both packages (`review-3072513..2e35476.diff` and `review-c6cf495..b8d0197.diff`), and `task-26-constraints.md`, `task-26-manual-checks.md`, `task-26-rulings.md`.
   - Fix what it finds (resume implementer `a81f27ea10f101ba2`, or a fresh opus).
   - Then write `Task 26: complete`.
2. **Final whole-branch review** (opus, `extra/code-reviewer.md` template, the spec and the plan).
   - Ranges: `14e9eb1..HEAD` on `v2-2b` and `5929cdc..HEAD` on `v2-2b-relay`.
   - Read-in-passes packages are ready: `final-00-index.md` (commits, task map, pass order, excluded generated files) and `final-1-core-ai.diff` … `final-8-relay-web.diff`. Regenerate `final-7-docs.diff` and `final-8-relay-web.diff` if Task 26's review changed those files.
   - Point the reviewer at `final-review-minors.md` to triage.
3. **One fix wave** (opus) with the complete findings list plus the four must-include items above. Then:
   - one scoped re-review;
   - adjudicate the residuals and ledger each;
   - append the fix-wave counts to `docs/superpowers/ledgers/v2-ai.md`.
4. **Integration**, by the top-level controller. Merge `v2-2b` into `shellx-v2`; `v2-2b-relay` waits for the deploy approval.
   - Tasks 2–4 must land together (the whole branch does that).
   - **Merge notes** for files V2-3/V2-4 may also touch:
     - **ARBs:** mobile `apps/mobile/lib/l10n/intl_en.arb`/`intl_vi.arb` (10 V2-2b commits add keys) and desktop `apps/desktop/lib/l10n/app_en.arb`/`app_vi.arb` (Tasks 5, 24). After merging the ARBs, regenerate:
       - mobile: `dart run intl_utils:generate`, then F12 (`dart format lib/shared/src/l10n.dart lib/shared/src/intl/messages_en.dart lib/shared/src/intl/messages_vi.dart` at 120 columns);
       - desktop: `flutter gen-l10n`.
     - **`settings_store.dart`:** V2-2b does not touch it, so its key count is unchanged by V2-2b.
     - **Protocol:** `packages/shellx_core/lib/src/protocol/messages.dart` and `ai_messages.dart` (Task 2, `329dce0`: the `fromMap` comment, `encodeBatch` writing `wire`, three `_Fields` helpers). The frozen V2-2a decoders under `test/protocol/frozen/` are generated and byte-identical with V2-2's.
     - **Agent:** `packages/shellx_agent/lib/src/session/session_router.dart` (Task 4, `c24fbfa`: `ai` capability 2); `packages/shellx_agent/lib/shellx_agent.dart` (Task 16, `b3bc42d`: exports `ai_blob_store.dart`). Keep both sides.
     - **Mobile platform files:**
       - `apps/mobile/pubspec.yaml`: `image_picker: 1.2.4` and `flutter_local_notifications: 22.3.2`.
       - `ios/Podfile.lock`: the `image_picker_ios` and `flutter_local_notifications` pod lines, with `COCOAPODS: 1.16.2` kept.
       - `ios/Runner/Info.plist` and `en.lproj`/`vi.lproj` `InfoPlist.strings`: camera, photo library, microphone, speech.
       - New `en.lproj`/`vi.lproj` `Localizable.strings` (registered in `project.pbxproj`).
       - `android/app/build.gradle.kts`: core-library desugaring.
       - `ios/Runner/AppDelegate.swift`: B5's delegate call plus the `ai_perm` category.
     - **Generated:** `dependency.config.dart` and `app_router.gr.dart` (regenerate with build_runner after merging).

## For the user's report

**Spec wording decisions still open:**
- B22: "Đã nối lại sau khi ShellX khởi động lại." also shows when one other tab shares the agent session, though ShellX did not restart. Proposed: "Đã nối lại phiên."
- "từ điện thoại" also marks another paired phone's prompts.
- B5 says "Không thêm flutter_local_notifications trên iOS". The pod is linked there but never initialised (checked inert).
- B9's "cùng tag" is replaced by F47's mechanism; the outcome is kept.
- B21: "nhả" (F48); the machine line for V2-2a desktops (F49); the app lock (an overlay) still holds up to six machines behind the lock screen.
- English "1 AI sessions · 1 need you" needs plurals.

**Behaviour changes against the plan's text:**
- F17/F19: a setting merely named like a no-approval mode is set on the computer only, behind the Bypass question, and never remembered.
- F28: history titles are cut by characters (spec), not bytes (plan).
- F34: a message carries at most 20 MB of photos.
- F38: photos are stripped of metadata on the phone; the plugin did not strip it.
- F47: the Android redraw mechanism.
- F51: the revert question re-reads the file list.

**Spec costs as written:**
- opening the same past session twice gives two tabs;
- no progress is shown while a resume is on its way;
- a history page retried after a lost answer may be refused;
- an Android push keeps FCM's plain notification when the background handler cannot run;
- the residual revert race (see "To triage").
