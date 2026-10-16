# ShellX v1.0 — Kế hoạch 04: Desktop agent (`apps/desktop`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ứng dụng Flutter chạy nền ở menu bar (macOS 12+) / khay hệ thống (Windows 10 1809+): đăng nhập/đăng ký, onboarding, cửa sổ QR ghép nối, thu hồi, đổi mật khẩu, menu tray đúng spec §8.3, giữ máy không ngủ, tự khởi động, một bản duy nhất, kiểm tra phiên bản — là lớp giao diện + adapter nền tảng mỏng bên trên `shellx_core` và `shellx_agent`.

**Architecture:** Mọi logic giao thức/phiên nằm trong `shellx_core`/`shellx_agent` (plan 02/03), dùng **chỉ** qua chữ ký ở overview §5.1–5.6 (cộng `AgentRevoked` của plan 03). App gồm ba lớp: (1) adapter nền tảng sau các interface nhỏ (`FlutterPtyFactory`, `SecureKeyValueStore`, `KeepAwake`, `LaunchAtLogin`, `SingleInstanceLock`, `SystemNotifier`, `UrlOpener`, `TrayHost`, `WindowHost`); (2) `AgentController` (Riverpod `Notifier<AgentViewState>`) giữ vòng đời đăng nhập và một `AgentRuntime` (seam bọc `RelayConnection` + `SessionManager` + `AgentService`) để test controller bằng fake; (3) một cửa sổ Flutter duy nhất do `WindowRouter` điều khiển (ẩn khi không có gì mở) và menu tray dựng thuần từ state.

**Tech Stack:** Flutter 3.41.7 / Dart 3.11.5 (pub workspace), `flutter_riverpod` 3.3.2, `flutter_pty` 0.4.2, `tray_manager` 0.5.3, `window_manager` 0.5.2, `launch_at_startup` 0.5.1, `flutter_secure_storage` 10.3.4, `shared_preferences` 2.5.5, `local_notifier` 0.1.6, `qr_flutter` 4.1.0, `win32` 5.15.0, `ffi` 2.2.0, `package_info_plus` 9.0.1, `path_provider` 2.1.6, `http` ^1.5.0, `flutter_localizations`/`intl` 0.20.2 (gen-l10n), `integration_test`.

**Spec:** `docs/superpowers/specs/2026-09-25-shellx-v1-design.md` · **Hợp đồng bắt buộc:** `docs/superpowers/plans/2026-09-25-shellx-v1-00-overview.md`

---

## Global Constraints

Mọi mục ở **overview §2** áp dụng nguyên văn (Dart `^3.11.0`, Flutter 3.41; macOS 12+, Windows 10 bản 1809+; mã ghép nối 32 byte / một lần / 5 phút; mật khẩu 8–128; mã đóng 4001/4002/4003; không log payload/token/mật khẩu; song ngữ Việt–Anh; Conventional Commits, mỗi task ≥ 1 commit). Thêm các giá trị riêng của plan này, chép từ spec:

- "Chỉ một bản agent chạy cùng lúc (khóa file trong thư mục dữ liệu ứng dụng)." (§8.2)
- "macOS dùng `LSUIElement = true` (không hiện Dock)." (§8.2) · "không bật App Sandbox", "bật hardened runtime", "ký Developer ID" (§8.5).
- Onboarding: "bật 'Khởi động cùng hệ thống' (mặc định bật); trên macOS hướng dẫn cấp **Full Disk Access** (nút mở `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`); giải thích rằng gập nắp laptop thì máy vẫn ngủ." (§8.2)
- Menu tray đúng thứ tự §8.3: `● Đã kết nối — user@email.com` / `✓ Cho phép truy cập từ xa` / `Phiên đang hoạt động (n) ▸ [từng phiên: Đóng] · Đóng tất cả` / `Ghép nối điện thoại…` / `Thiết bị đã ghép ▸ [từng thiết bị: Thu hồi]` / `✓ Giữ máy không ngủ` / `✓ Khởi động cùng hệ thống` / `Đổi mật khẩu…` / `Đăng xuất` / `Thoát`.
- "Icon tray có 3 trạng thái: bình thường, mất kết nối (xám), đang có điện thoại điều khiển (màu nổi)."
- "Thông báo hệ thống mỗi khi một điện thoại mở phiên mới ('<tên điện thoại> vừa mở phiên terminal'). Mặc định bật."
- "Tắt 'Cho phép truy cập từ xa': ngắt WebSocket tới relay và đóng mọi phiên; hỏi xác nhận nếu đang có phiên. Trạng thái bật/tắt được nhớ qua các lần khởi động."
- "Giữ máy không ngủ (mặc định bật): macOS: tiến trình con `caffeinate -i -w <pid agent>`. Windows: `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)`. Chỉ chặn máy tự ngủ khi để yên; không chặn ngủ khi gập nắp."
- "Đổi mật khẩu…: cửa sổ nhập mật khẩu mới hai lần." Chỉ token agent, không cần mật khẩu cũ (§5.2).
- Mã ghép nối "hết hạn sau 5 phút hoặc khi đóng cửa sổ QR. Mỗi lúc chỉ có tối đa một mã hiệu lực." Sau `pair.confirm`: "hiện thông báo 'Đã ghép nối với <tên điện thoại>' và đóng cửa sổ QR." (§5.3)
- Đăng xuất trên agent: "xóa token, xóa các bản ghi ghép nối của agent trong D1, xóa danh sách tin cậy cục bộ, đóng mọi phiên." (§5.2)
- **4002 / 401 (spec §5.2 đã sửa, phán quyết plan 03):** "luôn: xóa token, đóng mọi phiên, **giữ** khóa thiết bị và danh sách tin cậy, rồi hiện cửa sổ đăng nhập. Khi đăng nhập lại thành công, nếu `user_id` khác `user_id` đã lưu thì xóa danh sách tin cậy; cùng `user_id` thì giữ nguyên ghép nối." Tín hiệu: `AgentRevoked` (plan 03) và/hoặc `RelayConnectionState.revoked`. 4001: "Không tự kết nối lại".
- Lưu trữ: "Secure storage: khóa bí mật thiết bị, token, `device_id`, `user_id`, email, danh sách tin cậy. `shared_preferences`: các công tắc cài đặt." (§8.4)
- Cập nhật: "agent gọi `/v1/version` khi khởi động và mỗi 24 giờ; có bản mới thì hiện thông báo kèm link tải" (§14); dưới `min_agent` → "Cần cập nhật app" (§12). HTTP 429 → "Thử lại sau ít phút." (§12)
- Đóng phiên = "đóng PTY và kết thúc toàn bộ cây tiến trình con" (§7).
- **Ràng buộc từ plan 06 (phát hành):** macOS `ShellX.app`, bundle id `pro.shellx.desktop`; Windows `ShellX.exe` (`BINARY_NAME`, `Runner.rc`); giá trị Run của `launch_at_startup` tên đúng `ShellX`; `version:` trong `apps/desktop/pubspec.yaml` là nguồn phiên bản phát hành; cả `Release.entitlements` và `DebugProfile.entitlements` tắt App Sandbox; **không** entitlement cần provisioning profile (không `keychain-access-groups`); `apps/desktop/windows/runner/resources/app_icon.ico` phải tồn tại (flutter create sinh sẵn).
- **Ràng buộc workspace:** app Flutter trong workspace kéo theo ghim của Flutter SDK (`test_api` 0.7.10 → `test` 1.30.0, `meta` 1.17.0). App **không** khai báo `test`. Lệnh chuẩn (overview §3): `flutter test` và `flutter test integration_test -d macos|windows` trong `apps/desktop`, sau `flutter pub get` ở gốc.

## Review Focus

Năm tình huống spec ngụ ý nhưng dễ làm hỏng trải nghiệm, xếp theo khả năng xảy ra; mỗi dòng có test trong task sở hữu.

1. **Token bị thu hồi (4002/401 — đổi mật khẩu ở máy khác hoặc xóa tài khoản) khi agent đang chạy** — người dùng mong: mọi phiên đóng, cửa sổ đăng nhập hiện ra kèm lời giải thích, đăng nhập lại cùng tài khoản thì điện thoại vẫn dùng được (không phải ghép lại), tài khoản khác thì ghép nối cũ bị xóa; tín hiệu đến hai lần chỉ báo một lần. Test: Task 7 (`token revoked (4002 / 401)` ×3), Task 9 (`4002 while running brings the login window back`), Task 10 (`after a 4002 the login window explains the sign-out`).
2. **Đóng cửa sổ QR (hoặc mã hết hạn) trước khi điện thoại quét** — mã phải mất hiệu lực ngay; QR hết hạn không được tiếp tục hiển thị như còn dùng được. Test: Task 6 (`pairing QR … cancel invalidates it`), Task 9 (`closing the QR window invalidates the pairing code`, `a confirm on top of the QR window does not cancel pairing`), Task 10 (`an expired code hides the QR and offers a new one`).
3. **Không có mạng lúc khởi động hoặc vừa thức dậy sau khi máy ngủ** — app vẫn khởi động, vẫn đăng nhập, icon xám "Mất kết nối — đang thử lại…", kết nối lại ngay khi thức dậy, kiểm tra phiên bản thất bại thì thử lại khi có kết nối. Test: Task 5 (`WakeDetector …`), Task 7 (`relay offline at startup…`, `computer woke up…`, `a failed check is retried once the relay connects`), Task 8 (`status line follows the relay…`).
4. **Agent được mở hai lần** (mục đăng nhập tự khởi động + người dùng bấm đúp icon) — bản thứ hai phải thoát trước khi kết nối relay (nếu không hai bản cùng `device_id` sẽ đá nhau bằng 4001), bản đang chạy tự "hiện ra". Test: Task 5 (`a second process cannot take the lock…`, `a second launch can ask the running instance to come forward`).
5. **Windows với tên người dùng có dấu (`C:\Users\Nguyễn`)** — `flutter_pty` 0.4.2 biến mỗi byte UTF-8 thành một ký tự UTF-16 nên thư mục làm việc/biến môi trường có dấu bị hỏng; người dùng mong shell vẫn mở đúng ở thư mục home. Test: Task 3 (`Windows quotes the executable and shortens non-ASCII paths`, `asciiSafe*`, integration `environment and a Vietnamese working directory reach the shell` — chạy thật trên Windows CI).

## Sự thật đã xác minh (đọc mã nguồn package trong `~/.pub-cache`, 2026-09-25)

- **Phiên bản:** `flutter pub add` với Dart 3.11.5 cho: `flutter_riverpod` 3.3.2 (3.4.1+ đòi Dart 3.12), `tray_manager` 0.5.3 (0.7.0 đòi Dart 3.13), `win32` 5.15.0 và `flutter_secure_storage` 10.3.4 (11.x đòi `win32` ^6, xung đột với `launch_at_startup` 0.5.1 → `win32_registry` 2 → `win32` ^5), `package_info_plus` 9.0.1 (10.x đòi `win32` ^6). Toàn bộ workspace (stub `shellx_core`/`shellx_agent` + app) đã giải được; `test` về 1.30.0.
- **flutter_pty 0.4.2:** `Pty.start(executable, {arguments, workingDirectory, environment, rows = 25, columns = 80, ackRead})`; **`resize(int rows, int cols)` — hàng trước**; `kill([signal])` = `Process.killPid(pid)` chỉ giết shell. macOS: `forkpty` gọi `setsid()` (shell là trưởng session), `putenv` chồng lên env kế thừa; master fd không bao giờ đóng (rò 1 fd/phiên, chấp nhận). Windows: ConPTY, **không bao giờ gọi `ClosePseudoConsole`** (conhost.exe + pipe rò mỗi phiên), `Sleep(1000)` đồng bộ trong `pty_create` (mở phiên chặn isolate UI ~1 s), dòng lệnh/env/thư mục được ghép bằng cách **ép từng byte UTF-8 thành WCHAR** và nối tham số bằng dấu cách không trích dẫn. `output` là `ReceivePort` (single-subscription) được đóng khi nhận exit code.
- **Việc `FlutterPtyAdapter.kill()` làm chính xác:** macOS — chụp bảng tiến trình (`/bin/ps -A -o pid=,ppid=,comm=`), gửi **SIGHUP** cho shell và mọi hậu duệ, đợi 2 s, chụp lại, gửi **SIGKILL** cho những tiến trình trong cây còn sống và hậu duệ mới; không bao giờ gửi cho pid ≤ 1 hay chính agent; tiến trình đã tự tách (double-fork về launchd) trước lần chụp đầu thì thoát được. Windows — `taskkill /PID <shell> /T /F` (mọi hậu duệ còn liên kết parent-pid), rồi `taskkill /PID <conhost> /F` cho conhost.exe mà `CreatePseudoConsole` tạo làm con của agent (xác định bằng Toolhelp32 trước/sau `Pty.start`); conhost cũng bị dừng khi shell tự thoát. `output` luôn đóng ≤ 500 ms sau khi tiến trình thoát (SessionManager chờ tối đa 2 s).
- **tray_manager 0.5.3:** menu chỉ bật khi gọi `popUpContextMenu()` trong `onTrayIconMouseDown`/`onTrayIconRightMouseDown`; `setIcon` macOS đọc asset qua `rootBundle` (PNG, `isTemplate`), Windows `LoadImage` file `.ico` ở `data/flutter_assets/<path>`; `MenuItem.id` sinh mới mỗi lần dựng → plan gán id ổn định theo key.
- **window_manager 0.5.2:** ẩn khi khởi động = macOS override `order(_:relativeTo:)` gọi `hiddenWindowAtLaunch()`; Windows bỏ `this->Show()` trong `SetNextFrameCallback`. `show()` trên macOS gọi `NSApp.activate(ignoringOtherApps: true)` (cần cho app `LSUIElement`).
- **launch_at_startup 0.5.1:** Windows ghi `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` giá trị `appName`; macOS **chỉ** gọi MethodChannel `launch_at_startup` mà app phải tự cài → plan cài bằng `SMAppService.mainApp` (macOS 13+) và LaunchAgent plist `~/Library/LaunchAgents/pro.shellx.desktop.plist` (macOS 12).
- **flutter_secure_storage 10.3.4:** macOS mặc định dùng *data-protection keychain* (cần `keychain-access-groups` + provisioning profile) → plan đặt `MacOsOptions(usesDataProtectionKeychain: false, accountName: 'pro.shellx.desktop')` (login keychain, không cần entitlement). Windows: **tệp mã hóa DPAPI** `flutter_secure_storage.dat` trong thư mục app support (không phải Credential Manager như spec §5.1 ghi).
- **local_notifier 0.1.6:** macOS `NSUserNotification` (deprecated nhưng chạy); Windows WinToast, AUMID = `appName` = `ShellX`, cần `setup()` trước.
- **Đã chạy thật trên macOS (arm64, macOS 26):** `flutter test integration_test -d macos` (6/6), bản build debug `ShellX.app` (bundle id `pro.shellx.desktop`, `LSUIElement`, sandbox tắt) khởi động 25 s không lỗi.

## Cấu trúc file

```
apps/desktop/
  pubspec.yaml  l10n.yaml  analysis_options.yaml(flutter create)
  assets/tray/tray_{normal,offline,active}.{png,ico}     # Task 8, sinh bằng tool/gen_tray_icons.dart
  tool/gen_tray_icons.dart
  lib/main.dart                                           # Task 11: nối mọi thứ
  lib/l10n/app_en.arb app_vi.arb app_localizations*.dart  # Task 2
  lib/src/config.dart                                     # URL relay
  lib/src/l10n/locale.dart
  lib/src/platform/system_info.dart                       # Task 1
  lib/src/platform/pty/{process_table,process_tree_killer,windows_text,windows_native,flutter_pty_factory}.dart  # Task 3
  lib/src/platform/{secure_key_value_store,settings_store}.dart                                             # Task 4
  lib/src/platform/{keep_awake,launch_at_login,single_instance,notifier,url_opener,wake_detector}.dart      # Task 5
  lib/src/agent/{storage_keys,agent_runtime,update_check,agent_state}.dart   # Task 6
  lib/src/agent/{desktop_services,agent_controller}.dart                      # Task 7
  lib/src/tray/{tray_action,tray_menu,tray_presenter}.dart                    # Task 8
  lib/src/ui/{window_router,window_coordinator,window_host}.dart, lib/src/tray/tray_actions.dart  # Task 9
  lib/src/ui/{form_rules,app}.dart, lib/src/ui/pages/*.dart                   # Task 10
  test/…  integration_test/pty_test.dart
  macos/Runner/{Info.plist,*.entitlements,AppDelegate.swift,MainFlutterWindow.swift,Configs/AppInfo.xcconfig}, macos/Podfile, macos/Runner.xcodeproj/project.pbxproj
  windows/CMakeLists.txt, windows/runner/{Runner.rc,main.cpp,flutter_window.cpp}
```

Mọi lệnh bên dưới chạy từ `apps/desktop` trừ khi ghi khác. Sau khi viết code Dart, chạy `dart format lib test integration_test tool` trước commit.

---

### Task 1: Dựng app, workspace, cấu hình macOS/Windows

**Files:**
- Create (flutter create): `apps/desktop/**`
- Delete: `apps/desktop/pubspec.lock`, `apps/desktop/README.md`, `apps/desktop/shellx_desktop.iml`, `apps/desktop/test/widget_test.dart`
- Modify: `pubspec.yaml` (gốc, thêm 1 dòng `workspace:`), `apps/desktop/pubspec.yaml`, `apps/desktop/lib/main.dart`
- Modify: `apps/desktop/macos/Runner/{Info.plist,DebugProfile.entitlements,Release.entitlements,AppDelegate.swift,MainFlutterWindow.swift,Configs/AppInfo.xcconfig}`, `apps/desktop/macos/Podfile`, `apps/desktop/macos/Runner.xcodeproj/project.pbxproj`
- Modify: `apps/desktop/windows/CMakeLists.txt`, `apps/desktop/windows/runner/{Runner.rc,main.cpp,flutter_window.cpp}`
- Create: `apps/desktop/lib/src/platform/system_info.dart`
- Test: `apps/desktop/test/platform/system_info_test.dart`

**Interfaces:**
- Consumes: gốc workspace `pubspec.yaml` (plan 02), `shellx_core`, `shellx_agent` (plan 02/03, resolve bằng `any` trong workspace).
- Produces: `const int kMinWindowsBuild = 17763;` `int? windowsBuildNumber(String operatingSystemVersion)`; `bool isSupportedWindowsBuild(String operatingSystemVersion)`; `String deviceNameFromHostname(String hostname)`. Tên sản phẩm `ShellX.app` / `ShellX.exe`, bundle id `pro.shellx.desktop`, kênh MethodChannel `launch_at_startup` (`launchAtStartupIsEnabled` → bool, `launchAtStartupSetEnabled {setEnabledValue: bool}`).

- [ ] **Step 1: Tạo project và đưa vào workspace**

Từ gốc repo:

```bash
flutter create --platforms=macos,windows --org pro.shellx --project-name shellx_desktop apps/desktop
rm -f apps/desktop/pubspec.lock apps/desktop/README.md apps/desktop/shellx_desktop.iml apps/desktop/test/widget_test.dart
```

Thêm đúng một dòng vào danh sách `workspace:` của `pubspec.yaml` gốc (giữ nguyên các dòng của plan khác):

```yaml
  - apps/desktop
```

Thay toàn bộ `apps/desktop/pubspec.yaml` (Task 2 thêm `generate: true`, Task 8 thêm `assets:`):

```yaml
name: shellx_desktop
description: "ShellX desktop agent for macOS and Windows."
publish_to: none
version: 1.0.0+1
resolution: workspace

environment:
  sdk: ^3.11.0
  flutter: ">=3.41.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  ffi: ^2.2.0
  flutter_pty: ^0.4.2
  flutter_riverpod: ^3.3.2
  flutter_secure_storage: ^10.3.4
  http: ^1.5.0
  intl: ^0.20.2
  launch_at_startup: ^0.5.1
  local_notifier: ^0.1.6
  package_info_plus: ^9.0.1
  path_provider: ^2.1.6
  qr_flutter: ^4.1.0
  shared_preferences: ^2.5.5
  shellx_agent: any
  shellx_core: any
  tray_manager: ^0.5.3
  win32: ^5.15.0
  window_manager: ^0.5.2

dev_dependencies:
  flutter_lints: ^6.0.0
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  shared_preferences_platform_interface: ^2.4.1

flutter:
  uses-material-design: true
```

Thay `apps/desktop/lib/main.dart` (Task 11 thay bằng bản thật):

```dart
import 'package:flutter/widgets.dart';

// Minimal entry point until Task 11 wires the agent.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
}
```

Chạy từ gốc repo: `flutter pub get` — Expected: `Got dependencies`, và `apps/desktop/macos/Podfile` được tạo.

- [ ] **Step 2: Viết test thất bại cho `system_info`**

`apps/desktop/test/platform/system_info_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/system_info.dart';

void main() {
  test('parses the Windows build and enforces 1809 (17763)', () {
    expect(windowsBuildNumber('"Windows 10 Pro" 10.0 (Build 19045)'), 19045);
    expect(
      isSupportedWindowsBuild('"Windows 10 Pro" 10.0 (Build 17763)'),
      isTrue,
    );
    expect(
      isSupportedWindowsBuild('"Windows 10 Pro" 10.0 (Build 17134)'),
      isFalse,
    );
    expect(isSupportedWindowsBuild('something else'), isTrue);
  });

  test('device name drops .local and is never empty', () {
    expect(
      deviceNameFromHostname('Phus-MacBook-Pro.local'),
      'Phus-MacBook-Pro',
    );
    expect(deviceNameFromHostname('DESKTOP-7K2Q'), 'DESKTOP-7K2Q');
    expect(deviceNameFromHostname('  '), 'Computer');
    expect(deviceNameFromHostname('a' * 80), hasLength(64));
  });
}
```

- [ ] **Step 3: Chạy test, xác nhận thất bại**

Run: `flutter test test/platform/system_info_test.dart`
Expected: FAIL — `Error when reading 'lib/src/platform/system_info.dart': No such file or directory`.

- [ ] **Step 4: Cài đặt `system_info.dart`**

`apps/desktop/lib/src/platform/system_info.dart`:

```dart
/// Minimum Windows build: Windows 10 1809, the first with ConPTY (spec §3.1).
const int kMinWindowsBuild = 17763;

/// Parses the build number out of dart:io `Platform.operatingSystemVersion`
/// on Windows, e.g. `"Windows 10 Pro" 10.0 (Build 19045)`.
int? windowsBuildNumber(String operatingSystemVersion) {
  final match = RegExp(r'Build (\d+)').firstMatch(operatingSystemVersion);
  return match == null ? null : int.parse(match[1]!);
}

/// Unknown formats are allowed rather than locking the user out.
bool isSupportedWindowsBuild(String operatingSystemVersion) {
  final build = windowsBuildNumber(operatingSystemVersion);
  return build == null || build >= kMinWindowsBuild;
}

/// Device name sent to the relay (spec §5.2: the hostname), without the
/// macOS `.local` suffix, at most 64 characters.
String deviceNameFromHostname(String hostname) {
  var name = hostname.trim();
  if (name.toLowerCase().endsWith('.local')) {
    name = name.substring(0, name.length - '.local'.length);
  }
  if (name.isEmpty) return 'Computer';
  return name.length > 64 ? name.substring(0, 64) : name;
}
```

- [ ] **Step 5: Chạy test, xác nhận qua**

Run: `flutter test test/platform/system_info_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: Cấu hình macOS**

```bash
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" macos/Runner/Info.plist
sed -i.bak "s/platform :osx, '10.15'/platform :osx, '12.0'/" macos/Podfile && rm macos/Podfile.bak
sed -i.bak -e 's/MACOSX_DEPLOYMENT_TARGET = 10.15;/MACOSX_DEPLOYMENT_TARGET = 12.0;/g' \
  -e 's/pro\.shellx\.shellxDesktop\.RunnerTests/pro.shellx.desktop.RunnerTests/g' \
  macos/Runner.xcodeproj/project.pbxproj && rm macos/Runner.xcodeproj/project.pbxproj.bak
```

`macos/Runner/Configs/AppInfo.xcconfig` (thay toàn bộ):

```ini
// Application-level settings for the Runner target.
//
// This may be replaced with something auto-generated from metadata (e.g., pubspec.yaml) in the
// future. If not, the values below would default to using the project name when this becomes a
// 'flutter create' template.

// The application's name. By default this is also the title of the Flutter window.
PRODUCT_NAME = ShellX

// The application's bundle identifier
PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop

// The copyright displayed in application information
PRODUCT_COPYRIGHT = Copyright © 2026 pro.shellx. All rights reserved.
```

`macos/Runner/DebugProfile.entitlements` (sandbox tắt; `allow-jit` chỉ cho debug):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
</dict>
</plist>
```

`macos/Runner/Release.entitlements` (sandbox tắt, chỉ network client — tương thích hardened runtime, không cần provisioning profile):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
</plist>
```

`macos/Runner/AppDelegate.swift`:

```swift
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // ShellX lives in the menu bar; closing or hiding its window must not quit it.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
```

`macos/Runner/MainFlutterWindow.swift` (ẩn cửa sổ khi khởi động + cài kênh `launch_at_startup` mà package yêu cầu trên macOS):

```swift
import Cocoa
import FlutterMacOS
import ServiceManagement
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    LaunchAtLoginChannel.register(
      messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  // Keep the window hidden at launch; Dart decides when to show it.
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}

/// Implements the `launch_at_startup` channel expected by package
/// launch_at_startup on macOS: SMAppService on macOS 13+, a per-user
/// LaunchAgent plist on macOS 12.
enum LaunchAtLoginChannel {
  static let label = "pro.shellx.desktop"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "launch_at_startup", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "launchAtStartupIsEnabled":
        result(isEnabled())
      case "launchAtStartupSetEnabled":
        let enabled = (call.arguments as? [String: Any])?["setEnabledValue"] as? Bool ?? false
        do {
          try setEnabled(enabled)
          result(nil)
        } catch {
          result(FlutterError(code: "launch_at_login", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static var agentPlistURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/\(label).plist")
  }

  static func isEnabled() -> Bool {
    if #available(macOS 13.0, *) {
      return SMAppService.mainApp.status == .enabled
    }
    return FileManager.default.fileExists(atPath: agentPlistURL.path)
  }

  static func setEnabled(_ enabled: Bool) throws {
    if #available(macOS 13.0, *) {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      return
    }
    let url = agentPlistURL
    if enabled {
      let plist: [String: Any] = [
        "Label": label,
        "ProgramArguments": [Bundle.main.executablePath ?? ""],
        "RunAtLoad": true,
        "ProcessType": "Interactive",
      ]
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let data = try PropertyListSerialization.data(
        fromPropertyList: plist, format: .xml, options: 0)
      try data.write(to: url, options: .atomic)
    } else if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }
}
```

- [ ] **Step 7: Cấu hình Windows (tên `ShellX.exe`, ẩn khi khởi động)**

```bash
sed -i.bak 's/^set(BINARY_NAME "shellx_desktop")/set(BINARY_NAME "ShellX")/' windows/CMakeLists.txt && rm windows/CMakeLists.txt.bak
sed -i.bak -e 's/"FileDescription", "shellx_desktop"/"FileDescription", "ShellX"/' \
  -e 's/"InternalName", "shellx_desktop"/"InternalName", "ShellX"/' \
  -e 's/"OriginalFilename", "shellx_desktop.exe"/"OriginalFilename", "ShellX.exe"/' \
  -e 's/"ProductName", "shellx_desktop"/"ProductName", "ShellX"/' windows/runner/Runner.rc && rm windows/runner/Runner.rc.bak
sed -i.bak 's/window.Create(L"shellx_desktop", origin, size)/window.Create(L"ShellX", origin, size)/' windows/runner/main.cpp && rm windows/runner/main.cpp.bak
perl -0pi -e 's/  flutter_controller_->engine\(\)->SetNextFrameCallback\(\[&\]\(\) \{\n    this->Show\(\);\n  \}\);/  \/\/ ShellX starts hidden in the tray; Dart shows the window via window_manager.\n  flutter_controller_->engine()->SetNextFrameCallback([&]() {});/' windows/runner/flutter_window.cpp
grep -n 'ShellX' windows/CMakeLists.txt windows/runner/Runner.rc windows/runner/main.cpp windows/runner/flutter_window.cpp
```

Expected: 7 dòng khớp (`BINARY_NAME "ShellX"`, 4 dòng `Runner.rc`, `L"ShellX"`, comment trong `flutter_window.cpp`). `CompanyName` giữ `pro.shellx` (thư mục dữ liệu Windows: `%APPDATA%\pro.shellx\ShellX`). Windows 10 1809 được bảo đảm ở runtime (Task 11, `isSupportedWindowsBuild`) và bởi `MinVersion=10.0.17763` trong bộ cài của plan 06.

- [ ] **Step 8: Build và kiểm tra bundle**

```bash
flutter build macos --debug
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" -c "Print :LSUIElement" -c "Print :LSMinimumSystemVersion" build/macos/Build/Products/Debug/ShellX.app/Contents/Info.plist
codesign -d --entitlements - --xml build/macos/Build/Products/Debug/ShellX.app | plutil -p - | grep sandbox
```

Expected: `✓ Built build/macos/Build/Products/Debug/ShellX.app`; in ra `pro.shellx.desktop`, `true`, `12.0`; `"com.apple.security.app-sandbox" => false`.

- [ ] **Step 9: Commit**

```bash
cd ../..
git add pubspec.yaml apps/desktop
git add pubspec.lock 2>/dev/null || true
git commit -m "feat(desktop): scaffold ShellX tray app for macOS and Windows"
```

---

### Task 2: Đa ngôn ngữ (gen-l10n, vi + en)

**Files:**
- Create: `apps/desktop/l10n.yaml`, `apps/desktop/lib/l10n/app_en.arb`, `apps/desktop/lib/l10n/app_vi.arb`, `apps/desktop/lib/src/l10n/locale.dart`
- Generate + commit: `apps/desktop/lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_vi.dart`
- Modify: `apps/desktop/pubspec.yaml` (mục `flutter:`)
- Test: `apps/desktop/test/l10n/l10n_test.dart`

**Interfaces:**
- Produces: `package:shellx_desktop/l10n/app_localizations.dart` → `AppLocalizations` (mọi chuỗi hiển thị dưới đây, getter không-null), `AppLocalizations.localizationsDelegates`, `AppLocalizations.supportedLocales`, `AppLocalizations lookupAppLocalizations(Locale)`; `lib/src/l10n/locale.dart` → `const Locale kVietnamese`, `const Locale kEnglish`, `Locale resolveAppLocale(List<Locale> preferred)`.

- [ ] **Step 1: Viết test thất bại**

`apps/desktop/test/l10n/l10n_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/l10n/locale.dart';

Map<String, Object?> _arb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, Object?>;

