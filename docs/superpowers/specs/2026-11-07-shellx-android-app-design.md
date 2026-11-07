# ShellX cho Android (Kotlin) — đặc tả thiết kế

Ngày: 2026-11-07. Dự án 3/3 (thứ tự ở `2026-11-07-shellx-google-sign-in-design.md` §12). Nhãn:
**[người dùng]**, **[người viết]** như các đặc tả trước.

## 1. Ý định và lý do

Người dùng: "build một bản android app cho shellX bằng ngôn ngữ kotline", "tôi muốn tính năng giống hệt bản
IOS đang có", "tôi sẽ đưa lên Google Play cho mọi người" **[người dùng]**. Hôm nay ShellX chỉ có app iPhone
(`shellx-ios/`); app Flutter cũ (có Android) đã bị xoá ở tag `flutter-final`. Người dùng xác nhận 2026-11-07:
"app Flutter xoá hẳn" **[người dùng]**, nên không có người dùng Flutter nào cần chuyển sang.

Thành công (người viết đề xuất, người dùng không phản đối): một người dùng Android cài ShellX từ Google Play,
đăng nhập Google, quét QR ghép với Mac, thấy workspace và agent, trả lời được khi agent cần mà không phải
về máy tính; nhận thông báo "Cần bạn" cùng lúc với iPhone; không lag.

## 2. Mục tiêu

- **G1. Đủ tính năng như app iPhone** trên `develop` ngày 2026-11-07 (danh sách ở mục 6), cộng hai dự án
  cùng đợt: đăng nhập Google (dự án 1, Android không có Apple) và terminal thật (dự án 2) **[người dùng]**.
- **G2. Thông báo "Cần bạn" trên Android** qua Firebase Cloud Messaging, cùng nội dung và cùng lúc với
  iPhone **[người viết, người dùng xác nhận cần sửa relay]**.
- **G3. Phát hành công khai trên Google Play** dưới đúng mục `com.shellx.prod` của app Flutter cũ
  **[người dùng]**.

## 3. Không làm

- Bố cục riêng cho máy tính bảng hay máy gập: chạy bố cục điện thoại là đủ (app iPhone cũng chỉ cho iPhone)
  **[người viết]**.
- Wear OS, Android Auto, widget, phím tắt trên màn chính, trợ lý Google.
- Đăng nhập Apple hay mật khẩu trên Android.
- Phát hành ngoài Google Play (APK tự phân phối). APK chỉ dùng để thử nội bộ.
- Dịch vụ chạy nền (foreground service) giữ kết nối khi app ở nền: thông báo đi qua FCM **[người viết]**.
- Mang dữ liệu của app Flutter cũ sang: bản mới bỏ qua và dọn dữ liệu cũ ở lần mở đầu **[người viết]**.

## 4. Điều tuyệt đối tránh

- Thông báo trên điện thoại và trạng thái trên desktop lệch nhau; lag (mang sang từ đặc tả iPhone).
- Android và iPhone lệch tính năng hay hành vi mà không ai ghi lại (mục 9).
- Hao pin vì giữ kết nối khi app ở nền.
- Cảm giác "app iPhone bê sang": nút Back của hệ thống không chạy đúng, cử chỉ lạ với người dùng Android.

## 5. Ràng buộc

- **Giấy phép**: `shellx-android/` đóng nguồn ("All rights reserved", như `shellx-ios/LICENSE`). Được dùng:
  code của chính nó; code Kotlin của ShellX Link (mục 7.1, MIT); thư viện từ Maven Central / Google Maven
  có giấy phép Apache-2.0, MIT, BSD hoặc giấy phép Bouncy Castle; và các SDK của Google được **liệt kê theo
  tên**, dùng theo điều khoản của Google (Google Play services cho FCM và `googleid`, Firebase, Play In-App
  Updates) **[người viết]**. Không bao giờ GPL, LGPL hay AGPL. **Không** chép hay liên kết code GPL
  (`Sources/`, `Packages/`,
  `ios/`, `cmux-tui/`, `shellx-core/`). Được **dịch** từ `shellx-ios/` (code đóng của chính ShellX). Script
  mới `scripts/shellx/check-android-license.sh`, cùng tinh thần với `check-ios-license.sh`: allowlist thư
  viện theo `group:artifact`, đường dẫn Gradle không được ra ngoài `shellx-android/` và
  `shellx-link/kotlin/`, không có tên công ty upstream của cmux.
