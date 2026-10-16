# Task 26 constraints (verbatim excerpts) — Finish: full verification, compatibility matrix, privacy sweep, privacy pages, ledger

## Spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md` (binding; Vietnamese) — header (line 4), criterion 14 (line 44), B6, B12, B13, B25 (lines 80, 86, 87, 99):

- **Branch:** `shellx-v2`, đẩy lên `main` sau khi test và review. **Riêng phần relay** nằm ở nhánh `v2-2b-relay` và chỉ gộp vào `main` khi người dùng đồng ý, vì mọi thay đổi `relay/**` trên `main` tự triển khai lên server thật (`.github/workflows/deploy.yml`).

14. **Bản cũ.** Điện thoại V2-2b với desktop V2-2a, hoặc cửa sổ V2-2b với dịch vụ nền V2-2a: không hiện nút nào của V2-2b, phần V2-2a chạy như cũ. Điện thoại V2-2a với desktop V2-2b: như cũ. Mọi test hiện có vẫn xanh.

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B6 | Relay | Thêm hai khoá tuỳ chọn vào `POST /v1/notifications`: `category` (chỉ nhận `ai_perm`) và `tag` (`^[A-Za-z0-9_.:-]{1,64}$`); sai thì 400. FCM: thêm `apns.payload.aps.category` và `android.notification.tag`; **giữ nguyên khối `notification`** (không có tin chỉ-data, không cần bảng khả năng theo máy). Relay cũ bỏ qua hai khoá. Nhánh `v2-2b-relay`, gộp khi người dùng đồng ý triển khai. | Chưa triển khai relay thì thông báo vẫn như cũ, không có nút. |
| B12 | Ảnh | `ai.blob {rid, blob, part, parts, mime?, data}` (ĐT → DT; `data` ≤ 48 KiB; `mime` ở phần 0); mỗi phần một `ai.result`; điện thoại để ≤ 4 phần đang bay. Desktop giữ blob theo điện thoại trong bộ nhớ (≤ 5 × 10 MiB, ≤ 20 MiB mỗi điện thoại), bỏ sau 2 phút không dùng, khi điện thoại rời đi, hoặc khi đã gửi. `ai.prompt` thêm `blobs: [id]`: hub kiểm đủ phần, loại ảnh theo byte đầu (PNG/JPEG/GIF/WebP), agent nhận ảnh (`no_images` nếu không), rồi gửi kèm ảnh qua đường base64 ngoài isolate UI của desktop. Mục gương của tin người dùng có `img: n`. **Điện thoại:** `image_picker` 1.2.4, thư viện (tối đa 5) và camera, thu về ≤ 2048 px, JPEG chất lượng 85 (ảnh HEIC đổi sang JPEG). Mất kênh giữa chừng thì gửi lại **ảnh**, không bao giờ tự gửi lại tin. | Ảnh rất lớn bị thu nhỏ còn 2048 px. |
| B13 | Nhắc tệp | `ai.files {sid, rid, q}` → `ai.result {body: {"files": [đường dẫn tương đối]}}` (≤ 8, dùng chỉ mục dự án và bộ so khớp của ô nhập desktop). `ai.prompt` thêm `files: [đường dẫn]`: hub chỉ nhận đường dẫn **nằm trong thư mục của phiên**, có thật, rồi gửi `ResourceLinkBlock` như desktop. Ô nhập điện thoại: gõ `@` hiện gợi ý. | — |
| B25 | Riêng tư | Không có nội dung mới nào rời kênh mã hoá đầu cuối ngoài: id yêu cầu (số), hai id lựa chọn, một tag (B7). Trang Quyền riêng tư nói rõ thông báo AI mang gì (tên việc dạng rõ như N3; câu hỏi chỉ "<agent> hỏi bạn"; id). Không log nội dung (D12), kể cả ảnh, đường dẫn, diff. | — |

## Spec §6 (lines 178–184), §10 (lines 234–244), §11 (lines 248–252):

## 6. Riêng tư, an ninh và log

- Không có đường nào trả lời mà không có một lần chạm của người dùng (D13 giữ nguyên). Nút trên thông báo chỉ mang hai lựa chọn "một lần"; câu trả lời chỉ gửi sau khoá Face ID của app; không gửi lại sau khi mất kênh.
- Chế độ bỏ qua xin quyền không bao giờ được liệt kê hay đặt từ điện thoại (B11).
- Đường dẫn từ điện thoại (B13, B19) chỉ là đường dẫn desktop đã đưa và phải nằm trong thư mục phiên; desktop kiểm lại lúc làm.
- Ảnh chỉ nằm trong bộ nhớ desktop tới khi gửi cho agent (B12).
- Không log nội dung; `toString` của mọi tin mới trả `Tên(…)`, có test.