void main() {
  test('Vietnamese when the system prefers it, English otherwise', () {
    expect(resolveAppLocale(const [Locale('vi', 'VN')]), const Locale('vi'));
    expect(
      resolveAppLocale(const [Locale('fr'), Locale('vi')]),
      const Locale('vi'),
    );
    expect(resolveAppLocale(const [Locale('en', 'US')]), const Locale('en'));
    expect(resolveAppLocale(const [Locale('ja')]), const Locale('en'));
    expect(resolveAppLocale(const []), const Locale('en'));
  });

  test('both ARB files define exactly the same non-empty messages', () {
    final en = _arb('app_en.arb');
    final vi = _arb('app_vi.arb');
    Set<String> keys(Map<String, Object?> arb) =>
        arb.keys.where((k) => !k.startsWith('@')).toSet();
    expect(keys(vi), keys(en));
    for (final key in keys(en)) {
      expect((en[key] as String).trim(), isNotEmpty, reason: 'en $key');
      expect((vi[key] as String).trim(), isNotEmpty, reason: 'vi $key');
    }
  });

  test('Vietnamese strings match the spec wording', () {
    final vi = lookupAppLocalizations(const Locale('vi'));
    expect(
      vi.trayStatusConnected('user@email.com'),
      'Đã kết nối — user@email.com',
    );
    expect(vi.trayRemoteAccess, 'Cho phép truy cập từ xa');
    expect(vi.traySessions(2), 'Phiên đang hoạt động (2)');
    expect(vi.traySessionClose, 'Đóng');
    expect(vi.trayCloseAll, 'Đóng tất cả');
    expect(vi.trayPairPhone, 'Ghép nối điện thoại…');
    expect(vi.trayPairedDevices, 'Thiết bị đã ghép');
    expect(vi.trayRevoke, 'Thu hồi');
    expect(vi.trayKeepAwake, 'Giữ máy không ngủ');
    expect(vi.trayLaunchAtStartup, 'Khởi động cùng hệ thống');
    expect(vi.trayChangePassword, 'Đổi mật khẩu…');
    expect(vi.traySignOut, 'Đăng xuất');
    expect(vi.trayQuit, 'Thoát');
    expect(vi.notifySessionOpened('iPhone'), 'iPhone vừa mở phiên terminal');
    expect(vi.notifyPaired('iPhone'), 'Đã ghép nối với iPhone');
    expect(vi.errorRateLimited, 'Thử lại sau ít phút.');
    expect(vi.notifyUpdateRequiredTitle, 'Cần cập nhật app');
  });

  test('plural and select messages render in both languages', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final vi = lookupAppLocalizations(const Locale('vi'));
    expect(en.confirmRemoteOffBody(1), '1 open session will be closed.');
    expect(en.confirmRemoteOffBody(3), '3 open sessions will be closed.');
    expect(vi.confirmRemoteOffBody(3), '3 phiên đang mở sẽ bị đóng.');
    expect(en.onboardingTrayHint('macos'), contains('menu bar'));
    expect(en.onboardingTrayHint('windows'), contains('system tray'));
  });
}
```

- [ ] **Step 2: Chạy test, xác nhận thất bại**

Run: `flutter test test/l10n/l10n_test.dart`
Expected: FAIL — `Error when reading 'lib/l10n/app_localizations.dart': No such file or directory`.

- [ ] **Step 3: Thêm cấu hình và toàn bộ chuỗi**

Trong `apps/desktop/pubspec.yaml`, mục `flutter:` trở thành:

```yaml
flutter:
  uses-material-design: true
  generate: true
```

`apps/desktop/l10n.yaml`:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false
```

`apps/desktop/lib/l10n/app_en.arb` (template, có metadata placeholder):

```json
{
  "@@locale": "en",
  "appTitle": "ShellX",
  "actionCancel": "Cancel",
  "actionClose": "Close",
  "authSignInTitle": "Sign in to ShellX",
  "authRegisterTitle": "Create a ShellX account",
  "authEmailLabel": "Email",
  "authPasswordLabel": "Password",
  "authConfirmPasswordLabel": "Re-enter password",
  "authSignInButton": "Sign in",
  "authRegisterButton": "Create account",
  "authSwitchToRegister": "No account yet? Create one",
  "authSwitchToSignIn": "Already have an account? Sign in",
  "authForgotPasswordHint": "Forgot your password? Open ShellX on a computer that is still signed in and choose “Change password…” from its menu.",
  "authSignedOutNotice": "You were signed out. Sign in again.",
  "errorEmailInvalid": "Enter a valid email address.",
  "errorPasswordLength": "Password must be 8–128 characters.",
  "errorPasswordMismatch": "Passwords do not match.",
  "errorDisposableEmail": "Temporary email addresses are not allowed. Use a permanent address.",
  "errorEmailTaken": "This email is already registered. Sign in instead.",
  "errorInvalidCredentials": "Incorrect email or password.",
  "errorRateLimited": "Try again in a few minutes.",
  "errorNetwork": "Cannot reach the ShellX server. Check your Internet connection.",
  "errorAgentOnly": "Only a signed-in computer can change the password.",
  "errorUnexpected": "Something went wrong ({code}). Try again.",
  "@errorUnexpected": {
    "placeholders": {
      "code": {"type": "String"}
    }
  },
  "onboardingTitle": "Almost done",
  "onboardingLaunchAtStartup": "Start ShellX when the computer starts",
  "onboardingFullDiskTitle": "Full Disk Access (optional)",
  "onboardingFullDiskBody": "Commands that touch Desktop, Documents or Downloads make macOS show a permission prompt on this computer's screen, which you cannot answer from your phone. Give ShellX Full Disk Access to avoid it.",
  "onboardingOpenSettings": "Open System Settings",
  "onboardingSleepTitle": "Sleep",
  "onboardingSleepBody": "ShellX keeps the computer from sleeping while idle. Closing the laptop lid still puts it to sleep, and then your phone cannot reach it.",
  "onboardingTrayHint": "{platform, select, macos{ShellX now lives in the menu bar. Choose “Pair phone…” there to connect your phone.} other{ShellX now lives in the system tray. Choose “Pair phone…” there to connect your phone.}}",
  "@onboardingTrayHint": {
    "placeholders": {
      "platform": {"type": "String"}
    }
  },
  "onboardingFinish": "Finish",
  "trayTooltip": "ShellX",
  "trayStatusConnected": "Connected — {email}",
  "@trayStatusConnected": {
    "placeholders": {
      "email": {"type": "String"}
    }
  },
  "trayStatusConnecting": "Connecting — {email}",
  "@trayStatusConnecting": {
    "placeholders": {
      "email": {"type": "String"}
    }
  },
  "trayStatusReconnecting": "Disconnected — retrying…",
  "trayStatusRemoteOff": "Remote access is off",
  "trayStatusReplaced": "Another copy of ShellX took over this computer",
  "trayStatusSignedOut": "Not signed in",
  "trayRemoteAccess": "Allow remote access",
  "traySessions": "Active sessions ({count})",
  "@traySessions": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "traySessionItem": "{shell} {index}",
  "@traySessionItem": {
    "placeholders": {
      "shell": {"type": "String"},
      "index": {"type": "int"}
    }
  },
  "traySessionItemAttached": "{shell} {index} — {device}",
  "@traySessionItemAttached": {
    "placeholders": {
      "shell": {"type": "String"},
      "index": {"type": "int"},
      "device": {"type": "String"}
    }
  },
  "traySessionClose": "Close",
  "trayCloseAll": "Close all",
  "trayPairPhone": "Pair phone…",
  "trayPairedDevices": "Paired devices",
  "trayRevoke": "Revoke",
  "trayNoDevices": "No paired devices",
  "trayKeepAwake": "Keep computer awake",
  "trayLaunchAtStartup": "Start with system",
  "trayChangePassword": "Change password…",
  "traySignOut": "Sign out",
  "traySignIn": "Sign in…",
  "trayQuit": "Quit",
  "trayDownloadUpdate": "Download ShellX {version}…",
  "@trayDownloadUpdate": {
    "placeholders": {
      "version": {"type": "String"}
    }
  },
  "confirmRemoteOffTitle": "Turn off remote access?",
  "confirmRemoteOffBody": "{count, plural, =1{1 open session will be closed.} other{{count} open sessions will be closed.}}",
  "@confirmRemoteOffBody": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "confirmRemoteOffAction": "Turn off",
  "confirmSignOutTitle": "Sign out of ShellX?",
  "confirmSignOutBody": "All sessions will be closed and every paired phone will be removed. After signing in again you must pair your phones again.",
  "confirmSignOutAction": "Sign out",
  "confirmRevokeTitle": "Revoke {device}?",
  "@confirmRevokeTitle": {
    "placeholders": {
      "device": {"type": "String"}
    }
  },
  "confirmRevokeBody": "This phone loses access to this computer immediately and its sessions are closed. To use it again you must pair it again.",
  "confirmRevokeAction": "Revoke",
  "confirmQuitTitle": "Quit ShellX?",
  "confirmQuitBody": "{count, plural, =1{1 open session will be closed. Your phones cannot reach this computer until ShellX runs again.} other{{count} open sessions will be closed. Your phones cannot reach this computer until ShellX runs again.}}",
  "@confirmQuitBody": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "confirmQuitAction": "Quit",
  "pairingTitle": "Pair a phone",
  "pairingInstructions": "Open ShellX on your phone (signed in to the same account), tap this computer and scan the code.",
  "pairingExpiresIn": "Code expires in {time}",
  "@pairingExpiresIn": {
    "placeholders": {
      "time": {"type": "String"}
    }
  },
  "pairingExpired": "This code has expired.",
  "pairingNewCode": "Create new code",
  "pairingOfflineWarning": "Not connected to the ShellX server. Your phone can pair once the connection is back.",
  "pairingSecretWarning": "Anyone who scans this code while signed in to your account can control this computer. Do not share it.",
  "changePasswordTitle": "Change password",
  "changePasswordNew": "New password",
  "changePasswordConfirm": "Re-enter new password",
  "changePasswordSubmit": "Change password",
  "changePasswordNote": "Other devices will be signed out. Pairings are kept.",
  "changePasswordDone": "Password changed. Your phones must sign in again with the new password.",
  "notifySessionOpened": "{device} opened a terminal session",
  "@notifySessionOpened": {
    "placeholders": {
      "device": {"type": "String"}
    }
  },
  "notifyPaired": "Paired with {device}",
  "@notifyPaired": {
    "placeholders": {
      "device": {"type": "String"}
    }
  },
  "notifyUpdateAvailableTitle": "ShellX {version} is available",
  "@notifyUpdateAvailableTitle": {
    "placeholders": {
      "version": {"type": "String"}
    }
  },
  "notifyUpdateAvailableBody": "Click to download.",
  "notifyUpdateRequiredTitle": "ShellX needs to be updated",
  "notifyUpdateRequiredBody": "This version is no longer supported. Click to download ShellX {version}.",
  "@notifyUpdateRequiredBody": {
    "placeholders": {
      "version": {"type": "String"}
    }
  },
  "notifySignedOutTitle": "ShellX was signed out",
  "notifySignedOutBody": "Sign in again to allow remote access.",
  "notifyAlreadyRunningTitle": "ShellX is already running",
  "notifyAlreadyRunningBody": "{platform, select, macos{Find it in the menu bar.} other{Find it in the system tray.}}",
  "@notifyAlreadyRunningBody": {
    "placeholders": {
      "platform": {"type": "String"}
    }
  },
  "windowsVersionUnsupported": "ShellX requires Windows 10 version 1809 or later."
}
```

`apps/desktop/lib/l10n/app_vi.arb`:

```json
{
  "@@locale": "vi",
  "appTitle": "ShellX",
  "actionCancel": "Hủy",
  "actionClose": "Đóng",
  "authSignInTitle": "Đăng nhập ShellX",
  "authRegisterTitle": "Tạo tài khoản ShellX",
  "authEmailLabel": "Email",
  "authPasswordLabel": "Mật khẩu",
  "authConfirmPasswordLabel": "Nhập lại mật khẩu",
  "authSignInButton": "Đăng nhập",
  "authRegisterButton": "Tạo tài khoản",
  "authSwitchToRegister": "Chưa có tài khoản? Đăng ký",
  "authSwitchToSignIn": "Đã có tài khoản? Đăng nhập",
  "authForgotPasswordHint": "Quên mật khẩu? Mở ShellX trên máy tính vẫn đang đăng nhập và chọn “Đổi mật khẩu…” trong menu.",
  "authSignedOutNotice": "Bạn đã bị đăng xuất. Hãy đăng nhập lại.",
  "errorEmailInvalid": "Hãy nhập địa chỉ email hợp lệ.",
  "errorPasswordLength": "Mật khẩu phải dài 8–128 ký tự.",
  "errorPasswordMismatch": "Hai mật khẩu không khớp.",
  "errorDisposableEmail": "Không chấp nhận email tạm thời. Hãy dùng địa chỉ email thật.",
  "errorEmailTaken": "Email này đã được đăng ký. Hãy đăng nhập.",
  "errorInvalidCredentials": "Email hoặc mật khẩu không đúng.",
  "errorRateLimited": "Thử lại sau ít phút.",
  "errorNetwork": "Không kết nối được máy chủ ShellX. Hãy kiểm tra kết nối Internet.",
  "errorAgentOnly": "Chỉ máy tính đang đăng nhập mới đổi được mật khẩu.",
  "errorUnexpected": "Đã có lỗi ({code}). Hãy thử lại.",
  "onboardingTitle": "Sắp xong rồi",
  "onboardingLaunchAtStartup": "Khởi động ShellX cùng hệ thống",
  "onboardingFullDiskTitle": "Quyền truy cập toàn bộ ổ đĩa (không bắt buộc)",
  "onboardingFullDiskBody": "Lệnh chạm vào Desktop, Documents hoặc Downloads sẽ làm macOS hiện hộp thoại xin quyền trên màn hình máy này, và bạn không trả lời được từ điện thoại. Cấp quyền Full Disk Access cho ShellX để tránh việc đó.",
  "onboardingOpenSettings": "Mở Cài đặt hệ thống",
  "onboardingSleepTitle": "Chế độ ngủ",
  "onboardingSleepBody": "ShellX giữ máy không tự ngủ khi để yên. Gập nắp laptop thì máy vẫn ngủ và điện thoại sẽ không kết nối được.",
  "onboardingTrayHint": "{platform, select, macos{ShellX giờ nằm trên thanh menu. Chọn “Ghép nối điện thoại…” ở đó để kết nối điện thoại.} other{ShellX giờ nằm trong khay hệ thống. Chọn “Ghép nối điện thoại…” ở đó để kết nối điện thoại.}}",
  "onboardingFinish": "Hoàn tất",
  "trayTooltip": "ShellX",
  "trayStatusConnected": "Đã kết nối — {email}",
  "trayStatusConnecting": "Đang kết nối — {email}",
  "trayStatusReconnecting": "Mất kết nối — đang thử lại…",
  "trayStatusRemoteOff": "Đã tắt truy cập từ xa",
  "trayStatusReplaced": "Một bản ShellX khác đã kết nối thay máy này",
  "trayStatusSignedOut": "Chưa đăng nhập",
  "trayRemoteAccess": "Cho phép truy cập từ xa",
  "traySessions": "Phiên đang hoạt động ({count})",
  "traySessionItem": "{shell} {index}",
  "traySessionItemAttached": "{shell} {index} — {device}",
  "traySessionClose": "Đóng",
  "trayCloseAll": "Đóng tất cả",
  "trayPairPhone": "Ghép nối điện thoại…",
  "trayPairedDevices": "Thiết bị đã ghép",
  "trayRevoke": "Thu hồi",
  "trayNoDevices": "Chưa ghép thiết bị nào",
  "trayKeepAwake": "Giữ máy không ngủ",
  "trayLaunchAtStartup": "Khởi động cùng hệ thống",
  "trayChangePassword": "Đổi mật khẩu…",
  "traySignOut": "Đăng xuất",
  "traySignIn": "Đăng nhập…",
  "trayQuit": "Thoát",
  "trayDownloadUpdate": "Tải ShellX {version}…",
  "confirmRemoteOffTitle": "Tắt truy cập từ xa?",
  "confirmRemoteOffBody": "{count, plural, other{{count} phiên đang mở sẽ bị đóng.}}",
  "confirmRemoteOffAction": "Tắt",
  "confirmSignOutTitle": "Đăng xuất khỏi ShellX?",
  "confirmSignOutBody": "Mọi phiên sẽ bị đóng và mọi điện thoại đã ghép sẽ bị gỡ. Sau khi đăng nhập lại, bạn phải ghép nối lại điện thoại.",
  "confirmSignOutAction": "Đăng xuất",
  "confirmRevokeTitle": "Thu hồi {device}?",
  "confirmRevokeBody": "Điện thoại này mất quyền truy cập máy tính ngay lập tức và các phiên của nó bị đóng. Muốn dùng lại phải ghép nối lại.",
  "confirmRevokeAction": "Thu hồi",
  "confirmQuitTitle": "Thoát ShellX?",
  "confirmQuitBody": "{count, plural, other{{count} phiên đang mở sẽ bị đóng. Điện thoại không kết nối được máy này cho tới khi ShellX chạy lại.}}",
  "confirmQuitAction": "Thoát",
  "pairingTitle": "Ghép nối điện thoại",
  "pairingInstructions": "Mở ShellX trên điện thoại (đăng nhập cùng tài khoản), chạm vào máy tính này rồi quét mã.",
  "pairingExpiresIn": "Mã hết hạn sau {time}",
  "pairingExpired": "Mã đã hết hạn.",
  "pairingNewCode": "Tạo mã mới",
  "pairingOfflineWarning": "Chưa kết nối được máy chủ ShellX. Điện thoại chỉ ghép nối được khi có kết nối trở lại.",
  "pairingSecretWarning": "Ai quét được mã này khi đăng nhập tài khoản của bạn sẽ điều khiển được máy tính này. Đừng chia sẻ mã.",
  "changePasswordTitle": "Đổi mật khẩu",
  "changePasswordNew": "Mật khẩu mới",
  "changePasswordConfirm": "Nhập lại mật khẩu mới",
  "changePasswordSubmit": "Đổi mật khẩu",
  "changePasswordNote": "Các thiết bị khác sẽ bị đăng xuất. Ghép nối được giữ nguyên.",
  "changePasswordDone": "Đã đổi mật khẩu. Điện thoại cần đăng nhập lại bằng mật khẩu mới.",
  "notifySessionOpened": "{device} vừa mở phiên terminal",
  "notifyPaired": "Đã ghép nối với {device}",
  "notifyUpdateAvailableTitle": "Đã có ShellX {version}",
  "notifyUpdateAvailableBody": "Bấm để tải về.",
  "notifyUpdateRequiredTitle": "Cần cập nhật app",
  "notifyUpdateRequiredBody": "Phiên bản này không còn được hỗ trợ. Bấm để tải ShellX {version}.",
  "notifySignedOutTitle": "ShellX đã bị đăng xuất",
  "notifySignedOutBody": "Đăng nhập lại để cho phép truy cập từ xa.",
  "notifyAlreadyRunningTitle": "ShellX đang chạy",
  "notifyAlreadyRunningBody": "{platform, select, macos{Tìm ShellX trên thanh menu.} other{Tìm ShellX trong khay hệ thống.}}",
  "windowsVersionUnsupported": "ShellX cần Windows 10 bản 1809 trở lên."
}
```

`apps/desktop/lib/src/l10n/locale.dart`:

```dart
import 'dart:ui';

const Locale kVietnamese = Locale('vi');
const Locale kEnglish = Locale('en');

/// The first preferred system locale ShellX supports; English otherwise.
Locale resolveAppLocale(List<Locale> preferred) {
  for (final locale in preferred) {
    if (locale.languageCode == 'vi') return kVietnamese;
    if (locale.languageCode == 'en') return kEnglish;
  }
  return kEnglish;
}
```

Sinh mã: `flutter gen-l10n` — Expected: tạo `lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_vi.dart` (commit các file này để analyzer và CI không phụ thuộc bước sinh).

- [ ] **Step 4: Chạy test, xác nhận qua**

Run: `flutter test test/l10n/l10n_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add l10n.yaml pubspec.yaml lib/l10n lib/src/l10n test/l10n
git commit -m "feat(desktop): add Vietnamese and English strings with gen-l10n"
```

---

### Task 3: Adapter PTY (`FlutterPtyFactory`) + test tích hợp PTY thật

**Files:**
- Create: `apps/desktop/lib/src/platform/pty/process_table.dart`, `process_tree_killer.dart`, `windows_text.dart`, `windows_native.dart`, `flutter_pty_factory.dart`
- Test: `apps/desktop/test/platform/pty/process_tree_test.dart`, `apps/desktop/test/platform/pty/flutter_pty_factory_test.dart`, `apps/desktop/integration_test/pty_test.dart`

**Interfaces:**
- Consumes: `shellx_agent` — `abstract interface class Pty { Stream<Uint8List> get output; Future<int> get exitCode; void write(Uint8List data); void resize(int cols, int rows); void kill(); }`, `abstract interface class PtyFactory { Pty spawn(ShellCommand command, {required String workingDirectory, required Map<String, String> environment, required int cols, required int rows}); }`, `ShellCommand`. Plan 03: adapter phải đóng `output` khi tiến trình thoát (SessionManager chờ tối đa 2 s).
- Produces:
  - `final class ProcessEntry { const ProcessEntry({required int pid, required int parentPid, required String name}); }`, `abstract interface class ProcessTable { Future<List<ProcessEntry>> snapshot(); }`, `List<int> descendantsOf(int root, List<ProcessEntry> table)`, `List<ProcessEntry> parsePsOutput(String output)`, `final class PsProcessTable implements ProcessTable`.
  - `abstract interface class ProcessTreeKiller { Future<void> killTree(int rootPid); }`, `PosixProcessTreeKiller({ProcessTable table, SignalSender? signal, Duration grace = 2 s, int? ownPid})`, `WindowsProcessTreeKiller({CommandRunner? run})`; `typedef CommandRunner = Future<ProcessResult> Function(String executable, List<String> arguments);`
  - `bool isAscii(String)`, `String windowsQuoteArg(String)`, `String asciiSafePathList(String value, String Function(String) shorten)`, `Map<String, String> asciiSafeEnvironment(Map<String, String>, String Function(String))`; `String windowsShortPath(String)`; `final class WindowsProcessTable implements ProcessTable { List<ProcessEntry> snapshotSync(); }`.
  - `final class PtyLaunch`, `abstract interface class NativePty { int get pid; Stream<Uint8List> get output; Future<int> get exitCode; void write(Uint8List); void resize(int rows, int columns); }`, `typedef NativePtyStarter = NativePty Function(PtyLaunch launch);`, `NativePty startFlutterPty(PtyLaunch)`, `ConsoleHostTracker`, `Set<int> consoleHostChildren(int parentPid, List<ProcessEntry> table)`.
  - `final class FlutterPtyFactory implements PtyFactory { FlutterPtyFactory({required bool isWindows, required ProcessTreeKiller killer, NativePtyStarter start = startFlutterPty, String Function(String)? shortPath, ConsoleHostTracker? consoleHosts, Duration outputGrace = const Duration(milliseconds: 500)}); factory FlutterPtyFactory.forCurrentPlatform(); PtyLaunch launchFor(...); }`, `final class FlutterPtyAdapter implements Pty { int get pid; }`.

- [ ] **Step 1: Viết test đơn vị thất bại**

`apps/desktop/test/platform/pty/process_tree_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/pty/process_table.dart';
import 'package:shellx_desktop/src/platform/pty/process_tree_killer.dart';

final class _FakeTable implements ProcessTable {
  _FakeTable(this.snapshots);
  final List<List<ProcessEntry>> snapshots;
  int calls = 0;

  @override
  Future<List<ProcessEntry>> snapshot() async =>
      snapshots[calls < snapshots.length ? calls++ : snapshots.length - 1];
}

ProcessEntry _p(int pid, int ppid, [String name = 'x']) =>
    ProcessEntry(pid: pid, parentPid: ppid, name: name);

void main() {
  group('parsePsOutput', () {
    test('parses padded columns and names containing spaces', () {
      const output =
          '    1     0 /sbin/launchd\n'
          '  812     1 /Applications/Visual Studio Code.app/Contents/MacOS/Electron\n'
          'garbage line\n'
          ' 9001   812 -zsh\n';
      final entries = parsePsOutput(output);
      expect(entries.map((e) => e.pid), [1, 812, 9001]);
      expect(
        entries[1].name,
        '/Applications/Visual Studio Code.app/Contents/MacOS/Electron',
      );
      expect(entries[2].parentPid, 812);
    });
  });

  group('descendantsOf', () {
    test('returns the whole subtree and nothing else', () {
      final table = [
        _p(1, 0),
        _p(100, 1),
        _p(101, 100),
        _p(102, 101),
        _p(103, 100),
        _p(200, 1),
        _p(201, 200),
      ];
      expect(descendantsOf(100, table)..sort(), [101, 102, 103]);
      expect(descendantsOf(999, table), isEmpty);
    });

    test('survives self-parented entries and cycles', () {
      final table = [_p(0, 0), _p(5, 6), _p(6, 5)];
      expect(descendantsOf(5, table), [6]);
    });
  });

  group('PosixProcessTreeKiller', () {
    test(
      'SIGHUPs the tree, then SIGKILLs survivors and late children',
      () async {
        final sent = <(int, ProcessSignal)>[];
        final table = _FakeTable([
          [_p(1, 0), _p(100, 1), _p(101, 100), _p(102, 101), _p(200, 1)],
          [_p(1, 0), _p(101, 1), _p(100, 1), _p(105, 100), _p(200, 1)],
        ]);
        final killer = PosixProcessTreeKiller(
          table: table,
          signal: (pid, signal) {
            sent.add((pid, signal));
            return true;
          },
          grace: Duration.zero,
          ownPid: 4242,
        );

        await killer.killTree(100);

        final hups = sent
            .where((s) => s.$2 == ProcessSignal.sighup)
            .map((s) => s.$1)
            .toSet();
        final kills = sent
            .where((s) => s.$2 == ProcessSignal.sigkill)
            .map((s) => s.$1)
            .toSet();
        expect(hups, {100, 101, 102});
        expect(kills, {100, 101, 105});
        expect(sent.map((s) => s.$1), isNot(contains(200)));
      },
    );

    test('never signals itself, launchd or pid 0', () async {
      final sent = <int>[];
      final killer = PosixProcessTreeKiller(
        table: _FakeTable([
          [_p(50, 1), _p(4242, 50), _p(1, 50)],
        ]),
        signal: (pid, _) {
          sent.add(pid);
          return true;
        },
        grace: Duration.zero,
        ownPid: 4242,
      );
      await killer.killTree(50);
      expect(sent.toSet(), {50});
      sent.clear();
      await killer.killTree(4242);
      await killer.killTree(1);
      expect(sent, isEmpty);
    });
  });

  test(
    'WindowsProcessTreeKiller runs taskkill /T /F on the shell pid',
    () async {
      final calls = <List<String>>[];
      final killer = WindowsProcessTreeKiller(
        run: (exe, args) async {
          calls.add([exe, ...args]);
          return ProcessResult(0, 0, '', '');
        },
      );
      await killer.killTree(777);
      expect(calls, [
        ['taskkill', '/PID', '777', '/T', '/F'],
      ]);
    },
  );
}
```

`apps/desktop/test/platform/pty/flutter_pty_factory_test.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/platform/pty/flutter_pty_factory.dart';
import 'package:shellx_desktop/src/platform/pty/process_table.dart';
import 'package:shellx_desktop/src/platform/pty/process_tree_killer.dart';
import 'package:shellx_desktop/src/platform/pty/windows_text.dart';

final class _FakeNativePty implements NativePty {
  _FakeNativePty(this.launch);
  final PtyLaunch launch;
  final exit = Completer<int>();
  final StreamController<Uint8List> out = StreamController<Uint8List>();
  final resizes = <(int, int)>[];
  final writes = <Uint8List>[];

  @override
  int get pid => 4321;
  @override
  Stream<Uint8List> get output => out.stream;
  @override
  Future<int> get exitCode => exit.future;
  @override
  void write(Uint8List data) => writes.add(data);
  @override
  void resize(int rows, int columns) => resizes.add((rows, columns));
}

final class _RecordingKiller implements ProcessTreeKiller {
  final killed = <int>[];
  @override
  Future<void> killTree(int rootPid) async => killed.add(rootPid);
}

const _zsh = ShellCommand(
  executable: '/bin/zsh',
  arguments: ['-l'],
  name: 'zsh',
);
const _pwsh = ShellCommand(
  executable: r'C:\Program Files\PowerShell\7\pwsh.exe',
  arguments: ['-NoLogo'],
  name: 'pwsh',
);

void main() {
  group('windowsQuoteArg', () {
    test('leaves simple arguments alone', () {
      expect(windowsQuoteArg('pwsh.exe'), 'pwsh.exe');
      expect(windowsQuoteArg('-NoLogo'), '-NoLogo');
    });
    test('quotes spaces, escapes quotes and trailing backslashes', () {
      expect(
        windowsQuoteArg(r'C:\Program Files\x.exe'),
        r'"C:\Program Files\x.exe"',
      );
      expect(windowsQuoteArg('a"b'), r'"a\"b"');
      expect(windowsQuoteArg(r'C:\dir with space\'), r'"C:\dir with space\\"');
      expect(windowsQuoteArg(''), '""');
    });
  });

  group('asciiSafe*', () {
    String shorten(String p) => p.replaceAll('Nguyễn', 'NGUYEN~1');

    test('only non-ASCII list elements are shortened', () {
      expect(
        asciiSafePathList(r'C:\Windows;C:\Users\Nguyễn\bin', shorten),
        r'C:\Windows;C:\Users\NGUYEN~1\bin',
      );
      expect(asciiSafePathList(r'C:\Windows', (_) => 'never'), r'C:\Windows');
    });

    test('environment values are rewritten, keys kept', () {
      final env = asciiSafeEnvironment({
        'USERPROFILE': r'C:\Users\Nguyễn',
        'TERM': 'xterm-256color',
      }, shorten);
      expect(env, {
        'USERPROFILE': r'C:\Users\NGUYEN~1',
        'TERM': 'xterm-256color',
      });
    });
  });

  group('FlutterPtyFactory', () {
    test('macOS passes the command through unchanged', () {
      late _FakeNativePty native;
      final factory = FlutterPtyFactory(
        isWindows: false,
        killer: _RecordingKiller(),
        start: (launch) => native = _FakeNativePty(launch),
      );
      factory.spawn(
        _zsh,
        workingDirectory: '/Users/phú',
        environment: {'SHELLX': '1'},
        cols: 120,
        rows: 40,
      );
      expect(native.launch.executable, '/bin/zsh');
      expect(native.launch.arguments, ['-l']);
      expect(native.launch.workingDirectory, '/Users/phú');
      expect(native.launch.columns, 120);
      expect(native.launch.rows, 40);
    });

    test('Windows quotes the executable and shortens non-ASCII paths', () {
      late _FakeNativePty native;
      final factory = FlutterPtyFactory(
        isWindows: true,
        killer: _RecordingKiller(),
        start: (launch) => native = _FakeNativePty(launch),
        shortPath: (p) => p.replaceAll('Nguyễn', 'NGUYEN~1'),
      );
      factory.spawn(
        _pwsh,
        workingDirectory: r'C:\Users\Nguyễn',
        environment: {'HOME': r'C:\Users\Nguyễn'},
        cols: 80,
        rows: 24,
      );
      expect(
        native.launch.executable,
        r'"C:\Program Files\PowerShell\7\pwsh.exe"',
      );
      expect(native.launch.workingDirectory, r'C:\Users\NGUYEN~1');
      expect(native.launch.environment['HOME'], r'C:\Users\NGUYEN~1');
    });

    test(
      'resize swaps to flutter_pty (rows, cols) order; kill runs once',
      () async {
        late _FakeNativePty native;
        final killer = _RecordingKiller();
        final pty =
            FlutterPtyFactory(
              isWindows: false,
              killer: killer,
              start: (launch) => native = _FakeNativePty(launch),
            ).spawn(
              _zsh,
              workingDirectory: '/',
              environment: {},
              cols: 80,
              rows: 24,
            );

        pty.resize(132, 50);
        pty.kill();
        pty.kill();
        await Future<void>.delayed(Duration.zero);

        expect(native.resizes, [(50, 132)]);
        expect(killer.killed, [4321]);
      },
    );

    test(
      'Windows terminates the conhost that appeared during spawn once the shell exits',
      () async {
        var table = [
          const ProcessEntry(pid: 10, parentPid: 1, name: 'conhost.exe'),
        ];
        final taskkills = <List<String>>[];
        late _FakeNativePty native;
        final factory = FlutterPtyFactory(
          isWindows: true,
          killer: _RecordingKiller(),
          outputGrace: Duration.zero,
          start: (launch) {
            table = [
              ...table,
              const ProcessEntry(pid: 11, parentPid: 1, name: 'conhost.exe'),
              const ProcessEntry(pid: 12, parentPid: 1, name: 'pwsh.exe'),
            ];
            return native = _FakeNativePty(launch);
          },
          consoleHosts: ConsoleHostTracker(
            snapshot: () => table,
            ownPid: 1,
            run: (exe, args) async {
              taskkills.add([exe, ...args]);
              return ProcessResult(0, 0, '', '');
            },
          ),
        );
        factory.spawn(
          _pwsh,
          workingDirectory: r'C:\',
          environment: {},
          cols: 80,
          rows: 24,
        );
        expect(taskkills, isEmpty);

        native.exit.complete(0);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(taskkills, [
          ['taskkill', '/PID', '11', '/F'],
        ]);
      },
    );
  });

  group('FlutterPtyAdapter output', () {
    const launch = PtyLaunch(
      executable: 'x',
      arguments: [],
      workingDirectory: '/',
      environment: {},
      columns: 80,
      rows: 24,
    );

    test('forwards data and closes when the native stream closes', () async {
      final native = _FakeNativePty(launch);
      final pty = FlutterPtyAdapter(native, killer: _RecordingKiller());
      final received = pty.output.toList();
      native.out.add(Uint8List.fromList([104, 105]));
      await native.out.close();
      expect(await received, [
        [104, 105],
      ]);
    });

    test(
      'closes within the grace period after exit even if native stays open',
      () async {
        final native = _FakeNativePty(launch);
        final pty = FlutterPtyAdapter(
          native,
          killer: _RecordingKiller(),
          outputGrace: const Duration(milliseconds: 10),
        );
        final done = Completer<void>();
        pty.output.listen((_) {}, onDone: done.complete);
        native.exit.complete(0);
        await done.future.timeout(const Duration(seconds: 2));
      },
    );
  });
}
```