- **Google Play** (kiểm lại ngay trước khi phát hành, vì Google đổi hằng năm):
  - target API level Play đang đòi (≥ 36 lúc viết);
  - hỗ trợ trang bộ nhớ 16 KB nếu app có thư viện native (`.so`); ưu tiên thư viện thuần Java / Kotlin;
  - mục "An toàn dữ liệu", chính sách quyền riêng tư, URL xoá tài khoản, "Quyền truy cập ứng dụng" cho người
    duyệt, phân loại nội dung;
  - versionCode lớn hơn mọi bản Flutter đã tải lên; ký bằng khoá upload cũ
    `~/.shellx-release/shellx-upload.jks` (Play App Signing giữ khoá phát hành).
- **minSdk 26** (Android 8.0, như app Flutter cũ) **[người viết]**.
- **Firebase**: dự án `shellxpro` đã có, có app Android `com.shellx.prod`. Cần thêm app `com.shellx.dev`.
- **Phát hành cục bộ**, không CI, như iPhone (quyết định 2026-10-15 của người dùng): ký trên máy này, người
  dùng tự tải AAB lên Play Console.
- **JDK**: dùng JDK đi kèm Android Studio (`/Applications/Android Studio.app/Contents/jbr`) hoặc JDK 17/21;
  máy có sẵn Android SDK tới `android-36`.

## 6. Tính năng phải có: bản đối chiếu với iPhone

Tham chiếu là `shellx-ios/` ở commit chốt lúc lập plan. Mỗi dòng dưới đây có file iPhone tương ứng để dịch
hành vi.

### 6.1 Màn hình và luồng

- **Khởi động**: logo, tên (`ShellX/UI/RootView.swift` chọn màn theo trạng thái tài khoản).
- **Đăng nhập**: một nút "Tiếp tục với Google" (dự án 1). Lỗi: mạng, máy chủ, bị giới hạn tần suất, đang
  dọn dữ liệu; băng "Phiên đã hết hạn" sau 401.
- **Ghép với Mac**: quét QR, dán mã `shellx-link://…`, mở link từ app khác (deep link); xác nhận tên Mac,
  chờ bấm Cho phép trên Mac, xong; trạng thái bị chặn camera và thất bại (`ShellX/UI/Pairing/`,
  `ShellX/UI/Onboarding/FirstMacView.swift`). Mã ghép chỉ giữ trong bộ nhớ; không gì lên mạng trước khi
  người dùng xác nhận.
- **Màn chính** (`ShellX/UI/Workspaces/WorkspaceListScreen.swift`, `WorkspaceListView.swift`): chuông (đếm
  việc cần bạn), `＋` (workspace mới; nhiều Mac thì hỏi Mac nào), Cài đặt. Nhóm: Cần bạn, Đang chạy, Vừa
  xong, Workspace (mỗi Mac một nhóm), rồi "Đã kết thúc · N" gập lại. Kéo xuống để làm mới. Hành động trên
  dòng: đổi tên và đóng workspace; đóng agent; "Xoá khỏi điện thoại này" cho phiên đã mất.
- **Danh sách phiên**: phiên agent ngoài workspace, phiên đã kết thúc (`ShellX/UI/Home/`,
  `ShellX/UI/Workspaces/OtherSessionsView.swift`).
- **Mac của bạn** (`ShellX/UI/Machines/`): đặt mặc định, bỏ ghép (hỏi lại), xoá Mac đã bỏ ghép điện thoại.
- **Màn workspace** (`WorkspaceView.swift`, `WorkspaceScreen.swift`, `PaneChips.swift`): tiêu đề + nhánh git;
  menu đổi tên, Close Tab (hỏi lại), Close Workspace (hỏi lại); hàng chip, vuốt ngang giữa các pane, giữ lâu
  chip để Close Tab; báo khi pane hay workspace bị đóng trên Mac. Pane shell là terminal thật (dự án 2).
- **Chat agent** (`ShellX/UI/Agent/`): các loại mục (văn bản, suy nghĩ gập lại, bước tool, trạng thái); tải
  thêm khi cuộn lên; nút "Tin mới"; Dừng; Buộc dừng (hỏi lại); Đóng agent (hỏi lại); Xoá khỏi điện thoại.
- **Cần bạn** (`ShellX/UI/Pending/`): thẻ xin quyền (Từ chối, Cho phép, menu Luôn cho phép / Mọi tool);
  sheet câu hỏi (danh sách chọn, "Khác…" tự gõ, trả lời bằng giọng nói); sheet plan (Duyệt, chế độ khác,
  Sửa lại có góp ý bắt buộc, Từ chối).