## 10. ⚠ Kiểm tay (cần người: iPhone, Android, máy Mac; bản Profile/Release có APNs)

1. **Trước hết (V2-2a):** chạm thông báo AI khi app đã tắt, đang ở nền, đang ở trước: mở đúng phiên (B5). Banner trong app khi app ở trước.
2. Nút "Từ chối"/"Cho phép" trên iPhone (vuốt hoặc nhấn giữ thông báo), màn khoá, Apple Watch (chạm đúp không cho phép).
3. Android 13+ và một máy Samsung/Xiaomi: thông báo có nút thay thông báo thường; chạm nút mở app, trả lời.
4. Relay mới đã triển khai (sau khi người dùng đồng ý B6).
5. Chọn 5 ảnh HEIC từ iPhone: gửi được, agent thấy ảnh.
6. Micro trong ô nhập AI (tiếng Việt), từ khoá "gửi".
7. Hoàn tác một lượt từ điện thoại; pane trên máy tính hiện ghi chú.
8. Khởi động lại ShellX trên máy tính khi điện thoại đang mở phiên: tự nối lại.
9. Danh sách máy với 2–3 máy online: dòng AI, pin không tụt bất thường sau 10 phút mở màn.

## 11. Phạm vi

**Trong V2-2b:** mọi thứ ở §3–§8. Relay ở nhánh riêng tới khi được đồng ý.

**Ngoài V2-2b:** trả lời không cần mở app (chạy nền); tệp tuỳ ý từ điện thoại (PDF…); `@` cho thư mục; hiện tên điện thoại cụ thể ("từ iPhone của …").

## Plan ruling R13 (plan line 63) and Global Constraints: Lock files, Never auto-allow, No content in logs, Relay, Running the apps (plan lines 78, 81, 82, 86, 91):

- **R13 — the privacy pages ship with the relay** (B25): `web/**` on `main` deploys to production like `relay/**` (`.github/workflows/deploy.yml`), so the privacy text is committed on `v2-2b-relay`. *Cost if wrong:* the privacy text lags the desktop release until the user approves the deploy.

- **Lock files:** `pubspec.lock` files are git-ignored: never `git add` them. After a macOS desktop build, revert the `COCOAPODS:` line change in `apps/desktop/macos/Podfile.lock`. After an iOS mobile build that adds pods, commit the new pod lines in `apps/mobile/ios/Podfile.lock` with `COCOAPODS: 1.16.2` kept.
- **Never auto-allow (D13, spec §6):** no path in which a phone answers without a user tap; a notification button is that tap, and its answer goes only after the app's own lock (R7); push buttons offer only the first `allow_once` that turns on no no-approval mode and the first `reject_once` — never `allow_always`/`reject_always`; no answer is ever resent after a lost channel; a no-approval mode is never listed for, nor set from, a phone (R16); a remembered no-approval mode is never re-applied.
- **No content in logs (D12, B25):** no prompt, agent text, path, file name, diff, image, URL, header or body in any log; new log lines print only `error.runtimeType`. `toString()` of every new `ai.*` message is `'<Type>(…)'`; of every new body/view/record `'…'` (`with Redacted`) or `'<Name>(…)'`; each pinned by a test. Push data carries only an integer id, two option ids and a tag beyond V2-2a's (B25).
- **Relay:** only Task 7 touches `relay/**`, on branch `v2-2b-relay`; the privacy pages (`web/**`) go on that branch too (R13). Merging either to `main` is a production deploy — never done by an implementer.
- **Running the apps:** never on the user's real data. Any launch of the desktop app uses a copy with bundle id `pro.shellx.desktop.smoketest` and a temporary home (`CFFIXED_USER_HOME`), as in the session's `scratchpad/smoke/run.sh`.

## Controller rulings that amend the brief (SDD ledger)