- [ ] **Step 2: Chạy test, xác nhận thất bại**

Run: `flutter test test/platform/pty`
Expected: FAIL — `Error when reading 'lib/src/platform/pty/process_table.dart': No such file or directory`.

- [ ] **Step 3: Cài đặt**

`apps/desktop/lib/src/platform/pty/process_table.dart`:

```dart
import 'dart:convert';
import 'dart:io';

/// One row of the operating system process table.
final class ProcessEntry {
  const ProcessEntry({
    required this.pid,
    required this.parentPid,
    required this.name,
  });

  final int pid;
  final int parentPid;
  final String name;
}

/// Source of process-table snapshots (macOS: `ps`, Windows: Toolhelp32).
abstract interface class ProcessTable {
  Future<List<ProcessEntry>> snapshot();
}

/// Every descendant of [root] (children, grandchildren, ...), excluding [root].
List<int> descendantsOf(int root, List<ProcessEntry> table) {
  final children = <int, List<int>>{};
  for (final entry in table) {
    if (entry.pid == entry.parentPid) continue;
    children.putIfAbsent(entry.parentPid, () => <int>[]).add(entry.pid);
  }
  final result = <int>[];
  final seen = <int>{root};
  final queue = <int>[root];
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    for (final child in children[current] ?? const <int>[]) {
      if (seen.add(child)) {
        result.add(child);
        queue.add(child);
      }
    }
  }
  return result;
}

final RegExp _psLine = RegExp(r'^\s*(\d+)\s+(\d+)\s+(.*)$');

/// Parses the output of `ps -A -o pid=,ppid=,comm=`.
List<ProcessEntry> parsePsOutput(String output) {
  final entries = <ProcessEntry>[];
  for (final line in const LineSplitter().convert(output)) {
    final match = _psLine.firstMatch(line);
    if (match == null) continue;
    entries.add(
      ProcessEntry(
        pid: int.parse(match[1]!),
        parentPid: int.parse(match[2]!),
        name: match[3]!.trim(),
      ),
    );
  }
  return entries;
}

/// macOS process table via `/bin/ps`.
final class PsProcessTable implements ProcessTable {
  const PsProcessTable();

  @override
  Future<List<ProcessEntry>> snapshot() async {
    final result = await Process.run('/bin/ps', [
      '-A',
      '-o',
      'pid=,ppid=,comm=',
    ]);
    if (result.exitCode != 0) return const <ProcessEntry>[];
    return parsePsOutput(result.stdout as String);
  }
}
```

`apps/desktop/lib/src/platform/pty/process_tree_killer.dart`:

```dart
import 'dart:io';

import 'process_table.dart';

/// Terminates a shell and every process it started.
abstract interface class ProcessTreeKiller {
  Future<void> killTree(int rootPid);
}

typedef SignalSender = bool Function(int pid, ProcessSignal signal);
typedef CommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// macOS: SIGHUP to the shell and all its descendants (what closing a
/// terminal window does), wait [grace], then SIGKILL whatever from that tree is
/// still alive plus anything the shell spawned meanwhile.
///
/// Processes that detached themselves (double fork, re-parented to launchd)
/// before the first snapshot are outside the tree and survive; so do
/// `nohup`/`disown`ed jobs that ignore SIGHUP if they were re-parented.
final class PosixProcessTreeKiller implements ProcessTreeKiller {
  PosixProcessTreeKiller({
    ProcessTable table = const PsProcessTable(),
    SignalSender? signal,
    this.grace = const Duration(seconds: 2),
    int? ownPid,
  }) : _table = table,
       _signal = signal ?? Process.killPid,
       _ownPid = ownPid ?? pid;

  final ProcessTable _table;
  final SignalSender _signal;
  final int _ownPid;
  final Duration grace;

  bool _safe(int target) => target > 1 && target != _ownPid;

  @override
  Future<void> killTree(int rootPid) async {
    if (!_safe(rootPid)) return;
    final before = await _table.snapshot();
    final victims = <int>{rootPid, ...descendantsOf(rootPid, before)}
      ..removeWhere((p) => !_safe(p));
    for (final target in victims) {
      _signal(target, ProcessSignal.sighup);
    }
    await Future<void>.delayed(grace);
    final after = await _table.snapshot();
    final alive = after.map((e) => e.pid).toSet();
    final survivors = <int>{
      ...victims.where(alive.contains),
      ...descendantsOf(rootPid, after),
    }..removeWhere((p) => !_safe(p));
    for (final target in survivors) {
      _signal(target, ProcessSignal.sigkill);
    }
  }
}

/// Windows: `taskkill /PID <pid> /T /F` terminates the shell and every
/// descendant still linked to it by parent PID (TerminateProcess, no graceful
/// signal exists for console processes started under ConPTY).
final class WindowsProcessTreeKiller implements ProcessTreeKiller {
  WindowsProcessTreeKiller({CommandRunner? run}) : _run = run ?? Process.run;

  final CommandRunner _run;

  @override
  Future<void> killTree(int rootPid) async {
    await _run('taskkill', ['/PID', '$rootPid', '/T', '/F']);
  }
}
```

`apps/desktop/lib/src/platform/pty/windows_text.dart`:

```dart
/// Helpers that work around flutter_pty 0.4.2 on Windows: its C code builds the
/// command line, environment block and working directory by widening every
/// UTF-8 *byte* into one UTF-16 code unit, and joins arguments with plain
/// spaces. Non-ASCII text is therefore mangled and arguments with spaces split.
library;

bool isAscii(String value) => value.codeUnits.every((unit) => unit < 0x80);

/// Quotes one argument following the CommandLineToArgvW rules.
String windowsQuoteArg(String argument) {
  if (argument.isNotEmpty && !argument.contains(RegExp(r'[\s"]'))) {
    return argument;
  }
  final buffer = StringBuffer('"');
  var backslashes = 0;
  for (final char in argument.split('')) {
    if (char == r'\') {
      backslashes++;
      continue;
    }
    if (char == '"') {
      buffer.write(r'\' * (backslashes * 2 + 1));
      buffer.write('"');
    } else {
      buffer.write(r'\' * backslashes);
      buffer.write(char);
    }
    backslashes = 0;
  }
  buffer.write(r'\' * (backslashes * 2));
  buffer.write('"');
  return buffer.toString();
}

/// Rewrites each non-ASCII element of a `;`-separated path list with
/// [shorten] (8.3 short path). Elements [shorten] cannot convert stay as they
/// are (and will reach the shell mangled).
String asciiSafePathList(String value, String Function(String path) shorten) {
  if (isAscii(value)) return value;
  return value
      .split(';')
      .map((part) => isAscii(part) ? part : shorten(part))
      .join(';');
}

/// Applies [asciiSafePathList] to every environment value.
Map<String, String> asciiSafeEnvironment(
  Map<String, String> environment,
  String Function(String path) shorten,
) {
  return {
    for (final entry in environment.entries)
      entry.key: asciiSafePathList(entry.value, shorten),
  };
}
```

`apps/desktop/lib/src/platform/pty/windows_native.dart` (FFI tự khai báo Toolhelp32 vì `win32` 5.15.0 không có; chỉ được gọi trên Windows):

```dart
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' show GetShortPathName;

import 'process_table.dart';

/// 8.3 short form of [path] (pure ASCII when short names are enabled on the
/// volume), or [path] unchanged when the conversion fails. Windows only.
String windowsShortPath(String path) {
  final longPath = path.toNativeUtf16();
  try {
    final needed = GetShortPathName(longPath, nullptr, 0);
    if (needed == 0) return path;
    final buffer = calloc<Uint16>(needed).cast<Utf16>();
    try {
      final written = GetShortPathName(longPath, buffer, needed);
      if (written == 0 || written >= needed) return path;
      return buffer.toDartString();
    } finally {
      calloc.free(buffer);
    }
  } finally {
    calloc.free(longPath);
  }
}

const int _th32csSnapProcess = 0x00000002;
const int _maxPath = 260;

// PROCESSENTRY32W from tlhelp32.h. win32 5.15.0 does not bind Toolhelp32.
final class _ProcessEntry32W extends Struct {
  @Uint32()
  external int dwSize;
  @Uint32()
  external int cntUsage;
  @Uint32()
  external int th32ProcessID;
  @UintPtr()
  external int th32DefaultHeapID;
  @Uint32()
  external int th32ModuleID;
  @Uint32()
  external int cntThreads;
  @Uint32()
  external int th32ParentProcessID;
  @Int32()
  external int pcPriClassBase;
  @Uint32()
  external int dwFlags;
  @Array(_maxPath)
  external Array<Uint16> szExeFile;
}

typedef _SnapshotNative = IntPtr Function(Uint32 flags, Uint32 processId);
typedef _SnapshotDart = int Function(int flags, int processId);
typedef _WalkNative =
    Int32 Function(IntPtr snapshot, Pointer<_ProcessEntry32W> entry);
typedef _WalkDart = int Function(int snapshot, Pointer<_ProcessEntry32W> entry);
typedef _CloseNative = Int32 Function(IntPtr handle);
typedef _CloseDart = int Function(int handle);

/// Windows process table via CreateToolhelp32Snapshot (synchronous, ~1 ms).
final class WindowsProcessTable implements ProcessTable {
  WindowsProcessTable() : _kernel32 = DynamicLibrary.open('kernel32.dll');

  final DynamicLibrary _kernel32;
  late final _SnapshotDart _createSnapshot = _kernel32
      .lookupFunction<_SnapshotNative, _SnapshotDart>(
        'CreateToolhelp32Snapshot',
      );
  late final _WalkDart _first = _kernel32
      .lookupFunction<_WalkNative, _WalkDart>('Process32FirstW');
  late final _WalkDart _next = _kernel32.lookupFunction<_WalkNative, _WalkDart>(
    'Process32NextW',
  );
  late final _CloseDart _closeHandle = _kernel32
      .lookupFunction<_CloseNative, _CloseDart>('CloseHandle');

  List<ProcessEntry> snapshotSync() {
    final snapshot = _createSnapshot(_th32csSnapProcess, 0);
    if (snapshot == -1 || snapshot == 0) return const <ProcessEntry>[];
    final entry = calloc<_ProcessEntry32W>();
    try {
      entry.ref.dwSize = sizeOf<_ProcessEntry32W>();
      final result = <ProcessEntry>[];
      var ok = _first(snapshot, entry);
      while (ok != 0) {
        result.add(
          ProcessEntry(
            pid: entry.ref.th32ProcessID,
            parentPid: entry.ref.th32ParentProcessID,
            name: _exeName(entry.ref.szExeFile),
          ),
        );
        ok = _next(snapshot, entry);
      }
      return result;
    } finally {
      calloc.free(entry);
      _closeHandle(snapshot);
    }
  }

  @override
  Future<List<ProcessEntry>> snapshot() async => snapshotSync();
}

String _exeName(Array<Uint16> chars) {
  final units = <int>[];
  for (var i = 0; i < _maxPath; i++) {
    final unit = chars[i];
    if (unit == 0) break;
    units.add(unit);
  }
  return String.fromCharCodes(units);
}
```

`apps/desktop/lib/src/platform/pty/flutter_pty_factory.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart' as fp;
import 'package:shellx_agent/shellx_agent.dart';

import 'process_table.dart';
import 'process_tree_killer.dart';
import 'windows_native.dart';
import 'windows_text.dart';

/// Arguments handed to the native PTY, after platform fix-ups.
final class PtyLaunch {
  const PtyLaunch({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
    required this.columns,
    required this.rows,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;
  final int columns;
  final int rows;
}

/// The subset of `flutter_pty`'s `Pty` this adapter uses; faked in unit tests.
abstract interface class NativePty {
  int get pid;
  Stream<Uint8List> get output;
  Future<int> get exitCode;
  void write(Uint8List data);

  /// Note the flutter_pty argument order: rows first.
  void resize(int rows, int columns);
}

typedef NativePtyStarter = NativePty Function(PtyLaunch launch);

final class _FlutterNativePty implements NativePty {
  _FlutterNativePty(this._pty);

  final fp.Pty _pty;

  @override
  int get pid => _pty.pid;
  @override
  Stream<Uint8List> get output => _pty.output;
  @override
  Future<int> get exitCode => _pty.exitCode;
  @override
  void write(Uint8List data) => _pty.write(data);
  @override
  void resize(int rows, int columns) => _pty.resize(rows, columns);
}

NativePty startFlutterPty(PtyLaunch launch) {
  return _FlutterNativePty(
    fp.Pty.start(
      launch.executable,
      arguments: launch.arguments,
      workingDirectory: launch.workingDirectory,
      environment: launch.environment,
      columns: launch.columns,
      rows: launch.rows,
    ),
  );
}

/// Finds the ConPTY host process (`conhost.exe`) that CreatePseudoConsole
/// starts as a child of this process. flutter_pty 0.4.2 never calls
/// ClosePseudoConsole, so the adapter terminates that host itself.
final class ConsoleHostTracker {
  ConsoleHostTracker({
    required List<ProcessEntry> Function() snapshot,
    required int ownPid,
    CommandRunner? run,
  }) : _snapshot = snapshot,
       _ownPid = ownPid,
       _run = run ?? Process.run;

  final List<ProcessEntry> Function() _snapshot;
  final int _ownPid;
  final CommandRunner _run;

  Set<int> hostsNow() => consoleHostChildren(_ownPid, _snapshot());

  /// The single host that appeared since [before], or null if not exactly one.
  int? newHostSince(Set<int> before) {
    final added = hostsNow().difference(before);
    return added.length == 1 ? added.single : null;
  }

  Future<void> terminate(int hostPid) async {
    await _run('taskkill', ['/PID', '$hostPid', '/F']);
  }
}

Set<int> consoleHostChildren(int parentPid, List<ProcessEntry> table) {
  return {
    for (final entry in table)
      if (entry.parentPid == parentPid && _isConsoleHost(entry.name)) entry.pid,
  };
}

bool _isConsoleHost(String name) {
  final lower = name.toLowerCase();
  return lower == 'conhost.exe' || lower == 'openconsole.exe';
}

/// [PtyFactory] backed by package flutter_pty.
///
/// What `kill()` does:
/// * macOS: [PosixProcessTreeKiller] — SIGHUP to the shell and all
///   descendants, SIGKILL to survivors after 2 s.
/// * Windows: [WindowsProcessTreeKiller] (`taskkill /T /F`), then terminates
///   the session's conhost.exe so the pseudo console and its pipes are freed.
final class FlutterPtyFactory implements PtyFactory {
  FlutterPtyFactory({
    required bool isWindows,
    required ProcessTreeKiller killer,
    NativePtyStarter start = startFlutterPty,
    String Function(String path)? shortPath,
    ConsoleHostTracker? consoleHosts,
    Duration outputGrace = const Duration(milliseconds: 500),
  }) : _isWindows = isWindows,
       _outputGrace = outputGrace,
       _killer = killer,
       _start = start,
       _shortPath = shortPath ?? ((path) => path),
       _consoleHosts = consoleHosts;

  factory FlutterPtyFactory.forCurrentPlatform() {
    if (Platform.isWindows) {
      final table = WindowsProcessTable();
      return FlutterPtyFactory(
        isWindows: true,
        killer: WindowsProcessTreeKiller(),
        shortPath: windowsShortPath,
        consoleHosts: ConsoleHostTracker(
          snapshot: table.snapshotSync,
          ownPid: pid,
        ),
      );
    }
    return FlutterPtyFactory(
      isWindows: false,
      killer: PosixProcessTreeKiller(),
    );
  }

  final bool _isWindows;
  final ProcessTreeKiller _killer;
  final NativePtyStarter _start;
  final String Function(String path) _shortPath;
  final ConsoleHostTracker? _consoleHosts;
  final Duration _outputGrace;

  PtyLaunch launchFor(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) {
    if (!_isWindows) {
      return PtyLaunch(
        executable: command.executable,
        arguments: command.arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        columns: cols,
        rows: rows,
      );
    }
    return PtyLaunch(
      executable: windowsQuoteArg(
        asciiSafePathList(command.executable, _shortPath),
      ),
      arguments: [for (final a in command.arguments) windowsQuoteArg(a)],
      workingDirectory: asciiSafePathList(workingDirectory, _shortPath),
      environment: asciiSafeEnvironment(environment, _shortPath),
      columns: cols,
      rows: rows,
    );
  }

  @override
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) {
    final launch = launchFor(
      command,
      workingDirectory: workingDirectory,
      environment: environment,
      cols: cols,
      rows: rows,
    );
    final hosts = _consoleHosts;
    final before = hosts?.hostsNow();
    final native = _start(launch);
    final hostPid = before == null ? null : hosts!.newHostSince(before);
    return FlutterPtyAdapter(
      native,
      killer: _killer,
      onExit: hostPid == null ? null : () => hosts!.terminate(hostPid),
      outputGrace: _outputGrace,
    );
  }
}

/// Adapts a [NativePty] to the `shellx_agent` [Pty] contract.
///
/// `output` is guaranteed to close at most [outputGrace] after the process
/// exits (SessionManager waits up to 2 s for it). flutter_pty 0.4.2 already
/// closes its ReceivePort when the exit code arrives; the grace timer covers
/// any native stream that stays open.
final class FlutterPtyAdapter implements Pty {
  FlutterPtyAdapter(
    this._native, {
    required ProcessTreeKiller killer,
    Future<void> Function()? onExit,
    this.outputGrace = const Duration(milliseconds: 500),
  }) : _killer = killer {
    _nativeSubscription = _native.output.listen(
      _output.add,
      onError: _output.addError,
      onDone: _closeOutput,
    );
    unawaited(
      _native.exitCode.then((_) async {
        await Future<void>.delayed(outputGrace);
        _closeOutput();
        if (onExit != null) await onExit();
      }),
    );
  }

  final NativePty _native;
  final ProcessTreeKiller _killer;
  final Duration outputGrace;
  final StreamController<Uint8List> _output = StreamController<Uint8List>();
  late final StreamSubscription<Uint8List> _nativeSubscription;
  bool _killed = false;

  int get pid => _native.pid;

  void _closeOutput() {
    if (_output.isClosed) return;
    unawaited(_nativeSubscription.cancel());
    unawaited(_output.close());
  }

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _native.exitCode;

  @override
  void write(Uint8List data) => _native.write(data);

  @override
  void resize(int cols, int rows) => _native.resize(rows, cols);

  @override
  void kill() {
    if (_killed) return;
    _killed = true;
    unawaited(_killer.killTree(_native.pid));
  }
}
```

- [ ] **Step 4: Chạy test đơn vị, xác nhận qua**

Run: `flutter test test/platform/pty`
Expected: `All tests passed!` (16 test).

- [ ] **Step 5: Viết test tích hợp PTY thật**

`apps/desktop/integration_test/pty_test.dart` (macOS: `/bin/zsh -f`; Windows: `powershell.exe` và `pwsh.exe` nếu có trong PATH; test `vim` bị skip nếu không có `/usr/bin/vim` hoặc vim của Git for Windows):

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/platform/pty/flutter_pty_factory.dart';
import 'package:shellx_desktop/src/platform/pty/windows_native.dart';

final RegExp _ansi = RegExp(
  r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\)|[@-Z\\-_])',
);

/// Accumulates PTY output (ANSI stripped) and waits for a whole line.
final class Transcript {
  Transcript(Stream<Uint8List> output) {
    _subscription = output.listen(
      (chunk) {
        _raw.write(utf8.decode(chunk, allowMalformed: true));
        _changes.add(null);
      },
      onDone: () {
        if (!_done.isCompleted) _done.complete();
      },
    );
  }

  final Completer<void> _done = Completer<void>();

  /// Completes when the PTY closes its output stream.
  Future<void> get done => _done.future;

  final StringBuffer _raw = StringBuffer();
  final StreamController<void> _changes = StreamController<void>.broadcast();
  late final StreamSubscription<Uint8List> _subscription;

  List<String> get lines => _raw
      .toString()
      .replaceAll(_ansi, '')
      .split(RegExp(r'\r?\n|\r'))
      .map((line) => line.trim())
      .toList();

  Future<void> waitForLine(
    bool Function(String line) test, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!lines.any(test)) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        fail('Timed out. Transcript:\n${lines.join('\n')}');
      }
      await _changes.stream.first.timeout(left, onTimeout: () {});
    }
  }

  Future<void> close() => _subscription.cancel();
}

List<ShellCommand> _shells() {
  if (!Platform.isWindows) {
    return const [
      ShellCommand(executable: '/bin/zsh', arguments: ['-f'], name: 'zsh'),
    ];
  }
  final shells = <ShellCommand>[
    const ShellCommand(
      executable: 'powershell.exe',
      arguments: ['-NoLogo', '-NoProfile'],
      name: 'powershell',
    ),
  ];
  final hasPwsh = Process.runSync('where.exe', ['pwsh.exe']).exitCode == 0;
  if (hasPwsh) {
    shells.add(
      const ShellCommand(
        executable: 'pwsh.exe',
        arguments: ['-NoLogo', '-NoProfile'],
        name: 'pwsh',
      ),
    );
  }
  return shells;
}

Map<String, String> _environment() => {
  ...Platform.environment,
  'TERM': 'xterm-256color',
  'SHELLX': '1',
};

String get _home =>
    Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME']!;

