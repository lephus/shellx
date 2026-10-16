# Hand-off — V2-2b chunk 2 (Tasks 7–13)

**Status: complete.** Tasks 7–13 are implemented, reviewed and closed, plus one extra fix commit for top-level ruling F19. The ledger (`progress.md`, this workspace) records every dispatch, verdict, ruling and deferred minor. Read it before chunk 3.

- Plan: `docs/superpowers/plans/2026-10-15-v2-2b-phone-ai-more.md`.
- Spec: `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md`.
- Worktrees: `MAIN/.claude/worktrees/v2-2b` (branch `v2-2b`) and `MAIN/.claude/worktrees/v2-2b-relay` (branch `v2-2b-relay`).
- This chunk pushed and merged nothing. The top-level controller made backups: origin/v2-2b = a4011e0 and origin/v2-2b-relay.

## Tasks done

| Task | Commits | Review |
|---|---|---|
| 7. Relay `category`/`tag` (B6) | `v2-2b-relay`: 5929cdc..c6cf495 (`c6cf495`). `v2-2b`: cea0659..3156840 (`3156840`, the project-ledger line) | opus, clean |
| 8. A permission push carries its two answers (B7) | 3156840..f916d83 (`f916d83`) | opus, clean (F16 joined one test file) |
| 9. iOS notification delegate set before launch ends (B5) | f916d83..6dc1d59 (`6dc1d59`) | opus, clean |
| 10. Mode and model from the phone (B11, R16); the hub's `_ask` | 6dc1d59..a4011e0 (`fce1616`, fix `a4011e0` for F17 and F18) | opus; 1 fix round; sonnet re-review, clean |
| F19. On the computer, an option named like a no-approval mode asks first and is never remembered | a4011e0..ef867fe (`ef867fe`) | opus, clean |
| 11. Phone: "Chế độ và model" sheet | ef867fe..6e87a91 (`6e87a91`) | sonnet, clean |
| 12. A big item in full, `ai.item` in parts (B16) | 6e87a91..c9036d5 (`3317d91`, fix `c9036d5` for F21 and F22) | opus; 1 fix round; sonnet re-review, clean |
| 13. Phone: "Xem đủ" viewer (B16) | c9036d5..d36b214 (`b92be5e`, fix `d36b214` for F23–F25) | opus; 1 fix round; sonnet re-review, clean |

Commit ranges:
- `v2-2b`: **cea0659..d36b214**, 11 commits.
- `v2-2b-relay`: **5929cdc..c6cf495**, 1 commit. **`v2-2b-relay` head: `c6cf495`.** It is not deployed and has no upstream.

**Final pass** (at d36b214 and c6cf495; every package and app this range touched; all passing):

| Package or app | Result |
|---|---|
| shellx_core | 368 |
| shellx_ai | 622 |
| shellx_agent | 961 |
| shellx_client | 173 |
| shellx_e2e `push_e2e_test` | 2 skipped (no relay) |
| apps/desktop | 3584 passed, 10 skipped |
| apps/mobile | 1318 |
| relay | 24 files / 377 tests; typecheck silent |

Analyze is clean everywhere except mobile's one pre-existing info (`unnecessary_import`, `test/features/terminal/ime_in_place_edit_test.dart:2:8`).

Task 8's two push e2e tests also passed live through Task 7's relay with a fake FCM (F14).

Counts chunk 3 starts from: shellx_core 368, shellx_ai 622, shellx_agent 961, shellx_client 173, desktop 3584 + 10 skipped, mobile 1318.

## Every ruling of this chunk (in order, each with its cost if wrong)

The top-level rulings for chunk 2 are verbatim in the ledger, in the chunk-2 section and in "Chunk 2 resumed". They cover:
- Task 7 runs in the relay worktree.
- Task 8's live e2e.
- No pushes or merges.
- Tasks 8 and 9 use opus.
- F16 and F17 are accepted.
- The relay upstream was unset by the top-level controller.
- F19.

