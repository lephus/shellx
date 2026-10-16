# V2-2b final whole-branch review — index

- Product branch `v2-2b`: `14e9eb1..2e35476` (42 commits) in `/Users/richard/Documents/helper/shellx/.claude/worktrees/v2-2b`. `14e9eb1` = `shellx-v2` when the plan was committed (= origin/main `5929cdc` + the plan).
- Relay branch `v2-2b-relay`: `5929cdc..b8d0197` (2 commits: Task 7's relay change, Task 26's privacy pages) in `/Users/richard/Documents/helper/shellx/.claude/worktrees/v2-2b-relay`.

## Commits of v2-2b (oldest last)

```
2e35476 docs(v2-ai): V2-2b ledger — results, compatibility matrix, sweep, relay branch, manual checks
3072513 fix(v2-ai): a phone revert asks with the files it puts back now; the diff page draws the conversation's diff rows
875feea feat(v2-ai): the phone's Changes sheet, a file's diff page, and a revert asked first
7f998a1 test(v2-ai): the phone's changes test uses the shared scripted desktop
10b3fb1 feat(v2-ai): changes, diff and revert from the phone; the computer's pane says it
6f11366 feat(v2-ai): undo of a turn without a widget (AiUndo), the Changes panel on top of it
8ad948d fix(v2-ai): a machine whose AI handshake failed is tried again when it comes back (V2-2b Task 22 review)
fd48288 fix(v2-ai): the machine list lets its AI lines go whenever anything covers it, not only the pages it pushes itself
bf48669 feat(v2-ai): AI sessions on the machine list (at most six machines, only while the list shows)
640141b fix(v2-ai): an Android push button answers only its own request, and goes once tapped (V2-2b F47)
5e09e85 feat(v2-ai): Allow and Deny on an AI permission push on Android (flutter_local_notifications, replaced by tag)
dd7031c feat(v2-ai): Allow and Deny on an AI permission push (iOS), answered once after the app lock
03fc266 fix(v2-ai): the AI mic says a first refusal, keeps what the user types, and follows the dictation (V2-2b F40, F41)
6cd7108 feat(v2-ai): voice in the phone's AI composer
30d42fa fix(v2-ai): photos leave the phone without their metadata; a stale upload note goes with the next Send
d53a05f feat(v2-ai): photos and @ files in the phone's AI composer
cee5f53 fix(v2-ai): a phone's folder index is fresh only for the session that read it (V2-2b F37)
544fe07 feat(v2-ai): @ files from the phone — ai.files, ai.prompt {files} (V2-2b B13)
7af32c5 fix(v2-ai): an image upload ends with a lost channel or a failed part; blob numbers start at their own (V2-2b F32, F33)
b3bc42d feat(v2-ai): images from the phone — ai.blob parts, ai.prompt {blobs} (V2-2b B12)
edf917a fix(v2-ai): the history sheet shows its spinner, never "no earlier sessions", while a load is on its way (V2-2b B17, F31)
c3b662c feat(v2-ai): phone — session history, and a folder for a tab without one (V2-2b B17, B18)
7a06fa0 feat(v2-ai): session history, resume and a folder for a tab without one, from the phone (V2-2b B17, B18)
0dbdbd0 test(v2-ai): the empty listing check follows the features the hub names (V2-2b B17, B18)
d36b214 fix(v2-ai): a loaded question form is its question's alone; a cut line never splits a surrogate pair; Xem đủ follows the markdown's own cut (V2-2b F23, F24, F25)
b92be5e feat(v2-ai): "Xem đủ" on the phone — an item in full on its own page (V2-2b B16)
c9036d5 fix(v2-ai): a kept full item serves only the item it was made of; pin its 60 s and 4-per-phone life (V2-2b F21, F22)
3317d91 feat(v2-ai): a big item in full, slice by slice — ai.item (V2-2b B16)
6e87a91 feat(v2-ai): "Chế độ và model" on the phone (V2-2b B11)
ef867fe fix(v2-ai): on the computer, an option named like a no-approval mode asks the Bypass question and is never remembered (V2-2b F19)
a4011e0 fix(v2-ai): a phone never sees nor sets an option named like a no-approval mode; pin AiModesView.toString (V2-2b B11)
fce1616 feat(v2-ai): mode and model from the phone, never a no-approval choice (V2-2b B11)
6dc1d59 fix(mobile): set the notification delegate before launch ends (V2-2b B5)
f916d83 feat(v2-ai): a permission push carries its two answers and asks for buttons (V2-2b B7)
3156840 docs(v2-ai): V2-2b execution — relay B6 on v2-2b-relay, not deployed
cea0659 feat(v2-ai): the phone finds its AI session again after the computer restarted ShellX, and opens a push of a previous run as the session it is now (B22, B23)
5802157 feat(v2-ai): header keys acp, model, hist and undo; the turns undo knows move to package:shellx_ai (V2-2b §4.2)
67093c4 feat(v2-ai): a prompt says who wrote it — "Bạn · từ điện thoại" on the computer, "từ điện thoại" on the phone (B24)
c24fbfa feat(v2-ai): a phone uses a V2-2b feature only with ai 2 and the listing's f (B1, B4)
9731353 feat(v2-ai): the background service forwards ai.* verbatim (B2)
329dce0 feat(v2-ai): V2-2b ai.* messages, AiRaw and wire maps, ai protocol 2 (B1, B2, B4)
5500423 fix(v2-ai): one request id counter for the whole window run (V2-2b B3)
```