- Branches (F6, F45): product and ledger commits on `v2-2b` in `/Users/richard/Documents/helper/shellx/.claude/worktrees/v2-2b`; the privacy pages and their site test on `v2-2b-relay` in `/Users/richard/Documents/helper/shellx/.claude/worktrees/v2-2b-relay` (HEAD `c6cf495`, no upstream). Never `git switch`, never `git worktree add/remove`. The brief's `git switch shellx-v2` means: check that `git -C <v2-2b worktree> branch --show-current` prints `v2-2b`. Relay-branch scope check afterwards: `git -C <relay worktree> diff --stat 5929cdc..v2-2b-relay` lists only `relay/**` and `web/**` files.
- F14 / F45 (relay e2e, Step 6): ports 18787 (relay) / 18788 (fake FCM, `SHELLX_E2E_FAKE_FCM_PORT=18788`); check both ports are free first (`lsof -nP -iTCP:<port> -sTCP:LISTEN`); the fake FCM account written with `npm run fake-fcm-account -- <tmp>/fake-fcm.json`; the relay started directly from `<relay worktree>/relay`: `FCM_SERVICE_ACCOUNT=<tmp>/fake-fcm.json FCM_ENDPOINT=http://127.0.0.1:18788 FCM_TOKEN_ENDPOINT=http://127.0.0.1:18788/token PORT=18787 DB_PATH=<tmp>/relay.db nohup node --env-file=dev.env --import tsx src/server.ts > <tmp>/relay.log 2>&1 &` (PID saved, stopped with `kill <that PID>` only); then from `<v2-2b worktree>/packages/shellx_e2e`: `SHELLX_E2E_RELAY=http://127.0.0.1:18787 SHELLX_E2E_FAKE_FCM_PORT=18788 SHELLX_E2E_EXPECT_ACTIONS=1 ~/fvm/versions/3.41.4/bin/dart test test/push_e2e_test.dart`. The "old relay" run (no `SHELLX_E2E_EXPECT_ACTIONS`): the relay of `5929cdc` (= `shellx-v2`'s and `v2-2b`'s relay) extracted with `git -C <v2-2b worktree> archive 5929cdc relay | tar -x -C <tmp>/old` and `npm ci` there, started the same way from `<tmp>/old/relay` with its own DB path. Nothing is written into either worktree's `relay/` (logs, DBs, accounts all in `<tmp>`).
- F1 / F13 (ledger, Step 8): append under the existing `## V2-2b — execution` heading of `docs/superpowers/ledgers/v2-ai.md` (Task 7 created it; no second heading). Baseline counts (14e9eb1, before Task 1): shellx_core 351, shellx_ai 576, shellx_agent 916, shellx_client 159, apps/desktop 3574 passed + 10 skipped, apps/mobile 1262.
- F28: the code names the history title cap `kAiHistoryTitleChars` (120 characters, spec B17); the plan's `kAiHistoryTitleBytes` / "titles ≤ 120 bytes" do not exist in the code — use the code's names in the sweep and the ledger.
- F46 (privacy pages, beyond the brief's eight edits, both languages): append to the AI-photo bullet of "### Phiên AI trên điện thoại" — VI: "Trước khi gửi, ứng dụng bỏ các thông tin đi kèm trong ảnh, như vị trí, thời gian chụp hay loại máy; chỉ giữ hướng xoay của ảnh." EN (in "### AI sessions on the phone"): "Before sending, the app removes the information embedded in the photo, such as where and when it was taken or the camera model, keeping only its orientation."; and add one bullet after it — VI: "- Điện thoại chỉ nhắc được tệp nằm trong thư mục của phiên; máy tính kiểm lại từng đường dẫn trước khi dùng." EN: "- The phone can only point at files inside the session's folder; the computer checks each path again before using it."; the site test's fact lists gain `'hướng xoay'`, `'thư mục của phiên'` (VI) and `'keeping only its orientation'`, `"inside the session's folder"` (EN).
- Builds (Step 5): APK debug, iOS simulator debug and macOS desktop debug are builds, not launches (never run any app). Afterwards `apps/mobile/ios/Podfile.lock` keeps `COCOAPODS: 1.16.2` and `apps/desktop/macos/Podfile.lock` is restored (`git checkout --` it only if the `COCOAPODS:` line is its sole change).
- Manual checks (Step 8): the list in `task-26-manual-checks.md` replaces the brief's nine-item list (it holds spec §10's nine in order, each with what the reviews attached, then the other checks); every item "pending manual".
- Rulings (Step 8): "any ruling an implementer had to make" = `task-26-rulings.md` (one line each: id — decision — cost if wrong), plus anything this task decides.
- Known test noise and load flakes (not findings of this task): mobile analyze's one info (`unnecessary_import`, `test/features/terminal/ime_in_place_edit_test.dart:2:8`); desktop `ai_phone_test.dart` prints `ShellX: AI session for a phone failed: StateError`, `ai_files_refresh_test.dart` prints `ShellX: folder not listed: StateError`; mobile machine-list tests print `MachineAiLines error: MachineConnectionException`; under machine load, core `terminal_links_test.dart` "200k-char path", shellx_ai `checkpoint_review_test.dart` "too slow" and desktop `find_bar_test.dart` may fail by time and pass alone.
