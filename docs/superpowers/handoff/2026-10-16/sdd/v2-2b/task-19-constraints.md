# Task 19 constraints (verbatim excerpts) — phone: voice in the AI composer (+ B15 mic/speech texts)

## Spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md` (binding; Vietnamese) — success criteria 5, 14 (lines 35, 44); B14, B15 (lines 88–89):

5. **Giọng nói.** Nút micro trong ô nhập AI; nói thì chữ hiện vào ô; nói "gửi" ở cuối thì gửi.
14. **Bản cũ.** Điện thoại V2-2b với desktop V2-2a, hoặc cửa sổ V2-2b với dịch vụ nền V2-2a: không hiện nút nào của V2-2b, phần V2-2a chạy như cũ. Điện thoại V2-2a với desktop V2-2b: như cũ. Mọi test hiện có vẫn xanh.

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B14 | Giọng nói | Nút micro trong ô nhập AI, dùng lại `SpeechInput` và `VoiceCommandParser`: chữ cuối được nối vào ô nhập; từ khoá "gửi"/"send" ở cuối thì gửi. Mất kênh hoặc phiên đóng thì ngừng nghe. Sửa câu xin quyền micro và nhận giọng nói cho khỏi chỉ nhắc terminal. | — |
| B15 | Câu quyền | iOS: `NSCameraUsageDescription` mới; câu micro và nhận giọng nói chung cho terminal và AI. Android: không cần quyền mới cho trình chọn ảnh hệ thống; camera dùng intent hệ thống. | — |

## Spec §6 (lines 180, 184); §8 (line 220):

- Không có đường nào trả lời mà không có một lần chạm của người dùng (D13 giữ nguyên). Nút trên thông báo chỉ mang hai lựa chọn "một lần"; câu trả lời chỉ gửi sau khoá Face ID của app; không gửi lại sau khi mất kênh.
- Không log nội dung; `toString` của mọi tin mới trả `Tên(…)`, có test.

- **App mobile (widget):** từng màn mới, chống chạm 400 ms ở hoàn tác, các trạng thái.

## Plan ruling R9 (plan line 59):

- **R9 — "huỷ"/"cancel" drops that utterance only** (B14): it never clears what was typed in the AI field. *Cost if wrong:* the user clears the field by hand.

## Plan Global Constraints: Naming, No content in logs, Old peers, Mobile (lines 79, 82, 84, 87):

- **Naming:** "Claude" or "Claude Agent", never "Claude Code", in feature names and UI strings.
- **No content in logs (D12, B25):** no prompt, agent text, path, file name, diff, image, URL, header or body in any log; new log lines print only `error.runtimeType`. `toString()` of every new `ai.*` message is `'<Type>(…)'`; of every new body/view/record `'…'` (`with Redacted`) or `'<Name>(…)'`; each pinned by a test. Push data carries only an integer id, two option ids and a tag beyond V2-2a's (B25).
- **Old peers:** a malformed `ai.*` message is skipped and an unknown kind ignored, never dropping the channel; every V2-2b feature is gated by router `ai ≥ 2` AND listing `f` (R3); an older desktop or service never receives a V2-2b request; an older phone ignores `body`, `f`, `src`, `img` and the new header keys.
- **Mobile:** strings in `apps/mobile/lib/l10n/intl_en.arb` and `intl_vi.arb` (same keys; `test/l10n_test.dart` checks), generated with `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart run intl_utils:generate`; routes and DI with `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart run build_runner build --delete-conflicting-outputs`; generated files committed. Colours and type from `context.colors` / `context.typo` only; no looping animation except a spinner while loading and the existing mic pulse. Page width 120 (`apps/mobile/analysis_options.yaml`).

## Controller rulings and cross-task contracts (SDD ledger)

- Ruling (F12): after `dart run intl_utils:generate` in apps/mobile, run `~/fvm/versions/3.41.4/bin/dart format lib/shared/src/l10n.dart lib/shared/src/intl/messages_en.dart lib/shared/src/intl/messages_vi.dart` from apps/mobile so the commit holds only the new entries (the generator writes 80 columns, the committed files are at 120). The generator renumbers its `mN` helpers in messages_en/vi.dart when a string with arguments is added, and build_runner renumbers `_iN` import aliases in `app_router.gr.dart`: generator output, acceptable.
- Ruling (F11): a format command naming whole directories never commits a file outside the task's Files block (restored to HEAD and reported).
- Task 6 contract (H1): `AiSessionController(@factoryParam String agentId, @factoryParam String sid, SessionHolder session, AiDrafts drafts, WorkspaceRegistry registry)` positional in this order; `can(feature)` reads `MachineAi._listing` (kept across a lost channel) — a gated button may show while the channel is down; its request then fails as a lost channel.
- Mobile `flutter analyze` has one pre-existing info (`unnecessary_import`, `test/features/terminal/ime_in_place_edit_test.dart:2:8`) — not a task's finding.
- The mobile iOS `Podfile.lock` keeps `COCOAPODS: 1.16.2` (plan Global Constraints, Lock files); new pod lines a build adds are committed.
- Task 18 (done before this task): `AiComposer(…, note: …)` shows one line above the field (why the last images did not go, a voice problem); the composer's images/suggestions/attach button; the page's `_note`.
