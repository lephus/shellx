# ShellX v1.0 — Plan 05: Mobile app (`apps/mobile`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This plan is part of the ShellX v1.0 plan set: read `docs/superpowers/plans/2026-09-25-shellx-v1-00-overview.md` first — its Global Constraints and interface contracts (§4–§5) are binding here.

**Goal:** Build the ShellX Flutter app for iOS 15+ and Android 8.0 (API 26)+: sign in/up, list the account's computers with live presence, pair by QR, open terminal tabs on a computer (xterm.dart + extra keys bar, copy/paste, pinch zoom, hardware keyboard, reconnect on resume), biometric lock, settings (font size, lock, unpair, sign out, delete account, version).

**Architecture:** A thin Flutter UI over `shellx_core` (REST, relay connection, identity, pairing URI) and `shellx_client` (machine channels, tabs, pairing initiator), consumed **only** through the signatures in overview §5.1–§5.7. Because those classes are `final`, the app talks to them through three small app-side interfaces (`ShellxBackend`, `MachineSession`, `TabHandle`) with one production adapter (`ClientBackend`) and test fakes. State lives in plain `ChangeNotifier` controllers (account, lock, settings, machine list, terminal workspace/tabs) that are unit-tested without widgets; Riverpod provides the app-wide singletons at the root (`ProviderScope` overrides in `main()` and in tests); screens receive their collaborators through constructors.

**Tech Stack:** Flutter 3.41.7 / Dart 3.11.5 (pub workspace member), `xterm` 4.0.0, `mobile_scanner` 7.4.2, `local_auth` 3.0.2, `flutter_secure_storage` 11.2.0, `flutter_riverpod` 3.3.2, `flutter_localizations` + `intl` 0.20.2 (gen-l10n), `package_info_plus` 10.2.1, `device_info_plus` 13.2.0, `shared_preferences` 2.5.5, `url_launcher` 6.3.2; tests: `flutter_test`, `fake_async` 1.3.3, `http` 1.6.0 (`MockClient`). Font: JetBrains Mono 2.304 (SIL OFL 1.1).

**Spec:** `docs/superpowers/specs/2026-09-25-shellx-v1-design.md` (§5.2, §5.3, §5.5, §5.6, §9, §12, §13 mobile parts). **Overview:** `docs/superpowers/plans/2026-09-25-shellx-v1-00-overview.md`.

**Depends on:** plans 02 (`packages/shellx_core`, root workspace) and 03 (`packages/shellx_client`) merged into the branch this plan runs on. Every test in this plan compiles against their real public API; nothing here re-implements protocol, crypto or session logic.

**Working directory:** unless a step says otherwise, run commands from `apps/mobile` (for example `cd apps/mobile && flutter test test/terminal`). Git commands run from the repository root.

---

## Global Constraints

