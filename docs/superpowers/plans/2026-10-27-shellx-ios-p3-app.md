# ShellX iOS P3: app iOS native mới

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App iOS mới của ShellX (bản 2.0.0, thay app Flutter 1.0.0) làm trọn vòng với một Mac đang mở ShellX:
- đăng nhập tài khoản ShellX, ghép cặp Mac bằng QR;
- màn chính "ShellX": việc chờ được ghim, trạng thái các phiên Claude Code, nhắn việc cho một phiên đang chạy;
- duyệt quyền, trả lời câu hỏi, duyệt plan;
- chat với từng agent và dừng agent;
- giữ mic để nói, tiếng Việt;
- cài lên simulator và iPhone thật, đóng gói ipa App Store ngay trên Mac này.

**Architecture:**
- Thư mục mới `shellx-ios/`, có ranh giới giấy phép riêng, kiểm bằng `scripts/shellx/check-ios-license.sh`.
- Logic nằm trong package `shellx-ios/Packages/ShellXAppCore`, test bằng `swift test` trên Mac, không cần simulator. Package này phụ thuộc `shellx-link` (local).
- Test dùng `FakeMac`: một `LinkHost` thật với nguồn dữ liệu giả, nối qua `makeInMemoryCircuitPair()`. Nhờ vậy P3 làm song song được với P2 Task 8–11; chỉ Task 11 cần Mac thật.
- App target `shellx-ios/ShellX/` chỉ giữ SwiftUI, phần gắn với nền tảng (Keychain, Speech, AVFoundation, camera) và composition root.
- Project Xcode mỏng, commit vào repo. Mọi build iOS đi qua `shellx-ios/scripts/dev.sh` và `release/mobile/ios.sh`.

**Tech Stack:**
- Swift 6 (language mode 6), SwiftUI + Observation, iOS 17.0+, Xcode 26.2;
- CryptoKit, Security (Keychain), Speech (`SpeechAnalyzer` trên iOS 26+, `SFSpeechRecognizer`), AVFoundation, Network (`NWPathMonitor`);
- `shellx-link`: `ShellXLinkCore`, `ShellXLinkRelay`, `ShellXLinkSession`, `ShellXLinkAccount`;
- XCTest.

**Spec:** `docs/superpowers/specs/2026-10-22-shellx-ios-agent-remote-design.md` (§2, §3, §4, §7.1, §7.4, §7.5, §7.6, §8, §10 mục 3, §11). Mockup: `docs/superpowers/design/2026-10-22-ios-agent-remote/home-layout.html` (kiểu **C**). Hợp đồng với P2: các khối Interfaces của Task 2, 3, 4, 7 trong `docs/superpowers/plans/2026-10-27-shellx-link-p2-mac-serves-phones.md`. Ledger: `docs/superpowers/ledgers/shellx-ios.md`.

**Điều kiện bắt đầu:** P2 Task 7 đã commit trên `feat/shellx-link-p2`. Task 11 cần thêm P2 Task 8–11.

## Quyết định của người viết plan

Mọi mục dưới đây là **[người viết plan]**, builder có thể xem lại.

**D1. Thư mục và project Xcode.**
- App nằm ở `shellx-ios/` (gốc repo), có `LICENSE` riêng: "All rights reserved" (quyết định 3 của người dùng).
- `shellx-ios/ShellX.xcodeproj` được commit, viết tay một lần với `objectVersion = 77`. `ShellX/` và `ShellXTests/` là `PBXFileSystemSynchronizedRootGroup` (thư mục đồng bộ, Xcode 16+), nên thêm hay đổi tên file Swift không đụng tới `project.pbxproj`.
- Mọi build setting nằm trong `shellx-ios/Config/*.xcconfig`, nên diff đọc được.
- `Info.plist` và entitlements nằm ở `Config/`, ngoài thư mục đồng bộ, để khỏi bị chép thành resource.
- Không dùng XcodeGen hay Tuist. Lý do chính để dùng chúng là `pbxproj` đổi mỗi khi thêm file, mà thư mục đồng bộ đã giải quyết việc đó; dùng thì phải cài thêm công cụ.

**D2. Phụ thuộc vào `shellx-link`.**
- `ShellXAppCore/Package.swift` khai báo `.package(path: "../../../shellx-link")` và dùng bốn product của nó.
- App target chỉ link `ShellXAppCore` và `ShellXAppTestSupport`, không tham chiếu thẳng `shellx-link`. `ShellXAppTestSupport` được link để chạy chế độ demo của bản Debug.
- P3 không có package nào tải từ mạng.
- P3 chỉ thêm vào `shellx-link` hai thứ: product `ShellXLinkAccount` (khi P2 chưa khai báo) và `RelayAPI.logout(token:)`, đặt trong file mới để ít đụng nhánh P2.

**D3. Ranh giới giấy phép.** `scripts/shellx/check-ios-license.sh [--root <dir>]` thoát 1 và in đường dẫn vi phạm khi gặp một trong các trường hợp:
- một `Package.swift` trong `shellx-ios/` có `.package(url:`, hoặc có `path:` trỏ ra ngoài `shellx-ios/` và `shellx-link/`;
- một `project.pbxproj` có `XCRemoteSwiftPackageReference`, hoặc có `relativePath`/`path` trỏ ra ngoài hai thư mục đó;
- một file `.swift` trong `shellx-ios/` `import` một module ngoài **danh sách cho phép**. Danh sách gồm các framework Apple liệt kê trong script, `ShellXLinkCore`, `ShellXLinkRelay`, `ShellXLinkSession`, `ShellXLinkAccount`, `ShellXAppCore`, `ShellXAppTestSupport` và `ShellX`;
- có chữ `Manaflow` trong `shellx-ios/`;
- `scripts/shellx/check-link-license.sh` không qua.

Dùng danh sách cho phép thay vì danh sách cấm: một module GPL mới thêm vào `Packages/` sẽ tự bị chặn mà không ai phải nhớ cập nhật script.

**D4. Build, cài và test.** Dùng `shellx-ios/scripts/dev.sh`:
- `sim [--demo] [--api <url>]`: build Debug, rồi cài và mở trên simulator riêng tên `ShellX Dev`. Simulator này được tạo khi cần, bằng runtime iOS mới nhất đã cài. Script không bao giờ dùng simulator nào khác, và chỉ boot một simulator ShellX.
- `device [--device-id <id>] [--demo]`: build Debug ký tự động với team `W4RF3W4VTZ`, cài và mở bằng `xcrun devicectl`. Id máy lấy theo thứ tự: `--device-id`, `SHELLX_IPHONE_DEVICE_ID`, `~/.config/shellx/iphone-device-id`.
- `test [core|app|all] [--runtime <ver>]`: `core` chạy `swift test` cho `ShellXAppCore`; `app` chạy test của app trên `ShellX Dev`; cả hai đều chạy kèm `check-ios-license.sh` và `check-strings.py`.
- `screenshots <dir>`: chạy các test `*RenderTests` hai lần (`-testLanguage en` và `vi`), ghi PNG vào `<dir>`.
- `clean`: xoá simulator riêng và DerivedData.
- DerivedData nằm ở `shellx-ios/.derived/` (gitignore).
- Luật "không chạy `xcodebuild` trần" của repo áp cho iOS theo nghĩa: chỉ gọi `xcodebuild` qua `dev.sh` hoặc `release/mobile/ios.sh`.
- Cổng đăng nhập của `ios/AGENTS.md` thuộc về app cmux nên không áp dụng ở đây. Bản ShellX Dev cài lên iPhone ở trạng thái chưa đăng nhập, và người dùng tự đăng nhập trên máy. Script không bao giờ nhận mật khẩu.

**D5. Bundle id và máy chủ.**
- Release: `com.shellx.prod`, tên "ShellX", bản `2.0.0`. Luôn dùng `https://relay.shellx.pro` và bỏ qua mọi biến môi trường.
- Debug: `com.shellx.dev`, tên "ShellX Dev". Cài song song được với bản TestFlight, Keychain riêng. Mặc định cũng dùng `https://relay.shellx.pro`.
- `SHELLX_API_BASE` (đặt bằng `dev.sh sim --api`) chỉ có hiệu lực ở bản Debug, và chỉ khi là `https`, hoặc `http` tới loopback. Vì vậy relay local chỉ dùng được trên simulator, vốn dùng chung mạng với Mac.
- `SHELLX_DEMO=1` (chỉ bản Debug): bỏ qua đăng nhập; app ghép sẵn với một `FakeMac` chạy trong tiến trình, có việc chờ, phiên agent và chat giả. Chế độ này để làm UI trong lúc P2 Task 8–11 chưa xong.

**D6. Lưu trữ trên điện thoại.**
- **Keychain:**
  - lưu phiên tài khoản (token), khoá static Link của điện thoại, danh sách Mac đã ghép (kèm host key đã ghim) và `userID` chủ của danh sách đó;
  - thuộc tính: `kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, không đồng bộ iCloud;
  - access group `$(AppIdentifierPrefix)<bundle id>.shared`, để Notification Service Extension của P4 đọc được mà không phải chuyển dữ liệu.
- **Lịch sử:** gồm dòng thời gian của màn chính, bản sao chat của từng phiên, và trạng thái phiên lần cuối thấy.
  - Lưu thành file JSON trong `Application Support/ShellX/`, loại khỏi backup iCloud, với `completeUntilFirstUserAuthentication`.
  - Mất khi cài lại app thì chấp nhận được (spec §7.6).
  - Việc chờ và trạng thái agent luôn lấy lại từ Mac, không lưu.
- **Không dùng SwiftData.** Kho này rất đơn giản (đọc hết lúc mở, ghi lại có giới hạn). File JSON dễ test hơn, và không vướng luật `Sendable` của `ModelContext` trong Swift 6.
- **Gỡ app:** Keychain còn lại sau khi gỡ app (đó là hành vi của iOS). Cài lại thì vẫn đăng nhập và vẫn ghép cặp, chỉ mất lịch sử.
- **Đăng xuất và token hết hạn:** luật ở Task 2. Đăng xuất gỡ ghép cặp mọi Mac rồi xoá hết, để Mac không còn liệt kê một iPhone đã chết. Token hết hạn (401) chỉ xoá token: relay giữ `device_id` theo khoá công khai, nên đăng nhập lại cùng tài khoản thì grant còn nguyên.

**D7. Màn chính trong P3, khi chưa có AI điều phối (P6).** Người dùng đã chọn mặc định này (quyết định 1).
- **Ghim trên cùng:** "Cần bạn · N", gồm việc chờ của mọi Mac, ghim tới khi được xử lý.
- **Dưới đó:** "Agent · N". Mỗi phiên Claude Code còn sống là một dòng: chấm màu trạng thái, workspace, Mac, và trạng thái đó kéo dài bao lâu. Bấm vào thì mở chi tiết agent.
- **Dòng thời gian:** câu người dùng đã nói hoặc gõ, và tin của "ShellX". Tin của ShellX là câu soạn sẵn, không phải AI, ví dụ:
  - "Đã gửi tới Claude Code ở shellx.";
  - "MacBook Pro đang offline.";
  - "Claude Code ở shellx đã xong: <dòng đầu câu trả lời cuối của agent>".
- **Ô soạn (mic và bàn phím):** gửi tới **một phiên đang chạy**, ghi trên chip "Gửi tới: Claude Code · shellx ▾". Mặc định là phiên vừa nhắn; không có thì lấy phiên hoạt động gần nhất trên Mac mặc định.
- Chưa có chip skill (P5). Chưa mở được phiên mới từ điện thoại (P5/P6).

**D8. Giọng nói.**
- **iOS 26 trở lên:** dùng `SpeechAnalyzer` với module `SpeechTranscriber`, hoặc `DictationTranscriber` nếu chỉ module này có `vi-VN`.
- **Còn lại:** dùng `SFSpeechRecognizer`.
  - Chạy trên máy khi `supportsOnDeviceRecognition` đúng.
  - Nếu không, chạy qua máy chủ Apple, và Cài đặt ghi rõ điều đó.
- **Khi mic không dùng được:** chỉ xảy ra khi không còn đường nào (ví dụ không có mạng và không chạy trên máy được). Khi đó app nói lý do và mở bàn phím.
- **Ngữ cảnh:** tên workspace và các thuật ngữ (`PR`, `CI`, `push`, `branch`…) được đưa vào `contextualStrings`, để chịu được câu tiếng Việt xen thuật ngữ tiếng Anh.
- **Ngôn ngữ nói:** Tiếng Việt hoặc English. Mặc định là Tiếng Việt khi danh sách ngôn ngữ ưu tiên của máy có tiếng Việt.

**D9. Kênh `terminal` tách thành plan P3b.** Lý do:
- **Nhiều phần độc lập với app.** Nó trải trên ba phần:
  - giao thức: kênh byte, ảnh chụp màn hình ban đầu, flow control; v1 chưa định nghĩa việc chia frame;
  - phía Mac: móc `ghostty_surface_set_pty_tee_cb`, là code GPL trong `Sources/`;
  - phía iPhone: SwiftTerm hoặc libghostty, cần duyệt giấy phép và nới `check-ios-license.sh` cho một package tải từ mạng.
- **Ưu tiên của spec.** Spec §3.2 xếp chat trước, terminal sau, và app P3 dùng trọn vẹn được khi chưa có terminal.
- **Phụ thuộc.** Phía Mac của kênh này phụ thuộc P2 Task 10, chưa xong.

P3b được viết sau P3 Task 8. Màn chi tiết agent của P3 chưa có nút terminal.

## Quyết định của người dùng (2026-10-27)

1. **Màn chính P3 (D7):** giữ mặc định. Ô soạn nhắn việc vào một phiên Claude Code đang chạy; chưa mở phiên mới từ điện thoại cho tới P5/P6.
2. **Trả lời câu hỏi của agent:** **có trả lời tự do ("Khác…") ngay ở P3.** Giao thức đã đổi ở P2 Task 4b (`shellx-link/spec/PROTOCOL.md` §4 Decision, §5 luật 3):
   - `selections` theo vị trí: `selections[i]` trả lời `questions[i]`, số phần tử bằng số câu hỏi;
   - mỗi phần tử dài 1–1024 byte UTF-8;
   - phần tử trùng `label` là chọn đáp án đó, chuỗi khác là câu trả lời tự do;
   - câu chọn nhiều nối các `label` đã chọn bằng `", "`.

   Mac nhận ở P2 Task 10. Phần app nằm ở Task 5 (`QuestionDraft`, sheet câu hỏi) và Task 9 (giọng nói).
3. **`shellx-ios/LICENSE`:** "All rights reserved".

## Global Constraints

- Không chép, link hay import code từ `ios/`, `Packages/`, `Sources/`, `cmux-tui/` hay `shellx-core/`. Không dùng dịch vụ Manaflow nào (Cloud, VPN, Billing, Stack Auth, iroh, presence, analytics). `scripts/shellx/check-ios-license.sh` luôn xanh (spec §7.1, G6). Đọc app cmux iOS để tham khảo thì được, không chép.
- iOS tối thiểu 17.0, chỉ iPhone (`TARGETED_DEVICE_FAMILY = 1`), Swift language mode 6, `SWIFT_STRICT_CONCURRENCY = complete`. API của iOS 26 nằm sau `#available(iOS 26, *)`.
- Release: bundle `com.shellx.prod`, team `W4RF3W4VTZ`, `MARKETING_VERSION = 2.0.0`, tên ShellX, logo vẽ từ `design/shellx-logo.svg`.
- Code sửa trong `shellx-link/` vẫn tương thích Swift 6.0, và `scripts/shellx/check-link-license.sh` vẫn xanh.
- Mọi chữ hiển thị có cả `vi` và `en` trong `shellx-ios/ShellX/Localizable.xcstrings` hoặc `InfoPlist.xcstrings`.
  - Không có literal trần trong `Text`, `Button`, `Label`, `.navigationTitle` hay alert.
  - `shellx-ios/scripts/check-strings.py` phải xanh.
  - Mỗi task UI ghi kết quả audit localization vào commit.
