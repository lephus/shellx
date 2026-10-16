# Task 20 constraints (verbatim excerpts) — iOS buttons `ai_perm` and the answer after the app lock

## Spec `docs/superpowers/specs/2026-10-15-v2-2b-phone-ai-more-design.md` (binding; Vietnamese) — success criterion 1 (line 31); B5, B8, B10 (lines 79, 82, 84):

1. **Nút trên thông báo.** Thông báo xin quyền có hai nút **"Từ chối"** và **"Cho phép"**. Chạm "Cho phép": mở khoá máy, app mở, qua khoá Face ID của app thì câu trả lời được gửi **đúng một lần**; trang phiên hiện "Đã cho phép: Sửa src/main.ts" trong ≤ 3 s sau khi app mở. Yêu cầu đã được trả lời ở nơi khác hay đã hết: "Yêu cầu này đã được trả lời ở nơi khác." và **không trả lời gì khác**.

| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B5 | Delegate thông báo iOS (sửa lỗi V2-2a) | `AppDelegate.application(_:didFinishLaunchingWithOptions:)` gọi `FLTFirebaseMessagingPlugin.configureNotificationCenterDelegate()` (theo README 16.7.0) và đăng ký category `ai_perm` (B8) ngay tại đó. Không thêm `flutter_local_notifications` trên iOS. | — |
| B8 | Nút trên iOS | Category `ai_perm` đăng ký native trong `AppDelegate`: **"Từ chối"** trước (`.destructive` + `.foreground`), **"Cho phép"** sau (`.foreground` + `.authenticationRequired`). "Từ chối" đứng trước để cú chạm đúp trên Apple Watch không bao giờ cho phép. Tên nút theo ngôn ngữ máy (`Localizable.strings` en/vi). Chạm nút → iOS mở khoá và mở app → `firebase_messaging` đưa `RemoteMessage.actionIdentifier` qua `getInitialMessage()` / `onMessageOpenedApp`. | Một lần mở khoá và chuyển sang app cho mỗi câu trả lời. |
| B10 | Gửi câu trả lời | Chỉ khi app **đã ở trước và đã qua khoá Face ID của app**: kiểm dữ liệu (máy đã ghim, `ai_session`, `perm` là số, lựa chọn là đúng một trong hai id mang theo), gửi **một** `ai.answer` bằng kênh thường, chờ `ai.result`, không bao giờ gửi lại sau khi mất kênh (D13). Rồi mở trang phiên kèm kết quả: `ok` → "Đã cho phép: <việc>" / "Đã từ chối: <việc>"; `stale` → "Yêu cầu này đã được trả lời ở nơi khác."; `not_found` → "Phiên AI này đã đóng trên máy tính."; `on_computer` → "Trả lời yêu cầu này trên máy tính."; mất kênh/hết giờ → "Có thể chưa gửi được. Xem trong phiên." **Trả lời không cần mở app** (chạy nền) là việc sau: không áp được khoá Face ID của app, Android phải chạy isolate riêng với kết nối relay thứ hai. | — |

## Spec §5 strings (lines 151–153), §6 (line 180, 184), §7 (lines 192–194), §8 B10 (line 210), §9 Review Focus 1 (line 226):

| Khoá | EN | VI |
|---|---|---|
| `pushActionAllow` / `pushActionReject` | Allow / Deny | Cho phép / Từ chối |
| `aiPushAllowed` / `aiPushDenied` | Allowed: {title} / Denied: {title} | Đã cho phép: {title} / Đã từ chối: {title} |
| `aiPushMaybeNotSent` | It may not have been sent. Check the session. | Có thể chưa gửi được. Xem trong phiên. |

- Không có đường nào trả lời mà không có một lần chạm của người dùng (D13 giữ nguyên). Nút trên thông báo chỉ mang hai lựa chọn "một lần"; câu trả lời chỉ gửi sau khoá Face ID của app; không gửi lại sau khi mất kênh.
- Không log nội dung; `toString` của mọi tin mới trả `Tên(…)`, có test.

| Tình huống | Hành vi |
|---|---|
| Chạm nút khi yêu cầu đã được trả lời trên máy tính | `stale` → "đã được trả lời ở nơi khác", không trả lời gì |
| Chạm nút sau khi máy tính khởi động lại | sid cũ → B23; không khớp thì mở trang máy, không trả lời |
| Chạm nút khi app đang khoá Face ID | Chờ mở khoá xong mới gửi; huỷ khoá thì không gửi |

- **B10:** dữ liệu push sai bị bỏ; chỉ gửi sau khi mở khoá app; mọi mã kết quả ra đúng câu; không gửi lại.
1. **Câu trả lời trúng nhầm yêu cầu:** runtime đổi trên cùng pane (B3), thông báo cũ chạm muộn, sid của lần chạy trước (B23). Test: mọi đường đều ra `stale` hoặc mở trang, không bao giờ trả lời.

## Plan rulings R5, R6, R7 (plan lines 55–57):