1. **F13:** Task 7 created the `## V2-2b — execution` heading of `docs/superpowers/ledgers/v2-ai.md` on `v2-2b`, with the relay line. Task 26 Step 8 appends under it and must not add a second heading. Cost if wrong: none.
2. **F14:** Task 8's live-relay e2e used ports 18787/18788, put the DB and the fake account under `SCRATCH/v2-2b-e2e/`, and started and stopped the relay by its own PID. Cost if wrong: none.
3. **F15:** Task 9's simulator build ran with its `pod install`. The `COCOAPODS:` line of the mobile `Podfile.lock` was restored afterwards. Cost if wrong: some CocoaPods CDN traffic.
4. **F16:** `apps/desktop/test/ai/ai_phone_wiring_test.dart` was missing from Task 8's Files block and now pins B7's data, category and tag on both push paths. Cost if wrong: none (test only).
5. **F17:** on the phone path, a config option whose own id names a no-approval mode is never offered, whatever its kind. Setting it is `on_computer` at the hub and again at the window. Cost if wrong: an option merely named like one (e.g. `bypass_cache`) can only be set on the computer.
6. **F18:** `AiModesView.toString` is now pinned by a test (Global Constraint). Cost if wrong: none.
7. **F19 (top-level, verbatim in the ledger):** on the computer, such an option asks the Bypass question for any non-off value and is never remembered nor re-applied, whatever its value. It is implemented by widening `aiTurnsOnNoApproval` with a private `_isOff`, plus id checks in `rememberConfig` and `rememberedConfig`. Cost if wrong: one extra Bypass question.
8. **F20:** an empty config view shows only the sheet's title; no new string was added. Cost if wrong: one empty sheet, which the user closes.
9. **F21:** a cached full item is reused only for the very `TimelineItem` it was built from (`identical` and the same `rev`). Spec Review Focus 1 outranks B16's literal cache key. Cost if wrong: a rebuild on an item replaced without a rev bump (CPU only).
10. **F22:** the cache's 60 s life, its 4-per-phone cap and its drop on `phoneGone` are now pinned in `ai_phone_hub_item_test.dart`. Cost if wrong: none.
11. **F23:** a loaded full question form belongs to its own (ask id, item) and sid only. It is cleared when the page follows its session to a new sid, and a late load is dropped. Ask ids restart with each window run. Cost if wrong: the form is loaded again after a restart.
12. **F24:** the 4 000-character line cut uses `clipForDisplay` (new `clipLine`). A raw `substring` could split a surrogate pair, and layout then throws. Cost if wrong: none.
13. **F25:** "Xem đủ" on agent text and thought follows `AiMarkdown`'s own cut (`cutAction`), so the 200-block cut also gets the button. `ai_markdown.dart` joined Task 13. Cost if wrong: one more file.

## What chunk 3 (Tasks 14–19) must know

- **Harness (binding, common brief "Harness note"):**
  - Every dispatch and fix-round message carries its sentence verbatim.
  - When a child has reported interim, wait with a bounded background wait.
- **`offered` now reads:** `{AiFeature.acpHead, AiFeature.pushAnswer, AiFeature.config, AiFeature.item}`.
- **`_ask` and `_feature`:**
  - Every new hub request goes through `_ask` (`ai_phone_hub_requests.dart`).
  - Every new `MachineAi` request goes through `_feature`.
- **Known `_ask` gaps (deferred, Task 10):**
  - `_Reply.refuse` takes a nullable code.
  - Its body branch and `too_big` branch are pinned only by later tasks' own tests.
- **Mobile controller state added in this chunk:**
  - `loadConfig`/`setConfig`/`setMode` (Task 11).
  - `loadFull`, `formOf`, `loadForm` and the one-slot `_form` bound to (ask, item, sid) (Task 13/F23).
  - `AiItemActions({onViewAll, onChanges})`; Task 25 sets `onChanges`.
  - `AiMarkdown.cutAction` (F25).
  - `clipLine` in `ai_text.dart` (F24).
  - `kShownLineChars = 4000`.
- **Generator renumbering:** `intl_utils` renumbers its `mN` helpers in `messages_en/vi.dart` when a string with arguments is added, and `build_runner` renumbers `_iN` aliases in `app_router.gr.dart`. Both are generator output and acceptable; F12 still applies (format the three l10n files after generating).
- **Carried from chunk 1:**
  - H2: run Tasks 14 and 15, Task 18's `client_backend_test` case and Task 24's hub test first.
  - F3 revised (Task 24).
  - H1 contract.
  - F11/F12.