- **Ô soạn** (`ShellX/UI/Composer/`): ô chữ; mic khi ô trống (giữ để nói, thả để gửi, kéo trái để huỷ; chế
  độ chạm khi bật trình đọc màn hình); `＋` chọn ảnh và file (tối đa 5, mỗi file 10 MiB); tiến độ tải lên.
- **Cài đặt** (`ShellX/UI/Settings/`): Mac của bạn; Tài khoản (email, Đăng xuất có hỏi lại, **Xoá tài
  khoản…** của dự án 1); Giao diện (Theo máy / Sáng / Tối); Giọng nói (chọn ngôn ngữ, chỉ hiện khi mic đã
  dùng được); Giới thiệu (phiên bản, "Giấy phép" mở `shellx.pro`).
- **Nhắc cập nhật**: Cập nhật / Để sau, khi mở app và mỗi lần quay lại app; không bao giờ ở bản debug.
- **Thông báo**: `needs_you` (chạm mở trang Cần bạn), `resolved` (gỡ thông báo); không hiện khi app đang mở
  phía trước.
- **Xem thử không cần tài khoản** (ở cả bản phát hành) **[người viết; người dùng chưa trả lời câu hỏi
  này]**:
  - **Vì sao**: người duyệt của Google Play không có Mac, nên chỉ thấy màn ghép.
  - **Ở đâu**: một nút chữ trên màn đăng nhập và trên màn "chưa có Mac".
  - **Mở ra gì**: một Mac giả có workspace, agent và việc cần bạn, là bản dịch của
    `ShellX/Debug/DemoComposition.swift` và `DemoScript.swift`.
  - **Hành vi**: luôn có băng "Demo · Thoát". Không gửi gì lên mạng, không chạm dữ liệu thật.
  - **Dùng lại cho**: screenshot test.
  - **Giống iPhone**: bản iPhone làm cùng tính năng này ở dự án 1 (§6.6).

### 6.2 Luật hành vi phải giữ đúng

Lấy từ `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/` (đường dẫn tương đối dưới đây):

- "Vừa xong": rảnh trong vòng 3 600 s kể từ lúc điện thoại thấy phiên xong (`Home/HomeFocus.swift`); nhận
  biết phiên xong và giữ 2 lần xong mỗi phiên (`Home/SessionFinishDetector.swift`).
- "Đã kết thúc": 43 200 s (12 h) từ lúc kết thúc (`HomeFocus.endedFor`); ẩn theo từng máy
  (`Home/EndedDismissals.swift`); phiên đã mất xoá khỏi máy, giữ 30 ngày (`Home/GoneRemovals.swift`).
- Việc cần bạn gắn vào phiên mới nhất chưa kết thúc cùng Mac, workspace và agent (`HomeFocus.swift`).
- Màn chính sắp lại mỗi 30 s.
- Kết nối lại: chờ 0,5 / 1 / 2 / 4 / 8 / 15 rồi 30 s, mỗi lần ±20 %; về đầu khi nhận `welcome`
  (`Link/ReconnectSchedule.swift`, `Link/MachineConnection.swift`).
- Revision: ≤ hiện tại thì bỏ, kế tiếp thì áp, hụt thì đồng bộ lại toàn bộ (`Link/RevisionGate.swift`).
- Đổi mạng: chờ ổn định 300 ms rồi nối lại (`Link/NetworkChangeFilter.swift`, `MachineHub.networkChanged`).
- Ra nền: 25 s ân hạn rồi đóng phiên; quay lại thì nối lại Mac chưa online (`Link/MachineHub.swift`).
- Quyết định (`Pending/DecisionCenter.swift`): gửi lại một lần khi không có trả lời rồi báo lỗi; mất mạng là
  lỗi ngay, không xếp hàng; "đã xử lý ở nơi khác" hiện 2 s; góp ý tối đa 4 096 byte.
- Giới hạn: chat 16 384 byte (`Home/ComposerValidation.swift`); câu trả lời 1 024 byte
  (`Pending/QuestionDraft.swift`); đính kèm 5 × 10 MiB (`shellx-link/Sources/ShellXLinkCore/ShellXLink.swift`).
- Hẹn giờ: lưu nháp 500 ms; chờ 5 s; thông báo 4 s; "Không có gì cần bạn" 0,7 s; chốt giọng nói 1,5 s / 2 s;
  cache khả năng giọng nói 30 s.

## 7. Thiết kế

### 7.1 Cấu trúc [người viết]