- UI theo Apple HIG:
  - mỗi task UI đọc trang HIG liên quan và ghi tên trang vào commit;
  - có Dynamic Type và nhãn VoiceOver; vùng bấm ≥ 44 pt;
  - chạy đúng ở cả giao diện sáng và tối.
- Màu dịu, không nút gradient.
  - Màu chính `#60a5fa`; nút chính dùng chữ `#0b1220`.
  - Trạng thái: đang chạy = vàng `#facc15`, cần bạn = `#60a5fa`, xong = xanh lá `#4ade80`, lỗi = đỏ `#f87171`, đã kết thúc hoặc offline = xám `#8b919c`.
  - Ở giao diện sáng, các màu này dùng bản đậm hơn trong asset catalog.
- **Agent:** v1 chỉ phục vụ Claude Code, việc này do phía Mac lọc. App hiện mọi thứ host gửi, không lọc theo agent. Tên hiển thị: `claude` → "Claude Code", `codex` → "Codex", chuỗi khác giữ nguyên.
- **A1:** việc đã xử lý ở bất kỳ đâu thì thẻ và nút của nó biến mất. Sau khi mất kết nối, không bao giờ hiện nút bấm được cho dữ liệu chưa đồng bộ lại.
- **A2 và §7.4** (p95, đo trên iPhone thật qua relay.shellx.pro):
  - bấm Cho phép → hook nhận quyết định: < 500 ms;
  - trạng thái đổi trên Mac → thẻ đổi: < 1 s;
  - xử lý ở một máy → ghim ở máy kia biến mất: < 2 s;
  - đang nói → chữ đầu tiên hiện ra: < 300 ms;
  - mở app (đã có cache) → thấy cuộc trò chuyện: < 1 s, kết nối chạy nền.

  Không đạt thì báo người dùng, không lặng lẽ hạ mục tiêu.
- **Mac offline:** không xếp hàng việc. Nói hoặc gõ thì app trả lời ngay "<tên Mac> đang offline" (§7.5).
- Token, khoá, URI ghép cặp (chứa mã một lần) và mật khẩu không bao giờ được log, in ra hay nằm trên dòng lệnh. Log chỉ chứa số đo và mã lỗi.
- **Giọng nói:**
  - chỉ dùng nhận dạng của Apple, không gửi giọng nói tới máy chủ ShellX hay bên thứ ba;
  - không bao giờ tắt mic chỉ vì `vi-VN` không chạy được trên máy (§4).
- **Kiến trúc** (theo tinh thần `skills/cmux-architecture`):
  - model là `@MainActor @Observable`, phụ thuộc truyền qua `init`, không có singleton;
  - mỗi file một kiểu chính;
  - logic có test nằm trong `ShellXAppCore`; app target không chứa logic quyết định.
- **Build và cài:** chỉ qua `shellx-ios/scripts/dev.sh` và `release/mobile/ios.sh`, dùng simulator riêng `ShellX Dev`. Không đụng ShellX hay cmux đang chạy trên Mac của người dùng. Phía Mac chỉ dùng tagged build `link`.
- Phát hành chạy local, không có CI cho mobile (spec §8). Không upload TestFlight, push, deploy hay tạo tài nguyên trả phí khi chưa hỏi người dùng.
- **Nhánh:** làm trên `feat/shellx-ios-p3`, tách từ `feat/shellx-link-p2`.
  - Merge nhánh P2 vào mỗi khi P2 có task mới.
  - Mở PR vào `develop` sau khi P2 đã vào `develop`.
  - Chỉ push khi người dùng bảo.

## Review Focus

1. **Đổi mạng giữa chừng** (Wi-Fi ↔ 4G, vào hầm) khi app đang mở: phiên đã chết vẫn trông như "online" tới 45 s.
   - Kỳ vọng: đổi đường mạng thì nối lại ngay; thẻ chờ bị khoá nút cho tới khi đồng bộ lại; bấm trong lúc đó thì báo "chưa gửi được", không im lặng.
   - Test: Task 3 `testPathChangeForcesReconnect`, `testPendingDisabledWhileReconnectingClearedWhenOffline`; Task 5 `testTapWhileReconnectingFailsVisibly`.
2. **Việc được xử lý trên Mac (hoặc trên iPhone khác) trong lúc sheet trả lời câu hỏi hay duyệt plan đang mở.**
   - Kỳ vọng: sheet báo "Đã được xử lý ở nơi khác", tắt nút và không gửi gì.
   - Test: Task 5 `testSheetReportsHandledElsewhereWhenItemResolved`.
3. **Mac gỡ iPhone, hoặc mật khẩu tài khoản bị đổi, trong lúc app đang mở.**
   - Kỳ vọng: vòng nối lại dừng và máy hiện đúng trạng thái; 401 đưa về màn đăng nhập mà vẫn giữ các Mac đã ghép của cùng tài khoản.
   - Test: Task 3 `testNotGrantedStopsLoopAndMarksRevoked`, `testUnauthorizedStopsAndReports`; Task 2 `testExpiredTokenKeepsMachinesForSameAccount`.
4. **Chữ quá dài:** dán log 1 MB vào ô gõ, hoặc nói liền 10 phút.
   - Kỳ vọng: app chặn ở 16 384 byte trước khi gửi và nói rõ cho người dùng; Mac không bao giờ phải trả lỗi giao thức.
   - Test: Task 7 `testOverlongTextRefusedBeforeSend`; Task 9 `testDictationStopsAtByteLimit`.
5. **Nội dung lớn hoặc lạ:** lệnh xin phép 8 KB, plan 8 KB, 500 mục chat 4 KB, emoji, chữ viết từ phải sang trái.
   - Kỳ vọng: UI không đứng, preview được thu gọn, mục bị cắt có dấu báo.
   - Test: Task 5 `testLongPreviewRendersCollapsed`; Task 8 `testTruncatedEntryShowsMarker`, `testThreadCapKeepsNewest`.

---

### Task 1: Khung app, ranh giới giấy phép, script dev

**Files:**
- Create: `shellx-ios/LICENSE`, `shellx-ios/README.md`
- Create: `shellx-ios/ShellX.xcodeproj/project.pbxproj`, `shellx-ios/ShellX.xcodeproj/xcshareddata/xcschemes/ShellX.xcscheme`
- Create: `shellx-ios/Config/Base.xcconfig`, `Debug.xcconfig`, `Release.xcconfig`, `Version.xcconfig`, `Info.plist`, `ShellX.entitlements`
- Create: `shellx-ios/ShellX/ShellXApp.swift`, `shellx-ios/ShellX/UI/RootView.swift`, `shellx-ios/ShellX/Localizable.xcstrings`, `InfoPlist.xcstrings`, `Assets.xcassets`
- Create: `shellx-ios/Packages/ShellXAppCore/Package.swift`, `Sources/ShellXAppCore/Config/ShellXEndpoints.swift`
- Create: `shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/ShellXEndpointsTests.swift`, `LicenseBoundaryTests.swift`, `StringsCatalogCheckTests.swift`
- Create: `shellx-ios/ShellXTests/Support/SnapshotWriter.swift`, `shellx-ios/ShellXTests/LaunchSmokeTests.swift`
- Create: `scripts/shellx/check-ios-license.sh`, `shellx-ios/scripts/dev.sh`, `shellx-ios/scripts/check-strings.py`, `shellx-ios/scripts/strings-identity.txt`
- Modify: `.gitignore` (thêm `shellx-ios/.derived/`, `shellx-ios/Packages/*/.build/`)
- Modify (chỉ khi P2 chưa khai báo): `shellx-link/Package.swift` (thêm `.library(name: "ShellXLinkAccount", targets: ["ShellXLinkAccount"])`)

**Interfaces:**
- Consumes: `shellx-link` sau P2 Task 7 (Step 1).
- Produces:
  - **`ShellXEndpoints`:** `public struct ShellXEndpoints: Equatable, Sendable`, gồm:
    - `static let production = URL(string: "https://relay.shellx.pro")!`;
    - `let apiBase: URL`;
    - `init(debugBuild: Bool, environment: [String: String])`.

    Bản Release luôn dùng `production`. Bản Debug nhận `SHELLX_API_BASE` khi đó là `https`, hoặc `http` tới `localhost`, `127.0.0.0/8` hay `::1`. Giá trị khác thì bị bỏ: ghi log `api_override_rejected` và dùng `production`.
  - **Package `ShellXAppCore`:** swift-tools-version 6.0, platforms `.iOS(.v17)` và `.macOS(.v14)`, language mode 6, một product `ShellXAppCore`. Task 2 thêm `ShellXAppTestSupport`.
  - **xcconfig:**
    - `Base.xcconfig`:
      - `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `TARGETED_DEVICE_FAMILY = 1`;
      - `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`;
      - `DEVELOPMENT_TEAM = W4RF3W4VTZ`, `CODE_SIGN_STYLE = Automatic`;
      - `INFOPLIST_FILE = Config/Info.plist`, `CODE_SIGN_ENTITLEMENTS = Config/ShellX.entitlements`;
      - `LOCALIZATION_PREFERS_STRING_CATALOGS = YES`, `SWIFT_EMIT_LOC_STRINGS = YES`.
    - `Debug.xcconfig`: `PRODUCT_BUNDLE_IDENTIFIER = com.shellx.dev`, `SHELLX_DISPLAY_NAME = ShellX Dev`.
    - `Release.xcconfig`: `com.shellx.prod`, `ShellX`.
    - `Version.xcconfig`: `MARKETING_VERSION = 2.0.0`, `CURRENT_PROJECT_VERSION = 1`.
  - **Entitlements:** chỉ có `keychain-access-groups = [$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER).shared]`. Chưa có `aps-environment` (P4).
  - **Info.plist:**
    - `CFBundleDisplayName = $(SHELLX_DISPLAY_NAME)`;
    - `CFBundleDevelopmentRegion = en`, `CFBundleLocalizations = [en, vi]`;
    - `ShellXKeychainGroup = $(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER).shared`;
    - `NSAppTransportSecurity.NSAllowsLocalNetworking = YES`;
    - `UILaunchScreen`: nền hệ thống và logo.

    Chuỗi xin quyền và `CFBundleURLTypes` được thêm ở task dùng tới chúng.
  - **Asset catalog:**
    - `AppIcon`: một ảnh 1024×1024 vẽ từ `design/shellx-logo.svg` bằng `rsvg-convert`;
    - `AccentColor` = `#60a5fa`;
    - `AccentText`: sáng `#2563eb`, tối `#60a5fa`;
    - `StatusRunning`, `StatusNeedsYou`, `StatusDone`, `StatusError`, `StatusIdle`: bản tối dùng các mã ở Global Constraints, bản sáng lần lượt `#ca8a04`, `#2563eb`, `#16a34a`, `#dc2626`, `#6b7280`.
  - **`SnapshotWriter`** (`ShellXTests/Support/`, chỉ dùng trong test):
    - `struct SnapshotWriter { func write(_ view: some View, name: String) throws -> [UIImage] }`, trả ảnh sáng rồi ảnh tối;
    - view được đặt trong một `UIWindow` cỡ 393×852, chụp ở hai `overrideUserInterfaceStyle` bằng `drawHierarchy`. Không dùng `ImageRenderer`, vì nó không vẽ `List` và `TextField`;
    - ghi `<name>-<light|dark>-<ngôn ngữ>.png` vào `SHELLX_SNAPSHOT_DIR` khi biến này có giá trị.
  - **Script:**
    - `dev.sh`: như D4;
    - `check-ios-license.sh`: như D3;
    - `check-strings.py [--root <dir>]`, thoát 1 khi:
      - một key thiếu `en` hoặc `vi` đã dịch (state `translated`, không rỗng, đủ mọi nhánh plural);
      - có `extractionState: stale`;
      - bản `vi` giống hệt bản `en` mà key không nằm trong `strings-identity.txt`;
      - một key dùng trong `shellx-ios/ShellX/**/*.swift` (dạng `String(localized: "<key>"` hoặc `LocalizedStringResource("<key>"`) không có trong catalog;
      - có literal trần `Text("`, `Button("`, `Label("`, `.navigationTitle("` hoặc `.alert("`. `Text(verbatim:` được phép.

- [ ] **Step 1: Lấy code P2 và đối chiếu hợp đồng.**
  - Kiểm `test -f shellx-link/Sources/ShellXLinkAccount/LinkConnector.swift`. Nếu chưa có thì P2 Task 7 chưa xong: dừng lại.
  - Chạy `git merge --no-edit feat/shellx-link-p2`, rồi `swift test --package-path shellx-link`. Kỳ vọng PASS.
  - Đối chiếu chữ ký thật với khối Consumes của các task dưới:
    - `RelayAPI`, `PhonePairing.pair`, `LinkConnector.connect`, `PairedMachine`, `PairedMachineListing`, `RelayAPIError`;
    - `LinkClient.sessions/sessionChanges/chatHistory/chatSend/chatInterrupt/chatEntries`;
    - `LinkHost.init(key:trustedClients:feed:sessions:chat:hostVersion:machineName:)`;
    - `ChatEntry.rev` và helper chọn bản mới hơn (ví dụ `ChatEntry.newer(_:_:)`).

    Có chỗ khác thì sửa plan trong một commit riêng (`docs(shellx-ios): P3 plan follows P2 signatures`) trước khi làm tiếp.
- [ ] **Step 2: Viết test fail.**
  - `ShellXEndpointsTests`:
    - `testReleaseIgnoresOverride`;
    - `testDebugUsesLoopbackOverride` (`http://127.0.0.1:8787`);
    - `testDebugRejectsPlainHTTPRemote` (`http://192.168.1.5:8787` → `production`);
    - `testDebugDefaultsToProduction`.
  - `LicenseBoundaryTests`. Test dựng một cây giả trong thư mục tạm rồi chạy script với `--root`:
    - `testRepositoryPasses` (chạy trên cây thật);
    - `testRemotePackageInManifestFails`;
    - `testRemotePackageInProjectFails`;
    - `testPathIntoGPLTreeFails` (`relativePath = ../Packages/iOS/Foo`);
    - `testImportOutsideAllowlistFails` (`import CmuxMobileKit`);
    - `testManaflowStringFails`.
  - `StringsCatalogCheckTests`:
    - `testRepositoryPasses`;
    - `testMissingVietnameseFails`;
    - `testStaleEntryFails`;
    - `testCopiedEnglishFails`;
    - `testIdentityListAllowsSameText`;
    - `testKeyMissingFromCatalogFails`;
    - `testBareTextLiteralFails`.
  - `LaunchSmokeTests` (chạy trên simulator):
    - `testBundleHasEnglishAndVietnamese`: `Bundle.main.localizations` chứa `en` và `vi`;
    - `testDisplayNameIsShellXDev`;
    - `testRootRenders`: gọi `SnapshotWriter`.

  Chạy `shellx-ios/scripts/dev.sh test core`. Kỳ vọng FAIL.
