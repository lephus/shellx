# Task 18 constraints (verbatim excerpts) — phone: photos and `@` in the AI composer (+ B15 photo texts)

## Spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md` (binding; Vietnamese) — success criteria 3, 4, 14 (lines 33–34, 44); B12, B13, B15 (lines 86–87, 89):

3. **Ảnh.** Chọn tối đa 5 ảnh (thư viện hoặc camera) → hàng ảnh nhỏ → Gửi. Agent trên máy tính nhận ảnh; máy tính hiện ảnh trong tin; điện thoại hiện "2 ảnh". 5 ảnh chụp từ iPhone gửi xong trong ≤ 10 s qua Wi-Fi.
4. **`@` tệp.** Gõ `@sr` → tối đa 8 gợi ý tệp của dự án trong ≤ 1 s; chọn thì thành nhắc tệp như trên máy tính.
14. **Bản cũ.** Điện thoại V2-2b với desktop V2-2a, hoặc cửa sổ V2-2b với dịch vụ nền V2-2a: không hiện nút nào của V2-2b, phần V2-2a chạy như cũ. Điện thoại V2-2a với desktop V2-2b: như cũ. Mọi test hiện có vẫn xanh.

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B12 | Ảnh | `ai.blob {rid, blob, part, parts, mime?, data}` (ĐT → DT; `data` ≤ 48 KiB; `mime` ở phần 0); mỗi phần một `ai.result`; điện thoại để ≤ 4 phần đang bay. Desktop giữ blob theo điện thoại trong bộ nhớ (≤ 5 × 10 MiB, ≤ 20 MiB mỗi điện thoại), bỏ sau 2 phút không dùng, khi điện thoại rời đi, hoặc khi đã gửi. `ai.prompt` thêm `blobs: [id]`: hub kiểm đủ phần, loại ảnh theo byte đầu (PNG/JPEG/GIF/WebP), agent nhận ảnh (`no_images` nếu không), rồi gửi kèm ảnh qua đường base64 ngoài isolate UI của desktop. Mục gương của tin người dùng có `img: n`. **Điện thoại:** `image_picker` 1.2.4, thư viện (tối đa 5) và camera, thu về ≤ 2048 px, JPEG chất lượng 85 (ảnh HEIC đổi sang JPEG). Mất kênh giữa chừng thì gửi lại **ảnh**, không bao giờ tự gửi lại tin. | Ảnh rất lớn bị thu nhỏ còn 2048 px. |
| B13 | Nhắc tệp | `ai.files {sid, rid, q}` → `ai.result {body: {"files": [đường dẫn tương đối]}}` (≤ 8, dùng chỉ mục dự án và bộ so khớp của ô nhập desktop). `ai.prompt` thêm `files: [đường dẫn]`: hub chỉ nhận đường dẫn **nằm trong thư mục của phiên**, có thật, rồi gửi `ResourceLinkBlock` như desktop. Ô nhập điện thoại: gõ `@` hiện gợi ý. | — |
| B15 | Câu quyền | iOS: `NSCameraUsageDescription` mới; câu micro và nhận giọng nói chung cho terminal và AI. Android: không cần quyền mới cho trình chọn ảnh hệ thống; camera dùng intent hệ thống. | — |

## Spec §5 strings (lines 149–150, 156–159); §6 (lines 180, 182–184); §7 (lines 190–191, 195–196); §8 (lines 212–213, 220):

| Khoá | EN | VI |
|---|---|---|
| `aiAttachPhoto` / `aiTakePhoto` | Photo library / Camera | Thư viện ảnh / Chụp ảnh |
| `aiImagesCount` | {n, plural, one{1 image} other{{n} images}} | {n} ảnh |
| `aiImageFailed` | The image wasn't sent. Retry | Ảnh chưa gửi được. Thử lại |
| `aiNoImages` | {agent} doesn't take images. | {agent} không nhận ảnh. |

- Không có đường nào trả lời mà không có một lần chạm của người dùng (D13 giữ nguyên). Nút trên thông báo chỉ mang hai lựa chọn "một lần"; câu trả lời chỉ gửi sau khoá Face ID của app; không gửi lại sau khi mất kênh.
- Đường dẫn từ điện thoại (B13, B19) chỉ là đường dẫn desktop đã đưa và phải nằm trong thư mục phiên; desktop kiểm lại lúc làm.
- Ảnh chỉ nằm trong bộ nhớ desktop tới khi gửi cho agent (B12).
- Không log nội dung; `toString` của mọi tin mới trả `Tên(…)`, có test.

| Tình huống | Hành vi |
|---|---|
| Mất kênh khi đang tải ảnh | Tải lại ảnh khi có kênh; tin chưa gửi vẫn nằm trong ô nhập |
| Desktop V2-2a hoặc dịch vụ nền V2-2a | B1: không hiện tính năng mới |

- **B12:** ghép phần, thiếu phần, sai loại ảnh, vượt cỡ, hết hạn 2 phút, điện thoại rời đi; desktop nhận `ImageBlock` đúng.
- **B13:** đường dẫn ngoài thư mục phiên bị từ chối.
- **App mobile (widget):** từng màn mới, chống chạm 400 ms ở hoàn tác, các trạng thái.