- **`shellx-link/kotlin/`** (MIT, cùng giấy phép với bản Swift): thư viện Kotlin/JVM thuần, không phụ thuộc
  Android.
  - `link-core`: frame JSON (`kotlinx.serialization`), Noise_XX_25519_ChaChaPoly_SHA256 (prologue
    `shellx-link/1`), điều khiển relay, phiên Link.
  - `link-account`: API HTTP của relay (nonce, đăng nhập Google, ghép điện thoại, vé relay, push token,
    đăng xuất, xoá tài khoản).
  - Test chạy trên JVM, đọc chung vector với bản Swift: `shellx-link/vectors/noise_xx.json`,
    `shellx-link/spec/vectors/messages.json`, `pairing.json`, và `terminal.json` (dự án 2).
- **`shellx-android/core`**: module Kotlin/JVM thuần, bản dịch của `ShellXAppCore` (MachineHub, kho phiên và
  workspace theo revision, DecisionCenter, HomeFocus, nháp, lưu cuộc trò chuyện, logic giọng nói, cập nhật).
  Test JVM, không cần máy ảo.
- **`shellx-android/app`**: Jetpack Compose + Material 3, và phần gắn với Android (mục 7.3). Gốc ghép nối
  viết tay (`AppComposition`, như iPhone), không dùng framework DI.
- Thư viện gợi ý: Kotlin coroutines / Flow, OkHttp (HTTP + WebSocket), BouncyCastle (X25519,
  ChaCha20-Poly1305; SHA-256 / HMAC dùng JCA), Compose BOM, Navigation Compose, Lifecycle, DataStore, CameraX
  + ZXing core (đọc QR, thuần Java), `androidx.credentials` + `googleid`, Firebase Messaging, Play In-App
  Updates. Mọi thư viện phải nằm trong allowlist của mục 5.
- App id: `com.shellx.prod` (release, tên "ShellX") và `com.shellx.dev` (debug, tên "ShellX Dev"), cài song
  song như iPhone.

### 7.2 Giao diện [người viết]

- Material 3 với **bảng màu ShellX** lấy từ `shellx-ios/ShellX/Assets.xcassets`: nền sáng `#F2F2F7` / tối
  `#0B0716`, khối `#FFFFFF` / `#17122A`, chủ đạo `#60A5FA`, chữ nhấn `#2563EB` / `#60A5FA`, bong bóng của mình
  `#DBEAFE` / `#24364F`, màu trạng thái (Done, Error, Idle, NeedsYou, Running). Không dùng màu động của
  Android 12. Màu dịu, không nút gradient, *đang chạy* = vàng (gu đã chốt).
- **Cùng cấu trúc và cùng chữ** với iPhone: cùng màn, cùng nhóm, cùng thứ tự, cùng câu chữ (dịch
  `Localizable.xcstrings` sang `strings.xml`, en + vi).
- **Cách tương tác kiểu Android**: thanh trên Material, nút Back hệ thống (kể cả predictive back), bottom
  sheet thay sheet iPhone, hộp thoại cho mọi xác nhận, vuốt dòng để lộ hành động chính và giữ lâu để mở
  menu, kéo để làm mới, hiển thị tràn viền (edge-to-edge).

### 7.3 Thay phần riêng của iPhone