- [ ] **Step 3: Cài đặt.**
  - Viết project như D1.
  - `RootView` chỉ hiện logo và chữ "ShellX" (key `root.title`).
  - `README.md` ghi: ranh giới giấy phép, cách dùng `dev.sh`, chế độ demo.
- [ ] **Step 4: Chạy lại.**
  - `dev.sh test all`: kỳ vọng PASS.
  - `bash scripts/shellx/check-ios-license.sh`: kỳ vọng exit 0.
  - `dev.sh sim`: app mở trên `ShellX Dev`. Chụp bằng `xcrun simctl io <udid> screenshot` vào thư mục scratch.
  - `xcrun simctl list devices booted`: chỉ một simulator ShellX đang boot.
- [ ] **Step 5: Commit** (`feat(shellx-ios): app skeleton, license boundary, dev script`).

### Task 2: Tài khoản: Keychain, đăng nhập, đăng xuất

**Files:**
- Create: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Account/SecretStore.swift`, `InMemorySecretStore.swift`, `StoredSession.swift`, `AccountVault.swift`, `RelayAccountCalling.swift`, `RelayAPI+RelayAccountCalling.swift`, `SignInError.swift`, `LocalDataWiping.swift`, `AppPhase.swift`, `AppCoordinator.swift`
- Create: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppTestSupport/FakeRelayAccount.swift`
- Modify: `shellx-ios/Packages/ShellXAppCore/Package.swift` (target và product `ShellXAppTestSupport`), `shellx-ios/ShellX.xcodeproj/project.pbxproj` (app link `ShellXAppTestSupport`)
- Create: `shellx-link/Sources/ShellXLinkAccount/RelayAPI+Logout.swift`, `shellx-link/Tests/ShellXLinkAccountTests/RelayAPILogoutTests.swift`
- Create: `shellx-ios/ShellX/Platform/KeychainSecretStore.swift`, `shellx-ios/ShellX/AppComposition.swift`, `shellx-ios/ShellX/UI/SignIn/SignInView.swift`, `shellx-ios/ShellX/UI/Settings/SettingsView.swift`, `AccountSection.swift`, `AboutSection.swift`
- Modify: `shellx-ios/ShellX/ShellXApp.swift`, `UI/RootView.swift`, `Localizable.xcstrings`
- Test: `ShellXAppCoreTests/AccountVaultTests.swift`, `AppCoordinatorTests.swift`; `shellx-ios/ShellXTests/KeychainSecretStoreTests.swift`, `AccountRenderTests.swift`

**Interfaces:**
- Consumes:
  - từ P2 Task 7: `RelayAPI.login(email:password:deviceName:clientKey:)`, `.machines(token:)`, `.unpair(grantID:token:)`, `PhonePairing.pair(offerURI:clientKey:api:token:pollInterval:)`, `AccountSession`, `RelayAPIError`, `PairedMachine`, `PairedMachineListing`;
  - từ P1: `NoiseStaticKey`.
- Produces:
  - **`SecretStore`:**
    - `public protocol SecretStore: Sendable` có ba hàm: `func read(_ item: SecretItem) throws -> Data?`, `func write(_ data: Data, for item: SecretItem) throws`, `func delete(_ item: SecretItem) throws`;
    - `public enum SecretItem: String, CaseIterable, Sendable { case session, phoneKey = "phone-key", machines }`;
    - `public enum SecretStoreError: Error, Equatable { case unavailable(status: Int32), failed(status: Int32) }`. `unavailable` ứng với `errSecInteractionNotAllowed`;
    - `InMemorySecretStore` có thể cài sẵn lỗi cho từng hàm.
  - **`StoredSession`:** `public struct StoredSession: Codable, Equatable, Sendable { userID, deviceID, token, email }`. `description` không in token.
  - **`AccountVault`:** `public actor AccountVault`, gồm:
    - `init(store: any SecretStore)`;
    - `session() throws -> StoredSession?`, `setSession(_:) throws`, `clearSession() throws`;
    - `phoneKey() throws -> NoiseStaticKey`: tạo và lưu ở lần gọi đầu;
    - `machines() throws -> [PairedMachine]`, `machinesOwner() throws -> String?`, `setMachines(_ machines: [PairedMachine], owner: String) throws`;
    - `wipe() throws`.

    Bản ghi danh sách Mac lưu dạng `{"version":1,"owner":"<userID>","machines":[…]}`.
  - **`RelayAccountCalling`:** `public protocol RelayAccountCalling: Sendable`, gồm:
    - `login(email:password:deviceName:clientKey:) async throws -> AccountSession`;
    - `logout(token:) async throws`;
    - `machines(token:) async throws -> [PairedMachineListing]`;
    - `unpair(grantID:token:) async throws`;
    - `pair(offerURI:clientKey:token:) async throws -> PairedMachine`.

    `RelayAPI` conform protocol này; `pair` gọi `PhonePairing.pair(... api: self ...)`.
  - **`RelayAPI.logout(token: String) async throws`:** gọi `POST /v1/auth/logout` với Bearer. Mã 2xx là xong; mã khác ném `RelayAPIError.http`.
  - **`SignInError`:** `public enum SignInError: Error, Equatable { case invalidCredentials, rateLimited, network, server(code: String) }`. Map: 401 `invalid_credentials` → `invalidCredentials`; 429 → `rateLimited`; `URLError` → `network`; còn lại → `server`.
  - **`LocalDataWiping`:** `public protocol LocalDataWiping: Sendable { func wipe() async }`.
  - **`AppPhase`:** `public enum AppPhase: Equatable, Sendable { case launching, signedOut(expired: Bool), signedIn(email: String) }`.
  - **`AppCoordinator`:** `@MainActor @Observable public final class AppCoordinator`, gồm:
    - `init(vault: AccountVault, relay: any RelayAccountCalling, deviceName: String, wipers: [any LocalDataWiping])`;
    - `phase: AppPhase`;
    - `launch() async`;
    - `signIn(email: String, password: String) async throws(SignInError)`;
    - `signOut() async`;
    - `handleUnauthorized() async`;
    - `protectedDataBecameAvailable() async`.
  - **`FakeRelayAccount`** (`ShellXAppTestSupport`, actor):
    - ghi lại mọi lời gọi;
    - cài sẵn được kết quả `login`, danh sách grant, và lỗi cho từng hàm;
    - `pair` trả một `PairedMachine` cài sẵn sau `approvalDelay`.
  - **`KeychainSecretStore`** (app): `init(service: String, accessGroup: String?)`.
    - Thuộc tính: `kSecClassGenericPassword`, `kSecUseDataProtectionKeychain`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable = false`.
    - `service` là bundle id; `accessGroup` đọc từ khoá `ShellXKeychainGroup` trong Info.plist.

**Luật:**
- **`launch()`:** đọc phiên.
  - Gặp `unavailable` thì giữ `.launching` và thử lại ở `protectedDataBecameAvailable()`. Lý do: iOS có thể khởi động trước (prewarm) app khi máy chưa mở khoá lần nào.
  - Không có phiên thì chuyển sang `.signedOut(expired: false)`.
- **`signIn`:**
  - Khoá điện thoại tạo một lần và dùng lại ở mọi lần đăng nhập.
  - Nếu `machinesOwner` khác `userID` vừa đăng nhập, xoá danh sách Mac và chạy mọi `wipers`.
- **`signOut()`:** làm theo thứ tự:
  1. Gọi `machines(token:)`, rồi `unpair` từng grant. Lỗi chỉ ghi log.
  2. Gọi `logout`. Lỗi chỉ ghi log.
  3. Gọi `vault.wipe()` và mọi `wipers`.
  4. Chuyển sang `.signedOut(expired: false)`.
- **`handleUnauthorized()`:** chỉ gọi `clearSession()`, giữ khoá và danh sách Mac, rồi chuyển sang `.signedOut(expired: true)`.

**Chữ hiển thị (vi / en):**
- "Đăng nhập ShellX" / "Sign in to ShellX";
- "Dùng tài khoản ShellX bạn đã đăng nhập trên Mac." / "Use the ShellX account you signed in with on your Mac.";
- "Email hoặc mật khẩu không đúng." / "Wrong email or password.";
- "Thử lại sau ít phút." / "Try again in a few minutes.";
- "Không kết nối được tới ShellX." / "Can't reach ShellX.";
- "Phiên đăng nhập đã hết hạn. Đăng nhập lại." / "Your session expired. Sign in again.";
- "Đăng xuất" / "Sign out";
- xác nhận đăng xuất: "iPhone này sẽ bị gỡ khỏi mọi Mac đã ghép cặp, và lịch sử trên iPhone sẽ bị xoá." / "This iPhone will be removed from every paired Mac, and its history will be deleted."

- [ ] **Step 1: Viết test fail.**
  - `RelayAPILogoutTests` (dùng `StubURLProtocol` của P2): `testLogoutPostsBearer`, `testLogoutErrorSurfaced`.
  - `AccountVaultTests`: `testPhoneKeyCreatedOnceAndReused`, `testMachinesRoundTripWithOwner`, `testWipeRemovesEveryItem`, `testUnavailableSurfaces`.
  - `AppCoordinatorTests`:
    - `testLaunchWithoutSessionIsSignedOut`;
    - `testUnavailableKeychainDoesNotSignOut`;
    - `testSignInSendsStoredPhoneKey`;
    - `testSignInMapsInvalidCredentialsAndRateLimit`;
    - `testSignOutUnpairsLogsOutAndWipes`;
    - `testSignOutWipesEvenWhenRelayUnreachable`;
    - `testExpiredTokenKeepsMachinesForSameAccount`;
    - `testSignInAsOtherAccountDropsMachines`.
  - `KeychainSecretStoreTests` (simulator): `testWriteReadDelete`, `testItemIsThisDeviceOnlyAfterFirstUnlock` (đọc lại `kSecAttrAccessible` của item).

  Chạy `swift test --package-path shellx-link --filter RelayAPILogoutTests`, `dev.sh test core`, `dev.sh test app`. Kỳ vọng FAIL.
- [ ] **Step 2: Cài đặt.**
  - `SignInView`:
    - ô email dùng `.textContentType(.username)` và `.keyboardType(.emailAddress)`; ô mật khẩu dùng `.textContentType(.password)`, nên AutoFill hoạt động;
    - nút "Đăng nhập" là nút chính `#60a5fa`;
    - có lỗi thì hiện ngay dưới form.
  - `SettingsView`: mục Tài khoản (email, Đăng xuất với hộp xác nhận kiểu destructive) và mục Giới thiệu (phiên bản app; "Giấy phép" ghi `shellx-link` theo MIT).
  - `AppComposition` dựng `AppCoordinator` thật, `RootView` chuyển màn theo `phase`.
  - Đọc các trang HIG "Text fields", "Managing accounts", "Alerts".
- [ ] **Step 3: Chạy lại** các lệnh ở Step 1. Kỳ vọng PASS. Chạy `dev.sh screenshots <scratch>` (`AccountRenderTests`: `SignInView` có và không có lỗi, `SettingsView`) rồi xem bằng mắt.
- [ ] **Step 4: Audit localization** theo `check-strings.py` và `rg` tìm literal trần. Ghi kết quả audit và tên các trang HIG vào commit.
- [ ] **Step 5: Commit** (`feat(shellx-ios): account sign-in and sign-out with Keychain secrets`).

### Task 3: Một kết nối Link cho mỗi Mac