## Task → commits (from the SDD ledger)

- Task 1: complete (commits 14e9eb1..5500423, review clean)
- Task 2: complete (commits 5500423..329dce0, review clean)
- Task 3: complete (commits 329dce0..9731353, review clean)
- Task 4: complete (commits 9731353..c24fbfa, review clean)
- Task 5: complete (commits c24fbfa..67093c4, review clean)
- Task 6: complete (commits 67093c4..cea0659, review clean)
- Task 7: complete (commits 5929cdc..c6cf495 on v2-2b-relay + cea0659..3156840 on v2-2b, review clean)
- Task 8: complete (commits 3156840..f916d83, review clean)
- Task 9: complete (commits f916d83..6dc1d59, review clean)
- Task 10: complete (commits 6dc1d59..a4011e0, review clean after fix round 1)
- Task 11: complete (commits ef867fe..6e87a91, review clean)
- Task 12: complete (commits 6e87a91..c9036d5, review clean after fix round 1)
- Task 13: complete (commits c9036d5..d36b214, review clean after fix round 1)
- Task 14: complete (commits d36b214..7a06fa0, review clean)
- Task 15: complete (commits 7a06fa0..edf917a, review clean after fix round 1)
- Task 16: complete (commits edf917a..7af32c5, review clean after fix round 1)
- Task 17: complete (commits 7af32c5..cee5f53, review clean after fix round 1)
- Task 18: complete (commits cee5f53..30d42fa, review clean after fix round 1)
- Task 19: complete (commits 30d42fa..03fc266, review clean after fix round 1)
- Task 20: complete (commits 03fc266..dd7031c, review clean)
- Task 21: complete (commits dd7031c..640141b, review clean after fix round 1)
- Task 22: complete (commits 640141b..8ad948d, review clean after fix round 1; D1 fd48288 accepted by the review)
- Task 23: complete (commits 8ad948d..6f11366, review clean)
- Task 24: complete (commits 6f11366..7f998a1, review clean after fix round 1)
- Task 25: complete (commits 7f998a1..3072513, review clean after fix round 1)
- F19 (top-level ruling, chunk 2): ef867fe

## Diff files (read in passes, in this order)

1. `final-1-core-ai.diff` — shellx_core (protocol: ai_messages, messages) + shellx_ai (remote bodies, model ids/source, wire). Frozen V2-2a decoders under `packages/shellx_core/test/protocol/frozen/` are generated (excluded).
2. `final-2-agent-e2e.diff` — shellx_agent (hub + `ai_phone_hub_requests.dart`, mux verbatim forwarding, notify/push data, blob store) + shellx_e2e.
3. `final-3-client.diff` — shellx_client (`MachineAi`: capability gate, every request, uploads).
4. `final-4-desktop.diff` — apps/desktop (`ai_phone.dart` window seams, `ai_undo.dart`, reverts note, images, files). Generated `app_localizations*.dart` excluded.
5. `final-5-mobile-lib.diff` — apps/mobile lib + iOS/Android/pubspec (push buttons and answerer, Android redraw, AI session page/controller/dock/sheets, machine list). Generated `l10n.dart`, `messages_*.dart`, `app_router.gr.dart`, `dependency.config.dart` excluded.
6. `final-6-mobile-test.diff` — apps/mobile tests (skim; read the tests of what you judge risky).
7. `final-7-docs.diff` — the project ledger `docs/superpowers/ledgers/v2-ai.md`.
8. `final-8-relay-web.diff` — relay `category`/`tag` and the privacy pages (`v2-2b-relay`).

Generated files (excluded above; Task 26 Step 2 regenerated them and found them fresh): `apps/mobile/lib/shared/src/l10n.dart`, `apps/mobile/lib/shared/src/intl/messages_en.dart`, `apps/mobile/lib/shared/src/intl/messages_vi.dart`, `apps/mobile/lib/core/router/app_router.gr.dart`, `apps/mobile/lib/core/dependency/dependency.config.dart`, `apps/desktop/lib/l10n/app_localizations*.dart`, `packages/shellx_core/test/protocol/frozen/*`.