| iPhone (`shellx-ios/`) | Android |
| --- | --- |
| Keychain (`ShellX/Platform/KeychainSecretStore.swift`) | Khoá AES-GCM trong Android Keystore mã hoá token, khoá Noise tĩnh của điện thoại và danh sách Mac; loại khỏi sao lưu |
| APNs (`ShellX/Platform/PushAppDelegate.swift`, `Push/PushRegistration.swift`) | FCM; xin quyền `POST_NOTIFICATIONS` (Android 13+) đúng lúc iPhone xin quyền thông báo |
| `NWPathMonitor` (`ShellX/Platform/NetworkPathWatcher.swift`) | `ConnectivityManager.registerDefaultNetworkCallback` |
| Camera + QR (`QRScannerView.swift`, `CameraAccess.swift`) | CameraX + ZXing; xin quyền camera |
| Deep link `shellx-link` (Info.plist, `onOpenURL`) | intent filter scheme `shellx-link` |
| Nhận giọng nói: hai bộ nhận `ShellX/Voice/AnalyzerTranscriber.swift` (iOS 26+) và `LegacyTranscriber.swift`, chọn bằng `Packages/ShellXAppCore/Sources/ShellXAppCore/Voice/FallbackTranscriber.swift` | `SpeechRecognizer`; ưu tiên nhận trên máy khi có, rơi về bộ nhận thường như `FallbackTranscriber`; danh sách ngôn ngữ từ hệ thống |
| Mic (`AudioCapture.swift`, `AudioLevelMeter.swift`) | mức âm từ `onRmsChanged` của `SpeechRecognizer` |
| Ảnh / file (`AttachMenu.swift`, `AttachmentPreparer.swift`) | Photo Picker và `OpenMultipleDocuments`; kiểm cỡ qua `ContentResolver` |
| Haptics (`.sensoryFeedback`) | `HapticFeedback` của Compose |
| Ở nền (`beginBackgroundTask`) | `ProcessLifecycleOwner`: 25 s ân hạn rồi đóng phiên |
| App Store lookup (`Update/AppStoreRelease.swift`) | Play In-App Updates, luồng "flexible" (Cập nhật / Để sau) |
| Giao diện sáng / tối (`AppAppearance.swift`) | `AppCompatDelegate.setDefaultNightMode` hoặc theme Compose |
| Lưu cuộc trò chuyện (`Storage/ConversationStore.swift`) | file JSON trong `noBackupFilesDir` |
| `UserDefaults` | DataStore |
| Thông báo cho VoiceOver | thông báo cho TalkBack |
| Bảng tạm (`PairingPaste.swift`) | `ClipboardManager` |
| `os.Logger` (`Diagnostics/LatencyLog.swift`) | `android.util.Log`, chỉ tên số đo, không nội dung |

### 7.4 Thông báo qua FCM: sửa relay [người viết]

- `relay/src/v2/notifications.ts` hôm nay chỉ gửi cho token có `apns_topic` (iPhone). Thêm: chọn cả token
  Android (`push_tokens` không có `apns_topic`, thiết bị `platform = 'android'`) và gửi qua FCM HTTP v1.
- `relay/src/push/fcm.ts` phải được **mở rộng**. Hôm nay `PushMessage` bắt buộc có `title` / `body` và
  `send` luôn thêm khối `notification`. Nó cũng không có TTL, collapse key hay ưu tiên riêng cho từng tin
  (`fcm.ts:5-10,143-150`). Thêm một kiểu tin chỉ có dữ liệu với `android.priority`, `ttl` và
  `collapse_key`. Route v1 dùng chung client này (`relay/src/routes/notifications.ts:102-103`) và phải giữ
  nguyên hành vi.
- Tin **chỉ có dữ liệu** (data message): `kind`, `machine_id`, `request_id`, `agent`, `workspace_title`. App
  tự dựng thông báo bằng chuỗi của chính nó (như `loc-key` của iPhone), **không bao giờ** mang nội dung câu
  hỏi hay lệnh của agent (quyết định của người dùng cho iPhone). `needs_you` ưu tiên cao, sống 24 h, khoá
  gộp là `request_id`; `resolved` ưu tiên thường, app gỡ thông báo có tag `request_id`.
- Token FCM hỏng thì xoá như APNs. Trả 503 chỉ khi cả APNs lẫn FCM đều chưa cấu hình.
- App đăng ký token bằng `PUT /v1/devices/me/push-token {token, platform: "android"}` (đã có,
  `relay/src/routes/devices.ts`), xoá khi đăng xuất.
- Mac không phải đổi gì: `ShellXPhonePushForwarder` gửi một lần cho mỗi Mac, relay phân phát.
- Người dùng kiểm `FCM_SERVICE_ACCOUNT` trên VPS (`deploy/README.md` "Push notifications").

### 7.4b Chữ "iPhone" trên Mac [người viết]

Mac đang ghi "Pair iPhone…" (`Sources/ShellX/Remote/UI/PhonePairingSheet.swift:16,90`) và "Forward
notifications to my iPhone" (`Sources/NotificationsPage.swift:136-137`). Chuỗi `pairing.instructions` của
iPhone trích lại tên mục menu đó. Đổi sang chữ chung "điện thoại" / "phone" trong bản desktop 1.8.0 (cùng
bản với đăng nhập Google), sửa luôn chuỗi iPhone trích nó, và làm bước kiểm bản địa hoá theo
`skills/cmux-localization`.

### 7.4c Máy Android giữ thông báo lại [người viết]