**Files:**
- Create: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Link/MachineLinkConnecting.swift`, `RelayMachineConnector.swift`, `LinkFailure.swift`, `ReconnectSchedule.swift`, `RevisionGate.swift`, `PendingSet.swift`, `SessionSet.swift`, `MachineLinkState.swift`, `MachineEvent.swift`, `MachineConnection.swift`, `MachineModel.swift`, `MachineHub.swift`, `LinkCallError.swift`, `SessionRef.swift`, `MachinePendingItem.swift`, `MachineSession.swift`
- Create: `.../Sources/ShellXAppCore/Diagnostics/LatencyLog.swift`
- Modify: `.../Account/AppCoordinator.swift` (thêm `hub`)
- Create: `.../Sources/ShellXAppTestSupport/FakeMac.swift`, `FakeMacFeed.swift`, `FakeMacSessions.swift`, `FakeMacChat.swift`, `FakeMacFleet.swift`
- Create: `shellx-ios/ShellX/Platform/NetworkPathWatcher.swift`; Modify: `shellx-ios/ShellX/ShellXApp.swift`, `AppComposition.swift`
- Test: `ShellXAppCoreTests/PendingSetTests.swift`, `SessionSetTests.swift`, `LinkFailureTests.swift`, `ReconnectScheduleTests.swift`, `LatencyLogTests.swift`, `MachineConnectionTests.swift`, `MachineHubTests.swift`

**Interfaces:**
- Consumes:
  - từ P1 và P2 Task 2–3: `LinkClient` (`snapshot`, `changes`, `reply`, `sessions`, `sessionChanges`, `chatHistory`, `chatSend`, `chatInterrupt`, `chatEntries`, `close`), `LinkClientError`, `LinkHost.init(key:trustedClients:feed:sessions:chat:hostVersion:machineName:)`, `AgentFeedSource`, `AgentSessionSource`, `AgentChatSource`, `AgentSession`, `ChatEntry`, `makeInMemoryCircuitPair()`;
  - từ P2 Task 4 và 7: `LinkConnector.connect(machine:key:api:token:clientVersion:deviceName:)`, `RelayAPIError`, `RelayError.server(code:retryable:)`; từ P1: `NoiseError.untrustedPeer`;
  - từ Task 2: `AccountVault`, `RelayAccountCalling`, `AppCoordinator.handleUnauthorized()`.
- Produces:
  - **Kết nối:**
    - `public protocol MachineLinkConnecting: Sendable { func connect(_ machine: PairedMachine) async throws -> LinkClient }`;
    - `public struct RelayMachineConnector: MachineLinkConnecting`, `init(api: RelayAPI, vault: AccountVault, clientVersion: String, deviceName: String)`. Mỗi lần nối, nó đọc khoá và token mới nhất từ vault.
  - **`LinkFailure`:** `public enum LinkFailure: Equatable, Sendable { case offline, signedOut, revoked, hostKeyChanged, needsUpdate }`, khởi tạo bằng `init(_ error: any Error)`:
    - `RelayAPIError.http(401, _)` → `.signedOut`;
    - `RelayAPIError.http(_, "not_granted")` hoặc `"machine_not_found"` → `.revoked`;
    - `NoiseError.untrustedPeer` → `.hostKeyChanged`;
    - `LinkClientError.protocolMismatch` → `.needsUpdate`;
    - mọi lỗi khác (`URLError`, `RelayError`, `.timedOut`, `.sessionClosed`) → `.offline`.
  - **`ReconnectSchedule`:** `public struct ReconnectSchedule: Sendable`, có `static let standard` và `func delay(afterFailures: Int, jitter: Double) -> Duration`. `standard` chờ lần lượt 0.5, 1, 2, 4, 8, 15, 30 s, trần 30 s, cộng trừ tối đa 20 %.
  - **`MachineLinkState`:** `public enum MachineLinkState: Equatable, Sendable { case connecting, online, reconnecting, offline(since: Date), revoked, hostKeyChanged, needsUpdate }`. Ba trạng thái cuối dừng vòng nối lại.
  - **Tập dữ liệu có revision:**
    - `public struct PendingSet: Equatable, Sendable`: `revision: Int`, `items: [PendingItem]` (sắp theo `createdAtMs`), `mutating func reset(revision:items:)`, `mutating func apply(revision:added:resolved:) -> RevisionGate.Result`;
    - `SessionSet` có hình dạng tương tự, dùng `upserted` và `removed`; `sessions` sắp theo `lastActivityMs` giảm dần;
    - `RevisionGate.Result` gồm `.applied`, `.ignored`, `.gap`, theo đúng luật §4 của `PROTOCOL.md`.
  - **`MachineEvent`:** `public enum MachineEvent: Sendable`, gồm:
    - `.state(MachineLinkState)`;
    - `.pending(PendingSet, actionable: Bool)`;
    - `.sessions(SessionSet, supported: Bool)`;
    - `.chat(sessionId: String, entries: [ChatEntry])`.
  - **`MachineConnection`:** `public actor MachineConnection`, gồm:
    - `init(machine: PairedMachine, connector: any MachineLinkConnecting, latency: LatencyLog, schedule: ReconnectSchedule = .standard, sleep: @escaping @Sendable (Duration) async throws -> Void)`;
    - `nonisolated let events: AsyncStream<MachineEvent>`;
    - `start()`, `stop() async`;
    - `reconnectNow()`: bỏ qua thời gian chờ còn lại;
    - `forceReconnect()`: đóng phiên đang sống rồi nối lại;
    - `call<T: Sendable>(_ body: @Sendable (LinkClient) async throws -> T) async throws -> T`: ném `LinkCallError.offline` khi không ở trạng thái `online`.
  - **Kiểu dùng chung:**
    - `public struct SessionRef: Codable, Hashable, Sendable { machineID, sessionId, agent, workspaceTitle }`;
    - `public struct PendingKey: Hashable, Sendable { machineID, requestId }`;
    - `public struct MachinePendingItem: Identifiable, Equatable, Sendable { machineID, machineName, item: PendingItem, actionable: Bool; var id: PendingKey }`;
    - `public struct MachineSession: Identifiable, Equatable, Sendable { machineID, machineName, online: Bool, session: AgentSession; var ref: SessionRef }`;
    - `public enum LinkCallError: Error, Equatable { case offline(machineName: String), unknownMachine }`.
  - **`MachineModel`:** `@MainActor @Observable public final class MachineModel`, gồm `machine: PairedMachine`, `name: String`, `state: MachineLinkState`, `pending: PendingSet`, `pendingActionable: Bool`, `sessions: SessionSet`, `sessionsSupported: Bool`.
  - **`MachineHub`:** `@MainActor @Observable public final class MachineHub`, gồm:
    - `init(vault: AccountVault, relay: any RelayAccountCalling, connector: any MachineLinkConnecting, latency: LatencyLog, defaults: UserDefaults, sleep: @escaping @Sendable (Duration) async throws -> Void, onUnauthorized: @escaping @MainActor () async -> Void)`;
    - `machines: [MachineModel]`;
    - `defaultMachineID: String?`: lưu ở UserDefaults khoá `shellx.defaultMachineID`; khi Mac mặc định bị gỡ thì về Mac đầu tiên;
    - `pendingItems: [MachinePendingItem]`: việc chờ của mọi Mac, sắp theo `createdAtMs`;
    - `liveSessions: [MachineSession]`: mọi phiên có state khác `ended`;
    - `start() async`, `stopAll() async`;
    - `add(_ machine: PairedMachine) async throws`: lưu Mac vào vault (`owner` là `userID` của phiên) và bắt đầu kết nối; Mac trùng `machineID` thì thay bản cũ. Hub là nơi duy nhất ghi danh sách Mac vào vault (`start` đọc, `add` và `unpair` ghi);
    - `refreshGrants() async`: Mac không còn trong `machines(token:)` thì chuyển sang `revoked`; tên đổi thì cập nhật;
    - `appDidBecomeActive()`;
    - `appDidEnterBackground() async`: đóng mọi phiên sau `backgroundGrace = .seconds(25)` nếu app chưa quay lại;
    - `networkChanged()`: gọi `forceReconnect()` cho Mac đang `online`, `reconnectNow()` cho các Mac còn lại;
    - `reply(_ key: PendingKey, decision: LinkDecision) async throws -> ReplyOutcome`;
    - `chatHistory(_ ref: SessionRef, beforeSeq: Int?, limit: Int) async throws -> (entries: [ChatEntry], hasMore: Bool)`;
    - `chatSend(_ ref: SessionRef, text: String) async throws -> ChatSendOutcome`;
    - `chatInterrupt(_ ref: SessionRef, hard: Bool) async throws -> ChatInterruptOutcome`;
    - `chatUpdates() -> AsyncStream<(SessionRef, [ChatEntry])>` và `sessionUpdates() -> AsyncStream<(machineID: String, sessions: [AgentSession])>`. Cả hai là multicast: mỗi lần gọi thêm một subscriber, subscriber bị bỏ khi bên đọc dừng.
  - **`AppCoordinator`:** thêm `hub: MachineHub?` và tham số `init(..., makeHub: @escaping @MainActor () -> MachineHub)`.
    - Khi chuyển sang `signedIn`: tạo hub và `await hub.start()`.
    - Khi đăng xuất hoặc gặp 401: `await hub?.stopAll()` rồi bỏ hub.
  - **`LatencyLog`:** `public final class LatencyLog: Sendable`, an toàn đa luồng, gồm:
    - `public enum LatencyMetric: String, CaseIterable, Sendable { case replyRoundTrip, pendingArrival, sessionChangeArrival, launchToHome, firstWord }`;
    - `func record(_ metric: LatencyMetric, _ duration: Duration)`: giá trị âm (lệch đồng hồ) tính là 0;
    - `func summary(_ metric: LatencyMetric) -> LatencySummary?`, với `LatencySummary { count, p50, p95 }` tính trên 200 giá trị cuối;
    - mỗi lần ghi in một dòng `os.Logger` (category `latency`), chỉ gồm tên chỉ số và số ms.
  - **`FakeMac`** (`ShellXAppTestSupport`, actor):
    - `init(name: String)`; `nonisolated let machine: PairedMachine`;
    - `nonisolated func connector(phoneKey: @escaping @Sendable () async throws -> NoiseStaticKey) -> any MachineLinkConnecting`;
    - `failNextConnects(_ error: any Error, count: Int)`, `rotateHostKey()`, `dropLiveSessions() async`, `connectCount`;
    - việc chờ: `addPending(_:)`, `resolvePending(_:)`, `skipNextPendingRevision()`, `setReplyOutcome(_:delay:)`, `decisions`;
    - phiên: `upsertSession(_:)`, `removeSession(_:)`;
    - chat: `setHistory(sessionId:entries:)`, `pushChat(sessionId:entries:)`, `setSendOutcome(_:)`, `sentTexts`, `setInterruptOutcome(_:)`, `interrupts`;
    - `servesSessionsAndChat: Bool`: false thì `LinkHost` được tạo không có nguồn phiên và chat, giống Mac chưa có P2 Task 10.

    `FakeMacFleet(_ macs: [FakeMac], phoneKey:)` là một `MachineLinkConnecting` chuyển lời nối tới đúng `FakeMac` theo `machineID`.

**Luật của `MachineConnection`:**
- **Một vòng kết nối:**
  1. Nối tới Mac.
  2. Gọi `snapshot()`.
  3. Gọi `sessions()`. Lỗi `LinkClientError.remote(code: "unsupported", _)` không phải lỗi kết nối: đặt `supported = false` rồi đi tiếp.
  4. Phát `.online`.
  5. Đọc liên tục `changes`, `sessionChanges` và `chatEntries`, mỗi luồng một task, cho tới khi `changes` kết thúc.
- **Đọc `chatEntries` liên tục:** cả khi không có màn nào đang xem chat, vì đó là `AsyncStream` không giới hạn bộ đệm.
- **Ghi độ trễ:** mỗi item trong `added` ghi `pendingArrival` = bây giờ − `createdAtMs`. Mỗi phiên có trạng thái đổi ghi `sessionChangeArrival` = bây giờ − `stateSinceMs`.
- **Gặp `.gap`:** gọi lại `snapshot()` (hoặc `sessions()`) ngay trong phiên đang có.
- **Khi phiên kết thúc:** phát `.reconnecting` và giữ items với `actionable = false`. Nếu lần nối lại đầu tiên thất bại thì xoá items và phát `.offline(since:)`.
- **Lỗi dừng vòng:**
  - `.signedOut`: dừng, rồi hub gọi `onUnauthorized`;
  - `.revoked`, `.hostKeyChanged`, `.needsUpdate`: dừng và giữ nguyên trạng thái đó.
- **Nối lại:** theo `ReconnectSchedule`. Mỗi lần có `welcome` thì bộ đếm lỗi về 0.

- [ ] **Step 1: Viết test fail.**
  - `PendingSetTests`: `testOldRevisionIgnored`, `testNextRevisionApplied`, `testGapReported`, `testItemsSortedByCreation`.
  - `SessionSetTests`: `testUpsertAndRemove`, `testGapReported`.
  - `LinkFailureTests`, mỗi dòng map một test: `testUnauthorizedIsSignedOut`, `testNotGrantedIsRevoked`, `testMachineNotFoundIsRevoked`, `testUntrustedPeerIsHostKeyChanged`, `testProtocolMismatchIsNeedsUpdate`, `testOtherErrorsAreOffline`.
  - `ReconnectScheduleTests`: `testDelaysGrowAndCapAt30s`, `testJitterWithin20Percent`.
  - `LatencyLogTests`: `testPercentilesOverLast200`, `testNegativeDurationRecordedAsZero`.
  - `MachineConnectionTests` (dùng `FakeMac`, `sleep` không chờ):
    - `testConnectsAndPublishesPendingAndSessions`;
    - `testChangesAppliedInOrder`;
    - `testRevisionGapTriggersResync`;
    - `testHostWithoutSessionsStillServesPending`;
    - `testChatEntriesConsumedWithoutSubscribers`: 10 000 mục đẩy khi không ai nghe; bộ nhớ không giữ lại chúng, và việc chờ vẫn tới;
    - `testSessionEndReconnects`;
    - `testPendingDisabledWhileReconnectingClearedWhenOffline`;
    - `testNotGrantedStopsLoopAndMarksRevoked`;
    - `testUnauthorizedStopsAndReports`;
    - `testUntrustedHostStops` (dùng `rotateHostKey()`);
    - `testProtocolMismatchStops`;
    - `testReconnectNowSkipsBackoff`;
    - `testCallWhenOfflineThrowsOffline`.
  - `MachineHubTests`:
    - `testStartsOneConnectionPerPairedMachine`;
    - `testPendingMergedAcrossMachinesSortedByCreation`;
    - `testPathChangeForcesReconnect`;
    - `testBackgroundClosesAfterGrace`;
    - `testQuickReturnKeepsSessions`;
    - `testRefreshMarksMissingGrantRevokedAndRenames`;
    - `testUnauthorizedCallsCoordinator`;
    - `testChatAndSessionUpdatesMulticast`.

  Chạy `dev.sh test core`. Kỳ vọng FAIL.
- [ ] **Step 2: Cài đặt.**
  - `NetworkPathWatcher` dùng `NWPathMonitor`, gọi `hub.networkChanged()` khi interface hoặc trạng thái đổi. Các lần đổi trong vòng 300 ms gộp thành một lần gọi.
  - Theo `scenePhase`:
    - `.active`: gọi `appDidBecomeActive()` và `refreshGrants()`;
    - `.background`: gọi `appDidEnterBackground()` bên trong `beginBackgroundTask`.
- [ ] **Step 3: Chạy lại** `dev.sh test core` và `dev.sh test app`. Kỳ vọng PASS.
- [ ] **Step 4: Commit** (`feat(shellx-ios): one Link connection per paired Mac with resync and reconnect`).

### Task 4: Ghép cặp và "Máy của bạn"

**Files:**
- Create: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Pairing/PairingModel.swift`, `PairingFailure.swift`
- Modify: `.../Link/MachineHub.swift` (thêm `unpair`)
- Create: `shellx-ios/ShellX/UI/Pairing/PairingSheet.swift`, `QRScannerView.swift`, `UI/Machines/MachinesView.swift`, `MachineRow.swift`, `UI/Onboarding/FirstMacView.swift`, `UI/Theme/MachineStateStyle.swift`
- Create: `shellx-ios/ShellX/Debug/DemoComposition.swift`, `DemoScript.swift` (cả hai bọc trong `#if DEBUG`)
- Modify: `shellx-ios/ShellX/UI/RootView.swift`, `ShellXApp.swift` (`.onOpenURL`), `AppComposition.swift`, `Config/Info.plist` (`NSCameraUsageDescription`; `CFBundleURLTypes` với scheme `shellx-link`), `InfoPlist.xcstrings`, `Localizable.xcstrings`
- Test: `ShellXAppCoreTests/PairingModelTests.swift`, `MachineHubUnpairTests.swift`; `shellx-ios/ShellXTests/MachinesRenderTests.swift`

**Interfaces:**
- Consumes:
  - từ P2 Task 7: `PairingOffer(uri:)`, `PairingOffer.make(...)`, `PairingOfferError`, `PhonePairingError.denied/.expired`, `RelayAPIError`;
  - từ Task 2: `RelayAccountCalling.pair/unpair/machines`, `AccountVault`, `FakeRelayAccount`;
  - từ Task 3: `MachineHub`, `MachineLinkState`, `FakeMac`.