Everything in overview §2 applies (Dart `^3.11.0` / Flutter 3.41, bilingual UI, never log payloads/tokens/passwords, never send application data unencrypted, Conventional Commits with at least one commit per task, …). Plan-specific values, copied from the spec (and the coordinator's amendments) verbatim:

- Platforms: "Mobile app cho iOS 15+ và Android 8.0 (API 26)+." → iOS deployment target **15.0**, Android **minSdk 26**.
- Identity: bundle id / applicationId **`pro.shellx.mobile`**, display name **"ShellX"**.
- Crypto (coordinator ruling, overrides the `cryptography_flutter` entry of spec §9.1): the app does **not** depend on `cryptography_flutter` and never calls `FlutterCryptography.enable()`. `shellx_core` pins the pure-Dart `DartX25519`, `DartChacha20.poly1305Aead`, `DartBlake2s` backends so the vector-tested Noise code runs identically everywhere and failures stay `NoiseException` (native backends would surface `PlatformException`s). Task 1 pins this with a test.
- §5.1: "Khóa bí mật không bao giờ rời thiết bị … Cài lại app sinh khóa mới, nên phải ghép nối lại." → Keychain items use `first_unlock_this_device`; Android backup disabled; a fresh install wipes secure storage.
- §5.2: "Đăng xuất trên mobile: chỉ xóa token. Khóa thiết bị và danh sách máy đã ghim được giữ lại (lưu theo `user_id`) … Tài khoản khác đăng nhập trên cùng điện thoại không thấy dữ liệu đó."
- §5.2 (amended): "Xóa tài khoản … trong Cài đặt của mobile app, người dùng nhập lại mật khẩu để xác nhận." `ShellxApi.deleteAccount(password)` → `DELETE /v1/account`; `401 invalid_credentials` → "Mật khẩu không đúng."; on success delete the token, the device private key and this user's pinned machines, stop `ClientService`, go to the login screen.
- §5.6: "Face ID / vân tay / mã máy qua `local_auth`. Mặc định bật. Yêu cầu mở khóa khi mở app và khi quay lại sau hơn 5 phút ở nền."
- §9.3: "Một hàng cuộn ngang: `Esc` `Tab` `Ctrl` `Alt` `↑` `↓` `←` `→` `|` `~` `/` `-` `Home` `End` `PgUp` `PgDn` `Dán`." and "`Ctrl` và `Alt` là phím dính: chạm một lần áp dụng cho phím kế tiếp; chạm hai lần khóa lại cho tới khi chạm lần nữa."
- §9.4: long-press select + copy; bracketed paste when the application enabled it; pinch to change the font size; rotate/resize → `resize`; hardware keyboards work; channels to every machine with open tabs while in the foreground; on return from background: reconnect, re-handshake, re-attach with `last_seq` (the last two are done by `shellx_client`; the app suspends the backend — `ClientService.stop()` — when paused and resumes it — `ClientService.start()` — when back, or calls `RelayConnection.reconnectNow()` for a relay that is merely `disconnected`).
- §9.5: secure storage holds the device private key, token, `device_id`, pinned machines per `user_id`.
- §12 texts (Vietnamese, verbatim; English equivalents live in `app_en.arb`): "Mất kết nối, đang thử lại…"; "Lần cuối online: …"; "Máy không còn tin cậy điện thoại này. Hãy ghép nối lại."; "Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính."; "Máy này không thuộc tài khoản của bạn. Hãy đăng nhập cùng tài khoản trên máy tính."; "Cần cập nhật app"; "Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên."; `spawn_failed` shows the reason in the tab; 4002 → delete token, back to login; 4001 → no automatic reconnect; HTTP 429 → "Thử lại sau ít phút."; Review Focus 3 → "Phiên đã kết thúc".
- Storage keys: contract-owned `device_private_key` (`DeviceIdentity.storageKey`) and `pinned_machines_<userId>` (`PinnedStore`); plan-owned `auth_token`, `auth_user_id`, `auth_device_id`, `auth_email`, `settings_font_size`, `settings_biometric_lock` (secure storage) and `shellx_installed` (SharedPreferences).
- Contract facts from plans 02/03 (as written): a WebSocket upgrade rejected with 401 also ends in `RelayConnectionState.revoked`; REST 401 for a bad token has code `unauthorized`; the rate limit is recognised by **status 429**; network errors are status 0, code `network`; `ShellxApi.login/register` set `api.token`, `logout()` clears it; `RelayConnection.start()` may be called again after `stop()`/`replaced`/`revoked`, `reconnectNow()` acts only while `disconnected`; `ClientService.start()` loads the pins, subscribes and calls `relay.start()`, `ClientService.stop()` calls `relay.stop()` and may be followed by `start()` again; `MachineClient.connect()` and requests throw `MachineConnectionException(failure)` (plan 03 addition) after moving to `MachineFailed`; `MachineClient` forgets the pin on `untrusted`; re-attaching an existing tab reuses the same `ClientTab` with `last_seq = received`; `ClientTab.events` replays events emitted before its first listener; `closeTab` only sends `session.close` for an attached tab.
- Test command (overview §3): `flutter test` in `apps/mobile`. Never add `test` above 1.30 to this app — Flutter 3.41.7 pins `test_api 0.7.10`, and the whole workspace resolves together.

## Review Focus

Overview lines owned (partly) by this plan, then plan-specific inputs most likely to bite a user. Each line names the test that pins it.

1. **Overview RF 3 (UI):** a tab whose attach fails with `session_not_found` — when picked from the session list or when `shellx_client` re-attaches after a reconnect — shows "Phiên đã kết thúc" and can still be closed. Tests: Task 10 `Review Focus 3: session_not_found while reattaching ends the tab`, Task 12 `Review Focus 3: attach → session_not_found gives a closable "ended" tab`, Task 13 widget test `Review Focus 3: a session that vanished …`.
2. **Overview RF 4 (client side):** a zero-height or zero-width terminal (keyboard sliding, rotation) must never produce a `resize` below 1×1, and opening a session with an unmeasurable viewport uses a sane fallback. Tests: Task 10 `Review Focus 4: a zero-sized viewport is never sent`, Task 11 `Review Focus 4: null when not even one cell fits`, Task 13 `first open … opens a tab automatically` (asserts cols/rows ≥ 1).
3. **Soft keyboard + sticky Ctrl/Alt inside full-screen programs:** tapping `Ctrl` then typing `c` on the iOS/Android keyboard must send `^C`; `Alt` must keep the typed letter's case; arrows must switch to `ESC O A` when vim/htop/less enable DECCKM. xterm.dart 4.0.0 gets DECCKM and Alt/Shift+arrow wrong, so this is fixed and pinned. Tests: Task 7 `arrows follow DECCKM`, `modifier parameter is 1 + shift + 2*alt + 4*ctrl`; Task 9 `soft keyboard: sticky Ctrl turns "c" into ^C`, `soft keyboard: sticky Alt keeps the typed case`.
4. **Hardware keyboard on Android:** `Ctrl+A` (tmux prefix, readline) and `Ctrl+V` (vim block mode) must reach the shell; xterm.dart's default shortcuts would turn them into select-all/paste. Test: Task 7 `Android never captures Ctrl+A or Ctrl+V`.
5. **Multi-line paste:** clipboard text with `\n` or `\r\n` is sent with CR line breaks, wrapped in bracketed-paste markers when the program enabled mode 2004, and never picks up a pending sticky modifier. Test: Task 9 `paste: bracketed when enabled, CR line breaks, never modified`.
6. **Deleting the account:** the relay closes every socket with 4002 as part of the deletion; that must not be shown as "revoked", and another account's pinned machines on the same phone must survive. Tests: Task 5 `the 4002 close that accompanies the deletion is not treated as a revocation`, `success forgets token, device key and this user's pins only`.
7. **Reinstall on iOS:** Keychain survives app deletion; the first launch after a reinstall must start from a clean secure store (new device key, spec §5.1). Test: Task 2 `wipes once on the first launch, then never again`.

## Verified package APIs (checked against the sources in `~/.pub-cache`, Flutter 3.41.7)

| Package | Version | What this plan relies on |
|---|---|---|
| `xterm` | 4.0.0 | `Terminal({maxLines, inputHandler, onOutput, onResize, onTitleChange})`, `write`, `keyInput(TerminalKey, {shift, alt, ctrl})`, `textInput`, `paste` (wraps `ESC[200~…ESC[201~` when `bracketedPasteMode`), `resize` (clamps to ≥1), `cursorKeysMode`, `buffer.getText(range)`; `CascadeInputHandler`, `defaultInputHandler`, `TerminalKeyboardEvent`; `TerminalView(terminal, {controller, textStyle, autofocus, deleteDetection, readOnly, shortcuts})`; `TerminalController.selection/clearSelection`; `TerminalStyle({fontSize, fontFamily})`. `TerminalView` feeds soft-keyboard text as `keyInput(key)` then falls back to `textInput(text)`. RIS (`ESC c`) is **not** supported → a reset swaps in a new `Terminal`. Keytab quirks: app-cursor mode follows DECKPAM instead of DECCKM; Alt/Shift+arrow encoded as Ctrl+arrow; `charInput` has no uppercase Ctrl and sends Alt+letter uppercase. |
| `mobile_scanner` | 7.4.2 | `MobileScanner({controller, onDetect, errorBuilder: (BuildContext, MobileScannerException)})`, `MobileScannerController({formats, detectionSpeed})`, `Barcode.rawValue`, `MobileScannerErrorCode.permissionDenied`. Declares `CAMERA` itself; iOS needs `NSCameraUsageDescription`. |
| `local_auth` | 3.0.2 (android 2.0.8, darwin 2.0.4) | `LocalAuthentication().authenticate({localizedReason, biometricOnly, persistAcrossBackgrounding})`, `isDeviceSupported()`, `LocalAuthException.code` (`LocalAuthExceptionCode.noCredentialsSet`). Android: `FlutterFragmentActivity`, `USE_BIOMETRIC`, AppCompat launch theme on Android 8. iOS: `NSFaceIDUsageDescription`. |
| `flutter_secure_storage` | 11.2.0 | `FlutterSecureStorage({iOptions})`, `read/write/delete/deleteAll`, `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)`, `FlutterSecureStorage.setMockInitialValues`. |
| `cryptography_flutter` | 2.3.4 (checked, **not used**) | It auto-registers native backends through `dartPluginClass: FlutterCryptography` (so merely depending on it switches `Cryptography.instance`), and `FlutterCryptography.enable()` is deprecated. Excluded by the coordinator ruling above. |
| `flutter_riverpod` | 3.3.2 | `Provider`, `ProviderScope(overrides:)`, `overrideWithValue`, `ConsumerWidget`. (3.4.x requires Dart 3.12 and does not resolve.) |
| gen-l10n | Flutter 3.41.7 | With `generate: true` + `l10n.yaml`, files are generated into `lib/l10n/` (no synthetic `flutter_gen` package); import `package:shellx_mobile/l10n/app_localizations.dart`. |
| `package_info_plus` / `device_info_plus` | 10.2.1 / 13.2.0 | `PackageInfo.fromPlatform().version`; `IosDeviceInfo.modelName`, `AndroidDeviceInfo.manufacturer/model`. |
| `shared_preferences` / `url_launcher` | 2.5.5 / 6.3.2 | `SharedPreferences.getInstance/getBool/setBool/setMockInitialValues`; `launchUrl(uri, mode: LaunchMode.externalApplication)`. |

Scratch verification done while writing this plan: the complete app below was built against stubs of the overview §5 signatures (mirroring the plan 02/03 behaviour listed above) — `flutter analyze` clean, 164 tests passing, `flutter build apk --debug` and `flutter build ios --simulator --debug` succeed (merged manifest: `package="pro.shellx.mobile"`, `minSdkVersion="26"`, CAMERA/INTERNET/USE_BIOMETRIC; `Runner.app`: `MinimumOSVersion` 15.0, `CFBundleIdentifier` `pro.shellx.mobile`, display name ShellX). The code blocks of this document were then replayed task by task into a fresh workspace: after every task its tests pass and `flutter analyze` is clean using only the files of that task and the tasks before it.

## File structure

```
apps/mobile/
  pubspec.yaml, l10n.yaml, analysis_options.yaml (from flutter create)
  assets/fonts/JetBrainsMono-{Regular,Bold,Italic,BoldItalic}.ttf, OFL.txt
  android/…  ios/…                          platform config (Task 1)
  lib/
    main.dart                               composition root (Task 18)
    l10n/app_en.arb, app_vi.arb (+ generated app_localizations*.dart)
    app/config.dart                         relay URL, download page, ws URI (Task 2)
    app/providers.dart, shellx_app.dart, phase_router.dart, update_required_screen.dart (Task 18)
    platform/secure_key_value_store.dart, fresh_install.dart, device_description.dart (Task 2)
    settings/app_settings.dart (Task 2), settings_screen.dart, delete_account_screen.dart (Task 15)
    errors/error_text.dart                  spec §12 texts (Task 3)
    machines/last_seen.dart (Task 3), machine_list_controller.dart (Task 16), machine_list_screen.dart (Task 17)
    backend/backend.dart, client_backend.dart   app-side ports + shellx_client adapter (Task 4)
    account/account_store.dart, app_controller.dart (Task 5), login_screen.dart (Task 18)
    lock/biometric_authenticator.dart, app_lock_controller.dart, lock_gate.dart (Task 6)
    terminal/terminal_input.dart, terminal_shortcuts.dart (Task 7)
    terminal/extra_keys_controller.dart (Task 8), shellx_terminal.dart, extra_keys_bar.dart (Task 9)
    terminal/terminal_tab_controller.dart (Task 10), terminal_metrics.dart, pinch_zoom.dart (Task 11)
    terminal/terminal_workspace.dart (Task 12), session_picker.dart, terminal_screen.dart (Task 13)
    widgets/connection_banner.dart (Task 13)
    pairing/pairing_flow.dart, qr_scanner_screen.dart (Task 14)
  test/  (mirrors lib/; support/ holds fakes, the scripted relay HTTP API and widget harness)
```

---

### Task 1: Scaffold `apps/mobile` — workspace member, platform config, font, l10n

**Files:**
- Create (generator): `apps/mobile/**` via `flutter create`
- Modify: `pubspec.yaml` (repository root, one `workspace:` line)
- Create/replace: `apps/mobile/pubspec.yaml`, `apps/mobile/l10n.yaml`, `apps/mobile/lib/l10n/app_en.arb`, `apps/mobile/lib/l10n/app_vi.arb`, `apps/mobile/lib/main.dart`
- Create: `apps/mobile/assets/fonts/JetBrainsMono-{Regular,Bold,Italic,BoldItalic}.ttf`, `apps/mobile/assets/fonts/OFL.txt`
- Modify: `apps/mobile/ios/Podfile`, `apps/mobile/ios/Runner.xcodeproj/project.pbxproj`, `apps/mobile/ios/Runner/Info.plist`, `apps/mobile/android/app/build.gradle.kts`, `apps/mobile/android/app/src/main/AndroidManifest.xml`, `apps/mobile/android/app/src/main/res/values/styles.xml`, `apps/mobile/android/app/src/main/res/values-night/styles.xml`
- Move: `android/app/src/main/kotlin/pro/shellx/shellx_mobile/MainActivity.kt` → `android/app/src/main/kotlin/pro/shellx/mobile/MainActivity.kt`
- Test: `apps/mobile/test/platform_config_test.dart`, `apps/mobile/test/l10n_test.dart`

**Interfaces:**
- Consumes: root `pubspec.yaml` workspace (plan 02); packages `shellx_core`, `shellx_client` (plans 02/03).
- Produces: package `shellx_mobile`; `AppLocalizations` (`package:shellx_mobile/l10n/app_localizations.dart`, `nullable-getter: false`, locales `en`, `vi`, every key of the ARB files below — later tasks use them by name); font family `'JetBrainsMono'`; asset `assets/fonts/OFL.txt`.

- [ ] **Step 1: Generate the project and join the workspace**

From the repository root:

```bash
flutter create --platforms=ios,android --org pro.shellx --project-name shellx_mobile apps/mobile
rm apps/mobile/test/widget_test.dart
rm -rf apps/mobile/pubspec.lock apps/mobile/.dart_tool
```

Add `apps/mobile` to the root `pubspec.yaml` — exactly one line under `workspace:` (keep every line other plans added):

```yaml
workspace:
  # …keep every entry added by the other plans (packages/shellx_core, packages/shellx_agent,
  # packages/shellx_client, packages/shellx_e2e, apps/desktop, …) and add:
  - apps/mobile
```

Replace `apps/mobile/pubspec.yaml` with:

```yaml
name: shellx_mobile
description: ShellX mobile app — control your computer's terminal from your phone.
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
  shellx_client: any
  shellx_core: any
  device_info_plus: ^13.2.0
  flutter_riverpod: ^3.3.2
  flutter_secure_storage: ^11.2.0
  intl: ^0.20.2
  local_auth: ^3.0.2
  mobile_scanner: ^7.4.2
  package_info_plus: ^10.2.1
  shared_preferences: ^2.5.5
  url_launcher: ^6.3.2
  xterm: ^4.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  fake_async: ^1.3.3
  flutter_lints: ^6.0.0
  http: ^1.2.0

flutter:
  uses-material-design: true
  generate: true
  assets:
    - assets/fonts/OFL.txt
  fonts:
    - family: JetBrainsMono
      fonts:
        - asset: assets/fonts/JetBrainsMono-Regular.ttf
        - asset: assets/fonts/JetBrainsMono-Bold.ttf
          weight: 700
        - asset: assets/fonts/JetBrainsMono-Italic.ttf
          style: italic
        - asset: assets/fonts/JetBrainsMono-BoldItalic.ttf
          weight: 700
          style: italic
```

Create `apps/mobile/l10n.yaml`:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false
```

- [ ] **Step 2: Bundle JetBrains Mono (SIL Open Font License 1.1)**

Source: the official JetBrains release `v2.304` (<https://github.com/JetBrains/JetBrainsMono/releases/tag/v2.304>), licence OFL 1.1 (`OFL.txt` in the archive, bundled next to the fonts and registered with `LicenseRegistry` in Task 18).

```bash
cd apps/mobile
mkdir -p assets/fonts
curl -fsSL -o "${TMPDIR:-/tmp}/JetBrainsMono-2.304.zip" \
  https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip
echo "6f6376c6ed2960ea8a963cd7387ec9d76e3f629125bc33d1fdcd7eb7012f7bbf  ${TMPDIR:-/tmp}/JetBrainsMono-2.304.zip" | shasum -a 256 -c -
unzip -o -j "${TMPDIR:-/tmp}/JetBrainsMono-2.304.zip" \
  fonts/ttf/JetBrainsMono-Regular.ttf fonts/ttf/JetBrainsMono-Bold.ttf \
  fonts/ttf/JetBrainsMono-Italic.ttf fonts/ttf/JetBrainsMono-BoldItalic.ttf OFL.txt \
  -d assets/fonts
ls -l assets/fonts
```

Expected: `shasum` prints `OK`; five files (each TTF ≈ 270–280 KB, `OFL.txt` 4399 bytes).

- [ ] **Step 3: Write every user-visible string (Vietnamese + English)**

`apps/mobile/lib/l10n/app_en.arb` (template):

```json
{
  "@@locale": "en",
  "appTitle": "ShellX",
  "actionCancel": "Cancel",
  "actionClose": "Close",
  "loginTitle": "Sign in",
  "registerTitle": "Create account",
  "emailLabel": "Email",
  "passwordLabel": "Password",
  "loginButton": "Sign in",
  "registerButton": "Create account",
  "switchToRegister": "No account yet? Create one",
  "switchToLogin": "Already have an account? Sign in",
  "signedOutRevoked": "Your sign-in was revoked. Please sign in again.",
  "errorInvalidEmail": "Invalid email address.",
  "errorWeakPassword": "Password must be 8–128 characters.",
  "errorDisposableEmail": "Disposable email addresses are not allowed.",
  "errorEmailTaken": "This email is already registered.",
  "errorInvalidCredentials": "Incorrect email or password.",
  "errorRateLimited": "Try again in a few minutes.",
  "errorNetwork": "Can't reach the server. Check your connection and try again.",
  "errorUnknown": "Something went wrong ({code}).",
  "@errorUnknown": {
    "placeholders": {
      "code": {
        "type": "String"
      }
    }
  },
  "errorNotInAccount": "This computer doesn't belong to your account. Sign in with the same account on the computer.",
  "errorQrInvalid": "The QR code is invalid or has expired. Create a new code on your computer.",
  "errorAgentOffline": "The computer is offline. Open ShellX on the computer and try again.",
  "errorTimeout": "The computer didn't respond. Please try again.",
  "errorUntrusted": "This computer no longer trusts this phone. Please pair again.",
  "errorSessionLimit": "This computer already has the maximum of 10 sessions open. Close some sessions first.",
  "errorSpawnFailed": "Couldn't start the shell: {reason}",
  "@errorSpawnFailed": {
    "placeholders": {
      "reason": {
        "type": "String"
      }
    }
  },
  "updateRequiredTitle": "App update required",
  "updateRequiredBody": "This version is no longer supported (minimum {minVersion}). Update ShellX to continue.",
  "@updateRequiredBody": {
    "placeholders": {
      "minVersion": {
        "type": "String"
      }
    }
  },
  "updateRequiredButton": "Get the update",
  "lockTitle": "ShellX is locked",
  "lockUnlockButton": "Unlock",
  "lockReason": "Unlock ShellX",
  "bannerReconnecting": "Connection lost, retrying…",
  "bannerReplaced": "Another instance of the app has connected.",
  "bannerReconnectButton": "Reconnect",
  "machinesTitle": "Computers",
  "machinesEmpty": "No computers yet. Install ShellX on your computer and sign in with the same account.",
  "machineOnline": "Online",
  "machineOffline": "This computer is offline.",
  "machineLastOnline": "Last online: {when}",
  "@machineLastOnline": {
    "placeholders": {
      "when": {
        "type": "String"
      }
    }
  },
  "machineNotPaired": "Not paired",
  "lastSeenJustNow": "just now",
  "lastSeenMinutes": "{count, plural, =1{1 minute ago} other{{count} minutes ago}}",
  "@lastSeenMinutes": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "lastSeenHours": "{count, plural, =1{1 hour ago} other{{count} hours ago}}",
  "@lastSeenHours": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "lastSeenDays": "{count, plural, =1{1 day ago} other{{count} days ago}}",
  "@lastSeenDays": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "lastSeenUnknown": "unknown",
  "scanTooltip": "Scan QR code",
  "settingsTooltip": "Settings",
  "scannerTitle": "Scan pairing code",
  "scannerHint": "On your computer, choose \"Pair phone…\" from the ShellX icon, then scan the QR code.",
  "scannerPairing": "Pairing…",
  "scannerCameraDenied": "Camera access is needed to scan the QR code. Allow it in your phone's Settings.",
  "scannerCameraError": "Couldn't start the camera.",
  "scanAgain": "Scan again",
  "pairingSucceeded": "Paired",
  "sessionEnded": "Session ended",
  "tabExited": "Session ended (exit code {code})",
  "@tabExited": {
    "placeholders": {
      "code": {
        "type": "int"
      }
    }
  },
  "tabTakenOver": "This session was opened on another device.",
  "tabClosedByHost": "The session was closed on the computer.",
  "tabReattach": "Reattach",
  "terminalNewTab": "New session",
  "terminalCloseTab": "Close session",
  "terminalCloseConfirm": "Close this session? Programs running in it will be stopped.",
  "terminalSessionsTooltip": "Sessions on this computer",
  "terminalConnecting": "Connecting to the computer…",
  "terminalNoTabs": "No open sessions.",
  "terminalOpenNew": "Open a new session",
  "copyAction": "Copy",
  "copied": "Copied",
  "keyPaste": "Paste",
  "pickerTitle": "Sessions running on this computer",
  "pickerAttach": "Attach",
  "pickerAttachedElsewhere": "Open on another device",
  "pickerStartedAt": "Started {time}",
  "@pickerStartedAt": {
    "placeholders": {
      "time": {
        "type": "String"
      }
    }
  },
  "settingsTitle": "Settings",
  "settingsAccount": "Account",
  "settingsFontSize": "Default font size",
  "settingsBiometric": "Biometric lock",
  "settingsBiometricSubtitle": "Require Face ID, fingerprint or device passcode to open the app",
  "settingsBiometricUnavailable": "No passcode or biometrics are set up on this device",
  "settingsPairedMachines": "Paired computers",
  "settingsNoPairedMachines": "No paired computers.",
  "settingsUnpair": "Unpair",
  "settingsUnpairConfirm": "Unpair {name}? You'll need to scan a QR code again to use this computer.",
  "@settingsUnpairConfirm": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "settingsLogout": "Sign out",
  "settingsLogoutConfirm": "Sign out of ShellX? Paired computers are kept for your next sign-in.",
  "settingsLicenses": "Open-source licenses",
  "settingsVersion": "Version {version}",
  "@settingsVersion": {
    "placeholders": {
      "version": {
        "type": "String"
      }
    }
  },
  "settingsDeleteAccount": "Delete account",
  "deleteAccountTitle": "Delete account",
  "deleteAccountWarning": "This can't be undone. Your account and all of its devices and pairings will be deleted permanently, and every computer signed in to it will be signed out.",
  "deleteAccountPasswordLabel": "Re-enter your password to confirm",
  "deleteAccountButton": "Delete permanently",
  "errorWrongPassword": "Incorrect password.",
  "signedOutAccountDeleted": "Your account has been deleted.",
  "unknownMachine": "Unknown computer"
}
```

`apps/mobile/lib/l10n/app_vi.arb`:

```json
{
  "@@locale": "vi",
  "appTitle": "ShellX",
  "actionCancel": "Hủy",
  "actionClose": "Đóng",
  "loginTitle": "Đăng nhập",
  "registerTitle": "Đăng ký",
  "emailLabel": "Email",
  "passwordLabel": "Mật khẩu",
  "loginButton": "Đăng nhập",
  "registerButton": "Tạo tài khoản",
  "switchToRegister": "Chưa có tài khoản? Đăng ký",
  "switchToLogin": "Đã có tài khoản? Đăng nhập",
  "signedOutRevoked": "Phiên đăng nhập đã bị thu hồi. Hãy đăng nhập lại.",
  "errorInvalidEmail": "Email không hợp lệ.",
  "errorWeakPassword": "Mật khẩu phải có 8–128 ký tự.",
  "errorDisposableEmail": "Không chấp nhận địa chỉ email tạm thời.",
  "errorEmailTaken": "Email này đã được đăng ký.",
  "errorInvalidCredentials": "Email hoặc mật khẩu không đúng.",
  "errorRateLimited": "Thử lại sau ít phút.",
  "errorNetwork": "Không kết nối được máy chủ. Hãy kiểm tra mạng rồi thử lại.",
  "errorUnknown": "Đã có lỗi xảy ra ({code}).",
  "errorNotInAccount": "Máy này không thuộc tài khoản của bạn. Hãy đăng nhập cùng tài khoản trên máy tính.",
  "errorQrInvalid": "Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính.",
  "errorAgentOffline": "Máy tính đang offline. Hãy mở ShellX trên máy tính rồi thử lại.",
  "errorTimeout": "Máy tính không phản hồi. Hãy thử lại.",
  "errorUntrusted": "Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.",
  "errorSessionLimit": "Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên.",
  "errorSpawnFailed": "Không mở được shell: {reason}",
  "updateRequiredTitle": "Cần cập nhật app",
  "updateRequiredBody": "Phiên bản này không còn được hỗ trợ (tối thiểu {minVersion}). Hãy cập nhật ShellX để tiếp tục.",
  "updateRequiredButton": "Tải bản mới",
  "lockTitle": "ShellX đang khóa",
  "lockUnlockButton": "Mở khóa",
  "lockReason": "Mở khóa ShellX",
  "bannerReconnecting": "Mất kết nối, đang thử lại…",
  "bannerReplaced": "Một phiên bản khác của app đã kết nối.",
  "bannerReconnectButton": "Kết nối lại",
  "machinesTitle": "Máy tính",
  "machinesEmpty": "Chưa có máy tính nào. Cài ShellX trên máy tính và đăng nhập cùng tài khoản.",
  "machineOnline": "Đang online",
  "machineOffline": "Máy đang offline.",
  "machineLastOnline": "Lần cuối online: {when}",
  "machineNotPaired": "Chưa ghép nối",
  "lastSeenJustNow": "vừa xong",
  "lastSeenMinutes": "{count, plural, other{{count} phút trước}}",
  "lastSeenHours": "{count, plural, other{{count} giờ trước}}",
  "lastSeenDays": "{count, plural, other{{count} ngày trước}}",
  "lastSeenUnknown": "không rõ",
  "scanTooltip": "Quét mã QR",
  "settingsTooltip": "Cài đặt",
  "scannerTitle": "Quét mã ghép nối",
  "scannerHint": "Trên máy tính, chọn \"Ghép nối điện thoại…\" ở icon ShellX rồi quét mã QR.",
  "scannerPairing": "Đang ghép nối…",
  "scannerCameraDenied": "Cần quyền camera để quét mã QR. Hãy cho phép trong Cài đặt của điện thoại.",
  "scannerCameraError": "Không mở được camera.",
  "scanAgain": "Quét lại",
  "pairingSucceeded": "Đã ghép nối",
  "sessionEnded": "Phiên đã kết thúc",
  "tabExited": "Phiên đã kết thúc (mã thoát {code})",
  "tabTakenOver": "Phiên đang được mở trên thiết bị khác.",
  "tabClosedByHost": "Phiên đã bị đóng trên máy tính.",
  "tabReattach": "Gắn lại",
  "terminalNewTab": "Phiên mới",
  "terminalCloseTab": "Đóng phiên",
  "terminalCloseConfirm": "Đóng phiên này? Mọi chương trình đang chạy trong phiên sẽ bị dừng.",
  "terminalSessionsTooltip": "Phiên trên máy",
  "terminalConnecting": "Đang kết nối tới máy…",
  "terminalNoTabs": "Chưa có phiên nào đang mở.",
  "terminalOpenNew": "Mở phiên mới",
  "copyAction": "Sao chép",
  "copied": "Đã sao chép",
  "keyPaste": "Dán",
  "pickerTitle": "Phiên đang chạy trên máy",
  "pickerAttach": "Gắn",
  "pickerAttachedElsewhere": "Đang mở trên thiết bị khác",
  "pickerStartedAt": "Mở lúc {time}",
  "settingsTitle": "Cài đặt",
  "settingsAccount": "Tài khoản",
  "settingsFontSize": "Cỡ chữ mặc định",
  "settingsBiometric": "Khóa bằng sinh trắc học",
  "settingsBiometricSubtitle": "Yêu cầu Face ID, vân tay hoặc mã máy khi mở app",
  "settingsBiometricUnavailable": "Thiết bị chưa đặt mã khóa hoặc sinh trắc học",
  "settingsPairedMachines": "Máy đã ghép nối",
  "settingsNoPairedMachines": "Chưa ghép nối máy nào.",
  "settingsUnpair": "Bỏ ghép nối",
  "settingsUnpairConfirm": "Bỏ ghép nối {name}? Bạn sẽ phải quét lại mã QR để dùng máy này.",
  "settingsLogout": "Đăng xuất",
  "settingsLogoutConfirm": "Đăng xuất khỏi ShellX? Các máy đã ghép nối vẫn được giữ cho lần đăng nhập sau.",
  "settingsLicenses": "Giấy phép mã nguồn mở",
  "settingsVersion": "Phiên bản {version}",
  "settingsDeleteAccount": "Xóa tài khoản",
  "deleteAccountTitle": "Xóa tài khoản",
  "deleteAccountWarning": "Thao tác này không thể hoàn tác. Tài khoản của bạn cùng mọi thiết bị và ghép nối sẽ bị xóa vĩnh viễn; mọi máy tính đang đăng nhập tài khoản này sẽ bị đăng xuất.",
  "deleteAccountPasswordLabel": "Nhập lại mật khẩu để xác nhận",
  "deleteAccountButton": "Xóa vĩnh viễn",
  "errorWrongPassword": "Mật khẩu không đúng.",
  "signedOutAccountDeleted": "Tài khoản đã được xóa.",
  "unknownMachine": "Máy không xác định"
}
```

Then resolve and generate (this also creates `ios/Podfile`):

```bash
cd apps/mobile && flutter pub get && flutter gen-l10n
```

Expected: `Got dependencies`; `lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_vi.dart` exist; `ios/Podfile` exists.

- [ ] **Step 4: Write the failing tests**

`apps/mobile/test/platform_config_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// `flutter test` runs with the package root (apps/mobile) as the working directory.
String readFile(String path) => File(path).readAsStringSync();

void main() {
  group('iOS', () {
    test('deployment target is iOS 15.0 everywhere', () {
      final project = readFile('ios/Runner.xcodeproj/project.pbxproj');
      expect(project, contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0;'));
      expect(RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = (?!15\.0;)').hasMatch(project), isFalse);
      expect(readFile('ios/Podfile'), contains("platform :ios, '15.0'"));
    });

    test('bundle identifier is pro.shellx.mobile', () {
      final project = readFile('ios/Runner.xcodeproj/project.pbxproj');
      expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.mobile;'));
      expect(project, isNot(contains('shellxMobile')));
    });

    test('Info.plist declares camera, Face ID, display name and both UI languages', () {
      final plist = readFile('ios/Runner/Info.plist');
      expect(plist, contains('<key>CFBundleDisplayName</key>\n\t<string>ShellX</string>'));
      expect(plist, contains('<key>NSCameraUsageDescription</key>'));
      expect(plist, contains('<key>NSFaceIDUsageDescription</key>'));
      expect(plist, contains('<key>CFBundleLocalizations</key>'));
      expect(plist, contains('<string>vi</string>'));
    });
  });

  group('Android', () {
    test('application id pro.shellx.mobile, minSdk 26 (Android 8.0)', () {
      final gradle = readFile('android/app/build.gradle.kts');
      expect(gradle, contains('applicationId = "pro.shellx.mobile"'));
      expect(gradle, contains('namespace = "pro.shellx.mobile"'));
      expect(gradle, contains('minSdk = 26'));
    });

    test('manifest has the permissions and disables backup', () {
      final manifest = readFile('android/app/src/main/AndroidManifest.xml');
      for (final permission in ['INTERNET', 'CAMERA', 'USE_BIOMETRIC']) {
        expect(manifest, contains('android.permission.$permission'));
      }
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:label="ShellX"'));
    });

    test('MainActivity is a FlutterFragmentActivity with AppCompat themes', () {
      expect(
        readFile('android/app/src/main/kotlin/pro/shellx/mobile/MainActivity.kt'),
        contains('class MainActivity : FlutterFragmentActivity()'),
      );
      expect(readFile('android/app/src/main/res/values/styles.xml'), contains('Theme.AppCompat'));
      expect(readFile('android/app/src/main/res/values-night/styles.xml'), contains('Theme.AppCompat'));
    });
  });

  test('no native crypto plugin: shellx_core pins the pure-Dart backends', () {
    expect(readFile('pubspec.yaml'), isNot(contains('cryptography_flutter')));
  });

  test('JetBrains Mono and its OFL license are bundled', () {
    for (final style in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
      expect(File('assets/fonts/JetBrainsMono-$style.ttf').lengthSync(), greaterThan(100000));
    }
    expect(readFile('assets/fonts/OFL.txt'), contains('SIL OPEN FONT LICENSE'));
  });
}
```

`apps/mobile/test/l10n_test.dart` (guards ARB parity for every later edit; it already passes once Step 3 is done):

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/l10n/app_localizations.dart';

Set<String> messageKeys(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  return json.keys.where((key) => !key.startsWith('@')).toSet();
}

void main() {
  test('Vietnamese and English ARB files define the same messages', () {
    expect(messageKeys('lib/l10n/app_vi.arb'), messageKeys('lib/l10n/app_en.arb'));
  });

  test('both locales are supported and resolve spec texts', () {
    expect(AppLocalizations.supportedLocales, containsAll([const Locale('vi'), const Locale('en')]));
    final vi = lookupAppLocalizations(const Locale('vi'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(vi.bannerReconnecting, 'Mất kết nối, đang thử lại…');
    expect(en.bannerReconnecting, 'Connection lost, retrying…');
    expect(vi.lastSeenMinutes(5), '5 phút trước');
    expect(en.lastSeenMinutes(1), '1 minute ago');
    expect(en.lastSeenMinutes(5), '5 minutes ago');
  });
}
```

- [ ] **Step 5: Run the tests to see the platform checks fail**

Run: `cd apps/mobile && flutter test test/platform_config_test.dart test/l10n_test.dart`
Expected: FAIL — e.g. `Expected: contains 'IPHONEOS_DEPLOYMENT_TARGET = 15.0;'`, `bundle identifier is pro.shellx.mobile` fails, `Expected: contains 'minSdk = 26'`, `MainActivity.kt` not found; `l10n_test.dart` passes.

- [ ] **Step 6: Apply the iOS configuration**

```bash
cd apps/mobile
perl -pi -e "s/^# platform :ios, '13.0'/platform :ios, '15.0'/" ios/Podfile
perl -pi -e 's/IPHONEOS_DEPLOYMENT_TARGET = 13\.0;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/g; s/pro\.shellx\.shellxMobile/pro.shellx.mobile/g' \
  ios/Runner.xcodeproj/project.pbxproj
grep -n "platform :ios" ios/Podfile
grep -c "IPHONEOS_DEPLOYMENT_TARGET = 15.0;" ios/Runner.xcodeproj/project.pbxproj
grep -n "PRODUCT_BUNDLE_IDENTIFIER" ios/Runner.xcodeproj/project.pbxproj
```

Expected: `platform :ios, '15.0'`; count `3`; bundle ids `pro.shellx.mobile` (Runner) and `pro.shellx.mobile.RunnerTests`.

Replace `apps/mobile/ios/Runner/Info.plist` (adds display name, `CFBundleLocalizations`, camera and Face ID usage strings, `https` query scheme for `url_launcher`; keeps the Flutter 3.41 scene manifest):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CADisableMinimumFrameDurationOnPhone</key>
	<true/>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>ShellX</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string>
		<string>vi</string>
	</array>
	<key>CFBundleName</key>
	<string>shellx_mobile</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>$(FLUTTER_BUILD_NUMBER)</string>
	<key>LSApplicationQueriesSchemes</key>
	<array>
		<string>https</string>
	</array>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>NSCameraUsageDescription</key>
	<string>ShellX uses the camera to scan the pairing QR code shown on your computer.</string>
	<key>NSFaceIDUsageDescription</key>
	<string>ShellX uses Face ID to unlock the app.</string>
	<key>UIApplicationSceneManifest</key>
	<dict>
		<key>UIApplicationSupportsMultipleScenes</key>
		<false/>
		<key>UISceneConfigurations</key>
		<dict>
			<key>UIWindowSceneSessionRoleApplication</key>
			<array>
				<dict>
					<key>UISceneClassName</key>
					<string>UIWindowScene</string>
					<key>UISceneConfigurationName</key>
					<string>flutter</string>
					<key>UISceneDelegateClassName</key>
					<string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
					<key>UISceneStoryboardFile</key>
					<string>Main</string>
				</dict>
			</array>
		</dict>
	</dict>
	<key>UIApplicationSupportsIndirectInputEvents</key>
	<true/>
	<key>UILaunchStoryboardName</key>
	<string>LaunchScreen</string>
	<key>UIMainStoryboardFile</key>
	<string>Main</string>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>UISupportedInterfaceOrientations~ipad</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationPortraitUpsideDown</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 7: Apply the Android configuration**

Replace `apps/mobile/android/app/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "pro.shellx.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "pro.shellx.mobile"
        // Spec §3.1: Android 8.0 (API 26)+.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Release signing is configured by the store release process (plan 06).
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // LaunchTheme/NormalTheme use Theme.AppCompat parents: local_auth's BiometricPrompt
    // crashes on Android 8 with a non-AppCompat launch theme.
    implementation("androidx.appcompat:appcompat:1.7.1")
}
```

Replace `apps/mobile/android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>

    <!-- allowBackup=false: secure storage must not be restored onto another install
         (spec §5.1: a reinstall generates a new device key). -->
    <application
        android:label="ShellX"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:allowBackup="false"
        android:fullBackupContent="false">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
    </queries>
</manifest>
```

Move the activity to the new package and make it a `FlutterFragmentActivity` (required by `local_auth`):

```bash
cd apps/mobile
rm -r android/app/src/main/kotlin/pro/shellx/shellx_mobile
mkdir -p android/app/src/main/kotlin/pro/shellx/mobile
```

`apps/mobile/android/app/src/main/kotlin/pro/shellx/mobile/MainActivity.kt`:

```kotlin
package pro.shellx.mobile

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth shows BiometricPrompt, which needs a FragmentActivity.
class MainActivity : FlutterFragmentActivity()
```

Replace `apps/mobile/android/app/src/main/res/values/styles.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- AppCompat parents are required by local_auth (BiometricPrompt) on Android 8. -->
    <style name="LaunchTheme" parent="Theme.AppCompat.Light.NoActionBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>
    <style name="NormalTheme" parent="Theme.AppCompat.Light.NoActionBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

Replace `apps/mobile/android/app/src/main/res/values-night/styles.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- AppCompat parents are required by local_auth (BiometricPrompt) on Android 8. -->
    <style name="LaunchTheme" parent="Theme.AppCompat.NoActionBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>
    <style name="NormalTheme" parent="Theme.AppCompat.NoActionBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

- [ ] **Step 8: Bootstrap `main.dart`**

Replace `apps/mobile/lib/main.dart` (the full composition root arrives in Task 18):

```dart
import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';

// Bootstrap entry point; Task 18 replaces it with the full app wiring.
void main() => runApp(const _BootstrapApp());

class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(body: Center(child: Text(AppLocalizations.of(context).appTitle))),
      ),
    );
  }
}
```

- [ ] **Step 9: Run the tests and the analyzer**

Run: `cd apps/mobile && flutter test test/platform_config_test.dart test/l10n_test.dart && flutter analyze`
Expected: PASS (`All tests passed!`), `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add pubspec.yaml apps/mobile
git commit -m "feat(mobile): scaffold Flutter app with iOS 15/API 26 config, JetBrains Mono and vi/en strings"
```

### Task 2: Platform adapters — secure store, fresh-install wipe, device name, relay URI, settings

**Files:**
- Create: `apps/mobile/lib/app/config.dart`, `apps/mobile/lib/platform/secure_key_value_store.dart`, `apps/mobile/lib/platform/fresh_install.dart`, `apps/mobile/lib/platform/device_description.dart`, `apps/mobile/lib/settings/app_settings.dart`
- Test: `apps/mobile/test/platform/platform_test.dart`, `apps/mobile/test/settings/app_settings_test.dart`

**Interfaces:**
- Consumes: `KeyValueStore`, `InMemoryKeyValueStore`, `DevicePlatform` (overview §5.4–§5.5).
- Produces:
  - `abstract final class AppConfig { static final Uri relayBaseUri; static final Uri downloadPage; }` (`--dart-define=SHELLX_RELAY=…` overrides the relay) and `Uri relayWebSocketUri(Uri base)`.
  - `final class SecureKeyValueStore implements KeyValueStore { SecureKeyValueStore([FlutterSecureStorage? storage]); static const FlutterSecureStorage defaultStorage; Future<void> deleteAll(); }`
  - `const String installMarkerKey = 'shellx_installed';` `Future<void> wipeSecureStorageOnFreshInstall({required SharedPreferences prefs, required Future<void> Function() wipe})`
  - `final class DeviceDescription { const DeviceDescription({required String name, required DevicePlatform platform}); final String name; final DevicePlatform platform; }`, `String formatAndroidModelName(String manufacturer, String model)`, `Future<DeviceDescription> describeThisDevice([DeviceInfoPlugin? plugin])`
  - `final class AppSettings extends ChangeNotifier { AppSettings(KeyValueStore store); static const String fontSizeKey = 'settings_font_size', biometricLockKey = 'settings_biometric_lock'; static const double defaultFontSize = 14, minFontSize = 8, maxFontSize = 32; double get fontSize; bool get biometricLock; static double clampFontSize(double value); Future<void> load(); Future<void> setFontSize(double value); Future<void> setBiometricLock(bool enabled); }`

- [ ] **Step 1: Write the failing tests**

`apps/mobile/test/platform/platform_test.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shellx_mobile/app/config.dart';
import 'package:shellx_mobile/platform/device_description.dart';
import 'package:shellx_mobile/platform/fresh_install.dart';
import 'package:shellx_mobile/platform/secure_key_value_store.dart';

void main() {
  group('SecureKeyValueStore', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('reads, writes and deletes through flutter_secure_storage', () async {
      final store = SecureKeyValueStore();
      expect(await store.read('auth_token'), isNull);
      await store.write('auth_token', 'tok');
      expect(await store.read('auth_token'), 'tok');
      await store.delete('auth_token');
      expect(await store.read('auth_token'), isNull);
    });

    test('deleteAll removes every key', () async {
      final store = SecureKeyValueStore();
      await store.write('a', '1');
      await store.write('b', '2');
      await store.deleteAll();
      expect(await store.read('a'), isNull);
      expect(await store.read('b'), isNull);
    });
  });

  group('wipeSecureStorageOnFreshInstall', () {
    test('wipes once on the first launch, then never again', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var wipes = 0;
      Future<void> wipe() async => wipes++;

      await wipeSecureStorageOnFreshInstall(prefs: prefs, wipe: wipe);
      await wipeSecureStorageOnFreshInstall(prefs: prefs, wipe: wipe);

      expect(wipes, 1);
      expect(prefs.getBool(installMarkerKey), isTrue);
    });
  });

  group('formatAndroidModelName', () {
    test('prefixes the capitalised manufacturer unless the model already has it', () {
      expect(formatAndroidModelName('samsung', 'SM-S911B'), 'Samsung SM-S911B');
      expect(formatAndroidModelName('Google', 'Pixel 8'), 'Google Pixel 8');
      expect(formatAndroidModelName('Xiaomi', 'Xiaomi 13'), 'Xiaomi 13');
      expect(formatAndroidModelName('', 'Nokia G21'), 'Nokia G21');
    });
  });

  group('relayWebSocketUri', () {
    test('maps https to wss and http to ws on /v1/ws', () {
      expect(relayWebSocketUri(Uri.parse('https://relay.shellx.pro')).toString(),
          'wss://relay.shellx.pro/v1/ws');
      expect(relayWebSocketUri(Uri.parse('http://127.0.0.1:8787')).toString(),
          'ws://127.0.0.1:8787/v1/ws');
    });

    test('defaults to the production relay', () {
      expect(AppConfig.relayBaseUri.toString(), 'https://relay.shellx.pro');
    });
  });
}
```

`apps/mobile/test/settings/app_settings_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/settings/app_settings.dart';

void main() {
  test('defaults: font size 14 and biometric lock on (spec §5.6)', () async {
    final settings = AppSettings(InMemoryKeyValueStore());
    await settings.load();
    expect(settings.fontSize, 14);
    expect(settings.biometricLock, isTrue);
  });

  test('persists values and clamps the font size to 8..32', () async {
    final store = InMemoryKeyValueStore();
    final settings = AppSettings(store);
    var notifications = 0;
    settings.addListener(() => notifications++);

    await settings.setFontSize(99);
    await settings.setBiometricLock(false);

    final reloaded = AppSettings(store);
    await reloaded.load();
    expect(reloaded.fontSize, 32);
    expect(reloaded.biometricLock, isFalse);
    expect(notifications, 2);

    await settings.setFontSize(2);
    expect(settings.fontSize, 8);
  });

  test('ignores a corrupt stored font size', () async {
    final store = InMemoryKeyValueStore();
    await store.write(AppSettings.fontSizeKey, 'large');
    final settings = AppSettings(store);
    await settings.load();
    expect(settings.fontSize, AppSettings.defaultFontSize);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/mobile && flutter test test/platform test/settings`
Expected: FAIL — `Error: Error when reading 'lib/app/config.dart': No such file or directory` (and the same for the other new files).

- [ ] **Step 3: Implement**

`apps/mobile/lib/app/config.dart`:

```dart
/// Build-time configuration.
///
/// Point the app at a local relay with
/// `flutter run --dart-define=SHELLX_RELAY=http://127.0.0.1:8787`.
abstract final class AppConfig {
  static final Uri relayBaseUri = Uri.parse(
    const String.fromEnvironment('SHELLX_RELAY', defaultValue: 'https://relay.shellx.pro'),
  );

  /// Landing page with the App Store / Google Play links (spec §11).
  static final Uri downloadPage = Uri.parse('https://shellx.pro/');
}

/// `https://relay.shellx.pro` → `wss://relay.shellx.pro/v1/ws` (spec §6.1).
/// A plain `http` base (local `wrangler dev`) maps to `ws`.
Uri relayWebSocketUri(Uri base) =>
    base.replace(scheme: base.scheme == 'http' ? 'ws' : 'wss', path: '/v1/ws');
```

`apps/mobile/lib/platform/secure_key_value_store.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shellx_core/shellx_core.dart';

/// [KeyValueStore] backed by the iOS Keychain / Android Keystore (spec §5.1, §9.5).
final class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore([FlutterSecureStorage? storage]) : _storage = storage ?? defaultStorage;

  /// `first_unlock_this_device`: Keychain items are never migrated to another
  /// device through a backup — the device private key must not leave the phone.
  static const FlutterSecureStorage defaultStorage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  /// Removes every item this app stored.
  Future<void> deleteAll() => _storage.deleteAll();
}
```

`apps/mobile/lib/platform/fresh_install.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key marking that this install already ran once.
const String installMarkerKey = 'shellx_installed';

/// iOS keeps Keychain items after the app is deleted. Spec §5.1 says a
/// reinstall generates a new device key (and must be paired again), so the
/// first launch of a fresh install wipes secure storage. The marker lives in
/// SharedPreferences, which the OS deletes together with the app.
Future<void> wipeSecureStorageOnFreshInstall({
  required SharedPreferences prefs,
  required Future<void> Function() wipe,
}) async {
  if (prefs.getBool(installMarkerKey) ?? false) return;
  await wipe();
  await prefs.setBool(installMarkerKey, true);
}
```

`apps/mobile/lib/platform/device_description.dart`:

```dart
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shellx_core/shellx_core.dart';

/// What this phone reports as `device.name` / `device.platform` (spec §5.2:
/// the mobile device name is the phone model).
final class DeviceDescription {
  const DeviceDescription({required this.name, required this.platform});

  final String name;
  final DevicePlatform platform;
}

/// "samsung" + "SM-S911B" → "Samsung SM-S911B"; "Xiaomi" + "Xiaomi 13" → "Xiaomi 13".
String formatAndroidModelName(String manufacturer, String model) {
  final maker = manufacturer.trim();
  final name = model.trim();
  if (maker.isEmpty || name.toLowerCase().startsWith(maker.toLowerCase())) return name;
  return '${maker[0].toUpperCase()}${maker.substring(1)} $name';
}

Future<DeviceDescription> describeThisDevice([DeviceInfoPlugin? plugin]) async {
  final info = plugin ?? DeviceInfoPlugin();
  if (Platform.isIOS) {
    final ios = await info.iosInfo;
    return DeviceDescription(name: ios.modelName, platform: DevicePlatform.ios);
  }
  final android = await info.androidInfo;
  return DeviceDescription(
    name: formatAndroidModelName(android.manufacturer, android.model),
    platform: DevicePlatform.android,
  );
}
```

`apps/mobile/lib/settings/app_settings.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:shellx_core/shellx_core.dart';

/// User preferences (spec §9.2 #5). Stored in the same secure store as the
/// account so the app has a single persistence mechanism.
final class AppSettings extends ChangeNotifier {
  AppSettings(this._store);

  static const String fontSizeKey = 'settings_font_size';
  static const String biometricLockKey = 'settings_biometric_lock';
  static const double defaultFontSize = 14;
  static const double minFontSize = 8;
  static const double maxFontSize = 32;

  final KeyValueStore _store;
  double _fontSize = defaultFontSize;
  bool _biometricLock = true;

  double get fontSize => _fontSize;

  /// Spec §5.6: the biometric lock is on by default.
  bool get biometricLock => _biometricLock;

  static double clampFontSize(double value) => value.clamp(minFontSize, maxFontSize).toDouble();

  Future<void> load() async {
    final storedSize = double.tryParse(await _store.read(fontSizeKey) ?? '');
    _fontSize = clampFontSize(storedSize ?? defaultFontSize);
    _biometricLock = await _store.read(biometricLockKey) != 'false';
    notifyListeners();
  }

  Future<void> setFontSize(double value) async {
    _fontSize = clampFontSize(value);
    notifyListeners();
    await _store.write(fontSizeKey, _fontSize.toString());
  }

  Future<void> setBiometricLock(bool enabled) async {
    _biometricLock = enabled;
    notifyListeners();
    await _store.write(biometricLockKey, enabled.toString());
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/platform test/settings`
Expected: PASS — `All tests passed!` (9 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/app/config.dart apps/mobile/lib/platform apps/mobile/lib/settings/app_settings.dart \
  apps/mobile/test/platform apps/mobile/test/settings/app_settings_test.dart
git commit -m "feat(mobile): secure key-value store, fresh-install wipe, device name and settings"
```

---

### Task 3: User-facing error texts (spec §12) and "Lần cuối online" formatting

**Files:**
- Create: `apps/mobile/lib/errors/error_text.dart`, `apps/mobile/lib/machines/last_seen.dart`
- Test: `apps/mobile/test/errors/error_text_test.dart`, `apps/mobile/test/machines/last_seen_test.dart`

**Interfaces:**
- Consumes: `ApiException`, `AppErrorCode` (`shellx_core`); `PairingException`, `PairingFailure`, `AppErrorException`, `MachineFailed`, `MachineConnectionFailure`, `MachineConnectionException` (`shellx_client`; the last one is plan 03's addition to overview §5.7); `AppLocalizations` (Task 1).
- Produces: `final class ErrorText { const ErrorText(AppLocalizations l10n); String describe(Object error); String api(ApiException error); String pairing(PairingFailure failure); String machine(MachineConnectionFailure failure); String appError(AppErrorCode code, String message); }` and `String formatLastSeen(AppLocalizations l10n, DateTime? lastSeen, DateTime now)`.

Notes: HTTP 429 is recognised by `status`, never by code (plan 02 fact). `PairingFailure.invalidOrExpired` uses the fuller §12 text (the §5.3 text is its first sentence). `unauthorized` (bad/expired token on REST) reuses the "sign-in revoked" text.

- [ ] **Step 1: Write the failing tests**

`apps/mobile/test/errors/error_text_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/errors/error_text.dart';
import 'package:shellx_mobile/l10n/app_localizations.dart';

void main() {
  final vi = ErrorText(lookupAppLocalizations(const Locale('vi')));
  final en = ErrorText(lookupAppLocalizations(const Locale('en')));

  ApiException apiError(int status, String code) =>
      ApiException(status: status, code: code, message: code);

  test('spec §5.3/§12 pairing texts, verbatim', () {
    expect(vi.pairing(PairingFailure.notInAccount),
        'Máy này không thuộc tài khoản của bạn. Hãy đăng nhập cùng tài khoản trên máy tính.');
    expect(vi.pairing(PairingFailure.invalidOrExpired),
        'Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính.');
    expect(vi.pairing(PairingFailure.protocolUnsupported), 'Cần cập nhật app');
    expect(en.pairing(PairingFailure.invalidOrExpired),
        'The QR code is invalid or has expired. Create a new code on your computer.');
  });

  test('spec §12 machine connection texts', () {
    expect(vi.machine(MachineConnectionFailure.untrusted),
        'Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.');
    expect(vi.machine(MachineConnectionFailure.protocolUnsupported), 'Cần cập nhật app');
    expect(vi.machine(MachineConnectionFailure.agentOffline), 'Máy đang offline.');
    expect(en.machine(MachineConnectionFailure.untrusted),
        'This computer no longer trusts this phone. Please pair again.');
  });

  test('spec §12 session errors; spawn_failed shows the reason', () {
    expect(vi.appError(AppErrorCode.sessionLimit, 'x'),
        'Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên.');
    expect(vi.appError(AppErrorCode.sessionNotFound, 'x'), 'Phiên đã kết thúc');
    expect(vi.appError(AppErrorCode.spawnFailed, 'pwsh.exe not found'),
        'Không mở được shell: pwsh.exe not found');
    expect(en.appError(AppErrorCode.sessionNotFound, 'x'), 'Session ended');
  });

  test('HTTP 429 always maps to "Thử lại sau ít phút."', () {
    expect(vi.api(apiError(429, 'rate_limited')), 'Thử lại sau ít phút.');
    expect(vi.api(apiError(429, 'anything')), 'Thử lại sau ít phút.');
    expect(en.api(apiError(429, 'rate_limited')), 'Try again in a few minutes.');
  });

  test('account error codes of spec §10.2', () {
    expect(vi.api(apiError(401, 'invalid_credentials')), 'Email hoặc mật khẩu không đúng.');
    expect(vi.api(apiError(409, 'email_taken')), 'Email này đã được đăng ký.');
    expect(vi.api(apiError(400, 'invalid_email')), 'Email không hợp lệ.');
    expect(vi.api(apiError(400, 'disposable_email')), 'Không chấp nhận địa chỉ email tạm thời.');
    expect(vi.api(apiError(400, 'weak_password')), 'Mật khẩu phải có 8–128 ký tự.');
    expect(vi.api(apiError(0, 'network')),
        'Không kết nối được máy chủ. Hãy kiểm tra mạng rồi thử lại.');
    expect(vi.api(apiError(401, 'unauthorized')), 'Phiên đăng nhập đã bị thu hồi. Hãy đăng nhập lại.');
    expect(vi.api(apiError(500, 'internal')), 'Đã có lỗi xảy ra (internal).');
  });

  test('describe dispatches on the error type', () {
    expect(vi.describe(const PairingException(PairingFailure.timeout)),
        'Máy tính không phản hồi. Hãy thử lại.');
    expect(vi.describe(const AppErrorException(AppErrorCode.sessionLimit, 'limit')),
        'Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên.');
    expect(vi.describe(const MachineFailed(MachineConnectionFailure.untrusted)),
        'Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.');
    expect(vi.describe(const MachineConnectionException(MachineConnectionFailure.agentOffline)),
        'Máy đang offline.');
    expect(vi.describe(StateError('boom')), 'Đã có lỗi xảy ra (StateError).');
  });
}
```

`apps/mobile/test/machines/last_seen_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/l10n/app_localizations.dart';
import 'package:shellx_mobile/machines/last_seen.dart';

void main() {
  final vi = lookupAppLocalizations(const Locale('vi'));
  final en = lookupAppLocalizations(const Locale('en'));
  final now = DateTime(2026, 9, 25, 12);

  test('relative Vietnamese and English texts', () {
    expect(formatLastSeen(vi, null, now), 'không rõ');
    expect(formatLastSeen(vi, now.subtract(const Duration(seconds: 30)), now), 'vừa xong');
    expect(formatLastSeen(vi, now.subtract(const Duration(minutes: 5)), now), '5 phút trước');
    expect(formatLastSeen(vi, now.subtract(const Duration(hours: 3)), now), '3 giờ trước');
    expect(formatLastSeen(vi, now.subtract(const Duration(days: 2)), now), '2 ngày trước');
    expect(formatLastSeen(en, now.subtract(const Duration(hours: 1)), now), '1 hour ago');
    expect(formatLastSeen(en, now.subtract(const Duration(days: 4)), now), '4 days ago');
  });

  test('a timestamp in the future (clock skew) reads as "just now"', () {
    expect(formatLastSeen(en, now.add(const Duration(minutes: 3)), now), 'just now');
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/mobile && flutter test test/errors test/machines/last_seen_test.dart`
Expected: FAIL — `Error when reading 'lib/errors/error_text.dart': No such file or directory`, `Error when reading 'lib/machines/last_seen.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/mobile/lib/errors/error_text.dart`:

```dart
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';

import '../l10n/app_localizations.dart';

/// Turns contract exceptions and failure codes into the user-facing texts of
/// spec §12 (Vietnamese) and their English equivalents.
final class ErrorText {
  const ErrorText(this.l10n);

  final AppLocalizations l10n;

  String describe(Object error) => switch (error) {
    ApiException() => api(error),
    PairingException(:final failure) => pairing(failure),
    AppErrorException(:final code, :final message) => appError(code, message),
    MachineFailed(:final failure) => machine(failure),
    MachineConnectionException(:final failure) => machine(failure),
    _ => l10n.errorUnknown(error.runtimeType.toString()),
  };

  String api(ApiException error) {
    if (error.status == 429) return l10n.errorRateLimited;
    return switch (error.code) {
      'network' => l10n.errorNetwork,
      'unauthorized' => l10n.signedOutRevoked,
      'invalid_email' => l10n.errorInvalidEmail,
      'disposable_email' => l10n.errorDisposableEmail,
      'weak_password' => l10n.errorWeakPassword,
      'email_taken' => l10n.errorEmailTaken,
      'invalid_credentials' => l10n.errorInvalidCredentials,
      _ => l10n.errorUnknown(error.code),
    };
  }

  String pairing(PairingFailure failure) => switch (failure) {
    PairingFailure.notInAccount => l10n.errorNotInAccount,
    PairingFailure.invalidOrExpired => l10n.errorQrInvalid,
    PairingFailure.agentOffline => l10n.errorAgentOffline,
    PairingFailure.protocolUnsupported => l10n.updateRequiredTitle,
    PairingFailure.timeout => l10n.errorTimeout,
  };

  String machine(MachineConnectionFailure failure) => switch (failure) {
    MachineConnectionFailure.untrusted => l10n.errorUntrusted,
    MachineConnectionFailure.protocolUnsupported => l10n.updateRequiredTitle,
    MachineConnectionFailure.agentOffline => l10n.machineOffline,
    MachineConnectionFailure.timeout => l10n.errorTimeout,
  };

  String appError(AppErrorCode code, String message) => switch (code) {
    AppErrorCode.sessionLimit => l10n.errorSessionLimit,
    AppErrorCode.sessionNotFound => l10n.sessionEnded,
    AppErrorCode.spawnFailed => l10n.errorSpawnFailed(message),
  };
}
```

`apps/mobile/lib/machines/last_seen.dart`:

```dart
import '../l10n/app_localizations.dart';

/// The `…` of "Lần cuối online: …" (spec §9.2 #2, §12).
String formatLastSeen(AppLocalizations l10n, DateTime? lastSeen, DateTime now) {
  if (lastSeen == null) return l10n.lastSeenUnknown;
  final elapsed = now.difference(lastSeen);
  if (elapsed.inMinutes < 1) return l10n.lastSeenJustNow;
  if (elapsed.inHours < 1) return l10n.lastSeenMinutes(elapsed.inMinutes);
  if (elapsed.inDays < 1) return l10n.lastSeenHours(elapsed.inHours);
  return l10n.lastSeenDays(elapsed.inDays);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/errors test/machines/last_seen_test.dart`
Expected: PASS — `All tests passed!` (8 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/errors apps/mobile/lib/machines/last_seen.dart apps/mobile/test/errors apps/mobile/test/machines/last_seen_test.dart
git commit -m "feat(mobile): localized spec §12 error texts and last-online formatting"
```

---

### Task 4: Backend ports and the `shellx_client` adapter

**Files:**
- Create: `apps/mobile/lib/backend/backend.dart`, `apps/mobile/lib/backend/client_backend.dart`, `apps/mobile/test/support/fakes.dart`
- Test: `apps/mobile/test/backend/client_backend_test.dart`

**Interfaces:**
- Consumes (overview §5.5/§5.7, exact): `RelayConnection({required Uri wsUri, required String? Function() token, RelaySocketConnector connector})`, `.state`, `.states`, `.reconnectNow()`; `ShellxApi.token`, `.devices()`; `PinnedStore(KeyValueStore, {required String userId})`, `.list()`; `ClientService({relay, api, deviceId, userId, identity, pinned, appVersion, deviceName, platform})`, `.start()`, `.stop()`, `.isOnline()`, `.presence`, `.pair()`, `.machine()`, `.unpair()`; `MachineClient` and `ClientTab` members; `relayWebSocketUri` and `DeviceDescription` (Task 2).
- Produces (used by every later task):
  - `abstract interface class TabHandle { int get id; int get index; String get shell; bool get isAttached; Stream<TabEvent> get events; }`
  - `abstract interface class MachineSession { String get agentId; MachineConnectionState get state; Stream<MachineConnectionState> get states; Future<void> connect(); Future<List<SessionInfo>> listSessions(); Future<TabHandle> openSession({required int cols, required int rows}); Future<TabHandle> attach(int id, {required int cols, required int rows}); List<TabHandle> get tabs; void input(int id, Uint8List data); void resize(int id, int cols, int rows); Future<void> closeTab(int id); }`
  - `abstract interface class ShellxBackend { RelayConnectionState get relayState; Stream<RelayConnectionState> get relayStates; void reconnectNow(); Future<void> suspend(); Future<void> resume(); Future<List<RemoteDevice>> devices(); bool isOnline(String agentId); Stream<PresenceFrame> get presence; Future<List<PinnedMachine>> pinnedMachines(); Future<void> pair(PairingUri uri); MachineSession machine(String agentId); Future<void> unpair(String agentId); Future<void> dispose(); }`
  - `final class ClientBackend implements ShellxBackend { static Future<ClientBackend> start({required Uri relayBaseUri, required ShellxApi api, required String userId, required String deviceId, required NoiseKeyPair identity, required KeyValueStore store, required String appVersion, required DeviceDescription device, RelaySocketConnector connector = ioRelaySocketConnector}); }`
  - Test support (`test/support/fakes.dart`): `agentA`, `agentB`, `agentDevice(...)`, `pinned(...)`, `FakeTabHandle` (`emit`), `FakeMachineSession` (scriptable connect/list/open/attach errors, `attachHook`, `reuseHandles`, records inputs/resizes/closes), `FakeBackend` (`emitRelay`, `emitPresence`, `addMachine`, records `paired`/`unpaired`/`reconnectCalls`/`suspendCalls`/`resumeCalls`/`disposed`).

Why the ports: `ClientService`, `MachineClient` and `ClientTab` are `final` classes, so tests cannot implement them; the UI depends on these interfaces and `ClientBackend` is the only place that touches `shellx_client`. Lifecycle (plan 03): `ClientService.start()` subscribes and starts the relay, `stop()` stops it, and `start()` may run again — so `suspend()` = `client.stop()`, `resume()` = `client.start()` (machines and tabs survive; `shellx_client` re-handshakes and re-attaches on reconnect), `dispose()` = `client.stop()`. The adapter never calls `relay.start()`/`stop()` itself.

- [ ] **Step 1: Write the test fakes**

`apps/mobile/test/support/fakes.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/backend/backend.dart';

const String agentA = '11111111-1111-4111-8111-111111111111';
const String agentB = '22222222-2222-4222-8222-222222222222';

RemoteDevice agentDevice(
  String id,
  String name, {
  bool online = true,
  DateTime? lastSeenAt,
  DevicePlatform platform = DevicePlatform.macos,
}) =>
    RemoteDevice(
      id: id,
      kind: DeviceKind.agent,
      name: name,
      platform: platform,
      online: online,
      lastSeenAt: lastSeenAt,
      pairedWithMe: false,
    );

PinnedMachine pinned(String agentId) =>
    PinnedMachine(agentId: agentId, publicKey: Uint8List(32), pairedAt: DateTime(2026, 9, 25));

class FakeTabHandle implements TabHandle {
  FakeTabHandle({required this.id, required this.index, this.shell = 'zsh'});

  @override
  final int id;
  @override
  final int index;
  @override
  final String shell;
  bool attached = true;
  final StreamController<TabEvent> _events = StreamController<TabEvent>.broadcast(sync: true);

  void emit(TabEvent event) {
    if (event is TabExited || event is TabDetached) attached = false;
    _events.add(event);
  }

  @override
  bool get isAttached => attached;

  @override
  Stream<TabEvent> get events => _events.stream;
}

class FakeMachineSession implements MachineSession {
  FakeMachineSession(this.agentId);

  @override
  final String agentId;
  MachineConnectionState stateValue = const MachineIdle();
  final StreamController<MachineConnectionState> _states =
      StreamController<MachineConnectionState>.broadcast(sync: true);
  MachineConnectionFailure? connectFailure;
  int connectCalls = 0;
  List<SessionInfo> sessions = [];
  int listCalls = 0;
  Object? openError;
  final Map<int, Object> attachErrors = {};
  final List<FakeTabHandle> handles = [];
  final List<({int cols, int rows})> opened = [];
  final List<({int id, int cols, int rows})> attached = [];
  final List<({int id, Uint8List data})> inputs = [];
  final List<({int id, int cols, int rows})> resizes = [];
  final List<int> closed = [];

  /// Called inside [attach] before it returns (simulates catch-up output).
  void Function(int id)? attachHook;

  /// Like shellx_client: re-attaching an existing tab returns the same handle.
  bool reuseHandles = false;
  int _nextId = 1;

  void _setState(MachineConnectionState state) {
    stateValue = state;
    _states.add(state);
  }

  @override
  MachineConnectionState get state => stateValue;

  @override
  Stream<MachineConnectionState> get states => _states.stream;

  @override
  Future<void> connect() async {
    connectCalls++;
    final failure = connectFailure;
    if (failure != null) {
      final failed = MachineFailed(failure);
      _setState(failed);
      throw failed;
    }
    _setState(const MachineReady());
  }

  @override
  Future<List<SessionInfo>> listSessions() async {
    listCalls++;
    return sessions;
  }

  @override
  Future<TabHandle> openSession({required int cols, required int rows}) async {
    opened.add((cols: cols, rows: rows));
    final error = openError;
    if (error != null) throw error;
    final id = _nextId++;
    final handle = FakeTabHandle(id: 100 + id, index: id);
    handles.add(handle);
    return handle;
  }

  @override
  Future<TabHandle> attach(int id, {required int cols, required int rows}) async {
    attached.add((id: id, cols: cols, rows: rows));
    final error = attachErrors[id];
    if (error != null) throw error;
    attachHook?.call(id);
    final existing = handles.where((h) => h.id == id).firstOrNull;
    if (reuseHandles && existing != null) {
      existing.attached = true;
      return existing;
    }
    final info = sessions.where((s) => s.id == id).firstOrNull;
    final handle = FakeTabHandle(id: id, index: info?.index ?? id, shell: info?.shell ?? 'zsh');
    handles
      ..removeWhere((h) => h.id == id)
      ..add(handle);
    return handle;
  }

  @override
  List<TabHandle> get tabs => List<TabHandle>.of(handles);

  @override
  void input(int id, Uint8List data) => inputs.add((id: id, data: data));

  @override
  void resize(int id, int cols, int rows) => resizes.add((id: id, cols: cols, rows: rows));

  @override
  Future<void> closeTab(int id) async {
    closed.add(id);
    handles.removeWhere((h) => h.id == id);
  }

  FakeTabHandle handle(int id) => handles.firstWhere((h) => h.id == id);
}

class FakeBackend implements ShellxBackend {
  FakeBackend({List<RemoteDevice>? devices, List<PinnedMachine>? pinnedList})
      : deviceList = devices ?? [],
        pinnedList = pinnedList ?? [];

  List<RemoteDevice> deviceList;
  List<PinnedMachine> pinnedList;
  Object? devicesError;
  final Set<String> onlineIds = {};
  RelayConnectionState relayStateValue = RelayConnectionState.connected;
  final StreamController<RelayConnectionState> _relay =
      StreamController<RelayConnectionState>.broadcast(sync: true);
  final StreamController<PresenceFrame> _presence =
      StreamController<PresenceFrame>.broadcast(sync: true);
  final Map<String, FakeMachineSession> machines = {};
  Object? pairError;
  final List<PairingUri> paired = [];
  final List<String> unpaired = [];
  int reconnectCalls = 0;
  int suspendCalls = 0;
  int resumeCalls = 0;
  bool disposed = false;

  void emitRelay(RelayConnectionState state) {
    relayStateValue = state;
    _relay.add(state);
  }

  void emitPresence(String deviceId, {required bool online}) {
    online ? onlineIds.add(deviceId) : onlineIds.remove(deviceId);
    _presence.add(PresenceFrame(deviceId: deviceId, online: online));
  }

  FakeMachineSession addMachine(String agentId) =>
      machines.putIfAbsent(agentId, () => FakeMachineSession(agentId));

  @override
  RelayConnectionState get relayState => relayStateValue;

  @override
  Stream<RelayConnectionState> get relayStates => _relay.stream;

  @override
  void reconnectNow() => reconnectCalls++;

  @override
  Future<void> suspend() async {
    suspendCalls++;
    emitRelay(RelayConnectionState.stopped);
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    emitRelay(RelayConnectionState.connected);
  }

  @override
  Future<List<RemoteDevice>> devices() async {
    final error = devicesError;
    if (error != null) throw error;
    return deviceList;
  }

  @override
  bool isOnline(String agentId) => onlineIds.contains(agentId);

  @override
  Stream<PresenceFrame> get presence => _presence.stream;

  @override
  Future<List<PinnedMachine>> pinnedMachines() async => pinnedList;

  @override
  Future<void> pair(PairingUri uri) async {
    final error = pairError;
    if (error != null) throw error;
    paired.add(uri);
    pinnedList = [...pinnedList, pinned(uri.agentDeviceId)];
    addMachine(uri.agentDeviceId);
  }

  @override
  MachineSession machine(String agentId) =>
      machines[agentId] ?? (throw StateError('not pinned: $agentId'));

  @override
  Future<void> unpair(String agentId) async {
    unpaired.add(agentId);
    pinnedList = pinnedList.where((m) => m.agentId != agentId).toList();
    machines.remove(agentId);
  }

  @override
  Future<void> dispose() async => disposed = true;
}
```

- [ ] **Step 2: Write the failing test**

`apps/mobile/test/backend/client_backend_test.dart` (uses the real `shellx_core`/`shellx_client` classes; the socket connector fails so no network is touched):

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/backend/client_backend.dart';
import 'package:shellx_mobile/platform/device_description.dart';

import '../support/fakes.dart';

void main() {
  test('wires the per-user PinnedStore; suspend/resume/dispose drive the relay', () async {
    final store = InMemoryKeyValueStore();
    await PinnedStore(store, userId: 'user-1').add(
      PinnedMachine(agentId: agentA, publicKey: Uint8List(32), pairedAt: DateTime(2026, 9, 25)),
    );
    await PinnedStore(store, userId: 'user-2').add(
      PinnedMachine(agentId: agentB, publicKey: Uint8List(32), pairedAt: DateTime(2026, 9, 25)),
    );
    final api = ShellxApi(
      baseUri: Uri.parse('http://127.0.0.1:8787'),
      httpClient: MockClient((request) async => http.Response('[]', 200)),
    )..token = 'token-1';

    final backend = await ClientBackend.start(
      relayBaseUri: Uri.parse('http://127.0.0.1:8787'),
      api: api,
      userId: 'user-1',
      deviceId: '33333333-3333-4333-8333-333333333333',
      identity: await NoiseKeyPair.generate(),
      store: store,
      appVersion: '1.0.0',
      device: const DeviceDescription(name: 'iPhone 15', platform: DevicePlatform.ios),
      connector: (uri, headers) async => throw const SocketException('offline in tests'),
    );

    expect((await backend.pinnedMachines()).map((m) => m.agentId), [agentA]);
    expect(() => backend.machine('44444444-4444-4444-8444-444444444444'), throwsStateError);
    expect(backend.relayState, isNot(RelayConnectionState.stopped)); // ClientService.start() started it

    await backend.suspend();
    expect(backend.relayState, RelayConnectionState.stopped);
    await backend.resume();
    await pumpEventQueue();
    expect(backend.relayState, isNot(RelayConnectionState.stopped));

    await backend.dispose();
    expect(backend.relayState, RelayConnectionState.stopped);
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd apps/mobile && flutter test test/backend`
Expected: FAIL — `Error when reading 'lib/backend/client_backend.dart': No such file or directory` (and `lib/backend/backend.dart` for `fakes.dart`).

- [ ] **Step 4: Implement**

`apps/mobile/lib/backend/backend.dart`:

```dart
import 'dart:typed_data';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';

/// App-side view of one terminal tab ([ClientTab] in `shellx_client`).
///
/// `shellx_client` types are `final`, so the UI depends on these interfaces
/// and tests substitute fakes; [ClientBackend] adapts the real classes.
abstract interface class TabHandle {
  int get id;
  int get index;
  String get shell;
  bool get isAttached;
  Stream<TabEvent> get events;
}

/// App-side view of the encrypted channel to one machine ([MachineClient]).
abstract interface class MachineSession {
  String get agentId;
  MachineConnectionState get state;
  Stream<MachineConnectionState> get states;
  Future<void> connect();
  Future<List<SessionInfo>> listSessions();
  Future<TabHandle> openSession({required int cols, required int rows});
  Future<TabHandle> attach(int id, {required int cols, required int rows});
  List<TabHandle> get tabs;
  void input(int id, Uint8List data);
  void resize(int id, int cols, int rows);
  Future<void> closeTab(int id);
}

/// Everything the signed-in UI needs from `shellx_core` + `shellx_client`.
abstract interface class ShellxBackend {
  RelayConnectionState get relayState;
  Stream<RelayConnectionState> get relayStates;

  /// Skip the reconnect backoff (`RelayConnection.reconnectNow`, effective
  /// only while `disconnected`).
  void reconnectNow();

  /// App went to the background: drop the relay connection and every machine
  /// channel (spec §12: the phone only retries while in the foreground).
  Future<void> suspend();

  /// App is back: reconnect; `shellx_client` re-handshakes and re-attaches
  /// every attached tab with `last_seq` (spec §9.4).
  Future<void> resume();

  /// `GET /v1/devices` (spec §10.2).
  Future<List<RemoteDevice>> devices();

  /// Presence as last reported by the hub (spec §6.2 PRESENCE).
  bool isOnline(String agentId);
  Stream<PresenceFrame> get presence;

  /// Machines pinned for the signed-in user (spec §5.3 step 6).
  Future<List<PinnedMachine>> pinnedMachines();

  /// Pairing initiator (spec §5.3); throws [PairingException].
  Future<void> pair(PairingUri uri);

  /// Throws [StateError] when [agentId] is not pinned.
  MachineSession machine(String agentId);

  /// Spec §5.5: drop the pinned key and delete the pairing record.
  Future<void> unpair(String agentId);

  /// Stops the client and the relay connection for good (sign-out).
  Future<void> dispose();
}
```

`apps/mobile/lib/backend/client_backend.dart`:

```dart
import 'dart:typed_data';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';

import '../app/config.dart';
import '../platform/device_description.dart';
import 'backend.dart';

/// Production [ShellxBackend]: one [RelayConnection] + one [ClientService]
/// per signed-in account.
final class ClientBackend implements ShellxBackend {
  ClientBackend._(this._relay, this._api, this._client, this._pinned);

  final RelayConnection _relay;
  final ShellxApi _api;
  final ClientService _client;
  final PinnedStore _pinned;
  final Map<String, _MachineSessionAdapter> _machines = {};

  /// Builds the relay connection and client for a signed-in account and
  /// starts the client (plan 03: `ClientService.start()` loads the pins,
  /// subscribes and calls `relay.start()`; `stop()` calls `relay.stop()`).
  static Future<ClientBackend> start({
    required Uri relayBaseUri,
    required ShellxApi api,
    required String userId,
    required String deviceId,
    required NoiseKeyPair identity,
    required KeyValueStore store,
    required String appVersion,
    required DeviceDescription device,
    RelaySocketConnector connector = ioRelaySocketConnector,
  }) async {
    final relay = RelayConnection(
      wsUri: relayWebSocketUri(relayBaseUri),
      token: () => api.token,
      connector: connector,
    );
    final pinned = PinnedStore(store, userId: userId);
    final client = ClientService(
      relay: relay,
      api: api,
      deviceId: deviceId,
      userId: userId,
      identity: identity,
      pinned: pinned,
      appVersion: appVersion,
      deviceName: device.name,
      platform: device.platform,
    );
    await client.start();
    return ClientBackend._(relay, api, client, pinned);
  }

  @override
  RelayConnectionState get relayState => _relay.state;

  @override
  Stream<RelayConnectionState> get relayStates => _relay.states;

  @override
  void reconnectNow() => _relay.reconnectNow();

  @override
  Future<void> suspend() => _client.stop();

  /// `ClientService.start()` may run again after `stop()`; it restarts the
  /// relay (allowed after stopped/replaced, plan 02).
  @override
  Future<void> resume() => _client.start();

  @override
  Future<List<RemoteDevice>> devices() => _api.devices();

  @override
  bool isOnline(String agentId) => _client.isOnline(agentId);

  @override
  Stream<PresenceFrame> get presence => _client.presence;

  @override
  Future<List<PinnedMachine>> pinnedMachines() => _pinned.list();

  @override
  Future<void> pair(PairingUri uri) => _client.pair(uri);

  @override
  MachineSession machine(String agentId) =>
      _machines.putIfAbsent(agentId, () => _MachineSessionAdapter(_client.machine(agentId)));

  @override
  Future<void> unpair(String agentId) async {
    await _client.unpair(agentId);
    _machines.remove(agentId);
  }

  @override
  Future<void> dispose() => _client.stop();
}

final class _MachineSessionAdapter implements MachineSession {
  _MachineSessionAdapter(this._client);

  final MachineClient _client;
  final Map<ClientTab, _TabAdapter> _tabs = Map.identity();

  TabHandle _wrap(ClientTab tab) => _tabs.putIfAbsent(tab, () => _TabAdapter(tab));

  @override
  String get agentId => _client.agentId;

  @override
  MachineConnectionState get state => _client.state;

  @override
  Stream<MachineConnectionState> get states => _client.states;

  @override
  Future<void> connect() => _client.connect();

  @override
  Future<List<SessionInfo>> listSessions() => _client.listSessions();

  @override
  Future<TabHandle> openSession({required int cols, required int rows}) async =>
      _wrap(await _client.openSession(cols: cols, rows: rows));

  @override
  Future<TabHandle> attach(int id, {required int cols, required int rows}) async =>
      _wrap(await _client.attach(id, cols: cols, rows: rows));

  @override
  List<TabHandle> get tabs => [for (final tab in _client.tabs) _wrap(tab)];

  @override
  void input(int id, Uint8List data) => _client.input(id, data);

  @override
  void resize(int id, int cols, int rows) => _client.resize(id, cols, rows);

  @override
  Future<void> closeTab(int id) async {
    await _client.closeTab(id);
    _tabs.removeWhere((tab, _) => tab.id == id);
  }
}

final class _TabAdapter implements TabHandle {
  _TabAdapter(this._tab);

  final ClientTab _tab;

  @override
  int get id => _tab.id;

  @override
  int get index => _tab.index;

  @override
  String get shell => _tab.shell;

  @override
  bool get isAttached => _tab.isAttached;

  @override
  Stream<TabEvent> get events => _tab.events;
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/backend && flutter analyze`
Expected: PASS — `All tests passed!`; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/backend apps/mobile/test/backend apps/mobile/test/support/fakes.dart
git commit -m "feat(mobile): backend ports and shellx_client adapter"
```

---

### Task 5: Account lifecycle — version gate, sign in/up, sign out, 4002, 4001, delete account

**Files:**
- Create: `apps/mobile/lib/account/account_store.dart`, `apps/mobile/lib/account/app_controller.dart`, `apps/mobile/test/support/fake_relay_http.dart`
- Test: `apps/mobile/test/account/app_controller_test.dart`

**Interfaces:**
- Consumes: `ShellxApi` (`version`, `login`, `register`, `logout`, `deleteAccount`, `token`), `compareVersions`, `DeviceInfo`, `DeviceKind`, `NoiseKeyPair`, `DeviceIdentity.storageKey`, `ApiException`, `RelayConnectionState` (overview §5.2, §5.5); `ShellxBackend` (Task 4); `DeviceDescription` (Task 2).
- Produces:
  - `final class AccountSession { const AccountSession({required String userId, required String deviceId, required String token, required String email}); }`
  - `final class AccountStore { AccountStore(KeyValueStore store); static const String tokenKey = 'auth_token', userIdKey = 'auth_user_id', deviceIdKey = 'auth_device_id', emailKey = 'auth_email'; Future<AccountSession?> load(); Future<String?> lastEmail(); Future<void> save(AccountSession session); Future<void> clearToken(); Future<void> forgetAccount(String userId); }`
  - `sealed class AppPhase` with `AppStarting()`, `AppUpdateRequired(String minVersion)`, `AppSignedOut({String? lastEmail, bool revoked = false, bool accountDeleted = false})`, `AppSignedIn({required AccountSession session, required ShellxBackend backend})`
  - `typedef BackendFactory = Future<ShellxBackend> Function(AccountSession session, NoiseKeyPair identity);`
  - `final class AppController extends ChangeNotifier { AppController({required ShellxApi api, required AccountStore accounts, required Future<NoiseKeyPair> Function() loadIdentity, required DeviceDescription device, required String appVersion, required BackendFactory backendFactory}); AppPhase get phase; String get appVersion; Future<void> start(); Future<void> login(String email, String password); Future<void> register(String email, String password); Future<void> logout(); Future<void> deleteAccount(String password); Future<void> reconnectReplaced(); void onBackground(); void onForeground(); }`
  - Test support: `FakeRelayHttp` (scripted `/v1/version`, `/v1/auth/*`, `DELETE /v1/account`) with `testUserId`, `testDeviceId`.

Behaviour pinned by the tests: `/v1/version` newer than the app → `AppUpdateRequired` (unreachable relay does not block); logout deletes **only** the token (device key and `pinned_machines_<userId>` stay, spec §5.2) and works offline; `revoked` (4002 or a 401 upgrade) → token deleted, `AppSignedOut(revoked: true)`; `replaced` (4001) is never reconnected automatically — `reconnectReplaced()` restarts the same backend (`suspend` + `resume`) on user request, keeping machines and tabs; `onBackground()` suspends the backend (spec §12: retry only in the foreground; iOS drops the socket anyway) unless it is replaced/revoked; `onForeground()` resumes a suspended backend, or calls `reconnectNow()` for a `disconnected` relay; `deleteAccount` forgets token + ids + email + device key + this user's pins and ignores the 4002 that accompanies it. `StreamSubscription.cancel()` is deliberately not awaited: cancellation is immediate and awaiting its root-zone future stalls under `fake_async` in widget tests.

- [ ] **Step 1: Write the scripted relay API for tests**

`apps/mobile/test/support/fake_relay_http.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const testUserId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const testDeviceId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

/// A scripted relay REST API (spec §10.2 shapes).
class FakeRelayHttp {
  String minMobile = '1.0.0';
  bool versionOffline = false;
  Map<String, Object?>? loginError;
  bool logoutOffline = false;
  String accountPassword = 'correct horse';
  final List<http.Request> requests = [];

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/v1/version') {
      if (versionOffline) throw http.ClientException('offline');
      return http.Response(
        jsonEncode({
          'min_agent': '1.0.0',
          'min_mobile': minMobile,
          'latest_agent': {
            'version': '1.0.0',
            'mac_url': 'https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg',
            'win_url': 'https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe',
          },
        }),
        200,
      );
    }
    if (path == '/v1/auth/login' || path == '/v1/auth/register') {
      final error = loginError;
      if (error != null) return http.Response(jsonEncode({'error': error}), error['status'] as int);
      return http.Response(
        jsonEncode({'user_id': testUserId, 'device_id': testDeviceId, 'token': 'token-1'}),
        path.endsWith('register') ? 201 : 200,
      );
    }
    if (path == '/v1/account' && request.method == 'DELETE') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      if (body['password'] != accountPassword) {
        return http.Response(
          jsonEncode({'error': {'code': 'invalid_credentials', 'message': 'wrong password'}}),
          401,
        );
      }
      return http.Response('', 204);
    }
    if (path == '/v1/auth/logout') {
      if (logoutOffline) throw http.ClientException('offline');
      return http.Response('', 204);
    }
    return http.Response(jsonEncode({'error': {'code': 'not_found', 'message': path}}), 404);
  });

  http.Request lastTo(String path) => requests.lastWhere((r) => r.url.path == path);
}
```

- [ ] **Step 2: Write the failing test**

`apps/mobile/test/account/app_controller_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/account/account_store.dart';
import 'package:shellx_mobile/account/app_controller.dart';
import 'package:shellx_mobile/platform/device_description.dart';

import '../support/fake_relay_http.dart';
import '../support/fakes.dart';

void main() {
  late FakeRelayHttp relay;
  late InMemoryKeyValueStore store;
  late ShellxApi api;
  late List<FakeBackend> backends;
  late List<AccountSession> backendSessions;
  late NoiseKeyPair identity;

  AppController controller({String appVersion = '1.0.0'}) => AppController(
        api: api,
        accounts: AccountStore(store),
        loadIdentity: () async => identity,
        device: const DeviceDescription(name: 'iPhone 15', platform: DevicePlatform.ios),
        appVersion: appVersion,
        backendFactory: (session, id) async {
          backendSessions.add(session);
          final backend = FakeBackend();
          backends.add(backend);
          return backend;
        },
      );

  setUp(() async {
    relay = FakeRelayHttp();
    store = InMemoryKeyValueStore();
    api = ShellxApi(baseUri: Uri.parse('http://127.0.0.1:8787'), httpClient: relay.client);
    backends = [];
    backendSessions = [];
    identity = await NoiseKeyPair.generate();
  });

  Future<void> saveSession() => AccountStore(store).save(
        const AccountSession(userId: testUserId, deviceId: testDeviceId, token: 'saved', email: 'a@b.co'),
      );

  test('blocks the app when older than min_mobile (spec §14)', () async {
    relay.minMobile = '1.2.0';
    final app = controller(appVersion: '1.1.9');
    await app.start();
    expect(app.phase, isA<AppUpdateRequired>());
    expect((app.phase as AppUpdateRequired).minVersion, '1.2.0');
  });

  test('an unreachable /v1/version does not block the app', () async {
    relay.versionOffline = true;
    final app = controller();
    await app.start();
    expect(app.phase, isA<AppSignedOut>());
  });

  test('restores a saved session and starts its backend', () async {
    await saveSession();
    final app = controller();
    await app.start();
    expect(app.phase, isA<AppSignedIn>());
    expect(api.token, 'saved');
    expect(backendSessions.single.userId, testUserId);
  });

  test('login normalises the email and sends the mobile device info', () async {
    final app = controller();
    await app.start();
    await app.login('  Me@Example.COM ', 'correct horse');

    final body = jsonDecode(relay.lastTo('/v1/auth/login').body) as Map<String, Object?>;
    expect(body['email'], 'me@example.com');
    final device = body['device'] as Map<String, Object?>;
    expect(device['kind'], 'mobile');
    expect(device['platform'], 'ios');
    expect(device['name'], 'iPhone 15');
    expect(device['public_key'], base64UrlNoPad(identity.publicKey));

    expect(app.phase, isA<AppSignedIn>());
    final saved = await AccountStore(store).load();
    expect(saved?.token, 'token-1');
    expect(saved?.email, 'me@example.com');
  });

  test('register uses /v1/auth/register', () async {
    final app = controller();
    await app.start();
    await app.register('new@example.com', 'long enough');
    expect(relay.requests.map((r) => r.url.path), contains('/v1/auth/register'));
    expect(app.phase, isA<AppSignedIn>());
  });

  test('a rejected login throws ApiException and stays signed out', () async {
    relay.loginError = {'status': 401, 'code': 'invalid_credentials', 'message': 'no'};
    final app = controller();
    await app.start();
    await expectLater(
      app.login('a@b.co', 'wrong password'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_credentials')),
    );
    expect(app.phase, isA<AppSignedOut>());
    expect(await AccountStore(store).load(), isNull);
  });

  test('logout deletes only the token (spec §5.2)', () async {
    await saveSession();
    await store.write(DeviceIdentity.storageKey, 'private-key');
    await store.write('pinned_machines_$testUserId', '[]');
    final app = controller();
    await app.start();

    await app.logout();

    expect(relay.lastTo('/v1/auth/logout').headers['authorization'], 'Bearer saved');
    expect(backends.single.disposed, isTrue);
    expect(await store.read(AccountStore.tokenKey), isNull);
    expect(await store.read(DeviceIdentity.storageKey), 'private-key');
    expect(await store.read('pinned_machines_$testUserId'), '[]');
    expect(await store.read(AccountStore.userIdKey), testUserId);
    expect(api.token, isNull);
    expect(app.phase, isA<AppSignedOut>());
    expect((app.phase as AppSignedOut).lastEmail, 'a@b.co');
  });

  test('logout still signs out locally when the relay is unreachable', () async {
    await saveSession();
    relay.logoutOffline = true;
    final app = controller();
    await app.start();
    await app.logout();
    expect(app.phase, isA<AppSignedOut>());
    expect(await store.read(AccountStore.tokenKey), isNull);
  });

  test('close code 4002 (revoked) deletes the token and returns to login (spec §12)', () async {
    await saveSession();
    final app = controller();
    await app.start();

    backends.single.emitRelay(RelayConnectionState.revoked);
    await pumpEventQueue();

    expect(app.phase, isA<AppSignedOut>());
    expect((app.phase as AppSignedOut).revoked, isTrue);
    expect(await store.read(AccountStore.tokenKey), isNull);
    expect(relay.requests.where((r) => r.url.path == '/v1/auth/logout'), isEmpty);
  });

  test('reconnectReplaced restarts the same backend after 4001', () async {
    await saveSession();
    final app = controller();
    await app.start();
    final backend = backends.single;
    backend.emitRelay(RelayConnectionState.replaced);

    await app.reconnectReplaced();

    expect(backends, hasLength(1));
    expect(backend.suspendCalls, 1);
    expect(backend.resumeCalls, 1);
    expect(backend.relayState, RelayConnectionState.connected);
  });

  test('background suspends the relay, foreground resumes it (spec §9.4, §12)', () async {
    await saveSession();
    final app = controller();
    await app.start();
    final backend = backends.single;

    app.onBackground();
    app.onBackground();
    expect(backend.suspendCalls, 1);

    app.onForeground();
    app.onForeground();
    expect(backend.resumeCalls, 1);
    expect(backend.reconnectCalls, 0);
  });

  test('a replaced (4001) connection is never resumed automatically', () async {
    await saveSession();
    final app = controller();
    await app.start();
    final backend = backends.single;
    backend.emitRelay(RelayConnectionState.replaced);

    app.onBackground();
    app.onForeground();

    expect(backend.suspendCalls, 0);
    expect(backend.resumeCalls, 0);
    expect(backend.reconnectCalls, 0);
  });

  test('foreground without a background skips the backoff of a disconnected relay', () async {
    await saveSession();
    final app = controller();
    await app.start();
    final backend = backends.single;

    backend.relayStateValue = RelayConnectionState.disconnected;
    app.onForeground();
    backend.relayStateValue = RelayConnectionState.connected;
    app.onForeground();

    expect(backend.reconnectCalls, 1);
  });

  group('deleteAccount', () {
    test('wrong password throws invalid_credentials and keeps the session', () async {
      await saveSession();
      final app = controller();
      await app.start();

      await expectLater(
        app.deleteAccount('nope'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_credentials')),
      );
      expect(app.phase, isA<AppSignedIn>());
      expect(backends.single.disposed, isFalse);
      expect(await store.read(AccountStore.tokenKey), 'saved');
    });

    test('success forgets token, device key and this user\'s pins only', () async {
      await saveSession();
      await store.write(DeviceIdentity.storageKey, 'private-key');
      await store.write('pinned_machines_$testUserId', '[]');
      await store.write('pinned_machines_other-user', '[]');
      final app = controller();
      await app.start();

      await app.deleteAccount('correct horse');

      final request = relay.lastTo('/v1/account');
      expect(request.method, 'DELETE');
      expect(request.headers['authorization'], 'Bearer saved');
      expect(backends.single.disposed, isTrue);
      for (final key in [
        AccountStore.tokenKey,
        AccountStore.userIdKey,
        AccountStore.deviceIdKey,
        AccountStore.emailKey,
        DeviceIdentity.storageKey,
        'pinned_machines_$testUserId',
      ]) {
        expect(await store.read(key), isNull, reason: key);
      }
      expect(await store.read('pinned_machines_other-user'), '[]');
      expect(api.token, isNull);
      expect(app.phase, isA<AppSignedOut>());
      expect((app.phase as AppSignedOut).accountDeleted, isTrue);
      expect((app.phase as AppSignedOut).revoked, isFalse);
    });

    test('the 4002 close that accompanies the deletion is not treated as a revocation', () async {
      await saveSession();
      final app = controller();
      await app.start();
      final backend = backends.single;

      final deletion = app.deleteAccount('correct horse');
      backend.emitRelay(RelayConnectionState.revoked);
      await deletion;
      await pumpEventQueue();

      expect((app.phase as AppSignedOut).accountDeleted, isTrue);
      expect((app.phase as AppSignedOut).revoked, isFalse);
    });
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd apps/mobile && flutter test test/account/app_controller_test.dart`
Expected: FAIL — `Error when reading 'lib/account/account_store.dart': No such file or directory`, `Error when reading 'lib/account/app_controller.dart': No such file or directory`.

- [ ] **Step 4: Implement**

`apps/mobile/lib/account/account_store.dart`:

```dart
import 'package:shellx_core/shellx_core.dart';

/// The signed-in account as persisted in secure storage (spec §9.5).
final class AccountSession {
  const AccountSession({
    required this.userId,
    required this.deviceId,
    required this.token,
    required this.email,
  });

  final String userId;
  final String deviceId;
  final String token;
  final String email;
}

final class AccountStore {
  AccountStore(this._store);

  static const String tokenKey = 'auth_token';
  static const String userIdKey = 'auth_user_id';
  static const String deviceIdKey = 'auth_device_id';
  static const String emailKey = 'auth_email';

  final KeyValueStore _store;

  /// The saved session, or null when signed out.
  Future<AccountSession?> load() async {
    final token = await _store.read(tokenKey);
    final userId = await _store.read(userIdKey);
    final deviceId = await _store.read(deviceIdKey);
    final email = await _store.read(emailKey);
    if (token == null || userId == null || deviceId == null || email == null) return null;
    return AccountSession(userId: userId, deviceId: deviceId, token: token, email: email);
  }

  Future<String?> lastEmail() => _store.read(emailKey);

  Future<void> save(AccountSession session) async {
    await _store.write(userIdKey, session.userId);
    await _store.write(deviceIdKey, session.deviceId);
    await _store.write(emailKey, session.email);
    await _store.write(tokenKey, session.token);
  }

  /// Spec §5.2: logging out on mobile deletes only the token. The device key
  /// and the machines pinned under `pinned_machines_<userId>` are kept so the
  /// same account can sign in again without re-pairing.
  Future<void> clearToken() => _store.delete(tokenKey);

  /// After `DELETE /v1/account`: forget everything tied to the deleted
  /// account — the session, the device private key and the machines pinned
  /// for [userId] (key `pinned_machines_<userId>`, overview §5.7).
  Future<void> forgetAccount(String userId) async {
    for (final key in [tokenKey, userIdKey, deviceIdKey, emailKey]) {
      await _store.delete(key);
    }
    await _store.delete(DeviceIdentity.storageKey);
    await _store.delete('pinned_machines_$userId');
  }
}
```

`apps/mobile/lib/account/app_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shellx_core/shellx_core.dart';

import '../backend/backend.dart';
import '../platform/device_description.dart';
import 'account_store.dart';

sealed class AppPhase {
  const AppPhase();
}

final class AppStarting extends AppPhase {
  const AppStarting();
}

/// Spec §14: the app is blocked when it is older than `min_mobile`.
final class AppUpdateRequired extends AppPhase {
  const AppUpdateRequired(this.minVersion);
  final String minVersion;
}

final class AppSignedOut extends AppPhase {
  const AppSignedOut({this.lastEmail, this.revoked = false, this.accountDeleted = false});
  final String? lastEmail;

  /// True when the relay closed the socket with 4002 (spec §12).
  final bool revoked;

  /// True right after the user deleted their account (spec §5.2).
  final bool accountDeleted;
}

final class AppSignedIn extends AppPhase {
  const AppSignedIn({required this.session, required this.backend});
  final AccountSession session;
  final ShellxBackend backend;
}

typedef BackendFactory = Future<ShellxBackend> Function(
  AccountSession session,
  NoiseKeyPair identity,
);

/// Account lifecycle: version gate, login/register, logout, token revocation.
final class AppController extends ChangeNotifier {
  AppController({
    required ShellxApi api,
    required AccountStore accounts,
    required Future<NoiseKeyPair> Function() loadIdentity,
    required DeviceDescription device,
    required String appVersion,
    required BackendFactory backendFactory,
  })  : _api = api,
        _accounts = accounts,
        _loadIdentity = loadIdentity,
        _device = device,
        _appVersion = appVersion,
        _backendFactory = backendFactory;

  final ShellxApi _api;
  final AccountStore _accounts;
  final Future<NoiseKeyPair> Function() _loadIdentity;
  final DeviceDescription _device;
  final String _appVersion;
  final BackendFactory _backendFactory;
  StreamSubscription<RelayConnectionState>? _relaySubscription;
  AppPhase _phase = const AppStarting();
  bool _deletingAccount = false;
  bool _suspended = false;

  AppPhase get phase => _phase;
  String get appVersion => _appVersion;

  void _setPhase(AppPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  Future<void> start() async {
    try {
      final info = await _api.version();
      if (compareVersions(_appVersion, info.minMobile) < 0) {
        _setPhase(AppUpdateRequired(info.minMobile));
        return;
      }
    } on ApiException {
      // Relay unreachable: do not block the app; the gate runs on every launch.
    }
    final session = await _accounts.load();
    if (session == null) {
      _setPhase(AppSignedOut(lastEmail: await _accounts.lastEmail()));
      return;
    }
    await _enter(session, await _loadIdentity());
  }

  /// Throws [ApiException] (e.g. `invalid_credentials`, HTTP 429).
  Future<void> login(String email, String password) =>
      _authenticate(email, password, register: false);

  /// Throws [ApiException] (e.g. `email_taken`, `disposable_email`).
  Future<void> register(String email, String password) =>
      _authenticate(email, password, register: true);

  Future<void> _authenticate(String email, String password, {required bool register}) async {
    final identity = await _loadIdentity();
    final device = DeviceInfo(
      kind: DeviceKind.mobile,
      name: _device.name,
      platform: _device.platform,
      publicKey: identity.publicKey,
    );
    final normalized = email.trim().toLowerCase();
    final result = register
        ? await _api.register(normalized, password, device)
        : await _api.login(normalized, password, device);
    final session = AccountSession(
      userId: result.userId,
      deviceId: result.deviceId,
      token: result.token,
      email: normalized,
    );
    await _accounts.save(session);
    await _enter(session, identity);
  }

  Future<void> _enter(AccountSession session, NoiseKeyPair identity) async {
    _api.token = session.token;
    _suspended = false;
    final backend = await _backendFactory(session, identity);
    _relaySubscription = backend.relayStates.listen((state) {
      // Deleting the account closes every socket with 4002; that is not a revocation.
      if (state == RelayConnectionState.revoked && !_deletingAccount) {
        unawaited(_signOut(revoked: true));
      }
    });
    _setPhase(AppSignedIn(session: session, backend: backend));
  }

  Future<void> _teardown(AppSignedIn phase) async {
    // Cancelling takes effect immediately; its future only reports cleanup.
    unawaited(_relaySubscription?.cancel());
    _relaySubscription = null;
    await phase.backend.dispose();
  }

  Future<void> logout() => _signOut(revoked: false);

  Future<void> _signOut({required bool revoked}) async {
    final phase = _phase;
    if (phase is! AppSignedIn) return;
    await _teardown(phase);
    if (!revoked) {
      try {
        await _api.logout();
      } on ApiException {
        // Offline: the token is still deleted locally below.
      }
    }
    await _accounts.clearToken();
    _api.token = null;
    _setPhase(AppSignedOut(lastEmail: phase.session.email, revoked: revoked));
  }

  /// Spec §5.2 (App Store 5.1.1(v)): `DELETE /v1/account` with the password,
  /// then forget the token, the device key and this user's pinned machines.
  /// Throws [ApiException] (`invalid_credentials` for a wrong password) and
  /// stays signed in.
  Future<void> deleteAccount(String password) async {
    final phase = _phase;
    if (phase is! AppSignedIn) return;
    _deletingAccount = true;
    try {
      await _api.deleteAccount(password);
      await _teardown(phase);
      await _accounts.forgetAccount(phase.session.userId);
      _api.token = null;
      _setPhase(const AppSignedOut(accountDeleted: true));
    } finally {
      _deletingAccount = false;
    }
  }

  /// After close code 4001 the relay does not reconnect by itself (spec §12);
  /// the user takes the connection back from the banner. Restarting the same
  /// backend keeps every machine and tab (`RelayConnection.start()` is allowed
  /// after `replaced`).
  Future<void> reconnectReplaced() async {
    final phase = _phase;
    if (phase is! AppSignedIn) return;
    await phase.backend.suspend();
    await phase.backend.resume();
  }

  /// App went to the background: stop retrying (spec §12 "mobile thử khi ở
  /// foreground"); iOS would cut the socket anyway (spec §9.4).
  void onBackground() {
    final phase = _phase;
    if (phase is! AppSignedIn || _suspended) return;
    switch (phase.backend.relayState) {
      case RelayConnectionState.replaced:
      case RelayConnectionState.revoked:
      case RelayConnectionState.stopped:
        return; // Never reconnect these automatically.
      case RelayConnectionState.disconnected:
      case RelayConnectionState.connecting:
      case RelayConnectionState.connected:
        _suspended = true;
        unawaited(phase.backend.suspend());
    }
  }

  /// App back in the foreground: reconnect right away (spec §9.4, §12).
  void onForeground() {
    final phase = _phase;
    if (phase is! AppSignedIn) return;
    if (_suspended) {
      _suspended = false;
      unawaited(phase.backend.resume());
    } else if (phase.backend.relayState == RelayConnectionState.disconnected) {
      phase.backend.reconnectNow();
    }
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/account/app_controller_test.dart`
Expected: PASS — `All tests passed!` (16 tests).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/account/account_store.dart apps/mobile/lib/account/app_controller.dart \
  apps/mobile/test/account/app_controller_test.dart apps/mobile/test/support/fake_relay_http.dart
git commit -m "feat(mobile): account lifecycle with version gate, logout, revocation and account deletion"
```

---

### Task 6: Biometric lock (spec §5.6)

**Files:**
- Create: `apps/mobile/lib/lock/biometric_authenticator.dart`, `apps/mobile/lib/lock/app_lock_controller.dart`, `apps/mobile/lib/lock/lock_gate.dart`
- Modify: `apps/mobile/test/support/fakes.dart` (add `FakeBiometricAuthenticator`)
- Test: `apps/mobile/test/lock/app_lock_controller_test.dart`, `apps/mobile/test/lock/lock_gate_test.dart`

**Interfaces:**
- Consumes: `LocalAuthentication`, `LocalAuthException`, `LocalAuthExceptionCode` (`local_auth` 3.0.2); `AppLocalizations` (`lockTitle`, `lockUnlockButton`, `lockReason`).
- Produces:
  - `abstract interface class BiometricAuthenticator { Future<bool> isAvailable(); Future<bool> authenticate(String reason); }`, `final class LocalAuthBiometricAuthenticator implements BiometricAuthenticator { LocalAuthBiometricAuthenticator([LocalAuthentication? auth]); }`
  - `final class AppLockController extends ChangeNotifier { AppLockController({required BiometricAuthenticator authenticator, required bool Function() isEnabled, DateTime Function()? now, Duration backgroundTimeout = const Duration(minutes: 5)}); bool get isLocked; bool get isAuthenticating; void lockOnLaunch(); void onBackgrounded(); void onForegrounded(); Future<bool> unlock(String reason); void settingChanged(); }`
  - `class LockGate extends StatefulWidget { const LockGate({Key? key, required AppLockController lock, required VoidCallback onBackground, required VoidCallback onForeground, required Widget child}); }` — wraps the app (used in `MaterialApp.builder`), maps `AppLifecycleListener.onPause` → `lock.onBackgrounded` + `onBackground` (suspend hook), `onResume` → `lock.onForegrounded` + `onForeground` (reconnect hook), hides and unfocuses the content while locked. `class LockScreen extends StatefulWidget { const LockScreen({Key? key, required AppLockController lock}); }`
  - Test support: `FakeBiometricAuthenticator { bool available; bool result; int prompts; String? lastReason; }`

"More than 5 minutes" is strict: exactly 5:00 does not lock, 5:01 does. A device without passcode/biometrics cannot lock (unlock succeeds without a prompt; Settings shows the switch disabled in Task 15).

- [ ] **Step 1: Add the fake authenticator**

In `apps/mobile/test/support/fakes.dart` add the import after the `backend.dart` import:

```dart
import 'package:shellx_mobile/lock/biometric_authenticator.dart';
```

and append at the end of the file:

```dart
class FakeBiometricAuthenticator implements BiometricAuthenticator {
  bool available = true;
  bool result = true;
  int prompts = 0;
  String? lastReason;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    lastReason = reason;
    return result;
  }
}
```

- [ ] **Step 2: Write the failing tests**

`apps/mobile/test/lock/app_lock_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/lock/app_lock_controller.dart';

import '../support/fakes.dart';

void main() {
  late FakeBiometricAuthenticator auth;
  late DateTime now;
  late bool enabled;

  AppLockController controller() => AppLockController(
        authenticator: auth,
        isEnabled: () => enabled,
        now: () => now,
      );

  setUp(() {
    auth = FakeBiometricAuthenticator();
    now = DateTime(2026, 9, 25, 9);
    enabled = true;
  });

  test('locks on launch when enabled, not when disabled', () {
    final lock = controller()..lockOnLaunch();
    expect(lock.isLocked, isTrue);
    enabled = false;
    expect((controller()..lockOnLaunch()).isLocked, isFalse);
  });

  test('exactly 5 minutes in the background does not lock; more than 5 does', () {
    final lock = controller();
    lock.onBackgrounded();
    now = now.add(const Duration(minutes: 5));
    lock.onForegrounded();
    expect(lock.isLocked, isFalse);

    lock.onBackgrounded();
    now = now.add(const Duration(minutes: 5, seconds: 1));
    lock.onForegrounded();
    expect(lock.isLocked, isTrue);
  });

  test('a resume without a preceding pause never locks', () {
    final lock = controller();
    now = now.add(const Duration(hours: 1));
    lock.onForegrounded();
    expect(lock.isLocked, isFalse);
  });

  test('does not lock after a long background when the setting is off', () {
    enabled = false;
    final lock = controller()..onBackgrounded();
    now = now.add(const Duration(hours: 1));
    lock.onForegrounded();
    expect(lock.isLocked, isFalse);
  });

  test('unlock succeeds only when authentication succeeds', () async {
    final lock = controller()..lockOnLaunch();
    auth.result = false;
    expect(await lock.unlock('Unlock ShellX'), isFalse);
    expect(lock.isLocked, isTrue);
    auth.result = true;
    expect(await lock.unlock('Unlock ShellX'), isTrue);
    expect(lock.isLocked, isFalse);
    expect(auth.lastReason, 'Unlock ShellX');
  });

  test('a device without passcode or biometrics unlocks without prompting', () async {
    auth.available = false;
    final lock = controller()..lockOnLaunch();
    expect(await lock.unlock('reason'), isTrue);
    expect(auth.prompts, 0);
  });

  test('turning the setting off unlocks', () {
    final lock = controller()..lockOnLaunch();
    enabled = false;
    lock.settingChanged();
    expect(lock.isLocked, isFalse);
  });
}
```

`apps/mobile/test/lock/lock_gate_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/l10n/app_localizations.dart';
import 'package:shellx_mobile/lock/app_lock_controller.dart';
import 'package:shellx_mobile/lock/lock_gate.dart';

import '../support/fakes.dart';

void main() {
  late FakeBiometricAuthenticator auth;
  late DateTime now;
  late AppLockController lock;
  late int backgrounds;
  late int foregrounds;

  Widget app() => MaterialApp(
        locale: const Locale('vi'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => LockGate(
          lock: lock,
          onBackground: () => backgrounds++,
          onForeground: () => foregrounds++,
          child: child!,
        ),
        home: const Scaffold(body: Text('secret terminal')),
      );

  Future<void> goToBackground(WidgetTester tester) async {
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
  }

  Future<void> comeBack(WidgetTester tester) async {
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
  }

  setUp(() {
    auth = FakeBiometricAuthenticator()..result = false;
    now = DateTime(2026, 9, 25, 9);
    lock = AppLockController(authenticator: auth, isEnabled: () => true, now: () => now);
    backgrounds = 0;
    foregrounds = 0;
  });

  testWidgets('shows the lock screen on launch and prompts immediately', (tester) async {
    lock.lockOnLaunch();
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.text('ShellX đang khóa'), findsOneWidget);
    expect(auth.prompts, 1);
    expect(auth.lastReason, 'Mở khóa ShellX');

    auth.result = true;
    await tester.tap(find.text('Mở khóa'));
    await tester.pump();
    expect(find.text('ShellX đang khóa'), findsNothing);
    expect(find.text('secret terminal'), findsOneWidget);
  });

  testWidgets('relocks after more than 5 minutes in the background and reports both transitions',
      (tester) async {
    await tester.pumpWidget(app());
    expect(find.text('ShellX đang khóa'), findsNothing);

    await goToBackground(tester);
    now = now.add(const Duration(minutes: 6));
    await comeBack(tester);
    await tester.pump();

    expect(backgrounds, 1);
    expect(foregrounds, 1);
    expect(find.text('ShellX đang khóa'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `cd apps/mobile && flutter test test/lock`
Expected: FAIL — `Error when reading 'lib/lock/biometric_authenticator.dart': No such file or directory` (and `app_lock_controller.dart`, `lock_gate.dart`).

- [ ] **Step 4: Implement**

`apps/mobile/lib/lock/biometric_authenticator.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Face ID / fingerprint / device passcode (spec §5.6).
abstract interface class BiometricAuthenticator {
  /// False when the device has no passcode and no biometrics enrolled.
  Future<bool> isAvailable();

  /// True when the user proved their identity.
  Future<bool> authenticate(String reason);
}

final class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  LocalAuthBiometricAuthenticator([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // biometricOnly: false → the device passcode is accepted ("mã máy").
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } on LocalAuthException catch (error) {
      // The passcode was removed after the lock was enabled: nothing can be
      // verified any more, so do not lock the user out of their own app.
      return error.code == LocalAuthExceptionCode.noCredentialsSet;
    }
  }
}
```

`apps/mobile/lib/lock/app_lock_controller.dart`:

```dart
import 'package:flutter/foundation.dart';

import 'biometric_authenticator.dart';

/// Spec §5.6: require unlocking when the app opens and when it comes back
/// after more than 5 minutes in the background.
final class AppLockController extends ChangeNotifier {
  AppLockController({
    required BiometricAuthenticator authenticator,
    required bool Function() isEnabled,
    DateTime Function()? now,
    this.backgroundTimeout = const Duration(minutes: 5),
  })  : _authenticator = authenticator,
        _isEnabled = isEnabled,
        _now = now ?? DateTime.now;

  final BiometricAuthenticator _authenticator;
  final bool Function() _isEnabled;
  final DateTime Function() _now;
  final Duration backgroundTimeout;
  bool _locked = false;
  bool _authenticating = false;
  DateTime? _backgroundedAt;

  bool get isLocked => _locked;
  bool get isAuthenticating => _authenticating;

  void _setLocked(bool locked) {
    if (_locked == locked) return;
    _locked = locked;
    notifyListeners();
  }

  void lockOnLaunch() {
    if (_isEnabled()) _setLocked(true);
  }

  void onBackgrounded() => _backgroundedAt = _now();

  void onForegrounded() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || !_isEnabled()) return;
    if (_now().difference(since) > backgroundTimeout) _setLocked(true);
  }

  /// Prompts for Face ID / fingerprint / passcode. Unlocks without a prompt
  /// when the device cannot authenticate at all.
  Future<bool> unlock(String reason) async {
    if (!_locked) return true;
    if (_authenticating) return false;
    _authenticating = true;
    notifyListeners();
    try {
      final ok = !await _authenticator.isAvailable() || await _authenticator.authenticate(reason);
      if (ok) _locked = false;
      return ok;
    } finally {
      _authenticating = false;
      notifyListeners();
    }
  }

  /// Call after the biometric setting changes: turning it off while locked
  /// must not leave the user stuck.
  void settingChanged() {
    if (!_isEnabled()) _setLocked(false);
  }
}
```

`apps/mobile/lib/lock/lock_gate.dart`:

```dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'app_lock_controller.dart';

/// Covers the whole app with [LockScreen] while [lock] is locked and feeds
/// app lifecycle changes to the lock and to [onBackground]/[onForeground].
class LockGate extends StatefulWidget {
  const LockGate({
    super.key,
    required this.lock,
    required this.onBackground,
    required this.onForeground,
    required this.child,
  });

  final AppLockController lock;

  /// Called when the app is paused (suspend the relay, spec §12).
  final VoidCallback onBackground;

  /// Called every time the app returns to the foreground (reconnect, spec §9.4).
  final VoidCallback onForeground;
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onPause: _onPause, onResume: _onResume);
    widget.lock.addListener(_onLockChanged);
  }

  void _onPause() {
    widget.lock.onBackgrounded();
    widget.onBackground();
  }

  void _onResume() {
    widget.lock.onForegrounded();
    widget.onForeground();
  }

  void _onLockChanged() {
    // Keep keystrokes (soft or hardware keyboard) away from the hidden terminal.
    if (widget.lock.isLocked) FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    widget.lock.removeListener(_onLockChanged);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.lock,
      builder: (context, child) => Stack(
        children: [
          ExcludeFocus(excluding: widget.lock.isLocked, child: child!),
          if (widget.lock.isLocked) Positioned.fill(child: LockScreen(lock: widget.lock)),
        ],
      ),
      child: widget.child,
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.lock});

  final AppLockController lock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    // Prompt right away; the button retries after a cancelled prompt.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (!mounted) return;
    await widget.lock.unlock(AppLocalizations.of(context).lockReason);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 64),
            const SizedBox(height: 16),
            Text(l10n.lockTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: widget.lock.isAuthenticating ? null : _unlock,
              child: Text(l10n.lockUnlockButton),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/lock test/backend`
Expected: PASS — `All tests passed!` (9 lock tests + the backend test, which recompiles `fakes.dart`).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/lock apps/mobile/test/lock apps/mobile/test/support/fakes.dart
git commit -m "feat(mobile): biometric app lock on launch and after 5 minutes in background"
```

---

### Task 7: Terminal input primitives — cursor keys, control characters, newlines, shortcuts

**Files:**
- Create: `apps/mobile/lib/terminal/terminal_input.dart`, `apps/mobile/lib/terminal/terminal_shortcuts.dart`
- Test: `apps/mobile/test/terminal/terminal_input_test.dart`

**Interfaces:**
- Consumes: `package:xterm/core.dart` — `Terminal`, `TerminalKey`, `TerminalInputHandler`, `TerminalKeyboardEvent` (`key`, `shift`, `alt`, `ctrl`, `state.cursorKeysMode`), `CascadeInputHandler`, `defaultInputHandler`.
- Produces:
  - `final class CursorKeysInputHandler implements TerminalInputHandler { const CursorKeysInputHandler(); }` and `const TerminalInputHandler shellxInputHandler` (= `CascadeInputHandler([CursorKeysInputHandler(), defaultInputHandler])`)
  - `String? controlCharacterFor(String char)`, `String applyModifiersToText(String text, {required bool ctrl, required bool alt})`, `String normalizeTypedText(String text)`, `String normalizePastedText(String text)`
  - `Map<ShortcutActivator, Intent> terminalShortcuts(TargetPlatform platform)`

Why: verified in xterm 4.0.0's `KeytabInputHandler` — it passes `appKeypadMode` as `appCursorKeys`, so a program that sends only `ESC[?1h` still gets `ESC[A`; Alt+Left and Shift+Up come out as `ESC[1;5D`/`ESC[1;5A`, Ctrl+Alt+Left produces nothing. `charInput` ignores uppercase with Ctrl and sends Alt+a as `ESC A` (uppercase). This task keeps xterm's handler for every other key and replaces only those behaviours (Review Focus 3, 4).

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/terminal/terminal_input_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/terminal/terminal_input.dart';
import 'package:shellx_mobile/terminal/terminal_shortcuts.dart';
import 'package:xterm/core.dart';

void main() {
  group('shellxInputHandler', () {
    late List<String> out;
    late Terminal terminal;

    setUp(() {
      out = [];
      terminal = Terminal(inputHandler: shellxInputHandler, onOutput: out.add);
    });

    String press(TerminalKey key, {bool shift = false, bool alt = false, bool ctrl = false}) {
      out.clear();
      terminal.keyInput(key, shift: shift, alt: alt, ctrl: ctrl);
      return out.join();
    }

    test('arrows follow DECCKM (application cursor mode)', () {
      expect(press(TerminalKey.arrowUp), '\x1b[A');
      terminal.write('\x1b[?1h');
      expect(press(TerminalKey.arrowUp), '\x1bOA');
      expect(press(TerminalKey.arrowLeft), '\x1bOD');
      expect(press(TerminalKey.home), '\x1bOH');
      terminal.write('\x1b[?1l');
      expect(press(TerminalKey.arrowDown), '\x1b[B');
      expect(press(TerminalKey.end), '\x1b[F');
    });

    test('modifier parameter is 1 + shift + 2*alt + 4*ctrl', () {
      expect(press(TerminalKey.arrowUp, shift: true), '\x1b[1;2A');
      expect(press(TerminalKey.arrowLeft, alt: true), '\x1b[1;3D');
      expect(press(TerminalKey.arrowRight, ctrl: true), '\x1b[1;5C');
      expect(press(TerminalKey.arrowLeft, ctrl: true, alt: true), '\x1b[1;7D');
      terminal.write('\x1b[?1h');
      expect(press(TerminalKey.arrowUp, alt: true), '\x1b[1;3A');
    });

    test('other keys still use xterm defaults', () {
      expect(press(TerminalKey.pageUp), '\x1b[5~');
      expect(press(TerminalKey.pageDown, alt: true), '\x1b[6;3~');
      expect(press(TerminalKey.escape), '\x1b');
      expect(press(TerminalKey.tab), '\t');
      expect(press(TerminalKey.enter), '\r');
      expect(press(TerminalKey.keyC, ctrl: true), '\x03');
    });
  });

  test('controlCharacterFor', () {
    expect(controlCharacterFor('c'), '\x03');
    expect(controlCharacterFor('C'), '\x03');
    expect(controlCharacterFor('['), '\x1b');
    expect(controlCharacterFor('\\'), '\x1c');
    expect(controlCharacterFor('_'), '\x1f');
    expect(controlCharacterFor('@'), '\x00');
    expect(controlCharacterFor(' '), '\x00');
    expect(controlCharacterFor('/'), '\x1f');
    expect(controlCharacterFor('?'), '\x7f');
    expect(controlCharacterFor('|'), isNull);
    expect(controlCharacterFor('ab'), isNull);
  });

  test('applyModifiersToText', () {
    expect(applyModifiersToText('c', ctrl: true, alt: false), '\x03');
    expect(applyModifiersToText('b', ctrl: false, alt: true), '\x1bb');
    expect(applyModifiersToText('B', ctrl: false, alt: true), '\x1bB');
    expect(applyModifiersToText('x', ctrl: true, alt: true), '\x1b\x18');
    expect(applyModifiersToText('ab', ctrl: true, alt: false), '\x01b');
    expect(applyModifiersToText('|', ctrl: true, alt: false), '|');
    expect(applyModifiersToText('ệ', ctrl: false, alt: true), '\x1bệ');
    expect(applyModifiersToText('😀x', ctrl: false, alt: true), '\x1b😀x');
    expect(applyModifiersToText('', ctrl: true, alt: true), '');
    expect(applyModifiersToText('q', ctrl: false, alt: false), 'q');
  });

  test('newline normalisation', () {
    expect(normalizeTypedText('ls\n'), 'ls\r');
    expect(normalizePastedText('a\r\nb\nc'), 'a\rb\rc');
  });

  group('terminalShortcuts', () {
    Iterable<SingleActivator> activators(TargetPlatform platform) =>
        terminalShortcuts(platform).keys.cast<SingleActivator>();

    test('Android never captures Ctrl+A or Ctrl+V', () {
      final android = activators(TargetPlatform.android);
      expect(android.where((a) => a.control && !a.shift), isEmpty);
      expect(
        android.where((a) => a.trigger == LogicalKeyboardKey.keyV && a.control && a.shift),
        hasLength(1),
      );
    });

    test('iOS uses the Command key', () {
      final ios = activators(TargetPlatform.iOS);
      expect(ios.every((a) => a.meta && !a.control), isTrue);
      expect(terminalShortcuts(TargetPlatform.iOS).values.whereType<PasteTextIntent>(), hasLength(1));
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/mobile && flutter test test/terminal/terminal_input_test.dart`
Expected: FAIL — `Error when reading 'lib/terminal/terminal_input.dart': No such file or directory`, `Error when reading 'lib/terminal/terminal_shortcuts.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/mobile/lib/terminal/terminal_input.dart`:

```dart
import 'package:xterm/core.dart';

/// Cursor and navigation keys as xterm encodes them.
///
/// xterm.dart 4.0.0's keytab (a) derives application cursor mode from DECKPAM
/// (`ESC =`) instead of DECCKM (`ESC [ ? 1 h`) and (b) encodes Alt/Shift+arrow
/// as Ctrl+arrow and drops Ctrl+Alt+arrow. This handler runs first and fixes
/// both; every other key falls through to [defaultInputHandler].
final class CursorKeysInputHandler implements TerminalInputHandler {
  const CursorKeysInputHandler();

  @override
  String? call(TerminalKeyboardEvent event) {
    final letter = switch (event.key) {
      TerminalKey.arrowUp => 'A',
      TerminalKey.arrowDown => 'B',
      TerminalKey.arrowRight => 'C',
      TerminalKey.arrowLeft => 'D',
      TerminalKey.home => 'H',
      TerminalKey.end => 'F',
      _ => null,
    };
    if (letter == null) return null;
    final modifier = 1 + (event.shift ? 1 : 0) + (event.alt ? 2 : 0) + (event.ctrl ? 4 : 0);
    if (modifier > 1) return '\x1b[1;$modifier$letter';
    return event.state.cursorKeysMode ? '\x1bO$letter' : '\x1b[$letter';
  }
}

/// Input handler for every ShellX terminal.
const TerminalInputHandler shellxInputHandler =
    CascadeInputHandler([CursorKeysInputHandler(), defaultInputHandler]);

/// Ctrl+[char] → the C0 control character xterm sends, or null when there is none.
String? controlCharacterFor(String char) {
  if (char.length != 1) return null;
  final code = char.codeUnitAt(0);
  if (code >= 0x61 && code <= 0x7a) return String.fromCharCode(code - 0x60); // a..z
  if (code >= 0x40 && code <= 0x5f) return String.fromCharCode(code - 0x40); // @ A..Z [ \ ] ^ _
  if (code == 0x20) return '\x00'; // Ctrl+Space
  if (code == 0x2f) return '\x1f'; // Ctrl+/
  if (code == 0x3f) return '\x7f'; // Ctrl+?
  return null;
}

/// Applies Ctrl/Alt to the first character of typed [text]: Ctrl maps to a
/// control character, Alt prefixes ESC (xterm "metaSendsEscape").
String applyModifiersToText(String text, {required bool ctrl, required bool alt}) {
  if (text.isEmpty || (!ctrl && !alt)) return text;
  final first = String.fromCharCode(text.runes.first);
  final rest = text.substring(first.length);
  var head = ctrl ? (controlCharacterFor(first) ?? first) : first;
  if (alt) head = '\x1b$head';
  return '$head$rest';
}

/// The Return key of a soft keyboard arrives as "\n"; terminals send CR.
String normalizeTypedText(String text) => text.replaceAll('\n', '\r');

/// Pasted line breaks become CR, like xterm and iTerm2 do.
String normalizePastedText(String text) => text.replaceAll('\r\n', '\r').replaceAll('\n', '\r');
```

`apps/mobile/lib/terminal/terminal_shortcuts.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Copy/paste shortcuts for `TerminalView` with a hardware keyboard.
///
/// xterm.dart's defaults bind Ctrl+A / Ctrl+V on Android, which would swallow
/// keys the shell needs (readline, tmux, vim), so Android uses Ctrl+Shift+C/V
/// like desktop terminals; iOS/iPadOS uses ⌘C / ⌘V. No select-all binding.
Map<ShortcutActivator, Intent> terminalShortcuts(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return {
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): CopySelectionTextIntent.copy,
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            const PasteTextIntent(SelectionChangedCause.keyboard),
      };
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return {
        const SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
            CopySelectionTextIntent.copy,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
            const PasteTextIntent(SelectionChangedCause.keyboard),
      };
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/terminal/terminal_input_test.dart`
Expected: PASS — `All tests passed!` (8 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/terminal/terminal_input.dart apps/mobile/lib/terminal/terminal_shortcuts.dart \
  apps/mobile/test/terminal/terminal_input_test.dart
git commit -m "feat(mobile): terminal input handler with DECCKM, xterm modifiers and safe shortcuts"
```

---

### Task 8: `ExtraKeysController` — sticky Ctrl/Alt and key dispatch (spec §9.3)

**Files:**
- Create: `apps/mobile/lib/terminal/extra_keys_controller.dart`
- Test: `apps/mobile/test/terminal/extra_keys_controller_test.dart`

**Interfaces:**
- Consumes: `Terminal.keyInput(TerminalKey key, {bool shift, bool alt, bool ctrl})`, `Terminal.onOutput` (`package:xterm/core.dart` — pure Dart, no Flutter import); `applyModifiersToText`, `shellxInputHandler` (Task 7).
- Produces:
  - `enum ExtraKey { esc, tab, ctrl, alt, up, down, left, right, pipe, tilde, slash, minus, home, end, pageUp, pageDown, paste }` and `String? extraKeyLabel(ExtraKey key)` (null for `paste`, which is localised)
  - `enum ModifierLatch { off, oneShot, locked }`
  - `abstract interface class ModifierSource { bool get hasActiveModifiers; ({bool ctrl, bool alt}) consumeModifiers(); String applyModifiers(String text); }`
  - `final class ExtraKeysController implements ModifierSource { ExtraKeysController({DateTime Function()? now, Duration doubleTapWindow = const Duration(milliseconds: 400)}); ModifierLatch get ctrl; ModifierLatch get alt; Stream<void> get changes; void tapModifier(ExtraKey key); void sendKey(ExtraKey key, Terminal terminal); void dispose(); }`

Sticky semantics: off →(tap)→ one-shot; one-shot →(second tap within 400 ms)→ locked; one-shot →(slower tap)→ off (cancel); locked →(tap)→ off. A one-shot modifier is consumed by the next key from any source (extra key, soft keyboard, hardware keyboard); locked stays. Navigation keys go through `Terminal.keyInput` so xterm applies the cursor mode; characters go straight to `onOutput` because `ShellxTerminal.textInput` (Task 9) would apply the modifiers a second time.

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/terminal/extra_keys_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/terminal/extra_keys_controller.dart';
import 'package:shellx_mobile/terminal/terminal_input.dart';
import 'package:xterm/core.dart';

void main() {
  late DateTime now;
  late ExtraKeysController keys;
  late List<String> out;
  late Terminal terminal;

  void advance(int milliseconds) => now = now.add(Duration(milliseconds: milliseconds));

  String send(ExtraKey key) {
    out.clear();
    keys.sendKey(key, terminal);
    return out.join();
  }

  setUp(() {
    now = DateTime(2026, 9, 25);
    keys = ExtraKeysController(now: () => now);
    out = [];
    terminal = Terminal(inputHandler: shellxInputHandler, onOutput: out.add);
  });

  tearDown(() => keys.dispose());

  test('the row matches spec §9.3', () {
    expect(ExtraKey.values.map((k) => extraKeyLabel(k) ?? 'Dán').join(' '),
        'Esc Tab Ctrl Alt ↑ ↓ ← → | ~ / - Home End PgUp PgDn Dán');
  });

  group('sticky modifiers', () {
    test('one tap applies Ctrl to the next key only', () {
      keys.tapModifier(ExtraKey.ctrl);
      expect(keys.ctrl, ModifierLatch.oneShot);
      expect(keys.applyModifiers('c'), '\x03');
      expect(keys.ctrl, ModifierLatch.off);
      expect(keys.applyModifiers('c'), 'c');
    });

    test('a double tap locks until tapped again', () {
      keys.tapModifier(ExtraKey.ctrl);
      advance(200);
      keys.tapModifier(ExtraKey.ctrl);
      expect(keys.ctrl, ModifierLatch.locked);
      expect(keys.applyModifiers('c'), '\x03');
      expect(keys.applyModifiers('d'), '\x04');
      expect(keys.ctrl, ModifierLatch.locked);
      advance(5000);
      keys.tapModifier(ExtraKey.ctrl);
      expect(keys.ctrl, ModifierLatch.off);
      expect(keys.applyModifiers('c'), 'c');
    });

    test('the second tap must land inside the double-tap window', () {
      keys.tapModifier(ExtraKey.alt);
      advance(400);
      keys.tapModifier(ExtraKey.alt);
      expect(keys.alt, ModifierLatch.locked);

      keys.tapModifier(ExtraKey.alt); // unlock
      advance(1000);
      keys.tapModifier(ExtraKey.alt);
      advance(401);
      keys.tapModifier(ExtraKey.alt); // slow second tap cancels
      expect(keys.alt, ModifierLatch.off);
    });

    test('a quick tap after the one-shot was used arms a new one-shot, not a lock', () {
      keys.tapModifier(ExtraKey.ctrl);
      keys.applyModifiers('a');
      advance(100);
      keys.tapModifier(ExtraKey.ctrl);
      expect(keys.ctrl, ModifierLatch.oneShot);
    });

    test('Ctrl and Alt are independent and combine', () {
      keys.tapModifier(ExtraKey.ctrl);
      keys.tapModifier(ExtraKey.alt);
      expect(keys.applyModifiers('x'), '\x1b\x18');
      expect(keys.hasActiveModifiers, isFalse);
    });

    test('a locked Alt stays while a one-shot Ctrl is consumed', () {
      keys.tapModifier(ExtraKey.alt);
      keys.tapModifier(ExtraKey.alt);
      keys.tapModifier(ExtraKey.ctrl);
      expect(keys.consumeModifiers(), (ctrl: true, alt: true));
      expect(keys.consumeModifiers(), (ctrl: false, alt: true));
    });

    test('changes fires on taps and when a one-shot is consumed', () {
      var events = 0;
      keys.changes.listen((_) => events++);
      keys.tapModifier(ExtraKey.ctrl);
      keys.consumeModifiers();
      keys.consumeModifiers();
      expect(events, 2);
    });

    test('only Ctrl and Alt are modifiers', () {
      expect(() => keys.tapModifier(ExtraKey.esc), throwsArgumentError);
    });
  });

  group('sendKey through xterm key handling', () {
    test('navigation keys in normal and application cursor mode', () {
      expect(send(ExtraKey.up), '\x1b[A');
      expect(send(ExtraKey.down), '\x1b[B');
      expect(send(ExtraKey.right), '\x1b[C');
      expect(send(ExtraKey.left), '\x1b[D');
      expect(send(ExtraKey.home), '\x1b[H');
      expect(send(ExtraKey.end), '\x1b[F');
      expect(send(ExtraKey.pageUp), '\x1b[5~');
      expect(send(ExtraKey.pageDown), '\x1b[6~');
      expect(send(ExtraKey.esc), '\x1b');
      expect(send(ExtraKey.tab), '\t');

      terminal.write('\x1b[?1h'); // vim/htop/less enter application cursor mode
      expect(send(ExtraKey.up), '\x1bOA');
      expect(send(ExtraKey.left), '\x1bOD');
      expect(send(ExtraKey.home), '\x1bOH');
    });

    test('sticky modifiers reach navigation keys and are consumed', () {
      keys.tapModifier(ExtraKey.alt);
      expect(send(ExtraKey.left), '\x1b[1;3D');
      expect(send(ExtraKey.left), '\x1b[D');

      keys.tapModifier(ExtraKey.ctrl);
      advance(100);
      keys.tapModifier(ExtraKey.ctrl);
      expect(send(ExtraKey.right), '\x1b[1;5C');
      expect(send(ExtraKey.right), '\x1b[1;5C');
    });

    test('character keys', () {
      expect(send(ExtraKey.pipe), '|');
      expect(send(ExtraKey.tilde), '~');
      expect(send(ExtraKey.slash), '/');
      expect(send(ExtraKey.minus), '-');
      keys.tapModifier(ExtraKey.ctrl);
      expect(send(ExtraKey.slash), '\x1f');
      keys.tapModifier(ExtraKey.alt);
      expect(send(ExtraKey.tilde), '\x1b~');
      keys.tapModifier(ExtraKey.ctrl);
      expect(send(ExtraKey.pipe), '|');
      expect(keys.hasActiveModifiers, isFalse);
    });

    test('Ctrl, Alt and Paste are not sent as keys', () {
      expect(() => keys.sendKey(ExtraKey.ctrl, terminal), throwsArgumentError);
      expect(() => keys.sendKey(ExtraKey.paste, terminal), throwsArgumentError);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/mobile && flutter test test/terminal/extra_keys_controller_test.dart`
Expected: FAIL — `Error when reading 'lib/terminal/extra_keys_controller.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/mobile/lib/terminal/extra_keys_controller.dart`:

```dart
import 'dart:async';

import 'package:xterm/core.dart';

import 'terminal_input.dart';

/// The extra keys row of spec §9.3, in order.
enum ExtraKey { esc, tab, ctrl, alt, up, down, left, right, pipe, tilde, slash, minus, home, end, pageUp, pageDown, paste }

/// Fixed key cap text; [ExtraKey.paste] is localised ("Dán" / "Paste") by the UI.
String? extraKeyLabel(ExtraKey key) => switch (key) {
      ExtraKey.esc => 'Esc',
      ExtraKey.tab => 'Tab',
      ExtraKey.ctrl => 'Ctrl',
      ExtraKey.alt => 'Alt',
      ExtraKey.up => '↑',
      ExtraKey.down => '↓',
      ExtraKey.left => '←',
      ExtraKey.right => '→',
      ExtraKey.pipe => '|',
      ExtraKey.tilde => '~',
      ExtraKey.slash => '/',
      ExtraKey.minus => '-',
      ExtraKey.home => 'Home',
      ExtraKey.end => 'End',
      ExtraKey.pageUp => 'PgUp',
      ExtraKey.pageDown => 'PgDn',
      ExtraKey.paste => null,
    };

enum ModifierLatch { off, oneShot, locked }

/// Sticky modifiers that other input paths (soft keyboard, hardware keyboard)
/// must honour.
abstract interface class ModifierSource {
  bool get hasActiveModifiers;

  /// Returns the active modifiers and clears the one-shot ones.
  ({bool ctrl, bool alt}) consumeModifiers();

  /// [text] with the active modifiers applied; consumes one-shot modifiers.
  String applyModifiers(String text);
}

/// Pure-Dart state of the extra keys bar: sticky Ctrl/Alt and key dispatch.
///
/// Spec §9.3: tapping Ctrl/Alt once applies it to the next key only; a double
/// tap (second tap within [doubleTapWindow]) locks it until it is tapped
/// again. A slow second tap cancels a pending one-shot modifier.
final class ExtraKeysController implements ModifierSource {
  ExtraKeysController({
    DateTime Function()? now,
    this.doubleTapWindow = const Duration(milliseconds: 400),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration doubleTapWindow;
  final StreamController<void> _changes = StreamController<void>.broadcast(sync: true);
  ModifierLatch _ctrl = ModifierLatch.off;
  ModifierLatch _alt = ModifierLatch.off;
  DateTime? _ctrlTappedAt;
  DateTime? _altTappedAt;

  ModifierLatch get ctrl => _ctrl;
  ModifierLatch get alt => _alt;

  /// Emits whenever [ctrl] or [alt] changes.
  Stream<void> get changes => _changes.stream;

  void tapModifier(ExtraKey key) {
    final now = _now();
    switch (key) {
      case ExtraKey.ctrl:
        _ctrl = _nextLatch(_ctrl, _ctrlTappedAt, now);
        _ctrlTappedAt = now;
      case ExtraKey.alt:
        _alt = _nextLatch(_alt, _altTappedAt, now);
        _altTappedAt = now;
      default:
        throw ArgumentError.value(key, 'key', 'not a modifier key');
    }
    _changes.add(null);
  }

  ModifierLatch _nextLatch(ModifierLatch current, DateTime? lastTap, DateTime now) =>
      switch (current) {
        ModifierLatch.off => ModifierLatch.oneShot,
        ModifierLatch.oneShot => lastTap != null && now.difference(lastTap) <= doubleTapWindow
            ? ModifierLatch.locked
            : ModifierLatch.off,
        ModifierLatch.locked => ModifierLatch.off,
      };

  @override
  bool get hasActiveModifiers => _ctrl != ModifierLatch.off || _alt != ModifierLatch.off;

  @override
  ({bool ctrl, bool alt}) consumeModifiers() {
    final active = (ctrl: _ctrl != ModifierLatch.off, alt: _alt != ModifierLatch.off);
    var changed = false;
    if (_ctrl == ModifierLatch.oneShot) {
      _ctrl = ModifierLatch.off;
      changed = true;
    }
    if (_alt == ModifierLatch.oneShot) {
      _alt = ModifierLatch.off;
      changed = true;
    }
    if (changed) _changes.add(null);
    return active;
  }

  @override
  String applyModifiers(String text) {
    if (text.isEmpty || !hasActiveModifiers) return text;
    final active = consumeModifiers();
    return applyModifiersToText(text, ctrl: active.ctrl, alt: active.alt);
  }

  /// Sends a non-modifier, non-paste key to [terminal].
  ///
  /// Esc/Tab/arrows/Home/End/PgUp/PgDn go through [Terminal.keyInput] with
  /// the sticky modifiers, so xterm's application cursor mode and modifier
  /// encoding apply. Characters are emitted on [Terminal.onOutput] directly:
  /// `textInput` is where a ShellxTerminal applies modifiers again.
  void sendKey(ExtraKey key, Terminal terminal) {
    final terminalKey = switch (key) {
      ExtraKey.esc => TerminalKey.escape,
      ExtraKey.tab => TerminalKey.tab,
      ExtraKey.up => TerminalKey.arrowUp,
      ExtraKey.down => TerminalKey.arrowDown,
      ExtraKey.left => TerminalKey.arrowLeft,
      ExtraKey.right => TerminalKey.arrowRight,
      ExtraKey.home => TerminalKey.home,
      ExtraKey.end => TerminalKey.end,
      ExtraKey.pageUp => TerminalKey.pageUp,
      ExtraKey.pageDown => TerminalKey.pageDown,
      _ => null,
    };
    if (terminalKey != null) {
      final active = consumeModifiers();
      terminal.keyInput(terminalKey, ctrl: active.ctrl, alt: active.alt);
      return;
    }
    final char = switch (key) {
      ExtraKey.pipe => '|',
      ExtraKey.tilde => '~',
      ExtraKey.slash => '/',
      ExtraKey.minus => '-',
      _ => throw ArgumentError.value(key, 'key', 'use tapModifier() or paste instead'),
    };
    terminal.onOutput?.call(applyModifiers(char));
  }

  void dispose() => _changes.close();
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/terminal/extra_keys_controller_test.dart`
Expected: PASS — `All tests passed!` (13 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/terminal/extra_keys_controller.dart apps/mobile/test/terminal/extra_keys_controller_test.dart
git commit -m "feat(mobile): extra keys controller with sticky Ctrl/Alt"
```

---

### Task 9: `ShellxTerminal` (soft keyboard + sticky modifiers + paste) and the extra keys bar

**Files:**
- Create: `apps/mobile/lib/terminal/shellx_terminal.dart`, `apps/mobile/lib/terminal/extra_keys_bar.dart`
- Test: `apps/mobile/test/terminal/shellx_terminal_test.dart`, `apps/mobile/test/terminal/extra_keys_bar_test.dart`

**Interfaces:**
- Consumes: `Terminal` (`keyInput`, `textInput`, `paste`, `bracketedPasteMode`), `TerminalKey`; `ModifierSource`, `ExtraKeysController`, `ExtraKey`, `ModifierLatch`, `extraKeyLabel` (Task 8); `shellxInputHandler`, `normalizeTypedText`, `normalizePastedText` (Task 7); `AppLocalizations.keyPaste`.
- Produces:
  - `class ShellxTerminal extends Terminal { ShellxTerminal({required ModifierSource modifiers, int maxLines = 2000}); final ModifierSource modifiers; }` — overrides `keyInput` (applies pending sticky modifiers; returns `false` for text keys so `TerminalView` falls back to `textInput` with the typed character), `textInput` (Return → CR, then sticky modifiers), `paste` (CR line breaks, bracketed when enabled, never modified).
  - `class ExtraKeysBar extends StatefulWidget { const ExtraKeysBar({Key? key, required ExtraKeysController controller, required ValueChanged<ExtraKey> onKey, required VoidCallback onPaste}); }` — key caps keyed `ValueKey('extra-key-<name>')`; one-shot shows a dot (`ValueKey('latch-one-shot')`), locked a padlock (`ValueKey('latch-locked')`).

- [ ] **Step 1: Write the failing tests**

`apps/mobile/test/terminal/shellx_terminal_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/terminal/extra_keys_controller.dart';
import 'package:shellx_mobile/terminal/shellx_terminal.dart';
import 'package:xterm/core.dart';

void main() {
  late ExtraKeysController keys;
  late ShellxTerminal terminal;
  late List<String> out;

  setUp(() {
    keys = ExtraKeysController();
    out = [];
    terminal = ShellxTerminal(modifiers: keys)..onOutput = out.add;
  });

  tearDown(() => keys.dispose());

  /// What TerminalView does with a soft-keyboard character.
  void typeOnSoftKeyboard(String char, TerminalKey key) {
    if (!terminal.keyInput(key)) terminal.textInput(char);
  }

  test('soft keyboard: sticky Ctrl turns "c" into ^C', () {
    keys.tapModifier(ExtraKey.ctrl);
    typeOnSoftKeyboard('c', TerminalKey.keyC);
    expect(out, ['\x03']);
    expect(keys.hasActiveModifiers, isFalse);
  });

  test('soft keyboard: sticky Alt keeps the typed case', () {
    keys.tapModifier(ExtraKey.alt);
    typeOnSoftKeyboard('B', TerminalKey.keyB);
    expect(out, ['\x1bB']);
    keys.tapModifier(ExtraKey.alt);
    typeOnSoftKeyboard('b', TerminalKey.keyB);
    expect(out.last, '\x1bb');
  });

  test('soft keyboard without modifiers sends the text, Return as CR', () {
    typeOnSoftKeyboard('q', TerminalKey.keyQ);
    terminal.textInput('\n');
    terminal.textInput('xin chào');
    expect(out, ['q', '\r', 'xin chào']);
  });

  test('sticky Alt applies to non-text keys such as arrows', () {
    keys.tapModifier(ExtraKey.alt);
    expect(terminal.keyInput(TerminalKey.arrowLeft), isTrue);
    expect(out, ['\x1b[1;3D']);
    expect(keys.hasActiveModifiers, isFalse);
  });

  test('hardware Ctrl works on its own and leaves sticky modifiers alone', () {
    keys.tapModifier(ExtraKey.alt);
    expect(terminal.keyInput(TerminalKey.keyC, ctrl: true), isTrue);
    expect(out, ['\x03']);
    expect(keys.alt, ModifierLatch.oneShot);
  });

  test('application cursor mode comes from DECCKM', () {
    terminal.write('\x1b[?1h');
    terminal.keyInput(TerminalKey.arrowUp);
    expect(out, ['\x1bOA']);
  });

  test('paste: bracketed when enabled, CR line breaks, never modified', () {
    keys.tapModifier(ExtraKey.ctrl);
    terminal.paste('echo 1\necho 2');
    terminal.write('\x1b[?2004h');
    terminal.paste('a\r\nb');
    expect(out, ['echo 1\recho 2', '\x1b[200~a\rb\x1b[201~']);
    expect(keys.ctrl, ModifierLatch.oneShot);
  });
}
```

`apps/mobile/test/terminal/extra_keys_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/l10n/app_localizations.dart';
import 'package:shellx_mobile/terminal/extra_keys_bar.dart';
import 'package:shellx_mobile/terminal/extra_keys_controller.dart';
import 'package:shellx_mobile/terminal/shellx_terminal.dart';

void main() {
  late DateTime now;
  late ExtraKeysController keys;
  late ShellxTerminal terminal;
  late List<String> out;
  late int pastes;

  Widget bar() => MaterialApp(
        locale: const Locale('vi'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ExtraKeysBar(
              controller: keys,
              onKey: (key) => keys.sendKey(key, terminal),
              onPaste: () => pastes++,
            ),
          ),
        ),
      );

  Finder keyCap(ExtraKey key) => find.byKey(ValueKey('extra-key-${key.name}'));

  setUp(() {
    now = DateTime(2026, 9, 25);
    keys = ExtraKeysController(now: () => now);
    out = [];
    terminal = ShellxTerminal(modifiers: keys)..onOutput = out.add;
    pastes = 0;
  });

  tearDown(() => keys.dispose());

  testWidgets('shows every key of spec §9.3 with the localised Paste label', (tester) async {
    await tester.pumpWidget(bar());
    expect(find.text('Esc'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Dán').hitTestable(),
      100,
      scrollable: find.descendant(of: find.byType(ExtraKeysBar), matching: find.byType(Scrollable)),
    );
    expect(find.text('PgDn'), findsOneWidget);
    await tester.tap(find.text('Dán'));
    expect(pastes, 1);
  });

  testWidgets('tap Ctrl then type c on the soft keyboard sends ^C', (tester) async {
    await tester.pumpWidget(bar());
    await tester.tap(keyCap(ExtraKey.ctrl));
    await tester.pump();
    expect(find.descendant(of: keyCap(ExtraKey.ctrl), matching: find.byKey(const ValueKey('latch-one-shot'))),
        findsOneWidget);

    terminal.textInput('c');
    await tester.pump();
    expect(out, ['\x03']);
    expect(find.byKey(const ValueKey('latch-one-shot')), findsNothing);
  });

  testWidgets('double tap locks Ctrl, a third tap unlocks', (tester) async {
    await tester.pumpWidget(bar());
    await tester.tap(keyCap(ExtraKey.ctrl));
    now = now.add(const Duration(milliseconds: 150));
    await tester.tap(keyCap(ExtraKey.ctrl));
    await tester.pump();
    expect(find.descendant(of: keyCap(ExtraKey.ctrl), matching: find.byKey(const ValueKey('latch-locked'))),
        findsOneWidget);

    terminal.textInput('c');
    terminal.textInput('d');
    expect(out, ['\x03', '\x04']);

    now = now.add(const Duration(seconds: 2));
    await tester.tap(keyCap(ExtraKey.ctrl));
    await tester.pump();
    expect(find.byKey(const ValueKey('latch-locked')), findsNothing);
  });

  testWidgets('arrow key cap sends through xterm', (tester) async {
    await tester.pumpWidget(bar());
    await tester.tap(keyCap(ExtraKey.up));
    expect(out, ['\x1b[A']);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/mobile && flutter test test/terminal/shellx_terminal_test.dart test/terminal/extra_keys_bar_test.dart`
Expected: FAIL — `Error when reading 'lib/terminal/shellx_terminal.dart': No such file or directory`, `Error when reading 'lib/terminal/extra_keys_bar.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/mobile/lib/terminal/shellx_terminal.dart`:

```dart
import 'package:xterm/core.dart';

import 'extra_keys_controller.dart';
import 'terminal_input.dart';

/// Keys whose soft-keyboard text must reach [ShellxTerminal.textInput] so the
/// sticky modifiers keep the typed character's case.
const Set<TerminalKey> _textKeys = {
  TerminalKey.keyA, TerminalKey.keyB, TerminalKey.keyC, TerminalKey.keyD, TerminalKey.keyE,
  TerminalKey.keyF, TerminalKey.keyG, TerminalKey.keyH, TerminalKey.keyI, TerminalKey.keyJ,
  TerminalKey.keyK, TerminalKey.keyL, TerminalKey.keyM, TerminalKey.keyN, TerminalKey.keyO,
  TerminalKey.keyP, TerminalKey.keyQ, TerminalKey.keyR, TerminalKey.keyS, TerminalKey.keyT,
  TerminalKey.keyU, TerminalKey.keyV, TerminalKey.keyW, TerminalKey.keyX, TerminalKey.keyY,
  TerminalKey.keyZ, TerminalKey.digit0, TerminalKey.digit1, TerminalKey.digit2,
  TerminalKey.digit3, TerminalKey.digit4, TerminalKey.digit5, TerminalKey.digit6,
  TerminalKey.digit7, TerminalKey.digit8, TerminalKey.digit9, TerminalKey.space,
  TerminalKey.minus, TerminalKey.equal, TerminalKey.bracketLeft, TerminalKey.bracketRight,
  TerminalKey.backslash, TerminalKey.semicolon, TerminalKey.quote, TerminalKey.backquote,
  TerminalKey.comma, TerminalKey.period, TerminalKey.slash,
};

/// xterm [Terminal] that honours the extra keys bar's sticky Ctrl/Alt for
/// soft-keyboard and hardware-keyboard input.
///
/// `TerminalView` feeds soft-keyboard text as `keyInput(key)` first and falls
/// back to `textInput(text)` when that returns false; hardware keys arrive as
/// `keyInput(key, ctrl:, alt:, shift:)`.
class ShellxTerminal extends Terminal {
  ShellxTerminal({required this.modifiers, super.maxLines = 2000})
      : super(inputHandler: shellxInputHandler);

  final ModifierSource modifiers;

  @override
  bool keyInput(TerminalKey key, {bool shift = false, bool alt = false, bool ctrl = false}) {
    if (!ctrl && !alt && modifiers.hasActiveModifiers) {
      // Let TerminalView fall back to textInput() with the typed character.
      if (_textKeys.contains(key)) return false;
      final active = modifiers.consumeModifiers();
      return super.keyInput(key, shift: shift, ctrl: active.ctrl, alt: active.alt);
    }
    return super.keyInput(key, shift: shift, alt: alt, ctrl: ctrl);
  }

  @override
  void textInput(String text) => super.textInput(modifiers.applyModifiers(normalizeTypedText(text)));

  /// Spec §9.4: bracketed paste when the application enabled it. Pasted text
  /// never picks up sticky modifiers.
  @override
  void paste(String text) {
    final normalized = normalizePastedText(text);
    if (bracketedPasteMode) {
      super.paste(normalized);
    } else {
      super.textInput(normalized);
    }
  }
}
```

`apps/mobile/lib/terminal/extra_keys_bar.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'extra_keys_controller.dart';

/// The horizontally scrolling extra keys row shown right above the keyboard
/// (spec §9.3).
class ExtraKeysBar extends StatefulWidget {
  const ExtraKeysBar({super.key, required this.controller, required this.onKey, required this.onPaste});

  final ExtraKeysController controller;

  /// Every key except Ctrl, Alt and Paste.
  final ValueChanged<ExtraKey> onKey;
  final VoidCallback onPaste;

  @override
  State<ExtraKeysBar> createState() => _ExtraKeysBarState();
}

class _ExtraKeysBarState extends State<ExtraKeysBar> {
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.controller.changes.listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  void _press(ExtraKey key) {
    switch (key) {
      case ExtraKey.ctrl:
      case ExtraKey.alt:
        widget.controller.tapModifier(key);
      case ExtraKey.paste:
        widget.onPaste();
      default:
        widget.onKey(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          children: [
            for (final key in ExtraKey.values)
              _KeyCap(
                key: ValueKey('extra-key-${key.name}'),
                label: extraKeyLabel(key) ?? l10n.keyPaste,
                latch: switch (key) {
                  ExtraKey.ctrl => widget.controller.ctrl,
                  ExtraKey.alt => widget.controller.alt,
                  _ => null,
                },
                onTap: () => _press(key),
              ),
          ],
        ),
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({super.key, required this.label, required this.latch, required this.onTap});

  final String label;
  final ModifierLatch? latch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = latch != null && latch != ModifierLatch.off;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Material(
        color: active ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      color: active ? scheme.onPrimary : scheme.onSurface,
                    ),
                  ),
                  // One-shot: a dot; locked: a padlock.
                  if (latch == ModifierLatch.oneShot)
                    Container(
                      key: const ValueKey('latch-one-shot'),
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(color: scheme.onPrimary, shape: BoxShape.circle),
                    ),
                  if (latch == ModifierLatch.locked)
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Icon(Icons.lock, key: const ValueKey('latch-locked'), size: 12, color: scheme.onPrimary),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/terminal/shellx_terminal_test.dart test/terminal/extra_keys_bar_test.dart`
Expected: PASS — `All tests passed!` (11 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/terminal/shellx_terminal.dart apps/mobile/lib/terminal/extra_keys_bar.dart \
  apps/mobile/test/terminal/shellx_terminal_test.dart apps/mobile/test/terminal/extra_keys_bar_test.dart
git commit -m "feat(mobile): sticky modifiers for soft keyboard input and the extra keys bar"
```

---

### Task 10: `TerminalTabController` — bind a tab's events to an xterm terminal

**Files:**
- Create: `apps/mobile/lib/terminal/terminal_tab_controller.dart`
- Test: `apps/mobile/test/terminal/terminal_tab_controller_test.dart`

**Interfaces:**
- Consumes: `TabHandle`, `MachineSession` (Task 4); `TabEvent` subclasses `TabOutput(text)`, `TabReset()`, `TabExited(exitCode)`, `TabDetached(reason)`, `TabError(code, message)`, `AppErrorException`, `DetachReason`, `AppErrorCode`, `SessionInfo`; `ShellxTerminal`, `ModifierSource` (Tasks 8–9); `TerminalController` (`package:xterm/xterm.dart`).
- Produces:
  - `enum TabNotice { exited, sessionEnded, takenOver, closedByHost, failed }`, `final class TabBanner { const TabBanner(TabNotice notice, {int? exitCode, AppErrorCode? errorCode, String? detail}); }`
  - `final class TerminalTabController extends ChangeNotifier { TerminalTabController({required MachineSession machine, required TabHandle handle, required ModifierSource modifiers, required int cols, required int rows, Duration resizeDebounce = const Duration(milliseconds: 150)}); TerminalTabController.ended({required MachineSession machine, required SessionInfo session, required ModifierSource modifiers, Duration resizeDebounce}); final int id; final TerminalController selection; ShellxTerminal get terminal; TabBanner? get banner; bool get isLive; String get title; Future<void> reattach(); }`

Event mapping: `TabOutput` → `terminal.write`; `TabReset` → a fresh `ShellxTerminal` of the same size (xterm has no RIS); `TabExited` → "Phiên đã kết thúc (mã thoát N)" (kept "closed on the computer" when that came first); `TabDetached(takenOver)` → banner with "Gắn lại" (`reattach()` keeps the screen and the subscription — `shellx_client` re-attaches the same tab with `last_seq = received` and its catch-up output must not be dropped); `TabDetached(closedByHost)`; `TabError(sessionNotFound)` → "Phiên đã kết thúc" (Review Focus 1/overview RF 3); other `TabError` → reason in the tab (spawn_failed, spec §12). Input/resize only while live; resizes debounced 150 ms, deduplicated, never below 1×1 (Review Focus 2/overview RF 4). Title: OSC 0/2, else `"<shell> <index>"` (spec §7).

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/terminal/terminal_tab_controller_test.dart`:

```dart
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/terminal/extra_keys_controller.dart';
import 'package:shellx_mobile/terminal/terminal_tab_controller.dart';

import '../support/fakes.dart';

void main() {
  late FakeMachineSession machine;
  late FakeTabHandle handle;
  late ExtraKeysController keys;
  late TerminalTabController tab;

  String screen() => tab.terminal.buffer.getText().trim();

  setUp(() async {
    machine = FakeMachineSession(agentA);
    handle = await machine.openSession(cols: 80, rows: 24) as FakeTabHandle;
    keys = ExtraKeysController();
    tab = TerminalTabController(machine: machine, handle: handle, modifiers: keys, cols: 80, rows: 24);
  });

  tearDown(() {
    tab.dispose();
    keys.dispose();
  });

  test('output is written to the terminal, keys become input messages', () {
    handle.emit(const TabOutput('xin chào'));
    expect(screen(), 'xin chào');

    tab.terminal.textInput('ls\n');
    expect(utf8.decode(machine.inputs.single.data), 'ls\r');
    expect(machine.inputs.single.id, handle.id);
  });

  test('title falls back to "<shell> <index>", OSC title wins', () {
    expect(tab.title, 'zsh 1');
    handle.emit(const TabOutput('\x1b]2;vim notes.md\x07'));
    expect(tab.title, 'vim notes.md');
  });

  test('session.reset swaps in a clean terminal of the same size', () {
    tab.terminal.resize(100, 30);
    handle.emit(const TabOutput('stale output'));
    final before = tab.terminal;
    var notified = 0;
    tab.addListener(() => notified++);

    handle.emit(const TabReset());

    expect(tab.terminal, isNot(same(before)));
    expect(screen(), isEmpty);
    expect(tab.terminal.viewWidth, 100);
    expect(tab.terminal.viewHeight, 30);
    expect(notified, 1);
    handle.emit(const TabOutput('fresh'));
    expect(screen(), 'fresh');
  });

  test('resizes are debounced and deduplicated', () {
    fakeAsync((async) {
      tab.terminal.resize(90, 30);
      tab.terminal.resize(100, 40);
      async.elapse(const Duration(milliseconds: 149));
      expect(machine.resizes, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(machine.resizes, [(id: handle.id, cols: 100, rows: 40)]);

      tab.terminal.resize(100, 40);
      async.elapse(const Duration(seconds: 1));
      expect(machine.resizes, hasLength(1));
    });
  });

  test('Review Focus 4: a zero-sized viewport is never sent', () {
    fakeAsync((async) {
      tab.terminal.onResize!(0, 0, 0, 0);
      tab.terminal.onResize!(120, 0, 0, 0);
      async.elapse(const Duration(seconds: 1));
      expect(machine.resizes, isEmpty);
    });
  });

  test('exit shows a banner and stops input and resize', () {
    fakeAsync((async) {
      handle.emit(const TabExited(0));
      expect(tab.banner?.notice, TabNotice.exited);
      expect(tab.banner?.exitCode, 0);
      expect(tab.isLive, isFalse);

      tab.terminal.textInput('x');
      tab.terminal.resize(100, 40);
      async.elapse(const Duration(seconds: 1));
      expect(machine.inputs, isEmpty);
      expect(machine.resizes, isEmpty);
    });
  });

  test('closed on the computer stays the banner when session.exited follows', () {
    handle.emit(const TabDetached(DetachReason.closedByHost));
    handle.emit(const TabExited(0));
    expect(tab.banner?.notice, TabNotice.closedByHost);
  });

  test('spawn_failed keeps the reason for the banner', () {
    handle.emit(const TabError(AppErrorCode.spawnFailed, 'pwsh.exe not found'));
    expect(tab.banner?.notice, TabNotice.failed);
    expect(tab.banner?.errorCode, AppErrorCode.spawnFailed);
    expect(tab.banner?.detail, 'pwsh.exe not found');
  });

  test('Review Focus 3: session_not_found while reattaching ends the tab', () {
    handle.emit(const TabError(AppErrorCode.sessionNotFound, 'gone'));
    expect(tab.banner?.notice, TabNotice.sessionEnded);
    expect(tab.isLive, isFalse);
  });

  test('taken over → reattach attaches again with the current size and keeps the screen', () async {
    machine.sessions = [const SessionInfo(id: 101, index: 1, shell: 'zsh', createdAt: 0, attached: true)];
    tab.terminal.resize(100, 30);
    handle.emit(const TabOutput('before '));
    handle.emit(const TabDetached(DetachReason.takenOver));
    expect(tab.banner?.notice, TabNotice.takenOver);
    final before = tab.terminal;

    await tab.reattach();

    expect(machine.attached.single, (id: handle.id, cols: 100, rows: 30));
    expect(tab.banner, isNull);
    expect(tab.isLive, isTrue);
    expect(tab.terminal, same(before));
    machine.handle(handle.id).emit(const TabOutput('back'));
    expect(screen(), 'before back');
  });

  test('catch-up output sent while re-attaching is not lost', () async {
    handle.emit(const TabDetached(DetachReason.takenOver));
    // shellx_client returns the same tab and replays output before `attached`.
    machine.attachHook = (id) => handle.emit(const TabOutput('missed while away'));
    machine.reuseHandles = true;
    await tab.reattach();
    expect(screen(), 'missed while away');
  });

  test('reattach to a vanished session ends the tab', () async {
    handle.emit(const TabDetached(DetachReason.takenOver));
    machine.attachErrors[handle.id] = const AppErrorException(AppErrorCode.sessionNotFound, 'gone');
    await tab.reattach();
    expect(tab.banner?.notice, TabNotice.sessionEnded);
  });

  test('an ended placeholder tab is not live and drops input', () {
    final ended = TerminalTabController.ended(
      machine: machine,
      session: const SessionInfo(id: 7, index: 3, shell: 'bash', createdAt: 0, attached: false),
      modifiers: keys,
    );
    addTearDown(ended.dispose);
    expect(ended.banner?.notice, TabNotice.sessionEnded);
    expect(ended.title, 'bash 3');
    ended.terminal.textInput('x');
    expect(machine.inputs, isEmpty);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/mobile && flutter test test/terminal/terminal_tab_controller_test.dart`
Expected: FAIL — `Error when reading 'lib/terminal/terminal_tab_controller.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/mobile/lib/terminal/terminal_tab_controller.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:xterm/xterm.dart';

import '../backend/backend.dart';
import 'extra_keys_controller.dart';
import 'shellx_terminal.dart';

enum TabNotice { exited, sessionEnded, takenOver, closedByHost, failed }

/// Why a tab stopped being live; rendered over the terminal by the UI.
final class TabBanner {
  const TabBanner(this.notice, {this.exitCode, this.errorCode, this.detail});

  final TabNotice notice;
  final int? exitCode;
  final AppErrorCode? errorCode;
  final String? detail;
}

/// Binds one [TabHandle] to an xterm terminal: output → screen, keys → input,
/// size → resize, lifecycle events → [banner].
final class TerminalTabController extends ChangeNotifier {
  TerminalTabController({
    required MachineSession machine,
    required TabHandle handle,
    required ModifierSource modifiers,
    required int cols,
    required int rows,
    this.resizeDebounce = const Duration(milliseconds: 150),
  })  : _machine = machine,
        _modifiers = modifiers,
        id = handle.id,
        _shell = handle.shell,
        _index = handle.index {
    _terminal = _createTerminal(cols, rows);
    _lastSent = (cols: cols, rows: rows);
    _bind(handle);
  }

  /// Review Focus 3: attaching failed with `session_not_found` (the agent
  /// restarted). Shows "Phiên đã kết thúc" and can only be closed.
  TerminalTabController.ended({
    required MachineSession machine,
    required SessionInfo session,
    required ModifierSource modifiers,
    this.resizeDebounce = const Duration(milliseconds: 150),
  })  : _machine = machine,
        _modifiers = modifiers,
        id = session.id,
        _shell = session.shell,
        _index = session.index {
    _terminal = _createTerminal(80, 24);
    _banner = const TabBanner(TabNotice.sessionEnded);
  }

  final int id;
  final Duration resizeDebounce;
  final MachineSession _machine;
  final ModifierSource _modifiers;
  final String _shell;
  final int _index;

  /// Selection state for long-press copy (spec §9.4).
  final TerminalController selection = TerminalController();
  late ShellxTerminal _terminal;
  TabHandle? _handle;
  StreamSubscription<TabEvent>? _events;
  TabBanner? _banner;
  String? _oscTitle;
  Timer? _resizeTimer;
  ({int cols, int rows})? _lastSent;
  bool _disposed = false;

  /// Replaced by a fresh instance on `session.reset`.
  ShellxTerminal get terminal => _terminal;
  TabBanner? get banner => _banner;
  bool get isLive => _events != null && _banner == null;

  /// Spec §7: the terminal title (OSC 0/2) if the shell set one, else "`<shell> <index>`".
  String get title => _oscTitle ?? '$_shell $_index';

  ShellxTerminal _createTerminal(int cols, int rows) {
    final terminal = ShellxTerminal(modifiers: _modifiers)..resize(cols, rows);
    return terminal
      ..onOutput = _onUserInput
      ..onResize = _onResize
      ..onTitleChange = _onTitle;
  }

  void _bind(TabHandle handle) {
    _handle = handle;
    _events = handle.events.listen(_onEvent);
  }

  void _onEvent(TabEvent event) {
    switch (event) {
      case TabOutput(:final text):
        _terminal.write(text);
      case TabReset():
        _replaceTerminal(_terminal.viewWidth, _terminal.viewHeight);
        notifyListeners();
      case TabExited(:final exitCode):
        // "Closed on the computer" says more than the exit code that follows it.
        if (_banner?.notice != TabNotice.closedByHost) {
          _setBanner(TabBanner(TabNotice.exited, exitCode: exitCode));
        }
      case TabDetached(:final reason):
        _setBanner(TabBanner(
          reason == DetachReason.takenOver ? TabNotice.takenOver : TabNotice.closedByHost,
        ));
      case TabError(:final code, :final message):
        _setBanner(code == AppErrorCode.sessionNotFound
            ? const TabBanner(TabNotice.sessionEnded)
            : TabBanner(TabNotice.failed, errorCode: code, detail: message));
    }
  }

  void _setBanner(TabBanner banner) {
    _banner = banner;
    notifyListeners();
  }

  void _replaceTerminal(int cols, int rows) {
    _terminal = _createTerminal(cols, rows);
    selection.clearSelection();
  }

  void _onUserInput(String data) {
    if (!isLive) return;
    _machine.input(id, utf8.encode(data));
  }

  void _onResize(int cols, int rows, int pixelWidth, int pixelHeight) {
    // Coalesce the burst of sizes produced while the keyboard slides or the
    // phone rotates; only the final size is sent.
    _resizeTimer?.cancel();
    _resizeTimer = Timer(resizeDebounce, () => _sendResize(cols, rows));
  }

  /// Review Focus 4: never send a size below 1×1, never repeat the last size.
  void _sendResize(int cols, int rows) {
    if (_disposed || !isLive || cols < 1 || rows < 1) return;
    final size = (cols: cols, rows: rows);
    if (size == _lastSent) return;
    _lastSent = size;
    _machine.resize(id, cols, rows);
  }

  void _onTitle(String title) {
    _oscTitle = title.isEmpty ? null : title;
    notifyListeners();
  }

  /// After `taken_over`: attach this phone again (the other device gets
  /// `taken_over`). `shellx_client` re-attaches the same tab with
  /// `last_seq = received`, so the catch-up output arrives on the events we
  /// are still listening to and the current screen is kept; a `session.reset`
  /// replaces it as usual.
  Future<void> reattach() async {
    if (_banner?.notice != TabNotice.takenOver) return;
    final cols = _terminal.viewWidth;
    final rows = _terminal.viewHeight;
    try {
      final handle = await _machine.attach(id, cols: cols, rows: rows);
      if (!identical(handle, _handle)) {
        unawaited(_events?.cancel());
        _bind(handle);
      }
      _banner = null;
      _lastSent = (cols: cols, rows: rows);
      notifyListeners();
    } on AppErrorException catch (error) {
      if (error.code != AppErrorCode.sessionNotFound) rethrow;
      _setBanner(const TabBanner(TabNotice.sessionEnded));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _resizeTimer?.cancel();
    unawaited(_events?.cancel());
    selection.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/terminal/terminal_tab_controller_test.dart`
Expected: PASS — `All tests passed!` (13 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/terminal/terminal_tab_controller.dart apps/mobile/test/terminal/terminal_tab_controller_test.dart
git commit -m "feat(mobile): terminal tab controller for output, reset, resize and session banners"
```

---

### Task 11: Grid measurement and pinch-to-zoom

**Files:**
- Create: `apps/mobile/lib/terminal/terminal_metrics.dart`, `apps/mobile/lib/terminal/pinch_zoom.dart`
- Test: `apps/mobile/test/terminal/terminal_metrics_test.dart`

**Interfaces:**
- Consumes: `TerminalStyle({fontSize, fontFamily})`, `TerminalStyle.toTextStyle()` (`package:xterm/xterm.dart`); `AppSettings.minFontSize/maxFontSize` (Task 2).
- Produces:
  - `typedef TerminalGrid = ({int cols, int rows});`, `const TerminalGrid fallbackGrid = (cols: 80, rows: 24);`, `TerminalStyle shellxTerminalStyle(double fontSize)`, `TerminalGrid? measureTerminalGrid(Size size, TerminalStyle style, TextScaler textScaler)`
  - `final class PinchZoomTracker { PinchZoomTracker({double min = 8, double max = 32, double step = 0.5}); void down(int pointer, Offset position, double currentSize); double? move(int pointer, Offset position); void up(int pointer); }`, `class PinchToZoom extends StatefulWidget { const PinchToZoom({Key? key, required double fontSize, required ValueChanged<double> onFontSize, required Widget child}); }`

`measureTerminalGrid` mirrors xterm's `calcCharSize` (width of `"mmmmmmmmmm"` ÷ 10, paragraph height) to size `session.open`/`session.attach` before the new `TerminalView` is laid out; the first layout then corrects the size through `resize`. `PinchToZoom` listens to raw pointers (translucent `Listener`) so it never steals the terminal's scroll/selection gestures.

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/terminal/terminal_metrics_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/terminal/pinch_zoom.dart';
import 'package:shellx_mobile/terminal/terminal_metrics.dart';

void main() {
  group('measureTerminalGrid', () {
    // flutter_test renders every glyph as a square 1em wide.
    final style = shellxTerminalStyle(10);

    test('fits whole cells', () {
      // Cell = 10 px wide, 12 px tall (line height 1.2).
      expect(measureTerminalGrid(const Size(805, 250), style, TextScaler.noScaling), (cols: 80, rows: 20));
    });

    test('Review Focus 4: null when not even one cell fits', () {
      expect(measureTerminalGrid(const Size(805, 0), style, TextScaler.noScaling), isNull);
      expect(measureTerminalGrid(const Size(5, 400), style, TextScaler.noScaling), isNull);
    });

    test('text scaling makes cells bigger', () {
      expect(measureTerminalGrid(const Size(800, 240), style, const TextScaler.linear(2)), (cols: 40, rows: 10));
    });
  });

  group('PinchZoomTracker', () {
    test('spreading two fingers to twice the distance doubles the size', () {
      final tracker = PinchZoomTracker();
      tracker.down(1, const Offset(100, 100), 14);
      tracker.down(2, const Offset(200, 100), 14);
      expect(tracker.move(2, const Offset(300, 100)), 28);
    });

    test('rounds to 0.5 steps, clamps to 8..32, ignores sub-step moves', () {
      final tracker = PinchZoomTracker();
      tracker.down(1, Offset.zero, 14);
      tracker.down(2, const Offset(100, 0), 14);
      expect(tracker.move(2, const Offset(101, 0)), isNull); // 14.14 → 14.0
      expect(tracker.move(2, const Offset(104, 0)), 14.5); // 14.56 → 14.5
      expect(tracker.move(2, const Offset(1000, 0)), 32);
      expect(tracker.move(2, const Offset(1, 0)), 8);
    });

    test('one finger never zooms; a third finger pauses zooming', () {
      final tracker = PinchZoomTracker();
      tracker.down(1, Offset.zero, 14);
      expect(tracker.move(1, const Offset(500, 0)), isNull);
      tracker.down(2, const Offset(600, 0), 14);
      tracker.down(3, const Offset(50, 50), 14);
      expect(tracker.move(2, const Offset(900, 0)), isNull);
      tracker.up(3);
      // New baseline: pointer 1 at (500, 0), pointer 2 at (900, 0) → 400 px.
      expect(tracker.move(2, const Offset(1300, 0)), 28); // 800 px → ×2
    });
  });

  testWidgets('PinchToZoom reports the pinched font size', (tester) async {
    final sizes = <double>[];
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: PinchToZoom(
        fontSize: 14,
        onFontSize: sizes.add,
        child: const SizedBox.expand(),
      ),
    ));
    final first = await tester.startGesture(const Offset(300, 300), pointer: 1);
    final second = await tester.startGesture(const Offset(400, 300), pointer: 2);
    await second.moveTo(const Offset(500, 300));
    await first.up();
    await second.up();
    expect(sizes.last, 28);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/mobile && flutter test test/terminal/terminal_metrics_test.dart`
Expected: FAIL — `Error when reading 'lib/terminal/pinch_zoom.dart': No such file or directory`, `Error when reading 'lib/terminal/terminal_metrics.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/mobile/lib/terminal/terminal_metrics.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';

typedef TerminalGrid = ({int cols, int rows});

/// Used when the viewport cannot fit one cell yet (Review Focus 4): the real
/// size follows as a `resize` as soon as the terminal is laid out.
const TerminalGrid fallbackGrid = (cols: 80, rows: 24);

/// JetBrains Mono, bundled (spec §9.1).
TerminalStyle shellxTerminalStyle(double fontSize) =>
    TerminalStyle(fontSize: fontSize, fontFamily: 'JetBrainsMono');

/// Columns × rows of [style] cells that fit in [size], measured the way
/// xterm's RenderTerminal measures a cell (width of "mmmmmmmmmm" / 10, line
/// height). Null when not even one column or row fits.
TerminalGrid? measureTerminalGrid(Size size, TerminalStyle style, TextScaler textScaler) {
  final painter = TextPainter(
    text: TextSpan(text: 'mmmmmmmmmm', style: style.toTextStyle()),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();
  final cellWidth = painter.width / 10;
  final cellHeight = painter.height;
  painter.dispose();
  if (cellWidth <= 0 || cellHeight <= 0) return null;
  final cols = (size.width / cellWidth).floor();
  final rows = (size.height / cellHeight).floor();
  if (cols < 1 || rows < 1) return null;
  return (cols: cols, rows: rows);
}
```

`apps/mobile/lib/terminal/pinch_zoom.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../settings/app_settings.dart';

/// Two-finger pinch → terminal font size (spec §9.4). Pure logic fed with
/// raw pointer events, so it never competes with the terminal's own scroll
/// and selection gestures.
final class PinchZoomTracker {
  PinchZoomTracker({
    this.min = AppSettings.minFontSize,
    this.max = AppSettings.maxFontSize,
    this.step = 0.5,
  });

  final double min;
  final double max;
  final double step;
  final Map<int, Offset> _pointers = {};
  double? _startDistance;
  double _startSize = 0;
  double _current = 0;

  void down(int pointer, Offset position, double currentSize) {
    _pointers[pointer] = position;
    _current = currentSize;
    _rebaseline();
  }

  /// The new font size, or null when it did not change by a whole [step].
  double? move(int pointer, Offset position) {
    if (!_pointers.containsKey(pointer)) return null;
    _pointers[pointer] = position;
    final start = _startDistance;
    if (start == null || start == 0) return null;
    final raw = _startSize * _distance() / start;
    final size = ((raw / step).round() * step).clamp(min, max).toDouble();
    if (size == _current) return null;
    _current = size;
    return size;
  }

  void up(int pointer) {
    _pointers.remove(pointer);
    _rebaseline();
  }

  void _rebaseline() {
    if (_pointers.length == 2) {
      _startDistance = _distance();
      _startSize = _current;
    } else {
      _startDistance = null;
    }
  }

  double _distance() {
    final points = _pointers.values.toList();
    return (points[0] - points[1]).distance;
  }
}

class PinchToZoom extends StatefulWidget {
  const PinchToZoom({super.key, required this.fontSize, required this.onFontSize, required this.child});

  final double fontSize;
  final ValueChanged<double> onFontSize;
  final Widget child;

  @override
  State<PinchToZoom> createState() => _PinchToZoomState();
}

class _PinchToZoomState extends State<PinchToZoom> {
  final PinchZoomTracker _tracker = PinchZoomTracker();

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Observe pointers without taking them from the terminal's own gestures.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _tracker.down(event.pointer, event.position, widget.fontSize),
      onPointerMove: (event) {
        final size = _tracker.move(event.pointer, event.position);
        if (size != null) widget.onFontSize(size);
      },
      onPointerUp: (event) => _tracker.up(event.pointer),
      onPointerCancel: (event) => _tracker.up(event.pointer),
      child: widget.child,
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/terminal/terminal_metrics_test.dart`
Expected: PASS — `All tests passed!` (7 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/terminal/terminal_metrics.dart apps/mobile/lib/terminal/pinch_zoom.dart \
  apps/mobile/test/terminal/terminal_metrics_test.dart
git commit -m "feat(mobile): terminal grid measurement and pinch-to-zoom font size"
```

---

### Task 12: `TerminalWorkspace` — the tabs of one machine

**Files:**
- Create: `apps/mobile/lib/terminal/terminal_workspace.dart`
- Test: `apps/mobile/test/terminal/terminal_workspace_test.dart`

**Interfaces:**
- Consumes: `MachineSession`, `ShellxBackend.machine` (Task 4); `MachineReady`, `MachineFailed`, `AppErrorException`, `AppErrorCode`, `SessionInfo`; `ExtraKeysController` (Task 8); `TerminalTabController` (Task 10); `TerminalGrid` (Task 11).
- Produces:
  - `final class TerminalWorkspace extends ChangeNotifier { TerminalWorkspace({required MachineSession machine, ExtraKeysController? extraKeys}); final MachineSession machine; final ExtraKeysController extraKeys; List<TerminalTabController> get tabs; int get activeIndex; TerminalTabController? get activeTab; void select(int index); Future<void> ensureConnected(); Future<List<SessionInfo>?> prepare(); Future<TerminalTabController> openNew(TerminalGrid grid); Future<TerminalTabController> attach(SessionInfo session, TerminalGrid grid); Future<void> close(TerminalTabController tab); }`
  - `final class WorkspaceRegistry { WorkspaceRegistry(ShellxBackend backend); TerminalWorkspace forMachine(String agentId); void remove(String agentId); void dispose(); }`

`ensureConnected()` normalises the contract's "ném theo MachineFailed" (overview §5.7; plan 03 throws `MachineConnectionException` after setting `MachineFailed`): whatever `connect()` throws, the `MachineFailed` state is rethrown so the UI can map it — requests made later (`openSession`, `attach`, `listSessions`) may still throw `MachineConnectionException`, which `ErrorText` and the screen also handle. `prepare()` sends `session.list` only on the first visit of a machine in this sign-in (spec §9.2 #4). The registry keeps workspaces alive across screen visits so terminals keep receiving output (spec §9.4).

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/terminal/terminal_workspace_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/terminal/terminal_tab_controller.dart';
import 'package:shellx_mobile/terminal/terminal_workspace.dart';

import '../support/fakes.dart';

void main() {
  const grid = (cols: 80, rows: 24);
  const running = SessionInfo(id: 7, index: 1, shell: 'zsh', createdAt: 1790000000000, attached: false);
  late FakeBackend backend;
  late FakeMachineSession machine;
  late WorkspaceRegistry registry;
  late TerminalWorkspace workspace;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    registry = WorkspaceRegistry(backend);
    workspace = registry.forMachine(agentA);
  });

  tearDown(() => registry.dispose());

  test('the registry returns one workspace per machine and refuses unpinned ones', () {
    expect(registry.forMachine(agentA), same(workspace));
    expect(() => registry.forMachine(agentB), throwsStateError);
  });

  test('prepare connects and lists sessions only on the first visit', () async {
    machine.sessions = [running];
    expect(await workspace.prepare(), [running]);
    expect(await workspace.prepare(), isNull);
    expect(machine.connectCalls, 1);
    expect(machine.listCalls, 1);
  });

  test('prepare throws the MachineFailed state for an untrusted machine', () async {
    machine.connectFailure = MachineConnectionFailure.untrusted;
    await expectLater(
      workspace.prepare(),
      throwsA(isA<MachineFailed>().having((s) => s.failure, 'failure', MachineConnectionFailure.untrusted)),
    );
  });

  test('openNew opens with the grid and activates the new tab', () async {
    final first = await workspace.openNew(grid);
    final second = await workspace.openNew((cols: 100, rows: 30));
    expect(machine.opened, [(cols: 80, rows: 24), (cols: 100, rows: 30)]);
    expect(workspace.tabs, [first, second]);
    expect(workspace.activeTab, same(second));
    workspace.select(0);
    expect(workspace.activeTab, same(first));
  });

  test('session_limit surfaces as AppErrorException and adds no tab', () async {
    machine.openError = const AppErrorException(AppErrorCode.sessionLimit, 'limit');
    await expectLater(workspace.openNew(grid), throwsA(isA<AppErrorException>()));
    expect(workspace.tabs, isEmpty);
  });

  test('attach adds a live tab; attaching the same session again just selects it', () async {
    machine.sessions = [running];
    final tab = await workspace.attach(running, grid);
    await workspace.openNew(grid);
    expect(await workspace.attach(running, grid), same(tab));
    expect(workspace.activeTab, same(tab));
    expect(machine.attached, hasLength(1));
    expect(tab.isLive, isTrue);
  });

  test('Review Focus 3: attach → session_not_found gives a closable "ended" tab', () async {
    machine.attachErrors[running.id] = const AppErrorException(AppErrorCode.sessionNotFound, 'gone');
    final tab = await workspace.attach(running, grid);
    expect(tab.banner?.notice, TabNotice.sessionEnded);
    expect(workspace.tabs, [tab]);

    await workspace.close(tab);
    expect(workspace.tabs, isEmpty);
  });

  test('close sends session.close, keeps a valid selection, ignores machine errors', () async {
    final a = await workspace.openNew(grid);
    final b = await workspace.openNew(grid);
    await workspace.close(b);
    expect(machine.closed, [b.id]);
    expect(workspace.activeTab, same(a));
    await workspace.close(a);
    expect(workspace.activeTab, isNull);
  });

  test('remove disposes the workspace of an unpaired machine', () async {
    await workspace.openNew(grid);
    registry.remove(agentA);
    backend.addMachine(agentA);
    expect(registry.forMachine(agentA), isNot(same(workspace)));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/mobile && flutter test test/terminal/terminal_workspace_test.dart`
Expected: FAIL — `Error when reading 'lib/terminal/terminal_workspace.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/mobile/lib/terminal/terminal_workspace.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';

import '../backend/backend.dart';
import 'extra_keys_controller.dart';
import 'terminal_metrics.dart';
import 'terminal_tab_controller.dart';

/// The tabs of one machine. Outlives its screen so terminals keep receiving
/// output while the user is elsewhere in the app (spec §9.4).
final class TerminalWorkspace extends ChangeNotifier {
  TerminalWorkspace({required this.machine, ExtraKeysController? extraKeys})
      : extraKeys = extraKeys ?? ExtraKeysController();

  final MachineSession machine;
  final ExtraKeysController extraKeys;
  final List<TerminalTabController> _tabs = [];
  int _active = 0;
  bool _listedSessions = false;

  List<TerminalTabController> get tabs => List.unmodifiable(_tabs);
  int get activeIndex => _active;
  TerminalTabController? get activeTab => _tabs.isEmpty ? null : _tabs[_active];

  void select(int index) {
    if (index < 0 || index >= _tabs.length || index == _active) return;
    _active = index;
    notifyListeners();
  }

  /// Runs the IK handshake when needed. Throws the [MachineFailed] state
  /// (untrusted, protocolUnsupported, agentOffline, timeout).
  Future<void> ensureConnected() async {
    if (machine.state is MachineReady) return;
    try {
      await machine.connect();
    } catch (error) {
      if (error is MachineFailed) rethrow;
      final state = machine.state;
      if (state is MachineFailed) throw state;
      rethrow;
    }
  }

  /// Spec §9.2 #4: the first time the machine screen opens, send
  /// `session.list`. Returns the sessions not shown as tabs yet, or null on
  /// later visits.
  Future<List<SessionInfo>?> prepare() async {
    await ensureConnected();
    if (_listedSessions) return null;
    final sessions = await machine.listSessions();
    _listedSessions = true;
    return [for (final session in sessions) if (!_tabs.any((tab) => tab.id == session.id)) session];
  }

  /// Throws [AppErrorException] (`session_limit`, `spawn_failed`).
  Future<TerminalTabController> openNew(TerminalGrid grid) async {
    await ensureConnected();
    final handle = await machine.openSession(cols: grid.cols, rows: grid.rows);
    return _add(TerminalTabController(
      machine: machine,
      handle: handle,
      modifiers: extraKeys,
      cols: grid.cols,
      rows: grid.rows,
    ));
  }

  /// Attaches an existing session. Review Focus 3: when the session is gone
  /// (`session_not_found`), the tab still appears, showing "Phiên đã kết thúc".
  Future<TerminalTabController> attach(SessionInfo session, TerminalGrid grid) async {
    final existing = _tabs.indexWhere((tab) => tab.id == session.id);
    if (existing >= 0) {
      select(existing);
      return _tabs[existing];
    }
    await ensureConnected();
    try {
      final handle = await machine.attach(session.id, cols: grid.cols, rows: grid.rows);
      return _add(TerminalTabController(
        machine: machine,
        handle: handle,
        modifiers: extraKeys,
        cols: grid.cols,
        rows: grid.rows,
      ));
    } on AppErrorException catch (error) {
      if (error.code != AppErrorCode.sessionNotFound) rethrow;
      return _add(TerminalTabController.ended(machine: machine, session: session, modifiers: extraKeys));
    }
  }

  TerminalTabController _add(TerminalTabController tab) {
    _tabs.add(tab);
    _active = _tabs.length - 1;
    notifyListeners();
    return tab;
  }

  /// `×`: sends `session.close` (spec §6.4) and drops the tab. Errors from an
  /// already-ended session are ignored — the tab must always be closable.
  Future<void> close(TerminalTabController tab) async {
    final index = _tabs.indexOf(tab);
    if (index < 0) return;
    _tabs.removeAt(index);
    if (_active >= _tabs.length) _active = _tabs.isEmpty ? 0 : _tabs.length - 1;
    notifyListeners();
    tab.dispose();
    try {
      await machine.closeTab(tab.id);
    } on Object {
      // The session no longer exists on the machine.
    }
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.dispose();
    }
    _tabs.clear();
    extraKeys.dispose();
    super.dispose();
  }
}

/// One [TerminalWorkspace] per machine for the signed-in account.
final class WorkspaceRegistry {
  WorkspaceRegistry(this._backend);

  final ShellxBackend _backend;
  final Map<String, TerminalWorkspace> _workspaces = {};

  /// Throws [StateError] when [agentId] is not pinned.
  TerminalWorkspace forMachine(String agentId) =>
      _workspaces.putIfAbsent(agentId, () => TerminalWorkspace(machine: _backend.machine(agentId)));

  /// After unpairing (spec §5.5) or when the machine stops trusting us.
  void remove(String agentId) => _workspaces.remove(agentId)?.dispose();

  void dispose() {
    for (final workspace in _workspaces.values) {
      workspace.dispose();
    }
    _workspaces.clear();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/terminal/terminal_workspace_test.dart`
Expected: PASS — `All tests passed!` (9 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/terminal/terminal_workspace.dart apps/mobile/test/terminal/terminal_workspace_test.dart
git commit -m "feat(mobile): per-machine terminal workspace with session list, attach and close"
```

---

### Task 13: Terminal screen — tabs, session picker, xterm view, extra keys, copy/paste, banners

**Files:**
- Create: `apps/mobile/lib/widgets/connection_banner.dart`, `apps/mobile/lib/terminal/session_picker.dart`, `apps/mobile/lib/terminal/terminal_screen.dart`, `apps/mobile/test/support/app_harness.dart`
- Test: `apps/mobile/test/terminal/terminal_screen_test.dart`

**Interfaces:**
- Consumes: `ShellxBackend` (Task 4); `ErrorText` (Task 3); `ExtraKeysBar` (Task 9); `TerminalTabController`, `TabBanner`, `TabNotice` (Task 10); `measureTerminalGrid`, `fallbackGrid`, `shellxTerminalStyle`, `PinchToZoom` (Task 11); `TerminalWorkspace`, `WorkspaceRegistry` (Task 12); `terminalShortcuts` (Task 7); `TerminalView` (`xterm`); `Clipboard`; `DateFormat.Hm` (`intl`).
- Produces:
  - `class ConnectionBanner extends StatefulWidget { const ConnectionBanner({Key? key, required ShellxBackend backend, required VoidCallback onReconnectReplaced}); }` — "Mất kết nối, đang thử lại…" while disconnected/reconnecting (not during the very first connect), "Một phiên bản khác của app đã kết nối." + "Kết nối lại" after 4001.
  - `sealed class SessionChoice`, `final class AttachSession extends SessionChoice { const AttachSession(SessionInfo session); }`, `final class OpenNewSession extends SessionChoice { const OpenNewSession(); }`, `Future<SessionChoice?> showSessionPicker(BuildContext context, List<SessionInfo> sessions)`
  - `class TerminalScreen extends StatefulWidget { const TerminalScreen({Key? key, required ShellxBackend backend, required WorkspaceRegistry registry, required String agentId, required String machineName, required double initialFontSize, required VoidCallback onReconnectReplaced}); }`
  - Test support (`test/support/app_harness.dart`): `Widget pushingHost(WidgetBuilder screen, {Locale locale})`, `Widget localized(Widget home, {Locale locale})`, `Future<void> openPushed(WidgetTester tester)`.

Screen behaviour (spec §9.2 #4, §9.4, §12): first visit → connect + `session.list`; no running sessions → open one automatically, otherwise the picker (attach or new); the app-bar list icon shows the picker again; `+` opens, `×` closes (confirmation for live sessions, none for ended ones); tabs keyed `ValueKey('tab-<id>')`; the active tab renders a `TerminalView` (JetBrains Mono, `deleteDetection`, platform shortcuts, read-only when not live) inside `PinchToZoom`; long-press selection shows a "Sao chép" button; the bar's "Dán" pastes the clipboard through `ShellxTerminal.paste`; tab banners with "Đóng" (and "Gắn lại" after takeover); `MachineFailed(untrusted)` → message, unpair, pop; `session_limit` → spec message.

- [ ] **Step 1: Write the widget test harness**

`apps/mobile/test/support/app_harness.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/l10n/app_localizations.dart';

/// MaterialApp in Vietnamese whose home pushes [screen] when "open" is tapped,
/// so tests can observe the screen popping itself.
Widget pushingHost(WidgetBuilder screen, {Locale locale = const Locale('vi')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: screen)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

Widget localized(Widget home, {Locale locale = const Locale('vi')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

Future<void> openPushed(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 2: Write the failing widget tests**

`apps/mobile/test/terminal/terminal_screen_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/terminal/extra_keys_bar.dart';
import 'package:shellx_mobile/terminal/terminal_screen.dart';
import 'package:shellx_mobile/terminal/terminal_workspace.dart';

import '../support/app_harness.dart';
import '../support/fakes.dart';

void main() {
  const running = SessionInfo(id: 7, index: 1, shell: 'zsh', createdAt: 1790000000000, attached: true);
  late FakeBackend backend;
  late FakeMachineSession machine;
  late WorkspaceRegistry registry;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    registry = WorkspaceRegistry(backend);
  });

  tearDown(() => registry.dispose());

  Widget app() => pushingHost((_) => TerminalScreen(
        backend: backend,
        registry: registry,
        agentId: agentA,
        machineName: 'MacBook-Pro',
        initialFontSize: 14,
        onReconnectReplaced: () {},
      ));

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await openPushed(tester);
  }

  String lastInput() => utf8.decode(machine.inputs.last.data);

  testWidgets('first open without sessions opens a tab automatically', (tester) async {
    await open(tester);
    expect(machine.listCalls, 1);
    expect(machine.opened, hasLength(1));
    expect(machine.opened.single.cols, greaterThanOrEqualTo(1));
    expect(machine.opened.single.rows, greaterThanOrEqualTo(1));
    expect(find.text('zsh 1'), findsOneWidget);

    machine.handles.single.emit(const TabOutput('hello'));
    expect(registry.forMachine(agentA).activeTab!.terminal.buffer.getText(), contains('hello'));
  });

  testWidgets('first open lists running sessions and attaches the chosen one; later visits do not list',
      (tester) async {
    machine.sessions = [running];
    await open(tester);
    expect(find.text('Phiên đang chạy trên máy'), findsOneWidget);
    expect(find.textContaining('Đang mở trên thiết bị khác'), findsOneWidget);

    await tester.tap(find.text('Gắn'));
    await tester.pumpAndSettle();
    expect(machine.attached.single.id, 7);
    expect(find.text('zsh 1'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await openPushed(tester);
    expect(machine.listCalls, 1);
    expect(find.text('Phiên đang chạy trên máy'), findsNothing);
    expect(find.text('zsh 1'), findsOneWidget);
  });

  testWidgets('+ opens another tab; × asks before closing a live session', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Phiên mới'));
    await tester.pumpAndSettle();
    expect(find.text('zsh 2'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('tab-102')), matching: find.byTooltip('Đóng phiên')));
    await tester.pumpAndSettle();
    expect(find.text('Đóng phiên này? Mọi chương trình đang chạy trong phiên sẽ bị dừng.'), findsOneWidget);
    await tester.tap(find.text('Đóng phiên'));
    await tester.pumpAndSettle();
    expect(machine.closed, [102]);
    expect(find.text('zsh 2'), findsNothing);
  });

  testWidgets('Review Focus 3: a session that vanished shows "Phiên đã kết thúc" and can be closed',
      (tester) async {
    machine.sessions = [running];
    machine.attachErrors[7] = const AppErrorException(AppErrorCode.sessionNotFound, 'gone');
    await open(tester);
    await tester.tap(find.text('Gắn'));
    await tester.pumpAndSettle();

    expect(find.text('Phiên đã kết thúc'), findsOneWidget);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(find.text('Phiên đã kết thúc'), findsNothing);
    expect(find.text('zsh 1'), findsNothing);
    expect(machine.closed, [7]);
  });

  testWidgets('a reattached tab that the agent no longer knows ends the same way', (tester) async {
    await open(tester);
    machine.handles.single.emit(const TabError(AppErrorCode.sessionNotFound, 'gone'));
    await tester.pump();
    expect(find.text('Phiên đã kết thúc'), findsOneWidget);
  });

  testWidgets('exit code and spawn failure banners', (tester) async {
    await open(tester);
    machine.handles.single.emit(const TabExited(0));
    await tester.pump();
    expect(find.text('Phiên đã kết thúc (mã thoát 0)'), findsOneWidget);

    await tester.tap(find.byTooltip('Phiên mới'));
    await tester.pumpAndSettle();
    machine.handles.last.emit(const TabError(AppErrorCode.spawnFailed, 'pwsh.exe not found'));
    await tester.pump();
    expect(find.text('Không mở được shell: pwsh.exe not found'), findsOneWidget);
  });

  testWidgets('session_limit shows the spec message', (tester) async {
    await open(tester);
    machine.openError = const AppErrorException(AppErrorCode.sessionLimit, 'limit');
    await tester.tap(find.byTooltip('Phiên mới'));
    await tester.pump();
    expect(find.text('Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên.'), findsOneWidget);
  });

  testWidgets('an untrusted machine is unpaired and the screen closes (spec §12)', (tester) async {
    machine.connectFailure = MachineConnectionFailure.untrusted;
    await open(tester);
    await tester.pumpAndSettle();
    expect(find.text('Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.'), findsOneWidget);
    expect(backend.unpaired, [agentA]);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('extra keys and paste reach the active session', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return <String, Object?>{'text': 'echo 1\necho 2'};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('extra-key-up')));
    expect(lastInput(), '\x1b[A');

    machine.handles.single.emit(const TabOutput('\x1b[?1h'));
    await tester.tap(find.byKey(const ValueKey('extra-key-up')));
    expect(lastInput(), '\x1bOA');

    await tester.scrollUntilVisible(
      find.text('Dán').hitTestable(),
      100,
      scrollable: find.descendant(of: find.byType(ExtraKeysBar), matching: find.byType(Scrollable)),
    );
    await tester.tap(find.text('Dán'));
    await tester.pumpAndSettle();
    expect(lastInput(), 'echo 1\recho 2');
  });

  testWidgets('shows the reconnecting banner when the relay drops', (tester) async {
    await open(tester);
    backend.emitRelay(RelayConnectionState.disconnected);
    await tester.pump();
    expect(find.text('Mất kết nối, đang thử lại…'), findsOneWidget);
    backend.emitRelay(RelayConnectionState.connected);
    await tester.pump();
    expect(find.text('Mất kết nối, đang thử lại…'), findsNothing);
    await tester.pump(const Duration(seconds: 1)); // let the debounced resize fire
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `cd apps/mobile && flutter test test/terminal/terminal_screen_test.dart`
Expected: FAIL — `Error when reading 'lib/terminal/terminal_screen.dart': No such file or directory`.

- [ ] **Step 4: Implement**

`apps/mobile/lib/widgets/connection_banner.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shellx_core/shellx_core.dart';

import '../backend/backend.dart';
import '../l10n/app_localizations.dart';

/// Spec §12: "Mất kết nối, đang thử lại…" while the relay reconnects, and a
/// manual "Kết nối lại" after close code 4001 (no automatic reconnect).
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({super.key, required this.backend, required this.onReconnectReplaced});

  final ShellxBackend backend;
  final VoidCallback onReconnectReplaced;

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  StreamSubscription<RelayConnectionState>? _subscription;
  late RelayConnectionState _state;

  /// The first `connecting` after launch is not a lost connection.
  bool _hadConnectionOrFailure = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(ConnectionBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backend != widget.backend) {
      _subscription?.cancel();
      _hadConnectionOrFailure = false;
      _subscribe();
    }
  }

  void _subscribe() {
    _observe(widget.backend.relayState);
    _subscription = widget.backend.relayStates.listen((state) => setState(() => _observe(state)));
  }

  void _observe(RelayConnectionState state) {
    _state = state;
    if (state == RelayConnectionState.connected || state == RelayConnectionState.disconnected) {
      _hadConnectionOrFailure = true;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final reconnecting = _state == RelayConnectionState.disconnected ||
        (_state == RelayConnectionState.connecting && _hadConnectionOrFailure);
    if (!reconnecting && _state != RelayConnectionState.replaced) return const SizedBox.shrink();
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (reconnecting) ...[
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onErrorContainer),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                reconnecting ? l10n.bannerReconnecting : l10n.bannerReplaced,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (!reconnecting)
              TextButton(onPressed: widget.onReconnectReplaced, child: Text(l10n.bannerReconnectButton)),
          ],
        ),
      ),
    );
  }
}
```

`apps/mobile/lib/terminal/session_picker.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shellx_core/shellx_core.dart';

import '../l10n/app_localizations.dart';

sealed class SessionChoice {
  const SessionChoice();
}

final class AttachSession extends SessionChoice {
  const AttachSession(this.session);
  final SessionInfo session;
}

final class OpenNewSession extends SessionChoice {
  const OpenNewSession();
}

/// Spec §9.2 #4: lets the user attach to sessions already running on the
/// machine. Returns null when dismissed.
Future<SessionChoice?> showSessionPicker(BuildContext context, List<SessionInfo> sessions) {
  return showModalBottomSheet<SessionChoice>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      final time = DateFormat.Hm(Localizations.localeOf(context).toLanguageTag());
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(l10n.pickerTitle, style: Theme.of(context).textTheme.titleMedium)),
            for (final session in sessions)
              ListTile(
                leading: const Icon(Icons.terminal),
                title: Text('${session.shell} ${session.index}'),
                subtitle: Text([
                  l10n.pickerStartedAt(time.format(DateTime.fromMillisecondsSinceEpoch(session.createdAt))),
                  if (session.attached) l10n.pickerAttachedElsewhere,
                ].join(' · ')),
                trailing: FilledButton.tonal(
                  onPressed: () => Navigator.pop(context, AttachSession(session)),
                  child: Text(l10n.pickerAttach),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l10n.terminalOpenNew),
              onTap: () => Navigator.pop(context, const OpenNewSession()),
            ),
          ],
        ),
      );
    },
  );
}
```

`apps/mobile/lib/terminal/terminal_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:xterm/xterm.dart';

import '../backend/backend.dart';
import '../errors/error_text.dart';
import '../l10n/app_localizations.dart';
import '../widgets/connection_banner.dart';
import 'extra_keys_bar.dart';
import 'pinch_zoom.dart';
import 'session_picker.dart';
import 'terminal_metrics.dart';
import 'terminal_shortcuts.dart';
import 'terminal_tab_controller.dart';
import 'terminal_workspace.dart';

/// Spec §9.2 #4: tabs of one machine, the terminal and the extra keys bar.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({
    super.key,
    required this.backend,
    required this.registry,
    required this.agentId,
    required this.machineName,
    required this.initialFontSize,
    required this.onReconnectReplaced,
  });

  final ShellxBackend backend;
  final WorkspaceRegistry registry;
  final String agentId;
  final String machineName;
  final double initialFontSize;
  final VoidCallback onReconnectReplaced;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final TerminalWorkspace _workspace = widget.registry.forMachine(widget.agentId);
  late double _fontSize = widget.initialFontSize;
  TerminalGrid _grid = fallbackGrid;
  bool _busy = false;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  /// Runs a machine operation with the progress bar; errors become messages.
  /// Never wraps dialogs or sheets, so the UI can settle while they are open.
  Future<T?> _guard<T>(Future<T> Function() action) async {
    setState(() => _busy = true);
    try {
      return await action();
    } catch (error) {
      await _showError(error);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepare() async {
    final sessions = await _guard(_workspace.prepare);
    if (sessions == null || !mounted) return;
    if (sessions.isEmpty) {
      if (_workspace.tabs.isEmpty) await _openNew();
      return;
    }
    await _choose(sessions);
  }

  Future<void> _choose(List<SessionInfo> sessions) async {
    final choice = await showSessionPicker(context, sessions);
    switch (choice) {
      case AttachSession(:final session):
        await _guard(() => _workspace.attach(session, _grid));
      case OpenNewSession():
        await _openNew();
      case null:
        break;
    }
  }

  Future<void> _showSessions() async {
    final sessions = await _guard(() async {
      await _workspace.ensureConnected();
      return _workspace.machine.listSessions();
    });
    if (sessions == null || !mounted) return;
    final open = _workspace.tabs.map((tab) => tab.id).toSet();
    await _choose([for (final session in sessions) if (!open.contains(session.id)) session]);
  }

  Future<void> _openNew() => _guard(() => _workspace.openNew(_grid));

  Future<void> _close(TerminalTabController tab) async {
    if (tab.isLive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(_l10n.terminalCloseConfirm),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_l10n.actionCancel)),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(_l10n.terminalCloseTab)),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _workspace.close(tab);
  }

  Future<void> _showError(Object error) async {
    if (!mounted) return;
    final message = ErrorText(_l10n).describe(error);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    final failure = switch (error) {
      MachineFailed(:final failure) => failure,
      MachineConnectionException(:final failure) => failure,
      _ => null,
    };
    if (failure == MachineConnectionFailure.untrusted) {
      // Spec §12: the machine no longer trusts this phone → drop the pinned key.
      widget.registry.remove(widget.agentId);
      try {
        await widget.backend.unpair(widget.agentId);
      } on Object {
        // The pin is gone locally even if the relay call failed.
      }
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _paste() async {
    final tab = _workspace.activeTab;
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (tab == null || text == null || text.isEmpty) return;
    tab.terminal.paste(text);
  }

  Future<void> _copy(TerminalTabController tab) async {
    final range = tab.selection.selection;
    if (range == null) return;
    await Clipboard.setData(ClipboardData(text: tab.terminal.buffer.getText(range)));
    tab.selection.clearSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_l10n.copied)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.machineName),
        actions: [
          IconButton(
            tooltip: l10n.terminalSessionsTooltip,
            icon: const Icon(Icons.list),
            onPressed: _busy ? null : _showSessions,
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _workspace,
          builder: (context, _) {
            final active = _workspace.activeTab;
            return Column(
              children: [
                ConnectionBanner(backend: widget.backend, onReconnectReplaced: widget.onReconnectReplaced),
                _TabStrip(
                  workspace: _workspace,
                  canOpen: !_busy,
                  onOpen: _openNew,
                  onClose: _close,
                ),
                if (_busy) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _grid = measureTerminalGrid(
                            constraints.biggest,
                            shellxTerminalStyle(_fontSize),
                            MediaQuery.textScalerOf(context),
                          ) ??
                          fallbackGrid;
                      if (active == null) {
                        return Center(
                          child: _busy
                              ? Text(l10n.terminalConnecting)
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(l10n.terminalNoTabs),
                                    const SizedBox(height: 12),
                                    FilledButton(onPressed: _openNew, child: Text(l10n.terminalOpenNew)),
                                  ],
                                ),
                        );
                      }
                      return _TerminalPane(
                        key: ValueKey(active.id),
                        tab: active,
                        fontSize: _fontSize,
                        onFontSize: (size) => setState(() => _fontSize = size),
                        onCopy: () => _copy(active),
                        onClose: () => _workspace.close(active),
                      );
                    },
                  ),
                ),
                ExtraKeysBar(
                  controller: _workspace.extraKeys,
                  onKey: (key) {
                    final tab = _workspace.activeTab;
                    if (tab != null) _workspace.extraKeys.sendKey(key, tab.terminal);
                  },
                  onPaste: _paste,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.workspace, required this.canOpen, required this.onOpen, required this.onClose});

  final TerminalWorkspace workspace;
  final bool canOpen;
  final VoidCallback onOpen;
  final ValueChanged<TerminalTabController> onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tabs = workspace.tabs;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                final tab = tabs[index];
                return ListenableBuilder(
                  listenable: tab,
                  builder: (context, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    child: InputChip(
                      key: ValueKey('tab-${tab.id}'),
                      selected: index == workspace.activeIndex,
                      label: Text(tab.title, overflow: TextOverflow.ellipsis),
                      avatar: tab.isLive ? null : Icon(Icons.stop_circle_outlined, size: 16, color: scheme.error),
                      onPressed: () => workspace.select(index),
                      deleteButtonTooltipMessage: l10n.terminalCloseTab,
                      onDeleted: () => onClose(tab),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: l10n.terminalNewTab,
            icon: const Icon(Icons.add),
            onPressed: canOpen ? onOpen : null,
          ),
        ],
      ),
    );
  }
}

class _TerminalPane extends StatelessWidget {
  const _TerminalPane({
    super.key,
    required this.tab,
    required this.fontSize,
    required this.onFontSize,
    required this.onCopy,
    required this.onClose,
  });

  final TerminalTabController tab;
  final double fontSize;
  final ValueChanged<double> onFontSize;
  final VoidCallback onCopy;
  final VoidCallback onClose;

  String _bannerText(AppLocalizations l10n, TabBanner banner) => switch (banner.notice) {
        TabNotice.exited => l10n.tabExited(banner.exitCode ?? 0),
        TabNotice.sessionEnded => l10n.sessionEnded,
        TabNotice.takenOver => l10n.tabTakenOver,
        TabNotice.closedByHost => l10n.tabClosedByHost,
        TabNotice.failed => ErrorText(l10n).appError(banner.errorCode!, banner.detail ?? ''),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([tab, tab.selection]),
      builder: (context, _) {
        final banner = tab.banner;
        return Stack(
          children: [
            Positioned.fill(
              child: PinchToZoom(
                fontSize: fontSize,
                onFontSize: onFontSize,
                child: TerminalView(
                  tab.terminal,
                  controller: tab.selection,
                  textStyle: shellxTerminalStyle(fontSize),
                  autofocus: true,
                  deleteDetection: true,
                  readOnly: !tab.isLive,
                  shortcuts: terminalShortcuts(defaultTargetPlatform),
                ),
              ),
            ),
            if (tab.selection.selection != null)
              Positioned(
                top: 8,
                right: 8,
                child: FilledButton.tonalIcon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(l10n.copyAction),
                ),
              ),
            if (banner != null)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(_bannerText(l10n, banner))),
                        if (banner.notice == TabNotice.takenOver)
                          TextButton(onPressed: tab.reattach, child: Text(l10n.tabReattach)),
                        TextButton(onPressed: onClose, child: Text(l10n.actionClose)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/terminal && flutter analyze`
Expected: PASS — `All tests passed!` (71 tests in `test/terminal`); `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/widgets apps/mobile/lib/terminal/session_picker.dart apps/mobile/lib/terminal/terminal_screen.dart \
  apps/mobile/test/support/app_harness.dart apps/mobile/test/terminal/terminal_screen_test.dart
git commit -m "feat(mobile): terminal screen with tabs, session picker, extra keys, copy/paste and banners"
```

---

### Task 14: QR pairing — parse, pair, spec messages, scanner screen

**Files:**
- Create: `apps/mobile/lib/pairing/pairing_flow.dart`, `apps/mobile/lib/pairing/qr_scanner_screen.dart`
- Test: `apps/mobile/test/pairing/pairing_test.dart`

**Interfaces:**
- Consumes: `PairingUri.parse` (`FormatException`), `PairingUri(...).toUriString()`, `ApiException` (`shellx_core`); `PairingException`, `PairingFailure` (`shellx_client`); `ShellxBackend.pair` (Task 4); `ErrorText` (Task 3); `MobileScanner`, `MobileScannerController`, `BarcodeFormat`, `DetectionSpeed`, `MobileScannerErrorCode` (`mobile_scanner` 7.4.2).
- Produces:
  - `sealed class PairingOutcome`, `final class PairingSucceeded extends PairingOutcome { const PairingSucceeded(String agentId); }`, `final class PairingRejected extends PairingOutcome { const PairingRejected(String message); }`, `Future<PairingOutcome> pairFromQrCode(String raw, ShellxBackend backend, ErrorText text)`
  - `typedef ScannerViewBuilder = Widget Function(BuildContext context, ValueChanged<String> onCode);`, `Widget cameraScannerView(BuildContext context, ValueChanged<String> onCode)`, `class QrScannerScreen extends StatefulWidget { const QrScannerScreen({Key? key, required ShellxBackend backend, ScannerViewBuilder scannerBuilder = cameraScannerView}); }` — pops with the paired agent id.

A QR code that is not a `shellx://pair?...` URI gets the "invalid or expired" text. Detection is ignored while pairing runs or while a failure is shown; "Quét lại" re-arms it. Camera permission denial shows its own text.

- [ ] **Step 1: Write the failing tests**

`apps/mobile/test/pairing/pairing_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/errors/error_text.dart';
import 'package:shellx_mobile/l10n/app_localizations.dart';
import 'package:shellx_mobile/pairing/pairing_flow.dart';
import 'package:shellx_mobile/pairing/qr_scanner_screen.dart';

import '../support/app_harness.dart';
import '../support/fakes.dart';

void main() {
  final text = ErrorText(lookupAppLocalizations(const Locale('vi')));
  final validCode = PairingUri(
    agentDeviceId: agentA,
    agentPublicKey: Uint8List(32)..fillRange(0, 32, 7),
    secret: Uint8List(32)..fillRange(0, 32, 9),
  ).toUriString();
  late FakeBackend backend;

  setUp(() => backend = FakeBackend());

  group('pairFromQrCode', () {
    test('pairs with the scanned machine', () async {
      final outcome = await pairFromQrCode(validCode, backend, text);
      expect(outcome, isA<PairingSucceeded>().having((o) => o.agentId, 'agentId', agentA));
      expect(backend.paired.single.agentDeviceId, agentA);
    });

    test('a QR code that is not a pairing URI is "invalid or expired"', () async {
      final outcome = await pairFromQrCode('https://example.com', backend, text);
      expect((outcome as PairingRejected).message,
          'Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính.');
      expect(backend.paired, isEmpty);
    });

    final cases = {
      PairingFailure.notInAccount:
          'Máy này không thuộc tài khoản của bạn. Hãy đăng nhập cùng tài khoản trên máy tính.',
      PairingFailure.invalidOrExpired: 'Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính.',
      PairingFailure.agentOffline: 'Máy tính đang offline. Hãy mở ShellX trên máy tính rồi thử lại.',
      PairingFailure.protocolUnsupported: 'Cần cập nhật app',
      PairingFailure.timeout: 'Máy tính không phản hồi. Hãy thử lại.',
    };
    for (final entry in cases.entries) {
      test('${entry.key} → spec message', () async {
        backend.pairError = PairingException(entry.key);
        final outcome = await pairFromQrCode(validCode, backend, text);
        expect((outcome as PairingRejected).message, entry.value);
      });
    }

    test('a rate-limited GET /v1/devices maps to "Thử lại sau ít phút."', () async {
      backend.pairError = const ApiException(status: 429, code: 'rate_limited', message: 'slow down');
      final outcome = await pairFromQrCode(validCode, backend, text);
      expect((outcome as PairingRejected).message, 'Thử lại sau ít phút.');
    });
  });

  group('QrScannerScreen', () {
    late ValueChanged<String> scan;

    Widget app() => pushingHost((_) => QrScannerScreen(
          backend: backend,
          scannerBuilder: (context, onCode) {
            scan = onCode;
            return const ColoredBox(color: Colors.black);
          },
        ));

    testWidgets('success closes the scanner', (tester) async {
      await tester.pumpWidget(app());
      await openPushed(tester);
      expect(find.text('Quét mã ghép nối'), findsOneWidget);

      scan(validCode);
      await tester.pumpAndSettle();
      expect(find.text('Đã ghép nối'), findsOneWidget);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('a failure shows the message; "Quét lại" scans again', (tester) async {
      backend.pairError = const PairingException(PairingFailure.notInAccount);
      await tester.pumpWidget(app());
      await openPushed(tester);

      scan(validCode);
      await tester.pumpAndSettle();
      expect(find.text('Máy này không thuộc tài khoản của bạn. Hãy đăng nhập cùng tài khoản trên máy tính.'),
          findsOneWidget);

      scan(validCode); // ignored while the message is shown
      await tester.pumpAndSettle();
      expect(backend.paired, isEmpty);

      await tester.tap(find.text('Quét lại'));
      await tester.pumpAndSettle();
      backend.pairError = null;
      scan(validCode);
      await tester.pumpAndSettle();
      expect(backend.paired, hasLength(1));
    });
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/mobile && flutter test test/pairing`
Expected: FAIL — `Error when reading 'lib/pairing/pairing_flow.dart': No such file or directory`, `Error when reading 'lib/pairing/qr_scanner_screen.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/mobile/lib/pairing/pairing_flow.dart`:

```dart
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';

import '../backend/backend.dart';
import '../errors/error_text.dart';

sealed class PairingOutcome {
  const PairingOutcome();
}

final class PairingSucceeded extends PairingOutcome {
  const PairingSucceeded(this.agentId);
  final String agentId;
}

final class PairingRejected extends PairingOutcome {
  const PairingRejected(this.message);
  final String message;
}

/// Spec §5.3 on the phone: parse the scanned text, run the pairing
/// handshake, and turn every failure into the spec's message.
Future<PairingOutcome> pairFromQrCode(String raw, ShellxBackend backend, ErrorText text) async {
  final PairingUri uri;
  try {
    uri = PairingUri.parse(raw.trim());
  } on FormatException {
    // Not a ShellX pairing code (or a damaged one).
    return PairingRejected(text.pairing(PairingFailure.invalidOrExpired));
  }
  try {
    await backend.pair(uri);
    return PairingSucceeded(uri.agentDeviceId);
  } on PairingException catch (error) {
    return PairingRejected(text.pairing(error.failure));
  } on ApiException catch (error) {
    return PairingRejected(text.api(error));
  }
}
```

`apps/mobile/lib/pairing/qr_scanner_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../backend/backend.dart';
import '../errors/error_text.dart';
import '../l10n/app_localizations.dart';
import 'pairing_flow.dart';

/// Builds the camera view; tests replace it with a fake scanner.
typedef ScannerViewBuilder = Widget Function(BuildContext context, ValueChanged<String> onCode);

Widget cameraScannerView(BuildContext context, ValueChanged<String> onCode) => _CameraScanner(onCode: onCode);

/// Spec §9.2 #3. Pops with the paired agent id on success.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key, required this.backend, this.scannerBuilder = cameraScannerView});

  final ShellxBackend backend;
  final ScannerViewBuilder scannerBuilder;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _pairing = false;
  String? _error;

  Future<void> _onCode(String raw) async {
    if (_pairing || _error != null) return;
    setState(() => _pairing = true);
    final l10n = AppLocalizations.of(context);
    final outcome = await pairFromQrCode(raw, widget.backend, ErrorText(l10n));
    if (!mounted) return;
    switch (outcome) {
      case PairingSucceeded(:final agentId):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.pairingSucceeded)));
        Navigator.of(context).pop(agentId);
      case PairingRejected(:final message):
        setState(() {
          _pairing = false;
          _error = message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scannerTitle)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.scannerBuilder(context, _onCode),
                if (_pairing)
                  ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(l10n.scannerPairing, style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                if (error != null)
                  ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: Card(
                        margin: const EdgeInsets.all(24),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(error, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => setState(() => _error = null),
                                child: Text(l10n.scanAgain),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: Text(l10n.scannerHint, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

class _CameraScanner extends StatefulWidget {
  const _CameraScanner({required this.onCode});

  final ValueChanged<String> onCode;

  @override
  State<_CameraScanner> createState() => _CameraScannerState();
}

class _CameraScannerState extends State<_CameraScanner> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        final raw = capture.barcodes.firstOrNull?.rawValue;
        if (raw != null) widget.onCode(raw);
      },
      errorBuilder: (context, error) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? l10n.scannerCameraDenied
                  : l10n.scannerCameraError,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/pairing`
Expected: PASS — `All tests passed!` (10 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/pairing apps/mobile/test/pairing
git commit -m "feat(mobile): QR pairing flow and scanner screen with spec error messages"
```

---

### Task 15: Settings and account deletion

**Files:**
- Create: `apps/mobile/lib/settings/settings_screen.dart`, `apps/mobile/lib/settings/delete_account_screen.dart`
- Test: `apps/mobile/test/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `AppSettings` (Task 2); `AppLockController.settingChanged`, `BiometricAuthenticator.isAvailable` (Task 6); `ShellxBackend.pinnedMachines/devices/unpair` (Task 4); `ErrorText` (Task 3); `ApiException`; `showLicensePage`.
- Produces:
  - `class SettingsScreen extends StatefulWidget { const SettingsScreen({Key? key, required AppSettings settings, required AppLockController lock, required BiometricAuthenticator biometrics, required ShellxBackend backend, required String email, required String appVersion, required ValueChanged<String> onUnpaired, required Future<void> Function() onLogout, required Future<void> Function(String password) onDeleteAccount}); }`
  - `class DeleteAccountScreen extends StatefulWidget { const DeleteAccountScreen({Key? key, required Future<void> Function(String password) onDelete}); }`

Spec §9.2 #5 items in order: account email, default font size (slider 8–32), biometric lock (on by default, disabled with an explanation when the device has no passcode/biometrics), paired computers with "Bỏ ghép nối" (confirmation; spec §5.5), "Đăng xuất" (confirmation; only the token is deleted — Task 5), "Xóa tài khoản" → `DeleteAccountScreen` (irreversible warning, password re-entry, `invalid_credentials` → "Mật khẩu không đúng.", 429 → "Thử lại sau ít phút."), open-source licences (JetBrains Mono OFL), "Phiên bản x.y.z".

- [ ] **Step 1: Write the failing widget tests**

`apps/mobile/test/settings/settings_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/lock/app_lock_controller.dart';
import 'package:shellx_mobile/settings/app_settings.dart';
import 'package:shellx_mobile/settings/settings_screen.dart';

import '../support/app_harness.dart';
import '../support/fakes.dart';

void main() {
  late AppSettings settings;
  late FakeBiometricAuthenticator biometrics;
  late AppLockController lock;
  late FakeBackend backend;
  late List<String> unpairedCallbacks;
  late int logouts;
  late List<String> deleteAttempts;
  late Object? deleteError;

  setUp(() async {
    settings = AppSettings(InMemoryKeyValueStore());
    await settings.load();
    biometrics = FakeBiometricAuthenticator();
    lock = AppLockController(authenticator: biometrics, isEnabled: () => settings.biometricLock);
    backend = FakeBackend(
      devices: [agentDevice(agentA, 'MacBook-Pro'), agentDevice(agentB, 'DESKTOP-42')],
      pinnedList: [pinned(agentA)],
    );
    unpairedCallbacks = [];
    logouts = 0;
    deleteAttempts = [];
    deleteError = null;
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localized(SettingsScreen(
      settings: settings,
      lock: lock,
      biometrics: biometrics,
      backend: backend,
      email: 'me@example.com',
      appVersion: '1.0.0',
      onUnpaired: unpairedCallbacks.add,
      onLogout: () async => logouts++,
      onDeleteAccount: (password) async {
        deleteAttempts.add(password);
        final error = deleteError;
        if (error != null) throw error;
      },
    )));
    await tester.pumpAndSettle();
  }

  testWidgets('shows account, version and paired machines by name', (tester) async {
    await pumpSettings(tester);
    expect(find.text('me@example.com'), findsOneWidget);
    expect(find.text('Phiên bản 1.0.0'), findsOneWidget);
    expect(find.text('MacBook-Pro'), findsOneWidget);
    expect(find.text('DESKTOP-42'), findsNothing); // not paired
  });

  testWidgets('font size slider persists the default size', (tester) async {
    await pumpSettings(tester);
    tester.widget<Slider>(find.byType(Slider)).onChanged!(20);
    await tester.pump();
    expect(settings.fontSize, 20);
    expect(find.text('20'), findsWidgets);
  });

  testWidgets('biometric switch is on by default and can be turned off', (tester) async {
    lock.lockOnLaunch();
    await pumpSettings(tester);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(settings.biometricLock, isFalse);
    expect(lock.isLocked, isFalse);
  });

  testWidgets('biometric switch is disabled without passcode or biometrics', (tester) async {
    biometrics.available = false;
    await pumpSettings(tester);
    expect(find.text('Thiết bị chưa đặt mã khóa hoặc sinh trắc học'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
  });

  testWidgets('unpair asks, unpairs and refreshes the list (spec §5.5)', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Bỏ ghép nối'));
    await tester.pumpAndSettle();
    expect(find.text('Bỏ ghép nối MacBook-Pro? Bạn sẽ phải quét lại mã QR để dùng máy này.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Bỏ ghép nối').last);
    await tester.pumpAndSettle();
    expect(backend.unpaired, [agentA]);
    expect(unpairedCallbacks, [agentA]);
    expect(find.text('Chưa ghép nối máy nào.'), findsOneWidget);
  });

  testWidgets('sign out asks for confirmation', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(logouts, 0);
    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Đăng xuất'));
    await tester.pumpAndSettle();
    expect(logouts, 1);
  });

  group('delete account', () {
    Future<void> openDeleteScreen(WidgetTester tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Xóa tài khoản'));
      await tester.pumpAndSettle();
    }

    testWidgets('warns that it cannot be undone and requires the password', (tester) async {
      await openDeleteScreen(tester);
      expect(find.textContaining('không thể hoàn tác'), findsOneWidget);
      final button = find.widgetWithText(FilledButton, 'Xóa vĩnh viễn');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'correct horse');
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(deleteAttempts, ['correct horse']);
    });

    testWidgets('a wrong password shows "Mật khẩu không đúng."', (tester) async {
      deleteError = const ApiException(status: 401, code: 'invalid_credentials', message: 'no');
      await openDeleteScreen(tester);
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Xóa vĩnh viễn'));
      await tester.pumpAndSettle();
      expect(find.text('Mật khẩu không đúng.'), findsOneWidget);
    });

    testWidgets('rate limiting shows the spec message', (tester) async {
      deleteError = const ApiException(status: 429, code: 'rate_limited', message: 'slow');
      await openDeleteScreen(tester);
      await tester.enterText(find.byType(TextField), 'pw');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Xóa vĩnh viễn'));
      await tester.pumpAndSettle();
      expect(find.text('Thử lại sau ít phút.'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/mobile && flutter test test/settings/settings_screen_test.dart`
Expected: FAIL — `Error when reading 'lib/settings/settings_screen.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/mobile/lib/settings/delete_account_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shellx_core/shellx_core.dart';

import '../errors/error_text.dart';
import '../l10n/app_localizations.dart';

/// Spec §5.2 / §9.2 #5 (App Store 5.1.1(v)): irreversible-action warning and
/// password re-entry before `DELETE /v1/account`.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key, required this.onDelete});

  /// Throws [ApiException]; on success the app leaves the signed-in UI.
  final Future<void> Function(String password) onDelete;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onDelete(_password.text);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error =
          error.code == 'invalid_credentials' ? l10n.errorWrongPassword : ErrorText(l10n).api(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.deleteAccountTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.warning_amber_rounded, size: 48, color: scheme.error),
          const SizedBox(height: 16),
          Text(l10n.deleteAccountWarning, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 24),
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: l10n.deleteAccountPasswordLabel,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
            onPressed: _busy || _password.text.isEmpty ? null : _submit,
            child: _busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.deleteAccountButton),
          ),
        ],
      ),
    );
  }
}
```

`apps/mobile/lib/settings/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../errors/error_text.dart';
import '../l10n/app_localizations.dart';
import '../lock/app_lock_controller.dart';
import '../lock/biometric_authenticator.dart';
import 'app_settings.dart';
import 'delete_account_screen.dart';

typedef _PairedMachine = ({String agentId, String? name});

/// Spec §9.2 #5: default font size, biometric lock, unpair per machine,
/// sign out, delete account, app version.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.lock,
    required this.biometrics,
    required this.backend,
    required this.email,
    required this.appVersion,
    required this.onUnpaired,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  final AppSettings settings;
  final AppLockController lock;
  final BiometricAuthenticator biometrics;
  final ShellxBackend backend;
  final String email;
  final String appVersion;

  /// Called after a machine was unpaired (drop its terminal workspace).
  final ValueChanged<String> onUnpaired;
  final Future<void> Function() onLogout;
  final Future<void> Function(String password) onDeleteAccount;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Future<bool> _biometricsAvailable = widget.biometrics.isAvailable();
  late Future<List<_PairedMachine>> _paired = _loadPaired();

  AppLocalizations get _l10n => AppLocalizations.of(context);

  Future<List<_PairedMachine>> _loadPaired() async {
    final pins = await widget.backend.pinnedMachines();
    var names = <String, String>{};
    try {
      names = {for (final device in await widget.backend.devices()) device.id: device.name};
    } on Object {
      // Offline: still list the pinned machines, without names.
    }
    return [for (final pin in pins) (agentId: pin.agentId, name: names[pin.agentId])];
  }

  Future<bool> _confirm(String message, String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_l10n.actionCancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _unpair(_PairedMachine machine) async {
    final name = machine.name ?? _l10n.unknownMachine;
    if (!await _confirm(_l10n.settingsUnpairConfirm(name), _l10n.settingsUnpair)) return;
    try {
      await widget.backend.unpair(machine.agentId);
      widget.onUnpaired(machine.agentId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ErrorText(_l10n).describe(error))));
      }
    }
    if (!mounted) return;
    setState(() {
      _paired = _loadPaired();
    });
  }

  Future<void> _logout() async {
    if (!await _confirm(_l10n.settingsLogoutConfirm, _l10n.settingsLogout)) return;
    await widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) => ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(l10n.settingsAccount),
              subtitle: Text(widget.email),
            ),
            ListTile(
              leading: const Icon(Icons.format_size),
              title: Text(l10n.settingsFontSize),
              trailing: Text(widget.settings.fontSize.toStringAsFixed(0)),
            ),
            Slider(
              min: AppSettings.minFontSize,
              max: AppSettings.maxFontSize,
              divisions: (AppSettings.maxFontSize - AppSettings.minFontSize).round(),
              value: widget.settings.fontSize,
              label: widget.settings.fontSize.toStringAsFixed(0),
              onChanged: widget.settings.setFontSize,
            ),
            FutureBuilder<bool>(
              future: _biometricsAvailable,
              builder: (context, snapshot) {
                final available = snapshot.data ?? false;
                return SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: Text(l10n.settingsBiometric),
                  subtitle: Text(available ? l10n.settingsBiometricSubtitle : l10n.settingsBiometricUnavailable),
                  value: available && widget.settings.biometricLock,
                  onChanged: available
                      ? (enabled) async {
                          await widget.settings.setBiometricLock(enabled);
                          widget.lock.settingChanged();
                        }
                      : null,
                );
              },
            ),
            const Divider(),
            ListTile(title: Text(l10n.settingsPairedMachines, style: Theme.of(context).textTheme.titleSmall)),
            FutureBuilder<List<_PairedMachine>>(
              future: _paired,
              builder: (context, snapshot) {
                final machines = snapshot.data;
                if (machines == null) return const Center(child: CircularProgressIndicator());
                if (machines.isEmpty) return ListTile(title: Text(l10n.settingsNoPairedMachines));
                return Column(
                  children: [
                    for (final machine in machines)
                      ListTile(
                        leading: const Icon(Icons.computer),
                        title: Text(machine.name ?? l10n.unknownMachine),
                        trailing: TextButton(
                          onPressed: () => _unpair(machine),
                          child: Text(l10n.settingsUnpair),
                        ),
                      ),
                  ],
                );
              },
            ),
            const Divider(),
            ListTile(leading: const Icon(Icons.logout), title: Text(l10n.settingsLogout), onTap: _logout),
            ListTile(
              leading: Icon(Icons.delete_forever, color: scheme.error),
              title: Text(l10n.settingsDeleteAccount, style: TextStyle(color: scheme.error)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => DeleteAccountScreen(onDelete: widget.onDeleteAccount),
              )),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(l10n.settingsLicenses),
              onTap: () => showLicensePage(
                context: context,
                applicationName: l10n.appTitle,
                applicationVersion: widget.appVersion,
              ),
            ),
            ListTile(leading: const Icon(Icons.info_outline), title: Text(l10n.settingsVersion(widget.appVersion))),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/settings`
Expected: PASS — `All tests passed!` (12 tests: 9 new + 3 from Task 2).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/settings/settings_screen.dart apps/mobile/lib/settings/delete_account_screen.dart \
  apps/mobile/test/settings/settings_screen_test.dart
git commit -m "feat(mobile): settings screen with unpair, sign out and account deletion"
```

---

### Task 16: `MachineListController` — devices + PRESENCE + pins

**Files:**
- Create: `apps/mobile/lib/machines/machine_list_controller.dart`
- Test: `apps/mobile/test/machines/machine_list_controller_test.dart`

**Interfaces:**
- Consumes: `ShellxBackend.devices/pinnedMachines/isOnline/presence/relayState/relayStates` (Task 4); `RemoteDevice`, `DeviceKind`, `DevicePlatform`, `PresenceFrame`, `RelayConnectionState`.
- Produces:
  - `final class MachineEntry { const MachineEntry({required String id, required String name, required DevicePlatform platform, required bool online, required DateTime? lastSeenAt, required bool paired}); MachineEntry copyWith({bool? online, DateTime? lastSeenAt}); }`
  - `final class MachineListController extends ChangeNotifier { MachineListController({required ShellxBackend backend, DateTime Function()? now}); List<MachineEntry> get machines; bool get loading; Object? get error; Future<void> refresh(); }`

Rules: agents only, sorted by name; `paired` = pinned locally for this user (the server's `paired_with_me` is display-only; trust lives on the agent, spec §5.4); `online` = hub PRESENCE while the relay is connected, else the REST snapshot; PRESENCE offline stamps "last online" with the local clock; PRESENCE from an unknown agent and every reconnect trigger a refresh; a failed refresh keeps the last list and exposes the error.

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/machines/machine_list_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/machines/machine_list_controller.dart';

import '../support/fakes.dart';

void main() {
  final now = DateTime(2026, 9, 25, 12);
  late FakeBackend backend;
  late MachineListController controller;

  setUp(() {
    backend = FakeBackend(
      devices: [
        agentDevice(agentB, 'zeta-pc', online: false, lastSeenAt: now.subtract(const Duration(hours: 2))),
        agentDevice(agentA, 'MacBook-Pro'),
        const RemoteDevice(
          id: '99999999-9999-4999-8999-999999999999',
          kind: DeviceKind.mobile,
          name: 'iPhone 15',
          platform: DevicePlatform.ios,
          online: true,
          lastSeenAt: null,
          pairedWithMe: false,
        ),
      ],
      pinnedList: [pinned(agentA)],
    );
    controller = MachineListController(backend: backend, now: () => now);
  });

  tearDown(() => controller.dispose());

  test('lists agents only, sorted by name, with the local pin as "paired"', () async {
    backend.onlineIds.add(agentA);
    await controller.refresh();
    expect(controller.machines.map((m) => m.name), ['MacBook-Pro', 'zeta-pc']);
    expect(controller.machines.first.paired, isTrue);
    expect(controller.machines.last.paired, isFalse);
    expect(controller.machines.last.lastSeenAt, now.subtract(const Duration(hours: 2)));
  });

  test('uses PRESENCE while connected and the REST snapshot otherwise', () async {
    await controller.refresh();
    expect(controller.machines.first.online, isFalse); // hub says nothing is online

    backend.relayStateValue = RelayConnectionState.disconnected;
    await controller.refresh();
    expect(controller.machines.first.online, isTrue); // REST says online
  });

  test('PRESENCE offline greys the machine and stamps "last online" now', () async {
    backend.onlineIds.add(agentA);
    await controller.refresh();
    var notified = 0;
    controller.addListener(() => notified++);

    backend.emitPresence(agentA, online: false);

    final mac = controller.machines.firstWhere((m) => m.id == agentA);
    expect(mac.online, isFalse);
    expect(mac.lastSeenAt, now);
    expect(notified, 1);

    backend.emitPresence(agentA, online: true);
    expect(controller.machines.firstWhere((m) => m.id == agentA).online, isTrue);
  });

  test('PRESENCE from an unknown computer refreshes the list', () async {
    await controller.refresh();
    backend.deviceList = [...backend.deviceList, agentDevice('55555555-5555-4555-8555-555555555555', 'new-box')];
    backend.emitPresence('55555555-5555-4555-8555-555555555555', online: true);
    await pumpEventQueue();
    expect(controller.machines.map((m) => m.name), contains('new-box'));
  });

  test('refreshes when the relay reconnects', () async {
    await controller.refresh();
    backend.deviceList = [agentDevice(agentA, 'renamed')];
    backend.emitRelay(RelayConnectionState.connected);
    await pumpEventQueue();
    expect(controller.machines.single.name, 'renamed');
  });

  test('keeps the last list and exposes the error when the refresh fails', () async {
    await controller.refresh();
    backend.devicesError = const ApiException(status: 0, code: 'network', message: 'offline');
    await controller.refresh();
    expect(controller.machines, hasLength(2));
    expect(controller.error, isA<ApiException>());
    expect(controller.loading, isFalse);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/mobile && flutter test test/machines/machine_list_controller_test.dart`
Expected: FAIL — `Error when reading 'lib/machines/machine_list_controller.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/mobile/lib/machines/machine_list_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shellx_core/shellx_core.dart';

import '../backend/backend.dart';

/// One computer (agent) of the account as shown on the machine list.
final class MachineEntry {
  const MachineEntry({
    required this.id,
    required this.name,
    required this.platform,
    required this.online,
    required this.lastSeenAt,
    required this.paired,
  });

  final String id;
  final String name;
  final DevicePlatform platform;
  final bool online;
  final DateTime? lastSeenAt;

  /// Pinned on this phone for the signed-in user. The server's
  /// `paired_with_me` is display-only; the pin decides (spec §5.4).
  final bool paired;

  MachineEntry copyWith({bool? online, DateTime? lastSeenAt}) => MachineEntry(
        id: id,
        name: name,
        platform: platform,
        online: online ?? this.online,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        paired: paired,
      );
}

/// Spec §9.2 #2: agents from `GET /v1/devices`, kept live with PRESENCE.
final class MachineListController extends ChangeNotifier {
  MachineListController({required ShellxBackend backend, DateTime Function()? now})
      : _backend = backend,
        _now = now ?? DateTime.now {
    _presence = backend.presence.listen(_onPresence);
    _relay = backend.relayStates.listen((state) {
      // Presence may have been missed while disconnected.
      if (state == RelayConnectionState.connected) unawaited(refresh());
    });
  }

  final ShellxBackend _backend;
  final DateTime Function() _now;
  late final StreamSubscription<PresenceFrame> _presence;
  late final StreamSubscription<RelayConnectionState> _relay;
  List<MachineEntry> _machines = const [];
  bool _loading = false;
  Object? _error;
  bool _disposed = false;

  List<MachineEntry> get machines => _machines;
  bool get loading => _loading;

  /// The last refresh failure (an [ApiException]), or null.
  Object? get error => _error;

  Future<void> refresh() async {
    _loading = true;
    _notify();
    try {
      final devices = await _backend.devices();
      final pinned = {for (final machine in await _backend.pinnedMachines()) machine.agentId};
      final live = _backend.relayState == RelayConnectionState.connected;
      _machines = [
        for (final device in devices)
          if (device.kind == DeviceKind.agent)
            MachineEntry(
              id: device.id,
              name: device.name,
              platform: device.platform,
              // While connected the hub's PRESENCE is fresher than the REST snapshot.
              online: live ? _backend.isOnline(device.id) : device.online,
              lastSeenAt: device.lastSeenAt,
              paired: pinned.contains(device.id),
            ),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _error = null;
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  void _onPresence(PresenceFrame frame) {
    final index = _machines.indexWhere((machine) => machine.id == frame.deviceId);
    if (index < 0) {
      // A computer that just registered: fetch its name.
      if (frame.online) unawaited(refresh());
      return;
    }
    final machine = _machines[index];
    if (machine.online == frame.online) return;
    _machines = List.of(_machines)
      ..[index] = machine.copyWith(online: frame.online, lastSeenAt: frame.online ? null : _now());
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_presence.cancel());
    unawaited(_relay.cancel());
    super.dispose();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/machines/machine_list_controller_test.dart`
Expected: PASS — `All tests passed!` (6 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/machines/machine_list_controller.dart apps/mobile/test/machines/machine_list_controller_test.dart
git commit -m "feat(mobile): machine list controller combining devices, presence and pins"
```

---

### Task 17: Machine list screen

**Files:**
- Create: `apps/mobile/lib/machines/machine_list_screen.dart`
- Test: `apps/mobile/test/machines/machine_list_screen_test.dart`

**Interfaces:**
- Consumes: `MachineListController`, `MachineEntry` (Task 16); `formatLastSeen` (Task 3); `ConnectionBanner` (Task 13); `ErrorText` (Task 3); `ShellxBackend` (Task 4).
- Produces: `class MachineListScreen extends StatefulWidget { const MachineListScreen({Key? key, required ShellxBackend backend, required Future<void> Function(MachineEntry machine) onOpenMachine, required Future<void> Function(MachineEntry? target) onScan, required Future<void> Function() onOpenSettings, required VoidCallback onReconnectReplaced, DateTime Function() now = DateTime.now}); }` — tiles keyed `ValueKey('machine-<id>')`, dot keyed `ValueKey('dot-online')` / `ValueKey('dot-offline')`; the list refreshes after every navigation callback completes.

Spec §9.2 #2 / §12: name, OS icon, online dot; offline → grey + "Lần cuối online: …" and a tap only explains "Máy đang offline."; unpaired → "Chưa ghép nối" chip, tap opens the scanner; app bar: scan, settings; pull to refresh; empty-account hint; refresh errors shown with `ErrorText`.

- [ ] **Step 1: Write the failing widget tests**

`apps/mobile/test/machines/machine_list_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/machines/machine_list_controller.dart';
import 'package:shellx_mobile/machines/machine_list_screen.dart';

import '../support/app_harness.dart';
import '../support/fakes.dart';

void main() {
  final now = DateTime(2026, 9, 25, 12);
  late FakeBackend backend;
  late List<String> opened;
  late List<MachineEntry?> scans;
  late int settingsOpened;

  setUp(() {
    backend = FakeBackend(
      devices: [
        agentDevice(agentA, 'MacBook-Pro'),
        agentDevice(agentB, 'DESKTOP-42',
            online: false, platform: DevicePlatform.windows, lastSeenAt: now.subtract(const Duration(minutes: 5))),
        agentDevice('33333333-3333-4333-8333-333333333333', 'new-mac'),
      ],
      pinnedList: [pinned(agentA), pinned(agentB)],
    )..onlineIds.addAll([agentA, '33333333-3333-4333-8333-333333333333']);
    opened = [];
    scans = [];
    settingsOpened = 0;
  });

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(localized(MachineListScreen(
      backend: backend,
      now: () => now,
      onOpenMachine: (machine) async => opened.add(machine.id),
      onScan: (target) async => scans.add(target),
      onOpenSettings: () async => settingsOpened++,
      onReconnectReplaced: () {},
    )));
    await tester.pumpAndSettle();
  }

  Finder tile(String id) => find.byKey(ValueKey('machine-$id'));

  testWidgets('online dot, "Lần cuối online" and "Chưa ghép nối" (spec §9.2 #2)', (tester) async {
    await pumpList(tester);
    expect(find.descendant(of: tile(agentA), matching: find.byKey(const ValueKey('dot-online'))), findsOneWidget);
    expect(find.descendant(of: tile(agentA), matching: find.text('Đang online')), findsOneWidget);
    expect(find.descendant(of: tile(agentB), matching: find.byKey(const ValueKey('dot-offline'))), findsOneWidget);
    expect(find.text('Lần cuối online: 5 phút trước'), findsOneWidget);
    expect(find.descendant(of: tile('33333333-3333-4333-8333-333333333333'), matching: find.text('Chưa ghép nối')),
        findsOneWidget);
  });

  testWidgets('tapping: paired+online opens, offline explains, unpaired scans', (tester) async {
    await pumpList(tester);
    await tester.tap(tile(agentA));
    await tester.pumpAndSettle();
    expect(opened, [agentA]);

    await tester.tap(tile(agentB));
    await tester.pump();
    expect(find.text('Máy đang offline.'), findsOneWidget);
    expect(opened, [agentA]);

    await tester.tap(tile('33333333-3333-4333-8333-333333333333'));
    await tester.pumpAndSettle();
    expect(scans.single?.name, 'new-mac');
  });

  testWidgets('presence updates the dot live', (tester) async {
    await pumpList(tester);
    backend.emitPresence(agentA, online: false);
    await tester.pump();
    expect(find.descendant(of: tile(agentA), matching: find.byKey(const ValueKey('dot-offline'))), findsOneWidget);
    expect(find.text('Lần cuối online: vừa xong'), findsOneWidget);
  });

  testWidgets('app bar opens the scanner and settings; the list refreshes afterwards', (tester) async {
    await pumpList(tester);
    backend.deviceList = [agentDevice(agentA, 'Renamed-Mac')];
    await tester.tap(find.byTooltip('Quét mã QR'));
    await tester.pumpAndSettle();
    expect(scans, [null]);
    expect(find.text('Renamed-Mac'), findsOneWidget);

    await tester.tap(find.byTooltip('Cài đặt'));
    await tester.pumpAndSettle();
    expect(settingsOpened, 1);
  });

  testWidgets('empty account and offline errors', (tester) async {
    backend.deviceList = [];
    await pumpList(tester);
    expect(find.textContaining('Chưa có máy tính nào'), findsOneWidget);

    backend.devicesError = const ApiException(status: 429, code: 'rate_limited', message: 'slow');
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Thử lại sau ít phút.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/mobile && flutter test test/machines/machine_list_screen_test.dart`
Expected: FAIL — `Error when reading 'lib/machines/machine_list_screen.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/mobile/lib/machines/machine_list_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shellx_core/shellx_core.dart';

import '../backend/backend.dart';
import '../errors/error_text.dart';
import '../l10n/app_localizations.dart';
import '../widgets/connection_banner.dart';
import 'last_seen.dart';
import 'machine_list_controller.dart';

/// Spec §9.2 #2. Navigation is injected so the screen stays testable.
class MachineListScreen extends StatefulWidget {
  const MachineListScreen({
    super.key,
    required this.backend,
    required this.onOpenMachine,
    required this.onScan,
    required this.onOpenSettings,
    required this.onReconnectReplaced,
    this.now = DateTime.now,
  });

  final ShellxBackend backend;
  final Future<void> Function(MachineEntry machine) onOpenMachine;

  /// [target] is the unpaired machine the user tapped, or null from the app bar.
  final Future<void> Function(MachineEntry? target) onScan;
  final Future<void> Function() onOpenSettings;
  final VoidCallback onReconnectReplaced;
  final DateTime Function() now;

  @override
  State<MachineListScreen> createState() => _MachineListScreenState();
}

class _MachineListScreenState extends State<MachineListScreen> {
  late final MachineListController _controller = MachineListController(backend: widget.backend, now: widget.now)
    ..refresh();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _then(Future<void> navigation) async {
    await navigation;
    if (mounted) await _controller.refresh();
  }

  void _onTap(MachineEntry machine) {
    if (!machine.paired) {
      _then(widget.onScan(machine));
    } else if (!machine.online) {
      // Spec §12: an offline machine cannot open a tab.
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).machineOffline)));
    } else {
      _then(widget.onOpenMachine(machine));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.machinesTitle),
        actions: [
          IconButton(
            tooltip: l10n.scanTooltip,
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => _then(widget.onScan(null)),
          ),
          IconButton(
            tooltip: l10n.settingsTooltip,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _then(widget.onOpenSettings()),
          ),
        ],
      ),
      body: Column(
        children: [
          ConnectionBanner(backend: widget.backend, onReconnectReplaced: widget.onReconnectReplaced),
          Expanded(
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final machines = _controller.machines;
                final error = _controller.error;
                return RefreshIndicator(
                  onRefresh: _controller.refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (_controller.loading && machines.isEmpty) const LinearProgressIndicator(),
                      if (error != null)
                        ListTile(
                          leading: const Icon(Icons.error_outline),
                          title: Text(ErrorText(l10n).describe(error)),
                        ),
                      if (!_controller.loading && error == null && machines.isEmpty)
                        Padding(padding: const EdgeInsets.all(24), child: Text(l10n.machinesEmpty)),
                      for (final machine in machines)
                        _MachineTile(machine: machine, now: widget.now(), onTap: () => _onTap(machine)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MachineTile extends StatelessWidget {
  const _MachineTile({required this.machine, required this.now, required this.onTap});

  final MachineEntry machine;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final dimmed = !machine.online;
    return ListTile(
      key: ValueKey('machine-${machine.id}'),
      onTap: onTap,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            machine.platform == DevicePlatform.windows ? Icons.desktop_windows_outlined : Icons.laptop_mac,
            color: dimmed ? scheme.outline : scheme.onSurface,
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              key: ValueKey(machine.online ? 'dot-online' : 'dot-offline'),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: machine.online ? Colors.green : scheme.outline,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 1.5),
              ),
            ),
          ),
        ],
      ),
      title: Text(machine.name, style: TextStyle(color: dimmed ? scheme.outline : null)),
      subtitle: Text(machine.online
          ? l10n.machineOnline
          : l10n.machineLastOnline(formatLastSeen(l10n, machine.lastSeenAt, now))),
      trailing: machine.paired ? const Icon(Icons.chevron_right) : Chip(label: Text(l10n.machineNotPaired)),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/machines`
Expected: PASS — `All tests passed!` (13 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/machines/machine_list_screen.dart apps/mobile/test/machines/machine_list_screen_test.dart
git commit -m "feat(mobile): machine list screen with presence, last online and pairing badge"
```

---

### Task 18: App shell — login, update gate, routing, providers, `main()`; full verification

**Files:**
- Create: `apps/mobile/lib/account/login_screen.dart`, `apps/mobile/lib/app/update_required_screen.dart`, `apps/mobile/lib/app/providers.dart`, `apps/mobile/lib/app/phase_router.dart`, `apps/mobile/lib/app/shellx_app.dart`
- Modify: `apps/mobile/lib/main.dart` (replace the Task 1 bootstrap)
- Test: `apps/mobile/test/account/login_screen_test.dart`, `apps/mobile/test/app/shellx_app_test.dart`

**Interfaces:**
- Consumes: everything above — `AppController` (incl. `onBackground`/`onForeground`), `AppPhase` subclasses, `AccountStore` (Task 5); `AppLockController`, `LockGate`, `LocalAuthBiometricAuthenticator` (Task 6); `AppSettings`, `SecureKeyValueStore`, `wipeSecureStorageOnFreshInstall`, `describeThisDevice`, `AppConfig` (Task 2); `ClientBackend.start` (Task 4); `MachineListScreen` (Task 17); `TerminalScreen` (Task 13); `QrScannerScreen` (Task 14); `SettingsScreen` (Task 15); `WorkspaceRegistry` (Task 12); `ShellxApi`, `DeviceIdentity.loadOrCreate` (`shellx_core`); `PackageInfo.fromPlatform`; `launchUrl`.
- Produces:
  - `class LoginScreen extends StatefulWidget { const LoginScreen({Key? key, required Future<void> Function(String email, String password) onLogin, required Future<void> Function(String email, String password) onRegister, String? initialEmail, bool revoked = false, bool accountDeleted = false}); }`
  - `class UpdateRequiredScreen extends StatelessWidget { const UpdateRequiredScreen({Key? key, required String minVersion, required VoidCallback onDownload}); }`
  - `final appControllerProvider`, `appSettingsProvider`, `appLockProvider`, `biometricsProvider` (`Provider<…>` overridden in `main()` and tests)
  - `class PhaseRouter extends StatefulWidget { const PhaseRouter({Key? key, required AppController controller, required AppSettings settings, required AppLockController lock, required BiometricAuthenticator biometrics, required Future<bool> Function(Uri url) openUrl}); }` — pops every pushed route when the phase (or the signed-in backend) changes.
  - `class ShellxApp extends ConsumerWidget { const ShellxApp({Key? key, Future<bool> Function(Uri url) openUrl = openExternalUrl}); }`, `Future<bool> openExternalUrl(Uri url)`
  - `Future<void> main()` — composition root.

- [ ] **Step 1: Write the failing tests**

`apps/mobile/test/account/login_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/account/login_screen.dart';

import '../support/app_harness.dart';

void main() {
  late List<(String, String, String)> calls;
  Object? failure;

  setUp(() {
    calls = [];
    failure = null;
  });

  Future<void> call(String kind, String email, String password) async {
    calls.add((kind, email, password));
    final error = failure;
    if (error != null) throw error;
  }

  Future<void> pumpLogin(WidgetTester tester, {bool revoked = false, bool deleted = false, String? email}) =>
      tester.pumpWidget(localized(LoginScreen(
        initialEmail: email,
        revoked: revoked,
        accountDeleted: deleted,
        onLogin: (e, p) => call('login', e, p),
        onRegister: (e, p) => call('register', e, p),
      )));

  Future<void> fill(WidgetTester tester, String email, String password) async {
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), password);
  }

  testWidgets('signs in with a trimmed email', (tester) async {
    await pumpLogin(tester, email: 'old@example.com');
    expect(find.text('old@example.com'), findsOneWidget);
    await fill(tester, '  me@example.com ', 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(calls, [('login', 'me@example.com', 'secret')]);
  });

  testWidgets('shows invalid_credentials and 429 with the spec texts', (tester) async {
    await pumpLogin(tester);
    await fill(tester, 'me@example.com', 'wrong');
    failure = const ApiException(status: 401, code: 'invalid_credentials', message: 'x');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Email hoặc mật khẩu không đúng.'), findsOneWidget);

    failure = const ApiException(status: 429, code: 'rate_limited', message: 'x');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Thử lại sau ít phút.'), findsOneWidget);
  });

  testWidgets('register checks the 8–128 password length locally', (tester) async {
    await pumpLogin(tester);
    await tester.tap(find.text('Chưa có tài khoản? Đăng ký'));
    await tester.pump();
    await fill(tester, 'me@example.com', 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Tạo tài khoản'));
    await tester.pump();
    expect(find.text('Mật khẩu phải có 8–128 ký tự.'), findsOneWidget);
    expect(calls, isEmpty);

    await fill(tester, 'me@example.com', 'long enough');
    await tester.tap(find.widgetWithText(FilledButton, 'Tạo tài khoản'));
    await tester.pumpAndSettle();
    expect(calls, [('register', 'me@example.com', 'long enough')]);
  });

  testWidgets('rejects an obviously invalid email without calling the relay', (tester) async {
    await pumpLogin(tester);
    await fill(tester, 'not-an-email', 'whatever');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pump();
    expect(find.text('Email không hợp lệ.'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('explains a revoked session and a deleted account', (tester) async {
    await pumpLogin(tester, revoked: true);
    expect(find.text('Phiên đăng nhập đã bị thu hồi. Hãy đăng nhập lại.'), findsOneWidget);
    await pumpLogin(tester, deleted: true);
    expect(find.text('Tài khoản đã được xóa.'), findsOneWidget);
  });
}
```

`apps/mobile/test/app/shellx_app_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/account/account_store.dart';
import 'package:shellx_mobile/account/app_controller.dart';
import 'package:shellx_mobile/app/providers.dart';
import 'package:shellx_mobile/app/shellx_app.dart';
import 'package:shellx_mobile/lock/app_lock_controller.dart';
import 'package:shellx_mobile/platform/device_description.dart';
import 'package:shellx_mobile/settings/app_settings.dart';

import '../support/fake_relay_http.dart';
import '../support/fakes.dart';

void main() {
  late FakeRelayHttp relay;
  late InMemoryKeyValueStore store;
  late AppController controller;
  late AppSettings settings;
  late FakeBiometricAuthenticator biometrics;
  late AppLockController lock;
  late List<FakeBackend> backends;
  late List<Uri> opened;

  setUp(() async {
    relay = FakeRelayHttp();
    store = InMemoryKeyValueStore();
    backends = [];
    opened = [];
    final identity = await NoiseKeyPair.generate();
    controller = AppController(
      api: ShellxApi(baseUri: Uri.parse('http://127.0.0.1:8787'), httpClient: relay.client),
      accounts: AccountStore(store),
      loadIdentity: () async => identity,
      device: const DeviceDescription(name: 'Pixel 8', platform: DevicePlatform.android),
      appVersion: '1.0.0',
      backendFactory: (session, identity) async {
        final backend = FakeBackend(devices: [agentDevice(agentA, 'MacBook-Pro')], pinnedList: [pinned(agentA)])
          ..onlineIds.add(agentA)
          ..addMachine(agentA);
        backends.add(backend);
        return backend;
      },
    );
    settings = AppSettings(store);
    await settings.load();
    biometrics = FakeBiometricAuthenticator();
    lock = AppLockController(authenticator: biometrics, isEnabled: () => settings.biometricLock);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appControllerProvider.overrideWithValue(controller),
        appSettingsProvider.overrideWithValue(settings),
        appLockProvider.overrideWithValue(lock),
        biometricsProvider.overrideWithValue(biometrics),
      ],
      child: ShellxApp(openUrl: (url) async {
        opened.add(url);
        return true;
      }),
    ));
    await controller.start();
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'me@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'correct horse');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  testWidgets('an outdated app is blocked with a download link', (tester) async {
    relay.minMobile = '2.0.0';
    await pumpApp(tester);
    expect(find.text('App update required'), findsOneWidget);
    await tester.tap(find.text('Get the update'));
    expect(opened, [Uri.parse('https://shellx.pro/')]);
  });

  testWidgets('sign in → machine list → settings → sign out returns to login', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    expect(find.text('Computers'), findsOneWidget);
    expect(find.text('MacBook-Pro'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(backends.single.disposed, isTrue);
  });

  testWidgets('a revoked token while a terminal is open goes back to login (spec §12)', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('MacBook-Pro'));
    await tester.pumpAndSettle();
    expect(find.text('zsh 1'), findsOneWidget);

    backends.single.emitRelay(RelayConnectionState.revoked);
    await tester.pumpAndSettle();
    expect(find.text('Your sign-in was revoked. Please sign in again.'), findsOneWidget);
    expect(find.text('zsh 1'), findsNothing);
  });

  testWidgets('delete account from settings ends on the login screen', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'correct horse');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete permanently'));
    await tester.pumpAndSettle();

    expect(find.text('Your account has been deleted.'), findsOneWidget);
    expect(await store.read(AccountStore.tokenKey), isNull);
    expect(await store.read(DeviceIdentity.storageKey), isNull);
  });

  testWidgets('the lock screen covers the app on launch when enabled', (tester) async {
    biometrics.result = false;
    lock.lockOnLaunch();
    await pumpApp(tester);
    expect(find.text('ShellX is locked'), findsOneWidget);
    biometrics.result = true;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('ShellX is locked'), findsNothing);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/mobile && flutter test test/account/login_screen_test.dart test/app`
Expected: FAIL — `Error when reading 'lib/account/login_screen.dart': No such file or directory`, `Error when reading 'lib/app/providers.dart': No such file or directory`, `Error when reading 'lib/app/shellx_app.dart': No such file or directory`.

- [ ] **Step 3: Implement the screens and routing**

`apps/mobile/lib/account/login_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shellx_core/shellx_core.dart';

import '../errors/error_text.dart';
import '../l10n/app_localizations.dart';

/// Spec §9.2 #1: sign in / create account with email + password.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onLogin,
    required this.onRegister,
    this.initialEmail,
    this.revoked = false,
    this.accountDeleted = false,
  });

  /// Both throw [ApiException].
  final Future<void> Function(String email, String password) onLogin;
  final Future<void> Function(String email, String password) onRegister;
  final String? initialEmail;
  final bool revoked;
  final bool accountDeleted;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _email = TextEditingController(text: widget.initialEmail);
  final TextEditingController _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final email = _email.text.trim();
    final password = _password.text;
    // Quick local checks; the relay stays the authority (spec §5.2).
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = l10n.errorInvalidEmail);
      return;
    }
    if (_register && (password.length < 8 || password.length > 128)) {
      setState(() => _error = l10n.errorWeakPassword);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (_register ? widget.onRegister : widget.onLogin)(email, password);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = ErrorText(l10n).api(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notice = widget.accountDeleted
        ? l10n.signedOutAccountDeleted
        : widget.revoked
            ? l10n.signedOutRevoked
            : null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text(l10n.appTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: 8),
                Text(
                  _register ? l10n.registerTitle : l10n.loginTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (notice != null) ...[
                  const SizedBox(height: 16),
                  Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(notice))),
                ],
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(labelText: l10n.emailLabel, border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                  decoration: InputDecoration(labelText: l10n.passwordLabel, border: const OutlineInputBorder()),
                  onSubmitted: (_) => _busy ? null : _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_register ? l10n.registerButton : l10n.loginButton),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _register = !_register;
                            _error = null;
                          }),
                  child: Text(_register ? l10n.switchToLogin : l10n.switchToRegister),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

`apps/mobile/lib/app/update_required_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Spec §12/§14: blocks the app when it is older than `min_mobile`.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.minVersion, required this.onDownload});

  final String minVersion;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.system_update, size: 64),
                const SizedBox(height: 16),
                Text(l10n.updateRequiredTitle, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(l10n.updateRequiredBody(minVersion), textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(onPressed: onDownload, child: Text(l10n.updateRequiredButton)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

`apps/mobile/lib/app/providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/app_controller.dart';
import '../lock/app_lock_controller.dart';
import '../lock/biometric_authenticator.dart';
import '../settings/app_settings.dart';

// App-wide singletons, built in main() and injected with ProviderScope
// overrides (tests override them with fakes the same way).

final appControllerProvider =
    Provider<AppController>((ref) => throw UnimplementedError('Overridden in main()'));

final appSettingsProvider = Provider<AppSettings>((ref) => throw UnimplementedError('Overridden in main()'));

final appLockProvider = Provider<AppLockController>((ref) => throw UnimplementedError('Overridden in main()'));

final biometricsProvider =
    Provider<BiometricAuthenticator>((ref) => throw UnimplementedError('Overridden in main()'));
```

`apps/mobile/lib/app/phase_router.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../account/app_controller.dart';
import '../account/login_screen.dart';
import '../lock/app_lock_controller.dart';
import '../lock/biometric_authenticator.dart';
import '../machines/machine_list_screen.dart';
import '../pairing/qr_scanner_screen.dart';
import '../settings/app_settings.dart';
import '../settings/settings_screen.dart';
import '../terminal/terminal_screen.dart';
import '../terminal/terminal_workspace.dart';
import 'config.dart';
import 'update_required_screen.dart';

/// Home route: shows the screen for the current [AppPhase] and clears every
/// pushed route whenever the phase (or the signed-in backend) changes, e.g.
/// logout from Settings or a 4002 while a terminal is open.
class PhaseRouter extends StatefulWidget {
  const PhaseRouter({
    super.key,
    required this.controller,
    required this.settings,
    required this.lock,
    required this.biometrics,
    required this.openUrl,
  });

  final AppController controller;
  final AppSettings settings;
  final AppLockController lock;
  final BiometricAuthenticator biometrics;
  final Future<bool> Function(Uri url) openUrl;

  @override
  State<PhaseRouter> createState() => _PhaseRouterState();
}

class _PhaseRouterState extends State<PhaseRouter> {
  late AppPhase _phase = widget.controller.phase;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPhase);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPhase);
    super.dispose();
  }

  Object _identity(AppPhase phase) => phase is AppSignedIn ? phase.backend : phase.runtimeType;

  void _onPhase() {
    final next = widget.controller.phase;
    if (_identity(next) != _identity(_phase)) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    setState(() => _phase = next);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return switch (_phase) {
      AppStarting() => const Scaffold(body: Center(child: CircularProgressIndicator())),
      AppUpdateRequired(:final minVersion) => UpdateRequiredScreen(
          minVersion: minVersion,
          onDownload: () => widget.openUrl(AppConfig.downloadPage),
        ),
      AppSignedOut(:final lastEmail, :final revoked, :final accountDeleted) => LoginScreen(
          key: ObjectKey(_phase),
          initialEmail: lastEmail,
          revoked: revoked,
          accountDeleted: accountDeleted,
          onLogin: controller.login,
          onRegister: controller.register,
        ),
      final AppSignedIn signedIn => _SignedInHome(
          key: ObjectKey(signedIn.backend),
          phase: signedIn,
          controller: controller,
          settings: widget.settings,
          lock: widget.lock,
          biometrics: widget.biometrics,
        ),
    };
  }
}

class _SignedInHome extends StatefulWidget {
  const _SignedInHome({
    super.key,
    required this.phase,
    required this.controller,
    required this.settings,
    required this.lock,
    required this.biometrics,
  });

  final AppSignedIn phase;
  final AppController controller;
  final AppSettings settings;
  final AppLockController lock;
  final BiometricAuthenticator biometrics;

  @override
  State<_SignedInHome> createState() => _SignedInHomeState();
}

class _SignedInHomeState extends State<_SignedInHome> {
  late final WorkspaceRegistry _registry = WorkspaceRegistry(widget.phase.backend);

  @override
  void dispose() {
    _registry.dispose();
    super.dispose();
  }

  Future<void> _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  void _reconnectReplaced() => unawaited(widget.controller.reconnectReplaced());

  @override
  Widget build(BuildContext context) {
    final backend = widget.phase.backend;
    return MachineListScreen(
      backend: backend,
      onReconnectReplaced: _reconnectReplaced,
      onOpenMachine: (machine) => _push(TerminalScreen(
        backend: backend,
        registry: _registry,
        agentId: machine.id,
        machineName: machine.name,
        initialFontSize: widget.settings.fontSize,
        onReconnectReplaced: _reconnectReplaced,
      )),
      onScan: (_) => _push(QrScannerScreen(backend: backend)),
      onOpenSettings: () => _push(SettingsScreen(
        settings: widget.settings,
        lock: widget.lock,
        biometrics: widget.biometrics,
        backend: backend,
        email: widget.phase.session.email,
        appVersion: widget.controller.appVersion,
        onUnpaired: _registry.remove,
        onLogout: widget.controller.logout,
        onDeleteAccount: widget.controller.deleteAccount,
      )),
    );
  }
}
```

`apps/mobile/lib/app/shellx_app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../lock/lock_gate.dart';
import 'phase_router.dart';
import 'providers.dart';

Future<bool> openExternalUrl(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

class ShellxApp extends ConsumerWidget {
  const ShellxApp({super.key, this.openUrl = openExternalUrl});

  final Future<bool> Function(Uri url) openUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final lock = ref.watch(appLockProvider);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => LockGate(
        lock: lock,
        onBackground: controller.onBackground,
        onForeground: controller.onForeground,
        child: child!,
      ),
      home: PhaseRouter(
        controller: controller,
        settings: ref.watch(appSettingsProvider),
        lock: lock,
        biometrics: ref.watch(biometricsProvider),
        openUrl: openUrl,
      ),
    );
  }
}
```

- [ ] **Step 4: Replace `main.dart` with the composition root**

`apps/mobile/lib/main.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shellx_core/shellx_core.dart';

import 'account/account_store.dart';
import 'account/app_controller.dart';
import 'app/config.dart';
import 'app/providers.dart';
import 'app/shellx_app.dart';
import 'backend/client_backend.dart';
import 'lock/app_lock_controller.dart';
import 'lock/biometric_authenticator.dart';
import 'platform/device_description.dart';
import 'platform/fresh_install.dart';
import 'platform/secure_key_value_store.dart';
import 'settings/app_settings.dart';

// No cryptography_flutter (coordinator ruling): shellx_core pins the pure-Dart
// X25519 / ChaCha20-Poly1305 / BLAKE2s backends that pass the Noise vectors.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['JetBrains Mono'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });

  final store = SecureKeyValueStore();
  await wipeSecureStorageOnFreshInstall(prefs: await SharedPreferences.getInstance(), wipe: store.deleteAll);
  final settings = AppSettings(store);
  await settings.load();
  final appVersion = (await PackageInfo.fromPlatform()).version;
  final device = await describeThisDevice();
  final api = ShellxApi(baseUri: AppConfig.relayBaseUri);
  final biometrics = LocalAuthBiometricAuthenticator();

  final controller = AppController(
    api: api,
    accounts: AccountStore(store),
    loadIdentity: () => DeviceIdentity.loadOrCreate(store),
    device: device,
    appVersion: appVersion,
    backendFactory: (session, identity) => ClientBackend.start(
      relayBaseUri: AppConfig.relayBaseUri,
      api: api,
      userId: session.userId,
      deviceId: session.deviceId,
      identity: identity,
      store: store,
      appVersion: appVersion,
      device: device,
    ),
  );
  // Spec §5.6: locked when the app opens (if enabled).
  final lock = AppLockController(authenticator: biometrics, isEnabled: () => settings.biometricLock)
    ..lockOnLaunch();

  runApp(ProviderScope(
    overrides: [
      appControllerProvider.overrideWithValue(controller),
      appSettingsProvider.overrideWithValue(settings),
      appLockProvider.overrideWithValue(lock),
      biometricsProvider.overrideWithValue(biometrics),
    ],
    child: const ShellxApp(),
  ));
  unawaited(controller.start());
}
```

- [ ] **Step 5: Run the new tests**

Run: `cd apps/mobile && flutter test test/account test/app`
Expected: PASS — `All tests passed!` (26 tests).

- [ ] **Step 6: Run the whole suite, the analyzer and both platform builds**

```bash
cd apps/mobile
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator --debug   # macOS with Xcode only
```

Expected: `No issues found!`; `All tests passed!` (164 tests); `✓ Built build/app/outputs/flutter-apk/app-debug.apk`; `✓ Built build/ios/iphonesimulator/Runner.app`. Optional spot checks of the built artefacts:

```bash
grep -oE 'package="[^"]+"|minSdkVersion="26"' "$(find build/app/intermediates -name AndroidManifest.xml -path '*merged_manifest*' | head -1)" | sort -u
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" -c "Print :MinimumOSVersion" build/ios/iphonesimulator/Runner.app/Info.plist
```

Expected: `package="pro.shellx.mobile"`, `minSdkVersion="26"`; `pro.shellx.mobile`, `15.0`.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/account/login_screen.dart apps/mobile/lib/app apps/mobile/lib/main.dart \
  apps/mobile/test/account/login_screen_test.dart apps/mobile/test/app
git commit -m "feat(mobile): app shell with login, update gate, lock gate, routing and composition root"
```

---

## Manual verification on real devices (after Task 18)

These cannot be exercised by `flutter test`. Run the app against staging (`flutter run --release --dart-define=SHELLX_RELAY=https://relay-staging.shellx.pro`) with a desktop agent (plan 04) signed in to the same account, on at least one iPhone (iOS 15+) and one Android 8.0 (API 26) device or emulator plus a current Android phone.

1. **Biometric lock:** Face ID / fingerprint prompt on cold start; passcode fallback works; background 4 min → no prompt, 6 min → prompt; Android 8.0 BiometricPrompt shows without crashing (AppCompat theme + `FlutterFragmentActivity`); switch disabled on a device without passcode.
2. **Camera and pairing:** permission prompt text; scanning the desktop QR pairs in < 3 s; denying the permission shows the settings hint; scanning a QR from another account shows "Máy này không thuộc tài khoản của bạn…"; an expired code shows "Mã QR không hợp lệ hoặc đã hết hạn…".
3. **Soft keyboards:** iOS keyboard and Gboard/Samsung keyboard: letters, Vietnamese Telex/VNI composition, Backspace (`deleteDetection`), Return (CR); `Ctrl` then `c` interrupts `sleep 100`; double-tap `Ctrl` and type `a`, `e`; `Alt` then `b` moves a word back in bash.
4. **Full-screen programs:** `vim`, `htop`, `less`: arrows, Home/End, PgUp/PgDn, Esc, `Ctrl+Alt+←`; box-drawing characters render in JetBrains Mono; emoji fall back.
5. **Hardware keyboard:** iPad + Magic Keyboard and an Android phone + Bluetooth keyboard: arrows, `Ctrl+A` reaches tmux, `Ctrl+V` reaches vim, ⌘C/⌘V (iOS) and Ctrl+Shift+C/V (Android) copy/paste.
6. **Copy/paste:** long-press selects a word, dragging extends, "Sao chép" copies; pasting three lines into zsh with bracketed paste does not execute them; into `cat` they arrive as separate lines.
7. **Size:** pinch zoom changes the font size smoothly; rotating and showing/hiding the keyboard updates `stty size` on the computer; no `resize 0x…` in agent logs.
8. **Background/foreground:** open two tabs, run `yes | head -c 300000 | tail -c 20; sleep 30; echo done`, background the app for 1 min (the app suspends the relay; the agent shows the channel dropped), return: "Mất kết nối, đang thử lại…" appears briefly, tabs re-attach and show `done`; open the same machine on a second phone → first phone shows "Phiên đang được mở trên thiết bị khác." and "Gắn lại" takes it back.
9. **Pure-Dart crypto performance (ruling):** on the oldest supported devices (an iOS 15 iPhone, an Android 8.0 phone) measure IK handshake time and keystroke echo latency in a release build; spec §1 target is < 150 ms median keystroke latency.
10. **Reinstall:** delete and reinstall on iOS → new device key → the machine shows "Chưa ghép nối" and must be paired again (spec §5.1).
11. **Account:** sign out → sign in again with the same account keeps pairings; another account on the same phone sees none; delete account from Settings (wrong password shows "Mật khẩu không đúng.", right password returns to login with "Tài khoản đã được xóa.", the desktop agent is signed out).
12. **Update gate:** raise `MIN_MOBILE` on staging above the app version → "Cần cập nhật app" blocks the app and "Tải bản mới" opens `https://shellx.pro/`.