void _type(Pty pty, String line) =>
    pty.write(Uint8List.fromList(utf8.encode('$line\r')));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final factory = FlutterPtyFactory.forCurrentPlatform();

  for (final shell in _shells()) {
    testWidgets('${shell.name}: echo shellx-ok comes back on its own line', (
      tester,
    ) async {
      final pty = factory.spawn(
        shell,
        workingDirectory: _home,
        environment: _environment(),
        cols: 80,
        rows: 24,
      );
      final transcript = Transcript(pty.output);
      _type(pty, 'echo shellx-ok');
      await transcript.waitForLine((line) => line == 'shellx-ok');
      pty.kill();
      await pty.exitCode.timeout(const Duration(seconds: 15));
      await transcript.close();
    });
  }

  final shell = _shells().first;

  testWidgets('environment and a Vietnamese working directory reach the shell', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('shellx-thư-mục-');
    await File(
      '${dir.path}${Platform.pathSeparator}marker.txt',
    ).writeAsString('x');
    final pty = factory.spawn(
      shell,
      workingDirectory: dir.path,
      environment: _environment(),
      cols: 80,
      rows: 24,
    );
    final transcript = Transcript(pty.output);
    if (Platform.isWindows) {
      _type(
        pty,
        r"if (Test-Path marker.txt) { 'marker-' + 'ok' }; 'env-' + $env:SHELLX",
      );
    } else {
      _type(
        pty,
        r'test -f marker.txt && echo marker-$((1+0)); echo env-$SHELLX',
      );
    }
    await transcript.waitForLine(
      (line) => line == (Platform.isWindows ? 'marker-ok' : 'marker-1'),
    );
    await transcript.waitForLine((line) => line == 'env-1');
    pty.kill();
    await pty.exitCode.timeout(const Duration(seconds: 15));
    await transcript.close();
    await dir.delete(recursive: true);
  });

  testWidgets('output closes within 2 s after the shell exits', (tester) async {
    final pty = factory.spawn(
      shell,
      workingDirectory: _home,
      environment: _environment(),
      cols: 80,
      rows: 24,
    );
    final transcript = Transcript(pty.output);
    _type(pty, 'exit');
    await pty.exitCode.timeout(const Duration(seconds: 15));
    await transcript.done.timeout(const Duration(seconds: 2));
  });

  testWidgets('resize(cols, rows) reaches the terminal', (tester) async {
    final pty = factory.spawn(
      shell,
      workingDirectory: _home,
      environment: _environment(),
      cols: 80,
      rows: 24,
    );
    final transcript = Transcript(pty.output);
    pty.resize(100, 30);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (Platform.isWindows) {
      _type(pty, r"'cols-' + [Console]::WindowWidth");
      await transcript.waitForLine((line) => line == 'cols-100');
    } else {
      _type(pty, r'echo size-$(stty size | tr " " x)');
      await transcript.waitForLine((line) => line == 'size-30x100');
    }
    pty.kill();
    await pty.exitCode.timeout(const Duration(seconds: 15));
    await transcript.close();
  });

  testWidgets('kill() ends the shell and the processes it started', (
    tester,
  ) async {
    final hostsBefore = Platform.isWindows
        ? consoleHostChildren(pid, WindowsProcessTable().snapshotSync())
        : <int>{};
    final pty = factory.spawn(
      shell,
      workingDirectory: _home,
      environment: _environment(),
      cols: 80,
      rows: 24,
    );
    final transcript = Transcript(pty.output);
    if (Platform.isWindows) {
      _type(
        pty,
        r"$p = Start-Process -PassThru -NoNewWindow ping.exe -ArgumentList '-n','300','127.0.0.1'; 'child=' + $p.Id",
      );
    } else {
      _type(pty, r'sleep 300 & echo child=$!');
    }
    late int childPid;
    await transcript.waitForLine((line) {
      final match = RegExp(r'^child=(\d+)$').firstMatch(line);
      if (match == null) return false;
      childPid = int.parse(match[1]!);
      return true;
    });

    pty.kill();
    await pty.exitCode.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(const Duration(seconds: 4));

    if (Platform.isWindows) {
      final table = WindowsProcessTable().snapshotSync();
      expect(
        table.any((e) => e.pid == childPid),
        isFalse,
        reason: 'child process survived kill()',
      );
      expect(
        consoleHostChildren(pid, table).difference(hostsBefore),
        isEmpty,
        reason: 'conhost.exe of the closed PTY is still running',
      );
    } else {
      final probe = await Process.run('/bin/kill', ['-0', '$childPid']);
      expect(probe.exitCode, isNot(0), reason: 'child process survived kill()');
    }
    await transcript.close();
  });

  final vim = Platform.isWindows
      ? r'C:\Program Files\Git\usr\bin\vim.exe'
      : '/usr/bin/vim';
  testWidgets(
    'a full-screen program (vim) runs, takes keys and exits',
    (tester) async {
      final pty = factory.spawn(
        shell,
        workingDirectory: _home,
        environment: _environment(),
        cols: 80,
        rows: 24,
      );
      final transcript = Transcript(pty.output);
      _type(
        pty,
        Platform.isWindows ? "& '$vim' -u NONE -N" : '$vim -u NONE -N',
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      pty.resize(90, 30);
      pty.write(Uint8List.fromList(utf8.encode('\x1b:q!\r')));
      await Future<void>.delayed(const Duration(seconds: 1));
      _type(
        pty,
        Platform.isWindows ? "'after-' + 'vim'" : r'echo after-$((0))vim',
      );
      await transcript.waitForLine(
        (line) => line == (Platform.isWindows ? 'after-vim' : 'after-0vim'),
      );
      pty.kill();
      await pty.exitCode.timeout(const Duration(seconds: 15));
      await transcript.close();
    },
    skip: !File(vim).existsSync(),
  );
}
```

- [ ] **Step 6: Chạy test tích hợp trên macOS**

Run: `flutter test integration_test/pty_test.dart -d macos`
Expected: `All tests passed!` (6 test: echo, env + thư mục tiếng Việt, output đóng sau exit, resize, kill cả cây, vim). Trên Windows lệnh tương đương `flutter test integration_test/pty_test.dart -d windows` do CI của plan 06 chạy (xem mục "Chỉ kiểm được trên Windows" cuối plan).

- [ ] **Step 7: Commit**

```bash
git add lib/src/platform/pty test/platform/pty integration_test
git commit -m "feat(desktop): add flutter_pty adapter with process-tree kill"
```

---

### Task 4: Lưu trữ bảo mật và công tắc cài đặt

**Files:**
- Create: `apps/desktop/lib/src/platform/secure_key_value_store.dart`, `apps/desktop/lib/src/platform/settings_store.dart`
- Test: `apps/desktop/test/platform/storage_test.dart`

**Interfaces:**
- Consumes: `shellx_core` — `abstract interface class KeyValueStore { Future<String?> read(String key); Future<void> write(String key, String value); Future<void> delete(String key); }`.
- Produces: `final class SecureKeyValueStore implements KeyValueStore { SecureKeyValueStore([FlutterSecureStorage? storage]); static const FlutterSecureStorage defaultStorage; }`; `abstract final class SettingKeys { remoteAccess = 'remote_access_enabled', keepAwake = 'keep_awake_enabled', launchAtStartup = 'launch_at_startup_enabled', onboardingDone = 'onboarding_done', all }`; `abstract interface class SettingsStore { bool getBool(String key, {required bool defaultValue}); Future<void> setBool(String key, bool value); }`; `SharedPrefsSettingsStore.open()`; `InMemorySettingsStore([Map<String, bool>? values])` với field `values`.

- [ ] **Step 1: Viết test thất bại**

`apps/desktop/test/platform/storage_test.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shellx_desktop/src/platform/secure_key_value_store.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SecureKeyValueStore reads, writes and deletes', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureKeyValueStore();
    expect(await store.read('auth_token'), isNull);
    await store.write('auth_token', 'secret');
    expect(await store.read('auth_token'), 'secret');
    await store.delete('auth_token');
    expect(await store.read('auth_token'), isNull);
  });

  test('SharedPrefsSettingsStore persists switches with defaults', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final settings = await SharedPrefsSettingsStore.open();
    expect(
      settings.getBool(SettingKeys.remoteAccess, defaultValue: true),
      isTrue,
    );
    await settings.setBool(SettingKeys.remoteAccess, false);

    final reopened = await SharedPrefsSettingsStore.open();
    expect(
      reopened.getBool(SettingKeys.remoteAccess, defaultValue: true),
      isFalse,
    );
  });

  test('InMemorySettingsStore returns defaults until set', () async {
    final settings = InMemorySettingsStore();
    expect(settings.getBool(SettingKeys.keepAwake, defaultValue: true), isTrue);
    await settings.setBool(SettingKeys.keepAwake, false);
    expect(
      settings.getBool(SettingKeys.keepAwake, defaultValue: true),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Chạy test, xác nhận thất bại**

Run: `flutter test test/platform/storage_test.dart`
Expected: FAIL — `Error when reading 'lib/src/platform/secure_key_value_store.dart': No such file or directory`.

- [ ] **Step 3: Cài đặt**

`apps/desktop/lib/src/platform/secure_key_value_store.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shellx_core/shellx_core.dart';

/// [KeyValueStore] over flutter_secure_storage.
///
/// * macOS: login keychain, service `pro.shellx.desktop`. The legacy
///   (file-based) keychain is used on purpose: the data-protection keychain
///   needs a `keychain-access-groups` entitlement backed by a provisioning
///   profile, which a Developer ID app outside the App Store does not have.
/// * Windows: flutter_secure_storage 10.x stores values in a DPAPI-encrypted
///   file (`flutter_secure_storage.dat` in the app support directory),
///   readable only by the current Windows user.
final class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore([FlutterSecureStorage? storage])
    : _storage = storage ?? defaultStorage;

  static const FlutterSecureStorage defaultStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(
      accountName: 'pro.shellx.desktop',
      usesDataProtectionKeychain: false,
    ),
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
```

`apps/desktop/lib/src/platform/settings_store.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret switches (spec §8.4: shared_preferences).
abstract final class SettingKeys {
  static const String remoteAccess = 'remote_access_enabled';
  static const String keepAwake = 'keep_awake_enabled';
  static const String launchAtStartup = 'launch_at_startup_enabled';
  static const String onboardingDone = 'onboarding_done';

  static const Set<String> all = {
    remoteAccess,
    keepAwake,
    launchAtStartup,
    onboardingDone,
  };
}

abstract interface class SettingsStore {
  bool getBool(String key, {required bool defaultValue});
  Future<void> setBool(String key, bool value);
}

final class SharedPrefsSettingsStore implements SettingsStore {
  SharedPrefsSettingsStore._(this._prefs);

  static Future<SharedPrefsSettingsStore> open() async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: SettingKeys.all,
      ),
    );
    return SharedPrefsSettingsStore._(prefs);
  }

  final SharedPreferencesWithCache _prefs;

  @override
  bool getBool(String key, {required bool defaultValue}) =>
      _prefs.getBool(key) ?? defaultValue;

  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
}

final class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([Map<String, bool>? values]) : values = values ?? {};

  final Map<String, bool> values;

  @override
  bool getBool(String key, {required bool defaultValue}) =>
      values[key] ?? defaultValue;

  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;
}
```

- [ ] **Step 4: Chạy test, xác nhận qua**

Run: `flutter test test/platform/storage_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/src/platform/secure_key_value_store.dart lib/src/platform/settings_store.dart test/platform/storage_test.dart
git commit -m "feat(desktop): add secure key-value store and settings switches"
```

---

### Task 5: Tích hợp hệ điều hành — giữ máy thức, tự khởi động, một bản duy nhất, thông báo, mở URL, phát hiện thức dậy

**Files:**
- Create: `apps/desktop/lib/src/platform/keep_awake.dart`, `launch_at_login.dart`, `single_instance.dart`, `notifier.dart`, `url_opener.dart`, `wake_detector.dart`
- Create (fixture): `apps/desktop/test/fixtures/lock_probe.dart`
- Test: `apps/desktop/test/platform/os_integration_test.dart`, `apps/desktop/test/platform/single_instance_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class KeepAwake { Future<void> setEnabled(bool enabled); }`; `CaffeinateKeepAwake({ProcessStarter? start, int? agentPid})`; `WindowsKeepAwake({ExecutionStateSetter? setState})` (`esContinuous = 0x80000000`, `esSystemRequired = 0x1`).
  - `abstract interface class LaunchAtLogin { Future<bool> isEnabled(); Future<void> setEnabled(bool enabled); }`; `PackageLaunchAtLogin()` (appName `ShellX`).
  - `final class SingleInstanceLock { SingleInstanceLock(Directory directory); String get lockPath; Future<bool> acquire(); Future<void> release(); Future<void> signalRunningInstance(); Stream<void> activationRequests(); }`.
  - `abstract interface class SystemNotifier { Future<void> show({required String title, String? body, void Function()? onClick}); }`; `LocalSystemNotifier.setup()`.
  - `abstract interface class UrlOpener { Future<void> open(Uri uri); }`; `SystemUrlOpener({bool? isWindows, UrlCommandRunner? run})`; `static final Uri fullDiskAccessPane`.
  - `final class WakeDetector { WakeDetector({required void Function() onWake, DateTime Function()? now, Duration interval = 5 s, Duration tolerance = 15 s}); void start(); void check(); void stop(); }`.

- [ ] **Step 1: Viết test thất bại**

`apps/desktop/test/platform/os_integration_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/keep_awake.dart';
import 'package:shellx_desktop/src/platform/url_opener.dart';
import 'package:shellx_desktop/src/platform/wake_detector.dart';

final class _FakeProcess implements Process {
  final Completer<int> _exit = Completer<int>();
  bool killed = false;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(-15);
    return true;
  }

  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 999;
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
}

void main() {
  group('CaffeinateKeepAwake', () {
    test(
      'starts one caffeinate bound to the agent pid and kills it on disable',
      () async {
        final started = <List<String>>[];
        final processes = <_FakeProcess>[];
        final keepAwake = CaffeinateKeepAwake(
          agentPid: 4242,
          start: (exe, args) async {
            started.add([exe, ...args]);
            return processes.last;
          },
        );
        processes.add(_FakeProcess());
        await Future.wait([
          keepAwake.setEnabled(true),
          keepAwake.setEnabled(true),
        ]);
        expect(started, [
          ['/usr/bin/caffeinate', '-i', '-w', '4242'],
        ]);

        await keepAwake.setEnabled(false);
        expect(processes.single.killed, isTrue);

        processes.add(_FakeProcess());
        await keepAwake.setEnabled(true);
        expect(started, hasLength(2));
      },
    );
  });

  test(
    'WindowsKeepAwake sets ES_CONTINUOUS|ES_SYSTEM_REQUIRED, then ES_CONTINUOUS',
    () async {
      final flags = <int>[];
      final keepAwake = WindowsKeepAwake(
        setState: (f) {
          flags.add(f);
          return 1;
        },
      );
      await keepAwake.setEnabled(true);
      await keepAwake.setEnabled(false);
      expect(flags, [0x80000001, 0x80000000]);
    },
  );

  test('SystemUrlOpener uses open on macOS and rundll32 on Windows', () async {
    final calls = <List<String>>[];
    Future<ProcessResult> run(String exe, List<String> args) async {
      calls.add([exe, ...args]);
      return ProcessResult(0, 0, '', '');
    }

    await SystemUrlOpener(
      isWindows: false,
      run: run,
    ).open(SystemUrlOpener.fullDiskAccessPane);
    await SystemUrlOpener(
      isWindows: true,
      run: run,
    ).open(Uri.parse('https://download.shellx.pro/x.exe'));
    expect(calls, [
      [
        '/usr/bin/open',
        'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
      ],
      [
        'rundll32',
        'url.dll,FileProtocolHandler',
        'https://download.shellx.pro/x.exe',
      ],
    ]);
  });

  test(
    'WakeDetector fires only when the wall clock jumps past interval + tolerance',
    () {
      var now = DateTime(2026, 9, 25, 12);
      var wakes = 0;
      final detector = WakeDetector(onWake: () => wakes++, now: () => now);
      detector.start();
      now = now.add(const Duration(seconds: 5));
      detector.check();
      now = now.add(const Duration(seconds: 19));
      detector.check();
      expect(wakes, 0);
      now = now.add(const Duration(minutes: 42));
      detector.check();
      expect(wakes, 1);
      detector.stop();
    },
  );
}
```

`apps/desktop/test/fixtures/lock_probe.dart` (khóa file trên macOS là theo tiến trình, nên phải thử từ một tiến trình khác; cần lệnh `dart` trong PATH — có sẵn cùng Flutter SDK và trong CI `subosito/flutter-action`):

```dart
// Run with `dart test/fixtures/lock_probe.dart <lock file>`; prints
// "acquired" or "busy". Used by single_instance_test.dart because file locks
// are per process on macOS.
import 'dart:io';

Future<void> main(List<String> args) async {
  final file = await File(args.single).open(mode: FileMode.append);
  try {
    await file.lock(FileLock.exclusive);
    stdout.write('acquired');
  } on FileSystemException {
    stdout.write('busy');
  }
  await file.close();
}
```

`apps/desktop/test/platform/single_instance_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/single_instance.dart';

Future<String> _probe(String lockPath) async {
  final result = await Process.run('dart', [
    'test/fixtures/lock_probe.dart',
    lockPath,
  ]);
  return (result.stdout as String).trim();
}

void main() {
  late Directory dir;

  setUp(
    () async => dir = await Directory.systemTemp.createTemp('shellx-lock-'),
  );
  tearDown(() async => dir.delete(recursive: true));

  test(
    'a second process cannot take the lock until the first releases it',
    () async {
      final lock = SingleInstanceLock(dir);
      expect(await lock.acquire(), isTrue);
      expect(await _probe(lock.lockPath), 'busy');
      await lock.release();
      expect(await _probe(lock.lockPath), 'acquired');
    },
  );

  test(
    'a second launch can ask the running instance to come forward',
    () async {
      final lock = SingleInstanceLock(dir);
      expect(await lock.acquire(), isTrue);
      final request = lock.activationRequests().first;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await SingleInstanceLock(dir).signalRunningInstance();
      await request.timeout(const Duration(seconds: 10));
      await lock.release();
    },
  );
}
```

- [ ] **Step 2: Chạy test, xác nhận thất bại**

Run: `flutter test test/platform/os_integration_test.dart test/platform/single_instance_test.dart`
Expected: FAIL — `Error when reading 'lib/src/platform/keep_awake.dart': No such file or directory` (và tương tự cho `single_instance.dart`).

- [ ] **Step 3: Cài đặt**

`apps/desktop/lib/src/platform/keep_awake.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:win32/win32.dart' show SetThreadExecutionState;

/// Prevents idle system sleep while enabled. Never prevents lid-close sleep.
abstract interface class KeepAwake {
  Future<void> setEnabled(bool enabled);
}

typedef ProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// macOS: child process `caffeinate -i -w <agent pid>`. `-i` blocks idle
/// sleep only; `-w` makes caffeinate exit on its own if the agent dies.
final class CaffeinateKeepAwake implements KeepAwake {
  CaffeinateKeepAwake({ProcessStarter? start, int? agentPid})
    : _start = start ?? Process.start,
      _agentPid = agentPid ?? pid;

  final ProcessStarter _start;
  final int _agentPid;
  Process? _process;
  Future<void> _queue = Future<void>.value();

  @override
  Future<void> setEnabled(bool enabled) =>
      _queue = _queue.then((_) => _apply(enabled));

  Future<void> _apply(bool enabled) async {
    if (enabled) {
      if (_process != null) return;
      final process = await _start('/usr/bin/caffeinate', [
        '-i',
        '-w',
        '$_agentPid',
      ]);
      _process = process;
      unawaited(
        process.exitCode.then((_) {
          if (identical(_process, process)) _process = null;
        }),
      );
    } else {
      _process?.kill();
      _process = null;
    }
  }
}

typedef ExecutionStateSetter = int Function(int flags);

/// Windows: SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED) on the
/// Dart UI thread, which lives as long as the app.
final class WindowsKeepAwake implements KeepAwake {
  WindowsKeepAwake({ExecutionStateSetter? setState})
    : _setState = setState ?? SetThreadExecutionState;

  static const int esContinuous = 0x80000000;
  static const int esSystemRequired = 0x00000001;

  final ExecutionStateSetter _setState;

  @override
  Future<void> setEnabled(bool enabled) async {
    _setState(enabled ? (esContinuous | esSystemRequired) : esContinuous);
  }
}
```

`apps/desktop/lib/src/platform/launch_at_login.dart`:

```dart
import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';

abstract interface class LaunchAtLogin {
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);
}

/// Package launch_at_startup. Windows: HKCU\...\Run value "ShellX".
/// macOS: the `launch_at_startup` channel in MainFlutterWindow.swift
/// (SMAppService on 13+, LaunchAgent plist on 12).
final class PackageLaunchAtLogin implements LaunchAtLogin {
  PackageLaunchAtLogin() {
    final exe = Platform.resolvedExecutable;
    launchAtStartup.setup(
      appName: 'ShellX',
      appPath: Platform.isWindows ? '"$exe"' : exe,
    );
  }

  @override
  Future<bool> isEnabled() => launchAtStartup.isEnabled();

  @override
  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }
}
```

`apps/desktop/lib/src/platform/single_instance.dart`:

```dart
import 'dart:async';
import 'dart:io';

/// "Only one agent at a time" (spec §8.2): an exclusive lock on
/// `<app support>/shellx.lock`, held for the life of the process and released
/// by the OS even if the process crashes.
final class SingleInstanceLock {
  SingleInstanceLock(this.directory);

  static const String lockFileName = 'shellx.lock';
  static const String activationFileName = 'activate.signal';

  final Directory directory;
  RandomAccessFile? _handle;

  String get lockPath =>
      '${directory.path}${Platform.pathSeparator}$lockFileName';
  String get _activationPath =>
      '${directory.path}${Platform.pathSeparator}$activationFileName';

  /// True if this process now owns the lock.
  Future<bool> acquire() async {
    await directory.create(recursive: true);
    final handle = await File(lockPath).open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
    } on FileSystemException {
      await handle.close();
      return false;
    }
    _handle = handle;
    return true;
  }

  Future<void> release() async {
    final handle = _handle;
    _handle = null;
    if (handle == null) return;
    await handle.unlock();
    await handle.close();
  }

  /// Called by a second launch just before it exits.
  Future<void> signalRunningInstance() => File(
    _activationPath,
  ).writeAsString('${DateTime.now().microsecondsSinceEpoch}', flush: true);

  /// Fires when a second launch called [signalRunningInstance].
  Stream<void> activationRequests() => directory
      .watch(events: FileSystemEvent.create | FileSystemEvent.modify)
      .where((event) => event.path.endsWith(activationFileName))
      .map((_) {});
}
```

`apps/desktop/lib/src/platform/notifier.dart`:

```dart
import 'package:local_notifier/local_notifier.dart';

abstract interface class SystemNotifier {
  Future<void> show({
    required String title,
    String? body,
    void Function()? onClick,
  });
}

/// Package local_notifier (NSUserNotification on macOS, WinToast on Windows).
final class LocalSystemNotifier implements SystemNotifier {
  LocalSystemNotifier._();

  static Future<LocalSystemNotifier> setup() async {
    await localNotifier.setup(
      appName: 'ShellX',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    return LocalSystemNotifier._();
  }

  @override
  Future<void> show({
    required String title,
    String? body,
    void Function()? onClick,
  }) async {
    final notification = LocalNotification(title: title, body: body);
    notification.onClick = onClick;
    await notification.show();
  }
}
```

`apps/desktop/lib/src/platform/url_opener.dart`:

```dart
import 'dart:io';

typedef UrlCommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

abstract interface class UrlOpener {
  Future<void> open(Uri uri);
}

/// Opens URLs (download links, the macOS Full Disk Access pane) with the OS.
final class SystemUrlOpener implements UrlOpener {
  SystemUrlOpener({bool? isWindows, UrlCommandRunner? run})
    : _isWindows = isWindows ?? Platform.isWindows,
      _run = run ?? Process.run;

  static final Uri fullDiskAccessPane = Uri.parse(
    'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
  );

  final bool _isWindows;
  final UrlCommandRunner _run;

  @override
  Future<void> open(Uri uri) async {
    if (_isWindows) {
      await _run('rundll32', ['url.dll,FileProtocolHandler', uri.toString()]);
    } else {
      await _run('/usr/bin/open', [uri.toString()]);
    }
  }
}
```

`apps/desktop/lib/src/platform/wake_detector.dart`:

```dart
import 'dart:async';

/// Detects that the computer slept: Dart timers run on a monotonic clock that
/// stops during sleep while the wall clock keeps going, so after wake the gap
/// between two ticks is much larger than [interval].
final class WakeDetector {
  WakeDetector({
    required this.onWake,
    DateTime Function()? now,
    this.interval = const Duration(seconds: 5),
    this.tolerance = const Duration(seconds: 15),
  }) : _now = now ?? DateTime.now;

  final void Function() onWake;
  final DateTime Function() _now;
  final Duration interval;
  final Duration tolerance;
  Timer? _timer;
  DateTime? _last;

  void start() {
    _last = _now();
    _timer ??= Timer.periodic(interval, (_) => check());
  }

  /// One tick; public so tests can drive it with a fake clock.
  void check() {
    final now = _now();
    final last = _last;
    _last = now;
    if (last != null && now.difference(last) > interval + tolerance) {
      onWake();
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
```

- [ ] **Step 4: Chạy test, xác nhận qua**

Run: `flutter test test/platform/os_integration_test.dart test/platform/single_instance_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/src/platform test/platform/os_integration_test.dart test/platform/single_instance_test.dart test/fixtures
git commit -m "feat(desktop): add keep-awake, launch-at-login, single-instance and notifier adapters"
```

---

### Task 6: Seam `AgentRuntime`, state và kiểm tra phiên bản

**Files:**
- Create: `apps/desktop/lib/src/config.dart`, `apps/desktop/lib/src/agent/storage_keys.dart`, `agent_runtime.dart`, `update_check.dart`, `agent_state.dart`
- Test: `apps/desktop/test/agent/update_check_test.dart`, `apps/desktop/test/agent/core_agent_runtime_test.dart`

**Interfaces:**
- Consumes (overview §5.5–5.6, plan 03): `RelayConnection({required Uri wsUri, required String? Function() token, RelaySocketConnector connector, …})`, `RelayConnectionState`, `RelaySocket`, `RelaySocketConnector`, `ioRelaySocketConnector`, `RelayCloseCode.revoked`, `ShellxApi`, `NoiseKeyPair`, `PairingUri`, `VersionInfo`, `LatestAgent`, `DevicePlatform`, `compareVersions`; `SessionManager`, `SessionSummary`, `PairingCodeManager({DateTime Function()? now})` (`activeSecret`, TTL mặc định 5 phút), `TrustedStore`, `AgentService` (`start()` gọi `relay.start()`; `stop()` bỏ mọi kênh và gọi `relay.stop()`, **không** đóng phiên), `AgentEvent`, `PtyFactory`, `ShellResolver`, `PlatformShellResolver`.
- Produces:
  - `const String kRelayBaseUrl` (`--dart-define=SHELLX_RELAY`, mặc định `https://relay.shellx.pro`); `Uri relayWebSocketUri(Uri base)`.
  - `abstract final class DesktopStorageKeys { token = 'auth_token', deviceId = 'device_id', userId = 'user_id', email = 'email' }`.
  - `const Duration kPairingTtl`; `final class AgentCredentials {token, deviceId, userId, email}`; `final class PairingView { const PairingView({required PairingUri uri, required DateTime expiresAt}); }`.
  - `abstract interface class AgentRuntime { Future<void> start(); Future<void> stop(); RelayConnectionState get relayState; Stream<RelayConnectionState> get relayStates; Stream<AgentEvent> get events; List<SessionSummary> get sessions; Stream<void> get sessionChanges; PairingView startPairing(); void cancelPairing(); Future<void> revoke(String mobileId); void closeSession(int id); void closeAllSessions(); void reconnectNow(); }`.
  - `final class RuntimeParams {credentials, identity, trusted, api}`; `typedef AgentRuntimeFactory = AgentRuntime Function(RuntimeParams params);`; `final class CoreAgentRuntime implements AgentRuntime { CoreAgentRuntime(RuntimeParams params, {required Uri relayBaseUri, required String appVersion, required PtyFactory ptyFactory, required ShellResolver shellResolver, required String homeDirectory, required Map<String, String> baseEnvironment, RelaySocketConnector connector = ioRelaySocketConnector, DateTime Function()? now}); PairingCodeManager get pairingCodes; }`.
  - `final class UpdateNotice {version, url, required}`; `UpdateNotice? evaluateUpdate(VersionInfo info, {required String appVersion, required DevicePlatform platform})`.
  - `enum AuthPhase { loading, signedOut, signedIn }`; `final class AgentViewState` (fields: `phase, email, signedOutNotice, remoteAccess, keepAwake, launchAtStartup, onboardingDone, relay, activeChannels, sessions, trusted, pairing, update`; `bool get signedIn`; `copyWith(...)` — `email`, `pairing`, `update` nhận `null` để xóa).

- [ ] **Step 1: Viết test thất bại**

`apps/desktop/test/agent/update_check_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/update_check.dart';
import 'package:shellx_desktop/src/config.dart';

VersionInfo _info({
  String min = '1.0.0',
  String latest = '1.0.0',
}) => VersionInfo(
  minAgent: min,
  minMobile: '1.0.0',
  latestAgent: LatestAgent(
    version: latest,
    macUrl: Uri.parse(
      'https://download.shellx.pro/desktop/$latest/ShellX-$latest.dmg',
    ),
    winUrl: Uri.parse(
      'https://download.shellx.pro/desktop/$latest/ShellX-Setup-$latest.exe',
    ),
  ),
);

void main() {
  test('up to date → no notice', () {
    expect(
      evaluateUpdate(
        _info(),
        appVersion: '1.0.0',
        platform: DevicePlatform.macos,
      ),
      isNull,
    );
  });

  test('newer latest_agent → optional update with the platform URL', () {
    final mac = evaluateUpdate(
      _info(latest: '1.1.0'),
      appVersion: '1.0.0',
      platform: DevicePlatform.macos,
    )!;
    final win = evaluateUpdate(
      _info(latest: '1.1.0'),
      appVersion: '1.0.0',
      platform: DevicePlatform.windows,
    )!;
    expect(mac.required, isFalse);
    expect(mac.url.path, endsWith('ShellX-1.1.0.dmg'));
    expect(win.url.path, endsWith('ShellX-Setup-1.1.0.exe'));
  });

  test('below min_agent → required update', () {
    final notice = evaluateUpdate(
      _info(min: '1.2.0', latest: '1.2.0'),
      appVersion: '1.0.0',
      platform: DevicePlatform.macos,
    )!;
    expect(notice.required, isTrue);
    expect(notice.version, '1.2.0');
  });

  test('an unparsable server version is ignored instead of crashing', () {
    expect(
      evaluateUpdate(
        _info(latest: 'soon'),
        appVersion: '1.0.0',
        platform: DevicePlatform.macos,
      ),
      isNull,
    );
  });

  test('relay WebSocket URI follows the base URL scheme', () {
    expect(
      relayWebSocketUri(Uri.parse('https://relay.shellx.pro')).toString(),
      'wss://relay.shellx.pro/v1/ws',
    );
    expect(
      relayWebSocketUri(Uri.parse('http://127.0.0.1:8787')).toString(),
      'ws://127.0.0.1:8787/v1/ws',
    );
  });
}
```

`apps/desktop/test/agent/core_agent_runtime_test.dart` (chạy trên `RelayConnection`/`AgentService` thật của plan 02/03 với socket giả):

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_runtime.dart';

final class FakeRelaySocket implements RelaySocket {
  final StreamController<Object> incoming = StreamController<Object>();
  final List<String> sentText = [];
  final List<Uint8List> sentBytes = [];
  int? _closeCode;

  @override
  Stream<Object> get messages => incoming.stream;
  @override
  void sendText(String text) => sentText.add(text);
  @override
  void sendBytes(Uint8List bytes) => sentBytes.add(bytes);
  @override
  Future<void> close([int? code, String? reason]) async {
    _closeCode ??= code;
    if (!incoming.isClosed) await incoming.close();
  }

  @override
  int? get closeCode => _closeCode;

  /// The hub closes the socket with [code].
  Future<void> serverClose(int code) async {
    _closeCode = code;
    await incoming.close();
  }
}

final class _NoPty implements PtyFactory {
  @override
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) => throw UnsupportedError('no sessions in this test');
}

void main() {
  late FakeRelaySocket socket;
  late List<(Uri, Map<String, String>)> connects;
  late NoiseKeyPair identity;
  final now = DateTime(2026, 9, 25, 12);

  Future<CoreAgentRuntime> build() async {
    identity = await NoiseKeyPair.generate();
    final store = InMemoryKeyValueStore();
    return CoreAgentRuntime(
      RuntimeParams(
        credentials: const AgentCredentials(
          token: 'agent-token',
          deviceId: '22222222-2222-4222-8222-222222222222',
          userId: '11111111-1111-4111-8111-111111111111',
          email: 'phu@example.com',
        ),
        identity: identity,
        trusted: TrustedStore(store),
        api: ShellxApi(baseUri: Uri.parse('https://relay.shellx.pro')),
      ),
      relayBaseUri: Uri.parse('https://relay.shellx.pro'),
      appVersion: '1.0.0',
      ptyFactory: _NoPty(),
      shellResolver: PlatformShellResolver(
        operatingSystem: 'macos',
        environment: const {'HOME': '/Users/phu'},
      ),
      homeDirectory: '/Users/phu',
      baseEnvironment: const {'HOME': '/Users/phu'},
      connector: (uri, headers) async {
        connects.add((uri, headers));
        return socket = FakeRelaySocket();
      },
      now: () => now,
    );
  }

  setUp(() => connects = []);

  test(
    'start() connects to wss://relay.shellx.pro/v1/ws with the bearer token',
    () async {
      final runtime = await build();
      await runtime.start();
      await pumpEventQueue();
      expect(connects, hasLength(1));
      expect(connects.single.$1.toString(), 'wss://relay.shellx.pro/v1/ws');
      final auth = connects.single.$2.entries.firstWhere(
        (e) => e.key.toLowerCase() == 'authorization',
      );
      expect(auth.value, 'Bearer agent-token');
      await runtime.stop();
    },
  );

  test('a 4002 close is reported as revoked', () async {
    final runtime = await build();
    final states = <RelayConnectionState>[];
    runtime.relayStates.listen(states.add);
    await runtime.start();
    await pumpEventQueue();
    await socket.serverClose(RelayCloseCode.revoked);
    await pumpEventQueue();
    expect(states, contains(RelayConnectionState.revoked));
    await runtime.stop();
  });

  test(
    'pairing QR carries this agent, expires in 5 minutes, and cancel invalidates it',
    () async {
      final runtime = await build();
      await runtime.start();
      final view = runtime.startPairing();
      expect(view.uri.agentDeviceId, '22222222-2222-4222-8222-222222222222');
      expect(view.uri.agentPublicKey, identity.publicKey);
      expect(view.uri.secret, hasLength(32));
      expect(view.expiresAt, now.add(const Duration(minutes: 5)));
      expect(runtime.pairingCodes.activeSecret, isNotNull);

      runtime.cancelPairing();
      expect(runtime.pairingCodes.activeSecret, isNull);
      await runtime.stop();
    },
  );

  test('stop() leaves the relay stopped', () async {
    final runtime = await build();
    await runtime.start();
    await pumpEventQueue();
    await runtime.stop();
    expect(runtime.relayState, RelayConnectionState.stopped);
  });
}
```

- [ ] **Step 2: Chạy test, xác nhận thất bại**

Run: `flutter test test/agent/update_check_test.dart test/agent/core_agent_runtime_test.dart`
Expected: FAIL — `Error when reading 'lib/src/agent/update_check.dart': No such file or directory`.

- [ ] **Step 3: Cài đặt**

`apps/desktop/lib/src/config.dart`:

```dart
/// Relay base URL: production by default, override for local development with
/// `flutter run --dart-define=SHELLX_RELAY=http://127.0.0.1:8787`.
const String kRelayBaseUrl = String.fromEnvironment(
  'SHELLX_RELAY',
  defaultValue: 'https://relay.shellx.pro',
);

/// `wss://<host>/v1/ws` for an https base, `ws://<host>/v1/ws` for http.
Uri relayWebSocketUri(Uri base) =>
    base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/v1/ws');
```

`apps/desktop/lib/src/agent/storage_keys.dart`:

```dart
/// Secure-storage keys owned by the desktop app. `device_private_key`
/// (DeviceIdentity.storageKey) and `trusted_devices` (TrustedStore.storageKey)
/// are owned by shellx_core / shellx_agent.
abstract final class DesktopStorageKeys {
  static const String token = 'auth_token';
  static const String deviceId = 'device_id';
  static const String userId = 'user_id';
  static const String email = 'email';
}
```

`apps/desktop/lib/src/agent/agent_runtime.dart`:

```dart
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import '../config.dart';

/// Pairing codes live 5 minutes (spec §5.3); PairingCodeManager's default TTL.
const Duration kPairingTtl = Duration(minutes: 5);

final class AgentCredentials {
  const AgentCredentials({
    required this.token,
    required this.deviceId,
    required this.userId,
    required this.email,
  });

  final String token;
  final String deviceId;
  final String userId;
  final String email;
}

final class PairingView {
  const PairingView({required this.uri, required this.expiresAt});

  final PairingUri uri;
  final DateTime expiresAt;
}

/// Everything that exists only while signed in with remote access on: the
/// relay link, AgentService and SessionManager. The controller talks to this
/// seam so its tests do not depend on shellx_agent internals.
abstract interface class AgentRuntime {
  /// Starts AgentService, which calls `relay.start()`.
  Future<void> start();

  /// Closes every session, stops AgentService and disconnects from the relay.
  Future<void> stop();

  RelayConnectionState get relayState;
  Stream<RelayConnectionState> get relayStates;
  Stream<AgentEvent> get events;
  List<SessionSummary> get sessions;
  Stream<void> get sessionChanges;

  PairingView startPairing();
  void cancelPairing();
  Future<void> revoke(String mobileId);
  void closeSession(int id);
  void closeAllSessions();
  void reconnectNow();
}

final class RuntimeParams {
  const RuntimeParams({
    required this.credentials,
    required this.identity,
    required this.trusted,
    required this.api,
  });

  final AgentCredentials credentials;
  final NoiseKeyPair identity;
  final TrustedStore trusted;
  final ShellxApi api;
}

typedef AgentRuntimeFactory = AgentRuntime Function(RuntimeParams params);

/// Production [AgentRuntime] wiring shellx_core + shellx_agent.
final class CoreAgentRuntime implements AgentRuntime {
  CoreAgentRuntime(
    RuntimeParams params, {
    required Uri relayBaseUri,
    required String appVersion,
    required PtyFactory ptyFactory,
    required ShellResolver shellResolver,
    required String homeDirectory,
    required Map<String, String> baseEnvironment,
    RelaySocketConnector connector = ioRelaySocketConnector,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    final token = params.credentials.token;
    _relay = RelayConnection(
      wsUri: relayWebSocketUri(relayBaseUri),
      token: () => token,
      connector: connector,
    );
    _sessions = SessionManager(
      ptyFactory: ptyFactory,
      shellResolver: shellResolver,
      homeDirectory: homeDirectory,
      baseEnvironment: baseEnvironment,
    );
    _pairing = PairingCodeManager(now: _now);
    _service = AgentService(
      relay: _relay,
      api: params.api,
      deviceId: params.credentials.deviceId,
      identity: params.identity,
      trusted: params.trusted,
      sessions: _sessions,
      pairing: _pairing,
      appVersion: appVersion,
    );
  }

  final DateTime Function() _now;
  late final RelayConnection _relay;
  late final SessionManager _sessions;
  late final PairingCodeManager _pairing;
  late final AgentService _service;

  /// Exposed for tests.
  PairingCodeManager get pairingCodes => _pairing;

  @override
  Future<void> start() => _service.start();

  /// AgentService.stop() drops the channels and stops the relay but leaves
  /// sessions alone, so they are closed here first (plan 03 contract).
  @override
  Future<void> stop() async {
    _sessions.closeAll();
    await _service.stop();
  }

  @override
  RelayConnectionState get relayState => _relay.state;
  @override
  Stream<RelayConnectionState> get relayStates => _relay.states;
  @override
  Stream<AgentEvent> get events => _service.events;
  @override
  List<SessionSummary> get sessions => _sessions.sessions;
  @override
  Stream<void> get sessionChanges => _sessions.changes;

  @override
  PairingView startPairing() {
    final expiresAt = _now().add(kPairingTtl);
    return PairingView(uri: _service.startPairing(), expiresAt: expiresAt);
  }

  @override
  void cancelPairing() => _service.cancelPairing();
  @override
  Future<void> revoke(String mobileId) => _service.revoke(mobileId);
  @override
  void closeSession(int id) => _sessions.closeSession(id);
  @override
  void closeAllSessions() => _sessions.closeAll();
  @override
  void reconnectNow() => _relay.reconnectNow();
}
```

`apps/desktop/lib/src/agent/update_check.dart`:

```dart
import 'package:shellx_core/shellx_core.dart';

final class UpdateNotice {
  const UpdateNotice({
    required this.version,
    required this.url,
    required this.required,
  });

  final String version;
  final Uri url;

  /// True when this build is older than `min_agent` ("Cần cập nhật app").
  final bool required;
}

final RegExp _semver = RegExp(r'^\d+\.\d+\.\d+$');

/// Spec §14: notify when `/v1/version` offers a newer agent; §12: "Cần cập
/// nhật app" when this build is below `min_agent`. Returns null when up to
/// date or when any version is not `x.y.z` (never crash on server data).
UpdateNotice? evaluateUpdate(
  VersionInfo info, {
  required String appVersion,
  required DevicePlatform platform,
}) {
  final latest = info.latestAgent;
  if (![appVersion, info.minAgent, latest.version].every(_semver.hasMatch)) {
    return null;
  }
  final url = platform == DevicePlatform.windows
      ? latest.winUrl
      : latest.macUrl;
  if (compareVersions(appVersion, info.minAgent) < 0) {
    return UpdateNotice(version: latest.version, url: url, required: true);
  }
  if (compareVersions(latest.version, appVersion) > 0) {
    return UpdateNotice(version: latest.version, url: url, required: false);
  }
  return null;
}
```

`apps/desktop/lib/src/agent/agent_state.dart`:

```dart
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import 'agent_runtime.dart';
import 'update_check.dart';

enum AuthPhase { loading, signedOut, signedIn }

const Object _unset = Object();

/// Everything the tray and the windows render. Immutable.
final class AgentViewState {
  const AgentViewState({
    this.phase = AuthPhase.loading,
    this.email,
    this.signedOutNotice = false,
    this.remoteAccess = true,
    this.keepAwake = true,
    this.launchAtStartup = true,
    this.onboardingDone = false,
    this.relay = RelayConnectionState.stopped,
    this.activeChannels = 0,
    this.sessions = const <SessionSummary>[],
    this.trusted = const <TrustedDevice>[],
    this.pairing,
    this.update,
  });

  final AuthPhase phase;
  final String? email;

  /// True after a 4002 close signed us out; the login window explains why.
  final bool signedOutNotice;
  final bool remoteAccess;
  final bool keepAwake;
  final bool launchAtStartup;
  final bool onboardingDone;

  /// `stopped` whenever there is no runtime (signed out or remote access off).
  final RelayConnectionState relay;
  final int activeChannels;
  final List<SessionSummary> sessions;
  final List<TrustedDevice> trusted;
  final PairingView? pairing;
  final UpdateNotice? update;

  bool get signedIn => phase == AuthPhase.signedIn;

  AgentViewState copyWith({
    AuthPhase? phase,
    Object? email = _unset,
    bool? signedOutNotice,
    bool? remoteAccess,
    bool? keepAwake,
    bool? launchAtStartup,
    bool? onboardingDone,
    RelayConnectionState? relay,
    int? activeChannels,
    List<SessionSummary>? sessions,
    List<TrustedDevice>? trusted,
    Object? pairing = _unset,
    Object? update = _unset,
  }) {
    return AgentViewState(
      phase: phase ?? this.phase,
      email: identical(email, _unset) ? this.email : email as String?,
      signedOutNotice: signedOutNotice ?? this.signedOutNotice,
      remoteAccess: remoteAccess ?? this.remoteAccess,
      keepAwake: keepAwake ?? this.keepAwake,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      relay: relay ?? this.relay,
      activeChannels: activeChannels ?? this.activeChannels,
      sessions: sessions ?? this.sessions,
      trusted: trusted ?? this.trusted,
      pairing: identical(pairing, _unset)
          ? this.pairing
          : pairing as PairingView?,
      update: identical(update, _unset) ? this.update : update as UpdateNotice?,
    );
  }
}
```

- [ ] **Step 4: Chạy test, xác nhận qua**

Run: `flutter test test/agent/update_check_test.dart test/agent/core_agent_runtime_test.dart`
Expected: `All tests passed!` (9 test). `core_agent_runtime_test.dart` kiểm tra đúng những điều hợp đồng đã hứa: `start()` kết nối `wss://…/v1/ws` với `Authorization: Bearer`, đóng 4002 → `revoked`, `startPairing()`/`cancelPairing()` qua `PairingCodeManager` thật, `stop()` → `stopped`. Nếu một test ở đây hỏng thì đó là lệch hợp đồng với plan 02/03 — báo lại, không sửa test cho khớp.

- [ ] **Step 5: Commit**

```bash
git add lib/src/config.dart lib/src/agent test/agent/update_check_test.dart test/agent/core_agent_runtime_test.dart
git commit -m "feat(desktop): add agent runtime seam, view state and update check"
```

---

### Task 7: `AgentController` — đăng nhập, đăng xuất, thu hồi token, công tắc, ghép nối, cập nhật

**Files:**
- Create: `apps/desktop/lib/src/agent/desktop_services.dart`, `apps/desktop/lib/src/agent/agent_controller.dart`
- Create (test support): `apps/desktop/test/support/fakes.dart`
- Test: `apps/desktop/test/agent/agent_controller_test.dart`

**Interfaces:**
- Consumes: Task 2 `AppLocalizations`; Task 4 `SettingsStore`, `SettingKeys`, `InMemorySettingsStore`; Task 5 `KeepAwake`, `LaunchAtLogin`, `SystemNotifier`, `UrlOpener`, `WakeDetector`; Task 6 toàn bộ; core `DeviceIdentity.loadOrCreate`, `DeviceInfo`, `DeviceKind`, `ShellxApi` (`login/register` đặt `api.token`, `logout()` luôn xóa nó; lỗi mạng = `ApiException(status: 0, code: 'network')`, token hỏng = `401 unauthorized`, 429 phân biệt bằng `status`), `ApiException`, `InMemoryKeyValueStore`; agent `TrustedStore`, `TrustedDevice`, `MobilePaired`, `SessionOpenedByMobile`, `ActiveChannelsChanged`, `const AgentRevoked()` (plan 03).
- Produces:
  - `final class DesktopServices { const DesktopServices({required KeyValueStore secureStore, required SettingsStore settings, required ShellxApi api, required AgentRuntimeFactory runtimeFactory, required KeepAwake keepAwake, required LaunchAtLogin launchAtLogin, required SystemNotifier notifier, required UrlOpener urlOpener, required AppLocalizations l10n, required String appVersion, required DevicePlatform platform, required String deviceName, Duration updateInterval = const Duration(hours: 24), Future<void> Function()? quitApp}); }`; `final desktopServicesProvider = Provider<DesktopServices>(…)` (phải override); `final clockProvider = Provider<DateTime Function()>(…)`.
  - `final agentControllerProvider = NotifierProvider<AgentController, AgentViewState>(AgentController.new);`
  - `class AgentController extends Notifier<AgentViewState>`: `Future<void> bootstrap({bool watchForWake = true})`, `Future<void> signIn({required String email, required String password, required bool register})` (ném `ApiException`), `Future<void> signOut()`, `Future<void> changePassword(String newPassword)` (ném `ApiException`), `Future<void> setRemoteAccess(bool)`, `Future<void> setKeepAwake(bool)`, `Future<void> setLaunchAtStartup(bool)`, `Future<void> completeOnboarding()`, `PairingView? startPairing()`, `void cancelPairing()`, `Future<void> revoke(String mobileId)`, `void closeSession(int id)`, `void closeAllSessions()`, `void handleWake()`, `Future<void> checkForUpdate()`, `Future<void> shutdown()`, `AgentRuntime? get runtime`.
  - Test support: `TestHarness({Map<String,bool>? settings, Locale locale, String appVersion, DevicePlatform platform})` (`secureStore`, `settings`, `relay`, `keepAwake`, `launchAtLogin`, `notifier`, `urlOpener`, `l10n`, `runtimes`, `runtime`, `quits`, `api`, `services()`, `seedSignedIn()`), `FakeRelayApi` (`failures`, `offline`, `version`, `routes`, `last`, `bearerOf`), `FakeAgentRuntime` (`emitRelay`, `eventController`, `sessionController`, `currentSessions`, `started`, `stopped`, `closedAll`, `pairingStarts`, `pairingCancels`, `reconnects`, `revoked`, `closedSessions`), `RecordingKeepAwake`, `FakeLaunchAtLogin`, `RecordingNotifier`, `RecordingUrlOpener`, `TrustedDevice phone(String id, String name)`.

- [ ] **Step 1: Viết test support**

`apps/desktop/test/support/fakes.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_runtime.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/keep_awake.dart';
import 'package:shellx_desktop/src/platform/launch_at_login.dart';
import 'package:shellx_desktop/src/platform/notifier.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/platform/url_opener.dart';

/// In-process stand-in for the relay REST API (spec §10.2 wire format).
final class FakeRelayApi {
  final List<http.Request> requests = [];
  String userId = '11111111-1111-4111-8111-111111111111';
  String deviceId = '22222222-2222-4222-8222-222222222222';
  String token = 'token-1';
  bool offline = false;

  /// `'POST /v1/auth/login'` → (status, error code) to fail that route with.
  final Map<String, (int, String)> failures = {};
  Map<String, Object?> version = {
    'min_agent': '1.0.0',
    'min_mobile': '1.0.0',
    'latest_agent': {
      'version': '1.0.0',
      'mac_url': 'https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg',
      'win_url':
          'https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe',
    },
  };

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    if (offline) throw http.ClientException('offline');
    final route = '${request.method} ${request.url.path}';
    final failure = failures[route];
    if (failure != null) {
      return http.Response(
        jsonEncode({
          'error': {'code': failure.$2, 'message': failure.$2},
        }),
        failure.$1,
        headers: {'content-type': 'application/json'},
      );
    }
    if (route == 'POST /v1/auth/login' || route == 'POST /v1/auth/register') {
      return http.Response(
        jsonEncode({'user_id': userId, 'device_id': deviceId, 'token': token}),
        route.endsWith('register') ? 201 : 200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (route == 'GET /v1/version') {
      return http.Response(
        jsonEncode(version),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('', 204);
  });

  List<String> get routes => [
    for (final r in requests) '${r.method} ${r.url.path}',
  ];

  http.Request last(String route) =>
      requests.lastWhere((r) => '${r.method} ${r.url.path}' == route);

  String? bearerOf(http.Request request) => request.headers.entries
      .firstWhere(
        (e) => e.key.toLowerCase() == 'authorization',
        orElse: () => const MapEntry('', ''),
      )
      .value;
}

final class FakeAgentRuntime implements AgentRuntime {
  FakeAgentRuntime(this.params);

  final RuntimeParams params;
  final StreamController<RelayConnectionState> relayController =
      StreamController<RelayConnectionState>.broadcast(sync: true);
  final StreamController<AgentEvent> eventController =
      StreamController<AgentEvent>.broadcast(sync: true);
  final StreamController<void> sessionController =
      StreamController<void>.broadcast(sync: true);

  RelayConnectionState currentRelay = RelayConnectionState.connecting;
  List<SessionSummary> currentSessions = [];
  bool started = false;
  bool stopped = false;
  int pairingStarts = 0;
  int pairingCancels = 0;
  int reconnects = 0;
  final List<String> revoked = [];
  final List<int> closedSessions = [];
  bool closedAll = false;

  void emitRelay(RelayConnectionState state) {
    currentRelay = state;
    relayController.add(state);
  }

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> stop() async {
    stopped = true;
    closedAll = true;
  }

  @override
  RelayConnectionState get relayState => currentRelay;
  @override
  Stream<RelayConnectionState> get relayStates => relayController.stream;
  @override
  Stream<AgentEvent> get events => eventController.stream;
  @override
  List<SessionSummary> get sessions => currentSessions;
  @override
  Stream<void> get sessionChanges => sessionController.stream;

  /// Codes from this fake expire at 12:05 plus one minute per extra start.
  @override
  PairingView startPairing() {
    pairingStarts++;
    return PairingView(
      uri: PairingUri(
        agentDeviceId: params.credentials.deviceId,
        agentPublicKey: params.identity.publicKey,
        secret: Uint8List(32),
      ),
      expiresAt: DateTime(2026, 9, 25, 12, 4 + pairingStarts),
    );
  }

  @override
  void cancelPairing() => pairingCancels++;
  @override
  Future<void> revoke(String mobileId) async {
    revoked.add(mobileId);
    await params.trusted.remove(mobileId);
  }

  @override
  void closeSession(int id) => closedSessions.add(id);
  @override
  void closeAllSessions() => closedAll = true;
  @override
  void reconnectNow() => reconnects++;
}

final class RecordingKeepAwake implements KeepAwake {
  final List<bool> calls = [];
  bool? get last => calls.isEmpty ? null : calls.last;
  @override
  Future<void> setEnabled(bool enabled) async => calls.add(enabled);
}

final class FakeLaunchAtLogin implements LaunchAtLogin {
  bool enabled = false;
  bool fail = false;
  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<void> setEnabled(bool value) async {
    if (fail) throw Exception('denied');
    enabled = value;
  }
}

final class ShownNotification {
  const ShownNotification(this.title, this.body, this.onClick);
  final String title;
  final String? body;
  final void Function()? onClick;
}

final class RecordingNotifier implements SystemNotifier {
  final List<ShownNotification> shown = [];
  @override
  Future<void> show({
    required String title,
    String? body,
    void Function()? onClick,
  }) async => shown.add(ShownNotification(title, body, onClick));
}

final class RecordingUrlOpener implements UrlOpener {
  final List<Uri> opened = [];
  @override
  Future<void> open(Uri uri) async => opened.add(uri);
}

/// A trusted phone for tests.
TrustedDevice phone(String id, String name) => TrustedDevice(
  mobileId: id,
  publicKey: Uint8List(32),
  name: name,
  pairedAt: DateTime(2026, 9, 1),
);

/// Bundles every fake so tests can inspect them.
final class TestHarness {
  TestHarness({
    Map<String, bool>? settings,
    Locale locale = const Locale('en'),
    this.appVersion = '1.0.0',
    this.platform = DevicePlatform.macos,
  }) : settings = InMemorySettingsStore(settings),
       l10n = lookupAppLocalizations(locale);

  final InMemoryKeyValueStore secureStore = InMemoryKeyValueStore();
  final InMemorySettingsStore settings;
  final FakeRelayApi relay = FakeRelayApi();
  final RecordingKeepAwake keepAwake = RecordingKeepAwake();
  final FakeLaunchAtLogin launchAtLogin = FakeLaunchAtLogin();
  final RecordingNotifier notifier = RecordingNotifier();
  final RecordingUrlOpener urlOpener = RecordingUrlOpener();
  final AppLocalizations l10n;
  final String appVersion;
  final DevicePlatform platform;
  final List<FakeAgentRuntime> runtimes = [];
  int quits = 0;

  FakeAgentRuntime get runtime => runtimes.last;

  late final ShellxApi api = ShellxApi(
    baseUri: Uri.parse('https://relay.test'),
    httpClient: relay.client,
  );

  DesktopServices services() => DesktopServices(
    secureStore: secureStore,
    settings: settings,
    api: api,
    runtimeFactory: (params) {
      final runtime = FakeAgentRuntime(params);
      runtimes.add(runtime);
      return runtime;
    },
    keepAwake: keepAwake,
    launchAtLogin: launchAtLogin,
    notifier: notifier,
    urlOpener: urlOpener,
    l10n: l10n,
    appVersion: appVersion,
    platform: platform,
    deviceName: 'Phus-MacBook-Pro',
    quitApp: () async => quits++,
  );

  /// Stores credentials as a previous successful login would have.
  Future<void> seedSignedIn({String email = 'phu@example.com'}) async {
    await secureStore.write('auth_token', relay.token);
    await secureStore.write('device_id', relay.deviceId);
    await secureStore.write('user_id', relay.userId);
    await secureStore.write('email', email);
  }
}
```

- [ ] **Step 2: Viết test thất bại**

`apps/desktop/test/agent/agent_controller_test.dart`:

```dart
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';

import '../support/fakes.dart';

void main() {
  late TestHarness h;
  late ProviderContainer container;

  AgentController controller() =>
      container.read(agentControllerProvider.notifier);
  AgentViewState state() => container.read(agentControllerProvider);

  void boot([TestHarness? harness]) {
    h = harness ?? TestHarness();
    container = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
  }

  group('startup', () {
    test(
      'without a token: signed out, no runtime, no sleep assertion',
      () async {
        boot();
        await controller().bootstrap(watchForWake: false);
        expect(state().phase, AuthPhase.signedOut);
        expect(h.runtimes, isEmpty);
        expect(h.keepAwake.last, isFalse);
      },
    );

    test(
      'with a token: signed in, runtime started, trusted list loaded',
      () async {
        boot();
        await h.seedSignedIn();
        await TrustedStore(h.secureStore).add(phone('m1', 'iPhone của Phú'));
        await controller().bootstrap(watchForWake: false);
        expect(state().phase, AuthPhase.signedIn);
        expect(state().email, 'phu@example.com');
        expect(h.runtime.started, isTrue);
        expect(h.runtime.params.credentials.token, h.relay.token);
        expect(state().trusted.single.name, 'iPhone của Phú');
        expect(h.keepAwake.last, isTrue);
      },
    );

    test(
      'relay offline at startup: stays signed in and shows disconnected',
      () async {
        boot();
        await h.seedSignedIn();
        h.relay.offline = true;
        await controller().bootstrap(watchForWake: false);
        h.runtime.emitRelay(RelayConnectionState.disconnected);
        expect(state().phase, AuthPhase.signedIn);
        expect(state().relay, RelayConnectionState.disconnected);
        expect(h.notifier.shown, isEmpty);
      },
    );
  });

  group('sign in', () {
    test(
      'login sends the agent device and stores normalized credentials',
      () async {
        boot();
        await controller().bootstrap(watchForWake: false);
        await controller().signIn(
          email: '  Phu@Example.COM ',
          password: 'correct horse',
          register: false,
        );

        final body =
            jsonDecode(h.relay.last('POST /v1/auth/login').body) as Map;
        expect(body['email'], 'phu@example.com');
        expect(body['password'], 'correct horse');
        final device = body['device'] as Map;
        expect(device['kind'], 'agent');
        expect(device['platform'], 'macos');
        expect(device['name'], 'Phus-MacBook-Pro');
        expect(
          fromBase64UrlNoPad(device['public_key'] as String),
          hasLength(32),
        );

        expect(await h.secureStore.read('auth_token'), h.relay.token);
        expect(await h.secureStore.read('device_id'), h.relay.deviceId);
        expect(await h.secureStore.read('user_id'), h.relay.userId);
        expect(await h.secureStore.read('email'), 'phu@example.com');
        expect(state().phase, AuthPhase.signedIn);
        expect(h.runtime.started, isTrue);
      },
    );

    test('register calls POST /v1/auth/register', () async {
      boot();
      await controller().signIn(
        email: 'new@example.com',
        password: '12345678',
        register: true,
      );
      expect(h.relay.routes, contains('POST /v1/auth/register'));
    });

    test('a rejected login throws ApiException and stores nothing', () async {
      boot();
      h.relay.failures['POST /v1/auth/login'] = (401, 'invalid_credentials');
      await expectLater(
        controller().signIn(
          email: 'a@b.co',
          password: 'wrongpass',
          register: false,
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'invalid_credentials',
          ),
        ),
      );
      expect(await h.secureStore.read('auth_token'), isNull);
      expect(h.runtimes, isEmpty);
    });

    test('signing in to a different account clears the trusted list', () async {
      boot();
      await h.secureStore.write('user_id', 'old-user');
      await TrustedStore(h.secureStore).add(phone('m1', 'Old phone'));
      await controller().signIn(
        email: 'a@b.co',
        password: '12345678',
        register: false,
      );
      expect(await TrustedStore(h.secureStore).list(), isEmpty);
    });

    test(
      'signing in again to the same account keeps the trusted list',
      () async {
        boot();
        await h.secureStore.write('user_id', h.relay.userId);
        await TrustedStore(h.secureStore).add(phone('m1', 'iPhone'));
        await controller().signIn(
          email: 'a@b.co',
          password: '12345678',
          register: false,
        );
        expect(await TrustedStore(h.secureStore).list(), hasLength(1));
      },
    );
  });

  group('token revoked (4002 / 401)', () {
    test(
      'closes sessions, drops the token, keeps key + user + trusted list',
      () async {
        boot();
        await h.seedSignedIn();
        await TrustedStore(h.secureStore).add(phone('m1', 'iPhone'));
        await controller().bootstrap(watchForWake: false);
        final keyBefore = await h.secureStore.read('device_private_key');

        h.runtime.emitRelay(RelayConnectionState.revoked);
        await pumpEventQueue();

        expect(state().phase, AuthPhase.signedOut);
        expect(state().signedOutNotice, isTrue);
        expect(h.runtime.stopped, isTrue);
        expect(h.runtime.closedAll, isTrue);
        expect(await h.secureStore.read('auth_token'), isNull);
        expect(await h.secureStore.read('user_id'), h.relay.userId);
        expect(await h.secureStore.read('device_private_key'), keyBefore);
        expect(await TrustedStore(h.secureStore).list(), hasLength(1));
        expect(h.relay.routes, isNot(contains('POST /v1/auth/logout')));
        expect(h.notifier.shown.single.title, h.l10n.notifySignedOutTitle);
        expect(h.keepAwake.last, isFalse);
      },
    );

    test(
      'AgentRevoked does the same, and a doubled signal notifies once',
      () async {
        boot();
        await h.seedSignedIn();
        await controller().bootstrap(watchForWake: false);
        h.runtime.eventController.add(const AgentRevoked());
        h.runtime.emitRelay(RelayConnectionState.revoked);
        await pumpEventQueue();
        expect(state().phase, AuthPhase.signedOut);
        expect(h.notifier.shown, hasLength(1));
      },
    );

    test(
      'next login: same user keeps pairings, another user clears them',
      () async {
        boot();
        await h.seedSignedIn();
        await TrustedStore(h.secureStore).add(phone('m1', 'iPhone'));
        await controller().bootstrap(watchForWake: false);
        h.runtime.emitRelay(RelayConnectionState.revoked);
        await pumpEventQueue();

        await controller().signIn(
          email: 'phu@example.com',
          password: '12345678',
          register: false,
        );
        expect(await TrustedStore(h.secureStore).list(), hasLength(1));

        h.runtime.emitRelay(RelayConnectionState.revoked);
        await pumpEventQueue();
        h.relay.userId = '33333333-3333-4333-8333-333333333333';
        await controller().signIn(
          email: 'other@example.com',
          password: '12345678',
          register: false,
        );
        expect(await TrustedStore(h.secureStore).list(), isEmpty);
      },
    );

    test('a 401 from change password also signs out', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.relay.failures['POST /v1/auth/password'] = (401, 'unauthorized');
      await expectLater(
        controller().changePassword('new password'),
        throwsA(isA<ApiException>()),
      );
      expect(state().phase, AuthPhase.signedOut);
    });
  });

  group('sign out', () {
    test(
      'closes sessions, calls logout, clears token and trusted list',
      () async {
        boot();
        await h.seedSignedIn();
        await TrustedStore(h.secureStore).add(phone('m1', 'iPhone'));
        await controller().bootstrap(watchForWake: false);
        final runtime = h.runtime;

        await controller().signOut();

        expect(runtime.stopped, isTrue);
        expect(runtime.closedAll, isTrue);
        final logout = h.relay.last('POST /v1/auth/logout');
        expect(h.relay.bearerOf(logout), 'Bearer ${h.relay.token}');
        expect(await TrustedStore(h.secureStore).list(), isEmpty);
        expect(await h.secureStore.read('auth_token'), isNull);
        expect(await h.secureStore.read('user_id'), isNull);
        expect(await h.secureStore.read('email'), 'phu@example.com');
        expect(state().phase, AuthPhase.signedOut);
        expect(state().relay, RelayConnectionState.stopped);
        expect(h.keepAwake.last, isFalse);
      },
    );

    test('still signs out locally when the relay is unreachable', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.relay.offline = true;
      await controller().signOut();
      expect(state().phase, AuthPhase.signedOut);
      expect(await h.secureStore.read('auth_token'), isNull);
    });
  });

  group('change password', () {
    test('posts the new password with the agent token', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      await controller().changePassword('a new password');
      final request = h.relay.last('POST /v1/auth/password');
      expect(jsonDecode(request.body), {'new_password': 'a new password'});
      expect(h.relay.bearerOf(request), 'Bearer ${h.relay.token}');
    });

    test('weak_password is surfaced to the caller', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.relay.failures['POST /v1/auth/password'] = (400, 'weak_password');
      await expectLater(
        controller().changePassword('short'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'weak_password'),
        ),
      );
      expect(state().phase, AuthPhase.signedIn);
    });
  });

  group('remote access switch', () {
    test('off stops the runtime and is remembered across restarts', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      final first = h.runtime;

      await controller().setRemoteAccess(false);
      expect(first.stopped, isTrue);
      expect(state().relay, RelayConnectionState.stopped);
      expect(h.settings.values[SettingKeys.remoteAccess], isFalse);
      expect(h.keepAwake.last, isFalse);

      final restarted = TestHarness(settings: h.settings.values);
      await restarted.seedSignedIn();
      boot(restarted);
      await controller().bootstrap(watchForWake: false);
      expect(restarted.runtimes, isEmpty);
      expect(state().remoteAccess, isFalse);

      await controller().setRemoteAccess(true);
      expect(restarted.runtime.started, isTrue);
    });
  });

  group('pairing', () {
    test(
      'startPairing exposes the QR data; cancelPairing invalidates it',
      () async {
        boot();
        await h.seedSignedIn();
        await controller().bootstrap(watchForWake: false);

        final view = controller().startPairing()!;
        expect(view.uri.agentDeviceId, h.relay.deviceId);
        expect(state().pairing, same(view));

        controller().cancelPairing();
        expect(h.runtime.pairingCancels, 1);
        expect(state().pairing, isNull);
      },
    );

    test('no pairing while remote access is off', () async {
      boot(TestHarness(settings: {SettingKeys.remoteAccess: false}));
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      expect(controller().startPairing(), isNull);
    });

    test('MobilePaired closes the QR, refreshes trust and notifies', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      controller().startPairing();

      final device = phone('m9', 'Pixel 9');
      await TrustedStore(h.secureStore).add(device);
      h.runtime.eventController.add(MobilePaired(device));
      await pumpEventQueue();

      expect(state().pairing, isNull);
      expect(state().trusted.map((d) => d.mobileId), contains('m9'));
      expect(h.notifier.shown.last.title, 'Paired with Pixel 9');
    });
  });

  group('agent events', () {
    test('a phone opening a session raises a system notification', () async {
      boot(TestHarness(locale: const Locale('vi')));
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.runtime.eventController.add(
        const SessionOpenedByMobile(mobileName: 'iPhone của Phú', sessionId: 3),
      );
      await pumpEventQueue();
      expect(
        h.notifier.shown.last.title,
        'iPhone của Phú vừa mở phiên terminal',
      );
    });

    test('active channel count and session list follow the runtime', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      h.runtime.eventController.add(const ActiveChannelsChanged(2));
      h.runtime.currentSessions = [
        SessionSummary(
          id: 1,
          index: 1,
          shell: 'zsh',
          createdAt: DateTime(2026),
          attachedMobileId: 'm1',
        ),
      ];
      h.runtime.sessionController.add(null);
      await pumpEventQueue();
      expect(state().activeChannels, 2);
      expect(state().sessions.single.shell, 'zsh');
    });

    test('computer woke up: relay reconnects immediately', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      controller().handleWake();
      expect(h.runtime.reconnects, 1);
    });
  });

  group('revoke', () {
    test('with the agent running, AgentService.revoke does the work', () async {
      boot();
      await h.seedSignedIn();
      await TrustedStore(h.secureStore).add(phone('m1', 'iPhone'));
      await controller().bootstrap(watchForWake: false);
      await controller().revoke('m1');
      expect(h.runtime.revoked, ['m1']);
      expect(state().trusted, isEmpty);
    });

    test(
      'with remote access off, trust is removed locally and DELETE is sent',
      () async {
        boot(TestHarness(settings: {SettingKeys.remoteAccess: false}));
        await h.seedSignedIn();
        await TrustedStore(h.secureStore).add(phone('m1', 'iPhone'));
        await controller().bootstrap(watchForWake: false);
        await controller().revoke('m1');
        expect(await TrustedStore(h.secureStore).list(), isEmpty);
        expect(
          h.relay.routes,
          contains('DELETE /v1/pairings/${h.relay.deviceId}/m1'),
        );
      },
    );
  });

  group('switches', () {
    test('keep awake only while signed in with remote access on', () async {
      boot();
      await h.seedSignedIn();
      await controller().bootstrap(watchForWake: false);
      expect(h.keepAwake.last, isTrue);
      await controller().setKeepAwake(false);
      expect(h.keepAwake.last, isFalse);
      expect(h.settings.values[SettingKeys.keepAwake], isFalse);
      await controller().setKeepAwake(true);
      await controller().setRemoteAccess(false);
      expect(h.keepAwake.last, isFalse);
    });

    test(
      'launch at startup: applied, persisted, reverted on OS failure',
      () async {
        boot();
        await controller().bootstrap(watchForWake: false);
        await controller().completeOnboarding();
        expect(h.launchAtLogin.enabled, isTrue);
        expect(h.settings.values[SettingKeys.onboardingDone], isTrue);

        h.launchAtLogin.fail = true;
        await controller().setLaunchAtStartup(false);
        expect(state().launchAtStartup, isTrue);
      },
    );
  });

  group('update check', () {
    test(
      'a newer agent version raises a notification that opens the download',
      () async {
        boot();
        h.relay.version = {
          ...h.relay.version,
          'latest_agent': {
            'version': '1.2.0',
            'mac_url':
                'https://download.shellx.pro/desktop/1.2.0/ShellX-1.2.0.dmg',
            'win_url':
                'https://download.shellx.pro/desktop/1.2.0/ShellX-Setup-1.2.0.exe',
          },
        };
        await controller().checkForUpdate();
        expect(state().update!.version, '1.2.0');
        expect(state().update!.required, isFalse);
        final shown = h.notifier.shown.single;
        expect(shown.title, 'ShellX 1.2.0 is available');
        shown.onClick!();
        expect(h.urlOpener.opened.single.path, endsWith('ShellX-1.2.0.dmg'));
      },
    );

    test('below min_agent: "needs to be updated"', () async {
      boot(TestHarness(appVersion: '0.9.0'));
      await controller().checkForUpdate();
      expect(state().update!.required, isTrue);
      expect(h.notifier.shown.single.title, h.l10n.notifyUpdateRequiredTitle);
    });

    test('a failed check is retried once the relay connects', () async {
      boot();
      await h.seedSignedIn();
      h.relay.offline = true;
      await controller().bootstrap(watchForWake: false);
      await pumpEventQueue();
      expect(state().update, isNull);

      h.relay.offline = false;
      h.relay.version = {
        ...h.relay.version,
        'latest_agent': {
          'version': '2.0.0',
          'mac_url': 'https://download.shellx.pro/a.dmg',
          'win_url': 'https://download.shellx.pro/a.exe',
        },
      };
      h.runtime.emitRelay(RelayConnectionState.connected);
      await pumpEventQueue();
      expect(state().update!.version, '2.0.0');
    });
  });
}
```

- [ ] **Step 3: Chạy test, xác nhận thất bại**

Run: `flutter test test/agent/agent_controller_test.dart`
Expected: FAIL — `Error when reading 'lib/src/agent/agent_controller.dart': No such file or directory`.

- [ ] **Step 4: Cài đặt**

`apps/desktop/lib/src/agent/desktop_services.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../l10n/app_localizations.dart';
import '../platform/keep_awake.dart';
import '../platform/launch_at_login.dart';
import '../platform/notifier.dart';
import '../platform/settings_store.dart';
import '../platform/url_opener.dart';
import 'agent_runtime.dart';

/// Every platform dependency of the controller, swapped for fakes in tests.
final class DesktopServices {
  const DesktopServices({
    required this.secureStore,
    required this.settings,
    required this.api,
    required this.runtimeFactory,
    required this.keepAwake,
    required this.launchAtLogin,
    required this.notifier,
    required this.urlOpener,
    required this.l10n,
    required this.appVersion,
    required this.platform,
    required this.deviceName,
    this.updateInterval = const Duration(hours: 24),
    this.quitApp,
  });

  final KeyValueStore secureStore;
  final SettingsStore settings;
  final ShellxApi api;
  final AgentRuntimeFactory runtimeFactory;
  final KeepAwake keepAwake;
  final LaunchAtLogin launchAtLogin;
  final SystemNotifier notifier;
  final UrlOpener urlOpener;
  final AppLocalizations l10n;
  final String appVersion;
  final DevicePlatform platform;
  final String deviceName;
  final Duration updateInterval;

  /// Destroys the tray icon and the window, then exits the process.
  final Future<void> Function()? quitApp;
}

final desktopServicesProvider = Provider<DesktopServices>(
  (ref) => throw StateError('desktopServicesProvider must be overridden'),
);

/// Wall clock for countdowns; overridden in widget tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
```

`apps/desktop/lib/src/agent/agent_controller.dart` (lưu ý: không `await` `StreamSubscription.cancel()` — nó có thể trả future của root zone, làm treo test FakeAsync và luồng xử lý 4002 đang chạy bên trong chính listener bị hủy):

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import '../platform/settings_store.dart';
import '../platform/wake_detector.dart';
import 'agent_runtime.dart';
import 'agent_state.dart';
import 'desktop_services.dart';
import 'storage_keys.dart';
import 'update_check.dart';

final agentControllerProvider =
    NotifierProvider<AgentController, AgentViewState>(AgentController.new);

/// Owns the signed-in lifecycle: credentials, the [AgentRuntime], settings
/// switches, update checks. The tray and the windows only call its methods.
class AgentController extends Notifier<AgentViewState> {
  late DesktopServices _s;
  late TrustedStore _trusted;
  AgentRuntime? _runtime;
  final List<StreamSubscription<Object?>> _runtimeSubscriptions = [];
  StreamSubscription<void>? _trustedSubscription;
  Timer? _updateTimer;
  WakeDetector? _wakeDetector;
  bool _updateCheckFailed = false;
  bool _revoking = false;

  @override
  AgentViewState build() {
    _s = ref.watch(desktopServicesProvider);
    _trusted = TrustedStore(_s.secureStore);
    ref.onDispose(_dispose);
    return const AgentViewState();
  }

  /// Visible for tests.
  AgentRuntime? get runtime => _runtime;

  /// Loads settings and stored credentials; starts the agent when signed in
  /// and remote access is on; schedules update checks (startup + every 24 h).
  Future<void> bootstrap({bool watchForWake = true}) async {
    final settings = _s.settings;
    state = state.copyWith(
      remoteAccess: settings.getBool(
        SettingKeys.remoteAccess,
        defaultValue: true,
      ),
      keepAwake: settings.getBool(SettingKeys.keepAwake, defaultValue: true),
      launchAtStartup: settings.getBool(
        SettingKeys.launchAtStartup,
        defaultValue: true,
      ),
      onboardingDone: settings.getBool(
        SettingKeys.onboardingDone,
        defaultValue: false,
      ),
    );
    if (state.onboardingDone) {
      try {
        state = state.copyWith(
          launchAtStartup: await _s.launchAtLogin.isEnabled(),
        );
      } on Exception {
        // Keep the stored value if the OS cannot be queried.
      }
    }
    _trustedSubscription = _trusted.changes.listen((_) => _refreshTrusted());
    final token = await _s.secureStore.read(DesktopStorageKeys.token);
    final email = await _s.secureStore.read(DesktopStorageKeys.email);
    if (token == null) {
      state = state.copyWith(phase: AuthPhase.signedOut, email: email);
    } else {
      _s.api.token = token;
      state = state.copyWith(phase: AuthPhase.signedIn, email: email);
      await _refreshTrusted();
      if (state.remoteAccess) await _startRuntime();
    }
    await _applyKeepAwake();
    unawaited(checkForUpdate());
    _updateTimer = Timer.periodic(_s.updateInterval, (_) => checkForUpdate());
    if (watchForWake) {
      _wakeDetector = WakeDetector(onWake: handleWake)..start();
    }
  }

  /// Login or register (spec §5.2). Throws [ApiException] for the UI to show.
  Future<void> signIn({
    required String email,
    required String password,
    required bool register,
  }) async {
    final normalized = email.trim().toLowerCase();
    final identity = await DeviceIdentity.loadOrCreate(_s.secureStore);
    final device = DeviceInfo(
      kind: DeviceKind.agent,
      name: _s.deviceName,
      platform: _s.platform,
      publicKey: identity.publicKey,
    );
    _s.api.token = null;
    final result = register
        ? await _s.api.register(normalized, password, device)
        : await _s.api.login(normalized, password, device);
    final store = _s.secureStore;
    final previousUser = await store.read(DesktopStorageKeys.userId);
    if (previousUser != null && previousUser != result.userId) {
      // Phones trusted under another account can never reach this hub again.
      await _trusted.clear();
    }
    await store.write(DesktopStorageKeys.token, result.token);
    await store.write(DesktopStorageKeys.deviceId, result.deviceId);
    await store.write(DesktopStorageKeys.userId, result.userId);
    await store.write(DesktopStorageKeys.email, normalized);
    _s.api.token = result.token;
    state = state.copyWith(
      phase: AuthPhase.signedIn,
      email: normalized,
      signedOutNotice: false,
    );
    await _refreshTrusted();
    if (state.remoteAccess) await _startRuntime();
    await _applyKeepAwake();
  }

  /// Spec §5.2 "Đăng xuất trên agent": close sessions, delete the token and the
  /// server-side pairings (POST /v1/auth/logout), clear the local trusted list.
  Future<void> signOut() async {
    await _stopRuntime();
    try {
      await _s.api.logout().timeout(const Duration(seconds: 10));
    } on Exception {
      // Best effort: the token is deleted locally either way.
    }
    await _clearSignedInData();
    state = state.copyWith(
      phase: AuthPhase.signedOut,
      trusted: const <TrustedDevice>[],
      signedOutNotice: false,
    );
    await _applyKeepAwake();
  }

  /// Throws [ApiException] (`weak_password`, `agent_only`, network, 429).
  Future<void> changePassword(String newPassword) async {
    try {
      await _s.api.changePassword(newPassword);
    } on ApiException catch (error) {
      if (error.status == 401) await _handleRevoked();
      rethrow;
    }
  }

  Future<void> setRemoteAccess(bool enabled) async {
    await _s.settings.setBool(SettingKeys.remoteAccess, enabled);
    state = state.copyWith(remoteAccess: enabled);
    if (state.signedIn) {
      if (enabled) {
        await _startRuntime();
      } else {
        await _stopRuntime();
      }
    }
    await _applyKeepAwake();
  }

  Future<void> setKeepAwake(bool enabled) async {
    await _s.settings.setBool(SettingKeys.keepAwake, enabled);
    state = state.copyWith(keepAwake: enabled);
    await _applyKeepAwake();
  }

  Future<void> setLaunchAtStartup(bool enabled) async {
    try {
      await _s.launchAtLogin.setEnabled(enabled);
    } on Exception {
      state = state.copyWith(launchAtStartup: !enabled);
      return;
    }
    await _s.settings.setBool(SettingKeys.launchAtStartup, enabled);
    state = state.copyWith(launchAtStartup: enabled);
  }

  Future<void> completeOnboarding() async {
    await setLaunchAtStartup(state.launchAtStartup);
    await _s.settings.setBool(SettingKeys.onboardingDone, true);
    state = state.copyWith(onboardingDone: true);
  }

  /// Null when there is no runtime (signed out or remote access off).
  PairingView? startPairing() {
    final runtime = _runtime;
    if (runtime == null) return null;
    final view = runtime.startPairing();
    state = state.copyWith(pairing: view);
    return view;
  }

  /// Closing the QR window invalidates the code (spec §5.3).
  void cancelPairing() {
    _runtime?.cancelPairing();
    state = state.copyWith(pairing: null);
  }

  /// Spec §5.5: local trust is removed first and takes effect immediately; the
  /// DELETE /v1/pairings call is best effort (the record is display-only).
  Future<void> revoke(String mobileId) async {
    final runtime = _runtime;
    try {
      if (runtime != null) {
        await runtime.revoke(mobileId);
      } else {
        await _trusted.remove(mobileId);
        final agentId = await _s.secureStore.read(DesktopStorageKeys.deviceId);
        if (agentId != null) await _s.api.deletePairing(agentId, mobileId);
      }
    } on ApiException {
      // Trust is already gone locally; the server record is cosmetic.
    }
    await _refreshTrusted();
  }

  void closeSession(int id) => _runtime?.closeSession(id);

  void closeAllSessions() => _runtime?.closeAllSessions();

  /// Called by [WakeDetector] after the computer slept.
  void handleWake() => _runtime?.reconnectNow();

  Future<void> checkForUpdate() async {
    final VersionInfo info;
    try {
      info = await _s.api.version();
    } on Exception {
      _updateCheckFailed = true;
      return;
    }
    _updateCheckFailed = false;
    if (!ref.mounted) return;
    final notice = evaluateUpdate(
      info,
      appVersion: _s.appVersion,
      platform: _s.platform,
    );
    state = state.copyWith(update: notice);
    if (notice == null) return;
    final l10n = _s.l10n;
    await _s.notifier.show(
      title: notice.required
          ? l10n.notifyUpdateRequiredTitle
          : l10n.notifyUpdateAvailableTitle(notice.version),
      body: notice.required
          ? l10n.notifyUpdateRequiredBody(notice.version)
          : l10n.notifyUpdateAvailableBody,
      onClick: () => _s.urlOpener.open(notice.url),
    );
  }

  /// Before quitting: close sessions, disconnect, release the sleep assertion.
  Future<void> shutdown() async {
    _updateTimer?.cancel();
    _wakeDetector?.stop();
    await _stopRuntime();
    await _s.keepAwake.setEnabled(false);
  }

  Future<void> _startRuntime() async {
    if (_runtime != null) return;
    final store = _s.secureStore;
    final token = await store.read(DesktopStorageKeys.token);
    final deviceId = await store.read(DesktopStorageKeys.deviceId);
    final userId = await store.read(DesktopStorageKeys.userId);
    final email = await store.read(DesktopStorageKeys.email);
    if (token == null || deviceId == null || userId == null) {
      await _handleRevoked();
      return;
    }
    final identity = await DeviceIdentity.loadOrCreate(store);
    final runtime = _s.runtimeFactory(
      RuntimeParams(
        credentials: AgentCredentials(
          token: token,
          deviceId: deviceId,
          userId: userId,
          email: email ?? '',
        ),
        identity: identity,
        trusted: _trusted,
        api: _s.api,
      ),
    );
    _runtime = runtime;
    _runtimeSubscriptions.addAll([
      runtime.relayStates.listen(_onRelayState),
      runtime.events.listen(_onAgentEvent),
      runtime.sessionChanges.listen((_) => _refreshSessions()),
    ]);
    state = state.copyWith(
      relay: runtime.relayState,
      sessions: runtime.sessions,
      activeChannels: 0,
    );
    await runtime.start();
  }

  Future<void> _stopRuntime() async {
    final runtime = _runtime;
    if (runtime == null) return;
    _runtime = null;
    // Not awaited: cancel() may return a root-zone future, and we may be
    // running inside the relay listener that is being cancelled.
    for (final subscription in _runtimeSubscriptions) {
      unawaited(subscription.cancel());
    }
    _runtimeSubscriptions.clear();
    await runtime.stop();
    if (!ref.mounted) return;
    state = state.copyWith(
      relay: RelayConnectionState.stopped,
      sessions: const <SessionSummary>[],
      activeChannels: 0,
      pairing: null,
    );
  }

  /// Relay said 4002, or refused the upgrade with 401 (spec §5.2 as amended,
  /// §12). The agent cannot tell a password change from an account deletion,
  /// so it always: closes every session, deletes the token, KEEPS the device
  /// key, user id and trusted list, and returns to the login window. [signIn]
  /// clears the trusted list only if the next account is a different user.
  Future<void> _handleRevoked() async {
    if (_revoking || state.phase != AuthPhase.signedIn) return;
    _revoking = true;
    try {
      await _stopRuntime();
      await _s.secureStore.delete(DesktopStorageKeys.token);
      _s.api.token = null;
      if (!ref.mounted) return;
      state = state.copyWith(phase: AuthPhase.signedOut, signedOutNotice: true);
      await _applyKeepAwake();
      await _s.notifier.show(
        title: _s.l10n.notifySignedOutTitle,
        body: _s.l10n.notifySignedOutBody,
      );
    } finally {
      _revoking = false;
    }
  }

  /// Deletes token, device id, user id and the trusted list. Keeps the
  /// device key (spec §5.1) and the email (pre-fills the login form).
  Future<void> _clearSignedInData() async {
    await _trusted.clear();
    final store = _s.secureStore;
    await store.delete(DesktopStorageKeys.token);
    await store.delete(DesktopStorageKeys.deviceId);
    await store.delete(DesktopStorageKeys.userId);
    _s.api.token = null;
  }

  void _onRelayState(RelayConnectionState relay) {
    if (!ref.mounted) return;
    state = state.copyWith(relay: relay);
    if (relay == RelayConnectionState.revoked) {
      unawaited(_handleRevoked());
    } else if (relay == RelayConnectionState.connected && _updateCheckFailed) {
      unawaited(checkForUpdate());
    }
  }

  void _onAgentEvent(AgentEvent event) {
    if (!ref.mounted) return;
    final l10n = _s.l10n;
    switch (event) {
      case MobilePaired(:final device):
        state = state.copyWith(pairing: null);
        unawaited(_refreshTrusted());
        unawaited(_s.notifier.show(title: l10n.notifyPaired(device.name)));
      case SessionOpenedByMobile(:final mobileName):
        unawaited(
          _s.notifier.show(title: l10n.notifySessionOpened(mobileName)),
        );
      case ActiveChannelsChanged(:final count):
        state = state.copyWith(activeChannels: count);
      case AgentRevoked():
        unawaited(_handleRevoked());
    }
  }

  void _refreshSessions() {
    final runtime = _runtime;
    if (runtime == null || !ref.mounted) return;
    state = state.copyWith(sessions: runtime.sessions);
  }

  Future<void> _refreshTrusted() async {
    final devices = await _trusted.list();
    if (!ref.mounted) return;
    state = state.copyWith(trusted: devices);
  }

  Future<void> _applyKeepAwake() => _s.keepAwake.setEnabled(
    state.keepAwake && state.signedIn && state.remoteAccess,
  );

  void _dispose() {
    _updateTimer?.cancel();
    _wakeDetector?.stop();
    unawaited(_trustedSubscription?.cancel());
    for (final subscription in _runtimeSubscriptions) {
      unawaited(subscription.cancel());
    }
    final runtime = _runtime;
    _runtime = null;
    if (runtime != null) unawaited(runtime.stop());
  }
}
```

- [ ] **Step 5: Chạy test, xác nhận qua**

Run: `flutter test test/agent/agent_controller_test.dart`
Expected: `All tests passed!` (30 test).

- [ ] **Step 6: Commit**

```bash
git add lib/src/agent test/support test/agent/agent_controller_test.dart
git commit -m "feat(desktop): add agent controller for sign-in, revoke, pairing and settings"
```

---

### Task 8: Menu tray, icon 3 trạng thái, presenter

**Files:**
- Create: `apps/desktop/lib/src/tray/tray_action.dart`, `tray_menu.dart`, `tray_presenter.dart`
- Create: `apps/desktop/tool/gen_tray_icons.dart`; generate + commit `apps/desktop/assets/tray/tray_{normal,offline,active}.{png,ico}`
- Modify: `apps/desktop/pubspec.yaml` (mục `flutter:`)
- Test: `apps/desktop/test/tray/tray_menu_test.dart`, `tray_presenter_test.dart`, `tray_assets_test.dart`

**Interfaces:**
- Consumes: Task 6 `AgentViewState`, `AuthPhase`, `UpdateNotice`; Task 2 `AppLocalizations`; `tray_manager` (`Menu`, `MenuItem`, `MenuItem.separator/checkbox/submenu`, `trayManager`, `TrayListener`); Task 7 test support `phone()`.
- Produces:
  - `sealed class TrayAction` với `ToggleRemoteAccess`, `CloseSession(int id)`, `CloseAllSessions`, `PairPhone`, `RevokeDevice(String mobileId)`, `ToggleKeepAwake`, `ToggleLaunchAtStartup`, `OpenChangePassword`, `SignOut`, `SignIn`, `DownloadUpdate`, `Quit`; `abstract final class TrayKeys` (key tĩnh + `session(id)`, `closeSession(id)`, `device(mobileId)`, `revoke(mobileId)`); `TrayAction? trayActionForKey(String? key)`.
  - `enum TrayIconState { normal, offline, active }`; `TrayIconState trayIconFor(AgentViewState)`; `String trayIconAsset(TrayIconState, {required bool windows})`; `final class TrayMenuIds`; `Menu buildTrayMenu(AgentViewState, AppLocalizations, TrayMenuIds)`.
  - `abstract interface class TrayHost { Future<void> setIcon(String asset, {required bool isTemplate}); Future<void> setToolTip(String text); Future<void> setMenu(Menu menu); }`; `final class TrayPresenter { TrayPresenter({required TrayHost host, required AppLocalizations l10n, required bool isWindows, required Future<void> Function(TrayAction) onAction}); Future<void> render(AgentViewState); void onMenuItemClick(MenuItem); }`; `final class TrayManagerHost with TrayListener implements TrayHost { TrayManagerHost({required void Function(MenuItem) onClick}); Future<void> destroy(); }`.

- [ ] **Step 1: Viết test thất bại**

`apps/desktop/test/tray/tray_menu_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/update_check.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';
import 'package:tray_manager/tray_manager.dart';

import '../support/fakes.dart';

final vi = lookupAppLocalizations(const Locale('vi'));

AgentViewState _signedIn({
  RelayConnectionState relay = RelayConnectionState.connected,
  int channels = 0,
  bool remoteAccess = true,
  List<SessionSummary> sessions = const [],
  List<TrustedDevice> trusted = const [],
  UpdateNotice? update,
}) => AgentViewState(
  phase: AuthPhase.signedIn,
  email: 'user@email.com',
  relay: relay,
  activeChannels: channels,
  remoteAccess: remoteAccess,
  sessions: sessions,
  trusted: trusted,
  update: update,
);

List<String?> _labels(Menu menu) => [
  for (final item in menu.items!) item.type == 'separator' ? '---' : item.label,
];

void main() {
  test('signed-in menu is exactly spec §8.3, in order', () {
    final state = _signedIn(
      sessions: [
        SessionSummary(
          id: 7,
          index: 1,
          shell: 'zsh',
          createdAt: DateTime(2026),
          attachedMobileId: 'm1',
        ),
      ],
      trusted: [phone('m1', 'iPhone của Phú')],
    );
    final menu = buildTrayMenu(state, vi, TrayMenuIds());
    expect(_labels(menu), [
      '● Đã kết nối — user@email.com',
      '---',
      'Cho phép truy cập từ xa',
      'Phiên đang hoạt động (1)',
      'Ghép nối điện thoại…',
      'Thiết bị đã ghép',
      '---',
      'Giữ máy không ngủ',
      'Khởi động cùng hệ thống',
      'Đổi mật khẩu…',
      'Đăng xuất',
      'Thoát',
    ]);
    expect(menu.getMenuItem(TrayKeys.status)!.disabled, isTrue);
    expect(menu.getMenuItem(TrayKeys.remoteAccess)!.checked, isTrue);
    expect(menu.getMenuItem(TrayKeys.keepAwake)!.type, 'checkbox');

    final session = menu.getMenuItem(TrayKeys.session(7))!;
    expect(session.label, 'zsh 1 — iPhone của Phú');
    expect(session.submenu!.items!.single.key, TrayKeys.closeSession(7));
    expect(session.submenu!.items!.single.label, 'Đóng');
    expect(menu.getMenuItem(TrayKeys.closeAll)!.label, 'Đóng tất cả');

    final device = menu.getMenuItem(TrayKeys.device('m1'))!;
    expect(device.submenu!.items!.single.key, TrayKeys.revoke('m1'));
    expect(device.submenu!.items!.single.label, 'Thu hồi');
  });

  test('empty lists: sessions disabled, devices show a placeholder', () {
    final menu = buildTrayMenu(_signedIn(), vi, TrayMenuIds());
    expect(menu.getMenuItem(TrayKeys.sessions)!.disabled, isTrue);
    expect(menu.getMenuItem(TrayKeys.noDevices)!.disabled, isTrue);
  });

  test('status line follows the relay and the remote-access switch', () {
    String status(AgentViewState s) => buildTrayMenu(
      s,
      vi,
      TrayMenuIds(),
    ).getMenuItem(TrayKeys.status)!.label!;
    expect(
      status(_signedIn(relay: RelayConnectionState.disconnected)),
      '○ Mất kết nối — đang thử lại…',
    );
    expect(
      status(_signedIn(relay: RelayConnectionState.replaced)),
      '○ Một bản ShellX khác đã kết nối thay máy này',
    );
    expect(
      status(
        _signedIn(remoteAccess: false, relay: RelayConnectionState.stopped),
      ),
      '○ Đã tắt truy cập từ xa',
    );
    final off = buildTrayMenu(
      _signedIn(remoteAccess: false, relay: RelayConnectionState.stopped),
      vi,
      TrayMenuIds(),
    );
    expect(off.getMenuItem(TrayKeys.pair)!.disabled, isTrue);
  });

  test('update available adds a download item under the status line', () {
    final menu = buildTrayMenu(
      _signedIn(
        update: UpdateNotice(
          version: '1.1.0',
          url: Uri.parse('https://download.shellx.pro/x.dmg'),
          required: false,
        ),
      ),
      vi,
      TrayMenuIds(),
    );
    expect(menu.items![1].key, TrayKeys.downloadUpdate);
    expect(menu.items![1].label, 'Tải ShellX 1.1.0…');
  });

  test('signed-out menu offers sign in and quit only', () {
    final menu = buildTrayMenu(
      const AgentViewState(phase: AuthPhase.signedOut),
      vi,
      TrayMenuIds(),
    );
    expect(_labels(menu), ['○ Chưa đăng nhập', '---', 'Đăng nhập…', 'Thoát']);
  });

  test('menu item ids are stable across rebuilds', () {
    final ids = TrayMenuIds();
    final first = buildTrayMenu(_signedIn(), vi, ids);
    final second = buildTrayMenu(
      _signedIn(relay: RelayConnectionState.disconnected),
      vi,
      ids,
    );
    expect(
      second.getMenuItem(TrayKeys.quit)!.id,
      first.getMenuItem(TrayKeys.quit)!.id,
    );
    expect(
      second.getMenuItem(TrayKeys.pair)!.id,
      first.getMenuItem(TrayKeys.pair)!.id,
    );
  });

  test(
    'icon: grey unless connected, highlighted while a phone is connected',
    () {
      expect(
        trayIconFor(const AgentViewState(phase: AuthPhase.signedOut)),
        TrayIconState.offline,
      );
      expect(
        trayIconFor(_signedIn(relay: RelayConnectionState.disconnected)),
        TrayIconState.offline,
      );
      expect(
        trayIconFor(_signedIn(remoteAccess: false)),
        TrayIconState.offline,
      );
      expect(trayIconFor(_signedIn()), TrayIconState.normal);
      expect(trayIconFor(_signedIn(channels: 1)), TrayIconState.active);
      expect(
        trayIconAsset(TrayIconState.active, windows: true),
        'assets/tray/tray_active.ico',
      );
      expect(
        trayIconAsset(TrayIconState.offline, windows: false),
        'assets/tray/tray_offline.png',
      );
    },
  );

  test('menu keys map back to actions', () {
    expect(
      trayActionForKey(TrayKeys.closeSession(12)),
      isA<CloseSession>().having((a) => a.id, 'id', 12),
    );
    expect(
      trayActionForKey(TrayKeys.revoke('m-1')),
      isA<RevokeDevice>().having((a) => a.mobileId, 'mobileId', 'm-1'),
    );
    expect(trayActionForKey(TrayKeys.remoteAccess), isA<ToggleRemoteAccess>());
    expect(trayActionForKey(TrayKeys.quit), isA<Quit>());
    expect(trayActionForKey(TrayKeys.status), isNull);
    expect(trayActionForKey('session_close:abc'), isNull);
    expect(trayActionForKey(null), isNull);
  });
}
```

`apps/desktop/test/tray/tray_presenter_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_presenter.dart';
import 'package:tray_manager/tray_manager.dart';

final class _FakeTrayHost implements TrayHost {
  final List<(String, bool)> icons = [];
  final List<Menu> menus = [];
  @override
  Future<void> setIcon(String asset, {required bool isTemplate}) async =>
      icons.add((asset, isTemplate));
  @override
  Future<void> setToolTip(String text) async {}
  @override
  Future<void> setMenu(Menu menu) async => menus.add(menu);
}

void main() {
  const connected = AgentViewState(
    phase: AuthPhase.signedIn,
    email: 'a@b.co',
    relay: RelayConnectionState.connected,
  );

  test(
    'icon changes only when its state changes; macOS template except active',
    () async {
      final host = _FakeTrayHost();
      final presenter = TrayPresenter(
        host: host,
        l10n: lookupAppLocalizations(const Locale('en')),
        isWindows: false,
        onAction: (_) async {},
      );
      await presenter.render(connected);
      await presenter.render(connected.copyWith(email: 'c@d.co'));
      await presenter.render(connected.copyWith(activeChannels: 1));
      expect(host.icons, [
        ('assets/tray/tray_normal.png', true),
        ('assets/tray/tray_active.png', false),
      ]);
      expect(host.menus, hasLength(3));
    },
  );

  test('clicks are translated to actions; unknown keys are ignored', () async {
    final actions = <TrayAction>[];
    final presenter = TrayPresenter(
      host: _FakeTrayHost(),
      l10n: lookupAppLocalizations(const Locale('en')),
      isWindows: true,
      onAction: (a) async => actions.add(a),
    );
    presenter.onMenuItemClick(MenuItem(key: TrayKeys.pair));
    presenter.onMenuItemClick(MenuItem(key: TrayKeys.status));
    await Future<void>.delayed(Duration.zero);
    expect(actions.single, isA<PairPhone>());
  });
}
```

`apps/desktop/test/tray/tray_assets_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';

void main() {
  for (final icon in TrayIconState.values) {
    test(
      '${icon.name}: 36x36 PNG for macOS and a 16+32 px ICO for Windows',
      () {
        final png = File(trayIconAsset(icon, windows: false)).readAsBytesSync();
        expect(png.sublist(0, 8), [
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ]);
        final ihdr = ByteData.sublistView(png, 16, 24);
        expect(ihdr.getUint32(0), 36);
        expect(ihdr.getUint32(4), 36);

        final ico = ByteData.sublistView(
          File(trayIconAsset(icon, windows: true)).readAsBytesSync(),
        );
        expect(ico.getUint16(2, Endian.little), 1, reason: 'ICO type');
        expect(ico.getUint16(4, Endian.little), 2, reason: 'image count');
        expect(ico.getUint8(6), 16);
        expect(ico.getUint8(22), 32);
      },
    );
  }

  test('pubspec bundles the tray assets', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/tray/'));
  });
}
```

- [ ] **Step 2: Chạy test, xác nhận thất bại**

Run: `flutter test test/tray`
Expected: FAIL — `Error when reading 'lib/src/tray/tray_action.dart': No such file or directory`.

- [ ] **Step 3: Cài đặt menu và presenter**

`apps/desktop/lib/src/tray/tray_action.dart`:

```dart
/// Everything the tray menu can ask for.
sealed class TrayAction {
  const TrayAction();
}

final class ToggleRemoteAccess extends TrayAction {
  const ToggleRemoteAccess();
}

final class CloseSession extends TrayAction {
  const CloseSession(this.id);
  final int id;
}

final class CloseAllSessions extends TrayAction {
  const CloseAllSessions();
}

final class PairPhone extends TrayAction {
  const PairPhone();
}

final class RevokeDevice extends TrayAction {
  const RevokeDevice(this.mobileId);
  final String mobileId;
}

final class ToggleKeepAwake extends TrayAction {
  const ToggleKeepAwake();
}

final class ToggleLaunchAtStartup extends TrayAction {
  const ToggleLaunchAtStartup();
}

final class OpenChangePassword extends TrayAction {
  const OpenChangePassword();
}

final class SignOut extends TrayAction {
  const SignOut();
}

final class SignIn extends TrayAction {
  const SignIn();
}

final class DownloadUpdate extends TrayAction {
  const DownloadUpdate();
}

final class Quit extends TrayAction {
  const Quit();
}

/// Menu item keys. Dynamic keys embed the session id / mobile device id.
abstract final class TrayKeys {
  static const String status = 'status';
  static const String downloadUpdate = 'download_update';
  static const String remoteAccess = 'remote_access';
  static const String sessions = 'sessions';
  static const String closeAll = 'sessions_close_all';
  static const String pair = 'pair';
  static const String devices = 'devices';
  static const String noDevices = 'devices_none';
  static const String keepAwake = 'keep_awake';
  static const String launchAtStartup = 'launch_at_startup';
  static const String changePassword = 'change_password';
  static const String signOut = 'sign_out';
  static const String signIn = 'sign_in';
  static const String quit = 'quit';

  static String session(int id) => 'session:$id';
  static String closeSession(int id) => 'session_close:$id';
  static String device(String mobileId) => 'device:$mobileId';
  static String revoke(String mobileId) => 'revoke:$mobileId';
}

TrayAction? trayActionForKey(String? key) {
  if (key == null) return null;
  const closePrefix = 'session_close:';
  const revokePrefix = 'revoke:';
  if (key.startsWith(closePrefix)) {
    final id = int.tryParse(key.substring(closePrefix.length));
    return id == null ? null : CloseSession(id);
  }
  if (key.startsWith(revokePrefix)) {
    final mobileId = key.substring(revokePrefix.length);
    return mobileId.isEmpty ? null : RevokeDevice(mobileId);
  }
  return switch (key) {
    TrayKeys.remoteAccess => const ToggleRemoteAccess(),
    TrayKeys.closeAll => const CloseAllSessions(),
    TrayKeys.pair => const PairPhone(),
    TrayKeys.keepAwake => const ToggleKeepAwake(),
    TrayKeys.launchAtStartup => const ToggleLaunchAtStartup(),
    TrayKeys.changePassword => const OpenChangePassword(),
    TrayKeys.signOut => const SignOut(),
    TrayKeys.signIn => const SignIn(),
    TrayKeys.downloadUpdate => const DownloadUpdate(),
    TrayKeys.quit => const Quit(),
    _ => null,
  };
}
```

`apps/desktop/lib/src/tray/tray_menu.dart`:

```dart
import 'package:shellx_core/shellx_core.dart';
import 'package:tray_manager/tray_manager.dart';

import '../../l10n/app_localizations.dart';
import '../agent/agent_state.dart';
import 'tray_action.dart';

enum TrayIconState { normal, offline, active }

/// Spec §8.3: grey when not connected, highlighted while a phone has an open
/// encrypted channel, normal otherwise.
TrayIconState trayIconFor(AgentViewState state) {
  if (!state.signedIn ||
      !state.remoteAccess ||
      state.relay != RelayConnectionState.connected) {
    return TrayIconState.offline;
  }
  return state.activeChannels > 0 ? TrayIconState.active : TrayIconState.normal;
}

/// macOS uses PNG (template images for normal/offline), Windows needs ICO.
String trayIconAsset(TrayIconState icon, {required bool windows}) =>
    'assets/tray/tray_${icon.name}.${windows ? 'ico' : 'png'}';

/// Stable menu item ids per key. menu_base hands out a fresh id for every
/// MenuItem, so a click on a menu that was rebuilt while open would not be
/// found; reusing ids per key keeps such clicks working.
final class TrayMenuIds {
  final Map<String, int> _ids = {};
  int _next = 1024;
  int _separators = 0;

  int idFor(String key) => _ids.putIfAbsent(key, () => _next++);

  MenuItem assign(MenuItem item) {
    item.id = idFor(item.key ?? 'separator:${_separators++}');
    return item;
  }

  void startBuild() => _separators = 0;
}

String _statusLine(AgentViewState state, AppLocalizations l10n) {
  final email = state.email ?? '';
  if (!state.remoteAccess) return '○ ${l10n.trayStatusRemoteOff}';
  return switch (state.relay) {
    RelayConnectionState.connected => '● ${l10n.trayStatusConnected(email)}',
    RelayConnectionState.connecting => '○ ${l10n.trayStatusConnecting(email)}',
    RelayConnectionState.replaced => '○ ${l10n.trayStatusReplaced}',
    _ => '○ ${l10n.trayStatusReconnecting}',
  };
}

/// Builds the tray menu of spec §8.3 (signed in) or a minimal one (signed out).
Menu buildTrayMenu(
  AgentViewState state,
  AppLocalizations l10n,
  TrayMenuIds ids,
) {
  ids.startBuild();
  MenuItem sep() => ids.assign(MenuItem.separator());
  MenuItem item(String key, String label, {bool disabled = false}) =>
      ids.assign(MenuItem(key: key, label: label, disabled: disabled));
  MenuItem check(
    String key,
    String label,
    bool checked, {
    bool disabled = false,
  }) => ids.assign(
    MenuItem.checkbox(
      key: key,
      label: label,
      checked: checked,
      disabled: disabled,
    ),
  );
  MenuItem sub(
    String key,
    String label,
    List<MenuItem> children, {
    bool disabled = false,
  }) => ids.assign(
    MenuItem.submenu(
      key: key,
      label: label,
      disabled: disabled,
      submenu: Menu(items: children),
    ),
  );

  if (!state.signedIn) {
    return Menu(
      items: [
        item(TrayKeys.status, '○ ${l10n.trayStatusSignedOut}', disabled: true),
        sep(),
        item(TrayKeys.signIn, l10n.traySignIn),
        item(TrayKeys.quit, l10n.trayQuit),
      ],
    );
  }

  final names = {for (final d in state.trusted) d.mobileId: d.name};
  final sessionItems = [
    for (final s in state.sessions)
      sub(
        TrayKeys.session(s.id),
        s.attachedMobileId == null
            ? l10n.traySessionItem(s.shell, s.index)
            : l10n.traySessionItemAttached(
                s.shell,
                s.index,
                names[s.attachedMobileId] ?? s.attachedMobileId!,
              ),
        [item(TrayKeys.closeSession(s.id), l10n.traySessionClose)],
      ),
    if (state.sessions.isNotEmpty) sep(),
    if (state.sessions.isNotEmpty) item(TrayKeys.closeAll, l10n.trayCloseAll),
  ];
  final deviceItems = state.trusted.isEmpty
      ? [item(TrayKeys.noDevices, l10n.trayNoDevices, disabled: true)]
      : [
          for (final d in state.trusted)
            sub(TrayKeys.device(d.mobileId), d.name, [
              item(TrayKeys.revoke(d.mobileId), l10n.trayRevoke),
            ]),
        ];
  final update = state.update;

  return Menu(
    items: [
      item(TrayKeys.status, _statusLine(state, l10n), disabled: true),
      if (update != null)
        item(TrayKeys.downloadUpdate, l10n.trayDownloadUpdate(update.version)),
      sep(),
      check(TrayKeys.remoteAccess, l10n.trayRemoteAccess, state.remoteAccess),
      sub(
        TrayKeys.sessions,
        l10n.traySessions(state.sessions.length),
        sessionItems,
        disabled: state.sessions.isEmpty,
      ),
      item(TrayKeys.pair, l10n.trayPairPhone, disabled: !state.remoteAccess),
      sub(TrayKeys.devices, l10n.trayPairedDevices, deviceItems),
      sep(),
      check(TrayKeys.keepAwake, l10n.trayKeepAwake, state.keepAwake),
      check(
        TrayKeys.launchAtStartup,
        l10n.trayLaunchAtStartup,
        state.launchAtStartup,
      ),
      item(TrayKeys.changePassword, l10n.trayChangePassword),
      item(TrayKeys.signOut, l10n.traySignOut),
      item(TrayKeys.quit, l10n.trayQuit),
    ],
  );
}
```

`apps/desktop/lib/src/tray/tray_presenter.dart`:

```dart
import 'dart:async';

import 'package:tray_manager/tray_manager.dart';

import '../../l10n/app_localizations.dart';
import '../agent/agent_state.dart';
import 'tray_action.dart';
import 'tray_menu.dart';

abstract interface class TrayHost {
  Future<void> setIcon(String asset, {required bool isTemplate});
  Future<void> setToolTip(String text);
  Future<void> setMenu(Menu menu);
}

/// Mirrors [AgentViewState] into the tray icon and menu; routes clicks.
final class TrayPresenter {
  TrayPresenter({
    required TrayHost host,
    required AppLocalizations l10n,
    required bool isWindows,
    required Future<void> Function(TrayAction action) onAction,
  }) : _host = host,
       _l10n = l10n,
       _isWindows = isWindows,
       _onAction = onAction;

  final TrayHost _host;
  final AppLocalizations _l10n;
  final bool _isWindows;
  final Future<void> Function(TrayAction action) _onAction;
  final TrayMenuIds _ids = TrayMenuIds();
  TrayIconState? _icon;
  AgentViewState? _pending;
  bool _busy = false;

  /// Coalesces bursts of state changes into the latest one.
  Future<void> render(AgentViewState state) async {
    _pending = state;
    if (_busy) return;
    _busy = true;
    try {
      while (_pending != null) {
        final next = _pending!;
        _pending = null;
        await _render(next);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _render(AgentViewState state) async {
    final icon = trayIconFor(state);
    if (icon != _icon) {
      _icon = icon;
      await _host.setIcon(
        trayIconAsset(icon, windows: _isWindows),
        isTemplate: !_isWindows && icon != TrayIconState.active,
      );
      await _host.setToolTip(_l10n.trayTooltip);
    }
    await _host.setMenu(buildTrayMenu(state, _l10n, _ids));
  }

  void onMenuItemClick(MenuItem item) {
    final action = trayActionForKey(item.key);
    if (action != null) unawaited(_onAction(action));
  }
}

/// [TrayHost] over package tray_manager. Left and right click open the menu.
final class TrayManagerHost with TrayListener implements TrayHost {
  TrayManagerHost({required void Function(MenuItem item) onClick})
    : _onClick = onClick {
    trayManager.addListener(this);
  }

  final void Function(MenuItem item) _onClick;

  @override
  Future<void> setIcon(String asset, {required bool isTemplate}) =>
      trayManager.setIcon(asset, isTemplate: isTemplate);

  @override
  Future<void> setToolTip(String text) => trayManager.setToolTip(text);

  @override
  Future<void> setMenu(Menu menu) => trayManager.setContextMenu(menu);

  @override
  void onTrayIconMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) => _onClick(menuItem);

  Future<void> destroy() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
  }
}
```

- [ ] **Step 4: Sinh icon và khai báo asset**

`apps/desktop/tool/gen_tray_icons.dart`:

```dart
// Generates the tray icons in assets/tray/ (no dependencies beyond dart:io).
// Run from apps/desktop:  dart run tool/gen_tray_icons.dart
//
// Glyph: a rounded square with a ">_" prompt.
// macOS PNG 36x36 (18 pt @2x): normal/offline are template images (black,
// offline at 35 % alpha → rendered grey by the menu bar); active is green.
// Windows ICO (16x16 + 32x32, 32-bit DIB): blue / grey / green.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

typedef Rgba = (int r, int g, int b, int a);

double _segmentDistance(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax, dy = by - ay;
  final t = (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)).clamp(
    0.0,
    1.0,
  );
  final cx = ax + t * dx, cy = ay + t * dy;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}

double _roundedRectDistance(double px, double py) {
  // Signed distance to a rounded square centred at 0.5, half-size 0.42, radius 0.18.
  const half = 0.42, radius = 0.18;
  final qx = (px - 0.5).abs() - (half - radius);
  final qy = (py - 0.5).abs() - (half - radius);
  final outside = math.sqrt(
    math.pow(math.max(qx, 0), 2) + math.pow(math.max(qy, 0), 2),
  );
  return outside + math.min(math.max(qx, qy), 0.0) - radius;
}

bool _inside(double x, double y) {
  const stroke = 0.09;
  if (_roundedRectDistance(x, y).abs() < stroke / 2) return true;
  if (_segmentDistance(x, y, 0.28, 0.34, 0.46, 0.5) < stroke / 2) return true;
  if (_segmentDistance(x, y, 0.46, 0.5, 0.28, 0.66) < stroke / 2) return true;
  return _segmentDistance(x, y, 0.54, 0.67, 0.74, 0.67) < stroke / 2;
}

/// RGBA pixels, row-major, top row first; 4x4 supersampling for anti-aliasing.
Uint8List render(int size, Rgba color) {
  final pixels = Uint8List(size * size * 4);
  const samples = 4;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var hits = 0;
      for (var sy = 0; sy < samples; sy++) {
        for (var sx = 0; sx < samples; sx++) {
          if (_inside(
            (x + (sx + 0.5) / samples) / size,
            (y + (sy + 0.5) / samples) / size,
          )) {
            hits++;
          }
        }
      }
      final i = (y * size + x) * 4;
      pixels[i] = color.$1;
      pixels[i + 1] = color.$2;
      pixels[i + 2] = color.$3;
      pixels[i + 3] = (color.$4 * hits / (samples * samples)).round();
    }
  }
  return pixels;
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

List<int> _chunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  final out = BytesBuilder()
    ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
    ..add(body)
    ..add((ByteData(4)..setUint32(0, _crc32(body))).buffer.asUint8List());
  return out.takeBytes();
}

