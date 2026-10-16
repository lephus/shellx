# Hand-off — V2-2b chunk 3 (Tasks 14–19)

**Status: complete.** Tasks 14–19 are implemented, reviewed and closed. The ledger (`progress.md`, this workspace, section "Chunk 3") records every dispatch, verdict, ruling and deferred minor. Read it before chunk 4.

- Plan: `docs/superpowers/plans/2026-10-15-v2-2b-phone-ai-more.md`. Spec: `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md`.
- Worktree `MAIN/.claude/worktrees/v2-2b`, branch `v2-2b`. This chunk pushed and merged nothing; tree clean.
- `v2-2b-relay` was not touched (still `c6cf495`, no upstream, not deployed). No `relay/**`, `web/**` or `deploy/**` change in this chunk.
- The account's usage limit (API 429) stopped this controller once (~20:20–21:20); the Task 15 reviewer was resumed by SendMessage. Nothing was lost.

## Tasks done

| Task | Commits | Review |
|---|---|---|
| 14. Session history, resume, folder for a tab without one (B17, B18) | d36b214..7a06fa0 (`0dbdbd0` test outside the Files block, F30; `7a06fa0`) | opus, clean |
| 15. Phone: "Lịch sử phiên" and "Dùng thư mục này" | 7a06fa0..edf917a (`c3b662c`, fix `edf917a` F31) | sonnet; 1 fix round; sonnet re-review |
| 16. Images from the phone: `ai.blob`, `ai.prompt {blobs}` (B12) | edf917a..7af32c5 (`b3bc42d`, fix `7af32c5` F32, F33) | opus; 1 fix round; sonnet re-review |
| 17. `@` files from the phone: `ai.files`, `ai.prompt {files}` (B13, R18) | 7af32c5..cee5f53 (`544fe07`, fix `cee5f53` F37) | opus; 1 fix round; sonnet re-review |
| 18. Phone: photos and `@` in the AI composer (+ B15 photo texts) | cee5f53..30d42fa (`d53a05f`, fix `30d42fa` F38, F39) | opus; 1 fix round; sonnet re-review |
| 19. Phone: voice in the AI composer (+ B15 mic/speech texts) | 30d42fa..03fc266 (`6cd7108`, fix `03fc266` F40, F41, F43) | sonnet; 1 fix round; sonnet re-review |

Range on `v2-2b`: **d36b214..03fc266**, 12 commits. No task hit the 5-round breaker; nothing was parked at a breaker. Every Important finding was fixed; Minor findings are deferred in the ledger (`- Task N: minor (deferred): …`).

## Final pass (at 03fc266; every package and app this range touched; all passing)

| Package or app | Result |
|---|---|
| shellx_core | 368 (not touched; run for safety) |
| shellx_ai | 632 |
| shellx_agent | 995 |
| shellx_client | 193 |
| apps/desktop | 3595 passed, 10 skipped |
| apps/mobile | 1441 |

`dart analyze` "No issues found!" for core, ai, agent, client, e2e, acp; desktop `flutter analyze` clean; mobile only its one pre-existing info (`unnecessary_import`, `test/features/terminal/ime_in_place_edit_test.dart:2:8`).

Counts chunk 4 starts from: shellx_core 368, shellx_ai 632, shellx_agent 995, shellx_client 193, desktop 3595 + 10 skipped, mobile 1441.

## Every ruling of this chunk (in order; each with its cost if wrong)

Top-level rulings for chunk 3 (verbatim in the ledger): relay/web/deploy changes only in the relay worktree; no launches (builds allowed, F35); mobile `Podfile.lock` keeps `COCOAPODS: 1.16.2`; compaction → PARTIAL hand-off; timeout-only failures re-run once. Later notices: resume after the 429 (Task 15 reviewer resumed), and "Scratch hygiene" (every dispatch after 23:40 carried its sentence).