- Produces:
  - **`PairingFailure`:** `public enum PairingFailure: Equatable, Sendable { case notShellXCode, needsUpdate, damagedCode, denied, expired, otherAccount, network, server(code: String) }`. Map:
    - `PairingOfferError.badURI` → `notShellXCode`;
    - `.unsupportedVersion` → `needsUpdate`;
    - `.badField` → `damagedCode`;
    - `PhonePairingError.denied` → `denied`; `PhonePairingError.expired` → `expired`;
    - `RelayAPIError.http(_, "machine_not_found")` → `otherAccount`;
    - `URLError` → `network`;
    - còn lại → `server(code:)`.
  - **`PairingModel`:** `@MainActor @Observable public final class PairingModel`, gồm:
    - `enum Step: Equatable { case idle, confirm(machineName: String), waitingForMac(machineName: String), paired(machineName: String), failed(PairingFailure) }`;
    - `init(hub: MachineHub, relay: any RelayAccountCalling, vault: AccountVault)`;
    - `step: Step`;
    - `begin(uri: String)`: chỉ phân tích URI, không gọi mạng;
    - `confirm() async`: đọc khoá điện thoại và token từ vault, gọi `relay.pair(offerURI:clientKey:token:)`, rồi `hub.add` (hub tự lưu vào vault);
    - `cancel()`.
  - **`MachineHub.unpair(machineID: String) async throws`:**
    - tìm grant của Mac qua `machines(token:)` rồi gọi `unpair`;
    - grant đã mất (không có trong danh sách, hoặc 404) thì vẫn quên Mac;
    - lỗi mạng thì ném lỗi và giữ Mac.
  - **Demo** (bản Debug với `SHELLX_DEMO=1`): `DemoComposition` dựng `AppCoordinator` bằng:
    - `InMemorySecretStore` có sẵn một phiên;
    - `FakeRelayAccount` duyệt ghép cặp sau 2 s;
    - một `FakeMac` tên "Mac giả" đã ghép sẵn;
    - `DemoScript`: cứ 20 s thêm lần lượt một việc xin quyền, một câu hỏi, một plan; hai phiên agent đổi `working` → `idle`; chat có đủ các loại mục.

    `DemoComposition` cũng đặt sẵn vào pasteboard URI (mã giả) của "Mac giả 2", để thử luồng "Dán mã".

**Luật UI:**
- **Mở một QR hay URL:** đi vào bước `confirm`, hỏi "Ghép cặp với <tên Mac>?" trước mọi lời gọi mạng. URL `shellx-link://pair?...` mở từ app Camera của hệ thống cũng đi đúng đường này, nên một link lạ không tự ghép được. URL mở lúc chưa đăng nhập được giữ lại và mở sau khi đăng nhập xong.
- **Lúc chờ:** hiện "Bấm Đồng ý trên <tên Mac>" kèm nút Huỷ.
- **Dán mã:** sheet có lối "Dán mã ghép cặp" (đọc `UIPasteboard`), dùng được trên simulator (không có camera) và trên iPhone khi quyền camera bị từ chối.
- **Camera bị từ chối:** nói lý do, có nút mở Cài đặt và lối dán mã.
- **Danh sách "Máy của bạn":** mỗi Mac một dòng gồm tên, chấm và chữ trạng thái, dấu "Mặc định". Menu và thao tác vuốt có: "Đặt làm mặc định", "Gỡ ghép cặp" (cần xác nhận). Mac `hostKeyChanged` có nút "Ghép cặp lại"; Mac `revoked` có nút "Xoá".
- **Màn gốc:** đã đăng nhập mà chưa có Mac nào thì hiện `FirstMacView`. Có Mac thì tạm hiện `MachinesView`, cho tới khi Task 7 thay bằng màn chính.

**Chữ hiển thị (vi / en):**
- "Ghép cặp Mac" / "Pair a Mac";
- "Trên Mac, mở ShellX, bấm chuột phải vào "Mac này" rồi chọn Ghép cặp iPhone…" / "On your Mac, open ShellX, right-click "This Mac" and choose Pair iPhone…";
- "Ghép cặp với %@?" / "Pair with %@?";
- "Bấm Đồng ý trên %@" / "Click Allow on %@";
- trạng thái máy:
  - "Đã kết nối" / "Connected";
  - "Đang kết nối…" / "Connecting…";
  - "%@ đang offline" / "%@ is offline";
  - "Mac này đã gỡ iPhone" / "This Mac removed this iPhone";
  - "Khoá của Mac đã đổi. Ghép cặp lại." / "The Mac's key changed. Pair again.";
  - "Cần cập nhật ShellX" / "Update ShellX";
- lỗi ghép cặp:
  - "Đây không phải mã ghép cặp ShellX." / "This isn't a ShellX pairing code.";
  - "Mã đã hết hạn. Mở lại mã trên Mac." / "The code expired. Open it again on the Mac.";
  - "Mac đã từ chối." / "The Mac declined.";
  - "Mac này thuộc tài khoản khác." / "This Mac belongs to another account."

- [ ] **Step 1: Viết test fail.**
  - `PairingModelTests`:
    - `testValidURIAsksConfirmationBeforeNetwork`;
    - `testConfirmPairsSavesAndConnects`;
    - `testRepairReplacesSameMachine`;
    - `testDeniedAndExpiredMapped`;
    - `testOtherAccountMapped`;
    - `testBadURIMapped`;
    - `testCancelStopsWaiting`.
  - `MachineHubUnpairTests`:
    - `testUnpairCallsRelayThenForgets`;
    - `testUnpairMissingGrantStillForgets`;
    - `testUnpairNetworkErrorKeepsMachine`;
    - `testDefaultMachineFallsBackWhenRemoved`.

  Chạy `dev.sh test core`. Kỳ vọng FAIL.
- [ ] **Step 2: Cài đặt.** Đọc các trang HIG "Onboarding", "Sheets", "Lists and tables", "Alerts".
- [ ] **Step 3: Chạy lại** `dev.sh test core` và `dev.sh test app`. Kỳ vọng PASS.
  - `dev.sh sim --demo`: kỳ vọng "Mac giả" ở trạng thái "Đã kết nối"; ghép "Mac giả 2" bằng lối "Dán mã" thành công.
  - `dev.sh screenshots <scratch>` (`MachinesRenderTests`: mọi `MachineLinkState`, các bước của `PairingSheet`, `FirstMacView`), xem bằng mắt.
- [ ] **Step 4: Audit localization**, ghi kết quả và tên trang HIG vào commit.
- [ ] **Step 5: Commit** (`feat(shellx-ios): pair Macs by QR and manage paired Macs`).

### Task 5: Việc chờ và trả lời

**Files:**
- Create: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Pending/PendingAction.swift`, `PendingItem+Actions.swift`, `QuestionDraft.swift`, `DecisionSending.swift`, `DecisionStatus.swift`, `DecisionCenter.swift`, `PendingSheetModel.swift`, `AgentLabel.swift`
- Modify: `.../Link/MachineHub.swift` (conform `DecisionSending`)
- Create: `shellx-ios/ShellX/UI/Pending/PendingCardView.swift`, `PendingCardStatusLine.swift`, `CommandPreview.swift`, `QuestionAnswerSheet.swift`, `PlanReviewSheet.swift`
- Modify: `shellx-ios/ShellX/Localizable.xcstrings`
- Test: `ShellXAppCoreTests/PendingActionTests.swift`, `QuestionDraftTests.swift`, `DecisionCenterTests.swift`, `PendingSheetModelTests.swift`, `AgentLabelTests.swift`; `shellx-ios/ShellXTests/PendingCardRenderTests.swift`

**Interfaces:**
- Consumes:
  - từ P2 Task 2: `PendingItem` (`modes`, `questions`, `planPreview`), `PendingQuestion`, `PendingQuestionOption`, `LinkDecision`, `PermissionMode`, `ExitPlanMode`, `ReplyOutcome`, `LinkClientError`;
  - từ Task 3: `MachineHub.reply`, `pendingItems`, `MachinePendingItem`, `PendingKey`, `LinkCallError`, `LatencyLog`.
- Produces:
  - **`PendingAction`:** `public enum PendingAction: Equatable, Sendable { case allowOnce, deny, allowAlways, allowAllTools, answer, approvePlan(ExitPlanMode), revisePlan, rejectPlan, openOnMac }`, kèm `var decision: LinkDecision?`. `answer` và `revisePlan` cần thêm dữ liệu từ sheet nên trả nil.
  - **`extension PendingItem { public var actions: [PendingAction] }`:**
    - **permission:** xét theo thứ tự `once` → `.allowOnce`, `deny` → `.deny`, `always` → `.allowAlways`, `all` → `.allowAllTools`; mode nào có trong `modes` mới thành nút. Mode lạ (kể cả `bypass`) không bao giờ thành nút. Không còn nút nào thì trả `[.openOnMac]`.
    - **question:** `[.answer]` khi có ít nhất một câu hỏi và câu nào cũng có đáp án; nếu không thì `[.openOnMac]`.
    - **exit_plan:** `.approvePlan(.manual)` trước, rồi `.approvePlan(.autoAccept)` và `.approvePlan(.ultraplan)`, mỗi cái chỉ khi có trong `modes`. Thêm `.revisePlan` và `.rejectPlan` khi `modes` có `deny`.
    - **kind lạ:** `[.openOnMac]`.
  - **`QuestionDraft`:** `public struct QuestionDraft: Equatable, Sendable`, gồm:
    - `init(questions: [PendingQuestion])`;
    - `mutating func toggle(questionID: String, label: String)`: câu chọn một thì thay đáp án cũ; câu chọn nhiều thì bật hoặc tắt. Chọn một đáp án thì xoá chữ tự do của câu đó;
    - `mutating func setFreeText(questionID: String, text: String)`: câu trả lời "Khác…" cho câu đó; chữ không rỗng thì thay mọi đáp án đã chọn của câu đó. Chữ bị cắt còn 1024 byte UTF-8, đúng ranh giới ký tự;
    - `var isComplete: Bool`: câu nào cũng có đáp án hoặc chữ tự do;
    - `var decision: LinkDecision?` = `.question(selections:)` theo luật vị trí của P2 Task 4b. Mỗi câu hỏi đúng một phần tử, theo thứ tự câu hỏi: chữ tự do nếu có; nếu không thì `label` đã chọn, câu chọn nhiều nối các `label` bằng `", "` theo thứ tự đáp án.
    - Test thêm: `testFreeTextAnswerIsPositional`, `testChoosingOptionClearsFreeText`, `testMultiSelectJoinsLabels`, `testFreeTextCutAt1024Bytes`.
  - **Sheet câu hỏi:** mỗi câu hỏi có thêm dòng "Khác…" / "Other…" mở ô nhập chữ (bàn phím hoặc giữ mic). Chuỗi vi/en theo `skills/cmux-localization`.
  - **Gửi quyết định:**
    - `public protocol DecisionSending: Sendable { @MainActor func reply(_ key: PendingKey, decision: LinkDecision) async throws -> ReplyOutcome }`; `MachineHub` conform.
    - `public enum DecisionStatus: Equatable, Sendable { case sending, done, handledElsewhere, failed(DecisionFailure) }`.
    - `public enum DecisionFailure: Equatable, Sendable { case offline, noAnswer, rejected }`.
  - **`DecisionCenter`:** `@MainActor @Observable public final class DecisionCenter`, gồm:
    - `init(sender: any DecisionSending, latency: LatencyLog, sleep: @escaping @Sendable (Duration) async throws -> Void)`;
    - `status: [PendingKey: DecisionStatus]`;
    - `send(_ decision: LinkDecision, for key: PendingKey) async`;
    - `visibleItems(_ items: [MachinePendingItem]) -> [MachinePendingItem]`: bỏ item `done`, và bỏ item `handledElsewhere` sau 2 s;
    - `static let maxFeedbackBytes = 4096`.
  - **`PendingSheetModel`:** `@MainActor @Observable public final class PendingSheetModel`, gồm:
    - `init(key: PendingKey, hub: MachineHub, center: DecisionCenter)`;
    - `handledElsewhere: Bool`: đúng khi item rời tập chờ mà sheet chưa gửi gì;
    - `canSend: Bool`.
  - **`AgentLabel`:** `public struct AgentLabel { public init(agent: String); public let text: String }`. `claude` → "Claude Code", `codex` → "Codex", chuỗi khác giữ nguyên. Tên sản phẩm không dịch.

**Luật `DecisionCenter`:**
- Item đang `sending` thì bấm thêm bị bỏ qua.
- `.delivered` → `done`: thẻ ẩn ngay, không chờ `agent.changed`. Ghi `replyRoundTrip`.
- `.alreadyHandled` → `handledElsewhere`: hiện "Đã được xử lý ở nơi khác", rồi ẩn sau 2 s.
- `.unknown`, `.other(_)` hoặc `LinkClientError.remote` → `failed(.rejected)`: "Mac không nhận quyết định này. Mở trên Mac."
- `LinkClientError.timedOut` → gửi lại đúng một lần (an toàn vì idempotent). Lần đó vẫn hết giờ thì `failed(.noAnswer)`: "Chưa nhận được trả lời của Mac · Thử lại".
- `LinkCallError.offline`, `LinkClientError.sessionClosed`, hoặc item có `actionable == false` → `failed(.offline)`: "<Mac> đang offline · Chưa gửi". Khi nối lại, app không tự gửi lại (§7.5: không xếp hàng).
- Item không còn trong `pendingItems` thì xoá status của nó.
- `feedback` dài hơn 4096 byte UTF-8 thì không gửi. UI đếm byte và chặn trước.

**UI:**
- **Thẻ** (theo mockup C):
  - dòng đầu: `workspace · agent`; có từ hai Mac trở lên thì thêm tên Mac; sau đó là loại việc ("muốn chạy", "hỏi", "đề xuất plan");
  - thân: preview monospace tối đa 3 dòng. "Xem thêm" mở bản đầy đủ trong một sheet cuộn;
  - viền xanh `#60a5fa` nhạt;
  - nút: Cho phép (nút chính) và Từ chối. "Luôn cho phép" và "Tất cả công cụ" nằm trong menu "…";
  - thẻ có `actionable == false`: nút tắt, kèm dòng "Đang kết nối lại…".
- **Câu hỏi:** nút "Trả lời" mở `QuestionAnswerSheet`: mỗi câu hỏi một trang, đáp án là danh sách có dấu chọn, nút "Gửi" bật khi `isComplete`. Mic trong sheet được thêm ở Task 9.
- **Plan:** nút "Duyệt plan" mở `PlanReviewSheet`:
  - plan hiện dạng Markdown, cuộn được;
  - "Duyệt" gửi mode `manual`;
  - menu "Chế độ khác" có "Tự chấp nhận chỉnh sửa" và "Ultraplan";
  - "Chỉnh sửa…" gửi `deny` kèm góp ý (bắt buộc, ≤ 4096 byte);
  - "Từ chối".

**Chữ hiển thị (vi / en):** "Cho phép" / "Allow", "Từ chối" / "Deny", "Luôn cho phép" / "Always allow", "Tất cả công cụ" / "All tools", "Trả lời" / "Answer", "Duyệt plan" / "Review plan", "Duyệt" / "Approve", "Chỉnh sửa…" / "Revise…", "Mở trên Mac" / "Open on the Mac", "Đã được xử lý ở nơi khác" / "Already handled elsewhere".