Nhiều máy Xiaomi, Oppo, Vivo chặn FCM của app bị vuốt khỏi danh sách gần đây, trừ khi bật tự khởi chạy hoặc
miễn tối ưu pin. Cài đặt › Thông báo trên Android có thêm dòng **"Thông báo đến trễ?"**: hướng dẫn ngắn theo
hãng máy và một nút mở trang cài đặt hệ thống của app. Không xin quyền
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, vì Google Play hạn chế quyền này. Ghi vào file đối chiếu (mục 9) như
một khác biệt chỉ có trên Android.

### 7.5 Đăng nhập và terminal

- Đăng nhập: theo dự án 1 §6.2 và §6.7. Android dùng client "Web" làm `serverClientId`; Android client
  (package + SHA-1) chỉ để Google nhận ra app.
- Terminal: theo dự án 2, viết từ PROTOCOL.md và vector `terminal.json`, dịch hành vi từ bản iPhone; gõ
  tiếng Việt qua bàn phím hệ thống theo dự án 2 §3.6.

## 8. Kiểm thử và phát hành

- **Test JVM** cho `shellx-link/kotlin` (vector chung) và `shellx-android/core` (dịch các test hành vi của
  `ShellXAppCoreTests` cho phần đã dịch).
- **Screenshot test** cho mọi màn, sáng / tối, en / vi, như `ShellXTests/Support/SnapshotWriter.swift`.
- **Máy ảo** chạy với Mac dev tag:
  - cần ảnh điện thoại API 26 (bản thấp nhất app hỗ trợ) và API 36 (mới nhất);
  - SDK hôm nay chỉ có ảnh điện thoại API 29 và ảnh tablet API 35, nên phải tải thêm bằng `sdkmanager`.
- **Máy thật** cho camera, giọng nói, thông báo và bàn phím tiếng Việt.
- **Script**: `shellx-android/scripts/dev.sh` (test core / app / screenshot, chạy máy ảo, cài lên máy thật,
  kiểm bản release) như `shellx-ios/scripts/dev.sh`; `release/mobile/android.sh` dựng AAB đã ký vào
  `build/release/android/`, kiểm app id, versionCode, target SDK, không có code debug, căn trang 16 KB nếu
  có `.so`, rồi dừng; người dùng tự tải lên.
- **Con đường lên Play**: Internal testing sớm → Closed testing → Production khi đủ G1, G2.

## 9. Giữ Android và iPhone khớp nhau [người viết]

- File đối chiếu `docs/superpowers/ledgers/shellx-android-parity.md`: mỗi dòng là một màn hay một luật ở mục
  6, file iPhone, file Android, trạng thái.
- Thay đổi nào ở `shellx-ios/` trong lúc dự án chạy thì thêm dòng vào file này.
- Sau khi phát hành, mỗi tính năng điện thoại mới cần làm ở cả hai app hoặc ghi rõ lệch.

## 10. Phần việc của người dùng

- Play Console:
  - kiểm loại tài khoản nhà phát triển. Tài khoản **cá nhân tạo sau 13/11/2023** phải chạy closed testing
    với ít nhất 12 người thử trong 14 ngày liên tục trước khi được lên Production;
  - xem versionCode cao nhất đã tải lên;
  - lấy SHA-1 / SHA-256 của khoá Play App Signing.
- Firebase: thêm app `com.shellx.dev`, tải `google-services.json` cho cả hai app. File này không phải bí
  mật, nhưng giữ theo cách builder đề xuất.
- Google Cloud: các client OAuth Android và Web (dự án 1 §10).
- Máy Android thật để dogfood: người dùng **đã có** và chạy thử được **[người dùng]**. Plan ghi hãng và bản
  Android của máy ở bước đầu tiên. Nếu là Xiaomi, Oppo hay Vivo thì thêm phép thử ở 7.4c.
- Tải AAB lên Play Console.
- Điền các mục chính sách trên Play Console. Builder soạn sẵn câu trả lời từ sự thật trong code: dữ liệu
  thu, mã hoá đầu cuối, xoá tài khoản.
- Nội dung trang Play: biểu tượng 512 px, ảnh nổi bật 1024×500, ảnh chụp màn hình, mô tả en / vi.

## 11. Để lại cho người làm

- Cấu trúc Gradle chi tiết (một project hay included build cho `shellx-link/kotlin`), phiên bản thư viện.
- Cách ánh xạ từng thành phần SwiftUI sang Compose, miễn giữ mục 6 và 7.2.
- Cách lưu bí mật cụ thể trên Keystore, miễn không ra khỏi máy và không vào bản sao lưu.
- Thư viện screenshot test.
- Thứ tự công việc trong dự án, miễn terminal Android làm sau khi terminal iPhone đã vào `develop`.