1. **F26** — Task 14's hub test pins `_ask` passing a refusal's code and body through (`FakeAiControl.failWith = AiRefused(code, body: …)`; mutation-checked). Cost if wrong: none. `_ask`'s `too_big` branch stays unpinned: no V2-2b body encoder can exceed one body.
2. **F27** — `const _Reply.refuse(String this.code, [this.body])` (non-nullable code), as the plan's own Interfaces state. Cost if wrong: none.
3. **F28** — history titles are cut to **120 characters** (code points, "…" included, never splitting a surrogate pair), as spec B17 says, not 120 bytes as the plan's Global Constraints say; constant `kAiHistoryTitleChars` (the plan's `kAiHistoryTitleBytes` does not exist). Cost if wrong: one constant to rename back.
4. **F29** — Task 18's `_UserBubble` hint line keeps Task 13's "Xem đủ" button (`...[_Hint(s.aiCutText), _ViewAll(item.index)]`). Cost if wrong: none.
5. **F30** — `packages/shellx_agent/test/ai/ai_phone_hub_edges_test.dart` (outside Task 14's Files block, own commit `0dbdbd0`): the empty listing's `< 100` bytes pin became "equals `AiListing(features: rig.hub.features)`" — stable as features are added. Cost if wrong: none.
6. **F31** — the history sheet shows its spinner, never "Chưa có phiên nào…", while a load (incl. the `not_ready` retry) is on its way. Cost if wrong: none.
7. **F32** — `MachineAi.uploadImage` stops at a lost channel or a sibling's failure, also for parts waiting out their `busy` back-off (a channel-loss counter); before, the upload could end "ok" for an image the desktop had dropped, and parts went out after a loss with nobody asking (R23, D13). Cost if wrong: none.
8. **F33** — blob numbers start at a secure-random value in [1, 2^30) per `MachineAi`, then consecutive, so a restarted app cannot reuse a number whose whole image the desktop still holds (the prompt would send the previous run's image). Cost if wrong: none.
9. **F34** — one message's photos stay within 20 MiB (the desktop store's per-phone cap): `kAiMessageImageBytes`, `aiTakePicked(…, bytesLeft:)`, new `AiImageProblem.total` and string pair `aiImagesTooMuch` ("One message can carry at most 20 MB of images." / "Một tin chỉ mang được tối đa 20 MB ảnh."). Cost if wrong: one string pair; a photo left out the computer might have taken.
10. **F35** — Task 18's two build checks ran (iOS simulator debug with its `pod install`, APK debug); not launches; `COCOAPODS: 1.16.2` kept. Cost if wrong: download traffic.
11. **F36** — the phone refuses an `@` query over 200 bytes (`too_large`, nothing sent), matching the hub. Cost if wrong: none.
12. **F37** — the desktop's per-folder `@` index is fresh only for the session state that read it at the same last ended turn (two sessions of one folder could share a turn number and be served a stale index). Cost if wrong: an extra index read when two sessions alternate.
13. **F38** — **photos leave the phone without their metadata** except an Orientation tag: `aiWithoutMetadata` (JPEG drops APP1/APP13/COM and puts back a minimal Orientation Exif; PNG drops eXIf/tEXt/iTXt/zTXt/tIME; WebP drops EXIF/XMP and fixes VP8X/RIFF; GIF unchanged; an unwalkable file is refused as `type`). The plan's `requestFullMetadata: false` does not strip anything — image_picker copies EXIF incl. GPS on both platforms. Cost if wrong: ~150 lines; a photo with a broken structure cannot be sent.
14. **F39** — the composer's image note is cleared when a send starts (a stale "Ảnh chưa gửi được. Thử lại" after a send that may have landed invited a resend). Cost if wrong: none.
15. **F40** — a first-ever mic permission refusal is said in the note (the stop caused by the OS prompt no longer drops it). Cost if wrong: none.
16. **F41** — text typed while the mic hears is kept: a user edit ends the listen; nothing later of that listen touches the field or sends (R9). Cost if wrong: a listen ends at the first keystroke.
17. **F42** — the second dictation controller beside the terminal's stays (the plan's stated cost); extracting their shared pure pieces goes to the final review. Cost if wrong: two copies to keep in step.
18. **F43** — the dock's `Watch` now follows the dictation (a page signal `_dictationMade`; signals_flutter's `Watch.didUpdateWidget` re-runs the builder untracked). Cost if wrong: one page signal.

## Findings deferred to the final review