Uint8List encodePng(int size, Uint8List rgba) {
  final header = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6) // colour type RGBA
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  final raw = BytesBuilder();
  for (var y = 0; y < size; y++) {
    raw.addByte(0); // filter: none
    raw.add(rgba.sublist(y * size * 4, (y + 1) * size * 4));
  }
  return (BytesBuilder()
        ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..add(_chunk('IHDR', header.buffer.asUint8List()))
        ..add(_chunk('IDAT', ZLibEncoder().convert(raw.takeBytes())))
        ..add(_chunk('IEND', const [])))
      .takeBytes();
}

/// One 32-bit BGRA DIB icon image (BITMAPINFOHEADER + XOR bitmap + AND mask).
Uint8List _dib(int size, Uint8List rgba) {
  final maskRowBytes = ((size + 31) ~/ 32) * 4;
  final info = ByteData(40)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, size, Endian.little)
    ..setInt32(8, size * 2, Endian.little) // XOR + AND
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 32, Endian.little)
    ..setUint32(20, size * size * 4 + maskRowBytes * size, Endian.little);
  final out = BytesBuilder()..add(info.buffer.asUint8List());
  for (var y = size - 1; y >= 0; y--) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      out.add([rgba[i + 2], rgba[i + 1], rgba[i], rgba[i + 3]]);
    }
  }
  out.add(Uint8List(maskRowBytes * size)); // all zero: alpha channel decides
  return out.takeBytes();
}