- [ ] **Step 1: Viết test fail.**
  - `PendingActionTests`:
    - `testPermissionButtonsFollowModesInOrder`;
    - `testBypassAndUnknownModesNeverShown`;
    - `testEmptyModesOpenOnMac`;
    - `testQuestionWithoutOptionsOpenOnMac`;
    - `testPlanApproveManualFirst`;
    - `testUnknownKindOpenOnMacOnly`.
  - `QuestionDraftTests`: `testSingleSelectReplaces`, `testMultiSelectToggles`, `testCompleteNeedsEveryQuestion`, `testDecisionKeepsQuestionOrder`.
  - `AgentLabelTests`: `testKnownAgentsNamed`, `testUnknownAgentKeptAsIs`.
  - `DecisionCenterTests`. Phần lớn dùng hub thật với `FakeMac`; riêng các test hết giờ dùng một `DecisionSending` giả ném `LinkClientError.timedOut`, vì timeout thật của `LinkClient` là 10 s:
    - `testDeliveredHidesCardBeforeResolvedArrives`;
    - `testAlreadyHandledShowsThenHides`;
    - `testUnknownKeepsCardWithRejected`;
    - `testTimeoutResendsOnceThenFails`;
    - `testSecondTapWhileSendingIgnored`;
    - `testOfflineFailsWithoutResend`;
    - `testTapWhileReconnectingFailsVisibly`;
    - `testResolvedItemClearsStatus`;
    - `testFeedbackOver4096BytesRefused`.
  - `PendingSheetModelTests`: `testSheetReportsHandledElsewhereWhenItemResolved`, `testSheetNotFlaggedAfterOwnSend`.

  Chạy `dev.sh test core`. Kỳ vọng FAIL.
- [ ] **Step 2: Cài đặt.** Đọc các trang HIG "Buttons", "Menus", "Sheets", "Color".
- [ ] **Step 3: Chạy lại** `dev.sh test core`. Kỳ vọng PASS.
  - `PendingCardRenderTests`: mọi loại thẻ; các trạng thái `sending`, `failed`, `handledElsewhere` và không bấm được; cùng `testLongPreviewRendersCollapsed`: preview 8192 byte có emoji và chữ Ả Rập, kỳ vọng thẻ chỉ hiện 3 dòng preview.
  - Chạy `dev.sh test app` và `dev.sh screenshots <scratch>`, xem bằng mắt.
- [ ] **Step 4: Audit localization**, ghi kết quả và tên trang HIG vào commit.
- [ ] **Step 5: Commit** (`feat(shellx-ios): pinned pending cards with permission, question and plan replies`).

### Task 6: Lưu lịch sử trên điện thoại

**Files:**
- Create: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Storage/StoreDocument.swift`, `ConversationStore.swift`
- Modify: `shellx-ios/ShellX/AppComposition.swift` (tạo store trong `Application Support/ShellX/` và thêm nó vào `wipers`)
- Test: `ShellXAppCoreTests/ConversationStoreTests.swift`

**Interfaces:**
- Consumes: `LocalDataWiping` (Task 2), `SessionRef` (Task 3).
- Produces:
  - `public enum StoreDocument: Hashable, Sendable { case home, lastSessions, thread(SessionRef) }`.
  - **`ConversationStore`:** `public actor ConversationStore: LocalDataWiping`, gồm:
    - `init(directory: URL, maxThreads: Int = 100)`;
    - `func load<T: Decodable & Sendable>(_ doc: StoreDocument, as type: T.Type) -> T?`;
    - `func save<T: Encodable & Sendable>(_ value: T, to doc: StoreDocument)`;
    - `func wipe()`.
  - **Tên file:** `home.json`, `last-sessions.json`, và `threads/<sha256 hex của "machineID\0sessionId">.json`.
  - **Cách ghi:** dùng `.atomic` và `.completeFileProtectionUntilFirstUserAuthentication`; thư mục gốc đặt `isExcludedFromBackup = true`.
  - **File hỏng:** `load` trả nil, xoá file đó và ghi log `store_corrupt` kèm loại tài liệu (không ghi nội dung).
  - **Số thread:** quá `maxThreads` thì xoá thread được ghi lâu nhất.
  - Giới hạn số mục bên trong mỗi tài liệu do bên gọi giữ (Task 7, Task 8).

- [ ] **Step 1: Viết test fail.**
  - `testRoundTripEachDocument`;
  - `testCorruptFileLoadsNilAndIsRemoved`;
  - `testThreadsBeyondLimitEvictOldest`;
  - `testWipeRemovesEverything`;
  - `testDirectoryExcludedFromBackup`.

  Chạy `dev.sh test core`. Kỳ vọng FAIL.
- [ ] **Step 2: Cài đặt.**
- [ ] **Step 3: Chạy lại** `dev.sh test core`. Kỳ vọng PASS.
- [ ] **Step 4: Commit** (`feat(shellx-ios): on-device conversation store`).

### Task 7: Màn chính "ShellX"

**Files:**
- Create: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Home/HomeEntry.swift`, `HomeNote.swift`, `MachineSession+PreferredTarget.swift`, `SessionFinishDetector.swift`, `AgentStatusRow.swift`, `ComposerValidation.swift`, `HomeModel.swift`
- Create: `shellx-ios/ShellX/UI/Home/HomeView.swift`, `PinnedSection.swift`, `AgentStrip.swift`, `AgentStatusRowView.swift`, `UserMessageBubble.swift`, `HomeNoteRow.swift`, `MacStatusPill.swift`, `UI/Composer/ComposerBar.swift`, `TargetPicker.swift`, `UI/Theme/AgentStateStyle.swift`
- Modify: `shellx-ios/ShellX/UI/RootView.swift` (đã đăng nhập và có Mac → `HomeView`), `AppComposition.swift` (tạo `SignedInScope` gồm hub, `DecisionCenter`, `HomeModel`, `PairingModel` mỗi lần đăng nhập; ghi `launchToHome`), `ShellXApp.swift` (vào nền thì gọi `home.flush()`), `Localizable.xcstrings`
- Test: `ShellXAppCoreTests/PreferredTargetTests.swift`, `SessionFinishDetectorTests.swift`, `AgentStatusRowTests.swift`, `ComposerValidationTests.swift`, `HomeModelTests.swift`; `shellx-ios/ShellXTests/HomeRenderTests.swift`

**Interfaces:**
- Consumes:
  - từ Task 3: `MachineHub` (`liveSessions`, `pendingItems`, `machines`, `defaultMachineID`, `chatSend`, `chatHistory`, `chatUpdates`, `sessionUpdates`), `SessionRef`, `MachineSession`, `LatencyLog`;
  - từ Task 5: `DecisionCenter`, `PendingCardView`, `AgentLabel`;
  - từ Task 6: `ConversationStore`, `StoreDocument`.
- Produces:
  - **`HomeEntry`:** `public struct HomeEntry: Codable, Equatable, Identifiable, Sendable { id: String; at: Date; content: Content }`, với `enum Content: Codable, Equatable, Sendable { case userSaid(text: String, target: SessionRef?, viaVoice: Bool), note(HomeNote) }`.
  - **`HomeNote`:** `public enum HomeNote: Codable, Equatable, Sendable { case sent(SessionRef), sendFailed(SessionRef, SendFailure), machineOffline(machineName: String), noLiveSession, agentFinished(SessionRef, summary: String?) }`, với `public enum SendFailure: String, Codable, Sendable { case notFound, busy, failed, noAnswer }`.
  - **Chọn đích gửi:** `extension Array where Element == MachineSession { public func preferredTarget(lastUsed: SessionRef?, defaultMachineID: String?) -> SessionRef? }`. Thứ tự:
    1. `lastUsed`, nếu phiên đó còn sống và Mac của nó online;
    2. phiên có `lastActivityMs` mới nhất trên Mac mặc định (online);
    3. phiên mới nhất trên bất kỳ Mac online nào;
    4. không có thì nil.

    Phiên `ended` và phiên trên Mac không online không bao giờ là đích.
  - **`SessionFinishDetector`:** `public struct SessionFinishDetector: Codable, Sendable`, có `mutating func observe(machineID: String, sessions: [AgentSession]) -> [SessionRef]`.
    - Trả về các phiên vừa chuyển từ `working` hoặc `needsInput` sang `idle` so với lần thấy trước. Lần thấy trước có thể nằm trong `.lastSessions` đã lưu, nên việc xong trong lúc app đóng vẫn được báo.
    - Mỗi cặp `(sessionId, stateSinceMs)` chỉ báo một lần.
  - **`AgentStatusRow`:** `public struct AgentStatusRow: Equatable, Identifiable, Sendable { ref, machineName, state: AgentState, online: Bool, elapsed: Duration? }`, khởi tạo bằng `init(session: MachineSession, now: Date)`.
    - `elapsed` = bây giờ − `stateSinceMs`, không âm; nil khi thiếu `stateSinceMs`.
    - Danh sách hàng sắp theo: `needsInput`, rồi `working`, rồi `idle`; trong mỗi nhóm, `lastActivityMs` mới trước.
  - **`ComposerValidation`:** `public enum ComposerValidation: Equatable, Sendable { case empty, ok(String), tooLong(bytes: Int) }`, gồm `public init(_ text: String)` và `public static let maxBytes = 16_384`. Kiểm sau khi bỏ khoảng trắng ở hai đầu, đếm byte UTF-8.
  - **`HomeModel`:** `@MainActor @Observable public final class HomeModel`, gồm:
    - `init(hub: MachineHub, store: ConversationStore, now: @escaping () -> Date)`;
    - `entries: [HomeEntry]`: tối đa 2000 mục, giữ các mục mới nhất;
    - `target: SessionRef?`: đích người dùng tự chọn; nil thì dùng `effectiveTarget`;
    - `effectiveTarget: SessionRef?`;
    - `statusRows: [AgentStatusRow]`;
    - `load() async`;
    - `run() async`: theo dõi `sessionUpdates` để thêm note "xong", và `chatUpdates` để nhớ câu trả lời cuối của agent;
    - `submit(_ text: String, viaVoice: Bool) async -> ComposerValidation`;
    - `flush() async`: ghi ngay.

    Mỗi thay đổi được ghi xuống store chậm nhất 0.5 s sau lần thay đổi cuối, và ngay khi app vào nền.

**Luật `submit`:**
1. `empty` thì không làm gì. `tooLong` thì không gửi và trả kết quả về; UI hiện "Dài quá: %d / 16 384 byte".
2. Thêm một mục `userSaid`.
3. Không có đích:
   - Mac mặc định offline → thêm `.machineOffline(<tên Mac mặc định>)`;
   - ngược lại → thêm `.noLiveSession`.
4. Mac của đích không online → thêm `.machineOffline(name)` ngay, không gửi.
5. Gọi `chatSend`:
   - `submitted` → `.sent`;
   - `notFound`, `busy`, `failed`, `.other` → `.sendFailed` với lý do tương ứng (`.other` tính là `failed`);
   - ném `LinkCallError.offline` → `.machineOffline`; ném lỗi khác → `.sendFailed(.noAnswer)`.
6. Nhớ đích vừa dùng làm `lastUsed`.

**Note "xong":** `summary` là dòng đầu (tối đa 140 ký tự) của mục mới nhất có `role == .agent` và `kind == .prose` trong phiên đó. Nguồn là `chatUpdates` đã thấy; chưa thấy gì thì gọi `chatHistory(limit: 10)`. Gặp lỗi thì `summary` là nil.

**UI:**
- **Khung:** `NavigationStack`. Thanh công cụ: bên trái là `MacStatusPill` (tên Mac mặc định và chấm trạng thái; bấm mở "Máy của bạn"), bên phải là bánh răng mở Cài đặt.
- **Phần ghim:** đặt bằng `safeAreaInset(edge: .top)`, nên không trôi đi khi cuộn. Hiện tối đa hai thẻ kèm "Xem tất cả (N)"; danh sách lấy từ `DecisionCenter.visibleItems(hub.pendingItems)`.
- **`AgentStrip`:** nằm dưới phần ghim, thu gọn được.
- **Dòng thời gian:** `LazyVStack`, mục mới nhất ở dưới, tự cuộn xuống khi có mục mới.
- **`ComposerBar`** ở đáy màn: chip đích (mở `TargetPicker`), ô gõ 1–5 dòng, nút gửi. Task 9 thêm mic vào đây.
- **Trạng thái agent:** `idle` hiện là "Xong", màu xanh lá.

**Chữ hiển thị (vi / en):**
- "Cần bạn · %d" / "Needs you · %d", "Agent · %d" / "Agents · %d";
- "Gửi tới: %@" / "Send to: %@";
- "Đang chạy %@" / "Running for %@", "Cần bạn" / "Needs you", "Xong" / "Done";
- "Đã gửi tới %1$@ ở %2$@." / "Sent to %1$@ in %2$@.";
- "%@ đang offline." / "%@ is offline.";
- "Chưa có phiên Claude Code nào đang chạy. Mở Claude Code trong ShellX trên Mac rồi nhắn lại." / "No Claude Code session is running. Start Claude Code in ShellX on your Mac, then try again.";
- "%1$@ ở %2$@ đã xong: %3$@" / "%1$@ in %2$@ is done: %3$@";
- "Nhắn cho agent…" / "Message the agent…".

- [ ] **Step 1: Viết test fail.**
  - `PreferredTargetTests`: `testLastUsedWinsWhileLive`, `testDefaultMacMostRecentNext`, `testOfflineAndEndedNeverTargets`, `testNoLiveSessionGivesNil`.
  - `SessionFinishDetectorTests`: `testWorkingToIdleIsFinished`, `testFinishedWhileAppClosedDetectedFromSaved`, `testSameFinishNotRepeatedAfterResync`, `testIdleToIdleNotFinished`.
  - `AgentStatusRowTests`: `testElapsedClampsNegative` (đồng hồ Mac chạy nhanh hơn), `testElapsedNilWithoutSince`, `testRowsOrderNeedsYouThenRunningThenDone`.
  - `ComposerValidationTests`: `testWhitespaceIsEmpty`, `testExactly16384BytesOk`, `testOverlongTextRefusedBeforeSend` (16 385 byte chữ Việt nhiều byte).
  - `HomeModelTests` (hub với `FakeMac`, store trong thư mục tạm):
    - `testSubmitSendsToTargetAndNotesSent`;
    - `testSubmitToOfflineMacNotesOfflineImmediately`;
    - `testSubmitWithoutLiveSessionNotesNoLiveSession`;
    - `testBusyAndNotFoundNoted`;
    - `testFinishedNoteCarriesFirstLineOfLastAgentProse`;
    - `testEntriesPersistAndReload`;
    - `testEntriesCappedAt2000`.

  Chạy `dev.sh test core`. Kỳ vọng FAIL.
- [ ] **Step 2: Cài đặt.** Đọc các trang HIG "Layout", "Toolbars", "Text fields", "Scroll views", "Typography".
- [ ] **Step 3: Chạy lại** `dev.sh test core`. Kỳ vọng PASS.
  - `HomeRenderTests`: màn trống; màn đầy (2 việc chờ, 3 agent, 6 mục); Mac offline. Chạy `dev.sh test app` và `dev.sh screenshots <scratch>`, xem bằng mắt.
  - `dev.sh sim --demo`:
    - trả lời từng loại thẻ mà `DemoScript` tạo ra;
    - gửi tin tới một phiên giả và thấy note;
    - tắt app (`xcrun simctl terminate`) rồi mở lại. Kỳ vọng lịch sử vẫn còn, thẻ ghim được lấy lại từ Mac giả.