- **R5 — "Deny" is not marked destructive** (B8): Apple Watch's double tap runs the first non-destructive action; with "Từ chối" `[.foreground]` first and "Cho phép" `[.foreground, .authenticationRequired]` second, that is "Từ chối". B8 lists `.destructive` for "Từ chối"; its stated goal ("a Watch double tap never allows") wins. *Cost if wrong:* "Từ chối" is not drawn red.
- **R6 — the push answer's task title comes from the push body** (B10): "Đã cho phép: <việc>" cuts the head "Cần bạn trả lời: " / "Needs your answer: " from the body; no new data key (B25). *Cost if wrong:* a body in another wording shows whole.
- **R7 — a push answer waits for the app lock, and only so long** (B10, §7): sent after the lock is passed; dropped (nothing sent) when an unlock attempt ends still locked, when the app leaves the foreground first, or after 2 minutes. *Cost if wrong:* the user taps again in the session.

## Plan Global Constraints: Lock files, Never auto-allow, No content in logs, Mobile (plan lines 78, 81, 82, 87):

- **Lock files:** `pubspec.lock` files are git-ignored: never `git add` them. After a macOS desktop build, revert the `COCOAPODS:` line change in `apps/desktop/macos/Podfile.lock`. After an iOS mobile build that adds pods, commit the new pod lines in `apps/mobile/ios/Podfile.lock` with `COCOAPODS: 1.16.2` kept.
- **Never auto-allow (D13, spec §6):** no path in which a phone answers without a user tap; a notification button is that tap, and its answer goes only after the app's own lock (R7); push buttons offer only the first `allow_once` that turns on no no-approval mode and the first `reject_once` — never `allow_always`/`reject_always`; no answer is ever resent after a lost channel; a no-approval mode is never listed for, nor set from, a phone (R16); a remembered no-approval mode is never re-applied.
- **No content in logs (D12, B25):** no prompt, agent text, path, file name, diff, image, URL, header or body in any log; new log lines print only `error.runtimeType`. `toString()` of every new `ai.*` message is `'<Type>(…)'`; of every new body/view/record `'…'` (`with Redacted`) or `'<Name>(…)'`; each pinned by a test. Push data carries only an integer id, two option ids and a tag beyond V2-2a's (B25).
- **Mobile:** strings in `apps/mobile/lib/l10n/intl_en.arb` and `intl_vi.arb` (same keys; `test/l10n_test.dart` checks), generated with `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart run intl_utils:generate`; routes and DI with `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart run build_runner build --delete-conflicting-outputs`; generated files committed. Colours and type from `context.colors` / `context.typo` only; no looping animation except a spinner while loading and the existing mic pulse. Page width 120 (`apps/mobile/analysis_options.yaml`).

## Plan Review Focus 1 (plan line 97):

1. **An answer lands on another request** — a pane's runtime replaced (B3), a notification tapped late, a sid from before ShellX restarted (B23). Every path ends `stale` or opens a page; nothing answers another request. [Task 1: "an answer to the old runtime's request is stale; the new request stays asked", "a queued prompt of the old runtime is not the new one's either". Task 6: "a session of the previous run opens as the one session of the same agent session now", "none, or two, of the same agent session now: the machine opens". Task 20: "stale says it was answered elsewhere and sends nothing else", "an old sid gets not_found, then the page: …", "bad data sends nothing: …", "a lost channel is never retried (…)", "a cancelled unlock sends nothing, also when the app is unlocked later".]

## Controller rulings and cross-task contracts (SDD ledger)

- Hand-off 7-13 (Task 9 review, carried to Task 20): when Task 20 rewrites `AppDelegate.swift`, it adds one comment line saying firebase_messaging's shared instance becomes the notification centre's delegate, so no later plugin may set `UNUserNotificationCenter.current().delegate`.
- Ruling (F11): where a brief's format command names whole directories, any file outside the task's Files block that it changes is restored to HEAD and reported, never committed.
- Ruling (F12): after `dart run intl_utils:generate` in apps/mobile, run `~/fvm/versions/3.41.4/bin/dart format lib/shared/src/l10n.dart lib/shared/src/intl/messages_en.dart lib/shared/src/intl/messages_vi.dart` from apps/mobile so the commit holds only the new entries; `intl_utils` may renumber its `mN` helpers when a string with arguments is added (generator output, acceptable).
- The iOS simulator build of Step 11 is a build, not a launch (allowed by the task's own text); after it, `apps/mobile/ios/Podfile.lock` keeps `COCOAPODS: 1.16.2` and gains no other change (this task adds no pod).
- `NotificationOpener.open(PushMessage)` (Task 6, B23) pushes `AiSessionRoute(key: ValueKey('ai:<agentId>/<sid>'), …)`; `AiWords.failure(S s, String code, {bool answer = false, String? agent})` returns `String?` (Task 18 widened it).
- Mobile `flutter analyze` has one pre-existing info (`unnecessary_import`, `test/features/terminal/ime_in_place_edit_test.dart:2:8`) — not this task's finding.