All are in the ledger as `Task N: minor (deferred)`. Nothing was parked at a breaker. **Likely fix before merge (cheap):**
- Task 14: the history hub tests' `_ask` helper reads the newest result whatever its rid (a missing or duplicate answer passes); a stale hub cursor `shellx-rest-<n>` reaches the agent as its own cursor (refuse a `shellx-rest-` cursor the hub does not hold).
- Task 15: R3 gate pins missing (`head.history == false`, a listing without `history`; the chooser's negative gates).
- Task 18: every upload error, `unsupported` included, says "Thử lại" (pass `unsupported` through).
- Task 19: a listen keeps running under a pushed page (`AiItemRoute`, the chooser) — "gửi" could send from under it; `stop()` before those pushes.

**To triage (security/privacy hardening):**
- Task 16: `AiBlobStore.peek`/`take` return a Dart record whose `toString()` prints the image bytes.
- Task 17: the window's existence check follows symlinks (a file swapped for a link after the index read passes; not reachable from the phone alone).
- Task 18: the thumbnail's `imageCache` key keeps the full photo in memory after the page is left; the picker's temp copies (with their original metadata) stay in the app's temp/cache directory.
- Task 19 / cross-cutting: the `Watch` staleness F43 fixed is a library-level hazard (signals_flutter 6.3.1 `Watch.didUpdateWidget` re-runs the builder untracked) — 49 `Watch(` sites in 18 files under `apps/mobile/lib`; a builder whose first read of a signal happens only after a `setState`-only change can go stale; not audited.
- Cross-task: `_ask` has no deadline (a hung agent leaves the phone to its own timeout); `MachineAi.prompt` after a lost channel names blobs the desktop dropped → a bare `refused` (wording).

Earlier chunks' "likely fix before merge" items stand (Task 5 queued-row test, Task 8 lone surrogate, Task 11 sheet state).

## What chunk 4 (Tasks 20–26) must know

- **Harness and scratch:** every dispatch carries the harness-note sentence and the "Scratch hygiene" sentence verbatim (common brief).
- **`offered`** now reads `{acpHead, pushAnswer, config, item, history, folder, blob, files}`; Task 24 adds `changes`, `revert`. The edges test (F30) follows `hub.features` by itself. **F3 revised** (chunk 1) still applies at Task 24: the first test of `ai_phone_hub_v2b_test.dart` becomes "every kind's feature word of `_requests()` is in `AiPhoneHub.offered`".
- **F27:** `_Reply.refuse` takes a non-null `String` — Task 24's calls must pass a code.
- **F28:** the plan text still says `kAiHistoryTitleBytes` / "titles ≤ 120 bytes"; the code has `kAiHistoryTitleChars` (characters). Task 26's compatibility matrix and privacy sweep should use the code's names.
- **Route key:** every `router.replace`/`push` of `AiSessionRoute` that may land on a page of the same route name must carry `key: ValueKey('ai:<agentId>/<sid>')` (auto_route 11.1 only updates a same-named page otherwise; Task 15 found it). Tasks 20 and 22 open sessions from pushes and the machine list.
- **`AiWords.failure(s, code, {answer, agent})`** (Task 18) — Task 20 calls it with `{answer}` only (consistent).
- **Mobile controller/page state added:** `history`/`resume`/`chooseFolder`/`folders` (Task 15); `send(text, {images, files})` keeps Task 6's `_set(_reattached, false)` and reads the sid once; `files(query)`; `upload` signal (Task 18); the page's `_images`, `_mentions`, `_suggestions`, `_note` (cleared at each send, F39), `_dictation`, `_dictationMade` (F43); `AiComposer(images, onAttach, onRemoveImage, upload, suggestions, onSuggestion, note, listening, onMic)`. The page is ~760 lines, `ai_dock.dart` ~910: work carefully.
- **Mobile pubspec** now has `image_picker: 1.2.4`; `ios/Podfile.lock` has the 6 `image_picker_ios` lines with `COCOAPODS: 1.16.2` — Task 21 adds `flutter_local_notifications` the same way. Info.plist/InfoPlist.strings: camera (pairing + AI photos), photo library (new, R8), microphone and speech (terminal + AI sessions).
- **build_runner** prints that `--delete-conflicting-outputs` is removed and ignored (harmless; the plan's Mobile command still works).
- **Generator renumbering:** `intl_utils` renumbers `mN` helpers when a string with arguments is added; F12 still applies.
- **Task 26 privacy pages / sweep:** say what photos carry (F38: no metadata but the orientation), that images stay in the desktop's memory only until sent (B12), and that `@` paths are checked twice (R18).

## For the top-level controller

- **Merge into shellx-v2:** `v2-2b` = shellx-v2@14e9eb1 + chunk 1 (7) + chunk 2 (11) + chunk 3 (12 commits, d36b214..03fc266). Shared files changed in this chunk, for merging with V2-3/V2-4:
  - `packages/shellx_agent/lib/src/ai/ai_phone_hub.dart`, `ai_phone_hub_requests.dart`; new `ai_blob_store.dart` + export in `lib/shellx_agent.dart`; `test/support/ai_rig.dart`; `test/ai/ai_phone_hub_edges_test.dart` (F30).
  - `packages/shellx_ai/lib/remote.dart` (exports `history_view.dart`, `images.dart`), `src/remote/item_codec.dart` (`img`), `src/remote/mirror.dart` (`MirrorText.images`); new `history_view.dart`, `images.dart`.
  - `packages/shellx_client/lib/src/machine_ai.dart` (history/resume/chooseFolder/newBlobId/uploadImage/files/prompt, channel-loss counter); new `test/support/scripted_desktop.dart`.
  - `apps/desktop/lib/src/ai/ai_phone.dart`; `ui/ai/ai_images.dart` (helpers moved to `shellx_ai`, re-exported); new `ai/ai_image_encode.dart`, `ai/ai_phone_files.dart`; new `test/support/ai_phone_rig.dart`.
  - `apps/mobile`: `pubspec.yaml`, `ios/Podfile.lock`, `ios/Runner/Info.plist`, `en.lproj`/`vi.lproj/InfoPlist.strings`, ARB + generated l10n, `core/dependency/dependency.config.dart`, `core/router/app_router.gr.dart` (renumbering only), `core/backend/backend.dart`, `client_backend.dart`, `test/support/fakes.dart`, `features/ai/**` (controller, page, dock, items, words; new attachments, image source, picker source, attach sheet, history sheet, folder chooser, dictation).
- **Relay:** untouched in this chunk (`v2-2b-relay` at `c6cf495`, waiting for the user's deploy consent; earlier notes stand: one real FCM push with category + tag before the deploy; the pre-existing `npm ci` advisory).
- **Manual checks to add to Task 26's list:**
  - Criterion 8 end to end: "Lịch sử phiên" → a past session opens on the computer in a new tab, the computer's current tab unchanged, and the phone shows the replayed history.
  - Criterion 3: five iPhone photos sent within ≤ 10 s over Wi-Fi; the agent receives them; the phone shows "5 ảnh".
  - Photos arrive **upright** without location: an iPhone photo and an Android camera photo taken in portrait (F38 keeps only the Orientation tag; iOS checked by ImageIO in review, Android not).
  - Criterion 4: `@sr` gives ≤ 8 suggestions in ≤ 1 s on a large project.
  - Criterion 5 on device: the mic hears, "gửi" sends; the first-ever mic tap (the OS permission prompt makes the app `inactive`) needs a second tap after "Allow", and "Don't Allow" shows the note (F40).
  - Layout on a small phone (375×667, keyboard up): four `@` suggestions + a thumbnail row + a note, and the composer at 320–360 dp with attach + mic + Force stop + Send (possible RenderFlex overflow).
- **For the user's report:**
  - F38: the plan's "photos without metadata" was not true of the plugin (location went to the computer and the agent); the phone now strips it, keeping only the orientation.
  - F28: history titles follow the spec (120 characters), not the plan (120 bytes).
  - F34: a message carries at most 20 MB of photos (the computer's per-phone memory cap), said in the composer.
  - Spec costs as written: opening the same past session twice gives two tabs (B17); there is no progress shown while a resume is on its way; a history page retried after a lost answer may be refused (start the sheet again).