## Findings deferred to the final review

All are in the ledger as `Task N: minor (deferred)`. The ones worth its attention:

- **Task 8:**
  - Likely fix (cheap): an option id with a lone surrogate passes the hub's 1..256-character check but both relays refuse it, so that request's whole push is lost.
  - Security hardening to triage: the Allow button checks only `optionId`, never the option's name.
- **Task 10:**
  - `rememberConfig` throwing after the agent took a choice answers `refused`.
  - `setConfig` without a client answers `ok`.
  - `aiConfigRefusal`'s type guard runs before the id check, so a flagged id with a non-String/bool value gets `refused` instead of `on_computer`.
  - The "before any lookup" placement is unpinned.
- **F19:** defence in depth — `_applyPreferred`'s own guard knows only `mode` = `bypassPermissions` (closed today by the filtered `rememberedConfig`).
- **Task 11:** likely fix (cheap) — the sheet keeps its in-flight state per instance. After a swipe-dismiss a second request can go out; a reply arriving during the exit animation pops the session page.
- **Task 12:**
  - Check the budget arithmetic: a worst-case load of ~115 slices with no pacing on `busy`.
  - Theoretical splice across a runtime replacement in the middle of a load (closing it needs a protocol token).
  - Idle cache entries stay in memory until that phone's next ask.
- **Task 13:**
  - Leaving the item page logs `AI request error: _Left`, which is test-output noise.
  - A loaded form is dropped while `head` is null (safe direction).
  - `changing` has no test.
- **Task 7:** the bad-input table lacks `"t\n"` and a boolean category.
- **Task 9:** documentation — firebase_messaging, not FlutterAppDelegate, becomes the notification centre's delegate.

## For the top-level controller

- **Merge into shellx-v2:**
  - `v2-2b` = shellx-v2@14e9eb1 + chunk 1 (7 commits) + chunk 2 (11 commits, cea0659..d36b214).
  - Shared files changed in this chunk, for merging with V2-3/V2-4:
    - `packages/shellx_agent/lib/src/ai/ai_phone_hub.dart` and `ai_phone_hub_requests.dart` (new part file)
    - `notify/agent_notifications.dart`, `notify/notification_sender.dart`
    - `packages/shellx_core/lib/src/api/shellx_api.dart`
    - `packages/shellx_ai/lib/remote.dart` (exports `no_approval.dart`, `config_view.dart`, `full_view.dart`), `src/remote/no_approval.dart`
    - `packages/shellx_client/lib/src/machine_ai.dart`
    - `apps/desktop/lib/src/ai/ai_phone.dart`, `ai_no_approval.dart`, `ai_agents.dart`
    - `apps/mobile/ios/Runner/AppDelegate.swift`
    - mobile ARB files + generated l10n (Tasks 11, 13)
    - `apps/mobile/lib/core/router/app_router.dart` + `.gr.dart` (`AiItemRoute`)
    - mobile `backend.dart`, `client_backend.dart`, `test/support/fakes.dart`, `ai_session_controller.dart`, `ai_session_page.dart`, `ai_items.dart`, `ai_dock.dart`, `ai_markdown.dart`, `ai_text.dart`, `ai_words.dart`
    - `docs/superpowers/ledgers/v2-ai.md`
- **Relay:** `v2-2b-relay` at `c6cf495` is waiting for the user's deploy consent. For the user's report:
  - Send one real FCM push with a category and a tag; only a fake FCM was used here.
  - Look at the pre-existing `npm ci` "1 high severity vulnerability" advisory.
- **Manual checks to add to Task 26's list:**
  - A cold-start tap on an AI push opens the session exactly once (Task 9 review).
  - The refusal toast shows over the modal config sheet on a real device (Task 11 review).
  - Criterion 2's "≤ 2 s" end to end.
- **For Task 20 (chunk 4):** when it rewrites `AppDelegate.swift`, add one comment line saying firebase_messaging's shared instance becomes the notification centre's delegate, so no later plugin may set `UNUserNotificationCenter.current().delegate`.
- **For the user (spec wording):** F17 + F19 together mean that an agent setting merely named like a no-approval mode is set on the computer only, behind the Bypass question, and never remembered. An off value is set without asking.