## Plan rulings R8, R15, R18, R19, R23 (plan lines 58, 65, 68, 69, 73):

- **R8 — `NSPhotoLibraryUsageDescription` added** (B12, B15): App Store policy per the image_picker README, though never prompted (`requestFullMetadata: false`). *Cost if wrong:* one unused permission text.
- **R15 — a V2-2b request the computer cannot take fails at once on the phone** (`AiRequestException('unsupported')`, nothing sent). *Cost if wrong:* none.
- **R18 — a path from a phone must be one the window offered** (B13, B19): relative, no `..`, ≤ 1 KiB, and checked again by the window (inside the session folder, there). *Cost if wrong:* a file the phone typed by hand is refused.
- **R19 — the image caps evict, they do not refuse** (B12): past 5 images or 20 MiB per phone, the phone's least recently used images are dropped (an upload retried under new numbers is never blocked for 2 minutes); an image over 10 MiB, or alone over the phone's 20 MiB, is `too_large`. *Cost if wrong:* an image uploaded long before its prompt is uploaded again.
- **R23 — images lost with the channel go again with the next Send** (B12, §7): the text and the images stay in the composer ("Ảnh chưa gửi được. Thử lại"), and one tap on Send uploads them again (new numbers) and then sends the prompt; nothing is uploaded or sent by itself. *Cost if wrong:* the upload starts at the tap instead of when the channel returns.

## Plan Global Constraints: Toolchain, Lock files, Naming, No content in logs, Old peers, Mobile (lines 77–79, 82, 84, 87):

- **Toolchain:** Flutter only via `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter …`; Dart via `~/fvm/versions/3.41.4/bin/dart`. Flutter 3.41.4 / Dart 3.11.1. New packages pinned exactly: `image_picker: 1.2.4`, `flutter_local_notifications: 22.3.2` (Android core-library desugaring `com.android.tools:desugar_jdk_libs:2.1.4`). `firebase_messaging` stays `^16.7.0`.
- **Lock files:** `pubspec.lock` files are git-ignored: never `git add` them. After a macOS desktop build, revert the `COCOAPODS:` line change in `apps/desktop/macos/Podfile.lock`. After an iOS mobile build that adds pods, commit the new pod lines in `apps/mobile/ios/Podfile.lock` with `COCOAPODS: 1.16.2` kept.
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
- Ruling (F29): Task 18 Step 11's `_UserBubble` hint line keeps Task 13's button: `if (shown.cut || item.fullLength != null) ...[_Hint(s.aiCutText), _ViewAll(item.index)],` (the brief's block was written against the pre-Task-13 line).
- Tasks 16–17 (done before this task): `MachineAi.newBlobId()`, `uploadImage(blob, mime, bytes, {onProgress})` (parts of `kAiMaxBlobPartBytes`, ≤ 4 in flight, `busy` retried after 500 ms ×3), `files(sid, query)`, `prompt(sid, text, {blobs, files})` — each through `_feature` (R15: `unsupported` at once, nothing sent, when the computer cannot); the hub takes a prompt whose text is empty when it names blobs; `MirrorText.images` (from `img`).
- V2-2 D13: nothing is sent again by itself — a message that failed on the way is never resent; images go up again only on the user's next tap on Send (R23).
- Ruling (F34, for Task 18, from Task 16's review): the phone keeps one message's images within what the computer holds for a phone (B12: ≤ 20 MiB per phone): `ai_attachments.dart` gets `const int kAiMessageImageBytes = 20 << 20;` (documented as the desktop store's per-phone cap) and `aiTakePicked(picked, {required int room, int bytesLeft = kAiMessageImageBytes})`; a photo that would bring the photos taken past `bytesLeft` is left out with a new `AiImageProblem.total`, worded by a new string pair `aiImagesTooMuch` — EN "One message can carry at most 20 MB of images." / VI "Một tin chỉ mang được tối đa 20 MB ảnh."; the page passes `bytesLeft: kAiMessageImageBytes - <bytes of the images already in the composer>` and maps `total` to that string; a domain test pins it — why: past 20 MiB the store evicts the message's earliest images (ai_blob_store.dart:88-90), their later parts still answer ok, and the prompt fails with a bare `refused` on every retry — plausible with five PNG screenshots (the picker's JPEG quality does not apply to PNG); the existing size text says "This image is over 10 MB", which would be wrong here — cost if wrong: one more string pair, and a photo left out that the computer might have taken.
- Ruling (F35, for Task 18): Step 14's two build checks run (`flutter build ios --simulator --debug --no-codesign` with the `pod install` it triggers, and `flutter build apk --debug`), each the toolchain's own dependency fetch allowed as in F15; neither is a launch; `COCOAPODS:` in `apps/mobile/ios/Podfile.lock` goes back to `1.16.2` and only the new pod's lines stay; any other tracked file a build changes outside the Files block is restored to HEAD and reported; if a build cannot fetch what it needs the implementer reports DONE_WITH_CONCERNS with the evidence and the task stands on its tests (Tasks 20–21 build the same app again) — why: the plan's verification of a new native plugin; top-level "no launches" covers launching, not building — cost if wrong: some CocoaPods/Gradle download traffic and ~4 minutes.