- [ ] **Step 4: Audit localization**, ghi kết quả và tên trang HIG vào commit.
- [ ] **Step 5: Commit** (`feat(shellx-ios): home conversation with pinned cards, agent strip and composer`).

### Task 8: Chi tiết agent

**Files:**
- Create: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Agent/ChatThread.swift`, `AgentSendResult.swift`, `AgentThreadModel.swift`
- Create: `shellx-ios/ShellX/UI/Agent/AgentView.swift`, `AgentHeader.swift`, `ChatEntryRow.swift`, `StopButton.swift`
- Modify: `shellx-ios/ShellX/UI/Home/HomeView.swift` (thêm `.navigationDestination(for: SessionRef.self)`; dòng của `AgentStrip` và note `agentFinished` mở `AgentView`), `Localizable.xcstrings`
- Test: `ShellXAppCoreTests/ChatThreadTests.swift`, `AgentThreadModelTests.swift`; `shellx-ios/ShellXTests/AgentRenderTests.swift`

**Interfaces:**
- Consumes:
  - từ P2 Task 3: `ChatEntry` (`rev` và helper chọn bản mới hơn), `ChatSendOutcome`, `ChatInterruptOutcome`;
  - từ Task 3: `MachineHub.chatHistory/chatSend/chatInterrupt/chatUpdates/pendingItems/liveSessions`, `SessionRef`, `MachineSession`;
  - từ Task 5: `PendingCardView`, `DecisionCenter`;
  - từ Task 6: `ConversationStore` với `.thread(SessionRef)`;
  - từ Task 7: `ComposerBar`, `ComposerValidation`.
- Produces:
  - **`ChatThread`:** `public struct ChatThread: Codable, Equatable, Sendable`, gồm:
    - `static let maxEntries = 500`;
    - `entries: [ChatEntry]`, `hasMore: Bool`;
    - `mutating func upsert(_ incoming: [ChatEntry])`;
    - `mutating func applyLatestPage(_ page: [ChatEntry], hasMore: Bool)`;
    - `mutating func applyOlderPage(_ page: [ChatEntry], hasMore: Bool)`.

    Luật gộp:
    - **Gộp theo `id`, giữ bản có `rev` cao hơn.** Dùng helper của P2 (ví dụ `ChatEntry.newer(_:_:)`) nếu có. Bản có `rev` thấp hơn hoặc bằng đến sau thì bị bỏ, kể cả khi nó đến từ một trang lịch sử cũ.
    - Danh sách sắp theo `seq`.
    - Chỉ giữ 500 mục mới nhất; khi phải bỏ mục cũ thì đặt `hasMore = true`.
    - `applyLatestPage`: nếu trang mới nhất không nối được với cache (mục cũ nhất của trang có `seq` lớn hơn mục mới nhất của cache + 1, và `hasMore` đúng), thay cả cache bằng trang đó.
    - Không tự cắt chữ: host đã cắt mỗi mục còn 4096 byte.
  - **Kết quả gửi:** `public enum AgentSendResult: Equatable, Sendable { case refused(ComposerValidation), sent(ChatSendOutcome), offline, noAnswer }`.
  - **`AgentThreadModel`:** `@MainActor @Observable public final class AgentThreadModel`, gồm:
    - `init(ref: SessionRef, hub: MachineHub, store: ConversationStore)`;
    - `thread: ChatThread`, `loading: Bool`, `offline: Bool`;
    - `session: MachineSession?`;
    - `pendingHere: [MachinePendingItem]`: việc chờ cùng `machineID` và cùng `workspaceId` với phiên;
    - `open() async`: hiện cache ngay, rồi gọi `chatHistory(beforeSeq: nil, limit: 50)`;
    - `loadOlder() async`: `beforeSeq` là `seq` nhỏ nhất đang có;
    - `run() async`: nhận `chatUpdates` của phiên này;
    - `send(_ text: String, viaVoice: Bool) async -> AgentSendResult`;
    - `stop(hard: Bool) async -> ChatInterruptOutcome?`.

    Thread được ghi vào store chậm nhất 0.5 s sau thay đổi cuối, và khi đóng màn.

**UI:**
- **Đầu màn:** tên workspace, "Claude Code · <tên Mac>", chấm trạng thái và chữ như "Đang chạy 4 phút".
- **Việc chờ của workspace này:** ghim trên cùng (`PendingCardView`).
- **Danh sách mục:** `LazyVStack`; kéo lên đầu danh sách để tải mục cũ hơn. Mỗi loại hiện khác nhau:
  - `prose`: Markdown inline;
  - `thought`: thu gọn, chữ xám, bấm để mở;
  - `tool_use`: một dòng gồm tên tool và chữ monospace;
  - `status`: căn giữa, chữ nhỏ;
  - `other`: chữ nhỏ, xám.

  Mục có `truncated == true` thêm dòng "… (đã cắt, xem đầy đủ trên Mac)".
- **Composer:** như màn chính, nhưng đích cố định là phiên này.
- **Nút "Dừng":** chỉ hiện khi phiên đang `working` hoặc `needsInput`, gửi `hard: false`. Menu của nút có "Dừng hẳn" (`hard: true`, cần xác nhận).
- Chưa có nút terminal (P3b).

**Chữ hiển thị (vi / en):** "Dừng" / "Stop", "Dừng hẳn" / "Force stop", "Đã gửi lệnh dừng" / "Stop sent", "Phiên này không còn trên Mac" / "This session is gone from the Mac", "Agent đang bận, thử lại sau" / "The agent is busy; try again later", "… (đã cắt, xem đầy đủ trên Mac)" / "… (cut; see it in full on the Mac)".

- [ ] **Step 1: Viết test fail.**
  - `ChatThreadTests`:
    - `testUpsertKeepsHigherRevAndSortsBySeq`;
    - `testLowerRevNeverOverwrites`: một trang lịch sử cũ đến sau một cập nhật mới;
    - `testLatestPageWithGapReplacesStaleCache`;
    - `testOlderPagePrepends`;
    - `testThreadCapKeepsNewest`: 600 mục 4 KB còn lại 500 mục mới nhất, `hasMore == true`.
  - `AgentThreadModelTests`:
    - `testOpenShowsCacheThenLatest`;
    - `testLoadOlderUsesSmallestSeq`;
    - `testLiveEntriesAppendWhileOpen`;
    - `testSendMapsOutcomes`;
    - `testStopSoftAndHard`;
    - `testOfflineOpenShowsCacheAndOffline`;
    - `testPendingHereFiltersByWorkspace`.

  Chạy `dev.sh test core`. Kỳ vọng FAIL.
- [ ] **Step 2: Cài đặt.** Đọc các trang HIG "Lists and tables", "Menus", "Alerts", "Typography".
- [ ] **Step 3: Chạy lại** `dev.sh test core`. Kỳ vọng PASS.
  - `AgentRenderTests`: mọi loại mục; `testTruncatedEntryShowsMarker`; khối code dài; `thought` ở trạng thái thu gọn.
  - Chạy `dev.sh test app` và `dev.sh screenshots <scratch>`, xem bằng mắt.
  - `dev.sh sim --demo`: mở một agent giả, gửi tin, bấm Dừng.
- [ ] **Step 4: Audit localization**, ghi kết quả và tên trang HIG vào commit.
- [ ] **Step 5: Commit** (`feat(shellx-ios): agent detail with chat history, live entries and stop`).

### Task 9: Giọng nói

**Files:**
- Create: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Voice/SpeechTranscribing.swift`, `VoicePermissionChecking.swift`, `VoiceCapabilities.swift`, `VoiceLanguage.swift`, `VoiceInputModel.swift`, `PendingQuestion+Matching.swift`
- Create: `.../Sources/ShellXAppTestSupport/FakeTranscriber.swift`, `FakeVoicePermissions.swift`
- Create: `shellx-ios/ShellX/Voice/AudioCapture.swift`, `LegacyTranscriber.swift`, `AnalyzerTranscriber.swift`, `SystemVoicePermissions.swift`, `VoiceCapabilityProbe.swift`, `shellx-ios/ShellX/UI/Composer/MicButton.swift`, `shellx-ios/ShellX/UI/Settings/VoiceSection.swift`
- Modify: `shellx-ios/ShellX/UI/Composer/ComposerBar.swift`, `UI/Pending/QuestionAnswerSheet.swift`, `UI/Pending/PlanReviewSheet.swift`, `UI/Settings/SettingsView.swift`, `AppComposition.swift`, `Config/Info.plist` (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`), `InfoPlist.xcstrings`, `Localizable.xcstrings`
- Modify: `docs/superpowers/ledgers/shellx-ios.md` (thêm mục "D-iOS-2: đường giọng nói trên iPhone thật")
- Test: `ShellXAppCoreTests/VoiceCapabilitiesTests.swift`, `VoiceInputModelTests.swift`, `OptionMatchingTests.swift`; `shellx-ios/ShellXTests/VoiceCapabilityProbeTests.swift`, `MicButtonRenderTests.swift`

**Interfaces:**
- Consumes:
  - từ Task 3: `LatencyLog` (`firstWord`), `MachineHub.liveSessions` (lấy tên workspace cho `contextualStrings`);
  - từ Task 5: `QuestionDraft`, `QuestionAnswerSheet`, `PlanReviewSheet`, `DecisionCenter.maxFeedbackBytes`;
  - từ Task 7: `ComposerBar`, `ComposerValidation.maxBytes`;
  - từ Task 2: `SettingsView`.
- Produces:
  - **`SpeechTranscribing`:** `public protocol SpeechTranscribing: Sendable`, gồm:
    - `func start(locale: Locale, contextualStrings: [String]) async throws -> AsyncThrowingStream<String, any Error>`: mỗi phần tử là toàn bộ chữ tính tới lúc đó, kể cả phần tạm;
    - `func finish() async -> String`;
    - `func cancel() async`.
  - **`VoiceCapabilities`:** `public enum VoiceEngine: Equatable, Sendable { case analyzer, onDevice, server }` và `public struct VoiceCapabilities: Equatable, Sendable { analyzerSupportsLocale: Bool; legacyOnDevice: Bool; legacyAvailable: Bool; var engine: VoiceEngine? }`. Chọn `analyzer` trước, rồi `onDevice`, rồi `server` khi `legacyAvailable`. `engine` chỉ nil khi không còn đường nào.
  - **`VoiceLanguage`:** `public enum VoiceLanguage: String, Codable, CaseIterable, Sendable { case vietnamese = "vi-VN", english = "en-US" }`, có `init(preferredLanguages: [String])`: danh sách có ngôn ngữ `vi` thì chọn `vietnamese`, không thì `english`. Lựa chọn của người dùng lưu trong UserDefaults.
  - **Quyền:** `public protocol VoicePermissionChecking: Sendable { func microphone() async -> Bool; func speech() async -> Bool }`. Mỗi hàm xin quyền nếu chưa từng hỏi.
  - **`VoiceInputModel`:** `@MainActor @Observable public final class VoiceInputModel`, gồm:
    - `enum Phase: Equatable { case idle, listening(text: String), cancelArmed(text: String), finishing, denied(VoicePermission), unavailable }`, với `VoicePermission` là `.microphone` hoặc `.speech`;
    - `init(transcriber: any SpeechTranscribing, permissions: any VoicePermissionChecking, capabilities: @escaping @Sendable (VoiceLanguage) async -> VoiceCapabilities, language: VoiceLanguage, contextualStrings: @escaping @MainActor () -> [String], latency: LatencyLog, clock: any Clock<Duration>)`;
    - `press() async`;
    - `drag(dx: Double, dy: Double)`:
      - `dx ≤ −80` → `cancelArmed`; quay lại `dx > −80` → `listening`;
      - `dy ≤ −60` khi chưa có chữ nào → đặt `wantsKeyboard = true` và huỷ nghe;
    - `release() async -> String?`: trả chữ cuối cùng khi không bị huỷ và không rỗng;
    - `firstWordLatency: Duration?`: từ lúc `press` tới lần cập nhật đầu tiên có chữ. Giá trị này cũng được ghi vào `LatencyLog` (`firstWord`);
    - `limitReached: Bool`: khi chữ vượt `ComposerValidation.maxBytes`, model tự dừng nghe, giữ phần nằm trong giới hạn và đặt cờ này.
  - **Khớp đáp án:** `extension PendingQuestion { public func option(matching transcript: String) -> PendingQuestionOption? }`.
    - Chuẩn hoá cả hai phía: bỏ dấu tiếng Việt, chuyển chữ thường, bỏ dấu câu.
    - Khớp khi:
      - hai chuỗi bằng nhau;
      - câu nói chứa label (label có ít nhất 2 ký tự);
      - câu nói chỉ số thứ tự: "1", "một", "thứ nhất", "đầu tiên", "first", "số hai", "cái thứ hai"…
    - Chỉ trả về khi đúng một đáp án khớp.
    - Không khớp đáp án nào (hoặc khớp nhiều hơn một) thì câu nói thành chữ tự do của câu hỏi đó (`QuestionDraft.setFreeText`). Sheet hiện chữ đó để người dùng xem lại rồi mới gửi, không tự gửi.

**Phần của app:**
- **`AudioCapture`:**
  - dùng tap trên input node của `AVAudioEngine`;
  - `AVAudioSession` category `.record`, mode `.measurement`, option `.duckOthers`;
  - kích hoạt session khi `press`; khi xong thì tắt với `.notifyOthersOnDeactivation`.
- **`LegacyTranscriber`:**
  - dùng `SFSpeechRecognizer(locale:)` và `SFSpeechAudioBufferRecognitionRequest`;
  - đặt `shouldReportPartialResults = true`, `requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition`, `addsPunctuation = true`, và `contextualStrings`.
- **`AnalyzerTranscriber`** (`@available(iOS 26, *)`):
  - dùng `SpeechTranscriber` có kết quả tạm (volatile), hoặc `DictationTranscriber` khi chỉ module này có locale đó trong `supportedLocales`;
  - tài nguyên ngôn ngữ cài qua `AssetInventory`. Trong lúc đang tải, lần bấm đó dùng `LegacyTranscriber`;
  - `SpeechAnalyzer(modules:)` với `AnalysisContext.contextualStrings`; âm thanh chuyển sang `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`.
- **`VoiceCapabilityProbe`:** hỏi hệ điều hành để dựng `VoiceCapabilities` cho một ngôn ngữ.
- **`contextualStrings`:** tên workspace của các phiên còn sống, cộng `["PR", "CI", "push", "pull request", "branch", "merge", "deploy", "commit", "Claude"]`.

**UI:**
- **`MicButton`:**
  - nút tròn 58 pt màu `#60a5fa`, biểu tượng mic màu `#0b1220`; giữ để nói;
  - trong lúc nói, chữ hiện ngay phía trên composer, kèm một thanh mức âm đơn giản;
  - kéo sang trái thì hiện "Thả để huỷ"; vuốt lên thì mở bàn phím;
  - haptic qua `sensoryFeedback`: lúc bắt đầu (`.impact(weight: .light)`), lúc gửi (`.success`), lúc huỷ (`.warning`);
  - khi VoiceOver bật, nút hoạt động kiểu bấm để bắt đầu, bấm lần nữa để gửi.
- **Gợi ý dưới mic:** "Giữ để nói · vuốt lên để gõ" / "Hold to talk · swipe up to type".
- **Sheet câu hỏi:** có nút mic "Trả lời bằng giọng nói". Câu nói được khớp bằng `option(matching:)` rồi đáp án đó được đánh dấu; app không tự gửi. Không khớp thì hiện "Không khớp đáp án nào, hãy chọn bằng tay" / "That didn't match an option; pick one by hand".
- **Sheet plan:** mic điền vào ô góp ý.
- **Cài đặt › Giọng nói:** chọn ngôn ngữ, kèm một dòng giải thích theo `engine`:
  - `analyzer` hoặc `onDevice`: "Nhận dạng ngay trên iPhone." / "Recognized on this iPhone.";
  - `server`: "iPhone này chưa nhận dạng được %@ ngay trên máy, nên giọng nói được gửi tới máy chủ của Apple để nhận dạng. ShellX không nhận giọng nói của bạn." / "This iPhone can't recognize %@ on device, so your voice goes to Apple's servers for recognition. ShellX never receives your voice.";
  - nil: "Lúc này không nhận dạng giọng nói được. Bạn vẫn gõ được." / "Speech recognition isn't available right now. You can still type."
- **Quyền bị từ chối:** "ShellX cần quyền micro và nhận dạng giọng nói để nghe bạn." / "ShellX needs microphone and speech recognition access to hear you.", kèm nút "Mở Cài đặt". Bàn phím luôn dùng được.
- **Chuỗi xin quyền trong Info.plist:**
  - micro: "ShellX nghe khi bạn giữ nút mic để nói với agent." / "ShellX listens while you hold the mic button to talk to your agents.";
  - nhận dạng giọng nói: "Apple chuyển giọng nói của bạn thành chữ để gửi cho agent." / "Apple turns your speech into text to send to your agents."

- [ ] **Step 1: Viết test fail.**
  - `VoiceCapabilitiesTests`:
    - `testAnalyzerPreferredWhenItSupportsLocale`;
    - `testOnDeviceBeforeServer`;
    - `testServerWhenNoOnDevice`;
    - `testNilOnlyWhenNothingAvailable`;
    - `testDefaultLanguageVietnameseWhenPreferred`.
  - `VoiceInputModelTests` (dùng `FakeTranscriber`):
    - `testPressStartsListeningAndStreamsText`;
    - `testReleaseReturnsFinalText`;
    - `testDragLeftThenReleaseCancels`;
    - `testSwipeUpBeforeWordsAsksKeyboard`;
    - `testEmptyTranscriptReturnsNil`;
    - `testDeniedMicrophoneShowsDenied`;
    - `testUnavailableNeverBlocksKeyboard`;
    - `testFirstWordLatencyRecorded`;
    - `testDictationStopsAtByteLimit`.
  - `OptionMatchingTests`:
    - `testMatchesIgnoringDiacriticsAndCase`: "postgres" khớp "Postgres", "giu route v1" khớp "Giữ route v1";
    - `testOrdinalPicksOption`: "cái thứ hai" chọn đáp án 2;
    - `testAmbiguousReturnsNil`;
    - `testNoMatchReturnsNil`.

  Chạy `dev.sh test core`. Kỳ vọng FAIL.
- [ ] **Step 2: Cài đặt.** Đọc các trang HIG "Buttons", "Playing haptics", "Requesting permission", "Accessibility".
- [ ] **Step 3: Chạy lại** `dev.sh test core`. Kỳ vọng PASS.
  - `VoiceCapabilityProbeTests`: `testProbeReturnsEngineForEnglish` (trên máy hoặc qua máy chủ, không nil khi có mạng).
  - `MicButtonRenderTests`: các trạng thái `idle`, `listening`, `cancelArmed`, `denied`.
  - Chạy `dev.sh test app` (iOS 26.2), rồi `dev.sh test app --runtime 18.4` để đi qua đường `SFSpeechRecognizer`. Kỳ vọng PASS.
- [ ] **Step 4: Đo trên iPhone thật** (`dev.sh device --demo`). Ghi vào ledger, mục D-iOS-2:
  - phiên bản iOS;
  - `SpeechTranscriber` và `DictationTranscriber` có `vi-VN` không;
  - `supportsOnDeviceRecognition` của `vi-VN`;
  - engine app đã chọn;
  - p50 và p95 của `firstWordLatency` qua 20 lần giữ mic nói "chạy test cho shellx rồi tạo PR" (mục tiêu < 300 ms);
  - chữ nhận được cho 5 câu mẫu: "sửa CI đỏ ở nhánh fix/relay", "tạo PR cho branch develop", "chạy test cmuxTests rồi push", "giữ route v1, đừng xoá", "merge main vào develop".

  Không đạt mục tiêu thì báo người dùng.
- [ ] **Step 5: Audit localization** (gồm `InfoPlist.xcstrings`), ghi kết quả và tên trang HIG vào commit.
- [ ] **Step 6: Commit** (`feat(shellx-ios): hold-to-talk voice input with Vietnamese recognition`).

### Task 10: Phát hành local (`release/mobile/`)

App Flutter, `release/mobile/ios.sh` và `android.sh` cũ đã bị xoá ở `e986a28cd4`. Task này viết lại phần iOS cho app Swift; Android nằm ngoài dự án.

**Files:**
- Create: `release/mobile/README.md`, `release/mobile/ios.sh`, `release/mobile/ExportOptions.plist`
- Create: `shellx-ios/ShellX/PrivacyInfo.xcprivacy`
- Modify: `shellx-ios/README.md` (mục phát hành trỏ sang `release/mobile/README.md`)

**Interfaces:**
- Consumes: `shellx-ios/Config/Version.xcconfig` và scheme `ShellX` (Task 1).
- Produces:
  - **`release/mobile/ios.sh [--upload | --check-app <path.app>]`:**
    - đọc `MARKETING_VERSION` và `CURRENT_PROJECT_VERSION` từ `Version.xcconfig`;
    - chạy `xcodebuild archive` (cấu hình Release, `generic/platform=iOS`, `-allowProvisioningUpdates`), rồi `-exportArchive` với `ExportOptions.plist`;
    - ipa đặt ở `build/release/ios/ShellX-<version>-<build>.ipa`;
    - từ chối ipa (hoặc app đưa vào `--check-app`) khi:
      - team ký khác `W4RF3W4VTZ`;
      - bundle id khác `com.shellx.prod`;
      - version hoặc build khác `Version.xcconfig`;
      - `get-task-allow` là true;
      - có `aps-environment` mà giá trị khác `production`;
      - có `.framework` trong `Frameworks/` (P3 không nhúng framework nào);
    - `--upload` export lại cùng archive với `destination upload`. Chỉ chạy khi người dùng bảo.
  - **`ExportOptions.plist`:** `method app-store-connect`, `teamID W4RF3W4VTZ`, `signingStyle automatic`, `destination export`, `uploadSymbols true`, `manageAppVersionAndBuildNumber false`.
  - **`PrivacyInfo.xcprivacy`:**
    - `NSPrivacyTracking = false`;
    - API lý do bắt buộc: `UserDefaults` với lý do `CA92.1`;
    - dữ liệu thu thập: địa chỉ email, dùng cho chức năng app, không dùng để theo dõi.
  - **`README.md`** ghi:
    - tăng `CURRENT_PROJECT_VERSION` trước mỗi lần upload;
    - 2.0.0 thay bản Flutter 1.0.0 trên cùng một app ở App Store Connect;
    - câu hỏi export compliance do người dùng trả lời: app tự cài Noise trên CryptoKit;
    - App Review cần một tài khoản demo và một video, vì app chỉ dùng được khi đã ghép cặp với Mac;
    - giữ `MIN_MOBILE` như hiện tại cho tới khi 2.0.0 đã lên store;
    - `aps-environment` sẽ thành bắt buộc từ P4.

- [ ] **Step 1: Kiểm khi chưa có script.** Chạy `release/mobile/ios.sh --check-app shellx-ios/.derived/Build/Products/Debug-iphonesimulator/ShellX.app`. Kỳ vọng thất bại vì chưa có script.
- [ ] **Step 2: Cài đặt** ba file và `PrivacyInfo.xcprivacy`.
- [ ] **Step 3: Chạy lại.**
  - `bash -n release/mobile/ios.sh`. Kỳ vọng exit 0.
  - Lệnh ở Step 1 (bản Debug cho simulator). Kỳ vọng exit 1, có in "bundle id is not com.shellx.prod".
  - `release/mobile/ios.sh` (không upload). Kỳ vọng in "team W4RF3W4VTZ, com.shellx.prod 2.0.0 (1)".
    - Nếu Xcode chưa đăng nhập team, hoặc cần tạo chứng chỉ mới, thì dừng và báo người dùng. Không tự tạo chứng chỉ khi người dùng chưa đồng ý.
- [ ] **Step 4: Commit** (`feat(release): local App Store build of the ShellX iOS app`).

### Task 11: Chạy trọn đường với Mac thật, đo độ trễ

**Files:**
- Create: `shellx-ios/ShellX/UI/Settings/LatencySection.swift` (`#if DEBUG`: hiện `LatencyLog.summary` của từng chỉ số)
- Modify: `shellx-ios/ShellX/UI/Settings/SettingsView.swift`
- Modify: `docs/superpowers/ledgers/shellx-ios.md` (thêm mục "P3 kết quả" và "Mang sang P3b/P4")
- Modify khi cần: code sửa lỗi phát hiện lúc chạy thật. Mỗi lỗi một commit, test tái hiện lỗi được commit trước bản sửa.

**Interfaces:**
- Consumes:
  - mọi task ở trên;
  - P2 Task 8–11: `shellx.link.debug_pairing_offer` (trả `{offer_uri}`) và `shellx.link.debug_pairing_approve`;
  - các nguồn dữ liệu của Mac cho câu hỏi, plan, phiên agent và chat.
- Produces: số đo và nhật ký trong ledger.

- [ ] **Step 1: Lấy P2 đầy đủ.** Chạy `git merge --no-edit feat/shellx-link-p2` sau khi P2 Task 11 đã commit, rồi `dev.sh test all`. Kỳ vọng PASS.
- [ ] **Step 2: Dựng môi trường local** như P2 Task 11 Step 2:
  - relay Node local với đủ 8 migration;
  - `cmux-relay` local dùng chung secret với relay;
  - Mac tag `link`, chạy với `SHELLX_REMOTE_MACHINES=1` và `SHELLX_API_BASE=http://127.0.0.1:8787`;
  - một tài khoản dev dùng một lần, như ledger mục "Spike P1".

  App chạy bằng `dev.sh sim --api http://127.0.0.1:8787`.
- [ ] **Step 3: Chạy trọn đường trên simulator.**
  1. Đăng nhập tài khoản dev trong app (gõ tay).
  2. Lấy mã ghép cặp: gọi `CMUX_TAG=link scripts/cmux-debug-cli.sh rpc shellx.link.debug_pairing_offer '{}'`, ghi trường `offer_uri` vào một file quyền 0600, rồi chạy `xcrun simctl openurl <udid> "$(cat <file>)"`. Không in URI ra màn hình. Xác nhận trong app, rồi bấm Đồng ý trên Mac. Kỳ vọng Mac hiện "Đã kết nối" trong app.
  3. Trong app Mac, cho Claude Code tạo lần lượt một yêu cầu quyền Bash, một `AskUserQuestion` và một plan. Trả lời cả ba từ app. Kỳ vọng Claude chạy tiếp sau mỗi lần, và thẻ ghim biến mất.
  4. Kiểm A1:
     - tạo thêm một thẻ rồi bấm Cho phép **trên Mac**. Kỳ vọng thẻ trên app biến mất trong < 2 s;
     - mở sheet câu hỏi trên app, rồi trả lời câu đó trên Mac. Kỳ vọng sheet báo "Đã được xử lý ở nơi khác".
  5. Từ màn chính, gửi "liệt kê file" tới phiên đó. Mở chi tiết agent và thấy câu trả lời. Bấm Dừng khi agent đang chạy.
  6. Thoát ShellX trên Mac. Kỳ vọng app báo offline, và nói hoặc gõ thì nhận ngay "<tên Mac> đang offline."
  7. Mở lại ShellX trên Mac, rồi gỡ iPhone trong sheet ghép cặp. Kỳ vọng app chuyển sang "Mac này đã gỡ iPhone" và không nối lại nữa.

  Ghi nhật ký ngắn vào ledger.
- [ ] **Step 4: iPhone thật qua relay.shellx.pro. Cần người dùng đồng ý trước.** Route điện thoại của relay chỉ có trên production sau khi P2 vào `main` và được deploy.
  - Được đồng ý: chạy `dev.sh device`, đăng nhập tài khoản thật, ghép với Mac (tag `link`, API production), rồi lặp lại các bước 3–6 của Step 3, một lần trên 4G (tắt Wi-Fi) và một lần trên Wi-Fi.
  - Không được: ghi vào ledger "chưa đo trên iPhone thật qua relay.shellx.pro". Phần giọng nói đã đo ở Task 9.
- [ ] **Step 5: Đo.** Dùng mục "Đo độ trễ" trong Cài đặt (bản Debug), 20 lần cho mỗi loại:
  - `replyRoundTrip`: cận trên của "bấm Cho phép → hook nhận quyết định", vì host chỉ trả `delivered` sau khi hook đã nhận;
  - `pendingArrival` và `sessionChangeArrival`;
  - xử lý trên Mac → thẻ trên app biến mất (bấm giờ bằng tay);
  - `launchToHome`.

  Ghi p50 và p95, so với §7.4. Không đạt thì báo người dùng.
- [ ] **Step 6: Cập nhật ledger.**
  - Mục "P3 kết quả": các bước đã chạy, số đo, lỗi gặp phải.
  - Mục "Mang sang":
    - P3b: kênh `terminal`; xem trước chữ đang viết (`streamingProse`);
    - P4: APNs, gỡ thông báo, `aps-environment`;
    - những gì đo được về trả lời tự do bằng giọng nói (tỉ lệ khớp đáp án, số lần người dùng sửa chữ).
- [ ] **Step 7: Commit** (`docs(shellx-ios): P3 end-to-end on a real Mac and latency results`).

---

**Ngoài phạm vi P3:**
- kênh `terminal` và xem trước chữ đang viết (plan P3b, xem D9);
- APNs, Notification Service Extension, gỡ thông báo (P4);
- skill và chip skill (P5);
- AI điều phối: câu tự do tự định tuyến, câu "hôm nay thế nào?" gộp từ nhiều Mac (P6);
- mở phiên hoặc workspace mới từ điện thoại (P5/P6, xem quyết định 1);
- đăng ký và xoá tài khoản trong app: khách hàng đã có tài khoản từ Mac, app chỉ đăng nhập;
- màn "cần cập nhật" theo `min_mobile` của `/v1/version`. Lệch phiên bản giao thức với Mac đã được báo qua trạng thái `needsUpdate`;
- iPad, Apple Watch, widget, Android, CI cho mobile;
- upload TestFlight hoặc App Store: chỉ làm khi người dùng bảo, theo `release/mobile/README.md`.