Uint8List encodeIco(Rgba color) {
  const sizes = [16, 32];
  final images = [for (final s in sizes) _dib(s, render(s, color))];
  final header = ByteData(6 + 16 * sizes.length)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, sizes.length, Endian.little);
  var offset = header.lengthInBytes;
  for (var i = 0; i < sizes.length; i++) {
    final entry = 6 + 16 * i;
    header
      ..setUint8(entry, sizes[i])
      ..setUint8(entry + 1, sizes[i])
      ..setUint16(entry + 4, 1, Endian.little)
      ..setUint16(entry + 6, 32, Endian.little)
      ..setUint32(entry + 8, images[i].length, Endian.little)
      ..setUint32(entry + 12, offset, Endian.little);
    offset += images[i].length;
  }
  final out = BytesBuilder()..add(header.buffer.asUint8List());
  for (final image in images) {
    out.add(image);
  }
  return out.takeBytes();
}

void main() {
  const mac = <String, Rgba>{
    'normal': (0, 0, 0, 255),
    'offline': (0, 0, 0, 90),
    'active': (0x22, 0xC5, 0x5E, 255),
  };
  const windows = <String, Rgba>{
    'normal': (0x3B, 0x82, 0xF6, 255),
    'offline': (0x9C, 0xA3, 0xAF, 255),
    'active': (0x22, 0xC5, 0x5E, 255),
  };
  final dir = Directory('assets/tray')..createSync(recursive: true);
  for (final name in mac.keys) {
    File(
      '${dir.path}/tray_$name.png',
    ).writeAsBytesSync(encodePng(36, render(36, mac[name]!)));
    File(
      '${dir.path}/tray_$name.ico',
    ).writeAsBytesSync(encodeIco(windows[name]!));
  }
  stdout.writeln('Wrote ${mac.length * 2} icons to ${dir.path}');
}
```

Run: `dart run tool/gen_tray_icons.dart`
Expected: `Wrote 6 icons to assets/tray`; `file assets/tray/*` báo `PNG image data, 36 x 36` và `MS Windows icon resource - 2 icons, 16x16, 32 bits/pixel, 32x32`.

Trong `apps/desktop/pubspec.yaml`, mục `flutter:` trở thành:

```yaml
flutter:
  uses-material-design: true
  generate: true
  assets:
    - assets/tray/
```

- [ ] **Step 5: Chạy test, xác nhận qua**

Run: `flutter test test/tray`
Expected: `All tests passed!` (14 test).

- [ ] **Step 6: Commit**

```bash
git add lib/src/tray tool assets pubspec.yaml test/tray
git commit -m "feat(desktop): add tray menu, three-state icons and presenter"
```

---

### Task 9: Điều hướng cửa sổ, điều phối theo state, hành động tray có xác nhận

**Files:**
- Create: `apps/desktop/lib/src/ui/window_router.dart`, `window_coordinator.dart`, `window_host.dart`, `apps/desktop/lib/src/tray/tray_actions.dart`
- Test: `apps/desktop/test/ui/window_flow_test.dart`

**Interfaces:**
- Consumes: Task 7 `agentControllerProvider`, `AgentController`, `desktopServicesProvider`; Task 8 `TrayAction` và các lớp con; `window_manager` (`windowManager`, `WindowListener`).
- Produces:
  - `sealed class WindowRoute` với `LoginRoute`, `OnboardingRoute`, `PairingRoute`, `ChangePasswordRoute`; `final class ConfirmRequest { ConfirmRequest({required String title, required String body, required String confirmLabel}); Future<bool> get result; void complete(bool value); }`; `final class WindowState { const WindowState({WindowRoute? route, ConfirmRequest? confirm}); bool get visible; }`; `final windowRouterProvider = NotifierProvider<WindowRouter, WindowState>(…)`; `class WindowRouter { WindowRoute? get current; void open(WindowRoute); void close(); Future<bool> confirm(ConfirmRequest); }` — rời `PairingRoute` gọi `cancelPairing()`; rời `OnboardingRoute` khi chưa xong gọi `completeOnboarding()`.
  - `void coordinateWindows(AgentViewState? previous, AgentViewState next, WindowRouter router)`.
  - `abstract interface class WindowHost { Future<void> show(Size size); Future<void> hide(); }`; `Size windowSizeFor(WindowState)`; `final class WindowPresenter { WindowPresenter(WindowHost host); Future<void> apply(WindowState state); }`; `final class WindowManagerHost with WindowListener implements WindowHost { WindowManagerHost({required void Function() onCloseRequested}); Future<void> init(); }`.
  - `final trayActionsProvider = Provider<TrayActions>(TrayActions.new);` `final class TrayActions { Future<void> handle(TrayAction action); }`.

- [ ] **Step 1: Viết test thất bại**

`apps/desktop/test/ui/window_flow_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';
import 'package:shellx_desktop/src/ui/window_coordinator.dart';
import 'package:shellx_desktop/src/ui/window_host.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fakes.dart';

final class _FakeWindowHost implements WindowHost {
  final List<String> calls = [];
  @override
  Future<void> show(Size size) async =>
      calls.add('show ${size.width.toInt()}x${size.height.toInt()}');
  @override
  Future<void> hide() async => calls.add('hide');
}

void main() {
  late TestHarness h;
  late ProviderContainer container;

  WindowRouter router() => container.read(windowRouterProvider.notifier);
  WindowState window() => container.read(windowRouterProvider);
  AgentController agent() => container.read(agentControllerProvider.notifier);
  AgentViewState agentState() => container.read(agentControllerProvider);
  TrayActions tray() => container.read(trayActionsProvider);

  Future<void> signedIn({
    Map<String, bool>? settings,
    List<TrustedDevice> trusted = const [],
  }) async {
    h = TestHarness(settings: settings);
    container = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    container.listen(
      agentControllerProvider,
      (prev, next) => coordinateWindows(prev, next, router()),
    );
    await h.seedSignedIn();
    for (final device in trusted) {
      await TrustedStore(h.secureStore).add(device);
    }
    await agent().bootstrap(watchForWake: false);
  }

  /// Answers the confirm dialog currently shown.
  Future<void> answer(bool yes) async {
    await pumpEventQueue();
    window().confirm!.complete(yes);
    await pumpEventQueue();
  }

  group('WindowRouter', () {
    test('closing the QR window invalidates the pairing code', () async {
      await signedIn(settings: {'onboarding_done': true});
      await tray().handle(const PairPhone());
      expect(window().route, isA<PairingRoute>());
      expect(agentState().pairing, isNotNull);

      router().close();

      expect(window().visible, isFalse);
      expect(h.runtime.pairingCancels, 1);
      expect(agentState().pairing, isNull);
    });

    test('a confirm on top of the QR window does not cancel pairing', () async {
      await signedIn(settings: {'onboarding_done': true});
      await tray().handle(const PairPhone());
      final pending = router().confirm(
        ConfirmRequest(title: 't', body: 'b', confirmLabel: 'ok'),
      );
      router().close();
      expect(await pending, isFalse);
      expect(window().route, isA<PairingRoute>());
      expect(h.runtime.pairingCancels, 0);
    });

    test('closing onboarding counts as finishing it', () async {
      await signedIn();
      expect(window().route, isA<OnboardingRoute>());
      router().close();
      await pumpEventQueue();
      expect(agentState().onboardingDone, isTrue);
      expect(h.launchAtLogin.enabled, isTrue);
    });
  });

  group('coordinateWindows', () {
    test('startup signed out opens the login window', () async {
      h = TestHarness();
      container = ProviderContainer.test(
        overrides: [desktopServicesProvider.overrideWithValue(h.services())],
      );
      container.listen(
        agentControllerProvider,
        (prev, next) => coordinateWindows(prev, next, router()),
      );
      await agent().bootstrap(watchForWake: false);
      expect(window().route, isA<LoginRoute>());
    });

    test('4002 while running brings the login window back', () async {
      await signedIn(settings: {'onboarding_done': true});
      expect(window().visible, isFalse);
      h.runtime.emitRelay(RelayConnectionState.revoked);
      await pumpEventQueue();
      expect(window().route, isA<LoginRoute>());
      expect(agentState().signedOutNotice, isTrue);
    });

    test('a phone finishing pairing closes the QR window', () async {
      await signedIn(settings: {'onboarding_done': true});
      await tray().handle(const PairPhone());
      h.runtime.eventController.add(MobilePaired(phone('m1', 'Pixel')));
      await pumpEventQueue();
      expect(window().visible, isFalse);
    });

    test(
      'signing in from the login window hides it (onboarding already done)',
      () async {
        h = TestHarness(settings: {'onboarding_done': true});
        container = ProviderContainer.test(
          overrides: [desktopServicesProvider.overrideWithValue(h.services())],
        );
        container.listen(
          agentControllerProvider,
          (prev, next) => coordinateWindows(prev, next, router()),
        );
        await agent().bootstrap(watchForWake: false);
        expect(window().route, isA<LoginRoute>());
        await agent().signIn(
          email: 'a@b.co',
          password: '12345678',
          register: false,
        );
        expect(window().visible, isFalse);
      },
    );
  });

  group('TrayActions', () {
    List<SessionSummary> oneSession() => [
      SessionSummary(
        id: 1,
        index: 1,
        shell: 'zsh',
        createdAt: DateTime(2026),
        attachedMobileId: null,
      ),
    ];

    test(
      'remote access off with sessions asks first; cancel keeps it on',
      () async {
        await signedIn(settings: {'onboarding_done': true});
        h.runtime.currentSessions = oneSession();
        h.runtime.sessionController.add(null);

        final done = tray().handle(const ToggleRemoteAccess());
        await answer(false);
        await done;
        expect(agentState().remoteAccess, isTrue);

        final again = tray().handle(const ToggleRemoteAccess());
        await answer(true);
        await again;
        expect(agentState().remoteAccess, isFalse);
        expect(h.runtime.stopped, isTrue);
      },
    );

    test('remote access off without sessions does not ask', () async {
      await signedIn(settings: {'onboarding_done': true});
      await tray().handle(const ToggleRemoteAccess());
      expect(agentState().remoteAccess, isFalse);
      expect(window().confirm, isNull);
    });

    test('revoke asks with the phone name, then revokes', () async {
      await signedIn(
        settings: {'onboarding_done': true},
        trusted: [phone('m1', 'iPhone của Phú')],
      );
      final done = tray().handle(const RevokeDevice('m1'));
      await pumpEventQueue();
      expect(window().confirm!.title, 'Revoke iPhone của Phú?');
      await answer(true);
      await done;
      expect(h.runtime.revoked, ['m1']);
    });

    test('sign out asks, signs out and shows the login window', () async {
      await signedIn(settings: {'onboarding_done': true});
      final done = tray().handle(const SignOut());
      await answer(true);
      await done;
      expect(agentState().phase, AuthPhase.signedOut);
      expect(window().route, isA<LoginRoute>());
    });

    test('quit with sessions asks, then shuts down and quits', () async {
      await signedIn(settings: {'onboarding_done': true});
      h.runtime.currentSessions = oneSession();
      h.runtime.sessionController.add(null);
      final done = tray().handle(const Quit());
      await answer(true);
      await done;
      expect(h.runtime.stopped, isTrue);
      expect(h.keepAwake.last, isFalse);
      expect(h.quits, 1);
    });

    test('close one session / all sessions go to the runtime', () async {
      await signedIn(settings: {'onboarding_done': true});
      await tray().handle(const CloseSession(4));
      await tray().handle(const CloseAllSessions());
      expect(h.runtime.closedSessions, [4]);
      expect(h.runtime.closedAll, isTrue);
    });
  });

  test(
    'WindowPresenter shows with the route size and hides when closed',
    () async {
      final host = _FakeWindowHost();
      final presenter = WindowPresenter(host);
      await presenter.apply(const WindowState(route: LoginRoute()));
      await presenter.apply(const WindowState(route: LoginRoute()));
      await presenter.apply(const WindowState(route: PairingRoute()));
      await presenter.apply(const WindowState());
      expect(host.calls, ['show 440x620', 'show 440x660', 'hide']);
    },
  );
}
```

- [ ] **Step 2: Chạy test, xác nhận thất bại**

Run: `flutter test test/ui/window_flow_test.dart`
Expected: FAIL — `Error when reading 'lib/src/tray/tray_actions.dart': No such file or directory`.

- [ ] **Step 3: Cài đặt**

`apps/desktop/lib/src/ui/window_router.dart` (đặt state mới **trước** khi dọn route cũ, để listener điều phối không gọi `close()` lồng nhau):

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/agent_controller.dart';

sealed class WindowRoute {
  const WindowRoute();
}

final class LoginRoute extends WindowRoute {
  const LoginRoute();
}

final class OnboardingRoute extends WindowRoute {
  const OnboardingRoute();
}

final class PairingRoute extends WindowRoute {
  const PairingRoute();
}

final class ChangePasswordRoute extends WindowRoute {
  const ChangePasswordRoute();
}

/// A yes/no question shown in the window on top of whatever route is open.
final class ConfirmRequest {
  ConfirmRequest({
    required this.title,
    required this.body,
    required this.confirmLabel,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final Completer<bool> _completer = Completer<bool>();

  Future<bool> get result => _completer.future;

  void complete(bool value) {
    if (!_completer.isCompleted) _completer.complete(value);
  }
}

@immutable
final class WindowState {
  const WindowState({this.route, this.confirm});

  final WindowRoute? route;
  final ConfirmRequest? confirm;

  /// The single app window is shown only while something is open.
  bool get visible => route != null || confirm != null;
}

final windowRouterProvider = NotifierProvider<WindowRouter, WindowState>(
  WindowRouter.new,
);

/// Decides what the single Flutter window shows; hidden when nothing is open.
class WindowRouter extends Notifier<WindowState> {
  @override
  WindowState build() => const WindowState();

  WindowRoute? get current => state.route;

  void open(WindowRoute route) {
    final leaving = state.route;
    state = WindowState(route: route, confirm: state.confirm);
    _leave(leaving, next: route);
  }

  /// The window's close button, Escape, or a page that is done.
  void close() {
    final confirm = state.confirm;
    if (confirm != null) {
      confirm.complete(false);
      state = WindowState(route: state.route);
      return;
    }
    final leaving = state.route;
    state = const WindowState();
    _leave(leaving, next: null);
  }

  Future<bool> confirm(ConfirmRequest request) async {
    state.confirm?.complete(false);
    state = WindowState(route: state.route, confirm: request);
    final result = await request.result;
    if (ref.mounted && identical(state.confirm, request)) {
      state = WindowState(route: state.route);
    }
    return result;
  }

  void _leave(WindowRoute? current, {required WindowRoute? next}) {
    final agent = ref.read(agentControllerProvider.notifier);
    if (current is PairingRoute && next is! PairingRoute) {
      // Closing the QR window invalidates the pairing code (spec §5.3).
      agent.cancelPairing();
    }
    if (current is OnboardingRoute &&
        next is! OnboardingRoute &&
        !ref.read(agentControllerProvider).onboardingDone) {
      unawaited(agent.completeOnboarding());
    }
  }
}
```

`apps/desktop/lib/src/ui/window_coordinator.dart`:

```dart
import '../agent/agent_state.dart';
import 'window_router.dart';

/// Opens and closes windows when the agent state changes on its own
/// (startup, 4002 sign-out, a phone finishing pairing).
void coordinateWindows(
  AgentViewState? previous,
  AgentViewState next,
  WindowRouter router,
) {
  final before = previous?.phase;
  if (next.phase == AuthPhase.signedOut && before != AuthPhase.signedOut) {
    router.open(const LoginRoute());
  } else if (next.phase == AuthPhase.signedIn && before != AuthPhase.signedIn) {
    if (!next.onboardingDone) {
      router.open(const OnboardingRoute());
    } else if (router.current is LoginRoute) {
      router.close();
    }
  }
  if (previous?.pairing != null &&
      next.pairing == null &&
      router.current is PairingRoute) {
    router.close();
  }
}
```

`apps/desktop/lib/src/ui/window_host.dart`:

```dart
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import 'window_router.dart';

abstract interface class WindowHost {
  Future<void> show(Size size);
  Future<void> hide();
}

Size windowSizeFor(WindowState state) {
  if (state.confirm != null) return const Size(440, 260);
  return switch (state.route) {
    LoginRoute() => const Size(440, 620),
    OnboardingRoute() => const Size(520, 660),
    PairingRoute() => const Size(440, 660),
    ChangePasswordRoute() => const Size(440, 480),
    null => const Size(440, 260),
  };
}

/// Shows/hides the single window to follow the router.
final class WindowPresenter {
  WindowPresenter(this._host);

  final WindowHost _host;
  bool _visible = false;
  Size? _size;

  Future<void> apply(WindowState state) async {
    if (!state.visible) {
      if (_visible) await _host.hide();
      _visible = false;
      return;
    }
    final size = windowSizeFor(state);
    if (_visible && size == _size) return;
    _visible = true;
    _size = size;
    await _host.show(size);
  }
}

/// [WindowHost] over package window_manager. The native close button hides
/// the window through [onCloseRequested] instead of quitting the app.
final class WindowManagerHost with WindowListener implements WindowHost {
  WindowManagerHost({required this.onCloseRequested});

  final void Function() onCloseRequested;

  Future<void> init() async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await windowManager.setTitle('ShellX');
    await windowManager.setResizable(false);
    await windowManager.setMaximizable(false);
    windowManager.addListener(this);
  }

  @override
  Future<void> show(Size size) async {
    await windowManager.setSize(size);
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hide() => windowManager.hide();

  @override
  void onWindowClose() => onCloseRequested();
}
```

`apps/desktop/lib/src/tray/tray_actions.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_state.dart';
import '../agent/desktop_services.dart';
import '../ui/window_router.dart';
import 'tray_action.dart';

final trayActionsProvider = Provider<TrayActions>(TrayActions.new);

/// Executes tray menu actions, asking for confirmation where an action is
/// destructive (spec §8.3: turning remote access off with open sessions).
final class TrayActions {
  TrayActions(this._ref);

  final Ref _ref;

  AgentController get _agent => _ref.read(agentControllerProvider.notifier);
  AgentViewState get _state => _ref.read(agentControllerProvider);
  WindowRouter get _router => _ref.read(windowRouterProvider.notifier);
  DesktopServices get _services => _ref.read(desktopServicesProvider);

  Future<void> handle(TrayAction action) async {
    final l10n = _services.l10n;
    final state = _state;
    switch (action) {
      case ToggleRemoteAccess():
        if (state.remoteAccess && state.sessions.isNotEmpty) {
          final ok = await _router.confirm(
            ConfirmRequest(
              title: l10n.confirmRemoteOffTitle,
              body: l10n.confirmRemoteOffBody(state.sessions.length),
              confirmLabel: l10n.confirmRemoteOffAction,
            ),
          );
          if (!ok) return;
        }
        await _agent.setRemoteAccess(!state.remoteAccess);
      case CloseSession(:final id):
        _agent.closeSession(id);
      case CloseAllSessions():
        _agent.closeAllSessions();
      case PairPhone():
        if (_agent.startPairing() != null) _router.open(const PairingRoute());
      case RevokeDevice(:final mobileId):
        final matches = state.trusted.where((d) => d.mobileId == mobileId);
        final name = matches.isEmpty ? mobileId : matches.first.name;
        final ok = await _router.confirm(
          ConfirmRequest(
            title: l10n.confirmRevokeTitle(name),
            body: l10n.confirmRevokeBody,
            confirmLabel: l10n.confirmRevokeAction,
          ),
        );
        if (!ok) return;
        await _agent.revoke(mobileId);
      case ToggleKeepAwake():
        await _agent.setKeepAwake(!state.keepAwake);
      case ToggleLaunchAtStartup():
        await _agent.setLaunchAtStartup(!state.launchAtStartup);
      case OpenChangePassword():
        _router.open(const ChangePasswordRoute());
      case SignOut():
        final ok = await _router.confirm(
          ConfirmRequest(
            title: l10n.confirmSignOutTitle,
            body: l10n.confirmSignOutBody,
            confirmLabel: l10n.confirmSignOutAction,
          ),
        );
        if (!ok) return;
        await _agent.signOut();
      case SignIn():
        _router.open(const LoginRoute());
      case DownloadUpdate():
        final update = state.update;
        if (update != null) await _services.urlOpener.open(update.url);
      case Quit():
        if (state.sessions.isNotEmpty) {
          final ok = await _router.confirm(
            ConfirmRequest(
              title: l10n.confirmQuitTitle,
              body: l10n.confirmQuitBody(state.sessions.length),
              confirmLabel: l10n.confirmQuitAction,
            ),
          );
          if (!ok) return;
        }
        await _agent.shutdown();
        await _services.quitApp?.call();
    }
  }
}
```

- [ ] **Step 4: Chạy test, xác nhận qua**

Run: `flutter test test/ui/window_flow_test.dart`
Expected: `All tests passed!` (14 test).

- [ ] **Step 5: Commit**

```bash
git add lib/src/ui lib/src/tray/tray_actions.dart test/ui/window_flow_test.dart
git commit -m "feat(desktop): add window router, state-driven windows and confirmed tray actions"
```

---

### Task 10: Các cửa sổ — đăng nhập/đăng ký, onboarding, QR, đổi mật khẩu, xác nhận

**Files:**
- Create: `apps/desktop/lib/src/ui/form_rules.dart`, `apps/desktop/lib/src/ui/app.dart`, `apps/desktop/lib/src/ui/pages/login_page.dart`, `onboarding_page.dart`, `pairing_page.dart`, `change_password_page.dart`, `confirm_page.dart`
- Test: `apps/desktop/test/ui/pages_test.dart`

**Interfaces:**
- Consumes: Task 7 (`agentControllerProvider`, `desktopServicesProvider`, `clockProvider`), Task 9 (`windowRouterProvider`, route, `ConfirmRequest`, `coordinateWindows`), Task 5 `SystemUrlOpener.fullDiskAccessPane`, `qr_flutter` (`QrImageView(data:, size:, backgroundColor:, errorCorrectionLevel: QrErrorCorrectLevel.M)`), core `ApiException`, `RelayConnectionState`, `DevicePlatform`.
- Produces: `bool looksLikeEmail(String)`, `bool validPasswordLength(String)` (8–128 theo code unit UTF-16, giống `length` của JS phía relay), `String apiErrorText(ApiException, AppLocalizations)`, `String formatCountdown(Duration)`; `class ShellxDesktopApp extends StatelessWidget { const ShellxDesktopApp({super.key, required Locale locale}); }`; `class WindowContent extends ConsumerWidget`; các page `LoginPage`, `OnboardingPage`, `PairingPage`, `ChangePasswordPage`, `ConfirmPage({required ConfirmRequest request})`. Key widget cho test: `login.{email,password,confirm,submit,toggle,error,notice}`, `onboarding.{launch,fda,finish}`, `pairing.{qr,countdown,expired,new,offline}`, `password.{new,confirm,submit,error,done,close}`, `confirm.{cancel,ok}`.

- [ ] **Step 1: Viết test thất bại**

`apps/desktop/test/ui/pages_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/url_opener.dart';
import 'package:shellx_desktop/src/ui/app.dart';
import 'package:shellx_desktop/src/ui/window_coordinator.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fakes.dart';

late TestHarness h;
late ProviderContainer container;
DateTime now = DateTime(2026, 9, 25, 12);

WindowRouter router() => container.read(windowRouterProvider.notifier);
AgentController agent() => container.read(agentControllerProvider.notifier);
AgentViewState agentState() => container.read(agentControllerProvider);

Future<void> pumpApp(
  WidgetTester tester,
  TestHarness harness, {
  Locale locale = const Locale('en'),
}) async {
  h = harness;
  now = DateTime(2026, 9, 25, 12);
  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      clockProvider.overrideWithValue(() => now),
    ],
  );
  addTearDown(container.dispose);
  container.listen(
    agentControllerProvider,
    (prev, next) => coordinateWindows(prev, next, router()),
  );
  tester.view.physicalSize = const Size(520, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ShellxDesktopApp(locale: locale),
    ),
  );
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('LoginPage', () {
    testWidgets('rejects an invalid email without calling the relay', (
      tester,
    ) async {
      await pumpApp(tester, TestHarness());
      router().open(const LoginRoute());
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('login.email')),
        'not-an-email',
      );
      await tester.enterText(
        find.byKey(const Key('login.password')),
        '12345678',
      );
      await tester.tap(find.byKey(const Key('login.submit')));
      await settle(tester);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(h.relay.requests, isEmpty);
    });

    testWidgets('rejects a 7-character password', (tester) async {
      await pumpApp(tester, TestHarness());
      router().open(const LoginRoute());
      await settle(tester);
      await tester.enterText(find.byKey(const Key('login.email')), 'a@b.co');
      await tester.enterText(
        find.byKey(const Key('login.password')),
        '1234567',
      );
      await tester.tap(find.byKey(const Key('login.submit')));
      await settle(tester);
      expect(find.text('Password must be 8–128 characters.'), findsOneWidget);
    });

    testWidgets('signs in and hands over to onboarding', (tester) async {
      await pumpApp(tester, TestHarness());
      router().open(const LoginRoute());
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('login.email')),
        'Phu@Example.com',
      );
      await tester.enterText(
        find.byKey(const Key('login.password')),
        'correct horse',
      );
      await tester.tap(find.byKey(const Key('login.submit')));
      await settle(tester);
      expect(h.relay.routes, contains('POST /v1/auth/login'));
      expect(agentState().phase, AuthPhase.signedIn);
      expect(
        container.read(windowRouterProvider).route,
        isA<OnboardingRoute>(),
      );
    });

    testWidgets('shows relay errors in Vietnamese', (tester) async {
      await pumpApp(
        tester,
        TestHarness(locale: const Locale('vi')),
        locale: const Locale('vi'),
      );
      h.relay.failures['POST /v1/auth/login'] = (401, 'invalid_credentials');
      router().open(const LoginRoute());
      await settle(tester);
      await tester.enterText(find.byKey(const Key('login.email')), 'a@b.co');
      await tester.enterText(
        find.byKey(const Key('login.password')),
        '12345678',
      );
      await tester.tap(find.byKey(const Key('login.submit')));
      await settle(tester);
      expect(find.text('Email hoặc mật khẩu không đúng.'), findsOneWidget);

      h.relay.failures['POST /v1/auth/login'] = (429, 'rate_limited');
      await tester.tap(find.byKey(const Key('login.submit')));
      await settle(tester);
      expect(find.text('Thử lại sau ít phút.'), findsOneWidget);
    });

    testWidgets('register mode checks the confirmation and calls register', (
      tester,
    ) async {
      await pumpApp(tester, TestHarness());
      router().open(const LoginRoute());
      await settle(tester);
      await tester.tap(find.byKey(const Key('login.toggle')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('login.email')), 'new@b.co');
      await tester.enterText(
        find.byKey(const Key('login.password')),
        '12345678',
      );
      await tester.enterText(
        find.byKey(const Key('login.confirm')),
        '12345679',
      );
      await tester.tap(find.byKey(const Key('login.submit')));
      await settle(tester);
      expect(find.text('Passwords do not match.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('login.confirm')),
        '12345678',
      );
      await tester.tap(find.byKey(const Key('login.submit')));
      await settle(tester);
      expect(h.relay.routes, contains('POST /v1/auth/register'));
    });

    testWidgets('after a 4002 the login window explains the sign-out', (
      tester,
    ) async {
      await pumpApp(tester, TestHarness(settings: {'onboarding_done': true}));
      await agent().signIn(
        email: 'a@b.co',
        password: '12345678',
        register: false,
      );
      await settle(tester);
      h.runtime.emitRelay(RelayConnectionState.revoked);
      await settle(tester);
      expect(find.byKey(const Key('login.notice')), findsOneWidget);
      expect(find.text('You were signed out. Sign in again.'), findsOneWidget);
    });
  });

  group('OnboardingPage', () {
    testWidgets('macOS: Full Disk Access button opens the privacy pane', (
      tester,
    ) async {
      await pumpApp(tester, TestHarness());
      router().open(const OnboardingRoute());
      await settle(tester);
      await tester.tap(find.byKey(const Key('onboarding.fda')));
      await settle(tester);
      expect(h.urlOpener.opened.single, SystemUrlOpener.fullDiskAccessPane);
      expect(
        h.urlOpener.opened.single.toString(),
        'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
      );
    });

    testWidgets('Windows: no Full Disk Access section', (tester) async {
      await pumpApp(tester, TestHarness(platform: DevicePlatform.windows));
      router().open(const OnboardingRoute());
      await settle(tester);
      expect(find.byKey(const Key('onboarding.fda')), findsNothing);
      expect(find.textContaining('system tray'), findsOneWidget);
    });

    testWidgets(
      'launch at startup is on by default; Finish applies it and hides',
      (tester) async {
        await pumpApp(tester, TestHarness());
        router().open(const OnboardingRoute());
        await settle(tester);
        final toggle = tester.widget<SwitchListTile>(
          find.byKey(const Key('onboarding.launch')),
        );
        expect(toggle.value, isTrue);
        await tester.tap(find.byKey(const Key('onboarding.finish')));
        await settle(tester);
        expect(h.launchAtLogin.enabled, isTrue);
        expect(agentState().onboardingDone, isTrue);
        expect(container.read(windowRouterProvider).visible, isFalse);
      },
    );
  });

  group('PairingPage', () {
    Future<void> openPairing(WidgetTester tester) async {
      await pumpApp(tester, TestHarness(settings: {'onboarding_done': true}));
      await agent().signIn(
        email: 'a@b.co',
        password: '12345678',
        register: false,
      );
      agent().startPairing();
      router().open(const PairingRoute());
      await settle(tester);
    }

    testWidgets('shows the QR and counts down to expiry', (tester) async {
      await openPairing(tester);
      expect(find.byKey(const Key('pairing.qr')), findsOneWidget);
      expect(find.text('Code expires in 5:00'), findsOneWidget);

      now = now.add(const Duration(minutes: 4, seconds: 59));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Code expires in 0:01'), findsOneWidget);
    });

    testWidgets('an expired code hides the QR and offers a new one', (
      tester,
    ) async {
      await openPairing(tester);
      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('pairing.qr')), findsNothing);
      expect(find.byKey(const Key('pairing.expired')), findsOneWidget);

      await tester.tap(find.byKey(const Key('pairing.new')));
      await tester.pump(const Duration(seconds: 1));
      expect(h.runtime.pairingStarts, 2);
      expect(find.byKey(const Key('pairing.qr')), findsOneWidget);
      expect(find.text('Code expires in 1:00'), findsOneWidget);
    });

    testWidgets('warns while the relay is not connected', (tester) async {
      await openPairing(tester);
      expect(find.byKey(const Key('pairing.offline')), findsOneWidget);
      h.runtime.emitRelay(RelayConnectionState.connected);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('pairing.offline')), findsNothing);
    });

    testWidgets('closes itself once the phone is paired', (tester) async {
      await openPairing(tester);
      h.runtime.eventController.add(MobilePaired(phone('m1', 'Pixel')));
      await tester.pump(const Duration(seconds: 1));
      expect(container.read(windowRouterProvider).visible, isFalse);
      expect(find.byKey(const Key('pairing.qr')), findsNothing);
    });
  });

  group('ChangePasswordPage', () {
    Future<void> openChange(WidgetTester tester) async {
      await pumpApp(tester, TestHarness(settings: {'onboarding_done': true}));
      await agent().signIn(
        email: 'a@b.co',
        password: '12345678',
        register: false,
      );
      router().open(const ChangePasswordRoute());
      await settle(tester);
    }

    testWidgets('both fields must match and be 8–128 characters', (
      tester,
    ) async {
      await openChange(tester);
      await tester.enterText(find.byKey(const Key('password.new')), 'short');
      await tester.enterText(
        find.byKey(const Key('password.confirm')),
        'short',
      );
      await tester.tap(find.byKey(const Key('password.submit')));
      await settle(tester);
      expect(find.text('Password must be 8–128 characters.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('password.new')),
        'long enough 1',
      );
      await tester.enterText(
        find.byKey(const Key('password.confirm')),
        'long enough 2',
      );
      await tester.tap(find.byKey(const Key('password.submit')));
      await settle(tester);
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(h.relay.routes, isNot(contains('POST /v1/auth/password')));
    });

    testWidgets('success posts the new password and confirms', (tester) async {
      await openChange(tester);
      await tester.enterText(
        find.byKey(const Key('password.new')),
        'long enough 1',
      );
      await tester.enterText(
        find.byKey(const Key('password.confirm')),
        'long enough 1',
      );
      await tester.tap(find.byKey(const Key('password.submit')));
      await settle(tester);
      expect(jsonDecode(h.relay.last('POST /v1/auth/password').body), {
        'new_password': 'long enough 1',
      });
      expect(find.byKey(const Key('password.done')), findsOneWidget);
      await tester.tap(find.byKey(const Key('password.close')));
      await settle(tester);
      expect(container.read(windowRouterProvider).visible, isFalse);
    });

    testWidgets('server-side weak_password is shown', (tester) async {
      await openChange(tester);
      h.relay.failures['POST /v1/auth/password'] = (400, 'weak_password');
      await tester.enterText(find.byKey(const Key('password.new')), 'aaaaaaaa');
      await tester.enterText(
        find.byKey(const Key('password.confirm')),
        'aaaaaaaa',
      );
      await tester.tap(find.byKey(const Key('password.submit')));
      await settle(tester);
      expect(find.byKey(const Key('password.error')), findsOneWidget);
    });
  });

  testWidgets('ConfirmPage answers the pending request', (tester) async {
    await pumpApp(tester, TestHarness());
    final answer = router().confirm(
      ConfirmRequest(title: 'Quit ShellX?', body: 'body', confirmLabel: 'Quit'),
    );
    await settle(tester);
    expect(find.text('Quit ShellX?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm.ok')));
    await settle(tester);
    expect(await answer, isTrue);
    expect(container.read(windowRouterProvider).visible, isFalse);
  });
}
```

- [ ] **Step 2: Chạy test, xác nhận thất bại**

Run: `flutter test test/ui/pages_test.dart`
Expected: FAIL — `Error when reading 'lib/src/ui/app.dart': No such file or directory`.

- [ ] **Step 3: Cài đặt quy tắc form và các page**

`apps/desktop/lib/src/ui/form_rules.dart`:

```dart
import 'package:shellx_core/shellx_core.dart';

import '../../l10n/app_localizations.dart';

final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Client-side pre-check only; the relay does the real validation (spec §5.2).
bool looksLikeEmail(String value) => _email.hasMatch(value.trim());

/// 8–128 characters, counted in UTF-16 code units like the relay's JS `length`.
bool validPasswordLength(String value) =>
    value.length >= 8 && value.length <= 128;

/// Human text for a relay error (spec §10.2 codes, §12 messages).
String apiErrorText(ApiException error, AppLocalizations l10n) {
  if (error.status == 429) return l10n.errorRateLimited;
  if (error.status == 0 || error.code == 'network') return l10n.errorNetwork;
  return switch (error.code) {
    'invalid_email' => l10n.errorEmailInvalid,
    'disposable_email' => l10n.errorDisposableEmail,
    'weak_password' => l10n.errorPasswordLength,
    'email_taken' => l10n.errorEmailTaken,
    'invalid_credentials' => l10n.errorInvalidCredentials,
    'agent_only' => l10n.errorAgentOnly,
    _ => l10n.errorUnexpected(error.code),
  };
}

/// `m:ss`, never negative.
String formatCountdown(Duration remaining) {
  final clamped = remaining.isNegative ? Duration.zero : remaining;
  final seconds = (clamped.inSeconds % 60).toString().padLeft(2, '0');
  return '${clamped.inMinutes}:$seconds';
}
```

`apps/desktop/lib/src/ui/pages/confirm_page.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../window_router.dart';

class ConfirmPage extends StatelessWidget {
  const ConfirmPage({super.key, required this.request});

  final ConfirmRequest request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(request.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Expanded(
            child: Text(request.body, style: theme.textTheme.bodyMedium),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const Key('confirm.cancel'),
                onPressed: () => request.complete(false),
                child: Text(l10n.actionCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('confirm.ok'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: () => request.complete(true),
                child: Text(request.confirmLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

`apps/desktop/lib/src/ui/pages/login_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../form_rules.dart';

/// Login / register window (spec §8.2 step 1).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email.text = ref.read(agentControllerProvider).email ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validate(AppLocalizations l10n) {
    if (!looksLikeEmail(_email.text)) return l10n.errorEmailInvalid;
    if (!validPasswordLength(_password.text)) return l10n.errorPasswordLength;
    if (_register && _password.text != _confirm.text) {
      return l10n.errorPasswordMismatch;
    }
    return null;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final invalid = _validate(l10n);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(agentControllerProvider.notifier)
          .signIn(
            email: _email.text,
            password: _password.text,
            register: _register,
          );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = apiErrorText(error, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notice = ref.watch(
      agentControllerProvider.select((s) => s.signedOutNotice),
    );
    return Padding(
      padding: const EdgeInsets.all(32),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _register ? l10n.authRegisterTitle : l10n.authSignInTitle,
              style: theme.textTheme.headlineSmall,
            ),
            if (notice) ...[
              const SizedBox(height: 12),
              Text(
                l10n.authSignedOutNotice,
                key: const Key('login.notice'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            TextField(
              key: const Key('login.email'),
              controller: _email,
              enabled: !_busy,
              autofillHints: const [AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: l10n.authEmailLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('login.password'),
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(labelText: l10n.authPasswordLabel),
              onSubmitted: (_) => _register ? null : _submit(),
            ),
            if (_register) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('login.confirm'),
                controller: _confirm,
                enabled: !_busy,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.authConfirmPasswordLabel,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                _error!,
                key: const Key('login.error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('login.submit'),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _register
                          ? l10n.authRegisterButton
                          : l10n.authSignInButton,
                    ),
            ),
            TextButton(
              key: const Key('login.toggle'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _register = !_register;
                      _error = null;
                    }),
              child: Text(
                _register ? l10n.authSwitchToSignIn : l10n.authSwitchToRegister,
              ),
            ),
            const Spacer(),
            Text(l10n.authForgotPasswordHint, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
```

`apps/desktop/lib/src/ui/pages/onboarding_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../../agent/desktop_services.dart';
import '../../platform/url_opener.dart';
import '../window_router.dart';

/// First-run onboarding (spec §8.2 step 2).
class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final services = ref.watch(desktopServicesProvider);
    final isMac = services.platform == DevicePlatform.macos;
    final launch = ref.watch(
      agentControllerProvider.select((s) => s.launchAtStartup),
    );
    final agent = ref.read(agentControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.onboardingTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          SwitchListTile(
            key: const Key('onboarding.launch'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.onboardingLaunchAtStartup),
            value: launch,
            onChanged: (value) => agent.setLaunchAtStartup(value),
          ),
          if (isMac) ...[
            const SizedBox(height: 16),
            Text(
              l10n.onboardingFullDiskTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(l10n.onboardingFullDiskBody),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('onboarding.fda'),
                onPressed: () =>
                    services.urlOpener.open(SystemUrlOpener.fullDiskAccessPane),
                child: Text(l10n.onboardingOpenSettings),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(l10n.onboardingSleepTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(l10n.onboardingSleepBody),
          const Spacer(),
          Text(
            l10n.onboardingTrayHint(isMac ? 'macos' : 'windows'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('onboarding.finish'),
            onPressed: () async {
              await agent.completeOnboarding();
              ref.read(windowRouterProvider.notifier).close();
            },
            child: Text(l10n.onboardingFinish),
          ),
        ],
      ),
    );
  }
}
```

`apps/desktop/lib/src/ui/pages/pairing_page.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../../agent/desktop_services.dart';
import '../form_rules.dart';

/// QR pairing window (spec §5.3): QR of the pairing URI and a countdown to
/// expiry. Closing the window invalidates the code (see WindowRouter).
class PairingPage extends ConsumerStatefulWidget {
  const PairingPage({super.key});

  @override
  ConsumerState<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends ConsumerState<PairingPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(agentControllerProvider);
    final now = ref.watch(clockProvider)();
    final pairing = state.pairing;
    final remaining = pairing?.expiresAt.difference(now) ?? Duration.zero;
    final expired = pairing == null || remaining <= Duration.zero;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.pairingTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(l10n.pairingInstructions),
          const SizedBox(height: 16),
          Center(
            child: SizedBox.square(
              dimension: 260,
              child: expired
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.pairingExpired,
                            key: const Key('pairing.expired'),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            key: const Key('pairing.new'),
                            onPressed: () => ref
                                .read(agentControllerProvider.notifier)
                                .startPairing(),
                            child: Text(l10n.pairingNewCode),
                          ),
                        ],
                      ),
                    )
                  : QrImageView(
                      key: const Key('pairing.qr'),
                      data: pairing.uri.toUriString(),
                      size: 260,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (!expired)
            Text(
              l10n.pairingExpiresIn(formatCountdown(remaining)),
              key: const Key('pairing.countdown'),
              textAlign: TextAlign.center,
            ),
          if (state.relay != RelayConnectionState.connected) ...[
            const SizedBox(height: 12),
            Text(
              l10n.pairingOfflineWarning,
              key: const Key('pairing.offline'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const Spacer(),
          Text(l10n.pairingSecretWarning, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
```

`apps/desktop/lib/src/ui/pages/change_password_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../form_rules.dart';
import '../window_router.dart';

/// "Đổi mật khẩu…" (spec §8.3): new password twice, no old password (§5.2).
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!validPasswordLength(_password.text)) {
      setState(() => _error = l10n.errorPasswordLength);
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = l10n.errorPasswordMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(agentControllerProvider.notifier)
          .changePassword(_password.text);
      if (mounted) setState(() => _done = true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = apiErrorText(error, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final router = ref.read(windowRouterProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.changePasswordTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(l10n.changePasswordNote, style: theme.textTheme.bodySmall),
          const SizedBox(height: 24),
          if (_done) ...[
            Text(l10n.changePasswordDone, key: const Key('password.done')),
            const Spacer(),
            FilledButton(
              key: const Key('password.close'),
              onPressed: router.close,
              child: Text(l10n.actionClose),
            ),
          ] else ...[
            TextField(
              key: const Key('password.new'),
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.changePasswordNew),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('password.confirm'),
              controller: _confirm,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.changePasswordConfirm,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                _error!,
                key: const Key('password.error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : router.close,
                  child: Text(l10n.actionCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('password.submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(l10n.changePasswordSubmit),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
```

`apps/desktop/lib/src/ui/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'pages/change_password_page.dart';
import 'pages/confirm_page.dart';
import 'pages/login_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/pairing_page.dart';
import 'window_router.dart';

/// Root widget. The one window renders whatever the [WindowRouter] has open.
class ShellxDesktopApp extends StatelessWidget {
  const ShellxDesktopApp({super.key, required this.locale});

  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const WindowContent(),
    );
  }
}

class WindowContent extends ConsumerWidget {
  const WindowContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(windowRouterProvider);
    final confirm = window.confirm;
    final Widget page = confirm != null
        ? ConfirmPage(key: ValueKey(confirm), request: confirm)
        : switch (window.route) {
            LoginRoute() => const LoginPage(),
            OnboardingRoute() => const OnboardingPage(),
            PairingRoute() => const PairingPage(),
            ChangePasswordRoute() => const ChangePasswordPage(),
            null => const SizedBox.shrink(),
          };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            ref.read(windowRouterProvider.notifier).close(),
      },
      child: Focus(autofocus: true, child: Scaffold(body: page)),
    );
  }
}
```

- [ ] **Step 4: Chạy test, xác nhận qua**

Run: `flutter test test/ui/pages_test.dart`
Expected: `All tests passed!` (17 test).

- [ ] **Step 5: Commit**

```bash
git add lib/src/ui test/ui/pages_test.dart
git commit -m "feat(desktop): add login, onboarding, QR pairing, change-password and confirm windows"
```

---

### Task 11: Nối toàn bộ trong `main.dart`, kiểm tra khởi động thật

**Files:**
- Modify: `apps/desktop/lib/main.dart`

**Interfaces:**
- Consumes: mọi thứ từ Task 1–10; `package_info_plus` (`PackageInfo.fromPlatform().version` = `version:` của pubspec), `path_provider` (`getApplicationSupportDirectory()`), `win32` (`MessageBox`, `MB_OK`, `MB_ICONERROR`), `PlatformShellResolver({required String operatingSystem, required Map<String, String> environment})`.
- Produces: điểm vào app. Thứ tự: kiểm tra bản Windows ≥ 17763 → khóa một bản (bản thứ hai báo cho bản đang chạy rồi `exit(0)`) → `window_manager` (ẩn, chặn nút đóng) → dựng `DesktopServices` thật → `ProviderContainer` → listener cửa sổ + tray + điều phối → `runApp` → `bootstrap()`.

Task này chỉ nối dây (không có logic mới — logic đã được test ở Task 1–10), nên bước kiểm tra là build + chạy thật thay cho test đơn vị.

- [ ] **Step 1: Xác nhận bản tạm chưa làm gì**

Run: `flutter build macos --debug && perl -e 'alarm 15; exec @ARGV' build/macos/Build/Products/Debug/ShellX.app/Contents/MacOS/ShellX; ls "$HOME/Library/Application Support/pro.shellx.desktop/shellx.lock"`
Expected: FAIL — `No such file or directory` (entry point tạm của Task 1 không tạo khóa, không có tray).

- [ ] **Step 2: Viết `main.dart`**

`apps/desktop/lib/main.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:win32/win32.dart' as win32;

import 'l10n/app_localizations.dart';
import 'src/agent/agent_controller.dart';
import 'src/agent/agent_runtime.dart';
import 'src/agent/agent_state.dart';
import 'src/agent/desktop_services.dart';
import 'src/config.dart';
import 'src/l10n/locale.dart';
import 'src/platform/keep_awake.dart';
import 'src/platform/launch_at_login.dart';
import 'src/platform/notifier.dart';
import 'src/platform/pty/flutter_pty_factory.dart';
import 'src/platform/secure_key_value_store.dart';
import 'src/platform/settings_store.dart';
import 'src/platform/single_instance.dart';
import 'src/platform/system_info.dart';
import 'src/platform/url_opener.dart';
import 'src/tray/tray_actions.dart';
import 'src/tray/tray_presenter.dart';
import 'src/ui/app.dart';
import 'src/ui/window_coordinator.dart';
import 'src/ui/window_host.dart';
import 'src/ui/window_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final locale = resolveAppLocale(PlatformDispatcher.instance.locales);
  final l10n = lookupAppLocalizations(locale);

  if (Platform.isWindows &&
      !isSupportedWindowsBuild(Platform.operatingSystemVersion)) {
    _windowsErrorBox(l10n.windowsVersionUnsupported);
    exit(1);
  }

  // Spec §8.2: only one agent at a time.
  final lock = SingleInstanceLock(await getApplicationSupportDirectory());
  if (!await lock.acquire()) {
    await lock.signalRunningInstance();
    exit(0);
  }

  late final ProviderContainer container;
  final windowHost = WindowManagerHost(
    onCloseRequested: () =>
        container.read(windowRouterProvider.notifier).close(),
  );
  await windowHost.init();

  final info = await PackageInfo.fromPlatform();
  final environment = Map<String, String>.of(Platform.environment);
  final home =
      environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ??
      Directory.current.path;
  final relayBase = Uri.parse(kRelayBaseUrl);
  final ptyFactory = FlutterPtyFactory.forCurrentPlatform();
  final notifier = await LocalSystemNotifier.setup();
  late final TrayManagerHost trayHost;

  final services = DesktopServices(
    secureStore: SecureKeyValueStore(),
    settings: await SharedPrefsSettingsStore.open(),
    api: ShellxApi(baseUri: relayBase),
    runtimeFactory: (params) => CoreAgentRuntime(
      params,
      relayBaseUri: relayBase,
      appVersion: info.version,
      ptyFactory: ptyFactory,
      shellResolver: PlatformShellResolver(
        operatingSystem: Platform.operatingSystem,
        environment: environment,
      ),
      homeDirectory: home,
      baseEnvironment: environment,
    ),
    keepAwake: Platform.isWindows ? WindowsKeepAwake() : CaffeinateKeepAwake(),
    launchAtLogin: PackageLaunchAtLogin(),
    notifier: notifier,
    urlOpener: SystemUrlOpener(),
    l10n: l10n,
    appVersion: info.version,
    platform: Platform.isWindows
        ? DevicePlatform.windows
        : DevicePlatform.macos,
    deviceName: deviceNameFromHostname(Platform.localHostname),
    quitApp: () async {
      await trayHost.destroy();
      await lock.release();
      exit(0);
    },
  );

  container = ProviderContainer(
    overrides: [desktopServicesProvider.overrideWithValue(services)],
  );

  final windowPresenter = WindowPresenter(windowHost);
  container.listen<WindowState>(
    windowRouterProvider,
    (_, next) => unawaited(windowPresenter.apply(next)),
    fireImmediately: true,
  );

  final trayActions = container.read(trayActionsProvider);
  late final TrayPresenter trayPresenter;
  trayHost = TrayManagerHost(
    onClick: (item) => trayPresenter.onMenuItemClick(item),
  );
  trayPresenter = TrayPresenter(
    host: trayHost,
    l10n: l10n,
    isWindows: Platform.isWindows,
    onAction: trayActions.handle,
  );
  container.listen<AgentViewState>(agentControllerProvider, (previous, next) {
    unawaited(trayPresenter.render(next));
    coordinateWindows(
      previous,
      next,
      container.read(windowRouterProvider.notifier),
    );
  }, fireImmediately: true);

  // A second launch (double-click while running) asks us to come forward.
  lock.activationRequests().listen((_) {
    final state = container.read(agentControllerProvider);
    if (!state.signedIn) {
      container.read(windowRouterProvider.notifier).open(const LoginRoute());
    } else {
      unawaited(
        notifier.show(
          title: l10n.notifyAlreadyRunningTitle,
          body: l10n.notifyAlreadyRunningBody(
            Platform.isWindows ? 'windows' : 'macos',
          ),
        ),
      );
    }
  });

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: ShellxDesktopApp(locale: locale),
    ),
  );
  await container.read(agentControllerProvider.notifier).bootstrap();
}

void _windowsErrorBox(String message) {
  final text = message.toNativeUtf16();
  final title = 'ShellX'.toNativeUtf16();
  win32.MessageBox(0, text, title, win32.MB_OK | win32.MB_ICONERROR);
  calloc.free(text);
  calloc.free(title);
}
```

- [ ] **Step 3: Phân tích tĩnh và toàn bộ test**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` và `All tests passed!`.

- [ ] **Step 4: Chạy thật trên macOS (khói)**

```bash
flutter build macos --debug
perl -e 'alarm 20; exec @ARGV' build/macos/Build/Products/Debug/ShellX.app/Contents/MacOS/ShellX > "$TMPDIR/shellx-smoke.log" 2>&1; echo "exit=$?"
grep -c "Unhandled Exception" "$TMPDIR/shellx-smoke.log"
ls "$HOME/Library/Application Support/pro.shellx.desktop/shellx.lock"
```

Expected: `exit=142` (bị `alarm` dừng sau 20 s, nghĩa là app sống suốt thời gian đó), `0` dòng `Unhandled Exception`, file khóa tồn tại. Trong 20 s đó icon ">_" xám xuất hiện trên menu bar và cửa sổ "Sign in to ShellX"/"Đăng nhập ShellX" hiện ra (chưa có token).

- [ ] **Step 5: Kiểm tra thủ công với relay cục bộ (người thật, không bắt buộc cho agent)**

Với relay của plan 01 chạy bằng `npm run dev` trong `relay/`: `flutter run -d macos --dart-define=SHELLX_RELAY=http://127.0.0.1:8787`, rồi: đăng ký → onboarding (bật/tắt "Khởi động cùng hệ thống", nút Full Disk Access mở đúng trang) → "Hoàn tất" ẩn cửa sổ → icon chuyển thường khi kết nối → "Ghép nối điện thoại…" hiện QR + đếm ngược 5:00 → đóng cửa sổ → "Thiết bị đã ghép" → "Đổi mật khẩu…" → "Đăng xuất" (hỏi xác nhận) → "Thoát". Mở app lần hai khi đang chạy: bản thứ hai thoát, bản đầu hiện thông báo "ShellX đang chạy".

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart
git commit -m "feat(desktop): wire tray, windows and agent runtime in main"
```

---

## Chỉ kiểm được trên Windows (CI `windows-latest` của plan 06)

- `flutter test integration_test -d windows`: `powershell.exe` và `pwsh.exe` (nếu có) in `shellx-ok`; thư mục tạm có dấu (`shellx-thư-mục-…`) qua đường dẫn 8.3; `[Console]::WindowWidth` = 100 sau resize (thứ tự rows/cols của `ResizePseudoConsole`); `taskkill /T /F` giết `ping.exe` con; conhost.exe của PTY đã đóng bị dừng (`consoleHostChildren` không có pid mới); vim của Git for Windows (`C:\Program Files\Git\usr\bin\vim.exe`) nhận `:q!`; output đóng ≤ 2 s sau `exit`.
- Bố cục struct `PROCESSENTRY32W` và `CreateToolhelp32Snapshot`/`Process32FirstW/NextW` (FFI tự khai báo) — được test trên chạy qua gián tiếp.
- `flutter build windows` ra đúng `ShellX.exe`; `Runner.rc`; cửa sổ ẩn lúc khởi động; `SetThreadExecutionState` thật; khóa file bằng `LockFileEx` (test `single_instance_test.dart` chạy trong `flutter test` trên Windows nếu CI chạy unit test ở đó); `launch_at_startup` ghi `HKCU\…\Run\ShellX`; WinToast (`local_notifier.setup`) tạo shortcut Start Menu `ShellX.lnk`; `MessageBox` khi build < 17763 (chỉ đọc code, CI không có Windows cũ).

## Kiểm tra độ phủ spec

| Spec | Task |
|---|---|
| §5.2 đăng nhập/đăng ký (thiết bị agent, hostname), đổi mật khẩu, đăng xuất agent, 4002/401 | 1 (`deviceNameFromHostname`), 7, 10 |
| §5.3 cửa sổ QR, 5 phút / đóng cửa sổ, một mã, thông báo + đóng QR khi ghép xong | 6, 7, 9, 10 |
| §5.5 thu hồi từ tray | 7, 8, 9 |
| §8.1 package | 1 |
| §8.2 lần chạy đầu, onboarding, `LSUIElement`, một bản | 1, 5, 9, 10, 11 |
| §8.3 menu, 3 icon, thông báo phiên mới, tắt truy cập từ xa có hỏi, giữ máy thức, đổi mật khẩu | 5, 7, 8, 9, 10 |
| §8.4 lưu trữ | 4, 6, 7 |
| §8.5 quyền/entitlements | 1 |
| §12 mất kết nối (xám), 4002, 4001 ("Một bản ShellX khác đã kết nối"), 429, cần cập nhật | 7, 8, 10 |
| §13 test PTY thật macOS + Windows, widget test cửa sổ | 3, 10 |
| §14 `/v1/version` lúc khởi động + mỗi 24 giờ, thông báo kèm link | 6, 7 |
